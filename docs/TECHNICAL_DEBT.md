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

## [DEBT-051] Feature scope risk — persistent-zone design contains many long-term systems that must be staged — ADDED 2026-05-20

**Files:** `CLAUDE.md`, `docs/PROJECT_RULES.md`, `docs/PERSISTENT_ZONE_ROADMAP.md`
**Severity:** High
**Studio verification required:** Not applicable (design/planning debt, not a runtime bug)
**Risk:** The refined persistent-zone direction (metro base, physical zone transitions, carried cash, secured funds, risky in-zone shops, faction traders, missions, Reality Breakdown events, base storage and upgrades) is a large feature surface. If multiple systems are attempted in one prompt or one sprint without per-stage Studio verification, the result will be untestable scaffolding rather than a working loop. Historically this kind of scope ambiguity leads to half-implemented systems that block each other and debt that cannot be verified.

**Specific high-risk deferred systems that must not be started prematurely:**
- **Player flea market / global marketplace** — requires stable economy, stash, item ownership, anti-duplication system, and moderation/abuse controls. None of these exist yet. Starting the marketplace before these are in place creates an exploitable, unstable economy with no rollback path.
- **Free drawing on signs / custom sign painting** — content moderation and abuse risk have not been addressed. Building this system before a moderation plan exists creates a content abuse vector with no response capability.
- **Advanced AI death squads** — requires basic MonsterService (Stage 8) and zone events (Stage 7) to be proven first. Jumping to advanced AI before the simple version is stable adds unverifiable complexity.
- **Full gun attachment system** — requires weapon inventory, shop, and stash to be stable before attachment items can be stored, sold, or equipped. Building attachments before the item system exists creates orphaned data.
- **Complex visor / enemy detection system** — high design and implementation complexity; requires basic AI (Stage 8) and the combat loop to be proven first.
- **Full base decoration system** — cosmetic priority; requires core loop + stash (Stage 9) to be stable first.

**Rules:**
- Build one persistent-zone system at a time, per `docs/PERSISTENT_ZONE_ROADMAP.md`.
- Do not begin Stage N+1 until Stage N is verified in Studio.
- The flea market/player marketplace must not be prototyped, scaffolded, or designed in code until economy, stash, item ownership, anti-duplication, and a moderation plan are all confirmed stable.
- See `docs/PROJECT_RULES.md` (Refined persistent-zone design rules) for the full rule set.

**Resolve when:** Each stage in `docs/PERSISTENT_ZONE_ROADMAP.md` is individually verified in Studio. This entry closes when Stages 1–9 are complete and the deferred systems have been explicitly re-evaluated against their prerequisites.

---

## [DEBT-036] Round-based architecture no longer matches target persistent-zone design — UPDATED 2026-05-20

**Files:** `src/server/MatchService.server.lua`, `src/server/TeamService.server.lua`, `src/server/ObjectiveService.server.lua`, `src/client/UI/MatchUI.lua`, `src/client/UI/DeathScreen.lua`, `src/client/MatchController.lua`
**Severity:** High
**Studio verification required:** Yes
**Risk:** The current running codebase implements a five-round attackers-vs-defenders FPS loop. The target product direction (updated 2026-05-20) is a persistent PvPvE metro-base zone shooter: players spawn in a safe metro station, enter the quarantine zone through physical transitions (gates, trains, sewers), earn carried cash, optionally buy from risky in-zone shops, complete simple faction trader missions, survive Reality Breakdown events, and extract through physical exits to deposit at the metro base terminal. The existing round-based services (`MatchService`, `TeamService`, `ObjectiveService`) and their client counterparts (`MatchController`, `MatchUI`, `DeathScreen`) encode round-start, round-end, PREP/ACTIVE/RESULTS phase transitions, team assignment, and objective completion as core concepts. None of these map directly to the persistent zone loop.

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

**Roadmap reference:** `docs/PERSISTENT_ZONE_ROADMAP.md` defines the 10-stage staged build order for the persistent zone pivot (updated 2026-05-20 with metro-base design, physical zone transitions, risky in-zone shops, faction trader missions, Reality Breakdown events, and explicit deferred-feature rules). That document is planning-only — it does not resolve this debt entry. Runtime systems must still be built and verified in Studio stage by stage before this entry can be closed.

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

## [DEBT-034] MCP verification relies on Claude self-reporting — no automated scope guard — UPDATED 2026-05-19 (x2)

**File:** `CLAUDE.md`, `docs/PROJECT_RULES.md`
**Severity:** Low-Medium
**Studio verification required:** No
**Risk:** MCP verification rules are behavioral conventions enforced by `CLAUDE.md` and `docs/PROJECT_RULES.md`. There is no CI gate, hook, or linter that verifies whether Studio MCP was actually used before a commit was made. A session that does not read `CLAUDE.md` at startup, or one that proceeds with a runtime change without explicitly flagging it, may commit unverified gameplay changes silently.
**Updated (2026-05-19 — rule strengthened):** The MCP verification rule was significantly expanded. Previously it only described what to do when MCP was *unavailable*. The updated rule now:
- Requires MCP verification **before committing** for any change touching `src/server/`, `src/client/`, `src/shared/`, remotes, Rojo config, player spawning, camera/mouse behavior, viewmodel, movement input, combat, UI, economy, inventory, zone systems, character rig, or animations.
- Explicitly states that static checks (`selene`, `rojo build`, formatting) do **not** replace MCP runtime verification for gameplay systems.
- Defines a workflow: edit → `rojo serve` → MCP → play → verify → commit.
- Prohibits claiming Studio verification unless it was actually performed through MCP or a confirmed manual Studio test.
- Lists specific systems where MCP must not be skipped even for "small" changes (movement input, camera, animation, remotes, character spawn lifecycle, economy).
The same rule is now mirrored in `docs/PROJECT_RULES.md` (new "Studio / MCP verification" section with a verification table and workflow).
**Remaining risk:** The rules are still self-enforced. No CI gate exists to confirm MCP was used. The structural gap is unchanged.
**Trigger:** Any gameplay-affecting change (camera, viewmodel, combat, movement, match-loop, objectives, replication, economy, UI) committed without a Studio session — especially in a GitHub-only or context-limited session.
**Fix when:** A CI step can run `rojo build` and `selene` automatically on every push to catch at least structural errors. Full runtime verification always requires Studio. Until CI is added, unverified gameplay changes must be manually tagged "needs Studio verification" in the PR description and in a TECHNICAL_DEBT entry. Separately, a `.claude/settings.json` PreToolUse hook could remind the session to confirm MCP availability before editing gameplay files.

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

## [DEBT-044] MovementController animation system — Unarmed directional animations — UPDATED 2026-05-22 (x25)

**File:** `src/client/MovementController.lua`, `src/shared/Constants.lua`
**Severity:** Medium
**Studio verification required:** Yes
**Updated (2026-05-18 — Stage 2A):** R6 walk/run animation playback added. Four AnimationTrack objects are loaded per character via `Humanoid.Animator`. Tracks are played during ACTIVE phase only and cleared on respawn/destroy. `directionName` is correctly computed and drives animation selection alongside `isSprinting`.
**Updated (2026-05-18 — Animate-disable bug fix):** Custom animation tracks were not playing because the default Roblox `Animate` LocalScript was overriding them. `disableDefaultAnimate()` now sets `character.Animate.Disabled = true` before custom tracks are loaded. Gated by `Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED` and `Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT` (both default `true`). Animation diagnostics added behind `Constants.MOVEMENT_ANIMATION_DEBUG`. WalkLeft/WalkRight fallback logic added.
**Updated (2026-05-18 — R6 detection):** `hasR6BodyParts()`, `getRigDebugSummary()`, and `isR6Character()` helpers added. The direct `RigType ~= R6` guard replaced with `isR6Character()` (primary `RigType` check + structural body-part fallback). `disableDefaultAnimate()` moved from `setupCharacter()` into `loadMovementAnimations()` (after rig confirmation) so Animate is only disabled when the character is confirmed R6. `getRigDebugSummary()` logged when animations are skipped.
**Updated (2026-05-18 — animation-set selection fix):** Default animation set changed from AR15 to Unarmed. `getAnimationSetName()` now reads `equippedWeaponName` (nil → Unarmed, "AR15" → AR15 set, unknown → Unarmed fallback). Two new public methods: `SetEquippedWeaponName(name)` and `GetEquippedWeaponName()`. Both Unarmed and AR15 tracks are pre-loaded at spawn. Unarmed WalkLeft (`rbxassetid://101275785187464`) and WalkRight (`rbxassetid://72765640529019`) added. Animation-set-change debug log added (fires once per change, not per frame). Three new Constants: `MOVEMENT_ANIMATION_SET_UNARMED`, `MOVEMENT_ANIMATION_SET_AR15`, `MOVEMENT_DEFAULT_ANIMATION_SET`.
**Updated (2026-05-18 — Stage 2C animation behavior):** Strafe animations (WalkLeft/WalkRight) are now gated on mouse-lock / shift-lock style state. `UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter` is the practical runtime signal used (read-only — does not toggle shift lock or write camera). When not mouse-locked, all walking falls back to WalkForward. Gated by `Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK` (default `true`); set `false` to play strafe anims regardless. LeftShift sprint now works while Roblox's built-in shift lock is active — the previous `gameProcessed` guard was replaced with `UserInputService:GetFocusedTextBox() ~= nil` (blocks sprint only when typing in a TextBox). Animation playback speed multipliers added via `AnimationTrack:AdjustSpeed()`: WalkForward at 2.0×, WalkLeft/WalkRight at 1.35×, RunForward at 1.0× (unchanged). Speed is applied on play and on same-track re-check. Three new Constants: `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER`, `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER`, `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER`. `lastStrafeBlockedState` guard prevents per-frame log spam — strafe-blocked/enabled log fires only on state change.
**Updated (2026-05-19 — Stage 2D: custom mouse-lock toggle):** LeftShift sprint conflicted with Roblox default Shift Lock — pressing Shift both sprinted and toggled native mouse lock simultaneously. Resolved by adding a custom mouse-lock toggle on LeftAlt (`Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY`). `customMouseLocked` (local boolean) is the new source of truth for strafe animation gating. `isMouseLockedForStrafeAnimations()` now returns `customMouseLocked` when `CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true` (default), instead of reading `UserInputService.MouseBehavior`. `SetCustomMouseLocked(bool)` and `IsCustomMouseLocked()` are new public API methods. `UserInputService.MouseBehavior` is still written by `SetCustomMouseLocked` (LockCenter on, Default off) but is no longer the strafe gate source. Mouse lock released to Default on respawn and in `destroy()`. Four new Constants: `CUSTOM_MOUSE_LOCK_ENABLED`, `CUSTOM_MOUSE_LOCK_TOGGLE_KEY`, `CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY`, `CUSTOM_MOUSE_LOCK_DEBUG`.
**Updated (2026-05-19 — Stage 2D bugfix: three runtime bugs resolved):**
- **(1) Roblox default Shift Lock still toggling with LeftShift:** `default.project.json` now sets `StarterPlayer.EnableMouseLockOption = false` via Rojo `"Bool"` property. New helper `disableRobloxDefaultMouseLock()` calls `LocalPlayer.DevEnableMouseLock = false` (via `pcall`) on `Start()` and on every `CharacterAdded` — re-applies after respawn in case CoreScripts restore it. New constant: `DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK = true`.
- **(2) LeftAlt mouse-lock had ~1-frame delayed activation:** The `UserInputService.InputBegan` handler was replaced with `ContextActionService:BindActionAtPriority` at priority 3000 (above CoreScript default 2000). The action is bound by name (`MOUSE_LOCK_ACTION_NAME = "MovementController_ToggleCustomMouseLock"`) and unbound by name in `destroy()` — NOT stored in `_connections`. New constant: `CUSTOM_MOUSE_LOCK_INPUT_PRIORITY = 3000`.
- **(3) WalkLeft/WalkRight strafe animations not playing:** CoreScripts or UI transitions could silently reset `UserInputService.MouseBehavior` after the LeftAlt toggle, while `customMouseLocked` remained true and the strafe gate read correctly. New constant `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true` causes the Heartbeat callback to re-write `MouseBehavior = LockCenter` on every frame while `customMouseLocked` is true, preventing the lock from being stolen.
- **Phase-exit behavior changed:** `customMouseLocked` is NO LONGER reset when leaving ACTIVE phase. Player's toggle state persists across ACTIVE → LOBBY → RESULTS → ACTIVE. Only `loadMovementAnimations()` (respawn) and `destroy()` reset it to `false`. The `SetCustomMouseLocked()` call now delegates to new private helper `applyCustomMouseLock()` instead of writing `MouseBehavior` inline.
- Three new Constants added: `DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK`, `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME`, `CUSTOM_MOUSE_LOCK_INPUT_PRIORITY`.

