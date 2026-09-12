# Technical debt and unresolved migration questions

## AI Stage 1A — server-owned squad NPC foundation (Studio verification: REQUIRED, not done)

`AIService.server.lua` + `Constants.AI` add basic R6 rifleman "grunt" squads:
spawn from `Workspace/AISpawns`, patrol `Workspace/AIPatrolPoints`, detect players
by server raycast LOS, chase, and burst-fire server raycasts. `Workspace/AI` holds
live models. This is **foundation only** — the AI system is NOT complete.

- **Not runtime-verified.** `default.project.json` gained the `AIService` mapping
  (structural — `rojo serve` restarted), but MCP can't drive a player near a grunt
  or watch chase/attack/death. `TestAreaBuilder` now builds the input folders
  automatically (`DEV_TEST_AREA.SPAWN_AI_ZONE` → `Workspace/AISpawns` +
  `Workspace/AIPatrolPoints` with anchored marker parts, plus an "AI Patrol Zone"
  pad in the test area), so a Studio Play pass just needs: connect Rojo, Play Solo,
  confirm `Workspace/AI` appears with squads walking the patrol loop in the AI Zone
  corner of the test area, walk into `DETECTION_RANGE`, confirm detect → chase →
  attack, kill a grunt (or set `Humanoid.Health = 0`), confirm Dead + model cleanup
  after `DEATH_CLEANUP_DELAY`, run several minutes for Output spam / runaway count /
  server hitching, then Stop with no errors.
- **Server-script order is handled, not assumed.** `AIService` connects
  `workspace.ChildAdded` (stored in `serviceConns`, disconnected in `Destroy()`) and
  re-scans if a `Workspace/AISpawns` / `AIPatrolPoints` folder appears after it
  started — so it does not matter whether `AIService` or `TestAreaBuilder` runs
  first. This also picks up folders/parts added by hand mid-session. This is the
  service's one persistent connection.
- **Pathfinding is `Humanoid:MoveTo` only.** No `PathfindingService`. Grunts walk
  straight at the goal and will get stuck on walls, corners, and gaps.
  `PATH_RECALCULATE_INTERVAL` exists in `Constants.AI` but is currently unused
  (reserved for a throttled `ComputeAsync` pass in a **later** stage — Stage 1B was
  combat feedback FX, not pathfinding). **Partially addressed (2026-09-11) by "AI
  dynamic navigation"** (see that entry below): `PathfindingService` is now used,
  but only for dynamic roaming and Search/investigate goals — every combat
  movement path called out here (Chase/Attack/Cover/bound-and-cover) still walks
  straight at its goal via `Humanoid:MoveTo`, exactly as this entry originally
  described, and can still get stuck on walls/corners/gaps in combat. This
  bullet is left in place rather than marked fully resolved.
- **Shooting is a single burst raycast.** `fireOneShot` casts one ray per shot with
  a random cone (`SHOT_SPREAD_DEGREES`), flat `SHOT_DAMAGE` (region forced to
  `Unknown`, so no AI headshots). No penetration, no projectile travel. A cosmetic
  tracer Beam is drawn per shot (Stage 1B — see below).
- **player-to-AI damage relies on an existing path, not a dedicated hook.** NPCs are
  tagged `Constants.TAG_DAMAGE_ENTITY`, so `GunService.getDamageableEntity` →
  `DamageService:ApplyDamage` already damages them with no `GunService`/`DamageService`
  edit. If that tag contract or `getDamageableEntity` changes, player→AI damage
  silently breaks. AIService only listens for `Humanoid.Died`.
- **AI-to-player damage** goes through `DamageService:ApplyDamage` with `attacker = nil`
  (environment kill: no friendly-fire guard, `"environment"` in the kill feed, no
  killer name). A proper "killed by an NPC" feed entry is deferred.
- **No rewards / points / killstreaks / score.** AI death fires `CombatEvents.EntityKilled`
  (via `DamageService`) but nothing consumes it for scoring; there is a `TODO` marker
  in `onNPCDied` for a future `RewardService`. Ties into the existing
  "Award kills, streaks, or XP → RewardService (future)" gap.
- **No ragdoll on AI death.** `BreakJointsOnDeath = false`; the model is just
  `Destroy()`ed after `DEATH_CLEANUP_DELAY`. `RagdollService` is untouched. Wiring
  `RagdollService:Apply` on `Humanoid.Died` is a later step.
- **Muzzle flash / smoke / light / tracer / 3D sound now exist (Stage 1B — see the
  section below), still no firing animation and no weapon model.** Grunts have no
  `Animator` / animation system; the FX hang off a placeholder attachment on the
  Right Arm / HumanoidRootPart.
- **Blood is a free side effect.** `BloodService` reacts to any
  `CombatEvents.DamageDealt`, so shooting a grunt (or being shot by one) produces a
  blood burst on clients. Not explicitly wired; set `BR_BloodEnabled = false` on an
  NPC model to suppress.
- **No AI types, factions, suppression, flanking, or squad tactics.** One grunt
  archetype, one ring formation, leader only used as the patrol-index advancer.
  Grunts are hostile to every player (no team logic). **Basic per-grunt cover**
  landed in Stage 1D (see that section) — squad-coordinated cover / bounding is
  still absent.
- **Server performance at `MAX_ACTIVE_NPCS` (12) is untested.** One `THINK_INTERVAL`
  (0.25 s) loop over all NPCs plus per-NPC LOS raycasts, detached burst tasks, and
  now (Stage 1B) a per-shot `ParticleEmitter:Emit` × 2 + `Sound:Play` + a temporary
  tracer Part + a `task.delay` light pulse; needs a real Studio/server measurement.
- **All `Constants.AI` / `Constants.AI_COMBAT_FX` numbers are first-pass guesses**
  (ranges, damage, burst timing, speeds, spacing, flash/smoke/light/tracer sizes and
  lifetimes, sound rolloff) and need a Studio tuning pass.
- **Self-running Script, no `Destroy()` caller.** Like the other `*.server.lua`
  services it starts itself at file end and lives for the server session;
  `AIService.Destroy()` exists and is correct but is only reachable from the command
  bar / a future require. Its per-NPC connections and burst threads *are* cleaned on
  death.

## AI Stage 1B — combat feedback FX (Studio verification: REQUIRED, not done)

`Constants.AI_COMBAT_FX` + new helpers in `AIService.server.lua`
(`setupAICombatFx` / `playAIShotFx` / `playAITracer`) give AI shooting visible +
audible feedback: a server-created, **world-replicated** muzzle flash + smoke puff
+ light pulse on an auto-created `AIMuzzleAttachment`, an optional short tracer
`Beam`, and a 3D gunshot `Sound`. Emitters / light / sound are built **once per
NPC** and reused; the tracer creates one temporary holder Part per shot,
`Debris`-cleaned. `fireOneShot` calls `playAIShotFx` after the raycast (hit or
miss) — the hit / damage calculation is unchanged. No remotes, no client code, no
`GunService` / `DamageService` change. Open risks:

- **Not runtime-verified.** `Constants.lua` + `AIService.server.lua` are content
  edits (no `default.project.json` change), so a `rojo serve` restart is not needed,
  but MCP can't drive a player into a grunt's Attack state or watch the FX. Needs a
  Studio Play pass — see the test steps below.
- **AI muzzle position** — since Stage 1C `muzzleParentFor` puts `AIMuzzleAttachment`
  on the welded gun's **`Barrel`** part (falling back to Right Arm / HumanoidRootPart
  if the world model is missing). The `MUZZLE_*_OFFSET` (all 0) and "forward = local
  −Z of the Barrel" are still first guesses; a hand-authored `MuzzleAttachment` on
  the world model's Barrel would be the clean fix.
- **Placeholder asset IDs.** `FLASH_TEXTURE` / `SMOKE_TEXTURE` / `GUNSHOT_SOUND_ID`
  are `rbxassetid://0` — the flash/smoke render as the default particle square and
  the sound does not play (guarded so it never emits a "failed to load" warning).
  `AIService` `Logger.warn`s **once** on first NPC setup. Replace with real
  flash / smoke sprites and a gunshot sound, then tune sizes / lifetimes / rolloff.
- **Flash / smoke have no colour or transparency-curve constants.** They use a flat
  0→1 transparency ramp and the emitter default colour (white). Add
  `*_COLOR` / transparency-keypoint constants to `Constants.AI_COMBAT_FX` when the
  real art goes in.
- **Tracer parts are created per shot, not pooled.** Acceptable at Stage 1B because
  the AI fire rate is capped (`SECONDS_BETWEEN_SHOTS` / `SECONDS_BETWEEN_BURSTS`,
  `MAX_ACTIVE_NPCS`), each holder is `Debris:AddItem`-cleaned after
  `TRACER_LIFETIME` (≈55 ms), and `Destroy()` sweeps any `BR_AITracer` strays +
  destroys `Workspace/AI`. If NPC count or fire rate rises, pool the holder + Beam
  (one reusable rig per shooter, or a small shared ring).
- **AI firing animation + weapon model landed in Stage 1C** (see the section below) —
  grunts now hold the real AKS-74 and play the third-person fire kick per shot.
- **AI gunshot audio needs final sound design + distance tuning.**
  `GUNSHOT_VOLUME` (0.45), `GUNSHOT_ROLLOFF_MIN/MAX_DISTANCE` (12 / 180) and
  `RollOffMode.InverseTapered` are guesses; a real gunshot asset will change the
  perceived loudness and falloff. The single shared `Sound` is `:Play()`-restarted
  each shot (fine for a capped burst rate, but overlapping tails are lost).
- **The light pulse uses `task.delay` per shot.** Token-guarded and Parent-checked,
  so it is safe after NPC death / `Destroy()` and never errors, but it is one
  scheduled callback per shot rather than a pooled timer.
- **`playAIShotFx` reads `muzzleWorldPosition` from the attachment** (falls back to
  the ray origin). It is passed for the tracer + future use; the emitters / light /
  sound are attachment-parented so they ignore it.
- Still **no rewards / points / killstreaks**, **no AI types / advanced tactics**,
  **no AI ragdoll integration** — all unchanged from Stage 1A.

## AI Stage 1C — grunt weapon model + third-person animation (Studio verification: REQUIRED, not done)

New `Constants.AI` Stage 1C fields + `AIService` helpers `attachAIWorldWeapon` /
`setupAIAnimation` / `playAIFireAnim`, plus an `Animator` in `buildRig`. Each grunt
clones `ReplicatedStorage/WorldModels/AKS-74` and welds `Handle` → `Right Arm` via a
`Motor6D`, then loads the `WeaponData` `thirdPerson` equip/idle/fire clips + default
R6 idle/walk on the `Animator`, plays the weapon idle pose, and swaps idle↔walk on
`Humanoid.Running`. `fireOneShot` plays the fire clip per shot. **No new remotes, no
client files, no `default.project.json` / `GunService` / `DamageService` /
`WorldWeaponService` change.** MCP-verified: the world model exists with `Handle` +
`Barrel` BaseParts, `Animator:LoadAnimation` works server-side (even the Roblox
default R6 idle loaded), and the `Motor6D` grip attaches. Open risks:

- **Not runtime-verified in Play.** MCP can't drive a player into a grunt's Attack
  state or watch the pose blend. Needs a Studio Play pass — see the test steps.
- **`WorldWeaponService`'s attach body is now duplicated in `AIService`** (~30
  lines). `WorldWeaponService:EquipWeapon` takes a `Player` and lives in a
  `.server.lua` Script, so it can't be `require`d. Extract a shared
  `WorldWeapon` ModuleScript (`attach(character, weaponName)`) and have both call
  it — the grip CFrames / part names / physics-prop loop must stay in lockstep.
- **Server-side `LoadAnimation` on the game's own `thirdPerson` IDs is unverified**
  in a real session. The Roblox default R6 idle loaded fine via MCP, so game-owned
  clips should too, but each load is `pcall`'d — a failure leaves that track nil,
  `Logger.warn`s once, and the grunt holds the gun in the **raw identity pose**
  (gun through the wrist — ugly but functional). If it looks wrong in Play, that
  is the cause.
- **Animation priorities / fades / walk-speed threshold are first guesses.**
  Weapon idle at `Action`, fire/equip at `Action2`, locomotion at `Idle`/`Movement`,
  `LOCOMOTION_WALK_SPEED_MIN = 0.5`, fades 0.05–0.2 s. If the arms slide off the
  gun while walking, bump the weapon-idle priority; if legs jitter at the
  idle/walk boundary, widen the threshold or add hysteresis.
- **Only one archetype / weapon.** `Constants.AI.WEAPON_NAME` (= the player's
  default viewmodel weapon) drives both the world model and the anims for every
  grunt. Per-squad or per-type weapons need a real loadout concept.
- **Grunts still don't jump or climb** — no anim loaded for it (they never do
  either in Stage 1A). **No reload animation** — deliberate; grunts have infinite
  ammo and never reload.
- **The gun is server-owned and Motor6D-driven.** It replicates and animates
  correctly, but it is not network-owned by anyone (grunts are server-simulated).
  If a future "pick up a dropped AI gun" feature is added, ownership handoff is
  unhandled.
- **`buildRig` now always adds an `Animator`.** Harmless for Stage 1A/1B behaviour,
  but every grunt now carries an Animator + up to 4 `AnimationTrack`s; folded into
  the `MAX_ACTIVE_NPCS` performance question above.

## AI Stage 1D — face target + take cover between bursts (Studio verification: REQUIRED, not done)

New `Constants.AI` Stage 1D fields + `AIService` helpers `faceToward` /
`findCoverPoint`, a `Cover` state, and `Humanoid.AutoRotate = false` in `buildRig`.
Grunts turn to look at the target while engaging, and after each burst
`startBurst` arms `record.coverUntil` so `thinkNPC` moves the grunt to a
raycast-found LOS-breaking spot for `COVER_DURATION` before peeking out to fire
again. `AIService` + `Constants.AI` only — no new remotes / client / project /
`GunService` / `DamageService` change. MCP-checked the math + `AutoRotate`.
Residual risks:

- **Not runtime-verified in Play.** MCP can't drive a player into Attack range or
  watch the peek/shoot/hide loop. Needs a Studio Play pass — see CHANGELOG /
  the test steps.
- **The cover search is dumb.** `findCoverPoint` fires 5 raycasts from the grunt
  outward along `COVER_SAMPLE_ANGLES` and returns the first spot that a ray to the
  target finds occluded — it does **not** check that the spot is reachable or that
  the grunt can path to it. With plain `Humanoid:MoveTo` (no pathfinding) a grunt
  can walk face-first into the wall it is trying to hide behind. On open ground it
  just retreats `COVER_SEEK_DISTANCE` studs (partial cover). Real cover needs
  tagged cover nodes or a navmesh query.
- **No squad coordination.** Each grunt covers independently on its own burst
  timer — they do not cover each other, bound, or stagger. A squad all bursts and
  all ducks at once.
- **`COVER_DURATION` (3 s) vs `SECONDS_BETWEEN_BURSTS` (1.2 s) is a tuning guess.**
  Cover time currently dominates, so the grunt hides ~3 s then peeks. Shorten
  `COVER_DURATION` for more aggressive grunts; it also interacts with
  `DETECTION_RANGE` / `LOSE_TARGET_RANGE` (a grunt that covers too far loses the
  target and drops to Chase).
