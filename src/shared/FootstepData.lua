--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > FootstepData
--
-- Sound asset IDs for footstep variants, keyed by surface material and movement tier.
-- FootstepController indexes this as: FootstepData[surface][movementTier] → { string }
--
-- Stage 1: Concrete surface only, two variants per tier.
-- Future: add more surfaces (Metal, Grass, Gravel, Wood, Tile) as IDs are sourced.
-- Do not hardcode these IDs in FootstepController.

local FootstepData: { [string]: { [string]: { string } } } = {
    Concrete = {
        Walk = {
            "rbxassetid://122170062498802",
            "rbxassetid://100192350816880",
        },
        Run = {
            "rbxassetid://122170062498802",
            "rbxassetid://100192350816880",
        },
        Sprint = {
            "rbxassetid://122170062498802",
            "rbxassetid://100192350816880",
        },
        Crouch = {
            "rbxassetid://122170062498802",
            "rbxassetid://100192350816880",
        },
    },
    -- TODO Stage 2: add Metal, Grass, Gravel, Wood, Tile surfaces.
}

return FootstepData
