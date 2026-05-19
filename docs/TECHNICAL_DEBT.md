# TECHNICAL_DEBT.md

A running list of known maintenance risks, shortcuts, and deferred problems flagged during development.

**This is not a changelog.** Completed work belongs in `CHANGELOG.md`. This file tracks things that still need attention. Mark an entry `RESOLVED` and add the fix date when the underlying issue is addressed — do not delete entries.

---

## Severity legend

- **Critical** — blocks core playtest, match flow, security, or core combat correctness.
- **High** — likely to cause visible bugs, exploit risk, or serious multiplayer issues soon.
- **Medium-High** — not immediately broken, but likely to block the next few systems.
- **Medium** — real maintenance or quality risk, but not urgent.
- **Low-Medium** — fix opportunistically when touching the related system.
- **Low** — documentation, future-proofing, or rare-trigger issue.
- **Resolved** — retained for history only.

---

## [DEBT-036] Round-based architecture no longer matches target persistent-zone design — ADDED 2026-05-15

**Files:** `src/server/MatchService.server.lua`, `src/server/TeamService.server.lua`, `src/server/ObjectiveService.server.lua`, `src/client/UI/MatchUI.lua`, `src/client/UI/DeathScreen.lua`, `src/client/MatchController.lua`
**Severity:** High
**Studio verification required:** Yes
**Risk:** The current running codebase implements a five-round attackers-vs-defenders FPS loop. The target product direction (updated 2026-05-15) is a persistent PvPvE zone shooter with carried loot, secured funds, extraction exits, shops, and base progression. The existing round-based services (`MatchService`, `TeamService`, `ObjectiveService`) and their client counterparts (`MatchController`, `MatchUI`, `DeathScreen`) encode round-start, round-end, PREP/ACTIVE/RESULTS phase transitions, team assignment, and objective completion as core concepts. None of these map directly to the persistent zone loop.

**Affected legacy systems:**
- `MatchService` — round loop, phase management; must be replaced or dormant when ZoneService is built
- `TeamService` — Attackers/Defenders split; spawn logic will need to become faction/base-spawn management
- `ObjectiveService` — anchor planting, objective win conditions; will need to become zone events or contracts
- `MatchUI` — displays round countdown, results screen; irrelevant in a persistent zone
- `DeathScreen` — triggers on `RagdollApplied` + cleaned up on PREP; PREP cleanup path breaks without rounds; should adapt to zone death/respawn choice screen
- Round scoring, win conditions, and `RoundStateChanged` payload format — all round-specific
- No-respawn assumption — `TeamService` disables `CharacterAutoLoads` and loads characters only on PREP; persistent zone requires continuous respawn; this assumption is incompatible with always-open re-entry (see DEBT-019)
- Old objective win conditions — `ObjectiveService` treats anchor completion as a match-ending event; persistent zone has no match end

**What carries forward as-is:** `GunService`, `DamageService`, `RagdollService`, `GunController`, `ViewModelController`, `SoundController`, `HUD` (ammo/health panels), `KillFeedUI`, `WeaponData`, `Logger`, `Constants`.

**Migration approach:**
- Build new persistent zone services (`ZoneService`, `EconomyService`, `BaseService`, etc.) alongside the legacy services, not replacing them immediately.
- Do not expand legacy services with new round-specific features.
- Retire legacy services one at a time when their replacement is tested.
- `RoundStateChanged` and associated phase constants may be repurposed or replaced with a `ZoneStateChanged` remote when ZoneService is built.
- Every new persistent-zone system must be built in stages and verified in Studio before the next system is started. Do not batch multiple new services into one prompt.

**Resolve when:** The core persistent zone loop (zone entry → loot → extract → deposit → armory → zone) is working in Studio and the legacy round-based systems are no longer needed for active play.

**Roadmap reference:** `docs/PERSISTENT_ZONE_ROADMAP.md` defines the 11-stage staged build order for the persistent zone pivot. That document is planning-only — it does not resolve this debt entry. Runtime systems must still be built and verified in Studio stage by stage before this entry can be closed.

---

## [DEBT-001] Phase type union manually duplicated from Constants.Phase — PARTIALLY RESOLVED 2026-05-07

**File:** `src/shared/Types.lua` and `src/shared/Constants.lua`
**Severity:** Low
**Studio verification required:** No
**Risk:** `export type Phase` in `Types.lua` is a manually written string union. Luau has no `keyof` or value-union derivation, so this cannot be derived from the `Constants.Phase` table. Both declarations must be updated together whenever a phase is added or renamed. If only one is changed, the type system will silently allow invalid phase strings through any code that reads from the table but type-checks against the union.
**Partial resolution (2026-05-07):** The `"MATCHEND"` phase was added to both `Constants.Phase` and the `Types.Phase` union at the same time (Batch 1 task). Both files currently list exactly the same five phases: LOBBY, PREP, ACTIVE, RESULTS, MATCHEND. The structural risk — no compiler enforcement of the sync — remains because Luau still has no `keyof` equivalent.
**Trigger:** Adding any new phase to `Constants.Phase` without adding it to the `Types.Phase` union, or vice versa.
**Fix when:** Luau adds a mechanism to derive a union type from a table's value set, or when a phase is added and both files must be touched anyway — at that point, annotate each `Constants.Phase` value as `:: Types.Phase` so the compiler enforces the relationship.

---

## [DEBT-002] RemoteSetup Folder cast before nil check — RESOLVED 2026-05-06

**File:** `src/server/RemoteSetup.server.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`FindFirstChild("Remotes") :: Folder` cast the result before the nil check, which was unsound under `--!strict` — if `FindFirstChild` returned `nil`, the cast told the type system it was a `Folder` when it was not.~~
**Resolution:** Fixed in the "Two type-safety fixes" task. `FindFirstChild` result is now stored as `Instance?`, nil-checked first, then cast to `:: Folder` only inside the branch where nil is already ruled out.

---

## [DEBT-003] lastFiredPhase compares phase string only, not (phase, round) pair — LEGACY/TRANSITIONAL

**File:** `src/server/MatchService.server.lua`
**Severity:** Low-Medium (legacy — MatchService is transitional; see DEBT-036)
**Studio verification required:** Yes
**Risk:** `lastFiredPhase` is a plain string. `MatchEvents.PhaseChanged` fires on phase transitions (e.g. RESULTS → PREP), which is correct for current listeners. However, the guard does not distinguish *which round* the phase belongs to. A listener that needs to know "PREP for round 3 specifically vs round 4" — for example, a per-round escalation system — cannot get that from a phase-only comparison.
**Trigger:** Adding a listener to `MatchEvents.PhaseChanged` that needs to act differently per round (e.g. HordeService increasing spawn budget each round). The listener would receive the correct phase but have no way to know it was a fresh round vs the same phase it already handled, if the guard were extended to suppress repeat firings.
**Fix when:** Any system needs round-level granularity from `PhaseChanged`. Add `local lastFiredRound = -1` alongside `lastFiredPhase`, and change the guard to `phase ~= lastFiredPhase or round ~= lastFiredRound`.

---

## [DEBT-004] Team colours are local to TeamService, not in Constants — PARTIALLY RESOLVED 2026-05-07

**File:** `src/server/TeamService.server.lua`
**Severity:** Low
**Studio verification required:** No
**Risk:** ~~`ATTACKER_COLOR`, `DEFENDER_COLOR`, and `TELEPORT_Y_OFFSET` are defined as local constants inside TeamService.~~ `ATTACKER_COLOR` and `DEFENDER_COLOR` are still defined as local constants inside TeamService. If another system (kill feed, HUD team indicator, spectator camera) needs to read team colours, it will either hardcode them again or have no access to them — creating duplicate magic values.
**Partial resolution (2026-05-07):** `TELEPORT_Y_OFFSET` was moved to `src/shared/Constants.lua` during the "No magic numbers" audit. The offset value is no longer duplicated. `ATTACKER_COLOR` and `DEFENDER_COLOR` were not moved because `BrickColor` values are not numeric literals — they fall outside the no-magic-numbers rule. The underlying colour-duplication risk remains.
**Further resolution (2026-05-07):** `KillFeedUI` was the trigger — a second system needing team colours. `Color3` variants for UI tinting (`COLOR_TEAM_ATTACKERS`, `COLOR_TEAM_DEFENDERS`, `COLOR_TEAM_NEUTRAL`) were added to `src/shared/Constants.lua`. `KillFeedUI` reads from these constants; no new magic values were introduced. TeamService's `BrickColor` values (`ATTACKER_COLOR`, `DEFENDER_COLOR`) remain as local module constants because (a) they drive Roblox `Team.TeamColor` which requires `BrickColor`, not `Color3`, and (b) TeamService is a `.server.lua` Script that cannot be updated in this task scope.
**Remaining risk:** TeamService's `BrickColor` values are still not in Constants. If a future system needs BrickColor team values, it must add them to Constants separately. The Color3 UI values are now canonical and safe to use from any client UI.
**Trigger for full resolution:** Any system outside TeamService needing the `BrickColor` team colours. At that point, add `Constants.BRICKCOLOR_TEAM_ATTACKERS` and `Constants.BRICKCOLOR_TEAM_DEFENDERS` and replace the local declarations in TeamService.

---

## [DEBT-005] Odd player counts always give the extra player to Attackers — LEGACY/TRANSITIONAL

**File:** `src/server/TeamService.server.lua`
**Severity:** Medium (legacy — TeamService is transitional; see DEBT-036)
**Studio verification required:** Yes
**Risk:** `assignTeams()` splits players with `math.ceil(n/2)` going to Attackers. With 3 players the split is 2v1; with 5 it is 3v2. Attackers always have the numerical advantage on odd counts. This is a deliberate simplification, not a bug, but it will feel unfair once the player count grows and balance matters.
**Trigger:** The game reaches a point where balance is actively tested and odd-count matches are common (likely at the end of Milestone 0 playtesting).
**Fix when:** Playtesting reveals the split is consistently unfair, or when a balance pass is scheduled. Fix by alternating which team gets the extra player each round, or by enforcing even player counts before a round can start.

---

## [DEBT-006] playerTeams table has no signal for observers — RESOLVED 2026-05-06

**File:** `src/server/TeamService.server.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`playerTeams` is a plain `{ [Player]: string }` table. Any service that needs to know a player's team must call `TeamService:GetTeam(player)` by requiring TeamService and polling at the moment they need the value. There is no event that fires when a player is assigned.~~
**Resolution:** Added `MatchEvents.TeamAssigned = Instance.new("BindableEvent")` to `src/server/MatchEvents.lua`. `assignTeams()` now fires `MatchEvents.TeamAssigned:Fire(player, teamName)` per player. `DamageService` subscribes to this event and maintains its own `playerTeam` table, avoiding cross-require coupling.

