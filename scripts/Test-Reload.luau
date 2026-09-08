--!strict
-- Offline regression tests for the actual reload method; engine signals are mocked.
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local root = 'outputs/BrokenReality/'
local source = fs.readFile(root .. 'src/StarterPlayer/StarterPlayerScripts/Controllers/ViewModelController.lua')
local first = assert(string.find(source, 'function ViewModelController:PlayReloadAnimation()', 1, true))
local last = assert(string.find(source, '-- Called by GunController each RenderStepped with the current sprint flag.', first, true))
local method = string.sub(source, first, last - 1)
local function signal()
    local handlers = {}
    return {
        Connect = function(_, callback)
            local connection = {Connected=true}
            function connection:Disconnect() self.Connected=false end
            table.insert(handlers, {callback=callback, connection=connection})
            return connection
        end,
        Fire = function(_, ...)
            for _, item in table.clone(handlers) do
                if item.connection.Connected then item.callback(...) end
            end
        end,
        Count = function()
            local count=0
            for _, item in handlers do if item.connection.Connected then count+=1 end end
            return count
        end,
    }
end
local function fixture(length, fpError, tpError, immediateStop)
    local stopped, heartbeat = signal(), signal()
    local track = {Length=length, Stopped=stopped, plays=0, Animation={AnimationId='test'}}
    function track:Play()
        if fpError then error('FP test failure') end
        self.plays+=1
        if immediateStop then stopped:Fire() end
    end
    function track:Stop() stopped:Fire() end
    local tp = {Stop=function() end, Play=function() if tpError then error('TP test failure') end end}
    local env = {
        weaponReloadTrack=track, equippedWeaponName='AKS74', isReloading=false,
        reloadConnections={}, RunService={Heartbeat=heartbeat}, adsState='Hip',
        tpReloadTrack=tp, vmLocomotionState='Idle',
        Constants={VIEWMODEL_RELOAD_LOAD_TIMEOUT=3, VIEWMODEL_RELOAD_MAX_DURATION=10,
            VIEWMODEL_LOCOMOTION_ANIMS_ENABLED=true},
        Logger={debug=function() end,warn=function() end},
    }
    env.clearReloadConnections=function()
        for _, c in env.reloadConnections do c:Disconnect() end
        table.clear(env.reloadConnections)
    end
    local controller={model={}, SetLocomotionState=function() end}
    env.ViewModelController=controller
    luau.load(method .. '\nfunction ViewModelController.readState() return isReloading end', {environment=env})()
    local state = setmetatable({}, {__index=function(_,key)
        if key=='isReloading' then return controller.readState() end
        return env[key]
    end})
    return controller, state, track, stopped, heartbeat
end
local checks=0
local function check(value, message) assert(value,message); checks+=1 end
do
    local c,e,t,s,h=fixture(2,false,false,false)
    c:PlayReloadAnimation(); check(e.isReloading and t.plays==1,'Normal start')
    c:PlayReloadAnimation(); check(t.plays==1,'Spam does not restart')
    s:Fire(); check(not e.isReloading and s.Count()==0 and h.Count()==0,'Finish cleans signals')
    c:PlayReloadAnimation(); s:Fire(); check(s.Count()==0,'Repeated reload does not accumulate connections')
end
do
    local c,e,t,s,h=fixture(0,false,false,false)
    c:PlayReloadAnimation(); check(t.plays==0,'Unloaded track waits')
    t.Length=2; h:Fire(0.1); check(t.plays==1,'Delayed asset starts when ready')
    h:Fire(10); check(not e.isReloading and h.Count()==0,'Missing Stopped recovers')
end
do
    local c,e,t,s,h=fixture(0,false,false,false)
    c:PlayReloadAnimation(); h:Fire(3); check(not e.isReloading and t.plays==0,'Unavailable asset unlocks')
end
do
    local c,e,t,s,h=fixture(2,true,false,false)
    c:PlayReloadAnimation(); check(not e.isReloading and h.Count()==0,'FP Play error unlocks')
end
do
    local c,e,t,s,h=fixture(2,false,true,false)
    c:PlayReloadAnimation(); check(t.plays==1,'TP error does not block FP')
    s:Fire(); check(not e.isReloading,'TP error does not block recovery')
end
do
    local c,e,t,s,h=fixture(2,false,false,true)
    c:PlayReloadAnimation(); check(not e.isReloading and h.Count()==0,'Immediate stop recovers')
end
do
    local c,e,t,s,h=fixture(2,false,false,false)
    c:PlayReloadAnimation(); c.model={}; h:Fire(1)
    check(h.Count()==0 and s.Count()==0,'Replaced model disconnects old callbacks')
end
luau.compile(source)
luau.compile(fs.readFile(root .. 'src/ReplicatedStorage/Modules/Constants.lua'))
return checks
