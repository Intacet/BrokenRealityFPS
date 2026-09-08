--!strict
-- Offline Lune builder. Never reads or writes the currently open Studio session.
local fs = require('@lune/fs')
local roblox = require('@lune/roblox')
local serde = require('@lune/serde')
local I, V, C, RGB = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3.fromRGB
local E = roblox.Enum
local out = 'outputs/CityDistrict'
local source = 'outputs/BrokenReality/prototypes/CityDistrict/'
fs.writeDir(out)
local original = fs.readFile('outputs/StudioBackups/BrokenReality_preRojo.rbxl')
local game = roblox.deserializePlace(original)
local ws = game:GetService('Workspace')
local offset = V.new(10000,100,10000)
local district = I.new('Model'); district.Name='BR_CityDistrict'; district.Parent=ws
local records = {}
local function group(name, parent)
    local m=I.new('Model'); m.Name=name; m.Parent=parent or district; return m
end
local function part(parent,name,size,cf,color,material)
    local p=I.new('Part'); p.Name=name; p.Size=size; p.CFrame=C.new(offset)*cf
    p.Anchored=true; p.Color=color; p.Material=material or E.Material.Concrete
    p.TopSurface=E.SurfaceType.Smooth; p.BottomSurface=E.SurfaceType.Smooth; p.Parent=parent
    return p
end
local brick={RGB(117,65,51),RGB(142,82,62),RGB(91,61,53),RGB(164,121,91),RGB(110,104,89)}
local trim=RGB(180,168,141)
local asphalt=RGB(48,51,51)
local teal=RGB(46,77,73)
local function textSign(parent,name,cf,size,text,color)
    local p=part(parent,name,size,cf,color or teal,E.Material.Metal)
    local gui=I.new('SurfaceGui'); gui.Name='SignFace'; gui.Face=E.NormalId.Front
    gui.CanvasSize=roblox.Vector2.new(900,180); gui.Parent=p
    local t=I.new('TextLabel'); t.Size=roblox.UDim2.fromScale(1,1); t.BackgroundTransparency=1
    t.Text=text; t.TextColor3=RGB(231,222,198); t.TextScaled=true; t.Parent=gui
    return p
end
local function breakable(p,profile)
    p:SetAttribute('BR_BreakableProfile',profile)
    p.CanTouch=false
    return p
end
local ground=group('StreetsAndSidewalks')
part(ground,'Ground',V.new(760,4,650),C.new(0,-2,0),RGB(73,76,66),E.Material.Ground)
for _,x in {-290,-95,95,290} do
    part(ground,'CrossStreet',V.new(38,0.3,570),C.new(x,0.15,0),asphalt,E.Material.Asphalt)
end
for _,z in {-250,0,250} do
    part(ground,'MainStreet',V.new(700,0.3,38),C.new(0,0.15,z),asphalt,E.Material.Asphalt)
    for x=-320,320,24 do
        part(ground,'LaneMarking',V.new(10,0.05,0.4),C.new(x,0.33,z),RGB(189,165,90))
    end
end
local function cover(parent,x,z,kind)
    if kind=='timber' then
        breakable(part(parent,'TimberBarricade',V.new(12,8,1.2),C.new(x,4,z),RGB(119,90,54),E.Material.WoodPlanks),'Timber')
    elseif kind=='light' then
        breakable(part(parent,'BreakableCrate',V.new(7,6,5),C.new(x,3,z),RGB(118,106,75),E.Material.WoodPlanks),'LightCover')
    else
        part(parent,'PermanentPlanter',V.new(14,4,7),C.new(x,2,z),RGB(107,106,92))
        local leaves=part(parent,'Shrub',V.new(12,3,5),C.new(x,5,z),RGB(49,66,47),E.Material.Grass)
        leaves.CanCollide=false; leaves.CanQuery=false
    end
