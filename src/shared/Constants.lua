--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > Constants
--
-- Single source of truth for all game-wide numbers and enums.
-- Change values here to tune the game — never hardcode these in other scripts.

local Constants = {}

-- ============================================================
-- Phase enum
-- Use these instead of raw strings like "lobby" or "active".
-- Example: if currentPhase == Constants.Phase.ACTIVE then ...
-- ============================================================
Constants.Phase = {
    LOBBY    = "LOBBY",    -- server is waiting for enough players
    PREP     = "PREP",     -- brief countdown before the round starts (players read objectives)
    ACTIVE   = "ACTIVE",   -- round is live, players can fight and plant anchors
    RESULTS  = "RESULTS",  -- round ended, scores are shown before the next round
    MATCHEND = "MATCHEND", -- all rounds complete, overall match winner is displayed
}

-- ============================================================
-- Match settings
-- ============================================================
Constants.MAX_ROUNDS   = 5  -- number of rounds per match
Constants.MIN_PLAYERS  = 1  -- minimum players needed before lobby countdown starts

-- ============================================================
-- Phase durations (in seconds)
-- Adjust these to change how long each phase lasts.
-- ============================================================
Constants.LOBBY_TIME        = 2   -- how long to wait in lobby after MIN_PLAYERS is reached
Constants.PREP_TIME         = 2   -- how long the prep countdown lasts before active play
Constants.ACTIVE_TIME       = 180 -- how long each active round lasts (3 minutes)
Constants.RESULTS_TIME      = 10  -- how long results are shown between rounds
Constants.RESULTS_DURATION  = 10  -- alias used by MatchService for the per-round end screen
Constants.MATCHEND_DURATION = 15  -- how long the match-end screen is shown before the next lobby

-- ============================================================
-- Crouch hold behavior (Stage 2I — hold-to-crouch)
-- ============================================================
Constants.CROUCH_HOLD_KEY = Enum.KeyCode.C  -- key held to enter crouch; release to exit

-- When true, MovementController holds the final frame of EnterCrouch while crouched
-- and not moving (bottom-pose hold via AdjustSpeed(0) + TimePosition near clip end).
-- When false, no visual hold is applied and the character reverts to standing idle.
Constants.CROUCH_HOLD_BOTTOM_POSE_ENABLED = true

-- Seconds from the end of the EnterCrouch clip at which the hold TimePosition is set.
-- e.g. 0.05 means the track pauses at (clip.Length - 0.05) seconds.
-- Guards against setting TimePosition exactly at Length which can snap to frame 0
-- on some Roblox versions.
Constants.CROUCH_TRANSITION_MIN_HOLD_TIME = 0.05

-- Fallback TimePosition (seconds) used when EnterCrouch.Length == 0
-- (animation not yet loaded or zero-length clip). Must be >= 0.
Constants.CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98

-- When false, the EnterCrouch one-shot animation is skipped entirely on crouch press.
-- The character crossfades directly from the current idle/walk/run pose into CrouchIdle
-- (if not moving) or the appropriate CrouchWalk* animation (if moving).
-- Set true to re-enable the transition clip once a better EnterCrouch asset is provided.
-- Default: false — the bundled EnterCrouch asset bends the character forward through bad
-- intermediate frames before settling, producing an ugly transition. Disabled until a
-- replacement asset is supplied.
Constants.CROUCH_USE_ENTER_TRANSITION_ANIMATION = false

-- Crossfade duration (seconds) for the direct-blend when entering crouch and NOT moving.
-- Applied to the CrouchIdle (or fallback) fade-in. Shorter than MOVEMENT_ANIMATION_FADE_TIME
-- (0.15) for a snappier, less floaty feel.
Constants.CROUCH_DIRECT_BLEND_FADE_TIME = 0.12

-- Crossfade duration (seconds) for the direct-blend when entering crouch while MOVING.
-- Slightly shorter than CROUCH_DIRECT_BLEND_FADE_TIME to feel immediate and snappy.
Constants.CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.10

-- When false, the CrouchWalkStart one-shot is skipped when the player first moves while
-- crouched. The character blends directly from CrouchIdle into the directional CrouchWalk
-- without a start-of-movement transition clip.
-- Set true to re-enable when a better CrouchWalkStart animation is provided.
-- Default: false — avoids a forward-lunge artifact on the first crouched step.
Constants.CROUCH_USE_CROUCH_WALK_START_ANIMATION = false

-- ── Stage 2S: Zero-gap crouch-exit transitions ────────────────────────────────
-- Master switch. When true, releasing C blends directly from the crouch pose into the
-- correct standing idle/walk/run animation without showing the default Roblox neutral pose.
-- When false, the original ExitCrouch one-shot path is used (may show a pose gap).
Constants.CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = true

-- When false (default), the ExitCrouch one-shot is skipped while the player is moving.
-- The character crossfades directly from CrouchIdle/CrouchWalk into the appropriate
-- standing walk or run animation. Set true to restore ExitCrouch even while moving.
Constants.CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = false

-- Crossfade duration (seconds) for the direct blend from crouch into walk/run (moving path).
-- Both the crouch track fade-out and the walk/run fade-in use this value, so the blender
-- always has non-zero total weight — prevents the default pose flash.
Constants.CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.10

-- Crossfade duration (seconds) for the direct blend from crouch into Idle (not-moving path),
-- used both when ExitCrouch is absent and when ExitCrouch finishes and Idle should start.
Constants.CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.12

