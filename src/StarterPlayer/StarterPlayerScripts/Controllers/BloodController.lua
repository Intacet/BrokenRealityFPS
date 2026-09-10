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
local marks: { Mark } = {}          -- ring buffer, oldest first (all share one lifetime)

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
-- Surface marks
-- ============================================================

local function retireOldestMark()
    local m = table.remove(marks, 1)
    if m ~= nil then
        m.part:Destroy()
    end
end

-- cf: surface-flat CFrame (Y = surface normal). size: nominal footprint (studs).
local function addMark(cf: CFrame, size: number)
    if #marks >= (Constants.BLOOD_MAX_MARKS :: number) then
        retireOldestMark()
    end

    local now  = os.clock()
    local tMin: number = C.BLOOD_MARK_TRANSPARENCY_MIN
    local tMax: number = C.BLOOD_MARK_TRANSPARENCY_MAX
    local baseT = tMin + math.random() * (tMax - tMin)

    local part = Instance.new("Part")
    part.Name          = "BloodMark"
    -- Irregular footprint so it does not read as a red tile.
    part.Size          = Vector3.new(
        size * (0.72 + math.random() * 0.56),
        Constants.BLOOD_MARK_THICKNESS :: number,
        size * (0.72 + math.random() * 0.56)
    )
    part.CFrame        = cf
    part.Anchored      = true
    part.CanCollide    = false
    part.CanQuery      = false
    part.CanTouch      = false
    part.CastShadow    = false
    part.Locked        = true
    part.Material      = Enum.Material.SmoothPlastic
    part.Color         = BLOOD_COLOR:Lerp(BLOOD_DARK, math.random() * 0.65)
    part.Transparency  = 1    -- fades in via onHeartbeat
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent        = fxFolder

    table.insert(marks, {
        part = part,
        bornAt = now,
        expireAt = now + (Constants.BLOOD_MARK_LIFETIME :: number),
        baseT = baseT,
    })
end

local function spawnMarks(position: Vector3, travelDir: Vector3, intensity: number)
    local rays  = Constants.BLOOD_SPLATTER_RAYS :: number
    local range = Constants.BLOOD_SPLATTER_RANGE :: number
    local sMin  = Constants.BLOOD_MARK_SIZE_MIN :: number
    local sMax  = Constants.BLOOD_MARK_SIZE_MAX :: number
    local thick = Constants.BLOOD_MARK_THICKNESS :: number
    local sats  = Constants.BLOOD_MARK_SATELLITES :: number
    local satRange = Constants.BLOOD_MARK_SATELLITE_RANGE :: number
    local satSize  = Constants.BLOOD_MARK_SATELLITE_SIZE :: number

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { fxFolder }
    params.IgnoreWater = true
    params.RespectCanCollide = true

    local fwd = travelDir.Magnitude > 1e-3 and travelDir.Unit or Vector3.new(0, -1, 0)

    for i = 1, rays do
        local dir: Vector3
        if i == 1 then
            dir = fwd                                   -- the surface directly behind the hit
        elseif i == 2 then
            dir = Vector3.new(0, -1, 0)                 -- the floor below (pooling)
        else
            -- Biased toward the exit direction and downward, not fully random.
            local jitter = Vector3.new(
                (math.random() - 0.5) * 2,
                -math.random(),
                (math.random() - 0.5) * 2
            )
            dir = (fwd * 0.55 + jitter * 0.45)
            dir = dir.Magnitude > 1e-3 and dir.Unit or Vector3.new(0, -1, 0)
        end

        local result = workspace:Raycast(position, dir * range, params)
        if result ~= nil then
            local up = result.Normal
            local baseRight = up:Cross(Vector3.xAxis)
            if baseRight.Magnitude < 1e-3 then
                baseRight = up:Cross(Vector3.zAxis)
            end
            baseRight = baseRight.Unit
            local ang = math.random() * math.pi * 2
            local right = (baseRight * math.cos(ang) + up:Cross(baseRight) * math.sin(ang)).Unit
            local look = right:Cross(up).Unit

            local size = math.clamp(sMin + math.random() * (sMax - sMin), sMin, sMax)
                * (0.55 + 0.55 * intensity)
            addMark(CFrame.fromMatrix(result.Position + up * thick, right, up, look), size)

            -- A few tiny satellite spots scattered across the same surface plane.
            for _ = 1, sats do
                local off = right * ((math.random() - 0.5) * 2 * satRange)
                    + look * ((math.random() - 0.5) * 2 * satRange)
                addMark(
                    CFrame.fromMatrix(result.Position + off + up * thick, right, up, look),
                    satSize * (0.35 + math.random() * 0.65)
                )
            end
        end
    end
end

local function clearAll()
    for _, m in ipairs(marks) do
        m.part:Destroy()
    end
    table.clear(marks)
    for _, b in ipairs(bursts) do
        b.mist:Clear()
        b.droplet:Clear()
        b.busy = false
    end
end

-- ============================================================
-- Loop
-- ============================================================

local function onHeartbeat()
    local now = os.clock()

    for _, b in ipairs(bursts) do
        if b.busy and now >= b.freeAt then
            b.busy = false
        end
    end

    -- marks is oldest-first; expired ones are always at the front.
    while #marks > 0 and now >= marks[1].expireAt do
        retireOldestMark()
    end

    -- Fade marks in on birth and out at end of life; hold flat opacity in between.
    local fadeIn  = Constants.BLOOD_MARK_FADE_IN :: number
    local fadeOut = Constants.BLOOD_MARK_FADE_OUT :: number
    for _, m in ipairs(marks) do
        local age  = now - m.bornAt
        local left = m.expireAt - now
        if age < fadeIn then
            m.part.Transparency = m.baseT + (1 - m.baseT) * (1 - age / fadeIn)
        elseif left < fadeOut then
            m.part.Transparency = m.baseT + (1 - m.baseT) * (1 - left / fadeOut)
        elseif m.part.Transparency ~= m.baseT then
            m.part.Transparency = m.baseT
        end
    end
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
        spawnMarks(position, travelDir, clampedIntensity)
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
