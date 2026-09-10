--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > GunController
--
-- Owns client-side weapon input, shot reporting, recoil, and spread.
--
-- Weapon identity:
--   This controller reads Constants.DEFAULT_WEAPON for all client-side lookups
--   (WeaponData stats, WeaponFeel parameters). These lookups are used for
--   client-side rate-limiting, cosmetic muzzle flash duration, and recoil feel only.
--   GunService independently reads Constants.DEFAULT_WEAPON for authoritative
--   validation — GunController does not decide hits, damage, health, ammo, or the
--   real equipped weapon. When multiple weapons exist as a player choice, both sides
--   will read server-owned loadout state instead of a shared constant (DEBT-013).
--
-- Shot flow:
--   MouseButton1 → phase/rate/ammo guards → spread-perturbed raycast → WeaponFired:FireServer()
--   → PlayFireAnimation() on ViewModelController + muzzle flash + gunshot sound
--   → recoil CFrame snap pushed to ViewModelController via SetRecoilOffset()
--
-- Recoil:
--   Each shot adds an upward/sideways kick to a viewmodel-space recoil CFrame.
--   recoilBuildup accumulates while firing and resets after recoilResetTime seconds
--   of silence. RenderStepped lerps recoilCFrame back toward identity each frame.
--   The recovered CFrame is pushed to ViewModelController:SetRecoilOffset() so the
--   viewmodel rotates with each kick and smoothly returns to rest.
--   This is viewmodel-only recoil. Camera-space recoil requires CameraType.Scriptable
--   (deferred; see DEBT-045).
--
-- Spread:
--   A random angular deviation (half-cone) is applied to the raycast direction before
--   firing. Cone angle is computed from WeaponFeel values + MovementController state.
--
-- What this controller does NOT do:
--   - Decide if a shot hit or apply damage  →  GunService + DamageService (server)
--   - Render a viewmodel                    →  ViewModelController
--   - Show ammo count UI                    →  HUD (driven by AmmoChanged remote)
--
-- Initialized by ClientInit.client.lua after MovementController:Start() has run.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules      = ReplicatedStorage:WaitForChild("Modules")
local Constants    = require(Modules:WaitForChild("Constants"))
local WeaponData   = require(Modules:WaitForChild("WeaponData"))
local WeaponFeel   = require(Modules:WaitForChild("WeaponFeel"))
local Logger       = require(Modules:WaitForChild("Logger"))

local MatchController     = require(script.Parent:WaitForChild("MatchController"))
local ViewModelController = require(script.Parent:WaitForChild("ViewModelController"))
local MovementController  = require(script.Parent:WaitForChild("MovementController"))
local CrosshairUI         = require(script.Parent:WaitForChild("UI"):WaitForChild("CrosshairUI"))
local SoundController     = require(script.Parent:WaitForChild("SoundController"))
-- Stage 1 free-aim: FreeAimController is Init()ed by ClientInit before GunController:Start().
-- GunController is the "glue" that relays state → FreeAimController and offsets → CrosshairUI
-- + ViewModelController each frame.  No circular require: FreeAimController only requires
-- Constants and Logger.
local FreeAimController   = require(script.Parent:WaitForChild("FreeAimController"))

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local WeaponFired      = Remotes:WaitForChild("WeaponFired")      :: RemoteEvent
local HitConfirmed     = Remotes:WaitForChild("HitConfirmed")     :: RemoteEvent
local HealthChanged    = Remotes:WaitForChild("HealthChanged")    :: RemoteEvent
local AmmoChanged      = Remotes:WaitForChild("AmmoChanged")      :: RemoteEvent
local ReloadRequest    = Remotes:WaitForChild("ReloadRequest")    :: RemoteEvent
-- Tells WorldWeaponService to attach or remove the AKS74 world model on the character.
-- Payload: weaponName: string, isEquipped: boolean
local WeaponEquipState = Remotes:WaitForChild("WeaponEquipState") :: RemoteEvent

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Configuration
-- ============================================================

