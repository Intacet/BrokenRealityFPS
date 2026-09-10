--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > TestAreaBuilder
--
-- DEVELOPER-ONLY test-map tooling. On server start, in Studio only, (re)builds
-- Workspace/<Constants.DEV_TEST_AREA.FOLDER_NAME> — a self-contained sandbox for
-- quickly testing movement, weapon feel, first-person viewmodels, muzzle flash /
-- smoke, bullet impacts, reload timing, vaulting, crouch, sprint and landing drops.
--
-- This is NOT a gameplay system:
--   * No RemoteEvents / RemoteFunctions.
--   * No combat / damage / ammo / movement / camera / viewmodel logic.
--   * No per-frame loops, no RBXScriptConnections.
--   * game.Lighting is never touched — the lighting section is self-contained props
--     (Part + PointLight/SpotLight) that vanish with the folder.
--
-- Guards: does nothing unless RunService:IsStudio() AND
-- Constants.DEV_TEST_AREA.ENABLED == true.
--
-- Safe to re-run (stop/start Play Solo): it destroys ONLY the one folder it owns and
-- rebuilds it. Unrelated Workspace content is never read or modified.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local CFG = Constants.DEV_TEST_AREA :: any

-- ── Guards ───────────────────────────────────────────────────────────────────
if not RunService:IsStudio() then
	return
end
if CFG == nil or CFG.ENABLED ~= true then
	Logger.debug("[TestAreaBuilder] skipped — Constants.DEV_TEST_AREA.ENABLED is not true")
	return
end

-- ── Layout constants derived from Constants.DEV_TEST_AREA ─────────────────────
local FOLDER_NAME: string = CFG.FOLDER_NAME
local ORIGIN: Vector3     = CFG.ORIGIN
-- Top surface of the baseplate — every ground-level prop sits on this Y.
local GROUND_TOP: number  = CFG.BASEPLATE_POSITION.Y + CFG.BASEPLATE_SIZE.Y / 2
local LABEL_LIFT: number  = 3 -- studs a section label floats above its prop
local labelsEnabled: boolean = CFG.DEBUG_LABELS == true

-- World position = ORIGIN + local offset. ORIGIN is (0,0,0) today; going through this
-- keeps the whole area relocatable from one constant.
local function place(v: Vector3): Vector3
	return ORIGIN + v
end

-- ── Part / folder / label helpers ───────────────────────────────────────────
type BlockSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	castShadow: boolean?,
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
	part.CastShadow    = spec.castShadow == true
	part.Color         = spec.color or Color3.fromRGB(150, 150, 150)
	part.Material      = spec.material or Enum.Material.SmoothPlastic
	part.Transparency  = spec.transparency or 0
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent        = spec.parent
	return part
end

local function makeFolder(name: string, parent: Instance): Folder
	assert(type(name) == "string", "makeFolder: name must be a string")
	assert(typeof(parent) == "Instance", "makeFolder: parent must be an Instance")
	local f = Instance.new("Folder")
	f.Name   = name
	f.Parent = parent
	return f
end

-- BillboardGui text tag above a section. No-op when DEBUG_LABELS is false.
local function makeLabel(text: string, worldPos: Vector3, parent: Instance): ()
	assert(type(text) == "string", "makeLabel: text must be a string")
	assert(typeof(worldPos) == "Vector3", "makeLabel: worldPos must be a Vector3")
	assert(typeof(parent) == "Instance", "makeLabel: parent must be an Instance")
	if not labelsEnabled then
		return
	end

	local safe = (text:gsub("%W+", "_"))
	local anchor = Instance.new("Part")
	anchor.Name         = "Label_" .. safe
	anchor.Size         = Vector3.new(0.4, 0.4, 0.4)
	anchor.Transparency = 1
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CastShadow   = false
	anchor.CFrame       = CFrame.new(worldPos)
	anchor.Parent       = parent

	local gui = Instance.new("BillboardGui")
	gui.Name           = "Label"
	gui.Size           = UDim2.fromOffset(240, 46)
	gui.AlwaysOnTop    = true
	gui.LightInfluence = 0
	gui.MaxDistance    = 320
	gui.Parent         = anchor

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.BorderSizePixel        = 0
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.Font                   = Enum.Font.GothamMedium
	label.TextScaled             = true
	label.Text                   = text
	label.Parent                 = gui
end

