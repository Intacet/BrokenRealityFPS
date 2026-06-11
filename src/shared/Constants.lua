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
Constants.SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 0.18

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

-- ── Stage 3H: Sprint camera offset override ───────────────────────────────────
-- When true, Humanoid.CameraOffset is zeroed while sprinting in mouse lock,
-- removing the right-shoulder over-the-shoulder offset and centering the camera
-- directly behind the character. The offset is restored to CUSTOM_MOUSE_LOCK_CAMERA_OFFSET
-- the moment sprint ends (next Heartbeat, ≤16ms).
-- Normal sprint (LeftShift) and tactical sprint both trigger the zero-offset path.
-- Walking, idle, crouching, sprint-stop, and landing lock all keep the normal offset.
-- Set false to always use CUSTOM_MOUSE_LOCK_CAMERA_OFFSET regardless of sprint state.
Constants.SPRINT_DISABLES_CAMERA_OFFSET = true

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
-- First-person viewmodel ADS (aim down sights) — animation only
-- No FOV zoom, no camera changes — ADS is driven purely by animation playback.
-- ============================================================

-- Input type for ADS toggle (right mouse button).
Constants.ADS_INPUT_USER_INPUT_TYPE = Enum.UserInputType.MouseButton2

-- Fade time for ADS animation blend/transitions (in seconds).
Constants.VIEWMODEL_ADS_TRACK_FADE_TIME = 0.03

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
Constants.FREE_AIM_ENABLED                 = true

-- Hipfire deadzone radius in pixels (how far the crosshair can drift from center).
Constants.FREE_AIM_RADIUS_PIXELS           = 145

-- ADS deadzone radius in pixels (tighter; makes ADS feel steadier).
Constants.FREE_AIM_ADS_RADIUS_PIXELS       = 18

-- Scale factor applied to raw mouse delta before adding to aim offset.
-- 1.0 = one-to-one with raw delta; lower = sluggish/heavy; higher = hair-trigger.
Constants.FREE_AIM_MOUSE_GAIN              = 1.15

-- Return-to-center speed (lerp per second) when mouse is idle, hipfire.
Constants.FREE_AIM_RETURN_SPEED            = 7

-- Return-to-center speed (lerp per second) when mouse is idle, ADS.
Constants.FREE_AIM_ADS_RETURN_SPEED        = 22

-- Speed at which the visible crosshair position lerps toward the raw aim offset.
-- Higher = snappier tracking; lower = more pronounced trailing lag.
Constants.FREE_AIM_CROSSHAIR_SMOOTH_SPEED  = 18

-- Speed at which the viewmodel lean and inertia weight lerp toward their targets each frame.
-- Also governs how quickly the lean drains to zero during ADS.
Constants.FREE_AIM_VIEWMODEL_BLEND_SPEED   = 13

-- Maximum yaw (left/right) tilt of the viewmodel toward the aim point, in degrees.
-- Suppressed during ADS so iron sights stay centered (see ViewModelController).
Constants.FREE_AIM_VIEWMODEL_YAW_DEGREES   = 7

-- Maximum pitch (up/down) tilt of the viewmodel toward the aim point, in degrees.
-- Suppressed during ADS so iron sights stay centered (see ViewModelController).
Constants.FREE_AIM_VIEWMODEL_PITCH_DEGREES = 5

-- Maximum roll (clockwise tilt) of the viewmodel as the crosshair and inertia move horizontally.
-- Combined with mouse inertia contribution for a weighted, grounded feel.
-- Suppressed during ADS so iron sights stay centered (see ViewModelController).
Constants.FREE_AIM_VIEWMODEL_ROLL_DEGREES  = 4

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
Constants.FREE_AIM_HIP_WEIGHT              = 1.0
Constants.FREE_AIM_ADS_WEIGHT              = 0.18
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
-- absent. Normally WeaponData["AKS74"].rpm = 650 takes precedence; this constant is the
-- hard-coded sentinel so no magic number appears in controller code.
Constants.AKS74_DEFAULT_RPM = 650

-- ── Viewmodel recoil (data-driven per weapon; ApplyRecoil) ──────────────────────────────
-- Master switch. When false, ViewModelController:ApplyRecoil() is a no-op and the
-- vmRecoilCF inserted into PivotTo is CFrame.new() (identity — zero visual change).
Constants.VIEWMODEL_RECOIL_ENABLED = true

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

