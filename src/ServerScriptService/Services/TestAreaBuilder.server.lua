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
--   * No combat / damage / ammo / movement / camera / viewmodel logic — the test
--     dummies are plain tagged R6 rigs; DummyService owns all their behaviour.
--   * No per-frame loops, no RBXScriptConnections.
--   * game.Lighting is never touched — the lighting section is self-contained props
--     (Part + PointLight/SpotLight) that vanish with the folder.
--
-- Guards: does nothing unless RunService:IsStudio() AND
-- Constants.DEV_TEST_AREA.ENABLED == true.
--
-- Safe to re-run (stop/start Play Solo): it destroys ONLY the one folder it owns and
-- rebuilds it. Two opt-in exceptions touch Workspace content it does not own, both
-- swept/restored on every run:
--   * DEV_TEST_AREA.REDIRECT_TEAM_SPAWNS — moves the CFrames of Workspace/Spawns
--     BaseParts onto this area (originals stashed in a backup attribute).
--   * DEV_TEST_AREA.SPAWN_DUMMIES — spawns N R6 rigs tagged Constants.TAG_DAMAGE_DUMMY
--     with a BR_TestAreaDummy attribute, and destroys any it (or DummyService) left
--     behind before respawning them.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

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
local LABEL_LIFT: number  = 2 -- studs a section label floats above its prop
local labelsEnabled: boolean = CFG.DEBUG_LABELS == true

-- World position = ORIGIN + local offset. ORIGIN lifts the whole area into the sky
-- (see Constants.DEV_TEST_AREA.ORIGIN); routing every placement through here keeps it
-- relocatable from that one constant.
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
	gui.Size           = UDim2.fromOffset(96, 22)   -- small tag, ~1/3 the old footprint
	gui.StudsOffset    = Vector3.new(0, 0.4, 0)
	gui.AlwaysOnTop    = false                        -- occluded by geometry so only nearby ones show
	gui.LightInfluence = 0
	gui.MaxDistance    = 60                           -- only render when you're in that section
	gui.Parent         = anchor

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.55
	label.BorderSizePixel        = 0
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.Font                   = Enum.Font.GothamMedium
	label.TextScaled             = true
	label.TextWrapped            = true
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