- **Facing is state-split.** Walking states (Chase / Cover / Patrol) set
  `Humanoid.AutoRotate = true` and face the way they move; only the stationary
  `Attack` state sets `AutoRotate = false` and calls `faceToward` (a per-think
  `HumanoidRootPart.CFrame:Lerp`). The first cut called `faceToward` in every
  branch with AutoRotate off — writing the root CFrame every think while the
  Humanoid was also walking froze the grunts on their spawn stud (fixed here). So
  a grunt only truly points its rifle at the player while planted and shooting;
  while chasing / covering it faces its travel direction, which is roughly at /
  away from the player anyway. If a future branch needs the grunt to aim while
  moving, it needs an `AlignOrientation`, not a CFrame write.
- **`faceToward` still writes `HumanoidRootPart.CFrame`** (only in Attack, where
  the grunt is stationary, so it no longer stops movement). It would still fight a
  knockback / ragdoll impulse landing mid-think — AI ragdoll is not wired, so no
  conflict today.

## AI Stage 1E — fight from cover / react to fire / flank (Studio verification: REQUIRED, not done)

New `Constants.AI` Stage 1E fields + `AIService` helpers `hasNearbyCover` /
`findFightingPosition` / `flankPointFor`, a `Search` state, `fightPoint` /
`flankSide` on the record, and a service-level `CombatEvents.DamageDealt` listener
(a `require`d BindableEvent — **no new remote**). `AIService` + `Constants.AI`
only; `GunService` / `DamageService` / `CombatEvents` / `WorldWeaponService`
unchanged. MCP-checked the math + that `CombatEvents.DamageDealt` is a
BindableEvent. Residual risks:

- **Not runtime-verified in Play.** MCP can't drive a player into range or watch
  the fight-from-cover / flank behaviour — needs a Studio Play pass.
- **`findFightingPosition` is a 20-raycast local sample** (10 angles × 2 radii)
  and returns `nil` on open ground — the grunt then plants where it stopped
  exactly like pre-1E. "Don't stand in the open" is best-effort and entirely
  bounded by nearby geometry. With no pathfinding it can also pick a spot on the
  far side of a wall it can't walk around and get stuck against it.
- **`hasNearbyCover` only proves *something* is within `COVER_ADJACENT_RADIUS`** —
  not that it's tall enough to actually block a shot, nor which side of the grunt
  it's on. A knee-high crate or a thin pole counts.
- **The flank is `flankSide` alternation, not real squad coordination.** Two grunts
  arc from opposite sides by luck of spawn index; 3+ grunts don't fan out, and
  nobody covers anybody. `SEARCH_DURATION` (12 s), `FLANK_OFFSET_DISTANCE` (14),
  `FLANK_CURVE_DISTANCE` (30) are guesses.
- **`DamageDealt` fires once per accepted hit**, so a sustained stream re-arms
  `coverUntil` every shot — a pinned grunt keeps trying to reach a *fresh* hide
  spot (`coverPoint` is nil'd each hit) and barely peeks while under fire.
  Intended as "suppressed", but if it reads as frozen, only nil `coverPoint` when
  the grunt isn't already in `Cover`.
- **A grunt shot from a direction it cannot path to** (through a wall, from above)
  sets that shooter as its target and will walk straight at the obstacle. No LOS
  or reachability check on the attacker before adopting them.
- **`lastSeenPos` now survives the live-target drop.** A grunt that saw you once
  will hunt/flank your last spot for a full `SEARCH_DURATION` even if you're long
  gone — more persistent than before; lower `SEARCH_DURATION` to dial it back.
- Still **no suppression fire, no squad tactics, no AI ragdoll, no rewards** —
  unchanged from earlier stages.

## AI Stage 1F — crouch in cover + weapon-vs-wall retraction (Studio verification: REQUIRED, not done)

New `Constants.AI` Stage 1F fields + `AIService` helpers `setCrouched` /
`updateWeaponCollision` / `pullFromWalls`; `buildRig` returns the Right Shoulder
`Motor6D`; `setupAIAnimation` preloads the player's `CrouchIdle` clip;
`attachAIWorldWeapon` stores the grip `Motor6D`. `AIService` + `Constants.AI` only;
no new remotes, no client files, no `GunService` / `DamageService` /
`MovementController` / `ViewModelController` change. MCP-checked:
`Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed.CrouchIdle` loads server-side, the
additive `Motor6D` C0/C1 offsets apply and restore. Residual risks:

- **Not runtime-verified in Play.** MCP can't watch the crouch pose or the arm
  pull-back — needs a Studio Play pass.
- **The crouch clip is a no-gun full-body pose.** The rifle is welded to the Right
  Arm, so while crouched the gun rides wherever `CrouchIdle` puts the arm — low /
  off to the side, not a rifle-ready crouch. **(2026-09-10: now also used while
  actively firing — see below — so this visual mismatch is more visible than when
  crouching only meant hiding.)** A real crouched-rifle third-person clip (not in
  `WeaponData`) would be better. `EnterCrouch`/`ExitCrouch` transitions are not
  used (they bend the R6 through the floor per the player's own
  `CROUCH_USE_ENTER_TRANSITION_ANIMATION` note) — the crossfade is a plain
  `Play(fade)`/`Stop(fade)`.
- **Crouch now gates on arrival, and Attack crouches at real cover (2026-09-10,
  fixing user-reported "gets shot, instantly crouches and waddles to cover").**
  Both the `Cover` branch and the `Attack` planted branch now crouch only once
  `(root.Position - spot).Magnitude <= FIGHT_ARRIVE_DIST` — while still moving to
  either spot the grunt stands (runs) there, then crouches on arrival. `Attack`
  crouches (and fires from the crouch — nothing gates `startBurst` on pose) only
  when planted at real cover (`findFightingPosition` returned a spot); with no
  cover nearby it stands in the open, same as before. Reuses `FIGHT_ARRIVE_DIST`
  for the Cover-arrival check too (was previously unused there) rather than adding
  a parallel constant. Not runtime-verified — the fix is structurally sound
  (mirrors the pre-existing Attack `spot ~= nil` moving/planted split) but the
  actual look (does the crouch-fire pose read OK, does the stand→crouch snap feel
  abrupt without a transition anim) needs a Studio Play pass.
- **Covering fire while retreating to cover (2026-09-10, user-reported: "they
  don't shoot back while running to cover, they should go to cover while facing
  the player and shooting back").** The `Cover` branch's not-yet-arrived path is
  now a bounding-overwatch loop: walk toward the hide spot (`AutoRotate = true`,
  no facing writes — safe, matches every other walking state) until
  `record.nextCoverShotClock` elapses, then stop (`AutoRotate = false`,
  `MoveTo(root.Position)`, `faceToward`) and fire a burst via the same
  `startBurst` the `Attack` state uses, then resume walking once the burst (and
  its post-burst cooldown) ends. `startBurst`'s internal loop had to be relaxed
  from `record.state ~= "Attack"` to `record.state ~= "Attack" and ~= "Cover"` so
  it doesn't immediately self-abort when called from `Cover`. Deliberately never
  combines `faceToward` (a root CFrame write) with an active `MoveTo` in the same
  think — that exact combination is what froze grunts in place in the original
  Stage 1D bug, so this reuses the already-proven-safe "stop completely, THEN
  face+fire" pattern from `Attack` rather than trying to face the player while
  actually walking. Flag-gated `Constants.AI.COVER_RETREAT_FIRE`, cadence
  `COVER_RETREAT_SHOT_MIN/MAX`. Once actually arrived at the hide spot, behavior
  is unchanged (goes fully quiet for the rest of the window). Not runtime-verified
  — the state-machine logic was checked in isolation, not the in-game feel or
  timing. Residual risks:
  - **Not squad-attacker-slot-limited.** `updateSquadAttackSlots`
    (`Constants.AI_COMBAT_TUNING.MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD`) only
    counts grunts in `Attack`; a retreating grunt's covering-fire burst doesn't
    consume/respect a slot, so it's possible for more grunts to be shooting at
    once than the squad cap intends if some are retreating while others are
    fighting. Judged acceptable for a first pass — squads are small (≤4) and
    retreat bursts are short and infrequent — but worth revisiting if it feels
    like too much simultaneous fire.
  - **No reaction-time gate on the retreat burst** (`record.reactionReadyAt` is
    only checked in `Attack`) — intentional, since retreat-fire is always against
    an already-engaged target (reaction time modeled the beat before the FIRST
    shot on a new target, which already happened earlier), but means a covering
    burst can start the instant `nextCoverShotClock` elapses with no extra beat.
  - **The grunt only faces the player while STOPPED to fire**, never while
    actually walking (backpedaling-while-aiming is not attempted — that needs an
    upper-body aim-twist system independent of `Humanoid:MoveTo`, out of scope
    here and a nontrivial addition). The visual is "walk, plant, burst, walk
    again," not a continuous fighting-withdrawal strafe.
  - **`coverUntil` re-arms on every retreat burst** (`startBurst`'s existing
    end-of-burst line), which can extend how long a grunt keeps bounding toward
    cover if the player keeps giving it LOS — bounded in practice because arrival
    is purely positional (checked every think regardless of the timer), so the
    grunt still reaches the hide spot on schedule; it just may fire 1-2 more
    covering bursts than a fixed-duration design would along the way.
- **`updateWeaponCollision` is one forward chest-ray.** A wall to the *side* of the
  muzzle still clips; the ray also can't see players/other grunts (`losParams`
  excludes the AI folder), only map geometry. The C1 `+Z` / shoulder tuck signs
  and the `0.25` / `0.6` mix factors are un-eyeballed — if the gun pushes *forward*
  or the elbow *drops* near a wall, flip the signs in the helper.
- **Retraction runs at the 0.25 s think rate**, lerped by `GUN_RETRACT_ALPHA` so it
  eases rather than snapping, but it is not a per-frame follow — a grunt that
  rushes a wall will clip for a couple of thinks before the arm catches up.
- **`pullFromWalls` has no pathfinding.** A position pulled back off a wall can
  land somewhere the grunt can't actually walk to; and it only pushes straight
  back along the away-from-target axis, so it can shove the grunt into a *different*
  wall behind it.
- **No `HipHeight` change** (matches the player) — on steep/uneven ground the
  crouch clip can look like it floats.

### AI Stage 1F.1 — hide on the far side of cover (Studio verification: REQUIRED, not done)

`findCoverPoint` now scores occluded candidates by how near the blocking obstacle
is (`Constants.AI.COVER_HUG_DISTANCE`) and picks the nearest, so the grunt tucks
against the far face of that obstacle; the `Cover` branch re-picks when the player
flanks around and regains LOS. Risks:

- **Still per-grunt, still heuristic.** The "obstacle within `COVER_HUG_DISTANCE`"
  test is a single ray from the candidate to the player — a candidate beside a
  pillar that the player can walk around in a second still counts. No notion of
  which cover the squad is already using.
- **Re-pick can thrash.** If every sampled candidate is exposed (open ground) the
  grunt recomputes `findCoverPoint` every think while parked, issuing a new
  `MoveTo` each time — it will jitter in place rather than commit. Bounded only by
  `COVER_DURATION`.
- **`COVER_SAMPLE_ANGLES` is now 12 rays × (cover + fight) per think per grunt.**
  Cheap at the Stage-1 NPC cap but not free; revisit if the cap rises.
- **Wall-clip risks from the base 1F block still apply** (side walls, un-eyeballed
  C0/C1 signs, no pathfinding on the pulled-back spot).

## AI squad spacing / anti-bunching (Studio verification: REQUIRED, not done)

New `Constants.AI_SQUAD_SPACING` + `AIService` helpers `assignFormationSlots` /
`ensureFormationAssigned` / `formationDirectionForSlot` / `squadSpreadGoal` /
`getSeparationAdjustedGoal` / `issueSquadMoveGoal`, wired into Patrol/Idle,
Chase, fresh Search, Attack-transit, and Cover-retreat. `AIService` +
`Constants.AI_SQUAD_SPACING` only — no new remotes, no client files,
`GunService`/`DamageService` untouched; spawning, chase/attack, combat FX,
damage integration, and death cleanup all preserved (only the `MoveTo`
destinations themselves changed). MCP-checked formation-slot assignment
(leader promotion on death, slot numbering, empty-squad clearing), the
separation-push math, and the recalculate-throttle's anchor-vs-jitter
distinction, all in isolation with throwaway logic (not a live `AIService`
require — that pattern has previously timed out in this environment).
Residual risks:

- **Not runtime-verified in Play.** None of "does it actually look like a loose
  squad" has been observed — only the underlying math was checked.
- **Formation is simple offset-based, not real tactical movement.** Slots are
  fixed compass-ish directions off an anchor point scaled by a spread radius —
  no facing/heading rotation of the formation shape, no "flank left because
  there's a wall on the right," no coordination between squads.
- **No true obstacle-aware formation.** `squadSpreadGoal` and
  `getSeparationAdjustedGoal` are pure vector math against other squadmates'
  positions — a formation slot or a separation push can land a grunt inside a
  wall, off a ledge, or somewhere `Humanoid:MoveTo` simply can't path to. No
  raycast/walkability check on the adjusted goal (unlike `findCoverPoint`
  /`findFightingPosition`, which do raycast). `issueSquadMoveGoal`'s
  radius-0 call sites (Attack/Cover/Search-flank) are lower risk since the
  underlying goal there already came from a raycast-validated helper and
  separation only nudges it a few studs.
- **No pathfinding rewrite** (still plain `Humanoid:MoveTo`) — explicitly out
  of scope for this task, so a spread-out squadmate can still get stuck on
  geometry exactly like before.
- **Squad "anchor" isn't a single materialized value.** The task asked for
  "leader position if alive, else average of living members" — this
  implementation only ever uses the LEADER's live position (via slot 1's own
  goal, which is `anchor + 0` since `LEADER_SLOT_OFFSET` is zero) as the
  effective anchor for the *leader itself*, and each OTHER member's goal is
  `troot.Position` (the actual player, not a "squad anchor") + formation
  offset — so in the Chase/Search/Patrol cases the "anchor" is always the
  live target or patrol point, not the squad's own center of mass. The
  "average of living members" fallback (for a dead/missing leader) is not
  implemented as a distinct code path — dead leaders are handled by
  *promoting* a new leader (`assignFormationSlots`) rather than computing a
  centroid, which achieves the same practical goal (a stable slot-1 anchor
  member) more simply, but is a deliberate deviation from the literal spec
  wording. Documented here rather than silently diverging.
- **Spacing values are first guesses**, unplaytested — `MIN_PERSONAL_SPACE`,
  `SEPARATION_PUSH_DISTANCE`, the three spread radii, and `MOVE_GOAL_JITTER`
  all as specified verbatim.
- **`PREFERRED_PERSONAL_SPACE` and `FORMATION_SLOT_REACHED_DISTANCE` are
  unused.** Both are required Constants per the task spec but nothing in this
  pass reads them — `PREFERRED_PERSONAL_SPACE` documents an intended resting
  distance that `getSeparationAdjustedGoal`'s single push-on-violation model
  doesn't need a separate constant for, and `FORMATION_SLOT_REACHED_DISTANCE`
  is reserved for a future "has this grunt actually reached its formation
  slot" check that nothing currently asks. Left in `Constants.lua` (not
  removed) since the constant block was requested verbatim.
