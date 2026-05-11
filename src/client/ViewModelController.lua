--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ViewModelController
--
-- Owns the client-side viewmodel: builds a simple programmatic placeholder Model
-- (GunBody, Barrel, LeftArm, RightArm, MuzzleAttachment) and parents it to
-- workspace.CurrentCamera so it follows the camera every frame via PivotTo.
-- Locks the local player to first-person and re-applies the lock on every respawn
-- so TeamService's LoadCharacter() call cannot revert the camera to third person.
-- Shows only during ACTIVE; hidden during LOBBY, PREP, RESULTS, and MATCHEND.
-- Exposes PlayFireAnimation() for GunController to call on each shot.
-- Exposes GetBarrelTipCFrame() so GunController can position the muzzle flash.
--
-- The placeholder is built entirely in code — no ReplicatedStorage asset is
-- required. Replace init() with a model clone once a production-ready asset exists.
--
-- Initialized by ClientInit via loadAndStart() — no PlayerGui needed.
-- init() is called internally from Start() before event listeners are registered.

local Players           = game:GetService("Players")
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

-- Pivot offset of the model relative to the camera (right, down, forward).
local BASE_OFFSET = CFrame.new(0.6, -0.5, -1.5)

-- Recoil snap distance and decay rate.
-- recoilOffset starts at RECOIL_DIST on fire and decays to 0 at RECOIL_RATE studs/s,
-- returning the model to rest in 0.05 s.
local RECOIL_DIST : number = 0.05
local RECOIL_RATE : number = RECOIL_DIST / 0.05

-- Distance in front of the camera used as a muzzle flash fallback when the model
-- has no MuzzleAttachment. Not a gameplay value; kept here rather than Constants.
local MUZZLE_FALLBACK_DIST : number = 1.5

-- ============================================================
-- State
-- ============================================================

local visible      : boolean = false
local recoilOffset : number  = 0

-- ============================================================
-- Controller
-- ============================================================

local ViewModelController = {}
ViewModelController.model = nil :: Model?

-- Builds the placeholder viewmodel from code and parents it to the camera.
-- All parts start hidden (Transparency = 1).
-- If called again (e.g. re-init on respawn), the previous model is destroyed first.
-- Called internally by Start() before any event listeners are registered.
function ViewModelController:init()
    if self.model then
        self.model:Destroy()
        self.model = nil
    end

    local cam = workspace.CurrentCamera

    local container = Instance.new("Model")
    container.Name = "ViewModelPlaceholder"
    container.Parent = cam

    local function makePart(name: string, size: Vector3, color: BrickColor, cf: CFrame): Part
        local p = Instance.new("Part")
        p.Name        = name
        p.Size        = size
        p.BrickColor  = color
        p.CFrame      = cf
        p.CanCollide  = false
        p.CanQuery    = false
        p.CastShadow  = false
        p.Anchored    = false
        p.Transparency = 1
        p.Parent      = container
        return p
    end

    local darkGrey   = BrickColor.new("Dark grey")
    local pastelBrown = BrickColor.new("Pastel brown")

    -- All offsets are relative to the model pivot (world origin at creation time).
    -- PivotTo repositions the whole model so relative layout is preserved.

    -- Main gun body centred in view, slightly forward of pivot.
    makePart("GunBody", Vector3.new(0.25, 0.18, 1.2), darkGrey, CFrame.new(0, 0, -0.3))

    -- Thin barrel extending forward from the gun body, raised slightly.
    local barrel = makePart("Barrel", Vector3.new(0.07, 0.07, 0.5), darkGrey, CFrame.new(0, 0.04, -0.9))

    -- Right hand at the grip, behind and below the gun body.
    makePart("RightArm", Vector3.new(0.35, 0.35, 0.9), pastelBrown, CFrame.new(0.12, -0.22, 0.15))

    -- Left hand at the handguard, forward and below the gun body.
    makePart("LeftArm",  Vector3.new(0.35, 0.35, 0.7), pastelBrown, CFrame.new(-0.05, -0.18, -0.45))

    -- MuzzleAttachment at the front tip of the barrel.
    -- Barrel length is 0.5, so local tip is at Z = -0.25.
    local muzzle = Instance.new("Attachment")
    muzzle.Name     = "MuzzleAttachment"
    muzzle.Position = Vector3.new(0, 0, -0.25)
    muzzle.Parent   = barrel

    self.model = container
    visible = false
    Logger.debug("[ViewModelController] Programmatic placeholder built")
