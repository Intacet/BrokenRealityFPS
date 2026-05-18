# CHANGELOG.md

All notable changes to this project, newest first.

Format: `## [version or date] — description`
Under each entry: bullet points for what was added, changed, or removed.

---

## [2026-05-15] — Add docs/PERSISTENT_ZONE_ROADMAP.md: staged implementation plan for persistent-zone pivot (documentation only, no runtime code changed)

**This was a documentation and planning update. No `src/` files were changed. No remotes were added. No runtime behavior changed.**

**Added — `docs/PERSISTENT_ZONE_ROADMAP.md`**
- New file: 11-stage (Stage 0–10) staged build plan for the persistent PvPvE zone shooter pivot.
- Each stage defines: goal, checklist, files likely affected later, explicit scope gates ("not in this stage"), Studio/MCP verification requirement, and maintenance risks.
- Stage 0 (FPS foundation — GunService, DamageService, HUD, KillFeed, Constants) is marked partially complete. Stages 1–10 are not started.
- Stage 1: EconomyService (carried cash + secured funds, deposit logic, RemoteEvents).
- Stage 2: ZoneService (persistent zone state, entry/exit gates, player tracking).
- Stage 3: BaseService (safe base area, spawn selection, deposit terminal area).
- Stage 4: LootService (zone loot pickups, cash awards on pickup).
- Stage 5: DeathDropService (death bag, weapon + cash dropped at death position).
- Stage 6: ExtractionService (exit trigger, converts carried cash to secured funds on extract).
- Stage 7: ShopService (zone shop via carried cash; base armory via secured funds).
- Stage 8: MonsterService (zone AI enemies, pathfinding, attack logic).
- Stage 9: ZoneEventService (periodic timed events; deferred until Stages 1–8 stable).
- Stage 10: InventoryService / StashService / ProgressionService (deferred; do not start until full loop verified).
- Stage reference summary table included at the bottom of the file.

**Changed — `docs/PROJECT_MAP.md`**
- Added one-line reference to `docs/PERSISTENT_ZONE_ROADMAP.md` in the New Target Architecture section, below the first-milestone note.

**Changed — `docs/TECHNICAL_DEBT.md`**
- DEBT-036: Added roadmap reference note clarifying that `docs/PERSISTENT_ZONE_ROADMAP.md` is planning-only and does not resolve the debt entry; runtime systems must still be built and verified in Studio stage by stage.

---

## [2026-05-15] — Extend persistent-zone pivot documentation: in-zone shops, zone events, base/zone distinction, ZoneEventService (documentation only, no runtime code changed)

**This was a documentation and planning update. No `src/` files were changed. No remotes were added. No runtime behavior changed.**

**Changed — `CLAUDE.md`**
- Main loop diagram extended: in-zone zone shop step added; periodic zone events step added; base spend step expanded to include base upgrades and stash.
- Money model table extended with "Spendable" column: carried cash is spendable in-zone at zone shops; secured funds are spendable at base.
- New "**Base / zone distinction**" table added: base = safe, secured funds, armory/upgrades/stash; zone = dangerous, carried cash, shops, events, death drops.
- Early prototype scope updated: zone shop described as "consumables and basic guns" (base armory with full tiers added later); one simple periodic zone event added as a deferred scope item.

**Changed — `docs/PROJECT_MAP.md`**
- `ZoneEventService` added to planned services table: owns periodic zone events (timed loot surges, cash bonuses, monster waves); deferred until core loop is stable.
- `ShopService` description clarified: zone shop uses carried cash; base armory uses secured funds.
- First persistent-zone code milestone note added: build `EconomyService` (carried cash + secured funds + deposit/extraction) before any other new system.

**Changed — `docs/PROJECT_RULES.md`**
- "Zone shops and base armory" rule added: zone shops accept carried cash only and must not shortcut base progression; base armory uses secured funds only; two economies must remain separate.
- "Periodic zone events" rule added: events create pressure and reward aggression but must not lock players into mandatory participation or convert the persistent zone into a round mode.
- "Scope discipline" updated to include `ZoneEventService` in the deferred list and mention zone events in the "do not batch" example.

