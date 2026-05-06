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
-- Current listeners: TeamService
-- Future listeners:  ObjectiveService
MatchEvents.PhaseChanged = Instance.new("BindableEvent")

return MatchEvents
