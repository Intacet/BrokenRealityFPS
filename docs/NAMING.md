# Naming

- Preserve current Studio instance names, capitalization, hierarchy, and referenced paths during migration.
- Suggested snapshot layout: import/studio-snapshot/<Service>/<existing hierarchy>/<script filename>.
- Script: ExistingName.server.lua. LocalScript: ExistingName.client.lua. ModuleScript: ExistingName.lua.
- These extensions encode class, not complete execution behavior. Capture RunContext and enabled state separately before configuring Rojo.
- Rojo treats init.lua, init.server.lua, and init.client.lua specially. Do not use them casually; scripts with children need explicit review.
- A directory represents a Folder by default under Rojo; never assume a directory preserves a Model, Tool, ScreenGui, or another parent class.
- Duplicate names, reserved filenames, or incompatible characters require a documented local-name-to-Studio-path mapping. Do not rename Studio objects to solve these automatically.
- For future code, use descriptive names; Constants.lua is for gameplay constants and Logger.lua is reserved for the future logging module. Neither is implemented yet.
- New naming conventions must not trigger a global rename or formatting pass.
- Actual baseline archive uses service/numbered-name files to avoid duplicate-name collisions and long Windows paths. SCRIPT_INVENTORY.json maps each archive file to exact ancestor names/classes and same-name sibling indices. These archive filenames must not be used directly for Rojo syncing.
