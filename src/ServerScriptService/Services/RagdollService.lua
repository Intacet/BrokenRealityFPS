--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > RagdollService
--
-- Converts a Humanoid character from a rigidly-animated rig into a physics ragdoll, and
-- back again. Reusable for players, developer test dummies, and future NPCs — the caller
-- passes an options table; player-only side effects only run when a Player is supplied.
--
-- What this service does:
--   - Replaces every Motor6D with a BallSocketConstraint (Motor6Ds are disabled, not
--     destroyed, so Restore() can rebuild the rig)
--   - Sets PlatformStand = true so the Humanoid stops fighting the physics joints
--   - Sets BreakJointsOnDeath = false so a later Health = 0 does not destroy the joints
--   - Optionally applies a one-off impulse from the killing shot so deaths vary
--   - For players only: sets Humanoid.Health = 0, fires MatchEvents.PlayerDied, and fires
--     the RagdollApplied remote for the death screen
--   - Restore() removes the constraints, re-enables the Motor6Ds and clears PlatformStand
--
-- What this service does NOT do:
--   - Destroy the character / remove corpses  →  CorpseService (future)
--   - Track team or alive state               →  TeamService (via Humanoid.Died)
--   - Apply damage or validate hits           →  DamageService / GunService
--   - Decide when a non-player entity dies     →  DamageService (fires CombatEvents.EntityKilled)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local RagdollApplied = Remotes:WaitForChild("RagdollApplied") :: RemoteEvent

-- Attribute marking a character that is currently ragdolled — guards against a double
-- Apply() and lets other systems (DummyService, a future revive) check state cheaply.
local RAGDOLLED_ATTRIBUTE = "BR_Ragdolled"

local ATT0_PREFIX = "RagdollAtt0_"
local ATT1_PREFIX = "RagdollAtt1_"
local BSC_PREFIX  = "RagdollBSC_"

-- Limbs whose CanCollide we drop while ragdolled (so the Torso slumps rather than the rig
-- balancing on stiff legs). Original value is stashed on this attribute for Restore().
local LIMB_NAMES = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local WAS_COLLIDE_ATTR = "BR_RagdollWasCollide"

export type RagdollOptions = {
    player     : Player?,   -- set for player deaths; drives the death screen + kill signals
    attacker   : Player?,   -- responsible player, or nil for environment kills
    impulse    : Vector3?,  -- world-space impulse from the killing hit; clamped here
    hitPart    : BasePart?, -- part the impulse is applied to (falls back to the root/torso)
    sourceName : string?,   -- weapon / hazard label, for logs
}

-- ============================================================
-- Private helpers
-- ============================================================

-- Converts one Motor6D into a BallSocketConstraint so the joint becomes physics-driven
-- instead of animation-driven. The Motor6D is disabled but kept so Restore() can rebuild.
local function convertJoint(motor: Motor6D)
    local part0 = motor.Part0
    local part1 = motor.Part1
    if part0 == nil or part1 == nil then
        Logger.warn("[RagdollService] Motor6D has nil Part0 or Part1 — skipping:", motor:GetFullName())
        return
    end

    local att0 = Instance.new("Attachment")
    att0.Name   = ATT0_PREFIX .. motor.Name
    att0.CFrame = motor.C0
    att0.Parent = part0

    local att1 = Instance.new("Attachment")
    att1.Name   = ATT1_PREFIX .. motor.Name
    att1.CFrame = motor.C1
    att1.Parent = part1

    -- `or` fallbacks tolerate a Constants module that has not synced the new keys yet.
    local jointAngles = (Constants.RAGDOLL_JOINT_ANGLES :: any) or {}
    local upperAngle  = jointAngles[motor.Name]
        or (Constants.RAGDOLL_BALLSOCKET_DEFAULT_ANGLE :: any)
        or 90

    local bsc         = Instance.new("BallSocketConstraint")
    bsc.Name          = BSC_PREFIX .. motor.Name
    bsc.Attachment0   = att0
    bsc.Attachment1   = att1
    bsc.LimitsEnabled = true   -- prevent full 360° spin; keeps the ragdoll visually plausible
    bsc.UpperAngle    = upperAngle
    bsc.Parent        = part0

    motor.Enabled = false
