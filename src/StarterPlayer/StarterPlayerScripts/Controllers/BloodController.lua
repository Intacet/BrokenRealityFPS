--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > BloodController
--
-- Client-side blood visuals. Reproduces a short particle burst and a few surface marks
-- from the data the server sends on BloodEffect { hitPosition, hitDirection, intensity,
-- damageType }. The server never creates an instance — every particle and mark lives and
-- dies here, under hard caps.
--
-- Look (gritty, not arcade): a fine retrograde MIST (soft sprite, sprays back toward the
-- shooter, nudged up) plus heavier DROPLETS (small squares) that arc and fall. Surface
-- marks are small irregular flat parts in a dark-red palette, scattered with a few tiny
-- satellite spots, that fade in fast and fade out at end of life. All texture-free except
-- the built-in smoke sprite for the mist.
--
-- Reusable character system: it is driven purely by the BloodEffect remote and is not
-- aware of the test dummy, players, or NPCs. Disable everything at once by setting the
-- ReplicatedStorage attribute named by Constants.BLOOD_GLOBAL_ATTRIBUTE to false (the
-- developer blood toggle does exactly that).
--
-- Initialized by ClientInit via loadAndStart (Start() only; no PlayerGui).
--
-- What this controller does NOT do:
--   - Decide when blood happens or how much  →  BloodService (server)
--   - Any UI                                 →  it is a world-effects controller

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local BloodEffect = Remotes:WaitForChild("BloodEffect") :: RemoteEvent

local GLOBAL_ATTR = Constants.BLOOD_GLOBAL_ATTRIBUTE :: string
local BLOOD_COLOR = Constants.BLOOD_COLOR :: Color3
local BLOOD_DARK  = Constants.BLOOD_COLOR_DARK :: Color3

-- Untyped view of Constants so the many BLOOD_* tuning numbers read without a cast each.
local C = Constants :: any

local BloodController = {}

-- ============================================================
-- State
-- ============================================================

local fxFolder: Folder

type Burst = { part: BasePart, mist: ParticleEmitter, droplet: ParticleEmitter, freeAt: number, busy: boolean }
local bursts: { Burst } = {}

type Mark = { part: BasePart, bornAt: number, expireAt: number, baseT: number }
local marks:  { Mark } = {}   -- anchored floor-pool marks + their satellites (ring buffer)
local bodyFx: { Mark } = {}   -- small splatters + wound balls welded to a hit limb (ring buffer)

local started = false

-- ============================================================
-- Helpers
-- ============================================================

local function bloodOn(): boolean
    return ReplicatedStorage:GetAttribute(GLOBAL_ATTR) ~= false
end

local function makeEmitter(
    texture: string,
    sizeStart: number,
    sizeEnd: number,
    lifeMin: number,
    lifeMax: number,
    speedMin: number,
    speedMax: number,
    spread: number,
    gravity: number,
    drag: number,
    fadeStart: number
): ParticleEmitter
    local e = Instance.new("ParticleEmitter")
    e.Texture       = texture
    e.Enabled       = false
    e.Rate          = 0
    e.Lifetime      = NumberRange.new(lifeMin, lifeMax)
    e.Speed         = NumberRange.new(speedMin, speedMax)
    e.SpreadAngle   = Vector2.new(spread, spread)
    e.Acceleration  = Vector3.new(0, -gravity, 0)
    e.Drag          = drag
    e.LightEmission  = 0
    e.Rotation      = NumberRange.new(-180, 180)
    e.RotSpeed      = NumberRange.new(-160, 160)
    e.EmissionDirection = Enum.NormalId.Top   -- +Y of the host part == spray axis
    e.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, sizeStart),
        NumberSequenceKeypoint.new(1, sizeEnd),
    })
    e.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, fadeStart),
        NumberSequenceKeypoint.new(0.7, math.min(1, fadeStart + 0.35)),
        NumberSequenceKeypoint.new(1, 1),
    })
    -- Fresh at the spray tip, settling toward the dark tone as each particle ages.
    e.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, BLOOD_COLOR),
        ColorSequenceKeypoint.new(1, BLOOD_DARK),
    })
    return e
end

