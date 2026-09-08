--!strict
-- Called only by GunService AFTER its authoritative raycast, ammo and rate checks.
-- No remote listener and no client-supplied target, health, damage, or destruction result.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "DestructionService is server-only")
local Constants = require(script.Parent.Constants)
local Rules = require(script.Parent.DamageRules)
local Logger = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Logger"))
local MatchEvents = require(ServerScriptService:WaitForChild("Services"):WaitForChild("MatchEvents"))
local GameConstants = require(ReplicatedStorage.Modules.Constants)

type State = { health: number, maxHealth: number, transparency: number, collide: boolean, query: boolean, touch: boolean }
local states: { [BasePart]: State } = {}
local fragments: { [BasePart]: number } = {}
local connections: { RBXScriptConnection } = {}
local fragmentCount = 0
local root = workspace:WaitForChild(Constants.RootName)
local debrisFolder = Instance.new("Folder")
debrisFolder.Name = Constants.DebrisFolderName
debrisFolder.Parent = workspace
local Service = {}
local stopped = false

local function clearFragment(part: BasePart)
    if fragments[part] == nil then return end
    fragments[part] = nil
    fragmentCount -= 1
    part:Destroy()
end

local function scatter(part: BasePart, direction: Vector3)
    local count = math.min(Constants.FragmentsPerBreak, Constants.MaxLiveFragments - fragmentCount)
    for index = 1, count do
        local shard = Instance.new("Part")
        shard.Name = "CosmeticFragment"
        shard.Size = Vector3.new(
            math.clamp(part.Size.X * Constants.FragmentScale, Constants.FragmentMinSize, Constants.FragmentMaxSize),
            math.clamp(part.Size.Y * Constants.FragmentScale, Constants.FragmentMinSize, Constants.FragmentMaxSize),
            math.clamp(part.Size.Z * Constants.FragmentScale, Constants.FragmentMinSize, Constants.FragmentMaxSize)
        )
        shard.CFrame = part.CFrame
        shard.Color = part.Color
        shard.Material = part.Material
        shard.CanCollide = false
        shard.CanQuery = false
        shard.CanTouch = false
        shard.CastShadow = false
        shard.Parent = debrisFolder
        shard:SetNetworkOwner(nil)
        shard.AssemblyLinearVelocity = direction * Constants.FragmentSpeed + Vector3.new(0, Constants.FragmentLift, 0)
        shard.AssemblyAngularVelocity = Vector3.new(index, -index, index) * Constants.FragmentSpin
        fragments[shard] = os.clock() + Constants.FragmentLifetime
        fragmentCount += 1
    end
end

local function finiteVector(value: Vector3): boolean
    return Rules.IsFinite(value.X) and Rules.IsFinite(value.Y) and Rules.IsFinite(value.Z)
end

function Service.ApplyHit(part: Instance, damage: number, position: Vector3, direction: Vector3): boolean
    if stopped or not part:IsA("BasePart") then return false end
    local state = states[part]
    if state == nil or not part:IsDescendantOf(root) or not finiteVector(position) or not finiteVector(direction) then
        return false
    end
    -- Check against the actual oriented target bounds, not its distance from an arbitrary origin.
    local localPoint = part.CFrame:PointToObjectSpace(position)
    local extent = part.Size * 0.5 + Vector3.one * Constants.ImpactTolerance
    if math.abs(localPoint.X) > extent.X or math.abs(localPoint.Y) > extent.Y or math.abs(localPoint.Z) > extent.Z then
        return false
    end
    local nextHealth = Rules.NextHealth(state.health, damage, Constants.MaxDamagePerHit)
    if nextHealth == nil then return false end
    state.health = nextHealth
    part:SetAttribute(Constants.HealthAttribute, nextHealth)
    if nextHealth == 0 then
        -- Set authoritative state before effects so duplicate hits cannot break it twice.
        part:SetAttribute(Constants.BrokenAttribute, true)
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Transparency = 1
        if direction.Magnitude > Constants.MinDirectionMagnitude then scatter(part, direction.Unit) end
    end
    return true
end

function Service.Reset()
    if stopped then return end
    for part in fragments do clearFragment(part) end
    for part, state in states do
        if part:IsDescendantOf(root) then
            state.health = state.maxHealth
            part.Transparency = state.transparency
            part.CanCollide = state.collide
            part.CanQuery = state.query
            part.CanTouch = state.touch
            part:SetAttribute(Constants.HealthAttribute, state.health)
            part:SetAttribute(Constants.BrokenAttribute, false)
        end
    end
end

function Service.Destroy()
    if stopped then return end
    Service.Reset()
    stopped = true
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
    table.clear(states)
    debrisFolder:Destroy()
end

local registered = 0
for _, instance in root:GetDescendants() do
    if not instance:IsA("BasePart") then continue end
    local profileName = instance:GetAttribute(Constants.ProfileAttribute)
    if typeof(profileName) ~= "string" then continue end
    local profile = Constants.Profiles[profileName]
    if not profile or not instance.Anchored then continue end
    assert(registered < Constants.MaxRegisteredParts, "City breakable budget exceeded")
    states[instance] = { health = profile.Health, maxHealth = profile.Health,
        transparency = instance.Transparency, collide = instance.CanCollide,
        query = instance.CanQuery, touch = instance.CanTouch }
    instance:SetAttribute(Constants.HealthAttribute, profile.Health)
    instance:SetAttribute(Constants.BrokenAttribute, false)
    registered += 1
end
table.insert(connections, RunService.Heartbeat:Connect(function()
    local now = os.clock()
    for part, expires in fragments do if now >= expires then clearFragment(part) end end
end))
table.insert(connections, MatchEvents.PhaseChanged.Event:Connect(function(phase: string)
    if phase == GameConstants.Phase.PREP then Service.Reset() end
end))
table.insert(connections, root.Destroying:Connect(Service.Destroy))
table.insert(connections, script.Destroying:Connect(Service.Destroy))
Logger.debug("[CityDestruction] Registered", registered, "breakables; server-authoritative")
return Service
