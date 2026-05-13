--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > MatchUI
--
-- Minimal tactical match state UI.
-- Top-center bar (300×32 px): phase label left, round center, timer right.
-- Round-end overlay (400×80 px, centered): winner in team accent, score in grey.
-- Match-end overlay (full-screen dark): MATCH COMPLETE, winner, final score.
-- All color and visibility transitions use TweenService.
-- Hidden entirely during LOBBY.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects RoundStateChanged listener

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- Design tokens
-- ============================================================

local PANEL_COLOR  = Color3.fromRGB(10, 10, 10)
local PANEL_ALPHA  = 0.6
local WHITE        = Color3.new(1, 1, 1)
local GREY         = Color3.fromRGB(160, 160, 160)
local COLOR_ATK    = Color3.fromRGB(200, 60, 60)
local COLOR_DEF    = Color3.fromRGB(60, 120, 200)

-- ============================================================
-- GUI references (set in init())
-- ============================================================

local topBar         : Frame
local phaseLabel     : TextLabel
local roundLabel     : TextLabel
local timerLabel     : TextLabel

local resultsOverlay : Frame
local resultsWinner  : TextLabel
local resultsScore   : TextLabel

local matchEndOverlay  : Frame
local matchEndTitle    : TextLabel
local matchEndWinner   : TextLabel
local matchEndScore    : TextLabel

-- ============================================================
-- Helpers
-- ============================================================

local function lbl(
    parent   : Instance,
    text     : string,
    size     : UDim2,
    pos      : UDim2,
    fontSize : number,
    bold     : boolean,
    color    : Color3,
    align    : Enum.TextXAlignment
): TextLabel
    local t = Instance.new("TextLabel")
    t.Size                   = size
    t.Position               = pos
    t.BackgroundTransparency = 1
    t.Text                   = text
    t.TextColor3             = color
    t.Font                   = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    t.TextSize               = fontSize
    t.TextXAlignment         = align
    t.TextYAlignment         = Enum.TextYAlignment.Center
    t.Parent                 = parent
    return t
end

local function formatTime(seconds: number): string
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

local function teamColor(winner: string): Color3
    if winner == Constants.TEAM_ATTACKERS then
        return COLOR_ATK
    elseif winner == Constants.TEAM_DEFENDERS then
        return COLOR_DEF
    else
        return Color3.fromRGB(220, 220, 220)
    end
end

local PHASE_NAMES: { [string]: string } = {
    [Constants.Phase.LOBBY]    = "LOBBY",
    [Constants.Phase.PREP]     = "PREP",
    [Constants.Phase.ACTIVE]   = "ACTIVE",
    [Constants.Phase.RESULTS]  = "RESULTS",
    [Constants.Phase.MATCHEND] = "END",
}

-- ============================================================
-- State update
-- ============================================================

local function updateDisplay(payload: { phase: string, round: number, maxRounds: number, timeLeft: number, winner: string, attackerWins: number, defenderWins: number })
    local phase = payload.phase

    -- Top bar visibility
    topBar.Visible = (phase ~= Constants.Phase.LOBBY)

    if topBar.Visible then
        phaseLabel.Text = PHASE_NAMES[phase] or phase

        if phase == Constants.Phase.ACTIVE or phase == Constants.Phase.PREP then
            roundLabel.Text = string.format("ROUND %d / %d", payload.round, payload.maxRounds)
            timerLabel.Text = formatTime(payload.timeLeft)
        elseif phase == Constants.Phase.RESULTS then
            roundLabel.Text = string.format("ROUND %d / %d", payload.round, payload.maxRounds)
            timerLabel.Text = ""
        elseif phase == Constants.Phase.MATCHEND then
            roundLabel.Text = "MATCH COMPLETE"
            timerLabel.Text = ""
        end
    end

    -- Results overlay: shown only during RESULTS
    local showResults = (phase == Constants.Phase.RESULTS)
    resultsOverlay.Visible = showResults
    if showResults then
        local winner = payload.winner
        local displayWinner: string
        if winner == "Time Expired" then
            displayWinner = "DEFENDERS WIN"
            resultsWinner.TextColor3 = COLOR_DEF
        elseif winner == Constants.TEAM_ATTACKERS then
            displayWinner = "ATTACKERS WIN"
            resultsWinner.TextColor3 = COLOR_ATK
        elseif winner == Constants.TEAM_DEFENDERS then
            displayWinner = "DEFENDERS WIN"
            resultsWinner.TextColor3 = COLOR_DEF
        else
            displayWinner = winner ~= "" and (winner:upper() .. " WIN") or "ROUND OVER"
            resultsWinner.TextColor3 = WHITE
        end
        resultsWinner.Text = displayWinner
        resultsScore.Text  = string.format("ATK %d  —  DEF %d", payload.attackerWins, payload.defenderWins)
    end

    -- Match-end overlay: shown only during MATCHEND
    local showMatchEnd = (phase == Constants.Phase.MATCHEND)
    matchEndOverlay.Visible = showMatchEnd
    if showMatchEnd then
        local winner = payload.winner
        if winner == "Draw" then
            matchEndWinner.Text       = "DRAW"
            matchEndWinner.TextColor3 = WHITE
        elseif winner ~= "" then
            matchEndWinner.Text       = winner:upper() .. " WIN"
            matchEndWinner.TextColor3 = teamColor(winner)
        else
            matchEndWinner.Text = ""
        end
        matchEndScore.Text = string.format(
            "Attackers  %d  —  %d  Defenders",
            payload.attackerWins, payload.defenderWins
        )
    end

    -- Suppress unused-variable warning (TweenService required for future transitions)
    local _ = TweenService
