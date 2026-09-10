# Technical debt and unresolved migration questions

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
- **No replicated third-person muzzle flash.** Other players see nothing; this is local-only.
- **Local bullet impact FX now exists** (Stage 1 — see next section). Tracers, shell
  ejection, and surface-specific FX are still out of scope.
- **FX values (emit counts, lifetimes, sizes, speeds, light range/brightness/duration) are
  first guesses** and need eyeball tuning in Studio / a running app, especially once real
  textures exist. Per-gun profiles (`Constants.MUZZLE_FX.PROFILES`) are stubs — only AKS74
  and AR15 exist, and their differences are placeholders.
- Adds 5 module-level locals to `ViewModelController.lua`; that file has headroom now, but see
  the MovementController register-limit note below — the same limit applies here.

## Viewmodel / FX — Stage 1 local bullet impact FX (Studio verification: helper logic YES, in-game visuals NO)

`ImpactFX` helper inside `GunController.lua` + `Constants.BULLET_IMPACT_FX`. Dust/smoke
puff + tiny sparks at the local predicted raycast hit point, pooled and bounded. The
helper logic was Studio-verified in the Edit datamodel (300 rapid calls, no error, part
count pinned at `POOL_SIZE`, `assert` guards fire, `Destroy()` cleans up). Open items:

- **Placeholder textures.** `BULLET_IMPACT_FX.IMPACT_TEXTURE` / `SPARK_TEXTURE` are
  `rbxassetid://0` — Roblox renders a default square particle. Replace with real dust/spark
  art; the helper `Logger.warn`s once while they are placeholders.
- **Lives inside `GunController`, not a standalone controller.** This stage was scoped not
  to touch `default.project.json`, and an unmapped `ImpactFXController.lua` would not sync
  (WaitForChild hang, like the CameraRecoil incident). Extract to
  `src/StarterPlayer/StarterPlayerScripts/Controllers/ImpactFXController.lua` — keep the
  `ImpactFX.PlayImpact` / `ImpactFX.Destroy` shape, add `Start()`, add the Rojo-map entry
  and a `ClientInit` registration — in a follow-up that is allowed to edit those files.
- **`ImpactFX.Destroy()` is never called.** GunController has no destroy path (DEBT-059);
  the pooled parts + `BR_ImpactFx` folder live for the session. Bounded, so not a leak, but
  the cleanup hook is dead until the extraction / a GunController teardown exists.
- **No surface-specific impact types.** One dust+spark look for every material (concrete,
  metal, wood, flesh, dirt all identical). Needs a material→profile map later; deliberately
  omitted this stage.
- **Not replicated.** Only the shooter sees their own impacts; other players' shots produce
  nothing locally. A replicated path (server tells nearby clients, or clients predict from
  `WeaponFired` echoes) is deferred.
- **Server-authoritative reconciliation deferred.** The puff is placed at the *client's*
  predicted hit point; if the server's authoritative raycast disagrees (lag, movement,
  anti-cheat rejection) the FX is not corrected or suppressed. Acceptable for a cosmetic,
  but a future networked version should reconcile.
- **Pool size / timing (`POOL_SIZE = 20`, `IMPACT_PART_LIFETIME = 1.0`, emit counts,
  speed/size/lifetime ranges) are first guesses.** Need Studio stress testing at real
  full-auto RPM across framerates — with `POOL_SIZE` rigs and a 1.0 s hold time, sustained
  fire above ~20 rounds/sec starts stealing not-yet-finished rigs (visible pop). Tune
  `POOL_SIZE` up or `IMPACT_PART_LIFETIME` down once the real fire rates are settled.
- **Removed `Constants.BULLET_IMPACT_ENABLED` / `_SIZE` / `_LIFETIME` / `_TRANSPARENCY` /
  `_COLOR`** and their inline single-sphere block in `GunController` — superseded by
  `BULLET_IMPACT_FX`. The separate `DEBUG_BULLET_IMPACT_MARKERS` muzzle-tip marker is
  untouched.

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


## Damage test dummy — Stages 1–6 (new; Stages 2–3 owner-tested, 1 & 4–6 not)

Damage pipeline generalisation + `DummyService` + `RagdollService` rework (1–3) and blood /
hit reactions / debug UI (4–6). See `docs/DAMAGE_TEST_DUMMY_PLAN.md` for the full status
table and the Stages 4–6 debt list. Highlights:

- Stages 4–6 are not Studio-tested; the new `Constants` blocks (particle counts, mark caps,
  flinch angle/duration, ragdoll impulse) are first guesses.
- Hit reactions only render on rigs with no Animator writing `Transform` (the dummy). On
  players the flinch is silently overwritten — the seam for an animation provider is the
  single `applyReaction` function; no provider registry (YAGNI).
- Blood marks are texture-free flat parts (no splatter texture asset was available);
  `BloodEffect` is `FireAllClients` with no distance culling.
- Dev tooling trusts `RunService:IsStudio()`; `Constants.DEV_USER_IDS` is empty until filled.
- Ragdoll impulse was retuned down after the owner's first test (was flinging the rig);
  the retune has not been re-tested.

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
