--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > AIService
--
-- AI Stage 1A — basic server-owned squad NPC foundation.
-- AI Stage 1B — combat feedback FX (muzzle flash / smoke / light / tracer / 3D sound).
-- AI Stage 1C — grunt weapon model + third-person animation (same gun/poses as players).
-- AI Stage 1D — face the target while engaging + duck into cover between bursts.
-- AI Stage 1E — fight from cover, break to cover the instant you're hit, and
--               flank a stale last-known position instead of giving up.
-- AI Stage 1F — crouch while in cover + retract the gun/arm away from a near wall.
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
-- Stage 1D face + cover (Constants.AI Stage 1D fields): while a grunt is walking
-- (Chase / Cover / Patrol) it keeps Humanoid.AutoRotate on and faces the way it
-- moves. In the stationary Attack state thinkNPC turns AutoRotate OFF and hands
-- facing to faceToward(), which lerps the HumanoidRootPart to point the rifle at
-- the player — done only there because writing the root CFrame every think while
-- also walking stops the Humanoid dead. After each burst startBurst arms
-- record.coverUntil; while it is in the future thinkNPC runs a "Cover" branch that
-- moves the grunt to findCoverPoint() (a raycast-sampled spot that breaks LOS,
-- else a plain retreat) and holds there until it expires, then re-peeks and fires
-- — a per-grunt peek/shoot/hide loop. No squad coordination, no tagged cover
-- objects, no pathfinding.
--
-- Stage 1F crouch + weapon-vs-wall (Constants.AI Stage 1F fields): while in the
-- Cover state a grunt plays the player's own third-person crouch idle clip
-- (Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed.CrouchIdle); every think
-- updateWeaponCollision() casts a forward chest-ray and, when a wall is within
-- GUN_COLLISION_DISTANCE, additively pulls the welded gun (grip Motor6D C1) and
-- the Right Shoulder Motor6D C0 back toward the body so nothing pokes through.
-- findCoverPoint / findFightingPosition results are pulled WALL_STANDOFF studs
-- clear of walls. The player first-person version of this is a separate client task.
--
-- Stage 1E fight-from-cover / react / flank (Constants.AI Stage 1E fields): the
-- Attack branch first walks to findFightingPosition() (a spot within
-- FIGHT_SEEK_DISTANCE that keeps LOS to the target AND has an obstacle within
-- COVER_ADJACENT_RADIUS) before planting — nil result → hold in place as before.
-- A service-level CombatEvents.DamageDealt listener arms record.coverUntil the
-- moment a grunt is hit and, if a player did it, makes that player the target.
-- When a target has been unseen longer than LAST_SEEN_CHASE_SECONDS (up to
-- SEARCH_DURATION) the grunt enters a "Search" state and approaches lastSeenPos on
-- an arc via flankPointFor() (per-grunt flankSide alternates), converging on the
-- spot; after SEARCH_DURATION with no sighting it drops back to patrol.
--
-- Deferred (see docs/TECHNICAL_DEBT.md — AI Stage 1A..1F): PathfindingService,
-- ragdoll on AI death, rewards/points/killstreaks, AI types, real squad
-- cover/flanking coordination, suppression, jump/climb animation, reload
-- animation, final flash/smoke/sound art, tracer pooling, extracting the
-- WorldWeaponService attach body into a shared module.

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
local Types      = require(Modules:WaitForChild("Types"))

-- DamageService is a sibling ModuleScript; the only in-tree caller besides GunService.
local DamageService = require(script.Parent:WaitForChild("DamageService"))
-- CombatEvents is a sibling ModuleScript holding server-to-server BindableEvents
-- (DamageService is the sole producer). Stage 1E listens to DamageDealt so a grunt
-- reacts the instant it is shot.
local CombatEvents = require(script.Parent:WaitForChild("CombatEvents"))
-- Stage 1G: the same physics-ragdoll service DummyService uses on dummy death, so a
-- dead grunt flops with the shot's knockback instead of freezing then vanishing.
local RagdollService = require(script.Parent:WaitForChild("RagdollService"))

-- Stage 1H: RespawnBots — created by RemoteSetup before any Service needs it.
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local RespawnBots  = Remotes:WaitForChild("RespawnBots") :: RemoteEvent

-- Untyped views of the tuning tables (heterogeneous fields; matches the pattern
-- used by TestAreaBuilder's `local CFG = Constants.DEV_TEST_AREA :: any`).
local AI   = Constants.AI :: any
local FX   = Constants.AI_COMBAT_FX :: any
local TUNE = Constants.AI_COMBAT_TUNING :: any  -- AI Stage 1C: reaction/aim-ramp/suppression tuning

-- ============================================================
-- Types
-- ============================================================

type AIState = "Idle" | "Patrol" | "Chase" | "Attack" | "Cover" | "Search" | "Dead"

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

    coverUntil : number,    -- os.clock() deadline; > now → in the Cover branch (0 = not covering)
    coverPoint : Vector3?,  -- LOS-broken hide spot for Cover, cleared on return to Attack
    fightPoint : Vector3?,  -- Stage 1E: cover-adjacent spot that keeps LOS, for Attack
    flankSide  : number,    -- Stage 1E: -1 / +1, which way this grunt arcs into a stale last-known pos

    nextThinkClock      : number,
    nextTargetCheckClock: number,

    firing    : boolean,
    fireThread: thread?,
    conns     : { RBXScriptConnection },
    fx        : AICombatFx?,
    anim      : AIAnim?,

    -- Stage 1F
    crouched           : boolean,          -- currently in the crouch pose
    crouchTrack        : AnimationTrack?,  -- the player's CrouchIdle clip, loaded lazily
    retract            : number,           -- 0..1 lerped wall proximity (gun/arm pull-back amount)
    rightShoulder      : Motor6D?,         -- the Right Shoulder joint (base pose + retract offset)
    rightShoulderBaseC0: CFrame,           -- its C0 before any retract offset
    gripMotor          : Motor6D?,         -- the welded-gun grip Motor6D (Handle -> Right Arm)
    gripBaseC1         : CFrame,           -- its C1 before any retract offset

    -- Stage 1G — death ragdoll
    lastHit   : Types.DamageInfo?,         -- most recent accepted hit on this grunt (for the death impulse)

    -- Stage 1H — combat realism (per-grunt flavor; unrelated to the Stage 1C
    -- engagement-freshness ramp below — the two multiply together in fireOneShot).
    aimSkill     : number,  -- per-grunt spread multiplier, rolled once at spawn

    -- AI Stage 1C — fair combat tuning. NOTE: this file keeps the existing `target`
    -- field name above rather than the spec's `currentTarget` — same role, renaming
    -- ~15 existing call sites for a cosmetic difference was out of scope for a
    -- tuning-only pass (see docs/TECHNICAL_DEBT.md "AI Stage 1C").
    firstSawTargetAt    : number,    -- os.clock() the CURRENT target was first acquired (0 = no target seen yet)
    lastSawTargetAt     : number,    -- os.clock() of the most recent think the target was actually in LOS
    lastKnownTargetPosition: Vector3?, -- mirrors lastSeenPos; kept under the spec's field name too
    reactionReadyAt     : number,    -- os.clock() before which this grunt will not fire at its current target
    reactionAnnouncedAt : number,    -- de-dupe: the reactionReadyAt value the "reaction-ready" log already fired for
    lastTargetSwitchAt  : number,    -- os.clock() of the last time `target` changed to a DIFFERENT player
    suppressedUntil     : number,    -- os.clock() deadline; > now → SUPPRESSED_SPREAD_MULTIPLIER applies
    recentlyDamagedUntil: number,    -- os.clock() deadline; > now → next reaction uses the fast "recently damaged" tier
    visibleTargetTime   : number,    -- seconds the current target has been continuously visible, clamped to MAX_TRACKED_VISIBLE_TIME
    lastDamageCallAt    : number,    -- os.clock() of the last accepted DamageService call (MIN_TIME_BETWEEN_DAMAGE_CALLS guard)
    aimBand             : string?,   -- last logged ramp band ("Fresh"/"Settling"/"Settled"), DEBUG-log de-dupe only

    dead      : boolean,
}

