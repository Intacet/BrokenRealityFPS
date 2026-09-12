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
-- Applied to the CrouchIdle (or fallback) fade-in.
-- Stage 3M (2026-05-26): increased 0.12 → 0.28 s for a slower, more fluid drop into crouch.
Constants.CROUCH_DIRECT_BLEND_FADE_TIME = 0.28

-- Crossfade duration (seconds) for the direct-blend when entering crouch while MOVING.
-- Slightly shorter than CROUCH_DIRECT_BLEND_FADE_TIME — player is already in motion
-- so a full-weight pose is needed sooner, but still noticeably slower than before.
-- Stage 3M (2026-05-26): increased 0.10 → 0.22 s.
Constants.CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.22

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
-- Stage 3M (2026-05-26): increased 0.10 → 0.22 s for a more fluid stand-up while moving.
Constants.CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.22

-- Crossfade duration (seconds) for the direct blend from crouch into Idle (not-moving path),
-- used both when ExitCrouch is absent and when ExitCrouch finishes and Idle should start.
-- Stage 3M (2026-05-26): increased 0.12 → 0.28 s.
Constants.CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.28

-- When true, the correct standing animation starts immediately inside the ExitCrouch Stopped
-- callback, rather than waiting for the next Heartbeat tick.
-- Eliminates the ≥1 frame blank-pose window after the ExitCrouch one-shot ends.
Constants.CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true

-- ── Stage 3M: Crouch-exit speed lock ─────────────────────────────────────────
-- When true, WalkSpeed is held at CROUCH_SPEED for the full duration of the crouch-exit
-- animation window (CROUCH_EXIT_DIRECT_BLEND_FADE_TIME or CROUCH_EXIT_IDLE_BLEND_FADE_TIME
-- depending on the path). Without this, speed snaps to WALK_SPEED the instant C is released
-- while the stand-up animation is still playing — the character looks crouched but runs at
-- full speed. With this, the "getting up" motion has physical weight.
-- Set false to restore the instant-speed-restore behaviour.
Constants.CROUCH_TRANSITION_SPEED_LOCK_ENABLED = true

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
-- of snapping immediately to the target direction.
-- Stage 3G: enabled so the character body smoothly tracks movement direction while sprinting
-- in mouse lock, eliminating the discrete snap feel from Stage 3D's immediate path.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = true

-- LERP alpha applied per Heartbeat when smoothing is enabled. 1.0 = immediate (no smoothing).
-- Values closer to 0 produce slower, heavier-feeling rotation.
-- Stage 3G: 0.18 — responsive enough to track direction changes within ~3–4 frames,
-- slow enough to avoid the per-frame CFrame snap that caused the Stage 3E camera jerk.
-- Has no effect when SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED is false.
Constants.SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 0.10

-- ── Stage 3G: Smooth sprint body-facing toward MoveDirection ──────────────────
-- Master switch for the Stage 3G smooth body-facing path.
-- When true and custom mouse lock is active, sprinting rotates the character body smoothly
-- toward the raw Humanoid.MoveDirection (camera-relative) each Heartbeat using the existing
-- faceCharacterTowardsDirection() lerp helper (Stage 3D).
-- AutoRotate remains false — no Roblox-physics rotation is involved, so no camera jerk.
-- When false, sprint falls through to the camera-yaw CFrame write (character always faces camera).
-- Walking, idle, crouching, tactical sprint, sprint-stop, and landing use camera-yaw regardless.
Constants.SPRINT_SMOOTH_BODY_FACING_ENABLED = true

-- ── Stage 3N: Instant backward turn while sprinting in shift lock ─────────────
-- When true, sprinting in the Backward / BackwardLeft / BackwardRight direction while
-- shift lock is active snaps the character body to face the move direction on the very
-- first Heartbeat — no LERP sweep. Without this, the normal 0.18 LERP takes ~10–15
-- frames (~170–250 ms) to complete the 180° pivot, so the character visually runs
-- backward while still facing the camera.
-- Forward and diagonal-forward sprint directions continue to use the smooth LERP.
-- Set false to restore the slow LERP for backward sprint directions.
Constants.SPRINT_BACKWARD_INSTANT_TURN = true

-- LERP alpha used for the body-facing rotation when sprinting backward
-- (Backward / BackwardLeft / BackwardRight) and SPRINT_BACKWARD_INSTANT_TURN is true.
-- Previously hardcoded to 1.0 (instant snap); 0.40 is fast enough for the initial
-- 180° reversal (~5 frames) while eliminating the visible snap on 45° diagonal
-- transitions within the backward set (BackwardLeft ↔ Backward ↔ BackwardRight).
Constants.SPRINT_BACKWARD_BODY_FACING_LERP_ALPHA = 0.40

-- DEAD CODE (superseded by Stage 3J — 2026-05-25): SPRINT_DIAGONAL_BODY_ROTATION_DEGREES
-- was used by Stage 3I to rotate the body by a fixed angle from camera-forward when
-- sprinting in the ForwardLeft or ForwardRight direction. Stage 3J disables RunForwardLeft/
-- RunForwardRight animation selection entirely (getSprintAnimationName always returns RunForward),
-- so the baked animation lean that Stage 3I was compensating for no longer exists.
-- All sprint directions now use raw MoveDirection via getCameraRelativeMoveDirection().
-- This constant is retained for reference and may be removed in a future cleanup pass.
Constants.SPRINT_DIAGONAL_BODY_ROTATION_DEGREES = 20  -- UNUSED since Stage 3J

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
-- Reload ↔ sprint interaction. RELOAD_BLOCKS_SPRINT: a reload in progress cancels an
-- active sprint and stops a new one from starting (MovementController). While reloading,
-- the movement target speed is multiplied by RELOAD_MOVE_SPEED_MULTIPLIER.
Constants.RELOAD_BLOCKS_SPRINT          = true
Constants.RELOAD_MOVE_SPEED_MULTIPLIER  = 0.55   -- roughly half / three-fifths walk speed while reloading

-- Sprint ↔ fire interaction (regular sprint; TACTICAL_SPRINT_BLOCKS_GUN_USE covers tac-sprint).
-- When true: cannot fire while GetMoveState() == "Sprinting", and cannot start a sprint
-- while auto-fire is active. The two states are mutually exclusive.
Constants.SPRINT_BLOCKS_GUN_USE = true

-- Aiming down sights. While isAiming: movement target speed is multiplied by
-- ADS_MOVE_SPEED_MULTIPLIER (getTargetMoveSpeed), and mouse look sensitivity is scaled by
-- ADS_SENSITIVITY_MULTIPLIER (MovementController.SetAiming caches + restores the player's
-- UserInputService.MouseDeltaSensitivity). Sprint is already blocked while ADS.
Constants.ADS_MOVE_SPEED_MULTIPLIER  = 0.6
Constants.ADS_SENSITIVITY_ENABLED    = true
Constants.ADS_SENSITIVITY_MULTIPLIER = 0.55
Constants.MOVEMENT_DIRECTION_DEADZONE = 0.15 -- Humanoid.MoveDirection magnitude below which the player is "Idle"
Constants.SLIDE_SPEED            = 30    -- initial WalkSpeed for a normal-sprint slide
Constants.SLIDE_DURATION         = 1.0   -- seconds a slide lasts before returning to crouch (was 0.6)
Constants.SLIDE_COOLDOWN         = 1.5   -- seconds before another slide is allowed after one ends
-- ── Stage 3O: Slide system ────────────────────────────────────────────────────
Constants.SLIDE_ENABLED                  = true  -- master switch; set false to disable slide trigger
Constants.SLIDE_TAC_DURATION_MULTIPLIER  = 1.75  -- tac-sprint slide lasts this × SLIDE_DURATION (goes further)
Constants.SLIDE_TAC_SPEED_MULTIPLIER     = 1.3   -- tac-sprint slides start at SLIDE_SPEED × this (travels faster)
Constants.SLIDE_ANIMATION_SPEED_MULTIPLIER = 1.0 -- AdjustSpeed value for SlideInto / SlideIdle / SlideExit
Constants.SLIDE_DEBUG                    = true  -- log slide events via Logger.debug()
-- Slide momentum carry (LinearVelocity that pushes the player forward regardless of W/A/S/D input).
-- Same pattern as SPRINT_STOP_MOMENTUM. Set ENABLED = false to revert to WalkSpeed-only slide.
Constants.SLIDE_MOMENTUM_ENABLED   = true   -- create a LinearVelocity carry during the slide
Constants.SLIDE_MOMENTUM_MAX_FORCE = 60000  -- LinearVelocity MaxForce (Magnitude mode); matches sprint-stop
Constants.SPRINT_STAMINA_ENABLED = false -- stamina system not yet implemented (DEBT-042)
Constants.PRONE_ENABLED          = false -- prone stance not yet implemented (DEBT-043)

-- ── Stage 4A: Vault foundation ───────────────────────────────────────────────
-- Master switch. Set false to disable vault detection and input without removing code.
Constants.VAULT_ENABLED                  = true

-- Space bar is intercepted by ContextActionService at VAULT_INPUT_PRIORITY.
-- The action only Sinks when a vault actually begins; otherwise it Passes through
-- so normal Roblox jump still works.
Constants.VAULT_INPUT_KEY                = Enum.KeyCode.Space

-- Vault is only allowed when the player is actively moving (MoveDirection magnitude > deadzone).
Constants.VAULT_REQUIRE_MOVING           = true

-- Vault is only allowed when MatchController:GetPhase() == ACTIVE.
-- Set false (default) so vault works in all phases, matching slide/sprint behaviour.
Constants.VAULT_REQUIRE_ACTIVE_PHASE     = false

-- Seconds after a vault completes before another vault can start.
Constants.VAULT_COOLDOWN                 = 0.65

-- Studs of clearance above the obstacle top surface added to the vault arc peak.
-- The arc peaks at (obstacleTopY + VAULT_ARC_PEAK_CLEARANCE) above the character's
-- lerped start→end Y, ensuring the character rises over the obstacle cleanly.
Constants.VAULT_ARC_PEAK_CLEARANCE       = 1.5

-- Obstacle height bands (studs above character feet).
-- Obstacles outside LOW_VAULT_MIN..MEDIUM_VAULT_MAX are not vaultable.
Constants.LOW_VAULT_MIN_HEIGHT           = 1.5
Constants.LOW_VAULT_MAX_HEIGHT           = 3.5
Constants.MEDIUM_VAULT_MIN_HEIGHT        = 3.5
Constants.MEDIUM_VAULT_MAX_HEIGHT        = 5.0

-- Maximum forward distance (studs) the forward-probe ray travels.
Constants.VAULT_MAX_FORWARD_DISTANCE     = 4.0

