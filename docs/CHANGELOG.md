# CHANGELOG.md

All notable changes to this project, newest first.

Format: `## [version or date] — description`
Under each entry: bullet points for what was added, changed, or removed.

---

## [2026-05-20] — asset: swap Unarmed no-gun strafe-left/right animation IDs + correct speed multipliers

### Summary
Animation ID update for the Unarmed (no-gun) movement set. Confirmed-good R6 strafe-left and
strafe-right clips replace the previous IDs. Animation speed multipliers corrected to confirmed
values. No MovementController logic, camera behavior, or gun/combat systems changed.

### Changed files

- **`src/shared/Constants.lua`**:
  - `MOVEMENT_ANIMATION_IDS.R6.Unarmed.WalkLeft`: `101275785187464` → `115652140967957`
  - `MOVEMENT_ANIMATION_IDS.R6.Unarmed.WalkRight`: `73888687255042` → `82804864629403`
  - `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER`: `1.85` → `1.7`
  - `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER`: `1.6` → `1.4`
  - `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER`: `1.3` → `1.15`
  - All AR15 IDs, Unarmed WalkForward/RunForward IDs, and all other constants preserved.

- **`docs/PROJECT_MAP.md`** — Unarmed WalkLeft/WalkRight IDs and all three speed multiplier
  values updated to match.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated to x9; ID swap and multiplier correction noted.

### What was NOT changed
No `src/client/` files. No `src/server/` files. No `default.project.json`.
No MovementController logic. No camera changes. No gun/combat changes. No new remotes.

### Validation
- `rojo build` — passes.
- MCP unavailable — Studio verification not performed. Needs Studio verification.
  See DEBT-044 (x9) for test steps.

---

## [2026-05-19] — Movement Stage 2E: character-facing camera yaw (shift-lock style)

### Summary
Custom mouse lock (LeftAlt) now also rotates the character to face the camera's yaw direction
every Heartbeat — proper shift-lock behavior. `Humanoid.AutoRotate` is disabled while the lock
is active and restored on toggle-off, phase exit, respawn, or destroy.

### Changed files

- **`src/shared/Constants.lua`** — three new constants in the custom mouse-lock section:
  - `CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW = true` — enables character-facing rotation while locked.
  - `CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION = true` — facing only during ACTIVE phase;
    AutoRotate is restored on phase exit but the toggle state is preserved.
  - `CUSTOM_MOUSE_LOCK_ROTATION_DEBUG = true` — logs facing events and skip-reason changes to Output.

