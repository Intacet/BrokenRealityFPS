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
  combat feedback FX, not pathfinding).
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
- **No AI types, factions, cover, suppression, flanking, or squad tactics.** One
  grunt archetype, one ring formation, leader only used as the patrol-index advancer.
  Grunts are hostile to every player (no team logic).
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
- **Cursor-hide overlap with `GunController`.** While the menu is open it forces the OS
  cursor visible + unlocked; on close it re-locks only when
  `LocalPlayer.CameraMode == LockFirstPerson`. `GunController.applyFirstPersonAim` also
  drives `MouseIconEnabled` / `MouseBehavior`, so an edge case (holster mid-menu, phase
  flip on the same frame) can leave the cursor in the wrong state until the next
  equip/holster. Acceptable for a rough menu; a single cursor-owner arbiter is the fix.
- **`LOCK_EDITS_DURING_ACTIVE = false`.** A mid-round Deploy is accepted and only takes
  effect at the next PREP (attributes are read in `assignTeams` / `setupAmmo`), so there
  is no mid-round advantage. Set the flag true to reject ACTIVE-phase edits outright.
- **PREP is `PREP_TIME` (2 s) in dev config**, so the menu auto-opens on LOBBY / RESULTS
  only and is otherwise M-key driven. If PREP is lengthened, add `Constants.Phase.PREP`
  back to `Constants.LOADOUT.AUTO_OPEN_PHASES`.
- **Not runtime-verified.** MCP can't drive input or equip a weapon; needs an in-game
  Play test — menu open/close, team pick moving the spawn, AKS-74 equipping, ammo label.

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
