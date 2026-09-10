--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > DummyService
--
-- Owns developer damage-test dummies: R6 Humanoid models a developer tags with
-- Constants.TAG_DAMAGE_DUMMY (via scripts/Build-TestDummy.luau or by hand in Studio).
-- Nothing here is game logic — it exists to exercise the shared damage / ragdoll pipeline.
--
-- Responsibilities:
--   - Register every tagged dummy (at server start and whenever one is added at runtime),
--     add the generic Constants.TAG_DAMAGE_ENTITY tag so GunService damages it through the
--     normal pipeline, and prime its Humanoid.
--   - Track a per-limb health pool from CombatEvents.DamageDealt. Bookkeeping only —
--     Humanoid.Health still decides death — but it is the seam a future GoreService uses.
--   - On death (CombatEvents.EntityKilled or a stray Humanoid.Died), ragdoll the dummy
--     with the shot's preserved impulse, then respawn a fresh copy after
--     Constants.DUMMY_RESPAWN_DELAY unless it is flagged for manual respawn.
--   - Reset == respawn a pristine clone. A dead R6 Humanoid cannot be reliably revived,
--     and the owner asked for "normal Humanoid health/death", so reset replaces the model
--     from a template captured at first registration rather than healing a corpse.
--
-- What this script does NOT do:
--   - Apply or validate damage            →  GunService / DamageService
--   - Convert / rebuild the physics rig    →  RagdollService
--   - Build the dummy model                →  scripts/Build-TestDummy.luau (run once in Studio)
--   - Any dev UI / remote control          →  Stage 6 (not yet built)
--   - Gore / dismemberment                 →  future GoreService, via CombatEvents

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")
local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))
local Types     = require(Modules:WaitForChild("Types"))

local CombatEvents   = require(script.Parent:WaitForChild("CombatEvents"))
local RagdollService = require(script.Parent:WaitForChild("RagdollService"))

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local DummyDevCommand = Remotes:WaitForChild("DummyDevCommand") :: RemoteEvent
local DummyDevState   = Remotes:WaitForChild("DummyDevState")   :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

type LimbState = {
    health    : number,
    maxHealth : number,
    destroyed : boolean,
}

type DummyRecord = {
    id           : number,
    model        : Model,
    humanoid     : Humanoid,
    template     : Model,      -- pristine clone (Parent = nil); the source for every respawn
    spawnPivot   : CFrame,
    limbs        : { [string]: LimbState },
    lastHit      : Types.DamageInfo?,
    respawnToken : number,
    diedConn     : RBXScriptConnection?,
}

local dummies: { [number]: DummyRecord } = {}
local serviceConns: { RBXScriptConnection } = {}
local nextId = 0

local ID_ATTR = Constants.DUMMY_RUNTIME_ID_ATTRIBUTE :: string

-- Every R6 hit region except Unknown gets its own limb pool.
local LIMB_REGIONS: { string } = {
    Constants.HitRegion.Head,
    Constants.HitRegion.Torso,
    Constants.HitRegion.LeftArm,
    Constants.HitRegion.RightArm,
    Constants.HitRegion.LeftLeg,
    Constants.HitRegion.RightLeg,
}

-- ============================================================
-- Private helpers
-- ============================================================

local function freshLimbs(): { [string]: LimbState }
    local limbMax = Constants.DUMMY_LIMB_MAX_HEALTH :: number
    local limbs: { [string]: LimbState } = {}
    for _, region in ipairs(LIMB_REGIONS) do
        limbs[region] = { health = limbMax, maxHealth = limbMax, destroyed = false }
    end
    return limbs
end

local function resolveMaxHealth(model: Model): number
    local override = model:GetAttribute(Constants.DUMMY_ATTR_MAX_HEALTH :: string)
    if typeof(override) == "number" and override == override and override > 0 and override < math.huge then
        return override
    end
    return Constants.DUMMY_DEFAULT_MAX_HEALTH :: number
end

