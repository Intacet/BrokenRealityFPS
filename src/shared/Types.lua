--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > Types
--
-- All shared type definitions live here.
-- Import this module anywhere you need to type-check match state or remote payloads.
-- Example: local Types = require(Modules:WaitForChild("Types"))
--          local payload: Types.RoundStatePayload = ...

-- The five possible round phases (strings, narrowed by the type system).
--
-- SYNC WARNING: Luau cannot derive this union from the Constants.Phase table at compile
-- time — there is no keyof or value-union extraction in the type system. This means the
-- type and the table are two separate declarations of the same truth.
-- Rule: whenever you add or rename a phase in Constants.Phase, update this union too,
-- and vice versa. Both files must always list exactly the same set of phases.
export type Phase = "LOBBY" | "PREP" | "ACTIVE" | "RESULTS" | "MATCHEND"

-- Payload sent by the RoundStateChanged RemoteEvent every second.
-- Clients use this to update countdown timers, round numbers, phase labels, and win counts.
--
-- winner      : name of the team that won the current or most recent round.
--               "" during LOBBY, PREP, and ACTIVE (no winner yet).
--               "Attackers" | "Defenders" for elimination wins.
--               "Time Expired" when defenders win by surviving the timer.
--               During MATCHEND: name of the overall match winner, or "Draw".
-- attackerWins: running count of rounds won by Attackers this match.
-- defenderWins: running count of rounds won by Defenders this match.
export type RoundStatePayload = {
    phase        : Phase,  -- which phase is currently running
    round        : number, -- current round number (0 during LOBBY)
    maxRounds    : number, -- total rounds in the match (from Constants.MAX_ROUNDS)
    timeLeft     : number, -- seconds remaining in the current phase
    winner       : string, -- "" during non-results phases; winner name during RESULTS/MATCHEND
    attackerWins : number, -- Attacker round wins so far this match
    defenderWins : number, -- Defender round wins so far this match
}

-- ModuleScripts must return a table, even if it only contains type exports.
return {}
