--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > ObjectiveService
--
-- Manages anchor planting during the ACTIVE phase.
-- Attackers stand on BaseParts inside Workspace/Objectives to plant a reality anchor.
-- A full plant takes ANCHOR_PLANT_TIME seconds of uninterrupted contact.
-- If the attacker steps off before planting is complete, progress resets to 0.
-- When all objectives are planted, fires MatchEvents.RoundEndedEarly("Attackers").
--
-- Phase changes arrive via MatchEvents.PhaseChanged (set up on ACTIVE, reset on PREP/RESULTS).
-- Team assignments arrive via MatchEvents.TeamAssigned (populated during PREP).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local ObjectiveUpdated  = Remotes:WaitForChild("ObjectiveUpdated")  :: RemoteEvent
local ObjectiveComplete = Remotes:WaitForChild("ObjectiveComplete") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

-- Must match the team name string in TeamService exactly.
-- See DEBT-020 for the plan to centralise team name strings.
local TEAM_ATTACKERS = "Attackers"

-- ============================================================
-- Types
-- ============================================================

type ObjectiveState = {
    part        : BasePart,
    planter     : Player?,           -- who is currently capturing; nil if no capture in progress
    planted     : boolean,
    touchCounts : { [Player]: number }, -- per-player body-part touch count (many parts fire Touched)
    touchConn   : RBXScriptConnection?,
    endConn     : RBXScriptConnection?,
}

-- ============================================================
-- State
-- ============================================================

-- Objectives keyed by their BasePart for O(1) lookup inside touch handlers.
local objectives: { [BasePart]: ObjectiveState } = {}

-- Player team assignments; populated from MatchEvents.TeamAssigned during PREP.
local playerTeams: { [Player]: string } = {}

-- ============================================================
-- Private helpers
-- ============================================================

-- Walks up the ancestor chain to find the Player who owns this character part.
-- Returns nil for non-character parts (map geometry, weapons, etc.).
-- Duplicated from DamageService; see DEBT-018 for the planned shared utility.
local function getPlayerFromPart(hit: BasePart): Player?
    local model = hit:FindFirstAncestorOfClass("Model")
    if not model then
        return nil
    end
    return Players:GetPlayerFromCharacter(model)
end

-- Marks an objective as planted and checks whether all objectives are now planted.
-- Fires RoundEndedEarly("Attackers") when the last anchor goes in.
local function completeObjective(state: ObjectiveState)
    state.planted = true
    state.planter = nil
    Logger.debug("[ObjectiveService] Objective planted:", state.part.Name)
    ObjectiveComplete:FireAllClients(state.part)

    local allPlanted = true
    for _, obj in pairs(objectives) do
        if not obj.planted then
            allPlanted = false
            break
        end
    end

    if allPlanted then
        Logger.debug("[ObjectiveService] All objectives planted — Attackers win")
        MatchEvents.RoundEndedEarly:Fire("Attackers")
    end
end

-- Clears the current planter and broadcasts progress = 0 to clients.
local function cancelCapture(state: ObjectiveState)
    if state.planter then
        Logger.debug("[ObjectiveService] Capture cancelled by", state.planter.Name)
    end
    state.planter = nil
    ObjectiveUpdated:FireAllClients(state.part, 0)
end

-- Spawns a task that ticks capture progress each COUNTDOWN_TICK.
-- The loop exits cleanly if the planter leaves (state.planter changes to nil or a
-- different player) before ANCHOR_PLANT_TIME elapses.
local function startCapture(state: ObjectiveState, planter: Player)
    state.planter = planter
    Logger.debug("[ObjectiveService] Capture started by", planter.Name, "on", state.part.Name)

    task.spawn(function()
        local elapsed = 0
        while state.planter == planter do
            task.wait(Constants.COUNTDOWN_TICK)
            elapsed += Constants.COUNTDOWN_TICK
            local progress = math.min(elapsed / Constants.ANCHOR_PLANT_TIME, 1)
            ObjectiveUpdated:FireAllClients(state.part, progress)
            if elapsed >= Constants.ANCHOR_PLANT_TIME then
                completeObjective(state)
                return
            end
        end
    end)
