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

-- ============================================================
-- Combat / damage (2026-09-09)
-- Shared by DamageService, DamageRules, GunService, DummyService, RagdollService,
-- and future BloodService / HitReactionService / GoreService consumers.
-- ============================================================

-- Category of an incoming damage event. Only "Bullet" is produced today (GunService);
-- the rest are declared now so future sources do not need a type change.
--
-- SYNC WARNING: mirrors Constants.DamageType. Luau cannot derive this union from the
-- table, so both are separate declarations of the same set — change them together.
export type DamageType = "Bullet" | "Explosion" | "Melee" | "Fall" | "Zone" | "Unknown"

-- Which body region of an R6 rig was hit. "Unknown" is used when no hit part is known
-- (e.g. the legacy DamageService:Apply path) and always carries a ×1 multiplier.
--
-- SYNC WARNING: mirrors Constants.HitRegion — change both together.
export type HitRegion = "Head" | "Torso" | "LeftArm" | "RightArm" | "LeftLeg" | "RightLeg" | "Unknown"

-- A single resolved damage application. DamageService builds the completed record
-- (region resolved, finalAmount computed) and attaches it to CombatEvents.DamageDealt /
-- CombatEvents.EntityKilled. Callers of DamageService:ApplyDamage pass the same shape
-- with `finalAmount` omitted / 0 — DamageService fills it in.
--
-- targetPlayer : set when the target is a player; nil for NPCs / test dummies.
-- targetModel  : the character Model (may be nil for a player with no character).
-- attacker     : the responsible player, or nil for environment / hazard damage.
-- sourceName   : weapon or hazard identifier for logs / kill feed ("" if unknown).
-- region       : resolved hit region; "Unknown" when hitPart is nil.
-- hitPart      : the exact BasePart the server raycast returned, or nil.
-- hitPosition  : world-space hit point (server raycast result).
-- hitDirection : normalized travel direction of the shot at impact.
-- baseAmount   : pre-multiplier damage from the weapon definition.
-- finalAmount  : baseAmount × region multiplier, clamped (filled in by DamageService).
export type DamageInfo = {
    targetPlayer : Player?,
    targetModel  : Model?,
    attacker     : Player?,
    sourceName   : string,
    damageType   : DamageType,
    region       : HitRegion,
    hitPart      : BasePart?,
    hitPosition  : Vector3?,
    hitDirection : Vector3?,
    baseAmount   : number,
    finalAmount  : number,
}

-- What a caller passes to DamageService:ApplyDamage. Same shape as DamageInfo but with
-- the fields DamageService fills in itself left optional: `region` (derived from hitPart
-- when omitted), `finalAmount` (always computed), and the string/enum defaults.
export type DamageRequest = {
    targetPlayer : Player?,
    targetModel  : Model?,
    attacker     : Player?,
    sourceName   : string?,
    damageType   : DamageType?,
    region       : HitRegion?,
    hitPart      : BasePart?,
    hitPosition  : Vector3?,
    hitDirection : Vector3?,
    baseAmount   : number,
}

-- ModuleScripts must return a table, even if it only contains type exports.
return {}
