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

return WeaponData
