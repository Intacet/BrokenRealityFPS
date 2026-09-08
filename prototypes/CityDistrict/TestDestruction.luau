--!strict
-- Offline behavioral tests: actual module code and Lune instances, mocked engine signals/physics.
local fs=require('@lune/fs')
local rb=require('@lune/roblox')
local luau=require('@lune/luau')
local serde=require('@lune/serde')
local folder='outputs/BrokenReality/prototypes/CityDistrict/'
local Constants=luau.load(fs.readFile(folder..'Constants.lua'))()
local Rules=luau.load(fs.readFile(folder..'DamageRules.lua'))()
local game=rb.deserializePlace(fs.readFile('outputs/CityDistrict/BrokenReality_CityTest.rbxl'))
local ws=game:GetService('Workspace')
local signals={}
local function signal()
    local s={handlers={}}
    function s:Connect(fn)
        local connection={Connected=true}
        function connection:Disconnect() self.Connected=false end
        table.insert(self.handlers,{fn=fn,connection=connection})
        return connection
    end
    function s:Fire(...)
        for _,item in self.handlers do if item.connection.Connected then item.fn(...) end end
    end
    table.insert(signals,s)
    return s
end
local heartbeat=signal()
local phase=signal()
local destroying={}
rb.implementProperty('Instance','Destroying',function(obj)
    if not destroying[obj] then destroying[obj]=signal() end
    return destroying[obj]
end)
rb.implementMethod('Instance','WaitForChild',function(obj,name) return assert(obj:FindFirstChild(name),name) end)
rb.implementMethod('BasePart','SetNetworkOwner',function() end)
rb.implementMethod('RunService','IsServer',function() return true end)
rb.implementProperty('RunService','Heartbeat',function() return heartbeat end)
local elapsed=0
local function requireModule(module)
    if module.Name=='Constants' then
        if module.Parent.Name=='CityDistrict' then return Constants end
        return {Phase={PREP='PREP'}}
    elseif module.Name=='DamageRules' then return Rules
    elseif module.Name=='Logger' then return {debug=function() end}
    elseif module.Name=='MatchEvents' then return {PhaseChanged={Event=phase}} end
    error('Unexpected dependency')
end
local env={game=game,workspace=ws,script=game:GetService('ServerScriptService').CityDistrict.DestructionService,
    require=requireModule,Instance=rb.Instance,Vector3=rb.Vector3,os={clock=function() return elapsed end}}
local service=luau.load(fs.readFile(folder..'DestructionService.lua'),{environment=env})()
local checks=0
local function check(ok,message) assert(ok,message); checks+=1 end
local parts={}
for _,p in ws.BR_CityDistrict:GetDescendants() do if p:IsA('BasePart') and p:GetAttribute('BR_BreakableProfile') then table.insert(parts,p) end end
local target=parts[1]
local max=target:GetAttribute('BR_Health')
local at=target.CFrame.Position
local dir=rb.Vector3.new(1,0,0)
check(not service.ApplyHit(ws.BR_CityDistrict,20,at,dir),'Reject model target')
check(not service.ApplyHit(target,0/0,at,dir),'Reject NaN damage')
check(not service.ApplyHit(target,math.huge,at,dir),'Reject infinite damage')
check(not service.ApplyHit(target,-20,at,dir),'Reject negative damage')
check(not service.ApplyHit(target,20,at+rb.Vector3.new(100,0,0),dir),'Reject remote impact')
check(target:GetAttribute('BR_Health')==max,'Invalid hits preserve health')
check(service.ApplyHit(target,10,at,dir),'Valid partial damage')
check(target:GetAttribute('BR_Health')==max-10,'Accumulate damage')
check(service.ApplyHit(target,100,at,dir),'Break target')
check(target:GetAttribute('BR_Broken')==true and not target.CanCollide and not target.CanQuery and target.Transparency==1,'Passable invisible broken state')
local fragments=#ws.BR_CityDebris:GetChildren()
check(not service.ApplyHit(target,20,at,dir),'Reject duplicate break')
check(#ws.BR_CityDebris:GetChildren()==fragments,'Duplicate hit creates no debris')
for _,p in parts do
    service.ApplyHit(p,100,p.CFrame.Position,dir); service.ApplyHit(p,100,p.CFrame.Position,dir)
end
check(#ws.BR_CityDebris:GetChildren()<=Constants.MaxLiveFragments,'Global debris cap')
elapsed=Constants.FragmentLifetime+1
heartbeat:Fire()
check(#ws.BR_CityDebris:GetChildren()==0,'Debris expires')
phase:Fire('PREP')
check(target:GetAttribute('BR_Health')==max and target:GetAttribute('BR_Broken')==false and target.CanQuery,'Round reset restores state')
check(Rules.NextHealth(140,1000,100)==40,'Damage clamp')
service.Destroy()
for _,s in signals do for _,item in s.handlers do check(not item.connection.Connected,'Connections disconnected') end end
check(not service.ApplyHit(target,20,at,dir),'Destroyed service rejects hits')
for _,name in {'Constants.lua','DamageRules.lua','DestructionService.lua','BuildDistrict.luau'} do luau.compile(fs.readFile(folder..name)) end
luau.compile(fs.readFile('outputs/CityDistrict/GunService.test-only.server.lua'))
local original=rb.deserializePlace(fs.readFile('outputs/StudioBackups/BrokenReality_preRojo.rbxl'))
local function scripts(root)
    local list={}
    for _,obj in root:GetDescendants() do if obj:IsA('LuaSourceContainer') then table.insert(list,obj.Source) end end
    table.sort(list); return list
end
check(serde.encode('json',scripts(original:GetService('Workspace')))==serde.encode('json',scripts(game:GetService('ServerStorage').BR_OriginalWorkspace_Archive)),'All original Workspace scripts retained')
fs.writeFile('outputs/CityDistrict/TEST_RESULTS.json',serde.encode('json',{passed=checks,breakables=#parts,compiled=true,studioVerified=false,physicsMocked=true},true))
