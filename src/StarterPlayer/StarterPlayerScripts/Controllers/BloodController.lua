--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > BloodController
--
-- Client-side blood visuals. Reproduces a short particle burst and a few surface marks
-- from the data the server sends on BloodEffect { hitPosition, hitDirection, intensity,
-- damageType }. The server never creates an instance — every particle and mark lives and
-- dies here, under hard caps.
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

local BloodController = {}

-- ============================================================
-- State
-- ============================================================

local fxFolder: Folder

type Burst = { part: BasePart, emitter: ParticleEmitter, freeAt: number, busy: boolean }
local bursts: { Burst } = {}

type Mark = { part: BasePart, expireAt: number }
local marks: { Mark } = {}          -- ring buffer, oldest first

local started = false

-- ============================================================
-- Helpers
-- ============================================================

local function bloodOn(): boolean
    return ReplicatedStorage:GetAttribute(GLOBAL_ATTR) ~= false
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
        part.Parent       = fxFolder

        local emitter = Instance.new("ParticleEmitter")
        emitter.Enabled      = false
        emitter.Rate         = 0
        emitter.Color        = ColorSequence.new(BLOOD_COLOR)
        emitter.Size         = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.35),
            NumberSequenceKeypoint.new(1, 0.05),
        })
        emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        })
        emitter.Lifetime     = NumberRange.new(0.25, 0.55)
        emitter.Speed        = NumberRange.new(9, 20)
        emitter.SpreadAngle  = Vector2.new(28, 28)
        emitter.Acceleration = Vector3.new(0, -90, 0)
        emitter.Drag         = 3
        emitter.LightEmission = 0
        emitter.Parent       = part

        table.insert(bursts, { part = part, emitter = emitter, freeAt = 0, busy = false })
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
    -- Spray back toward where the shot came from, plus the emitter's own spread.
    local sprayDir = (-travelDir)
    if sprayDir.Magnitude < 1e-3 then
        sprayDir = Vector3.yAxis
    end
    b.part.CFrame = CFrame.lookAt(position, position + sprayDir.Unit)
    local count = (Constants.BLOOD_PARTICLES_BASE :: number)
        + math.round(intensity * (Constants.BLOOD_PARTICLES_PER_INTENSITY :: number))
    b.emitter:Emit(count)
    b.busy   = true
    b.freeAt = os.clock() + (Constants.BLOOD_BURST_LIFETIME :: number)
end

local function retireOldestMark()
    local m = table.remove(marks, 1)
    if m ~= nil then
        m.part:Destroy()
    end
end

local function addMark(cf: CFrame, size: number)
    if #marks >= (Constants.BLOOD_MAX_MARKS :: number) then
        retireOldestMark()
    end
    local part = Instance.new("Part")
    part.Name         = "BloodMark"
    part.Size         = Vector3.new(size, Constants.BLOOD_MARK_THICKNESS :: number, size)
    part.CFrame       = cf
    part.Anchored     = true
    part.CanCollide   = false
    part.CanQuery     = false
    part.CanTouch     = false
    part.CastShadow   = false
    part.Material     = Enum.Material.SmoothPlastic
    part.Color        = BLOOD_COLOR
    part.Transparency = 0.15
    part.TopSurface   = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent       = fxFolder

    table.insert(marks, { part = part, expireAt = os.clock() + (Constants.BLOOD_MARK_LIFETIME :: number) })
end

local function spawnMarks(position: Vector3, travelDir: Vector3, intensity: number)
    local rays  = Constants.BLOOD_SPLATTER_RAYS :: number
    local range = Constants.BLOOD_SPLATTER_RANGE :: number
    local sMin  = Constants.BLOOD_MARK_SIZE_MIN :: number
    local sMax  = Constants.BLOOD_MARK_SIZE_MAX :: number

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { fxFolder }
    params.IgnoreWater = true
    params.RespectCanCollide = true

    for i = 1, rays do
        local dir: Vector3
        if i == 1 and travelDir.Magnitude > 1e-3 then
            dir = travelDir.Unit                          -- the wall directly behind the hit
        else
            dir = Vector3.new(
                (math.random() - 0.5) * 2,
                (math.random() - 0.5) * 2,
                (math.random() - 0.5) * 2
            )
            if dir.Magnitude < 1e-3 then dir = Vector3.yAxis end
            dir = dir.Unit
        end

        local result = workspace:Raycast(position, dir * range, params)
        if result ~= nil then
            local size = math.clamp(sMin + math.random() * (sMax - sMin), sMin, sMax)
                * (0.5 + 0.5 * intensity)
            local up = result.Normal
            local right = up:Cross(Vector3.xAxis)
            if right.Magnitude < 1e-3 then right = up:Cross(Vector3.zAxis) end
            right = right.Unit
            local look = right:Cross(up).Unit
            local cf = CFrame.fromMatrix(
                result.Position + up * (Constants.BLOOD_MARK_THICKNESS :: number),
                right, up, look
            )
            addMark(cf, size)
        end
    end
end

local function clearAll()
    for _, m in ipairs(marks) do
        m.part:Destroy()
    end
    table.clear(marks)
    for _, b in ipairs(bursts) do
        b.emitter:Clear()
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
