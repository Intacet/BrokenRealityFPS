--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > FootstepData
--
-- Sound asset IDs for footstep variants, keyed by surface material and movement tier.
-- FootstepController indexes this as: FootstepData[surface][movementTier] → { string }
--
-- Stage 1: Concrete surface only, one ID per tier (single asset rbxassetid://118809277654750).
-- FootstepController already handles single-element tables correctly via math.random(1, #ids).
-- Future: add more surfaces (Metal, Grass, Gravel, Wood, Tile) as IDs are sourced.
-- Do not hardcode these IDs in FootstepController.

local FootstepData: { [string]: { [string]: { string } } } = {
    Concrete = {
        Walk = {
            "rbxassetid://118809277654750",
        },
        Run = {
            "rbxassetid://118809277654750",
        },
        Sprint = {
            "rbxassetid://118809277654750",
        },
        Crouch = {
            "rbxassetid://118809277654750",
        },
    },
    -- TODO Stage 2: add Metal, Grass, Gravel, Wood, Tile surfaces.
}

return FootstepData