-- ── Debug bullet impact markers ─────────────────────────────────────────────────────────
-- When true, a neon sphere is rendered at the barrel tip each shot for visual debugging.
-- Must be false in any build shown to players.
Constants.DEBUG_BULLET_IMPACT_MARKERS             = false
Constants.DEBUG_BULLET_IMPACT_MARKER_SIZE         = 0.18   -- studs; sphere diameter
Constants.DEBUG_BULLET_IMPACT_MARKER_LIFETIME     = 0.08   -- seconds before destroy
Constants.DEBUG_BULLET_IMPACT_MARKER_TRANSPARENCY = 0.35

-- ── Bullet impact effect ────────────────────────────────────────────────────────────────
-- Subtle neutral sphere rendered at the raycast hit point each shot.
-- Set BULLET_IMPACT_ENABLED = false to disable entirely (no Part is created).
Constants.BULLET_IMPACT_ENABLED      = true
Constants.BULLET_IMPACT_SIZE         = 0.12    -- studs; sphere diameter
Constants.BULLET_IMPACT_LIFETIME     = 0.10    -- seconds before destroy
Constants.BULLET_IMPACT_TRANSPARENCY = 0.45
Constants.BULLET_IMPACT_COLOR        = Color3.fromRGB(170, 170, 170)

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
Constants.VIEWMODEL_WALK_BOB_AMOUNT       = 0.018  -- studs; max vertical bob while walking
Constants.VIEWMODEL_WALK_BOB_SPEED        = 6      -- rad/s sine phase advance while walking
Constants.VIEWMODEL_SPRINT_BOB_AMOUNT     = 0.035
Constants.VIEWMODEL_SPRINT_BOB_SPEED      = 9
Constants.VIEWMODEL_CROUCH_BOB_AMOUNT     = 0.008
Constants.VIEWMODEL_CROUCH_BOB_SPEED      = 4
Constants.VIEWMODEL_MOVE_BOB_SMOOTH_SPEED = 12     -- rate at which vmBobTime decays to zero when stopped

-- Strafe roll: weapon rolls and slides when moving laterally relative to camera.
Constants.VIEWMODEL_STRAFE_ROLL_ENABLED   = true
Constants.VIEWMODEL_STRAFE_ROLL_DEGREES   = 0.9    -- degrees of roll at full strafe
Constants.VIEWMODEL_STRAFE_TRANSLATE_X    = 0.012  -- studs of lateral translation at full strafe
Constants.VIEWMODEL_STRAFE_SMOOTH_SPEED   = 14     -- lerp rate for vmStrafeLag toward current strafe dot

-- State weights [0, 1]: how much sway applies in each state.
-- ADS is nearly zero; all effects become imperceptible while aiming.
Constants.VIEWMODEL_SWAY_HIP_WEIGHT    = 1.0
Constants.VIEWMODEL_SWAY_ADS_WEIGHT    = 0.08
Constants.VIEWMODEL_SWAY_RELOAD_WEIGHT = 0.15
Constants.VIEWMODEL_SWAY_SPRINT_WEIGHT = 0.45

-- ── Task A: ADS sprint disable + ADS focus zoom ────────────────────────────────────────────
-- FOV values for the three camera states.  Sprint FOV (SPRINT_CAMERA_FOV,
-- TACTICAL_SPRINT_CAMERA_FOV) still applies when not ADS — these are ADS-specific.
-- CAMERA_DEFAULT_FOV mirrors DEFAULT_CAMERA_FOV (both = 70); the ADS system uses
-- CAMERA_DEFAULT_FOV so tuning ADS behaviour touches one clearly-named constant.
Constants.CAMERA_DEFAULT_FOV               = 70    -- no-ADS base FOV (matches DEFAULT_CAMERA_FOV)
Constants.CAMERA_ADS_FOV                  = 62    -- FOV while ADS with no focus key
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
Constants.CAMERA_BODY_OFFSET_SMOOTH_SPEED = 16     -- lerp rate (units/s) for stance Y/Z approach
Constants.CAMERA_BODY_OFFSET_RESET_SPEED  = 22     -- lerp rate (units/s) for bob fade-out when idle

-- Walk bob
Constants.CAMERA_WALK_BOB_ENABLED         = true   -- master switch for all bob types
Constants.CAMERA_WALK_BOB_AMOUNT_Y        = 0.035  -- studs; vertical bob amplitude while walking
Constants.CAMERA_WALK_BOB_AMOUNT_X        = 0.012  -- studs; horizontal sway amplitude while walking
Constants.CAMERA_WALK_BOB_SPEED           = 6      -- radians/s; sine phase advance while walking

-- Sprint bob
Constants.CAMERA_SPRINT_BOB_AMOUNT_Y      = 0.075  -- studs; vertical bob amplitude while sprinting
Constants.CAMERA_SPRINT_BOB_AMOUNT_X      = 0.022  -- studs; horizontal sway amplitude while sprinting
Constants.CAMERA_SPRINT_BOB_SPEED         = 9      -- radians/s; sine phase advance while sprinting