-- Y offset from HRP origin the forward-probe ray is cast from.
-- NEGATIVE = below HRP. Obstacle faces for LowVault (1.5–3.5 studs above feet) sit at
-- roughly HRP-1.5 to HRP+0.5. Using -2.0 places the ray 1 stud above feet, which is
-- reliably below every vaultable obstacle face and safely above the ground.
-- Previous value was +2.0 (above the character's head) which caused the ray to miss
-- all low obstacles entirely.
Constants.VAULT_OBSTACLE_RAY_HEIGHT_LOW    = -2.0
-- Y offset for a second forward probe (reserved for MediumVault detection pass — not yet used).
Constants.VAULT_OBSTACLE_RAY_HEIGHT_MEDIUM = 1.5

-- Total height above HRP used for the downward top-of-obstacle ray and the clearance ray.
Constants.VAULT_CLEARANCE_HEIGHT         = 5.5

-- Forward distance (studs past the obstacle face) the landing ray is cast from.
Constants.VAULT_LANDING_FORWARD_DISTANCE = 3.0

-- Small upward offset applied to the computed landing position so HRP sits correctly above ground.
-- R6 HumanoidRootPart is ~3 studs above ground; VAULT_LANDING_UP_OFFSET fine-tunes the final snap.
Constants.VAULT_LANDING_UP_OFFSET        = 0.25

-- TweenService movement duration for each vault tier (seconds).
Constants.VAULT_MOVE_DURATION_LOW        = 0.35
Constants.VAULT_MOVE_DURATION_MEDIUM     = 0.48

-- Surface normal Y-component threshold below which a surface is considered a wall (not a floor).
-- Forward-ray hits with Normal.Y >= this value are treated as sloped floors and rejected.
Constants.VAULT_MAX_SLOPE_NORMAL_Y       = 0.65

-- When true, WalkSpeed is set to 0 during the vault tween (mirrors SLIDE_LOCKS_MOVEMENT pattern).
Constants.VAULT_LOCKS_MOVEMENT           = true

-- When true, tactical sprint state is cleared when a vault starts.
Constants.VAULT_BLOCKS_SPRINT            = true

-- When true, crouch state blocks vault attempts (player must stand first).
Constants.VAULT_BLOCKS_CROUCH            = true

-- ContextActionService priority for the Space intercept.
-- Above CoreScript jump (2000) so we can intercept; below custom mouse-lock (3000).
Constants.VAULT_INPUT_PRIORITY           = 2500

-- AdjustSpeed multiplier applied to LowVault / MediumVault animation tracks.
Constants.VAULT_ANIMATION_SPEED_MULTIPLIER = 1.0

-- When true, vault detection and state transitions emit Logger.debug() output.
Constants.VAULT_DEBUG                    = true

-- Minimum XZ speed (studs/s) the character must be travelling to attempt a vault.
-- Set to 0 (disabled) — detectVault() raycasts are the real gate; the velocity guard
-- was found to block the intended "hold Space against obstacle" input model.
-- Raise above 0 to re-enable if unintentional vaults recur on fast wall contact.
Constants.VAULT_MIN_APPROACH_SPEED       = 0

-- When true, vault is blocked while the character is airborne
-- (Humanoid.FloorMaterial == Enum.Material.Air).
-- Prevents Space from stealing a vault while jumping near a wall.
Constants.VAULT_REQUIRE_GROUNDED         = true

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
            -- Vault animations (Unarmed only) — Stage 4A: active.
            -- Low vault (1.5–3.5 studs): played for shorter obstacles.
            -- Medium vault (3.5–5.0 studs): played for taller obstacles.
            LowVault    = "rbxassetid://78932004147700",  -- low-vault one-shot (Stage 4A — active)
            MediumVault = "rbxassetid://98948076922717",  -- medium-vault one-shot (Stage 4A — active)
            -- Slide animations (Unarmed only).
            -- IDs reserved for future implementation. NOT loaded by loadMovementAnimations() yet.
            -- Do not add loading, input, or state-machine code until the slide system is designed and staged. See DEBT-053.
            SlideInto = "rbxassetid://101320244227398",  -- slide-into one-shot (deferred — slide system not yet implemented)
            SlideIdle = "rbxassetid://123763519906235",  -- slide-idle loop (deferred — slide system not yet implemented)
            SlideExit = "rbxassetid://89774397391406",   -- slide-exit one-shot (deferred — slide system not yet implemented)
        },
        AR15 = {
            WalkForward = "rbxassetid://138802532485746",
            RunForward              = "rbxassetid://79045069356901",   -- basic run (Shift once); no apex-pause artifact
            TacticalSprintForward1  = "rbxassetid://135119369971434",  -- aggressive lean sprint (Shift twice)
            WalkLeft    = "rbxassetid://90637681602224",   -- armed strafe left  (mouse-lock only)
            WalkRight   = "rbxassetid://87299213260935",   -- armed strafe right (mouse-lock only)
            Idle        = "rbxassetid://117989834436525",  -- AR15 standing idle (Stage 2H)
            EnterCrouch = "rbxassetid://79753647497328",   -- AR15 enter-crouch one-shot (Stage 2H)
            ExitCrouch  = "rbxassetid://91295776984408",   -- AR15 exit-crouch one-shot (Stage 2H)
            -- Crouch idle/walk: reuse Unarmed clips until AR15-specific ones are made.
            -- Avoids holdCrouchBottomPose() freeze when crouching while armed.
            CrouchIdle  = "rbxassetid://81947601552045",   -- Unarmed CrouchIdle (same clip)
            CrouchWalk  = "rbxassetid://70428646705219",   -- Unarmed CrouchWalkForward (same clip)
            -- Slide: reuse Unarmed clips until AR15-specific ones are made.
            SlideInto = "rbxassetid://101320244227398",    -- Unarmed SlideInto (same clip)
            SlideIdle = "rbxassetid://123763519906235",    -- Unarmed SlideIdle (same clip)
            SlideExit = "rbxassetid://89774397391406",     -- Unarmed SlideExit (same clip)
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
Constants.MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.5   -- EnterCrouch/ExitCrouch one-shots play at 0.5× clip speed (Stage 3M: slowed from 0.9 for more fluid stand-up feel)
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
-- required to sustain tactical sprint each Heartbeat. Falls below this → tactical sprint
-- ends. 0.6 ≈ 53° off-forward: a diagonal (W+D ≈ 0.71) still sustains as a veer, but a
-- hard sideways strafe (dot ≈ 0) cancels the burst — no juking while committed forward.
Constants.TACTICAL_SPRINT_MIN_FORWARD_DOT = 0.6

-- ── Balance: tactical sprint is a short committed burst, not a permanent gait ──
-- Force-stops after this many seconds of continuous tactical sprint.
Constants.TACTICAL_SPRINT_MAX_DURATION = 3.0
-- Seconds after tactical sprint ends before a double-tap can start it again.
Constants.TACTICAL_SPRINT_COOLDOWN = 4.0

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
-- Kept below TACTICAL_SPRINT_MAX_DURATION so a full burst can still trigger the stop clip.
Constants.TACTICAL_SPRINT_STOP_MIN_DURATION = 1.5

-- ── Stage 3K: Tactical sprint mouse sensitivity override ──────────────────────
-- When true, MovementController reduces UserInputService.MouseDeltaSensitivity by
-- TACTICAL_SPRINT_SENSITIVITY_MULTIPLIER on tactical sprint entry, and restores
-- the pre-entry value the moment tactical sprint ends (any exit path).
-- Prevents players from snapping the camera too quickly while in a committed forward run.
-- Set false to leave sensitivity unchanged during tactical sprint.
Constants.TACTICAL_SPRINT_SENSITIVITY_ENABLED = true

-- Fraction of current MouseDeltaSensitivity applied while tactical sprint is active.
-- 0.5 = half sensitivity (default). Values below 1.0 reduce turn speed; 1.0 = no change.
-- Has no effect when TACTICAL_SPRINT_SENSITIVITY_ENABLED is false.
Constants.TACTICAL_SPRINT_SENSITIVITY_MULTIPLIER = 0.5

-- When true, Humanoid.CameraOffset.X is corrected each Heartbeat so the right-shoulder
-- offset stays visually on the camera's right side regardless of body rotation from backpedal.
-- Without this, CameraOffset (in character LOCAL space) swings to the wrong visual side as
-- the body faces away from camera during the backpedal LERP.
-- Formula: correctedX = CAMERA_OFFSET.X * dot(cameraRightFlat, bodyRightFlat)
-- Set false to restore the fixed (1.75, 0, 0) offset.
Constants.BACKPEDAL_CAMERA_OFFSET_CORRECTION = true

-- Seconds to hold slideDirection yaw after SlideExit completes before releasing to normal
-- applyCharacterFacing(). Without this hold, the first Heartbeat after SlideExit immediately
-- snaps the character to face the camera, which is jarring when the camera moved during the slide.
Constants.SLIDE_EXIT_FACING_HOLD_DURATION = 0.25

-- ── Stage 4: Custom mouse-lock body-yaw and animation direction ───────────────
-- When true, the character body always faces the camera yaw direction during walking and
-- idle in custom mouse-lock mode.  The body does NOT rotate toward Humanoid.MoveDirection
-- during backward movement — the camera-relative direction (Backward / BackwardLeft /
-- BackwardRight) is used for animation selection only, not for body rotation.
-- Set false to disable the camera-yaw walk facing (body will not track camera yaw).
Constants.CUSTOM_MOUSE_LOCK_WALK_FACES_CAMERA = true

-- When true, sets Humanoid.AutoRotate = true during walking in custom mouse-lock instead
-- of writing HumanoidRootPart.CFrame manually.  False = use rotateCharacterCapped() CFrame
-- write (recommended — prevents the engine physics from dragging the camera).
Constants.CUSTOM_MOUSE_LOCK_WALK_AUTOROTATE = false

-- When true, sets Humanoid.AutoRotate = true during sprint in custom mouse-lock.
-- False = rely on Stage 3G (faceCharacterTowardsDirection LERP) for sprint body rotation.
-- Currently unused directly — Stage 3G handles sprint; kept for future sprint-path refactor.
Constants.CUSTOM_MOUSE_LOCK_SPRINT_AUTOROTATE = true

-- Angular speed (degrees per 60-fps frame, dt-normalised) for camera-yaw body tracking
-- during walking and idle in custom mouse-lock.  18°/frame at 60 fps means the body
-- completes a 180° flip in ~10 frames (~167 ms) — smooth and free of visible snapping.
-- Raise carefully: values above ~35°/frame may appear as a single-frame snap at 60 fps.
Constants.CUSTOM_MOUSE_LOCK_BODY_YAW_LERP_SPEED = 18

-- Minimum time (seconds) between accepted animation direction-name changes in
-- chooseDirectionalAnimationWithHysteresis().  Prevents rapid animation oscillation when
-- input sits exactly on a direction boundary (e.g. S+A at the BackwardLeft / Backward line).
-- 0.08 s ≈ 5 frames at 60 fps — long enough to suppress jitter, short enough to feel instant.
Constants.MOVEMENT_DIRECTION_MIN_SWITCH_INTERVAL = 0.08

-- Crossfade time (seconds) used by playMovementAnimation() for normal walking direction
-- transitions (Forward, ForwardLeft, ForwardRight, Left, Right).
-- Shorter than MOVEMENT_ANIMATION_FADE_TIME (0.15) for snappier strafe feel.
Constants.MOVEMENT_DIRECTION_CROSSFADE_TIME = 0.12

-- Crossfade time (seconds) used by playMovementAnimation() for transitions within or
-- entering/exiting the backward cluster (Backward / BackwardLeft / BackwardRight).
-- Slightly shorter than MOVEMENT_DIRECTION_CROSSFADE_TIME to keep diagonal-backward
-- transitions visually tight while still blending.
Constants.MOVEMENT_BACK_DIRECTION_CROSSFADE_TIME = 0.10

-- Hysteresis angle (degrees) reserved for future angle-based direction lock — not yet
-- wired into chooseDirectionalAnimationWithHysteresis() but present for future tuning.
Constants.MOVEMENT_DIRECTION_HYSTERESIS_DEGREES = 10

-- When true, chooseDirectionalAnimationWithHysteresis() logs each held and accepted
-- direction change via Logger.debug().  Set false before shipping.
Constants.MOVEMENT_DIRECTION_DEBUG = true

-- When true, WalkLeft/WalkRight strafe animations only play while mouse lock / shift-lock
-- style state is active (UserInputService.MouseBehavior == LockCenter).
-- Left/right/diagonal movement falls back to WalkForward when mouse lock is off.
-- Set false to play strafe animations regardless of mouse-lock state.
Constants.MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK = true

-- When true, ALL directional animations (Backward, ForwardLeft, ForwardRight, BackwardLeft,
-- BackwardRight, Left, Right) require mouse lock to be active. Without mouse lock, every
-- walking direction plays WalkForward instead. This is a superset of
-- MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK (which only gates Left/Right strafe).
-- Set false to restore the legacy behaviour where Backward and diagonals play regardless.
Constants.MOVEMENT_DIRECTIONAL_ANIMS_REQUIRE_MOUSE_LOCK = true

-- When true and mouse lock is OFF, updateMovementAnimation forces the locomotion direction
-- to "Forward" for all walking inputs so WalkForward always plays.
-- Requires MOVEMENT_DIRECTIONAL_ANIMS_REQUIRE_MOUSE_LOCK = true to have any effect.
Constants.MOVEMENT_NON_MOUSE_LOCK_FORCE_FORWARD_ANIM = true

-- AutoRotate management during non-mouse-lock locomotion.
-- When true, MovementController sets Humanoid.AutoRotate = true whenever the custom
-- mouse lock is inactive so the engine rotates the character toward hum.MoveDirection.
-- When false, AutoRotate is not touched by MovementController in the non-mouse-lock path.
Constants.MOVEMENT_NON_MOUSE_LOCK_AUTOROTATE = true

-- When true, MovementController ensures Humanoid.AutoRotate = false while custom mouse
-- lock is active (matches the existing rotateCharacterCapped behaviour).
Constants.MOVEMENT_MOUSE_LOCK_AUTOROTATE = false

-- Body-yaw smooth speeds for the two locomotion modes.
-- MOVEMENT_NON_MOUSE_LOCK_BODY_YAW_SMOOTH_SPEED is reserved for a future explicit yaw
-- path when MOVEMENT_NON_MOUSE_LOCK_AUTOROTATE = false.
-- MOVEMENT_MOUSE_LOCK_BODY_YAW_SMOOTH_SPEED documents the intended mouse-lock speed;
-- the per-stance constants (MOVEMENT_BODY_YAW_WALK_SMOOTH_SPEED etc.) are authoritative.
Constants.MOVEMENT_NON_MOUSE_LOCK_BODY_YAW_SMOOTH_SPEED = 16
Constants.MOVEMENT_MOUSE_LOCK_BODY_YAW_SMOOTH_SPEED     = 18

-- Dot-product thresholds used by getLocomotionAnimationDirection() when classifying
-- camera-relative movement into Forward / Backward / Strafe buckets.
-- Values are cos(angle): 0.45 ≈ 63°, -0.45 ≈ 117°, 0.35 ≈ 70°.
Constants.MOVEMENT_DIRECTION_DOT_FORWARD_THRESHOLD  =  0.45
Constants.MOVEMENT_DIRECTION_DOT_BACK_THRESHOLD     = -0.45
Constants.MOVEMENT_DIRECTION_DOT_STRAFE_THRESHOLD   =  0.35

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
Constants.THIRD_PERSON_MIN_ZOOM_DISTANCE = 3    -- minimum camera zoom (studs); player can scroll in to 3 studs
Constants.THIRD_PERSON_MAX_ZOOM_DISTANCE = 8    -- maximum camera zoom (studs); player cannot scroll out beyond 8 studs

-- Custom mouse-lock camera settings (Stage 2K — 2026-05-20)
-- Applied when custom mouse lock is enabled; restored to normal third-person limits on disable.
-- CameraMinZoom = CameraMaxZoom = CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE locks the zoom to a single
-- over-the-shoulder distance. Roblox's default camera controller handles the actual orbit.
Constants.CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE       = 6                       -- locked zoom distance (studs) while mouse lock is on
Constants.CUSTOM_MOUSE_LOCK_CAMERA_OFFSET         = Vector3.new(1.75, 0, 0) -- Humanoid.CameraOffset while mouse lock is on (right-shoulder)
Constants.CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET = Vector3.zero            -- Humanoid.CameraOffset when mouse lock is off (no offset)

-- When true, applyCustomMouseLockCamera() sets CameraMinZoom = CameraMaxZoom = CAMERA_DISTANCE.
-- Set false to leave zoom scrollable while mouse lock is on.
Constants.CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE = true

-- When true, applyCustomMouseLockCamera() sets Humanoid.CameraOffset = CAMERA_OFFSET.
-- Set false to leave CameraOffset unchanged while mouse lock is on.
Constants.CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET = true

-- ── Stage 3H: Sprint camera offset override ───────────────────────────────────
-- When true, Humanoid.CameraOffset is zeroed while sprinting in mouse lock,
-- removing the right-shoulder over-the-shoulder offset and centering the camera
-- directly behind the character. The offset is restored to CUSTOM_MOUSE_LOCK_CAMERA_OFFSET
-- the moment sprint ends (next Heartbeat, ≤16ms).
-- Normal sprint (LeftShift) and tactical sprint both trigger the zero-offset path.
-- Walking, idle, crouching, sprint-stop, and landing lock all keep the normal offset.
-- Set false to always use CUSTOM_MOUSE_LOCK_CAMERA_OFFSET regardless of sprint state.
Constants.SPRINT_DISABLES_CAMERA_OFFSET = false

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

-- Fallback weapon name used by GunService (authoritative stat / ammo lookups) and
-- GunController (client-side prediction and cosmetics only) whenever a player has
-- no valid loadout selection. Per-player choice now lives in server-owned state —
-- see Constants.LOADOUT below and LoadoutService (partially resolves DEBT-013).
Constants.DEFAULT_WEAPON = "AR15"

-- ============================================================
-- Pre-round loadout menu (LoadoutMenu client UI + LoadoutService)
--
-- LoadoutService is the sole writer of two Player attributes, read by
-- GunService (primary weapon stats/ammo), TeamService (team assignment), and
-- GunController (which viewmodel to equip):
--   • ATTR_PRIMARY   — a WeaponData key from an entry with selectable == true
--   • ATTR_TEAM_PREF — one of TEAM_CHOICES
-- Attributes replicate to the owning client, so LoadoutMenu re-reads its own
-- previous selection with no extra remote traffic.
-- ============================================================
Constants.LOADOUT = {
    ENABLED                  = true,
    TOGGLE_KEY               = Enum.KeyCode.M,   -- opens / closes LoadoutMenu
    -- Phases in which the menu springs open on its own. PREP is deliberately
    -- excluded — it is only PREP_TIME seconds long and is the spawn moment.
    AUTO_OPEN_PHASES         = { [Constants.Phase.LOBBY] = true, [Constants.Phase.RESULTS] = true },
    -- false: a mid-round SelectLoadout is accepted and queued — GunService and
    -- TeamService only read the attributes at PREP, so it takes effect next round
    -- with no mid-round advantage. Set true to reject edits outright during ACTIVE.
    LOCK_EDITS_DURING_ACTIVE = false,

    ATTR_PRIMARY   = "BR_LoadoutPrimary",
    ATTR_TEAM_PREF = "BR_TeamPref",

    DEFAULT_PRIMARY   = "AKS74",   -- must be a selectable WEAPONS entry with full WeaponData
    DEFAULT_TEAM_PREF = "Auto",
    TEAM_CHOICES      = { "Auto", "Attackers", "Defenders" },

    -- Ordered weapon rows shown in the menu. selectable == false renders a greyed
    -- "LOCKED" card and is rejected server-side. To unlock a weapon: add its full
    -- data block in WeaponData (+ WeaponFeel + a ReplicatedStorage/ViewModels asset)
    -- and flip selectable = true here — no other code change needed.
    WEAPONS = {
        { key = "AKS74", label = "AKS-74", blurb = "7.62x39 assault rifle", selectable = true  },
        { key = "AR15",  label = "AR-15",  blurb = "LOCKED",                selectable = false },
        { key = "SCAR",  label = "SCAR-H", blurb = "LOCKED",                selectable = false },
    },
}

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
Constants.FORCE_FIRST_PERSON = true

-- ============================================================
-- Viewmodel equip / holster (AKS74 first-person foundation — 2026-05-28)
-- Key 1 toggles the AKS74 viewmodel on / off in GunController.
-- No fire animation, no reload animation, no ADS, no recoil, no sprint-lowered,
-- no third-person world-model logic — smallest equip/holster scaffold only.
-- ============================================================

-- Name of the weapon to equip when key 1 is pressed.
-- Maps to a WeaponData entry that must have viewModelName and animations.firstPerson.
Constants.DEFAULT_VIEWMODEL_WEAPON = "AKS74"

-- Key that toggles the first-person viewmodel equip / holster state.
Constants.VIEWMODEL_EQUIP_KEY = Enum.KeyCode.One

-- Name of the ReplicatedStorage folder that holds viewmodel Model assets.
Constants.VIEWMODEL_FOLDER_NAME = "ViewModels"

-- Primary root-part name on a viewmodel rig (used for BASE_OFFSET computation).
Constants.VIEWMODEL_DEFAULT_ROOT_PART_NAME = "HumanoidRootPart"

-- Fallback root-part name when HumanoidRootPart is absent on a viewmodel rig.
Constants.VIEWMODEL_FALLBACK_ROOT_PART_NAME = "RootPart"

-- When true, the player can scroll the mouse wheel to toggle between first-person
-- (LockFirstPerson) and third-person (Classic) camera modes.
-- Scroll down while in first-person  → switch to third-person.
-- Scroll up  while in third-person and zoom distance ≤ CAMERA_FIRST_PERSON_SNAP_THRESHOLD
--   → snap back to first-person.
-- FORCE_FIRST_PERSON still controls the STARTING mode; this adds the ability to switch.
Constants.CAMERA_PERSPECTIVE_SWITCH_ENABLED = true

-- Zoom distance (studs) at which scrolling up while in third-person snaps back to
-- first-person.  Should be slightly above THIRD_PERSON_MIN_ZOOM_DISTANCE (4) so the
-- snap happens reliably at full zoom-in without requiring pixel-perfect alignment.
Constants.CAMERA_FIRST_PERSON_SNAP_THRESHOLD = 5

-- Extra CFrame offset applied to the viewmodel in camera space every RenderStepped,
-- inserted between cam.CFrame and the recoil/bob/BASE_OFFSET chain.
-- Negative Z moves the model toward the camera (weapon appears larger/closer).
-- Positive Z pushes it away (weapon appears smaller/farther).
-- X shifts the model right (+) or left (-) in camera space.
-- Y shifts the model up (+) or down (-) in camera space.
-- Tune in Studio: equip AKS74 in ACTIVE phase, adjust until the weapon fills the
-- lower portion of the screen as in the reference Blender viewport.
-- Starting value: 1.2 studs forward (closer) with no lateral or vertical shift.
Constants.VIEWMODEL_CAMERA_EXTRA_OFFSET = CFrame.new(-0.1, 0.25, 0.7)

-- ============================================================
-- Viewmodel effects (bob, sway, landing dip, slide tilt)
-- All effects are viewmodel-only — they affect the weapon model's PivotTo offset only.
-- No camera.CFrame, CameraOffset, FieldOfView, or CameraType changes.
-- Composed by MovementController:GetViewmodelAddCFrame() each Heartbeat.
-- ============================================================

-- Master switch. Set false to disable all viewmodel effects at once.
Constants.VIEWMODEL_EFFECTS_ENABLED = true

-- ── Bob ───────────────────────────────────────────────────────
-- Sinusoidal up/down + lateral sway of the weapon while moving.
-- Amplitude in studs; frequency in cycles per second.
Constants.VIEWMODEL_BOB_ENABLED           = false -- disabled; replaced by VIEWMODEL_MOVE_BOB_ENABLED in ViewModelController sway layer
Constants.VIEWMODEL_BOB_WALK_AMPLITUDE    = 0.035  -- max vertical displacement (studs) while walking
Constants.VIEWMODEL_BOB_WALK_FREQUENCY    = 2.2    -- cycles per second while walking
Constants.VIEWMODEL_BOB_SPRINT_AMPLITUDE  = 0.055  -- stronger bob while sprinting
Constants.VIEWMODEL_BOB_SPRINT_FREQUENCY  = 3.0
Constants.VIEWMODEL_BOB_CROUCH_AMPLITUDE  = 0.015  -- reduced bob while crouching
Constants.VIEWMODEL_BOB_CROUCH_FREQUENCY  = 1.8
-- Lateral (X) bob as a fraction of the vertical (Y) bob amplitude.
Constants.VIEWMODEL_BOB_LATERAL_FACTOR    = 0.35
-- Subtle roll tilt applied as (lateralBobOffset × this). Units: radians per stud.
-- At sprint amplitude 0.055 × 0.35 = 0.019 studs lateral → 0.019 × 0.9 ≈ 0.017 rad ≈ ~1°.
Constants.VIEWMODEL_BOB_TILT_FACTOR       = 0.9
-- Lerp speed for fading bob in when movement starts and out when it stops (per second).
Constants.VIEWMODEL_BOB_FADE_SPEED        = 6

-- ── Sway ──────────────────────────────────────────────────────
-- Slight weapon lag/swing driven by mouse movement.
Constants.VIEWMODEL_SWAY_ENABLED          = true
-- Degrees of yaw/pitch sway accumulated per pixel of mouse delta.
Constants.VIEWMODEL_SWAY_HORIZONTAL_FACTOR = 0     -- zeroed; ViewModelController sway layer handles mouse sway
Constants.VIEWMODEL_SWAY_VERTICAL_FACTOR   = 0     -- zeroed; ViewModelController sway layer handles mouse sway
-- Maximum sway magnitude in degrees (clamps accumulation).
Constants.VIEWMODEL_SWAY_MAX              = 3.0
-- Per-second exponential decay rate back to zero when mouse stops moving.
Constants.VIEWMODEL_SWAY_DECAY            = 5

-- ── Landing dip ───────────────────────────────────────────────
-- Short downward Y impulse applied to the viewmodel on landing.
Constants.VIEWMODEL_LANDING_DIP_ENABLED   = true
Constants.VIEWMODEL_LANDING_DIP_LIGHT     = 0.06   -- studs (barely felt)
Constants.VIEWMODEL_LANDING_DIP_MEDIUM    = 0.14   -- studs (noticeable; matches LandingMedium anim)
Constants.VIEWMODEL_LANDING_DIP_HEAVY     = 0.28   -- studs (clearly felt; matches LandingHeavy anim)
-- Per-second exponential decay rate; dip fully recovers in ~0.4 s at rate 10.
Constants.VIEWMODEL_LANDING_DIP_DECAY     = 10

-- ── Slide tilt ────────────────────────────────────────────────
-- Roll tilt applied while sliding; direction driven by slide direction relative to camera.
Constants.VIEWMODEL_SLIDE_TILT_ENABLED    = true
Constants.VIEWMODEL_SLIDE_TILT_MAX        = 5      -- maximum roll in degrees
-- Per-second lerp speed for tilt entering and leaving slide. Higher = snappier.
Constants.VIEWMODEL_SLIDE_TILT_SPEED      = 8

-- ============================================================
-- World weapon model (third-person / server-side attachment)
-- WorldWeaponService clones ReplicatedStorage/<WORLD_WEAPON_FOLDER_NAME>/<worldModelName>
-- into the player's character and attaches Handle to R6 Right Arm via Motor6D.
-- Grip CFrames are initial tuning values only — adjust in Studio without touching code.
-- ============================================================

-- ReplicatedStorage folder that holds gun-only world model assets.
Constants.WORLD_WEAPON_FOLDER_NAME            = "WorldModels"

-- Name of the BasePart inside the world model that the Motor6D is attached to.
Constants.WORLD_WEAPON_HANDLE_PART_NAME       = "Handle"

-- Name given to the cloned world model when parented to the character.
Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME   = "EquippedWorldWeapon"

-- Name of the Motor6D created on the R6 Right Arm.
-- Must match the Motor6D name used in the animation pack rig so the Animator can
-- find and drive this joint when third-person weapon animations play.
Constants.WORLD_WEAPON_GRIP_MOTOR_NAME        = "Handle"

-- R6 right arm part name (per R6 canonical body-part names in PROJECT_RULES.md).
Constants.WORLD_WEAPON_R6_RIGHT_ARM_NAME      = "Right Arm"

-- AKS74 grip offsets for the Motor6D (C0 on Right Arm, C1 on Handle).
-- Both are identity so the animation pack's keyframes drive Handle directly
-- from the Right Arm origin — exactly matching the animation pack rig.
-- The third-person animations (equip/idle/fire/reload) contain the full
-- Handle positioning data; C0/C1 offsets here would shift everything wrong.
Constants.WORLD_AKS74_GRIP_C0 = CFrame.new()
Constants.WORLD_AKS74_GRIP_C1 = CFrame.new()

-- ============================================================
-- First-person viewmodel ADS (aim down sights)
-- Camera FOV zoom is owned by MovementController (updateSprintFov "Task A", keyed off
-- isAiming). ViewModelController owns the pivot glide to screen centre (adsAimAlpha) and,
-- when VIEWMODEL_ADS_ANIMATION_ENABLED is true, the adsIn/adsIdle/adsOut/adsFire pose
-- sequence. With it false (current default) ADS is just the FOV zoom + the pivot glide.
-- ============================================================

-- Input for ADS (right mouse button).
Constants.ADS_INPUT_USER_INPUT_TYPE = Enum.UserInputType.MouseButton2
-- true  = hold the button to aim, release to lower (default).
-- false = press to toggle aim on/off.
Constants.ADS_HOLD_TO_AIM = true

-- Fade time for ADS animation blend/transitions (in seconds).
Constants.VIEWMODEL_ADS_TRACK_FADE_TIME = 0.03

-- Playback-speed multiplier for the adsIn / adsOut transition clips (AnimationTrack:AdjustSpeed).
-- > 1 makes raising/lowering the sights snappier without touching the animation assets.
Constants.VIEWMODEL_ADS_TRANSITION_SPEED_MULTIPLIER = 1.35

-- When false, ADS plays NO viewmodel pose animation. Entering ADS goes straight to the
-- held "Aiming" state, the gun glides to a camera-centred position via VIEWMODEL_ADS_AIM_
-- BLEND_SPEED (adsAimAlpha), the FOV zoom is handled by MovementController as today, and
-- shots while aimed use the normal hipfire animation. Set true to restore the authored
-- adsIn / adsIdle / adsOut / adsFire animation sequence and its bounded-recovery watchdogs.
Constants.VIEWMODEL_ADS_ANIMATION_ENABLED = false

-- Crossfade duration for idle ↔ run and post-reload resume transitions.
-- Longer than ADS (which needs to feel snappy) but short enough to feel responsive.
Constants.VIEWMODEL_IDLE_RUN_FADE_TIME    = 0.18
Constants.VIEWMODEL_RELOAD_RESUME_FADE_TIME = 0.20

-- Disable procedural movement (mouse sway, move bob) while ADS to keep pose stable.
Constants.VIEWMODEL_ADS_DISABLE_PROCEDURAL_MOVEMENT = true

-- Suppress normal idle/run tracks while ADS to prevent pose fighting.
Constants.VIEWMODEL_ADS_DISABLE_RUN_WHILE_AIMING = true
Constants.VIEWMODEL_ADS_DISABLE_NORMAL_IDLE_WHILE_AIMING = true

-- ADS alignment: blend the viewmodel pivot toward the FakeCamera-at-camera-centre position
-- during ADS so the ADS animation's sights land exactly at screen centre.
-- At alpha=1 CAMERA_EXTRA_OFFSET is removed from the chain; BASE_OFFSET then places
-- FakeCamera exactly at cam.CFrame, matching where the ADS animation aims the iron sights.
-- At 18/s the correction reaches ~99% complete by the time a 0.25 s adsIn finishes.
Constants.VIEWMODEL_ADS_AIM_BLEND_SPEED = 18

-- ============================================================
-- Free-aim foundation (Stage 1 — visual / input only)
-- Crosshair and viewmodel lean toward mouse aim point within a deadzone.
-- Does NOT change bullet direction, camera.CFrame, server remotes, or hit validation.
-- Stage 2 integration (GetAimRay → firing) is deferred; see DEBT-063.
-- ============================================================

-- Master switch: set false to disable all free-aim behaviour instantly.
Constants.FREE_AIM_ENABLED                        = true
-- Debug: Logger.debug on weight changes and large-delta resets.
Constants.FREE_AIM_DEBUG                          = false

-- Tarkov-style firing: when true and hip-firing, GunController fires from the CAMERA
-- position along the direction the free-aim-rotated gun visually points
-- (camera.CFrame * CFrame.Angles(ViewModelController.GetFreeAimAngles())), instead of a
-- camera ray through the reticle pixel offset. Bullets leave where the gun points without
-- depending on a cosmetic muzzle attachment, and the origin stays camera-anchored so the
-- server's origin-vs-root check passes. ADS and free-aim-off fire dead-centre.
-- Server origin/direction validation + re-raycast are unchanged; no remote/ammo/damage change.
Constants.FREE_AIM_FIRE_FROM_MUZZLE               = true

-- Hide the fixed centre crosshair while hip-firing (only the floating gun-direction reticle
-- shows). The centre crosshair returns for ADS. See CrosshairUI:SetHipfireActive.
Constants.FREE_AIM_HIDE_CENTER_CROSSHAIR_HIPFIRE  = true

-- First-person aim/cursor lock. GunController pins + hides the OS pointer during active
-- first-person weapon use so the white cursor is no longer an apparent aim point, and
-- restores it outside gameplay. MouseBehavior LockCenter also feeds mouse delta to the
-- camera + FreeAimController exactly as before. Coexists with MovementController's own
-- LeftControl mouse-lock (both want LockCenter).
Constants.FIRST_PERSON_AIM = {
    ENABLED                   = true,
    LOCK_MOUSE_TO_CENTER      = true,
    HIDE_DEFAULT_CURSOR       = true,
    SHOW_CUSTOM_CROSSHAIR     = true,
    RESTORE_MOUSE_ON_INACTIVE = true,
    -- false: hide the OS cursor + lock to centre whenever a weapon is equipped, in any
    -- match phase (so you are cursor-free while just running around the test area).
    -- true: only do it during the ACTIVE round phase (leaves the cursor for lobby menus).
    REQUIRE_ACTIVE_PHASE      = false,
    DEBUG                     = true,
}

-- Per-weapon free-aim "weight / inertia" feel. DEFAULT holds every override-able knob;
-- FREE_AIM_PROFILES[<weaponName>] overrides only the keys it lists (rest fall back to
-- DEFAULT). weaponName matches ViewModelController:EquipWeapon / Constants.DEFAULT_VIEWMODEL_WEAPON.
-- The non-listed FREE_AIM_* constants below stay global (ADS behaviour, input deadzone, etc.).
Constants.FREE_AIM_PROFILES = {
    DEFAULT = {
        RADIUS_PIXELS          = 55,     -- how far the reticle / gun can drift from centre
        MOUSE_GAIN             = 0.26,   -- reticle responsiveness to raw mouse delta (hip)
        CROSSHAIR_MAX_SPEED_PIXELS = 420,
        CROSSHAIR_SMOOTH_SPEED = 9,      -- reticle position lag (lower = more trailing)
        RECENTER_SPEED         = 7,      -- pull back to centre when idle
        RECENTER_DELAY         = 0.08,
        VIEWMODEL_BLEND_SPEED  = 13,     -- gun rotation lag toward the reticle
        VIEWMODEL_TRACK_FACTOR = 0.92,   -- how fully the muzzle lands on the reticle (0..1)
        MOUSE_INERTIA_GAIN     = 0.10,   -- swing/weight from fast mouse motion
        MOUSE_INERTIA_MAX      = 26,
        MOUSE_INERTIA_DAMPING  = 12,
    },
    -- AKS-74 (5.45 rifle): medium weight, a touch more drift + swing.
    AKS74 = {
        RADIUS_PIXELS          = 60,
        MOUSE_GAIN             = 0.26,
        CROSSHAIR_SMOOTH_SPEED = 8.5,
        VIEWMODEL_BLEND_SPEED  = 12,
        VIEWMODEL_TRACK_FACTOR = 0.92,
        MOUSE_INERTIA_GAIN     = 0.12,
        MOUSE_INERTIA_MAX      = 30,
    },
    -- AR-15 (5.56 carbine): lighter, snappier, less drift.
    AR15 = {
        RADIUS_PIXELS          = 50,
        MOUSE_GAIN             = 0.28,
        CROSSHAIR_SMOOTH_SPEED = 10,
        VIEWMODEL_BLEND_SPEED  = 15,
        VIEWMODEL_TRACK_FACTOR = 0.9,
        MOUSE_INERTIA_GAIN     = 0.09,
        MOUSE_INERTIA_MAX      = 22,
    },
}

-- Hipfire deadzone radius in pixels (how far the crosshair can drift from center).
Constants.FREE_AIM_RADIUS_PIXELS                  = 55

-- ADS deadzone radius in pixels (tighter; makes ADS feel almost locked).
Constants.FREE_AIM_ADS_RADIUS_PIXELS              = 4

-- Scale factor applied to raw mouse delta before adding to aim offset (hipfire).
-- 1.0 = one-to-one with raw delta; lower = sluggish/heavy; higher = hair-trigger.
Constants.FREE_AIM_MOUSE_GAIN                     = 0.26

-- Scale factor applied to raw mouse delta during ADS. Near-zero so sights feel locked.
Constants.FREE_AIM_ADS_MOUSE_GAIN                 = 0.025

-- Maximum crosshair travel speed (pixels/s). Caps how far a fast flick can push the dot in one frame.
Constants.FREE_AIM_CROSSHAIR_MAX_SPEED_PIXELS     = 420

-- Input deadzone (pixels of raw delta). Movements below this threshold are ignored (jitter suppression).
Constants.FREE_AIM_CROSSHAIR_INPUT_DEADZONE_PIXELS = 0.65

-- Return-to-center speed (lerp per second) when mouse is idle, hipfire.
Constants.FREE_AIM_RETURN_SPEED                   = 7

-- Return-to-center speed (lerp per second) when mouse is idle, ADS.
Constants.FREE_AIM_ADS_RETURN_SPEED               = 22

-- Return speed used when suppressed (weapon holstered, sprint/reload suppress).
Constants.FREE_AIM_CROSSHAIR_RETURN_SPEED         = 11

-- Speed at which the visible crosshair position lerps toward the raw aim offset.
-- Higher = snappier tracking; lower = more pronounced trailing lag.
Constants.FREE_AIM_CROSSHAIR_SMOOTH_SPEED         = 9

-- Recenter: smoothly pull aim offset back to zero after the player stops moving the mouse.
Constants.FREE_AIM_RECENTER_ENABLED               = true
-- Seconds of idle input before recentering begins.
Constants.FREE_AIM_RECENTER_DELAY                 = 0.08
-- Lerp speed for the gentle recenter pull (slower than suppressed return).
Constants.FREE_AIM_RECENTER_SPEED                 = 7

-- Speed at which the viewmodel lean and inertia weight lerp toward their targets each frame.
-- Also governs how quickly the lean drains to zero during ADS.
Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED   = 13

-- How closely the hip-fire viewmodel actually points THROUGH the floating crosshair.
-- ViewModelController converts the normalized aim offset into the true angle the reticle
-- subtends at the current FOV/viewport, then rotates the viewmodel by that angle × this
-- factor. 1.0 = muzzle lands exactly on the reticle; lower = the gun trails it a little.
-- Set to 0 to fall back to the old fixed-degree cosmetic lean (YAW/PITCH_DEGREES below).
Constants.FREE_AIM_VIEWMODEL_TRACK_FACTOR  = 0.92

-- Fixed-degree cosmetic lean, used only when FREE_AIM_VIEWMODEL_TRACK_FACTOR == 0.
-- Suppressed during ADS so iron sights stay centered (see ViewModelController).
Constants.FREE_AIM_VIEWMODEL_YAW_DEGREES   = 0.65
Constants.FREE_AIM_VIEWMODEL_PITCH_DEGREES = 0.45

-- Maximum roll (clockwise tilt) of the viewmodel as the crosshair and inertia move horizontally.
-- Combined with mouse inertia contribution for a weighted, grounded feel.
-- Suppressed during ADS so iron sights stay centered (see ViewModelController).
Constants.FREE_AIM_VIEWMODEL_ROLL_DEGREES  = 0.12

-- Trailing rotational "swing" from fast mouse motion, as a fraction of the full
-- deadzone-edge aim angle. 0 = the muzzle only tracks the reticle (no weapon-mass lag
-- on flicks); higher = the gun rotates further behind a fast flick before catching up.
-- Multiplies the NORMALISED mouse-inertia velocity, so it is bounded no matter how fast
-- the flick is, and is scaled by the per-state inertia weight (≈0 during ADS).
Constants.FREE_AIM_VIEWMODEL_SWING_FACTOR  = 0.5

-- Translation: viewmodel shifts slightly opposite to the aim/inertia direction.
-- Gives the AK a sense of physical mass — the gun lags behind the look direction.
-- X = lateral (studs), Y = vertical (studs), Z = depth (studs).
Constants.FREE_AIM_VIEWMODEL_TRANSLATE_X   = 0.08
Constants.FREE_AIM_VIEWMODEL_TRANSLATE_Y   = 0.045
Constants.FREE_AIM_VIEWMODEL_TRANSLATE_Z   = 0.025

-- Mouse inertia: velocity accumulated from raw mouse delta each frame, then damped.
-- Adds roll and translation when the mouse is moving quickly, settling smoothly after.
Constants.FREE_AIM_MOUSE_INERTIA_ENABLED   = true

-- How strongly each mouse-delta unit pushes the inertia velocity (0 = off, higher = more lag).
Constants.FREE_AIM_MOUSE_INERTIA_GAIN      = 0.035

-- Damping rate (lerp fraction/s) applied to inertia velocity when not in ADS.
-- Lower value = takes longer to settle (heavier feel).
Constants.FREE_AIM_MOUSE_INERTIA_DAMPING   = 12

-- Damping rate (lerp fraction/s) applied to inertia velocity during ADS.
-- Higher than DAMPING so inertia drains quickly when entering ADS.
Constants.FREE_AIM_MOUSE_INERTIA_RETURN_SPEED = 10

-- Maximum inertia velocity magnitude (clamps how far inertia can push the viewmodel).
Constants.FREE_AIM_MOUSE_INERTIA_MAX       = 1.0

-- Per-state inertia weight. 1.0 = full effect applied; 0.0 = suppressed completely.
-- Lerped each frame at FREE_AIM_VIEWMODEL_BLEND_SPEED so transitions are smooth.
-- ADS is kept very low so iron sights remain steady; sprint/reload are partial.
Constants.FREE_AIM_HIP_WEIGHT              = 0.24
Constants.FREE_AIM_ADS_WEIGHT              = 0.0
Constants.FREE_AIM_SPRINT_WEIGHT           = 0.35
Constants.FREE_AIM_RELOAD_WEIGHT           = 0.15

-- When true, free-aim crosshair offset smoothly recenters while sprinting.
-- False: crosshair drift is allowed during sprint; inertia weight still reduces effect.
Constants.FREE_AIM_DISABLE_WHILE_SPRINTING = false

-- When true, free-aim crosshair offset smoothly recenters while reloading.
-- False: crosshair drift is allowed during reload; inertia weight still reduces effect.
Constants.FREE_AIM_DISABLE_WHILE_RELOADING = false

-- When true, the aim offset is reset to zero when the weapon is holstered.
Constants.FREE_AIM_RESET_ON_HOLSTER        = true

-- When false, the aim offset is NOT reset when exiting ADS back to hipfire.
-- The crosshair drifts from wherever it was before ADS, giving continuity.
Constants.FREE_AIM_RESET_ON_ADS_EXIT       = false

-- ── AKS74 fire configuration ──────────────────────────────────────────────────────────────
-- AKS74_DEFAULT_RPM: fallback RPM used by GunController if WeaponData[equippedWeapon].rpm is
-- absent. Normally WeaponData["AKS74"].rpm = 550 takes precedence; this constant is the
-- hard-coded sentinel so no magic number appears in controller code.
Constants.AKS74_DEFAULT_RPM = 550

-- ── Viewmodel recoil (data-driven per weapon; ApplyRecoil) ──────────────────────────────
-- Master switch. When false, ViewModelController:ApplyRecoil() is a no-op and the
-- vmRecoilCF inserted into PivotTo is CFrame.new() (identity — zero visual change).
Constants.VIEWMODEL_RECOIL_ENABLED = true
Constants.VIEWMODEL_RECOIL_DEBUG   = false  -- when true, Logger.debug fires on each ApplyRecoil call

-- First-person viewmodel locomotion animations (walk / enter-run / run / sprint).
-- Data-driven per weapon via WeaponData[name].animations.firstPerson.{walk,enterRun,run,sprint}.
-- When disabled, SetLocomotionState falls back to the binary SetRunning(isSprinting) path.
Constants.VIEWMODEL_LOCOMOTION_ANIMS_ENABLED           = true
Constants.VIEWMODEL_LOCOMOTION_DEBUG                   = false
Constants.VIEWMODEL_LOCOMOTION_FADE_TIME               = 0.14   -- crossfade between locomotion states (seconds)
Constants.VIEWMODEL_LOCOMOTION_ENTER_RUN_FADE_TIME     = 0.08   -- blend-in time for enterRun one-shot
Constants.VIEWMODEL_LOCOMOTION_ENTER_RUN_MIN_DURATION  = 0.12   -- reserved; enterRun plays to natural completion
Constants.VIEWMODEL_LOCOMOTION_MIN_SPEED               = 1.5    -- horizSpeed below this → Idle
Constants.VIEWMODEL_LOCOMOTION_WALK_SPEED_THRESHOLD    = 1.5    -- horizSpeed ≥ this → Walk
Constants.VIEWMODEL_LOCOMOTION_RUN_SPEED_THRESHOLD     = 10     -- horizSpeed ≥ this → Run (non-sprint movement)
Constants.VIEWMODEL_LOCOMOTION_SPRINT_SPEED_THRESHOLD  = 18     -- reserved; Sprint driven by GetMoveState()
Constants.VIEWMODEL_LOCOMOTION_ADS_BLOCKS_SPRINT_ANIM  = true   -- sprint anim suppressed during ADS; falls back to Run
Constants.VIEWMODEL_LOCOMOTION_RELOAD_PRIORITY_BLOCK   = true   -- reload blocks locomotion transitions; resumes after
Constants.VIEWMODEL_LOCOMOTION_EQUIP_PRIORITY_BLOCK    = true   -- equip plays fully before locomotion starts

-- Fallback values used when a weapon's WeaponData entry has no recoil sub-table.
-- Per-weapon overrides live in WeaponData["<name>"].recoil.{hip,ads}.
-- positionBack > 0 moves the weapon toward the camera (+Z camera-local = backward).
-- positionUp   > 0 lifts the weapon (+Y camera-local).
-- pitchDegrees > 0 = muzzle rises; pending Studio verification.
Constants.DEFAULT_VIEWMODEL_RECOIL_POSITION_BACK  = 0.035
Constants.DEFAULT_VIEWMODEL_RECOIL_POSITION_UP    = 0.004
Constants.DEFAULT_VIEWMODEL_RECOIL_PITCH_DEGREES  = 0.8
Constants.DEFAULT_VIEWMODEL_RECOIL_YAW_DEGREES    = 0.08
Constants.DEFAULT_VIEWMODEL_RECOIL_ROLL_DEGREES   = 0.08
Constants.DEFAULT_VIEWMODEL_RECOIL_RECOVERY_SPEED = 22
Constants.DEFAULT_VIEWMODEL_RECOIL_KICK_SPEED     = 40
Constants.DEFAULT_VIEWMODEL_RECOIL_MAX_BUILDUP    = 0.4

-- Fallback camera-space recoil kick for weapons that have a per-weapon recoil profile
-- but no camera sub-table.  Per-weapon values in WeaponData override these.
Constants.DEFAULT_CAMERA_RECOIL_KICK_UP    = 0.35   -- degrees of screen kick per shot
Constants.DEFAULT_CAMERA_RECOIL_KICK_RIGHT = 0.05

-- ── Debug bullet impact markers ─────────────────────────────────────────────────────────
-- When true, a neon sphere is rendered at the barrel tip each shot for visual debugging.
-- Must be false in any build shown to players.
Constants.DEBUG_BULLET_IMPACT_MARKERS             = false
Constants.DEBUG_BULLET_IMPACT_MARKER_SIZE         = 0.18   -- studs; sphere diameter
Constants.DEBUG_BULLET_IMPACT_MARKER_LIFETIME     = 0.08   -- seconds before destroy
Constants.DEBUG_BULLET_IMPACT_MARKER_TRANSPARENCY = 0.35

-- ── Local bullet impact FX (Stage 1) ────────────────────────────────────────────────────
-- Small, fast, material-specific visual response at the LOCAL predicted raycast hit point,
-- oriented to the surface normal. Client-only / visual-only: not replicated, never
-- consulted for damage / ammo / hit validation, no camera writes. Owned by the ImpactFX
-- helper inside GunController (extraction to an ImpactFXController is filed in
-- TECHNICAL_DEBT). Gritty-realistic: tiny puffs / chips / sparks, short lifetimes, pooled
-- so full-auto reuses a fixed set of invisible rigs and never grows part count.
--
-- Each impact rig has three ParticleEmitters: DUST (soft smoke puff), DEBRIS (tiny solid
-- squares → chips / splinters / dirt), SPARK (bright sparkle, metal only). A category
-- table lists only the emitters it uses; a missing DUST / DEBRIS / SPARK sub-table means
-- that emitter is silent for the category. Textures are engine built-ins (no upload).
Constants.BULLET_IMPACT_FX = {
    ENABLED = true,
    DEBUG   = true,

    POOL_SIZE             = 24,     -- fixed pre-built invisible rigs; reused, never grown
    IMPACT_PART_LIFETIME  = 1.0,    -- seconds a rig stays "busy" before it can be reused
    IMPACT_SURFACE_OFFSET = 0.03,   -- studs the rig floats off the surface along the normal

    -- Particle textures. DUST needs a soft sprite (engine built-in, on every client);
    -- DEBRIS and SPARK use a blank texture = a small solid square, which reads as a
    -- chip / fragment / spark and avoids any "magic sparkle" look or asset dependency.
    DUST_TEXTURE   = "rbxasset://textures/particles/smoke_main.dds",
    DEBRIS_TEXTURE = "",
    SPARK_TEXTURE  = "",

    -- World-space downward pull per role (studs/s²). Chips/sparks fall fast; dust drifts.
    DUST_GRAVITY   = 4,
    DEBRIS_GRAVITY = 55,
    SPARK_GRAVITY  = 40,

    -- Enum.Material → category. Anything not listed falls back to "default"; a nil / bad
    -- material also falls back to "default" (never errors).
    MATERIAL_CATEGORY = {
        [Enum.Material.Concrete]    = "concrete",
        [Enum.Material.Brick]       = "concrete",
        [Enum.Material.Cobblestone] = "concrete",
        [Enum.Material.Rock]        = "concrete",
        [Enum.Material.Slate]       = "concrete",
        [Enum.Material.Asphalt]     = "concrete",
        [Enum.Material.Pavement]    = "concrete",
        [Enum.Material.Limestone]   = "concrete",
        [Enum.Material.Sandstone]   = "concrete",
        [Enum.Material.Basalt]      = "concrete",

        [Enum.Material.Metal]         = "metal",
        [Enum.Material.CorrodedMetal] = "metal",
        [Enum.Material.DiamondPlate]  = "metal",

        [Enum.Material.Wood]       = "wood",
        [Enum.Material.WoodPlanks] = "wood",

        [Enum.Material.Ground]     = "dirt",
        [Enum.Material.Grass]      = "dirt",
        [Enum.Material.LeafyGrass] = "dirt",
        [Enum.Material.Mud]        = "dirt",
        [Enum.Material.Sand]       = "dirt",
        [Enum.Material.Snow]       = "dirt",
    },

    -- Per-category emitter params. Sizes/speeds in studs & studs/s. count = 0 or a missing
    -- sub-table disables that emitter for the category. Kept small and short — but big
    -- enough to actually read at a few studs (DEBRIS/SPARK squares under ~0.12 studs are
    -- invisible in practice).
    CATEGORIES = {
        -- Concrete / brick / stone: gray dust puff + pale chips out of the surface.
        concrete = {
            DUST   = { count = 7, lifeMin = 0.18, lifeMax = 0.44, speedMin = 1.5, speedMax = 5,
                       sizeStart = 0.3, sizeEnd = 1.3, transparency = 0.3, spread = 55,
                       color = Color3.fromRGB(176, 172, 163) },
            DEBRIS = { count = 10, lifeMin = 0.18, lifeMax = 0.4, speedMin = 7, speedMax = 19,
                       size = 0.17, transparency = 0.0, spread = 34,
                       color = Color3.fromRGB(188, 183, 172) },
        },
        -- Metal: bright directional sparks + a thin wisp of gray smoke, almost no chips.
        metal = {
            DUST  = { count = 3, lifeMin = 0.1, lifeMax = 0.3, speedMin = 1, speedMax = 3,
                      sizeStart = 0.14, sizeEnd = 0.6, transparency = 0.45, spread = 38,
                      color = Color3.fromRGB(140, 140, 145) },
            SPARK = { count = 16, lifeMin = 0.05, lifeMax = 0.17, speedMin = 18, speedMax = 44,
                      size = 0.17, transparency = 0, spread = 24,
                      color = Color3.fromRGB(255, 238, 200) },
        },
        -- Wood: tan splinter puff + lots of light splinter fragments, little smoke, no sparks.
        wood = {
            DUST   = { count = 3, lifeMin = 0.14, lifeMax = 0.36, speedMin = 1, speedMax = 3.5,
                       sizeStart = 0.18, sizeEnd = 0.7, transparency = 0.4, spread = 42,
                       color = Color3.fromRGB(156, 124, 84) },
            DEBRIS = { count = 12, lifeMin = 0.16, lifeMax = 0.38, speedMin = 8, speedMax = 22,
                       size = 0.18, transparency = 0.0, spread = 26,
                       color = Color3.fromRGB(160, 122, 76) },
        },
        -- Dirt / grass / sand: low dirt puff + a few dark clumps, no sparks.
        dirt = {
            DUST   = { count = 7, lifeMin = 0.16, lifeMax = 0.42, speedMin = 1, speedMax = 4,
                       sizeStart = 0.26, sizeEnd = 1.15, transparency = 0.32, spread = 34,
                       color = Color3.fromRGB(110, 90, 64) },
            DEBRIS = { count = 8, lifeMin = 0.15, lifeMax = 0.34, speedMin = 5, speedMax = 15,
                       size = 0.15, transparency = 0.0, spread = 30,
                       color = Color3.fromRGB(92, 72, 50) },
        },
        -- Anything else: small neutral dust puff + a few neutral specks.
        default = {
            DUST   = { count = 6, lifeMin = 0.15, lifeMax = 0.42, speedMin = 1.5, speedMax = 4.5,
                       sizeStart = 0.24, sizeEnd = 1.05, transparency = 0.34, spread = 45,
                       color = Color3.fromRGB(154, 152, 146) },
            DEBRIS = { count = 7, lifeMin = 0.15, lifeMax = 0.34, speedMin = 6, speedMax = 16,
                       size = 0.15, transparency = 0.0, spread = 30,
                       color = Color3.fromRGB(150, 148, 142) },
        },
    },
}

-- ── ViewModelController procedural sway ──────────────────────────────────────────────────
-- A second, independent sway layer applied in ViewModelController's RenderStepped loop.
-- Stage 5A bob (VIEWMODEL_BOB_ENABLED above = false) and Stage 5A mouse sway factors
-- (VIEWMODEL_SWAY_HORIZONTAL/VERTICAL_FACTOR = 0 above) are disabled so this layer is the
-- sole source of weapon bob and mouse lag.  VIEWMODEL_SWAY_ENABLED (above) gates this entire
-- block; set it false to disable all procedural sway from ViewModelController.
--
-- Mouse-look weapon lag (two-spring model):
--   vmSwayMouseTarget accumulates raw delta, clamped to MAX, decaying at RETURN_SPEED.
--   vmSwayMouseCurrent chases vmSwayMouseTarget at SMOOTH_SPEED.
Constants.VIEWMODEL_SWAY_MOUSE_YAW_DEGREES   = 1.2    -- degrees of yaw per unit of accumulated delta
Constants.VIEWMODEL_SWAY_MOUSE_PITCH_DEGREES = 0.8
Constants.VIEWMODEL_SWAY_MOUSE_ROLL_DEGREES  = 0.35   -- counter-roll into the turn; felt more than seen
Constants.VIEWMODEL_SWAY_MOUSE_TRANSLATE_X   = 0.006  -- studs of lateral translation per unit
Constants.VIEWMODEL_SWAY_MOUSE_TRANSLATE_Y   = 0.004  -- studs of vertical translation per unit
Constants.VIEWMODEL_SWAY_MOUSE_SMOOTH_SPEED  = 18     -- lerp rate for vmSwayMouseCurrent chasing target
Constants.VIEWMODEL_SWAY_MOUSE_RETURN_SPEED  = 16     -- lerp rate for vmSwayMouseTarget decaying to zero
Constants.VIEWMODEL_SWAY_MOUSE_MAX           = 0.65   -- maximum magnitude of accumulated mouse delta

-- Movement bob: sine oscillation while moving. Replaces Stage 5A VIEWMODEL_BOB_ENABLED.
Constants.VIEWMODEL_MOVE_BOB_ENABLED      = true
Constants.VIEWMODEL_WALK_BOB_AMOUNT       = 0.013  -- studs; max vertical bob while walking
Constants.VIEWMODEL_WALK_BOB_SPEED        = 6      -- rad/s sine phase advance while walking
Constants.VIEWMODEL_SPRINT_BOB_AMOUNT     = 0.026
Constants.VIEWMODEL_SPRINT_BOB_SPEED      = 9
Constants.VIEWMODEL_CROUCH_BOB_AMOUNT     = 0.006
Constants.VIEWMODEL_CROUCH_BOB_SPEED      = 4
Constants.VIEWMODEL_MOVE_BOB_SMOOTH_SPEED = 12     -- rate at which vmBobTime decays to zero when stopped
Constants.VIEWMODEL_WALK_BOB_LATERAL_FACTOR = 0.55  -- lateral sway as a fraction of vertical bob; cos(phase) for circular figure-8 path

-- Bob amplitude / speed smoothing: lerp between states to eliminate pops on walk→sprint, etc.
Constants.VIEWMODEL_BOB_AMOUNT_BLEND_SPEED  = 10    -- lerp speed for bob amplitude transitions
Constants.VIEWMODEL_BOB_SPEED_BLEND_SPEED   = 6     -- lerp speed for bob cycle-speed transitions

-- Vertical velocity tilt: gun pitches up when jumping, down when falling.
Constants.VIEWMODEL_VERT_TILT_ENABLED       = true
Constants.VIEWMODEL_VERT_TILT_SCALE         = 0.0012  -- radians of pitch per stud/s of Y velocity
Constants.VIEWMODEL_VERT_TILT_MAX           = 0.065   -- maximum tilt in radians (~3.7°)
Constants.VIEWMODEL_VERT_TILT_SMOOTH        = 8       -- lerp speed toward tilt target

-- Forward lean: gun lags behind horizontal velocity (inertia/weight feel).
Constants.VIEWMODEL_FORWARD_LEAN_ENABLED    = true
Constants.VIEWMODEL_FORWARD_LEAN_SCALE      = 0.0017  -- studs of Z lean per stud/s of forward velocity
Constants.VIEWMODEL_FORWARD_LEAN_MAX        = 0.05    -- maximum lean in studs
Constants.VIEWMODEL_FORWARD_LEAN_SMOOTH     = 12      -- lerp speed toward lean target

-- Landing dip spring: gun bounces down and recovers on landing.
Constants.VIEWMODEL_LAND_DIP_ENABLED        = true
Constants.VIEWMODEL_LAND_DIP_THRESHOLD      = -8      -- velY (studs/s) that triggers a dip
Constants.VIEWMODEL_LAND_DIP_SCALE          = 0.003   -- dip amount per stud/s of impact velocity
Constants.VIEWMODEL_LAND_DIP_SPRING         = 22      -- spring stiffness (higher = faster return)
Constants.VIEWMODEL_LAND_DIP_DAMPING        = 8       -- spring damping (lower = more bounce)

-- Idle breathing: subtle oscillation when the player is stationary.
Constants.VIEWMODEL_BREATH_ENABLED          = true
Constants.VIEWMODEL_BREATH_SPEED            = 0.25    -- breathing cycles per second (~4 s/breath)
Constants.VIEWMODEL_BREATH_AMOUNT_Y         = 0.003   -- vertical amplitude in studs
Constants.VIEWMODEL_BREATH_AMOUNT_X         = 0.0015  -- lateral amplitude in studs
Constants.VIEWMODEL_BREATH_BLEND_SPEED      = 2       -- lerp speed for breath fade in/out

-- Strafe roll: weapon rolls and slides when moving laterally relative to camera.
-- Spring-damper replaces the old lerp so reversing direction produces a subtle overshoot.
Constants.VIEWMODEL_STRAFE_ROLL_ENABLED   = true
Constants.VIEWMODEL_STRAFE_ROLL_DEGREES   = 0.9    -- degrees of roll at full strafe
Constants.VIEWMODEL_STRAFE_TRANSLATE_X    = 0.012  -- studs of lateral translation at full strafe
Constants.VIEWMODEL_STRAFE_SMOOTH_SPEED   = 14     -- legacy (unused; kept to avoid nil reads)
Constants.VIEWMODEL_STRAFE_SPRING_K       = 35     -- spring stiffness (higher = snappier return)
Constants.VIEWMODEL_STRAFE_SPRING_D       = 9      -- spring damping (lower = more overshoot)

-- Forward lean spring: replaces lerp so stopping causes a slight forward swing.
Constants.VIEWMODEL_FORWARD_LEAN_SPRING_K = 25     -- spring stiffness
Constants.VIEWMODEL_FORWARD_LEAN_SPRING_D = 7      -- spring damping

-- Vertical tilt spring: replaces lerp so jump apex / landing has organic bounce.
Constants.VIEWMODEL_VERT_TILT_SPRING_K    = 18     -- spring stiffness
Constants.VIEWMODEL_VERT_TILT_SPRING_D    = 5      -- spring damping

-- Acceleration tilt: gun pitches back when accelerating, forward when decelerating.
Constants.VIEWMODEL_ACCEL_TILT_ENABLED    = true
Constants.VIEWMODEL_ACCEL_TILT_SCALE      = 0.0015  -- radians per stud/s² of horizontal acceleration
Constants.VIEWMODEL_ACCEL_TILT_MAX        = 0.045   -- maximum tilt in radians (~2.6°)
Constants.VIEWMODEL_ACCEL_TILT_SMOOTH     = 8       -- lerp speed for vmAccelTilt chasing target

-- Bob depth and pitch: per-step Z compression and muzzle-nod on each footfall.
Constants.VIEWMODEL_BOB_DEPTH_FACTOR      = 0.20    -- Z amplitude as fraction of Y bob amplitude
Constants.VIEWMODEL_BOB_PITCH_FACTOR      = 1.4     -- pitch (rad) per stud of Y bob amplitude

-- Landing dip roll: subtle sideways tilt derived from the dip spring displacement.
Constants.VIEWMODEL_LAND_DIP_ROLL_SCALE   = 0.30    -- roll (rad) per stud of dip displacement

-- Breathing roll: third Lissajous frequency added to idle breathing oscillation.
Constants.VIEWMODEL_BREATH_AMOUNT_ROLL    = 0.0006  -- roll amplitude in radians

-- State weights [0, 1]: how much sway applies in each state.
-- ADS is nearly zero; all effects become imperceptible while aiming.
Constants.VIEWMODEL_SWAY_HIP_WEIGHT    = 1.0
Constants.VIEWMODEL_SWAY_ADS_WEIGHT    = 0.08
Constants.VIEWMODEL_SWAY_RELOAD_WEIGHT = 0.15
Constants.VIEWMODEL_SWAY_SPRINT_WEIGHT = 0.45

-- ── Camera rotation inertia (viewmodel-only — no camera movement) ──────────────────────────
-- Gun lags behind camera rotation and catches up smoothly, giving the weapon a sense of mass.
-- Only the viewmodel CFrame is offset; camera.CFrame, FieldOfView, and CameraOffset are untouched.
-- All rotation/translation offsets are in camera-local space.
Constants.VIEWMODEL_CAMERA_INERTIA_ENABLED = true   -- master switch; false = cameraInertiaCF is identity
Constants.VIEWMODEL_CAMERA_INERTIA_DEBUG   = false  -- Logger.debug on state changes and large-delta resets

-- Rotation strength: multiplied by camera yaw/pitch delta per frame; higher = stronger lag.
Constants.VIEWMODEL_CAMERA_INERTIA_YAW_STRENGTH   = 0.70  -- yaw lag per radian of camera yaw turn
Constants.VIEWMODEL_CAMERA_INERTIA_PITCH_STRENGTH = 0.52  -- pitch lag per radian of camera pitch turn
Constants.VIEWMODEL_CAMERA_INERTIA_ROLL_STRENGTH  = 0.24  -- roll tilt derived from yaw speed

-- Maximum angular displacement (degrees). Hard clamp; prevents wild swings.
Constants.VIEWMODEL_CAMERA_INERTIA_MAX_YAW_DEGREES   = 2.8
Constants.VIEWMODEL_CAMERA_INERTIA_MAX_PITCH_DEGREES = 2.1
Constants.VIEWMODEL_CAMERA_INERTIA_MAX_ROLL_DEGREES  = 1.1

-- Position offset: gun also translates slightly opposite to rotation (pendulum-mass illusion).
Constants.VIEWMODEL_CAMERA_INERTIA_POSITION_X_STRENGTH = 0.035  -- studs per radian of yaw delta
Constants.VIEWMODEL_CAMERA_INERTIA_POSITION_Y_STRENGTH = 0.025  -- studs per radian of pitch delta
Constants.VIEWMODEL_CAMERA_INERTIA_MAX_POSITION_X      = 0.055  -- hard clamp in studs
Constants.VIEWMODEL_CAMERA_INERTIA_MAX_POSITION_Y      = 0.040

-- Spring return: controls how quickly inertia settles back to neutral after camera stops.
-- effectiveDecayRate = SPRING_SPEED * (1 - DAMPING) = 18 * 0.18 = 3.24 /s → half-life ≈ 0.21 s.
-- Higher SPRING_SPEED = faster return. Lower DAMPING = faster return (less "stickiness").
Constants.VIEWMODEL_CAMERA_INERTIA_SPRING_SPEED = 18   -- per-second spring rate
Constants.VIEWMODEL_CAMERA_INERTIA_DAMPING      = 0.82 -- damping coefficient (0 = instant, 1 = never returns)

-- State multipliers. ADS is strongly suppressed so iron sight alignment stays stable.
-- During ADS transition (0 < adsAimAlpha < 1) both the multiplier AND the Lerp blend reduce inertia.
Constants.VIEWMODEL_CAMERA_INERTIA_ADS_MULTIPLIER    = 0.10  -- barely perceptible while aiming
Constants.VIEWMODEL_CAMERA_INERTIA_RELOAD_MULTIPLIER = 0.45  -- slightly reduced during reload
Constants.VIEWMODEL_CAMERA_INERTIA_EQUIP_MULTIPLIER  = 0.35  -- reduced during equip animation
Constants.VIEWMODEL_CAMERA_INERTIA_SPRINT_MULTIPLIER = 1.10  -- slightly amplified while running/sprinting

-- ── Viewmodel movement velocity inertia ───────────────────────────────────────────────────────
-- Gun shifts opposite to player movement velocity, giving the weapon a sense of carried weight.
-- Only the viewmodel CFrame is offset; camera.CFrame, velocity, animations, and gameplay are untouched.
Constants.VIEWMODEL_MOVEMENT_INERTIA_ENABLED = true   -- master switch; false = movementInertiaCF is identity
Constants.VIEWMODEL_MOVEMENT_INERTIA_DEBUG   = false  -- Logger.debug on weight changes

-- Position strengths: viewmodel offset (studs) per stud/s of camera-local velocity × dt per frame.
Constants.VIEWMODEL_MOVEMENT_INERTIA_STRAFE_X_STRENGTH   = 0.075  -- lateral strafe offset
Constants.VIEWMODEL_MOVEMENT_INERTIA_FORWARD_Z_STRENGTH  = 0.055  -- forward/back weight
Constants.VIEWMODEL_MOVEMENT_INERTIA_VERTICAL_Y_STRENGTH = 0.030  -- vertical velocity carry

-- Maximum positional displacement (studs). Hard clamp; prevents wild swings on velocity spikes.
Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_X = 0.090
Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_Y = 0.045
Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_Z = 0.075

-- Derived rotation from position offset (no separate spring — computed inline from position each frame).
Constants.VIEWMODEL_MOVEMENT_INERTIA_ROLL_STRENGTH     = 1.25  -- radians of roll per stud of X offset
Constants.VIEWMODEL_MOVEMENT_INERTIA_PITCH_STRENGTH    = 0.75  -- radians of pitch per stud of Z offset
Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_ROLL_DEGREES  = 1.4
Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_PITCH_DEGREES = 0.8

-- Spring return: effectiveDecayRate = SPRING_SPEED * (1 - DAMPING) = 14 * 0.22 = 3.08 /s.
Constants.VIEWMODEL_MOVEMENT_INERTIA_SPRING_SPEED = 14   -- per-second spring rate
Constants.VIEWMODEL_MOVEMENT_INERTIA_DAMPING      = 0.78 -- damping coefficient (0 = instant, 1 = never)

-- State multipliers: same pattern as camera rotation inertia.
Constants.VIEWMODEL_MOVEMENT_INERTIA_ADS_MULTIPLIER    = 0.08  -- nearly off while aiming (sights must stay stable)
Constants.VIEWMODEL_MOVEMENT_INERTIA_RELOAD_MULTIPLIER = 0.50  -- reduced during reload
Constants.VIEWMODEL_MOVEMENT_INERTIA_SPRINT_MULTIPLIER = 1.20  -- slightly amplified while sprinting
Constants.VIEWMODEL_MOVEMENT_INERTIA_CROUCH_MULTIPLIER = 0.65  -- reduced while crouching

-- Velocity gate: ignore speeds below MIN_SPEED (idle jitter / physics noise).
-- MAX_SPEED_REFERENCE caps velocity input range — no spike from a one-frame physics outlier.
Constants.VIEWMODEL_MOVEMENT_INERTIA_MIN_SPEED           = 1.5  -- studs/s — below this: no accumulation
Constants.VIEWMODEL_MOVEMENT_INERTIA_MAX_SPEED_REFERENCE = 24   -- studs/s — each axis clamped to this

-- ── Viewmodel wall collision (Tarkov-style close-quarters weapon retraction) ────────────────
-- ViewModelController casts one forward ray from the camera each RenderStepped; when it hits
-- geometry within PROBE_DISTANCE the whole viewmodel is pulled back toward the player (camera-
-- local +Z, same axis as positional recoil) and the muzzle tucks up, so the gun stops clipping
-- through the wall you walk into. Purely visual — bullets still originate from the camera / free-
-- aim solve in GunController, so point-blank aim is unchanged. Lerped for a soft ease in/out.
Constants.VIEWMODEL_WALL_COLLISION_ENABLED   = true   -- master switch; false → wallCF is identity
Constants.VIEWMODEL_WALL_COLLISION_DEBUG     = false  -- Logger.debug on large push changes
Constants.VIEWMODEL_WALL_PROBE_DISTANCE      = 5.0    -- studs; wall nearer than this along camera look → retract
Constants.VIEWMODEL_WALL_PROBE_BACKUP        = 1.0    -- studs; start the ray this far behind the camera so a wall at the camera plane still registers
Constants.VIEWMODEL_WALL_PUSH_MAX            = 2.4    -- studs; maximum backward pull of the viewmodel at a flush wall
Constants.VIEWMODEL_WALL_TUCK_MAX_DEG        = 20     -- degrees; muzzle tuck-up at full retract
Constants.VIEWMODEL_WALL_LERP_SPEED          = 14     -- per-second rate the current retract chases the target (framerate-independent)
Constants.VIEWMODEL_WALL_ADS_SCALE           = 0.5    -- multiplier on the retract while ADS (sights stay usable; you still can't aim through a wall)
Constants.VIEWMODEL_WALL_EPSILON             = 0.001  -- below this retract fraction → snap to zero / identity

-- ── Task A: ADS sprint disable + ADS focus zoom ─────────────────────────────────────────────
-- FOV values for the three camera states.  Sprint FOV (SPRINT_CAMERA_FOV,
-- TACTICAL_SPRINT_CAMERA_FOV) still applies when not ADS — these are ADS-specific.
-- CAMERA_DEFAULT_FOV mirrors DEFAULT_CAMERA_FOV (both = 70); the ADS system uses
-- CAMERA_DEFAULT_FOV so tuning ADS behaviour touches one clearly-named constant.
Constants.CAMERA_DEFAULT_FOV               = 70    -- no-ADS base FOV (matches DEFAULT_CAMERA_FOV)
Constants.CAMERA_ADS_FOV                  = 56    -- FOV while ADS with no focus key
Constants.CAMERA_ADS_FOCUS_FOV            = 52    -- FOV while ADS + CAMERA_ADS_FOCUS_KEY held
Constants.CAMERA_FOV_TWEEN_SPEED          = 18    -- FOV units per second; ADS tween duration = Δ/speed
Constants.CAMERA_ADS_FOCUS_KEY            = Enum.KeyCode.LeftShift  -- key for extra zoom while ADS
Constants.MOVEMENT_DISABLE_SPRINT_WHILE_ADS = true  -- LeftShift while ADS → focus zoom, not sprint
Constants.MOVEMENT_CANCEL_SPRINT_ON_ADS     = true  -- entering ADS while sprinting cancels sprint
Constants.ADS_FOCUS_ZOOM_ENABLED           = true   -- master switch for focus zoom (false → Shift is no-op)
Constants.ADS_BLOCK_PERSPECTIVE_SWITCH     = true   -- true → scroll-down cannot exit first-person while ADS active
Constants.ADS_FORCE_FIRST_PERSON          = true   -- true → entering ADS snaps to first-person; exiting restores previous mode

-- ── Task B: First-person stance POV height offsets ────────────────────────────────────────
-- Applied to Humanoid.CameraOffset.Y only (not camera.CFrame or FieldOfView).
-- Additive on landing: dip is layered on top of current stance offset.
-- ADS and reload multipliers scale the entire combined offset.
Constants.CAMERA_POV_ENABLED              = true    -- master switch; false → no stance offset writes
Constants.CAMERA_CROUCH_OFFSET_Y          = -1.0    -- studs; POV lowered while crouching
Constants.CAMERA_SLIDE_OFFSET_Y           = -1.45   -- studs; POV lowered while sliding
Constants.CAMERA_JUMP_OFFSET_Y            =  0.28   -- studs; lift during the jump arc (Task B; superseded by CAMERA_JUMP_LIFT_Y in Task D)
Constants.CAMERA_FALL_OFFSET_Y            = -0.16   -- studs; subtle drop during freefall (updated Task D)
Constants.CAMERA_LAND_LIGHT_DIP_Y         = -0.16   -- studs; landing impulse — light impact (updated Task D)
Constants.CAMERA_LAND_MEDIUM_DIP_Y        = -0.30   -- studs; landing impulse — medium impact (updated Task D)
Constants.CAMERA_LAND_HEAVY_DIP_Y         = -0.45   -- studs; landing impulse — heavy impact (updated Task D)
Constants.CAMERA_POV_SMOOTH_SPEED         =  14     -- lerp rate: how fast current tracks stance target
Constants.CAMERA_POV_LAND_RECOVER_SPEED   =   8     -- decay rate: how fast landing dip fades to zero
Constants.CAMERA_POV_ADS_MULTIPLIER       =  0.65   -- scale applied to offset while ADS
Constants.CAMERA_POV_RELOAD_MULTIPLIER    =  0.80   -- scale applied to offset while reloading

-- ── Task D: Criminality-style camera body feel ───────────────────────────────────────────
-- All offsets applied via Humanoid.CameraOffset only. No camera.CFrame changes.
-- updateCameraBodyFeel() in MovementController is the single writer of CameraOffset per frame.

Constants.CAMERA_BODY_FEEL_ENABLED        = true   -- master switch; false = no body camera offsets
Constants.CAMERA_BODY_OFFSET_SMOOTH_SPEED = 10     -- lerp rate (units/s) for stance Y/Z approach
Constants.CAMERA_BODY_BOB_FADE_IN_SPEED   = 5      -- lerp rate (units/s) for bob alpha fade-in when moving
Constants.CAMERA_BODY_OFFSET_RESET_SPEED  = 7      -- lerp rate (units/s) for bob fade-out when idle

-- Walk bob
Constants.CAMERA_WALK_BOB_ENABLED         = true   -- master switch for all bob types
Constants.CAMERA_WALK_BOB_AMOUNT_Y        = 0.035  -- studs; vertical bob amplitude while walking
Constants.CAMERA_WALK_BOB_AMOUNT_X        = 0.005  -- studs; horizontal sway amplitude while walking
Constants.CAMERA_WALK_BOB_SPEED           = 6      -- radians/s; sine phase advance while walking

-- Sprint bob
Constants.CAMERA_SPRINT_BOB_AMOUNT_Y      = 0.075  -- studs; vertical bob amplitude while sprinting
Constants.CAMERA_SPRINT_BOB_AMOUNT_X      = 0.009  -- studs; horizontal sway amplitude while sprinting
Constants.CAMERA_SPRINT_BOB_SPEED         = 9      -- radians/s; sine phase advance while sprinting

-- Crouch bob
Constants.CAMERA_CROUCH_BOB_AMOUNT_Y      = 0.012  -- studs; vertical bob amplitude while crouching
Constants.CAMERA_CROUCH_BOB_AMOUNT_X      = 0.003  -- studs; horizontal sway amplitude while crouching
Constants.CAMERA_CROUCH_BOB_SPEED         = 4      -- radians/s; sine phase advance while crouching

-- Stance Z offsets (applied to CameraOffset.Z; negative = camera pulls backward)
Constants.CAMERA_CROUCH_OFFSET_Z          = 0      -- studs; camera depth while crouching
Constants.CAMERA_SLIDE_OFFSET_Z           = -0.15  -- studs; camera pulls back slightly during slide

-- Jump lift (transient upward impulse at jump start; decays over CAMERA_JUMP_LIFT_DURATION)
Constants.CAMERA_JUMP_LIFT_Y              = 0.22   -- studs; lift magnitude at jump takeoff
Constants.CAMERA_JUMP_LIFT_DURATION       = 0.26   -- seconds; decay window for the lift impulse

-- Fall offset (CAMERA_FALL_OFFSET_Y already set above; MAX_Y is a sanity clamp)
Constants.CAMERA_FALL_OFFSET_MAX_Y        = -0.35  -- studs; max downward offset during freefall (clamp)

-- Landing dip recovery (replaces CAMERA_POV_LAND_RECOVER_SPEED = 8 for Task D)
Constants.CAMERA_LAND_RECOVERY_SPEED      = 10     -- decay rate; landing dip fades to zero at this speed

-- ADS and reload multipliers (replace CAMERA_POV_ADS/RELOAD_MULTIPLIER for Task D)
Constants.CAMERA_BODY_ADS_MULTIPLIER      = 0.45   -- scale applied to all body offsets + bob while ADS
Constants.CAMERA_BODY_RELOAD_MULTIPLIER   = 0.65   -- scale applied to all body offsets + bob while reloading

-- ── Task C: Criminality-style movement smoothing and body-yaw foundation ─────────────────
-- Do NOT add MOVEMENT_DISABLE_SPRINT_WHILE_ADS or MOVEMENT_CANCEL_SPRINT_ON_ADS here —
-- those were added in Task A and already exist above.

-- Movement speed smoothing — WalkSpeed ramps via acceleration/deceleration instead of snapping.
Constants.MOVEMENT_SMOOTH_SPEED_ENABLED    = true   -- master switch; false = instant snap (legacy)
-- Body weight: extra-drag multipliers applied to deceleration for a grounded, physical feel.
-- When false, sprint-exit and normal stop both use the base DECELERATION value with no scaling.
Constants.MOVEMENT_BODY_WEIGHT_ENABLED     = true   -- master switch for body-weight drag multipliers
Constants.MOVEMENT_BODY_WEIGHT_DEBUG       = false  -- log decel path changes via Logger.debug()
Constants.MOVEMENT_ACCELERATION            = 34     -- studs/s²: idle → walk ramp-up
Constants.MOVEMENT_DECELERATION            = 52     -- studs/s²: walk-state ramp-down (STOP_EXTRA_DRAG applies on top)
Constants.MOVEMENT_SPRINT_ACCELERATION     = 26     -- studs/s²: walk → sprint ramp-up (slower for body-weight feel)
Constants.MOVEMENT_SPRINT_DECELERATION     = 46     -- studs/s²: sprint-exit ramp-down (SPRINT_EXIT_EXTRA_DRAG applies on top)
Constants.MOVEMENT_CROUCH_ACCELERATION     = 40     -- studs/s²: crouch speed transition
Constants.MOVEMENT_AIR_ACCELERATION        = 14     -- studs/s²: while airborne (jump/fall)
Constants.MOVEMENT_STOP_EPSILON            = 0.05   -- studs/s; snap to target when |diff| < this
Constants.MOVEMENT_MIN_ACTIVE_INPUT        = 0.05   -- input magnitude below which idle is assumed
Constants.MOVEMENT_STOP_EXTRA_DRAG         = 1.15   -- multiplier on DECELERATION during normal walk ramp-down
Constants.MOVEMENT_SPRINT_EXIT_EXTRA_DRAG  = 1.05   -- multiplier on SPRINT_DECELERATION when exiting sprint

-- Body yaw smoothing — deg/frame at 60fps passed to rotateCharacterCapped().
-- MOVEMENT_BODY_YAW_SPRINT_SMOOTH_SPEED equals MAX_DELTA / 60 so sprint caps at the global limit.
Constants.MOVEMENT_BODY_YAW_SMOOTH_ENABLED               = true  -- master switch; false = use CUSTOM_MOUSE_LOCK_BODY_YAW_LERP_SPEED
Constants.MOVEMENT_BODY_YAW_WALK_SMOOTH_SPEED            = 7     -- deg/frame@60fps while walking
Constants.MOVEMENT_BODY_YAW_CROUCH_SMOOTH_SPEED          = 6     -- deg/frame@60fps while crouching
Constants.MOVEMENT_BODY_YAW_SPRINT_SMOOTH_SPEED          = 9     -- deg/frame@60fps while sprinting
Constants.MOVEMENT_BODY_YAW_BACKPEDAL_SMOOTH_SPEED       = 10    -- deg/frame@60fps while backpedaling
Constants.MOVEMENT_BODY_YAW_MAX_DELTA_DEGREES_PER_SECOND = 540   -- global cap; 540 / 60 = 9 deg/frame (sprint value)

-- ── Grounded turning weight (2026-06-13) ─────────────────────────────────────
-- Adds angular inertia to body yaw in custom mouse-lock so the character
-- "catches up" to camera direction rather than snapping instantly.
-- Only active in custom mouse-lock; normal mode uses Humanoid.AutoRotate.
-- SMOOTH_SPEED: dimensionless ramp rate (higher = faster build-up = less inertia).
-- MAX_DEGREES_PER_SECOND: peak turn rate the ramping speed asymptotes toward.
Constants.MOVEMENT_TURN_WEIGHT_ENABLED                       = true
Constants.MOVEMENT_TURN_WEIGHT_DEBUG                         = false

-- Per-state smooth factors (applied as factor * dt each Heartbeat toward peak rate).
Constants.MOVEMENT_TURN_WEIGHT_WALK_SMOOTH_SPEED             = 14   -- backward / strafe walk
Constants.MOVEMENT_TURN_WEIGHT_RUN_SMOOTH_SPEED              = 12   -- forward walk at WALK_SPEED
Constants.MOVEMENT_TURN_WEIGHT_SPRINT_SMOOTH_SPEED           = 8    -- sprint (reserved; Stage 3G owns sprint yaw)
Constants.MOVEMENT_TURN_WEIGHT_CROUCH_SMOOTH_SPEED           = 16   -- crouched movement (most responsive)

-- Per-state peak turn rate caps (deg/s). The current angular speed ramps toward this.
Constants.MOVEMENT_TURN_WEIGHT_MAX_DEGREES_PER_SECOND_WALK   = 420  -- ≈ 7.0 deg/frame@60fps (backward/strafe)
Constants.MOVEMENT_TURN_WEIGHT_MAX_DEGREES_PER_SECOND_RUN    = 360  -- ≈ 6.0 deg/frame@60fps (forward walk)
Constants.MOVEMENT_TURN_WEIGHT_MAX_DEGREES_PER_SECOND_SPRINT = 280  -- ≈ 4.7 deg/frame@60fps (sprint reserve)
Constants.MOVEMENT_TURN_WEIGHT_MAX_DEGREES_PER_SECOND_CROUCH = 360  -- ≈ 6.0 deg/frame@60fps (crouch)

-- Guards and resets.
Constants.MOVEMENT_TURN_WEIGHT_INPUT_DEADZONE                = 0.08  -- skip when moveVector.Magnitude < this
Constants.MOVEMENT_TURN_WEIGHT_MIN_MOVE_SPEED                = 1.5   -- skip when moveSmoothSpeed < this
Constants.MOVEMENT_TURN_WEIGHT_DISABLE_WHILE_AIRBORNE        = true  -- no inertia while falling / jumping
Constants.MOVEMENT_TURN_WEIGHT_DISABLE_WHILE_SLIDING         = true  -- no inertia during slide
Constants.MOVEMENT_TURN_WEIGHT_RESET_ON_STOP_SPEED           = 0.75  -- zero angular speed when nearly stopped

-- ============================================================
-- AKS74 shoot sound — first-person fire audio (Task: sound variants)
-- ============================================================
Constants.AKS74_SHOOT_SOUND_VOLUME              = 0.75
Constants.AKS74_SHOOT_SOUND_PLAYBACK_SPEED_MIN  = 0.82
Constants.AKS74_SHOOT_SOUND_PLAYBACK_SPEED_MAX  = 0.90
Constants.AKS74_SHOOT_SOUND_ROLLOFF_MIN_DISTANCE = 8
Constants.AKS74_SHOOT_SOUND_ROLLOFF_MAX_DISTANCE = 90
Constants.AKS74_SHOOT_SOUND_FADE_TIME           = 0.30  -- seconds for volume to decay to 0 after each shot
Constants.AKS74_SHOOT_SOUND_DEBUG               = false

-- ============================================================
-- Footstep sounds — client-side timer-based Stage 1
-- Stage 2: replace timer with animation marker listeners (LeftFootstep / RightFootstep).
-- ============================================================
Constants.FOOTSTEPS_ENABLED             = true
Constants.FOOTSTEP_DEBUG                = false
Constants.FOOTSTEP_MODE                 = "Timer"           -- "Timer" | "Marker" (Marker not yet implemented)
Constants.FOOTSTEP_MARKER_MODE_READY    = false             -- set true when marker events are wired
Constants.FOOTSTEP_MIN_SPEED            = 1.5               -- horizontal studs/s below which footsteps stop (uses HRP AssemblyLinearVelocity)
Constants.FOOTSTEP_GROUNDED_REQUIRED    = true              -- do not step while airborne
Constants.FOOTSTEP_EMITTER_NAME         = "FootstepEmitter" -- Attachment name under HumanoidRootPart

Constants.FOOTSTEP_ROLLOFF_MIN_DISTANCE = 5
Constants.FOOTSTEP_ROLLOFF_MAX_DISTANCE = 55

Constants.FOOTSTEP_WALK_INTERVAL        = 0.385 -- WalkForward clip 1.0s / 1.3x speed / 2 contacts per cycle
Constants.FOOTSTEP_RUN_INTERVAL         = 0.385 -- same WalkForward clip as Walk tier
Constants.FOOTSTEP_SPRINT_INTERVAL      = 0.25  -- RunForward clip 0.567s / 1.15x speed / 2 contacts ≈ 0.246s
Constants.FOOTSTEP_CROUCH_INTERVAL      = 0.50  -- CrouchWalk clip 1.0s / 1.0x speed / 2 contacts per cycle

Constants.FOOTSTEP_WALK_VOLUME          = 0.30
Constants.FOOTSTEP_RUN_VOLUME           = 0.46
Constants.FOOTSTEP_SPRINT_VOLUME        = 0.62
Constants.FOOTSTEP_CROUCH_VOLUME        = 0.14

Constants.FOOTSTEP_WALK_PITCH_MIN       = 0.80
Constants.FOOTSTEP_WALK_PITCH_MAX       = 0.88
Constants.FOOTSTEP_RUN_PITCH_MIN        = 0.84
Constants.FOOTSTEP_RUN_PITCH_MAX        = 0.92
Constants.FOOTSTEP_SPRINT_PITCH_MIN     = 0.88
Constants.FOOTSTEP_SPRINT_PITCH_MAX     = 0.96
Constants.FOOTSTEP_CROUCH_PITCH_MIN     = 0.72
Constants.FOOTSTEP_CROUCH_PITCH_MAX     = 0.80

Constants.FOOTSTEP_DEFAULT_SURFACE      = "Concrete"

-- ============================================================
-- Projectile ballistics foundation — data-driven defaults
-- PROJECTILE_BALLISTICS_ENABLED = false: all existing gameplay remains hitscan.
-- These constants are fallbacks used by Ballistics.GetConfig() when a weapon's
-- WeaponData.ballistics table omits a field. No code reads them during active
-- gameplay yet — they exist only for Ballistics module normalisation.
-- See DEBT-079 for the integration roadmap.
-- ============================================================
Constants.PROJECTILE_BALLISTICS_ENABLED         = false
Constants.PROJECTILE_BALLISTICS_DEBUG           = false
Constants.PROJECTILE_DEFAULT_MUZZLE_VELOCITY    = 2800    -- studs/s (AKS74 spec ≈ 880 m/s ≈ 2800 studs/s)
Constants.PROJECTILE_DEFAULT_GRAVITY_MULTIPLIER = 0.0     -- 0 = no drop; 1 = workspace.Gravity (≈ 196.2 studs/s²)
Constants.PROJECTILE_DEFAULT_MAX_DISTANCE       = 900     -- studs; discard projectile beyond this range
Constants.PROJECTILE_DEFAULT_MAX_LIFETIME       = 1.25    -- seconds; hard cap on simulation age
Constants.PROJECTILE_DEFAULT_SIMULATION_STEP    = 0.008333333333333333  -- seconds per sub-step (≈ 120 Hz)
Constants.PROJECTILE_DEFAULT_MAX_STEP_DISTANCE  = 55      -- studs; max travel per sub-step before forced subdivision

-- Client presentation bounds; these never award ammo or decide server reload results.
Constants.VIEWMODEL_RELOAD_LOAD_TIMEOUT = 3
Constants.VIEWMODEL_RELOAD_MAX_DURATION = 10

-- Same recovery bounds for the equip animation: if the asset never loads (LOAD_TIMEOUT)
-- or a loaded track never reports completion (MAX_DURATION), the weapon still resumes
-- idle/run instead of freezing at bind pose indefinitely.
Constants.VIEWMODEL_EQUIP_LOAD_TIMEOUT = 3
Constants.VIEWMODEL_EQUIP_MAX_DURATION = 10

-- Same recovery bounds for ADS-in/ADS-out: prevents a stuck "Entering"/"Exiting" state
-- from leaving IsAiming() permanently true, which would otherwise silently swallow every
-- future shot's fire animation (PlayADSFireAnimation only plays while adsState=="Aiming").
Constants.VIEWMODEL_ADS_LOAD_TIMEOUT = 3
Constants.VIEWMODEL_ADS_MAX_DURATION = 10

-- ============================================================
-- Destruction — wood/door breakable props (2026-09-08)
-- Bullet-driven only. No explosive/AoE damage yet — see docs/DESTRUCTION_SYSTEM_PLAN.md.
-- ============================================================

-- Any Anchored BasePart anywhere in workspace tagged with this attribute (a string key
-- into Constants.DESTRUCTION_PROFILES) is registered as breakable by DestructionService
-- at server start. A door is not one part — Studio authors it as several parts (e.g. left
-- panel / right panel / frame), each independently tagged, so shooting one panel breaks
-- only that panel (the Rainbow Six Siege behavior the owner asked for). DestructionService
-- has no special "door" concept; this attribute-per-part model is what gives that behavior.
Constants.BREAKABLE_PROFILE_ATTRIBUTE = "BR_BreakableProfile"
Constants.BREAKABLE_HEALTH_ATTRIBUTE  = "BR_Health"
Constants.BREAKABLE_BROKEN_ATTRIBUTE  = "BR_Broken"

-- Health per breakable profile. Wood = 80 covers doors, crates, fences, planks — any wood
-- prop — and takes 3 accepted hits from AR15's 28 damage, matching the already-tuned value
-- from the isolated prototypes/CityDistrict/DestructionService.lua's "Timber" profile.
Constants.DESTRUCTION_PROFILES = {
    Wood = { Health = 80 },
}

Constants.DESTRUCTION_MAX_REGISTERED_PARTS    = 800   -- registration budget; see Logger warnings if exceeded
Constants.DESTRUCTION_MAX_DAMAGE_PER_HIT      = 100   -- clamps a single hit so a bad WeaponData value can't overflow
Constants.DESTRUCTION_IMPACT_TOLERANCE        = 1.5   -- studs; slack around a part's bounds for the hit-point check
Constants.DESTRUCTION_MAX_LIVE_FRAGMENTS      = 64    -- global cosmetic debris cap across all breaks
Constants.DESTRUCTION_FRAGMENTS_PER_BREAK     = 3
Constants.DESTRUCTION_FRAGMENT_LIFETIME       = 2.5   -- seconds before cosmetic debris is removed
Constants.DESTRUCTION_FRAGMENT_SCALE          = 0.22
Constants.DESTRUCTION_FRAGMENT_MIN_SIZE       = 0.15
Constants.DESTRUCTION_FRAGMENT_MAX_SIZE       = 2
Constants.DESTRUCTION_FRAGMENT_SPEED          = 12
Constants.DESTRUCTION_FRAGMENT_LIFT           = 6
Constants.DESTRUCTION_FRAGMENT_SPIN           = 4
Constants.DESTRUCTION_MIN_DIRECTION_MAGNITUDE = 0.001
Constants.DESTRUCTION_DEBRIS_FOLDER_NAME      = "BR_Debris"

-- ============================================================
-- Combat — hit regions, damage types, developer test dummy, ragdoll impulse (2026-09-09)
-- Consumed by DamageService / DamageRules (server), GunService (server),
-- DummyService (server), RagdollService (server).
-- See docs/DAMAGE_TEST_DUMMY_PLAN.md. Gore/dismemberment is intentionally out of scope.
-- ============================================================

-- Damage type tags. Mirrors Types.DamageType — keep both in sync (see Types.lua SYNC WARNING).
-- Values are singleton-typed so `Constants.DamageType.Bullet` is assignable to Types.DamageType
-- in --!strict callers without a cast at every use site.
Constants.DamageType = {
    Bullet    = "Bullet"    :: "Bullet",
    Explosion = "Explosion" :: "Explosion",
    Melee     = "Melee"     :: "Melee",
    Fall      = "Fall"      :: "Fall",
    Zone      = "Zone"      :: "Zone",
    Unknown   = "Unknown"   :: "Unknown",
}

-- Hit regions for R6 rigs. Mirrors Types.HitRegion — keep both in sync. Singleton-typed
-- for the same reason as DamageType above.
Constants.HitRegion = {
    Head     = "Head"     :: "Head",
    Torso    = "Torso"    :: "Torso",
    LeftArm  = "LeftArm"  :: "LeftArm",
    RightArm = "RightArm" :: "RightArm",
    LeftLeg  = "LeftLeg"  :: "LeftLeg",
    RightLeg = "RightLeg" :: "RightLeg",
    Unknown  = "Unknown"  :: "Unknown",
}

-- Per-region damage multiplier applied by DamageRules.ComputeFinalDamage.
-- "Unknown" MUST stay 1.0 so the legacy DamageService:Apply path is byte-for-byte unchanged.
Constants.DAMAGE_REGION_MULTIPLIERS = {
    Head     = 2.0,
    Torso    = 1.0,
    LeftArm  = 0.85,
    RightArm = 0.85,
    LeftLeg  = 0.8,
    RightLeg = 0.8,
    Unknown  = 1.0,
}

-- Maps an R6 BasePart.Name to a HitRegion. DamageRules.RegionForPart returns
-- Constants.HitRegion.Unknown for anything not listed here.
Constants.R6_PART_REGIONS = {
    ["Head"]             = "Head",
    ["Torso"]            = "Torso",
    ["HumanoidRootPart"] = "Torso",
    ["Left Arm"]         = "LeftArm",
    ["Right Arm"]        = "RightArm",
    ["Left Leg"]         = "LeftLeg",
    ["Right Leg"]        = "RightLeg",
}

-- Hard clamp on a single resolved hit so a bad WeaponData value multiplied by a
-- region multiplier can never one-frame-delete a high-health entity.
Constants.DAMAGE_MAX_PER_HIT = 500

-- CollectionService tags and instance attributes. Systems key off these, never off
-- hardcoded instance paths.
Constants.TAG_DAMAGE_ENTITY      = "BR_DamageEntity"     -- any Humanoid Model GunService may damage through the shared pipeline (test dummies + AIService grunt NPCs)
Constants.TAG_DAMAGE_DUMMY       = "BR_DamageDummy"      -- developer test dummy; DummyService owns registration / death / reset
Constants.ATTR_INFINITE_HEALTH   = "BR_InfiniteHealth"   -- model attribute: DamageService still fires damage events but does not reduce Humanoid.Health
Constants.ATTR_REACTIONS_ENABLED = "BR_ReactionsEnabled" -- reserved for HitReactionService (Stage 5, not yet built)
Constants.ATTR_BLOOD_ENABLED     = "BR_BloodEnabled"     -- reserved for BloodService (Stage 4, not yet built)
-- Player attribute (2026-09-11): AIService's own targeting (findVisibleTarget /
-- targetRootOf / the DamageDealt hit-reaction listener) skips a player entirely
-- while this is true — set server-side by AIService's SetAIInvisible remote
-- handler, requested by LoadoutMenu's "AI INVISIBILITY" toggle button. Persists
-- across respawns (a session toggle, like the crosshair toggle) until turned off.
Constants.ATTR_AI_INVISIBLE      = "BR_AIInvisible"

-- Developer gating. Dev-only tooling (dummy control UI, Stage 6) is accepted from a
-- player whose UserId is listed here, or from any client when RunService:IsStudio().
Constants.DEV_USER_IDS = {
    -- [175217234] = true,  -- fill in live-place developer UserIds; Studio is always allowed
}

-- ── AI Stage 1A — server-owned squad NPC foundation (AIService.server) ──────
-- Simple R6 rifleman "grunt" squads: easy to kill alone, dangerous in numbers.
-- ALL AI decisions are server-side. AIService spawns from Workspace/AISpawns,
-- patrols Workspace/AIPatrolPoints, and parents live NPCs under Workspace/AI.
-- NPCs are tagged Constants.TAG_DAMAGE_ENTITY, so the existing GunService →
-- DamageService path already lets player bullets kill them; AI shots damage
-- players through DamageService:ApplyDamage (no new remotes, no client AI).
-- All AI tuning lives here — no magic numbers in AIService.
Constants.AI = {
    ENABLED = true,
    DEBUG   = true,

    FOLDER_NAME        = "AI",             -- Workspace child holding live NPC models
    SPAWN_FOLDER_NAME  = "AISpawns",       -- Workspace folder of BasePart squad origins
    PATROL_FOLDER_NAME = "AIPatrolPoints", -- Workspace folder of BasePart patrol destinations

    -- AI arena / factions (2026-09-11): the Constants.AI_FACTIONS key every
    -- spawn resolves to when SpawnSquad's factionKey argument is omitted — every
    -- pre-existing spawn path (auto-spawn, RespawnBots, KillAllBots) stays on
    -- this one faction, so same-faction grunts never target each other and
    -- today's behavior is unchanged. See Constants.AI_FACTIONS below.
    DEFAULT_FACTION = "DEFAULT",

    -- Bugfix (2026-09-11): raised from 12 — with both AI arenas' auto-battles
    -- running alongside the main game's own AI zone, steady-state demand is
    -- up to MAX_SQUADS*DEFAULT_SQUAD_SIZE (6) + AI_ARENA.SQUAD_SIZE*2 (8) +
    -- AI_ARENA_2.SQUAD_SIZE*2 (6) = 20 living grunts at once. At 12 the two
    -- arenas' own spawnArenaSquad retry loops were starving each other for
    -- the shared budget — confirmed in testing as "only the red squad spawns,
    -- blue never does" (red spawns first in each arena's battle loop and used
    -- up what little room existed). 30 covers that 20 with real headroom.
    MAX_ACTIVE_NPCS    = 30,
    DEFAULT_SQUAD_SIZE = 3,
    MAX_SQUADS         = 2,

    -- ── Manual respawn (RespawnBots remote, fired from the LoadoutMenu button) ──
    -- Any player can request a full AI reset — every live/pending-cleanup grunt is
    -- destroyed immediately (no ragdoll; this is a manual reset, not a kill) and
    -- fresh squads spawn at the AISpawns points. One shared server-wide cooldown
    -- (not per-player) so it can't be spammed to grief other players' fights.
    RESPAWN_COOLDOWN_SECONDS = 8,

    -- ── Kill all (KillAllBots remote, fired from the LoadoutMenu button) ────────
    -- Unlike Respawn, this routes every live grunt through the REAL death path
    -- (Humanoid.Health = 0 → the existing Died handler → ragdoll + blood + the
    -- normal DEATH_CLEANUP_DELAY corpse timer) instead of an instant destroy, and
    -- does not spawn replacements — the AI zone just goes quiet until the next
    -- Respawn Bots press or server restart. Same shared, not-per-player, cooldown
    -- pattern as RESPAWN_COOLDOWN_SECONDS.
    KILL_ALL_COOLDOWN_SECONDS = 5,

    SPAWN_ON_SERVER_START_IN_STUDIO    = true,
    -- Published servers previously never spawned any AI at all (this flag did not
    -- exist, so the Studio-only gate below silently skipped every live server).
    -- Same on/off pattern as Constants.DEV_TEST_AREA.RUN_IN_PUBLISHED, which is what
    -- actually builds the Workspace/AISpawns + AIPatrolPoints parts AIService reads.
    SPAWN_ON_SERVER_START_IN_PUBLISHED = true,
    SPAWN_DELAY_BETWEEN_NPCS           = 0.2,

    NPC_RIG_TYPE    = "R6",
    NPC_NAME_PREFIX = "BR_Grunt",

    NPC_HEALTH      = 80,
    NPC_WALK_SPEED  = 12,
    NPC_CHASE_SPEED = 15,

    THINK_INTERVAL            = 0.25,
    -- Reserved since Stage 1A for a throttled ComputeAsync pass "in a later
    -- stage" (see its own comment history) — that stage is AI dynamic
    -- navigation's Constants.AI_NAVIGATION.PATH_RECALCULATE_INTERVAL (1.5s)
    -- below, a separate field per that task's own required table, not a rename
    -- of this one. This field is left declared, still unread by AIService, per
    -- the project's "don't remove existing values" convention — see
    -- docs/TECHNICAL_DEBT.md "AI dynamic navigation".
    PATH_RECALCULATE_INTERVAL = 1.0,  -- reserved, unused; see comment above
    TARGET_RECHECK_INTERVAL   = 0.35,

    DETECTION_RANGE            = 120,
    LOSE_TARGET_RANGE          = 160,
    ATTACK_RANGE               = 90,
    LINE_OF_SIGHT_HEIGHT_OFFSET = 2.5,

    BURST_SHOTS_MIN      = 2,
    BURST_SHOTS_MAX      = 4,
    SECONDS_BETWEEN_SHOTS  = 0.16,
    SECONDS_BETWEEN_BURSTS = 1.2,
    SHOT_DAMAGE         = 8,
    SHOT_SPREAD_DEGREES = 4.0,
    SHOT_RANGE          = 220,

    DEATH_CLEANUP_DELAY = 6,

    -- Extra Stage 1A tuning (still Constants.AI — not magic numbers).
    SQUAD_SPACING           = 6,   -- studs between squad members around leader/patrol/spawn
    PATROL_ARRIVE_DISTANCE  = 8,   -- leader within this of a patrol point → advance the squad index
    LAST_SEEN_CHASE_SECONDS = 3,   -- keep chasing a lost target's last position this long
    ATTACK_MOVE_SPEED       = 6,   -- WalkSpeed while in Attack (slow, not a hard stop)

    -- ── Stage 1C — grunt weapon model + third-person animation ─────────────
    -- AIService clones ReplicatedStorage/WorldModels/<worldModelName> onto the
    -- grunt's Right Arm exactly like WorldWeaponService does for players, and
    -- loads the same WeaponData thirdPerson equip/idle/fire clips + default R6
    -- idle/walk onto the grunt's Humanoid.Animator. The gun only sits right while
    -- the thirdPerson `idle` pose is playing (WORLD_AKS74_GRIP_C0/C1 are identity).
    WEAPON_NAME               = Constants.DEFAULT_VIEWMODEL_WEAPON,  -- WeaponData key: world model + thirdPerson anims
    USE_WORLD_WEAPON          = true,   -- weld WorldModels/<worldModelName> to the Right Arm
    USE_THIRD_PERSON_ANIMS    = true,   -- load thirdPerson equip/idle/fire on the grunt Animator
    USE_LOCOMOTION_ANIMS      = true,   -- default R6 idle/walk driven off Humanoid speed
    LOCOMOTION_IDLE_ANIM_ID   = "rbxassetid://180435571",  -- Roblox default R6 idle
    LOCOMOTION_WALK_ANIM_ID   = "rbxassetid://180426354",  -- Roblox default R6 walk
    LOCOMOTION_WALK_SPEED_MIN = 0.5,   -- Humanoid speed at/above this → walk clip, else idle
    WEAPON_IDLE_ANIM_FADE     = 0.2,
    WEAPON_EQUIP_ANIM_FADE    = 0.1,
    WEAPON_FIRE_ANIM_FADE     = 0.05,

    -- ── Stage 1D — face target while engaging + take cover between bursts ───
    -- Grunts turn to look at the player (AutoRotate is off; faceToward drives it)
    -- and, after each burst, relocate to a raycast-found spot that breaks line of
    -- sight for COVER_DURATION seconds, then peek out and fire again.
    FACE_TARGET         = true,
    FACE_TURN_ALPHA     = 0.4,     -- HumanoidRootPart CFrame:Lerp per think toward the face direction
    TAKE_COVER          = true,
    COVER_DURATION      = 3.0,     -- seconds in cover before re-peeking
    COVER_SEEK_DISTANCE = 16,      -- studs from the grunt to test for a cover spot
    -- Fuller ring so a grunt can find cover to the side / slightly toward the player
    -- (a pillar), not only directly away from them. 0 = straight away from the target.
    COVER_SAMPLE_ANGLES = { 0, 25, -25, 50, -50, 80, -80, 115, -115, 150, -150, 180 },
    -- The obstacle that breaks LOS must be within this of the candidate spot, else the
    -- grunt would be hiding behind some far wall while still exposed up close. Picking
    -- the candidate with the *nearest* such obstacle puts the grunt on the far side of
    -- it, hugging cover, out of the player's view.
    COVER_HUG_DISTANCE  = 7,
    -- Covering fire while retreating (2026-09-10, user-reported: grunts jogged to
    -- cover in dead silence instead of fighting on the way there). While NOT YET at
    -- the cover spot, the grunt periodically stops, faces the player, and fires a
    -- burst back — then resumes walking. Once actually arrived it still goes fully
    -- quiet as before (that part of Cover is unchanged). false = old silent retreat.
    COVER_RETREAT_FIRE     = true,
    COVER_RETREAT_SHOT_MIN = 1.4,   -- seconds; minimum gap between retreat covering-fire bursts
    COVER_RETREAT_SHOT_MAX = 2.2,

    -- ── Stage 1E — fight from cover, react to fire, flank a stale target ───
    HURT_COVER            = true,  -- taking any hit arms the cover window immediately
    FIGHT_FROM_COVER      = true,  -- Attack walks to a cover-adjacent spot that still has LOS before planting
    FIGHT_SEEK_DISTANCE   = 10,    -- studs: radius searched for a fighting position
    FIGHT_ARRIVE_DIST     = 3,     -- within this of the fighting position → plant + fire
    COVER_ADJACENT_RADIUS = 6,     -- an obstacle within this of a spot = "beside cover"
    FIGHT_SAMPLE_ANGLES   = { 0, 35, -35, 70, -70, 110, -110, 145, -145, 180 },
    SEARCH_DURATION       = 12,    -- total seconds to hunt a lost target before returning to patrol
    FLANK_OFFSET_DISTANCE = 14,    -- max lateral offset when approaching a stale last-known position
    FLANK_CURVE_DISTANCE  = 30,    -- beyond this range the full offset applies; nearer → converge on the spot

    -- ── Stage 1F — crouch behind cover + weapon-vs-wall retraction ─────────
    -- Master switch: preloads the crouch AnimationTrack at all. The grunt only
    -- actually crouches once it has ARRIVED at a real cover/fighting spot — never
    -- while still moving there — and it fires normally while crouched (2026-09-10:
    -- previously it stood to fire and crouched the instant it decided to retreat,
    -- even mid-sprint across open ground, which looked wrong).
    CROUCH_IN_COVER     = true,
    CROUCH_ANIM_FADE    = 0.25,
    -- The player's own third-person crouch idle
    -- (Constants.MOVEMENT_ANIMATION_IDS.R6.Unarmed.CrouchIdle). AIService reads it
    -- from there at load; this is the fallback if that table's shape ever changes.
    CROUCH_IDLE_ANIM_ID = "rbxassetid://81947601552045",

    WALL_STANDOFF = 4,             -- keep cover / fighting positions this many studs clear of a wall in front

    GUN_COLLISION_ENABLED  = true,
    GUN_COLLISION_DISTANCE = 5,    -- forward ray length; a wall nearer than this retracts the gun + right arm
    GUN_RETRACT_MAX        = 2.2,  -- max studs the welded gun + right arm pull back
    GUN_RETRACT_TUCK_DEG   = 30,   -- max degrees the muzzle tucks up as it retracts
    GUN_RETRACT_ALPHA      = 0.35, -- lerp per think toward the target retract amount (0 = clear, 1 = flush against wall)

    -- ── Stage 1G — death ragdoll (same RagdollService path the test dummies use) ──
    -- On Humanoid.Died the grunt is handed to RagdollService:Apply with an impulse
    -- built from its last accepted hit (Constants.RAGDOLL_WEAPON_IMPULSE by
    -- DamageInfo.sourceName, else RAGDOLL_IMPULSE_DEFAULT) — identical to
    -- DummyService.onDummyDied. The welded AKS-74 is removed first (its parts are
    -- held together by Motor6Ds that RagdollService would otherwise convert). Blood
    -- already works: BloodService reacts to the same CombatEvents.DamageDealt.
    RAGDOLL_ON_DEATH = true,

    -- ── Stage 1H — combat realism pass ──────────────────────────────────────
    -- None of this is new tactics (still per-grunt, still Humanoid:MoveTo, still no
    -- reload/grenades — those remain deliberately out of scope). It targets the
    -- "twitch-perfect clone" feel: a beat before a freshly-spotted target gets shot
    -- at, aim that is not identical rifle-to-rifle, and worse aim against a target
    -- that is actually moving.

    -- Reaction time: a random delay between a grunt acquiring a NEW live target
    -- (first sighting, or a different attacker on being shot from an unseen angle)
    -- and its first shot at that target. Re-engaging the SAME target after a
    -- Cover peek does not re-roll this — they already know where you are.
    REACTION_TIME_MIN = 0.15,
    REACTION_TIME_MAX = 0.45,

    -- Per-grunt aim skill: a spread multiplier rolled once at spawn (record.aimSkill)
    -- so not every grunt shoots with identical accuracy. 1.0 = Constants.AI.SHOT_SPREAD_DEGREES
    -- unchanged; clamped to [AIM_SKILL_MIN, AIM_SKILL_MAX].
    AIM_SKILL_VARIANCE = 0.35,
    AIM_SKILL_MIN       = 0.6,
    AIM_SKILL_MAX       = 1.5,

    -- Moving-target spread bonus: extra spread (degrees) added on top of the
    -- per-grunt skill spread, scaled by the target's current speed — a sprinting /
    -- strafing player is harder to hit than someone standing still. 0 speed = no
    -- bonus; AIM_MOVING_TARGET_SPEED_REF studs/s or faster = the full bonus.
    AIM_MOVING_TARGET_SPREAD_ENABLED    = true,
    AIM_MOVING_TARGET_SPEED_REF         = 24,   -- studs/s (roughly a sprinting player)
    AIM_MOVING_TARGET_SPREAD_BONUS_DEG  = 3.5,

    -- Wounded grunts hunker down longer than a fresh one on the same cover timer —
    -- Cover / hurt-reaction both read this via coverDurationFor().
    LOW_HEALTH_RATIO           = 0.3,   -- Humanoid.Health / MaxHealth at/below this counts as "wounded"
    LOW_HEALTH_COVER_MULTIPLIER = 1.8,  -- COVER_DURATION is multiplied by this while wounded
}