**Changed — `docs/TECHNICAL_DEBT.md`**
- DEBT-036 updated: added no-respawn assumption (TeamService's `CharacterAutoLoads = false` is incompatible with always-open re-entry) and old objective win conditions (ObjectiveService treats anchor completion as match-ending) to affected legacy systems list. Added stage-and-verify migration rule.

**Validation**
- No `src/` files changed. ✓
- No remotes added. ✓
- No camera behavior changed. ✓
- No gameplay code changed. ✓
- Old round-based documentation preserved and marked legacy/transitional (not deleted). ✓
- No markdown linter configured locally — manual review only.

---

## [2026-05-15] — Project direction pivot: persistent PvPvE zone shooter (documentation only, no runtime code changed)

**This was a documentation and planning update. No `src/` files were changed. No remotes were added. No runtime behavior changed.**

**Changed — `CLAUDE.md`**
- "Game concept" section marked as legacy/transitional with a note not to expand round-based features.
- New "**Current product direction**" section added defining:
  - Persistent PvPvE broken-reality zone shooter (no round timer)
  - Main loop: spawn at base → enter zone → loot/fight/earn carried cash → extract → deposit → armory → zone
  - Death rule: lose equipped weapon, carried loot, carried cash; keep secured funds, stash, upgrades, reputation
  - Money model: carried cash (risky, lost on death) vs secured funds (safe, never lost)
  - Early prototype scope: one zone, one base, deposit terminal, armory, three weapons, simple loot, death drops
- "First playable goal" updated: old five-round attacker/defender milestone marked as achieved (legacy); new persistent zone prototype goal defined.
- "Build order" updated: Milestone 0 (legacy round-based) marked complete/legacy; Milestone 1 (persistent zone) build sequence added (ZoneService → EconomyService → BaseService → LootService → DeathDropService → ExtractionService → ShopService → deferred systems → MonsterService).

**Changed — `docs/PROJECT_RULES.md`**
- New "Persistent zone design rules" section added: loot security requires physical extraction, death must hurt but not cause quit, free respawn always available, fast re-entry, one system per prompt discipline, legacy systems must not be expanded.
- New "Server authority — persistent zone systems" section added: server owns carried cash, secured funds, inventory, death drops, extraction success, shop purchases, base upgrades, loot positions; client fires request remotes and displays server state only.

**Changed — `docs/PROJECT_MAP.md`**
- "Match lifecycle" system map section marked as **legacy/transitional**.
- "AI" system map section annotated (HordeService plan updated for zone ambient spawning).
- New "**New Target Architecture**" section added with:
  - Planned future services table (ZoneService, BaseService, EconomyService, LootService, DeathDropService, ExtractionService, ShopService, InventoryService, StashService, ProgressionService, MonsterService)
  - Legacy services table with migration notes (MatchService → ZoneService; TeamService → faction/spawn management; ObjectiveService → zone events)
  - Reusable systems table (GunService, DamageService, RagdollService, etc.)

**Changed — `docs/TECHNICAL_DEBT.md`**
- DEBT-036 added: "Round-based architecture no longer matches target persistent-zone design" — Severity: High — covers MatchService, TeamService, ObjectiveService, MatchUI, DeathScreen, and their client counterparts.
- DEBT-003, DEBT-005, DEBT-007, DEBT-019, DEBT-020 annotated as **legacy/transitional** in the context of the pivot.

**Validation**
- No `src/` files changed. ✓
- No remotes added. ✓
- No camera behavior changed. ✓
- No gameplay code changed. ✓
- Old round-based documentation preserved and marked legacy/transitional (not deleted). ✓
- No markdown linter configured locally — manual review only.

---

## [2026-05-15] — Harden GunService shot validation: origin proximity and direction magnitude checks (needs Studio verification)

**Changed — `src/shared/Constants.lua`**
- Added `Constants.SHOT_ORIGIN_MAX_DISTANCE = 12` — maximum studs between the client-sent shot origin and the shooter's `HumanoidRootPart`; shots with farther origins are rejected.
- Added `Constants.SHOT_DIRECTION_MIN_MAGNITUDE = 0.001` — minimum direction vector magnitude; near-zero directions are rejected before normalization.

**Changed — `src/server/GunService.server.lua`**
- Added `getShooterRootPosition(player: Player): Vector3?` — returns `HumanoidRootPart.Position` or nil if the character or root is missing.
- Added `isValidShotPayload(shooter, origin, direction): (boolean, Vector3?, Vector3?)` — checks types, direction magnitude, and origin-to-root distance. Returns normalized direction on success; logs via `Logger.warn` and returns `false, nil, nil` on failure.
- Replaced the thin type-only guard in `WeaponFired.OnServerEvent` with a call to `isValidShotPayload`. The returned validated origin and normalized direction are used for `workspace:Raycast`.
- All previous validation (phase gate, rate limit, ammo check) unchanged.
- `clientTick` validation intentionally not added — see DEBT-014.

**Updated — `docs/PROJECT_MAP.md`**
- GunService validates line updated to document payload type checks, direction magnitude rejection, origin proximity rejection, and direction normalization. clientTick deferral noted.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-014: Updated to note origin/direction hardening was added. clientTick still deferred. MCP-unavailable note added.

**Validation**
- `selene` not available locally — linter could not be run.
- `rojo` not available locally — build validation could not be run.
- `Constants.SHOT_ORIGIN_MAX_DISTANCE = 12` confirmed. ✓
- `Constants.SHOT_DIRECTION_MIN_MAGNITUDE = 0.001` confirmed. ✓
- `getShooterRootPosition` added with nil-safe character/root check. ✓
- `isValidShotPayload` added with all required checks in order. ✓
- `validOrigin` and `validDirection` used for `workspace:Raycast`. ✓
- `clientTick` not validated (intentional). ✓
- No remotes added or changed. ✓
- No client files changed. ✓
- No camera behavior changed. ✓
- **Needs Studio verification before DEBT-014 origin/direction portion can be closed.**

---

## [2026-05-15] — Centralize default weapon name in Constants.DEFAULT_WEAPON for GunService and GunController (needs Studio verification)

**Changed — `src/client/GunController.lua`**
- Removed `local CURRENT_WEAPON = "AR15"`. GunController now reads `Constants.DEFAULT_WEAPON` directly for all client-side prediction: dry-fire checks, `WeaponData` range for the cosmetic raycast, and local rate limiting.
- Updated Configuration comment block to document that `Constants.DEFAULT_WEAPON` is the single source of truth and that `GunService` remains authoritative for all server-side validation.

**Changed — `src/server/GunService.server.lua`**
- Updated Configuration comment to reflect that both GunService and GunController now read `Constants.DEFAULT_WEAPON`. Removed stale reference to GunController's `CURRENT_WEAPON` local.
- No logic changes. All `Constants.DEFAULT_WEAPON` usages were already in place from the previous session.

**No change — `src/shared/Constants.lua`**
- `Constants.DEFAULT_WEAPON = "AR15"` was already present. No edit required.

**Updated — `docs/PROJECT_MAP.md`**
- GunService combat section expanded to document: GunService uses `Constants.DEFAULT_WEAPON` authoritatively; GunController uses it only for client-side prediction; a single rename of `Constants.DEFAULT_WEAPON` covers both sides; `WeaponFired` and `ReloadRequest` carry no weapon name by design.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-013: Second partial resolution entry added. `CURRENT_WEAPON` local removed from GunController; remaining risk (no weapon name in `WeaponFired`/`ReloadRequest`) documented as intentional. Studio verification still required.

**Validation**
- `selene` not available locally — linter could not be run.
- `rojo` not available locally — build validation could not be run.
- `Constants.DEFAULT_WEAPON = "AR15"` confirmed present in `src/shared/Constants.lua`. ✓
- `GunService.server.lua` confirmed: no `local DEFAULT_WEAPON` declaration; all usages are `Constants.DEFAULT_WEAPON`. ✓
- `GunController.lua` confirmed: no `local CURRENT_WEAPON` declaration; both usages replaced with `Constants.DEFAULT_WEAPON`. ✓
- No remotes added or changed. ✓
- No viewmodel files changed. ✓
- No camera behavior changed. ✓
- `WeaponFired` payload unchanged: `(origin, direction, tick)`. ✓
- `ReloadRequest` payload unchanged: no arguments. ✓
- **Needs Studio verification before DEBT-013 can be closed.**

---

## [2026-05-15] — Tighten friendly-fire guard with Player.Team fallback (needs Studio verification)

**Changed — `src/server/DamageService.lua`**
- Added `getTeamName(player: Player): string?` private helper. Checks `playerTeam[]` cache first (populated via `MatchEvents.TeamAssigned` at PREP). If the cache entry is nil, falls back to `player.Team.Name`. Returns nil if both are unavailable — in that case the guard does not block damage.
- Friendly-fire guard in `Apply()` refactored to call `getTeamName(attacker)` and `getTeamName(victim)`. Same early-return behavior (no health change, no `HealthChanged`, no `RagdollService`) when both team names are non-nil and equal. If either is nil, the shot passes through.
- Updated stale comments on `playerTeam` table and `GetTeam()` public method.

**Confirmed — `src/shared/Constants.lua`**
- `Constants.FRIENDLY_FIRE_ENABLED = false` already present (added in previous task). No change required.

**Updated — `docs/PROJECT_MAP.md`**
- DamageService combat section updated to document the two-tier team lookup (cache → `Player.Team.Name` fallback) and the nil-team pass-through behavior.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-009: Updated to "Code improved; needs Studio verification." Fallback behavior and runtime test steps (including late-joiner scenario) documented.

**Validation**
- `selene` not available locally — linter could not be run.
- `rojo` not available locally — build validation could not be run.
- No remotes added or changed. ✓
- No client files changed. ✓
- No camera files changed. ✓
- `Constants.FRIENDLY_FIRE_ENABLED = false` confirmed present. ✓
- `getTeamName()` helper confirmed added with cache-first / `Player.Team.Name` fallback. ✓
- **Needs Studio verification before DEBT-009 can be closed.**

---

## [2026-05-15] — AmmoChanged now sends weapon name; HUD displays server-provided weapon (needs Studio verification)

**Changed — `src/shared/Constants.lua`**
- Added `Constants.DEFAULT_WEAPON = "AR15"` in the **Combat rules** section. Single source of truth for the active weapon name used by GunService and HUD.

**Changed — `src/server/GunService.server.lua`**
- Removed `local DEFAULT_WEAPON = "AR15"`. All five `AmmoChanged:FireClient` call sites now pass `Constants.DEFAULT_WEAPON` as the first argument before `mag` and `reserve`.
- All `WeaponData` lookups and logger messages now reference `Constants.DEFAULT_WEAPON`.

**Changed — `src/client/GunController.lua`**
- `AmmoChanged.OnClientEvent` listener updated from `function(mag, reserve)` to `function(_weaponName, mag, reserve)`. `_weaponName` is ignored here; HUD displays it.

**Changed — `src/client/UI/HUD.lua`**
- Removed hardcoded `"SCAR"` weapon-name label from the ammo block.
- Added `weaponLabel: TextLabel` reference populated during `init()` with `Constants.DEFAULT_WEAPON` as the initial text (never blank before the first `AmmoChanged` fires).
- `setAmmo()` now accepts `weaponName: string` as first argument and sets `weaponLabel.Text`.
- `AmmoChanged.OnClientEvent` listener updated to `function(weaponName, mag, reserve)`.

**Updated — `docs/PROJECT_MAP.md`**
- `AmmoChanged` remote registry row updated with new payload (`weaponName, mag, reserve`).
- Added GunService combat section note: server owns weapon identity; `Constants.DEFAULT_WEAPON` is the single source of truth.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-013: Updated to "Partially resolved." Single source of truth established; HUD now server-driven. `WeaponFired`/`ReloadRequest` still do not carry weapon name — intentional at this stage.

**Validation**
- `selene` not available locally — linter could not be run.
- `rojo` not available locally — build validation could not be run.
- No new remotes created. ✓
- No viewmodel files changed. ✓
- No camera behavior changed. ✓
- **Needs Studio verification before DEBT-013 can be closed.**

---

## [2026-05-15] — Add friendly-fire prevention to DamageService (needs Studio verification)

**Changed — `src/server/DamageService.lua`**
- Added a friendly-fire guard to `DamageService:Apply()`. When `Constants.FRIENDLY_FIRE_ENABLED == false`, shots from a player at a teammate (both with known `playerTeam` entries) return immediately without mutating health, firing `HealthChanged`, or triggering `RagdollService`. Environment damage (`attacker == nil`) and players whose team was never assigned (nil entry in `playerTeam`) bypass the guard. Blocked shots are logged via `Logger.debug`.

**Changed — `src/shared/Constants.lua`**
- Added `Constants.FRIENDLY_FIRE_ENABLED = false` in a new **Combat rules** section. Set to `true` to re-enable full friendly fire without a code change.

**Updated — `docs/PROJECT_MAP.md`**
- Combat section now documents that `DamageService` blocks same-team damage when `Constants.FRIENDLY_FIRE_ENABLED == false`, and that this decision is server-side only.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-009: Updated to "Code added; needs Studio verification." Runtime test steps documented. Not marked fully resolved — MCP was unavailable during this task.

**Validation**
- `selene` not available locally — linter could not be run.
- `rojo` not available locally — build validation could not be run.
- No remotes added or changed. ✓
- No client files changed. ✓
- No camera files changed. ✓
- **Needs Studio verification before DEBT-009 can be closed.**

---

## [2026-05-15] — Add asset import safety checklist to reduce risk of untracked rogue Studio scripts

**Updated — `CLAUDE.md`**
- Added **Asset import safety checklist** section to the Claude behavior rules. Requires: stating expected container changes before importing; inspecting `StarterCharacterScripts`, `StarterGui`, `StarterPack`, `ReplicatedFirst`, `Lighting`, `SoundService`, `Workspace`, and all imported Model descendants after every import; deleting or moving every untracked Script or LocalScript to `src/`; deleting any LocalScript that controls `CameraType`, `camera.CFrame`, or `RenderStepped` camera behavior; and marking camera/viewmodel/combat imports as requiring Studio verification.

**Updated — `docs/PROJECT_RULES.md`**
- Added **Asset import safety checklist** section with the same rules in the project-rules format (concise, imperative).

**Updated — `docs/PROJECT_MAP.md`**
- Added **Rojo-managed vs unmanaged Studio containers** table documenting every top-level Studio container, whether Rojo tracks it, the source path (if any), and notes. Clearly marks `StarterCharacterScripts`, `StarterGui`, `StarterPack`, `ReplicatedFirst`, `Lighting`, and `SoundService` as unmanaged. Includes a warning about import-introduced scripts in unmanaged containers.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-031: Added "Partially mitigated (2026-05-15)" note documenting the checklist as a process control. Severity stays High — the structural gap (no Rojo mapping for `StarterCharacterScripts`) remains. Studio verification required: Yes — only Studio inspection after each import can confirm no rogue scripts were introduced.

**Validation**
- No markdown linter installed locally.
- No src files changed. ✓
- No gameplay files changed. ✓
- MCP unavailable — no Studio verification performed. ✓

---

## [2026-05-15] — Add severity and Studio verification labels to all technical debt entries

**Updated — `docs/TECHNICAL_DEBT.md`**
- Added a **Severity legend** section near the top of the file defining Critical / High / Medium-High / Medium / Low-Medium / Low / Resolved.
- Added **Severity:** and **Studio verification required:** fields to every debt entry (33 entries total: 25 active, 8 resolved).
- No entry's resolution status, meaning, or existing text was changed — labels only.

Severity assignments:
- Critical: DEBT-009 (friendly fire live)
- High: DEBT-013, DEBT-014 (weapon hardcode, tick exploit), DEBT-022 (ragdoll accumulation), DEBT-031 (untracked Studio containers)
- Medium-High: DEBT-007 (six RoundStateChanged listeners), DEBT-019 (CharacterAutoLoads no fallback)
- Medium: DEBT-005, DEBT-010, DEBT-011, DEBT-020, DEBT-024, DEBT-030
- Low-Medium: DEBT-003, DEBT-017, DEBT-018, DEBT-023, DEBT-026, DEBT-034
- Low: DEBT-001, DEBT-004, DEBT-029, DEBT-032, DEBT-033, DEBT-035
- Resolved: DEBT-002, DEBT-006, DEBT-008, DEBT-012, DEBT-015, DEBT-016, DEBT-021, DEBT-025

Studio verification required: Yes for all runtime, gameplay, combat, UI, camera, character lifecycle, and ragdoll entries. No for static-inspection-only entries. Not applicable for resolved entries.

**Validation**
- No markdown linter is installed locally — no markdown validation was run.
- No src files changed. ✓
- No gameplay files changed. ✓

---

## [2026-05-15] — Remove invalid StarterGui/src/ui Rojo mapping; document controller-generated UI architecture

**Changed — `default.project.json`**
- Removed the `StarterGui` block that mapped `"$path": "src/ui"`. The `src/ui/` directory exists on disk but is empty — no `.lua` files are present. The mapping caused Rojo to attempt to sync an empty folder into `StarterGui`, which is misleading and would produce an empty synced container. All ScreenGui instances are created at runtime by client controllers (`HUD`, `MatchUI`, `DeathScreen`, `KillFeedUI`, `CrosshairUI`), not by static disk files. StarterGui is now unmanaged by Rojo, which is correct for this development stage.
- All other mappings preserved: `ReplicatedStorage/Modules → src/shared`, `ServerScriptService/Services → src/server`, `StarterPlayer/StarterPlayerScripts/Controllers → src/client`, all Workspace sub-folders.

**Updated — `docs/PROJECT_MAP.md`**
- Added a **StarterGui / UI source mapping** section documenting that UI is controller-generated, StarterGui has no Rojo mapping, `src/ui/` has no files, and explaining exactly what steps to take when static StarterGui content is needed.

**Updated — `docs/TECHNICAL_DEBT.md`**
- DEBT-031: Updated title and body to explicitly include StarterGui as a second untracked Rojo container alongside StarterCharacterScripts. Added 2026-05-15 update note explaining why the mapping was removed.
- Added DEBT-035: Documents that StarterGui intentionally has no Rojo source mapping at this stage. Captures the forward risk that a developer adding files to `src/ui/` must also restore the mapping, and that restoring the mapping without files causes a Rojo build error.

**Validation**
- `default.project.json` is valid JSON (no `src/ui` reference remains). ✓
- No `src/` files changed. ✓
- Rojo binary not available locally — static `rojo build` validation was not run. Needs Rojo/Studio verification on next Studio session.
- MCP unavailable — no Studio verification performed.

---

## [2026-05-15] — Add prompt pre-flight review and MCP unavailable / GitHub-only mode rules to CLAUDE.md

**Updated — `CLAUDE.md`**
- Added **Prompt pre-flight review** rule: before implementing any prompt, Claude Code must state the goal, confirm safety and scope, list expected file changes, flag any camera/viewmodel/combat/replication/data-loss risks, and either proceed (if safe and prompt includes "review then proceed if safe") or stop and ask for confirmation
- Added **MCP unavailable / GitHub-only mode** rule: when Roblox Studio MCP is disconnected, restrict work to docs/config/static-validation only; never claim Studio verification was performed; mark any gameplay-affecting change as "needs Studio verification"; do not mark runtime debt resolved without actual Studio confirmation

**Updated — `docs/TECHNICAL_DEBT.md`**
- Added DEBT-033: prompt pre-flight review is a behavioral convention only — no tooling enforces it; a future hook or CI step would strengthen the guarantee
- Added DEBT-034: MCP-unavailable scope guard is self-reported — no CI gate verifies that gameplay changes were tested in Studio; unverified changes must be manually tagged

---

## [2026-05-14] — Add full movement system and Ready or Not gunplay feel

### New files
- **`src/shared/WeaponFeel.lua`** — per-weapon gunplay feel parameters. SCAR entry (recoil up/right/buildup/recovery/reset, hip/ads spread, moving/sprinting/crouch spread modifiers, ADS time, fire rate, muzzle flash duration, shell eject flag). AR15 is an alias for SCAR pending a separate tuning pass (DEBT-039).
- **`src/client/MovementController.lua`** — complete movement feel controller:
  - Sprint (Left Shift), crouch toggle (C), slide (C while sprinting with cooldown), vault (auto step-up over 0.5–2.5 stud obstacles, raycast every 0.1 s)
  - 13-state animation machine: Idle, WalkForward, WalkBack, WalkLeft, WalkRight, WalkDiagFL, WalkDiagFR, WalkDiagBL, WalkDiagBR, Sprint, CrouchIdle, CrouchWalk, Slide. All IDs are 0 (placeholder, DEBT-044).
  - 8-directional walk classification via camera-relative dot products
  - Camera bob: sine wave on `Humanoid.CameraOffset` at BOB_FREQ_WALK=9 Hz / BOB_AMP_WALK=0.07 stud while walking, BOB_FREQ_SPRINT=13 Hz / BOB_AMP_SPRINT=0.11 stud while sprinting
  - Crouch camera height tween via `Humanoid.CameraOffset` (CROUCH_CAM_OFFSET=-1.4 over 0.15 s)
  - Landing dip via `Humanoid.CameraOffset` (0.3 stud down over 0.08 s, rise over 0.2 s)
  - Viewmodel slide tilt roll (8°, lerped at 12/s) exposed via `GetViewmodelAddCFrame()`
  - Phase awareness: movement features gated on ACTIVE; speed and stance reset on other phases
  - Exposes: `GetMoveState()`, `IsADSBlocked()`, `GetViewmodelAddCFrame()`, `Start()`

### Changed files
- **`src/shared/Constants.lua`** — updated speed values and added movement constants:
  - `WALK_SPEED` 16 → 14, `SPRINT_SPEED` 24 → 22
  - Added `CROUCH_SPEED=10`, `SLIDE_SPEED=30`, `SLIDE_DURATION=0.6`, `SLIDE_COOLDOWN=1.5`
  - Added `SPRINT_STAMINA_ENABLED=false` (DEBT-042), `PRONE_ENABLED=false` (DEBT-043)
- **`src/client/GunController.lua`** — recoil, spread, ADS, and WeaponFeel integration:
  - Requires `WeaponFeel` and `MovementController`
  - Recoil CFrame accumulated per shot (`recoilBuildup` increases with sustained fire, resets after `recoilResetTime` seconds of silence). Lerps to identity in RenderStepped. Pushed to ViewModelController via `SetRecoilOffset()` every frame (push pattern — no circular dependency).
  - Spread: half-cone angle computed from `WeaponFeel` + `MovementController:GetMoveState()`. Applied as random polar deviation to raycast direction before `WeaponFired:FireServer()`.
  - ADS: `isADS` toggled by MouseButton2. Blocks if `MovementController:IsADSBlocked()`. Gates spread to `baseSpread` only (visual transition deferred, DEBT-040).
  - Muzzle flash duration now reads `WeaponFeel.muzzleFlashDuration` instead of hardcoded 0.05 s.
  - Exposes `GetRecoilOffset(): CFrame`.
- **`src/client/ViewModelController.lua`** — applies recoil and movement offsets:
  - Requires `MovementController` (no circular — MovementController does not require ViewModelController).
  - Added `viewRecoilCFrame: CFrame` state variable.
  - Added `SetRecoilOffset(cf: CFrame)` public setter for GunController to push into.
  - RenderStepped now composes: `cam.CFrame * viewRecoilCFrame * MovementController:GetViewmodelAddCFrame() * BASE_OFFSET * CFrame.new(0, 0, recoilOffset)`.
- **`src/client/ClientInit.client.lua`** — added MovementController at position 9, GunController moved to 10. Header comment updated to 10 controllers. Dependency notes updated.
- **`docs/PROJECT_MAP.md`** — expanded MovementController entry, added WeaponFeel to shared modules table, updated initialization order to 10.
- **`docs/TECHNICAL_DEBT.md`** — added DEBT-039 through DEBT-045; updated DEBT-007 and DEBT-017 notes.

### Debt entries added
- DEBT-039: WeaponFeel AR15 is an alias for SCAR (no separate tuning)
- DEBT-040: ADS visual transition not implemented
- DEBT-041: Shell ejection VFX not implemented
- DEBT-042: Sprint stamina system not implemented
- DEBT-043: Prone stance not implemented
- DEBT-044: All animation IDs are placeholder zeroes
- DEBT-045: Recoil is viewmodel-only (no camera-space kick)

---

## [2026-05-14] — Fix camera pitch lock (rogue StarterCharacterScripts LocalScript removed)

### Root cause
A `LocalScript` (named `"LocalScript"`) was present in `StarterPlayer.StarterCharacterScripts`.
It was **not** part of the Rojo-tracked `src/` tree — it was imported into the place directly
when the TROY DEFENSE AR viewmodel asset was brought in. It ran on every spawned character and:

- Bound `"overTheShoulderCamera"` to `RunService:BindToRenderStep` at priority 201
- Set `camera.CameraType = Enum.CameraType.Scriptable` every frame, overriding the Roblox camera system
- Computed `camera.CFrame = CFrame.lookAt(rootPart-relative offset, rootPart-relative target)` using
  fixed vertical offsets — **zero pitch input, yaw only**
- Rotated a `BodyGyro` with `CFrame.fromAxisAngle(Vector3.new(0,1,0), …)` — Y-axis only
- Forced `UserInputService.MouseBehavior = LockCenter` and disabled `human.AutoRotate`

Result: mouse left/right worked (BodyGyro yaw), mouse up/down was silently discarded.
The `"Camera has been binded"` and `"ACL_Toggle"` messages in the console were produced by this script.

### Fix (Studio-side only — no Rojo source file)
Deleted `StarterPlayer.StarterCharacterScripts.LocalScript` via Roblox Studio MCP `execute_luau`.
`StarterCharacterScripts` is not mapped in `default.project.json`, so no disk file exists.
**The deletion must be saved in Studio (Ctrl+S) to persist across Studio restarts.**
The standard `PlayerModule.CameraModule` (ClassicCamera + `LockFirstPerson` mode set by
`ViewModelController`) now handles both yaw and pitch. `ViewModelController` reads `camera.CFrame`
in RenderStepped and passes full pitch+yaw to `PivotTo` — the viewmodel follows up/down correctly.

### Verified in play mode
- No `CameraType = Scriptable`, `overTheShoulderCamera`, or `ACL_Toggle` log messages ✓
- `setVisibility(true) — 40 parts` during ACTIVE (viewmodel BaseParts present) ✓
- `MuzzleAttachment` found (no fallback warning logged) ✓

---

## [2026-05-14] — Replace AR15 viewmodel with imported rig; fix camera alignment and replication race

### Changes

**Built in Studio via MCP — `ReplicatedStorage/ViewModels/AR15` (replaced)**
- Replaced the previous 30-part WeldConstraint-based asset with the full 49-BasePart TROY DEFENSE AR Motor6D rig
- All 49 BaseParts: CanCollide=false, CanQuery=false, CanTouch=false, Massless=true, CastShadow=false
- PrimaryPart = HumanoidRootPart; Motor6D arm chain (L and R sub-models, Torso, Handcontrol) preserved intact
- HELPER_PARTS (HumanoidRootPart, FakeCamera, Torso, Handcontrol, Main): Transparency=1 permanently
- Visual parts (arm MeshParts, gun MeshParts): Transparency=0 during ACTIVE; 40 visual BaseParts
- MuzzleAttachment added at barrel tip Part for muzzle flash placement in `GetBarrelTipCFrame()`
- Humanoid removed; no scripts remain in the model
- Previous 30-part WeldConstraint asset backed up as `ReplicatedStorage/ViewModels/AR15_Old_Backup`

**Updated — `src/client/ViewModelController.lua`**
- `init()` now uses `WaitForChild("AR15", 5)` + `found:WaitForChild("HumanoidRootPart", 5)` instead of bare `FindFirstChild` — fixes the play-mode "clone has 0 BaseParts" replication race that caused the placeholder to load instead of the real rig
- Post-clone part-count guard added: if clone still has 0 BaseParts after WaitForChild, logs a warning and falls through to the programmatic placeholder
- `HELPER_PARTS` table added at module level — lists 6 physics/rig-anchor part names (HumanoidRootPart, FakeCamera, Torso, Handcontrol, Main, Root) that must remain Transparency=1 permanently
- `setVisibility(show=true)` now skips HELPER_PARTS to avoid flashing invisible rig anchors as visible geometry
- `init()` now dynamically computes `BASE_OFFSET = hrp.CFrame:ToObjectSpace(fc.CFrame):Inverse()` from the clone's FakeCamera so `PivotTo(cam.CFrame * BASE_OFFSET)` aligns FakeCamera exactly with CurrentCamera (the rig's intended camera pivot); falls back to hardcoded `REAL_MODEL_OFFSET` if FakeCamera is absent
- `REAL_MODEL_OFFSET` updated to the pre-computed FakeCamera inverse `CFrame.new(-0.7141, -1.6346, 2.0080) * CFrame.Angles(0.055254, 0, 0)` — used only as a fallback constant

