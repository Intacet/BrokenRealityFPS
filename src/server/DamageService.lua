--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > DamageService
--
-- Owns all server-side health tracking.
-- Clients never modify health directly — they fire a remote; DamageService validates
-- and applies the change, then fires HealthChanged back to the affected client.
--
-- What this script does NOT do:
--   - Award kills, streaks, or XP  →  RewardService (future)
--   - Remove corpses or spawn fresh characters  →  CorpseService (future)
--   - Validate line-of-sight or range  →  will move here from GunService when built

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local HealthChanged = Remotes:WaitForChild("HealthChanged") :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

-- Server-authoritative health table. Never trust a client-supplied health value.
-- Keyed by Player; set to MAX_HEALTH on assignment and cleared on disconnect/reset.
local playerHealth: { [Player]: number } = {}

-- Team memberships received from TeamService via MatchEvents.TeamAssigned.
-- Used by DamageService:Apply() for friendly-fire checks once that rule is added.
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

-- Kills the player by zeroing their Humanoid health.
-- HealthChanged with 0 is fired first so the client UI reacts immediately,
-- before the character is replaced by Roblox's respawn system.
local function killPlayer(player: Player, attacker: Player?)
    playerHealth[player] = 0
    HealthChanged:FireClient(player, 0, Constants.MAX_HEALTH)

    local character = player.Character
    local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
    end

    local attackerName = attacker and attacker.Name or "environment"
    Logger.debug("[DamageService]", player.Name, "killed by", attackerName)
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

-- Returns the player's team name as tracked from TeamAssigned events, or nil.
-- Future friendly-fire logic in Apply() will read this.
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
