--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ViewModelController
--
-- Owns the client-side first-person viewmodel.
--
-- Weapon equip / holster (AKS74 foundation — 2026-05-28):
--   EquipWeapon(weaponName) clones ReplicatedStorage/ViewModels/<viewModelName> and parents it to
--   workspace.CurrentCamera.  The weapon stays holstered (self.model == nil) until EquipWeapon is
--   called.  GunController calls EquipWeapon / HolsterWeapon in response to key 1 input.
--   PlayEquipAnimation() plays the first-person equip track once, then chains into PlayIdleAnimation().
--   If the equip track is absent, PlayIdleAnimation() starts immediately.
--   StopWeaponAnimations() stops and destroys all loaded weapon AnimationTracks.
--   HolsterWeapon() stops animations, destroys the model clone, and clears all equip state.
--
-- PivotTo camera follow (every RenderStepped, only when self.model is non-nil):
--   m:PivotTo(cam.CFrame * CAMERA_EXTRA_OFFSET * cameraInertiaCF * movementInertiaCF * viewRecoilCFrame
--             * vmRecoilCF * freeAimCF * swayCF * finalMoveCF * BASE_OFFSET * CFrame.new(0,0,recoilOffset))
--   CAMERA_EXTRA_OFFSET — constant base offset from the camera reference point (hipfire).
--   cameraInertiaCF     — camera-turn inertia lag (viewmodel-only; excluded from ADS pivot).
--   movementInertiaCF   — movement velocity inertia lag (viewmodel-only; excluded from ADS pivot).
--   swayCF — procedural sway: mouse lag, movement bob, strafe roll (weight ADS≈0/hip=100%).
--   No code-level ADS alignment offset: the ADS animation positions the iron sights.
--   BASE_OFFSET is computed from the rig's FakeCamera CFrame relative to HumanoidRootPart.
--   Falls back to REAL_MODEL_OFFSET when FakeCamera is absent.
--   Positional recoil (RECOIL_DIST) and camera-relative recoil CFrame (from GunController) are
--   both applied here; they operate on whatever model is currently equipped.
--
-- Visibility:
--   shouldShowViewModel() gates on FORCE_FIRST_PERSON + phase ACTIVE + model non-nil.
--   When no weapon is equipped (model == nil), the viewmodel is always hidden.
--   setVisibility() is module-level so EquipWeapon and HolsterWeapon can call it directly.
--
-- Camera mode / perspective switching:
--   isFirstPerson (module-level bool) drives CameraMode and viewmodel visibility.
--   Initialized from Constants.FORCE_FIRST_PERSON on Start() and on each CharacterAdded.
--   When Constants.CAMERA_PERSPECTIVE_SWITCH_ENABLED is true, the scroll wheel toggles:
--     Scroll down while first-person → Classic (third-person); viewmodel hidden.
--     Scroll up  while third-person + shift lock ON            → snaps immediately to FP
--       (shift lock fixes camera at 8 studs; can't zoom further, so any up-scroll returns to FP).
--     Scroll up  while third-person + shift lock OFF + zoom ≤ SNAP_THRESHOLD → LockFirstPerson.
--   applyCameraMode() writes LocalPlayer.CameraMode only; no camera.CFrame changes.
--
-- Public API:
--   :Start()                  — init + register event listeners (called once by ClientInit)
--   :EquipWeapon(name)        — clone & equip a weapon viewmodel, play equip → idle animation
--   :HolsterWeapon()          — stop animations, destroy model, clear equip state
--   :IsWeaponEquipped()       — returns true while any weapon is equipped
--   :PlayEquipAnimation()     — play equip track once, then chain to run or idle
--   :PlayIdleAnimation()      — play idle track (looped)
--   :PlayRunAnimation()       — play run track (looped, called by SetRunning)
--   :PlayFireAnimation()      — positional recoil snap + one-shot fire track (blocked by reload)
--   :PlayReloadAnimation()    — one-shot reload track; blocks fire/run; resumes run or idle on end
--   :SetRunning(isSprinting)  — called by GunController each frame; manages run ↔ idle transition
--   :SetReloading(reloading)  — external setter for isReloading; wraps internal flag from PlayReloadAnimation
--   :StopWeaponAnimations()   — stop and destroy all loaded weapon AnimationTracks, reset flags
--   :SetRecoilOffset(cf)      — push a rotational recoil CFrame from GunController
--   :GetBarrelTipCFrame()     — world CFrame at MuzzleAttachment tip (muzzle-flash placement)
--
-- Initialized by ClientInit via loadAndStart() — no PlayerGui needed.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))

