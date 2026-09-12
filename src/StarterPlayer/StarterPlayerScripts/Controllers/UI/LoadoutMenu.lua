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
-- RESPAWN BOTS fires the RespawnBots RemoteEvent — AIService.RespawnAllSquads()
-- instantly clears every live AI grunt and spawns fresh squads at Workspace/AISpawns.
-- Available to every player, in Studio and a published server alike; the server
-- holds one shared cooldown (Constants.AI.RESPAWN_COOLDOWN_SECONDS) so it can't be
-- spammed — this button's countdown is a cosmetic mirror of that, not the real gate.
--
-- KILL ALL BOTS fires the KillAllBots RemoteEvent — AIService.KillAllBots() routes
-- every live grunt through the real death path (ragdoll, blood, the normal corpse
-- timer) instead of an instant destroy, and does not spawn replacements. Same
-- shared-cooldown pattern (Constants.AI.KILL_ALL_COOLDOWN_SECONDS).
--
-- WATCH AI ARENA fires TeleportToArena — the server moves the player's own
-- character above Workspace/BrokenReality_AIArena (Constants.AI_ARENA.SPECTATE_HEIGHT)
-- and fires the same remote back once it lands; SpectatorFlyController (a separate
-- client controller) listens for that confirmation and grants free-fly spectating.
-- Only ever affects the requesting player, so no shared cooldown.
--
-- AI INVISIBILITY toggles Constants.ATTR_AI_INVISIBLE on this player via the
-- SetAIInvisible remote — AIService's own targeting (findVisibleTarget,
-- targetRootOf, the hit-reaction listener) skips this player entirely while
-- it's set, so grunts never acquire, track, or return fire on them. A session
-- toggle like Crosshair — persists across respawns until turned back off.
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

-- CrosshairUI (ClientInit slot 6) owns SetUserEnabled/IsUserEnabled — the loadout
-- menu exposes that toggle to every player (the DummyDebugUI button is dev-only).
local CrosshairUI = require(script.Parent:WaitForChild("CrosshairUI"))

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
local SelectLoadout     = Remotes:WaitForChild("SelectLoadout")     :: RemoteEvent
local RespawnBots       = Remotes:WaitForChild("RespawnBots")       :: RemoteEvent
local KillAllBots       = Remotes:WaitForChild("KillAllBots")       :: RemoteEvent
local TeleportToArena   = Remotes:WaitForChild("TeleportToArena")   :: RemoteEvent
local SetAIInvisible    = Remotes:WaitForChild("SetAIInvisible")    :: RemoteEvent

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

local screenGui    : ScreenGui
local panel        : Frame
local deployBtn    : TextButton
local crosshairBtn : TextButton
local crosshairLbl : TextLabel
local respawnBtn   : TextButton
local respawnLbl   : TextLabel
local killAllBtn   : TextButton
local killAllLbl   : TextLabel
local watchArenaBtn: TextButton
local aiInvisibleBtn: TextButton
local aiInvisibleLbl: TextLabel

-- weapon key → { button: TextButton, stroke: UIStroke, selectable: boolean }
local weaponRows : { [string]: { button: TextButton, stroke: UIStroke, selectable: boolean } } = {}
-- team choice → { button: TextButton, stroke: UIStroke }
local teamRows   : { [string]: { button: TextButton, stroke: UIStroke } } = {}

-- ============================================================
-- State
-- ============================================================

local isOpen          = false
local selectedWeapon  : string = LOADOUT.DEFAULT_PRIMARY
local selectedTeam    : string = LOADOUT.DEFAULT_TEAM_PREF
local lastPhase       : string = Constants.Phase.LOBBY
-- Mirror of CrosshairUI:IsUserEnabled(); the button label follows it.
local crosshairEnabled = true
-- Client-side mirror of the server's shared RESPAWN_COOLDOWN_SECONDS gate — purely
-- cosmetic (disables the button + shows a countdown); the server is the real gate
-- and simply ignores a request that arrives too soon.
local respawnCooldownUntil = 0
-- Same pattern, mirroring Constants.AI.KILL_ALL_COOLDOWN_SECONDS.
local killAllCooldownUntil = 0
-- Client-side mirror of Constants.ATTR_AI_INVISIBLE — same "purely a UI mirror"
-- pattern as crosshairEnabled; the server attribute (set via SetAIInvisible) is
-- the real state AIService reads, this var only drives the button label.
local aiInvisibleEnabled = false

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

