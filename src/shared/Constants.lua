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
Constants.LOBBY_TIME        = 30  -- how long to wait in lobby after MIN_PLAYERS is reached
Constants.PREP_TIME         = 10  -- how long the prep countdown lasts before active play
Constants.ACTIVE_TIME       = 180 -- how long each active round lasts (3 minutes)
Constants.RESULTS_TIME      = 10  -- how long results are shown between rounds
Constants.RESULTS_DURATION  = 10  -- alias used by MatchService for the per-round end screen
Constants.MATCHEND_DURATION = 15  -- how long the match-end screen is shown before the next lobby

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

return Constants
