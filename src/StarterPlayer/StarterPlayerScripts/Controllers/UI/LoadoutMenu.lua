--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > UI > LoadoutMenu
--
-- Rough pre-round deployment screen: pick a primary weapon and a team, then Deploy.
--
-- Deploy fires the SelectLoadout RemoteEvent; LoadoutService validates the choice
-- and writes it to the BR_LoadoutPrimary / BR_TeamPref Player attributes that
-- GunService, TeamService and GunController read. This UI owns no authoritative
-- state — it re-reads those attributes every time it opens.
--
-- Opens/closes on Constants.LOADOUT.TOGGLE_KEY, and auto-opens on entry to a
-- Constants.LOADOUT.AUTO_OPEN_PHASES phase (LOBBY / RESULTS). Auto-closes on entry
-- to any other phase (PREP / ACTIVE / MATCHEND). Phase comes straight off the
-- RoundStateChanged remote — the same feed MatchUI uses.
--
-- A mid-round Deploy is honoured but only takes effect at the next PREP, because
-- GunService / TeamService read the attributes when they assign teams and ammo.
--
-- Initialized by ClientInit via loadInitAndStart():
--   1. init(playerGui) — builds every GUI instance
--   2. Start()         — connects input + RoundStateChanged, seeds selection

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")

local Modules   = ReplicatedStorage:WaitForChild("Modules")
local Constants = require(Modules:WaitForChild("Constants"))
local Logger    = require(Modules:WaitForChild("Logger"))

