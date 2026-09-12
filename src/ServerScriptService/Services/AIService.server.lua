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
-- AI dynamic navigation (Constants.AI_NAVIGATION, 2026-09-11): lets squads roam,
-- search, and investigate on a big map without hand-placed Workspace/AIPatrolPoints.
-- sampleReachableGroundNear() picks a random downward-raycast-validated ground
-- point within a radius band; computePath()/followNavGoal() wrap
-- PathfindingService (agent params from Constants.AI_NAVIGATION), waypoint-by-
-- waypoint via Humanoid:MoveTo, with a distance-over-time stuck check and a plain
-- MoveTo fallback if pathfinding is disabled or fails. Applied ONLY to Idle/Patrol
-- dynamic roaming (dynamicRoam(), used when Workspace/AIPatrolPoints doesn't
-- exist — authored patrol points still work exactly as before) and the two
-- "Search" state goals (this grunt's own stale last-seen flank, and the squad-
-- shared investigate-last-known-position goal) — every combat movement path
-- (Chase toward a live target, Attack transit, Cover retreat, bound-and-cover)
-- deliberately keeps its existing direct Humanoid:MoveTo, unchanged, to preserve
-- already-tuned close-combat responsiveness. See docs/TECHNICAL_DEBT.md "AI
-- dynamic navigation" for that scoping and every other limitation.
--
-- Deferred (see docs/TECHNICAL_DEBT.md — AI Stage 1A..1F, AI dynamic navigation):
-- ragdoll on AI death, rewards/points/killstreaks, AI types, real squad
-- cover/flanking coordination, suppression, jump/climb animation, reload
-- animation, final flash/smoke/sound art, tracer pooling, extracting the
-- WorldWeaponService attach body into a shared module, doors/ladders/vaulting,
-- a designer-authored AI-zone/navmesh-region system, a strategic map-level planner.

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")
local Debris             = game:GetService("Debris")

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

-- Stage 1H: RespawnBots / KillAllBots — created by RemoteSetup before any Service needs them.
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local RespawnBots     = Remotes:WaitForChild("RespawnBots") :: RemoteEvent
local KillAllBots     = Remotes:WaitForChild("KillAllBots") :: RemoteEvent
-- AI arena spectating (2026-09-11): client → server request, then server → same
-- client confirmation once the teleport lands (SpectatorFlyController grants fly
-- only after seeing that confirmation, never on the raw request).
local TeleportToArena = Remotes:WaitForChild("TeleportToArena") :: RemoteEvent
-- AI invisibility toggle (2026-09-11): client → server (boolean) | sets/clears
-- Constants.ATTR_AI_INVISIBLE on the requesting player.
local SetAIInvisible  = Remotes:WaitForChild("SetAIInvisible")  :: RemoteEvent

-- Untyped views of the tuning tables (heterogeneous fields; matches the pattern
-- used by TestAreaBuilder's `local CFG = Constants.DEV_TEST_AREA :: any`).
local AI      = Constants.AI :: any
local FX      = Constants.AI_COMBAT_FX :: any
local TUNE    = Constants.AI_COMBAT_TUNING :: any  -- AI Stage 1C: reaction/aim-ramp/suppression tuning
local SPACING    = Constants.AI_SQUAD_SPACING :: any    -- squad formation / anti-bunching tuning
local DISCIPLINE = Constants.AI_FIRE_DISCIPLINE :: any  -- squad fire discipline (active shooter slots + non-shooter support)
local AWARENESS  = Constants.AI_SQUAD_AWARENESS :: any  -- squad awareness sharing + last-known-position memory
local BOUNDING   = Constants.AI_BOUNDING :: any  -- squad bound-and-cover movement (Mover/Cover roles)
local NAV        = Constants.AI_NAVIGATION :: any  -- dynamic big-map navigation (ground sampling + PathfindingService)
local ARENA      = Constants.AI_ARENA :: any  -- AI arena: auto-spawns + watches an ARENA_RED vs ARENA_BLUE battle (geometry itself is AIArenaBuilder.server.lua)
local ARENA2     = Constants.AI_ARENA_2 :: any  -- second, separate AI arena (2026-09-11) — ARENA2_RED vs ARENA2_BLUE (geometry is AIArenaCorridorBuilder.server.lua)
local SHOTGUN    = Constants.AI_SHOTGUN :: any  -- some grunts (random roll at spawn) carry a shotgun instead of the default rifle

-- ============================================================
-- Types
-- ============================================================

type AIState = "Idle" | "Patrol" | "Chase" | "Attack" | "Cover" | "Search" | "Dead"

-- AI arena / factions (2026-09-11): anything a grunt can target/engage — a
-- live Player (the only case that existed before this pass) or another AI
-- grunt's own Model (opposing faction — see Constants.AI_FACTIONS). Every
-- field/function that used to be typed Player-only for "the current target"
-- widens to this; targetRootOf/targetCharacterOf are the only two places that
-- actually branch on which kind it is — everything else just passes it through.
type AITarget = Player | Model

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

    -- AI arena / factions (2026-09-11): a key into Constants.AI_FACTIONS,
    -- resolved once at spawn (also sets the rig's colors — see buildRig) and
    -- never changed after. Two grunts only ever consider each other hostile
    -- when their factions differ — see findVisibleTarget/fireOneShot. Every
    -- existing spawn path resolves this to Constants.AI.DEFAULT_FACTION, so
    -- same-faction grunts never target each other (today's behavior, unchanged).
    faction  : string,

    -- AI shotgun (2026-09-11): a WeaponData key, resolved once at spawn via an
    -- independent random roll (Constants.AI_SHOTGUN.CHANCE) — unrelated to
    -- faction/squad. Read by attachAIWorldWeapon (world model + grip),
    -- setupAIAnimation (thirdPerson clips, with a rifle-anim fallback for
    -- weapons with no thirdPerson set of their own), and fireOneShot/
    -- startBurst (per-weapon damage/range/spread/burst pacing).
    weaponKey: string,

    state        : AIState,
    target       : AITarget?,
    lastSeenPos  : Vector3?,
    lastSeenClock: number,

    coverUntil : number,    -- os.clock() deadline; > now → in the Cover branch (0 = not covering)
    coverPoint : Vector3?,  -- LOS-broken hide spot for Cover, cleared on return to Attack
    fightPoint : Vector3?,  -- Stage 1E: cover-adjacent spot that keeps LOS, for Attack
    flankSide  : number,    -- Stage 1E: -1 / +1, which way this grunt arcs into a stale last-known pos
    nextCoverShotClock: number,  -- os.clock() before which the Cover branch won't stop to fire a covering-fire burst while retreating

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

    -- AI squad spacing / formation (2026-09-11)
    formationSlotIndex: number,    -- 1 = leader/anchor; 2+ cycle through Constants.AI_SQUAD_SPACING.SLOT_OFFSETS
    currentMoveGoal   : Vector3?,  -- last goal actually issued to Humanoid:MoveTo by the throttled travel path (nil = none issued yet)
    lastMoveGoalAt    : number,    -- os.clock() of that issuance
    lastMoveAnchor    : Vector3?,  -- the RAW target (player pos / patrol point / etc, before spread+jitter+separation) that goal was computed from —
                                    -- compared against on each think so the MOVE_GOAL_RECALCULATE_INTERVAL throttle isn't defeated by jitter re-rolling every time

    -- AI squad fire discipline (2026-09-11)
    hasAttackSlot          : boolean, -- mirrors squad.activeShooterIds[model] — true = this grunt is one of the squad's active shooters right now
    attackSlotAssignedAt   : number,  -- os.clock() the slot was (most recently) granted; feeds ATTACK_SLOT_TIMEOUT
    lastSupportRepositionAt: number,  -- os.clock() of this non-shooter's last support/hold-angle goal pick

    -- AI squad awareness (2026-09-11). lastSawTargetAt / lastKnownTargetPosition
    -- above (Stage 1C) already cover "when/where did I personally last see the
    -- target" — reused as-is, not duplicated.
    isAlertedBySquad: boolean,  -- a squadmate within ALERT_SHARE_RADIUS saw/was hit recently; may investigate without own LOS
    investigateGoal : Vector3?, -- a small random offset near the squad's shared lastKnownTargetPosition, picked once and reused until stale (not the exact point — "don't send every NPC to the same spot")

    -- AI squad bound-and-cover (2026-09-11). "Shooter"/"Support" are refined live,
    -- each think, from the base "Cover" assignment (see updateSquadBounding) —
    -- Shooter = currently holds an attack slot; Support = holding in Chase with no
    -- LOS at all yet. nil = this grunt isn't part of an active bound right now.
    tacticalRole    : ("Mover" | "Cover" | "Shooter" | "Support")?,
    boundDestination: Vector3?, -- the Mover's current bound point (nil for every other role); computed once per assignment, held until arrival/timeout

    -- AI dynamic navigation (2026-09-11) — path-following state, shared by every
    -- nav-mode goal (dynamic roam and both Search-state goals below). currentPath
    -- is the cached waypoint LIST from the most recent successful
    -- Path:GetWaypoints() call, not a live Path instance — simpler to hold an
    -- index into than re-deriving one from a Path object every think.
    currentPath           : { PathWaypoint }?,
    currentWaypointIndex  : number,
    currentNavigationGoal : Vector3?,
    lastPathRecalculateAt : number,
    lastStuckCheckAt      : number,
    lastStuckCheckPosition: Vector3?,
    stuckSince            : number, -- os.clock() progress last stalled; 0 = not currently stuck

    -- AI dynamic navigation — roaming (2026-09-11). Only read/written by
    -- dynamicRoam() (Idle/Patrol with no Workspace/AIPatrolPoints); independent of
    -- the path-following fields above, which roam shares with Search/investigate.
    roamGoal         : Vector3?,
    roamCooldownUntil: number,

    dead      : boolean,
}

type SquadRecord = {
    id          : number,
    spawnCFrame : CFrame,
    patrolIndex : number,

    -- AI Stage 1C — fair combat tuning (reaction/aim/suppression; NOT the attack-slot
    -- fields, which moved to the fire-discipline block below in the 2026-09-11 pass).
    -- `alerted` is superseded by `alertUntil` below (2026-09-11 squad awareness
    -- pass) — left declared, no longer read or written, per the project's "don't
    -- remove existing values" convention for these tasks.
    alerted : boolean,

    -- AI squad spacing / formation (2026-09-11)
    members                : { Model },             -- living members as of the last assignFormationSlots() pass
    leader                 : Model?,                 -- the current leader/anchor (original spawn leader if alive, else the first survivor)
    formationSlotAssignments: { [Model]: number },   -- model -> formation slot index, mirrored onto each NPCRecord.formationSlotIndex
    lastFormationAssignAt  : number,                 -- os.clock() of the last (re)assignment

    -- AI squad fire discipline (2026-09-11) — supersedes the original Stage 1C
    -- attackerSlots/nextAttackSlotRecheck fields (renamed to match the fire-
    -- discipline task's required names; same mechanism, consolidated in place
    -- rather than run twice — see docs/TECHNICAL_DEBT.md "AI squad fire discipline").
    activeShooterIds     : { [Model]: boolean }, -- grunts currently allowed to fire (MAX_ACTIVE_SHOOTERS_PER_SQUAD)
    lastAttackSlotUpdateAt: number,              -- os.clock() of the last updateSquadAttackSlots() pass

    -- AI squad awareness (2026-09-11) — supersedes `alerted` above (now unread) for
    -- reaction-tier selection: armReaction reads `now < alertUntil` instead of the
    -- old sticky boolean, so a squad's "Alert" tier now actually expires. See
    -- docs/TECHNICAL_DEBT.md "AI squad awareness" for that and every other
    -- overlap this consolidates rather than duplicates.
    alertUntil            : number,    -- os.clock() deadline; > now → squad reacts on the fast "Alert" reaction tier
    lastKnownTargetPosition: Vector3?, -- shared sighting/hit position, nil once CLEAR_ALERT_AFTER_NO_CONTACT elapses
    lastKnownTargetPlayer  : AITarget?,  -- who that position belongs to (Player, or an enemy-faction grunt's Model — AI arena, 2026-09-11); field name unchanged, only the type widened
    lastKnownUpdateAt      : number,   -- os.clock() of the last share (also the LAST_KNOWN_POSITION_SHARE_INTERVAL throttle gate)
    lastContactAt          : number,   -- os.clock() of the most recent sighting or hit, from ANY member — drives CLEAR_ALERT_AFTER_NO_CONTACT

    -- AI squad bound-and-cover (2026-09-11)
    currentMoverNpcId   : Model?,   -- the grunt currently assigned "Mover", or nil while not bounding
    coveringNpcIds      : { Model }, -- every other living member currently assigned "Cover" (further refined to "Shooter"/"Support" live)
    currentBoundStartedAt: number,  -- os.clock() the current mover was assigned — feeds SWAP_AFTER_MAX_TIME
    lastBoundEvaluateAt  : number,  -- os.clock() of the last updateSquadBounding() pass
}

-- ============================================================
-- State
-- ============================================================

local started   = false
local running   = false
local mainThread: thread? = nil
-- AI arena / factions (2026-09-11): the auto-spawn + self-healing battle watch
-- loop (runArenaBattle) — a second, independent task.spawn loop alongside
-- mainThread, cancelled the same way in Destroy().
local arenaThread: thread? = nil
-- Second, separate AI arena (2026-09-11) — its own independent battle-watch
-- thread, same cancellation pattern.
local arena2Thread: thread? = nil
local serviceConns: { RBXScriptConnection } = {}
local didAutoSpawn = false
-- Stage 1H: shared server-wide cooldown gate for the RespawnBots remote.
local lastManualRespawnClock = -math.huge
-- Shared server-wide cooldown gate for the KillAllBots remote.
local lastManualKillAllClock = -math.huge
-- AI arena spectating: PER-PLAYER debounce for TeleportToArena (unlike the two
-- above, this only ever affects the requester, so it is not a shared gate) —
-- cleared on PlayerRemoving so this table never grows across a long server life.
local lastTeleportToArenaClock: { [Player]: number } = {}

local aiFolder : Folder? = nil
local losParams: RaycastParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

-- AI arena / factions bugfix (2026-09-11): losParams.FilterDescendantsInstances
-- is set to { aiFolder } below — the ENTIRE folder every grunt (and its welded
-- gun) lives in — so any raycast using losParams passes straight through every
-- grunt, friend or enemy. That's correct for canSee()'s LOS check (a squadmate
-- standing in the way shouldn't block detection) but was silently breaking
-- fireOneShot's actual damage raycast: it could never hit another grunt at all,
-- so AI-vs-AI shots always missed regardless of faction/range/aim. shotParams
-- excludes only the FIRING grunt's own Model each shot (mutated right before
-- each raycast, no per-shot allocation) — its welded gun is a descendant of
-- that Model, so it's excluded too — letting a bullet hit players, terrain,
-- AND any other grunt (enemy or friendly; fireOneShot's own faction check is
-- what decides whether a hit on a grunt actually deals damage).
local shotParams: RaycastParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
shotParams.IgnoreWater = true

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
local warnedBadFaction      = false  -- one-time: spawnOne got an unrecognized Constants.AI_FACTIONS key (AI arena, 2026-09-11)

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
-- `optional` (AI dynamic navigation, 2026-09-11) downgrades that one-time notice
-- to a Logger.debug "this is fine" message instead of Logger.warn — used for
-- Workspace/AIPatrolPoints, which dynamic roaming makes non-required.
-- Workspace/AISpawns callers leave it unset and keep the original warn behavior.
local function collectParts(folderName: string, alreadyWarned: boolean, optional: boolean?): ({ BasePart }, boolean)
    local out: { BasePart } = {}
    local folder = workspace:FindFirstChild(folderName)
    if folder == nil then
        if not alreadyWarned then
            if optional == true then
                if NAV.DEBUG == true then
                    Logger.debug("[AIService] Workspace." .. folderName .. " not found — optional, using dynamic roaming instead")
                end
            else
                Logger.warn("[AIService] Workspace." .. folderName .. " is missing — AIService still starts, that source is just empty")
            end
        end
        return out, true
    end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(out, child)
        end
    end
    if #out == 0 and not alreadyWarned then
        if optional == true then
            if NAV.DEBUG == true then
                Logger.debug("[AIService] Workspace." .. folderName .. " has no BasePart children — optional, using dynamic roaming instead")
            end
        else
            Logger.warn("[AIService] Workspace." .. folderName .. " has no BasePart children")
        end
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

-- Builds a standard R6 rig at the given world CFrame. `bodyColor`/`limbColor`
-- (AI arena / factions, 2026-09-11) let a squad's faction give its grunts a
-- distinct look — see Constants.AI_FACTIONS; every existing call site passes
-- the same BODY_COLOR/LIMB_COLOR constants below, so the default grey rig is
-- unchanged.
-- Returns (model, humanoid, root, rightShoulderMotor).
local function buildRig(worldCFrame: CFrame, bodyColor: Color3, limbColor: Color3): (Model, Humanoid, BasePart, Motor6D)
    local model = Instance.new("Model")

    local root  = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), bodyColor)
    root.Transparency = 1
    root.CanCollide   = false

    local torso = makePart("Torso",     Vector3.new(2, 2, 1), bodyColor)
    local head  = makePart("Head",      Vector3.new(2, 1, 1), bodyColor)
    local lArm  = makePart("Left Arm",  Vector3.new(1, 2, 1), limbColor)
    local rArm  = makePart("Right Arm", Vector3.new(1, 2, 1), limbColor)
    local lLeg  = makePart("Left Leg",  Vector3.new(1, 2, 1), limbColor)
    local rLeg  = makePart("Right Leg", Vector3.new(1, 2, 1), limbColor)

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

-- AI invisibility toggle (2026-09-11): true while Constants.ATTR_AI_INVISIBLE
-- is set on `player` (LoadoutMenu's "AI INVISIBILITY" button, via the
-- SetAIInvisible remote below). Consulted by findVisibleTarget (never
-- acquired as a fresh target) and targetRootOf (drops an already-engaged
-- grunt's target instantly, the same as if the player had disconnected) — the
-- combination is what makes this a real "AI can't see me" toggle rather than
-- only blocking new acquisitions.
local function isAIInvisible(player: Player): boolean
    return player:GetAttribute(Constants.ATTR_AI_INVISIBLE) == true
end

-- Nearest target that is alive, in DETECTION_RANGE, and visible — a Player
-- (unconditionally hostile, as it always has been, unless isAIInvisible) or
-- an enemy-faction AI grunt (AI arena, 2026-09-11). nil if none. Two grunts of
-- the SAME faction never match each other here — every existing
-- single-faction spawn path resolves to the same Constants.AI.DEFAULT_FACTION,
-- so this loop's second half is a no-op for all of today's behavior.
local function findVisibleTarget(record: NPCRecord): AITarget?
    local best: AITarget? = nil
    local bestDist = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char ~= nil and not isAIInvisible(player) then
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
    for otherModel, other in pairs(npcs) do
        if other ~= record and not other.dead and other.faction ~= record.faction then
            local dist = (other.root.Position - record.root.Position).Magnitude
            if dist <= AI.DETECTION_RANGE and dist < bestDist and canSee(record, otherModel, other.root) then
                best = otherModel
                bestDist = dist
            end
        end
    end
    return best
end

-- Returns the target's root BasePart if the target is still live — a Player's
-- Character HumanoidRootPart (unchanged logic), or (AI arena, 2026-09-11) an
-- enemy grunt's own root, resolved via the live npcs table (cheaper and more
-- authoritative than re-deriving state from the Model).
local function targetRootOf(target: AITarget?): BasePart?
    if target == nil then
        return nil
    end
    if target:IsA("Player") then
        local player = target :: Player
        if isAIInvisible(player) then
            -- Drops an already-engaged grunt's target the instant invisibility
            -- is turned on — exactly as if the player had disconnected. thinkNPC
            -- falls back to lastSeenPos/Chase/Search from here, same as any
            -- other lost-target case.
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
    local enemyRecord = npcs[target :: Model]
    if enemyRecord == nil or enemyRecord.dead then
        return nil
    end
    return enemyRecord.root
end

-- Returns the "character" Model to feed canSee()/attack-slot LOS checks — a
-- Player's Character (unchanged), or (AI arena) the enemy grunt's own Model,
-- which already IS its character equivalent (no further indirection needed).
local function targetCharacterOf(target: AITarget?): Model?
    if target == nil then
        return nil
    end
    if target:IsA("Player") then
        return (target :: Player).Character
    end
    return target :: Model
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
    elseif squad ~= nil and now < squad.alertUntil then
        -- AI squad awareness (2026-09-11): reads the time-bounded alertUntil
        -- (shareSquadAlert) instead of the old sticky `squad.alerted` boolean, so
        -- a squad that hasn't had contact in a while correctly cools back down to
        -- the slower "Unaware" tier rather than staying alert for the rest of its
        -- life. armReaction itself no longer sets squad.alerted (or alertUntil) —
        -- only an actual sighting/hit (shareSquadAlert) does that.
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
end

-- AI squad awareness: called whenever a grunt has a confirmed live sighting
-- (every TARGET_RECHECK_INTERVAL while it can see its target — not just on the
-- first acquisition, so an ongoing engagement keeps the squad's alert timer
-- topped up) or is hit. Refreshes the squad's shared alert-expiry fields, and —
-- throttled to LAST_KNOWN_POSITION_SHARE_INTERVAL so this isn't rewritten every
-- think by every seeing member — the shared last-known position, then marks
-- living squadmates within ALERT_SHARE_RADIUS as isAlertedBySquad so they can
-- start investigating even without their own line of sight. `targetPos == nil`
-- (attacker unknown, or no position available) still puts the squad "on edge"
-- (alertUntil/lastContactAt, faster reaction tier) without sharing anywhere to
-- investigate toward, per spec point 3.
local function shareSquadAlert(record: NPCRecord, targetPlayer: AITarget?, targetPos: Vector3?, now: number)
    if AWARENESS.ENABLED ~= true then
        return
    end
    local squad = squads[record.squadId]
    if squad == nil then
        return
    end
    squad.lastContactAt = now
    squad.alertUntil = now + (AWARENESS.ALERT_MEMORY_DURATION :: number)
    if targetPos == nil then
        return
    end
    if now - squad.lastKnownUpdateAt < (AWARENESS.LAST_KNOWN_POSITION_SHARE_INTERVAL :: number) then
        return
    end
    local isNewAlert = squad.lastKnownTargetPosition == nil
    squad.lastKnownTargetPosition = targetPos
    squad.lastKnownTargetPlayer   = targetPlayer
    squad.lastKnownUpdateAt       = now
    if AWARENESS.DEBUG == true and isNewAlert then
        Logger.debug("[AIService] squad", squad.id, "alerted by", record.model.Name)
    end
    local radius = AWARENESS.ALERT_SHARE_RADIUS :: number
    for otherModel, other in pairs(npcs) do
        if other ~= record and not other.dead and other.squadId == record.squadId
            and (other.root.Position - record.root.Position).Magnitude <= radius then
            if AWARENESS.DEBUG == true and not other.isAlertedBySquad then
                Logger.debug("[AIService]", otherModel.Name, "alerted by squadmate", record.model.Name)
            end
            other.isAlertedBySquad = true
        end
    end
end

-- Clears a squad's shared alert once no member has had contact (a sighting or a
-- hit — see shareSquadAlert) for CLEAR_ALERT_AFTER_NO_CONTACT seconds: drops the
-- shared last-known position and every living member's isAlertedBySquad /
-- investigateGoal, so the squad genuinely returns to Patrol/Idle rather than
-- staying aggro forever. Cheap early-return; safe to call from every member's
-- think (mirrors updateSquadAttackSlots / ensureFormationAssigned's throttle
-- pattern) — the pre-check skips the real work once a squad is already clear,
-- which is the common case for a squad that's never made contact at all.
local function clearStaleSquadAlert(squad: SquadRecord, now: number)
    if AWARENESS.ENABLED ~= true then
        return
    end
    if squad.lastKnownTargetPosition == nil and squad.alertUntil <= now then
        return
    end
    if now - squad.lastContactAt < (AWARENESS.CLEAR_ALERT_AFTER_NO_CONTACT :: number) then
        return
    end
    squad.alertUntil = 0
    squad.lastKnownTargetPosition = nil
    squad.lastKnownTargetPlayer = nil
    for _, record in pairs(npcs) do
        if record.squadId == squad.id then
            record.isAlertedBySquad = false
            record.investigateGoal = nil
        end
    end
    if AWARENESS.DEBUG == true then
        Logger.debug("[AIService] squad", squad.id, "alert cleared — no contact for", AWARENESS.CLEAR_ALERT_AFTER_NO_CONTACT :: number, "s")
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