---

## [2026-05-14] — Add AR15 first-person viewmodel from Workspace assets

**Asset flow:** `Workspace["TROY DEFENSE AR"]` + `Workspace.Viewmodel` → `ReplicatedStorage/ViewModels/AR15` (built via MCP Lua) → `ViewModelController:init()` clones and parents to `CurrentCamera` → `RenderStepped` drives `PivotTo` every frame → `setVisibility` shows/hides on phase change.

### Changes

**Built in Studio via MCP — `ReplicatedStorage/ViewModels/AR15` (new Model)**
- `Root` Part (0.1×0.1×0.1, Transparency=1, CanCollide/CanQuery/CanTouch=false, Massless=true, Anchored=false) set as PrimaryPart — this is the camera-anchor that PivotTo targets
- 27 BaseParts cloned from `Workspace["TROY DEFENSE AR"]`: physics flags reset (CanCollide/CanQuery/CanTouch=false, Massless=true, Anchored=false); positions shifted from Workspace world space to camera-local space (gun centre at (0.35, -0.35, -1.0) from Root); rotations preserved
- `LeftArm` and `RightArm` MeshParts cloned from `Workspace.Viewmodel`: positioned at camera-local offsets derived from Motor6D C0 analysis (LeftArm: −1.54, −1.22, −2.95; RightArm: +1.65, −1.22, −2.95); oriented to face the -Z camera direction
- `MuzzleAttachment` (Attachment) added to the most-forward barrel tip part at local Position (0, 0, −halfZ); used by `GetBarrelTipCFrame()` for muzzle flash placement
- 29 WeldConstraints created (Root→each BasePart) so `PivotTo` on Root moves the entire assembly
- Total descendants: 86 (30 BaseParts + 29 WeldConstraints + 1 Attachment + other children)