end

-- Picks the part an impulse is applied to. Prefer the Torso (the ragdoll's main mass) so
-- the body gets one coherent shove instead of a light limb being flung across the room;
-- fall back to the HumanoidRootPart, then to the hit part only if the rig has neither.
local function impulseTarget(character: Model, hitPart: BasePart?): BasePart?
    local torso = character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        return torso
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    if hitPart ~= nil and hitPart.Parent ~= nil and hitPart:IsDescendantOf(character) then
        return hitPart
    end
    return nil
end

-- ============================================================
-- Public API
-- ============================================================

local RagdollService = {}

-- Ragdolls `character`. `opts.player` distinguishes a player death (death screen + kill
-- signals) from an NPC / dummy death (physics only). Safe to call once per death; a second
-- call while already ragdolled is a no-op.
function RagdollService:Apply(character: Model, opts: RagdollOptions?)
    local options: RagdollOptions = opts or {}

    if character:GetAttribute(RAGDOLLED_ATTRIBUTE) == true then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        local who = options.player and options.player.Name or character.Name
        Logger.warn("[RagdollService] No Humanoid in character for", who, "— cannot ragdoll")
        return
    end

    -- BreakJointsOnDeath must be off BEFORE anything sets Health to 0, or the engine
    -- destroys the Motor6Ds we are about to disable and Restore() can never rebuild them.
    humanoid.BreakJointsOnDeath = false

    -- RequiresNeck must be off BEFORE the Neck Motor6D is disabled below. With it on
    -- (the default), the engine notices the missing neck and, after a ~0.5 s grace
    -- period, forcibly finalises the death — the rig stays upright and rigid for that
    -- half second, then flops. Turning it off lets the constraints take over on the
    -- same frame, so the ragdoll (and the death impulse) land immediately.
    humanoid.RequiresNeck = false

    -- ── Convert all Motor6Ds to physics joints ──────────────────────────────────
    local motorCount = 0
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            convertJoint(descendant :: Motor6D)
            motorCount += 1
        end
    end

    local who = options.player and options.player.Name or character.Name
    if motorCount == 0 then
        Logger.warn("[RagdollService] No Motor6Ds found in character for", who,
            "— ragdoll will not work; rig may be non-standard or already broken")
    else
        Logger.debug("[RagdollService] Converted", motorCount, "Motor6Ds for", who)
    end

    -- ── Stop the Humanoid fighting the joints ───────────────────────────────────
    humanoid.PlatformStand = true
    -- GettingUp would repeatedly try to stand the rig back up mid-ragdoll.
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end)
    character:SetAttribute(RAGDOLLED_ATTRIBUTE, true)

    -- ── Force server physics ownership so the death impulse lands this frame ─────
    -- Without this the parts may still be owned by a client (or unassigned), and the
    -- ApplyImpulse below is silently deferred/absorbed — the "folds up while standing"
    -- symptom. A dead body is server-authoritative anyway.
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") and not descendant.Anchored then
            pcall(function()
                descendant:SetNetworkOwner(nil)
            end)
        end
    end

    -- ── Let the body actually fall: drop CanCollide on the limbs ────────────────
    if (Constants.RAGDOLL_LIMB_NONCOLLIDE :: any) ~= false then
        for _, limbName in ipairs(LIMB_NAMES) do
            local limb = character:FindFirstChild(limbName)
            if limb ~= nil and limb:IsA("BasePart") then
                limb:SetAttribute(WAS_COLLIDE_ATTR, limb.CanCollide)
                limb.CanCollide = false
            end
        end
    end

    -- ── Preserve some of the incoming shot force ────────────────────────────────
    -- Applied after PlatformStand so the Humanoid does not immediately damp it out.
    if options.impulse ~= nil then
        local raw = options.impulse
        -- Tilt the shove toward the ground so the body falls rather than sailing back.
        local downBias = (Constants.RAGDOLL_IMPULSE_DOWN_BIAS :: any) or 0
        if raw.Magnitude > 0 and downBias > 0 then
            raw = (raw.Unit + Vector3.new(0, -downBias, 0)).Unit * raw.Magnitude
        end
        -- Hard safety ceiling (per-weapon MAX is applied by the caller).
        local ceiling = (Constants.RAGDOLL_MAX_IMPULSE :: any) or 1200
        if raw.Magnitude > ceiling then
            raw = raw.Unit * ceiling
        end
        local target = impulseTarget(character, options.hitPart)
        if target ~= nil and raw.Magnitude > 0 then
            -- Apply ABOVE the centre of mass so the shove tips the body over rather than
            -- just sliding it (a lever arm from the feet).
            local hOffset = (Constants.RAGDOLL_IMPULSE_HEIGHT_OFFSET :: any) or 1.6
            target:ApplyImpulseAtPosition(raw, target.Position + Vector3.new(0, hOffset, 0))
        end
    end

    -- ── Player-only side effects ────────────────────────────────────────────────
    if options.player ~= nil then
        local player     = options.player
        local killerName = if options.attacker ~= nil then options.attacker.DisplayName else ""

        -- Setting Health = 0 fires Humanoid.Died, which TeamService listens to for
        -- alive-count tracking and round-end detection.
        humanoid.Health = 0

        -- Server-side named death signal for future consumers (RewardService, CorpseService)
        -- that do not want to rely on Humanoid.Died.
        MatchEvents.PlayerDied:Fire(player, killerName)

        -- Tells every client a player died; the dying player's DeathScreen reacts to its
        -- own UserId (fade, blur, audio muffle).
        RagdollApplied:FireAllClients(player.UserId, killerName)

        Logger.debug("[RagdollService] Ragdoll applied to", player.Name, "| killer:", killerName)
    else
        Logger.debug("[RagdollService] Ragdoll applied to entity", character.Name,
            "| source:", options.sourceName or "unknown")
    end