end

function ViewModelController:Start()
    self:init()

    -- init() always succeeds (no external assets); self.model is guaranteed here.
    -- Guard kept defensively in case init() is extended later with a failure path.
    if not self.model then
        return
    end

    local localPlayer = Players.LocalPlayer
    localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

    -- Re-build the viewmodel and re-apply the camera lock after each respawn.
    -- TeamService calls player:LoadCharacter() at the start of every PREP which
    -- would otherwise revert CameraMode to the default (Classic / third-person).
    localPlayer.CharacterAdded:Connect(function(_character: Model)
        self:init()
        localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
        Logger.debug("[ViewModelController] Model rebuilt on character respawn")
    end)

    -- Sets Transparency on every BasePart descendant of the model.
    -- Hiding: ALL BaseParts → Transparency 1.
    -- Showing: all BaseParts → Transparency 0.
    -- Reads self.model per-call so re-builds after CharacterAdded are always used.
    local function setVisibility(show: boolean)
        local m = self.model
        if not m then return end
        local count = 0
        for _, desc in ipairs(m:GetDescendants()) do
            if desc:IsA("BasePart") then
                (desc :: BasePart).Transparency = show and 0 or 1
                count += 1
            end
        end
        Logger.debug(string.format("[ViewModelController] setVisibility(%s) — %d parts", tostring(show), count))
    end

    -- Phase listener: show only during ACTIVE; hide during all other phases.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local show    = (payload.phase == Constants.Phase.ACTIVE)
        visible = show
        setVisibility(show)
    end)

    -- RenderStepped: reposition the model pivot every frame to follow the camera.
    -- Skipped entirely when not visible to avoid unnecessary PivotTo calls.
    -- Reads self.model per-call so re-builds after CharacterAdded are always used.
    RunService.RenderStepped:Connect(function(dt: number)
        if not visible then
            return
        end
        local m = self.model
        if not m then return end

        -- Decay recoil offset back to zero at RECOIL_RATE studs/second.
        if recoilOffset > 0 then
            recoilOffset = math.max(0, recoilOffset - dt * RECOIL_RATE)
        end

        local cam = workspace.CurrentCamera
        m:PivotTo(cam.CFrame * BASE_OFFSET * CFrame.new(0, 0, recoilOffset))
    end)

    Logger.debug("[ViewModelController] Ready")
end

-- Called by GunController immediately after WeaponFired:FireServer().
-- Nudges the model back by RECOIL_DIST and begins the decay back to rest position.
function ViewModelController:PlayFireAnimation()
    local model = self.model
    if not model then
        return
    end
    recoilOffset = RECOIL_DIST
    -- Apply the snap immediately so the first rendered frame shows the kicked position.
    model:PivotTo(model:GetPivot() * CFrame.new(0, 0, recoilOffset))
end

-- Returns a CFrame at the barrel muzzle tip for muzzle flash placement.
-- Reads WorldPosition from MuzzleAttachment if the model has one.
-- Falls back to a point 1.5 studs in front of the camera with a warning.
function ViewModelController:GetBarrelTipCFrame(): CFrame
    local model = self.model
    if model then
        local attachment = model:FindFirstChild("MuzzleAttachment", true)
        if attachment and attachment:IsA("Attachment") then
            return CFrame.new((attachment :: Attachment).WorldPosition)
        end
    end
    Logger.warn("[ViewModelController] GetBarrelTipCFrame: MuzzleAttachment not found — using camera fallback")
    local cam = workspace.CurrentCamera
    return CFrame.new(cam.CFrame.Position + cam.CFrame.LookVector * MUZZLE_FALLBACK_DIST)
end

return ViewModelController
