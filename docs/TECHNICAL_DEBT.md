# TECHNICAL_DEBT.md

A running list of known maintenance risks, shortcuts, and deferred problems flagged during development.

**This is not a changelog.** Completed work belongs in `CHANGELOG.md`. This file tracks things that still need attention. Mark an entry `RESOLVED` and add the fix date when the underlying issue is addressed — do not delete entries.

---

## [DEBT-001] Phase type union manually duplicated from Constants.Phase

**File:** `src/shared/Types.lua` and `src/shared/Constants.lua`
**Risk:** `export type Phase` in `Types.lua` is a manually written string union `"LOBBY" | "PREP" | "ACTIVE" | "RESULTS"`. Luau has no `keyof` or value-union derivation, so this cannot be derived from the `Constants.Phase` table. Both declarations must be updated together whenever a phase is added or renamed. If only one is changed, the type system will silently allow invalid phase strings through any code that reads from the table but type-checks against the union.
**Trigger:** Adding a new phase (e.g. `"OVERTIME"`) to `Constants.Phase` without adding it to the `Types.Phase` union, or vice versa.
**Fix when:** Luau adds a mechanism to derive a union type from a table's value set, or when a phase is added and both files must be touched anyway — at that point, annotate each `Constants.Phase` value as `:: Types.Phase` so the compiler enforces the relationship.

---

## [DEBT-002] RemoteSetup Folder cast before nil check — RESOLVED 2026-05-06

**File:** `src/server/RemoteSetup.server.lua`
**Risk:** ~~`FindFirstChild("Remotes") :: Folder` cast the result before the nil check, which was unsound under `--!strict` — if `FindFirstChild` returned `nil`, the cast told the type system it was a `Folder` when it was not.~~
**Resolution:** Fixed in the "Two type-safety fixes" task. `FindFirstChild` result is now stored as `Instance?`, nil-checked first, then cast to `:: Folder` only inside the branch where nil is already ruled out.

---

## [DEBT-003] lastFiredPhase compares phase string only, not (phase, round) pair

**File:** `src/server/MatchService.server.lua`
**Risk:** `lastFiredPhase` is a plain string. `MatchEvents.PhaseChanged` fires on phase transitions (e.g. RESULTS → PREP), which is correct for current listeners. However, the guard does not distinguish *which round* the phase belongs to. A listener that needs to know "PREP for round 3 specifically vs round 4" — for example, a per-round escalation system — cannot get that from a phase-only comparison.
**Trigger:** Adding a listener to `MatchEvents.PhaseChanged` that needs to act differently per round (e.g. HordeService increasing spawn budget each round). The listener would receive the correct phase but have no way to know it was a fresh round vs the same phase it already handled, if the guard were extended to suppress repeat firings.
**Fix when:** Any system needs round-level granularity from `PhaseChanged`. Add `local lastFiredRound = -1` alongside `lastFiredPhase`, and change the guard to `phase ~= lastFiredPhase or round ~= lastFiredRound`.

---

## [DEBT-004] Team colours and teleport offset are local to TeamService, not in Constants

**File:** `src/server/TeamService.server.lua`
**Risk:** `ATTACKER_COLOR`, `DEFENDER_COLOR`, and `TELEPORT_Y_OFFSET` are defined as local constants inside TeamService. If another system (kill feed, HUD team indicator, spectator camera) needs to read team colours, it will either hardcode them again or have no access to them — creating duplicate magic values.
**Trigger:** Adding a kill feed, name tag, or any UI that needs to tint elements by team colour. Adding a second teleportation site that needs the same Y offset.
**Fix when:** Any system outside TeamService needs to read team colours or the teleport offset. Move them to `src/shared/Constants.lua` at that point.

---

## [DEBT-005] Odd player counts always give the extra player to Attackers

**File:** `src/server/TeamService.server.lua`
**Risk:** `assignTeams()` splits players with `math.ceil(n/2)` going to Attackers. With 3 players the split is 2v1; with 5 it is 3v2. Attackers always have the numerical advantage on odd counts. This is a deliberate simplification, not a bug, but it will feel unfair once the player count grows and balance matters.
**Trigger:** The game reaches a point where balance is actively tested and odd-count matches are common (likely at the end of Milestone 0 playtesting).
**Fix when:** Playtesting reveals the split is consistently unfair, or when a balance pass is scheduled. Fix by alternating which team gets the extra player each round, or by enforcing even player counts before a round can start.

