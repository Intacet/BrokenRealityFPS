--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > DestructionService
--
-- Owns server-side destructible wood props: doors, crates, fences, planks — any part
-- Studio tags with Constants.BREAKABLE_PROFILE_ATTRIBUTE. Bullet-driven only; explosive/AoE
-- damage is an explicitly deferred future pass — see docs/DESTRUCTION_SYSTEM_PLAN.md.
--
-- Any Anchored BasePart anywhere in workspace carrying that attribute (a string naming a
-- key in Constants.DESTRUCTION_PROFILES) is registered once at server start. GunService
-- calls Service:ApplyHit() with its own already-validated raycast result, for any shot that
-- did not hit a player — see the "── Destruction ──" block in GunService.server.lua.
-- No new remotes: this only consumes the raycast GunService already computed from the
-- existing WeaponFired flow. No client ever supplies damage, a target, or a break result.
--
-- Doors break the way Rainbow Six Siege doors do: a door is not one BasePart, it is several
-- (e.g. left panel / right panel / frame), each independently tagged and health-tracked, so
-- shooting one panel breaks only that panel. This module has no "door" concept at all — that
-- behavior falls out for free once a door is authored in Studio as multiple tagged pieces
-- instead of one part. Ported from, and functionally equivalent to, the already offline-
-- tested prototypes/CityDistrict/DestructionService.lua, retargeted from one isolated test
-- subtree to the whole live workspace and from its "Timber" profile to "Wood".
--
-- What this script does NOT do:
--   - Decide whether a shot is valid           →  GunService (raycast, phase, ammo, rate)
--   - Explosive/AoE damage                     →  future pass, see docs/DESTRUCTION_SYSTEM_PLAN.md
--   - Client-side break VFX                    →  fires the existing PartDestroyed remote as
--                                                   a hook only; no client currently listens
--   - Register parts added to workspace later   →  known limitation, see DESTRUCTION_SYSTEM_PLAN.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
assert(RunService:IsServer(), "[DestructionService] server-only module")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Rules       = require(script.Parent:WaitForChild("DestructionRules"))
local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local PartDestroyed = Remotes:WaitForChild("PartDestroyed") :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

type PartState = {
    health: number,
    maxHealth: number,
    transparency: number,
    collide: boolean,
    query: boolean,
    touch: boolean,
}

-- Registered breakables and their pre-break property snapshot (restored on Reset()).
local states: { [BasePart]: PartState } = {}

-- Live cosmetic debris and the os.clock() timestamp each piece expires at.
local fragments: { [BasePart]: number } = {}
local fragmentCount = 0

local connections: { RBXScriptConnection } = {}
local stopped = false

local debrisFolder = Instance.new("Folder")
debrisFolder.Name = Constants.DESTRUCTION_DEBRIS_FOLDER_NAME :: string
debrisFolder.Parent = workspace

local DestructionService = {}

-- ============================================================
-- Private helpers
-- ============================================================

local function clearFragment(part: BasePart)
    if fragments[part] == nil then return end
    fragments[part] = nil
    fragmentCount -= 1
    part:Destroy()
end

-- Scatters a few small, capped-lifetime, non-collidable fragments outward from a broken
-- part. Purely cosmetic — never affects health, collision for players, or raycasts.
local function scatter(part: BasePart, direction: Vector3)
    local count = math.min(
        Constants.DESTRUCTION_FRAGMENTS_PER_BREAK :: number,
        (Constants.DESTRUCTION_MAX_LIVE_FRAGMENTS :: number) - fragmentCount
    )
    local scale   = Constants.DESTRUCTION_FRAGMENT_SCALE :: number
    local minSize = Constants.DESTRUCTION_FRAGMENT_MIN_SIZE :: number
    local maxSize = Constants.DESTRUCTION_FRAGMENT_MAX_SIZE :: number
    for index = 1, count do
        local shard = Instance.new("Part")
        shard.Name = "WoodFragment"
        shard.Size = Vector3.new(
            math.clamp(part.Size.X * scale, minSize, maxSize),
            math.clamp(part.Size.Y * scale, minSize, maxSize),
            math.clamp(part.Size.Z * scale, minSize, maxSize)
        )
        shard.CFrame     = part.CFrame
        shard.Color      = part.Color
        shard.Material   = part.Material
        shard.CanCollide = false
        shard.CanQuery   = false
        shard.CanTouch   = false
        shard.CastShadow = false
        shard.Parent     = debrisFolder
        shard:SetNetworkOwner(nil)
        shard.AssemblyLinearVelocity = direction * (Constants.DESTRUCTION_FRAGMENT_SPEED :: number)
            + Vector3.new(0, Constants.DESTRUCTION_FRAGMENT_LIFT :: number, 0)
        shard.AssemblyAngularVelocity = Vector3.new(index, -index, index)
            * (Constants.DESTRUCTION_FRAGMENT_SPIN :: number)
        fragments[shard] = os.clock() + (Constants.DESTRUCTION_FRAGMENT_LIFETIME :: number)
        fragmentCount += 1
    end
end

local function finiteVector(value: Vector3): boolean
    return Rules.IsFinite(value.X) and Rules.IsFinite(value.Y) and Rules.IsFinite(value.Z)
end

-- ============================================================
-- Public API
-- ============================================================

