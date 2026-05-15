# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# Broken Reality FPS

## Game concept (legacy — see "Current product direction" below)

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

> **Note:** The five-round attackers-vs-defenders FPS loop above was the original first milestone. It is now considered **legacy/transitional**. Do not expand round-based features or add new round-specific systems unless explicitly requested.

---

## Current product direction (updated 2026-05-15)

**Broken Reality is a persistent PvPvE broken-reality zone shooter.**

Players spawn at a safe base, enter a quarantined zone to fight other players and monsters, collect loot and earn carried cash, then choose when to extract. Depositing at the base converts dangerous carried cash into secured funds used for weapons, gear, and base improvements.

### Main loop

```
Spawn at base (safe area)
  └─ Enter zone (dangerous, persistent — no round timer)
       └─ Fight players + monsters, loot objects, earn carried cash
            └─ Choose: stay longer (more risk, more reward)
                 or extract (reach an exit point)
                      └─ Exit → deposit at base terminal
                           └─ Spend secured funds: armory (weapons), shop (consumables)
                                └─ Return to zone
```

### Death rule

On death **inside the zone**, the player loses:
- Equipped weapon
- All carried loot
- All carried cash
- Some consumables

The player **keeps**:
- Secured funds (deposited at base before death)
- Stash contents
- Base upgrades
- Reputation and unlocks

Death must hurt, but never make a player quit. Always preserve a weak free respawn option so players can re-enter immediately with a basic loadout at no cost.

### Money model

| Currency | Earned | Lost on death | Purpose |
|---|---|---|---|
| **Carried cash** | Kills, loot pickups, zone contracts | In full | Risk currency; converted to secured at deposit |
| **Secured funds** | Depositing carried cash at base | Never | Safe progression; used at armory and shop |

### Early prototype scope

Build the smallest playable version first:

- One persistent suburban quarantine zone (no round timer; re-entry always open)
- Safe base area with one deposit terminal and one base armory
- One or two zone entrances; one or two extraction exit points
- Basic carried cash earned from kills and loot pickups
- Basic secured funds deposited at the base terminal
- One zone shop (consumables) and one base armory (three weapons: AR15, pistol, shotgun)
- Simple loot objects scattered in the zone (cash pickups, small drops)
- On death: drop equipped weapon and carried cash at the death location as a droppable bag

Do not build the full progression system, inventory UI, crafting, faction reputation, or monster wave escalation in one step. One feature at a time.

---

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

## First playable goal (legacy — achieved at Milestone 0)

> The original milestone was a 5-round attackers vs defenders FPS on one small suburban map where attackers plant reality anchors and defenders try to stop them. That prototype was the build target for the legacy system. It is now complete enough to be treated as a foundation, not an active goal.

**New first playable goal (persistent zone prototype):**

A single persistent zone where any number of players can enter, fight each other and monsters, collect loot, earn carried cash, and extract through a zone exit to deposit at a base. Death drops the player's weapon and cash on the floor. The base has one armory (three weapons) and one deposit terminal. No round timer. Re-entry is always open.

Do not build the full dream game first.

## Build order (legacy — Milestone 0 complete)

> The sequence below was the original Milestone 0 build order. Systems 1–10 are built. Systems 11–16 are partially built or planned. This order is now **legacy/transitional** — new systems follow the persistent zone architecture instead.

**Milestone 0 (legacy round-based — do not expand):**

1. Folder structure ✓
2. Config modules ✓
3. MatchService ✓
4. MatchController ✓
5. TeamService ✓
6. ObjectiveService ✓
7. Basic UI ✓
8. GunService ✓
9. GunController ✓
10. DamageService ✓
11. MovementController (partial)
12. DestructionService (not started)
13. CorpseService (not started)
14. MonsterService (not started)
15. HordeService (not started)
16. CutsceneController (not started)

**Milestone 1 (persistent zone — new target):**

Build one system at a time. Server before client. Do not start the next until the current is tested.

