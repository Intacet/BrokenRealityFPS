# TECHNICAL_DEBT.md

A running list of known maintenance risks, shortcuts, and deferred problems flagged during development.

**This is not a changelog.** Completed work belongs in `CHANGELOG.md`. This file tracks things that still need attention. Mark an entry `RESOLVED` and add the fix date when the underlying issue is addressed — do not delete entries.

---

## [DEBT-001] Phase type union manually duplicated from Constants.Phase — PARTIALLY RESOLVED 2026-05-07

**File:** `src/shared/Types.lua` and `src/shared/Constants.lua`
**Risk:** `export type Phase` in `Types.lua` is a manually written string union. Luau has no `keyof` or value-union derivation, so this cannot be derived from the `Constants.Phase` table. Both declarations must be updated together whenever a phase is added or renamed. If only one is changed, the type system will silently allow invalid phase strings through any code that reads from the table but type-checks against the union.
**Partial resolution (2026-05-07):** The `"MATCHEND"` phase was added to both `Constants.Phase` and the `Types.Phase` union at the same time (Batch 1 task). Both files currently list exactly the same five phases: LOBBY, PREP, ACTIVE, RESULTS, MATCHEND. The structural risk — no compiler enforcement of the sync — remains because Luau still has no `keyof` equivalent.
**Trigger:** Adding any new phase to `Constants.Phase` without adding it to the `Types.Phase` union, or vice versa.
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

## [DEBT-004] Team colours are local to TeamService, not in Constants — PARTIALLY RESOLVED 2026-05-07

**File:** `src/server/TeamService.server.lua`
**Risk:** ~~`ATTACKER_COLOR`, `DEFENDER_COLOR`, and `TELEPORT_Y_OFFSET` are defined as local constants inside TeamService.~~ `ATTACKER_COLOR` and `DEFENDER_COLOR` are still defined as local constants inside TeamService. If another system (kill feed, HUD team indicator, spectator camera) needs to read team colours, it will either hardcode them again or have no access to them — creating duplicate magic values.
**Partial resolution (2026-05-07):** `TELEPORT_Y_OFFSET` was moved to `src/shared/Constants.lua` during the "No magic numbers" audit. The offset value is no longer duplicated. `ATTACKER_COLOR` and `DEFENDER_COLOR` were not moved because `BrickColor` values are not numeric literals — they fall outside the no-magic-numbers rule. The underlying colour-duplication risk remains.
**Trigger:** Adding a kill feed, name tag, or any UI that needs to tint elements by team colour.
**Fix when:** Any system outside TeamService needs to read team colours. Move `ATTACKER_COLOR` and `DEFENDER_COLOR` to `src/shared/Constants.lua` at that point.

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

**Files:** `src/server/GunService.server.lua`, `src/client/GunController.lua`
**Risk:** `DEFAULT_WEAPON = "AssaultRifle"` in GunService and `CURRENT_WEAPON = "AssaultRifle"` in GunController are independent hardcodes that must be kept in sync. GunController's `WeaponFired` payload is `{origin, direction, tick}` with no weapon name — so the server cannot know what weapon the client is using. With a single weapon this is invisible; with multiple weapons, every shot is validated against AssaultRifle stats regardless of what the player holds.
**Worsened (2026-05-07):** The ammo system added in GunService (`setupAmmo`, `ReloadRequest` handler) also looks up `WeaponData[DEFAULT_WEAPON]` for `magazineSize` and `reserveAmmo`. A player holding a different weapon would be assigned AssaultRifle ammo and have their reload calculated against AssaultRifle's magazine size. There are now three hardcoded lookup points instead of two.
**Trigger:** Adding a second weapon to WeaponData, or giving players a loadout choice.
**Fix when:** Multiple weapons exist. Add `weaponName: string` to the `WeaponFired` payload (and to `ReloadRequest`), validate it exists in WeaponData on the server, and remove all three hardcoded DEFAULT_WEAPON / CURRENT_WEAPON references.

---

## [DEBT-014] WeaponFired clientTick is received but not validated

**File:** `src/server/GunService.server.lua`
**Risk:** The `tick` value sent with each `WeaponFired` event is intended to let the server reject shots with timestamps too far in the past (replay attacks or lag compensation abuse). Currently `_clientTick` is discarded. Without this check, a client could theoretically queue up shots during lag and dump them all at once, bypassing the server-side rate limiter — though the rate limiter's `os.clock()` comparison already partially mitigates this.
**Trigger:** The game is stress-tested with high-latency clients or an exploiter attempts shot-replay injection.
**Fix when:** Combat is otherwise stable. Add a maximum acceptable age check: `if os.clock() - clientTick > MAX_SHOT_AGE then return end` where `MAX_SHOT_AGE` accounts for typical RTT plus a tolerance (e.g. 0.5 s). Add `MAX_SHOT_AGE` to Constants.

---

## [DEBT-015] MatchController.client.lua must be renamed MatchController.lua before GunController works — RESOLVED 2026-05-07

**Files:** `src/client/MatchController.client.lua`, `src/client/GunController.client.lua`
**Risk:** ~~`GunController.client.lua` calls `require(script.Parent:WaitForChild("MatchController"))`. A file named `MatchController.client.lua` creates a LocalScript instance — `require()` will throw at runtime. The game will error on the client on startup.~~
**Resolution:** Both controllers renamed to `.lua` (ModuleScript). `MatchController.client.lua` → `MatchController.lua`; `GunController.client.lua` → `GunController.lua`. The self-calling `MatchController:Start()` at the bottom of MatchController was removed — leaving it in would have caused `Start()` to fire twice on `require()` (once from the module tail, once from ClientInit), registering `RoundStateChanged.OnClientEvent` twice. GunController's event connections were wrapped in `GunController:Start()` and a `return GunController` was added. `ClientInit.client.lua` is the sole LocalScript runner — it requires both controllers in dependency order (MatchController first) and calls their `Start()` methods. `require()` now resolves correctly; the startup error is eliminated.

---

## [DEBT-010] DamageService health reset fires for all players including mid-respawn characters

**File:** `src/server/DamageService.lua`
**Risk:** On PREP, `resetHealth()` calls `setHealth(player, MAX_HEALTH)` and fires `HealthChanged` to the client for every connected player. If a player is mid-respawn (character is nil or Humanoid is being created), the client receives a correct health value but the Humanoid itself may reset to its default health independently when the new character loads — causing a brief mismatch between the server table and the Humanoid's displayed value.
**Trigger:** A player disconnects or dies in the final second of RESULTS, so their character is respawning exactly when PREP begins and `resetHealth()` fires.
**Fix when:** CorpseService is built (it owns character lifecycle). At that point, hook health reset into `CharacterAdded` instead of relying solely on the phase-change event.

---

## [DEBT-007] Multiple clients connect to RoundStateChanged independently

**Files:** `src/client/MatchController.lua`, `src/client/UI/MatchUI.lua`, `src/client/UI/HUD.lua`, `src/client/UI/CrosshairUI.lua`, `src/client/ViewModelController.lua`, `src/client/UI/DeathScreen.lua`
**Risk:** Six separate systems now each connect their own `RoundStateChanged.OnClientEvent` listener. Every server broadcast triggers six separate handlers. If the payload format ever changes, all six must be updated together.
**History:** Originally 1 listener (MatchController). Each new system that needs phase data adds another — now at 6. The fix of introducing a `MatchController.StateChanged` BindableEvent is overdue.
**Trigger:** Adding any further system that reads phase data (CutsceneController, ObjectiveUI, etc.).
**Fix when:** A seventh listener is needed, or when a payload format change is required. Introduce `MatchController.StateChanged` BindableEvent, fire it from `applyState()`, migrate all UI/controllers to subscribe to it instead of the RemoteEvent directly.

---

## [DEBT-016] Logger.DEBUG_MODE requires a source-level code edit to disable for production — RESOLVED 2026-05-07

**File:** `src/shared/Logger.lua`
**Risk:** ~~`DEBUG_MODE = true` is a Lua local variable inside `Logger.lua`. Silencing all `Logger.debug()` output before shipping requires opening the file and changing the value to `false`. A developer who forgets to flip the flag ships with debug output visible to every player in the Output window.~~
**Resolution:** Replaced `local DEBUG_MODE = true` with `local DEBUG_MODE = game:GetService("RunService"):IsStudio()`. `RunService:IsStudio()` returns `true` only inside Roblox Studio and `false` in any live published build or Roblox test server. No manual step exists to forget — the runtime environment determines the flag automatically. The underlying risk is fully eliminated.

---

## [DEBT-017] ClientInit must be manually updated when a new controller is added

**File:** `src/client/ClientInit.client.lua`
**Risk:** `ClientInit.client.lua` holds an explicit ordered list of `loadAndStart()` / `loadInitAndStart()` calls. When a new controller is built (e.g. `MovementController`, `CutsceneController`), a developer must manually add its call in the correct position. If forgotten, the controller's `Start()` is never called and it silently does nothing — no error, no warning, just a non-functional system.
**Current count:** 8 entries (MatchController, MatchUI, HUD, DeathScreen, CrosshairUI, ViewModelController, SoundController, GunController).
**Trigger:** Every time a new controller is built. The risk grows with each addition.
**Fix when:** The controller count reaches double digits. At that point, consider a self-registration pattern where each ModuleScript registers itself with ClientInit via a shared table, or a folder-scan pattern that discovers and calls all controllers automatically. Until then, the explicit list is simpler and clearer.

---

## [DEBT-018] getPlayerFromPart is duplicated in DamageService and ObjectiveService

**Files:** `src/server/DamageService.lua`, `src/server/ObjectiveService.server.lua`
**Risk:** Both services implement an identical `getPlayerFromPart(hit: BasePart): Player?` helper that walks up the ancestor chain to find the owning Player. If the Roblox character hierarchy ever changes (e.g. a model-in-model arrangement for ragdolls or vehicles), both copies must be updated in sync. A fix in one without the other will cause inconsistent hit detection across services.
**Trigger:** Adding a third service that needs to map a BasePart back to a Player (e.g. MonsterService targeting a player, or a Zone service checking who is inside a region).
**Fix when:** A third consumer appears. Create `src/server/CharacterUtil.lua` (ModuleScript) with `CharacterUtil.getPlayerFromPart(hit)` and `CharacterUtil.getHumanoid(player)`. Replace the inline copies in DamageService and ObjectiveService with `require(CharacterUtil)` calls.

---

## [DEBT-019] Players.CharacterAutoLoads = false is set globally in TeamService with no fallback

**File:** `src/server/TeamService.server.lua`
**Risk:** `Players.CharacterAutoLoads = false` is set at the top of TeamService. If TeamService fails to load (a require error, a script disabled in Studio), Roblox will never auto-spawn characters, and players will see a blank screen with no error. There is no watchdog that re-enables auto-loading if TeamService fails, and no fallback spawn path.
**Trigger:** Any unhandled error in TeamService's module-level code (e.g. a missing dependency) that prevents the script from running fully.
**Fix when:** The server-side error handling pass. Add a `pcall` around the PREP phase handler in TeamService, and consider a separate failsafe script that re-enables CharacterAutoLoads if TeamService has not reported readiness within N seconds.

---

## [DEBT-020] Team name strings are duplicated across TeamService and ObjectiveService

**Files:** `src/server/TeamService.server.lua`, `src/server/ObjectiveService.server.lua`
**Risk:** Both services define `local TEAM_ATTACKERS = "Attackers"` and both assume `TEAM_DEFENDERS = "Defenders"` (implicit). If a team is renamed, both files must be updated together. A mismatch — e.g. TeamService assigns "Attacker" (no s) but ObjectiveService checks "Attackers" — silently breaks objective capture without any runtime error, because `playerTeams[player] ~= TEAM_ATTACKERS` is always true.
**Trigger:** Renaming a team, or adding a third service that filters by team name.
**Fix when:** A third consumer appears, or when the team names are likely to change. Add `Constants.TEAM_ATTACKERS = "Attackers"` and `Constants.TEAM_DEFENDERS = "Defenders"` to `src/shared/Constants.lua` and replace the local declarations in both service files.

---

## [DEBT-022] Ragdolled characters have no cleanup owner until CorpseService is built

**File:** `src/server/RagdollService.lua`
**Risk:** `RagdollService:Apply()` deliberately does not destroy the character — the ragdoll stays in Workspace so other players can see it. However, there is currently no system that removes these ragdoll models. Motor6Ds disabled + BallSocketConstraints attached means the character is a persistent physics object. Across multiple rounds, ragdolled characters from earlier rounds accumulate in Workspace. They have no cleanup on PREP or RESULTS.
**Current exposure:** Characters are still respawned at the start of PREP via `player:LoadCharacter()` in TeamService — this replaces the character reference on the Player object, but the old ragdolled Model is orphaned in Workspace (it loses its `Players.Player.Character` association but is not destroyed).
**Trigger:** After the first kill in any round. Corpses accumulate every round. On a long session, this causes memory pressure and visual clutter.
**Fix when:** CorpseService is built (Stage 5 on the roadmap). CorpseService should take ownership of ragdolled models, track them across rounds, and call `:Destroy()` on all of them at MATCHEND.

---

## [DEBT-023] BallSocketConstraint ragdoll assumes a standard Roblox R15 or R6 character rig

**File:** `src/server/RagdollService.lua`
**Risk:** `RagdollService:Apply()` iterates `character:GetDescendants()` and converts every `Motor6D` it finds. This works correctly for standard Roblox R15 and R6 characters, which have a known, predictable Motor6D hierarchy. If a custom character rig is introduced (e.g. a non-humanoid defender faction, a monster that uses the Humanoid class, or a weapon held by a player model with its own Motor6Ds), `Apply()` may convert joints that should not be ragdolled — breaking the custom rig or producing unexpected physics behavior.
**Trigger:** Adding any non-standard character rig to the game.
**Fix when:** A custom rig is introduced. Add a tag or attribute (e.g. `Instance:SetAttribute("RagdollEnabled", true)`) to each Motor6D that should participate in ragdolling, and filter by that attribute in `convertJoint()`.

---

## [DEBT-024] SoundController uses single Sound instances with no pooling

**File:** `src/client/SoundController.lua`
**Risk:** Each sound type (gunshot, hit, reload, death, dry-fire) is backed by exactly one `Sound` instance. Calling `Sound:Play()` when the instance is already playing restarts it from the beginning rather than spawning a concurrent playback. For `PlayGunshot()` called at `AssaultRifle.fireRate = 0.1 s` intervals, if the gunshot sound asset is longer than 0.1 s, each new shot cuts the previous one audibly. This produces a choppy, interrupted audio experience at the maximum fire rate.
**Current exposure:** The gunshot asset (`rbxassetid://4792534948`) is a short percussive shot; restart-on-play produces an acceptable rapid-fire stutter at this fire rate. Risk grows if a slower, longer-sounding weapon is added.
**Trigger:** Adding a weapon with a fire rate longer than the corresponding sound asset's duration, or adding a shotgun/burst weapon that plays multiple sounds at once.
**Fix when:** A second weapon type with a noticeably longer sound is added. Implement a small sound pool per type (3–5 clones, round-robin `Play()`). Alternatively, use `SoundGroup` with `PolyphonyMode = SoundGroup.Polyphony` if that API is available.

---

## [DEBT-025] DryFire sound has no asset ID assigned — ACTIVELY TRIGGERED

**File:** `src/client/SoundController.lua`
**Risk:** `ID_DRYFIRE = ""` — `SoundController:PlayDryFire()` logs a warning and returns immediately without playing anything. GunController now calls `PlayDryFire()` when the magazine is empty (ammo system added 2026-05-07), so the warning `[SoundController] PlayDryFire: no SoundId assigned (DEBT-025)` will appear in Output on every empty-mag click during playtesting.
**Trigger:** Player fires with an empty magazine. Now active in every ACTIVE phase after the magazine is exhausted.
**Fix when:** Immediately — find a free Roblox audio asset for a dry-fire click (e.g. a Mauser empty-chamber click), assign its `rbxassetid://` to `ID_DRYFIRE` in `SoundController.lua`, and remove the early-return guard in `PlayDryFire()`.

---

## [DEBT-026] Ammo is not initialized for players who join after the PREP TeamAssigned window

**File:** `src/server/GunService.server.lua`
**Risk:** GunService populates `playerMag` and `playerReserve` when `MatchEvents.TeamAssigned` fires (during PREP). TeamService fires TeamAssigned for all connected players at the start of every PREP phase. A player who joins while a round is already ACTIVE will not receive TeamAssigned until the next PREP; their `playerMag` and `playerReserve` will be `nil`. The WeaponFired handler already guards against this — it returns silently if `playerMag[shooter] == nil` — so no crash occurs. However, that player cannot fire at all until the next round, even though TeamService also does not spawn mid-ACTIVE joiners, so the nil ammo case is moot in practice.
**Trigger:** A player joins during ACTIVE phase and, by some path, has a character and attempts to fire (e.g. a future game mode that allows mid-round joining).
**Fix when:** A mid-round join or reinforcement system is built. At that point, hook into `Players.PlayerAdded` and `player.CharacterAdded` during ACTIVE to assign ammo on spawn rather than relying solely on TeamAssigned.

---

## [DEBT-021] ViewModelController parts have no cleanup path if Start() is called twice

**File:** `src/client/ViewModelController.lua`
**Risk:** `gunBody`, `barrel`, and `grip` are module-level variables created inside `Start()`. If `Start()` were called a second time (e.g., a future re-initialization path), a new set of Parts would be parented to `workspace.CurrentCamera` without the old ones being destroyed — leaving orphaned, invisible Parts consuming memory and rendering time.
**Current exposure:** ClientInit calls `Start()` exactly once per session; there is no re-initialization path today. Risk is not triggered.
**Trigger:** Any future change that calls `Start()` more than once, or a pattern where the controller is torn down and rebuilt (e.g., a map reload system).
**Fix when:** A re-initialization path is needed. Add a `cleanup()` helper at the top of `Start()` that destroys existing Parts if they are non-nil before creating new ones.

---

## [DEBT-008] pcall on GetMatchConfig silently swallows server errors — RESOLVED 2026-05-06

**File:** `src/client/MatchController.lua`
**Risk:** ~~`GetMatchConfig:InvokeServer()` is wrapped in `pcall`. If `MatchService` has a bug in its `OnServerInvoke` handler — an error thrown, a nil return, a missing field — the `pcall` catches it, prints a generic fallback message, and the controller continues with stale default state (LOBBY, round 0). This makes a server-side logic error look like a timing issue and is easy to miss.~~
**Resolution:** The `else` branch now distinguishes two cases. `not ok` (genuine error thrown server-side) calls `warn("[MatchController] GetMatchConfig error:", result)` where `result` is the error string — visible as red output. `ok` with a nil result keeps the original print, since that is a genuine timing edge case and not an error.
