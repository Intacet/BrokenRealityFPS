--!strict
-- ModuleScript (LocalScript context only)
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > FootstepController
--
-- Stage 1: Timer-based footstep audio. Plays one random Sound instance per step interval
-- while the local player is grounded and moving. Sounds are parented to a FootstepEmitter
-- Attachment under HumanoidRootPart so they have natural 3D position; they self-destroy
-- when playback ends.
--
-- Stage 2 path (deferred — see DEBT-073):
--   Replace the Heartbeat timer with AnimationTrack:GetMarkerReachedSignal("LeftFootstep")
--   and GetMarkerReachedSignal("RightFootstep") connections. Set FOOTSTEP_MARKER_MODE_READY
--   = true in Constants.lua once the marker signals are wired.
--
-- This controller does NOT:
--   - Replicate footstep sounds to other clients (see DEBT-074)
--   - Detect surface material (all surfaces use FOOTSTEP_DEFAULT_SURFACE = "Concrete")
--   - Change movement speed, animation IDs, camera, or any server state

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules        = ReplicatedStorage:WaitForChild("Modules")
local Logger         = require(Modules:WaitForChild("Logger"))
local Constants      = require(Modules:WaitForChild("Constants"))
local FootstepData   = require(Modules:WaitForChild("FootstepData"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))

-- ============================================================
-- Types
-- ============================================================

type MovementTier = "Walk" | "Run" | "Sprint" | "Crouch"

-- ============================================================
-- Module
-- ============================================================

local FootstepController = {}

-- ============================================================
-- State
-- ============================================================

local localPlayer: Player = Players.LocalPlayer
local humanoid: Humanoid?       = nil
local hrp: BasePart?            = nil
local footstepEmitter: Attachment? = nil
local heartbeatConn: RBXScriptConnection? = nil
local characterConn: RBXScriptConnection? = nil
local timeSinceLastStep: number = 0
local initialized: boolean      = false

-- Grounded Humanoid states — footsteps play in these states only.
local GROUNDED_STATES: { [Enum.HumanoidStateType]: boolean } = {
    [Enum.HumanoidStateType.Running]      = true,
    [Enum.HumanoidStateType.RunningNoPhysics] = true,
    [Enum.HumanoidStateType.Landed]       = true,
}

-- ============================================================
-- Private helpers
-- ============================================================

-- Returns the interval, volume, and pitch range for the given movement tier.
local function getTierParams(tier: MovementTier): (number, number, number, number)
    if tier == "Sprint" then
        return
            Constants.FOOTSTEP_SPRINT_INTERVAL :: number,
            Constants.FOOTSTEP_SPRINT_VOLUME   :: number,
            Constants.FOOTSTEP_SPRINT_PITCH_MIN :: number,
            Constants.FOOTSTEP_SPRINT_PITCH_MAX :: number
    elseif tier == "Crouch" then
        return
            Constants.FOOTSTEP_CROUCH_INTERVAL :: number,
            Constants.FOOTSTEP_CROUCH_VOLUME   :: number,
            Constants.FOOTSTEP_CROUCH_PITCH_MIN :: number,
            Constants.FOOTSTEP_CROUCH_PITCH_MAX :: number
    elseif tier == "Run" then
        return
            Constants.FOOTSTEP_RUN_INTERVAL :: number,
            Constants.FOOTSTEP_RUN_VOLUME   :: number,
            Constants.FOOTSTEP_RUN_PITCH_MIN :: number,
            Constants.FOOTSTEP_RUN_PITCH_MAX :: number
    else
        return
            Constants.FOOTSTEP_WALK_INTERVAL :: number,
            Constants.FOOTSTEP_WALK_VOLUME   :: number,
            Constants.FOOTSTEP_WALK_PITCH_MIN :: number,
            Constants.FOOTSTEP_WALK_PITCH_MAX :: number
    end
end

