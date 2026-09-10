# Damage test dummy — plan & status

Developer-only tooling for iterating on weapon damage, hit reactions, blood, ragdolls and
(later) gore. Built incrementally. Gore/dismemberment is **out of scope** for every stage
here — the events are shaped so a future `GoreService` subscribes without editing
`DamageService` or `GunService`.

## Architecture spine

The damage pipeline was made **entity-agnostic and event-emitting**. Everything else hangs
off two BindableEvents, not off the dummy.

| Module | Kind | Role |
|---|---|---|
| `ReplicatedStorage/Modules/Types` | (types) | `DamageType`, `HitRegion`, `DamageInfo`, `DamageRequest` |
| `ReplicatedStorage/Modules/Constants` | (data) | `Combat` block: region multipliers, R6 part map, tags/attributes, dummy + ragdoll tuning |
| `ServerScriptService/Services/CombatEvents` | ModuleScript | BindableEvents `DamageDealt`, `EntityKilled`. **DamageService is the only producer.** |
| `ServerScriptService/Services/DamageRules` | ModuleScript | Pure: part→region, region→multiplier, final-damage math. No Instance access (mirrors `DestructionRules`). |
| `ServerScriptService/Services/DamageService` | ModuleScript | Extended. `ApplyDamage(request)` handles players **and** non-player Humanoids; `Apply()` is now a thin shim over it. Fires the combat events. |
| `ServerScriptService/Services/GunService` | Script | Hit branch generalised: player → pipeline (now with body part), tagged Humanoid entity → pipeline, breakable → `DestructionService`, else ignored. |
| `ServerScriptService/Services/DummyService` | Script | Owns tagged test dummies: registration, per-limb tracking, death→ragdoll, respawn/reset. |
| `ServerScriptService/Services/RagdollService` | ModuleScript | Generalised: `Apply(character, opts)` + `Restore(character)` + impulse preservation. Player path unchanged. |
| `scripts/Build-TestDummy.luau` | helper | One-shot **Studio** script (Command Bar / temp Script) that builds + tags a standard R6 rig. |

### CombatEvents payloads

- `DamageDealt(targetModel: Model?, info: DamageInfo)` — after every accepted, non-zero hit,
  including non-lethal hits and hits on an infinite-health entity (no health removed, event
  still describes the impact).
- `EntityKilled(targetModel: Model?, info: DamageInfo)` — when an accepted hit brings a
  Humanoid to 0. Fires for players too (after `killPlayer` has run) for a consistent death
  signal; the **player** ragdoll is still driven directly by `DamageService.killPlayer`,
  not by this event.

`DamageInfo` carries: target player/model, attacker, `sourceName`, `damageType`, `region`,
`hitPart`, `hitPosition`, `hitDirection`, `baseAmount`, `finalAmount`. That is everything a
future BloodService / HitReactionService / GoreService needs.

## Tags & attributes (no hardcoded instance paths)

| Name | Kind | Meaning |
|---|---|---|
| `BR_DamageDummy` | CollectionService tag | A developer test dummy. `DummyService` owns it. |
| `BR_DamageEntity` | CollectionService tag | Generic "GunService may damage this Humanoid model through the shared pipeline". `DummyService` adds it to every dummy; a future NPC system reuses it. |
| `BR_InfiniteHealth` | attribute (bool) | `DamageService` still fires `DamageDealt` but removes no health and never kills. |
| `BR_ReactionsEnabled` / `BR_BloodEnabled` | attribute (bool) | Reserved for Stage 4/5. Set to `true` on dummies now; unused. |
| `BR_DummyMaxHealth` | attribute (number) | Per-instance `Humanoid.MaxHealth` override. |
| `BR_ManualRespawn` | attribute (bool) | `true` → no auto-respawn after death; reset only. |
| `BR_DummyRuntimeId` | attribute (number) | Set by `DummyService`; links a spawned model to its record across respawns. Internal. |
| `BR_Ragdolled` | attribute (bool) | Set by `RagdollService.Apply`, cleared by `Restore`. Guards double-ragdoll. |

## Remotes

Added in Stage 4 / 6 (registered in `RemoteSetup` + `PROJECT_MAP.md`):

| Remote | Direction | Producer / consumer |
|---|---|---|
| `BloodEffect` | server → all clients | `BloodService` → `BloodController` — `{ hitPosition, hitDirection, intensity, damageType }` |
| `DummyDevCommand` | client → server | `DummyDebugUI` → `DummyService` (dev-gated: Studio or `DEV_USER_IDS`) — `subscribe` / `reset` / `heal` / `infinite` / `blood` |
| `DummyDevState` | server → subscribed dev client | `DummyService` → `DummyDebugUI` — throttled dummy snapshot |

`HitReaction` stays server-side (no remote) — the dummy's physics is server-owned. A remote
is only needed once flinches are applied to player characters.