- **`src/client/MovementController.lua`** — Stage 2E additions:
  - **New private state:** `currentCharacter: Model?`, `currentRootPart: BasePart?` (cached in
    `setupCharacter()`), `originalAutoRotate: boolean?` (cached once per lock session), and
    `lastFacingSkippedReason: string` (deduplicates debug log spam).
  - **New helper `getCameraFlatLookVector(): Vector3?`** — reads `workspace.CurrentCamera.CFrame.LookVector`,
    flattens to XZ, returns nil if near-vertical (XZ magnitude < 0.001) to prevent NaN.
  - **New helper `restoreCharacterAutoRotate()`** — restores `Humanoid.AutoRotate` from
    `originalAutoRotate` (defaults to `true` if nil). Logs under `CUSTOM_MOUSE_LOCK_ROTATION_DEBUG`.
  - **New helper `applyCharacterFacing()`** — phase-gated, customMouseLocked-gated. Writes
    `HumanoidRootPart.CFrame = CFrame.lookAt(pos, pos + flatLook)` (yaw only, position preserved).
    Logs skip-reason once per reason change. Does NOT write camera.CFrame or change velocity.
  - **`applyCustomMouseLock()` updated** — on enable: caches `originalAutoRotate`, sets
    `AutoRotate = false`, calls `applyCharacterFacing()`. On disable: calls
    `restoreCharacterAutoRotate()` and clears `originalAutoRotate`. Master-switch-off path also
    restores AutoRotate.
  - **`setupCharacter()` updated** — caches `currentCharacter` and `currentRootPart`;
    resets `originalAutoRotate = nil` and `lastFacingSkippedReason = ""` on each spawn.
  - **`loadMovementAnimations()` updated** — adds `originalAutoRotate = nil` to the
    respawn-reset block alongside the existing `customMouseLocked = false` reset.
  - **`RoundStateChanged` handler updated** — on leaving ACTIVE with
    `REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION = true` and `customMouseLocked = true`:
    calls `restoreCharacterAutoRotate()` (preserves `originalAutoRotate` for re-entry). On
    ACTIVE re-entry with `customMouseLocked = true`: disables `AutoRotate` (caches if nil)
    and calls `applyCharacterFacing()`.
  - **`destroy()` updated** — calls `restoreCharacterAutoRotate()` before clearing state (if
    locked); clears `originalAutoRotate`, `currentCharacter`, `currentRootPart`,
    `lastFacingSkippedReason`.
  - **Heartbeat updated** — calls `applyCharacterFacing()` after the MouseBehavior reapply
    and before the `if not hum` guard; `applyCharacterFacing` self-gates on all conditions.
  - **Header, Owns section, animation constants list, camera/rotation rule comments updated.**

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers,
all `src/server/` files, `WeaponData`, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`,
`NAMING.md`, `stylua.toml`, `selene.toml`.

### Validation
- `rojo build default.project.json` — succeeds.
- MCP unavailable — Studio verification was not performed.
  Needs Studio verification: character-facing rotation, AutoRotate management, jitter under movement.
  Tracked as DEBT-044 (x8).

---

## [2026-05-20] — Docs: refined persistent-zone direction — metro base, physical transitions, deferred features

### Summary
Documentation-only planning update. **No runtime code changed. No remotes added. No src/ files touched.**

The persistent-zone product direction was refined and expanded across `CLAUDE.md`, `docs/PROJECT_RULES.md`,
`docs/PROJECT_MAP.md`, `docs/PERSISTENT_ZONE_ROADMAP.md` (new file), `docs/TECHNICAL_DEBT.md`, and
`docs/CHANGELOG.md`.

### Key direction changes documented

- **Metro station as safe-base fantasy** — the metro station is the primary hub. Players spawn there,
  deposit earnings, visit traders, and upgrade their operation. It is a physical space in Workspace, not
  a menu.
- **Physical zone transitions** — zone entry/exit must be physical: gates, train routes, sewers, tunnels,
  checkpoint exits. No abstract teleport menus.
- **Carried cash and secured funds** — two-currency economy: carried cash is at risk in the zone; secured
  funds are safe and only earned by physically depositing at the metro base terminal or extraction exit.
- **Risky in-zone shops** — emergency guns/supplies available in the zone at elevated prices (carried cash
  only). Never a shortcut to base armory progression.
- **Faction traders / simple missions** — optional short objectives (kill X, extract with cash, visit
  location) offered by a trader in the metro base. No complex faction warfare yet.
- **Reality Breakdown-style events** — periodic timed pressure (lethal zone spread, monster escalation, or
  loot surge). Participation is optional; safe extraction must always remain possible.
- **Base storage and upgrades** — locker/crate storage, armory tiers, medical upgrades. Visible progression
  funded by secured funds.
- **Flea market / player marketplace explicitly deferred** — documented as a long-term idea only. Must not
  be included in the first playable version. Prerequisites: stable economy, stash, item ownership,
  anti-duplication system, and moderation/abuse plan.

### Changed files

- **`CLAUDE.md`** — "Current product direction" section rewritten (metro base, refined core loop, eight
  experience pillars, updated money model / base-zone table, first playable scope). "Deferred / Do Not
  Build Yet" table added (flea market, free drawing, advanced AI death squads, full attachments, melee,
  faction warfare, visor detection, base decoration). "New first playable goal" updated. Build order
  table updated to reference `PERSISTENT_ZONE_ROADMAP.md`.

- **`docs/PROJECT_RULES.md`** — new "Refined persistent-zone design rules" section added:
  - First playable version discipline (prove the loop before secondary systems).
  - Explicit "do not build yet" rules for flea market, advanced AI, attachments, free drawing.
  - Physical extraction/deposit rule (no instant banking from zone).
  - Zone shop and pricing rule (higher prices than base; server-validates purchases).
  - Base progression rule (visible but not grindy).
  - Expanded server authority rule table for refined zone systems.

- **`docs/PROJECT_MAP.md`** — added "Planned persistent-zone systems" section with the full service
  list (ZoneService, EconomyService, ExtractionService, ShopService, LootService, DeathDropService,
  MissionService, ZoneEventService, BaseService, StashService, MonsterService). Added metro base design
  notes and zone entry/exit design notes. Flea market marked as "Deferred / Not first playable."
  Legacy AI section updated with stage references.

- **`docs/PERSISTENT_ZONE_ROADMAP.md`** — NEW FILE. Ten-stage build order:
  - Stage 0: FPS foundation (largely complete)
  - Stage 1: Metro base + zone transition
  - Stage 2: Economy foundation (carried cash, secured funds)
  - Stage 3: Deposit / extraction
  - Stage 4: Death loss + death drops
  - Stage 5: Risky zone shop + loot objects
  - Stage 6: Simple missions / faction traders
  - Stage 7: First event (Reality Breakdown)
  - Stage 8: Simple monsters
  - Stage 9: Base storage and upgrades
  - Stage 10: Deferred polish and expansion (flea market, advanced AI, attachments, etc.)
  Each stage lists "what is included", "what is NOT needed", and a "stage complete when" test condition.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-051 added (feature scope risk — high severity; lists deferred
  high-risk systems; flea market note explicit). DEBT-036 updated to reference refined metro-base
  direction (2026-05-20) and updated `PERSISTENT_ZONE_ROADMAP.md` reference.

### What was NOT changed
No `src/server/` files. No `src/client/` files. No `src/shared/` files.
No `default.project.json`. No `docs/NAMING.md`. No `stylua.toml`, `selene.toml`.
No remotes added. No camera changes. No gameplay logic changes. No runtime behavior changed.

### Validation
- `rojo build default.project.json` — run before commit to confirm no Rojo config changes caused errors.
- MCP unavailable — Studio verification not performed (documentation-only task; no runtime change).
- No markdown linter configured locally.
- `git diff --name-only` should show only: `CLAUDE.md`, `docs/PROJECT_RULES.md`, `docs/PROJECT_MAP.md`,
  `docs/PERSISTENT_ZONE_ROADMAP.md`, `docs/TECHNICAL_DEBT.md`, `docs/CHANGELOG.md`.

---

## [2026-05-19] — Workflow: MCP verification rules strengthened — always use Studio MCP when accessible

### Summary
The MCP verification rules in `CLAUDE.md` and `docs/PROJECT_RULES.md` were significantly expanded.
Previously the rule only described what to do when MCP was *unavailable*. The updated rule now
requires proactive MCP/Studio verification **before committing** for any runtime-affecting change,
and explicitly states that static checks alone are not sufficient for gameplay systems.

### Changed files

- **`CLAUDE.md`** — "MCP unavailable / GitHub-only mode" section replaced with a full
  "MCP verification rule" section:
  - Positive requirement: always use MCP when accessible; do not skip it because static checks pass.
  - Explicit list of system categories that require MCP before committing: `src/server/`,
    `src/client/`, `src/shared/`, remotes, Rojo config, player spawning, camera/mouse behavior,
    viewmodel, movement input, combat, UI, economy/inventory/zone systems, character rig, animation.
  - Verification workflow: edit → `rojo serve` → MCP → play → verify → commit.
  - Clear prohibition: never claim Studio verification unless actually performed through MCP or a
    confirmed manual Studio test. "This should work" and "static checks pass" are not equivalents.
  - Static checks (`selene`, `rojo build`, formatting) explicitly named as pre-conditions, not
    replacements for runtime verification.
  - "When MCP is unavailable" sub-section preserved and clarified.

- **`docs/PROJECT_RULES.md`** — new "Studio / MCP verification" section added after "Build discipline":
  - Verification requirement table: maps system categories to examples.
  - Step-by-step workflow for MCP-accessible sessions.
  - "When MCP is unavailable" behavior rules.
  - "Systems that especially must not skip MCP" callout (movement input, camera, animation,
    remotes, character spawn lifecycle, economy).

- **`docs/TECHNICAL_DEBT.md`** — DEBT-034 updated (x2):
  - Reflects the expanded rule scope (now covers "use MCP when available", not just "MCP unavailable").
  - Notes that the self-reporting risk remains unresolved (no CI gate yet).

### What was NOT changed
No `src/` files. No gameplay logic. No remotes. No camera changes. No Rojo config changes.
No animation IDs. No `docs/PROJECT_MAP.md`. No `docs/NAMING.md`. No `stylua.toml`, `selene.toml`.

### Validation
- `rojo build default.project.json` — succeeds (no Rojo config changes; build confirms tree is valid).
- No markdown linter is configured locally — no `markdownlint` or equivalent is installed.
- `git diff --name-only` confirms only `CLAUDE.md`, `docs/PROJECT_RULES.md`, `docs/TECHNICAL_DEBT.md`,
  and `docs/CHANGELOG.md` changed.

---

## [2026-05-19] — Movement Stage 2D bugfix: DevEnableMouseLock, ContextActionService bind, reapply-every-frame, phase-exit preserves lock

### Summary
Three runtime bugs found after Stage 2D shipped are fixed:
1. **Roblox default Shift Lock still activating on LeftShift** — `default.project.json` now sets
   `StarterPlayer.EnableMouseLockOption = false` via Rojo `"Bool"` syntax. MovementController's
   `Start()` and every `CharacterAdded` call `disableRobloxDefaultMouseLock()` (pcall on
   `LocalPlayer.DevEnableMouseLock = false`) to suppress the built-in lock client-side.
2. **LeftAlt toggle had ~1-frame delay** — `UserInputService.InputBegan` handler replaced with
   `ContextActionService:BindActionAtPriority` at priority 3000 (above CoreScript default 2000).
   The action is bound and unbound by name; NOT stored in `_connections`.
3. **WalkLeft/WalkRight strafe animations not playing** — new Heartbeat reapply: while
   `customMouseLocked` is `true`, `MouseBehavior = LockCenter` is re-written every frame so
   CoreScripts cannot silently steal the lock state after the LeftAlt toggle fires.

**Phase-exit behavior changed:** `customMouseLocked` is no longer reset on leaving ACTIVE.
The player's LeftAlt toggle state is now preserved across phase changes. Only respawn
(`loadMovementAnimations`) and `destroy()` reset it to `false`.

### Changed files

- **`src/shared/Constants.lua`** — three new constants in the custom mouse-lock section:
  - `DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK = true` — gates the `DevEnableMouseLock = false` call.
  - `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true` — causes Heartbeat to reapply LockCenter while locked.
  - `CUSTOM_MOUSE_LOCK_INPUT_PRIORITY = 3000` — ContextActionService bind priority for LeftAlt.

- **`default.project.json`** — added `EnableMouseLockOption: { "Bool": false }` to
  `StarterPlayer.$properties`. This disables the Roblox native Shift Lock option project-wide
  without requiring a manual Studio step.

- **`src/client/MovementController.lua`**:
  - New `ContextActionService` service require + module-level `MOUSE_LOCK_ACTION_NAME` constant.
  - New private helper `applyCustomMouseLock()` — writes `UserInputService.MouseBehavior` based on
    `customMouseLocked` and `CUSTOM_MOUSE_LOCK_ENABLED`; called by `SetCustomMouseLocked()`.
  - New private helper `disableRobloxDefaultMouseLock()` — pcall on `DevEnableMouseLock = false`;
    warns on failure via Logger; gated by `DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK`.
  - `Start()`: calls `disableRobloxDefaultMouseLock()` immediately; `CharacterAdded` also calls it.
  - `Start()`: LeftAlt binding replaced — `UserInputService.InputBegan` handler removed, replaced
    with `ContextActionService:BindActionAtPriority(MOUSE_LOCK_ACTION_NAME, ..., 3000, LeftAlt)`.
    Returns `Sink` on `Begin`; `Pass` on `End`/`Change` and when TextBox is focused.
  - `Start()` Heartbeat: reapply-every-frame block added at the top — writes `LockCenter` while
    `customMouseLocked` is true; runs regardless of phase.
  - `RoundStateChanged` handler: removed the `customMouseLocked` reset block. Phase exit no longer
    touches `customMouseLocked` — toggle state is preserved across phases.
  - `destroy()`: calls `ContextActionService:UnbindAction(MOUSE_LOCK_ACTION_NAME)` before connection cleanup.
  - `SetCustomMouseLocked()`: now delegates to `applyCustomMouseLock()` instead of writing
    `UserInputService.MouseBehavior` inline.
  - `customMouseLocked` comment updated: documents phase-change preservation, respawn/destroy reset.
  - Header, Owns, animation constants list, and Ready log updated for Stage 2D bugfix.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated to (x7); new "Stage 2D bugfix" update entry;
  remaining risks updated (stale Shift Lock and phase-exit notes replaced with current behavior).

- **`docs/PROJECT_MAP.md`** — MovementController and Constants sections updated:
  - "Mouse lock released on leaving ACTIVE" removed; now only released on respawn / destroy().
  - Three new `DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK`, `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME`,
    `CUSTOM_MOUSE_LOCK_INPUT_PRIORITY` constants documented.
  - `disableRobloxDefaultMouseLock()`, `applyCustomMouseLock()`, ContextActionService bind
    behavior documented.

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers, all
server files, `WeaponData`, animation IDs, `CLAUDE.md`, `PROJECT_RULES.md`, `NAMING.md`.
No remotes added. No camera.CFrame writes. No movement speeds changed. No gun/combat/server changes.

### Studio verification required
- LeftAlt toggles custom mouse lock immediately (no perceptible lag).
- LeftShift does NOT activate Roblox native Shift Lock icon or any native cursor centering.
- WalkLeft/WalkRight strafe animations play while `customMouseLocked` is true.
- Strafe anims stop when LeftAlt is toggled off; WalkForward plays instead.
- `customMouseLocked` state persists through ACTIVE → LOBBY → RESULTS → ACTIVE cycles.
- Mouse lock is released on character respawn and when the controller is destroyed.
- No console errors. `[MovementController] Roblox default Shift Lock disabled for LocalPlayer`
  appears in Output on Start (when `CUSTOM_MOUSE_LOCK_DEBUG = true`).

---

## [2026-05-19] — Movement Stage 2D: custom mouse-lock toggle (LeftAlt), LeftShift sprint-only, strafe gating via custom lock

### Summary
Added a custom mouse-lock toggle on LeftAlt so LeftShift can be used exclusively for sprinting
without conflict with Roblox's default Shift Lock. Strafe animations (WalkLeft/WalkRight) now
gate on the local `customMouseLocked` boolean rather than reading `UserInputService.MouseBehavior`
directly, decoupling strafe animation behavior from Roblox's native shift-lock state entirely.

This is NOT a full custom camera controller — `LockCenter` still routes through Roblox's default
camera system. A full Scriptable camera is deferred.

### Changed files

- **`src/shared/Constants.lua`** — four new custom mouse-lock constants:
  - `CUSTOM_MOUSE_LOCK_ENABLED = true` — master switch for the LeftAlt toggle system.
  - `CUSTOM_MOUSE_LOCK_TOGGLE_KEY = Enum.KeyCode.LeftAlt` — toggle key (LeftShift remains sprint-only).
  - `CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true` — when true, strafe gating reads `customMouseLocked`
    instead of `UserInputService.MouseBehavior` (Roblox native shift-lock detection is the legacy fallback).
  - `CUSTOM_MOUSE_LOCK_DEBUG = true` — logs mouse-lock toggle events to Output.
  - All existing constants preserved unchanged (`MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK`, speed multipliers, etc.).

- **`src/client/MovementController.lua`**:
  - New private state `customMouseLocked: boolean = false` — source of truth for strafe gating.
    Written only by `SetCustomMouseLocked()` and reset on respawn/phase-exit/destroy.
  - `isMouseLockedForStrafeAnimations()` updated:
    - Primary path (`CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true`): returns `customMouseLocked`.
    - Legacy path (`CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = false`): reads
      `UserInputService.MouseBehavior == LockCenter` (Stage 2C behaviour, now deprecated path).
  - New public method `MovementController.SetCustomMouseLocked(enabled: boolean)`:
    - `assert(typeof(enabled) == "boolean", ...)` validation.
    - If `CUSTOM_MOUSE_LOCK_ENABLED ~= true`: forces off and resets MouseBehavior to Default.
    - `enabled = true`: sets `customMouseLocked = true`, `UserInputService.MouseBehavior = LockCenter`.
    - `enabled = false`: sets `customMouseLocked = false`, `UserInputService.MouseBehavior = Default`.
    - Logs state change if `CUSTOM_MOUSE_LOCK_DEBUG == true`.
    - Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
  - New public method `MovementController.IsCustomMouseLocked(): boolean` — returns `customMouseLocked`.
  - New LeftAlt input handler in `Start()`:
    - Fires on `CUSTOM_MOUSE_LOCK_TOGGLE_KEY` (LeftAlt). No gameProcessed guard; TextBox guard only.
    - Toggles `SetCustomMouseLocked(not customMouseLocked)`.
    - Does NOT trigger sprint or affect movement speed.
  - `loadMovementAnimations()` updated: resets `customMouseLocked = false` and
    `UserInputService.MouseBehavior = Default` on respawn.
  - `RoundStateChanged` handler updated: releases `customMouseLocked = false` and resets
    `UserInputService.MouseBehavior = Default` when leaving ACTIVE. Logs if `CUSTOM_MOUSE_LOCK_DEBUG`.
  - `destroy()` updated: resets `customMouseLocked = false` and `UserInputService.MouseBehavior = Default`.
  - Strafe debug log messages updated to say "custom mouse lock" instead of "mouse lock".
  - Module header, Owns/Camera-rule/Stage-scope/Exposes sections updated for Stage 2D.
  - Ready log updated to include Stage 2D.

- **`docs/PROJECT_MAP.md`** — MovementController and Constants entries fully updated:
  - Documents `customMouseLocked`, `SetCustomMouseLocked`, `IsCustomMouseLocked`, LeftAlt toggle key.
  - Documents that `UserInputService.MouseBehavior` is WRITTEN (not just read) for mouse lock.
  - Documents that strafe gating uses `customMouseLocked`, not Roblox native Shift Lock.
  - Documents manual Studio step: `StarterPlayer.EnableMouseLockOption = false`.
  - Documents that this is NOT a full custom camera controller.
  - Constants section updated with four new `CUSTOM_MOUSE_LOCK_*` constants.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x6) (see Debt entries section).

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers, all server
files, `WeaponData`, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`, `NAMING.md`.
No remotes added. No camera.CFrame writes. No movement speeds changed. No animation IDs changed.
No gun/combat/server state changed. `LeftShift` sprint handler unchanged.

