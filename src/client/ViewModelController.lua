--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ViewModelController
--
-- Owns the client-side viewmodel: clones ReplicatedStorage/ViewModels/AR15 (a Model
-- containing the gun mesh parts, arm MeshParts, WeldConstraints, and a Root PrimaryPart)
-- and parents it to workspace.CurrentCamera so it follows the camera every frame via PivotTo.
-- Falls back to a programmatic placeholder if the AR15 asset is missing from ReplicatedStorage.
-- Locks the local player to first-person and re-applies the lock on every respawn
-- so TeamService's LoadCharacter() call cannot revert the camera to third person.
-- Shows only during ACTIVE; hidden during LOBBY, PREP, RESULTS, and MATCHEND.
-- Exposes PlayFireAnimation() for GunController to call on each shot.
-- Exposes GetBarrelTipCFrame() so GunController can position the muzzle flash.
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

-- BASE_OFFSET: pivot (PrimaryPart) position of the model relative to the camera.
-- Real AR15 model — Root is the camera-local origin; all geometry is baked into the
-- part positions relative to Root.  No additional offset needed.
local REAL_MODEL_OFFSET : CFrame = CFrame.new(0, 0, 0)

-- Programmatic placeholder — the model pivot sits at the visual gun-body centre,
-- so we shift it right/down/forward to appear in the corner of the screen.
local PLACEHOLDER_OFFSET : CFrame = CFrame.new(0.6, -0.5, -1.5)

-- Set by init() based on which model loaded.  Starts at the placeholder value
-- so any code that runs before init() gets a safe default.
local BASE_OFFSET : CFrame = PLACEHOLDER_OFFSET

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

-- Attempts to clone ReplicatedStorage/ViewModels/AR15 and parent it to the camera.
-- Falls back to building a programmatic placeholder if the asset is absent.
-- All parts start hidden (Transparency = 1) via setVisibility called on the
-- next RoundStateChanged event.
-- Destroys any previously built model before creating a new one so re-init is safe.
-- Called internally by Start() before any event listeners are registered.
function ViewModelController:init()
    if self.model then
        self.model:Destroy()
        self.model = nil
    end

    local cam = workspace.CurrentCamera

    -- ── Attempt 1: clone AR15 production asset ────────────────────────────────
    local viewModels = ReplicatedStorage:FindFirstChild("ViewModels")
    local ar15Asset  = viewModels and viewModels:FindFirstChild("AR15")
    if ar15Asset then
        local clone = ar15Asset:Clone()
        -- Hide all parts BEFORE parenting so there is no single-frame flash at the
        -- stored world positions (which are the build-time positions, not camera-local).
        -- setVisibility(true) will be called by the RoundStateChanged listener when
        -- the ACTIVE phase begins.
        for _, desc in ipairs(clone:GetDescendants()) do
            if desc:IsA("BasePart") then
                (desc :: BasePart).Transparency = 1
            end
        end
        clone.Parent = cam
        self.model  = clone
        BASE_OFFSET = REAL_MODEL_OFFSET
        -- Reset visible so the next RoundStateChanged always fires setVisibility,
        -- even if the phase has not changed since the previous character load.
        visible = false
        Logger.debug("[ViewModelController] AR15 model cloned from ReplicatedStorage")
        return
    end

    -- ── Attempt 2: programmatic placeholder ───────────────────────────────────
    Logger.warn("[ViewModelController] init: ReplicatedStorage/ViewModels/AR15 not found — using placeholder")
    BASE_OFFSET = PLACEHOLDER_OFFSET

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

    local darkGrey    = BrickColor.new("Dark grey")
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
    -- Reset visible so the next RoundStateChanged always calls setVisibility,
    -- even if the phase hasn't changed since the previous character load.
    visible = false
    Logger.debug("[ViewModelController] Programmatic placeholder built")
end

function ViewModelController:Start()
    self:init()

    -- init() always sets self.model (either the AR15 clone or the placeholder).
    -- Guard kept defensively: if init() is extended with a hard-failure path in
    -- future, this prevents a nil-model crash from propagating to event listeners.
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
        Logger.debug(string.format("[ViewModelController] setVisibility(%s)", tostring(show)))
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
    -- Guard removed intentionally: after CharacterAdded re-runs init(), visible is
    -- reset to false, so the next RoundStateChanged must always call setVisibility
    -- even when the phase hasn't changed (e.g. ACTIVE fires again after respawn).
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
