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

-- Name of the currently equipped weapon, or nil when holstered.
local equippedWeaponName: string? = nil

-- First-person animation tracks for the equipped weapon.
-- equip and idle are the base-layer tracks (loaded and cleared by _setupWeaponAnimations).
-- fire, reload, and run are the action/movement overlay tracks (same lifetime).
local weaponEquipTrack:  AnimationTrack? = nil
local weaponIdleTrack:   AnimationTrack? = nil
local weaponFireTrack:   AnimationTrack? = nil
local weaponReloadTrack: AnimationTrack? = nil
local weaponRunTrack:    AnimationTrack? = nil

-- Animation state flags.
-- isReloading: true while reload one-shot is playing; blocks fire and run.
-- isRunning:   true while GunController reports sprint state and a weapon is equipped.
local isReloading: boolean = false
local isRunning:   boolean = false

-- Third-person character weapon AnimationTracks.
-- Loaded on the local player's Humanoid.Animator when a weapon is equipped.
-- Priority: equip/idle = Action (overlays movement), fire/reload = Action2 (overlays idle).
-- Cleared (nil, no Stop) in init() because CharacterAdded may fire after the old Animator
-- is already destroyed.  Stopped and Destroyed in StopWeaponAnimations() during normal play.
local tpEquipTrack:  AnimationTrack? = nil
local tpIdleTrack:   AnimationTrack? = nil
local tpFireTrack:   AnimationTrack? = nil
local tpReloadTrack: AnimationTrack? = nil
-- ADS tracks: adsIn/adsOut at Action2 (overlay idle), adsFire at Action3 (overlay ADS hold).
local tpAdsInTrack:  AnimationTrack? = nil
local tpAdsOutTrack: AnimationTrack? = nil
local tpAdsFireTrack: AnimationTrack? = nil
-- True while the ADS-in animation is playing or frozen at its last frame.
-- Cleared when adsOut completes, or when StopWeaponAnimations / PlayReloadAnimation runs.
local isTPADS: boolean = false

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
    isReloading = false
    isRunning   = false
    -- Third-person character tracks: nil references only — do NOT call Stop/Destroy.
    -- init() is called from CharacterAdded where the old Humanoid.Animator may already be
    -- destroyed, making track method calls unsafe.  Same pattern as MovementController's
    -- loadMovementAnimations() respawn cleanup (table.clear without Stop).
    tpEquipTrack   = nil
    tpIdleTrack    = nil
    tpFireTrack    = nil
    tpReloadTrack  = nil
    tpAdsInTrack   = nil
    tpAdsOutTrack  = nil
    tpAdsFireTrack = nil
    isTPADS        = false
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
    isReloading = false
    isRunning   = false
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
    if tpAdsInTrack then
        tpAdsInTrack:AdjustSpeed(1)  -- unfreeze before stopping
        tpAdsInTrack:Stop()
        tpAdsInTrack:Destroy()
        tpAdsInTrack = nil
    end
    if tpAdsOutTrack then
        tpAdsOutTrack:Stop()
        tpAdsOutTrack:Destroy()
        tpAdsOutTrack = nil
    end
    if tpAdsFireTrack then
        tpAdsFireTrack:Stop()
        tpAdsFireTrack:Destroy()
        tpAdsFireTrack = nil
    end
    isTPADS = false
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
    -- ADS: adsIn/adsOut overlay idle (Action2); adsFire overrides the frozen ADS pose (Action3).
    tpAdsInTrack   = loadTp(tp.adsIn   or "", false, Enum.AnimationPriority.Action2)
    tpAdsOutTrack  = loadTp(tp.adsOut  or "", false, Enum.AnimationPriority.Action2)
    tpAdsFireTrack = loadTp(tp.adsFire or "", false, Enum.AnimationPriority.Action3)

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

    -- RenderStepped: reposition viewmodel every frame when a weapon is equipped.
    -- Returns immediately when self.model is nil (holstered), preventing any gravity drop.
    -- Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
    RunService.RenderStepped:Connect(function(dt: number)
        local m = self.model
        if not m then return end

        -- Decay positional recoil back to zero.
        if recoilOffset > 0 then
            recoilOffset = math.max(0, recoilOffset - dt * RECOIL_RATE)
        end

        local cam    = workspace.CurrentCamera
        local moveCF = MovementController:GetViewmodelAddCFrame()
        m:PivotTo(
            cam.CFrame
            * CAMERA_EXTRA_OFFSET   -- shifts entire model in camera space (tune via Constants)
            * viewRecoilCFrame
            * moveCF
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
    -- First-person: stop immediately and restart for per-shot restartability.
    if weaponFireTrack then
        if weaponFireTrack.IsPlaying then
            weaponFireTrack:Stop(0)
        end
        weaponFireTrack:Play()
        Logger.debug("[ViewModelController] PlayFireAnimation: FP fire track started")
    end
    -- Third-person: pick adsFire (Action3) when ADS, or regular fire (Action2) otherwise.
    -- Same pattern — restart per shot so rapid fire always plays from frame 0.
    local fireTrackToUse = (isTPADS and tpAdsFireTrack) or tpFireTrack
    if fireTrackToUse then
        if fireTrackToUse.IsPlaying then
            fireTrackToUse:Stop(0)
        end
        fireTrackToUse:Play()
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
    -- Reload clears ADS state — can't reload while aiming.
    if isTPADS then
        isTPADS = false
        if tpAdsInTrack and tpAdsInTrack.IsPlaying then
            tpAdsInTrack:AdjustSpeed(1)
            tpAdsInTrack:Stop()
        end
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

-- Called by GunController when MouseButton2 is pressed (entering=true) or released (false).
-- Manages the third-person ADS animation sequence:
--   entering=true:  stop TP idle → play adsIn one-shot → freeze at last frame while held.
--   entering=false: unfreeze adsIn → play adsOut one-shot → resume TP idle on completion.
-- Guards: holstered, already in target state, or reloading in progress → no-op.
function ViewModelController:SetTPADS(entering: boolean)
    assert(typeof(entering) == "boolean",
        "[ViewModelController] SetTPADS: entering must be a boolean")
    if equippedWeaponName == nil then return end
    if entering == isTPADS then return end
    if entering and isReloading then return end  -- reload takes priority; block ADS entry

    local capturedWeapon = equippedWeaponName

    if entering then
        isTPADS = true
        -- Stop base layer so adsIn is unobstructed.
        if tpIdleTrack and tpIdleTrack.IsPlaying then
            tpIdleTrack:Stop()
        end
        if tpAdsInTrack then
            tpAdsInTrack:Play()
            -- When adsIn one-shot ends, freeze it at the last frame so the ADS pose holds.
            -- AnimationTrack:Destroy() (in StopWeaponAnimations) severs this connection
            -- synchronously, so it cannot fire after holster.
            tpAdsInTrack.Stopped:Connect(function()
                if equippedWeaponName ~= capturedWeapon or not isTPADS then return end
                if tpAdsInTrack and tpAdsInTrack.Length > 0 then
                    tpAdsInTrack:Play(0)
                    tpAdsInTrack:AdjustSpeed(0)
                    tpAdsInTrack.TimePosition = tpAdsInTrack.Length - 0.001
                end
            end)
            Logger.debug("[ViewModelController] SetTPADS: adsIn started")
        end
    else
        isTPADS = false
        -- Unfreeze adsIn (restore speed before stopping so the fade works correctly).
        if tpAdsInTrack and tpAdsInTrack.IsPlaying then
            tpAdsInTrack:AdjustSpeed(1)
            tpAdsInTrack:Stop()
        end
        -- Play adsOut then resume idle.
        if tpAdsOutTrack then
            tpAdsOutTrack:Play()
            tpAdsOutTrack.Stopped:Connect(function()
                if equippedWeaponName ~= capturedWeapon or isTPADS then return end
                if not isReloading then
                    if isRunning and weaponRunTrack ~= nil then
                        -- Resume run if player is still sprinting.
                        if tpIdleTrack and tpIdleTrack.IsPlaying then tpIdleTrack:Stop() end
                    else
                        if tpIdleTrack then tpIdleTrack:Play() end
                    end
                end
            end)
            Logger.debug("[ViewModelController] SetTPADS: adsOut started")
        else
            if not isReloading and tpIdleTrack then
                tpIdleTrack:Play()
            end
        end
    end
end

-- Receives the rotational recoil CFrame from GunController each RenderStepped.
-- Push pattern keeps the dependency one-directional: GunController → ViewModelController.
function ViewModelController:SetRecoilOffset(cf: CFrame)
    viewRecoilCFrame = cf
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