local function buildPool()
    fxFolder = Instance.new("Folder")
    fxFolder.Name   = "BR_BloodFx"
    fxFolder.Parent = workspace

    for _ = 1, (Constants.BLOOD_POOL_SIZE :: number) do
        local part = Instance.new("Part")
        part.Name         = "BloodBurst"
        part.Size         = Vector3.one * 0.1
        part.Transparency = 1
        part.Anchored     = true
        part.CanCollide   = false
        part.CanQuery     = false
        part.CanTouch     = false
        part.CastShadow   = false
        part.Locked       = true
        part.Parent       = fxFolder

        local mist = makeEmitter(
            C.BLOOD_MIST_TEXTURE,
            C.BLOOD_MIST_SIZE_START, C.BLOOD_MIST_SIZE_END,
            C.BLOOD_MIST_LIFETIME_MIN, C.BLOOD_MIST_LIFETIME_MAX,
            C.BLOOD_MIST_SPEED_MIN, C.BLOOD_MIST_SPEED_MAX,
            C.BLOOD_MIST_SPREAD, C.BLOOD_MIST_GRAVITY, 4, 0.12
        )
        mist.Name   = "Mist"
        mist.Parent = part

        local droplet = makeEmitter(
            "",  -- blank = small solid square, reads as a droplet/fleck
            C.BLOOD_DROPLET_SIZE_START, C.BLOOD_DROPLET_SIZE_END,
            C.BLOOD_DROPLET_LIFETIME_MIN, C.BLOOD_DROPLET_LIFETIME_MAX,
            C.BLOOD_DROPLET_SPEED_MIN, C.BLOOD_DROPLET_SPEED_MAX,
            C.BLOOD_DROPLET_SPREAD, C.BLOOD_DROPLET_GRAVITY, 1.5, 0.0
        )
        droplet.Name   = "Droplet"
        droplet.Parent = part

        table.insert(bursts, { part = part, mist = mist, droplet = droplet, freeAt = 0, busy = false })
    end
end

-- Grabs a free burst, or steals the one that will free soonest if all are busy.
local function takeBurst(): Burst
    local best: Burst? = nil
    for _, b in ipairs(bursts) do
        if not b.busy then
            return b
        end
        if best == nil or b.freeAt < best.freeAt then
            best = b
        end
    end
    return best :: Burst
end

