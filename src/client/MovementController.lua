--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MovementController
--
-- Movement Stage 1 + 2A + 2C + 2D + 2E + 2F + 2G + 2H + 2I + 2J + 2K + 2L + 2M + 2N + 2O (Animate-disable, R6 detection, animation-set selection,
-- strafe gating, animation speed multipliers, shift-lock sprint fix, custom mouse-lock toggle,
-- character-facing camera yaw, Unarmed backward/diagonal directional animations,
-- sprint always uses RunForward (RunForwardLeft/Right deferred — Stage 2L),
-- standing idle + enter/exit crouch one-shot transition animations,
-- hold-to-crouch + EnterCrouch bottom-pose hold,
-- Unarmed 8-directional crouch-walk animations + CrouchWalk speed multiplier,
-- third-person zoom limits + custom mouse-lock camera distance/offset,
-- CrouchIdle looped idle while crouched+still + CrouchWalkStart one-shot idle-to-walk transition,
-- Unarmed Falling looped + LandingMedium one-shot via Humanoid.StateChanged) —
-- walk, sprint, crouch speed; 8-direction camera-relative movement state; phase gating;
-- respawn handling; connection cleanup; R6 animation playback with Unarmed default set.
--
-- Bug fix (2026-05-18): The default Roblox Animate LocalScript inside the character
-- was overriding custom R6 AnimationTrack objects loaded in Stage 2A. MovementController
-- now calls disableDefaultAnimate() inside loadMovementAnimations() — after the character
-- is confirmed R6 — to stop the avatar animation pack from controlling locomotion.
-- This is gated by Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED and
-- Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT (both default true).
-- Animate is disabled (not destroyed) only when the rig is confirmed R6.
--
-- R6 detection (2026-05-18): Humanoid.RigType is the primary check. If RigType does not
-- report R6, a structural body-part fallback (hasR6BodyParts) is tried. If neither check
-- passes, getRigDebugSummary() is logged so the exact mismatch is immediately visible.
--
-- Animation-set selection (2026-05-18): MovementController defaults to the Unarmed
-- animation set when no weapon is equipped (equippedWeaponName == nil). Call
-- MovementController.SetEquippedWeaponName("AR15") to switch to AR15 movement animations.
-- This is presentation-only and does not affect server state, ammo, or combat.
--
-- Stage 2C (2026-05-18): Strafe animations (WalkLeft/WalkRight) now only play when
-- UserInputService.MouseBehavior == LockCenter (shift-lock / mouse-lock active). Without
-- mouse lock, left/right/diagonal movement falls back to WalkForward. LeftShift sprint
-- now works while shift lock is enabled: the gameProcessed guard was replaced with a
-- UserInputService:GetFocusedTextBox() check so Roblox's shift-lock Shift interception
-- no longer blocks sprint. Animation playback speeds are tuned via AdjustSpeed:
-- WalkForward at 2.0×, WalkLeft/WalkRight at 1.35×, RunForward unchanged at 1.0×.
--
-- Stage 2D (2026-05-19): Custom mouse-lock toggle added on LeftAlt (Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY).
-- Stage 2K (2026-05-20): Toggle key changed from LeftAlt to LeftControl.
--   Third-person camera zoom clamped to min=4 / max=14 studs (applied on Start + CharacterAdded).
--   Custom mouse lock ON:  CameraMin = CameraMax = 8 studs; Humanoid.CameraOffset = Vector3.new(1.75,0,0).
--   Custom mouse lock OFF: CameraMin=4, CameraMax=14; CameraOffset = Vector3.zero.
--   No camera.CFrame writes. No CameraType=Scriptable. No FieldOfView changes.
-- LeftShift is now sprint-only — it no longer conflicts with Roblox's default Shift Lock.
-- Strafe animation gating now depends on the local customMouseLocked boolean (set by
-- SetCustomMouseLocked / the LeftAlt toggle) rather than reading UserInputService.MouseBehavior
-- directly. UserInputService.MouseBehavior is written by SetCustomMouseLocked (LockCenter on,
-- Default off) but is NOT used as the strafe gate source.
-- Roblox default Shift Lock should be disabled in Studio (StarterPlayer.EnableMouseLockOption = false)
-- to avoid conflicts with LeftShift sprint.
-- This is NOT a full custom camera controller — camera rotation still runs through the Roblox
-- default camera system (LockCenter only locks cursor to center; it does not replace camera logic).
--
-- Stage 2E (2026-05-19): Character-facing camera yaw added.
-- When CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW is true, enabling custom mouse lock (LeftAlt) also:
--   • Caches Humanoid.AutoRotate (once per lock session) and sets AutoRotate = false.
--   • Reads workspace.CurrentCamera.CFrame.LookVector every Heartbeat, flattens to XZ, and
--     rotates HumanoidRootPart.CFrame to face that direction (position is preserved, no teleport).
-- On toggle-off or respawn, AutoRotate is restored from the cached value.
-- When CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION is true, facing rotation is only
-- applied during the ACTIVE phase. AutoRotate is restored on phase exit but the toggle state is
-- preserved; on ACTIVE re-entry with lock still on, AutoRotate is disabled again.
-- This is NOT a camera controller — it reads camera yaw only. It does NOT write camera.CFrame,
-- CameraOffset, FieldOfView, or add camera bob/sway/tilt/ADS/zoom/viewmodel effects.
--
-- Stage 2D bugfix (2026-05-19): Three bugs found after Stage 2D shipped:
--   (1) Roblox default Shift Lock still toggling with LeftShift:
--       Fixed via LocalPlayer.DevEnableMouseLock = false (pcall, once per Start + per respawn)
--       and StarterPlayer.EnableMouseLockOption = false in default.project.json.
--       New helper: disableRobloxDefaultMouseLock(). Gated by DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK.
--   (2) LeftAlt mouse-lock had ~1-frame delayed activation (InputBegan fires after CoreScripts):
--       Fixed via ContextActionService:BindActionAtPriority at priority 3000 (above CoreScript
--       default 2000). Action name MOUSE_LOCK_ACTION_NAME, unbound by name in destroy().
--   (3) WalkLeft/WalkRight strafe animations no longer playing:
--       Root cause: CoreScripts or UI transitions could reset MouseBehavior after the LeftAlt
--       toggle fired, but customMouseLocked (the gate source) still read true. Added
--       CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME: every Heartbeat re-writes LockCenter while
--       customMouseLocked is true so the lock cannot be silently stolen.
--   Phase behavior change: customMouseLocked is NO LONGER reset on phase exit. The player's
--   LeftAlt toggle state persists across ACTIVE → LOBBY → RESULTS → ACTIVE. Only respawn
--   (loadMovementAnimations) and destroy() reset it to false.
--   New constants added: DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK, CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME,
--   CUSTOM_MOUSE_LOCK_INPUT_PRIORITY (all in Constants.lua).
--
-- NOTE: disabling Animate removes idle, jump, fall, and climb animations in addition
-- to locomotion. Custom replacements for those states are needed in a future stage.
--
-- Owns:
--   • local movement input (LeftShift = sprint, C = hold-to-crouch, LeftControl = mouse-lock toggle)
--   • customMouseLocked boolean — true when LeftControl has toggled custom mouse lock on
--   • UserInputService.MouseBehavior writes: LockCenter (on) / Default (off) for custom mouse lock
--   • Humanoid.AutoRotate writes: false when custom mouse lock + FACE_CAMERA_YAW + ACTIVE phase;
--       restored from cached originalAutoRotate on toggle-off, respawn, phase-exit, or destroy
--   • HumanoidRootPart.CFrame yaw writes: rotates character to face camera yaw every Heartbeat
--       while mouse lock is on and FACE_CAMERA_YAW is true (position never changes; not a teleport)
--   • movementState table (isMoving, isSprinting, isCrouching, directionName, moveVector)
--   • Humanoid.WalkSpeed:
--       0                          when phase is not ACTIVE
--       Constants.WALK_SPEED       when ACTIVE and not sprinting/crouching
--       Constants.SPRINT_SPEED     when ACTIVE, sprinting, and moving
--       Constants.CROUCH_SPEED     when ACTIVE and crouching
--   • 8-directional direction detection via Humanoid.MoveDirection dot products
--   • R6 walk/run AnimationTracks loaded per character, played during ACTIVE phase only
--   • Disabling character.Animate (R6 characters only) to prevent avatar animation pack override
--   • Robust R6 rig detection: RigType primary, structural body-part fallback, debug summary on skip
--   • presentation-only equippedWeaponName driving animation set selection (Unarmed default)
--   • strafe animation gating via customMouseLocked (not Roblox default Shift Lock)
--   • animation playback speed multipliers applied via AnimationTrack:AdjustSpeed
--
-- Animation control constants (all in Constants.lua):
--   CUSTOM_MOVEMENT_ANIMATIONS_ENABLED = true       — master switch for custom anim system
--   DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = true — disables character.Animate
--   MOVEMENT_ANIMATION_DEBUG = true                 — logs load/switch events to Output
--   MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK = true — strafe anims require mouse lock (legacy gate)
--   CUSTOM_MOUSE_LOCK_ENABLED = true                — enables LeftAlt custom mouse-lock toggle
--   CUSTOM_MOUSE_LOCK_TOGGLE_KEY = Enum.KeyCode.LeftControl — toggle key (changed to LeftControl in Stage 2K)
--   CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true      — strafe gate reads customMouseLocked (not native ShiftLock)
--   CUSTOM_MOUSE_LOCK_DEBUG = true                  — logs mouse-lock toggle events to Output
--   DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK = true        — calls DevEnableMouseLock=false on Start/respawn
--   CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true    — re-writes LockCenter every Heartbeat while locked
--   CUSTOM_MOUSE_LOCK_INPUT_PRIORITY = 3000         — ContextActionService priority for LeftAlt bind
--   CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW = true        — rotate character to face camera yaw while locked
--   CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION = true — facing only during ACTIVE phase
--   CUSTOM_MOUSE_LOCK_ROTATION_DEBUG = true         — logs facing rotation events to Output
--   MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER = 1.3   — WalkForward/Backward/diagonal AdjustSpeed multiplier
--   MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER = 1.4  — WalkLeft/WalkRight AdjustSpeed multiplier
--   MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER = 1.15   — RunForward/RunForwardLeft/Right AdjustSpeed multiplier
--   MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER = 0.75  — Idle AdjustSpeed multiplier (Stage 2H)
--   MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9 — EnterCrouch/ExitCrouch AdjustSpeed multiplier (Stage 2H)
--   MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0 — CrouchWalk* directional tracks AdjustSpeed multiplier (Stage 2J)
--   CROUCH_HOLD_KEY = Enum.KeyCode.C            — key held to crouch (Stage 2I)
--   CROUCH_HOLD_BOTTOM_POSE_ENABLED = true       — enables EnterCrouch bottom-pose hold (Stage 2I)
--   CROUCH_TRANSITION_MIN_HOLD_TIME = 0.05       — seconds from end for hold TimePosition (Stage 2I)
--   CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98 — fallback when clip.Length == 0 (Stage 2I)
--
-- Camera rule (Stage 1 + 2A + 2C + 2D + 2E + 2K):
--   Reads workspace.CurrentCamera.CFrame for direction detection and camera yaw facing.
--   Writes UserInputService.MouseBehavior (LockCenter / Default) for custom mouse-lock toggle.
--   Writes Players.LocalPlayer.CameraMinZoomDistance and CameraMaxZoomDistance (Stage 2K):
--     Normal third-person: min=4, max=14 studs. Custom mouse lock: min=max=8 studs (locked).
--   Writes Humanoid.CameraOffset (Stage 2K):
--     Custom mouse lock ON:  Vector3.new(1.75, 0, 0) — right-shoulder over-the-shoulder offset.
--     Custom mouse lock OFF: Vector3.zero — no offset.
--   Does NOT write camera.CFrame or FieldOfView.
--   Does NOT set CameraType to Scriptable.
--   Does NOT add camera bob, sway, landing dip, tilt, ADS zoom, or viewmodel effects.
--   Does NOT implement a full custom camera controller — camera rotation uses Roblox default.
--
-- Stage 2E character rotation scope:
--   Writes Humanoid.AutoRotate (false while locked + ACTIVE; restored on toggle-off/phase-exit/respawn).
--   Writes HumanoidRootPart.CFrame yaw component every Heartbeat to face camera — preserves position.
--   Does NOT teleport the player. Does NOT change velocity, WalkSpeed, JumpPower, or HipHeight.
--
-- Stage 2A + 2C + 2D animation scope:
--   Defaults to Unarmed animation set when equippedWeaponName == nil (no weapon equipped).
--   Call SetEquippedWeaponName("AR15") to switch to AR15 movement animations.
--   True server-owned equipment state is deferred — see DEBT-050.
--   WalkLeft/WalkRight (pure lateral strafe) only when customMouseLocked == true (LeftAlt on).
--   Without custom mouse lock, pure Left/Right fall back to WalkForward.
--   WalkBackward always plays for Backward direction regardless of mouse-lock state.
--   WalkForwardLeft/Right and WalkBackwardLeft/Right always play regardless of mouse-lock state.
--   Sprint in any direction always uses RunForward for the current animation set. (Stage 2L)
--   RunForwardLeft/RunForwardRight IDs retained in Constants but no longer selected. (Stage 2L)
--   WalkForward/Backward/diagonals: 1.3× speed. WalkLeft/WalkRight: 1.4× speed. RunForward: 1.15× speed.
--   Sprint works with LeftShift even while shift lock is active (TextBox check instead of gp).
--   Stage 2F (2026-05-20): Unarmed backward/diagonal animation support added:
--     WalkBackward, WalkBackwardLeft, WalkBackwardRight, WalkForwardLeft, WalkForwardRight.
--   Stage 2G (2026-05-20): Unarmed run-forward diagonal IDs added (RunForwardLeft, RunForwardRight).
--     Sprint diagonal selection deferred in Stage 2L — sprint always uses RunForward now.
--   Stage 2H (2026-05-20): Idle (looped) + EnterCrouch/ExitCrouch one-shot transition animations added:
--     Idle plays when standing still in ACTIVE (both Unarmed and AR15 sets).
--     EnterCrouch plays when C is held; ExitCrouch plays when C is released (both sets).
--     crouchTransitionPlaying gates updateMovementAnimation during one-shot clips.
--   Stage 2I (2026-05-20): Hold-to-crouch + crouch bottom-pose hold:
--     C is now hold-to-crouch. Holding C: isCrouching=true + EnterCrouch. Releasing C: ExitCrouch.
--     After EnterCrouch finishes: holdCrouchBottomPose() pauses the clip at its final frame
--       (track:Play(0) + TimePosition + AdjustSpeed(0)) to keep the character visually crouched.
--     CrouchWalk plays while isCrouching=true + isMoving=true IF the animation ID exists;
--       otherwise the bottom-pose hold is preserved while the character moves at CROUCH_SPEED.
--   Stage 2J (2026-05-20): Unarmed 8-directional crouch-walk animations:
--     Nine Unarmed CrouchWalk* IDs added to Constants (CrouchWalk, CrouchWalkForward,
--       CrouchWalkBackward, CrouchWalkLeft/Right, CrouchWalkForwardLeft/Right, CrouchWalkBackwardLeft/Right).
--     All nine tracks are pre-loaded at spawn alongside the other Unarmed tracks.
--     CrouchWalkForward and CrouchWalk share the same asset ID (forward is the canonical clip).
--     Direction selection while crouching+moving:
--       customMouseLocked OFF → CrouchWalkForward fallback (no directional strafe).
--       customMouseLocked ON  → per-direction selection (mirrors walking direction logic).
--     AR15 set: no CrouchWalk IDs — falls back to bottom-pose hold (same as Stage 2I).
--     New constant: MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0 (all CrouchWalk* names).
--   No reload, fire, or ADS animations in Stage 2A/2C/2D/2E/2F/2G/2H/2I/2J.
--   No lower-body/upper-body animation split.
--   Non-R6 characters: animation loading skipped; getRigDebugSummary logged; Stage 1 speed logic remains active.
--
-- Not in Stage 1/2A/2D: slide, vault, stamina, prone, footsteps, crouch body lowering,
--   camera height changes, viewmodel sway, strafe/backward/diagonal animations.
-- Manual Studio step: disable StarterPlayer.EnableMouseLockOption = false to prevent
--   Roblox default Shift Lock from conflicting with LeftShift sprint.
--
-- Exposes:
--   GetMovementState()           → movementState table (all fields read-only for callers)
--   GetMoveState(): string       → "Idle"|"Walking"|"Sprinting"|"Crouching" (GunController compat)
--   IsADSBlocked(): boolean      → true while sprinting; blocks GunController ADS
--   GetViewmodelAddCFrame(): CFrame → identity in Stage 1/2A; ViewModelController multiplies this in
--   SetEquippedWeaponName(name)  → sets animation set (Unarmed if nil/"", AR15 if "AR15"); presentation only
--   GetEquippedWeaponName()      → returns current equippedWeaponName (nil = Unarmed set active)
--   SetCustomMouseLocked(bool)   → toggles custom mouse lock; writes UserInputService.MouseBehavior
--   IsCustomMouseLocked()        → returns current customMouseLocked boolean
--   Start()                      → called by ClientInit after MatchController:Start()
--   destroy()                    → disconnects all connections and resets state
--
-- Phase source: MatchController:GetPhase() (cached value) + RoundStateChanged for live updates.
-- Initialized at position 9 in ClientInit.client.lua.