-- When true, the correct standing animation starts immediately inside the ExitCrouch Stopped
-- callback, rather than waiting for the next Heartbeat tick.
-- Eliminates the ≥1 frame blank-pose window after the ExitCrouch one-shot ends.
Constants.CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true

-- ── Stage 3D: Sprint directional body-facing ──────────────────────────────────
-- When true and custom mouse lock is active, sprinting rotates the character body toward
-- the camera-relative movement input direction instead of always facing camera yaw.
-- Walking (isSprinting == false) is unaffected — character still faces camera yaw while walking.
Constants.SPRINT_FACE_MOVEMENT_DIRECTION_WHILE_MOUSE_LOCKED = true

-- Master switch for the sprint directional body-facing feature.
-- Set false to disable entirely and revert to camera-yaw facing during all mouse-locked states.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_ENABLED = true

-- Minimum XZ movement-input magnitude below which no sprint direction facing is applied.
-- Below this threshold, faceCharacterTowardsDirection() and getCameraRelativeMoveDirection()
-- both no-op, and camera-yaw facing is used as the fallback.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE = 0.1

-- When true, logs sprint body-facing mode changes (camera-yaw ↔ movement-direction)
-- and sprint animation name changes to Output. Change-gated — does not spam per frame.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_DEBUG = true

-- When true, body rotation is smoothed using LERP over multiple Heartbeat frames instead
-- of snapping immediately to the target direction. Default false for instant, responsive feel.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = false

-- LERP alpha applied per Heartbeat when smoothing is enabled. 1.0 = immediate (no smoothing).
-- Values closer to 0 produce slower, heavier-feeling rotation.
-- Has no effect when SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED is false.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 1

-- ── Stage 3E: Natural AutoRotate sprint rotation ──────────────────────────────────────────────
-- Replaces Stage 3D directional CFrame snapping during sprint + custom mouse lock.
-- When both flags below are true, sprinting under custom mouse lock sets Humanoid.AutoRotate = true
-- so the Roblox physics engine rotates the character naturally toward movement direction,
-- eliminating the discrete 45°/90° snaps caused by the Stage 3D faceCharacterTowardsDirection() path.
-- Walking, idle, crouching, tactical sprint, sprint-stop, and landing all continue on the
-- existing camera-yaw CFrame facing path (AutoRotate = false, root.CFrame = CFrame.lookAt).
-- Set both false to revert to camera-yaw-only facing (no sprint direction rotation at all).
-- Set SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED false alone to disable this path
-- without touching SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED (future-proofing).
-- DISABLED (Stage 3E-fix 2026-05-25): AutoRotate=true caused camera jerk when changing
-- sprint direction in shift lock. The camera is pinned to HumanoidRootPart yaw in mouse-lock
-- mode, so every Roblox-physics body rotation snapped the camera with it. Fix: keep false so
-- sprint falls through to the camera-yaw CFrame path (same as walking in mouse lock).
-- Directional sprint animations (RunForwardLeft/Right) already show movement direction visually.
Constants.SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED     = false
Constants.SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED = true

-- When true, logs natural-AutoRotate mode entry and exit to Output once per mode change.
-- Does not spam per frame — gated by lastNaturalSprintAutoRotateActive in applyCharacterFacing().
Constants.SPRINT_NATURAL_AUTOROTATE_DEBUG = true

-- ============================================================
-- Objective settings
-- ============================================================
Constants.ANCHOR_PLANT_TIME = 5  -- seconds an attacker must stand on an objective to plant it

-- ============================================================
-- Player settings
-- ============================================================
Constants.MAX_HEALTH        = 100 -- maximum and starting health for every player
Constants.TELEPORT_Y_OFFSET = 3   -- studs above a spawn part's centre so characters land on top
Constants.RESPAWN_DELAY     = 5   -- seconds before a player re-enters play at round start (reserved for reinforcement system)
Constants.WALK_SPEED             = 14    -- default WalkSpeed for all players (studs/s)
Constants.SPRINT_SPEED           = 22    -- WalkSpeed while sprinting
Constants.CROUCH_SPEED           = 10    -- WalkSpeed while crouching
Constants.MOVEMENT_DIRECTION_DEADZONE = 0.15 -- Humanoid.MoveDirection magnitude below which the player is "Idle"
Constants.SLIDE_SPEED            = 30    -- initial WalkSpeed applied at slide start
Constants.SLIDE_DURATION         = 0.6   -- seconds a slide lasts before returning to crouch
Constants.SLIDE_COOLDOWN         = 1.5   -- seconds before another slide is allowed after one ends
Constants.SPRINT_STAMINA_ENABLED = false -- stamina system not yet implemented (DEBT-042)
Constants.PRONE_ENABLED          = false -- prone stance not yet implemented (DEBT-043)

-- ============================================================
-- Movement animation set names
-- Used by MovementController to key into MOVEMENT_ANIMATION_IDS and to validate
-- the argument passed to MovementController.SetEquippedWeaponName().
-- ============================================================
Constants.MOVEMENT_ANIMATION_SET_UNARMED = "Unarmed"  -- no weapon equipped
Constants.MOVEMENT_ANIMATION_SET_AR15    = "AR15"     -- AR15 rifle equipped

