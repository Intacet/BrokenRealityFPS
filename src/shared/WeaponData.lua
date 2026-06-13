--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > WeaponData
--
-- All weapon definitions. Add a new entry here to add a new weapon.
-- GunService reads damage and fireRate. GunController reads fireRate for
-- client-side shot pacing (cosmetic only — the server re-validates).
-- Do not put weapon logic here — only data.

local WeaponData = {}

-- damage        — hit points removed per shot (read by DamageService via GunService)
-- fireRate      — minimum seconds between shots; enforced server-side as a rate limit
-- range         — maximum raycast distance in studs; shots beyond this are ignored
-- magazineSize  — rounds per magazine; server rejects WeaponFired when magazine is empty
-- reserveAmmo   — total spare rounds the player starts each round with
WeaponData["SCAR"] = {
    damage       = 30,
    fireRate     = 0.1,
    range        = 400,
    magazineSize = 20,
    reserveAmmo  = 100,
}

-- AR15 — the active first-person viewmodel weapon (viewmodel asset in ReplicatedStorage/ViewModels/AR15).
-- reloadTime is stored here for future use; GunService does not yet read it (see DEBT-013 / DEBT-030).
WeaponData["AR15"] = {
    damage       = 28,
    fireRate     = 0.09,
    range        = 450,
    magazineSize = 30,
    reserveAmmo  = 120,
    reloadTime   = 2.2,
}

-- AKS74 — full-auto 650 RPM viewmodel weapon (2026-06-13 recoil retune).
-- displayName / viewModelName / animations are read by ViewModelController only.
-- fireMode / rpm / fireRate are read by GunController for client-side pacing.
-- damage / range / magazineSize / reserveAmmo / reloadTime are stored for future GunService use.
-- GunService continues to use Constants.DEFAULT_WEAPON ("AR15") for all server validation.
-- See DEBT-013 and DEBT-059.  Third-person animation IDs stored for future use.
WeaponData["AKS74"] = {
    displayName   = "AKS-74",
    viewModelName = "AKS74",
    worldModelName = "AKS-74",  -- gun-only model in ReplicatedStorage/WorldModels/AKS-74
    fireMode      = "Auto",
    rpm           = 650,
    fireRate      = 60 / 650,   -- ~0.0923 s per shot; derived from rpm, not hardcoded
    damage        = 30,
    range         = 450,
    magazineSize  = 30,
    reserveAmmo   = 120,
    reloadTime    = 2.2,
    recoil = {
        -- Viewmodel gun kick applied via ViewModelController:ApplyRecoil() (vmRecoilCF path).
        -- Sign convention (Studio-verified 2026-06-13):
        --   positionBack > 0 → +Z camera-local → weapon moves toward player (backward kick). ✓
        --   positionUp   > 0 → +Y camera-local → weapon lifts upward.                        ✓
        --   pitchDegrees > 0 → CFrame.Angles(pitch,...) → muzzle rises.                      ✓
        hip = {
            positionBack = 0.052,   -- weapon moves toward camera each shot
            positionUp   = 0.008,
            pitchDegrees = 1.15,    -- muzzle rise per shot in viewmodel space
            yawDegrees   = 0.12,
            rollDegrees  = 0.16,
        },
        ads = {
            positionBack = 0.020,   -- ~38% of hip: noticeably tighter while aiming
            positionUp   = 0.003,
            pitchDegrees = 0.38,
            yawDegrees   = 0.035,
            rollDegrees  = 0.045,
        },
        -- Camera-space screen kick (viewRecoilCFrame — shifts entire viewmodel up/right).
        -- Distinct from the gun-kick above; both paths run independently without fighting.
        camera = {
            hip = { kickUp = 0.45, kickRight = 0.06 },  -- degrees per shot, hip fire
            ads = { kickUp = 0.16, kickRight = 0.02 },  -- reduced while ADS
        },
        buildupPerShot  = 0.065,  -- buildup scalar added per shot [0, maxBuildup]
        maxBuildup      = 0.46,   -- caps vmRecoilBuildup; pitch reaches 1.46× base at max
        recoverySpeed   = 22,     -- ~91.8% recovery between shots at 650 RPM (was 8 = 42%)
        kickSpeed       = 44,     -- vmRecoilCurrent chase speed (fast snap feel)
        randomYawScale  = 0.55,
        randomRollScale = 0.45,
        alternatingYaw  = true,
    },
    -- Ballistics data — read by Ballistics.GetConfig(); not yet read by GunService or DamageService.
    -- mode = "Projectile" declares intent; hitscan gameplay is unchanged while
    -- PROJECTILE_BALLISTICS_ENABLED = false. See DEBT-079.
    ballistics = {
        mode              = "Projectile",
        muzzleVelocity    = 2800,                  -- studs/s (AKS74 spec ≈ 880 m/s)
        gravityMultiplier = 0.0,                   -- no drop yet; set to 1.0 when bullet drop is enabled
        maxDistance       = 900,                   -- studs; matches WeaponData.range upper bound
        maxLifetime       = 1.25,                  -- seconds
        simulationStep    = 0.008333333333333333,  -- ≈ 120 Hz sub-step
        maxStepDistance   = 55,                    -- studs per sub-step cap
    },
    animations = {
        firstPerson = {
            equip    = "rbxassetid://139265999638776",
            idle     = "rbxassetid://75961893882956",
            fire     = "rbxassetid://116185608269786",
            reload   = "rbxassetid://84867185321281",
            walk     = "rbxassetid://125395339753686",   -- FP walk loop
            enterRun = "rbxassetid://131163456590831",   -- FP enter-run one-shot (Walk/Idle → Run)
            run      = "rbxassetid://73261579857067",    -- FP run loop (replaces old: 111133092181267)
            sprint   = "rbxassetid://126248731863931",   -- FP sprint loop
            adsIn    = "rbxassetid://112260183627854",   -- ADS enter animation
            adsOut   = "rbxassetid://108479441252268",   -- ADS exit animation
            adsIdle  = "rbxassetid://105305883052870",   -- ADS idle loop
            adsFire  = "rbxassetid://138021695403324",   -- fire while ADS
        },
        thirdPerson = {
            equip  = "rbxassetid://124808012153849",
            idle   = "rbxassetid://79290751562233",
            fire   = "rbxassetid://101346298541907",
            reload = "rbxassetid://82861605710102",
        },
    },
    sounds = {
        fireFirstPerson = {
            "rbxassetid://116842061471256",  -- ak2
        },
    },
}

return WeaponData
