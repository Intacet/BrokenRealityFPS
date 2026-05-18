--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MovementController
--
-- Movement Stage 1 — walk, sprint, crouch speed; 8-direction camera-relative movement
-- state; phase gating; respawn handling; connection cleanup.
--
-- Owns:
--   • local movement input (LeftShift = sprint, C = crouch toggle)
--   • movementState table (isMoving, isSprinting, isCrouching, directionName, moveVector)
--   • Humanoid.WalkSpeed:
--       0                          when phase is not ACTIVE
--       Constants.WALK_SPEED       when ACTIVE and not sprinting/crouching
--       Constants.SPRINT_SPEED     when ACTIVE, sprinting, and moving
--       Constants.CROUCH_SPEED     when ACTIVE and crouching
--   • 8-directional direction detection via Humanoid.MoveDirection dot products
--
-- Camera rule (Stage 1):
--   Reads workspace.CurrentCamera.CFrame for direction detection only.
--   Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
--   Does NOT add camera bob, sway, landing dip, tilt, or viewmodel effects.
--
-- Not in Stage 1: slide, vault, stamina, prone, animations, footsteps, crouch body lowering,
--   camera height changes, viewmodel sway.
--
-- Exposes:
--   GetMovementState()           → movementState table (all fields read-only for callers)
--   GetMoveState(): string       → "Idle"|"Walking"|"Sprinting"|"Crouching" (GunController compat)
--   IsADSBlocked(): boolean      → true while sprinting; blocks GunController ADS
--   GetViewmodelAddCFrame(): CFrame → identity in Stage 1; ViewModelController multiplies this in
--   Start()                      → called by ClientInit after MatchController:Start()
--   destroy()                    → disconnects all connections and resets state
--
-- Phase source: MatchController:GetPhase() (cached value) + RoundStateChanged for live updates.
-- Initialized at position 9 in ClientInit.client.lua.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules        = ReplicatedStorage:WaitForChild("Modules")
local Constants      = require(Modules:WaitForChild("Constants"))
local Logger         = require(Modules:WaitForChild("Logger"))

