--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MovementController
--
-- Movement Stage 1 + 2A + 2C + 2D + 2E + 2F + 2G + 2H + 2I + 2J + 2K + 2L + 2M + 2N + 2O + 2P + 2Q + 2Q+ + 2Q-D + 2R + 2S + 3A + 3B + 3C + 3D (Animate-disable, R6 detection, animation-set selection,
-- strafe gating, animation speed multipliers, shift-lock sprint fix, custom mouse-lock toggle,
-- character-facing camera yaw, Unarmed backward/diagonal directional animations,
-- directional sprint selection (RunForwardLeft/Right with mouse lock; RunForward fallback),
-- standing idle + enter/exit crouch one-shot transition animations,
-- hold-to-crouch + EnterCrouch bottom-pose hold,
-- Unarmed 8-directional crouch-walk animations + CrouchWalk speed multiplier,
-- third-person zoom limits + custom mouse-lock camera distance/offset,
-- CrouchIdle looped idle while crouched+still + CrouchWalkStart one-shot idle-to-walk transition,
-- Unarmed Falling looped + landing one-shot (LandingLight/Medium/Heavy) via Humanoid.StateChanged,
-- Tactical sprint foundation: double-tap LeftShift → faster sprint with speed ramp + forward-only animation + gun block,
-- Fix crouch animation contamination (Stage 2Q): stopCrouchTracksExcept helper + direct CrouchIdle transition + clearCrouchBottomHold no-resume fix,
-- Crouch blend contamination follow-up (Stage 2Q+): fix "Crouch" pattern (catches EnterCrouch/ExitCrouch), remove IsPlaying guard, Stop(0) for immediate weight cut, add stopCrouchTracksExcept call in playCrouchTransition before track:Play,
-- Sprint FOV stretch via TweenService (FieldOfView only — no camera.CFrame) + landing classification light/medium/heavy) —
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
--   Sprint with custom mouse lock OFF: always RunForward regardless of direction. (Stage 2L)
--   Sprint with custom mouse lock ON, ForwardLeft: RunForwardLeft if loaded, else RunForward. (Stage 2R)
--   Sprint with custom mouse lock ON, ForwardRight: RunForwardRight if loaded, else RunForward. (Stage 2R)
--   Sprint with custom mouse lock ON, other directions: RunForward fallback. (Stage 2R)
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
local TweenService          = game:GetService("TweenService")   -- Stage 3A: sprint FOV tween
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
    isMoving            = false,          -- true when MoveDirection.Magnitude > MOVEMENT_DIRECTION_DEADZONE
    isSprinting         = false,          -- true while LeftShift is held during ACTIVE
    isCrouching         = false,          -- true while crouched (toggled by C during ACTIVE)
    directionName       = "Idle",         -- one of 9 direction strings (see classifyDirection)
    moveVector          = Vector3.zero,   -- raw Humanoid.MoveDirection each Heartbeat
    isTacticalSprinting = false,          -- true while tactical sprint is active (Stage 2P)
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

-- Stage 2R: last sprint animation name that was logged to Output.
-- Guards against per-frame log spam: only logs when the sprint anim key changes.
-- Reset to "" on each character load and in destroy().
local lastSprintAnimName: string = ""

-- Stage 3A: sprint FOV tween state ───────────────────────────────────────────
-- Active TweenService Tween object for the sprint FieldOfView transition.
-- Cancelled before a new tween starts. Cancelled and cleared in destroy().
-- nil when no tween is in flight (idle, or FOV already at target).
local currentFovTween: Tween? = nil

-- The FieldOfView value that the most recent tween targeted.
-- Guards against restarting the same tween every frame: updateSprintFov only
-- starts a new tween when the desired target differs from this value.
-- Reset to Constants.DEFAULT_CAMERA_FOV on respawn and in destroy().
local targetFov: number = 70  -- will be synced to Constants.DEFAULT_CAMERA_FOV on Start/respawn

-- Stage 3A: jump and drop tracking ───────────────────────────────────────────
-- World-Y position of HumanoidRootPart when the airborne phase began.
-- Set on Jumping state (jump entry) or Freefall entry (ledge drop with no Jumping state).
-- Used on landing to compute dropDistance = airborneStartY - landingY.
-- nil when not airborne or after landing is processed. Reset on respawn.
local airborneStartY: number? = nil

-- true when the current airborne phase began with a Jumping state.
-- false for pure ledge drops (Freefall without a preceding Jumping state).
-- Cleared to false after landing is processed. Reset on respawn.
local wasJumpingThisAirborne: boolean = false

-- true when the player was sprinting (normal or tactical) at the moment of jump.
-- Only meaningful when wasJumpingThisAirborne is true.
-- Used by getLandingAnimationName; when MOVEMENT_LANDING_SPRINT_JUMP_USES_MEDIUM = false,
-- sprint jumps resolve to LandingLight (same as normal jumps). Walk-off drops are unaffected.
-- Cleared to false after landing is processed. Reset on respawn.
local jumpedWhileSprinting: boolean = false

-- Stage 3B: landing movement lock state ──────────────────────────────────────

-- true while a medium/heavy landing is locking player input movement (WalkSpeed = 0).
-- Cleared by clearLandingMovementLock() — either from the animation Stopped callback,
-- the fallback task.delay timer, or from phase exit / respawn / destroy.
local isLandingMovementLocked: boolean = false

-- Monotonically incrementing token used to invalidate stale task.delay unlock callbacks.
-- Incremented by clearLandingMovementLock(). Each task.delay captures the token value
-- at creation; it only runs if the token still matches when the delay fires.
-- Prevents a respawn or earlier manual unlock from causing a double-unlock later.
local landingLockToken: number = 0

-- true while a sprint-jump momentum LinearVelocity carry is active.
-- Set by startSprintJumpLandingMomentum; cleared by clearLandingMomentum.
-- Checked by the landing Stopped callback — when active, the callback defers
-- the movement-lock release to the momentum's own task.delay.
local landingMomentumActive: boolean = false

-- The Attachment instance created on HumanoidRootPart for the momentum carry.
-- Parented to currentRootPart; destroyed (not just unparented) in clearLandingMomentum.
-- nil when no momentum carry is active.
local landingMomentumAttachment: Attachment? = nil

-- The LinearVelocity instance driving the sprint-jump forward carry.
-- Parented to currentRootPart; destroyed in clearLandingMomentum.
-- nil when no momentum carry is active.
local landingMomentumVelocity: LinearVelocity? = nil

-- The horizontal unit direction captured at the moment of a sprint jump.
-- Set by captureJumpMomentumDirection() in the Jumping state handler.
-- Consumed (read then set to nil) by the Landed handler when starting the carry.
-- nil when not tracking a sprint-jump airborne phase.
local sprintJumpMomentumDirection: Vector3? = nil

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

-- Stage 3D: last sprint body-facing mode, used to deduplicate debug log on mode change.
-- "move_dir" while sprinting + mouse lock + valid move direction; "camera_yaw" otherwise.
local lastSprintFacingMode: string = ""

-- Stage 3E: true while natural-AutoRotate sprint is active. Used to detect the transition back
-- to camera-yaw facing (so AutoRotate is restored to false before the CFrame write).
-- Reset on respawn (loadMovementAnimations), mouse-lock disable, and destroy().
local lastNaturalSprintAutoRotateActive: boolean = false

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

-- Stage 2P: tactical sprint state ──────────────────────────────────────────

-- True while a tactical sprint is active (double-tap LeftShift detected).
-- Cleared on Shift release, movement stops, forward-dot failure, crouch, phase exit, or respawn.
-- Mirrors movementState.isTacticalSprinting for GunController and other callers.
local isTacticalSprinting: boolean = false

-- os.clock() captured when tactical sprint began. Used to compute the speed ramp in applySpeed().
-- Reset to 0 when tactical sprint ends.
local tacticalSprintStartTime: number = 0

-- os.clock() of the most recent valid LeftShift InputBegan event during ACTIVE phase.
-- Used by double-tap detection: if the next LeftShift press arrives within
-- TACTICAL_SPRINT_DOUBLE_TAP_WINDOW seconds of this value, tactical sprint starts.
-- Initialized to 0 so the very first LeftShift press never triggers tactical sprint alone.
local lastShiftPressTime: number = 0

-- Stopped-event connection for the active TacticalSprintStop one-shot track.
-- Connected when stopTacticalSprint() plays TacticalSprintStop; disconnected by
-- clearTacticalSprintStopConnection() when the track finishes.
-- Also used as an "is-playing" gate in updateMovementAnimation() — when non-nil,
-- the one-shot is still running and Heartbeat must not override it.
local tacticalSprintStopConn: RBXScriptConnection? = nil

-- Stage 3C: normal sprint-stop state ─────────────────────────────────────────

-- os.clock() captured when normal sprint (LeftShift) begins.
-- Set to nil after duration is evaluated at sprint end, and on respawn/destroy.
-- Used to gate SprintStop by SPRINT_STOP_MIN_SPRINT_DURATION.
local sprintStartTime: number? = nil

-- Last known XZ-normalised sprint direction, updated every Heartbeat while
-- movementState.isSprinting is true (and tactical sprint is not active).
-- Consumed by playSprintStopWithLock as the momentum carry direction.
-- Cleared on respawn/destroy and on phase exit.
local lastSprintMomentumDirection: Vector3? = nil

-- True while the SprintStop one-shot is playing and movement is locked.
-- Cleared by clearSprintStopLock() when the animation finishes or the fallback timer fires.
-- Gates updateMovementAnimation() and applySpeed() while the one-shot runs.
local isSprintStopPlaying: boolean = false

-- Invalidation counter for stale task.delay unlock callbacks — mirrors landingLockToken.
-- Incremented on every clearSprintStopLock() call; each task.delay captures the value
-- at dispatch time and no-ops if the token has since changed.
local sprintStopLockToken: number = 0

-- LinearVelocity Attachment parented to HumanoidRootPart during the momentum carry.
-- Nil when no carry is active. Destroyed by clearSprintStopMomentum().
local sprintStopMomentumAttachment: Attachment? = nil

-- The LinearVelocity instance pushing the player forward during the momentum carry.
-- Nil when no carry is active. Destroyed by clearSprintStopMomentum().
local sprintStopMomentumVelocity: LinearVelocity? = nil

-- ============================================================
-- Private helpers — Stage 1
-- ============================================================

-- Resets all movementState fields to initial (idle) values.
-- Does NOT apply WalkSpeed — callers must call applySpeed() or set it directly after.
local function resetState()
    movementState.isMoving            = false
    movementState.isSprinting         = false
    movementState.isCrouching         = false
    movementState.directionName       = "Idle"
    movementState.moveVector          = Vector3.zero
    movementState.isTacticalSprinting = false  -- Stage 2P
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

    -- Stage 3B: landing movement lock overrides all other speed logic.
    -- When a medium/heavy landing is locking input, WalkSpeed stays at 0
    -- regardless of sprint/crouch/walk state. The LinearVelocity carry (if active)
    -- provides the only motion during this window; player input is not applied.
    if isLandingMovementLocked then
        hum.WalkSpeed = 0
        return
    end

    -- Stage 3C: sprint-stop movement lock — second-highest priority after landing lock.
    -- When SprintStop is playing and SPRINT_STOP_LOCKS_MOVEMENT is true, WalkSpeed stays
    -- at 0 regardless of sprint/crouch/walk state. Cleared by clearSprintStopLock().
    if isSprintStopPlaying and Constants.SPRINT_STOP_LOCKS_MOVEMENT == true then
        hum.WalkSpeed = 0
        return
    end

    -- Stage 2P: tactical sprint speed ramp — lerp from SPRINT_SPEED to TACTICAL_SPRINT_SPEED
    -- over TACTICAL_SPRINT_ACCELERATION_TIME. Runs before the regular speed checks so it
    -- takes priority while tactical sprint is active (overrides the normal sprint path).
    if isTacticalSprinting then
        local elapsed = os.clock() - tacticalSprintStartTime
        local t = math.clamp(elapsed / Constants.TACTICAL_SPRINT_ACCELERATION_TIME, 0, 1)
        hum.WalkSpeed = Constants.SPRINT_SPEED
            + (Constants.TACTICAL_SPRINT_SPEED - Constants.SPRINT_SPEED) * t
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

-- ── Stage 3D ─────────────────────────────────────────────────────────────────

-- Returns the flat XZ world-space direction of the player's current movement input,
-- expressed camera-relative. Uses movementState.moveVector (Humanoid.MoveDirection),
-- which Roblox already computes camera-relative — no additional camera transform needed.
-- Returns nil when movement magnitude is below SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE
-- (no useful direction to face toward).
-- Does NOT write camera.CFrame. Does NOT modify any state.
local function getCameraRelativeMoveDirection(): Vector3?
    local mv = movementState.moveVector
    if mv == nil then return nil end
    local flat = Vector3.new(mv.X, 0, mv.Z)
    if flat.Magnitude < Constants.SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE then
        return nil
    end
    return flat.Unit
end

