--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > WeaponFeel
--
-- Per-weapon gunplay feel parameters. Consumed by GunController for recoil,
-- spread, and timing; values here are designer-tunable without touching controller code.
--
-- All angle values are in degrees. Spread values are half-cone angles.
-- recoilBuildup accumulates per shot and decays after recoilResetTime seconds of
-- not firing — it pushes recoilUp/Right higher as the player holds the trigger.

local WeaponFeel = {}

WeaponFeel["SCAR"] = {
    -- ── Recoil ───────────────────────────────────────────────────────────────
    recoilUp             = 1.8,   -- degrees of upward kick per shot on the viewmodel
    recoilRight          = 0.4,   -- degrees of rightward kick per shot
    recoilRightAlternate = true,  -- alternate right/left each shot for natural spread
    recoilRecoverySpeed  = 8,     -- lerp factor (per second) returning recoil to zero
    recoilBuildup        = 0.15,  -- added to recoil multiplier each shot while holding
    recoilBuildupMax     = 2.5,   -- maximum recoil multiplier from buildup
    recoilResetTime      = 0.3,   -- seconds after last shot before buildup resets to zero

    -- ── Spread ───────────────────────────────────────────────────────────────
    baseSpread           = 0.4,   -- minimum half-cone spread in degrees (ADS, still)
    hipfireSpread        = 3.2,   -- additional degrees added when not aiming down sights
    movingSpreadAdd      = 2.0,   -- additional degrees when velocity > walk threshold
    sprintingSpreadAdd   = 5.0,   -- additional degrees when in sprint state
    crouchSpreadMult     = 0.6,   -- multiplier applied to total spread when crouching

    -- ── ADS ──────────────────────────────────────────────────────────────────
    adsTime              = 0.22,  -- seconds to reach full ADS (visual only; DEBT-040)

    -- ── Timing ───────────────────────────────────────────────────────────────
    fireRate             = 0.09,  -- minimum seconds between shots (must match WeaponData)

    -- ── Visual ───────────────────────────────────────────────────────────────
    muzzleFlashDuration  = 0.04,  -- seconds the muzzle flash part is visible
    shellEjectEnabled    = false, -- shell casing ejection VFX (unimplemented; DEBT-041)
}

-- AR15 mirrors SCAR until a weapon-specific tuning pass is done.
-- When AR15 gets its own values, replace this reference with a separate table.
-- See DEBT-032.
WeaponFeel["AR15"] = WeaponFeel["SCAR"]

return WeaponFeel
