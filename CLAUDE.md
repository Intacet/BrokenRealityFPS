# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# Broken Reality FPS

## Game concept

This is a Roblox round-based FPS set on Earth after reality breaks open in certain zones.

The main mode has:
- attackers
- defenders
- AI monsters
- multiple rounds
- controlled destruction
- dead bodies that remain between rounds
- different maps later

Attackers are a spec ops containment team sent to anchor unstable zones.
Defenders change by map and may be civilians, scientists, soldiers, militia, or survivors.
Monsters attack both human teams.

The morality should feel gray. Attackers may save the world, but their orders can be brutal. Defenders may protect innocent people, but they may risk spreading the break.

## Toolchain

| Tool | Purpose |
|------|---------|
| [Rojo](https://rojo.space/) | Syncs the `src/` file tree into Roblox Studio |
| [Wally](https://wally.run/) | Luau package manager (`wally.toml`) |
| [Selene](https://kampfkarren.github.io/selene/) | Luau linter |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | Luau formatter |

## Commands

```bash
# Sync project into Roblox Studio (Studio must be open)
rojo serve default.project.json

# Build a place file without Studio
rojo build default.project.json -o BrokenRealityFPS.rbxlx

# Install/update Wally packages into Packages/
wally install

# Lint all Luau files
selene src/

# Format all Luau files in-place
stylua src/
```

## Folder structure

Roblox instance tree (what lives in-engine):

```
ReplicatedStorage
  Remotes          -- all RemoteEvents and RemoteFunctions (single source of truth)
  Modules          -- shared ModuleScripts (types, weapon data, zone data, constants)

ServerScriptService
  Services         -- server-only Scripts (one per system, see Build order below)

StarterPlayer
  StarterPlayerScripts
    Controllers    -- LocalScripts (one per system, mirrors Services)

StarterGui
  HUD              -- ammo, health, kill feed, zone-effect indicator
  MatchUI          -- lobby countdown, round results
  ObjectiveUI      -- anchor progress, objective markers

Workspace
  Map              -- static map geometry
  Spawns           -- attacker and defender spawn folders
  Objectives       -- anchor/objective parts
  Destructibles    -- parts managed by DestructionService
  MonsterSpawns    -- spawn nodes for MonsterService
  CorpseFolder     -- corpse models persisted between rounds
```

Rojo source tree (files on disk, synced into the instance tree above):

```
src/
  server/          -- maps to ServerScriptService/Services
  client/          -- maps to StarterPlayerScripts/Controllers
  shared/          -- maps to ReplicatedStorage/Modules
  ui/              -- maps to StarterGui
Packages/          -- Wally dependencies (committed, do not edit manually)
default.project.json
wally.toml
selene.toml
stylua.toml
```

## Code rules

Do not write one giant script. Use small, modular scripts — one per system.

**Server controls:**
- match state
- teams
- objectives
- damage and health
- destruction states
- monster AI
- corpses
- rewards and saving

**Client controls:**
- input
- camera
- recoil visuals
- sounds
- UI
- hitmarkers
- cutscenes

**Do not trust the client with:**
- damage
- rewards
- objectives
- inventory
- destruction
- win conditions

**Config modules — use them for any value that may change:**
- Any number a designer might want to tune (timer, damage, speed, count, distance) goes in `ReplicatedStorage/Modules/Constants` or a relevant data module — never hardcoded inside a service or controller.
- If the value appears in more than one place, it must be in a module. No duplicate magic numbers.

**No magic numbers:**
- No numeric literal may appear in a service or controller unless it is a loop counter or a table index.
- Every tunable value — wait times, distances, thresholds, damage values, counts — must have a named constant in `Constants.lua` or the relevant data module.
- If a value has no obvious home, add it to `Constants.lua` with a comment explaining what it controls.

**Luau specifics:**
- `--!strict` at the top of every script.
- No `wait()` — use `task.wait()`. No `spawn()` — use `task.spawn()`.
- Module return shape: always a table. Service modules use `Module:Method()`; pure utilities use `Module.method()`.
- Types are defined in `ReplicatedStorage/Modules/Types` and imported, never redeclared locally.
- Weapon stats and zone configs are data tables, not branching logic — add entries to the data modules rather than `if weapon == "AR"` style conditionals.
- Server scripts never `require` anything under `src/client/`. Client scripts never `require` anything under `src/server/`.

**No circular requires:**
- Never require a module that directly or indirectly requires the calling module back.
- If two services need to communicate bidirectionally, use a BindableEvent in `MatchEvents.lua` instead of direct requires.
- Before requiring a new module, confirm the dependency only flows in one direction.

**Logger — never call print() or warn() directly:**
- Never call `print()` or `warn()` directly in a service or controller.
- Always `require` `src/shared/Logger.lua` and use `Logger.debug()` for development output and `Logger.warn()` for unexpected states.
- `Logger.debug()` calls are automatically suppressed when `DEBUG_MODE` is set to `false` before shipping.
- Require Logger from shared modules with: `local Logger = require(Modules:WaitForChild("Logger"))` where `Modules` is already resolved via `WaitForChild`.

**No silent failures:**
- Never use `pcall` without logging the error message in the failure branch using `Logger.warn()`.
- Never return `nil` from a function that is expected to return a value without first calling `Logger.warn()` with the function name and the reason.
- Silent failures must not exist anywhere in the codebase.

**Remote conventions:**
- All Remotes are created and referenced through `ReplicatedStorage/Remotes` only.
- `RemoteEvent` names: `PascalCase`, verb-first (`WeaponFired`, `RoundStateChanged`, `DamageApplied`).
- `RemoteFunction` names: `PascalCase`, question-phrased (`GetMatchConfig`).
- Before adding a new `RemoteEvent` or `RemoteFunction`, add it to the remote registry table in `docs/PROJECT_MAP.md` first with its **Fired by** and **Listened by** columns filled in.
- Never fire or listen to a remote that is not listed in that table.
- Never assign a second script to fire or listen to an existing remote without updating the table and explaining why.

## First playable goal

Build the smallest playable version first:

A 5-round attackers vs defenders FPS on one small suburban map where attackers plant reality anchors and defenders try to stop them.

Do not build the full dream game first.

## Build order

1. Folder structure
2. Config modules
3. MatchService
4. MatchController
5. TeamService
6. ObjectiveService
7. Basic UI
8. GunService
9. GunController
10. DamageService
11. MovementController
12. DestructionService
13. CorpseService
14. MonsterService
15. HordeService
16. CutsceneController

Each service on the server has a matching controller on the client. Build the server side of a system before the client side.

## Claude behavior

**Read `docs/` before making any code changes. These files are the source of truth for this project.**

The files to read before starting any task:
- `docs/PROJECT_RULES.md` — hard rules for every file
- `docs/PROJECT_MAP.md` — how systems connect and the remote registry
- `docs/NAMING.md` — naming conventions for every layer
- `docs/ROADMAP.md` — what is planned and in what order
- `docs/CHANGELOG.md` — what has already been built
- `docs/TECHNICAL_DEBT.md` — known risks and deferred problems

Before writing any code:
- read the docs listed above
- inspect the existing structure
- reuse existing names and module patterns
- do not rename public functions unless asked
- explain every file that will change and exactly what will change in it
- explain how the new code connects to existing systems (which services call it, which remotes it uses, which modules it reads)
- build one system at a time

After writing any code:
- give concrete test steps so the change can be verified in Studio before moving on
- point out anything in the new code that may become hard to maintain later (tight coupling, load-order assumptions, growing conditionals, anything that will need revisiting)
- add an entry to `docs/CHANGELOG.md` describing what was added or changed
- every time you flag a maintenance risk or known limitation in a response, add it to `docs/TECHNICAL_DEBT.md` as a new numbered entry before finishing the task

At the start of every task, read `docs/TECHNICAL_DEBT.md` and check whether the requested change touches any file or system listed there. Before writing any code, explicitly state which debt entries are relevant to this task and whether the change resolves, worsens, or is unaffected by each one.

When a task touches a debt entry, evaluate whether the debt is fully resolved, partially resolved, or unresolved based on the actual state of the code after your changes. Do not mark an entry resolved simply because the requested fix was applied — confirm the underlying risk is genuinely gone. Update the entry status with your reasoning.

After every task, run `git add -A`, `git commit -m "[description]"`, and `git push` before ending the session. Never leave completed work uncommitted or unpushed. A task is not finished until it is on GitHub.

**Object pooling:**
For any object that is created and destroyed frequently during gameplay (muzzle flash parts, bullet impact effects, debris, floating text), use an object pool rather than calling `Instance.new()` on every event. When a second pooled object type is needed, create `src/shared/ObjectPool.lua` as a reusable pool module.

**Connection cleanup:**
Store all `RBXScriptConnection`s in a local array when created inside a service or controller. When a system resets (phase change, round end) or a player leaves, iterate the array and `Disconnect()` every connection, then clear the array. Never leave active connections pointing to removed players, destroyed instances, or finished rounds.

**Public API validation:**
Every public API function that accepts required parameters must validate them with `assert()` before any other logic. Example: `assert(typeof(victim) == 'Instance' and victim:IsA('Player'), '[ServiceName] method requires a valid Player')`. This prevents silent failures from bad callers and makes errors immediately traceable.

**Formatting and diff hygiene:**
- Do not run a global formatter across the whole repository unless explicitly asked.
- When modifying code, format only the files touched by the current task.
- Keep diffs small and focused so gameplay changes remain easy to review.
- Do not make formatting-only edits to unrelated files.
- Preserve the existing style of untouched files.
- If a formatter is later configured, run it only on files modified by the current task unless the user explicitly requests a full-repo formatting pass.
