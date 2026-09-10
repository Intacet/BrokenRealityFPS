--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > AIService
--
-- AI Stage 1A — basic server-owned squad NPC foundation.
-- AI Stage 1B — combat feedback FX (muzzle flash / smoke / light / tracer / 3D sound).
-- AI Stage 1C — grunt weapon model + third-person animation (same gun/poses as players).
--
-- Spawns simple R6 rifleman "grunt" squads from Workspace/AISpawns, patrols
-- Workspace/AIPatrolPoints, detects players by server raycast line-of-sight,
-- chases visible targets, and burst-fires simple server raycasts at them.
-- Easy to kill alone, dangerous in numbers — battlefield filler, not tactical AI.
--
-- ALL decisions are server-side. No remotes, no client AI scripts, no client
-- damage decisions. All tuning is in Constants.AI / Constants.AI_COMBAT_FX.
--
-- Damage integration (uses existing extension points only — nothing else changed):
--   * player -> AI : every NPC model is tagged Constants.TAG_DAMAGE_ENTITY, so
--     GunService.getDamageableEntity already routes player bullet hits into
--     DamageService:ApplyDamage. AIService just listens for Humanoid.Died.
--   * AI -> player : fireOneShot() calls DamageService:ApplyDamage (the public,
--     entity-agnostic entry point) with attacker = nil and region = Unknown so
--     the damage is a flat Constants.AI.SHOT_DAMAGE.
--   * BloodService reacts to any CombatEvents.DamageDealt, so hits on/by AI
--     already produce blood — a side effect, suppressible with BR_BloodEnabled.
--
-- Stage 1B combat FX (Constants.AI_COMBAT_FX): server-created, world-replicated
-- placeholder visuals — a muzzle flash + smoke puff + light pulse on an
-- auto-created "AIMuzzleAttachment" (on the welded gun's Barrel, else the Right
-- Arm), an optional short tracer Beam parented under Workspace/AI, and a 3D
-- gunshot Sound. Emitters / light / sound are built ONCE per NPC in
-- setupAICombatFx and reused; only the tracer creates a temporary part per shot
-- (Debris-cleaned; AI fire rate is capped). Placeholder asset IDs (rbxassetid://0)
-- warn once and do not crash.
--
-- Stage 1C weapon + animation (Constants.AI Stage 1C fields): each grunt gets the
-- real AKS-74 world model (ReplicatedStorage/WorldModels/<worldModelName>) welded
-- Handle -> Right Arm via a Motor6D, exactly like WorldWeaponService does for
-- players, plus the WeaponData thirdPerson equip/idle/fire clips and the default
-- R6 idle/walk clips loaded on the grunt's Humanoid.Animator. The gun only sits
-- correctly while the thirdPerson `idle` pose plays (grip C0/C1 are identity). All
-- of this degrades gracefully — a missing model or a failed LoadAnimation just
-- warns once and the grunt still fires.
--
-- Deferred (see docs/TECHNICAL_DEBT.md — AI Stage 1A/1B/1C): PathfindingService,
-- ragdoll on AI death, rewards/points/killstreaks, AI types, cover/flanking,
-- jump/climb animation, reload animation, final flash/smoke/sound art, tracer
-- pooling, extracting the WorldWeaponService attach body into a shared module.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))

-- DamageService is a sibling ModuleScript; the only in-tree caller besides GunService.
local DamageService = require(script.Parent:WaitForChild("DamageService"))

