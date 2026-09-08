--!strict
-- Server-only tuning for the isolated city destruction prototype.
return table.freeze({
    RootName = "BR_CityDistrict",
    DebrisFolderName = "BR_CityDebris",
    ProfileAttribute = "BR_BreakableProfile",
    HealthAttribute = "BR_Health",
    BrokenAttribute = "BR_Broken",
    MaxRegisteredParts = 400,
    MaxDamagePerHit = 100,
    ImpactTolerance = 1.5,
    MaxLiveFragments = 48,
    FragmentsPerBreak = 3,
    FragmentLifetime = 2.5,
    FragmentScale = 0.22,
    FragmentMinSize = 0.15,
    FragmentMaxSize = 2,
    FragmentSpeed = 12,
    FragmentLift = 6,
    FragmentSpin = 4,
    MinDirectionMagnitude = 0.001,
    Profiles = table.freeze({
        Glass = table.freeze({ Health = 20 }),
        Timber = table.freeze({ Health = 80 }),
        LightCover = table.freeze({ Health = 140 }),
    }),
})