-- Rotates HumanoidRootPart to face `direction` (XZ, yaw-only) without changing position.
-- Mirrors the CFrame.lookAt pattern used by applyCharacterFacing() for camera-yaw facing.
-- Sets Humanoid.AutoRotate = false so the manual CFrame write is not overwritten by Roblox
-- physics on the next step. originalAutoRotate is cached by the existing mouse-lock path.
-- Does NOT write camera.CFrame. Does NOT change velocity or teleport the character.
-- Optional LERP: when SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED is true, blends
-- toward the target over multiple frames using SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA.
local function faceCharacterTowardsDirection(direction: Vector3)
    assert(typeof(direction) == "Vector3",
        "[MovementController] faceCharacterTowardsDirection: direction must be a Vector3")
    local root = currentRootPart
    if not root then return end
    local hum = humanoid
    if not hum then return end

    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < Constants.SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE then
        return
    end
    local targetDir = flat.Unit

    -- AutoRotate must be false for the CFrame write to persist.
    -- originalAutoRotate is already cached by SetCustomMouseLocked when the lock was enabled.
    hum.AutoRotate = false

    local pos = root.Position

    if Constants.SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED then
        -- Smoothed path: LERP between current facing and target direction.
        local alpha = math.clamp(Constants.SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA, 0, 1)
        local currentLook = root.CFrame.LookVector
        local currentFlat = Vector3.new(currentLook.X, 0, currentLook.Z)
        if currentFlat.Magnitude > 0.001 then
            -- Lerp then normalise — avoids division by zero when the two vectors are collinear.
            local lerpedDir = currentFlat.Unit:Lerp(targetDir, alpha)
            if lerpedDir.Magnitude > 0.001 then
                root.CFrame = CFrame.lookAt(pos, pos + lerpedDir.Unit)
                return
            end
        end
        -- Fallback to immediate facing if current look is degenerate.
    end

    -- Immediate (default) path.
    root.CFrame = CFrame.lookAt(pos, pos + targetDir)
end

-- ─────────────────────────────────────────────────────────────────────────────

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

-- ── Stage 3E ─────────────────────────────────────────────────────────────────

-- Returns true when the Stage 3E natural-AutoRotate sprint path should be active.
-- Both SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED and
-- SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED must be true (independent kill switches).
-- Requires: custom mouse lock on, actively sprinting, not in tactical sprint, not crouching,
-- not during sprint-stop animation playback, and not during landing movement lock.
-- Does NOT check phase — phase is gated at the top of applyCharacterFacing() already.
-- Does NOT write any state or modify any variables.
local function shouldUseNaturalSprintAutoRotate(): boolean
    if not Constants.SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED then return false end
    if not Constants.SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED then return false end
    if not customMouseLocked then return false end
    if not movementState.isSprinting then return false end
    if isTacticalSprinting then return false end
    if movementState.isCrouching then return false end
    if isSprintStopPlaying then return false end
    if isLandingMovementLocked then return false end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Rotates the character's HumanoidRootPart to face the camera's yaw direction every
-- Heartbeat while custom mouse lock is active and FACE_CAMERA_YAW is enabled.
-- Phase-gated when REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION is true (only runs in ACTIVE).
-- No-ops silently when guards fail (no humanoid, no root part, near-vertical camera look).
-- Writes HumanoidRootPart.CFrame with the same position — the character is rotated in place;
-- it is NOT teleported and its velocity is NOT modified.
-- Logs skip-reason changes once per reason when CUSTOM_MOUSE_LOCK_ROTATION_DEBUG is true.
-- Stage 3E: when shouldUseNaturalSprintAutoRotate() is true, sets AutoRotate = true and
-- returns without writing HumanoidRootPart.CFrame — Roblox physics handles the yaw rotation.
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

    -- ── Stage 3E: Natural AutoRotate sprint rotation ──────────────────────────
    -- When sprinting + custom mouse lock active (and both Stage 3E kill switches are true),
    -- delegate yaw rotation to the Roblox engine by setting AutoRotate = true.
    -- This eliminates the discrete 45°/90° CFrame snaps produced by Stage 3D's
    -- faceCharacterTowardsDirection() when the player crosses a directionName boundary.
    -- Walking, idle, crouching, tactical sprint, sprint-stop, and landing continue on the
    -- camera-yaw CFrame path below (AutoRotate = false, root.CFrame = CFrame.lookAt).
    if shouldUseNaturalSprintAutoRotate() then
        local hum = humanoid
        if hum then
            hum.AutoRotate = true
        end
        if Constants.SPRINT_NATURAL_AUTOROTATE_DEBUG and not lastNaturalSprintAutoRotateActive then
            lastNaturalSprintAutoRotateActive = true
            Logger.debug(
                "[MovementController] applyCharacterFacing → natural AutoRotate (sprint, Stage 3E)"
            )
        end
        return
    end

    -- Stage 3E exit: if we just left natural-AutoRotate sprint, re-enforce AutoRotate = false
    -- before the camera-yaw CFrame write below — otherwise the engine would immediately
    -- overwrite our CFrame via its own AutoRotate rotation.
    if lastNaturalSprintAutoRotateActive then
        lastNaturalSprintAutoRotateActive = false
        local hum = humanoid
        if hum then
            hum.AutoRotate = false
        end
        if Constants.SPRINT_NATURAL_AUTOROTATE_DEBUG then
            Logger.debug(
                "[MovementController] applyCharacterFacing → camera yaw (AutoRotate restored false, Stage 3E)"
            )
        end
    end
    -- ─────────────────────────────────────────────────────────────────────────

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
        -- Stage 3E: clear natural-AutoRotate sprint flag so the next lock session starts clean.
        lastNaturalSprintAutoRotateActive = false
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

-- Stage 2P: Disconnects the TacticalSprintStop Stopped callback.
-- Must be called BEFORE any track:Stop() on the TacticalSprintStop track to prevent
-- spurious callbacks — mirrors the clearLandingConnection() pattern.
-- Also used as the "is-playing" indicator in updateMovementAnimation(): when
-- tacticalSprintStopConn is non-nil, the one-shot is still running.
-- Safe to call when no stop one-shot is active (no-op).
local function clearTacticalSprintStopConnection()
    if tacticalSprintStopConn then
        tacticalSprintStopConn:Disconnect()
        tacticalSprintStopConn = nil
    end
end

-- Stage 2Q+: Stops every loaded crouch-variant AnimationTrack whose key is NOT allowedKey.
-- Called before transitioning into EnterCrouch, ExitCrouch, CrouchIdle, CrouchWalk*,
-- CrouchWalkStart, or any other crouch clip to ensure no stale crouch blend persists.
-- allowedKey may be nil to stop ALL crouch tracks (used during phase exit / full cleanup).
-- Does NOT call clearCrouchBottomHold() — callers that need to release the hold state must
-- do so explicitly before calling this function.
-- Clears currentAnimationName when the currently tracked animation was one of the stopped tracks.
--
-- Pattern uses key:find("Crouch") (not "_Crouch") so that EnterCrouch and ExitCrouch
-- (whose keys end with "Crouch" after the verb prefix) are also matched — previously these
-- were silently skipped and could continue blending as the new animation faded in.
--
-- Stop(0) is used (not MOVEMENT_ANIMATION_FADE_TIME) so that any track with a non-zero
-- weight — including tracks already stopped via Stop(fadeTime) whose weight is still
-- decaying — is immediately cut to zero weight before the new animation starts.
-- This prevents the "old crouch pose bleeds through the fade-in window" contamination.
local function stopCrouchTracksExcept(allowedKey: string?)
    for key, track in pairs(animationTracks) do
        if key:find("Crouch") and key ~= allowedKey then
            track:Stop(0)
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug("[MovementController] stopCrouchTracksExcept: cut " .. key)
            end
        end
    end
    -- If the currently tracked animation was a crouch track that was just stopped, clear it
    -- so stopCurrentMovementAnimation() does not try to stop it a second time.
    if currentAnimationName ~= ""
        and currentAnimationName:find("Crouch")
        and currentAnimationName ~= allowedKey
    then
        currentAnimationName = ""
    end
end

-- ============================================================
-- Private helpers — Stage 3B: landing movement lock + sprint-jump momentum
-- Inserted here (before loadMovementAnimations) so that loadMovementAnimations can
-- call clearLandingMovementLock() without a Luau --!strict forward-reference error.
-- All helpers depend only on applySpeed() and module-level state, both declared above.
-- ============================================================

-- Returns the XZ-flattened unit vector of `vector`, or nil when the horizontal
-- magnitude is too small to produce a stable unit direction (<= 0.01).
-- Used to derive a momentum carry direction from AssemblyLinearVelocity or MoveDirection.
local function getFlatVector(vector: Vector3): Vector3?
    local flat = Vector3.new(vector.X, 0, vector.Z)
    if flat.Magnitude <= 0.01 then return nil end
    return flat.Unit
end

-- Captures the horizontal unit direction to use for the sprint-jump momentum carry.
-- Called in the Jumping state handler when jumpedWhileSprinting is true — before the
-- character enters Freefall, so velocity and facing are still valid for the takeoff frame.
--
-- Priority (highest to lowest):
--  1. currentRootPart.AssemblyLinearVelocity (physics velocity at takeoff)
--  2. humanoid.MoveDirection (input direction if velocity is unavailable)
--  3. currentRootPart.CFrame.LookVector (character facing as last resort)
--
-- Result stored in sprintJumpMomentumDirection. Consumed (set to nil) by the Landed handler.
local function captureJumpMomentumDirection()
    local rootPart = currentRootPart
    local hum      = humanoid

    -- Priority 1: physics velocity direction.
    if rootPart then
        local vel = (rootPart :: BasePart).AssemblyLinearVelocity
        local dir = getFlatVector(vel)
        if dir then
            sprintJumpMomentumDirection = dir
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] captureJumpMomentumDirection: velocity dir "
                    .. string.format("(%.2f,%.2f,%.2f)", dir.X, dir.Y, dir.Z)
                )
            end
            return
        end
    end

    -- Priority 2: humanoid MoveDirection.
    if hum then
        local dir = getFlatVector(hum.MoveDirection)
        if dir then
            sprintJumpMomentumDirection = dir
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] captureJumpMomentumDirection: MoveDirection dir "
                    .. string.format("(%.2f,%.2f,%.2f)", dir.X, dir.Y, dir.Z)
                )
            end
            return
        end
    end

    -- Priority 3: character facing (CFrame LookVector).
    if rootPart then
        local dir = getFlatVector((rootPart :: BasePart).CFrame.LookVector)
        if dir then
            sprintJumpMomentumDirection = dir
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] captureJumpMomentumDirection: LookVector fallback "
                    .. string.format("(%.2f,%.2f,%.2f)", dir.X, dir.Y, dir.Z)
                )
            end
            return
        end
    end

    -- All sources failed; no momentum direction available.
    sprintJumpMomentumDirection = nil
    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug("[MovementController] captureJumpMomentumDirection: no valid direction — momentum carry will be skipped")
    end
end

-- Destroys the LinearVelocity and Attachment instances created by
-- startSprintJumpLandingMomentum, if they exist.
-- Idempotent — safe to call when no momentum carry is active (no-op).
-- Does NOT call clearLandingMovementLock — callers manage lock state separately.
local function clearLandingMomentum()
    if landingMomentumVelocity then
        landingMomentumVelocity:Destroy()
        landingMomentumVelocity = nil
    end
    if landingMomentumAttachment then
        landingMomentumAttachment:Destroy()
        landingMomentumAttachment = nil
    end
    landingMomentumActive = false
end

-- Clears the landing movement lock and restores normal WalkSpeed.
-- Invalidates any pending task.delay unlock callbacks via landingLockToken.
-- Calls clearLandingMomentum to ensure LinearVelocity is always cleaned up.
-- Idempotent — safe to call when no lock is active (applySpeed is harmless).
local function clearLandingMovementLock()
    landingLockToken       += 1          -- invalidate any pending task.delay unlock
    isLandingMovementLocked = false
    clearLandingMomentum()
    -- Restore WalkSpeed to the phase/state-appropriate value.
    applySpeed()
    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug("[MovementController] Landing movement lock CLEARED → WalkSpeed restored")
    end
end

-- Sets isLandingMovementLocked = true and schedules an automatic unlock after `duration`
-- seconds via task.delay. The unlock only fires if the token still matches (i.e., no
-- manual clearLandingMovementLock() or respawn has already cleared it).
--
-- Also suppresses sprint/tactical-sprint state so the animation system does not
-- resume sprint clips while input is locked. WalkSpeed is zeroed immediately via applySpeed().
--
-- No-op when Constants.LANDING_MOVEMENT_LOCK_ENABLED ~= true.
-- Uses task.delay — never wait() or spawn().
local function startLandingMovementLock(duration: number)
    assert(typeof(duration) == "number", "[MovementController] startLandingMovementLock: duration must be a number")

    if Constants.LANDING_MOVEMENT_LOCK_ENABLED ~= true then return end

    isLandingMovementLocked = true
    landingLockToken        += 1
    local token              = landingLockToken   -- capture for closure

    -- Suppress sprint flags so animation/speed logic sees a non-sprint state.
    movementState.isSprinting         = false
    movementState.isTacticalSprinting = false
    isTacticalSprinting               = false

    -- Zero WalkSpeed immediately — applySpeed() now sees isLandingMovementLocked = true.
    applySpeed()

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] Landing movement lock START"
            .. " duration=" .. string.format("%.2fs", duration)
            .. " token=" .. tostring(token)
        )
    end

    -- Fallback unlock: fires if the animation Stopped callback did not unlock first.
    task.delay(duration, function()
        if landingLockToken ~= token then return end   -- already cleared by callback or respawn
        clearLandingMovementLock()
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] Landing movement lock TIMEOUT unlock (token=" .. tostring(token) .. ")")
        end
    end)