local Players               = game:GetService("Players")
local RunService            = game:GetService("RunService")
local UserInputService      = game:GetService("UserInputService")
local ContextActionService  = game:GetService("ContextActionService")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")

-- ContextActionService action name for the custom mouse-lock toggle.
-- Used by both Start() (bind) and destroy() (unbind). Must be module-unique.
local MOUSE_LOCK_ACTION_NAME: string = "MovementController_ToggleCustomMouseLock"

-- ============================================================
-- Dependencies
-- ============================================================

local Modules        = ReplicatedStorage:WaitForChild("Modules")
local Constants      = require(Modules:WaitForChild("Constants"))
local Logger         = require(Modules:WaitForChild("Logger"))

-- MatchController is guaranteed Start()ed before this module's Start() (ClientInit order 1→9).
local MatchController = require(script.Parent:WaitForChild("MatchController"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- movementState — public read-only state table
-- Written only by this module. Callers read via GetMovementState().
-- ============================================================

local movementState = {
    isMoving      = false,          -- true when MoveDirection.Magnitude > MOVEMENT_DIRECTION_DEADZONE
    isSprinting   = false,          -- true while LeftShift is held during ACTIVE
    isCrouching   = false,          -- true while crouched (toggled by C during ACTIVE)
    directionName = "Idle",         -- one of 9 direction strings (see classifyDirection)
    moveVector    = Vector3.zero,   -- raw Humanoid.MoveDirection each Heartbeat
}

-- ============================================================
-- Private state
-- ============================================================

-- Current Humanoid — replaced on every CharacterAdded.
local humanoid: Humanoid? = nil

-- All RBXScriptConnections created in Start(). destroy() disconnects every entry.
local _connections: { RBXScriptConnection } = {}

-- ── Stage 2A animation state ──────────────────────────────────────────────────

-- AnimationTrack table keyed by "SetName_AnimName" (e.g. "AR15_WalkForward").
-- Typed AnimationTrack? so nil checks on absent keys are type-safe.
local animationTracks: { [string]: AnimationTrack? } = {}

-- Unparented Animation instances created during loadMovementAnimations().
-- Stored for explicit cleanup on respawn and in destroy().
local animationInstances: { [string]: Animation } = {}

-- The key currently being played, or "" when nothing is playing.
-- Guards against restarting the same track on every Heartbeat tick.
local currentAnimationName: string = ""

-- Whether a rig-type warning has already been issued for the current character.
-- Reset on each new character so future warnings are not suppressed.
local rigTypeWarned: boolean = false

-- Presentation-only equipped weapon name used solely for movement animation set selection.
-- nil  = no weapon equipped → Unarmed animation set (default).
-- "AR15" = AR15 equipped → AR15 animation set.
-- Any other non-empty string → Unarmed fallback (warn emitted in SetEquippedWeaponName).
-- Set via MovementController.SetEquippedWeaponName(). Never affects server state or combat.
-- Persists across character respawns; cleared only in destroy().
local equippedWeaponName: string? = nil

-- Last animation set name that was logged to Output.
-- Guards against per-frame spam: only logs when the set name changes.
-- Reset to "" on each character load so the first movement after respawn re-logs.
local lastAnimationSet: string = ""

-- Last known "strafe animations blocked" state for strafe-blocked debug log deduplication.
-- true = strafe was blocked on the last frame that logged. Logs only on state change.
-- Reset to false on each character load and in destroy().
local lastStrafeBlockedState: boolean = false

-- Custom mouse-lock state (Stage 2D — key changed to LeftControl in Stage 2K).
-- true  = LeftControl has toggled mouse lock on; UserInputService.MouseBehavior == LockCenter.
-- false = mouse lock off; UserInputService.MouseBehavior == Default.
-- Toggled by the ContextActionService handler (Start()) and by SetCustomMouseLocked().
-- Reset to false on respawn (loadMovementAnimations) and in destroy().
-- Phase changes do NOT reset this — the player's toggle state is preserved across phases.
-- This is the source of truth for strafe animation gating — NOT UserInputService.MouseBehavior.
local customMouseLocked: boolean = false

-- Stage 2E: character-facing state ──────────────────────────────────────────────

-- Current character Model — set by setupCharacter(), cleared by destroy().
-- Used by applyCharacterFacing() to locate HumanoidRootPart without an additional lookup.
local currentCharacter: Model? = nil

-- Current HumanoidRootPart — set by setupCharacter(), cleared by destroy().
-- Cached to avoid FindFirstChild on every Heartbeat tick.
local currentRootPart: BasePart? = nil

-- Cached Humanoid.AutoRotate value, captured once when custom mouse lock is first enabled.
-- Restored verbatim when lock is disabled, on respawn, phase exit (REQUIRE_ACTIVE=true), or destroy().
-- NOT cleared on phase exit — preserved so re-entry to ACTIVE can restore it correctly.
-- Cleared (set nil) on respawn (loadMovementAnimations) and when lock is explicitly disabled.
local originalAutoRotate: boolean? = nil

-- Last reason applyCharacterFacing() was skipped, used to deduplicate debug logs.
-- Reset to "" on each character load.
local lastFacingSkippedReason: string = ""

-- Stage 2K: third-person camera state ────────────────────────────────────────────
-- Cached once on first Start() call before any zoom overrides are applied.
-- Kept nil until cacheDefaultCameraSettings() runs so we only cache the true defaults.
-- These are not used for restoration (we always restore to THIRD_PERSON limits, not the
-- original Roblox defaults which are very wide), but are retained for diagnostics / future use.
local defaultCameraMinZoomDistance: number? = nil
local defaultCameraMaxZoomDistance: number? = nil
local defaultCameraOffset: Vector3? = nil

-- Stage 2H: crouch transition state ──────────────────────────────────────────

-- True while a one-shot EnterCrouch or ExitCrouch animation is playing.
-- Guards updateMovementAnimation from interrupting the transition mid-clip.
-- Cleared by stopCrouchTransition() and by the track.Stopped callback.
local crouchTransitionPlaying: boolean = false

-- Stopped-event connection for the active crouch transition track.
-- Disconnected by clearCrouchTransitionConnection() BEFORE any external track:Stop() call
-- to prevent the Stopped callback from firing spuriously.
local crouchTransitionConn: RBXScriptConnection? = nil

-- Stage 2I: crouch bottom-hold state ─────────────────────────────────────────

-- True while the EnterCrouch track is held at its final frame to keep the character
-- visually crouched (set by holdCrouchBottomPose; cleared by clearCrouchBottomHold).
local isHoldingCrouchBottomPose: boolean = false

-- The AnimationTrack held at its final frame during the crouch-bottom hold.
-- Always an EnterCrouch track for the current animation set.
-- nil when no hold is active. Set by holdCrouchBottomPose; cleared by clearCrouchBottomHold.
local crouchHoldTrack: AnimationTrack? = nil

-- Warn-once guard so holdCrouchBottomPose() does not spam Logger.warn every frame
-- when the EnterCrouch track is absent. Reset to false on each respawn.
local crouchBottomPoseWarned: boolean = false

-- Stage 2N: CrouchWalkStart one-shot transition state ────────────────────────
-- True while the CrouchWalkStart one-shot clip is playing.
-- Guards updateMovementAnimation from interrupting or re-selecting animations until
-- the clip finishes. Cleared by clearCrouchWalkStart() via the track's Stopped event.
local crouchWalkStartPlaying: boolean = false

-- Stopped-event connection for the active CrouchWalkStart track.
-- Disconnected by clearCrouchWalkStart() BEFORE any external track:Stop() to prevent
-- spurious callbacks — mirrors the clearCrouchTransitionConnection() pattern.
local crouchWalkStartConn: RBXScriptConnection? = nil

-- True while the player is crouching and has already started moving during this crouch session.
-- Set to true in the crouch-moving branch when movement begins (so CrouchWalkStart plays).
-- Also set to true in the EnterCrouch Stopped callback when the player is already moving
-- (to skip CrouchWalkStart — the player was moving before the transition finished).
-- Reset to false in the crouch-not-moving branch and on respawn.
local wasMovingWhileCrouching: boolean = false

-- Stage 2O: falling and landing animation state ───────────────────────────────

-- True while the Humanoid is in the Freefall state.
-- Gates updateMovementAnimation from overriding the Falling looped track.
-- Set true on Freefall; cleared to false on any landing state or on respawn/destroy.
local isFalling: boolean = false

-- os.clock() timestamp captured when Freefall begins.
-- Used to compute air time on landing; compared against MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME.
local airStartTime: number = 0

-- True while the LandingMedium one-shot animation is playing.
-- Gates updateMovementAnimation from overriding the landing clip.
-- Cleared by clearLandingConnection() via the track's Stopped event.
local isLandingPlaying: boolean = false

-- Stopped-event connection for the active LandingMedium track.
-- Disconnected by clearLandingConnection() BEFORE any external track:Stop() to prevent
-- spurious callbacks — mirrors the clearCrouchTransitionConnection() pattern.
local landingConn: RBXScriptConnection? = nil

-- Per-character Humanoid.StateChanged connection.
-- Connected in setupCharacter() after animation tracks are loaded.
-- Disconnected at the top of loadMovementAnimations() (on respawn) and in destroy().
-- NOT stored in _connections (which persists across respawns).
local stateChangedConn: RBXScriptConnection? = nil

-- ============================================================
-- Private helpers — Stage 1
-- ============================================================

-- Resets all movementState fields to initial (idle) values.
-- Does NOT apply WalkSpeed — callers must call applySpeed() or set it directly after.
local function resetState()
    movementState.isMoving      = false
    movementState.isSprinting   = false
    movementState.isCrouching   = false
    movementState.directionName = "Idle"
    movementState.moveVector    = Vector3.zero
end

-- Sets Humanoid.WalkSpeed according to the current phase and movementState.
-- Safe to call at any time; guards against nil humanoid.
-- Speed priority: not-ACTIVE → 0; crouching → CROUCH_SPEED;
--   sprinting+moving → SPRINT_SPEED; else → WALK_SPEED.
local function applySpeed()
    local hum = humanoid
    if not hum then return end

    if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then
        hum.WalkSpeed = 0
        return
    end

    if movementState.isCrouching then
        hum.WalkSpeed = Constants.CROUCH_SPEED
    elseif movementState.isSprinting and movementState.isMoving then
        hum.WalkSpeed = Constants.SPRINT_SPEED
    else
        hum.WalkSpeed = Constants.WALK_SPEED
    end
end

-- Maps Humanoid.MoveDirection to one of 9 named directions.
-- Returns "Idle" when the magnitude is below MOVEMENT_DIRECTION_DEADZONE.
-- Uses dot products against the camera's XZ-flattened look and right vectors
-- so directions are camera-relative (W = Forward relative to where you're looking).
local function classifyDirection(moveDir: Vector3): string
    if moveDir.Magnitude < Constants.MOVEMENT_DIRECTION_DEADZONE then
        return "Idle"
    end

    local cam      = workspace.CurrentCamera
    local look     = cam.CFrame.LookVector
    local right    = cam.CFrame.RightVector

    -- Flatten onto the XZ plane so camera pitch does not affect direction classification.
    local camFlat  = Vector3.new(look.X,  0, look.Z)
    local camRight = Vector3.new(right.X, 0, right.Z)

    -- Guard: camera may briefly look straight up or down (e.g. first-person death pan).
    if camFlat.Magnitude < 0.01 then
        camFlat = Vector3.new(0, 0, -1)  -- default: world -Z
    else
        camFlat = camFlat.Unit
    end
    if camRight.Magnitude < 0.01 then
        -- Derive right as the 90° CW rotation of camFlat on XZ.
        camRight = Vector3.new(camFlat.Z, 0, -camFlat.X)
    else
        camRight = camRight.Unit
    end

    local f = moveDir:Dot(camFlat)   -- positive = forward relative to camera
    local r = moveDir:Dot(camRight)  -- positive = right relative to camera

    -- Diagonal threshold: both axes must exceed this to qualify as a diagonal direction.
    -- Keeping this separate from MOVEMENT_DIRECTION_DEADZONE (magnitude check above).
    local diag: number = 0.35

    local isFwd   = f >  diag
    local isBack  = f < -diag
    local isRight = r >  diag
    local isLeft  = r < -diag

    if   isFwd  and isRight then return "ForwardRight"
    elseif isFwd  and isLeft  then return "ForwardLeft"
    elseif isBack and isRight then return "BackwardRight"
    elseif isBack and isLeft  then return "BackwardLeft"
    elseif isFwd              then return "Forward"
    elseif isBack             then return "Backward"
    elseif isRight            then return "Right"
    elseif isLeft             then return "Left"
    else                           return "Idle"
    end
end

-- ============================================================
-- Private helpers — Stage 2E: character-facing camera yaw
-- ============================================================

-- Returns the camera's look direction flattened to the XZ plane as a unit Vector3,
-- or nil when the camera look vector is too near-vertical to produce a stable yaw
-- (magnitude of XZ projection < 0.001 — avoids NaN from Unit on a near-zero vector).
-- Reads workspace.CurrentCamera.CFrame — does NOT write it.
local function getCameraFlatLookVector(): Vector3?
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local look   = camera.CFrame.LookVector
    local flat   = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.001 then return nil end
    return flat.Unit
end

-- Restores Humanoid.AutoRotate to the cached originalAutoRotate value (defaults to true
-- if nothing was cached). Does NOT clear originalAutoRotate — callers that need to clear
-- it (disable path, respawn, destroy) must set it to nil themselves after calling.
-- Safe to call when humanoid is nil (no-ops silently).
local function restoreCharacterAutoRotate()
    local hum = humanoid
    if not hum then return end
    local restoreValue = if originalAutoRotate ~= nil then originalAutoRotate else true
    hum.AutoRotate = restoreValue
    if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG then
        Logger.debug(
            "[MovementController] AutoRotate restored → " .. tostring(restoreValue)
        )
    end
end

-- Rotates the character's HumanoidRootPart to face the camera's yaw direction every
-- Heartbeat while custom mouse lock is active and FACE_CAMERA_YAW is enabled.
-- Phase-gated when REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION is true (only runs in ACTIVE).
-- No-ops silently when guards fail (no humanoid, no root part, near-vertical camera look).
-- Writes HumanoidRootPart.CFrame with the same position — the character is rotated in place;
-- it is NOT teleported and its velocity is NOT modified.
-- Logs skip-reason changes once per reason when CUSTOM_MOUSE_LOCK_ROTATION_DEBUG is true.
local function applyCharacterFacing()
    if not Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW then return end
    if not customMouseLocked then return end

    -- Phase gate: only apply rotation in ACTIVE when required.
    if Constants.CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION then
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then
            -- Suppress per-frame spam: log only when the skip reason changes.
            local reason = "phase_not_active"
            if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG and lastFacingSkippedReason ~= reason then
                lastFacingSkippedReason = reason
                Logger.debug("[MovementController] applyCharacterFacing: skipped — phase not ACTIVE")
            end
            return
        end
    end

    local root = currentRootPart
    if not root then
        local reason = "no_root"
        if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG and lastFacingSkippedReason ~= reason then
            lastFacingSkippedReason = reason
            Logger.debug("[MovementController] applyCharacterFacing: skipped — no HumanoidRootPart")
        end
        return
    end

    local flatLook = getCameraFlatLookVector()
    if not flatLook then
        local reason = "camera_vertical"
        if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG and lastFacingSkippedReason ~= reason then
            lastFacingSkippedReason = reason
            Logger.debug("[MovementController] applyCharacterFacing: skipped — camera look near vertical")
        end
        return
    end

    -- All guards passed. Clear skip-reason so transitions are logged again if needed.
    if lastFacingSkippedReason ~= "" then
        lastFacingSkippedReason = ""
    end

    -- Rotate character to face camera yaw. Position is unchanged — this is a yaw-only
    -- CFrame replacement, not a teleport and not a velocity change.
    local pos = root.Position
    root.CFrame = CFrame.lookAt(pos, pos + flatLook)
end

-- ============================================================
-- Private helpers — Stage 2K: third-person camera zoom limits + mouse-lock camera
-- ============================================================

-- Caches the player's default camera zoom distances and humanoid CameraOffset on first call.
-- Idempotent — only writes each slot if it is still nil (does not overwrite on re-call).
-- Called at Start() (before any zoom overrides) and on CharacterAdded (to capture new humanoid offset).
-- Safe to call when humanoid is nil — skips the CameraOffset slot in that case.
local function cacheDefaultCameraSettings()
    local localPlayer = Players.LocalPlayer
    if defaultCameraMinZoomDistance == nil then
        defaultCameraMinZoomDistance = localPlayer.CameraMinZoomDistance
    end
    if defaultCameraMaxZoomDistance == nil then
        defaultCameraMaxZoomDistance = localPlayer.CameraMaxZoomDistance
    end
    if humanoid ~= nil and defaultCameraOffset == nil then
        defaultCameraOffset = humanoid.CameraOffset
    end
end

-- Sets Players.LocalPlayer zoom limits to the controlled third-person range.
-- Called on Start() and whenever custom mouse lock is disabled.
-- Does NOT write camera.CFrame, FieldOfView, or CameraType.
local function applyThirdPersonZoomLimits()
    local localPlayer = Players.LocalPlayer
    localPlayer.CameraMinZoomDistance = Constants.THIRD_PERSON_MIN_ZOOM_DISTANCE
    localPlayer.CameraMaxZoomDistance = Constants.THIRD_PERSON_MAX_ZOOM_DISTANCE
end

-- Applies the custom mouse-lock camera distance (locked zoom) and CameraOffset.
-- Called when custom mouse lock is enabled (from applyCustomMouseLock / SetCustomMouseLocked).
-- Immediately pins CameraMin = CameraMax = CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE so the
-- Roblox camera sits at exactly that distance (shift-lock / over-the-shoulder style).
-- Sets Humanoid.CameraOffset to provide the right-shoulder lateral offset.
-- Does NOT write camera.CFrame, FieldOfView, or CameraType.
-- Does NOT set CameraType to Scriptable.
local function applyCustomMouseLockCamera()
    if Constants.CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE then
        local localPlayer = Players.LocalPlayer
        localPlayer.CameraMinZoomDistance = Constants.CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE
        localPlayer.CameraMaxZoomDistance = Constants.CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE
    end
    if Constants.CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET then
        -- Fallback: if the module-level humanoid variable is nil (e.g. called before
        -- setupCharacter runs, or during MCP execute_luau tests), look it up directly
        -- from the character. Avoids silently skipping the CameraOffset write. (Stage 2K)
        local hum = humanoid
            or (Players.LocalPlayer.Character
                and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
        if hum then
            hum.CameraOffset = Constants.CUSTOM_MOUSE_LOCK_CAMERA_OFFSET
        end
    end
end

-- Restores zoom limits to the normal third-person range and clears CameraOffset.
-- Called when custom mouse lock is disabled, on CharacterAdded, and in destroy().
-- Does NOT restore to the original Roblox default zoom range (which is very wide).
-- Always restores to THIRD_PERSON_MIN/MAX_ZOOM_DISTANCE so the player stays in the
-- controlled range regardless of whether mouse lock was previously on.
-- Does NOT write camera.CFrame, FieldOfView, or CameraType.
local function restoreNormalThirdPersonCamera()
    local localPlayer = Players.LocalPlayer
    localPlayer.CameraMinZoomDistance = Constants.THIRD_PERSON_MIN_ZOOM_DISTANCE
    localPlayer.CameraMaxZoomDistance = Constants.THIRD_PERSON_MAX_ZOOM_DISTANCE
    -- Fallback: look up Humanoid directly when the module-level variable is nil. (Stage 2K)
    local hum = humanoid
        or (Players.LocalPlayer.Character
            and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
    if hum then
        hum.CameraOffset = Constants.CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET
    end
end

-- ============================================================
-- Private helpers — Stage 2D: custom mouse lock
-- ============================================================

-- Applies the current customMouseLocked state to UserInputService.MouseBehavior
-- and (Stage 2E) Humanoid.AutoRotate + initial character-facing rotation.
-- Called by SetCustomMouseLocked() and the ContextActionService toggle handler.
-- Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
-- Does NOT add camera rotation logic.
local function applyCustomMouseLock()
    if Constants.CUSTOM_MOUSE_LOCK_ENABLED ~= true then
        customMouseLocked              = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        -- Stage 2E: restore AutoRotate if it was disabled before the master switch was turned off.
        restoreCharacterAutoRotate()
        originalAutoRotate = nil
        -- Stage 2K: restore normal third-person camera when the master switch is turned off.
        restoreNormalThirdPersonCamera()
        return
    end

    if customMouseLocked then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        -- Stage 2K: apply closer shift-lock-style camera distance and shoulder offset.
        applyCustomMouseLockCamera()

        -- Stage 2E: disable AutoRotate once per lock session and apply initial facing.
        if Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW then
            local hum = humanoid
            if hum then
                -- Cache only the first time so toggling off/on re-uses the original value.
                if originalAutoRotate == nil then
                    originalAutoRotate = hum.AutoRotate
                end
                hum.AutoRotate = false
                if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG then
                    Logger.debug("[MovementController] AutoRotate disabled for character-facing (cached: " .. tostring(originalAutoRotate) .. ")")
                end
            end
            applyCharacterFacing()
        end
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        -- Stage 2K: restore normal third-person zoom range and clear CameraOffset.
        restoreNormalThirdPersonCamera()

        -- Stage 2E: restore AutoRotate when the lock is toggled off.
        if Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW then
            restoreCharacterAutoRotate()
            originalAutoRotate = nil
        end
    end
end

-- Attempts to disable the Roblox built-in Shift Lock for the local player by setting
-- LocalPlayer.DevEnableMouseLock = false. This is a client-side companion to the
-- StarterPlayer.EnableMouseLockOption = false project setting (default.project.json).
-- Using pcall because DevEnableMouseLock is only settable in LocalScripts and may fail
-- if the property is not available on this Roblox version.
-- Only acts when Constants.DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK == true.
local function disableRobloxDefaultMouseLock()
    if Constants.DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK ~= true then return end
    local localPlayer = Players.LocalPlayer
    local ok, err = pcall(function()
        localPlayer.DevEnableMouseLock = false
    end)
    if ok then
        if Constants.CUSTOM_MOUSE_LOCK_DEBUG then
            Logger.debug("[MovementController] Roblox default Shift Lock disabled for LocalPlayer")
        end
    else
        Logger.warn(
            "[MovementController] disableRobloxDefaultMouseLock: DevEnableMouseLock failed: "
            .. tostring(err)
        )
    end
end

-- ============================================================
-- Private helpers — Stage 2H + 2I: crouch transition (no deps — defined early)
-- ============================================================

-- Disconnects the active crouch transition Stopped callback and nils the reference.
-- Does NOT clear crouchTransitionPlaying — callers manage that flag explicitly after
-- calling this function, so the flag always reflects the caller's intent.
-- Must be called BEFORE any track:Stop() to prevent the Stopped callback from
-- firing spuriously when an external stop is requested.
-- Safe to call when no connection is active (no-op).
local function clearCrouchTransitionConnection()
    if crouchTransitionConn then
        crouchTransitionConn:Disconnect()
        crouchTransitionConn = nil
    end
end

-- Stage 2N: Disconnects the CrouchWalkStart Stopped callback and clears the playing flag.
-- Must be called BEFORE any track:Stop() on the CrouchWalkStart track — same pattern as
-- clearCrouchTransitionConnection() — to prevent spurious callbacks on external stops.
-- Safe to call when no CrouchWalkStart is active (no-op).
local function clearCrouchWalkStart()
    if crouchWalkStartConn then
        crouchWalkStartConn:Disconnect()
        crouchWalkStartConn = nil
    end
    crouchWalkStartPlaying = false
end

-- Stage 2O: Disconnects the LandingMedium Stopped callback and clears the playing flag.
-- Must be called BEFORE any track:Stop() on the LandingMedium track to prevent spurious
-- callbacks — mirrors the clearCrouchTransitionConnection() and clearCrouchWalkStart() patterns.
-- Safe to call when no landing one-shot is active (no-op).
local function clearLandingConnection()
    if landingConn then
        landingConn:Disconnect()
        landingConn = nil
    end
    isLandingPlaying = false
end

-- ============================================================
-- Private helpers — Stage 2A: animation
-- ============================================================

-- Disables the default Roblox Animate LocalScript so the avatar animation pack no
-- longer controls locomotion. Custom tracks from loadMovementAnimations() will then
-- play without being overridden.
--
-- Only acts when both CUSTOM_MOVEMENT_ANIMATIONS_ENABLED and
-- DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT are true.
-- Disables Animate; does NOT destroy it and does NOT touch any other scripts.
--
-- Side effect: disabling Animate also removes idle, jump, fall, and climb animations.
-- Custom replacements for those states are needed in a future movement stage.
local function disableDefaultAnimate(character: Model)
    assert(character ~= nil, "[MovementController] disableDefaultAnimate: character is required")

    if Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED ~= true then return end

    if Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT ~= true then
        -- Animate is left running. Custom tracks may be overridden or blend unexpectedly
        -- with avatar animation pack locomotion. Set
        -- DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = true to resolve conflicts.
        return
    end

    local animate = character:FindFirstChild("Animate")
    if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
        animate.Disabled = true
        Logger.debug("[MovementController] default Animate script disabled for: " .. character.Name)
    end
end

-- Returns true when all seven canonical R6 body parts are direct children of character.
-- Used as a structural fallback when Humanoid.RigType does not report R6.
-- Does NOT indicate that the Humanoid.RigType value is R6 — use isR6Character() for that.
local function hasR6BodyParts(character: Model): boolean
    assert(character ~= nil, "[MovementController] hasR6BodyParts: character is required")
    return character:FindFirstChild("HumanoidRootPart") ~= nil
        and character:FindFirstChild("Torso") ~= nil
        and character:FindFirstChild("Head") ~= nil
        and character:FindFirstChild("Left Arm") ~= nil
        and character:FindFirstChild("Right Arm") ~= nil
        and character:FindFirstChild("Left Leg") ~= nil
        and character:FindFirstChild("Right Leg") ~= nil
end

-- Returns a formatted diagnostic string showing the rig identity of a character.
-- Logged whenever R6 animations are skipped so the exact mismatch is visible in Output.
-- Checks for both R6 and R15 key parts so the log immediately shows which rig is present.
local function getRigDebugSummary(character: Model, hum: Humanoid): string
    assert(character ~= nil, "[MovementController] getRigDebugSummary: character is required")
    assert(hum ~= nil,       "[MovementController] getRigDebugSummary: humanoid is required")
    return string.format(
        "RigType=%s Torso=%s UpperTorso=%s LowerTorso=%s LeftArm=%s LeftUpperArm=%s Character=%s",
        hum.RigType.Name,
        tostring(character:FindFirstChild("Torso")       ~= nil),
        tostring(character:FindFirstChild("UpperTorso")  ~= nil),
        tostring(character:FindFirstChild("LowerTorso")  ~= nil),
        tostring(character:FindFirstChild("Left Arm")    ~= nil),
        tostring(character:FindFirstChild("LeftUpperArm") ~= nil),
        character.Name
    )
end

-- Primary R6 check: Humanoid.RigType == R6.
-- Structural fallback: if RigType does not report R6 but all seven R6 body parts are
-- present, treat the character as R6 and emit a one-time warning so the mismatch is
-- visible. This handles edge cases where CharacterRigType was set in StarterPlayer but
-- the Humanoid.RigType value did not propagate in the current Studio session.
-- rigTypeWarned must be reset to false before calling (loadMovementAnimations() does this).
local function isR6Character(character: Model, hum: Humanoid): boolean
    assert(character ~= nil, "[MovementController] isR6Character: character is required")
    assert(hum ~= nil,       "[MovementController] isR6Character: humanoid is required")

    if hum.RigType == Enum.HumanoidRigType.R6 then
        return true
    end

    -- RigType did not report R6. Try the structural fallback.
    if hasR6BodyParts(character) then
        if not rigTypeWarned then
            rigTypeWarned = true
            Logger.warn(
                "[MovementController] isR6Character: structural R6 body parts found but "
                .. "Humanoid.RigType is not R6 (RigType=" .. hum.RigType.Name
                .. "). Treating as R6 and loading custom animations. "
                .. "Verify StarterPlayer.CharacterRigType after rojo serve — see DEBT-049."
            )
        end
        return true
    end

    return false
end

-- Finds the Animator inside a character's Humanoid.
-- Returns nil and warns if not found; all callers skip animation and continue safely.
local function getAnimator(character: Model): Animator?
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then
        Logger.warn("[MovementController] getAnimator: no Humanoid in character")
        return nil
    end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        Logger.warn("[MovementController] getAnimator: no Animator in Humanoid")
        return nil
    end
    return animator
end

-- Returns the movement animation set name based on the current equippedWeaponName.
-- Defaults to Constants.MOVEMENT_ANIMATION_SET_UNARMED ("Unarmed") when no weapon
-- is equipped (equippedWeaponName == nil). Returns "AR15" only when equippedWeaponName
-- matches Constants.DEFAULT_WEAPON or Constants.MOVEMENT_ANIMATION_SET_AR15.
-- Falls back to "Unarmed" for any unknown weapon name; the caller-side warn was already
-- emitted in SetEquippedWeaponName so no additional per-frame warn fires here.
--
-- MAINTENANCE (DEBT-050 — partially resolved): equippedWeaponName is set by the
-- presentation-only SetEquippedWeaponName() method, not by server-owned loadout state.
-- True armed/unarmed state must eventually come from an EquipmentController or
-- server-owned equipment system. See DEBT-050.
local function getAnimationSetName(): string
    if equippedWeaponName == nil then
        return Constants.MOVEMENT_ANIMATION_SET_UNARMED
    end
    if equippedWeaponName == Constants.DEFAULT_WEAPON
        or equippedWeaponName == Constants.MOVEMENT_ANIMATION_SET_AR15 then
        return Constants.MOVEMENT_ANIMATION_SET_AR15
    end
    -- Unknown weapon name — fall back to Unarmed (warn already issued in SetEquippedWeaponName).
    return Constants.MOVEMENT_ANIMATION_SET_UNARMED
end

-- Returns true when strafe animations should be allowed for this frame.
-- Stage 2D primary path (CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY == true):
--   Returns customMouseLocked — the local boolean toggled by LeftAlt / SetCustomMouseLocked().
--   Does NOT read UserInputService.MouseBehavior as the gate (that was the Stage 2C approach).
-- Legacy path (CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY == false):
--   Falls back to reading UserInputService.MouseBehavior == LockCenter (Roblox native shift lock).
--   This path is deprecated; prefer the custom mouse lock system.
-- Does NOT toggle shift lock. Does NOT write camera.CFrame.
local function isMouseLockedForStrafeAnimations(): boolean
    if Constants.CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY then
        return customMouseLocked
    end
    -- Legacy: Roblox native MouseBehavior check (MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK path).
    return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

-- Returns the playback speed multiplier for the given short animation name.
-- animationName must be the short name portion (e.g. "WalkForward", not "Unarmed_WalkForward").
-- Used by playMovementAnimation() to call AnimationTrack:AdjustSpeed() on play.
-- Does not affect Humanoid.WalkSpeed or any movement speed constant.
-- Stage 2J: any name beginning with "CrouchWalk" → MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER.
local function getAnimationSpeedMultiplier(animationName: string): number
    assert(animationName ~= nil, "[MovementController] getAnimationSpeedMultiplier: animationName is required")
    if animationName == "WalkForward"
        or animationName == "WalkForwardAlt"   -- Stage 2M: alternate forward walk (loaded but not yet selected)
        or animationName == "WalkBackward"
        or animationName == "WalkBackwardLeft"
        or animationName == "WalkBackwardRight"
        or animationName == "WalkForwardLeft"
        or animationName == "WalkForwardRight"
    then
        return Constants.MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "WalkLeft" or animationName == "WalkRight" then
        return Constants.MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "RunForward"
        or animationName == "RunForwardLeft"
        or animationName == "RunForwardRight"
    then
        return Constants.MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "Idle" then
        return Constants.MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "EnterCrouch" or animationName == "ExitCrouch" then
        return Constants.MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER
    elseif animationName:sub(1, 10) == "CrouchWalk"
        or animationName == "CrouchIdle"
        or animationName == "CrouchIdleAlt"
    then
        -- Covers CrouchWalk, CrouchWalkForward, CrouchWalkBackward, CrouchWalkLeft/Right,
        -- CrouchWalkForwardLeft/Right, CrouchWalkBackwardLeft/Right (Stage 2J),
        -- CrouchIdle, CrouchIdleAlt (Stage 2N).
        return Constants.MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "Falling" then
        -- Stage 2O: looped falling clip played while Humanoid is in Freefall.
        return Constants.MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "LandingMedium" then
        -- Stage 2O: one-shot landing clip played after landing from sufficient height.
        return Constants.MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER
    end
    return 1.0
end

-- Stops the currently playing movement animation with a fade-out.
-- Safe to call when nothing is playing (currentAnimationName == "").
local function stopCurrentMovementAnimation()
    if currentAnimationName == "" then return end
    local track = animationTracks[currentAnimationName]
    if track then
        track:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
    end
    currentAnimationName = ""
end

-- Plays the named animation track (key format: "SetName_AnimName", e.g. "Unarmed_WalkForward").
-- Fades in over MOVEMENT_ANIMATION_FADE_TIME. Applies a playback speed multiplier via
-- AdjustSpeed using getAnimationSpeedMultiplier on the short animation name.
-- If the same track is already playing, AdjustSpeed is still called (no restart).
-- Logs the switch (with speed multiplier) if MOVEMENT_ANIMATION_DEBUG is true.
-- Warns and clears currentAnimationName if the requested key is absent.
local function playMovementAnimation(animationName: string)
    -- Extract the short name from the full key ("Unarmed_WalkForward" → "WalkForward").
    local animShortName = animationName:match("_(.+)$") or animationName
    local speedMult = getAnimationSpeedMultiplier(animShortName)

    if currentAnimationName == animationName then
        -- Same track already playing. Ensure speed is correct without restarting.
        local track = animationTracks[animationName]
        if track then
            track:AdjustSpeed(speedMult)
        end
        return
    end

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] anim switch: ["
            .. (currentAnimationName == "" and "none" or currentAnimationName)
            .. "] → [" .. animationName .. "] ×" .. speedMult
        )
    end

    -- Fade out the previous animation.
    if currentAnimationName ~= "" then
        local prevTrack = animationTracks[currentAnimationName]
        if prevTrack then
            prevTrack:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
        end
    end

    local track = animationTracks[animationName]
    if not track then
        Logger.warn("[MovementController] playMovementAnimation: track not loaded: " .. animationName)
        currentAnimationName = ""
        return
    end

    track:Play(Constants.MOVEMENT_ANIMATION_FADE_TIME)
    track:AdjustSpeed(speedMult)
    currentAnimationName = animationName
end

-- ============================================================
-- Private helpers — Stage 2I: crouch bottom-hold
-- ============================================================

-- Holds the character at the final pose of the EnterCrouch clip by:
--   1. Ensuring the track is playing (calls Play(0) if not already playing).
--   2. Setting TimePosition to near the clip's end so only the final frame is visible.
--   3. Calling AdjustSpeed(0) to freeze the clip in place.
-- Gated by Constants.CROUCH_HOLD_BOTTOM_POSE_ENABLED and movementState.isCrouching.
-- Emits a one-time Logger.warn if the EnterCrouch track is absent.
-- Does NOT change Humanoid.HipHeight, CameraOffset, or WalkSpeed.
-- Must be defined after getAnimationSetName.
local function holdCrouchBottomPose()
    if Constants.CROUCH_HOLD_BOTTOM_POSE_ENABLED ~= true then return end
    if not movementState.isCrouching then return end

    local setName = getAnimationSetName()
    local key     = setName .. "_EnterCrouch"
    local track   = animationTracks[key]

    if not track then
        if not crouchBottomPoseWarned then
            crouchBottomPoseWarned = true
            Logger.warn(
                "[MovementController] holdCrouchBottomPose: EnterCrouch track not loaded "
                .. "for set '" .. setName .. "' — crouch bottom-pose hold unavailable"
            )
        end
        return
    end

    -- Guard: already holding this exact track — nothing to do.
    if crouchHoldTrack == track and isHoldingCrouchBottomPose then return end

    crouchHoldTrack          = track
    isHoldingCrouchBottomPose = true

    -- Ensure the track is playing so TimePosition can be set.
    -- Play(0) = zero fade time to avoid a visible jump from frame 0.
    if not track.IsPlaying then
        track:Play(0)
    end

    -- Seek to the near-final frame and freeze.
    local holdPos: number
    if track.Length > 0 then
        holdPos = math.max(track.Length - Constants.CROUCH_TRANSITION_MIN_HOLD_TIME, 0)
    else
        holdPos = Constants.CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK
    end
    track.TimePosition = holdPos
    track:AdjustSpeed(0)

    -- currentAnimationName is intentionally left "" here — the hold track is managed
    -- by crouchHoldTrack, not by the playMovementAnimation / stopCurrentMovementAnimation
    -- system. This prevents normal animation selection from accidentally stopping it.

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] crouch bottom-hold BEGIN: " .. key
            .. " @ " .. string.format("%.3f", holdPos) .. "s (speed=0)"
        )
    end
end

-- Releases the active crouch bottom-hold by restoring playback speed and stopping
-- the held track with a short fade. Safe to call when no hold is active (no-op).
-- Does NOT stop unrelated locomotion tracks.
local function clearCrouchBottomHold()
    local track = crouchHoldTrack
    if track then
        -- Restore normal playback speed before Stop so the fade-out is audible/visible.
        track:AdjustSpeed(Constants.MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER)
        track:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
    end
    crouchHoldTrack          = nil
    isHoldingCrouchBottomPose = false

    if Constants.MOVEMENT_ANIMATION_DEBUG and track ~= nil then
        Logger.debug("[MovementController] crouch bottom-hold END")
    end
end

-- Plays the one-shot EnterCrouch (entering == true) or ExitCrouch (entering == false)
-- transition animation for the current weapon set.
-- • Calls clearCrouchTransitionConnection() first — disconnects any previous Stopped
--   callback before stopping tracks to prevent spurious callbacks.
-- • Fades out any current locomotion/idle track via stopCurrentMovementAnimation.
-- • Sets crouchTransitionPlaying = true so updateMovementAnimation skips interrupting
--   the one-shot clip while it is running.
-- • EnterCrouch Stopped: if still crouching, calls holdCrouchBottomPose() (or plays
--   CrouchWalk if available and moving). ExitCrouch Stopped: resumes normal selection.
-- • Falls back silently if the track for this set is not loaded.
-- Does NOT change Humanoid.WalkSpeed, HipHeight, or CameraOffset.
-- Must be defined after playMovementAnimation, holdCrouchBottomPose, clearCrouchBottomHold,
-- and getAnimationSetName.
local function playCrouchTransition(entering: boolean)
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end
    if next(animationTracks) == nil then return end

    local setName    = getAnimationSetName()
    local animSuffix = if entering then "EnterCrouch" else "ExitCrouch"
    local key        = setName .. "_" .. animSuffix

    local track = animationTracks[key]
    if not track then
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] playCrouchTransition: no track for " .. key .. " (skipping)")
        end
        return
    end

    -- Disconnect previous Stopped callback BEFORE stopping any tracks.
    clearCrouchTransitionConnection()
    -- Fade out any currently playing locomotion, idle, or hold track.
    -- clearCrouchBottomHold stops the hold track first (if active).
    clearCrouchBottomHold()
    stopCurrentMovementAnimation()

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] crouch transition: "
            .. (entering and "ENTER" or "EXIT") .. " → " .. key
        )
    end

    -- Mark transition active BEFORE Play() so the next Heartbeat tick is gated.
    crouchTransitionPlaying = true
    -- Track via currentAnimationName so stopCurrentMovementAnimation() can externally
    -- stop this clip during phase exit or destroy (before the Stopped callback fires).
    currentAnimationName = key
    track:Play(Constants.MOVEMENT_ANIMATION_FADE_TIME)
    track:AdjustSpeed(getAnimationSpeedMultiplier(animSuffix))

    crouchTransitionConn = track.Stopped:Connect(function()
        -- Disconnect self first to guard against re-entry on external Stop.
        clearCrouchTransitionConnection()
        crouchTransitionPlaying = false
        if currentAnimationName == key then
            currentAnimationName = ""
        end

        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] crouch transition finished: " .. key)
        end

        if entering then
            -- EnterCrouch finished. If still crouching, establish the visual pose.
            if movementState.isCrouching then
                if movementState.isMoving then
                    -- Stage 2N: mark that we are already moving when EnterCrouch finishes.
                    -- This prevents CrouchWalkStart from playing on the next Heartbeat — the
                    -- player was already in motion so the start-of-movement transition is moot.
                    wasMovingWhileCrouching = true
                    -- Start a suitable crouch-walk immediately to avoid a blank frame.
                    -- updateMovementAnimation() refines the direction on the next Heartbeat.
                    -- Priority: CrouchWalkForward (canonical forward) → CrouchWalk alias → hold pose.
                    local setName2  = getAnimationSetName()
                    local fwdKey    = setName2 .. "_CrouchWalkForward"
                    local aliasKey  = setName2 .. "_CrouchWalk"
                    if animationTracks[fwdKey] ~= nil then
                        playMovementAnimation(fwdKey)
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug(
                                "[MovementController] crouch: EnterCrouch done → " .. fwdKey
                                .. " (direction refined next Heartbeat)"
                            )
                        end
                    elseif animationTracks[aliasKey] ~= nil then
                        playMovementAnimation(aliasKey)
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug("[MovementController] crouch: EnterCrouch done → " .. aliasKey)
                        end
                    else
                        holdCrouchBottomPose()
                    end
                else
                    holdCrouchBottomPose()
                end
            end
            -- If isCrouching == false here: C was released during the transition;
            -- ExitCrouch is already playing. Do nothing.
        end
        -- ExitCrouch finished: normal updateMovementAnimation resumes next Heartbeat.
    end)