-- ── AI Stage 1B — combat feedback FX for AIService grunts ───────────────────
-- Server-created, world-replicated placeholder visuals/audio so players can SEE
-- and HEAR AI fire: a tiny muzzle flash + smoke puff + light pulse + optional
-- tracer beam + a 3D gunshot sound, all owned by AIService. Emitters / light /
-- sound are built ONCE per NPC (under an auto-created "AIMuzzleAttachment" on the
-- grunt's Right Arm, or HumanoidRootPart if absent — a placeholder until AI
-- weapon models exist). Tracer parts are temporary, parented under Workspace/AI,
-- and Debris-cleaned. No new remotes; no client code; no damage-path change.
-- Placeholder asset IDs (rbxassetid://0) are tolerated — AIService warns once.
Constants.AI_COMBAT_FX = {
    ENABLED = true,
    DEBUG = true,

    MUZZLE_ATTACHMENT_NAME = "AIMuzzleAttachment",
    AUTO_CREATE_MUZZLE_ATTACHMENT = true,
    MUZZLE_FORWARD_OFFSET = 0,
    MUZZLE_UP_OFFSET = 0,
    MUZZLE_RIGHT_OFFSET = 0,

    FLASH_ENABLED = true,
    FLASH_TEXTURE = "rbxassetid://0",
    FLASH_EMIT_COUNT = 1,
    FLASH_LIFETIME_MIN = 0.025,
    FLASH_LIFETIME_MAX = 0.05,
    FLASH_SIZE_START = 0.35,
    FLASH_SIZE_END = 0.05,

    SMOKE_ENABLED = true,
    SMOKE_TEXTURE = "rbxassetid://0",
    SMOKE_EMIT_COUNT = 1,
    SMOKE_LIFETIME_MIN = 0.12,
    SMOKE_LIFETIME_MAX = 0.28,
    SMOKE_SPEED_MIN = 0.5,
    SMOKE_SPEED_MAX = 1.5,
    SMOKE_SIZE_START = 0.08,
    SMOKE_SIZE_END = 0.35,

    LIGHT_ENABLED = true,
    LIGHT_BRIGHTNESS = 1.5,
    LIGHT_RANGE = 6,
    LIGHT_DURATION = 0.035,

    TRACER_ENABLED = true,
    TRACER_LIFETIME = 0.055,
    TRACER_WIDTH_START = 0.045,
    TRACER_WIDTH_END = 0.015,
    TRACER_TRANSPARENCY_START = 0.15,
    TRACER_TRANSPARENCY_END = 1,

    SOUND_ENABLED = true,
    GUNSHOT_SOUND_ID = "rbxassetid://0",
    GUNSHOT_VOLUME = 0.45,
    GUNSHOT_PLAYBACK_SPEED_MIN = 0.96,
    GUNSHOT_PLAYBACK_SPEED_MAX = 1.04,
    GUNSHOT_ROLLOFF_MIN_DISTANCE = 12,
    GUNSHOT_ROLLOFF_MAX_DISTANCE = 180,

    CLEANUP_LIFETIME = 1.0,
}

-- ── AI Stage 1C — fair combat tuning (AIService.server) ─────────────────────
-- Reaction delay, aim ramp-up, suppression, target memory and per-squad attack
-- slots — makes one grunt beatable and a squad dangerous if ignored, without
-- aimbot accuracy. Layers on top of (does not replace) the earlier per-grunt
-- Constants.AI.AIM_SKILL_* / AIM_MOVING_TARGET_* spread factors — those are
-- unchanged, this is an additional multiplier for engagement freshness +
-- suppression. Supersedes Constants.AI.REACTION_TIME_MIN/MAX for the actual
-- fire-gate (see docs/TECHNICAL_DEBT.md "AI Stage 1C" — those two fields are
-- left in place, unread, rather than deleted).
Constants.AI_COMBAT_TUNING = {
    ENABLED = true,
    DEBUG = true,

    REACTION_TIME_UNAWARE_MIN = 0.55,
    REACTION_TIME_UNAWARE_MAX = 0.95,
    REACTION_TIME_ALERT_MIN = 0.25,
    REACTION_TIME_ALERT_MAX = 0.5,
    REACTION_TIME_RECENTLY_DAMAGED_MIN = 0.12,
    REACTION_TIME_RECENTLY_DAMAGED_MAX = 0.28,

    AIM_SETTLE_TIME = 1.6,
    INITIAL_SPREAD_MULTIPLIER = 2.25,
    FINAL_SPREAD_MULTIPLIER = 0.85,
    MAX_TRACKED_VISIBLE_TIME = 3.0,

    SUPPRESSED_SPREAD_MULTIPLIER = 1.8,
    SUPPRESSED_DURATION = 1.4,
    RECENT_DAMAGE_SUPPRESSION_DURATION = 2.0,

    LAST_KNOWN_POSITION_MEMORY = 4.0,
    TARGET_SWITCH_COOLDOWN = 1.25,

    MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD = 2,
    ATTACK_SLOT_RECHECK_INTERVAL = 0.5,

    MIN_TIME_BETWEEN_DAMAGE_CALLS = 0.05,
}

-- ── AI squad spacing / anti-bunching (AIService.server) ─────────────────────
-- Loose formation slots around a squad anchor (leader if alive, else the average
-- of living members) so squadmates fan out instead of stacking on the exact same
-- point while patrolling, chasing, or taking cover. Simple offset-based formation,
-- not real tactical movement — no obstacle awareness, no pathfinding. Layers on
-- top of the per-grunt cover/fighting-position picking from earlier stages (which
-- already naturally spreads Attack/Cover goals per grunt); this targets the
-- "everyone runs to the identical point" cases: Chase, Search, Patrol/Idle.
Constants.AI_SQUAD_SPACING = {
    ENABLED = true,
    DEBUG = true,

    MIN_PERSONAL_SPACE      = 7,   -- studs; a squadmate's goal closer than this to another gets pushed away
    PREFERRED_PERSONAL_SPACE = 11, -- studs; not directly enforced, documents the target resting spacing MIN_PERSONAL_SPACE + SEPARATION_PUSH_DISTANCE approximates
    SEPARATION_PUSH_DISTANCE = 5,  -- studs; how far getSeparationAdjustedGoal nudges a goal away from a too-close squadmate

    FORMATION_SLOT_REASSIGN_INTERVAL = 3.0, -- seconds between periodic slot reassignment passes (also reassigned immediately on a member's death)
    FORMATION_SLOT_REACHED_DISTANCE  = 5,   -- studs; not a hard gate anywhere yet — reserved for a future "has this grunt reached its slot" check

    -- Slot 1 is the leader/anchor; it goes (almost) straight for the anchor point.
    -- Slots 2+ cycle through SLOT_OFFSETS[2..], each one's DIRECTION (not raw
    -- magnitude) scaled out to the context's spread radius below — SLOT_OFFSETS
    -- defines the formation's shape (who's left/right/rear), the radius constants
    -- define its scale per behavior.
    LEADER_SLOT_OFFSET = Vector3.new(0, 0, 0),
    SLOT_OFFSETS = {
        Vector3.new(0, 0, 0),
        Vector3.new(-10, 0, 5),
        Vector3.new(10, 0, 5),
        Vector3.new(-7, 0, 13),
        Vector3.new(7, 0, 13),
    },

    CHASE_SPREAD_RADIUS  = 14, -- studs; Chase and a fresh (non-stale) Search both fan out around the target at this radius
    COMBAT_SPREAD_RADIUS = 18, -- studs; Attack fallback when findFightingPosition finds no literal cover — fan out around the target instead of planting wherever combat range was reached
    IDLE_SPREAD_RADIUS   = 10, -- studs; Patrol/Idle fan out around the patrol point / squad spawn at this radius

    MOVE_GOAL_JITTER = 3,   -- studs; random +/- per axis added so goals don't perfectly overlap; also the "meaningfully changed" distance threshold for the MoveTo throttle below
    MOVE_GOAL_RECALCULATE_INTERVAL = 1.0, -- seconds; a travel MoveTo goal is only recomputed/reissued this often, or sooner if the underlying anchor moved past MOVE_GOAL_JITTER studs
}