-- Resolves the record for a model via its runtime-id attribute. Returns nil for an
-- untracked model, or one whose id slot has been reused / cleared.
local function recordFor(model: Instance?): DummyRecord?
    if model == nil then
        return nil
    end
    local id = model:GetAttribute(ID_ATTR)
    if typeof(id) ~= "number" then
        return nil
    end
    local record = dummies[id]
    if record ~= nil and record.model == model then
        return record
    end
    return nil
end

-- Replaces a dummy with a pristine clone of its template at the original spawn pose.
-- Used for both auto-respawn after death and manual reset — a dead R6 rig is not revived.
local function replaceWithFresh(record: DummyRecord)
    if dummies[record.id] ~= record then
        return  -- already replaced / unregistered
    end
    record.respawnToken += 1

    if record.diedConn ~= nil then
        record.diedConn:Disconnect()
        record.diedConn = nil
    end
    dummies[record.id] = nil

    local old = record.model
    local fresh = record.template:Clone()
    fresh:SetAttribute(ID_ATTR, nil)  -- registerTagged assigns a new id when it parents
    fresh:PivotTo(record.spawnPivot)
    fresh.Parent = workspace          -- fires the CollectionService added signal → registerTagged(fresh)

    if old.Parent ~= nil then
        old:Destroy()
    end
    Logger.debug("[DummyService] Replaced", old.Name, "with a fresh copy")
end

local function scheduleRespawn(record: DummyRecord)
    if record.model:GetAttribute(Constants.DUMMY_ATTR_MANUAL_RESPAWN :: string) == true then
        Logger.debug("[DummyService]", record.model.Name, "died — manual respawn only")
        return
    end
    record.respawnToken += 1
    local token = record.respawnToken
    local delay = Constants.DUMMY_RESPAWN_DELAY :: number
    task.delay(delay, function()
        if dummies[record.id] == record and record.respawnToken == token then
            replaceWithFresh(record)
        end
    end)
    Logger.debug("[DummyService]", record.model.Name, "died — respawning in", delay, "s")
end

local function onDummyDied(model: Instance?, info: Types.DamageInfo?)
    local record = recordFor(model)
    if record == nil then
        return
    end
    if RagdollService:IsRagdolled(record.model) then
        return  -- EntityKilled and Humanoid.Died can both land; ragdoll once
    end

    -- Per-weapon knockback: look the profile up by the damage source name, else DEFAULT.
    -- `or` fallbacks tolerate a Constants module that has not synced the new keys yet.
    local impulse: Vector3? = nil
    if info ~= nil and info.hitDirection ~= nil and info.finalAmount > 0 then
        local byWeapon = (Constants.RAGDOLL_WEAPON_IMPULSE :: any) or {}
        local prof = (info.sourceName ~= nil and byWeapon[info.sourceName])
            or (Constants.RAGDOLL_IMPULSE_DEFAULT :: any)
            or { SCALE = 2.6, MAX = 240 }
        local mag = math.min(info.finalAmount * prof.SCALE, prof.MAX)
        impulse = info.hitDirection.Unit * mag
    end

    RagdollService:Apply(record.model, {
        impulse    = impulse,
        hitPart    = info and info.hitPart,
        sourceName = info and info.sourceName,
    })

    scheduleRespawn(record)
end

local function onDamageDealt(targetModel: Model?, info: Types.DamageInfo)
    local record = recordFor(targetModel)
    if record == nil then
        return
    end

    record.lastHit = info

    -- Skip limb depletion while the dummy is invincible — you are testing sustained fire /
    -- blood / reactions, not trying to whittle its limbs down. Humanoid.Health is untouched
    -- in that mode anyway (DamageService), so limb pools would drift out of sync with it.
    local infinite = record.model:GetAttribute(Constants.ATTR_INFINITE_HEALTH :: string) == true
    local limb = record.limbs[info.region]
    if not infinite and limb ~= nil and not limb.destroyed then
        limb.health = math.max(0, limb.health - info.finalAmount)
        if limb.health == 0 then
            limb.destroyed = true  -- tracked only; Humanoid.Health still decides death
        end
    end

    Logger.debug(string.format(
        "[DummyService] %s took %.1f dmg to %s (%s) | HP %d/%d",
        record.model.Name, info.finalAmount, info.region,
        info.sourceName ~= "" and info.sourceName or "?",
        math.floor(record.humanoid.Health), math.floor(record.humanoid.MaxHealth)
    ))