-- ── Composite prop helpers (shared shapes) ──────────────────────────────────
-- A ground-standing bar of a fixed height — used for the three vault obstacles.
local function buildVaultBar(name: string, labelText: string, height: number, xz: Vector3, parent: Instance): ()
	assert(type(height) == "number", "buildVaultBar: height must be a number")
	assert(typeof(xz) == "Vector3", "buildVaultBar: xz must be a Vector3")
	makeBlock({
		name = name,
		size = Vector3.new(10, height, 1),
		cframe = CFrame.new(place(Vector3.new(xz.X, GROUND_TOP + height / 2, xz.Z))),
		color = Color3.fromRGB(120, 85, 55),
		material = Enum.Material.WoodPlanks,
		parent = parent,
	})
	makeLabel(labelText, place(Vector3.new(xz.X, GROUND_TOP + height + LABEL_LIFT, xz.Z)), parent)
end

-- An elevated platform at a given height plus a walk-up ramp on its -Z side.
local function buildDropPlatform(height: number, xz: Vector3, parent: Instance): ()
	assert(type(height) == "number", "buildDropPlatform: height must be a number")
	assert(typeof(xz) == "Vector3", "buildDropPlatform: xz must be a Vector3")
	local h = tostring(height)
	local topY = GROUND_TOP + height
	makeBlock({
		name = "Platform_" .. h,
		size = Vector3.new(14, 1, 14),
		cframe = CFrame.new(place(Vector3.new(xz.X, topY, xz.Z))),
		color = Color3.fromRGB(90, 100, 115),
		material = Enum.Material.Metal,
		parent = parent,
	})
	-- Ramp: run = 3x rise for a walkable ~18 degree slope; -Z end low, +Z end at the platform.
	local run = height * 3
	local rampLen = math.sqrt(run * run + height * height)
	local pitch = math.atan2(height, run)
	makeBlock({
		name = "Ramp_" .. h,
		size = Vector3.new(6, 1, rampLen),
		cframe = CFrame.new(place(Vector3.new(xz.X, GROUND_TOP + height / 2, xz.Z - 7 - run / 2)))
			* CFrame.Angles(-pitch, 0, 0),
		color = Color3.fromRGB(70, 78, 90),
		material = Enum.Material.Metal,
		parent = parent,
	})
	makeLabel("Drop Test " .. h, place(Vector3.new(xz.X, topY + LABEL_LIFT, xz.Z)), parent)
end

-- ── Section builders ────────────────────────────────────────────────────────
local function buildBaseAndSpawn(root: Folder): ()
	makeBlock({
		name = "Baseplate",
		size = CFG.BASEPLATE_SIZE,
		cframe = CFrame.new(place(CFG.BASEPLATE_POSITION)),
		color = Color3.fromRGB(95, 95, 100),
		material = Enum.Material.Concrete,
		parent = root,
	})

	-- TestSpawn: an enabled neutral SpawnLocation raised on a dais (SPAWN_POSITION.Y is
	-- the dais centre). The live game sets Players.CharacterAutoLoads = false and teleports
	-- via TeamService, so this never hijacks the match flow; in a plain Studio playtest a
	-- character can start here. Delete the folder to remove it.
	local daisH = CFG.SPAWN_POSITION.Y * 2
	local spawn = Instance.new("SpawnLocation")
	spawn.Name                    = "TestSpawn"
	spawn.Size                    = Vector3.new(8, daisH, 8)
	spawn.CFrame                  = CFrame.new(place(Vector3.new(CFG.SPAWN_POSITION.X, GROUND_TOP + daisH / 2, CFG.SPAWN_POSITION.Z)))
	spawn.Anchored                = true
	spawn.CanCollide              = true
	spawn.Neutral                 = true
	spawn.Enabled                 = true
	spawn.Duration                = 0
	spawn.AllowTeamChangeOnTouch  = false
	spawn.Color                   = Color3.fromRGB(60, 200, 90)
	spawn.Material                = Enum.Material.SmoothPlastic
	spawn.TopSurface              = Enum.SurfaceType.Smooth
	spawn.Parent                  = root
	makeLabel("Test Start", place(Vector3.new(CFG.SPAWN_POSITION.X, GROUND_TOP + daisH + LABEL_LIFT, CFG.SPAWN_POSITION.Z)), root)
end

