--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > MatchEvents
--
-- Holds BindableEvents for server-to-server communication about match state.
--
-- WHY THIS EXISTS:
-- Roblox RemoteEvents only carry data between the server and clients.
-- A server Script cannot listen to a RemoteEvent fired by another server Script.
-- BindableEvents work entirely on the server side and solve this gap.
--
-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  ACTION REQUIRED IN MatchService.server.lua                     ║
-- ║                                                                  ║
-- ║  MatchService must require this module and fire PhaseChanged     ║
-- ║  each time it broadcasts a phase change. Add these two lines:   ║
-- ║                                                                  ║
-- ║  At the top, with the other requires:                           ║
-- ║    local MatchEvents = require(script.Parent                    ║
-- ║        :WaitForChild("MatchEvents"))                            ║
-- ║                                                                  ║
-- ║  Inside broadcast(), after RoundStateChanged:FireAllClients():  ║
-- ║    MatchEvents.PhaseChanged:Fire(phase, round)                  ║
-- ╚══════════════════════════════════════════════════════════════════╝

local MatchEvents = {}

-- Fired by MatchService whenever the round phase changes.
-- Payload: (phase: string, round: number)
-- Current listeners: TeamService, DamageService
-- Future listeners:  ObjectiveService
MatchEvents.PhaseChanged = Instance.new("BindableEvent")

-- Fired by TeamService once per player inside assignTeams().
-- Payload: (player: Player, teamName: string)
-- Current listeners: DamageService, ObjectiveService
MatchEvents.TeamAssigned = Instance.new("BindableEvent")

-- Fired by TeamService (elimination) or ObjectiveService (all anchors planted) to cut
-- the ACTIVE phase short. MatchService's countdown() listens and captures the winner.
-- Payload: (winner: string) — "Attackers" | "Defenders"
-- Fires at most once per round; MatchService disconnects the listener after ACTIVE ends.
MatchEvents.RoundEndedEarly = Instance.new("BindableEvent")

-- Fired by RagdollService after a player's character is ragdolled.
-- TeamService's existing Humanoid.Died listener still handles death tracking;
-- this event exists for services that need to hook into deaths without relying on
-- Humanoid.Died (e.g., future RewardService, CorpseService).
-- Payload: (player: Player, killerName: string) — killerName is "" for environment kills.
MatchEvents.PlayerDied = Instance.new("BindableEvent")

return MatchEvents