---

## [DEBT-009] DamageService:Apply() friendly-fire guard — CODE IMPROVED, NEEDS STUDIO VERIFICATION (2026-05-15)

**File:** `src/server/DamageService.lua`
**Severity:** Critical
**Studio verification required:** Yes
**Risk:** ~~`Apply()` tracks the attacker and victim but does not yet check whether they are on the same team. The `playerTeam` table is populated and `GetTeam()` is exposed, but the friendly-fire guard was not written. Any weapon that called `Apply()` would hit teammates.~~
**Code-side fix (2026-05-15):** `Constants.FRIENDLY_FIRE_ENABLED = false` added to `src/shared/Constants.lua` (Combat rules section). A friendly-fire guard added to `DamageService:Apply()` using direct `playerTeam[]` cache lookups. When `FRIENDLY_FIRE_ENABLED == false` and both players had cached team entries, same-team shots returned early without mutating health, firing `HealthChanged`, or calling `RagdollService`.
**Improved (2026-05-15):** Guard refactored to use a new `getTeamName(player: Player): string?` private helper. Lookup order: (1) `playerTeam[player]` cache (populated at PREP via `MatchEvents.TeamAssigned`); (2) `player.Team.Name` fallback if the cache entry is nil. This protects late-joiners and players who missed `TeamAssigned` but have a Roblox Team object assigned. If both sources return nil, the guard does not block — unknown team membership is never assumed to be same-team. `Constants.FRIENDLY_FIRE_ENABLED` is the explicit toggle; setting it `true` re-enables full friendly fire without a code change.
**MCP unavailable:** Neither the initial fix nor the improvement was tested in Roblox Studio. Runtime behavior must be verified before this is marked resolved.
**Runtime test required:**
1. Start a play session. Reach ACTIVE phase with at least two players on the same team.
2. Have one Attacker shoot another. Confirm health does not decrease and no death screen appears. Check Output for `[DamageService] Blocked friendly fire:`.
3. Have an Attacker shoot a Defender. Confirm the Defender's health decreases normally.
4. Simulate a late-joiner (player who missed TeamAssigned but has `Player.Team` set): confirm the `Player.Team.Name` fallback still blocks same-team damage.
5. Set `Constants.FRIENDLY_FIRE_ENABLED = true`. Repeat steps 2–3; both shots should now deal damage.
**Resolve when:** Steps 1–5 above pass in Studio play mode with MCP available.

---

## [DEBT-011] No on-demand team query path exists for services that miss TeamAssigned

**File:** `src/server/TeamService.server.lua`, `src/server/MatchEvents.lua`
**Severity:** Medium
**Studio verification required:** Yes
**Risk:** Team assignments are distributed once per PREP phase via `MatchEvents.TeamAssigned`. Any service that starts after PREP (or requires at a moment after assignments have already fired) will have an empty team table and no way to back-fill. There is currently no shared module that a service can read to find a player's current team on demand — TeamService is a `.server.lua` Script and cannot be required, and there is no `TeamData` ModuleScript.
**Trigger:** A new service that is added later in the build order and needs to know a player's team at an arbitrary moment (e.g. a late-loading ObjectiveService that checks team on first touch rather than on assignment). It will miss the TeamAssigned events that fired at PREP and have no fallback.
**Fix when:** Any service needs to query a player's current team outside of the TeamAssigned subscription window. Create a `src/server/TeamData.lua` ModuleScript that TeamService writes to on assignment and reset, and that other services read from via `TeamData.GetTeam(player)`.

---

## [DEBT-012] DamageService.server.lua must be renamed to DamageService.lua before GunService works — RESOLVED 2026-05-06

