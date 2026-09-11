--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > AIArenaBuilder
--
-- DEVELOPER-ONLY test-map tooling, mirroring TestAreaBuilder.server.lua's own
-- patterns exactly (self-contained folder rebuild, a local makeBlock part
-- helper, Studio/RUN_IN_PUBLISHED gating) but as a SEPARATE arena: on server
-- start it (re)builds Workspace/<Constants.AI_ARENA.FOLDER_NAME> — walls,
-- scattered cover, and a small stepped structure — so two opposing AI
-- factions (see Constants.AI_FACTIONS) can be watched fighting each other
-- instead of just the player.
--
-- This script ONLY builds geometry. It never spawns AI and never calls into
-- AIService — AIService.server.lua is a Script, not a requirable ModuleScript
-- (see default.project.json), so there is no direct call between the two;
-- AIService's own auto-spawn-battle system (gated by the same
-- Constants.AI_ARENA table, see AIService.server.lua's "AI arena / factions"
-- section) independently computes the same two spawn positions from these
-- constants and spawns/watches the battle itself. The two scripts share a
-- Constants contract, not a function call — the same relationship
-- TestAreaBuilder already has with AIService today (it builds
-- Workspace/AISpawns parts; AIService discovers them independently).
--
-- Not a gameplay system on its own: no RemoteEvents, no per-frame loops, no
-- RBXScriptConnections, no combat/damage logic of its own.
--
-- Guards: does nothing unless Constants.AI_ARENA.ENABLED == true AND it is
-- allowed to run here — always in Studio, and in a published server only when
-- Constants.AI_ARENA.RUN_IN_PUBLISHED == true.
--
-- Safe to re-run (stop/start Play Solo): destroys ONLY the one folder it owns
-- (found-and-destroyed by name, same as TestAreaBuilder's own root) and
-- rebuilds it. Touches nothing else in Workspace.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local CFG = Constants.AI_ARENA :: any
local FACTIONS = Constants.AI_FACTIONS :: any

-- ── Guards ───────────────────────────────────────────────────────────────────
if CFG == nil or CFG.ENABLED ~= true then
    Logger.debug("[AIArenaBuilder] skipped — Constants.AI_ARENA.ENABLED is not true")
    return
end
if not RunService:IsStudio() and CFG.RUN_IN_PUBLISHED ~= true then
    Logger.debug("[AIArenaBuilder] skipped — not in Studio and AI_ARENA.RUN_IN_PUBLISHED is not true")
    return
end

-- ── Layout constants derived from Constants.AI_ARENA ───────────────────────────
local FOLDER_NAME: string = CFG.FOLDER_NAME
local ORIGIN: Vector3     = CFG.ORIGIN
-- Top surface of the baseplate — every ground-level prop sits on this local Y.
local GROUND_TOP: number = CFG.BASEPLATE_POSITION.Y + CFG.BASEPLATE_SIZE.Y / 2

-- World position = ORIGIN + local offset — keeps the whole arena relocatable
-- from that one constant, same convention as TestAreaBuilder's own `place`.
local function place(v: Vector3): Vector3
    return ORIGIN + v
end

-- ── Part helper (deliberate small duplication of TestAreaBuilder's own
-- makeBlock — this file is intentionally independent of it; see the header
-- comment. Same precedent as AIService's Stage 1C weapon-attach code
-- duplicating WorldWeaponService's, already noted in TECHNICAL_DEBT.) ────────
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

-- ── Perimeter walls ──────────────────────────────────────────────────────────
local function buildPerimeterWalls(root: Folder): ()
    local f = makeFolder("PerimeterWalls", root)
    local size: Vector3 = CFG.BASEPLATE_SIZE
    local halfX, halfZ = size.X / 2, size.Z / 2
    local thickness: number = CFG.WALL_THICKNESS
    local height: number    = CFG.WALL_HEIGHT
    local wallY = GROUND_TOP + height / 2
    local wallColor = Color3.fromRGB(110, 112, 118)

    makeBlock({ name = "Wall_North", size = Vector3.new(size.X, height, thickness),
        cframe = CFrame.new(place(Vector3.new(0, wallY, halfZ - thickness / 2))), color = wallColor, parent = f })
    makeBlock({ name = "Wall_South", size = Vector3.new(size.X, height, thickness),
        cframe = CFrame.new(place(Vector3.new(0, wallY, -halfZ + thickness / 2))), color = wallColor, parent = f })
    makeBlock({ name = "Wall_East", size = Vector3.new(thickness, height, size.Z),
        cframe = CFrame.new(place(Vector3.new(halfX - thickness / 2, wallY, 0))), color = wallColor, parent = f })
    makeBlock({ name = "Wall_West", size = Vector3.new(thickness, height, size.Z),
        cframe = CFrame.new(place(Vector3.new(-halfX + thickness / 2, wallY, 0))), color = wallColor, parent = f })
end

-- ── Spawn markers (purely visual — AIService reads AI_ARENA.RED/BLUE_SPAWN_POSITION
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

    marker("RedSpawnMarker", redPos, (FACTIONS.ARENA_RED :: any).BODY_COLOR)
    marker("BlueSpawnMarker", bluePos, (FACTIONS.ARENA_BLUE :: any).BODY_COLOR)
end

-- ── Scattered cover — hand-placed, asymmetric (not a symmetric corridor) so
-- squads must actually maneuver around it, not just walk a straight lane.
-- Hardcoded here rather than as individual Constants.lua fields, same
-- convention TestAreaBuilder already uses for its own Stairs/DropTest shapes.
local function buildCoverScatter(root: Folder): ()
    local f = makeFolder("Cover", root)
    local coverColor = Color3.fromRGB(130, 128, 118)

    -- { x, z, width, height, rotationDegrees }
    local specs = {
        { -40, -30, 10, 6, 0 },
        { 20, -25, 6, 7, 25 },
        { -10, -10, 14, 5, 90 },
        { 45, -5, 8, 6, -15 },
        { -55, 10, 6, 8, 10 },
        { 5, 15, 10, 6, 60 },
        { -25, 30, 8, 5, -40 },
        { 50, 35, 6, 7, 20 },
        { -60, -45, 5, 6, 0 },
        { 60, 45, 5, 6, 0 },
    }

    for i, spec in ipairs(specs) do
        local x, z, width, height, rot = spec[1], spec[2], spec[3], spec[4], spec[5]
        makeBlock({
            name = "Cover_" .. tostring(i),
            size = Vector3.new(width, height, 2),
            cframe = CFrame.new(place(Vector3.new(x, GROUND_TOP + height / 2, z))) * CFrame.Angles(0, math.rad(rot), 0),
            color = coverColor,
            material = Enum.Material.Concrete,
            parent = f,
        })
    end
end

-- ── One small stepped structure for visual variety and a modest elevated
-- position — plain stacked blocks (no ramp math needed), each riser only 2
-- studs so a Humanoid walks it without jumping; AI has no vault/climb (see
-- docs/TECHNICAL_DEBT.md), so every riser here stays walkable, not a ledge.
local function buildStructure(root: Folder): ()
    local f = makeFolder("Structure", root)
    local structColor = Color3.fromRGB(150, 140, 120)

    local steps = {
        { z = 4, y = 1, height = 2 },
        { z = 8, y = 3, height = 2 },
        { z = 12, y = 5, height = 2 },
    }
    for i, step in ipairs(steps) do
        makeBlock({
            name = "Step_" .. tostring(i),
            size = Vector3.new(16, step.height, 4),
            cframe = CFrame.new(place(Vector3.new(0, GROUND_TOP + step.y, step.z))),
            color = structColor,
            material = Enum.Material.WoodPlanks,
            parent = f,
        })
    end
    makeBlock({
        name = "Platform",
        size = Vector3.new(16, 1, 16),
        cframe = CFrame.new(place(Vector3.new(0, GROUND_TOP + 6.5, 20))),
        color = structColor,
        material = Enum.Material.WoodPlanks,
        parent = f,
    })
end

-- ── Build ───────────────────────────────────────────────────────────────────
local existing = workspace:FindFirstChild(FOLDER_NAME)
if existing ~= nil then
    if not existing:IsA("Folder") then
        Logger.warn("[AIArenaBuilder] Workspace." .. FOLDER_NAME .. " existed as a "
            .. existing.ClassName .. ", not a Folder — replacing it")
    end
    existing:Destroy()
end

local root = Instance.new("Folder")
root.Name = FOLDER_NAME

buildBaseplate(root)
buildPerimeterWalls(root)
buildSpawnMarkers(root)
buildCoverScatter(root)
buildStructure(root)

root.Parent = workspace

Logger.debug("[AIArenaBuilder] built Workspace." .. FOLDER_NAME .. " — " .. tostring(#root:GetDescendants()) .. " instances")