### Manual Studio step (now automated in Stage 2D bugfix)
- `StarterPlayer.EnableMouseLockOption = false` was previously a required manual Studio step.
  It has since been automated — `default.project.json` now sets this property via Rojo `"Bool"` syntax.
  See the Stage 2D bugfix entry above for the full resolution.

### Debt entries updated
- DEBT-044: updated (x6) with Stage 2D: custom mouse-lock toggle, LeftAlt key, strafe gate source
  changed to `customMouseLocked`; updated remaining gaps (full camera controller still deferred);
  updated remaining risks (Roblox default ShiftLock should be disabled, input needs Studio verification).

### Studio verification required
Yes. With `CUSTOM_MOUSE_LOCK_DEBUG = true` and `MOVEMENT_ANIMATION_DEBUG = true`:
- Disable `StarterPlayer.EnableMouseLockOption` in Studio before testing.
- Spawn in ACTIVE. Walk sideways without pressing LeftAlt:
  - WalkForward plays (strafe blocked). Output: "strafe animations blocked: custom mouse lock not active (press LeftAlt to enable)".
- Press LeftAlt: Output: "custom mouse lock: ON". Mouse locks to center.
  - Walk left: WalkLeft plays.
  - Walk right: WalkRight plays.
  - Hold LeftShift + move: RunForward plays (sprint, not affected by mouse lock).