-- Applies `damage` to `part` at world `position`, arriving from `direction` (used only to
-- scatter cosmetic debris outward on break). Returns true if `part` is a registered
-- breakable and the hit was accepted (whether or not it broke the part this time); false
-- for any unregistered part or an invalid hit — callers can safely call this for every
-- non-player raycast hit without checking eligibility first.
-- Server-authoritative: GunService supplies position/direction from its own validated
-- raycast, never from an unvalidated client value.
function DestructionService:ApplyHit(part: Instance, damage: number, position: Vector3, direction: Vector3): boolean
    if stopped or not part:IsA("BasePart") then return false end
    local state = states[part]
    if state == nil or not finiteVector(position) or not finiteVector(direction) then
        return false
    end

    -- Confirm the hit point is actually within this part's oriented bounds — guards
    -- against a mismatched position/part pair, not just "the raycast named this Instance".
    local localPoint = part.CFrame:PointToObjectSpace(position)
    local extent = part.Size * 0.5 + Vector3.one * (Constants.DESTRUCTION_IMPACT_TOLERANCE :: number)
    if math.abs(localPoint.X) > extent.X or math.abs(localPoint.Y) > extent.Y or math.abs(localPoint.Z) > extent.Z then
        return false
    end

    local nextHealth = Rules.NextHealth(state.health, damage, Constants.DESTRUCTION_MAX_DAMAGE_PER_HIT :: number)
    if nextHealth == nil then return false end
    state.health = nextHealth
    part:SetAttribute(Constants.BREAKABLE_HEALTH_ATTRIBUTE :: string, nextHealth)

    if nextHealth == 0 then
        -- Set authoritative state before effects so two shots landing the same server
        -- tick cannot break (and debris-scatter) the same piece twice.
        part:SetAttribute(Constants.BREAKABLE_BROKEN_ATTRIBUTE :: string, true)
        part.CanCollide   = false
        part.CanQuery     = false
        part.CanTouch     = false
        part.Transparency = 1
        if direction.Magnitude > (Constants.DESTRUCTION_MIN_DIRECTION_MAGNITUDE :: number) then
            scatter(part, direction.Unit)
        end
        -- Hook for a future client-side break VFX system; no client currently listens.
        PartDestroyed:FireAllClients(part, position)
        Logger.debug("[DestructionService] Broke", part:GetFullName())
    end
    return true
end

-- Restores every registered part to its pre-break property snapshot and clears live
-- debris. Called at the start of each PREP phase so ACTIVE always begins with wood/doors
-- intact — mirrors DamageService's health reset on the same event.
function DestructionService:Reset()
    if stopped then return end
    for part in fragments do
        clearFragment(part)
    end
    for part, state in states do
        if part.Parent ~= nil then
            state.health = state.maxHealth
            part.Transparency = state.transparency
            part.CanCollide   = state.collide
            part.CanQuery     = state.query
            part.CanTouch     = state.touch
            part:SetAttribute(Constants.BREAKABLE_HEALTH_ATTRIBUTE :: string, state.health)
            part:SetAttribute(Constants.BREAKABLE_BROKEN_ATTRIBUTE :: string, false)
        end
    end
    Logger.debug("[DestructionService] Reset all breakables")
end

-- Disconnects everything and clears state. Not called during normal play — the service is
-- meant to live for the server's lifetime. Exists for offline tests and future teardown.
function DestructionService:Destroy()
    if stopped then return end
    self:Reset()
    stopped = true
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
    table.clear(states)
    debrisFolder:Destroy()
end

-- ============================================================
-- Registration — server start only. Parts added to workspace after this point are not
-- registered; see the "known limitation" note in docs/DESTRUCTION_SYSTEM_PLAN.md.
-- ============================================================

local registered = 0
for _, instance in ipairs(workspace:GetDescendants()) do
    if not instance:IsA("BasePart") then continue end
    local profileName = instance:GetAttribute(Constants.BREAKABLE_PROFILE_ATTRIBUTE :: string)
    if typeof(profileName) ~= "string" then continue end
    local profile = (Constants.DESTRUCTION_PROFILES :: any)[profileName]
    if not profile or not instance.Anchored then continue end
    if registered >= (Constants.DESTRUCTION_MAX_REGISTERED_PARTS :: number) then
        Logger.warn("[DestructionService] Breakable budget exceeded — skipping", instance:GetFullName())
        continue
    end
    states[instance] = {
        health = profile.Health, maxHealth = profile.Health,
        transparency = instance.Transparency, collide = instance.CanCollide,
        query = instance.CanQuery, touch = instance.CanTouch,
    }
    instance:SetAttribute(Constants.BREAKABLE_HEALTH_ATTRIBUTE :: string, profile.Health)
    instance:SetAttribute(Constants.BREAKABLE_BROKEN_ATTRIBUTE :: string, false)
    registered += 1
end

table.insert(connections, RunService.Heartbeat:Connect(function()
    local now = os.clock()
    for part, expires in fragments do
        if now >= expires then clearFragment(part) end
    end
end))

table.insert(connections, MatchEvents.PhaseChanged.Event:Connect(function(phase: string, _round: number)
    if phase == Constants.Phase.PREP then
        DestructionService:Reset()
    end
end))

Logger.debug("[DestructionService] Registered", registered, "breakable parts; server-authoritative")

return DestructionService