- **Replaces, rather than layers onto, the Stage 1A static per-grunt ring
  offset** (`record.slot`) for Chase/Search-fresh/Patrol/Idle — running both a
  fixed spawn-time offset and a dynamic reassigned one for the same "spread
  squadmates around a shared goal" purpose would be redundant, so
  `record.slot` is now only read as the disabled/no-squad fallback inside
  `squadSpreadGoal`. Same consolidation pattern as the Stage 1C-vs-1H
  reaction-delay merge earlier this session.
- **`COMBAT_SPREAD_RADIUS` fallback changes `Attack` behavior when no cover is
  found**: previously a grunt with no cover nearby just held wherever
  `ATTACK_RANGE` was reached; now (when `SPACING.ENABLED`) it walks to a
  formation-spread point around the target instead. The crouch decision at the
  plant point was updated to re-check `hasNearbyCover` live (rather than just
  "a fight point exists") specifically because this fallback point has no
  cover guarantee — worth confirming in Play that this doesn't make grunts
  wander more than intended when genuinely no cover exists nearby.

## AI squad fire discipline (Studio verification: REQUIRED, not done)

**Consolidation note:** this task asked for a `Constants.AI_FIRE_DISCIPLINE`
table and a `local function updateSquadAttackSlots(squadRecord, now)` helper —
both already existed (as `Constants.AI_COMBAT_TUNING` fields and an
`AIService.updateSquadAttackSlots`) from the earlier "fair combat tuning"
pass, with the same values for `MAX_ACTIVE_SHOOTERS_PER_SQUAD` /
`MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD` (2) and the recheck interval (0.5s).
Rather than run two "who gets to shoot" gates side by side, the existing
mechanism was **rewritten in place**: `SquadRecord.attackerSlots` /
`nextAttackSlotRecheck` renamed to this task's required
`activeShooterIds` / `lastAttackSlotUpdateAt`; `updateSquadAttackSlots` gained
the required `assert`s and now reads `Constants.AI_FIRE_DISCIPLINE` as
authoritative. `Constants.AI_COMBAT_TUNING.MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD`
/ `ATTACK_SLOT_RECHECK_INTERVAL` are left in `Constants.lua` (not removed —
neither task said to remove existing values) but are now unread. Same pattern
as the Stage 1C-vs-1H reaction-delay merge and the squad-spacing
`record.slot` supersession earlier this session — three consolidations in one
file's history now; worth a dedicated cleanup pass eventually to delete the
genuinely dead constants once nobody's relying on their presence.

New `attackSlotEligible` / `canNpcUseAttackSlot` / `releaseAttackSlot`
helpers, new `NPCRecord` fields (`hasAttackSlot`, `attackSlotAssignedAt`,
`lastSupportRepositionAt`). `AIService` + `Constants.AI_FIRE_DISCIPLINE` only
— no new remotes, no client files, `GunService`/`DamageService` untouched,
`DamageService` integration and active-shooter burst timing unchanged. MCP-
checked slot assignment, the eligibility drop / timeout logic, and the
non-shooter support-distance random selection with throwaway logic (not a
live `AIService` require). Residual risks:

- **Not runtime-verified in Play.** Whether the pressure actually reads as
  "dangerous but fair" — the core design goal — has not been observed.
- **Found and fixed a real bug during the isolated logic check:**
  `SquadRecord.lastAttackSlotUpdateAt` initialized to `0`, and
  `updateSquadAttackSlots`'s guard is `now - last < RECHECK_INTERVAL → skip`.
  Since a fresh Roblox server's `os.clock()` starts near 0 too, a squad's
  very first attack-slot pass could — in principle, if a grunt reached the
  Attack-planted branch in the first ~0.5s of server life — skip assigning
  any shooter at all. Fixed by initializing to `-math.huge` (matching the
  pattern already used for other "must always fire on the first check"
  fields in this file, e.g. `lastDamageCallAt`). In practice this window is
  extremely unlikely to matter (spawning + walking into range takes longer
  than 0.5s), but it was a real latent bug, not just theoretical — worth
  double-checking similar `= 0`-initialized throttle fields elsewhere if any
  more get added.
- **Active shooter selection is simple: eligibility + squad member iteration
  order, no ranking.** "Prefer bots with clear LOS and good position" is
  satisfied only in the sense that LOS is a hard eligibility requirement —
  there's no scoring for "best" position among several eligible candidates
  (closest, best angle, etc.); whichever eligible member is encountered first
  in `squad.members` order fills a vacancy.