**File:** `src/server/DamageService.server.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`GunService.server.lua` calls `require(script.Parent:WaitForChild("DamageService"))`. In Roblox, `require()` only accepts a ModuleScript. A file named `DamageService.server.lua` creates a Script instance, not a ModuleScript — so `require()` will throw at runtime.~~
**Resolution:** Renamed `src/server/DamageService.server.lua` → `src/server/DamageService.lua`. Rojo maps `.lua` files in `src/server/` to ModuleScript instances, so `require()` in GunService now resolves correctly. `default.project.json` uses a folder-level `$path` mapping and required no changes. File header updated from `-- Script` to `-- ModuleScript`. Logic unchanged.

---

## [DEBT-013] Weapon name is hardcoded on both client and server instead of sent in the payload — PARTIALLY RESOLVED 2026-05-15

**Files:** `src/server/GunService.server.lua`, `src/client/GunController.lua`, `src/client/UI/HUD.lua`, `src/shared/Constants.lua`
**Severity:** High
**Studio verification required:** Yes
**Risk:** GunController's `WeaponFired` payload is `{origin, direction, tick}` with no weapon name — so the server cannot know what weapon the client is using. With a single weapon this is invisible; with multiple weapons, every shot is validated against AR15 stats regardless of what the player holds.
**Worsened (2026-05-07):** The ammo system added in GunService (`setupAmmo`, `ReloadRequest` handler) also looks up `WeaponData[DEFAULT_WEAPON]` for `magazineSize` and `reserveAmmo`. A player holding a different weapon would be assigned AR15 ammo.
**Updated (2026-05-14 — AR15 viewmodel task):** Both hardcodes changed from `"SCAR"` to `"AR15"`. Both sides were in sync but structurally fragile.
**Partially resolved (2026-05-15 — GunService):** The server-side `local DEFAULT_WEAPON = "AR15"` in GunService was replaced with `Constants.DEFAULT_WEAPON` — the weapon name now has a single source of truth in `src/shared/Constants.lua`. `AmmoChanged` payload expanded from `(mag, reserve)` to `(weaponName, mag, reserve)`: GunService sends `Constants.DEFAULT_WEAPON` with every ammo update. HUD now displays the server-sent weapon name instead of the hardcoded "SCAR" string.
**Partially resolved (2026-05-15 — GunController):** GunController's `local CURRENT_WEAPON = "AR15"` was removed. Both GunService and GunController now read `Constants.DEFAULT_WEAPON` directly. A single rename of `Constants.DEFAULT_WEAPON` covers both sides. GunController uses `Constants.DEFAULT_WEAPON` only for client-side prediction: dry-fire checks, WeaponData range for the cosmetic raycast, and local rate limiting. GunService remains the server-authoritative source.
**Remaining risk:** `WeaponFired` and `ReloadRequest` still do not carry a weapon name — this is intentional until a full server-owned loadout/equipment system exists. With only one weapon this is invisible; with multiple weapons, the server would have no way to know which weapon a client is using. The HUD label and ammo logic remain correct as long as there is only one weapon.
**MCP unavailable:** These changes were not tested in Roblox Studio. Runtime behavior — HUD weapon label displaying the server-sent string, ammo counts remaining correct, GunController dry-fire and rate-limit behavior unchanged — must be verified.
**Trigger for full resolution:** Multiple weapons exist as a player choice. Add `weaponName: string` to the `WeaponFired` payload (and to `ReloadRequest`), validate it exists in WeaponData on the server.
**Studio test required:** Join a session in ACTIVE phase; confirm HUD bottom-right shows "AR15" (not blank). Fire a shot and reload; confirm ammo counts decrement and replenish correctly. Fire with empty magazine; confirm dry-fire sound plays and no WeaponFired is sent.

---

## [DEBT-014] WeaponFired clientTick is received but not validated

**File:** `src/server/GunService.server.lua`
**Severity:** High
**Studio verification required:** Yes
**Risk:** The `tick` value sent with each `WeaponFired` event is intended to let the server reject shots with timestamps too far in the past (replay attacks or lag compensation abuse). Currently `_clientTick` is discarded. Without this check, a client could theoretically queue up shots during lag and dump them all at once, bypassing the server-side rate limiter — though the rate limiter's `os.clock()` comparison already partially mitigates this.
**Updated (2026-05-15):** Shot origin and direction are now validated server-side before raycasting via `isValidShotPayload()`: types are checked, near-zero directions (< `Constants.SHOT_DIRECTION_MIN_MAGNITUDE`) are rejected, and origins too far from the shooter's `HumanoidRootPart` (> `Constants.SHOT_ORIGIN_MAX_DISTANCE = 12` studs) are rejected. Direction is normalized before use. These checks harden against teleport-origin exploits and zero-vector crashes. `clientTick` validation remains deferred.
**MCP unavailable:** Origin/direction hardening was not tested in Studio. Must be verified to confirm valid shots still pass at all ping levels and that the 12-stud origin limit does not produce false rejections during normal play (jump landings, character transitions).
**Trigger:** The game is stress-tested with high-latency clients or an exploiter attempts shot-replay injection.
**Fix when:** Combat is otherwise stable. Add a maximum acceptable age check: `if os.clock() - clientTick > MAX_SHOT_AGE then return end` where `MAX_SHOT_AGE` accounts for typical RTT plus a tolerance (e.g. 0.5 s). Add `MAX_SHOT_AGE` to Constants.

---

## [DEBT-015] MatchController.client.lua must be renamed MatchController.lua before GunController works — RESOLVED 2026-05-07

**Files:** `src/client/MatchController.client.lua`, `src/client/GunController.client.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`GunController.client.lua` calls `require(script.Parent:WaitForChild("MatchController"))`. A file named `MatchController.client.lua` creates a LocalScript instance — `require()` will throw at runtime. The game will error on the client on startup.~~
**Resolution:** Both controllers renamed to `.lua` (ModuleScript). `MatchController.client.lua` → `MatchController.lua`; `GunController.client.lua` → `GunController.lua`. The self-calling `MatchController:Start()` at the bottom of MatchController was removed — leaving it in would have caused `Start()` to fire twice on `require()` (once from the module tail, once from ClientInit), registering `RoundStateChanged.OnClientEvent` twice. GunController's event connections were wrapped in `GunController:Start()` and a `return GunController` was added. `ClientInit.client.lua` is the sole LocalScript runner — it requires both controllers in dependency order (MatchController first) and calls their `Start()` methods. `require()` now resolves correctly; the startup error is eliminated.

---

## [DEBT-010] DamageService health reset fires for all players including mid-respawn characters

**File:** `src/server/DamageService.lua`
**Severity:** Medium
**Studio verification required:** Yes
**Risk:** On PREP, `resetHealth()` calls `setHealth(player, MAX_HEALTH)` and fires `HealthChanged` to the client for every connected player. If a player is mid-respawn (character is nil or Humanoid is being created), the client receives a correct health value but the Humanoid itself may reset to its default health independently when the new character loads — causing a brief mismatch between the server table and the Humanoid's displayed value.
**Trigger:** A player disconnects or dies in the final second of RESULTS, so their character is respawning exactly when PREP begins and `resetHealth()` fires.
**Fix when:** CorpseService is built (it owns character lifecycle). At that point, hook health reset into `CharacterAdded` instead of relying solely on the phase-change event.

---

## [DEBT-007] Multiple clients connect to RoundStateChanged independently — LEGACY/TRANSITIONAL

**Files:** `src/client/MatchController.lua`, `src/client/UI/MatchUI.lua`, `src/client/UI/HUD.lua`, `src/client/UI/CrosshairUI.lua`, `src/client/ViewModelController.lua`, `src/client/UI/DeathScreen.lua`
**Severity:** Medium-High (context: RoundStateChanged is a legacy remote tied to the round-based loop; see DEBT-036. The proliferation risk applies now, but the remote itself may be replaced or retired with ZoneService.)
**Studio verification required:** Yes
**Risk:** Six separate systems now each connect their own `RoundStateChanged.OnClientEvent` listener. Every server broadcast triggers six separate handlers. If the payload format ever changes, all six must be updated together.
**History:** Originally 1 listener (MatchController). Each new system that needs phase data adds another — now at 6. The fix of introducing a `MatchController.StateChanged` BindableEvent is overdue.
**Trigger:** Adding any further system that reads phase data (CutsceneController, ObjectiveUI, etc.).
**Fix when:** A seventh listener is needed, or when a payload format change is required. Introduce `MatchController.StateChanged` BindableEvent, fire it from `applyState()`, migrate all UI/controllers to subscribe to it instead of the RemoteEvent directly.

---

## [DEBT-016] Logger.DEBUG_MODE requires a source-level code edit to disable for production — RESOLVED 2026-05-07