-- ── AI squad fire discipline (AIService.server) ─────────────────────────────
-- Limits how many grunts in one squad actively pull the trigger at once, so a
-- 3-4 bot squad pressures the player instead of instantly deleting them with
-- everyone firing simultaneously. NOTE: MAX_ACTIVE_SHOOTERS_PER_SQUAD and
-- ATTACK_SLOT_RECHECK_INTERVAL duplicate (same values) Constants.AI_COMBAT_TUNING's
-- MAX_SIMULTANEOUS_ATTACKERS_PER_SQUAD / ATTACK_SLOT_RECHECK_INTERVAL from the
-- earlier "fair combat tuning" pass — AIService's attack-slot system was
-- consolidated in place to read this table as authoritative rather than running
-- two competing "who gets to shoot" gates; the AI_COMBAT_TUNING pair are left
-- in place, now unread. See docs/TECHNICAL_DEBT.md "AI squad fire discipline".
Constants.AI_FIRE_DISCIPLINE = {
    ENABLED = true,
    DEBUG = true,

    MAX_ACTIVE_SHOOTERS_PER_SQUAD = 2,
    ATTACK_SLOT_RECHECK_INTERVAL  = 0.5,  -- seconds between updateSquadAttackSlots() passes per squad
    ATTACK_SLOT_TIMEOUT           = 2.5,  -- seconds; a slot is force-released after this even if still eligible, so one grunt can't hog it forever

    NON_SHOOTER_REPOSITION_INTERVAL_MIN = 1.5, -- seconds; how often a non-shooter picks a NEW support/hold-angle goal
    NON_SHOOTER_REPOSITION_INTERVAL_MAX = 3.5,

    HOLD_ANGLE_DISTANCE_MIN = 25, -- studs from the target; non-shooters "holding an angle" (watching, not closing in) pick a distance in this range
    HOLD_ANGLE_DISTANCE_MAX = 85,

    SUPPORT_MOVE_DISTANCE_MIN = 8,  -- studs from the target; non-shooters moving up to support pick a distance in this range instead
    SUPPORT_MOVE_DISTANCE_MAX = 22,

    WAITING_BOT_CAN_TRACK_TARGET = true,  -- non-shooters still faceToward the player instead of facing travel direction
    WAITING_BOT_CAN_CHASE        = true,  -- non-shooters may reposition (see the two interval/distance pairs above) instead of freezing in place
    WAITING_BOT_CAN_SHOOT        = false, -- escape hatch: true lets non-shooters fire anyway, bypassing the slot limit entirely — off by default, this IS the fire-discipline gate
}

