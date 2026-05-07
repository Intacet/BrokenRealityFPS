--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > MatchService
--
-- Owns the full match lifecycle: Lobby → (Prep → Active → Results) × MAX_ROUNDS.
-- Fires RoundStateChanged every second so clients can update timers and phase labels.
--
-- What this script does NOT do (handled by future services):
--   - Spawn or assign players to teams  →  TeamService
--   - Track objective capture progress  →  ObjectiveService
--   - Apply damage or health changes    →  DamageService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ============================================================
-- Dependencies
-- ============================================================

-- WaitForChild is used here because Roblox does not guarantee that
-- ReplicatedStorage children exist the instant this script runs.
local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local GetMatchConfig    = Remotes:WaitForChild("GetMatchConfig")    :: RemoteFunction

-- Bridges phase changes to other server services (TeamService, ObjectiveService).
-- MatchEvents is a sibling ModuleScript in ServerScriptService/Services.
local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

-- ============================================================
-- State
-- These variables track what phase and round the server is currently in.
-- Read by GetMatchConfig so late-joining clients can sync immediately.
-- ============================================================

local currentPhase    = Constants.Phase.LOBBY
local currentRound    = 0
local currentTimeLeft = 0

-- Tracks the last phase fired to MatchEvents so PhaseChanged only fires once per
-- transition, not once per second. Initialised to "" so the first broadcast always fires.
local lastFiredPhase  = ""

-- ============================================================
-- Early-end hook (for ObjectiveService, built next)
--
-- When an objective is completed, ObjectiveService will fire this
-- BindableEvent to cut the Active phase short without needing to
-- wait for the full ACTIVE_TIME to expire.
-- ============================================================

local RoundEndedEarly = Instance.new("BindableEvent")

-- Public accessor so ObjectiveService can reach this event.
-- Usage from ObjectiveService: MatchService.RoundEndedEarly:Fire()
-- (ObjectiveService will require this script once it is built.)
-- For now this is wired up but never fired.
local MatchService = {}
MatchService.RoundEndedEarly = RoundEndedEarly

-- ============================================================
-- GetMatchConfig handler
--
-- A client calls this when they first join to get the current state.
-- Without this, a player who joins mid-round would see stale UI.
-- ============================================================

GetMatchConfig.OnServerInvoke = function(_player)
    -- Return the current snapshot so the client can sync its UI immediately.
    return {
        phase     = currentPhase,
        round     = currentRound,
        maxRounds = Constants.MAX_ROUNDS,
        timeLeft  = currentTimeLeft,
    }
end

-- ============================================================
-- Private helpers
-- ============================================================

-- Sends the current match state to every connected client.
-- Called once per COUNTDOWN_TICK during any timed phase.
local function broadcast(phase: string, round: number, timeLeft: number)
    -- Keep module-level state in sync so GetMatchConfig always returns fresh data.
    currentPhase    = phase
    currentRound    = round
    currentTimeLeft = timeLeft

    RoundStateChanged:FireAllClients({
        phase     = phase,
        round     = round,
        maxRounds = Constants.MAX_ROUNDS,
        timeLeft  = timeLeft,
    })

    -- Only fire PhaseChanged when the phase actually transitions.
    -- broadcast() runs every second, but listeners only need to react once per phase.
    if phase ~= lastFiredPhase then
        lastFiredPhase = phase
        MatchEvents.PhaseChanged:Fire(phase, round)
    end
end

-- Counts down `duration` seconds, broadcasting the state every COUNTDOWN_TICK.
-- Returns true if the full duration elapsed normally.
-- Returns false if RoundEndedEarly fired (objective completed early).
local function countdown(phase: string, round: number, duration: number): boolean
    local endTime    = os.clock() + duration
    local endedEarly = false

    -- Listen for ObjectiveService signalling an early round end.
    local earlyConnection = RoundEndedEarly.Event:Connect(function()
        endedEarly = true
    end)

    while os.clock() < endTime and not endedEarly do
        local timeLeft = math.ceil(endTime - os.clock())
        broadcast(phase, round, timeLeft)
        task.wait(Constants.COUNTDOWN_TICK)
    end

    earlyConnection:Disconnect() -- always clean up connections to avoid memory leaks
    return not endedEarly
end

-- Blocks until the server has at least MIN_PLAYERS connected.
-- Broadcasts a LOBBY state with timeLeft = 0 while waiting.
local function waitForPlayers()
    while #Players:GetPlayers() < Constants.MIN_PLAYERS do
        broadcast(Constants.Phase.LOBBY, 0, 0)
        task.wait(Constants.LOBBY_POLL_INTERVAL)
    end
end

-- ============================================================
-- Phase runners
-- Each function runs one phase of the match and then returns.
-- ============================================================

local function runLobby()
    Logger.debug("[MatchService] LOBBY — waiting for", Constants.MIN_PLAYERS, "players")

    -- Keep broadcasting LOBBY until enough players are present.
    waitForPlayers()

    Logger.debug("[MatchService] LOBBY — players ready, starting countdown")
    -- Count down the lobby timer. Players should see this on their MatchUI.
    countdown(Constants.Phase.LOBBY, 0, Constants.LOBBY_TIME)
end

local function runPrep(round: number)
    Logger.debug("[MatchService] PREP — round", round, "of", Constants.MAX_ROUNDS)

    -- Broadcast once immediately so clients flip their UI to PREP without waiting 1 second.
    broadcast(Constants.Phase.PREP, round, Constants.PREP_TIME)
    countdown(Constants.Phase.PREP, round, Constants.PREP_TIME)
end

local function runActive(round: number)
    Logger.debug("[MatchService] ACTIVE — round", round)

    broadcast(Constants.Phase.ACTIVE, round, Constants.ACTIVE_TIME)
    local completedNormally = countdown(Constants.Phase.ACTIVE, round, Constants.ACTIVE_TIME)

    if not completedNormally then
        -- An objective was completed. ObjectiveService already fired ObjectiveComplete
        -- to clients, so we just move on to the results phase immediately.
        Logger.debug("[MatchService] ACTIVE ended early — objective completed")
    end
end

local function runResults(round: number)
    Logger.debug("[MatchService] RESULTS — round", round)

    broadcast(Constants.Phase.RESULTS, round, Constants.RESULTS_TIME)
    countdown(Constants.Phase.RESULTS, round, Constants.RESULTS_TIME)
end

-- ============================================================
-- Main match loop
-- ============================================================

local function runMatch()
    Logger.debug("[MatchService] ========== NEW MATCH ==========")

    runLobby()

    for round = 1, Constants.MAX_ROUNDS do
        runPrep(round)
        runActive(round)
        runResults(round)
    end

    -- Match is over. Broadcast a final state with timeLeft = 0 so clients know
    -- the full match has ended (not just a single round).
    Logger.debug("[MatchService] Match complete — all", Constants.MAX_ROUNDS, "rounds finished")
    broadcast(Constants.Phase.RESULTS, Constants.MAX_ROUNDS, 0)
    task.wait(Constants.RESULTS_TIME)
end

-- ============================================================
-- Entry point
--
-- Run matches back-to-back indefinitely so the server never idles.
-- A MATCH_END_PAUSE gap between matches gives players time to read final scores.
-- ============================================================

while true do
    runMatch()
    task.wait(Constants.MATCH_END_PAUSE)
end