**Updated — `src/client/ViewModelController.lua`**
- Header comment updated: describes AR15 clone path and fallback
- `REAL_MODEL_OFFSET = CFrame.new(0, 0, 0)` added — Root is the camera-local origin; gun geometry offset is baked into part positions
- `PLACEHOLDER_OFFSET = CFrame.new(0.6, -0.5, -1.5)` added (renamed from the old `BASE_OFFSET` constant)
- `BASE_OFFSET` is now a mutable local variable set by `init()` based on which path loaded
- `init()` updated: first attempts `ReplicatedStorage:FindFirstChild("ViewModels").AR15:Clone()`; if found, hides all BaseParts (Transparency=1) before parenting to prevent a one-frame position flash, sets `BASE_OFFSET = REAL_MODEL_OFFSET`, returns early; if missing, logs `Logger.warn` and falls through to the existing programmatic placeholder path with `BASE_OFFSET = PLACEHOLDER_OFFSET`
- `Start()` guard comment updated to reflect that init() now has an external-asset path

**Updated — `src/shared/WeaponData.lua`**
- `WeaponData["AR15"]` updated: `damage=28` (was 25), `fireRate=0.09` (was 0.1), `range=450` (was 300), `magazineSize=30` (unchanged), `reserveAmmo=120` (was 90), `reloadTime=2.2` added (not yet read by GunService — see DEBT-030)
- Comment updated to identify AR15 as the active viewmodel weapon
- `WeaponData["SCAR"]` retained as a secondary definition

**Updated — `src/client/GunController.lua`**
- `CURRENT_WEAPON` changed from `"SCAR"` to `"AR15"`

**Updated — `src/server/GunService.server.lua`**
- `DEFAULT_WEAPON` changed from `"SCAR"` to `"AR15"`

### Debt evaluation

- **DEBT-013** (weapon name hardcoded): **updated** — both hardcodes changed from `"SCAR"` to `"AR15"` to match the active viewmodel; names are now in sync; structural problem (no weapon name in payload) remains unresolved; entry updated with history
- **DEBT-029** (setVisibility every tick): **worsened slightly** — real model has 30 BaseParts vs placeholder's 4; still well below the 50-part trigger threshold; entry updated with new part count
- **DEBT-030** (new): `WeaponData.reloadTime` stored but not read by GunService; see entry

### Test steps

1. Press Play in Studio. In Output, confirm `[ViewModelController] AR15 model cloned from ReplicatedStorage` (not the placeholder warning).
2. Start a round so phase reaches ACTIVE. Confirm the AR15 gun mesh appears in the lower-right corner of the first-person view, arms visible on both sides.
3. Fire (left-click). Confirm gun snaps back briefly (recoil) and muzzle flash sphere appears at the barrel tip.
4. Check ammo HUD — magazine starts at 30, decrements per shot.
5. Press R to reload — magazine refills from 120 reserve.
6. Kill another player — hitmarker appears and kill appears in kill feed.
7. Round ends (RESULTS phase) — viewmodel hides (all parts Transparency=1).
8. New round begins (ACTIVE) — viewmodel reappears.
9. Die and respawn — viewmodel rebuilds cleanly on CharacterAdded; no orphan models in CurrentCamera.

---

## [2026-05-12] — Fix viewmodel visibility bug, sync codebase, UI redesign, fix sound IDs

### Task 1 — Fix ViewModelController visibility bug

**Updated — `src/client/ViewModelController.lua`**
- `init()`: added `visible = false` after `self.model = container` — resets module-level state on every re-init so the next RoundStateChanged always calls setVisibility, even if the phase hasn't changed since the previous character load; note: the remote branch independently implemented this same fix and the guard removal before our commit was rebased
- `setVisibility()`: added `Logger.debug(string.format("[ViewModelController] setVisibility(%s)", tostring(show)))` at the top so every show/hide call is traceable in Output
- `RoundStateChanged` listener: removed `if show ~= visible then` guard — setVisibility now fires unconditionally on every phase update; eliminates the entire class of state-mismatch bugs where stale `visible` prevents the new model from being shown
- `BASE_OFFSET`: `CFrame.new(0.6, -0.5, -1.5)` (placeholder-appropriate; no model-specific compensation needed for programmatic geometry)

**Debt evaluation**
- DEBT-027 (WaitForChild blocks forever): **deleted** — WaitForChild no longer used; programmatic placeholder needs no external assets
- DEBT-028 (BASE_OFFSET hardcoded per model): **deleted** — programmatic placeholder uses geometry-neutral offset; per-weapon offset concern deferred until production model
- Added DEBT-029: setVisibility now called every tick instead of only on transitions; see entry for resolution path

### Task 2 — Codebase sync

**Updated — `src/shared/Constants.lua`**
- Added `WALK_SPEED = 16` and `SPRINT_SPEED = 24` (reserved for MovementController)
- Updated `DEATH_OVERLAY_OPACITY` from `0.6` to `0.75` (matches redesigned DeathScreen spec)
- Updated `KILLFEED_FADE_TIME` from `0.4` to `0.3` (matches redesigned KillFeedUI spec)
- Updated team Color3 values to desaturated palette: `COLOR_TEAM_ATTACKERS = Color3.fromRGB(200, 60, 60)`, `COLOR_TEAM_DEFENDERS = Color3.fromRGB(60, 120, 200)`, `COLOR_TEAM_NEUTRAL = Color3.fromRGB(160, 160, 160)`
- Added `AMMO_LOW_THRESHOLD = 5` — magazine count at or below which the ammo number turns amber in HUD

**Updated — `src/shared/WeaponData.lua`**
- Removed duplicate `WeaponData["SCAR"]` entry (a second identical definition was appended by a prior edit; only one SCAR entry now exists)
- Second entry retained as `WeaponData["AR15"]` (formerly `"AssaultRifle"` comment; not the active weapon)

All priority server files (MatchService, GunService, TeamService) were read and confirmed complete against the CHANGELOG. No code changes required.

### Task 3 — UI redesign (all five UI files rewritten)

**Design system used across all files:**
- Panel background: `Color3.fromRGB(10, 10, 10)` at 0.6 transparency
- Primary text: white, `GothamBold`
- Secondary text: `Color3.fromRGB(160, 160, 160)`, `Gotham`
- Attacker accent: `Color3.fromRGB(200, 60, 60)`
- Defender accent: `Color3.fromRGB(60, 120, 200)`
- Warning/amber: `Color3.fromRGB(220, 160, 40)`
- No rounded corners, no drop shadows; sharp rectangles only
- All transitions via TweenService

**Rewritten — `src/client/UI/HUD.lua`**
- Bottom-left health cluster: `HEALTH` grey label (size 11) above bar; 220×6 px white fill bar with amber below 50% and red below 25% (tweened); health number white bold size 14 right of bar; `ATK: N | DEF: N` grey size 11 below bar with team accent colours via RichText
- Bottom-right ammo block: magazine number white bold size 28 centered; thin grey divider; reserve size 14 grey centered; `SCAR` size 10 grey below
- Magazine colour: amber at ≤5 rounds (`AMMO_LOW_THRESHOLD`), red at 0
- Magazine pulse: `UIScale` 1.0 → 1.15 → 1.0 over 0.1s (two sequential 0.05s tweens) on every `AmmoChanged` event

**Rewritten — `src/client/UI/MatchUI.lua`**
- Top-center bar 300×32 px: phase label grey size 11 (left), round label white bold size 13 (center), timer white bold size 13 (right)
- Round-end overlay 400×80 px centered: winner text size 22 in team accent colour; score grey size 13
- Match-end overlay full-screen: `MATCH COMPLETE` grey size 12; winner size 28 in team accent; final score white size 16
- Winner colour determined by team name from payload

**Rewritten — `src/client/UI/CrosshairUI.lua`**
- Four bars: 2×12 px, pure white, 6 px gap from center, ZIndex 10; no center dot
- Hitmarker: four diagonal bars 2×10 px, `Color3.fromRGB(220, 60, 60)`, rotated ±45°; appears instantly at full opacity, fades to transparent over 0.08s via TweenService after 0.12s hold; bars are individual frames tweened separately (not a container visibility toggle)

**Rewritten — `src/client/UI/KillFeedUI.lua`**
- Entry: outer wrapper Frame (UIListLayout child, 260×24 px) with `ClipDescendants = true`; inner panel frame slides in from right over 0.15s (QuadOut tween)
- `UIStroke` border on each panel: 1px, `Color3.fromRGB(60, 60, 60)`
- Format: `[KillerName] › [VictimName]` in RichText; killer in team accent, `›` in grey, victim in team accent; Font Gotham size 12
- Environment kills: `✦ › [VictimName]`
- Fade-out: 0.3s linear after `KILLFEED_DISPLAY_TIME`, then destroy wrapper

**Rewritten — `src/client/UI/DeathScreen.lua`**
- Black overlay tweened to 0.75 opacity over 0.8s
- After 0.4s: `E L I M I N A T E D` white GothamBold size 24; `ELIMINATED BY [Name]` grey size 13; `STANDBY FOR NEXT ROUND` grey size 11 with infinite TweenService pulse (RepeatCount -1, Reverses true, 0.75s) cycling opacity 1.0 → 0.4 → 1.0
- Clears on PREP with 0.5s fade out; pulse tween cancelled on hide
- Text appears at 0.4s (not `DEATH_FADE_TIME`) to allow the overlay to partially settle first

### Task 4 — Sound asset IDs

**Updated — `src/client/SoundController.lua`**
- `ID_GUNSHOT`:  `rbxassetid://9118294910`
- `ID_HIT`:      `rbxassetid://9118294928`
- `ID_RELOAD`:   `rbxassetid://9118294935`
- `ID_DEATH`:    `rbxassetid://9118294942`
- `ID_DRYFIRE`:  `rbxassetid://9118294950`

**Debt evaluation (all open entries)**
- DEBT-001 (Phase sync): unaffected
- DEBT-003 (lastFiredPhase): unaffected
- DEBT-004 (team BrickColors): unaffected — Color3 values now updated to desaturated palette in Constants
- DEBT-005 (odd player split): unaffected
- DEBT-007 (RoundStateChanged fan-out): unaffected — listener count remains 6
- DEBT-009 (friendly-fire): unaffected
- DEBT-010 (health reset timing): unaffected
- DEBT-011 (on-demand team query): unaffected
- DEBT-013 (weapon name hardcoded): unaffected
- DEBT-014 (clientTick not validated): unaffected
- DEBT-017 (ClientInit count): unaffected — still 9 entries
- DEBT-018 (getPlayerFromPart duplicated): unaffected
- DEBT-019 (CharacterAutoLoads): unaffected
- DEBT-020 (team name strings): unaffected
- DEBT-022 (ragdoll cleanup): unaffected
- DEBT-023 (non-standard rig): unaffected
- DEBT-024 (sound pooling): unaffected — IDs updated but pooling not yet added
- DEBT-026 (ammo mid-round joiners): unaffected
- Added DEBT-029: setVisibility no longer guarded (see entry)

