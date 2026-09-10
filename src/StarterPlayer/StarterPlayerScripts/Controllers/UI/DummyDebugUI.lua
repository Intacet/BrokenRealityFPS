--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > DummyDebugUI
--
-- Developer-only overlay for the damage test dummies. Built ONLY when RunService:IsStudio()
-- or the local UserId is in Constants.DEV_USER_IDS — for everyone else init() is a no-op and
-- no GUI is created.
--
-- Shows, per tagged dummy: current HP, last damage (amount / region / source / type), per-
-- limb state, infinite-health flag, ragdoll flag. Buttons: Reset, Heal, Infinite (toggle),
-- Blood (toggle), Hitboxes (local viz toggle).
--
-- State comes from DummyDevState (server, throttled). Commands go up via DummyDevCommand.
-- Hitbox visualization is drawn locally from the tagged models — it sends nothing and
-- creates no server instances.
--
-- Initialized by ClientInit via loadInitAndStart (init(playerGui) then Start()).

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local CollectionService  = game:GetService("CollectionService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local DummyDevCommand = Remotes:WaitForChild("DummyDevCommand") :: RemoteEvent
local DummyDevState   = Remotes:WaitForChild("DummyDevState")   :: RemoteEvent

local LocalPlayer = Players.LocalPlayer

local DummyDebugUI = {}

-- ============================================================
-- Config / state
-- ============================================================

local enabled       = false
local infiniteOn    = false
local hitboxOn      = false

local screen: ScreenGui
local listFrame: Frame
local bloodBtn: TextButton
local infBtn: TextButton
local hitboxBtn: TextButton

local hitboxAdorns: { SelectionBox } = {}

local REGION_COLORS: { [string]: Color3 } = {
    Head     = Color3.fromRGB(235, 90, 90),
    Torso    = Color3.fromRGB(240, 200, 90),
    LeftArm  = Color3.fromRGB(120, 190, 240),
    RightArm = Color3.fromRGB(120, 190, 240),
    LeftLeg  = Color3.fromRGB(150, 220, 150),
    RightLeg = Color3.fromRGB(150, 220, 150),
}

local PART_REGION: { [string]: string } = {
    ["Head"] = "Head", ["Torso"] = "Torso", ["HumanoidRootPart"] = "Torso",
    ["Left Arm"] = "LeftArm", ["Right Arm"] = "RightArm",
    ["Left Leg"] = "LeftLeg", ["Right Leg"] = "RightLeg",
}

-- ============================================================
-- Helpers
-- ============================================================

local function isDeveloper(): boolean
    if RunService:IsStudio() then
        return true
    end
    return (Constants.DEV_USER_IDS :: { [number]: boolean })[LocalPlayer.UserId] == true
end

local function makeButton(text: string, order: number): TextButton
    local b = Instance.new("TextButton")
    b.Name              = text .. "Btn"
    b.Size              = UDim2.new(0, 96, 0, 24)
    b.LayoutOrder       = order
    b.BackgroundColor3  = Color3.fromRGB(24, 24, 24)
    b.BackgroundTransparency = 0.25
    b.BorderSizePixel   = 0
    b.TextColor3        = Color3.new(1, 1, 1)
    b.Font              = Enum.Font.Code
    b.TextSize          = 13
    b.Text              = text
    b.AutoButtonColor   = true
    return b
end

-- ── Hitbox visualization (local only) ───────────────────────────────────────
local function clearHitboxes()
    for _, adorn in ipairs(hitboxAdorns) do
        adorn:Destroy()
    end
    table.clear(hitboxAdorns)
end

local function refreshHitboxes()
    clearHitboxes()
    if not hitboxOn then
        return
    end
    for _, model in ipairs(CollectionService:GetTagged(Constants.TAG_DAMAGE_DUMMY :: string)) do
        if model:IsA("Model") then
            for _, part in ipairs(model:GetChildren()) do
                if part:IsA("BasePart") then
                    local region = PART_REGION[part.Name]
                    local box = Instance.new("SelectionBox")
                    box.Adornee        = part
                    box.LineThickness  = 0.03
                    box.Transparency   = 0.35
                    box.SurfaceTransparency = 0.85
                    box.Color3         = region and (REGION_COLORS[region] or Color3.new(1, 1, 1)) or Color3.fromRGB(150, 150, 150)
                    box.SurfaceColor3  = box.Color3
                    box.Parent         = part
                    table.insert(hitboxAdorns, box)
                end
            end
        end
    end
end

-- ============================================================
-- Rendering
-- ============================================================

local function clearRows()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function addDummyRow(data: { [string]: any }, order: number)
    local row = Instance.new("Frame")
    row.Name             = "Dummy_" .. tostring(data.id)
    row.Size             = UDim2.new(1, 0, 0, 78)
    row.LayoutOrder      = order
    row.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
    row.BackgroundTransparency = 0.35
    row.BorderSizePixel  = 0
    row.Parent           = listFrame

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingTop  = UDim.new(0, 4)
    pad.Parent      = row

    local header = Instance.new("TextLabel")
    header.Size                   = UDim2.new(1, -8, 0, 16)
    header.BackgroundTransparency = 1
    header.Font                   = Enum.Font.Code
    header.TextSize               = 13
    header.TextXAlignment         = Enum.TextXAlignment.Left
    header.TextColor3             = Color3.new(1, 1, 1)
    local hp = string.format("%d/%d", data.health, data.maxHealth)
    header.Text = string.format("%s   HP %s%s%s", data.name, hp,
        data.infinite and "  [INF]" or "",
        data.ragdolled and "  [RAGDOLL]" or "")
    header.Parent = row

    local last = Instance.new("TextLabel")
    last.Position                 = UDim2.new(0, 0, 0, 18)
    last.Size                     = UDim2.new(1, -8, 0, 16)
    last.BackgroundTransparency   = 1
    last.Font                     = Enum.Font.Code
    last.TextSize                 = 12
    last.TextXAlignment           = Enum.TextXAlignment.Left
    last.TextColor3               = Color3.fromRGB(200, 200, 200)
    if data.lastHit ~= nil then
        last.Text = string.format("last: %.0f  %s  (%s / %s)",
            data.lastHit.amount, data.lastHit.region,
            data.lastHit.source ~= "" and data.lastHit.source or "?",
            data.lastHit.damageType)
    else
        last.Text = "last: —"
    end
    last.Parent = row

    local limbs = Instance.new("TextLabel")
    limbs.Position               = UDim2.new(0, 0, 0, 36)
    limbs.Size                   = UDim2.new(1, -8, 0, 36)
    limbs.BackgroundTransparency = 1
    limbs.Font                   = Enum.Font.Code
    limbs.TextSize               = 11
    limbs.TextXAlignment         = Enum.TextXAlignment.Left
    limbs.TextYAlignment         = Enum.TextYAlignment.Top
    limbs.TextColor3             = Color3.fromRGB(170, 170, 170)
    limbs.TextWrapped            = true
    local order2 = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
    local byRegion: { [string]: any } = {}
    for _, l in ipairs(data.limbs) do byRegion[l.region] = l end
    local parts: { string } = {}
    for _, region in ipairs(order2) do
        local l = byRegion[region]
        if l ~= nil then
            table.insert(parts, string.format("%s %d%s", region, l.health, l.destroyed and "x" or ""))
        end
    end
    limbs.Text = table.concat(parts, "  ")
    limbs.Parent = row
end

local function render(state: { [string]: any })
    if not enabled then
        return
    end
    bloodBtn.Text = state.bloodEnabled and "Blood: ON" or "Blood: OFF"
    infBtn.Text   = "Infinite: " .. (infiniteOn and "ON" or "OFF")
    hitboxBtn.Text = "Hitboxes: " .. (hitboxOn and "ON" or "OFF")

    clearRows()
    local list = state.dummies or {}
    if #list == 0 then
        local none = Instance.new("Frame")
        none.Size = UDim2.new(1, 0, 0, 20)
        none.BackgroundTransparency = 1
        none.LayoutOrder = 1
        none.Parent = listFrame
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 12
        lbl.TextColor3 = Color3.fromRGB(150, 150, 150)
        lbl.Text = "no tagged dummies (run scripts/Build-TestDummy.luau)"
        lbl.Parent = none
    else
        for i, data in ipairs(list) do
            addDummyRow(data, i)
        end
    end
end

-- ============================================================
-- init / Start
-- ============================================================

function DummyDebugUI:init(playerGui: PlayerGui)
    if not isDeveloper() then
        return  -- no GUI for non-developers
    end
    enabled = true

    screen = Instance.new("ScreenGui")
    screen.Name            = "DummyDebugUI"
    screen.ResetOnSpawn    = false
    screen.IgnoreGuiInset  = true
    screen.DisplayOrder    = 50
    screen.Parent          = playerGui

    local panel = Instance.new("Frame")
    panel.Name              = "Panel"
    panel.AnchorPoint       = Vector2.new(1, 0)
    panel.Position          = UDim2.new(1, -12, 0, 12)
    panel.Size              = UDim2.new(0, 320, 0, 320)
    panel.BackgroundColor3  = Color3.fromRGB(8, 8, 8)
    panel.BackgroundTransparency = 0.35
    panel.BorderSizePixel   = 0
    panel.Parent            = screen

    local title = Instance.new("TextLabel")
    title.Size                   = UDim2.new(1, 0, 0, 22)
    title.BackgroundColor3       = Color3.fromRGB(20, 20, 20)
    title.BackgroundTransparency = 0.2
    title.BorderSizePixel        = 0
    title.Font                   = Enum.Font.Code
    title.TextSize               = 13
    title.TextColor3             = Color3.fromRGB(240, 200, 90)
    title.Text                   = "DUMMY DEBUG"
    title.Parent                 = panel

    local btnRow = Instance.new("Frame")
    btnRow.Position               = UDim2.new(0, 6, 0, 26)
    btnRow.Size                   = UDim2.new(1, -12, 0, 54)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent                 = panel
    local grid = Instance.new("UIGridLayout")
    grid.CellSize      = UDim2.new(0, 100, 0, 24)
    grid.CellPadding   = UDim2.new(0, 4, 0, 4)
    grid.Parent        = btnRow

    local resetBtn = makeButton("Reset", 1)
    resetBtn.Parent = btnRow
    local healBtn  = makeButton("Heal", 2)
    healBtn.Parent  = btnRow
    infBtn    = makeButton("Infinite: OFF", 3)
    infBtn.Parent = btnRow
    bloodBtn  = makeButton("Blood: ON", 4)
    bloodBtn.Parent = btnRow
    hitboxBtn = makeButton("Hitboxes: OFF", 5)
    hitboxBtn.Parent = btnRow

    listFrame = Instance.new("Frame")
    listFrame.Name                 = "List"
    listFrame.Position             = UDim2.new(0, 6, 0, 84)
    listFrame.Size                 = UDim2.new(1, -12, 1, -90)
    listFrame.BackgroundTransparency = 1
    listFrame.Parent               = panel
    local vlist = Instance.new("UIListLayout")
    vlist.Padding   = UDim.new(0, 4)
    vlist.SortOrder = Enum.SortOrder.LayoutOrder
    vlist.Parent    = listFrame

    resetBtn.Activated:Connect(function()
        DummyDevCommand:FireServer("reset")
    end)
    healBtn.Activated:Connect(function()
        DummyDevCommand:FireServer("heal")
    end)
    infBtn.Activated:Connect(function()
        infiniteOn = not infiniteOn
        DummyDevCommand:FireServer("infinite", infiniteOn)
    end)
    bloodBtn.Activated:Connect(function()
        local turningOn = bloodBtn.Text ~= "Blood: ON"
        DummyDevCommand:FireServer("blood", turningOn)
    end)
    hitboxBtn.Activated:Connect(function()
        hitboxOn = not hitboxOn
        hitboxBtn.Text = "Hitboxes: " .. (hitboxOn and "ON" or "OFF")
        refreshHitboxes()
    end)
end

function DummyDebugUI:Start()
    if not enabled then
        return
    end

    DummyDevState.OnClientEvent:Connect(render)
    DummyDevCommand:FireServer("subscribe")

    -- Keep hitbox adornments attached as dummies respawn (their parts are recreated).
    RunService.Heartbeat:Connect(function()
        if not hitboxOn then
            return
        end
        local first = hitboxAdorns[1]
        local adornee = first and first.Adornee
        if first == nil or adornee == nil or adornee.Parent == nil then
            refreshHitboxes()
        end
    end)

    Logger.debug("[DummyDebugUI] Ready (developer overlay)")
end

return DummyDebugUI
