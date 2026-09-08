# AI decision log

This file records durable project decisions shared by GPT/Codex and Claude. Add a dated entry only when the owner confirms a direction or a migration boundary changes.

| Date | Decision | Consequence |
| --- | --- | --- |
| 2026-09-07 | Broken Reality uses R6. | Do not propose R15 rigs or revive the old R15 animation plan. |
| 2026-09-07 | SCAR references are historical unless current source proves a dependency. | Current weapon/viewmodel work uses AKS-74 / AR-style terminology and assets. |
| 2026-09-07 | The game direction is a gritty FPS / PvPvE zone shooter. | The inherited attacker/defender rounds are prototype context, not the final game structure. |
| 2026-09-07 | Studio owns maps, models, animations, viewmodels, lighting, spawns, and other Studio assets for now. | Rojo mappings must stay script-specific and preserve unknown instances. |
| 2026-09-07 | Existing scripts move to VS Code/Rojo only through staged verification. | Start with the Logger-only disposable-copy pilot; do not connect the important place yet. |
| 2026-09-08 | `main` is the active GPT/Claude workflow branch. | Preserve `claude/create-claude-md-AqEm8` as history; do not switch to it for current work. |
| 2026-09-08 | First district style is brick rowhouses, corner shops, warehouses, and alleys. | Continue Mercer District as an isolated route/destruction prototype until Studio tests are confirmed. |
| 2026-09-08 | Only one assistant edits the shared checkout at a time. | Commit a reviewed checkpoint and update `AI_HANDOFF.md` before switching tools. |
| 2026-09-08 | Destruction system direction: small-scale (not full Teardown-scale) building destructibility; explosives can blow open buildings/walls; doors break into shootable pieces R6-Siege-style (individual panels/segments, not one binary broken state). | Supersedes a plain graduate-vs-redesign choice. `prototypes/CityDistrict/DestructionService.lua` is a starting reference (per-part health/attributes, capped cosmetic debris, PREP reset), not a drop-in — it currently only supports one break state per part. See `docs/DESTRUCTION_SYSTEM_PLAN.md`. |
| 2026-09-08 | Owner authorized building the wood/door destruction pillars now; explosives explicitly held back for a later pass. | `src/ServerScriptService/Services/DestructionService.lua` + `DestructionRules.lua` built and wired into the main game's `GunService.server.lua` (bullet-driven, no new remote — reuses the existing raycast). Explosive/AoE damage remains unstarted; a new RemoteEvent for it needs a separate explicit go-ahead. Not installed in Studio, not committed. See `docs/DESTRUCTION_SYSTEM_PLAN.md`. |