-- Default animation set played when no weapon is explicitly equipped.
-- Changing this constant switches the project-wide default without touching controllers.
Constants.MOVEMENT_DEFAULT_ANIMATION_SET = Constants.MOVEMENT_ANIMATION_SET_UNARMED

-- ============================================================
-- Movement animation IDs (Movement Stage 2A — R6 only)
-- Keyed by rig type → weapon-set name → animation name.
-- Do not add R15 animation IDs here.
-- Default set is Unarmed (no gun). AR15 set plays only when
-- MovementController.SetEquippedWeaponName("AR15") is called.
-- ============================================================
Constants.MOVEMENT_ANIMATION_IDS = {
    R6 = {
        Unarmed = {
            WalkForward        = "rbxassetid://81276554788940",   -- confirmed-good R6 no-gun walk forward (Stage 2M)
            WalkForwardAlt     = "rbxassetid://97919904114609",   -- alternate forward walk clip; loaded but not yet selected (Stage 2M)
            RunForward         = "rbxassetid://79045069356901",   -- confirmed-good R6 no-gun run forward  (Stage 2L)
            RunForwardTest     = "rbxassetid://118179559114284",  -- test run-forward clip; toggle via MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION
            WalkLeft           = "rbxassetid://127934481756733",  -- no-gun strafe left  (Stage 2M)
            WalkRight          = "rbxassetid://122034548466839",  -- no-gun strafe right (Stage 2M)
            WalkBackward       = "rbxassetid://140436478515683",  -- no-gun walk backward          (Stage 2M)
            WalkBackwardLeft   = "rbxassetid://137714892165355",  -- no-gun backward-left diagonal  (Stage 2M)
            WalkBackwardRight  = "rbxassetid://83443564844340",   -- no-gun backward-right diagonal (Stage 2M)
            WalkForwardLeft    = "rbxassetid://137297382056770",  -- no-gun walk forward-left diagonal  (Stage 2M)
            WalkForwardRight   = "rbxassetid://133633696854516",  -- no-gun walk forward-right diagonal (Stage 2M)
            RunForwardLeft     = "rbxassetid://94337945101783",   -- no-gun run forward-left diagonal (Stage 2G)
            RunForwardRight    = "rbxassetid://104724352837263",  -- no-gun run forward-right diagonal (Stage 2G)
            Idle               = "rbxassetid://132044223555193",  -- no-gun standing idle (Stage 2H)
            EnterCrouch        = "rbxassetid://105064599119554",  -- no-gun enter-crouch one-shot (Stage 2H)
            ExitCrouch         = "rbxassetid://104596765238289",  -- no-gun exit-crouch one-shot (Stage 2H)
            -- Stage 2J: Unarmed directional crouch-walk animations
            -- CrouchWalk / CrouchWalkForward share the same ID (forward is the canonical clip).
            -- Stage 2N: CrouchIdle (looped idle while crouched+still), CrouchIdleAlt (deferred alternate),
            --   CrouchWalkForward updated to new clip, CrouchWalkStart (one-shot idle-to-walk transition).
            CrouchIdle            = "rbxassetid://81947601552045",   -- no-gun crouch idle looped (Stage 2N)
            CrouchIdleAlt         = "rbxassetid://132053404406349",  -- no-gun crouch idle alternate; loaded but not yet selected (Stage 2N)
            CrouchWalk            = "rbxassetid://70428646705219",   -- no-gun crouch walk forward (canonical fallback alias) (Stage 2N)
            CrouchWalkForward     = "rbxassetid://70428646705219",   -- no-gun crouch walk forward (Stage 2N)
            CrouchWalkBackward    = "rbxassetid://131295440357763",  -- no-gun crouch walk backward
            CrouchWalkLeft        = "rbxassetid://103170217015576",  -- no-gun crouch walk strafe left
            CrouchWalkRight       = "rbxassetid://84961452934451",   -- no-gun crouch walk strafe right
            CrouchWalkForwardLeft  = "rbxassetid://115919203745144", -- no-gun crouch walk forward-left diagonal
            CrouchWalkForwardRight = "rbxassetid://107284851359368", -- no-gun crouch walk forward-right diagonal
            CrouchWalkBackwardLeft  = "rbxassetid://118800024223445",-- no-gun crouch walk backward-left diagonal
            CrouchWalkBackwardRight = "rbxassetid://104285284019251",-- no-gun crouch walk backward-right diagonal
            CrouchWalkStart       = "rbxassetid://129868628706658",  -- no-gun crouch walk start one-shot transition (Stage 2N)
            -- Stage 2O: falling animation.
            -- Stage 3A: landing classification — three tiers (light/medium/heavy).
            -- LandingMedium ID unchanged from Stage 2O; LandingLight and LandingHeavy are new.
            Falling               = "rbxassetid://86705296926580",   -- no-gun falling looped (Stage 2O)
            LandingLight          = "rbxassetid://135438895968665",  -- no-gun light landing one-shot (Stage 3A — normal jumps + small drops)
            LandingMedium         = "rbxassetid://135915211175953",  -- no-gun medium landing one-shot (Stage 2O / Stage 3A reclassified — sprint jumps + medium drops)
            LandingHeavy          = "rbxassetid://72796290236543",   -- no-gun heavy landing one-shot (Stage 3A — high drops)
            -- Stage 2P: tactical sprint animations (Unarmed only; no AR15 tactical sprint yet).
            TacticalSprintForward1 = "rbxassetid://135119369971434", -- tactical sprint forward primary (looped) (Stage 2P)
            TacticalSprintForward2 = "rbxassetid://110008857265859", -- tactical sprint forward alternate; loaded, not yet selected (Stage 2P)
            TacticalSprintStop     = "rbxassetid://81946205769343",  -- tactical sprint stop one-shot; plays when tactical sprint ends (Stage 2P)
            -- Vault animations (Unarmed only).
            -- IDs reserved for future implementation. NOT loaded by loadMovementAnimations() yet.
            -- Do not add loading or selection code until the vault system is designed and staged.
            LowVault    = "rbxassetid://78932004147700",  -- low-vault one-shot (deferred — vault system not yet implemented)
            MediumVault = "rbxassetid://98948076922717",  -- medium-vault one-shot (deferred — vault system not yet implemented)
        },
        AR15 = {
            WalkForward = "rbxassetid://138802532485746",
            RunForward  = "rbxassetid://79735501581082",
            Idle        = "rbxassetid://117989834436525",  -- AR15 standing idle (Stage 2H)
            EnterCrouch = "rbxassetid://79753647497328",   -- AR15 enter-crouch one-shot (Stage 2H)
            ExitCrouch  = "rbxassetid://91295776984408",   -- AR15 exit-crouch one-shot (Stage 2H)
        },
    },
}