-- Untyped views of the tuning tables (heterogeneous fields; matches the pattern
-- used by TestAreaBuilder's `local CFG = Constants.DEV_TEST_AREA :: any`).
local AI = Constants.AI :: any
local FX = Constants.AI_COMBAT_FX :: any

-- ============================================================
-- Types
-- ============================================================

type AIState = "Idle" | "Patrol" | "Chase" | "Attack" | "Dead"

-- Stage 1B combat FX instances, built once per NPC and reused every shot.
-- All children of `attachment`, so they are destroyed with the NPC model.
type AICombatFx = {
    attachment: Attachment,
    flash     : ParticleEmitter?,
    smoke     : ParticleEmitter?,
    light     : PointLight?,
    sound     : Sound?,
    lightToken: number,          -- guards the light-off task.delay against rapid re-fire
}

-- Stage 1C animation tracks, loaded once per NPC on the Humanoid.Animator.
-- Tracks + Animator are children of the NPC model and die with it.
type AIAnim = {
    weaponIdle    : AnimationTrack?,  -- thirdPerson idle — positions the welded gun
    locomotionIdle: AnimationTrack?,
    locomotionWalk: AnimationTrack?,
    fire          : AnimationTrack?,  -- thirdPerson fire — played per shot
    movingWalk    : boolean,          -- current locomotion state (walk vs idle)
}

type NPCRecord = {
    model    : Model,
    humanoid : Humanoid,
    root     : BasePart,
    squadId  : number,
    isLeader : boolean,
    slot     : Vector3,          -- formation offset around the squad reference point

    state        : AIState,
    target       : Player?,
    lastSeenPos  : Vector3?,
    lastSeenClock: number,

    nextThinkClock      : number,
    nextTargetCheckClock: number,

    firing    : boolean,
    fireThread: thread?,
    conns     : { RBXScriptConnection },
    fx        : AICombatFx?,
    anim      : AIAnim?,
    dead      : boolean,
}

type SquadRecord = {
    id          : number,
    spawnCFrame : CFrame,
    patrolIndex : number,
}

-- ============================================================
-- State
-- ============================================================

local started   = false
local running   = false
local mainThread: thread? = nil
local serviceConns: { RBXScriptConnection } = {}
local didStudioAutoSpawn = false

local aiFolder : Folder? = nil
local losParams: RaycastParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

local npcs   : { [Model]: NPCRecord } = {}
local squads : { [number]: SquadRecord } = {}

-- Dead NPCs waiting out DEATH_CLEANUP_DELAY before their model is destroyed.
local pendingCleanup : { NPCRecord } = {}

local spawnParts  : { BasePart } = {}
local patrolPoints: { BasePart } = {}

local squadCounter = 0
local npcCounter   = 0

local warnedNoSpawns = false
local warnedNoPatrol = false
local warnedPlaceholderFx  = false  -- one-time: AI_COMBAT_FX still on rbxassetid://0
local warnedNoMuzzleParent = false  -- one-time: an NPC rig had no Right Arm / HRP
local warnedNoWorldModel    = false  -- one-time: WorldModels/<weapon> asset missing (Stage 1C)
local warnedAnimLoadFailed  = false  -- one-time: LoadAnimation threw for an AI anim (Stage 1C)

-- ============================================================
-- Workspace folder discovery
-- ============================================================

local function ensureAIFolder(): Folder
    local existing = workspace:FindFirstChild(AI.FOLDER_NAME)
    if existing ~= nil and existing:IsA("Folder") then
        return existing :: Folder
    end
    if existing ~= nil then
        existing:Destroy()
    end
    local folder = Instance.new("Folder")
    folder.Name   = AI.FOLDER_NAME
    folder.Parent = workspace
    return folder
end

-- Collects BasePart children of a named Workspace folder. Warns once (via the
-- passed flag setter) if the folder is missing or empty; never errors.
local function collectParts(folderName: string, alreadyWarned: boolean): ({ BasePart }, boolean)
    local out: { BasePart } = {}
    local folder = workspace:FindFirstChild(folderName)
    if folder == nil then
        if not alreadyWarned then
            Logger.warn("[AIService] Workspace." .. folderName .. " is missing — AIService still starts, that source is just empty")
        end
        return out, true
    end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(out, child)
        end
    end
    if #out == 0 and not alreadyWarned then
        Logger.warn("[AIService] Workspace." .. folderName .. " has no BasePart children")
        return out, true
    end
    return out, alreadyWarned
end

-- ============================================================
-- R6 rig construction (geometry mirrors scripts/Build-TestDummy.luau)
-- ============================================================

local BODY_COLOR: Color3 = Color3.fromRGB(120, 122, 128)
local LIMB_COLOR: Color3 = Color3.fromRGB(96, 98, 104)

local function makePart(name: string, size: Vector3, color: Color3): BasePart
    local part = Instance.new("Part")
    part.Name          = name
    part.Size          = size
    part.Color         = color
    part.Material      = Enum.Material.SmoothPlastic
    part.TopSurface    = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    return part
end

local function makeMotor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
    local motor = Instance.new("Motor6D")
    motor.Name   = name
    motor.Part0  = part0
    motor.Part1  = part1
    motor.C0     = c0
    motor.C1     = c1
    motor.Parent = part0
end

-- Builds a standard R6 rig at the given world CFrame. Returns (model, humanoid, root).
local function buildRig(worldCFrame: CFrame): (Model, Humanoid, BasePart)
    local model = Instance.new("Model")

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

    makeMotor("RootJoint", root, torso,
        CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
        CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
    makeMotor("Neck", torso, head,
        CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
        CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
    makeMotor("Left Shoulder", torso, lArm,
        CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
        CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
    makeMotor("Right Shoulder", torso, rArm,
        CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
        CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
    makeMotor("Left Hip", torso, lLeg,
        CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
        CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
    makeMotor("Right Hip", torso, rLeg,
        CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
        CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))

    local humanoid = Instance.new("Humanoid")
    humanoid.RigType             = Enum.HumanoidRigType.R6
    humanoid.MaxHealth           = AI.NPC_HEALTH
    humanoid.Health              = AI.NPC_HEALTH
    humanoid.WalkSpeed           = AI.NPC_WALK_SPEED
    humanoid.BreakJointsOnDeath  = false
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.Parent = model

    -- Stage 1C: an Animator is required to LoadAnimation on this rig.
    local animator = Instance.new("Animator")
    animator.Parent = humanoid

    model.PrimaryPart = root
    model:PivotTo(worldCFrame)

    return model, humanoid, root
end

-- Ring formation offset for member `index` (1-based) of a squad of `size`.
local function slotOffset(index: number, size: number): Vector3
    if size <= 1 then
        return Vector3.zero
    end
    local angle  = (index - 1) * (math.pi * 2 / size)
    local radius = AI.SQUAD_SPACING
    return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- ============================================================
-- Line of sight / target detection
-- ============================================================

-- Clear line of sight from the NPC's eye height to the target character's root.
local function canSee(record: NPCRecord, targetChar: Model, targetRoot: BasePart): boolean
    local offset = Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET, 0)
    local origin = record.root.Position + offset
    local dir    = (targetRoot.Position + offset) - origin
    local result = workspace:Raycast(origin, dir, losParams)
    if result == nil then
        return true
    end
    return result.Instance:IsDescendantOf(targetChar)
end

-- Nearest player that is alive, in DETECTION_RANGE, and visible. nil if none.
local function findVisibleTarget(record: NPCRecord): Player?
    local best: Player? = nil
    local bestDist = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char ~= nil then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local rootInst = char:FindFirstChild("HumanoidRootPart")
            if humanoid ~= nil and humanoid.Health > 0 and rootInst ~= nil and rootInst:IsA("BasePart") then
                local proot = rootInst :: BasePart
                local dist  = (proot.Position - record.root.Position).Magnitude
                if dist <= AI.DETECTION_RANGE and dist < bestDist and canSee(record, char, proot) then
                    best = player
                    bestDist = dist
                end
            end
        end
    end
    return best
end

-- Returns the target's root BasePart if the target is still a live, rooted character.
local function targetRootOf(player: Player?): BasePart?
    if player == nil then
        return nil
    end
    local char = player.Character
    if char == nil then
        return nil
    end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid == nil or humanoid.Health <= 0 then
        return nil
    end
    local rootInst = char:FindFirstChild("HumanoidRootPart")
    if rootInst == nil or not rootInst:IsA("BasePart") then
        return nil
    end
    return rootInst :: BasePart
end

-- ============================================================
-- Shooting (server raycast, no remotes)
-- ============================================================

-- Random direction inside a cone of half-angle `maxAngleRad` about `dir`.
local function coneSpread(dir: Vector3, maxAngleRad: number): Vector3
    if maxAngleRad <= 0 then
        return dir
    end
    local up: Vector3 = if math.abs(dir.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
    local right   = dir:Cross(up).Unit
    local realUp  = right:Cross(dir).Unit
    local roll    = math.random() * math.pi * 2
    local spread  = math.tan(math.random() * maxAngleRad)
    local offset  = (right * math.cos(roll) + realUp * math.sin(roll)) * spread
    return (dir + offset).Unit
end

-- ============================================================
-- Stage 1B — AI combat feedback FX (server-created, world-replicated)
--
-- Placeholder visuals until AI weapon models exist. All per-NPC emitters / light /
-- sound are built ONCE in setupAICombatFx and reused; only the tracer creates a
-- temporary part per shot (Debris-cleaned; AI fire rate is capped so this is
-- bounded — pooling is filed as future debt). No remotes, no client code.
-- ============================================================

-- One-time warning when flash / smoke / sound are still rbxassetid://0.
local function warnPlaceholderFxOnce()
    if warnedPlaceholderFx then
        return
    end
    if FX.FLASH_TEXTURE == "rbxassetid://0"
        or FX.SMOKE_TEXTURE == "rbxassetid://0"
        or FX.GUNSHOT_SOUND_ID == "rbxassetid://0"
    then
        warnedPlaceholderFx = true
        Logger.warn("[AIService] Constants.AI_COMBAT_FX still uses placeholder asset IDs (rbxassetid://0) — replace FLASH_TEXTURE / SMOKE_TEXTURE / GUNSHOT_SOUND_ID with real assets before shipping AI combat feedback")
    end
end

-- The rig part the muzzle FX hang off. Prefers the welded gun's Barrel (Stage 1C),
-- then the Right Arm, then HumanoidRootPart.
local function muzzleParentFor(record: NPCRecord): BasePart?
    local gun = record.model:FindFirstChild(Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME)
    if gun ~= nil then
        local barrel = gun:FindFirstChild("Barrel")
        if barrel ~= nil and barrel:IsA("BasePart") and barrel.Parent ~= nil then
            return barrel
        end
    end
    local arm = record.model:FindFirstChild("Right Arm")
    if arm ~= nil and arm:IsA("BasePart") and arm.Parent ~= nil then
        return arm
    end
    if record.root.Parent ~= nil then
        return record.root
    end
    return nil
end

-- Reuses a correctly-typed child of `parent` named `childName`, or replaces/creates it.
local function reuseOrNew(parent: Instance, childName: string, className: string): Instance
    local existing = parent:FindFirstChild(childName)
    if existing ~= nil and existing.ClassName == className then
        return existing
    end
    if existing ~= nil then
        existing:Destroy()
    end
    local inst = Instance.new(className)
    inst.Name = childName
    return inst
end

-- Builds (or re-finds) the per-NPC muzzle attachment + flash / smoke emitters +
-- light + sound. Idempotent: a second call is a no-op (record.fx already set),
-- and even a forced re-run reuses existing children rather than duplicating.
local function setupAICombatFx(npcRecord: NPCRecord): ()
    assert(npcRecord ~= nil, "npcRecord is required")

    if npcRecord.fx ~= nil or FX.ENABLED ~= true then
        return
    end

    warnPlaceholderFxOnce()

    local parentPart = muzzleParentFor(npcRecord)
    if parentPart == nil then
        if not warnedNoMuzzleParent then
            warnedNoMuzzleParent = true
            Logger.warn("[AIService] NPC rig has no Right Arm or HumanoidRootPart — AI muzzle FX skipped for", npcRecord.model.Name)
        end
        return
    end

    local attName: string = FX.MUZZLE_ATTACHMENT_NAME
    local attInst = parentPart:FindFirstChild(attName)
    local att: Attachment
    if attInst ~= nil and attInst:IsA("Attachment") then
        att = attInst :: Attachment
    elseif FX.AUTO_CREATE_MUZZLE_ATTACHMENT == true then
        local newAtt = Instance.new("Attachment")
        newAtt.Name = attName
        newAtt.Parent = parentPart
        att = newAtt
    else
        return  -- no attachment and not allowed to create one
    end
    -- Part-local placement: -Z is "forward" for an R6 limb roughly facing ahead.
    att.Position = Vector3.new(FX.MUZZLE_RIGHT_OFFSET, FX.MUZZLE_UP_OFFSET, -FX.MUZZLE_FORWARD_OFFSET)

    -- Note: only table-driven values are set. Structural rendering defaults
    -- (Enabled/Rate off, LightEmission/EmissionDirection, 0→1 transparency ramp)
    -- carry no gameplay tuning. Flash/smoke have no dedicated colour constants yet.
    local flash: ParticleEmitter? = nil
    if FX.FLASH_ENABLED == true then
        local e = reuseOrNew(att, "AIMuzzleFlashEmitter", "ParticleEmitter") :: ParticleEmitter
        e.Texture        = FX.FLASH_TEXTURE
        e.Enabled        = false
        e.Rate           = 0
        e.Lifetime       = NumberRange.new(FX.FLASH_LIFETIME_MIN, FX.FLASH_LIFETIME_MAX)
        e.Speed          = NumberRange.new(0, 0)
        e.Size           = NumberSequence.new(FX.FLASH_SIZE_START, FX.FLASH_SIZE_END)
        e.Transparency   = NumberSequence.new(0, 1)
        e.LightEmission  = 1
        e.LightInfluence = 0
        e.Parent         = att
        flash = e
    end

    local smoke: ParticleEmitter? = nil
    if FX.SMOKE_ENABLED == true then
        local e = reuseOrNew(att, "AIMuzzleSmokeEmitter", "ParticleEmitter") :: ParticleEmitter
        e.Texture           = FX.SMOKE_TEXTURE
        e.Enabled           = false
        e.Rate              = 0
        e.Lifetime          = NumberRange.new(FX.SMOKE_LIFETIME_MIN, FX.SMOKE_LIFETIME_MAX)
        e.Speed             = NumberRange.new(FX.SMOKE_SPEED_MIN, FX.SMOKE_SPEED_MAX)
        e.Size              = NumberSequence.new(FX.SMOKE_SIZE_START, FX.SMOKE_SIZE_END)
        e.Transparency      = NumberSequence.new(0, 1)
        e.EmissionDirection = Enum.NormalId.Front
        e.Parent            = att
        smoke = e
    end

    local light: PointLight? = nil
    if FX.LIGHT_ENABLED == true then
        local l = reuseOrNew(att, "AIMuzzleFlashLight", "PointLight") :: PointLight
        l.Brightness = FX.LIGHT_BRIGHTNESS
        l.Range      = FX.LIGHT_RANGE
        l.Enabled    = false
        l.Parent     = att
        light = l
    end

    local sound: Sound? = nil
    if FX.SOUND_ENABLED == true then
        local s = reuseOrNew(att, "AIGunshotSound", "Sound") :: Sound
        s.SoundId            = FX.GUNSHOT_SOUND_ID
        s.Volume             = FX.GUNSHOT_VOLUME
        s.RollOffMode        = Enum.RollOffMode.InverseTapered
        s.RollOffMinDistance = FX.GUNSHOT_ROLLOFF_MIN_DISTANCE
        s.RollOffMaxDistance = FX.GUNSHOT_ROLLOFF_MAX_DISTANCE
        s.Looped             = false
        s.Parent             = att
        sound = s
    end

    npcRecord.fx = {
        attachment = att,
        flash      = flash,
        smoke      = smoke,
        light      = light,
        sound      = sound,
        lightToken = 0,
    }
end

-- A very short-lived tracer Beam between the muzzle and the shot end point.
-- Temporary holder Part parented under Workspace/AI, Debris-cleaned. Bounded by
-- the AI fire rate; pooling is future debt (see docs/TECHNICAL_DEBT.md).
local function playAITracer(muzzleWorldPosition: Vector3, hitPosition: Vector3): ()
    assert(typeof(muzzleWorldPosition) == "Vector3", "muzzleWorldPosition must be a Vector3")
    assert(typeof(hitPosition) == "Vector3", "hitPosition must be a Vector3")
    if FX.TRACER_ENABLED ~= true then
        return
    end
    local folder = aiFolder
    if folder == nil then
        return
    end

    local holder = Instance.new("Part")
    holder.Name         = "AITracer"
    holder.Anchored     = true
    holder.CanCollide   = false
    holder.CanQuery     = false
    holder.CanTouch     = false
    holder.Transparency = 1
    holder.Size         = Vector3.one * 0.05
    holder.CFrame       = CFrame.new(muzzleWorldPosition)
    holder:SetAttribute("BR_AITracer", true)

    local a0 = Instance.new("Attachment")
    a0.Parent = holder
    local a1 = Instance.new("Attachment")
    a1.Position = holder.CFrame:PointToObjectSpace(hitPosition)
    a1.Parent = holder

    local beam = Instance.new("Beam")
    beam.Attachment0   = a0
    beam.Attachment1   = a1
    beam.Width0        = FX.TRACER_WIDTH_START
    beam.Width1        = FX.TRACER_WIDTH_END
    beam.Transparency  = NumberSequence.new(FX.TRACER_TRANSPARENCY_START, FX.TRACER_TRANSPARENCY_END)
    beam.FaceCamera    = true
    beam.LightEmission = 1
    beam.Segments      = 1
    beam.Parent        = holder

    holder.Parent = folder

    local life = FX.TRACER_LIFETIME
    if typeof(life) ~= "number" or life <= 0 then
        life = FX.CLEANUP_LIFETIME
    end
    Debris:AddItem(holder, life)
end

-- Plays the visible + audible feedback for one AI shot. Never yields the firing
-- path. Emits from the pre-built per-NPC emitters, pulses the light with a
-- token-guarded task.delay (safe after NPC death / service destroy), plays the
-- one shared 3D sound, and draws the tracer when an end point is known.
local function playAIShotFx(npcRecord: NPCRecord, muzzleWorldPosition: Vector3, hitPosition: Vector3?): ()
    assert(npcRecord ~= nil, "npcRecord is required")
    assert(typeof(muzzleWorldPosition) == "Vector3", "muzzleWorldPosition must be a Vector3")
    if hitPosition ~= nil then
        assert(typeof(hitPosition) == "Vector3", "hitPosition must be a Vector3")
    end
    if FX.ENABLED ~= true then
        return
    end

    local fx = npcRecord.fx
    if fx ~= nil and fx.attachment.Parent ~= nil then
        if FX.FLASH_ENABLED == true and fx.flash ~= nil then
            fx.flash:Emit(FX.FLASH_EMIT_COUNT)
        end
        if FX.SMOKE_ENABLED == true and fx.smoke ~= nil then
            fx.smoke:Emit(FX.SMOKE_EMIT_COUNT)
        end
        if FX.LIGHT_ENABLED == true and fx.light ~= nil then
            fx.lightToken += 1
            local myToken = fx.lightToken
            local theLight = fx.light
            theLight.Enabled = true
            task.delay(FX.LIGHT_DURATION, function()
                -- theLight.Parent is nil once the NPC model is destroyed; the
                -- token guard also stops a stale pulse darkening a later flash.
                if theLight.Parent ~= nil and fx.lightToken == myToken then
                    theLight.Enabled = false
                end
            end)
        end
        if FX.SOUND_ENABLED == true and fx.sound ~= nil
            and fx.sound.SoundId ~= "rbxassetid://0" and fx.sound.SoundId ~= ""
        then
            local lo: number = FX.GUNSHOT_PLAYBACK_SPEED_MIN
            local hi: number = FX.GUNSHOT_PLAYBACK_SPEED_MAX
            fx.sound.PlaybackSpeed = lo + math.random() * (hi - lo)
            fx.sound:Play()
        end
    end

    if hitPosition ~= nil then
        playAITracer(muzzleWorldPosition, hitPosition)
    end
end

-- ============================================================
-- Stage 1C — grunt weapon model + third-person animation
-- Clones ReplicatedStorage/WorldModels/<worldModelName> onto the Right Arm exactly
-- like WorldWeaponService, and loads the WeaponData thirdPerson equip/idle/fire +
-- default R6 idle/walk on the Humanoid.Animator. Everything degrades gracefully.
-- ============================================================

-- Loads one Animation asset into a track on `animator`. Returns nil (and warns
-- once) if LoadAnimation throws — e.g. the asset is not readable by this place.
local function loadTrack(
    animator: Animator,
    animId: string,
    looped: boolean,
    priority: Enum.AnimationPriority
): AnimationTrack?
    local anim = Instance.new("Animation")
    anim.AnimationId = animId
    local ok, result = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    anim:Destroy()
    if not ok then
        if not warnedAnimLoadFailed then
            warnedAnimLoadFailed = true
            Logger.warn("[AIService] LoadAnimation failed for an AI clip (" .. animId
                .. ") — grunts fall back to the raw pose:", tostring(result))
        end
        return nil
    end
    local track = result :: AnimationTrack
    track.Looped = looped
    track.Priority = priority
    return track
end

-- Clones the AKS-74 world model onto the grunt's Right Arm. Mirrors
-- WorldWeaponService.EquipWeapon's attach body (that service takes a Player and is
-- a Script, so it can't be reused) using the same Constants.WORLD_WEAPON_* values.
local function attachAIWorldWeapon(record: NPCRecord): ()
    assert(record ~= nil, "record is required")
    if AI.USE_WORLD_WEAPON ~= true then
        return
    end

    local rawData = WeaponData[AI.WEAPON_NAME]
    if rawData == nil then
        return
    end
    local wmName = (rawData :: any).worldModelName
    if typeof(wmName) ~= "string" or wmName == "" then
        return
    end

    local folder = ReplicatedStorage:FindFirstChild(Constants.WORLD_WEAPON_FOLDER_NAME)
    local asset = if folder ~= nil then folder:FindFirstChild(wmName) else nil
    if asset == nil or not asset:IsA("Model") then
        if not warnedNoWorldModel then
            warnedNoWorldModel = true
            Logger.warn("[AIService] ReplicatedStorage." .. Constants.WORLD_WEAPON_FOLDER_NAME
                .. "." .. wmName .. " not found — grunts fire without a visible gun")
        end
        return
    end

    local rightArmInst = record.model:FindFirstChild(Constants.WORLD_WEAPON_R6_RIGHT_ARM_NAME)
    if rightArmInst == nil or not rightArmInst:IsA("BasePart") then
        return
    end

    -- Defensive: drop any earlier clone (setup runs once per NPC).
    local prior = record.model:FindFirstChild(Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME)
    if prior ~= nil then
        prior:Destroy()
    end

    local clone = (asset :: Model):Clone()
    clone.Name = Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME
    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.CanCollide = false
            desc.CanQuery   = false
            desc.CanTouch   = false
            desc.Massless    = true
            desc.Anchored    = false
        end
    end

    local handleInst = clone:FindFirstChild(Constants.WORLD_WEAPON_HANDLE_PART_NAME)
    if handleInst == nil or not handleInst:IsA("BasePart") then
        clone:Destroy()
        Logger.warn("[AIService] WorldModels." .. wmName .. " has no '"
            .. Constants.WORLD_WEAPON_HANDLE_PART_NAME .. "' BasePart — AI gun not attached")
        return
    end

    clone.Parent = record.model

    local motor  = Instance.new("Motor6D")
    motor.Name   = Constants.WORLD_WEAPON_GRIP_MOTOR_NAME
    motor.Part0  = rightArmInst
    motor.Part1  = handleInst
    motor.C0     = Constants.WORLD_AKS74_GRIP_C0
    motor.C1     = Constants.WORLD_AKS74_GRIP_C1
    motor.Parent = rightArmInst
end

-- Loads idle/walk (default R6) + thirdPerson idle/fire/equip on the grunt's
-- Animator and starts the hold pose. Connects Humanoid.Running to swap idle<->walk.
local function setupAIAnimation(record: NPCRecord): ()
    assert(record ~= nil, "record is required")
    if record.anim ~= nil then
        return
    end
    if AI.USE_THIRD_PERSON_ANIMS ~= true and AI.USE_LOCOMOTION_ANIMS ~= true then
        return
    end

    local animator = record.humanoid:FindFirstChildOfClass("Animator")
    if animator == nil then
        return
    end

    local anim: AIAnim = {
        weaponIdle     = nil,
        locomotionIdle = nil,
        locomotionWalk = nil,
        fire           = nil,
        movingWalk     = false,
    }

    if AI.USE_LOCOMOTION_ANIMS == true then
        anim.locomotionIdle = loadTrack(animator, AI.LOCOMOTION_IDLE_ANIM_ID, true, Enum.AnimationPriority.Idle)
        anim.locomotionWalk = loadTrack(animator, AI.LOCOMOTION_WALK_ANIM_ID, true, Enum.AnimationPriority.Movement)
        local li = anim.locomotionIdle
        if li ~= nil then
            li:Play()
        end
    end

    if AI.USE_THIRD_PERSON_ANIMS == true then
        local data = WeaponData[AI.WEAPON_NAME] :: any
        local tp = if data ~= nil and data.animations ~= nil then data.animations.thirdPerson else nil
        if tp ~= nil then
            if typeof(tp.idle) == "string" then
                anim.weaponIdle = loadTrack(animator, tp.idle, true, Enum.AnimationPriority.Action)
                local wi = anim.weaponIdle
                if wi ~= nil then
                    wi:Play(AI.WEAPON_IDLE_ANIM_FADE)
                end
            end
            if typeof(tp.fire) == "string" then
                anim.fire = loadTrack(animator, tp.fire, false, Enum.AnimationPriority.Action2)
            end
            if typeof(tp.equip) == "string" then
                local equipTrack = loadTrack(animator, tp.equip, false, Enum.AnimationPriority.Action2)
                if equipTrack ~= nil then
                    equipTrack:Play(AI.WEAPON_EQUIP_ANIM_FADE)
                end
            end
        end
    end

    record.anim = anim

    -- Swap idle <-> walk on the Humanoid's own speed signal (only when it flips).
    local runConn = record.humanoid.Running:Connect(function(speed: number)
        local a = record.anim
        if a == nil or record.dead then
            return
        end
        local shouldWalk = speed >= (AI.LOCOMOTION_WALK_SPEED_MIN :: number)
        if shouldWalk == a.movingWalk then
            return
        end
        a.movingWalk = shouldWalk
        local li, lw = a.locomotionIdle, a.locomotionWalk
        if shouldWalk then
            if li ~= nil then li:Stop() end
            if lw ~= nil then lw:Play() end
        else
            if lw ~= nil then lw:Stop() end
            if li ~= nil then li:Play() end
        end
    end)
    table.insert(record.conns, runConn)
end

-- Plays the thirdPerson fire kick once, restarting it if already playing (fine at
-- the capped AI fire rate — same reasoning as the shared Stage 1B gunshot Sound).
local function playAIFireAnim(record: NPCRecord): ()
    local a = record.anim
    if a == nil then
        return
    end
    local fire = a.fire
    if fire ~= nil then
        fire:Play(AI.WEAPON_FIRE_ANIM_FADE)
        fire.TimePosition = 0
    end
end

local function fireOneShot(record: NPCRecord)
    local target = record.target
    local troot  = targetRootOf(target)
    if target == nil or troot == nil then
        record.target = nil
        return
    end

    local offset = Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET, 0)
    local origin = record.root.Position + offset
    local baseDir = (troot.Position - origin)
    if baseDir.Magnitude < 1e-3 then
        return
    end
    local dir = coneSpread(baseDir.Unit, math.rad(AI.SHOT_SPREAD_DEGREES))

    local rayVec = dir * AI.SHOT_RANGE
    local result = workspace:Raycast(origin, rayVec, losParams)

    -- Stage 1B/1C: play the visible + audible shot FX and the fire kick for every
    -- shot, hit or miss. Reads only the muzzle / end position — hit calc unchanged.
    local muzzlePos: Vector3 = origin
    local fx = record.fx
    if fx ~= nil and fx.attachment.Parent ~= nil then
        muzzlePos = fx.attachment.WorldPosition
    end
    local endPos: Vector3 = if result ~= nil then result.Position else origin + rayVec
    playAIShotFx(record, muzzlePos, endPos)
    playAIFireAnim(record)

    if result == nil then
        return
    end

    local hitModel = result.Instance:FindFirstAncestorWhichIsA("Model")
    if hitModel == nil then
        return
    end
    local victim = Players:GetPlayerFromCharacter(hitModel :: Model)
    if victim == nil then
        return
    end

    -- `attacker` is intentionally omitted: AI is not a Player, so DamageService
    -- treats it as an environment kill (no friendly-fire guard, "environment" feed).
    DamageService:ApplyDamage({
        targetPlayer = victim,
        targetModel  = victim.Character,
        sourceName   = AI.NPC_NAME_PREFIX,
        damageType   = Constants.DamageType.Bullet,
        region       = Constants.HitRegion.Unknown,  -- flat SHOT_DAMAGE, no headshot multiplier
        hitPart      = result.Instance :: BasePart,
        hitPosition  = result.Position,
        hitDirection = dir,
        baseAmount   = AI.SHOT_DAMAGE,
    })

    if AI.DEBUG then
        Logger.debug("[AIService]", record.model.Name, "hit", victim.Name, "for", AI.SHOT_DAMAGE)
    end
end

-- Starts one burst on a detached task that stops safely on death / service destroy.
local function startBurst(record: NPCRecord)
    if record.firing or record.dead or not running then
        return
    end
    record.firing = true
    record.fireThread = task.spawn(function()
        local shots = math.random(AI.BURST_SHOTS_MIN, AI.BURST_SHOTS_MAX)
        if AI.DEBUG then
            local tname = record.target ~= nil and record.target.Name or "?"
            Logger.debug("[AIService]", record.model.Name, "burst x" .. tostring(shots), "at", tname)
        end
        for _ = 1, shots do
            if record.dead or not running or record.state ~= "Attack" or record.target == nil then
                break
            end
            fireOneShot(record)
            task.wait(AI.SECONDS_BETWEEN_SHOTS)
        end
        if not record.dead and running then
            task.wait(AI.SECONDS_BETWEEN_BURSTS)
        end
        record.firing = false
        record.fireThread = nil
    end)
end

-- ============================================================
-- Per-NPC think
-- ============================================================

local function setState(record: NPCRecord, newState: AIState)
    if record.state == newState then
        return
    end
    record.state = newState
    if AI.DEBUG then
        Logger.debug("[AIService]", record.model.Name, "state ->", newState)
    end
end

local function patrolDestination(record: NPCRecord): Vector3
    local squad = squads[record.squadId]
    if #patrolPoints > 0 and squad ~= nil then
        local pt = patrolPoints[((squad.patrolIndex - 1) % #patrolPoints) + 1]
        return pt.Position + record.slot
    end
    if squad ~= nil then
        return squad.spawnCFrame.Position + record.slot
    end
    return record.root.Position
end

local function thinkNPC(record: NPCRecord, now: number)
    if record.dead then
        return
    end
    local humanoid, root = record.humanoid, record.root
    if humanoid.Parent == nil or root.Parent == nil then
        return
    end

    -- ── Target acquisition / validation ──────────────────────────────────────
    if now >= record.nextTargetCheckClock then
        record.nextTargetCheckClock = now + AI.TARGET_RECHECK_INTERVAL
        local seen = findVisibleTarget(record)
        if seen ~= nil then
            record.target = seen
            local sroot = targetRootOf(seen)
            if sroot ~= nil then
                record.lastSeenPos = sroot.Position
            end
            record.lastSeenClock = now
        elseif record.target ~= nil then
            local troot = targetRootOf(record.target)
            local lost  = troot == nil
            if troot ~= nil and (troot.Position - root.Position).Magnitude > AI.LOSE_TARGET_RANGE then
                lost = true
            end
            if lost or (now - record.lastSeenClock) > AI.LAST_SEEN_CHASE_SECONDS then
                record.target = nil
                record.lastSeenPos = nil
            end
        end
    end

    -- ── Decide + act ────────────────────────────────────────────────────────
    local troot = targetRootOf(record.target)
    local tchar: Model? = if record.target ~= nil then record.target.Character else nil
    if troot ~= nil then
        record.lastSeenPos = troot.Position
        record.lastSeenClock = now
    end

    local goal: Vector3? = nil
    if troot ~= nil then
        goal = troot.Position
    elseif record.lastSeenPos ~= nil and (now - record.lastSeenClock) <= AI.LAST_SEEN_CHASE_SECONDS then
        goal = record.lastSeenPos
    end

    if goal ~= nil then
        local dist  = (goal - root.Position).Magnitude
        local inLos = troot ~= nil and tchar ~= nil and canSee(record, tchar, troot)
        if troot ~= nil and dist <= AI.ATTACK_RANGE and inLos then
            setState(record, "Attack")
            humanoid.WalkSpeed = AI.ATTACK_MOVE_SPEED
            humanoid:MoveTo(root.Position)  -- hold position
            if not record.firing then
                startBurst(record)
            end
        else
            setState(record, "Chase")
            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
            humanoid:MoveTo(goal + record.slot)
        end
        return
    end

    -- No target: patrol between points, or idle near the squad spawn.
    setState(record, (#patrolPoints > 0) and "Patrol" or "Idle")
    humanoid.WalkSpeed = AI.NPC_WALK_SPEED
    humanoid:MoveTo(patrolDestination(record))

    if record.isLeader and #patrolPoints > 0 then
        local squad = squads[record.squadId]
        if squad ~= nil then
            local pt = patrolPoints[((squad.patrolIndex - 1) % #patrolPoints) + 1]
            if (root.Position - pt.Position).Magnitude <= AI.PATROL_ARRIVE_DISTANCE then
                squad.patrolIndex += 1
            end
        end
    end
end

-- ============================================================
-- Death + cleanup
-- ============================================================

local function disconnectRecord(record: NPCRecord)
    if record.fireThread ~= nil then
        pcall(task.cancel, record.fireThread)
        record.fireThread = nil
    end
    record.firing = false
    -- Stage 1B/1C: drop FX + animation references. Emitters / light / sound /
    -- AnimationTracks / Animator / gun model are all children of the NPC model and
    -- die with it; the token-guarded light task.delay no-ops. The Humanoid.Running
    -- connection is in record.conns and is disconnected in the loop below.
    record.fx = nil
    record.anim = nil
    for _, conn in ipairs(record.conns) do
        conn:Disconnect()
    end
    table.clear(record.conns)
end

local function onNPCDied(record: NPCRecord)
    if record.dead then
        return
    end
    record.dead   = true
    record.state  = "Dead"
    record.target = nil
    disconnectRecord(record)
    npcs[record.model] = nil
    table.insert(pendingCleanup, record)

    if AI.DEBUG then
        Logger.debug("[AIService]", record.model.Name, "died — cleanup in", AI.DEATH_CLEANUP_DELAY, "s")
    end
    -- TODO (AI Stage 1B+): award a kill / score here (RewardService). Debt entry filed.

    -- Self-guarding one-shot: no-op if Destroy() already took the model.
    task.delay(AI.DEATH_CLEANUP_DELAY, function()
        local idx = table.find(pendingCleanup, record)
        if idx ~= nil then
            table.remove(pendingCleanup, idx)
        end
        if record.model.Parent ~= nil then
            record.model:Destroy()
        end
    end)
end

-- ============================================================
-- Spawning
-- ============================================================

local function activeCount(): number
    local n = 0
    for _, record in pairs(npcs) do
        if not record.dead then
            n += 1
        end
    end
    return n
end

local function spawnOne(worldCFrame: CFrame, squadId: number, isLeader: boolean, index: number, size: number): Model
    npcCounter += 1
    local model, humanoid, root = buildRig(worldCFrame)
    model.Name = AI.NPC_NAME_PREFIX .. "_" .. tostring(squadId) .. "_" .. tostring(npcCounter)
    model:SetAttribute("BR_AINpc", true)
    CollectionService:AddTag(model, Constants.TAG_DAMAGE_ENTITY)

    model.Parent = aiFolder or workspace
    -- Force server physics ownership so AI movement is fully authoritative.
    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    local record: NPCRecord = {
        model    = model,
        humanoid = humanoid,
        root     = root,
        squadId  = squadId,
        isLeader = isLeader,
        slot     = slotOffset(index, size),

        state        = "Idle",
        target       = nil,
        lastSeenPos  = nil,
        lastSeenClock= 0,

        nextThinkClock       = 0,
        nextTargetCheckClock = 0,

        firing    = false,
        fireThread= nil,
        conns     = {},
        fx        = nil,
        anim      = nil,
        dead      = false,
    }

    local diedConn: RBXScriptConnection
    diedConn = humanoid.Died:Connect(function()
        diedConn:Disconnect()
        onNPCDied(record)
    end)
    table.insert(record.conns, diedConn)

    npcs[model] = record

    -- Presentation setup, each pcall'd so a Studio asset quirk can never block a
    -- grunt from spawning. Order matters:
    --   1C weapon first  — so setupAICombatFx's attachment can land on the Barrel
    --   1B muzzle FX
    --   1C animation last — plays the idle pose on a rig that already has the gun
    local okWeapon, weaponErr = pcall(attachAIWorldWeapon, record)
    if not okWeapon then
        Logger.warn("[AIService] attachAIWorldWeapon failed for", model.Name, "-", tostring(weaponErr))
    end

    local okFx, fxErr = pcall(setupAICombatFx, record)
    if not okFx then
        Logger.warn("[AIService] setupAICombatFx failed for", model.Name, "-", tostring(fxErr))
    end

    local okAnim, animErr = pcall(setupAIAnimation, record)
    if not okAnim then
        Logger.warn("[AIService] setupAIAnimation failed for", model.Name, "-", tostring(animErr))
    end

    return model
end

-- Public: create up to `squadSize` NPCs near `spawnCFrame`. Clamped so the total
-- never exceeds Constants.AI.MAX_ACTIVE_NPCS. Returns the spawned models.
local function spawnSquad(spawnCFrame: CFrame?, squadSize: number?): { Model }
    assert(spawnCFrame == nil or typeof(spawnCFrame) == "CFrame",
        "[AIService] SpawnSquad: spawnCFrame must be a CFrame or nil")
    assert(squadSize == nil or (type(squadSize) == "number" and squadSize >= 1),
        "[AIService] SpawnSquad: squadSize must be a number >= 1 or nil")

    if not started or not running then
        Logger.warn("[AIService] SpawnSquad called before Start() / after Destroy() — ignored")
        return {}
    end

    local origin: CFrame
    if spawnCFrame ~= nil then
        origin = spawnCFrame
    elseif #spawnParts > 0 then
        origin = spawnParts[1].CFrame
    else
        origin = CFrame.new(0, 5, 0)
    end

    local want = math.floor(squadSize or AI.DEFAULT_SQUAD_SIZE)
    local room = AI.MAX_ACTIVE_NPCS - activeCount()
    local size = math.clamp(want, 0, math.max(room, 0))
    if size <= 0 then
        if AI.DEBUG then
            Logger.debug("[AIService] SpawnSquad: at MAX_ACTIVE_NPCS (" .. tostring(AI.MAX_ACTIVE_NPCS) .. ") — nothing spawned")
        end
        return {}
    end

    squadCounter += 1
    local squadId = squadCounter
    squads[squadId] = {
        id          = squadId,
        spawnCFrame = origin,
        patrolIndex = 1,
    }

    local models: { Model } = {}
    for i = 1, size do
        if not running then
            break
        end
        local memberCFrame = origin * CFrame.new(slotOffset(i, size))
        table.insert(models, spawnOne(memberCFrame, squadId, i == 1, i, size))
        if i < size then
            task.wait(AI.SPAWN_DELAY_BETWEEN_NPCS)
        end
    end

    if AI.DEBUG then
        Logger.debug("[AIService] spawned squad", squadId, "with", #models, "grunt(s) — active", activeCount())
    end
    return models
end

-- ============================================================
-- Main loop — one throttled updater for every NPC
-- ============================================================

local function mainLoop()
    while running do
        local now = os.clock()
        for model, record in pairs(npcs) do
            if not record.dead and now >= record.nextThinkClock then
                record.nextThinkClock = now + AI.THINK_INTERVAL
                local ok, err = pcall(thinkNPC, record, now)
                if not ok then
                    Logger.warn("[AIService] think error for", model.Name, "-", tostring(err))
                end
            end
        end
        task.wait(AI.THINK_INTERVAL)
    end
end

-- Runs the one-time Studio opening spawn (idempotent via didStudioAutoSpawn). Safe
-- to call again once spawn parts appear — e.g. TestAreaBuilder creating
-- Workspace/AISpawns after this service already started (script order is not fixed).
local function studioAutoSpawn()
    if didStudioAutoSpawn or not running then
        return
    end
    if not (RunService:IsStudio() and AI.SPAWN_ON_SERVER_START_IN_STUDIO == true) then
        return
    end
    if #spawnParts == 0 then
        return
    end
    didStudioAutoSpawn = true
    task.spawn(function()
        for i = 1, AI.MAX_SQUADS do
            if not running or activeCount() >= AI.MAX_ACTIVE_NPCS then
                break
            end
            local part = spawnParts[((i - 1) % #spawnParts) + 1]
            spawnSquad(part.CFrame, AI.DEFAULT_SQUAD_SIZE)
        end
    end)
end

-- ============================================================
-- Public API
-- ============================================================

local AIService = {}

-- Idempotent. Discovers Workspace folders, starts the single update loop, and (in
-- Studio, if enabled) spawns the opening squads.
function AIService.Start(): ()
    if started then
        if AI.DEBUG then
            Logger.debug("[AIService] Start() called again — already running")
        end
        return
    end
    if AI.ENABLED ~= true then
        Logger.debug("[AIService] disabled via Constants.AI.ENABLED")
        return
    end

    started = true
    running = true

    local folder = ensureAIFolder()
    aiFolder = folder
    losParams.FilterDescendantsInstances = { folder }

    spawnParts,   warnedNoSpawns = collectParts(AI.SPAWN_FOLDER_NAME, warnedNoSpawns)
    patrolPoints, warnedNoPatrol = collectParts(AI.PATROL_FOLDER_NAME, warnedNoPatrol)

    mainThread = task.spawn(mainLoop)

    -- Re-scan when an AISpawns / AIPatrolPoints folder appears after we started
    -- (server script order is not guaranteed; TestAreaBuilder may build them later).
    local addedConn = workspace.ChildAdded:Connect(function(child: Instance)
        if not child:IsA("Folder") then
            return
        end
        if child.Name == AI.SPAWN_FOLDER_NAME then
            spawnParts, warnedNoSpawns = collectParts(AI.SPAWN_FOLDER_NAME, warnedNoSpawns)
            studioAutoSpawn()
        elseif child.Name == AI.PATROL_FOLDER_NAME then
            patrolPoints, warnedNoPatrol = collectParts(AI.PATROL_FOLDER_NAME, warnedNoPatrol)
        end
    end)
    table.insert(serviceConns, addedConn)

    if RunService:IsStudio() and AI.SPAWN_ON_SERVER_START_IN_STUDIO == true and #spawnParts == 0 then
        Logger.warn("[AIService] SPAWN_ON_SERVER_START_IN_STUDIO is on but Workspace." .. AI.SPAWN_FOLDER_NAME .. " has no spawn parts yet — will spawn if one appears")
    end
    studioAutoSpawn()

    Logger.debug("[AIService] started — spawns:", #spawnParts, "patrol points:", #patrolPoints)
end

-- Public wrapper (asserts live in spawnSquad).
function AIService.SpawnSquad(spawnCFrame: CFrame?, squadSize: number?): { Model }
    return spawnSquad(spawnCFrame, squadSize)
end

-- Number of NPCs that are alive and thinking.
function AIService.GetActiveNPCCount(): number
    return activeCount()
end

-- Stops the loop and every burst, disconnects all connections, destroys all NPC
-- models (live and pending), and clears state. Safe to call repeatedly.
function AIService.Destroy(): ()
    running = false
    started = false
    didStudioAutoSpawn = false

    for _, conn in ipairs(serviceConns) do
        conn:Disconnect()
    end
    table.clear(serviceConns)

    if mainThread ~= nil then
        pcall(task.cancel, mainThread)
        mainThread = nil
    end

    for _, record in pairs(npcs) do
        disconnectRecord(record)
        if record.model.Parent ~= nil then
            record.model:Destroy()
        end
    end
    for _, record in ipairs(pendingCleanup) do
        disconnectRecord(record)
        if record.model.Parent ~= nil then
            record.model:Destroy()
        end
    end

    table.clear(npcs)
    table.clear(squads)
    table.clear(pendingCleanup)
    table.clear(spawnParts)
    table.clear(patrolPoints)

    -- Stage 1B tracer holder parts are parented under aiFolder, so destroying it
    -- removes any that Debris has not yet collected. Sweep first for robustness in
    -- case one was ever re-parented out.
    for _, inst in ipairs(workspace:GetChildren()) do
        if inst:GetAttribute("BR_AITracer") == true then
            inst:Destroy()
        end
    end
    if aiFolder ~= nil and aiFolder.Parent ~= nil then
        aiFolder:Destroy()
    end
    aiFolder = nil

    Logger.debug("[AIService] destroyed — all NPCs, loops and connections cleared")
end

-- ============================================================
-- Bootstrap — this repo has no ServerInit; every *.server.lua service self-starts.
-- ============================================================

AIService.Start()