local function playBurst(position: Vector3, travelDir: Vector3, intensity: number)
    local b = takeBurst()

    -- Spray axis: back toward the shooter (retrograde spatter), tilted up so the mist
    -- rises and the droplets arc over before gravity takes them.
    local axis = -travelDir
    if axis.Magnitude < 1e-3 then
        axis = Vector3.yAxis
    end
    axis = (axis.Unit + Vector3.yAxis * (Constants.BLOOD_SPRAY_UP_BIAS :: number))
    axis = axis.Magnitude > 1e-4 and axis.Unit or Vector3.yAxis

    local ref = if math.abs(axis.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
    local right = ref:Cross(axis)
    right = right.Magnitude > 1e-4 and right.Unit or Vector3.xAxis
    b.part.CFrame = CFrame.fromMatrix(position, right, axis)

    local mistCount = math.round(C.BLOOD_MIST_BASE + intensity * C.BLOOD_MIST_PER_INTENSITY)
    local dropCount = math.round(C.BLOOD_DROPLET_BASE + intensity * C.BLOOD_DROPLET_PER_INTENSITY)
    b.mist:Emit(mistCount)
    b.droplet:Emit(dropCount)

    b.busy   = true
    b.freeAt = os.clock() + (Constants.BLOOD_BURST_LIFETIME :: number)
end

-- ============================================================
-- Surface marks / body splatter / wounds
-- ============================================================

local THICK = Constants.BLOOD_MARK_THICKNESS :: number

local function randBaseT(): number
    local tMin: number = C.BLOOD_MARK_TRANSPARENCY_MIN
    local tMax: number = C.BLOOD_MARK_TRANSPARENCY_MAX
    return tMin + math.random() * (tMax - tMin)
end

-- Perpendicular basis for a unit normal.
local function basisFor(n: Vector3): (Vector3, Vector3)
    local ref = if math.abs(n.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
    local r = ref:Cross(n)
    r = r.Magnitude > 1e-4 and r.Unit or Vector3.xAxis
    local ang = math.random() * math.pi * 2
    local right = (r * math.cos(ang) + n:Cross(r) * math.sin(ang)).Unit
    return right, right:Cross(n).Unit
end

-- A flat, slightly irregular blood mark. Anchored under fxFolder, or welded to `weldTo`.
local function makeFlatMark(cf: CFrame, size: number, weldTo: BasePart?): BasePart
    local part = Instance.new("Part")
    part.Name          = "BloodMark"
    part.Size          = Vector3.new(
        size * (0.7 + math.random() * 0.6),
        THICK,
        size * (0.7 + math.random() * 0.6)
    )
    part.CFrame        = cf
    part.CanCollide    = false
    part.CanQuery      = false
    part.CanTouch      = false
    part.CastShadow    = false
    part.Locked        = true
    part.Material      = Enum.Material.SmoothPlastic
    part.Color         = BLOOD_COLOR:Lerp(BLOOD_DARK, math.random() * 0.6)
    part.Transparency  = 1    -- fades in via onHeartbeat
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    if weldTo ~= nil then
        part.Anchored = false
        part.Massless = true
        part.Parent   = weldTo
        local w = Instance.new("WeldConstraint")
        w.Part0  = part
        w.Part1  = weldTo
        w.Parent = part
    else
        part.Anchored = true
        part.Parent   = fxFolder
    end
    return part
end

-- A dark ball mostly sunk into the limb along the shot line — the "carved" wound.
local function makeWound(position: Vector3, shotDir: Vector3, size: number, weldTo: BasePart): BasePart
    local part = Instance.new("Part")
    part.Name         = "BloodWound"
    part.Shape        = Enum.PartType.Ball
    part.Size         = Vector3.one * size
    part.CFrame       = CFrame.new(position - shotDir * (size * (Constants.BLOOD_WOUND_SINK :: number)))
    part.Color        = Constants.BLOOD_WOUND_COLOR :: Color3
    part.Material     = Enum.Material.SmoothPlastic
    part.CanCollide   = false
    part.CanQuery     = false
    part.CanTouch     = false
    part.CastShadow   = false
    part.Locked       = true
    part.Anchored     = false
    part.Massless     = true
    part.Transparency = 1
    part.Parent       = weldTo
    local w = Instance.new("WeldConstraint")
    w.Part0  = part
    w.Part1  = weldTo
    w.Parent = part
    return part
end

local function pushRecord(list: { Mark }, cap: number, part: BasePart, lifetime: number)
    if #list >= cap then
        local old = table.remove(list, 1)
        if old ~= nil then
            old.part:Destroy()
        end
    end
    local now = os.clock()
    table.insert(list, { part = part, bornAt = now, expireAt = now + lifetime, baseT = randBaseT() })
end

-- Probe around the hit for the limb that was struck (a BasePart under a Humanoid model).
local function findHitLimb(position: Vector3, shotDir: Vector3): BasePart?
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { fxFolder }
    rp.IgnoreWater = true
    local probes = { shotDir, -shotDir, Vector3.yAxis, -Vector3.yAxis }
    for _, d in ipairs(probes) do
        local r = workspace:Raycast(position - d * 1.2, d * 2.4, rp)
        if r ~= nil then
            local model = r.Instance:FindFirstAncestorWhichIsA("Model")
            if model ~= nil and model:FindFirstChildWhichIsA("Humanoid") ~= nil then
                return r.Instance
            end
        end
    end
    return nil
end

-- A BloodEffect only fires for a Humanoid that took damage, so `position` is always on a
-- body: a few small welded splatters + one recessed wound there, plus a bigger pool of
-- marks on the floor found by casting straight down (past the hit character).
local function spawnBloodMarks(position: Vector3, travelDir: Vector3, intensity: number)
    local shotDir = travelDir.Magnitude > 1e-3 and travelDir.Unit or Vector3.new(0, -1, 0)
    local limb    = findHitLimb(position, shotDir)
    local model   = limb ~= nil and limb:FindFirstAncestorWhichIsA("Model") or nil

    -- ── Body: small splatters welded to the limb (entry side faces the shooter). ──
    local entryN = -shotDir
    entryN = entryN.Magnitude > 1e-4 and entryN.Unit or Vector3.yAxis
    local bodyMin: number = C.BLOOD_BODY_MARK_SIZE_MIN
    local bodyMax: number = C.BLOOD_BODY_MARK_SIZE_MAX
    local spread: number  = C.BLOOD_BODY_MARK_SPREAD
    local eRight, eLook = basisFor(entryN)
    for _ = 1, (C.BLOOD_BODY_MARK_COUNT :: number) do
        local off = eRight * ((math.random() - 0.5) * 2 * spread)
            + eLook * ((math.random() - 0.5) * 2 * spread)
        local r2, l2 = basisFor(entryN)
        local size = (bodyMin + math.random() * (bodyMax - bodyMin)) * (0.6 + 0.5 * intensity)
        local cf = CFrame.fromMatrix(position + off + entryN * THICK, r2, entryN, l2)
        local part = makeFlatMark(cf, size, limb)
        pushRecord(bodyFx, C.BLOOD_MAX_BODY_FX, part, C.BLOOD_BODY_MARK_LIFETIME)
    end

    -- ── Wound: a dark ball carved into the limb. ──
    if limb ~= nil and (C.BLOOD_WOUND_ENABLED :: boolean) then
        local wMin: number = C.BLOOD_WOUND_SIZE_MIN
        local wMax: number = C.BLOOD_WOUND_SIZE_MAX
        local wsize = (wMin + math.random() * (wMax - wMin)) * (0.7 + 0.5 * intensity)
        local wp = makeWound(position, shotDir, wsize, limb)
        pushRecord(bodyFx, C.BLOOD_MAX_BODY_FX, wp, C.BLOOD_WOUND_LIFETIME)
    end

    -- ── Floor pool: bigger marks straight below the hit (and a step downrange). ──
    local groundParams = RaycastParams.new()
    groundParams.FilterType = Enum.RaycastFilterType.Exclude
    groundParams.FilterDescendantsInstances = model ~= nil and { fxFolder, model } or { fxFolder }
    groundParams.IgnoreWater = true

    local gMin: number = C.BLOOD_GROUND_MARK_SIZE_MIN
    local gMax: number = C.BLOOD_GROUND_MARK_SIZE_MAX
    local gRange: number = C.BLOOD_GROUND_RANGE
    local gSats: number  = C.BLOOD_GROUND_SATELLITES
    local gSatRange: number = C.BLOOD_GROUND_SATELLITE_RANGE
    local gSatSize: number  = C.BLOOD_GROUND_SATELLITE_SIZE

    local horiz = Vector3.new(shotDir.X, 0, shotDir.Z)
    horiz = horiz.Magnitude > 1e-3 and horiz.Unit or Vector3.zero
    local origins = {
        position,
        position + horiz * (1.5 + 3 * intensity),
    }
    for _, org in ipairs(origins) do
        local r = workspace:Raycast(org + Vector3.new(0, 0.25, 0), Vector3.new(0, -gRange, 0), groundParams)
        if r ~= nil then
            local up = r.Normal
            local right, look = basisFor(up)
            local size = (gMin + math.random() * (gMax - gMin)) * (0.6 + 0.7 * intensity)
            pushRecord(marks, C.BLOOD_MAX_MARKS,
                makeFlatMark(CFrame.fromMatrix(r.Position + up * THICK, right, up, look), size, nil),
                C.BLOOD_MARK_LIFETIME)
            for _ = 1, gSats do
                local off = right * ((math.random() - 0.5) * 2 * gSatRange)
                    + look * ((math.random() - 0.5) * 2 * gSatRange)
                pushRecord(marks, C.BLOOD_MAX_MARKS,
                    makeFlatMark(
                        CFrame.fromMatrix(r.Position + off + up * THICK, right, up, look),
                        gSatSize * (0.35 + math.random() * 0.65),
                        nil
                    ),
                    C.BLOOD_MARK_LIFETIME)
            end
        end
    end
end

local function clearAll()
    for _, m in ipairs(marks) do
        m.part:Destroy()
    end
    table.clear(marks)
    for _, m in ipairs(bodyFx) do
        m.part:Destroy()
    end
    table.clear(bodyFx)
    for _, b in ipairs(bursts) do
        b.mist:Clear()
        b.droplet:Clear()
        b.busy = false
    end
end

-- ============================================================
-- Loop
-- ============================================================

local FADE_IN  = Constants.BLOOD_MARK_FADE_IN :: number
local FADE_OUT = Constants.BLOOD_MARK_FADE_OUT :: number

-- Expire, fade, and (for welded body fx) drop records whose limb was destroyed.
local function sweep(list: { Mark }, now: number)
    local i = 1
    while i <= #list do
        local m = list[i]
        if m.part.Parent == nil or now >= m.expireAt then
            m.part:Destroy()
            table.remove(list, i)
        else
            local age  = now - m.bornAt
            local left = m.expireAt - now
            if age < FADE_IN then
                m.part.Transparency = m.baseT + (1 - m.baseT) * (1 - age / FADE_IN)
            elseif left < FADE_OUT then
                m.part.Transparency = m.baseT + (1 - m.baseT) * (1 - left / FADE_OUT)
            elseif m.part.Transparency ~= m.baseT then
                m.part.Transparency = m.baseT
            end
            i += 1
        end
    end
end

local function onHeartbeat()
    local now = os.clock()
    for _, b in ipairs(bursts) do
        if b.busy and now >= b.freeAt then
            b.busy = false
        end
    end
    sweep(marks, now)
    sweep(bodyFx, now)
end

-- ============================================================
-- Public
-- ============================================================

function BloodController:Start()
    if started then
        return
    end
    started = true

    buildPool()

    BloodEffect.OnClientEvent:Connect(function(position: Vector3, travelDir: Vector3, intensity: number, _damageType: string)
        if not bloodOn() then
            return
        end
        if typeof(position) ~= "Vector3" or typeof(travelDir) ~= "Vector3" or typeof(intensity) ~= "number" then
            return
        end
        local clampedIntensity = math.clamp(intensity, 0, 1)
        playBurst(position, travelDir, clampedIntensity)
        spawnBloodMarks(position, travelDir, clampedIntensity)
    end)

    ReplicatedStorage:GetAttributeChangedSignal(GLOBAL_ATTR):Connect(function()
        if not bloodOn() then
            clearAll()  -- instant cut-off when a developer disables blood
        end
    end)

    RunService.Heartbeat:Connect(onHeartbeat)

    Logger.debug("[BloodController] Ready — pool", #bursts, "| mark cap", Constants.BLOOD_MAX_MARKS)
end

return BloodController
