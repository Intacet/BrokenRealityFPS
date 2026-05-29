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
-- Camera mode:
--   applyCameraMode() sets CameraMode based on Constants.FORCE_FIRST_PERSON.
--   Called in Start() and after every CharacterAdded respawn.
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

-- ============================================================
-- State
-- ============================================================

-- Visibility flag and current phase, tracked for the shouldShowViewModel() gate.
local visible:      boolean = false
local currentPhase: string  = Constants.Phase.LOBBY

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

-- Sets the local player's CameraMode based on Constants.FORCE_FIRST_PERSON.
-- Called in Start() and after every CharacterAdded.
local function applyCameraMode()
    local localPlayer = Players.LocalPlayer
    if Constants.FORCE_FIRST_PERSON then
        localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
    else
        localPlayer.CameraMode = Enum.CameraMode.Classic
    end
end

-- Returns true only when all three conditions hold:
--   1. Constants.FORCE_FIRST_PERSON is true (dev mode hides viewmodel when false)
--   2. currentPhase == ACTIVE
--   3. ViewModelController.model is non-nil (weapon is equipped)
local function shouldShowViewModel(): boolean
    return Constants.FORCE_FIRST_PERSON
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

    -- Load animation tracks on the clone's Animator.
    self:_setupWeaponAnimations(weaponName, data)

    -- Apply current phase-based visibility.
    local show = shouldShowViewModel()
    visible    = show
    setVisibility(show)

    -- Begin equip → idle animation sequence.
    self:PlayEquipAnimation()
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
    localPlayer.CharacterAdded:Connect(function(_character: Model)
        self:init()
        applyCameraMode()
        -- After init(), model is nil → shouldShowViewModel() is false.
        local show = shouldShowViewModel()
        visible    = show
        setVisibility(show)
        Logger.debug("[ViewModelController] State reset on character respawn (weapon holstered)")
    end)

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

        local cam   = workspace.CurrentCamera
        local moveCF = MovementController:GetViewmodelAddCFrame()
        m:PivotTo(
            cam.CFrame
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
    -- One-shot fire track: stop immediately (no fade) and restart for each shot so rapid
    -- fire plays the full fire animation kick from frame 0 every time.
    if weaponFireTrack then
        if weaponFireTrack.IsPlaying then
            weaponFireTrack:Stop(0)
        end
        weaponFireTrack:Play()
        Logger.debug("[ViewModelController] PlayFireAnimation: fire track started")
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
    weaponReloadTrack:Play()
    -- Resume the correct base animation when reload finishes.
    -- AnimationTrack:Destroy() (called by StopWeaponAnimations / HolsterWeapon) severs this
    -- connection synchronously before it can fire on a stale weapon.
    weaponReloadTrack.Stopped:Connect(function()
        if equippedWeaponName ~= capturedWeapon or self.model == nil then return end
        isReloading = false
        -- If the player is still sprinting, resume run; otherwise return to idle.
        if isRunning and weaponRunTrack ~= nil then
            self:PlayRunAnimation()
        else
            self:PlayIdleAnimation()
        end
        Logger.debug("[ViewModelController] PlayReloadAnimation: reload complete, resumed "
            .. (isRunning and "run" or "idle"))
    end)
    Logger.debug("[ViewModelController] PlayReloadAnimation: reload track started")
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