end

-- Creates a LinearVelocity on HumanoidRootPart that carries the character forward
-- in `direction` at SPRINT_JUMP_LANDING_MOMENTUM_SPEED for SPRINT_JUMP_LANDING_MOMENTUM_DURATION
-- seconds. Cleans up automatically after the duration via task.delay.
--
-- The carry provides the only motion during the lock window; player input is ignored because
-- WalkSpeed = 0 (set by startLandingMovementLock). This is NOT a slide system — no slide
-- animation, no camera tilt, no camera.CFrame writes, no fall damage.
--
-- No-op when Constants.SPRINT_JUMP_LANDING_MOMENTUM_ENABLED ~= true or currentRootPart is nil.
local function startSprintJumpLandingMomentum(direction: Vector3)
    assert(typeof(direction) == "Vector3", "[MovementController] startSprintJumpLandingMomentum: direction must be a Vector3")

    if Constants.SPRINT_JUMP_LANDING_MOMENTUM_ENABLED ~= true then return end
    local rootPart = currentRootPart
    if not rootPart then return end

    -- Clear any stale carry from a previous landing before creating new instances.
    clearLandingMomentum()

    local flatDir = getFlatVector(direction)
    if not flatDir then
        Logger.warn("[MovementController] startSprintJumpLandingMomentum: direction has no horizontal component — skipping carry")
        return
    end

    local att = Instance.new("Attachment")
    att.Name   = "BRLandingMomentumAttachment"
    att.Parent = rootPart :: BasePart
    landingMomentumAttachment = att

    local lv = Instance.new("LinearVelocity")
    lv.Name           = "BRLandingMomentumVelocity"
    lv.Attachment0    = att
    lv.RelativeTo     = Enum.ActuatorRelativeTo.World
    lv.MaxForce       = Constants.SPRINT_JUMP_LANDING_MOMENTUM_MAX_FORCE
    lv.VectorVelocity = (flatDir :: Vector3) * Constants.SPRINT_JUMP_LANDING_MOMENTUM_SPEED
    lv.Parent         = rootPart :: BasePart
    landingMomentumVelocity = lv

    landingMomentumActive = true

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] Sprint-jump momentum carry START"
            .. string.format(" dir=(%.2f,%.2f,%.2f)", (flatDir :: Vector3).X, (flatDir :: Vector3).Y, (flatDir :: Vector3).Z)
            .. " speed=" .. tostring(Constants.SPRINT_JUMP_LANDING_MOMENTUM_SPEED)
            .. " duration=" .. string.format("%.2fs", Constants.SPRINT_JUMP_LANDING_MOMENTUM_DURATION)
        )
    end

    task.delay(Constants.SPRINT_JUMP_LANDING_MOMENTUM_DURATION, function()
        clearLandingMomentum()
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] Sprint-jump momentum carry ENDED")
        end
    end)
end

-- ============================================================
-- Private helpers — Stage 3C: sprint-stop movement lock + momentum carry
-- ============================================================

-- Returns true when all conditions for playing SprintStop are met.
-- Returns false when: SPRINT_STOP_ENABLED is false, sprint was shorter than
-- SPRINT_STOP_MIN_SPRINT_DURATION, phase is not ACTIVE, player is crouching,
-- or landing movement lock is currently active.
local function shouldPlaySprintStop(sprintDuration: number): boolean
    if Constants.SPRINT_STOP_ENABLED ~= true then return false end
    if sprintDuration < Constants.SPRINT_STOP_MIN_SPRINT_DURATION then return false end
    if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return false end
    if movementState.isCrouching then return false end
    if isLandingMovementLocked then return false end
    return true
end

-- Destroys the active sprint-stop LinearVelocity and Attachment if present.
-- Idempotent — safe to call when no momentum is active.
-- Does NOT touch any other constraints or attachments on HumanoidRootPart.
local function clearSprintStopMomentum()
    if sprintStopMomentumVelocity then
        sprintStopMomentumVelocity:Destroy()
        sprintStopMomentumVelocity = nil
    end
    if sprintStopMomentumAttachment then
        sprintStopMomentumAttachment:Destroy()
        sprintStopMomentumAttachment = nil
    end
end

-- Clears the sprint-stop movement lock and restores normal WalkSpeed.
-- Increments sprintStopLockToken to invalidate any pending task.delay unlock callbacks.
-- Calls clearSprintStopMomentum() to destroy any active LinearVelocity.
-- Idempotent — safe to call when no lock is active (applySpeed is harmless).
local function clearSprintStopLock()
    sprintStopLockToken += 1
    isSprintStopPlaying  = false
    clearSprintStopMomentum()
    applySpeed()
    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug("[MovementController] SprintStop lock CLEARED → WalkSpeed restored")
    end
end

-- Creates a LinearVelocity on HumanoidRootPart carrying the character forward in
-- `direction` at SPRINT_STOP_MOMENTUM_SPEED for `duration` seconds.
-- Flattens direction to XZ and normalises before use.
-- No-op when SPRINT_STOP_MOMENTUM_ENABLED is false, direction is degenerate, or
-- currentRootPart is nil.
-- Does NOT write camera.CFrame. Uses the stored sprint direction only — player
-- cannot steer this momentum with A/D/W/S after it starts.
-- `duration` is passed explicitly by the caller so the carry can be matched to the
-- animation length (tactical sprint stop) or a fixed constant (other callers).
local function startSprintStopMomentum(direction: Vector3, duration: number)
    if Constants.SPRINT_STOP_MOMENTUM_ENABLED ~= true then return end
    local hrp = currentRootPart
    if hrp == nil then return end

    local flatDir = Vector3.new(direction.X, 0, direction.Z)
    if flatDir.Magnitude < 0.001 then return end
    local unitDir = flatDir.Unit

    -- Clear any stale carry before creating new instances.
    clearSprintStopMomentum()

    local att = Instance.new("Attachment")
    att.Name   = "BRSprintStopMomentumAttachment"
    att.Parent = hrp
    sprintStopMomentumAttachment = att

    local lv = Instance.new("LinearVelocity")
    lv.Name           = "BRSprintStopMomentumVelocity"
    lv.Attachment0    = att
    lv.RelativeTo     = Enum.ActuatorRelativeTo.World
    lv.MaxForce       = Constants.SPRINT_STOP_MOMENTUM_MAX_FORCE
    lv.VectorVelocity = unitDir * Constants.SPRINT_STOP_MOMENTUM_SPEED
    lv.Parent         = hrp
    sprintStopMomentumVelocity = lv

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] SprintStop momentum START"
            .. string.format(" dir=(%.2f,%.2f,%.2f)", unitDir.X, unitDir.Y, unitDir.Z)
            .. " speed=" .. tostring(Constants.SPRINT_STOP_MOMENTUM_SPEED)
            .. " duration=" .. string.format("%.2fs", duration)
        )
    end

    task.delay(duration, function()
        clearSprintStopMomentum()
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] SprintStop momentum carry ENDED")
        end
    end)
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
        or animationName == "RunForwardTest"
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
    elseif animationName == "LandingLight" then
        -- Stage 3A: light landing — plays at 1.15× so the clip completes quickly.
        return Constants.MOVEMENT_LANDING_LIGHT_SPEED_MULTIPLIER
    elseif animationName == "LandingMedium" then
        -- Stage 2O / Stage 3A: medium landing — sprint jumps and medium drops.
        return Constants.MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER
    elseif animationName == "LandingHeavy" then
        -- Stage 3A: heavy landing — high drops; plays at 0.9× for heavier feel.
        return Constants.MOVEMENT_LANDING_HEAVY_SPEED_MULTIPLIER
    elseif animationName == "TacticalSprintForward1"
        or animationName == "TacticalSprintForward2"
    then
        -- Stage 2P: tactical sprint forward clips play at the run animation speed.
        return Constants.MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER
    elseif animationName == "TacticalSprintStop" then
        -- Stage 2P: tactical sprint stop one-shot plays at 1.0× (no speed adjustment needed).
        return 1.0
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
-- Private helpers — Stage 3A: sprint FOV tween
-- ============================================================

-- Cancels any in-progress FOV tween and starts a new one toward `target`.
-- Never touches camera.CFrame. Never sets CameraType to Scriptable.
-- No-op if Constants.SPRINT_FOV_ENABLED is not true or camera is nil.
local function tweenCameraFov(target: number, duration: number)
	assert(typeof(target)   == "number", "[MovementController] tweenCameraFov: target must be a number")
	assert(typeof(duration) == "number", "[MovementController] tweenCameraFov: duration must be a number")
	if Constants.SPRINT_FOV_ENABLED ~= true then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	if currentFovTween then
		currentFovTween:Cancel()
		currentFovTween = nil
	end
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween     = TweenService:Create(camera, tweenInfo, { FieldOfView = target })
	tween:Play()
	currentFovTween = tween
	if Constants.MOVEMENT_ANIMATION_DEBUG then
		Logger.debug(
			"[MovementController] FOV → " .. target
			.. " over " .. string.format("%.2f", duration) .. "s"
		)
	end
end

-- Determines the correct target FOV based on current sprint/tactical-sprint
-- state and phase, then calls tweenCameraFov only if the target differs from
-- the last-requested value (dedup guard prevents per-frame tween restarts).
local function updateSprintFov()
	if Constants.SPRINT_FOV_ENABLED ~= true then return end
	local newTarget: number
	local phase = MatchController:GetPhase()
	if phase ~= Constants.Phase.ACTIVE then
		newTarget = Constants.DEFAULT_CAMERA_FOV
	elseif isTacticalSprinting then
		newTarget = Constants.TACTICAL_SPRINT_CAMERA_FOV
	elseif movementState.isSprinting
		and movementState.isMoving
		and not movementState.isCrouching
	then
		newTarget = Constants.SPRINT_CAMERA_FOV
	else
		newTarget = Constants.DEFAULT_CAMERA_FOV
	end
	if newTarget == targetFov then return end
	targetFov = newTarget
	local duration: number = if newTarget == Constants.DEFAULT_CAMERA_FOV
		then Constants.SPRINT_FOV_RESTORE_TIME
		else Constants.SPRINT_FOV_TWEEN_TIME
	tweenCameraFov(newTarget, duration)
end

-- ============================================================
-- Private helpers — Stage 2P: tactical sprint
-- ============================================================

-- Ends tactical sprint, resets speed/state, and plays the TacticalSprintStop
-- one-shot if enabled and the track is loaded.
-- • Clears isTacticalSprinting and movementState.isTacticalSprinting immediately.
-- • Stops the current movement animation (TacticalSprintForward1).
-- • Plays TacticalSprintStop (one-shot) if TACTICAL_SPRINT_STOP_ANIMATION_ENABLED and present.
--   The Stopped callback clears tacticalSprintStopConn when the one-shot finishes.
-- • updateMovementAnimation() gates on tacticalSprintStopConn ~= nil while the one-shot runs.
-- No-op if not currently tactical sprinting or if animation tracks are not loaded.
-- Does NOT modify movementState.isSprinting — callers manage that flag based on LeftShift state.
-- Defined here (after playMovementAnimation) so all helpers it calls are already in scope.
local function stopTacticalSprint()
    if not isTacticalSprinting then return end
    isTacticalSprinting               = false
    movementState.isTacticalSprinting = false
    tacticalSprintStartTime           = 0

    -- Disconnect any existing TacticalSprintStop Stopped callback first.
    clearTacticalSprintStopConnection()

    -- If tracks are not loaded (respawn edge case), just clear state and return.
    if next(animationTracks) == nil then return end

    -- Stop the TacticalSprintForward animation immediately.
    stopCurrentMovementAnimation()

    -- NOTE: We intentionally do NOT play TacticalSprintStop here.
    -- Animation + movement lock + momentum carry are ONLY applied via playSprintStopWithLock,
    -- which is called from sprintEndConn (Shift release) when the tactical sprint duration
    -- threshold is met.  Direction-change and crouch interruptions cut instantly with no
    -- stop animation, no lock, and no carry — this keeps the state machine simple and
    -- prevents the player being locked in place during an involuntary interruption.
    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug("[MovementController] Tactical sprint END (instant — no stop animation)")
    end

    -- Stage 3A: update FOV after tactical sprint ends.
    -- If the player is still holding Shift (isSprinting), updateSprintFov will
    -- transition from TACTICAL_SPRINT_CAMERA_FOV down to SPRINT_CAMERA_FOV.
    -- If Shift was released, it will restore to DEFAULT_CAMERA_FOV.
    updateSprintFov()
end

