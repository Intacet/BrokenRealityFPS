# Changelog

## AI arena — separate AI-vs-AI test map with two colored factions

- **New self-contained arena** for watching AI squads fight each other, not
  just the player: perimeter walls, a scattered layout of cover blocks, and a
  small stepped structure, built at `Workspace/BrokenReality_AIArena` (its own
  sky-island location, well clear of the main game map and the existing dev
  test area). Auto-spawns a **Red Squad** and a **Blue Squad** on server start
  in Studio, and automatically restarts the battle a few seconds after either
  side is wiped — a hands-off, continuously-repeating test.
- **AI can now fight AI.** Squads only ever target/damage each other when they
  belong to different factions — every existing single-squad spawn (the main
  game's AI zone, Respawn Bots, Kill All Bots) stays on one shared default
  faction and is completely unaffected; grunts of the same faction still never
  target each other, exactly like today.
- **Each faction has its own color** as a visual designation — Red Squad and
  Blue Squad grunts are recolored at spawn; a player who walks into the arena
  is treated as hostile by both sides too (AI already targets players
  unconditionally, unchanged).
- No DamageService changes were needed — an AI grunt shooting another AI grunt
  routes through the exact same damage path a player's bullet already uses to
  hurt a tagged grunt.
- New `Constants.AI_FACTIONS` + `Constants.AI_ARENA` tables, new
  `AIArenaBuilder.server.lua` (geometry only — no AI spawning, no combat logic
  of its own), and `AIService.server.lua` additions: a widened target type so
  a grunt can target either a Player or an enemy-faction grunt, per-faction
  rig colors, and the arena's own auto-spawn/self-healing battle loop (fully
  inside AIService — the two new/changed files never call into each other
  directly, they just share the same `Constants.AI_ARENA` layout).
- No new remotes, no client files, `GunService`/`DamageService`/`TeamService`
  untouched. One new `default.project.json` entry for `AIArenaBuilder`. `rojo
  build` clean; MCP-checked the faction no-op guarantee, target-type
  branching, arena geometry (walls fully enclose the spawn points and cover
  scatter), and the wipe-detection/retry logic in isolation; not yet
  runtime-verified in Play — see docs/TECHNICAL_DEBT.md "AI arena / factions"
  for every scoping note and known limitation (this is the largest AI
  targeting-core change this session).

## AI dynamic big-map navigation (AIPatrolPoints now optional)

- **AI no longer needs hand-placed patrol points.** Workspace/AIPatrolPoints is
  now optional — if it exists, squads still patrol it exactly as before; if it's
  missing or empty, squads dynamically roam near their spawn instead (a random
  reachable ground point sampled 35–100 studs out, walked to, a short cooldown,
  then a new one), so a squad works on a large hand-built map without a designer
  placing points everywhere.
- **Squads path around obstacles when roaming, searching, or investigating.** A
  new PathfindingService-backed helper computes a waypoint route and follows it,
  with a stuck check that forces a repath (or a fresh goal entirely) if a bot
  makes no real progress for a couple seconds, and a plain straight-line
  fallback if pathfinding is disabled or fails. Applied to dynamic roaming and
  both "investigate a last-known position" behaviors (a bot's own stale memory,
  and a squad-shared last-known-position from AI squad awareness).
- **Combat movement is untouched.** Chasing a target you can currently see,
  fighting/planting, retreating to cover, and bound-and-cover advancing all keep
  their existing direct movement exactly as before — pathfinding is deliberately
  scoped to roam/search/investigate only, so already-tuned close-combat feel and
  responsiveness aren't affected.
- New `Constants.AI_NAVIGATION` table + `AIService` helpers
  `sampleReachableGroundNear` / `computePath` / `followNavGoal` / `dynamicRoam`.
  Foundation-only, not a navmesh editor, not designer-authored AI zones, no
  doors/ladders/vaulting/climbing, no strategic map-level planner — see
  docs/TECHNICAL_DEBT.md "AI dynamic navigation" for every scoping note and
  known limitation.
- `AIService.server.lua` + `Constants.lua` only — no new remotes, no client
  files, `GunService`/`DamageService` untouched, existing spawning / spacing /
  fire discipline / awareness / bounding / combat FX / damage / death cleanup
  all preserved. `rojo build` clean; MCP-checked the ground-sampling radius math,
  slope rejection, stuck-detection timing, waypoint-advance logic, and a real
  `PathfindingService:CreatePath`/`ComputeAsync` call with these agent
  parameters in a live Server datamodel; not runtime-verified in Play (Studio
  was mid-Play-session during this check, so the Edit datamodel wasn't
  available for the usual pre-Play static pass either — flagged, not skipped).

## AI squad bound-and-cover movement

- **Squads advance more naturally.** When a squad is alert with a known
  player position but still far away, one living member is picked as the
  **Mover** and advances toward the player while everyone else holds as
  **Cover** — instead of the whole squad sprinting straight at the player
  together. Once the Mover arrives (or a timeout passes), a different member
  becomes the next Mover, so squads leapfrog forward rather than bunching.
- **Fire discipline still applies, plus new restrictions.** A Mover does not
  shoot while advancing (`MOVER_SHOULD_NOT_SHOOT`); Cover bots only fire with
  their own line of sight and only if a fire-discipline attack slot is free
  (`COVER_BOT_CAN_SHOOT` can force them to hold fire entirely). Never a
  wallhack — bounding only ever changes movement/shoot-suppression, the
  existing "must have own LOS to shoot" rule is untouched.
- **Fair, not unbeatable.** Only a limited number of bots shoot at once
  (existing fire discipline), the advancing Mover is exposed while moving,
  and roles clear immediately on death/target loss/squad wipe — no stuck
  mover, no permanent advantage.
- New `Constants.AI_BOUNDING` table + `AIService` helpers `releaseBoundRole` /
  `clearSquadBounding` / `boundDestinationFor` / `updateSquadBounding`. A
  simplified, game-friendly pass — not a real cover-node/fire-and-maneuver
  system — layered on top of the existing squad spacing, fire discipline, and
  awareness systems rather than duplicating any of them; see
  docs/TECHNICAL_DEBT.md "AI squad bound-and-cover movement" for every
  scoping note and known limitation.
- `AIService.server.lua` + `Constants.lua` only — no new remotes, no client
  files, `GunService`/`DamageService` untouched, existing spawning / patrol /
  chase / attack / cover / awareness / combat FX / damage / death cleanup all
  preserved. `rojo build` clean; MCP-checked the bound-destination math,
  mover selection, and arrival/timeout swap logic in isolation; not
  runtime-verified in Play.

## AI squad awareness and last-known-position memory

- **Squads react together.** When one grunt spots (or is hit by) the player,
  its whole squad goes on a time-bounded alert (not stuck alert forever), and
  living squadmates within `ALERT_SHARE_RADIUS` learn roughly where the
  player was and start investigating — even if they never personally saw
  anything.
- **Never a wallhack.** Shared awareness only ever changes where a grunt
  walks. A grunt can only actually shoot with its own line of sight — that
  was already true structurally and stays true regardless of any new flag.
- **Investigate, don't beeline.** An alerted grunt with no target of its own
  picks a random nearby offset near the shared position — not the exact
  spot — and moves there using the existing anti-bunching/spacing logic, so
  a squad converging on a last-known position doesn't stack on one point.
  Once the shared position goes stale (`LAST_KNOWN_POSITION_MEMORY`) the
  investigate goal clears.
- **Alerts actually expire.** With no sighting or hit from any squad member
  for `CLEAR_ALERT_AFTER_NO_CONTACT` seconds, the whole squad's alert clears
  and everyone returns to Patrol/Idle — no permanent aggro.
- New `Constants.AI_SQUAD_AWARENESS` table. Consolidates in place, rather
  than duplicates, the earlier sticky `squad.alerted` reaction-tier flag
  (now a proper expiring deadline) and reuses two `NPCRecord` fields that
  already existed from an earlier pass — see docs/TECHNICAL_DEBT.md "AI
  squad awareness" for that and every other scoping note.
- `AIService` + `Constants.AI_SQUAD_AWARENESS` only — no new remotes, no
  client files, `GunService`/`DamageService` untouched, existing spawning /
  spacing / fire discipline / combat all preserved. MCP-checked the sharing,
  throttling, alert-clearing, and investigate-goal logic in isolation; not
  runtime-verified in Play.

## Kill All Bots button

- New **KILL ALL BOTS** button in the loadout (`M`) menu, next to Respawn Bots.
  Fires a new `KillAllBots` RemoteEvent; `AIService.KillAllBots()` sets every
  live grunt's `Humanoid.Health = 0`, routing it through the exact same death
  path a player's bullet would (ragdoll, blood, the normal corpse-cleanup
  timer, attack-slot release, squad formation reassignment) — unlike Respawn
  Bots, it does not spawn replacements; the AI zone stays empty until the next
  Respawn Bots press. Available to every player, Studio and published alike,
  gated by its own shared server-wide cooldown
  (`Constants.AI.KILL_ALL_COOLDOWN_SECONDS`), same not-per-player pattern as
  Respawn Bots.
- `AIService.server.lua` + `RemoteSetup.server.lua` + `LoadoutMenu.lua` +
  `Constants.lua` only. No other file touched. `rojo build` clean; the
  underlying kill mechanism (`Humanoid.Health = 0` → `Died` → `onNPCDied`) is
  the same one every AI death this session already goes through, not a new
  code path — not independently re-verified in Play.

## AI squad fire discipline

