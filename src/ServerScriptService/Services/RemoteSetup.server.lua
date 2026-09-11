--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > RemoteSetup
--
-- Creates every RemoteEvent and RemoteFunction in ReplicatedStorage > Remotes.
-- This runs once when the server starts, before any other service needs remotes.
-- Clients use WaitForChild() to safely access remotes after they are created.
--
-- IMPORTANT: Add new remotes here AND in docs/PROJECT_MAP.md before using them anywhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Grab the Remotes folder that Rojo creates, or create it if running without Rojo.
-- FindFirstChild returns Instance? (nullable), so we check for nil before casting.
local Remotes: Folder
local existing = ReplicatedStorage:FindFirstChild("Remotes")
if existing then
    Remotes = existing :: Folder  -- nil already ruled out; cast is safe here
else
    local folder = Instance.new("Folder")
    folder.Name = "Remotes"
    folder.Parent = ReplicatedStorage
    Remotes = folder
end

-- Helper: creates a RemoteEvent by name and parents it to the Remotes folder.
local function makeEvent(name: string): RemoteEvent
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = Remotes
    return remote
end

-- Helper: creates a RemoteFunction by name and parents it to the Remotes folder.
local function makeFunction(name: string): RemoteFunction
    local remote = Instance.new("RemoteFunction")
    remote.Name = name
    remote.Parent = Remotes
    return remote
end

-- ============================================================
-- RemoteEvents (server fires to client, or client fires to server)
-- ============================================================

-- Match loop
makeEvent("RoundStateChanged")  -- server → all clients | phase, round, timeLeft update

-- Teams
makeEvent("TeamAssigned")       -- server → individual client | your team for this round

-- Loadout menu
makeEvent("SelectLoadout")      -- client → server | player picks primary weapon + team preference (LoadoutService)

-- Health & combat
makeEvent("HealthChanged")      -- server → affected client | current health value
makeEvent("WeaponFired")        -- client → server | request hit validation
makeEvent("HitConfirmed")       -- server → firing client | cosmetic hitmarker only
makeEvent("AmmoChanged")        -- server → firing client | magazine and reserve after each shot or reload
makeEvent("ReloadRequest")      -- client → server | player requests a magazine reload

-- Objectives
makeEvent("ObjectiveUpdated")   -- server → all clients | anchor capture progress (0–1)
makeEvent("ObjectiveComplete")  -- server → all clients | an objective was finished

-- Teams / death tracking
makeEvent("TeamStatusUpdate")   -- server → all clients | alive count per team after a death
makeEvent("RagdollApplied")     -- server → all clients | triggers death visual on the dying client
makeEvent("KillFeed")           -- server → all clients | killer + victim names and teams for kill feed

-- World
makeEvent("PartDestroyed")      -- server → all clients | trigger destruction VFX
makeEvent("ZoneEffectApplied")  -- server → all clients | trigger visual overlay

-- Combat feedback (character systems — not dummy-specific)
makeEvent("BloodEffect")        -- server → all clients | reproduce a blood burst + surface marks at a hit point

-- Developer dummy control (Studio / DEV_USER_IDS only; validated server-side)
makeEvent("DummyDevCommand")    -- client → server | dev command: subscribe / reset / heal / infinite / blood / hitbox
makeEvent("DummyDevState")      -- server → subscribed dev client | test-dummy state snapshot for the debug HUD

-- AI grunts (available to every player, dev and published — LoadoutMenu buttons)
makeEvent("RespawnBots")        -- client → server | request AIService.RespawnAllSquads(); server-side cooldown
makeEvent("KillAllBots")        -- client → server | request AIService.KillAllBots(); server-side cooldown

-- World weapon model (third-person attachment)
makeEvent("WeaponEquipState")   -- client → server | request equip/holster of world weapon model

-- ============================================================
-- RemoteFunctions (client asks server for data; server replies)
-- ============================================================

makeFunction("GetMatchConfig")  -- client → server | fetch current match state on join