The blood global kill switch is **not** a remote — it is the `BR_BloodGlobalEnabled`
attribute on `ReplicatedStorage`. `DummyService` sets it, `BloodService` and
`BloodController` both read it live.

## Stage status

| Stage | Scope | Status |
|---|---|---|
| 1 | Damage spine (Types, Constants, CombatEvents, DamageRules, DamageService, GunService) | **Code complete — not Studio-tested** |
| 2 | DummyService + tag registration + limb state + Humanoid death + Build-TestDummy | **Owner-tested in Studio: works** |
| 3 | RagdollService generalisation + `Restore` + impulse; DummyService death→ragdoll→respawn | **Owner-tested: worked, ragdoll flew too far → impulse retuned (scale 45→1.5, clamp 4000→200, now applied to Torso not the hit limb). Retune not yet re-tested.** |
| 4 | BloodService + BloodController + `BloodEffect` + caps + global disable | **Code complete — not Studio-tested** |
| 5 | HitReactionService (procedural flinch, one swap seam) | **Code complete — not Studio-tested** |
| 6 | DummyDebugUI + `DummyDevCommand` / `DummyDevState` + dev gating (HP / last hit / limbs / reset / heal / infinite / blood / hitbox viz) | **Code complete — not Studio-tested** |

## How to test Stages 1–3 in Studio

1. Sync the code in (Rojo full project, or MCP push — the Rojo *plugin* connection is the
   current blocker, see the reload work).
2. Run `scripts/Build-TestDummy.luau` once from the Command Bar. A `DamageDummy` appears in
   front of the first SpawnLocation, tagged `BR_DamageDummy`. Reposition it as desired.
3. Play. Expected server Output:
   - `[DummyService] Registered dummy … | HP 100`
   - On shots: `[GunService] … hit entity DamageDummy (Torso) for 30 base dmg` and
     `[DummyService] DamageDummy took 30.0 dmg to Torso (AKS74) | HP 70/100`
   - Head shots log `(Head)` and `60.0 dmg` (×2 multiplier).
   - On the killing shot: `[DamageService] … killed by …`, `[RagdollService] Ragdoll
     applied to entity DamageDummy`, `[DummyService] … respawning in 3 s`, then a fresh
     dummy at the spawn pose.
4. PvP regression: player-vs-player damage numbers must be unchanged; a head hit now does
   ×2 (this is the one intentional PvP behaviour change — see debt below).

## Stages 4–6 — how they hang together

Everything still keys off `CombatEvents` and attributes; no system knows about the dummy.

- **Blood (Stage 4).** `BloodService` (server Script) listens to `DamageDealt`; if the hit
  has a position, `Constants.BLOOD_ENABLED` is on and neither the per-model
  `BR_BloodEnabled` nor the global `BR_BloodGlobalEnabled` (ReplicatedStorage attribute) is
  false, it computes `intensity = clamp(finalAmount / BLOOD_REFERENCE_DAMAGE, MIN, 1)`,
  rate-limits per target, and fires `BloodEffect`. It creates **zero** instances.
  `BloodController` (client) owns a fixed pool of `BLOOD_POOL_SIZE` particle bursts and a
  ring buffer of `BLOOD_MAX_MARKS` texture-free surface marks (raycast around the hit,
  flat parts flush to whatever they hit), each with a lifetime; a Heartbeat retires
  expired bursts/marks. Flipping `BR_BloodGlobalEnabled` to false clears everything on the
  spot.
- **Hit reactions (Stage 5).** `HitReactionService` (server Script) listens to
  `DamageDealt`; for a live, non-ragdolled model with `BR_ReactionsEnabled`, it writes a
  decaying additive offset to one `Motor6D.Transform` picked by
  `Constants.REACTION_REGION_JOINTS[region]`, strength from
  `finalAmount / REACTION_REFERENCE_DAMAGE`, direction = the shot's travel vector resolved
  into the rig's frame. A Heartbeat lerps it back to identity over `REACTION_DURATION`;
  every offset also has a hard `deadline` so it can never stick. It never touches C0/C1,
  `Motor6D.Enabled`, `PlatformStand` or `WalkSpeed`. `applyReaction` is the one seam to
  swap for animation-driven flinches later.
- **Debug UI (Stage 6).** `DummyDebugUI` (client, `Controllers/UI/`) builds nothing unless
  `RunService:IsStudio()` or the local UserId is in `Constants.DEV_USER_IDS`. It
  `subscribe`s over `DummyDevCommand`, renders throttled `DummyDevState` snapshots (per
  dummy: HP, last hit, per-limb pool, INF / RAGDOLL flags), and has Reset / Heal /
  Infinite / Blood / Hitboxes buttons. Hitbox viz is drawn locally with `SelectionBox`
  adornments coloured per region — no server instances, nothing sent.