end

-- Clears old animation state and loads all R6 movement AnimationTracks for the character.
-- Called from setupCharacter() on every spawn/respawn.
-- Skipped entirely if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is false.
-- Rig detection: isR6Character() is checked first (RigType primary, structural fallback).
--   If the character is confirmed R6, disableDefaultAnimate() is called here before tracks load.
--   If the character is not R6, getRigDebugSummary() is logged and the function returns early.
-- Old AnimationTrack references are cleared (previous Animator may already be destroyed).
-- Old Animation instances are explicitly destroyed before new ones are created.
local function loadMovementAnimations(character: Model)
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end

    -- Stage 2H + 2I: disconnect transition callback before clearing track references.
    -- Must be called before table.clear so the Stopped callback cannot fire for a
    -- track that no longer exists in the new table.
    clearCrouchTransitionConnection()
    crouchTransitionPlaying = false
    -- Stage 2N: disconnect CrouchWalkStart callback and clear its state (same reason).
    clearCrouchWalkStart()
    wasMovingWhileCrouching = false
    -- Stage 2O: disconnect StateChanged and clear falling/landing state on respawn.
    -- stateChangedConn is NOT in _connections (per-character only); disconnect here and in destroy().
    if stateChangedConn then
        stateChangedConn:Disconnect()
        stateChangedConn = nil
    end
    isFalling    = false
    airStartTime = 0
    clearLandingConnection()
    -- Do NOT call clearCrouchBottomHold() here — the previous Animator may already be
    -- destroyed, making the hold track reference unsafe to Stop(). Clear state directly.
    crouchHoldTrack          = nil
    isHoldingCrouchBottomPose = false
    crouchBottomPoseWarned   = false

    -- Clear stale track references. Do NOT :Stop() them — the previous Animator may
    -- already be destroyed, making those references unsafe to call.
    table.clear(animationTracks)
    currentAnimationName = ""
    rigTypeWarned        = false
    -- Reset set-change log guard so the first movement after respawn re-logs the active set.
    lastAnimationSet       = ""
    -- Reset strafe-blocked log guard so the first movement after respawn re-logs the state.
    lastStrafeBlockedState = false
    -- Reset custom mouse lock on respawn: release the cursor so the player is not stuck
    -- with a locked mouse if they die or respawn while mouse lock was active.
    customMouseLocked                    = false
    UserInputService.MouseBehavior       = Enum.MouseBehavior.Default
    -- Stage 2E: clear the cached AutoRotate value so the next lock session caches fresh.
    -- The Humanoid itself is also new on respawn so there is nothing to restore here.
    originalAutoRotate                   = nil

    -- Destroy and clear old Animation instances from the previous character.
    for _, inst in pairs(animationInstances) do
        inst:Destroy()
    end
    table.clear(animationInstances)

    -- Rig detection: use isR6Character() which checks RigType first and falls back to
    -- structural body-part inspection. rigTypeWarned was reset above so mismatch warnings
    -- are not suppressed for this character.
    local hum = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not hum then
        Logger.warn("[MovementController] loadMovementAnimations: no Humanoid — skipping")
        return
    end
    if not isR6Character(character, hum) then
        Logger.warn(
            "[MovementController] Custom R6 animations skipped. "
            .. getRigDebugSummary(character, hum)
        )
        return
    end

    -- Character confirmed R6 — disable Animate before loading custom tracks.
    -- Order matters: Animate must be disabled first so the avatar animation pack cannot
    -- override custom tracks. Only called here (not in setupCharacter) so Animate is
    -- left running on non-R6 characters.
    disableDefaultAnimate(character)

    local animator = getAnimator(character)
    if not animator then return end

    -- Build the flat "SetName_AnimName" → AnimationTrack table.
    -- Both Unarmed and AR15 tracks are loaded at spawn so switching sets is instant
    -- (no reload needed when SetEquippedWeaponName is called mid-session).
    local r6 = Constants.MOVEMENT_ANIMATION_IDS.R6
    local toLoad: { [string]: string } = {
        -- Unarmed (default / no-gun) set
        ["Unarmed_WalkForward"]       = r6.Unarmed.WalkForward,
        ["Unarmed_RunForward"]        = r6.Unarmed.RunForward,
        ["Unarmed_WalkLeft"]          = r6.Unarmed.WalkLeft,          -- no-gun strafe left
        ["Unarmed_WalkRight"]         = r6.Unarmed.WalkRight,         -- no-gun strafe right
        ["Unarmed_WalkBackward"]      = r6.Unarmed.WalkBackward,      -- no-gun backward (Stage 2F)
        ["Unarmed_WalkBackwardLeft"]  = r6.Unarmed.WalkBackwardLeft,  -- no-gun backward-left diagonal (Stage 2F)
        ["Unarmed_WalkBackwardRight"] = r6.Unarmed.WalkBackwardRight, -- no-gun backward-right diagonal (Stage 2F)
        ["Unarmed_WalkForwardLeft"]   = r6.Unarmed.WalkForwardLeft,   -- no-gun walk forward-left diagonal (Stage 2F)
        ["Unarmed_WalkForwardRight"]  = r6.Unarmed.WalkForwardRight,  -- no-gun walk forward-right diagonal (Stage 2F)
        ["Unarmed_RunForwardLeft"]    = r6.Unarmed.RunForwardLeft,    -- no-gun run forward-left diagonal (Stage 2G — deferred)
        ["Unarmed_RunForwardRight"]   = r6.Unarmed.RunForwardRight,   -- no-gun run forward-right diagonal (Stage 2G — deferred)
        ["Unarmed_Idle"]              = r6.Unarmed.Idle,              -- no-gun standing idle (Stage 2H)
        ["Unarmed_EnterCrouch"]       = r6.Unarmed.EnterCrouch,       -- no-gun enter-crouch one-shot (Stage 2H)
        ["Unarmed_ExitCrouch"]        = r6.Unarmed.ExitCrouch,        -- no-gun exit-crouch one-shot (Stage 2H)
        -- AR15 set — only plays when SetEquippedWeaponName("AR15") is called
        ["AR15_WalkForward"]          = r6.AR15.WalkForward,
        ["AR15_RunForward"]           = r6.AR15.RunForward,
        ["AR15_Idle"]                 = r6.AR15.Idle,                 -- AR15 standing idle (Stage 2H)
        ["AR15_EnterCrouch"]          = r6.AR15.EnterCrouch,          -- AR15 enter-crouch one-shot (Stage 2H)
        ["AR15_ExitCrouch"]           = r6.AR15.ExitCrouch,           -- AR15 exit-crouch one-shot (Stage 2H)
    }

    -- WalkForwardAlt is an optional alternate forward walk clip (Stage 2M).
    -- Loaded if the ID exists in Constants; not selected yet — no variation system built.
    -- When a safe alternation system is added later, select between Unarmed_WalkForward
    -- and Unarmed_WalkForwardAlt without touching any other logic paths.
    if r6.Unarmed.WalkForwardAlt and r6.Unarmed.WalkForwardAlt ~= "" then
        toLoad["Unarmed_WalkForwardAlt"] = r6.Unarmed.WalkForwardAlt
    end

    -- Stage 2N: CrouchIdle (looped idle while crouched+still) — preferred over the
    -- EnterCrouch bottom-pose hold when the player is crouched and not moving.
    -- Falls back to holdCrouchBottomPose() if this track is absent.
    if r6.Unarmed.CrouchIdle and r6.Unarmed.CrouchIdle ~= "" then
        toLoad["Unarmed_CrouchIdle"] = r6.Unarmed.CrouchIdle
    end

    -- Stage 2N: CrouchIdleAlt — deferred alternate crouch-idle clip.
    -- Loaded but never selected until a safe alternation system is built.
    if r6.Unarmed.CrouchIdleAlt and r6.Unarmed.CrouchIdleAlt ~= "" then
        toLoad["Unarmed_CrouchIdleAlt"] = r6.Unarmed.CrouchIdleAlt
    end

    -- Stage 2N: CrouchWalkStart — one-shot transition from crouched-idle to crouched-walk.
    -- Plays exactly once when movement begins while crouched; cleared by Stopped callback.
    if r6.Unarmed.CrouchWalkStart and r6.Unarmed.CrouchWalkStart ~= "" then
        toLoad["Unarmed_CrouchWalkStart"] = r6.Unarmed.CrouchWalkStart
    end

    -- Stage 2O: Falling — looped clip played while Humanoid is in Freefall.
    -- Only loaded for Unarmed set. AR15 set has no Falling ID; the animationTracks[key] ~= nil
    -- guard in onHumanoidStateChanged skips the animation cleanly when the key is absent.
    if r6.Unarmed.Falling and r6.Unarmed.Falling ~= "" then
        toLoad["Unarmed_Falling"] = r6.Unarmed.Falling
    end

    -- Stage 2O: LandingMedium — one-shot clip played on landing after MIN_AIR_TIME seconds.
    -- Only loaded for Unarmed set (same AR15 guard applies — see above).
    if r6.Unarmed.LandingMedium and r6.Unarmed.LandingMedium ~= "" then
        toLoad["Unarmed_LandingMedium"] = r6.Unarmed.LandingMedium
    end

    -- CrouchWalk tracks are optional. Only loaded if IDs exist in Constants.
    -- Stage 2J: nine Unarmed directional CrouchWalk* IDs added. All looped.
    -- CrouchWalk and CrouchWalkForward share the same asset ID (forward is the canonical fallback).
    -- AR15: no CrouchWalk IDs in Stage 2J — added conditionally if populated in a future stage.
    local unarmedCrouchWalkNames: { string } = {
        "CrouchWalk",
        "CrouchWalkForward",
        "CrouchWalkBackward",
        "CrouchWalkLeft",
        "CrouchWalkRight",
        "CrouchWalkForwardLeft",
        "CrouchWalkForwardRight",
        "CrouchWalkBackwardLeft",
        "CrouchWalkBackwardRight",
    }
    for _, cwName in ipairs(unarmedCrouchWalkNames) do
        local assetId: string? = (r6.Unarmed :: any)[cwName]
        if assetId ~= nil and assetId ~= "" then
            toLoad["Unarmed_" .. cwName] = assetId
        end
    end
    if r6.AR15.CrouchWalk then
        toLoad["AR15_CrouchWalk"] = r6.AR15.CrouchWalk
    end

    for key, assetId in pairs(toLoad) do
        if assetId == nil or assetId == "" then
            -- Warn for missing or empty asset IDs — these may indicate an unloaded
            -- constant, a private asset, or a placeholder not yet replaced.
            Logger.warn("[MovementController] loadMovementAnimations: empty assetId for key: " .. key)
        else
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug("[MovementController] loading anim [" .. key .. "] = " .. assetId)
            end
            local animInstance       = Instance.new("Animation")
            animInstance.AnimationId = assetId
            animationInstances[key]  = animInstance
            local track              = animator:LoadAnimation(animInstance)
            -- One-shot clips play once and stop; all others loop.
            -- Stage 2O: LandingMedium added to the one-shot list.
            if key:match("_EnterCrouch$") or key:match("_ExitCrouch$")
                or key:match("_CrouchWalkStart$") or key:match("_LandingMedium$")
            then
                track.Looped = false
            else
                track.Looped = true
            end
            animationTracks[key]     = track
        end
    end

    Logger.debug("[MovementController] R6 movement animations loaded for: " .. character.Name)