## [2026-05-12] — Add formatting and diff hygiene rule to CLAUDE.md

**Updated — `CLAUDE.md`**
- Added **Formatting and diff hygiene** rule to the Claude behavior section: global formatter (`stylua src/`) must not be run unless explicitly requested; format only files touched by the current task; keep diffs small and focused; preserve style of untouched files

**Updated — `docs/TECHNICAL_DEBT.md`**
- Added DEBT-032: documents that global StyLua passes are intentionally deferred to avoid noisy diffs; records the policy and the condition under which a full-repo format would be acceptable

---

## [2026-05-12] — Add object pooling, connection cleanup, and API validation rules to CLAUDE.md

**Updated — `CLAUDE.md`**
- Added **Object pooling** rule: frequently created/destroyed instances (muzzle flash, impact effects, debris, floating text) must use an object pool instead of `Instance.new()` per event; when a second pooled type is needed, create `src/shared/ObjectPool.lua` as the shared pool module
- Added **Connection cleanup** rule: all `RBXScriptConnection`s created inside a service or controller must be stored in a local array; on system reset (phase change, round end) or player leave, every connection must be `Disconnect()`ed and the array cleared; no active connections may point to removed players, destroyed instances, or finished rounds
- Added **Public API validation** rule: every public function accepting required parameters must call `assert()` with a descriptive message before any other logic, to prevent silent failures from bad callers and make errors immediately traceable

---

## [2026-05-10] — Fix ViewModelController visibility state bug on model rebuild

**Updated — `src/client/ViewModelController.lua`**
- `init()`: added `visible = false` after `self.model = container` — resets the module-level visibility flag to match the newly built model's actual state (all parts at Transparency 1); without this, if `visible` was `true` when `init()` ran (e.g. respawn during ACTIVE), the new model would stay invisible forever
- `setVisibility`: added `local count = 0` counter that increments per BasePart; added `Logger.debug(string.format(...))` call after the loop reporting the show value and part count — confirms the function is being called and how many parts it touched
- `RoundStateChanged` listener: removed the `if show ~= visible then` guard; now always calls `setVisibility(show)` unconditionally — eliminates the entire class of state-mismatch bugs where stale `visible` prevents the new model from being shown; minor extra transparency pass per phase change is negligible

**Debt evaluation**
- All open entries: unaffected

---

## [2026-05-10] — Fix placeholder viewmodel part positions to align arms with gun

**Updated — `src/client/ViewModelController.lua`**
- `GunBody`: size changed to `0.25 × 0.18 × 1.2`, CFrame offset `(0, 0, -0.3)` — centred in view, slightly forward of model pivot
- `Barrel`: size changed to `0.07 × 0.07 × 0.5`, CFrame offset `(0, 0.04, -0.9)` — thin barrel extending forward and raised slightly above gun body
- `RightArm`: size changed to `0.35 × 0.35 × 0.9`, BrickColor changed to `Pastel brown`, CFrame offset `(0.12, -0.22, 0.15)` — right hand at the grip, behind and below gun body
- `LeftArm`: size changed to `0.35 × 0.35 × 0.7`, BrickColor changed to `Pastel brown`, CFrame offset `(-0.05, -0.18, -0.45)` — left hand at the handguard, forward and below gun body
- `MuzzleAttachment` local position updated to `(0, 0, -0.25)` to match shorter barrel (0.5 length → tip at −0.25 local Z)
- `BASE_OFFSET` adjusted from `CFrame.new(0.6, -0.4, -1.5)` to `CFrame.new(0.6, -0.5, -1.5)` — shifts the whole viewmodel 0.1 studs lower on screen to match the new part layout
- `makePart` helper signature changed from `position: Vector3` to `cf: CFrame` so rotation can be added per-part in future without changing the helper

**Debt evaluation**
- All open entries: unaffected

---

## [2026-05-10] — Revert viewmodel to programmatic placeholder while proper model is sourced

**Updated — `src/client/ViewModelController.lua`**
- `init()` rebuilt from scratch: no longer clones from `ReplicatedStorage/ViewModels/SCAR`; all geometry is now created programmatically in code
- Creates a `Model` named `ViewModelPlaceholder` parented to `workspace.CurrentCamera`
- Parts built inside the model: `GunBody` (0.3 × 0.2 × 1.4, dark grey), `Barrel` (0.08 × 0.08 × 0.6, dark grey, 0.7 studs forward from body centre), `LeftArm` (0.4 × 0.4 × 1.2, Light orange, offset left/below), `RightArm` (same, offset right/below)
- All parts: `CanCollide false`, `CanQuery false`, `CastShadow false`, `Anchored false`, `Transparency 1` on creation
- `MuzzleAttachment` added at barrel front tip `(0, 0, −0.3)` in barrel local space
- `BASE_OFFSET` changed to `CFrame.new(0.6, -0.4, -1.5)` (placeholder-appropriate, no model-specific compensation needed)
- `setVisibility` simplified: no longer special-cases `HumanoidRootPart` / `FakeCamera` (placeholder has no such parts)
- Removed all `WaitForChild("ViewModels")` and `WaitForChild("SCAR")` calls — no external asset dependency
- `ReplicatedStorage` import retained (still needed for Modules and Remotes)
- All show/hide, `PivotTo`, camera-lock, `CharacterAdded`, `PlayFireAnimation`, and `GetBarrelTipCFrame` logic unchanged

**Debt evaluation**
- DEBT-021 (model cleanup on re-init): unaffected — `init()` destroy-before-create guard still present; entry remains resolved
- DEBT-027 (WaitForChild blocks forever): **deleted** — WaitForChild no longer used in `init()`; the entry is now moot
- DEBT-028 (BASE_OFFSET hardcoded per model): **deleted** — programmatic placeholder uses a geometry-neutral offset; per-weapon offset concern does not apply until a production model with a non-standard pivot is introduced

---

## [2026-05-10] — Fix camera mode, viewmodel cleanup on respawn, gun position offset

**Updated — `src/client/ViewModelController.lua`**
- `Start()`: applies `Enum.CameraMode.LockFirstPerson` to `Players.LocalPlayer` immediately on init, preventing the camera from reverting to third-person
- `Start()`: connects `localPlayer.CharacterAdded` — on each respawn, calls `self:init()` (destroys old model, clones fresh SCAR from ReplicatedStorage) then re-applies `LockFirstPerson`; this handles `player:LoadCharacter()` calls from TeamService at the start of every PREP
- `setVisibility` and `RenderStepped` closures now read `local m = self.model` per-call instead of capturing `local model` at `Start()` time, so the fresh clone after each respawn is automatically picked up
- `BASE_OFFSET` changed from `CFrame.new(0.6, -0.4, -1.2)` to `CFrame.new(3.2, 0.9, -1.2)` to compensate for the Troy Defense AR model's internal geometry layout (~2.6 studs right and ~1.3 studs down relative to the model pivot)
- Added `local Players = game:GetService("Players")` import (required for LocalPlayer and CharacterAdded)

**Debt evaluation**
- DEBT-007 (multiple RoundStateChanged listeners): unaffected — count unchanged
- DEBT-013 (weapon name hardcoded): unaffected
- DEBT-021 (model cleanup on re-init): unaffected — already resolved; `init()` guard still present
- DEBT-027 (WaitForChild timeout): unaffected — already resolved; timeout still in place
- DEBT-028 (BASE_OFFSET hardcoded per-model): **introduced** — see DEBT-028 entry

---

## [2026-05-07] — Update ViewModelController for Troy Defense AR model structure

**Updated — `src/client/ViewModelController.lua`**
- `setVisibility(show)` in `Start()`: when hiding (show=false), all BaseParts set to Transparency=1 as before; when showing (show=true), all BaseParts set to Transparency=0 **except** parts named `HumanoidRootPart` or `FakeCamera`, which always remain at Transparency=1 — these are the physics anchor and camera reference part, not visual geometry
- `Start()`: added nil guard after `self:init()` — if the model failed to load (DEBT-027 early-return path), `Start()` now returns cleanly instead of casting a nil `self.model` to `Model` and crashing; other controllers continue initializing normally

**Debt evaluation**
- All open entries: unaffected

---

## [2026-05-07] — Fix DEBT-027: add WaitForChild timeout for SCAR model

**Updated — `src/client/ViewModelController.lua`**
- `init()`: replaced bare `WaitForChild("ViewModels")` with `WaitForChild("ViewModels", 10)` + nil check + `Logger.warn` + early return
- `init()`: replaced bare `WaitForChild("SCAR")` with `WaitForChild("SCAR", 10)` + nil check + `Logger.warn` + early return
- A missing folder or model now prints an actionable warning in Output and returns cleanly instead of blocking ClientInit forever

**Debt evaluation**
- DEBT-027 (WaitForChild blocks forever): **resolved** — both calls now time out after 10 s with loud warnings; entry marked resolved

---

## [2026-05-07] — Replace block viewmodel with SCAR model using PivotTo

**Model attachment:** `ViewModelController:init()` clones `ReplicatedStorage/ViewModels/SCAR` and parents it to `workspace.CurrentCamera`. `RenderStepped` calls `model:PivotTo(camera.CFrame * CFrame.new(0.6, -0.4, -1.2) * CFrame.new(0, 0, recoilOffset))` every frame, keeping the model locked to the camera. No PrimaryPart is required — `PivotTo` repositions by the model's geometric pivot.

**Updated — `src/client/ViewModelController.lua`**
- Replaced the three hand-built Parts (`gunBody`, `barrel`, `grip`) and `makePart()` helper with a single cloned Model stored as `self.model` (table field, typed `Model?`)
- Added `ViewModelController:init()`: destroys any existing `self.model` (re-init safe), calls `ReplicatedStorage:WaitForChild("ViewModels"):WaitForChild("SCAR")`, clones the model, parents clone to `workspace.CurrentCamera`, hides all `BasePart` descendants via `GetDescendants()` / `IsA("BasePart")` / `Transparency = 1`
- `Start()` calls `self:init()` first, then narrows `self.model` to non-nil `Model`, registers `RoundStateChanged` phase listener and `RenderStepped` loop
- `RenderStepped`: replaced three individual `Part.CFrame` assignments with `model:PivotTo(cam.CFrame * BASE_OFFSET * CFrame.new(0, 0, recoilOffset))`; skipped entirely when `visible == false`
- `setVisibility(show)`: iterates `model:GetDescendants()` / `IsA("BasePart")` to set `Transparency`; called only on phase changes (not per-frame)
- Visibility rule unchanged: shown only during `ACTIVE`, hidden during all other phases
- `PlayFireAnimation()`: sets `recoilOffset = RECOIL_DIST`, then immediately applies `model:PivotTo(model:GetPivot() * CFrame.new(0, 0, recoilOffset))` for a same-frame snap; `RenderStepped` decays `recoilOffset` back to 0 over 0.05 s
- `GetBarrelTipCFrame()`: uses `model:FindFirstChild("MuzzleAttachment", true)` → `CFrame.new(attachment.WorldPosition)`; falls back to `CFrame.new(cam.CFrame.Position + cam.CFrame.LookVector * 1.5)` with `Logger.warn` if attachment is missing
- Removed: `VM_COLOR`, `BARREL_CENTER_OFFSET`, `BARREL_TIP_OFFSET`, `GRIP_OFFSET`, `makePart()`, `local gunBody/barrel/grip`