type SquadRecord = {
    id          : number,
    spawnCFrame : CFrame,
    patrolIndex : number,

    -- AI Stage 1C — fair combat tuning
    alerted             : boolean,             -- sticky: true once any member has engaged a live target this squad's life
    attackerSlots       : { [Model]: boolean }, -- grunts currently allowed to fire (MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD)
    nextAttackSlotRecheck: number,              -- os.clock() of the next updateSquadAttackSlots() pass
}

-- ============================================================
-- State
-- ============================================================

local started   = false
local running   = false
local mainThread: thread? = nil
local serviceConns: { RBXScriptConnection } = {}
local didAutoSpawn = false
-- Stage 1H: shared server-wide cooldown gate for the RespawnBots remote.
local lastManualRespawnClock = -math.huge

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

-- Builds a standard R6 rig at the given world CFrame.
-- Returns (model, humanoid, root, rightShoulderMotor).
local function buildRig(worldCFrame: CFrame): (Model, Humanoid, BasePart, Motor6D)
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
    local rightShoulder = makeMotor("Right Shoulder", torso, rArm,
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
    -- Stage 1D: AutoRotate is left ON (default) so walking grunts face the way they
    -- move. thinkNPC turns it OFF only in the stationary Attack state and hands
    -- facing to faceToward() there — writing HumanoidRootPart.CFrame every think
    -- while also walking would stomp the Humanoid's movement.
    humanoid.Parent = model

    -- Stage 1C: an Animator is required to LoadAnimation on this rig.
    local animator = Instance.new("Animator")
    animator.Parent = humanoid

    model.PrimaryPart = root
    model:PivotTo(worldCFrame)

    return model, humanoid, root, rightShoulder
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

-- AI Stage 1C: three-tier reaction delay. Called only when a grunt's live target
-- actually changes (fresh acquisition, or a different attacker via the hit-reaction
-- listener) — not on every think — so an ongoing firefight never re-hesitates
-- mid-engagement. Tier priority: recently damaged (already under fire — react fast)
-- > alert (this squad has made contact before) > unaware (first contact). Squad-,
-- not grunt-, level alertness per the spec's "squad/AI is unaware/alert" wording:
-- one grunt spotting a threat puts the whole squad on alert, even before its own
-- delay elapses — realistic (yelling/pointing), and simple (sticky, never resets).
local function armReaction(record: NPCRecord, now: number)
    if TUNE.ENABLED ~= true then
        -- Master switch off: revert to "fires the instant it can" (pre-Stage-1C).
        record.reactionReadyAt = now
        record.reactionAnnouncedAt = now
        return
    end
    local squad = squads[record.squadId]
    local lo: number, hi: number, tier: string
    if now < record.recentlyDamagedUntil then
        lo, hi, tier = TUNE.REACTION_TIME_RECENTLY_DAMAGED_MIN :: number, TUNE.REACTION_TIME_RECENTLY_DAMAGED_MAX :: number, "RecentlyDamaged"
    elseif squad ~= nil and squad.alerted then
        lo, hi, tier = TUNE.REACTION_TIME_ALERT_MIN :: number, TUNE.REACTION_TIME_ALERT_MAX :: number, "Alert"
    else
        lo, hi, tier = TUNE.REACTION_TIME_UNAWARE_MIN :: number, TUNE.REACTION_TIME_UNAWARE_MAX :: number, "Unaware"
    end
    local delay = lo + math.random() * (hi - lo)
    record.reactionReadyAt = now + delay
    record.reactionAnnouncedAt = -1  -- allow the "reaction-ready" log to fire again for this engagement
    if TUNE.DEBUG == true then
        Logger.debug("[AIService]", record.model.Name, "reaction delay:", tier, string.format("%.2fs", delay))
    end
    if squad ~= nil then
        squad.alerted = true
    end
end

-- AI Stage 1C: "Fresh" / "Settling" / "Settled" aim-ramp band for DEBUG logging
-- only (fireOneShot computes the actual continuous multiplier) — keeps the log to
-- one line per band crossing instead of every think.
local function aimBandFor(t: number): string
    if t >= 0.9 then
        return "Settled"
    elseif t >= 0.15 then
        return "Settling"
    end
    return "Fresh"
end

-- AI Stage 1C: caps how many grunts in one squad actively fire at once
-- (MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD) so a 3-grunt squad doesn't all laser the
-- player simultaneously — the extras hold their planted Attack position (still
-- tracking/facing the player) without pulling the trigger until a slot opens.
-- Sticky: an existing holder keeps its slot as long as it stays eligible, so slots
-- don't flicker between squadmates every recheck; only vacated slots are refilled.
-- Cheap: re-evaluated at most once per ATTACK_SLOT_RECHECK_INTERVAL per squad,
-- guarded below, and squads are small (MAX_ACTIVE_NPCS = 12 total).
local function updateSquadAttackSlots(squad: SquadRecord, now: number)
    if now < squad.nextAttackSlotRecheck then
        return
    end
    squad.nextAttackSlotRecheck = now + (TUNE.ATTACK_SLOT_RECHECK_INTERVAL :: number)
    local maxSlots = TUNE.MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD :: number

    local function eligible(record: NPCRecord?): boolean
        return record ~= nil and not record.dead and record.state == "Attack" and record.target ~= nil
    end

    -- Drop holders that are no longer eligible (dead, lost target, left Attack).
    for model in pairs(squad.attackerSlots) do
        if not eligible(npcs[model]) then
            squad.attackerSlots[model] = nil
        end
    end

    -- Fill any remaining slots from eligible squad members that don't hold one yet.
    local held = 0
    for _ in pairs(squad.attackerSlots) do
        held += 1
    end
    if held < maxSlots then
        for model, record in pairs(npcs) do
            if held >= maxSlots then
                break
            end
            if record.squadId == squad.id and squad.attackerSlots[model] == nil and eligible(record) then
                squad.attackerSlots[model] = true
                held += 1
            end
        end
    end
end

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

    -- Stage 1F: remember the grip joint + its rest C1 so updateWeaponCollision can
    -- additively pull the gun toward the body near a wall.
    record.gripMotor  = motor
    record.gripBaseC1 = motor.C1
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

    -- Stage 1F: preload (don't play) the crouch pose — the player's own
    -- third-person CrouchIdle, with the Constants.AI fallback if that table moves.
    if AI.CROUCH_IN_COVER == true then
        local crouchId: any = AI.CROUCH_IDLE_ANIM_ID
        local okTbl, fromTable = pcall(function()
            return (Constants :: any).MOVEMENT_ANIMATION_IDS.R6.Unarmed.CrouchIdle
        end)
        if okTbl and typeof(fromTable) == "string" and fromTable ~= "" then
            crouchId = fromTable
        end
        if typeof(crouchId) == "string" and crouchId ~= "" then
            record.crouchTrack = loadTrack(animator, crouchId, true, Enum.AnimationPriority.Action)
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

    local now = os.clock()

    -- Stage 1H: per-grunt aim skill (rolled at spawn) plus extra spread against a
    -- target that is actually moving — real aim tracks a sprinting/strafing target
    -- worse than a stationary one. AssemblyLinearVelocity reads the live HRP.
    local spreadDeg = (AI.SHOT_SPREAD_DEGREES :: number) * record.aimSkill
    if AI.AIM_MOVING_TARGET_SPREAD_ENABLED == true then
        local speed = troot.AssemblyLinearVelocity.Magnitude
        local ref   = AI.AIM_MOVING_TARGET_SPEED_REF :: number
        spreadDeg  += math.clamp(speed / ref, 0, 1) * (AI.AIM_MOVING_TARGET_SPREAD_BONUS_DEG :: number)
    end

    -- AI Stage 1C: aim ramp — a freshly-acquired target gets INITIAL_SPREAD_MULTIPLIER
    -- (wide, "miss shots at first"), easing toward FINAL_SPREAD_MULTIPLIER as
    -- record.visibleTargetTime (continuous LOS on the CURRENT target) approaches
    -- AIM_SETTLE_TIME ("become dangerous if the player stays exposed"). Multiplies
    -- with aimSkill/moving-target above — three independent factors, not a
    -- replacement for either. Then a temporary SUPPRESSED_SPREAD_MULTIPLIER while
    -- record.suppressedUntil is in the future (a recent hit rattled this grunt).
    if TUNE.ENABLED == true then
        local settle = (TUNE.AIM_SETTLE_TIME :: number)
        local rampT  = if settle > 0 then math.clamp(record.visibleTargetTime / settle, 0, 1) else 1
        local initM, finalM = (TUNE.INITIAL_SPREAD_MULTIPLIER :: number), (TUNE.FINAL_SPREAD_MULTIPLIER :: number)
        spreadDeg *= initM + (finalM - initM) * rampT
        if now < record.suppressedUntil then
            spreadDeg *= (TUNE.SUPPRESSED_SPREAD_MULTIPLIER :: number)
        end
    end

    local dir = coneSpread(baseDir.Unit, math.rad(spreadDeg))

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

    -- AI Stage 1C: safety net, independent of burst timing — never call DamageService
    -- for this grunt more often than MIN_TIME_BETWEEN_DAMAGE_CALLS, even if a future
    -- tuning change ever drops SECONDS_BETWEEN_SHOTS below it. DamageService itself
    -- is unchanged; this only decides whether AIService calls it.
    if now - record.lastDamageCallAt < (TUNE.MIN_TIME_BETWEEN_DAMAGE_CALLS :: number) then
        return
    end
    record.lastDamageCallAt = now

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

-- Stage 1H: a grunt that has taken damage down toward AI.LOW_HEALTH_RATIO stays in
-- cover longer than a fresh one on the same COVER_DURATION timer — real fighters
-- get warier once they're actually hurt, not just once they've fired a burst.
local function coverDurationFor(record: NPCRecord): number
    local base = AI.COVER_DURATION :: number
    local humanoid = record.humanoid
    if humanoid.MaxHealth <= 0 then
        return base
    end
    if humanoid.Health / humanoid.MaxHealth <= (AI.LOW_HEALTH_RATIO :: number) then
        return base * (AI.LOW_HEALTH_COVER_MULTIPLIER :: number)
    end
    return base
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
        -- Stage 1D: arm the cover window so thinkNPC ducks this grunt away before
        -- the next burst. The burst loop already bailed on state ~= "Attack".
        if not record.dead and running and AI.TAKE_COVER == true then
            record.coverUntil = os.clock() + coverDurationFor(record)
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

-- Stage 1D: lerp the HumanoidRootPart to look at `worldPos` (flattened to the
-- grunt's own Y so the rig never tilts). No-op if facing is disabled or the point
-- is basically on top of the grunt. Safe on a server-owned, stationary NPC.
local function faceToward(record: NPCRecord, worldPos: Vector3)
    if AI.FACE_TARGET ~= true then
        return
    end
    local root = record.root
    local flat = Vector3.new(worldPos.X, root.Position.Y, worldPos.Z)
    if (flat - root.Position).Magnitude < 0.1 then
        return
    end
    root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flat), AI.FACE_TURN_ALPHA)
end

-- Stage 1F: nudge `pos` back along `awayDir` if a wall is closer than WALL_STANDOFF
-- in the aim direction or on either flank, so the grunt does not stand flush
-- against the wall it is using (which is how its arm ends up poking through).
local function pullFromWalls(pos: Vector3, awayDir: Vector3): Vector3
    local standoff = AI.WALL_STANDOFF :: number
    if standoff <= 0 or awayDir.Magnitude < 0.1 then
        return pos
    end
    local eye  = Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET, 0)
    local unit = awayDir.Unit
    local worst = 0
    for _, deg in ipairs({ 180, 140, -140, 90, -90 }) do  -- 180 = straight toward the target
        local dir = (CFrame.Angles(0, math.rad(deg), 0) * unit).Unit
        local hit = workspace:Raycast(pos + eye, dir * standoff, losParams)
        if hit ~= nil then
            worst = math.max(worst, standoff - hit.Distance)
        end
    end
    if worst <= 0 then
        return pos
    end
    return pos + unit * worst
