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

## [DEBT-006] playerTeams table has no signal for observers

**File:** `src/server/TeamService.server.lua`
**Risk:** `playerTeams` is a plain `{ [Player]: string }` table. Any service that needs to know a player's team must call `TeamService:GetTeam(player)` by requiring TeamService and polling at the moment they need the value. There is no event that fires when a player is assigned. If two or more services need to react *at the moment of assignment* (rather than querying lazily), they have no clean hook.
**Trigger:** Adding DamageService (needs team for friendly-fire), ObjectiveService (needs team to validate who can plant an anchor), or any system that must respond immediately when teams are set — rather than checking on demand.
**Fix when:** Two or more services need to subscribe to team assignment events. Add a `MatchEvents.TeamAssigned` BindableEvent fired per-player inside `assignTeams()`, mirroring the pattern already used for `PhaseChanged`.

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
