# GitHub migration record

- Repository: https://github.com/Intacet/BrokenRealityFPS
- Existing default branch when inspected: claude/create-claude-md-AqEm8
- Existing tip: 04a445df23361187116ab5b0e96686cf2236df4e
- No main or master branch existed at inspection.
- All 32 prior main-script sources matched the saved Studio sources byte-for-byte after accounting for the different local folder layout.
- The older configuration also described Workspace folders, asset folders, and StarterPlayer properties. The new configuration deliberately manages only individually reviewed code targets and preserves unknown instances at every affected node.
- The old branch is retained unchanged. Main joins its history using Git's ours merge strategy: the migration tree is retained in full, while the previous history becomes an ancestor. No forced push or remote history replacement is used.
- Old place files and previous roadmaps remain recoverable in history, but are not added to the active scripts/docs tree. This does not erase historical large files from Git storage.
- GitHub's default branch has not been changed. Use main for this migration workflow.
- HTTPS operations used Git's OpenSSL backend because the Windows Schannel backend failed to initialize credentials. Certificate verification stayed enabled; no global Git settings were changed.
- Upload succeeded using the owner's normal Windows Git credentials outside the sandbox accounts. Main now exists on GitHub and the local main tracks origin/main. Earlier sandbox credential failures did not indicate a problem with the owner's GitHub account.
- The OpenSSL backend is configured only for this local repository so VS Code can use it too. Sign in through the normal GitHub flow before publishing main; do not put tokens in project files or chat.