end

-- Stage 1D / 1F: pick a spot roughly COVER_SEEK_DISTANCE studs from the grunt that
-- breaks line of sight to `targetPos`. Samples a ring of angles off the
-- away-from-target vector; of the candidates whose LOS to the target is blocked,
-- prefers the one whose blocking obstacle is *closest* (within COVER_HUG_DISTANCE)
-- so the grunt ends up hugging the far side of that obstacle, fully out of the
-- player's view — not merely behind some distant wall. Falls back to the first
-- occluded candidate, then to a plain retreat point. Never returns nil.
local function findCoverPoint(record: NPCRecord, targetPos: Vector3): Vector3
    local root = record.root
    local eye  = Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET, 0)
    local flatAway = Vector3.new(root.Position.X - targetPos.X, 0, root.Position.Z - targetPos.Z)
    if flatAway.Magnitude < 0.1 then
        flatAway = Vector3.new(0, 0, 1)
    end
    local awayDir  = flatAway.Unit
    local distance = AI.COVER_SEEK_DISTANCE
    local hug      = AI.COVER_HUG_DISTANCE :: number

    local tchar: Model? = if record.target ~= nil then record.target.Character else nil
    local bestPos: Vector3? = nil
    local bestObstacleDist = math.huge
    local fallbackPos: Vector3? = nil

    for _, deg in ipairs(AI.COVER_SAMPLE_ANGLES) do
        local dir = (CFrame.Angles(0, math.rad(deg), 0) * awayDir).Unit
        local candidate = root.Position + dir * distance
        local result = workspace:Raycast(candidate + eye, (targetPos + eye) - (candidate + eye), losParams)
        if result ~= nil and (tchar == nil or not result.Instance:IsDescendantOf(tchar)) then
            -- Something occludes this spot. result.Distance is how far that obstacle
            -- is from the candidate — small = the grunt would be tucked right behind it.
            if fallbackPos == nil then
                fallbackPos = candidate
            end
            if result.Distance <= hug and result.Distance < bestObstacleDist then
                bestObstacleDist = result.Distance
                bestPos = candidate
            end
        end
    end

    local chosen = bestPos or fallbackPos or (root.Position + awayDir * distance)
    return pullFromWalls(chosen, awayDir)
