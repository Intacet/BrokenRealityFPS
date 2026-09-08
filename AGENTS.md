# Broken Reality — instructions for AI tools

Read docs/CURRENT_GAME_DIRECTION.md, docs/PROJECT_RULES.md, and docs/PROJECT_MAP.md before proposing changes.

When switching between GPT and Claude, also read docs/AI_WORKFLOW.md, docs/AI_HANDOFF.md, and docs/AI_DECISIONS.md. Use main for current work; only one assistant edits a shared checkout at a time. Record a handoff before switching tools.

- Broken Reality is currently R6, not R15.
- SCAR references are outdated unless found in current Studio scripts. The old R15 animation plan is not current.
- Current focus: custom R6 movement, first-person viewmodels, AKS-74 / AR-style weapons, and PvPvE zone shooter foundations.
- Studio remains the source for maps, models, animations, viewmodels, lighting, spawns, and other Studio assets for now.
- VS Code/Rojo will manage scripts going forward, individually after verified migration. Until then, Studio is authoritative for existing scripts too.
- Current stage: owner authorized diagnosing and fixing the reload/shooting lock, then re-raised the same symptom after the first patch was never installed or committed. The recovery patch in src (ViewModelController + Constants) now covers reload, FP equip, and ADS-in/out — same class of bug (a one-shot AnimationTrack whose Stopped signal never fires, freezing dependent state). See docs/RELOAD_DIAGNOSIS.md. Imports and original Studio backups remain the baseline. City work remains isolated under prototypes/CityDistrict.
- Owner then confirmed a destruction-system direction and authorized building the wood/door pillars now (small-scale destructibility, R6-Siege-style multi-piece doors), explicitly holding explosives back for later. `src/ServerScriptService/Services/DestructionService.lua` + `DestructionRules.lua` are now built and wired into the main game's GunService.server.lua — bullet-driven only, no explosive/AoE path. No new remote was added (the pre-existing, previously-unused PartDestroyed event now has a producer). See docs/DESTRUCTION_SYSTEM_PLAN.md. Do not start the explosives pillar without a fresh explicit go-ahead — it needs a new RemoteEvent.
- Live Rojo handoff remains unverified; do not assume local source changes (animation patch or destruction system) are installed in Studio.
- Never replace the existing place with a code-only Rojo build. Never map entire asset-bearing services or move scripts merely to fit a proposed layout.
- Before any first connection, inventory paths/properties/dependencies, compare copied source, review every mapping, and confirm a verified backup and disposable test copy exist.
- Use Luau strict mode for new or deliberately edited scripts. Preserve imported source verbatim first; record legacy violations instead of silently fixing them.
- No print() or warn(); use a Logger module later. No wait() or spawn(); use task.wait() and task.spawn().
- Gameplay constants belong in Constants.lua. Existing Constants and Logger modules were found in the saved place under ReplicatedStorage/Modules; review/reuse them, do not create duplicates.
- Server owns game state. Clients do not decide damage, health, hits, money, inventory, or extraction results.
- No new remotes without explicit request. Store and clean up RBXScriptConnections.
- Keep tasks small and staged; do not build multiple systems in one pass. No global formatting unless requested.
- Never claim Studio verification without the user's reported result. Separate local checks from Studio tests.
- Update the project map, debt log, and changelog when confirmed facts change. Mark unknowns explicitly; do not invent current implementations.