**Updated — `src/shared/WeaponData.lua`**
- Added `WeaponData["SCAR"] = { damage=30, fireRate=0.1, range=400, magazineSize=20, reserveAmmo=100 }`
- Retained `WeaponData["AssaultRifle"]` as a fallback definition (not the active weapon)

**Updated — `src/server/GunService.server.lua`**
- `DEFAULT_WEAPON` changed from `"AssaultRifle"` to `"SCAR"`

**Updated — `src/client/GunController.lua`**
- `CURRENT_WEAPON` changed from `"AssaultRifle"` to `"SCAR"`

**Debt evaluation**
- DEBT-013 (weapon name hardcoded): **worsened** — WeaponData now has two named entries; mismatch between the two hardcoded strings would silently apply wrong stats (damage 25→30, range 300→400, mag 30→20); entry updated
- DEBT-021 (ViewModelController no cleanup on double-Start): **resolved** — `init()` destroys previous `self.model` before cloning; three-Part orphaning risk eliminated; entry marked resolved
- DEBT-007 (RoundStateChanged fan-out): **unaffected** — still one listener in ViewModelController; count stays at 6
- Added DEBT-027: `WaitForChild("ViewModels")` / `WaitForChild("SCAR")` blocks forever if model is missing from ReplicatedStorage

---

## [2026-05-07] — Fix reload to discard magazine instead of topping off

**Updated — `src/server/GunService.server.lua`**
- `ReloadRequest` handler: replaced top-off logic (`needed = magazineSize - mag; pulled = min(needed, reserve); mag += pulled`) with full-discard logic (`pulled = min(magazineSize, reserve); mag = pulled; reserve -= pulled`)
- Concrete example added as a comment: 15 rounds in magazine, 70 in reserve → 30 in magazine, 40 in reserve; the 15 remaining rounds are permanently discarded
- The full-magazine guard (`mag >= magazineSize → early return`) is unchanged and correct: reloading a full magazine with the new logic would consume reserve rounds for zero gain

**Debt evaluation**
- All open entries: unaffected

---

## [2026-05-07] — Add kill feed UI

**Kill feed data flow:** `DamageService:killPlayer()` → `KillFeed:FireAllClients(killerName, victimName, killerTeam, victimTeam)` → `KillFeedUI:addEntry()` → top-right entry stack, fades after 4 s

**Updated — `src/shared/Constants.lua`**
- Added `KILLFEED_DISPLAY_TIME = 4` — seconds each entry is visible before fading
- Added `KILLFEED_FADE_TIME = 0.4` — seconds for the fade-out tween
- Added `TEAM_ATTACKERS = "Attackers"` and `TEAM_DEFENDERS = "Defenders"` — canonical team name strings (triggered by DEBT-020 fix condition: KillFeedUI is the third consumer)
- Added `COLOR_TEAM_ATTACKERS = Color3.fromRGB(255, 80, 80)`, `COLOR_TEAM_DEFENDERS = Color3.fromRGB(80, 140, 255)`, `COLOR_TEAM_NEUTRAL = Color3.fromRGB(220, 220, 220)` — centralized Color3 values for UI team tinting (triggered by DEBT-004 fix condition: KillFeedUI needs team colours)

**Updated — `src/server/RemoteSetup.server.lua`**
- Added `makeEvent("KillFeed")` in the "Teams / death tracking" section

**Updated — `src/server/DamageService.lua`**
- Added `KillFeed` remote reference at module level
- `killPlayer()`: after firing HealthChanged and applying ragdoll, fires `KillFeed:FireAllClients(killerDisplayName, victimDisplayName, killerTeamName, victimTeamName)`; `killerDisplayName` is `attacker.DisplayName` or `""` for environment kills; `killerTeamName` is `playerTeam[attacker]` or `""` if attacker has no recorded team (mid-round joiner or environment kill)
- Header comment updated to note KillFeed broadcast

**New file — `src/client/UI/KillFeedUI.lua`**
- `init(playerGui)`: creates ScreenGui "KillFeedUI" (`ResetOnSpawn=false`, `IgnoreGuiInset=true`, `DisplayOrder=5`); transparent container Frame anchored top-right (AnchorPoint=(1,0), 8 px inset, 260 px wide, `AutomaticSize=Y`); UIListLayout (Vertical, LayoutOrder sort, 2 px padding)
- `Start()`: connects `KillFeed.OnClientEvent` → calls `addEntry()`
- `addEntry(killerName, victimName, killerTeam, victimTeam)`: enforces max 5 entries (oldest `removeEntry()`d immediately when a 6th arrives); creates a 22 px Frame with semi-transparent black background; TextLabel with `RichText=true` showing `<font color="rgb(...)">KillerName</font> → <font color="rgb(...)">VictimName</font>` — team colours from `Constants.COLOR_TEAM_*`; environment kills show `✦ → VictimName` in neutral colour; schedules `task.delay(KILLFEED_DISPLAY_TIME)` → TweenService fades `BackgroundTransparency` and `TextTransparency` to 1 over `KILLFEED_FADE_TIME` → `removeEntry()` on tween completion
- `removeEntry(frame)`: removes frame from `entries` table by reference and calls `Destroy()`; guarded against double-destroy via `if not frame.Parent then return end` check in the delay callback

**Updated — `src/client/ClientInit.client.lua`**
- KillFeedUI inserted at position 5 (after DeathScreen, before CrosshairUI) using `loadInitAndStart`
- CrosshairUI shifts to 6, ViewModelController to 7, SoundController to 8, GunController to 9
- Header comment updated to 9-entry order

**Updated — `docs/PROJECT_MAP.md`**
- Added `KillFeed` row to remote registry (Fired by DamageService.lua, Listened by KillFeedUI.lua)
- Added `KillFeedUI` to Presentation section
- Updated `RagdollApplied` Listened-by to include `SoundController.lua` (correction from prior entry)
- Updated ClientInit order to 9 entries; added `loadInitNoGuiAndStart` to the helpers list

**Debt evaluation**
- DEBT-004 (team colours not in Constants): **further resolved** — `COLOR_TEAM_*` Color3 constants now in Constants.lua; KillFeedUI uses them; TeamService's BrickColor values remain local (outside task scope); entry updated with reasoning
- DEBT-007 (RoundStateChanged fan-out): **unaffected** — KillFeedUI listens to KillFeed, not RoundStateChanged; listener count stays at 6
- DEBT-017 (ClientInit manual update): **worsened** — 9 entries now; count updated
- DEBT-020 (team name strings duplicated): **partially resolved** — `TEAM_ATTACKERS`/`TEAM_DEFENDERS` added to Constants.lua; KillFeedUI uses them; TeamService and ObjectiveService still have local copies (outside task scope); entry updated

---

## [2026-05-07] — Add server-authoritative ammo system with reload

**Ammo flow:** `TeamAssigned` → `GunService.setupAmmo()` → `AmmoChanged` → `GunController` + `HUD` | `WeaponFired` → ammo check → decrement → `AmmoChanged` | `ReloadRequest` → validate → transfer → `AmmoChanged`

**Updated — `src/shared/WeaponData.lua`**
- Added `magazineSize = 30` and `reserveAmmo = 90` to the AssaultRifle entry; updated field comment

**Updated — `src/server/GunService.server.lua`**
- Added `AmmoChanged` and `ReloadRequest` remote references
- Added `playerMag: { [Player]: number }` and `playerReserve: { [Player]: number }` state tables
- Added `setupAmmo(player)` helper: reads `DEFAULT_WEAPON.magazineSize` and `.reserveAmmo`, populates both tables, fires `AmmoChanged` to the player
- Added `MatchEvents.TeamAssigned.Event` listener → calls `setupAmmo(player)` at PREP start for every player
- `WeaponFired` handler: after rate limit, checks `playerMag[shooter]` — nil (mid-round joiner) silently returns; 0 fires `AmmoChanged(0, reserve)` to re-sync client and returns; positive decrements by 1 and fires `AmmoChanged` before the raycast
- Added `ReloadRequest.OnServerEvent` handler: validates ACTIVE phase and non-nil ammo tables; rejects if reserve ≤ 0 or mag already full (fires AmmoChanged to sync); otherwise transfers `min(magazineSize - mag, reserve)` rounds from reserve to magazine and fires AmmoChanged
- `PlayerRemoving`: now also clears `playerMag[player]` and `playerReserve[player]`

**Updated — `src/server/RemoteSetup.server.lua`**
- Added `makeEvent("AmmoChanged")` and `makeEvent("ReloadRequest")` in the "Health & combat" section

**Updated — `src/client/GunController.lua`**
- Added `AmmoChanged` and `ReloadRequest` remote references at module level
- Added `currentMag` and `currentReserve` state variables (start at 0/0; updated exclusively by AmmoChanged)
- Dry fire check added in `InputBegan` before rate limit: `if currentMag <= 0 then SoundController:PlayDryFire() return end`
- Added second `InputBegan` connection for `Enum.KeyCode.R` in ACTIVE phase: fires `ReloadRequest:FireServer()` then calls `SoundController:PlayReload()` (optimistic sound; server validates)
- Added `AmmoChanged.OnClientEvent` listener: caches `currentMag` and `currentReserve`; logs the new values
- Added `GunController:GetAmmo(): (number, number)` getter returning cached magazine and reserve

**Updated — `src/client/UI/HUD.lua`**
- Added `AmmoChanged` remote reference
- Added `ammoFrame` (130×44 px, bottom-right corner, same semi-transparent black style as health frame) and `ammoLabel` (right-aligned, 22 pt GothamBold, white) created in `init()`; initial text `"— / —"` until first AmmoChanged
- Added `setAmmo(mag, reserve)` helper: formats label as `"30 / 90"` etc.
- Added `AmmoChanged.OnClientEvent` listener in `Start()` → calls `setAmmo()`
- `RoundStateChanged` visibility handler updated: now also toggles `ammoFrame.Visible` alongside `hudFrame.Visible`

**Updated — `docs/PROJECT_MAP.md`**
- Added `AmmoChanged` and `ReloadRequest` rows to remote registry; updated `HitConfirmed` Listened-by to include `SoundController.lua`; updated HUD Presentation entry to include AmmoChanged

**Debt evaluation**
- DEBT-013 (hardcoded weapon name): **worsened** — ammo system adds a third hardcoded lookup point (`setupAmmo` and reload handler both use `DEFAULT_WEAPON`); entry updated
- DEBT-025 (DryFire no asset): **actively triggered** — GunController now calls `PlayDryFire()` on empty magazine; warning fires every playtest; entry updated with urgency
- DEBT-026 (new): ammo not initialized for mid-ACTIVE joiners; nil guard in WeaponFired silently blocks their shots; no crash, no functional impact today but will matter if reinforcement system is added
- All other entries: unaffected

---

## [2026-05-07] — Add sound system with gunshot, hit, reload, death sounds

