--!strict
-- Build-TestDummy.luau
--
-- One-shot developer helper. NOT a Lune script and NOT part of the game — run it ONCE
-- inside Roblox Studio (paste into the Command Bar, or drop it in a temporary Script,
-- run, then delete the Script). It builds a standard R6 rig, tags it, and parents it to
-- Workspace so DummyService can pick it up.
--
-- After running:
--   * DummyService registers the model on the next server start (it also picks up dummies
--     added at runtime), primes the Humanoid from Constants.DUMMY_* values, and adds the
--     generic Constants.TAG_DAMAGE_ENTITY tag.
--   * You then own the rig in Studio — reposition it, duplicate it, add a
--     "BR_DummyMaxHealth" NumberValue attribute to override health, or a "BR_ManualRespawn"
--     BoolValue attribute to stop auto-respawn.
--
-- Re-running makes another dummy; it never edits or removes an existing one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Constants"))
local Logger    = require(ReplicatedStorage.Modules:WaitForChild("Logger"))

-- ── Tuning (rig geometry only — gameplay values live in Constants) ───────────────
local DUMMY_NAME   = "DamageDummy"
local BODY_COLOR   = Color3.fromRGB(180, 180, 185)
local LIMB_COLOR   = Color3.fromRGB(150, 150, 155)
local BODY_MATERIAL: Enum.Material = Enum.Material.SmoothPlastic

-- ── Where to place it: just in front of the first SpawnLocation, else near origin ──
local function spawnCFrame(): CFrame
    local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    if spawn then
        return spawn.CFrame * CFrame.new(0, 3, -8)
    end
    return CFrame.new(0, 5, 0)
end

-- ── Part factory ────────────────────────────────────────────────────────────────
local function makePart(name: string, size: Vector3, color: Color3): BasePart
    local part = Instance.new("Part")
    part.Name          = name
    part.Size          = size
    part.Color         = color
    part.Material      = BODY_MATERIAL
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    return part
end

local function makeMotor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
    local motor = Instance.new("Motor6D")
    motor.Name   = name
    motor.Part0  = part0
    motor.Part1  = part1
    motor.C0     = c0
    motor.C1     = c1
    motor.Parent = part0
    return motor
end

-- ── Build ───────────────────────────────────────────────────────────────────────
local model = Instance.new("Model")
model.Name = DUMMY_NAME

local root  = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), BODY_COLOR)
root.Transparency = 1
root.CanCollide   = false

local torso = makePart("Torso",     Vector3.new(2, 2, 1), BODY_COLOR)
local head  = makePart("Head",      Vector3.new(2, 1, 1), BODY_COLOR)
local lArm  = makePart("Left Arm",  Vector3.new(1, 2, 1), LIMB_COLOR)
local rArm  = makePart("Right Arm", Vector3.new(1, 2, 1), LIMB_COLOR)
local lLeg  = makePart("Left Leg",  Vector3.new(1, 2, 1), LIMB_COLOR)
local rLeg  = makePart("Right Leg", Vector3.new(1, 2, 1), LIMB_COLOR)

local headMesh = Instance.new("SpecialMesh")
headMesh.MeshType = Enum.MeshType.Head
headMesh.Scale    = Vector3.new(1.25, 1.25, 1.25)
headMesh.Parent   = head

-- A face, purely so "forward" is obvious when aiming.
local face = Instance.new("Decal")
face.Name    = "face"
face.Texture  = "rbxasset://textures/face.png"
face.Face    = Enum.NormalId.Front
face.Parent  = head

-- Position everything relative to the torso, then move the whole rig to the spawn CFrame.
local base = CFrame.new(0, 3, 0)  -- lift so legs clear the ground before we PivotTo
torso.CFrame = base
root.CFrame  = base
head.CFrame  = base * CFrame.new(0,  1.5, 0)
lArm.CFrame  = base * CFrame.new(-1.5, 0,  0)
rArm.CFrame  = base * CFrame.new( 1.5, 0,  0)
lLeg.CFrame  = base * CFrame.new(-0.5, -2, 0)
rLeg.CFrame  = base * CFrame.new( 0.5, -2, 0)

for _, part in ipairs({ root, torso, head, lArm, rArm, lLeg, rLeg }) do
    part.Parent = model
end

-- Canonical R6 joints.
makeMotor("RootJoint", root, torso,
    CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
    CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
makeMotor("Neck", torso, head,
    CFrame.new(0,  1,   0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
    CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
makeMotor("Left Shoulder", torso, lArm,
    CFrame.new(-1,   0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
    CFrame.new( 0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
makeMotor("Right Shoulder", torso, rArm,
    CFrame.new( 1,   0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
    CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
makeMotor("Left Hip", torso, lLeg,
    CFrame.new(-1,   -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
    CFrame.new(-0.5,  1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
makeMotor("Right Hip", torso, rLeg,
    CFrame.new( 1,  -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
    CFrame.new( 0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))

local humanoid = Instance.new("Humanoid")
humanoid.RigType             = Enum.HumanoidRigType.R6
humanoid.MaxHealth           = Constants.DUMMY_DEFAULT_MAX_HEALTH
humanoid.Health              = Constants.DUMMY_DEFAULT_MAX_HEALTH
humanoid.BreakJointsOnDeath  = false   -- DummyService also enforces this; set here so a Studio-only test still ragdolls cleanly
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
humanoid.Parent = model

model.PrimaryPart = root
model:PivotTo(spawnCFrame())

CollectionService:AddTag(model, Constants.TAG_DAMAGE_DUMMY)

model.Parent = workspace

Logger.debug("[Build-TestDummy] Created", model:GetFullName(),
    "| tag:", Constants.TAG_DAMAGE_DUMMY,
    "| HP:", Constants.DUMMY_DEFAULT_MAX_HEALTH,
    "— reposition it in Studio; DummyService registers it on the next server run.")