-- ── AI squad awareness / last-known-position memory (AIService.server) ──────
-- One grunt spotting (or being hit by) the player puts its whole squad "on
-- edge" (a time-bounded alert, not sticky forever) and shares roughly where the
-- player was with living squadmates nearby, so they investigate instead of
-- staying oblivious — but a grunt without its OWN line of sight can never fire;
-- shared awareness only ever changes movement, never the shoot gate. NOTE:
-- squad reaction-tier selection now reads THIS table's timing (via the shared
-- alert deadline) instead of the old sticky Constants.AI_COMBAT_TUNING-driven
-- `squad.alerted` boolean from the earlier "fair combat tuning" pass — see
-- docs/TECHNICAL_DEBT.md "AI squad awareness" for that and the per-NPC
-- lastSawTargetAt / lastKnownTargetPosition fields this reuses instead of
-- duplicating (both already existed from that same earlier pass).
Constants.AI_SQUAD_AWARENESS = {
    ENABLED = true,
    DEBUG = true,

    ALERT_SHARE_RADIUS    = 85,  -- studs; only squadmates within this of the spotting/hit grunt become isAlertedBySquad
    ALERT_MEMORY_DURATION = 6.0, -- seconds; a sighting/hit keeps the squad on the fast "Alert" reaction tier this long
    LAST_KNOWN_POSITION_MEMORY = 4.0, -- seconds; how long the shared position stays fresh enough to actually walk toward
    LAST_KNOWN_POSITION_SHARE_INTERVAL = 0.75, -- seconds; throttles how often the shared position/alert broadcast actually re-runs, not every think

    INVESTIGATE_DISTANCE_MIN = 8,  -- studs; an alerted-but-blind squadmate picks a random offset this far from the shared position — not the exact point
    INVESTIGATE_DISTANCE_MAX = 20,
    INVESTIGATE_ARRIVE_DISTANCE = 7, -- studs; once within this of the current investigate spot with nothing found, pick a different nearby offset instead of idling there

    LOSE_TARGET_GRACE_TIME = 0.45, -- seconds after THIS grunt's own contact lapses before it starts relying on squad-shared data instead (this file's interpretation — see TECHNICAL_DEBT)
    CLEAR_ALERT_AFTER_NO_CONTACT = 7.0, -- seconds with no sighting/hit from ANY member before the whole squad's alert clears and everyone returns to Patrol/Idle

    REQUIRE_OWN_LOS_TO_SHOOT = true, -- documents (does not toggle — see attackSlotEligible) that shared awareness never lets a blind grunt shoot; "no wallhack shooting" is a hard invariant here, not tunable
}