**Updated (2026-05-20 — Unarmed strafe ID swap + multiplier correction):**
- `Unarmed.WalkLeft` replaced: `101275785187464` → `115652140967957` (confirmed-good R6 no-gun strafe left).
- `Unarmed.WalkRight` replaced: `73888687255042` → `82804864629403` (confirmed-good R6 no-gun strafe right).
- Animation speed multipliers corrected to confirmed values: walk 1.7×, strafe 1.4×, run 1.15×.
- All AR15 IDs, Unarmed WalkForward/RunForward IDs, and all MovementController behavior preserved unchanged.
- Asset swap and constant correction only — no logic changes.

**Updated (2026-05-20 — Stage 2F: Unarmed backward/diagonal directional animations):**
- Five new Unarmed animation IDs added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`:
  - `WalkBackward = rbxassetid://107080862064563`
  - `WalkBackwardLeft = rbxassetid://107785647885776`
  - `WalkBackwardRight = rbxassetid://109190640713438`
  - `WalkForwardLeft = rbxassetid://97324289156918`
  - `WalkForwardRight = rbxassetid://81077784555491`
- Five corresponding entries added to `loadMovementAnimations()` toLoad table (all pre-loaded at spawn).
- `getAnimationSpeedMultiplier()` extended: WalkBackward, WalkBackwardLeft/Right, WalkForwardLeft/Right → 1.7× (same as WalkForward).
- `updateMovementAnimation()` Unarmed branch rewritten for full per-direction selection:
  - Backward → WalkBackward → WalkForward fallback (no mouse-lock requirement).
  - ForwardLeft → WalkForwardLeft → WalkLeft (if mouse locked) → WalkForward.
  - ForwardRight → WalkForwardRight → WalkRight (if mouse locked) → WalkForward.
  - BackwardLeft → WalkBackwardLeft → WalkBackward → WalkForward.
  - BackwardRight → WalkBackwardRight → WalkBackward → WalkForward.
  - Left/Right: unchanged — WalkLeft/WalkRight only when mouse locked.
- AR15 and other sets: behavior unchanged (existing left/right grouping preserved).

**Updated (2026-05-20 — Stage 2G: Unarmed run-forward diagonal animations + walk multiplier change):**
- `Unarmed.RunForwardLeft = rbxassetid://94337945101783` added (confirmed-good R6 no-gun run forward-left).
- `Unarmed.RunForwardRight = rbxassetid://104724352837263` added (confirmed-good R6 no-gun run forward-right).
- Both tracks pre-loaded at spawn alongside all other Unarmed tracks.
- `updateMovementAnimation()` sprint block extended: Unarmed + `customMouseLocked == true` → ForwardLeft sprint plays RunForwardLeft, ForwardRight sprint plays RunForwardRight. All other sprint directions (and mouse lock off, or AR15/other sets) continue using RunForward as before.
- `getAnimationSpeedMultiplier()` extended: RunForwardLeft and RunForwardRight return `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER` (1.15×).
- `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER` changed: 1.7 → 1.3.
- Strafe multiplier preserved: 1.4×. Run multiplier preserved: 1.15×.
- No AR15 run diagonal IDs added. AR15 sprinting continues using AR15 RunForward in all directions.

**Updated (2026-05-20 — Unarmed WalkForward + RunForward ID swap):**
- `Unarmed.WalkForward` replaced: `83352851460622` → `97200177177374` (confirmed-good R6 no-gun walk forward).
- `Unarmed.RunForward` replaced: `106253559282626` → `81826691810907` (confirmed-good R6 no-gun run forward).
- All other Unarmed IDs (WalkLeft/Right, WalkBackward, WalkBackwardLeft/Right, WalkForwardLeft/Right) preserved.
- All AR15 IDs preserved.
- Animation speed multipliers intentionally preserved: walk 1.7×, strafe 1.4×, run 1.15×.
- No MovementController logic changed. No camera changes. No remotes.

**Updated (2026-05-19 — Stage 2E: character-facing camera yaw):**
When `CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW = true`, enabling custom mouse lock (LeftAlt) now also:
- Caches `Humanoid.AutoRotate` (once per lock session) into `originalAutoRotate` and sets `AutoRotate = false`, preventing the engine from auto-rotating the character toward its movement direction.
- Every Heartbeat: reads `workspace.CurrentCamera.CFrame.LookVector`, flattens to XZ, and writes `HumanoidRootPart.CFrame = CFrame.lookAt(pos, pos + flatLook)` to face the character toward the camera. Position is unchanged — this is a yaw-only rotation, not a teleport.
- On toggle-off: `restoreCharacterAutoRotate()` is called and `originalAutoRotate` is cleared.
- On respawn (`loadMovementAnimations`): `originalAutoRotate` is cleared; the new Humanoid starts with its own `AutoRotate` value.
- Phase gating (`CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION = true`): on leaving ACTIVE, `restoreCharacterAutoRotate()` is called but `originalAutoRotate` is NOT cleared (preserved for ACTIVE re-entry). On ACTIVE re-entry with `customMouseLocked` still true, `AutoRotate` is disabled again and `applyCharacterFacing()` is called immediately.
- `getCameraFlatLookVector()` returns nil when camera look vector is near-vertical (XZ magnitude < 0.001) to prevent NaN from `Vector3.Unit`; `applyCharacterFacing()` skips gracefully.
- `applyCharacterFacing()` uses `lastFacingSkippedReason` deduplication to log skip transitions once per reason, not every frame.
- New private state: `currentCharacter: Model?`, `currentRootPart: BasePart?`, `originalAutoRotate: boolean?`, `lastFacingSkippedReason: string`.
- Three new Constants: `CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW`, `CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION`, `CUSTOM_MOUSE_LOCK_ROTATION_DEBUG`.

**Updated (2026-05-20 — Stage 2H: Idle + EnterCrouch/ExitCrouch transition animations):**
- Six new animation IDs added to `Constants.MOVEMENT_ANIMATION_IDS.R6`:
  - `Unarmed.Idle = rbxassetid://132044223555193` (standing idle, looped)
  - `Unarmed.EnterCrouch = rbxassetid://105064599119554` (enter-crouch one-shot)
  - `Unarmed.ExitCrouch = rbxassetid://104596765238289` (exit-crouch one-shot)
  - `AR15.Idle = rbxassetid://117989834436525` (standing idle, looped)
  - `AR15.EnterCrouch = rbxassetid://79753647497328` (enter-crouch one-shot)
  - `AR15.ExitCrouch = rbxassetid://91295776984408` (exit-crouch one-shot)
- Two new speed multiplier constants: `MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER = 0.75`, `MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9`.
- All 6 tracks pre-loaded at spawn in `loadMovementAnimations()`. `EnterCrouch`/`ExitCrouch` keys use `track.Looped = false`; all other tracks remain `Looped = true`.
- New private state: `crouchTransitionPlaying: boolean`, `crouchTransitionConn: RBXScriptConnection?`.
- New helper `stopCrouchTransition()` (no deps, defined before Stage 2A section): disconnects `crouchTransitionConn` before any `track:Stop()` call to prevent spurious Stopped callbacks.
- New helper `playCrouchTransition(entering: boolean)` (after `playMovementAnimation`): plays EnterCrouch or ExitCrouch for the current weapon set; sets `crouchTransitionPlaying = true`; connects Stopped callback to clear the flag and `currentAnimationName`; tracks the key via `currentAnimationName` so `stopCurrentMovementAnimation()` can stop the transition track on phase exit/destroy.
- `updateMovementAnimation()`: `crouchTransitionPlaying` guard added (early return while one-shot plays); `setName` moved before the isMoving check; idle path — when not moving, plays `setName .. "_Idle"` if the track is loaded, otherwise calls `stopCurrentMovementAnimation()`.
- Crouch input handler: `playCrouchTransition(movementState.isCrouching)` called after `applySpeed()`.
- Phase exit handler: `stopCrouchTransition()` called before `stopCurrentMovementAnimation()`.
- `destroy()`: `stopCrouchTransition()` called before `stopCurrentMovementAnimation()`.
- `loadMovementAnimations()` reset block: `stopCrouchTransition()` called before `table.clear(animationTracks)`.

**Updated (2026-05-20 — Stage 2I: Hold-to-crouch + crouch bottom-pose hold):**
- Crouch input changed from toggle (press C once to enter, press C again to exit) to hold-to-crouch: `InputBegan` (C held down) enters crouch and plays EnterCrouch; `InputEnded` (C released) exits crouch, clears the bottom-hold, and plays ExitCrouch. The old toggle handler is replaced.
- `holdCrouchBottomPose()` added: after EnterCrouch `Stopped` fires (if still crouching and no CrouchWalk), re-plays EnterCrouch at `AdjustSpeed(0)` parked at `Length - CROUCH_TRANSITION_MIN_HOLD_TIME` seconds. Character visually holds the crouched pose. `crouchHoldTrack` points to this track and is managed independently of `currentAnimationName` so `stopCurrentMovementAnimation()` cannot stop it.
- `clearCrouchBottomHold()` added: restores `AdjustSpeed` then calls `track:Stop(fade)`. Called on C-release, phase exit, and `destroy()`. On respawn (`loadMovementAnimations`), variables are cleared directly without calling Stop (old Animator may be destroyed).
- `updateMovementAnimation()` crouch branch added (returns early, before standing logic): moving + CrouchWalk ID exists → CrouchWalk; moving + no CrouchWalk → hold bottom pose; idle → hold bottom pose. Prevents standing idle from playing while crouching.
- `stopCrouchTransition()` renamed to `clearCrouchTransitionConnection()` — behavior narrowed to disconnect-only; callers now explicitly manage `crouchTransitionPlaying` after calling it.
- Optional CrouchWalk: `loadMovementAnimations()` conditionally loads `Unarmed_CrouchWalk` and `AR15_CrouchWalk` only if the corresponding IDs exist in Constants. No IDs added in Stage 2I.
- Four new Constants: `CROUCH_HOLD_KEY = Enum.KeyCode.C`, `CROUCH_HOLD_BOTTOM_POSE_ENABLED = true`, `CROUCH_TRANSITION_MIN_HOLD_TIME = 0.05`, `CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98`.
- MCP/Studio verification not yet performed.

