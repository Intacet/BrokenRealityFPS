--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > DeathScreen
--
-- Minimal tactical death screen.
-- Triggered by RagdollApplied on the local player's UserId.
-- Black overlay fades to 0.75 opacity over 0.8s.
-- After 0.4s: "E L I M I N A T E D" white bold size 24.
-- Below: "ELIMINATED BY [Name]" grey size 13 (hidden if no killer).
-- Below: "STANDBY FOR NEXT ROUND" grey size 11, pulsing opacity 0.4→1.0 on 1.5s loop.
-- Clears on PREP with 0.5s fade out.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — creates all ScreenGui instances
--   2. Start()         — connects RagdollApplied and RoundStateChanged listeners

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RagdollApplied    = Remotes:WaitForChild("RagdollApplied")    :: RemoteEvent
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Module state
-- ============================================================

local overlay        : Frame
local textContainer  : Frame
local killerLabel    : TextLabel
local standbyLabel   : TextLabel

local blurEffect     : BlurEffect?             = nil
local eqEffect       : EqualizerSoundEffect?   = nil
local activeTween    : Tween?                  = nil
local pulseTween     : Tween?                  = nil
local isDeathActive  : boolean                 = false

-- ============================================================
-- Tween configs
-- ============================================================

local fadeInInfo  = TweenInfo.new(Constants.DEATH_FADE_TIME,    Enum.EasingStyle.Linear)
local fadeOutInfo = TweenInfo.new(Constants.DEATH_CLEANUP_TIME, Enum.EasingStyle.Linear)
-- Pulse: 0.75s half-period × 2 (reverses) = 1.5s loop, opacity 1.0 → 0.4 → 1.0
local pulseInfo   = TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- ============================================================
-- Private helpers
-- ============================================================

local function cancelActiveTween()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
end

local function cancelPulseTween()
    if pulseTween then
        pulseTween:Cancel()
        pulseTween = nil
    end
end

local function showDeathUI(killerName: string)
    isDeathActive = true

    -- Blur
    local blur = Instance.new("BlurEffect")
    blur.Size   = 0
    blur.Parent = Lighting
    blurEffect  = blur

    -- Audio muffle
    local eq       = Instance.new("EqualizerSoundEffect")
    eq.LowGain     = Constants.DEATH_EQ_LOW_GAIN
    eq.MidGain     = Constants.DEATH_EQ_MID_GAIN
    eq.HighGain    = Constants.DEATH_EQ_HIGH_GAIN
    eq.Parent      = SoundService
    eqEffect       = eq

    -- Fade overlay in to 0.75 opacity (transparency = 0.25)
    local targetTransparency = 1 - Constants.DEATH_OVERLAY_OPACITY
    cancelActiveTween()
    local overlayTween = TweenService:Create(overlay, fadeInInfo, { BackgroundTransparency = targetTransparency })
    local blurTween    = TweenService:Create(blur,    fadeInInfo, { Size = Constants.DEATH_BLUR_SIZE })
    overlayTween:Play()
    blurTween:Play()
    activeTween = overlayTween

    -- Killer label
    if killerName ~= "" then
        killerLabel.Text    = "ELIMINATED BY  " .. killerName
        killerLabel.Visible = true
    else
        killerLabel.Visible = false
    end

    -- Show text block after 0.4s
    task.delay(0.4, function()
        if not isDeathActive then return end
        textContainer.Visible = true

        -- Start standby pulse: TextTransparency 0 → 0.6 → 0 (opacity 1.0 → 0.4 → 1.0)
        standbyLabel.TextTransparency = 0
        cancelPulseTween()
        pulseTween = TweenService:Create(standbyLabel, pulseInfo, { TextTransparency = 0.6 })
        pulseTween:Play()
    end)

    Logger.debug("[DeathScreen] Death experience started | killer:", killerName)
end

local function hideDeathUI()
    if not isDeathActive then return end
    isDeathActive = false

    cancelPulseTween()
    textContainer.Visible = false

    -- Fade overlay back out
    cancelActiveTween()
    local overlayTween = TweenService:Create(overlay, fadeOutInfo, { BackgroundTransparency = 1 })
    overlayTween:Play()
    activeTween = overlayTween

    -- Fade blur back down then destroy
    if blurEffect then
        local blurRef = blurEffect
        blurEffect    = nil
        local blurTween = TweenService:Create(blurRef, fadeOutInfo, { Size = 0 })
        blurTween:Play()
        blurTween.Completed:Connect(function()
            blurRef:Destroy()
        end)
    end

    -- Destroy EQ after cleanup
    if eqEffect then
        local eqRef = eqEffect
        eqEffect    = nil
        task.delay(Constants.DEATH_CLEANUP_TIME, function()
            eqRef:Destroy()
        end)
    end

    Logger.debug("[DeathScreen] Death experience cleared")