1. ZoneService — manages persistent zone state (no rounds, persistent respawns)
2. EconomyService — owns carried cash, secured funds, deposit logic
3. BaseService — owns safe base area, armory access, spawn selection
4. LootService — spawns and tracks loot objects in the zone
5. DeathDropService — creates droppable bag on death, owned by server
6. ExtractionService — handles exit trigger, converts carried cash to secured funds
7. ShopService — handles zone shop and base armory purchases
8. InventoryService — tracks equipped weapon, held consumables (deferred until needed)
9. StashService — persistent stash across sessions (deferred until needed)
10. ProgressionService — reputation, unlocks (deferred until needed)
11. MonsterService — AI enemies in zone (carries forward from legacy plan)

Each server service has a matching client controller. Build server side first.

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

**Prompt pre-flight review:**
- Before implementing any user prompt, briefly review the prompt first.
- State the intended goal in 1-2 sentences.
- State whether the prompt is safe, focused, and consistent with project rules.
- List the files expected to change.
- Flag any risks, especially camera, viewmodel, combat, movement, match-loop, objective, replication, remotes, or data-loss risks.
- State whether you recommend proceeding as written, narrowing the scope, or revising the prompt.
- If the prompt is risky, ambiguous, too broad, conflicts with project rules, or requires unavailable Studio/MCP verification, stop and ask for confirmation before editing.
- If the prompt is safe and includes "review then proceed if safe", continue after the pre-flight review without waiting for another confirmation.
- Do not use the pre-flight review to avoid reasonable work. If the task is clear and safe, proceed.

**MCP unavailable / GitHub-only mode:**
- If Roblox Studio MCP is unavailable, do not claim Studio verification was performed.
- Prefer documentation, configuration, and static-validation tasks only.
- Avoid camera, viewmodel, combat, movement, match-loop, objective, and replication changes unless the user explicitly accepts that the change is unverified in Studio.
- Run only non-Studio validation that is available locally, such as `git diff`, `rojo build`, `selene`, or formatting checks.
- Mark any gameplay-affecting change as "needs Studio verification" in `docs/TECHNICAL_DEBT.md` or the final response.
- Do not mark runtime technical debt fully resolved unless the behavior was actually verified in Studio.
- If MCP is unavailable for a task that normally requires MCP, clearly state that limitation.

**Asset import safety checklist:**
Before importing any Marketplace, Toolbox, `.rbxm`, or `.rbxmx` asset into Studio, state which containers the asset is expected to modify. After importing, perform all of the following checks before committing or syncing:

1. **State expected changes** — before importing, list which Studio containers the asset is known to modify (e.g. "ReplicatedStorage/ViewModels only").
2. **Inspect unmanaged containers** — after importing, open each of the following containers in Studio and look for any new Scripts or LocalScripts that were not there before:
   - `StarterPlayer.StarterCharacterScripts`
   - `StarterGui`
   - `StarterPack`
   - `ReplicatedFirst`
   - `Lighting`
   - `SoundService`
   - `Workspace` (and all imported Model descendants)
3. **Resolve every untracked script** — any Script or LocalScript found outside the Rojo-managed `src/` tree must be either:
   - Deleted (if it is a rig helper, camera controller, or other import artifact not needed by this project), or
   - Moved into the appropriate `src/` subfolder so it is tracked by Rojo and appears in git.
   No Studio-only script may remain untracked unless explicitly approved and documented as a new entry in `docs/TECHNICAL_DEBT.md`.
4. **Viewmodel imports** — delete or disable any LocalScript that controls `CameraType`, `camera.CFrame`, character movement, or `RenderStepped` camera behavior. These override the project's camera system and will silently break player input.
5. **Mark for Studio verification** — if the import affects the camera, viewmodel, combat, or character controls, mark the change as requiring Studio verification in `docs/TECHNICAL_DEBT.md` and the task response. Do not claim the change is verified until it has been tested in Studio play mode.