-- MovementController provides bob/tilt offsets each frame.
-- ViewModelController → MovementController is one-directional (no circular).
local MovementController = require(script.Parent:WaitForChild("MovementController"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

-- REAL_MODEL_OFFSET: fallback used when FakeCamera cannot be found on the clone.
-- Derived with: hrp.CFrame:ToObjectSpace(fc.CFrame):Inverse()
-- Re-derive if the rig is re-imported.
local REAL_MODEL_OFFSET: CFrame = CFrame.new(-0.7141, -1.6346, 2.0080)
    * CFrame.Angles(0.055254, 0, 0)

-- Set by EquipWeapon() from the rig's FakeCamera CFrame.
-- Falls back to REAL_MODEL_OFFSET when FakeCamera is absent.
local BASE_OFFSET: CFrame = REAL_MODEL_OFFSET

-- Positional recoil snap distance and decay rate (studs).
local RECOIL_DIST: number = 0.05
local RECOIL_RATE: number = RECOIL_DIST / 0.05

-- Fallback muzzle-flash distance when MuzzleAttachment is absent.
local MUZZLE_FALLBACK_DIST: number = 1.5

-- Extra offset applied in camera space before the recoil/bob/BASE_OFFSET chain.
-- Negative Z brings the model closer to the camera (weapon fills more of the screen).
-- Read once at module load; change Constants.VIEWMODEL_CAMERA_EXTRA_OFFSET to retune.
local CAMERA_EXTRA_OFFSET: CFrame = Constants.VIEWMODEL_CAMERA_EXTRA_OFFSET

-- ============================================================
-- State
-- ============================================================

-- Visibility flag and current phase, tracked for the shouldShowViewModel() gate.
local visible:      boolean = false
local currentPhase: string  = Constants.Phase.LOBBY

-- Current camera perspective mode.
-- true  = LockFirstPerson (viewmodel visible in ACTIVE).
-- false = Classic third-person (viewmodel always hidden).
-- Initialized from Constants.FORCE_FIRST_PERSON; toggled by the scroll wheel when
-- Constants.CAMERA_PERSPECTIVE_SWITCH_ENABLED is true.
local isFirstPerson: boolean = Constants.FORCE_FIRST_PERSON

-- Perspective mode that was active before ADS entered.
-- Saved by SetAiming(true) and restored by SetAiming(false) so exiting ADS returns
-- the player to whatever mode they were in (first-person or third-person).
local preAdsFirstPerson: boolean = Constants.FORCE_FIRST_PERSON

-- Positional recoil offset (decays toward 0 each RenderStepped).
local recoilOffset: number = 0

-- Rotational recoil CFrame pushed by GunController each frame via SetRecoilOffset().
local viewRecoilCFrame: CFrame = CFrame.new()

-- Free-aim viewmodel rotation state (Stage 1 — visual only).
-- vmFreeAimNormalized: latest normalized offset pushed by GunController each frame
--   via SetFreeAimOffset().  Range [-1, 1] in each axis (0,0 = crosshair centered).
-- vmFreeAimBlended:    per-frame lerped value; eases toward vmFreeAimNormalized at
--   FREE_AIM_VIEWMODEL_BLEND_SPEED to give the weapon a slight lag behind aim drift.
local vmFreeAimNormalized: Vector2 = Vector2.zero
local vmFreeAimBlended:    Vector2 = Vector2.zero

-- Mouse inertia state: velocity accumulated from raw mouse delta each frame, then damped.
-- vmMouseInertiaDelta: latest delta pushed by GunController via SetMouseInertia().
-- vmMouseInertia:      running velocity (integrated + clamped + damped each RenderStepped).
-- vmInertiaCurrent:    current inertia weight [0, 1] lerped toward state-based target.
local vmMouseInertiaDelta: Vector2 = Vector2.zero
local vmMouseInertia:      Vector2 = Vector2.zero
local vmInertiaCurrent:    number  = 1

-- Viewmodel recoil state (data-driven per weapon profile; see WeaponData[name].recoil).
-- vmRecoilTarget:        desired recoil CFrame; pushed outward each shot, decays to identity.
-- vmRecoilCurrent:       per-frame follower that chases vmRecoilTarget at vmActiveKickSpeed.
-- vmRecoilBuildup:       accumulated kick scalar [0, maxBuildup]; increases per shot.
-- vmRecoilYawDir:        alternating yaw direction (+1 or -1); flipped each shot.
-- vmActiveKickSpeed:     lerp rate for current chasing target; set by ApplyRecoil from profile.
-- vmActiveRecoverySpeed: lerp rate for target decaying to identity; set by ApplyRecoil.
local vmRecoilTarget:        CFrame = CFrame.new()
local vmRecoilCurrent:       CFrame = CFrame.new()
local vmRecoilBuildup:       number = 0
local vmRecoilYawDir:        number = 1
local vmActiveKickSpeed:     number = 38
local vmActiveRecoverySpeed: number = 18

-- Procedural sway state (mouse-look weapon lag, movement bob, strafe roll).
-- vmSwayMouseTarget:  desired sway from accumulated mouse delta; clamped + decays to zero.
-- vmSwayMouseCurrent: smoothed follower that chases vmSwayMouseTarget; drives swayCF.
-- vmSwayWeight:       current weight [0, 1] lerped toward state-based target each frame.
-- vmBobTime:          sine phase accumulator; advanced while amplitude > 0, decays to 0 when still.
-- vmBobAmountCurrent: smoothly lerped bob amplitude (eliminates pop on state transitions).
-- vmBobSpeedCurrent:  smoothly lerped bob speed (same purpose).
-- vmStrafeLag/Vel:    spring displacement+velocity for strafe; Vel enables overshoot on reversal.
-- vmVertTilt/Vel:     spring displacement+velocity for vertical tilt; Vel gives organic bounce.
-- vmForwardLean/Vel:  spring displacement+velocity for forward lean; Vel gives swing when stopping.
-- vmLandDip/Vel:      spring state for landing impact dip; impulse applied on velY sign change.
-- vmPrevVelY:         previous-frame Y velocity for landing-edge detection.
-- vmBreathTime:       idle breathing oscillator phase; always advancing.
-- vmBreathWeight:     lerped 0→1 when stationary, 1→0 when moving.
-- vmAccelTilt:        pitch from horizontal acceleration (leans back when sprinting, forward on stop).
-- vmHorizSpeedPrev:   previous frame horizontal speed for per-frame acceleration estimate.
local vmSwayMouseTarget:  Vector2 = Vector2.zero
local vmSwayMouseCurrent: Vector2 = Vector2.zero
local vmSwayWeight:       number  = 1
local vmBobTime:          number  = 0
local vmBobAmountCurrent: number  = 0
local vmBobSpeedCurrent:  number  = 4
local vmStrafeLag:        number  = 0
local vmStrafeLagVel:     number  = 0
local vmVertTilt:         number  = 0
local vmVertTiltVel:      number  = 0
local vmForwardLean:      number  = 0
local vmForwardLeanVel:   number  = 0
local vmLandDip:          number  = 0
local vmLandDipVel:       number  = 0
local vmPrevVelY:         number  = 0
local vmBreathTime:       number  = 0
local vmBreathWeight:     number  = 0
local vmAccelTilt:        number  = 0
local vmHorizSpeedPrev:   number  = 0

-- Camera rotation inertia: angular/translational displacement that lags behind camera turns.
-- vmPrevCamCFrame:    camera CFrame from the PREVIOUS frame (used to compute per-frame rotation delta).
-- vmCamInertia{Yaw/Pitch/Roll}: current angular offset (radians); accumulated each frame, springs to zero.
-- vmCamInertia{TX/TY}:          current positional offset (studs); pendulum-mass companion to rotation.
-- vmCamInertiaWeight:           current state multiplier [0, >1]; lerped toward state-based target.
-- vmCamInertiaLastTarget:       previous target value; used to gate change-only Logger.debug calls.
local vmPrevCamCFrame:       CFrame = CFrame.new()
local vmCamInertiaYaw:       number = 0
local vmCamInertiaPitch:     number = 0
local vmCamInertiaRoll:      number = 0
local vmCamInertiaTX:        number = 0
local vmCamInertiaTY:        number = 0
local vmCamInertiaWeight:    number = 1
local vmCamInertiaLastTarget:number = 1

-- Movement velocity inertia: positional offset that lags behind player velocity changes.
-- vmMovInertia{X/Y/Z}: camera-local offset (studs). +Z = toward viewer (backward), -X = left, -Y = down.
-- vmMovInertiaWeight:   state multiplier [0, >1]; lerped toward state-based target each frame.
-- vmMovInertiaLastTarget: previous target; gates change-only debug logs.
local vmMovInertiaX:          number = 0
local vmMovInertiaY:          number = 0
local vmMovInertiaZ:          number = 0
local vmMovInertiaWeight:     number = 1
local vmMovInertiaLastTarget: number = 1

-- Name of the currently equipped weapon, or nil when holstered.
local equippedWeaponName: string? = nil

-- First-person animation tracks for the equipped weapon.
-- equip and idle are the base-layer tracks (loaded and cleared by _setupWeaponAnimations).
-- fire, reload, and run are the action/movement overlay tracks (same lifetime).
local weaponEquipTrack:   AnimationTrack? = nil
local weaponIdleTrack:    AnimationTrack? = nil
local weaponFireTrack:    AnimationTrack? = nil
local weaponReloadTrack:  AnimationTrack? = nil
local weaponRunTrack:     AnimationTrack? = nil

-- Animation state flags.
-- isReloading: true while reload one-shot is playing; blocks fire and locomotion.
-- isRunning:   true while locomotion state is "Sprint"; used by sway/inertia weight system.
local isReloading: boolean = false
local isRunning:   boolean = false

-- Locomotion animation tracks (walk / enterRun / sprint).
-- weaponRunTrack already declared above; walk/enterRun/sprint extend it.
-- All three share Movement priority and are mutually exclusive at runtime.
local weaponWalkTrack:     AnimationTrack? = nil
local weaponEnterRunTrack: AnimationTrack? = nil
local weaponSprintTrack:   AnimationTrack? = nil

-- Locomotion FSM state: "Idle" | "Walk" | "Run" | "Sprint".
-- Managed by SetLocomotionState(); cleared on StopWeaponAnimations / init.
-- vmEnterRunPlaying guards the Stopped:Once callback so it fires only once per transition.
local vmLocomotionState:   string  = "Idle"
local vmEnterRunPlaying:   boolean = false

-- First-person ADS (aim down sights) animation tracks.
-- adsIn plays once on SetAiming(true).
-- adsIdle loops after adsIn finishes.
-- adsOut plays once on SetAiming(false), returns to idle.
-- adsFire replaces normal fire track when IsAiming() is true.
local weaponAdsInTrack:   AnimationTrack? = nil
local weaponAdsIdleTrack: AnimationTrack? = nil
local weaponAdsOutTrack:  AnimationTrack? = nil
local weaponAdsFireTrack: AnimationTrack? = nil

-- ADS state machine: explicit state to prevent idle/run from fighting ADS pose.
-- "Hip" = normal viewmodel idle/run/fire behavior
-- "Entering" = adsIn is playing forward
-- "Aiming" = adsIn is held at final frame, fake ADS idle active
-- "Exiting" = adsOut is playing
type ADSState = "Hip" | "Entering" | "Aiming" | "Exiting"
local adsState: ADSState = "Hip"

-- Fake ADS idle: accumulator for sine-based breathing/sway when adsState == "Aiming".
local adsIdleTime: number = 0

-- ADS pivot alignment alpha (0 = hip pivot, 1 = FakeCamera-at-camera-centre pivot).
-- Lerped each RenderStepped toward 1 during Entering/Aiming/Exiting and toward 0 once Hip.
-- At alpha=1 the pivot removes CAMERA_EXTRA_OFFSET so the ADS animation's sights land at
-- screen centre.  Uses BASE_OFFSET which was already derived from FakeCamera in EquipWeapon.
local adsAimAlpha: number = 0

-- Countdown (seconds) that holds adsAimAlpha at 1 after StopADSAnimations() is called.
-- Gives the adsIdle/adsIn fade time to finish before the pivot starts shifting toward basePivot,
-- preventing the gun-into-camera glitch when reload interrupts ADS.
local adsAimHoldTimer: number = 0


-- Third-person character weapon AnimationTracks.
-- Loaded on the local player's Humanoid.Animator when a weapon is equipped.
-- Priority: equip/idle = Action (overlays movement), fire/reload = Action2 (overlays idle).
-- Cleared (nil, no Stop) in init() because CharacterAdded may fire after the old Animator
-- is already destroyed.  Stopped and Destroyed in StopWeaponAnimations() during normal play.
local tpEquipTrack:  AnimationTrack? = nil
local tpIdleTrack:   AnimationTrack? = nil
local tpFireTrack:   AnimationTrack? = nil
local tpReloadTrack: AnimationTrack? = nil

-- ============================================================
-- Controller table
-- ============================================================

local ViewModelController = {}
-- The current weapon viewmodel Model, parented to workspace.CurrentCamera when equipped.
-- nil while holstered.
ViewModelController.model = nil :: Model?

-- Parts that must remain Transparent = 1 at all times (rig physics / helper bones).
-- Applied by setVisibility() to avoid flashing invisible rig bones.
local HELPER_PARTS: { [string]: boolean } = {
    HumanoidRootPart = true,
    FakeCamera       = true,
    Torso            = true,
    Handcontrol      = true,
    Main             = true,
    Root             = true,
}

-- ============================================================
-- Private helpers (module-level so public methods can call them)
-- ============================================================

-- Sets the local player's CameraMode based on the isFirstPerson state variable.
-- Called on Start(), CharacterAdded, and whenever the perspective is switched.
-- Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
local function applyCameraMode()
    local localPlayer = Players.LocalPlayer
    if isFirstPerson then
        localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
    else
        localPlayer.CameraMode = Enum.CameraMode.Classic
    end
end

-- Returns true only when all three conditions hold:
--   1. isFirstPerson is true (third-person mode always hides the viewmodel)
--   2. currentPhase == ACTIVE
--   3. ViewModelController.model is non-nil (weapon is equipped)
local function shouldShowViewModel(): boolean
    return isFirstPerson
        and currentPhase == Constants.Phase.ACTIVE
        and ViewModelController.model ~= nil
end

-- Sets BasePart Transparency on the current viewmodel.
-- show=true  → visual geometry parts become opaque; helper parts stay transparent.
-- show=false → all parts become transparent.
-- Module-level (not inside Start()) so EquipWeapon and HolsterWeapon can call it.
local function setVisibility(show: boolean)
    Logger.debug(string.format("[ViewModelController] setVisibility(%s)", tostring(show)))
    local m = ViewModelController.model
    if not m then return end
    local count = 0
    for _, desc in ipairs(m:GetDescendants()) do
        if desc:IsA("BasePart") then
            if show then
                if not HELPER_PARTS[desc.Name] then
                    (desc :: BasePart).Transparency = 0
                    count += 1
                end
            else
                (desc :: BasePart).Transparency = 1
                count += 1
            end
        end
    end
    Logger.debug(string.format("[ViewModelController] setVisibility(%s) — %d parts", tostring(show), count))
end

-- Returns the Animator under the local player's character Humanoid, or nil if unavailable.
-- Used to load third-person weapon animation tracks onto the character's existing rig.
local function getCharacterAnimator(): Animator?
    local char = Players.LocalPlayer.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    return hum:FindFirstChildOfClass("Animator")
end

-- Plays the third-person equip one-shot then chains to the TP idle loop.
-- Mirrors PlayEquipAnimation() but for the character-body TP tracks.
-- No-op when tpEquipTrack / tpIdleTrack are nil (weapon has no TP animations).
local function startThirdPersonEquipSequence()
    local capturedWeapon = equippedWeaponName
    if tpEquipTrack and tpEquipTrack.Length > 0 then
        tpEquipTrack:Play()
        tpEquipTrack.Stopped:Connect(function()
            if equippedWeaponName ~= capturedWeapon then return end
            if tpIdleTrack then
                tpIdleTrack:Play()
            end
        end)
    else
        if tpIdleTrack then
            tpIdleTrack:Play()
        end
    end
end

-- Switches the active camera perspective and updates viewmodel visibility accordingly.
-- fp = true  → LockFirstPerson; viewmodel shown when equipped + ACTIVE.
-- fp = false → Classic third-person; viewmodel always hidden.
-- Also called from Start() to initialize, and from CharacterAdded to reset.
local function setFirstPerson(fp: boolean)
    if isFirstPerson == fp then return end  -- no-op on unchanged state
    isFirstPerson = fp
    applyCameraMode()
    local show = shouldShowViewModel()
    visible    = show
    setVisibility(show)
    Logger.debug("[ViewModelController] Perspective → " .. (fp and "first-person" or "third-person"))
end

-- ============================================================
-- Public methods — weapon lifecycle
-- ============================================================

-- Clears all weapon state.  Called by Start() and CharacterAdded.
-- After init(), self.model is nil (weapon holstered) and no animation tracks are loaded.
function ViewModelController:init()
    -- Stop and destroy all weapon animation tracks.
    if weaponEquipTrack then
        weaponEquipTrack:Stop()
        weaponEquipTrack:Destroy()
        weaponEquipTrack = nil
    end
    if weaponIdleTrack then
        weaponIdleTrack:Stop()
        weaponIdleTrack:Destroy()
        weaponIdleTrack = nil
    end
    if weaponFireTrack then
        weaponFireTrack:Stop()
        weaponFireTrack:Destroy()
        weaponFireTrack = nil
    end
    if weaponReloadTrack then
        weaponReloadTrack:Stop()
        weaponReloadTrack:Destroy()
        weaponReloadTrack = nil
    end
    if weaponRunTrack then
        weaponRunTrack:Stop()
        weaponRunTrack:Destroy()
        weaponRunTrack = nil
    end
    if weaponWalkTrack then
        weaponWalkTrack:Stop()
        weaponWalkTrack:Destroy()
        weaponWalkTrack = nil
    end
    if weaponEnterRunTrack then
        weaponEnterRunTrack:Stop()
        weaponEnterRunTrack:Destroy()
        weaponEnterRunTrack = nil
    end
    if weaponSprintTrack then
        weaponSprintTrack:Stop()
        weaponSprintTrack:Destroy()
        weaponSprintTrack = nil
    end
    -- Stop and destroy ADS tracks.
    if weaponAdsInTrack then
        weaponAdsInTrack:Stop()
        weaponAdsInTrack:Destroy()
        weaponAdsInTrack = nil
    end
    if weaponAdsIdleTrack then
        weaponAdsIdleTrack:Stop()
        weaponAdsIdleTrack:Destroy()
        weaponAdsIdleTrack = nil
    end
    if weaponAdsOutTrack then
        weaponAdsOutTrack:Stop()
        weaponAdsOutTrack:Destroy()
        weaponAdsOutTrack = nil
    end
    if weaponAdsFireTrack then
        weaponAdsFireTrack:Stop()
        weaponAdsFireTrack:Destroy()
        weaponAdsFireTrack = nil
    end
    isReloading          = false
    isRunning            = false
    vmLocomotionState    = "Idle"
    vmEnterRunPlaying    = false
    adsState             = "Hip"
    adsIdleTime          = 0
    adsAimAlpha          = 0
    adsAimHoldTimer      = 0
    vmMouseInertiaDelta  = Vector2.zero
    vmMouseInertia       = Vector2.zero
    vmInertiaCurrent     = 1
    vmRecoilTarget        = CFrame.new()
    vmRecoilCurrent       = CFrame.new()
    vmRecoilBuildup       = 0
    vmRecoilYawDir        = 1
    vmActiveKickSpeed     = Constants.DEFAULT_VIEWMODEL_RECOIL_KICK_SPEED
    vmActiveRecoverySpeed = Constants.DEFAULT_VIEWMODEL_RECOIL_RECOVERY_SPEED
    vmSwayMouseTarget  = Vector2.zero
    vmSwayMouseCurrent = Vector2.zero
    vmSwayWeight       = 1
    vmBobTime          = 0
    vmBobAmountCurrent = 0
    vmBobSpeedCurrent  = Constants.VIEWMODEL_WALK_BOB_SPEED :: number
    vmStrafeLag        = 0
    vmStrafeLagVel     = 0
    vmVertTilt         = 0
    vmVertTiltVel      = 0
    vmForwardLean      = 0
    vmForwardLeanVel   = 0
    vmLandDip          = 0
    vmLandDipVel       = 0
    vmPrevVelY         = 0
    vmBreathTime       = 0
    vmBreathWeight     = 0
    vmAccelTilt        = 0
    vmHorizSpeedPrev   = 0
    vmPrevCamCFrame       = CFrame.new()
    vmCamInertiaYaw       = 0
    vmCamInertiaPitch     = 0
    vmCamInertiaRoll      = 0
    vmCamInertiaTX        = 0
    vmCamInertiaTY        = 0
    vmCamInertiaWeight    = 1
    vmCamInertiaLastTarget= 1
    vmMovInertiaX         = 0
    vmMovInertiaY         = 0
    vmMovInertiaZ         = 0
    vmMovInertiaWeight    = 1
    vmMovInertiaLastTarget= 1
    -- Third-person character tracks: nil references only — do NOT call Stop/Destroy.
    -- init() is called from CharacterAdded where the old Humanoid.Animator may already be
    -- destroyed, making track method calls unsafe.  Same pattern as MovementController's
    -- loadMovementAnimations() respawn cleanup (table.clear without Stop).
    tpEquipTrack   = nil
    tpIdleTrack    = nil
    tpFireTrack    = nil
    tpReloadTrack  = nil
    -- Destroy any existing weapon model.
    if self.model then
        self.model:Destroy()
        self.model = nil
    end
    equippedWeaponName = nil
    BASE_OFFSET        = REAL_MODEL_OFFSET
    visible            = false
    Logger.debug("[ViewModelController] init: state cleared (weapon holstered)")
end

-- Stops and destroys all loaded weapon AnimationTracks and resets all animation state flags.
-- AnimationTrack:Destroy() severs Stopped signals synchronously, so no deferred callbacks
-- (reload chain, equip chain) will fire after this returns.
-- Safe to call when no weapon is equipped (no-op in that case).
function ViewModelController:StopWeaponAnimations()
    if weaponEquipTrack then
        weaponEquipTrack:Stop()
        weaponEquipTrack:Destroy()
        weaponEquipTrack = nil
    end
    if weaponIdleTrack then
        weaponIdleTrack:Stop()
        weaponIdleTrack:Destroy()
        weaponIdleTrack = nil
    end
    if weaponFireTrack then
        weaponFireTrack:Stop()
        weaponFireTrack:Destroy()
        weaponFireTrack = nil
    end
    if weaponReloadTrack then
        weaponReloadTrack:Stop()
        weaponReloadTrack:Destroy()
        weaponReloadTrack = nil
    end
    if weaponRunTrack then
        weaponRunTrack:Stop()
        weaponRunTrack:Destroy()
        weaponRunTrack = nil
    end
    if weaponWalkTrack then
        weaponWalkTrack:Stop()
        weaponWalkTrack:Destroy()
        weaponWalkTrack = nil
    end
    if weaponEnterRunTrack then
        weaponEnterRunTrack:Stop()
        weaponEnterRunTrack:Destroy()
        weaponEnterRunTrack = nil
    end
    if weaponSprintTrack then
        weaponSprintTrack:Stop()
        weaponSprintTrack:Destroy()
        weaponSprintTrack = nil
    end
    -- Stop and destroy ADS tracks.
    if weaponAdsInTrack then
        weaponAdsInTrack:Stop()
        weaponAdsInTrack:Destroy()
        weaponAdsInTrack = nil
    end
    if weaponAdsIdleTrack then
        weaponAdsIdleTrack:Stop()
        weaponAdsIdleTrack:Destroy()
        weaponAdsIdleTrack = nil
    end
    if weaponAdsOutTrack then
        weaponAdsOutTrack:Stop()
        weaponAdsOutTrack:Destroy()
        weaponAdsOutTrack = nil
    end
    if weaponAdsFireTrack then
        weaponAdsFireTrack:Stop()
        weaponAdsFireTrack:Destroy()
        weaponAdsFireTrack = nil
    end
    isReloading            = false
    isRunning              = false
    vmLocomotionState      = "Idle"
    vmEnterRunPlaying      = false
    adsState               = "Hip"
    adsIdleTime            = 0
    adsAimAlpha            = 0
    adsAimHoldTimer        = 0
    vmMouseInertiaDelta    = Vector2.zero
    vmMouseInertia         = Vector2.zero
    vmInertiaCurrent       = 1
    vmRecoilTarget        = CFrame.new()
    vmRecoilCurrent       = CFrame.new()
    vmRecoilBuildup       = 0
    vmRecoilYawDir        = 1
    vmActiveKickSpeed     = Constants.DEFAULT_VIEWMODEL_RECOIL_KICK_SPEED
    vmActiveRecoverySpeed = Constants.DEFAULT_VIEWMODEL_RECOIL_RECOVERY_SPEED
    vmSwayMouseTarget  = Vector2.zero
    vmSwayMouseCurrent = Vector2.zero
    vmSwayWeight       = 1
    vmBobTime          = 0
    vmBobAmountCurrent = 0
    vmBobSpeedCurrent  = Constants.VIEWMODEL_WALK_BOB_SPEED :: number
    vmStrafeLag        = 0
    vmStrafeLagVel     = 0
    vmVertTilt         = 0
    vmVertTiltVel      = 0
    vmForwardLean      = 0
    vmForwardLeanVel   = 0
    vmLandDip          = 0
    vmLandDipVel       = 0
    vmPrevVelY         = 0
    vmBreathTime       = 0
    vmBreathWeight     = 0
    vmAccelTilt        = 0
    vmHorizSpeedPrev   = 0
    -- Third-person character tracks: stop and destroy (character is alive in this path).
    -- AnimationTrack:Destroy() severs Stopped connections synchronously, preventing any
    -- deferred equip-chain or reload-chain callback from firing after holster.
    if tpEquipTrack then
        tpEquipTrack:Stop()
        tpEquipTrack:Destroy()
        tpEquipTrack = nil
    end
    if tpIdleTrack then
        tpIdleTrack:Stop()
        tpIdleTrack:Destroy()
        tpIdleTrack = nil
    end
    if tpFireTrack then
        tpFireTrack:Stop()
        tpFireTrack:Destroy()
        tpFireTrack = nil
    end
    if tpReloadTrack then
        tpReloadTrack:Stop()
        tpReloadTrack:Destroy()
        tpReloadTrack = nil
    end
    Logger.debug("[ViewModelController] StopWeaponAnimations: all tracks cleared, flags reset")
end

-- Stops animations, destroys the current weapon model, and clears equip state.
-- IsWeaponEquipped() returns false after this call.
function ViewModelController:HolsterWeapon()
    self:StopWeaponAnimations()
    if self.model then
        self.model:Destroy()
        self.model = nil
    end
    equippedWeaponName = nil
    visible            = false
    Logger.debug("[ViewModelController] HolsterWeapon: weapon holstered")
end

-- Returns true while any weapon viewmodel is equipped (self.model ~= nil).
function ViewModelController:IsWeaponEquipped(): boolean
    return equippedWeaponName ~= nil
end

-- Plays the loaded idle AnimationTrack (looped).
-- fadeTime defaults to VIEWMODEL_IDLE_RUN_FADE_TIME for smooth crossfades from run/reload.
-- No-op when no idle track is loaded.
function ViewModelController:PlayIdleAnimation(fadeTime: number?)
    if weaponIdleTrack then
        weaponIdleTrack:Play(fadeTime or (Constants.VIEWMODEL_IDLE_RUN_FADE_TIME :: number))
        Logger.debug("[ViewModelController] PlayIdleAnimation: idle track started")
    else
        Logger.debug("[ViewModelController] PlayIdleAnimation: no idle track loaded — skipped")
    end
end

-- Plays the equip AnimationTrack once, then chains to PlayIdleAnimation() via the
-- Stopped signal.  If the equip track is absent, PlayIdleAnimation() starts immediately
-- without blocking.
-- NOTE: do NOT gate on weaponEquipTrack.Length > 0 — Length is 0 until the animation
-- asset loads from the Roblox server, which happens asynchronously after LoadAnimation().
function ViewModelController:PlayEquipAnimation()
    -- Capture weapon identity so the Stopped callback can guard against stale calls.
    local capturedWeapon = equippedWeaponName

    if weaponEquipTrack then
        -- Connect Stopped BEFORE Play() — same reason as reload: if the asset hasn't
        -- loaded yet (Length == 0), Stopped can fire synchronously on Play(), which
        -- would skip the callback and leave the weapon stuck at bind pose with no idle.
        -- AnimationTrack:Destroy() disconnects all signals synchronously, so the
        -- Stopped callback will not fire after StopWeaponAnimations() has run.
        weaponEquipTrack.Stopped:Connect(function()
            -- Guard: only proceed if same weapon is still equipped.
            if equippedWeaponName ~= capturedWeapon or self.model == nil then return end
            -- Resume current locomotion state (bypasses guard by clearing cached state).
            if Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED :: boolean then
                local saved = vmLocomotionState
                vmLocomotionState = ""
                vmEnterRunPlaying = false
                self:SetLocomotionState(saved)
            elseif isRunning and weaponRunTrack ~= nil then
                self:PlayRunAnimation()
            elseif weaponIdleTrack ~= nil then
                self:PlayIdleAnimation()
            end
        end)
        weaponEquipTrack:Play()
        Logger.debug("[ViewModelController] PlayEquipAnimation: equip track started")
    else
        -- No equip track or zero-length clip — start locomotion or idle directly.
        Logger.debug("[ViewModelController] PlayEquipAnimation: no equip track — starting base directly")
        if Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED :: boolean then
            local saved = vmLocomotionState
            vmLocomotionState = ""
            vmEnterRunPlaying = false
            self:SetLocomotionState(saved)
        elseif isRunning and weaponRunTrack ~= nil then
            self:PlayRunAnimation()
        else
            self:PlayIdleAnimation()
        end
    end
end

-- Clones the weapon viewmodel from ReplicatedStorage/ViewModels/<viewModelName>, parents it
-- to workspace.CurrentCamera, sets up BasePart properties, computes BASE_OFFSET, loads
-- animation tracks, and plays the equip → idle sequence.
--
-- Guards:
--   • same weapon already equipped → no-op
--   • different weapon equipped → holsters current weapon first
--   • weaponName not in WeaponData → warning, early return
--   • viewmodel not found or clone is empty → warning, early return
function ViewModelController:EquipWeapon(weaponName: string)
    assert(typeof(weaponName) == "string",
        "[ViewModelController] EquipWeapon: weaponName must be a string")

    -- No-op if the same weapon is already equipped.
    if equippedWeaponName == weaponName then
        Logger.debug("[ViewModelController] EquipWeapon: " .. weaponName .. " already equipped — no-op")
        return
    end

    -- Holster any different weapon that is currently equipped.
    if equippedWeaponName ~= nil then
        self:HolsterWeapon()
    end

    -- Look up weapon definition.
    local rawData = WeaponData[weaponName]
    if not rawData then
        Logger.warn("[ViewModelController] EquipWeapon: no WeaponData entry for: " .. weaponName)
        return
    end
    -- Cast to any so we can access displayName, viewModelName, animations without
    -- strict-mode field-union errors (WeaponData entries have heterogeneous shapes).
    local data = rawData :: any

    local vmName: string = data.viewModelName :: string
    if not vmName or vmName == "" then
        Logger.warn("[ViewModelController] EquipWeapon: viewModelName missing for: " .. weaponName)
        return
    end

    -- Locate the viewmodel folder.
    local vmFolder = ReplicatedStorage:FindFirstChild(Constants.VIEWMODEL_FOLDER_NAME)
    if not vmFolder then
        Logger.warn("[ViewModelController] EquipWeapon: ReplicatedStorage/"
            .. Constants.VIEWMODEL_FOLDER_NAME .. " not found")
        return
    end

    -- WaitForChild (5 s) so we block until the model and its children have replicated.
    local vmAsset = vmFolder:WaitForChild(vmName, 5)
    if not vmAsset or not vmAsset:IsA("Model") then
        Logger.warn("[ViewModelController] EquipWeapon: viewmodel not found for weapon: " .. weaponName
            .. " (looked for: " .. vmName .. ")")
        return
    end

    -- Clone the viewmodel.
    local clone = (vmAsset :: Model):Clone()

    -- Verify the clone is not empty (guards against replication-race returning a shell).
    local partCount = 0
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then partCount += 1 end
    end
    if partCount == 0 then
        Logger.warn("[ViewModelController] EquipWeapon: " .. weaponName
            .. " clone has 0 BaseParts (replication race) — aborting")
        clone:Destroy()
        return
    end

    -- Configure all BasePart descendants.
    -- Visual parts start transparent; setVisibility(true) reveals them.
    -- Helper rig bones (HRP, FakeCamera, etc.) remain permanently transparent.
    -- Do NOT use Welds or WeldConstraints — Motor6Ds maintain the rig hierarchy.
    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") then
            local p = desc :: BasePart
            p.CanCollide = false
            p.CanQuery   = false
            p.CanTouch   = false
            p.Massless   = true
            if not HELPER_PARTS[p.Name] then
                p.Transparency = 1  -- hidden until setVisibility(true) is called
            end
        end
    end

    -- Compute BASE_OFFSET from the rig's FakeCamera CFrame so PivotTo(cam.CFrame * BASE_OFFSET)
    -- places FakeCamera exactly at the camera's CFrame each frame.
    local rootPartName = Constants.VIEWMODEL_DEFAULT_ROOT_PART_NAME
    local rootPart     = clone:FindFirstChild(rootPartName) :: BasePart?
    if not rootPart then
        rootPart = clone:FindFirstChild(Constants.VIEWMODEL_FALLBACK_ROOT_PART_NAME) :: BasePart?
        if rootPart then
            Logger.debug("[ViewModelController] EquipWeapon: used fallback root part ("
                .. Constants.VIEWMODEL_FALLBACK_ROOT_PART_NAME .. ") for " .. weaponName)
        end
    end
    local fcPart = clone:FindFirstChild("FakeCamera") :: BasePart?
    if rootPart and fcPart then
        BASE_OFFSET = rootPart.CFrame:ToObjectSpace(fcPart.CFrame):Inverse()
    else
        BASE_OFFSET = REAL_MODEL_OFFSET
        Logger.warn("[ViewModelController] EquipWeapon: FakeCamera or root part not found on "
            .. weaponName .. " clone — using hardcoded offset")
    end

    -- Parent the clone to the camera so it follows RenderStepped repositioning.
    local cam = workspace.CurrentCamera
    clone.Parent    = cam
    self.model      = clone
    equippedWeaponName = weaponName
    visible         = false  -- will be updated by setVisibility below

    Logger.debug("[ViewModelController] EquipWeapon: " .. weaponName
        .. " cloned (" .. tostring(partCount) .. " parts) and parented to camera")

    -- Load first-person animation tracks on the viewmodel clone's Animator.
    self:_setupWeaponAnimations(weaponName, data)

    -- Load third-person animation tracks on the character's Humanoid.Animator.
    -- These overlay movement animations on the character body (visible in third-person
    -- and by other players).  Runs regardless of current camera perspective.
    self:_setupThirdPersonWeaponAnimations(weaponName, data)

    -- Begin first-person equip → idle animation sequence.
    -- The model is still invisible at this point so the animation system can evaluate
    -- Motor6D CFrames before the first render — this prevents the bind-pose flash.
    self:PlayEquipAnimation()

    -- Begin third-person equip → idle sequence on the character body.
    startThirdPersonEquipSequence()

    -- Reveal after one RenderStepped so Motor6Ds are in animation pose, not bind pose.
    -- RenderStepped fires after PreAnimation (Motor6D evaluation) but before the render.
    if shouldShowViewModel() then
        local capturedClone = clone
        local revealConn: RBXScriptConnection
        revealConn = RunService.RenderStepped:Connect(function()
            revealConn:Disconnect()
            if self.model == capturedClone then
                visible = true
                setVisibility(true)
            end
        end)
    end
end

-- Private: finds or creates AnimationController + Animator on the cloned viewmodel, then
-- loads the firstPerson equip and idle animation tracks from WeaponData.
-- Does NOT use Welds or WeldConstraints.
function ViewModelController:_setupWeaponAnimations(weaponName: string, data: any)
    local clone = self.model
    if not clone then return end

    -- Resolve Animator: prefer Humanoid (if the rig has one), then AnimationController.
    -- If neither exists, create AnimationController + Animator programmatically.
    local animator: Animator? = nil

    local humanoid = clone:FindFirstChildOfClass("Humanoid")
    if humanoid then
        animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            local a = Instance.new("Animator")
            a.Parent = humanoid
            animator  = a
        end
    else
        local animCtrl = clone:FindFirstChildOfClass("AnimationController")
        if not animCtrl then
            local ac = Instance.new("AnimationController")
            ac.Parent = clone
            animCtrl  = ac
        end
        animator = animCtrl:FindFirstChildOfClass("Animator")
        if not animator then
            local a = Instance.new("Animator")
            a.Parent = animCtrl :: AnimationController
            animator  = a
        end
    end

    if not animator then
        Logger.warn("[ViewModelController] _setupWeaponAnimations: could not find/create Animator for: "
            .. weaponName)
        return
    end

    -- Retrieve first-person animation IDs from WeaponData.
    local anims = data.animations
    if not anims then
        Logger.warn("[ViewModelController] _setupWeaponAnimations: WeaponData.animations missing for: "
            .. weaponName)
        return
    end
    local fp = anims.firstPerson
    if not fp then
        Logger.warn("[ViewModelController] _setupWeaponAnimations: animations.firstPerson missing for: "
            .. weaponName)
        return
    end

    -- Load equip track (one-shot, Action priority — overrides idle on entry).
    local equipId: string = tostring(fp.equip or "")
    if equipId ~= "" and equipId ~= "rbxassetid://0" then
        local equipAnim = Instance.new("Animation")
        equipAnim.AnimationId = equipId
        local track = (animator :: Animator):LoadAnimation(equipAnim)
        track.Looped    = false
        track.Priority  = Enum.AnimationPriority.Action
        weaponEquipTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no equip animation ID for: "
            .. weaponName)
    end

    -- Load idle track (looped, Idle priority — base layer).
    local idleId: string = tostring(fp.idle or "")
    if idleId ~= "" and idleId ~= "rbxassetid://0" then
        local idleAnim = Instance.new("Animation")
        idleAnim.AnimationId = idleId
        local track = (animator :: Animator):LoadAnimation(idleAnim)
        track.Looped   = true
        track.Priority = Enum.AnimationPriority.Idle
        weaponIdleTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no idle animation ID for: "
            .. weaponName)
    end

    -- Load fire track (one-shot, Action priority — overrides run and idle per shot).
    local fireId: string = tostring(fp.fire or "")
    if fireId ~= "" and fireId ~= "rbxassetid://0" then
        local fireAnim = Instance.new("Animation")
        fireAnim.AnimationId = fireId
        local track = (animator :: Animator):LoadAnimation(fireAnim)
        track.Looped   = false
        track.Priority = Enum.AnimationPriority.Action
        weaponFireTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no fire animation ID for: "
            .. weaponName)
    end

    -- Load reload track (one-shot, Action priority — blocks fire and run while playing).
    local reloadId: string = tostring(fp.reload or "")
    if reloadId ~= "" and reloadId ~= "rbxassetid://0" then
        local reloadAnim = Instance.new("Animation")
        reloadAnim.AnimationId = reloadId
        local track = (animator :: Animator):LoadAnimation(reloadAnim)
        track.Looped   = false
        track.Priority = Enum.AnimationPriority.Action
        weaponReloadTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no reload animation ID for: "
            .. weaponName)
    end

    -- Load run track (looped, Movement priority — plays in Run locomotion state).
    local runId: string = tostring(fp.run or "")
    if runId ~= "" and runId ~= "rbxassetid://0" then
        local runAnim = Instance.new("Animation")
        runAnim.AnimationId = runId
        local track = (animator :: Animator):LoadAnimation(runAnim)
        track.Looped   = true
        track.Priority = Enum.AnimationPriority.Movement
        weaponRunTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no run animation ID for: "
            .. weaponName)
    end

    -- Load walk track (looped, Movement priority — plays in Walk locomotion state).
    local walkId: string = tostring(fp.walk or "")
    if walkId ~= "" and walkId ~= "rbxassetid://0" then
        local walkAnim = Instance.new("Animation")
        walkAnim.AnimationId = walkId
        local track = (animator :: Animator):LoadAnimation(walkAnim)
        track.Looped   = true
        track.Priority = Enum.AnimationPriority.Movement
        weaponWalkTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no walk animation ID for: "
            .. weaponName)
    end

    -- Load enterRun track (one-shot, Movement priority — plays once on Walk/Idle → Run).
    local enterRunId: string = tostring(fp.enterRun or "")
    if enterRunId ~= "" and enterRunId ~= "rbxassetid://0" then
        local enterRunAnim = Instance.new("Animation")
        enterRunAnim.AnimationId = enterRunId
        local track = (animator :: Animator):LoadAnimation(enterRunAnim)
        track.Looped   = false
        track.Priority = Enum.AnimationPriority.Movement
        weaponEnterRunTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no enterRun animation ID for: "
            .. weaponName)
    end

    -- Load sprint track (looped, Movement priority — plays in Sprint locomotion state).
    local sprintId: string = tostring(fp.sprint or "")
    if sprintId ~= "" and sprintId ~= "rbxassetid://0" then
        local sprintAnim = Instance.new("Animation")
        sprintAnim.AnimationId = sprintId
        local track = (animator :: Animator):LoadAnimation(sprintAnim)
        track.Looped   = true
        track.Priority = Enum.AnimationPriority.Movement
        weaponSprintTrack = track
    else
        Logger.debug("[ViewModelController] _setupWeaponAnimations: no sprint animation ID for: "
            .. weaponName)
    end

    -- Load ADS in track (one-shot, Action priority — plays once, then adsIdle loops).
    local adsInId: string = tostring(fp.adsIn or "")
    if adsInId ~= "" and adsInId ~= "rbxassetid://0" then
        local adsInAnim = Instance.new("Animation")
        adsInAnim.AnimationId = adsInId
        local track = (animator :: Animator):LoadAnimation(adsInAnim)
        track.Looped   = false
        track.Priority = Enum.AnimationPriority.Action
        weaponAdsInTrack = track
    end

    -- Load ADS idle track (looped, Action priority — loops while ADS is held).
    local adsIdleId: string = tostring(fp.adsIdle or "")
    if adsIdleId ~= "" and adsIdleId ~= "rbxassetid://0" then
        local adsIdleAnim = Instance.new("Animation")
        adsIdleAnim.AnimationId = adsIdleId
        local track = (animator :: Animator):LoadAnimation(adsIdleAnim)
        track.Looped   = true
        track.Priority = Enum.AnimationPriority.Action
        weaponAdsIdleTrack = track
    end

    -- Load ADS out track (one-shot, Action priority — returns to idle/run).
    local adsOutId: string = tostring(fp.adsOut or "")
    if adsOutId ~= "" and adsOutId ~= "rbxassetid://0" then
        local adsOutAnim = Instance.new("Animation")
        adsOutAnim.AnimationId = adsOutId
        local track = (animator :: Animator):LoadAnimation(adsOutAnim)
        track.Looped   = false
        track.Priority = Enum.AnimationPriority.Action
        weaponAdsOutTrack = track
    end

    -- Load ADS fire track (one-shot, Action2 priority — plays while ADS, overlays adsIdle).
    local adsFireId: string = tostring(fp.adsFire or "")
    if adsFireId ~= "" and adsFireId ~= "rbxassetid://0" then
        local adsFireAnim = Instance.new("Animation")
        adsFireAnim.AnimationId = adsFireId
        local track = (animator :: Animator):LoadAnimation(adsFireAnim)
        track.Looped   = false
        track.Priority = Enum.AnimationPriority.Action2
        weaponAdsFireTrack = track
    end

    Logger.debug("[ViewModelController] _setupWeaponAnimations: tracks loaded for: " .. weaponName)
