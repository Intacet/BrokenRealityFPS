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
            WalkForward        = "rbxassetid://71329939839948",   -- confirmed-good R6 no-gun walk forward (Stage 2L)
            RunForward         = "rbxassetid://79045069356901",   -- confirmed-good R6 no-gun run forward  (Stage 2L)
            WalkLeft           = "rbxassetid://115652140967957",  -- no-gun strafe left
            WalkRight          = "rbxassetid://82804864629403",   -- no-gun strafe right
            WalkBackward       = "rbxassetid://107080862064563",  -- no-gun walk backward
            WalkBackwardLeft   = "rbxassetid://107785647885776",  -- no-gun backward-left diagonal
            WalkBackwardRight  = "rbxassetid://109190640713438",  -- no-gun backward-right diagonal
            WalkForwardLeft    = "rbxassetid://97324289156918",   -- no-gun walk forward-left diagonal
            WalkForwardRight   = "rbxassetid://81077784555491",   -- no-gun walk forward-right diagonal
            RunForwardLeft     = "rbxassetid://94337945101783",   -- no-gun run forward-left diagonal (Stage 2G)
            RunForwardRight    = "rbxassetid://104724352837263",  -- no-gun run forward-right diagonal (Stage 2G)
            Idle               = "rbxassetid://132044223555193",  -- no-gun standing idle (Stage 2H)
            EnterCrouch        = "rbxassetid://105064599119554",  -- no-gun enter-crouch one-shot (Stage 2H)
            ExitCrouch         = "rbxassetid://104596765238289",  -- no-gun exit-crouch one-shot (Stage 2H)
            -- Stage 2J: Unarmed directional crouch-walk animations
            -- CrouchWalk / CrouchWalkForward share the same ID (forward is the canonical clip).
            CrouchWalk            = "rbxassetid://82558685099409",   -- no-gun crouch walk forward (canonical fallback alias)
            CrouchWalkForward     = "rbxassetid://82558685099409",   -- no-gun crouch walk forward
            CrouchWalkBackward    = "rbxassetid://131295440357763",  -- no-gun crouch walk backward
            CrouchWalkLeft        = "rbxassetid://103170217015576",  -- no-gun crouch walk strafe left
            CrouchWalkRight       = "rbxassetid://84961452934451",   -- no-gun crouch walk strafe right
            CrouchWalkForwardLeft  = "rbxassetid://115919203745144", -- no-gun crouch walk forward-left diagonal
            CrouchWalkForwardRight = "rbxassetid://107284851359368", -- no-gun crouch walk forward-right diagonal
            CrouchWalkBackwardLeft  = "rbxassetid://118800024223445",-- no-gun crouch walk backward-left diagonal
            CrouchWalkBackwardRight = "rbxassetid://104285284019251",-- no-gun crouch walk backward-right diagonal
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
Constants.MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER              = 0.75  -- Idle plays at 0.75× clip speed (Stage 2H)
Constants.MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9   -- EnterCrouch/ExitCrouch one-shots play at 0.9× clip speed (Stage 2H)
Constants.MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER       = 1.0   -- CrouchWalk* directional tracks play at 1.0× clip speed (Stage 2J)

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
-- Client presentation flags (development / testing)
-- ============================================================
-- false = allow normal Roblox camera for development/testing and hide first-person viewmodel.
-- true  = lock first person and show first-person viewmodel during gameplay.
-- Set to true before shipping or playtesting the FPS experience.
-- See ViewModelController.lua and DEBT-048 for full context.
Constants.FORCE_FIRST_PERSON = false

return Constants