-- Constants.DEFAULT_WEAPON is the single source of truth for the active weapon name.
-- GunController reads it only for client-side prediction: dry-fire checks,
-- WeaponData range for the cosmetic raycast, and local rate limiting.
-- GunService remains authoritative — it validates all shots, ammo, and damage.
-- WeaponFired and ReloadRequest carry no weapon name by design; see DEBT-013.

-- ============================================================
-- State
-- ============================================================

-- Presentation-only flag: name of the currently equipped viewmodel weapon, or nil
-- when holstered.  Gates left-click fire and reload — no weapon means no shots.
-- Does NOT affect server validation; GunService continues to use Constants.DEFAULT_WEAPON.
-- See DEBT-013 and DEBT-059.
local equippedWeaponName: string? = nil

-- Cleanup table for new RBXScriptConnections added by this task.
-- Existing connections (fire, reload, ammo, health) pre-date this table and are not
-- stored here — they follow the existing unmanaged pattern.
-- DEBT-059: no cleanup/destroy path exists for GunController yet; connections stored
-- here are disconnected when / if a destroy() method is added in a future task.
local _connections: { RBXScriptConnection } = {}

-- Client-side rate limiting (mirrors GunService).
local lastShotTime: number = 0

-- Server-mirrored ammo state. Updated by AmmoChanged only.
local currentMag:     number = 0
local currentReserve: number = 0

-- ADS state. Visual transition is deferred (DEBT-040).

-- Recoil CFrame accumulator. Applied to ViewModelController each frame.
-- Snapped outward on each shot, lerped back to identity by RenderStepped.
local recoilBuildup:   number  = 0   -- accumulated multiplier from sustained fire
local recoilResetTimer:number  = 0   -- counts down from feel.recoilResetTime after last shot

-- Full-auto flag. Set true by InputBegan MB1; cleared by InputEnded MB1, dry-fire, or holster.
-- RenderStepped calls attemptFire() each frame while this is true; the internal cooldown check
-- gates actual shot cadence to the weapon's fireRate.
local isAutoFiring: boolean = false

-- Tracks the previous-frame reload state so RenderStepped can detect the reload→done edge
-- and exit ADS automatically.
local wasReloading: boolean = false

-- Last locomotion state sent to ViewModelController.
-- Compared each RenderStepped to detect changes; SetLocomotionState is called only on edge.
local lastLocomotionState: string = "Idle"

-- ============================================================
-- Private helpers
-- ============================================================

-- Applies a spread cone perturbation to a unit direction vector.
-- spreadDeg is the half-cone angle in degrees.
-- Returns a new unit vector that deviates from dir by a random angle within the cone.
local function applySpread(dir: Vector3, spreadDeg: number): Vector3
    if spreadDeg <= 0 then return dir end
    local halfAngle = math.rad(spreadDeg)
    -- Random polar coordinates within the cone.
    local theta  = math.random() * halfAngle           -- deviation from axis
    local phi    = math.random() * math.pi * 2         -- rotation around axis
    -- Build a perpendicular basis.
    local up     = math.abs(dir.Y) < 0.99 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
    local right  = dir:Cross(up).Unit
    local upPerp = dir:Cross(right).Unit
    -- Apply deviation.
    local deviation = (right * math.cos(phi) + upPerp * math.sin(phi)) * math.tan(theta)
    return (dir + deviation).Unit
end

-- Computes the total spread half-cone angle in degrees from WeaponFeel + movement state.
local function computeSpread(feel: { [string]: any }): number
    local isADS = ViewModelController:IsAiming()
    local moveState = MovementController:GetMoveState()
    local spread    = (isADS and (feel.baseSpread :: number) or
                      (feel.baseSpread :: number) + (feel.hipfireSpread :: number))

    if moveState == "Walking" then
        spread = spread + (feel.movingSpreadAdd :: number)
    elseif moveState == "Sprinting" or moveState == "Sliding" then
        spread = spread + (feel.sprintingSpreadAdd :: number)
    elseif moveState == "Crouching" then
        spread = spread * (feel.crouchSpreadMult :: number)
    end

    return spread
end

-- ============================================================
-- Controller
-- ============================================================

local CameraRecoil = require(script.Parent:WaitForChild("CameraRecoil"))
local GunController = {}