end

-- Selects and triggers the correct movement animation for the current movementState.
-- Called every Heartbeat tick during ACTIVE phase.
-- Skipped if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is false.
-- currentAnimationName guard inside playMovementAnimation prevents track restarts.
--
-- Stage 2A + 2C + 2F + 2G + 2H + 2I + 2J + 2L scope:
--   WalkLeft/WalkRight only play when canUseStrafeAnimations is true (mouse lock active).
--   WalkBackward plays for Backward regardless of mouse-lock state (Unarmed set only).
--   WalkForwardLeft/Right and WalkBackwardLeft/Right play for diagonals regardless of mouse lock (Unarmed only).
--   Sprint (any direction, any set, mouse lock on or off): always plays RunForward. (Stage 2L)
--   RunForwardLeft/RunForwardRight IDs exist in Constants but are not selected here. (Stage 2L)
--   Not moving (standing): plays Idle (looped) when the track is loaded; stops otherwise.
--   Skips entirely while crouchTransitionPlaying is true (transition clips run uninterrupted).
--   Stage 2I+2J crouch branch (returns early before standing/sprint logic):
--     isCrouching + not moving → hold/establish crouch bottom pose; stop any CrouchWalk* if playing.
--     isCrouching + moving + Unarmed:
--       customMouseLocked OFF → CrouchWalkForward (fallback) or CrouchWalk or hold bottom pose.
--       customMouseLocked ON  → per-direction selection (8 directions, mirrors walk selection).
--     isCrouching + moving + non-Unarmed set → generic <Set>_CrouchWalk or hold bottom pose.
--     All CrouchWalk* tracks play at MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER (1.0×).
local function updateMovementAnimation()
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end
    if next(animationTracks) == nil then return end

    -- Do not interrupt a one-shot crouch transition clip.
    if crouchTransitionPlaying then return end
    -- Stage 2O: do not interrupt Falling looped or LandingMedium one-shot.
    if isFalling then return end
    if isLandingPlaying then return end

    local setName = getAnimationSetName()   -- "Unarmed" (default) or "AR15" (when weapon equipped)

    -- ── Crouching branch (Stage 2I + 2J) ─────────────────────────────────────
    if movementState.isCrouching then
        if movementState.isMoving then
            -- ── Stage 2N: CrouchWalkStart one-shot on first movement ──────
            -- wasMovingWhileCrouching is false only at the exact transition from still to moving
            -- while crouched. If the player was already moving when EnterCrouch finished, the
            -- EnterCrouch Stopped callback sets it true to skip this block.
            if not wasMovingWhileCrouching then
                wasMovingWhileCrouching = true
                local startKey = setName .. "_CrouchWalkStart"
                if animationTracks[startKey] ~= nil and not crouchWalkStartPlaying then
                    -- Disconnect callback BEFORE stopping CrouchIdle to prevent spurious events.
                    clearCrouchWalkStart()
                    if isHoldingCrouchBottomPose then
                        clearCrouchBottomHold()
                    end
                    stopCurrentMovementAnimation()  -- stops CrouchIdle if playing
                    crouchWalkStartPlaying = true
                    playMovementAnimation(startKey)
                    local startTrack = animationTracks[startKey]
                    if startTrack then
                        crouchWalkStartConn = startTrack.Stopped:Connect(function()
                            clearCrouchWalkStart()
                        end)
                    end
                    return  -- Let the one-shot run; directional selection resumes next Heartbeat.
                end
            end

            -- Skip directional selection while the CrouchWalkStart one-shot is still running.
            if crouchWalkStartPlaying then return end

            -- ── Determine target crouch-walk animation key ────────────────
            local targetCrouchKey: string? = nil

            if setName == Constants.MOVEMENT_ANIMATION_SET_UNARMED then
                if customMouseLocked then
                    -- Mouse lock ON: full 8-directional selection (Stage 2J).
                    local dir = movementState.directionName
                    if dir == "Forward" then
                        -- Forward: CrouchWalkForward → CrouchWalk → nil.
                        local k = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "Backward" then
                        -- Backward: CrouchWalkBackward → CrouchWalkForward → CrouchWalk → nil.
                        local k = "Unarmed_CrouchWalkBackward"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "Left" then
                        -- Left strafe: CrouchWalkLeft → CrouchWalkForward → CrouchWalk → nil.
                        local k = "Unarmed_CrouchWalkLeft"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "Right" then
                        -- Right strafe: CrouchWalkRight → CrouchWalkForward → CrouchWalk → nil.
                        local k = "Unarmed_CrouchWalkRight"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "ForwardLeft" then
                        -- Forward-left diagonal: CrouchWalkForwardLeft → CrouchWalkLeft → CrouchWalkForward → CrouchWalk → nil.
                        local k   = "Unarmed_CrouchWalkForwardLeft"
                        local l   = "Unarmed_CrouchWalkLeft"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[l] ~= nil then
                            targetCrouchKey = l
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "ForwardRight" then
                        -- Forward-right diagonal: CrouchWalkForwardRight → CrouchWalkRight → CrouchWalkForward → CrouchWalk → nil.
                        local k   = "Unarmed_CrouchWalkForwardRight"
                        local r   = "Unarmed_CrouchWalkRight"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[r] ~= nil then
                            targetCrouchKey = r
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "BackwardLeft" then
                        -- Backward-left diagonal: CrouchWalkBackwardLeft → CrouchWalkLeft → CrouchWalkBackward → CrouchWalkForward → CrouchWalk → nil.
                        local k   = "Unarmed_CrouchWalkBackwardLeft"
                        local l   = "Unarmed_CrouchWalkLeft"
                        local bwd = "Unarmed_CrouchWalkBackward"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[l] ~= nil then
                            targetCrouchKey = l
                        elseif animationTracks[bwd] ~= nil then
                            targetCrouchKey = bwd
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    elseif dir == "BackwardRight" then
                        -- Backward-right diagonal: CrouchWalkBackwardRight → CrouchWalkRight → CrouchWalkBackward → CrouchWalkForward → CrouchWalk → nil.
                        local k   = "Unarmed_CrouchWalkBackwardRight"
                        local r   = "Unarmed_CrouchWalkRight"
                        local bwd = "Unarmed_CrouchWalkBackward"
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[k] ~= nil then
                            targetCrouchKey = k
                        elseif animationTracks[r] ~= nil then
                            targetCrouchKey = r
                        elseif animationTracks[bwd] ~= nil then
                            targetCrouchKey = bwd
                        elseif animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end

                    else
                        -- "Idle" or unclassified while isCrouching+isMoving — use forward fallback.
                        local fwd = "Unarmed_CrouchWalkForward"
                        if animationTracks[fwd] ~= nil then
                            targetCrouchKey = fwd
                        elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                            targetCrouchKey = "Unarmed_CrouchWalk"
                        end
                    end

                else
                    -- Mouse lock OFF: CrouchWalkForward fallback only (no directional strafe).
                    local fwd = "Unarmed_CrouchWalkForward"
                    if animationTracks[fwd] ~= nil then
                        targetCrouchKey = fwd
                    elseif animationTracks["Unarmed_CrouchWalk"] ~= nil then
                        targetCrouchKey = "Unarmed_CrouchWalk"
                    end
                end

            else
                -- Non-Unarmed set (e.g. AR15): generic CrouchWalk only if the ID exists.
                local k = setName .. "_CrouchWalk"
                if animationTracks[k] ~= nil then
                    targetCrouchKey = k
                end
            end

            -- ── Play or hold based on resolution ─────────────────────────
            if targetCrouchKey ~= nil then
                -- A crouch-walk track was resolved: release the bottom-hold and play it.
                if isHoldingCrouchBottomPose then
                    clearCrouchBottomHold()
                end
                playMovementAnimation(targetCrouchKey)
            else
                -- No crouch-walk available for this set/direction: hold the bottom pose.
                -- Ensure no standing locomotion track is playing.
                stopCurrentMovementAnimation()
                if not isHoldingCrouchBottomPose then
                    holdCrouchBottomPose()
                end
            end

        else
            -- ── Stage 2N: Crouching and not moving ───────────────────────
            -- Reset movement tracking so the next movement burst plays CrouchWalkStart.
            wasMovingWhileCrouching = false
            -- Disconnect CrouchWalkStart callback BEFORE stopping any track (prevents spurious callbacks).
            if crouchWalkStartPlaying then
                clearCrouchWalkStart()
            end
            -- Stop any CrouchWalk* animation that was playing (string pattern check).
            if currentAnimationName ~= "" and currentAnimationName:find("_CrouchWalk") then
                stopCurrentMovementAnimation()
            end
            -- Prefer CrouchIdle (looped) over holding the EnterCrouch bottom pose (Stage 2N).
            -- Fall back to holdCrouchBottomPose() when the track is absent.
            local crouchIdleKey = setName .. "_CrouchIdle"
            if animationTracks[crouchIdleKey] ~= nil then
                -- CrouchIdle track exists. Release the bottom-hold if active, then play idle.
                if isHoldingCrouchBottomPose then
                    clearCrouchBottomHold()
                end
                -- playMovementAnimation guard prevents restart if CrouchIdle is already playing.
                playMovementAnimation(crouchIdleKey)
            else
                -- No CrouchIdle for this set — fall back to the EnterCrouch bottom-pose hold.
                if not isHoldingCrouchBottomPose then
                    holdCrouchBottomPose()
                end
            end
        end
        return  -- Never fall through to standing/sprint branch while crouching.
    end

    -- ── Standing branch — not crouching ───────────────────────────────────────

    -- Not moving: play idle if the track is loaded, otherwise stop.
    if not movementState.isMoving then
        local idleKey = setName .. "_Idle"
        if animationTracks[idleKey] ~= nil then
            playMovementAnimation(idleKey)
        else
            stopCurrentMovementAnimation()
        end
        return
    end

    -- Debug: log once when the active animation set changes (not every Heartbeat frame).
    if Constants.MOVEMENT_ANIMATION_DEBUG and setName ~= lastAnimationSet then
        Logger.debug("[MovementController] animation set: " .. setName)
        lastAnimationSet = setName
    end

    -- Determine whether strafe animations are allowed for this frame.
    -- When MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK is true, strafe only plays in
    -- mouse-lock / shift-lock style state (UserInputService.MouseBehavior == LockCenter).
    local canUseStrafeAnimations: boolean
    if Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK then
        canUseStrafeAnimations = isMouseLockedForStrafeAnimations()
    else
        canUseStrafeAnimations = true
    end

    -- Debug: log once when the strafe-blocked state changes (not every Heartbeat frame).
    if Constants.MOVEMENT_ANIMATION_DEBUG then
        local strafeBlocked = not canUseStrafeAnimations
        if strafeBlocked ~= lastStrafeBlockedState then
            lastStrafeBlockedState = strafeBlocked
            if strafeBlocked then
                Logger.debug("[MovementController] strafe animations blocked: custom mouse lock not active (press LeftControl to enable)")
            else
                Logger.debug("[MovementController] strafe animations enabled: custom mouse lock active")
            end
        end
    end

    local dirName = movementState.directionName
    local animName: string

    if movementState.isSprinting then
        -- Sprint: always use RunForward for the current animation set, regardless of direction
        -- or customMouseLocked state. RunForwardLeft/RunForwardRight IDs are deferred. (Stage 2L)
        animName = setName .. "_RunForward"

    elseif setName == Constants.MOVEMENT_ANIMATION_SET_UNARMED then
        -- Unarmed set: full per-direction selection (Stage 2F).
        -- WalkBackward plays for Backward regardless of mouse-lock state.
        -- WalkForwardLeft/Right and WalkBackwardLeft/Right play for diagonals regardless of mouse-lock.
        -- Pure Left/Right strafe (WalkLeft/WalkRight) still require canUseStrafeAnimations.
        if dirName == "Backward" then
            local key = "Unarmed_WalkBackward"
            animName = if animationTracks[key] ~= nil then key else "Unarmed_WalkForward"

        elseif dirName == "ForwardLeft" then
            local fwdLeft = "Unarmed_WalkForwardLeft"
            local left    = "Unarmed_WalkLeft"
            if animationTracks[fwdLeft] ~= nil then
                animName = fwdLeft
            elseif canUseStrafeAnimations and animationTracks[left] ~= nil then
                animName = left
            else
                animName = "Unarmed_WalkForward"
            end

        elseif dirName == "ForwardRight" then
            local fwdRight = "Unarmed_WalkForwardRight"
            local right    = "Unarmed_WalkRight"
            if animationTracks[fwdRight] ~= nil then
                animName = fwdRight
            elseif canUseStrafeAnimations and animationTracks[right] ~= nil then
                animName = right
            else
                animName = "Unarmed_WalkForward"
            end

        elseif dirName == "BackwardLeft" then
            local bwdLeft = "Unarmed_WalkBackwardLeft"
            local bwd     = "Unarmed_WalkBackward"
            if animationTracks[bwdLeft] ~= nil then
                animName = bwdLeft
            elseif animationTracks[bwd] ~= nil then
                animName = bwd
            else
                animName = "Unarmed_WalkForward"
            end

        elseif dirName == "BackwardRight" then
            local bwdRight = "Unarmed_WalkBackwardRight"
            local bwd      = "Unarmed_WalkBackward"
            if animationTracks[bwdRight] ~= nil then
                animName = bwdRight
            elseif animationTracks[bwd] ~= nil then
                animName = bwd
            else
                animName = "Unarmed_WalkForward"
            end

        elseif canUseStrafeAnimations then
            -- Left, Right, or Forward with mouse lock active.
            if dirName == "Left" then
                local leftKey = "Unarmed_WalkLeft"
                animName = if animationTracks[leftKey] ~= nil then leftKey else "Unarmed_WalkForward"
            elseif dirName == "Right" then
                local rightKey = "Unarmed_WalkRight"
                animName = if animationTracks[rightKey] ~= nil then rightKey else "Unarmed_WalkForward"
            else
                -- Forward or unclassified.
                animName = "Unarmed_WalkForward"
            end

        else
            -- Mouse lock not active: pure Left/Right and Forward use WalkForward.
            animName = "Unarmed_WalkForward"
        end

    elseif canUseStrafeAnimations then
        -- AR15 and other sets: existing left/right grouping with WalkForward fallback.
        if dirName == "Left" or dirName == "ForwardLeft" or dirName == "BackwardLeft" then
            local leftKey   = setName .. "_WalkLeft"
            local leftTrack = animationTracks[leftKey]
            animName = if leftTrack ~= nil then leftKey else (setName .. "_WalkForward")

        elseif dirName == "Right" or dirName == "ForwardRight" or dirName == "BackwardRight" then
            local rightKey   = setName .. "_WalkRight"
            local rightTrack = animationTracks[rightKey]
            animName = if rightTrack ~= nil then rightKey else (setName .. "_WalkForward")

        else
            -- Forward, Backward, or near-idle magnitude → WalkForward.
            animName = setName .. "_WalkForward"
        end

    else
        -- Mouse lock not active: all walking directions use WalkForward.
        animName = setName .. "_WalkForward"
    end

    playMovementAnimation(animName)
