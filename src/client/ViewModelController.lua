--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ViewModelController
--
-- Owns the client-side viewmodel: clones the SCAR model from
-- ReplicatedStorage/ViewModels and parents it to workspace.CurrentCamera so it
-- follows the camera every frame via PivotTo.
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

-- Pivot offset of the model relative to the camera (right, down, forward).
-- Compensates for the Troy Defense AR internal layout (~2.6 studs left, ~1.3 below pivot).
-- May need visual fine-tuning once the model pivot is confirmed in Studio. See DEBT-028.
local BASE_OFFSET = CFrame.new(3.2, 0.9, -1.2)

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

-- Clones the SCAR model from ReplicatedStorage/ViewModels and parents it to the
-- camera. All BasePart descendants are hidden (Transparency = 1) on creation.
-- If called again (e.g. re-init), the previous model is destroyed first.
-- Called internally by Start() before any event listeners are registered.
function ViewModelController:init()
    -- Clean up any previous model so re-initialization does not orphan instances.
    if self.model then
        self.model:Destroy()
        self.model = nil
    end

    local viewModels = ReplicatedStorage:WaitForChild("ViewModels", 10)
    if not viewModels then
        Logger.warn("[ViewModelController] ViewModels folder not found in ReplicatedStorage after 10s — check Rojo sync")
        return
    end
    local scarModel = viewModels:WaitForChild("SCAR", 10)
    if not scarModel then
        Logger.warn("[ViewModelController] SCAR model not found after 10s — check ReplicatedStorage/ViewModels/SCAR exists")
        return
    end
    local clone = (scarModel :: Model):Clone()
    clone.Parent     = workspace.CurrentCamera
    self.model       = clone

    -- Start fully hidden; the phase listener in Start() will show during ACTIVE.
    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") then
            (desc :: BasePart).Transparency = 1
        end
    end

    Logger.debug("[ViewModelController] SCAR model cloned and hidden")
end

function ViewModelController:Start()
    self:init()

    -- If init() returned early because the model assets were missing, the
    -- controller is inert. Return cleanly so other controllers still initialize.
    if not self.model then
        return
    end

    local localPlayer = Players.LocalPlayer
    localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

    -- Re-clone the viewmodel and re-apply the camera lock after each respawn.
    -- TeamService calls player:LoadCharacter() at the start of every PREP which
    -- would otherwise revert CameraMode to the default (Classic / third-person).
    localPlayer.CharacterAdded:Connect(function(_character: Model)
        self:init()
        localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
        Logger.debug("[ViewModelController] Model re-cloned on character respawn")
    end)

    -- Sets Transparency on every BasePart descendant of the model.
    -- Hiding: ALL BaseParts → Transparency 1.
    -- Showing: all BaseParts → Transparency 0, EXCEPT HumanoidRootPart (physics
    -- anchor) and FakeCamera (camera reference part) which must always stay
    -- invisible regardless of phase — they are structural, not visual.
    -- Reads self.model per-call so re-clones after CharacterAdded are always used.
    local function setVisibility(show: boolean)
        local m = self.model
        if not m then return end
        for _, desc in ipairs(m:GetDescendants()) do
            if desc:IsA("BasePart") then
                local part = desc :: BasePart
                local alwaysHidden = part.Name == "HumanoidRootPart" or part.Name == "FakeCamera"
                part.Transparency = (show and not alwaysHidden) and 0 or 1
            end
        end
    end

    -- Phase listener: show only during ACTIVE; hide during all other phases.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        local payload = raw :: { phase: string }
        local show    = (payload.phase == Constants.Phase.ACTIVE)
        if show ~= visible then
            visible = show
            setVisibility(visible)
        end
    end)

    -- RenderStepped: reposition the model pivot every frame to follow the camera.
    -- Skipped entirely when not visible to avoid unnecessary PivotTo calls.
    -- Reads self.model per-call so re-clones after CharacterAdded are always used.
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
