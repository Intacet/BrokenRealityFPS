--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > GunService
--
-- Validates weapon shots fired by clients.
-- Clients fire WeaponFired with origin+direction+tick; GunService re-runs the
-- raycast on the server, then routes its single validated result:
--   - a player character            →  DamageService:ApplyDamage() (with body-part region)
--   - a tagged Humanoid entity       →  DamageService:ApplyDamage() (test dummy / future NPC)
--   - a registered breakable prop    →  DestructionService:ApplyHit()
--   - anything else                  →  ignored
--
-- What this script does NOT do:
--   - Apply damage, track health, or map body parts  →  DamageService / DamageRules
--   - Track breakable prop health or debris           →  DestructionService
--   - Own or spawn test dummies                       →  DummyService
--   - Handle client input                             →  GunController (client)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))
local Logger     = require(Modules:WaitForChild("Logger"))

-- DamageService, DestructionService, and MatchEvents are sibling ModuleScripts in Services.
local DamageService      = require(script.Parent:WaitForChild("DamageService"))
local DestructionService = require(script.Parent:WaitForChild("DestructionService"))
local MatchEvents        = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local WeaponFired    = Remotes:WaitForChild("WeaponFired")    :: RemoteEvent
local HitConfirmed   = Remotes:WaitForChild("HitConfirmed")   :: RemoteEvent
local AmmoChanged    = Remotes:WaitForChild("AmmoChanged")    :: RemoteEvent
local ReloadRequest  = Remotes:WaitForChild("ReloadRequest")  :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

-- Active weapon identity is Constants.DEFAULT_WEAPON (src/shared/Constants.lua).
-- GunService uses Constants.DEFAULT_WEAPON as the authoritative weapon name for all
-- server-side validation, ammo setup, and AmmoChanged broadcasts.
-- GunController also reads Constants.DEFAULT_WEAPON for client-side prediction,
-- dry-fire checks, range for the cosmetic raycast, and local rate limiting.
-- Renaming the default weapon requires changing Constants.DEFAULT_WEAPON only.
-- WeaponFired and ReloadRequest carry no weapon name by design — see DEBT-013.

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

-- Walks up from `part` to the first ancestor Model that both contains a Humanoid and
-- carries the Constants.TAG_DAMAGE_ENTITY CollectionService tag. That tag is the generic
-- opt-in for "a non-player thing GunService is allowed to damage through the shared
-- pipeline" — DummyService adds it to every test dummy; future NPC spawners would do the
-- same. Returns nil for untagged models, props, and terrain, so the caller can fall
-- through to DestructionService.
local function getDamageableEntity(part: Instance): Model?
    local node: Instance? = part
    while node ~= nil and node ~= workspace do
        if node:IsA("Model")
            and CollectionService:HasTag(node, Constants.TAG_DAMAGE_ENTITY)
            and node:FindFirstChildOfClass("Humanoid") ~= nil
        then
            return node
        end
        node = node.Parent
    end
    return nil
end

-- Initialises a player's ammo from WeaponData and fires AmmoChanged so their HUD
-- shows the correct values immediately. Called on TeamAssigned (PREP phase).
local function setupAmmo(player: Player)
    local weaponDef = WeaponData[Constants.DEFAULT_WEAPON]
    if not weaponDef then
        Logger.warn("[GunService] setupAmmo: no WeaponData for", Constants.DEFAULT_WEAPON)
        return
    end
    playerMag[player]     = weaponDef.magazineSize
    playerReserve[player] = weaponDef.reserveAmmo
    AmmoChanged:FireClient(player, Constants.DEFAULT_WEAPON, playerMag[player], playerReserve[player])
    Logger.debug("[GunService] Ammo set for", player.Name,
        "| mag:", playerMag[player], "reserve:", playerReserve[player])
end

