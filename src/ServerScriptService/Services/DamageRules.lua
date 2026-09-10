--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > DamageRules
--
-- Pure damage math used by DamageService. No Instance access, no side effects, no
-- randomness — every function is value-in, value-out. Mirrors the DestructionRules split:
-- DamageService does the Instance work, DamageRules does the arithmetic and the lookups,
-- so both can be reasoned about (and later unit-tested) in isolation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Types     = require(Modules:WaitForChild("Types"))

local DamageRules = {}

function DamageRules.IsFinite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end

function DamageRules.IsFiniteVector(value: Vector3): boolean
    return DamageRules.IsFinite(value.X) and DamageRules.IsFinite(value.Y) and DamageRules.IsFinite(value.Z)
end

-- Maps an R6 BasePart name to a HitRegion via Constants.R6_PART_REGIONS.
-- Anything unrecognised (accessories, tools, non-standard rigs) resolves to Unknown,
-- which carries a ×1 multiplier — an unknown part never amplifies or reduces damage.
function DamageRules.RegionForPart(partName: string?): Types.HitRegion
    if partName == nil then
        return Constants.HitRegion.Unknown :: Types.HitRegion
    end
    local region = (Constants.R6_PART_REGIONS :: { [string]: string })[partName]
    return (region or Constants.HitRegion.Unknown) :: Types.HitRegion
end

-- Region multiplier from Constants.DAMAGE_REGION_MULTIPLIERS, defaulting to 1.0 for any
-- region without an entry so a missing tuning value can never zero out damage.
function DamageRules.MultiplierForRegion(region: Types.HitRegion): number
    local mult = (Constants.DAMAGE_REGION_MULTIPLIERS :: { [string]: number })[region]
    if mult == nil or not DamageRules.IsFinite(mult) or mult < 0 then
        return 1.0
    end
    return mult
end

-- Final damage for one hit: base × region multiplier, floored at 0 and clamped to
-- Constants.DAMAGE_MAX_PER_HIT. Returns nil for a non-finite or non-positive base — the
-- caller must treat nil as "reject this hit", exactly like DestructionRules.NextHealth.
function DamageRules.ComputeFinalDamage(baseAmount: number, region: Types.HitRegion): number?
    if not DamageRules.IsFinite(baseAmount) or baseAmount <= 0 then
        return nil
    end
    local maxPerHit = Constants.DAMAGE_MAX_PER_HIT :: number
    local scaled = baseAmount * DamageRules.MultiplierForRegion(region)
    if not DamageRules.IsFinite(scaled) or scaled <= 0 then
        return nil
    end
    return math.min(scaled, maxPerHit)
end

return table.freeze(DamageRules)