-- Drives the RESPAWN BOTS button through its cooldown: disables it and counts down
-- the label, then restores it. Purely cosmetic — the server holds the real gate
-- (Constants.AI.RESPAWN_COOLDOWN_SECONDS) and just ignores a request that arrives
-- too soon, so a stale/missed client countdown can never let a request through early.
local function runRespawnCooldown(seconds: number)
    respawnCooldownUntil = os.clock() + seconds
    task.spawn(function()
        while os.clock() < respawnCooldownUntil do
            if respawnBtn ~= nil then
                respawnBtn.Active = false
                respawnBtn.AutoButtonColor = false
            end
            if respawnLbl ~= nil then
                respawnLbl.Text = string.format("RESPAWN BOTS (%ds)", math.max(0, math.ceil(respawnCooldownUntil - os.clock())))
                respawnLbl.TextColor3 = DIM_GREY
            end
            task.wait(0.2)
        end
        if respawnBtn ~= nil then
            respawnBtn.Active = true
            respawnBtn.AutoButtonColor = true
        end
        if respawnLbl ~= nil then
            respawnLbl.Text = "RESPAWN BOTS"
            respawnLbl.TextColor3 = WHITE
        end
    end)
end

-- Same as runRespawnCooldown, for the KILL ALL BOTS button.
local function runKillAllCooldown(seconds: number)
    killAllCooldownUntil = os.clock() + seconds
    task.spawn(function()
        while os.clock() < killAllCooldownUntil do
            if killAllBtn ~= nil then
                killAllBtn.Active = false
                killAllBtn.AutoButtonColor = false
            end
            if killAllLbl ~= nil then
                killAllLbl.Text = string.format("KILL ALL BOTS (%ds)", math.max(0, math.ceil(killAllCooldownUntil - os.clock())))
                killAllLbl.TextColor3 = DIM_GREY
            end
            task.wait(0.2)
        end
        if killAllBtn ~= nil then
            killAllBtn.Active = true
            killAllBtn.AutoButtonColor = true
        end
        if killAllLbl ~= nil then
            killAllLbl.Text = "KILL ALL BOTS"
            killAllLbl.TextColor3 = WHITE
        end
    end)
end

-- Syncs the crosshair toggle label from CrosshairUI's current user setting.
local function refreshCrosshairButton()
    local ok, enabled = pcall(function()
        return CrosshairUI:IsUserEnabled()
    end)
    if ok and type(enabled) == "boolean" then
        crosshairEnabled = enabled
    end
    if crosshairLbl ~= nil then
        crosshairLbl.Text = "CROSSHAIR: " .. (crosshairEnabled and "ON" or "OFF")
        crosshairLbl.TextColor3 = crosshairEnabled and WHITE or DIM_GREY
    end
end

-- Syncs the AI invisibility toggle label from the local mirror. Unlike
-- crosshair there's no client-readable authority to re-sync FROM (the real
-- state lives server-side as Constants.ATTR_AI_INVISIBLE on this player) —
-- aiInvisibleEnabled is the only place this button's state lives client-side,
-- exactly like the server-authoritative respawn/kill-all cooldowns above.
local function refreshAIInvisibleButton()
    if aiInvisibleLbl ~= nil then
        aiInvisibleLbl.Text = "AI INVISIBILITY: " .. (aiInvisibleEnabled and "ON" or "OFF")
        aiInvisibleLbl.TextColor3 = aiInvisibleEnabled and WHITE or DIM_GREY
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