end

-- Reverses Apply(): removes the ragdoll constraints/attachments it created and re-enables
-- the Motor6Ds so the rig is animation-driven again. Does NOT restore Humanoid.Health or
-- reposition the character — the caller (DummyService reset, a future revive) owns that.
function RagdollService:Restore(character: Model)
    if character:GetAttribute(RAGDOLLED_ATTRIBUTE) ~= true then
        return
    end

    local removed = 0
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BallSocketConstraint") and descendant.Name:sub(1, #BSC_PREFIX) == BSC_PREFIX then
            descendant:Destroy()
            removed += 1
        elseif descendant:IsA("Attachment")
            and (descendant.Name:sub(1, #ATT0_PREFIX) == ATT0_PREFIX
                or descendant.Name:sub(1, #ATT1_PREFIX) == ATT1_PREFIX)
        then
            descendant:Destroy()
            removed += 1
        elseif descendant:IsA("Motor6D") and not descendant.Enabled then
            descendant.Enabled = true
        end
    end

    -- Restore limb collision from the stashed value.
    for _, limbName in ipairs(LIMB_NAMES) do
        local limb = character:FindFirstChild(limbName)
        if limb ~= nil and limb:IsA("BasePart") then
            local was = limb:GetAttribute(WAS_COLLIDE_ATTR)
            if typeof(was) == "boolean" then
                limb.CanCollide = was
            end
            limb:SetAttribute(WAS_COLLIDE_ATTR, nil)
        end
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.PlatformStand = false
        humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
        humanoid.RequiresNeck = true
    end

    character:SetAttribute(RAGDOLLED_ATTRIBUTE, false)
    Logger.debug("[RagdollService] Restored", character.Name, "— removed", removed, "ragdoll instances")
end

-- Whether a character is currently ragdolled (set by Apply, cleared by Restore).
function RagdollService:IsRagdolled(character: Model): boolean
    return character:GetAttribute(RAGDOLLED_ATTRIBUTE) == true
end

return RagdollService