Constants.MOVEMENT_ANIMATION_FADE_TIME = 0.15  -- seconds to cross-fade between movement animations

-- Animation playback speed multipliers (Stage 2C + 2H).
-- Applied via AnimationTrack:AdjustSpeed() when a track starts playing.
-- Tune these to match clip cadence without changing Humanoid.WalkSpeed.
Constants.MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER              = 1.3   -- WalkForward/Backward/diagonals play at 1.3× clip speed
Constants.MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER            = 1.4   -- WalkLeft/WalkRight play at 1.4× clip speed
Constants.MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER               = 1.15  -- RunForward plays at 1.15× clip speed; RunForwardLeft/Right IDs retained but deferred (Stage 2L)
-- Toggle to swap the active run-forward clip between RunForward (current) and RunForwardTest.
-- Set true to audition the test clip; set false to restore the confirmed RunForward clip.
-- Only affects the Unarmed set. AR15 RunForward is unaffected.
Constants.MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION               = false -- false = RunForward (current), true = RunForwardTest
Constants.MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER              = 0.75  -- Idle plays at 0.75× clip speed (Stage 2H)
Constants.MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9   -- EnterCrouch/ExitCrouch one-shots play at 0.9× clip speed (Stage 2H)
Constants.MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER       = 1.0   -- CrouchWalk* directional tracks play at 1.0× clip speed (Stage 2J)
-- Stage 2O: falling animation playback constant.
Constants.MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER           = 1.0   -- Falling looped track AdjustSpeed multiplier (Stage 2O)
-- Stage 2O (legacy alias) / Stage 3A: LandingMedium playback speed.
-- Superseded by MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER in Stage 3A; kept for reference.
Constants.MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER           = 1.0   -- LandingMedium AdjustSpeed multiplier (legacy alias — use LANDING_MEDIUM_SPEED_MULTIPLIER)
-- Minimum seconds in airborne state before a non-jump landing animation plays.
-- Pure drops shorter than this threshold skip the landing clip (tiny step-off).
-- Does NOT apply to jumps (wasJumping == true) — jump landings always classify. (Stage 3A)
Constants.MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME               = 0.25  -- seconds airborne required for non-jump landing (Stage 2O; still used in Stage 3A)

-- ============================================================
-- Tactical sprint (Movement Stage 2P — double-tap LeftShift)
-- ============================================================

-- Master switch: when false, the entire tactical sprint system is disabled and
-- double-tap LeftShift behaves the same as a normal sprint start.
Constants.TACTICAL_SPRINT_ENABLED = true

-- Seconds between two LeftShift presses that counts as a double-tap.
-- A second press within this window after the first starts tactical sprint.
Constants.TACTICAL_SPRINT_DOUBLE_TAP_WINDOW = 0.3

-- WalkSpeed target at full tactical sprint (studs/s).
-- Speed ramps from SPRINT_SPEED to this value over TACTICAL_SPRINT_ACCELERATION_TIME.
Constants.TACTICAL_SPRINT_SPEED = 30

-- Seconds to linearly ramp from SPRINT_SPEED to TACTICAL_SPRINT_SPEED after tactical sprint starts.
Constants.TACTICAL_SPRINT_ACCELERATION_TIME = 1.0

-- Minimum dot product of Humanoid.MoveDirection against the camera flat-forward vector
-- required to sustain tactical sprint each Heartbeat. Falls below this → tactical sprint ends.
-- 0.35 ≈ 70° off-forward; values above this require the player to face roughly forward.
Constants.TACTICAL_SPRINT_MIN_FORWARD_DOT = 0.35

-- When true, GunController blocks firing and reloading while tactical sprint is active.
-- The client does not send WeaponFired or ReloadRequest during tactical sprint.
Constants.TACTICAL_SPRINT_BLOCKS_GUN_USE = true

-- When true, the TacticalSprintStop one-shot animation plays when tactical sprint ends
-- (Shift released, direction changed, crouch pressed, or phase exit while sprinting).
-- When false, tactical sprint ends silently and normal animation selection resumes immediately.
Constants.TACTICAL_SPRINT_STOP_ANIMATION_ENABLED = true

