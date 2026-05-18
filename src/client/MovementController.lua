--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MovementController
--
-- Owns all character movement feel on the client:
--   • Speed management: sets Humanoid.WalkSpeed based on stance/state
--   • Sprint (Left Shift), Crouch (C toggle), Slide (C while sprinting)
--   • Vault: auto step-up over obstacles 0.5–2.5 studs high, cast every 0.1 s
--   • 13-state animation machine driven by velocity direction relative to camera
--   • Camera bob: sine wave on HumanoidRootPart.CameraOffset while moving
--   • Crouch height tween: CameraOffset.Y eased to CROUCH_CAM_OFFSET on crouch
--   • Landing dip: CameraOffset.Y nudged down then eased back on landing
--   • Viewmodel sway/tilt: returned via GetViewmodelAddCFrame() for ViewModelController
--   • Phase awareness: movement features only during ACTIVE; reset on other phases
--
-- Exposes:
--   GetMoveState(): string      — current MoveState enum value; read by GunController for spread
--   IsADSBlocked(): boolean     — true while sprinting (ADS not allowed)
--   GetViewmodelAddCFrame(): CFrame — combined bob/sway/tilt CFrame for ViewModelController
--   Start()                     — called by ClientInit after MatchController:Start()
--
-- Animation IDs are all 0 (placeholder). Replace with real asset IDs and remove
-- the skip-if-zero guard. See DEBT-044.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules        = ReplicatedStorage:WaitForChild("Modules")
local Constants      = require(Modules:WaitForChild("Constants"))
local Logger         = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

-- Placeholder animation IDs. Set to real Roblox animation asset IDs.
-- Tracks with ID == 0 will not be loaded or played (guarded in loadAnims). DEBT-044.
local ANIM_IDS: { [string]: number } = {
    Idle           = 0,
    WalkForward    = 0,
    WalkBack       = 0,
    WalkLeft       = 0,
    WalkRight      = 0,
    WalkDiagFL     = 0,
    WalkDiagFR     = 0,
    WalkDiagBL     = 0,
    WalkDiagBR     = 0,
    Sprint         = 0,
    CrouchIdle     = 0,
    CrouchWalk     = 0,
    Slide          = 0,
}

-- Camera bob parameters.
local BOB_FREQ_WALK   : number = 9    -- oscillations per second while walking
local BOB_FREQ_SPRINT : number = 13   -- oscillations per second while sprinting
local BOB_AMP_WALK    : number = 0.07 -- studs of vertical travel while walking
local BOB_AMP_SPRINT  : number = 0.11 -- studs of vertical travel while sprinting
local BOB_DECAY       : number = 10   -- lerp speed (per second) back to zero when idle

-- Crouch camera height offset in studs (negative = camera drops).
local CROUCH_CAM_OFFSET : number = -1.4
local CROUCH_TWEEN_TIME : number = 0.15 -- seconds to reach crouch height

-- Landing dip: camera drops this far on landing then eases back.
local LAND_DIP_DIST  : number = 0.3  -- studs downward on impact
local LAND_DIP_TIME  : number = 0.08 -- seconds to reach full dip
local LAND_RISE_TIME : number = 0.2  -- seconds to rise back to rest

-- Slide tilt: viewmodel rolls this many degrees during a slide.
local SLIDE_TILT_DEG  : number = 8   -- degrees of roll on viewmodel while sliding
local SLIDE_TILT_RATE : number = 12  -- lerp speed (per second) for tilt in/out

-- Vault parameters.
local VAULT_INTERVAL     : number = 0.1  -- seconds between vault raycasts
local VAULT_MIN_HEIGHT   : number = 0.5  -- minimum obstacle height (studs) to vault
local VAULT_MAX_HEIGHT   : number = 2.5  -- maximum obstacle height (studs) to vault
local VAULT_TWEEN_TIME   : number = 0.2  -- seconds to complete a vault step-up
local VAULT_FORWARD_DIST : number = 1.8  -- studs in front of HRP to cast the vault ray

-- Velocity threshold below which the player is considered idle.
local MOVING_THRESHOLD : number = 0.5

