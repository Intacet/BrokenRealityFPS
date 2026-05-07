--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > MatchService
--
-- Owns the full match lifecycle: Lobby → (Prep → Active → Results) × MAX_ROUNDS → MatchEnd.
-- Fires RoundStateChanged every second so clients can update timers and phase labels.
-- Fires MatchEvents.PhaseChanged on every phase transition so server services can react.
-- Tracks round wins and announces the overall match winner during MATCHEND.
--
-- Early round ends: TeamService or ObjectiveService fires MatchEvents.RoundEndedEarly
-- with a winner string. countdown() captures this and runActive() passes it to runResults().
--
-- What this script does NOT do (handled by other services):
--   - Spawn or assign players to teams  →  TeamService
--   - Track objective capture progress  →  ObjectiveService
--   - Apply damage or health changes    →  DamageService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local GetMatchConfig    = Remotes:WaitForChild("GetMatchConfig")    :: RemoteFunction

-- Bridges phase changes and early-end signals to/from other server services.
local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

-- ============================================================
-- State
-- ============================================================

local currentPhase    : string = Constants.Phase.LOBBY
local currentRound    : number = 0
local currentTimeLeft : number = 0
local currentWinner   : string = ""

local attackerRoundWins : number = 0
local defenderRoundWins : number = 0

-- Tracks the last phase fired so PhaseChanged fires exactly once per transition.
local lastFiredPhase : string = ""

-- ============================================================
-- GetMatchConfig handler
--
-- A client calls this on join to get the current state immediately.
-- ============================================================

GetMatchConfig.OnServerInvoke = function(_player)
    return {
        phase        = currentPhase,
        round        = currentRound,
        maxRounds    = Constants.MAX_ROUNDS,
        timeLeft     = currentTimeLeft,
        winner       = currentWinner,
        attackerWins = attackerRoundWins,
        defenderWins = defenderRoundWins,
    }
end

-- ============================================================
-- Private helpers
-- ============================================================

-- Sends the current match state to every client and fires PhaseChanged once per transition.
local function broadcast(phase: string, round: number, timeLeft: number)
    currentPhase    = phase
    currentRound    = round
    currentTimeLeft = timeLeft

    RoundStateChanged:FireAllClients({
        phase        = phase,
        round        = round,
        maxRounds    = Constants.MAX_ROUNDS,
        timeLeft     = timeLeft,
        winner       = currentWinner,
        attackerWins = attackerRoundWins,
        defenderWins = defenderRoundWins,
    })

    if phase ~= lastFiredPhase then
        lastFiredPhase = phase
        MatchEvents.PhaseChanged:Fire(phase, round)
    end
end

-- Counts down `duration` seconds, broadcasting every COUNTDOWN_TICK.
-- Pass listenForEarlyEnd = true during ACTIVE to capture RoundEndedEarly signals.
-- Returns (completedNormally: boolean, earlyWinner: string).
-- earlyWinner is "" when completedNormally is true.
local function countdown(
    phase: string,
    round: number,
    duration: number,
    listenForEarlyEnd: boolean?
): (boolean, string)
    local endTime     = os.clock() + duration
    local endedEarly  = false
    local earlyWinner = ""

    local earlyConn: RBXScriptConnection?
    if listenForEarlyEnd then
        earlyConn = MatchEvents.RoundEndedEarly.Event:Connect(function(winner: string)
            earlyWinner = winner
            endedEarly  = true
        end)
    end

    while os.clock() < endTime and not endedEarly do
        local timeLeft = math.ceil(endTime - os.clock())
        broadcast(phase, round, timeLeft)
        task.wait(Constants.COUNTDOWN_TICK)
    end

    if earlyConn then
        earlyConn:Disconnect()
    end
    return not endedEarly, earlyWinner
end

-- Blocks until the server has at least MIN_PLAYERS connected.
local function waitForPlayers()
    while #Players:GetPlayers() < Constants.MIN_PLAYERS do
        broadcast(Constants.Phase.LOBBY, 0, 0)
        task.wait(Constants.LOBBY_POLL_INTERVAL)
    end
end

-- ============================================================
-- Phase runners
-- ============================================================

local function runLobby()
    Logger.debug("[MatchService] LOBBY — waiting for", Constants.MIN_PLAYERS, "players")
    waitForPlayers()
    Logger.debug("[MatchService] LOBBY — players ready, starting countdown")
    countdown(Constants.Phase.LOBBY, 0, Constants.LOBBY_TIME)
end

local function runPrep(round: number)
    Logger.debug("[MatchService] PREP — round", round, "of", Constants.MAX_ROUNDS)
    -- Broadcast once immediately so clients flip to PREP without a one-second delay.
    broadcast(Constants.Phase.PREP, round, Constants.PREP_TIME)
    countdown(Constants.Phase.PREP, round, Constants.PREP_TIME)
end

-- Returns the round winner: "Time Expired" on normal end, team name on early end.
-- "Time Expired" is treated as a Defenders round win everywhere that reads it.
local function runActive(round: number): string
    Logger.debug("[MatchService] ACTIVE — round", round)
    broadcast(Constants.Phase.ACTIVE, round, Constants.ACTIVE_TIME)
    local completedNormally, earlyWinner =
        countdown(Constants.Phase.ACTIVE, round, Constants.ACTIVE_TIME, true)

    if completedNormally then
        Logger.debug("[MatchService] ACTIVE — time expired, Defenders win")
        return "Time Expired"
    else
        Logger.debug("[MatchService] ACTIVE — ended early, winner:", earlyWinner)
        return earlyWinner
    end
end

-- Sets currentWinner so it is included in every broadcast during RESULTS.
local function runResults(round: number, winner: string)
    Logger.debug("[MatchService] RESULTS — round", round, "| winner:", winner)
    currentWinner = winner
    broadcast(Constants.Phase.RESULTS, round, Constants.RESULTS_DURATION)
    countdown(Constants.Phase.RESULTS, round, Constants.RESULTS_DURATION)
end

-- ============================================================
-- Main match loop
-- ============================================================

local function runMatch()
    Logger.debug("[MatchService] ========== NEW MATCH ==========")
    attackerRoundWins = 0
    defenderRoundWins = 0
    currentWinner     = ""

    runLobby()

    for round = 1, Constants.MAX_ROUNDS do
        runPrep(round)
        local winner = runActive(round)

        -- "Time Expired" is a Defenders win; all other winner strings are team names.
        if winner == "Attackers" then
            attackerRoundWins += 1
        else
            defenderRoundWins += 1
        end

        runResults(round, winner)
    end

    -- Determine the overall match winner and broadcast MATCHEND.
    local matchWinner: string
    if attackerRoundWins > defenderRoundWins then
        matchWinner = "Attackers"
    elseif defenderRoundWins > attackerRoundWins then
        matchWinner = "Defenders"
    else
        matchWinner = "Draw"
    end

    Logger.debug(string.format(
        "[MatchService] Match complete — ATK %d DEF %d — overall winner: %s",
        attackerRoundWins, defenderRoundWins, matchWinner
    ))

    currentWinner = matchWinner
    broadcast(Constants.Phase.MATCHEND, Constants.MAX_ROUNDS, Constants.MATCHEND_DURATION)
    task.wait(Constants.MATCHEND_DURATION)
end

-- ============================================================
-- Entry point — run matches back-to-back indefinitely.
-- ============================================================

while true do
    runMatch()
    task.wait(Constants.MATCH_END_PAUSE)
end
