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
--   If the equip track has zero length or is absent, PlayIdleAnimation() starts immediately.
--   StopWeaponAnimations() stops and destroys all loaded weapon AnimationTracks.
--   HolsterWeapon() stops animations, destroys the model clone, and clears all equip state.
--
-- PivotTo camera follow (every RenderStepped, only when self.model is non-nil):
--   m:PivotTo(cam.CFrame * viewRecoilCFrame * moveCF * BASE_OFFSET * CFrame.new(0,0,recoilOffset))
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
-- isReloading: true while reload one-shot is playing; blocks fire and run.
-- isRunning:   true while GunController reports sprint state and a weapon is equipped.
local isReloading: boolean = false
local isRunning:   boolean = false

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
    isReloading = false
    isRunning   = false
    adsState    = "Hip"
    adsIdleTime = 0
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
    isReloading = false
    isRunning   = false
    adsState    = "Hip"
    adsIdleTime = 0
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
-- No-op when no idle track is loaded.
function ViewModelController:PlayIdleAnimation()
    if weaponIdleTrack then
        weaponIdleTrack:Play()
        Logger.debug("[ViewModelController] PlayIdleAnimation: idle track started")
    else
        Logger.debug("[ViewModelController] PlayIdleAnimation: no idle track loaded — skipped")
    end
end