end

local function registerTagged(instance: Instance)
    if not instance:IsA("Model") then
        return
    end
    local model = instance :: Model
    if recordFor(model) ~= nil then
        return
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        Logger.warn("[DummyService] Tagged dummy has no Humanoid — skipped:", model:GetFullName())
        return
    end

    -- Capture the pristine rig BEFORE priming, so every respawn starts identical.
    local template = model:Clone()
    template:SetAttribute(ID_ATTR, nil)

    nextId += 1
    local id = nextId

    local maxHealth = resolveMaxHealth(model)
    humanoid.BreakJointsOnDeath = false   -- RagdollService rebuilds joints; the engine must not destroy them on death
    humanoid.MaxHealth          = maxHealth
    humanoid.Health             = maxHealth

    -- Generic "GunService may damage this" opt-in, kept separate from the dummy tag so a
    -- future NPC system reuses the routing without touching DummyService.
    if not CollectionService:HasTag(model, Constants.TAG_DAMAGE_ENTITY :: string) then
        CollectionService:AddTag(model, Constants.TAG_DAMAGE_ENTITY :: string)
    end
    -- Reserved for Stage 4/5. Only set when absent so hand-authored values win.
    if model:GetAttribute(Constants.ATTR_REACTIONS_ENABLED :: string) == nil then
        model:SetAttribute(Constants.ATTR_REACTIONS_ENABLED :: string, true)
    end
    if model:GetAttribute(Constants.ATTR_BLOOD_ENABLED :: string) == nil then
        model:SetAttribute(Constants.ATTR_BLOOD_ENABLED :: string, true)
    end

    model:SetAttribute(ID_ATTR, id)

    local record: DummyRecord = {
        id           = id,
        model        = model,
        humanoid     = humanoid,
        template     = template,
        spawnPivot   = model:GetPivot(),
        limbs        = freshLimbs(),
        lastHit      = nil,
        respawnToken = 0,
        diedConn     = nil,
    }

    -- Defensive: if something other than the damage pipeline kills the Humanoid (void,
    -- scripts, Studio), still ragdoll + respawn. onDummyDied de-dupes against IsRagdolled.
    record.diedConn = humanoid.Died:Connect(function()
        onDummyDied(model, record.lastHit)
    end)

    dummies[id] = record
    Logger.debug("[DummyService] Registered dummy", model:GetFullName(), "| id", id, "| HP", maxHealth)
end

local function unregisterTagged(instance: Instance)
    local record = recordFor(instance)
    if record == nil then
        return
    end
    record.respawnToken += 1
    if record.diedConn ~= nil then
        record.diedConn:Disconnect()
        record.diedConn = nil
    end
    dummies[record.id] = nil
    Logger.debug("[DummyService] Unregistered dummy", instance:GetFullName(), "| id", record.id)
end

-- ============================================================
-- Developer control (Stage 6) — Studio or Constants.DEV_USER_IDS only
-- ============================================================

local devSubscribers: { [Player]: boolean } = {}
local devStateAccumulator = 0

local function isDev(player: Player): boolean
    if RunService:IsStudio() then
        return true
    end
    return (Constants.DEV_USER_IDS :: { [number]: boolean })[player.UserId] == true
end

local function forEachDummy(fn: (DummyRecord) -> ())
    -- Snapshot ids first: replaceWithFresh mutates `dummies` mid-iteration.
    local ids: { number } = {}
    for id in dummies do
        table.insert(ids, id)
    end
    for _, id in ipairs(ids) do
        local record = dummies[id]
        if record ~= nil then
            fn(record)
        end
    end
end

