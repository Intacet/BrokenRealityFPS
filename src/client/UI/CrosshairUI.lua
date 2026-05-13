--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > CrosshairUI
--
-- Minimal tactical crosshair and hitmarker.
-- Crosshair: four white axis-aligned bars, 2×12 px, 6 px gap from center.
-- Hitmarker: four diagonal bars, 2×10 px, rotated 45°, Color3.fromRGB(220,60,60).
--   Appears instantly; fades to transparent over 0.08s using TweenService.
-- All elements ZIndex 10. No center dot. Sharp rectangles only.
-- Crosshair visible during PREP and ACTIVE; hidden during all other phases.
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
-- Configuration
-- ============================================================

local CH_GAP : number = 6    -- pixels from screen center to near edge of each crosshair bar
local CH_LEN : number = 12   -- long dimension of each crosshair bar in pixels
local CH_THK : number = 2    -- short dimension (thickness) of each bar in pixels

local HM_LEN  : number = 10  -- long dimension of each hitmarker bar
local HM_DIST : number = 8   -- pixels diagonally from center to each hitmarker bar center

local WHITE    = Color3.new(1, 1, 1)
local HM_COLOR = Color3.fromRGB(220, 60, 60)

local ZINDEX = 10

local HM_SHOW_TIME : number = 0.12  -- seconds the hitmarker stays fully visible
local HM_FADE_TIME : number = 0.08  -- seconds to fade the hitmarker out

-- ============================================================
-- GUI references (set inside init())
-- ============================================================

local crosshairContainer : Frame
local hitmarkerBars      : { Frame } = {}

-- ============================================================
-- Private helpers
-- ============================================================

local function makeBar(
    parent   : Instance,
    size     : UDim2,
    position : UDim2,
    rotation : number,
    color    : Color3
): Frame
    local bar                  = Instance.new("Frame")
    bar.Size                   = size
    bar.Position               = position
    bar.AnchorPoint            = Vector2.new(0.5, 0.5)
    bar.BackgroundColor3       = color
    bar.BorderSizePixel        = 0
    bar.Rotation               = rotation
    bar.ZIndex                 = ZINDEX
    bar.Parent                 = parent
    return bar
end

-- ============================================================
-- Controller
-- ============================================================

local CrosshairUI = {}

function CrosshairUI:init(playerGui: PlayerGui)
    local screen              = Instance.new("ScreenGui")
    screen.Name               = "CrosshairUI"
    screen.ResetOnSpawn       = false
    screen.IgnoreGuiInset     = true
    screen.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
    screen.Parent             = playerGui

    -- ── Crosshair ─────────────────────────────────────────────────────────────
    crosshairContainer               = Instance.new("Frame")
    crosshairContainer.Name          = "Crosshair"
    crosshairContainer.Size          = UDim2.fromScale(1, 1)
    crosshairContainer.BackgroundTransparency = 1
    crosshairContainer.ZIndex        = ZINDEX
    crosshairContainer.Visible       = false
    crosshairContainer.Parent        = screen

    local cx = 0.5
    local cy = 0.5

    -- Top
    makeBar(crosshairContainer,
        UDim2.fromOffset(CH_THK, CH_LEN),
        UDim2.new(cx, 0, cy, -(CH_GAP + CH_LEN / 2)),
        0, WHITE)

    -- Bottom
    makeBar(crosshairContainer,
        UDim2.fromOffset(CH_THK, CH_LEN),
        UDim2.new(cx, 0, cy, CH_GAP + CH_LEN / 2),
        0, WHITE)

    -- Left
    makeBar(crosshairContainer,
        UDim2.fromOffset(CH_LEN, CH_THK),
        UDim2.new(cx, -(CH_GAP + CH_LEN / 2), cy, 0),
        0, WHITE)

    -- Right
    makeBar(crosshairContainer,
        UDim2.fromOffset(CH_LEN, CH_THK),
        UDim2.new(cx, CH_GAP + CH_LEN / 2, cy, 0),
        0, WHITE)

    -- ── Hitmarker ─────────────────────────────────────────────────────────────
    -- Four diagonal bars forming an X; built directly in the screen, not in crosshairContainer,
    -- so they can be individually tweened for the fade-out.
    local d = HM_DIST

    -- NE (/)
    hitmarkerBars[1] = makeBar(screen,
        UDim2.fromOffset(CH_THK, HM_LEN),
        UDim2.new(cx, d, cy, -d),
        -45, HM_COLOR)
    -- SW (/)
    hitmarkerBars[2] = makeBar(screen,
        UDim2.fromOffset(CH_THK, HM_LEN),
        UDim2.new(cx, -d, cy, d),
        -45, HM_COLOR)
    -- NW (\)
    hitmarkerBars[3] = makeBar(screen,
        UDim2.fromOffset(CH_THK, HM_LEN),
        UDim2.new(cx, -d, cy, -d),
        45, HM_COLOR)
    -- SE (\)
    hitmarkerBars[4] = makeBar(screen,
        UDim2.fromOffset(CH_THK, HM_LEN),
        UDim2.new(cx, d, cy, d),
        45, HM_COLOR)

    -- Start hidden
    for _, bar in ipairs(hitmarkerBars) do
        bar.BackgroundTransparency = 1
    end

    Logger.debug("[CrosshairUI] GUI created")
end

function CrosshairUI:Start()
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local phase   = payload.phase
        crosshairContainer.Visible =
            (phase == Constants.Phase.PREP or phase == Constants.Phase.ACTIVE)
    end)

    Logger.debug("[CrosshairUI] Started")
end

-- Shows the hitmarker for HM_SHOW_TIME seconds, then fades it over HM_FADE_TIME.
-- Safe to call rapidly — each new call snaps bars back to opaque instantly.
function CrosshairUI:ShowHitmarker()
    -- Snap visible immediately
    for _, bar in ipairs(hitmarkerBars) do
        bar.BackgroundTransparency = 0
    end

    task.delay(HM_SHOW_TIME, function()
        local fadeInfo = TweenInfo.new(HM_FADE_TIME, Enum.EasingStyle.Linear)
        for _, bar in ipairs(hitmarkerBars) do
            TweenService:Create(bar, fadeInfo, { BackgroundTransparency = 1 }):Play()
        end
    end)
end

return CrosshairUI
