# AI handoff

Update this file at the end of each completed task so GPT/Codex and Claude start from the same verified state. Record facts and test results, not plans presented as completed work.

## Current state — 2026-09-08

- Work from `main`, which is also the GitHub default branch. The branch `claude/create-claude-md-AqEm8` is preserved history and is not the active migration branch.
- The working Studio game is R6. Current direction is a gritty FPS / PvPvE zone shooter with custom R6 movement, AKS-74 / AR-style first-person viewmodels, and reality-break containment objectives.
- SCAR and R15 references are historical unless a current source dependency is found and documented.
- Studio remains authoritative for maps, models, animations, viewmodels, lighting, spawns, and the current live place. Existing scripts remain Studio-authoritative until each Rojo handoff is verified.
- An immutable pre-Rojo place backup exists outside Git. Its recorded SHA-256 is `99ae27dd2262a6d5441873d60dfc356081f2521239683e2027ef3dae8023b4c8`.
- 216 Studio scripts were captured. The 32 core files in `src/` match the captured baseline. Do not silently modernize imported source during migration.
- Rojo CLI 7.6.1 matches the observed Studio plugin. `pilot.project.json` maps only `ReplicatedStorage/Modules/Logger`; `default.project.json` maps 32 reviewed core scripts. No live-place handoff is confirmed.
- The separate Mercer District prototype lives in `prototypes/CityDistrict/`. Its generated test place is outside Git. It passed 22 offline destruction checks and opened into an ACTIVE Studio round. Multiplayer destruction, route balance, performance, and user-confirmed Studio verification remain pending.
- Reload/equip/ADS animation locks: owner re-reported the same reload/shooting symptom (patch had been written but never installed or committed). Local ViewModelController now applies the same bounded-recovery pattern (Heartbeat watchdog, tracked connections, timeout Constants) to three places: reload (unchanged from the prior pass, re-verified by manual trace against `scripts/Test-Reload.luau`), FP equip (`PlayEquipAnimation`), and ADS-in/ADS-out (`SetAiming`) — the ADS case matters because a stuck ADS state silently routes every future shot to a fire animation that no-ops, so the gun keeps firing server-side with no visible animation. None of this is installed in Studio, none is committed, and none is Studio-verified. Visual animation asset access/rig compatibility remain unconfirmed. See RELOAD_DIAGNOSIS.md ("Extended scope" section) and TECHNICAL_DEBT.md for two related gaps left unpatched (TP equip skip, enterRun stuck-while-sprinting) plus the pre-existing server reload-lock gap.
- Destruction system: owner confirmed the direction (small-scale destructibility, explosives, R6-Siege-style doors) then explicitly authorized building the wood/door pillars now while holding explosives back. Built this session: `src/ServerScriptService/Services/DestructionService.lua` + `DestructionRules.lua`, wired into the main game's actual `GunService.server.lua` (not the isolated Mercer District test copy) — any non-player raycast hit is checked against parts tagged `BR_BreakableProfile`. No new remote (reuses the pre-existing, previously-unused `PartDestroyed` event as a VFX hook). Explosive/AoE damage is untouched, per instruction. See `docs/DESTRUCTION_SYSTEM_PLAN.md` for full status and what remains (Studio content authoring: tagging actual doors/wood as multiple breakable pieces — no code work is blocking that).
- VS Code has Codex, Claude Code, Rojo, and Luau language-server extensions installed. The repository provides safe start/review tasks and a tracked workspace file.

## Next safe action

1. Manually install the edited files into Studio (no verified live Rojo connection exists yet): `src/ReplicatedStorage/Modules/Constants.lua`, `src/StarterPlayer/StarterPlayerScripts/Controllers/ViewModelController.lua` (reload/equip/ADS fix), and `src/ServerScriptService/Services/GunService.server.lua` + the two new files `DestructionService.lua`/`DestructionRules.lua` (wood/door destruction). Reload/equip/ADS-test per RELOAD_DIAGNOSIS.md's steps; report Output messages containing "recovered" if the symptom persists — that means the underlying animation asset, not client logic, is the remaining blocker.
2. To actually see wood/door destruction in Studio, some parts need `BR_BreakableProfile = "Wood"` tagged on them first (e.g. a test door split into a couple of parts) — the system registers zero parts and does nothing until content exists to tag. Shoot a tagged part, confirm it breaks/scatters debris/blocks nothing, then confirm PREP resets it. Report `Logger.warn` output if a part doesn't break as expected.
3. Separately: use the disposable `BrokenReality_migration_test.rbxl` copy for the Logger-only Rojo pilot described in `docs/ROJO_REVIEW.md`. Before connecting, confirm no Studio script is newer than the saved capture. Do not connect Rojo to the important working place or to `BrokenReality_CityTest.rbxl`.
4. Explosives (deferred): when the owner is ready, the plan in `docs/DESTRUCTION_SYSTEM_PLAN.md` pillar 2 needs a new RemoteEvent for grenade/charge triggering — get explicit approval for that specifically before adding it.
5. Run `scripts/Test-Destruction.luau` and `scripts/Test-Reload.luau` with Lune once it's available in an environment that has it — neither has actually been executed yet, only manually traced.

## Handoff template

When finishing a task, replace the current-state date and add:

- Objective completed:
- Files changed:
- Local checks completed:
- Studio checks reported by owner:
- Unverified behavior:
- Commit and branch:
- Next safe action:
