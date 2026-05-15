--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > HUD
--
-- Minimal tactical HUD.
-- Bottom-left cluster: HEALTH label, bar (220×6 px), health number, ATK/DEF alive counts.
-- Bottom-right ammo block: magazine number (large), divider, reserve (small), weapon name.
-- Health bar transitions: white → amber below 50% → red below 25%.
-- Magazine number transitions: amber at ≤5, red at 0.
-- Magazine number pulses (scale 1.0 → 1.15 → 1.0 over 0.1s) on every AmmoChanged.
-- All color transitions use TweenService.
-- Visibility: hidden during LOBBY and MATCHEND.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects all remote listeners

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local HealthChanged     = Remotes:WaitForChild("HealthChanged")     :: RemoteEvent
local TeamStatusUpdate  = Remotes:WaitForChild("TeamStatusUpdate")  :: RemoteEvent
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local AmmoChanged       = Remotes:WaitForChild("AmmoChanged")       :: RemoteEvent

-- ============================================================
-- Design tokens
-- ============================================================

local PANEL_COLOR       = Color3.fromRGB(10, 10, 10)
local PANEL_ALPHA       = 0.6
local WHITE             = Color3.new(1, 1, 1)
local GREY              = Color3.fromRGB(160, 160, 160)
local COLOR_ATK         = Color3.fromRGB(200, 60, 60)
local COLOR_DEF         = Color3.fromRGB(60, 120, 200)
local COLOR_WARN        = Color3.fromRGB(220, 160, 40)

local BAR_FULL  = WHITE
local BAR_MED   = COLOR_WARN
local BAR_LOW   = COLOR_ATK  -- same red as attacker accent

local HEALTH_BAR_W  = 220
local HEALTH_BAR_H  = 6
local HUD_PAD       = 12
local HUD_BOTTOM    = 16

-- ============================================================
-- GUI references (set in init())
-- ============================================================

local hudScreen     : ScreenGui
local hudFrame      : Frame      -- bottom-left health cluster
local ammoFrame     : Frame      -- bottom-right ammo block
local healthBarFill : Frame
local healthNumber  : TextLabel
local aliveLabel    : TextLabel
local magLabel      : TextLabel
local magScale      : UIScale
local reserveLabel  : TextLabel
local weaponLabel   : TextLabel  -- server-sent weapon name shown below reserve count

-- ============================================================
-- Helpers
-- ============================================================

local function label(
    parent   : Instance,
    text     : string,
    size     : UDim2,
    pos      : UDim2,
    fontSize : number,
    bold     : boolean,
    color    : Color3
): TextLabel
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = size
    lbl.Position               = pos
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = color
    lbl.Font                   = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    lbl.TextSize               = fontSize
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.TextYAlignment         = Enum.TextYAlignment.Center
    lbl.Parent                 = parent
    return lbl
end

local function setHealthColor(ratio: number)
    local target: Color3
    if ratio > 0.5 then
        target = BAR_FULL
    elseif ratio > 0.25 then
        target = BAR_MED
    else
        target = BAR_LOW
    end
    TweenService:Create(
        healthBarFill,
        TweenInfo.new(0.15, Enum.EasingStyle.Linear),
        { BackgroundColor3 = target }
    ):Play()
end

local function setHealth(hp: number)
    local ratio = math.clamp(hp / Constants.MAX_HEALTH, 0, 1)
    healthNumber.Text = tostring(math.ceil(hp))
    TweenService:Create(
        healthBarFill,
        TweenInfo.new(0.1, Enum.EasingStyle.Linear),
        { Size = UDim2.new(ratio, 0, 1, 0) }
    ):Play()
    setHealthColor(ratio)
end

