--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MovementController
--
-- Movement Stage 1 + 2A — walk, sprint, crouch speed; 8-direction camera-relative
-- movement state; phase gating; respawn handling; connection cleanup.
-- Stage 2A adds R6 walk/run animation playback for armed (AR15) and unarmed movement.
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
--   • R6 walk/run AnimationTracks loaded per character, played during ACTIVE phase only
--
-- Camera rule (Stage 1 + 2A):
--   Reads workspace.CurrentCamera.CFrame for direction detection only.
--   Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
--   Does NOT add camera bob, sway, landing dip, tilt, or viewmodel effects.
--
-- Stage 2A animation scope (forward walk/run only):
--   Plays the AR15 or Unarmed animation set based on weapon state.
--   Current prototype defaults to AR15 set (true armed/unarmed state deferred — see DEBT-050).
--   Only WalkForward and RunForward exist in Stage 2A.
--   No crouch, strafe, backward, diagonal, reload, fire, or ADS animations in this stage.
--   No lower-body/upper-body animation split in this stage.
--   If the character is not R6, animation loading is skipped safely; Stage 1 speed
--   logic remains fully active regardless.
--
-- Not in Stage 1/2A: slide, vault, stamina, prone, footsteps, crouch body lowering,
--   camera height changes, viewmodel sway, strafe/backward/diagonal animations.
--
-- Exposes:
--   GetMovementState()           → movementState table (all fields read-only for callers)
--   GetMoveState(): string       → "Idle"|"Walking"|"Sprinting"|"Crouching" (GunController compat)
--   IsADSBlocked(): boolean      → true while sprinting; blocks GunController ADS
--   GetViewmodelAddCFrame(): CFrame → identity in Stage 1/2A; ViewModelController multiplies this in
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

-- ── Stage 2A animation state ──────────────────────────────────────────────────

-- AnimationTrack table keyed by "SetName_AnimName" (e.g. "AR15_WalkForward").
-- Populated by loadMovementAnimations(); cleared on character respawn and destroy().
local animationTracks: { [string]: AnimationTrack } = {}

-- The key currently being played, or "" when nothing is playing.
-- Used to avoid restarting the same animation every Heartbeat tick.
local currentAnimationName: string = ""

-- Whether a rig-type warning has already been issued for the current character.
-- Reset each time a new character is set up to avoid suppressing future warnings.
local rigTypeWarned: boolean = false

-- ============================================================
-- Private helpers — Stage 1
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

-- ============================================================
-- Private helpers — Stage 2A: animation
-- ============================================================

-- Finds the Animator inside a character's Humanoid.
-- Returns nil and warns if not found; all callers skip animation and continue safely.
local function getAnimator(character: Model): Animator?
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then
        Logger.warn("[MovementController] getAnimator: no Humanoid in character")
        return nil
    end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        Logger.warn("[MovementController] getAnimator: no Animator in Humanoid")
        return nil
    end
    return animator
end

-- Returns the animation set name for the player's current weapon.
-- MAINTENANCE (DEBT-050): This prototype always returns "AR15" because true
-- armed/unarmed state is not yet owned by the client — it requires server-owned
-- equipment state (InventoryService or EquipmentService). When that system exists,
-- query the equipped weapon here and return "Unarmed" when no weapon is held.
local function getAnimationSetName(): string
    return "AR15"
end

-- Stops the currently playing movement animation with a fade-out.
-- Safe to call when nothing is playing (currentAnimationName == "").
local function stopCurrentMovementAnimation()
    if currentAnimationName == "" then return end
    local track = animationTracks[currentAnimationName]
    if track then
        track:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
    end
    currentAnimationName = ""
end

-- Plays the named animation track (key format: "SetName_AnimName", e.g. "AR15_WalkForward").
-- Fades in over MOVEMENT_ANIMATION_FADE_TIME. No-ops if the same track is already playing.
-- Warns and clears currentAnimationName if the requested key is absent from animationTracks.
local function playMovementAnimation(animationName: string)
    if currentAnimationName == animationName then return end  -- already playing; no switch needed

    -- Fade out the previous animation.
    if currentAnimationName ~= "" then
        local prevTrack = animationTracks[currentAnimationName]
        if prevTrack then
            prevTrack:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
        end
    end

    local track = animationTracks[animationName]
    if not track then
        Logger.warn("[MovementController] playMovementAnimation: track not loaded: " .. animationName)
        currentAnimationName = ""
        return
    end

    track:Play(Constants.MOVEMENT_ANIMATION_FADE_TIME)
    currentAnimationName = animationName
end