-- Returns the HumanoidRootPart world position for the player's character,
-- or nil if the character or root part is not present.
local function getShooterRootPosition(player: Player): Vector3?
    assert(player ~= nil, "[GunService] getShooterRootPosition: player is required")
    local character = player.Character
    if not character then
        return nil
    end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return nil
    end
    return (rootPart :: BasePart).Position
end

-- Validates the client-supplied origin and direction from a WeaponFired event.
-- Checks: Vector3 types, direction magnitude, origin distance from shooter root.
-- Returns (true, validatedOrigin, normalizedDirection) on success.
-- Returns (false, nil, nil) on any failure — caller must return without raycasting.
local function isValidShotPayload(
    shooter: Player,
    origin: any,
    direction: any
): (boolean, Vector3?, Vector3?)
    assert(shooter ~= nil, "[GunService] isValidShotPayload: shooter is required")

    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
        Logger.warn("[GunService] WeaponFired: invalid payload types from", shooter.Name)
        return false, nil, nil
    end

    -- Block zero and near-zero directions before normalization to avoid NaN/inf.
    if direction.Magnitude < Constants.SHOT_DIRECTION_MIN_MAGNITUDE then
        Logger.warn("[GunService] WeaponFired: near-zero direction from", shooter.Name)
        return false, nil, nil
    end

    -- Reject origins far from the shooter's HumanoidRootPart.
    -- This catches teleport-origin exploits without affecting legitimate shots —
    -- the camera is typically 2–4 studs from the root; 12 is a generous ceiling.
    local rootPosition = getShooterRootPosition(shooter)
    if rootPosition == nil then
        return false, nil, nil  -- no character on server; shot cannot be valid
    end

    if (origin - rootPosition).Magnitude > Constants.SHOT_ORIGIN_MAX_DISTANCE then
        Logger.warn("[GunService] WeaponFired: origin too far from root for", shooter.Name)
        return false, nil, nil
    end

    return true, origin, direction.Unit
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

    -- ── Payload validation ────────────────────────────────────────────────────
    -- Validates types, direction magnitude, and origin proximity to the shooter's
    -- root position. Returns a normalized direction on success.
    -- Malformed or suspicious payloads are logged inside isValidShotPayload.
    local valid, validOrigin, validDirection = isValidShotPayload(shooter, origin, direction)
    if not valid or validOrigin == nil or validDirection == nil then
        return
    end

    -- ── Weapon lookup ────────────────────────────────────────────────────────
    local weaponDef = WeaponData[Constants.DEFAULT_WEAPON]
    if not weaponDef then
        Logger.warn("[GunService] No WeaponData entry for:", Constants.DEFAULT_WEAPON)
        return
    end

    -- ── Rate limit ───────────────────────────────────────────────────────────
    -- Reject shots fired faster than the weapon's configured rate allows.
    -- Derives effectiveFireRate from weaponDef.rpm when present (future-proof for when
    -- DEBT-013 is resolved and GunService reads the correct per-weapon definition).
    -- Currently weaponDef = WeaponData[Constants.DEFAULT_WEAPON] = AR15 (no rpm field),
    -- so effectiveFireRate = weaponDef.fireRate = 0.09 s — unchanged from before.
    -- os.clock() is server-local and monotonic — not affected by client timing.
    local now      = os.clock()
    local lastShot = lastShotTime[shooter] or 0
    local effectiveFireRate: number
    local defAny = weaponDef :: any
    if typeof(defAny.rpm) == "number" and defAny.rpm > 0 then
        effectiveFireRate = 60 / defAny.rpm
    else
        effectiveFireRate = weaponDef.fireRate
    end
    if now - lastShot < effectiveFireRate then
        Logger.debug("[GunService] Rate limit: shot rejected for " .. shooter.Name)
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
        AmmoChanged:FireClient(shooter, Constants.DEFAULT_WEAPON, 0, playerReserve[shooter] or 0)
        return
    end

    -- Consume one round before the raycast so exploiters cannot fire ahead of
    -- the decrement and overflow back to a positive value.
    playerMag[shooter] = mag - 1
    AmmoChanged:FireClient(shooter, Constants.DEFAULT_WEAPON, playerMag[shooter], playerReserve[shooter] or 0)

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
        validOrigin,
        validDirection * weaponDef.range,  -- validDirection is already normalized
        params
    )

    if not result then
        return  -- missed or exceeded weapon range
    end

    -- ── Hit routing ─────────────────────────────────────────────────────────
    -- One validated raycast result → exactly one consumer. GunService never mutates
    -- health or prop state and never fires HealthChanged itself.
    local hitPart = result.Instance
    local victim  = getPlayerFromPart(hitPart)

    if victim ~= nil and victim ~= shooter then
        -- Player hit. The shared pipeline now carries the hit part too, so headshot
        -- multipliers (Constants.DAMAGE_REGION_MULTIPLIERS) apply to PvP as well.
        -- Friendly fire is enforced inside DamageService, not here — see DEBT-009.
        DamageService:ApplyDamage({
            targetPlayer = victim,
            targetModel  = victim.Character,
            attacker     = shooter,
            sourceName   = Constants.DEFAULT_WEAPON,
            damageType   = Constants.DamageType.Bullet,
            hitPart      = hitPart :: BasePart,
            hitPosition  = result.Position,
            hitDirection = validDirection,
            baseAmount   = weaponDef.damage,
        })

        -- Cosmetic hitmarker for the shooter — carries no health or kill information.
        HitConfirmed:FireClient(shooter)

        Logger.debug(string.format(
            "[GunService] %s hit %s (%s) for %d base dmg",
            shooter.Name, victim.Name, hitPart.Name, weaponDef.damage
        ))
        return
    end

    if victim == nil then
        -- Not a player. A tagged Humanoid entity (test dummy / future NPC) is damaged
        -- through the same pipeline; otherwise fall back to a breakable prop. Both calls
        -- no-op harmlessly for anything they do not own.
        local entity = getDamageableEntity(hitPart)
        if entity ~= nil then
            DamageService:ApplyDamage({
                targetModel  = entity,
                attacker     = shooter,
                sourceName   = Constants.DEFAULT_WEAPON,
                damageType   = Constants.DamageType.Bullet,
                hitPart      = hitPart :: BasePart,
                hitPosition  = result.Position,
                hitDirection = validDirection,
                baseAmount   = weaponDef.damage,
            })
            HitConfirmed:FireClient(shooter)
            Logger.debug(string.format(
                "[GunService] %s hit entity %s (%s) for %d base dmg",
                shooter.Name, entity.Name, hitPart.Name, weaponDef.damage
            ))
            return
        end

        DestructionService:ApplyHit(hitPart, weaponDef.damage, result.Position, validDirection)
    end
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

    local weaponDef = WeaponData[Constants.DEFAULT_WEAPON]
    if not weaponDef then
        Logger.warn("[GunService] ReloadRequest: no WeaponData for", Constants.DEFAULT_WEAPON)
        return
    end

    if reserve <= 0 or mag >= weaponDef.magazineSize then
        -- Nothing to reload: no reserve left, or magazine already full.
        -- Fire AmmoChanged so the client HUD stays accurate.
        AmmoChanged:FireClient(player, Constants.DEFAULT_WEAPON, mag, reserve)
        return
    end

    -- Discard the current magazine entirely and pull a full new one from reserve.
    -- Example: 15 rounds in magazine, 70 in reserve → 30 in magazine, 40 in reserve.
    -- The 15 remaining rounds are permanently discarded.
    local pulled = math.min(weaponDef.magazineSize, reserve)
    playerMag[player]     = pulled
    playerReserve[player] = reserve - pulled
    AmmoChanged:FireClient(player, Constants.DEFAULT_WEAPON, playerMag[player], playerReserve[player])

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