local function buildShootingRange(root: Folder): ()
	local f = makeFolder("ShootingRange", root)
	local start: Vector3 = CFG.SHOOTING_RANGE_START
	local tSize: Vector3 = CFG.TARGET_SIZE

	-- Firing line marker (flat, on the ground).
	makeBlock({
		name = "FiringLine",
		size = Vector3.new(36, 0.4, 3),
		cframe = CFrame.new(place(Vector3.new(start.X, GROUND_TOP + 0.2, start.Z))),
		color = Color3.fromRGB(240, 210, 60),
		material = Enum.Material.Neon,
		canCollide = false,
		parent = f,
	})
	makeLabel("Shooting Range", place(Vector3.new(start.X, GROUND_TOP + 9, start.Z)), f)

	-- Static targets down-range (+Z), each on the ground with a distance label.
	local maxDist = 0
	for _, dist: number in ipairs(CFG.TARGET_DISTANCES :: { number }) do
		if dist > maxDist then
			maxDist = dist
		end
		local centre = place(Vector3.new(start.X, GROUND_TOP + tSize.Y / 2, start.Z + dist))
		makeBlock({
			name = "Target_" .. tostring(dist),
			size = tSize,
			cframe = CFrame.new(centre),
			color = Color3.fromRGB(235, 120, 30),
			material = Enum.Material.SmoothPlastic,
			parent = f,
		})
		makeBlock({
			name = "TargetBull_" .. tostring(dist),
			size = Vector3.new(1.4, 1.4, tSize.Z + 0.1),
			cframe = CFrame.new(centre),
			color = Color3.fromRGB(250, 250, 250),
			material = Enum.Material.Neon,
			canCollide = false,
			parent = f,
		})
		makeLabel(tostring(dist) .. " studs",
			place(Vector3.new(start.X, GROUND_TOP + tSize.Y + 2, start.Z + dist)), f)
	end

	-- Backstop wall behind the farthest target.
	makeBlock({
		name = "Backstop",
		size = Vector3.new(44, 26, 2),
		cframe = CFrame.new(place(Vector3.new(start.X, GROUND_TOP + 13, start.Z + maxDist + 10))),
		color = Color3.fromRGB(55, 55, 60),
		material = Enum.Material.Concrete,
		parent = f,
	})
end

local function buildImpactWall(root: Folder): ()
	local f = makeFolder("ImpactWall", root)
	local pos: Vector3 = CFG.IMPACT_WALL_POSITION
	makeBlock({
		name = "Wall",
		size = CFG.IMPACT_WALL_SIZE,
		cframe = CFrame.new(place(pos)),
		color = Color3.fromRGB(172, 172, 178),
		material = Enum.Material.Concrete,
		parent = f,
	})
	makeLabel("Impact Wall", place(Vector3.new(pos.X, pos.Y + CFG.IMPACT_WALL_SIZE.Y / 2 + LABEL_LIFT, pos.Z)), f)
end

local function buildSprintLane(parent: Folder): ()
	local f = makeFolder("SprintLane", parent)
	local pos: Vector3 = CFG.SPRINT_LANE_POSITION
	local size: Vector3 = CFG.SPRINT_LANE_SIZE

	makeBlock({
		name = "Lane",
		size = size,
		cframe = CFrame.new(place(Vector3.new(pos.X, GROUND_TOP + size.Y / 2, pos.Z))),
		color = Color3.fromRGB(40, 42, 48),
		material = Enum.Material.Metal,
		canCollide = false,
		parent = f,
	})

	-- Distance stripes every 10 studs from the near (−Z) end, with a stud-count label.
	local nearZ = pos.Z - size.Z / 2
	local steps = math.floor(size.Z / 10)
	for i = 0, steps do
		local z = nearZ + i * 10
		makeBlock({
			name = "Marker_" .. tostring(i * 10),
			size = Vector3.new(size.X + 1, 0.25, 0.6),
			cframe = CFrame.new(place(Vector3.new(pos.X, GROUND_TOP + 0.15, z))),
			color = Color3.fromRGB(240, 210, 60),
			material = Enum.Material.Neon,
			canCollide = false,
			parent = f,
		})
		makeLabel(tostring(i * 10), place(Vector3.new(pos.X + size.X / 2 + 2, GROUND_TOP + 2, z)), f)
	end
	makeLabel("Sprint Lane", place(Vector3.new(pos.X, GROUND_TOP + 6, pos.Z - size.Z / 2)), f)
end