-- Minimum seconds the player must have been in a tactical sprint before the full stop
-- (TacticalSprintStop animation + movement lock + momentum carry) plays on Shift release.
-- Below this threshold, Shift release ends tactical sprint instantly with no animation or lock.
-- Only applies to the Shift-release path; direction-change stops (Heartbeat) are unaffected.
Constants.TACTICAL_SPRINT_STOP_MIN_DURATION = 5.0

-- When true, WalkLeft/WalkRight strafe animations only play while mouse lock / shift-lock
-- style state is active (UserInputService.MouseBehavior == LockCenter).
-- Left/right/diagonal movement falls back to WalkForward when mouse lock is off.
-- Set false to play strafe animations regardless of mouse-lock state.
Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK = true

-- Master switch: when false, MovementController does not disable Animate and does not
-- play any custom movement tracks — the default avatar animation pack runs as normal.
-- Set true (default) to use the custom R6 animation system with Unarmed/AR15 sets.
Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED = true

-- When true, MovementController sets character.Animate.Disabled = true before loading
-- custom tracks so the avatar animation pack cannot override R6 locomotion.
-- When false, Animate is left running; custom tracks may blend or be overridden.
-- DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT has no effect when
-- CUSTOM_MOVEMENT_ANIMATIONS_ENABLED is false.
Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = true

-- When true, MovementController logs animation load and switch events to Output.
-- Set false to silence animation diagnostics in production.
Constants.MOVEMENT_ANIMATION_DEBUG = true

-- ============================================================
-- Custom mouse-lock toggle (Movement Stage 2D)
-- Replaces reliance on Roblox default Shift Lock for strafe animation gating.
-- LeftAlt toggles custom mouse lock; LeftShift remains sprint-only.
-- ============================================================

-- Master switch: when true, MovementController toggles a custom mouse-lock state on
-- CUSTOM_MOUSE_LOCK_TOGGLE_KEY press, and sets UserInputService.MouseBehavior to
-- LockCenter (on) / Default (off). When false, custom mouse lock is disabled and
-- MouseBehavior is reset to Default.
Constants.CUSTOM_MOUSE_LOCK_ENABLED = true

-- Key that toggles the custom mouse-lock state.
-- Default: LeftControl (changed from LeftAlt in Stage 2K — keeps LeftShift free for sprint-only use).
Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY = Enum.KeyCode.LeftControl

-- When true, WalkLeft/WalkRight strafe animations only play when the custom mouse lock
-- is active (customMouseLocked == true). This supersedes the Roblox-native-ShiftLock
-- detection path that MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK previously relied on.
-- Set false to fall back to the MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK legacy path.
Constants.CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true

-- When true, MovementController logs custom mouse-lock toggle events to Output.
-- Set false to silence custom mouse-lock diagnostics in production.
Constants.CUSTOM_MOUSE_LOCK_DEBUG = true

-- When true, MovementController calls LocalPlayer.DevEnableMouseLock = false on Start()
-- and on CharacterAdded to prevent Roblox's built-in Shift Lock from interfering with
-- LeftShift sprint. This is a client-side fix; also set StarterPlayer.EnableMouseLockOption
-- = false in the project (default.project.json / Studio) for a full solution.
Constants.DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK = true

-- When true, MovementController writes UserInputService.MouseBehavior = LockCenter on every
-- Heartbeat while customMouseLocked is true. Prevents CoreScripts or UI transitions from
-- stealing mouse lock after the LeftAlt toggle applies it.
Constants.CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true

-- ContextActionService priority for the custom mouse-lock toggle binding.
-- Higher numbers take priority over lower ones. 3000 is above the default CoreScript
-- input priority (2000) so the LeftAlt bind is processed before CoreScripts can intercept.
Constants.CUSTOM_MOUSE_LOCK_INPUT_PRIORITY = 3000

-- When true, MovementController additionally sets Humanoid.AutoRotate = false and rotates
-- HumanoidRootPart.CFrame to face the camera yaw direction every Heartbeat while custom
-- mouse lock is active. This produces proper shift-lock-style character facing.
-- On toggle-off, respawn, or phase exit (when REQUIRE_ACTIVE is true), AutoRotate is restored.
-- Set false to disable character-facing rotation (cursor lock only, no rotation).
Constants.CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW = true

-- When true, character-facing rotation is only active during the ACTIVE phase.
-- On phase exit (e.g. ACTIVE → RESULTS/LOBBY), AutoRotate is restored to its cached value
-- while customMouseLocked remains unchanged (the toggle state is preserved).
-- On re-entry to ACTIVE with customMouseLocked still true, AutoRotate is disabled again.
-- Set false to apply character-facing rotation in all phases whenever mouse lock is on.
Constants.CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION = true

-- When true, MovementController logs character-facing rotation events and skip reasons to Output.
-- Set false to silence facing-rotation diagnostics in production.
Constants.CUSTOM_MOUSE_LOCK_ROTATION_DEBUG = true

-- ============================================================
-- Third-person camera zoom limits (Stage 2K — 2026-05-20)
-- Applied by MovementController on Start() and on every CharacterAdded.
-- Replaces Roblox's default wide camera zoom range with a controlled FPS prototype range.
-- Player can scroll between MIN and MAX while in normal third-person mode.
-- Do NOT set CameraType to Scriptable or write camera.CFrame to enforce these.
-- Roblox's built-in camera system respects these player-property limits.
-- ============================================================
Constants.THIRD_PERSON_MIN_ZOOM_DISTANCE = 4    -- minimum camera zoom (studs); player can scroll in to 4 studs
Constants.THIRD_PERSON_MAX_ZOOM_DISTANCE = 14   -- maximum camera zoom (studs); player cannot scroll out beyond 14 studs

