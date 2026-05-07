--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > DeathScreen
--
-- Owns the full death experience for the local player.
-- Activates when RagdollApplied fires with the local player's UserId.
-- Applies a black overlay fade, a Lighting BlurEffect, and an EqualizerSoundEffect
-- that muffles most audio. Shows death text and killer name while waiting for the
-- next round. Cleans everything up when PREP phase begins.
--
-- What this module does NOT do:
--   - Apply the ragdoll physics  →  RagdollService (server)
--   - Show other players' death effects  →  future kill-feed system
--   - Track round or match state  →  MatchController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")

-- ============================================================
-- Dependencies
-- ============================================================

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

-- UI references created in init()
local overlay: Frame          -- full-screen black overlay
local textContainer: Frame    -- centered death-text block
local killerLabel: TextLabel  -- "Eliminated by [Name]" — hidden if no killer

-- Active death-effect instances; nil when death experience is not showing.
local blurEffect: BlurEffect?              = nil
local eqEffect: EqualizerSoundEffect?      = nil
local activeTween: Tween?                  = nil  -- currently running tween, if any
local isDeathActive: boolean               = false

-- ============================================================
-- Tween helpers
-- ============================================================

local fadeInInfo    = TweenInfo.new(Constants.DEATH_FADE_TIME,    Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local fadeOutInfo   = TweenInfo.new(Constants.DEATH_CLEANUP_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

-- ============================================================
-- Private helpers
-- ============================================================

local function cancelActiveTween()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
end

local function showDeathUI(killerName: string)
    isDeathActive = true

    -- ── Lighting blur ────────────────────────────────────────────────────────────
    local blur = Instance.new("BlurEffect")
    blur.Size   = 0
    blur.Parent = Lighting
    blurEffect  = blur

    -- ── Audio muffle via equalizer ───────────────────────────────────────────────
    local eq          = Instance.new("EqualizerSoundEffect")
    eq.LowGain        = Constants.DEATH_EQ_LOW_GAIN
    eq.MidGain        = Constants.DEATH_EQ_MID_GAIN
    eq.HighGain       = Constants.DEATH_EQ_HIGH_GAIN
    eq.Parent         = SoundService
    eqEffect          = eq

    -- ── Screen overlay fade ──────────────────────────────────────────────────────
    -- BackgroundTransparency: 1 = fully transparent, 0 = fully opaque.
    -- Target: 1 - DEATH_OVERLAY_OPACITY so 60% opacity = 0.4 transparency.
    local targetTransparency = 1 - Constants.DEATH_OVERLAY_OPACITY
    local overlayTween = TweenService:Create(overlay, fadeInInfo, {
        BackgroundTransparency = targetTransparency,
    })
    local blurTween = TweenService:Create(blur, fadeInInfo, {
        Size = Constants.DEATH_BLUR_SIZE,
    })

    cancelActiveTween()
    overlayTween:Play()
    blurTween:Play()
    activeTween = overlayTween  -- track the overlay tween for cancellation

    -- ── Death text (shown after fade completes) ──────────────────────────────────
    if killerName ~= "" then
        killerLabel.Text    = "Eliminated by " .. killerName
        killerLabel.Visible = true
    else
        killerLabel.Visible = false
    end

    task.delay(Constants.DEATH_FADE_TIME, function()
        if isDeathActive then
            textContainer.Visible = true
        end
    end)

    Logger.debug("[DeathScreen] Death experience started | killer:", killerName)
end

local function hideDeathUI()
    if not isDeathActive then
        return
    end
    isDeathActive = false
    textContainer.Visible = false

    -- ── Fade overlay back out ────────────────────────────────────────────────────
    local overlayTween = TweenService:Create(overlay, fadeOutInfo, {
        BackgroundTransparency = 1,
    })
    cancelActiveTween()
    overlayTween:Play()
    activeTween = overlayTween

    -- ── Fade blur back down ──────────────────────────────────────────────────────
    if blurEffect then
        local blurTarget = blurEffect  -- capture reference for the closure
        local blurTween = TweenService:Create(blurTarget, fadeOutInfo, {
            Size = 0,
        })
        blurTween:Play()
        blurTween.Completed:Connect(function()
            blurTarget:Destroy()
        end)
        blurEffect = nil
    end

    -- ── Remove equalizer after cleanup completes ─────────────────────────────────
    if eqEffect then
        local eqTarget = eqEffect
        task.delay(Constants.DEATH_CLEANUP_TIME, function()
            eqTarget:Destroy()
        end)
        eqEffect = nil
    end

    Logger.debug("[DeathScreen] Death experience cleared")
end

-- ============================================================
-- Module
-- ============================================================

local DeathScreen = {}

-- Called by ClientInit before Start(). Creates the ScreenGui and all child
-- instances. Does not make anything visible.
function DeathScreen:init(playerGui: PlayerGui)
    local gui              = Instance.new("ScreenGui")
    gui.Name               = "DeathScreen"
    gui.ResetOnSpawn       = false
    gui.IgnoreGuiInset     = true
    gui.DisplayOrder       = 10  -- render above gameplay UI but below system dialogs
    gui.Parent             = playerGui

    -- Full-screen black overlay — starts transparent, tweened to partial opacity on death.
    local frame                    = Instance.new("Frame")
    frame.Name                     = "Overlay"
    frame.Size                     = UDim2.fromScale(1, 1)
    frame.Position                 = UDim2.fromScale(0, 0)
    frame.BackgroundColor3         = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency   = 1
    frame.BorderSizePixel          = 0
    frame.ZIndex                   = 10
    frame.Parent                   = gui
    overlay = frame

    -- Centered container for death text labels.
    local container              = Instance.new("Frame")
    container.Name               = "DeathText"
    container.Size               = UDim2.fromOffset(500, 160)
    container.Position           = UDim2.new(0.5, -250, 0.5, -80)
    container.BackgroundTransparency = 1
    container.BorderSizePixel    = 0
    container.ZIndex             = 11
    container.Visible            = false
    container.Parent             = gui
    textContainer = container

    -- "YOU DIED" — large, white
    local diedLabel              = Instance.new("TextLabel")
    diedLabel.Name               = "DiedLabel"
    diedLabel.Size               = UDim2.new(1, 0, 0, 72)
    diedLabel.Position           = UDim2.fromOffset(0, 0)
    diedLabel.BackgroundTransparency = 1
    diedLabel.Text               = "YOU DIED"
    diedLabel.TextColor3         = Color3.fromRGB(255, 255, 255)
    diedLabel.TextScaled         = true
    diedLabel.Font               = Enum.Font.GothamBold
    diedLabel.ZIndex             = 11
    diedLabel.Parent             = container

    -- "Eliminated by [Name]" — medium, light red; hidden when no killer
    local killer                 = Instance.new("TextLabel")
    killer.Name                  = "KillerLabel"
    killer.Size                  = UDim2.new(1, 0, 0, 40)
    killer.Position              = UDim2.fromOffset(0, 76)
    killer.BackgroundTransparency = 1
    killer.Text                  = ""
    killer.TextColor3            = Color3.fromRGB(220, 80, 80)
    killer.TextScaled            = true
    killer.Font                  = Enum.Font.Gotham
    killer.ZIndex                = 11
    killer.Visible               = false
    killer.Parent                = container
    killerLabel = killer

    -- "Waiting for next round..." — small, grey
    local waitLabel              = Instance.new("TextLabel")
    waitLabel.Name               = "WaitLabel"
    waitLabel.Size               = UDim2.new(1, 0, 0, 32)
    waitLabel.Position           = UDim2.fromOffset(0, 120)
    waitLabel.BackgroundTransparency = 1
    waitLabel.Text               = "Waiting for next round..."
    waitLabel.TextColor3         = Color3.fromRGB(160, 160, 160)
    waitLabel.TextScaled         = true
    waitLabel.Font               = Enum.Font.Gotham
    waitLabel.ZIndex             = 11
    waitLabel.Parent             = container
end

-- Called by ClientInit after init(). Connects all remote listeners.
function DeathScreen:Start()
    -- Trigger the death experience when the local player's ragdoll fires.
    RagdollApplied.OnClientEvent:Connect(function(userId: number, killerName: string)
        if userId ~= LocalPlayer.UserId then
            return  -- another player died; future kill-feed will handle this
        end
        showDeathUI(killerName)
    end)

    -- Clean up when the next round's PREP phase begins.
    RoundStateChanged.OnClientEvent:Connect(function(payload: { phase: string })
        if payload.phase == Constants.Phase.PREP then
            hideDeathUI()
        end
    end)

    Logger.debug("[DeathScreen] Ready")
end

return DeathScreen
