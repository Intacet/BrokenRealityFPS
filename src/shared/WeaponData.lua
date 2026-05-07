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
WeaponData["AssaultRifle"] = {
    damage       = 25,
    fireRate     = 0.1,
    range        = 300,
    magazineSize = 30,
    reserveAmmo  = 90,
}

return WeaponData
