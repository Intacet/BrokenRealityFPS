# Rojo migration review — 2026-09-07

## Status

The owner reported that the saved test place looks good after being asked to inspect and test it. This is owner-reported baseline confirmation, not agent-observed verification, and not a post-Rojo test. Exact movement/weapon checks were not individually reported.

Studio already has Rojo 7.6.1 installed, verified through its Plugins menu and panel. The local CLI at .tools/rojo.exe now matches 7.6.1 (excluded from Git). Its official release archive SHA-256 was verified: e1c9a78193c609720f3afb38057d3909ed483ecbf5e9e3541313ba0dcbc4f1f8. Both projects also built successfully with 7.6.1.

An earlier 7.7.0 plugin download remains separately at ../RojoPlugin/Rojo.rbxm; do not install it over the working 7.6.1 setup. No plugin changes were needed. The Logger pilot server has been started; connection and post-sync verification remain pending.

## Scope

| Project | Existing targets | Use |
| --- | --- | --- |
| pilot.project.json | ReplicatedStorage/Modules/Logger only | First test-copy trial |
| default.project.json | 8 Modules, 11 Services, 13 Controllers/UI scripts | Later, after pilot verification |

All sources in src/ are byte-identical to the saved baseline. ROJO_SOURCE_MAP.json records each file's exact original path and source hash. No script was moved within Studio. The full project maps individual source files, not whole filesystem directories. Existing ancestors are declared with their verified classes. Unknown instances are explicitly preserved at every ancestor and script node. Script enabled states and Legacy RunContext are preserved. The 32 targets have no child instances, tags, or attributes in the backup.

Workspace, maps, terrain, lighting, models, animations, viewmodels, Tools, UI assets, remotes, and all 184 Workspace scripts are omitted. The existing RemoteSetup source is copied unchanged; configuration does not create remotes. Existing gameplay scripts can still change lighting, world objects, or create remotes when played, exactly as before; omission from Rojo does not prevent their normal runtime behavior.

## Local validation completed

- Both projects built successfully with official Rojo 7.7.0.
- Every target and structural ancestor resolved uniquely in the saved place with matching class.
- Every source matched the saved place; mapped execution properties matched.
- Every affected node explicitly preserves unknown instances.
- Full configuration: 32 source targets and 9 structural ancestors. Pilot: 1 source target and 3 structural ancestors.
- Build artifacts are under work/, outside the project. They are code-only validation artifacts and MUST NOT replace the real place.

These checks establish the intended sync scope, not observed plugin reconciliation. Any source edits made in Studio since the backup must be recaptured before syncing. No place-ID restriction has been added because the intended runtime PlaceId is unconfirmed; do not use a place ID inferred only from the filename. The server binds to 127.0.0.1.

## Next guided step

1. Use the existing observed 7.6.1 Studio plugin with the matching local CLI. Do not install the separately downloaded 7.7.0 plugin over it. Recheck the installed version if Studio has changed.
2. Reopen Studio if needed and open only BrokenReality_migration_test.rbxl for the trial. Keep play stopped.
3. In VS Code, run the task named "Broken Reality: Start Logger pilot (test copy only)". This starts the local server; Studio still requires a separate connection.
4. In Studio's Rojo plugin, connect to localhost:34872. Review any proposed-change display: only the existing ReplicatedStorage/Modules/Logger source may be managed, and it should already match. Cancel for any unexplained deletions, replacements, or duplicates. If no preview is offered, trial only on the disposable copy and inspect immediately afterward.
5. Check that exactly one Logger remains, other scripts/assets are intact, and behavior matches the baseline. Do not edit the module just to prove sync. Report the result before advancing to the 32-script configuration.

After the pilot: stop the server, review the wider scope, and test the full configuration on the disposable copy. Migration of the real working place requires a fresh backup, reconciliation of newer Studio edits, and the reported successful trial. Do not publish a test over the real place.

Sources: https://rojo.space/docs/v7/project-format/ and https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0