-- Converts MovementController:GetMoveState() into the footstep tier used for
-- interval/volume/pitch selection and FootstepData lookup.
local function resolveMovementTier(moveState: string): MovementTier?
    if moveState == "Sprinting" then
        return "Sprint"
    elseif moveState == "Crouching" then
        return "Crouch"
    elseif moveState == "Walking" then
        -- Use "Run" tier when WalkSpeed is above the walk threshold (approaching sprint speed).
        -- This distinguishes a brisk jog from a walk without requiring a separate state string.
        local hum = humanoid
        if hum ~= nil then
            local speed = (hum :: Humanoid).WalkSpeed
            local walkThreshold = (Constants.WALK_SPEED :: number) + 1
            if speed > walkThreshold then
                return "Run"
            end
        end
        return "Walk"
    else
        -- Idle, Sliding, Vaulting — no footsteps
        return nil
    end
end

-- Returns true when the character is grounded (not airborne, not dead, not seated).
local function isGrounded(): boolean
    local hum = humanoid
    if hum == nil then return false end
    if not (Constants.FOOTSTEP_GROUNDED_REQUIRED :: boolean) then return true end
    local state = (hum :: Humanoid):GetState()
    return GROUNDED_STATES[state] == true
end

-- Returns true when the local player is moving fast enough to warrant footsteps.
-- Uses HumanoidRootPart AssemblyLinearVelocity (horizontal component) so that
-- FOOTSTEP_MIN_SPEED is a studs-per-second threshold. MoveDirection is a unit
-- vector capped at 1.0 and cannot reach 1.5, so it must not be used here.
local function isMoving(): boolean
    local root = hrp
    if root == nil then return false end
    local vel = (root :: BasePart).AssemblyLinearVelocity
    local horizontalSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
    return horizontalSpeed >= (Constants.FOOTSTEP_MIN_SPEED :: number)
end

