# Changelog

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
