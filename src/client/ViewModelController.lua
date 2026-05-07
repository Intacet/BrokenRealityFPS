--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ViewModelController
--
-- Owns the client-side viewmodel: three Parts parented to the camera that follow it
-- every frame and represent the player's held weapon.
-- Shows only during ACTIVE; hidden during LOBBY, PREP, RESULTS, and MATCHEND.
-- Exposes PlayFireAnimation() for GunController to call on each shot.
-- Exposes GetBarrelTipCFrame() so GunController can position the muzzle flash.
--
-- Initialized by ClientInit via loadAndStart() — no PlayerGui needed.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

-- ============================================================
-- Configuration
-- ============================================================

-- Position of the gun body relative to the camera (right, down, forward).
local BASE_OFFSET = CFrame.new(0.6, -0.4, -1.2)

-- How far the gun body snaps back on fire, and how long it takes to return.
local RECOIL_DIST : number = 0.05  -- studs
local RECOIL_RATE : number = RECOIL_DIST / 0.05  -- studs/second (returns in 0.05 s)

-- Dark grey BrickColor used for all viewmodel parts.
local VM_COLOR = BrickColor.new("Dark grey")

-- Barrel geometry: cylinder aligned to the gun's forward axis.
-- Center offset from GunBody: (right=0, up=0.04, forward=0.55 past GunBody front).
-- Tip offset from GunBody: (right=0, up=0.04, forward=0.85 past GunBody center).
local BARREL_CENTER_OFFSET = CFrame.new(0, 0.04, -0.55) * CFrame.Angles(math.pi / 2, 0, 0)
local BARREL_TIP_OFFSET    = CFrame.new(0, 0.04, -0.85)

-- Grip offset from GunBody center (below and slightly toward the rear).
local GRIP_OFFSET = CFrame.new(0, -0.225, 0.1)

-- ============================================================
-- State
-- ============================================================

-- Parts created in Start(); referenced in RenderStepped and public methods.
local gunBody : Part
local barrel  : Part
local grip    : Part

local visible      : boolean = false
local recoilOffset : number  = 0

-- ============================================================
-- Private helpers
-- ============================================================

local function makePart(name: string, size: Vector3): Part
    local p          = Instance.new("Part")
    p.Name           = name
    p.Size           = size
    p.Anchored       = false
    p.CanCollide     = false
    p.CastShadow     = false
    p.BrickColor     = VM_COLOR
    p.Parent         = workspace.CurrentCamera
    return p
end

local function setVisibility(show: boolean)
    local t = show and 0 or 1
    gunBody.Transparency = t
    barrel.Transparency  = t
    grip.Transparency    = t
end

-- ============================================================
-- Controller
-- ============================================================

local ViewModelController = {}

function ViewModelController:Start()
    -- Create the three viewmodel parts and parent them to the camera.
    gunBody = makePart("GunBody", Vector3.new(0.8, 0.2, 0.5))
    barrel  = makePart("Barrel",  Vector3.new(0.08, 0.6, 0.08))
    grip    = makePart("Grip",    Vector3.new(0.15, 0.25, 0.15))

    -- Cylinder SpecialMesh so the barrel renders as a cylinder rather than a block.
    -- The mesh runs along the Part's Y axis; BARREL_CENTER_OFFSET rotates Y to point forward.
    local cylinderMesh      = Instance.new("SpecialMesh")
    cylinderMesh.MeshType   = Enum.MeshType.Cylinder
    cylinderMesh.Parent     = barrel

    -- Start fully hidden; phase listener below will show during ACTIVE.
    setVisibility(false)

    -- Phase listener: show during ACTIVE only.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local show    = (payload.phase == Constants.Phase.ACTIVE)
        if show ~= visible then
            visible = show
            setVisibility(visible)
        end
    end)

    -- RenderStepped: keep parts attached to camera every frame.
    -- deltaTime is used to smoothly return the gun to rest after recoil.
    RunService.RenderStepped:Connect(function(dt: number)
        if not visible then
            return
        end

        -- Decay recoil back to zero at RECOIL_RATE studs/second.
        if recoilOffset > 0 then
            recoilOffset = math.max(0, recoilOffset - dt * RECOIL_RATE)
        end

        local cam      = workspace.CurrentCamera
        -- Positive Z in camera local space is behind the camera (+Z = away from look dir).
        local bodyBase = cam.CFrame * BASE_OFFSET * CFrame.new(0, 0, recoilOffset)

        gunBody.CFrame = bodyBase
        barrel.CFrame  = bodyBase * BARREL_CENTER_OFFSET
        grip.CFrame    = bodyBase * GRIP_OFFSET
    end)

    Logger.debug("[ViewModelController] Ready")
end

-- Called by GunController immediately after WeaponFired:FireServer().
-- Snaps recoilOffset to RECOIL_DIST; RenderStepped lerps it back to 0.
function ViewModelController:PlayFireAnimation()
    recoilOffset = RECOIL_DIST
end

-- Returns the world CFrame at the barrel muzzle tip.
-- Used by GunController to position the muzzle flash Part.
function ViewModelController:GetBarrelTipCFrame(): CFrame
    return gunBody.CFrame * BARREL_TIP_OFFSET
end

return ViewModelController