-- Plays one one-shot footstep sound. The Sound instance is created, played,
-- and destroyed on Ended — no Sound instances persist between steps.
local function playStep(tier: MovementTier)
    local surface = Constants.FOOTSTEP_DEFAULT_SURFACE :: string
    local surfaceData = FootstepData[surface]
    if surfaceData == nil then
        Logger.warn("[FootstepController] No FootstepData entry for surface: " .. surface)
        return
    end
    local ids: { string }? = surfaceData[tier]
    if ids == nil or #(ids :: { string }) == 0 then
        Logger.warn("[FootstepController] No sound IDs for surface=" .. surface .. " tier=" .. tier)
        return
    end

    local emitter = footstepEmitter
    if emitter == nil then return end

    local chosenId = (ids :: { string })[math.random(1, #(ids :: { string }))]
    local interval, volume, pitchMin, pitchMax = getTierParams(tier)
    local _ = interval -- used by caller, not here

    local s = Instance.new("Sound")
    s.SoundId       = chosenId
    s.Volume        = volume
    s.PlaybackSpeed = pitchMin + math.random() * (pitchMax - pitchMin)
    s.RollOffMinDistance = Constants.FOOTSTEP_ROLLOFF_MIN_DISTANCE :: number
    s.RollOffMaxDistance = Constants.FOOTSTEP_ROLLOFF_MAX_DISTANCE :: number
    s.Looped        = false
    s.Parent        = emitter
    s:Play()

    s.Ended:Connect(function()
        s:Destroy()
    end)

    if Constants.FOOTSTEP_DEBUG :: boolean then
        Logger.debug(
            "[FootstepController] step tier=" .. tier
            .. " id=" .. chosenId
            .. " vol=" .. string.format("%.2f", volume)
            .. " pitch=" .. string.format("%.2f", s.PlaybackSpeed)
        )
    end
end

-- Creates (or recreates) the FootstepEmitter attachment under HumanoidRootPart.
local function setupEmitter(root: BasePart)
    local existing = root:FindFirstChild(Constants.FOOTSTEP_EMITTER_NAME :: string)
    if existing and existing:IsA("Attachment") then
        footstepEmitter = existing :: Attachment
        return
    end
    local att         = Instance.new("Attachment")
    att.Name          = Constants.FOOTSTEP_EMITTER_NAME :: string
    att.Position      = Vector3.new(0, -2.5, 0)   -- near foot level on R6 (HRP center is ~3 studs up)
    att.Parent        = root
    footstepEmitter   = att
end

-- Binds to a new character: finds Humanoid, HumanoidRootPart, creates emitter.
-- Safe to call multiple times (clears previous state first).
local function onCharacterAdded(character: Model)
    -- Clear previous character state without stopping the Heartbeat loop.
    humanoid        = nil
    hrp             = nil
    footstepEmitter = nil
    timeSinceLastStep = 0

    local hum = character:WaitForChild("Humanoid", 5) :: Humanoid?
    if hum == nil then
        Logger.warn("[FootstepController] Humanoid not found on character in 5 s")
        return
    end
    local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
    if root == nil then
        Logger.warn("[FootstepController] HumanoidRootPart not found on character in 5 s")
        return
    end

    humanoid = hum
    hrp      = root
    setupEmitter(root)

    -- Mute Roblox's built-in running/footstep sound so our custom sounds play exclusively.
    -- Roblox's Sound script adds "Running" after HumanoidRootPart is ready, so we watch
    -- ChildAdded as well as checking for an already-present instance.
    local function muteIfRunningSound(child: Instance)
        if child.Name == "Running" and child:IsA("Sound") then
            (child :: Sound).Volume = 0
        end
    end
    for _, child in root:GetChildren() do
        muteIfRunningSound(child)
    end
    root.ChildAdded:Connect(muteIfRunningSound)

    if Constants.FOOTSTEP_DEBUG :: boolean then
        Logger.debug("[FootstepController] character bound — footsteps active")
    end
end

-- Main per-frame update. Called every Heartbeat.
local function onHeartbeat(dt: number)
    if not (Constants.FOOTSTEPS_ENABLED :: boolean) then return end
    if humanoid == nil then return end

    -- Gate: must be grounded and moving.
    -- Do NOT reset timeSinceLastStep here — velocity and humanoid state can flicker
    -- one frame per stride (double-support phase), which would break the cadence if we reset.
    -- Pausing accumulation (just returning) keeps the phase intact through brief dips.
    if not isGrounded() or not isMoving() then
        return
    end

    -- Resolve movement tier; nil means no footstep (idle, sliding, vaulting, etc.)
    local moveState = MovementController:GetMoveState()
    local tier: MovementTier? = resolveMovementTier(moveState)
    if tier == nil then
        return
    end

    local interval, _, _, _ = getTierParams(tier :: MovementTier)
    timeSinceLastStep += dt

    if timeSinceLastStep >= interval then
        timeSinceLastStep -= interval   -- carry leftover so cadence stays accurate
        playStep(tier :: MovementTier)
    end
end

-- ============================================================
-- Public API
-- ============================================================

function FootstepController:Init()
    if initialized then return end
    initialized = true

    -- Connect to current and future characters.
    local character = localPlayer.Character
    if character ~= nil then
        task.spawn(onCharacterAdded, character)
    end
    characterConn = localPlayer.CharacterAdded:Connect(function(char: Model)
        onCharacterAdded(char)
    end)

    -- Single Heartbeat loop. Never recreated on respawn — onCharacterAdded replaces hrp/hum/emitter.
    heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)

    Logger.debug("[FootstepController] initialized")
end

-- SetMovementState is reserved for external callers that may want to force a
-- particular tier (e.g. a future network-replicated footstep system).
-- In Stage 1, GetMoveState() from MovementController is the authoritative source.
function FootstepController:SetMovementState(movementState: string)
    assert(typeof(movementState) == "string",
        "[FootstepController] SetMovementState: movementState must be a string")
    -- No-op in Stage 1: state is inferred from MovementController:GetMoveState() each frame.
    if Constants.FOOTSTEP_DEBUG :: boolean then
        Logger.debug("[FootstepController] SetMovementState called: " .. movementState .. " (no-op in timer mode)")
    end
end

-- Clears per-step timer. Call when entering a special state (cutscene, etc.).
function FootstepController:Reset()
    timeSinceLastStep = 0
    Logger.debug("[FootstepController] reset")
end

-- Full teardown. Disconnects all connections. Call on logout or session end.
function FootstepController:Destroy()
    if heartbeatConn ~= nil then
        (heartbeatConn :: RBXScriptConnection):Disconnect()
        heartbeatConn = nil
    end
    if characterConn ~= nil then
        (characterConn :: RBXScriptConnection):Disconnect()
        characterConn = nil
    end
    humanoid        = nil
    hrp             = nil
    footstepEmitter = nil
    timeSinceLastStep = 0
    initialized     = false
    Logger.debug("[FootstepController] destroyed")
end

return FootstepController