end

-- ============================================================
-- Private helpers — Stage 2O: Humanoid.StateChanged handler
-- ============================================================

-- Handles Humanoid state transitions to drive Falling (looped) and LandingMedium (one-shot).
-- Connected in setupCharacter() after loadMovementAnimations(), stored in stateChangedConn.
-- Disconnected at the top of loadMovementAnimations() on respawn and in destroy().
-- NOT stored in _connections — it is per-character and must be managed separately.
--
-- Freefall  → isFalling = true; capture airStartTime; play Falling if the track exists.
-- Landed / Running → isFalling = false; stop Falling; play LandingMedium if:
--   • airTime ≥ MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME
--   • not crouching (crouch branch owns the animation layer while isCrouching)
--   • crouchTransitionPlaying is false (a one-shot transition owns the layer)
--   • Falling and LandingMedium tracks exist for the current set
--   After LandingMedium's Stopped event fires, clearLandingConnection() releases the gate
--   and the next Heartbeat resumes normal animation selection.
-- All other states → ignored.
local function onHumanoidStateChanged(
    _oldState: Enum.HumanoidStateType,
    newState: Enum.HumanoidStateType
)
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end
    if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
    if next(animationTracks) == nil then return end

    local setName = getAnimationSetName()

    if newState == Enum.HumanoidStateType.Freefall then
        -- ── Entered Freefall ──────────────────────────────────────────────────
        if isFalling then return end   -- already falling; guard against double-fire
        isFalling    = true
        airStartTime = os.clock()

        -- Clear any in-flight LandingMedium Stopped callback (edge case: landed then jumped
        -- again before the one-shot finished and landed a second time).
        clearLandingConnection()
        local landKey   = setName .. "_LandingMedium"
        local landTrack = animationTracks[landKey]
        if landTrack and landTrack.IsPlaying then
            landTrack:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
        end

        -- Play Falling looped. Guard: track must exist (AR15 set has no Falling ID).
        local fallingKey = setName .. "_Falling"
        if animationTracks[fallingKey] ~= nil then
            stopCurrentMovementAnimation()
            playMovementAnimation(fallingKey)
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug("[MovementController] Falling BEGIN (" .. fallingKey .. ")")
            end
        end

    elseif newState == Enum.HumanoidStateType.Landed
        or newState == Enum.HumanoidStateType.Running
    then
        -- ── Landed or transitioned to Running from airborne ───────────────────
        -- Running fires when the character starts moving on the ground; Landed fires on
        -- any ground contact. Both are treated as "landed" for animation purposes.
        if not isFalling then return end   -- was not in a tracked Freefall; ignore
        isFalling = false

        local airTime = os.clock() - airStartTime

        -- Stop the Falling looped track.
        local fallingKey   = setName .. "_Falling"
        local fallingTrack = animationTracks[fallingKey]
        if fallingTrack ~= nil then
            if currentAnimationName == fallingKey then
                -- Let stopCurrentMovementAnimation handle the fade and name clear.
                stopCurrentMovementAnimation()
            elseif fallingTrack.IsPlaying then
                fallingTrack:Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
            end
        end

        -- Guard: skip LandingMedium for any of these conditions:
        --   • airTime too short (small hop or step-off — not a meaningful fall)
        --   • player is crouching (crouch branch owns the animation layer)
        --   • a crouch transition one-shot is in flight (it owns the layer)
        --   • LandingMedium track was not loaded (AR15 set, or track absent)
        local landKey   = setName .. "_LandingMedium"
        local landTrack = animationTracks[landKey]
        if airTime < Constants.MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME
            or movementState.isCrouching
            or crouchTransitionPlaying
            or landTrack == nil
        then
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] Landing: LandingMedium skipped"
                    .. " (airTime=" .. string.format("%.2f", airTime) .. "s"
                    .. " crouching=" .. tostring(movementState.isCrouching)
                    .. " transition=" .. tostring(crouchTransitionPlaying) .. ")"
                )
            end
            return
        end

        -- Play LandingMedium one-shot. Gate isLandingPlaying so updateMovementAnimation
        -- does not override it before the Stopped event fires.
        isLandingPlaying = true
        stopCurrentMovementAnimation()
        playMovementAnimation(landKey)
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug(
                "[MovementController] LandingMedium BEGIN (" .. landKey
                .. " airTime=" .. string.format("%.2f", airTime) .. "s)"
            )
        end

        -- Stopped callback: release the gate so normal selection resumes next Heartbeat.
        -- clearLandingConnection() BEFORE track:Stop() in any external caller — same pattern
        -- as clearCrouchTransitionConnection() and clearCrouchWalkStart().
        landingConn = landTrack.Stopped:Connect(function()
            clearLandingConnection()
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug("[MovementController] LandingMedium finished")
            end
        end)
    end
