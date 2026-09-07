# Project rules

## Preservation and scope

Preserve the existing place and all Studio work. Back up before migration. Work on a disposable copy for the first Rojo test. Do not publish a test over the live place. No gameplay code changes during the initial source capture.

This game uses R6. SCAR and R15 plans are historical unless current evidence establishes a relevant legacy dependency. Follow CURRENT_GAME_DIRECTION.md.

Studio owns assets; VS Code/Rojo will own migrated scripts. Do not allow competing edits after a script handoff. Disconnect Rojo before emergency Studio source edits, then reconcile source before reconnecting.

## Code rules for later stages

- Use --!strict for new and intentionally edited Luau scripts.
- Capture existing source unchanged first, even if it violates these rules. Log violations as debt and address separately.
- No print() or warn(); use a Logger module later.
- No wait() or spawn(); use task.wait() and task.spawn().
- No gameplay magic numbers; put constants in Constants.lua.
- Server owns authoritative state: damage, health, hits, money, inventory, extraction results. Client requests require server validation.
- No new remotes unless explicitly requested.
- Store RBXScriptConnections and disconnect them when their owner is destroyed, replaced, or otherwise finished.
- Small staged tasks; one system per pass. No global formatting unless requested.

## Verification

Document what was checked locally and what the user tested in Studio separately. Never infer Studio success from a file comparison or successful Rojo build. First sync requires explicit confirmation that the proposed mappings preserve important Studio work.