- Press LeftAlt again: Output: "custom mouse lock: OFF". Mouse returns to Default.
  - Walk sideways: WalkForward plays again.
- Hold LeftShift while mouse lock is OFF and walk sideways: sprint activates, RunForward plays,
  mouse lock does NOT toggle on.
- Leave ACTIVE phase: Output: "custom mouse lock released: left ACTIVE phase". Cursor released.
- Respawn: cursor released, customMouseLocked = false confirmed by no "custom mouse lock: ON" log.
- Confirm no camera.CFrame, CameraOffset, or FieldOfView changes.
- Confirm no new remotes in Remotes folder.

---

## [2026-05-19] — Movement Stage 2 animation ID update: replace forward walk/run IDs with confirmed-good assets

### Summary
Replaced the four forward walk/run animation asset IDs (Unarmed WalkForward, Unarmed RunForward,
AR15 WalkForward, AR15 RunForward) with confirmed-good IDs. Strafe animation IDs (WalkLeft/WalkRight)
are unchanged. `MovementController` logic and all other constants are unchanged — this is a
pure asset ID swap.

### Changed files

- **`src/shared/Constants.lua`** — `Constants.MOVEMENT_ANIMATION_IDS.R6`:
  - `Unarmed.WalkForward`: `rbxassetid://83927286289016` → `rbxassetid://83352851460622`
  - `Unarmed.RunForward`:  `rbxassetid://98612697944606` → `rbxassetid://101113310705500`
  - `AR15.WalkForward`:    `rbxassetid://110651810525086` → `rbxassetid://138802532485746`
  - `AR15.RunForward`:     `rbxassetid://124640088553427` → `rbxassetid://79735501581082`
  - `Unarmed.WalkLeft`, `Unarmed.WalkRight` — **unchanged**.
  - No constants added or removed.

- **`docs/PROJECT_MAP.md`** — animation ID table in MovementController entry updated to match.
  Note added: "IDs updated 2026-05-19 — asset swap only, MovementController logic unchanged."

### What was NOT changed
`MovementController.lua`, all other Constants, all services, all UI controllers, all remotes,
`default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`, `TECHNICAL_DEBT.md`, `NAMING.md`.
No logic changes. No speed or behaviour changes.

### Debt entries updated
- DEBT-044: unaffected — this swap does not resolve or worsen any listed risk. Animation ownership
  risk is unchanged; confirm the new IDs are owned by the game's creator/group before shipping.

### Studio verification required
Yes. Spawn in ACTIVE phase with `MOVEMENT_ANIMATION_DEBUG = true`:
- Walk forward unarmed → Unarmed WalkForward clip plays (new ID `83352851460622`).
- Sprint forward unarmed → Unarmed RunForward clip plays (new ID `101113310705500`).
- Call `MovementController.SetEquippedWeaponName("AR15")`, walk forward → AR15 WalkForward plays
  (new ID `138802532485746`).
- Sprint with AR15 set → AR15 RunForward plays (new ID `79735501581082`).
- Strafe left/right (with mouse lock) → WalkLeft/WalkRight play unchanged.

---

## [2026-05-18] — Movement Stage 2C: strafe animation mouse-lock gating, LeftShift sprint fix, animation speed multipliers

### Summary
Three behaviour fixes applied to `MovementController` (Stage 2C):

1. **Strafe animation gating** — WalkLeft/WalkRight now only play when mouse-lock / shift-lock style
   state is active (`UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter`). Without mouse
   lock the character faces the camera direction, so dedicated strafe clips look wrong; all walking
   falls back to WalkForward in that state. Gated by `Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK`
   (default `true`); set `false` to always play strafe anims regardless.
2. **LeftShift sprint fix while shift lock is enabled** — Roblox's built-in shift lock marks LeftShift
   as `gameProcessed = true`, which the previous `if gp then return end` guard silently honoured,
   blocking sprint whenever shift lock was active. The guard is replaced with
   `UserInputService:GetFocusedTextBox() ~= nil` — sprint is now blocked only when the player is
   typing in a TextBox. The crouch handler (C key) keeps the original guard.
3. **Animation playback speed multipliers** — `AnimationTrack:AdjustSpeed()` is now called whenever
   a track starts (and on same-track re-checks) to set clip cadence independently of `Humanoid.WalkSpeed`:
   WalkForward 2.0×, WalkLeft/WalkRight 1.35×, RunForward 1.0× (unchanged).

### Changed files

- **`src/shared/Constants.lua`**:
  - `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER   = 2.0`  — WalkForward plays at 2× clip speed.
  - `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER = 1.35` — WalkLeft/WalkRight play at 1.35×.
  - `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER    = 1.0`  — RunForward plays at original clip speed.
  - `MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK   = true` — master switch gating strafe anims on mouse lock.

- **`src/client/MovementController.lua`**:
  - New private state `lastStrafeBlockedState: boolean = false` — prevents per-frame log spam for
    strafe-blocked/enabled state changes; logs only on transition.
  - New helper `isMouseLockedForStrafeAnimations()` — returns
    `UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter`. Read-only; does not write
    camera or toggle shift lock.
  - New helper `getAnimationSpeedMultiplier(animationName)` — maps short anim name to the matching
    `Constants.MOVEMENT_*_ANIMATION_SPEED_MULTIPLIER` value; defaults to 1.0 for unknown names.
  - `playMovementAnimation()` rewritten:
    - Extracts short name from full key (`"Unarmed_WalkForward"` → `"WalkForward"`) via
      `animationName:match("_(.+)$")` for multiplier lookup.
    - Calls `track:AdjustSpeed(speedMult)` immediately after `track:Play()`.
    - On same-track re-check, calls `track:AdjustSpeed(speedMult)` only (no restart).
    - Debug log now includes the speed multiplier suffix (e.g. `"×2"`, `"×1.35"`).
  - `updateMovementAnimation()` updated:
    - Evaluates `canUseStrafeAnimations` each tick based on `MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK`
      and `isMouseLockedForStrafeAnimations()`.
    - When `canUseStrafeAnimations` is false, all walking falls back to `setName .. "_WalkForward"`.
    - Strafe-blocked/enabled state change logged once per transition behind `MOVEMENT_ANIMATION_DEBUG`.
  - `sprintBeginConn` in `Start()` updated:
    - Removed `if gp then return end` guard for LeftShift (was silently blocking sprint while shift
      lock was active).
    - Added `if UserInputService:GetFocusedTextBox() ~= nil then return end` (blocks sprint only
      when typing). Comment documents why the standard guard is intentionally absent.
  - `loadMovementAnimations()` updated: resets `lastStrafeBlockedState = false` so the first
    movement after respawn re-logs the strafe state.
  - `destroy()` updated: resets `lastStrafeBlockedState = false`.
  - Module header, Owns/Camera-rule/Stage-scope sections updated to document Stage 2C.

