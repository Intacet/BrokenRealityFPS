--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > CrosshairUI
--
-- Fixed crosshair image at screen center + barrel dot that drifts with free-aim inertia.
-- Crosshair: ImageLabel using CROSSHAIR_IMAGE_ID, always fixed at true screen center.
-- Barrel dot: small filled circle that follows where the gun barrel is actually pointing.
--   Drifts with free-aim offset; returns to screen center as inertia fades.
-- Hitmarker: four diagonal bars, 2×10 px, Color3.fromRGB(220,60,60).
--   Appears instantly; fades over HM_FADE_TIME seconds.
-- All elements ZIndex 10.
-- Crosshair + dot visible during PREP and ACTIVE; hidden during all other phases.
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

-- Crosshair image: fixed at screen center; always shows where bullets land.
local CROSSHAIR_IMAGE_ID : string = "rbxassetid://82580952195402"
local CROSSHAIR_SIZE     : number = 32   -- pixels; small, matches dot scale

-- Barrel dot: drifts with gun inertia / free-aim, returns to center.
-- Slightly larger than a pixel so it reads clearly, similar visual weight to the crosshair.
local DOT_SIZE  : number = 8    -- pixels; diameter
local DOT_COLOR          = Color3.new(1, 1, 1)
local DOT_ALPHA : number = 0.1  -- nearly opaque for readability

-- Hitmarker
local HM_LEN  : number = 10
local HM_DIST : number = 8
local HM_THK  : number = 2
local HM_COLOR           = Color3.fromRGB(220, 60, 60)

local ZINDEX : number = 10

local HM_SHOW_TIME : number = 0.12
local HM_FADE_TIME : number = 0.08

-- ============================================================
-- GUI references (set inside init())
-- ============================================================

local crosshairImg  : ImageLabel      -- fixed at screen center; never shifted
local barrelDot     : Frame           -- drifts with free-aim to show barrel aim point
local hitmarkerBars : { Frame } = {}

local freeAimEnabled: boolean = false

-- Visibility inputs: the round phase allows the reticle, and whether we are currently
-- hip-firing (in which case the fixed centre crosshair is hidden per Constants).
local phaseShowsReticle: boolean = false
local hipfireActive:     boolean = false
-- Developer override (DummyDebugUI "Crosshair" button). When false the crosshair image
-- AND the floating gun-direction dot are hidden regardless of phase / hipfire state.
local userCrosshairEnabled: boolean = true

-- ============================================================
-- Private helpers
-- ============================================================

-- Applies the current visibility state. barrelDot (the floating gun-direction reticle)
-- shows whenever the phase allows it. crosshairImg (fixed centre) additionally hides
-- while hip-firing when FREE_AIM_HIDE_CENTER_CROSSHAIR_HIPFIRE is set.
local function updateVisibility()
    if not crosshairImg or not barrelDot then
        return
    end
    barrelDot.Visible = phaseShowsReticle and userCrosshairEnabled
    local hideCenter = hipfireActive
        and (Constants.FREE_AIM_HIDE_CENTER_CROSSHAIR_HIPFIRE :: boolean)
    crosshairImg.Visible = phaseShowsReticle and userCrosshairEnabled and not hideCenter
end

local function makeBar(
    parent   : Instance,
    size     : UDim2,
    position : UDim2,
    rotation : number,
    color    : Color3
): Frame
    local bar            = Instance.new("Frame")
    bar.Size             = size
    bar.Position         = position
    bar.AnchorPoint      = Vector2.new(0.5, 0.5)
    bar.BackgroundColor3 = color
    bar.BorderSizePixel  = 0
    bar.Rotation         = rotation
    bar.ZIndex           = ZINDEX
    bar.Parent           = parent
    return bar
end

-- ============================================================
-- Controller
-- ============================================================

local CrosshairUI = {}

