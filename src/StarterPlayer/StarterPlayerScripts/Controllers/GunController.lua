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

-- First-person aim cursor lock (Constants.FIRST_PERSON_AIM). Active while a weapon is
-- equipped in the ACTIVE phase; pins + hides the OS pointer so the white cursor is no
-- longer an apparent aim point.  Edge-triggered from the RenderStepped loop and forced
-- off on holster / respawn.
local firstPersonAimActive: boolean = false
local savedMouseBehavior: Enum.MouseBehavior? = nil

-- ============================================================
-- Private helpers
-- ============================================================

-- Enables/disables the first-person aim cursor lock. Idempotent; only touches
-- MouseBehavior/MouseIconEnabled on a real state change. On release it restores the
-- MouseBehavior that was in effect when it locked, so MovementController's own
-- LeftControl mouse-lock (LockCenter) is preserved rather than clobbered to Default.
local function applyFirstPersonAim(active: boolean)
    local cfg = Constants.FIRST_PERSON_AIM :: any
    if cfg.ENABLED ~= true then
        return
    end
    if active == firstPersonAimActive then
        return
    end
    firstPersonAimActive = active

    if active then
        if cfg.HIDE_DEFAULT_CURSOR == true then
            UserInputService.MouseIconEnabled = false
        end
        if cfg.LOCK_MOUSE_TO_CENTER == true then
            savedMouseBehavior = UserInputService.MouseBehavior
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
        if cfg.DEBUG == true then
            Logger.debug("[GunController] first-person aim lock ON")
        end
    else
        if cfg.RESTORE_MOUSE_ON_INACTIVE == true then
            UserInputService.MouseIconEnabled = true
            if savedMouseBehavior ~= nil then
                UserInputService.MouseBehavior = savedMouseBehavior
                savedMouseBehavior = nil
            else
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end
        if cfg.DEBUG == true then
            Logger.debug("[GunController] first-person aim lock OFF")
        end
    end
