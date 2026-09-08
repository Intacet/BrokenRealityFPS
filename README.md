# Broken Reality

R6 Roblox FPS / PvPvE project. Current direction: a large map with a team sent to stabilize breaks in reality, opposed by a still-being-defined citizens/defenders team, with people and creatures in the area.

## Start here

- [AI instructions](AGENTS.md)
- [Current direction](docs/CURRENT_GAME_DIRECTION.md)
- [Project map](docs/PROJECT_MAP.md)
- [Rojo review and next steps](docs/ROJO_REVIEW.md)

Studio remains authoritative for assets and for scripts until their migration is verified. The saved Studio baseline contains 216 scripts; all were captured unchanged in import/studio-snapshot/. The 32 main scripts also exist under src/ with their original Studio hierarchy.

The Logger-only pilot is the first Rojo trial. The full configuration must wait for the pilot result. Do not replace the Studio place with a code-only build. Neither configuration has been connected yet.

## History

The earlier work remains on branch `claude/create-claude-md-AqEm8`, last inspected at `04a445df23361187116ab5b0e96686cf2236df4e`. All 32 main scripts matched that commit byte-for-byte when compared with the saved Studio place. This migration changes organization and setup, not gameplay code.

The older configuration, roadmaps, technical debt, and place snapshots remain available in Git history. Their plans need review against the owner's current instructions before reuse. Current code/docs work should use `main`; GitHub's default branch may still point to the older branch until separately changed.

## Local tools

The current laptop has verified Rojo 7.6.1 under .tools/rojo.exe, matching the installed Studio plugin; that binary is excluded from Git. A fresh clone needs the matching official CLI installed at that path to use the VS Code pilot task. The Studio plugin and separate place backups are also outside this repository. Git does not replace off-device backups of Studio assets.