-- Plays the equip AnimationTrack once, then chains to PlayIdleAnimation() via the
-- Stopped signal.  If the equip track has zero length or is absent, PlayIdleAnimation()
-- starts immediately without blocking.
function ViewModelController:PlayEquipAnimation()
    -- Capture weapon identity so the Stopped callback can guard against stale calls.
    local capturedWeapon = equippedWeaponName

    if weaponEquipTrack and weaponEquipTrack.Length > 0 then
        weaponEquipTrack:Play()
        -- Chain to run or idle when the equip one-shot ends.
        -- AnimationTrack:Destroy() disconnects all signals synchronously, so the
        -- Stopped callback will not fire after StopWeaponAnimations() has run.
        weaponEquipTrack.Stopped:Connect(function()
            -- Guard: only proceed if same weapon is still equipped.
            if equippedWeaponName ~= capturedWeapon or self.model == nil then return end
            -- Resume run if GunController already flagged sprint, else start idle.
            if isRunning and weaponRunTrack ~= nil then
                self:PlayRunAnimation()
            elseif weaponIdleTrack ~= nil then
                self:PlayIdleAnimation()
            end
        end)
        Logger.debug("[ViewModelController] PlayEquipAnimation: equip track started")
    else
        -- No equip track or zero-length clip — start run or idle directly.
        Logger.debug("[ViewModelController] PlayEquipAnimation: no equip track — starting base directly")
        if isRunning and weaponRunTrack ~= nil then
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

    -- Apply current phase-based visibility.
    local show = shouldShowViewModel()
    visible    = show
    setVisibility(show)

    -- Begin first-person equip → idle animation sequence.
    self:PlayEquipAnimation()

    -- Begin third-person equip → idle sequence on the character body.
    startThirdPersonEquipSequence()
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

    -- Load run track (looped, Movement priority — replaces idle while sprinting).
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
                setFirstPerson(false)
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
        -- When ADS is active (Entering or Aiming), disable procedural movement to keep pose stable.
        local finalMoveCF = moveCF
        if Constants.VIEWMODEL_ADS_DISABLE_PROCEDURAL_MOVEMENT then
            if adsState == "Entering" or adsState == "Aiming" then
                finalMoveCF = CFrame.new()  -- zero out procedural movement
            end
        end

        -- Free-aim viewmodel lean: blend the normalized aim offset toward the weapon's
        -- visible rotation.  Suppressed during ADS (Entering / Aiming) so the lean does not
        -- push the iron sights off-center.  During Hip and Exiting the lean resumes from
        -- wherever vmFreeAimBlended left off (near zero after being drained), so there is
        -- no pop on ADS exit.
        local freeAimCF: CFrame
        if adsState == "Entering" or adsState == "Aiming" then
            -- Drain blended value toward zero so the lean doesn't snap when exiting ADS.
            -- freeAimCF is identity — the ADS animation alone positions the iron sights.
            vmFreeAimBlended = vmFreeAimBlended:Lerp(
                Vector2.zero,
                math.min(1, dt * Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED)
            )
            freeAimCF = CFrame.new()
        else
            -- Hip / Exiting: apply lean normally.
            vmFreeAimBlended = vmFreeAimBlended:Lerp(
                vmFreeAimNormalized,
                math.min(1, dt * Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED)
            )
            local freeAimYaw   = vmFreeAimBlended.X * math.rad(Constants.FREE_AIM_VIEWMODEL_YAW_DEGREES)
            local freeAimPitch = -vmFreeAimBlended.Y * math.rad(Constants.FREE_AIM_VIEWMODEL_PITCH_DEGREES)
            freeAimCF = CFrame.Angles(freeAimPitch, freeAimYaw, 0)
        end

        -- Final viewmodel CFrame.
        -- Order: CAMERA_EXTRA_OFFSET (base hipfire positioning) → viewRecoilCFrame (rotational recoil)
        --        → freeAimCF (weapon lean toward aim point, Stage 1; identity during Entering/Aiming)
        --        → finalMoveCF (movement sway/bob, zeroed during ADS)
        --        → BASE_OFFSET (model-specific pivot alignment) → recoilOffset (positional recoil)
        -- CAMERA_EXTRA_OFFSET is always applied and was present when ADS was authored — the ADS animation
        -- itself positions the iron sights at screen center without any additional model-level offset.
        m:PivotTo(
            cam.CFrame
            * CAMERA_EXTRA_OFFSET
            * viewRecoilCFrame
            * freeAimCF
            * finalMoveCF
            * BASE_OFFSET
            * CFrame.new(0, 0, recoilOffset)
        )
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
-- No-op when no run track is loaded.
function ViewModelController:PlayRunAnimation()
    if weaponRunTrack then
        weaponRunTrack:Play()
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
    -- Stop fire and run so reload plays unobstructed.
    if weaponFireTrack and weaponFireTrack.IsPlaying then
        weaponFireTrack:Stop(0)
    end
    if weaponRunTrack and weaponRunTrack.IsPlaying then
        weaponRunTrack:Stop()
    end
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
        tpReloadTrack:Play()
        tpReloadTrack.Stopped:Connect(function()
            -- Guard: resume TP idle only if the same weapon is still equipped.
            if equippedWeaponName ~= capturedWeapon then return end
            if tpIdleTrack then
                tpIdleTrack:Play()
            end
        end)
    end

    weaponReloadTrack:Play()
    -- Resume the correct FP base animation when reload finishes.
    -- AnimationTrack:Destroy() (called by StopWeaponAnimations / HolsterWeapon) severs this
    -- connection synchronously before it can fire on a stale weapon.
    weaponReloadTrack.Stopped:Connect(function()
        if equippedWeaponName ~= capturedWeapon or self.model == nil then return end
        isReloading = false
        -- If the player is still sprinting, resume FP run; otherwise return to FP idle.
        if isRunning and weaponRunTrack ~= nil then
            self:PlayRunAnimation()
        else
            self:PlayIdleAnimation()
        end
        Logger.debug("[ViewModelController] PlayReloadAnimation: reload complete, resumed "
            .. (isRunning and "run" or "idle"))
    end)
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
    if isSprinting then
        -- Stop idle and start run.
        if weaponIdleTrack and weaponIdleTrack.IsPlaying then
            weaponIdleTrack:Stop()
        end
        self:PlayRunAnimation()
    else
        -- Stop run and return to idle.
        if weaponRunTrack and weaponRunTrack.IsPlaying then
            weaponRunTrack:Stop()
        end
        self:PlayIdleAnimation()
    end
    Logger.debug("[ViewModelController] SetRunning: isRunning=" .. tostring(isRunning))
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
        -- ADS in: stop idle/run, play adsIn, set state to Entering.
        -- RenderStepped will monitor TimePosition and freeze at final frame.

        -- Stop run (ADS suppresses run visually).
        if Constants.VIEWMODEL_ADS_DISABLE_RUN_WHILE_AIMING then
            if weaponRunTrack and weaponRunTrack.IsPlaying then
                weaponRunTrack:Stop()
            end
        end

        -- Stop idle (ADS suppresses idle visually).
        if Constants.VIEWMODEL_ADS_DISABLE_NORMAL_IDLE_WHILE_AIMING then
            if weaponIdleTrack and weaponIdleTrack.IsPlaying then
                weaponIdleTrack:Stop()
            end
        end

        -- Stop any active adsOut (cancel exit if re-entering).
        if weaponAdsOutTrack and weaponAdsOutTrack.IsPlaying then
            weaponAdsOutTrack:Stop()
        end

        -- Stop any active adsIdle (in case re-entering from Aiming).
        if weaponAdsIdleTrack and weaponAdsIdleTrack.IsPlaying then
            weaponAdsIdleTrack:Stop()
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
        -- ADS out: stop adsIn/adsIdle, play adsOut, set state to Exiting.
        adsIdleTime = 0

        -- Stop adsIn if still entering.
        if weaponAdsInTrack and weaponAdsInTrack.IsPlaying then
            weaponAdsInTrack:Stop()
        end

        -- Stop adsIdle if currently aiming.
        if weaponAdsIdleTrack and weaponAdsIdleTrack.IsPlaying then
            weaponAdsIdleTrack:Stop()
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
                    -- Resume idle/run if not reloading.
                    if not isReloading then
                        if isRunning and weaponRunTrack ~= nil and not Constants.VIEWMODEL_ADS_DISABLE_RUN_WHILE_AIMING then
                            self:PlayRunAnimation()
                        elseif not Constants.VIEWMODEL_ADS_DISABLE_NORMAL_IDLE_WHILE_AIMING then
                            self:PlayIdleAnimation()
                        end
                    end
                end
            end)
            Logger.debug("[ViewModelController] SetAiming: adsOut started (state = Exiting)")
        else
            -- No adsOut track: immediately return to Hip and resume idle/run.
            adsState = "Hip"
            if not isReloading then
                if isRunning and weaponRunTrack ~= nil and not Constants.VIEWMODEL_ADS_DISABLE_RUN_WHILE_AIMING then
                    self:PlayRunAnimation()
                elseif not Constants.VIEWMODEL_ADS_DISABLE_NORMAL_IDLE_WHILE_AIMING then
                    self:PlayIdleAnimation()
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
    if weaponAdsInTrack and weaponAdsInTrack.IsPlaying then
        weaponAdsInTrack:Stop()
    end
    if weaponAdsIdleTrack and weaponAdsIdleTrack.IsPlaying then
        weaponAdsIdleTrack:Stop()
    end
    if weaponAdsOutTrack and weaponAdsOutTrack.IsPlaying then
        weaponAdsOutTrack:Stop()
    end
    if weaponAdsFireTrack and weaponAdsFireTrack.IsPlaying then
        weaponAdsFireTrack:Stop()
    end
    adsState = "Hip"
    adsIdleTime = 0
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
    vmFreeAimNormalized = normalizedOffset
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