-- Custom mouse-lock camera settings (Stage 2K — 2026-05-20)
-- Applied when custom mouse lock is enabled; restored to normal third-person limits on disable.
-- CameraMinZoom = CameraMaxZoom = CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE locks the zoom to a single
-- over-the-shoulder distance. Roblox's default camera controller handles the actual orbit.
Constants.CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE       = 8                       -- locked zoom distance (studs) while mouse lock is on
Constants.CUSTOM_MOUSE_LOCK_CAMERA_OFFSET         = Vector3.new(1.75, 0, 0) -- Humanoid.CameraOffset while mouse lock is on (right-shoulder)
Constants.CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET = Vector3.zero            -- Humanoid.CameraOffset when mouse lock is off (no offset)

-- When true, applyCustomMouseLockCamera() sets CameraMinZoom = CameraMaxZoom = CAMERA_DISTANCE.
-- Set false to leave zoom scrollable while mouse lock is on.
Constants.CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE = true

-- When true, applyCustomMouseLockCamera() sets Humanoid.CameraOffset = CAMERA_OFFSET.
-- Set false to leave CameraOffset unchanged while mouse lock is on.
Constants.CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET = true

-- ============================================================
-- Timing constants
-- ============================================================
Constants.COUNTDOWN_TICK     = 1  -- seconds between each broadcast inside a phase countdown
Constants.LOBBY_POLL_INTERVAL = 2  -- seconds between player-count checks while waiting for MIN_PLAYERS
Constants.MATCH_END_PAUSE    = 3   -- seconds between the end of one match and the start of the next

-- ============================================================
-- Death screen (client presentation only)
-- ============================================================
Constants.DEATH_FADE_TIME      = 0.8  -- seconds to tween the black overlay and blur in on death
Constants.DEATH_OVERLAY_OPACITY = 0.75 -- target opacity of the black screen overlay (0–1)
Constants.DEATH_BLUR_SIZE       = 24   -- target blur size applied to Lighting on death
Constants.DEATH_CLEANUP_TIME    = 0.5  -- seconds to tween the overlay and blur back out on PREP
Constants.DEATH_EQ_LOW_GAIN     = 0    -- EqualizerSoundEffect low-frequency gain on death (unchanged)
Constants.DEATH_EQ_MID_GAIN     = -50  -- EqualizerSoundEffect mid-frequency gain on death (heavy cut)
Constants.DEATH_EQ_HIGH_GAIN    = -60  -- EqualizerSoundEffect high-frequency gain on death (near silence)

-- ============================================================
-- Kill feed (client presentation only)
-- ============================================================
Constants.KILLFEED_DISPLAY_TIME = 4    -- seconds each kill entry is visible before fading out
Constants.KILLFEED_FADE_TIME    = 0.3  -- seconds to tween an entry to transparent before destroying it

-- ============================================================
-- Team identity — canonical strings and UI colours
-- Use these instead of raw "Attackers"/"Defenders" literals.
-- TeamService also defines BrickColor values for Roblox Team objects; those are
-- separate from these Color3 values used for text and UI tinting.
-- ============================================================
Constants.TEAM_ATTACKERS = "Attackers"
Constants.TEAM_DEFENDERS = "Defenders"

Constants.COLOR_TEAM_ATTACKERS = Color3.fromRGB(200,  60,  60)  -- desaturated red  — attacker accent
Constants.COLOR_TEAM_DEFENDERS = Color3.fromRGB( 60, 120, 200)  -- desaturated blue — defender accent
Constants.COLOR_TEAM_NEUTRAL   = Color3.fromRGB(160, 160, 160)  -- medium grey — unknown/environment

-- ============================================================
-- Ammo HUD thresholds (client presentation only)
-- ============================================================
Constants.AMMO_LOW_THRESHOLD = 5  -- magazine count at or below which the number turns amber

-- ============================================================
-- Combat rules
-- ============================================================
Constants.FRIENDLY_FIRE_ENABLED = false  -- set true to allow players to damage teammates

-- Single source of truth for the active weapon name used by both GunService
-- (authoritative stat / ammo lookups) and GunController (client-side prediction
-- and cosmetics only). When multiple weapons exist as a player choice, replace
-- this constant with server-owned loadout state sent via a RemoteEvent — DEBT-013.
Constants.DEFAULT_WEAPON = "AR15"

-- Shot validation thresholds (server-side, GunService only)
Constants.SHOT_ORIGIN_MAX_DISTANCE    = 12    -- max studs between client origin and shooter HumanoidRootPart; farther origins are rejected
Constants.SHOT_DIRECTION_MIN_MAGNITUDE = 0.001 -- minimum direction vector magnitude; near-zero directions are rejected before normalization

-- ============================================================
-- Sprint FOV stretch (Movement Stage 3A — camera-feel only)
-- Changes workspace.CurrentCamera.FieldOfView smoothly while sprinting.
-- Does NOT write camera.CFrame. Does NOT set CameraType to Scriptable.
-- Does NOT change CameraOffset. Does NOT add camera bob/sway/tilt/viewmodel effects.
-- FieldOfView is restored on sprint end, tactical sprint end, phase exit (non-ACTIVE),
-- character respawn, and MovementController.destroy().
-- ============================================================