**File:** `src/shared/Logger.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`DEBUG_MODE = true` is a Lua local variable inside `Logger.lua`. Silencing all `Logger.debug()` output before shipping requires opening the file and changing the value to `false`. A developer who forgets to flip the flag ships with debug output visible to every player in the Output window.~~
**Resolution:** Replaced `local DEBUG_MODE = true` with `local DEBUG_MODE = game:GetService("RunService"):IsStudio()`. `RunService:IsStudio()` returns `true` only inside Roblox Studio and `false` in any live published build or Roblox test server. No manual step exists to forget — the runtime environment determines the flag automatically. The underlying risk is fully eliminated.

---

## [DEBT-017] ClientInit must be manually updated when a new controller is added

**File:** `src/client/ClientInit.client.lua`
**Severity:** Low-Medium
**Studio verification required:** No
**Risk:** `ClientInit.client.lua` holds an explicit ordered list of `loadAndStart()` / `loadInitAndStart()` calls. When a new controller is built (e.g. `MovementController`, `CutsceneController`), a developer must manually add its call in the correct position. If forgotten, the controller's `Start()` is never called and it silently does nothing — no error, no warning, just a non-functional system.
**Current count:** 9 entries (MatchController, MatchUI, HUD, DeathScreen, KillFeedUI, CrosshairUI, ViewModelController, SoundController, GunController).
**Trigger:** Every time a new controller is built. The risk grows with each addition.
**Fix when:** The controller count reaches double digits. At that point, consider a self-registration pattern where each ModuleScript registers itself with ClientInit via a shared table, or a folder-scan pattern that discovers and calls all controllers automatically. Until then, the explicit list is simpler and clearer.

---

## [DEBT-018] getPlayerFromPart is duplicated in DamageService and ObjectiveService

**Files:** `src/server/DamageService.lua`, `src/server/ObjectiveService.server.lua`
**Severity:** Low-Medium
**Studio verification required:** No
**Risk:** Both services implement an identical `getPlayerFromPart(hit: BasePart): Player?` helper that walks up the ancestor chain to find the owning Player. If the Roblox character hierarchy ever changes (e.g. a model-in-model arrangement for ragdolls or vehicles), both copies must be updated in sync. A fix in one without the other will cause inconsistent hit detection across services.
**Trigger:** Adding a third service that needs to map a BasePart back to a Player (e.g. MonsterService targeting a player, or a Zone service checking who is inside a region).
**Fix when:** A third consumer appears. Create `src/server/CharacterUtil.lua` (ModuleScript) with `CharacterUtil.getPlayerFromPart(hit)` and `CharacterUtil.getHumanoid(player)`. Replace the inline copies in DamageService and ObjectiveService with `require(CharacterUtil)` calls.

---

## [DEBT-019] Players.CharacterAutoLoads = false is set globally in TeamService with no fallback — LEGACY/TRANSITIONAL

**File:** `src/server/TeamService.server.lua`
**Severity:** Medium-High (legacy — TeamService is transitional; ZoneService will own character spawn logic; see DEBT-036)
**Studio verification required:** Yes
**Risk:** `Players.CharacterAutoLoads = false` is set at the top of TeamService. If TeamService fails to load (a require error, a script disabled in Studio), Roblox will never auto-spawn characters, and players will see a blank screen with no error. There is no watchdog that re-enables auto-loading if TeamService fails, and no fallback spawn path.
**Trigger:** Any unhandled error in TeamService's module-level code (e.g. a missing dependency) that prevents the script from running fully.
**Fix when:** The server-side error handling pass. Add a `pcall` around the PREP phase handler in TeamService, and consider a separate failsafe script that re-enables CharacterAutoLoads if TeamService has not reported readiness within N seconds.

---

## [DEBT-020] Team name strings are duplicated across TeamService and ObjectiveService — PARTIALLY RESOLVED 2026-05-07 — LEGACY/TRANSITIONAL

**Files:** `src/server/TeamService.server.lua`, `src/server/ObjectiveService.server.lua`
**Severity:** Medium (legacy — both services are transitional; see DEBT-036)
**Studio verification required:** No
**Risk:** Both services define `local TEAM_ATTACKERS = "Attackers"` and both assume `TEAM_DEFENDERS = "Defenders"` (implicit). If a team is renamed, both files must be updated together. A mismatch — e.g. TeamService assigns "Attacker" (no s) but ObjectiveService checks "Attackers" — silently breaks objective capture without any runtime error, because `playerTeams[player] ~= TEAM_ATTACKERS` is always true.
**Partial resolution (2026-05-07):** `KillFeedUI` was the third consumer that triggered the fix condition. `Constants.TEAM_ATTACKERS = "Attackers"` and `Constants.TEAM_DEFENDERS = "Defenders"` were added to `src/shared/Constants.lua`. `KillFeedUI` reads from Constants and introduces no new hardcoded strings. TeamService and ObjectiveService still have their own local declarations (not in the allowed-file scope for this task).
**Remaining risk:** TeamService and ObjectiveService still have local `TEAM_ATTACKERS`/`TEAM_DEFENDERS` strings that are not wired to Constants. A team rename still requires updating three files instead of one.
**Fix when:** The next task that touches TeamService or ObjectiveService. Replace their local `TEAM_ATTACKERS`/`TEAM_DEFENDERS` declarations with `require(Constants).TEAM_ATTACKERS` / `.TEAM_DEFENDERS`.

---

## [DEBT-022] Ragdolled characters have no cleanup owner until CorpseService is built

**File:** `src/server/RagdollService.lua`
**Severity:** High
**Studio verification required:** Yes
**Risk:** `RagdollService:Apply()` deliberately does not destroy the character — the ragdoll stays in Workspace so other players can see it. However, there is currently no system that removes these ragdoll models. Motor6Ds disabled + BallSocketConstraints attached means the character is a persistent physics object. Across multiple rounds, ragdolled characters from earlier rounds accumulate in Workspace. They have no cleanup on PREP or RESULTS.
**Current exposure:** Characters are still respawned at the start of PREP via `player:LoadCharacter()` in TeamService — this replaces the character reference on the Player object, but the old ragdolled Model is orphaned in Workspace (it loses its `Players.Player.Character` association but is not destroyed).
**Trigger:** After the first kill in any round. Corpses accumulate every round. On a long session, this causes memory pressure and visual clutter.
**Fix when:** CorpseService is built (Stage 5 on the roadmap). CorpseService should take ownership of ragdolled models, track them across rounds, and call `:Destroy()` on all of them at MATCHEND.

---

## [DEBT-023] BallSocketConstraint ragdoll assumes a standard Roblox R6 character rig — UPDATED 2026-05-18

**File:** `src/server/RagdollService.lua`
**Severity:** Low-Medium
**Studio verification required:** Yes
**Risk:** `RagdollService:Apply()` iterates `character:GetDescendants()` and converts every `Motor6D` it finds. This works correctly for standard Roblox R6 characters (and would also work for R15), which have a known, predictable Motor6D hierarchy. If a custom character rig is introduced (e.g. a non-humanoid defender faction, a monster that uses the Humanoid class, or a weapon held by a player model with its own Motor6Ds), `Apply()` may convert joints that should not be ragdolled — breaking the custom rig or producing unexpected physics behavior.
**Updated (2026-05-18 — R6 migration):** The project's rig target was changed from R15 (original) to R6. `RagdollService` iterates Motor6Ds by type, not by part name — this is rig-agnostic and requires no code change for the R6 migration. The risk noted above (custom rig Motor6D confusion) is unchanged. R6 has fewer Motor6Ds than R15 (6 joints vs ~15), so the ragdoll is simpler and the risk of accidentally capturing unintended joints is lower.
**Trigger:** Adding any non-standard character rig to the game.
**Fix when:** A custom rig is introduced. Add a tag or attribute (e.g. `Instance:SetAttribute("RagdollEnabled", true)`) to each Motor6D that should participate in ragdolling, and filter by that attribute in `convertJoint()`.

---

## [DEBT-024] SoundController uses single Sound instances with no pooling

**File:** `src/client/SoundController.lua`
**Severity:** Medium
**Studio verification required:** Yes
**Risk:** Each sound type (gunshot, hit, reload, death, dry-fire) is backed by exactly one `Sound` instance. Calling `Sound:Play()` when the instance is already playing restarts it from the beginning rather than spawning a concurrent playback. For `PlayGunshot()` called at `AssaultRifle.fireRate = 0.1 s` intervals, if the gunshot sound asset is longer than 0.1 s, each new shot cuts the previous one audibly. This produces a choppy, interrupted audio experience at the maximum fire rate.
**Current exposure:** The gunshot asset (`rbxassetid://4792534948`) is a short percussive shot; restart-on-play produces an acceptable rapid-fire stutter at this fire rate. Risk grows if a slower, longer-sounding weapon is added.
**Trigger:** Adding a weapon with a fire rate longer than the corresponding sound asset's duration, or adding a shotgun/burst weapon that plays multiple sounds at once.
**Fix when:** A second weapon type with a noticeably longer sound is added. Implement a small sound pool per type (3–5 clones, round-robin `Play()`). Alternatively, use `SoundGroup` with `PolyphonyMode = SoundGroup.Polyphony` if that API is available.

---

## [DEBT-025] DryFire sound has no asset ID assigned — RESOLVED 2026-05-07

