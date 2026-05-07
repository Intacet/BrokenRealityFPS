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
Constants.DEATH_OVERLAY_OPACITY = 0.6  -- target opacity of the black screen overlay (0–1)
Constants.DEATH_BLUR_SIZE       = 24   -- target blur size applied to Lighting on death
Constants.DEATH_CLEANUP_TIME    = 0.5  -- seconds to tween the overlay and blur back out on PREP
Constants.DEATH_EQ_LOW_GAIN     = 0    -- EqualizerSoundEffect low-frequency gain on death (unchanged)
Constants.DEATH_EQ_MID_GAIN     = -50  -- EqualizerSoundEffect mid-frequency gain on death (heavy cut)
Constants.DEATH_EQ_HIGH_GAIN    = -60  -- EqualizerSoundEffect high-frequency gain on death (near silence)

return Constants
