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
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
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

-- Health & combat
makeEvent("HealthChanged")      -- server → affected client | current health value
makeEvent("WeaponFired")        -- client → server | request hit validation
makeEvent("HitConfirmed")       -- server → firing client | cosmetic hitmarker only

-- Objectives
makeEvent("ObjectiveUpdated")   -- server → all clients | anchor capture progress (0–1)
makeEvent("ObjectiveComplete")  -- server → all clients | an objective was finished

-- World
makeEvent("PartDestroyed")      -- server → all clients | trigger destruction VFX
makeEvent("ZoneEffectApplied")  -- server → all clients | trigger visual overlay

-- ============================================================
-- RemoteFunctions (client asks server for data; server replies)
-- ============================================================

makeFunction("GetMatchConfig")  -- client → server | fetch current match state on join
