# Broken Reality — instructions for AI tools

Read docs/CURRENT_GAME_DIRECTION.md, docs/PROJECT_RULES.md, and docs/PROJECT_MAP.md before proposing changes.

- Broken Reality is currently R6, not R15.
- SCAR references are outdated unless found in current Studio scripts. The old R15 animation plan is not current.
- Current focus: custom R6 movement, first-person viewmodels, AKS-74 / AR-style weapons, and PvPvE zone shooter foundations.
- Studio remains the source for maps, models, animations, viewmodels, lighting, spawns, and other Studio assets for now.
- VS Code/Rojo will manage scripts going forward, individually after verified migration. Until then, Studio is authoritative for existing scripts too.
- Current stage: documentation and migration planning only. Do not write or edit gameplay code, create remotes, generate a Rojo project, or connect Rojo yet.
- Never replace the existing place with a code-only Rojo build. Never map entire asset-bearing services or move scripts merely to fit a proposed layout.
- Before any first connection, inventory paths/properties/dependencies, compare copied source, review every mapping, and confirm a verified backup and disposable test copy exist.
- Use Luau strict mode for new or deliberately edited scripts. Preserve imported source verbatim first; record legacy violations instead of silently fixing them.
- No print() or warn(); use a Logger module later. No wait() or spawn(); use task.wait() and task.spawn().
- Gameplay constants belong in Constants.lua. Do not create Constants.lua or Logger until the relevant code stage is requested.
- Server owns game state. Clients do not decide damage, health, hits, money, inventory, or extraction results.
- No new remotes without explicit request. Store and clean up RBXScriptConnections.
- Keep tasks small and staged; do not build multiple systems in one pass. No global formatting unless requested.
- Never claim Studio verification without the user's reported result. Separate local checks from Studio tests.
- Update the project map, debt log, and changelog when confirmed facts change. Mark unknowns explicitly; do not invent current implementations.
