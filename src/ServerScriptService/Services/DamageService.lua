--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > DamageService
--
-- Owns all server-side health tracking for players AND non-player Humanoid entities
-- (developer test dummies now; NPCs later).
-- Clients never modify health directly — they fire a remote; GunService validates the
-- shot and calls DamageService, which applies the change and fires HealthChanged back to
-- the affected client (players only).
--
-- Every accepted hit fires CombatEvents.DamageDealt; every lethal hit fires
-- CombatEvents.EntityKilled. Those two BindableEvents are the extension point for
-- BloodService, HitReactionService and a future GoreService — none of them require an
-- edit to this file.
--
-- What this script does NOT do:
--   - Convert a character to a ragdoll  →  RagdollService (players: called from killPlayer;
--                                          NPCs/dummies: DummyService listens to EntityKilled)
--   - Remove ragdoll corpses  →  CorpseService (future)
--   - Award kills, streaks, or XP  →  RewardService (future)
--   - Validate line-of-sight or range  →  GunService
--   - Body-part → region mapping or damage arithmetic  →  DamageRules (pure module)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))
local Types      = require(Modules:WaitForChild("Types"))

local MatchEvents     = require(script.Parent:WaitForChild("MatchEvents"))
local CombatEvents    = require(script.Parent:WaitForChild("CombatEvents"))
local DamageRules     = require(script.Parent:WaitForChild("DamageRules"))
local RagdollService  = require(script.Parent:WaitForChild("RagdollService"))

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local HealthChanged = Remotes:WaitForChild("HealthChanged") :: RemoteEvent
local KillFeed      = Remotes:WaitForChild("KillFeed")      :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

-- Server-authoritative player health table. Never trust a client-supplied health value.
-- Keyed by Player; set to MAX_HEALTH on assignment and cleared on disconnect/reset.
-- Non-player entities are NOT tracked here — their Humanoid.Health is authoritative and
-- DummyService owns any per-limb bookkeeping.
local playerHealth: { [Player]: number } = {}

-- Team memberships received from TeamService via MatchEvents.TeamAssigned.
-- Used by getTeamName() for the friendly-fire guard; also queried by GetTeam().
local playerTeam: { [Player]: string } = {}

-- ============================================================
-- Private helpers — players
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
        RagdollService:Apply(character, { player = player, attacker = attacker })
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
-- Private helpers — resolved damage application
-- ============================================================

-- Applies a completed DamageInfo to a player. Reproduces the historical Apply() path
-- exactly (friendly-fire guard, playerHealth table, kill-vs-set), then fires the combat
-- events so downstream systems see player hits the same way they see NPC hits.
local function applyToPlayer(info: Types.DamageInfo)
    local victim   = info.targetPlayer :: Player
    local attacker = info.attacker

    if not Constants.FRIENDLY_FIRE_ENABLED and attacker ~= nil then
        local attackerTeam = getTeamName(attacker)
        local victimTeam    = getTeamName(victim)
        if attackerTeam ~= nil and victimTeam ~= nil and attackerTeam == victimTeam then
            Logger.debug("[DamageService] Blocked friendly fire:", attacker.Name, "→", victim.Name)
            return
        end
    end

    -- Tooling-helper support (SetInvincible, 2026-09-11 — AI-arena-spectating
    -- addition): mirrors applyToNonPlayer's ATTR_INFINITE_HEALTH behavior below
    -- for a Player victim too — still emits DamageDealt (blood/reactions/limb
    -- tracking keep working) but takes no health and can never die. Keyed off
    -- the Character Model, since that is what SetInvincible actually receives
    -- (the attribute lives on the Model, not the Player) — a fresh respawn is a
    -- new Model, so this never carries over past a death/round-start reset.
    local victimChar = victim.Character
    if victimChar ~= nil and victimChar:GetAttribute(Constants.ATTR_INFINITE_HEALTH) == true then
        CombatEvents.DamageDealt:Fire(info.targetModel, info)
        return
    end

    local current = playerHealth[victim]
    if current == nil then
        -- Player joined between phases; initialise to full health before applying damage.
        current = Constants.MAX_HEALTH
    end

    local newHp = current - info.finalAmount

    if newHp <= 0 then
        killPlayer(victim, attacker)
        CombatEvents.DamageDealt:Fire(info.targetModel, info)
        CombatEvents.EntityKilled:Fire(info.targetModel, info)
    else
        setHealth(victim, newHp)
        CombatEvents.DamageDealt:Fire(info.targetModel, info)
    end
end