## How to test Stages 4–6 in Studio

- **Blood:** shoot the dummy → a short red burst at the impact point and a few flat dark
  marks on nearby surfaces. Hold full-auto → mark count tops out at `BLOOD_MAX_MARKS`
  (default 40) and stops growing; oldest marks disappear first. Toggle **Blood** in the
  debug panel → new hits produce nothing and existing marks clear immediately.
- **Reactions:** each hit gives a short directional flinch of the hit limb / torso that
  settles back within ~0.3 s. Rapid fire stacks toward `REACTION_MAX_STACK` then decays.
  Nothing sticks after you stop firing; the dummy still walks / dies / ragdolls normally.
- **Debug UI (Studio only by default):** panel top-right. Watch HP / last hit / limb
  numbers update as you fire. **Reset** respawns the dummy at its spawn pose, **Heal**
  refills HP, **Infinite** stops HP dropping (blood + reactions still play), **Hitboxes**
  outlines each R6 part in its region colour.

## Known gaps / debt (Stages 1–3)

- **Nothing is Studio-tested.** No Lune coverage yet either (no Lune in this environment);
  `DamageRules` is pure and unit-testable — a `scripts/Test-Damage.luau` should follow.
- **Reset == respawn a fresh clone.** A dead R6 Humanoid cannot be reliably revived, and the
  owner wants real Humanoid death, so `DummyService` replaces the model from a template
  captured at first registration. Costs one retained template clone per live dummy.
- **PvP headshots now do ×2.** The shared pipeline carries the hit part for players too, so
  `Constants.DAMAGE_REGION_MULTIPLIERS` applies to PvP, not just dummies. Intentional and
  desirable, but it *is* a live gameplay change — set every region to `1.0` to disable.
- **`DAMAGE_MAX_PER_HIT` (500) now clamps the legacy `Apply` path.** Immaterial (weapons do
  ≤30, players have 100 HP) but it is a behavioural difference from the old un-clamped path.
- **Self-hit no longer calls `DestructionService:ApplyHit`.** The old hit branch did (a
  harmless no-op, since a character part is never a registered breakable). New branch skips
  it. No functional change.
- **Limb health is tracked but does nothing.** It does not gate death and there is no
  visible effect until a `GoreService` consumes it.
- `DamageService:Heal` / `:SetInvincible` are landed early (Stage 6 needs them) and are
  currently unused by any caller.
- `DummyService` is a server-lifetime Script; its two service-level connections are tracked
  but never disconnected (same as `GunService` / `TeamService`). Per-dummy connections
  *are* disconnected on unregister/respawn.
- A one-frame window exists between a respawned clone entering `workspace` and
  `DummyService` priming its Humanoid (`BreakJointsOnDeath`, health). Invisible in practice.
- Server-side reload duration lock is still absent (pre-existing, unrelated — see other
  debt entries).

## Known gaps / debt (Stages 4–6)

- **Nothing in Stages 4–6 is Studio-tested.** Values in the new `Constants` blocks
  (particle counts, mark caps, flinch angle/duration, impulse) are first guesses.
- **Hit reactions only show on rigs with no Animator writing `Transform`** — i.e. the test
  dummy. On a player character the Animate script overwrites `Transform` every frame, so
  the flinch is invisible. That is the intended boundary; the fix is an animation-based
  provider swapped in at `applyReaction`, deferred until reactions are wanted on players.
- **The reaction "provider swap" is a documented one-function seam, not a registry.** No
  `SetProvider` API yet — `HitReactionService` is a self-starting Script, so exposing one
  would mean converting it to a module + a server bootstrap. Deferred (YAGNI until a second
  provider exists).
- **Blood marks are texture-free flat parts, not decals.** No blood-splatter texture asset
  was available; `Constants.BLOOD_COLOR` parts read fine but a real decal/texture would
  look better. Drop-in later via a texture constant.
- **Blood `BloodEffect` is `FireAllClients`** with no distance culling — fine for a test
  tool, wasteful at scale. Add a range filter (send only to clients near the hit) before
  this is used in real combat.
- `BloodService` per-target rate-limit table is pruned on a 5 s Heartbeat sweep; a
  destroyed model can linger in it for up to that long (bounded, not a true leak).
- `DummyDebugUI` dev commands act on **all** registered dummies at once (no per-dummy
  targeting / "the one you're looking at"). Fine for the expected 1–2 dummies.
- Dev gating trusts `RunService:IsStudio()` on the client for building the UI and on the
  server for accepting commands; in a live place only `Constants.DEV_USER_IDS` gates it,
  and that list is empty until filled in.
- `HitReactionService` / `BloodService` service-level connections are tracked but never
  disconnected (server-lifetime Scripts, same pattern as `GunService`).
