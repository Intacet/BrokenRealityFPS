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

## Current product direction (updated 2026-05-20)

**Broken Reality is a persistent PvPvE broken-reality zone shooter set inside a quarantined metro district.**

The **metro station** is the main safe-base fantasy — a believable underground hub where players prepare, deposit earnings, visit traders, and upgrade their operation. The **zone** is the dangerous overground layer where the reality break is active: players fight other players and monsters, loot objects, earn carried cash, and choose when to push their luck and when to extract.

The base and zone must feel **physically connected** through trains, gates, sewers, tunnels, and checkpoint exits — not abstract menus. Walking through a checkpoint gate or boarding a departing train is the transition; there is no loading screen shortcut.

### Refined core loop

```
Spawn in metro base (safe — no PvP or monsters)
  └─ Enter zone through physical transition
       (train route / gate / sewer / checkpoint exit)
            └─ Fight players and monsters; loot objects; earn carried cash
                 └─ (Optional) Buy emergency guns/supplies from risky in-zone shops
                       (higher prices than base; accepts carried cash only)
                            └─ (Optional) Accept simple faction trader missions
                                  (kill X monsters, extract with cash, visit location)
                                       └─ Survive or respond to periodic Reality Breakdown events
                                             (timed pressure; optional participation)
                                                  └─ Choose: stay for more risk/reward
                                                       or extract through a physical exit
                                                            └─ Return to metro base
                                                                 └─ Deposit at base terminal
                                                                      (carried cash → secured funds)
                                                                           └─ Store items in stash
                                                                                └─ Upgrade base, visit traders
                                                                                     └─ Repeat
```

### Core experience pillars (near-term)

Build these before anything else. They define whether the game loop is fun.

1. **Fast re-entry** — A player who dies should be back in the zone within a few seconds of choosing to respawn. Re-entry friction must stay near-zero.
2. **Carried cash risk** — Every run puts your current earnings at risk. You only lock them in by extracting. Dying in the zone hurts.
3. **Secured funds safety** — Deposited earnings are permanently safe. Players build trust in the extraction loop over time.
4. **Physical extraction/deposit** — Value is only secured by physically reaching a deposit terminal or extraction exit. No instant banking from anywhere inside the zone.
5. **Risky in-zone shops** — Emergency guns and supplies available inside the zone at a premium. Useful in a pinch; never a shortcut to base armory progression.
6. **Simple faction traders/missions** — Short, optional objectives (kill X, extract with cash, reach a location). Give players direction without mandatory participation.
7. **Periodic Reality Breakdown events** — Timed pressure events (loot surge, monster escalation, lethal zone spread). Participation is optional; safe extraction must still be possible.
8. **Base storage and upgrades** — Locker/crate storage, armory tiers, medical supply upgrades. Visible progression that rewards consistent extraction.

### Death rule

On death **inside the zone**, the player loses:
- Equipped weapon
- All carried loot
- All carried cash

The player **keeps**:
- Secured funds (deposited at base terminal before death)
- Stash contents
- Base upgrades

Death must hurt, but never make a player quit. Always preserve a weak free respawn option (free pistol or equivalent) so a player can re-enter immediately with a basic loadout at no cost.

### Money model

| Currency | Earned | Lost on death | Spendable at | Purpose |
|---|---|---|---|---|
| **Carried cash** | Kills, loot pickups, missions | In full | In-zone shops; deposit terminal | Risk currency; converted to secured at deposit |
| **Secured funds** | Depositing at base terminal | Never | Base armory, upgrades, stash | Safe progression currency |

The two economies must stay **separate at all times**. Spending carried cash in-zone is a tactical choice. Spending secured funds at the base is a progression choice. A server bug that accidentally secures undeposited cash violates the core loop.

### Base / zone distinction

| | **Metro base** | **Zone** |
|---|---|---|
| Safety | Safe — no PvP or monsters | Dangerous — full PvP + monsters |
| Currency accepted | Secured funds | Carried cash |
| Key activities | Stash, armory, upgrades, traders, deposit, preparation | Looting, fighting, in-zone shops, missions, events, death drops |
| Physical access | Via train, checkpoint gate, sewer exit from zone | Via train, checkpoint gate, sewer entry from base |
| On death | N/A | Lose weapon, carried cash, carried loot |

### First playable scope

Build the smallest loop that proves the core works:

- One persistent quarantine zone (no round timer; re-entry always open)
- One physical zone entrance (gate, train stop, or sewer)
- One physical extraction/deposit exit (gate or checkpoint)
- Metro base safe area with one deposit terminal and one base armory
- Carried cash earned from kills and loot pickups
- Secured funds deposited at the base terminal
- One risky in-zone shop (emergency guns/ammo at elevated prices)
- Simple loot objects (cash pickups, small drops) scattered in the zone
- On death: drop carried cash and equipped weapon as a pickup bag at the death location
- One simple Reality Breakdown event — added after the basic loop is proven

Do not build the full progression system, inventory UI, crafting, faction reputation, complex monster waves, or zone events until the core loop (enter → loot → extract → deposit → return) is working in Studio.

---

## Deferred / Do Not Build Yet

The following features are **explicitly deferred** and must not be started until the core loop is stable, relevant prerequisite systems exist, and risks have been intentionally addressed.

| Feature | Why deferred | Prerequisites before starting |
|---|---|---|
| **Player flea market / global marketplace** | Economy, stash, item ownership, anti-duplication, and moderation/abuse controls do not exist yet | Stable economy + stash + item ownership + anti-duplication system + moderation plan |
| **Free drawing on signs / custom paintings** | Content moderation and abuse risk not yet addressed | Dedicated moderation system, abuse risk review, content policy |
| **Advanced AI death squads** | Simple monsters and basic event pressure not yet proven | MonsterService working + zone events proven |
| **Full gun attachment system** | Basic weapon/economy loop not yet established | Weapon inventory + shop + stash loop stable |
| **Complex melee system** | Scope risk during FPS foundation phase | Core FPS loop + movement proven |
| **Complex faction warfare** | Simple missions and traders not yet proven | MissionService + basic trader system working |
| **Complex visor / enemy detection system** | High design and implementation complexity | Basic AI + combat loop proven |
| **Full base decoration system** | Cosmetic priority too high relative to core loop | Core loop proven + storage/stash stable |

> **The flea market/player marketplace is a long-term idea only. It must not be included in the first playable version, and must not be started until the economy, stash, item ownership, anti-duplication, and moderation/abuse risks are solved.**

---

## Toolchain

