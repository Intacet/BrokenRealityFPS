--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > AIArenaCorridorBuilder
--
-- DEVELOPER-ONLY test-map tooling, mirroring AIArenaBuilder.server.lua's own
-- patterns exactly (self-contained folder rebuild, a local makeBlock part
-- helper, Studio/RUN_IN_PUBLISHED gating): on server start it (re)builds
-- Workspace/<Constants.AI_ARENA_2.FOLDER_NAME> — a SECOND, separate AI arena
-- alongside the first one, laid out to a user-sketched design: an elongated
-- room with solid north/south walls, open east/west ends as the two team
-- entrances, two tall "high wall" segments blocking the centerline (with a
-- gap between them as a crossing lane), shorter "low cover" segments flanking
-- them on both sides, and one L-shaped elevated platform + staircase near
-- each entrance (south side near the west/red entrance, north side near the
-- east/blue entrance — a 180°-rotationally-symmetric layout, fair to both
-- teams) for a grunt to climb up and shoot down from.
--
-- This script ONLY builds geometry. It never spawns AI and never calls into
-- AIService — AIService.server.lua is a Script, not a requirable ModuleScript
-- (see default.project.json), so there is no direct call between the two;
-- AIService's own auto-spawn-battle system (gated by the same
-- Constants.AI_ARENA_2 table, see AIService.server.lua's "AI arena / factions"
-- section) independently computes the same two spawn positions from these
-- constants and spawns/watches its own ARENA2_RED vs ARENA2_BLUE battle. The
-- two scripts share a Constants contract, not a function call — the same
-- relationship AIArenaBuilder already has with AIService for the first arena.
--
-- Not a gameplay system on its own: no RemoteEvents, no per-frame loops, no
-- RBXScriptConnections, no combat/damage logic of its own.
--
-- Guards: does nothing unless Constants.AI_ARENA_2.ENABLED == true AND it is
-- allowed to run here — always in Studio, and in a published server only when
-- Constants.AI_ARENA_2.RUN_IN_PUBLISHED == true.
--
-- Safe to re-run (stop/start Play Solo): destroys ONLY the one folder it owns
-- (found-and-destroyed by name, same as every other builder's own root) and
-- rebuilds it. Touches nothing else in Workspace.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local CFG = Constants.AI_ARENA_2 :: any
local FACTIONS = Constants.AI_FACTIONS :: any

-- ── Guards ───────────────────────────────────────────────────────────────────
if CFG == nil or CFG.ENABLED ~= true then
    Logger.debug("[AIArenaCorridorBuilder] skipped — Constants.AI_ARENA_2.ENABLED is not true")
    return
end
if not RunService:IsStudio() and CFG.RUN_IN_PUBLISHED ~= true then
    Logger.debug("[AIArenaCorridorBuilder] skipped — not in Studio and AI_ARENA_2.RUN_IN_PUBLISHED is not true")
    return
end

-- ── Layout constants derived from Constants.AI_ARENA_2 ─────────────────────────
local FOLDER_NAME: string = CFG.FOLDER_NAME
local ORIGIN: Vector3     = CFG.ORIGIN
local GROUND_TOP: number  = CFG.BASEPLATE_POSITION.Y + CFG.BASEPLATE_SIZE.Y / 2

-- World position = ORIGIN + local offset — keeps the whole arena relocatable
-- from that one constant, same convention every other builder in this project
-- uses. Local convention here: +X = east (blue side), -X = west (red side),
-- +Z = south, -Z = north.
local function place(v: Vector3): Vector3
    return ORIGIN + v
end

-- ── Part helper (deliberate small duplication of AIArenaBuilder's own
-- makeBlock — this file is intentionally independent of it, same precedent
-- as Stage 1C's AI weapon-attach code duplicating WorldWeaponService's,
-- already noted in TECHNICAL_DEBT.) ─────────────────────────────────────────
type BlockSpec = {
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3?,
    material: Enum.Material?,
    canCollide: boolean?,
    parent: Instance,
}

local function makeBlock(spec: BlockSpec): BasePart
    assert(type(spec) == "table", "makeBlock: spec must be a table")
    assert(type(spec.name) == "string", "makeBlock: spec.name must be a string")
    assert(typeof(spec.size) == "Vector3", "makeBlock: spec.size must be a Vector3")
    assert(typeof(spec.cframe) == "CFrame", "makeBlock: spec.cframe must be a CFrame")
    assert(typeof(spec.parent) == "Instance", "makeBlock: spec.parent must be an Instance")

    local part = Instance.new("Part")
    part.Name          = spec.name
    part.Size          = spec.size
    part.CFrame        = spec.cframe
    part.Anchored      = true
    part.CanCollide    = if spec.canCollide == nil then true else spec.canCollide
    part.Color         = spec.color or Color3.fromRGB(150, 150, 150)
    part.Material      = spec.material or Enum.Material.SmoothPlastic
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent        = spec.parent
    return part
end

local function makeFolder(name: string, parent: Instance): Folder
    local f = Instance.new("Folder")
    f.Name   = name
    f.Parent = parent
    return f
end

-- ── Baseplate ────────────────────────────────────────────────────────────────
local function buildBaseplate(root: Folder): ()
    makeBlock({
        name   = "Baseplate",
        size   = CFG.BASEPLATE_SIZE,
        cframe = CFrame.new(place(CFG.BASEPLATE_POSITION)),
        color  = Color3.fromRGB(70, 72, 76),
        material = Enum.Material.Concrete,
        parent = root,
    })
end

-- ── Perimeter walls — north/south only; east/west stay open as the two team
-- entrances (the "shaped like this" sketch's left/right gaps). ─────────────
local function buildPerimeterWalls(root: Folder): ()
    local f = makeFolder("PerimeterWalls", root)
    local xMin: number, xMax: number = CFG.WALL_X_MIN, CFG.WALL_X_MAX
    local z: number = CFG.WALL_Z
    local height: number, thickness: number = CFG.WALL_HEIGHT, CFG.WALL_THICKNESS
    local wallY = GROUND_TOP + height / 2
    local length = xMax - xMin
    local color = Color3.fromRGB(110, 112, 118)

    makeBlock({ name = "Wall_North", size = Vector3.new(length, height, thickness),
        cframe = CFrame.new(place(Vector3.new((xMin + xMax) / 2, wallY, -z))), color = color, parent = f })
    makeBlock({ name = "Wall_South", size = Vector3.new(length, height, thickness),
        cframe = CFrame.new(place(Vector3.new((xMin + xMax) / 2, wallY, z))), color = color, parent = f })
end

-- ── The two "high walls" down the centerline, split with a crossing gap ─────
local function buildCenterWalls(root: Folder): ()
    local f = makeFolder("CenterWalls", root)
    local height: number, thickness: number = CFG.CENTER_WALL_HEIGHT, CFG.CENTER_WALL_THICKNESS
    local zInner: number, zOuter: number = CFG.CENTER_WALL_Z_INNER, CFG.CENTER_WALL_Z_OUTER
    local wallY = GROUND_TOP + height / 2
    local length = zOuter - zInner
    local color = Color3.fromRGB(90, 92, 98)

    makeBlock({ name = "CenterWall_North", size = Vector3.new(thickness, height, length),
        cframe = CFrame.new(place(Vector3.new(0, wallY, -(zInner + zOuter) / 2))), color = color, parent = f })
    makeBlock({ name = "CenterWall_South", size = Vector3.new(thickness, height, length),
        cframe = CFrame.new(place(Vector3.new(0, wallY, (zInner + zOuter) / 2))), color = color, parent = f })
end

-- ── Shorter "low cover" segments flanking the center walls on both sides ────
local function buildFlankingCover(root: Folder): ()
    local f = makeFolder("FlankingCover", root)
    local height: number, thickness: number = CFG.COVER_HEIGHT, CFG.COVER_THICKNESS
    local x: number = CFG.COVER_X
    local zInner: number, zOuter: number = CFG.COVER_Z_INNER, CFG.COVER_Z_OUTER
    local coverY = GROUND_TOP + height / 2
    local length = zOuter - zInner
    local color = Color3.fromRGB(130, 128, 118)

    for _, side in ipairs({ { tag = "West", x = -x }, { tag = "East", x = x } }) do
        makeBlock({ name = "Cover_" .. side.tag .. "_North",
            size = Vector3.new(thickness, height, length),
            cframe = CFrame.new(place(Vector3.new(side.x, coverY, -(zInner + zOuter) / 2))),
            color = color, material = Enum.Material.Concrete, parent = f })
        makeBlock({ name = "Cover_" .. side.tag .. "_South",
            size = Vector3.new(thickness, height, length),
            cframe = CFrame.new(place(Vector3.new(side.x, coverY, (zInner + zOuter) / 2))),
            color = color, material = Enum.Material.Concrete, parent = f })
    end
end

-- ── Spawn markers (purely visual — AIService reads AI_ARENA_2.RED/BLUE_SPAWN_POSITION
-- directly, not these parts; they just show where each faction spawns in) ──────
local function buildSpawnMarkers(root: Folder): ()
    local f = makeFolder("SpawnMarkers", root)
    local markerSize = Vector3.new(6, 0.4, 6)
    local redPos: Vector3  = CFG.RED_SPAWN_POSITION
    local bluePos: Vector3 = CFG.BLUE_SPAWN_POSITION

    local function marker(name: string, pos: Vector3, color: Color3)
        local m = makeBlock({
            name = name,
            size = markerSize,
            cframe = CFrame.new(place(Vector3.new(pos.X, GROUND_TOP + markerSize.Y / 2, pos.Z))),
            color = color,
            material = Enum.Material.Neon,
            canCollide = false,
            parent = f,
        })
        m.CastShadow = false
    end

    marker("RedSpawnMarker", redPos, (FACTIONS.ARENA2_RED :: any).BODY_COLOR)
    marker("BlueSpawnMarker", bluePos, (FACTIONS.ARENA2_BLUE :: any).BODY_COLOR)
end

-- ── L-shaped platform + staircase near each entrance. Hardcoded per-side
-- specs (same convention as AIArenaBuilder's own hardcoded cover scatter /
-- stepped structure) rather than a dozen more Constants fields — only the
-- important tunables (PLATFORM_HEIGHT, STEP_RISE, STEP_COUNT) live in
-- Constants.lua. `xSign`/`zSign` place the SAME shape on either corner:
-- (-1, +1) = south-west (red, near the west entrance, on its "right" as it
-- walks in east); (+1, -1) = north-east (blue, near the east entrance, on
-- its "right" as it walks in west) — a 180° rotation of one another, so both
-- teams get an identical, fair structure.
local function buildStairPlatform(root: Folder, name: string, xSign: number, zSign: number, color: Color3): ()
    local f = makeFolder(name, root)
    local platformY = GROUND_TOP + CFG.PLATFORM_HEIGHT

    -- Two overlapping arms forming an L in plan view.
    makeBlock({ name = "PlatformArmA", size = Vector3.new(26, 1, 14),
        cframe = CFrame.new(place(Vector3.new(xSign * 85, platformY, zSign * 45))),
        color = color, parent = f })
    makeBlock({ name = "PlatformArmB", size = Vector3.new(14, 1, 34),
        cframe = CFrame.new(place(Vector3.new(xSign * 91, platformY, zSign * 35))),
        color = color, parent = f })

    -- Three steps ascending from the crossing lane up to ArmB's inner edge.
    for i = 1, CFG.STEP_COUNT :: number do
        local riseTop = i * (CFG.STEP_RISE :: number)
        local riseCenter = GROUND_TOP + riseTop - (CFG.STEP_RISE :: number) / 2
        local zCenter = zSign * (2 + 4 * i)
        makeBlock({
            name = "Step_" .. tostring(i),
            size = Vector3.new(10, CFG.STEP_RISE :: number, 4),
            cframe = CFrame.new(place(Vector3.new(xSign * 91, riseCenter, zCenter))),
            color = color,
            material = Enum.Material.WoodPlanks,
            parent = f,
        })
    end
end

-- ── Build ───────────────────────────────────────────────────────────────────
local existing = workspace:FindFirstChild(FOLDER_NAME)
if existing ~= nil then
    if not existing:IsA("Folder") then
        Logger.warn("[AIArenaCorridorBuilder] Workspace." .. FOLDER_NAME .. " existed as a "
            .. existing.ClassName .. ", not a Folder — replacing it")
    end
    existing:Destroy()
end

local root = Instance.new("Folder")
root.Name = FOLDER_NAME

buildBaseplate(root)
buildPerimeterWalls(root)
buildCenterWalls(root)
buildFlankingCover(root)
buildSpawnMarkers(root)
buildStairPlatform(root, "RedPlatform", -1, 1, (FACTIONS.ARENA2_RED :: any).BODY_COLOR)
buildStairPlatform(root, "BluePlatform", 1, -1, (FACTIONS.ARENA2_BLUE :: any).BODY_COLOR)

root.Parent = workspace

Logger.debug("[AIArenaCorridorBuilder] built Workspace." .. FOLDER_NAME .. " — " .. tostring(#root:GetDescendants()) .. " instances")