-- Stage 3C: Plays the SprintStop one-shot, locks WalkSpeed = 0, and optionally applies
-- a short LinearVelocity forward carry in `direction`.
-- Reuses Unarmed_TacticalSprintStop (same animation asset, already loaded).
-- Must be defined AFTER stopCurrentMovementAnimation() and playMovementAnimation() so
-- Lua can resolve those names — mirrors the stopTacticalSprint() placement rule.
--
-- Token-based stale-unlock prevention:
--   sprintStopLockToken is incremented here; the Stopped callback and fallback task.delay
--   each capture capturedToken and no-op if the token has changed (cleared by phase-exit,
--   respawn, or a second SprintStop start).
--
-- If the TacticalSprintStop track is absent (e.g. AR15 set has no stop clip), sprint
-- state is cleared normally and no lock or momentum is applied — graceful fallback.
local function playSprintStopWithLock(direction: Vector3?)
    local setName = getAnimationSetName()
    local stopKey = setName .. "_TacticalSprintStop"

    -- Graceful fallback: track not loaded (AR15 set, or animation failed to load).
    if animationTracks[stopKey] == nil then
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug(
                "[MovementController] SprintStop: track absent (" .. stopKey .. ") — clearing sprint state only"
            )
        end
        movementState.isSprinting = false
        applySpeed()
        return
    end

    -- Set lock state BEFORE applySpeed() so WalkSpeed is zeroed immediately.
    isSprintStopPlaying               = true
    movementState.isSprinting         = false
    movementState.isTacticalSprinting = false
    isTacticalSprinting               = false

    -- Increment token for stale-unlock prevention; capture for closures.
    sprintStopLockToken += 1
    local capturedToken = sprintStopLockToken

    -- Zero WalkSpeed — applySpeed() sees isSprintStopPlaying = true.
    applySpeed()

    -- Determine lock duration BEFORE starting momentum so the carry can be matched to
    -- the exact animation length (momentum lasts the full stop animation, not a fixed window).
    local stopTrack   = animationTracks[stopKey]
    local lockDuration = Constants.SPRINT_STOP_LOCK_FALLBACK_DURATION
    if stopTrack and stopTrack.Length > 0 then
        lockDuration = math.max(stopTrack.Length, Constants.SPRINT_STOP_LOCK_FALLBACK_DURATION)
    end

    -- Apply momentum carry for the full duration of the stop animation.
    if direction ~= nil then
        startSprintStopMomentum(direction, lockDuration)
    end

    -- Stop the current animation and play SprintStop one-shot.
    stopCurrentMovementAnimation()
    playMovementAnimation(stopKey)

    -- Early unlock: Stopped callback releases the lock when the animation finishes.
    -- Disconnect immediately to prevent stacking multiple Stopped connections if somehow
    -- called again while a previous SprintStop Stopped is still pending.
    if stopTrack then
        local conn: RBXScriptConnection
        conn = stopTrack.Stopped:Connect(function()
            conn:Disconnect()
            if sprintStopLockToken == capturedToken then
                clearSprintStopLock()
                if Constants.MOVEMENT_ANIMATION_DEBUG then
                    Logger.debug("[MovementController] SprintStop FINISHED (Stopped callback)")
                end
            end
        end)
    end

    -- Fallback timer: releases lock in case the Stopped callback never fires
    -- (e.g. animation interrupted externally or track destroyed mid-play).
    task.delay(lockDuration, function()
        if sprintStopLockToken ~= capturedToken then return end
        clearSprintStopLock()
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] SprintStop TIMEOUT unlock (token=" .. tostring(capturedToken) .. ")")
        end
    end)

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] SprintStop BEGIN (" .. stopKey .. ")"
            .. (direction and string.format(" dir=(%.2f,%.2f,%.2f)", direction.X, direction.Y, direction.Z) or " dir=nil")
            .. " lockDuration=" .. string.format("%.2fs", lockDuration)
        )
    end
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

-- Releases the active crouch bottom-hold by stopping the held track with a short fade.
-- Safe to call when no hold is active (no-op).
-- Does NOT stop unrelated locomotion tracks.
--
-- Stage 2Q fix: AdjustSpeed restoration before Stop was removed.
-- holdCrouchBottomPose() freezes the track via AdjustSpeed(0). Calling AdjustSpeed(normal)
-- immediately before Stop caused the frozen EnterCrouch to briefly resume playback from its
-- frozen-near-end position during the fade-out window, producing a visible animation flash.
-- Stopping at speed 0 lets the track fade out silently from the frozen frame — no resume.
local function clearCrouchBottomHold()
    local track = crouchHoldTrack
    if track then
        -- Stop directly at AdjustSpeed(0). Do NOT restore speed first; see comment above.
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

    -- ── Stage 2Q-D: Direct-blend path ────────────────────────────────────────
    -- When CROUCH_USE_ENTER_TRANSITION_ANIMATION is false, skip the EnterCrouch
    -- one-shot entirely and crossfade directly into the correct crouched pose.
    -- Only applies to crouch-enter; ExitCrouch always uses the original path below.
    if entering and not Constants.CROUCH_USE_ENTER_TRANSITION_ANIMATION then
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug(
                "[MovementController] playCrouchTransition: EnterCrouch SKIPPED"
                .. " (CROUCH_USE_ENTER_TRANSITION_ANIMATION=false) — direct blend"
            )
        end
        -- Clean up any lingering transition state (e.g. ExitCrouch was playing).
        clearCrouchTransitionConnection()
        crouchTransitionPlaying = false  -- clear flag so Heartbeat can immediately maintain pose
        clearCrouchBottomHold()
        -- Fade out whatever standing animation is playing.
        stopCurrentMovementAnimation()
        -- Hard-stop all stale crouch tracks so nothing bleeds through the fade-in.
        stopCrouchTracksExcept(nil)

        -- Pick the target crouched animation.
        -- Heartbeat takes over on the very next tick and refines direction if needed.
        local directKey: string?      = nil
        local directFade: number      = Constants.CROUCH_DIRECT_BLEND_FADE_TIME

        if movementState.isMoving then
            directFade = Constants.CROUCH_DIRECT_BLEND_MOVING_FADE_TIME
            -- Mark already-moving so the next Heartbeat tick skips CrouchWalkStart.
            wasMovingWhileCrouching = true

            -- Attempt directional selection (Unarmed + mouse-lock = 8-way).
            if setName == Constants.MOVEMENT_ANIMATION_SET_UNARMED and customMouseLocked then
                local dir = movementState.directionName
                if dir ~= "Idle" then
                    local dirKey = setName .. "_CrouchWalk" .. dir
                    if animationTracks[dirKey] ~= nil then
                        directKey = dirKey
                    end
                end
            end
            -- Fallback: CrouchWalkForward → CrouchWalk alias (covers mouse-lock OFF and AR15).
            if directKey == nil then
                local fwdKey   = setName .. "_CrouchWalkForward"
                local aliasKey = setName .. "_CrouchWalk"
                if animationTracks[fwdKey] ~= nil then
                    directKey = fwdKey
                elseif animationTracks[aliasKey] ~= nil then
                    directKey = aliasKey
                end
            end
        end

        -- When not moving (or no crouch-walk track found), prefer CrouchIdle.
        if directKey == nil then
            directFade = Constants.CROUCH_DIRECT_BLEND_FADE_TIME
            local idleKey = setName .. "_CrouchIdle"
            if animationTracks[idleKey] ~= nil then
                directKey = idleKey
            end
        end

        if directKey ~= nil then
            local directTrack = animationTracks[directKey]
            if directTrack then
                currentAnimationName = directKey
                local shortName = directKey:match("_(.+)$") or directKey
                directTrack:Play(directFade)
                directTrack:AdjustSpeed(getAnimationSpeedMultiplier(shortName))
                if Constants.MOVEMENT_ANIMATION_DEBUG then
                    Logger.debug(
                        "[MovementController] crouch direct-blend → " .. directKey
                        .. string.format(" (fade=%.2fs)", directFade)
                    )
                end
            end
        else
            -- No CrouchIdle or CrouchWalk available for this set: fall back to hold-pose.
            -- This path only fires for AR15 / non-Unarmed sets that lack both tracks.
            holdCrouchBottomPose()
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] crouch direct-blend: no idle/walk track for set '"
                    .. setName .. "' — holdCrouchBottomPose fallback"
                )
            end
        end
        return   -- direct blend done; Heartbeat maintains the pose from here
    end
    -- ─────────────────────────────────────────────────────────────────────────

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

    -- Stage 2Q+: hard-stop every other crouch track (EnterCrouch, ExitCrouch, CrouchIdle,
    -- CrouchWalk*, CrouchWalkStart) before playing the new transition clip.
    -- This is the critical missing call from Stage 2Q: without it, any previously fading
    -- CrouchIdle, ExitCrouch, or CrouchWalk track from a prior state continues to blend
    -- through the new transition's fade-in window (e.g. quick C-release → C-press cycles
    -- leave a fading CrouchIdle that bleeds into the next EnterCrouch).
    stopCrouchTracksExcept(key)

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
                        -- Stage 2Q+: stop all other crouch tracks before the walk animation.
                        stopCrouchTracksExcept(fwdKey)
                        playMovementAnimation(fwdKey)
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug(
                                "[MovementController] crouch: EnterCrouch done → " .. fwdKey
                                .. " (direction refined next Heartbeat)"
                            )
                        end
                    elseif animationTracks[aliasKey] ~= nil then
                        -- Stage 2Q+: stop all other crouch tracks before the walk animation.
                        stopCrouchTracksExcept(aliasKey)
                        playMovementAnimation(aliasKey)
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug("[MovementController] crouch: EnterCrouch done → " .. aliasKey)
                        end
                    else
                        holdCrouchBottomPose()
                    end
                else
                    -- Stage 2Q: prefer CrouchIdle directly over holdCrouchBottomPose().
                    -- holdCrouchBottomPose() calls track:Play(0) which restarts EnterCrouch
                    -- from frame 0 (one-frame flash) before seeking to near-end and freezing.
                    -- When CrouchIdle exists, transition straight into it — no hold-pose step.
                    local setName2       = getAnimationSetName()
                    local crouchIdleKey2 = setName2 .. "_CrouchIdle"
                    if animationTracks[crouchIdleKey2] ~= nil then
                        stopCrouchTracksExcept(crouchIdleKey2)
                        playMovementAnimation(crouchIdleKey2)
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug(
                                "[MovementController] crouch: EnterCrouch done → "
                                .. crouchIdleKey2 .. " (direct, no hold-pose)"
                            )
                        end
                    else
                        holdCrouchBottomPose()
                    end
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
    -- Stage 3B: clear landing movement lock and momentum on respawn.
    -- clearLandingMovementLock() increments the token (invalidates any pending task.delay
    -- unlock from the previous character), sets isLandingMovementLocked = false, calls
    -- clearLandingMomentum() to destroy LinearVelocity/Attachment, and calls applySpeed().
    -- At this point humanoid and currentRootPart are already set by setupCharacter(), so
    -- applySpeed() can write to the new Humanoid safely.
    clearLandingMovementLock()
    sprintJumpMomentumDirection = nil
    -- Stage 3A: clear new jump/drop tracking state on respawn.
    airborneStartY         = nil
    wasJumpingThisAirborne = false
    jumpedWhileSprinting   = false
    -- Stage 3A: restore FOV to default immediately on respawn (no tween — new character).
    if currentFovTween then
        currentFovTween:Cancel()
        currentFovTween = nil
    end
    targetFov = Constants.DEFAULT_CAMERA_FOV
    local _camOnRespawn = workspace.CurrentCamera
    if _camOnRespawn then
        _camOnRespawn.FieldOfView = Constants.DEFAULT_CAMERA_FOV
    end
    -- Stage 2P: clear tactical sprint state on respawn — do NOT play TacticalSprintStop here
    -- because the previous Animator may already be destroyed (same reason as crouchHoldTrack).
    isTacticalSprinting               = false
    movementState.isTacticalSprinting = false
    tacticalSprintStartTime           = 0
    lastShiftPressTime                = 0
    clearTacticalSprintStopConnection()
    -- Stage 3C: clear sprint-stop state on respawn.
    -- Do NOT call clearSprintStopLock() (which calls applySpeed()) here — the previous
    -- Animator may already be destroyed. Clear state directly and destroy constraints.
    isSprintStopPlaying         = false
    sprintStopLockToken        += 1   -- invalidate any pending task.delay unlock callbacks
    clearSprintStopMomentum()        -- destroy any active LinearVelocity/Attachment
    sprintStartTime             = nil
    lastSprintMomentumDirection = nil
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
    -- Stage 2R: reset sprint anim log guard so the first sprint after respawn re-logs.
    lastSprintAnimName     = ""
    -- Stage 3D: reset sprint body-facing mode log guard on respawn.
    lastSprintFacingMode              = ""
    -- Stage 3E: reset natural-AutoRotate sprint state on respawn.
    lastNaturalSprintAutoRotateActive = false
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

    -- Test run-forward clip — loaded alongside RunForward so both are always available.
    -- Active when MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION == true.
    -- Toggle the constant to switch without touching any logic code.
    if r6.Unarmed.RunForwardTest and r6.Unarmed.RunForwardTest ~= "" then
        toLoad["Unarmed_RunForwardTest"] = r6.Unarmed.RunForwardTest
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

    -- Stage 3A: LandingLight — one-shot; plays for normal jumps and small drops.
    if r6.Unarmed.LandingLight and r6.Unarmed.LandingLight ~= "" then
        toLoad["Unarmed_LandingLight"] = r6.Unarmed.LandingLight
    end
    -- Stage 2O / Stage 3A: LandingMedium — one-shot; reclassified to sprint jumps + medium drops.
    if r6.Unarmed.LandingMedium and r6.Unarmed.LandingMedium ~= "" then
        toLoad["Unarmed_LandingMedium"] = r6.Unarmed.LandingMedium
    end
    -- Stage 3A: LandingHeavy — one-shot; plays for high drops.
    if r6.Unarmed.LandingHeavy and r6.Unarmed.LandingHeavy ~= "" then
        toLoad["Unarmed_LandingHeavy"] = r6.Unarmed.LandingHeavy
    end

    -- Stage 2P: Tactical sprint animations — Unarmed set only.
    -- TacticalSprintForward1: primary forward clip (looped); selected when isTacticalSprinting.
    -- TacticalSprintForward2: alternate forward clip; loaded but not yet selected — deferred.
    -- TacticalSprintStop: one-shot stop clip; plays when tactical sprint ends.
    -- AR15 set has no tactical sprint IDs; the animationTracks[key] ~= nil guard in
    -- updateMovementAnimation() falls back to RunForward cleanly when the key is absent.
    if r6.Unarmed.TacticalSprintForward1 and r6.Unarmed.TacticalSprintForward1 ~= "" then
        toLoad["Unarmed_TacticalSprintForward1"] = r6.Unarmed.TacticalSprintForward1
    end
    if r6.Unarmed.TacticalSprintForward2 and r6.Unarmed.TacticalSprintForward2 ~= "" then
        toLoad["Unarmed_TacticalSprintForward2"] = r6.Unarmed.TacticalSprintForward2
    end
    if r6.Unarmed.TacticalSprintStop and r6.Unarmed.TacticalSprintStop ~= "" then
        toLoad["Unarmed_TacticalSprintStop"] = r6.Unarmed.TacticalSprintStop
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
            -- Stage 2P: TacticalSprintStop added to the one-shot list.
            if key:match("_EnterCrouch$") or key:match("_ExitCrouch$")
                or key:match("_CrouchWalkStart$")
                or key:match("_LandingLight$") or key:match("_LandingMedium$") or key:match("_LandingHeavy$")
                or key:match("_TacticalSprintStop$")
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