- **`docs/PROJECT_MAP.md`** — `MovementController` and Constants entries fully updated with Stage 2C:
  - Strafe gating logic, `canUseStrafeAnimations`, `lastStrafeBlockedState` guard.
  - `isMouseLockedForStrafeAnimations()` and `getAnimationSpeedMultiplier()` helpers.
  - LeftShift sprint fix and `GetFocusedTextBox` guard.
  - Speed multiplier constants and `AdjustSpeed` call.
  - Note that `UserInputService.MouseBehavior` is read but not written.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x5) with Stage 2C notes (see Debt entries section).

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers, all server
files, `WeaponData`, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`, `NAMING.md`.
No remotes added. No camera writes. No new weapon or inventory state. No server-side changes.

### Debt entries updated
- DEBT-044: updated (x5) with Stage 2C strafe gating, sprint fix, speed multipliers, updated remaining
  gaps (true shift-lock system not built) and risks (speed multipliers need Studio tuning, Shift + sprint
  UX may feel awkward with built-in shift lock).

### Studio verification required
Yes. With `MOVEMENT_ANIMATION_DEBUG = true`:
- Without mouse lock active: walk in any direction → Output: `"strafe animations blocked: mouse lock not active"` on first movement. WalkForward plays regardless of direction.
- Enable Roblox built-in shift lock, then hold LeftShift and move → sprint starts normally (RunForward); no longer silently blocked.
- Hold LeftShift and click a TextBox → sprint blocked correctly.
- With mouse lock active: strafe left/right → WalkLeft/WalkRight plays. Output: `"strafe animations enabled: mouse lock active"` on first movement.
- Walk forward → Output log includes `"×2"` multiplier suffix. Strafe → `"×1.35"`. Sprint → `"×1"`.

---

## [2026-05-18] — Movement animation-set fix: default to Unarmed; add no-gun strafe IDs; SetEquippedWeaponName API

### Summary
Fixed `MovementController` defaulting to the AR15/gun animation set when no weapon is equipped.
The correct default is Unarmed. AR15 movement animations now only play when
`MovementController.SetEquippedWeaponName("AR15")` is explicitly called.
Two no-gun strafe animation IDs (WalkLeft/WalkRight) were added to the Unarmed set so
left/right strafe animations play correctly without a weapon equipped.
This is presentation-only: `equippedWeaponName` controls animation selection only and does not
affect server weapon state, ammo, damage, hit validation, reload, or inventory.

### Changed files

- **`src/shared/Constants.lua`**:
  - Three new animation-set name constants:
    - `Constants.MOVEMENT_ANIMATION_SET_UNARMED = "Unarmed"` — key for the no-gun set.
    - `Constants.MOVEMENT_ANIMATION_SET_AR15    = "AR15"`    — key for the AR15 set.
    - `Constants.MOVEMENT_DEFAULT_ANIMATION_SET = Constants.MOVEMENT_ANIMATION_SET_UNARMED` — project default.
  - Two new Unarmed animation IDs added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`:
    - `WalkLeft  = "rbxassetid://101275785187464"` — no-gun strafe left.
    - `WalkRight = "rbxassetid://72765640529019"`  — no-gun strafe right.
  - All existing IDs (Unarmed WalkForward/RunForward, AR15 WalkForward/RunForward) preserved.

- **`src/client/MovementController.lua`**:
  - New private state `equippedWeaponName: string? = nil` — presentation-only; nil = Unarmed set.
  - New private state `lastAnimationSet: string = ""` — guards against per-frame set-change log spam.
  - `getAnimationSetName()` rewritten:
    - Returns `MOVEMENT_ANIMATION_SET_UNARMED` when `equippedWeaponName == nil` (was: always "AR15").
    - Returns `MOVEMENT_ANIMATION_SET_AR15` when `equippedWeaponName == Constants.DEFAULT_WEAPON` or `"AR15"`.
    - Falls back to `MOVEMENT_ANIMATION_SET_UNARMED` for unknown weapon names.
  - `loadMovementAnimations()` updated:
    - Resets `lastAnimationSet = ""` at the start of each character load.
    - Expanded `toLoad` table to include `Unarmed_WalkLeft` and `Unarmed_WalkRight`.
    - Both Unarmed and AR15 tracks are pre-loaded at spawn for instant set switching.
  - `updateMovementAnimation()` updated:
    - Logs `"animation set: Unarmed"` or `"animation set: AR15"` once per set change (not per frame),
      behind `Constants.MOVEMENT_ANIMATION_DEBUG`.
  - New public method `MovementController.SetEquippedWeaponName(weaponName: string?)`:
    - `nil` or `""` → `equippedWeaponName = nil` (Unarmed set).
    - `"AR15"` / `Constants.DEFAULT_WEAPON` → `equippedWeaponName = weaponName` (AR15 set).
    - Any other non-empty string → stored with a one-time `Logger.warn`; Unarmed fallback in `getAnimationSetName`.
    - Validated with `assert()`. Logs debug output when `MOVEMENT_ANIMATION_DEBUG = true`.
    - Does NOT affect server weapon state, ammo, damage, hit validation, or reload.
  - New public method `MovementController.GetEquippedWeaponName(): string?`:
    - Returns current `equippedWeaponName`. `nil` = Unarmed set active.
  - `destroy()` updated: resets `equippedWeaponName = nil` and `lastAnimationSet = ""`.
  - Module header, Owns section, Stage 2A scope, and Exposes section updated to document the new API.

- **`docs/PROJECT_MAP.md`** — `MovementController` entry updated:
  - Documents `SetEquippedWeaponName`/`GetEquippedWeaponName` and the presentation-only nature of `equippedWeaponName`.
  - Documents that Unarmed is the default; AR15 only plays after an explicit call.
  - Documents all six animation IDs including the two new no-gun strafe IDs.
  - Constants entry updated with the three new animation-set name constants.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 and DEBT-050 updated:
  - DEBT-044: added animation-set fix update, revised remaining gaps and risks.
  - DEBT-050: partially resolved; severity lowered to Low-Medium; remaining risk documented (no real equip caller exists yet).

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers, all server
files, `WeaponData`, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`, `NAMING.md`.
No remotes added. No camera writes. No movement speeds changed. No gun/combat/server state changed.

### Debt entries updated
- DEBT-044: updated (x4) with animation-set selection fix.
- DEBT-050: partially resolved — default is now Unarmed; `SetEquippedWeaponName` API added; remaining risk is no real equip caller exists yet.

### Studio verification required
Yes. With `MOVEMENT_ANIMATION_DEBUG = true`:
- Spawn with no gun equipped → Output: `"animation set: Unarmed"`. Walking forward plays Unarmed WalkForward.
- Sprint plays Unarmed RunForward.
- Strafe left plays Unarmed WalkLeft (rbxassetid://101275785187464).
- Strafe right plays Unarmed WalkRight (rbxassetid://72765640529019).
- No AR15 movement animation plays with no gun equipped.
- From command bar: `require(game.StarterPlayer.StarterPlayerScripts.Controllers.MovementController).SetEquippedWeaponName("AR15")` → Output: `"animation set: AR15"`. AR15 walk/run plays.
- Call `SetEquippedWeaponName(nil)` → Output: `"animation set: Unarmed"`. Returns to no-gun animations.
- Respawn: tracks reload without duplicates; set-change log fires once on first movement.
- Leave ACTIVE phase: movement animations stop. No camera bob, sway, FOV, or camera.CFrame changes.

---

## [2026-05-18] — Movement Stage 2A: robust R6 rig detection helpers in MovementController

### Summary
Added three private helpers to `MovementController` to diagnose and recover from cases where
`Humanoid.RigType` does not report R6 despite `StarterPlayer.CharacterRigType` being set to R6.
The primary check (`RigType == R6`) is supplemented by a structural fallback (`hasR6BodyParts`)
that inspects the seven canonical R6 body-part names. If neither check passes,
`getRigDebugSummary` is logged showing the exact `RigType.Name`, which parts are present, and
the character name — making any mismatch immediately visible in Output.
The `disableDefaultAnimate()` call was moved from `setupCharacter()` into `loadMovementAnimations()`
(after the rig check passes) so Animate is only disabled when the character is confirmed R6.

### Changed files

- **`src/client/MovementController.lua`**:
  - New helper `hasR6BodyParts(character: Model): boolean` — returns true when all seven R6 body
    parts (`HumanoidRootPart`, `Torso`, `Head`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg`)
    are direct children of `character`. Used as structural fallback only.
  - New helper `getRigDebugSummary(character: Model, hum: Humanoid): string` — returns a formatted
    string with `RigType.Name`, presence of `Torso`/`UpperTorso`/`LowerTorso`/`Left Arm`/`LeftUpperArm`,
    and `character.Name`. Logged when R6 animations are skipped.
  - New helper `isR6Character(character: Model, hum: Humanoid): boolean` — primary check is
    `RigType == R6`; structural fallback via `hasR6BodyParts()`; emits a one-time `Logger.warn`
    (guarded by `rigTypeWarned`) if the fallback fires with a reference to DEBT-049.
  - `loadMovementAnimations()`: replaced direct `RigType ~= R6` check with `isR6Character()`;
    logs `getRigDebugSummary()` when skipping; `disableDefaultAnimate()` call moved here from
    `setupCharacter()`, placed immediately after `isR6Character()` passes.
  - `setupCharacter()`: removed explicit `disableDefaultAnimate(char)` call; updated comment
    noting that Animate disable now happens inside `loadMovementAnimations` after rig confirmation.
  - Module header updated to document R6 detection behaviour and corrected Animate-disable placement.

