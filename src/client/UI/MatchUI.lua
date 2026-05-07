--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > MatchUI
--
-- Builds and drives the match state overlay: round/phase label, countdown timer,
-- per-round result overlay, and overall match-end overlay.
-- Receives state from RoundStateChanged (server → all clients).
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects the RoundStateChanged listener

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Types     = require(Modules:WaitForChild("Types"))
local Logger    = require(Modules:WaitForChild("Logger"))

-- Silence unused-variable warning: Types is imported for its exported types only.
local _ = Types

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

local FONT_BOLD   = Enum.Font.GothamBold
local FONT_NORMAL = Enum.Font.Gotham
local WHITE       = Color3.new(1, 1, 1)
local BLACK       = Color3.new(0, 0, 0)

-- ============================================================
-- GUI references (set inside init())
-- ============================================================

local roundLabel  : TextLabel
local timerLabel  : TextLabel
local topBar      : Frame

local resultsOverlay  : Frame
local resultsTitle    : TextLabel
local resultsWinner   : TextLabel
local resultsScore    : TextLabel

local matchEndOverlay : Frame
local matchEndTitle   : TextLabel
local matchEndWinner  : TextLabel
local matchEndScore   : TextLabel

-- ============================================================
-- Private helpers
-- ============================================================

local function formatTime(seconds: number): string
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function makeLabel(
    parent: Instance,
    name: string,
    size: UDim2,
    pos: UDim2,
    textSize: number,
    font: Enum.Font,
    zIndex: number
): TextLabel
    local label = Instance.new("TextLabel")
    label.Name                 = name
    label.Size                 = size
    label.Position             = pos
    label.BackgroundTransparency = 1
    label.TextColor3           = WHITE
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3     = BLACK
    label.Font                 = font
    label.TextSize             = textSize
    label.ZIndex               = zIndex
    label.Parent               = parent
    return label
end

local function makeOverlay(
    parent: Instance,
    name: string,
    baseZIndex: number
): (Frame, TextLabel, TextLabel, TextLabel)
    local overlay = Instance.new("Frame")
    overlay.Name                  = name
    overlay.Size                  = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3      = BLACK
    overlay.BackgroundTransparency = 0.35
    overlay.Visible               = false
    overlay.ZIndex                = baseZIndex
    overlay.Parent                = parent

    local title = makeLabel(
        overlay, "Title",
        UDim2.new(0, 500, 0, 60),
        UDim2.new(0.5, -250, 0.38, 0),
        40, FONT_BOLD, baseZIndex + 1
    )
    local winnerLbl = makeLabel(
        overlay, "Winner",
        UDim2.new(0, 500, 0, 40),
        UDim2.new(0.5, -250, 0.48, 0),
        26, FONT_BOLD, baseZIndex + 1
    )
    local scoreLbl = makeLabel(
        overlay, "Score",
        UDim2.new(0, 500, 0, 30),
        UDim2.new(0.5, -250, 0.56, 0),
        20, FONT_NORMAL, baseZIndex + 1
    )
    return overlay, title, winnerLbl, scoreLbl
end

