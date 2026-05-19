--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MovementController
--
-- Movement Stage 1 + 2A (with Animate-disable bug fix) — walk, sprint, crouch speed;
-- 8-direction camera-relative movement state; phase gating; respawn handling;
-- connection cleanup; R6 animation playback.
--
-- Bug fix (2026-05-18): The default Roblox Animate LocalScript inside the character
-- was overriding custom R6 AnimationTrack objects loaded in Stage 2A. MovementController
-- now calls disableDefaultAnimate() on every CharacterAdded — before loading custom
-- tracks — to stop the avatar animation pack from controlling locomotion.
-- This is gated by Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED and
-- Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT (both default true).
-- Animate is disabled, not destroyed, so it can be re-enabled if needed.
--
-- NOTE: disabling Animate removes idle, jump, fall, and climb animations in addition
-- to locomotion. Custom replacements for those states are needed in a future stage.
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
--   • Disabling character.Animate to prevent avatar animation pack override
--
-- Animation control constants (all in Constants.lua):
--   CUSTOM_MOVEMENT_ANIMATIONS_ENABLED = true       — master switch for custom anim system
--   DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = true — disables character.Animate
--   MOVEMENT_ANIMATION_DEBUG = true                 — logs load/switch events to Output
--
-- Camera rule (Stage 1 + 2A):
--   Reads workspace.CurrentCamera.CFrame for direction detection only.
--   Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
--   Does NOT add camera bob, sway, landing dip, tilt, or viewmodel effects.
--
-- Stage 2A animation scope (forward walk/run only):
--   Defaults to AR15 animation set (true armed/unarmed state deferred — see DEBT-050).
--   WalkLeft/WalkRight played if tracks exist; falls back to WalkForward if absent.
--   No crouch, backward, diagonal, reload, fire, or ADS animations in Stage 2A.
--   No lower-body/upper-body animation split in Stage 2A.
--   Non-R6 characters: animation loading skipped; Stage 1 speed logic remains active.
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
-- Typed AnimationTrack? so nil checks on absent keys are type-safe.
local animationTracks: { [string]: AnimationTrack? } = {}

-- Unparented Animation instances created during loadMovementAnimations().
-- Stored for explicit cleanup on respawn and in destroy().
local animationInstances: { [string]: Animation } = {}

-- The key currently being played, or "" when nothing is playing.
-- Guards against restarting the same track on every Heartbeat tick.
local currentAnimationName: string = ""

-- Whether a rig-type warning has already been issued for the current character.
-- Reset on each new character so future warnings are not suppressed.
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

-- Disables the default Roblox Animate LocalScript so the avatar animation pack no
-- longer controls locomotion. Custom tracks from loadMovementAnimations() will then
-- play without being overridden.
--
-- Only acts when both CUSTOM_MOVEMENT_ANIMATIONS_ENABLED and
-- DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT are true.
-- Disables Animate; does NOT destroy it and does NOT touch any other scripts.
--
-- Side effect: disabling Animate also removes idle, jump, fall, and climb animations.
-- Custom replacements for those states are needed in a future movement stage.
local function disableDefaultAnimate(character: Model)
    assert(character ~= nil, "[MovementController] disableDefaultAnimate: character is required")

    if Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED ~= true then return end

    if Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT ~= true then
        -- Animate is left running. Custom tracks may be overridden or blend unexpectedly
        -- with avatar animation pack locomotion. Set
        -- DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = true to resolve conflicts.
        return
    end

    local animate = character:FindFirstChild("Animate")
    if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
        animate.Disabled = true
        Logger.debug("[MovementController] default Animate script disabled for: " .. character.Name)
    end
end

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
-- MAINTENANCE (DEBT-050): Always returns "AR15" — true armed/unarmed state requires
-- server-owned equipment state (InventoryService or EquipmentService). When that
-- system exists, query it here and return "Unarmed" when no weapon is held.
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
-- Fades in over MOVEMENT_ANIMATION_FADE_TIME. No-ops if already playing that track.
-- Logs the switch if MOVEMENT_ANIMATION_DEBUG is true.
-- Warns and clears currentAnimationName if the requested key is absent.
local function playMovementAnimation(animationName: string)
    if currentAnimationName == animationName then return end  -- already playing; no restart needed

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] anim switch: ["
            .. (currentAnimationName == "" and "none" or currentAnimationName)
            .. "] → [" .. animationName .. "]"
        )
    end

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