end
local function building(name,x,z,w,d,h,rotation,color,sign,door)
    local m=group(name)
    local pivot=C.new(x,0,z)*C.Angles(0,rotation,0)
    local function p(n,size,px,py,pz,c,mat)
        return part(m,n,size,pivot*C.new(px,py,pz),c or color,mat or E.Material.Brick)
    end
    p('Floor',V.new(w,0.6,d),0,0.6,0,RGB(103,96,85),E.Material.Concrete)
    p('LeftPartyWall',V.new(1.2,h,d),-w/2,h/2,0)
    p('RightPartyWall',V.new(1.2,h,d),w/2,h/2,0)
    -- Ground-floor openings are real holes; no hidden wall behind glass or doors.
    local opening={{-w*.34-3,-w*.34+3,4,11,'Window'},{-4.5,4.5,0,11,'Door'},{w*.34-3,w*.34+3,4,11,'Window'}}
    for _,face in {-1,1} do
        local cuts={-w/2,w/2}
        for _,o in opening do table.insert(cuts,o[1]); table.insert(cuts,o[2]) end
        table.sort(cuts)
        for _,band in {{0,4},{4,11},{11,h}} do
            for k=1,#cuts-1 do
                local left,right=cuts[k],cuts[k+1]
                local mx,my=(left+right)/2,(band[1]+band[2])/2
                local hole=false
                for _,o in opening do if mx>o[1] and mx<o[2] and my>o[3] and my<o[4] then hole=true end end
                if not hole then p('FacadeBrick',V.new(right-left,band[2]-band[1],1),mx,my,face*d/2) end
            end
        end
        for _,o in opening do
            local mx=(o[1]+o[2])/2
            if o[5]=='Window' then
                local glass=p('GroundWindow',V.new(o[2]-o[1],o[4]-o[3],0.25),mx,(o[3]+o[4])/2,face*d/2,RGB(115,151,147),E.Material.Glass)
                glass.Transparency=0.35; breakable(glass,'Glass')
                p('WindowSill',V.new(7,0.4,1.5),mx,3.8,face*d/2,trim,E.Material.Concrete)
            elseif door and face==-1 then
                local panel=p('BreachableDoor',V.new(8.7,10.8,0.5),mx,5.4,face*d/2,RGB(119,84,55),E.Material.WoodPlanks)
                breakable(panel,'Timber')
            end
        end
    end
    p('Cornice',V.new(w+1,1.2,d+1),0,h-1,0,trim,E.Material.Concrete)
    p('Roof',V.new(w+1,0.8,d+1),0,h+0.4,0,RGB(68,70,65),E.Material.Slate)
    for _,face in {-1,1} do
        for wx=-w/2+7,w/2-5,12 do
            for wy=20,h-5,13 do
                p('UpperWindowInset',V.new(5,7,0.18),wx,wy,face*(d/2+0.55),RGB(43,57,58),E.Material.SmoothPlastic)
                p('UpperLintel',V.new(6,0.5,0.7),wx,wy+3.7,face*(d/2+0.6),trim,E.Material.Concrete)
                p('UpperSill',V.new(6,0.5,0.7),wx,wy-3.7,face*(d/2+0.6),trim,E.Material.Concrete)
            end
        end
    end
    if sign then
        textSign(m,'ShopSign',pivot*C.new(0,13,-d/2-0.8),V.new(w-2,3,0.6),sign)
        p('Awning',V.new(w-1,0.5,4),0,11.5,-d/2-2,teal,E.Material.Fabric)
        p('ShopCounter',V.new(w*.38,3.5,3),-w*.2,2.5,0,RGB(90,71,52),E.Material.Wood)
        p('BackShelf',V.new(3,6,d*.4),w/2-3,3.8,0,RGB(80,85,76),E.Material.Metal)
    else
        p('InteriorCover',V.new(7,4,3),-w*.24,2.7,2,RGB(105,82,62),E.Material.Wood)
    end
    table.insert(records,{name=name,x=x,z=z,width=w,depth=d,height=h,rotation=rotation,interior=true})
    return m