local function buildCrouchTunnel(parent: Folder): ()
	local f = makeFolder("CrouchTunnel", parent)
	local pos: Vector3 = CFG.CROUCH_TUNNEL_POSITION
	local size: Vector3 = CFG.CROUCH_TUNNEL_SIZE
	local opening: number = CFG.CROUCH_TUNNEL_OPENING_HEIGHT

	-- Side walls (open along Z so you walk through).
	for _, sign in ipairs({ -1, 1 }) do
		makeBlock({
			name = if sign < 0 then "WallLeft" else "WallRight",
			size = Vector3.new(1, size.Y, size.Z),
			cframe = CFrame.new(place(Vector3.new(pos.X + sign * size.X / 2, GROUND_TOP + size.Y / 2, pos.Z))),
			color = Color3.fromRGB(150, 150, 150),
			material = Enum.Material.Concrete,
			parent = f,
		})
	end
	-- Roof: its underside sits at GROUND_TOP + opening, forcing a crouch.
	local roofThick = size.Y - opening
	makeBlock({
		name = "Roof",
		size = Vector3.new(size.X, roofThick, size.Z),
		cframe = CFrame.new(place(Vector3.new(pos.X, GROUND_TOP + opening + roofThick / 2, pos.Z))),
		color = Color3.fromRGB(110, 90, 70),
		material = Enum.Material.WoodPlanks,
		parent = f,
	})
	makeLabel("Crouch Tunnel", place(Vector3.new(pos.X, GROUND_TOP + size.Y + LABEL_LIFT, pos.Z)), f)
end

local function buildVaults(parent: Folder): ()
	local f = makeFolder("Vaults", parent)
	-- Lined up just past the sprint-lane exit so you can sprint into them.
	local laneX = CFG.SPRINT_LANE_POSITION.X
	local baseZ = CFG.SPRINT_LANE_POSITION.Z + CFG.SPRINT_LANE_SIZE.Z / 2 + 10
	buildVaultBar("LowVault", "Low Vault", CFG.LOW_VAULT_HEIGHT, Vector3.new(laneX, 0, baseZ), f)
	buildVaultBar("MediumVault", "Medium Vault", CFG.MEDIUM_VAULT_HEIGHT, Vector3.new(laneX, 0, baseZ + 12), f)
	buildVaultBar("TooTallVault", "Too Tall / Reject", CFG.TOO_TALL_VAULT_HEIGHT, Vector3.new(laneX, 0, baseZ + 24), f)
end

local function buildDropTest(parent: Folder): ()
	local f = makeFolder("DropTest", parent)
	makeLabel("Drop Test", place(Vector3.new(-88, GROUND_TOP + 20, -45)), f)
	for i, height: number in ipairs(CFG.DROP_TEST_HEIGHTS :: { number }) do
		buildDropPlatform(height, Vector3.new(-88, 0, -25 + (i - 1) * 22), f)
	end
end

local function buildStairs(parent: Folder): ()
	local f = makeFolder("Stairs", parent)
	-- Compact 6-step run for ascent/descent feel; not a full staircase system.
	for i = 1, 6 do
		makeBlock({
			name = "Step_" .. tostring(i),
			size = Vector3.new(8, 1, 2.5),
			cframe = CFrame.new(place(Vector3.new(-64, GROUND_TOP + i - 0.5, -14 - i * 2.5))),
			color = Color3.fromRGB(130, 130, 135),
			material = Enum.Material.Concrete,
			parent = f,
		})
	end
	makeLabel("Stairs", place(Vector3.new(-64, GROUND_TOP + 8, -14)), f)
end

local function buildMovementCourse(root: Folder): ()
	local f = makeFolder("MovementCourse", root)
	buildSprintLane(f)
	buildCrouchTunnel(f)
	buildVaults(f)
	buildDropTest(f)
	buildStairs(f)
end

local function buildMaterialTest(root: Folder): ()
	local f = makeFolder("MaterialTest", root)
	local pos: Vector3 = CFG.MATERIAL_TEST_POSITION
	-- Visual/test surfaces only — no material-specific impact logic in this task.
	local samples: { { name: string, material: Enum.Material, color: Color3 } } = {
		{ name = "Concrete", material = Enum.Material.Concrete, color = Color3.fromRGB(140, 140, 145) },
		{ name = "Metal", material = Enum.Material.Metal, color = Color3.fromRGB(120, 125, 135) },
		{ name = "Wood", material = Enum.Material.WoodPlanks, color = Color3.fromRGB(125, 90, 55) },
		{ name = "Grass", material = Enum.Material.Grass, color = Color3.fromRGB(70, 120, 55) },
	}
	for i, s in ipairs(samples) do
		local x = pos.X + (i - 2.5) * 10
		makeBlock({
			name = "Sample_" .. s.name .. "_Wall",
			size = Vector3.new(8, 8, 1),
			cframe = CFrame.new(place(Vector3.new(x, GROUND_TOP + 4, pos.Z))),
			color = s.color,
			material = s.material,
			parent = f,
		})
		makeBlock({
			name = "Sample_" .. s.name .. "_Floor",
			size = Vector3.new(8, 0.5, 8),
			cframe = CFrame.new(place(Vector3.new(x, GROUND_TOP + 0.25, pos.Z - 6))),
			color = s.color,
			material = s.material,
			parent = f,
		})
		makeLabel(s.name, place(Vector3.new(x, GROUND_TOP + 9, pos.Z)), f)
	end
	makeLabel("Material Test", place(Vector3.new(pos.X, GROUND_TOP + 12, pos.Z)), f)