-- ============================================================
-- Enums
-- ============================================================

-- Stance: body posture (affects camera height and animation layer).
local Stance = {
    Standing  = "Standing",
    Crouching = "Crouching",
}

-- MoveState: locomotion category; read externally by GunController for spread.
local MoveState = {
    Idle      = "Idle",
    Walking   = "Walking",
    Sprinting = "Sprinting",
    Crouching = "Crouching",
    Sliding   = "Sliding",
}

-- ============================================================
-- State
-- ============================================================

local currentPhase    : string  = Constants.Phase.LOBBY
local currentStance   : string  = Stance.Standing
local currentMoveState: string  = MoveState.Idle

local isSprinting     : boolean = false
local isSliding       : boolean = false
local slideTimer      : number  = 0
local slideCooldown   : number  = 0

-- Camera bob
local bobTime         : number  = 0
local bobY            : number  = 0  -- current vertical bob offset applied to CameraOffset

-- Camera height offset (0 = standing, CROUCH_CAM_OFFSET = crouching)
local camHeightOffset : number  = 0

-- Landing dip
local landDipOffset   : number  = 0
local wasGrounded     : boolean = true

-- Viewmodel sway/tilt
local currentSlideTilt: number  = 0  -- current roll in radians

-- Animation state machine
local animTracks     : { [string]: AnimationTrack? } = {}
local currentAnimState: string = ""

-- Character references (refreshed on CharacterAdded)
local character  : Model?          = nil
local humanoid   : Humanoid?       = nil
local rootPart   : BasePart?       = nil

-- ============================================================
-- Controller
-- ============================================================

local MovementController = {}

-- ── Getters ───────────────────────────────────────────────────────────────────

function MovementController:GetMoveState(): string
    return currentMoveState
end

function MovementController:IsADSBlocked(): boolean
    return isSprinting or isSliding
end

-- Returns a CFrame that ViewModelController multiplies into its PivotTo call each frame.
-- Encodes vertical bob displacement and slide tilt roll.
-- Safe to call before Start() — returns identity by default.
function MovementController:GetViewmodelAddCFrame(): CFrame
    -- Vertical bob offset: shift viewmodel up/down with the camera bob.
    -- Slide roll: roll the viewmodel on the Z axis while sliding.
    return CFrame.new(0, bobY * 0.6, 0) * CFrame.Angles(0, 0, currentSlideTilt)
end

-- ── Animation helpers ─────────────────────────────────────────────────────────

-- Loads all animation tracks from the Animator. Called after each CharacterAdded.
-- Skips IDs == 0 (placeholder guard). DEBT-044.
local function loadAnims(anim: Animator)
    animTracks    = {}
    currentAnimState = ""
    for name, id in pairs(ANIM_IDS) do
        if id ~= 0 then
            local animInstance = Instance.new("Animation")
            animInstance.AnimationId = "rbxassetid://" .. tostring(id)
            local ok, track = pcall(function()
                return anim:LoadAnimation(animInstance)
            end)
            if ok and track then
                animTracks[name] = track :: AnimationTrack
            else
                Logger.warn("[MovementController] Failed to load animation: " .. name)
            end
            animInstance:Destroy()
        end
    end
end

-- Transitions to a new animation state with a crossfade. No-ops if already in that state.
local function playAnim(stateName: string)
    if stateName == currentAnimState then return end
    local prevTrack = animTracks[currentAnimState]
    if prevTrack and prevTrack.IsPlaying then
        prevTrack:Stop(0.15)
    end
    currentAnimState = stateName
    local track = animTracks[stateName]
    if track then
        track:Play(0.15)
    end
end

-- ── Direction classification ──────────────────────────────────────────────────

