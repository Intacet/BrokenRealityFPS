--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > SpectatorFlyController
--
-- Free-fly / noclip spectating, granted only once the server confirms a
-- TeleportToArena request actually landed (AIService.server.lua's teleport
-- handler; requested by LoadoutMenu's "WATCH AI ARENA" button) — never on the
-- raw client button press. This is a dev/spectator convenience, not an
-- anti-cheat boundary: nothing stops a modified client from granting itself
-- fly locally regardless, same trust level as every other purely-cosmetic
-- client movement/camera system in this game.
--
-- Movement: Humanoid.PlatformStand freezes normal ground locomotion; every
-- RenderStepped this controller instead drives HumanoidRootPart.CFrame
-- directly from camera-relative WASD + ascend/descend input
-- (Constants.SPECTATOR_FLY). Every character BasePart's CanCollide is
-- disabled while flying so cover/walls/other grunts never block the camera.
-- TOGGLE_KEY (default F) switches fly on/off at any time once granted — the
-- grant persists for the rest of that Character's life; a fresh respawn is a
-- new Character (CharacterAdded resets all local state), so it never carries
-- over past a death or round-start teleport.
--
-- Initialized by ClientInit via loadInitAndStart (init(playerGui) then Start()).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local TeleportToArena = Remotes:WaitForChild("TeleportToArena") :: RemoteEvent

local FLY   = Constants.SPECTATOR_FLY :: any
local ARENA = Constants.AI_ARENA :: any

local LocalPlayer = Players.LocalPlayer

local SpectatorFlyController = {}

-- ============================================================
-- State
-- ============================================================

local granted = false -- true once the server has ever confirmed a teleport for the CURRENT character
local flying  = false
local hint: TextLabel? = nil
local renderConn: RBXScriptConnection? = nil
local originalCanCollide: { [BasePart]: boolean } = {}
local currentRoot: BasePart? = nil

-- ============================================================
-- Movement
-- ============================================================

local function onRenderStepped(dt: number)
    if not flying or currentRoot == nil then
        return
    end
    local camera = workspace.CurrentCamera
    if camera == nil then
        return
    end
    local root = currentRoot :: BasePart
    local camCF = camera.CFrame

    local moveDir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        moveDir += camCF.LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        moveDir -= camCF.LookVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        moveDir += camCF.RightVector
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        moveDir -= camCF.RightVector
    end
    if UserInputService:IsKeyDown(FLY.ASCEND_KEY) then
        moveDir += Vector3.yAxis
    end
    if UserInputService:IsKeyDown(FLY.DESCEND_KEY) then
        moveDir -= Vector3.yAxis
    end

    if moveDir.Magnitude < 1e-4 then
        return
    end

    local speed = if UserInputService:IsKeyDown(FLY.BOOST_KEY)
        then FLY.BOOST_SPEED :: number
        else FLY.SPEED :: number
    local newPos = root.Position + moveDir.Unit * speed * dt
    root.CFrame = CFrame.new(newPos, newPos + camCF.LookVector)
end

-- ============================================================
-- GUI
-- ============================================================

function SpectatorFlyController:init(playerGui: PlayerGui): ()
    if FLY.ENABLED ~= true then
        return
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "SpectatorFlyHint"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true

    local label = Instance.new("TextLabel")
    label.Name                   = "Hint"
    label.AnchorPoint            = Vector2.new(0.5, 1)
    label.Position               = UDim2.new(0.5, 0, 1, -12)
    label.Size                   = UDim2.fromOffset(620, 20)
    label.BackgroundTransparency = 1
    label.Font                   = Enum.Font.GothamBold
    label.TextSize               = 14
    label.TextColor3             = Color3.fromRGB(235, 235, 235)
    label.TextStrokeTransparency = 0.4
    label.Text = string.format(
        "SPECTATING — WASD move, %s/%s up/down, hold %s to boost, %s to toggle fly",
        (FLY.ASCEND_KEY :: EnumItem).Name,
        (FLY.DESCEND_KEY :: EnumItem).Name,
        (FLY.BOOST_KEY :: EnumItem).Name,
        (FLY.TOGGLE_KEY :: EnumItem).Name
    )
    label.Visible = false
    label.Parent  = screen

    hint = label
    screen.Parent = playerGui
end

-- ============================================================
-- Fly toggle
-- ============================================================

local function setFlying(on: boolean): ()
    if on == flying then
        return
    end
    local character = LocalPlayer.Character
    if character == nil then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if humanoid == nil or root == nil then
        return
    end

    flying = on
    currentRoot = root

    if on then
        humanoid.PlatformStand = true
        table.clear(originalCanCollide)
        for _, inst in ipairs(character:GetDescendants()) do
            if inst:IsA("BasePart") then
                originalCanCollide[inst] = inst.CanCollide
                inst.CanCollide = false
            end
        end
        if hint ~= nil then
            hint.Visible = true
        end
        if renderConn == nil then
            renderConn = RunService.RenderStepped:Connect(onRenderStepped)
        end
        Logger.debug("[SpectatorFlyController] fly ON")
    else
        -- Safety net: if we've flown far outside the arena footprint (or below
        -- its ground), land back at its center instead of falling into the void.
        local origin = ARENA.ORIGIN :: Vector3
        local flat = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
        if flat.Magnitude > 120 or root.Position.Y < origin.Y - 10 then
            root.CFrame = CFrame.new(origin + Vector3.new(0, 10, 0))
        end
        humanoid.PlatformStand = false
        for part, canCollide in pairs(originalCanCollide) do
            if part.Parent ~= nil then
                part.CanCollide = canCollide
            end
        end
        table.clear(originalCanCollide)
        if hint ~= nil then
            hint.Visible = false
        end
        if renderConn ~= nil then
            renderConn:Disconnect()
            renderConn = nil
        end
        Logger.debug("[SpectatorFlyController] fly OFF")
    end
end

function SpectatorFlyController:Start(): ()
    if FLY.ENABLED ~= true then
        return
    end

    local function resetForNewCharacter(): ()
        granted = false
        flying = false
        currentRoot = nil
        table.clear(originalCanCollide)
        if renderConn ~= nil then
            renderConn:Disconnect()
            renderConn = nil
        end
        if hint ~= nil then
            hint.Visible = false
        end
    end

    LocalPlayer.CharacterAdded:Connect(function()
        resetForNewCharacter()
    end)
    if LocalPlayer.Character ~= nil then
        resetForNewCharacter()
    end

    -- The server only fires this back after it has actually moved the
    -- character above the arena — this is what grants fly, never the button
    -- click itself.
    TeleportToArena.OnClientEvent:Connect(function()
        granted = true
        setFlying(true)
        Logger.debug("[SpectatorFlyController] fly granted (teleported to AI arena)")
    end)

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed or not granted then
            return
        end
        if input.KeyCode == FLY.TOGGLE_KEY then
            setFlying(not flying)
        end
    end)

    Logger.debug("[SpectatorFlyController] started")
end

return SpectatorFlyController
