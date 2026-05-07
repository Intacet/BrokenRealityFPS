--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > GunService
--
-- Validates weapon shots fired by clients.
-- Clients fire WeaponFired with origin+direction+tick; GunService re-runs the
-- raycast on the server and calls DamageService:Apply() only if the shot is valid.
--
-- What this script does NOT do:
--   - Apply damage or track health   →  DamageService
--   - Handle client input            →  GunController (client)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))
local Logger     = require(Modules:WaitForChild("Logger"))

-- DamageService and MatchEvents are sibling ModuleScripts in Services.
local DamageService = require(script.Parent:WaitForChild("DamageService"))
local MatchEvents   = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local WeaponFired    = Remotes:WaitForChild("WeaponFired")    :: RemoteEvent
local HitConfirmed   = Remotes:WaitForChild("HitConfirmed")   :: RemoteEvent
local AmmoChanged    = Remotes:WaitForChild("AmmoChanged")    :: RemoteEvent
local ReloadRequest  = Remotes:WaitForChild("ReloadRequest")  :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

-- GunController will include the weapon name in the WeaponFired payload once it is
-- built. Until then, every shot is attributed to this default weapon.
-- Must stay in sync with GunController's CURRENT_WEAPON — see DEBT-013.
local DEFAULT_WEAPON = "SCAR"

-- ============================================================
-- State
-- ============================================================

-- Mirrors the server's current phase so the WeaponFired handler can gate on ACTIVE
-- without polling MatchService. Updated by MatchEvents.PhaseChanged.
local currentPhase: string = Constants.Phase.LOBBY

-- Tracks the last accepted shot time per player for rate limiting.
-- Cleared on PlayerRemoving so disconnected players don't hold memory.
local lastShotTime: { [Player]: number } = {}

-- Server-authoritative ammo tables. Populated on TeamAssigned (PREP phase).
-- Cleared on PlayerRemoving. A nil entry means the player has not yet been
-- assigned ammo for this round (e.g. joined after the PREP window — see DEBT-026).
local playerMag:     { [Player]: number } = {}
local playerReserve: { [Player]: number } = {}

-- ============================================================
-- Private helpers
-- ============================================================

-- Walks the Players list to find who owns the character containing `part`.
-- Returns nil if the part is not inside any player's character (e.g. an NPC or prop).
local function getPlayerFromPart(part: Instance): Player?
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            return player
        end
    end
    return nil
end

-- Initialises a player's ammo from WeaponData and fires AmmoChanged so their HUD
-- shows the correct values immediately. Called on TeamAssigned (PREP phase).
local function setupAmmo(player: Player)
    local weaponDef = WeaponData[DEFAULT_WEAPON]
    if not weaponDef then
        Logger.warn("[GunService] setupAmmo: no WeaponData for", DEFAULT_WEAPON)
        return
    end
    playerMag[player]     = weaponDef.magazineSize
    playerReserve[player] = weaponDef.reserveAmmo
    AmmoChanged:FireClient(player, playerMag[player], playerReserve[player])
    Logger.debug("[GunService] Ammo set for", player.Name,
        "| mag:", playerMag[player], "reserve:", playerReserve[player])
end

-- ============================================================
-- Event listeners
-- ============================================================

-- Keep currentPhase up to date so the shot handler always has the latest phase.
MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    currentPhase = phase
end)

-- Reset ammo tables each time a player is assigned to a team (start of every PREP).
-- TeamService fires TeamAssigned once per player inside assignTeams(), which runs at
-- the start of PREP, so this fires before ACTIVE begins and before any WeaponFired
-- events can arrive.
MatchEvents.TeamAssigned.Event:Connect(function(player: Player, _teamName: string)
    setupAmmo(player)
end)

