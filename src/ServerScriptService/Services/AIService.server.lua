--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > AIService
--
-- AI Stage 1A — basic server-owned squad NPC foundation.
--
-- Spawns simple R6 rifleman "grunt" squads from Workspace/AISpawns, patrols
-- Workspace/AIPatrolPoints, detects players by server raycast line-of-sight,
-- chases visible targets, and burst-fires simple server raycasts at them.
-- Easy to kill alone, dangerous in numbers — battlefield filler, not tactical AI.
--
-- ALL decisions are server-side. No remotes, no client AI scripts, no client
-- damage decisions. All tuning is in Constants.AI.
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
-- Deferred (see docs/TECHNICAL_DEBT.md — AI Stage 1A): PathfindingService,
-- ragdoll on AI death, rewards/points/killstreaks, AI types, cover/flanking,
-- replicated muzzle flash / sound, AI animations.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

-- DamageService is a sibling ModuleScript; the only in-tree caller besides GunService.
local DamageService = require(script.Parent:WaitForChild("DamageService"))

-- Untyped view of the tuning table (heterogeneous fields; matches the pattern used
-- by TestAreaBuilder's `local CFG = Constants.DEV_TEST_AREA :: any`).
local AI = Constants.AI :: any

-- ============================================================
-- Types
-- ============================================================

type AIState = "Idle" | "Patrol" | "Chase" | "Attack" | "Dead"

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

    local result = workspace:Raycast(origin, dir * AI.SHOT_RANGE, losParams)
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
        dead      = false,
    }

    local diedConn: RBXScriptConnection
    diedConn = humanoid.Died:Connect(function()
        diedConn:Disconnect()
        onNPCDied(record)
    end)
    table.insert(record.conns, diedConn)

    npcs[model] = record
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