- **Non-shooter support positions are rough vector math, not tactical.**
  `troot.Position + formationDirectionForSlot(...) * randomDistance` — no
  raycast/walkability check (same caveat as squad spacing's goals), no
  concept of "behind cover while supporting," no coordination with what the
  active shooters are doing. A non-shooter can end up standing somewhere
  awkward, in the open, or even closer to the player than a shooter.
- **No true suppression/flanking roles yet.** Non-shooters are functionally
  identical to each other (reposition or hold, chosen randomly per cycle) —
  no dedicated "flanker," "suppressor," or "spotter" behavior. Explicitly out
  of scope for this task ("no advanced flanking").
- **`ATTACK_SLOT_TIMEOUT` is untested for feel.** A slot force-releasing at
  2.5s even from an actively-firing, still-fully-eligible shooter could cause
  a visible mid-burst-adjacent handoff; `startBurst`'s own burst+cooldown
  cycle is usually longer than 2.5s (`SECONDS_BETWEEN_BURSTS` plus a
  multi-shot burst), so this may fire mid-engagement more often than intended
  — worth watching in Play and lengthening `ATTACK_SLOT_TIMEOUT` if slot
  handoffs look twitchy.
- **No difficulty presets** — `Constants.AI_FIRE_DISCIPLINE.ENABLED = false`
  is the only on/off switch (reverts every grunt to the pre-fire-discipline,
  no-slot-limit behavior); there's no "easy/normal/hard" tuning surface.

## AI squad awareness / last-known-position memory (Studio verification: REQUIRED, not done)

**Consolidation note:** two of the four `NPCRecord` fields this task asked for
— `lastSawTargetAt` and `lastKnownTargetPosition` — already existed under
those exact names from the earlier "fair combat tuning" pass; reused as-is,
not duplicated. The squad-level "one bot's sighting alerts the squad" concept
also already existed as a sticky `squad.alerted` boolean from that same pass
(used only for reaction-tier selection); **superseded in place** by the new
time-bounded `squad.alertUntil` — `armReaction` now checks `now < alertUntil`
instead of the old boolean, so a squad's "Alert" reaction tier actually
expires. `alerted` is left declared (not removed — no task said to), now
unread. Same consolidation pattern as three earlier passes this session
(Stage 1C-vs-1H reaction delay, squad-spacing's `record.slot`, fire
discipline's attack-slot rename) — running a fourth parallel "is this squad
alert" flag alongside `alertUntil` would have been actively confusing, not a
neutral addition.

New `shareSquadAlert` / `clearStaleSquadAlert` helpers, new `NPCRecord` fields
`isAlertedBySquad` / `investigateGoal`, new `SquadRecord` fields `alertUntil`
/ `lastKnownTargetPosition` / `lastKnownTargetPlayer` / `lastKnownUpdateAt` /
`lastContactAt`. `AIService` + `Constants.AI_SQUAD_AWARENESS` only — no new
remotes, no client files, `GunService`/`DamageService` untouched, spawning /
spacing / fire discipline / chase / attack / combat FX / damage / death
cleanup all preserved. MCP-checked the share/throttle/broadcast logic (radius
gating, share-interval throttle), the alert-clear pre-filter and timing, the
`armReaction` tier switch, and the investigate-goal recompute conditions
(nil / arrived / stale-interval) with throwaway logic (not a live `AIService`
require — that pattern has previously timed out in this environment).
Residual risks:

- **Not runtime-verified in Play.** Whether shared alerting and investigate
  behavior actually reads as "believable" — the core design goal — has not
  been observed.
- **`LOSE_TARGET_GRACE_TIME` and `INVESTIGATE_ARRIVE_DISTANCE`'s exact roles
  were not fully specified** by the task and are this file's interpretation:
  `LOSE_TARGET_GRACE_TIME` gates how long after THIS grunt's own contact
  lapses before it starts relying on squad-shared data instead of its own
  memory (rather than, say, a general "flicker" debounce on LOS itself, which
  risked touching the already-tuned Stage 1D/1E Attack↔Chase transition);
  `INVESTIGATE_ARRIVE_DISTANCE` was wired to make an investigating grunt pick
  a *different* nearby offset once it arrives and finds nothing, rather than
  idling at the first spot forever. Both are defensible readings, not the
  only possible ones — flag if the feel is off.
- **Awareness is simple squad memory, not full sensory simulation.** No
  hearing (a grunt does not react to unheard/unseen gunfire — the only
  "alert without seeing" path is being hit directly, per spec point 3), no
  line-of-sound occlusion, no smell/vibration, no distinction between a
  suppressed vs. loud weapon.
- **No gunshot-sound investigation system.** A miss that doesn't hit a grunt
  produces no awareness signal at all — only a direct hit or a personal
  sighting shares anything with the squad.
- **No radio/callout UI or audio.** The "share alert" moment is silent and
  invisible to the player — no bark, no radio chatter, no on-screen tell that
  a squad has gone alert. Would be a good place for one later
  (`shareSquadAlert`'s `isNewAlert` branch is exactly the hook point).
- **No stealth system.** There's no player crouch-noise/visibility model this
  plugs into — `findVisibleTarget`'s raycast LOS is the only detection input
  that exists, unchanged by this task.
- **Investigate goals have no obstacle/walkability check** — same caveat as
  squad spacing's goals: a random offset near the shared position can land
  somewhere the grunt can't actually path to (`Humanoid:MoveTo` will just
  fail quietly). **Improved (2026-09-11) by "AI dynamic navigation":** the
  investigate goal now routes through `PathfindingService` (`followNavGoal`)
  instead of a bare `MoveTo`, so it can path *around* obstacles, and an
  unreachable offset now gets abandoned for a fresh one on the next think
  (a stuck signal) instead of silently failing forever — but the offset
  itself is still an unvalidated random point, so a goal that lands somewhere
  genuinely unreachable (not just obstructed) is still possible; it now just
  recovers instead of getting stuck on it.
- **Radius-gated sharing uses a flat distance, not LOS or hearing range** —
  `ALERT_SHARE_RADIUS` is a straight-line distance check between the alerting
  grunt and each squadmate, so a squadmate on the other side of a thin wall
  85 studs away is alerted exactly as readily as one in open ground the same
  distance — no occlusion test. Kept simple deliberately ("not full sensory
  simulation" per the task's own design goal), but worth revisiting if it
  feels like squads communicate through solid geometry too easily.
- **Three overlapping timers** (`LAST_KNOWN_POSITION_MEMORY` 4s <
  `ALERT_MEMORY_DURATION` 6s < `CLEAR_ALERT_AFTER_NO_CONTACT` 7s) govern,
  respectively: how long the shared position stays walkable-toward, how long
  the squad keeps the fast reaction tier, and how long until the squad fully
  stands down. Deliberately layered rather than merged into one constant, but
  the three values are unplaytested together and could feel disjointed (e.g.
  a squadmate still shown as "alert" for reaction purposes 2 extra seconds
  after it's stopped actually investigating anywhere).

## AI squad bound-and-cover movement (Studio verification: REQUIRED, not done)

**Scope note up front:** this is a deliberately **simplified, game-friendly**
pass — "one bot advances while others hold, then they swap" — not a real
fire-and-maneuver doctrine simulation, not a cover-node system, no flanking
routes, no breaching, no grenades, no voice callouts. That's an explicit
design goal from the task, not a shortcut taken against it.

New `Constants.AI_BOUNDING` table + `AIService` helpers `releaseBoundRole` /
`clearSquadBounding` / `boundDestinationFor` / `updateSquadBounding`, new
`NPCRecord` fields `tacticalRole` (`"Mover" | "Cover" | "Shooter" | "Support" |
nil`) / `boundDestination`, new `SquadRecord` fields `currentMoverNpcId` /
`coveringNpcIds` / `currentBoundStartedAt` / `lastBoundEvaluateAt`. Layers on
top of, and reads from, three earlier systems this same session built:
squad-spacing's `formationDirectionForSlot` (lateral offset for the bound
destination), fire discipline's slot/LOS gate (bounding only ever
*restricts* who's allowed to fire further, never grants a shot fire
discipline wouldn't already), and squad awareness's shared `alertUntil` /
`lastKnownTargetPosition` (the "is the squad alert with a known target"
precondition for bounding at all). `AIService` + `Constants.AI_BOUNDING`
only — no new remotes, no client files, `GunService`/`DamageService`
untouched, spawning / spacing / fire discipline / awareness / cover /
combat FX / damage / death cleanup all preserved. MCP-checked (throwaway
logic, not a live `AIService` require) the bound-destination math
(advance/clamp toward target, never landing inside
`DO_NOT_BOUND_WITHIN_ATTACK_RANGE`), farthest-from-target mover selection,
the arrival/timeout swap conditions, the `MIN_COVERING_BOTS_REQUIRED` /
`DO_NOT_BOUND_WITHIN_ATTACK_RANGE` bounding-eligibility gate, and the
`-math.huge` reevaluation-throttle init (same bug class caught twice already
this session in `lastAttackSlotUpdateAt` / `lastKnownUpdateAt`). Residual
risks:

- **Not runtime-verified in Play.** Whether a squad advancing this way
  actually reads as "one bot moves while others cover, then they swap" — the
  core design goal — has not been observed. The distance/timing constants
  (`MOVE_BOUND_DISTANCE_MIN/MAX`, `BOUND_ARRIVE_DISTANCE`,
  `SWAP_AFTER_MAX_TIME`, `BOUND_REEVALUATE_INTERVAL`) are first guesses and
  will likely need tuning after an actual playtest.
- **No real cover-node system.** The Mover's `boundDestination` is a raw
  point offset toward the target plus a formation-slot lateral nudge — it is
  not validated against actual geometry, does not check walkability, and
  does not prefer an actual wall/obstacle the way `findCoverPoint` /
  `findFightingPosition` do for the Cover/Attack states. A bound can plan a
  destination in the open, against a wall, or somewhere the grunt can't
  path to (`Humanoid:MoveTo` then just quietly fails, same caveat as every
  other computed-goal system this session).
- **Cover role doesn't call `findCoverPoint`/`findFightingPosition` while
  holding in `Chase`.** Per the task's own "keep it simple" instruction, a
  covering bot in the `Chase` state just holds its current ground
  (`MoveTo(root.Position)`) rather than actively repositioning to nearby
  literal cover — it only gets real cover-seeking once it's close enough to
  transition into the existing `Attack` state (`findFightingPosition`) or
  gets shot at (`Cover` state, `findCoverPoint`). A covering bot caught in
  the open while holding is therefore still exposed, same as it always was
  outside of Attack/Cover — bounding does not make it safer, only stops it
  from *also* running forward.
- **`MAX_MOVERS_PER_SQUAD` only supports the literal value `1` from this
  task's spec.** `SquadRecord.currentMoverNpcId` is a single field, not a
  list — setting the constant higher than `1` would have no effect (the code
  never reads it as a count). Documented here rather than silently ignored;
  generalizing to N movers would need `currentMoverNpcId` turned into a set
  and touches `updateSquadBounding`'s mover-picking loop, `releaseBoundRole`,
  and every branch that checks `record.tacticalRole == "Mover"`.
- **`COVER_HOLD_TIME_MIN`/`MAX` are declared but not read anywhere.** The
  task's Constants block includes them (reserved for a future randomized
  "how long does a covering bot hold before also considering advancing"
  timer); this pass never needed that decision — a covering bot's role only
  changes when `updateSquadBounding` reassigns Mover/Cover on its own
  `BOUND_REEVALUATE_INTERVAL` cadence, or when fire-discipline/LOS
  reassigns `tacticalRole` between `Cover`/`Shooter`/`Support`. Left as
  literal dead config rather than wiring speculative behavior for it.
- **Mover-selection is "farthest from target," not doctrine-aware.** It does
  not consider ammo, health, formation slot role (e.g. the leader could get
  picked as Mover), or whether the farthest bot has a remotely safe path —
  purely a distance heuristic chosen to keep the pass simple and to
  naturally alternate who advances (the previous mover, now nearer, is
  unlikely to be picked again immediately).
- **Bound-and-cover only integrates with `Chase` and the `Attack`-planted
  branch — not `Cover`, `Search`, or the squad-shared-investigate path.** A
  bot retreating to cover after taking fire, searching a stale last-known
  position, or investigating a squadmate's shared sighting ignores its
  `tacticalRole` entirely for movement purposes (though the shoot-gates
  still apply anywhere `startBurst` is reachable). This was a deliberate
  scope decision — the task asked for "basic bound-and-cover movement," and
  Chase (the "several squad members are running straight at the player"
  case the task specifically called out) plus Attack (where the shoot-gates
  matter) cover the actual complaint; extending role-awareness into every
  other state risked a much larger, riskier change for a "keep it simple"
  task.
- **`ATTACK_RANGE` (90 studs) is far larger than
  `DO_NOT_BOUND_WITHIN_ATTACK_RANGE` (18 studs)**, so a squad is very
  commonly already in the `Attack`-planted branch (in range + LOS) while
  still bounding. Handled via a dedicated bound-override branch checked
  *before* the normal Attack-range decision (a Mover keeps closing on its
  `boundDestination` even though it technically qualifies for `Attack`) plus
  shoot-suppression inside the Attack-planted branch itself as a safety net
  for the brief window before a role updates — but this means "Attack" state
  and "currently bounding" now overlap for a meaningful chunk of typical
  engagement range, which adds a small amount of branch complexity future
  readers should be aware of.
- **No animation/callout polish.** A Mover advancing and a Cover bot holding
  look identical to their existing Chase/Attack poses — no distinct "moving
  up" or "covering" animation, stance, or barked line.

## AI dynamic navigation (Studio verification: REQUIRED, not done)

**Scope note up front:** this is explicitly a **navigation foundation**, not a
finished big-map AI system — dynamic roaming, search, and investigate on
sampled ground points, plus throttled `PathfindingService` support. No
designer-authored AI zones, no navmesh editor tooling, no doors/ladders/
vaulting/climbing, no strategic map-level planner, no vehicle navigation. All
per the task's own stated boundaries.

New `Constants.AI_NAVIGATION` table + `AIService` helpers
`sampleReachableGroundNear` / `computePath` / `followNavGoal` / `dynamicRoam`,
new `NPCRecord` path-following fields (`currentPath`, `currentWaypointIndex`,
`currentNavigationGoal`, `lastPathRecalculateAt`, `lastStuckCheckAt`,
`lastStuckCheckPosition`, `stuckSince`) and roam fields (`roamGoal`,
`roamCooldownUntil`). `collectParts` gained an `optional: boolean?` parameter
so a missing/empty `Workspace/AIPatrolPoints` logs a `Logger.debug` "this is
fine" note instead of `Logger.warn` — `AISpawns` is unchanged and still warns,
it remains required. `AIService` + `Constants.AI_NAVIGATION` only — no new
remotes, no client files, `GunService`/`DamageService` untouched, spawning /
spacing / fire discipline / awareness / bounding / cover / combat FX / damage /
death cleanup all preserved. MCP-checked (throwaway logic against a live
Server datamodel, not a live `AIService` require) the ground-sampling
radius-band math, the slope-rejection threshold, stuck-detection timing
(wedged-in-place vs. steadily-moving sequences), waypoint catch-up/advance
logic, the goal-change path-invalidation threshold, the `-math.huge`
recalculate-throttle init (same bug class caught 3× already this session —
`lastAttackSlotUpdateAt` / `lastKnownUpdateAt` / `lastBoundEvaluateAt`), and a
real `PathfindingService:CreatePath`/`ComputeAsync` call with this task's exact
agent parameters, which completed without error. One throwaway-test authoring
mistake was caught and corrected during that check (a waypoint-advance test
seeded an unrealistic starting index — the real `currentWaypointIndex` only
ever advances forward as a grunt actually walks a path in order, so "already
near the final waypoint" can't realistically start back at waypoint 1); noted
here for transparency, not because it changed any shipped logic. Studio's Edit
datamodel was unavailable during this check (a Play session was already
running in the target Studio instance), so verification ran against the
Server datamodel instead of the usual pre-Play Edit pass — not a substitute
for the Studio test steps below. Residual risks:

- **Not runtime-verified in Play.** Whether roaming/searching actually reads
  as "natural" on a real large map, whether `PathfindingService` costs are
  acceptable with several squads active at once, and whether the stuck
  threshold (`PATH_STUCK_TIME` = 2s) is well-tuned for real geometry have not
  been observed.
- **`PathfindingService` can be expensive and needs stress testing.** Each
  `computePath` call is a real navmesh query; it's throttled to
  `PATH_RECALCULATE_INTERVAL` (1.5s) per NPC and only triggered when a path is
  missing, exhausted, or the grunt is stuck — but there is no cross-NPC
  scheduling to spread simultaneous compute calls across different think
  ticks (spec point 8, "do not compute many paths for all NPCs in the same
  frame if easy to avoid," was not implemented — every NPC's own
  `AI.THINK_INTERVAL` stagger is the only spreading effect, and it's
  incidental, not designed for this). With `MAX_ACTIVE_NPCS` bots all newly
  alerted/roaming at once, a burst of simultaneous `ComputeAsync` calls is
  possible and unmeasured.
- **Dynamic roaming is simple and may choose weird destinations.**
  `sampleReachableGroundNear` is a blind angle+radius raycast sample — it has
  no concept of "interesting" locations, rooms, cover, or the shape of the
  map beyond "is there walkable, non-steep, collidable ground here." A roam
  goal can land in a random open field, a tiny ledge, or technically-valid
  ground that reads as a strange place for a patrol to wander to. There is no
  concept of a "patrol route shape" the way authored `AIPatrolPoints` gives —
  dynamic roam is uncoordinated per-grunt wandering near the anchor, not a
  designed circuit.
- **No designer-authored AI zones yet.** Nothing here lets a level designer
  mark "patrol this room, not that one," bias roam sampling toward specific
  areas, or exclude regions (a hazard, an out-of-bounds zone, a room that
  should stay empty) from ground sampling. `RANDOM_ROAM_RADIUS_MIN/MAX` is a
  single flat radius band around one anchor point per squad.
- **No strategic map-level AI planner.** Each grunt/squad reasons only about
  its own immediate roam/search goal — there is no shared understanding of
  the map's layout, no squad-to-squad coordination beyond what already
  existed (spacing/fire-discipline/awareness/bounding), and no notion of
  "cover this objective" or "hold this lane."
- **No doors/ladders/vaulting/climbing.** `AGENT_CAN_CLIMB` is `false` and
  nothing opens a door — a roam/search goal on the far side of a closed door
  or behind a ladder-only gap will fail to path (falls back to a direct
  `MoveTo`, which will then just walk into the obstacle) or `computePath`
  will return `nil` for that goal, discarded on the next pick.
- **Ground sampling can be fooled by thin or layered geometry.** The
  validation raycast is a single downward cast from directly above the
  candidate XZ point — a thin overhang, a bridge over a pit, or stacked
  floors can validate a point that isn't actually the intended walkable
  surface (e.g. sampling lands on a rooftop instead of the street below it,
  or a walkway over water). `MAX_GROUND_SLOPE_NORMAL_Y` filters slope, not
  which of several stacked hits is "the right one" — `workspace:Raycast`
  returns the nearest hit along the ray, which is usually correct but not
  guaranteed to be the intended floor on a vertically complex map.
- **Stuck detection retries the same path/goal; `dynamicRoam` is the only
  caller that reacts by picking a genuinely different destination.** The
  squad-shared investigate branch also drops its goal on a stuck signal (a
  fresh nearby offset is picked next think), but the personal stale-last-seen
  Search branch (`flankPointFor`) does not check `followNavGoal`'s stuck
  return at all — a flank point behind unreachable geometry can keep
  retrying via `issueSquadMoveGoal`'s own throttle without ever being
  abandoned for a different point. Left this way because `flankPointFor`'s
  arc-converging behavior already has its own SEARCH_DURATION expiry
  (Stage 1E) that eventually drops the grunt back to Patrol/Idle regardless,
  so a wedged flank point self-resolves, just not as quickly as it could.
- **Scope boundary: pathfinding applies to roam + Search/investigate only,
  not to any combat movement.** Chase-toward-a-visible-target, the Attack
  fighting-spot transit, the Cover retreat, and bound-and-cover's Mover
  advance all keep their pre-existing direct `Humanoid:MoveTo`, unchanged —
  a deliberate interpretation of "navigation foundation" to avoid touching
  already-tuned close-combat responsiveness/latency in the same pass that
  adds a new, unverified system. This means combat movement still won't path
  around obstacles on a large map — only roam/search/investigate do. Flagged
  as a scope decision, not an oversight, but worth revisiting once this
  foundation is Play-verified and trusted.
- **`SEARCH_RADIUS_MIN/MAX` supersedes `AI_SQUAD_AWARENESS.INVESTIGATE_DISTANCE_MIN/MAX`
  in place**, same consolidation pattern used four times already this
  session (Stage 1C-vs-1H reaction delay, squad-spacing's `record.slot`,
  fire discipline's attack-slot rename, squad awareness's `alerted` flag) —
  the awareness pass's own fields are left declared, now unread, rather than
  running two parallel "how far to offset the investigate goal" knobs.
- **No per-NPC path-compute scheduling/stagger.** See the `PathfindingService`
  cost note above — this is the most likely source of a real hitch under
  load and the top candidate for the "stress testing" the task asked to flag.
- **`currentPath` holds a cached waypoint LIST, not a live `Path` instance** —
  a minor, deliberate deviation from the task's literal field-name
  implication (`currentPath: Path?`) for practicality: re-deriving an index
  into a live `Path` object every think is awkward compared to holding the
  already-fetched `{ PathWaypoint }` array. Typed and commented at the
  declaration site; functionally equivalent for this task's purposes.
- **No `Path.Blocked` event subscription.** Waypoint blockage is caught by the
  existing polling stuck-check on its own cadence (`PATH_STUCK_CHECK_INTERVAL`),
  not instantly via an event listener — simpler (no per-NPC connection to
  store/disconnect) at the cost of reacting a beat slower than an event-driven
  version would. Nothing to disconnect currently exists because nothing
  subscribes; flagged here since the task's cleanup section anticipated one.

## AI arena / factions (Studio verification: REQUIRED, not done)

**Scope note up front:** this is the largest AI-targeting-core change this
session — it widens `NPCRecord.target`'s type (`Player?` → `Player | Model`)
and touches `findVisibleTarget`/`targetRootOf`/`fireOneShot`, the functions
every combat decision in `thinkNPC` ultimately depends on. It was deliberately
designed so every existing single-faction spawn path is a **structural
no-op** — same-faction grunts never select each other in `findVisibleTarget`,
so nothing about today's Player-vs-AI behavior should have changed — but
this is real surface area on the most safety-critical file in the project,
flagged honestly as higher-risk than the last several AI passes rather than
downplayed.

New `Constants.AI_FACTIONS` + `Constants.AI_ARENA` tables, new
`AIArenaBuilder.server.lua` (geometry only), and in `AIService.server.lua`: a
new `AITarget` type, `NPCRecord.faction`, `targetCharacterOf`, the widened
`targetRootOf`/`findVisibleTarget`/`fireOneShot`, per-faction `buildRig`
colors, the `factionKey` parameter threaded through `spawnOne`/`spawnSquad`/
`AIService.SpawnSquad`, and the self-contained `runArenaBattle` auto-spawn/
watch loop. `AIService.server.lua` + `Constants.lua` + one new file + one new
`default.project.json` entry only — no new remotes, no client files,
`GunService`/`DamageService`/`TeamService` untouched. MCP-checked (throwaway
logic, not a live `AIService` require, against a live Edit datamodel) the
same-faction no-op guarantee, different-faction targeting, dead-target
exclusion, the Player-vs-Model target-kind branch, the arena's wall/cover/
spawn-position geometry (spawn points and every cover block, including its
rotated half-diagonal, land inside the perimeter walls; the two spawn points
are ~130 studs apart), the wipe-detection condition, and the spawn-retry
loop's termination behavior. Residual risks:

- **Not runtime-verified in Play.** Whether AI-vs-AI combat actually looks
  and feels right — squads advancing, using cover, fire discipline holding,
  bound-and-cover leapfrogging, dynamic navigation routing around the
  arena's walls — has not been observed. This is also, by construction, the
  first time `findVisibleTarget`'s enemy-grunt loop and `fireOneShot`'s
  enemy-grunt damage branch have ever actually executed (no faction has ever
  differed before this pass), so it is the least-exercised new code path in
  the whole session.
- **No attacker attribution for AI-vs-AI damage.** `DamageService`'s
  `attacker` field is `Player?` — deliberately not touched, so `ApplyDamage`
  is called with `targetModel` only when the source is an enemy grunt. This
  means the `CombatEvents.DamageDealt` hit-reaction listener (which sets
  `record.target = info.attacker` to instantly retarget onto whoever just
  shot you) never fires for AI-inflicted hits, exactly as it already didn't
  for AI→player hits — a grunt shot by an enemy squad only reacquires that
  enemy via `findVisibleTarget`'s next LOS scan (`AI.TARGET_RECHECK_INTERVAL`),
  not instantly. It does still enter `Cover` on the hit (`record.coverUntil`
  is armed regardless of attacker identity) and does still get suppressed/
  recently-damaged tiering, since those don't need to know *who* shot it.
- **Arena squads share the global `MAX_ACTIVE_NPCS` (12) budget with every
  other AI spawn in the game.** With the main game's own AI zone active
  (`DEV_TEST_AREA.SPAWN_AI_ZONE`, up to `MAX_SQUADS` × `DEFAULT_SQUAD_SIZE` =
  6) plus the arena's two `SQUAD_SIZE` = 4 squads (8), total demand (14) can
  exceed the cap — squads may spawn smaller than requested, or `spawnSquad`
  can return empty and `runArenaBattle`'s retry loop can exhaust all
  `SPAWN_RETRY_ATTEMPTS` and give up (logged via `Logger.warn`) if the game's
  other AI never frees up room. Not fixed automatically — `MAX_ACTIVE_NPCS`
  is a gameplay-balance constant, out of scope to silently raise here.
- **A wandering DEFAULT-faction grunt (or a player) near the arena's
  sky-island footprint would also register as hostile to both arena
  factions** — correct "different faction = enemy" semantics by design, not
  a bug, but this specific interaction (a third faction wandering into an
  active two-faction fight) is untested. In practice the arena's `Y=600`
  sky-island origin makes this unlikely to ever happen by accident.
- **No designer control over the arena's cover placement.** The ten cover
  blocks and the one stepped structure in `AIArenaBuilder.buildCoverScatter`/
  `buildStructure` are a single hand-authored layout, hardcoded in the
  builder script (same convention `TestAreaBuilder` already uses for its own
  Stairs/DropTest shapes) — not data-driven, not randomized, no in-Studio
  editor. Changing the layout means editing the script.
- **`AIArenaBuilder` duplicates `TestAreaBuilder`'s `makeBlock` helper**
  rather than sharing a module — deliberate isolation (this file is meant to
  be fully independent of `TestAreaBuilder`), same precedent as Stage 1C's
  AI weapon-attach code duplicating `WorldWeaponService`'s ~30 lines,
  already noted elsewhere in this file.
- **The stepped structure's risers are a first guess (2 studs each), not
  Studio-verified against the default `Humanoid` step height** — if a grunt
  can't auto-step them, it will just walk into the first riser and stop
  (`AGENT_CAN_JUMP = true` in `Constants.AI_NAVIGATION` gives dynamic-nav
  waypoints a jump fallback, but the structure isn't guaranteed to be reached
  via a nav-mode goal — it is purely decorative/optional, not a required
  combat position).
- **`runArenaBattle`'s wipe-detection polls on a fixed `BATTLE_CHECK_INTERVAL`
  (4s)**, so there's up to a 4s delay between a side's last grunt dying and
  the respawn timer even starting, on top of the `BATTLE_RESPAWN_DELAY`
  itself — not instant, deliberately (matches every other polling loop in
  this file rather than adding an event-driven death hook).
- **No scoring, no round counter, no UI.** Per the task's own narrowed scope
  ("just two teams... their own color") — nothing here tracks win/loss
  history or displays faction identity to a player beyond the rig colors
  themselves and the `BR_AIFaction` attribute (Studio-inspectable only).

## AI arena spectating (Studio verification: REQUIRED, not done)

**Scope note up front:** this task requires client UI (a new menu button) and
a way to keep a spectating player from being shot — genuinely can't be done
without touching client controllers and, for the invincibility,
`DamageService.lua`. This is the **first time this session touches
`DamageService.lua`**, a file every prior AI task in this session explicitly
listed as off-limits; flagged prominently rather than done quietly. The
change itself is small and additive (see below), not a rewrite.

New `TeleportToArena` RemoteEvent (`RemoteSetup.server.lua`), a new
"WATCH AI ARENA" button (`LoadoutMenu.lua`), a new `SpectatorFlyController.lua`
client controller (registered in `ClientInit.client.lua`, one new
`default.project.json` entry), a new `Constants.SPECTATOR_FLY` table +
`Constants.AI_ARENA.SPECTATE_HEIGHT`, a new `TeleportToArena.OnServerEvent`
handler in `AIService.server.lua`, and a small addition to
`DamageService.lua`'s `applyToPlayer` (extends the existing `SetInvincible`
tooling helper — previously non-player-only — to also work for a Player's
Character, mirroring `applyToNonPlayer`'s exact `ATTR_INFINITE_HEALTH`
behavior). `GunService.server.lua`/`TeamService.server.lua` untouched. MCP-
checked (throwaway logic against a live Edit datamodel) the camera-relative
movement composition, speed selection, position integration, the
safe-landing distance check, the toggle no-op guard, the per-player
debounce, and a live round-trip of the invincibility attribute against the
real `Constants` module — a live `require(DamageService)` check timed out
(the same "live file require can hang" limitation noted earlier this
session, not a new one; the edit was instead verified by careful manual
review plus the successful live `Constants` require, which exercises the
same Luau parser). Residual risks:

- **Not runtime-verified in Play.** Whether the fly controls feel good,
  whether the invincibility grant actually prevents damage end-to-end, and
  whether the button/teleport/fly sequence works smoothly together have not
  been observed.
- **The `DamageService.lua` change is real, if small.** `applyToPlayer` now
  reads `victim.Character:GetAttribute(Constants.ATTR_INFINITE_HEALTH)` before
  computing health — a new branch in the single most safety-critical function
  in the combat pipeline (every player death/damage event in the whole game
  goes through it). It is a straight mirror of `applyToNonPlayer`'s existing,
  already-shipped behavior for the identical attribute, not new logic, but it
  is still a change to a file this session has treated as sacrosanct until
  now — worth a deliberate look in review, not just a rubber stamp because
  the diff is short.
- **Invincibility has no explicit "turn it back off" path.** It's keyed to
  the Character Model and only ever cleared by that Model going away (death →
  a fresh Model from the next `TeamService` respawn is never invincible by
  default). A player who flies back down and keeps playing on the SAME body
  without ever dying stays invincible until the next round's forced
  respawn (`TeamService` calls `LoadCharacter()` + teleports every player at
  every PREP) — bounded by the match loop, but not instant.
- **Fly movement is entirely client-authoritative**, same trust level as
  every other cosmetic client movement/camera system in this game (no
  anti-cheat boundary, nothing server-side validates or bounds where a
  spectating player's HumanoidRootPart actually goes). Acceptable for a
  dev/spectator convenience feature; would need real server reconciliation
  before this pattern could be reused for anything competitive.
- **`Space`/`Left Ctrl` (ascend/descend) overlap with existing bound keys** in
  `MovementController.lua` (`Space` = vault trigger, `Left Ctrl` = custom
  mouse-lock toggle). Deliberately not touched — `MovementController.lua` is
  at Luau's 200-local-register limit (see its own entry above) and this
  controller was built as a fully separate module specifically to avoid it.
  Holding these keys while flying may harmlessly also fire those other
  systems' input handlers (e.g. toggling mouse lock) since `Humanoid.
  PlatformStand` freezes the Humanoid's own state machine but not other
  scripts' raw input listeners — cosmetic overlap only, not a functional
  conflict, but untested together.
- **No server-side bound on how far a player can fly from the arena** —
  `setFlying`'s off-branch only snaps back to the arena center once, on
  toggle-off, past a 120-stud/below-ground threshold; nothing stops a player
  from flying arbitrarily far away first (e.g. back over the live map, 500+
  studs below). Acceptable for a dev feature; not something a player could
  do accidentally.
- **No "return to the game" affordance.** Landing, walking back into the
  normal game area, or dying are the only ways out of spectator mode short
  of the next round's forced respawn — there's no button that immediately
  ends spectating and teleports the player back to a normal spawn.
- **The hint label's wording is fixed English text**, not localized, and only
  ever shows/hides with the flying state — no separate "press the arena
  button to get started" prompt before the first grant.

## AI Invisibility button (Studio verification: REQUIRED, not done)

New `SetAIInvisible` RemoteEvent, `Constants.ATTR_AI_INVISIBLE` player
attribute, a `LoadoutMenu.lua` toggle button, and `isAIInvisible(player)`
checks inside `AIService.server.lua`'s `findVisibleTarget`, `targetRootOf`,
and the `CombatEvents.DamageDealt` hit-reaction listener. No `GunService`/
`DamageService`/`TeamService` changes. MCP-checked (throwaway logic) the
attribute round-trip, the "skip invisible even if closer" selection rule, the
instant-drop-on-toggle behavior, and the attacker-nulling logic in isolation;
this check deliberately avoided the live `Constants` module in this Studio
session, which was stale for these newest additions (Rojo sync had not
picked them up yet at check time — confirmed by re-checking `Constants.
AI_ARENA.SPECTATE_HEIGHT`, added the previous task and correctly resolving
live, versus `Constants.ATTR_AI_INVISIBLE`, added this task and resolving
`nil` live) — noted honestly rather than silently skipped or reported as a
false pass. Residual risks:

- **Not runtime-verified in Play.** Whether the toggle actually prevents
  detection/damage/awareness end-to-end in a live fight, and whether the
  button's label stays accurate across menu opens/closes, has not been
  observed.
- **Invisibility is a targeting-selection rule only, not a rendering/
  collision change.** An "invisible" player is still fully visible and solid
  to every other *player* (this never touches `LocalTransparencyModifier`,
  `CanCollide`, or any client rendering) — the name describes how AI treats
  them, not a literal visual effect. Worth a clearer button label
  ("AI CAN'T SEE ME" or similar) if this reads as confusing in practice.
- **No server-side validation of the boolean payload beyond a `== true`
  coercion.** `SetAIInvisible.OnServerEvent`'s handler accepts whatever a
  client sends and coerces it — harmless here (the attribute only ever
  affects that same player's own treatment by AI, there is no way to abuse
  it against anyone else), but worth knowing this remote trusts its caller
  completely, same trust level as the crosshair toggle.
- **No cooldown/rate limit on toggling.** Spamming the button just spams
  attribute writes and debug logs — cheap, but unbounded; not expected to
  matter for a single-player-affecting dev toggle.
- **Does not suppress an already-armed `record.coverUntil`/suppression state**
  on the grunt that gets shot by an invisible attacker — the grunt still
  ducks into cover and gets suppressed (matches `applyToNonPlayer`'s general
  "still reacts physically, just can't identify/track the shooter" design
  used elsewhere for unknown attackers) — it just can't identify or chase the
  source. This is almost certainly the right call (a suppressed/hiding grunt
  reads as more "alive" than one that visibly ignores incoming fire), but
  it's a design choice worth flagging, not an oversight.
- **Does not affect `RocketService`'s splash-damage iteration** (it walks
  every `TAG_DAMAGE_ENTITY`-tagged entity directly, independent of
  `AIService`'s targeting) — an invisible player standing near a rocket
  impact would still take splash damage exactly as before. Out of scope
  here (that file is the parallel session's), but worth knowing "AI
  Invisibility" is specifically about AI *targeting*, not blast AoE.

## Player first-person weapon retraction — Tarkov close-quarters (Studio verification: REQUIRED, not done)

`ViewModelController.computeWallCollisionCF` + `Constants.VIEWMODEL_WALL_*`. One
forward ray from `camera.Position - look * VIEWMODEL_WALL_PROBE_BACKUP` along the
camera look each `RenderStepped`; a collidable hit within
`VIEWMODEL_WALL_PROBE_DISTANCE` produces a camera-local `wallCF`
(`CFrame.new(0,0,push) * CFrame.Angles(tuck,0,0)`) appended last in the PivotTo
chain, next to the positional-recoil term, on both the hip and ADS-aligned pivots.
`vmWallRetract` is a framerate-independent lerp (`1 - e^(-LERP_SPEED*dt)`), reset
to 0 in both `init` reset blocks. MCP-checked the APIs
(`RaycastParams.RespectCanCollide`, directional raycast, the CFrame chain + Lerp).
Residual risks:

- **Not runtime-verified.** Needs a first-person Play pass walking into walls at
  various angles, hip and ADS.
- **Push / tuck magnitudes and the tuck *sign* are un-eyeballed.** `push` is `+Z`
  (toward the player, same as recoil — verified direction); `tuck` is
  `CFrame.Angles(+x,0,0)` which should raise the muzzle. If the gun sinks or the
  barrel drops into the floor, flip `VIEWMODEL_WALL_TUCK_MAX_DEG` negative or lower
  `VIEWMODEL_WALL_PUSH_MAX`.
- **Single centre ray.** A wall only to the left/right of the crosshair (gun
  angled across a doorframe) does not retract; a thin railing the ray passes
  between does not either. No spread of probes, no per-barrel-tip test.
- **`wallCF` is right-multiplied onto both Lerp endpoints**, so during the ADS
  blend the interpolation is `Lerp(A*w, B*w, α)`, not `Lerp(A,B,α)*w`. The
  positional difference is tiny at these magnitudes but it is not mathematically
  identical to applying `wallCF` after the blend.
- **ADS alignment shifts.** Even at `VIEWMODEL_WALL_ADS_SCALE = 0.5` the sights
  move off centre when you aim into a wall — intended (you can't ADS through a
  wall) but it will feel different from games that just block the shot. Retune the
  scale (0 disables it while aiming) after a test.
- **`RespectCanCollide = true`** means the probe ignores non-collidable parts;
  a map made of `CanCollide = false` decorative walls would not retract the gun.
- **No interaction with the existing camera zoom / third-person switch.** In
  third-person (`isFirstPerson` false) the viewmodel is hidden so `wallCF` is
  moot, but the helper still raycasts every frame — a micro-cost, not gated on
  visibility.
- **Fire origin unchanged** by design (`GunController` camera / free-aim solve),
  so a retracted gun visually behind the player's eye still fires straight —
  correct for gameplay, but the muzzle-flash FX (`GetMuzzleWorldCFrame`) will play
  at the retracted position.

## AI Stage 1G — grunt death ragdoll (Studio verification: REQUIRED, not done)

`AIService` `require`s `RagdollService` and `onNPCDied` → `ragdollDeadNPC` mirrors
`DummyService.onDummyDied`: destroy the welded gun (+ its grip `Motor6D` on the
Right Arm), build a per-weapon impulse from `record.lastHit`, `RagdollService:Apply`
(pcall-wrapped). `record.lastHit` is set in the existing `CombatEvents.DamageDealt`
listener. Verified in a live Server datamodel that a 15-joint rig with a
9-part welded gun reduces to the 6 body joints and all 6 convert to
BallSocketConstraints with `BR_Ragdolled` set. Residual risks:

- **Not play-tested.** MCP confirmed the joint teardown/conversion, not how the
  body actually falls, whether the impulse reads right, or that nothing errors
  when a grunt dies mid-crouch / mid-move / mid-burst in a real round.
- **The gun just vanishes.** Dummies have no weapon, so this matches them, but a
  dropped rifle would look better. A weapon-drop path was considered and left out —
  detaching the model as a falling rigid assembly (restore mass + collision,
  `SetNetworkOwner(nil)`, re-parent to the AI folder / a debris folder) is the
  follow-up.
- **No `SetNetworkOwner` retry / no anchored-part guard beyond RagdollService's
  own.** `RagdollService:Apply` force-sets server ownership; if a grunt part is
  somehow anchored (it shouldn't be) the impulse is absorbed.
- **No corpse system.** The model is still `Destroy()`ed after
  `Constants.AI.DEATH_CLEANUP_DELAY` (6 s) — the ragdoll pops out of existence
  rather than sinking / fading. Same as before Stage 1G, now more noticeable.
- **`record.lastHit` can be stale.** If a grunt dies from a non-`DamageDealt`
  cause (a future hazard, `Humanoid.Health` set directly, a fall) `lastHit` holds
  the previous hit or nil → the impulse is from the wrong direction or absent
  (body just crumples). Acceptable for now (all current damage is `DamageDealt`).
- **`AIService.Destroy()` does not `RagdollService:Restore`** the pending-cleanup
  corpses before destroying them — fine because the model is destroyed whole, but
  if a revive/corpse-reuse system ever appears this needs revisiting.
- **Blood assumed working** from the shared `DamageDealt` path — not
  independently re-verified for the AI target in this change.

## AI Stage 1H — combat realism pass + manual respawn button (Studio verification: REQUIRED, not done)

Two independent changes landed together:

**Realism** — `fireOneShot` spread = `SHOT_SPREAD_DEGREES * record.aimSkill` (a
per-grunt multiplier rolled once at spawn) plus a bonus scaled by the target's
`AssemblyLinearVelocity` (harder to hit a moving player). A new
`record.engageAtClock`, armed only when the live target actually **changes**
(fresh sighting, or a new attacker via the hit-reaction listener), delays
`startBurst` by a random `REACTION_TIME_MIN`–`MAX` beat — the grunt still tracks
the target during that beat (`faceToward` runs regardless), it just doesn't
fire instantly. `coverDurationFor()` stretches `COVER_DURATION` while
`Humanoid.Health / MaxHealth <= LOW_HEALTH_RATIO`.

**Manual respawn** — a new `RespawnBots` RemoteEvent (client → server, no
payload) + `AIService.RespawnAllSquads()` (destroys every live/pending-cleanup
grunt with no ragdoll — a reset, not a kill — then re-spawns fresh squads),
wired to a **RESPAWN BOTS** button in `LoadoutMenu`. One shared server-wide
cooldown (`Constants.AI.RESPAWN_COOLDOWN_SECONDS`), not per-player.

`AIService` + `Constants.AI` + `LoadoutMenu` + `RemoteSetup` only. MCP-checked
the math (reaction-time range, aim-skill clamp, moving-target spread, low-health
ratio) and `AssemblyLinearVelocity` as an engine API; `RespawnAllSquads` was not
independently exercised live (it reuses the `AIService.Destroy()` teardown
pattern already verified in Stage 1G). Residual risks:

- **Not runtime-verified in Play.** Reaction-time feel, aim-skill variance, the
  moving-target penalty, and the respawn button all need a live pass.
- **Reaction time only gates the FIRST shot of a new engagement**, not every
  shot — intentional (real hesitation is at first contact, not per-round), but
  means a grunt that loses and instantly re-acquires the *same* target (e.g.
  LOS flickers behind a thin rail) fires without any pause, because
  `record.target ~= seen` is false. A target that actually goes fully `nil`
  first (the `LAST_SEEN_CHASE_SECONDS` window) and comes back does get a fresh
  beat.
- **`aimSkill` and the moving-target bonus are additive on the same cone**, so a
  low-skill grunt (`aimSkill` near `AIM_SKILL_MAX`) shooting at a sprinting
  target can reach a fairly wide effective cone — not hard-capped beyond the two
  individual constants; could feel too forgiving/punishing depending on how the
  two combine in practice. Tune `AIM_SKILL_VARIANCE` / `AIM_MOVING_TARGET_SPREAD_BONUS_DEG`
  after a test.
- **`AssemblyLinearVelocity` includes vertical speed** (jumping/falling counts
  as "moving") — not obviously wrong (a jumping target is genuinely harder to
  hit) but untested whether it feels right vs. horizontal-only speed.
- **Wounded grunts only stay in cover longer** — they don't actively disengage,
  call for help, or retreat toward their squad. No morale/rout behavior, no
  squad awareness of a wounded member.
- **`RespawnAllSquads` has no confirmation / feedback to the requester** beyond
  the button's own cosmetic countdown — no toast/sound on success, and a
  request that lands during the cooldown is silently dropped server-side with
  only a debug log, not surfaced to the player who clicked.
- **Respawn destroys grunts mid-anything** (mid-burst, mid-crouch, mid-retreat)
  with no ragdoll and no FX — an instant pop, by design (it's a reset button,
  not a kill), but worth confirming it doesn't look jarring or leave a
  half-played fire animation / sound hanging.
- **No access control on the remote** beyond the shared cooldown — any player,
  including a spectator or someone not actually fighting the AI, can trigger it
  for the whole server. Acceptable for a PvPvE test/zone context; would need a
  host/permission check if this ships toward a competitive mode.
- **Still no reload, no grenades, no squad tactics, no pathfinding** — explicitly
  out of scope for this pass (reload was already rejected in Stage 1C); "as
  realistic as possible" was interpreted as bounded human-like imperfection +
  wound response, not a tactics/AI-navigation overhaul.

## AI Stage 1C — fair combat tuning (Studio verification: REQUIRED, not done)

**Naming note:** this is the **second** feature to use the "AI Stage 1C" label —
the earlier one (still above, "grunt weapon model + third-person animation") is
unrelated and unaffected. The task that produced this entry explicitly named
itself "AI Stage 1C fair combat tuning" without apparent awareness that a Stage
1C already existed in this codebase (Stages 1A–1H were already complete). Both
are kept, distinguished by date/content in `docs/CHANGELOG.md` and
`docs/PROJECT_MAP.md`; nothing was renumbered.

New `Constants.AI_COMBAT_TUNING` + `AIService` helpers `armReaction` /
`aimBandFor` / `updateSquadAttackSlots`, new `NPCRecord` fields
(`firstSawTargetAt`, `lastSawTargetAt`, `lastKnownTargetPosition`,
`reactionReadyAt`, `reactionAnnouncedAt`, `lastTargetSwitchAt`,
`suppressedUntil`, `recentlyDamagedUntil`, `visibleTargetTime`,
`lastDamageCallAt`, `aimBand`) and new `SquadRecord` fields (`alerted`,
`attackerSlots`, `nextAttackSlotRecheck`). `AIService` + `Constants.AI_COMBAT_TUNING`
only — no new remotes, no client files, `GunService` / `DamageService` /
`RemoteSetup` / `default.project.json` untouched. MCP-checked the tier
selection, aim-ramp formula, sticky attack-slot allocation, target-switch
cooldown, and visible-time freeze/reset math with throwaway logic (not a live
`AIService` require — that pattern timed out in this environment in an earlier
session; see the Stage 1G entry above). Residual risks:

- **Not runtime-verified in Play.** None of reaction feel, aim-ramp danger
  curve, suppression's effect on incoming fire, or squad-slot fairness has been
  observed in a real fight — only the underlying math was checked in isolation.
- **Tuning values are first guesses.** `REACTION_TIME_*`, `AIM_SETTLE_TIME`,
  the two spread multipliers, `SUPPRESSED_*`, `MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD`
  — all as specified verbatim, none tuned against actual play. Expect to need
  a pass after the Studio test steps below.
- **Near-miss suppression was deferred**, per the task's own "Optional only if
  easy" — there is no existing signal for "a shot passed close to this NPC
  without hitting it" (raycasts resolve to a single hit or nothing; there's no
  broad-phase near-miss event). Only actual accepted hits (`CombatEvents.DamageDealt`)
  arm suppression. Adding true near-miss detection would need a new geometric
  check (e.g. closest-approach-to-ray) — a separate, larger task.
- **Consolidated with, rather than layered onto, Stage 1H's reaction-delay
  mechanism.** The old flat `Constants.AI.REACTION_TIME_MIN/MAX` fire-gate
  (`record.engageAtClock`, the `reactionDelay()` helper) was **removed** and
  replaced by the new tiered system — running both would have gated the same
  "when does this grunt first shoot" decision twice for no benefit and no
  unaware/alert distinction. The two `Constants.AI` fields are left in place,
  now unread, because the task said not to remove existing `Constants.AI`
  values; a future cleanup could delete them. Stage 1H's *other* two knobs
  (`aimSkill` per-grunt variance, the moving-target spread bonus) were kept and
  now multiply together with the new aim-ramp/suppression factors on the same
  cone — not redundant (different concepts: personality vs. target behavior vs.
  engagement freshness vs. being shot at) but four multiplicative factors
  stacked on one `SHOT_SPREAD_DEGREES` is more surface area to over/under-tune
  than the spec alone describes; watch for it compounding into either
  laser-accurate or comically wide shots in edge cases (e.g. a low-`aimSkill`
  grunt that is also suppressed and tracking a sprinting target).
- **`record.target` was kept**, not renamed to the spec's `currentTarget` — same
  role, used at ~15 existing call sites; renaming was judged out of scope for a
  tuning-only pass ("do not rewrite AIService from scratch"). Anyone matching
  this file against the original task text should expect that name difference.
- **`LAST_KNOWN_POSITION_MEMORY` drives the NEW aim-ramp decay, not a second
  chase/investigate timer.** The pre-existing `LAST_SEEN_CHASE_SECONDS` /
  `SEARCH_DURATION` / `flankPointFor` Chase→Search pipeline (Stage 1D/1E) is
  completely unchanged — deliberately, since cover/flanking rewrites were
  explicitly out of scope for this task. "AI can chase/investigate last known
  position for LAST_KNOWN_POSITION_MEMORY seconds" is satisfied by that
  pre-existing pipeline, not a new one.
- **Squad attack slots are a simple recheck-and-fill, no roles.** Sticky (an
  existing holder keeps its slot while eligible) to avoid flicker, but has no
  concept of "best positioned" or "closest" grunt — whichever eligible member
  `pairs(npcs)` happens to iterate to first fills a vacancy. A benched grunt
  only "holds fire"; it does not reposition or fall back to reload/support,
  per the task's own scope (no advanced roles yet).
- **`squad.alerted` never resets.** Once any member of a squad has engaged a
  live target, that squad's reaction tier is `Alert` forever (until the squad
  is destroyed/respawned) — matches "alert bots react faster" but means a squad
  that loses the player for a long time and returns to patrolling still reacts
  at Alert speed on next contact, never fully de-escalating to Unaware. No
  decay timer exists for this; could be added later if it feels wrong.
- **No rewards/killstreaks, no difficulty presets** — not part of this task.

## Pre-round loadout menu — partial DEBT-013 (Studio verification: YES, required)

`LoadoutMenu` (client UI) + `LoadoutService` (server) + the `SelectLoadout` remote give
each player server-owned pre-round state in two Player attributes:
`BR_LoadoutPrimary` (weapon key) and `BR_TeamPref` (`Auto` / `Attackers` / `Defenders`).
`GunService.resolvePrimary()`, `TeamService.resolveTeamAssignment()` and
`GunController`'s equip path all read those attributes, falling back to
`Constants.DEFAULT_WEAPON` / an even split. All tuning is in `Constants.LOADOUT`.

- **Partially closes DEBT-013.** The primary weapon and team are no longer a single
  shared constant. Still open: secondary/gadget slots, per-weapon reserve/attachment
  choices, and `WeaponFired`/`ReloadRequest` still trust the attribute rather than
  carrying a validated weapon id.
- **Only AKS74 is selectable.** `AR15` / `SCAR` render as greyed "LOCKED" rows and are
  rejected server-side — they have no complete `WeaponData` block or viewmodel asset,
  and `WeaponData.lua` / `WeaponFeel.lua` are owned by a parallel work session. Unlock =
  add the data + a `ReplicatedStorage/ViewModels` asset, then flip `selectable = true`
  in `Constants.LOADOUT.WEAPONS`. No other code change.
- **Cursor-hide race, partially fixed (2026-09-10, user-reported: "the cursor is
  back on the screen").** On close, `setOpen(false)` used to re-lock the cursor
  only if `LocalPlayer.CameraMode == LockFirstPerson` **at that exact instant** —
  but the menu closes off `RoundStateChanged` (a remote) while `CameraMode` flips
  to `LockFirstPerson` off `CharacterAdded` (`ViewModelController`), two
  independently-timed events. Whichever landed second left the cursor stuck
  visible. Fixed by making the cursor-sync a standing reaction
  (`syncCursorToCameraMode`, driven by both the menu closing AND a
  `CameraMode` `GetPropertyChangedSignal`), not a one-shot check. Still true and
  still open: `GunController.applyFirstPersonAim` independently drives the same
  two properties keyed off weapon-equip state, so a holster/menu-open on the same
  frame can still race between the two owners — a single cursor-owner arbiter
  remains the real fix, this only closes the specific timing gap that was hit.
  Not runtime-verified (this session has no way to reproduce the exact race).
- **`LOCK_EDITS_DURING_ACTIVE = false` — mid-round switch now equips immediately
  (2026-09-10, user-reported: "when I click the shotgun... I should switch to
  that weapon").** `GunController` now re-equips instantly (holster + re-equip,
  reusing its own existing branches) when `BR_LoadoutPrimary` changes while the
  player already holds a weapon in `ACTIVE`; `GunService` mirrors this by
  re-running `setupAmmo` (full mag/reserve for the NEW weapon) on the same
  attribute change, fixing what would otherwise be a leftover ammo-count
  mismatch (e.g. still "22" rounds after switching from a 30-round mag to a
  6-round one). Both are additive listeners in `GunController.lua` /
  `GunService.server.lua` — **files a parallel session is actively rewriting for
  shotgun support; left uncommitted** so they aren't lost/conflicted, and could
  be overwritten by that session's next full-file save. No client/server change
  to a holstered player (their next manual equip already reads the fresh
  attribute) and no change to `LOCK_EDITS_DURING_ACTIVE` itself — this is a
  parallel behavior, not a bypass of that flag. Not runtime-verified.
- **PREP is `PREP_TIME` (2 s) in dev config**, so the menu auto-opens on LOBBY / RESULTS
  only and is otherwise M-key driven. If PREP is lengthened, add `Constants.Phase.PREP`
  back to `Constants.LOADOUT.AUTO_OPEN_PHASES`.
- **Not runtime-verified.** MCP can't drive input or equip a weapon; needs an in-game
  Play test — menu open/close, team pick moving the spawn, AKS-74 equipping, ammo label.
- **KILL ALL BOTS button (2026-09-11).** `AIService.KillAllBots()` sets every live
  grunt's `Humanoid.Health = 0` directly and lets the existing per-NPC `Died`
  connection do the rest (`onNPCDied`: ragdoll, blood, corpse timer, attack-slot
  release, formation reassignment) — the same mechanism every AI death in this
  game already goes through (a player's bullet, `KillAllBots`'s remote
  ancestor being no different structurally). Gated by a new
  `Constants.AI.KILL_ALL_COOLDOWN_SECONDS` shared cooldown, same pattern as
  Respawn Bots. No new record fields, no new state machine — `AIService`'s
  own `onNPCDied` already handles every cleanup path this button needs. Not
  independently runtime-verified (relies on the already-proven Health=0→Died
  pipeline, not a new one); confirm in Play that a full squad wipe via the
  button looks/sounds right (ragdolls drop with no impulse direction, since
  there's no `DamageInfo` behind this kill — `record.lastHit` is whatever it
  last was, which `ragdollDeadNPC` already handles as an optional field, so
  the body should just crumple rather than fly, which is the intended feel
  for an admin/dev-style kill switch, not a shot).

## Aiming / free-aim / cursor — Tarkov-style hipfire (Studio verification: YES, required)

Hipfire fires from the camera along the direction the free-aim-rotated gun visually points,
per-weapon free-aim feel profiles exist, and the OS cursor is locked/hidden during weapon
use. This **wires DEBT-063** (previously: "free-aim GetAimRay is a forward-declared API, not
wired into firing"). Client-only; no server/remote/damage/ammo change. Open risks:

- **Not runtime-verified.** MCP `require()` gets a separate module context and a weapon
  can't be equipped from MCP, so the aim direction, cursor lock, and per-gun feel could not
  be exercised. Needs an in-game test.
- **Firing model changed 2026-09-09 (v2), not Studio-tested.** The first version fired from
  `ViewModelController.GetMuzzleWorldCFrame()` (the viewmodel `MuzzleAttachment`
  WorldCFrame). Studio measurement showed that attachment (auto-created on the AKS-74
  `Barrel`) pointed ~180° backwards **and** the Model pivot was ~330 studs from the player,
  so the server rejected every hipfire shot (`WeaponFired: origin too far from root`) —
  hipfire did no damage. Now: origin = `camera.CFrame.Position`, direction =
  `(camera.CFrame * CFrame.Angles(ViewModelController.GetFreeAimAngles())).LookVector`.
  `GetFreeAimAngles()` returns the same pitch/yaw that build `freeAimCF` (swing included).
  Still needs an in-game check that hipfire now damages and lands where the gun points.
- **`GetFreeAimAngles()` ≈ but ≠ the viewmodel's true world rotation.** Recoil CFs
  (`viewRecoilCFrame`, `vmRecoilCF`) and the camera/movement inertia CFs sit between
  `cam.CFrame` and `freeAimCF` in the pivot chain, so the fired direction omits the visual
  recoil kick (intended — camera recoil + spread own that) and a sub-degree of inertia lag.
- **`GetMuzzleWorldCFrame()` is now unused by the fire path** — kept as a public accessor
  (future tracer/bore-FX origin). Remove if nothing adopts it.
- **Yaw sign is a guess.** `ViewModelController` rotates the viewmodel with
  `freeAimYaw = -vmFreeAimBlended.X * angle`, and firing now inherits that exact sign. If
  the gun points *away* from the reticle in Studio, flip to `+vmFreeAimBlended.X` (this also
  flips the fired direction, since they share the value).
- **Rotation-vs-slide fix (2026-09-09), not Studio-tested.** Owner reported the gun would
  not visibly rotate right — it slid left and recentred. Cause: raw `vmMouseInertia`
  (clamp ≈26–30) was summed into the roll/translation terms next to `vmFreeAimBlended`
  (clamp ≈1), so fast moves were dominated by a lateral lurch. Now the inertia is
  normalised to ≈[-1,1] first, and also feeds `freeAimYaw`/`freeAimPitch` as a trailing
  swing via `Constants.FREE_AIM_VIEWMODEL_SWING_FACTOR` (0.5). `SWING_FACTOR` and the
  reticle-tracking `maxAimAngle` (≈4° at the deadzone edge) are un-eyeballed guesses.
- **A residual *constant* leftward lean, if any remains after the fix, is NOT free-aim.**
  The free-aim yaw is small (≈4°), symmetric, and self-centres when the mouse settles. A
  fixed cant that doesn't change when the camera turns is the AKS-74 viewmodel idle/hold
  animation or the rig's FakeCamera → `BASE_OFFSET` alignment, and must be corrected on the
  rig in Studio — no code knob covers it.
- **Fire origin is the camera**, not the bore — no muzzle parallax at all now (a fixed-bore
  Tarkov feel would need the origin moved back to a real per-weapon `MuzzleAttachment` plus
  an origin-vs-root guard so a bad rig can't get shots server-rejected).
- **`FREE_AIM_FIRE_FROM_MUZZLE = false`** now just means "fire the camera ray through the
  reticle offset" (the pre-Tarkov behaviour); it no longer depends on any attachment.
- **Muzzle-flash emitters still hang off the auto-created `MuzzleAttachment`.** The
  auto-create sign heuristic was fixed (axis flipped if it points back at the model
  centroid), but a hand-authored `MuzzleAttachment` at the bore tip per weapon is still the
  right fix — if the AKS-74 rig template already contains a backwards one, delete it so the
  heuristic runs.
- **Cursor lock coexistence with `MovementController`.** `GunController` restores the
  pre-lock `MouseBehavior`, so if MovementController's LeftControl lock was on it stays
  LockCenter; if it was off, a 1-frame flicker to Default is possible when unequipping in a
  menu. Not observed, not fixed.
- Per-gun `FREE_AIM_PROFILES` values (AKS74/AR15) are first-guess stubs.
- Recoil/spread/camera-kick: `CameraRecoil.lua` (parallel change) now exists; its
  `camera.CFrame` writes are separate from this work.
- No dynamic crosshair / spread UI.

## Viewmodel / FX — Stage 1 muzzle flash (Studio verification: Yes, still required for visuals/tuning)

Local first-person muzzle FX (`ViewModelController` + `Constants.MUZZLE_FX`). Runtime behaviour
was MCP-verified in a Studio Play session (emitters/light built once from the right per-gun
profile, light pulse, no Output errors, graceful fallback). Remaining risks:

- **Placeholder particle textures** — `FLASH_TEXTURE` / `SMOKE_TEXTURE` / `SPARK_TEXTURE` are
  `rbxassetid://0`; Roblox renders a default square particle. Replace with real flash/smoke/
  spark art in `Constants.MUZZLE_FX.DEFAULT` (or per-profile). ViewModelController warns once.
- **`MuzzleAttachment` should be authored in Studio per weapon.** The AKS-74 viewmodel has no
  attachment, so one is auto-created on its `Barrel` part along that part's longest local axis
  — a best-effort guess for position AND facing; the sign of "forward" may be wrong on some
  rigs. Add a real `MuzzleAttachment` at the bore tip, pointing out the barrel, for each gun.
- **No replicated third-person muzzle flash for players.** Other players see nothing;
  this player viewmodel FX is local-only. (Separate system: AI grunts got a
  server-created, world-replicated muzzle flash in AI Stage 1B — `Constants.AI_COMBAT_FX`
  in `AIService`, not shared with this `Constants.MUZZLE_FX` player path.)
- **Local bullet impact FX now exists** (Stage 1 — see next section). Tracers, shell
  ejection, and surface-specific FX are still out of scope.
- **FX values (emit counts, lifetimes, sizes, speeds, light range/brightness/duration) are
  first guesses** and need eyeball tuning in Studio / a running app, especially once real
  textures exist. Per-gun profiles (`Constants.MUZZLE_FX.PROFILES`) are stubs — only AKS74
  and AR15 exist, and their differences are placeholders.
- Adds 5 module-level locals to `ViewModelController.lua`; that file has headroom now, but see
  the MovementController register-limit note below — the same limit applies here.

## Viewmodel / FX — Stage 1 local bullet impact FX (Studio verification: helper logic YES, in-game look NO)

`ImpactFX` helper inside `GunController.lua` + `Constants.BULLET_IMPACT_FX`. Now
**material-specific**: `MATERIAL_CATEGORY` maps `Enum.Material` → `concrete` / `metal` /
`wood` / `dirt` / `default`, and `CATEGORIES` holds a `DUST` / `DEBRIS` / `SPARK` config
per category. Each pooled rig carries three emitters; `PlayImpact(pos, normal, material)`
looks up the category and assigns pre-resolved sequences (no per-shot allocation), rig
`+Y` aligned to the surface normal. Studio-verified (Client datamodel: mapping correct,
per-category params applied to the right emitters, missing role leaves its emitter
untouched, 300 rapid calls no error, pool pinned at `POOL_SIZE`, asserts fire, `Destroy`
cleans up). Open items:

- **Textures are engine built-ins, not authored art.** `DUST_TEXTURE` is the built-in
  smoke sprite; `DEBRIS_TEXTURE` / `SPARK_TEXTURE` are `""` (a plain square). Fine and
  cheap, but real chip / spark / streak sprites would look better — swap them in
  `Constants.BULLET_IMPACT_FX` (`rbxassetid://0` still triggers a one-time warn).
- **In-game look not eyeballed.** MCP can't equip a weapon; the per-category counts /
  sizes / speeds / colors / gravity are first guesses and need a Studio pass (single
  shots + sustained full-auto on each material).
- **Lives inside `GunController`, not a standalone controller.** Extract to
  `src/StarterPlayer/StarterPlayerScripts/Controllers/ImpactFXController.lua` — keep the
  `ImpactFX.PlayImpact` / `ImpactFX.Destroy` shape, add `Start()`, add the Rojo-map entry
  and a `ClientInit` registration. `default.project.json` can be edited now (TestAreaBuilder
  set the precedent), so this is unblocked — just not done.
- **`ImpactFX.Destroy()` is never called.** GunController has no destroy path (DEBT-059);
  the pooled parts + `BR_ImpactFx` folder live for the session. Bounded, so not a leak.
- **Glass is not implemented.** No `glass` category / shard burst — deferred until a glass
  material is actually in use (spec: "do not implement unless glass material support is
  simple").
- **Flesh / character hits use `default`.** `BR_DamageDummy` / player hits produce a
  neutral dust puff, not blood — blood is `BloodController`'s job (separate system, Stage
  4). No overlap wired.
- **No decals / scorch marks / bullet holes.** Impacts are particle-only; no persistent
  surface mark of any kind.
- **Not replicated.** Only the shooter sees their own impacts. A replicated path (server
  tells nearby clients, or clients predict from `WeaponFired` echoes) is deferred.
- **Server-authoritative reconciliation deferred.** The burst is placed at the *client's*
  predicted hit point; if the server's authoritative raycast disagrees it is not corrected.
- **Pool size / timing (`POOL_SIZE = 24`, `IMPACT_PART_LIFETIME = 1.0`) are first guesses.**
  With 24 rigs and a 1.0 s hold, sustained fire above ~24 rounds/sec starts stealing
  not-yet-finished rigs (visible pop). Tune once real fire rates are settled.
- **Removed `Constants.BULLET_IMPACT_ENABLED` / `_SIZE` / `_LIFETIME` / `_TRANSPARENCY` /
  `_COLOR`** and their inline single-sphere block in `GunController` — superseded by
  `BULLET_IMPACT_FX`. The separate `DEBUG_BULLET_IMPACT_MARKERS` muzzle-tip marker is
  untouched.

## Dev tooling — generated test area `TestAreaBuilder` (Studio verification: build logic YES, in-game run required)

`src/ServerScriptService/Services/TestAreaBuilder.server.lua` + `Constants.DEV_TEST_AREA`
build `Workspace/BrokenReality_TestArea` on server start, Studio-only. The construction
logic was verified in the Edit datamodel (builds clean, rerun reproduces an identical
tree, exactly one folder, `workspace` gains one child, all sections present, self-cleaned).
Open items / deferred:

- **Developer-only by design.** Guarded by `RunService:IsStudio()` **and**
  `DEV_TEST_AREA.ENABLED`. It must never build in a live server — if a live build is ever
  wanted, add an explicit separate flag rather than loosening the `IsStudio()` gate.
- **Auto-run on server start not MCP-tested.** A weapon/character can't be driven from MCP;
  the `Play`-time behaviour (script runs, folder appears, no Output errors, stop/restart
  rebuilds safely) needs an in-Studio pass with Rojo connected.
- **Visual layout is first-pass and will need tuning.** Section spacing, ramp angles, the
  crouch-tunnel clearance vs. the real R6 crouch height, vault-bar reachability, and label
  placement are eyeball guesses in `Constants.DEV_TEST_AREA`. Ramps use a flat run = 3×rise
  and may not meet the platform edge perfectly.
- **`TestSpawn` is an enabled neutral `SpawnLocation`.** Harmless with the live flow
  (`Players.CharacterAutoLoads = false` + `TeamService` teleports), but in a plain Studio
  playtest it becomes a real spawn. If that ever conflicts, set `Enabled = false` and make
  it a plain marker.
- **`REDIRECT_TEAM_SPAWNS` mutates `Workspace/Spawns` (Studio only, reversible).** This is
  the one place the builder writes Workspace content it does not own. It only sets
  `BasePart.CFrame` + the `BR_TestAreaOriginalCFrame` attribute, restores from that
  attribute at the top of every run, and never reparents/resizes/destroys — but the revert
  path depends on those attributes surviving. If a spawn part is deleted/recreated in
  Studio while redirected, its original position is lost (re-place it by hand). To restore:
  `REDIRECT_TEAM_SPAWNS = false` (keep `ENABLED = true`) + Play once. A fully disabled
  builder (`ENABLED = false`) will NOT auto-restore — it returns before reaching the spawn
  code — so toggle the sub-flag, not the master flag, to revert.
- **Grid layout of the redirected spawns is arbitrary** (6 per row, `TEAM_SPAWN_GRID_SPACING`
  studs, offset +8/+row from `SPAWN_POSITION`). Attackers and Defenders are interleaved in
  one grid, not separated — fine for solo movement/weapon testing, not for team-flow tests.
- **Material-specific impact logic is NOT implemented.** The `MaterialTest` samples are
  visual surfaces only — no per-material impact FX / sound / decal behaviour exists yet.
- **Moving targets are deferred.** The static neon targets never move.
- **Damage test dummies are now spawned** (2026-09-10): `DEV_TEST_AREA.SPAWN_DUMMIES`
  builds `DUMMY_COUNT` tagged R6 rigs downrange (rig geometry mirrors
  `scripts/Build-TestDummy.luau`); `DummyService` registers them for damage / blood / hit
  reactions / ragdoll / respawn. They carry `BR_TestAreaDummy` so a rebuild sweeps its own
  rigs and any `DummyService` respawn clone. Caveats: parented straight to `workspace`
  (not the test-area folder or a sub-folder), so between a rebuild and the sweep there is a
  brief window where an old and a new set could co-exist; the rig has no clothing / R15 /
  animation and no `HumanoidDescription`; DummyService's own service connections are never
  disconnected (pre-existing). The **test dummies** still just stand and take hits — moving
  AI now lives in the separate `AIService` (see "AI Stage 1A" above); its grunt NPCs are a
  different tag (`BR_DamageEntity` only, not `BR_DamageDummy`) so DummyService ignores them.
- **AI patrol zone is now built** (2026-09-10): `DEV_TEST_AREA.SPAWN_AI_ZONE` (default
  true) → a marked "AI Patrol Zone" pad inside the test-area folder, plus the top-level
  `Workspace/AISpawns` (2 anchored parts) and `Workspace/AIPatrolPoints` (4 anchored parts
  in a loop) that `AIService` reads, so grunt squads spawn and patrol on Play with no
  manual setup. The two folders carry `BR_TestAreaOwned`; each run destroys only folders
  with that attribute, so a **hand-authored** `AISpawns` / `AIPatrolPoints` is detected and
  left completely alone (the builder then skips its own). Caveats: the folder-name match is
  by string only (`Constants.AI.SPAWN_FOLDER_NAME` / `PATROL_FOLDER_NAME`); the marker part
  positions and the 4-point loop shape are eyeball guesses; `SPAWN_AI_ZONE = false` + one
  more run removes the owned folders (like the other opt-in sub-flags).
- **Extraction / loot-loop test area is deferred.** No objective, stash, exfil, or
  inventory props — out of scope for this task.
- **No global lighting/atmosphere test.** `LightingTest` is self-contained props only;
  `game.Lighting` is deliberately untouched (that stays owned by `LightingSetup.server`).
- **`default.project.json` gained one entry** (`TestAreaBuilder`) — required because the
  `Services` folder maps scripts explicitly, not as a directory.

## MovementController.lua is at Luau's 200-local-register limit (main chunk)

`MovementController.lua` (~6500 lines) has so many module-level `local` declarations that its
main chunk sits exactly at Luau's hard limit of 200 registers per function. Adding one more
module-level `local` fails compilation with `Out of local registers ... exceeded limit 200`,
which cascades: `ViewModelController` and `GunController` require `MovementController`, so a
compile failure there takes down equip, fire, reload, sprint, and viewmodel/perspective
setup with a single line.

- Adding the sprint↔fire `isFiring` flag as a module-level `local` triggered exactly this;
  it was moved into the existing `movementState` table (table fields cost no registers).
- **Rule going forward:** do not add module-level `local`s to `MovementController.lua`.
  Store new flags in `movementState` (or another existing table), or the file needs a
  refactor that moves state into tables / splits it into sub-modules.
- Not caught by `rojo build` — it is a runtime compile error visible only when the module
  is required in Studio.

## Vault / jump height (2026-09-10)

- Jump height is now pinned via `StarterPlayer.$properties`
  (`CharacterUseJumpPower = false`, `CharacterJumpHeight = 4.5`) in `default.project.json`
  — a **structural** project change, so `rojo serve` must be restarted for it to sync, and
  any code that later writes `Humanoid.JumpHeight`/`JumpPower` will silently override it.
- `detectVault` measures obstacle height from the obstacle's own base via a downward
  raycast just inside the struck face. Assumes the obstacle sits on something within
  `VAULT_CLEARANCE_HEIGHT*2 + 24` studs below that face; a wall on a tall pillar, on
  deep terrain, or floating reads as "no base → un-vaultably tall" and is rejected. Fine
  for current geometry but a real map may need the search window widened, or a proper
  "walk up to a raised ledge" case that this rejects.
- The R6 foot offset is still assumed `3.0` studs elsewhere in the vault arc/landing math;
  only the height *classification* was moved off the player-feet reference.


## Damage test dummy — Stages 1–6 (new; Stages 2–3 owner-tested, 1 & 4–6 not)

Damage pipeline generalisation + `DummyService` + `RagdollService` rework (1–3) and blood /
hit reactions / debug UI (4–6). See `docs/DAMAGE_TEST_DUMMY_PLAN.md` for the full status
table and the Stages 4–6 debt list. Highlights:

- Stages 4–6 are not Studio-tested; the new `Constants` blocks (particle counts, mark caps,
  flinch angle/duration, ragdoll impulse) are first guesses.
- Hit reactions only render on rigs with no Animator writing `Transform` (the dummy). On
  players the flinch is silently overwritten — the seam for an animation provider is the
  single `applyReaction` function; no provider registry (YAGNI).
- **Blood realism pass (2026-09-10).** `BloodController` does a two-emitter burst
  (soft-sprite MIST back toward the shooter + tilts up, blank-square DROPLETS that arc and
  fall on stronger gravity). Marks are split by role: small flat **body splatter** + a dark
  `Ball` **wound** both **welded to the struck limb** (found by a probe raycast), and
  bigger **ground-pool** marks + satellites found by a downward ray that excludes the hit
  character. New `Constants.BLOOD_BODY_MARK_*` / `BLOOD_WOUND_*` / `BLOOD_GROUND_*` /
  `BLOOD_COLOR_DARK`. Remaining debt:
  - Client-side `WeldConstraint` from a locally-made part to a **server-owned limb** —
    works for local visuals, but if the limb's network ownership or CanCollide changes it
    has not been stress-tested; the welded fx are never re-parented if the limb is swapped
    without a Destroy (the sweep only reacts to `Parent == nil`).
  - The limb probe (`findHitLimb`) is 4 short rays; a graze hit whose `hitPosition` sits
    just off every body part gets no body marks / wound (falls back to burst only).
  - Marks are texture-free flat parts (no splatter decal asset); the wound is a plain
    dark ball, not real carved geometry.
  - `BloodEffect` is `FireAllClients` with no distance culling; the whole thing is
    client-predicted (no server reconciliation).
  - All numbers are first-eyeball guesses — needs a Studio pass shooting a dummy.
- Dev tooling trusts `RunService:IsStudio()`; `Constants.DEV_USER_IDS` is empty until filled.
- **Ragdoll rework (2026-09-10) — needs an in-Play eyeball.** The "folds up while standing"
  symptom had three causes, all now addressed in `RagdollService:Apply`: (1) the death
  `ApplyImpulse` was silently absorbed until network ownership resolved — `Apply` now
  `SetNetworkOwner(nil)`s every unanchored body part first (Studio-verified: impulse lands
  the same frame vs not at all); (2) every `BallSocketConstraint` used one 45° limit —
  now per-joint via `Constants.RAGDOLL_JOINT_ANGLES` (hips/shoulders 115°, root 100°,
  neck 45°) so the rig can actually fall over; (3) the collidable legs held it upright —
  arms + legs go `CanCollide = false` while ragdolled (restored from a stashed attribute).
  The shove is now per-weapon (`Constants.RAGDOLL_WEAPON_IMPULSE` keyed by
  `DamageInfo.sourceName`, `DEFAULT` fallback), applied with `ApplyImpulseAtPosition`
  `RAGDOLL_IMPULSE_HEIGHT_OFFSET` studs above the Torso for topple torque, tilted down by
  `RAGDOLL_IMPULSE_DOWN_BIAS`. AKS-74 = `{ SCALE = 4.5, MAX = 320 }` — tuned from Studio
  physics probes (velocity ~40 studs/s topples an R6 rig, 16 does not) but **not** watched
  in a real death yet; if it still doesn't fall / flies too far, tune
  `RAGDOLL_WEAPON_IMPULSE.AKS74.SCALE`, `RAGDOLL_JOINT_ANGLES`, `RAGDOLL_IMPULSE_HEIGHT_OFFSET`.
  Removed `RAGDOLL_IMPULSE_SCALE` / `RAGDOLL_BALLSOCKET_UPPER_ANGLE`.
- **`SetNetworkOwner(nil)` on player deaths** hands corpse physics to the server — correct
  for authority, but if a future revive/get-up returns control to the player it must
  `SetNetworkOwnershipAuto()` in `Restore` (not done — dummies never revive, they respawn a
  clone).

Open items (Stages 1–3):

- Not installed in Studio, not committed, not Studio-verified. No Lune coverage — `DamageRules`
  is pure and should get a `scripts/Test-Damage.luau`.
- **PvP headshots now do ×2 damage.** The shared pipeline carries the hit part for players,
  so `Constants.DAMAGE_REGION_MULTIPLIERS` applies to PvP, not only dummies. Intentional,
  but a live gameplay change — zero out the multipliers to disable.
- `Constants.DAMAGE_MAX_PER_HIT` (500) now clamps the legacy `DamageService:Apply` path,
  which was previously un-clamped. Immaterial at current weapon/health values.
- Self-hit no longer routes to `DestructionService:ApplyHit` (was a harmless no-op).
- Limb health pool is tracked from `DamageDealt` but has no effect — it does not gate death
  and nothing consumes it until a future `GoreService`.
- Reset/respawn replaces the dummy Model from a template clone (a dead R6 Humanoid is not
  reliably revivable). One retained template clone per live dummy.
- `DamageService:Heal` / `:SetInvincible` landed early for Stage 6; currently unused.
- `DummyService` service-level connections are tracked but never disconnected (server-
  lifetime Script, same as `GunService` / `TeamService`). Per-dummy connections are cleaned.
- Blood (Stage 4), hit reactions (Stage 5) and the debug UI + dev remotes (Stage 6) are not
  built. `BR_ReactionsEnabled` / `BR_BloodEnabled` attributes are set on dummies but unused.
- Gore/dismemberment deliberately absent; `CombatEvents` + the limb pool are the seam for it.

## Reload recovery patch

Local code addresses an indefinite client reload lock and TP playback preventing FP playback. Visual asset load/permissions and joint compatibility remain unconfirmed in Studio. See RELOAD_DIAGNOSIS.md; no animation asset ID was changed. User testing and source reconciliation before installation are pending.

## ADS zoom-only mode (2026-09-09, not Studio-tested)

`Constants.VIEWMODEL_ADS_ANIMATION_ENABLED = false` (new default) makes `SetAiming` skip
the `adsIn`/`adsIdle`/`adsOut` pose clips: Hip→Aiming and Aiming→Hip are set directly,
the `adsAimAlpha` pivot blend glides the gun to centre, and the FOV zoom
(`MovementController.updateSprintFov` Task A) is the "zoom in". `PlayADSFireAnimation`
delegates to `PlayFireAnimation`. Open items:

- **Not Studio-tested.** A weapon can't be equipped from MCP. Needs an in-game check: ADS
  toggle glide framing, FOV in/out, fire while aimed, and reload/holster while aimed
  (all route through `StopADSAnimations` / the reload `adsState ~= "Hip"` exit, which are
  harmless no-ops on the never-played ADS tracks — verify visually anyway).
- **Centred pose is the idle pose, not a sighted pose.** With no `adsIn` clip, `aimAlignedPivot`
  puts the rig's FakeCamera at the camera in whatever pose idle/locomotion holds — "roughly
  centred", iron sights not truly aligned. If the framing looks off, add a small static
  `CFrame` offset to `aimAlignedPivot` in the zoom-only branch (no constant exists for this
  yet) or re-enable the animation.
- **Procedural sway/bob still fades out during zoom** (`inADS` path, scaled by `1 - adsAimAlpha`)
  and free-aim is zeroed — intended for a steadier zoom, but if the gun should keep bobbing
  while zoomed that suppression needs a carve-out.
- **The four ADS tracks are still loaded** by `_setupWeaponAnimations` even though unused —
  deliberate, so flipping the constant back to `true` restores full behaviour with no other
  change. Minor wasted `LoadAnimation` per equip.
- **Two FOV writers are now one path but two owners in principle.** MovementController owns
  `camera.FieldOfView` (sprint + ADS Task A). ViewModelController's zoom-only ADS relies on
  that; it does not write FOV itself. If ViewModelController ever needs its own zoom curve,
  reconcile ownership rather than adding a second writer.

## Animation lock recovery — equip / ADS (new, not yet Studio-tested)

Same bounded-recovery pattern as the reload patch, applied to `PlayEquipAnimation` and to ADS-in/ADS-out in `SetAiming`. See RELOAD_DIAGNOSIS.md "Extended scope". Not installed in Studio; visual asset load/permissions remain unconfirmed there, same as the reload patch. **Note (2026-09-09):** with `VIEWMODEL_ADS_ANIMATION_ENABLED = false` the ADS-in/ADS-out watchdogs and the Entering/Exiting states are not used at all — the recovery patch only matters if the animation is re-enabled.

Two related gaps were found but intentionally left unpatched this pass (lower impact, no permanent lock):
- Third-person equip (`startThirdPersonEquipSequence`) skips the TP equip clip whenever it isn't already loaded at the moment `EquipWeapon` calls it (near-always, since asset loading is asynchronous) and falls straight to TP idle — a missed cosmetic beat, not a freeze.
- `weaponEnterRunTrack`'s one-shot Walk/Idle→Run clip has no completion timeout; it can only visibly stick if a player holds Sprint uninterrupted while that specific clip fails to load, since every other locomotion-state entry already force-clears it via `cancelEnterRun()`.

## Wood/door destruction (new, not yet Studio-tested)

`DestructionService`/`DestructionRules` (`src/ServerScriptService/Services/`) implement bullet-driven wood/door destruction in the main game, wired into `GunService.server.lua`. See `docs/DESTRUCTION_SYSTEM_PLAN.md` for full status. Key open items:

- Not installed in Studio, not committed, not Studio-verified. No actual Studio map content is tagged with `BR_BreakableProfile` yet — until it is, the system registers zero parts and is a no-op.
- `scripts/Test-Destruction.luau` was written but could not be run here (Lune not installed in this environment) — verified only by manual trace, same caveat as the reload/equip/ADS test re-verification this session.
- Only registers parts present in `workspace` at server start; anything added to the map later (streaming, runtime spawning) is not picked up. Matches the already-accepted limitation in the CityDistrict prototype this was ported from.
- `DESTRUCTION_MAX_REGISTERED_PARTS` (800) and the debris cap (64) are starting guesses carried over from the smaller isolated prototype's tuned values, not measured against the actual game map's likely part density once doors/walls are chunked more finely.
- Explosive/AoE damage is explicitly out of scope (owner deferred it) — no `ApplyExplosion`, no trigger object, no new remote.

## Server-side reload has no duration lock

`GunService` transfers ammo immediately on `ReloadRequest` with no persistent server-side reload-duration lock, independent of client animation timing. A player could in principle spam `ReloadRequest` to top up ammo instantly regardless of the client's reload animation length. Not addressed by the client-side animation-recovery patches above — this is a server balance/exploit question, not an animation bug, and needs an explicit decision before any server-side reload-lock remote/logic change (no new remotes without explicit request).

The initial migration questions below are historical; see dated findings and SCRIPT_INVENTORY.md for inspected source. Do not treat unresolved questions as confirmed defects.

| Item | Status | Next step |
| --- | --- | --- |
| Complete script inventory and dependencies | Unknown | Inspect Studio Explorer and sources |
| Missing strict mode or legacy print/warn/wait/spawn | Not assessed | Record during verbatim capture; fix separately |
| Gameplay magic numbers | Not assessed | Review later for Constants.lua |
| Server authority and remote validation | Not assessed | Review one system at a time later |
| RBXScriptConnection cleanup | Not assessed | Review later |
| R15/SCAR legacy references | Not assessed | Record occurrences without assuming current direction |
| Script children, attributes, tags, RunContext, package behavior | Unknown | Capture before any sync mapping |
| Asset IDs, ownership/access, unpublished animation work | Unknown | Inventory and back up in Studio |

Do not create replacement systems to resolve speculative debt. Preserve baseline behavior during migration.

## City prototype — 2026-09-08

- Reload animation does not visibly play according to the owner; deferred, not repaired by the map work.
- Mercer District is a first blockout: upper floors are shells, terrain is flat, props are simple, and spawn/objective balance is untested. No new creature AI or zone persistence was added.
- Destruction passed 22 offline checks, but engine physics, multiplayer replication/late join, passage through breaches, reset behavior, and performance still need user-confirmed Studio results.
- Existing AR15 server weapon and AKS74 viewmodel naming/configuration differ; keep this separate from city integration.
- Generated test-copy GunService integration is not represented in src or Rojo mappings. Connecting baseline default.project.json to the city copy would revert that integration.
- New map artifacts are stored separately from Git. The generator is backed up in Git, but rebuilding the complete test requires the separately preserved original place file.


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


## Visible support collapse — 2026-09-11

Fixed unsupported sections disappearing when cosmetic clone debris hit its 64-primitive budget. Support collapse now animates the existing unsupported geometry as a falling group; it does not allocate debris clones. Gravity-driven visual descent is capped by a downward ground ray, with a slight tip. Sections remain for six seconds and fade over 1.2 seconds. Collision/query are disabled during collapse; this is cosmetic server-controlled motion, not a dynamic rigid-body simulation. Bullet/explosion chips retain their separate limits. Original transforms are recorded and restored on Reset; shutdown/removal clears tracking.

Assistant MCP test severed wood along an exact horizontal polygon cut: 447 unsupported primitives remained visible and moved downward (>0.1 studs), exceeding the old clone budget without disappearance. Timed fade cleanup and reset restoring original positions/visibility/collision passed. Source compiled and whitespace check passed. Playtest stopped; not published.