end

-- Stage 1E: true if there is something to hug within COVER_ADJACENT_RADIUS of
-- `fromPos` on the side facing away from the target (or either flank of it).
local function hasNearbyCover(fromPos: Vector3, targetPos: Vector3): boolean
    local eye = Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET * 0.5, 0)
    local flatAway = Vector3.new(fromPos.X - targetPos.X, 0, fromPos.Z - targetPos.Z)
    if flatAway.Magnitude < 0.1 then
        return false
    end
    local away  = flatAway.Unit
    local reach = AI.COVER_ADJACENT_RADIUS
    for _, deg in ipairs({ 0, 60, -60, 120, -120 }) do
        local dir = (CFrame.Angles(0, math.rad(deg), 0) * away).Unit
        if workspace:Raycast(fromPos + eye, dir * reach, losParams) ~= nil then
            return true
        end
    end
    return false
end

-- Stage 1E: a spot within FIGHT_SEEK_DISTANCE that keeps line of sight to the
-- target AND sits beside cover. Returns nil when none qualifies (caller then just
-- holds where it is — the pre-1E behaviour). Samples FIGHT_SAMPLE_ANGLES off the
-- away-from-target vector at two radii, near first.
local function findFightingPosition(record: NPCRecord, targetPos: Vector3): Vector3?
    local root = record.root
    local eye  = Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET, 0)
    local flatAway = Vector3.new(root.Position.X - targetPos.X, 0, root.Position.Z - targetPos.Z)
    if flatAway.Magnitude < 0.1 then
        return nil
    end
    local awayDir = flatAway.Unit
    local tchar: Model? = if record.target ~= nil then record.target.Character else nil

    for _, radius in ipairs({ AI.FIGHT_SEEK_DISTANCE * 0.5, AI.FIGHT_SEEK_DISTANCE }) do
        for _, deg in ipairs(AI.FIGHT_SAMPLE_ANGLES) do
            local dir = (CFrame.Angles(0, math.rad(deg), 0) * awayDir).Unit
            local c = root.Position + dir * radius
            -- (a) still sees the target: ray reaches the target character, or hits nothing
            local losHit = workspace:Raycast(c + eye, (targetPos + eye) - (c + eye), losParams)
            local seesTarget = losHit == nil or (tchar ~= nil and losHit.Instance:IsDescendantOf(tchar))
            if seesTarget and hasNearbyCover(c, targetPos) then
                return pullFromWalls(c, awayDir)
            end
        end
    end
    return nil