-- Applies a completed DamageInfo to a non-player Humanoid entity (test dummy / NPC).
-- Humanoid.Health is the authoritative store — there is no parallel table. A model
-- flagged Constants.ATTR_INFINITE_HEALTH still emits DamageDealt (so blood, reactions and
-- limb tracking keep working) but loses no health and can never die.
local function applyToNonPlayer(info: Types.DamageInfo)
    local model    = info.targetModel
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        Logger.warn("[DamageService] ApplyDamage: non-player target has no Humanoid — ignored")
        return
    end
    if humanoid.Health <= 0 then
        return  -- already dead; ignore further hits until the owner respawns it
    end

    local infinite = model ~= nil and model:GetAttribute(Constants.ATTR_INFINITE_HEALTH) == true
    if not infinite then
        humanoid:TakeDamage(info.finalAmount)
    end

    CombatEvents.DamageDealt:Fire(model, info)

    if not infinite and humanoid.Health <= 0 then
        local killerName = info.attacker and info.attacker.DisplayName
            or (info.sourceName ~= "" and info.sourceName)
            or "environment"
        Logger.debug("[DamageService]", model and model.Name or "entity", "killed by", killerName)
        CombatEvents.EntityKilled:Fire(model, info)
    end
end

-- ============================================================
-- Public API
-- ============================================================

local DamageService = {}

-- Entity-agnostic damage entry point. `request` is a Types.DamageInfo-shaped table with
-- `finalAmount` omitted (or 0) — DamageService resolves the region, computes the final
-- amount via DamageRules, then routes to the player or non-player path.
--
-- Always called from the server. GunService is the only in-tree caller for real shots;
-- DamageService:Apply() below is a thin compatibility shim over this.
function DamageService:ApplyDamage(request: Types.DamageRequest)
    if request == nil then
        return
    end
    local base = request.baseAmount
    if typeof(base) ~= "number" or base <= 0 then
        return  -- ignore zero-damage and healing calls routed here by mistake
    end

    -- Region: explicit value wins (the Apply() shim passes Unknown); otherwise derive it
    -- from the hit part name. Unknown always carries a ×1 multiplier.
    local region: Types.HitRegion = request.region
        or DamageRules.RegionForPart(request.hitPart and (request.hitPart :: BasePart).Name)

    local finalAmount = DamageRules.ComputeFinalDamage(base, region)
    if finalAmount == nil then
        Logger.warn("[DamageService] ApplyDamage: rejected non-finite/non-positive damage from",
            (request.sourceName ~= nil and request.sourceName ~= "") and request.sourceName or "unknown source")
        return
    end

    local info: Types.DamageInfo = {
        targetPlayer = request.targetPlayer,
        targetModel  = request.targetModel,
        attacker     = request.attacker,
        sourceName   = request.sourceName or "",
        damageType   = request.damageType or Constants.DamageType.Unknown,
        region       = region,
        hitPart      = request.hitPart,
        hitPosition  = request.hitPosition,
        hitDirection = request.hitDirection,
        baseAmount   = base,
        finalAmount  = finalAmount,
    }

    if info.targetPlayer ~= nil then
        applyToPlayer(info)
    else
        applyToNonPlayer(info)
    end
end

-- Compatibility shim. Historical signature used everywhere before the pipeline was
-- generalised: flat damage on a player, no body part. Behaviour is unchanged — region is
-- forced to Unknown (×1) so the numbers match exactly; it now also emits combat events.
function DamageService:Apply(victim: Player, amount: number, attacker: Player?)
    self:ApplyDamage({
        targetPlayer = victim,
        targetModel  = victim.Character,
        attacker     = attacker,
        sourceName   = "",
        damageType   = Constants.DamageType.Bullet :: Types.DamageType,
        region       = Constants.HitRegion.Unknown :: Types.HitRegion,
        baseAmount   = amount,
    })
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

-- Tooling helper (used by DummyService reset / the Stage 6 debug UI). Heals a player or a
-- non-player Humanoid model by `amount`, clamped to MaxHealth. Never fires damage events.
function DamageService:Heal(target: Instance, amount: number)
    if typeof(amount) ~= "number" or amount <= 0 then
        return
    end
    if target:IsA("Player") then
        local player  = target :: Player
        local current = playerHealth[player] or Constants.MAX_HEALTH
        setHealth(player, current + amount)
    elseif target:IsA("Model") then
        local humanoid = (target :: Model):FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
        end
    end
end

-- Tooling helper. Toggles Constants.ATTR_INFINITE_HEALTH on `model`. While set,
-- ApplyDamage still emits DamageDealt but removes no health and never kills it —
-- works for a non-player model (applyToNonPlayer, the original use) AND (added
-- 2026-09-11 for AI-arena spectating) a player's Character (applyToPlayer now
-- checks this attribute too, keyed off the Character since that is what this
-- function receives, not the Player).
function DamageService:SetInvincible(model: Model, enabled: boolean)
    model:SetAttribute(Constants.ATTR_INFINITE_HEALTH, enabled == true)
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
