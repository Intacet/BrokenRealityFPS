# GPT and Claude workflow

Use the existing BrokenReality checkout on branch main. The claude/create-claude-md-AqEm8 branch preserves older history; it is not the current migration branch. Do not clone a second working copy or switch to the older branch to follow an outdated setup message. GitHub's default branch may still display the older branch: select main explicitly.

## Open the project

Open the adjacent BrokenReality.code-workspace file in VS Code, or open this repository folder. The official Codex and Claude Code extensions provide the two assistants. Open their panels and complete sign-in yourself if requested; never put account tokens in the repository or chat. Extension installation does not establish that either account is signed in.

Use the available model picker to select GPT-6 Astra where your account offers it. No model or subscription settings were changed by this setup.

## Work one small task at a time

1. Check Source Control before starting. Keep existing uncommitted work; never reset it to make the status clean.
2. Give one assistant the editing task. Have it read AGENTS.md, CURRENT_GAME_DIRECTION.md, PROJECT_RULES.md, PROJECT_MAP.md, and this guide.
3. Stop its editing and review the diff before asking the other assistant to review. The reviewer should report findings without changing files until assigned the next edit.
4. Record changed files, checks actually performed, remaining issues, and the next small action in the task handoff. Commit a reviewed checkpoint before switching assistants.
5. Push scripts/docs to GitHub. Save and back up Studio assets separately. A Git push does not back up the place files excluded by .gitignore.

Both assistants share files, not automatic conversation memory. A browser chat that only sees the GitHub default branch may give obsolete advice; provide the main branch link and the handoff below.

## Current handoff

- R6; current weapon/viewmodel direction is AKS-74 / AR-style, with custom R6 movement and PvPvE zone foundations. SCAR references are legacy unless found in current source.
- Studio owns maps/models/animations/viewmodels and current live scripts until verified migration. Preserve the original preRojo backup.
- 216 scripts were captured; 32 unchanged core scripts are in src. main includes the current preservation docs and isolated city prototype.
- Mercer District and destruction source live in prototypes/CityDistrict. Generated place/model files are in the adjacent CityDistrict folder. The complete test-place builder also needs the adjacent StudioBackups/BrokenReality_preRojo.rbxl.
- 22 offline destruction checks passed. Studio multiplayer/destruction/route balance remain unconfirmed. Reload animation remains unresolved.
- No new gameplay work is authorized by this setup document alone.

## Rojo boundary

The CLI is local at .tools/rojo.exe, version 7.6.1, matching the observed Studio plugin. It does not need a global PATH installation. Use the VS Code task "Broken Reality: Start Logger pilot (test copy only)" after reviewing docs/ROJO_REVIEW.md. Starting the server does not authorize connecting an important place.

The first sync is restricted to the existing Logger in a disposable migration copy. Reconcile any newer Studio source first. The full default.project.json manages 32 baseline scripts, not the new city prototype. Do not connect that full configuration to BrokenReality_CityTest.rbxl: it would restore baseline GunService and remove its destruction integration. Never open a code-only Rojo build as the replacement for the working place.

## Setup references

[Official Codex IDE guide](https://learn.chatgpt.com/docs/codex/ide) and [official Claude Code VS Code guide](https://code.claude.com/docs/en/vs-code).