-- AI squad fire discipline. Base combat eligibility for holding an attack slot at
-- all, independent of slot availability: dead, no live target, out of
-- ATTACK_RANGE, or no line of sight (no wallhack shooting — squadmates seeing
-- the player does not let a blind grunt shoot) all disqualify. Deliberately does
-- NOT check record.state == "Attack" here — that's what calls this in the first
-- place (only the Attack-planted branch ever asks), and keeping it a pure
-- target/range/LOS predicate makes it independently testable and reusable.
local function attackSlotEligible(record: NPCRecord): boolean
    if record.dead then
        return false
    end
    local troot = targetRootOf(record.target)
    if troot == nil then
        return false
    end
    if (troot.Position - record.root.Position).Magnitude > (AI.ATTACK_RANGE :: number) then
        return false
    end
    -- AI squad awareness's REQUIRE_OWN_LOS_TO_SHOOT documents this LOS check as an
    -- intentional invariant of this codebase rather than a togglable behavior: the
    -- canSee() requirement immediately below is NOT gated on the flag, so setting
    -- it false does not enable shooting without LOS — "no wallhack shooting" is a
    -- hard restriction on this task, not a tunable. The flag exists so future code
    -- reading Constants.AI_SQUAD_AWARENESS can assert/document the invariant
    -- without re-deriving it. See docs/TECHNICAL_DEBT.md "AI squad awareness".
    local tchar: Model? = targetCharacterOf(record.target)
    if tchar == nil or not canSee(record, tchar, troot) then
        return false
    end
    return true
end

-- Required helper (exact signature per the fire-discipline task spec). True only
-- when the grunt is combat-eligible (see attackSlotEligible) AND its squad
-- currently has a free attack slot — or it already holds one (so a still-eligible
-- current shooter reads as "can use its slot", not "needs a new one").
local function canNpcUseAttackSlot(npcRecord: NPCRecord): boolean
    if not attackSlotEligible(npcRecord) then
        return false
    end
    local squad = squads[npcRecord.squadId]
    if squad == nil then
        return false
    end
    if squad.activeShooterIds[npcRecord.model] == true then
        return true
    end
    local held = 0
    for _ in pairs(squad.activeShooterIds) do
        held += 1
    end
    return held < (DISCIPLINE.MAX_ACTIVE_SHOOTERS_PER_SQUAD :: number)
end

-- Immediately drops `record`'s attack slot, if it holds one — called from
-- setState() on every transition OUT of "Attack" (dies, loses target, leaves
-- attack range/LOS, retreats to Cover, etc.), so a slot frees up right away
-- instead of lingering up to ATTACK_SLOT_RECHECK_INTERVAL stale.
local function releaseAttackSlot(record: NPCRecord)
    if not record.hasAttackSlot then
        return
    end
    record.hasAttackSlot = false
    local squad = squads[record.squadId]
    if squad ~= nil then
        squad.activeShooterIds[record.model] = nil
    end
end