**Updated (2026-05-20 — Stage 2J: Unarmed 8-directional crouch-walk animations):**
- Nine Unarmed CrouchWalk* IDs added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`: `CrouchWalk`, `CrouchWalkForward` (same asset as CrouchWalk — forward is the canonical clip), `CrouchWalkBackward`, `CrouchWalkLeft`, `CrouchWalkRight`, `CrouchWalkForwardLeft`, `CrouchWalkForwardRight`, `CrouchWalkBackwardLeft`, `CrouchWalkBackwardRight`.
- All nine tracks are pre-loaded at spawn in `loadMovementAnimations()`. Tracks are looped.
- New constant `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0`. All animation names beginning with `CrouchWalk` return this multiplier from `getAnimationSpeedMultiplier()`.
- `updateMovementAnimation()` crouch-moving branch rewritten for full 8-directional selection:
  - `customMouseLocked` OFF → CrouchWalkForward fallback (or CrouchWalk alias, or hold bottom pose).
  - `customMouseLocked` ON  → per-direction chains matching the walking direction system spec.
  - Non-Unarmed (AR15): generic `<Set>_CrouchWalk` if it exists, otherwise hold bottom pose.
  - Not moving while crouched: stop any CrouchWalk* track and hold the bottom pose.
- `playCrouchTransition()` EnterCrouch Stopped callback updated: when crouching + moving, starts CrouchWalkForward or CrouchWalk immediately to avoid a blank frame; `updateMovementAnimation()` refines direction on the next Heartbeat.
- AR15 and other sets: no CrouchWalk IDs — still falls back to bottom-pose hold. Deferred to a future armed-crouchwalk stage.
- MCP/Studio verification not yet performed.

**Updated (2026-05-20 — Stage 2K: third-person zoom limits + mouse-lock camera distance/offset):**
- `Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY` changed from `Enum.KeyCode.LeftAlt` to `Enum.KeyCode.LeftControl`. ContextActionService binding reads the constant at Start() so no other code change was needed. LeftAlt is now free for future use. LeftShift continues to be sprint-only.
- `applyThirdPersonZoomLimits()` added: sets `LocalPlayer.CameraMinZoomDistance = 4` and `CameraMaxZoomDistance = 14` using the new `THIRD_PERSON_MIN_ZOOM_DISTANCE`/`THIRD_PERSON_MAX_ZOOM_DISTANCE` constants. Called in `Start()` and `CharacterAdded`. Limits the default scroll range without locking to first-person.
- `applyCustomMouseLockCamera()` added: when mouse lock ON, pins `CameraMin = CameraMax = CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE (8)` and writes `Humanoid.CameraOffset = CUSTOM_MOUSE_LOCK_CAMERA_OFFSET (Vector3.new(1.75,0,0))`. CameraOffset fallback: if module-level `humanoid` is nil, looks up via `Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")` directly.
- `restoreNormalThirdPersonCamera()` added: when mouse lock OFF, restores `CameraMin=4`, `CameraMax=14`, and `CameraOffset = CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET (Vector3.zero)`. Same humanoid fallback applies.
- `cacheDefaultCameraSettings()` added: stores the initial `CameraMin/Max/CameraOffset` values on first call (without overwriting if already set). Not currently used for restore (restore always goes to the new Constants values, not the original Roblox defaults), but retained as a stable reference.
- `applyCustomMouseLock()` updated: calls `applyCustomMouseLockCamera()` when ON, `restoreNormalThirdPersonCamera()` when OFF. Also calls `restoreNormalThirdPersonCamera()` when `CUSTOM_MOUSE_LOCK_ENABLED` is false.
- `destroy()` updated: calls `restoreNormalThirdPersonCamera()` and clears the cache variables.
- Eight new Constants: `THIRD_PERSON_MIN_ZOOM_DISTANCE`, `THIRD_PERSON_MAX_ZOOM_DISTANCE`, `CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE`, `CUSTOM_MOUSE_LOCK_CAMERA_OFFSET`, `CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET`, `CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE`, `CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET`.
- MCP/Studio verified 2026-05-20: INIT zoom=4/14 offset=0,0,0 ✅ ON zoom=8/8 offset=1.75,0,0 ✅ OFF zoom=4/14 offset=0,0,0 ✅

**Updated (2026-05-20 — Stage 2L: Unarmed WalkForward/RunForward ID swap + sprint simplification):**
- `Unarmed.WalkForward` replaced: `97200177177374` → `71329939839948` (confirmed-good R6 no-gun walk forward).
- `Unarmed.RunForward` replaced: `81826691810907` → `79045069356901` (confirmed-good R6 no-gun run forward).
- Sprint selection in `updateMovementAnimation()` simplified: all sprint directions, all animation sets, mouse lock on or off now play `setName .. "_RunForward"`. The 14-line Unarmed+mouse-lock conditional (RunForwardLeft for ForwardLeft, RunForwardRight for ForwardRight) is removed.
- `RunForwardLeft` and `RunForwardRight` IDs remain in `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed` and are still loaded by `loadMovementAnimations()`, but are never selected at runtime. They are explicitly deferred.
- All animation speed multipliers preserved: walk 1.3×, strafe 1.4×, run 1.15×, idle 0.75×, crouch transition 0.9×, crouch walk 1.0×.
- Walking directional animations (WalkBackward, diagonals, strafes), crouch-walk animations, and idle behavior are unchanged.
- MCP/Studio verified 2026-05-20: sprint block code confirmed = `animName = setName .. "_RunForward"` only.

**Updated (2026-05-20 — Stage 2M: Unarmed walking animation ID replacement + WalkForwardAlt):**
- All 8 Unarmed walking IDs replaced with new confirmed-good R6 clips: `WalkForward`, `WalkLeft`, `WalkRight`, `WalkBackward`, `WalkBackwardLeft`, `WalkBackwardRight`, `WalkForwardLeft`, `WalkForwardRight`.
- New `WalkForwardAlt` ID added (`97919904114609`): loaded conditionally in `loadMovementAnimations()` if the ID exists; not selected by `updateMovementAnimation()` — no variation system built yet.
- `WalkForwardAlt` added to `getAnimationSpeedMultiplier()` so it gets `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER` (1.3×) when/if eventually selected.
- No selection-logic changes. Sprint (RunForward), crouch, idle, and AR15 behavior unchanged.
- All speed multipliers preserved: walk 1.3×, strafe 1.4×, run 1.15×, idle 0.75×, crouch transition 0.9×, crouch walk 1.0×.
- MCP/Studio verified 2026-05-20: all 9 new IDs present in Constants source, all 8 old IDs absent, WalkForwardAlt in toLoad and speed helper, sprint block still 1 code line.

**Updated (2026-05-21 — Stage 2O: Unarmed Falling looped + LandingMedium one-shot via Humanoid.StateChanged):**
- `Falling = rbxassetid://86705296926580` added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`: looped clip played while Humanoid is in Freefall. `Looped = true`. Only loaded for Unarmed set (AR15 has no Falling ID; the `animationTracks[key] ~= nil` guard in `onHumanoidStateChanged` skips it cleanly).
- `LandingMedium = rbxassetid://135915211175953` added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`: one-shot landing clip, `Looped = false`. Plays once on landing after at least `MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME` (0.25 s) of freefall. Skipped for crouch, crouch-transition, or short hops.
- Three new Constants: `MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER = 1.0`, `MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER = 1.0`, `MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME = 0.25`.
- New private state: `isFalling: boolean`, `airStartTime: number`, `isLandingPlaying: boolean`, `landingConn: RBXScriptConnection?`, `stateChangedConn: RBXScriptConnection?`.
- New helper `clearLandingConnection()`: disconnects `landingConn` and clears `isLandingPlaying`. Must be called before any external Stop on LandingMedium — mirrors `clearCrouchTransitionConnection()` / `clearCrouchWalkStart()` patterns.
- New handler `onHumanoidStateChanged(_old, new)`: phase-gated; ignores non-ACTIVE; on Freefall sets `isFalling = true`, records `airStartTime`, plays Falling; on Landed/Running stops Falling, checks air time, plays LandingMedium if all guards pass; on LandingMedium Stopped fires `clearLandingConnection()`.
- `loadMovementAnimations()`: disconnects `stateChangedConn` at top (before `table.clear`); resets `isFalling`, `airStartTime`, `clearLandingConnection()` on respawn; conditional loads for `Unarmed_Falling` and `Unarmed_LandingMedium`; `_LandingMedium$` added to the `Looped = false` pattern.
- `updateMovementAnimation()`: `if isFalling then return end` and `if isLandingPlaying then return end` guards added after `crouchTransitionPlaying` check — prevents Heartbeat from overriding Falling or LandingMedium.
- `setupCharacter()`: `stateChangedConn = hum.StateChanged:Connect(onHumanoidStateChanged)` added after `loadMovementAnimations()`. NOT stored in `_connections`.
- Phase-exit handler (non-ACTIVE branch): `isFalling = false; clearLandingConnection()` added so re-entry to ACTIVE starts clean.
- `destroy()`: `stateChangedConn` disconnected; `isFalling`, `airStartTime` reset; `clearLandingConnection()` called.
- `getAnimationSpeedMultiplier()`: `Falling` → `MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER`; `LandingMedium` → `MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER`.
- MCP/Studio verified 2026-05-21: Freefall → Falling track plays (looped, `L=true`); Landed → LandingMedium plays once (`L=false`); after LandingMedium Stopped callback fires, Idle resumes normally. Full trace logged.