-- ── Team-spawn redirect (Studio only, reversible) ───────────────────────────
-- The one place this script touches Workspace content it does not own. It only
-- writes BasePart.CFrame and a single backup attribute — never reparents,
-- resizes, restyles, or destroys a spawn point. Each run first restores every
-- previously-moved spawn from its backup attribute, so flipping
-- REDIRECT_TEAM_SPAWNS to false and pressing Play once fully reverts.
local function redirectTeamSpawns(): ()
	local spawnsRoot = workspace:FindFirstChild("Spawns")
	if spawnsRoot == nil then
		Logger.debug("[TestAreaBuilder] no Workspace.Spawns — team-spawn redirect skipped")
		return
	end
	local attr: string = CFG.SPAWN_BACKUP_ATTRIBUTE

	-- 1. Restore anything we moved on a previous run (self-healing / clean toggle-off).
	local restored = 0
	for _, d in ipairs(spawnsRoot:GetDescendants()) do
		if d:IsA("BasePart") then
			local saved = d:GetAttribute(attr)
			if typeof(saved) == "CFrame" then
				d.CFrame = saved :: CFrame
				d:SetAttribute(attr, nil)
				restored += 1
			end
		end
	end

	if CFG.REDIRECT_TEAM_SPAWNS ~= true then
		if restored > 0 then
			Logger.debug(("[TestAreaBuilder] restored %d team spawn point(s) to their original CFrames"):format(restored))
		end
		return
	end

	-- 2. Stash each spawn part's current CFrame, then lay them out in a grid on the
	--    baseplate around SPAWN_POSITION so every player spawns in the test area.
	local parts: { BasePart } = {}
	for _, d in ipairs(spawnsRoot:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		Logger.warn("[TestAreaBuilder] Workspace.Spawns has no BasePart children — nothing to redirect")
		return
	end

	local spacing: number = CFG.TEAM_SPAWN_GRID_SPACING
	local perRow = 6
	local base = CFG.SPAWN_POSITION
	for i, part in ipairs(parts) do
		part:SetAttribute(attr, part.CFrame)
		local idx = i - 1
		local col = idx % perRow
		local rowN = math.floor(idx / perRow)
		local gridOffset = Vector3.new(
			(col - (perRow - 1) / 2) * spacing,
			0,
			8 + rowN * spacing
		)
		part.CFrame = CFrame.new(place(Vector3.new(base.X, GROUND_TOP + 3, base.Z)) + gridOffset)
	end
	Logger.debug(("[TestAreaBuilder] redirected %d team spawn point(s) into %s (originals stashed on '%s')")
		:format(#parts, FOLDER_NAME, attr))
end

-- ── Developer damage-test dummies (Studio only) ────────────────────────────
-- Standard R6 rigs tagged Constants.TAG_DAMAGE_DUMMY so DummyService owns them
-- (damage / blood / hit reactions / ragdoll / respawn). Rig geometry mirrors
-- scripts/Build-TestDummy.luau. Each rig carries a BR_TestAreaDummy attribute so this
-- builder can sweep its own dummies — and DummyService's respawn clones, which inherit
-- the attribute — on every rebuild.
local DUMMY_ATTR = "BR_TestAreaDummy"

local function buildDummyRig(worldCFrame: CFrame): Model
	assert(typeof(worldCFrame) == "CFrame", "buildDummyRig: worldCFrame must be a CFrame")
	local BODY = Color3.fromRGB(180, 180, 185)
	local LIMB = Color3.fromRGB(150, 150, 155)

	local function p(name: string, size: Vector3, color: Color3): BasePart
		local part = Instance.new("Part")
		part.Name          = name
		part.Size          = size
		part.Color         = color
		part.Material      = Enum.Material.SmoothPlastic
		part.TopSurface    = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end
	local function motor(name: string, a: BasePart, b: BasePart, c0: CFrame, c1: CFrame)
		local m = Instance.new("Motor6D")
		m.Name   = name
		m.Part0  = a
		m.Part1  = b
		m.C0     = c0
		m.C1     = c1
		m.Parent = a
	end

	local model = Instance.new("Model")
	model.Name = "TestAreaDummy"

	local root = p("HumanoidRootPart", Vector3.new(2, 2, 1), BODY)
	root.Transparency = 1
	root.CanCollide   = false
	local torso = p("Torso", Vector3.new(2, 2, 1), BODY)
	local head  = p("Head", Vector3.new(2, 1, 1), BODY)
	local lArm  = p("Left Arm", Vector3.new(1, 2, 1), LIMB)
	local rArm  = p("Right Arm", Vector3.new(1, 2, 1), LIMB)
	local lLeg  = p("Left Leg", Vector3.new(1, 2, 1), LIMB)
	local rLeg  = p("Right Leg", Vector3.new(1, 2, 1), LIMB)

	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale    = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent   = head
	local face = Instance.new("Decal")
	face.Name    = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face    = Enum.NormalId.Front
	face.Parent  = head

	local base = CFrame.new(0, 3, 0)
	torso.CFrame = base
	root.CFrame  = base
	head.CFrame  = base * CFrame.new(0, 1.5, 0)
	lArm.CFrame  = base * CFrame.new(-1.5, 0, 0)
	rArm.CFrame  = base * CFrame.new(1.5, 0, 0)
	lLeg.CFrame  = base * CFrame.new(-0.5, -2, 0)
	rLeg.CFrame  = base * CFrame.new(0.5, -2, 0)
	for _, part in ipairs({ root, torso, head, lArm, rArm, lLeg, rLeg }) do
		part.Parent = model
	end

	motor("RootJoint", root, torso,
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Neck", torso, head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Left Shoulder", torso, lArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Shoulder", torso, rArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, lLeg,
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType             = Enum.HumanoidRigType.R6
	humanoid.MaxHealth           = Constants.DUMMY_DEFAULT_MAX_HEALTH :: number
	humanoid.Health              = Constants.DUMMY_DEFAULT_MAX_HEALTH :: number
	humanoid.BreakJointsOnDeath  = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	model.PrimaryPart = root
	model:PivotTo(worldCFrame)
	model:SetAttribute(DUMMY_ATTR, true)
	CollectionService:AddTag(model, Constants.TAG_DAMAGE_DUMMY :: string)
	return model
end

-- Sweeps this builder's previous dummies (and DummyService respawn clones, which keep the
-- attribute), then spawns DUMMY_COUNT fresh rigs downrange of the firing line, facing it.
local function spawnTestDummies(): ()
	local swept = 0
	for _, m in ipairs(CollectionService:GetTagged(Constants.TAG_DAMAGE_DUMMY :: string)) do
		if m:GetAttribute(DUMMY_ATTR) == true then
			m:Destroy()
			swept += 1
		end
	end

	if CFG.SPAWN_DUMMIES ~= true then
		if swept > 0 then
			Logger.debug(("[TestAreaBuilder] removed %d prior test dummy/dummies"):format(swept))
		end
		return
	end

	local count: number     = CFG.DUMMY_COUNT
	local spacing: number    = CFG.DUMMY_SPACING
	local downrange: number  = CFG.DUMMY_DOWNRANGE
	local start: Vector3     = CFG.SHOOTING_RANGE_START
	local faceTarget = place(Vector3.new(start.X, GROUND_TOP + 3, start.Z))
	for i = 1, count do
		local x = start.X + (i - (count + 1) / 2) * spacing
		local pivotPos = place(Vector3.new(x, GROUND_TOP + 3, start.Z + downrange))
		buildDummyRig(CFrame.lookAt(pivotPos, faceTarget)).Parent = workspace
	end
	Logger.debug(("[TestAreaBuilder] spawned %d damage test dummy/dummies (swept %d)")
		:format(count, swept))
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

redirectTeamSpawns()
spawnTestDummies()

Logger.debug(("[TestAreaBuilder] built Workspace.%s — %d instances (labels %s)")
	:format(FOLDER_NAME, #root:GetDescendants(), if labelsEnabled then "on" else "off"))
