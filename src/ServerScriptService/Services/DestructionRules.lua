--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > DestructionRules
--
-- Pure validation used by DestructionService and its offline tests. No Instance access,
-- no side effects, no randomness — every function is a plain value-in, value-out check.
-- Mirrors prototypes/CityDistrict/DamageRules.lua, which this logic was ported from.

local DestructionRules = {}

function DestructionRules.IsFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

-- Returns the health remaining after `damage` (clamped to `maxDamage`) is subtracted from
-- `health`, floored at 0. Returns nil for any non-finite or non-positive input — callers
-- must treat nil as "reject the hit", not as zero damage.
function DestructionRules.NextHealth(health: number, damage: number, maxDamage: number): number?
    if not DestructionRules.IsFinite(health) or not DestructionRules.IsFinite(damage)
        or not DestructionRules.IsFinite(maxDamage) or health <= 0 or damage <= 0 or maxDamage <= 0 then
        return nil
    end
    return math.max(0, health - math.min(damage, maxDamage))
end

return table.freeze(DestructionRules)
