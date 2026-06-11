--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > FootstepData
--
-- Sound asset IDs for footstep variants, keyed by surface material and movement tier.
-- FootstepController indexes this as: FootstepData[surface][movementTier] → { string }
--
-- Stage 1: Concrete surface only, one ID per tier (single asset rbxassetid://92132964739718).
-- FootstepController already handles single-element tables correctly via math.random(1, #ids).
-- Future: add more surfaces (Metal, Grass, Gravel, Wood, Tile) as IDs are sourced.
-- Do not hardcode these IDs in FootstepController.

local FootstepData: { [string]: { [string]: { string } } } = {
    Concrete = {
        Walk = {
            "rbxassetid://92132964739718",
        },
        Run = {
            "rbxassetid://92132964739718",
        },
        Sprint = {
            "rbxassetid://92132964739718",
        },
        Crouch = {
            "rbxassetid://92132964739718",
        },
    },
    -- TODO Stage 2: add Metal, Grass, Gravel, Wood, Tile surfaces.
}

return FootstepData