function CrosshairUI:init(playerGui: PlayerGui)
    local screen          = Instance.new("ScreenGui")
    screen.Name           = "CrosshairUI"
    screen.ResetOnSpawn   = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent         = playerGui

    -- ── Fixed crosshair image (always at screen center) ───────────────────────
    -- Lives directly in the ScreenGui; free-aim never shifts it.
    crosshairImg                     = Instance.new("ImageLabel")
    crosshairImg.Name                = "CrosshairImage"
    crosshairImg.Size                = UDim2.fromOffset(CROSSHAIR_SIZE, CROSSHAIR_SIZE)
    crosshairImg.Position            = UDim2.new(0.5, 0, 0.5, 0)
    crosshairImg.AnchorPoint         = Vector2.new(0.5, 0.5)
    crosshairImg.Image               = CROSSHAIR_IMAGE_ID
    crosshairImg.BackgroundTransparency = 1
    crosshairImg.BorderSizePixel     = 0
    crosshairImg.ZIndex              = ZINDEX
    crosshairImg.ScaleType           = Enum.ScaleType.Fit
    crosshairImg.Visible             = false
    crosshairImg.Parent              = screen

    -- ── Barrel dot (drifts with free-aim inertia) ─────────────────────────────
    -- Starts at screen center; SetFreeAimOffset moves it to show actual barrel aim point.
    -- Returns to center as inertia settles, converging on the crosshair.
    barrelDot                     = Instance.new("Frame")
    barrelDot.Name                = "BarrelDot"
    barrelDot.Size                = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
    barrelDot.Position            = UDim2.new(0.5, 0, 0.5, 0)
    barrelDot.AnchorPoint         = Vector2.new(0.5, 0.5)
    barrelDot.BackgroundColor3    = DOT_COLOR
    barrelDot.BackgroundTransparency = DOT_ALPHA
    barrelDot.BorderSizePixel     = 0
    barrelDot.ZIndex              = ZINDEX + 1   -- always on top of crosshair image
    barrelDot.Visible             = false
    barrelDot.Parent              = screen

    -- Rounded corners so the dot is a circle.
    local corner       = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent      = barrelDot

    -- ── Hitmarker (fixed at screen center) ────────────────────────────────────
    local cx = 0.5
    local cy = 0.5
    local d  = HM_DIST

    hitmarkerBars[1] = makeBar(screen, UDim2.fromOffset(HM_THK, HM_LEN),
        UDim2.new(cx,  d, cy, -d), -45, HM_COLOR)
    hitmarkerBars[2] = makeBar(screen, UDim2.fromOffset(HM_THK, HM_LEN),
        UDim2.new(cx, -d, cy,  d), -45, HM_COLOR)
    hitmarkerBars[3] = makeBar(screen, UDim2.fromOffset(HM_THK, HM_LEN),
        UDim2.new(cx, -d, cy, -d),  45, HM_COLOR)
    hitmarkerBars[4] = makeBar(screen, UDim2.fromOffset(HM_THK, HM_LEN),
        UDim2.new(cx,  d, cy,  d),  45, HM_COLOR)

    for _, bar in ipairs(hitmarkerBars) do
        bar.BackgroundTransparency = 1
    end

    Logger.debug("[CrosshairUI] GUI created")
end

function CrosshairUI:Start()
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        phaseShowsReticle = (payload.phase == Constants.Phase.PREP
                          or payload.phase == Constants.Phase.ACTIVE)
        updateVisibility()
    end)

    Logger.debug("[CrosshairUI] Started")
end

-- ============================================================
-- Free-aim barrel dot API (Stage 1 — visual only)
-- ============================================================

-- Moves the barrel dot by the free-aim pixel offset from screen center.
-- The crosshair image is NOT moved — it stays fixed at the bullet aim point.
-- Called every RenderStepped by GunController with FreeAimController:GetSmoothedAimOffset().
function CrosshairUI:SetFreeAimOffset(offset: Vector2): ()
    local dot = barrelDot
    if not dot then
        Logger.warn("[CrosshairUI] SetFreeAimOffset: barrelDot is nil")
        return
    end
    dot.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
end

-- Enables or disables free-aim dot movement.
-- When disabled the barrel dot snaps back to screen center (converges with crosshair).
function CrosshairUI:SetFreeAimEnabled(enabled: boolean): ()
    assert(typeof(enabled) == "boolean", "[CrosshairUI] SetFreeAimEnabled: expected boolean")
    freeAimEnabled = enabled
    if not enabled then
        local dot = barrelDot
        if dot then
            dot.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end
end

-- Called each frame by GunController: true while hip-firing (armed, not ADS). Hides the
-- fixed centre crosshair so only the floating gun-direction reticle shows during hipfire.
function CrosshairUI:SetHipfireActive(active: boolean): ()
    assert(typeof(active) == "boolean", "[CrosshairUI] SetHipfireActive: expected boolean")
    if active == hipfireActive then
        return
    end
    hipfireActive = active
    updateVisibility()
end

-- Developer toggle (DummyDebugUI). false hides the crosshair image + the floating dot
-- entirely; true restores normal phase/hipfire-driven visibility.
function CrosshairUI:SetUserEnabled(enabled: boolean): ()
    assert(typeof(enabled) == "boolean", "[CrosshairUI] SetUserEnabled: expected boolean")
    if enabled == userCrosshairEnabled then
        return
    end
    userCrosshairEnabled = enabled
    updateVisibility()
end

-- Current state of the developer toggle above.
function CrosshairUI:IsUserEnabled(): boolean
    return userCrosshairEnabled
end

-- ============================================================
-- Hitmarker
-- ============================================================

-- Shows the hitmarker for HM_SHOW_TIME seconds then fades it over HM_FADE_TIME.
-- Safe to call rapidly — each call snaps bars back to fully opaque immediately.
function CrosshairUI:ShowHitmarker()
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