end

-- ============================================================
-- setupCharacter
-- ============================================================

-- Called on every CharacterAdded. Re-acquires the Humanoid reference, resets
-- movementState, applies the phase-appropriate WalkSpeed immediately, then loads
-- R6 movement animations (Stage 2A layer).
-- Note: disableDefaultAnimate() is called inside loadMovementAnimations() — after the
-- rig is confirmed R6 — so Animate is only disabled when the rig is actually R6.
local function setupCharacter(char: Model)
    humanoid = char:WaitForChild("Humanoid") :: Humanoid

    -- Stage 2E: cache character and root part references for applyCharacterFacing().
    currentCharacter = char
    currentRootPart  = char:WaitForChild("HumanoidRootPart") :: BasePart
    -- Reset facing state so the new character starts clean.
    originalAutoRotate      = nil
    lastFacingSkippedReason = ""

    resetState()

    -- Apply speed immediately — do not wait for the next Heartbeat.
    local hum = humanoid :: Humanoid
    if MatchController:GetPhase() == Constants.Phase.ACTIVE then
        hum.WalkSpeed = Constants.WALK_SPEED  -- sprint/crouch state was just reset above
    else
        hum.WalkSpeed = 0  -- freeze in LOBBY / PREP / RESULTS / MATCHEND
    end

    -- Load R6 movement animations. Skipped if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is
    -- false, rig is not R6, or Animator is missing. Stage 1 speed logic is unaffected.
    -- disableDefaultAnimate() is called inside loadMovementAnimations after rig confirmation.
    loadMovementAnimations(char)

    -- Stage 2O: connect StateChanged AFTER tracks are loaded so the handler can reference
    -- animationTracks safely. stateChangedConn is disconnected at the top of
    -- loadMovementAnimations() on the next respawn, and in destroy(). NOT in _connections.
    local hum2 = humanoid
    if hum2 then
        stateChangedConn = hum2.StateChanged:Connect(onHumanoidStateChanged)
    end

    Logger.debug("[MovementController] Character set up: " .. char.Name)