**File:** `src/client/SoundController.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`ID_DRYFIRE = ""` — `SoundController:PlayDryFire()` logs a warning and returns immediately without playing anything. GunController now calls `PlayDryFire()` when the magazine is empty (ammo system added 2026-05-07), so the warning `[SoundController] PlayDryFire: no SoundId assigned (DEBT-025)` will appear in Output on every empty-mag click during playtesting.~~
**Resolution:** `ID_DRYFIRE` assigned `"rbxassetid://9120386446"` (short metallic click). The empty-string guard and `Logger.warn` in `PlayDryFire()` were removed — the method now calls `dryFireSound:Play()` directly. The stale comment on the `makeSound` call in `init()` was also removed.

---

## [DEBT-026] Ammo is not initialized for players who join after the PREP TeamAssigned window

**File:** `src/server/GunService.server.lua`
**Severity:** Low-Medium
**Studio verification required:** Yes
**Risk:** GunService populates `playerMag` and `playerReserve` when `MatchEvents.TeamAssigned` fires (during PREP). TeamService fires TeamAssigned for all connected players at the start of every PREP phase. A player who joins while a round is already ACTIVE will not receive TeamAssigned until the next PREP; their `playerMag` and `playerReserve` will be `nil`. The WeaponFired handler already guards against this — it returns silently if `playerMag[shooter] == nil` — so no crash occurs. However, that player cannot fire at all until the next round, even though TeamService also does not spawn mid-ACTIVE joiners, so the nil ammo case is moot in practice.
**Trigger:** A player joins during ACTIVE phase and, by some path, has a character and attempts to fire (e.g. a future game mode that allows mid-round joining).
**Fix when:** A mid-round join or reinforcement system is built. At that point, hook into `Players.PlayerAdded` and `player.CharacterAdded` during ACTIVE to assign ammo on spawn rather than relying solely on TeamAssigned.

---

## [DEBT-021] ViewModelController parts have no cleanup path if Start() is called twice — RESOLVED 2026-05-07

**File:** `src/client/ViewModelController.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`gunBody`, `barrel`, and `grip` are module-level variables created inside `Start()`. If `Start()` were called a second time, a new set of Parts would be parented to `workspace.CurrentCamera` without the old ones being destroyed.~~
**Resolution:** The three individual Part variables were replaced by a single `self.model` (a cloned Model). `init()` — which `Start()` calls first — destroys any existing `self.model` before cloning a new one: `if self.model then self.model:Destroy() end`. Re-calling `Start()` is now safe with respect to model instances. Note: duplicate RenderStepped and RoundStateChanged connections would still accumulate on double-Start; this is a general concern for all controllers and is prevented by ClientInit calling `Start()` exactly once.

---

## [DEBT-029] ViewModelController setVisibility called every RoundStateChanged tick, not only on phase transitions

**File:** `src/client/ViewModelController.lua`
**Severity:** Low
**Studio verification required:** Yes
**Risk:** The `if show ~= visible then` guard was removed to fix the re-init visibility bug (2026-05-12). Without the guard, `setVisibility` is called every second during ACTIVE (and every tick during any other phase), iterating all model descendants and setting Transparency on each call. The full TROY DEFENSE AR rig has 49 BaseParts total; 40 are visual (setVisibility(true) touches 40, setVisibility(false) touches all 49). This is 10× the placeholder's work but still well within frame budget at 60fps.
**Updated (2026-05-14):** Part count corrected — the new 49-BasePart Motor6D rig replaced the previous 30-part WeldConstraint asset. Observed count: `setVisibility(true) — 40 parts`, `setVisibility(false) — 49 parts`.
**Trigger:** Adding a high-polygon viewmodel with 50+ BaseParts, or introducing a phase that toggles rapidly.
**Fix when:** Frame-time profiling reveals the GetDescendants iteration inside setVisibility contributes meaningfully to client frame budget. At that point, restore a state guard (`if show ~= visible then ... end`) — `visible` is already reset to `false` at the end of `init()` so the guard fires correctly after CharacterAdded re-runs `init()`.

---

## [DEBT-030] WeaponData.reloadTime is stored but not read by GunService

**File:** `src/shared/WeaponData.lua`, `src/server/GunService.server.lua`
**Severity:** Medium
**Studio verification required:** Yes
**Risk:** `WeaponData["AR15"].reloadTime = 2.2` was added in the AR15 viewmodel task for future use. GunService's `ReloadRequest` handler currently executes an instant reload — ammo transfers from reserve to magazine with no delay. A future system that adds a reload animation or enforces a server-side delay will need to read `reloadTime` and either impose a server-side wait or validate that sufficient time has passed since the reload was requested.
**Trigger:** Adding a server-enforced reload time or a reload animation in GunController (e.g. a `reloadTime`-second cooldown window during which `WeaponFired` is rejected even in ACTIVE).
**Fix when:** Reload animations are built. Add a `reloadEndTime[player]: number` table to GunService; on `ReloadRequest`, set it to `os.clock() + weaponDef.reloadTime` and reject `WeaponFired` events that arrive before that time elapses.

---

## [DEBT-031] StarterCharacterScripts and StarterGui not tracked by Rojo — imported assets can silently add scripts there — PARTIALLY RESOLVED 2026-05-14

**File:** `StarterPlayer.StarterCharacterScripts`, `StarterGui` (Studio only, no Rojo mapping)
**Severity:** High
**Studio verification required:** Yes
**Risk:** `default.project.json` maps `StarterPlayerScripts/Controllers` → `src/client` and no other
`StarterPlayer` containers. `StarterCharacterScripts` and `StarterGui` are outside Rojo's managed tree. Any
Creator Marketplace import or drag-and-drop asset that includes a LocalScript in `StarterCharacterScripts`
or a ScreenGui in `StarterGui` will be silently accepted by Studio with no corresponding disk file, no
git tracking, and no Rojo sync mechanism to detect or remove it.

The TROY DEFENSE AR viewmodel import included exactly such a script: a LocalScript named `"LocalScript"`
that set `camera.CameraType = Scriptable` every RenderStep using yaw-only rotation — locking the
player's vertical camera movement for the entire life of the project until manually found and deleted.

**Partial resolution (2026-05-14):** The specific rogue script in `StarterCharacterScripts` was deleted. The structural gap remains.

**Updated (2026-05-15):** The invalid `StarterGui → src/ui` mapping was removed from `default.project.json`
(it pointed to an empty folder with no files). `StarterGui` is now intentionally unmanaged by Rojo:
all ScreenGui instances are created at runtime by client controllers. This is correct for the current
stage, but it means StarterGui is now an explicitly untracked container — see DEBT-035.

**Partially mitigated (2026-05-15):** An asset import safety checklist was added to `CLAUDE.md` and
`docs/PROJECT_RULES.md`. The checklist requires: (1) stating which containers an import is expected
to modify before importing; (2) manually inspecting `StarterCharacterScripts`, `StarterGui`,
`StarterPack`, `ReplicatedFirst`, `Lighting`, `SoundService`, `Workspace`, and all imported Model
descendants after every import; (3) deleting or moving to `src/` any untracked Script or LocalScript
found; and (4) explicitly deleting any LocalScript that controls `CameraType`, `camera.CFrame`, or
`RenderStepped` camera behavior. The structural gap — no Rojo tracking of these containers — remains.
The checklist is a process control, not a structural fix. Severity stays High until
`StarterCharacterScripts` is added to `default.project.json` as a mapped source folder.

**Trigger:** Any future import from the Creator Marketplace or from a `.rbxm` file that includes
scripts in `StarterCharacterScripts`, `StarterGui`, or other Studio containers not listed in
`default.project.json`.

**Fix when:** Add a `StarterCharacterScripts` mapping to `default.project.json` pointing at
`src/character/` (or `src/character-scripts/`) so any script placed there must have a corresponding
tracked disk file. At that point, the checklist process becomes a secondary backstop rather than the
primary protection.

---

## [DEBT-033] Prompt pre-flight review is a convention enforced only by CLAUDE.md — not tooling

**File:** `CLAUDE.md`
**Severity:** Low
**Studio verification required:** No
**Risk:** The prompt pre-flight review rule instructs Claude Code to assess each prompt before acting. This is a behavioral convention, not a hard enforcement mechanism. A session that does not read CLAUDE.md at startup, or a tool invocation that bypasses the behavior section, will not perform the pre-flight check. There is no linter, CI gate, or hook that verifies the review happened.
**Trigger:** Any session where CLAUDE.md is not read at startup, or where a prompt is applied directly to a file without a conversational turn.
**Fix when:** A hook or pre-task checklist can be encoded into `.claude/settings.json` or a Stop/PreToolUse hook that reminds the session to confirm pre-flight was done. Until then, the rule is advisory only.

---

## [DEBT-034] MCP-unavailable work has no automated scope guard — relies on Claude self-reporting

**File:** `CLAUDE.md`
**Severity:** Low-Medium
**Studio verification required:** No
**Risk:** The MCP unavailable rule instructs Claude Code not to claim Studio verification when MCP is disconnected and to restrict scope to docs/config/static-validation. This is self-reported — there is no CI gate that checks whether a change touching gameplay files was actually tested in Studio. If a session misidentifies MCP as available, or proceeds with a runtime change without explicitly flagging it, the unverified change enters the codebase silently.
**Trigger:** Any gameplay-affecting change (camera, viewmodel, combat, match-loop, objectives, replication) committed without a Studio session — especially in a GitHub-only session.
**Fix when:** A CI step can run `rojo build` and `selene` automatically on every push to catch at least structural errors. Full runtime verification always requires Studio. Until CI is added, unverified gameplay changes must be manually tagged "needs Studio verification" in the PR description and in a TECHNICAL_DEBT entry.