**Updated (2026-05-20 — Stage 2N: CrouchIdle looped idle + CrouchWalkStart one-shot transition):**
- `CrouchIdle = rbxassetid://81947601552045` added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`: looped idle played while crouching + not moving. Replaces the EnterCrouch bottom-pose hold when the track is loaded. Falls back to `holdCrouchBottomPose()` when absent. `playMovementAnimation()` guard prevents restart every Heartbeat frame.
- `CrouchIdleAlt = rbxassetid://132053404406349` added: deferred alternate clip. Loaded conditionally, never selected — no variation system built yet.
- `CrouchWalk` and `CrouchWalkForward` IDs updated: `82558685099409` → `70428646705219` (new confirmed-good forward crouch-walk clip).
- `CrouchWalkStart = rbxassetid://129868628706658` added: one-shot idle-to-walk transition, `Looped = false`. Plays exactly once when the player first moves while crouched in each movement burst. `wasMovingWhileCrouching` flag tracks first-movement-burst; resets to false when the player stops while crouching.
- New private state: `crouchWalkStartPlaying: boolean`, `crouchWalkStartConn: RBXScriptConnection?`, `wasMovingWhileCrouching: boolean`.
- New helper `clearCrouchWalkStart()`: disconnects `crouchWalkStartConn` and clears `crouchWalkStartPlaying`. Must be called before any external Stop on the CrouchWalkStart track — mirrors `clearCrouchTransitionConnection()` pattern.
- `loadMovementAnimations()` Looped=false pattern extended: `_CrouchWalkStart$` added alongside `_EnterCrouch$` / `_ExitCrouch$`.
- `playCrouchTransition()` EnterCrouch Stopped callback: `wasMovingWhileCrouching = true` set when crouching + already moving at transition end, to skip CrouchWalkStart on the next Heartbeat.
- `getAnimationSpeedMultiplier()`: `CrouchIdle` and `CrouchIdleAlt` added to the `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER` (1.0×) branch.
- All directional CrouchWalk* selection logic, sprint, AR15, and non-crouch behavior unchanged.
- MCP/Studio verified 2026-05-20: all five Stage 2N IDs confirmed in Constants; old CrouchWalk ID (82558685099409) absent; CrouchIdle=looped=true, CrouchIdleAlt=looped=true, CrouchWalkStart=looped=false — all load without error on live character.

**Updated (2026-05-21 — Stage 2P: tactical sprint foundation — double-tap LeftShift):**
- `TacticalSprintForward1 = rbxassetid://135119369971434` added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`: looped clip played while tactical sprint is active. `Looped = true`. AR15 set has no tactical sprint IDs; the `animationTracks[key] ~= nil` guard in `updateMovementAnimation()` safely falls back to RunForward.
- `TacticalSprintForward2 = rbxassetid://110008857265859` added: alternate forward clip. Loaded conditionally, never selected — no variation system built yet.
- `TacticalSprintStop = rbxassetid://81946205769343` added: one-shot stop clip, `Looped = false`. Plays when tactical sprint ends (gated by `TACTICAL_SPRINT_STOP_ANIMATION_ENABLED = true`).
- Seven new Constants: `TACTICAL_SPRINT_ENABLED`, `TACTICAL_SPRINT_DOUBLE_TAP_WINDOW`, `TACTICAL_SPRINT_SPEED`, `TACTICAL_SPRINT_ACCELERATION_TIME`, `TACTICAL_SPRINT_MIN_FORWARD_DOT`, `TACTICAL_SPRINT_BLOCKS_GUN_USE`, `TACTICAL_SPRINT_STOP_ANIMATION_ENABLED`.
- New private state: `isTacticalSprinting: boolean`, `tacticalSprintStartTime: number`, `lastShiftPressTime: number`, `tacticalSprintStopConn: RBXScriptConnection?`. `movementState.isTacticalSprinting` mirrors the flag for external reads.
- New helper `clearTacticalSprintStopConnection()`: disconnect-only; placed after `clearLandingConnection()`.
- New function `stopTacticalSprint()`: defined AFTER `playMovementAnimation()` (Lua scoping requirement — it calls `stopCurrentMovementAnimation()` and `playMovementAnimation()`). Clears state, plays `TacticalSprintStop` one-shot, connects `Stopped` callback via `tacticalSprintStopConn`. No-op if not currently tactical sprinting.
- `applySpeed()`: tactical sprint ramp inserted as first priority check: `WalkSpeed = SPRINT_SPEED + (TACTICAL_SPRINT_SPEED - SPRINT_SPEED) * clamp(elapsed/ACCELERATION_TIME, 0, 1)`.
- `updateMovementAnimation()`: `tacticalSprintStopConn ~= nil` gate added (mirrors `landingConn` / `crouchWalkStartConn` pattern). Sprint branch: `if isTacticalSprinting` plays `TacticalSprintForward1` (fallback: `RunForward`) and returns.
- LeftShift `InputBegan`: double-tap window `(now - lastShiftPressTime) <= DOUBLE_TAP_WINDOW` within ACTIVE + `isMoving` + forward-dot ≥ `MIN_FORWARD_DOT` → sets `isTacticalSprinting`, captures `tacticalSprintStartTime`.
- LeftShift `InputEnded`: `stopTacticalSprint()` if active.
- Crouch `InputBegan`: `stopTacticalSprint()` before crouch state change.
- Heartbeat: `isMoving=false` or `fwdDot < MIN_FORWARD_DOT` → `stopTacticalSprint()` + `applySpeed()`.
- Phase-exit (non-ACTIVE): directly clears tactical sprint state WITHOUT calling `stopTacticalSprint()` (no visible effect during phase transitions).
- New public method `IsTacticalSprinting(): boolean` read by `GunController`.
- `GunController`: fire and reload handlers each call `MovementController.IsTacticalSprinting()` and return early when `TACTICAL_SPRINT_BLOCKS_GUN_USE = true`.
- MCP/Studio verified 2026-05-21: all 7 Constants correct; all 3 IDs load (Forward1 looped, Forward2 looped, Stop one-shot); WalkSpeed=30 observed during live double-tap test run; gun block guard verified programmatically (BLOCKED when isTac=true, FIRED when isTac=false); 4 stopTacticalSprint() call sites + tacticalSprintStopConn gate confirmed in running module source. Note: full live double-tap → animation → stop one-shot sequence was limited by MCP keyboard W-key not sustaining movement in Studio play mode; all static patterns, load-time state, and guard logic verified programmatically.

**Updated (2026-05-21 — Stage 2Q: fix crouch animation contamination):**
- Root cause 1 (frame-0 flash): `playCrouchTransition()` EnterCrouch Stopped callback called `holdCrouchBottomPose()` unconditionally when `!isMoving`. `holdCrouchBottomPose()` calls `track:Play(0)`, restarting EnterCrouch from frame 0 before seeking to near-end and freezing — one rendered frame shows the beginning of the old animation. **Fix:** Stopped callback now prefers `CrouchIdle` when `animationTracks[crouchIdleKey2] ~= nil`. If found: calls `stopCrouchTracksExcept(crouchIdleKey2)` + `playMovementAnimation(crouchIdleKey2)` directly. `holdCrouchBottomPose()` is only called when no CrouchIdle exists.
- Root cause 2 (resume flash): `clearCrouchBottomHold()` called `track:AdjustSpeed(SPEED_MULTIPLIER)` before `track:Stop(fade)`. The frozen-at-AdjustSpeed(0) EnterCrouch briefly resumed during the fade-out window. **Fix:** `clearCrouchBottomHold()` now calls `track:Stop(fade)` directly. The track fades out from the frozen frame; no resume.
- New helper `stopCrouchTracksExcept(allowedKey: string?)`: stops every `_Crouch`-keyed track in `animationTracks` except `allowedKey`; clears `currentAnimationName` if a stopped track was the current animation. Called before CrouchIdle, CrouchWalkStart, and CrouchWalk* transitions to prevent stale crouch blends from bleeding through.
- **Stage 2I risk updated:** "A one-frame visual at frame 0 may occur between Play and TimePosition assignment in `holdCrouchBottomPose()`" — this risk is now substantially mitigated. When `CrouchIdle` exists, `holdCrouchBottomPose()` is no longer called from the Stopped callback path. The `holdCrouchBottomPose()` path remains only as a fallback when CrouchIdle is absent.
- MCP/Studio verified 2026-05-21: module loaded clean; `track:AdjustSpeed` absent from `clearCrouchBottomHold` body (confirmed via `src:find`); `animationTracks[crouchIdleKey2]` guard and `"no hold-pose"` comment present in Stopped callback; all 4 `stopCrouchTracksExcept` call-sites confirmed. Known limitation: C key input via `user_keyboard_input` tool does not reach `InputBegan` in Studio play mode — full end-to-end animation flow requires manual Studio playtest (same limitation as Stage 2P W-key).

**Updated (2026-05-22 — Stage 2Q+: crouch blend contamination follow-up):**
- Root cause 1 (wrong pattern): `stopCrouchTracksExcept` used `key:find("_Crouch")`, which matched `Unarmed_CrouchIdle`, `Unarmed_CrouchWalk*`, etc., but silently skipped `Unarmed_EnterCrouch` and `Unarmed_ExitCrouch` (their keys end with `"Crouch"` after the verb prefix `"Enter"` / `"Exit"`, so the `"_Crouch"` substring is not present). These tracks could continue fading and blending through a new animation. **Fix:** pattern changed to `key:find("Crouch")` — matches all crouch-keyed tracks; zero false positives on any non-crouch animation name.
- Root cause 2 (fading track guard): `if track.IsPlaying` guard skipped tracks whose weight was still decaying after a prior `Stop(fadeTime)` call (`IsPlaying` becomes `false` immediately after `Stop` even while weight fades). **Fix:** guard removed; `Stop(0)` used unconditionally — immediately zeroes weight on any matching track regardless of state.
- Root cause 3 (missing pre-Play call): `playCrouchTransition` never called `stopCrouchTracksExcept` before `track:Play(...)`. Any fading CrouchIdle, CrouchWalk, or previous transition track blended through the new clip's fade-in window (most visible during rapid C-release → C-press cycles where CrouchIdle was stopped with FADE_TIME, then EnterCrouch started immediately, and both contributed weight). **Fix:** `stopCrouchTracksExcept(key)` added immediately before `crouchTransitionPlaying = true` and `track:Play(...)` in `playCrouchTransition`.
- Additional: `stopCrouchTracksExcept(fwdKey)` / `stopCrouchTracksExcept(aliasKey)` added in the EnterCrouch Stopped callback moving branch (Stage 2Q only had the not-moving branch). `stopCrouchTracksExcept(nil)` added in phase exit handler.
- `currentAnimationName:find("Crouch")` guard in the helper also updated from `"_Crouch"` to `"Crouch"`.
- Total call sites: 8 (4 from Stage 2Q: crouchIdleKey2 / crouchIdleKey / startKey / targetCrouchKey; 4 new: key in playCrouchTransition / fwdKey / aliasKey / nil in phase exit).
- **Stage 2Q risk updated:** The "EnterCrouch should not remain blended once CrouchIdle or CrouchWalk starts" risk is now resolved. The pattern fix ensures EnterCrouch is always in the candidate set. The pre-Play call ensures it is cut before the new clip begins.
- MCP/Studio verified 2026-05-22: all 7 pattern checks passed in running module; pattern smoke test confirmed `Unarmed_EnterCrouch`, `Unarmed_ExitCrouch`, `AR15_EnterCrouch`, `AR15_ExitCrouch` newly matched; 6 non-crouch keys correctly skipped; module loaded clean with no Output errors. Known limitation: full end-to-end visual requires manual Studio playtest (C key does not reach `InputBegan` via MCP).

