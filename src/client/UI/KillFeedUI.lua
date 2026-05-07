--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > KillFeedUI
--
-- Displays a scrolling kill feed in the top-right corner of the screen.
-- Driven by KillFeed RemoteEvent (server → all clients).
-- Each entry shows "[Killer] → [Victim]" with team-coloured names.
-- Entries stack downward from the top-right, fade after KILLFEED_DISPLAY_TIME seconds,
-- and the oldest entry is removed immediately when a sixth arrives.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects KillFeed remote event

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local KillFeed = Remotes:WaitForChild("KillFeed") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

local MAX_ENTRIES     = 5
local CONTAINER_WIDTH = 260
local ENTRY_HEIGHT    = 22
local ENTRY_PADDING   = 2

-- ============================================================
-- GUI references (set inside init())
-- ============================================================

local feedScreen    : ScreenGui
local feedContainer : Frame

-- ============================================================
-- State
-- ============================================================

local entries      : { Frame } = {}
local entryCounter : number    = 0

-- ============================================================
-- Private helpers
-- ============================================================

-- Returns the Color3 for a given team name using centralized Constants.
local function teamColor(teamName: string): Color3
    if teamName == Constants.TEAM_ATTACKERS then
        return Constants.COLOR_TEAM_ATTACKERS
    elseif teamName == Constants.TEAM_DEFENDERS then
        return Constants.COLOR_TEAM_DEFENDERS
    else
        return Constants.COLOR_TEAM_NEUTRAL
    end
end

-- Converts a Color3 to the "rgb(r,g,b)" format required by Roblox RichText.
local function colorTag(c: Color3): string
    return string.format(
        "rgb(%d,%d,%d)",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5)
    )
end

-- Removes a frame from the entries table and destroys it.
-- Safe to call even if the frame was already destroyed (Destroy is idempotent).
local function removeEntry(frame: Frame)
    for i, e in ipairs(entries) do
        if e == frame then
            table.remove(entries, i)
            break
        end
    end
    frame:Destroy()
end

-- Creates one kill-feed entry, appends it to the container, and schedules its removal.
local function addEntry(
    killerName: string,
    victimName: string,
    killerTeam: string,
    victimTeam: string
)
    -- Enforce the cap: remove the oldest entry before adding a new one.
    if #entries >= MAX_ENTRIES then
        removeEntry(entries[1])
    end

    entryCounter += 1

    local frame = Instance.new("Frame")
    frame.Name                   = "KillEntry"
    frame.Size                   = UDim2.new(1, 0, 0, ENTRY_HEIGHT)
    frame.BackgroundColor3       = Color3.new(0, 0, 0)
    frame.BackgroundTransparency = 0.4
    frame.BorderSizePixel        = 0
    frame.LayoutOrder            = entryCounter
    frame.Parent                 = feedContainer

    local label = Instance.new("TextLabel")
    label.Name                   = "KillText"
    label.Size                   = UDim2.new(1, -8, 1, 0)
    label.Position               = UDim2.fromOffset(4, 0)
    label.BackgroundTransparency = 1
    label.TextColor3             = Color3.new(1, 1, 1)
    label.Font                   = Enum.Font.GothamBold
    label.TextSize               = 13
    label.TextXAlignment         = Enum.TextXAlignment.Left
    label.TextYAlignment         = Enum.TextYAlignment.Center
    label.RichText               = true
    label.Parent                 = frame

    local killerTag = colorTag(teamColor(killerTeam))
    local victimTag = colorTag(teamColor(victimTeam))

    if killerName == "" then
        -- Environment kill: show a neutral symbol in place of a killer name.
        label.Text = string.format(
            '<font color="%s">✦</font> → <font color="%s">%s</font>',
            colorTag(Constants.COLOR_TEAM_NEUTRAL),
            victimTag,
            victimName
        )
    else
        label.Text = string.format(
            '<font color="%s">%s</font> → <font color="%s">%s</font>',
            killerTag,
            killerName,
            victimTag,
            victimName
        )
    end

    entries[#entries + 1] = frame

    -- Schedule fade-out. If the frame was already removed by the max-cap path,
    -- frame.Parent will be nil and we exit early to avoid tweening a destroyed instance.
    task.delay(Constants.KILLFEED_DISPLAY_TIME, function()
        if not frame.Parent then
            return
        end

        local fadeInfo   = TweenInfo.new(Constants.KILLFEED_FADE_TIME, Enum.EasingStyle.Linear)
        local frameTween = TweenService:Create(frame, fadeInfo, { BackgroundTransparency = 1 })
        local labelTween = TweenService:Create(label, fadeInfo, { TextTransparency = 1 })

        frameTween:Play()
        labelTween:Play()

        -- Remove from entries table and destroy after the fade completes.
        frameTween.Completed:Connect(function()
            removeEntry(frame)
        end)
    end)
end

-- ============================================================
-- Controller
-- ============================================================

local KillFeedUI = {}

-- Creates all ScreenGui elements. Must be called before Start().
function KillFeedUI:init(playerGui: PlayerGui)
    feedScreen = Instance.new("ScreenGui")
    feedScreen.Name           = "KillFeedUI"
    feedScreen.ResetOnSpawn   = false
    feedScreen.IgnoreGuiInset = true
    feedScreen.DisplayOrder   = 5
    feedScreen.Parent         = playerGui

    -- Transparent container anchored to the top-right corner.
    -- AutomaticSize = Y lets it grow as entries are added without a fixed height.
    feedContainer = Instance.new("Frame")
    feedContainer.Name                   = "KillFeedContainer"
    feedContainer.AnchorPoint            = Vector2.new(1, 0)
    feedContainer.Position               = UDim2.new(1, -8, 0, 8)
    feedContainer.Size                   = UDim2.new(0, CONTAINER_WIDTH, 0, 0)
    feedContainer.AutomaticSize          = Enum.AutomaticSize.Y
    feedContainer.BackgroundTransparency = 1
    feedContainer.BorderSizePixel        = 0
    feedContainer.Parent                 = feedScreen

    local layout = Instance.new("UIListLayout")
    layout.SortOrder         = Enum.SortOrder.LayoutOrder
    layout.FillDirection     = Enum.FillDirection.Vertical
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Padding           = UDim.new(0, ENTRY_PADDING)
    layout.Parent            = feedContainer

    Logger.debug("[KillFeedUI] GUI created")
end

-- Connects KillFeed remote event. Must be called after init().
function KillFeedUI:Start()
    KillFeed.OnClientEvent:Connect(function(
        killerName: string,
        victimName: string,
        killerTeam: string,
        victimTeam: string
    )
        addEntry(killerName, victimName, killerTeam, victimTeam)
        Logger.debug(string.format(
            "[KillFeedUI] %s → %s (%s vs %s)",
            killerName == "" and "✦" or killerName,
            victimName,
            killerTeam,
            victimTeam
        ))
    end)

    Logger.debug("[KillFeedUI] Started")
end

return KillFeedUI