-- MatchController (ClientInit slot 1) is already started by the time Start() runs;
-- requiring it again returns the same cached module. Used only to seed the initial
-- phase so a mid-match joiner does not briefly see the menu before RoundStateChanged.
local MatchController = require(script.Parent.Parent:WaitForChild("MatchController"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local SelectLoadout     = Remotes:WaitForChild("SelectLoadout")     :: RemoteEvent

local LocalPlayer = Players.LocalPlayer
local LOADOUT     = Constants.LOADOUT :: any

-- ============================================================
-- Design tokens (local to this UI, matches MatchUI's palette)
-- ============================================================

local PANEL_COLOR   = Color3.fromRGB(10, 10, 10)
local CARD_COLOR    = Color3.fromRGB(26, 26, 26)
local CARD_LOCKED   = Color3.fromRGB(18, 18, 18)
local WHITE         = Color3.fromRGB(240, 240, 240)
local GREY          = Color3.fromRGB(150, 150, 150)
local DIM_GREY      = Color3.fromRGB(90, 90, 90)
local ACCENT        = Color3.fromRGB(235, 180, 90)
local COLOR_ATK     = Color3.fromRGB(200, 60, 60)
local COLOR_DEF     = Color3.fromRGB(60, 120, 200)

local PANEL_W   = 460
local PAD       = 16
local CARD_H    = 44
local CARD_GAP  = 6
local ROW_H     = 40

-- ============================================================
-- GUI references (set in init())
-- ============================================================

local screenGui  : ScreenGui
local panel      : Frame
local deployBtn  : TextButton

-- weapon key → { button: TextButton, stroke: UIStroke, selectable: boolean }
local weaponRows : { [string]: { button: TextButton, stroke: UIStroke, selectable: boolean } } = {}
-- team choice → { button: TextButton, stroke: UIStroke }
local teamRows   : { [string]: { button: TextButton, stroke: UIStroke } } = {}

-- ============================================================
-- State
-- ============================================================

local isOpen         = false
local selectedWeapon : string = LOADOUT.DEFAULT_PRIMARY
local selectedTeam   : string = LOADOUT.DEFAULT_TEAM_PREF
local lastPhase      : string = Constants.Phase.LOBBY

-- ============================================================
-- Build helpers
-- ============================================================

local function makeLabel(
    parent: Instance,
    text: string,
    size: UDim2,
    pos: UDim2,
    fontSize: number,
    bold: boolean,
    color: Color3,
    align: Enum.TextXAlignment
): TextLabel
    local t = Instance.new("TextLabel")
    t.Size                   = size
    t.Position               = pos
    t.BackgroundTransparency = 1
    t.Text                   = text
    t.TextColor3             = color
    t.Font                   = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    t.TextSize               = fontSize
    t.TextXAlignment         = align
    t.TextYAlignment         = Enum.TextYAlignment.Center
    t.Parent                 = parent
    return t
end

local function makeButton(parent: Instance, size: UDim2, pos: UDim2, bg: Color3): (TextButton, UIStroke)
    local b = Instance.new("TextButton")
    b.Size                   = size
    b.Position               = pos
    b.BackgroundColor3       = bg
    b.BorderSizePixel        = 0
    b.AutoButtonColor        = true
    b.Text                   = ""
    b.Parent                 = parent
    local stroke = Instance.new("UIStroke")
    stroke.Color     = ACCENT
    stroke.Thickness  = 1.5
    stroke.Enabled   = false
    stroke.Parent    = b
    return b, stroke
end

-- ============================================================
-- Selection rendering
-- ============================================================

local function refreshSelectionHighlight()
    for key, row in pairs(weaponRows) do
        row.stroke.Enabled = row.selectable and key == selectedWeapon
    end
    for choice, row in pairs(teamRows) do
        row.stroke.Enabled = choice == selectedTeam
    end
end

-- ============================================================
-- Open / close
-- ============================================================

-- Pulls the current selection from the replicated Player attributes so a reopened
-- menu shows what the server currently has for this player.
local function seedFromAttributes()
    local primary = LocalPlayer:GetAttribute(LOADOUT.ATTR_PRIMARY)
    if typeof(primary) == "string" then
        local row = weaponRows[primary]
        if row ~= nil and row.selectable then
            selectedWeapon = primary
        end
    end
    local team = LocalPlayer:GetAttribute(LOADOUT.ATTR_TEAM_PREF)
    if typeof(team) == "string" and teamRows[team] ~= nil then
        selectedTeam = team
    end
end

local function setOpen(open: boolean)
    if open == isOpen then
        return
    end
    isOpen = open
    screenGui.Enabled = open

    if open then
        seedFromAttributes()
        refreshSelectionHighlight()
        UserInputService.MouseIconEnabled = true
        UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
    else
        -- Hand the cursor back to gameplay only when we're in a locked
        -- first-person view; otherwise leave the default lobby cursor alone.
        if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
            UserInputService.MouseIconEnabled = false
            UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
        end
    end
end

-- ============================================================
-- Deploy
-- ============================================================

local function deploy()
    SelectLoadout:FireServer({ primary = selectedWeapon, team = selectedTeam })
    Logger.debug(string.format(
        "[LoadoutMenu] Deploy → weapon=%s team=%s", selectedWeapon, selectedTeam
    ))
    setOpen(false)
end

-- ============================================================
-- Phase reaction — only acts on transitions (RoundStateChanged fires every second)
-- ============================================================

local function onPhase(phase: string)
    if phase == lastPhase then
        return
    end
    lastPhase = phase

    if LOADOUT.AUTO_OPEN_PHASES[phase] == true then
        setOpen(true)
    else
        -- PREP / ACTIVE / MATCHEND — get the panel out of the way.
        setOpen(false)
    end
end

-- ============================================================
-- Controller
-- ============================================================

local LoadoutMenu = {}

function LoadoutMenu:init(playerGui: PlayerGui)
    screenGui                = Instance.new("ScreenGui")
    screenGui.Name           = "LoadoutMenu"
    screenGui.ResetOnSpawn   = false
    screenGui.IgnoreGuiInset  = true
    screenGui.DisplayOrder    = 20
    screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled        = false
    screenGui.Parent         = playerGui

    -- Full-screen click-absorbing backdrop (a TextButton so clicks outside the
    -- panel don't fall through to the gun / world).
    local backdrop               = Instance.new("TextButton")
    backdrop.Name                = "Backdrop"
    backdrop.Size                = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3    = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 0.35
    backdrop.BorderSizePixel     = 0
    backdrop.AutoButtonColor     = false
    backdrop.Text                = ""
    backdrop.Modal               = true
    backdrop.Parent              = screenGui

    -- Panel
    local weaponBlockH = #LOADOUT.WEAPONS * CARD_H + (#LOADOUT.WEAPONS - 1) * CARD_GAP
    local panelH = PAD + 28 + 22 + weaponBlockH + 24 + 20 + ROW_H + 20 + ROW_H + 8 + 16 + PAD

    panel                    = Instance.new("Frame")
    panel.Name               = "Panel"
    panel.AnchorPoint        = Vector2.new(0.5, 0.5)
    panel.Position           = UDim2.fromScale(0.5, 0.5)
    panel.Size               = UDim2.fromOffset(PANEL_W, panelH)
    panel.BackgroundColor3   = PANEL_COLOR
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel    = 0
    panel.Parent             = screenGui

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color        = Color3.fromRGB(60, 60, 60)
    panelStroke.Thickness    = 1
    panelStroke.Parent       = panel

    local innerW = PANEL_W - PAD * 2
    local y = PAD

    makeLabel(panel, "DEPLOYMENT",
        UDim2.fromOffset(innerW, 28), UDim2.fromOffset(PAD, y),
        22, true, WHITE, Enum.TextXAlignment.Left)
    y += 28

    makeLabel(panel, "PRIMARY WEAPON",
        UDim2.fromOffset(innerW, 22), UDim2.fromOffset(PAD, y),
        12, true, GREY, Enum.TextXAlignment.Left)
    y += 22

    for _, spec in ipairs(LOADOUT.WEAPONS) do
        local selectable = spec.selectable == true
        local card, stroke = makeButton(panel,
            UDim2.fromOffset(innerW, CARD_H),
            UDim2.fromOffset(PAD, y),
            selectable and CARD_COLOR or CARD_LOCKED)
        card.Name        = "Weapon_" .. spec.key
        card.AutoButtonColor = selectable
        card.Active      = selectable

        makeLabel(card, spec.label,
            UDim2.fromOffset(innerW - 120, CARD_H), UDim2.fromOffset(12, 0),
            16, true, selectable and WHITE or DIM_GREY, Enum.TextXAlignment.Left)
        makeLabel(card, spec.blurb,
            UDim2.fromOffset(innerW - 24, CARD_H), UDim2.fromOffset(-12, 0),
            11, false, selectable and GREY or DIM_GREY, Enum.TextXAlignment.Right)

        weaponRows[spec.key] = { button = card, stroke = stroke, selectable = selectable }
        y += CARD_H + CARD_GAP
    end
    y += 24 - CARD_GAP

    makeLabel(panel, "TEAM",
        UDim2.fromOffset(innerW, 20), UDim2.fromOffset(PAD, y),
        12, true, GREY, Enum.TextXAlignment.Left)
    y += 20

    local segW = (innerW - CARD_GAP * (#LOADOUT.TEAM_CHOICES - 1)) / #LOADOUT.TEAM_CHOICES
    for idx, choice in ipairs(LOADOUT.TEAM_CHOICES) do
        local seg, stroke = makeButton(panel,
            UDim2.fromOffset(segW, ROW_H),
            UDim2.fromOffset(PAD + (idx - 1) * (segW + CARD_GAP), y),
            CARD_COLOR)
        seg.Name = "Team_" .. choice
        local labelColor = WHITE
        if choice == Constants.TEAM_ATTACKERS then
            labelColor = COLOR_ATK
        elseif choice == Constants.TEAM_DEFENDERS then
            labelColor = COLOR_DEF
        end
        makeLabel(seg, choice:upper(),
            UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
            13, true, labelColor, Enum.TextXAlignment.Center)
        teamRows[choice] = { button = seg, stroke = stroke }
    end
    y += ROW_H + 20

    local deployButton = makeButton(panel,
        UDim2.fromOffset(innerW, ROW_H),
        UDim2.fromOffset(PAD, y),
        Color3.fromRGB(40, 90, 40))
    deployBtn = deployButton
    deployBtn.Name = "Deploy"
    makeLabel(deployBtn, "DEPLOY",
        UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
        16, true, WHITE, Enum.TextXAlignment.Center)
    y += ROW_H + 8

    makeLabel(panel,
        string.format("[%s] close", LOADOUT.TOGGLE_KEY.Name),
        UDim2.fromOffset(innerW, 16), UDim2.fromOffset(PAD, y),
        11, false, DIM_GREY, Enum.TextXAlignment.Right)
end

function LoadoutMenu:Start()
    if LOADOUT.ENABLED ~= true then
        Logger.debug("[LoadoutMenu] Disabled via Constants.LOADOUT.ENABLED")
        return
    end

    -- Weapon card clicks.
    for key, row in pairs(weaponRows) do
        if row.selectable then
            row.button.Activated:Connect(function()
                selectedWeapon = key
                refreshSelectionHighlight()
            end)
        end
    end

    -- Team segment clicks.
    for choice, row in pairs(teamRows) do
        row.button.Activated:Connect(function()
            selectedTeam = choice
            refreshSelectionHighlight()
        end)
    end

    deployBtn.Activated:Connect(deploy)

    -- Toggle key.
    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then
            return
        end
        if input.KeyCode == LOADOUT.TOGGLE_KEY then
            setOpen(not isOpen)
        end
    end)

    -- Phase feed — same remote MatchUI uses.
    RoundStateChanged.OnClientEvent:Connect(function(raw: any)
        if type(raw) == "table" and type(raw.phase) == "string" then
            onPhase(raw.phase)
        end
    end)

    -- Seed the initial selection and phase, then open if we're already in a menu phase.
    seedFromAttributes()
    refreshSelectionHighlight()
    local ok, phase = pcall(function()
        return MatchController:GetPhase()
    end)
    if ok and type(phase) == "string" then
        lastPhase = phase
    end
    if LOADOUT.AUTO_OPEN_PHASES[lastPhase] == true then
        setOpen(true)
    end
end

return LoadoutMenu
