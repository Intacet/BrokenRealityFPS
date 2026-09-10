--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > LoadoutService
--
-- Owns each player's pre-round loadout: primary weapon and team preference.
-- These are stored as Player attributes (Constants.LOADOUT.ATTR_PRIMARY /
-- ATTR_TEAM_PREF) so the other .server.lua Scripts that cannot require this one
-- still read the choice:
--   • GunService   — primary weapon stats, ammo, AmmoChanged label, damage source
--   • TeamService  — honours the team preference in assignTeams()
--   • GunController — which viewmodel to equip (attribute replicates to the client)
--
-- LoadoutService is the ONLY writer of those attributes. The client asks for a
-- change through the SelectLoadout RemoteEvent; every field is validated here.
--
-- Phase changes arrive via MatchEvents.PhaseChanged (a BindableEvent) and are
-- only used to reject edits mid-round when LOCK_EDITS_DURING_ACTIVE is true.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))

local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local SelectLoadout  = Remotes:WaitForChild("SelectLoadout") :: RemoteEvent

local LOADOUT = Constants.LOADOUT :: any

-- ============================================================
-- State
-- ============================================================

-- Mirrors the current match phase so SelectLoadout can reject edits during ACTIVE.
local currentPhase: string = Constants.Phase.LOBBY

-- ============================================================
-- Validation helpers
-- ============================================================

-- Returns true when `key` names a weapon row flagged selectable AND has a real
-- WeaponData entry. Locked rows and typos are rejected.
local function isSelectableWeapon(key: unknown): boolean
    if typeof(key) ~= "string" then
        return false
    end
    if WeaponData[key] == nil then
        return false
    end
    for _, row in ipairs(LOADOUT.WEAPONS) do
        if row.key == key then
            return row.selectable == true
        end
    end
    return false
end

-- Returns true when `team` is one of Constants.LOADOUT.TEAM_CHOICES.
local function isValidTeamChoice(team: unknown): boolean
    if typeof(team) ~= "string" then
        return false
    end
    for _, choice in ipairs(LOADOUT.TEAM_CHOICES) do
        if choice == team then
            return true
        end
    end
    return false
end

-- ============================================================
-- Core logic
-- ============================================================

-- Sets the two loadout attributes to their defaults if the player does not yet
-- have a valid value. Safe to call repeatedly.
local function applyDefaults(player: Player)
    if not isSelectableWeapon(player:GetAttribute(LOADOUT.ATTR_PRIMARY)) then
        player:SetAttribute(LOADOUT.ATTR_PRIMARY, LOADOUT.DEFAULT_PRIMARY)
    end
    if not isValidTeamChoice(player:GetAttribute(LOADOUT.ATTR_TEAM_PREF)) then
        player:SetAttribute(LOADOUT.ATTR_TEAM_PREF, LOADOUT.DEFAULT_TEAM_PREF)
    end
end

-- Applies a validated SelectLoadout request. Unknown / locked / malformed fields
-- are ignored individually so a bad weapon does not also drop a good team pick.
local function onSelectLoadout(player: Player, payload: unknown)
    if type(payload) ~= "table" then
        Logger.warn("[LoadoutService] SelectLoadout from", player.Name, "with non-table payload — ignored")
        return
    end

    if LOADOUT.LOCK_EDITS_DURING_ACTIVE and currentPhase == Constants.Phase.ACTIVE then
        Logger.debug("[LoadoutService] SelectLoadout from", player.Name, "ignored — edits locked during ACTIVE")
        return
    end

    local data = payload :: any

    local changedPrimary = false
    if data.primary ~= nil then
        if isSelectableWeapon(data.primary) then
            player:SetAttribute(LOADOUT.ATTR_PRIMARY, data.primary :: string)
            changedPrimary = true
        else
            Logger.debug("[LoadoutService]", player.Name, "requested unavailable weapon:", tostring(data.primary))
        end
    end

    local changedTeam = false
    if data.team ~= nil then
        if isValidTeamChoice(data.team) then
            player:SetAttribute(LOADOUT.ATTR_TEAM_PREF, data.team :: string)
            changedTeam = true
        else
            Logger.debug("[LoadoutService]", player.Name, "requested invalid team:", tostring(data.team))
        end
    end

    Logger.debug(string.format(
        "[LoadoutService] %s loadout → primary=%s%s team=%s%s",
        player.Name,
        tostring(player:GetAttribute(LOADOUT.ATTR_PRIMARY)),
        changedPrimary and "" or " (unchanged)",
        tostring(player:GetAttribute(LOADOUT.ATTR_TEAM_PREF)),
        changedTeam and "" or " (unchanged)"
    ))
end

-- ============================================================
-- Event wiring
-- ============================================================

Players.PlayerAdded:Connect(applyDefaults)
for _, player in ipairs(Players:GetPlayers()) do
    applyDefaults(player)
end

SelectLoadout.OnServerEvent:Connect(onSelectLoadout)

MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    currentPhase = phase
end)

Logger.debug("[LoadoutService] Ready")