end

-- ============================================================
-- Controller
-- ============================================================

local MovementController = {}

-- ── Public API ─────────────────────────────────────────────────────────────────

-- Returns the live movementState table. Treat all fields as read-only.
-- Returned by reference — the table updates in place each Heartbeat.
function MovementController:GetMovementState(): typeof(movementState)
    return movementState
end

-- Backward-compatible single-string getter for GunController's spread computation.
-- Returns "Sprinting", "Crouching", "Walking", or "Idle".
function MovementController:GetMoveState(): string
    if movementState.isSprinting and movementState.isMoving then
        return "Sprinting"
    elseif movementState.isCrouching then
        return "Crouching"
    elseif movementState.isMoving then
        return "Walking"
    else
        return "Idle"
    end
end

-- True while the player is sprinting. GunController reads this to block ADS.
function MovementController:IsADSBlocked(): boolean
    return movementState.isSprinting
end

-- Stage 1/2A: no viewmodel effects. Returns identity so ViewModelController's
-- PivotTo composition is unaffected. Future stages compose bob, tilt, and sway
-- here without changing ViewModelController's call site.
function MovementController:GetViewmodelAddCFrame(): CFrame
    return CFrame.new()
end

-- ── Animation set selection — presentation only ────────────────────────────────
-- These methods control ONLY which movement animation set plays (Unarmed or AR15).
-- They do NOT affect server weapon state, ammo, damage, hit validation, or reload.
-- Must eventually be called by a real EquipmentController or weapon equip system
-- when server-owned loadout state is built — see DEBT-050.

-- Sets the equipped weapon name used for movement animation set selection.
-- Pass nil or "" to return to the Unarmed (no-gun) animation set (the default).
-- Pass Constants.DEFAULT_WEAPON / "AR15" to switch to the AR15 animation set.
-- Any other non-empty string: stored as-is but a one-time warning is emitted because
-- no dedicated movement animation set may exist for that weapon name.
function MovementController.SetEquippedWeaponName(weaponName: string?)
    assert(
        weaponName == nil or type(weaponName) == "string",
        "[MovementController] SetEquippedWeaponName: weaponName must be a string or nil"
    )

    if weaponName == nil or weaponName == "" then
        equippedWeaponName = nil
    elseif weaponName == Constants.DEFAULT_WEAPON
        or weaponName == Constants.MOVEMENT_ANIMATION_SET_AR15 then
        equippedWeaponName = weaponName
    else
        -- Unknown weapon — store the name so callers see consistent state, but warn
        -- once that no dedicated animation set is registered for it. Movement will
        -- fall back to Unarmed until a matching set is added to MOVEMENT_ANIMATION_IDS.
        Logger.warn(
            "[MovementController] SetEquippedWeaponName: no dedicated movement animation set "
            .. "for '" .. weaponName .. "'. Movement animations will use Unarmed as fallback."
        )
        equippedWeaponName = weaponName
    end

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] equippedWeaponName = " .. tostring(equippedWeaponName)
        )
    end
end

-- Returns the current presentation-only equipped weapon name used for animation set selection.
-- Returns nil when no weapon is equipped (Unarmed animation set is active).
function MovementController.GetEquippedWeaponName(): string?
    return equippedWeaponName
end

-- ── Custom mouse-lock (Stage 2D) ───────────────────────────────────────────────

-- Sets the custom mouse-lock state and applies UserInputService.MouseBehavior accordingly.
-- enabled == true  → customMouseLocked = true; MouseBehavior = LockCenter.
-- enabled == false → customMouseLocked = false; MouseBehavior = Default.
-- If Constants.CUSTOM_MOUSE_LOCK_ENABLED is false, forces off and resets to Default.
-- Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
-- Logs state change if Constants.CUSTOM_MOUSE_LOCK_DEBUG == true.
function MovementController.SetCustomMouseLocked(enabled: boolean)
    assert(
        typeof(enabled) == "boolean",
        "[MovementController] SetCustomMouseLocked: enabled must be a boolean"
    )

    customMouseLocked = enabled
    -- applyCustomMouseLock() handles the CUSTOM_MOUSE_LOCK_ENABLED gate and writes
    -- UserInputService.MouseBehavior immediately (no deferred task, no Heartbeat wait).
    applyCustomMouseLock()

    if Constants.CUSTOM_MOUSE_LOCK_DEBUG then
        Logger.debug(
            "[MovementController] custom mouse lock: " .. (customMouseLocked and "ON" or "OFF")
        )
    end
