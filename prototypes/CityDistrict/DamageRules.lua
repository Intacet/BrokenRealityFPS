--!strict
-- Pure validation used by the server service and offline tests.
local Rules = {}

function Rules.IsFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

function Rules.NextHealth(health: number, damage: number, maxDamage: number): number?
    if not Rules.IsFinite(health) or not Rules.IsFinite(damage)
        or not Rules.IsFinite(maxDamage) or health <= 0 or damage <= 0 or maxDamage <= 0 then
        return nil
    end
    return math.max(0, health - math.min(damage, maxDamage))
end

return table.freeze(Rules)
