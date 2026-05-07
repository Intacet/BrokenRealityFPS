# CHANGELOG.md

All notable changes to this project, newest first.

Format: `## [version or date] — description`
Under each entry: bullet points for what was added, changed, or removed.

---

## [2026-05-07] — Five project rules: Logger, no magic numbers, no silent failures, remote ownership, no circular requires

**Rule 1 — No circular requires (doc only)**
- Added rule to `CLAUDE.md`: never require a module that directly or indirectly requires the caller back; use a BindableEvent in `MatchEvents.lua` for bidirectional server communication; confirm one-way dependency direction before requiring

**Rule 2 — Remote ownership**
- Updated `docs/PROJECT_MAP.md`: expanded remote registry table from 4 to 5 columns — added **Listened by** column; changed **Fired by** from generic "Client"/"Server" labels to exact script filenames (`GunController.client.lua`, `GunService.server.lua`, `DamageService.lua`, `MatchService.server.lua`, `TeamService.server.lua`, `MatchController.client.lua`); rows for unbuilt systems marked `pending`
- Added rule to `CLAUDE.md`: register every remote in `docs/PROJECT_MAP.md` before implementing; one Fired by, one Listened by per remote; never fire or listen to an unregistered remote

**Rule 3 — No magic numbers**
- Audited all files in `src/server/` and `src/client/` for numeric literals that are not loop counters or table indices
- Added four new named constants to `src/shared/Constants.lua`:
  - `TELEPORT_Y_OFFSET = 3` — studs above a spawn part's centre so characters land on top (moved from local variable in `TeamService.server.lua`)
  - `COUNTDOWN_TICK = 1` — seconds between each broadcast inside a phase countdown (moved from `task.wait(1)` in `MatchService.server.lua`)
  - `LOBBY_POLL_INTERVAL = 2` — seconds between player-count checks while waiting for MIN_PLAYERS (moved from `task.wait(2)` in `MatchService.server.lua`)
  - `MATCH_END_PAUSE = 3` — seconds between end of one match and start of the next (moved from `task.wait(3)` in `MatchService.server.lua`)
- Added rule to `CLAUDE.md`: no numeric literal in any service or controller except loop counters and table indices

**Rule 4 — Logger.lua**
- Created `src/shared/Logger.lua` — `DEBUG_MODE = true` flag at top; `Logger.debug(...)` prints `[DEBUG]` prefix only when flag is true; `Logger.warn(...)` always calls Roblox `warn()` with `[WARN]` prefix; no other logic
- Updated all six source files to replace every `print()` with `Logger.debug()` and every `warn()` with `Logger.warn()`, and to require Logger via `Modules:WaitForChild("Logger")`:
  - `src/server/MatchService.server.lua`
  - `src/server/TeamService.server.lua`
  - `src/server/DamageService.lua`
  - `src/server/GunService.server.lua`
  - `src/client/MatchController.client.lua`
  - `src/client/GunController.client.lua`
- Added rule to `CLAUDE.md`: never call `print()` or `warn()` directly; always use Logger

**Rule 5 — No silent failures**
- Audited all files in `src/server/` and `src/client/` for unlogged failures; found and fixed three:
  - `src/server/TeamService.server.lua` `teleportToSpawn()` — nil `character` returned silently → now calls `Logger.warn("[TeamService] teleportToSpawn: character is nil for <name> — skipping")`
  - `src/server/TeamService.server.lua` `teleportToSpawn()` — nil `HumanoidRootPart` returned silently → now calls `Logger.warn("[TeamService] teleportToSpawn: HumanoidRootPart missing for <name> — skipping")`
  - `src/server/GunService.server.lua` — `typeof` guard for invalid Vector3 payload returned silently → now calls `Logger.warn("[GunService] WeaponFired: invalid payload types from <name>")`
- Added rule to `CLAUDE.md`: every `pcall` failure branch must log with `Logger.warn()`; every unexpected nil return must log with `Logger.warn()`

**Debt evaluation**
- Updated `docs/TECHNICAL_DEBT.md`:
  - DEBT-004: marked partially resolved — `TELEPORT_Y_OFFSET` moved to Constants; `ATTACKER_COLOR`/`DEFENDER_COLOR` remain local (BrickColor values fall outside the no-magic-numbers rule); colour-duplication risk persists
  - DEBT-010: corrected stale file reference from `DamageService.server.lua` to `DamageService.lua`
  - Added DEBT-016: `Logger.DEBUG_MODE` is a source-level flag — shipping with debug output visible requires a manual code edit; fix is `RunService:IsStudio()` guard

---

## [2026-05-06] — GunController + CLAUDE.md debt-resolution rule