end

-- Private: loads third-person weapon AnimationTracks onto the character's Humanoid.Animator.
-- All tracks overlay movement animations via animation priority:
--   equip / idle — Action   (overlays MovementController's Idle/Movement-priority tracks)
--   fire / reload — Action2 (overlays the TP idle while shooting or reloading)
-- Safe to call when thirdPerson animations are absent from WeaponData — silently skips.
function ViewModelController:_setupThirdPersonWeaponAnimations(weaponName: string, data: any)
    local animator = getCharacterAnimator()
    if not animator then
        Logger.debug("[ViewModelController] _setupThirdPersonWeaponAnimations: no character animator — skipped")
        return
    end

    local anims = data.animations
    if not anims then return end
    local tp = anims.thirdPerson
    if not tp then
        Logger.debug("[ViewModelController] _setupThirdPersonWeaponAnimations: no thirdPerson block for: " .. weaponName)
        return
    end

    -- Helper to load one track.
    local function loadTp(id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
        local idStr = tostring(id or "")
        if idStr == "" or idStr == "rbxassetid://0" then return nil end
        local anim = Instance.new("Animation")
        anim.AnimationId = idStr
        local track = (animator :: Animator):LoadAnimation(anim)
        track.Looped   = looped
        track.Priority = priority
        return track
    end

    tpEquipTrack   = loadTp(tp.equip   or "", false, Enum.AnimationPriority.Action)
    tpIdleTrack    = loadTp(tp.idle    or "", true,  Enum.AnimationPriority.Action)
    tpFireTrack    = loadTp(tp.fire    or "", false, Enum.AnimationPriority.Action2)
    tpReloadTrack  = loadTp(tp.reload  or "", false, Enum.AnimationPriority.Action2)

    Logger.debug("[ViewModelController] _setupThirdPersonWeaponAnimations: tracks loaded for: " .. weaponName)
end

-- ============================================================
-- Start — registers event listeners, sets up camera follow loop
-- ============================================================

function ViewModelController:Start()
    -- Clear any stale state from a previous session / double-start.
    self:init()

    -- self.model is nil after init() — this is expected.
    -- Unlike the previous AR15 auto-equip behavior, the viewmodel starts holstered.
    -- GunController calls EquipWeapon("AKS74") when key 1 is pressed.

    local localPlayer = Players.LocalPlayer

    -- Apply initial camera mode.
    applyCameraMode()

    -- Re-init and re-apply camera mode on respawn.
    -- init() holsters the weapon and clears animations.  The player must press key 1 again
    -- to re-equip after respawning (DEBT-059: equip state is not persisted across death).
    -- isFirstPerson is reset to FORCE_FIRST_PERSON on respawn so the starting perspective
    -- is always consistent regardless of what the player had switched to before dying.
    localPlayer.CharacterAdded:Connect(function(_character: Model)
        self:init()
        isFirstPerson = Constants.FORCE_FIRST_PERSON  -- reset to default on respawn
        applyCameraMode()
        -- After init(), model is nil → shouldShowViewModel() is false.
        local show = shouldShowViewModel()
        visible    = show
        setVisibility(show)
        Logger.debug("[ViewModelController] State reset on character respawn (weapon holstered)")
    end)

    -- Scroll wheel: toggle between first-person and third-person.
    -- Scroll down while first-person  → switch to third-person (Classic camera).
    -- Scroll up  while third-person + near min zoom → snap back to first-person.
    -- Only active when Constants.CAMERA_PERSPECTIVE_SWITCH_ENABLED is true.
    if Constants.CAMERA_PERSPECTIVE_SWITCH_ENABLED then
        UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
            if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
            local delta: number = input.Position.Z  -- positive = up, negative = down

            if isFirstPerson and not gp and delta < 0 then
                -- Scroll down in first-person → third-person.
                -- Block the switch while ADS is active so the player cannot accidentally
                -- leave first-person in the middle of an aim. ADS exit restores the ability.
                if Constants.ADS_BLOCK_PERSPECTIVE_SWITCH and adsState ~= "Hip" then
                    -- no-op: perspective switch suppressed during ADS
                else
                    setFirstPerson(false)
                end
            elseif not isFirstPerson and delta > 0 then
                -- Scroll up in third-person → snap to first-person when appropriate.
                -- (gp is ignored here: Roblox marks scroll as processed in Classic mode
                --  for its own zoom system, which would prevent our handler from firing.)
                --
                -- Two cases:
                --   1. Shift lock ON: MovementController locks CameraMin=CameraMax=8 studs.
                --      Camera cannot zoom in any further, so any scroll-up should snap
                --      straight to first-person regardless of actual zoom distance.
                --   2. Shift lock OFF: snap only when the player has manually zoomed in
                --      to within CAMERA_FIRST_PERSON_SNAP_THRESHOLD (5 studs).
                local shouldSnap: boolean
                if MovementController:IsCustomMouseLocked() then
                    shouldSnap = true
                else
                    local cam = workspace.CurrentCamera
                    if cam then
                        local zoomDist = (cam.CFrame.Position - cam.Focus.Position).Magnitude
                        shouldSnap = zoomDist <= Constants.CAMERA_FIRST_PERSON_SNAP_THRESHOLD
                    else
                        shouldSnap = false
                    end
                end
                if shouldSnap then
                    setFirstPerson(true)
                end
            end
        end)
    end

    -- Phase listener: update currentPhase and re-evaluate visibility every tick.
    -- Guard on visible intentionally absent: after CharacterAdded re-runs init(), visible
    -- is reset to false, so the next RoundStateChanged must always call setVisibility even
    -- when the phase has not changed since the previous respawn.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        currentPhase   = payload.phase
        local show     = shouldShowViewModel()
        visible        = show
        setVisibility(show)
    end)

    -- RenderStepped: reposition viewmodel + fake ADS idle movement when aiming.
    -- Returns immediately when self.model is nil (holstered), preventing any gravity drop.
    -- Does NOT write camera.CFrame, FieldOfView, or CameraOffset (no FOV zoom in this task).
    RunService.RenderStepped:Connect(function(dt: number)
        local m = self.model
        if not m then return end

        -- Decay positional recoil back to zero.
        if recoilOffset > 0 then
            recoilOffset = math.max(0, recoilOffset - dt * RECOIL_RATE)
        end

        local cam    = workspace.CurrentCamera
        local moveCF = MovementController:GetViewmodelAddCFrame()

        -- ADS state machine: no longer monitors TimePosition for early freeze.
        -- ADS enter animation plays fully to completion; Stopped callback handles Entering → Aiming transition.
        -- This comment block preserved for code archaeology; epsilon-based freeze removed to fix visual cutoff.

        -- Procedural movement suppression while ADS.
        -- Scale procedural movement by (1 - adsAimAlpha) so it fades out smoothly as ADS
        -- engages and fades back in as it exits — no snap when crossing state boundaries.
        local finalMoveCF = moveCF
        if Constants.VIEWMODEL_ADS_DISABLE_PROCEDURAL_MOVEMENT and adsAimAlpha > 0 then
            finalMoveCF = CFrame.new():Lerp(moveCF, 1 - adsAimAlpha)
        end

        -- Free-aim viewmodel lean + mouse inertia + weight system.
        -- ADS (Entering/Aiming): freeAimCF is identity; blended values drain toward zero
        --   so there is no snap on ADS exit.  ADS alignment is preserved unchanged.
        -- Hip/Exiting: build CFrame from normalized offset + mouse inertia, scaled by vmInertiaCurrent.
        local inADS = adsState == "Entering" or adsState == "Aiming"

        -- Inertia weight: lerp toward state-based target each frame.
        local targetWeight: number
        if inADS then
            targetWeight = 0
        elseif isReloading then
            targetWeight = Constants.FREE_AIM_RELOAD_WEIGHT
        elseif isRunning then
            targetWeight = Constants.FREE_AIM_SPRINT_WEIGHT
        else
            targetWeight = Constants.FREE_AIM_HIP_WEIGHT
        end
        vmInertiaCurrent = vmInertiaCurrent
            + (targetWeight - vmInertiaCurrent) * math.min(1, dt * Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED)

        -- Mouse inertia: integrate delta, clamp magnitude, then damp.
        if Constants.FREE_AIM_MOUSE_INERTIA_ENABLED then
            if not inADS then
                vmMouseInertia = vmMouseInertia
                    + vmMouseInertiaDelta * Constants.FREE_AIM_MOUSE_INERTIA_GAIN
                local inertMag = vmMouseInertia.Magnitude
                if inertMag > Constants.FREE_AIM_MOUSE_INERTIA_MAX then
                    vmMouseInertia = vmMouseInertia * (Constants.FREE_AIM_MOUSE_INERTIA_MAX / inertMag)
                end
                vmMouseInertia = vmMouseInertia:Lerp(
                    Vector2.zero,
                    math.min(1, dt * Constants.FREE_AIM_MOUSE_INERTIA_DAMPING)
                )
            else
                vmMouseInertia = vmMouseInertia:Lerp(
                    Vector2.zero,
                    math.min(1, dt * Constants.FREE_AIM_MOUSE_INERTIA_RETURN_SPEED)
                )
            end
        end

        local freeAimCF: CFrame
        if inADS then
            vmFreeAimBlended = vmFreeAimBlended:Lerp(
                Vector2.zero,
                math.min(1, dt * Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED)
            )
            freeAimCF = CFrame.new()
        else
            vmFreeAimBlended = vmFreeAimBlended:Lerp(
                vmFreeAimNormalized,
                math.min(1, dt * Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED)
            )
            local w = vmInertiaCurrent

            -- Inertia X/Y from mouse delta (adds roll momentum when mouse is moving fast).
            local inertiaX: number = 0
            local inertiaY: number = 0
            if Constants.FREE_AIM_MOUSE_INERTIA_ENABLED then
                inertiaX = vmMouseInertia.X
                inertiaY = vmMouseInertia.Y
            end

            -- Rotation: yaw + pitch from aim offset; roll from aim + mouse inertia.
            local freeAimYaw   = vmFreeAimBlended.X * math.rad(Constants.FREE_AIM_VIEWMODEL_YAW_DEGREES) * w
            local freeAimPitch = -vmFreeAimBlended.Y * math.rad(Constants.FREE_AIM_VIEWMODEL_PITCH_DEGREES) * w
            local freeAimRoll  = -(vmFreeAimBlended.X + inertiaX) * math.rad(Constants.FREE_AIM_VIEWMODEL_ROLL_DEGREES) * w

            -- Translation opposite to movement gives the weapon a sense of physical mass.
            local translateX = -(vmFreeAimBlended.X + inertiaX) * Constants.FREE_AIM_VIEWMODEL_TRANSLATE_X * w
            local translateY = -(vmFreeAimBlended.Y + inertiaY) * Constants.FREE_AIM_VIEWMODEL_TRANSLATE_Y * w
            local translateZ =  vmFreeAimBlended.Magnitude * Constants.FREE_AIM_VIEWMODEL_TRANSLATE_Z * w

            freeAimCF = CFrame.new(translateX, translateY, translateZ)
                * CFrame.Angles(freeAimPitch, freeAimYaw, freeAimRoll)
        end

        -- ── Procedural sway (mouse lag, movement bob, strafe roll) ───────────
        -- Weight lerps toward state-based target each frame.
        -- ADS ≈ 0, reload = 15%, sprint = 45%, hip = 100%.
        -- swayCF is inserted between freeAimCF and finalMoveCF; absent from aimAlignedPivot.
        local swayWeightTarget: number
        if inADS then
            swayWeightTarget = Constants.VIEWMODEL_SWAY_ADS_WEIGHT :: number
        elseif isReloading then
            swayWeightTarget = Constants.VIEWMODEL_SWAY_RELOAD_WEIGHT :: number
        elseif isRunning then
            swayWeightTarget = Constants.VIEWMODEL_SWAY_SPRINT_WEIGHT :: number
        else
            swayWeightTarget = Constants.VIEWMODEL_SWAY_HIP_WEIGHT :: number
        end
        vmSwayWeight = vmSwayWeight
            + (swayWeightTarget - vmSwayWeight)
            * math.min(1, dt * (Constants.VIEWMODEL_SWAY_MOUSE_SMOOTH_SPEED :: number))
        local swayW = vmSwayWeight

        local swayCF: CFrame
        if Constants.VIEWMODEL_SWAY_ENABLED then
            -- Mouse-look weapon lag (two-spring model).
            -- vmSwayMouseTarget accumulates raw mouse delta, clamped + decayed toward zero.
            -- vmSwayMouseCurrent smoothly chases vmSwayMouseTarget for extra lag feel.
            local md = UserInputService:GetMouseDelta()
            vmSwayMouseTarget = vmSwayMouseTarget + Vector2.new(md.X, md.Y)
            local swayMag = vmSwayMouseTarget.Magnitude
            local swayMax = Constants.VIEWMODEL_SWAY_MOUSE_MAX :: number
            if swayMag > swayMax then
                vmSwayMouseTarget = vmSwayMouseTarget * (swayMax / swayMag)
            end
            vmSwayMouseTarget = vmSwayMouseTarget:Lerp(
                Vector2.zero,
                math.min(1, dt * (Constants.VIEWMODEL_SWAY_MOUSE_RETURN_SPEED :: number))
            )
            vmSwayMouseCurrent = vmSwayMouseCurrent:Lerp(
                vmSwayMouseTarget,
                math.min(1, dt * (Constants.VIEWMODEL_SWAY_MOUSE_SMOOTH_SPEED :: number))
            )
            local sv        = vmSwayMouseCurrent
            local swayYaw   = math.rad(sv.X * (Constants.VIEWMODEL_SWAY_MOUSE_YAW_DEGREES :: number)) * swayW
            local swayPitch = math.rad(sv.Y * (Constants.VIEWMODEL_SWAY_MOUSE_PITCH_DEGREES :: number)) * swayW
            local swayRoll  = math.rad(-sv.X * (Constants.VIEWMODEL_SWAY_MOUSE_ROLL_DEGREES :: number)) * swayW
            local swayTX    = -sv.X * (Constants.VIEWMODEL_SWAY_MOUSE_TRANSLATE_X :: number) * swayW
            local swayTY    = -sv.Y * (Constants.VIEWMODEL_SWAY_MOUSE_TRANSLATE_Y :: number) * swayW

            -- Shared movement + physics state for all procedural effects.
            local char = Players.LocalPlayer.Character
            local hum: Humanoid? = nil
            local hrp: BasePart?  = nil
            if char then
                hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
                hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            end
            local moveDir: Vector3 = if hum then hum.MoveDirection else Vector3.zero
            local velXYZ:  Vector3 = if hrp then hrp.AssemblyLinearVelocity else Vector3.zero
            local horizSpeed = Vector2.new(velXYZ.X, velXYZ.Z).Magnitude

            -- Movement bob: smoothly lerped amplitude and speed eliminate pops on state changes.
            -- Horizontal velocity magnitude drives isMoving so sliding continues the bob and
            -- standing still (pressed against wall) correctly zeroes it.
            -- Four outputs: Y (vertical), X (lateral figure-8), Z (depth per step), bobPitch (nod).
            local bobTX:    number = 0
            local bobTY:    number = 0
            local bobTZ:    number = 0
            local bobPitch: number = 0
            if Constants.VIEWMODEL_MOVE_BOB_ENABLED then
                local isMoving = horizSpeed > 0.5
                local bobAmountTarget: number = 0
                local bobSpeedTarget:  number = Constants.VIEWMODEL_WALK_BOB_SPEED :: number
                if isMoving then
                    local ms = MovementController:GetMoveState()
                    if ms == "Sprinting" then
                        bobAmountTarget = Constants.VIEWMODEL_SPRINT_BOB_AMOUNT :: number
                        bobSpeedTarget  = Constants.VIEWMODEL_SPRINT_BOB_SPEED  :: number
                    elseif ms == "Crouching" then
                        bobAmountTarget = Constants.VIEWMODEL_CROUCH_BOB_AMOUNT :: number
                        bobSpeedTarget  = Constants.VIEWMODEL_CROUCH_BOB_SPEED  :: number
                    else
                        bobAmountTarget = Constants.VIEWMODEL_WALK_BOB_AMOUNT :: number
                    end
                end
                vmBobAmountCurrent = vmBobAmountCurrent
                    + (bobAmountTarget - vmBobAmountCurrent)
                    * math.min(1, dt * (Constants.VIEWMODEL_BOB_AMOUNT_BLEND_SPEED :: number))
                vmBobSpeedCurrent = vmBobSpeedCurrent
                    + (bobSpeedTarget - vmBobSpeedCurrent)
                    * math.min(1, dt * (Constants.VIEWMODEL_BOB_SPEED_BLEND_SPEED :: number))
                if vmBobAmountCurrent > 0.0001 then
                    vmBobTime = (vmBobTime + dt * vmBobSpeedCurrent) % (math.pi * 2)
                else
                    vmBobTime = vmBobTime
                        * math.max(0, 1 - dt * (Constants.VIEWMODEL_MOVE_BOB_SMOOTH_SPEED :: number))
                end
                local sinT = math.sin(vmBobTime)
                local cosT = math.cos(vmBobTime)
                local amt  = vmBobAmountCurrent
                -- Vertical: rises between footfalls, dips at footfall.
                bobTY = sinT * amt * swayW
                -- Lateral: cos(t) is 90° out-of-phase — creates a circular figure-8 path.
                bobTX = cosT * amt * (Constants.VIEWMODEL_WALK_BOB_LATERAL_FACTOR :: number) * swayW
                -- Depth: gun compresses toward camera at each footfall (sinT < 0 → +Z toward cam).
                bobTZ = -sinT * amt * (Constants.VIEWMODEL_BOB_DEPTH_FACTOR :: number) * swayW
                -- Pitch nod: muzzle dips in phase with vertical bob for natural weight feel.
                bobPitch = sinT * amt * (Constants.VIEWMODEL_BOB_PITCH_FACTOR :: number) * swayW
            end

            -- Strafe roll + translate: spring-damper for organic overshoot on direction reversal.
            -- Using moveDir (normalised input) so wall-pressing produces no false strafe.
            local strafeRoll: number = 0
            local strafeTX:   number = 0
            if Constants.VIEWMODEL_STRAFE_ROLL_ENABLED then
                local strafeDot = cam.CFrame.RightVector:Dot(moveDir)
                local sF = (Constants.VIEWMODEL_STRAFE_SPRING_K :: number) * (strafeDot - vmStrafeLag)
                         - (Constants.VIEWMODEL_STRAFE_SPRING_D :: number) * vmStrafeLagVel
                vmStrafeLagVel = vmStrafeLagVel + sF * dt
                vmStrafeLag    = math.clamp(vmStrafeLag + vmStrafeLagVel * dt, -1.5, 1.5)
                strafeRoll = math.rad(-vmStrafeLag * (Constants.VIEWMODEL_STRAFE_ROLL_DEGREES :: number)) * swayW
                strafeTX   = -vmStrafeLag * (Constants.VIEWMODEL_STRAFE_TRANSLATE_X :: number) * swayW
            end

            -- Vertical velocity tilt: spring-damper so jump apex and landing have organic bounce.
            -- velY > 0 = rising (muzzle up), velY < 0 = falling (muzzle down).
            local vertTiltPitch: number = 0
            if Constants.VIEWMODEL_VERT_TILT_ENABLED then
                local tiltTarget = math.clamp(
                    velXYZ.Y * (Constants.VIEWMODEL_VERT_TILT_SCALE :: number),
                    -(Constants.VIEWMODEL_VERT_TILT_MAX :: number),
                     (Constants.VIEWMODEL_VERT_TILT_MAX :: number))
                local vF = (Constants.VIEWMODEL_VERT_TILT_SPRING_K :: number) * (tiltTarget - vmVertTilt)
                         - (Constants.VIEWMODEL_VERT_TILT_SPRING_D :: number) * vmVertTiltVel
                vmVertTiltVel = vmVertTiltVel + vF * dt
                vmVertTilt    = vmVertTilt    + vmVertTiltVel * dt
                vertTiltPitch = vmVertTilt
            end

            -- Forward lean: spring-damper so stopping produces a slight forward swing.
            -- Moving forward → +Z (gun toward camera, inertia lag feel).
            -- Stopping → spring overshoots slightly to -Z then returns (gun swings forward).
            local forwardLeanZ: number = 0
            if Constants.VIEWMODEL_FORWARD_LEAN_ENABLED then
                local forwardVel = cam.CFrame.LookVector:Dot(velXYZ)
                local leanTarget = math.clamp(
                    forwardVel * (Constants.VIEWMODEL_FORWARD_LEAN_SCALE :: number),
                    -(Constants.VIEWMODEL_FORWARD_LEAN_MAX :: number),
                     (Constants.VIEWMODEL_FORWARD_LEAN_MAX :: number))
                local fF = (Constants.VIEWMODEL_FORWARD_LEAN_SPRING_K :: number) * (leanTarget - vmForwardLean)
                         - (Constants.VIEWMODEL_FORWARD_LEAN_SPRING_D :: number) * vmForwardLeanVel
                vmForwardLeanVel = vmForwardLeanVel + fF * dt
                vmForwardLean    = vmForwardLean    + vmForwardLeanVel * dt
                forwardLeanZ = vmForwardLean
            end

            -- Acceleration tilt: gun pitches back when player accelerates, forward when decelerating.
            -- Captures the rotational inertia component that forward lean (translational) misses.
            -- rawAccel > 0 = speeding up → muzzle up (positive pitch); < 0 = braking → muzzle dips.
            local accelTiltPitch: number = 0
            if Constants.VIEWMODEL_ACCEL_TILT_ENABLED then
                local rawAccel = (horizSpeed - vmHorizSpeedPrev) / math.max(dt, 0.001)
                vmHorizSpeedPrev = horizSpeed
                local accelTarget = math.clamp(
                    rawAccel * (Constants.VIEWMODEL_ACCEL_TILT_SCALE :: number),
                    -(Constants.VIEWMODEL_ACCEL_TILT_MAX :: number),
                     (Constants.VIEWMODEL_ACCEL_TILT_MAX :: number))
                vmAccelTilt = vmAccelTilt
                    + (accelTarget - vmAccelTilt)
                    * math.min(1, dt * (Constants.VIEWMODEL_ACCEL_TILT_SMOOTH :: number))
                accelTiltPitch = vmAccelTilt
            end

            -- Landing dip spring: gun bounces down and recovers on impact.
            -- Impulse fired when Y velocity crosses the threshold from below (landing edge).
            -- Roll is derived from dip displacement — follows the same spring at no extra cost.
            local landDipY:    number = 0
            local landDipRoll: number = 0
            if Constants.VIEWMODEL_LAND_DIP_ENABLED then
                local velY = velXYZ.Y
                if vmPrevVelY < (Constants.VIEWMODEL_LAND_DIP_THRESHOLD :: number)
                    and velY >= (Constants.VIEWMODEL_LAND_DIP_THRESHOLD :: number)
                then
                    local impact = math.min(math.abs(vmPrevVelY), 60)
                    vmLandDipVel = vmLandDipVel - impact * (Constants.VIEWMODEL_LAND_DIP_SCALE :: number)
                end
                vmPrevVelY = velY
                local dF = -(Constants.VIEWMODEL_LAND_DIP_SPRING :: number) * vmLandDip
                         - (Constants.VIEWMODEL_LAND_DIP_DAMPING :: number) * vmLandDipVel
                vmLandDipVel = vmLandDipVel + dF * dt
                vmLandDip    = vmLandDip    + vmLandDipVel * dt
                landDipY    = vmLandDip
                landDipRoll = vmLandDip * (Constants.VIEWMODEL_LAND_DIP_ROLL_SCALE :: number)
            end

            -- Idle breathing: three-frequency Lissajous for a non-repeating organic idle.
            -- Frequencies 1 : 0.5 : 0.75 (incommensurable ratios) prevent audible looping.
            -- breathWeight fades in when stationary, out when moving.
            local breathX:    number = 0
            local breathY:    number = 0
            local breathRoll: number = 0
            if Constants.VIEWMODEL_BREATH_ENABLED then
                vmBreathTime = (vmBreathTime + dt * (Constants.VIEWMODEL_BREATH_SPEED :: number) * math.pi * 2)
                    % (math.pi * 4)
                local breathTarget = if vmBobAmountCurrent < 0.0005 then 1 else 0
                vmBreathWeight = vmBreathWeight
                    + (breathTarget - vmBreathWeight)
                    * math.min(1, dt * (Constants.VIEWMODEL_BREATH_BLEND_SPEED :: number))
                local bw = vmBreathWeight * swayW
                breathY    = math.sin(vmBreathTime)
                    * (Constants.VIEWMODEL_BREATH_AMOUNT_Y :: number) * bw
                breathX    = math.sin(vmBreathTime * 0.5 + math.pi / 3)
                    * (Constants.VIEWMODEL_BREATH_AMOUNT_X :: number) * bw
                breathRoll = math.sin(vmBreathTime * 0.75 + math.pi / 6)
                    * (Constants.VIEWMODEL_BREATH_AMOUNT_ROLL :: number) * bw
            end

            swayCF = CFrame.new(
                swayTX + strafeTX + bobTX + breathX,
                swayTY + bobTY + landDipY + breathY,
                forwardLeanZ + bobTZ
            ) * CFrame.Angles(
                swayPitch + vertTiltPitch + bobPitch + accelTiltPitch,
                swayYaw,
                swayRoll + strafeRoll + landDipRoll + breathRoll
            )
        else
            swayCF = CFrame.new()
        end

        -- ADS pivot alignment.
        -- The ADS animation targets FakeCamera, but the hip pivot chain places FakeCamera at
        -- cam.CFrame * CAMERA_EXTRA_OFFSET rather than cam.CFrame.  To fix this, adsAimAlpha
        -- blends the pivot toward a chain that omits CAMERA_EXTRA_OFFSET so BASE_OFFSET places
        -- FakeCamera exactly at cam.CFrame when alpha=1 — matching where the animation aims.
        -- freeAimCF and finalMoveCF are already CFrame.new() during ADS (zeroed above).
        -- Tick down the hold timer that prevents pivot decay immediately after
        -- StopADSAnimations (reload-interrupts-ADS path).
        if adsAimHoldTimer > 0 then
            adsAimHoldTimer = math.max(0, adsAimHoldTimer - dt)
        end

        -- adsAimTarget = 1 whenever any ADS activity is in progress:
        --   Entering/Aiming  — ADS engaging or held
        --   Exiting          — adsOut playing; pivot must stay ADS-aligned for its full
        --                      duration so the barrel doesn't clip through the camera as
        --                      the animation and the pivot shift at different rates
        --   adsAimHoldTimer  — brief grace window after StopADSAnimations so the
        --                      adsIdle/adsIn fade completes before the pivot moves
        local adsAimTarget: number = 0
        if adsState ~= "Hip" or adsAimHoldTimer > 0 then
            adsAimTarget = 1
        end
        adsAimAlpha = adsAimAlpha
            + (adsAimTarget - adsAimAlpha) * math.min(1, dt * Constants.VIEWMODEL_ADS_AIM_BLEND_SPEED)

        -- ── Viewmodel recoil (data-driven per weapon profile) ───────────────
        -- vmRecoilCurrent chases vmRecoilTarget at vmActiveKickSpeed (set by ApplyRecoil).
        -- vmRecoilTarget decays to identity at vmActiveRecoverySpeed.
        -- vmRecoilBuildup decays at half the recovery rate between shots.
        -- Both CFrames are identity when VIEWMODEL_RECOIL_ENABLED is false.
        local vmRecoilCF: CFrame
        if Constants.VIEWMODEL_RECOIL_ENABLED then
            vmRecoilCurrent = vmRecoilCurrent:Lerp(
                vmRecoilTarget,
                math.min(1, dt * vmActiveKickSpeed)
            )
            vmRecoilTarget = vmRecoilTarget:Lerp(
                CFrame.new(),
                math.min(1, dt * vmActiveRecoverySpeed)
            )
            if vmRecoilBuildup > 0 then
                vmRecoilBuildup = math.max(0, vmRecoilBuildup - dt * vmActiveRecoverySpeed * 0.5)
            end
            vmRecoilCF = vmRecoilCurrent
        else
            vmRecoilCF = CFrame.new()
        end

        -- ── Camera rotation inertia ───────────────────────────────────────────────────────
        -- Measures camera rotation delta frame-to-frame and applies an opposite angular/
        -- translational offset so the gun appears to have weight behind camera turns.
        -- Excluded from aimAlignedPivot → ADS alignment is exact and unaffected.
        -- CFrame stack position: after CAMERA_EXTRA_OFFSET, before recoil layers.
        local cameraInertiaCF: CFrame = CFrame.new()
        do
            -- State-based multiplier (lerped, not snapped, for smooth transitions).
            -- isMovingFast covers both Run (shift-held) and Sprint (tactical) locomotion.
            local isMovingFast = vmLocomotionState == "Run" or vmLocomotionState == "Sprint"
            local isEquipping  = weaponEquipTrack ~= nil
                and (weaponEquipTrack :: AnimationTrack).IsPlaying
            local inertiaTarget: number
            if inADS then
                inertiaTarget = Constants.VIEWMODEL_CAMERA_INERTIA_ADS_MULTIPLIER
            elseif isReloading then
                inertiaTarget = Constants.VIEWMODEL_CAMERA_INERTIA_RELOAD_MULTIPLIER
            elseif isEquipping then
                inertiaTarget = Constants.VIEWMODEL_CAMERA_INERTIA_EQUIP_MULTIPLIER
            elseif isMovingFast then
                inertiaTarget = Constants.VIEWMODEL_CAMERA_INERTIA_SPRINT_MULTIPLIER
            else
                inertiaTarget = 1
            end
            if Constants.VIEWMODEL_CAMERA_INERTIA_DEBUG
                and inertiaTarget ~= vmCamInertiaLastTarget
            then
                vmCamInertiaLastTarget = inertiaTarget
                Logger.debug(string.format(
                    "[VMC] Camera inertia multiplier → %.2f (ads=%s reload=%s equip=%s fast=%s)",
                    inertiaTarget, tostring(inADS), tostring(isReloading),
                    tostring(isEquipping), tostring(isMovingFast)
                ))
            end
            vmCamInertiaWeight = vmCamInertiaWeight
                + (inertiaTarget - vmCamInertiaWeight)
                * math.min(1, dt * (Constants.VIEWMODEL_CAMERA_INERTIA_SPRING_SPEED :: number))

            if Constants.VIEWMODEL_CAMERA_INERTIA_ENABLED then
                -- Rotation delta in previous frame's camera-local space.
                -- ToObjectSpace(cur) = prevInverse * cur = "how much did cam rotate since last frame"
                local rotDelta = vmPrevCamCFrame:ToObjectSpace(cam.CFrame)
                local rx, ry, _ = rotDelta:ToEulerAnglesYXZ()
                -- rx: pitch delta (negative when camera looks up in Roblox convention)
                -- ry: yaw delta   (positive when camera turns right)

                -- Guard: large angular jump (teleport, respawn, death) → reset displacement to zero.
                -- Threshold: 45° total angular change is impossible at normal sensitivity in one frame.
                if math.abs(rx) + math.abs(ry) > math.rad(45) then
                    vmCamInertiaYaw   = 0
                    vmCamInertiaPitch = 0
                    vmCamInertiaRoll  = 0
                    vmCamInertiaTX    = 0
                    vmCamInertiaTY    = 0
                    if Constants.VIEWMODEL_CAMERA_INERTIA_DEBUG then
                        Logger.debug(string.format(
                            "[VMC] Camera inertia: large-delta reset (Δyaw=%.1f° Δpitch=%.1f°)",
                            math.deg(ry), math.deg(rx)
                        ))
                    end
                else
                    local w = vmCamInertiaWeight
                    -- Accumulate opposite-direction displacement (gun lags behind camera turn).
                    -- Sign convention (verified in Studio — invert here if observed backwards):
                    --   camera right (+ry) → gun lags left  → negative yaw offset
                    --   camera up   (-rx)  → gun lags down  → positive pitch offset (+pitch = muzzle down)
                    --   camera right (+ry) → barrel tilts   → negative roll offset
                    vmCamInertiaYaw   -= ry * (Constants.VIEWMODEL_CAMERA_INERTIA_YAW_STRENGTH   :: number) * w
                    vmCamInertiaPitch -= rx * (Constants.VIEWMODEL_CAMERA_INERTIA_PITCH_STRENGTH :: number) * w
                    vmCamInertiaRoll  -= ry * (Constants.VIEWMODEL_CAMERA_INERTIA_ROLL_STRENGTH  :: number) * w
                    vmCamInertiaTX    -= ry * (Constants.VIEWMODEL_CAMERA_INERTIA_POSITION_X_STRENGTH :: number) * w
                    vmCamInertiaTY    -= rx * (Constants.VIEWMODEL_CAMERA_INERTIA_POSITION_Y_STRENGTH :: number) * w

                    -- Clamp to maximum displacement (prevents wild swings on high-speed camera moves).
                    local maxYr = math.rad(Constants.VIEWMODEL_CAMERA_INERTIA_MAX_YAW_DEGREES   :: number)
                    local maxPr = math.rad(Constants.VIEWMODEL_CAMERA_INERTIA_MAX_PITCH_DEGREES :: number)
                    local maxRr = math.rad(Constants.VIEWMODEL_CAMERA_INERTIA_MAX_ROLL_DEGREES  :: number)
                    local maxTX = Constants.VIEWMODEL_CAMERA_INERTIA_MAX_POSITION_X :: number
                    local maxTY = Constants.VIEWMODEL_CAMERA_INERTIA_MAX_POSITION_Y :: number
                    vmCamInertiaYaw   = math.clamp(vmCamInertiaYaw,   -maxYr, maxYr)
                    vmCamInertiaPitch = math.clamp(vmCamInertiaPitch, -maxPr, maxPr)
                    vmCamInertiaRoll  = math.clamp(vmCamInertiaRoll,  -maxRr, maxRr)
                    vmCamInertiaTX    = math.clamp(vmCamInertiaTX,    -maxTX, maxTX)
                    vmCamInertiaTY    = math.clamp(vmCamInertiaTY,    -maxTY, maxTY)

                    -- Spring decay toward zero.
                    -- effectiveDecayRate = SPRING_SPEED * (1 - DAMPING) = 18 * 0.18 = 3.24 /s
                    -- → half-life ≈ 0.21 s; gun settles in ~0.5 s after camera stops.
                    local returnRate  = (Constants.VIEWMODEL_CAMERA_INERTIA_SPRING_SPEED :: number)
                        * (1 - (Constants.VIEWMODEL_CAMERA_INERTIA_DAMPING :: number))
                    local decayFactor = math.max(0, 1 - dt * returnRate)
                    vmCamInertiaYaw   *= decayFactor
                    vmCamInertiaPitch *= decayFactor
                    vmCamInertiaRoll  *= decayFactor
                    vmCamInertiaTX    *= decayFactor
                    vmCamInertiaTY    *= decayFactor
                end

                -- Always update prev CFrame (avoids stale large-delta on re-enable or next frame).
                vmPrevCamCFrame = cam.CFrame

                cameraInertiaCF = CFrame.new(vmCamInertiaTX, vmCamInertiaTY, 0)
                    * CFrame.Angles(vmCamInertiaPitch, vmCamInertiaYaw, vmCamInertiaRoll)
            else
                -- Disabled: keep prev CFrame current so re-enable has no jump.
                vmPrevCamCFrame = cam.CFrame
            end
        end

        -- Movement velocity inertia: gun lags behind player movement, giving the weapon a sense of mass.
        -- Strafe right → gun shifts left; move forward → gun settles back; stop → gun catches up.
        -- Excluded from aimAlignedPivot so ADS alignment stays exact and bullet direction is unaffected.
        local movementInertiaCF: CFrame = CFrame.new()
        do
            -- State-based multiplier (same lerp pattern as camera rotation inertia).
            local movInertiaTarget: number = 1
            if inADS then
                movInertiaTarget = Constants.VIEWMODEL_MOVEMENT_INERTIA_ADS_MULTIPLIER :: number
            elseif isReloading then
                movInertiaTarget = Constants.VIEWMODEL_MOVEMENT_INERTIA_RELOAD_MULTIPLIER :: number
            elseif vmLocomotionState == "Sprint" then
                movInertiaTarget = Constants.VIEWMODEL_MOVEMENT_INERTIA_SPRINT_MULTIPLIER :: number
            elseif MovementController:GetMoveState() == "Crouching" then
                movInertiaTarget = Constants.VIEWMODEL_MOVEMENT_INERTIA_CROUCH_MULTIPLIER :: number
            end
            if Constants.VIEWMODEL_MOVEMENT_INERTIA_DEBUG :: boolean
                and movInertiaTarget ~= vmMovInertiaLastTarget
            then
                vmMovInertiaLastTarget = movInertiaTarget
                Logger.debug(string.format(
                    "[VMC] Movement inertia weight → %.2f (ads=%s reload=%s loco=%s)",
                    movInertiaTarget, tostring(inADS), tostring(isReloading), vmLocomotionState
                ))
            end
            vmMovInertiaWeight = vmMovInertiaWeight
                + (movInertiaTarget - vmMovInertiaWeight)
                * math.min(1, dt * (Constants.VIEWMODEL_MOVEMENT_INERTIA_SPRING_SPEED :: number))

            if Constants.VIEWMODEL_MOVEMENT_INERTIA_ENABLED :: boolean then
                -- Independent HRP lookup — not scoped to the sway block; works even when sway is off.
                local char3 = Players.LocalPlayer.Character
                local hrp3: BasePart? = if char3 then char3:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
                local velWorld: Vector3 = if hrp3 then hrp3.AssemblyLinearVelocity else Vector3.zero

                -- Min-speed gate: ignore physics jitter below MIN_SPEED.
                local hSpd3 = Vector2.new(velWorld.X, velWorld.Z).Magnitude
                if hSpd3 >= (Constants.VIEWMODEL_MOVEMENT_INERTIA_MIN_SPEED :: number) then
                    local maxRef = Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_SPEED_REFERENCE :: number
                    -- Project world velocity onto camera axes.
                    local localX   = math.clamp(cam.CFrame.RightVector:Dot(velWorld),  -maxRef, maxRef)
                    local localFwd = math.clamp(cam.CFrame.LookVector:Dot(velWorld),   -maxRef, maxRef)
                    local localY   = math.clamp(velWorld.Y,                             -maxRef, maxRef)

                    local w  = vmMovInertiaWeight
                    local sx = Constants.VIEWMODEL_MOVEMENT_INERTIA_STRAFE_X_STRENGTH   :: number
                    local sz = Constants.VIEWMODEL_MOVEMENT_INERTIA_FORWARD_Z_STRENGTH  :: number
                    local sy = Constants.VIEWMODEL_MOVEMENT_INERTIA_VERTICAL_Y_STRENGTH :: number

                    -- Accumulate opposite to velocity: strafe right → gun left (−X);
                    -- move forward → gun settles back (+Z toward viewer); move up → gun drops (−Y).
                    vmMovInertiaX -= localX   * sx * w * dt
                    vmMovInertiaZ += localFwd * sz * w * dt
                    vmMovInertiaY -= localY   * sy * w * dt
                end

                -- Hard clamp to maximum displacement.
                local maxX = Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_X :: number
                local maxY = Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_Y :: number
                local maxZ = Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_Z :: number
                vmMovInertiaX = math.clamp(vmMovInertiaX, -maxX, maxX)
                vmMovInertiaY = math.clamp(vmMovInertiaY, -maxY, maxY)
                vmMovInertiaZ = math.clamp(vmMovInertiaZ, -maxZ, maxZ)

                -- Exponential spring decay toward zero.
                local returnRate3 = (Constants.VIEWMODEL_MOVEMENT_INERTIA_SPRING_SPEED :: number)
                    * (1 - (Constants.VIEWMODEL_MOVEMENT_INERTIA_DAMPING :: number))
                local decayFactor3 = math.max(0, 1 - dt * returnRate3)
                vmMovInertiaX *= decayFactor3
                vmMovInertiaY *= decayFactor3
                vmMovInertiaZ *= decayFactor3

                -- Derive rotation from position offsets (computed each frame from position state; no extra spring).
                local maxRollR  = math.rad(Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_ROLL_DEGREES  :: number)
                local maxPitchR = math.rad(Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_PITCH_DEGREES :: number)
                -- Roll: strafe right → X offset positive → gun rolls right (same direction as shift).
                local movRoll  = math.clamp(
                    vmMovInertiaX * (Constants.VIEWMODEL_MOVEMENT_INERTIA_ROLL_STRENGTH :: number),
                    -maxRollR, maxRollR
                )
                -- Pitch: forward settle → Z offset positive (+Z) → gun tips slightly down (−pitch).
                local movPitch = math.clamp(
                    -vmMovInertiaZ * (Constants.VIEWMODEL_MOVEMENT_INERTIA_PITCH_STRENGTH :: number),
                    -maxPitchR, maxPitchR
                )

                movementInertiaCF = CFrame.new(vmMovInertiaX, vmMovInertiaY, vmMovInertiaZ)
                    * CFrame.Angles(movPitch, 0, movRoll)
            end
        end

        -- Hip base pivot (full chain).
        -- CFrame stack (hip):
        --   cam.CFrame                — world camera reference
        --   CAMERA_EXTRA_OFFSET       — constant screen-space base offset
        --   cameraInertiaCF           — camera-turn inertia lag (viewmodel-only; not in ADS pivot)
        --   movementInertiaCF         — movement velocity inertia lag (viewmodel-only; not in ADS pivot)
        --   viewRecoilCFrame          — camera-space rotational recoil from GunController
        --   vmRecoilCF                — data-driven gun-kick recoil (pitch/yaw/roll spring)
        --   freeAimCF                 — free-aim drift offset (mouse deadzone visual)
        --   swayCF                    — procedural sway (mouse lag, bob, strafe, breath)
        --   finalMoveCF               — movement/bob CFrame from MovementController
        --   BASE_OFFSET               — rig FakeCamera-relative alignment offset
        --   CFrame.new(0,0,recoilOffset) — positional push-back recoil
        local basePivot = cam.CFrame
            * CAMERA_EXTRA_OFFSET
            * cameraInertiaCF
            * movementInertiaCF
            * viewRecoilCFrame
            * vmRecoilCF
            * freeAimCF
            * swayCF
            * finalMoveCF
            * BASE_OFFSET
            * CFrame.new(0, 0, recoilOffset)

        if adsAimAlpha > 0.001 then
            -- ADS-aligned pivot: no CAMERA_EXTRA_OFFSET → FakeCamera lands at cam.CFrame.
            -- viewRecoilCFrame and vmRecoilCF are both preserved so weapon kick is visible
            -- while aiming. freeAimCF and finalMoveCF are already identity during ADS.
            local aimAlignedPivot = cam.CFrame
                * viewRecoilCFrame
                * vmRecoilCF
                * BASE_OFFSET
                * CFrame.new(0, 0, recoilOffset)
            m:PivotTo(basePivot:Lerp(aimAlignedPivot, adsAimAlpha))
        else
            m:PivotTo(basePivot)
        end
    end)

    Logger.debug("[ViewModelController] Ready")