---

## [DEBT-006] playerTeams table has no signal for observers — RESOLVED 2026-05-06

**File:** `src/server/TeamService.server.lua`
**Risk:** ~~`playerTeams` is a plain `{ [Player]: string }` table. Any service that needs to know a player's team must call `TeamService:GetTeam(player)` by requiring TeamService and polling at the moment they need the value. There is no event that fires when a player is assigned.~~
**Resolution:** Added `MatchEvents.TeamAssigned = Instance.new("BindableEvent")` to `src/server/MatchEvents.lua`. `assignTeams()` now fires `MatchEvents.TeamAssigned:Fire(player, teamName)` per player. `DamageService` subscribes to this event and maintains its own `playerTeam` table, avoiding cross-require coupling.

---

## [DEBT-009] DamageService:Apply() has no friendly-fire enforcement yet

**File:** `src/server/DamageService.lua`
**Risk:** `Apply()` tracks the attacker and victim but does not yet check whether they are on the same team. The `playerTeam` table is populated and `GetTeam()` is exposed, but the friendly-fire guard (`if playerTeam[victim] == playerTeam[attacker] then return end`) is not written. Any weapon that calls `Apply()` will hit teammates.
**Trigger:** GunService is now built and calls `Apply()`. Friendly fire is live.
**Fix when:** Immediately — add the team-equality check at the top of `Apply()` before the damage calculation, along with a design decision on whether friendly fire should be blocked entirely or penalised (reflected damage, etc.).

---

## [DEBT-011] No on-demand team query path exists for services that miss TeamAssigned

**File:** `src/server/TeamService.server.lua`, `src/server/MatchEvents.lua`
**Risk:** Team assignments are distributed once per PREP phase via `MatchEvents.TeamAssigned`. Any service that starts after PREP (or requires at a moment after assignments have already fired) will have an empty team table and no way to back-fill. There is currently no shared module that a service can read to find a player's current team on demand — TeamService is a `.server.lua` Script and cannot be required, and there is no `TeamData` ModuleScript.
**Trigger:** A new service that is added later in the build order and needs to know a player's team at an arbitrary moment (e.g. a late-loading ObjectiveService that checks team on first touch rather than on assignment). It will miss the TeamAssigned events that fired at PREP and have no fallback.
**Fix when:** Any service needs to query a player's current team outside of the TeamAssigned subscription window. Create a `src/server/TeamData.lua` ModuleScript that TeamService writes to on assignment and reset, and that other services read from via `TeamData.GetTeam(player)`.

---

## [DEBT-012] DamageService.server.lua must be renamed to DamageService.lua before GunService works — RESOLVED 2026-05-06

**File:** `src/server/DamageService.server.lua`
**Risk:** ~~`GunService.server.lua` calls `require(script.Parent:WaitForChild("DamageService"))`. In Roblox, `require()` only accepts a ModuleScript. A file named `DamageService.server.lua` creates a Script instance, not a ModuleScript — so `require()` will throw at runtime.~~
**Resolution:** Renamed `src/server/DamageService.server.lua` → `src/server/DamageService.lua`. Rojo maps `.lua` files in `src/server/` to ModuleScript instances, so `require()` in GunService now resolves correctly. `default.project.json` uses a folder-level `$path` mapping and required no changes. File header updated from `-- Script` to `-- ModuleScript`. Logic unchanged.

---

## [DEBT-013] Weapon name is hardcoded on both client and server instead of sent in the payload