end

-- Connects Touched/TouchEnded on a BasePart and adds it to the objectives table.
-- Uses per-player touch counting so body-part spam does not cause false entry/exit.
local function registerObjective(part: BasePart)
    local state: ObjectiveState = {
        part        = part,
        planter     = nil,
        planted     = false,
        touchCounts = {},
        touchConn   = nil,
        endConn     = nil,
    }

    state.touchConn = part.Touched:Connect(function(hit: BasePart)
        if state.planted then return end
        local player = getPlayerFromPart(hit)
        if not player then return end
        if playerTeams[player] ~= TEAM_ATTACKERS then return end

        local count = (state.touchCounts[player] or 0) + 1
        state.touchCounts[player] = count

        -- count 0 → 1 is the true entry event; only start if no capture is in progress.
        if count == 1 and state.planter == nil then
            startCapture(state, player)
        end
    end)

    state.endConn = part.TouchEnded:Connect(function(hit: BasePart)
        local player = getPlayerFromPart(hit)
        if not player then return end

        local count = (state.touchCounts[player] or 0) - 1
        if count <= 0 then
            state.touchCounts[player] = nil
            -- count N → 0 is the true exit event; cancel only if this player was the planter.
            if state.planter == player then
                cancelCapture(state)
            end
        else
            state.touchCounts[player] = count
        end
    end)

    objectives[part] = state
    Logger.debug("[ObjectiveService] Registered objective:", part.Name)
end

-- Disconnects all Touched/TouchEnded connections and clears the objectives table.
local function resetObjectives()
    for _, state in pairs(objectives) do
        if state.touchConn then
            state.touchConn:Disconnect()
        end
        if state.endConn then
            state.endConn:Disconnect()
        end
    end
    table.clear(objectives)
    Logger.debug("[ObjectiveService] Objectives reset")
end

-- Scans Workspace/Objectives for BaseParts and registers each one.
local function setupObjectives()
    local objectivesFolder = workspace:FindFirstChild("Objectives")
    if not objectivesFolder then
        Logger.warn("[ObjectiveService] Workspace/Objectives folder missing — no objectives to track")
        return
    end
    local count = 0
    for _, child in ipairs(objectivesFolder:GetChildren()) do
        if child:IsA("BasePart") then
            registerObjective(child :: BasePart)
            count += 1
        end
    end
    if count == 0 then
        Logger.warn("[ObjectiveService] Workspace/Objectives has no BasePart children")
    else
        Logger.debug("[ObjectiveService] Set up", count, "objectives for ACTIVE phase")
    end
end

-- ============================================================
-- Event listeners
-- ============================================================

Players.PlayerRemoving:Connect(function(player: Player)
    playerTeams[player] = nil
    -- Cancel any in-progress capture by the leaving player.
    for _, state in pairs(objectives) do
        if state.planter == player then
            cancelCapture(state)
        end
    end
end)

-- Populate playerTeams as each player is assigned during PREP.
-- TeamService fires TeamAssigned for every connected player before ObjectiveService's
-- PREP handler runs, so playerTeams is already correct by the time ACTIVE begins.
MatchEvents.TeamAssigned.Event:Connect(function(player: Player, teamName: string)
    playerTeams[player] = teamName
end)

MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    if phase == Constants.Phase.PREP then
        -- Clean up the previous round's objective state.
        -- playerTeams is refreshed by incoming TeamAssigned events during PREP.
        resetObjectives()
    elseif phase == Constants.Phase.ACTIVE then
        setupObjectives()
    elseif phase == Constants.Phase.RESULTS then
        -- Disconnect touch listeners so no captures can fire into RESULTS.
        resetObjectives()
    end
end)

Logger.debug("[ObjectiveService] Ready — waiting for ACTIVE phase")
