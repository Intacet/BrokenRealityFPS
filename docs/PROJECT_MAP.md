# Project map

## Known state

- The initial local workspace contained no existing code or Git repository.
- Local branch: main. Origin: https://github.com/Intacet/BrokenRealityFPS.git. See GITHUB_MIGRATION.md for preservation of the previous branch/history and the upload record.
- Verbatim source capture contains 216 scripts. src/ now contains unchanged copies of 32 main scripts; pilot.project.json targets Logger only and default.project.json targets those 32 scripts. Both passed local mapping validation; neither has connected to Studio.
- Saved place and script hierarchy are inventoried below. Rojo CLI/plugin are 7.6.1; Lune is 0.10.5. Published place ID remains unconfirmed.
- Backup received: ../StudioBackups/BrokenReality_preRojo.rbxl (1,379,020 bytes). A separate migration_test copy has an identical SHA-256: 99ae27dd2262a6d5441873d60dfc356081f2521239683e2027ef3dae8023b4c8.
- All 216 source files match source decoded from the saved backup. The owner reported the test copy looks good. Exact test steps, off-device backup, and post-sync Studio checks remain pending.
- See SCRIPT_INVENTORY.md and SCRIPT_INVENTORY.json for extracted paths, classes, properties, children, attributes, tags, source hashes, and archive filenames.
- Saved script counts: ReplicatedStorage 8; ServerScriptService 11; StarterPlayer 13; Workspace 184. No saved remote instances were found; runtime setup must be inspected.
- Existing main folders: ReplicatedStorage/Modules, ServerScriptService/Services, StarterPlayer/StarterPlayerScripts/Controllers. These are candidates for review, not approved mappings.
- Existing Logger and Constants modules are present in ReplicatedStorage/Modules.
- RemoteSetup source explicitly creates 15 RemoteEvents and one RemoteFunction at runtime; zero saved remote instances does not mean the prototype has no networking.
- R6 and the direction in CURRENT_GAME_DIRECTION.md are owner-confirmed, not locally inspected.

## Isolated city prototype — 2026-09-08

New source is under prototypes/CityDistrict; see its README for build and playtest steps. Mercer District is a fictional Richmond-inspired six-block map with 26 buildings, ground-floor routes, three objective areas, 2,494 parts, and 132 breakable windows/barriers/crates. Upper floors remain facade shells.

Generated artifacts are outside the code repo in ../CityDistrict. BrokenReality_CityTest.rbxl archives the original Workspace content inside that test copy only. The immutable preRojo backup and migrated src files remain unchanged. The test copy has its own GunService destruction integration and daylight settings. Neither Rojo configuration maps this feature; do not connect the baseline full project to the city test.

22 offline checks passed with mocked engine events/physics ownership. The assistant observed the test place opening and entering ACTIVE, but user-confirmed destruction, multiplayer, route balance, and performance verification remain pending.

## Ownership

| Content | Source of truth now | Planned handoff |
| --- | --- | --- |
| Maps, terrain, models, lighting, spawns | Studio | None for now |
| R6 rigs, animations, viewmodels, weapons/Tools and their assets | Studio | None for now |
| UI objects, sounds, effects, attachments, constraints, packages | Studio | None for now |
| Existing remotes and non-code configuration instances | Studio | None without separate review |
| Existing scripts | Studio | VS Code/Rojo individually after verified migration |
| Rules and migration records | This project | Git/GitHub backup |

## Script inventory — fill before mapping

For each Script, LocalScript, and ModuleScript record:

| Exact Explorer path | Class | Enabled/Disabled and RunContext | Attributes/tags/children | Dependencies and callers | Local file | Copy compared | Sync approved |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pending Studio inventory | Unknown | Unknown | Unknown | Unknown | Unassigned | No | No |

Record duplicate sibling names and names that cannot map cleanly to Windows filenames. Record script.Parent chains, require paths, WaitForChild paths, object references, asset IDs, and existing remote paths. Record package links and whether scripts exist only at runtime.

Inspect ServerScriptService, ReplicatedStorage, ServerStorage, StarterPlayerScripts, StarterCharacterScripts, StarterGui, StarterPack, ReplicatedFirst, and scripts nested anywhere in Workspace/models/Tools/viewmodels. Locations are inspection targets, not assertions that scripts exist there.

## Proposed local folders — not Studio mappings

- import/studio-snapshot/: verbatim source capture organized by exact service and hierarchy; never sync this folder.
- src/: only reviewed scripts promoted for migration. Final subfolders follow the verified hierarchy; no guessed server/client/shared relocation.
- docs/: rules, inventory, decisions, and verification records.

See ROJO_REVIEW.md for the locally validated individual-script mappings. No live handoff has occurred; all scripts remain Studio-authoritative until trial verification. Scripts with children or unusual execution settings require a reviewed representation before migration.
