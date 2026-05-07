--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > HUD
--
-- Builds and drives the heads-up display: health bar, team alive counts, and ammo.
-- Health is driven by HealthChanged (server → this client only).
-- Alive counts are driven by TeamStatusUpdate (server → all clients).
-- Ammo is driven by AmmoChanged (server → this client only).
-- Visibility is driven by RoundStateChanged — HUD hides during LOBBY and MATCHEND.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects HealthChanged, TeamStatusUpdate, RoundStateChanged

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Types     = require(Modules:WaitForChild("Types"))
local Logger    = require(Modules:WaitForChild("Logger"))

-- Silence unused-variable warning: Types is imported for its exported types only.
local _ = Types

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local HealthChanged     = Remotes:WaitForChild("HealthChanged")     :: RemoteEvent
local TeamStatusUpdate  = Remotes:WaitForChild("TeamStatusUpdate")  :: RemoteEvent
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local AmmoChanged       = Remotes:WaitForChild("AmmoChanged")       :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

local FONT_BOLD   = Enum.Font.GothamBold
local FONT_NORMAL = Enum.Font.Gotham
local WHITE       = Color3.new(1, 1, 1)
local BLACK       = Color3.new(0, 0, 0)

local COLOR_HEALTH_HIGH   = Color3.fromRGB(50,  200,  50)  -- green
local COLOR_HEALTH_MED    = Color3.fromRGB(220, 160,  20)  -- yellow-orange
local COLOR_HEALTH_LOW    = Color3.fromRGB(200,  40,  40)  -- red

local HEALTH_WARN_THRESHOLD   = 0.5   -- below this ratio the bar turns yellow-orange
local HEALTH_DANGER_THRESHOLD = 0.25  -- below this ratio the bar turns red

local HEALTH_BAR_WIDTH  = 200
local HEALTH_BAR_HEIGHT = 14

local AMMO_FRAME_WIDTH  = 130
local AMMO_FRAME_HEIGHT = 44

-- ============================================================
-- GUI references (set inside init())
-- ============================================================

local hudScreen    : ScreenGui
local hudFrame     : Frame
local healthNumber : TextLabel
local healthBarBg  : Frame
local healthBarFill: Frame
local teamStatus   : TextLabel
local ammoFrame    : Frame
local ammoLabel    : TextLabel

-- ============================================================
-- Private helpers
-- ============================================================

local function makeLabel(
    parent: Instance,
    name: string,
    size: UDim2,
    pos: UDim2,
    textSize: number,
    font: Enum.Font
): TextLabel
    local label = Instance.new("TextLabel")
    label.Name                   = name
    label.Size                   = size
    label.Position               = pos
    label.BackgroundTransparency = 1
    label.TextColor3             = WHITE
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3       = BLACK
    label.Font                   = font
    label.TextSize               = textSize
    label.TextXAlignment         = Enum.TextXAlignment.Left
    label.Parent                 = parent
    return label
end

local function setAmmo(mag: number, reserve: number)
    ammoLabel.Text = string.format("%d / %d", mag, reserve)
end

local function setHealth(health: number)
    local ratio = math.clamp(health / Constants.MAX_HEALTH, 0, 1)
    healthNumber.Text = tostring(math.ceil(health))
    healthBarFill.Size = UDim2.new(ratio, 0, 1, 0)

    if ratio > HEALTH_WARN_THRESHOLD then
        healthBarFill.BackgroundColor3 = COLOR_HEALTH_HIGH
    elseif ratio > HEALTH_DANGER_THRESHOLD then
        healthBarFill.BackgroundColor3 = COLOR_HEALTH_MED
    else
        healthBarFill.BackgroundColor3 = COLOR_HEALTH_LOW
    end
end

-- ============================================================
-- Controller
-- ============================================================

local HUD = {}