end

-- ============================================================
-- Public methods — fire, recoil, muzzle (called by GunController)
-- ============================================================

-- Called by GunController immediately after WeaponFired:FireServer().
-- Applies a positional recoil snap and plays the fire one-shot animation.
-- Blocked while reloading (reload priority > fire).
-- Restartable: each shot re-plays the fire track from the start, even if it is still playing.
function ViewModelController:PlayFireAnimation()
    local model = self.model
    if not model then return end
    -- Reload takes priority over fire; do not play fire during a reload.
    if isReloading then return end
    -- Positional recoil snap — decays back to zero in RenderStepped.
    recoilOffset = RECOIL_DIST
    model:PivotTo(model:GetPivot() * CFrame.new(0, 0, recoilOffset))
    -- First-person: fire track plays on top of idle/run.
    -- Stop immediately and restart for per-shot restartability.
    if weaponFireTrack then
        if weaponFireTrack.IsPlaying then
            weaponFireTrack:Stop(0)
        end
        weaponFireTrack:Play()
        Logger.debug("[ViewModelController] PlayFireAnimation: FP fire track started")
    end
    -- Third-person: same pattern — restart per shot so rapid fire always plays from frame 0.
    if tpFireTrack then
        if tpFireTrack.IsPlaying then
            tpFireTrack:Stop(0)
        end
        tpFireTrack:Play()
    end