end

local function buildLightingTest(root: Folder): ()
	-- Self-contained props only. game.Lighting is NOT modified anywhere in this script.
	local f = makeFolder("LightingTest", root)

	-- Warm point-light pocket (muzzle flash / viewmodel readability in local light).
	local orb = makeBlock({
		name = "PointLightOrb",
		size = Vector3.new(2, 2, 2),
		cframe = CFrame.new(place(Vector3.new(-14, GROUND_TOP + 8, -40))),
		color = Color3.fromRGB(255, 220, 170),
		material = Enum.Material.Neon,
		canCollide = false,
		parent = f,
	})
	makeBlock({
		name = "PointLightPole",
		size = Vector3.new(0.6, 8, 0.6),
		cframe = CFrame.new(place(Vector3.new(-14, GROUND_TOP + 4, -40))),
		color = Color3.fromRGB(40, 40, 45),
		material = Enum.Material.Metal,
		parent = f,
	})
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 4
	pointLight.Range      = 26
	pointLight.Color      = Color3.fromRGB(255, 210, 160)
	pointLight.Parent     = orb

	-- Spot light aimed at the impact wall.
	local head = makeBlock({
		name = "SpotLightHead",
		size = Vector3.new(2, 2, 2),
		cframe = CFrame.new(place(Vector3.new(18, GROUND_TOP + 9, -40))),
		color = Color3.fromRGB(230, 230, 240),
		material = Enum.Material.Neon,
		canCollide = false,
		parent = f,
	})
	local spot = Instance.new("SpotLight")
	spot.Brightness = 5
	spot.Range      = 45
	spot.Angle      = 55
	spot.Face       = Enum.NormalId.Bottom
	spot.Color      = Color3.fromRGB(235, 240, 255)
	spot.Parent     = head

	-- Shade overhang: a roofed pocket for checking FX / viewmodel in shadow.
	makeBlock({
		name = "OverhangRoof",
		size = Vector3.new(16, 1, 16),
		cframe = CFrame.new(place(Vector3.new(-14, GROUND_TOP + 8, -58))),
		color = Color3.fromRGB(60, 60, 65),
		material = Enum.Material.Concrete,
		castShadow = true,
		parent = f,
	})
	for _, sign in ipairs({ -1, 1 }) do
		makeBlock({
			name = if sign < 0 then "OverhangPostA" else "OverhangPostB",
			size = Vector3.new(1, 8, 1),
			cframe = CFrame.new(place(Vector3.new(-14 + sign * 7, GROUND_TOP + 4, -58 - 7))),
			color = Color3.fromRGB(60, 60, 65),
			material = Enum.Material.Concrete,
			castShadow = true,
			parent = f,
		})
	end
	makeLabel("Lighting Test", place(Vector3.new(-14, GROUND_TOP + 12, -49)), f)
end

-- ── Build ───────────────────────────────────────────────────────────────────
local existing = workspace:FindFirstChild(FOLDER_NAME)
if existing ~= nil then
	if not existing:IsA("Folder") then
		Logger.warn("[TestAreaBuilder] Workspace." .. FOLDER_NAME
			.. " existed as a " .. existing.ClassName .. ", not a Folder — replacing it")
	end
	existing:Destroy()
end

local root = Instance.new("Folder")
root.Name = FOLDER_NAME

buildBaseAndSpawn(root)
buildShootingRange(root)
buildImpactWall(root)
buildMovementCourse(root)
buildMaterialTest(root)
buildLightingTest(root)

root.Parent = workspace

Logger.debug(("[TestAreaBuilder] built Workspace.%s — %d instances (labels %s)")
	:format(FOLDER_NAME, #root:GetDescendants(), if labelsEnabled then "on" else "off"))