end

-- Stage 1E: an arc approach to `lastSeenPos` — wide lateral offset when far,
-- converging on the spot as the grunt closes. flankSide picks left / right so
-- squad members come in from opposite sides.
local function flankPointFor(record: NPCRecord, lastSeenPos: Vector3): Vector3
    local root = record.root
    local flat = Vector3.new(lastSeenPos.X - root.Position.X, 0, lastSeenPos.Z - root.Position.Z)
    if flat.Magnitude < 0.1 then
        return lastSeenPos
    end
    local dir  = flat.Unit
    local perp = Vector3.new(-dir.Z, 0, dir.X) * record.flankSide
    local lateral = (AI.FLANK_OFFSET_DISTANCE :: number)
        * math.clamp(flat.Magnitude / (AI.FLANK_CURVE_DISTANCE :: number), 0, 1)
    return lastSeenPos + perp * lateral
end

-- Stage 1F: crossfade the grunt between its rifle idle stance and the player's
-- crouch pose. Idempotent (record.crouched). Only one of the two plays at a time.
local function setCrouched(record: NPCRecord, on: boolean)
    if record.crouched == on then
        return
    end
    record.crouched = on
    local fade: number = AI.CROUCH_ANIM_FADE
    local ct = record.crouchTrack
    local wi = record.anim and record.anim.weaponIdle or nil
    if on then
        if ct ~= nil then ct:Play(fade) end
        if wi ~= nil then wi:Stop(fade) end
    else
        if ct ~= nil then ct:Stop(fade) end
        if wi ~= nil then wi:Play(fade) end
    end
end

-- Stage 1F: cast a forward chest-ray; when a wall is within GUN_COLLISION_DISTANCE
-- additively pull the welded gun (grip C1) and the Right Shoulder joint (C0) back
-- toward the body so the rifle / arm never poke through. Composes on top of the
-- Animator's Transform and restores cleanly when clear. Lerped, so it eases in.
local function updateWeaponCollision(record: NPCRecord)
    local shoulder = record.rightShoulder
    if shoulder == nil or AI.GUN_COLLISION_ENABLED ~= true then
        return
    end

    local maxDist = (AI.GUN_COLLISION_DISTANCE :: number)
    local torso   = record.model:FindFirstChild("Torso")
    local from    = (torso ~= nil and torso:IsA("BasePart"))
        and (torso :: BasePart).Position
        or record.root.Position
    local origin  = from + Vector3.new(0, AI.LINE_OF_SIGHT_HEIGHT_OFFSET, 0)
    local hit     = workspace:Raycast(origin, record.root.CFrame.LookVector * maxDist, losParams)
    local wanted  = if hit ~= nil then math.clamp(1 - hit.Distance / maxDist, 0, 1) else 0

    record.retract += (wanted - record.retract) * (AI.GUN_RETRACT_ALPHA :: number)
    local grip = record.gripMotor

    if record.retract < 0.01 then
        record.retract = 0
        if grip ~= nil then
            grip.C1 = record.gripBaseC1
        end
        shoulder.C0 = record.rightShoulderBaseC0
        return
    end

    local t    = record.retract
    local back = t * (AI.GUN_RETRACT_MAX :: number)
    if grip ~= nil then
        grip.C1 = record.gripBaseC1 * CFrame.new(0, 0, back)
    end
    shoulder.C0 = record.rightShoulderBaseC0
        * CFrame.new(0, back * 0.25, back * 0.6)
        * CFrame.Angles(-math.rad(t * (AI.GUN_RETRACT_TUCK_DEG :: number)), 0, 0)
end

