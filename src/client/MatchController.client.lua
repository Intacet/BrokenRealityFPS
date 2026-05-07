--!strict
-- LocalScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > MatchController
--
-- Owns the client-side view of match state: current phase, round number, and time left.
-- Syncs immediately on join via GetMatchConfig, then stays up to date via RoundStateChanged.
--
-- Does NOT build any UI — MatchUI will read from this controller once it is built.
-- Does NOT touch server state — all authoritative data lives in MatchService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Types      = require(Modules:WaitForChild("Types"))
local Logger     = require(Modules:WaitForChild("Logger"))

-- Silence the unused-variable warning: Types is imported for its exported types only.
-- The require is still necessary so the type system resolves Types.Phase and
-- Types.RoundStatePayload in this file.
local _ = Types

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local GetMatchConfig    = Remotes:WaitForChild("GetMatchConfig")    :: RemoteFunction

-- ============================================================
-- Local state
-- These are the client's current copy of the match state.
-- Read by other controllers (e.g. MatchUI) via the public getters below.
-- Never written to from outside this module — only MatchService owns the truth.
-- ============================================================

local currentPhase: Types.Phase = Constants.Phase.LOBBY
local currentRound: number      = 0
local currentTimeLeft: number   = 0
local currentMaxRounds: number  = Constants.MAX_ROUNDS

-- ============================================================
-- Private helpers
-- ============================================================

-- Writes a received payload into local state and logs it for verification.
-- This is the single place where local state is mutated.
-- MatchUI will hook into this function (or replace the debug call) when it is built.
local function applyState(payload: Types.RoundStatePayload)
    currentPhase     = payload.phase
    currentRound     = payload.round
    currentTimeLeft  = payload.timeLeft
    currentMaxRounds = payload.maxRounds

    -- Temporary debug output so we can confirm the controller is receiving correctly.
    -- Replace this with a UI update when MatchUI is built.
    Logger.debug(string.format(
        "[MatchController] %s | Round %d / %d | %ds left",
        currentPhase,
        currentRound,
        currentMaxRounds,
        currentTimeLeft
    ))
end

-- ============================================================
-- Controller
-- ============================================================

local MatchController = {}

-- Called once when the LocalScript runs.
-- Syncs immediately, then listens for updates.
function MatchController:Start()
    -- Ask the server for the current state right now.
    -- This handles the case where a player joins mid-round and would otherwise
    -- see stale default values until the next RoundStateChanged fires.
    --
    -- pcall guards against the brief startup window where MatchService may not
    -- have registered its OnServerInvoke handler yet. If the call fails, the
    -- controller falls back to waiting for the first RoundStateChanged event.
    local ok, result = pcall(function()
        return GetMatchConfig:InvokeServer()
    end)

    if ok and result ~= nil then
        applyState(result :: Types.RoundStatePayload)
    elseif not ok then
        -- result contains the error string when pcall catches a thrown error.
        -- Logger.warn makes it red in the Output window and easier to spot.
        Logger.warn("[MatchController] GetMatchConfig error:", result)
    else
        -- ok is true but the server returned nil — genuine timing edge case where
        -- MatchService hasn't set up its handler yet. Wait for RoundStateChanged.
        Logger.debug("[MatchController] GetMatchConfig not ready yet — waiting for first RoundStateChanged")
    end

    -- Listen for every subsequent state update from MatchService.
    -- OnClientEvent delivers its arguments as `any`, so we receive the raw value
    -- and cast it to RoundStatePayload before passing it to applyState.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        applyState(raw :: Types.RoundStatePayload)
    end)
end

-- ============================================================
-- Public getters
-- Read-only access for other client systems (MatchUI, CutsceneController, etc.).
-- These will be called once MatchUI is built — do not remove them.
-- ============================================================

function MatchController:GetPhase(): Types.Phase
    return currentPhase
end

function MatchController:GetRound(): number
    return currentRound
end

function MatchController:GetTimeLeft(): number
    return currentTimeLeft
end

function MatchController:GetMaxRounds(): number
    return currentMaxRounds
end

-- ============================================================
-- Entry point
-- LocalScripts run automatically; call Start() here so the controller
-- is active as soon as the player's client loads.
-- ============================================================

MatchController:Start()

return MatchController