**New file — `src/client/SoundController.lua`**
- `init()`: creates `SoundService/GameSounds/` folder; creates five `Sound` instances inside it: Gunshot (`rbxassetid://4792534948`, vol 0.6), HitConfirm (`rbxassetid://4612378292`, vol 0.8), Reload (`rbxassetid://3900723713`, vol 0.7), Death (`rbxassetid://3900724014`, vol 0.8), DryFire (no asset assigned yet, vol 0.5). All sounds have `RollOffMaxDistance = 0` (flat/non-positional — correct for local-player feedback)
- `Start()`: connects `HitConfirmed.OnClientEvent` → `PlayHit()`; connects `RagdollApplied.OnClientEvent` → `PlayDeath()` when `userId == LocalPlayer.UserId`. The death sound plays through DeathScreen's EQ muffle (DeathScreen connects first; EQ is active before PlayDeath fires)
- Public API: `PlayGunshot()`, `PlayHit()`, `PlayDryFire()` (logs warning, no-ops until DEBT-025 resolved), `PlayReload()`, `PlayDeath()`
- Volume and asset ID values are named local constants at module level (cannot go in Constants.lua per task scope restriction; move there when a second caller needs them)

**Updated — `src/client/GunController.lua`**
- Added module-level `require(SoundController)` alongside existing ViewModelController and CrosshairUI requires
- Added `SoundController:PlayGunshot()` call immediately after `WeaponFired:FireServer()` in the input handler (cosmetic, no server impact)

**Updated — `src/client/ClientInit.client.lua`**
- Added `loadInitNoGuiAndStart()` helper — for modules that have `init()` (no playerGui argument) followed by `Start()`; fills the gap between `loadAndStart` (no init) and `loadInitAndStart` (init with playerGui)
- SoundController inserted at position 7 using `loadInitNoGuiAndStart`; GunController shifts to position 8
- Header comment updated to 8-entry order; dependency note updated (GunController now requires ViewModelController, CrosshairUI, AND SoundController)

**Debt evaluation**
- DEBT-007 (RoundStateChanged fan-out): **unaffected** — SoundController connects to HitConfirmed and RagdollApplied, not RoundStateChanged
- DEBT-017 (ClientInit manual update): **worsened** — 8 entries now; count updated
- Added DEBT-024: single Sound instances have no audio pooling; rapid PlayGunshot() calls restart instead of overlap
- Added DEBT-025: DryFire has no asset ID; PlayDryFire() is a no-op until the ammo system is built

---

## [2026-05-07] — Add ragdoll system and death screen with blur and audio muffling

**Death pipeline overview:** `DamageService:killPlayer()` → `RagdollService:Apply()` → `humanoid.Health = 0` → `Humanoid.Died` (TeamService alive tracking, unchanged) + `RagdollApplied:FireAllClients()` (DeathScreen client trigger)

**New file — `src/server/RagdollService.lua`**
- `RagdollService:Apply(character, victim, attacker)` called by DamageService when health reaches 0
- Iterates `character:GetDescendants()` for all `Motor6D` instances; for each: creates two `Attachment` instances in `Part0` (CFrame = `C0`) and `Part1` (CFrame = `C1`), creates a `BallSocketConstraint` linking them (`LimitsEnabled = true`, `UpperAngle = 45`), then sets `Motor6D.Enabled = false`
- Sets `humanoid.PlatformStand = true` (stops Humanoid from counteracting physics) then `humanoid.Health = 0` (fires `Humanoid.Died` → TeamService still handles alive tracking with no changes)
- Fires `MatchEvents.PlayerDied:Fire(victim, killerName)` for future consumers (RewardService, CorpseService)
- Fires `RagdollApplied:FireAllClients(victim.UserId, killerName)` — `killerName` is `attacker.DisplayName` or `""` for environment kills
- Warns if no Motor6Ds found (non-standard rig) or if Part0/Part1 is nil on any joint

**Updated — `src/server/DamageService.lua`**
- Added `require(RagdollService)` at module level
- `killPlayer()` now calls `RagdollService:Apply(character, player, attacker)` instead of directly setting `humanoid.Health = 0`; logs a warning and skips ragdoll if `player.Character` is nil at kill time
- Header comment updated to reflect that character is no longer destroyed

**Updated — `src/server/MatchEvents.lua`**
- Added `MatchEvents.PlayerDied = Instance.new("BindableEvent")` — payload: `(player: Player, killerName: string)` — for future server-side listeners that want a named death signal without relying on `Humanoid.Died`

**Updated — `src/server/RemoteSetup.server.lua`**
- Added `makeEvent("RagdollApplied")` in the "Teams / death tracking" section

**New file — `src/client/UI/DeathScreen.lua`**
- `init(playerGui)`: creates ScreenGui "DeathScreen" (`ResetOnSpawn=false`, `IgnoreGuiInset=true`, `DisplayOrder=10`); full-screen black overlay Frame (starts `BackgroundTransparency=1`); centered text container (hidden by default) with "YOU DIED" (GothamBold, large, white), "Eliminated by [Name]" (Gotham, red, hidden if no killer), "Waiting for next round..." (Gotham, grey)
- `Start()`: connects `RagdollApplied.OnClientEvent` — if `userId == LocalPlayer.UserId`, calls `showDeathUI(killerName)`: creates `BlurEffect` in `game.Lighting` (Size 0 → 24 via TweenService), creates `EqualizerSoundEffect` in `SoundService` (`LowGain=Constants.DEATH_EQ_LOW_GAIN`, `MidGain=Constants.DEATH_EQ_MID_GAIN`, `HighGain=Constants.DEATH_EQ_HIGH_GAIN`), tweens overlay `BackgroundTransparency` from 1 to `1-DEATH_OVERLAY_OPACITY` (0.4), shows text container after `DEATH_FADE_TIME` seconds via `task.delay`
- Connects `RoundStateChanged.OnClientEvent` — on PREP: calls `hideDeathUI()` which hides text, tweens overlay back to transparent, tweens blur Size back to 0 then destroys `BlurEffect`, destroys `EqualizerSoundEffect` after cleanup tween
- Active tween is cancelled before any new tween starts to prevent overlap on rapid phase changes

**Updated — `src/shared/Constants.lua`**
- Added 7 death screen constants: `DEATH_FADE_TIME = 0.8`, `DEATH_OVERLAY_OPACITY = 0.6`, `DEATH_BLUR_SIZE = 24`, `DEATH_CLEANUP_TIME = 0.5`, `DEATH_EQ_LOW_GAIN = 0`, `DEATH_EQ_MID_GAIN = -50`, `DEATH_EQ_HIGH_GAIN = -60`

**Updated — `src/client/ClientInit.client.lua`**
- DeathScreen inserted at position 4 (after HUD, before CrosshairUI); uses `loadInitAndStart()`
- Header comment updated: 7-entry order documented

**Updated — `docs/PROJECT_MAP.md`**
- Added `RagdollApplied` row to remote registry (Fired by RagdollService, Listened by DeathScreen)
- Added `DeathScreen` to Presentation section
- Updated ClientInit order to 7 entries

**Debt evaluation**
- DEBT-007 (RoundStateChanged fan-out): **worsened** — now 6 listeners; entry updated with new count
- DEBT-009 (no friendly-fire guard): **unaffected**
- DEBT-010 (health reset vs mid-respawn): **partially mitigated** — characters stay ragdolled rather than being respawned, reducing the timing window; structural risk remains
- DEBT-017 (ClientInit manual update): **worsened** — 7 entries now; entry updated with current count
- Added DEBT-022: ragdolled characters have no cleanup owner until CorpseService is built; corpses accumulate across rounds
- Added DEBT-023: Motor6D ragdoll conversion assumes standard R15/R6 rig; custom rigs untested

---

## [2026-05-07] — Sync all documentation to current codebase state

**`docs/ROADMAP.md`**
- Stage 2: checked off MatchController, TeamService, ObjectiveService; updated descriptions to reflect actual implementation (win-condition tallying, alive-count tracking, per-player touch counting)
- Stage 3: split "Basic UI" into three separate entries — HUD (checked), MatchUI (checked), ObjectiveUI (unchecked, not yet built)
- Stage 4: checked off GunService, GunController, DamageService; added ViewModelController+CrosshairUI as a checked entry; MovementController remains unchecked

**`docs/PROJECT_MAP.md`**
- Presentation section: added `CrosshairUI` (driven by RoundStateChanged, exposes ShowHitmarker()) and `ViewModelController` (driven by RoundStateChanged, exposes PlayFireAnimation()/GetBarrelTipCFrame()); corrected HUD driven-by list from AmmoChanged to TeamStatusUpdate; added ObjectiveComplete to ObjectiveUI driven-by list

No code changes in this entry. Remote registry, ClientInit order, and debt entries were already up to date from prior sessions.

---

## [2026-05-07] — Add viewmodel, crosshair, hitmarker, muzzle flash

**Part 1 — ViewModelController (`src/client/ViewModelController.lua`, new)**
- Creates three Parts (GunBody 0.8×0.2×0.5, Barrel 0.08×0.6×0.08 with Cylinder SpecialMesh, Grip 0.15×0.25×0.15) parented to `workspace.CurrentCamera` in `Start()`
- All parts: `Anchored=false`, `CanCollide=false`, `CastShadow=false`, `BrickColor="Dark grey"`
- `RunService.RenderStepped` updates GunBody CFrame to `camera.CFrame * CFrame.new(0.6, -0.4, -1.2) * CFrame.new(0, 0, recoilOffset)` every frame; Barrel and Grip follow with fixed offsets
- Visibility toggled by `RoundStateChanged` — shown only during `ACTIVE`, hidden in all other phases
- `PlayFireAnimation()`: sets `recoilOffset = 0.05`; RenderStepped decays it back to 0 at 1 stud/sec (returns in 0.05 s)
- `GetBarrelTipCFrame()`: returns `gunBody.CFrame * CFrame.new(0, 0.04, -0.85)` — the muzzle world CFrame used by GunController for flash placement

**Part 2 — CrosshairUI (`src/client/UI/CrosshairUI.lua`, new)**
- Creates a ScreenGui "CrosshairUI" (`ResetOnSpawn=false`, `IgnoreGuiInset=true`) in `init(playerGui)`
- Crosshair: four white Frames (2×10 px top/bottom, 10×2 px left/right) with 4 px gap and `AnchorPoint=(0.5, 0.5)`; container hidden until `Start()` receives a phase
- Hitmarker: four white 2×10 px Frames placed diagonally (NE, NW, SE, SW — ±8 px from center, rotated ±45°) forming an X; hidden by default
- `Start()` connects `RoundStateChanged` — crosshair shown during `PREP` and `ACTIVE` only
- `ShowHitmarker()`: sets hitmarker container visible, hides it after 0.1 s via `task.delay`

**Part 3 — GunController (`src/client/GunController.lua`, updated)**
- Added module-level requires: `ViewModelController` (sibling) and `CrosshairUI` (`UI/CrosshairUI`)
- After `WeaponFired:FireServer()`: calls `ViewModelController:PlayFireAnimation()`, then creates a 0.3-stud Neon bright-yellow Sphere Part (SpecialMesh) at `ViewModelController:GetBarrelTipCFrame()` parented to `workspace.CurrentCamera`, destroyed after 0.05 s via `task.delay`
- `HitConfirmed` listener: now calls `CrosshairUI:ShowHitmarker()` before the existing `Logger.debug("HIT")` call
- No changes to raycast, rate-limiting, phase gate, or server fire logic

**Part 4 — ClientInit (`src/client/ClientInit.client.lua`, updated)**
- New initialization order: MatchController → MatchUI → HUD → CrosshairUI → ViewModelController → GunController
- CrosshairUI uses `loadInitAndStart()` (needs PlayerGui); ViewModelController uses `loadAndStart()` (no PlayerGui)
- Dependency comment updated: ViewModelController and CrosshairUI must start before GunController