-- Returns the run-forward animation suffix for a given set name.
-- When MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION is true and Unarmed_RunForwardTest is loaded,
-- returns "RunForwardTest" instead of "RunForward". All other sets always return "RunForward".
-- Called from getSprintAnimationName() and any other code path that selects the run-forward clip.
local function getRunForwardSuffix(animSetName: string): string
    if Constants.MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION
        and animSetName == Constants.MOVEMENT_ANIMATION_SET_UNARMED
        and animationTracks[animSetName .. "_RunForwardTest"] ~= nil
    then
        return "RunForwardTest"
    end
    return "RunForward"
end

-- Stage 2R: Returns the short animation suffix (without set prefix) for the current normal sprint.
-- The caller prepends the animation set name: `setName .. "_" .. getSprintAnimationName(...)`.
-- Only resolves RunForwardLeft/RunForwardRight when customMouseLocked == true AND the track exists.
-- All other directions (Left, Right, Backward, BackwardLeft, BackwardRight, Forward, unknown)
-- return "RunForward" — no dedicated run-left/run-right/run-backward animations exist yet.
-- Warns once per missing directional sprint track via Logger.warn(); never spams per frame.
-- Does NOT call playMovementAnimation(). Does NOT write camera.CFrame.
--
-- missedSprintAnimWarned: module-level table, keyed by full track key.
-- Intentionally not reset on respawn — the same set of tracks is loaded each character.
local missedSprintAnimWarned: {[string]: boolean} = {}
local function getSprintAnimationName(animSetName: string, directionName: string): string
    assert(animSetName ~= nil,   "[MovementController] getSprintAnimationName: animSetName is required")
    assert(directionName ~= nil, "[MovementController] getSprintAnimationName: directionName is required")

    -- Without custom mouse lock, all sprint directions play RunForward (matches Stage 2L behavior).
    if not customMouseLocked then
        return getRunForwardSuffix(animSetName)
    end

    -- Custom mouse lock ON: resolve directional run clips when tracks are loaded.
    if directionName == "ForwardLeft" then
        local key = animSetName .. "_RunForwardLeft"
        if animationTracks[key] ~= nil then
            return "RunForwardLeft"
        else
            if not missedSprintAnimWarned[key] then
                missedSprintAnimWarned[key] = true
                Logger.warn("[MovementController] getSprintAnimationName: " .. key .. " not loaded — RunForward fallback")
            end
            return getRunForwardSuffix(animSetName)
        end
    end

    if directionName == "ForwardRight" then
        local key = animSetName .. "_RunForwardRight"
        if animationTracks[key] ~= nil then
            return "RunForwardRight"
        else
            if not missedSprintAnimWarned[key] then
                missedSprintAnimWarned[key] = true
                Logger.warn("[MovementController] getSprintAnimationName: " .. key .. " not loaded — RunForward fallback")
            end
            return getRunForwardSuffix(animSetName)
        end
    end

    -- Stage 3D: backward diagonals reuse forward-diagonal animations when available.
    -- Body will be rotated toward backward-left/right by faceCharacterTowardsDirection(),
    -- so RunForwardLeft/RunForwardRight plays in the correct world-space direction.
    if directionName == "BackwardLeft" then
        local key = animSetName .. "_RunForwardLeft"
        if animationTracks[key] ~= nil then
            return "RunForwardLeft"
        else
            if not missedSprintAnimWarned[key] then
                missedSprintAnimWarned[key] = true
                Logger.warn(
                    "[MovementController] getSprintAnimationName: "
                    .. key .. " not loaded — RunForward fallback (BackwardLeft)"
                )
            end
            return getRunForwardSuffix(animSetName)
        end
    end

    if directionName == "BackwardRight" then
        local key = animSetName .. "_RunForwardRight"
        if animationTracks[key] ~= nil then
            return "RunForwardRight"
        else
            if not missedSprintAnimWarned[key] then
                missedSprintAnimWarned[key] = true
                Logger.warn(
                    "[MovementController] getSprintAnimationName: "
                    .. key .. " not loaded — RunForward fallback (BackwardRight)"
                )
            end
            return getRunForwardSuffix(animSetName)
        end
    end

    -- Left, Right, Backward, Forward, or unclassified → RunForward (or RunForwardTest when toggled).
    -- Body is rotated toward movement direction by faceCharacterTowardsDirection(),
    -- so the run-forward clip plays in the correct world-space direction.
    -- Dedicated run-left/run-right/run-backward IDs are deferred to a future stage.
    return getRunForwardSuffix(animSetName)
end

-- ============================================================
-- Private helpers — Stage 3A: landing animation classification
-- ============================================================

-- Warn-once guard for playLandingAnimation: fires Logger.warn exactly once per
-- missing landing track name per session. Not reset on respawn (same tracks every char).
local playLandingAnimWarned: {[string]: boolean} = {}

-- Classifies a landing event into a landing animation name based on drop distance,
-- air time, and jump/sprint flags. Returns nil if no animation should play.
--
-- Priority:
--  1. dropDistance >= MOVEMENT_LANDING_HEAVY_MIN_DROP → "LandingHeavy"  (always, even for jumps)
--  2. wasJump == true and sprintJump == true and SPRINT_JUMP_USES_MEDIUM → "LandingMedium"
--     (SPRINT_JUMP_USES_MEDIUM = false by default — all intentional jumps resolve to LandingLight)
--  3. wasJump == true → "LandingLight"
--  4. dropDistance <= MOVEMENT_LANDING_LIGHT_MAX_DROP  → "LandingLight"   (walk-off drop)
--  5. dropDistance <= MOVEMENT_LANDING_MEDIUM_MAX_DROP → "LandingMedium"  (walk-off drop)
--  6. else → "LandingHeavy"                                               (walk-off drop)
local function getLandingAnimationName(
    dropDistance: number,
    airTime: number,
    wasJump: boolean,
    sprintJump: boolean
): string?
    assert(typeof(dropDistance) == "number",  "[MovementController] getLandingAnimationName: dropDistance must be a number")
    assert(typeof(airTime)      == "number",  "[MovementController] getLandingAnimationName: airTime must be a number")
    assert(typeof(wasJump)      == "boolean", "[MovementController] getLandingAnimationName: wasJump must be a boolean")
    assert(typeof(sprintJump)   == "boolean", "[MovementController] getLandingAnimationName: sprintJump must be a boolean")

    -- Heavy drop always wins regardless of jump context.
    if dropDistance >= Constants.MOVEMENT_LANDING_HEAVY_MIN_DROP then
        return "LandingHeavy"
    end

    -- Jump context: wasJump takes precedence over drop-distance thresholds.
    if wasJump then
        if sprintJump and Constants.MOVEMENT_LANDING_SPRINT_JUMP_USES_MEDIUM then
            return "LandingMedium"  -- sprint jump → medium
        end
        return "LandingLight"       -- normal jump → light
    end

    -- Pure drop (no jump): classify by distance.
    if dropDistance <= Constants.MOVEMENT_LANDING_LIGHT_MAX_DROP then
        return "LandingLight"
    elseif dropDistance <= Constants.MOVEMENT_LANDING_MEDIUM_MAX_DROP then
        return "LandingMedium"
    else
        return "LandingHeavy"
    end
end

-- Returns the full animation track key (e.g. "Unarmed_WalkForward") that
-- updateMovementAnimation would select for the current non-crouching standing state.
-- Pure read: does NOT call playMovementAnimation and does NOT modify any state.
-- Returns nil when: phase is not ACTIVE, tracks not loaded, or no valid key exists.
-- The selection logic mirrors updateMovementAnimation's standing/sprint branch exactly;
-- any future change to walk/sprint selection must be applied here too.
-- Placed here (before playLandingAnimation) so the landing Stopped callback can call it
-- without a forward-reference — mirrors the Stage 3B placement comment at line ~1137.
-- Also used by resumeStandingLocomotionAfterCrouch (Stage 2S — defined further below).
local function getDesiredStandingLocomotionKey(): string?
    if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return nil end
    if next(animationTracks) == nil then return nil end

    local setName = getAnimationSetName()

    -- Not moving: Idle.
    if not movementState.isMoving then
        local idleKey = setName .. "_Idle"
        if animationTracks[idleKey] ~= nil then
            return idleKey
        end
        return nil
    end

    -- Sprinting branch (mirrors updateMovementAnimation sprint block).
    if movementState.isSprinting then
        if isTacticalSprinting then
            local tsKey = setName .. "_TacticalSprintForward1"
            if animationTracks[tsKey] ~= nil then return tsKey end
            return setName .. "_" .. getRunForwardSuffix(setName)
        end
        local sprintSuffix = getSprintAnimationName(setName, movementState.directionName)
        return setName .. "_" .. sprintSuffix
    end

    -- Walking branch (mirrors updateMovementAnimation Unarmed + non-Unarmed selection).
    local canUseStrafe: boolean
    if Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK then
        canUseStrafe = isMouseLockedForStrafeAnimations()
    else
        canUseStrafe = true
    end

    local dirName = movementState.directionName

    if setName == Constants.MOVEMENT_ANIMATION_SET_UNARMED then
        if dirName == "Backward" then
            local k = "Unarmed_WalkBackward"
            return if animationTracks[k] ~= nil then k else "Unarmed_WalkForward"

        elseif dirName == "ForwardLeft" then
            local fl = "Unarmed_WalkForwardLeft"
            local l  = "Unarmed_WalkLeft"
            if animationTracks[fl] ~= nil then return fl end
            if canUseStrafe and animationTracks[l] ~= nil then return l end
            return "Unarmed_WalkForward"

        elseif dirName == "ForwardRight" then
            local fr = "Unarmed_WalkForwardRight"
            local r  = "Unarmed_WalkRight"
            if animationTracks[fr] ~= nil then return fr end
            if canUseStrafe and animationTracks[r] ~= nil then return r end
            return "Unarmed_WalkForward"

        elseif dirName == "BackwardLeft" then
            local bl  = "Unarmed_WalkBackwardLeft"
            local bwd = "Unarmed_WalkBackward"
            if animationTracks[bl] ~= nil then return bl end
            if animationTracks[bwd] ~= nil then return bwd end
            return "Unarmed_WalkForward"

        elseif dirName == "BackwardRight" then
            local br  = "Unarmed_WalkBackwardRight"
            local bwd = "Unarmed_WalkBackward"
            if animationTracks[br] ~= nil then return br end
            if animationTracks[bwd] ~= nil then return bwd end
            return "Unarmed_WalkForward"

        elseif canUseStrafe then
            if dirName == "Left" then
                local lk = "Unarmed_WalkLeft"
                return if animationTracks[lk] ~= nil then lk else "Unarmed_WalkForward"
            elseif dirName == "Right" then
                local rk = "Unarmed_WalkRight"
                return if animationTracks[rk] ~= nil then rk else "Unarmed_WalkForward"
            end
        end
        return "Unarmed_WalkForward"

    elseif canUseStrafe then
        if dirName == "Left" or dirName == "ForwardLeft" or dirName == "BackwardLeft" then
            local lk = setName .. "_WalkLeft"
            return if animationTracks[lk] ~= nil then lk else (setName .. "_WalkForward")
        elseif dirName == "Right" or dirName == "ForwardRight" or dirName == "BackwardRight" then
            local rk = setName .. "_WalkRight"
            return if animationTracks[rk] ~= nil then rk else (setName .. "_WalkForward")
        end
    end
    return setName .. "_WalkForward"
