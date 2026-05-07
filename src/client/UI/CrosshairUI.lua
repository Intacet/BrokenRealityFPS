--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > CrosshairUI
--
-- Builds and drives the crosshair and hitmarker overlays.
--
-- Crosshair: four white axis-aligned bars (top, bottom, left, right) with a 4 px gap.
-- Shown during PREP and ACTIVE; hidden during LOBBY, RESULTS, and MATCHEND.
--
-- Hitmarker: four white bars placed diagonally (NE, NW, SE, SW) forming an X.
-- Hidden by default; shown for 0.1 s when ShowHitmarker() is called.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects RoundStateChanged listener

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

local CH_GAP : number = 4   -- pixels between screen center and the near edge of each bar
local CH_LEN : number = 10  -- pixels for the long dimension of each crosshair bar
local CH_THK : number = 2   -- pixels for the short dimension (thickness) of each bar

-- Hitmarker bar centers are placed CH_HM_DIST pixels diagonally from screen center.
local CH_HM_DIST : number = 8

local WHITE = Color3.new(1, 1, 1)

-- ============================================================
-- GUI references (set inside init())
-- ============================================================

local crosshairContainer : Frame
local hitmarkerContainer : Frame

-- ============================================================
-- Private helpers
-- ============================================================

-- Creates a white bar Frame anchored at its center.
local function makeBar(
    parent   : Instance,
    size     : UDim2,
    position : UDim2,
    rotation : number
): Frame
    local bar                      = Instance.new("Frame")
    bar.Size                       = size
    bar.Position                   = position
    bar.AnchorPoint                = Vector2.new(0.5, 0.5)
    bar.BackgroundColor3           = WHITE
    bar.BorderSizePixel            = 0
    bar.Rotation                   = rotation
    bar.Parent                     = parent
    return bar
end

-- Creates a transparent container Frame centered on screen.
local function makeContainer(parent: Instance, name: string): Frame
    local c                      = Instance.new("Frame")
    c.Name                       = name
    c.Size                       = UDim2.fromScale(1, 1)
    c.BackgroundTransparency     = 1
    c.Parent                     = parent
    return c
end

-- ============================================================
-- Controller
-- ============================================================

local CrosshairUI = {}

-- Creates the ScreenGui with crosshair and hitmarker bars.
-- Must be called before Start().
function CrosshairUI:init(playerGui: PlayerGui)
    local screen              = Instance.new("ScreenGui")
    screen.Name               = "CrosshairUI"
    screen.ResetOnSpawn       = false
    screen.IgnoreGuiInset     = true
    screen.Parent             = playerGui

    -- ── Crosshair ────────────────────────────────────────────────────────────
    crosshairContainer = makeContainer(screen, "Crosshair")
    crosshairContainer.Visible = false  -- hidden until Start() receives a phase

    local cx = 0.5  -- screen center scale
    local cy = 0.5

    -- Top bar: vertical, centered (gap + half-length) above screen center.
    makeBar(crosshairContainer,
        UDim2.new(0, CH_THK, 0, CH_LEN),
        UDim2.new(cx, 0, cy, -(CH_GAP + CH_LEN / 2)),
        0)

    -- Bottom bar: vertical, centered (gap + half-length) below screen center.
    makeBar(crosshairContainer,
        UDim2.new(0, CH_THK, 0, CH_LEN),
        UDim2.new(cx, 0, cy, CH_GAP + CH_LEN / 2),
        0)

    -- Left bar: horizontal, centered (gap + half-length) left of screen center.
    makeBar(crosshairContainer,
        UDim2.new(0, CH_LEN, 0, CH_THK),
        UDim2.new(cx, -(CH_GAP + CH_LEN / 2), cy, 0),
        0)

    -- Right bar: horizontal, centered (gap + half-length) right of screen center.
    makeBar(crosshairContainer,
        UDim2.new(0, CH_LEN, 0, CH_THK),
        UDim2.new(cx, CH_GAP + CH_LEN / 2, cy, 0),
        0)

    -- ── Hitmarker ────────────────────────────────────────────────────────────
    -- Four bars placed at diagonal offsets from center and rotated to form an X.
    -- Rotation -45 (/) and +45 (\) pair up on opposite sides of center.
    hitmarkerContainer = makeContainer(screen, "Hitmarker")
    hitmarkerContainer.Visible = false

    local d = CH_HM_DIST

    -- NE bar (/): top-right of center, rotated -45°.
    makeBar(hitmarkerContainer,
        UDim2.new(0, CH_THK, 0, CH_LEN),
        UDim2.new(cx, d, cy, -d),
        -45)

    -- SW bar (/): bottom-left of center, rotated -45°.
    makeBar(hitmarkerContainer,
        UDim2.new(0, CH_THK, 0, CH_LEN),
        UDim2.new(cx, -d, cy, d),
        -45)

    -- NW bar (\): top-left of center, rotated +45°.
    makeBar(hitmarkerContainer,
        UDim2.new(0, CH_THK, 0, CH_LEN),
        UDim2.new(cx, -d, cy, -d),
        45)

    -- SE bar (\): bottom-right of center, rotated +45°.
    makeBar(hitmarkerContainer,
        UDim2.new(0, CH_THK, 0, CH_LEN),
        UDim2.new(cx, d, cy, d),
        45)

    Logger.debug("[CrosshairUI] GUI created")
end

-- Connects the RoundStateChanged listener. Must be called after init().
function CrosshairUI:Start()
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local phase   = payload.phase
        -- Crosshair visible during PREP and ACTIVE only.
        crosshairContainer.Visible =
            (phase == Constants.Phase.PREP or phase == Constants.Phase.ACTIVE)
    end)

    Logger.debug("[CrosshairUI] Started")
end

-- Shows the hitmarker for 0.1 seconds then hides it.
-- Safe to call rapidly — subsequent calls during the flash window extend it slightly.
function CrosshairUI:ShowHitmarker()
    hitmarkerContainer.Visible = true
    task.delay(0.1, function()
        hitmarkerContainer.Visible = false
    end)
end

return CrosshairUI
