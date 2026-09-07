--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > Ballistics
--
-- Virtual projectile ballistics math library. Pure data/math only.
-- No Instances created. No raycasts. No RunService references.
-- Safe to require from both client and server.
--
-- Typical usage (future — when PROJECTILE_BALLISTICS_ENABLED = true):
--   local cfg      = Ballistics.GetConfig(WeaponData["AKS74"])
--   local gravity  = Ballistics.ComputeGravity(cfg)
--   local velocity = Ballistics.ComputeInitialVelocity(origin, direction, cfg)
--   while not Ballistics.ShouldExpire(origin, pos, age, cfg) do
--       pos, velocity = Ballistics.Step(pos, velocity, dt, gravity)
--       -- perform segment raycast here (not in this module)
--   end
--
-- PROJECTILE_BALLISTICS_ENABLED (Constants) is not read here.
-- Callers gate on that constant so this module remains side-effect free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

-- ============================================================
-- Exported type
-- ============================================================

export type BallisticsConfig = {
    mode              : string,
    muzzleVelocity    : number,
    gravityMultiplier : number,
    maxDistance       : number,
    maxLifetime       : number,
    simulationStep    : number,
    maxStepDistance   : number,
}

-- ============================================================
-- Module table
-- ============================================================

local Ballistics = {}

-- ============================================================
-- GetConfig
-- ============================================================
-- Normalises a weapon definition's ballistics sub-table into a BallisticsConfig.
-- Any field absent from weaponDef.ballistics falls back to the matching
-- PROJECTILE_DEFAULT_* constant. Logs each fallback at debug level when
-- PROJECTILE_BALLISTICS_DEBUG = true.
function Ballistics.GetConfig(weaponDef: any): BallisticsConfig
    assert(typeof(weaponDef) == "table",
        "[Ballistics] GetConfig: weaponDef must be a table")

    local raw: any = nil
    if typeof(weaponDef.ballistics) == "table" then
        raw = weaponDef.ballistics
    end

    local debugOn: boolean = Constants.PROJECTILE_BALLISTICS_DEBUG == true

    local function pickStr(field: string, default_: string): string
        local val: any = if raw ~= nil then raw[field] else nil
        if val ~= nil then
            return val :: string
        end
        if debugOn then
            Logger.debug("[Ballistics] GetConfig:", field, "missing — using default", default_)
        end
        return default_
    end

    local function pickNum(field: string, default_: number): number
        local val: any = if raw ~= nil then raw[field] else nil
        if val ~= nil then
            return val :: number
        end
        if debugOn then
            Logger.debug("[Ballistics] GetConfig:", field, "missing — using default", tostring(default_))
        end
        return default_
    end

    return {
        mode              = pickStr("mode",             "Hitscan"),
        muzzleVelocity    = pickNum("muzzleVelocity",    Constants.PROJECTILE_DEFAULT_MUZZLE_VELOCITY    :: number),
        gravityMultiplier = pickNum("gravityMultiplier",  Constants.PROJECTILE_DEFAULT_GRAVITY_MULTIPLIER  :: number),
        maxDistance       = pickNum("maxDistance",        Constants.PROJECTILE_DEFAULT_MAX_DISTANCE        :: number),
        maxLifetime       = pickNum("maxLifetime",        Constants.PROJECTILE_DEFAULT_MAX_LIFETIME        :: number),
        simulationStep    = pickNum("simulationStep",     Constants.PROJECTILE_DEFAULT_SIMULATION_STEP     :: number),
        maxStepDistance   = pickNum("maxStepDistance",    Constants.PROJECTILE_DEFAULT_MAX_STEP_DISTANCE   :: number),
    }
end

-- ============================================================
-- ComputeInitialVelocity
-- ============================================================
-- Returns the projectile's starting velocity vector (studs/s).
-- direction is normalised to a unit vector before scaling by muzzleVelocity,
-- so callers may pass a raw shot direction without pre-normalising.
function Ballistics.ComputeInitialVelocity(
    origin   : Vector3,
    direction: Vector3,
    config   : BallisticsConfig
): Vector3
    assert(typeof(origin)    == "Vector3",
        "[Ballistics] ComputeInitialVelocity: origin must be Vector3")
    assert(typeof(direction) == "Vector3",
        "[Ballistics] ComputeInitialVelocity: direction must be Vector3")
    return direction.Unit * config.muzzleVelocity
end

-- ============================================================
-- ComputeGravity
-- ============================================================
-- Returns the downward acceleration vector (studs/s²) for this config.
-- gravityMultiplier 0.0 → Vector3.zero (no bullet drop).
-- gravityMultiplier 1.0 → full workspace.Gravity downward (≈ 196.2 studs/s²).
function Ballistics.ComputeGravity(config: BallisticsConfig): Vector3
    return Vector3.new(0, -workspace.Gravity * config.gravityMultiplier, 0)
end

-- ============================================================
-- Step
-- ============================================================
-- Advances a virtual projectile by dt seconds using semi-implicit Euler
-- integration (velocity updated before position for better energy conservation).
-- Returns (newPosition, newVelocity).
-- Does NOT perform a raycast — the caller is responsible for segment detection.
function Ballistics.Step(
    position: Vector3,
    velocity: Vector3,
    dt      : number,
    gravity : Vector3
): (Vector3, Vector3)
    assert(typeof(position) == "Vector3",
        "[Ballistics] Step: position must be Vector3")
    assert(typeof(velocity) == "Vector3",
        "[Ballistics] Step: velocity must be Vector3")
    assert(typeof(dt) == "number",
        "[Ballistics] Step: dt must be number")

    local newVelocity: Vector3 = velocity + gravity * dt
    local newPosition: Vector3 = position + newVelocity * dt
    return newPosition, newVelocity
end

-- ============================================================
-- ShouldExpire
-- ============================================================
-- Returns true when the projectile should be discarded:
--   • age exceeds config.maxLifetime, OR
--   • distance from origin exceeds config.maxDistance
function Ballistics.ShouldExpire(
    origin  : Vector3,
    position: Vector3,
    age     : number,
    config  : BallisticsConfig
): boolean
    assert(typeof(origin)   == "Vector3",
        "[Ballistics] ShouldExpire: origin must be Vector3")
    assert(typeof(position) == "Vector3",
        "[Ballistics] ShouldExpire: position must be Vector3")
    assert(typeof(age) == "number",
        "[Ballistics] ShouldExpire: age must be number")

    if age > config.maxLifetime then
        return true
    end
    if (position - origin).Magnitude > config.maxDistance then
        return true
    end
    return false
end

return Ballistics