end

-- Plays the named landing animation (e.g. "LandingLight") for the current animation set.
-- Falls back to Unarmed set if the current set lacks the landing track.
-- Warns once (playLandingAnimWarned) if no track exists even after the Unarmed fallback.
-- Stops Falling and any in-flight landing animation before playing the new one.
-- Uses MOVEMENT_LANDING_ANIMATION_FADE_TIME (shorter than the normal fade) for quick blending.
-- Sets isLandingPlaying = true and connects a Stopped callback to clear it when done.
-- Does NOT freeze WalkSpeed or lock input — movement physics are unaffected.
-- Stage 3F: Stopped callback immediately crossfades to the correct locomotion animation
-- (when LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY is true) to prevent the one-frame
-- blank-pose flash between the landing one-shot ending and the next Heartbeat tick.
local function playLandingAnimation(animationName: string)
    assert(animationName ~= nil, "[MovementController] playLandingAnimation: animationName is required")

    local setName    = getAnimationSetName()
    local primaryKey = setName .. "_" .. animationName

    -- Resolve track: try current set first, fall back to Unarmed if set lacks the track.
    local track: AnimationTrack? = animationTracks[primaryKey]
    local usedKey: string        = primaryKey
    if track == nil and setName ~= Constants.MOVEMENT_ANIMATION_SET_UNARMED then
        local unarmedKey = Constants.MOVEMENT_ANIMATION_SET_UNARMED .. "_" .. animationName
        if animationTracks[unarmedKey] ~= nil then
            track   = animationTracks[unarmedKey]
            usedKey = unarmedKey
        end
    end

    if track == nil then
        if not playLandingAnimWarned[animationName] then
            playLandingAnimWarned[animationName] = true
            Logger.warn(
                "[MovementController] playLandingAnimation: no track for '"
                .. primaryKey .. "' (no Unarmed fallback either) — skipping"
            )
        end
        return
    end

    -- Disconnect any old landing Stopped callback (prevents spurious clearLandingConnection
    -- calls from a previously started but not-yet-finished landing animation).
    -- This sets isLandingPlaying = false; we re-set it true below after clearing.
    clearLandingConnection()

    -- Stop whatever is currently playing (typically Falling or idle).
    -- This also stops any landing track that is currentAnimationName-tracked.
    stopCurrentMovementAnimation()

    -- Determine speed multiplier for this landing tier.
    local speedMult: number
    if animationName == "LandingLight" then
        speedMult = Constants.MOVEMENT_LANDING_LIGHT_SPEED_MULTIPLIER
    elseif animationName == "LandingHeavy" then
        speedMult = Constants.MOVEMENT_LANDING_HEAVY_SPEED_MULTIPLIER
    else
        -- LandingMedium or unknown → use medium multiplier as safe default.
        speedMult = Constants.MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER
    end

    -- Play the track and set gate state.
    -- currentAnimationName is set so stopCurrentMovementAnimation() can stop it externally
    -- (phase exit, destroy, or a second landing before the first finishes).
    isLandingPlaying     = true
    currentAnimationName = usedKey

    track:Play(Constants.MOVEMENT_LANDING_ANIMATION_FADE_TIME)
    track:AdjustSpeed(speedMult)

    -- Connect Stopped callback: releases the gate when the one-shot finishes.
    -- clearLandingConnection() MUST be called before any external track:Stop() to prevent
    -- the callback from firing spuriously — mirrors clearCrouchTransitionConnection() pattern.
    landingConn = track.Stopped:Connect(function()
        clearLandingConnection()
        -- Stage 3B: if the animation finished before the fallback timer, release the
        -- movement lock early — but only when no momentum carry is still active.
        -- When momentum IS active, the carry's own task.delay (and startLandingMovementLock's
        -- timer) will clear the lock when the carry ends. Releasing early here would destroy
        -- the LinearVelocity before the carry duration completes.
        if isLandingMovementLocked and not landingMomentumActive then
            clearLandingMovementLock()
        end
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug("[MovementController] " .. animationName .. " finished → resuming locomotion")
        end
        -- Stage 3F: zero-gap landing exit — crossfade immediately to the correct locomotion
        -- animation so there is no blank-pose frame between the one-shot ending and the
        -- next Heartbeat tick. Mirrors the Stage 2S crouch-exit crossfade approach.
        -- If a second landing started before this callback ran, isLandingPlaying is already
        -- true again and we skip so we do not interrupt the new landing animation.
        if Constants.LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY and not isLandingPlaying then
            local desiredKey = getDesiredStandingLocomotionKey()
            if desiredKey ~= nil then
                playMovementAnimation(desiredKey)
            end
        end
    end)
end

-- ============================================================
-- Private helpers — Stage 2S: Zero-gap crouch-exit transition
-- Eliminates the brief default-pose flash that occurs when the player releases C
-- while moving or running. The fix is to crossfade directly from CrouchIdle/CrouchWalk
-- into the correct standing animation rather than waiting for ExitCrouch to finish.
-- getDesiredStandingLocomotionKey() is defined above playLandingAnimation (Stage 3F
-- placement) so the landing Stopped callback can also use it without a forward-reference.
-- ============================================================

-- Immediately resumes the correct standing locomotion animation after crouch exit.
-- Fades ALL crouch tracks out with `fadeTime` while simultaneously fading the target
-- standing animation IN with the same `fadeTime`. Because both Stop and Play use the same
-- duration, the combined animation weight is never zero — this prevents the brief flash of
-- the default Roblox neutral pose that occurs when all tracks momentarily have zero weight.
--
-- fadeTime: crossfade duration; shorter than MOVEMENT_ANIMATION_FADE_TIME for a snappier feel.
-- Called from:
--   • crouchEndConn moving path (skip ExitCrouch, direct blend into walk/run).
--   • crouchEndConn idle path when ExitCrouch track is absent (direct blend into Idle).
--   • ExitCrouch Stopped callback when CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY is true.
-- Must be defined after getDesiredStandingLocomotionKey and getAnimationSpeedMultiplier.
local function resumeStandingLocomotionAfterCrouch(fadeTime: number)
    assert(typeof(fadeTime) == "number",
        "[MovementController] resumeStandingLocomotionAfterCrouch: fadeTime must be a number")

    local desiredKey = getDesiredStandingLocomotionKey()

    -- Fade all crouch tracks out with fadeTime (not Stop(0)) so they decay concurrently
    -- with the incoming animation fading in — crossfade, not cut.
    for key, track in pairs(animationTracks) do
        if key:find("Crouch") then
            track:Stop(fadeTime)
        end
    end
    -- Clear currentAnimationName if it pointed at a crouch track (now fading out).
    if currentAnimationName ~= "" and currentAnimationName:find("Crouch") then
        currentAnimationName = ""
    end

    if desiredKey == nil then
        -- Phase not ACTIVE or no suitable standing track. Stop any remaining locomotion.
        if currentAnimationName ~= "" then
            local staleTrack = animationTracks[currentAnimationName]
            if staleTrack then
                staleTrack:Stop(fadeTime)
            end
            currentAnimationName = ""
        end
        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug(
                "[MovementController] resumeStandingLocomotionAfterCrouch:"
                .. " no standing key (phase not ACTIVE or tracks absent)"
            )
        end
        return
    end

    if Constants.MOVEMENT_ANIMATION_DEBUG then
        Logger.debug(
            "[MovementController] crouch exit → " .. desiredKey
            .. string.format(" (fade=%.2fs)", fadeTime)
        )
    end

    -- Don't restart the track if it is already playing (e.g. crouch entered and released
    -- within a single Heartbeat while walking — extremely fast tap).
    if currentAnimationName == desiredKey then
        local existingTrack = animationTracks[desiredKey]
        if existingTrack and existingTrack.IsPlaying then
            return
        end
    end

    -- Fade out any previous non-crouch animation at the same rate.
    if currentAnimationName ~= "" and currentAnimationName ~= desiredKey then
        local prevTrack = animationTracks[currentAnimationName]
        if prevTrack then
            prevTrack:Stop(fadeTime)
        end
    end

    local targetTrack = animationTracks[desiredKey]
    if not targetTrack then
        Logger.warn(
            "[MovementController] resumeStandingLocomotionAfterCrouch:"
            .. " track not loaded: " .. desiredKey
        )
        currentAnimationName = ""
        return
    end

    currentAnimationName = desiredKey
    targetTrack:Play(fadeTime)
    local shortName = desiredKey:match("_(.+)$") or desiredKey
    targetTrack:AdjustSpeed(getAnimationSpeedMultiplier(shortName))
end

-- Selects and triggers the correct movement animation for the current movementState.
-- Called every Heartbeat tick during ACTIVE phase.
-- Skipped if CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is false.
-- currentAnimationName guard inside playMovementAnimation prevents track restarts.
--
-- Stage 2A + 2C + 2F + 2G + 2H + 2I + 2J + 2L + 2R scope:
--   WalkLeft/WalkRight only play when canUseStrafeAnimations is true (mouse lock active).
--   WalkBackward plays for Backward regardless of mouse-lock state (Unarmed set only).
--   WalkForwardLeft/Right and WalkBackwardLeft/Right play for diagonals regardless of mouse lock (Unarmed only).
--   Sprint (mouse lock OFF or non-Forward directions): always plays RunForward.
--   Sprint ForwardLeft (mouse lock ON): RunForwardLeft if loaded, otherwise RunForward. (Stage 2R)
--   Sprint ForwardRight (mouse lock ON): RunForwardRight if loaded, otherwise RunForward. (Stage 2R)
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
    -- Stage 2P: do not interrupt TacticalSprintStop one-shot (tacticalSprintStopConn is non-nil
    -- only while the stop animation is playing — mirrors the landingConn "is-playing" pattern).
    if tacticalSprintStopConn ~= nil then return end
    -- Stage 3C: do not interrupt normal SprintStop one-shot (mirrors tacticalSprintStopConn pattern).
    if isSprintStopPlaying then return end

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
                -- Stage 2Q-D: gate CrouchWalkStart behind CROUCH_USE_CROUCH_WALK_START_ANIMATION.
                -- When false (default), skip the start one-shot and fall through to directional
                -- selection below. Set true to re-enable once a better start animation is provided.
                if Constants.CROUCH_USE_CROUCH_WALK_START_ANIMATION
                    and animationTracks[startKey] ~= nil
                    and not crouchWalkStartPlaying
                then
                    -- Disconnect callback BEFORE stopping CrouchIdle to prevent spurious events.
                    clearCrouchWalkStart()
                    if isHoldingCrouchBottomPose then
                        clearCrouchBottomHold()
                    end
                    stopCurrentMovementAnimation()  -- stops CrouchIdle if playing
                    -- Stage 2Q: stop any remaining stale crouch tracks before the start one-shot.
                    stopCrouchTracksExcept(startKey)
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
                -- CROUCH_USE_CROUCH_WALK_START_ANIMATION is false or track absent:
                -- fall through to directional selection immediately.
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
                -- Stage 2Q: stop any stale crouch tracks before the directional walk animation.
                stopCrouchTracksExcept(targetCrouchKey)
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
                -- Stage 2Q: stop any stale crouch tracks (e.g. a fading EnterCrouch) before
                -- playing CrouchIdle so they do not bleed through during the fade-in.
                stopCrouchTracksExcept(crouchIdleKey)
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
        -- Stage 2P: tactical sprint uses TacticalSprintForward1 exclusively.
        -- No directional selection; the character always plays the forward clip.
        -- Falls back to RunForward if the tactical sprint track is not loaded
        -- (e.g. AR15 set has no TacticalSprintForward1).
        if isTacticalSprinting then
            local tsKey = setName .. "_TacticalSprintForward1"
            if animationTracks[tsKey] ~= nil then
                playMovementAnimation(tsKey)
            else
                playMovementAnimation(setName .. "_" .. getRunForwardSuffix(setName))
            end
            return  -- no further direction selection while tactical sprinting
        end

        -- Stage 2R: directional sprint animation selection via getSprintAnimationName().
        -- With custom mouse lock ON: ForwardLeft → RunForwardLeft (if loaded), else RunForward.
        --                             ForwardRight → RunForwardRight (if loaded), else RunForward.
        -- With custom mouse lock OFF or any other direction: RunForward.
        animName = setName .. "_" .. getSprintAnimationName(setName, movementState.directionName)

        -- Debug: log once when the resolved sprint animation key changes (not every frame).
        if Constants.MOVEMENT_ANIMATION_DEBUG and animName ~= lastSprintAnimName then
            lastSprintAnimName = animName
            Logger.debug("[MovementController] sprint animation → " .. animName)
        end

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

