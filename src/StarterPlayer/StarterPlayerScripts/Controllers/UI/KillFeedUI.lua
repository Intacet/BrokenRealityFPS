--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > KillFeedUI
--
-- Minimal tactical kill feed, top-right corner.
-- Format: [KillerName]  ›  [VictimName]
-- Killer name in team accent color, › in grey, victim in team accent color.
-- Each entry: dark panel 260×24 px with thin UIStroke border, Font Gotham size 12.
-- Slide-in from right over 0.15s (QuadOut), fade-out over KILLFEED_FADE_TIME (0.3s).
-- Max 5 entries; oldest removed immediately when a sixth arrives.
-- Entries stack top-to-bottom with 4 px gap.
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
local ENTRY_W         = 260
local ENTRY_H         = 24
local ENTRY_GAP       = 4
local CONTAINER_INSET = 8

-- ============================================================
-- GUI references (set in init())
-- ============================================================

local feedContainer : Frame

-- ============================================================
-- State
-- ============================================================

-- Each element is the outer wrapper Frame (managed by UIListLayout).
local entries      : { Frame } = {}
local entryCounter : number    = 0

-- ============================================================
-- Helpers
-- ============================================================

local function teamColor(teamName: string): Color3
    if teamName == Constants.TEAM_ATTACKERS then
        return Constants.COLOR_TEAM_ATTACKERS
    elseif teamName == Constants.TEAM_DEFENDERS then
        return Constants.COLOR_TEAM_DEFENDERS
    else
        return Constants.COLOR_TEAM_NEUTRAL
    end
end