local function thinkNPC(record: NPCRecord, now: number)
    if record.dead then
        return
    end
    local humanoid, root = record.humanoid, record.root
    if humanoid.Parent == nil or root.Parent == nil then
        return
    end

    -- Stage 1F: pull the gun/arm off any near wall every think, in every state.
    updateWeaponCollision(record)

    -- ── Target acquisition / validation ──────────────────────────────────────
    if now >= record.nextTargetCheckClock then
        record.nextTargetCheckClock = now + AI.TARGET_RECHECK_INTERVAL
        local seen = findVisibleTarget(record)
        if seen ~= nil then
            local isSwitch = record.target ~= nil and record.target ~= seen
            -- AI Stage 1C: switching AWAY from an already-valid target is rate-limited
            -- (TARGET_SWITCH_COOLDOWN) so two nearby players don't make a grunt flicker
            -- between them. A target-less grunt can always acquire immediately.
            local canSwitch = not isSwitch or (now - record.lastTargetSwitchAt) >= (TUNE.TARGET_SWITCH_COOLDOWN :: number)
            if canSwitch then
                if record.target ~= seen then
                    -- Stage 1H/1C: a genuinely NEW target gets a tiered reaction-time
                    -- beat before the first shot; re-confirming the same one every
                    -- recheck must not re-hesitate. Also resets the aim ramp — you
                    -- don't inherit "settled" aim against a different player.
                    record.lastTargetSwitchAt = now
                    record.firstSawTargetAt = now
                    record.lastSawTargetAt = now
                    record.visibleTargetTime = 0
                    record.aimBand = nil
                    armReaction(record, now)
                end
                record.target = seen
                local sroot = targetRootOf(seen)
                if sroot ~= nil then
                    record.lastSeenPos = sroot.Position
                    record.lastKnownTargetPosition = sroot.Position
                end
                record.lastSeenClock = now
            end
        elseif record.target ~= nil then
            local tr   = targetRootOf(record.target)
            local lost = tr == nil
            if tr ~= nil and (tr.Position - root.Position).Magnitude > AI.LOSE_TARGET_RANGE then
                lost = true
            end
            -- Drop the live target ref once LOS has been gone past the direct-chase
            -- window, but KEEP lastSeenPos so the Search / flank phase can use it.
            if lost or (now - record.lastSeenClock) > AI.LAST_SEEN_CHASE_SECONDS then
                record.target = nil
            end
        end
    end
    -- Stage 1E: forget the last-known position entirely after SEARCH_DURATION with
    -- no fresh sighting.
    if record.lastSeenPos ~= nil and (now - record.lastSeenClock) > AI.SEARCH_DURATION then
        record.lastSeenPos = nil
    end

    -- ── Decide + act ────────────────────────────────────────────────────────
    local troot = targetRootOf(record.target)
    local tchar: Model? = if record.target ~= nil then record.target.Character else nil
    if troot ~= nil then
        record.lastSeenPos = troot.Position
        record.lastSeenClock = now
    end

    -- ── Live target: cover / fight-from-cover / chase ──────────────────────
    if troot ~= nil then
        local dist  = (troot.Position - root.Position).Magnitude
        local inLos = tchar ~= nil and canSee(record, tchar, troot)

        -- AI Stage 1C: track continuous-visibility time for the aim ramp + refresh
        -- lastKnownTargetPosition. Freezes (does not increase) the instant LOS breaks;
        -- resets only once the break outlasts LAST_KNOWN_POSITION_MEMORY, so a
        -- one-think LOS flicker doesn't cost the ramp, but genuinely losing the
        -- player for a few seconds does. Bookkeeping only — never fires through this.
        if inLos then
            local dt = now - record.lastSawTargetAt
            if dt < 0 or dt > 1.0 then
                dt = AI.THINK_INTERVAL :: number
            end
            record.visibleTargetTime = math.min(record.visibleTargetTime + dt, TUNE.MAX_TRACKED_VISIBLE_TIME :: number)
            record.lastSawTargetAt = now
            record.lastKnownTargetPosition = troot.Position
            if TUNE.DEBUG == true then
                local settle = math.max(TUNE.AIM_SETTLE_TIME :: number, 1e-3)
                local band = aimBandFor(record.visibleTargetTime / settle)
                if band ~= record.aimBand then
                    record.aimBand = band
                    Logger.debug("[AIService]", record.model.Name, "aim ramp ->", band)
                end
            end
        elseif (now - record.lastSawTargetAt) > (TUNE.LAST_KNOWN_POSITION_MEMORY :: number) then
            record.visibleTargetTime = 0
            record.aimBand = nil
        end

        if AI.TAKE_COVER == true and record.coverUntil > now then
            -- Burst just finished OR just got shot — hold at / move to a spot that
            -- breaks LOS until the window expires. Ahead of the range/LOS check so
            -- reaching cover doesn't flip to Chase.
            setState(record, "Cover")
            setCrouched(record, true)  -- Stage 1F: hunker down while in cover
            record.fightPoint = nil
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
            if record.coverPoint == nil then
                record.coverPoint = findCoverPoint(record, troot.Position)
            end
            -- Stage 1F: if the player has moved around our cover and can see us again
            -- (we're parked at the spot but still in LOS), pick a fresh one on the far
            -- side of the nearest obstacle.
            local cp = record.coverPoint
            if inLos and cp ~= nil and (root.Position - cp).Magnitude <= AI.FIGHT_ARRIVE_DIST then
                record.coverPoint = findCoverPoint(record, troot.Position)
            end
            humanoid:MoveTo(record.coverPoint or root.Position)
        elseif dist <= AI.ATTACK_RANGE and inLos then
            setState(record, "Attack")
            setCrouched(record, false)  -- stand to keep the aimed-rifle look while firing
            record.coverPoint = nil
            local spot = record.fightPoint
            if spot == nil and AI.FIGHT_FROM_COVER == true then
                spot = findFightingPosition(record, troot.Position)
                record.fightPoint = spot
            end
            if spot ~= nil and (root.Position - spot).Magnitude > AI.FIGHT_ARRIVE_DIST then
                -- Still moving into a cover-adjacent firing spot.
                humanoid.AutoRotate = true
                humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
                humanoid:MoveTo(spot)
            else
                -- Planted (at cover, or no cover found) — face the player and fire.
                humanoid.AutoRotate = false
                humanoid.WalkSpeed = AI.ATTACK_MOVE_SPEED
                humanoid:MoveTo(root.Position)
                faceToward(record, troot.Position)

                -- AI Stage 1C: raise/track the target during the reaction-time window
                -- but hold fire until reactionReadyAt — a beat before shooting, not an
                -- instant flick. "If target is lost before reactionReadyAt, do not
                -- shoot magically" is automatic: this branch only runs while troot is
                -- non-nil (a live, in-range target), so losing the target routes to
                -- Chase/Search instead and startBurst is simply never reached.
                local reactionReady = now >= record.reactionReadyAt
                if reactionReady and record.reactionAnnouncedAt ~= record.reactionReadyAt then
                    record.reactionAnnouncedAt = record.reactionReadyAt
                    if TUNE.DEBUG == true then
                        Logger.debug("[AIService]", record.model.Name, "reaction-ready, engaging")
                    end
                end

                -- Per-squad attack slot: at most MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD
                -- grunts in this squad fire at once. Extras stay planted and aimed
                -- (everything above still runs) but hold fire until a slot frees up.
                local squad = squads[record.squadId]
                local hasAttackSlot = true
                if TUNE.ENABLED == true and squad ~= nil then
                    updateSquadAttackSlots(squad, now)
                    hasAttackSlot = squad.attackerSlots[record.model] == true
                end

                if not record.firing and reactionReady and hasAttackSlot then
                    startBurst(record)
                end
            end
        else
            setState(record, "Chase")
            setCrouched(record, false)
            record.coverUntil = 0
            record.coverPoint = nil
            record.fightPoint = nil
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
            humanoid:MoveTo(troot.Position + record.slot)
        end
        return
    end

    -- ── No live target, but a last-known position to work ──────────────────
    local lastSeen = record.lastSeenPos
    if lastSeen ~= nil then
        setCrouched(record, false)
        record.coverUntil = 0
        record.coverPoint = nil
        record.fightPoint = nil
        humanoid.AutoRotate = true
        if (now - record.lastSeenClock) <= AI.LAST_SEEN_CHASE_SECONDS then
            -- Fresh: run straight at where they were last seen.
            setState(record, "Chase")
            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
            humanoid:MoveTo(lastSeen + record.slot)
        else
            -- Stale: move in and flank the last-known position on an arc.
            setState(record, "Search")
            humanoid.WalkSpeed = AI.NPC_WALK_SPEED
            humanoid:MoveTo(flankPointFor(record, lastSeen))
        end
        return
    end

    -- No target: patrol between points, or idle near the squad spawn.
    setCrouched(record, false)
    record.coverUntil = 0
    record.coverPoint = nil
    record.fightPoint = nil
    setState(record, (#patrolPoints > 0) and "Patrol" or "Idle")
    humanoid.AutoRotate = true
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
    record.coverUntil = 0
    record.coverPoint = nil
    record.fightPoint = nil
    -- Stage 1F: motors + tracks are children of the NPC model and die with it.
    record.crouchTrack = nil
    record.rightShoulder = nil
    record.gripMotor = nil
    for _, conn in ipairs(record.conns) do
        conn:Disconnect()
    end
    table.clear(record.conns)
end

-- Stage 1G: hand the dead grunt to the same RagdollService the test dummies use.
-- The welded AKS-74 is removed first — its parts are joined by Motor6Ds that
-- RagdollService:Apply would convert to BallSocketConstraints, scattering the rifle
-- into loose floating pieces. The knockback impulse is built exactly like
-- DummyService.onDummyDied (per-weapon RAGDOLL_WEAPON_IMPULSE, else the default).
local function ragdollDeadNPC(record: NPCRecord)
    if AI.RAGDOLL_ON_DEATH ~= true then
        return
    end
    if RagdollService:IsRagdolled(record.model) then
        return
    end

    -- Drop the grip Motor6D (it lives on the Right Arm, not inside the gun model) so
    -- RagdollService's Motor6D sweep doesn't hit a joint with a destroyed Part1.
    local rightArm = record.model:FindFirstChild(Constants.WORLD_WEAPON_R6_RIGHT_ARM_NAME)
    if rightArm ~= nil then
        local grip = rightArm:FindFirstChild(Constants.WORLD_WEAPON_GRIP_MOTOR_NAME)
        if grip ~= nil then
            grip:Destroy()
        end
    end
    local gun = record.model:FindFirstChild(Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME)
    if gun ~= nil then
        gun:Destroy()
    end

    local info = record.lastHit
    local impulse: Vector3? = nil
    if info ~= nil and info.hitDirection ~= nil and info.finalAmount > 0 then
        local byWeapon = (Constants.RAGDOLL_WEAPON_IMPULSE :: any) or {}
        local prof = (info.sourceName ~= nil and byWeapon[info.sourceName])
            or (Constants.RAGDOLL_IMPULSE_DEFAULT :: any)
            or { SCALE = 4.5, MAX = 320 }
        local mag = math.min(info.finalAmount * prof.SCALE, prof.MAX)
        impulse = info.hitDirection.Unit * mag
    end

    local hitPart: BasePart? = if info ~= nil then info.hitPart else nil
    local sourceName: string? = if info ~= nil then info.sourceName else nil
    local ok, err = pcall(function()
        RagdollService:Apply(record.model, {
            impulse    = impulse,
            hitPart    = hitPart,
            sourceName = sourceName,
        })
    end)
    if not ok then
        Logger.warn("[AIService] ragdoll failed for", record.model.Name, "-", tostring(err))
    end
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

    ragdollDeadNPC(record)

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
    local model, humanoid, root, rightShoulder = buildRig(worldCFrame)
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

        coverUntil = 0,
        coverPoint = nil,
        fightPoint = nil,
        flankSide  = (index % 2 == 0) and 1 or -1,

        nextThinkClock       = 0,
        nextTargetCheckClock = 0,

        firing    = false,
        fireThread= nil,
        conns     = {},
        fx        = nil,
        anim      = nil,

        crouched            = false,
        crouchTrack         = nil,
        retract             = 0,
        rightShoulder       = rightShoulder,
        rightShoulderBaseC0 = rightShoulder.C0,
        gripMotor           = nil,
        gripBaseC1          = CFrame.new(),

        lastHit   = nil,

        aimSkill = math.clamp(
            1 + (math.random() * 2 - 1) * (AI.AIM_SKILL_VARIANCE :: number),
            AI.AIM_SKILL_MIN :: number, AI.AIM_SKILL_MAX :: number
        ),

        firstSawTargetAt        = 0,
        lastSawTargetAt         = 0,
        lastKnownTargetPosition = nil,
        reactionReadyAt         = 0,
        reactionAnnouncedAt     = -1,
        lastTargetSwitchAt      = -math.huge,
        suppressedUntil         = 0,
        recentlyDamagedUntil    = 0,
        visibleTargetTime       = 0,
        lastDamageCallAt        = -math.huge,
        aimBand                 = nil,

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

        alerted               = false,
        attackerSlots         = {},
        nextAttackSlotRecheck = 0,
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

-- Gate for the one-time opening squad spawn below: Studio uses
-- SPAWN_ON_SERVER_START_IN_STUDIO, a published server uses
-- SPAWN_ON_SERVER_START_IN_PUBLISHED — same split as
-- Constants.DEV_TEST_AREA.RUN_IN_PUBLISHED, which is what actually builds the
-- Workspace/AISpawns + AIPatrolPoints parts this reads.
local function autoSpawnEnabled(): boolean
    if RunService:IsStudio() then
        return AI.SPAWN_ON_SERVER_START_IN_STUDIO == true
    end
    return AI.SPAWN_ON_SERVER_START_IN_PUBLISHED == true
end

-- Runs the one-time opening spawn (idempotent via didAutoSpawn). Safe to call
-- again once spawn parts appear — e.g. TestAreaBuilder creating
-- Workspace/AISpawns after this service already started (script order is not fixed).
local function autoSpawnSquads()
    if didAutoSpawn or not running then
        return
    end
    if not autoSpawnEnabled() then
        return
    end
    if #spawnParts == 0 then
        return
    end
    didAutoSpawn = true
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

-- Idempotent. Discovers Workspace folders, starts the single update loop, and (if
-- enabled for this environment — see autoSpawnEnabled) spawns the opening squads.
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

    -- Stage 1E: react the instant a grunt is shot. DamageService fires DamageDealt
    -- for every accepted hit; targetModel is the grunt's Model, info.attacker is
    -- the player who shot it (nil for AI-inflicted or environment damage). Non-grunt
    -- events find no npcs[targetModel] and no-op.
    local dmgConn = CombatEvents.DamageDealt.Event:Connect(function(targetModel: Model?, info: Types.DamageInfo)
        if targetModel == nil then
            return
        end
        local record = npcs[targetModel]
        if record == nil or record.dead then
            return
        end
        local now = os.clock()

        -- Stage 1G: remember the latest hit so onNPCDied can shove the ragdoll with
        -- the killing shot's direction / weapon (mirrors DummyService.record.lastHit).
        record.lastHit = info
        if AI.HURT_COVER == true then
            record.coverUntil = now + coverDurationFor(record)
            record.coverPoint = nil  -- force a fresh hide spot away from the new threat
        end

        -- AI Stage 1C: any accepted hit marks this grunt suppressed (worse aim for
        -- SUPPRESSED_DURATION) and "recently damaged" (fast reaction tier for
        -- RECENT_DAMAGE_SUPPRESSION_DURATION) — required per spec regardless of
        -- whether the attacker is known.
        if TUNE.ENABLED == true then
            local wasSuppressed = now < record.suppressedUntil
            record.suppressedUntil = now + (TUNE.SUPPRESSED_DURATION :: number)
            record.recentlyDamagedUntil = now + (TUNE.RECENT_DAMAGE_SUPPRESSION_DURATION :: number)
            if not wasSuppressed and TUNE.DEBUG == true then
                Logger.debug("[AIService]", record.model.Name, "suppressed")
            end
        end

        local attacker = info.attacker
        if attacker ~= nil then
            -- Shot from an unseen angle — still take a beat to identify the threat
            -- before returning fire; recentlyDamagedUntil (just armed above) makes
            -- armReaction pick the fast tier, so that beat is short, not zero.
            if record.target ~= attacker then
                record.firstSawTargetAt = now
                record.lastSawTargetAt = now
                record.visibleTargetTime = 0
                record.aimBand = nil
                armReaction(record, now)
            end
            record.target = attacker
            local aroot = targetRootOf(attacker)
            if aroot ~= nil then
                record.lastSeenPos = aroot.Position
                record.lastKnownTargetPosition = aroot.Position
                record.lastSeenClock = now
            end
        end
    end)
    table.insert(serviceConns, dmgConn)

    -- Re-scan when an AISpawns / AIPatrolPoints folder appears after we started
    -- (server script order is not guaranteed; TestAreaBuilder may build them later).
    local addedConn = workspace.ChildAdded:Connect(function(child: Instance)
        if not child:IsA("Folder") then
            return
        end
        if child.Name == AI.SPAWN_FOLDER_NAME then
            spawnParts, warnedNoSpawns = collectParts(AI.SPAWN_FOLDER_NAME, warnedNoSpawns)
            autoSpawnSquads()
        elseif child.Name == AI.PATROL_FOLDER_NAME then
            patrolPoints, warnedNoPatrol = collectParts(AI.PATROL_FOLDER_NAME, warnedNoPatrol)
        end
    end)
    table.insert(serviceConns, addedConn)

    -- Stage 1H: any player can request a full AI reset from the LoadoutMenu button,
    -- dev and published alike. Server-authoritative and cooldown-gated (shared, not
    -- per-player) so it can't be spammed to grief other players' fights. task.spawn
    -- because RespawnAllSquads/spawnSquad yields (task.wait between squad members).
    local respawnConn = RespawnBots.OnServerEvent:Connect(function(player: Player)
        local now = os.clock()
        local cooldown = AI.RESPAWN_COOLDOWN_SECONDS :: number
        if now - lastManualRespawnClock < cooldown then
            return
        end
        lastManualRespawnClock = now
        Logger.debug("[AIService] RespawnAllSquads requested by", player.Name)
        task.spawn(function()
            AIService.RespawnAllSquads()
        end)
    end)
    table.insert(serviceConns, respawnConn)

    if autoSpawnEnabled() and #spawnParts == 0 then
        local flagName = if RunService:IsStudio()
            then "SPAWN_ON_SERVER_START_IN_STUDIO"
            else "SPAWN_ON_SERVER_START_IN_PUBLISHED"
        Logger.warn("[AIService]", flagName, "is on but Workspace." .. AI.SPAWN_FOLDER_NAME .. " has no spawn parts yet — will spawn if one appears")
    end
    autoSpawnSquads()

    Logger.debug("[AIService] started — spawns:", #spawnParts, "patrol points:", #patrolPoints)
end

-- Public wrapper (asserts live in spawnSquad).
function AIService.SpawnSquad(spawnCFrame: CFrame?, squadSize: number?): { Model }
    return spawnSquad(spawnCFrame, squadSize)
end

-- Stage 1H: full manual reset — instantly destroys every live/pending-cleanup grunt
-- (no ragdoll; this is a reset, not a kill) and spawns fresh squads at the current
-- AISpawns points. Mirrors the teardown half of AIService.Destroy() but leaves the
-- service (loop, connections) running. Re-collects spawnParts first in case
-- TestAreaBuilder rebuilt the zone since Start(). Returns the number of squads spawned.
function AIService.RespawnAllSquads(): number
    if not started or not running then
        Logger.warn("[AIService] RespawnAllSquads called before Start() / after Destroy() — ignored")
        return 0
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
    table.clear(pendingCleanup)
    table.clear(squads)

    spawnParts, warnedNoSpawns = collectParts(AI.SPAWN_FOLDER_NAME, warnedNoSpawns)
    if #spawnParts == 0 then
        Logger.warn("[AIService] RespawnAllSquads: Workspace." .. AI.SPAWN_FOLDER_NAME .. " has no spawn parts — nothing to spawn")
        return 0
    end

    local spawned = 0
    for i = 1, AI.MAX_SQUADS do
        if not running or activeCount() >= AI.MAX_ACTIVE_NPCS then
            break
        end
        local part = spawnParts[((i - 1) % #spawnParts) + 1]
        spawnSquad(part.CFrame, AI.DEFAULT_SQUAD_SIZE)
        spawned += 1
    end
    Logger.debug("[AIService] RespawnAllSquads: spawned", spawned, "squad(s) — active", activeCount())
    return spawned
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
    didAutoSpawn = false

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