-- ── AI squad bound-and-cover movement (AIService.server) ─────────────────────
-- A simplified, game-friendly "one bot advances while others hold" pass layered
-- on top of the existing Chase state: while a squad is alert with a shared
-- last-known target position (Constants.AI_SQUAD_AWARENESS) and not already
-- close enough to fight, one living member is picked as Mover and advances a
-- bound closer to the target; the rest hold in place instead of also rushing
-- forward. Once the squad is close enough (DO_NOT_BOUND_WITHIN_ATTACK_RANGE) or
-- not alert, bounding clears and Chase/Attack behave exactly as before this
-- pass. Not a cover-node system, not real fire-and-maneuver doctrine — see
-- docs/TECHNICAL_DEBT.md "AI squad bound-and-cover".
Constants.AI_BOUNDING = {
    ENABLED = true,
    DEBUG = true,

    BOUND_REEVALUATE_INTERVAL  = 1.25, -- seconds between updateSquadBounding() passes per squad — role assignment, not movement itself, is throttled to this
    MAX_MOVERS_PER_SQUAD       = 1,    -- hard cap on simultaneous movers; this pass only ever assigns one regardless
    MIN_COVERING_BOTS_REQUIRED = 1,    -- desired floor for a debug warning only — bounding still proceeds with fewer if the squad is small

    MOVE_BOUND_DISTANCE_MIN = 10, -- studs; the mover's bound destination advances this far toward the target, at most
    MOVE_BOUND_DISTANCE_MAX = 26,
    BOUND_ARRIVE_DISTANCE   = 6,  -- studs; within this of its bound destination, the mover is considered arrived

    COVER_HOLD_TIME_MIN = 1.0, -- seconds; reserved for a future randomized cover-hold duration (see docs/TECHNICAL_DEBT.md "AI squad bound-and-cover") — not yet read
    COVER_HOLD_TIME_MAX = 2.25,

    MOVER_SHOULD_NOT_SHOOT = true, -- the mover never starts a burst while it holds the Mover role, even if it briefly gains an attack slot + LOS mid-advance
    COVER_BOT_CAN_SHOOT    = true, -- false forces every non-mover bounding member to hold fire even with an attack slot + LOS (pure "watch and don't engage" cover) — true (default) leaves the existing fire-discipline gate as the only requirement

    SWAP_AFTER_MOVER_ARRIVES = true, -- once the mover reaches BOUND_ARRIVE_DISTANCE, the next reevaluation picks a new mover
    SWAP_AFTER_MAX_TIME      = 4.5,  -- seconds; a mover that hasn't arrived by this long is swapped out anyway (stuck-on-geometry safety net)

    DO_NOT_BOUND_WITHIN_ATTACK_RANGE = 18, -- studs; once the closest living squad member is this near the shared target position, stop bounding and let Chase/Attack/fire-discipline take over directly
}

