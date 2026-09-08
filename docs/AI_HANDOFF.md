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
- The reload animation still does not visibly play according to the owner. It is unresolved and was not changed by the city prototype.
- VS Code has Codex, Claude Code, Rojo, and Luau language-server extensions installed. The repository provides safe start/review tasks and a tracked workspace file.

## Next safe action

Use the disposable `BrokenReality_migration_test.rbxl` copy for the Logger-only Rojo pilot described in `docs/ROJO_REVIEW.md`. Before connecting, confirm no Studio script is newer than the saved capture. Do not connect Rojo to the important working place or to `BrokenReality_CityTest.rbxl`.

## Handoff template

When finishing a task, replace the current-state date and add:

- Objective completed:
- Files changed:
- Local checks completed:
- Studio checks reported by owner:
- Unverified behavior:
- Commit and branch:
- Next safe action:
