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

## [DEBT-003] lastFiredPhase compares phase string only, not (phase, round) pair

**File:** `src/server/MatchService.server.lua`
**Severity:** Low-Medium
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

## [DEBT-005] Odd player counts always give the extra player to Attackers

**File:** `src/server/TeamService.server.lua`
**Severity:** Medium
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

## [DEBT-007] Multiple clients connect to RoundStateChanged independently

**Files:** `src/client/MatchController.lua`, `src/client/UI/MatchUI.lua`, `src/client/UI/HUD.lua`, `src/client/UI/CrosshairUI.lua`, `src/client/ViewModelController.lua`, `src/client/UI/DeathScreen.lua`
**Severity:** Medium-High
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

## [DEBT-019] Players.CharacterAutoLoads = false is set globally in TeamService with no fallback

**File:** `src/server/TeamService.server.lua`
**Severity:** Medium-High
**Studio verification required:** Yes
**Risk:** `Players.CharacterAutoLoads = false` is set at the top of TeamService. If TeamService fails to load (a require error, a script disabled in Studio), Roblox will never auto-spawn characters, and players will see a blank screen with no error. There is no watchdog that re-enables auto-loading if TeamService fails, and no fallback spawn path.
**Trigger:** Any unhandled error in TeamService's module-level code (e.g. a missing dependency) that prevents the script from running fully.
**Fix when:** The server-side error handling pass. Add a `pcall` around the PREP phase handler in TeamService, and consider a separate failsafe script that re-enables CharacterAutoLoads if TeamService has not reported readiness within N seconds.

---

## [DEBT-020] Team name strings are duplicated across TeamService and ObjectiveService — PARTIALLY RESOLVED 2026-05-07

**Files:** `src/server/TeamService.server.lua`, `src/server/ObjectiveService.server.lua`
**Severity:** Medium
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

## [DEBT-023] BallSocketConstraint ragdoll assumes a standard Roblox R15 or R6 character rig

**File:** `src/server/RagdollService.lua`
**Severity:** Low-Medium
**Studio verification required:** Yes
**Risk:** `RagdollService:Apply()` iterates `character:GetDescendants()` and converts every `Motor6D` it finds. This works correctly for standard Roblox R15 and R6 characters, which have a known, predictable Motor6D hierarchy. If a custom character rig is introduced (e.g. a non-humanoid defender faction, a monster that uses the Humanoid class, or a weapon held by a player model with its own Motor6Ds), `Apply()` may convert joints that should not be ragdolled — breaking the custom rig or producing unexpected physics behavior.
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

## [DEBT-008] pcall on GetMatchConfig silently swallows server errors — RESOLVED 2026-05-06

**File:** `src/client/MatchController.lua`
**Severity:** Resolved
**Studio verification required:** Not applicable
**Risk:** ~~`GetMatchConfig:InvokeServer()` is wrapped in `pcall`. If `MatchService` has a bug in its `OnServerInvoke` handler — an error thrown, a nil return, a missing field — the `pcall` catches it, prints a generic fallback message, and the controller continues with stale default state (LOBBY, round 0). This makes a server-side logic error look like a timing issue and is easy to miss.~~
**Resolution:** The `else` branch now distinguishes two cases. `not ok` (genuine error thrown server-side) calls `warn("[MatchController] GetMatchConfig error:", result)` where `result` is the error string — visible as red output. `ok` with a nil result keeps the original print, since that is a genuine timing edge case and not an error.