---

## [DEBT-035] StarterGui has no Rojo source mapping — UI is controller-generated (intentional at this stage)

**File:** `default.project.json`, `src/ui/` (empty directory)
**Severity:** Low
**Studio verification required:** No
**Risk:** StarterGui is not mapped to a source folder in `default.project.json`. All ScreenGui instances are built programmatically by `init(playerGui)` methods inside `src/client/UI/*.lua` at runtime. This is correct for the current development stage — no static StarterGui assets exist. However, if a developer adds files to `src/ui/` without also restoring the mapping in `default.project.json`, those files will never sync into Studio. Conversely, if a developer adds the mapping without adding files, Rojo will error on build because `src/ui` contains no `.lua` files (Rojo requires a non-empty source path for `$path` mappings on a container).
**Context:** The `StarterGui → src/ui` mapping was removed on 2026-05-15 because `src/ui/` was empty and the mapping was misleading. See DEBT-031 for the broader untracked-container risk.
**Trigger:** Any task that introduces static StarterGui content (pre-built ObjectiveUI assets, map-specific loading screens, or any ScreenGui that should exist before `ClientInit` runs).
**Fix when:** The first file is added to `src/ui/`. At that point:
1. Add the file(s) to `src/ui/`.
2. Restore the StarterGui mapping in `default.project.json`.
3. Update `docs/PROJECT_MAP.md` (StarterGui / UI source mapping section).
4. Run `rojo build` to confirm the mapping is valid.

---

## [DEBT-032] Global formatter (StyLua) intentionally not run on whole repo

**File:** `CLAUDE.md`, `stylua.toml`
**Severity:** Low
**Studio verification required:** No
**Risk:** `stylua src/` is listed in `CLAUDE.md`'s Commands section as a convenience reference but is intentionally not run as a blanket pass during normal development. Running it globally would reformat every Luau file — including files unrelated to the current task — producing noisy diffs that bury actual gameplay changes and make code review harder.
**Current policy (added 2026-05-12):** CLAUDE.md now explicitly prohibits global formatting passes unless the user asks for one. StyLua should only be run on files modified by the current task.
**Fix when:** A deliberate "format the whole repo" cleanup is scheduled and the user explicitly requests it as a standalone commit with no other changes mixed in.

---

## [DEBT-039] WeaponFeel AR15 entry is an alias for SCAR — no separate tuning

**File:** `src/shared/WeaponFeel.lua`
**Risk:** `WeaponFeel["AR15"] = WeaponFeel["SCAR"]` — both weapons share the same feel table by reference. Any write to the SCAR entry would mutate AR15 simultaneously (though no code currently writes to feel tables at runtime). More practically, the two weapons fire and feel identically, which is incorrect — the AR15 should have lighter recoil and faster reset.
**Trigger:** A second weapon tuning pass, or the addition of any third weapon with a different feel.
**Fix when:** A per-weapon design pass is scheduled. Replace the alias with a full copy of the SCAR table, adjust values for AR15 (typically lower `recoilUp`, faster `recoilRecoverySpeed`, slightly tighter `hipfireSpread`), and add a comment explaining the intended feel difference.

---

## [DEBT-040] ADS visual transition not implemented

**File:** `src/client/GunController.lua`, `src/client/ViewModelController.lua`
**Risk:** `isADS` is tracked and gates spread calculation, but there is no visual change when MouseButton2 is held. The viewmodel does not move into a sights-up position, no FOV change occurs, and no TweenService transition plays. The player receives mechanical benefit (tighter spread) with no visual feedback that ADS is active.
**Trigger:** Any playtesting session where a player notices pressing right-click does nothing visible.
**Fix when:** ViewModelController is extended to expose a `SetADS(isADS: boolean)` setter. GunController calls it on MouseButton2 down/up. ViewModelController tweens the viewmodel position to an ADS offset CFrame over `WeaponFeel.adsTime` seconds. Optionally, `workspace.CurrentCamera.FieldOfView` is tweened to 50° and back.

---

## [DEBT-041] Shell ejection VFX not implemented

**File:** `src/shared/WeaponFeel.lua`, `src/client/GunController.lua`
**Risk:** `shellEjectEnabled = false` is stored in WeaponFeel but GunController never reads it. No shell casing part is spawned or ejected from the ejection port on each shot. The field exists only as a forward-declaration for when the system is built.
**Trigger:** Any art review where shell casings are expected.
**Fix when:** A VFX pass is scheduled. Create an `ObjectPool` (per CLAUDE.md pooling rules) of small cylinder Parts; on each shot, retrieve a part from the pool, position it at an `EjectPortAttachment` on the viewmodel, apply a random rightward velocity + tumble AngularVelocity, and return it to the pool after 2–3 seconds. Read `shellEjectEnabled` from WeaponFeel to gate the spawn.

---

## [DEBT-042] Sprint stamina system not implemented

**File:** `src/client/MovementController.lua`, `src/shared/Constants.lua`
**Risk:** `Constants.SPRINT_STAMINA_ENABLED = false`. Sprint is currently unlimited — the player can hold Shift indefinitely with no stamina drain. `MovementController` reads this constant but only as a disable gate (the stamina system is entirely unimplemented). There is no stamina UI, no drain-per-second, no recovery rate, and no exhaustion state.
**Trigger:** Any balance pass where unlimited sprint is identified as exploitable or too permissive.
**Fix when:** A stamina design spec is written. Add `SPRINT_STAMINA_MAX`, `SPRINT_DRAIN_RATE`, and `SPRINT_REGEN_RATE` to Constants. In MovementController's RenderStepped, decrement stamina while `isSprinting`, increment while not, and force exit from sprint when it reaches zero. Fire a BindableEvent or call a HUD setter to update the stamina indicator.

---

## [DEBT-043] Prone stance not implemented

**File:** `src/client/MovementController.lua`, `src/shared/Constants.lua`
**Risk:** `Constants.PRONE_ENABLED = false`. No prone state, animation, hitbox change, or camera height exists. The constant is a placeholder so the feature slot is visible in code review.
**Trigger:** Any design pass where prone is added to the movement spec.
**Fix when:** Prone is added to the movement design doc. Requires: prone animation ID in `ANIM_IDS`, `PRONE_SPEED` constant, camera height offset, hitbox height reduction (scale HRP Y), `Stance.Prone` state, and input key assignment (default X or toggle from crouch).

---

## [DEBT-044] MovementController animation system — Stage 2D — UPDATED 2026-05-19 (x6)

