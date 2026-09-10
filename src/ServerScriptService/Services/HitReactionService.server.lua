--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > HitReactionService
--
-- Directional flinch reactions, driven by CombatEvents.DamageDealt. Reusable character
-- system — it acts on any R6 model whose BR_ReactionsEnabled attribute is true, not just
-- the test dummy.
--
-- IMPLEMENTATION: procedural. A short, decaying additive offset is written to one
-- Motor6D.Transform (chosen by hit region), then lerped back to identity over
-- Constants.REACTION_DURATION. It never touches Motor6D.C0/C1, Motor6D.Enabled,
-- Humanoid.PlatformStand or Humanoid.WalkSpeed, and every offset has a hard deadline, so
-- applying this to player characters later cannot brick movement or weapons — the worst
-- case is the flinch being invisible because the player's Animator overwrites Transform.
--
-- THE SWAP SEAM: `applyReaction` below is the single place a reaction is produced. To
-- supplement or replace procedural flinches with animation (e.g. a short additive flinch
-- track on a dedicated layer), swap that one function — the DamageDealt wiring, region
-- mapping, strength math and cleanup loop stay the same.
--
-- What this script does NOT do:
--   - Ragdoll / death physics    →  RagdollService
--   - Decide damage              →  DamageService
--   - Blood                      →  BloodService / BloodController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))
local Types     = require(Modules:WaitForChild("Types"))

local CombatEvents = require(script.Parent:WaitForChild("CombatEvents"))

local REACTIONS_ATTR = Constants.ATTR_REACTIONS_ENABLED :: string
local RAGDOLLED_ATTR = "BR_Ragdolled"

-- ============================================================
-- State
-- ============================================================

type Flinch = {
    motor    : Motor6D,
    peak     : CFrame,
    strength : number,
    elapsed  : number,
    duration : number,
    deadline : number,   -- os.clock() hard stop; the offset is cleared no matter what past this
}

local flinches: { [Motor6D]: Flinch } = {}
local conns: { RBXScriptConnection } = {}

-- ============================================================
-- Helpers
-- ============================================================

local function reactionsAllowed(model: Model?): boolean
    if model == nil then
        return false
    end
    if model:GetAttribute(REACTIONS_ATTR) ~= true then
        return false
    end
    if model:GetAttribute(RAGDOLLED_ATTR) == true then
        return false
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function findJoint(model: Model, jointName: string): Motor6D?
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Motor6D") and descendant.Name == jointName then
            return descendant
        end
    end
    return nil
end

-- Produces one flinch offset. THE SWAP SEAM (see file header).
local function applyReaction(model: Model, region: Types.HitRegion, hitDirection: Vector3, strength: number)
    local jointName = (Constants.REACTION_REGION_JOINTS :: { [string]: string })[region]
        or Constants.REACTION_REGION_JOINTS.Unknown
    local motor = findJoint(model, jointName)
    if motor == nil then
        return
    end

    -- Flinch continues in the shot's travel direction (the body is shoved the way the
    -- round was going). Resolve that into the character's own frame so "from the front"
    -- always pitches back regardless of which way the rig faces.
    local rel = model:GetPivot():VectorToObjectSpace(hitDirection)
    if rel.Magnitude > 1e-3 then
        rel = rel.Unit
    end

    local maxAngle = math.rad(Constants.REACTION_MAX_ANGLE_DEG :: number)

    -- If a flinch is already decaying on this joint, stack toward REACTION_MAX_STACK and
    -- restart the decay rather than starting a second competing offset.
    local existing = flinches[motor]
    local effStrength = strength
    if existing ~= nil then
        effStrength = math.min(Constants.REACTION_MAX_STACK :: number, existing.strength + strength)
    end

    local pitch = -rel.Z * maxAngle * effStrength   -- shot into the front (rel.Z < 0) → head/torso tips back
    local yaw   = -rel.X * maxAngle * effStrength
    local peak  = CFrame.Angles(pitch, yaw, 0)

    local duration = Constants.REACTION_DURATION :: number
    flinches[motor] = {
        motor    = motor,
        peak     = peak,
        strength = effStrength,
        elapsed  = 0,
        duration = duration,
        deadline = os.clock() + duration + 0.5,
    }
end

local function clearFlinch(motor: Motor6D)
    if motor.Parent ~= nil then
        motor.Transform = CFrame.identity
    end
    flinches[motor] = nil
end

-- ============================================================
-- Loop
-- ============================================================

local function onHeartbeat(dt: number)
    local now = os.clock()
    for motor, record in flinches do
        if motor.Parent == nil or now >= record.deadline then
            clearFlinch(motor)
        else
            record.elapsed += dt
            local alpha = record.elapsed / record.duration
            if alpha >= 1 then
                clearFlinch(motor)
            else
                -- peak at alpha 0 → identity at alpha 1
                motor.Transform = record.peak:Lerp(CFrame.identity, alpha)
            end
        end
    end
end

-- ============================================================
-- Init
-- ============================================================

table.insert(conns, CombatEvents.DamageDealt.Event:Connect(function(targetModel: Model?, info: Types.DamageInfo)
    if info.hitDirection == nil or info.finalAmount <= 0 then
        return
    end
    if not reactionsAllowed(targetModel) then
        return
    end
    local strength = math.clamp(info.finalAmount / (Constants.REACTION_REFERENCE_DAMAGE :: number), 0, 1)
    applyReaction(targetModel :: Model, info.region, info.hitDirection, strength)
end))

table.insert(conns, RunService.Heartbeat:Connect(onHeartbeat))

Logger.debug("[HitReactionService] Ready — procedural flinch")