- Added `src/client/GunController.client.lua` — listens to left mouse button via `UserInputService`; gates shots on `MatchController:GetPhase() == ACTIVE`; enforces client-side rate limit from `WeaponData["AssaultRifle"].fireRate`; casts a client-side ray from `workspace.CurrentCamera` (result not yet used — placeholder for future viewmodel hit FX); fires `WeaponFired:FireServer(origin, direction, now)`; listens to `HitConfirmed` and prints `HIT` (placeholder for hitmarker); listens to `HealthChanged` and prints current/max health (placeholder for HUD)
- Updated `CLAUDE.md`: appended new Claude behavior rule — when a task touches a debt entry, evaluate whether the underlying risk is genuinely gone before marking it resolved, not just whether the requested fix was applied
- Updated `docs/TECHNICAL_DEBT.md`: added DEBT-015 (MatchController.client.lua must be renamed MatchController.lua — blocking prerequisite identical to the DEBT-012 pattern); updated DEBT-013 to reflect that GunController also has a hardcoded `CURRENT_WEAPON` that doubles the sync risk; corrected stale file reference in DEBT-009 (`DamageService.server.lua` → `DamageService.lua`)

---

## [2026-05-06] — Resolve DEBT-012: rename DamageService to ModuleScript

- Renamed `src/server/DamageService.server.lua` → `src/server/DamageService.lua` — Rojo maps `.server.lua` to Script and `.lua` to ModuleScript; the old name prevented `require()` from GunService at runtime; logic is identical, only the file header comment changed (`-- Script` → `-- ModuleScript`)
- `default.project.json` unchanged — server folder is mapped by directory path, not by explicit file list
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-012 resolved with today's date

---

## [2026-05-06] — GunService

- Added `src/server/GunService.server.lua` — validates client shot requests server-side; listens to `WeaponFired` RemoteEvent; enforces ACTIVE-phase gate, Vector3 type guard, per-player rate limit (from WeaponData.fireRate), and server raycast; calls `DamageService:Apply(victim, damage, shooter)` on a confirmed hit; fires `HitConfirmed` back to the shooter client for a cosmetic hitmarker; cleans up `lastShotTime` on `PlayerRemoving`
- Updated `src/shared/WeaponData.lua` — replaced stub comment with first real entry: `WeaponData["AssaultRifle"] = { damage = 25, fireRate = 0.1, range = 300 }`
- Updated `docs/TECHNICAL_DEBT.md` — updated DEBT-009 (friendly-fire guard now actively triggered by GunService); added DEBT-012 (DamageService.server.lua must be renamed to DamageService.lua — blocking prerequisite before GunService can run); added DEBT-013 (hardcoded DEFAULT_WEAPON until GunController supplies weapon name in payload); added DEBT-014 (clientTick received but not validated against shot-replay window)

---

## [2026-05-06] — Fix three bugs from DamageService/TeamService tasks

- `src/server/TeamService.server.lua`: removed dead `local TeamService = {}` table, `TeamService:GetTeam()` method, and `return TeamService` — TeamService is a `.server.lua` Script and cannot be required, so the public API was unreachable; replaced with a comment explaining that team data is accessed via `MatchEvents.TeamAssigned`
- `src/server/MatchEvents.lua`: `MatchEvents.TeamAssigned` BindableEvent confirmed present (was already added when DamageService was written; no change needed)
- `src/shared/Constants.lua`: `Constants.MAX_HEALTH = 100` confirmed present (was already added when DamageService was written; no change needed)
- `docs/TECHNICAL_DEBT.md`: added DEBT-011 — no on-demand team query path exists for services that miss the TeamAssigned event window; fix when a late-loading service needs `TeamData.GetTeam(player)`

---

## [2026-05-06] — DamageService + DEBT-006 resolution

- Added `src/server/DamageService.server.lua` — server-authoritative health tracking; `DamageService:Apply(victim, amount, attacker)` clamps damage and calls `killPlayer()` when health reaches zero; `HealthChanged` fires to the victim's client on every health change; health resets to `MAX_HEALTH` on every PREP phase for all connected players; `playerHealth` and `playerTeam` tables are cleared on `PlayerRemoving`
- Added `Constants.MAX_HEALTH = 100` to `src/shared/Constants.lua` — single source of truth for starting and maximum health (config module rule)
- Updated `src/server/MatchEvents.lua`: added `MatchEvents.TeamAssigned = Instance.new("BindableEvent")` — fired per-player inside TeamService's `assignTeams()`, consumed by DamageService for team tracking
- Updated `src/server/TeamService.server.lua`: added `MatchEvents.TeamAssigned:Fire(player, teamName)` inside the `assignTeams()` loop — resolves DEBT-006
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-006 resolved; added DEBT-009 (no friendly-fire guard in Apply() yet) and DEBT-010 (health reset during mid-respawn may cause brief Humanoid mismatch)

---

## [2026-05-06] — Resolve DEBT-008: GetMatchConfig errors now visible in Output

- Updated `src/client/MatchController.client.lua`: split the pcall `else` branch into two cases — `not ok` now calls `warn()` with the actual error string (red in Output) rather than a generic print; `ok` with a nil result keeps the original timing-fallback print
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-008 resolved with today's date

---

## [2026-05-06] — Technical debt tracking added