end

-- Returns true when the custom mouse lock is currently active (LeftControl toggled on).
-- Strafe animation selection (updateMovementAnimation) reads this via isMouseLockedForStrafeAnimations().
function MovementController.IsCustomMouseLocked(): boolean
    return customMouseLocked
end

-- Disconnects all event connections, stops all animation tracks, destroys Animation
-- instances, and resets all state.
-- Safe to call even if Start() was never called (iterates empty tables).
function MovementController:destroy()
    -- Unbind the ContextActionService mouse-lock action (not stored in _connections).
    ContextActionService:UnbindAction(MOUSE_LOCK_ACTION_NAME)

    -- Stage 2K: restore normal third-person camera limits and clear CameraOffset.
    -- Called before customMouseLocked is reset so restoreNormalThirdPersonCamera can
    -- always write the correct zoom limits regardless of lock state.
    restoreNormalThirdPersonCamera()
    defaultCameraMinZoomDistance = nil
    defaultCameraMaxZoomDistance = nil
    defaultCameraOffset          = nil

    -- Stage 2H + 2I: disconnect callback, clear hold, then stop tracks.
    clearCrouchTransitionConnection()
    crouchTransitionPlaying   = false
    -- Stage 2N: disconnect CrouchWalkStart callback and clear its state.
    clearCrouchWalkStart()
    wasMovingWhileCrouching = false
    -- Stage 2O: disconnect StateChanged and clear falling/landing state.
    if stateChangedConn then
        stateChangedConn:Disconnect()
        stateChangedConn = nil
    end
    isFalling    = false
    airStartTime = 0
    clearLandingConnection()
    clearCrouchBottomHold()
    -- Stop the active animation if still playing, then clear track references.
    stopCurrentMovementAnimation()
    table.clear(animationTracks)
    currentAnimationName      = ""
    rigTypeWarned             = false
    equippedWeaponName        = nil
    lastAnimationSet          = ""
    lastStrafeBlockedState    = false
    crouchBottomPoseWarned    = false
    -- Stage 2E: restore AutoRotate if mouse lock is active before clearing state.
    if Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW and customMouseLocked then
        restoreCharacterAutoRotate()
    end
    originalAutoRotate      = nil
    currentCharacter        = nil
    currentRootPart         = nil
    lastFacingSkippedReason = ""

    -- Release custom mouse lock and cursor on destroy.
    customMouseLocked                  = false
    UserInputService.MouseBehavior     = Enum.MouseBehavior.Default

    -- Explicitly destroy Animation instances.
    for _, inst in pairs(animationInstances) do
        inst:Destroy()
    end
    table.clear(animationInstances)

    for _, conn in ipairs(_connections) do
        conn:Disconnect()
    end
    _connections = {}
    humanoid     = nil
    resetState()
    Logger.debug("[MovementController] Destroyed")
end

-- ============================================================
-- Start
-- ============================================================

function MovementController:Start()
    local localPlayer = Players.LocalPlayer

    -- Stage 2K: cache the player's default zoom distances before we override them,
    -- then immediately apply the controlled third-person range.
    -- cacheDefaultCameraSettings() is idempotent — safe if Start() is re-called.
    cacheDefaultCameraSettings()
    applyThirdPersonZoomLimits()

    -- Disable Roblox's built-in Shift Lock immediately so LeftShift is sprint-only.
    -- Also applied on every CharacterAdded below because CoreScripts may re-enable it
    -- on respawn. Gated by Constants.DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK.
    disableRobloxDefaultMouseLock()

    -- Handle a character that already exists before Start() is called.
    -- Rare in normal play (ClientInit runs early) but correct to handle.
    if localPlayer.Character then
        setupCharacter(localPlayer.Character)
    end

    -- ── CharacterAdded ────────────────────────────────────────────────────────
    -- Re-acquires Humanoid, resets state, and loads R6 animations (Animate disable
    -- is handled inside loadMovementAnimations after rig confirmation).
    local charConn = localPlayer.CharacterAdded:Connect(function(char: Model)
        -- Re-disable Roblox Shift Lock after respawn — CoreScripts may restore it.
        disableRobloxDefaultMouseLock()
        -- setupCharacter() sets humanoid, calls loadMovementAnimations() which resets
        -- customMouseLocked = false, so after this call the mouse lock is always off.
        setupCharacter(char)
        -- Stage 2K: re-cache CameraOffset for the new humanoid, then apply correct camera state.
        -- customMouseLocked is false after respawn (reset in loadMovementAnimations), so we
        -- always restore normal third-person limits and clear any leftover CameraOffset.
        cacheDefaultCameraSettings()
        if customMouseLocked then
            applyCustomMouseLockCamera()
        else
            restoreNormalThirdPersonCamera()
        end
    end)
    table.insert(_connections, charConn)

    -- ── RoundStateChanged ─────────────────────────────────────────────────────
    -- Mirrors the phase into movementState and WalkSpeed.
    local phaseConn = RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local phase   = payload.phase

        if phase ~= Constants.Phase.ACTIVE then
            -- Leaving ACTIVE: freeze the player, clear movement state, stop animations.
            resetState()
            -- Stage 2H + 2I: disconnect Stopped callback, clear hold, then stop tracks.
            -- Order: disconnect → clear hold (stops hold track) → stop locomotion.
            clearCrouchTransitionConnection()
            crouchTransitionPlaying = false
            clearCrouchBottomHold()
            stopCurrentMovementAnimation()
            -- Stage 2O: reset falling/landing state so re-entry to ACTIVE starts clean.
            isFalling = false
            clearLandingConnection()
            local hum = humanoid
            if hum then
                hum.WalkSpeed = 0
            end
            -- Custom mouse lock is intentionally NOT reset here.
            -- The player's LeftAlt toggle state is preserved across phase changes
            -- (ACTIVE → LOBBY → RESULTS → ACTIVE). Only respawn (loadMovementAnimations)
            -- and destroy() clear customMouseLocked.

            -- Stage 2E: restore AutoRotate when leaving ACTIVE while mouse lock is on
            -- and REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION is true. The originalAutoRotate
            -- cache is preserved (NOT cleared) so re-entry to ACTIVE can disable it again.
            if Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW
                and Constants.CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION
                and customMouseLocked
            then
                restoreCharacterAutoRotate()
                -- Intentionally do NOT clear originalAutoRotate here — preserved for ACTIVE re-entry.
                if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG then
                    Logger.debug("[MovementController] Phase exit: AutoRotate restored (toggle state preserved)")
                end
            end
        else
            -- Entering ACTIVE: restore walk speed.
            local hum = humanoid
            if hum then
                hum.WalkSpeed = Constants.WALK_SPEED
            end

            -- Stage 2E: re-disable AutoRotate if mouse lock is still on and FACE_CAMERA_YAW
            -- is active. This handles the case where the player toggled mouse lock in a
            -- non-ACTIVE phase and then the round transitioned back to ACTIVE.
            if Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW and customMouseLocked then
                local h = humanoid
                if h then
                    if originalAutoRotate == nil then
                        originalAutoRotate = h.AutoRotate
                    end
                    h.AutoRotate = false
                    if Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG then
                        Logger.debug("[MovementController] ACTIVE re-entry: AutoRotate disabled for character-facing")
                    end
                end
                applyCharacterFacing()
            end
        end
    end)
    table.insert(_connections, phaseConn)

    -- ── Input: Sprint (LeftShift) ─────────────────────────────────────────────
    -- The standard gameProcessed (gp) guard is intentionally NOT used for LeftShift.
    -- Roblox's built-in shift-lock feature marks LeftShift as gameProcessed = true even
    -- when the player intends to sprint, which would silently block sprint while shift
    -- lock is active. Instead, sprint is only blocked while the player is typing in a
    -- TextBox — any other gameProcessed reason (including shift lock) is allowed through.
    local sprintBeginConn = UserInputService.InputBegan:Connect(
        function(input: InputObject, _gp: boolean)
            if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
            -- Block sprint while the player is focused on a TextBox (typing).
            if UserInputService:GetFocusedTextBox() ~= nil then return end
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
            if movementState.isCrouching then return end
            movementState.isSprinting = true
            applySpeed()
        end
    )
    table.insert(_connections, sprintBeginConn)

    local sprintEndConn = UserInputService.InputEnded:Connect(
        function(input: InputObject, _gp: boolean)
            if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
            if not movementState.isSprinting then return end
            movementState.isSprinting = false
            applySpeed()
        end
    )
    table.insert(_connections, sprintEndConn)

    -- ── Input: Custom mouse-lock toggle (LeftControl via ContextActionService) ──────
    -- Priority 3000 > CoreScript default 2000 — LeftControl is intercepted before CoreScripts
    -- can delay or consume it, eliminating the ~1-frame toggle lag seen with InputBegan.
    -- Key changed from LeftAlt to LeftControl in Stage 2K (2026-05-20).
    -- Returns Sink on Begin so CoreScripts never see the key; returns Pass on all other
    -- states (End, Change) so those are handled normally.
    -- NOT stored in _connections — unbound by name via MOUSE_LOCK_ACTION_NAME in destroy().
    ContextActionService:BindActionAtPriority(
        MOUSE_LOCK_ACTION_NAME,
        function(
            _actionName: string,
            inputState: Enum.UserInputState,
            _inputObj: InputObject
        ): Enum.ContextActionResult
            -- Only act on Begin; pass End and Change through.
            if inputState ~= Enum.UserInputState.Begin then
                return Enum.ContextActionResult.Pass
            end
            -- Block toggle while the player is focused on a TextBox (typing).
            if UserInputService:GetFocusedTextBox() ~= nil then
                return Enum.ContextActionResult.Pass
            end
            if Constants.CUSTOM_MOUSE_LOCK_ENABLED ~= true then
                return Enum.ContextActionResult.Pass
            end
            MovementController.SetCustomMouseLocked(not customMouseLocked)
            -- Sink so CoreScripts do not see the LeftAlt key press.
            return Enum.ContextActionResult.Sink
        end,
        false,                                          -- createTouchButton
        Constants.CUSTOM_MOUSE_LOCK_INPUT_PRIORITY,    -- priority (3000)
        Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY          -- Enum.KeyCode.LeftControl (Stage 2K)
    )

    -- ── Input: Crouch (hold-to-crouch — Stage 2I) ────────────────────────────
    -- C held → enter crouch; C released → exit crouch.
    -- Replaces the previous toggle-on-C behavior (Stage 2H).
    -- Sprint is blocked while crouching; sprint cannot start until C is released.
    local crouchBeginConn = UserInputService.InputBegan:Connect(
        function(input: InputObject, _gp: boolean)
            if input.KeyCode ~= Constants.CROUCH_HOLD_KEY then return end
            if UserInputService:GetFocusedTextBox() ~= nil then return end
            if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
            if movementState.isCrouching then return end  -- already crouching; ignore repeat

            movementState.isCrouching = true
            movementState.isSprinting = false
            applySpeed()
            playCrouchTransition(true)   -- play EnterCrouch
        end
    )
    table.insert(_connections, crouchBeginConn)

    local crouchEndConn = UserInputService.InputEnded:Connect(
        function(input: InputObject, _gp: boolean)
            if input.KeyCode ~= Constants.CROUCH_HOLD_KEY then return end
            if not movementState.isCrouching then return end

            movementState.isCrouching = false
            applySpeed()
            -- Disconnect any in-flight EnterCrouch Stopped callback so
            -- holdCrouchBottomPose() does not fire after we've already exited crouch.
            clearCrouchTransitionConnection()
            crouchTransitionPlaying = false
            -- Release the hold pose if it was active.
            clearCrouchBottomHold()
            -- Play ExitCrouch. playCrouchTransition calls stopCurrentMovementAnimation
            -- internally to cleanly stop any partially-played EnterCrouch or CrouchWalk.
            playCrouchTransition(false)  -- play ExitCrouch
        end
    )
    table.insert(_connections, crouchEndConn)

    -- ── Heartbeat: direction detection, speed maintenance, animation update ────
    -- Runs every physics step. Updates movementState, re-applies speed, and drives
    -- the Stage 2A animation layer. No camera writes.
    local heartbeatConn = RunService.Heartbeat:Connect(function(_dt: number)
        -- Reapply custom mouse lock every frame while it is active.
        -- Prevents CoreScripts or UI transitions from resetting MouseBehavior after the
        -- LeftAlt toggle fires. Runs regardless of phase so the lock persists in all states.
        if Constants.CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME and customMouseLocked then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end

        -- Stage 2E: rotate character to face camera yaw every frame while locked.
        -- applyCharacterFacing() self-gates on REQUIRE_ACTIVE, customMouseLocked, nil checks.
        -- Runs before the phase guard below so the skip-reason log fires on phase transitions.
        applyCharacterFacing()

        local hum = humanoid
        if not hum then return end
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end

        local moveDir               = hum.MoveDirection
        movementState.moveVector    = moveDir
        movementState.isMoving      = moveDir.Magnitude > Constants.MOVEMENT_DIRECTION_DEADZONE
        movementState.directionName = classifyDirection(moveDir)

        applySpeed()

        -- Stage 2A: select and play the correct walk/run animation.
        updateMovementAnimation()
    end)
    table.insert(_connections, heartbeatConn)

    Logger.debug("[MovementController] Ready (Stage 1–2O: DevMouseLock, CAS 3000, LeftControl toggle, reapply-frame, facing-yaw, zoom-limits 4–14, mouse-lock-cam 8+offset, Unarmed directional/diagonals+new IDs, idle, hold-to-crouch, crouch-bottom-hold, CrouchWalk, sprint→RunForward, CrouchIdle, CrouchWalkStart, Falling+LandingMedium)")
end

return MovementController