- **Only 1-2 bots fire at once per squad** (`MAX_ACTIVE_SHOOTERS_PER_SQUAD`) —
  a 3-4 grunt squad now pressures the player instead of everyone opening up
  simultaneously. Consolidates and hardens the per-squad attack-slot
  mechanism from the earlier "fair combat tuning" pass rather than running a
  second copy of it: slot eligibility now requires a live target, attack
  range, **and line of sight** (no wallhack shooting — a squadmate seeing the
  player doesn't let a blind grunt fire), and a slot force-releases after
  `ATTACK_SLOT_TIMEOUT` even if the holder is still eligible, so one grunt
  can't hog it forever.
- **Slots release immediately**, not on the next recheck, the instant a grunt
  dies, loses its target, or leaves the `Attack` state for any reason
  (retreats to Cover, target goes out of range/LOS, ...).
- **Non-shooters don't just stand there.** A grunt without a slot still
  tracks the player (faces it) and, every couple of seconds, picks a new
  support position — either holding back to watch an angle or moving up
  closer to support — instead of freezing in place or piling onto the active
  shooters' target.
- New `Constants.AI_FIRE_DISCIPLINE` table. `AIService` + that table only —
  no new remotes, no client files, `GunService`/`DamageService` untouched,
  existing damage integration and active-shooter burst timing unchanged.
  MCP-checked the slot assignment/drop/timeout logic and the support-distance
  selection (catching and fixing a real initialization bug along the way);
  not runtime-verified in Play (see docs/TECHNICAL_DEBT.md "AI squad fire
  discipline").

## AI squad spacing and anti-bunching

- **Formation slots.** Each squad now assigns a formation slot to every living
  member — 1 for the leader/anchor (original spawn leader, or the first
  survivor if it dies), 2+ cycling through flanking/rear directions
  (`Constants.AI_SQUAD_SPACING.SLOT_OFFSETS`). Reassigned at most every
  `FORMATION_SLOT_REASSIGN_INTERVAL`, and immediately on a member's death —
  never every think.
- **Squadmates no longer all run to the identical point.** Patrol/Idle, Chase,
  and a fresh Search now fan squadmates out from the shared target (patrol
  point, player position, last-known position) by formation-slot direction ×
  a context spread radius (`CHASE_SPREAD_RADIUS` / `IDLE_SPREAD_RADIUS`) plus
  a little jitter so goals never perfectly overlap.
- **Separation avoidance.** New `getSeparationAdjustedGoal` nudges any goal
  away from a squadmate closer than `MIN_PERSONAL_SPACE` — pure vector math,
  no physics forces, never touches `HumanoidRootPart` directly. Applied on
  top of every travel goal, including the ones that are already individually
  computed (Attack fighting spots, Cover hide points, flank points), so those
  only get a small safety-net push, not the full spread treatment (keeps them
  from being pulled off a validated cover/LOS spot).
- **Combat fallback.** When `Attack` finds no literal cover
  (`findFightingPosition` returns nil), grunts now fan out around the target
  at `COMBAT_SPREAD_RADIUS` instead of planting wherever attack range was
  reached — a common cause of squads bunching in the open.
- **MoveTo throttling.** A new shared `issueSquadMoveGoal` only recomputes and
  reissues a travel goal when `MOVE_GOAL_RECALCULATE_INTERVAL` has passed or
  the underlying raw target has moved past `MOVE_GOAL_JITTER` studs — not
  every think. Stationary "hold position" `MoveTo(root.Position)` calls
  (planted/firing, mid-burst) are untouched and stay direct, so a grunt still
  stops moving the instant it plants.
- Falls back to the pre-existing static per-grunt ring offset when
  `Constants.AI_SQUAD_SPACING.ENABLED` is false or a squad record can't be
  found, cleanly reverting to prior behavior.
- `AIService` + `Constants.AI_SQUAD_SPACING` only — no new remotes, no client
  files, `GunService`/`DamageService` untouched. Spawning, chase/attack,
  combat FX, damage integration, and death cleanup all preserved. MCP-checked
  the formation math in isolation; not runtime-verified in Play (see
  docs/TECHNICAL_DEBT.md "AI squad spacing / anti-bunching").

## Fix: stuck cursor + instant mid-round weapon switch from the loadout menu

- **Cursor stuck visible after spawning in.** `LoadoutMenu`'s cursor-restore
  used to run once, at the moment the menu closed, checking whatever
  `CameraMode` happened to be at that instant — a race against
  `ViewModelController` flipping `CameraMode` to `LockFirstPerson` on respawn
  (two independently-timed events). New `syncCursorToCameraMode()` is now also
  driven by a live `CameraMode` change signal, so whichever event lands second
  still gets the cursor into the right state.
- **Selecting a weapon in the loadout menu now switches you immediately** if
  you're already spawned in with a weapon out, instead of only taking effect
  at the next round's PREP. `GunController` holsters and re-equips through its
  own existing branches the instant `BR_LoadoutPrimary` changes during ACTIVE;
  `GunService` re-runs `setupAmmo` on the same change so the new weapon gets
  its own full mag/reserve instead of inheriting a leftover count from the old
  one. A holstered player is untouched — their next manual equip already reads
  the new selection.
- `LoadoutMenu.lua` is this session's own file (committed normally). The
  `GunController.lua` / `GunService.server.lua` additions are small, additive
  listeners only — but both files are being actively rewritten by a parallel
  shotgun-support session, so they're left **uncommitted** to avoid losing or
  conflicting with that work; either could be overwritten by its next save.
  Not runtime-verified in Play.

## Fix: grunts fire back while retreating to cover instead of jogging there silently

- **Covering fire.** The `Cover` state's not-yet-arrived path is now a
  bounding-overwatch loop: walk toward the hide spot, periodically stop, face
  the player, and fire a burst back, then resume walking once the burst ends
  — instead of silently jogging to cover with your back turned. Cadence is
  `Constants.AI.COVER_RETREAT_SHOT_MIN/MAX` (randomized), gated by
  `COVER_RETREAT_FIRE`. Once actually arrived at the hide spot it still goes
  fully quiet for the rest of the window, same as before.
- `startBurst`'s internal loop now allows firing while `state == "Cover"` as
  well as `"Attack"` (it previously self-aborted immediately if called from
  any state but `Attack`).
- Deliberately never combines a `faceToward` root-CFrame write with an active
  `Humanoid:MoveTo` in the same think — reuses the exact "stop completely, then
  face + fire" pattern `Attack` already uses, rather than trying to have the
  grunt face the player while still walking (that combination is what froze
  grunts in place in the original Stage 1D bug).
- `AIService` + `Constants.AI` only. Not squad-attack-slot-limited (a retreat
  burst doesn't consume/respect `MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD`) — see
  docs/TECHNICAL_DEBT.md "AI Stage 1F". MCP-checked the branch logic and burst
  guard; not runtime-verified in Play.

## Fix: grunts crouch only on arrival at cover, and now fire from the crouch

- **No more instant-crouch-and-waddle.** `Cover` and the `Attack` planted branch
  now only switch to the crouch pose once the grunt has actually *arrived* at its
  cover / fighting spot (`(root.Position - spot).Magnitude <= FIGHT_ARRIVE_DIST`)
  — it stands (runs normally) on the way there. Previously it crouched the
  instant it decided to retreat, mid-sprint across open ground, which read as
  "gets shot, instantly crouches, waddles to cover."
- **Grunts now fire while crouched.** `Attack` no longer forces standing to
  shoot — once planted at real cover (a spot `findFightingPosition` actually
  found), it crouches *and* fires from the crouch; nothing in the fire path was
  ever gated on pose, so this only needed the crouch-suppression removed. With
  no cover nearby it still stands in the open, same as before.
- `AIService` only, reusing the existing `FIGHT_ARRIVE_DIST` constant for both
  the Cover and Attack arrival checks. Not runtime-verified — see
  docs/TECHNICAL_DEBT.md "AI Stage 1F".

## AI Stage 1C — fair combat tuning (reaction tiers, aim ramp, suppression, target memory, squad attack slots)

- **Tiered reaction delay.** Replaces the flat Stage 1H reaction beat with three
  tiers keyed off squad/NPC state: `RecentlyDamaged` (fastest — already under
  fire) > `Alert` (this squad has made contact before — sticky, squad-wide) >
  `Unaware` (first contact, slowest). Armed only when a grunt's live target
  actually changes; movement/facing continue during the delay, only the first
  shot is held back.
- **Aim ramp.** A freshly-acquired target gets a wide `INITIAL_SPREAD_MULTIPLIER`
  cone; it eases toward a tighter `FINAL_SPREAD_MULTIPLIER` as the target stays
  continuously visible, up to `AIM_SETTLE_TIME` — miss shots at first, dangerous
  if you stay exposed. Frozen (not reset) on a brief LOS break; resets only past
  `LAST_KNOWN_POSITION_MEMORY`. Multiplies with, doesn't replace, the existing
  per-grunt aim-skill and moving-target spread factors.
- **Suppression.** Any accepted hit on a grunt now also arms a temporary
  `SUPPRESSED_SPREAD_MULTIPLIER` penalty and marks it "recently damaged" (feeds
  the fast reaction tier above) — damaged bots shoot back worse, not not at all.
- **Target switch cooldown** stops a grunt from flickering between two nearby
  players; **per-squad attacker limit** caps how many squadmates fire at once
  (`MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD`, sticky slot allocation, rechecked on
  `ATTACK_SLOT_RECHECK_INTERVAL`) — the rest stay planted and aimed but hold
  fire, so a 3-grunt squad doesn't all laser the player simultaneously.
- **Damage-call-rate safety net** (`MIN_TIME_BETWEEN_DAMAGE_CALLS`), independent
  of burst timing; `DamageService` itself is untouched.
- New `Constants.AI_COMBAT_TUNING` table. Consolidates with (removes) the
  overlapping Stage 1H flat reaction-delay mechanism rather than running two
  competing gates for the same decision — see docs/TECHNICAL_DEBT.md "AI Stage
  1C" for that call and every other judgment call made interpreting this task.
  `AIService` + `Constants.AI_COMBAT_TUNING` only — no new remotes, no client
  files, `GunService` / `DamageService` untouched. MCP-checked the tier logic,
  ramp formula, sticky slot allocation, and target-memory math; not
  runtime-verified in Play.

## AI Stage 1H — combat realism pass + a Respawn Bots button

- **Reaction time.** A grunt no longer fires the instant it spots you: acquiring
  a NEW live target (a fresh sighting, or a new attacker from a from-behind hit)
  arms a random 0.15–0.45s beat (`Constants.AI.REACTION_TIME_MIN/MAX`) before its
  first shot — it still tracks/faces you during that beat. Re-confirming the same
  target on every recheck, or re-peeking from `Cover` mid-firefight, does not
  re-arm it, so an ongoing engagement never stutters.
- **Per-grunt aim skill + moving-target penalty.** Each grunt rolls a spread
  multiplier once at spawn (`AIM_SKILL_VARIANCE`, clamped) so not every rifle
  shoots identically, plus extra spread scaled by the target's live velocity
  (`AIM_MOVING_TARGET_*`) — a sprinting/strafing player is harder to hit than
  someone standing still.
- **Wounded grunts hunker down longer.** `coverDurationFor()` multiplies
  `COVER_DURATION` by `LOW_HEALTH_COVER_MULTIPLIER` once a grunt's health drops
  to `LOW_HEALTH_RATIO`, used by both the post-burst cover-arm and the
  hurt-reaction listener.
- **RESPAWN BOTS button**, in `LoadoutMenu`, available to every player in Studio
  and on a published server alike. Fires a new `RespawnBots` RemoteEvent; the
  server's `AIService.RespawnAllSquads()` instantly clears every live grunt (no
  ragdoll — a reset, not a kill) and spawns fresh squads at `Workspace/AISpawns`.
  One shared server-wide cooldown (`Constants.AI.RESPAWN_COOLDOWN_SECONDS`, not
  per-player) so it can't be spammed to grief other players' fights; the button's
  own countdown is a cosmetic mirror of that, not the real gate.
- Deliberately out of scope: reload (rejected earlier in Stage 1C), grenades,
  squad tactics, pathfinding, morale/retreat. `AIService` + `Constants.AI` +
  `LoadoutMenu` + `RemoteSetup` only. MCP-checked the math + `AssemblyLinearVelocity`;
  not runtime-verified (see docs/TECHNICAL_DEBT.md "AI Stage 1H").

## Fix: AI never spawned on a published server

- **Root cause:** `AIService`'s opening-squad spawn was gated
  `RunService:IsStudio() and Constants.AI.SPAWN_ON_SERVER_START_IN_STUDIO` — there
  was no published-server equivalent, so a live/published game never spawned a
  single grunt even though `TestAreaBuilder` (already fixed for
  `DEV_TEST_AREA.RUN_IN_PUBLISHED`) was correctly building the
  `Workspace/AISpawns` / `AIPatrolPoints` parts for it to use. Studio Play always
  worked, masking this.
- New `Constants.AI.SPAWN_ON_SERVER_START_IN_PUBLISHED` (default `true`, same
  pattern as `DEV_TEST_AREA.RUN_IN_PUBLISHED`). `studioAutoSpawn` renamed
  `autoSpawnSquads`, gated by a new `autoSpawnEnabled()` that picks the Studio or
  published flag. `didStudioAutoSpawn` renamed `didAutoSpawn`.
- `Constants.AI` + `AIService` only — no new remotes, no other file touched.
  `rojo build` clean.

## AI grunts ragdoll + bleed on death like the test dummies

- **Death ragdoll.** On `Humanoid.Died` a grunt is handed to the same
  `RagdollService:Apply` the test dummies use, with a knockback impulse built from
  its last accepted hit (`Constants.RAGDOLL_WEAPON_IMPULSE` by weapon name, else
  `RAGDOLL_IMPULSE_DEFAULT`) — the exact path as `DummyService.onDummyDied`. The
  body flops with the shot instead of freezing upright and vanishing; the corpse
  is still cleared after `Constants.AI.DEATH_CLEANUP_DELAY`.
- The welded AKS-74 is removed first (its parts are held together by `Motor6D`s
  that `RagdollService` would otherwise convert to loose ball sockets), grip joint
  included. Gated by `Constants.AI.RAGDOLL_ON_DEATH`.
- **Blood** already worked — `BloodService` reacts to the same
  `CombatEvents.DamageDealt` for any target, so shooting a grunt bleeds exactly
  like shooting a dummy. No change needed.
- `AIService` + `Constants.AI` only — new `require` of the existing
  `RagdollService`, no new remotes, no `RagdollService` / `DummyService` /
  `DamageService` / `BloodService` edit. Verified the teardown + ragdoll in a live
  Server datamodel (15 joints → 6 body joints convert, gun gone); the in-game
  feel needs a Studio Play test.

## Cover on the far side of the player + first-person weapon retraction

- **Grunts hide where the player can't see them.** `findCoverPoint` now sweeps a
  fuller ring of angles and, among spots whose line of sight to the player is
  blocked, picks the one whose blocking obstacle is *nearest* (within
  `Constants.AI.COVER_HUG_DISTANCE`) — so the grunt tucks against the far face of
  that obstacle instead of standing behind a distant wall still half-exposed. The
  `Cover` state also re-picks its spot if the player flanks around the cover and
  regains line of sight while the grunt is parked there.
- **Player weapon retraction (Tarkov close-quarters).** `ViewModelController` casts
  one forward ray from just behind the camera each frame; when it hits a wall
  within `Constants.VIEWMODEL_WALL_PROBE_DISTANCE` the whole viewmodel is pulled
  back toward the player and the muzzle tucks up (`VIEWMODEL_WALL_PUSH_MAX` /
  `VIEWMODEL_WALL_TUCK_MAX_DEG`), framerate-independently lerped and scaled down
  while ADS. Appended last in the existing PivotTo chain next to the positional
  recoil term. Purely cosmetic — `GunController` still fires from the camera /
  free-aim solve, so shooting point-blank into a wall is unchanged.
- `AIService` + `Constants.AI` (cover) and `ViewModelController` + `Constants`
  (retraction) only — no new remotes, no server/damage/camera-writer change. MCP
  checked the APIs; both need a Studio Play test (see docs/TECHNICAL_DEBT.md).

## AI Stage 1F — grunts crouch behind cover, guns retract off walls

- **Crouch in cover.** In the `Cover` state a grunt now crossfades to the player's
  own `CrouchIdle` clip (`Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed.CrouchIdle`,
  no `HipHeight` change — pure animation) instead of standing upright. It stands
  again the instant it re-peeks to `Attack` so the aimed-rifle look reads, then
  crouches on the next between-burst duck. Flag-gated `CROUCH_IN_COVER`.
- **Guns stop poking through walls.** A new `updateWeaponCollision` runs every
  think for every live grunt: a forward chest-ray of `GUN_COLLISION_DISTANCE`
  studs, and when it hits map geometry the welded rifle's grip `Motor6D` (C1) and
  the `Right Shoulder` `Motor6D` (C0) are additively pulled back toward the body —
  Tarkov-style — up to `GUN_RETRACT_MAX` studs with a `GUN_RETRACT_TUCK_DEG` muzzle
  tuck, lerped by `GUN_RETRACT_ALPHA`. Composes on top of the animation and
  restores cleanly when the grunt backs off. Flag-gated `GUN_COLLISION_ENABLED`.
- **Stand off the wall.** `findCoverPoint` / `findFightingPosition` results are run
  through a new `pullFromWalls` that shoves the spot `WALL_STANDOFF` studs clear of
  any wall it's flush against, so grunts fight from a step back rather than face-first.
- Per-grunt heuristics only: the crouch clip is a no-gun full-body pose so the
  welded rifle rides low while crouched; the retraction is one forward ray so a
  wall to the side still clips; `pullFromWalls` has no pathfinding. See
  docs/TECHNICAL_DEBT.md "AI Stage 1F".
- **`AIService` + `Constants.AI` only** — no new remotes, no client files, no
  `default.project.json` / `GunService` / `DamageService` / `WorldWeaponService`
  change. The player's own first-person Tarkov weapon collision
  (`ViewModelController`) is a separate follow-up client task. MCP-checked the APIs;
  the behaviour needs a Studio Play test.

## AI Stage 1E — grunts fight from cover, react to fire, flank a lost target

- **Don't stand in the open.** The `Attack` state now walks to `findFightingPosition`
  first — a spot within `FIGHT_SEEK_DISTANCE` that still has line of sight to the
  target *and* has an obstacle within `COVER_ADJACENT_RADIUS` — then plants there
  to fire. No cover nearby → holds where it stopped (pre-1E behaviour).
- **React to being shot.** A service-level `CombatEvents.DamageDealt` listener (a
  `require`d BindableEvent — no new remote) arms the cover window the instant a
  grunt takes any hit, and if a player did it, makes that player the target and
  updates the last-seen position. A grunt shot in the back while patrolling now
  turns, ducks to cover, and engages the shooter.
- **Flank a stale last-known position.** `lastSeenPos` is kept after the live
  target reference is dropped. Once it's older than `LAST_SEEN_CHASE_SECONDS`
  (up to `SEARCH_DURATION`), the grunt enters a new `Search` state and moves in
  via `flankPointFor` — an arc that's wide when far from the spot and converges on
  it, with squad members alternating `flankSide` for a rough pincer — instead of
  immediately giving up and patrolling.
- Per-grunt heuristics only: no squad coordination, no tagged cover nodes, no
  pathfinding (a grunt can get stuck against a wall it's trying to fight from /
  reach). All flag-gated (`FIGHT_FROM_COVER`, `HURT_COVER`).
- **`AIService` + `Constants.AI` only** — no new remotes, no client files, no
  `default.project.json` / `GunService` / `DamageService` / `CombatEvents` change.
  AI detection / damage / death is preserved. MCP-checked the math + APIs; the
  behaviour needs a Studio Play test (see docs/TECHNICAL_DEBT.md "AI Stage 1E").

## AI Stage 1D — grunts face the player + take cover between bursts

- **Face the target while shooting.** In the stationary `Attack` state
  `Humanoid.AutoRotate` is turned off and a new `faceToward` helper lerps the
  `HumanoidRootPart` to point the rifle at the player, so a grunt that walked in
  sideways turns to face you before/while firing. Walking states (Chase / Cover /
  Patrol) keep `AutoRotate` on and face their travel direction — writing the root
  CFrame every think while also walking would freeze the grunt in place.
  `Constants.AI.FACE_TARGET` / `FACE_TURN_ALPHA`.
- **Take cover after each burst.** New `Cover` state: when a burst finishes,
  `startBurst` arms `record.coverUntil`; while it's in the future `thinkNPC` moves
  the grunt to `findCoverPoint` (samples `COVER_SAMPLE_ANGLES` off the
  away-from-target vector at `COVER_SEEK_DISTANCE`, keeps the first spot a raycast
  finds LOS-occluded, else a plain retreat) and holds there for `COVER_DURATION`
  before peeking out and firing again — a per-grunt peek/shoot/hide loop. Breaking
  LOS or leaving range drops the loop to `Chase`.
- Per-grunt only — no squad coordination, no tagged cover nodes, no pathfinding
  (so a grunt can walk into a wall it's trying to hide behind; on open ground it
  just backs off `COVER_SEEK_DISTANCE` studs). All flag-gated (`TAKE_COVER`).
- **`AIService` + `Constants.AI` only** — no new remotes, no client files, no
  `default.project.json` / `GunService` / `DamageService` change. AI detection /
  chase / attack / damage / death is preserved. MCP-checked the math + APIs; the
  peek/shoot/hide loop needs a Studio Play test (see docs/TECHNICAL_DEBT.md
  "AI Stage 1D").

## AI Stage 1C — grunts get the player's gun + third-person animations

- Each AI grunt now holds the **real AKS-74 world model** — `AIService` clones
  `ReplicatedStorage/WorldModels/AKS-74` and welds `Handle` → `Right Arm` with a
  `Motor6D`, the exact attach body `WorldWeaponService` uses for players (same
  `Constants.WORLD_WEAPON_*` / grip CFrames; the ~30 lines are duplicated because
  that service takes a `Player` and can't be `require`d).
- Grunts gained an `Animator` and load the player's **third-person weapon poses**
  (`WeaponData` `thirdPerson` equip / idle / fire — reload skipped, infinite ammo)
  plus **default R6 idle / walk** clips. The weapon idle pose is what positions the
  gun in-hand (grip C0/C1 are identity); `Humanoid.Running` swaps idle↔walk by
  speed so grunts walk instead of sliding; `fireOneShot` plays the fire kick per
  shot. Muzzle FX now originate at the gun's **`Barrel`**.
- Every step is `pcall`'d and warns once on failure — a missing world model or a
  failed `LoadAnimation` just means the grunt fires without the gun / in the raw
  pose. New `Constants.AI` Stage 1C fields (`WEAPON_NAME`, `USE_*` flags,
  `LOCOMOTION_*_ANIM_ID`, fades).
- **No new remotes, no client files, no `default.project.json` change**;
  `WorldWeaponService` / `WeaponData` / `GunService` / `DamageService` unchanged.
  AI detection / chase / attack / damage / death is preserved. MCP-verified the
  engine APIs + asset; full behaviour needs a Studio Play test (see
  docs/TECHNICAL_DEBT.md "AI Stage 1C").

## AI Stage 1B — combat feedback FX for grunts

- New `Constants.AI_COMBAT_FX` + `AIService` helpers `setupAICombatFx` /
  `playAIShotFx` / `playAITracer`. When an AI grunt fires, `fireOneShot` now plays
  **server-created, world-replicated placeholder FX** so players can see and hear
  it: a small **muzzle flash + smoke puff + light pulse** off an auto-created
  `AIMuzzleAttachment` (on the grunt's Right Arm, or HumanoidRootPart if absent —
  placeholder until AI weapon models exist), an optional brief **tracer Beam**, and
  a **3D gunshot Sound**. FX play on every shot, hit or miss.
- Emitters / light / sound are built **once per NPC** and reused — not per shot.
  Only the tracer makes a temporary holder Part per shot, `Debris`-cleaned and
  parented under `Workspace/AI` (also swept by `Destroy()`). FX refs are cleared on
  NPC death; the light pulse's `task.delay` is token-guarded and Parent-checked so
  it never errors after death / service destroy.
- Placeholder asset IDs (`FLASH_TEXTURE` / `SMOKE_TEXTURE` / `GUNSHOT_SOUND_ID` =
  `rbxassetid://0`) are tolerated — `AIService` `Logger.warn`s once; the flash/smoke
  show as default particles and the sound is skipped (no "failed to load" spam).
- **No new remotes, no client files, no `GunService` / `DamageService` change.** AI
  detection / chase / attack / damage / death is preserved exactly. Existing
  Stage 1A behaviour unchanged. Not runtime-verified — Studio Play test required
  (see docs/TECHNICAL_DEBT.md "AI Stage 1B").

## AI patrol zone in the test area

- `TestAreaBuilder` now builds an "AI Patrol Zone" — a marked pad in a clear corner of
  the test area (`Constants.DEV_TEST_AREA.AI_ZONE_*`) plus the top-level
  `Workspace/AISpawns` (2 anchored parts) and `Workspace/AIPatrolPoints` (4 anchored
  parts in a loop) that `AIService` reads. So on Play you now see grunt squads spawn and
  walk the patrol loop with zero manual setup. New `DEV_TEST_AREA.SPAWN_AI_ZONE` flag
  (default true); the two folders carry `BR_TestAreaOwned` so a rebuild only ever
  destroys folders it made — a hand-authored `AISpawns`/`AIPatrolPoints` is detected and
  left untouched. `SPAWN_AI_ZONE = false` + one more run removes the owned folders.
- `AIService` now connects `workspace.ChildAdded` (its one persistent connection,
  disconnected in `Destroy()`) and re-scans if `AISpawns`/`AIPatrolPoints` appear after
  it started — so it no longer matters whether `AIService` or `TestAreaBuilder` runs
  first, and folders/parts added by hand mid-session are picked up.

## AI Stage 1A — basic server-owned squad NPC foundation

- New `src/ServerScriptService/Services/AIService.server.lua` (self-running Script,
  mapped in `default.project.json`) + new `Constants.AI` tuning table. Simple R6
  rifleman "grunt" squads: spawn from `Workspace/AISpawns`, patrol
  `Workspace/AIPatrolPoints` (missing folders → one `Logger.warn`, service still
  starts), parent live models under `Workspace/AI`, detect players by server raycast
  line-of-sight, chase, and burst-fire simple server raycasts. States: Idle / Patrol
  / Chase / Attack / Dead. Dead grunts stop thinking and are destroyed after
  `DEATH_CLEANUP_DELAY`. Active count hard-capped at `MAX_ACTIVE_NPCS`.
- **No new remotes. No client AI scripts. No client damage decisions.** All AI
  decisions are server-side.
- Damage integration uses existing paths only — **no `GunService` / `DamageService`
  edit**: player→AI via the `Constants.TAG_DAMAGE_ENTITY` tag + `GunService`'s
  existing entity-hit path; AI→player via the public `DamageService:ApplyDamage`
  (flat `Constants.AI.SHOT_DAMAGE`, `attacker = nil`).
- **No killstreaks / points / rewards / airstrikes, no AI types, no monster AI, no
  pathfinding (plain `MoveTo`), no ragdoll on AI death, no AI animations or weapon
  models, no cover / flanking / suppression.** Foundation only.
- Not runtime-verified (MCP can't place `AISpawns` parts or drive a player) — Studio
  Play test required; see docs/TECHNICAL_DEBT.md "AI Stage 1A".

## Crosshair toggle for every player

- The crosshair on/off control was only in `DummyDebugUI`, which builds for developers
  only (`RunService:IsStudio()` / `Constants.DEV_USER_IDS`). Added a **CROSSHAIR: ON/OFF**
  button to `LoadoutMenu` (which everyone gets, opened with M), wired to the same
  `CrosshairUI:SetUserEnabled` / `:IsUserEnabled`. The menu re-reads the current state
  each time it opens so the two buttons never disagree. Session-local (not persisted).
  The dev `DummyDebugUI` button is unchanged.

## Test area can run in a published build

- `TestAreaBuilder` was hard-gated to `RunService:IsStudio()`, so a published place
  never built the sandbox and never redirected spawns — you'd spawn in the real map.
  New `Constants.DEV_TEST_AREA.RUN_IN_PUBLISHED` (default **true** for now): the guard
  is now `ENABLED and (IsStudio() or RUN_IN_PUBLISHED)`. Nothing else changed — same
  folder-scoped rebuild, same reversible `REDIRECT_TEAM_SPAWNS` (restores originals
  first on every run). ⚠ Set `RUN_IN_PUBLISHED = false` (or `ENABLED = false`) before a
  real release or the sandbox and the relocated match spawns ship to live players.

## Ragdoll fires instantly (no ~0.5 s stall)

- `RagdollService:Apply` now sets `Humanoid.RequiresNeck = false` before it disables the
  Neck Motor6D. With `RequiresNeck` on (the default), the engine saw the missing neck and
  waited a ~0.5 s grace period before finalising the death — the rig stood upright and
  rigid for that half second, then flopped, and the death impulse was damped during the
  freeze. `Restore()` sets it back to `true`. No tuning change.

## Pre-round loadout menu (primary weapon + team pick)

- **New `LoadoutMenu` client UI** (`Controllers/UI/LoadoutMenu.lua`, ClientInit slot 15).
  A centered deployment panel: a weapon list, a three-way team pick
  (Auto / Attackers / Defenders), and a Deploy button. Opens/closes on **M**, and
  auto-opens on entry to LOBBY / RESULTS (PREP is only `PREP_TIME` = 2 s in dev config).
  Clicking Deploy fires the new `SelectLoadout` remote and closes the panel; selections
  persist across rounds. Only **AKS-74** is selectable — **AR-15** / **SCAR-H** show as
  greyed "LOCKED" rows until they have full `WeaponData`.
- **New `LoadoutService` server script** — the sole writer of two per-player attributes,
  `BR_LoadoutPrimary` (a `WeaponData` key) and `BR_TeamPref`. Validates every field of a
  `SelectLoadout` request against `Constants.LOADOUT`; unknown / locked / malformed
  fields are ignored individually. `LOCK_EDITS_DURING_ACTIVE = false` — a mid-round
  Deploy is accepted and applies at the next PREP.
- **`GunService` reads the loadout.** New `resolvePrimary(player)` helper replaces the
  bare `Constants.DEFAULT_WEAPON` at every stat / ammo / `AmmoChanged` / damage-source
  site (falls back to `Constants.DEFAULT_WEAPON` when the attribute is missing/invalid).
- **`TeamService` honours the team pick.** New `resolveTeamAssignment()` places explicit
  Attackers/Defenders picks first, fills "Auto" players toward an even split, and never
  leaves a side empty when 2+ players are present. A lone player always gets their pick.
- **`GunController` equips the chosen weapon** — the equip path resolves
  `BR_LoadoutPrimary` (fallback `Constants.DEFAULT_VIEWMODEL_WEAPON`) instead of a
  constant; holster now reports the actually-equipped name to `WorldWeaponService`.
- New `Constants.LOADOUT` tuning table. New `SelectLoadout` RemoteEvent in
  `RemoteSetup.server.lua`. Two new mappings in `default.project.json` (**restart
  `rojo serve`**). `WeaponData.lua` / `WeaponFeel.lua` were **not** touched; `MatchService`
  is unchanged. Partially closes DEBT-013. Not in-game verified — MCP can't drive input.

## Tactical sprint balance — short bursts, no juking

- **Burst duration + cooldown.** New `Constants.TACTICAL_SPRINT_MAX_DURATION` (3 s):
  `MovementController`'s Heartbeat force-stops tactical sprint once a burst hits that
  length. New `TACTICAL_SPRINT_COOLDOWN` (4 s): a double-tap can't restart it until that
  long after the previous burst ended (tracked in `movementState.lastTacticalSprintEndTime`,
  set from `stopTacticalSprint()` and the Shift-release path; respawn does not impose it).
- **Commit to forward.** `TACTICAL_SPRINT_MIN_FORWARD_DOT` 0.35 → **0.6**. The existing
  per-frame sustain check now ends the burst if the move input drifts more than ~53° off
  camera-forward — a diagonal veer (W+D) still holds, a hard sideways strafe cancels it.
- `TACTICAL_SPRINT_STOP_MIN_DURATION` 5 → **1.5** so a full 3 s burst can still trigger
  the stop-animation + momentum carry on release (it was previously unreachable).
- No new module-level locals in `MovementController` (register-limit safe) — one
  `movementState` field + closure-scoped locals only. Not in-game tested (Edit mode has
  no input); tune `TACTICAL_SPRINT_MAX_DURATION` / `_COOLDOWN` / `_MIN_FORWARD_DOT`.

## Fix jumping / vaulting over walls that should be too tall

- **Jump height.** Nothing was setting it, so characters used the R6 default
  (`JumpPower 50` ≈ a 6.4-stud jump) — enough to clear the 6-stud "too tall" wall and
  anything shorter. Added `StarterPlayer.$properties` in `default.project.json`:
  `CharacterUseJumpPower = false`, `CharacterJumpHeight = 4.5`. A plain jump now peaks
  ~4.4 studs — clears crates / low ledges, not a 6-stud wall.
- **Vault height was measured from the player's feet**, so a jump, a ledge, or standing
  on another vault bar made a tall wall read as short (a 6-stud wall while stood on the
  4.25 bar classified as a 1.75-stud *LowVault*). `MovementController.detectVault` now
  casts straight **down from just inside the struck face** to find the obstacle's own
  base and measures `obstacleTopY - obstacleBaseY`. A 6-stud wall now reads 6 studs and
  is rejected from every stance; no floor beneath the face → treated as un-vaultably
  tall. Legit Low/Medium vaults are unchanged. Studio-verified (raycast harness):
  LowBar → LowVault, MedBar → MediumVault, TooTall → REJECT from ground, mid-jump, and
  while standing on the MedBar.

## Hold-to-ADS + collapsible dummy overlay + a crosshair toggle

- **Hold to aim.** `Constants.ADS_HOLD_TO_AIM` (default true): MB2 InputBegan engages ADS,
  InputEnded lowers it. `GunController`'s ADS handler is refactored around one
  `requestAiming(active)` helper (the weapon / phase / tac-sprint / first-person guards
  only gate *entering*; release always lowers). Set the constant false for the old
  press-to-toggle behaviour. No server / recoil / spread change — still just drives
  `ViewModelController:SetAiming` + `MovementController.SetAiming`.
- **Dummy debug overlay opens/closes.** The `DUMMY DEBUG` title bar is now a button;
  clicking it collapses the panel to just that bar (`[-]` / `[+]`) and restores it. The
  row list is skipped while collapsed and re-rendered from the last cached state on
  re-open.
- **Crosshair toggle.** New `Crosshair: ON/OFF` button in the dummy overlay calls
  `CrosshairUI:SetUserEnabled(bool)` — a new developer override that hides both the fixed
  centre crosshair image and the floating gun-direction dot regardless of phase / hipfire
  state (hitmarker still flashes on hits). Client-only; `DummyDebugUI` requires
  `CrosshairUI` directly (sibling controller, initialised earlier by `ClientInit`).

## Ragdoll actually knocks the body over now (per-weapon knockback)

The death ragdoll "folded up while standing" instead of falling. Three fixes in
`RagdollService:Apply`, none of which change how a ragdoll is *entered*:

1. **The impulse was being swallowed.** `ApplyImpulse` on the fresh corpse did nothing
   until network ownership resolved a few frames later. `Apply` now `SetNetworkOwner(nil)`s
   every unanchored body part before the shove (server owns a dead body anyway). Studio
   physics probe: with this, the impulse lands the same frame; without it, not at all.
2. **Every joint had one 45° limit.** Now per-joint via `Constants.RAGDOLL_JOINT_ANGLES`
   (hips/shoulders 115°, root 100°, neck 45°) so the rig can collapse and roll instead of
   holding a rigid shape.
3. **The collidable legs propped it up.** Arms + legs go `CanCollide = false` while
   ragdolled (restored from a stashed `BR_RagdollWasCollide` attribute in `Restore`), so
   the collidable Torso slumps to the ground.

- Knockback is now **per-weapon**: `DummyService` looks up `Constants.RAGDOLL_WEAPON_IMPULSE`
  by `DamageInfo.sourceName`, falling back to `RAGDOLL_IMPULSE_DEFAULT`. Magnitude =
  `min(finalAmount * SCALE, MAX)`; applied with `ApplyImpulseAtPosition`
  `RAGDOLL_IMPULSE_HEIGHT_OFFSET` (1.2) studs above the Torso for topple torque, tilted
  down by `RAGDOLL_IMPULSE_DOWN_BIAS` (0.1). **AKS-74 = `{ SCALE = 4.5, MAX = 320 }`** —
  a firm topple, no launch. Add a `FUTURE_SHOTGUN = { SCALE = 12, MAX = 1100 }`-style
  entry later for weapons that should send bodies flying.
- Also disables the Humanoid `GettingUp` state during ragdoll (re-enabled on `Restore`).
- Removed `RAGDOLL_IMPULSE_SCALE` / `RAGDOLL_BALLSOCKET_UPPER_ANGLE`; all new
  `Constants.RAGDOLL_*` consumers have `or`-fallbacks for a partial Constants sync.
- **Not watched in a real death yet** — Edit mode doesn't step physics. Tuned from Studio
  probes (≈40 studs/s topples an R6 rig; 16 doesn't). If it still won't fall or flies too
  far, the knobs are `RAGDOLL_WEAPON_IMPULSE.AKS74.SCALE`, `RAGDOLL_JOINT_ANGLES`,
  `RAGDOLL_IMPULSE_HEIGHT_OFFSET`.

## Blood marks: small welded body splatter + carved wound + bigger ground pool

Owner feedback — the old marks plastered big flat red squares over the torso. Reworked
`BloodController`'s mark logic (`Constants.BLOOD_*` restructured):

- A `BloodEffect` only ever fires for a Humanoid that took damage, so the hit point is
  always on a body. The mark spawn now splits into three parts:
  - **Body splatter** — `BLOOD_BODY_MARK_COUNT` (3) *small* flat marks (≈0.18–0.5 studs)
    scattered around the entry point, **welded to the struck limb** (found by a short probe
    raycast) so they ride the ragdoll and vanish with the model on respawn.
  - **Carved wound** — one dark near-black `Enum.PartType.Ball` (`BLOOD_WOUND_COLOR`,
    ≈0.16–0.4 studs) sunk halfway into the limb along the shot line, also welded — reads as
    a bullet cavity.
  - **Ground pool** — the *bigger* marks (≈0.6–2.4 studs) + satellites, found by casting
    straight **down** from the hit (past the hit character, which is excluded from that
    ray). No floor within `BLOOD_GROUND_RANGE` → no ground marks (mid-air hit).
- No more rays fired along the shot direction into the body, so nothing large sticks to the
  torso. Welded body fx are a capped ring buffer (`BLOOD_MAX_BODY_FX`) with the same
  fade-in / fade-out; the Heartbeat sweep also drops records whose limb was destroyed.
- Removed `BLOOD_SPLATTER_RAYS/RANGE`, `BLOOD_MARK_SIZE_MIN/MAX`,
  `BLOOD_MARK_SATELLITE*`; added `BLOOD_BODY_MARK_*`, `BLOOD_WOUND_*`, `BLOOD_GROUND_*`.
  Burst (mist + droplets) unchanged. Server contract unchanged.
- Studio-verified: probe finds the limb, 3 body marks + 1 wound-ball weld to it, the
  down-ray finds the floor and places the bigger marks in `fxFolder`, ground marks measure
  ~3× the body marks, self-cleans.

## Test-area damage dummies + a blood realism pass

- **Dummies in the test area.** `Constants.DEV_TEST_AREA.SPAWN_DUMMIES` (default true) —
  `TestAreaBuilder` builds `DUMMY_COUNT` (3) standard R6 rigs downrange of the firing line,
  facing it, tagged `Constants.TAG_DAMAGE_DUMMY` + a `BR_TestAreaDummy` attribute so
  `DummyService` picks them up (damage / blood / hit reactions / ragdoll / respawn) and the
  builder can sweep its own rigs — and `DummyService` respawn clones, which inherit the
  attribute — on every rebuild. Rig geometry mirrors `scripts/Build-TestDummy.luau`. No
  new gameplay code; `DummyService` is untouched. `CollectionService` added to
  `TestAreaBuilder`'s requires. Studio-verified: the rig builds as a valid tagged R6
  Humanoid model (7 parts, 6 Motor6Ds, HP 100, PrimaryPart set).
- **Blood realism pass** (`BloodController` + `Constants.BLOOD_*`, rewritten):
  - Burst is now **two emitters** per pooled rig: a fine **MIST** (built-in soft smoke
    sprite, tinted, sprays back toward the shooter and tilts up) + heavier **DROPLETS**
    (blank-square flecks, narrower cone, ~5× the mist gravity so they arc and fall). Both
    fade base→dark over each particle's life.
  - Darker two-tone palette: `BLOOD_COLOR` `(112,6,6)` → `(104,12,12)`, new
    `BLOOD_COLOR_DARK` `(56,8,8)`.
  - **Surface marks** are now irregular (random footprint aspect, random rotation about
    the surface normal, per-mark colour lerp toward the dark tone, randomised opacity),
    smaller (≤ ~1.9 studs vs the old 4.0), each hit also drops a few tiny **satellite
    spatter spots**, and marks **fade in** on birth and **fade out** over the last 5 s
    instead of popping. Ray directions are biased toward the exit direction + downward
    (floor pooling) rather than fully random.
  - Server contract unchanged (`BloodEffect` still sends only position/dir/intensity/type;
    zero server instances). Hard caps kept: 12 pooled bursts, 56-mark ring buffer, global
    `BR_BloodGlobalEnabled` kill switch. Old flat `BLOOD_PARTICLES_*` keys removed.
  - Studio-verified: 2 emitters per rig, 40 rapid bursts + ~800 mark adds with no error,
    ring buffer holds at the cap, fade pass runs.

## Impact FX visibility bump + cursor hidden whenever armed

- **Impact FX chips/sparks were too small to see.** Bumped `Constants.BULLET_IMPACT_FX`
  per-category sizes/counts: metal SPARK 0.06→0.17 studs, count 10→16, life to 0.17 s;
  DEBRIS across all categories 0.08–0.10 → 0.14–0.18 studs, higher counts, and chip
  colours lightened so they contrast with the surface. Dust puffs slightly larger. All
  still short-lived and pooled at 24.
- **`ImpactFX` helper is now defensive.** If a partial Rojo sync leaves the old flat
  `Constants.BULLET_IMPACT_FX` in place, it falls back to built-in textures + a synthesised
  neutral dust/chip default instead of erroring on `pairs(nil)` — so a stale Constants
  degrades gracefully rather than killing all impact FX. Studio-verified both paths (old
  shape: no crash, neutral default; new shape: per-category params applied, pool 24).
- **Cursor:** `Constants.FIRST_PERSON_AIM.REQUIRE_ACTIVE_PHASE` (new, default `false`) —
  `GunController` now hides the OS cursor + locks it to centre whenever a weapon is
  equipped, in any match phase (so you're cursor-free just running around the test area).
  Set it `true` to restore the previous "only during the ACTIVE round" behaviour.

## Bullet impact FX: material-specific, and actually visible (helper logic Studio-verified)

The Stage 1 impact FX was invisible in-game — the emitter textures were `rbxassetid://0`
and the dust particle was 0.08 studs. Rebuilt around a material config:

- `Constants.BULLET_IMPACT_FX` restructured: top-level pool + textures + per-role gravity,
  a `MATERIAL_CATEGORY` map (`Enum.Material` → `concrete` / `metal` / `wood` / `dirt` /
  `default`), and a `CATEGORIES` table with a `DUST` / `DEBRIS` / `SPARK` sub-table per
  category (a missing sub-table = that emitter is silent for the category). Textures are
  now engine built-ins: `DUST_TEXTURE` = the built-in smoke sprite, `DEBRIS_TEXTURE` /
  `SPARK_TEXTURE` = `""` (a small solid square → chip / spark, no asset dependency, no
  "magic sparkle" look). Old flat `DUST_EMIT_COUNT` / `IMPACT_TEXTURE` / `POOL_ENABLED` /
  size keys removed.
- `GunController`'s `ImpactFX` helper reworked: each pooled rig now carries three emitters
  (dust / debris / spark). `ensureInit()` pre-resolves every category's `NumberRange` /
  `NumberSequence` / `ColorSequence` once, so `PlayImpact(pos, normal, material)` just
  looks up the category and assigns cached values before `:Emit()` — no per-shot
  allocation. Rig `+Y` is aligned to the surface normal so all three emitters fire away
  from the surface. Still a fixed pool (24), still reused/never grown, still local-only
  and never consulted for damage/hit validation.
- `attemptFire()` now passes `hitResult.Material` to `ImpactFX.PlayImpact`.
- Behaviour: concrete/brick/stone → gray dust puff + chips; metal → tiny bright
  directional sparks + a wisp of smoke; wood → tan splinter puff + light chips; dirt/
  grass/sand → subtle low dirt puff + dark specks; unknown → small neutral dust. Short
  lifetimes (dust ≈ 0.1–0.42 s, debris ≈ 0.15–0.34 s, sparks ≈ 0.04–0.12 s). Glass is
  **not** implemented (no simple glass material in use yet).
- Studio-verified (Client datamodel harness): material→category mapping correct for
  Concrete/Metal/Wood/Grass/Plastic/nil; per-category params are applied to the right
  emitters on each hit and a missing role leaves its emitter untouched; 300 rapid
  mixed-material calls raise no error; pool stays pinned at 24; asserts fire; `Destroy`
  cleans up. The in-game look still needs an eyeball pass.

## TestAreaBuilder tuning: lift the area into the sky + shrink the labels

- `Constants.DEV_TEST_AREA.ORIGIN` moved from `(0, 0, 0)` to `(0, 300, 0)`. The baseplate
  top was at Y 0, ~10 studs *below* the map's grass at the origin, so half the props were
  buried and unusable. It now floats clear in the sky (tallest map part ≈ Y 95); every
  prop, label and redirected spawn follows `ORIGIN` so nothing else changed.
- Section labels: `BillboardGui` shrunk from 240×46 → 96×22, `AlwaysOnTop` off (so they're
  occluded by geometry instead of punching through the whole scene), `MaxDistance`
  320 → 60 (only the section you're standing in shows), lighter background. `LABEL_LIFT`
  3 → 2.

## TestAreaBuilder: optional redirect of all team spawns into the test area (Studio-verified, reversible)

Follow-up so every player spawns in `BrokenReality_TestArea` while testing.

- New `Constants.DEV_TEST_AREA.REDIRECT_TEAM_SPAWNS` (default **true**), plus
  `TEAM_SPAWN_GRID_SPACING` and `SPAWN_BACKUP_ATTRIBUTE`.
- `TestAreaBuilder` now, after building its folder (Studio only), calls
  `redirectTeamSpawns()`: for every `BasePart` under `Workspace/Spawns` it (1) restores
  any part it moved on a previous run from the `BR_TestAreaOriginalCFrame` attribute,
  then (2) if the flag is on, stashes each part's current `CFrame` in that attribute and
  lays the parts out in a grid around `SPAWN_POSITION` on the baseplate. `TeamService`
  reads those parts' CFrames unchanged, so all round spawns land in the test area.
- **Reversible:** set `REDIRECT_TEAM_SPAWNS = false` (keep `ENABLED = true`) and press
  Play once — step (1) restores every spawn to its exact original CFrame and clears the
  attributes. It only ever writes `BasePart.CFrame` + that one attribute; never reparents,
  resizes, restyles, or destroys a spawn point.
- Still no new remotes, no `TeamService`/`MatchService` change, no gameplay logic change.
- Studio-verified against the live `Workspace/Spawns` (Attackers ×3 + Defenders ×3):
  redirect moves all 6 and tags them; a second run is position-stable (deterministic
  grid, no drift); toggling the flag off restores all 6 to their original CFrames with
  zero leftover attributes. Left fully restored after the check.

## Generated developer test area — `TestAreaBuilder` (build logic Studio-verified; in-game run not tested)

New Studio-only sandbox for iterating on movement, weapon feel, viewmodels, muzzle FX,
bullet impacts, reload timing, vaulting, crouch, sprint, and landing drops.

- New `Constants.DEV_TEST_AREA` table — every position / size / height / distance the
  builder uses, so the layout is tunable without touching code and the whole area is
  relocatable from `ORIGIN`.
- New server script `src/ServerScriptService/Services/TestAreaBuilder.server.lua`
  (mapped in `default.project.json`). On server start it **no-ops unless
  `RunService:IsStudio()` and `Constants.DEV_TEST_AREA.ENABLED == true`**. When it runs
  it destroys and rebuilds **only** `Workspace.BrokenReality_TestArea` — it never reads
  or modifies any other Workspace content, and never touches `game.Lighting`.
- Contents: baseplate; `TestSpawn` (enabled neutral `SpawnLocation` on a dais);
  **ShootingRange** (firing line, static targets at 25/50/100/150 studs with distance
  labels + neon bullseyes, backstop wall); **ImpactWall** (side wall for impact FX /
  spread); **MovementCourse** (sprint lane with 10-stud markers, crouch tunnel with 3.5
  stud clearance, Low/Medium/Too-Tall vault bars at the configured heights, three drop
  platforms at 4/8/14 studs with walk-up ramps, a 6-step stair run);
  **MaterialTest** (Concrete/Metal/Wood/Grass wall + floor samples — visual only);
  **LightingTest** (self-contained point light, spot light, and a shade overhang — no
  global lighting change). `BillboardGui` section labels when
  `DEV_TEST_AREA.DEBUG_LABELS == true`.
- Helpers only (`makeBlock` / `makeFolder` / `makeLabel` / `buildVaultBar` /
  `buildDropPlatform`), `assert`-validated params, `--!strict`. No RemoteEvents, no
  per-frame loops, no `RBXScriptConnection`s. No combat / damage / ammo / movement /
  camera / viewmodel / animation-ID changes.
- Studio-verified (Edit datamodel harness, self-cleaning): builds without error, a
  second build reproduces an identical 159-instance tree (safe rerun), exactly one
  `BrokenReality_TestArea` folder results, `workspace` gains exactly one child, all eight
  sections + `TestSpawn` + the four targets are present. The script auto-running on
  **server start** (Rojo sync + Play) is not MCP-testable — needs an in-Studio check.

## ADS is now zoom-only — viewmodel pose animation replaced by an FOV zoom + pivot glide (not Studio-tested)

Per owner request: "replace the ADS animation with just a zoom in."

- New `Constants.VIEWMODEL_ADS_ANIMATION_ENABLED` (default **false**). When false,
  `ViewModelController:SetAiming(true)` skips the `adsIn` pose clip and the
  Entering→Aiming watchdog machinery and drops straight to the held `Aiming` state;
  `SetAiming(false)` drops straight to `Hip`. The existing `adsAimAlpha` blend
  (`VIEWMODEL_ADS_AIM_BLEND_SPEED = 18/s`) still glides the viewmodel pivot to the
  camera-centred position and back, so the gun eases toward centre — just with no
  animated arm pose. Idle/locomotion animations keep running underneath (they are no
  longer stopped on ADS-in, so nothing needs resuming on ADS-out).
- The **FOV zoom already existed** and is unchanged: `MovementController.updateSprintFov`
  ("Task A") tweens `camera.FieldOfView` to `Constants.CAMERA_ADS_FOV` (70→56, or →52
  with the focus key) whenever `isAiming`. MovementController remains the sole FOV writer.
- `PlayADSFireAnimation()` now delegates to `PlayFireAnimation()` in zoom-only mode, so
  shots while aimed use the normal hipfire animation + recoil (owner's choice). The
  `adsFire` clip is only used when `VIEWMODEL_ADS_ANIMATION_ENABLED = true`.
- Fully reversible: set `VIEWMODEL_ADS_ANIMATION_ENABLED = true` to restore the authored
  `adsIn`/`adsIdle`/`adsOut`/`adsFire` sequence and its bounded-recovery watchdogs. The
  four ADS tracks are still loaded by `_setupWeaponAnimations` either way.
- Client/viewmodel only: no new remotes, no server/damage/ammo/fire-rate change, no new
  camera writer. `rojo build` clean. Not Studio-tested — a weapon can't be equipped from
  MCP; needs an in-game ADS toggle check (glide framing, FOV in/out, fire while aimed,
  reload/holster while aimed).

## Stage 1 local bullet impact FX (helper logic Studio-verified; in-game visuals not tested)

When the local player fires and the client raycast hits a surface, a small dust/smoke
puff + a few tiny sparks now play at the predicted hit point.

- New `Constants.BULLET_IMPACT_FX` table (enable/debug flags, placeholder textures, emit
  counts, lifetime/speed/size ranges, surface offset, `POOL_ENABLED` + `POOL_SIZE`).
- New `ImpactFX` helper **inside `GunController.lua`** (not a separate controller — see
  below): `ImpactFX.PlayImpact(position, normal?)` / `ImpactFX.Destroy()`. Fixed
  pre-built pool of `POOL_SIZE` anchored invisible parts under a `workspace/BR_ImpactFx`
  folder, each with an `Attachment` carrying a `Dust` and a `Spark` `ParticleEmitter`.
  `PlayImpact` orients the part's +Y to the surface normal (offset out by
  `IMPACT_SURFACE_OFFSET`), grabs the free rig (or the one finishing soonest — the pool
  never grows), and `:Emit()`s both emitters. With `POOL_ENABLED = false` it falls back
  to bounded create-and-destroy, still capped at `POOL_SIZE` concurrent. Cleanup is
  time-based (`task.delay`) — no stored connections.
- Wired in `attemptFire()`: `if hitResult ~= nil then ImpactFX.PlayImpact(hitResult.Position, hitResult.Normal) end`.
  `PlayImpact` self-gates on `BULLET_IMPACT_FX.ENABLED`. No change to fire rate, spread,
  bullet direction, `WeaponFired`, damage, ammo, recoil, camera, or the muzzle flash.
- **Removed** the old single-sphere debug impact (`Constants.BULLET_IMPACT_ENABLED` /
  `_SIZE` / `_LIFETIME` / `_TRANSPARENCY` / `_COLOR` and its inline `Part` block) — the
  new FX replaces it, and keeping both would double-own the impact visual. The unrelated
  `DEBUG_BULLET_IMPACT_MARKERS` muzzle-tip marker is untouched.
- No new remotes, no server changes, no `default.project.json` change (the helper lives
  in `GunController` precisely so no Rojo-map entry is needed this stage — extraction to
  `ImpactFXController.lua` is filed as debt).
- Studio-verified (Edit datamodel, self-cleaning harness): 300 rapid `PlayImpact` calls
  raise no error, the part count stays pinned at `POOL_SIZE` (20), the `assert` guards
  reject a non-`Vector3` position/normal, and `Destroy()` removes the folder. The actual
  in-game look (equip → shoot wall/ground) is **not** MCP-testable — a weapon can't be
  equipped from MCP — so eyeball tuning + placeholder-texture replacement remain.

## Hipfire: fire from the camera along the gun's rotation, not the viewmodel muzzle (not Studio-tested)

Measured in a Studio Play session: the previous "fire from the viewmodel `MuzzleAttachment`"
path was broken end to end.

- The auto-created `MuzzleAttachment` on the AKS-74 `Barrel` had its LookVector along the
  barrel's local **+X**, which is ~180° from the firing direction (`dot(+X, cameraLook) =
  -0.998`) — the auto-create picked the right axis, wrong sign.
- The viewmodel Model's pivot resolves ~330 studs from the player (detached from where its
  parts render), so the muzzle **origin** failed the server's proximity check — the console
  showed `[GunService] WeaponFired: origin too far from root` on **every** hipfire shot.
  Hipfire was doing zero damage.

Fix (owner picked this option): `GunController` now fires hipfire from
`camera.CFrame.Position` along `(camera.CFrame * CFrame.Angles(pitch, yaw, 0)).LookVector`,
where `(pitch, yaw)` is the free-aim rotation the viewmodel is actually drawn with, newly
exposed as `ViewModelController.GetFreeAimAngles()` (0,0 while ADS or holstered). Bullets
leave in the direction the gun visually points — same intent as before — but with no
dependency on a cosmetic attachment and with a camera-anchored, server-valid origin. ADS
and free-aim-off keep the camera-ray-through-reticle path.

- `ViewModelController` publishes `freeAimAimYaw` / `freeAimAimPitch` each frame from the
  same values that build `freeAimCF` (swing included, roll excluded — roll isn't aim).
  Reset to 0 on holster / `StopWeaponAnimations` / ADS.
- `setupMuzzleFx` auto-create sign fixed too: the bore axis is flipped if it points back
  toward the model centroid, so the **muzzle-flash emitters** face forward. (Firing no
  longer uses this; authoring a real `MuzzleAttachment` per weapon in Studio is still the
  right long-term move.)
- `GetMuzzleWorldCFrame()` kept as a public accessor, now unused by the fire path.
- No new remotes, no server changes, no ammo/damage/hit-validation change — the server
  still re-raycasts the client origin+direction. `rojo build` clean.
- **Needs the in-game check** the previous two entries also need: equip, confirm hipfire
  now damages and lands where the gun points, and that `origin too far from root` is gone.

## Free-aim: rotation is now the primary hipfire effect + bounded flick swing (not Studio-tested)

Follow-up to the Tarkov-style hipfire commit. Owner reported the viewmodel would not
visibly rotate toward the aim when the mouse moved right — it "slid left and returned to
centre" — while moving left looked fine.

- **Root cause: scale mismatch in `ViewModelController`'s `freeAimCF`.** The raw
  mouse-inertia velocity (`vmMouseInertia`, clamped to `MOUSE_INERTIA_MAX` ≈ 26–30) was
  summed straight into the roll and X/Y translation terms alongside `vmFreeAimBlended`
  (clamped to ≈ 1). On any fast mouse move the inertia term outweighed the reticle offset
  ~30×, so the frame's dominant motion was a large lateral translation *opposite* the
  flick, which then damped back to centre — burying the ~4° muzzle rotation. The rotation
  math itself was already symmetric.
- **Fix:** normalise the inertia to ~[-1, 1] (divide by `MOUSE_INERTIA_MAX`) before it is
  used anywhere, so `(reticle + inertia)` sums stay bounded (≤ 2). The lateral lurch is
  gone; the yaw/pitch that points the muzzle through the reticle is now the visible effect
  and is equal-and-opposite left vs. right.
- **Added a real rotational swing.** Fast mouse motion now folds the normalised inertia
  into `freeAimYaw` / `freeAimPitch` (not just translation) as a trailing rotation —
  weapon mass — scaled by the new `Constants.FREE_AIM_VIEWMODEL_SWING_FACTOR` (0.5) and
  the per-state inertia weight (so it fades to ~0 in ADS like everything else). This is
  the "swings on fast moves" the owner asked for.
- One new constant (`FREE_AIM_VIEWMODEL_SWING_FACTOR`); no new remotes, no server/camera/
  ammo/damage changes. `rojo build` clean; both modules compile in a Studio require.
- **Still needs an in-game check** (MCP can't equip a weapon): confirm the gun now points
  right when aiming right, the swing feels right, and whether any *constant* leftward lean
  remains — if so that is the AKS-74 viewmodel idle animation / FakeCamera `BASE_OFFSET`
  alignment, not free-aim, and must be fixed on the rig in Studio. See TECHNICAL_DEBT.

## Damage test dummy — Stages 4–6: blood, hit reactions, debug UI (not Studio-tested)

- **Ragdoll impulse retuned** after owner test — it flung the rig across the room. Scale
  45→1.5, clamp 4000→200, and the impulse now lands on the Torso (main mass) instead of
  the hit limb, so it reads as a stagger. Both values in `Constants`.
- **Blood (Stage 4).** New `BloodEffect` remote. New server `BloodService` (data only —
  listens to `CombatEvents.DamageDealt`, computes intensity from `finalAmount`,
  rate-limited per target, `FireAllClients`, creates zero instances). New client
  `BloodController` (`Controllers/`, reusable, not dummy-bound): fixed pool of particle
  bursts + a ring buffer of `BLOOD_MAX_MARKS` texture-free surface marks from raycasts
  around the hit, Heartbeat expiry, hard caps. Global kill switch = `BR_BloodGlobalEnabled`
  attribute on ReplicatedStorage (server-set, both sides read it live; flipping it off
  clears existing blood at once). New `Constants` blood block.
- **Hit reactions (Stage 5).** New server `HitReactionService`: on `DamageDealt`, for a
  live non-ragdolled model tagged `BR_ReactionsEnabled`, writes a decaying additive
  `Motor6D.Transform` offset on one joint chosen by hit region
  (`Constants.REACTION_REGION_JOINTS`), strength from `finalAmount`, direction from the
  shot vector in the rig's frame. Heartbeat lerps back to identity; every offset has a hard
  deadline so it can't stick. Never touches C0/C1, `Motor6D.Enabled`, `PlatformStand` or
  `WalkSpeed`. `applyReaction` is the single seam for an animation-based provider later.
  New `Constants` reaction block.
- **Debug UI (Stage 6).** New `DummyDevCommand` / `DummyDevState` remotes. `DummyService`
  gained a dev-gated command handler (Studio or `Constants.DEV_USER_IDS`) — `subscribe` /
  `reset` / `heal` / `infinite` / `blood` — and a throttled state stream. New client
  `DummyDebugUI` (`Controllers/UI/`, built only for developers): per-dummy HP / last hit /
  per-limb pool / INF / RAGDOLL, plus Reset / Heal / Infinite / Blood / Hitboxes buttons.
  Hitbox viz is local `SelectionBox` adornments per R6 part — no server instances.
- `ClientInit` registers `BloodController` (13) and `DummyDebugUI` (14). `RemoteSetup` and
  `default.project.json` updated. Gore still absent — `CombatEvents` + the limb pool remain
  the only seam it needs.
- Not installed in Studio (blocked on the Rojo plugin reconnect), not committed.

## Damage test dummy — Stages 1–3 (not Studio-tested, not committed)

Developer-only tooling for weapon damage / hit reactions / blood / ragdoll / future gore.
Built incrementally; Stages 4–6 (blood, reactions, debug UI) are paused for review. Gore is
out of scope by design. See `docs/DAMAGE_TEST_DUMMY_PLAN.md`.

- **Damage pipeline is now entity-agnostic and event-emitting.** New `CombatEvents`
  (BindableEvents `DamageDealt` / `EntityKilled`, DamageService is the only producer) and
  pure `DamageRules` (R6 part→region, region multiplier, final-damage math — mirrors
  `DestructionRules`). New shared types `DamageType` / `HitRegion` / `DamageInfo` /
  `DamageRequest`. New `Constants` "Combat" block (region multipliers, R6 part map,
  tags/attributes, dummy + ragdoll tuning).
- `DamageService` extended, not rewritten: `ApplyDamage(request)` damages players **and**
  non-player Humanoid entities; `Apply()` is now a thin shim (region forced to Unknown, ×1
  — legacy numbers unchanged) that also emits the combat events. Added tooling helpers
  `Heal` / `SetInvincible` (unused until Stage 6).
- `GunService` hit branch generalised: player → shared pipeline **with body part** (so
  headshot multipliers apply to PvP too), a Humanoid model tagged `BR_DamageEntity` →
  shared pipeline, breakable → `DestructionService`, else ignored. No dummy-specific weapon
  code.
- New `DummyService` (server Script): registers models tagged `BR_DamageDummy` (at start
  and at runtime via CollectionService signals), primes the Humanoid, adds the generic
  `BR_DamageEntity` tag, tracks a per-limb health pool from `DamageDealt` (bookkeeping only
  — does not gate death), and on death ragdolls with the shot's preserved impulse then
  respawns a fresh clone after `Constants.DUMMY_RESPAWN_DELAY`. Reset == respawn (a dead R6
  Humanoid is not revived).
- `RagdollService` generalised: `Apply(character, opts)` with player-only side effects
  gated on `opts.player`; new `Restore(character)` (removes the constraints/attachments it
  made, re-enables Motor6Ds) and `IsRagdolled`; preserves incoming shot impulse so deaths
  vary; `BreakJointsOnDeath` forced off so joints survive for `Restore`. The player death
  path is behaviourally unchanged. `BallSocketConstraint.UpperAngle` moved to Constants.
- New `scripts/Build-TestDummy.luau`: one-shot **Studio** helper (Command Bar / temp
  Script, not Lune) that builds a canonical R6 rig, tags it `BR_DamageDummy`, and parents
  it to Workspace.
- No new remotes. `default.project.json` maps the three new server modules.
- Not installed in Studio, not committed, not Studio-verified. Intentional live change:
  PvP headshots now do ×2 (`Constants.DAMAGE_REGION_MULTIPLIERS`).

## Tarkov-style hipfire: bullets from the muzzle + cursor lock (not in-game verified)

Client-only, no server / remote / ammo / damage / hit-validation change.

- **Bullets leave the muzzle, along where the gun points.** `GunController`'s hipfire
  raycast now originates at the viewmodel `MuzzleAttachment` and travels its LookVector
  (`ViewModelController.GetMuzzleWorldCFrame()`), instead of a camera ray through the
  reticle pixel offset. Because the viewmodel is already rotated toward the free-aim
  reticle (`FREE_AIM_VIEWMODEL_TRACK_FACTOR`), that direction *is* "where the gun points".
  ADS and "no muzzle" fall back to the camera path. Gated by
  `Constants.FREE_AIM_FIRE_FROM_MUZZLE`. Server origin/direction validation + re-raycast
  unchanged (muzzle origin is ~2-3 studs from camera, well inside `SHOT_ORIGIN_MAX_DISTANCE`).
  This wires the long-standing `DEBT-063` (free-aim → firing) — see TECHNICAL_DEBT.
- **Per-weapon free-aim feel.** New `Constants.FREE_AIM_PROFILES` (`DEFAULT` + `AKS74` +
  `AR15`) overriding the weight/inertia knobs (deadzone radius, mouse gain, reticle lag,
  viewmodel blend speed, track factor, mouse-inertia gain/max) per gun. `FreeAimController`
  gained `SetWeapon(name)` (`SetWeaponEquipped` kept as a shim); `ViewModelController`
  resolves its own profile on equip. Non-listed `FREE_AIM_*` constants stay global.
- **White cursor gone during weapon use.** New `Constants.FIRST_PERSON_AIM` table.
  `GunController` sets `MouseBehavior = LockCenter` + `MouseIconEnabled = false` while armed
  in the ACTIVE phase (edge-triggered), and restores on holster / respawn / phase change —
  restoring the pre-lock `MouseBehavior` so `MovementController`'s own LeftControl mouse-lock
  is preserved, not clobbered.
- **Centre crosshair hidden in hipfire.** `CrosshairUI:SetHipfireActive` — only the floating
  gun-direction reticle (`barrelDot`) shows while hip-firing; the fixed centre crosshair
  returns for ADS. Gated by `Constants.FREE_AIM_HIDE_CENTER_CROSSHAIR_HIPFIRE`.
- Compiles, all client controllers load clean, `rojo build` passes. **Runtime not
  MCP-verifiable** (module require-context split): the yaw sign of the muzzle rotation, the
  in-game feel, and the cursor lock need an in-game test — press 1, hip-fire while moving
  the mouse, confirm bullets land where the gun points and the OS pointer is gone. If the
  gun points *away* from the reticle, flip the `freeAimYaw` sign in ViewModelController.

## Stage 1 first-person muzzle FX (MCP-verified in a Studio Play session)

- New local, visual-only first-person muzzle flash for the viewmodel weapon:
  brief ParticleEmitter flash + tiny smoke puff + small spark burst + a ~35 ms PointLight
  pulse, played when the LOCAL player fires. All instances live under the viewmodel Model.
- `Constants.MUZZLE_FX` (new): `ENABLED` / `DEBUG`, attachment name list, auto-create
  settings, a `DEFAULT` tunable block, and per-weapon `PROFILES` (AKS74 + AR15) merged
  over `DEFAULT` so the flash / smoke / spark / light can differ per gun.
- `ViewModelController` (only client file touched): `resolveMuzzleProfile`,
  `createMuzzleFxEmitters` (spec helper), `setupMuzzleFx`, `clearMuzzleFx`, and
  `ViewModelController.PlayMuzzleFlash()`. Setup runs once per equipped viewmodel (in
  `EquipWeapon`); `PlayMuzzleFlash()` is called from the end of `PlayFireAnimation()`
  (hip fire) **and** the start of `PlayADSFireAnimation()` (fire while aiming — before its
  "Aiming" pose guard, so a shot mid-ADS-transition still flashes), so **GunController was
  not changed**. `init` / `HolsterWeapon` clear the references and bump a token so pending
  `task.delay` light callbacks no-op.
- ADS transition sped up: `Constants.VIEWMODEL_ADS_TRANSITION_SPEED_MULTIPLIER` (1.35) is
  applied via `AnimationTrack:AdjustSpeed` to the adsIn and adsOut clips in `SetAiming`
  (after `Play`, since `Play()` resets speed to 1). Raising/lowering the sights is ~35%
  faster; animation assets untouched.
- If the viewmodel has no `MuzzleAttachment`, one is auto-created on a BasePart named
  "Barrel"/"Muzzle" (the AKS-74 viewmodel has a `Barrel` part) with a one-time warn.
  Placeholder particle textures (`rbxassetid://0`) also warn once.
- Verified in Studio via MCP: emitters + light created from the correct per-gun profile,
  built once (not per shot — 30 fire calls kept the same 4 child instances), light pulses
  true→false over `LIGHT_DURATION`, no Output errors, AR15 (no barrel part) fails
  gracefully.
- Visual-only. No server, remote, combat, ammo, reload, damage, or camera behaviour
  changed. No third-person / replicated flash, tracers, shell ejection, or impact FX.

## Reload / sprint / fire movement interactions (not Studio-tested)

- **Reload ↔ sprint.** A reload in progress cancels an active sprint and blocks starting a
  new one (`MovementController.SetReloading` → `SetSprinting(false)` on the edge; LeftShift
  handler early-returns while `isReloading`). Gated by `Constants.RELOAD_BLOCKS_SPRINT`.
- **Reload move speed.** While reloading, the movement target speed in `getTargetMoveSpeed`
  (the one choke point both speed paths use) is multiplied by
  `Constants.RELOAD_MOVE_SPEED_MULTIPLIER` — now **0.55** (was 0.85), roughly half / three-
  fifths walk speed.
- **Sprint ↔ fire (mutually exclusive).** New `Constants.SPRINT_BLOCKS_GUN_USE`. Cannot
  fire while `MovementController:GetMoveState() == "Sprinting"` (new guard in
  `GunController.attemptFire`, alongside the existing tactical-sprint guard). Cannot start a
  sprint while auto-fire is active — GunController pushes fire state each frame via the new
  `MovementController.SetFiring`, and the LeftShift handler early-returns while `isFiring`.
  Whichever input came first wins; the other is ignored until released.
- Client-side only; no server, remote, or animation change.

## AKS-74 empty reload animation (not Studio-tested)

- Added `WeaponData.AKS74.animations.firstPerson.reloadEmpty` (`rbxassetid://128124271528232`,
  verified in-place: 179 keyframes / 3.7s).
- `ViewModelController._setupWeaponAnimations` loads it into a new optional
  `weaponReloadEmptyTrack` (cleared alongside `weaponReloadTrack` in `init` /
  `StopWeaponAnimations`). `PlayReloadAnimation(isEmpty)` plays the empty track when
  `isEmpty` and it is loaded, else falls back to the tactical `reload` track.
- `GunController` passes `currentMag <= 0` so an empty-magazine reload uses the new clip.
  No server or remote change — reload validation is unchanged.

## Wood/door destruction (main game, bullet-driven, no explosives)

- Added `src/ServerScriptService/Services/DestructionService.lua` and `DestructionRules.lua`: server-authoritative, attribute-driven (`BR_BreakableProfile`) wood destruction, ported from the already offline-tested `prototypes/CityDistrict/DestructionService.lua` and retargeted from that isolated test subtree to the whole live main-game `workspace`. One profile, `Wood` (health 80), covers doors, crates, fences, planks — any wood prop.
- A door authored in Studio as several independently tagged parts (frame/panels/etc.) already breaks piece-by-piece with this — no per-door code exists or is needed, matching the requested Rainbow Six Siege behavior.
- Wired into `src/ServerScriptService/Services/GunService.server.lua`: any shot that doesn't hit a player is now checked against the registered breakables using the same already-validated server raycast. No new remote — `PartDestroyed` (pre-existing, previously unused) is fired as a break-VFX hook.
- Explosive/AoE damage is explicitly deferred (owner instruction) — not implemented.
- Added `scripts/Test-Destruction.luau`, mirroring the prototype's proven `TestDestruction.luau` assertions; not executed in this environment (no local Lune), verified by manual trace only. See `docs/DESTRUCTION_SYSTEM_PLAN.md`.
- Not installed in Studio, not committed, not Studio-verified.

## Animation lock recovery (equip / ADS)

- Extended the reload recovery pattern below to `PlayEquipAnimation` and to ADS-in/ADS-out in `SetAiming`: each now has a Heartbeat watchdog (tracked connections, cleared on weapon switch/holster/respawn/ADS interrupt) that force-resumes the correct state if the one-shot animation's `Stopped` signal never arrives, using new `VIEWMODEL_EQUIP_LOAD_TIMEOUT`/`MAX_DURATION` and `VIEWMODEL_ADS_LOAD_TIMEOUT`/`MAX_DURATION` Constants (3s / 10s, matching reload's values).
- Rationale: a stuck ADS "Entering"/"Exiting" state left `IsAiming()` permanently true, which silently routes every future shot to the ADS fire animation — itself a no-op outside the "Aiming" state — so the gun kept firing server-side with no visible fire animation. A stuck equip state left the weapon frozen at bind pose. See RELOAD_DIAGNOSIS.md "Extended scope" for detail.
- The equip fix preserves the existing immediate `Play()` call unchanged (success path untouched); it only adds a recovery net. No animation asset IDs were changed.
- Re-verified (by manual trace, not by running Lune — not installed in this environment) that all 13 existing `scripts/Test-Reload.luau` assertions still hold against the current `PlayReloadAnimation` source; that method was not modified this pass.
- Not installed in Studio and not Studio-tested. See TECHNICAL_DEBT.md.

## Reload recovery

- Added bounded asset loading and playback recovery to ViewModelController, with timeout tuning in Constants and explicit reload connection cleanup. FP playback is independent of TP playback errors.
- Added 13 mocked regression assertions and syntax compilation of the two edited runtime files. Visual asset failure cause and Studio verification remain pending; existing asset IDs and original place are unchanged.

## 2026-09-08 — VS Code sourcemap path

- Pointed Luau LSP at the verified project-local Rojo 7.6.1 executable and selected `default.project.json` for code navigation.
- Ignored the generated `sourcemap.json`. This changes editor metadata only and does not start a Rojo server or connect Studio.

## 2026-09-08 — daily GPT / Claude / Rojo workflow

- Added `AI_HANDOFF.md` and `AI_DECISIONS.md` so both assistants share current state and durable owner decisions through Git.
- Added a tracked VS Code workspace plus safe start and pre-commit review tasks. The start task refuses to pull over uncommitted files and permits only a fast-forward update of `main`.
- Installed and verified Codex 26.901.22334, Claude Code 2.1.263, Rojo 2.1.2, and Luau LSP 1.69.0 VS Code extensions.
- Rebuilt both Rojo configurations successfully. No Rojo server was connected to Studio, no gameplay source changed, and no place was published.
- Scoped Git's safe-directory allowance to each workflow command so the normal Windows account can use this sandbox-created checkout without changing global Git settings.
- Changed the GitHub default branch to `main`; preserved `claude/create-claude-md-AqEm8` as historical context.

## 2026-09-08 — shared GPT / Claude laptop setup

- Verified main matches the remote before setup; retained the historical Claude branch.
- Installed official Codex VS Code extension 26.901.22334 and verified existing Claude Code 2.1.263 in VS Code 1.135.0. Account sign-in and model selection remain user-controlled.
- Added shared handoff instructions and extension recommendations. Disabled automatic formatting only for this workspace. Opened the existing checkout in VS Code.
- Retained matching Rojo CLI/plugin 7.6.1; rebuilt the Logger pilot and rechecked the immutable Studio backup hash. No Studio sync, gameplay source change, or publish was performed.

## 2026-09-08 — isolated Mercer District prototype

- Added a separate city builder, geometry model, test place, and overhead plan: brick homes, corner shops, warehouses, alleys, protected staging cover, and three objective areas.
- Added server-owned destruction for 132 selected pieces with material health, bounded cosmetic debris, PREP reset, and connection cleanup. Reused the existing validated server shot path and existing match events; no new remotes.
- Kept migrated src unchanged. Only the generated test copy integrates destruction, changes test lighting, and archives original Workspace objects under ServerStorage.
- Passed 22 offline checks, syntax compilation, and original Workspace source preservation checks. Assistant observed the separate place enter ACTIVE; user-confirmed Studio destruction/multiplayer verification is pending.
- Deferred reload animation debugging. No publish or live Rojo handoff performed.

## 2026-09-07 — documentation baseline

- Inspected the provided local workspace: no existing scripts, Rojo configuration, or Git repository found.
- Created AGENTS.md and the six requested project documents.
- Recorded R6, AKS-74 / AR-style viewmodels, custom movement, and PvPvE direction.
- Defined Studio asset ownership and a staged script handoff.
- Added a migration plan. No gameplay code written or edited; no Rojo connection/configuration, Git initialization, or GitHub publishing performed.
- Studio backup, inventory, and testing remain unconfirmed.

## 2026-09-07 — laptop setup started

- Added the owner's big-map stabilization-team premise; opposing citizens/defenders design remains undecided.
- Added .gitignore and empty source-capture and reviewed-source folders.
- Confirmed Git and VS Code are on the command path; Rojo and gh were not found there.
- Native Studio UI control is unavailable in this session. Awaiting a user-saved place copy before source inventory or sync configuration.

## 2026-09-07 — saved-place capture

- Received the saved binary place and made a separate test copy; both hashes match.
- Used official Lune 0.10.5, with its downloaded archive checked against the GitHub release checksum, to read the place without running gameplay or writing the place.
- Captured 216 script sources and verified the output bytes against decoded saved source; added inventory and metadata records.
- Found 184 Workspace-embedded scripts and 32 scripts in main code locations. Existing Logger and Constants modules are present.
- No source was edited; no remotes or sync project created. Studio visual/behavior verification and GitHub backup remain pending.

## 2026-09-07 — Rojo configuration prepared

- Recorded the owner's positive test-copy report; no post-sync test is claimed.
- Copied 32 main scripts unchanged into src/ at their existing hierarchy.
- Added a Logger-only pilot and an explicit 32-script configuration, with unknown-instance preservation on every affected node.
- Installed the official verified Rojo 7.7.0 CLI locally and validated both builds and mappings against the saved place.
- Downloaded the matching verified Studio plugin; installation remains pending because filesystem write permission was not granted.
- Added a VS Code task for the pilot. No server started, Studio connection made, or gameplay source edited. GitHub remains pending repository selection.

## 2026-09-07 — existing GitHub repository reconciled

- Connected origin to the owner's Intacet/BrokenRealityFPS repository and inspected its existing branch/history.
- Confirmed all 32 main scripts match the prior GitHub tip byte-for-byte.
- Added a shared CLAUDE.md entry point and README to direct future tools to current instructions.
- Retained the migration tree while joining the older branch history; the original branch is preserved. Main is the new migration branch; the GitHub default branch is unchanged.

## 2026-09-07 — GitHub upload and native Studio access

- Uploaded main successfully using normal Windows Git credentials; preserved the old remote branch.
- Native Studio control became available. Observed the migration test window and existing Rojo 7.6.1 plugin.
- Matched the local CLI to official Rojo 7.6.1 and rebuilt both configurations successfully.
- Saved the test copy and revalidated all mapped scripts against it before attempting the pilot connection.


## RPG-7 gameplay prototype — 2026-09-11

Owner requested continuation after RPG import. Added RPG7 loadout (one loaded/four reserve), semi fire, 4.8-second server-validated reload, server ray-swept rocket flight (140 studs/s, 600-stud limit), impact blast (14-stud radius, distance falloff, occlusion checks), and procedural presentation using the existing shared arms module. No new remotes. RocketService uses the existing DamageService with Explosion/Unknown-region damage and a visual-only zero-pressure Explosion. WorldWeaponService now accepts registered worldModelName entries instead of an AKS74-only guard.

Assistant MCP checks: equipped RPG7 visible with arms; fire consumed 1/4 to 0/4; reload restored 1/3; controlled blast target health 56.56 exposed, 100 behind cover, 100 outside radius. Seven changed scripts compiled before the world-model guard refinement. Source pack clips remain archived, not published/retargeted animation tracks. Generic rocket visual/audio and procedural reload remain polish work; no prop demolition is wired. No user-confirmed playtest or publishing claimed. Test sessions stopped and temporary QA instances discarded.


## Material destruction — 2026-09-11

Implemented server-owned Wood, Glass, Plaster, Brick, Concrete, and Metal profiles, with bullet/blast multipliers. Existing anchored-part opt-in remains: BR_BreakableProfile is a profile name or Auto (Material lookup). Untagged geometry is preserved. Runtime additions register automatically; call DestructionService:Register after assigning an attribute to an already-parented part. Bullet hits also attempt lazy registration.

RPG impacts now call ApplyBlast after character damage. Blast range/falloff uses nearest oriented-box point; cover visibility is snapshotted before applying changes, preventing a single blast from destroying successive layers through cover. Existing fragment budget and PREP reset are retained. This is whole-part destruction; authored segmented panels give partial breaches. No arbitrary mesh cutting or structural collapse.

Assistant MCP tests: a 30-damage bullet left Glass 0, Wood 50, Plaster 31, Brick 145.5, Concrete 240, Metal 198.5 health. Untagged parts rejected damage; invalid blast radius rejected; broken parts rejected repeat hits; reset restored health, transparency, and collision. A glass front panel blocked damage to another glass panel behind it within the same blast. Runtime Auto-material registration and RPG-impact glass destruction passed. These are assistant tests, not owner-reported verification. Studio RocketService required a targeted manual hook update because the active Rojo process had not loaded its new mapping. Sessions stopped and temporary test objects cleared.

Workspace.MaterialDestructionRange contains six labeled opt-in sample panels at the elevated test range (y=303, z=-48). No other map geometry was newly tagged. Generic material-matched fragments are used; unique shatter sounds/dust/chipping remain future polish. Not published.


## Irregular fracture prototype — 2026-09-11

Owner rejected the untested cell-grid direction and requested Battlefield-style irregular breaches. Removed the grid implementation and its configuration. DestructionService now supports authored irregular section Models, shared section health, precise planar polygon blast distance, steep local blast falloff, rigid cosmetic slab detachment, foundation/neighbor-graph support checks, and full PREP reset. Ordinary tagged material parts retain their previous behavior. No new remotes.

Workspace.FractureWallDemo is a 14x8x0.65 concrete wall, centered (-28,304,-30), with 18 irregular sections made from 118 wedge primitives (no voxel cells). The wedges inside each section share health and detach together. Foundations and shared-edge neighbor lists were generated from clipped Voronoi polygons. Labeled RPG test wall added. Rotated brick surface textures exposed each triangle, so this demo deliberately uses concrete; authored UV meshes are still preferable for brick courses and detailed finishes.

Assistant MCP tests: actual RocketService projectile opened four of 18 sections, leaving an irregular central breach. Shared health, concrete bullet resistance, collapse after removal of all foundations (18 sections), debris cap/noncollision, and complete health/collision/visibility reset passed. Changed scripts compiled; whitespace check passed with Windows line endings recognized. Test objects discarded by stopping Play. No user-reported verification or publishing claimed.

Authoring: parent BaseParts under section Models marked BR_FractureRegion=true. Give each piece BR_BreakableProfile. Put sections under a wall Model; mark base sections BR_Foundation=true, list adjacent section names in comma-separated BR_Neighbors, and enable BR_SupportCollapse on the wall. Generated planar sections also store BR_FracturePolygon; wall pivot and BR_FractureFrame/BR_FractureThickness define the face for precise blast distance. A section must fit wholly inside the global registration budget. Model movement during active simulation is not supported; walls are anchored static structures.

Scope: this is a working pre-fractured-wall prototype, not automatic arbitrary-map fracture, mesh carving, full building load simulation, layered plaster/rebar, or persistent rubble. Debris is cosmetic, noncolliding, globally capped at 64 primitives and expires. Materials still use the established damage profiles. Only the demonstration wall has been authored with the new irregular geometry; the six earlier sample panels remain whole-part tests.


## Wood splinters and metal snap fragments — 2026-09-11

Added material-specific break presentation to existing tagged objects and fracture sections. Wood emits long tapered WedgePart splinters; metal emits thin angular shards with greater velocity and spin. Authored fracture slabs also use material-specific launch motion. Shared debris budget/noncollision/lifetime and existing damage/reset rules remain. No new remotes or sound assets.

Added WoodFractureDemo (14 elongated irregular regions, 80 primitives, x=-46) and MetalFractureDemo (10 angular regions, 58 primitives, x=-10), both y=304,z=-30. Wood geometry was refined from overly straight full-height strips to staggered long fractures. Wood material avoids rotating plank-course patterns. These are authored demo patterns; existing ordinary props receive debris styles but do not automatically acquire irregular geometry.

Assistant MCP tests confirmed WoodSplinter and MetalShard output, tapered/thin dimensions, noncolliding/nonqueryable debris, and reset restoring both models and clearing debris. Visually reviewed wood splinters and metal sharp breach edges in play. Source compile passed. Sessions stopped; no publishing or user-reported verification claimed. Rebuild scripts saved in outputs/MaterialFractures in the active task workspace.


## Fine wood and concrete fractures — 2026-09-11

Owner requested smaller wood/concrete pieces, with very small gunfire wood splinters and larger explosive debris. Damage kind now reaches the break presentation: wood bullet breaks emit 0.154–0.275-stud tapered splinters and suppress the large detached slab; explosive/collapse breaks retain 1.26–2.25-stud splinters plus slab detachment. Existing metal behavior remains. No new remotes.

WoodFractureDemo now has 140 irregular regions (1021 wedge primitives after degenerate wedges are skipped); FractureWallDemo now has 48 regions (333 primitives). Global registration ceiling increased from 800 to 1800 for the denser test assets; cosmetic debris ceiling remains 64. This is a bounded demonstration density, not a recommendation to prefracture an entire map at this resolution. Only authored fracture walls get the smaller openings; ordinary tagged props still break as a whole part with the updated debris style. Wood procedural texture orientation varies across wedge geometry; unified authored UVs remain visual polish.

Assistant MCP tests: all wood/concrete pieces registered; one bullet destroyed exactly one small wood region, emitting only tiny splinters (observed max 0.251 studs). An explosive hit emitted larger splinters (observed max 2.243 studs) and slabs. Visual checks confirmed the small gunfire hole and finer concrete breach. Reset restored collision, visibility, and intact flags for both denser walls. Script compiled. Test session stopped and temporary checks removed; not published and no user-reported verification claimed.


## Concrete RPG breach tuning — 2026-09-11

Added a concrete-only fracture blast falloff exponent of 4 (other fracture materials retain 5). Assistant MCP comparison at the same RPG impact broke 10 concrete sections versus 8 previously. Character blast damage/range and wood/metal rules unchanged. Playtest stopped; not published.


## Visible support collapse — 2026-09-11

Fixed unsupported sections disappearing when cosmetic clone debris hit its 64-primitive budget. Support collapse now animates the existing unsupported geometry as a falling group; it does not allocate debris clones. Gravity-driven visual descent is capped by a downward ground ray, with a slight tip. Sections remain for six seconds and fade over 1.2 seconds. Collision/query are disabled during collapse; this is cosmetic server-controlled motion, not a dynamic rigid-body simulation. Bullet/explosion chips retain their separate limits. Original transforms are recorded and restored on Reset; shutdown/removal clears tracking.

Assistant MCP test severed wood along an exact horizontal polygon cut: 447 unsupported primitives remained visible and moved downward (>0.1 studs), exceeding the old clone budget without disappearance. Timed fade cleanup and reset restoring original positions/visibility/collision passed. Source compiled and whitespace check passed. Playtest stopped; not published.
