# Destruction system — design and implementation status

Owner-confirmed direction (2026-09-08, recorded in AI_DECISIONS.md): small-scale building destructibility (not full Teardown-scale voxel simulation), explosives able to blow open buildings/walls, and doors that break into shootable pieces the way Rainbow Six Siege destroys doors (individual panels/segments come off independently, not one binary broken state).

## Status (2026-09-08, session 3)

- **Built this pass, bullet-driven, no explosives:** `src/ServerScriptService/Services/DestructionService.lua` + `DestructionRules.lua`, wired into the **main game's actual `GunService.server.lua`** (not the isolated Mercer District prototype). Any non-player raycast hit is now checked against a registered breakable. See "What's implemented" below.
- **Explicitly deferred, per owner instruction:** explosive/AoE damage. Not started. Still needs the new-remote conversation flagged below before any work begins.
- Not installed in Studio, not committed, not Studio-verified — same status as the animation-lock patch in RELOAD_DIAGNOSIS.md. `src/ReplicatedStorage/Modules/Constants.lua` and `src/ServerScriptService/Services/GunService.server.lua` now intentionally differ from the captured baseline too; see PROJECT_MAP.md.
- Offline test `scripts/Test-Destruction.luau` was written (mirrors the already-proven `prototypes/CityDistrict/TestDestruction.luau` assertions) but could not be executed in this environment — Lune is not installed here. Verified instead by manual trace of the extracted-chunk free-variable mechanics, the same way `scripts/Test-Reload.luau` was re-verified this session. Run it with Lune before trusting it as a passing suite.

## What already existed (reusable reference, unchanged this pass)

`prototypes/CityDistrict/DestructionService.lua` + `DamageRules.lua` + `Constants.lua`, offline-tested, server-authoritative, wired into a **test-only** fork of GunService inside the isolated Mercer District copy. This is what the main-game module below was ported from — same validation logic, same debris/reset mechanics, retargeted from one isolated test subtree to the whole live workspace.

## What's implemented now (main game, bullet-driven, no explosives)

- `src/ServerScriptService/Services/DestructionRules.lua` — pure validation, ported near-verbatim from the prototype's `DamageRules.lua`.
- `src/ServerScriptService/Services/DestructionService.lua` — registers any `Anchored` `BasePart` anywhere in the live `workspace` tagged with `BR_BreakableProfile` (currently one profile, `Wood`, health 80 — 3 hits from AR15's 28 damage, matching the prototype's already-tuned "Timber" value). `DestructionService:ApplyHit(part, damage, position, direction)` validates the hit point against the part's oriented bounds, subtracts damage, and on reaching 0 health sets `CanCollide/CanQuery/CanTouch = false` and `Transparency = 1` server-side, scatters capped/timed cosmetic debris, and fires the pre-existing (unused until now) `PartDestroyed` RemoteEvent as a hook for a future client VFX listener — no new remote was added. `DestructionService:Reset()` restores every registered part on the existing PREP phase event, mirroring `DamageService`'s health reset.
- `src/ServerScriptService/Services/GunService.server.lua` now calls `DestructionService:ApplyHit(...)` with its own already-validated raycast result whenever a shot hits something that isn't a player — this is what actually gives per-part door/wood destruction; no explosive/AoE path exists.
- **This delivers pillars 1 and 3 at the code level already** (see below) — a door or wood structure authored in Studio as several independently `BR_BreakableProfile`-tagged parts already breaks piece-by-piece today, no further server logic needed. What remains for both is Studio content authoring, not code.
- **Pillar 2 (explosives) is untouched, on your instruction.** No `ApplyExplosion`-style radius/falloff path, no grenade/charge object, no new remote.

## Closing the remaining gap, pillar by pillar

**1. Small-scale localized destruction ("Teardown, much smaller").** Code-complete. What's left is **Studio content-authoring work**: chunking a destructible wall/room into several discrete pre-modeled pieces (not one monolithic wall part) and tagging each with `BR_BreakableProfile = "Wood"`. Watch `DESTRUCTION_MAX_REGISTERED_PARTS` (currently 800) as chunking density increases — Logger will warn if it's exceeded.

**2. Explosives blowing open buildings/walls — deferred.** Still needs a genuinely new code path: `ApplyHit` only ever damages the one part a raycast hit. An explosion needs radius+falloff damage against every registered breakable part within range — e.g. `DestructionService:ApplyExplosion(position, radius, maxDamage)` iterating registered parts, computing falloff by distance, and (to avoid damage passing through intact walls) an occlusion/line-of-sight check per candidate part. This also needs a *trigger*: a grenade/placed-charge object with a fuse, which is new gameplay that does not exist yet. **That almost certainly needs a new RemoteEvent** — per PROJECT_RULES.md, no new remote gets added without your explicit go-ahead, which you have not given for this piece.

**3. Siege-style door destruction.** Code-complete, same reasoning as pillar 1 — the service treats every `BasePart` independently already, so a door authored as several tagged pieces (e.g. frame, left panel, right panel, maybe a hinge piece) already breaks piece-by-piece. What's left is **Studio authoring work**, one door type at a time: modeling/splitting each destructible door into its separate parts and tagging them.

## Decisions still open

- **New remote(s) for explosives.** Explicitly deferred by you this pass — revisit when you want to start on pillar 2.
- **Destructibility scope.** Which rooms/walls/doors in the actual game map get chunked destructibility vs. stay permanent structural cover — mirrors the existing intact-vs-breakable split CityDistrict already made for its own map, but needs a fresh call for whatever map the core game uses.
- **Asset authoring load.** Chunked walls and multi-piece doors are real Studio modeling/tagging work, owned by Studio per the project's ownership table — the server logic that consumes the `BR_BreakableProfile` attribute is done; the parts and tags themselves are not.
- **Performance/replication budget.** Denser chunking plus multi-piece doors means far more simultaneous state changes and debris than the isolated prototype's 132-piece / 400-part numbers were tuned for; `DESTRUCTION_MAX_REGISTERED_PARTS` was raised to 800 and the debris cap to 64 as a starting guess, not a measured budget — revisit after Studio testing.
