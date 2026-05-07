--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > TeamService
--
-- Assigns players to Roblox Teams at the start of each PREP phase.
-- Teleports each player to a random spawn point inside Workspace/Spawns.
-- Fires TeamAssigned to each individual client so their UI can show their role.
-- Resets assignments when RESULTS starts so the next round begins clean.
--
-- Phase changes arrive via MatchEvents.PhaseChanged (a BindableEvent).
-- See src/server/MatchEvents.lua for the note on wiring MatchService.

local Players           = game:GetService("Players")
local Teams             = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

-- MatchEvents is a sibling ModuleScript in ServerScriptService/Services.
-- script.Parent is that Services folder at runtime.
local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local TeamAssigned = Remotes:WaitForChild("TeamAssigned") :: RemoteEvent

-- ============================================================
-- Configuration
-- Team name strings must exactly match the identifiers in docs/NAMING.md.
-- Colors are defined here for now; move them to Constants if other systems
-- ever need to read team colours (e.g. a kill-feed that tints names).
-- Teleport offset lives in Constants.TELEPORT_Y_OFFSET.
-- ============================================================

local TEAM_ATTACKERS = "Attackers"
local TEAM_DEFENDERS = "Defenders"
local ATTACKER_COLOR = BrickColor.new("Bright red")
local DEFENDER_COLOR = BrickColor.new("Bright blue")

-- ============================================================
-- State
-- ============================================================

-- Maps each connected Player to their team name for the current round.
-- Cleared at RESULTS so the next PREP assigns fresh.
local playerTeams: { [Player]: string } = {}

-- ============================================================
-- Private helpers
-- ============================================================

-- Returns the named Roblox Team, creating it if it does not yet exist.
-- AutoAssignable is disabled — we place players manually.
local function getOrCreateTeam(name: string, color: BrickColor): Team
    local existing = Teams:FindFirstChild(name)
    if existing and existing:IsA("Team") then
        return existing :: Team
    end
    local team          = Instance.new("Team")
    team.Name           = name
    team.TeamColor      = color
    team.AutoAssignable = false
    team.Parent         = Teams
    return team
end