-- Clears old animation state and loads all R6 movement AnimationTracks for the character.
-- Called from setupCharacter() on every spawn/respawn, after disableDefaultAnimate().
-- Skipped entirely if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is false.
-- Old AnimationTrack references are cleared (previous Animator may already be destroyed).
-- Old Animation instances are explicitly destroyed before new ones are created.
local function loadMovementAnimations(character: Model)
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end

    -- Clear stale track references. Do NOT :Stop() them — the previous Animator may
    -- already be destroyed, making those references unsafe to call.
    table.clear(animationTracks)
    currentAnimationName = ""
    rigTypeWarned        = false

    -- Destroy and clear old Animation instances from the previous character.
    for _, inst in pairs(animationInstances) do
        inst:Destroy()
    end
    table.clear(animationInstances)

    -- Rig type safety: only load R6 animations for R6 characters. Warn once per
    -- character so the log is not spammed from Heartbeat.
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

    -- Build the flat "SetName_AnimName" → AnimationTrack table.
    local r6 = Constants.MOVEMENT_ANIMATION_IDS.R6
    local toLoad: { [string]: string } = {
        ["Unarmed_WalkForward"] = r6.Unarmed.WalkForward,
        ["Unarmed_RunForward"]  = r6.Unarmed.RunForward,
        ["AR15_WalkForward"]    = r6.AR15.WalkForward,
        ["AR15_RunForward"]     = r6.AR15.RunForward,
    }

    for key, assetId in pairs(toLoad) do
        if assetId == nil or assetId == "" then
            -- Warn for missing or empty asset IDs — these may indicate an unloaded
            -- constant, a private asset, or a placeholder not yet replaced.
            Logger.warn("[MovementController] loadMovementAnimations: empty assetId for key: " .. key)
        else
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug("[MovementController] loading anim [" .. key .. "] = " .. assetId)
            end
            local animInstance       = Instance.new("Animation")
            animInstance.AnimationId = assetId
            animationInstances[key]  = animInstance
            local track              = animator:LoadAnimation(animInstance)
            track.Looped             = true
            animationTracks[key]     = track
        end
    end

    Logger.debug("[MovementController] R6 movement animations loaded for: " .. character.Name)
end

-- Selects and triggers the correct movement animation for the current movementState.
-- Called every Heartbeat tick during ACTIVE phase.
-- Skipped if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is false.
-- currentAnimationName guard prevents restarting the same track every frame.
--
-- Stage 2A scope:
--   WalkLeft/WalkRight played if present in animationTracks; falls back to WalkForward.
--   Crouch animation not implemented; crouching uses WalkForward at CROUCH_SPEED.
--   Backward, diagonal directions also fall back to WalkForward in Stage 2A.
local function updateMovementAnimation()
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end
    if next(animationTracks) == nil then return end

    -- Stop if not moving.
    if not movementState.isMoving then
        stopCurrentMovementAnimation()
        return
    end

    local setName = getAnimationSetName()   -- "AR15" or "Unarmed" (currently always "AR15")
    local dirName = movementState.directionName
    local animName: string

    if movementState.isSprinting then
        animName = setName .. "_RunForward"

    elseif dirName == "Left" or dirName == "ForwardLeft" or dirName == "BackwardLeft" then
        -- Attempt left-strafe; fall back to WalkForward if not loaded in Stage 2A.
        local leftKey   = setName .. "_WalkLeft"
        local leftTrack = animationTracks[leftKey]
        animName = if leftTrack ~= nil then leftKey else (setName .. "_WalkForward")

    elseif dirName == "Right" or dirName == "ForwardRight" or dirName == "BackwardRight" then
        -- Attempt right-strafe; fall back to WalkForward if not loaded in Stage 2A.
        local rightKey   = setName .. "_WalkRight"
        local rightTrack = animationTracks[rightKey]
        animName = if rightTrack ~= nil then rightKey else (setName .. "_WalkForward")

    else
        -- Forward, Backward, or Idle-magnitude directions → WalkForward.
        animName = setName .. "_WalkForward"
    end

    playMovementAnimation(animName)