- **`docs/PROJECT_MAP.md`** — `MovementController` entry updated:
  - Documents `hasR6BodyParts`, `getRigDebugSummary`, `isR6Character` helpers.
  - Notes corrected Animate-disable placement (inside `loadMovementAnimations` after rig check).

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated:
  - Notes R6 detection helpers added, `disableDefaultAnimate` moved inside rig check.
  - Remaining risk: if neither `RigType` nor structural check passes, animations are skipped and
    the developer must verify `StarterPlayer.CharacterRigType` after each `rojo serve` (DEBT-049).

### What was NOT changed
`Constants.lua`, `GunController`, `ViewModelController`, `ClientInit`, all server files, all UI
controllers, all remotes, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`. No animation
IDs changed. No movement speeds changed. No camera writes. No new remotes.

### Debt entries updated
- DEBT-044: updated with R6 detection helpers, corrected Animate-disable placement.

### Studio verification required
Yes — test in Studio play mode. With `MOVEMENT_ANIMATION_DEBUG = true`:
- If character is R6 (`RigType` path): no warn, Animate disabled, custom animations play.
- If character has R6 parts but `RigType` mismatch: structural fallback warning fires once, Animate disabled, custom animations play.
- If character is not R6 at all: `getRigDebugSummary` logged in Output, Stage 1 speed/direction still active.

---

## [2026-05-18] — Movement Stage 2A bug fix: disable default Animate script so custom R6 locomotion plays

### Summary
Bug fix for custom R6 movement animations not playing. The root cause was the default Roblox `Animate` LocalScript — present in every spawned character — overriding custom `AnimationTrack` objects loaded in Stage 2A. `MovementController` now calls `disableDefaultAnimate(character)` on every `CharacterAdded`, before loading custom tracks, so the avatar animation pack no longer controls locomotion. The fix is gated by two new constants (both default `true`). A third constant enables animation diagnostic logging. WalkLeft/WalkRight direction fallback logic added.

### Changed files

- **`src/shared/Constants.lua`** — three new constants added in the movement animation section:
  - `Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED = true` — master switch; `false` leaves Animate running and skips all custom track logic.
  - `Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = true` — when `true`, sets `character.Animate.Disabled = true` before loading custom tracks; `false` leaves Animate running (custom tracks may conflict).
  - `Constants.MOVEMENT_ANIMATION_DEBUG = true` — logs animation load and switch events to Output; set `false` to silence in production.
  - No existing constants changed. No animation IDs changed.

- **`src/client/MovementController.lua`** — multiple targeted additions on top of the Stage 2A layer:
  - New private state: `animationInstances: { [string]: Animation }` — stores unparented `Animation` instances so they can be explicitly destroyed on respawn and in `destroy()`.
  - `animationTracks` type updated from `{ [string]: AnimationTrack }` to `{ [string]: AnimationTrack? }` — makes nil checks on absent keys type-safe.
  - New private helper `disableDefaultAnimate(character: Model)`:
    - Guards on `CUSTOM_MOVEMENT_ANIMATIONS_ENABLED` and `DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT`.
    - Finds `character:FindFirstChild("Animate")`; if it is a `LocalScript` or `Script`, sets `Disabled = true`.
    - Does NOT destroy Animate. Does NOT touch any script outside the character.
    - Logs via `Logger.debug()` when Animate is disabled.
  - `setupCharacter()` updated: calls `disableDefaultAnimate(char)` before `loadMovementAnimations(char)`.
  - `loadMovementAnimations()` updated:
    - Gated on `CUSTOM_MOVEMENT_ANIMATIONS_ENABLED` at the top.
    - Destroys and clears `animationInstances` at the start of each respawn (old `Animation` objects explicitly destroyed).
    - Per-track `Logger.debug()` behind `MOVEMENT_ANIMATION_DEBUG` (key + assetId).
    - `Logger.warn()` for any empty or nil assetId.
  - `playMovementAnimation()` updated: logs switch (prev → next) behind `MOVEMENT_ANIMATION_DEBUG`.
  - `updateMovementAnimation()` updated:
    - Gated on `CUSTOM_MOVEMENT_ANIMATIONS_ENABLED`.
    - Now attempts `WalkLeft`/`WalkRight` tracks for left/right directions; falls back to `WalkForward` if not loaded (Stage 2A has no strafe IDs yet).
  - `destroy()` updated: explicitly destroys and clears `animationInstances` in addition to clearing `animationTracks`.
  - Module header comment updated to document the bug fix, Animate side effects, and animation constants.

- **`docs/PROJECT_MAP.md`** — `MovementController` entry updated:
  - Documents `disableDefaultAnimate()` behavior, guard constants, and "disabled not destroyed" note.
  - Documents Animate side effect: idle/jump/fall/climb also suppressed.
  - Documents `CUSTOM_MOVEMENT_ANIMATIONS_ENABLED`, `DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT`, `MOVEMENT_ANIMATION_DEBUG` in the Constants entry.
  - Notes animation ID ownership risk.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated:
  - Notes the Animate-disable bug fix.
  - Adds remaining risks: animation ID ownership, non-R6 skip, idle/jump/fall/climb T-pose, armed/unarmed always AR15, conflict when `DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = false`.

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers, all server files, `WeaponData`, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`, `NAMING.md`. No remotes added. No camera writes. No movement speeds changed. No new animation IDs added.

### Debt entries updated
- DEBT-044: updated with Animate-disable fix, WalkLeft/WalkRight fallback, new remaining risks listed.

### Studio verification required
Yes — see Studio test steps in the task prompt. Key: character.Animate becomes Disabled on spawn, avatar pack walk/run no longer plays, custom walk/run plays during ACTIVE.

---

## [2026-05-18] — Movement Stage 2A: R6 walk/run animation playback in MovementController

### Summary
Adds prototype R6 walk/run animation playback to `MovementController` (Movement Stage 2A). Four AnimationTrack objects are loaded per character respawn via `Humanoid.Animator` and played during ACTIVE phase only. Sprint plays `RunForward`; all other movement plays `WalkForward` (strafing, backward, and diagonal fallback — full per-direction set is deferred to Stage 2B). All Stage 1 speed and direction logic is unchanged. Non-R6 characters skip animation loading cleanly. No new remotes. No camera changes. No server files touched.

