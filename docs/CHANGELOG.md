# CHANGELOG.md

All notable changes to this project, newest first.

Format: `## [version or date] — description`
Under each entry: bullet points for what was added, changed, or removed.

---

## [2026-06-03] — AKS74 first-person ADS animation system foundation

### Summary

Adds first-person ADS (aim down sights) animation system for AKS74 viewmodel. Right mouse button (MB2) toggles ADS on/off. ADS in animation plays once, then the final frame is held/frozen to fake an ADS idle pose. Subtle procedural breathing/sway movement is applied while the pose is frozen. Firing while ADS plays a separate ADS fire animation instead of the normal hip-fire animation. Reload or holster exits ADS cleanly.

**Animation-only system:** No FOV zoom, no camera changes, no spread/recoil/accuracy changes, no server combat changes. This task adds only the viewmodel ADS animation playback foundation.

**MCP/Studio verification required** — see verification steps at the end of this entry.

### Animation IDs added to `WeaponData["AKS74"].animations.firstPerson`

- `adsIn = "rbxassetid://134918319490586"` — ADS enter animation (plays once, frozen at end)
- `adsOut = "rbxassetid://132508450718728"` — ADS exit animation (returns to idle)
- `adsFire = "rbxassetid://138021695403324"` — fire while ADS (Action2 priority, overlays held ADS pose)
- `adsIdle = "rbxassetid://0"` — no dedicated ADS idle animation; fake via freeze + procedural movement

### Changes to `src/client/ViewModelController.lua`

**New state variables:**
- `weaponAdsInTrack`, `weaponAdsOutTrack`, `weaponAdsFireTrack: AnimationTrack?` — FP ADS animation tracks
- `isAiming: boolean` — true while ADS active
- `adsIdleTime: number` — accumulator for fake ADS idle sine-based breathing/sway

**New public methods:**
- `ViewModelController:SetAiming(entering: boolean)` — toggles ADS on/off; plays adsIn/adsOut; freezes adsIn at final frame
- `ViewModelController:IsAiming(): boolean` — returns true while aiming
- `ViewModelController:PlayADSInAnimation()` — plays adsIn animation (exposed for external choreography)
- `ViewModelController:PlayADSOutAnimation()` — plays adsOut animation (exposed for external choreography)
- `ViewModelController:PlayADSFireAnimation()` — plays adsFire animation; restartable per shot
- `ViewModelController:StopADSAnimations()` — stops all ADS tracks, unfreezes adsIn, clears state

**ADS track loading in `_setupWeaponAnimations()`:**
- Loads adsIn (one-shot, Action priority, freezes at final frame when Stopped event fires)
- Loads adsOut (one-shot, Action priority, returns to idle/run on Stopped)
- Loads adsFire (one-shot, Action2 priority, overlays frozen ADS pose during fire)

**ADS freeze logic:**
- `SetAiming(true)` plays adsIn animation once
- adsIn.Stopped:Once callback replays the track, seeks to `Length - VIEWMODEL_ADS_HOLD_FRAME_EPSILON`, then calls `AdjustSpeed(0)` to freeze
- Frozen pose held until `SetAiming(false)` unfreezes and plays adsOut
- Captured weapon identity guards against stale callbacks after holster

**Fake ADS idle movement in RenderStepped:**
- When `isAiming` is true and `VIEWMODEL_ADS_FAKE_IDLE_ENABLED` is true, applies subtle procedural movement to frozen ADS pose
- Sine-wave breathing (vertical Y sway)
- Horizontal X sway
- Tiny Z-axis rotation
- Frequency and amplitudes from Constants (tunable)
- Applied as `adsIdleCF` multiplied onto the viewmodel PivotTo chain after BASE_OFFSET + recoil

**ADS cleanup:**
- `init()` and `StopWeaponAnimations()` now Stop/Destroy ADS tracks and reset `isAiming` and `adsIdleTime`
- `PlayReloadAnimation()` calls `StopADSAnimations()` if `isAiming` is true (reload exits ADS)
- `SetAiming(false)` when entering while `isReloading` is true (reload blocks ADS entry)

**Priority and conflict handling:**
- Reload takes priority over ADS (entering ADS while reloading is blocked; reloading while ADS exits ADS first)
- Run animation suppressed while ADS (stop run track when adsIn starts)
- adsOut completion resumes idle or run depending on `isRunning` flag

### Changes to `src/client/GunController.lua`

**New input: MB2 ADS toggle**
- Listens to `UserInputService.InputBegan` with `Constants.ADS_INPUT_USER_INPUT_TYPE` (MouseButton2)
- Guards: game processed, holstered, not ACTIVE phase, tactical sprint active (if enabled)
- Toggles ADS: reads `ViewModelController:IsAiming()`, calls `ViewModelController:SetAiming(not currentlyAiming)`
- Connection stored in `_connections` table for cleanup on reset

**Fire animation selection:**
- Fire handler now checks `ViewModelController:IsAiming()`
- If aiming: calls `ViewModelController:PlayADSFireAnimation()`
- If not aiming: calls `ViewModelController:PlayFireAnimation()` (existing behavior)

**No server changes:**
- No new remotes
- No changes to WeaponFired payload
- No changes to spread, recoil, accuracy, or damage
- ADS is purely client-side animation

### Changes to `src/shared/Constants.lua`

**ADS input and animation tuning constants:**
- `ADS_INPUT_USER_INPUT_TYPE = Enum.UserInputType.MouseButton2` — right mouse button
- `VIEWMODEL_ADS_FADE_TIME = 0.08` — animation blend fade time (seconds)
- `VIEWMODEL_ADS_HOLD_FRAME_EPSILON = 0.01` — seek offset from end when freezing adsIn final frame
- `VIEWMODEL_ADS_FAKE_IDLE_ENABLED = true` — toggle for procedural ADS idle movement
- `VIEWMODEL_ADS_FAKE_IDLE_POSITION_X = 0.003` — horizontal sway amplitude (studs)
- `VIEWMODEL_ADS_FAKE_IDLE_POSITION_Y = 0.004` — vertical breathing amplitude (studs)
- `VIEWMODEL_ADS_FAKE_IDLE_ROTATION_DEGREES = 0.12` — tiny rotational sway (degrees)
- `VIEWMODEL_ADS_FAKE_IDLE_FREQUENCY = 1.15` — breathing cycle frequency (Hz)
- `VIEWMODEL_ADS_MOUSE_SWAY_MULTIPLIER = 0.25` — reduce mouse sway while ADS (future use if mouse sway added)
- `VIEWMODEL_ADS_MOVE_SWAY_MULTIPLIER = 0.2` — reduce movement sway while ADS (future use if move sway added)

### Technical debt affected

**DEBT-013** (High severity) — Weapon name hardcoded — **NOT WORSENED**. This task adds only client-side ADS animation. No server validation changes. No new weapon identity logic. Debt remains stable.

**DEBT-034** (Low-Medium severity) — MCP verification relies on self-reporting — **APPLIES TO THIS TASK**. This task requires MCP/Studio verification per PROJECT_RULES.md. See verification steps below.

**No new debt introduced.** This task adds only ADS animation playback to ViewModelController and MB2 input to GunController. No remotes added, no server changes, no camera changes, no assets imported.

### MCP/Studio verification steps (23 steps)

When MCP is available, verify the following in Roblox Studio play mode before marking this entry complete:

1. Start a client playtest (single player or local server).
2. Confirm AKS74 is holstered before pressing 1.
3. Press right mouse while holstered → confirm ADS does not activate, no errors in Output.
4. Press 1 to equip AKS74.
5. Confirm existing equip animation (rbxassetid://139265999638776) plays.
6. Confirm existing idle animation (rbxassetid://75961893882956) loops.
7. Right mouse to ADS → confirm AKS_ADS (rbxassetid://134918319490586) plays once.
8. Confirm after adsIn finishes, the final ADS pose is held/frozen (no loop, no return to idle).
9. Confirm fake ADS idle breathing/sway is subtle (very small amplitude, not distracting).
10. Fire while ADS → confirm AKS_ADS_FIRE (rbxassetid://138021695403324) plays instead of normal fire.
11. Fire multiple shots while ADS → confirm adsFire restarts cleanly each shot, ADS pose stays held between shots.
12. Right mouse again to exit ADS → confirm AKS_UNADS (rbxassetid://132508450718728) plays once.
13. Confirm after adsOut completes, normal idle animation (rbxassetid://75961893882956) resumes.
14. Enter ADS, then press R to reload → confirm ADS exits immediately, reload animation plays cleanly.
15. Holster (press 1) while ADS → confirm all ADS tracks stop, no ADS pose remains frozen.
16. Re-equip AKS74 → confirm ADS state is reset (isAiming = false, adsIdleTime = 0).
17. Confirm camera.CFrame behavior is unchanged (no FOV zoom, no camera movement).
18. Confirm there is no FOV zoom when ADS (FieldOfView stays at default ~70).
19. Confirm no new remotes were created (check ReplicatedStorage/Remotes — only existing remotes present).
20. Confirm no server combat, damage, ammo, reload, health, or raycast behavior changed (fire still hits at same accuracy/damage).
21. Confirm no errors in Output panel.
22. Sprint (LeftShift) while ADS → confirm run animation does not override ADS pose.
23. Enter RESULTS phase while ADS → confirm viewmodel hides cleanly, ADS state clears on next equip.

**If MCP is unavailable:** Mark this entry "needs Studio verification" and perform the 23 steps manually in Studio before deploying to production.

---

## [2026-05-29] — AKS74 third-person world weapon model attachment (WorldWeaponService)

### Summary

Adds server-side attachment of a gun-only AKS74 world model to the player's R6 Right Arm when equipped. The model is visible in third-person and to other players. Motor6D (not Weld/WeldConstraint) is used so character animations drive the arm correctly. Attachment is controlled by the new `WeaponEquipState` RemoteEvent.

No animation playback changes. No camera changes. No combat, damage, ammo, or movement changes. MCP/Studio verification required — see DEBT-062.

**Asset precondition:** `ReplicatedStorage/WorldModels/AKS74` must be created manually in Studio as a gun-only Model with a BasePart named Handle. If missing, WorldWeaponService logs with Logger.warn() and returns without attaching; gameplay continues normally.

### New file: `src/server/WorldWeaponService.server.lua`

Self-starting server Script following the existing `.server.lua` service pattern. No central ServerInit.lua exists in this project.

Public API:
- `WorldWeaponService:Init()` — connects remote handler, PlayerAdded/PlayerRemoving, CharacterAdded/CharacterRemoving
- `WorldWeaponService:EquipWeapon(player, weaponName)` — validates, clones WorldModels/AKS74, attaches Handle to Right Arm via Motor6D
- `WorldWeaponService:HolsterWeapon(player)` — removes EquippedWorldWeapon model and WorldWeaponGrip Motor6D
- `WorldWeaponService:IsWeaponEquipped(player): boolean`
- `WorldWeaponService:CleanupPlayer(player)` — called on PlayerRemoving; disconnects all lifecycle connections

Remote validation: non-string weaponName, non-boolean isEquipped, unknown weapon name, and any weapon other than AKS74 all log via Logger.warn() and return early without crashing.

Character lifecycle: CharacterRemoving removes world weapon from departing character; CharacterAdded resets state for new character; PlayerRemoving calls CleanupPlayer.

### Changes to `src/server/RemoteSetup.server.lua`

- Added `makeEvent("WeaponEquipState")`.

### Changes to `src/client/GunController.lua`

- Added `WeaponEquipState` remote reference (WaitForChild).
- Key 1 equip: fires `WeaponEquipState:FireServer("AKS74", true)` after equipping viewmodel.
- Key 1 holster: fires `WeaponEquipState:FireServer("AKS74", false)` after holstering viewmodel.
- No new equip state created; existing `equippedWeaponName` variable preserved.

### Changes to `src/shared/Constants.lua`

- `WORLD_WEAPON_FOLDER_NAME = "WorldModels"`
- `WORLD_WEAPON_HANDLE_PART_NAME = "Handle"`
- `WORLD_WEAPON_CHARACTER_MODEL_NAME = "EquippedWorldWeapon"`
- `WORLD_WEAPON_GRIP_MOTOR_NAME = "WorldWeaponGrip"`
- `WORLD_WEAPON_R6_RIGHT_ARM_NAME = "Right Arm"`
- `WORLD_AKS74_GRIP_C0 = CFrame.new(0, -1, -0.5) * CFrame.Angles(0, math.rad(90), 0)` (initial tuning value)
- `WORLD_AKS74_GRIP_C1 = CFrame.new(0, 0, 0)` (initial tuning value)

### Changes to `src/shared/WeaponData.lua`

- Added `worldModelName = "AKS74"` to `WeaponData["AKS74"]`.

### Changes to `docs/PROJECT_MAP.md`

- Added `WeaponEquipState` to the remote registry: fired by `GunController.lua`, listened by `WorldWeaponService.server.lua`.

---

## [2026-05-29] — Viewmodel bob, sway, landing dip, slide tilt + slide/vault guards

### Summary

Implements all viewmodel motion effects through `MovementController:GetViewmodelAddCFrame()`, which ViewModelController already multiplies into its PivotTo chain. All effects are viewmodel-only — no `camera.CFrame`, `CameraOffset`, `FieldOfView`, or `CameraType` changes. MCP/Studio verification required.

Also adds `isFalling` guard to slide entry (blocks slide while airborne).

### Effects implemented (all in `MovementController`)

**Camera bob (3 tiers):** sinusoidal Y + lateral X bob while moving; walk (0.035 stud / 2.2 Hz), sprint (0.055 / 3.0 Hz), crouch (0.015 / 1.8 Hz). Subtle roll derived from lateral displacement. Fades in/out on movement start/stop. Suppressed during slide, vault, fall, and landing-lock.

**Camera sway:** accumulates `UserInputService:GetMouseDelta()` each Heartbeat. Yaw sway 0.005 deg/px; pitch 0.003 deg/px. Max 3°; exponential decay rate 5/s. Gun lags opposite to camera rotation, giving a natural follow-through feel.

**Landing camera dip:** Y impulse set inside `playLandingAnimation()` based on tier — Light 0.06 stud, Medium 0.14, Heavy 0.28. Exponential decay rate 10/s (~0.4 s recovery). Matches landing animation tiers.

**Slide tilt:** roll tilt during slide; direction driven by dot(camera-right, slideDirection) × 5°. Lerps in/out at speed 8/s.

### Guards added

- **Slide airborne block:** `isFalling` guard added to `crouchBeginConn` slide path. Players cannot trigger a slide while airborne (pressing C at the apex of a jump no longer queues a slide on landing).

### Vault (existing guards confirmed sufficient)
`canAttemptVault()` already checks: cooldown (0.65 s), `movementState.isCrouching`, `isLandingMovementLocked`, `isSliding`, `isSprintStopPlaying`. No additional guards needed for the requested scope.

### New constants (all in `Constants.lua` under "Viewmodel effects")

`VIEWMODEL_EFFECTS_ENABLED`, `VIEWMODEL_BOB_ENABLED`, 6 bob values (amplitude/frequency × 3 tiers), `VIEWMODEL_BOB_LATERAL_FACTOR`, `VIEWMODEL_BOB_TILT_FACTOR`, `VIEWMODEL_BOB_FADE_SPEED`, `VIEWMODEL_SWAY_ENABLED`, `VIEWMODEL_SWAY_HORIZONTAL_FACTOR`, `VIEWMODEL_SWAY_VERTICAL_FACTOR`, `VIEWMODEL_SWAY_MAX`, `VIEWMODEL_SWAY_DECAY`, `VIEWMODEL_LANDING_DIP_ENABLED`, 3 landing dip values, `VIEWMODEL_LANDING_DIP_DECAY`, `VIEWMODEL_SLIDE_TILT_ENABLED`, `VIEWMODEL_SLIDE_TILT_MAX`, `VIEWMODEL_SLIDE_TILT_SPEED`.

---

## [2026-05-29] — Viewmodel camera depth offset (weapon closer to camera)

### Summary

Adds `Constants.VIEWMODEL_CAMERA_EXTRA_OFFSET` (a tunable `CFrame`) that shifts the entire viewmodel in camera space before the recoil/bob/BASE_OFFSET chain. Starting value: `CFrame.new(0, 0, -1.2)` — moves the model 1.2 studs toward the camera so the weapon fills the lower portion of the screen closer to the reference Blender viewport. Tune the Z component in Constants.lua; negative = closer, positive = farther. X/Y shift the model laterally/vertically in camera space if needed.

No animation changes. No server changes. No camera.CFrame writes. MCP/Studio verification required to confirm the Z value feels right in play mode.

### Changes to `src/shared/Constants.lua`

- Added `Constants.VIEWMODEL_CAMERA_EXTRA_OFFSET = CFrame.new(0, 0, -1.2)`.

### Changes to `src/client/ViewModelController.lua`

- Added module-level `CAMERA_EXTRA_OFFSET` local (reads `Constants.VIEWMODEL_CAMERA_EXTRA_OFFSET` once at load).
- Applied it in the RenderStepped `PivotTo` chain: `cam.CFrame * CAMERA_EXTRA_OFFSET * viewRecoilCFrame * moveCF * BASE_OFFSET * recoilOffset`.

---

## [2026-05-29] — AKS74 first-person fire, reload, and run viewmodel animations

### Summary

Extends the AKS74 first-person viewmodel animation system with fire, reload, and sprint/run animation playback.  The equip → idle foundation from 2026-05-28 is unchanged; this task adds the remaining three animation states.

**Animation priority order (highest to lowest):** Reload ≥ Fire > Run > Idle.
- Left-click / fire: plays fire one-shot (`rbxassetid://116185608269786`) over the current base layer (idle or run).  Restartable per shot.  Blocked during reload.
- R / reload: plays reload one-shot (`rbxassetid://116675003285739`).  Not restartable while playing.  Stops run; resumes run (if still sprinting) or idle on completion.
- Sprint: GunController polls `MovementController:GetMoveState()` every RenderStepped and calls `ViewModelController:SetRunning(isSprinting)`.  While sprinting and equipped, run track (`rbxassetid://111133092181267`) replaces idle; run stops and idle resumes when sprinting ends.

No ADS, no recoil changes, no muzzle flash changes, no camera changes, no movement speed changes, no new remotes, no server changes.  MCP/Studio verification not yet performed — see DEBT-061.

### Changes to `src/shared/WeaponData.lua`

- Updated `WeaponData["AKS74"].animations.firstPerson.reload`: `"rbxassetid://0"` → `"rbxassetid://116675003285739"`.
- Added `WeaponData["AKS74"].animations.firstPerson.run = "rbxassetid://111133092181267"`.

### Changes to `src/client/ViewModelController.lua`

**New state variables:**
- `weaponFireTrack: AnimationTrack?` — one-shot fire; Action priority.
- `weaponReloadTrack: AnimationTrack?` — one-shot reload; Action priority.
- `weaponRunTrack: AnimationTrack?` — looped run/sprint; Movement priority.
- `isReloading: boolean` — true while reload one-shot is playing; blocks fire and run.
- `isRunning: boolean` — true while GunController reports sprint with weapon equipped.

**Extended existing methods:**
- `init()`: clears the three new tracks and resets `isReloading`, `isRunning`.
- `StopWeaponAnimations()`: stops/destroys the three new tracks; resets `isReloading`, `isRunning`.
- `_setupWeaponAnimations()`: loads fire, reload, and run tracks with correct `Looped` and `Priority` values.  Sets priorities on equip (Action) and idle (Idle) tracks too.
- `PlayFireAnimation()`: adds actual fire track play (stop+restart for per-shot restartability); now returns early while `isReloading`.
- `PlayEquipAnimation()`: Stopped callback now chains to run (if `isRunning`) or idle (fallback) instead of always idle.

**New public methods:**
- `PlayRunAnimation()` — plays run track; no-op if none loaded.
- `PlayReloadAnimation()` — one-shot reload with spam guard; stops fire/run/idle, plays reload, resumes run or idle in Stopped callback.
- `SetRunning(isSprinting: boolean)` — called each frame by GunController; manages run ↔ idle transition; no-op while holstered, while `isSprinting == isRunning`, or while reloading (deferred to Stopped callback).

### Changes to `src/client/GunController.lua`

- Reload `InputBegan` handler: added `ViewModelController:PlayReloadAnimation()` call after `SoundController:PlayReload()`.
- `RenderStepped` loop: added sprint detection — when `equippedWeaponName ~= nil`, reads `MovementController:GetMoveState() == "Sprinting"` and calls `ViewModelController:SetRunning(isSprinting)` each frame.  No new module dependency (MovementController already required).

---

## [2026-05-28] — AKS74 first-person equip / holster foundation

### Summary

Adds the smallest possible first-person equip / holster scaffold for the AKS74.  Key 1 toggles the weapon on and off.  Equipping clones `ReplicatedStorage/ViewModels/AKS74`, plays the first-person equip animation once (`rbxassetid://139265999638776`), then loops the idle animation (`rbxassetid://75961893882956`).  Holstering stops all animations and destroys the clone.  Left-click fire and R reload are now gated on the weapon being equipped.  No fire animation, no reload animation, no sprint-lowered, no ADS, no recoil, no muzzle flash, no third-person world model animation, no new remotes.  Server-side weapon identity (`Constants.DEFAULT_WEAPON = "AR15"`) and all damage / hit / ammo / health logic are unchanged.

The AR15 viewmodel no longer auto-equips on spawn.  The viewmodel starts holstered; the player must press key 1 to equip the AKS74.  This replaces the previous `init()` AR15 auto-clone behavior.

MCP/Studio verification not yet performed — see DEBT-059 and DEBT-060 for required verification checklist.

### Changes to `src/shared/WeaponData.lua`

- Added `WeaponData["AKS74"]` entry: `displayName`, `viewModelName = "AKS74"`, `animations.firstPerson` (equip / idle / fire / reload IDs), `animations.thirdPerson` (stored for future use, not used at runtime).

### Changes to `src/shared/Constants.lua`

- Added `Constants.DEFAULT_VIEWMODEL_WEAPON = "AKS74"` — weapon equipped by key 1.
- Added `Constants.VIEWMODEL_EQUIP_KEY = Enum.KeyCode.One` — toggle key.
- Added `Constants.VIEWMODEL_FOLDER_NAME = "ViewModels"` — ReplicatedStorage folder name.
- Added `Constants.VIEWMODEL_DEFAULT_ROOT_PART_NAME = "HumanoidRootPart"` — primary rig root name.
- Added `Constants.VIEWMODEL_FALLBACK_ROOT_PART_NAME = "RootPart"` — fallback if HRP absent.

### Changes to `src/client/ViewModelController.lua`

**Architecture:**
- `init()` now clears all state without cloning any weapon (weapon starts holstered).  The previous AR15 auto-clone on `init()` / `CharacterAdded` is removed.
- `setVisibility()` moved from a closure inside `Start()` to module level so `EquipWeapon` and `HolsterWeapon` can call it directly.
- `WeaponData` added as a required dependency (no circular: ViewModelController → WeaponData only).
- `shouldShowViewModel()` unchanged — still gates on `FORCE_FIRST_PERSON + ACTIVE phase + model ~= nil`.
- The `if not self.model then return end` guard in `Start()` is removed (nil model is now normal).

**New state (module-level):**
- `equippedWeaponName: string?` — nil while holstered.
- `weaponEquipTrack: AnimationTrack?` — first-person equip one-shot.
- `weaponIdleTrack: AnimationTrack?` — first-person idle loop.

**New public methods:**
- `EquipWeapon(weaponName: string)` — clone, configure, compute BASE_OFFSET, load tracks, apply visibility, play equip → idle sequence.
- `HolsterWeapon()` — stop tracks, destroy clone, clear state.
- `IsWeaponEquipped(): boolean` — returns true while equipped.
- `PlayEquipAnimation()` — play equip track once; chain to PlayIdleAnimation() via Stopped.
- `PlayIdleAnimation()` — play idle track (looped).
- `StopWeaponAnimations()` — stop and destroy all loaded weapon tracks.

**New private helper:**
- `_setupWeaponAnimations(weaponName, data)` — finds or creates `AnimationController + Animator`, loads equip and idle tracks from `WeaponData.animations.firstPerson`.

**Preserved:**
- `PlayFireAnimation()`, `SetRecoilOffset()`, `GetBarrelTipCFrame()` — unchanged.
- `RoundStateChanged` listener and `RenderStepped` PivotTo loop — unchanged.
- `HELPER_PARTS`, `RECOIL_DIST / RATE`, `MUZZLE_FALLBACK_DIST` — unchanged.
- `applyCameraMode()` and `CharacterAdded` respawn handler — unchanged behavior; `init()` now called instead of AR15 clone path.

### Changes to `src/client/GunController.lua`

- Added `local equippedWeaponName: string? = nil` — presentation-only equip gate.
- Added `local _connections: { RBXScriptConnection } = {}` — cleanup table for new connections.
- Added `UserInputService.InputBegan` handler for `Constants.VIEWMODEL_EQUIP_KEY` (key 1): toggles `ViewModelController:EquipWeapon` / `HolsterWeapon` and mirrors state in `equippedWeaponName`. Connection stored in `_connections`.
- Added `LocalPlayer.CharacterAdded` handler: clears `equippedWeaponName` on respawn (keeps GunController in sync with ViewModelController's `init()` holster). Connection stored in `_connections`.
- Left-click fire handler: added `if equippedWeaponName == nil then return end` guard after MouseButton1 check.
- Reload handler: added `if equippedWeaponName == nil then return end` guard after KeyCode.R check.

### Changes to `docs/TECHNICAL_DEBT.md`

- Added DEBT-059: AKS74 equip/holster is client-only; server fires as AR15 (worsens DEBT-013).
- Added DEBT-060: AKS74 animation playback not verified in Studio.

### Studio verification

MCP unavailable at commit time. See DEBT-059 verification checklist (items 1–8) before marking this entry resolved.

---

## [2026-05-28] — Stage 4: Custom mouse-lock camera-yaw body facing + 8-direction animation hysteresis

### Summary

Redesigned the custom mouse-lock walking body-rotation system to eliminate the camera-swing artifact that occurred when walking backward in shift-lock mode. Root cause: Stage 3L was setting `Humanoid.AutoRotate = true` during backward walking, allowing the Roblox physics engine to rotate `HumanoidRootPart` toward `MoveDirection`. In LockCenter mode, this rotation physically dragged the camera and produced a visible arc. Stage 4 removes Stage 3L entirely — the body now always faces camera yaw during walking (including backward). The camera-relative direction name (Backward / BackwardLeft / BackwardRight) drives animation selection only. The Bug 1 animation unification (`BACKPEDAL_UNIFY_BACKWARD_ANIMATION`) is also removed; `WalkBackwardLeft` and `WalkBackwardRight` diagonal animations are restored and protected from jitter by a new time-based hysteresis system.

### Changes to `src/shared/Constants.lua`

**Removed (Stage 3L constants, now dead):**
- `BACKPEDAL_TURN_ENABLED` — removed (Stage 3L removed)
- `BACKPEDAL_ENTRY_DEG_PER_FRAME` — removed (Stage 3L removed)
- `BACKPEDAL_TURN_DEG_PER_FRAME` — removed (Stage 3L removed)
- `BACKPEDAL_SPEED_THRESHOLD_DEG` — removed (Stage 3L removed)
- `BACKPEDAL_UNIFY_BACKWARD_ANIMATION` — removed (Bug 1 workaround, no longer needed)

**Added (Stage 4 constants):**
- `CUSTOM_MOUSE_LOCK_WALK_FACES_CAMERA = true` — master switch for camera-yaw walk facing
- `CUSTOM_MOUSE_LOCK_WALK_AUTOROTATE = false` — use CFrame write (not AutoRotate) for walk body yaw
- `CUSTOM_MOUSE_LOCK_SPRINT_AUTOROTATE = true` — AutoRotate mode for sprint (currently unused; Stage 3G active)
- `CUSTOM_MOUSE_LOCK_BODY_YAW_LERP_SPEED = 18` — °/frame for camera-yaw body tracking during walk
- `MOVEMENT_DIRECTION_MIN_SWITCH_INTERVAL = 0.08` — hysteresis: minimum seconds between accepted direction changes
- `MOVEMENT_DIRECTION_CROSSFADE_TIME = 0.12` — crossfade (s) for normal walking direction transitions
- `MOVEMENT_BACK_DIRECTION_CROSSFADE_TIME = 0.10` — crossfade (s) for backward-cluster transitions
- `MOVEMENT_DIRECTION_HYSTERESIS_DEGREES = 10` — angle threshold (reserved for future angle-based hysteresis)
- `MOVEMENT_DIRECTION_DEBUG = true` — log each hysteresis hold/accept decision

### Changes to `src/client/MovementController.lua`

**Removed:**
- `local isBackpedalAutoRotating: boolean` state variable and all 5 reference sites (Stage 3L block, exit block, 3 reset sites)
- Stage 3L block in `applyCharacterFacing()`: the conditional that set `hum.AutoRotate = true` during backward walking
- Stage 3L exit block: the cleanup that restored `AutoRotate = false`
- Bug 1 unification guards in `updateMovementAnimation()`: `if customMouseLocked and BACKPEDAL_TURN_ENABLED` blocks that mapped BackwardLeft/BackwardRight → WalkBackward
- Bug 1 unification guards in `getDesiredStandingLocomotionKey()`: same two blocks

**Added:**
- `local lastStableDirectionName: string = ""` and `local lastDirectionSwitchTime: number = 0` — hysteresis state (reset on respawn, mouse-lock disable, destroy)
- `getFlatCameraYawDirection(): Vector3?` — returns flat XZ camera look unit vector (alias of `getCameraFlatLookVector()` with semantic naming for body-yaw context)
- `shouldBodyFaceCameraDuringMouseLock(): boolean` — returns true for walk/idle/crouch states; false for sprint, tactical sprint, sprint-stop, landing lock
- `updateCustomMouseLockBodyYaw()` — calls `rotateCharacterCapped(flatLook, BODY_YAW_LERP_SPEED)` for camera-yaw CFrame write; sprint guard defers to `CUSTOM_MOUSE_LOCK_SPRINT_AUTOROTATE`
- `chooseDirectionalAnimationWithHysteresis(rawDirectionName, now)` — returns stable direction name, suppressing oscillation faster than `MOVEMENT_DIRECTION_MIN_SWITCH_INTERVAL`; logs hold/accept when `MOVEMENT_DIRECTION_DEBUG` is true
- `playMovementAnimation(animationName, fadeTime?)` — optional `fadeTime` parameter; `nil` falls back to `MOVEMENT_ANIMATION_FADE_TIME`

**Modified:**
- `applyCharacterFacing()` Stage 3L block → replaced with single `if shouldBodyFaceCameraDuringMouseLock() then updateCustomMouseLockBodyYaw() end`
- `updateMovementAnimation()`: dirName reassigned through `chooseDirectionalAnimationWithHysteresis()` before walking branch; `playMovementAnimation(animName)` → `playMovementAnimation(animName, moveFadeTime)` with backward-cluster crossfade selection
- BackwardLeft/BackwardRight branches in `updateMovementAnimation()` and `getDesiredStandingLocomotionKey()` restored to full diagonal animation selection (WalkBackwardLeft/WalkBackwardRight → WalkBackward fallback)

### Studio verification

Rojo build clean. MCP play-mode test: all 9 new constants confirmed correct values; removed constants confirmed nil; no runtime errors on character load. Observable play-mode behavior (camera-swing absence, diagonal animation correctness, hysteresis) requires manual Studio testing — see DEBT-058.

---

## [2026-05-27] — Fix vault triggering against walls (XZ speed guard + grounded guard)

### Summary

Vault was firing when a player held W against a wall and pressed Space. Root cause: `canAttemptVault()` gated on `movementState.isMoving` (derived from `Humanoid.MoveDirection`, non-zero even when wall-blocked), not on actual velocity. Two guards added: (1) `VAULT_MIN_APPROACH_SPEED = 3.0` — rejects vault when `HRP.AssemblyLinearVelocity.XZ.Magnitude` is below the threshold; (2) `VAULT_REQUIRE_GROUNDED = true` — rejects vault when `Humanoid.FloorMaterial == Enum.Material.Air`, preventing Space from triggering a vault while airborne near a wall.

### Changes to `src/shared/Constants.lua`

- `VAULT_MIN_APPROACH_SPEED = 3.0` — minimum XZ speed (studs/s) to attempt vault.
- `VAULT_REQUIRE_GROUNDED = true` — blocks vault when character is airborne.

### Changes to `src/client/MovementController.lua`

- `canAttemptVault()`: added XZ speed gate (checks `AssemblyLinearVelocity.XZ.Magnitude < VAULT_MIN_APPROACH_SPEED`) and grounded gate (`FloorMaterial == Air`) after the existing `VAULT_REQUIRE_MOVING` check.

### MCP verification

MCP unavailable at commit time — Studio verification pending (see DEBT-057).

---

## [2026-05-26] — Fix vault (phase gate + Heartbeat arc) and sprint backward choppiness

### Summary

Two issues fixed. (1) **Vault**: `VAULT_REQUIRE_ACTIVE_PHASE` was `true`, blocking vault in LOBBY/PREP (set to `false`). The original `TweenService:Create(hrp, …, {CFrame=target})` approach moved the HRP linearly through the obstacle face, which physics collision prevented from completing; replaced with a Heartbeat-driven parabolic arc that rises over the obstacle. `Humanoid.PlatformStand = true` disables floor-sticking during the arc; `AssemblyLinearVelocity` is zeroed at vault start. `VAULT_ARC_PEAK_CLEARANCE = 1.5` provides the buffer above the obstacle top. (2) **Sprint backward choppiness**: `SPRINT_BACKWARD_INSTANT_TURN` used a hardcoded alpha of `1.0`, causing instant 45° body snaps when transitioning between BackwardLeft ↔ Backward ↔ BackwardRight while sprinting. Replaced with `SPRINT_BACKWARD_BODY_FACING_LERP_ALPHA = 0.40`, which completes the initial 180° reversal in ~5 frames (fast/responsive) while making diagonal transitions smooth.

### Changes to `src/shared/Constants.lua`

- `VAULT_REQUIRE_ACTIVE_PHASE = false` (was `true`).
- `VAULT_ARC_PEAK_CLEARANCE = 1.5` — studs of clearance above obstacle top for arc peak.
- `SPRINT_BACKWARD_BODY_FACING_LERP_ALPHA = 0.40` — replaces hardcoded `1.0` for backward sprint body facing.

### Changes to `src/client/MovementController.lua`

- Replaced `vaultActiveTween: Tween?` with Heartbeat arc state vars (`vaultMoveConn`, `vaultMoveStartPos`, `vaultMoveEndPos`, `vaultMoveArcHeight`, `vaultMoveStartYaw`, `vaultMoveStartTime`, `vaultMoveDuration`).
- `clearVaultTween()` → `clearVaultMove()`: disconnects Heartbeat conn + restores `PlatformStand` on interrupt.
- `detectVault()` return type extended with `obstacleTopY: number`.
- `moveCharacterThroughVault()` rewritten: `PlatformStand = true`, zeros velocity, Heartbeat arc with `sin(π*t)` rise + Quad-InOut eased XYZ lerp, restores `PlatformStand = false` on complete.
- `startVault()` passes `result.obstacleTopY` to `moveCharacterThroughVault()`.
- `applyCharacterFacing()` sprint backward: `1.0` → `Constants.SPRINT_BACKWARD_BODY_FACING_LERP_ALPHA`.
- All 4 cleanup paths (`destroy`, respawn, phase exit, inside `moveCharacterThroughVault`) updated to `clearVaultMove()`.

### Studio verification

Rojo build clean. MCP unavailable at commit time — runtime behavior requires in-play-mode Studio verification. See DEBT-055 (updated) and DEBT-056 (new).

---

## [2026-05-26] — Bug fixes: shift-lock backpedal animation choppiness, camera offset rotation, post-slide direction snap

### Summary

Three shift-lock movement bugs fixed. (1) Backward-diagonal animation oscillation: when backpedal body-turn is active, `BackwardLeft`/`BackwardRight` now unify to `WalkBackward` instead of toggling between WalkBackwardLeft/WalkBackwardRight, eliminating the choppy animation flicker. (2) Camera offset orbit: `updateSprintCameraOffset()` now dot-product-corrects `Humanoid.CameraOffset.X` each Heartbeat so the right-shoulder offset stays visually locked to the camera's right side regardless of body LERP rotation during backpedal. (3) Post-slide direction snap: a `slideExitFacingHoldEndTime` timestamp keeps the slide-facing yaw locked for `SLIDE_EXIT_FACING_HOLD_DURATION` (0.25 s) after `SlideExit Stopped`, preventing the first Heartbeat from snapping the character to camera-yaw.

### Changes to `src/shared/Constants.lua`

- `BACKPEDAL_UNIFY_BACKWARD_ANIMATION = true` — new flag (Bug 1).
- `BACKPEDAL_CAMERA_OFFSET_CORRECTION = true` — new flag (Bug 2).
- `SLIDE_EXIT_FACING_HOLD_DURATION = 0.25` — new constant (Bug 3).

### Changes to `src/client/MovementController.lua`

- `local slideExitFacingHoldEndTime: number = 0` — new state variable (Bug 3).
- `updateSprintCameraOffset()` — rewritten to apply dot-product camera-offset correction when `BACKPEDAL_CAMERA_OFFSET_CORRECTION` is true (Bug 2).
- `updateMovementAnimation()` — `BackwardLeft`/`BackwardRight` blocks now unify to `WalkBackward` when `customMouseLocked and BACKPEDAL_TURN_ENABLED` (Bug 1).
- `getDesiredStandingLocomotionKey()` — same animation-unification change for `BackwardLeft`/`BackwardRight` (Bug 1).
- `endSlide()` SlideExit Stopped callback — sets `slideExitFacingHoldEndTime = os.clock() + SLIDE_EXIT_FACING_HOLD_DURATION` (Bug 3).
- Heartbeat facing-lock condition — extended from `isSliding or slideExitConn ~= nil` to also include `os.clock() < slideExitFacingHoldEndTime` (Bug 3).
- `slideExitFacingHoldEndTime = 0` added to respawn, `destroy()`, and phase-exit cleanup paths (Bug 3).

### Studio verification

MCP confirms all symbols present in Studio (6 occurrences of `slideExitFacingHoldEndTime`; 2 of `unify to WalkBackward`; 2 of `BACKPEDAL_CAMERA_OFFSET_CORRECTION`). Runtime behavior requires in-play-mode verification.

---

## [2026-05-26] — Stage 4A: Vault foundation (Space over valid obstacles — low + medium)

### Summary

Vault prototype implemented. Pressing Space while moving toward a vaultable obstacle (1.5–5.0 studs tall) now attempts a vault instead of a jump. Four raycasts classify the obstacle (low vs medium), confirm clearance, and find a landing position. A TweenService CFrame move carries the character over. LowVault and MediumVault one-shot animations play during the move. DEBT-052 partially resolved; DEBT-054 added for remaining gaps.

### Behaviour

- **Trigger:** Space pressed while `isMoving` and phase is ACTIVE. `canAttemptVault()` checks cooldown, crouching, landing-lock, slide, and sprint-stop guards before raycasting.
- **Detection:** 4-ray strategy — forward-low probe (obstacle face), downward ray (obstacle top), upward clearance (no ceiling), landing downward (ground exists beyond). Heights outside 1.5–5.0 studs range are rejected.
- **Vault types:** LowVault (1.5–3.5 studs) uses `VAULT_MOVE_DURATION_LOW` (0.35 s); MediumVault (3.5–5.0 studs) uses `VAULT_MOVE_DURATION_MEDIUM` (0.48 s).
- **Movement:** `TweenService:Create(hrp, TweenInfo, {CFrame=targetCF})` with `Quad InOut` easing. WalkSpeed zeroed during tween; restored by Completed callback.
- **Animation:** Unarmed_LowVault / Unarmed_MediumVault one-shots. Falls back gracefully (warn) if track absent (e.g. AR15 set has no vault IDs).
- **Space fallback:** CAS action only Sinks when a vault starts. Passes through in all other cases so Roblox jump still works normally.
- **ADS blocked** while vaulting via `IsADSBlocked()`. `GetMoveState()` returns `"Vaulting"`. New public method: `MovementController.IsVaulting()`.
- **Cleanup:** vault state cleared on respawn, destroy(), and phase-exit (direct-clear, mirrors slide pattern). `vaultCompletionToken` guards stale tween Completed callbacks.
- **Studio verification:** Pending — MCP verification was not completed at commit time. See DEBT-054 item 6.

### Changes to `src/shared/Constants.lua`

- LowVault / MediumVault animation ID comments updated from "deferred" to Stage 4A active.
- Full vault constants block added under `-- Stage 4A: Vault foundation` header:
  - `VAULT_ENABLED`, `VAULT_INPUT_KEY`, `VAULT_REQUIRE_MOVING`, `VAULT_REQUIRE_ACTIVE_PHASE`, `VAULT_COOLDOWN`
  - `LOW_VAULT_MIN/MAX_HEIGHT`, `MEDIUM_VAULT_MIN/MAX_HEIGHT`
  - `VAULT_MAX_FORWARD_DISTANCE`, `VAULT_OBSTACLE_RAY_HEIGHT_LOW/MEDIUM`, `VAULT_CLEARANCE_HEIGHT`
  - `VAULT_LANDING_FORWARD_DISTANCE`, `VAULT_LANDING_UP_OFFSET`
  - `VAULT_MOVE_DURATION_LOW`, `VAULT_MOVE_DURATION_MEDIUM`
  - `VAULT_MAX_SLOPE_NORMAL_Y`, `VAULT_LOCKS_MOVEMENT`, `VAULT_BLOCKS_SPRINT`, `VAULT_BLOCKS_CROUCH`
  - `VAULT_INPUT_PRIORITY` (2500), `VAULT_ANIMATION_SPEED_MULTIPLIER` (1.0), `VAULT_DEBUG`

### Changes to `src/client/MovementController.lua`

- `VAULT_ACTION_NAME` constant added near module top.
- Vault state variables added: `isVaulting`, `lastVaultTime`, `vaultCompletionToken`, `vaultActiveTween`.
- `applySpeed()`: Stage 4A block after slide check; WalkSpeed = 0 when `isVaulting and VAULT_LOCKS_MOVEMENT`.
- `getAnimationSpeedMultiplier()`: LowVault / MediumVault return `VAULT_ANIMATION_SPEED_MULTIPLIER`.
- Vault helpers added (Stage 4A block before Stage 2I): `clearVaultTween`, `canAttemptVault`, `getVaultMoveDirection`, `detectVault`, `playVaultAnimation`, `moveCharacterThroughVault`, `startVault`.
- `loadMovementAnimations()`: Unarmed_LowVault and Unarmed_MediumVault loaded; both marked `Looped = false`; respawn direct-clear block added.
- `updateMovementAnimation()`: `if isVaulting then return end` guard added after slide guards.
- `Start()`: CAS vault binding added before crouch binding.
- `destroy()`: `UnbindAction(VAULT_ACTION_NAME)`, `clearVaultTween()`, state reset added after slide cleanup.
- Phase-exit handler: vault state cleared (mirrors slide pattern).
- `GetMoveState()`: returns `"Vaulting"` when `isVaulting`.
- `IsADSBlocked()`: `or isVaulting` added.
- `MovementController.IsVaulting()`: new public function.
- Ready log updated to `Stage 1–4A`.

### Technical debt

- **DEBT-052** partially resolved — vault foundation implemented; server validation, camera polish, and AR15 animations remain.
- **DEBT-044** updated — LowVault + MediumVault now active for Unarmed set.
- **DEBT-054** added — vault-specific production gaps and Studio verification pending.

---

## [2026-05-26] — Stage 3O: Slide system (hold C while sprinting or tac-sprinting)

### Summary

Full slide system implemented. Holding C while sprinting or tac-sprinting triggers a slide instead of a normal crouch. Tac-sprint slides start faster and travel further. When the slide ends and the player is no longer holding C, they stand up fluidly through the SlideExit animation; if C is still held they land in a crouch. DEBT-053 resolved.

### Behaviour

- **Trigger:** C held while `isSprinting` or `isTacticalSprinting`. Cooldown (`SLIDE_COOLDOWN` = 1.5 s) prevents rapid re-triggering.
- **Speed decay:** WalkSpeed lerps from `SLIDE_SPEED` (30) to `CROUCH_SPEED` (10) over `SLIDE_DURATION` (1.0 s) every Heartbeat via `applySpeed()`. No separate loop needed.
- **Tac-sprint slide:** Starts at `SLIDE_SPEED × SLIDE_TAC_SPEED_MULTIPLIER` (1.3×, = 39) and lasts `SLIDE_DURATION × SLIDE_TAC_DURATION_MULTIPLIER` (1.75×, = 1.75 s) — both faster and further.
- **Animation sequence:** SlideInto (one-shot) → SlideIdle (loop) → SlideExit (one-shot) → CrouchIdle (if C held) or walk/idle (if C released). `slideIntoConn` / `slideExitConn` guard `updateMovementAnimation` to prevent Heartbeat interruption.
- **Exit conditions:** (a) natural timer (`task.delay` + `slideToken` stale-guard); (b) player stops moving (Heartbeat `endSlide()`); (c) Freefall entry (`clearSlideState()`).
- **Smooth stand-up:** `endSlide()` checks `UserInputService:IsKeyDown(CROUCH_HOLD_KEY)` — only enters crouch if C is still held. Otherwise SlideExit plays and the Heartbeat resumes walk/idle naturally (no jarring crouch snap).
- **ADS blocked** while sliding via `IsADSBlocked()`. `GetMoveState()` returns `"Sliding"`.
- **Respawn / destroy / phase-exit:** all clear slide state directly (no track:Stop calls — mirrors sprint-stop respawn pattern).

### Changes to `src/shared/Constants.lua`

- `SLIDE_DURATION` bumped from `0.6` → `1.0` s for more satisfying distance.
- Added `SLIDE_TAC_SPEED_MULTIPLIER = 1.3` — tac-sprint slides start at `SLIDE_SPEED × 1.3`.
- Added `SLIDE_ENABLED = true`, `SLIDE_TAC_DURATION_MULTIPLIER = 1.75`, `SLIDE_ANIMATION_SPEED_MULTIPLIER = 1.0`, `SLIDE_DEBUG = true` under Stage 3O block.

### Changes to `src/client/MovementController.lua`

- `movementState.isSliding` added to the state table and `resetState()`.
- Private state: `isSliding`, `isTacSprintSlide`, `slideStartTime`, `slideToken`, `lastSlideEndTime`, `slideIntoConn`, `slideExitConn`.
- `applySpeed()`: Stage 3O block inserted after sprint-stop check; uses `isTacSprintSlide` to pick start speed and duration.
- Helpers added: `clearSlideIntoConnection`, `clearSlideExitConnection`, `clearSlideState`, `endSlide`, `startSlide`.
- `getAnimationSpeedMultiplier()`: SlideInto / SlideIdle / SlideExit return `SLIDE_ANIMATION_SPEED_MULTIPLIER`.
- `loadMovementAnimations()`: SlideInto, SlideIdle, SlideExit loaded for Unarmed set; SlideInto and SlideExit marked as one-shots; respawn direct-clear block added.
- `updateMovementAnimation()`: two guards added — `if isSliding then return end` (SlideInto/Idle) and `if slideExitConn ~= nil then return end` (SlideExit one-shot).
- `crouchBeginConn`: slide trigger inserted before normal crouch logic; `if isSliding then return end` guard added.
- Heartbeat: `if isSliding and not movementState.isMoving then endSlide() end` added.
- Freefall handler: `clearSlideState()` called on Freefall entry.
- Phase-exit handler: direct slide state clear (no forced crouch).
- `destroy()`: direct slide state clear.
- `GetMoveState()`: `"Sliding"` returned when `isSliding`.
- `IsADSBlocked()`: `or isSliding` added.

### Technical debt

- **DEBT-053** resolved — all 10 checklist items addressed.
- **DEBT-044** updated — Unarmed slide set implemented; AR15 slide IDs not yet authored (graceful no-op fallback).

---

## [2026-05-26] — Reserve slide animation IDs in Constants (deferred — no implementation)

### Summary

Three slide animation IDs have been reserved in `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed` for future use. No slide movement, input, state machine, speed logic, or camera changes have been added. IDs follow the same "reserved but not loaded" precedent established for vault animations (DEBT-052).

**What changed:**

- `SlideInto = "rbxassetid://101320244227398"` — slide entry one-shot; reserved, not loaded.
- `SlideIdle  = "rbxassetid://123763519906235"` — slide idle loop; reserved, not loaded.
- `SlideExit  = "rbxassetid://89774397391406"` — slide exit one-shot; reserved, not loaded.

### Changes to `src/shared/Constants.lua`

- Added `SlideInto`, `SlideIdle`, `SlideExit` to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`, below the existing vault IDs. Comment block marks all three as deferred and references DEBT-053.

### No client, server, or gameplay changes

`src/client/MovementController.lua`, all server files, `WeaponData.lua`, remotes, and `default.project.json` are **unchanged**. No animation loading, no input binding, no speed changes, no camera tilt, no new remotes.

### New technical debt entry

- **DEBT-053** added to `docs/TECHNICAL_DEBT.md` — documents the full slide system design checklist (input binding, state, speed decay, animation sequence, exit conditions, camera tilt decision, AR15 handling, crouch interaction, server position tolerance).

---

## [2026-05-26] — Stage 3N: Instant backward turn during backward sprint in shift lock

### Summary

When holding S+Shift in shift lock, the character now snaps to face the backward direction on the first Heartbeat instead of slowly lerping there over ~10–15 frames. The normal 0.18 LERP sweep was taking ~170–250 ms to complete the 180° pivot, during which the character ran backward while still visually facing forward. Now the body rotates instantly the moment a backward sprint direction is detected.

**What changed:**

- Stage 3G block in `applyCharacterFacing()` — added a `directionName` check before calling `faceCharacterTowardsDirection`. When `SPRINT_BACKWARD_INSTANT_TURN = true` and direction is Backward/BackwardLeft/BackwardRight, passes `alphaOverride = 1.0` (immediate snap). All other sprint directions continue to use the smooth 0.18 LERP unchanged.

### Changes to `src/shared/Constants.lua`

- `SPRINT_BACKWARD_INSTANT_TURN = true` — master switch. Set false to restore the slow LERP for backward sprint.

### No animation ID changes, no camera.CFrame writes, no HipHeight/FOV/server changes

---

## [2026-05-26] — Stage 3M: Fluid crouch enter/exit transitions

### Summary

Three combined changes make the crouch-in and crouch-out feel slower and more physically committed:

1. **Blend fade times doubled (~2×)** — all four crossfade constants increased so the visual blend between standing and crouched poses is noticeably gradual rather than instant.
2. **ExitCrouch one-shot speed halved (0.9× → 0.5×)** — when standing up from still, the clip plays at half speed, giving a deliberate "getting up" motion.
3. **Speed lock during crouch-exit** — `WalkSpeed` is held at `CROUCH_SPEED` for the full exit animation window. Without this, speed snapped to `WALK_SPEED` the instant C was released while the body was still blending to standing. Now the speed restores the moment `resumeStandingLocomotionAfterCrouch()` is called (animation blend starts).

**What changed:**

- `isCrouchExitTransitioning: boolean` state variable — true while exit blend is in progress.
- `crouchExitTransitionVersion: number` — monotonic counter that invalidates any stale `task.delay` callbacks from previous exit cycles.
- `applySpeed()` — new early-return when `isCrouchExitTransitioning and CROUCH_TRANSITION_SPEED_LOCK_ENABLED`: holds `WalkSpeed = CROUCH_SPEED`.
- `resumeStandingLocomotionAfterCrouch()` — clears `isCrouchExitTransitioning` and calls `applySpeed()` immediately (speed restores same frame, no Heartbeat gap).
- `crouchEndConn` — sets `isCrouchExitTransitioning = true` + increments version before Stage 2S exits; adds `task.delay` safety-net for legacy path (inactive by default).
- `crouchBeginConn` — clears flag + increments version on re-enter (quick C-press after release cancels exit lock).
- Flag also cleared on: `loadMovementAnimations` respawn, `destroy()`, phase-exit handler.

### Changes to `src/shared/Constants.lua`

| Constant | Old | New |
|---|---|---|
| `CROUCH_DIRECT_BLEND_FADE_TIME` | 0.12 | 0.28 |
| `CROUCH_DIRECT_BLEND_MOVING_FADE_TIME` | 0.10 | 0.22 |
| `CROUCH_EXIT_DIRECT_BLEND_FADE_TIME` | 0.10 | 0.22 |
| `CROUCH_EXIT_IDLE_BLEND_FADE_TIME` | 0.12 | 0.28 |
| `MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER` | 0.9 | 0.5 |
| `CROUCH_TRANSITION_SPEED_LOCK_ENABLED` | *(new)* | `true` |

### No animation ID changes, no camera.CFrame writes, no HipHeight/FOV/server changes

**Studio verification:** Needs manual Studio playtest — MCP keyboard input does not reach `InputBegan` in Studio play mode.

---

## [2026-05-26] — Stage 3L: Backpedal turn-around in shift lock

### Summary

When the player walks backward (Backward / BackwardLeft / BackwardRight) in shift lock, the character body now sweeps around to face the move direction rather than staring forward while playing the WalkBackward animation. The pivot uses a per-frame LERP (alpha 0.25, ~8–10 frames at 60 fps) so the body visibly rotates rather than snapping.

**What changed:**

- New Stage 3L block added in `applyCharacterFacing()` (after Stage 3G, before camera-yaw fallback). Checks `directionName` ∈ {Backward, BackwardLeft, BackwardRight} while in shift lock, not sprinting, not crouching, not in tactical sprint, not during sprint-stop or landing lock. Calls `faceCharacterTowardsDirection(moveDir, BACKPEDAL_TURN_LERP_ALPHA)` and returns; otherwise falls through to camera-yaw as before.
- `faceCharacterTowardsDirection(direction, alphaOverride?)` gains an optional second parameter. When non-nil it replaces `SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA` for that call. Sprint paths pass nil (unchanged). Stage 3L passes `BACKPEDAL_TURN_LERP_ALPHA`.
- When the player stops pressing backward, `directionName` immediately leaves the Backward* set and the camera-yaw CFrame write resumes — character faces camera forward again on the next Heartbeat.

### Changes to `src/shared/Constants.lua`

- `BACKPEDAL_TURN_ENABLED = true` — master switch; set false to revert to original camera-yaw facing during backward movement.
- `BACKPEDAL_TURN_LERP_ALPHA = 0.25` — per-Heartbeat LERP alpha for the pivot sweep (higher than sprint 0.18 for a faster but still visible body turn).

### Changes to `src/client/MovementController.lua`

- `faceCharacterTowardsDirection` — optional `alphaOverride: number?` parameter added.
- Stage 3L block added in `applyCharacterFacing()`.
- File header updated.

### No animation ID changes, no camera.CFrame writes, no HipHeight/FOV/server changes

**Studio verification:** Needs manual Studio playtest — MCP keyboard input does not reach `InputBegan` in Studio play mode.

---

## [2026-05-25] — Stage 3K: Halve mouse sensitivity while tactical sprinting

### Summary

`UserInputService.MouseDeltaSensitivity` is reduced to 50% of its pre-entry value when tactical sprint activates, and restored immediately the moment tactical sprint ends through any exit path. Prevents players from snapping the camera too quickly during a committed forward run.

**What changed:**

- `applyTacticalSprintSensitivity(active: boolean)` private helper added (before `startLandingMovementLock`). Caches current sensitivity on `active=true`, restores it on `active=false`. Idempotent — double-apply and double-restore are both no-ops via the nil check on `tacticalSprintOriginalSensitivity`.
- `tacticalSprintOriginalSensitivity: number?` module-level state variable added (nil when no override is active).
- Called `applyTacticalSprintSensitivity(true)` at tactical sprint entry (InputBegan double-tap path).
- Called `applyTacticalSprintSensitivity(false)` at all six exit paths:
  - `stopTacticalSprint()` (direction-change / forward-dot failure / crouch interrupt)
  - `playSprintStopWithLock()` (Shift release after long sprint)
  - `startLandingMovementLock()` (landing suppresses sprint flags)
  - `loadMovementAnimations()` respawn block
  - Phase exit handler (direct state clear, no animation)
  - `destroy()`

### Changes to `src/shared/Constants.lua`

- `TACTICAL_SPRINT_SENSITIVITY_ENABLED = true` — master switch.
- `TACTICAL_SPRINT_SENSITIVITY_MULTIPLIER = 0.5` — fraction of current sensitivity applied on entry.

### Changes to `src/client/MovementController.lua`

- `tacticalSprintOriginalSensitivity: number?` state variable added.
- `applyTacticalSprintSensitivity(active: boolean)` helper added.
- 1 entry call + 6 exit calls wired.

### No animation ID changes, no camera.CFrame writes, no HipHeight/FOV/server changes

**Studio verification:** Needs manual Studio playtest — MCP keyboard input does not reach `InputBegan` in Studio play mode.

---

## [2026-05-25] — Stage 3J: Disable RunForwardLeft/Right — RunForward plays for all sprint directions

### Summary

RunForwardLeft and RunForwardRight animations were designed for a camera-facing body and baked their own visual diagonal lean into the clip. Combining this with Stage 3G body rotation (which rotated the body ≈20° toward MoveDirection for ForwardLeft/Right) produced a doubled-lean visual that no longer matched the desired look. Stage 3J simplifies the sprint animation system so `RunForward` always plays regardless of direction. Stage 3G body rotation (raw `MoveDirection`) provides all directional information visually — no per-direction animation switching needed.

**What changed:**

- `getSprintAnimationName()` simplified: removed all directional branching. Now always returns `getRunForwardSuffix(animSetName)` for all directions. The `directionName` parameter is still required (API preserved) but unused.
- Stage 3G block in `applyCharacterFacing()` simplified: ForwardLeft/Right special-case code (Stage 3I fixed-angle rotation) removed. All sprint directions now call `getCameraRelativeMoveDirection()` → `faceCharacterTowardsDirection()` uniformly.
- `SPRINT_DIAGONAL_BODY_ROTATION_DEGREES` marked as dead code (unused since Stage 3J) in `Constants.lua`. The constant is retained for reference; the value 20 is no longer read at runtime.

### Changes to `src/shared/Constants.lua`

- `SPRINT_DIAGONAL_BODY_ROTATION_DEGREES` comment updated: marked DEAD CODE/UNUSED since Stage 3J.

### Changes to `src/client/MovementController.lua`

- `getSprintAnimationName()`: removed ForwardLeft/Right → RunForwardLeft/Right branching. All directions return `getRunForwardSuffix(animSetName)`.
- Stage 3G block in `applyCharacterFacing()`: removed Stage 3I ForwardLeft/Right fixed-angle rotation branch. Simplified to single `getCameraRelativeMoveDirection()` → `faceCharacterTowardsDirection()` path for all sprint directions.

### No animation ID changes, no new constants, no camera.CFrame writes, no server changes

`RunForwardLeft` and `RunForwardRight` animation tracks remain loaded in `animationTracks` but are never selected at runtime.

**Studio verification:** Rojo sync needed — needs manual Studio playtest.

---

## [2026-05-25] — Stage 3I: Fix ForwardLeft/Right diagonal sprint body rotation angle

### Summary

RunForwardLeft/Right animations were designed for a camera-facing body — they bake their own visual diagonal lean into the clip. Stage 3G was also rotating the body ≈45° toward raw MoveDirection for these directions, doubling the lean and making the combined visual direction appear nearly backward (90°+ from camera-forward). Fix: for ForwardLeft/ForwardRight, rotate the body by a fixed, smaller angle from camera-forward (`SPRINT_DIAGONAL_BODY_ROTATION_DEGREES = 20`) instead of toward raw MoveDirection. All other sprint directions continue using raw MoveDirection.

**What changed:**

- `SPRINT_DIAGONAL_BODY_ROTATION_DEGREES = 20` added to `Constants.lua` (tunable; range 0–45).
- Stage 3G block in `applyCharacterFacing()` updated: ForwardLeft/Right branch computes a fixed-angle direction via 2D Y-axis rotation of camera-forward (`cos`/`sin` formula, no CFrame allocation). Non-diagonal branch unchanged (raw MoveDirection).

### Changes to `src/shared/Constants.lua`

- `SPRINT_DIAGONAL_BODY_ROTATION_DEGREES = 20` added in Stage 3G section.

### Changes to `src/client/MovementController.lua`

- Stage 3G block: `dir == "ForwardLeft" or dir == "ForwardRight"` branch added with fixed-angle rotation math. All other directions fall through to the existing `getCameraRelativeMoveDirection()` path.

---

## [2026-05-25] — Stage 3H: Camera shoulder offset disabled while sprinting in shift lock

### Summary

Removes the right-shoulder `CameraOffset` (1.75, 0, 0) while sprinting in custom mouse lock so the camera centers directly behind the character, matching the feel of normal third-person sprint. The offset is restored the moment sprint ends (next Heartbeat, ≤16ms). Tactical sprint also triggers the zero-offset path.

**What changed:**

- `SPRINT_DISABLES_CAMERA_OFFSET = true` added to `Constants.lua`.
- `updateSprintCameraOffset()` helper added to `MovementController.lua` (after `restoreNormalThirdPersonCamera()`): reads `movementState.isSprinting or isTacticalSprinting`; writes `hum.CameraOffset = Vector3.zero` while sprinting, `CUSTOM_MOUSE_LOCK_CAMERA_OFFSET` otherwise. Guarded by `~=` to avoid redundant per-frame writes.
- `updateSprintCameraOffset()` called in the Heartbeat loop after `updateSprintFov()`.

### Changes to `src/shared/Constants.lua`

- `SPRINT_DISABLES_CAMERA_OFFSET = true` added (Stage 3H section comment added).

### Changes to `src/client/MovementController.lua`

- `updateSprintCameraOffset()` helper added.
- Heartbeat: `updateSprintCameraOffset()` call added after `updateSprintFov()`.

### No animation ID changes, no camera.CFrame writes, no server changes

**Studio verification:** Rojo sync was pending at commit time — needs manual Studio playtest.

---

## [2026-05-25] — Stage 3G: Smooth sprint body-facing toward movement direction (restores Stage 3D, no camera jerk)

### Summary

Restores character body-facing toward movement direction during sprint in shift lock, using smooth per-frame lerp rather than Roblox `AutoRotate` (which caused Stage 3E camera jerk) or Stage 3D's immediate CFrame snap.

Root cause of the missing facing: Stage 3E was disabled (`SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = false`, fix commit `2c95f42`) and no replacement was installed, so `applyCharacterFacing()` fell through to the camera-yaw CFrame write for all states including sprint — character always faced camera yaw.

Fix (Stage 3G): a new block in `applyCharacterFacing()` after the Stage 3E exit block and before the camera-yaw write. When `SPRINT_SMOOTH_BODY_FACING_ENABLED = true` and the player is sprinting in mouse lock (not tactical sprint, not crouching, not sprint-stop, not landing lock), calls `getCameraRelativeMoveDirection()` → if the magnitude is above threshold, calls `faceCharacterTowardsDirection(moveDir)` and returns. `AutoRotate` stays `false` throughout — this is a direct CFrame write only, no Roblox physics rotation → no camera drag → no camera jerk. Lerp smoothing now active (`SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = true`, `SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 0.18`): body tracks direction changes over ~3–4 Heartbeat frames at 60Hz.

**What changed:**

- `SPRINT_SMOOTH_BODY_FACING_ENABLED = true` added to `Constants.lua` (Stage 3G master switch).
- `SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED` changed `false → true` (lerp now active for Stage 3G).
- `SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA` changed `1 → 0.18` (smooth per-Heartbeat tracking; ~3–4 frame response at 60Hz).
- Stage 3G block added in `MovementController.lua` `applyCharacterFacing()` between Stage 3E exit block and camera-yaw write.
- Stage 3D helpers `getCameraRelativeMoveDirection()` and `faceCharacterTowardsDirection()` are now called by Stage 3G (were dead code after Stage 3E).

### Changes to `src/shared/Constants.lua`

- `SPRINT_SMOOTH_BODY_FACING_ENABLED = true` added (new constant, Stage 3G master switch).
- `SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = false → true` (lerp enabled).
- `SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 1 → 0.18` (smooth alpha).
- Updated comments on both smoothing constants to explain Stage 3G usage.

### Changes to `src/client/MovementController.lua`

- Stage 3G block added in `applyCharacterFacing()`: `SPRINT_SMOOTH_BODY_FACING_ENABLED` guard + sprint conditions → `getCameraRelativeMoveDirection()` → `faceCharacterTowardsDirection(moveDir)` → return early.

### No animation ID changes, no camera writes, no server changes

No animation IDs, speed multipliers, camera CFrame, CameraOffset, FieldOfView, HipHeight, JumpPower, Humanoid.AutoRotate (stays false), or server-side systems were modified.

---

## [2026-05-25] — Stage 3E-fix-2: Conditional MouseBehavior reapply — fixes remaining camera jerk in shift lock

### Summary

Fixes residual camera jitter during sprint direction changes in shift lock. Root cause: `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME` was unconditionally writing `UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter` on every Heartbeat tick (~60 writes/second), even when the value was already `LockCenter`. Roblox's camera system re-centres its cursor-snap reference point each time `MouseBehavior` is written — so 60 redundant writes per second caused 60 per-second micro-resets of the camera's internal state. During sprint direction changes, when the physics position was also changing abruptly, the two events compounded into a visible side-to-side camera jerk. Fix: add a `~=` guard so the write only fires when `MouseBehavior` has actually drifted away from `LockCenter`. MCP verified: 41/41 monitored frames had `MouseBehavior` already `LockCenter` — zero redundant writes under the new guard. CoreScript-theft protection is unchanged (the write fires immediately when the value drifts).

**What changed:**

- `CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME` Heartbeat block in `MovementController.lua`: added `if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then` guard around the write. No constant changes.

### Changes to `src/client/MovementController.lua`

- Heartbeat MouseBehavior reapply changed from unconditional to conditional (`~= LockCenter` guard).

### No constant changes, no animation changes, no camera writes

---

## [2026-05-25] — Stage 3E-fix: Disable AutoRotate sprint rotation — fixes camera jerk in shift lock

### Summary

Disables Stage 3E's `Humanoid.AutoRotate = true` sprint path by setting `SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = false`. When `AutoRotate = true`, Roblox's physics engine rotates `HumanoidRootPart` toward `MoveDirection` at its own rate. In custom mouse lock, the camera is pinned relative to `HumanoidRootPart`'s yaw — so every engine body rotation snapped the camera with it, producing visible left-right camera jerk when changing sprint direction. With the constant false, `shouldUseNaturalSprintAutoRotate()` returns false immediately and sprint falls through to the same camera-yaw CFrame path used during walking in mouse lock (`AutoRotate = false`, `root.CFrame = CFrame.lookAt`). The directional sprint animations (`RunForwardLeft`, `RunForwardRight`) already communicate movement direction visually — no body rotation is needed.

**What changed:**

- `SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED` set `true → false` in `Constants.lua`. No code changes — the constant is the sole kill switch.
- Stage 3E infrastructure (`shouldUseNaturalSprintAutoRotate()`, `lastNaturalSprintAutoRotateActive`, Stage 3E block in `applyCharacterFacing()`) is retained as dead code for rollback and future use.

### Changes to `src/shared/Constants.lua`

- `SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = false` (was `true`). Updated comment explains the camera-jerk root cause.

### No animation ID changes, no speed changes, no camera changes

No animation IDs, speed multipliers, camera CFrame, CameraOffset, FieldOfView, HipHeight, JumpPower, or server-side systems were modified.

---

## [2026-05-25] — Stage 3F: Zero-gap landing exit (mirrors Stage 2S crouch-exit fix)

### Summary

Eliminates the brief T-pose / blank-pose flash that appeared between the end of a landing one-shot animation and the resumption of locomotion. Root cause: the `landingConn` Stopped callback in `playLandingAnimation()` cleared `isLandingPlaying` (releasing the Heartbeat gate) but did not immediately start the next locomotion animation. The next `updateMovementAnimation()` call on the following Heartbeat tick (~16ms later) would then start the correct animation, leaving at least one rendered frame with all track weights at zero — producing the visible neutral-pose flash. Fix: call `playMovementAnimation(getDesiredStandingLocomotionKey())` directly from the Stopped callback, mirroring the Stage 2S crouch-exit approach.

**What changed:**

- **One new constant** in `Constants.lua`: `LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true`. When `true`, the landing Stopped callback immediately crossfades to the correct locomotion animation. Set `false` to revert to the old Heartbeat-gap behaviour.
- **`getDesiredStandingLocomotionKey()` moved** from the Stage 2S section (~line 2759) to just before `playLandingAnimation()` (~line 2662) so the landing Stopped callback can call it without a forward-reference. All dependencies of the helper (`getAnimationSetName`, `isMouseLockedForStrafeAnimations`, `getRunForwardSuffix`, `getSprintAnimationName`) are already defined before the new position.
- **Stage 2S section header updated**: the duplicate `getDesiredStandingLocomotionKey` definition removed; header comment updated to reference Stage 3F placement.
- **`landingConn` Stopped callback extended**: after `clearLandingConnection()` and the optional early movement-lock release, the callback now calls `playMovementAnimation(getDesiredStandingLocomotionKey())` when `LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true` and `not isLandingPlaying` (guards against a second landing starting before the callback fires).
- **Studio MCP verified 2026-05-25**: 25-stud drop showed `LandingHeavy` (w=0.61) and `Idle` (w=0.78) overlapping in the same Heartbeat tick — no zero-weight gap frame. Full crossfade trace: `t=2.70 [LandingHeavy w=0.61] [Idle w=0.78]` → `t=2.88 [LandingHeavy w=0.00] [Idle w=1.00]` → `t=2.90 [Idle w=1.00]`.

### Changes to `src/shared/Constants.lua`

- `LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true` added after `SPRINT_JUMP_LANDING_MOMENTUM_MAX_FORCE` (Stage 3F section comment).

### Changes to `src/client/MovementController.lua`

- `getDesiredStandingLocomotionKey()` moved from Stage 2S section to just before `playLandingAnimation()` (placement comment updated).
- Duplicate `getDesiredStandingLocomotionKey()` removed from Stage 2S section; section header updated.
- `landingConn` Stopped callback in `playLandingAnimation()` extended with Stage 3F zero-gap crossfade block.

### No animation ID changes, no speed changes, no camera changes

No animation IDs, animation track loading, speed multipliers, camera CFrame, CameraOffset, FieldOfView, HipHeight, JumpPower, or server-side systems were modified.

---

## [2026-05-23] — Stage 3E: Natural AutoRotate sprint rotation (replaces Stage 3D directional CFrame snapping)

### Summary

Replaces the Stage 3D `faceCharacterTowardsDirection()` CFrame-snap path with a natural `Humanoid.AutoRotate = true` approach during sprint + custom mouse lock. Stage 3D rotated the character by writing `HumanoidRootPart.CFrame` toward a discrete `directionName`-bucketed direction on every Heartbeat, causing visible 45°/90° snaps each time the player crossed a direction boundary. Stage 3E instead sets `AutoRotate = true` during sprint, letting Roblox physics rotate the character smoothly toward movement direction without any CFrame writes from the controller. Walking, idle, crouching, tactical sprint, sprint-stop, and landing all continue on the existing camera-yaw CFrame path (`AutoRotate = false`).

**What changed:**

- **Three new constants** in `Constants.lua` (Stage 3E section after Stage 3D constants): `SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = true`, `SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED = true`, `SPRINT_NATURAL_AUTOROTATE_DEBUG = true`.
- **New helper** `shouldUseNaturalSprintAutoRotate()` in `MovementController.lua`: returns true when both kill-switch constants are on, custom mouse lock is active, player is sprinting, not in tactical sprint, not crouching, not in sprint-stop, and not landing-movement-locked.
- **`applyCharacterFacing()` Stage 3D block replaced with Stage 3E block:** When `shouldUseNaturalSprintAutoRotate()` is true, sets `humanoid.AutoRotate = true` and returns early (no CFrame write). An exit block (`if lastNaturalSprintAutoRotateActive`) runs on the first non-sprint frame to restore `AutoRotate = false` before the camera-yaw CFrame write.
- **New state variable** `lastNaturalSprintAutoRotateActive: boolean = false`: tracks whether Stage 3E is currently active; reset on respawn, mouse-lock disable, and `destroy()`.
- **Mouse-lock disable path updated:** `lastNaturalSprintAutoRotateActive = false` added to the `customMouseLocked = false` branch of `applyCustomMouseLock()` so the flag is clean on the next lock session.
- **Stage 3D helpers retained** (not deleted): `getCameraRelativeMoveDirection()`, `faceCharacterTowardsDirection()`, `lastSprintFacingMode`, and all six Stage 3D constants remain in the codebase as rollback infrastructure. They are dead code paths when both Stage 3E flags are true.
- **MCP unavailable — Studio verification not performed.** Needs manual playtest (see DEBT-044 Stage 3E risks).

### Changes to `src/shared/Constants.lua`

- New Stage 3E constant block added after Stage 3D constants (`SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA`):
  - `SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = true`
  - `SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED = true`
  - `SPRINT_NATURAL_AUTOROTATE_DEBUG = true`

### Changes to `src/client/MovementController.lua`

- New state variable `lastNaturalSprintAutoRotateActive: boolean = false` (after `lastSprintFacingMode`, line ~413).
- New private helper `shouldUseNaturalSprintAutoRotate(): boolean` (inserted in Stage 3E section before `applyCharacterFacing()`).
- `applyCharacterFacing()`: Stage 3D sprint block replaced with Stage 3E natural-AutoRotate block.
- `applyCustomMouseLock()` off-branch: `lastNaturalSprintAutoRotateActive = false` added.
- `loadMovementAnimations()`: `lastNaturalSprintAutoRotateActive = false` added to respawn reset block.
- `destroy()`: `lastNaturalSprintAutoRotateActive = false` added to teardown reset block.

### No animation ID changes, no speed changes, no camera changes

No animation IDs, animation track loading, speed multipliers, camera CFrame, CameraOffset, FieldOfView, HipHeight, JumpPower, or server-side systems were modified.

---

## [2026-05-23] — Vault animation IDs reserved in Constants (system deferred)

### Summary

`LowVault` and `MediumVault` animation IDs added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`. No loading code, no selection code, no controller changes. IDs are present in the data table only, clearly marked deferred. The vault system design (obstacle detection, input binding, state machine, movement lock, server interaction) is tracked in DEBT-052.

**What changed:**

- `Unarmed.LowVault = "rbxassetid://78932004147700"` added after `TacticalSprintStop` in the Unarmed table.
- `Unarmed.MediumVault = "rbxassetid://98948076922717"` added after `LowVault`.
- Both entries are commented as deferred and explicitly note that `loadMovementAnimations()` must not load them until the vault system is implemented.
- No Constants speed multiplier entries. No MovementController changes of any kind.

### Changes to `src/shared/Constants.lua`

Two entries added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed` (after `TacticalSprintStop`):
- `LowVault = "rbxassetid://78932004147700"` — deferred
- `MediumVault = "rbxassetid://98948076922717"` — deferred

### No runtime changes

`MovementController.lua` is not modified. The IDs are never passed to `LoadAnimation()` or `AnimationTrack:Play()`. No behavior change of any kind at runtime.

---

## [2026-05-23] — RunForwardTest toggle: audition R6 no-gun run-forward animation

### Summary

Adds a test run-forward animation for the Unarmed set alongside the existing `RunForward` clip. A single constant (`MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION`) switches between them. The existing confirmed clip is untouched. Toggle the constant, save, and `rojo serve` to audition; set back to `false` to restore.

**What changed:**

- **New animation ID** — `Unarmed.RunForwardTest = rbxassetid://118179559114284` added to `Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed`. Loaded alongside `Unarmed_RunForward` on every character spawn; never loaded for the AR15 set.
- **New toggle** — `MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION = false` (default: current `RunForward` clip plays). Set to `true` to play the test clip on all Unarmed sprint paths.
- **New helper** — `getRunForwardSuffix(animSetName)` returns `"RunForwardTest"` when the toggle is `true` + track is loaded + set is Unarmed; otherwise `"RunForward"`. All code paths that previously produced the `RunForward` suffix now route through this helper.
- **All sprint selection paths updated** — `getSprintAnimationName()` (all 6 return sites: no-mouse-lock path, ForwardLeft/ForwardRight/BackwardLeft/BackwardRight fallbacks, final catchall); `updateMovementAnimation()` tactical-sprint fallback; `getDesiredStandingLocomotionKey()` tactical-sprint fallback.
- **Speed multiplier** — `RunForwardTest` added to the `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER` (1.15×) branch in `getAnimationSpeedMultiplier()`. Identical speed to the current clip; tune separately if needed.
- **AR15 unaffected** — `getRunForwardSuffix()` returns `"RunForward"` unconditionally for any non-Unarmed set.

### Changes to `src/shared/Constants.lua`

- `MOVEMENT_ANIMATION_IDS.R6.Unarmed.RunForwardTest = "rbxassetid://118179559114284"` (after `RunForward`)
- `MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION = false` (after `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER`)

### Changes to `src/client/MovementController.lua`

- `getAnimationSpeedMultiplier()`: `"RunForwardTest"` added to the `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER` branch.
- `loadMovementAnimations()`: conditional load block for `Unarmed_RunForwardTest` (after `Unarmed_WalkForwardAlt` block).
- New private helper `getRunForwardSuffix(animSetName)` inserted before `getSprintAnimationName`.
- All 6 `return "RunForward"` sites in `getSprintAnimationName()` → `return getRunForwardSuffix(animSetName)`.
- `updateMovementAnimation()` tactical-sprint fallback → `setName .. "_" .. getRunForwardSuffix(setName)`.
- `getDesiredStandingLocomotionKey()` tactical-sprint fallback → `setName .. "_" .. getRunForwardSuffix(setName)`.

### Verification

MCP Studio verification was NOT performed — Studio instance "Project BR Dev" disconnected before the MCP execute step. Static check (`rojo build`) passed with no parse errors. Marked "needs Studio verification" in `docs/TECHNICAL_DEBT.md`.

**Manual test steps:**
1. Set `MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION = false`. Save + `rojo serve`.
2. Spawn R6, enter ACTIVE, sprint forward (LeftShift + W). Confirm original `RunForward` clip plays. Check Output — no errors.
3. Sprint in all 8 directions; confirm no regression (RunForwardLeft/Right when mouse-locked, RunForward fallback elsewhere).
4. Set `MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION = true`. Save + `rojo serve`.
5. Respawn (or rejoin). Sprint forward. Confirm the new `RunForwardTest` clip plays — it should look different from the original.
6. Sprint in all 8 directions. Confirm test clip plays for all Unarmed sprint paths.
7. Switch to AR15 set (`MovementController.SetEquippedWeaponName("AR15")`). Sprint forward. Confirm AR15 `RunForward` plays (test clip must NOT affect AR15).
8. Set `MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION = false`. Confirm original Unarmed clip restored.
9. Confirm `WalkSpeed`, `HipHeight`, `CameraOffset`, `FOV` unchanged throughout.

---

## [2026-05-23] — Movement Stage 3D: Sprint directional body-facing during custom mouse lock

### Summary

When custom mouse lock is active and the player is sprinting (non-tactical), the character body now rotates to face the camera-relative movement input direction instead of always facing camera yaw. Walking during mouse lock is unchanged (still faces camera yaw — Stage 2E behavior). Camera is never written; only `HumanoidRootPart.CFrame` yaw is modified. Crouch state is excluded (sprint facing is suppressed while crouching). Tactical sprint is excluded (always camera-forward by design).

**What changed:**

- **Sprint body-facing** (`SPRINT_DIRECTIONAL_BODY_FACING_ENABLED = true`, `SPRINT_FACE_MOVEMENT_DIRECTION_WHILE_MOUSE_LOCKED = true`): `applyCharacterFacing()` now checks whether the player is sprinting and not tactical-sprinting and not crouching before writing `HumanoidRootPart.CFrame`. If conditions met, reads `movementState.moveVector` (already camera-relative in Roblox — engine computes this), flattens to XZ, and calls `faceCharacterTowardsDirection()` instead of the camera-yaw write.
- **Walking unchanged**: when not sprinting, `applyCharacterFacing()` still writes camera yaw as before (Stage 2E unchanged).
- **BackwardLeft/BackwardRight sprint animations**: `getSprintAnimationName()` now maps `BackwardLeft` → `RunForwardLeft` and `BackwardRight` → `RunForwardRight` (when those tracks exist), with `RunForward` fallback and a one-time warn per missing key. This also applies to `getDesiredStandingLocomotionKey()` (which calls `getSprintAnimationName()` internally).
- **Debug logging**: `lastSprintFacingMode` tracks mode transitions so the debug log fires only when the mode changes (`"move_dir"` vs `"camera_yaw"`), not every frame.
- **Smoothing**: optional per-frame lerp (`SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = false` by default; alpha controlled by `SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 1`).
- **Cleanup**: `lastSprintFacingMode` reset in `loadMovementAnimations` and `destroy()`.

### New helpers (`src/client/MovementController.lua`)

- **`getCameraRelativeMoveDirection(): Vector3?`** — Reads `movementState.moveVector`, flattens to XZ, returns unit vector if magnitude ≥ `SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE`, else `nil`. No camera read needed — Roblox engine already computes `MoveDirection` in camera-relative space.
- **`faceCharacterTowardsDirection(direction: Vector3)`** — Sets `humanoid.AutoRotate = false` and writes `HumanoidRootPart.CFrame` yaw toward a given flat XZ direction. Optionally lerps via `SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED`. Guards against zero-magnitude input.

### Changes to `src/shared/Constants.lua`

Six new constants added (Stage 3D section, after Stage 2S block):
- `SPRINT_FACE_MOVEMENT_DIRECTION_WHILE_MOUSE_LOCKED = true`
- `SPRINT_DIRECTIONAL_BODY_FACING_ENABLED = true`
- `SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE = 0.1`
- `SPRINT_DIRECTIONAL_BODY_FACING_DEBUG = true`
- `SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = false`
- `SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 1`

All existing crouch, landing, sprint, camera, and weapon constants unchanged.

### Verification

MCP Studio verification was NOT performed — Studio instance "Project BR Dev" disconnected before the MCP execute step. Static checks (`rojo build`) passed with no parse errors. Marked as "needs Studio verification" in `docs/TECHNICAL_DEBT.md`.

**Manual test steps:**
1. Spawn as R6, enter ACTIVE phase, enable custom mouse lock (LeftControl or configured key).
2. Hold LeftShift and press W (forward sprint): character body should face camera-forward.
3. Hold LeftShift and press A (strafe-left sprint): character body should rotate to face camera-left while sprinting.
4. Hold LeftShift and press W+A (forward-left diagonal sprint): body faces forward-left; `RunForwardLeft` animation plays if loaded.
5. Hold LeftShift and press S+A (backward-left diagonal sprint): body faces backward-left; `RunForwardLeft` animation plays (reused) if loaded, else `RunForward` fallback.
6. Hold LeftShift and press S (backward sprint): body faces backward; `RunForward` animation plays (fallback).
7. Release LeftShift while still moving: body should revert to camera-yaw facing (walking mode).
8. Disable mouse lock: body facing should revert to default Roblox AutoRotate.
9. Hold C + LeftShift (sprint while crouching, if allowed): sprint body-facing should be suppressed; crouch animations unchanged.
10. Enable tactical sprint (if bound): body should face camera-forward, not movement input.
11. Respawn: confirm no stuck AutoRotate = false state, no duplicate tracks.

---

## [2026-05-23] — Movement Stage 2S: Zero-gap crouch-exit transitions

### Summary

Eliminates the brief default Roblox neutral/T-pose that appeared between crouch release and walk/run animation start. Root cause: `playCrouchTransition(false)` hard-stopped all crouch tracks and gated Heartbeat behind `crouchTransitionPlaying`, leaving ≥1 frame where every track had zero weight — causing the engine to flash the default standing pose before the next animation faded in.

**What changed:**

- **Moving on C-release** (`CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = false`, default): ExitCrouch is now skipped entirely. `resumeStandingLocomotionAfterCrouch(0.10s)` fades all crouch tracks out and the correct walk/run animation in with the **same** `fadeTime` — combined weight never reaches zero, so the default pose cannot appear.
- **Not moving on C-release**: ExitCrouch still plays. When it finishes, `resumeStandingLocomotionAfterCrouch` is called immediately inside the Stopped callback (`CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true`). Idle starts inside the callback, not on the following Heartbeat tick — the ≥1 frame blank-pose gap after ExitCrouch is also eliminated.
- **No ExitCrouch track**: falls directly to `resumeStandingLocomotionAfterCrouch`.
- **Legacy path preserved**: setting `CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = false` restores the original `playCrouchTransition(false)` behavior.
- `wasMovingWhileCrouching` and `CrouchWalkStart` are now explicitly reset in `crouchEndConn` (were previously only reset by Heartbeat on the next tick).

### New helpers (`src/client/MovementController.lua`)

- **`getDesiredStandingLocomotionKey(): string?`** — Pure read; mirrors `updateMovementAnimation`'s standing/sprint animation selection; returns the full track key (e.g. `"Unarmed_WalkForward"`) without modifying state.
- **`resumeStandingLocomotionAfterCrouch(fadeTime: number)`** — Fades all crouch tracks out with `fadeTime` and simultaneously starts the selected standing track in with the same `fadeTime`. Includes assert, `Logger.warn` on missing track, and same-track-already-playing guard.

### Changes to `src/shared/Constants.lua`

Five new constants added (Stage 2S section):
- `CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = true`
- `CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = false`
- `CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.10`
- `CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.12`
- `CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true`

All existing crouch, landing, sprint, camera, and weapon constants unchanged.

### Verification

MCP Studio verified 2026-05-23: module loaded with no Output errors in play mode; all 5 new constants live at runtime; all 13 source patterns (helper names, constant names, debug log strings, crossfade loop pattern) confirmed present in running module source. C key does not reach `InputBegan` via MCP — full visual crouch test requires manual Studio playtest.

**Manual test steps:**
1. Spawn as R6, enter ACTIVE.
2. Hold C (stand still) → release C: crouch exits cleanly into Idle with no default-pose frame.
3. Hold C, move forward, release C while holding W: blends directly into WalkForward — no neutral pose gap.
4. Hold C, move forward, hold LeftShift, release C: blends directly into RunForward/sprint animation.
5. With LeftControl mouse-lock ON: hold C, strafe left, release C while strafing: blends into WalkLeft/WalkForwardLeft.
6. Confirm crouch enter still blends directly into CrouchIdle/CrouchWalk (Stage 2Q-D unchanged).
7. Confirm respawn does not produce duplicate tracks or stuck state.
8. Confirm leaving ACTIVE clears crouch state safely.

---

## [2026-05-23] — Movement Stage 2Q-D: crouch direct-blend / EnterCrouch disable

### Summary

Visual fix for the crouch transition animation. The bundled `EnterCrouch` asset had bad intermediate frames (a visible forward-bend artifact on the first frame of the clip). Rather than replacing the asset, the animation is **disabled by default** and the system crossfades directly from the current standing pose into `CrouchIdle` or the appropriate `CrouchWalk*` direction.

**What changed:**

- **`EnterCrouch` disabled by default** (`CROUCH_USE_ENTER_TRANSITION_ANIMATION = false`). The asset still loads — flip the constant to `true` to restore the original one-shot if/when the asset is replaced.
- **Direct-blend on crouch press**: when not moving, crossfades into `CrouchIdle` over `CROUCH_DIRECT_BLEND_FADE_TIME = 0.12s`; when moving, crossfades into the correct directional `CrouchWalk*` over `CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.10s`. `stopCrouchTracksExcept(nil)` called before the new play to zero any residual weights.
- **`crouchTransitionPlaying` cleared immediately** in the direct-blend path, so Heartbeat takes over animation maintenance on the next frame (no gating delay).
- **`wasMovingWhileCrouching = true`** set in the direct-blend path when the player is moving, so the first Heartbeat skips `CrouchWalkStart` and goes straight to directional selection.
- **`CrouchWalkStart` gated off** (`CROUCH_USE_CROUCH_WALK_START_ANIMATION = false`). The forward-lunge artifact on the first crouched step is eliminated. The track still loads; set the constant to `true` to restore the one-shot.
- **ExitCrouch path is unchanged.** No HipHeight, CameraOffset, FOV, camera.CFrame, sprint, landing, or server-side changes. No new animation IDs. No new remotes.

### Changes to `src/shared/Constants.lua`

Four new constants added (after `CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK`):
- `CROUCH_USE_ENTER_TRANSITION_ANIMATION = false`
- `CROUCH_DIRECT_BLEND_FADE_TIME = 0.12`
- `CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.10`
- `CROUCH_USE_CROUCH_WALK_START_ANIMATION = false`

### Changes to `src/client/MovementController.lua`

- **`playCrouchTransition(entering: boolean)`**: direct-blend branch inserted before the existing `local track = animationTracks[key]` line. When `entering == true and not Constants.CROUCH_USE_ENTER_TRANSITION_ANIMATION`, the branch runs the direct crossfade and returns early. The original `EnterCrouch` / `ExitCrouch` path is unchanged and reached for `entering == false` or when the flag is `true`.
- **`updateMovementAnimation()` CrouchWalkStart block**: `if animationTracks[startKey] ~= nil and not crouchWalkStartPlaying then` gate replaced with `if Constants.CROUCH_USE_CROUCH_WALK_START_ANIMATION and animationTracks[startKey] ~= nil and not crouchWalkStartPlaying then`. When the flag is false, falls through immediately to directional selection.

### Documentation

- `docs/PROJECT_MAP.md`: Stage 2Q-D behavior block added after Stage 2Q+; four new constants documented in the Constants section.
- `docs/TECHNICAL_DEBT.md`: Stage 2Q-D risks and Studio verification requirement added to the MovementController animation debt entry.

### Verification

MCP unavailable — Studio verification was not performed. Needs manual playtest:
1. C press while standing → crossfades directly to `CrouchIdle` (no visible forward-bend).
2. C press while walking → crossfades directly to `CrouchWalk*` without CrouchWalkStart lunge.
3. C release → `ExitCrouch` plays cleanly from `CrouchIdle`/`CrouchWalk`.
4. No animation blending artifacts (no old crouch track bleeding through).
5. WalkSpeed, HipHeight, and CameraOffset are unaffected.

---

## [2026-05-22] — Movement Stage 3C fix: sprint stop movement lock + stopTacticalSprint refactor

### Summary

Two bug fixes for the tactical sprint stop system, continuing Stage 3C.

**Fix 1 — Sprint stop movement lock during direction-change stops.**
`stopTacticalSprint()` previously played the `TacticalSprintStop` animation via `playMovementAnimation()` but never set `isSprintStopPlaying = true`, so `applySpeed()` never locked `WalkSpeed` to 0. The player could freely move during the animation. **Fix:** `stopTacticalSprint()` is now a pure state-clear function. It stops `TacticalSprintForward` immediately and clears all tactical sprint flags, but plays **no animation**. Animation + lock + momentum carry happen **only** via `playSprintStopWithLock` on the Shift-release path (when tactical sprint duration ≥ `TACTICAL_SPRINT_STOP_MIN_DURATION`). Direction-change and crouch interruptions now cut instantly with no stop animation.

**Fix 2 — Stale comment update in `crouchBeginConn`.**
The comment still referred to `stopTacticalSprint()` playing `TacticalSprintStop`; updated to reflect the new pure state-clear behaviour.

### Changes to `src/client/MovementController.lua`

- **`stopTacticalSprint()`**: removed the `if Constants.TACTICAL_SPRINT_STOP_ANIMATION_ENABLED then ... playMovementAnimation(stopKey) ... tacticalSprintStopConn = stopTrack.Stopped:Connect(...)` block entirely. The function now only clears `isTacticalSprinting`, `movementState.isTacticalSprinting`, `tacticalSprintStartTime`, calls `clearTacticalSprintStopConnection()`, `stopCurrentMovementAnimation()`, and `updateSprintFov()`. Added a `MOVEMENT_ANIMATION_DEBUG` log confirming the instant cut path.
- **`crouchBeginConn`**: updated Stage 2P comment to reflect that `stopTacticalSprint()` is now a pure state-clear with no animation.

### Verification

- Sprint stop lock: MCP Studio — `MOVEMENT_ANIMATION_DEBUG` output confirmed; WalkSpeed = 0 during `TacticalSprintStop` requires manual test (needs >5 s tactical sprint, then Shift release).
- Direction-change instant stop (Heartbeat path): verified `tacticalSprintStopConn` is never set by `stopTacticalSprint()` — no animation plays on direction change.
- Crouch cancel of tactical sprint: verified `stopTacticalSprint()` now produces no animation; EnterCrouch plays cleanly from `playCrouchTransition(true)`.
- **Crouch bug**: MCP cannot simulate C key in Studio play mode — requires manual visual verification by the user.

---

## [2026-05-22] — Movement Stage 3C: Tactical sprint stop polish (lock + momentum carry; regular sprint unaffected)

### Summary

Polish pass on **tactical sprint stop** (double-tap Shift sprint) only. Regular single-Shift sprint now exits cleanly with no animation. The `TacticalSprintStop` animation (`Unarmed_TacticalSprintStop`, pre-existing) continues to play when tactical sprint ends; the supporting infrastructure (lock, momentum carry, helpers) is built and available but not yet wired into the tactical-sprint stop path — that is deferred.

**What changed:**

- **Regular sprint end is clean**: releasing Shift after a normal single-Shift sprint clears `isSprinting`, calls `applySpeed()`, and restores FOV — no animation, no lock, no momentum.
- **Tactical sprint end unchanged**: `stopTacticalSprint()` still plays `TacticalSprintStop` as before (Stage 2P behavior preserved).
- **Infrastructure built for future wiring**: `shouldPlaySprintStop`, `clearSprintStopMomentum`, `clearSprintStopLock`, `startSprintStopMomentum`, `playSprintStopWithLock`, and all 9 Stage 3C constants are present and correct. When the tactical sprint stop is polished (lock + momentum carry), `stopTacticalSprint()` can delegate to `playSprintStopWithLock` without needing new helpers or constants.

### Changes to `src/shared/Constants.lua`

Nine new sprint-stop constants added (Stage 3C section, available for future tactical-stop wiring):
`SPRINT_STOP_ENABLED`, `SPRINT_STOP_MIN_SPRINT_DURATION` (0.75), `SPRINT_STOP_LOCKS_MOVEMENT`, `SPRINT_STOP_LOCK_FALLBACK_DURATION` (0.38), `SPRINT_STOP_MOMENTUM_ENABLED`, `SPRINT_STOP_MOMENTUM_DURATION` (0.24), `SPRINT_STOP_MOMENTUM_SPEED` (16), `SPRINT_STOP_MOMENTUM_MAX_FORCE` (60000), `SPRINT_STOP_MIN_HORIZONTAL_SPEED` (8).

### Changes to `src/client/MovementController.lua`

- **Header**: stage tag updated to `3A + 3B + 3C`.
- **State variables** (after `tacticalSprintStopConn`): `sprintStartTime`, `lastSprintMomentumDirection`, `isSprintStopPlaying`, `sprintStopLockToken`, `sprintStopMomentumAttachment`, `sprintStopMomentumVelocity`.
- **`applySpeed()`**: sprint-stop lock block added (used when `playSprintStopWithLock` is active).
- **Helpers** (after `startSprintJumpLandingMomentum`): `shouldPlaySprintStop`, `clearSprintStopMomentum`, `clearSprintStopLock`, `startSprintStopMomentum`.
- **`playSprintStopWithLock(direction?)`** (after `stopTacticalSprint`): locks WalkSpeed to 0, applies momentum carry, plays `TacticalSprintStop`, registers Stopped callback + fallback timer. Not currently called from regular sprint path.
- **`updateMovementAnimation()`**: `if isSprintStopPlaying then return end` gate added.
- **Sprint `InputBegan`**: `sprintStartTime = os.clock()` added; `clearSprintStopLock()` called if SprintStop was in-flight.
- **Sprint `InputEnded`**: tactical sprint → `stopTacticalSprint()`; regular sprint → simple clean exit (no animation). `shouldPlaySprintStop` is NOT called here.
- **Crouch `InputBegan`**: `clearSprintStopLock()` + `sprintStartTime = nil` added.
- **Heartbeat**: `lastSprintMomentumDirection` tracking added for future momentum carry accuracy.
- **Phase exit, `loadMovementAnimations()`, `destroy()`**: cleanup of all Stage 3C state.
- **Ready log**: updated to `Stage 1–3C`.

### No-change scope

No new remotes. No server changes. No new animation IDs. No camera writes. No `GunController`, `ViewModelController`, or `SoundController` changes. No UI changes. No slide system.

### Verification status

MCP/Studio verified 2026-05-22: 26/26 checks passed (9 Constants + 17 MovementController source patterns confirmed live in running Studio module). Manual Studio playtest required for full behavioral confirmation — MCP keyboard input does not reach `InputBegan` in Studio play mode.

---

## [2026-05-22] — Movement Stage 2Q+: Crouch blend contamination follow-up fix

### Summary

Follow-up to Stage 2Q that resolves the remaining "old crouch pose briefly visible" contamination that Stage 2Q did not fully eliminate.

**Three root causes fixed:**

1. **Wrong pattern in `stopCrouchTracksExcept`** — the helper used `key:find("_Crouch")`, which matches `Unarmed_CrouchIdle`, `Unarmed_CrouchWalk*`, etc., but silently skips `Unarmed_EnterCrouch` and `Unarmed_ExitCrouch` (whose keys end with `Crouch` after the verb prefix, with no `_Crouch` substring). Transitioning away from EnterCrouch/ExitCrouch left those tracks still fading and blending through the new animation. Fixed by changing the pattern to `key:find("Crouch")` — catches all crouch-related tracks; no false positives on non-crouch animations.

2. **`if track.IsPlaying` guard in `stopCrouchTracksExcept`** — the guard skipped tracks whose weight was still decaying after a prior `Stop(fadeTime)` call (`IsPlaying` is `false` immediately after `Stop` even while the weight fades). Changed to unconditionally call `Stop(0)` on every matching track, immediately zeroing any residual weight.

3. **Missing `stopCrouchTracksExcept(key)` call in `playCrouchTransition`** — when starting EnterCrouch or ExitCrouch, no prior call cleared the other crouch tracks. Any fading CrouchIdle, CrouchWalk, or previous transition track continued blending through the new transition's fade-in window (most visible during rapid C-release → C-press cycles). Added `stopCrouchTracksExcept(key)` immediately before `track:Play(...)`.

### Additional hardening

- Added `stopCrouchTracksExcept(fwdKey)` / `stopCrouchTracksExcept(aliasKey)` before `playMovementAnimation` in the **EnterCrouch Stopped callback moving branch** (was previously missing; only the not-moving branch had this call from Stage 2Q).
- Added `stopCrouchTracksExcept(nil)` in the **phase exit handler** after `stopCurrentMovementAnimation()` — ensures no fading crouch weight persists across phase transitions when `currentAnimationName` no longer tracks the fading track.

### Changes to `src/client/MovementController.lua`

- **`stopCrouchTracksExcept`**: pattern `"_Crouch"` → `"Crouch"`; removed `if track.IsPlaying` guard; `Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)` → `Stop(0)`. `currentAnimationName` clear-guard also updated to use `find("Crouch")`.
- **`playCrouchTransition`**: added `stopCrouchTracksExcept(key)` before `crouchTransitionPlaying = true` and `track:Play(...)`.
- **EnterCrouch Stopped callback (moving branch)**: added `stopCrouchTracksExcept(fwdKey)` before `playMovementAnimation(fwdKey)`; added `stopCrouchTracksExcept(aliasKey)` before `playMovementAnimation(aliasKey)`.
- **Phase exit handler**: added `stopCrouchTracksExcept(nil)` after `stopCurrentMovementAnimation()`.
- Header comment and stage tag updated to `2Q+`.

### No-change scope

No new remotes. No server changes. No animation IDs changed. No speed constants changed. No camera writes. No `CameraOffset`, `FieldOfView`, or `CameraType` changes. No `GunController`, `ViewModelController`, or `SoundController` changes. No UI changes.

### MCP Studio verification (2026-05-22)

- All 7 pattern checks passed in running module (new pattern, absent old pattern, `Stop(0)`, all 4 new call sites).
- Pattern smoke test: `Unarmed_EnterCrouch`, `Unarmed_ExitCrouch`, `AR15_EnterCrouch`, `AR15_ExitCrouch` — all newly matched ✅; 6 non-crouch keys correctly skipped ✅.
- Module loaded cleanly — no errors or unexpected warns in Output panel.
- 8 total `stopCrouchTracksExcept` call sites confirmed (4 existing from Stage 2Q + 4 new from Stage 2Q+).
- Known limitation: C key input via `user_keyboard_input` does not reach `InputBegan` in Studio play mode — full end-to-end crouch transition visual requires manual Studio playtest (same limitation as Stages 2P/2Q/2R/3A/3B).

---

## [2026-05-21] — Movement Stage 3B: Landing movement lock + sprint-jump momentum carry

### Summary

Landing movement lock and optional sprint-jump momentum carry added to `MovementController`.

- **LandingLight** — no change to movement; player retains full input control.
- **LandingMedium** — `WalkSpeed` set to 0 while the animation plays. If the player landed from a sprint jump, a `LinearVelocity` carries horizontal momentum for `SPRINT_JUMP_LANDING_MOMENTUM_DURATION` (0.22 s) while input is locked; the lock matches the momentum window. For non-sprint-jump medium landings the lock uses `LANDING_MEDIUM_LOCK_FALLBACK_DURATION` (0.35 s). Lock is released early if the animation's `Stopped` event fires first (and momentum is not still active).
- **LandingHeavy** — `WalkSpeed` set to 0 for `LANDING_HEAVY_LOCK_FALLBACK_DURATION` (0.65 s) or until animation finishes, whichever is shorter.

**Token-based stale-unlock prevention:** `landingLockToken` is incremented on every lock clear. Each `task.delay` closure captures the token at dispatch time and no-ops if the token has since changed (prevents stale unlocks after respawn, phase-exit, or rapid re-landing).

**Sprint-jump momentum carry:** `LinearVelocity` + `Attachment` parented to `HumanoidRootPart`; horizontal direction captured at the `Jumping` state entry (not `Freefall`). Destroyed after `SPRINT_JUMP_LANDING_MOMENTUM_DURATION`. Not a slide system — no player slide state, no slide input, no slide animation.

**Phase-exit / respawn cleanup:** `clearLandingMovementLock()` called in the phase-exit handler, `loadMovementAnimations()`, and `destroy()` to guarantee `WalkSpeed` is never left at 0 after the active game phase ends.

**Studio verification (MCP):** LandingLight at 6 studs — min WalkSpeed 14.0 (no lock). LandingMedium at 14 studs — locked for ~0.37 s. LandingHeavy at 22 studs — locked for exactly 0.65 s. No `LinearVelocity` present on non-sprint-jump landings (correct — sprint-jump path requires client-side `jumpedWhileSprinting` flag).

### New constants (`src/shared/Constants.lua`)

- `LANDING_MOVEMENT_LOCK_ENABLED = true` — master switch; when false no lock is ever applied
- `LANDING_MEDIUM_LOCKS_MOVEMENT = true` — enables lock for LandingMedium tier
- `LANDING_HEAVY_LOCKS_MOVEMENT = true` — enables lock for LandingHeavy tier
- `LANDING_LIGHT_LOCKS_MOVEMENT = false` — always false; LandingLight never locks
- `LANDING_MEDIUM_LOCK_FALLBACK_DURATION = 0.35` — non-sprint-jump medium lock duration (seconds)
- `LANDING_HEAVY_LOCK_FALLBACK_DURATION = 0.65` — heavy lock duration (seconds)
- `SPRINT_JUMP_LANDING_MOMENTUM_ENABLED = true` — master switch for LinearVelocity carry
- `SPRINT_JUMP_LANDING_MOMENTUM_DURATION = 0.22` — seconds of momentum carry (also the lock duration for sprint-jump medium landings)
- `SPRINT_JUMP_LANDING_MOMENTUM_SPEED = 18` — horizontal carry speed in studs/s
- `SPRINT_JUMP_LANDING_MOMENTUM_MAX_FORCE = 60000` — LinearVelocity MaxForce (Magnitude mode)

### New helpers (`src/client/MovementController.lua`)

Inserted after `stopCrouchTracksExcept` (~line 945) and **before** `loadMovementAnimations` (~line 1766) to satisfy Luau `--!strict` forward-reference rules:

- **`getFlatVector(vector)`** — flattens Y, returns unit or nil if magnitude ≤ 0.01
- **`captureJumpMomentumDirection()`** — captures sprint takeoff direction at `Jumping` state entry; priority: `AssemblyLinearVelocity` → `MoveDirection` → `CFrame.LookVector`
- **`clearLandingMomentum()`** — destroys `LinearVelocity` and `Attachment` on `HumanoidRootPart`; sets `landingMomentumActive = false`
- **`clearLandingMovementLock()`** — increments token, sets `isLandingMovementLocked = false`, calls `clearLandingMomentum()`, calls `applySpeed()`
- **`startLandingMovementLock(duration)`** — sets lock, suppresses sprint flags, calls `applySpeed()` (→ `WalkSpeed = 0`), schedules token-guarded `task.delay` fallback
- **`startSprintJumpLandingMomentum(direction)`** — creates `Attachment` + `LinearVelocity` on `HumanoidRootPart`, sets velocity, schedules `task.delay` cleanup

### New module-level state

- `isLandingMovementLocked: boolean` — when true, `applySpeed()` immediately sets `WalkSpeed = 0` and returns
- `landingLockToken: number` — invalidation token; incremented on every lock clear
- `landingMomentumActive: boolean` — true while `LinearVelocity` carry is running
- `landingMomentumAttachment: Attachment?` — reference for cleanup
- `landingMomentumVelocity: LinearVelocity?` — reference for cleanup
- `sprintJumpMomentumDirection: Vector3?` — captured at jump entry; consumed and cleared at landing

---

## [2026-05-21] — Movement Stage 3A: Sprint FOV stretch + landing animation classification

### Summary

Two independent polish systems added to `MovementController`:

1. **Sprint FOV stretch** — `TweenService` smoothly adjusts `workspace.CurrentCamera.FieldOfView` while sprinting (normal sprint → 78, tactical sprint → 84, restore to 70 on sprint end / phase-exit / respawn / destroy). No speed changes. Never writes `camera.CFrame`. Controlled by `Constants.SPRINT_FOV_ENABLED` master switch.

2. **Landing animation classification** — Three tiers replace Stage 2O's single `LandingMedium`. `LandingLight` for normal jumps and small drops; `LandingMedium` for sprint jumps and medium drops; `LandingHeavy` for high drops (≥ 18 studs regardless of jump context). Pure-drop landings require ≥ 0.25 s of air time to classify. Jumping state is tracked so jump-vs-drop context is always known.

### New constants (`src/shared/Constants.lua`)

Sprint FOV block:
- `SPRINT_FOV_ENABLED = true` — master switch; when false MovementController never touches FieldOfView
- `DEFAULT_CAMERA_FOV = 70` — baseline; restored on sprint end / phase-exit / respawn / destroy
- `SPRINT_CAMERA_FOV = 78` — target while normal sprint active and moving
- `TACTICAL_SPRINT_CAMERA_FOV = 84` — target while tactical sprint active
- `SPRINT_FOV_TWEEN_TIME = 0.18` — seconds to tween to sprint/tactical-sprint target
- `SPRINT_FOV_RESTORE_TIME = 0.22` — seconds to tween back to default

Landing classification block:
- `MOVEMENT_LANDING_LIGHT_MAX_DROP = 8` — max drop distance (studs) for LandingLight (pure drops)
- `MOVEMENT_LANDING_MEDIUM_MAX_DROP = 18` — max drop distance (studs) for LandingMedium (pure drops)
- `MOVEMENT_LANDING_HEAVY_MIN_DROP = 18` — at or above this, LandingHeavy plays regardless of jump context
- `MOVEMENT_LANDING_JUMP_LIGHT_MAX_AIR_TIME = 0.85` — reserved; currently unused by classifier
- `MOVEMENT_LANDING_SPRINT_JUMP_USES_MEDIUM = true` — sprint jumps resolve to LandingMedium instead of LandingLight
- `MOVEMENT_LANDING_ANIMATION_FADE_TIME = 0.08` — fade-in time for landing animations (shorter than the standard 0.15)
- `MOVEMENT_LANDING_LIGHT_SPEED_MULTIPLIER = 1.15` — LandingLight playback speed
- `MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER = 1.0` — LandingMedium playback speed
- `MOVEMENT_LANDING_HEAVY_SPEED_MULTIPLIER = 0.9` — LandingHeavy playback speed
- `MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME = 0.25` — pure drops shorter than this play no landing animation

Updated animation IDs (`MOVEMENT_ANIMATION_IDS.R6.Unarmed`):
- `LandingLight = "rbxassetid://135438895968665"` — new; one-shot light landing
- `LandingMedium = "rbxassetid://135915211175953"` — unchanged from Stage 2O; reclassified use
- `LandingHeavy = "rbxassetid://72796290236543"` — new; one-shot heavy landing

### New helpers (`src/client/MovementController.lua`)

**Sprint FOV section** (inserted before Stage 2P tactical sprint section to avoid Luau forward-reference):
- **`tweenCameraFov(target, duration)`** — cancels any in-progress FOV tween and starts a new one. Never touches `camera.CFrame`. No-op when `SPRINT_FOV_ENABLED ~= true` or camera is nil.
- **`updateSprintFov()`** — determines the correct target FOV from phase + sprint state, then calls `tweenCameraFov` only if target differs from `targetFov` (dedup guard prevents per-frame tween restarts).

**Landing section** (inserted before `updateMovementAnimation`):
- **`getLandingAnimationName(dropDistance, airTime, wasJump, sprintJump): string?`** — classifies landing tier. Heavy always wins; then jump context (sprint jump → Medium, normal jump → Light); then pure-drop thresholds. Returns `nil` for drops shorter than `MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME`.
- **`playLandingAnimation(animationName)`** — plays landing animation using `MOVEMENT_LANDING_ANIMATION_FADE_TIME` (0.08) instead of the standard fade time. Sets `isLandingPlaying = true` and `currentAnimationName`. Falls back to Unarmed set for AR15.

### New module-level state

- `currentFovTween: Tween?` — reference to the active FOV tween; cancelled before starting a new one
- `targetFov: number` — last-requested FOV target; dedup guard in `updateSprintFov()`
- `airborneStartY: number?` — HumanoidRootPart Y captured on Jumping state; used to compute drop distance
- `wasJumpingThisAirborne: boolean` — true if the current airborne phase started with a jump (not a walk-off)
- `jumpedWhileSprinting: boolean` — true if the jump that started the current airborne phase happened while sprinting

### Files changed

- **`src/shared/Constants.lua`** — Sprint FOV block + landing classification block added; animation IDs updated; `MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER` comment updated.
- **`src/client/MovementController.lua`** — TweenService required; new state variables; `getAnimationSpeedMultiplier` updated for three tiers; `loadMovementAnimations` loads LandingLight + LandingHeavy (Looped=false) and resets new state on respawn; FOV helpers inserted before Stage 2P section; landing helpers inserted before `updateMovementAnimation`; `stopTacticalSprint` calls `updateSprintFov()`; `onHumanoidStateChanged` rewritten to track Jumping, update `airborneStartY`/`wasJumpingThisAirborne`/`jumpedWhileSprinting`, and call `getLandingAnimationName` + `playLandingAnimation` on Landed; `destroy()` cancels FOV tween and resets new state; `Start()` resets `targetFov` on CharacterAdded; phase-exit handler restores FOV; sprint/crouch/Heartbeat handlers call `updateSprintFov()`; ready log updated to Stage 1–3A.

### No-change scope

No new remotes. No server changes. No speed changes. No fall damage. No stamina. No slide/vault/prone. No `camera.CFrame` writes. No `CameraType` changes. No `CameraOffset` changes. No third-person zoom changes. No `ViewModelController` changes. No `GunController` changes. No `SoundController` changes. No UI changes.

### MCP verification (2026-05-21)

- Constants block: all 10 FOV + landing constants confirmed live in Studio (`SPRINT_FOV_ENABLED=true`, `DEFAULT_CAMERA_FOV=70`, `SPRINT_CAMERA_FOV=78`, `TACTICAL_SPRINT_CAMERA_FOV=84`, `TWEEN=0.18s`, `RESTORE=0.22s`, all landing thresholds correct).
- Camera FOV at play start: 70.0 ✓
- Manual tween smoke test: 70 → 78 → 70 round-trip via TweenService confirmed ✓
- Landing classifier inline test — all 7 cases correct:
  - Normal jump (no sprint) → LandingLight ✓
  - Sprint jump → LandingMedium ✓
  - High jump (drop ≥ 18 studs) → LandingHeavy ✓
  - Small pure drop (≤ 8 studs, air ≥ 0.25 s) → LandingLight ✓
  - Medium pure drop (8–18 studs) → LandingMedium ✓
  - Heavy pure drop (≥ 18 studs) → LandingHeavy ✓
  - Tiny drop (air < 0.25 s) → nil (no animation) ✓
- No runtime errors or unexpected warnings in Output panel.
- **Known limitation:** full end-to-end FOV tween during live sprint + landing animations during actual jumps/drops require manual Studio playtest — MCP `user_keyboard_input` does not reach `InputBegan` handlers (gameProcessed gate).

---

## [2026-05-21] — Movement Stage 2R: Directional sprint animation selection with custom mouse lock

### Summary

Re-enables directional sprint animation selection that was deferred in Stage 2L. When `customMouseLocked == true` (LeftControl), sprinting in the `ForwardLeft` direction plays `RunForwardLeft` if the track is loaded; sprinting in the `ForwardRight` direction plays `RunForwardRight` if the track is loaded. All other sprint directions (Left, Right, Backward, BackwardLeft, BackwardRight, Forward) and all directions when `customMouseLocked == false` continue to use `RunForward`. No camera writes. No new animation IDs. No Constants changes.

### New helper

- **`getSprintAnimationName(animSetName: string, directionName: string): string`** — resolves which sprint animation suffix to use. With `customMouseLocked == false`, always returns `"RunForward"`. With `customMouseLocked == true`: `ForwardLeft` → `"RunForwardLeft"` if `animationTracks[animSetName .. "_RunForwardLeft"] ~= nil`, else `"RunForward"` (warn once via `missedSprintAnimWarned`); `ForwardRight` → `"RunForwardRight"` if loaded, else `"RunForward"` (warn once); all other directions → `"RunForward"`. Caller composes `setName .. "_" .. suffix`.

### New module-level state

- **`missedSprintAnimWarned: {[string]: boolean}`** — per-track-key warn-once table. Each missing directional sprint track (`animSetName_RunForwardLeft`, `animSetName_RunForwardRight`) fires `Logger.warn()` exactly once per session. Not reset on respawn — warns once per module lifetime.
- **`lastSprintAnimName: string`** — debug deduplication guard. `Logger.debug` fires only when the resolved sprint animation key changes (not every frame). Reset to `""` on each character load and in `destroy()`.

### Files changed

- **`src/client/MovementController.lua`** (Stage 2R):
  - Header comment updated: stage list `2P + 2Q` → `2P + 2Q + 2R`; sprint behavior summary updated.
  - Behavior summary block updated: "Sprint in any direction always uses RunForward" replaced with four-line description of directional sprint fallback behavior.
  - Module-level `lastSprintAnimName: string = ""` added (after `lastStrafeBlockedState`).
  - `loadMovementAnimations()` reset block: `lastSprintAnimName = ""` added.
  - `destroy()` reset block: `lastSprintAnimName = ""` added.
  - `missedSprintAnimWarned` table and `getSprintAnimationName()` function inserted before `updateMovementAnimation()`.
  - `updateMovementAnimation()` normal sprint block replaced: single `animName = setName .. "_RunForward"` line replaced with `animName = setName .. "_" .. getSprintAnimationName(setName, movementState.directionName)` plus debug log guard.
  - Ready log updated: `Stage 1–2Q` → `Stage 1–2R`; sprint description updated.

### No-change scope

No new animation IDs. No Constants changes. No camera writes (no `camera.CFrame`, `CameraOffset`, `FieldOfView`, `CameraType`). No speed multiplier changes. No movement speed changes. No new remotes. No server changes. No GunController/ViewModelController/SoundController changes. Tactical sprint branch unchanged (still uses `TacticalSprintForward1` / `RunForward` fallback). AR15 sprint unchanged (still always `AR15_RunForward`).

### MCP verification (2026-05-21)

- Studio play mode entered; module loaded cleanly (`type=table`).
- MatchController patched to ACTIVE for phase-gate passthrough.
- Source-level checks via `mcScript.Source` (all using plain-text search `find(str, 1, true)`):
  - `getSprintAnimationName` function definition confirmed ✓
  - `missedSprintAnimWarned` table declaration confirmed ✓
  - `ForwardLeft` branch with `RunForwardLeft` key confirmed ✓
  - `ForwardRight` branch with `RunForwardRight` key confirmed ✓
  - `lastSprintAnimName` declaration confirmed ✓
  - `lastSprintAnimName = ""` in `loadMovementAnimations` confirmed ✓
  - `lastSprintAnimName = ""` in `destroy()` confirmed ✓
  - Debug log `sprint animation →` confirmed ✓
  - Old single-line `animName = setName .. "_RunForward"` absent in sprint block ✓
  - `customMouseLocked` toggle (`SetCustomMouseLocked(true)`/`(false)`) state changes confirmed via live module call ✓
- **Source length verified:** disk file 149,222 bytes; Studio synced correctly after rojo stale-intermediate issue resolved via `mcp__Roblox_Studio__multi_edit`.
- **Known limitation:** W and C key inputs via MCP `user_keyboard_input` do not reach `InputBegan` handlers in Studio play mode (gameProcessed gate). Full end-to-end sprint animation flow requires manual Studio playtest — same limitation as Stages 2P and 2Q.

---

## [2026-05-21] — Movement Stage 2Q: Fix crouch animation contamination

### Summary

Eliminated two visual artifacts that appeared when pressing C to crouch:

1. **Frame-0 flash (primary)** — `playCrouchTransition()` Stopped callback called `holdCrouchBottomPose()` unconditionally when not moving. That function calls `track:Play(0)` which restarts EnterCrouch from frame 0 before seeking to near-end and freezing, producing a one-frame flash of the old crouch animation. **Fix:** Stopped callback now checks for `CrouchIdle` first; if present, calls `stopCrouchTracksExcept(crouchIdleKey2)` + `playMovementAnimation(crouchIdleKey2)` directly, skipping the hold-pose step entirely. `holdCrouchBottomPose()` is only called when no `CrouchIdle` track exists.

2. **Resume flash (secondary)** — `clearCrouchBottomHold()` called `track:AdjustSpeed(SPEED_MULTIPLIER)` before `track:Stop(fade)`. This caused the AdjustSpeed(0)-frozen EnterCrouch to briefly resume playing from its frozen position during the fade-out, producing a visible replay of the stale animation. **Fix:** `clearCrouchBottomHold()` now calls `track:Stop()` directly without restoring speed first. The track fades out silently from the frozen frame.

### New helper

- **`stopCrouchTracksExcept(allowedKey: string?)`** — iterates `animationTracks`, stops every `_Crouch`-keyed track except `allowedKey`, and clears `currentAnimationName` if it was one of the stopped tracks. Called at all three crouch animation transition points to prevent any stale crouch blend from bleeding through.

### Files changed

- **`src/client/MovementController.lua`** (Stage 2Q):
  - Header comment updated to include Stage 2Q.
  - Added `stopCrouchTracksExcept(allowedKey: string?)` after `clearTacticalSprintStopConnection()`.
  - `clearCrouchBottomHold()`: removed `track:AdjustSpeed(SPEED_MULTIPLIER)` before `track:Stop()`.
  - `playCrouchTransition()` EnterCrouch Stopped callback, not-moving branch: added CrouchIdle preference path over `holdCrouchBottomPose()`.
  - `updateMovementAnimation()` crouching-not-moving branch: added `stopCrouchTracksExcept(crouchIdleKey)` before `playMovementAnimation(crouchIdleKey)`.
  - `updateMovementAnimation()` CrouchWalkStart path: added `stopCrouchTracksExcept(startKey)` before `playMovementAnimation(startKey)`.
  - `updateMovementAnimation()` CrouchWalk target path: added `stopCrouchTracksExcept(targetCrouchKey)` before `playMovementAnimation(targetCrouchKey)`.

### No-change scope

No new animation IDs. No Constants changes. No speed multiplier changes. No camera writes. No new remotes. No server changes. No GunController/ViewModelController/SoundController changes.

### MCP verification (2026-05-21)

- Studio play mode entered; module loaded cleanly (`type=table`).
- MatchController patched to ACTIVE for phase-gate passthrough.
- Source-level checks via `mcScript.Source`:
  - `track:AdjustSpeed` absent from `clearCrouchBottomHold` body ✓
  - `animationTracks[crouchIdleKey2]` guard present in Stopped callback ✓
  - `stopCrouchTracksExcept` function definition confirmed ✓
  - All 4 call-sites confirmed (`crouchIdleKey2`, `crouchIdleKey`, `startKey`, `targetCrouchKey`) ✓
- **Known limitation:** C key input via MCP `user_keyboard_input` does not reach `InputBegan` handler in Studio play mode (gameProcessed gate blocks it). Full end-to-end animation flow requires manual Studio playtest. This is the same limitation documented for Stage 2P (W-key not sustaining).

---

## [2026-05-21] — Movement Stage 2P: Tactical sprint foundation (double-tap LeftShift)

### Summary
Adds a tactical sprint mode triggered by double-tapping LeftShift while moving forward in the ACTIVE
phase. Tactical sprint ramps `Humanoid.WalkSpeed` from `SPRINT_SPEED` (22) to `TACTICAL_SPRINT_SPEED`
(30) over `TACTICAL_SPRINT_ACCELERATION_TIME` (1.0 s). A looped `TacticalSprintForward1` animation
plays while active (forward direction only; no variation alternation yet). A one-shot `TacticalSprintStop`
clip fires when tactical sprint ends (configurable). Firing and reloading are blocked while tactical
sprint is active when `TACTICAL_SPRINT_BLOCKS_GUN_USE = true`. All existing walk, sprint, crouch,
idle, falling, and landing behavior is preserved unchanged.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added `Unarmed.TacticalSprintForward1 = "rbxassetid://135119369971434"` — looped forward clip (Stage 2P)
  - Added `Unarmed.TacticalSprintForward2 = "rbxassetid://110008857265859"` — alternate clip; loaded, not yet selected (Stage 2P)
  - Added `Unarmed.TacticalSprintStop = "rbxassetid://81946205769343"` — one-shot stop clip (Stage 2P)
  - Added `Constants.TACTICAL_SPRINT_ENABLED = true`
  - Added `Constants.TACTICAL_SPRINT_DOUBLE_TAP_WINDOW = 0.3` — seconds between two LeftShift presses to trigger
  - Added `Constants.TACTICAL_SPRINT_SPEED = 30` — top speed when tactical sprint is fully ramped
  - Added `Constants.TACTICAL_SPRINT_ACCELERATION_TIME = 1.0` — seconds to ramp from SPRINT_SPEED to TACTICAL_SPRINT_SPEED
  - Added `Constants.TACTICAL_SPRINT_MIN_FORWARD_DOT = 0.35` — minimum MoveDirection·camera-forward dot product to start/sustain
  - Added `Constants.TACTICAL_SPRINT_BLOCKS_GUN_USE = true` — blocks WeaponFired and ReloadRequest while active
  - Added `Constants.TACTICAL_SPRINT_STOP_ANIMATION_ENABLED = true` — plays TacticalSprintStop one-shot on end

- **`src/client/MovementController.lua`**:
  - New `movementState.isTacticalSprinting` boolean (mirrors private `isTacticalSprinting`; read by external systems).
  - New private state: `isTacticalSprinting`, `tacticalSprintStartTime`, `lastShiftPressTime`, `tacticalSprintStopConn`.
  - New helper `clearTacticalSprintStopConnection()`: disconnects `tacticalSprintStopConn`; placed after `clearLandingConnection()`.
  - New function `stopTacticalSprint()`: clears `isTacticalSprinting`, plays `TacticalSprintStop` one-shot (if enabled and loaded), connects `Stopped` callback via `tacticalSprintStopConn`. Defined AFTER `playMovementAnimation()` to avoid Lua scoping issues.
  - `applySpeed()`: tactical sprint ramp inserted as first check (before isCrouching): `WalkSpeed = SPRINT_SPEED + (TACTICAL_SPRINT_SPEED - SPRINT_SPEED) * t` where `t = clamp(elapsed/ACCELERATION_TIME, 0, 1)`.
  - `getAnimationSpeedMultiplier()`: `TacticalSprintForward1` and `TacticalSprintForward2` → `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER`; `TacticalSprintStop` → 1.0.
  - `loadMovementAnimations()`: resets all tactical sprint state on respawn; conditionally loads `Unarmed_TacticalSprintForward1`, `Unarmed_TacticalSprintForward2`, `Unarmed_TacticalSprintStop`; `_TacticalSprintStop$` added to `Looped = false` pattern.
  - `updateMovementAnimation()`: `if tacticalSprintStopConn ~= nil then return end` gate added (prevents Heartbeat overriding the stop one-shot, mirrors `landingConn` pattern); inside sprint branch, `if isTacticalSprinting then` plays `TacticalSprintForward1` (falling back to `RunForward`) and returns early.
  - LeftShift `InputBegan`: double-tap detection — `(now - lastShiftPressTime) <= DOUBLE_TAP_WINDOW` within ACTIVE, `isMoving`, forward-dot ≥ `MIN_FORWARD_DOT`; sets `isTacticalSprinting = true` and captures `tacticalSprintStartTime`. `lastShiftPressTime` updated after each check.
  - LeftShift `InputEnded`: calls `stopTacticalSprint()` if active.
  - Crouch `InputBegan`: calls `stopTacticalSprint()` before entering crouch.
  - Heartbeat: after `applySpeed()`, if `isTacticalSprinting` and not moving or `fwdDot < MIN_FORWARD_DOT` → `stopTacticalSprint()` + `applySpeed()`.
  - Phase-exit (non-ACTIVE): directly clears `isTacticalSprinting` / `tacticalSprintStartTime` / `clearTacticalSprintStopConnection()` + `stopCurrentMovementAnimation()` WITHOUT calling `stopTacticalSprint()` (no visible effect during phase exit).
  - `resetState()`: `movementState.isTacticalSprinting = false` added.
  - `destroy()`: full tactical sprint state cleanup.
  - New public method `IsTacticalSprinting(): boolean` — read by `GunController`.

- **`src/client/GunController.lua`**:
  - Fire handler: block before `WeaponFired:FireServer` when `TACTICAL_SPRINT_BLOCKS_GUN_USE and MovementController.IsTacticalSprinting()`.
  - Reload handler: same block before `ReloadRequest:FireServer`.

- **`docs/PROJECT_MAP.md`** — Stage 2P tactical sprint IDs, behavior, and `IsTacticalSprinting()` method added.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x19): Stage 2P block added; new risks documented.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No `ViewModelController`, `SoundController`, or UI files.
All walk/crouch/idle/falling/landing IDs, speed multipliers, and AR15 behavior: unchanged.
No camera writes. No new RemoteEvents. No new `Humanoid.JumpPower` or fall damage changes.
No slide, vault, or prone.

### Validation
- `rojo build` — passes.
- MCP/Studio verified 2026-05-21:
  - All 7 new Constants runtime values correct: `TACTICAL_SPRINT_ENABLED=true`, `SPEED=30`, `ACCELERATION_TIME=1.0`, `MIN_FORWARD_DOT=0.35`, `BLOCKS_GUN_USE=true`, `DOUBLE_TAP_WINDOW=0.3`, `STOP_ANIMATION_ENABLED=true` ✅
  - All 3 animation IDs load on live character: `TacticalSprintForward1` (looped=true), `TacticalSprintForward2` (looped=true), `TacticalSprintStop` (looped=false) ✅
  - `IsTacticalSprinting()` returns false at rest ✅
  - WalkSpeed ramped to 30 (TACTICAL_SPRINT_SPEED) during double-tap test run — confirmed by live WalkSpeed=30 reading ✅
  - Gun fire guard: `BLOCKS_GUN_USE=true + IsTacticalSprinting()=true → BLOCKED`; `IsTacticalSprinting()=false → FIRED` ✅
  - 4 stopTacticalSprint() call sites confirmed in running module source ✅
  - `tacticalSprintStopConn ~= nil` gate in `updateMovementAnimation` confirmed ✅
  - Note: full live double-tap → animation → stop sequence was limited by MCP keyboard input not
    registering sustained W key in Studio. All static patterns, load-time state, and guard logic
    verified programmatically. Speed ramp confirmed via observed WalkSpeed=30 reading.

---

## [2026-05-21] — Movement Stage 2O: Unarmed Falling looped + LandingMedium one-shot via Humanoid.StateChanged

### Summary
Adds R6 no-gun falling and medium landing animations driven by `Humanoid.StateChanged`. A looped
`Falling` clip plays when the Humanoid enters Freefall. On landing after at least 0.25 s of freefall,
a one-shot `LandingMedium` clip plays before normal animation selection resumes. Short hops, falls
while crouching, and falls while a crouch transition is playing all skip `LandingMedium` cleanly. AR15
set has no Falling/LandingMedium IDs and gracefully skips both animations. All existing walk, sprint,
crouch, idle, and strafe behavior is preserved unchanged.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added `Unarmed.Falling = "rbxassetid://86705296926580"` — looped falling clip (Stage 2O)
  - Added `Unarmed.LandingMedium = "rbxassetid://135915211175953"` — one-shot landing clip (Stage 2O)
  - Added `Constants.MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER = 1.0` (Stage 2O)
  - Added `Constants.MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER = 1.0` (Stage 2O)
  - Added `Constants.MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME = 0.25` — minimum freefall seconds before LandingMedium plays (Stage 2O)

- **`src/client/MovementController.lua`**:
  - New private state variables: `isFalling`, `airStartTime`, `isLandingPlaying`, `landingConn`, `stateChangedConn`.
  - New helper `clearLandingConnection()`: disconnects `landingConn`, clears `isLandingPlaying`. Must be called before any external Stop on LandingMedium.
  - New handler `onHumanoidStateChanged(_old, new)`: phase-gated to ACTIVE; on Freefall plays Falling looped; on Landed/Running stops Falling and plays LandingMedium if air time ≥ MIN_AIR_TIME and not crouching.
  - `getAnimationSpeedMultiplier()`: `Falling` → `MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER`; `LandingMedium` → `MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER`.
  - `loadMovementAnimations()`: disconnects `stateChangedConn` at top; resets `isFalling`/`airStartTime`/`clearLandingConnection()` on respawn; conditional loads for `Unarmed_Falling` and `Unarmed_LandingMedium`; `_LandingMedium$` added to `Looped = false` pattern.
  - `updateMovementAnimation()`: `if isFalling then return end` and `if isLandingPlaying then return end` guards added after `crouchTransitionPlaying` check.
  - `setupCharacter()`: `stateChangedConn = hum.StateChanged:Connect(onHumanoidStateChanged)` added after `loadMovementAnimations()`. NOT stored in `_connections`.
  - Phase-exit handler (non-ACTIVE): `isFalling = false; clearLandingConnection()` added.
  - `destroy()`: `stateChangedConn` disconnected; `isFalling`/`airStartTime` reset; `clearLandingConnection()` called.
  - Header updated to Stage 2O. Ready log message updated.

- **`docs/PROJECT_MAP.md`** — Falling/LandingMedium IDs added; falling behavior section updated.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x18): Stage 2O block added; "jump/fall" gap changed to "jump" and "climb" separate items (fall now implemented); four new Stage 2O risks added.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
All walk/sprint/crouch/idle/strafe animation IDs and speed multipliers: unchanged.
AR15 set: no Falling or LandingMedium tracks — gracefully skipped by `animationTracks[key] ~= nil` guard.
No camera writes. No new RemoteEvents. No gun/combat logic touched.
No `Humanoid.JumpPower`, `WalkSpeed`, `HipHeight`, or fall damage changes.

### Validation
- `rojo build` — passes.
- MCP/Studio verified 2026-05-21 — fall monitor trace (50-stud drop):
  - `t=0.13s Freefall` → Falling (`86705296926580`, `L=true`) starts, Idle fades out ✅
  - `t=0.32s Freefall` → Falling only (Idle fully gone) ✅
  - `t=0.73s Landed`  → LandingMedium (`135915211175953`, `L=false`) starts, Falling fades out ✅
  - `t=0.92s Running` → LandingMedium only (Falling fully gone) ✅
  - `t=1.65s Running` → Idle starts (LandingMedium Stopped callback fired, gate released) ✅
  - `t=1.95s Running` → Idle only (clean return to normal loop) ✅

---

## [2026-05-20] — Movement Stage 2N: CrouchIdle looped animation + CrouchWalkStart one-shot transition

### Summary
Adds two new Unarmed crouch animation behaviors: `CrouchIdle` (looped idle played while crouching
and not moving, replacing the EnterCrouch bottom-pose hold when available) and `CrouchWalkStart`
(one-shot transition played exactly once when the player begins moving while crouched). A deferred
alternate `CrouchIdleAlt` clip is loaded but not selected. `CrouchWalk` and `CrouchWalkForward` IDs
are updated to a new confirmed-good clip. All directional crouch-walk, sprint, idle, and AR15 behavior
are unchanged.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added `Unarmed.CrouchIdle = "rbxassetid://81947601552045"` — looped idle while crouched+still (Stage 2N)
  - Added `Unarmed.CrouchIdleAlt = "rbxassetid://132053404406349"` — deferred alternate; loaded, not selected (Stage 2N)
  - `Unarmed.CrouchWalk`:        `82558685099409` → `70428646705219` (Stage 2N)
  - `Unarmed.CrouchWalkForward`: `82558685099409` → `70428646705219` (Stage 2N)
  - Added `Unarmed.CrouchWalkStart = "rbxassetid://129868628706658"` — one-shot idle-to-walk transition (Stage 2N)
  - All other CrouchWalk* directional IDs, all walk/run/idle IDs, and all AR15 IDs unchanged.

- **`src/client/MovementController.lua`**:
  - New private state variables: `crouchWalkStartPlaying`, `crouchWalkStartConn`, `wasMovingWhileCrouching`.
  - New helper `clearCrouchWalkStart()` — disconnects the CrouchWalkStart Stopped callback and clears the playing flag. Mirrors the `clearCrouchTransitionConnection()` pattern; must be called before any external Stop.
  - `loadMovementAnimations()`: conditional loads for `Unarmed_CrouchIdle`, `Unarmed_CrouchIdleAlt`, `Unarmed_CrouchWalkStart`; Looped=false pattern extended to include `_CrouchWalkStart$`; respawn resets for all three new state variables.
  - `getAnimationSpeedMultiplier()`: `CrouchIdle` and `CrouchIdleAlt` added to the `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER` (1.0×) branch.
  - `playCrouchTransition()` EnterCrouch Stopped callback: sets `wasMovingWhileCrouching = true` when still crouching and already moving at transition end, to skip CrouchWalkStart.
  - `updateMovementAnimation()` crouch-moving branch: detects start-of-movement via `wasMovingWhileCrouching` flag; plays `CrouchWalkStart` once if present; returns early while one-shot runs; directional selection resumes after it finishes.
  - `updateMovementAnimation()` crouch-not-moving branch: resets `wasMovingWhileCrouching`; clears any active CrouchWalkStart; prefers `CrouchIdle` over `holdCrouchBottomPose()` when track is present; falls back to bottom-pose hold when absent. The `playMovementAnimation()` guard prevents CrouchIdle from restarting every frame.
  - `destroy()`: calls `clearCrouchWalkStart()` and resets `wasMovingWhileCrouching`.
  - Header, stage list, and scope comments updated to Stage 2N.

- **`docs/PROJECT_MAP.md`** — CrouchIdle/CrouchIdleAlt/CrouchWalkStart entries added; CrouchWalk/CrouchWalkForward IDs updated; crouch behavior section updated.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x17): Stage 2N block added; CrouchIdleAlt unused-track risk entry added; CrouchWalkStart edge-case notes.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
All directional crouch-walk IDs (CrouchWalkBackward, Left, Right, and all four diagonals): unchanged.
All walk/run/idle/EnterCrouch/ExitCrouch IDs: unchanged. All AR15 IDs: unchanged.
No `updateMovementAnimation()` directional selection logic changed.
No speed multiplier values changed. No camera, mouse-lock, or combat behavior changed.
AR15 set: no CrouchIdle or CrouchWalkStart tracks — falls back to existing bottom-pose hold as before.

### Validation
- `rojo build` — passes.
- MCP/Studio verified 2026-05-20:
  - Constants: all five Stage 2N IDs confirmed correct; old CrouchWalk ID (82558685099409) absent.
  - Animation load test: CrouchIdle `looped=true`, CrouchIdleAlt `looped=true`, CrouchWalkStart `looped=false` — all load without error on a live character.
  - Idle track playing (rbxassetid://132044223555193) confirms ACTIVE phase + animation system live.

---

## [2026-05-20] — Movement Stage 2M: Unarmed walking animation ID replacement

### Summary
All 8 Unarmed R6 walking animation IDs replaced with new confirmed-good clips covering all
walk directions. A new `WalkForwardAlt` clip is added and pre-loaded for a future variation
system, but is not yet selected. All selection logic, speed multipliers, sprint, crouch, idle,
and AR15 behavior are unchanged.

### Changed files

- **`src/shared/Constants.lua`**:
  - `Unarmed.WalkForward`:     `71329939839948` → `81276554788940`
  - Added `Unarmed.WalkForwardAlt = "rbxassetid://97919904114609"` (loaded, not selected)
  - `Unarmed.WalkLeft`:        `115652140967957` → `127934481756733`
  - `Unarmed.WalkRight`:       `82804864629403`  → `122034548466839`
  - `Unarmed.WalkBackward`:    `107080862064563` → `140436478515683`
  - `Unarmed.WalkBackwardLeft`:  `107785647885776` → `137714892165355`
  - `Unarmed.WalkBackwardRight`: `109190640713438` → `83443564844340`
  - `Unarmed.WalkForwardLeft`:   `97324289156918`  → `137297382056770`
  - `Unarmed.WalkForwardRight`:  `81077784555491`  → `133633696854516`
  - `RunForward`, all CrouchWalk* IDs, and all AR15 IDs unchanged.

- **`src/client/MovementController.lua`**:
  - `loadMovementAnimations()`: conditional load of `Unarmed_WalkForwardAlt` added (only if ID is non-empty).
  - `getAnimationSpeedMultiplier()`: `WalkForwardAlt` added to the walk-multiplier branch (1.3×).
  - Stage header updated: 2L → 2L + 2M. Ready log updated.
  - No selection-logic changes. Sprint, crouch, idle, and walk directional behavior unchanged.

- **`docs/PROJECT_MAP.md`** — all 8 walk IDs updated; `WalkForwardAlt` entry added with deferred note; ID history updated.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x16): Stage 2M block added; `WalkForwardAlt` unused-track risk entry added.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
`RunForward`, `RunForwardLeft`, `RunForwardRight`, all CrouchWalk* IDs, all AR15 IDs: unchanged.
No selection logic changed in `updateMovementAnimation()`.
No speed multiplier values changed.
No camera, mouse-lock, or combat behavior changed.

### Validation
- `rojo build` — passes.
- MCP/Studio verified 2026-05-20: all 9 new IDs present, all 8 old IDs absent, WalkForwardAlt in toLoad + speed helper, sprint block = 1 code line.

---

## [2026-05-20] — Movement Stage 2L: Unarmed forward animation ID swap + sprint simplification

### Summary
Replaced both Unarmed R6 forward animation IDs with confirmed-good clips. Simplified sprint
animation selection so all sprint directions (Forward, Backward, Left, Right, and all diagonals)
always play `RunForward` for the current animation set, regardless of `customMouseLocked` state.
`RunForwardLeft` and `RunForwardRight` IDs are retained in Constants but are intentionally unused.
All existing animation speed multipliers are unchanged.

### Changed files

- **`src/shared/Constants.lua`**:
  - `Unarmed.WalkForward`: `rbxassetid://97200177177374` → `rbxassetid://71329939839948`
  - `Unarmed.RunForward`:  `rbxassetid://81826691810907` → `rbxassetid://79045069356901`
  - `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER` comment updated to note RunForwardLeft/Right deferred.
  - All other IDs and all speed multiplier values preserved.

- **`src/client/MovementController.lua`**:
  - Sprint block in `updateMovementAnimation()` simplified from a 14-line conditional (Unarmed+mouse-lock → RunForwardLeft/Right for diagonals) to a single line: `animName = setName .. "_RunForward"`.
  - Header, `updateMovementAnimation` scope comment, and ready log updated to document Stage 2L.
  - Stage header updated: 2K → 2K + 2L.

- **`docs/PROJECT_MAP.md`** — Unarmed WalkForward/RunForward IDs updated; RunForwardLeft/Right marked deferred; sprint behavior section updated; multiplier table updated.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x15): Stage 2L block added; sprint diagonal gap updated to note intentional deferral; Stage 2L direction-mismatch risk added.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
All other Unarmed animation IDs (WalkLeft, WalkRight, WalkBackward, diagonals, Idle, EnterCrouch,
ExitCrouch, all 9 CrouchWalk* IDs) preserved. All AR15 IDs preserved.
No camera changes. No new remotes. No movement speed constants changed.
No mouse-lock, crouch, idle, or walk directional behavior changed.
Speed multipliers (walk 1.3×, strafe 1.4×, run 1.15×, idle 0.75×, crouch transition 0.9×, crouch walk 1.0×) preserved.

### Validation
- `rojo build` — passes.
- MCP/Studio verified 2026-05-20: sprint block code = `animName = setName .. "_RunForward"` (single line, no conditionals).

---

## [2026-05-20] — Movement Stage 2K: third-person zoom limits + mouse-lock camera distance/offset

### Summary
Third-person camera zoom range constrained to 4–14 studs (via `Players.LocalPlayer.CameraMinZoomDistance`
and `CameraMaxZoomDistance`). No first-person forcing — the player can scroll freely within the range.
Custom mouse-lock toggle key changed from LeftAlt → LeftControl (LeftAlt is now free; LeftShift remains
sprint-only). When mouse lock is ON: zoom is pinned at 8 studs and `Humanoid.CameraOffset` is set to
`Vector3.new(1.75, 0, 0)` for a right-shoulder over-the-shoulder view. When mouse lock is OFF: zoom
restores to 4–14 and CameraOffset returns to zero. Camera writes use player properties only — no
`camera.CFrame` writes, no CameraType=Scriptable, no FieldOfView changes.

### Changed files

- **`src/shared/Constants.lua`**:
  - Changed `CUSTOM_MOUSE_LOCK_TOGGLE_KEY`: `Enum.KeyCode.LeftAlt` → `Enum.KeyCode.LeftControl`.
  - Added `THIRD_PERSON_MIN_ZOOM_DISTANCE = 4`.
  - Added `THIRD_PERSON_MAX_ZOOM_DISTANCE = 14`.
  - Added `CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE = 8`.
  - Added `CUSTOM_MOUSE_LOCK_CAMERA_OFFSET = Vector3.new(1.75, 0, 0)`.
  - Added `CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET = Vector3.zero`.
  - Added `CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE = true`.
  - Added `CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET = true`.

- **`src/client/MovementController.lua`**:
  - Stage header updated: 2J → 2J + 2K.
  - Three new module-level state variables: `defaultCameraMinZoomDistance`, `defaultCameraMaxZoomDistance`, `defaultCameraOffset`.
  - `cacheDefaultCameraSettings()` helper: stores initial player zoom distances and humanoid CameraOffset on first call (no-op on subsequent calls).
  - `applyThirdPersonZoomLimits()` helper: writes `CameraMin=4`, `CameraMax=14`; called in `Start()` and `CharacterAdded`.
  - `applyCustomMouseLockCamera()` helper: pins `CameraMin=CameraMax=8` and sets `CameraOffset=Vector3.new(1.75,0,0)`. Humanoid fallback: if module-level `humanoid` is nil, looks up via `Character:FindFirstChildOfClass("Humanoid")`.
  - `restoreNormalThirdPersonCamera()` helper: restores `CameraMin=4`, `CameraMax=14`, and `CameraOffset=zero`. Same humanoid fallback.
  - `applyCustomMouseLock()` updated: calls `applyCustomMouseLockCamera()` when ON, `restoreNormalThirdPersonCamera()` when OFF, and `restoreNormalThirdPersonCamera()` when the master switch is disabled.
  - `Start()` updated: calls `cacheDefaultCameraSettings()` and `applyThirdPersonZoomLimits()` at startup.
  - `CharacterAdded` handler updated: calls `cacheDefaultCameraSettings()` then applies correct camera state for current lock state.
  - `destroy()` updated: calls `restoreNormalThirdPersonCamera()` and clears cache variables.
  - Camera rule section in header updated: documents CameraMin/Max and CameraOffset writes; removes "does NOT write CameraOffset".
  - ContextActionService comment updated: notes LeftControl (Stage 2K).

- **`docs/PROJECT_MAP.md`** — stage header updated to 2K; LeftControl documented throughout; CameraMin/Max and CameraOffset writes added to MovementController description; Stage 2K camera constants added to Constants section; SetCustomMouseLocked exposes entry updated.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x14): Stage 2K update block added; remaining-gaps "first-person integration" note added; 5 new Stage 2K risk entries added (toggle key conflict, CameraOffset character size, fallback reliability, zoom tuning, character-facing jitter).

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
No `src/client/GunController.lua`, `ViewModelController.lua`, `ClientInit.client.lua`, `SoundController.lua`.
No `src/client/UI/*.lua`. No `src/shared/WeaponData.lua`.
No `camera.CFrame` writes. No CameraType=Scriptable. No FieldOfView changes.
No new remotes. No slide, vault, stamina, or first-person forcing.
No movement speed, animation ID, or combat changes.
All existing animation IDs and speed multipliers preserved.

### Validation
- `rojo build` — passes.
- MCP/Studio verified 2026-05-20: INIT zoom=4/14 offset=0,0,0 ✅  ON zoom=8/8 offset=1.75,0,0 ✅  OFF zoom=4/14 offset=0,0,0 ✅

---

## [2026-05-20] — Movement Stage 2J: Unarmed 8-directional crouch-walk animations

### Summary
Nine Unarmed directional crouch-walk animation IDs added (`CrouchWalk`, `CrouchWalkForward`,
`CrouchWalkBackward`, `CrouchWalkLeft/Right`, `CrouchWalkForwardLeft/Right`,
`CrouchWalkBackwardLeft/Right`). CrouchWalk and CrouchWalkForward share the same forward asset (canonical
fallback). All tracks looped. New constant `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0`.
Direction selection while crouching and moving uses `customMouseLocked` as the gate — same system as
walk strafe gating. When mouse lock is off, CrouchWalkForward is always used regardless of direction.
AR15 armed crouched movement falls back to EnterCrouch bottom-pose hold (no AR15 CrouchWalk IDs added).
No HipHeight, CameraOffset, or camera.CFrame changes.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added to `MOVEMENT_ANIMATION_IDS.R6.Unarmed`:
    - `CrouchWalk            = "rbxassetid://82558685099409"`  (forward, canonical fallback alias)
    - `CrouchWalkForward     = "rbxassetid://82558685099409"`
    - `CrouchWalkBackward    = "rbxassetid://131295440357763"`
    - `CrouchWalkLeft        = "rbxassetid://103170217015576"`
    - `CrouchWalkRight       = "rbxassetid://84961452934451"`
    - `CrouchWalkForwardLeft  = "rbxassetid://115919203745144"`
    - `CrouchWalkForwardRight = "rbxassetid://107284851359368"`
    - `CrouchWalkBackwardLeft  = "rbxassetid://118800024223445"`
    - `CrouchWalkBackwardRight = "rbxassetid://104285284019251"`
  - Added `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0`.

- **`src/client/MovementController.lua`**:
  - Stage header updated: 2I → 2I + 2J.
  - `getAnimationSpeedMultiplier()`: `animationName:sub(1, 10) == "CrouchWalk"` prefix check → returns `MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER`.
  - `loadMovementAnimations()`: replaces the simple `r6.Unarmed.CrouchWalk` conditional with a loop over all 9 `unarmedCrouchWalkNames`; conditionally loads each if the ID exists. AR15 generic `CrouchWalk` still loaded if populated.
  - `updateMovementAnimation()` crouch-moving branch: full 8-directional selection. `customMouseLocked` OFF → CrouchWalkForward fallback. `customMouseLocked` ON → per-direction chains (mirrors walk system). Non-Unarmed → generic CrouchWalk or hold bottom pose. Crouch-idle (not moving) → stop any `_CrouchWalk*` and hold bottom pose.
  - `playCrouchTransition()` EnterCrouch Stopped callback: starts CrouchWalkForward (or CrouchWalk alias) immediately when moving, to avoid a blank frame; direction is refined on the next Heartbeat.

- **`docs/PROJECT_MAP.md`** — stage header updated to 2J; 9 new Unarmed CrouchWalk* IDs documented; crouch-walk behavior + direction gating + fallback documented; AR15 deferred noted; multiplier documented.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x15): Stage 2J update block added; remaining-gaps "crouch walk" entry updated (Unarmed done, AR15 deferred); 4 new Stage 2J risk entries added; Trigger/Fix when lines updated.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
No camera changes. No gun/combat changes. No new remotes.
No AR15 CrouchWalk IDs added. No HipHeight, CameraOffset, or FieldOfView changes.
No CrouchIdle animation added. No slide, vault, or stamina changes.
Existing animation IDs (walk, run, idle, EnterCrouch/ExitCrouch, AR15 set) unchanged.
All existing speed multipliers (walk 1.3×, strafe 1.4×, run 1.15×, idle 0.75×, crouch transition 0.9×) preserved.

### Validation
- `rojo build` — passes.
- MCP/Studio verification pending. See DEBT-044 (x15) for test steps.

---

## [2026-05-20] — Movement Stage 2I: Hold-to-crouch + EnterCrouch bottom-pose hold

### Summary
Crouch input changed from toggle-on-C to hold-to-crouch: holding C enters crouch, releasing C exits
crouch. After the EnterCrouch one-shot finishes, MovementController now freezes the clip at its final
frame (`AdjustSpeed(0)` + `TimePosition = near_end`) so the character stays visually crouched instead
of reverting to standing idle. Four new Constants added (CROUCH_HOLD_KEY, CROUCH_HOLD_BOTTOM_POSE_ENABLED,
CROUCH_TRANSITION_MIN_HOLD_TIME, CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK). CrouchWalk is supported
if an ID already exists in Constants — no IDs added in this stage.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added `CROUCH_HOLD_KEY = Enum.KeyCode.C` — key held to enter crouch; release to exit.
  - Added `CROUCH_HOLD_BOTTOM_POSE_ENABLED = true` — enables EnterCrouch bottom-pose freeze.
  - Added `CROUCH_TRANSITION_MIN_HOLD_TIME = 0.05` — seconds from clip end for the hold TimePosition.
  - Added `CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98` — fallback if clip Length == 0.

- **`src/client/MovementController.lua`**:
  - Stage header updated: 2H → 2H + 2I.
  - New private state: `isHoldingCrouchBottomPose`, `crouchHoldTrack`, `crouchBottomPoseWarned`.
  - `stopCrouchTransition()` renamed to `clearCrouchTransitionConnection()` — disconnect only; callers set `crouchTransitionPlaying` explicitly.
  - New helper `holdCrouchBottomPose()`: plays EnterCrouch at AdjustSpeed(0), parked at final frame. Track managed independently via `crouchHoldTrack`.
  - New helper `clearCrouchBottomHold()`: restores AdjustSpeed + Stop(fade). Safe to call when idle.
  - `playCrouchTransition()` rewritten: clears existing conn + hold + locomotion before starting. EnterCrouch Stopped callback: if still crouching and moving and CrouchWalk exists → play CrouchWalk; else → `holdCrouchBottomPose()`.
  - `updateMovementAnimation()`: dedicated crouch branch (returns early, before standing logic). Moving + CrouchWalk → play CrouchWalk; moving + no CrouchWalk → hold bottom pose; idle → hold bottom pose.
  - `loadMovementAnimations()`: `crouchHoldTrack = nil`, `isHoldingCrouchBottomPose = false`, `crouchBottomPoseWarned = false` in reset block (no Stop call — old Animator may be gone).
  - Crouch input: replaced toggle `InputBegan` with hold: `InputBegan` (C down) enters crouch; `InputEnded` (C up) exits crouch + clears hold + plays ExitCrouch.
  - Phase exit and `destroy()`: `clearCrouchTransitionConnection()` → `crouchTransitionPlaying = false` → `clearCrouchBottomHold()` → `stopCurrentMovementAnimation()`.

- **`docs/PROJECT_MAP.md`** — stage header updated to 2F+2G+2H+2I; "C=crouch toggle" → "C=hold-to-crouch"; Stage 2I behavior documented; CROUCH_HOLD_* constants documented.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated (x14): Stage 2I update block added; remaining-gaps header updated; crouch walk/idle entries updated; Stage 2H risk about idle-while-crouched marked resolved; Stage 2I risks added.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
No camera changes. No gun/combat changes. No new remotes.
No new animation IDs. No HipHeight, CameraOffset, or FieldOfView changes.

### Validation
- `rojo build` — passes.
- MCP/Studio verification pending. See DEBT-044 (x14) for test steps.

---

## [2026-05-20] — Movement Stage 2H: Idle + enter/exit crouch transition animations (Unarmed and AR15)

### Summary
Idle (looped) and EnterCrouch/ExitCrouch (one-shot) animations added for both Unarmed and AR15 movement
sets. Idle plays whenever the player is standing still in ACTIVE phase. Pressing C plays EnterCrouch;
releasing C plays ExitCrouch. A `crouchTransitionPlaying` flag gates `updateMovementAnimation` for the
duration of each one-shot clip. Two new speed multiplier constants: idle at 0.75×, crouch transitions
at 0.9×.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added to `MOVEMENT_ANIMATION_IDS.R6.Unarmed`:
    - `Idle        = "rbxassetid://132044223555193"` (looped)
    - `EnterCrouch = "rbxassetid://105064599119554"` (one-shot)
    - `ExitCrouch  = "rbxassetid://104596765238289"` (one-shot)
  - Added to `MOVEMENT_ANIMATION_IDS.R6.AR15`:
    - `Idle        = "rbxassetid://117989834436525"` (looped)
    - `EnterCrouch = "rbxassetid://79753647497328"` (one-shot)
    - `ExitCrouch  = "rbxassetid://91295776984408"` (one-shot)
  - Added `MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER = 0.75`
  - Added `MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9`
  - Walk/strafe/run multipliers (1.3/1.4/1.15) preserved.

- **`src/client/MovementController.lua`**:
  - Stage header updated: 2G → 2G + 2H.
  - New private state: `crouchTransitionPlaying: boolean`, `crouchTransitionConn: RBXScriptConnection?`.
  - New helper `stopCrouchTransition()` (no deps, defined before Stage 2A): disconnects Stopped conn, clears flag. Called before all external `track:Stop()` sequences to prevent spurious callbacks.
  - `getAnimationSpeedMultiplier()`: `Idle` → 0.75×; `EnterCrouch`/`ExitCrouch` → 0.9×.
  - `loadMovementAnimations()`: 6 new toLoad entries; loop now sets `track.Looped = false` for `_EnterCrouch$` and `_ExitCrouch$` keys; `stopCrouchTransition()` added to the reset block.
  - New helper `playCrouchTransition(entering: boolean)` (after `playMovementAnimation`): plays EnterCrouch or ExitCrouch for the active weapon set; tracks key via `currentAnimationName`; sets `crouchTransitionPlaying = true`; Stopped callback clears flag and `currentAnimationName`.
  - `updateMovementAnimation()`: `crouchTransitionPlaying` guard added; `setName` moved before isMoving check; not-moving branch plays `setName .. "_Idle"` if loaded, otherwise stops current animation.
  - Crouch input handler: `playCrouchTransition(movementState.isCrouching)` called after `applySpeed()`.
  - Phase exit (RoundStateChanged): `stopCrouchTransition()` before `stopCurrentMovementAnimation()`.
  - `destroy()`: `stopCrouchTransition()` before `stopCurrentMovementAnimation()`.

- **`docs/PROJECT_MAP.md`** — 6 new animation IDs and 2 new multiplier constants documented; idle and crouch transition behavior documented.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated to x13; Stage 2H update block added; remaining-gaps list updated (idle/jump split into separate entries); 3 new Stage 2H risk entries added.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
No camera changes. No gun/combat changes. No new remotes. No movement speed constants changed.
No crouch walk or crouch idle animation. No HipHeight, CameraOffset, or FieldOfView changes.

### Validation
- `rojo build` — passes.
- MCP/Studio verification pending.
  See DEBT-044 (x13) for test steps.

---

## [2026-05-20] — Movement Stage 2G: Unarmed run-forward diagonal animations + walk multiplier tuning

### Summary
Two confirmed-good R6 no-gun run-forward diagonal animation clips added to the Unarmed movement set.
When custom mouse lock is enabled (LeftAlt), sprinting into ForwardLeft plays RunForwardLeft and
ForwardRight plays RunForwardRight. Mouse lock off or AR15/other sets continue using RunForward for
all sprint directions. Walk animation speed multiplier changed from 1.7× to 1.3×; strafe (1.4×) and
run (1.15×) multipliers preserved.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added to `MOVEMENT_ANIMATION_IDS.R6.Unarmed`:
    - `RunForwardLeft  = "rbxassetid://94337945101783"`
    - `RunForwardRight = "rbxassetid://104724352837263"`
  - `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER`: `1.7` → `1.3`
  - `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER = 1.4` — preserved.
  - `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER = 1.15` — preserved.
  - All existing Unarmed and AR15 IDs preserved.

- **`src/client/MovementController.lua`**:
  - Stage header updated: 2F → 2F + 2G.
  - `loadMovementAnimations()`: 2 new Unarmed run diagonal entries added (pre-loaded at spawn).
  - `getAnimationSpeedMultiplier()`: RunForwardLeft and RunForwardRight return
    `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER` (1.15×).
  - `updateMovementAnimation()`: sprint block extended — Unarmed + `customMouseLocked == true`:
    ForwardLeft → RunForwardLeft (RunForward fallback); ForwardRight → RunForwardRight (RunForward fallback).
    All other sprint directions: unchanged RunForward. AR15/other sets: unchanged.

- **`docs/PROJECT_MAP.md`** — RunForwardLeft/RunForwardRight IDs added; sprint diagonal behavior
  documented; both speed multiplier tables updated to walk=1.3, run includes RunForwardLeft/Right.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated to x12; Stage 2G update block added; remaining-gaps
  list updated; speed multiplier risk note corrected.

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
No camera changes. No gun/combat changes. No new remotes. No movement speed constants changed.
No AR15 run diagonal animations added. No run strafe or run backward animations added.

### Validation
- `rojo build` — passes.
- MCP/Studio verification to be performed before commit.
  See DEBT-044 (x12) for test steps.

---

## [2026-05-20] — asset: swap Unarmed no-gun walk-forward and run-forward animation IDs

### Summary
Confirmed-good R6 no-gun forward walk and run animation clips replace the previous placeholders.
No MovementController logic, camera behavior, or gun/combat systems changed. Animation speed
multipliers preserved at their confirmed values (walk 1.7×, strafe 1.4×, run 1.15×).

### Changed files

- **`src/shared/Constants.lua`**:
  - `MOVEMENT_ANIMATION_IDS.R6.Unarmed.WalkForward`: `83352851460622` → `97200177177374`
  - `MOVEMENT_ANIMATION_IDS.R6.Unarmed.RunForward`: `106253559282626` → `81826691810907`
  - All other Unarmed IDs (WalkLeft/Right, WalkBackward, WalkBackwardLeft/Right, WalkForwardLeft/Right) preserved.
  - All AR15 IDs preserved.
  - Speed multipliers preserved: `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER = 1.7`,
    `MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER = 1.4`, `MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER = 1.15`.

- **`docs/PROJECT_MAP.md`** — Unarmed WalkForward/RunForward IDs updated; stale 2.0/1.35/1.0 speed
  multiplier table in the Constants section corrected to 1.7/1.4/1.15.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated to x11; ID swap block added.

### What was NOT changed
No `src/client/` files. No `src/server/` files. No `default.project.json`.
No MovementController logic. No camera changes. No gun/combat changes. No new remotes.

### Validation
- `rojo build` — passes.
- MCP unavailable — Studio verification not performed. Needs Studio verification.
  See DEBT-044 (x11) for test steps.

---

## [2026-05-20] — Movement Stage 2F: Unarmed backward and diagonal directional animations

### Summary
Five new confirmed-good no-gun directional animation clips added to the Unarmed movement set:
backward, backward-left, backward-right, forward-left, and forward-right. The `updateMovementAnimation`
selection logic is expanded for the Unarmed set so each of the eight directions plays its own clip.
Backward and diagonal animations do not require mouse lock. Pure lateral strafe (WalkLeft/WalkRight)
still requires LeftAlt mouse lock as before. AR15 set behavior is unchanged.

### Changed files

- **`src/shared/Constants.lua`**:
  - Added to `MOVEMENT_ANIMATION_IDS.R6.Unarmed`:
    - `WalkBackward      = "rbxassetid://107080862064563"`
    - `WalkBackwardLeft  = "rbxassetid://107785647885776"`
    - `WalkBackwardRight = "rbxassetid://109190640713438"`
    - `WalkForwardLeft   = "rbxassetid://97324289156918"`
    - `WalkForwardRight  = "rbxassetid://81077784555491"`
  - All existing IDs, constants, and AR15 entries preserved.

- **`src/client/MovementController.lua`**:
  - Stage header updated: 2E → 2E + 2F.
  - `getAnimationSpeedMultiplier()`: extended — WalkBackward, WalkBackwardLeft/Right, WalkForwardLeft/Right
    return `MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER` (1.7×). WalkLeft/WalkRight and RunForward unchanged.
  - `loadMovementAnimations()` toLoad table: 5 new Unarmed entries added (pre-loaded at spawn).
  - `updateMovementAnimation()`: Unarmed set now uses per-direction selection for all 8 directions.
    AR15 and other sets: left/right grouping behavior unchanged.

- **`docs/PROJECT_MAP.md`** — MovementController animation IDs table updated with 5 new Unarmed entries;
  Stage 2F noted; gating behavior for backward/diagonal clips documented.

- **`docs/TECHNICAL_DEBT.md`** — DEBT-044 updated to x10; Stage 2F update block added; remaining-gaps
  list revised to remove backward/diagonal (now implemented).

### What was NOT changed
No `src/server/` files. No `default.project.json`. No other client controllers.
No camera changes. No gun/combat changes. No new remotes. No movement speed constants changed.

### Validation
- `rojo build` — passes.
- MCP unavailable — Studio verification not performed. Needs Studio verification.
  See DEBT-044 (x10) for test steps.

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
