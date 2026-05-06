--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > Types
--
-- All shared type definitions live here.
-- Import this module anywhere you need to type-check match state or remote payloads.
-- Example: local Types = require(Modules:WaitForChild("Types"))
--          local payload: Types.RoundStatePayload = ...

-- The four possible round phases (strings, but narrowed by the type system).
export type Phase = "LOBBY" | "PREP" | "ACTIVE" | "RESULTS"

-- Payload sent by the RoundStateChanged RemoteEvent every second.
-- Clients use this to update countdown timers, round numbers, and phase labels.
export type RoundStatePayload = {
    phase     : Phase,  -- which phase is currently running
    round     : number, -- current round number (0 during LOBBY)
    maxRounds : number, -- total rounds in the match (from Constants.MAX_ROUNDS)
    timeLeft  : number, -- seconds remaining in the current phase
}

-- ModuleScripts must return a table, even if it only contains type exports.
return {}