**Files:** `src/server/GunService.server.lua`, `src/client/GunController.client.lua`
**Risk:** `DEFAULT_WEAPON = "AssaultRifle"` in GunService and `CURRENT_WEAPON = "AssaultRifle"` in GunController are two independent hardcodes that must be kept in sync. GunController is now built but the `WeaponFired` payload is `{origin, direction, tick}` with no weapon name — so the server cannot know what weapon the client is using. With a single weapon this is invisible. With multiple weapons, every shot is validated against AssaultRifle stats regardless of what the player holds.
**Trigger:** Adding a second weapon to WeaponData, or giving players a loadout choice.
**Fix when:** Multiple weapons exist. Add `weaponName: string` to the `WeaponFired` payload, validate it exists in WeaponData on the server (never trust the client's name blindly — verify it is a real entry), and remove both hardcodes.

---

## [DEBT-014] WeaponFired clientTick is received but not validated

**File:** `src/server/GunService.server.lua`
**Risk:** The `tick` value sent with each `WeaponFired` event is intended to let the server reject shots with timestamps too far in the past (replay attacks or lag compensation abuse). Currently `_clientTick` is discarded. Without this check, a client could theoretically queue up shots during lag and dump them all at once, bypassing the server-side rate limiter — though the rate limiter's `os.clock()` comparison already partially mitigates this.
**Trigger:** The game is stress-tested with high-latency clients or an exploiter attempts shot-replay injection.
**Fix when:** Combat is otherwise stable. Add a maximum acceptable age check: `if os.clock() - clientTick > MAX_SHOT_AGE then return end` where `MAX_SHOT_AGE` accounts for typical RTT plus a tolerance (e.g. 0.5 s). Add `MAX_SHOT_AGE` to Constants.

---

## [DEBT-015] MatchController.client.lua must be renamed MatchController.lua before GunController works

**File:** `src/client/MatchController.client.lua`
**Risk:** `GunController.client.lua` calls `require(script.Parent:WaitForChild("MatchController"))`. In Roblox, `require()` only accepts a ModuleScript. A file named `MatchController.client.lua` creates a LocalScript instance — `require()` will throw at runtime. GunController is architecturally correct; the file extension is wrong. The game will error on the client on startup until this is fixed.
**Trigger:** This is blocking — GunController cannot run until it is resolved.
**Fix when:** Immediately. Rename `src/client/MatchController.client.lua` → `src/client/MatchController.lua`. The `MatchController:Start()` call at the bottom of the file already handles self-initialization on first `require()`, so no runner script is needed. Update the header comment from `-- LocalScript` to `-- ModuleScript`. Logic unchanged.

---

## [DEBT-010] DamageService health reset fires for all players including mid-respawn characters

**File:** `src/server/DamageService.server.lua`
**Risk:** On PREP, `resetHealth()` calls `setHealth(player, MAX_HEALTH)` and fires `HealthChanged` to the client for every connected player. If a player is mid-respawn (character is nil or Humanoid is being created), the client receives a correct health value but the Humanoid itself may reset to its default health independently when the new character loads — causing a brief mismatch between the server table and the Humanoid's displayed value.
**Trigger:** A player disconnects or dies in the final second of RESULTS, so their character is respawning exactly when PREP begins and `resetHealth()` fires.
**Fix when:** CorpseService is built (it owns character lifecycle). At that point, hook health reset into `CharacterAdded` instead of relying solely on the phase-change event.

---

## [DEBT-007] applyState is the only mutation point in MatchController — will grow

**File:** `src/client/MatchController.client.lua`
**Risk:** `applyState()` is the single function that writes to local state and currently calls `print()`. When MatchUI is built, a UI update call will be added here. If CutsceneController, HUD, and ObjectiveUI all need to react to phase changes, they will each add a call inside `applyState()`, making it a growing list of side effects in one function.
**Trigger:** Adding MatchUI (Stage 3 of the roadmap) — the first UI that needs to read from MatchController.
**Fix when:** A second system needs to react to phase changes. Replace the `print()` with a `BindableEvent:Fire(payload)` that any client system can connect to, rather than adding direct calls inside `applyState()`.

---

## [DEBT-008] pcall on GetMatchConfig silently swallows server errors — RESOLVED 2026-05-06

**File:** `src/client/MatchController.client.lua`
**Risk:** ~~`GetMatchConfig:InvokeServer()` is wrapped in `pcall`. If `MatchService` has a bug in its `OnServerInvoke` handler — an error thrown, a nil return, a missing field — the `pcall` catches it, prints a generic fallback message, and the controller continues with stale default state (LOBBY, round 0). This makes a server-side logic error look like a timing issue and is easy to miss.~~
**Resolution:** The `else` branch now distinguishes two cases. `not ok` (genuine error thrown server-side) calls `warn("[MatchController] GetMatchConfig error:", result)` where `result` is the error string — visible as red output. `ok` with a nil result keeps the original print, since that is a genuine timing edge case and not an error.