-- Collects every BasePart inside Workspace/Spawns/<folderName>.
-- Warns and returns an empty table if the folder is absent or contains no parts —
-- teleportation will be skipped gracefully rather than throwing an error.
local function getSpawnPoints(folderName: string): { BasePart }
    local spawnsRoot = workspace:FindFirstChild("Spawns")
    if not spawnsRoot then
        Logger.warn("[TeamService] Workspace/Spawns is missing — cannot find spawn points")
        return {}
    end
    local teamFolder = spawnsRoot:FindFirstChild(folderName)
    if not teamFolder then
        Logger.warn("[TeamService] Workspace/Spawns/" .. folderName .. " is missing")
        return {}
    end
    local points: { BasePart } = {}
    for _, child in ipairs(teamFolder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(points, child)
        end
    end
    if #points == 0 then
        Logger.warn("[TeamService] Workspace/Spawns/" .. folderName .. " has no BasePart children")
    end
    return points
end

-- Moves the player's HumanoidRootPart to a random BasePart in spawnPoints.
-- Does nothing if the character or root part is not present.
local function teleportToSpawn(player: Player, spawnPoints: { BasePart })
    if #spawnPoints == 0 then
        Logger.warn("[TeamService] No spawn points for " .. player.Name .. " — skipping teleport")
        return
    end
    local character = player.Character
    if not character then
        -- teleportWhenReady should guarantee the character exists before calling this.
        -- A nil character here means a race condition (player disconnected mid-respawn).
        Logger.warn("[TeamService] teleportToSpawn: character is nil for " .. player.Name .. " — skipping")
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then
        Logger.warn("[TeamService] teleportToSpawn: HumanoidRootPart missing for " .. player.Name .. " — skipping")
        return
    end
    local point = spawnPoints[math.random(1, #spawnPoints)]
    -- Place the character above the spawn part so it lands on the surface cleanly.
    root.CFrame = point.CFrame + Vector3.new(0, Constants.TELEPORT_Y_OFFSET, 0)
end

-- Teleports immediately if the character is loaded, or defers until CharacterAdded
-- fires (handles players who are mid-respawn when PREP begins).
local function teleportWhenReady(player: Player, spawnPoints: { BasePart })
    if player.Character then
        teleportToSpawn(player, spawnPoints)
    else
        local conn: RBXScriptConnection
        conn = player.CharacterAdded:Connect(function()
            conn:Disconnect()
            task.wait()  -- one frame so the character physics settle before we move it
            teleportToSpawn(player, spawnPoints)
        end)
    end
end

-- Fisher-Yates in-place shuffle.
-- Randomises the player list so team composition is different every round.
local function shuffle(list: { Player })
    for i = #list, 2, -1 do
        local j    = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
end

-- ============================================================
-- Core logic
-- ============================================================

-- Splits connected players as evenly as possible across both teams, teleports
-- each to a random spawn, and fires TeamAssigned to their client.
-- Called when PREP starts.
local function assignTeams()
    local players = Players:GetPlayers()
    shuffle(players)  -- random order so no player is always Attacker / always Defender

    local attackerTeam   = getOrCreateTeam(TEAM_ATTACKERS, ATTACKER_COLOR)
    local defenderTeam   = getOrCreateTeam(TEAM_DEFENDERS, DEFENDER_COLOR)
    local attackerSpawns = getSpawnPoints(TEAM_ATTACKERS)
    local defenderSpawns = getSpawnPoints(TEAM_DEFENDERS)

    -- First ceil(n/2) players → Attackers, the rest → Defenders.
    -- Odd player counts give Attackers the extra player.
    local attackerCount = math.ceil(#players / 2)

    for i, player in ipairs(players) do
        local teamName: string
        local team: Team
        local spawnPoints: { BasePart }

        if i <= attackerCount then
            teamName    = TEAM_ATTACKERS
            team        = attackerTeam
            spawnPoints = attackerSpawns
        else
            teamName    = TEAM_DEFENDERS
            team        = defenderTeam
            spawnPoints = defenderSpawns
        end

        player.Team         = team     -- sets the Roblox scoreboard team
        playerTeams[player] = teamName -- records it for other services to query

        teleportWhenReady(player, spawnPoints)

        TeamAssigned:FireClient(player, teamName)
        MatchEvents.TeamAssigned:Fire(player, teamName)  -- notify server services (DamageService, etc.)
        Logger.debug("[TeamService]", player.Name, "→", teamName)
    end

    Logger.debug("[TeamService] Assigned", #players, "players")
end

-- Removes players from their Roblox teams and clears the tracking table.
-- Called when RESULTS starts so the next PREP assigns fresh.
local function resetTeams()
    for _, player in ipairs(Players:GetPlayers()) do
        player.Team = nil  -- sets the player to "Neutral" on the scoreboard
    end
    playerTeams = {}
    Logger.debug("[TeamService] Teams reset")
end

-- ============================================================
-- Event listeners
-- ============================================================

-- Discard a player's assignment if they leave mid-round so the table
-- does not hold a reference to a disconnected Player instance.
Players.PlayerRemoving:Connect(function(player: Player)
    playerTeams[player] = nil
end)

-- React to phase changes from MatchService.
-- PREP    → assign teams and teleport everyone.
-- RESULTS → clear assignments ready for the next round.
-- Other phases (LOBBY, ACTIVE) require no action from TeamService.
MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    if phase == Constants.Phase.PREP then
        assignTeams()
    elseif phase == Constants.Phase.RESULTS then
        resetTeams()
    end
end)

Logger.debug("[TeamService] Ready — waiting for PREP phase")

-- TeamService is a .server.lua Script and cannot be required by other server scripts.
-- Other services access team data by subscribing to MatchEvents.TeamAssigned, not by
-- requiring this file directly.