- Created `docs/TECHNICAL_DEBT.md` — running registry of known maintenance risks and deferred problems; 8 entries covering: Phase type sync (DEBT-001), RemoteSetup Folder cast resolved (DEBT-002), lastFiredPhase phase-only comparison (DEBT-003), TeamService colours/offset not in Constants (DEBT-004), odd player split bias (DEBT-005), playerTeams has no observer signal (DEBT-006), MatchController applyState growth risk (DEBT-007), pcall silently swallows GetMatchConfig errors (DEBT-008)
- Updated `CLAUDE.md`: added `docs/TECHNICAL_DEBT.md` to the required reading list; added two new Claude behavior rules — (1) add every flagged risk to TECHNICAL_DEBT.md before finishing a task, (2) read TECHNICAL_DEBT.md at the start of every task and report which entries are relevant before writing code

---

## [2026-05-06] — Fix PhaseChanged firing once per second instead of once per transition

- Updated `src/server/MatchService.server.lua`: added `lastFiredPhase = ""` to the State block; wrapped `MatchEvents.PhaseChanged:Fire()` in a `phase ~= lastFiredPhase` guard so it fires exactly once per phase transition rather than every second — all current and future listeners (TeamService, ObjectiveService) are automatically protected

---

## [2026-05-06] — Wire MatchService → MatchEvents

- Updated `src/server/MatchService.server.lua`: added `require(MatchEvents)` in the dependencies block; added `MatchEvents.PhaseChanged:Fire(phase, round)` inside `broadcast()` after `FireAllClients` — TeamService and future ObjectiveService now receive phase signals without polling

---

## [2026-05-06] — TeamService + MatchEvents bridge

- Added `src/server/MatchEvents.lua` — server-only ModuleScript holding `PhaseChanged` BindableEvent; bridges MatchService → TeamService (and future ObjectiveService) without polling; includes instructions for the two lines that must be added to MatchService to activate the connection
- Added `src/server/TeamService.server.lua` — assigns players to Roblox Teams on PREP, teleports each to a random spawn in `Workspace/Spawns/Attackers` or `Workspace/Spawns/Defenders`, fires `TeamAssigned` to each client, resets on RESULTS; handles missing spawn folders gracefully; exposes `TeamService:GetTeam(player)` for DamageService and ObjectiveService

---

## [2026-05-06] — MatchController (client)

- Added `src/client/MatchController.client.lua` — client-side match state mirror; syncs on join via `GetMatchConfig`, then stays current via `RoundStateChanged`; stores `currentPhase`, `currentRound`, `currentTimeLeft`, `currentMaxRounds` locally; prints state to Output for verification; exposes `GetPhase`, `GetRound`, `GetTimeLeft`, `GetMaxRounds` for MatchUI to call once built

---

## [2026-05-06] — Two type-safety fixes

- `src/server/RemoteSetup.server.lua`: fixed unsafe nil cast — `FindFirstChild` result is now left as `Instance?`, nil-checked first, then narrowed with `:: Folder` only inside the branch where nil is already ruled out
- `src/shared/Types.lua`: added a prominent sync warning on the `Phase` union explaining that Luau cannot derive it from `Constants.Phase` at compile time, and that both files must be updated together whenever a phase is added or renamed

---

## [2026-05-06] — Coding rules expanded in CLAUDE.md and PROJECT_RULES.md

- Added explicit "Config modules" rule: tunable values must live in `ReplicatedStorage/Modules`, never hardcoded
- Added "Explaining changes" rule: every task must list every changed file, explain how new code connects to existing systems, flag maintenance risks, and provide test steps
- These rules now appear in both `CLAUDE.md` (Claude behavior section + code rules) and `docs/PROJECT_RULES.md`

---

## [2026-05-06] — Stage 1 infrastructure + MatchService

- Added `default.project.json` (Rojo project), `wally.toml`, `selene.toml`, `stylua.toml`
- Added `src/shared/Constants.lua` — Phase enum (LOBBY, PREP, ACTIVE, RESULTS), all timing values, MAX_ROUNDS, MIN_PLAYERS
- Added `src/shared/Types.lua` — `Phase` and `RoundStatePayload` type exports
- Added `src/shared/WeaponData.lua` — stub, populated when GunService is built
- Added `src/shared/ZoneData.lua` — stub, populated when ZoneService is built
- Added `src/server/RemoteSetup.server.lua` — creates all RemoteEvents and RemoteFunctions in ReplicatedStorage/Remotes at server start
- Added `src/server/MatchService.server.lua` — full match loop: Lobby → (Prep → Active → Results) × 5, fires RoundStateChanged every second, handles GetMatchConfig for late-joining clients, exposes RoundEndedEarly BindableEvent for ObjectiveService
- Updated `docs/NAMING.md` — added PREP phase, corrected file extension table (`.server.lua`, `.client.lua`, `.lua`)
- Updated `docs/ROADMAP.md` — checked off Stage 1 items and MatchService

---

## [2026-05-06] — Project initialized

- Created `CLAUDE.md` with game concept, toolchain, folder structure, server/client rules, build order, and Claude behavior guidelines
- Created `docs/PROJECT_RULES.md`
- Created `docs/PROJECT_MAP.md`
- Created `docs/NAMING.md`
- Created `docs/ROADMAP.md`
- Created `docs/CHANGELOG.md`

No game code written yet. Infrastructure and documentation only.