-- Updates all visible UI elements from the latest RoundStatePayload.
local function updateDisplay(payload: Types.RoundStatePayload)
    local phase = payload.phase

    -- Top bar: hide during LOBBY; show during all other phases.
    topBar.Visible = (phase ~= Constants.Phase.LOBBY)

    if phase == Constants.Phase.LOBBY then
        roundLabel.Text = "WAITING FOR PLAYERS"
        timerLabel.Text = ""
    elseif phase == Constants.Phase.PREP then
        roundLabel.Text = string.format("ROUND %d / %d — PREP", payload.round, payload.maxRounds)
        timerLabel.Text = formatTime(payload.timeLeft)
    elseif phase == Constants.Phase.ACTIVE then
        roundLabel.Text = string.format("ROUND %d / %d", payload.round, payload.maxRounds)
        timerLabel.Text = formatTime(payload.timeLeft)
    elseif phase == Constants.Phase.RESULTS then
        roundLabel.Text = string.format("ROUND %d / %d", payload.round, payload.maxRounds)
        timerLabel.Text = ""
    elseif phase == Constants.Phase.MATCHEND then
        roundLabel.Text = "MATCH OVER"
        timerLabel.Text = ""
    end

    -- Results overlay: visible only during RESULTS.
    local showResults = (phase == Constants.Phase.RESULTS)
    resultsOverlay.Visible = showResults
    if showResults then
        local winner = payload.winner
        if winner == "Time Expired" then
            resultsWinner.Text = "Defenders win (time expired)"
        elseif winner ~= "" then
            resultsWinner.Text = winner .. " win"
        else
            resultsWinner.Text = ""
        end
        resultsScore.Text = string.format(
            "Attackers %d — Defenders %d",
            payload.attackerWins,
            payload.defenderWins
        )
    end

    -- Match end overlay: visible only during MATCHEND.
    local showMatchEnd = (phase == Constants.Phase.MATCHEND)
    matchEndOverlay.Visible = showMatchEnd
    if showMatchEnd then
        local winner = payload.winner
        if winner == "Draw" then
            matchEndWinner.Text = "Draw"
        elseif winner ~= "" then
            matchEndWinner.Text = winner .. " win the match"
        else
            matchEndWinner.Text = ""
        end
        matchEndScore.Text = string.format(
            "Attackers %d — Defenders %d",
            payload.attackerWins,
            payload.defenderWins
        )
    end
end

-- ============================================================
-- Controller
-- ============================================================

local MatchUI = {}

-- Creates all ScreenGui elements. Must be called before Start().
function MatchUI:init(playerGui: PlayerGui)
    local screen = Instance.new("ScreenGui")
    screen.Name           = "MatchUI"
    screen.ResetOnSpawn   = false
    screen.IgnoreGuiInset = true
    screen.Parent         = playerGui

    -- Top bar — fixed height strip at the very top of the screen.
    topBar = Instance.new("Frame")
    topBar.Name                  = "TopBar"
    topBar.Size                  = UDim2.new(1, 0, 0, 52)
    topBar.Position              = UDim2.fromScale(0, 0)
    topBar.BackgroundColor3      = BLACK
    topBar.BackgroundTransparency = 0.45
    topBar.Visible               = false
    topBar.Parent                = screen

    roundLabel = makeLabel(
        topBar, "RoundLabel",
        UDim2.new(1, -120, 0, 26),
        UDim2.new(0, 0, 0, 4),
        18, FONT_BOLD, 2
    )
    roundLabel.TextXAlignment = Enum.TextXAlignment.Center

    timerLabel = makeLabel(
        topBar, "TimerLabel",
        UDim2.new(0, 110, 0, 26),
        UDim2.new(1, -114, 0, 4),
        22, FONT_BOLD, 2
    )
    timerLabel.TextXAlignment = Enum.TextXAlignment.Right

    -- Results overlay — covers the screen during RESULTS with winner info.
    resultsOverlay, resultsTitle, resultsWinner, resultsScore =
        makeOverlay(screen, "ResultsOverlay", 10)
    resultsTitle.Text = "ROUND OVER"

    -- Match end overlay — covers the screen during MATCHEND with final scores.
    matchEndOverlay, matchEndTitle, matchEndWinner, matchEndScore =
        makeOverlay(screen, "MatchEndOverlay", 20)
    matchEndTitle.Text = "MATCH OVER"

    Logger.debug("[MatchUI] GUI created")
end

-- Connects to RoundStateChanged and immediately applies the current state.
-- Must be called after init().
function MatchUI:Start()
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        updateDisplay(raw :: Types.RoundStatePayload)
    end)
    Logger.debug("[MatchUI] Started")
end

return MatchUI