-- Handles Humanoid state transitions to drive Falling (looped) and landing (one-shot).
-- Connected in setupCharacter() after loadMovementAnimations(), stored in stateChangedConn.
-- Disconnected at the top of loadMovementAnimations() on respawn and in destroy().
-- NOT stored in _connections — it is per-character and must be managed separately.
--
-- Stage 3A rework (replaces Stage 2O single-LandingMedium logic):
--
-- Jumping → capture airborneStartY + airStartTime; set wasJumpingThisAirborne + jumpedWhileSprinting.
--           Freefall handler fills in these values if Jumping never fires (ledge drop).
-- Freefall  → isFalling = true. If not already captured, sets airStartTime + airborneStartY.
--             Clears any in-flight landing animation via clearLandingConnection +
--             stopCurrentMovementAnimation. Plays Falling looped if the track exists.
-- Landed / Running → isFalling = false. Computes airTime and dropDistance.
--   Guards: (a) must have been in a tracked airborne state (isFalling or wasJumpingThisAirborne);
--           (b) not crouching (crouch branch owns the layer); (c) no active crouch transition.
--   For non-jump landings: additional guard airTime ≥ MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME
--   (pure tiny step-offs skip the landing animation). Jump landings are never skipped on airTime.
--   Calls getLandingAnimationName(dropDistance, airTime, wasJump, sprintJump) to classify tier.
--   Calls playLandingAnimation(animName) to play the one-shot.
-- All other states → ignored.
local function onHumanoidStateChanged(
    _oldState: Enum.HumanoidStateType,
    newState: Enum.HumanoidStateType
)
    if not Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED then return end
    if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then return end
    if next(animationTracks) == nil then return end

    local setName = getAnimationSetName()

    if newState == Enum.HumanoidStateType.Jumping then
        -- ── Player jumped ────────────────────────────────────────────────────
        -- Capture jump context before Freefall fires. Freefall handler will guard against
        -- double-setting these values.
        wasJumpingThisAirborne = true
        jumpedWhileSprinting   = movementState.isSprinting or movementState.isTacticalSprinting
        -- Stage 3B: capture the horizontal takeoff direction now, at jump entry, while the
        -- character's velocity and facing still reflect the sprint direction. Freefall entry
        -- is slightly later and may have different velocity if the character bumps geometry.
        if jumpedWhileSprinting then
            captureJumpMomentumDirection()
        else
            sprintJumpMomentumDirection = nil  -- ensure no stale direction from a previous sprint jump
        end
        -- Capture the highest Y position at jump launch (not at Freefall entry, which is
        -- a bit later and slightly lower). Used to compute drop on landing.
        local rootAtJump = currentRootPart
        if rootAtJump then
            airborneStartY = (rootAtJump :: BasePart).Position.Y
        end
        -- Record air start time at jump; Freefall handler leaves this unchanged if already set.
        airStartTime = os.clock()

    elseif newState == Enum.HumanoidStateType.Freefall then
        -- ── Entered Freefall ─────────────────────────────────────────────────
        if isFalling then return end   -- already falling; guard against double-fire
        isFalling = true

        -- Fill in airborne tracking if not already set by the Jumping handler
        -- (ledge drop: Freefall fires without a preceding Jumping state).
        if airStartTime == 0 then
            airStartTime = os.clock()
        end
        if airborneStartY == nil then
            local rootAtFall = currentRootPart
            if rootAtFall then
                airborneStartY = (rootAtFall :: BasePart).Position.Y
            end
        end

        -- Clear any in-flight landing animation from a previous landing that was
        -- interrupted (player landed and jumped again before the one-shot finished).
        -- clearLandingConnection() disconnects the Stopped callback; stopCurrentMovementAnimation
        -- stops the track if it is tracked as currentAnimationName.
        clearLandingConnection()
        stopCurrentMovementAnimation()

        -- Play Falling looped. Guard: track must exist (AR15 set has no Falling ID).
        local fallingKey = setName .. "_Falling"
        if animationTracks[fallingKey] ~= nil then
            playMovementAnimation(fallingKey)
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug("[MovementController] Falling BEGIN (" .. fallingKey .. ")")
            end
        end

    elseif newState == Enum.HumanoidStateType.Landed
        or newState == Enum.HumanoidStateType.Running
    then
        -- ── Landed or transitioned to Running from airborne ──────────────────
        -- Running fires when the character begins ground movement; Landed fires on any
        -- ground contact. Both signal the end of an airborne phase.
        -- Guard: must have been tracking an airborne state.
        if not isFalling and not wasJumpingThisAirborne then return end

        isFalling = false

        -- Compute air metrics.
        local airTime: number      = if airStartTime > 0 then (os.clock() - airStartTime) else 0
        local landingRootPart      = currentRootPart
        local dropDistance: number = 0
        if airborneStartY ~= nil and landingRootPart ~= nil then
            dropDistance = math.max(0, (airborneStartY :: number) - (landingRootPart :: BasePart).Position.Y)
        end

        -- Capture and clear jump-tracking state before any early returns.
        local wasJump  = wasJumpingThisAirborne
        local sprintJp = jumpedWhileSprinting
        wasJumpingThisAirborne = false
        jumpedWhileSprinting   = false
        airborneStartY         = nil
        airStartTime           = 0

        -- Stop the Falling looped track (if still playing as currentAnimationName).
        local fallingKey = setName .. "_Falling"
        if currentAnimationName == fallingKey then
            stopCurrentMovementAnimation()
        elseif animationTracks[fallingKey] ~= nil
            and (animationTracks[fallingKey] :: AnimationTrack).IsPlaying
        then
            (animationTracks[fallingKey] :: AnimationTrack):Stop(Constants.MOVEMENT_ANIMATION_FADE_TIME)
        end

        -- Guard: skip landing animation when crouching or in a crouch transition.
        -- The crouch branch owns the animation layer — playing a landing on top would conflict.
        if movementState.isCrouching or crouchTransitionPlaying then
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] Landing skipped"
                    .. " (crouching=" .. tostring(movementState.isCrouching)
                    .. " transition=" .. tostring(crouchTransitionPlaying) .. ")"
                )
            end
            return
        end

        -- Guard: for non-jump landings (pure drops), skip if air time is too short.
        -- Jump landings are always classified regardless of air time.
        if not wasJump and airTime < Constants.MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME then
            if Constants.MOVEMENT_ANIMATION_DEBUG then
                Logger.debug(
                    "[MovementController] Landing skipped"
                    .. " (pure drop, airTime=" .. string.format("%.2f", airTime) .. "s < MIN_AIR_TIME)"
                )
            end
            return
        end

        -- Classify landing tier and play.
        local animName = getLandingAnimationName(dropDistance, airTime, wasJump, sprintJp)
        if animName == nil then return end

        if Constants.MOVEMENT_ANIMATION_DEBUG then
            Logger.debug(
                "[MovementController] Landing: " .. animName
                .. " (drop=" .. string.format("%.1f", dropDistance) .. " studs"
                .. " airTime=" .. string.format("%.2f", airTime) .. "s"
                .. " wasJump=" .. tostring(wasJump)
                .. " sprintJump=" .. tostring(sprintJp) .. ")"
            )
        end

        playLandingAnimation(animName)

        -- Stage 3B: apply movement lock (and optional sprint-jump momentum carry) per tier.
        -- Lock state is managed by token; cleanup happens in clearLandingMovementLock().
        -- Capture and nil-out sprintJumpMomentumDirection before any early returns so we
        -- never carry a stale direction into the next landing event.
        local capturedMomentumDir = sprintJumpMomentumDirection
        sprintJumpMomentumDirection = nil

        if animName == "LandingLight" then
            -- LandingLight: no movement lock. Movement flow is preserved for normal jumps/drops.
            -- No-op — do nothing, capturedMomentumDir is discarded.

        elseif animName == "LandingMedium" then
            if Constants.LANDING_MEDIUM_LOCKS_MOVEMENT then
                if wasJump and sprintJp then
                    -- Sprint-jump medium landing: lock + LinearVelocity carry.
                    startLandingMovementLock(Constants.SPRINT_JUMP_LANDING_MOMENTUM_DURATION)
                    if capturedMomentumDir ~= nil then
                        startSprintJumpLandingMomentum(capturedMomentumDir)
                    else
                        -- Direction capture failed at jump time; lock only, no carry.
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug("[MovementController] Sprint-jump momentum: direction unavailable — lock only")
                        end
                    end
                else
                    -- Non-sprint-jump medium landing: lock only (pure drop or normal jump).
                    startLandingMovementLock(Constants.LANDING_MEDIUM_LOCK_FALLBACK_DURATION)
                end
            end

        elseif animName == "LandingHeavy" then
            if Constants.LANDING_HEAVY_LOCKS_MOVEMENT then
                -- Heavy landing: lock only, no momentum carry regardless of jump context.
                startLandingMovementLock(Constants.LANDING_HEAVY_LOCK_FALLBACK_DURATION)
            end
        end
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

-- ── Tactical sprint (Stage 2P) ─────────────────────────────────────────────────