end

-- Plays the run AnimationTrack (looped, Movement priority).
-- Called by SetRunning when sprint begins and the base state transitions from idle to run.
-- fadeTime defaults to VIEWMODEL_IDLE_RUN_FADE_TIME for smooth crossfades from idle/reload.
-- No-op when no run track is loaded.
function ViewModelController:PlayRunAnimation(fadeTime: number?)
    if weaponRunTrack then
        weaponRunTrack:Play(fadeTime or (Constants.VIEWMODEL_IDLE_RUN_FADE_TIME :: number))
        Logger.debug("[ViewModelController] PlayRunAnimation: run track started")
    else
        Logger.debug("[ViewModelController] PlayRunAnimation: no run track loaded — skipped")
    end
end

-- Plays the reload AnimationTrack (one-shot).  Called by GunController when R is pressed.
-- Guards:
--   • no weapon equipped  → no-op
--   • already reloading   → no-op (spam protection; reload is not restartable)
--   • no reload track     → no-op
-- While reload plays: fire and run are blocked.
-- When reload ends: resumes run if isRunning, else resumes idle.
function ViewModelController:PlayReloadAnimation()
    if not self.model then return end
    if isReloading then
        Logger.debug("[ViewModelController] PlayReloadAnimation: already reloading — ignored")
        return
    end
    if not weaponReloadTrack then
        Logger.debug("[ViewModelController] PlayReloadAnimation: no reload track loaded — skipped")
        return
    end
    -- Capture weapon identity so the Stopped callback can guard against stale calls.
    local capturedWeapon = equippedWeaponName
    isReloading = true
    -- Exit ADS if active (reload takes priority).
    if adsState ~= "Hip" then
        self:StopADSAnimations()
    end
    -- Stop fire and all locomotion tracks so reload plays unobstructed.
    if weaponFireTrack and weaponFireTrack.IsPlaying then
        weaponFireTrack:Stop(0)
    end
    if weaponRunTrack and weaponRunTrack.IsPlaying then
        weaponRunTrack:Stop()
    end
    if weaponWalkTrack and weaponWalkTrack.IsPlaying then
        weaponWalkTrack:Stop()
    end
    if weaponSprintTrack and weaponSprintTrack.IsPlaying then
        weaponSprintTrack:Stop()
    end
    if weaponEnterRunTrack and weaponEnterRunTrack.IsPlaying then
        weaponEnterRunTrack:Stop(Constants.VIEWMODEL_LOCOMOTION_ENTER_RUN_FADE_TIME :: number)
    end
    vmEnterRunPlaying = false
    if weaponIdleTrack and weaponIdleTrack.IsPlaying then
        weaponIdleTrack:Stop()
    end
    -- Third-person: stop TP fire/idle and play TP reload alongside the FP reload.
    -- TP idle resumes via its own Stopped callback, independent of the FP chain.
    if tpFireTrack and tpFireTrack.IsPlaying then
        tpFireTrack:Stop(0)
    end
    if tpIdleTrack and tpIdleTrack.IsPlaying then
        tpIdleTrack:Stop()
    end
    if tpReloadTrack then
        tpReloadTrack.Stopped:Connect(function()
            -- Guard: resume TP idle only if the same weapon is still equipped.
            if equippedWeaponName ~= capturedWeapon then return end
            if tpIdleTrack then
                tpIdleTrack:Play()
            end
        end)
        tpReloadTrack:Play()
    end

    -- Connect Stopped BEFORE Play() so the callback is guaranteed to be registered
    -- even if the animation has Length == 0 at play time (e.g. asset not yet loaded,
    -- or invalid ID). If Play is called first and Stopped fires synchronously, the
    -- callback would never be registered and isReloading would stay true forever.
    -- AnimationTrack:Destroy() (called by StopWeaponAnimations / HolsterWeapon) severs
    -- this connection synchronously before it can fire on a stale weapon.
    weaponReloadTrack.Stopped:Connect(function()
        if equippedWeaponName ~= capturedWeapon or self.model == nil then return end
        isReloading = false
        -- Resume current locomotion state (or legacy run/idle on disabled path).
        if Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED :: boolean then
            local saved = vmLocomotionState
            vmLocomotionState = ""
            vmEnterRunPlaying = false
            self:SetLocomotionState(saved)
        else
            local resumeFade = Constants.VIEWMODEL_RELOAD_RESUME_FADE_TIME :: number
            if isRunning and weaponRunTrack ~= nil then
                self:PlayRunAnimation(resumeFade)
            else
                self:PlayIdleAnimation(resumeFade)
            end
        end
        Logger.debug("[ViewModelController] PlayReloadAnimation: reload complete, resumed "
            .. vmLocomotionState)
    end)
    weaponReloadTrack:Play()
    Logger.debug("[ViewModelController] PlayReloadAnimation: reload track started (FP + TP)")
