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
    LOBBY   = "LOBBY",   -- server is waiting for enough players
    PREP    = "PREP",    -- brief countdown before the round starts (players read objectives)
    ACTIVE  = "ACTIVE",  -- round is live, players can fight and plant anchors
    RESULTS = "RESULTS", -- round ended, scores are shown before the next round
}

-- ============================================================
-- Match settings
-- ============================================================
Constants.MAX_ROUNDS   = 5  -- number of rounds per match
Constants.MIN_PLAYERS  = 2  -- minimum players needed before lobby countdown starts

-- ============================================================
-- Phase durations (in seconds)
-- Adjust these to change how long each phase lasts.
-- ============================================================
Constants.LOBBY_TIME   = 30  -- how long to wait in lobby after MIN_PLAYERS is reached
Constants.PREP_TIME    = 10  -- how long the prep countdown lasts before active play
Constants.ACTIVE_TIME  = 180 -- how long each active round lasts (3 minutes)
Constants.RESULTS_TIME = 10  -- how long results are shown between rounds

return Constants