-- ── AI dynamic big-map navigation (AIService.server) ──────────────────────────
-- Foundation-only navigation so squads work on a large map without hand-placed
-- Workspace/AIPatrolPoints: sampleReachableGroundNear() picks a random validated
-- ground point in a radius band via a downward raycast; computePath() /
-- followNavGoal() wrap PathfindingService (agent params below) for waypoint
-- travel, with a stuck check and a plain Humanoid:MoveTo fallback. Applied only
-- to Idle/Patrol dynamic roaming (when AIPatrolPoints doesn't exist — authored
-- points still work exactly as before) and the two "Search" state goals (stale
-- last-seen flank, squad-shared last-known-position investigate). Every combat
-- movement path (Chase-toward-a-live-target, Attack transit, Cover retreat,
-- bound-and-cover) is untouched, still a direct MoveTo — see
-- docs/TECHNICAL_DEBT.md "AI dynamic navigation" for that scoping and every
-- other simplification. Not a navmesh editor, not designer-authored AI zones,
-- not a strategic map-level planner, no doors/ladders/vaulting/climbing.
Constants.AI_NAVIGATION = {
    ENABLED = true,
    DEBUG = true,

    USE_PATHFINDING = true,

    PATH_RECALCULATE_INTERVAL     = 1.5,  -- seconds between PathfindingService compute attempts per NPC — the expensive call is throttled to this, never every think
    PATH_WAYPOINT_REACHED_DISTANCE = 5,   -- studs; also doubles as "goal changed enough to invalidate the current path" in followNavGoal
    PATH_STUCK_CHECK_INTERVAL     = 0.75, -- seconds between stuck-distance samples
    PATH_STUCK_DISTANCE_THRESHOLD = 1.5,  -- studs of root movement, per check, below which a grunt is considered not-progressing
    PATH_STUCK_TIME               = 2.0,  -- seconds of no progress before a grunt is flagged "stuck" (forces a repath attempt; callers like dynamicRoam may abandon the goal entirely)

    AGENT_RADIUS    = 2.5,
    AGENT_HEIGHT    = 5,
    AGENT_CAN_JUMP  = true,
    AGENT_CAN_CLIMB = false,
    WAYPOINT_SPACING = 6,

    RANDOM_ROAM_RADIUS_MIN = 35,  -- studs from squad spawn/anchor; dynamic Idle/Patrol roaming
    RANDOM_ROAM_RADIUS_MAX = 100,
    SEARCH_RADIUS_MIN      = 20,  -- studs from the squad's shared last-known target position; drives the squad-shared investigate goal offset (supersedes AI_SQUAD_AWARENESS.INVESTIGATE_DISTANCE_MIN/MAX in place — that pair is left declared, now unread)
    SEARCH_RADIUS_MAX      = 60,

    GROUND_SAMPLE_ATTEMPTS      = 10,  -- sampleReachableGroundNear retries before giving up and returning nil
    GROUND_SAMPLE_HEIGHT        = 80,  -- studs above the sample origin's Y that the validation raycast starts from
    GROUND_SAMPLE_DEPTH         = 160, -- studs the validation raycast casts downward
    MAX_GROUND_SLOPE_NORMAL_Y   = 0.55, -- a hit surface normal's Y must be at least this (≈56° from vertical) to count as walkable ground, not a wall/roof

    ROAM_GOAL_REACHED_DISTANCE = 8,   -- studs; how close counts as "arrived" at a roam goal
    ROAM_GOAL_COOLDOWN_MIN     = 2.5, -- seconds to wait after reaching (or abandoning) a roam goal before picking another
    ROAM_GOAL_COOLDOWN_MAX     = 5.0,

    FALLBACK_TO_MOVE_TO_ON_PATH_FAIL = true, -- if pathfinding fails/returns no waypoints, fall back to a direct Humanoid:MoveTo(goal) rather than the grunt freezing in place
    AIPATROLPOINTS_OPTIONAL          = true, -- documents the behavior collectParts()/thinkNPC already implement — Workspace/AIPatrolPoints missing or empty no longer warns as a misconfiguration and dynamic roaming takes over
}

-- ── AI shotgun (AIService.server) ─────────────────────────────────────────────
-- Gives "some of the AI" (a per-grunt random roll at spawn, CHANCE below —
-- independent of faction/squad/arena, so any squad can end up with a mix of
-- rifle and shotgun grunts) a WeaponData.PumpShotgun instead of the default
-- rifle (Constants.AI.WEAPON_NAME). Combat numbers here are AI's OWN
-- simplified tuning (PELLET_COUNT/SHOT_DAMAGE_PER_PELLET/etc.), independent
-- of WeaponData.PumpShotgun's own player-facing stats — same relationship
-- Constants.AI.SHOT_DAMAGE already has to WeaponData.AKS74.damage (never
-- read from there either). WeaponData.PumpShotgun.animations.thirdPerson is
-- intentionally empty (its presentation is procedural, client-only —
-- ShotgunPresentation.lua — which AI does not run), so a shotgun-grunt falls
-- back to the rifle's own thirdPerson idle/fire/equip clips (see
-- USE_RIFLE_THIRDPERSON_ANIM_FALLBACK) rather than standing in a raw,
-- unanimated pose; only the welded world-model mesh actually changes.
-- WeaponData.PumpShotgun.worldGripC0/C1 (the same fields WorldWeaponService
-- already reads for players) are reused as-is for the AI grip weld — no
-- separate copy kept here. See docs/TECHNICAL_DEBT.md "AI shotgun".
Constants.AI_SHOTGUN = {
    ENABLED = true,
    DEBUG   = true,

    WEAPON_KEY = "PumpShotgun", -- WeaponData key; also stored as NPCRecord.weaponKey / the BR_AIWeapon attribute
    CHANCE     = 0.3,           -- 0..1 probability a newly-spawned grunt carries a shotgun instead of the rifle

    USE_RIFLE_THIRDPERSON_ANIM_FALLBACK = true,

    PELLET_COUNT           = 6,
    SHOT_DAMAGE_PER_PELLET = 5,   -- 6 pellets landing all at once tops out around one solid rifle hit's worth of damage
    PELLET_SPREAD_DEGREES  = 6.0, -- extra spread cone on top of the usual aim-skill/aim-ramp/suppression spread — pellets scatter, a single rifle round doesn't
    SHOT_RANGE             = 90,  -- short — shotguns are a close-quarters weapon, unlike the rifle's longer SHOT_RANGE

    -- Shotguns don't "burst" like a rifle — one or two shells, then a slower
    -- pump-action recovery beat, not the rifle's rapid multi-shot burst.
    BURST_SHOTS_MIN = 1,
    BURST_SHOTS_MAX = 2,
    SECONDS_BETWEEN_SHOTS  = 0.9,
    SECONDS_BETWEEN_BURSTS = 2.2,
}

-- ── AI factions (AIService.server) ────────────────────────────────────────────
-- A grunt only ever targets / is targeted by another grunt when their factions
-- differ — see findVisibleTarget/fireOneShot in AIService.server.lua. DEFAULT
-- is what every existing spawn path (auto-spawn, RespawnBots, KillAllBots)
-- resolves to when Constants.AI.DEFAULT_FACTION / SpawnSquad's factionKey is
-- omitted, so same-faction grunts never fight each other — this table adding
-- ARENA_RED/ARENA_BLUE does not change any of today's single-faction behavior.
-- BODY_COLOR/LIMB_COLOR also give each faction's rig a distinct look (the
-- "designation" requested for the AI arena) — DEFAULT's colors are the
-- pre-existing grey grunt, unchanged.
Constants.AI_FACTIONS = {
    DEFAULT = {
        NAME       = "Grunt",
        BODY_COLOR = Color3.fromRGB(120, 122, 128),
        LIMB_COLOR = Color3.fromRGB( 96,  98, 104),
    },
    ARENA_RED = {
        NAME       = "Red Squad",
        BODY_COLOR = Color3.fromRGB(150,  45,  45),
        LIMB_COLOR = Color3.fromRGB(110,  32,  32),
    },
    ARENA_BLUE = {
        NAME       = "Blue Squad",
        BODY_COLOR = Color3.fromRGB( 45,  80, 150),
        LIMB_COLOR = Color3.fromRGB( 32,  58, 110),
    },
    -- Second, separate AI arena (2026-09-11) — same red/blue team colors as
    -- above (still just "red squad" / "blue squad" thematically), but a
    -- DIFFERENT faction key so this arena's battle and the first arena's
    -- battle never mix into one combined countLivingByFaction headcount.
    ARENA2_RED = {
        NAME       = "Red Squad",
        BODY_COLOR = Color3.fromRGB(150,  45,  45),
        LIMB_COLOR = Color3.fromRGB(110,  32,  32),
    },
    ARENA2_BLUE = {
        NAME       = "Blue Squad",
        BODY_COLOR = Color3.fromRGB( 45,  80, 150),
        LIMB_COLOR = Color3.fromRGB( 32,  58, 110),
    },
}

-- ── AI arena (AIArenaBuilder.server) ──────────────────────────────────────────
-- A separate generated test map — walls, scattered cover, one ramp structure —
-- so ARENA_RED vs ARENA_BLUE squads can be watched fighting each other,
-- exercising spacing/fire-discipline/awareness/bounding/dynamic-navigation
-- against a real opponent instead of just the player. Own sky-island ORIGIN,
-- clear of DEV_TEST_AREA's (Y 300) and the live map's (~Y 10-95). Entirely
-- separate from Workspace/AISpawns + AIPatrolPoints — those stay the main
-- game's, untouched; this arena computes its own spawn CFrames and calls
-- AIService.SpawnSquad directly. Foundation-only: not a designer AI-zone
-- editor, no scoring/UI — see docs/TECHNICAL_DEBT.md "AI arena / factions".
Constants.AI_ARENA = {
    ENABLED = true,
    DEBUG   = true,
    -- false = Studio only (safe default). true = also build it on a published
    -- server, same split as DEV_TEST_AREA.RUN_IN_PUBLISHED.
    RUN_IN_PUBLISHED = false,

    FOLDER_NAME = "BrokenReality_AIArena",
    ORIGIN      = Vector3.new(0, 600, 0),

    BASEPLATE_SIZE     = Vector3.new(170, 1, 170),
    BASEPLATE_POSITION = Vector3.new(0, -0.5, 0),

    WALL_HEIGHT    = 14,
    WALL_THICKNESS = 2,

    -- Opposite ends of the arena, ~130 studs apart with the scattered cover
    -- layout between them, so squads must advance to find each other instead
    -- of seeing each other the instant they spawn.
    RED_SPAWN_POSITION  = Vector3.new(0, 3, -65),
    BLUE_SPAWN_POSITION = Vector3.new(0, 3,  65),
    SPAWN_SPREAD        = 10, -- studs between individual squad-member spawn points along X

    SQUAD_SIZE = 4,

    -- Auto-spawns both squads on server start (Studio-gated like every other
    -- dev system) and, once either side's living count hits 0 (a battle
    -- conclusion, or an unrelated RespawnBots/KillAllBots wipe — this doesn't
    -- distinguish why), waits this long then respawns BOTH sides fresh — a
    -- hands-off, continuously-repeating AI-vs-AI test.
    AUTO_SPAWN_BATTLE     = true,
    BATTLE_CHECK_INTERVAL = 4,
    BATTLE_RESPAWN_DELAY  = 6,
    -- How long SpawnSquad is retried (AIService.Start() may not have run yet)
    -- before giving up with a Logger.warn.
    SPAWN_RETRY_INTERVAL = 0.5,
    SPAWN_RETRY_ATTEMPTS = 20,

    -- Spectating (TeleportToArena remote, AIService.server / LoadoutMenu "WATCH
    -- AI ARENA" button, 2026-09-11): how high above ORIGIN a requesting player is
    -- placed — comfortably above WALL_HEIGHT and the stepped structure for a full
    -- view. Client-side fly behavior itself is Constants.SPECTATOR_FLY, below.
    SPECTATE_HEIGHT = 60,
}

-- ── Second AI arena — corridor map (AIArenaCorridorBuilder.server) ───────────
-- A second, separate arena (2026-09-11, user-sketched layout) alongside the
-- first (Constants.AI_ARENA): an elongated room, solid north/south walls, open
-- east/west ends as the two team entrances, two tall "high wall" segments
-- blocking the centerline (with a gap between them as a crossing lane),
-- shorter "low cover" segments flanking them on both sides, and one L-shaped
-- elevated platform + staircase near each entrance — positioned so it's on
-- the RIGHT as that team walks in (south side near the west/red entrance,
-- north side near the east/blue entrance — a 180°-rotationally-symmetric,
-- fair layout). Own sky-island ORIGIN, clear of DEV_TEST_AREA (Y 300) and the
-- first AI arena (Y 600). Runs its own independent auto-spawn/self-healing
-- battle in AIService.server.lua under ARENA2_RED/ARENA2_BLUE — see
-- docs/TECHNICAL_DEBT.md "Second AI arena — corridor map" for the geometry's
-- first-guess numbers and every other scoping note.
Constants.AI_ARENA_2 = {
    ENABLED = true,
    DEBUG   = true,
    RUN_IN_PUBLISHED = false,

    FOLDER_NAME = "BrokenReality_AIArenaCorridor",
    ORIGIN      = Vector3.new(0, 900, 0),

    -- Room interior: X (east/west, the long axis) in [-100,100], Z (north/
    -- south) in [-55,55]. Baseplate is sized a bit larger so the spawn points
    -- (X = ±110) still sit on solid ground just outside the room proper.
    BASEPLATE_SIZE     = Vector3.new(260, 1, 130),
    BASEPLATE_POSITION = Vector3.new(0, -0.5, 0),

    -- North/south perimeter walls: stop short of the very ends (leaving the
    -- east/west entrances open) rather than fully enclosing the room.
    WALL_HEIGHT     = 16,
    WALL_THICKNESS  = 3,
    WALL_X_MIN      = -80,
    WALL_X_MAX      = 80,
    WALL_Z          = 55, -- north wall at -WALL_Z, south wall at +WALL_Z

    -- The two "high walls" down the centerline (X = 0), split in two along Z
    -- with a gap in the middle so squads can cross through the center lane
    -- instead of only flanking left/right.
    CENTER_WALL_HEIGHT    = 16,
    CENTER_WALL_THICKNESS = 3,
    CENTER_WALL_Z_INNER   = 15, -- gap spans [-CENTER_WALL_Z_INNER, +CENTER_WALL_Z_INNER]
    CENTER_WALL_Z_OUTER   = 55, -- each segment runs from Z_INNER out to Z_OUTER

    -- The shorter "low cover" segments flanking the center walls on both
    -- sides (X = ±COVER_X), same inner/outer gap shape, shorter and thinner.
    COVER_HEIGHT    = 5,
    COVER_THICKNESS = 2,
    COVER_X         = 35,
    COVER_Z_INNER   = 25,
    COVER_Z_OUTER   = 50,

    -- Team spawns at the open east/west ends.
    RED_SPAWN_POSITION  = Vector3.new(-110, 3, 0),
    BLUE_SPAWN_POSITION = Vector3.new(110, 3, 0),

    -- L-shaped platform + 3-step staircase near each entrance (south-west for
    -- red, north-east for blue — 180° rotations of each other). Height 6,
    -- matching the first arena's stepped structure; each step riser is 2 studs.
    PLATFORM_HEIGHT = 6,
    STEP_RISE       = 2,
    STEP_COUNT      = 3,

    SQUAD_SIZE = 3, -- smaller than the first arena's (4) — two arenas plus the
                     -- main game's own AI zone now share one MAX_ACTIVE_NPCS budget

    AUTO_SPAWN_BATTLE     = true,
    BATTLE_CHECK_INTERVAL = 4,
    BATTLE_RESPAWN_DELAY  = 6,
    SPAWN_RETRY_INTERVAL  = 0.5,
    SPAWN_RETRY_ATTEMPTS  = 20,
}

