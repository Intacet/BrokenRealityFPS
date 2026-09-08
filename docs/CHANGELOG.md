# Changelog

## Animation lock recovery (equip / ADS)

- Extended the reload recovery pattern below to `PlayEquipAnimation` and to ADS-in/ADS-out in `SetAiming`: each now has a Heartbeat watchdog (tracked connections, cleared on weapon switch/holster/respawn/ADS interrupt) that force-resumes the correct state if the one-shot animation's `Stopped` signal never arrives, using new `VIEWMODEL_EQUIP_LOAD_TIMEOUT`/`MAX_DURATION` and `VIEWMODEL_ADS_LOAD_TIMEOUT`/`MAX_DURATION` Constants (3s / 10s, matching reload's values).
- Rationale: a stuck ADS "Entering"/"Exiting" state left `IsAiming()` permanently true, which silently routes every future shot to the ADS fire animation — itself a no-op outside the "Aiming" state — so the gun kept firing server-side with no visible fire animation. A stuck equip state left the weapon frozen at bind pose. See RELOAD_DIAGNOSIS.md "Extended scope" for detail.
- The equip fix preserves the existing immediate `Play()` call unchanged (success path untouched); it only adds a recovery net. No animation asset IDs were changed.
- Re-verified (by manual trace, not by running Lune — not installed in this environment) that all 13 existing `scripts/Test-Reload.luau` assertions still hold against the current `PlayReloadAnimation` source; that method was not modified this pass.
- Not installed in Studio and not Studio-tested. See TECHNICAL_DEBT.md.

## Reload recovery

- Added bounded asset loading and playback recovery to ViewModelController, with timeout tuning in Constants and explicit reload connection cleanup. FP playback is independent of TP playback errors.
- Added 13 mocked regression assertions and syntax compilation of the two edited runtime files. Visual asset failure cause and Studio verification remain pending; existing asset IDs and original place are unchanged.

## 2026-09-08 — VS Code sourcemap path

- Pointed Luau LSP at the verified project-local Rojo 7.6.1 executable and selected `default.project.json` for code navigation.
- Ignored the generated `sourcemap.json`. This changes editor metadata only and does not start a Rojo server or connect Studio.

## 2026-09-08 — daily GPT / Claude / Rojo workflow

- Added `AI_HANDOFF.md` and `AI_DECISIONS.md` so both assistants share current state and durable owner decisions through Git.
- Added a tracked VS Code workspace plus safe start and pre-commit review tasks. The start task refuses to pull over uncommitted files and permits only a fast-forward update of `main`.
- Installed and verified Codex 26.901.22334, Claude Code 2.1.263, Rojo 2.1.2, and Luau LSP 1.69.0 VS Code extensions.
- Rebuilt both Rojo configurations successfully. No Rojo server was connected to Studio, no gameplay source changed, and no place was published.
- Scoped Git's safe-directory allowance to each workflow command so the normal Windows account can use this sandbox-created checkout without changing global Git settings.
- Changed the GitHub default branch to `main`; preserved `claude/create-claude-md-AqEm8` as historical context.

## 2026-09-08 — shared GPT / Claude laptop setup

- Verified main matches the remote before setup; retained the historical Claude branch.
- Installed official Codex VS Code extension 26.901.22334 and verified existing Claude Code 2.1.263 in VS Code 1.135.0. Account sign-in and model selection remain user-controlled.
- Added shared handoff instructions and extension recommendations. Disabled automatic formatting only for this workspace. Opened the existing checkout in VS Code.
- Retained matching Rojo CLI/plugin 7.6.1; rebuilt the Logger pilot and rechecked the immutable Studio backup hash. No Studio sync, gameplay source change, or publish was performed.

## 2026-09-08 — isolated Mercer District prototype

- Added a separate city builder, geometry model, test place, and overhead plan: brick homes, corner shops, warehouses, alleys, protected staging cover, and three objective areas.
- Added server-owned destruction for 132 selected pieces with material health, bounded cosmetic debris, PREP reset, and connection cleanup. Reused the existing validated server shot path and existing match events; no new remotes.
- Kept migrated src unchanged. Only the generated test copy integrates destruction, changes test lighting, and archives original Workspace objects under ServerStorage.
- Passed 22 offline checks, syntax compilation, and original Workspace source preservation checks. Assistant observed the separate place enter ACTIVE; user-confirmed Studio destruction/multiplayer verification is pending.
- Deferred reload animation debugging. No publish or live Rojo handoff performed.

## 2026-09-07 — documentation baseline

- Inspected the provided local workspace: no existing scripts, Rojo configuration, or Git repository found.
- Created AGENTS.md and the six requested project documents.
- Recorded R6, AKS-74 / AR-style viewmodels, custom movement, and PvPvE direction.
- Defined Studio asset ownership and a staged script handoff.
- Added a migration plan. No gameplay code written or edited; no Rojo connection/configuration, Git initialization, or GitHub publishing performed.
- Studio backup, inventory, and testing remain unconfirmed.

## 2026-09-07 — laptop setup started

- Added the owner's big-map stabilization-team premise; opposing citizens/defenders design remains undecided.
- Added .gitignore and empty source-capture and reviewed-source folders.
- Confirmed Git and VS Code are on the command path; Rojo and gh were not found there.
- Native Studio UI control is unavailable in this session. Awaiting a user-saved place copy before source inventory or sync configuration.

## 2026-09-07 — saved-place capture

- Received the saved binary place and made a separate test copy; both hashes match.
- Used official Lune 0.10.5, with its downloaded archive checked against the GitHub release checksum, to read the place without running gameplay or writing the place.
- Captured 216 script sources and verified the output bytes against decoded saved source; added inventory and metadata records.
- Found 184 Workspace-embedded scripts and 32 scripts in main code locations. Existing Logger and Constants modules are present.
- No source was edited; no remotes or sync project created. Studio visual/behavior verification and GitHub backup remain pending.

## 2026-09-07 — Rojo configuration prepared

- Recorded the owner's positive test-copy report; no post-sync test is claimed.
- Copied 32 main scripts unchanged into src/ at their existing hierarchy.
- Added a Logger-only pilot and an explicit 32-script configuration, with unknown-instance preservation on every affected node.
- Installed the official verified Rojo 7.7.0 CLI locally and validated both builds and mappings against the saved place.
- Downloaded the matching verified Studio plugin; installation remains pending because filesystem write permission was not granted.
- Added a VS Code task for the pilot. No server started, Studio connection made, or gameplay source edited. GitHub remains pending repository selection.

## 2026-09-07 — existing GitHub repository reconciled

- Connected origin to the owner's Intacet/BrokenRealityFPS repository and inspected its existing branch/history.
- Confirmed all 32 main scripts match the prior GitHub tip byte-for-byte.
- Added a shared CLAUDE.md entry point and README to direct future tools to current instructions.
- Retained the migration tree while joining the older branch history; the original branch is preserved. Main is the new migration branch; the GitHub default branch is unchanged.

## 2026-09-07 — GitHub upload and native Studio access

- Uploaded main successfully using normal Windows Git credentials; preserved the old remote branch.
- Native Studio control became available. Observed the migration test window and existing Rojo 7.6.1 plugin.
- Matched the local CLI to official Rojo 7.6.1 and rebuilt both configurations successfully.
- Saved the test copy and revalidated all mapped scripts against it before attempting the pilot connection.
