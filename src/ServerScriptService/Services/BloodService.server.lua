--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > BloodService
--
-- Turns damage events into the minimum information a client needs to draw blood, and
-- nothing more. The server creates zero particles and zero decals — it only decides
-- "a hit worth bleeding happened here, this hard" and fires BloodEffect. BloodController
-- (client) owns every visual and every instance cap.
--
-- Reusable character system: it reacts to CombatEvents.DamageDealt for ANY target with a
-- hit position, gated per-model by the BR_BloodEnabled attribute (default on) and globally
-- by Constants.BLOOD_ENABLED plus the runtime BR_BloodGlobalEnabled attribute on
-- ReplicatedStorage. It is not coupled to the test dummy.
--
-- What this script does NOT do:
--   - Draw particles / marks / decals        →  BloodController (client)
--   - Decide damage or death                 →  DamageService
--   - Gore / dismemberment                   →  future GoreService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))
local Types     = require(Modules:WaitForChild("Types"))

local CombatEvents = require(script.Parent:WaitForChild("CombatEvents"))

local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local BloodEffect = Remotes:WaitForChild("BloodEffect") :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

local GLOBAL_ATTR = Constants.BLOOD_GLOBAL_ATTRIBUTE :: string

-- Per-target send throttle. Pruned on a slow Heartbeat sweep so destroyed models do not
-- pin themselves alive through this table.
local lastSendAt: { [Model]: number } = {}
local conns: { RBXScriptConnection } = {}
local pruneAccumulator = 0

-- ============================================================
-- Helpers
-- ============================================================

local function bloodGloballyOn(): boolean
    if not (Constants.BLOOD_ENABLED :: boolean) then
        return false
    end
    -- Unset attribute → treated as on; only an explicit false disables.
    return ReplicatedStorage:GetAttribute(GLOBAL_ATTR) ~= false
end

local function onDamageDealt(_targetModel: Model?, info: Types.DamageInfo)
    if info.hitPosition == nil or info.hitDirection == nil then
        return
    end
    if not bloodGloballyOn() then
        return
    end

    local model = info.targetModel
    if model ~= nil and model:GetAttribute(Constants.ATTR_BLOOD_ENABLED :: string) == false then
        return
    end

    if model ~= nil then
        local now  = os.clock()
        local last = lastSendAt[model]
        if last ~= nil and now - last < (Constants.BLOOD_EFFECT_RATE_LIMIT :: number) then
            return
        end
        lastSendAt[model] = now
    end

    local reference = Constants.BLOOD_REFERENCE_DAMAGE :: number
    local minI      = Constants.BLOOD_MIN_INTENSITY :: number
    local intensity = math.clamp(info.finalAmount / reference, minI, 1)

    -- Data only. No instance is created on the server.
    BloodEffect:FireAllClients(info.hitPosition, info.hitDirection, intensity, info.damageType)
end

-- The runtime global toggle IS the ReplicatedStorage attribute named by
-- Constants.BLOOD_GLOBAL_ATTRIBUTE. DummyService's dev command sets it; BloodController
-- reads the same replicated value for an instant client-side cut-off. No cross-require.

-- ============================================================
-- Init
-- ============================================================

table.insert(conns, CombatEvents.DamageDealt.Event:Connect(onDamageDealt))

table.insert(conns, RunService.Heartbeat:Connect(function(dt: number)
    pruneAccumulator += dt
    if pruneAccumulator < 5 then
        return
    end
    pruneAccumulator = 0
    for model in lastSendAt do
        if model.Parent == nil then
            lastSendAt[model] = nil
        end
    end
end))

-- Make the current global flag explicit at boot so late-joining clients replicate a value.
if ReplicatedStorage:GetAttribute(GLOBAL_ATTR) == nil then
    ReplicatedStorage:SetAttribute(GLOBAL_ATTR, Constants.BLOOD_ENABLED :: boolean)
end

Logger.debug("[BloodService] Ready — data-only; client draws every effect")