-- Maps a horizontal velocity vector to one of the 8-directional animation states.
-- Dot products against camera forward/right vectors yield signed [-1,1] scalars;
-- diagonal threshold 0.35 picks diagonals when both axes are meaningfully active.
local function classifyDirection(vel: Vector3, cam: Camera): string
    local camFlat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
    if camFlat.Magnitude < 0.01 then return "WalkForward" end
    camFlat = camFlat.Unit
    local camRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit

    local fwd   = vel:Dot(camFlat)
    local right = vel:Dot(camRight)
    local diag  = 0.35

    if fwd > 0 and math.abs(right) <= diag then
        return "WalkForward"
    elseif fwd < 0 and math.abs(right) <= diag then
        return "WalkBack"
    elseif right > 0 and math.abs(fwd) <= diag then
        return "WalkRight"
    elseif right < 0 and math.abs(fwd) <= diag then
        return "WalkLeft"
    elseif fwd > 0 and right > 0 then
        return "WalkDiagFR"
    elseif fwd > 0 and right < 0 then
        return "WalkDiagFL"
    elseif fwd < 0 and right > 0 then
        return "WalkDiagBR"
    else
        return "WalkDiagBL"
    end
end

-- ── Speed setter ──────────────────────────────────────────────────────────────

local function applySpeed(speed: number)
    local hum = humanoid
    if hum then
        hum.WalkSpeed = speed
    end
end

-- ── Stance transitions ────────────────────────────────────────────────────────

