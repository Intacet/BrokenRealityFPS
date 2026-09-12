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

-- Bugfix (2026-09-11): the original version only wrote root.CFrame when
-- moveDir was non-zero, and never touched the part's velocity. Gravity keeps
-- accelerating an unanchored BasePart's AssemblyLinearVelocity every physics
-- step regardless of PlatformStand or how often a script repositions it — so
-- standing still (or even moving) let that velocity build up between frames,
-- making "flying" feel like a losing fight against constantly falling/
-- sinking, up to and including feeling like flight "doesn't work" at all.
-- Now: runs — and re-pins position — every frame while flying, moved or not,
-- and explicitly zeroes both linear and angular velocity every frame so
-- gravity/physics never gets a chance to accumulate between writes.
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

    local speed = if UserInputService:IsKeyDown(FLY.BOOST_KEY)
        then FLY.BOOST_SPEED :: number
        else FLY.SPEED :: number
    local delta = if moveDir.Magnitude > 1e-4 then moveDir.Unit * speed * dt else Vector3.zero
    local newPos = root.Position + delta
    root.CFrame = CFrame.new(newPos, newPos + camCF.LookVector)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
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
        -- Bugfix (2026-09-11): PlatformStand alone stops WASD-driven walking,
        -- but the Humanoid's own state machine (Running/Freefall/Landed, each
        -- with its own physics/animation behavior) can still be active and
        -- fighting for control. Forcing the Physics state hands the rig fully
        -- over to direct script control — the standard technique for a custom
        -- fly/noclip controller like this one.
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        end)
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
        -- Hands control back to the normal Humanoid state machine (matches
        -- the ChangeState(Physics) call above) rather than leaving it stuck.
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
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