**File:** `src/client/MovementController.lua`, `src/shared/Constants.lua`
**Severity:** Medium
**Studio verification required:** Yes
**Updated (2026-05-18 — Stage 2A):** R6 walk/run animation playback added. Four AnimationTrack objects are loaded per character via `Humanoid.Animator`. Tracks are played during ACTIVE phase only and cleared on respawn/destroy. `directionName` is correctly computed and drives animation selection alongside `isSprinting`.
**Updated (2026-05-18 — Animate-disable bug fix):** Custom animation tracks were not playing because the default Roblox `Animate` LocalScript was overriding them. `disableDefaultAnimate()` now sets `character.Animate.Disabled = true` before custom tracks are loaded. Gated by `Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED` and `Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT` (both default `true`). Animation diagnostics added behind `Constants.MOVEMENT_ANIMATION_DEBUG`. WalkLeft/WalkRight fallback logic added.
**Updated (2026-05-18 — R6 detection):** `hasR6BodyParts()`, `getRigDebugSummary()`, and `isR6Character()` helpers added. The direct `RigType ~= R6` guard replaced with `isR6Character()` (primary `RigType` check + structural body-part fallback). `disableDefaultAnimate()` moved from `setupCharacter()` into `loadMovementAnimations()` (after rig confirmation) so Animate is only disabled when the character is confirmed R6. `getRigDebugSummary()` logged when animations are skipped.
**Updated (2026-05-18 — animation-set selection fix):** Default animation set changed from AR15 to Unarmed. `getAnimationSetName()` now reads `equippedWeaponName` (nil → Unarmed, "AR15" → AR15 set, unknown → Unarmed fallback). Two new public methods: `SetEquippedWeaponName(name)` and `GetEquippedWeaponName()`. Both Unarmed and AR15 tracks are pre-loaded at spawn. Unarmed WalkLeft (`rbxassetid://101275785187464`) and WalkRight (`rbxassetid://72765640529019`) added. Animation-set-change debug log added (fires once per change, not per frame). Three new Constants: `MOVEMENT_ANIMATION_SET_UNARMED`, `MOVEMENT_ANIMATION_SET_AR15`, `MOVEMENT_DEFAULT_ANIMATION_SET`.
**Updated (2026-05-18 — Stage 2C animation behavior):** Strafe animations (WalkLeft/WalkRight) are now gated on mouse-lock / shift-lock style state. `UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter` is the practical runtime signal used (read-only — does not toggle shift lock or write camera). When not mouse-locked, all walking falls back to WalkForward. Gated by `Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK` (default `true`); set `false` to play strafe anims regardless. LeftShift sprint now works while Roblox's built-in shift lock is active — the previous `gameProcessed` guard was replaced with `UserInputService:GetFocusedTextBox() ~= nil` (blocks sprint only when typing in a TextBox). Animation playback speed multipliers added via `AnimationTrack:AdjustSpeed()`: WalkForward at 2.0×, WalkLeft/WalkRight at 1.35×, RunForward at 1.0× (unchanged). Speed is applied on play and on same-track re-check. Three new Constants: `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER`, `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER`, `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER`. `lastStrafeBlockedState` guard prevents per-frame log spam — strafe-blocked/enabled log fires only on state change.
**Updated (2026-05-19 — Stage 2D: custom mouse-lock toggle):** LeftShift sprint conflicted with Roblox default Shift Lock — pressing Shift both sprinted and toggled native mouse lock simultaneously. Resolved by adding a custom mouse-lock toggle on LeftAlt (`Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY`). `customMouseLocked` (local boolean) is the new source of truth for strafe animation gating. `isMouseLockedForStrafeAnimations()` now returns `customMouseLocked` when `CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true` (default), instead of reading `UserInputService.MouseBehavior`. `SetCustomMouseLocked(bool)` and `IsCustomMouseLocked()` are new public API methods. `UserInputService.MouseBehavior` is still written by `SetCustomMouseLocked` (LockCenter on, Default off) but is no longer the strafe gate source. Mouse lock is released to Default on respawn, leaving ACTIVE, and in `destroy()`. Four new Constants: `CUSTOM_MOUSE_LOCK_ENABLED`, `CUSTOM_MOUSE_LOCK_TOGGLE_KEY`, `CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY`, `CUSTOM_MOUSE_LOCK_DEBUG`. Manual Studio step required: set `StarterPlayer.EnableMouseLockOption = false` to prevent Roblox default Shift Lock from conflicting.

**Remaining gaps (not yet in Stage 2D):**
- Crouch walk animation — not implemented; crouching uses WalkForward at CROUCH_SPEED.
- Backward-specific animation — Backward direction falls back to WalkForward.
- Diagonal-specific animations — ForwardLeft/ForwardRight etc. use WalkLeft/WalkRight or WalkForward.
- Lower-body / upper-body animation split — not implemented; the full body plays the movement animation.
- Reload, fire, ADS, and sprint-hold weapon animations — deferred to a weapon-anim stage.
- Idle, jump, fall, and climb animations — suppressed along with locomotion when Animate is disabled. Custom replacements needed in a future movement stage.
- True server-owned equipment state — equippedWeaponName is presentation-only; see DEBT-050.
- Full custom camera controller — `SetCustomMouseLocked` writes `UserInputService.MouseBehavior = LockCenter`, which locks the cursor to center and allows camera rotation via Roblox's default camera system. A full custom camera controller (Scriptable CameraType, raw mouse-delta yaw/pitch) is not built.

**Remaining risks:**
- If custom animation IDs are private or not owned by the game's creator / group, Roblox may silently refuse to load them. `Logger.warn()` fires for any empty assetId; a failed `LoadAnimation()` call will produce an output error. Confirm animation ownership before shipping.
- If neither `RigType == R6` nor the structural body-part check passes, R6 animations are skipped and `getRigDebugSummary()` is logged. Stage 1 speed/direction logic remains active. Verify `StarterPlayer.CharacterRigType` in Studio after each `rojo serve` (DEBT-049).
- If the structural fallback fires (R6 parts present but `RigType` mismatch), a one-time warn is emitted. This is expected in some Studio sessions — the real fix is DEBT-049 verification.
- Disabling Animate removes the default idle, jump, fall, and climb animations. Until custom clips are added, the character will T-pose during these states.
- `equippedWeaponName` is presentation-only. True armed/unarmed state must later come from a server-owned equipment/loadout system. `SetEquippedWeaponName` must eventually be called by a real EquipmentController or weapon equip system (see DEBT-050).
- Sprint in all directions still uses RunForward (no directional sprint animations yet). Backward and diagonal movement uses WalkForward fallback only.
- If `DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = false`, Animate keeps running and may override or blend with custom locomotion tracks. This constant must stay `true` for custom animations to take effect.
- Animation speed multipliers (`MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER = 2.0`, `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER = 1.35`) were set before Studio testing. These values may need tuning after Studio verification — if the clip cadence feels too fast or too slow, adjust only the Constants without touching controller logic.
- Roblox default Shift Lock (`StarterPlayer.EnableMouseLockOption`) should be disabled in Studio if it is still accessible to players. If left enabled, Roblox Shift Lock can re-enable native `MouseBehavior = LockCenter` independently of `customMouseLocked`, causing the strafe gate to fire unexpectedly if the legacy path is ever used. Recommended Studio setting: `StarterPlayer.EnableMouseLockOption = false`.
- Input/mouse-lock behavior needs Studio verification — particularly: LeftAlt toggles correctly, LeftShift does not trigger mouse lock, strafe anims gate on `customMouseLocked`, cursor releases on phase exit and respawn.

**Trigger:** Any playtesting session where T-pose during idle/jump or missing backward/diagonal animations is noticeable, or where the `getRigDebugSummary` warn appears, or where animation speed feels off after Studio testing, or where LeftShift/LeftAlt input feels wrong.
**Fix when:** A future movement stage adds idle/jump/fall/climb custom clips, backward/diagonal clips, and server-owned equipment integration. Tune speed multipliers after first Studio playtest. Do not build full Scriptable camera system until camera refactor is scheduled.

---

## [DEBT-046] MovementController phase gating uses legacy MatchController / Constants.Phase.ACTIVE — ADDED 2026-05-18

**File:** `src/client/MovementController.lua`
**Severity:** Low-Medium
**Studio verification required:** No (structural coupling, not a runtime bug)
**Risk:** MovementController listens to `RoundStateChanged` (the legacy remote from the round-based `MatchService`) and calls `MatchController:GetPhase()` to gate speed, sprint, and crouch. When the persistent zone architecture is built and `ZoneService` replaces `MatchService`, the phase constants and remote will change or be retired. MovementController will need to be updated to gate on `ZoneService` state instead (e.g. "player is in zone" rather than `Constants.Phase.ACTIVE`).
**In practice (Stage 1):** This coupling is intentional — the legacy round-based system is the only phase source available. All movement features are correctly gated: WalkSpeed=0 outside ACTIVE, normal movement inside ACTIVE.
**Trigger:** ZoneService is built and `RoundStateChanged` is retired or repurposed. At that point MovementController's phase listener must be migrated to the new zone-state remote and `MatchController:GetPhase()` calls replaced.
**Fix when:** ZoneService replaces MatchService. Update the `RoundStateChanged` listener to the zone-state equivalent; replace `Constants.Phase.ACTIVE` checks with zone-entry state; remove the `MatchController` require.

---

## [DEBT-047] movementState is a shared table returned by reference — callers must treat it as read-only — ADDED 2026-05-18

**File:** `src/client/MovementController.lua`
**Severity:** Low
**Studio verification required:** No
**Risk:** `GetMovementState()` returns the `movementState` table by reference. Any caller that writes to the returned table (e.g. `ms.isSprinting = true`) would corrupt MovementController's internal state without any error. This is intentional for performance (no copy allocation per call) but requires caller discipline.
**Current callers:** None in Stage 1 — `GetMovementState()` is reserved for future animation and HUD systems that will read (not write) the fields.
**Trigger:** Any system that receives the table and writes to a field — especially if a future sprint-stamina or slide system is built outside MovementController.
**Fix when:** A second system needs write access to movement state, or if a caller is found mutating the returned table. At that point, either (a) return a shallow copy (`table.clone(movementState)`) at a small allocation cost per call, or (b) expose individual getters (`GetIsSprinting()`, `GetDirectionName()`, etc.) and remove `GetMovementState()`.