-- Master switch: when false, sprint FOV stretch is disabled entirely.
-- FieldOfView is not written by MovementController at all when this is false.
Constants.SPRINT_FOV_ENABLED = true

-- Default FieldOfView applied on Start() and restored when sprinting ends.
-- Roblox's built-in camera default is 70. Match your project's baseline FOV here.
Constants.DEFAULT_CAMERA_FOV = 70

-- FieldOfView target while normal sprint (LeftShift) is active and the player is moving.
-- Higher values widen the field of view — makes movement feel faster without increasing speed.
Constants.SPRINT_CAMERA_FOV = 78

-- FieldOfView target while tactical sprint (double-tap LeftShift) is active.
-- Slightly higher than SPRINT_CAMERA_FOV for a stronger visual feel.
-- Only applied when TACTICAL_SPRINT_ENABLED is true and tactical sprint is active.
Constants.TACTICAL_SPRINT_CAMERA_FOV = 84

-- Seconds to tween FieldOfView to the sprint/tactical-sprint target (sprint-start direction).
Constants.SPRINT_FOV_TWEEN_TIME = 0.18

-- Seconds to tween FieldOfView back to DEFAULT_CAMERA_FOV (sprint-end / phase-exit / respawn).
Constants.SPRINT_FOV_RESTORE_TIME = 0.22

-- ============================================================
-- Landing animation classification (Movement Stage 3A)
-- Three tiers replace the single LandingMedium from Stage 2O.
-- Drop distance = vertical displacement (studs) from airborne-start Y to landing Y.
-- Jump classification takes precedence over drop-distance classification:
--   wasJump=true + not sprint → LandingLight (regardless of drop distance, unless heavy)
--   wasJump=true + sprint     → LandingMedium (unless heavy drop)
-- Pure drops (no jump) are classified by drop distance.
-- ============================================================

-- Maximum drop distance (studs) for a LandingLight animation (pure drops only).
Constants.MOVEMENT_LANDING_LIGHT_MAX_DROP = 8

-- Maximum drop distance (studs) for a LandingMedium animation (pure drops only).
-- Drops above this use LandingHeavy.
Constants.MOVEMENT_LANDING_MEDIUM_MAX_DROP = 18

-- Minimum drop distance (studs) at which LandingHeavy is always played.
-- Equal to MOVEMENT_LANDING_MEDIUM_MAX_DROP — drops at or above this use heavy regardless of wasJump.
Constants.MOVEMENT_LANDING_HEAVY_MIN_DROP = 18

-- Maximum air time (seconds) for a jump to be classified as light.
-- Reserved for future use — current getLandingAnimationName uses wasJump boolean + drop distance.
Constants.MOVEMENT_LANDING_JUMP_LIGHT_MAX_AIR_TIME = 0.85

-- When true, a jump performed while normal or tactical sprint is active uses LandingMedium.
-- When false, all intentional jumps use LandingLight regardless of sprint state.
-- Walk-off drops (ledge falls with no jump input) still use height-based Medium/Heavy classification.
Constants.MOVEMENT_LANDING_SPRINT_JUMP_USES_MEDIUM = false

-- Fade time (seconds) for playing and stopping landing animation tracks.
-- Shorter than MOVEMENT_ANIMATION_FADE_TIME (0.15) so landing clips blend in and out quickly.
Constants.MOVEMENT_LANDING_ANIMATION_FADE_TIME = 0.08

-- Playback speed multipliers for each landing tier (via AnimationTrack:AdjustSpeed).
-- LandingLight is faster (1.15×) so the clip completes quickly and movement flow resumes sooner.
-- LandingHeavy is slightly slower (0.9×) for a heavier, more impactful feel.
Constants.MOVEMENT_LANDING_LIGHT_SPEED_MULTIPLIER  = 1.15
Constants.MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER = 1.0
Constants.MOVEMENT_LANDING_HEAVY_SPEED_MULTIPLIER  = 0.9

-- ============================================================
-- Landing movement lock (Movement Stage 3B)
-- Locks Humanoid.WalkSpeed = 0 while medium/heavy landing animations play,
-- preventing player input from moving the character during the impact recovery.
-- Sprint-jump medium landings additionally apply a short LinearVelocity carry
-- in the jump momentum direction while input movement remains locked.
-- LandingLight never locks movement.
-- Does NOT add fall damage, stamina, slide, vault, prone, or camera changes.
-- Does NOT write camera.CFrame, CameraOffset, FieldOfView, HipHeight, or JumpPower.
-- ============================================================

-- Master switch: when false, no landing movement lock is applied for any tier.
Constants.LANDING_MOVEMENT_LOCK_ENABLED = true

-- Per-tier switches: set to false to disable locking for a specific tier only.
Constants.LANDING_MEDIUM_LOCKS_MOVEMENT = true
Constants.LANDING_HEAVY_LOCKS_MOVEMENT  = true
Constants.LANDING_LIGHT_LOCKS_MOVEMENT  = false   -- always false; LandingLight never locks

