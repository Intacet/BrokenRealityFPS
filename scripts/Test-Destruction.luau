--!strict
-- Offline regression tests for DestructionService's per-hit logic (ApplyHit/Reset/Destroy).
-- Real @lune/roblox Vector3/CFrame/Instance datatypes are used for accurate math against a
-- synthetic Part fixture; the module's top-level workspace scan and Heartbeat/PhaseChanged
-- wiring are intentionally NOT executed here (they need a real workspace/RunService/
-- MatchEvents) — the same scope boundary scripts/Test-Reload.luau already draws around its
-- one extracted method. Assertions mirror prototypes/CityDistrict/TestDestruction.luau,
-- which this module's ApplyHit/Reset logic was ported from.
local fs   = require('@lune/fs')
local rb   = require('@lune/roblox')
local luau = require('@lune/luau')
local root = 'outputs/BrokenReality/'

local Constants = luau.load(fs.readFile(root .. 'src/ReplicatedStorage/Modules/Constants.lua'))()
local Rules     = luau.load(fs.readFile(root .. 'src/ServerScriptService/Services/DestructionRules.lua'))()
local woodHealth        = (Constants.DESTRUCTION_PROFILES :: any).Wood.Health :: number
local fragmentsPerBreak = Constants.DESTRUCTION_FRAGMENTS_PER_BREAK :: number
local maxLiveFragments  = Constants.DESTRUCTION_MAX_LIVE_FRAGMENTS :: number

-- Extraction starts AFTER "local DestructionService = {}" (not included) so that name
-- becomes a free variable resolved through the injected environment below, exactly like
-- `states`/`fragments`/etc. — the fixture pre-creates the table and reads it back by that
-- same reference afterward, rather than relying on the chunk's (absent, out of range)
-- final `return DestructionService` statement.
local source = fs.readFile(root .. 'src/ServerScriptService/Services/DestructionService.lua')
local first = assert(string.find(source, 'local function clearFragment', 1, true))
local last  = assert(string.find(source, 'local registered = 0', first, true))
local method = string.sub(source, first, last - 1)

local function makePart(name: string)
    local part = rb.Instance.new('Part')
    part.Name = name
    part.Size = rb.Vector3.new(4, 7, 0.5)
    part.CFrame = rb.CFrame.new(10, 5, 10)
    part.Anchored = true
    return part
end

-- Snapshot matching what the excluded registration loop would have recorded for this part.
local function registeredState(part)
    return { health = woodHealth, maxHealth = woodHealth, transparency = part.Transparency,
        collide = part.CanCollide, query = part.CanQuery, touch = part.CanTouch }
end

-- Plain-value free variables (stopped, fragmentCount) reassigned inside the loaded chunk
-- are not safe to read back via env.X from the outside — same reasoning Test-Reload.luau
-- documents for isReloading. Instead, append a getter attached to the returned table
-- itself (a real shared object), read from inside the same closure scope, mirroring
-- Test-Reload.luau's `function ViewModelController.readState() return isReloading end`.
-- Table-valued free variables (states, fragments, connections) are safe to read directly
-- via env.X: assigning env's entries into the chunk's scope copies the table *reference*,
-- so mutations to their contents are visible on the same object from either side.
local methodWithTestHooks = method
    .. '\nfunction DestructionService.__test_stopped() return stopped end'

-- Counts live debris by reading the (safe, table-valued) env.fragments directly, rather
-- than trusting env.fragmentCount — that seed is only for the chunk's own internal
-- arithmetic and, being a plain number reassigned by +=/-=, is not reliable to read back.
local function countFragments(env): number
    local n = 0
    for _ in env.fragments do n += 1 end
    return n
end

local function fixture()
    local partDestroyedCalls = 0
    local target = makePart('TestDoorPanel')
    local env = {
        DestructionService = {},  -- pre-created; the chunk populates it in place via `:` defs
        states = { [target] = registeredState(target) },
        fragments = {}, fragmentCount = 0, connections = {}, stopped = false,
        debrisFolder = rb.Instance.new('Folder'),
        Constants = Constants, Rules = Rules,
        Instance = rb.Instance, Vector3 = rb.Vector3,
        os = { clock = function() return 0 end },
        Logger = { debug = function() end, warn = function() end },
        PartDestroyed = { FireAllClients = function() partDestroyedCalls += 1 end },
    }
    luau.load(methodWithTestHooks, { environment = env })()
    return env.DestructionService, env, target, function() return partDestroyedCalls end
end

