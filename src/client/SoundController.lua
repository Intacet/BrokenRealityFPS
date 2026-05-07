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

-- ============================================================
-- Dependencies
-- ============================================================

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Logger  = require(Modules:WaitForChild("Logger"))

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
local ID_GUNSHOT  = "rbxassetid://4792534948"
local ID_HIT      = "rbxassetid://4612378292"
local ID_RELOAD   = "rbxassetid://3900723713"
local ID_DEATH    = "rbxassetid://3900724014"
-- DryFire: no asset assigned — no ammo system exists yet (see DEBT-025).
local ID_DRYFIRE  = ""

-- ============================================================
-- Sound references (assigned in init(), read in Start() and public methods)
-- ============================================================
local gunshotSound:  Sound
local hitSound:      Sound
local reloadSound:   Sound
local deathSound:    Sound
local dryFireSound:  Sound

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

    gunshotSound  = makeSound(folder, "Gunshot",    ID_GUNSHOT,  GUNSHOT_VOLUME)
    hitSound      = makeSound(folder, "HitConfirm", ID_HIT,      HIT_VOLUME)
    reloadSound   = makeSound(folder, "Reload",     ID_RELOAD,   RELOAD_VOLUME)
    deathSound    = makeSound(folder, "Death",       ID_DEATH,    DEATH_VOLUME)
    dryFireSound  = makeSound(folder, "DryFire",    ID_DRYFIRE,  DRYFIRE_VOLUME)
    -- DryFire SoundId is empty until an ammo system exists; playing it does nothing.

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
-- No asset is assigned yet — calls are silently no-ops until DEBT-025 is resolved.
function SoundController:PlayDryFire()
    if ID_DRYFIRE == "" then
        Logger.warn("[SoundController] PlayDryFire: no SoundId assigned (DEBT-025)")
        return
    end
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

return SoundController