-- Hands the cursor back to gameplay only when we're in a locked first-person
-- view and the menu is closed; otherwise leaves the default lobby cursor alone
-- (third-person wants a free cursor for camera orbit). Split out from setOpen()
-- and also driven by a CameraMode change signal below: closing the menu and
-- ViewModelController flipping CameraMode to LockFirstPerson on respawn are two
-- independently-timed events (menu close comes from RoundStateChanged, camera
-- mode comes from CharacterAdded) — whichever lands first left the cursor stuck
-- visible if this only ran once, at close time, against whatever CameraMode
-- happened to already be.
local function syncCursorToCameraMode()
    if isOpen then
        return  -- the menu owns the cursor while it's up
    end
    if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
        UserInputService.MouseIconEnabled = false
        UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
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
        refreshCrosshairButton()
        UserInputService.MouseIconEnabled = true
        UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
    else
        syncCursorToCameraMode()
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
    local TOGGLE_H = 30  -- crosshair / respawn-bots / kill-all-bots / watch-arena / ai-invisibility button row height
    local weaponBlockH = #LOADOUT.WEAPONS * CARD_H + (#LOADOUT.WEAPONS - 1) * CARD_GAP
    local panelH = PAD + 28 + 22 + weaponBlockH + 24 + 20 + ROW_H + 20 + ROW_H + 8
        + TOGGLE_H + 8 + TOGGLE_H + 8 + TOGGLE_H + 8 + TOGGLE_H + 8 + TOGGLE_H + 8 + 16 + PAD

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

    -- Crosshair toggle — available to every player (the DummyDebugUI copy is dev-only).
    local xhairButton = makeButton(panel,
        UDim2.fromOffset(innerW, TOGGLE_H),
        UDim2.fromOffset(PAD, y),
        CARD_COLOR)
    crosshairBtn = xhairButton
    crosshairBtn.Name = "CrosshairToggle"
    crosshairLbl = makeLabel(crosshairBtn, "CROSSHAIR: ON",
        UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
        12, true, WHITE, Enum.TextXAlignment.Center)
    y += TOGGLE_H + 8

    -- Respawn bots — available to every player, dev and published alike. Server owns
    -- the real cooldown (Constants.AI.RESPAWN_COOLDOWN_SECONDS); this just requests it.
    local respawnButton = makeButton(panel,
        UDim2.fromOffset(innerW, TOGGLE_H),
        UDim2.fromOffset(PAD, y),
        CARD_COLOR)
    respawnBtn = respawnButton
    respawnBtn.Name = "RespawnBots"
    respawnLbl = makeLabel(respawnBtn, "RESPAWN BOTS",
        UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
        12, true, WHITE, Enum.TextXAlignment.Center)
    y += TOGGLE_H + 8

    -- Kill all bots — same availability as Respawn Bots, but routes every grunt
    -- through the real death path instead of an instant reset. Server owns the
    -- real cooldown (Constants.AI.KILL_ALL_COOLDOWN_SECONDS).
    local killAllButton = makeButton(panel,
        UDim2.fromOffset(innerW, TOGGLE_H),
        UDim2.fromOffset(PAD, y),
        CARD_COLOR)
    killAllBtn = killAllButton
    killAllBtn.Name = "KillAllBots"
    killAllLbl = makeLabel(killAllBtn, "KILL ALL BOTS",
        UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
        12, true, WHITE, Enum.TextXAlignment.Center)
    y += TOGGLE_H + 8

    -- Watch AI arena — teleports the player above Workspace/BrokenReality_AIArena
    -- and grants free-fly spectating (SpectatorFlyController) once the server
    -- confirms the teleport landed. No cooldown UI: only moves the requester.
    local watchArenaButton = makeButton(panel,
        UDim2.fromOffset(innerW, TOGGLE_H),
        UDim2.fromOffset(PAD, y),
        CARD_COLOR)
    watchArenaBtn = watchArenaButton
    watchArenaBtn.Name = "WatchAIArena"
    makeLabel(watchArenaBtn, "WATCH AI ARENA",
        UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
        12, true, WHITE, Enum.TextXAlignment.Center)
    y += TOGGLE_H + 8

    -- AI invisibility — sets Constants.ATTR_AI_INVISIBLE on this player via
    -- SetAIInvisible; AIService's own targeting (findVisibleTarget/
    -- targetRootOf/hit-reaction) skips this player entirely while it's set.
    -- Session toggle, like Crosshair — persists across respawns until turned off.
    local aiInvisibleButton = makeButton(panel,
        UDim2.fromOffset(innerW, TOGGLE_H),
        UDim2.fromOffset(PAD, y),
        CARD_COLOR)
    aiInvisibleBtn = aiInvisibleButton
    aiInvisibleBtn.Name = "AIInvisibility"
    aiInvisibleLbl = makeLabel(aiInvisibleBtn, "AI INVISIBILITY: OFF",
        UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
        12, true, WHITE, Enum.TextXAlignment.Center)
    y += TOGGLE_H + 8

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

    -- Crosshair on/off — routes to CrosshairUI:SetUserEnabled, which hides both the
    -- fixed centre reticle and the floating hipfire reticle. Session-local.
    crosshairBtn.Activated:Connect(function()
        crosshairEnabled = not crosshairEnabled
        pcall(function()
            CrosshairUI:SetUserEnabled(crosshairEnabled)
        end)
        refreshCrosshairButton()
    end)

    -- Respawn bots — fires immediately; the server is the real gate (silently
    -- ignores a request inside its cooldown), so a stale client countdown is safe.
    respawnBtn.Activated:Connect(function()
        if os.clock() < respawnCooldownUntil then
            return
        end
        RespawnBots:FireServer()
        Logger.debug("[LoadoutMenu] Respawn Bots requested")
        local cooldown = (Constants.AI :: any).RESPAWN_COOLDOWN_SECONDS
        runRespawnCooldown(typeof(cooldown) == "number" and cooldown or 8)
    end)

    -- Kill all bots — same immediate-fire / server-is-the-real-gate pattern.
    killAllBtn.Activated:Connect(function()
        if os.clock() < killAllCooldownUntil then
            return
        end
        KillAllBots:FireServer()
        Logger.debug("[LoadoutMenu] Kill All Bots requested")
        local cooldown = (Constants.AI :: any).KILL_ALL_COOLDOWN_SECONDS
        runKillAllCooldown(typeof(cooldown) == "number" and cooldown or 5)
    end)

    -- Watch AI arena — closes the menu immediately so the player can see
    -- themselves teleport; SpectatorFlyController grants fly on the server's
    -- TeleportToArena confirmation, not on this click.
    watchArenaBtn.Activated:Connect(function()
        TeleportToArena:FireServer()
        Logger.debug("[LoadoutMenu] Watch AI Arena requested")
        setOpen(false)
    end)

    -- AI invisibility on/off — fires immediately; the server just sets the
    -- attribute, no validation/cooldown needed since it only affects the
    -- requester's own player.
    aiInvisibleBtn.Activated:Connect(function()
        aiInvisibleEnabled = not aiInvisibleEnabled
        SetAIInvisible:FireServer(aiInvisibleEnabled)
        Logger.debug("[LoadoutMenu] AI Invisibility ->", aiInvisibleEnabled)
        refreshAIInvisibleButton()
    end)

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

    -- Re-sync the cursor whenever CameraMode itself changes (respawn flips it to
    -- LockFirstPerson via ViewModelController, on its own timing relative to the
    -- phase transition above) — see syncCursorToCameraMode's comment.
    LocalPlayer:GetPropertyChangedSignal("CameraMode"):Connect(syncCursorToCameraMode)

    -- Seed the initial selection and phase, then open if we're already in a menu phase.
    seedFromAttributes()
    refreshSelectionHighlight()
    refreshCrosshairButton()
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
