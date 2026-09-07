# Safe migration plan

## 1. Back up Studio first

1. Stop playtesting. Keep Rojo disconnected. Resolve and save intended open script edits; if Team Create/drafts are used, confirm which edits are included without discarding collaborators' work.
2. Export the current open place using File > Save to File or Download a Copy, depending on Studio's available menu. Use a dated name such as BrokenReality_preRojo_2026-09-07_01.rbxl in a dedicated backup directory outside the code repository.
3. Copy that file to a second device or backed-up cloud folder. Keep the original untouched.
4. Open the backup separately in Studio and inspect maps, terrain, lighting, spawns, R6 rig assets, Tools, viewmodels, scripts, and animation objects. Record the filename and your result in PROJECT_MAP.md.
5. Save a separate working copy named BrokenReality_migration_test.rbxl. Only this disposable copy will receive the first reviewed Rojo sync.
6. If using Roblox cloud saves, make a named save/version checkpoint as a supplementary backup; do not publish over the live game just to make a backup. Repeat for other places in the experience when relevant.
7. Record animation/mesh/sound/texture IDs and asset ownership. Save unfinished Animation Editor work using its supported save/export workflow. A place snapshot does not embed every externally hosted asset or back up DataStores, all experience settings, or unsaved editor/plugin state.

Official place-file guidance: https://create.roblox.com/docs/projects/place-files

## 2. Local project

Open the BrokenReality folder containing AGENTS.md in VS Code. Keep source control scoped to this folder. The seven requested docs exist. Create import/studio-snapshot/ when capturing source and src/ when promoting reviewed scripts; both remain empty until then.

Create .gitignore before staging files: exclude place/model backups (*.rbxl, *.rbxlx, *.rbxm, *.rbxmx), backup directories, build output, credentials, and local tool caches. Keep place backups in their separate backup location. Do not add a default.project.json yet or run a template initializer in the existing place workflow.

## 3. Inspect and copy

Use the inventory in PROJECT_MAP.md. Inspect edit-time objects, not only runtime clones. For each script, copy the full Source from Studio's script editor into a matching file under import/studio-snapshot/. Preserve content verbatim: no strict header insertion, renaming, cleanup, or formatting during capture. Keep the original Studio script intact.

Capture source for all required modules and document properties/children/dependencies. Compare each saved local file against Studio in full, including first/last lines and line count. Source copy alone does not capture instance metadata or child objects. Record every comparison. Take a baseline Git commit before any later code changes.

Scripts embedded in Tools, models, GUI objects, viewmodels, or other asset hierarchies stay Studio-managed until individually reviewed. A snapshot copy of their source does not transfer ownership.

## 4. Git and GitHub

Initialize Git in this project folder after reviewing .gitignore. Review the complete staged file list and diff, then commit the documentation baseline. Commit the verified source capture separately. Create or select the owner's intended private GitHub repository, inspect its existing contents before combining histories, add the correct remote, and push. Confirm the commits/files are visible on GitHub. Do not overwrite an existing remote history or force-push.

GitHub backs up committed scripts/docs, not Studio assets. Record repository URL and backup verification in PROJECT_MAP.md. Tool installation/authentication and actual push are later steps; none are complete yet.

## 5. Review Rojo before connecting

After inventory and source comparison, record the CLI/plugin versions and create a version-compatible project that maps only approved scripts or verified code-only folders at their existing Studio paths. Promote those source files into src/; never map import/ or docs/.

Do not map whole Workspace, ReplicatedStorage, ServerStorage, StarterGui, StarterPack, or other asset-bearing services to local folders. Preserve structural ancestors and their correct classes. Explicitly review unknown-child preservation at every affected ancestor and mapped node. Rojo's $ignoreUnknownInstances defaults differ depending on whether $path exists; do not rely on defaults or assume a parent setting protects all descendants. This setting does not protect a mapped object's source/properties from replacement.

Preserve script class, enabled state, RunContext, attributes, tags, and children through a reviewed mapping/metadata representation. Resolve duplicate names and path-dependent logic. Do not move a script to a new code folder if that breaks callers or script.Parent assumptions. Use servePlaceIds for the intended target where applicable, as an additional guard rather than the sole safeguard.

Official references: https://rojo.space/docs/v7/project-format/ and https://rojo.space/docs/v7/sync-details/

## 6. First connection gate

All must be confirmed before connecting even the disposable copy:

- Verified backup and separate test copy exist.
- Inventory and source comparison are complete for the proposed small batch.
- Exact mapping and instance metadata reviewed; no unexplained deletion, replacement, duplication, or asset scope.
- Rollback is available by discarding the test copy and reopening the untouched backup.
- User has confirmed the folder/mapping review preserves important Studio work.

Connect only the disposable copy first, stopped outside Play mode. Inspect any available proposed-change preview before accepting; reject unexpected changes. If the installed version lacks a preview, restrict the trial to the disposable copy and compare afterward. Check preserved assets, script counts, hierarchy, properties, and source. Ensure no duplicate running scripts. User then tests existing behavior: spawn, R6 movement, camera/viewmodels, current weapon behavior, and other relevant baseline systems, reporting results rather than assuming success.

Only after the successful trial is reported: take a fresh backup of the current real place, reconcile any intervening Studio edits, review the same mapping, and connect that place. Transfer script ownership batch by batch. Never replace the real place with a code-only generated place.

## Studio-only for now

Maps/terrain, models, R6 rigs, meshes, Tools and weapon assets, animations and editor data, viewmodels, lighting, spawns, UI instances, sounds/effects, attachments/constraints, asset-bearing packages, existing remote instances, and non-code configuration objects. Embedded scripts remain Studio-authoritative until separately approved for migration. Documentation can inventory these objects without syncing them.