local function applyCrouchHeight(crouching: boolean)
    local target = crouching and CROUCH_CAM_OFFSET or 0
    local info   = TweenInfo.new(CROUCH_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    -- Tween the camHeightOffset variable toward target each RenderStepped instead of TweenService,
    -- because CameraOffset is set every frame (a Tween would fight the RenderStepped assignment).
    -- We use a simple lerp target stored in camHeightOffset for the RenderStepped to pull toward.
    camHeightOffset = target
    _ = info  -- suppress unused warning; kept for future TweenService migration if camera changes
end

-- ── Slide ────────────────────────────────────────────────────────────────────

local function startSlide()
    if isSliding or slideCooldown > 0 then return end
    isSliding  = true
    slideTimer = Constants.SLIDE_DURATION
    currentMoveState = MoveState.Sliding
    applySpeed(Constants.SLIDE_SPEED)
    applyCrouchHeight(true)
    playAnim("Slide")
    Logger.debug("[MovementController] Slide started")
end

local function endSlide()
    isSliding = false
    slideCooldown = Constants.SLIDE_COOLDOWN
    -- Land in crouch if C is still held, otherwise stand.
    if currentStance == Stance.Crouching then
        currentMoveState = MoveState.Crouching
        applySpeed(Constants.CROUCH_SPEED)
    else
        currentMoveState = MoveState.Idle
        applySpeed(Constants.WALK_SPEED)
        applyCrouchHeight(false)
    end
    Logger.debug("[MovementController] Slide ended")
end

-- ── Vault ────────────────────────────────────────────────────────────────────

local vaultTimer: number = 0

local function tryVault()
    local root = rootPart
    if not root then return end
    local cam  = workspace.CurrentCamera
    local fwd  = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
    if fwd.Magnitude < 0.01 then return end
    fwd = fwd.Unit

    -- Cast from slightly above root toward the obstacle face.
    local origin = root.Position + Vector3.new(0, VAULT_MAX_HEIGHT, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character :: Instance }

    -- Downward cast a short distance forward to find the top of the obstacle.
    local downResult = workspace:Raycast(
        origin + fwd * VAULT_FORWARD_DIST,
        Vector3.new(0, -(VAULT_MAX_HEIGHT + 0.5), 0),
        params
    )
    if not downResult then return end

    local hitY    = downResult.Position.Y
    local rootY   = root.Position.Y - (root.Size.Y / 2)  -- base of character
    local stepH   = hitY - rootY

    if stepH >= VAULT_MIN_HEIGHT and stepH <= VAULT_MAX_HEIGHT then
        -- Smooth step-up: tween root position upward.
        local newPos = root.Position + Vector3.new(0, stepH, 0)
        local info   = TweenInfo.new(VAULT_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        TweenService:Create(root, info, { CFrame = root.CFrame + Vector3.new(0, stepH, 0) }):Play()
        Logger.debug(string.format("[MovementController] Vault: %.2f studs", stepH))
        _ = newPos  -- suppress unused warning
    end
end

-- ── Landing detection ────────────────────────────────────────────────────────

local function onHumanoidStateChanged(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
    if new == Enum.HumanoidStateType.Landed then
        -- Apply a quick camera dip to sell the landing impact.
        local dipInfo  = TweenInfo.new(LAND_DIP_TIME,  Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        local riseInfo = TweenInfo.new(LAND_RISE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        _ = dipInfo
        _ = riseInfo
        -- Set via the landDipOffset variable; RenderStepped applies it to CameraOffset.
        landDipOffset = -LAND_DIP_DIST
        task.delay(LAND_DIP_TIME, function()
            landDipOffset = 0
        end)
    end
end

-- ── Character setup ──────────────────────────────────────────────────────────

local function setupCharacter(char: Model)
    character = char
    humanoid  = char:WaitForChild("Humanoid") :: Humanoid
    rootPart  = char:WaitForChild("HumanoidRootPart") :: BasePart

    -- Reset all state so leftover values from a previous life don't persist.
    isSprinting       = false
    isSliding         = false
    slideTimer        = 0
    slideCooldown     = 0
    bobTime           = 0
    bobY              = 0
    camHeightOffset   = 0
    landDipOffset     = 0
    currentSlideTilt  = 0
    currentMoveState  = MoveState.Idle
    currentStance     = Stance.Standing

    applySpeed(Constants.WALK_SPEED)

    -- Connect landing detection.
    humanoid.StateChanged:Connect(onHumanoidStateChanged)

    -- Load animations.
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        loadAnims(animator)
    else
        Logger.warn("[MovementController] No Animator found on Humanoid — animations unavailable")
    end

    Logger.debug("[MovementController] Character set up: " .. char.Name)
end

-- ============================================================
-- Start
-- ============================================================

function MovementController:Start()
    local localPlayer = Players.LocalPlayer

    -- Set up for any character already present (rare but possible on re-require).
    if localPlayer.Character then
        setupCharacter(localPlayer.Character)
    end

    localPlayer.CharacterAdded:Connect(function(char: Model)
        setupCharacter(char)
    end)

    -- ── Phase listener ────────────────────────────────────────────────────────
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        currentPhase = payload.phase
        if currentPhase ~= Constants.Phase.ACTIVE then
            -- Reset movement state so the next ACTIVE starts clean.
            isSprinting      = false
            isSliding        = false
            slideTimer       = 0
            slideCooldown    = 0
            currentStance    = Stance.Standing
            currentMoveState = MoveState.Idle
            camHeightOffset  = 0
            applySpeed(Constants.WALK_SPEED)
        end
    end)

    -- ── Input: Sprint ─────────────────────────────────────────────────────────
    UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
        if gp then return end
        if currentPhase ~= Constants.Phase.ACTIVE then return end
        if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
        if isSliding then return end
        isSprinting    = true
        currentStance  = Stance.Standing
        currentMoveState = MoveState.Sprinting
        camHeightOffset  = 0
        applySpeed(Constants.SPRINT_SPEED)
    end)

    UserInputService.InputEnded:Connect(function(input: InputObject, _gp: boolean)
        if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
        if not isSprinting then return end
        isSprinting = false
        if currentStance == Stance.Crouching then
            currentMoveState = MoveState.Crouching
            applySpeed(Constants.CROUCH_SPEED)
        else
            currentMoveState = MoveState.Idle
            applySpeed(Constants.WALK_SPEED)
        end
    end)

    -- ── Input: Crouch / Slide ─────────────────────────────────────────────────
    UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
        if gp then return end
        if currentPhase ~= Constants.Phase.ACTIVE then return end
        if input.KeyCode ~= Enum.KeyCode.C then return end

        if isSprinting and not isSliding then
            -- Slide while sprinting.
            startSlide()
        elseif not isSliding then
            -- Toggle crouch.
            if currentStance == Stance.Standing then
                currentStance    = Stance.Crouching
                currentMoveState = MoveState.Crouching
                applyCrouchHeight(true)
                applySpeed(Constants.CROUCH_SPEED)
            else
                currentStance    = Stance.Standing
                currentMoveState = MoveState.Idle
                applyCrouchHeight(false)
                applySpeed(Constants.WALK_SPEED)
            end
        end
    end)

    -- ── RenderStepped ─────────────────────────────────────────────────────────
    RunService.RenderStepped:Connect(function(dt: number)
        local root = rootPart
        local hum  = humanoid
        if not root or not hum then return end

        -- ── Slide timer ───────────────────────────────────────────────────────
        if isSliding then
            slideTimer = slideTimer - dt
            if slideTimer <= 0 then
                endSlide()
            end
        end
        if slideCooldown > 0 then
            slideCooldown = math.max(0, slideCooldown - dt)
        end

        -- ── Velocity-based state & animation ─────────────────────────────────
        if not isSliding and currentPhase == Constants.Phase.ACTIVE then
            local vel      = root.AssemblyLinearVelocity
            local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

            if flatSpeed > MOVING_THRESHOLD then
                if isSprinting then
                    currentMoveState = MoveState.Sprinting
                    playAnim("Sprint")
                elseif currentStance == Stance.Crouching then
                    currentMoveState = MoveState.Crouching
                    playAnim("CrouchWalk")
                else
                    currentMoveState = MoveState.Walking
                    local dirAnim = classifyDirection(vel, workspace.CurrentCamera)
                    playAnim(dirAnim)
                end
            else
                if currentStance == Stance.Crouching then
                    currentMoveState = MoveState.Crouching
                    playAnim("CrouchIdle")
                else
                    currentMoveState = MoveState.Idle
                    playAnim("Idle")
                end
            end
        end

        -- ── Camera bob ────────────────────────────────────────────────────────
        local vel      = root.AssemblyLinearVelocity
        local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        local isMoving  = flatSpeed > MOVING_THRESHOLD

        if isMoving and currentPhase == Constants.Phase.ACTIVE then
            local freq = isSprinting and BOB_FREQ_SPRINT or BOB_FREQ_WALK
            local amp  = isSprinting and BOB_AMP_SPRINT  or BOB_AMP_WALK
            bobTime = bobTime + dt * freq
            bobY    = math.sin(bobTime) * amp
        else
            -- Decay bob back to zero.
            bobY = bobY - bobY * math.min(1, dt * BOB_DECAY)
            if math.abs(bobY) < 0.001 then
                bobY    = 0
                bobTime = 0
            end
        end

        -- ── Slide tilt (viewmodel roll) ───────────────────────────────────────
        local targetTilt = isSliding and math.rad(SLIDE_TILT_DEG) or 0
        local tiltDelta  = targetTilt - currentSlideTilt
        currentSlideTilt = currentSlideTilt + tiltDelta * math.min(1, dt * SLIDE_TILT_RATE)

        -- ── CameraOffset assembly ─────────────────────────────────────────────
        -- Lerp toward camHeightOffset so the crouch transition is smooth.
        local currentHeight = root.CFrame.Position.Y  -- unused but documents intent
        _ = currentHeight
        local targetCamY = camHeightOffset + landDipOffset
        local camOffset  = root:FindFirstChild("CameraOffset")
        -- Apply via Humanoid.CameraOffset (the correct Roblox property for this).
        local curOffset  = hum.CameraOffset
        local newY       = curOffset.Y + (targetCamY - curOffset.Y) * math.min(1, dt * (1 / CROUCH_TWEEN_TIME))
        hum.CameraOffset = Vector3.new(curOffset.X, newY + bobY, curOffset.Z)
        _ = camOffset

        -- ── Vault check ───────────────────────────────────────────────────────
        if not isSliding and currentPhase == Constants.Phase.ACTIVE then
            vaultTimer = vaultTimer - dt
            if vaultTimer <= 0 then
                vaultTimer = VAULT_INTERVAL
                if isMoving then
                    tryVault()
                end
            end
        end
    end)

    Logger.debug("[MovementController] Ready")
end

return MovementController