### Changed files

- **`src/shared/Constants.lua`** — two additions in a new "Movement animation IDs" section:
  - `Constants.MOVEMENT_ANIMATION_IDS` — nested table keyed by rig type (`R6`) → weapon set (`Unarmed`, `AR15`) → animation name (`WalkForward`, `RunForward`). Four asset IDs total:
    - `Unarmed.WalkForward = "rbxassetid://83927286289016"`
    - `Unarmed.RunForward  = "rbxassetid://98612697944606"`
    - `AR15.WalkForward    = "rbxassetid://110651810525086"`
    - `AR15.RunForward     = "rbxassetid://124640088553427"`
  - `Constants.MOVEMENT_ANIMATION_FADE_TIME = 0.15` — cross-fade duration for all animation transitions.

- **`src/client/MovementController.lua`** — Stage 2A animation layer added on top of Stage 1:
  - New private state: `animationTracks: { [string]: AnimationTrack }`, `currentAnimationName: string`, `rigTypeWarned: boolean`.
  - New private helpers:
    - `getAnimator(character)` — finds `Humanoid.Animator`; warns and returns nil if absent.
    - `getAnimationSetName()` — returns `"AR15"` (prototype default; true state deferred — DEBT-050).
    - `stopCurrentMovementAnimation()` — stops playing track with fade; clears `currentAnimationName`.
    - `playMovementAnimation(animationName)` — switches to a named track with fade; guards against duplicate play and missing keys.
    - `loadMovementAnimations(character)` — clears stale track references, checks `HumanoidRigType.R6`, loads all four tracks via `Animator:LoadAnimation`; sets `Looped = true`; skips with a one-time warn on non-R6.
    - `updateMovementAnimation()` — called every Heartbeat during ACTIVE; stops when not moving; plays `RunForward` while sprinting, `WalkForward` otherwise.
  - `setupCharacter()` updated: calls `loadMovementAnimations(char)` after acquiring Humanoid.
  - `destroy()` updated: calls `stopCurrentMovementAnimation()` then `table.clear(animationTracks)` before disconnecting connections.
  - `phaseConn` handler updated: calls `stopCurrentMovementAnimation()` when leaving ACTIVE.
  - `heartbeatConn` updated: calls `updateMovementAnimation()` after `applySpeed()`.
  - Module header comment updated to document Stage 2A scope and limitations.
  - Log message updated: `"Ready (Stage 1 + Stage 2A)"`.

- **`docs/PROJECT_MAP.md`** — `MovementController` entry in Presentation section updated:
  - Documents Stage 2A animation support, all four animation IDs, and per-animation meanings.
  - Documents what is NOT in Stage 2A (crouch anim, strafe/backward/diagonal, lower/upper-body split, reload/fire/ADS).
  - Notes that non-R6 characters skip animation loading safely.

- **`docs/TECHNICAL_DEBT.md`** — two changes:
  - DEBT-044 updated: partial resolution — Stage 2A forward walk/run exists; remaining gaps listed (crouch, strafe, backward, diagonal, splits, weapon anims, armed/unarmed state).
  - DEBT-050 added (Medium): `getAnimationSetName()` always returns `"AR15"`; true armed/unarmed selection requires server-owned equipment state (InventoryService/EquipmentService).

### What was NOT changed
`GunController`, `ViewModelController`, `ClientInit`, `SoundController`, all UI controllers, all server files, `WeaponData`, `default.project.json`, `CLAUDE.md`, `PROJECT_RULES.md`, `NAMING.md`. No remotes added. No camera.CFrame writes. No `CameraOffset` writes. No `FieldOfView` changes. No movement speeds changed. No new RenderStepped connections.

### Debt entries added
- DEBT-050: `getAnimationSetName()` defaults to AR15; true armed/unarmed state deferred to InventoryService/EquipmentService.

### Debt entries updated
- DEBT-044: Partially resolved — Stage 2A forward walk/run added. Crouch, strafe, backward, diagonal, splits, and weapon anims remain deferred.

### Studio verification required
Yes — see Studio test steps in the task prompt. Key: character is R6, AR15 WalkForward plays in ACTIVE while walking forward, RunForward plays while sprinting, animation stops when not moving or leaving ACTIVE, no duplicate tracks on respawn.

---

## [2026-05-18] — Set R6 as project character rig target; document rig rules in all project docs

### Summary
Establishes R6 as the canonical character rig for BrokenRealityFPS. Sets `StarterPlayer.CharacterRigType` to `Enum.HumanoidRigType.R6` (ordinal 0) in `default.project.json` via Rojo `$properties`. Documents R6 body-part names, rig rules, and future-system constraints across `CLAUDE.md`, `docs/PROJECT_RULES.md`, `docs/PROJECT_MAP.md`, `docs/TECHNICAL_DEBT.md`. No `src/` files were changed. No remotes added. No camera, movement, or gameplay logic changed.

### Changed files

- **`default.project.json`** — added `"$properties": { "CharacterRigType": { "Enum": 0 } }` to the `StarterPlayer` entry. Enum ordinal 0 = `Enum.HumanoidRigType.R6`. Rojo 7.x applies this when syncing into Studio.

- **`CLAUDE.md`** — added "Character rig target" section (between Toolchain and Commands sections):
  - States R6 as the current target; R15 as legacy.
  - Lists the 7 R6 canonical body-part names with roles.
  - Notes where the setting lives in Studio and `default.project.json`.
  - Lists future systems that must target R6 (animations, hitbox, ragdoll Stage 2, weapon attachment points).

- **`docs/PROJECT_RULES.md`** — added "Character rig target" section at the end of the file:
  - Hard rules: no R15 part names in new code, animation IDs must be R6-rigged, hitbox lookups use R6 names, weapon attachment points align to R6 geometry.
  - Clarifies that rig-agnostic code (e.g. `RagdollService` iterating Motor6D by type) is acceptable.

- **`docs/PROJECT_MAP.md`** — added "Character Rig Target" section (between Workspace layout and New Target Architecture):
  - Shows the Rojo JSON snippet for `CharacterRigType`.
  - Lists R6 body-part reference table.
  - Lists systems that must target R6 and their specific R6 dependency.
  - Notes that `RagdollService`'s rig-agnostic Motor6D iteration requires no change.

- **`docs/TECHNICAL_DEBT.md`** — two changes:
  - Added DEBT-049 (High): R6 `CharacterRigType` set via Rojo `$properties` — requires Studio manual verification that `StarterPlayer` shows `R6`, not `R15`, after each `rojo serve` session.
  - Updated DEBT-023: notes the project rig changed from R15 to R6; `RagdollService` Motor6D iteration is rig-agnostic and requires no code change; R6 has fewer joints (6 vs ~15) so accidental joint capture risk is lower.

### What was NOT changed
All `src/` files: no changes to any service, controller, shared module, or UI. No remotes. No camera changes. No gameplay logic. No animation changes. `wally.toml`, `selene.toml`, `stylua.toml` untouched.

### Debt entries added
- DEBT-049: R6 rig target needs Studio manual verification after each `rojo serve` session.

### Debt entries updated
- DEBT-023: Updated to reflect R6 as the current rig target; no code changes required to `RagdollService`.

### Studio verification required
Yes — see DEBT-049. After `rojo serve`, confirm `StarterPlayer.CharacterRigType = R6` in the Properties panel. If Rojo does not apply the property, set it manually via `Game Settings → Avatar → R6`.

---

## [2026-05-18] — Add Constants.FORCE_FIRST_PERSON testing flag; ViewModelController supports normal-camera testing mode

### Summary
Adds `Constants.FORCE_FIRST_PERSON = false` (default) and updates `ViewModelController` so that both the first-person camera lock and the AR15 viewmodel visibility are conditional on this flag. When `false` (the default), the player keeps the normal Roblox Classic camera and the viewmodel stays permanently hidden — useful for movement, map, and zone testing without a floating gun in view. When `true`, behaviour matches the original FPS experience: LockFirstPerson camera and the viewmodel shown during ACTIVE only. No new remotes. No changes to GunController, MovementController, or any server file.

