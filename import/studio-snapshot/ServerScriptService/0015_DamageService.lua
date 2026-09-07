--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > DamageService
--
-- Owns all server-side health tracking.
-- Clients never modify health directly — they fire a remote; DamageService validates
-- and applies the change, then fires HealthChanged back to the affected client.
--
-- What this script does NOT do:
--   - Convert the character to a ragdoll  →  RagdollService (called from killPlayer)
--   - Remove ragdoll corpses  →  CorpseService (future)
--   - Award kills, streaks, or XP  →  RewardService (future)
--   - Validate line-of-sight or range  →  will move here from GunService when built

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

local MatchEvents     = require(script.Parent:WaitForChild("MatchEvents"))
local RagdollService  = require(script.Parent:WaitForChild("RagdollService"))

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local HealthChanged = Remotes:WaitForChild("HealthChanged") :: RemoteEvent
local KillFeed      = Remotes:WaitForChild("KillFeed")      :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

-- Server-authoritative health table. Never trust a client-supplied health value.
-- Keyed by Player; set to MAX_HEALTH on assignment and cleared on disconnect/reset.
local playerHealth: { [Player]: number } = {}

-- Team memberships received from TeamService via MatchEvents.TeamAssigned.
-- Used by getTeamName() for the friendly-fire guard in Apply(); also queried by GetTeam().
local playerTeam: { [Player]: string } = {}

-- ============================================================
-- Private helpers
-- ============================================================

local function setHealth(player: Player, hp: number)
    local clamped = math.clamp(hp, 0, Constants.MAX_HEALTH)
    playerHealth[player] = clamped
    HealthChanged:FireClient(player, clamped, Constants.MAX_HEALTH)
end

local function resetHealth(player: Player)
    setHealth(player, Constants.MAX_HEALTH)
    Logger.debug("[DamageService] Reset health for", player.Name)
end

-- Kills the player: fires HealthChanged(0) to the client, then hands the character
-- to RagdollService which converts Motor6Ds to physics joints and fires Humanoid.Health=0.
-- RagdollService fires Humanoid.Died (TeamService alive tracking) and RagdollApplied
-- (client death screen). The character is NOT destroyed — it stays as a ragdoll.
-- Also fires KillFeed to all clients so the kill feed UI can display the kill.
local function killPlayer(player: Player, attacker: Player?)
    playerHealth[player] = 0
    HealthChanged:FireClient(player, 0, Constants.MAX_HEALTH)

    local character = player.Character
    if character then
        RagdollService:Apply(character, player, attacker)
    else
        Logger.warn("[DamageService] killPlayer: no character for", player.Name,
            "— ragdoll skipped; Humanoid.Died will not fire via this path")
    end

    -- Broadcast kill to all clients for the kill feed.
    -- killerTeam may be nil if attacker joined between phases and missed TeamAssigned.
    local killerDisplayName = attacker and attacker.DisplayName or ""
    local victimDisplayName = player.DisplayName
    local killerTeamName    = (attacker and playerTeam[attacker]) or ""
    local victimTeamName    = playerTeam[player] or ""
    KillFeed:FireAllClients(killerDisplayName, victimDisplayName, killerTeamName, victimTeamName)

    local attackerName = attacker and attacker.DisplayName or "environment"
    Logger.debug("[DamageService]", player.Name, "killed by", attackerName)
end

-- Returns the team name for a player, preferring the TeamAssigned cache over
-- the live Player.Team.Name lookup.  The cache is populated at PREP via
-- MatchEvents.TeamAssigned; players who joined after that window may have
-- Player.Team set by Roblox's team system even without a cache entry.
-- Returns nil if neither source has a team entry — callers must not assume
-- team membership when nil is returned.
local function getTeamName(player: Player): string?
    assert(player ~= nil, "[DamageService] getTeamName: player is required")
    local cached = playerTeam[player]
    if cached ~= nil then
        return cached
    end
    local team = player.Team
    if team ~= nil then
        return team.Name
    end
    return nil
end

-- ============================================================
-- Public API
-- ============================================================

local DamageService = {}

-- Apply `amount` points of damage to `victim`.
-- `attacker` is the Player responsible (nil for hazards, fall damage, etc.).
-- Always called from the server (GunService calls this once a shot is validated).
-- Never called directly from a client.
function DamageService:Apply(victim: Player, amount: number, attacker: Player?)
    if amount <= 0 then
        return  -- ignore zero-damage and healing calls routed here by mistake
    end

    -- Friendly-fire guard: block same-team damage when Constants.FRIENDLY_FIRE_ENABLED is false.
    -- getTeamName() checks the TeamAssigned cache first, then falls back to Player.Team.Name
    -- so late-joiners whose cache entry is missing are still protected.
    -- Skips for environment damage (attacker == nil) and when either team is truly unknown
    -- (nil return) — never blocks damage when team membership cannot be confirmed.
    if not Constants.FRIENDLY_FIRE_ENABLED and attacker ~= nil then
        local attackerTeam = getTeamName(attacker)
        local victimTeam   = getTeamName(victim)
        if attackerTeam ~= nil and victimTeam ~= nil and attackerTeam == victimTeam then
            Logger.debug("[DamageService] Blocked friendly fire:", attacker.Name, "→", victim.Name)
            return
        end
    end

    local current = playerHealth[victim]
    if current == nil then
        -- Player joined between phases; initialise to full health before applying damage.
        current = Constants.MAX_HEALTH
    end

    local newHp = current - amount

    if newHp <= 0 then
        killPlayer(victim, attacker)
    else
        setHealth(victim, newHp)
    end
end

-- Returns the player's current health, or MAX_HEALTH if they have no entry yet.
-- Used by GunService and ObjectiveService for conditional logic.
function DamageService:GetHealth(player: Player): number
    return playerHealth[player] or Constants.MAX_HEALTH
end

-- Returns the cached TeamAssigned team name for the player, or nil if not yet assigned.
-- External callers should prefer this over reading Player.Team.Name directly, as it
-- reflects the match-assigned team rather than any incidental Roblox team membership.
function DamageService:GetTeam(player: Player): string?
    return playerTeam[player]
end

-- ============================================================
-- Event listeners
-- ============================================================

-- Track team assignments so DamageService can enforce friendly-fire rules later.
MatchEvents.TeamAssigned.Event:Connect(function(player: Player, teamName: string)
    playerTeam[player] = teamName
    Logger.debug("[DamageService] Tracking team for", player.Name, "→", teamName)
end)

-- Reset every player's health to MAX_HEALTH at the start of each PREP phase
-- so the ACTIVE phase always begins with everyone at full health.
MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    if phase == Constants.Phase.PREP then
        for _, player in ipairs(Players:GetPlayers()) do
            resetHealth(player)
        end
        Logger.debug("[DamageService] Health reset for all players")
    end
end)

-- Clean up state when a player disconnects so tables don't hold stale references.
Players.PlayerRemoving:Connect(function(player: Player)
    playerHealth[player] = nil
    playerTeam[player]   = nil
end)

Logger.debug("[DamageService] Ready")

return DamageService