**Updated (2026-05-21 — Stage 2R: directional sprint animation selection):**
- `getSprintAnimationName(animSetName: string, directionName: string): string` added: private helper that resolves which sprint animation suffix to play. Returns `"RunForward"` when `customMouseLocked == false` (all directions). Returns `"RunForwardLeft"` when `customMouseLocked == true` and `directionName == "ForwardLeft"` and `animationTracks[animSetName .. "_RunForwardLeft"] ~= nil`. Returns `"RunForwardRight"` analogously for `ForwardRight`. All other directions → `"RunForward"`. On missing directional track, fires `Logger.warn` exactly once per track key per session via `missedSprintAnimWarned` table.
- `missedSprintAnimWarned: {[string]: boolean}` table: module-level, never reset on respawn — warns once per module lifetime per missing key.
- `lastSprintAnimName: string` debug guard added: `Logger.debug` fires only when the resolved sprint animation key changes (not every frame). Reset to `""` on each `loadMovementAnimations()` and in `destroy()`.
- `updateMovementAnimation()` normal sprint block updated: single `animName = setName .. "_RunForward"` replaced with `animName = setName .. "_" .. getSprintAnimationName(setName, movementState.directionName)` plus `lastSprintAnimName` change-log guard.
- `RunForwardLeft` and `RunForwardRight` IDs (already in Constants since Stage 2G, already loaded into `animationTracks` since Stage 2G, already in `getAnimationSpeedMultiplier()` at 1.15×) are now actively selected by `updateMovementAnimation()` when the conditions are met. No new IDs. No Constants changes. No speed multiplier changes.
- No camera writes. No `camera.CFrame`, `CameraOffset`, `FieldOfView`, `CameraType` changes. No new remotes. No server changes. No GunController changes. Tactical sprint branch unchanged.
- MCP/Studio verified 2026-05-21: all code patterns confirmed via `src:find(str, 1, true)` plain-text search; `customMouseLocked` toggle confirmed via live module call; disk file length 149,222 bytes confirmed. Rojo stale-intermediate issue resolved via `mcp__Roblox_Studio__multi_edit`. Known limitation: W and C key inputs via MCP `user_keyboard_input` do not reach `InputBegan` in Studio play mode — full end-to-end directional sprint flow requires manual Studio playtest (same limitation as Stages 2P/2Q).

**Updated (2026-05-21 — Stage 3A: sprint FOV stretch + landing animation classification):**
- `tweenCameraFov(target, duration)` and `updateSprintFov()` added as private helpers. Inserted BEFORE the Stage 2P `stopTacticalSprint` section to satisfy Luau `--!strict` forward-reference rules (`stopTacticalSprint` calls `updateSprintFov`; both must be defined before `stopTacticalSprint`).
- Sprint FOV: `TweenService:Create(camera, TweenInfo.new(duration, Quad, Out), {FieldOfView=target})`. Normal sprint → 78, tactical sprint → 84, all else → 70. `targetFov` dedup guard prevents per-frame tween restarts from Heartbeat. FOV restored on sprint end, tactical sprint end, phase exit (non-ACTIVE), CharacterAdded (direct set), and `destroy()` (cancel + direct set).
- Landing classification: three tiers (LandingLight/Medium/Heavy) replace the single LandingMedium from Stage 2O. `wasJumpingThisAirborne` and `jumpedWhileSprinting` track jump context. `airborneStartY` records the Y position at jump/freefall start for drop-distance calculation. `getLandingAnimationName()` implements classification; `playLandingAnimation()` uses `MOVEMENT_LANDING_ANIMATION_FADE_TIME` (0.08s) for a snappier hit. New IDs: `Unarmed.LandingLight = rbxassetid://135438895968665`, `Unarmed.LandingHeavy = rbxassetid://72796290236543`.
- `onHumanoidStateChanged` rewritten: Jumping state now captured (previously only Freefall was handled). Freefall records `airborneStartY` only when `wasJumpingThisAirborne=false` (walk-off drops). Landed calls `getLandingAnimationName(dropDist, airTime, wasJump, sprintJump)` and routes to `playLandingAnimation`.
- Three new speed multiplier constants: `MOVEMENT_LANDING_LIGHT_SPEED_MULTIPLIER=1.15`, `MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER=1.0`, `MOVEMENT_LANDING_HEAVY_SPEED_MULTIPLIER=0.9`.
- No fall damage. No stamina. No slide/vault/prone. No camera.CFrame writes. No CameraOffset changes. No new remotes. No server changes.
- MCP/Studio verified 2026-05-21: all 6 FOV constants live in Studio; camera FOV starts at 70.0; TweenService round-trip 70→78→70 confirmed; all 7 landing classifier cases verified inline (NormalJump→Light, SprintJump→Medium, HighJump≥18→Heavy, SmallDrop→Light, MedDrop→Medium, HeavyDrop→Heavy, TinyDrop<0.25s→nil). No runtime errors in Output panel. Known limitation: full end-to-end FOV tween during live sprint and landing animations during actual jumps require manual Studio playtest — MCP keyboard input does not reach `InputBegan` handlers (same gameProcessed limitation as Stages 2P/2Q/2R).

**Updated (2026-05-21 — Stage 3B: landing movement lock + sprint-jump momentum carry):**
- `isLandingMovementLocked` state variable added. When `true`, `applySpeed()` immediately sets `WalkSpeed = 0` and returns — before tactical sprint ramp, before all other speed logic.
- `landingLockToken` (number) added. Incremented on every `clearLandingMovementLock()` call. Each `task.delay` fallback closure captures the token at dispatch time and no-ops if the token has changed (stale-unlock prevention for respawn, phase-exit, and rapid re-landing).
- `landingMomentumActive`, `landingMomentumAttachment: Attachment?`, `landingMomentumVelocity: LinearVelocity?` added for sprint-jump momentum carry.
- `sprintJumpMomentumDirection: Vector3?` added — captured in the Jumping state handler; consumed and cleared at landing.
- Six new private helpers inserted before `loadMovementAnimations()` to satisfy Luau `--!strict` forward-reference rules:
  - `getFlatVector(vector)` — flatten Y, return unit or nil.
  - `captureJumpMomentumDirection()` — reads `AssemblyLinearVelocity` → `MoveDirection` → `CFrame.LookVector` at jump entry.
  - `clearLandingMomentum()` — destroys `LinearVelocity` + `Attachment`, clears flag.
  - `clearLandingMovementLock()` — increments token, sets flag false, calls `clearLandingMomentum()`, calls `applySpeed()`.
  - `startLandingMovementLock(duration)` — sets lock, suppresses sprint flags, calls `applySpeed()`, schedules fallback timer.
  - `startSprintJumpLandingMomentum(direction)` — creates `Attachment` + `LinearVelocity` on `HumanoidRootPart`.
- `playLandingAnimation` Stopped callback updated: after `clearLandingConnection()`, calls `clearLandingMovementLock()` if `isLandingMovementLocked and not landingMomentumActive` (early-unlock, not called while momentum carry is still active).
- `onHumanoidStateChanged` Jumping branch updated: captures `captureJumpMomentumDirection()` when `jumpedWhileSprinting`, clears to nil otherwise.
- `onHumanoidStateChanged` Landed branch updated: after `playLandingAnimation(animName)`, routes to `startLandingMovementLock` (with optional `startSprintJumpLandingMomentum`) per tier.
- Phase-exit handler, `loadMovementAnimations()`, and `destroy()` all call `clearLandingMovementLock()` + reset `sprintJumpMomentumDirection`.
- Ten new Constants (see "New constants" in CHANGELOG Stage 3B entry).
- MCP/Studio verified 2026-05-21: LandingLight (6 studs) — min WalkSpeed 14.0 (no lock) ✅; LandingMedium (14 studs) — locked ~0.37s ✅; LandingHeavy (22 studs) — locked exactly 0.65s ✅; no LinearVelocity on non-sprint-jump landings ✅.

**Remaining gaps (updated Stage 3B):**
- Crouch walk animation — implemented for Unarmed (9 directional IDs, Stage 2J). AR15/gun-equipped CrouchWalk IDs still deferred.
- Sprint-jump momentum carry — LinearVelocity carry implemented for LandingMedium sprint-jump path (Stage 3B). AR15 set and LandingHeavy paths use only the lock (no carry). A dedicated heavy-landing carry is deferred.
- Directional sprint animations — ForwardLeft and ForwardRight now play RunForwardLeft/RunForwardRight when customMouseLocked is ON (Stage 2R). Remaining directions (Left, Right, Backward, BackwardLeft, BackwardRight) still use RunForward in all cases. AR15 sprinting uses AR15 RunForward in all directions.
- AR15 run diagonal animations — AR15 set sprinting uses RunForward for all directions; no AR15-specific run diagonals.
- AR15 backward/diagonal walk animations — AR15 set only has WalkForward and RunForward; backward and diagonal walk directions fall back to WalkForward/strafe grouping.
- AR15 CrouchIdle / CrouchWalkStart — AR15 set has no CrouchIdle or CrouchWalkStart tracks; falls back to bottom-pose hold while crouched+still. Deferred to a future armed-crouch stage.
- AR15 Falling / LandingLight / LandingMedium / LandingHeavy — AR15 set has no Falling or landing IDs; all are safely skipped by `animationTracks[key] ~= nil` guards. Deferred.
- AR15 tactical sprint — AR15 set has no TacticalSprint* IDs; tactical sprint safely falls back to RunForward for the animation, but the forward clip does not match the armed aesthetic. Deferred to a future armed-tactical-sprint stage.
- TacticalSprintForward2 variation system — `TacticalSprintForward2` is loaded but never selected. A safe alternation system (cooldown, random pick, or distance-based trigger) is needed before it can be used.
- Jump animations — suppressed along with locomotion when Animate is disabled. Custom replacement needed in a future movement stage.
- Climb animations — suppressed by Animate disable. Custom replacement needed.
- Lower-body / upper-body animation split — not implemented; the full body plays the movement animation.
- Reload, fire, ADS, and sprint-hold weapon animations — deferred to a weapon-anim stage.
- True server-owned equipment state — equippedWeaponName is presentation-only; see DEBT-050.
- Full custom camera controller — `SetCustomMouseLocked` writes `UserInputService.MouseBehavior = LockCenter`. A full custom camera controller (Scriptable CameraType, raw mouse-delta yaw/pitch) is not built.
- First-person integration — when `FORCE_FIRST_PERSON = true` (ViewModelController), Stage 2K zoom limits and mouse-lock distance only apply while Classic CameraMode is active. Verify when first-person is enabled (DEBT-048).
- WalkForwardAlt / CrouchIdleAlt variation system — both alternate clips are loaded but never selected. A safe alternation system (cooldown, random pick, or distance-based trigger) is needed before they can be used.