-- Returns true while a tactical sprint is active (double-tap LeftShift detected).
-- GunController reads this to block firing and reloading when TACTICAL_SPRINT_BLOCKS_GUN_USE
-- is true. Returns false after Shift release, direction change, crouch, or phase exit.
function MovementController.IsTacticalSprinting(): boolean
    return isTacticalSprinting
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
    -- Stage 3B: clear landing movement lock and momentum on destroy.
    -- humanoid is still valid at this point (nil'd later in destroy()), so applySpeed()
    -- inside clearLandingMovementLock() may write to it; that is safe and correct.
    clearLandingMovementLock()
    sprintJumpMomentumDirection = nil
    -- Stage 3C: clear sprint-stop lock and momentum on destroy.
    -- clearSprintStopLock() calls applySpeed() — humanoid still valid here, safe and correct.
    clearSprintStopLock()
    sprintStartTime             = nil
    lastSprintMomentumDirection = nil
    -- Stage 3A: clear new jump/drop tracking state.
    airborneStartY         = nil
    wasJumpingThisAirborne = false
    jumpedWhileSprinting   = false
    -- Stage 3A: cancel any in-flight FOV tween and restore default FieldOfView immediately.
    if currentFovTween then
        currentFovTween:Cancel()
        currentFovTween = nil
    end
    targetFov = Constants.DEFAULT_CAMERA_FOV
    local _camOnDestroy = workspace.CurrentCamera
    if _camOnDestroy then
        _camOnDestroy.FieldOfView = Constants.DEFAULT_CAMERA_FOV
    end
    -- Stage 2P: clear tactical sprint state without playing TacticalSprintStop (destroy path).
    isTacticalSprinting               = false
    movementState.isTacticalSprinting = false
    tacticalSprintStartTime           = 0
    lastShiftPressTime                = 0
    clearTacticalSprintStopConnection()
    clearCrouchBottomHold()
    -- Stop the active animation if still playing, then clear track references.
    stopCurrentMovementAnimation()
    table.clear(animationTracks)
    currentAnimationName      = ""
    rigTypeWarned             = false
    equippedWeaponName        = nil
    lastAnimationSet          = ""
    lastStrafeBlockedState    = false
    lastSprintAnimName        = ""   -- Stage 2R
    lastSprintFacingMode              = ""    -- Stage 3D
    lastNaturalSprintAutoRotateActive = false -- Stage 3E
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
        -- Stage 3A: FOV was already restored to DEFAULT directly in loadMovementAnimations
        -- (no tween on respawn — new character). Reset targetFov here so the first
        -- sprint after respawn triggers a fresh tween instead of seeing "no change".
        targetFov = Constants.DEFAULT_CAMERA_FOV
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
            -- Stage 2Q+: hard-stop all remaining crouch tracks (EnterCrouch, ExitCrouch,
            -- CrouchIdle, CrouchWalk*) so no fading crouch weight persists across phase
            -- transitions. stopCurrentMovementAnimation() only stops currentAnimationName;
            -- any previously-faded crouch track not tracked there is caught here.
            stopCrouchTracksExcept(nil)
            -- Stage 2O: reset falling/landing state so re-entry to ACTIVE starts clean.
            isFalling = false
            clearLandingConnection()
            -- Stage 3B: clear movement lock and momentum on phase exit.
            -- clearLandingMovementLock() increments token (invalidates task.delay), sets
            -- isLandingMovementLocked = false, and calls clearLandingMomentum() which destroys
            -- any active LinearVelocity/Attachment on HumanoidRootPart.
            clearLandingMovementLock()
            sprintJumpMomentumDirection = nil
            -- Stage 3C: clear sprint-stop lock on phase exit.
            -- clearSprintStopLock() increments token (invalidates task.delay), sets
            -- isSprintStopPlaying = false, and destroys any sprint-stop LinearVelocity.
            -- This ensures WalkSpeed is never left stuck at 0 across phase transitions.
            clearSprintStopLock()
            sprintStartTime             = nil
            lastSprintMomentumDirection = nil
            -- Stage 3A: clear jump/drop tracking state on phase exit.
            airborneStartY         = nil
            wasJumpingThisAirborne = false
            jumpedWhileSprinting   = false
            -- Stage 3A: restore FOV immediately on phase exit — do not wait for the next
            -- Heartbeat. Tween to DEFAULT so the transition is visible but quick.
            if Constants.SPRINT_FOV_ENABLED then
                if targetFov ~= Constants.DEFAULT_CAMERA_FOV then
                    targetFov = Constants.DEFAULT_CAMERA_FOV
                    tweenCameraFov(Constants.DEFAULT_CAMERA_FOV, Constants.SPRINT_FOV_RESTORE_TIME)
                end
            end
            -- Stage 2P: clear tactical sprint state on phase exit.
            -- Do NOT call stopTacticalSprint() here — it would try to play TacticalSprintStop
            -- while the phase is leaving ACTIVE (the animation would have no visible effect and
            -- the character is about to freeze). Clear state directly instead.
            if isTacticalSprinting then
                isTacticalSprinting               = false
                movementState.isTacticalSprinting = false
                tacticalSprintStartTime           = 0
                clearTacticalSprintStopConnection()
                stopCurrentMovementAnimation()
            end
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

            -- Stage 2P: double-tap LeftShift detection.
            -- Compare this press against the previous one. If within the double-tap window
            -- and the player is already moving forward, start tactical sprint.
            local now = os.clock()
            if Constants.TACTICAL_SPRINT_ENABLED
                and not isTacticalSprinting
                and movementState.isMoving
                and (now - lastShiftPressTime) <= Constants.TACTICAL_SPRINT_DOUBLE_TAP_WINDOW
            then
                -- Forward dot check: MoveDirection must point sufficiently toward camera forward.
                local hum2 = humanoid
                if hum2 then
                    local cam     = workspace.CurrentCamera
                    local look    = cam.CFrame.LookVector
                    local flat    = Vector3.new(look.X, 0, look.Z)
                    local fwdDot: number = 0
                    if flat.Magnitude > 0.01 then
                        fwdDot = hum2.MoveDirection:Dot(flat.Unit)
                    end
                    if fwdDot >= Constants.TACTICAL_SPRINT_MIN_FORWARD_DOT then
                        isTacticalSprinting               = true
                        movementState.isTacticalSprinting = true
                        tacticalSprintStartTime           = os.clock()
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug(
                                "[MovementController] Tactical sprint START"
                                .. " (fwdDot=" .. string.format("%.2f", fwdDot) .. ")"
                            )
                        end
                    end
                end
            end
            -- Always update lastShiftPressTime AFTER the check so this press becomes
            -- the "previous press" for the next InputBegan event.
            lastShiftPressTime = now

            movementState.isSprinting = true
            -- Stage 3C: record sprint start time for SPRINT_STOP_MIN_SPRINT_DURATION gate.
            sprintStartTime = os.clock()
            -- Stage 3C: cancel any in-flight SprintStop if the player re-sprints immediately.
            if isSprintStopPlaying then
                clearSprintStopLock()
            end
            applySpeed()
            -- Stage 3A: start sprint FOV tween immediately on sprint start.
            updateSprintFov()
        end
    )
    table.insert(_connections, sprintBeginConn)

    local sprintEndConn = UserInputService.InputEnded:Connect(
        function(input: InputObject, _gp: boolean)
            if input.KeyCode ~= Enum.KeyCode.LeftShift then return end
            if not movementState.isSprinting then return end

            -- Stage 2P/3C: Shift release ends sprint.
            -- Tactical sprint: full stop (animation + lock + carry) only when the player has been
            --   tactical sprinting for at least TACTICAL_SPRINT_STOP_MIN_DURATION seconds.
            --   Below that threshold, or for regular sprint, state is cleared instantly with no animation.
            if isTacticalSprinting then
                local tacticalDuration = tacticalSprintStartTime > 0
                    and (os.clock() - tacticalSprintStartTime)
                    or 0

                -- Clear tactical sprint tracking state first (before playSprintStopWithLock so
                -- the fallback path in that function never leaves isTacticalSprinting stuck true).
                isTacticalSprinting               = false
                movementState.isTacticalSprinting = false
                tacticalSprintStartTime           = 0
                clearTacticalSprintStopConnection()

                if tacticalDuration >= Constants.TACTICAL_SPRINT_STOP_MIN_DURATION then
                    -- Long tactical sprint: full stop with animation + lock + carry.
                    -- playSprintStopWithLock clears movementState.isSprinting and calls applySpeed().
                    playSprintStopWithLock(lastSprintMomentumDirection)
                else
                    -- Short tactical sprint (under threshold): instant clear, no animation or lock.
                    movementState.isSprinting = false
                    applySpeed()
                end
            else
                -- Regular sprint end: no animation, no lock, no carry.
                movementState.isSprinting = false
                applySpeed()
            end
            sprintStartTime = nil
            -- Stage 3A: restore FOV immediately on sprint end.
            updateSprintFov()
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

            -- Stage 2P/3C: crouch cancels tactical sprint instantly (no stop animation).
            -- stopTacticalSprint() is now a pure state-clear — it stops TacticalSprintForward
            -- and clears all tactical sprint flags without playing TacticalSprintStop.
            -- Animation + lock + carry only fire via playSprintStopWithLock (Shift-release path).
            -- updateSprintFov() is called internally by stopTacticalSprint().
            if isTacticalSprinting then
                stopTacticalSprint()
            end
            -- Stage 3C: crouch cancels any in-flight SprintStop; clear sprint timer too.
            -- SprintStop should not play when entering crouch — player chose to crouch.
            if isSprintStopPlaying then
                clearSprintStopLock()
            end
            sprintStartTime = nil
            movementState.isCrouching = true
            movementState.isSprinting = false
            applySpeed()
            -- Stage 3A: crouch clears sprint → restore FOV immediately.
            updateSprintFov()
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
            -- holdCrouchBottomPose() does not fire after we have already exited crouch.
            clearCrouchTransitionConnection()
            crouchTransitionPlaying = false
            -- Release the hold pose if it was active.
            clearCrouchBottomHold()
            -- Disconnect CrouchWalkStart if still in-flight; reset first-movement tracking.
            if crouchWalkStartPlaying then
                clearCrouchWalkStart()
            end
            wasMovingWhileCrouching = false

            -- ── Stage 2S: zero-gap crouch-exit transition ─────────────────────────
            if Constants.CROUCH_ZERO_GAP_TRANSITIONS_ENABLED then
                if movementState.isMoving
                    and not Constants.CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING
                then
                    -- Moving: skip ExitCrouch, blend directly into walk/run/sprint.
                    -- resumeStandingLocomotionAfterCrouch fades crouch tracks out and the
                    -- standing animation in with the same fadeTime — combined weight never
                    -- reaches zero so the default Roblox pose cannot flash through.
                    if Constants.MOVEMENT_ANIMATION_DEBUG then
                        Logger.debug(
                            "[MovementController] crouch exit: moving →"
                            .. " ExitCrouch SKIPPED (CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING=false)"
                            .. " — direct blend into standing locomotion"
                        )
                    end
                    resumeStandingLocomotionAfterCrouch(Constants.CROUCH_EXIT_DIRECT_BLEND_FADE_TIME)
                else
                    -- Not moving (or CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = true):
                    -- play ExitCrouch one-shot, then immediately start Idle when it finishes.
                    local sn        = getAnimationSetName()
                    local exitKey   = sn .. "_ExitCrouch"
                    local exitTrack = animationTracks[exitKey]
                    if exitTrack then
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug(
                                "[MovementController] crouch exit: not moving →"
                                .. " ExitCrouch (" .. exitKey .. ") → Idle"
                            )
                        end
                        -- Stop remaining crouch tracks but keep ExitCrouch playing cleanly.
                        stopCrouchTracksExcept(exitKey)
                        stopCurrentMovementAnimation()
                        crouchTransitionPlaying = true
                        currentAnimationName    = exitKey
                        exitTrack:Play(Constants.MOVEMENT_ANIMATION_FADE_TIME)
                        exitTrack:AdjustSpeed(getAnimationSpeedMultiplier("ExitCrouch"))
                        -- clearCrouchTransitionConnection() already called above.
                        crouchTransitionConn = exitTrack.Stopped:Connect(function()
                            clearCrouchTransitionConnection()
                            crouchTransitionPlaying = false
                            if currentAnimationName == exitKey then
                                currentAnimationName = ""
                            end
                            if Constants.MOVEMENT_ANIMATION_DEBUG then
                                Logger.debug(
                                    "[MovementController] crouch exit: ExitCrouch done →"
                                    .. " resuming standing locomotion"
                                )
                            end
                            if Constants.CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY then
                                -- Start Idle immediately — no Heartbeat gap.
                                resumeStandingLocomotionAfterCrouch(
                                    Constants.CROUCH_EXIT_IDLE_BLEND_FADE_TIME
                                )
                            end
                            -- If false, Heartbeat resumes on the next tick (legacy gap may reappear).
                        end)
                    else
                        -- No ExitCrouch track for this set: blend directly into Idle.
                        if Constants.MOVEMENT_ANIMATION_DEBUG then
                            Logger.debug(
                                "[MovementController] crouch exit: no ExitCrouch track →"
                                .. " direct blend into standing locomotion"
                            )
                        end
                        resumeStandingLocomotionAfterCrouch(
                            Constants.CROUCH_EXIT_IDLE_BLEND_FADE_TIME
                        )
                    end
                end
            else
                -- Legacy path (CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = false).
                -- Play ExitCrouch via playCrouchTransition; Heartbeat takes over when done.
                playCrouchTransition(false)
            end
            -- ─────────────────────────────────────────────────────────────────────
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

        -- Stage 2P: sustain or end tactical sprint based on movement direction each frame.
        -- If the player stops moving or drifts off-forward, tactical sprint ends automatically.
        -- applySpeed() is called again after the state change so WalkSpeed reflects the
        -- new non-tactical-sprint mode immediately (no one-frame speed overshoot).
        if isTacticalSprinting then
            if not movementState.isMoving then
                stopTacticalSprint()
                applySpeed()
            else
                local cam    = workspace.CurrentCamera
                local look   = cam.CFrame.LookVector
                local flat   = Vector3.new(look.X, 0, look.Z)
                local fwdDot: number = 0
                if flat.Magnitude > 0.01 then
                    fwdDot = moveDir:Dot(flat.Unit)
                end
                if fwdDot < Constants.TACTICAL_SPRINT_MIN_FORWARD_DOT then
                    stopTacticalSprint()
                    applySpeed()
                end
            end
        end

        -- Stage 3C: update lastSprintMomentumDirection each frame while sprinting.
        -- Captures the most recent XZ direction so SprintStop / tactical sprint stop has an
        -- accurate carry vector. Updated during both normal and tactical sprint; gated only on
        -- SprintStop not already in-flight so the direction stays fresh for the stop carry.
        if movementState.isSprinting and not isSprintStopPlaying then
            local hrp = currentRootPart
            if hrp then
                local vel     = hrp.AssemblyLinearVelocity
                local flatVel = Vector3.new(vel.X, 0, vel.Z)
                if flatVel.Magnitude >= Constants.SPRINT_STOP_MIN_HORIZONTAL_SPEED then
                    -- Use actual velocity for the most physically accurate direction.
                    lastSprintMomentumDirection = flatVel.Unit
                else
                    -- Velocity too low (just started sprinting or on a slope); use input direction.
                    local md = hum.MoveDirection
                    if md.Magnitude > Constants.MOVEMENT_DIRECTION_DEADZONE then
                        lastSprintMomentumDirection = Vector3.new(md.X, 0, md.Z)
                    else
                        -- No input direction; fall back to camera look vector.
                        local look = workspace.CurrentCamera.CFrame.LookVector
                        lastSprintMomentumDirection = Vector3.new(look.X, 0, look.Z)
                    end
                end
            end
        end

        -- Stage 2A: select and play the correct walk/run animation.
        updateMovementAnimation()

        -- Stage 3A: update sprint FOV every frame. updateSprintFov() gates internally on
        -- targetFov so redundant tweens are never started. Also called directly from sprint/
        -- crouch input handlers for immediate response — this call covers continuous state.
        updateSprintFov()
    end)
    table.insert(_connections, heartbeatConn)

    Logger.debug("[MovementController] Ready (Stage 1–3C: DevMouseLock, CAS 3000, LeftControl toggle, reapply-frame, facing-yaw, zoom-limits 4–14, mouse-lock-cam 8+offset, Unarmed directional/diagonals+new IDs, idle, hold-to-crouch, crouch-bottom-hold, CrouchWalk, sprint→directional(2R), CrouchIdle, CrouchWalkStart, Falling+LandingLight/Medium/Heavy, TacticalSprint double-tap+ramp+stop, sprintFOV+landingClassification, landingMovementLock+sprintJumpMomentum, sprintStopLock+momentumCarry)")
end

return MovementController