WeaponFired.OnServerEvent:Connect(function(
    shooter: Player,
    origin: any,
    direction: any,
    _clientTick: any  -- received but not yet validated; see DEBT-014
)
    -- ── Phase guard ──────────────────────────────────────────────────────────
    -- Shots are only valid during ACTIVE. Reject anything fired during LOBBY,
    -- PREP, or RESULTS (e.g. a client sending events at the wrong time).
    if currentPhase ~= Constants.Phase.ACTIVE then
        return
    end

    -- ── Type guard ───────────────────────────────────────────────────────────
    -- Reject payloads where an exploiter has replaced Vector3 values with
    -- non-Vector3 types. Log as warn because malformed payloads are unexpected
    -- and may indicate an exploiter probing the remote.
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
        Logger.warn("[GunService] WeaponFired: invalid payload types from", shooter.Name)
        return
    end

    -- ── Weapon lookup ────────────────────────────────────────────────────────
    local weaponDef = WeaponData[DEFAULT_WEAPON]
    if not weaponDef then
        Logger.warn("[GunService] No WeaponData entry for:", DEFAULT_WEAPON)
        return
    end

    -- ── Rate limit ───────────────────────────────────────────────────────────
    -- Reject shots fired faster than the weapon's fireRate allows.
    -- os.clock() is server-local and monotonic — not affected by client timing.
    local now      = os.clock()
    local lastShot = lastShotTime[shooter] or 0
    if now - lastShot < weaponDef.fireRate then
        return
    end
    lastShotTime[shooter] = now

    -- ── Ammo check ───────────────────────────────────────────────────────────
    -- Reject shots when the magazine is empty. nil means the player joined after
    -- the PREP TeamAssigned window and has never received ammo — see DEBT-026.
    local mag = playerMag[shooter]
    if mag == nil then
        return  -- no ammo record; player joined mid-round
    end
    if mag <= 0 then
        -- Magazine empty. Fire AmmoChanged so the client HUD stays in sync if it
        -- somehow drifted (e.g. a client-side prediction bug).
        AmmoChanged:FireClient(shooter, 0, playerReserve[shooter] or 0)
        return
    end

    -- Consume one round before the raycast so exploiters cannot fire ahead of
    -- the decrement and overflow back to a positive value.
    playerMag[shooter] = mag - 1
    AmmoChanged:FireClient(shooter, playerMag[shooter], playerReserve[shooter] or 0)

    -- ── Server raycast ───────────────────────────────────────────────────────
    -- Re-run the shot on the server. The client's claimed hit is ignored —
    -- only this result determines whether damage is applied.
    -- The shooter's own character is excluded so the ray doesn't self-hit
    -- (the origin may be inside the character's torso or arm).
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = shooter.Character
        and { shooter.Character } or {}

    local result = workspace:Raycast(
        origin,
        direction.Unit * weaponDef.range,
        params
    )

    if not result then
        return  -- missed or exceeded weapon range
    end

    -- ── Hit validation ───────────────────────────────────────────────────────
    -- Confirm the hit part belongs to a player character (not a wall or prop).
    local victim = getPlayerFromPart(result.Instance)
    if not victim or victim == shooter then
        return
    end

    -- ── Damage application ───────────────────────────────────────────────────
    -- DamageService owns all health mutation. GunService never modifies health
    -- directly and never reads or fires HealthChanged.
    -- NOTE: friendly-fire is not blocked here — see DEBT-009.
    DamageService:Apply(victim, weaponDef.damage, shooter)

    -- ── Hit confirmation ──────────────────────────────────────────────────────
    -- Tell the shooter's client to show a hitmarker. This is cosmetic only —
    -- the client cannot infer health values or kill state from this event.
    HitConfirmed:FireClient(shooter)

    Logger.debug(string.format(
        "[GunService] %s hit %s for %d dmg",
        shooter.Name, victim.Name, weaponDef.damage
    ))
end)

-- Handle magazine reload. The client fires this when the player presses R.
-- Validate phase and ammo state, transfer rounds from reserve to magazine,
-- and fire AmmoChanged with the updated values.
ReloadRequest.OnServerEvent:Connect(function(player: Player)
    if currentPhase ~= Constants.Phase.ACTIVE then
        return  -- reload only allowed during active play
    end

    local mag     = playerMag[player]
    local reserve = playerReserve[player]
    if mag == nil or reserve == nil then
        Logger.warn("[GunService] ReloadRequest from", player.Name, "with no ammo entry")
        return
    end

    local weaponDef = WeaponData[DEFAULT_WEAPON]
    if not weaponDef then
        Logger.warn("[GunService] ReloadRequest: no WeaponData for", DEFAULT_WEAPON)
        return
    end

    if reserve <= 0 or mag >= weaponDef.magazineSize then
        -- Nothing to reload: no reserve left, or magazine already full.
        -- Fire AmmoChanged so the client HUD stays accurate.
        AmmoChanged:FireClient(player, mag, reserve)
        return
    end

    -- Discard the current magazine entirely and pull a full new one from reserve.
    -- Example: 15 rounds in magazine, 70 in reserve → 30 in magazine, 40 in reserve.
    -- The 15 remaining rounds are permanently discarded.
    local pulled = math.min(weaponDef.magazineSize, reserve)
    playerMag[player]     = pulled
    playerReserve[player] = reserve - pulled
    AmmoChanged:FireClient(player, playerMag[player], playerReserve[player])

    Logger.debug(string.format(
        "[GunService] %s reloaded: %d→%d (reserve %d→%d)",
        player.Name, mag, playerMag[player], reserve, playerReserve[player]
    ))
end)

-- Clean up all per-player tables when a player leaves so they don't
-- accumulate references to disconnected Player instances.
Players.PlayerRemoving:Connect(function(player: Player)
    lastShotTime[player]  = nil
    playerMag[player]     = nil
    playerReserve[player] = nil
end)

Logger.debug("[GunService] Ready")