**Remaining risks:**
- If custom animation IDs are private or not owned by the game's creator / group, Roblox may silently refuse to load them. `Logger.warn()` fires for any empty assetId; a failed `LoadAnimation()` call will produce an output error. Confirm animation ownership before shipping.
- If neither `RigType == R6` nor the structural body-part check passes, R6 animations are skipped and `getRigDebugSummary()` is logged. Stage 1 speed/direction logic remains active. Verify `StarterPlayer.CharacterRigType` in Studio after each `rojo serve` (DEBT-049).
- If the structural fallback fires (R6 parts present but `RigType` mismatch), a one-time warn is emitted. This is expected in some Studio sessions — the real fix is DEBT-049 verification.
- Disabling Animate removes the default idle, jump, fall, and climb animations. Until custom clips are added, the character will T-pose during these states.
- `equippedWeaponName` is presentation-only. True armed/unarmed state must later come from a server-owned equipment/loadout system. `SetEquippedWeaponName` must eventually be called by a real EquipmentController or weapon equip system (see DEBT-050).
- Sprint Left, Right, Backward, BackwardLeft, BackwardRight still use RunForward in all cases (Stage 2R only adds ForwardLeft → RunForwardLeft and ForwardRight → RunForwardRight when mouse lock ON). Dedicated run-left, run-right, and run-backward IDs do not exist yet. Walking backward/diagonal uses WalkForward fallback when mouse lock is OFF.
- Sprint FOV: `SPRINT_FOV_ENABLED` master switch is `true`. If a future stage adds a separate camera system that also writes FieldOfView, a tween conflict may occur. `currentFovTween:Cancel()` is always called before starting a new tween; ensure any future camera system also cancels this tween on takeover.
- If `DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = false`, Animate keeps running and may override or blend with custom locomotion tracks. This constant must stay `true` for custom animations to take effect.
- Animation speed multipliers (walk 1.3×, strafe 1.4×, run 1.15×, idle 0.75×, crouch transition 0.9×). Walk was changed from 1.7→1.3 in Stage 2G; idle and crouch transition added in Stage 2H. These values may still need tuning after Studio verification — if the clip cadence feels too fast or too slow, adjust only the Constants without touching controller logic.
- **Stage 2H/2I new risk:** If `playCrouchTransition` is called while `crouchTransitionPlaying` is true (rapid press of C during an in-flight one-shot), `clearCrouchTransitionConnection()` disconnects the Stopped conn and then plays a fresh clip. The previous clip fades out via `stopCurrentMovementAnimation()`. This is correct behavior but may feel abrupt at low playback speeds. Tune `MOVEMENT_ANIMATION_FADE_TIME` if the interruption is visually jarring. (Note: `stopCrouchTransition()` was renamed to `clearCrouchTransitionConnection()` in Stage 2I.)
- **Stage 2H risk — resolved in Stage 2I:** Idle playing while crouched: The `updateMovementAnimation()` crouch branch added in Stage 2I returns early before standing locomotion logic runs, so standing Idle no longer plays while `isCrouching == true`. Crouched idle state now holds the EnterCrouch bottom pose instead.
- **Stage 2H/2I new risk:** `playCrouchTransition` uses `currentAnimationName = key` to let `stopCurrentMovementAnimation()` stop the transition track externally. If any code path calls `stopCurrentMovementAnimation()` while `crouchTransitionPlaying` is true (e.g. a future system that force-stops all animations), the Stopped callback will fire after the disconnect — but since `clearCrouchTransitionConnection()` must be called first, the callback guard (`if currentAnimationName == key`) prevents double-clearing. Verify that all external stop paths call `clearCrouchTransitionConnection()` + set `crouchTransitionPlaying = false` before `stopCurrentMovementAnimation()`.
- **Stage 2J new risk:** `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0` is the default and has not been tuned in Studio. If the clip cadence feels too slow or too fast relative to actual movement speed at `CROUCH_SPEED = 10`, adjust only the constant without touching controller logic.
- **Stage 2J new risk:** When `customMouseLocked` is OFF, all crouched movement directions use CrouchWalkForward. If the player moves backward while crouching without mouse lock, the forward crouch-walk clip plays while the character moves backward — the animation direction will not match movement direction. This is intentional (matches the walk system's mouse-lock behavior) and is acceptable until customMouseLocked is the default or the user opts in via LeftAlt.
- **Stage 2J new risk:** The `playCrouchTransition()` EnterCrouch Stopped callback starts CrouchWalkForward immediately if the player is moving. On the next Heartbeat, `updateMovementAnimation()` refines to the correct directional animation. If `MOVEMENT_ANIMATION_FADE_TIME` is large (> 0.2 s), the crossfade from CrouchWalkForward to the directional clip (e.g. CrouchWalkBackward) may be visible. Tune `MOVEMENT_ANIMATION_FADE_TIME` if this transition looks abrupt.
- **Stage 2J new risk:** AR15 CrouchWalk IDs are missing — armed crouched movement still uses the EnterCrouch bottom-pose hold. This is acceptable for the current prototype (one weapon) but will need AR15 CrouchWalk* IDs for a polished armed-crouching experience.
- **Stage 2I new risk:** `AdjustSpeed(0)` freezes the AnimationTrack at the current TimePosition. If `track.Length` is 0 (animation not yet fully loaded when `holdCrouchBottomPose()` fires), the fallback `CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98` is used. If the actual clip is shorter than 0.98 s, the pose will snap to the wrong frame. Verify `track.Length > 0` after `LoadAnimation` completes in Studio — check Output for the warn-once guard if the fallback fires.
- **Stage 2I new risk:** Setting `TimePosition` after `AdjustSpeed(0)` relies on the track being in the Playing state. If `track.IsPlaying` is false when `holdCrouchBottomPose()` is called, `track:Play(0)` is called first to enter the Playing state before the position/speed writes. A one-frame visual at frame 0 may occur between Play and TimePosition assignment on some Roblox versions. If a visible snap is seen in Studio on crouch entry, wrap the TimePosition + AdjustSpeed writes in a `task.defer()`.
- **Stage 2I new risk:** `crouchHoldTrack` is independent of `currentAnimationName` by design — `stopCurrentMovementAnimation()` will NOT stop the held EnterCrouch. Any system that needs to force-clear all animations must also call `clearCrouchBottomHold()` explicitly.
- `StarterPlayer.EnableMouseLockOption = false` is now set in `default.project.json` and `LocalPlayer.DevEnableMouseLock = false` is set on Start and CharacterAdded. If CoreScripts still find a path to re-enable Shift Lock, the `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME` Heartbeat write provides a second line of defence. Verify in Studio that LeftShift never activates the Roblox native mouse-lock icon.
- `ContextActionService:BindActionAtPriority` at priority 3000 is the new LeftAlt binding. If a future CoreScript update changes input priority behavior, the toggle lag could return. Verify in Studio that LeftAlt toggles take effect immediately (no perceptible 1-frame delay).
- `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true` re-writes `MouseBehavior = LockCenter` every Heartbeat while `customMouseLocked` is true. If an expensive UI transition reads `MouseBehavior` to detect lock state (rather than calling `IsCustomMouseLocked()`), it may be confused by the aggressive reapply. Verify in Studio that the UI does not flicker or misread lock state during phase transitions.
- Phase-exit no longer resets `customMouseLocked`. If `LOBBY` or `RESULTS` phases are expected to release the cursor lock for UI interaction (e.g. a settings menu or lobby screen), the reapply-every-frame will keep the cursor locked even in those phases. Address by either resetting `customMouseLocked` on specific non-ACTIVE phases when UI modals are added, or by pausing the reapply when a modal is open.
- **Stage 2N new risk:** `CrouchWalkStart` one-shot relies on `wasMovingWhileCrouching` being reset to `false` every time the player stops while crouched. If `updateMovementAnimation()` is skipped for any reason (e.g. `crouchTransitionPlaying` is true for an unexpectedly long time) while the player is not moving, `wasMovingWhileCrouching` will not reset and the next movement burst will skip CrouchWalkStart. Verify in Studio that rapid hold/release of C does not leave `wasMovingWhileCrouching` stuck `true`.
- **Stage 2Q+ note:** `Stop(0)` is now used in `stopCrouchTracksExcept` instead of `Stop(FADE_TIME)`. This means the outgoing crouch track is cut immediately (no blend window) before the new clip starts. The new clip still fades in over `MOVEMENT_ANIMATION_FADE_TIME`. This produces an instant-cut-then-fade-in feel for crouch transitions rather than a simultaneous crossfade. If a smoother blend between crouch states is desired in the future, consider a two-phase approach: `Stop(FADE_TIME)` for the `currentAnimationName` track (handled by `playMovementAnimation`) and `Stop(0)` only for stale non-tracked crouch tracks.
- **Stage 2N new risk:** The `clearCrouchWalkStart()` call at the top of the crouch-moving branch (`if not wasMovingWhileCrouching`) is called before `stopCurrentMovementAnimation()`. If `crouchWalkStartConn` is nil (no active one-shot), this is a no-op. If it is non-nil (pathological case: two movement bursts back-to-back faster than a Stopped event fires), the second call disconnects the first connection safely. Verify that rapid re-triggering of movement while crouched does not leave a dangling connection.
- **Stage 2N new risk:** `CrouchIdleAlt` is loaded but never selected. If the alternate variation system is later added without removing this risk entry, the unused-load cost (network, memory) will silently remain. Track this until the variation system is built or the ID is removed.
- **Stage 2K new risk — toggle key change:** LeftControl is now the mouse-lock toggle (was LeftAlt). LeftControl is also used by some OS-level and Roblox CoreScript shortcuts. Verify in Studio (and on each target platform) that LeftControl does not conflict with any OS shortcut or Roblox default binding. If a conflict is found, change `CUSTOM_MOUSE_LOCK_TOGGLE_KEY` to another key without touching any other code.
- **Stage 2K new risk — CameraOffset and character size:** `CUSTOM_MOUSE_LOCK_CAMERA_OFFSET = Vector3.new(1.75, 0, 0)` is tuned for the default R6 rig dimensions. If the character is scaled (accessories, hats, or future character resizing), the right-shoulder offset may drift visually (too far right or too close to the camera). No fix needed now; revisit when character scaling is added.
- **Stage 2K new risk — CameraOffset fallback reliability:** `applyCustomMouseLockCamera()` and `restoreNormalThirdPersonCamera()` fall back to `Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")` when the module-level `humanoid` is nil. If `Character` itself is nil (player hasn't spawned yet or is in the death/respawn gap), the fallback returns nil and the CameraOffset write is silently skipped. The zoom distance write still succeeds (it targets `LocalPlayer`, not the humanoid). The CameraOffset will be applied correctly on the next CharacterAdded callback. This is acceptable — the camera distance still changes on toggle; only the shoulder offset is temporarily missed.
- **Stage 2O new risk — LandingMedium while crouching:** When the player lands while crouched, `movementState.isCrouching == true` skips LandingMedium. `isFalling` is cleared and the crouch branch resumes on the next Heartbeat (CrouchIdle or bottom-pose hold). This is intentional, but if a distinct crouched-landing animation is ever wanted for the Unarmed set, a separate `CrouchLandingMedium` ID and branch will need to be added without disrupting the existing standing-landing path.
- **Stage 2O new risk — Running fires on ground contact:** `onHumanoidStateChanged` treats `Enum.HumanoidStateType.Running` as a landing signal (alongside `Landed`) because Roblox's state machine transitions directly to Running when a moving character lands. If `Running` fires for reasons unrelated to landing (e.g. a very brief airborne frame that does not set `isFalling`), the `if not isFalling then return end` guard prevents false positives. Verify in Studio that no spurious Running handler calls produce unwanted animation interruptions during normal ground locomotion.
- **Stage 2O new risk — short jumps skip LandingMedium:** `MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME = 0.25` s. A jump that doesn't clear 0.25 s of Freefall (step off a curb, walk off a very short ledge) will skip LandingMedium. This is intentional, but if the threshold feels too aggressive in Studio (landing animation never plays, or always plays), adjust only the constant.
- **Stage 2O new risk — `stateChangedConn` is NOT in `_connections`:** The connection is per-character and manually managed (disconnected in `loadMovementAnimations()` top block and in `destroy()`). If any future code path calls `destroy()` before `setupCharacter()` runs on a new character, `stateChangedConn` may be nil (no-op disconnect). This is safe but must be kept in mind when extending the lifecycle flow.
- **Stage 2K new risk — zoom distance tuning:** `THIRD_PERSON_MIN_ZOOM_DISTANCE = 4` and `THIRD_PERSON_MAX_ZOOM_DISTANCE = 14` and `CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE = 8` are initial values and have not been evaluated with multiple level sizes or field-of-view settings. Adjust only these three Constants if the camera feels too close or too far in Studio — no controller logic changes needed.
- **Stage 2M new risk — WalkForwardAlt unused track:** `Unarmed_WalkForwardAlt` is loaded into `animationTracks` at spawn and occupies an `AnimationTrack` slot. It is never selected by `updateMovementAnimation()`. If the variation system is never built, this track will keep loading unnecessarily. Either implement the alternation system or remove the ID and load entry to reclaim the slot.
- **Stage 2P new risk — TacticalSprintForward2 unused track:** `Unarmed_TacticalSprintForward2` is loaded but never selected (same pattern as WalkForwardAlt). Implement a variation system or remove the ID to reclaim the slot if tactical sprint variation is never added.
- **Stage 2P new risk — AR15 tactical sprint falls back to RunForward:** When `equippedWeaponName == "AR15"` and tactical sprint is active, `updateMovementAnimation()` plays `AR15_RunForward` (the `animationTracks[tsKey] ~= nil` guard fails for AR15). This is intentional for now but means the armed sprint forward clip plays during tactical sprint rather than a dedicated armed tactical sprint animation. Add AR15 TacticalSprint* IDs when an armed tactical sprint aesthetic is wanted.
- **Stage 2P new risk — stopTacticalSprint() must stay after playMovementAnimation():** `stopTacticalSprint()` calls `stopCurrentMovementAnimation()` and `playMovementAnimation()`. In Lua, a `local function` is only visible from its declaration line onward. If any future refactor moves `stopTacticalSprint()` above `playMovementAnimation()`, the calls will resolve to nil and the stop animation will silently fail. The placement is intentional and must be preserved.
- **Stage 2P new risk — double-tap window race with hold:** If the player presses and releases Shift very quickly twice (tapping, not holding), the double-tap fires correctly. If the player holds Shift from the first press through the second press (typical sprint-then-double-tap), `lastShiftPressTime` is set on the first `InputBegan` and the second `InputBegan` fires within the window — this is the intended trigger pattern. If a future stage adds any InputBegan processing that fires LeftShift repeatedly (e.g. repeat-key simulation), verify that `lastShiftPressTime` is not being set by synthetic input.
- **Stage 2P new risk — MCP keyboard W-key limitation:** Full live MCP testing of the double-tap → animation → TacticalSprintStop sequence was not possible because the MCP `user_keyboard_input` tool did not sustain W key movement in Studio play mode during this session. WalkSpeed=30 was observed in an earlier test (confirming activation), and all guards/state were verified programmatically. A manual Studio playtest should be run to confirm the full flow (double-tap → TacticalSprintForward1 plays → TacticalSprintStop fires on Shift release) before shipping.
- **Stage 2Q new risk — stopCrouchTracksExcept iterates all animationTracks:** The helper uses `pairs(animationTracks)` which includes all sets (Unarmed + AR15 + future sets). Any track whose key contains `_Crouch` will be stopped. If a future set has a `_Crouch`-keyed track that should NOT be stopped during a different set's transition (cross-set blending), `stopCrouchTracksExcept` would incorrectly stop it. At present there is only one active set at a time (Unarmed), so this is safe. If multi-set blending is ever added, scope the iteration to `setName` only.
- **Stage 2Q new risk — holdCrouchBottomPose() still used as fallback:** When `CrouchIdle` is absent (AR15 set, or any set where the ID is not loaded), `holdCrouchBottomPose()` is still called from the Stopped callback. The frame-0 flash risk still exists for those sets. AR15 set has no CrouchIdle — if an AR15 CrouchIdle is added in a future stage, verify the Stopped callback path picks it up correctly and no holdCrouchBottomPose is called.
- **Stage 2Q new risk — MCP keyboard C-key limitation:** Full end-to-end crouch animation contamination fix was not visually confirmed in Studio play mode. The C key input via MCP `user_keyboard_input` tool did not reach the `InputBegan` handler (same limitation as Stage 2P W-key). All source-level and load-time checks passed. A manual Studio playtest should be run to visually confirm that (1) no frame-0 flash occurs on EnterCrouch finish, (2) no resume flash occurs when CrouchIdle starts after a hold-pose, and (3) CrouchIdle plays cleanly without any old animation blending through.
- **Stage 2L new risk — sprint direction mismatch (partially resolved in Stage 2R):** Stage 2L simplified all sprint directions to RunForward. Stage 2R re-enables ForwardLeft → RunForwardLeft and ForwardRight → RunForwardRight when `customMouseLocked == true`. Sprinting Left, Right, Backward, BackwardLeft, and BackwardRight still play RunForward regardless of direction. No dedicated run-left, run-right, or run-backward IDs exist. If additional directional run clips are confirmed and added in a future stage, extend `getSprintAnimationName()` to handle those directions without touching any other sprint logic.
- **Stage 2R new risk — body-facing during diagonal sprint:** With `customMouseLocked == true`, the character faces the camera yaw (Stage 2E) while the sprint animation plays RunForwardLeft or RunForwardRight. The animation visually aligns with ForwardLeft/ForwardRight relative to the body, which is rotated to face the camera. This interaction is intentional but has not been verified in live Studio play. If the diagonal sprint animation looks misaligned relative to actual character movement in Studio, consider whether a body-rotation compensation is needed (without touching camera.CFrame).
- **Stage 2R new risk — missedSprintAnimWarned never cleared:** The warn-once table is module-level and not reset on respawn. If a track fails to load for one character and then loads correctly on respawn (e.g. slow asset load on first spawn), the warn fires once but no correction is logged on the second spawn. This is acceptable — warns are informational and the fallback to RunForward is safe.
- **Stage 2R new risk — MCP keyboard W-key limitation:** Full live MCP testing of directional sprint animation selection (ForwardLeft → RunForwardLeft, ForwardRight → RunForwardRight) was not possible because MCP `user_keyboard_input` W and C keys do not reach `InputBegan` in Studio play mode. All patterns verified programmatically via source scan. Manual Studio playtest required to confirm (1) RunForwardLeft/RunForwardRight plays visually during diagonal sprint with mouse lock ON, (2) RunForward plays when mouse lock is OFF, (3) no animation blending artifacts at sprint-direction transitions.
- **Stage 2K new risk — character-facing jitter while mouse-locked:** With `AutoRotate = false` (Stage 2E) and `CameraOffset = Vector3.new(1.75, 0, 0)` (Stage 2K), the character's HumanoidRootPart is written every Heartbeat to face the camera yaw (Stage 2E). The combined effect is a right-shoulder over-the-shoulder view where the character continuously tracks the camera. If frame-rate drops cause Heartbeat timing jitter, the character facing may stutter visibly. If this is noticeable in Studio, consider clamping yaw changes per frame or moving the facing write to RunService.RenderStepped (smoother but client-only).
- **Stage 2E new risk:** `HumanoidRootPart.CFrame` is written every Heartbeat while mouse lock is active. Roblox's physics engine normally controls `HumanoidRootPart` position; writing CFrame while the character is moving may cause micro-jitter visible at low frame rates. If jitter is observed in Studio, consider applying the yaw rotation only when `MoveDirection.Magnitude` exceeds the deadzone (character is moving) and reverting to `AutoRotate = true` while standing still.
- **Stage 2E new risk:** `getCameraFlatLookVector()` returns nil and skips rotation when the camera is looking near-straight-up or near-straight-down. This is unlikely in normal FPS play but will produce a frozen character-facing during extreme camera angles. Acceptable for Stage 2E; a future camera stage may add a separate yaw-memory for this edge case.
- **Stage 2E new risk:** `currentRootPart` is cached in `setupCharacter()` via `WaitForChild`. If the HumanoidRootPart is temporarily removed and re-added (e.g. by a ragdoll system that swaps the root), the cached reference will point to the old part. The cached reference is only refreshed on the next `CharacterAdded`. Verify in Studio that ragdoll (via `RagdollService`) does not swap the HumanoidRootPart after `setupCharacter()` runs.
- Input/mouse-lock and character-facing behavior needs Studio verification — particularly: LeftAlt toggles cursor lock and character facing simultaneously, character visibly rotates to face camera on LeftAlt toggle, character does not jitter while moving with mouse lock on, AutoRotate is restored on toggle-off and on phase exit, facing resumes on ACTIVE re-entry when toggle was left on, respawn resets both cursor lock and AutoRotate correctly.

- **Stage 3B new risk — LinearVelocity vs. physics systems:** `startSprintJumpLandingMomentum()` creates a `LinearVelocity` with `RelativeTo = World` and `MaxForce = 60000`. If another physics constraint (e.g. a future conveyor, wind zone, or ragdoll joint) is applied to the same `HumanoidRootPart` simultaneously, the constraints will fight each other. `clearLandingMomentum()` always destroys the constraint after `SPRINT_JUMP_LANDING_MOMENTUM_DURATION` (0.22s) — the window is short enough that conflicts are unlikely in normal play. If a physics system is added in the future, verify that it checks for and yields to active `LinearVelocity` constraints.
- **Stage 3B new risk — WalkSpeed stuck at 0 in edge cases:** If a bug causes `clearLandingMovementLock()` to never be called (e.g. an unhandled exception in the token-delay closure), the player will be stuck with `WalkSpeed = 0` until respawn. The token guard, early-unlock from animation Stopped, and cleanup in phase-exit/respawn/destroy are all independent paths that should prevent this — but all are async (`task.delay`, event callbacks). If this occurs in live play, the respawn path is the guaranteed fix. Add a diagnostic: if `WalkSpeed == 0` more than `LANDING_HEAVY_LOCK_FALLBACK_DURATION + 0.5s` after a landing, emit a `Logger.warn` and force `clearLandingMovementLock()`.
- **Stage 3B new risk — sprint-jump momentum carry not MCP-verified end-to-end:** The `LinearVelocity` path requires `jumpedWhileSprinting = true` at landing, which is client-side state set by actual sprint+jump input. MCP `user_keyboard_input` does not sustain LeftShift or W in Studio play mode, so the full sprint-jump → momentum carry sequence was not live-tested. The non-sprint medium landing lock (0.35s) and heavy landing lock (0.65s) were verified via server-side teleport tests. Manual Studio playtest required to confirm: sprint → jump → land → LinearVelocity appears on HRP → WalkSpeed=0 for 0.22s → LinearVelocity destroyed → WalkSpeed restored.
- **Stage 3B new risk — `captureJumpMomentumDirection()` called at Jumping, not Freefall:** Direction is captured when `Humanoid.StateType == Jumping`. If the jump animation or a lag spike causes the `AssemblyLinearVelocity` to be near-zero at the exact Jumping frame (before horizontal velocity builds), `MoveDirection` and then `CFrame.LookVector` are used as fallbacks. If all three are near-zero (player standing still at jump entry), `sprintJumpMomentumDirection` is left nil and momentum carry is skipped gracefully. Verify in Studio that a standing sprint-jump (pressing LeftShift but not W just before jump) still produces a reasonable carry direction.
- **Stage 3B new risk — token invalidation and early unlock interaction:** The Stopped callback releases the lock early (`clearLandingMovementLock()`) when `not landingMomentumActive`. The fallback `task.delay` also calls `clearLandingMovementLock()` when the token matches. If both fire in the same frame (Stopped fires exactly as the fallback timer expires), the second call is a no-op (`isLandingMovementLocked` will already be false and `landingLockToken` will have been incremented). This is safe but worth noting: the increment-on-clear means the fallback timer is always invalidated after the Stopped early-unlock.

**Updated (2026-05-22 — Stage 3C: sprint stop duration gate + movement lock + momentum carry):**
- `sprintStartTime: number?` — set to `os.clock()` on every sprint `InputBegan`; cleared on sprint `InputEnded` and crouch `InputBegan`.
- `lastSprintMomentumDirection: Vector3?` — updated every Heartbeat while `isSprinting and not isTacticalSprinting`. Reads `AssemblyLinearVelocity` flat component if magnitude ≥ `SPRINT_STOP_MIN_HORIZONTAL_SPEED` (8); falls back to `MoveDirection` then `CFrame.LookVector`.
- `isSprintStopPlaying: boolean`, `sprintStopLockToken: number` — mirror the Stage 3B `isLandingMovementLocked` / `landingLockToken` pattern. `sprintStopLockToken` is incremented on every `clearSprintStopLock()`.
- `sprintStopMomentumAttachment: Attachment?`, `sprintStopMomentumVelocity: LinearVelocity?` — created by `startSprintStopMomentum()`, destroyed after `SPRINT_STOP_MOMENTUM_DURATION` (0.24s).
- `shouldPlaySprintStop(sprintDuration)`: returns false if `SPRINT_STOP_ENABLED` is false, `sprintDuration < SPRINT_STOP_MIN_SPRINT_DURATION` (0.75s), phase is not ACTIVE, player is crouching, or landing lock is active.
- `clearSprintStopMomentum()`, `clearSprintStopLock()`, `startSprintStopMomentum()`: helpers mirroring Stage 3B momentum helpers.
- `playSprintStopWithLock(direction?)`: sets `isSprintStopPlaying = true`, `WalkSpeed = 0`, calls `startSprintStopMomentum`, plays `TacticalSprintStop` (animation reused, same ID `rbxassetid://81946205769343`), connects `Stopped` callback to call `clearSprintStopLock()`, and schedules a fallback `task.delay(SPRINT_STOP_LOCK_FALLBACK_DURATION)`. Graceful fallback if the animation key is not loaded.
- `updateMovementAnimation()` gate: `if isSprintStopPlaying then return end` — after the `tacticalSprintStopConn ~= nil` gate.
- Sprint `InputEnded`: if `isTacticalSprinting` calls `stopTacticalSprint()`; regular sprint end is a simple clean exit (`isSprinting=false, applySpeed, updateSprintFov`) — `playSprintStopWithLock` is NOT called from the regular sprint path (SprintStop animation is tactical-sprint-only).
- Crouch `InputBegan`: calls `clearSprintStopLock()` and sets `sprintStartTime = nil` before entering crouch.
- Phase exit, `loadMovementAnimations()` (respawn), and `destroy()` all call `clearSprintStopLock()`, reset `sprintStartTime`, and reset `lastSprintMomentumDirection`.
- Nine new Constants: `SPRINT_STOP_ENABLED`, `SPRINT_STOP_MIN_SPRINT_DURATION` (0.75), `SPRINT_STOP_LOCKS_MOVEMENT`, `SPRINT_STOP_LOCK_FALLBACK_DURATION` (0.38), `SPRINT_STOP_MOMENTUM_ENABLED`, `SPRINT_STOP_MOMENTUM_DURATION` (0.24), `SPRINT_STOP_MOMENTUM_SPEED` (16), `SPRINT_STOP_MOMENTUM_MAX_FORCE` (60000), `SPRINT_STOP_MIN_HORIZONTAL_SPEED` (8).
- MCP/Studio verified 2026-05-22 (26/26 checks): all 9 Constants live in Studio; all 17 MovementController code patterns confirmed present in running module source via `loadstring` + plain-text `src:find` scan. No Output errors. Note: full end-to-end behavioral test (sprint ≥ 0.75s → SprintStop plays + WalkSpeed=0 + momentum carry) requires manual Studio playtest — MCP keyboard input does not reach `InputBegan` in Studio play mode (same limitation as Stages 2P/2Q/2R/3A/3B).

**Remaining gaps (updated Stage 3C):**
- Crouch walk animation — implemented for Unarmed (9 directional IDs, Stage 2J). AR15/gun-equipped CrouchWalk IDs still deferred.
- Sprint-jump momentum carry — LinearVelocity carry implemented for LandingMedium sprint-jump path (Stage 3B). AR15 set and LandingHeavy paths use only the lock (no carry). A dedicated heavy-landing carry is deferred.
- Sprint stop lock/momentum wired (2026-05-22 fix): `stopTacticalSprint()` is now a pure state-clear — no animation, no lock, no carry. Animation + lock + carry fire only from `playSprintStopWithLock` on Shift-release after ≥ `TACTICAL_SPRINT_STOP_MIN_DURATION` seconds. Direction-change and crouch interruptions cut instantly. `tacticalSprintStopConn` is now dead code (never set by `stopTacticalSprint`); the `updateMovementAnimation` gate `if tacticalSprintStopConn ~= nil then return end` is also dead code. Both can be removed in a future cleanup pass without changing behaviour.
- Momentum tuning: `SPRINT_STOP_MOMENTUM_SPEED = 16`, carry duration = `TacticalSprintStop.Length` (1.650s). May need tuning after manual playtest.
- Directional sprint animations — ForwardLeft and ForwardRight now play RunForwardLeft/RunForwardRight when customMouseLocked is ON (Stage 2R). Remaining directions still use RunForward in all cases.
- AR15 run diagonal, backward/diagonal walk, CrouchIdle/CrouchWalkStart, Falling/Landing IDs, tactical sprint IDs — all deferred (same as Stage 3B).
- TacticalSprintForward2 variation system, WalkForwardAlt/CrouchIdleAlt variation systems — deferred.
- Jump/climb/lower-upper-body split, reload/fire/ADS weapon animations — deferred.
- True server-owned equipment state, full custom camera, first-person integration — deferred (see DEBT-048, DEBT-050).

- **Stage 3C new risk — SprintStop momentum carry on slopes:** The `LinearVelocity` uses `RelativeTo = World` with a flat XZ direction. On a sloped surface the flat push may drive the character into the slope or along it unexpectedly. The `MaxForce = 60000` ensures the carry wins over gravity during the short 0.24s window, but slope geometry was not tested. If players experience unintended uphill/downhill push, reduce `MaxForce` or add a slope-angle guard in `startSprintStopMomentum` that skips carry when the floor normal deviates from up by more than a threshold.
- **Stage 3C new risk — SprintStop animation reuse (TacticalSprintStop):** The same one-shot animation (`rbxassetid://81946205769343`) is shared between tactical sprint stop and normal sprint stop. If a future stage adds a dedicated normal-sprint-stop animation, the ID must be added to `Constants.MOVEMENT_ANIMATION_IDS` under a distinct key (e.g. `SprintStop`) and `playSprintStopWithLock` updated to prefer it. The current reuse is intentional and safe as long as both code paths can tolerate the same clip.
- **Stage 3C new risk — WalkSpeed stuck at 0 in SprintStop edge cases:** Same risk as Stage 3B landing lock. The `task.delay` fallback (0.38s), the Stopped callback, and the cleanup in phase-exit/respawn/destroy are independent unlock paths. If all three fail (unlikely), the player will be stuck until respawn. The token guard prevents stale unlocks from a delayed closure.
- **Stage 3C new risk — SprintStop plays during rapid re-sprint:** If the player releases Shift (triggering SprintStop) and immediately presses Shift again, the `InputBegan` handler calls `clearSprintStopLock()` which cancels the in-flight SprintStop and restores WalkSpeed. The sprint resumes normally. The token increment ensures the stale fallback timer does not re-clear state after the new sprint begins. Verify in Studio that rapid Shift-release → Shift-press does not leave a stuck WalkSpeed=0 or a double-SprintStop.
- **Stage 3C new risk — MCP Studio verification not completed for SprintStop:** The disk edits passed `rojo build` and all grep checks. Studio MCP verification was attempted but blocked by a Rojo Connect dialog that cannot be clicked via MCP tools. A manual Studio playtest is required to confirm: (1) sprint < 0.75s → no SprintStop; (2) sprint ≥ 0.75s → SprintStop plays, WalkSpeed=0, player carries forward; (3) tactical sprint stop still takes precedence; (4) crouch while sprinting cancels SprintStop; (5) momentum direction matches actual sprint direction.
- **Stage 3C fix risk — `tacticalSprintStopConn` is now dead code (2026-05-22):** After the `stopTacticalSprint()` refactor, `tacticalSprintStopConn` is never set and the `if tacticalSprintStopConn ~= nil then return end` gate in `updateMovementAnimation()` never fires. These are safe dead-code paths (they only gate, never corrupt state), but they should be removed in a future cleanup to reduce confusion. Safe to delete in any future movement stage.
- **Stage 3C fix risk — crouch bug unverified (2026-05-22):** The user reports an ongoing crouch bug. MCP cannot simulate the C key in Studio play mode (C key does not reach `InputBegan`). Static code review did not identify a clear root cause after Stage 2Q+ fixes. Manual visual playtesting is required. Test: rapid C tap (press + release within 300ms), C press while walking, C press while in TacticalSprintStop, and C press while `isSprintStopPlaying = true`.

**Trigger:** Any playtesting session where T-pose during idle/jump or missing backward/diagonal animations is noticeable; where crouch bottom-pose hold or CrouchWalk transitions look wrong; where the `getRigDebugSummary` warn appears; where CrouchWalk direction does not match movement direction; where WalkSpeed appears stuck at 0 after a landing; or where animation speed or input feels wrong after Studio testing.
**Fix when:** A future movement stage adds idle/jump/fall/climb custom clips, AR15 CrouchWalk IDs, a dedicated CrouchIdle clip, and server-owned equipment integration. Tune speed multipliers after first Studio playtest. Do not build full Scriptable camera system until camera refactor is scheduled. Add the WalkSpeed=0 stuck diagnostic when any live-play test confirms the edge case.

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