end

-- ============================================================
-- setupCharacter
-- ============================================================

-- Called on every CharacterAdded. Re-acquires the Humanoid reference, resets
-- movementState, applies the phase-appropriate WalkSpeed immediately, disables the
-- default Animate script, then loads R6 movement animations (Stage 2A layer).
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

    -- Disable the default Animate script before loading custom tracks.
    -- Order matters: Animate must be disabled first so it cannot start playing
    -- avatar locomotion animations that would override custom tracks.
    disableDefaultAnimate(char)

    -- Load R6 movement animations. Skipped if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is
    -- false, rig is not R6, or Animator is missing. Stage 1 speed logic is unaffected.
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
-- PivotTo composition is unaffected. Future stages compose bob, tilt, and sway
-- here without changing ViewModelController's call site.
function MovementController:GetViewmodelAddCFrame(): CFrame
    return CFrame.new()
end

-- Disconnects all event connections, stops all animation tracks, destroys Animation
-- instances, and resets all state.
-- Safe to call even if Start() was never called (iterates empty tables).
function MovementController:destroy()
    -- Stop the active animation if still playing, then clear track references.
    stopCurrentMovementAnimation()
    table.clear(animationTracks)
    currentAnimationName = ""
    rigTypeWarned        = false

    -- Explicitly destroy Animation instances.
    for _, inst in pairs(animationInstances) do
        inst:Destroy()
    end
    table.clear(animationInstances)

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
    -- Re-acquires Humanoid, resets state, disables Animate, and loads animations.
    local charConn = localPlayer.CharacterAdded:Connect(function(char: Model)
        setupCharacter(char)
    end)
    table.insert(_connections, charConn)

    -- ── RoundStateChanged ─────────────────────────────────────────────────────
    -- Mirrors the phase into movementState and WalkSpeed.
    local phaseConn = RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local phase   = payload.phase

        if phase ~= Constants.Phase.ACTIVE then
            -- Leaving ACTIVE: freeze the player, clear movement state, stop animation.
            resetState()
            stopCurrentMovementAnimation()
            local hum = humanoid
            if hum then
                hum.WalkSpeed = 0
            end
        else
            -- Entering ACTIVE: restore walk speed.
            local hum = humanoid
            if hum then
                hum.WalkSpeed = Constants.WALK_SPEED
            end
        end
    end)
    table.insert(_connections, phaseConn)

    -- ── Input: Sprint (LeftShift) ─────────────────────────────────────────────
    local sprintBeginConn = UserInputService.InputBegan:Connect(
        function(input: InputObject, gp: boolean)
            if gp then return end
            if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
            if movementState.isCrouching then return end
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
    local crouchConn = UserInputService.InputBegan:Connect(
        function(input: InputObject, gp: boolean)
            if gp then return end
            if input.KeyCode ~= Enum.KeyCode.C then return end
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end

            movementState.isCrouching = not movementState.isCrouching
            if movementState.isCrouching then
                movementState.isSprinting = false
            end
            applySpeed()
        end
    )
    table.insert(_connections, crouchConn)

    -- ── Heartbeat: direction detection, speed maintenance, animation update ────
    -- Runs every physics step. Updates movementState, re-applies speed, and drives
    -- the Stage 2A animation layer. No camera writes.
    local heartbeatConn = RunService.Heartbeat:Connect(function(_dt: number)
        local hum = humanoid
        if not hum then return end
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end

        local moveDir               = hum.MoveDirection
        movementState.moveVector    = moveDir
        movementState.isMoving      = moveDir.Magnitude > Constants.MOVEMENT_DIRECTION_DEADZONE
        movementState.directionName = classifyDirection(moveDir)

        applySpeed()

        -- Stage 2A: select and play the correct walk/run animation.
        updateMovementAnimation()
    end)
    table.insert(_connections, heartbeatConn)

    Logger.debug("[MovementController] Ready (Stage 1 + Stage 2A)")
end

return MovementController