-- ── Spectator fly (SpectatorFlyController, client) ────────────────────────────
-- Free-fly / noclip movement so a player teleported above the AI arena (see
-- Constants.AI_ARENA.SPECTATE_HEIGHT) can move around and watch. Entirely
-- client-side (Humanoid.PlatformStand freezes normal locomotion; the
-- controller drives HumanoidRootPart.CFrame directly from camera-relative
-- input) — no server authority over spectator movement, same trust level as
-- every other purely-cosmetic camera/movement system in this game. Toggled by
-- TOGGLE_KEY at any time once granted (granted automatically on the
-- TeleportToArena confirmation; see docs/TECHNICAL_DEBT.md "AI arena
-- spectating" for why this isn't gated further).
Constants.SPECTATOR_FLY = {
    ENABLED = true,

    TOGGLE_KEY  = Enum.KeyCode.F,
    ASCEND_KEY  = Enum.KeyCode.Space,
    DESCEND_KEY = Enum.KeyCode.LeftControl,
    BOOST_KEY   = Enum.KeyCode.LeftShift, -- held for BOOST_SPEED instead of SPEED

    SPEED       = 60,  -- studs/second, camera-relative WASD + ascend/descend
    BOOST_SPEED = 150,
}

-- ── Developer test area (TestAreaBuilder.server) ────────────────────────────
-- Layout knobs for the generated developer sandbox under Workspace/<FOLDER_NAME>.
-- All positions are world-space offsets from ORIGIN.
-- TestAreaBuilder no-ops entirely unless ENABLED == true AND it is allowed to run
-- in the current context: always in Studio, and in a published server only when
-- RUN_IN_PUBLISHED == true. It destroys/rebuilds only the one folder it owns;
-- the opt-in exceptions that touch Workspace content outside that folder are all
-- reversible: REDIRECT_TEAM_SPAWNS (relocates Workspace/Spawns points),
-- SPAWN_DUMMIES (parents tagged R6 rigs to Workspace), and SPAWN_AI_ZONE (creates
-- the top-level Workspace/AISpawns + Workspace/AIPatrolPoints folders it owns).
-- Not a gameplay system.
--
-- ⚠ With RUN_IN_PUBLISHED = true the sandbox — and, if REDIRECT_TEAM_SPAWNS is on,
-- every real match spawn moved into it — ships to all players in the live game.
-- Set RUN_IN_PUBLISHED = false (or ENABLED = false) before any real release.
Constants.DEV_TEST_AREA = {
    ENABLED = true,
    -- false = Studio only (the safe default for a shipping build). true = also build
    -- it on a published server so `Play` / a published test place spawns you here too.
    RUN_IN_PUBLISHED = true,
    FOLDER_NAME = "BrokenReality_TestArea",

    -- Lifted well above the map (tallest map part ≈ Y 95; grass at the map origin ≈ Y 10)
    -- so the whole area floats clear in the sky and nothing is buried in terrain.
    -- Every prop, label and redirected spawn is placed as ORIGIN + local offset.
    ORIGIN = Vector3.new(0, 300, 0),

    -- Reversible: move every BasePart under Workspace/Spawns onto this test area so
    -- all players spawn here (runs wherever TestAreaBuilder runs — see RUN_IN_PUBLISHED).
    -- TestAreaBuilder stashes each spawn part's original CFrame in
    -- SPAWN_BACKUP_ATTRIBUTE before moving it, and restores every stashed spawn on
    -- each run first — so setting this false (keep ENABLED true) and starting one more
    -- server / Play puts all spawns back exactly where they were.
    REDIRECT_TEAM_SPAWNS = true,
    TEAM_SPAWN_GRID_SPACING = 4,
    SPAWN_BACKUP_ATTRIBUTE = "BR_TestAreaOriginalCFrame",

    BASEPLATE_SIZE = Vector3.new(220, 1, 220),
    BASEPLATE_POSITION = Vector3.new(0, -0.5, 0),

    SPAWN_POSITION = Vector3.new(0, 2, -80),

    SHOOTING_RANGE_START = Vector3.new(0, 1, -50),
    TARGET_DISTANCES = { 25, 50, 100, 150 },
    TARGET_SIZE = Vector3.new(5, 7, 1),

    IMPACT_WALL_POSITION = Vector3.new(35, 6, -35),
    IMPACT_WALL_SIZE = Vector3.new(1, 12, 35),

    SPRINT_LANE_POSITION = Vector3.new(-45, 0.05, -15),
    SPRINT_LANE_SIZE = Vector3.new(12, 0.2, 70),

    CROUCH_TUNNEL_POSITION = Vector3.new(-25, 2.5, 35),
    CROUCH_TUNNEL_SIZE = Vector3.new(18, 5, 20),
    CROUCH_TUNNEL_OPENING_HEIGHT = 3.5,

    LOW_VAULT_HEIGHT = 2.5,
    MEDIUM_VAULT_HEIGHT = 4.25,
    TOO_TALL_VAULT_HEIGHT = 6.0,

    DROP_TEST_HEIGHTS = { 4, 8, 14 },

    MATERIAL_TEST_POSITION = Vector3.new(55, 1, 35),

    -- AI patrol zone. Reversible, opt-in: TestAreaBuilder builds a small marked pad
    -- (a child of its own folder) AND, outside that folder, the top-level
    -- Workspace/AISpawns + Workspace/AIPatrolPoints folders (name-matched to
    -- Constants.AI.SPAWN_FOLDER_NAME / PATROL_FOLDER_NAME) that AIService reads.
    -- Those two folders carry AI_ZONE_OWNED_ATTRIBUTE so a rebuild only ever
    -- destroys folders it made itself — a hand-authored AISpawns/AIPatrolPoints is
    -- left untouched. Set SPAWN_AI_ZONE = false + start one more server to remove them.
    SPAWN_AI_ZONE          = true,
    AI_ZONE_POSITION       = Vector3.new(70, 0, 70),   -- local; a clear corner of the baseplate
    AI_ZONE_SIZE           = Vector3.new(48, 1, 48),   -- marked pad footprint
    AI_ZONE_SPAWN_COUNT    = 2,                        -- anchored squad-spawn parts
    AI_ZONE_PATROL_COUNT   = 4,                        -- anchored patrol-point parts (walked as a loop)
    AI_ZONE_MARKER_SIZE    = Vector3.new(3, 1, 3),     -- size of each spawn / patrol part
    AI_ZONE_OWNED_ATTRIBUTE = "BR_TestAreaOwned",      -- marks the folders TestAreaBuilder created

    -- Developer damage-test dummies. TestAreaBuilder builds N tagged R6 rigs
    -- (Constants.TAG_DAMAGE_DUMMY) so DummyService picks them up — shoot them to test
    -- damage, blood, hit reactions and ragdoll. They carry a BR_TestAreaDummy attribute
    -- so a rebuild (and DummyService's respawn clones) can be swept clean.
    SPAWN_DUMMIES = true,
    DUMMY_COUNT = 3,
    DUMMY_SPACING = 8,          -- studs between dummies along the firing line
    DUMMY_DOWNRANGE = 16,       -- studs in front of SHOOTING_RANGE_START

    DEBUG_LABELS = true,
}

-- Test dummy
Constants.DUMMY_DEFAULT_MAX_HEALTH  = 100
Constants.DUMMY_LIMB_MAX_HEALTH     = 100    -- per-limb pool; tracked from DamageDealt, does NOT gate death yet
Constants.DUMMY_RESPAWN_DELAY       = 3      -- seconds after death before auto-respawn
Constants.DUMMY_ATTR_MAX_HEALTH     = "BR_DummyMaxHealth"     -- optional per-instance Humanoid.MaxHealth override
Constants.DUMMY_ATTR_MANUAL_RESPAWN = "BR_ManualRespawn"      -- attribute = true → no auto-respawn; reset only
Constants.DUMMY_RUNTIME_ID_ATTRIBUTE = "BR_DummyRuntimeId"    -- set by DummyService; links a spawned model back to its record across respawns

-- ── Blood (Stage 4) ─────────────────────────────────────────────────────────
-- Server sends only { hitPosition, hitDirection, intensity, damageType } over BloodEffect;
-- BloodController (client) reproduces every visual. All caps are client-side.
Constants.BLOOD_ENABLED            = true   -- compile-time master switch
Constants.BLOOD_GLOBAL_ATTRIBUTE   = "BR_BloodGlobalEnabled"  -- runtime kill switch: attribute on ReplicatedStorage, server-set, read by both sides. Unset = on.
Constants.BLOOD_REFERENCE_DAMAGE   = 40     -- finalAmount that maps to intensity 1.0
Constants.BLOOD_MIN_INTENSITY      = 0.25   -- a hit always produces at least this much
Constants.BLOOD_EFFECT_RATE_LIMIT  = 0.045  -- min seconds between BloodEffect sends per target model
Constants.BLOOD_COLOR               = Color3.fromRGB(104, 12, 12)  -- fresh
Constants.BLOOD_COLOR_DARK          = Color3.fromRGB(56, 8, 8)     -- settled / venous — marks & particle tails lerp toward this

-- Client burst: a fine retrograde MIST (soft sprite) + heavier DROPLETS (square) that
-- arc and fall. Both spray back along -hitDirection, nudged upward.
Constants.BLOOD_POOL_SIZE            = 12    -- reused burst rigs (2 emitters each)
Constants.BLOOD_BURST_LIFETIME      = 1.1    -- seconds a rig stays busy before it can be reused
Constants.BLOOD_MIST_TEXTURE        = "rbxasset://textures/particles/smoke_main.dds"
Constants.BLOOD_MIST_BASE           = 7      -- mist particles at intensity 0
Constants.BLOOD_MIST_PER_INTENSITY  = 24     -- extra mist particles at intensity 1
Constants.BLOOD_MIST_SIZE_START     = 0.05
Constants.BLOOD_MIST_SIZE_END       = 0.34
Constants.BLOOD_MIST_LIFETIME_MIN   = 0.16
Constants.BLOOD_MIST_LIFETIME_MAX   = 0.42
Constants.BLOOD_MIST_SPEED_MIN      = 12
Constants.BLOOD_MIST_SPEED_MAX      = 30
Constants.BLOOD_MIST_SPREAD         = 34     -- half-cone degrees
Constants.BLOOD_MIST_GRAVITY        = 26
Constants.BLOOD_DROPLET_BASE           = 3
Constants.BLOOD_DROPLET_PER_INTENSITY  = 11
Constants.BLOOD_DROPLET_SIZE_START     = 0.13
Constants.BLOOD_DROPLET_SIZE_END       = 0.05
Constants.BLOOD_DROPLET_LIFETIME_MIN   = 0.35
Constants.BLOOD_DROPLET_LIFETIME_MAX   = 0.85
Constants.BLOOD_DROPLET_SPEED_MIN      = 7
Constants.BLOOD_DROPLET_SPEED_MAX      = 22
Constants.BLOOD_DROPLET_SPREAD         = 22
Constants.BLOOD_DROPLET_GRAVITY        = 130
Constants.BLOOD_SPRAY_UP_BIAS          = 0.35 -- how much the spray axis tilts toward world up

-- Client surface marks (texture-free flat parts). A character hit is split into: a few
-- SMALL splatters welded to the limb, a dark recessed WOUND ball ("carved flesh"), and a
-- BIGGER pool of marks on the floor found by casting straight down from the hit.
Constants.BLOOD_MARK_LIFETIME       = 18     -- seconds a floor mark lives
Constants.BLOOD_MARK_FADE_IN        = 0.1    -- seconds to fade a fresh mark/wound in
Constants.BLOOD_MARK_FADE_OUT       = 5      -- seconds of fade-out at the end of life
Constants.BLOOD_MARK_THICKNESS      = 0.04
Constants.BLOOD_MARK_TRANSPARENCY_MIN = 0.06 -- base opacity range (randomised per mark)
Constants.BLOOD_MARK_TRANSPARENCY_MAX = 0.3

-- Body splatter — small, welded to the hit limb so it rides the ragdoll / respawn.
Constants.BLOOD_BODY_MARK_COUNT     = 3
Constants.BLOOD_BODY_MARK_SIZE_MIN  = 0.18
Constants.BLOOD_BODY_MARK_SIZE_MAX  = 0.5
Constants.BLOOD_BODY_MARK_SPREAD    = 0.45   -- studs the small marks scatter around the entry
Constants.BLOOD_BODY_MARK_LIFETIME  = 22

-- Carved wound — a dark ball mostly sunk into the limb along the shot line.
Constants.BLOOD_WOUND_ENABLED       = true
Constants.BLOOD_WOUND_SIZE_MIN      = 0.16
Constants.BLOOD_WOUND_SIZE_MAX      = 0.4
Constants.BLOOD_WOUND_SINK          = 0.5    -- fraction of the ball buried in the surface
Constants.BLOOD_WOUND_COLOR         = Color3.fromRGB(34, 3, 3)
Constants.BLOOD_WOUND_LIFETIME      = 26
Constants.BLOOD_MAX_BODY_FX         = 44     -- ring buffer for body splatters + wounds combined

-- Floor pool — bigger marks below the hit.
Constants.BLOOD_GROUND_RANGE        = 14     -- studs to search downward for a floor
Constants.BLOOD_GROUND_MARK_SIZE_MIN = 0.6
Constants.BLOOD_GROUND_MARK_SIZE_MAX = 2.4
Constants.BLOOD_GROUND_SATELLITES   = 4      -- tiny spots around each floor mark
Constants.BLOOD_GROUND_SATELLITE_RANGE = 2.2 -- studs the satellites scatter
Constants.BLOOD_GROUND_SATELLITE_SIZE  = 0.4
Constants.BLOOD_MAX_MARKS           = 60     -- ring buffer for floor marks + their satellites

-- ── Hit reactions (Stage 5) ─────────────────────────────────────────────────
-- Procedural flinch written to Motor6D.Transform, decayed to identity. Never touches
-- C0/C1, PlatformStand, WalkSpeed or Motor6D.Enabled, so applying it to players later
-- cannot brick movement or weapons.
Constants.REACTION_REFERENCE_DAMAGE = 35     -- finalAmount that maps to strength 1.0
Constants.REACTION_DURATION         = 0.32   -- seconds to decay from full flinch back to neutral
Constants.REACTION_MAX_ANGLE_DEG    = 26     -- peak joint deflection at strength 1.0
Constants.REACTION_MAX_STACK        = 1.6    -- a fresh hit mid-flinch can push strength up to this
-- Region → which R6 Motor6D flinches. Missing / Unknown falls back to RootJoint (torso lean).
Constants.REACTION_REGION_JOINTS = {
    Head     = "Neck",
    Torso    = "RootJoint",
    LeftArm  = "Left Shoulder",
    RightArm = "Right Shoulder",
    LeftLeg  = "Left Hip",
    RightLeg = "Right Hip",
    Unknown  = "RootJoint",
}

-- ── Developer dummy control (Stage 6) ───────────────────────────────────────
Constants.DUMMY_DEV_STATE_INTERVAL = 0.2    -- seconds between DummyDevState snapshots to subscribed dev clients

-- Ragdoll (Stage 3). On the killing shot the body is converted to a physics rig and
-- shoved so deaths do not collapse identically.
--
-- Knockback is per-weapon: DummyService looks up RAGDOLL_WEAPON_IMPULSE by
-- DamageInfo.sourceName, falling back to RAGDOLL_IMPULSE_DEFAULT. impulse magnitude =
-- min(finalAmount * SCALE, MAX); direction = hitDirection tilted toward -Y by
-- RAGDOLL_IMPULSE_DOWN_BIAS; applied to the Torso via ApplyImpulseAtPosition at
-- RAGDOLL_IMPULSE_HEIGHT_OFFSET studs ABOVE it, so the off-centre shove tips the body
-- over instead of sliding it. AKS-74 is tuned to knock the body over without launching
-- it; give a future shotgun/launcher a big SCALE + MAX for flight.
Constants.RAGDOLL_IMPULSE_DEFAULT   = { SCALE = 4.5, MAX = 320 }
Constants.RAGDOLL_WEAPON_IMPULSE = {
    AKS74  = { SCALE = 4.5, MAX = 320 },  -- firm topple, no flight
    -- AR15 = { SCALE = 4.2, MAX = 300 },
    -- FUTURE_SHOTGUN = { SCALE = 12, MAX = 1100 },  -- sends the body flying
}
Constants.RAGDOLL_IMPULSE_DOWN_BIAS      = 0.1    -- tilt toward -Y so the body commits to falling
Constants.RAGDOLL_IMPULSE_HEIGHT_OFFSET  = 1.2    -- studs above the Torso the shove is applied (topple lever arm)
Constants.RAGDOLL_MAX_IMPULSE            = 1200   -- RagdollService hard safety ceiling (per-weapon MAX is the real limit)

-- BallSocketConstraint.UpperAngle per converted joint (degrees). A joint not listed
-- (RootJoint) uses RAGDOLL_BALLSOCKET_DEFAULT_ANGLE. Loose hips/shoulders + a loose
-- torso↔root link let the rig actually fall over instead of folding while upright.
Constants.RAGDOLL_BALLSOCKET_DEFAULT_ANGLE = 100
Constants.RAGDOLL_JOINT_ANGLES = {
    Neck               = 45,
    ["Left Shoulder"]  = 115,
    ["Right Shoulder"] = 115,
    ["Left Hip"]       = 115,
    ["Right Hip"]      = 115,
}
-- While ragdolled, drop CanCollide on the arms + legs so the collidable Torso slumps to
-- the ground instead of the rig balancing on rigid legs. Restored on Restore().
Constants.RAGDOLL_LIMB_NONCOLLIDE = true

-- Reference gunplay tuning, 2026-09-09. Angles in degrees; rates per second.
Constants.CAMERA_RECOIL_SPRING = 18
Constants.CAMERA_RECOIL_MAX_PITCH = 8
Constants.CAMERA_RECOIL_MAX_YAW = 2
Constants.CAMERA_RECOIL_MAX_VELOCITY = 160
Constants.RECOIL_BURST_RESET_DELAY = 0.18
Constants.RECOIL_BUILDUP_RECOVERY = 1.4

-- ============================================================
-- Muzzle FX — Stage 1 (2026-09-09)
-- Local, visual-only first-person muzzle flash / smoke / sparks / light. Built and played
-- entirely inside ViewModelController on the LOCAL client. No remotes, no server, no
-- replicated third-person flash, no camera writes, no combat/ammo/reload interaction.
--
-- Per-gun: DEFAULT holds every tunable; PROFILES[<weaponName>] overrides only the keys it
-- lists (everything else falls back to DEFAULT). So each weapon's flash/smoke/spark/light
-- can differ without duplicating the whole block. weaponName matches the value passed to
-- ViewModelController:EquipWeapon (e.g. Constants.DEFAULT_VIEWMODEL_WEAPON).
--
-- Textures are placeholder "rbxassetid://0" until real flash/smoke/spark art exists —
-- the system still runs (Roblox renders a default particle), and ViewModelController
-- Logger.warn()s once that they need replacing.
-- ============================================================
Constants.MUZZLE_FX = {
    ENABLED = true,
    DEBUG   = true,

    -- Attachment lookup: ViewModelController searches the viewmodel's descendants for an
    -- Attachment named any of these, in order. Expected authored name: "MuzzleAttachment".
    MUZZLE_ATTACHMENT_NAMES = {
        "MuzzleAttachment",
        "Muzzle",
        "BarrelAttachment",
    },

    -- If no muzzle Attachment is found, ViewModelController looks for a BasePart whose name
    -- contains "Barrel" or "Muzzle" and creates an Attachment named "MuzzleAttachment" at
    -- the far face along that part's LONGEST local axis (that axis is treated as the bore),
    -- offset outward by AUTO_ATTACHMENT_FORWARD_OFFSET, oriented so emitters fire outward.
    -- This is a fallback only — author a real MuzzleAttachment in Studio per weapon.
    AUTO_CREATE_ATTACHMENT_IF_MISSING = true,
    AUTO_ATTACHMENT_FORWARD_OFFSET    = 0,

    -- Base tunables. Every PROFILES entry is merged over this table.
    DEFAULT = {
        FLASH_TEXTURE = "rbxassetid://0",
        SMOKE_TEXTURE = "rbxassetid://0",
        SPARK_TEXTURE = "rbxassetid://0",

        FLASH_EMIT_COUNT = 1,
        SMOKE_EMIT_COUNT = 2,
        SPARK_EMIT_COUNT = 3,

        FLASH_LIFETIME_MIN = 0.025,
        FLASH_LIFETIME_MAX = 0.05,
        SMOKE_LIFETIME_MIN = 0.18,
        SMOKE_LIFETIME_MAX = 0.35,
        SPARK_LIFETIME_MIN = 0.04,
        SPARK_LIFETIME_MAX = 0.09,

        FLASH_SPEED_MIN = 0,
        FLASH_SPEED_MAX = 0,
        SMOKE_SPEED_MIN = 0.8,
        SMOKE_SPEED_MAX = 2.2,
        SPARK_SPEED_MIN = 4,
        SPARK_SPEED_MAX = 8,

        FLASH_SIZE_START = 0.35,
        FLASH_SIZE_END   = 0.05,
        SMOKE_SIZE_START = 0.12,
        SMOKE_SIZE_END   = 0.5,
        SPARK_SIZE       = 0.035,

        LIGHT_ENABLED    = true,
        LIGHT_BRIGHTNESS = 2.5,
        LIGHT_RANGE      = 7,
        LIGHT_DURATION   = 0.035,
    },

    -- Per-weapon overrides. Add a key per gun; anything omitted uses DEFAULT unchanged.
    PROFILES = {
        -- AKS-74 (5.45×39): slightly larger flash, more smoke, a touch more light.
        AKS74 = {
            FLASH_SIZE_START = 0.42,
            SMOKE_EMIT_COUNT = 3,
            SMOKE_SIZE_END   = 0.6,
            SPARK_EMIT_COUNT = 4,
            LIGHT_BRIGHTNESS = 3.0,
            LIGHT_RANGE      = 8,
        },
        -- AR-15 (5.56×45): tighter, cleaner flash, less smoke.
        AR15 = {
            FLASH_SIZE_START = 0.30,
            SMOKE_EMIT_COUNT = 2,
            SMOKE_SIZE_END   = 0.42,
            SPARK_EMIT_COUNT = 2,
            LIGHT_BRIGHTNESS = 2.2,
            LIGHT_RANGE      = 6,
        },
    },
}

return Constants
