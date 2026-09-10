--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > CombatEvents
--
-- Holds BindableEvents for server-to-server communication about damage and death.
--
-- WHY THIS EXISTS:
-- Same reason as MatchEvents — a server Script cannot listen to a RemoteEvent fired by
-- another server Script. RemoteEvents are server<->client only; BindableEvents are the
-- server-side signal bus.
--
-- WHY IT IS SEPARATE FROM MatchEvents:
-- MatchEvents is scoped to match-loop state (phase, teams, round end). Damage and death
-- of arbitrary entities (players, test dummies, future NPCs) is a different concern with a
-- different, wider set of listeners, so it gets its own module.
--
-- DamageService is the ONLY producer. Nothing else fires these.

local CombatEvents = {}

-- Fired by DamageService after every accepted, non-zero hit is applied — including hits
-- that leave the target alive, and hits on an entity flagged BR_InfiniteHealth (where no
-- health was actually removed but the event still describes the impact).
-- Payload: (targetModel: Model?, info: Types.DamageInfo)
--   targetModel may be nil only for a player damaged while they have no character.
--   info.finalAmount is the post-multiplier, post-clamp value that was applied.
-- Current listeners: DummyService (last-hit / limb tracking)
-- Future listeners:  BloodService (Stage 4), HitReactionService (Stage 5), GoreService
CombatEvents.DamageDealt = Instance.new("BindableEvent")

-- Fired by DamageService when an accepted hit brings an entity's Humanoid to 0 health.
-- Fires for players too (after the existing killPlayer path has run) so future consumers
-- get one consistent death signal — but the player ragdoll is still driven directly by
-- DamageService.killPlayer, NOT by this event.
-- Payload: (targetModel: Model?, info: Types.DamageInfo)
-- Current listeners: DummyService (ragdoll + respawn)
-- Future listeners:  GoreService, RewardService, CorpseService
CombatEvents.EntityKilled = Instance.new("BindableEvent")

return CombatEvents
