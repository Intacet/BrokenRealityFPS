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

-- AKS74 — full-auto 550 RPM viewmodel weapon (2026-06-10).
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
    rpm           = 550,
    fireRate      = 60 / 550,   -- ~0.1091 s per shot; derived from rpm, not hardcoded
    damage        = 30,
    range         = 450,
    magazineSize  = 30,
    reserveAmmo   = 120,
    reloadTime    = 2.2,
    recoil = {
        hip = {
            positionBack = 0.045,   -- weapon moves toward camera each shot
            positionUp   = 0.006,   -- weapon lifts slightly
            pitchDegrees = 1.2,     -- positive = muzzle rises; pending Studio verification
            yawDegrees   = 0.12,
            rollDegrees  = 0.18,
        },
        ads = {
            positionBack = 0.018,
            positionUp   = 0.002,
            pitchDegrees = 0.45,
            yawDegrees   = 0.04,
            rollDegrees  = 0.06,
        },
        buildupPerShot  = 0.055,  -- buildup scalar added per shot [0, maxBuildup]
        maxBuildup      = 0.42,   -- caps vmRecoilBuildup; pitch scales by (1 + buildup)
        recoverySpeed   = 24,     -- lerp rate for vmRecoilTarget decay to identity
        kickSpeed       = 42,     -- lerp rate for vmRecoilCurrent chasing vmRecoilTarget
        randomYawScale  = 0.6,    -- ±variation on yaw per shot (0 = deterministic)
        randomRollScale = 0.5,
        alternatingYaw  = true,   -- flip yaw direction each shot (left-right-left...)
    },
    animations = {
        firstPerson = {
            equip   = "rbxassetid://139265999638776",
            idle    = "rbxassetid://75961893882956",
            fire    = "rbxassetid://116185608269786",
            reload  = "rbxassetid://84867185321281",
            run     = "rbxassetid://111133092181267",
            adsIn   = "rbxassetid://112260183627854",   -- ADS enter animation (new)
            adsOut  = "rbxassetid://108479441252268",   -- ADS exit animation (new)
            adsIdle = "rbxassetid://105305883052870",   -- ADS idle loop (new - replaces fake freeze)
            adsFire = "rbxassetid://138021695403324",   -- fire while ADS (preserved)
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