end

-- Called by GunController each RenderStepped with the current sprint flag.
-- Manages the run ↔ idle base-layer transition.
-- Guards:
--   • no weapon equipped  → no-op (holstered)
--   • isSprinting unchanged → no-op (state unchanged)
--   • isReloading         → update flag only; reload Stopped callback will resume correctly
function ViewModelController:SetRunning(isSprinting: boolean)
    assert(typeof(isSprinting) == "boolean",
        "[ViewModelController] SetRunning: isSprinting must be a boolean")
    -- No-op while holstered — tracks are not loaded.
    if equippedWeaponName == nil then return end
    -- No-op when state has not changed.
    if isSprinting == isRunning then return end
    isRunning = isSprinting
    -- While reloading, update the flag but let the Stopped callback resume the correct track.
    if isReloading then return end
    local fadeT = Constants.VIEWMODEL_IDLE_RUN_FADE_TIME :: number
    if isSprinting then
        -- Stop idle and start run.
        if weaponIdleTrack and weaponIdleTrack.IsPlaying then
            weaponIdleTrack:Stop(fadeT)
        end
        self:PlayRunAnimation()
    else
        -- Stop run and return to idle.
        if weaponRunTrack and weaponRunTrack.IsPlaying then
            weaponRunTrack:Stop(fadeT)
        end
        self:PlayIdleAnimation()
    end
    Logger.debug("[ViewModelController] SetRunning: isRunning=" .. tostring(isRunning))