end

-- ============================================================
-- Module
-- ============================================================

local DeathScreen = {}

function DeathScreen:init(playerGui: PlayerGui)
    local gui             = Instance.new("ScreenGui")
    gui.Name              = "DeathScreen"
    gui.ResetOnSpawn      = false
    gui.IgnoreGuiInset    = true
    gui.DisplayOrder      = 10
    gui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
    gui.Parent            = playerGui

    -- Full-screen black overlay
    local frame                  = Instance.new("Frame")
    frame.Name                   = "Overlay"
    frame.Size                   = UDim2.fromScale(1, 1)
    frame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel        = 0
    frame.ZIndex                 = 10
    frame.Parent                 = gui
    overlay = frame

    -- Centered text container (hidden until 0.4s after death)
    local container                  = Instance.new("Frame")
    container.Name                   = "DeathText"
    container.Size                   = UDim2.fromOffset(520, 100)
    container.Position               = UDim2.new(0.5, -260, 0.5, -50)
    container.BackgroundTransparency = 1
    container.BorderSizePixel        = 0
    container.ZIndex                 = 11
    container.Visible                = false
    container.Parent                 = gui
    textContainer = container

    -- "E L I M I N A T E D" — white bold size 24
    local elimLabel              = Instance.new("TextLabel")
    elimLabel.Name               = "ElimLabel"
    elimLabel.Size               = UDim2.fromOffset(520, 36)
    elimLabel.Position           = UDim2.fromOffset(0, 0)
    elimLabel.BackgroundTransparency = 1
    elimLabel.Text               = "E L I M I N A T E D"
    elimLabel.TextColor3         = Color3.fromRGB(255, 255, 255)
    elimLabel.Font               = Enum.Font.GothamBold
    elimLabel.TextSize           = 24
    elimLabel.TextXAlignment     = Enum.TextXAlignment.Center
    elimLabel.TextYAlignment     = Enum.TextYAlignment.Center
    elimLabel.ZIndex             = 11
    elimLabel.Parent             = container

    -- "ELIMINATED BY [Name]" — grey size 13
    local killer                 = Instance.new("TextLabel")
    killer.Name                  = "KillerLabel"
    killer.Size                  = UDim2.fromOffset(520, 26)
    killer.Position              = UDim2.fromOffset(0, 38)
    killer.BackgroundTransparency = 1
    killer.Text                  = ""
    killer.TextColor3            = Color3.fromRGB(160, 160, 160)
    killer.Font                  = Enum.Font.Gotham
    killer.TextSize              = 13
    killer.TextXAlignment        = Enum.TextXAlignment.Center
    killer.TextYAlignment        = Enum.TextYAlignment.Center
    killer.ZIndex                = 11
    killer.Visible               = false
    killer.Parent                = container
    killerLabel = killer

    -- "STANDBY FOR NEXT ROUND" — grey size 11, pulsing
    local standby                = Instance.new("TextLabel")
    standby.Name                 = "StandbyLabel"
    standby.Size                 = UDim2.fromOffset(520, 20)
    standby.Position             = UDim2.fromOffset(0, 68)
    standby.BackgroundTransparency = 1
    standby.Text                 = "STANDBY FOR NEXT ROUND"
    standby.TextColor3           = Color3.fromRGB(160, 160, 160)
    standby.Font                 = Enum.Font.Gotham
    standby.TextSize             = 11
    standby.TextXAlignment       = Enum.TextXAlignment.Center
    standby.TextYAlignment       = Enum.TextYAlignment.Center
    standby.TextTransparency     = 0
    standby.ZIndex               = 11
    standby.Parent               = container
    standbyLabel = standby

    Logger.debug("[DeathScreen] GUI created")
end

function DeathScreen:Start()
    RagdollApplied.OnClientEvent:Connect(function(userId: number, killerName: string)
        if userId ~= LocalPlayer.UserId then return end
        showDeathUI(killerName)
    end)

    RoundStateChanged.OnClientEvent:Connect(function(payload: { phase: string })
        if payload.phase == Constants.Phase.PREP then
            hideDeathUI()
        end
    end)

    Logger.debug("[DeathScreen] Ready")
end

return DeathScreen