end
local shops={{'MERCER MARKET','RADIO REPAIR'},{'WARD PHARMACY','COMMON TABLE'},{'RIVER FREIGHT','MOTOR WORKS'}}
for col,cx in {-190,0,190} do
    for _,side in {-1,1} do
        local bz=side*132
        part(ground,'RaisedBlock',V.new(146,0.6,186),C.new(cx,0.35,bz),RGB(128,121,106))
        -- A continuous 18-stud rear alley connects both ends of each block.
        part(ground,'RearAlley',V.new(146,0.12,18),C.new(cx,0.73,side*132),RGB(84,80,71),E.Material.Asphalt)
        for unit,dx in {-35,35} do
            local n=(side==-1 and 'North' or 'South')..col..'_'..unit
            building(n..'_Shop',cx+dx,side*68,58,42,29+(col%2)*9,side==-1 and math.pi or 0,brick[col],shops[col][unit],unit==2)
        end
        if col<3 then
            for unit,dx in {-48,0,48} do
                building((side==-1 and 'North' or 'South')..col..'_Rowhouse'..unit,cx+dx,side*191,36,42,34+(unit%2)*5,side==1 and math.pi or 0,brick[(unit+col)%#brick+1],nil,unit==2)
            end
        else
            building((side==-1 and 'North' or 'South')..'_Warehouse',cx,side*188,116,50,25,side==1 and math.pi or 0,brick[3],'RIVER TRANSIT / STORAGE',true)
        end
        local courtyard=group((side==-1 and 'North' or 'South')..col..'_Courtyard')
        cover(courtyard,cx-40,side*112,'light'); cover(courtyard,cx+35,side*151,'solid')
        cover(courtyard,cx+8,side*112,'solid')
        -- Only secondary cut-throughs are gated. Main alley remains walkable intact.
        cover(courtyard,cx+60,side*153,'timber')
    end
end
local streets=group('StreetFurniture')
for _,x in {-245,-130,-55,55,130,245} do
    for _,z in {-26,26} do
        part(streets,'LampPost',V.new(0.7,20,0.7),C.new(x,10,z),RGB(54,59,56),E.Material.Metal)
        local lamp=part(streets,'Lamp',V.new(3,0.6,2),C.new(x,20,z),RGB(226,203,144),E.Material.Neon)
        local light=I.new('PointLight'); light.Range=28; light.Brightness=0.8; light.Color=RGB(236,210,161); light.Parent=lamp
    end
end
for _,x in {-95,95} do
    for _,z in {-22,22} do
        for stripe=-3,3 do part(streets,'Crosswalk',V.new(2,0.08,9),C.new(x+stripe*4,0.39,z),RGB(192,186,161)) end
    end
end
-- Offset street furniture interrupts uninterrupted avenue sightlines without sealing the lanes.
for _,data in {{-140,-7},{15,7},{175,-7}} do
    local x,z=data[1],data[2]
    local bus=group('AbandonedDeliveryVan')
    part(bus,'Body',V.new(10,7,23),C.new(x,4,z),RGB(112,119,106),E.Material.Metal)
    part(bus,'CabWindow',V.new(10.1,3,5),C.new(x,6,z-6),RGB(42,58,60),E.Material.Glass)
    for _,dx in {-5,5} do for _,dz in {-7,7} do part(bus,'Wheel',V.new(1.4,3,3),C.new(x+dx,1.8,z+dz),RGB(29,31,30),E.Material.Rubber) end end
end
for _,x in {-230,-45,120,245} do cover(streets,x,22,'solid'); cover(streets,x+18,-23,'light') end
-- Solid sightline screens at the side-street bends: always leave two pedestrian bypasses.
for _,x in {-95,95} do
    for _,z in {-160,160} do part(streets,'SightlineScreen',V.new(18,10,3),C.new(x,5,z),RGB(90,96,86)) end
end
local perimeter=group('DistrictBoundary')
for _,z in {-300,300} do part(perimeter,'BoundaryWall',V.new(730,18,2),C.new(0,9,z),brick[3],E.Material.Brick) end
for _,x in {-365,365} do part(perimeter,'BoundaryWall',V.new(2,18,600),C.new(x,9,0),brick[3],E.Material.Brick) end
local staging=group('TeamStaging')
for _,x in {-330,330} do
    for _,z in {-28,28} do part(staging,'ProtectedStagingWall',V.new(42,12,3),C.new(x,6,z),RGB(81,91,81)) end
    part(staging,'SpawnSightlineScreen',V.new(3,12,28),C.new(x<0 and -302 or 302,6,0),RGB(81,91,81))
end
textSign(staging,'ContainmentSign',C.new(-345,12,0)*C.Angles(0,-math.pi/2,0),V.new(30,4,1),'CONTAINMENT / ENTRY',RGB(56,76,86))
textSign(staging,'DefenderSign',C.new(345,12,0)*C.Angles(0,math.pi/2,0),V.new(30,4,1),'RESIDENTS / ASSEMBLY',RGB(112,66,47))
local objectives={{name='A_MarketJunction',x=-190,z=23},{name='B_ResidentialCourt',x=0,z=-132},{name='C_FreightYard',x=190,z=132}}
local sites=group('RealityBreakLandmarks')
for index,o in objectives do
    local color=({RGB(83,185,184),RGB(178,119,201),RGB(204,156,73)})[index]
    part(sites,o.name..'_Plinth',V.new(15,0.8,15),C.new(o.x,0.8,o.z),RGB(62,70,71))
    local shard=part(sites,o.name..'_Fracture',V.new(1.2,15,3),C.new(o.x,9,o.z)*C.Angles(0,0,0.18),color,E.Material.Neon)
    shard.CanCollide=false; shard.CanQuery=false; shard.CanTouch=false
    textSign(sites,o.name..'_Marker',C.new(o.x,17,o.z),V.new(9,4,0.4),string.sub(o.name,1,1)..' / BREAK',teal)
end
district:SetAttribute('BR_Prototype','Richmond-inspired fictional district; structural shells remain intact')
district:SetAttribute('BR_Origin',offset)
-- Standalone geometry model contains no scripts. Importing is optional; never automatic.
fs.writeFile(out..'/BR_CityDistrict.rbxm',roblox.serializeModel({district}))

-- Generated test copy: retain original Workspace contents in ServerStorage, unchanged internally.
local archive=I.new('Folder'); archive.Name='BR_OriginalWorkspace_Archive'; archive.Parent=game:GetService('ServerStorage')
for _,child in ws:GetChildren() do
    if child~=district and child.ClassName~='Terrain' and child.ClassName~='Camera' then child.Parent=archive end
end
local spawns=I.new('Folder'); spawns.Name='Spawns'; spawns.Parent=ws
for _,team in {'Attackers','Defenders'} do
    local f=I.new('Folder'); f.Name=team; f.Parent=spawns
    for index=1,4 do
        local x=team=='Attackers' and -340 or 340
        local p=part(f,team..index,V.new(6,0.5,6),C.new(x,1.1,-15+(index-1)*10),RGB(98,116,108))
        p.Transparency=1; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
    end
end
local spawn=I.new('SpawnLocation'); spawn.Name='CityLobbySpawn'; spawn.Size=V.new(8,1,8)
spawn.CFrame=C.new(offset+V.new(-340,1,0)); spawn.Anchored=true; spawn.Neutral=true; spawn.Duration=0; spawn.Transparency=1; spawn.Parent=ws
local objectiveFolder=I.new('Folder'); objectiveFolder.Name='Objectives'; objectiveFolder.Parent=ws
for _,o in objectives do
    local p=part(objectiveFolder,o.name,V.new(14,1,14),C.new(o.x,1.2,o.z),RGB(96,161,146))
    p.Transparency=0.6; p.CanCollide=false; p.CanQuery=false
end
for _,name in {'Destructibles','MonsterSpawns','CorpseFolder'} do local f=I.new('Folder'); f.Name=name; f.Parent=ws end
local sss=game:GetService('ServerScriptService')
assert(not sss:FindFirstChild('CityDistrict'),'Prototype folder collision')
local code=I.new('Folder'); code.Name='CityDistrict'; code.Parent=sss
for _,name in {'Constants','DamageRules','DestructionService'} do
    local m=I.new('ModuleScript'); m.Name=name; m.Source=fs.readFile(source..name..'.lua'); m.Parent=code
end
local gun=sss.Services.GunService
local before=gun.Source
local needle='local DamageService = require(script.Parent:WaitForChild("DamageService"))'
assert(string.find(before,needle,1,true),'GunService dependency anchor missing')
local a,b=string.find(before,needle,1,true)
local patched=string.sub(before,1,b)..'\nlocal CityDestruction = require(script.Parent.Parent:WaitForChild("CityDistrict"):WaitForChild("DestructionService"))'..string.sub(before,b+1)
needle='    local victim = getPlayerFromPart(result.Instance)'
a,b=string.find(patched,needle,1,true); assert(a,'GunService hit anchor missing')
patched=string.sub(patched,1,a-1)..'    if CityDestruction.ApplyHit(result.Instance, weaponDef.damage, result.Position, validDirection) then\n        return\n    end\n\n'..string.sub(patched,a)
gun.Source=patched
fs.writeFile(out..'/GunService.test-only.server.lua',patched)
-- Disable only the legacy lighting script in the generated copy for readable daytime testing.
sss.Services.LightingSetup.Disabled=true
local lighting=game:GetService('Lighting')
lighting.ClockTime=16; lighting.Brightness=2; lighting.ExposureCompensation=0
lighting.Ambient=RGB(105,108,111); lighting.OutdoorAmbient=RGB(132,136,141)
lighting.FogEnd=1500; lighting.FogStart=650
for _,fx in lighting:GetChildren() do
    if fx.ClassName=='Atmosphere' then fx.Density=0.22; fx.Offset=0.15 end
    if fx.ClassName=='ColorCorrectionEffect' then fx.Brightness=0; fx.Contrast=0.08; fx.Saturation=-0.12 end
end
local camera=ws:FindFirstChildOfClass('Camera')
if camera then camera.CFrame=C.lookAt(offset+V.new(460,420,480),offset); camera.Focus=C.new(offset) end
fs.writeFile(out..'/BrokenReality_CityTest.rbxl',roblox.serializePlace(game))
local count,breaks=0,0
for _,p in district:GetDescendants() do if p:IsA('BasePart') then count+=1; if p:GetAttribute('BR_BreakableProfile') then breaks+=1 end end end
fs.writeFile(out..'/layout.json',serde.encode('json',{buildings=records,objectives=objectives,parts=count,breakables=breaks,width=730,depth=600,origin={10000,100,10000}},true))