-- Crouch bob
Constants.CAMERA_CROUCH_BOB_AMOUNT_Y      = 0.012  -- studs; vertical bob amplitude while crouching
Constants.CAMERA_CROUCH_BOB_AMOUNT_X      = 0.006  -- studs; horizontal sway amplitude while crouching
Constants.CAMERA_CROUCH_BOB_SPEED         = 4      -- radians/s; sine phase advance while crouching

-- Stance Z offsets (applied to CameraOffset.Z; negative = camera pulls backward)
Constants.CAMERA_CROUCH_OFFSET_Z          = 0      -- studs; camera depth while crouching
Constants.CAMERA_SLIDE_OFFSET_Z           = -0.15  -- studs; camera pulls back slightly during slide

-- Jump lift (transient upward impulse at jump start; decays over CAMERA_JUMP_LIFT_DURATION)
Constants.CAMERA_JUMP_LIFT_Y              = 0.22   -- studs; lift magnitude at jump takeoff
Constants.CAMERA_JUMP_LIFT_DURATION       = 0.16   -- seconds; decay window for the lift impulse

-- Fall offset (CAMERA_FALL_OFFSET_Y already set above; MAX_Y is a sanity clamp)
Constants.CAMERA_FALL_OFFSET_MAX_Y        = -0.35  -- studs; max downward offset during freefall (clamp)

-- Landing dip recovery (replaces CAMERA_POV_LAND_RECOVER_SPEED = 8 for Task D)
Constants.CAMERA_LAND_RECOVERY_SPEED      = 18     -- decay rate; landing dip fades to zero at this speed

-- ADS and reload multipliers (replace CAMERA_POV_ADS/RELOAD_MULTIPLIER for Task D)
Constants.CAMERA_BODY_ADS_MULTIPLIER      = 0.45   -- scale applied to all body offsets + bob while ADS
Constants.CAMERA_BODY_RELOAD_MULTIPLIER   = 0.65   -- scale applied to all body offsets + bob while reloading

-- ── Task C: Criminality-style movement smoothing and body-yaw foundation ─────────────────
-- Do NOT add MOVEMENT_DISABLE_SPRINT_WHILE_ADS or MOVEMENT_CANCEL_SPRINT_ON_ADS here —
-- those were added in Task A and already exist above.

-- Movement speed smoothing — WalkSpeed ramps via acceleration/deceleration instead of snapping.
Constants.MOVEMENT_SMOOTH_SPEED_ENABLED   = true   -- master switch; false = instant snap (legacy)
Constants.MOVEMENT_ACCELERATION           = 42     -- studs/s²: idle → walk ramp-up
Constants.MOVEMENT_DECELERATION           = 58     -- studs/s²: any state → idle ramp-down
Constants.MOVEMENT_SPRINT_ACCELERATION    = 34     -- studs/s²: walk → sprint ramp-up
Constants.MOVEMENT_CROUCH_ACCELERATION    = 48     -- studs/s²: crouch speed transition
Constants.MOVEMENT_AIR_ACCELERATION       = 14     -- studs/s²: while airborne (jump/fall)
Constants.MOVEMENT_STOP_EPSILON           = 0.05   -- studs/s; snap to target when |diff| < this
Constants.MOVEMENT_MIN_ACTIVE_INPUT       = 0.05   -- input magnitude below which idle is assumed

-- Body yaw smoothing — deg/frame at 60fps passed to rotateCharacterCapped().
-- MOVEMENT_BODY_YAW_SPRINT_SMOOTH_SPEED equals MAX_DELTA / 60 so sprint caps at the global limit.
Constants.MOVEMENT_BODY_YAW_SMOOTH_ENABLED               = true  -- master switch; false = use CUSTOM_MOUSE_LOCK_BODY_YAW_LERP_SPEED
Constants.MOVEMENT_BODY_YAW_WALK_SMOOTH_SPEED            = 18    -- deg/frame@60fps while walking
Constants.MOVEMENT_BODY_YAW_CROUCH_SMOOTH_SPEED          = 20    -- deg/frame@60fps while crouching
Constants.MOVEMENT_BODY_YAW_SPRINT_SMOOTH_SPEED          = 9     -- deg/frame@60fps while sprinting
Constants.MOVEMENT_BODY_YAW_BACKPEDAL_SMOOTH_SPEED       = 22    -- deg/frame@60fps while backpedaling
Constants.MOVEMENT_BODY_YAW_MAX_DELTA_DEGREES_PER_SECOND = 540   -- global cap; 540 / 60 = 9 deg/frame (sprint value)

return Constants