### Changed files

- **`src/shared/Constants.lua`** — added one constant at the end of the file:
  - `Constants.FORCE_FIRST_PERSON = false` — development/testing flag; set `true` before FPS playtesting or shipping.

- **`src/client/ViewModelController.lua`** — behaviour changes only in `Start()` and the `CharacterAdded` handler:
  - Added module-level state: `local currentPhase : string = Constants.Phase.LOBBY` — tracks the last received phase so `CharacterAdded` can evaluate visibility immediately without waiting for the next `RoundStateChanged` tick.
  - Added `local function applyCameraMode()` — sets `Players.LocalPlayer.CameraMode` to `LockFirstPerson` when `FORCE_FIRST_PERSON` is `true`, or `Classic` when `false`. Replaces the unconditional `LockFirstPerson` assignment.
  - Added `local function shouldShowViewModel(): boolean` — returns `true` only when `FORCE_FIRST_PERSON == true` AND `currentPhase == ACTIVE` AND `self.model ~= nil`. All three conditions must hold.
  - `Start()`: calls `applyCameraMode()` instead of unconditionally setting `LockFirstPerson`. Moved `setVisibility` definition before `CharacterAdded` connection (forward-reference fix).
  - `CharacterAdded`: calls `self:init()`, then `applyCameraMode()`, then `setVisibility(shouldShowViewModel())`. Previously only called `init()` and set `LockFirstPerson`.
  - `RoundStateChanged` listener: now updates `currentPhase` from `payload.phase` before calling `setVisibility(shouldShowViewModel())`. Previously derived `show` directly from `payload.phase == ACTIVE`.
  - `RenderStepped` / `PivotTo`: unchanged — still runs unconditionally when `FORCE_FIRST_PERSON` is `false` so unanchored model parts do not fall and get destroyed by Roblox's `FallenPartsDestroyHeight` mechanism.
  - `PlayFireAnimation()`, `GetBarrelTipCFrame()`, `SetRecoilOffset()`: unchanged — all public APIs preserved. No errors when viewmodel is hidden (model exists; Transparency=1 has no effect on CFrame operations).
  - Module header comment updated to document the FORCE_FIRST_PERSON camera rule and the read-only camera constraint.

- **`docs/PROJECT_MAP.md`** — updated two sections:
  - `ViewModelController` entry in Presentation section: documents `FORCE_FIRST_PERSON` modes, camera-read-only rule.
  - `Constants` entry in Shared modules section: documents `FORCE_FIRST_PERSON` with both values described.

- **`docs/TECHNICAL_DEBT.md`** — added DEBT-048.

### What was NOT changed
GunController, MovementController, ClientInit, SoundController, all UI controllers, all server files, WeaponData, default.project.json, CLAUDE.md, PROJECT_RULES.md, NAMING.md. No remotes added or changed. No camera.CFrame writes. No CameraOffset writes. No FieldOfView changes. No new animations, bob, sway, ADS, or recoil logic.

### Debt entries added
- DEBT-048: FORCE_FIRST_PERSON=false is a development shortcut; must be flipped to `true` before FPS playtesting or shipping. Long-term: replace with a GameModeConfig or SettingsService read.

### Debt evaluation
- DEBT-029 (setVisibility called every tick): **unaffected** — setVisibility is still called every `RoundStateChanged` tick with `shouldShowViewModel()` result; when `FORCE_FIRST_PERSON=false` this is always `false`, iterating 49 parts unnecessarily each tick. No change to severity.
- DEBT-045 (recoil viewmodel-only): **unaffected**.
- DEBT-040 (ADS visual not implemented): **unaffected**.
- DEBT-007 (RoundStateChanged fan-out, 8 listeners): **unaffected** — ViewModelController still has exactly one listener.
- DEBT-017 (ClientInit manual update): **unaffected** — no new controller added.

### Studio verification required
Yes — see Studio test steps in the task prompt.

---

## [2026-05-18] — Movement Stage 1: walk/sprint/crouch speed, 8-direction detection, phase gating, respawn handling, connection cleanup

### Summary
Movement Stage 1 replaces the previous over-built MovementController (which included slide, vault, camera bob, CameraOffset manipulation, animation machine, viewmodel sway, and landing dip) with a clean, minimal foundation. All features beyond Stage 1 scope are deferred to future stages. No new remotes were added. Camera rules strictly observed: no writes to `camera.CFrame`, `Humanoid.CameraOffset`, or `FieldOfView`.

### Changed files

- **`src/client/MovementController.lua`** — complete rewrite (Stage 1 only):
  - Removed: slide, vault, camera bob, `Humanoid.CameraOffset` manipulation, animation machine (`ANIM_IDS`, `loadAnims`, `playAnim`), viewmodel sway/tilt, landing dip, `TweenService` calls, `Stance` enum.
  - Added: `movementState` table (`isMoving`, `isSprinting`, `isCrouching`, `directionName`, `moveVector`).
  - Sprint: LeftShift held enables sprint in ACTIVE; ignored while crouching. Speed = `SPRINT_SPEED` only when sprinting AND moving.
  - Crouch: C toggles in ACTIVE; entering crouch clears sprint. Speed = `CROUCH_SPEED`.
  - Phase gating: WalkSpeed = 0 outside ACTIVE; `WALK_SPEED` / `SPRINT_SPEED` / `CROUCH_SPEED` during ACTIVE.
  - Respawn: `CharacterAdded` connection re-acquires Humanoid, resets state, applies phase-appropriate speed.
  - Direction detection: Heartbeat reads `humanoid.MoveDirection`, flattens camera `LookVector` / `RightVector` onto XZ, dot products classify into one of 9 directions: `"Idle"`, `"Forward"`, `"Backward"`, `"Left"`, `"Right"`, `"ForwardLeft"`, `"ForwardRight"`, `"BackwardLeft"`, `"BackwardRight"`. Uses `Constants.MOVEMENT_DIRECTION_DEADZONE` for the magnitude gate.
  - Connection cleanup: all 6 connections stored in `_connections`; `destroy()` disconnects all.
  - Public API: `GetMovementState()` (table), `GetMoveState()` (string, backward-compat for GunController), `IsADSBlocked()` (bool), `GetViewmodelAddCFrame()` (identity in Stage 1), `Start()`, `destroy()`.

- **`src/shared/Constants.lua`** — added one constant:
  - `Constants.MOVEMENT_DIRECTION_DEADZONE = 0.15` — `Humanoid.MoveDirection` magnitude below which the player is considered "Idle"; placed in the Player settings section alongside the speed constants.

- **`src/client/ClientInit.client.lua`** — updated position-9 comment to describe Stage 1 behavior (no functional change to initialization order or controller count).

- **`docs/PROJECT_MAP.md`** — updated MovementController entry and initialization-order row to reflect Stage 1 scope, camera-read-only rule, and new public API.

- **`docs/TECHNICAL_DEBT.md`** — updated DEBT-044 (animation system now explicitly absent, not placeholder); updated DEBT-007 and DEBT-017 notes; added DEBT-046 (phase gating couples to legacy MatchController / ZoneService migration note) and DEBT-047 (movementState returned by reference — callers must treat as read-only).

### What was NOT added (Stage 1 scope gates)
Slide, vault, stamina, prone, footsteps, animations, camera bob, landing dip, camera height changes (`CameraOffset`), viewmodel sway, `TweenService`, `FieldOfView` changes.

### Debt entries added
- DEBT-046: Phase gating uses legacy MatchController/Constants.Phase.ACTIVE; must adapt to ZoneService.
- DEBT-047: movementState returned by reference — callers must not write to the table.

### Studio verification required
Yes — see test steps in the task prompt. MCP Studio test will follow.

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