end

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
-- Bullet impact FX (Stage 1 — local, visual-only, pooled)
-- ============================================================
-- A small dust/smoke puff + a few tiny sparks at the LOCAL predicted hit point.
-- Local-only and visual-only: not replicated, never consulted for damage / ammo /
-- hit validation, and it never writes the camera. Driven from attemptFire() with the
-- existing client raycast result.
--
-- DEBT: this lives inside GunController because this task was scoped not to touch
-- default.project.json, and a standalone Controller file would not sync without a
-- Rojo map entry. Extract to
-- src/StarterPlayer/StarterPlayerScripts/Controllers/ImpactFXController.lua (keeping
-- the ImpactFX.PlayImpact / ImpactFX.Destroy shape, adding Start()) once the Rojo
-- map can be updated. No connections are stored here — cleanup is time-based only.
local ImpactFX = {}
do
    local FX = Constants.BULLET_IMPACT_FX :: any

    -- Tolerate a partially-synced Constants (old flat shape) — fall back to sane values
    -- and a plain neutral dust puff rather than erroring on nil fields.
    local DUST_TEXTURE: string   = FX.DUST_TEXTURE or "rbxasset://textures/particles/smoke_main.dds"
    local DEBRIS_TEXTURE: string = FX.DEBRIS_TEXTURE or ""
    local SPARK_TEXTURE: string  = FX.SPARK_TEXTURE or ""
    local DUST_GRAVITY: number   = FX.DUST_GRAVITY or 4
    local DEBRIS_GRAVITY: number = FX.DEBRIS_GRAVITY or 55
    local SPARK_GRAVITY: number  = FX.SPARK_GRAVITY or 40
    local POOL_SIZE: number      = FX.POOL_SIZE or 24
    local PART_LIFETIME: number  = FX.IMPACT_PART_LIFETIME or 1.0
    local SURFACE_OFFSET: number = FX.IMPACT_SURFACE_OFFSET or 0.03

    type RoleRuntime = {
        count: number,
        lifetime: NumberRange,
        speed: NumberRange,
        size: NumberSequence,
        transparency: NumberSequence,
        color: ColorSequence,
        spread: Vector2,
    }
    type Rig = {
        part: BasePart,
        dust: ParticleEmitter,
        debris: ParticleEmitter,
        spark: ParticleEmitter,
        busy: boolean,
        freeAt: number,
    }

    -- category name → { dust: RoleRuntime, debris: RoleRuntime, spark: RoleRuntime }.
    -- Built once in ensureInit() from Constants.BULLET_IMPACT_FX.CATEGORIES so PlayImpact
    -- only assigns pre-made NumberSequence/Range objects (no per-shot allocation).
    local RESOLVED: { [string]: any } = {}
    local rigs: { Rig } = {}
    local fxFolder: Folder? = nil
    local warnedPlaceholder = false
    local initialized = false

    -- Turn a Constants role sub-table (DUST / DEBRIS / SPARK) into ready-to-assign emitter
    -- values. A nil table or count <= 0 yields a silent role.
    local function resolveRole(t: any): RoleRuntime
        if t == nil or (t.count or 0) <= 0 then
            return {
                count = 0,
                lifetime = NumberRange.new(0.1),
                speed = NumberRange.new(0),
                size = NumberSequence.new(0.1),
                transparency = NumberSequence.new(1),
                color = ColorSequence.new(Color3.new(1, 1, 1)),
                spread = Vector2.zero,
            }
        end
        local sizeSeq: NumberSequence
        if t.sizeStart ~= nil then
            sizeSeq = NumberSequence.new({
                NumberSequenceKeypoint.new(0, t.sizeStart),
                NumberSequenceKeypoint.new(1, t.sizeEnd),
            })
        else
            sizeSeq = NumberSequence.new(t.size)
        end
        local baseT: number = t.transparency or 0.2
        return {
            count = t.count,
            lifetime = NumberRange.new(t.lifeMin, t.lifeMax),
            speed = NumberRange.new(t.speedMin, t.speedMax),
            size = sizeSeq,
            transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, baseT),
                NumberSequenceKeypoint.new(0.75, math.min(1, baseT + 0.3)),
                NumberSequenceKeypoint.new(1, 1),
            }),
            color = ColorSequence.new(t.color or Color3.fromRGB(150, 148, 142)),
            spread = Vector2.new(t.spread or 30, t.spread or 30),
        }
    end

    local function makeEmitter(name: string, texture: string, gravity: number,
        drag: number, lightEmission: number, tumble: boolean): ParticleEmitter
        local e = Instance.new("ParticleEmitter")
        e.Name              = name
        e.Texture           = texture
        e.Enabled           = false
        e.Rate              = 0
        e.Acceleration      = Vector3.new(0, -gravity, 0)
        e.Drag              = drag
        e.LightEmission     = lightEmission
        e.EmissionDirection = Enum.NormalId.Top -- +Y of the rig == surface normal
        if tumble then
            e.Rotation = NumberRange.new(-180, 180)
            e.RotSpeed = NumberRange.new(-140, 140)
        end
        -- Silent placeholders; PlayImpact overwrites the dynamic props per category.
        e.Lifetime     = NumberRange.new(0.1)
        e.Size         = NumberSequence.new(0.1)
        e.Transparency = NumberSequence.new(1)
        return e
    end

    local function buildRig(): Rig
        local part = Instance.new("Part")
        part.Name         = "BR_BulletImpactFx"
        part.Size         = Vector3.one * 0.05
        part.Transparency = 1
        part.Anchored     = true
        part.CanCollide   = false
        part.CanQuery     = false
        part.CanTouch     = false
        part.CastShadow   = false
        part.Locked       = true

        local att = Instance.new("Attachment")
        att.Name   = "FxAttachment"
        att.Parent = part

        local dust   = makeEmitter("Dust", DUST_TEXTURE, DUST_GRAVITY, 3.5, 0, true)
        local debris = makeEmitter("Debris", DEBRIS_TEXTURE, DEBRIS_GRAVITY, 0.6, 0, true)
        local spark  = makeEmitter("Spark", SPARK_TEXTURE, SPARK_GRAVITY, 1.8, 1, false)
        dust.Parent, debris.Parent, spark.Parent = att, att, att

        return { part = part, dust = dust, debris = debris, spark = spark, busy = false, freeAt = 0 }
    end

    local function ensureInit()
        if initialized then
            return
        end
        initialized = true

        for catName, cat in pairs(FX.CATEGORIES or {}) do
            RESOLVED[catName] = {
                dust   = resolveRole(cat.DUST),
                debris = resolveRole(cat.DEBRIS),
                spark  = resolveRole(cat.SPARK),
            }
        end
        if RESOLVED.default == nil then
            -- No CATEGORIES synced (old Constants) — still give a usable neutral impact.
            RESOLVED.default = {
                dust = resolveRole({
                    count = 6, lifeMin = 0.15, lifeMax = 0.42, speedMin = 1.5, speedMax = 4.5,
                    sizeStart = 0.24, sizeEnd = 1.05, transparency = 0.34, spread = 45,
                    color = Color3.fromRGB(154, 152, 146),
                }),
                debris = resolveRole({
                    count = 6, lifeMin = 0.15, lifeMax = 0.34, speedMin = 6, speedMax = 16,
                    size = 0.15, transparency = 0.0, spread = 30, color = Color3.fromRGB(150, 148, 142),
                }),
                spark = resolveRole(nil),
            }
        end

        local folder = Instance.new("Folder")
        folder.Name   = "BR_ImpactFx"
        folder.Parent = workspace
        fxFolder = folder

        for _ = 1, POOL_SIZE do
            local rig = buildRig()
            rig.part.Parent = folder
            table.insert(rigs, rig)
        end

        if FX.DEBUG == true then
            local cats = 0
            for _ in pairs(RESOLVED) do
                cats += 1
            end
            Logger.debug("[GunController] ImpactFX ready — pool", POOL_SIZE, "| categories", cats)
        end
    end

    -- The rig whose burst has finished, else the one finishing soonest. Never grows the pool,
    -- so full-auto can never add parts.
    local function takeRig(): Rig
        local now = os.clock()
        local best: Rig? = nil
        for _, r in ipairs(rigs) do
            if not r.busy or now >= r.freeAt then
                return r
            end
            if best == nil or r.freeAt < best.freeAt then
                best = r
            end
        end
        return best :: Rig
    end

    local function configureAndEmit(emitter: ParticleEmitter, role: RoleRuntime)
        if role.count <= 0 then
            return
        end
        emitter.Lifetime     = role.lifetime
        emitter.Speed        = role.speed
        emitter.Size         = role.size
        emitter.Transparency = role.transparency
        emitter.Color        = role.color
        emitter.SpreadAngle  = role.spread
        emitter:Emit(role.count)
    end

    -- position: local predicted hit point. normal: surface normal. material: Enum.Material
    -- of the surface (selects the per-category look; nil / unmapped → "default"). Never
    -- errors on a missing or unsupported material.
    function ImpactFX.PlayImpact(position: Vector3, normal: Vector3?, material: Enum.Material?): ()
        assert(typeof(position) == "Vector3", "position must be a Vector3")
        if normal ~= nil then
            assert(typeof(normal) == "Vector3", "normal must be a Vector3")
        end
        if FX.ENABLED ~= true then
            return
        end

        if not warnedPlaceholder
            and (DUST_TEXTURE == "rbxassetid://0" or SPARK_TEXTURE == "rbxassetid://0")
        then
            warnedPlaceholder = true
            Logger.warn("[GunController] ImpactFX: placeholder texture (rbxassetid://0) in Constants.BULLET_IMPACT_FX")
        end

        ensureInit()

        local matMap = FX.MATERIAL_CATEGORY or {}
        local catName = (material ~= nil and matMap[material]) or "default"
        local rc = RESOLVED[catName] or RESOLVED.default
        if rc == nil then
            return
        end

        -- Surface-aligned CFrame: +Y along the normal so all three emitters fire away from
        -- the surface. Fallback: unoriented at the point.
        local cf: CFrame
        local n = normal
        if n ~= nil and n.Magnitude > 1e-4 then
            n = n.Unit
            local ref = if math.abs(n.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
            local right = ref:Cross(n)
            right = if right.Magnitude > 1e-4 then right.Unit else Vector3.xAxis
            cf = CFrame.fromMatrix(position + n * SURFACE_OFFSET, right, n)
        else
            cf = CFrame.new(position)
        end

        local rig = takeRig()
        rig.part.CFrame = cf
        rig.busy   = true
        rig.freeAt = os.clock() + PART_LIFETIME
        configureAndEmit(rig.dust, rc.dust)
        configureAndEmit(rig.debris, rc.debris)
        configureAndEmit(rig.spark, rc.spark)
    end

    -- Recycle/destroy everything. Not wired yet — GunController has no destroy path
    -- (DEBT-059); present for the eventual ImpactFXController extraction.
    function ImpactFX.Destroy(): ()
        for _, r in ipairs(rigs) do
            r.part:Destroy()
        end
        table.clear(rigs)
        table.clear(RESOLVED)
        if fxFolder ~= nil then
            fxFolder:Destroy()
            fxFolder = nil
        end
        initialized = false
    end
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
        -- Tarkov-style hipfire: the bullet leaves the CAMERA travelling the way the
        -- free-aim-rotated gun visually points (ViewModelController.GetFreeAimAngles()),
        -- so rounds go where the muzzle points without depending on a cosmetic muzzle
        -- attachment or an off-camera origin. ADS and free-aim-off collapse to a camera
        -- ray through the reticle offset (0 offset = dead centre). The origin stays at
        -- the camera so the server's origin-vs-root check always passes; the authoritative
        -- server re-raycast of this origin+direction is unchanged.
        local camera    = workspace.CurrentCamera
        local origin:  Vector3 = camera.CFrame.Position
        local baseDir: Vector3
        if Constants.FREE_AIM_ENABLED
            and Constants.FREE_AIM_FIRE_FROM_MUZZLE
            and not ViewModelController:IsAiming()
        then
            local aimPitch, aimYaw = ViewModelController.GetFreeAimAngles()
            baseDir = (camera.CFrame * CFrame.Angles(aimPitch, aimYaw, 0)).LookVector
        else
            local offset = if Constants.FREE_AIM_ENABLED
                then FreeAimController:GetSmoothedAimOffset()
                else Vector2.zero
            local aimPoint = camera.ViewportSize / 2 + offset
            baseDir = camera:ViewportPointToRay(aimPoint.X, aimPoint.Y).Direction
        end
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

        -- ── Local bullet impact FX (Stage 1) ─────────────────────────────────
        -- Material-specific dust / chips / sparks at the LOCAL predicted hit point,
        -- oriented to the surface normal. Visual only: not replicated, never consulted
        -- for damage / ammo / hit validation. Pooled so full-auto cannot grow parts.
        -- ImpactFX.PlayImpact self-gates on Constants.BULLET_IMPACT_FX.ENABLED.
        if hitResult ~= nil then
            ImpactFX.PlayImpact(hitResult.Position, hitResult.Normal, hitResult.Material)
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
            -- Hide the fixed centre crosshair while hip-firing (only the floating gun-
            -- direction reticle shows); it returns for ADS.
            CrosshairUI:SetHipfireActive(
                equippedWeaponName ~= nil and not ViewModelController:IsAiming()
            )
        end

        -- First-person aim cursor lock: active while a weapon is equipped. Only additionally
        -- requires the ACTIVE round phase when FIRST_PERSON_AIM.REQUIRE_ACTIVE_PHASE is true.
        applyFirstPersonAim(
            equippedWeaponName ~= nil
            and (
                (Constants.FIRST_PERSON_AIM :: any).REQUIRE_ACTIVE_PHASE ~= true
                or MatchController:GetPhase() == Constants.Phase.ACTIVE
            )
        )
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
            -- Resolve the player's chosen primary from the BR_LoadoutPrimary
            -- attribute (LoadoutService writes it from the pre-round menu).
            -- Falls back to the default viewmodel weapon when unset or unknown.
            local chosen = LocalPlayer:GetAttribute((Constants.LOADOUT :: any).ATTR_PRIMARY)
            local weaponName: string = Constants.DEFAULT_VIEWMODEL_WEAPON
            if typeof(chosen) == "string" and WeaponData[chosen] ~= nil then
                weaponName = chosen
            end

            ViewModelController:EquipWeapon(weaponName)
            equippedWeaponName = weaponName
            -- Inform WorldWeaponService so it attaches the gun-only world model
            -- to the character's Right Arm (visible to self in third-person and
            -- to other players regardless of camera mode).
            WeaponEquipState:FireServer(weaponName, true)
            -- Notify FreeAimController so the free-aim deadzone activates + resolves the
            -- per-weapon feel profile.
            if Constants.FREE_AIM_ENABLED then
                FreeAimController:SetWeapon(equippedWeaponName)
            end
            applyFirstPersonAim(
                (Constants.FIRST_PERSON_AIM :: any).REQUIRE_ACTIVE_PHASE ~= true
                or MatchController:GetPhase() == Constants.Phase.ACTIVE
            )
            -- Switch movement animations to the armed set.
            MovementController.SetEquippedWeaponName(Constants.MOVEMENT_ANIMATION_SET_AR15)
            Logger.debug("[GunController] Equipped: " .. weaponName)
        else
            local holsteredName: string = equippedWeaponName
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
            WeaponEquipState:FireServer(holsteredName, false)
            -- Notify FreeAimController and reset the offset on holster.
            if Constants.FREE_AIM_ENABLED then
                FreeAimController:SetWeapon(nil)
                if Constants.FREE_AIM_RESET_ON_HOLSTER then
                    FreeAimController:ResetOffset()
                end
            end
            applyFirstPersonAim(false)
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
            FreeAimController:SetWeapon(nil)
            FreeAimController:ResetOffset()
        end
        applyFirstPersonAim(false)
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

    -- ── Input: ADS (aim down sights) — MB2 ────────────────────────────────────
    -- Constants.ADS_HOLD_TO_AIM: true = hold MB2 to aim / release to lower; false = press
    -- to toggle. Only drives viewmodel animation + ADS FOV/move-speed via SetAiming — no
    -- server state, no recoil/spread changes.
    local function requestAiming(active: boolean)
        if equippedWeaponName == nil then
            active = false  -- never leave the flag stuck on with no weapon
        end
        if active then
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
            if Constants.TACTICAL_SPRINT_BLOCKS_GUN_USE
                and MovementController.IsTacticalSprinting()
            then
                return
            end
            -- No ADS entry from third-person: scroll into first-person first.
            if LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson then
                return
            end
        end
        if ViewModelController:IsAiming() == active then return end
        ViewModelController:SetAiming(active)
        MovementController.SetAiming(active)
        Logger.debug("[GunController] ADS " .. (active and "engaged" or "released"))
    end

    local adsBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
        if gp then return end
        if input.UserInputType ~= Constants.ADS_INPUT_USER_INPUT_TYPE then return end
        if Constants.ADS_HOLD_TO_AIM then
            requestAiming(true)
        else
            requestAiming(not ViewModelController:IsAiming())
        end
    end)
    table.insert(_connections, adsBeganConn)

    -- Release always lowers the sights in hold mode (no gameProcessed check — a stuck
    -- "aiming" flag would be worse than a spurious release).
    local adsEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType ~= Constants.ADS_INPUT_USER_INPUT_TYPE then return end
        if Constants.ADS_HOLD_TO_AIM then
            requestAiming(false)
        end
    end)
    table.insert(_connections, adsEndedConn)

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
