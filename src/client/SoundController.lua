--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > SoundController
--
-- Owns all client-side audio playback. No sounds are ever played server-side.
-- Sound instances live in a Folder under SoundService so they play without positional
-- attenuation (correct for local-player feedback sounds like gunshot, hit confirm,
-- and death — sounds other players hear are handled separately when needed).
--
-- What this controller does NOT do:
--   - Play sounds other players hear  →  future 3D sound system attached to character parts
--   - Manage ambient or music tracks  →  future MusicController
--   - Apply effects to existing sounds →  DeathScreen owns the death EQ muffle

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local workspace         = game:GetService("Workspace")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Logger     = require(Modules:WaitForChild("Logger"))
local Constants  = require(Modules:WaitForChild("Constants"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local HitConfirmed   = Remotes:WaitForChild("HitConfirmed")   :: RemoteEvent
local RagdollApplied = Remotes:WaitForChild("RagdollApplied") :: RemoteEvent

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Volume constants
-- These belong in Constants.lua once a second caller needs them.
-- Kept here while only SoundController reads them.
-- ============================================================
local GUNSHOT_VOLUME  = 0.6
local HIT_VOLUME      = 0.8
local RELOAD_VOLUME   = 0.7
local DEATH_VOLUME    = 0.8
local DRYFIRE_VOLUME  = 0.5

-- ============================================================
-- Sound asset IDs
-- ============================================================
local ID_GUNSHOT      = "rbxassetid://9118294910"
local ID_HIT          = "rbxassetid://9118294928"
local ID_RELOAD       = "rbxassetid://9118294935"
local ID_DEATH        = "rbxassetid://9118294942"
local ID_DRYFIRE      = "rbxassetid://9118294950"
local ID_WEAPON_FIRE  = "rbxassetid://116842061471256"  -- ak2

-- ============================================================
-- Sound references (assigned in init(), read in Start() and public methods)
-- ============================================================
local gunshotSound:    Sound
local hitSound:        Sound
local reloadSound:     Sound
local deathSound:      Sound
local dryFireSound:    Sound
local weaponFireSound: Sound
local weaponFireFadeTween: Tween?

-- ============================================================
-- Private helpers
-- ============================================================

local function makeSound(parent: Instance, name: string, id: string, volume: number): Sound
    local s         = Instance.new("Sound")
    s.Name          = name
    s.SoundId       = id
    s.Volume        = volume
    s.RollOffMaxDistance = 0   -- no 3D rolloff; these are flat UI/feedback sounds
    s.Parent        = parent
    return s
end

-- ============================================================
-- Controller
-- ============================================================

local SoundController = {}

-- Called by ClientInit before Start(). Creates all Sound instances inside
-- SoundService/GameSounds. No connections are made here.
function SoundController:init()
    local folder      = Instance.new("Folder")
    folder.Name       = "GameSounds"
    folder.Parent     = SoundService

    gunshotSound  = makeSound(folder, "Gunshot",    ID_GUNSHOT,      GUNSHOT_VOLUME)
    hitSound      = makeSound(folder, "HitConfirm", ID_HIT,          HIT_VOLUME)
    reloadSound   = makeSound(folder, "Reload",     ID_RELOAD,       RELOAD_VOLUME)
    deathSound    = makeSound(folder, "Death",      ID_DEATH,        DEATH_VOLUME)
    dryFireSound  = makeSound(folder, "DryFire",   ID_DRYFIRE,      DRYFIRE_VOLUME)

    -- Pre-create the weapon fire sound so the asset is loaded before the first shot.
    -- PlayWeaponFire reuses this instance (Stop + Play) rather than creating a new
    -- Sound each call — eliminates the CDN-load stutter on the first trigger pull.
    local wf = makeSound(folder, "WeaponFire", ID_WEAPON_FIRE, Constants.AKS74_SHOOT_SOUND_VOLUME :: number)
    wf.RollOffMinDistance = Constants.AKS74_SHOOT_SOUND_ROLLOFF_MIN_DISTANCE :: number
    wf.RollOffMaxDistance = Constants.AKS74_SHOOT_SOUND_ROLLOFF_MAX_DISTANCE :: number
    weaponFireSound = wf

    Logger.debug("[SoundController] Sound instances created")
end

-- Called by ClientInit after init(). Connects remote listeners.
function SoundController:Start()
    -- Auto-play hit sound when the server confirms a shot landed.
    -- GunController handles CrosshairUI:ShowHitmarker() on the same event;
    -- both listeners are independent and both fire.
    HitConfirmed.OnClientEvent:Connect(function()
        self:PlayHit()
    end)

    -- Auto-play death sound when the local player is ragdolled.
    -- DeathScreen also listens to this event for visual/EQ effects;
    -- DeathScreen connects first (initialised at step 4), so the EQ is applied
    -- before this handler fires — the death sound plays through the muffle.
    RagdollApplied.OnClientEvent:Connect(function(userId: number)
        if userId == LocalPlayer.UserId then
            self:PlayDeath()
        end
    end)

    Logger.debug("[SoundController] Ready")
end

-- ============================================================
-- Public API
-- ============================================================

-- Plays the gunshot sound. Called by GunController on every confirmed shot.
-- Single Sound instance: rapid calls restart the sound rather than overlapping.
-- See DEBT-024 for the pooling improvement needed at high fire rates.
function SoundController:PlayGunshot()
    gunshotSound:Play()
end

-- Plays the hit-confirmation sound. Auto-called on HitConfirmed; also exposed
-- for any future system that needs a programmatic hit ping.
function SoundController:PlayHit()
    hitSound:Play()
end

-- Plays an empty-chamber click when the player tries to fire with no ammo.
function SoundController:PlayDryFire()
    dryFireSound:Play()
end

-- Plays the weapon reload sound.
function SoundController:PlayReload()
    reloadSound:Play()
end

-- Plays the death sting. Auto-called on RagdollApplied for the local player;
-- also exposed for future systems (e.g. a cutscene that triggers a death sound
-- outside of the normal damage pipeline).
function SoundController:PlayDeath()
    deathSound:Play()
end

-- Plays the weapon fire sound. Reuses the pre-cached Sound instance created in init()
-- so there is no CDN-load stutter on the first shot.
-- soundIds / parent are kept for API compatibility with GunController but are unused:
-- the single ak2 asset is fixed at init time.
function SoundController:PlayWeaponFire(soundIds: { string }, parent: Instance?)
    local s = weaponFireSound
    if s == nil then
        Logger.warn("[SoundController] PlayWeaponFire: sound not initialized")
        return
    end

    -- Cancel any in-progress fade and restore full volume before each shot.
    if weaponFireFadeTween then
        weaponFireFadeTween:Cancel()
        weaponFireFadeTween = nil
    end
    s.Volume = Constants.AKS74_SHOOT_SOUND_VOLUME :: number

    s.PlaybackSpeed = (Constants.AKS74_SHOOT_SOUND_PLAYBACK_SPEED_MIN :: number)
        + math.random() * (
            (Constants.AKS74_SHOOT_SOUND_PLAYBACK_SPEED_MAX :: number)
            - (Constants.AKS74_SHOOT_SOUND_PLAYBACK_SPEED_MIN :: number)
        )
    s:Play()

    -- Fade volume to 0 over the tail so shots decay naturally instead of cutting off.
    local fadeTime = Constants.AKS74_SHOOT_SOUND_FADE_TIME :: number
    local tweenInfo = TweenInfo.new(fadeTime, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(s, tweenInfo, { Volume = 0 })
    tween:Play()
    weaponFireFadeTween = tween

    if Constants.AKS74_SHOOT_SOUND_DEBUG :: boolean then
        Logger.debug("[SoundController] PlayWeaponFire: played " .. ID_WEAPON_FIRE)
    end
end

return SoundController