---

## [DEBT-045] Recoil is viewmodel-only — no camera-space kick

**File:** `src/client/GunController.lua`, `src/client/ViewModelController.lua`
**Risk:** The recoil CFrame is composed into `ViewModelController`'s PivotTo call, rotating the viewmodel assembly in camera space. The camera itself does not move. In most competitive FPS games, camera recoil (the crosshair rising on screen) is a core mechanic that requires compensating pull-down; without it the weapon feels "floaty" and aiming is trivially easy. Implementing camera recoil requires switching to `CameraType.Scriptable` and managing the full camera transform per frame, which would need to be coordinated with the viewmodel's `PivotTo` call to avoid desync.
**Trigger:** Any feel review where the lack of camera kick is flagged as making the gun feel disconnected.
**Fix when:** A full camera-management refactor is scheduled. Switch `workspace.CurrentCamera.CameraType` to `Scriptable`; manage yaw/pitch from raw mouse delta; compose the recoil CFrame on top each frame; revert to the engine camera on focus loss.

---

## [DEBT-007] Eight RoundStateChanged listeners — MovementController Stage 1 retains its listener

**File:** `src/client/ViewModelController.lua`, `src/client/GunController.lua`, `src/client/MovementController.lua`, plus four UI controllers (MatchUI, HUD, CrosshairUI, DeathScreen)
**Updated (2026-05-14):** MovementController added an 8th `RoundStateChanged.OnClientEvent` listener.
**Updated (2026-05-18):** Movement Stage 1 rewrite retains the single `RoundStateChanged` listener in MovementController. Listener count unchanged at 8. See original DEBT-007 entry for fix guidance.

---

## [DEBT-017] ClientInit manages 10 controllers — threshold reached

**File:** `src/client/ClientInit.client.lua`
**Updated (2026-05-14):** MovementController inserted at position 9, shifting GunController to 10. The threshold condition (refactor if >10 controllers) has now been reached.
**Updated (2026-05-18):** Movement Stage 1 rewrite does not change the controller count — MovementController remains at position 9. Consider splitting ClientInit into a UI group and a gameplay-controller group, or adopting a registry pattern where controllers self-register. See original DEBT-017 entry.

---

## [DEBT-048] Constants.FORCE_FIRST_PERSON=false is a development/testing shortcut — ADDED 2026-05-18

**File:** `src/shared/Constants.lua`, `src/client/ViewModelController.lua`
**Severity:** Low-Medium
**Studio verification required:** Yes
**Risk:** `Constants.FORCE_FIRST_PERSON = false` allows movement, map, and zone testing with normal Roblox camera and a permanently hidden viewmodel. This is intentional for development. However:
1. **Must be set to `true` before any FPS playtesting or shipping.** If forgotten, players will have no first-person camera lock and no visible weapon — the game will feel like a top-down or third-person experience.
2. **No automated enforcement.** There is no CI gate, build step, or Selene rule that warns when `FORCE_FIRST_PERSON = false` ships in a production build. The flip is a manual edit.
3. **Not a real game-mode decision.** A production game would read this from a game mode config, a player settings module, or a server-side flag (e.g. "FPS mode" vs "overhead map testing mode") rather than hardcoding it in Constants.
4. **Muzzle flash still fires when false.** When `FORCE_FIRST_PERSON = false`, `GetBarrelTipCFrame()` returns the hidden barrel's WorldPosition (the model follows the camera via PivotTo). GunController uses this to place the muzzle flash Part. The flash will appear at the ghost barrel position, which is invisible but not at the expected screen position for the Classic camera view.
**Trigger:** Shipping or playtesting without flipping the flag to `true`, or a future system that needs to read camera/viewmodel mode dynamically rather than from a compile-time constant.
**Fix when:** Before the first FPS playtesting session, flip to `true`. Long-term: replace the boolean constant with a read from a `GameModeConfig` or `SettingsService` module so the decision can vary per game mode or build target without touching Constants.

---

## [DEBT-049] R6 rig target set in default.project.json — Studio manual verification required — ADDED 2026-05-18

**Files:** `default.project.json`, Studio Game Settings
**Severity:** High
**Studio verification required:** Yes
**Risk:** `StarterPlayer.CharacterRigType` is set to `Enum.HumanoidRigType.R6` (ordinal 0) via Rojo `$properties` in `default.project.json`. Rojo 7.x supports enum properties via `{"Enum": ordinalValue}` syntax. However, Rojo does not always apply `StarterPlayer` property overrides on first sync in an existing Studio session — the `CharacterRigType` value shown in Studio's `StarterPlayer` Properties panel should be manually confirmed after every `rojo serve` session.

**What to verify:**
1. Open Studio and start `rojo serve default.project.json`.
2. In Studio, select `StarterPlayer` in the Explorer.
3. In the Properties panel, confirm `CharacterRigType` shows `R6` (not `R15`).
4. If it shows `R15`: manually set `Game Settings → Avatar → Avatar Type → R6` as a fallback. Document this as a required manual step if the Rojo property is not applied.
5. Playtest: spawn a character and confirm the character model uses the R6 body parts (`Torso`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg`) — not R15 parts.

**Fallback:** If Rojo does not reliably apply `CharacterRigType` from `default.project.json`, the property must be set manually in Studio each session. In that case, document this as a blocking manual step here and in `docs/PROJECT_RULES.md`.

**Resolve when:** Steps 1–5 above are confirmed in Studio. If the Rojo property applies cleanly, mark resolved and note the Rojo version under which it was verified. If it does not apply, update this entry with the fallback procedure and leave severity at High.

---

## [DEBT-050] MovementController animation set selection is presentation-only — UPDATED 2026-05-18

**File:** `src/client/MovementController.lua` (`getAnimationSetName()`, `SetEquippedWeaponName()`)
**Severity:** Low-Medium (down from Medium — Unarmed is now correct default)
**Studio verification required:** Yes
**Partially resolved (2026-05-18):** `getAnimationSetName()` no longer hardcodes AR15. Default is now `Unarmed` (`equippedWeaponName == nil`). A new `SetEquippedWeaponName(name)` public method lets callers switch the active animation set. This is presentation-only — it controls movement animation selection only and has no effect on server weapon state, ammo, damage, or inventory. `GetEquippedWeaponName()` exposes the current value.
**Remaining risk:** `equippedWeaponName` is set by the client-side `SetEquippedWeaponName()` call. No server-owned equipment state exists yet to drive it authoritatively. The correct call site (an `EquipmentController` or weapon equip/drop system) does not exist — `SetEquippedWeaponName` currently has no caller in the codebase. This means:
- The default Unarmed set plays at all times until a real equip event calls `SetEquippedWeaponName("AR15")`.
- When a player picks up or equips the AR15, something must call `MovementController.SetEquippedWeaponName("AR15")`.
- When a player drops or loses the AR15, something must call `MovementController.SetEquippedWeaponName(nil)`.
**Trigger:** InventoryService or EquipmentController is built and sends equipped weapon state to the client.
**Fix when:** A real equipment/loadout system exists. Wire `SetEquippedWeaponName` to the weapon equip/unequip event from that system. At that point the client-side presentation state correctly mirrors server authority — remove the "presentation-only" caveat from this entry.

---

## [DEBT-008] pcall on GetMatchConfig silently swallows server errors — RESOLVED 2026-05-06

**File:** `src/client/MatchController.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`GetMatchConfig:InvokeServer()` is wrapped in `pcall`. If `MatchService` has a bug in its `OnServerInvoke` handler — an error thrown, a nil return, a missing field — the `pcall` catches it, prints a generic fallback message, and the controller continues with stale default state (LOBBY, round 0). This makes a server-side logic error look like a timing issue and is easy to miss.~~
**Resolution:** The `else` branch now distinguishes two cases. `not ok` (genuine error thrown server-side) calls `warn("[MatchController] GetMatchConfig error:", result)` where `result` is the error string — visible as red output. `ok` with a nil result keeps the original print, since that is a genuine timing edge case and not an error.