-- Fallback lock duration (seconds) for medium/heavy landings when no sprint-jump
-- momentum carry applies. WalkSpeed is restored when this timer fires OR when the
-- landing animation track finishes (whichever comes first).
-- LANDING_MEDIUM: should roughly match LandingMedium track natural length at 1.0× speed.
-- LANDING_HEAVY:  should roughly match LandingHeavy track natural length at 0.9× speed.
-- Both values may need tuning after Studio playtest — see DEBT-044 remaining risks.
Constants.LANDING_MEDIUM_LOCK_FALLBACK_DURATION = 0.35
Constants.LANDING_HEAVY_LOCK_FALLBACK_DURATION  = 0.65

-- Sprint-jump landing momentum carry (applied only on LandingMedium from a sprint jump).
-- A LinearVelocity instance is created on HumanoidRootPart for the duration,
-- pushing the character forward at MOMENTUM_SPEED while input movement is locked.
-- The carry ends after MOMENTUM_DURATION seconds; both the LinearVelocity and
-- Attachment are destroyed (clearLandingMomentum) when the carry finishes.
-- This is NOT the slide system — no slide animation, no camera tilt, no fall damage.
Constants.SPRINT_JUMP_LANDING_MOMENTUM_ENABLED  = true
Constants.SPRINT_JUMP_LANDING_MOMENTUM_DURATION = 0.22    -- seconds
Constants.SPRINT_JUMP_LANDING_MOMENTUM_SPEED    = 18      -- studs/s (horizontal only)
Constants.SPRINT_JUMP_LANDING_MOMENTUM_MAX_FORCE = 60000  -- LinearVelocity MaxForce (Magnitude mode)

-- Stage 3F: zero-gap landing exit.
-- When true, the landing animation's Stopped callback immediately crossfades to the
-- correct locomotion animation (walk/run/idle) before the next Heartbeat tick fires.
-- Prevents the brief blank-pose (T-pose) flash that occurs between the landing one-shot
-- ending and updateMovementAnimation() picking up on the following Heartbeat.
-- Mirrors Constants.CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY (Stage 2S).
-- Set false to revert to the old behaviour (locomotion resumes on the next Heartbeat).
Constants.LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true

-- ============================================================
-- Sprint stop behavior (Movement Stage 3C — 2026-05-22)
-- Applies a movement lock and short forward momentum carry when normal sprint
-- (LeftShift hold) ends, provided the player sprinted for at least
-- SPRINT_STOP_MIN_SPRINT_DURATION seconds.
-- Uses the TacticalSprintStop animation asset (same clip, no new animation ID).
-- This is NOT the slide system — no slide animation, no camera tilt, no prone state.
-- Does NOT write camera.CFrame, CameraOffset, FieldOfView, HipHeight, or JumpPower.
-- ============================================================

-- Master switch: when false, SprintStop never plays and no lock or momentum is applied.
-- Normal sprint ends silently (same as before Stage 3C).
Constants.SPRINT_STOP_ENABLED = true

-- Minimum sprint duration (seconds) before SprintStop is eligible to play.
-- Tap-sprints shorter than this threshold skip SprintStop entirely and end normally.
Constants.SPRINT_STOP_MIN_SPRINT_DURATION = 0.75

-- When true, Humanoid.WalkSpeed is set to 0 while SprintStop is playing.
-- Normal walk/sprint/crouch speed logic does not override it while locked.
-- WalkSpeed is restored after SprintStop ends (Stopped callback or fallback timer).
Constants.SPRINT_STOP_LOCKS_MOVEMENT = true

-- Fallback lock duration (seconds) if the animation Stopped callback never fires.
-- The greater of track.Length and this value is used as the actual lock window.
Constants.SPRINT_STOP_LOCK_FALLBACK_DURATION = 0.38

-- When true, a short LinearVelocity momentum carry is applied during SprintStop,
-- pushing the player forward in their last sprint direction while input is locked.
-- Produces a brief forward-carry feel without a slide animation or slide state.
Constants.SPRINT_STOP_MOMENTUM_ENABLED = true

-- NOTE: This constant is no longer used. The tactical sprint stop carry duration is now
-- derived from the TacticalSprintStop animation's Length (matched exactly so the slide
-- lasts the full animation). Kept here for reference; safe to remove in a future cleanup.
Constants.SPRINT_STOP_MOMENTUM_DURATION = 0.24

-- Horizontal carry speed in studs/s during the momentum window.
Constants.SPRINT_STOP_MOMENTUM_SPEED = 16

-- LinearVelocity MaxForce (Magnitude mode) for the sprint stop momentum carry.
-- Matches the value used for landing momentum (SPRINT_JUMP_LANDING_MOMENTUM_MAX_FORCE).
Constants.SPRINT_STOP_MOMENTUM_MAX_FORCE = 60000

-- Minimum horizontal speed (studs/s from AssemblyLinearVelocity) required to use
-- the root part's actual velocity as the sprint direction source each Heartbeat.
-- Below this, Humanoid.MoveDirection is used instead (fallback to CFrame.LookVector if zero).
Constants.SPRINT_STOP_MIN_HORIZONTAL_SPEED = 8

-- ============================================================
-- Client presentation flags (development / testing)
-- ============================================================
-- false = allow normal Roblox camera for development/testing and hide first-person viewmodel.
-- true  = lock first person and show first-person viewmodel during gameplay.
-- Set to true before shipping or playtesting the FPS experience.
-- See ViewModelController.lua and DEBT-048 for full context.
Constants.FORCE_FIRST_PERSON = false

return Constants
