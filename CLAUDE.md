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

**Luau specifics:**
- `--!strict` at the top of every script.
- No `wait()` — use `task.wait()`. No `spawn()` — use `task.spawn()`.
- Module return shape: always a table. Service modules use `Module:Method()`; pure utilities use `Module.method()`.
- Types are defined in `ReplicatedStorage/Modules/Types` and imported, never redeclared locally.
- Weapon stats and zone configs are data tables, not branching logic — add entries to the data modules rather than `if weapon == "AR"` style conditionals.
- Server scripts never `require` anything under `src/client/`. Client scripts never `require` anything under `src/server/`.

**Remote conventions:**
- All Remotes are created and referenced through `ReplicatedStorage/Remotes` only.
- `RemoteEvent` names: `PascalCase`, verb-first (`WeaponFired`, `RoundStateChanged`, `DamageApplied`).
- `RemoteFunction` names: `PascalCase`, question-phrased (`GetMatchConfig`).

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