-- Clears and reloads all R6 movement AnimationTracks for the given character.
-- Called from setupCharacter() on every spawn/respawn.
--
-- Old tracks are safe to abandon without explicit :Stop()/:Destroy() — Roblox stops
-- and cleans up all AnimationTracks automatically when the Animator is destroyed
-- with the outgoing character. Calling methods on those stale references is unsafe.
local function loadMovementAnimations(character: Model)
    -- Clear the previous character's stale track references.
    -- Do NOT :Stop() them — the previous Animator may already be destroyed.
    table.clear(animationTracks)
    currentAnimationName = ""
    rigTypeWarned        = false

    -- Rig type safety: only load R6 animations for R6 characters.
    -- Warn once per character so the log is not spammed from Heartbeat.
    local hum = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not hum then
        Logger.warn("[MovementController] loadMovementAnimations: no Humanoid — skipping")
        return
    end
    if hum.RigType ~= Enum.HumanoidRigType.R6 then
        rigTypeWarned = true
        Logger.warn(
            "[MovementController] Character rig is not R6 — R6 movement animations skipped. "
            .. "Stage 1 speed/direction logic remains active."
        )
        return
    end

    local animator = getAnimator(character)
    if not animator then return end

    -- Build the flat "SetName_AnimName" → AnimationTrack table for all four clips.
    local r6 = Constants.MOVEMENT_ANIMATION_IDS.R6
    local toLoad: { [string]: string } = {
        ["Unarmed_WalkForward"] = r6.Unarmed.WalkForward,
        ["Unarmed_RunForward"]  = r6.Unarmed.RunForward,
        ["AR15_WalkForward"]    = r6.AR15.WalkForward,
        ["AR15_RunForward"]     = r6.AR15.RunForward,
    }

    for key, assetId in pairs(toLoad) do
        local animInstance       = Instance.new("Animation")
        animInstance.AnimationId = assetId
        local track              = animator:LoadAnimation(animInstance)
        track.Looped             = true
        animationTracks[key]     = track
    end

    Logger.debug("[MovementController] R6 movement animations loaded for: " .. character.Name)
end

-- Selects and triggers the correct movement animation based on the current movementState.
-- Called every Heartbeat tick during ACTIVE phase. Uses currentAnimationName tracking
-- to avoid restarting the same track every frame.
--
-- Stage 2A scope:
--   Only WalkForward and RunForward are implemented. For non-Forward directions
--   (strafe, backward, diagonal), WalkForward is used as a fallback — this is the
--   simpler option; Stage 2B will add per-direction clips.
--   Crouch animation is not implemented; crouching uses WalkForward at CROUCH_SPEED
--   until a dedicated crouch-walk clip is added in a future stage.
local function updateMovementAnimation()
    -- Nothing to animate if tracks were not loaded (non-R6 rig or missing Animator).
    if next(animationTracks) == nil then return end

    -- Stop if not moving.
    if not movementState.isMoving then
        stopCurrentMovementAnimation()
        return
    end

    -- Select animation: sprinting → RunForward, otherwise → WalkForward.
    -- WalkForward also covers strafe, backward, and diagonal directions in Stage 2A.
    local setName  = getAnimationSetName()  -- "AR15" or "Unarmed" (currently always "AR15")
    local animName: string
    if movementState.isSprinting then
        animName = setName .. "_RunForward"
    else
        animName = setName .. "_WalkForward"  -- fallback for all non-sprint movement directions
    end

    playMovementAnimation(animName)
end

-- ============================================================
-- setupCharacter
-- ============================================================

-- Called on every CharacterAdded. Re-acquires the Humanoid reference, resets
-- movementState, applies the phase-appropriate WalkSpeed immediately, and loads
-- R6 movement animations for the new character (Stage 2A layer).
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

    -- Stage 2A: load R6 movement animations for this character.
    -- Skipped safely if rig is not R6; Stage 1 speed logic always runs regardless.
    loadMovementAnimations(char)

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
-- Kept alongside GetMovementState() so GunController does not need changes in Stage 1/2A.
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

-- Stage 1/2A: no viewmodel effects. Returns identity so ViewModelController's
-- PivotTo composition is unaffected. Future stages will compose bob, tilt,
-- and sway here without changing ViewModelController's call site.
function MovementController:GetViewmodelAddCFrame(): CFrame
    return CFrame.new()
end

-- Disconnects all event connections, stops all animation tracks, and resets all state.
-- Safe to call even if Start() was never called (iterates empty tables).
function MovementController:destroy()
    -- Stage 2A: stop the active animation (if any) and clear the track table.
    -- The character may or may not still be alive at this point; :Stop() is safe
    -- as long as we hold a live reference (animationTracks keeps references alive).
    stopCurrentMovementAnimation()
    table.clear(animationTracks)
    currentAnimationName = ""
    rigTypeWarned        = false

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
    -- Re-acquires Humanoid, resets state, and loads animations on every respawn.
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
            -- Leaving ACTIVE: freeze the player, clear all movement state, and
            -- stop any playing movement animation (Stage 2A).
            resetState()
            stopCurrentMovementAnimation()
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

    -- ── Heartbeat: direction detection, speed maintenance, animation update ────
    -- Runs every physics step. Reads Humanoid.MoveDirection, classifies it into
    -- one of 9 named directions, updates movementState, re-applies speed, and
    -- calls updateMovementAnimation() for the Stage 2A animation layer.
    -- Using Heartbeat (not RenderStepped) because this is physics-step work
    -- with no camera or rendering dependency.

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

        -- Stage 2A: select and play the correct walk/run animation.
        updateMovementAnimation()
    end)
    table.insert(_connections, heartbeatConn)

    Logger.debug("[MovementController] Ready (Stage 1 + Stage 2A)")
end

return MovementController