end

-- Called by GunController when the locomotion state changes.
-- state: "Idle" | "Walk" | "Run" | "Sprint"
-- Only transitions when state changes (no-op on repeated identical calls).
-- Priority rules:
--   1. Reload in progress → update state flag; let reload Stopped callback resume.
--   2. ADS active + Sprint → treat as Run (sprint anim suppressed during ADS).
--   3. Otherwise → start the correct locomotion track with crossfade.
-- EnterRun plays once on Walk/Idle → Run, then transitions to the run loop.
-- Falls back to legacy SetRunning(isSprinting) when VIEWMODEL_LOCOMOTION_ANIMS_ENABLED = false.
function ViewModelController:SetLocomotionState(state: string)
    assert(typeof(state) == "string",
        "[ViewModelController] SetLocomotionState: state must be a string")

    -- No-op while holstered.
    if equippedWeaponName == nil then return end

    -- Legacy fallback path.
    if not (Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED :: boolean) then
        self:SetRunning(state == "Sprint")
        return
    end

    -- No-op when state has not changed.
    if state == vmLocomotionState then return end

    local prevState = vmLocomotionState
    vmLocomotionState = state

    -- Update isRunning flag for the sway/inertia weight system (Sprint-only, not Run).
    isRunning = (state == "Sprint")

    -- Priority block: reload in progress.
    -- Update state flag so the reload Stopped callback resumes the correct track.
    if (Constants.VIEWMODEL_LOCOMOTION_RELOAD_PRIORITY_BLOCK :: boolean) and isReloading then
        if (Constants.VIEWMODEL_LOCOMOTION_DEBUG :: boolean) then
            Logger.debug("[ViewModelController] SetLocomotionState: blocked by reload ("
                .. prevState .. " → " .. state .. ")")
        end
        return
    end

    local ft   = Constants.VIEWMODEL_LOCOMOTION_FADE_TIME :: number
    local erft = Constants.VIEWMODEL_LOCOMOTION_ENTER_RUN_FADE_TIME :: number

    -- ADS blocks sprint anim: downgrade Sprint to Run visually so the sprint track
    -- does not fight the ADS pivot. vmLocomotionState remains "Sprint" so when ADS
    -- exits, the adsOut Stopped callback resumes sprint correctly.
    local effectiveState = state
    if state == "Sprint"
        and (Constants.VIEWMODEL_LOCOMOTION_ADS_BLOCKS_SPRINT_ANIM :: boolean)
        and adsState ~= "Hip"
    then
        effectiveState = "Run"
    end

    -- Stop all looped locomotion tracks.
    local function stopLoops(fade: number?)
        local f = fade or ft
        if weaponWalkTrack and weaponWalkTrack.IsPlaying then
            weaponWalkTrack:Stop(f)
        end
        if weaponRunTrack and weaponRunTrack.IsPlaying then
            weaponRunTrack:Stop(f)
        end
        if weaponSprintTrack and weaponSprintTrack.IsPlaying then
            weaponSprintTrack:Stop(f)
        end
    end

    -- Cancel any in-flight enterRun one-shot.
    local function cancelEnterRun()
        if weaponEnterRunTrack and weaponEnterRunTrack.IsPlaying then
            weaponEnterRunTrack:Stop(erft)
        end
        vmEnterRunPlaying = false
    end

    if effectiveState == "Idle" then
        cancelEnterRun()
        stopLoops()
        self:PlayIdleAnimation(ft)

    elseif effectiveState == "Walk" then
        cancelEnterRun()
        stopLoops()
        if weaponWalkTrack then
            weaponWalkTrack:Play(ft)
        else
            self:PlayIdleAnimation(ft)
        end

    elseif effectiveState == "Run" then
        -- Walk/Idle → Run: play enterRun once, then run loop.
        -- Sprint → Run, or no enterRun track: crossfade directly to run loop.
        local useEnterRun = (prevState == "Walk" or prevState == "Idle")
            and weaponEnterRunTrack ~= nil
            and not vmEnterRunPlaying

        if useEnterRun then
            stopLoops()
            cancelEnterRun()
            vmEnterRunPlaying = true
            local capturedWeapon = equippedWeaponName
            weaponEnterRunTrack:Play(erft)
            weaponEnterRunTrack.Stopped:Once(function()
                if equippedWeaponName ~= capturedWeapon then return end
                vmEnterRunPlaying = false
                -- Only start run loop if still in Run state (not transitioned away).
                if vmLocomotionState ~= "Run" then return end
                if weaponRunTrack then
                    weaponRunTrack:Play(erft)
                end
                if (Constants.VIEWMODEL_LOCOMOTION_DEBUG :: boolean) then
                    Logger.debug("[ViewModelController] enterRun complete → run loop started")
                end
            end)
        else
            cancelEnterRun()
            stopLoops()
            if weaponRunTrack then
                weaponRunTrack:Play(ft)
            else
                self:PlayIdleAnimation(ft)
            end
        end

    elseif effectiveState == "Sprint" then
        cancelEnterRun()
        stopLoops()
        if weaponSprintTrack then
            weaponSprintTrack:Play(ft)
        elseif weaponRunTrack then
            weaponRunTrack:Play(ft)
        else
            self:PlayIdleAnimation(ft)
        end
    end

    if (Constants.VIEWMODEL_LOCOMOTION_DEBUG :: boolean) then
        Logger.debug(string.format(
            "[ViewModelController] SetLocomotionState: %s → %s (effective: %s)",
            prevState, state, effectiveState))
    end
end

-- External setter for the isReloading flag.
-- PlayReloadAnimation() already sets and clears this flag via its Stopped callback, so
-- GunController typically does not need to call this.  Exposed as part of the public sway
-- API for completeness and future external callers.
function ViewModelController:SetReloading(reloading: boolean)
    assert(typeof(reloading) == "boolean",
        "[ViewModelController] SetReloading: reloading must be a boolean")
    isReloading = reloading
end

-- ============================================================
-- Public methods — ADS (aim down sights)
-- ============================================================