local function colorTag(c: Color3): string
    return string.format("rgb(%d,%d,%d)",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function removeEntry(wrapper: Frame)
    for i, e in ipairs(entries) do
        if e == wrapper then
            table.remove(entries, i)
            break
        end
    end
    if wrapper.Parent then
        wrapper:Destroy()
    end
end

local function addEntry(killerName: string, victimName: string, killerTeam: string, victimTeam: string)
    -- Enforce cap: remove oldest before adding a new one
    if #entries >= MAX_ENTRIES then
        removeEntry(entries[1])
    end

    entryCounter += 1

    -- ── Outer wrapper (positioned by UIListLayout) ─────────────────────────────
    local wrapper                    = Instance.new("Frame")
    wrapper.Name                     = "KillEntry"
    wrapper.Size                     = UDim2.fromOffset(ENTRY_W, ENTRY_H)
    wrapper.BackgroundTransparency   = 1  -- transparent container
    wrapper.BorderSizePixel          = 0
    wrapper.ClipDescendants          = true
    wrapper.LayoutOrder              = entryCounter
    wrapper.Parent                   = feedContainer

    -- ── Inner panel (slides in from right) ────────────────────────────────────
    local panel                      = Instance.new("Frame")
    panel.Name                       = "Panel"
    panel.Size                       = UDim2.fromOffset(ENTRY_W, ENTRY_H)
    panel.Position                   = UDim2.fromOffset(ENTRY_W, 0)  -- starts off-screen right
    panel.BackgroundColor3           = Color3.fromRGB(10, 10, 10)
    panel.BackgroundTransparency     = 0.4
    panel.BorderSizePixel            = 0
    panel.Parent                     = wrapper

    -- Thin border via UIStroke
    local stroke              = Instance.new("UIStroke")
    stroke.Color              = Color3.fromRGB(60, 60, 60)
    stroke.Thickness          = 1
    stroke.Transparency       = 0
    stroke.ApplyStrokeMode    = Enum.ApplyStrokeMode.Border
    stroke.Parent             = panel

    -- Kill text label
    local textLabel                    = Instance.new("TextLabel")
    textLabel.Name                     = "KillText"
    textLabel.Size                     = UDim2.new(1, -8, 1, 0)
    textLabel.Position                 = UDim2.fromOffset(4, 0)
    textLabel.BackgroundTransparency   = 1
    textLabel.TextColor3               = Constants.COLOR_TEAM_NEUTRAL
    textLabel.Font                     = Enum.Font.Gotham
    textLabel.TextSize                 = 12
    textLabel.TextXAlignment           = Enum.TextXAlignment.Left
    textLabel.TextYAlignment           = Enum.TextYAlignment.Center
    textLabel.RichText                 = true
    textLabel.Parent                   = panel

    -- Build rich text: Killer › Victim
    local killerTag = colorTag(teamColor(killerTeam))
    local victimTag = colorTag(teamColor(victimTeam))
    local greyTag   = colorTag(Constants.COLOR_TEAM_NEUTRAL)

    if killerName == "" then
        textLabel.Text = string.format(
            '<font color="%s">✦</font> <font color="%s"> › </font> <font color="%s">%s</font>',
            greyTag, greyTag, victimTag, victimName)
    else
        textLabel.Text = string.format(
            '<font color="%s">%s</font> <font color="%s"> › </font> <font color="%s">%s</font>',
            killerTag, killerName, greyTag, victimTag, victimName)
    end

    entries[#entries + 1] = wrapper

    -- ── Slide in from right ────────────────────────────────────────────────────
    TweenService:Create(
        panel,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.fromOffset(0, 0) }
    ):Play()

    -- ── Schedule fade-out ─────────────────────────────────────────────────────
    task.delay(Constants.KILLFEED_DISPLAY_TIME, function()
        if not wrapper.Parent then
            return
        end
        local fadeInfo = TweenInfo.new(Constants.KILLFEED_FADE_TIME, Enum.EasingStyle.Linear)
        TweenService:Create(panel,      fadeInfo, { BackgroundTransparency = 1 }):Play()
        local labelFade = TweenService:Create(textLabel, fadeInfo, { TextTransparency = 1 })
        labelFade:Play()
        labelFade.Completed:Connect(function()
            removeEntry(wrapper)
        end)
    end)
end

-- ============================================================
-- Controller
-- ============================================================

local KillFeedUI = {}

function KillFeedUI:init(playerGui: PlayerGui)
    local screen              = Instance.new("ScreenGui")
    screen.Name               = "KillFeedUI"
    screen.ResetOnSpawn       = false
    screen.IgnoreGuiInset     = true
    screen.DisplayOrder       = 5
    screen.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
    screen.Parent             = playerGui

    -- Container anchored to top-right; entries stack downward via UIListLayout.
    feedContainer                      = Instance.new("Frame")
    feedContainer.Name                 = "KillFeedContainer"
    feedContainer.AnchorPoint          = Vector2.new(1, 0)
    feedContainer.Position             = UDim2.new(1, -CONTAINER_INSET, 0, CONTAINER_INSET)
    feedContainer.Size                 = UDim2.fromOffset(ENTRY_W, 0)
    feedContainer.AutomaticSize        = Enum.AutomaticSize.Y
    feedContainer.BackgroundTransparency = 1
    feedContainer.BorderSizePixel      = 0
    feedContainer.Parent               = screen

    local layout              = Instance.new("UIListLayout")
    layout.SortOrder          = Enum.SortOrder.LayoutOrder
    layout.FillDirection      = Enum.FillDirection.Vertical
    layout.VerticalAlignment  = Enum.VerticalAlignment.Top
    layout.Padding            = UDim.new(0, ENTRY_GAP)
    layout.Parent             = feedContainer

    Logger.debug("[KillFeedUI] GUI created")
end

function KillFeedUI:Start()
    KillFeed.OnClientEvent:Connect(function(
        killerName: string,
        victimName: string,
        killerTeam: string,
        victimTeam: string
    )
        addEntry(killerName, victimName, killerTeam, victimTeam)
        Logger.debug(string.format(
            "[KillFeedUI] %s › %s (%s vs %s)",
            killerName == "" and "✦" or killerName,
            victimName,
            killerTeam,
            victimTeam
        ))
    end)

    Logger.debug("[KillFeedUI] Started")
end

return KillFeedUI