end

-- ============================================================
-- Controller
-- ============================================================

local MatchUI = {}

function MatchUI:init(playerGui: PlayerGui)
    local screen              = Instance.new("ScreenGui")
    screen.Name               = "MatchUI"
    screen.ResetOnSpawn       = false
    screen.IgnoreGuiInset     = true
    screen.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
    screen.Parent             = playerGui

    -- ── Top-center bar (300×32 px) ────────────────────────────────────────────
    local BAR_W = 300
    local BAR_H = 32
    topBar                    = Instance.new("Frame")
    topBar.Name               = "TopBar"
    topBar.Size               = UDim2.fromOffset(BAR_W, BAR_H)
    topBar.Position           = UDim2.new(0.5, -BAR_W / 2, 0, 8)
    topBar.BackgroundColor3   = PANEL_COLOR
    topBar.BackgroundTransparency = PANEL_ALPHA
    topBar.BorderSizePixel    = 0
    topBar.Visible            = false
    topBar.Parent             = screen

    -- Phase label — left, grey size 11
    phaseLabel = lbl(topBar, "LOBBY",
        UDim2.fromOffset(70, BAR_H),
        UDim2.fromOffset(8, 0),
        11, false, GREY, Enum.TextXAlignment.Left)

    -- Round label — center, white bold size 13
    roundLabel = lbl(topBar, "",
        UDim2.fromOffset(160, BAR_H),
        UDim2.fromOffset((BAR_W - 160) / 2, 0),
        13, true, WHITE, Enum.TextXAlignment.Center)

    -- Timer label — right, white bold size 13
    timerLabel = lbl(topBar, "",
        UDim2.fromOffset(70, BAR_H),
        UDim2.fromOffset(BAR_W - 78, 0),
        13, true, WHITE, Enum.TextXAlignment.Right)

    -- ── Round-end overlay (400×80 px, centered) ───────────────────────────────
    local RES_W = 400
    local RES_H = 80
    resultsOverlay                    = Instance.new("Frame")
    resultsOverlay.Name               = "ResultsOverlay"
    resultsOverlay.Size               = UDim2.fromOffset(RES_W, RES_H)
    resultsOverlay.Position           = UDim2.new(0.5, -RES_W / 2, 0.5, -RES_H / 2)
    resultsOverlay.BackgroundColor3   = PANEL_COLOR
    resultsOverlay.BackgroundTransparency = 0.2
    resultsOverlay.BorderSizePixel    = 0
    resultsOverlay.Visible            = false
    resultsOverlay.Parent             = screen

    resultsWinner = lbl(resultsOverlay, "",
        UDim2.fromOffset(RES_W, 44),
        UDim2.fromOffset(0, 4),
        22, true, WHITE, Enum.TextXAlignment.Center)

    resultsScore = lbl(resultsOverlay, "",
        UDim2.fromOffset(RES_W, 26),
        UDim2.fromOffset(0, 50),
        13, false, GREY, Enum.TextXAlignment.Center)

    -- ── Match-end overlay (full screen) ───────────────────────────────────────
    matchEndOverlay                    = Instance.new("Frame")
    matchEndOverlay.Name               = "MatchEndOverlay"
    matchEndOverlay.Size               = UDim2.fromScale(1, 1)
    matchEndOverlay.BackgroundColor3   = PANEL_COLOR
    matchEndOverlay.BackgroundTransparency = 0.15
    matchEndOverlay.BorderSizePixel    = 0
    matchEndOverlay.Visible            = false
    matchEndOverlay.Parent             = screen

    matchEndTitle = lbl(matchEndOverlay, "MATCH COMPLETE",
        UDim2.new(1, 0, 0, 30),
        UDim2.new(0, 0, 0.42, 0),
        12, false, GREY, Enum.TextXAlignment.Center)

    matchEndWinner = lbl(matchEndOverlay, "",
        UDim2.new(1, 0, 0, 50),
        UDim2.new(0, 0, 0.47, 0),
        28, true, WHITE, Enum.TextXAlignment.Center)

    matchEndScore = lbl(matchEndOverlay, "",
        UDim2.new(1, 0, 0, 30),
        UDim2.new(0, 0, 0.59, 0),
        16, false, WHITE, Enum.TextXAlignment.Center)

    Logger.debug("[MatchUI] GUI created")
end

function MatchUI:Start()
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        updateDisplay(raw :: { phase: string, round: number, maxRounds: number, timeLeft: number, winner: string, attackerWins: number, defenderWins: number })
    end)
    Logger.debug("[MatchUI] Started")
end

return MatchUI