-- Called by GunController when ADS toggle (MB2) is pressed.
-- Manages ADS in → hold → ADS out animation sequence.
-- Guards:
--   • no weapon equipped  → clears isAiming and returns
--   • isAiming unchanged  → no-op (prevents restart spam)
--   • isReloading        → blocks ADS entry (reload takes priority)
function ViewModelController:SetAiming(entering: boolean)
    assert(typeof(entering) == "boolean",
        "[ViewModelController] SetAiming: entering must be a boolean")

    -- No weapon equipped: clear ADS state and return.
    if equippedWeaponName == nil then
        adsState = "Hip"
        adsIdleTime = 0
        return
    end

    -- No-op if already in target state.
    if entering and (adsState == "Entering" or adsState == "Aiming") then
        return
    end
    if not entering and adsState == "Hip" then
        return
    end

    -- Block ADS entry while reloading.
    if entering and isReloading then
        adsState = "Hip"
        return
    end

    if entering then
        -- ADS in: force first-person so the player cannot aim in third-person.
        if Constants.ADS_FORCE_FIRST_PERSON then
            preAdsFirstPerson = isFirstPerson
            setFirstPerson(true)
        end

        -- ADS in: stop idle/run, play adsIn, set state to Entering.
        -- RenderStepped will monitor TimePosition and freeze at final frame.

        -- Stop all locomotion tracks (ADS suppresses all movement animations).
        if Constants.VIEWMODEL_ADS_DISABLE_RUN_WHILE_AIMING then
            if weaponRunTrack and weaponRunTrack.IsPlaying then
                weaponRunTrack:Stop()
            end
            if weaponWalkTrack and weaponWalkTrack.IsPlaying then
                weaponWalkTrack:Stop()
            end
            if weaponSprintTrack and weaponSprintTrack.IsPlaying then
                weaponSprintTrack:Stop()
            end
            if weaponEnterRunTrack and weaponEnterRunTrack.IsPlaying then
                weaponEnterRunTrack:Stop(Constants.VIEWMODEL_LOCOMOTION_ENTER_RUN_FADE_TIME :: number)
            end
            vmEnterRunPlaying = false
        end

        -- Stop idle (ADS suppresses idle visually).
        if Constants.VIEWMODEL_ADS_DISABLE_NORMAL_IDLE_WHILE_AIMING then
            if weaponIdleTrack and weaponIdleTrack.IsPlaying then
                weaponIdleTrack:Stop()
            end
        end

        -- Stop any active adsOut (cancel exit if re-entering).
        -- Fade so the rig doesn't snap to rest-pose for one frame mid-transition.
        if weaponAdsOutTrack and weaponAdsOutTrack.IsPlaying then
            weaponAdsOutTrack:Stop(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
        end

        -- Stop any active adsIdle (in case re-entering from Aiming).
        if weaponAdsIdleTrack and weaponAdsIdleTrack.IsPlaying then
            weaponAdsIdleTrack:Stop(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
        end

        if weaponAdsInTrack then
            -- Play adsIn from the start with fade.
            weaponAdsInTrack.TimePosition = 0
            weaponAdsInTrack:AdjustSpeed(1)
            weaponAdsInTrack:Play(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
            adsState = "Entering"
            adsIdleTime = 0
            Logger.debug("[ViewModelController] SetAiming: adsIn started (state = Entering)")

            -- When adsIn finishes, start looping adsIdle.
            local capturedWeapon = equippedWeaponName
            weaponAdsInTrack.Stopped:Once(function()
                -- Only transition if same weapon, still entering, and model exists.
                if equippedWeaponName ~= capturedWeapon or self.model == nil then
                    return
                end
                if adsState ~= "Entering" then
                    return
                end

                -- Transition to Aiming state and start adsIdle loop.
                adsState = "Aiming"
                adsIdleTime = 0
                Logger.debug("[ViewModelController] adsIn Stopped: transitioned to Aiming")

                -- Start adsIdle loop if available.
                if weaponAdsIdleTrack then
                    weaponAdsIdleTrack:Play(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
                    Logger.debug("[ViewModelController] adsIn Stopped: adsIdle started")
                else
                    Logger.warn("[ViewModelController] adsIn Stopped: no adsIdle track loaded - ADS pose may not hold")
                end
            end)
        else
            Logger.warn("[ViewModelController] SetAiming: no adsIn track loaded")
            adsState = "Hip"
        end
    else
        -- ADS out: restore the perspective mode that was active before ADS entered.
        if Constants.ADS_FORCE_FIRST_PERSON then
            setFirstPerson(preAdsFirstPerson)
        end

        -- ADS out: stop adsIn/adsIdle, play adsOut, set state to Exiting.
        adsIdleTime = 0

        -- Stop adsIn if still entering.
        -- Fade so the rig doesn't snap to rest-pose for one frame before adsOut fades in.
        if weaponAdsInTrack and weaponAdsInTrack.IsPlaying then
            weaponAdsInTrack:Stop(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
        end

        -- Stop adsIdle if currently aiming.
        if weaponAdsIdleTrack and weaponAdsIdleTrack.IsPlaying then
            weaponAdsIdleTrack:Stop(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
        end

        if weaponAdsOutTrack then
            weaponAdsOutTrack.TimePosition = 0
            weaponAdsOutTrack:Play(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
            adsState = "Exiting"

            -- When adsOut finishes, return to Hip and resume idle/run.
            local capturedWeapon = equippedWeaponName
            weaponAdsOutTrack.Stopped:Once(function()
                -- Only resume if same weapon and still exiting.
                if equippedWeaponName ~= capturedWeapon or self.model == nil then
                    return
                end
                if adsState == "Exiting" then
                    adsState = "Hip"
                    -- Resume base-layer hip animation.
                    -- The VIEWMODEL_ADS_DISABLE_* constants suppress idle/run DURING ADS;
                    -- they must not prevent the hip animation from resuming once ADS ends.
                    -- Without unconditional resumption here, the weapon freezes on the final
                    -- adsOut frame with no looping animation (idle-after-ADS bug — DEBT-040).
                    if not isReloading then
                        if Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED :: boolean then
                            local saved = vmLocomotionState
                            vmLocomotionState = ""
                            vmEnterRunPlaying = false
                            self:SetLocomotionState(saved)
                        else
                            if isRunning and weaponRunTrack ~= nil then
                                self:PlayRunAnimation()
                            else
                                self:PlayIdleAnimation()
                            end
                        end
                    end
                    Logger.debug("[ViewModelController] adsOut complete: hip animation resumed")
                end
            end)
            Logger.debug("[ViewModelController] SetAiming: adsOut started (state = Exiting)")
        else
            -- No adsOut track: immediately return to Hip and resume locomotion.
            adsState = "Hip"
            if not isReloading then
                if Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED :: boolean then
                    local saved = vmLocomotionState
                    vmLocomotionState = ""
                    vmEnterRunPlaying = false
                    self:SetLocomotionState(saved)
                else
                    if isRunning and weaponRunTrack ~= nil then
                        self:PlayRunAnimation()
                    else
                        self:PlayIdleAnimation()
                    end
                end
            end
        end
    end
end

-- Returns true while the player is aiming (ADS entering, holding, or exiting).
-- Returns false only when adsState == "Hip".
function ViewModelController:IsAiming(): boolean
    return adsState ~= "Hip"
end

-- Plays the ADS in animation (enter ADS).
-- Called by SetAiming(true) internally; exposed for external choreography if needed.
function ViewModelController:PlayADSInAnimation()
    if weaponAdsInTrack then
        weaponAdsInTrack:Play()
    end
end

-- Plays the ADS out animation (exit ADS).
-- Called by SetAiming(false) internally; exposed for external choreography if needed.
function ViewModelController:PlayADSOutAnimation()
    if weaponAdsOutTrack then
        weaponAdsOutTrack:Play()
    end
end

-- Plays the ADS fire animation (firing while ADS).
-- Called by GunController when firing while IsAiming() is true.
-- Only plays if adsState == "Aiming" (held ADS pose).
-- Restartable: each shot re-plays from the start.
function ViewModelController:PlayADSFireAnimation()
    -- Only fire while in the held ADS pose.
    if adsState ~= "Aiming" then
        Logger.debug("[ViewModelController] PlayADSFireAnimation: not in Aiming state, skipped")
        return
    end
    if not weaponAdsFireTrack then return end
    if weaponAdsFireTrack.IsPlaying then
        weaponAdsFireTrack:Stop(0)
    end
    weaponAdsFireTrack:Play()
    Logger.debug("[ViewModelController] PlayADSFireAnimation: adsFire track started")
end

-- Stops all ADS animations and clears ADS state.
-- Called internally when holstering, reloading, or resetting.
function ViewModelController:StopADSAnimations()
    -- adsIn and adsIdle hold the weapon in the ADS pose while active.
    -- Stopping them without a fade snaps the rig to its rest T-pose for one frame,
    -- causing the gun-into-camera glitch when reload or holster interrupts ADS.
    if weaponAdsInTrack and weaponAdsInTrack.IsPlaying then
        weaponAdsInTrack:Stop(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
    end
    if weaponAdsIdleTrack and weaponAdsIdleTrack.IsPlaying then
        weaponAdsIdleTrack:Stop(Constants.VIEWMODEL_ADS_TRACK_FADE_TIME)
    end
    if weaponAdsOutTrack and weaponAdsOutTrack.IsPlaying then
        weaponAdsOutTrack:Stop()
    end
    if weaponAdsFireTrack and weaponAdsFireTrack.IsPlaying then
        weaponAdsFireTrack:Stop()
    end
    adsState               = "Hip"
    adsIdleTime            = 0
    -- Hold adsAimAlpha at 1 for FADE_TIME after interruption so the adsIdle/adsIn
    -- fade completes before the pivot starts shifting toward basePivot.
    -- Without this, the pivot decays during the fade window, and the mid-fade rig
    -- pose (between ADS and rest) combined with partial pivot shift places the gun
    -- inside the camera.
    adsAimHoldTimer        = Constants.VIEWMODEL_ADS_TRACK_FADE_TIME :: number
    -- Do NOT hard-reset adsAimAlpha: the RenderStepped lerp decays it to 0
    -- smoothly once adsAimHoldTimer expires. Resetting it here causes an instant
    -- pivot snap (CAMERA_EXTRA_OFFSET jump) visible as a one-frame position pop.
end

-- ============================================================
-- Public methods — recoil, muzzle
-- ============================================================

-- Receives the rotational recoil CFrame from GunController each RenderStepped.
-- Push pattern keeps the dependency one-directional: GunController → ViewModelController.
function ViewModelController:SetRecoilOffset(cf: CFrame)
    viewRecoilCFrame = cf
end

-- Receives the normalized free-aim offset from GunController each RenderStepped.
-- normalizedOffset is in [-1, 1] range per axis (FreeAimController:GetNormalizedAimOffset()).
-- Stored as vmFreeAimNormalized; RenderStepped lerps vmFreeAimBlended toward it each frame,
-- converting it to a subtle weapon yaw/pitch via FREE_AIM_VIEWMODEL_YAW/PITCH_DEGREES.
-- Stage 1 only — does not affect camera.CFrame, bullet direction, or server state.
function ViewModelController:SetFreeAimOffset(normalizedOffset: Vector2): ()
    assert(typeof(normalizedOffset) == "Vector2",
        "[ViewModelController] SetFreeAimOffset: normalizedOffset must be a Vector2")
    vmFreeAimNormalized = normalizedOffset
end

-- Receives the latest raw mouse delta from GunController each RenderStepped.
-- Stored as vmMouseInertiaDelta; RenderStepped integrates it into vmMouseInertia (a damped
-- velocity), which adds roll and translation to the viewmodel in proportion to how fast
-- the mouse is moving.  Zeroed on holster/reset via StopWeaponAnimations().
-- Stage 1 only — does not affect camera.CFrame, bullet direction, or server state.
function ViewModelController:SetMouseInertia(mouseDelta: Vector2): ()
    assert(typeof(mouseDelta) == "Vector2",
        "[ViewModelController] SetMouseInertia: mouseDelta must be a Vector2")
    vmMouseInertiaDelta = mouseDelta
end

-- Applies a data-driven viewmodel recoil impulse when a shot is fired.
-- recoilProfile = WeaponData["<name>"].recoil; nil falls back to DEFAULT_VIEWMODEL_RECOIL_*
-- constants. Stage 1 — viewmodel only; no camera.CFrame change.
-- No-op when Constants.VIEWMODEL_RECOIL_ENABLED is false.
function ViewModelController:ApplyRecoil(isAiming: boolean, recoilProfile: any?): ()
    assert(typeof(isAiming) == "boolean",
        "[ViewModelController] ApplyRecoil: isAiming must be a boolean")
    if recoilProfile ~= nil then
        assert(typeof(recoilProfile) == "table",
            "[ViewModelController] ApplyRecoil: recoilProfile must be a table or nil")
    end
    if not Constants.VIEWMODEL_RECOIL_ENABLED then return end

    -- Update active kick/recovery speeds from the profile (persist for this recovery arc).
    if recoilProfile ~= nil then
        local ksp = (recoilProfile :: any).kickSpeed
        local rsp = (recoilProfile :: any).recoverySpeed
        if typeof(ksp) == "number" then vmActiveKickSpeed     = ksp :: number end
        if typeof(rsp) == "number" then vmActiveRecoverySpeed = rsp :: number end
    end

    -- Resolve hip or ads sub-table.
    local sub: any = nil
    if recoilProfile ~= nil then
        sub = isAiming and (recoilProfile :: any).ads or (recoilProfile :: any).hip
        if sub == nil then
            Logger.warn("[ViewModelController] ApplyRecoil: recoilProfile missing sub-table for isAiming=" .. tostring(isAiming))
        end
    end

    -- Read per-shot values with fallback to Constants defaults.
    -- positionBack > 0 = weapon moves toward camera (+Z camera-local = backward kick).
    -- positionUp   > 0 = weapon lifts upward (+Y camera-local).
    -- pitchDegrees > 0 = muzzle rises; pending Studio verification (WeaponFeel gate applied).
    local pz: number
    local py: number
    local pitch: number
    local yaw: number
    local roll: number
    if sub ~= nil then
        pz    = if typeof((sub :: any).positionBack) == "number" then (sub :: any).positionBack :: number else Constants.DEFAULT_VIEWMODEL_RECOIL_POSITION_BACK
        py    = if typeof((sub :: any).positionUp)   == "number" then (sub :: any).positionUp   :: number else Constants.DEFAULT_VIEWMODEL_RECOIL_POSITION_UP
        pitch = if typeof((sub :: any).pitchDegrees) == "number" then (sub :: any).pitchDegrees :: number else Constants.DEFAULT_VIEWMODEL_RECOIL_PITCH_DEGREES
        yaw   = if typeof((sub :: any).yawDegrees)   == "number" then (sub :: any).yawDegrees   :: number else Constants.DEFAULT_VIEWMODEL_RECOIL_YAW_DEGREES
        roll  = if typeof((sub :: any).rollDegrees)  == "number" then (sub :: any).rollDegrees  :: number else Constants.DEFAULT_VIEWMODEL_RECOIL_ROLL_DEGREES
    else
        pz    = Constants.DEFAULT_VIEWMODEL_RECOIL_POSITION_BACK
        py    = Constants.DEFAULT_VIEWMODEL_RECOIL_POSITION_UP
        pitch = Constants.DEFAULT_VIEWMODEL_RECOIL_PITCH_DEGREES
        yaw   = Constants.DEFAULT_VIEWMODEL_RECOIL_YAW_DEGREES
        roll  = Constants.DEFAULT_VIEWMODEL_RECOIL_ROLL_DEGREES
    end

    local randomYawScale  = if recoilProfile ~= nil and typeof((recoilProfile :: any).randomYawScale)  == "number" then (recoilProfile :: any).randomYawScale  :: number else 1.0
    local randomRollScale = if recoilProfile ~= nil and typeof((recoilProfile :: any).randomRollScale) == "number" then (recoilProfile :: any).randomRollScale :: number else 1.0
    local maxBuildup      = if recoilProfile ~= nil and typeof((recoilProfile :: any).maxBuildup)      == "number" then (recoilProfile :: any).maxBuildup      :: number else Constants.DEFAULT_VIEWMODEL_RECOIL_MAX_BUILDUP
    local buildupPerShot  = if recoilProfile ~= nil and typeof((recoilProfile :: any).buildupPerShot)  == "number" then (recoilProfile :: any).buildupPerShot  :: number else 0.10
    local alternatingYaw  = recoilProfile ~= nil and (recoilProfile :: any).alternatingYaw == true

    -- Scale pitch by buildup; position magnitude is constant per shot.
    local buildupMult = 1 + vmRecoilBuildup
    vmRecoilBuildup = math.min(vmRecoilBuildup + buildupPerShot, maxBuildup)

    -- Yaw: alternating direction each shot when alternatingYaw=true; random otherwise.
    local finalYaw: number
    if alternatingYaw then
        finalYaw = yaw * vmRecoilYawDir * (1 + (math.random() - 0.5) * randomYawScale * 0.5)
        vmRecoilYawDir = -vmRecoilYawDir
    else
        finalYaw = yaw * (1 + (math.random() - 0.5) * 2 * randomYawScale)
    end
    local finalRoll = roll * (1 + (math.random() - 0.5) * 2 * randomRollScale)

    local kick = CFrame.new(0, py, pz)
        * CFrame.Angles(math.rad(pitch * buildupMult), math.rad(finalYaw), math.rad(finalRoll))

    vmRecoilTarget = vmRecoilTarget * kick
    Logger.debug("[ViewModelController] ApplyRecoil: isAiming=" .. tostring(isAiming) .. " buildup=" .. string.format("%.2f", vmRecoilBuildup))
end

-- Returns true while a reload animation is playing.
-- Read by GunController each RenderStepped to push isReloading state to FreeAimController.
-- Exposed here so GunController can query it without storing a duplicate flag.
function ViewModelController:GetIsReloading(): boolean
    return isReloading
end

-- Returns a CFrame at the barrel muzzle tip for muzzle-flash placement.
-- Reads WorldPosition from MuzzleAttachment if present; falls back to a point in front of
-- the camera with a warning.
function ViewModelController:GetBarrelTipCFrame(): CFrame
    local model = self.model
    if model then
        local attachment = model:FindFirstChild("MuzzleAttachment", true)
        if attachment and attachment:IsA("Attachment") then
            return CFrame.new((attachment :: Attachment).WorldPosition)
        end
    end
    Logger.warn("[ViewModelController] GetBarrelTipCFrame: MuzzleAttachment not found — using camera fallback")
    local cam = workspace.CurrentCamera
    return CFrame.new(cam.CFrame.Position + cam.CFrame.LookVector * MUZZLE_FALLBACK_DIST)
end

return ViewModelController