**Debt evaluation**
- DEBT-007 (RoundStateChanged fan-out): **worsened** — now 5 listeners (MatchController, MatchUI, HUD, CrosshairUI, ViewModelController); entry updated with new count and escalated urgency
- DEBT-017 (ClientInit manual update): **worsened** — 2 more entries added (CrosshairUI, ViewModelController)
- All other open entries: unaffected
- Added DEBT-021: ViewModelController parts created once in `Start()` with no cleanup — second call would orphan the first set of parts

---

## [2026-05-07] — Batch 1: Constants, Types, RemoteSetup, Logger baseline audit

Confirmed and completed the shared-module baseline required before building further systems. Most values were already present from the previous session; the audit identified and filled one gap.

**`src/shared/Constants.lua`**
- Already present: `Phase.MATCHEND`, `MAX_HEALTH`, `ANCHOR_PLANT_TIME`, `COUNTDOWN_TICK`, `TELEPORT_Y_OFFSET`, `LOBBY_POLL_INTERVAL`, `MATCH_END_PAUSE`
- Added: `RESPAWN_DELAY = 5` — seconds before a player re-enters play at round start; reserved for the future reinforcement system, not yet consumed by any service

**`src/shared/Types.lua`**
- Already correct: `Phase` union includes all five values (`"LOBBY" | "PREP" | "ACTIVE" | "RESULTS" | "MATCHEND"`); `RoundStatePayload` already carries `winner`, `attackerWins`, `defenderWins`
- No changes made

**`src/server/RemoteSetup.server.lua`**
- Already present: `makeEvent("TeamStatusUpdate")`
- No changes made

**`src/shared/Logger.lua`**
- Already exists with `RunService:IsStudio()` DEBUG_MODE guard, `Logger.debug()`, `Logger.warn()`
- No changes made

**Debt evaluation**
- DEBT-001 (Phase type sync): updated to "partially resolved" — both files list the same five phases after MATCHEND was added; structural risk (no compiler enforcement) remains
- DEBT-016 (Logger DEBUG_MODE): confirmed fully resolved from prior session; no action needed

---

## [2026-05-07] — Four systems for first playtest: death tracking, win conditions, objectives, HUD + MatchUI

**System 1 — Death tracking (TeamService)**
- `Players.CharacterAutoLoads = false` set at the top of TeamService; Roblox never auto-spawns characters
- `player:LoadCharacter()` called for all players at the start of each PREP phase (concurrent)
- New state: `aliveAttackers`, `aliveDefenders`, `diedConnections: { [Player]: RBXScriptConnection }`, `currentPhase`
- `handlePlayerDied(player)`: removes the player from the alive table for their team, fires `TeamStatusUpdate:FireAllClients(attAlive, defAlive)`, and fires `MatchEvents.RoundEndedEarly` if one team is fully eliminated (simultaneous elimination → Defenders win as tiebreak)
- `setupDeathTracking()`: connects `Humanoid.Died` for every player at ACTIVE start; broadcasts initial alive counts; stores connections by player for clean disconnection
- `cleanupDeathTracking()`: disconnects all `Humanoid.Died` connections; called at RESULTS
- `PlayerRemoving`: disconnects the player's death connection; treats a mid-ACTIVE disconnect as a death via `handlePlayerDied()` before clearing tables
- `resetTeams()` updated to call `cleanupDeathTracking()` and use `table.clear()` for alive tables
- Added `TeamStatusUpdate` RemoteEvent to `RemoteSetup.server.lua`
- Added `MatchEvents.RoundEndedEarly = Instance.new("BindableEvent")` to `src/server/MatchEvents.lua`

**System 2 — Win conditions (MatchService)**
- Removed the old local `RoundEndedEarly` BindableEvent and `MatchService` table; early-end signals now flow through `MatchEvents.RoundEndedEarly` so TeamService and ObjectiveService can fire it
- New state: `currentWinner: string`, `attackerRoundWins: number`, `defenderRoundWins: number`
- `broadcast()` now includes `winner`, `attackerWins`, `defenderWins` in every `RoundStateChanged` payload
- `GetMatchConfig` returns the full payload including winner and win counts
- `countdown()` signature changed to `(phase, round, duration, listenForEarlyEnd?): (boolean, string)` — returns the winner string captured from `MatchEvents.RoundEndedEarly` when ended early
- `runActive()` returns `"Time Expired"` on normal completion or the winner team name on early end
- `runResults(round, winner)` sets `currentWinner` before broadcasting so RESULTS payloads carry the winner
- `runMatch()` resets win counts at match start, tallies wins per round ("Time Expired" counts as Defenders), determines the overall match winner (or "Draw"), broadcasts MATCHEND with `MATCHEND_DURATION`, then waits
- Added `Constants.MATCHEND` phase to `Constants.Phase`; "MATCHEND" added to `Types.Phase` union
- Added `Constants.RESULTS_DURATION = 10` and `Constants.MATCHEND_DURATION = 15` to `Constants.lua`

**System 3 — Objective capture (ObjectiveService)**
- New file `src/server/ObjectiveService.server.lua`
- Subscribes to `MatchEvents.TeamAssigned` to build a local `playerTeams` table; does not require TeamService directly (avoids cross-require and DEBT-011 timing risk)
- On ACTIVE: scans `Workspace/Objectives` for BaseParts and calls `registerObjective()` on each
- `registerObjective(part)`: creates an `ObjectiveState` record and connects `Touched`/`TouchEnded` with per-player touch counting (prevents body-part spam from causing false entry/exit)
- `startCapture(state, planter)`: spawns a task that ticks progress every `COUNTDOWN_TICK`; fires `ObjectiveUpdated:FireAllClients(part, progress)` each tick; exits cleanly if `state.planter` changes before `ANCHOR_PLANT_TIME` elapses
- `cancelCapture(state)`: clears planter and fires `ObjectiveUpdated` with progress 0
- `completeObjective(state)`: marks planted, fires `ObjectiveComplete:FireAllClients(part)`, checks if all objectives are planted, fires `MatchEvents.RoundEndedEarly("Attackers")` when they are
- `resetObjectives()`: disconnects all `Touched`/`TouchEnded` connections and clears the objectives table; called on PREP and RESULTS
- `PlayerRemoving`: clears `playerTeams` entry and cancels any in-progress capture by that player

**System 4 — MatchUI and HUD**
- `src/client/UI/MatchUI.lua` (new ModuleScript): creates a ScreenGui with a top bar (round/phase label + timer), a RESULTS overlay (winner + round scores), and a MATCHEND overlay (match winner + final scores); hidden during LOBBY; connects `RoundStateChanged.OnClientEvent` in `Start()`
- `src/client/UI/HUD.lua` (new ModuleScript): creates a ScreenGui with a bottom-left frame containing a health number, a colour-coded health bar (green → orange → red by ratio), and a team-alive-count label; connects `HealthChanged`, `TeamStatusUpdate`, and `RoundStateChanged` in `Start()`; hidden during LOBBY and MATCHEND
- `src/client/MatchController.lua`: added `currentWinner`, `currentAttackerWins`, `currentDefenderWins` state; `applyState()` reads these from the payload; added `GetWinner()`, `GetAttackerWins()`, `GetDefenderWins()` public getters
- `src/client/ClientInit.client.lua`: added `loadInitAndStart()` helper for UI modules that require `init(playerGui)` before `Start()`; added `Players.LocalPlayer:WaitForChild("PlayerGui")` reference; updated initialization order to: MatchController → MatchUI → HUD → GunController

**Debt evaluation**
- DEBT-003 (lastFiredPhase phase-only): unaffected — MatchService changes do not worsen or resolve it
- DEBT-007 (applyState growth): partially triggered — MatchUI and HUD connect directly to RoundStateChanged; updated entry to reflect the fan-out pattern and the planned BindableEvent fix
- DEBT-009 (no friendly-fire guard): unaffected
- DEBT-011 (no on-demand team query): ObjectiveService uses TeamAssigned subscription correctly; risk not triggered since all services start before the first PREP phase
- DEBT-017 (ClientInit manual update): worsened by two new UI entries; still acceptable at this controller count
- Added DEBT-018: `getPlayerFromPart` duplicated in DamageService and ObjectiveService
- Added DEBT-019: `Players.CharacterAutoLoads = false` set globally in TeamService with no fallback
- Added DEBT-020: `TEAM_ATTACKERS` / `TEAM_DEFENDERS` string literals duplicated across TeamService and ObjectiveService

---

## [2026-05-07] — Resolve DEBT-015: ClientInit pattern + controller ModuleScript conversion

**Part 1 — MatchController renamed**
- `src/client/MatchController.client.lua` → `src/client/MatchController.lua` — Rojo now creates a ModuleScript instance; `require()` from GunController resolves correctly
- Updated header comment from `-- LocalScript` to `-- ModuleScript`
- Removed the `MatchController:Start()` self-call at the bottom of the file — leaving it would have caused `Start()` to fire twice on first `require()` (once from the module tail, once from ClientInit), registering `RoundStateChanged.OnClientEvent` twice and causing double event delivery
- Added clarifying comment on `Start()`: called once by ClientInit, not self-invoked

**Part 2 — GunController renamed and wrapped**
- `src/client/GunController.client.lua` → `src/client/GunController.lua` — ModuleScript so ClientInit can require it
- Updated header comment from `-- LocalScript` to `-- ModuleScript`; removed now-resolved DEBT-015 prerequisite warning
- Added `local GunController = {}` table and wrapped all event connections (`InputBegan`, `HitConfirmed.OnClientEvent`, `HealthChanged.OnClientEvent`) and the Ready log inside `GunController:Start()` — no logic changed, only structure
- Added `return GunController` at the bottom
- All module-level requires and state declarations (`lastShotTime`, `CURRENT_WEAPON`) remain at module level as before

**Part 3 — ClientInit**
- Created `src/client/ClientInit.client.lua` — the only LocalScript in the Controllers folder; requires `MatchController` then `GunController` via `script.Parent:WaitForChild()`; calls each controller's `:Start()` in dependency order; both the `require` and the `Start()` call for each controller are individually guarded by `pcall` with `Logger.warn()` on failure so one broken controller never silently blocks the others

**Docs**
- Updated `docs/PROJECT_MAP.md`: added "Client initialization pattern" section explaining the ClientInit runner, current initialization order, and instructions for adding future controllers
- Updated `docs/TECHNICAL_DEBT.md`: DEBT-015 marked resolved with full reasoning (double-call bug explained); DEBT-007 and DEBT-013 file references corrected from `.client.lua` to `.lua`; DEBT-008 file reference corrected; added DEBT-017 (ClientInit must be manually updated when a new controller is added)

---

## [2026-05-07] — Resolve DEBT-016: Logger.DEBUG_MODE auto-detects Studio vs production

- Updated `src/shared/Logger.lua`: replaced `local DEBUG_MODE = true` with `local DEBUG_MODE = game:GetService("RunService"):IsStudio()` — `Logger.debug()` is now automatically silent in every published build without any manual code edit before shipping; the manual-step risk described in DEBT-016 is fully eliminated
- `src/client/GunController.client.lua`: already built and committed in the previous session (`6904711`); satisfies all requirements (UserInputService left-click, phase gate via `MatchController:GetPhase()`, client-side rate limit from `WeaponData`, camera raycast excluding local character, `WeaponFired:FireServer(origin, direction, now)`, `HitConfirmed` and `HealthChanged` listeners, Logger throughout); no changes needed
- `docs/PROJECT_MAP.md`: `WeaponFired` and `HitConfirmed` listener columns already correctly show `GunController.client.lua` from the five-rules task; no changes needed
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-016 resolved with full reasoning

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