| Tool | Purpose |
|------|---------|
| [Rojo](https://rojo.space/) | Syncs the `src/` file tree into Roblox Studio |
| [Wally](https://wally.run/) | Luau package manager (`wally.toml`) |
| [Selene](https://kampfkarren.github.io/selene/) | Luau linter |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | Luau formatter |

## Character rig target

**Current target: R6.**

All character rigs, animations, hitbox logic, ragdoll joints, and weapon attachment points must target the R6 body-part hierarchy:

| Part name | Role |
|---|---|
| `HumanoidRootPart` | Physics root, anchor point for all calculations |
| `Torso` | Central torso body part |
| `Head` | Head |
| `Left Arm` | Left arm |
| `Right Arm` | Right arm |
| `Left Leg` | Left leg |
| `Right Leg` | Right leg |

**R15 is legacy.** R15 part names (`UpperTorso`, `LowerTorso`, `LeftUpperArm`, `RightUpperArm`, etc.) must not appear in any new code. Existing references to R15 in RagdollService (Motor6D iteration) are acceptable because the logic is rig-agnostic, but new animation, hitbox, and weapon-alignment code must use R6 names.

**Setting in Studio:** `Game Settings → Avatar → Avatar Type → R6`. This is enforced programmatically via `StarterPlayer.CharacterRigType = Enum.HumanoidRigType.R6` in `default.project.json` (`"$properties": { "CharacterRigType": { "Enum": 0 } }`).

**Future systems that must target R6:**
- Movement animations (Stage 2+) — animation IDs and track names must be R6 rigs
- Hitbox system — part-name lookups must use R6 names
- Ragdoll Stage 2 — any per-part joint filtering must use R6 body-part names
- Weapon attachment points (`EjectPortAttachment`, barrel tip alignment) — must be rigged to R6 `Right Arm` / `Torso`

---

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

**New first playable goal (persistent zone prototype — updated 2026-05-20):**

A metro-base-to-zone loop: players spawn in a safe metro station, enter the quarantine zone through a physical transition (gate, train, sewer), fight players and monsters, earn carried cash, optionally buy emergency supplies from a risky in-zone shop, and extract through a physical exit back to the metro base where they deposit at a terminal. Death drops carried cash and equipped weapon on the floor. The metro base has one deposit terminal and one base armory. No round timer. Re-entry is always open.

Do not build the full dream game first. The flea market, advanced AI death squads, full attachment system, and base decoration are explicitly deferred — see "Deferred / Do Not Build Yet" above.

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
11. MovementController (partial — Stages 1 + 2A–2E complete)
12. DestructionService (not started)
13. CorpseService (not started)
14. MonsterService (not started)
15. HordeService (not started — replaced by ambient zone spawn budget)
16. CutsceneController (not started)

**Milestone 1 (persistent zone — current target):**

See `docs/PERSISTENT_ZONE_ROADMAP.md` for the full staged build order. Summary:

| Stage | System | Status |
|---|---|---|
| 0 | Reusable FPS foundation (AR15, movement, damage/death) | ✓ Largely done via Milestone 0 |
| 1 | Metro base + zone transition (safe area, one entrance, one exit) | Not started |
| 2 | Economy foundation (carried cash, secured funds — server-owned) | Not started |
| 3 | Deposit/extraction (physical transfer of carried cash → secured funds) | Not started |
| 4 | Death loss (carried cash lost on death; death drop bag) | Not started |
| 5 | Risky zone shop (in-zone trader/cache; carried cash only) | Not started |
| 6 | Simple missions/traders (faction trader, short optional objectives) | Not started |
| 7 | First event (Reality Breakdown countdown; extract or suffer) | Not started |
| 8 | Simple monsters (basic AI; no advanced death squads) | Not started |
| 9 | Base storage/upgrades (lockers, armory tiers, medical) | Not started |
| 10 | Deferred polish and expansion (see "Deferred" section above) | Deferred |

Build one system at a time. Server before client. Do not start the next until the current is tested in Studio. See `docs/PERSISTENT_ZONE_ROADMAP.md` for full stage specs.

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

**MCP verification rule (Studio / Roblox Studio MCP):**

When MCP is accessible, always use it. Do not skip MCP verification just because static checks pass.

**What requires MCP/Studio verification before committing (when MCP is accessible):**
Any change touching the following systems must be verified in Roblox Studio via MCP before the commit is made:
- `src/server/` — any server-side service (match state, teams, objectives, damage, economy, shop, extraction, loot, death drops, monsters)
- `src/client/` — any client controller (movement, camera, viewmodel, gun, sound, UI, animation)
- `src/shared/` — Constants, WeaponData, WeaponFeel, or any shared module that affects runtime behavior
- Remotes (`ReplicatedStorage/Remotes`) — any new or changed RemoteEvent / RemoteFunction
- Rojo config (`default.project.json`) — property changes that affect StarterPlayer, character spawning, or rig type
- Player spawning or character lifecycle
- Camera or UserInputService behavior (CameraType, MouseBehavior, FieldOfView)
- Viewmodel or weapon attachment changes
- Movement input (LeftShift, LeftAlt, C, any key binding)
- Combat (damage, hit validation, ammo, reload)
- All UI (HUD, MatchUI, DeathScreen, KillFeedUI, CrosshairUI, ObjectiveUI)
- Economy, inventory, shop, zone, or base systems (when built)
- Character rig changes (R6/R15 target, StarterPlayer.CharacterRigType)
- Animation loading, animation IDs, or AnimationTrack playback

**Workflow when MCP is accessible:**
1. Write or edit the code.
2. Run `rojo serve default.project.json` so changes sync into Studio.
3. Connect Studio MCP and run `rojo serve` so the MCP tool has a live session.
4. Use MCP to verify: play mode behavior, Output panel (no errors or unexpected warns), and the specific system's observable behavior.
5. Confirm the behavior matches the task spec.
6. Then commit and push.

Static checks (`selene`, `rojo build`, formatting) are a pre-condition, not a replacement. Static checks catch structural errors; they do not verify runtime behavior, animation playback, input handling, physics, UI layout, server–client data flow, or remote timing.

**When MCP is unavailable:**
- Do not claim Studio verification was performed.
- Prefer documentation, configuration, and static-validation tasks only.
- Avoid camera, viewmodel, combat, movement, match-loop, objective, replication, economy, and UI changes unless the user explicitly accepts that the change is unverified in Studio.
- Run only non-Studio validation that is available locally: `git diff`, `rojo build`, `selene`, formatting checks.
- Mark any gameplay-affecting change as "needs Studio verification" in `docs/TECHNICAL_DEBT.md` or the final response.
- Do not mark runtime technical debt fully resolved unless the behavior was actually verified in Studio.
- Clearly state "MCP unavailable — Studio verification was not performed" in the task response when this applies.

**Never claim a behavior was tested in Studio unless it was actually verified through MCP or a confirmed manual Studio test.** Stating "this should work" or "static checks pass" is not equivalent to Studio verification for any runtime system.

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
