--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > TeamService
--
-- Assigns players to Roblox Teams at the start of each PREP phase.
-- Force-spawns every player via LoadCharacter() at PREP (no auto-respawn mid-round).
-- Teleports each player to a random spawn point inside Workspace/Spawns.
-- Fires TeamAssigned to each individual client so their UI can show their role.
-- Tracks which players are alive during ACTIVE and ends the round by elimination.
-- Resets assignments when RESULTS starts so the next round begins clean.
--
-- Phase changes arrive via MatchEvents.PhaseChanged (a BindableEvent).

local Players           = game:GetService("Players")
local Teams             = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Respawn control
-- CharacterAutoLoads = false means Roblox never spawns characters automatically.
-- TeamService calls player:LoadCharacter() at the start of each PREP phase instead.
-- This is the standard pattern for round-based games with no mid-round respawns.
-- ============================================================

Players.CharacterAutoLoads = false

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local TeamAssigned     = Remotes:WaitForChild("TeamAssigned")     :: RemoteEvent
local TeamStatusUpdate = Remotes:WaitForChild("TeamStatusUpdate") :: RemoteEvent

-- ============================================================
-- Configuration
-- Team name strings must exactly match the identifiers in docs/NAMING.md.
-- Colors are defined here for now; move to Constants if any other system needs them.
-- ============================================================

local TEAM_ATTACKERS = "Attackers"
local TEAM_DEFENDERS = "Defenders"
local ATTACKER_COLOR = BrickColor.new("Bright red")
local DEFENDER_COLOR = BrickColor.new("Bright blue")

-- Player attribute holding a team preference ("Auto" | "Attackers" | "Defenders"),
-- written by LoadoutService from the pre-round loadout menu. Read in assignTeams().
local TEAM_PREF_ATTR = (Constants.LOADOUT :: any).ATTR_TEAM_PREF

-- ============================================================
-- State
-- ============================================================

-- Maps each connected Player to their team name for the current round.
-- Cleared at RESULTS so the next PREP assigns fresh.
local playerTeams: { [Player]: string } = {}

-- Alive tracking — populated at PREP, decremented on Humanoid.Died during ACTIVE.
-- nil means not present / dead; true means alive.
local aliveAttackers: { [Player]: boolean } = {}
local aliveDefenders: { [Player]: boolean } = {}

-- Humanoid.Died connections keyed by player for clean disconnection.
local diedConnections: { [Player]: RBXScriptConnection } = {}

-- Mirrors the current phase so PlayerRemoving can decide whether to treat a
-- disconnect as a death without needing to poll MatchService.
local currentPhase: string = Constants.Phase.LOBBY

-- ============================================================
-- Private helpers
-- ============================================================

local function countAlive(aliveMap: { [Player]: boolean }): number
    local count = 0
    for _ in pairs(aliveMap) do
        count += 1
    end
    return count
end