local function buildDevState(): { [string]: any }
    local list: { any } = {}
    forEachDummy(function(record)
        local limbList: { any } = {}
        for region, limb in pairs(record.limbs) do
            table.insert(limbList, {
                region    = region,
                health    = limb.health,
                maxHealth = limb.maxHealth,
                destroyed = limb.destroyed,
            })
        end
        local lastHit: { [string]: any }? = nil
        if record.lastHit ~= nil then
            lastHit = {
                region     = record.lastHit.region,
                amount     = record.lastHit.finalAmount,
                source     = record.lastHit.sourceName,
                damageType = record.lastHit.damageType,
            }
        end
        table.insert(list, {
            id        = record.id,
            name      = record.model.Name,
            health    = math.floor(record.humanoid.Health + 0.5),
            maxHealth = math.floor(record.humanoid.MaxHealth + 0.5),
            infinite  = record.model:GetAttribute(Constants.ATTR_INFINITE_HEALTH :: string) == true,
            ragdolled = RagdollService:IsRagdolled(record.model),
            lastHit   = lastHit,
            limbs     = limbList,
        })
    end)
    return {
        bloodEnabled = ReplicatedStorage:GetAttribute(Constants.BLOOD_GLOBAL_ATTRIBUTE :: string) ~= false,
        dummies      = list,
    }
end

local function handleDevCommand(player: Player, command: any, arg: any)
    if not isDev(player) or typeof(command) ~= "string" then
        return
    end

    if command == "subscribe" then
        devSubscribers[player] = true
        DummyDevState:FireClient(player, buildDevState())
    elseif command == "reset" then
        forEachDummy(replaceWithFresh)
        Logger.debug("[DummyService] Dev reset by", player.Name)
    elseif command == "heal" then
        forEachDummy(function(record)
            if record.humanoid.Parent ~= nil then
                record.humanoid.Health = record.humanoid.MaxHealth
            end
        end)
        Logger.debug("[DummyService] Dev heal by", player.Name)
    elseif command == "infinite" then
        local enabled = arg == true
        forEachDummy(function(record)
            record.model:SetAttribute(Constants.ATTR_INFINITE_HEALTH :: string, enabled)
        end)
        Logger.debug("[DummyService] Dev infinite =", enabled, "by", player.Name)
    elseif command == "blood" then
        ReplicatedStorage:SetAttribute(Constants.BLOOD_GLOBAL_ATTRIBUTE :: string, arg == true)
        Logger.debug("[DummyService] Dev blood =", arg == true, "by", player.Name)
    end
end

-- ============================================================
-- Init
-- ============================================================

local dummyTag = Constants.TAG_DAMAGE_DUMMY :: string

table.insert(serviceConns, CombatEvents.DamageDealt.Event:Connect(onDamageDealt))
table.insert(serviceConns, CombatEvents.EntityKilled.Event:Connect(function(targetModel: Model?, info: Types.DamageInfo)
    onDummyDied(targetModel, info)
end))

table.insert(serviceConns, CollectionService:GetInstanceAddedSignal(dummyTag):Connect(registerTagged))
table.insert(serviceConns, CollectionService:GetInstanceRemovedSignal(dummyTag):Connect(unregisterTagged))

table.insert(serviceConns, DummyDevCommand.OnServerEvent:Connect(handleDevCommand))
table.insert(serviceConns, Players.PlayerRemoving:Connect(function(player: Player)
    devSubscribers[player] = nil
end))
table.insert(serviceConns, RunService.Heartbeat:Connect(function(dt: number)
    devStateAccumulator += dt
    if devStateAccumulator < (Constants.DUMMY_DEV_STATE_INTERVAL :: number) then
        return
    end
    devStateAccumulator = 0
    if next(devSubscribers) == nil then
        return
    end
    local state = buildDevState()
    for player in devSubscribers do
        if player.Parent ~= nil then
            DummyDevState:FireClient(player, state)
        else
            devSubscribers[player] = nil
        end
    end
end))

for _, model in ipairs(CollectionService:GetTagged(dummyTag)) do
    registerTagged(model)
end

Logger.debug("[DummyService] Ready —", #CollectionService:GetTagged(dummyTag), "tagged dummies")