local checks = 0
local function check(value: any, message: string) assert(value, message); checks += 1 end

do
    local service, env, target, destroyedCalls = fixture()
    local at  = target.CFrame.Position
    local dir = rb.Vector3.new(1, 0, 0)
    local other = makePart('Unregistered')

    check(not service:ApplyHit(other, 20, at, dir), 'Reject unregistered part')
    check(not service:ApplyHit(target, 0 / 0, at, dir), 'Reject NaN damage')
    check(not service:ApplyHit(target, math.huge, at, dir), 'Reject infinite damage')
    check(not service:ApplyHit(target, -20, at, dir), 'Reject negative damage')
    check(not service:ApplyHit(target, 20, at + rb.Vector3.new(100, 0, 0), dir), 'Reject remote impact point')
    check(env.states[target].health == woodHealth, 'Invalid hits leave health unchanged')

    check(service:ApplyHit(target, 10, at, dir), 'Valid partial damage accepted')
    check(env.states[target].health == woodHealth - 10, 'Partial damage accumulates')
    check(target:GetAttribute('BR_Health') == woodHealth - 10, 'Health attribute mirrors state')

    check(service:ApplyHit(target, 1000, at, dir), 'Break target (damage clamped, still lethal)')
    check(target:GetAttribute('BR_Broken') == true, 'Broken attribute set')
    check(not target.CanCollide and not target.CanQuery and not target.CanTouch,
        'Broken part is non-collidable/non-queryable/non-touchable')
    check(target.Transparency == 1, 'Broken part is invisible')
    check(destroyedCalls() == 1, 'PartDestroyed remote fired once on break')

    local debrisCount = countFragments(env)
    check(debrisCount > 0 and debrisCount <= fragmentsPerBreak, 'Debris scattered within per-break cap')

    check(not service:ApplyHit(target, 20, at, dir), 'Reject duplicate break')
    check(countFragments(env) == debrisCount, 'Duplicate hit creates no additional debris')
    check(destroyedCalls() == 1, 'PartDestroyed does not re-fire on duplicate break')
end

do
    -- Global fragment cap holds even when far more parts break than the cap alone allows.
    local service, env = fixture()
    local needed = math.ceil(maxLiveFragments / fragmentsPerBreak) + 2
    for i = 1, needed do
        local p = makePart('Wood' .. i)
        env.states[p] = registeredState(p)
        service:ApplyHit(p, 1000, p.CFrame.Position, rb.Vector3.new(0, 1, 0))
    end
    check(countFragments(env) <= maxLiveFragments, 'Global debris cap holds across many breaks')
end

do
    local service, env, target = fixture()
    local at = target.CFrame.Position
    service:ApplyHit(target, 1000, at, rb.Vector3.new(0, 1, 0))
    check(countFragments(env) > 0, 'Debris exists before reset')

    service:Reset()
    check(env.states[target].health == woodHealth, 'Reset restores health')
    check(target:GetAttribute('BR_Health') == woodHealth, 'Reset restores health attribute')
    check(target:GetAttribute('BR_Broken') == false, 'Reset clears broken attribute')
    check(target.CanQuery and target.CanCollide and target.CanTouch, 'Reset restores collision flags')
    check(target.Transparency == 0, 'Reset restores original (0) transparency')
    check(countFragments(env) == 0, 'Reset clears live debris')

    check(service:ApplyHit(target, 10, at, rb.Vector3.new(0, 1, 0)), 'Part is breakable again after reset')
end

do
    local service, env, target = fixture()
    service:ApplyHit(target, 1000, target.CFrame.Position, rb.Vector3.new(1, 0, 0))
    service:Destroy()
    check(service.__test_stopped(), 'Destroy sets stopped')
    check(not service:ApplyHit(target, 20, target.CFrame.Position, rb.Vector3.new(1, 0, 0)),
        'Destroyed service rejects further hits')
end

check(Rules.NextHealth(140, 1000, 100) == 40, 'Damage clamp: a single hit cannot exceed MAX_DAMAGE_PER_HIT')
check(Rules.NextHealth(woodHealth, woodHealth, 100) == 0, 'Exact lethal damage reaches exactly zero, not negative')
check(Rules.NextHealth(0, 10, 100) == nil, 'Hitting an already-zero-health part is rejected, not re-processed')

luau.compile(source)
luau.compile(fs.readFile(root .. 'src/ServerScriptService/Services/DestructionRules.lua'))
luau.compile(fs.readFile(root .. 'src/ReplicatedStorage/Modules/Constants.lua'))

return checks