local function setAmmo(weaponName: string, mag: number, reserve: number)
    weaponLabel.Text  = weaponName
    magLabel.Text     = tostring(mag)
    reserveLabel.Text = tostring(reserve)

    -- Color magazine number based on ammo level
    local magColor: Color3
    if mag == 0 then
        magColor = BAR_LOW
    elseif mag <= 5 then
        magColor = COLOR_WARN
    else
        magColor = WHITE
    end
    magLabel.TextColor3 = magColor

    -- Pulse scale: 1.0 → 1.15 → 1.0 over 0.1s
    magScale.Scale = 1.0
    TweenService:Create(magScale, TweenInfo.new(0.05, Enum.EasingStyle.Linear), { Scale = 1.15 }):Play()
    task.delay(0.05, function()
        TweenService:Create(magScale, TweenInfo.new(0.05, Enum.EasingStyle.Linear), { Scale = 1.0 }):Play()
    end)
end

-- ============================================================
-- Controller
-- ============================================================

local HUD = {}

function HUD:init(playerGui: PlayerGui)
    hudScreen               = Instance.new("ScreenGui")
    hudScreen.Name          = "HUD"
    hudScreen.ResetOnSpawn  = false
    hudScreen.IgnoreGuiInset = true
    hudScreen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudScreen.Parent        = playerGui

    -- ── Bottom-left health cluster ────────────────────────────────────────────
    -- Layout (top to bottom, all within hudFrame):
    --   "HEALTH"  (grey, 11)
    --   [====bar====] [number]
    --   ATK: N  |  DEF: N  (grey, 11)

    local clusterH = 11 + 4 + HEALTH_BAR_H + 4 + 11  -- labels + bar + gaps
    hudFrame                     = Instance.new("Frame")
    hudFrame.Name                = "HealthCluster"
    hudFrame.Size                = UDim2.fromOffset(HEALTH_BAR_W + 40, clusterH + 8)
    hudFrame.Position            = UDim2.new(0, HUD_PAD, 1, -(clusterH + 8 + HUD_BOTTOM))
    hudFrame.BackgroundColor3    = PANEL_COLOR
    hudFrame.BackgroundTransparency = PANEL_ALPHA
    hudFrame.BorderSizePixel     = 0
    hudFrame.Visible             = false
    hudFrame.Parent              = hudScreen

    -- "HEALTH" label
    label(hudFrame, "HEALTH",
        UDim2.fromOffset(HEALTH_BAR_W, 11),
        UDim2.fromOffset(6, 4),
        11, false, GREY)

    -- Bar row: bar background + fill + health number side-by-side
    local barY = 4 + 11 + 4
    local barBg              = Instance.new("Frame")
    barBg.Name               = "BarBg"
    barBg.Size               = UDim2.fromOffset(HEALTH_BAR_W, HEALTH_BAR_H)
    barBg.Position           = UDim2.fromOffset(6, barY)
    barBg.BackgroundColor3   = Color3.fromRGB(30, 30, 30)
    barBg.BorderSizePixel    = 0
    barBg.Parent             = hudFrame

    healthBarFill            = Instance.new("Frame")
    healthBarFill.Name       = "BarFill"
    healthBarFill.Size       = UDim2.fromScale(1, 1)
    healthBarFill.BackgroundColor3 = BAR_FULL
    healthBarFill.BorderSizePixel  = 0
    healthBarFill.Parent     = barBg

    healthNumber = label(hudFrame, tostring(Constants.MAX_HEALTH),
        UDim2.fromOffset(36, HEALTH_BAR_H + 4),
        UDim2.fromOffset(HEALTH_BAR_W + 8, barY - 2),
        14, true, WHITE)
    healthNumber.TextXAlignment = Enum.TextXAlignment.Left

    -- Alive counts label
    local aliveY = barY + HEALTH_BAR_H + 4
    aliveLabel = label(hudFrame, "ATK: —  |  DEF: —",
        UDim2.fromOffset(HEALTH_BAR_W + 34, 11),
        UDim2.fromOffset(6, aliveY),
        11, false, GREY)

    -- ── Bottom-right ammo block ───────────────────────────────────────────────
    -- Layout (top to bottom):
    --   [magazine number large]
    --   ────────────────  (thin line)
    --   [reserve small grey]
    --   [weapon name small grey]  ← text set by AmmoChanged, defaults to Constants.DEFAULT_WEAPON

    local ammoW = 90
    local ammoH = 70
    ammoFrame                     = Instance.new("Frame")
    ammoFrame.Name                = "AmmoBlock"
    ammoFrame.Size                = UDim2.fromOffset(ammoW, ammoH)
    ammoFrame.Position            = UDim2.new(1, -(ammoW + HUD_PAD), 1, -(ammoH + HUD_BOTTOM))
    ammoFrame.BackgroundColor3    = PANEL_COLOR
    ammoFrame.BackgroundTransparency = PANEL_ALPHA
    ammoFrame.BorderSizePixel     = 0
    ammoFrame.Visible             = false
    ammoFrame.Parent              = hudScreen

    -- Magazine number — large, centred, with a UIScale for the pulse
    local magWrapper              = Instance.new("Frame")
    magWrapper.Name               = "MagWrapper"
    magWrapper.Size               = UDim2.fromOffset(ammoW, 34)
    magWrapper.Position           = UDim2.fromOffset(0, 4)
    magWrapper.BackgroundTransparency = 1
    magWrapper.Parent             = ammoFrame

    magScale                = Instance.new("UIScale")
    magScale.Scale          = 1
    magScale.Parent         = magWrapper

    magLabel = Instance.new("TextLabel")
    magLabel.Name                   = "MagLabel"
    magLabel.Size                   = UDim2.fromScale(1, 1)
    magLabel.BackgroundTransparency = 1
    magLabel.Text                   = "—"
    magLabel.TextColor3             = WHITE
    magLabel.Font                   = Enum.Font.GothamBold
    magLabel.TextSize               = 28
    magLabel.TextXAlignment         = Enum.TextXAlignment.Center
    magLabel.TextYAlignment         = Enum.TextYAlignment.Center
    magLabel.Parent                 = magWrapper

    -- Thin divider line
    local divider              = Instance.new("Frame")
    divider.Name               = "Divider"
    divider.Size               = UDim2.new(1, -12, 0, 1)
    divider.Position           = UDim2.fromOffset(6, 40)
    divider.BackgroundColor3   = GREY
    divider.BackgroundTransparency = 0.4
    divider.BorderSizePixel    = 0
    divider.Parent             = ammoFrame

    -- Reserve count
    reserveLabel = label(ammoFrame, "—",
        UDim2.fromOffset(ammoW, 14),
        UDim2.fromOffset(0, 43),
        14, false, GREY)
    reserveLabel.TextXAlignment = Enum.TextXAlignment.Center

    -- Weapon name — populated by AmmoChanged; defaults to Constants.DEFAULT_WEAPON
    -- until the first event arrives so the label is never blank at startup.
    weaponLabel = label(ammoFrame, Constants.DEFAULT_WEAPON,
        UDim2.fromOffset(ammoW, 12),
        UDim2.fromOffset(0, 57),
        10, false, GREY)
    weaponLabel.TextXAlignment = Enum.TextXAlignment.Center

    Logger.debug("[HUD] GUI created")
end

function HUD:Start()
    setHealth(Constants.MAX_HEALTH)

    HealthChanged.OnClientEvent:Connect(function(hp: number)
        setHealth(hp)
    end)

    TeamStatusUpdate.OnClientEvent:Connect(function(attAlive: number, defAlive: number)
        local atkStr = string.format('<font color="rgb(%d,%d,%d)">ATK: %d</font>', 200, 60, 60, attAlive)
        local defStr = string.format('<font color="rgb(%d,%d,%d)">DEF: %d</font>', 60, 120, 200, defAlive)
        aliveLabel.RichText = true
        aliveLabel.Text     = atkStr .. "  |  " .. defStr
        -- suppress unused warnings
        local _ = COLOR_ATK
        local __ = COLOR_DEF
    end)

    AmmoChanged.OnClientEvent:Connect(function(weaponName: string, mag: number, reserve: number)
        setAmmo(weaponName, mag, reserve)
    end)

    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local show = (payload.phase ~= Constants.Phase.LOBBY and payload.phase ~= Constants.Phase.MATCHEND)
        hudFrame.Visible  = show
        ammoFrame.Visible = show
    end)

    Logger.debug("[HUD] Started")
end

return HUD