-- Creates all ScreenGui elements. Must be called before Start().
function HUD:init(playerGui: PlayerGui)
    hudScreen = Instance.new("ScreenGui")
    hudScreen.Name           = "HUD"
    hudScreen.ResetOnSpawn   = false
    hudScreen.IgnoreGuiInset = true
    hudScreen.Parent         = playerGui

    -- Bottom-left frame anchored to the lower-left corner.
    hudFrame = Instance.new("Frame")
    hudFrame.Name                  = "HUDFrame"
    hudFrame.Size                  = UDim2.new(0, HEALTH_BAR_WIDTH + 10, 0, 64)
    hudFrame.Position              = UDim2.new(0, 12, 1, -76)
    hudFrame.BackgroundColor3      = BLACK
    hudFrame.BackgroundTransparency = 0.6
    hudFrame.Visible               = false
    hudFrame.Parent                = hudScreen

    -- Health number label (e.g. "75").
    healthNumber = makeLabel(
        hudFrame, "HealthNumber",
        UDim2.new(0, HEALTH_BAR_WIDTH, 0, 22),
        UDim2.new(0, 6, 0, 4),
        18, FONT_BOLD
    )
    healthNumber.Text = tostring(Constants.MAX_HEALTH)

    -- Health bar background (dark).
    healthBarBg = Instance.new("Frame")
    healthBarBg.Name                  = "HealthBarBg"
    healthBarBg.Size                  = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT)
    healthBarBg.Position              = UDim2.new(0, 6, 0, 28)
    healthBarBg.BackgroundColor3      = Color3.fromRGB(40, 40, 40)
    healthBarBg.BorderSizePixel       = 0
    healthBarBg.Parent                = hudFrame

    -- Health bar fill (coloured, scales with health ratio).
    healthBarFill = Instance.new("Frame")
    healthBarFill.Name             = "HealthBarFill"
    healthBarFill.Size             = UDim2.fromScale(1, 1)
    healthBarFill.BackgroundColor3 = COLOR_HEALTH_HIGH
    healthBarFill.BorderSizePixel  = 0
    healthBarFill.Parent           = healthBarBg

    -- Team status label — bottom of the HUD frame.
    teamStatus = makeLabel(
        hudFrame, "TeamStatus",
        UDim2.new(0, HEALTH_BAR_WIDTH, 0, 18),
        UDim2.new(0, 6, 0, 44),
        13, FONT_NORMAL
    )
    teamStatus.Text = "ATK: — · DEF: —"

    -- Ammo display — bottom-right corner, separate from the health frame.
    ammoFrame = Instance.new("Frame")
    ammoFrame.Name                   = "AmmoFrame"
    ammoFrame.Size                   = UDim2.new(0, AMMO_FRAME_WIDTH, 0, AMMO_FRAME_HEIGHT)
    ammoFrame.Position               = UDim2.new(1, -(AMMO_FRAME_WIDTH + 12), 1, -(AMMO_FRAME_HEIGHT + 16))
    ammoFrame.BackgroundColor3       = BLACK
    ammoFrame.BackgroundTransparency = 0.6
    ammoFrame.BorderSizePixel        = 0
    ammoFrame.Visible                = false
    ammoFrame.Parent                 = hudScreen

    ammoLabel = Instance.new("TextLabel")
    ammoLabel.Name                   = "AmmoLabel"
    ammoLabel.Size                   = UDim2.new(1, -8, 1, 0)
    ammoLabel.Position               = UDim2.fromOffset(4, 0)
    ammoLabel.BackgroundTransparency = 1
    ammoLabel.TextColor3             = WHITE
    ammoLabel.TextStrokeTransparency = 0.5
    ammoLabel.TextStrokeColor3       = BLACK
    ammoLabel.Font                   = FONT_BOLD
    ammoLabel.TextSize               = 22
    ammoLabel.TextXAlignment         = Enum.TextXAlignment.Right
    ammoLabel.Text                   = "— / —"
    ammoLabel.Parent                 = ammoFrame

    Logger.debug("[HUD] GUI created")
end

-- Connects HealthChanged, TeamStatusUpdate, and RoundStateChanged.
-- Must be called after init().
function HUD:Start()
    -- Show full health on first connect so the bar is not empty before the first update.
    setHealth(Constants.MAX_HEALTH)

    HealthChanged.OnClientEvent:Connect(function(health: number)
        setHealth(health)
    end)

    TeamStatusUpdate.OnClientEvent:Connect(function(attAlive: number, defAlive: number)
        teamStatus.Text = string.format("ATK: %d · DEF: %d", attAlive, defAlive)
    end)

    AmmoChanged.OnClientEvent:Connect(function(mag: number, reserve: number)
        setAmmo(mag, reserve)
    end)

    -- Show HUD elements only during active gameplay phases; hide otherwise.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: Types.RoundStatePayload
        local phase   = payload.phase
        local visible = (phase ~= Constants.Phase.LOBBY and phase ~= Constants.Phase.MATCHEND)
        hudFrame.Visible  = visible
        ammoFrame.Visible = visible
    end)

    Logger.debug("[HUD] Started")
end

return HUD