function GunController:Start()
    CameraRecoil.Start()

    -- ── attemptFire: internal helper — fire one shot if all guards pass ────────
    -- Defined before RenderStepped and InputBegan so both closures can reference it.
    -- Returns true on a successful shot, false on any guard failure.
    -- Reads WeaponData[equippedWeaponName] for client-side rate limiting so the client
    -- paces shots at AKS74's 650 RPM; GunService still validates against AR15 (DEBT-013).
    local function attemptFire(): boolean
        -- Guard: weapon must be equipped.
        local weapon = equippedWeaponName
        if weapon == nil then return false end

        -- Guard: phase must be ACTIVE.
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return false end

        -- Guard: WeaponFeel data must exist (uses DEFAULT_WEAPON for all cosmetics).
        local feel = WeaponFeel[equippedWeaponName or Constants.DEFAULT_WEAPON] or WeaponFeel[Constants.DEFAULT_WEAPON]
        if not feel then
            Logger.warn("[GunController] No WeaponFeel entry for:", Constants.DEFAULT_WEAPON)
            return false
        end

        -- Guard: DEFAULT_WEAPON stat block must exist (needed for range and fallback rate).
        local defaultDef = WeaponData[Constants.DEFAULT_WEAPON]
        if not defaultDef then
            Logger.warn("[GunController] No WeaponData entry for:", Constants.DEFAULT_WEAPON)
            return false
        end

        -- Derive client-side shot interval. Prefer equipped weapon's rpm then fireRate,
        -- then fall back to DEFAULT_WEAPON fireRate. AKS74 at 650 RPM = ~0.0923 s;
        -- AR15 server limit is 0.09 s (more restrictive) so all AKS74 shots pass.
        local interval: number
        local equippedDef = (WeaponData :: any)[weapon :: string]
        if equippedDef ~= nil then
            local rpm = (equippedDef :: any).rpm
            local fr  = (equippedDef :: any).fireRate
            if typeof(rpm) == "number" and (rpm :: number) > 0 then
                interval = 60 / (rpm :: number)
            elseif typeof(fr) == "number" and (fr :: number) > 0 then
                interval = fr :: number
            else
                interval = defaultDef.fireRate
                Logger.warn("[GunController] No rpm/fireRate for " .. weapon .. " — using DEFAULT_WEAPON fallback")
            end
        else
            interval = defaultDef.fireRate
        end

        -- Guard: dry fire — no rounds in magazine.
        if currentMag <= 0 then
            SoundController:PlayDryFire()
            isAutoFiring = false
            Logger.debug("[GunController] Dry fire — auto-fire stopped")
            return false
        end

        -- Guard: cannot fire while reloading.
        if ViewModelController:GetIsReloading() then return false end

        -- Guard: client-side rate limit (mirrors server; server re-validates independently).
        local now = os.clock()
        if now - lastShotTime < interval then return false end

        -- Guard: ADS may be blocked by movement.
        local isADS = ViewModelController:IsAiming()

        -- Guard: tactical sprint blocks fire (client-side presentation only).
        if Constants.TACTICAL_SPRINT_BLOCKS_GUN_USE
            and MovementController.IsTacticalSprinting()
        then
            return false
        end

        -- Guard: regular sprint blocks fire too — you cannot shoot while running.
        -- GetMoveState() == "Sprinting" means isSprinting AND actually moving.
        if Constants.SPRINT_BLOCKS_GUN_USE
            and MovementController:GetMoveState() == "Sprinting"
        then
            return false
        end

        -- Guard: character must exist.
        local character = LocalPlayer.Character
        if not character then return false end

        -- ── Spread-perturbed raycast ──────────────────────────────────────────
        local camera    = workspace.CurrentCamera
        local origin    = camera.CFrame.Position
        -- Use the same screen-space point as the visible free-aim reticle.
        local offset = if Constants.FREE_AIM_ENABLED then FreeAimController:GetSmoothedAimOffset() else Vector2.zero
        local aimPoint = camera.ViewportSize / 2 + offset
        local baseDir = camera:ViewportPointToRay(aimPoint.X, aimPoint.Y).Direction
        local spread    = computeSpread(feel)
        local direction = applySpread(baseDir, spread)

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character }

        local hitResult = workspace:Raycast(origin, direction.Unit * defaultDef.range, params)

        lastShotTime = now
        WeaponFired:FireServer(origin, direction, now)

        -- ── Recoil CFrame snap ────────────────────────────────────────────────
        recoilBuildup = math.min(
            recoilBuildup + (feel.recoilBuildup :: number),
            feel.recoilBuildupMax :: number
        )
        recoilResetTimer = feel.recoilResetTime :: number

        local profile = equippedDef and (equippedDef :: any).recoil
        local camSub = profile and profile.camera and (if isADS then profile.camera.ads else profile.camera.hip)
        local kickUp = if camSub then camSub.kickUp else Constants.DEFAULT_CAMERA_RECOIL_KICK_UP
        local kickSide = if camSub then camSub.kickRight else Constants.DEFAULT_CAMERA_RECOIL_KICK_RIGHT
        CameraRecoil.Kick(kickUp * (1 + recoilBuildup), kickSide)

        -- ── Audio and visuals ─────────────────────────────────────────────────
        -- Use per-weapon fire sounds when available (WeaponData[weapon].sounds.fireFirstPerson).
        -- Falls back to the legacy PlayGunshot() for weapons that predate the sound data table.
        local fireSounds = equippedDef ~= nil
            and (equippedDef :: any).sounds
            and (equippedDef :: any).sounds.fireFirstPerson
        if typeof(fireSounds) == "table" and #(fireSounds :: { string }) > 0 then
            SoundController:PlayWeaponFire(fireSounds :: { string })
        else
            SoundController:PlayGunshot()
        end
        if ViewModelController:IsAiming() then
            ViewModelController:PlayADSFireAnimation()
        else
            ViewModelController:PlayFireAnimation()
        end

        -- ── Viewmodel recoil impulse (Stage 1 — viewmodel only) ──────────────
        if Constants.VIEWMODEL_RECOIL_ENABLED then
            local recoilProfile = equippedDef ~= nil and (equippedDef :: any).recoil or nil
            ViewModelController:ApplyRecoil(ViewModelController:IsAiming(), recoilProfile)
        end

        -- ── Debug muzzle marker (disabled by default) ─────────────────────────
        if Constants.DEBUG_BULLET_IMPACT_MARKERS then
            local markerSize = Constants.DEBUG_BULLET_IMPACT_MARKER_SIZE :: number
            local flash        = Instance.new("Part")
            flash.Name         = "MuzzleFlash"
            flash.Size         = Vector3.new(markerSize, markerSize, markerSize)
            flash.BrickColor   = BrickColor.new("Bright yellow")
            flash.Material     = Enum.Material.Neon
            flash.Transparency = Constants.DEBUG_BULLET_IMPACT_MARKER_TRANSPARENCY :: number
            flash.CanCollide   = false
            flash.CastShadow   = false
            flash.Anchored     = true
            flash.CFrame       = ViewModelController:GetBarrelTipCFrame()
            flash.Parent       = workspace.CurrentCamera
            local flashMesh    = Instance.new("SpecialMesh")
            flashMesh.MeshType = Enum.MeshType.Sphere
            flashMesh.Parent   = flash
            task.delay(Constants.DEBUG_BULLET_IMPACT_MARKER_LIFETIME :: number, function()
                flash:Destroy()
            end)
        end

        -- ── Bullet impact effect ──────────────────────────────────────────────
        if Constants.BULLET_IMPACT_ENABLED and hitResult ~= nil then
            local impactSize = Constants.BULLET_IMPACT_SIZE :: number
            local impact        = Instance.new("Part")
            impact.Name         = "BulletImpact"
            impact.Size         = Vector3.new(impactSize, impactSize, impactSize)
            impact.Color        = Constants.BULLET_IMPACT_COLOR :: Color3
            impact.Material     = Enum.Material.SmoothPlastic
            impact.Transparency = Constants.BULLET_IMPACT_TRANSPARENCY :: number
            impact.CanCollide   = false
            impact.CastShadow   = false
            impact.Anchored     = true
            impact.CFrame       = CFrame.new(hitResult.Position)
            impact.Parent       = workspace.CurrentCamera
            local impactMesh    = Instance.new("SpecialMesh")
            impactMesh.MeshType = Enum.MeshType.Sphere
            impactMesh.Parent   = impact
            task.delay(Constants.BULLET_IMPACT_LIFETIME :: number, function()
                impact:Destroy()
            end)
        end

        return true
    end

    -- ── RenderStepped: recoil recovery ────────────────────────────────────────
    -- Lerps recoilCFrame back toward identity each frame, then pushes the result
    -- to ViewModelController so the viewmodel tracks the recovery.
    RunService.RenderStepped:Connect(function(dt: number)
        local feel = WeaponFeel[equippedWeaponName or Constants.DEFAULT_WEAPON] or WeaponFeel[Constants.DEFAULT_WEAPON]
        if not feel then return end

        -- Decay the recoil CFrame back to identity.
        if recoilResetTimer > 0 then
            recoilResetTimer = recoilResetTimer - dt
            if recoilResetTimer <= 0 then
                recoilBuildup    = 0
                recoilResetTimer = 0
            end
        end

        -- Push the current recoil CFrame to ViewModelController every frame
        -- so the viewmodel smoothly returns to rest as recoilCFrame decays.
        -- CameraRecoil owns camera rotation; do not apply it a second time to the gun.
        ViewModelController:SetRecoilOffset(CFrame.new())

        -- Locomotion state: map MovementController state to viewmodel locomotion.
        -- GetMoveState() returns "Sprinting" for both shift-held run and tactical sprint;
        -- IsTacticalSprinting() is the only reliable way to separate the two.
        -- Speed-based detection is intentionally absent: normal walk speed (~16 studs/s)
        -- exceeds any reasonable "run" speed threshold and would misfire constantly.
        if equippedWeaponName ~= nil then
            local moveState = MovementController:GetMoveState()
            local locomotionState: string
            if moveState == "Sprinting" and MovementController.IsTacticalSprinting() then
                locomotionState = "Sprint"
            elseif moveState == "Sprinting" then
                locomotionState = "Run"
            elseif moveState == "Walking" then
                locomotionState = "Walk"
            else
                locomotionState = "Idle"
            end
            if locomotionState ~= lastLocomotionState then
                lastLocomotionState = locomotionState
                ViewModelController:SetLocomotionState(locomotionState)
            end
        end

        -- Stage 1 free-aim sync.
        -- Push current game state to FreeAimController so it can decide suppression,
        -- then relay the resulting offsets to CrosshairUI and ViewModelController.
        -- Gated on the master switch so a single constant toggles all free-aim behaviour.
        if Constants.FREE_AIM_ENABLED then
            local sprinting = MovementController:GetMoveState() == "Sprinting"
            FreeAimController:SetSprinting(sprinting)
            FreeAimController:SetReloading(ViewModelController:GetIsReloading())
            FreeAimController:SetAiming(ViewModelController:IsAiming())
            ViewModelController:SetFreeAimOffset(FreeAimController:GetNormalizedAimOffset())
            if Constants.FREE_AIM_MOUSE_INERTIA_ENABLED then
                ViewModelController:SetMouseInertia(UserInputService:GetMouseDelta())
            end
            CrosshairUI:SetFreeAimOffset(FreeAimController:GetSmoothedAimOffset())
            CrosshairUI:SetFreeAimEnabled(
                FreeAimController:IsEnabled() and equippedWeaponName ~= nil
            )
        end
        -- Task A/B: sync reload state to MovementController each frame so the stance POV
        -- reload multiplier stays accurate without creating a VMC→MC dependency.
        local nowReloading = ViewModelController:GetIsReloading()
        MovementController.SetReloading(nowReloading)
        -- Sync fire state so MovementController can block a sprint start while shooting
        -- (the "cannot run while shooting" half of the mutual exclusion).
        MovementController.SetFiring(isAutoFiring)
        -- On the reload→done edge, exit ADS so the weapon returns to hip idle.
        if wasReloading and not nowReloading then
            ViewModelController:SetAiming(false)
            MovementController.SetAiming(false)
        end
        wasReloading = nowReloading

        -- Full-auto: fire each frame while button is held; internal rate limit gates cadence.
        if isAutoFiring then
            attemptFire()
        end
    end)

    -- ── Input: Key 1 — equip / holster AKS74 viewmodel ─────────────────────
    -- Toggles the first-person viewmodel on / off.  Presentation-only: the server
    -- continues to use Constants.DEFAULT_WEAPON for all authoritative validation.
    -- Using UserInputService.InputBegan to match the existing input style in this controller.
    local equipConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
        if gp then return end
        if input.KeyCode ~= Constants.VIEWMODEL_EQUIP_KEY then return end
        if equippedWeaponName == nil then
            ViewModelController:EquipWeapon(Constants.DEFAULT_VIEWMODEL_WEAPON)
            equippedWeaponName = Constants.DEFAULT_VIEWMODEL_WEAPON
            -- Inform WorldWeaponService so it attaches the gun-only world model
            -- to the character's Right Arm (visible to self in third-person and
            -- to other players regardless of camera mode).
            WeaponEquipState:FireServer(Constants.DEFAULT_VIEWMODEL_WEAPON, true)
            -- Notify FreeAimController so the free-aim deadzone activates.
            if Constants.FREE_AIM_ENABLED then
                FreeAimController:SetWeaponEquipped(true)
            end
            -- Switch movement animations to the armed set.
            MovementController.SetEquippedWeaponName(Constants.MOVEMENT_ANIMATION_SET_AR15)
            Logger.debug("[GunController] Equipped: " .. Constants.DEFAULT_VIEWMODEL_WEAPON)
        else
            ViewModelController:HolsterWeapon()
            CameraRecoil.Reset()
            equippedWeaponName = nil
            isAutoFiring = false
            lastLocomotionState = "Idle"
            -- Clear ADS state in MovementController so focus zoom and sprint-lock
            -- do not persist after the gun is put away.
            MovementController.SetAiming(false)
            -- Restore movement animations to the unarmed set.
            MovementController.SetEquippedWeaponName(nil)
            -- Inform WorldWeaponService to remove the world model.
            WeaponEquipState:FireServer(Constants.DEFAULT_VIEWMODEL_WEAPON, false)
            -- Notify FreeAimController and reset the offset on holster.
            if Constants.FREE_AIM_ENABLED then
                FreeAimController:SetWeaponEquipped(false)
                if Constants.FREE_AIM_RESET_ON_HOLSTER then
                    FreeAimController:ResetOffset()
                end
            end
            Logger.debug("[GunController] Holstered weapon")
        end
    end)
    table.insert(_connections, equipConn)

    -- Sync equippedWeaponName with ViewModelController on character respawn.
    -- ViewModelController:init() holsters the weapon on CharacterAdded; this listener
    -- ensures GunController's local state matches so fire / reload remain gated.
    local respawnConn = LocalPlayer.CharacterAdded:Connect(function(_character: Model)
        equippedWeaponName = nil
        CameraRecoil.Reset()
        recoilBuildup = 0
        recoilResetTimer = 0
        isAutoFiring = false
        lastLocomotionState = "Idle"
        -- Clear ADS state and movement animation set in MovementController on respawn.
        MovementController.SetAiming(false)
        MovementController.SetEquippedWeaponName(nil)
        -- Reset free-aim state on respawn: weapon is holstered, offset is cleared.
        if Constants.FREE_AIM_ENABLED then
            FreeAimController:SetWeaponEquipped(false)
            FreeAimController:ResetOffset()
        end
        Logger.debug("[GunController] equippedWeaponName cleared on respawn (weapon holstered)")
    end)
    table.insert(_connections, respawnConn)

    -- ── Input: Fire (full-auto MB1) ───────────────────────────────────────────
    -- InputBegan sets the isAutoFiring flag and fires the first shot immediately.
    -- RenderStepped fires subsequent shots while the flag is true, gated by the
    -- internal rate limit in attemptFire(). InputEnded clears the flag.
    -- Both connections are stored in _connections for future cleanup.

    local fireBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if equippedWeaponName == nil then return end
        if isAutoFiring then return end
        isAutoFiring = true
        Logger.debug("[GunController] Auto-fire started")
        attemptFire()
    end)
    table.insert(_connections, fireBeganConn)

    local fireEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
        -- Always release the trigger even if UI consumed the release.
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if not isAutoFiring then return end
        isAutoFiring = false
        Logger.debug("[GunController] Auto-fire stopped")
    end)
    table.insert(_connections, fireEndedConn)

    -- ── Input: Reload ─────────────────────────────────────────────────────────

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then return end
        if input.KeyCode ~= Enum.KeyCode.R then return end
        -- Block reload while holstered (no weapon in hand).
        if equippedWeaponName == nil then return end
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
        -- Stage 2P: block reload while tactical sprint is active.
        if Constants.TACTICAL_SPRINT_BLOCKS_GUN_USE
            and MovementController.IsTacticalSprinting()
        then
            return
        end
        ReloadRequest:FireServer()
        SoundController:PlayReload()
        -- currentMag reflects the last AmmoChanged; <= 0 means this is an empty-mag reload.
        ViewModelController:PlayReloadAnimation(currentMag <= 0)
        Logger.debug("[GunController] Reload requested", currentMag <= 0 and "(empty)" or "(tactical)")
    end)

    -- ── Input: ADS (aim down sights) — MB2 toggle ─────────────────────────────
    -- Toggles first-person ADS animation on/off.
    -- Only affects viewmodel animation; no server state, no recoil/spread changes.
    -- MB2 press toggles isAiming state; GunController uses ViewModelController:IsAiming()
    -- to decide which fire animation to play (normal fire vs ADS fire).
    local adsConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
        if gp then return end
        if input.UserInputType ~= Constants.ADS_INPUT_USER_INPUT_TYPE then return end
        -- Block ADS while holstered (no weapon in hand).
        if equippedWeaponName == nil then return end
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
        -- Stage 2P: block ADS while tactical sprint is active.
        if Constants.TACTICAL_SPRINT_BLOCKS_GUN_USE
            and MovementController.IsTacticalSprinting()
        then
            return
        end
        -- Block ADS entry from third-person: player must scroll into first-person first.
        local currentlyAiming = ViewModelController:IsAiming()
        local newAiming = not currentlyAiming
        if newAiming and LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson then
            return
        end
        ViewModelController:SetAiming(newAiming)
        -- Task A: notify MovementController so it can cancel sprint and manage ADS FOV.
        MovementController.SetAiming(newAiming)
        Logger.debug("[GunController] ADS toggled: " .. tostring(newAiming))
    end)
    table.insert(_connections, adsConn)

    -- ── Server event listeners ────────────────────────────────────────────────

    HitConfirmed.OnClientEvent:Connect(function()
        CrosshairUI:ShowHitmarker()
        Logger.debug("[GunController] HIT")
    end)

    -- GunService updated this player's ammo. Cache for dry-fire check and GetAmmo().
    -- _weaponName is forwarded by the server but not used here; HUD displays it.
    AmmoChanged.OnClientEvent:Connect(function(_weaponName: string, mag: number, reserve: number)
        currentMag     = mag
        currentReserve = reserve
        Logger.debug(string.format("[GunController] Ammo: %d / %d", mag, reserve))
    end)

    HealthChanged.OnClientEvent:Connect(function(current: number, maximum: number)
        Logger.debug(string.format("[GunController] Health: %d / %d", current, maximum))
    end)

    Logger.debug("[GunController] Ready")
end

-- Returns the locally cached magazine and reserve ammo counts.
function GunController:GetAmmo(): (number, number)
    return currentMag, currentReserve
end

-- Returns the current recoil CFrame (rotation offset applied to the viewmodel).
-- Read by external systems that need to know current recoil state.
function GunController:GetRecoilOffset(): CFrame
    return CameraRecoil.GetOffset()
end

return GunController