-- Returns the named Roblox Team, creating it if it does not yet exist.
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
local function teleportToSpawn(player: Player, spawnPoints: { BasePart })
    if #spawnPoints == 0 then
        Logger.warn("[TeamService] No spawn points for " .. player.Name .. " — skipping teleport")
        return
    end
    local character = player.Character
    if not character then
        Logger.warn("[TeamService] teleportToSpawn: character is nil for " .. player.Name .. " — skipping")
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then
        Logger.warn("[TeamService] teleportToSpawn: HumanoidRootPart missing for " .. player.Name .. " — skipping")
        return
    end
    local point = spawnPoints[math.random(1, #spawnPoints)]
    root.CFrame = point.CFrame + Vector3.new(0, Constants.TELEPORT_Y_OFFSET, 0)
end

-- Teleports immediately if the character is loaded, or defers until CharacterAdded.
-- Used after LoadCharacter() so we handle the async spawn correctly.
local function teleportWhenReady(player: Player, spawnPoints: { BasePart })
    if player.Character then
        teleportToSpawn(player, spawnPoints)
    else
        local conn: RBXScriptConnection
        conn = player.CharacterAdded:Connect(function()
            conn:Disconnect()
            task.wait()  -- one frame so physics settle
            teleportToSpawn(player, spawnPoints)
        end)
    end
end

-- Fisher-Yates in-place shuffle.
local function shuffle(list: { Player })
    for i = #list, 2, -1 do
        local j    = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
end

-- ============================================================
-- Death tracking
-- ============================================================

-- Called when a player dies or disconnects during ACTIVE.
-- Removes them from the alive table, broadcasts the new alive counts,
-- and checks whether one team has been completely eliminated.
local function handlePlayerDied(player: Player)
    if currentPhase ~= Constants.Phase.ACTIVE then
        return
    end

    local team = playerTeams[player]
    if not team then
        return
    end

    -- Remove from alive tables (safe to call even if already removed)
    aliveAttackers[player] = nil
    aliveDefenders[player] = nil

    local attAlive = countAlive(aliveAttackers)
    local defAlive = countAlive(aliveDefenders)

    Logger.debug(string.format(
        "[TeamService] %s died (%s) — ATK alive: %d  DEF alive: %d",
        player.Name, team, attAlive, defAlive
    ))

    -- Broadcast alive counts to all clients so HUD can update.
    TeamStatusUpdate:FireAllClients(attAlive, defAlive)

    -- Check for elimination win condition.
    if attAlive == 0 and defAlive == 0 then
        -- Simultaneous elimination (rare edge case — both teams die on same tick).
        -- Treat as Defenders win (time-expiry is the tiebreak rule).
        Logger.debug("[TeamService] Simultaneous elimination — Defenders win tiebreak")
        MatchEvents.RoundEndedEarly:Fire("Defenders")
    elseif attAlive == 0 then
        Logger.debug("[TeamService] All Attackers eliminated — Defenders win")
        MatchEvents.RoundEndedEarly:Fire("Defenders")
    elseif defAlive == 0 then
        Logger.debug("[TeamService] All Defenders eliminated — Attackers win")
        MatchEvents.RoundEndedEarly:Fire("Attackers")
    end
end

-- Connects a Humanoid.Died listener for each living player.
-- Called when ACTIVE starts so every character is already loaded and spawned.
local function setupDeathTracking()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then
            continue
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            continue
        end

        local conn: RBXScriptConnection
        conn = humanoid.Died:Connect(function()
            -- Disconnect immediately so we don't double-fire if Died somehow runs twice.
            conn:Disconnect()
            diedConnections[player] = nil
            handlePlayerDied(player)
        end)
        diedConnections[player] = conn
    end

    -- Broadcast initial alive counts now that ACTIVE has started.
    TeamStatusUpdate:FireAllClients(countAlive(aliveAttackers), countAlive(aliveDefenders))
    Logger.debug("[TeamService] Death tracking active")
end

-- Disconnects all Humanoid.Died connections. Called on RESULTS or match end.
local function cleanupDeathTracking()
    for player, conn in pairs(diedConnections) do
        conn:Disconnect()
        diedConnections[player] = nil
    end
    Logger.debug("[TeamService] Death tracking cleaned up")
end

-- ============================================================
-- Core logic
-- ============================================================

-- Maps each player to a team name, honouring the BR_TeamPref attribute that
-- LoadoutService writes from the pre-round menu. Explicit "Attackers"/"Defenders"
-- picks are placed first; "Auto"/unset/invalid preferences fill toward an even
-- split (the caller pre-shuffles `players`, so Auto players split randomly).
-- With two or more players a side is never left empty — the last player added to
-- the full side is moved across. A lone player always gets exactly what they asked for.
local function resolveTeamAssignment(players: { Player }): { [Player]: string }
    local attackers: { Player } = {}
    local defenders: { Player } = {}
    local autoPlayers: { Player } = {}

    for _, player in ipairs(players) do
        local pref = player:GetAttribute(TEAM_PREF_ATTR)
        if pref == TEAM_ATTACKERS then
            table.insert(attackers, player)
        elseif pref == TEAM_DEFENDERS then
            table.insert(defenders, player)
        else
            table.insert(autoPlayers, player)
        end
    end

    for _, player in ipairs(autoPlayers) do
        if #attackers <= #defenders then
            table.insert(attackers, player)
        else
            table.insert(defenders, player)
        end
    end

    if #players > 1 then
        if #attackers == 0 and #defenders > 1 then
            local moved = table.remove(defenders)
            if moved ~= nil then
                table.insert(attackers, moved)
            end
        elseif #defenders == 0 and #attackers > 1 then
            local moved = table.remove(attackers)
            if moved ~= nil then
                table.insert(defenders, moved)
            end
        end
    end

    local assigned: { [Player]: string } = {}
    for _, player in ipairs(attackers) do
        assigned[player] = TEAM_ATTACKERS
    end
    for _, player in ipairs(defenders) do
        assigned[player] = TEAM_DEFENDERS
    end
    return assigned
end

-- Splits connected players across both teams, force-spawns each via LoadCharacter(),
-- teleports to a random spawn, and fires TeamAssigned.
-- Called when PREP starts.
local function assignTeams()
    local players = Players:GetPlayers()
    shuffle(players)

    local attackerTeam   = getOrCreateTeam(TEAM_ATTACKERS, ATTACKER_COLOR)
    local defenderTeam   = getOrCreateTeam(TEAM_DEFENDERS, DEFENDER_COLOR)
    local attackerSpawns = getSpawnPoints(TEAM_ATTACKERS)
    local defenderSpawns = getSpawnPoints(TEAM_DEFENDERS)
    local assignedTeam   = resolveTeamAssignment(players)

    -- Reset alive tables before repopulating for this round.
    table.clear(aliveAttackers)
    table.clear(aliveDefenders)

    -- Force-spawn all players first so LoadCharacter() calls go out concurrently.
    -- teleportWhenReady() handles the async gap between LoadCharacter() and CharacterAdded.
    for _, player in ipairs(players) do
        player:LoadCharacter()
    end

    for _, player in ipairs(players) do
        -- resolveTeamAssignment covers every player; `or TEAM_DEFENDERS` only
        -- satisfies strict-mode nil-narrowing and is never actually reached.
        local teamName: string = assignedTeam[player] or TEAM_DEFENDERS
        local team        = (teamName == TEAM_ATTACKERS) and attackerTeam or defenderTeam
        local spawnPoints = (teamName == TEAM_ATTACKERS) and attackerSpawns or defenderSpawns

        player.Team         = team
        playerTeams[player] = teamName

        -- Mark alive for elimination tracking.
        if teamName == TEAM_ATTACKERS then
            aliveAttackers[player] = true
        else
            aliveDefenders[player] = true
        end

        teleportWhenReady(player, spawnPoints)

        TeamAssigned:FireClient(player, teamName)
        MatchEvents.TeamAssigned:Fire(player, teamName)
        Logger.debug("[TeamService]", player.Name, "→", teamName)
    end

    Logger.debug("[TeamService] Assigned", #players, "players")
end

-- Removes players from their Roblox teams and clears all tracking tables.
-- Called when RESULTS starts so the next PREP assigns fresh.
local function resetTeams()
    cleanupDeathTracking()
    for _, player in ipairs(Players:GetPlayers()) do
        player.Team = nil
    end
    table.clear(playerTeams)
    table.clear(aliveAttackers)
    table.clear(aliveDefenders)
    Logger.debug("[TeamService] Teams reset")
end

-- ============================================================
-- Event listeners
-- ============================================================

Players.PlayerRemoving:Connect(function(player: Player)
    -- Disconnect death tracking if still connected.
    local conn = diedConnections[player]
    if conn then
        conn:Disconnect()
        diedConnections[player] = nil
    end

    -- Treat a mid-ACTIVE disconnect as a death for elimination purposes.
    -- handlePlayerDied reads playerTeams[player], so call it before clearing.
    if currentPhase == Constants.Phase.ACTIVE then
        handlePlayerDied(player)
    end

    -- Clean up all tables.
    playerTeams[player]    = nil
    aliveAttackers[player] = nil
    aliveDefenders[player] = nil
end)

MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    currentPhase = phase

    if phase == Constants.Phase.PREP then
        assignTeams()
    elseif phase == Constants.Phase.ACTIVE then
        setupDeathTracking()
    elseif phase == Constants.Phase.RESULTS then
        resetTeams()
    end
end)

Logger.debug("[TeamService] Ready — waiting for PREP phase")

-- TeamService is a .server.lua Script and cannot be required by other server scripts.
-- Other services access team data by subscribing to MatchEvents.TeamAssigned, not by
-- requiring this file directly.