-- Caps how many grunts in one squad actively fire at once
-- (MAX_ACTIVE_SHOOTERS_PER_SQUAD) so a 3-4 grunt squad doesn't all laser the
-- player simultaneously — the extras hold their planted Attack position (still
-- tracking/facing the player, or repositioning — see the Attack-planted branch)
-- without pulling the trigger until a slot opens. Sticky: an existing holder
-- keeps its slot as long as it stays eligible, so slots don't flicker between
-- squadmates every recheck; only vacated slots are refilled. A slot is also
-- force-released after ATTACK_SLOT_TIMEOUT even if still eligible, so one grunt
-- can't hog it forever. Cheap: re-evaluated at most once per
-- ATTACK_SLOT_RECHECK_INTERVAL per squad, guarded below, and squads are small
-- (MAX_ACTIVE_NPCS = 12 total).
local function updateSquadAttackSlots(squad: SquadRecord, now: number)
    assert(squad ~= nil, "squadRecord is required")
    assert(typeof(now) == "number", "now must be a number")
    if now - squad.lastAttackSlotUpdateAt < (DISCIPLINE.ATTACK_SLOT_RECHECK_INTERVAL :: number) then
        return
    end
    squad.lastAttackSlotUpdateAt = now
    local maxSlots = DISCIPLINE.MAX_ACTIVE_SHOOTERS_PER_SQUAD :: number
    local timeout  = DISCIPLINE.ATTACK_SLOT_TIMEOUT :: number

    -- Drop holders that are no longer eligible, or have held the slot past timeout.
    for model in pairs(squad.activeShooterIds) do
        local record = npcs[model]
        local expired = record ~= nil and timeout > 0 and (now - record.attackSlotAssignedAt) >= timeout
        if record == nil or not attackSlotEligible(record) or expired then
            squad.activeShooterIds[model] = nil
            if record ~= nil then
                record.hasAttackSlot = false
            end
            if DISCIPLINE.DEBUG == true then
                Logger.debug("[AIService]", model.Name, "attack slot released",
                    expired and "(timeout)" or "(no longer eligible)")
            end
        end
    end

    -- Fill any remaining slots from eligible squad members that don't hold one yet.
    local held = 0
    for _ in pairs(squad.activeShooterIds) do
        held += 1
    end
    if held < maxSlots then
        for _, model in ipairs(squad.members) do
            if held >= maxSlots then
                break
            end
            local record = npcs[model]
            if record ~= nil and squad.activeShooterIds[model] == nil and attackSlotEligible(record) then
                squad.activeShooterIds[model] = true
                record.hasAttackSlot = true
                record.attackSlotAssignedAt = now
                held += 1
                if DISCIPLINE.DEBUG == true then
                    Logger.debug("[AIService]", model.Name, "attack slot assigned")
                end
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

    -- AI shotgun (2026-09-11): uses this grunt's OWN assigned weapon, not
    -- always the rifle default.
    local rawData = WeaponData[record.weaponKey]
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

    -- AI shotgun (2026-09-11): Constants.WORLD_AKS74_GRIP_C0/C1 are the
    -- rifle's own grip offsets specifically; a weapon that instead defines
    -- worldGripC0/C1 directly in its own WeaponData entry (PumpShotgun, RPG7
    -- — the same fields WorldWeaponService already reads for players) uses
    -- those instead, so the grip isn't hardcoded to one weapon's shape.
    local gripC0 = (rawData :: any).worldGripC0
    local gripC1 = (rawData :: any).worldGripC1
    if typeof(gripC0) ~= "CFrame" then
        gripC0 = Constants.WORLD_AKS74_GRIP_C0
    end
    if typeof(gripC1) ~= "CFrame" then
        gripC1 = Constants.WORLD_AKS74_GRIP_C1
    end

    local motor  = Instance.new("Motor6D")
    motor.Name   = Constants.WORLD_WEAPON_GRIP_MOTOR_NAME
    motor.Part0  = rightArmInst
    motor.Part1  = handleInst
    motor.C0     = gripC0 :: CFrame
    motor.C1     = gripC1 :: CFrame
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
        local data = WeaponData[record.weaponKey] :: any
        local tp = if data ~= nil and data.animations ~= nil then data.animations.thirdPerson else nil
        -- AI shotgun (2026-09-11): WeaponData.PumpShotgun.animations.thirdPerson
        -- is intentionally empty (its presentation is procedural, client-only,
        -- which AI does not run) — fall back to the rifle's own thirdPerson
        -- clips so a shotgun-grunt still looks like it's holding/firing
        -- something, rather than standing in a raw, unanimated pose. Only
        -- triggers for a weapon whose OWN thirdPerson set is genuinely empty,
        -- so the rifle's own animations (and any future weapon that defines
        -- its own) are never overridden.
        if (tp == nil or (typeof(tp.idle) ~= "string" and typeof(tp.fire) ~= "string" and typeof(tp.equip) ~= "string"))
            and SHOTGUN.USE_RIFLE_THIRDPERSON_ANIM_FALLBACK == true
            and record.weaponKey ~= (AI.WEAPON_NAME :: string) then
            local fallbackData = WeaponData[AI.WEAPON_NAME] :: any
            tp = if fallbackData ~= nil and fallbackData.animations ~= nil then fallbackData.animations.thirdPerson else nil
        end
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