-- MatchController is guaranteed Start()ed before this module's Start() (ClientInit order 1→9).
local MatchController = require(script.Parent:WaitForChild("MatchController"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- movementState — public read-only state table
-- Written only by this module. Callers read via GetMovementState().
-- ============================================================

local movementState = {
    isMoving      = false,          -- true when MoveDirection.Magnitude > MOVEMENT_DIRECTION_DEADZONE
    isSprinting   = false,          -- true while LeftShift is held during ACTIVE
    isCrouching   = false,          -- true while crouched (toggled by C during ACTIVE)
    directionName = "Idle",         -- one of 9 direction strings (see classifyDirection)
    moveVector    = Vector3.zero,   -- raw Humanoid.MoveDirection each Heartbeat
}

-- ============================================================
-- Private state
-- ============================================================

-- Current Humanoid — replaced on every CharacterAdded.
local humanoid: Humanoid? = nil

-- All RBXScriptConnections created in Start(). destroy() disconnects every entry.
local _connections: { RBXScriptConnection } = {}

-- ============================================================
-- Private helpers
-- ============================================================

-- Resets all movementState fields to initial (idle) values.
-- Does NOT apply WalkSpeed — callers must call applySpeed() or set it directly after.
local function resetState()
    movementState.isMoving      = false
    movementState.isSprinting   = false
    movementState.isCrouching   = false
    movementState.directionName = "Idle"
    movementState.moveVector    = Vector3.zero
end

-- Sets Humanoid.WalkSpeed according to the current phase and movementState.
-- Safe to call at any time; guards against nil humanoid.
-- Speed priority: not-ACTIVE → 0; crouching → CROUCH_SPEED;
--   sprinting+moving → SPRINT_SPEED; else → WALK_SPEED.
local function applySpeed()
    local hum = humanoid
    if not hum then return end

    if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then
        hum.WalkSpeed = 0
        return
    end

    if movementState.isCrouching then
        hum.WalkSpeed = Constants.CROUCH_SPEED
    elseif movementState.isSprinting and movementState.isMoving then
        hum.WalkSpeed = Constants.SPRINT_SPEED
    else
        hum.WalkSpeed = Constants.WALK_SPEED
    end
end

-- Maps Humanoid.MoveDirection to one of 9 named directions.
-- Returns "Idle" when the magnitude is below MOVEMENT_DIRECTION_DEADZONE.
-- Uses dot products against the camera's XZ-flattened look and right vectors
-- so directions are camera-relative (W = Forward relative to where you're looking).
local function classifyDirection(moveDir: Vector3): string
    if moveDir.Magnitude < Constants.MOVEMENT_DIRECTION_DEADZONE then
        return "Idle"
    end

    local cam      = workspace.CurrentCamera
    local look     = cam.CFrame.LookVector
    local right    = cam.CFrame.RightVector

    -- Flatten onto the XZ plane so camera pitch does not affect direction classification.
    local camFlat  = Vector3.new(look.X,  0, look.Z)
    local camRight = Vector3.new(right.X, 0, right.Z)

    -- Guard: camera may briefly look straight up or down (e.g. first-person death pan).
    if camFlat.Magnitude < 0.01 then
        camFlat = Vector3.new(0, 0, -1)  -- default: world -Z
    else
        camFlat = camFlat.Unit
    end
    if camRight.Magnitude < 0.01 then
        -- Derive right as the 90° CW rotation of camFlat on XZ.
        camRight = Vector3.new(camFlat.Z, 0, -camFlat.X)
    else
        camRight = camRight.Unit
    end

    local f = moveDir:Dot(camFlat)   -- positive = forward relative to camera
    local r = moveDir:Dot(camRight)  -- positive = right relative to camera

    -- Diagonal threshold: both axes must exceed this to qualify as a diagonal direction.
    -- Keeping this separate from MOVEMENT_DIRECTION_DEADZONE (magnitude check above).
    local diag: number = 0.35

    local isFwd   = f >  diag
    local isBack  = f < -diag
    local isRight = r >  diag
    local isLeft  = r < -diag

    if   isFwd  and isRight then return "ForwardRight"
    elseif isFwd  and isLeft  then return "ForwardLeft"
    elseif isBack and isRight then return "BackwardRight"
    elseif isBack and isLeft  then return "BackwardLeft"
    elseif isFwd              then return "Forward"
    elseif isBack             then return "Backward"
    elseif isRight            then return "Right"
    elseif isLeft             then return "Left"
    else                           return "Idle"
    end
end

-- Called on every CharacterAdded. Re-acquires the Humanoid reference, resets
-- movementState, and applies the phase-appropriate WalkSpeed immediately so
-- characters don't inherit speed from the previous life.
local function setupCharacter(char: Model)
    humanoid = char:WaitForChild("Humanoid") :: Humanoid

    resetState()

    -- Apply speed immediately — do not wait for the next Heartbeat.
    local hum = humanoid :: Humanoid
    if MatchController:GetPhase() == Constants.Phase.ACTIVE then
        hum.WalkSpeed = Constants.WALK_SPEED  -- sprint/crouch state was just reset above
    else
        hum.WalkSpeed = 0  -- freeze in LOBBY / PREP / RESULTS / MATCHEND
    end

    Logger.debug("[MovementController] Character set up: " .. char.Name)
end

-- ============================================================
-- Controller
-- ============================================================

local MovementController = {}

-- ── Public API ─────────────────────────────────────────────────────────────────

-- Returns the live movementState table. Treat all fields as read-only.
-- Returned by reference — the table updates in place each Heartbeat.
function MovementController:GetMovementState(): typeof(movementState)
    return movementState
end

-- Backward-compatible single-string getter for GunController's spread computation.
-- Returns "Sprinting", "Crouching", "Walking", or "Idle".
-- Kept alongside GetMovementState() so GunController does not need changes in Stage 1.
function MovementController:GetMoveState(): string
    if movementState.isSprinting and movementState.isMoving then
        return "Sprinting"
    elseif movementState.isCrouching then
        return "Crouching"
    elseif movementState.isMoving then
        return "Walking"
    else
        return "Idle"
    end
end

-- True while the player is sprinting. GunController reads this to block ADS.
function MovementController:IsADSBlocked(): boolean
    return movementState.isSprinting
end

-- Stage 1: no viewmodel effects. Returns identity so ViewModelController's
-- PivotTo composition is unaffected. Future stages will compose bob, tilt,
-- and sway here without changing ViewModelController's call site.
function MovementController:GetViewmodelAddCFrame(): CFrame
    return CFrame.new()
end

-- Disconnects all event connections and resets all state.
-- Safe to call even if Start() was never called (iterates an empty table).
function MovementController:destroy()
    for _, conn in ipairs(_connections) do
        conn:Disconnect()
    end
    _connections = {}
    humanoid     = nil
    resetState()
    Logger.debug("[MovementController] Destroyed")
end

-- ============================================================
-- Start
-- ============================================================

function MovementController:Start()
    local localPlayer = Players.LocalPlayer

    -- Handle a character that already exists before Start() is called.
    -- Rare in normal play (ClientInit runs early) but correct to handle.
    if localPlayer.Character then
        setupCharacter(localPlayer.Character)
    end

    -- ── CharacterAdded ────────────────────────────────────────────────────────
    -- Re-acquires Humanoid and resets state on every respawn.
    -- Stored so destroy() can disconnect it.
    local charConn = localPlayer.CharacterAdded:Connect(function(char: Model)
        setupCharacter(char)
    end)
    table.insert(_connections, charConn)

    -- ── RoundStateChanged ─────────────────────────────────────────────────────
    -- Mirrors the phase into movementState and WalkSpeed so the controller
    -- stays correct without polling MatchController every Heartbeat.
    local phaseConn = RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local phase   = payload.phase

        if phase ~= Constants.Phase.ACTIVE then
            -- Leaving ACTIVE: freeze the player and clear all movement state.
            resetState()
            local hum = humanoid
            if hum then
                hum.WalkSpeed = 0
            end
        else
            -- Entering ACTIVE: restore walk speed. State was already reset when
            -- we left the previous phase, so sprint/crouch flags are clean.
            local hum = humanoid
            if hum then
                hum.WalkSpeed = Constants.WALK_SPEED
            end
        end
    end)
    table.insert(_connections, phaseConn)

    -- ── Input: Sprint (LeftShift) ─────────────────────────────────────────────
    -- Sprint is only active during ACTIVE phase and only when not crouching.
    -- Crouching overrides sprint — pressing Shift while crouched is ignored.

    local sprintBeginConn = UserInputService.InputBegan:Connect(
        function(input: InputObject, gp: boolean)
            if gp then return end
            if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
            if movementState.isCrouching then return end  -- sprint ignored while crouched
            movementState.isSprinting = true
            applySpeed()
        end
    )
    table.insert(_connections, sprintBeginConn)

    local sprintEndConn = UserInputService.InputEnded:Connect(
        function(input: InputObject, _gp: boolean)
            if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
            if not movementState.isSprinting then return end
            movementState.isSprinting = false
            applySpeed()
        end
    )
    table.insert(_connections, sprintEndConn)

    -- ── Input: Crouch (C toggle) ──────────────────────────────────────────────
    -- C toggles crouch during ACTIVE. Entering crouch clears sprint.
    -- Sprinting while crouched is not allowed (sprint begin handler guards this too).

    local crouchConn = UserInputService.InputBegan:Connect(
        function(input: InputObject, gp: boolean)
            if gp then return end
            if input.KeyCode ~= Enum.KeyCode.C then return end
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end

            movementState.isCrouching = not movementState.isCrouching
            if movementState.isCrouching then
                -- Entering crouch: clear sprint so applySpeed() picks CROUCH_SPEED.
                movementState.isSprinting = false
            end
            applySpeed()
        end
    )
    table.insert(_connections, crouchConn)

    -- ── Heartbeat: direction detection and speed maintenance ──────────────────
    -- Runs every physics step. Reads Humanoid.MoveDirection, classifies it into
    -- one of 9 named directions, updates movementState, and re-applies speed.
    -- Using Heartbeat (not RenderStepped) because direction detection is physics-
    -- step work with no camera or rendering dependency.

    local heartbeatConn = RunService.Heartbeat:Connect(function(_dt: number)
        local hum = humanoid
        if not hum then return end
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end

        local moveDir               = hum.MoveDirection
        movementState.moveVector    = moveDir
        movementState.isMoving      = moveDir.Magnitude > Constants.MOVEMENT_DIRECTION_DEADZONE
        movementState.directionName = classifyDirection(moveDir)

        -- Re-apply speed each tick so sprint speed activates as soon as isMoving
        -- becomes true after the player begins moving while Shift is held.
        applySpeed()
    end)
    table.insert(_connections, heartbeatConn)

    Logger.debug("[MovementController] Ready (Stage 1)")
end

return MovementController