-- Resolves one raycast result into a valid damageable target (a live Player,
-- or a living enemy-faction grunt — same rule as elsewhere: same-faction
-- grunts are never a valid hit) and, if found, applies `damage`. Returns true
-- if a target was actually found (regardless of whether it was hit before —
-- used by fireOneShot to know whether ANY pellet connected). Shared by the
-- single rifle round and every shotgun pellet so there is exactly one place
-- that resolves "what did this raycast actually hit."
local function resolveAndDamageHit(record: NPCRecord, result: RaycastResult?, dir: Vector3, damage: number): boolean
    if result == nil then
        return false
    end
    local hitModel = result.Instance:FindFirstAncestorWhichIsA("Model")
    if hitModel == nil then
        return false
    end
    local victim = Players:GetPlayerFromCharacter(hitModel :: Model)

    -- AI arena / factions (2026-09-11): the ray can also hit another AI grunt.
    -- Only counts as a valid enemy hit if that grunt is alive AND its faction
    -- differs from the shooter's — two same-faction grunts (every existing
    -- single-faction spawn) can physically hit each other's hitboxes but this
    -- stays nil for them, so nothing here changes today's behavior.
    local enemyRecord: NPCRecord? = nil
    if victim == nil then
        local candidate = npcs[hitModel :: Model]
        if candidate ~= nil and not candidate.dead and candidate.faction ~= record.faction then
            enemyRecord = candidate
        end
    end
    if victim == nil and enemyRecord == nil then
        return false
    end

    if victim ~= nil then
        -- `attacker` is intentionally omitted: AI is not a Player, so DamageService
        -- treats it as an environment kill (no friendly-fire guard, "environment" feed).
        DamageService:ApplyDamage({
            targetPlayer = victim,
            targetModel  = victim.Character,
            sourceName   = AI.NPC_NAME_PREFIX,
            damageType   = Constants.DamageType.Bullet,
            region       = Constants.HitRegion.Unknown,  -- flat per-shot/per-pellet damage, no headshot multiplier
            hitPart      = result.Instance :: BasePart,
            hitPosition  = result.Position,
            hitDirection = dir,
            baseAmount   = damage,
        })
        if AI.DEBUG then
            Logger.debug("[AIService]", record.model.Name, "hit", victim.Name, "for", damage)
        end
    else
        local enemy = enemyRecord :: NPCRecord
        -- Same ApplyDamage shape as above, minus targetPlayer — the exact
        -- applyToNonPlayer path a player's bullet already uses to damage a
        -- TAG_DAMAGE_ENTITY-tagged grunt (see getDamageableEntity in
        -- GunService); DamageService needed no changes for AI-vs-AI. No
        -- attacker attribution here either (DamageInfo.attacker is Player-only)
        -- — see docs/TECHNICAL_DEBT.md "AI arena / factions" for that limit.
        DamageService:ApplyDamage({
            targetModel  = enemy.model,
            sourceName   = AI.NPC_NAME_PREFIX,
            damageType   = Constants.DamageType.Bullet,
            region       = Constants.HitRegion.Unknown,
            hitPart      = result.Instance :: BasePart,
            hitPosition  = result.Position,
            hitDirection = dir,
            baseAmount   = damage,
        })
        if AI.DEBUG then
            Logger.debug("[AIService]", record.model.Name, "hit enemy-faction", enemy.model.Name, "for", damage)
        end
    end
    return true
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

    -- AI shotgun (2026-09-11): this grunt's own weapon decides pellet count/
    -- damage/range/extra spread. pelletCount is 1 and pelletSpreadDeg is 0 for
    -- every non-shotgun weapon, so the loop below fires exactly once with
    -- exactly the same numbers as before this change — a pure extension, not
    -- a behavior change, for the rifle.
    local isShotgun = SHOTGUN.ENABLED == true and record.weaponKey == SHOTGUN.WEAPON_KEY
    local shotRange       = if isShotgun then (SHOTGUN.SHOT_RANGE :: number) else (AI.SHOT_RANGE :: number)
    local shotDamage      = if isShotgun then (SHOTGUN.SHOT_DAMAGE_PER_PELLET :: number) else (AI.SHOT_DAMAGE :: number)
    local pelletCount     = if isShotgun then math.max(1, SHOTGUN.PELLET_COUNT :: number) else 1
    local pelletSpreadDeg = if isShotgun then (SHOTGUN.PELLET_SPREAD_DEGREES :: number) else 0

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
    spreadDeg += pelletSpreadDeg -- 0 for every non-shotgun weapon

    -- Fire the first (or only) pellet now — also what the visible tracer/FX use.
    local dir = coneSpread(baseDir.Unit, math.rad(spreadDeg))
    local rayVec = dir * shotRange
    -- shotParams (not losParams — see its declaration) excludes only this
    -- grunt's own Model, so the shot can actually hit another grunt.
    shotParams.FilterDescendantsInstances = { record.model }
    local result = workspace:Raycast(origin, rayVec, shotParams)

    -- Stage 1B/1C: play the visible + audible shot FX and the fire kick for every
    -- shot, hit or miss, once per trigger pull (not once per pellet). Reads only
    -- the muzzle / end position — hit calc unchanged.
    local muzzlePos: Vector3 = origin
    local fx = record.fx
    if fx ~= nil and fx.attachment.Parent ~= nil then
        muzzlePos = fx.attachment.WorldPosition
    end
    local endPos: Vector3 = if result ~= nil then result.Position else origin + rayVec
    playAIShotFx(record, muzzlePos, endPos)
    playAIFireAnim(record)

    -- Collect every pellet that actually resolved to a valid, damageable
    -- target before touching the damage-rate gate or calling DamageService —
    -- for the rifle (pelletCount == 1) this is exactly the original
    -- single-raycast control flow, just routed through the shared helper.
    local hits: { { result: RaycastResult, dir: Vector3 } } = {}
    if result ~= nil then
        table.insert(hits, { result = result :: RaycastResult, dir = dir })
    end
    for _ = 2, pelletCount do
        local pelletDir = coneSpread(baseDir.Unit, math.rad(spreadDeg))
        local pelletRayVec = pelletDir * shotRange
        shotParams.FilterDescendantsInstances = { record.model }
        local pelletResult = workspace:Raycast(origin, pelletRayVec, shotParams)
        if pelletResult ~= nil then
            table.insert(hits, { result = pelletResult :: RaycastResult, dir = pelletDir })
        end
    end

    if #hits == 0 then
        return
    end

    -- AI Stage 1C: safety net, independent of burst timing — never call DamageService
    -- for this grunt more often than MIN_TIME_BETWEEN_DAMAGE_CALLS, even if a future
    -- tuning change ever drops SECONDS_BETWEEN_SHOTS below it. Gates the WHOLE
    -- trigger pull once, not per pellet. DamageService itself is unchanged;
    -- this only decides whether AIService calls it.
    if now - record.lastDamageCallAt < (TUNE.MIN_TIME_BETWEEN_DAMAGE_CALLS :: number) then
        return
    end
    record.lastDamageCallAt = now

    for _, hit in ipairs(hits) do
        resolveAndDamageHit(record, hit.result, hit.dir, shotDamage)
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
    -- AI shotgun (2026-09-11): a shotgun-armed grunt bursts on its own
    -- (fewer, further-spaced pulls) pacing instead of the rifle's — read
    -- once per burst, same as the rifle's AI.* fields always have been.
    local isShotgun = SHOTGUN.ENABLED == true and record.weaponKey == SHOTGUN.WEAPON_KEY
    local minShots      = if isShotgun then (SHOTGUN.BURST_SHOTS_MIN :: number) else (AI.BURST_SHOTS_MIN :: number)
    local maxShots       = if isShotgun then (SHOTGUN.BURST_SHOTS_MAX :: number) else (AI.BURST_SHOTS_MAX :: number)
    local betweenShots  = if isShotgun then (SHOTGUN.SECONDS_BETWEEN_SHOTS :: number) else (AI.SECONDS_BETWEEN_SHOTS :: number)
    local betweenBursts = if isShotgun then (SHOTGUN.SECONDS_BETWEEN_BURSTS :: number) else (AI.SECONDS_BETWEEN_BURSTS :: number)
    record.fireThread = task.spawn(function()
        local shots = math.random(minShots, maxShots)
        if AI.DEBUG then
            local tname = record.target ~= nil and record.target.Name or "?"
            Logger.debug("[AIService]", record.model.Name, "burst x" .. tostring(shots), "at", tname)
        end
        for _ = 1, shots do
            -- "Attack" is the normal planted firefight; "Cover" is a covering-fire
            -- burst fired while retreating (see the Cover branch's bounding-overwatch
            -- pulse) — both are valid states to keep shooting in. Anything else
            -- (Chase/Search/Patrol/dead) means the target/engagement ended; stop.
            if record.dead or not running or record.target == nil
                or (record.state ~= "Attack" and record.state ~= "Cover") then
                break
            end
            fireOneShot(record)
            task.wait(betweenShots)
        end
        -- Stage 1D: arm the cover window so thinkNPC ducks this grunt away before
        -- the next burst. The burst loop already bailed on an invalid state above.
        if not record.dead and running and AI.TAKE_COVER == true then
            record.coverUntil = os.clock() + coverDurationFor(record)
        end
        if not record.dead and running then
            task.wait(betweenBursts)
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
    -- Fire discipline: leaving Attack (dies, loses target, leaves range/LOS,
    -- retreats to Cover, ...) immediately frees this grunt's attack slot rather
    -- than leaving it stale for up to ATTACK_SLOT_RECHECK_INTERVAL.
    if record.state == "Attack" and newState ~= "Attack" then
        releaseAttackSlot(record)
    end
    record.state = newState
    if AI.DEBUG then
        Logger.debug("[AIService]", record.model.Name, "state ->", newState)
    end
end

-- Base Patrol/Idle anchor point (a patrol waypoint, or the squad spawn if there
-- are none) — WITHOUT any per-grunt offset. Squad spacing applies the spread
-- (IDLE_SPREAD_RADIUS) at the call site via issueSquadMoveGoal, replacing the
-- old flat `+ record.slot` that used to live here.
local function patrolDestination(record: NPCRecord): Vector3
    local squad = squads[record.squadId]
    if #patrolPoints > 0 and squad ~= nil then
        local pt = patrolPoints[((squad.patrolIndex - 1) % #patrolPoints) + 1]
        return pt.Position
    end
    if squad ~= nil then
        return squad.spawnCFrame.Position
    end
    return record.root.Position
end

-- ============================================================
-- Squad spacing / anti-bunching
-- ============================================================

-- Direction (unit vector, or zero) a formation slot pulls a grunt away from the
-- squad anchor. Slot 1 (leader) uses LEADER_SLOT_OFFSET (zero by default — the
-- leader beelines for the anchor); slots 2+ cycle through SLOT_OFFSETS[2..],
-- wrapping if the squad somehow has more members than table entries. Only the
-- DIRECTION is used here — squadSpreadGoal scales it out to the context's own
-- spread radius, so SLOT_OFFSETS defines the formation's shape, not its size.
local function formationDirectionForSlot(slotIndex: number): Vector3
    local offsets = SPACING.SLOT_OFFSETS :: { Vector3 }
    local off: Vector3
    if slotIndex <= 1 or #offsets <= 1 then
        off = SPACING.LEADER_SLOT_OFFSET :: Vector3
    else
        local idx = ((slotIndex - 2) % (#offsets - 1)) + 2
        off = offsets[idx]
    end
    if off.Magnitude > 0.01 then
        return off.Unit
    end
    return Vector3.zero
end

-- Fans a grunt's goal out from a SHARED anchor (player position, last-known
-- position, patrol point, squad spawn) by its formation slot direction scaled to
-- `radius`, plus a small random MOVE_GOAL_JITTER so goals never perfectly
-- overlap even within the same slot. Falls back to the grunt's static spawn-time
-- ring offset (record.slot — Stage 1A) when squad spacing is disabled or its
-- squad record can't be found, so disabling SPACING.ENABLED cleanly reverts to
-- the original pre-this-change behavior.
local function squadSpreadGoal(record: NPCRecord, anchor: Vector3, radius: number): Vector3
    if SPACING.ENABLED ~= true or squads[record.squadId] == nil then
        return anchor + record.slot
    end
    local dir = formationDirectionForSlot(record.formationSlotIndex)
    local jitter = Vector3.new(
        (math.random() * 2 - 1) * (SPACING.MOVE_GOAL_JITTER :: number),
        0,
        (math.random() * 2 - 1) * (SPACING.MOVE_GOAL_JITTER :: number)
    )
    return anchor + dir * radius + jitter
end

-- Required helper (exact signature from the squad-spacing task spec). Nudges
-- `desiredGoal` away from any LIVING squadmate whose current position is closer
-- than MIN_PERSONAL_SPACE to it, by SEPARATION_PUSH_DISTANCE per violator. Pure
-- math — returns a new Vector3 only; never touches HumanoidRootPart, never
-- applies a physics force. Squads are tiny (MAX_ACTIVE_NPCS = 12 total) so a
-- full scan of `npcs` per call is cheap.
local function getSeparationAdjustedGoal(npcRecord: NPCRecord, desiredGoal: Vector3): Vector3
    assert(npcRecord ~= nil, "npcRecord is required")
    assert(typeof(desiredGoal) == "Vector3", "desiredGoal must be a Vector3")
    if SPACING.ENABLED ~= true then
        return desiredGoal
    end
    local minSpace = SPACING.MIN_PERSONAL_SPACE :: number
    local pushDist = SPACING.SEPARATION_PUSH_DISTANCE :: number
    local adjusted = desiredGoal
    for otherModel, other in pairs(npcs) do
        if other ~= npcRecord and not other.dead and other.squadId == npcRecord.squadId then
            local otherPos = other.root.Position
            local delta = Vector3.new(adjusted.X - otherPos.X, 0, adjusted.Z - otherPos.Z)
            local dist = delta.Magnitude
            if dist < minSpace then
                local pushDir = if dist > 0.01 then delta.Unit else Vector3.new(1, 0, 0)
                adjusted = adjusted + pushDir * pushDist
                if SPACING.DEBUG == true then
                    Logger.debug("[AIService]", npcRecord.model.Name, "separation: pushed goal away from", otherModel.Name)
                end
            end
        end
    end
    return adjusted
end

-- ============================================================
-- AI dynamic navigation (ground sampling + PathfindingService)
-- ============================================================
-- Foundation only: lets squads roam/search/investigate on a large map without
-- hand-placed Workspace/AIPatrolPoints. See the file-header comment and
-- docs/TECHNICAL_DEBT.md "AI dynamic navigation" for exactly which movement
-- paths this does (roam, Search/investigate) and does not (Chase/Attack/Cover/
-- bound-and-cover, all left as a direct Humanoid:MoveTo) touch.

-- Picks a random reachable ground point within [minRadius, maxRadius] studs of
-- `origin` via a downward raycast sample — "reachable" here means "valid
-- standable ground" (real, collidable, not too steep), not "provably pathable
-- from here"; computePath() is what actually verifies a route exists. Tries up
-- to GROUND_SAMPLE_ATTEMPTS times; nil if none of them validate.
local function sampleReachableGroundNear(origin: Vector3, minRadius: number, maxRadius: number): Vector3?
    assert(typeof(origin) == "Vector3", "origin must be a Vector3")
    assert(typeof(minRadius) == "number", "minRadius must be a number")
    assert(typeof(maxRadius) == "number", "maxRadius must be a number")

    local attempts     = NAV.GROUND_SAMPLE_ATTEMPTS :: number
    local sampleHeight = NAV.GROUND_SAMPLE_HEIGHT :: number
    local sampleDepth  = NAV.GROUND_SAMPLE_DEPTH :: number
    local maxSlope     = NAV.MAX_GROUND_SLOPE_NORMAL_Y :: number
    local lo, hi = math.min(minRadius, maxRadius), math.max(minRadius, maxRadius)

    for _ = 1, attempts do
        local ang  = math.random() * math.pi * 2
        local dist = lo + math.random() * math.max(hi - lo, 0)
        local candidate = origin + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
        local rayOrigin = Vector3.new(candidate.X, origin.Y + sampleHeight, candidate.Z)
        local hit = workspace:Raycast(rayOrigin, Vector3.new(0, -sampleDepth, 0), losParams)
        if hit ~= nil and hit.Instance ~= nil and hit.Instance:IsA("BasePart") then
            -- A valid floor's normal points mostly straight up; reject steep
            -- surfaces (walls, roofs) and non-collidable "geometry" (decals,
            -- CanCollide-false dressing isn't real ground to stand on).
            if hit.Normal.Y >= maxSlope and hit.Instance.CanCollide == true then
                return hit.Position
            end
        end
    end
    return nil
end

-- Computes a PathfindingService path from `startPosition` to `goalPosition`
-- using the agent parameters in Constants.AI_NAVIGATION. Fully pcall'd —
-- CreatePath/ComputeAsync can throw on bad input or an unready navmesh — and
-- returns nil on any failure or a non-Success status, never erroring the
-- caller's think. Stateless and unthrottled by design; followNavGoal() (the
-- only caller) is what respects PATH_RECALCULATE_INTERVAL per NPC.
local function computePath(startPosition: Vector3, goalPosition: Vector3): Path?
    local ok, result = pcall(function()
        local path = PathfindingService:CreatePath({
            AgentRadius = NAV.AGENT_RADIUS,
            AgentHeight = NAV.AGENT_HEIGHT,
            AgentCanJump = NAV.AGENT_CAN_JUMP,
            AgentCanClimb = NAV.AGENT_CAN_CLIMB,
            WaypointSpacing = NAV.WAYPOINT_SPACING,
        })
        path:ComputeAsync(startPosition, goalPosition)
        return path
    end)
    if not ok or result == nil then
        return nil
    end
    local path = result :: Path
    if path.Status ~= Enum.PathStatus.Success then
        return nil
    end
    return path
end

-- Advances `record` toward `goal` using a PathfindingService path when
-- Constants.AI_NAVIGATION allows it — waypoint by waypoint via Humanoid:MoveTo,
-- with a distance-over-time stuck check — falling back to a direct
-- Humanoid:MoveTo when pathfinding is disabled, a path attempt fails, or
-- FALLBACK_TO_MOVE_TO_ON_PATH_FAIL is set. Path (re)computation itself is
-- throttled to PATH_RECALCULATE_INTERVAL per NPC via record.lastPathRecalculateAt
-- — never every think, never every frame. Returns true once `record` has made
-- no real progress for at least PATH_STUCK_TIME, so a caller like dynamicRoam
-- can abandon this goal and pick a different one instead of waiting out a full
-- cooldown; returns false otherwise (including whenever pathfinding is off).
local function followNavGoal(record: NPCRecord, humanoid: Humanoid, goal: Vector3, now: number): boolean
    if NAV.ENABLED ~= true or NAV.USE_PATHFINDING ~= true then
        humanoid:MoveTo(goal)
        return false
    end

    -- A materially different goal invalidates whatever path we were following.
    if record.currentNavigationGoal == nil
        or (goal - (record.currentNavigationGoal :: Vector3)).Magnitude > (NAV.PATH_WAYPOINT_REACHED_DISTANCE :: number) then
        record.currentNavigationGoal = goal
        record.currentPath = nil
        record.currentWaypointIndex = 1
        record.lastPathRecalculateAt = -math.huge -- force an immediate compute below
        record.stuckSince = 0
    end

    -- Stuck check: the root hasn't moved PATH_STUCK_DISTANCE_THRESHOLD in
    -- PATH_STUCK_TIME, sampled at most every PATH_STUCK_CHECK_INTERVAL — cheap,
    -- no per-frame work.
    if now - record.lastStuckCheckAt >= (NAV.PATH_STUCK_CHECK_INTERVAL :: number) then
        local last = record.lastStuckCheckPosition
        local moved = last == nil or (record.root.Position - (last :: Vector3)).Magnitude >= (NAV.PATH_STUCK_DISTANCE_THRESHOLD :: number)
        record.lastStuckCheckAt = now
        record.lastStuckCheckPosition = record.root.Position
        if moved then
            record.stuckSince = 0
        elseif record.stuckSince == 0 then
            record.stuckSince = now
        end
    end
    local stuck = record.stuckSince ~= 0 and now - record.stuckSince >= (NAV.PATH_STUCK_TIME :: number)

    local waypoints = record.currentPath
    local needsCompute = waypoints == nil or record.currentWaypointIndex > #waypoints
    if (needsCompute or stuck) and now - record.lastPathRecalculateAt >= (NAV.PATH_RECALCULATE_INTERVAL :: number) then
        record.lastPathRecalculateAt = now
        local path = computePath(record.root.Position, goal)
        local points: { PathWaypoint }? = nil
        if path ~= nil then
            local ok, result = pcall(function()
                return (path :: Path):GetWaypoints()
            end)
            if ok and result ~= nil and #result > 0 then
                points = result
            end
        end
        record.currentPath = points
        record.currentWaypointIndex = 1
        if points ~= nil then
            record.stuckSince = 0 -- got a fresh path; give it a chance before flagging stuck again
            if NAV.DEBUG == true then
                Logger.debug("[AIService]", record.model.Name, "path computed —", #points, "waypoint(s)")
            end
        elseif NAV.DEBUG == true then
            Logger.debug("[AIService]", record.model.Name, "path computation failed or empty")
        end
        waypoints = points
    end

    if waypoints == nil or #waypoints == 0 then
        if NAV.FALLBACK_TO_MOVE_TO_ON_PATH_FAIL == true then
            humanoid:MoveTo(goal)
        end
        return stuck
    end

    -- Advance past any waypoint already reached — handles a low think rate
    -- skipping straight past a close one instead of stepping through each.
    while record.currentWaypointIndex <= #waypoints do
        local wp = waypoints[record.currentWaypointIndex]
        local flat = Vector3.new(wp.Position.X, record.root.Position.Y, wp.Position.Z)
        if (record.root.Position - flat).Magnitude <= (NAV.PATH_WAYPOINT_REACHED_DISTANCE :: number) then
            record.currentWaypointIndex += 1
        else
            humanoid:MoveTo(wp.Position)
            if wp.Action == Enum.PathWaypointAction.Jump and (NAV.AGENT_CAN_JUMP :: boolean) == true then
                humanoid.Jump = true
            end
            return stuck
        end
    end
    -- Ran off the end this same think (the last waypoint was already within
    -- range) — hold at the final goal; the caller's own arrival check (roam's
    -- ROAM_GOAL_REACHED_DISTANCE, investigate's INVESTIGATE_ARRIVE_DISTANCE)
    -- picks the next one.
    humanoid:MoveTo(goal)
    return stuck
end

-- Shared throttled MoveTo issuance for every "travel toward a destination"
-- branch (Patrol/Idle, Chase, Search, Attack/Cover transit) — never the
-- stationary "hold position" MoveTo(root.Position) calls elsewhere in this file,
-- which stay direct/unthrottled so a grunt that just planted actually stops
-- moving on the same think rather than coasting further on a stale goal.
--
-- Only recomputes/reissues when MOVE_GOAL_RECALCULATE_INTERVAL has elapsed OR
-- `anchor` (the RAW target — before spread/jitter/separation) has moved more
-- than MOVE_GOAL_JITTER studs since the last issuance. Comparing the raw anchor
-- rather than the final goal is what makes the throttle actually throttle:
-- squadSpreadGoal re-rolls jitter on every call, so comparing final goals would
-- see "changed" almost every think and never actually skip a reissue.
--
-- `radius` > 0 additionally fans the grunt out around `anchor` by formation slot
-- (shared-target cases — pass CHASE_SPREAD_RADIUS / IDLE_SPREAD_RADIUS). Pass 0
-- for a goal that is already an individually-computed final position (an Attack
-- fighting spot, a Cover hide point, a flank point) — those only get separation,
-- never spread/jitter, so they aren't pulled off a validated cover/LOS spot.
--
-- `useNav` (AI dynamic navigation, 2026-09-11; default/omitted = false) routes
-- the final MoveTo through followNavGoal() instead of a direct MoveTo — used only
-- by dynamic roam and the two Search-state goals, never by any combat movement
-- call site (those all omit it, unchanged). Returns nil when the throttle above
-- skipped this think (no new info yet); otherwise followNavGoal's stuck flag
-- (always false when useNav isn't true).
local function issueSquadMoveGoal(record: NPCRecord, humanoid: Humanoid, anchor: Vector3, radius: number, now: number, useNav: boolean?): boolean?
    local lastAnchor = record.lastMoveAnchor
    local intervalPassed = now - record.lastMoveGoalAt >= (SPACING.MOVE_GOAL_RECALCULATE_INTERVAL :: number)
    local anchorMoved = lastAnchor == nil or (anchor - lastAnchor).Magnitude >= (SPACING.MOVE_GOAL_JITTER :: number)
    if not intervalPassed and not anchorMoved then
        return nil
    end
    local desired = if radius > 0 then squadSpreadGoal(record, anchor, radius) else anchor
    local adjusted = getSeparationAdjustedGoal(record, desired)
    record.lastMoveAnchor  = anchor
    record.currentMoveGoal = adjusted
    record.lastMoveGoalAt  = now
    if useNav == true then
        return followNavGoal(record, humanoid, adjusted, now)
    end
    humanoid:MoveTo(adjusted)
    return false
end

-- AI dynamic navigation: Idle/Patrol behavior when there are no authored
-- Workspace/AIPatrolPoints — picks a reachable ground point within
-- RANDOM_ROAM_RADIUS_MIN/MAX of the squad's spawn/anchor, paths to it (via
-- issueSquadMoveGoal in nav mode, so it still gets squad-spacing spread +
-- separation — multiple bots don't all roam to the exact same point), and once
-- arrived (or abandoned as stuck) waits ROAM_GOAL_COOLDOWN_MIN..MAX before
-- picking another. Holds at the anchor if no valid ground sample is found.
local function dynamicRoam(record: NPCRecord, humanoid: Humanoid, now: number)
    local squad = squads[record.squadId]
    local anchor = if squad ~= nil then squad.spawnCFrame.Position else record.root.Position

    if record.roamGoal ~= nil then
        local arrived = (record.root.Position - (record.roamGoal :: Vector3)).Magnitude <= (NAV.ROAM_GOAL_REACHED_DISTANCE :: number)
        if arrived then
            local lo, hi = NAV.ROAM_GOAL_COOLDOWN_MIN :: number, NAV.ROAM_GOAL_COOLDOWN_MAX :: number
            record.roamCooldownUntil = now + lo + math.random() * (hi - lo)
            record.roamGoal = nil
            record.currentNavigationGoal = nil
            record.currentPath = nil
            if NAV.DEBUG == true then
                Logger.debug("[AIService]", record.model.Name, "reached roam goal — cooling down")
            end
            humanoid:MoveTo(record.root.Position) -- stop cleanly instead of coasting past it
            return
        end
    end

    if now < record.roamCooldownUntil then
        humanoid:MoveTo(record.root.Position)
        return
    end

    if record.roamGoal == nil then
        local point = sampleReachableGroundNear(anchor, NAV.RANDOM_ROAM_RADIUS_MIN :: number, NAV.RANDOM_ROAM_RADIUS_MAX :: number)
        record.roamGoal = point
        if point == nil then
            -- No valid sample this attempt — hold near the anchor (still through
            -- the squad-spacing spread so several idling bots don't stack) and try
            -- again next think rather than spamming raycasts every tick.
            issueSquadMoveGoal(record, humanoid, anchor, SPACING.IDLE_SPREAD_RADIUS :: number, now)
            return
        end
        if NAV.DEBUG == true then
            Logger.debug("[AIService]", record.model.Name, "picked a new roam goal")
        end
    end

    -- roamGoal is already a final, individually-sampled point, so radius 0 —
    -- still routed through issueSquadMoveGoal for its separation nudge + shared
    -- throttle, in nav mode so it actually paths there.
    local stuck = issueSquadMoveGoal(record, humanoid, record.roamGoal :: Vector3, 0, now, true)
    if stuck == true then
        if NAV.DEBUG == true then
            Logger.debug("[AIService]", record.model.Name, "roam goal unreachable — picking a different one")
        end
        record.roamGoal = nil
        record.currentNavigationGoal = nil
        record.currentPath = nil
    end
end

-- ============================================================
-- Squad bound-and-cover movement (Mover/Cover roles)
-- ============================================================
-- A simplified, game-friendly "one bot advances while others hold" pass layered
-- on top of Chase/Attack — NOT a real fire-and-maneuver/cover-node system. See
-- docs/TECHNICAL_DEBT.md "AI squad bound-and-cover" for every simplification.

-- Clears `record`'s own tacticalRole/boundDestination, and — if it was the
-- squad's current Mover or a listed Cover member — clears that squad-level
-- bookkeeping too, so a dead/invalid bot never leaves a stuck role behind.
-- Called from onNPCDied / disconnectRecord (one grunt) as well as from
-- updateSquadBounding itself (mover arrived / timed out / went invalid).
local function releaseBoundRole(record: NPCRecord)
    if record.tacticalRole == nil and record.boundDestination == nil then
        return
    end
    record.tacticalRole = nil
    record.boundDestination = nil
    local squad = squads[record.squadId]
    if squad == nil then
        return
    end
    if squad.currentMoverNpcId == record.model then
        squad.currentMoverNpcId = nil
        squad.currentBoundStartedAt = 0
    end
    local idx = table.find(squad.coveringNpcIds, record.model)
    if idx ~= nil then
        table.remove(squad.coveringNpcIds, idx)
    end
end

-- Drops an entire squad's bounding state (no active Mover, nobody labeled Cover/
-- Shooter/Support) — used when the squad isn't alert, has no shared target
-- position, is already close enough (DO_NOT_BOUND_WITHIN_ATTACK_RANGE), or has
-- fewer than 2 living members to bound with. Cheap no-op once already clear.
local function clearSquadBounding(squad: SquadRecord)
    if squad.currentMoverNpcId == nil and #squad.coveringNpcIds == 0 then
        return
    end
    for _, record in pairs(npcs) do
        if record.squadId == squad.id then
            record.tacticalRole = nil
            record.boundDestination = nil
        end
    end
    squad.currentMoverNpcId = nil
    table.clear(squad.coveringNpcIds)
    squad.currentBoundStartedAt = 0
end

-- Picks the Mover's next bound point: `MOVE_BOUND_DISTANCE_MIN..MAX` studs toward
-- the shared target, offset sideways by this grunt's existing squad-spacing
-- formation direction (same shape every other squad goal in this file uses) so
-- movers from different slots don't all converge on one line. Never plans past
-- DO_NOT_BOUND_WITHIN_ATTACK_RANGE of the target — the final close is left to the
-- normal Attack approach instead of the bound overshooting into melee range.
local function boundDestinationFor(record: NPCRecord, targetPos: Vector3): Vector3
    local root = record.root
    local toTarget = targetPos - root.Position
    local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
    local forward = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
    local lo, hi = BOUNDING.MOVE_BOUND_DISTANCE_MIN :: number, BOUNDING.MOVE_BOUND_DISTANCE_MAX :: number
    local advance = lo + math.random() * (hi - lo)
    local maxAdvance = math.max(flat.Magnitude - (BOUNDING.DO_NOT_BOUND_WITHIN_ATTACK_RANGE :: number), 1)
    advance = math.min(advance, maxAdvance)
    local lateral = formationDirectionForSlot(record.formationSlotIndex)
    -- 0.35 is a fixed formation-shape ratio (how wide the lateral fan is relative
    -- to how far the bound advances), not an independent gameplay tunable — kept
    -- inline rather than adding a single-use Constants field for it.
    return root.Position + forward * advance + lateral * (advance * 0.35)
end

-- Re-evaluates squad `squad`'s bound-and-cover roles, at most once every
-- BOUND_REEVALUATE_INTERVAL (cheap early-return otherwise — safe to call from
-- every member's think, mirrors ensureFormationAssigned / clearStaleSquadAlert).
-- Only ever maintains MAX_ACTIVE_NPCS-scale squads, so a full `npcs` scan per
-- pass is cheap (same justification as getSeparationAdjustedGoal).
local function updateSquadBounding(squad: SquadRecord, now: number)
    if BOUNDING.ENABLED ~= true then
        return
    end
    if now - squad.lastBoundEvaluateAt < (BOUNDING.BOUND_REEVALUATE_INTERVAL :: number) then
        return
    end
    squad.lastBoundEvaluateAt = now

    local targetPos = squad.lastKnownTargetPosition
    local alert = now < squad.alertUntil
    if not alert or targetPos == nil then
        clearSquadBounding(squad)
        return
    end

    local living: { Model } = {}
    local nearest = math.huge
    for model, record in pairs(npcs) do
        if record.squadId == squad.id and not record.dead then
            table.insert(living, model)
            local d = (record.root.Position - targetPos).Magnitude
            if d < nearest then
                nearest = d
            end
        end
    end

    -- Need a Mover plus at least MIN_COVERING_BOTS_REQUIRED to bound at all, and
    -- no point bounding once the squad is already this close to the target.
    if #living < 1 + (BOUNDING.MIN_COVERING_BOTS_REQUIRED :: number)
        or nearest <= (BOUNDING.DO_NOT_BOUND_WITHIN_ATTACK_RANGE :: number) then
        clearSquadBounding(squad)
        return
    end

    -- Validate / retire the current Mover (dead, arrived, or timed out).
    local moverModel = squad.currentMoverNpcId
    local moverRecord: NPCRecord? = if moverModel ~= nil then npcs[moverModel] else nil
    if moverRecord ~= nil and moverRecord.dead then
        releaseBoundRole(moverRecord)
        moverModel, moverRecord = nil, nil
    end
    if moverRecord ~= nil then
        local dest = moverRecord.boundDestination
        local arrived = dest ~= nil and (moverRecord.root.Position - (dest :: Vector3)).Magnitude <= (BOUNDING.BOUND_ARRIVE_DISTANCE :: number)
        local timedOut = (now - squad.currentBoundStartedAt) >= (BOUNDING.SWAP_AFTER_MAX_TIME :: number)
        if (arrived and BOUNDING.SWAP_AFTER_MOVER_ARRIVES == true) or timedOut then
            if BOUNDING.DEBUG == true then
                Logger.debug("[AIService] squad", squad.id, "bound complete —", moverRecord.model.Name,
                    arrived and "(arrived)" or "(timed out)")
            end
            releaseBoundRole(moverRecord)
            moverModel, moverRecord = nil, nil
        end
    end

    -- MAX_MOVERS_PER_SQUAD is 1 by design in this pass (see
    -- docs/TECHNICAL_DEBT.md) — a single squad.currentMoverNpcId field, not a
    -- list. Pick the living member farthest from the target (closes the biggest
    -- gap; naturally excludes whoever just finished a bound since it's now nearer
    -- than everyone it left behind), so the squad actually alternates instead of
    -- re-picking the same mover every time.
    if moverRecord == nil then
        local best: Model? = nil
        local bestDist = -1
        for _, model in ipairs(living) do
            local candidate = npcs[model]
            if candidate ~= nil then
                local d = (candidate.root.Position - targetPos).Magnitude
                if d > bestDist then
                    bestDist = d
                    best = model
                end
            end
        end
        if best ~= nil then
            moverModel = best
            moverRecord = npcs[best]
            squad.currentMoverNpcId = best
            squad.currentBoundStartedAt = now
            if moverRecord ~= nil then
                moverRecord.tacticalRole = "Mover"
                moverRecord.boundDestination = boundDestinationFor(moverRecord, targetPos)
            end
            if BOUNDING.DEBUG == true then
                Logger.debug("[AIService] squad", squad.id, "mover assigned —", best.Name)
            end
        end
    end

    -- Everyone else living holds as Cover (thinkNPC's Attack-planted branch
    -- further refines this live to "Shooter"/keeps "Support" — see there).
    table.clear(squad.coveringNpcIds)
    for _, model in ipairs(living) do
        if model ~= moverModel then
            local record = npcs[model]
            if record ~= nil then
                record.tacticalRole = "Cover"
                record.boundDestination = nil
                table.insert(squad.coveringNpcIds, model)
            end
        end
    end
end

-- (Re)assigns every living squad member a formation slot index: 1 = leader/anchor
-- (the original spawn leader if still alive, else the first surviving member is
-- promoted), 2+ cycle through SLOT_OFFSETS' flanking/rear directions. Called once
-- at spawn, at most every FORMATION_SLOT_REASSIGN_INTERVAL thereafter (guarded
-- below), and immediately whenever a member dies — never every think tick.
local function assignFormationSlots(squad: SquadRecord, now: number)
    local members: { Model } = {}
    local leader: Model? = nil
    for model, record in pairs(npcs) do
        if record.squadId == squad.id and not record.dead then
            table.insert(members, model)
            if record.isLeader then
                leader = model
            end
        end
    end
    if leader == nil and #members > 0 then
        leader = members[1]  -- the original leader died; promote the first survivor
    end

    squad.members = members
    squad.leader  = leader
    table.clear(squad.formationSlotAssignments)

    if leader ~= nil then
        squad.formationSlotAssignments[leader] = 1
        local leaderRecord = npcs[leader]
        if leaderRecord ~= nil then
            leaderRecord.formationSlotIndex = 1
        end
    end
    local nextSlot = 2
    for _, model in ipairs(members) do
        if model ~= leader then
            squad.formationSlotAssignments[model] = nextSlot
            local memberRecord = npcs[model]
            if memberRecord ~= nil then
                memberRecord.formationSlotIndex = nextSlot
            end
            nextSlot += 1
        end
    end
    squad.lastFormationAssignAt = now

    if SPACING.DEBUG == true then
        Logger.debug("[AIService] squad", squad.id, "formation reassigned —", #members,
            "member(s), leader:", leader ~= nil and leader.Name or "none")
    end
end

-- Reassigns squad `id`'s formation slots if FORMATION_SLOT_REASSIGN_INTERVAL has
-- elapsed since the last pass. Cheap early-return; safe to call from every
-- member's think (mirrors the existing updateSquadAttackSlots recheck pattern).
local function ensureFormationAssigned(squad: SquadRecord, now: number)
    if SPACING.ENABLED == true and now - squad.lastFormationAssignAt >= (SPACING.FORMATION_SLOT_REASSIGN_INTERVAL :: number) then
        assignFormationSlots(squad, now)
    end
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

    local tchar: Model? = targetCharacterOf(record.target)
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
    local tchar: Model? = targetCharacterOf(record.target)

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

    -- Squad spacing: keep this grunt's formation slot fresh (cheap no-op unless
    -- FORMATION_SLOT_REASSIGN_INTERVAL has actually elapsed). Squad awareness:
    -- clear a stale alert the same way (cheap no-op unless CLEAR_ALERT_AFTER_NO_CONTACT
    -- has actually elapsed since the squad's last sighting/hit).
    do
        local squad = squads[record.squadId]
        if squad ~= nil then
            ensureFormationAssigned(squad, now)
            clearStaleSquadAlert(squad, now)
            -- AI squad bound-and-cover: cheap no-op unless BOUND_REEVALUATE_INTERVAL
            -- has actually elapsed (mirrors the two calls above).
            updateSquadBounding(squad, now)
        end
    end

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
                -- AI squad awareness: share this (re-)confirmed sighting with the
                -- squad every recheck, not just on first acquisition.
                shareSquadAlert(record, seen, sroot ~= nil and sroot.Position or nil, now)
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
    local tchar: Model? = targetCharacterOf(record.target)
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
            -- Burst just finished OR just got shot — head for a spot that breaks LOS
            -- until the window expires. Ahead of the range/LOS check so reaching cover
            -- doesn't flip to Chase.
            setState(record, "Cover")
            record.fightPoint = nil
            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
            if record.coverPoint == nil then
                record.coverPoint = findCoverPoint(record, troot.Position)
            end
            -- Stage 1F: if the player has moved around our cover and can see us again
            -- (we're parked at the spot but still in LOS), pick a fresh one on the far
            -- side of the nearest obstacle — this also stands the grunt back up (see
            -- below) since `arrived` becomes false against the fresh, not-yet-reached spot.
            local cp = record.coverPoint
            if inLos and cp ~= nil and (root.Position - cp).Magnitude <= AI.FIGHT_ARRIVE_DIST then
                record.coverPoint = findCoverPoint(record, troot.Position)
                cp = record.coverPoint
            end
            -- Only crouch once actually AT the cover spot — crouching mid-sprint while
            -- still exposed and running there is exactly what looked wrong; stand (run)
            -- there, then drop into cover on arrival.
            local arrived = cp ~= nil and (root.Position - cp).Magnitude <= AI.FIGHT_ARRIVE_DIST
            setCrouched(record, arrived)

            if arrived then
                -- At the hide spot: break LOS and go quiet for the rest of the window.
                humanoid.AutoRotate = true
                humanoid:MoveTo(cp or root.Position)
            elseif AI.COVER_RETREAT_FIRE == true and record.firing then
                -- Mid covering-fire burst (started below on an earlier think): hold
                -- still and keep facing the player — startBurst's own loop is doing
                -- the actual shooting. Do NOT re-issue MoveTo(cp) here or it cancels
                -- the plant; AutoRotate/faceToward + an active MoveTo fight each other
                -- (this is what froze grunts in place back in Stage 1D).
                humanoid.AutoRotate = false
                humanoid:MoveTo(root.Position)
                faceToward(record, troot.Position)
            elseif AI.COVER_RETREAT_FIRE == true and inLos and now >= record.nextCoverShotClock then
                -- Bounding-overwatch pulse: stop, face the player, fire a burst back,
                -- then resume walking to cover once it (and its cooldown) finishes.
                local lo, hi = AI.COVER_RETREAT_SHOT_MIN :: number, AI.COVER_RETREAT_SHOT_MAX :: number
                record.nextCoverShotClock = now + lo + math.random() * (hi - lo)
                humanoid.AutoRotate = false
                humanoid:MoveTo(root.Position)
                faceToward(record, troot.Position)
                startBurst(record)
            else
                -- Between shots, no LOS, or the retreat-fire flag is off — just keep
                -- retreating toward cover. `cp` is already an individually-computed
                -- LOS-breaking spot (Stage 1D findCoverPoint), so radius 0: separation
                -- + throttling only, no additional squad spread/jitter.
                humanoid.AutoRotate = true
                issueSquadMoveGoal(record, humanoid, cp or root.Position, 0, now)
            end
        elseif BOUNDING.ENABLED == true and record.tacticalRole == "Mover" and record.boundDestination ~= nil
            and dist > (BOUNDING.DO_NOT_BOUND_WITHIN_ATTACK_RANGE :: number) then
            -- AI squad bound-and-cover: this grunt is the squad's currently-advancing
            -- Mover — keep closing on its bound destination instead of planting/
            -- fighting from here, even though ATTACK_RANGE/LOS may already allow it.
            -- Falls through to the normal Attack/Chase branches below on its own once
            -- it's close enough that bounding no longer applies (updateSquadBounding
            -- also clears the role on arrival/timeout/target loss).
            setState(record, "Chase")
            record.coverUntil = 0
            record.coverPoint = nil
            record.fightPoint = nil
            setCrouched(record, false)
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
            issueSquadMoveGoal(record, humanoid, record.boundDestination :: Vector3, 0, now)
            if BOUNDING.MOVER_SHOULD_NOT_SHOOT ~= true and inLos and not record.firing and now >= record.reactionReadyAt then
                startBurst(record)
            end
        elseif dist <= AI.ATTACK_RANGE and inLos then
            setState(record, "Attack")
            record.coverPoint = nil
            local spot = record.fightPoint
            if spot == nil and AI.FIGHT_FROM_COVER == true then
                spot = findFightingPosition(record, troot.Position)
                if spot == nil and SPACING.ENABLED == true then
                    -- No literal cover nearby (findFightingPosition gave up). Rather
                    -- than planting wherever ATTACK_RANGE happened to be reached —
                    -- which is how a squad converging on the player ends up bunched
                    -- in the open — fan out around the target using the formation
                    -- slot at COMBAT_SPREAD_RADIUS.
                    spot = squadSpreadGoal(record, troot.Position, SPACING.COMBAT_SPREAD_RADIUS :: number)
                end
                record.fightPoint = spot
            end
            if spot ~= nil and (root.Position - spot).Magnitude > AI.FIGHT_ARRIVE_DIST then
                -- Still moving into a firing spot — stand while moving. `spot` is
                -- already a final, individually-computed position (real cover, or the
                -- combat-spread fallback above), so radius 0 here.
                setCrouched(record, false)
                humanoid.AutoRotate = true
                humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
                issueSquadMoveGoal(record, humanoid, spot, 0, now)
            else
                -- Planted. Crouch — and fire from the crouch, nothing blocks that —
                -- only when the plant spot is actually beside cover (re-checked live
                -- with hasNearbyCover rather than just "spot ~= nil", since `spot` can
                -- now also be the squad-spacing COMBAT_SPREAD_RADIUS fallback above,
                -- which has no cover guarantee); otherwise stand in the open.
                setCrouched(record, spot ~= nil and hasNearbyCover(spot, troot.Position))
                humanoid.WalkSpeed = AI.ATTACK_MOVE_SPEED

                -- AI fire discipline: at most MAX_ACTIVE_SHOOTERS_PER_SQUAD grunts in
                -- this squad may actually pull the trigger at once. Consolidates the
                -- original Stage 1C per-squad attack-slot mechanism in place (renamed
                -- fields/constants, added LOS/range eligibility + a timeout) rather
                -- than running it twice under two names — see docs/TECHNICAL_DEBT.md
                -- "AI squad fire discipline".
                local squad = squads[record.squadId]
                local hasAttackSlot = true
                if DISCIPLINE.ENABLED == true and squad ~= nil then
                    updateSquadAttackSlots(squad, now)
                    hasAttackSlot = record.hasAttackSlot
                end

                -- AI squad bound-and-cover: a Mover caught here (already within
                -- ATTACK_RANGE/LOS but not yet past DO_NOT_BOUND_WITHIN_ATTACK_RANGE —
                -- see the bound-override branch above) still must not shoot while
                -- MOVER_SHOULD_NOT_SHOOT is true; a bounding Cover/Shooter/Support bot
                -- must not shoot at all when COVER_BOT_CAN_SHOOT is false, even if it
                -- holds a fire-discipline slot. Purely a further restriction on top of
                -- hasAttackSlot — never grants a slot fire discipline didn't already.
                local effectiveHasSlot = hasAttackSlot
                if hasAttackSlot and BOUNDING.ENABLED == true then
                    if record.tacticalRole == "Mover" and BOUNDING.MOVER_SHOULD_NOT_SHOOT == true then
                        effectiveHasSlot = false
                    elseif (record.tacticalRole == "Cover" or record.tacticalRole == "Shooter" or record.tacticalRole == "Support")
                        and BOUNDING.COVER_BOT_CAN_SHOOT ~= true then
                        effectiveHasSlot = false
                    end
                end

                if effectiveHasSlot then
                    if BOUNDING.ENABLED == true and record.tacticalRole ~= nil and record.tacticalRole ~= "Mover" then
                        if record.tacticalRole ~= "Shooter" and BOUNDING.DEBUG == true then
                            Logger.debug("[AIService]", record.model.Name, "bound role -> Shooter")
                        end
                        record.tacticalRole = "Shooter"
                    end
                    -- Active shooter: face the player and fire once reaction-time
                    -- elapses. "If target is lost before reactionReadyAt, do not shoot
                    -- magically" is automatic: this branch only runs while troot is
                    -- non-nil (a live, in-range target), so losing the target routes
                    -- to Chase/Search instead and startBurst is simply never reached.
                    humanoid.AutoRotate = false
                    humanoid:MoveTo(root.Position)
                    faceToward(record, troot.Position)

                    local reactionReady = now >= record.reactionReadyAt
                    if reactionReady and record.reactionAnnouncedAt ~= record.reactionReadyAt then
                        record.reactionAnnouncedAt = record.reactionReadyAt
                        if TUNE.DEBUG == true then
                            Logger.debug("[AIService]", record.model.Name, "reaction-ready, engaging")
                        end
                    end
                    if not record.firing and reactionReady then
                        startBurst(record)
                    end
                else
                    -- AI squad bound-and-cover: relabel a bounding bot that's holding
                    -- fire here (no slot, or COVER_BOT_CAN_SHOOT suppressed it) — "Cover"
                    -- if it still has its own LOS, "Support" if it doesn't (matches the
                    -- NPCRecord field doc: Support = no LOS at all yet).
                    if BOUNDING.ENABLED == true and record.tacticalRole ~= nil and record.tacticalRole ~= "Mover" then
                        record.tacticalRole = if inLos then "Cover" else "Support"
                    end
                    -- No attack slot: never startBurst here (WAITING_BOT_CAN_SHOOT is
                    -- false by default — see below for the explicit opt-in escape
                    -- hatch). Track the target and/or reposition to a support/hold
                    -- position instead of stacking damage on top of the active
                    -- shooters and instead of just standing there doing nothing.
                    if DISCIPLINE.ENABLED ~= true or DISCIPLINE.WAITING_BOT_CAN_TRACK_TARGET == true then
                        humanoid.AutoRotate = false
                        faceToward(record, troot.Position)
                    else
                        humanoid.AutoRotate = true
                    end

                    if DISCIPLINE.ENABLED == true and DISCIPLINE.WAITING_BOT_CAN_CHASE == true then
                        -- Only pick a NEW support spot on the (randomized,
                        -- non-shooter-specific) reposition timer — "do not jitter
                        -- between goals" — issueSquadMoveGoal's own throttle then
                        -- governs how often that goal is actually re-issued.
                        local lo, hi = DISCIPLINE.NON_SHOOTER_REPOSITION_INTERVAL_MIN :: number,
                            DISCIPLINE.NON_SHOOTER_REPOSITION_INTERVAL_MAX :: number
                        if now - record.lastSupportRepositionAt >= (lo + math.random() * (hi - lo)) then
                            record.lastSupportRepositionAt = now
                            -- Alternate between holding farther back at a firing angle
                            -- and moving up closer to support — reuses the squad-
                            -- spacing formation direction for which side to favor.
                            local dir = formationDirectionForSlot(record.formationSlotIndex)
                            if dir.Magnitude < 0.01 then
                                local ang = math.random() * math.pi * 2
                                dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
                            end
                            local holdAngle = math.random() < 0.5
                            local distLo = if holdAngle then DISCIPLINE.HOLD_ANGLE_DISTANCE_MIN :: number else DISCIPLINE.SUPPORT_MOVE_DISTANCE_MIN :: number
                            local distHi = if holdAngle then DISCIPLINE.HOLD_ANGLE_DISTANCE_MAX :: number else DISCIPLINE.SUPPORT_MOVE_DISTANCE_MAX :: number
                            local dist = distLo + math.random() * (distHi - distLo)
                            local supportSpot = troot.Position + dir * dist
                            humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
                            -- supportSpot is already a final, individually-computed
                            -- position (per-grunt formation direction + random
                            -- distance), so radius 0: separation + throttle only.
                            issueSquadMoveGoal(record, humanoid, supportSpot, 0, now)
                        end
                    else
                        humanoid:MoveTo(root.Position)
                    end

                    -- Escape hatch (off by default): explicitly let waiting bots fire
                    -- anyway, bypassing the slot limit. Reads Constants.AI.SHOT_* via
                    -- the normal startBurst/fireOneShot path, no separate damage logic.
                    -- Bound-and-cover's own restrictions still apply on top of it.
                    local escapeHatchBlocked = BOUNDING.ENABLED == true
                        and ((record.tacticalRole == "Mover" and BOUNDING.MOVER_SHOULD_NOT_SHOOT == true)
                            or ((record.tacticalRole == "Cover" or record.tacticalRole == "Support")
                                and BOUNDING.COVER_BOT_CAN_SHOOT ~= true))
                    if DISCIPLINE.WAITING_BOT_CAN_SHOOT == true and not escapeHatchBlocked
                        and not record.firing and now >= record.reactionReadyAt then
                        startBurst(record)
                    end
                end
            end
        else
            setState(record, "Chase")
            setCrouched(record, false)
            record.coverUntil = 0
            record.coverPoint = nil
            record.fightPoint = nil
            humanoid.AutoRotate = true

            if BOUNDING.ENABLED == true and record.tacticalRole == "Mover" and record.boundDestination ~= nil then
                humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
                issueSquadMoveGoal(record, humanoid, record.boundDestination :: Vector3, 0, now)
            elseif BOUNDING.ENABLED == true and record.tacticalRole ~= nil then
                -- Covering (Cover/Shooter/Support): hold this ground instead of also
                -- rushing forward while the squad's Mover advances — the core "some
                -- bots hold while another moves" ask. Still turns to track the target
                -- if it can see it. Does not route through findCoverPoint/
                -- findFightingPosition here — see docs/TECHNICAL_DEBT.md "AI squad
                -- bound-and-cover" for that deliberate simplification.
                humanoid:MoveTo(root.Position)
                if inLos then
                    faceToward(record, troot.Position)
                end
            else
                humanoid.WalkSpeed = AI.NPC_CHASE_SPEED
                issueSquadMoveGoal(record, humanoid, troot.Position, SPACING.CHASE_SPREAD_RADIUS :: number, now)
            end
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
            issueSquadMoveGoal(record, humanoid, lastSeen, SPACING.CHASE_SPREAD_RADIUS :: number, now)
        else
            -- Stale: move in and flank the last-known position on an arc. flankPointFor
            -- already spreads squadmates via flankSide (Stage 1E) — that logic is
            -- untouched here; radius 0 layers on separation + throttling only.
            -- AI dynamic navigation: nav-mode (useNav = true) so this actually paths
            -- around obstacles on a big map instead of a straight-line MoveTo — see
            -- docs/TECHNICAL_DEBT.md "AI dynamic navigation" for why Chase above (the
            -- fresh-sighting branch) deliberately keeps the direct MoveTo instead.
            setState(record, "Search")
            humanoid.WalkSpeed = AI.NPC_WALK_SPEED
            issueSquadMoveGoal(record, humanoid, flankPointFor(record, lastSeen), 0, now, true)
        end
        return
    end

    -- ── No own memory, but a squadmate shared a last-known position ─────────
    -- Only reached once this grunt's OWN sighting (above) is long gone — personal
    -- memory always takes priority over secondhand squad info. LOSE_TARGET_GRACE_TIME
    -- gives a brief beat after this grunt's own contact lapses before it leans on
    -- squad-shared data (this file's interpretation of that constant — not
    -- explicit in the spec; see docs/TECHNICAL_DEBT.md "AI squad awareness").
    if AWARENESS.ENABLED == true and record.isAlertedBySquad then
        local squad = squads[record.squadId]
        local sharedPos = squad ~= nil and squad.lastKnownTargetPosition or nil
        local fresh = squad ~= nil and (now - squad.lastKnownUpdateAt) <= (AWARENESS.LAST_KNOWN_POSITION_MEMORY :: number)
        local pastGrace = (now - record.lastSawTargetAt) >= (AWARENESS.LOSE_TARGET_GRACE_TIME :: number)
        if sharedPos ~= nil and fresh and pastGrace then
            setCrouched(record, false)
            record.coverUntil = 0
            record.coverPoint = nil
            record.fightPoint = nil
            -- Reuses the "Search" state rather than adding a dedicated
            -- "Investigate" AIState — a label-only difference that would otherwise
            -- touch the state type and every state-keyed system (fire discipline's
            -- setState hook, debug logs) for no behavioral gain.
            setState(record, "Search")
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = AI.NPC_WALK_SPEED
            -- Pick a fresh small offset near (not exactly at) the shared position —
            -- either the current one has gone stale (MOVE_GOAL_RECALCULATE_INTERVAL,
            -- reusing the squad-spacing cadence rather than a new constant, so the
            -- offset doesn't jitter every think) or the grunt actually reached it
            -- (INVESTIGATE_ARRIVE_DISTANCE) and should check a different nearby spot
            -- rather than idling there. issueSquadMoveGoal's own throttle governs
            -- the actual MoveTo reissue on top of either trigger.
            local arrived = record.investigateGoal ~= nil
                and (root.Position - (record.investigateGoal :: Vector3)).Magnitude <= (AWARENESS.INVESTIGATE_ARRIVE_DISTANCE :: number)
            if record.investigateGoal == nil or arrived
                or (now - record.lastMoveGoalAt) >= (SPACING.MOVE_GOAL_RECALCULATE_INTERVAL :: number) then
                local ang  = math.random() * math.pi * 2
                -- AI dynamic navigation: consolidated onto NAV.SEARCH_RADIUS_MIN/MAX
                -- (the task's required "search goals around last known position"
                -- radius) in place of the awareness pass's own INVESTIGATE_DISTANCE_MIN/
                -- MAX — same role, one radius knob rather than two. AWARENESS's fields
                -- are left declared, now unread, per this project's established
                -- consolidate-in-place convention; see docs/TECHNICAL_DEBT.md "AI
                -- dynamic navigation".
                local distLo, distHi = NAV.SEARCH_RADIUS_MIN :: number, NAV.SEARCH_RADIUS_MAX :: number
                local dist = distLo + math.random() * (distHi - distLo)
                record.investigateGoal = sharedPos + Vector3.new(math.cos(ang), 0, math.sin(ang)) * dist
                if AWARENESS.DEBUG == true then
                    Logger.debug("[AIService]", record.model.Name, "investigating near squad's last-known position")
                end
            end
            -- investigateGoal is already a final, individually-offset position, so
            -- radius 0: separation + throttle only (matches every other
            -- individually-computed goal in this file). AI dynamic navigation:
            -- nav-mode (useNav = true) so investigating actually paths there on a
            -- big map; if it turns out unreachable (stuck), drop it so the next
            -- think picks a fresh nearby offset instead of pounding a dead spot.
            local stuck = issueSquadMoveGoal(record, humanoid, record.investigateGoal :: Vector3, 0, now, true)
            if stuck == true then
                if AWARENESS.DEBUG == true then
                    Logger.debug("[AIService]", record.model.Name, "investigate goal unreachable — picking a different one")
                end
                record.investigateGoal = nil
                record.currentNavigationGoal = nil
                record.currentPath = nil
            end
            return
        end
        record.investigateGoal = nil
    end

    -- No target: patrol authored Workspace/AIPatrolPoints if any exist, else roam
    -- dynamically (AI dynamic navigation — AIPatrolPoints is optional, not
    -- required). Idle near the squad spawn only if navigation is itself disabled.
    setCrouched(record, false)
    record.coverUntil = 0
    record.coverPoint = nil
    record.fightPoint = nil
    humanoid.AutoRotate = true
    humanoid.WalkSpeed = AI.NPC_WALK_SPEED

    if #patrolPoints > 0 then
        setState(record, "Patrol")
        issueSquadMoveGoal(record, humanoid, patrolDestination(record), SPACING.IDLE_SPREAD_RADIUS :: number, now)

        if record.isLeader then
            local squad = squads[record.squadId]
            if squad ~= nil then
                local pt = patrolPoints[((squad.patrolIndex - 1) % #patrolPoints) + 1]
                if (root.Position - pt.Position).Magnitude <= AI.PATROL_ARRIVE_DISTANCE then
                    squad.patrolIndex += 1
                end
            end
        end
    elseif NAV.ENABLED == true then
        setState(record, "Idle")
        dynamicRoam(record, humanoid, now)
    else
        -- Navigation disabled and no patrol points: the original pre-navigation
        -- Idle behavior — hold near the squad spawn (patrolDestination's own
        -- fallback when patrolPoints is empty).
        setState(record, "Idle")
        issueSquadMoveGoal(record, humanoid, patrolDestination(record), SPACING.IDLE_SPREAD_RADIUS :: number, now)
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
    -- AI squad awareness: this grunt is about to leave `npcs` (onNPCDied does that
    -- right after calling this), so nothing else could read these again — cleared
    -- anyway for hygiene, matching every other per-death field above.
    record.isAlertedBySquad = false
    record.investigateGoal = nil
    -- AI squad bound-and-cover: release this grunt's Mover/Cover role (and the
    -- squad's currentMoverNpcId/coveringNpcIds bookkeeping if it held one) so a
    -- dead or destroyed grunt never leaves a stuck role behind.
    releaseBoundRole(record)
    -- AI dynamic navigation: drop any in-progress path/roam state. disconnectRecord
    -- is also called from non-death paths (RespawnAllSquads, Destroy()), so this is
    -- what satisfies "Destroy() clears all path/nav data" — Destroy() already
    -- routes every record through here.
    record.currentPath = nil
    record.currentWaypointIndex = 1
    record.currentNavigationGoal = nil
    record.stuckSince = 0
    record.roamGoal = nil
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

    -- Fire discipline: free this grunt's attack slot immediately on death (setState's
    -- own release hook never runs here since onNPCDied sets record.state directly).
    releaseAttackSlot(record)

    -- Squad spacing: reassign formation slots immediately on a death (per spec —
    -- not waiting for the next FORMATION_SLOT_REASSIGN_INTERVAL) so the rest of the
    -- squad doesn't keep orbiting a now-vacant slot. If that leaves nobody alive,
    -- drop the squad record entirely rather than leaving a zero-member husk around.
    local squad = squads[record.squadId]
    if squad ~= nil then
        assignFormationSlots(squad, os.clock())
        if #squad.members == 0 then
            squads[record.squadId] = nil
            if SPACING.DEBUG == true then
                Logger.debug("[AIService] squad", record.squadId, "cleared — no members remain")
            end
        end
    end

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

-- AI arena / factions (2026-09-11): how many LIVING grunts currently belong to
-- `faction`. Shared by the public AIService.CountLivingByFaction wrapper and
-- runArenaBattle's own wipe check below, so there's one counting rule, not two.
local function countLivingByFaction(faction: string): number
    local n = 0
    for _, record in pairs(npcs) do
        if not record.dead and record.faction == faction then
            n += 1
        end
    end
    return n
end

-- `faction` (AI arena, 2026-09-11) is a key into Constants.AI_FACTIONS; an
-- unknown key falls back to the DEFAULT entry (logged once via warnedBadFaction
-- below) rather than erroring a whole squad's spawn.
local function spawnOne(worldCFrame: CFrame, squadId: number, isLeader: boolean, index: number, size: number, faction: string): Model
    npcCounter += 1
    local factions = Constants.AI_FACTIONS :: any
    local factionCfg = factions[faction]
    if factionCfg == nil then
        factionCfg = factions.DEFAULT
        if not warnedBadFaction then
            warnedBadFaction = true
            Logger.warn("[AIService] unknown AI faction \"" .. tostring(faction) .. "\" — falling back to DEFAULT")
        end
    end
    -- AI shotgun (2026-09-11): a per-grunt roll, independent of faction/squad
    -- — CHANCE below decides "some of the AI" (any squad, either arena, or the
    -- main game's AI zone, can end up with a mix of rifle and shotgun grunts).
    local weaponKey: string = AI.WEAPON_NAME :: string
    if SHOTGUN.ENABLED == true and math.random() < (SHOTGUN.CHANCE :: number) then
        weaponKey = SHOTGUN.WEAPON_KEY :: string
    end

    local model, humanoid, root, rightShoulder = buildRig(worldCFrame, factionCfg.BODY_COLOR, factionCfg.LIMB_COLOR)
    model.Name = AI.NPC_NAME_PREFIX .. "_" .. tostring(squadId) .. "_" .. tostring(npcCounter)
    model:SetAttribute("BR_AINpc", true)
    model:SetAttribute("BR_AIFaction", faction)
    model:SetAttribute("BR_AIWeapon", weaponKey)
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
        faction  = faction,
        weaponKey= weaponKey,

        state        = "Idle",
        target       = nil,
        lastSeenPos  = nil,
        lastSeenClock= 0,

        coverUntil = 0,
        coverPoint = nil,
        fightPoint = nil,
        flankSide  = (index % 2 == 0) and 1 or -1,
        nextCoverShotClock = 0,

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

        formationSlotIndex = 1,   -- corrected by assignFormationSlots() right after this record is registered
        currentMoveGoal    = nil,
        lastMoveGoalAt     = 0,
        lastMoveAnchor     = nil,

        hasAttackSlot           = false,
        attackSlotAssignedAt    = 0,
        lastSupportRepositionAt = 0,

        isAlertedBySquad = false,
        investigateGoal  = nil,

        tacticalRole     = nil,
        boundDestination = nil,

        currentPath            = nil,
        currentWaypointIndex   = 1,
        currentNavigationGoal  = nil,
        -- -math.huge, same reasoning/bug class as several throttle-gate fields
        -- above (lastAttackSlotUpdateAt / lastKnownUpdateAt / lastBoundEvaluateAt):
        -- a 0-init would let PATH_RECALCULATE_INTERVAL / PATH_STUCK_CHECK_INTERVAL
        -- skip this grunt's very first pathfinding/stuck check if it happens within
        -- the first couple seconds of server life.
        lastPathRecalculateAt  = -math.huge,
        lastStuckCheckAt       = -math.huge,
        lastStuckCheckPosition = nil,
        stuckSince             = 0,

        roamGoal          = nil,
        roamCooldownUntil = 0,

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
-- `factionKey` (AI arena, 2026-09-11): nil/omitted resolves to
-- Constants.AI.DEFAULT_FACTION — every pre-existing call site (auto-spawn,
-- RespawnAllSquads) omits it, so this is a no-op for all of today's behavior.
local function spawnSquad(spawnCFrame: CFrame?, squadSize: number?, factionKey: string?): { Model }
    assert(spawnCFrame == nil or typeof(spawnCFrame) == "CFrame",
        "[AIService] SpawnSquad: spawnCFrame must be a CFrame or nil")
    assert(squadSize == nil or (type(squadSize) == "number" and squadSize >= 1),
        "[AIService] SpawnSquad: squadSize must be a number >= 1 or nil")
    assert(factionKey == nil or type(factionKey) == "string",
        "[AIService] SpawnSquad: factionKey must be a string or nil")
    local faction: string = factionKey or (AI.DEFAULT_FACTION :: string)

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

        alerted = false,

        members                 = {},
        leader                  = nil,
        formationSlotAssignments = {},
        lastFormationAssignAt   = 0,

        activeShooterIds       = {},
        lastAttackSlotUpdateAt = -math.huge,  -- guarantees the first updateSquadAttackSlots() call always runs regardless of server os.clock() at spawn time

        alertUntil             = 0,
        lastKnownTargetPosition = nil,
        lastKnownTargetPlayer   = nil,
        -- -math.huge, same reasoning/bug class as lastAttackSlotUpdateAt above: a
        -- 0-init would let the LAST_KNOWN_POSITION_SHARE_INTERVAL throttle in
        -- shareSquadAlert skip a squad's very first-ever share if it happens within
        -- the first 0.75s of server life.
        lastKnownUpdateAt      = -math.huge,
        lastContactAt          = 0,  -- safe at 0: clearStaleSquadAlert's own pre-filter (lastKnownTargetPosition == nil) shields this before it's ever checked

        currentMoverNpcId    = nil,
        coveringNpcIds       = {},
        currentBoundStartedAt = 0,
        -- -math.huge, same reasoning/bug class as lastAttackSlotUpdateAt /
        -- lastKnownUpdateAt above: a 0-init would let the BOUND_REEVALUATE_INTERVAL
        -- throttle in updateSquadBounding skip this squad's very first evaluation if
        -- it happens within the first 1.25s of server life.
        lastBoundEvaluateAt   = -math.huge,
    }

    local models: { Model } = {}
    for i = 1, size do
        if not running then
            break
        end
        local memberCFrame = origin * CFrame.new(slotOffset(i, size))
        table.insert(models, spawnOne(memberCFrame, squadId, i == 1, i, size, faction))
        if i < size then
            task.wait(AI.SPAWN_DELAY_BETWEEN_NPCS)
        end
    end

    -- Squad spacing: assign formation slots immediately (leader = slot 1) rather
    -- than waiting for the first think's lazy FORMATION_SLOT_REASSIGN_INTERVAL check.
    local newSquad = squads[squadId]
    if newSquad ~= nil then
        assignFormationSlots(newSquad, os.clock())
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
-- AI arena / factions — auto-spawn + self-healing RED vs BLUE battle
-- ============================================================
-- Generalized (2026-09-11, second arena) to take the arena's Constants table
-- and faction key pair as parameters, rather than closing over the single
-- Constants.AI_ARENA global — so the exact same battle logic runs both the
-- original arena (ARENA_RED/ARENA_BLUE) and the new second arena
-- (ARENA2_RED/ARENA2_BLUE) as two independent threads. Behavior for the first
-- arena is unchanged; this is a pure parameterization.

-- Whether the auto-spawn-battle system is allowed to run for `cfg` — same
-- Studio/RUN_IN_PUBLISHED split every other dev-only system in this file uses.
local function arenaEnabled(cfg: any): boolean
    if cfg == nil or cfg.ENABLED ~= true or cfg.AUTO_SPAWN_BATTLE ~= true then
        return false
    end
    if RunService:IsStudio() then
        return true
    end
    return cfg.RUN_IN_PUBLISHED == true
end

-- Spawns one faction's squad at its arena position, retrying briefly if it
-- comes back empty (e.g. MAX_ACTIVE_NPCS is momentarily full while the game's
-- own single-faction auto-spawn — or the OTHER arena's — is still in
-- progress) rather than giving up after a single attempt.
local function spawnArenaSquad(cfg: any, cframe: CFrame, factionKey: string): { Model }
    for _ = 1, (cfg.SPAWN_RETRY_ATTEMPTS :: number) do
        if not running then
            return {}
        end
        local models = spawnSquad(cframe, cfg.SQUAD_SIZE, factionKey)
        if #models > 0 then
            return models
        end
        task.wait(cfg.SPAWN_RETRY_INTERVAL :: number)
    end
    Logger.warn("[AIService] AI arena: gave up spawning faction", factionKey,
        "after", cfg.SPAWN_RETRY_ATTEMPTS, "attempt(s)")
    return {}
end

-- Auto-spawns `redFaction` vs `blueFaction` at `cfg`'s two spawn positions,
-- then watches (every cfg.BATTLE_CHECK_INTERVAL) until either side's living
-- count hits 0 — a battle conclusion, or an unrelated RespawnBots/KillAllBots
-- wipe; this doesn't distinguish why — and after cfg.BATTLE_RESPAWN_DELAY
-- respawns BOTH sides fresh. Runs entirely inside AIService (never a
-- cross-script call — AIService.server.lua is a Script, not a requirable
-- ModuleScript; the AIArenaBuilder scripts only build each arena's geometry,
-- independently, off the same Constants tables — see docs/TECHNICAL_DEBT.md
-- "AI arena / factions"). Each arena gets its OWN faction key pair (not
-- shared) specifically so countLivingByFaction scopes to that arena's own
-- battle, not a combined count across every arena using "red"/"blue".
local function runArenaBattle(cfg: any, redFaction: string, blueFaction: string)
    local origin     = cfg.ORIGIN :: Vector3
    local redCFrame  = CFrame.new(origin + (cfg.RED_SPAWN_POSITION :: Vector3))
    local blueCFrame = CFrame.new(origin + (cfg.BLUE_SPAWN_POSITION :: Vector3))

    local function spawnBothFresh()
        spawnArenaSquad(cfg, redCFrame, redFaction)
        spawnArenaSquad(cfg, blueCFrame, blueFaction)
        if cfg.DEBUG == true then
            Logger.debug("[AIService] AI arena: battle (re)started —", redFaction, "vs", blueFaction)
        end
    end

    spawnBothFresh()

    while running do
        task.wait(cfg.BATTLE_CHECK_INTERVAL :: number)
        if not running then
            break
        end
        local redAlive  = countLivingByFaction(redFaction)
        local blueAlive = countLivingByFaction(blueFaction)
        if redAlive <= 0 or blueAlive <= 0 then
            if cfg.DEBUG == true then
                Logger.debug("[AIService] AI arena: one side wiped (", redFaction, redAlive, "/", blueFaction, blueAlive,
                    ") — respawning in", cfg.BATTLE_RESPAWN_DELAY, "s")
            end
            task.wait(cfg.BATTLE_RESPAWN_DELAY :: number)
            if running then
                spawnBothFresh()
            end
        end
    end
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
    patrolPoints, warnedNoPatrol = collectParts(AI.PATROL_FOLDER_NAME, warnedNoPatrol, true)

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
        -- AI invisibility toggle: a hit from an invisible player is treated
        -- exactly like an unidentified attacker below — no target acquisition,
        -- no position shared with the squad. Without this, shooting a grunt
        -- while "invisible" would instantly reveal you anyway, defeating the
        -- whole point of the toggle.
        if attacker ~= nil and isAIInvisible(attacker) then
            attacker = nil
        end
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
            -- AI squad awareness: share the attacker + position (when known) with
            -- the squad, per spec point 3.
            shareSquadAlert(record, attacker, aroot ~= nil and aroot.Position or nil, now)
        else
            -- Attacker unknown (e.g. environment damage, or an invisible player's
            -- hit, per above) — still puts the squad on edge without a location to
            -- share or investigate toward.
            shareSquadAlert(record, nil, nil, now)
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
            patrolPoints, warnedNoPatrol = collectParts(AI.PATROL_FOLDER_NAME, warnedNoPatrol, true)
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

    -- Any player can request a full AI kill from the LoadoutMenu button, dev and
    -- published alike. Server-authoritative and cooldown-gated (shared, not
    -- per-player). Unlike RespawnBots this routes every grunt through the REAL
    -- death path (ragdoll, blood, cleanup timer) and does not spawn replacements.
    local killAllConn = KillAllBots.OnServerEvent:Connect(function(player: Player)
        local now = os.clock()
        local cooldown = AI.KILL_ALL_COOLDOWN_SECONDS :: number
        if now - lastManualKillAllClock < cooldown then
            return
        end
        lastManualKillAllClock = now
        Logger.debug("[AIService] KillAllBots requested by", player.Name)
        AIService.KillAllBots()
    end)
    table.insert(serviceConns, killAllConn)

    -- AI arena spectating (2026-09-11): teleport the requesting player's own
    -- character above Workspace/BrokenReality_AIArena so they can watch the
    -- ARENA_RED vs ARENA_BLUE battle. Only ever moves the requester — no shared
    -- cooldown needed (unlike RespawnBots/KillAllBots, which affect every
    -- player's AI) — a small per-player debounce just guards against an
    -- accidental double-fire, not a real gameplay gate. Sets HumanoidRootPart.CFrame
    -- directly, same convention TeamService.teleportToSpawn already uses for
    -- round-start spawning. Fires TeleportToArena back to the SAME client once the
    -- teleport lands — that confirmation, not the raw button press, is what
    -- SpectatorFlyController treats as permission to grant fly.
    local teleportConn = TeleportToArena.OnServerEvent:Connect(function(player: Player)
        local now = os.clock()
        local last = lastTeleportToArenaClock[player]
        if last ~= nil and now - last < 1 then
            return
        end
        lastTeleportToArenaClock[player] = now

        local character = player.Character
        if character == nil then
            return
        end
        local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root == nil then
            return
        end

        local origin = ARENA.ORIGIN :: Vector3
        local height = ARENA.SPECTATE_HEIGHT :: number
        root.CFrame = CFrame.new(origin + Vector3.new(0, height, 0))
        root.AssemblyLinearVelocity = Vector3.zero

        -- Grunts detect/attack unconditionally out to DETECTION_RANGE (120) /
        -- ATTACK_RANGE (90) studs — both farther than SPECTATE_HEIGHT, so a
        -- spectator flying near the arena is a fair target without this.
        -- SetInvincible (DamageService) is keyed off the Character Model, so a
        -- future normal respawn (a fresh Model from TeamService) is never
        -- invincible by default.
        pcall(function()
            DamageService:SetInvincible(character :: Model, true)
        end)

        if ARENA.DEBUG == true then
            Logger.debug("[AIService] teleported", player.Name, "above the AI arena")
        end
        TeleportToArena:FireClient(player)
    end)
    table.insert(serviceConns, teleportConn)

    local teleportCleanupConn = Players.PlayerRemoving:Connect(function(player: Player)
        lastTeleportToArenaClock[player] = nil
    end)
    table.insert(serviceConns, teleportCleanupConn)

    -- AI invisibility toggle (2026-09-11): sets/clears Constants.ATTR_AI_INVISIBLE
    -- on the requesting player. No cooldown — only ever affects the requester,
    -- and findVisibleTarget/targetRootOf/the DamageDealt listener above are the
    -- real gate (this just flips the attribute they all read).
    local setInvisibleConn = SetAIInvisible.OnServerEvent:Connect(function(player: Player, enabled: any)
        local on = enabled == true
        player:SetAttribute(Constants.ATTR_AI_INVISIBLE, on)
        if AI.DEBUG then
            Logger.debug("[AIService]", player.Name, "AI invisibility:", on and "ON" or "OFF")
        end
    end)
    table.insert(serviceConns, setInvisibleConn)

    if autoSpawnEnabled() and #spawnParts == 0 then
        local flagName = if RunService:IsStudio()
            then "SPAWN_ON_SERVER_START_IN_STUDIO"
            else "SPAWN_ON_SERVER_START_IN_PUBLISHED"
        Logger.warn("[AIService]", flagName, "is on but Workspace." .. AI.SPAWN_FOLDER_NAME .. " has no spawn parts yet — will spawn if one appears")
    end
    autoSpawnSquads()

    -- AI arena / factions: independent of the game's own single-faction
    -- auto-spawn above — its own Studio/RUN_IN_PUBLISHED gate, its own thread.
    if arenaEnabled(ARENA) then
        arenaThread = task.spawn(function()
            runArenaBattle(ARENA, "ARENA_RED", "ARENA_BLUE")
        end)
    end
    -- Second, separate AI arena (2026-09-11) — its own config, its own faction
    -- keys (so countLivingByFaction never mixes the two arenas' headcounts),
    -- its own thread.
    if arenaEnabled(ARENA2) then
        arena2Thread = task.spawn(function()
            runArenaBattle(ARENA2, "ARENA2_RED", "ARENA2_BLUE")
        end)
    end

    Logger.debug("[AIService] started — spawns:", #spawnParts, "patrol points:", #patrolPoints)
end

-- Public wrapper (asserts live in spawnSquad). `factionKey` (AI arena,
-- 2026-09-11) is optional — omit it for the normal single-faction grunts every
-- existing caller spawns; pass a Constants.AI_FACTIONS key (e.g. "ARENA_RED")
-- to spawn a squad that only targets/is targeted by a DIFFERENT faction.
function AIService.SpawnSquad(spawnCFrame: CFrame?, squadSize: number?, factionKey: string?): { Model }
    return spawnSquad(spawnCFrame, squadSize, factionKey)
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

-- Instantly routes every LIVE grunt through the real death path: sets
-- Humanoid.Health = 0, which fires the same Humanoid.Died connection every grunt
-- already has, running the normal onNPCDied flow (ragdoll, the DEATH_CLEANUP_DELAY
-- corpse timer, attack-slot release, formation reassignment) — the same as if a
-- player had shot them. Unlike RespawnAllSquads this does NOT spawn replacements;
-- the AI zone just goes quiet until the next Respawn Bots press or server restart.
-- Grunts already dying (pendingCleanup) are left alone. Non-yielding (no
-- task.wait anywhere in this function), so — unlike RespawnAllSquads — the
-- KillAllBots remote handler calls this directly, no task.spawn needed. Returns
-- the number of grunts killed.
function AIService.KillAllBots(): number
    if not started or not running then
        Logger.warn("[AIService] KillAllBots called before Start() / after Destroy() — ignored")
        return 0
    end
    local killed = 0
    for _, record in pairs(npcs) do
        if not record.dead and record.humanoid.Parent ~= nil then
            record.humanoid.Health = 0
            killed += 1
        end
    end
    if AI.DEBUG then
        Logger.debug("[AIService] KillAllBots: killed", killed, "grunt(s)")
    end
    return killed
end

-- Number of NPCs that are alive and thinking.
function AIService.GetActiveNPCCount(): number
    return activeCount()
end

-- AI arena / factions (2026-09-11): how many LIVING grunts currently belong to
-- `faction` — public read-only convenience (e.g. for Studio/MCP inspection);
-- runArenaBattle uses the same underlying countLivingByFaction directly.
function AIService.CountLivingByFaction(faction: string): number
    return countLivingByFaction(faction)
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
    if arenaThread ~= nil then
        pcall(task.cancel, arenaThread)
        arenaThread = nil
    end
    if arena2Thread ~= nil then
        pcall(task.cancel, arena2Thread)
        arena2Thread = nil
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
