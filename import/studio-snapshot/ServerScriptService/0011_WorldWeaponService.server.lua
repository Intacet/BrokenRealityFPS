--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > WorldWeaponService
--
-- Manages server-side attachment of gun-only world models to player characters.
-- Listens to WeaponEquipState (fired by GunController) to equip or holster.
-- Clones ReplicatedStorage/WorldModels/<worldModelName> into the character and
-- attaches the Handle BasePart to the R6 Right Arm via a Motor6D named WorldWeaponGrip.
-- Other players can see the world model because it is parented to the character.
--
-- What this script does NOT do:
--   - Play animations               →  ViewModelController / MovementController (client)
--   - Apply damage or hit detection →  GunService + DamageService
--   - Change ammo, health, or recoil
--   - Create Welds or WeldConstraints for the attachment (Motor6D only)
--
-- Startup: self-starts by calling WorldWeaponService:Init() at the bottom of this file.
-- No central ServerInit.lua exists in this project; each service is a self-starting Script.
--
-- Asset precondition:
--   ReplicatedStorage/WorldModels/AKS74 must be a gun-only Model containing a BasePart
--   named Handle.  If missing, EquipWeapon logs with Logger.warn() and returns without
--   attaching anything.  Gameplay remains functional (weapon fires as normal).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))
local Logger     = require(Modules:WaitForChild("Logger"))

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local WeaponEquipState = Remotes:WaitForChild("WeaponEquipState") :: RemoteEvent

-- ============================================================
-- State
-- ============================================================

-- Server-authoritative map of player → currently equipped world weapon name (or nil).
local equippedWeapon: { [Player]: string? } = {}

-- Per-player RBXScriptConnections for character lifecycle (CharacterAdded, CharacterRemoving).
-- Keyed by Player; disconnected in CleanupPlayer when the player leaves.
local playerLifecycleConns: { [Player]: { RBXScriptConnection } } = {}

-- ============================================================
-- WorldWeaponService
-- ============================================================

local WorldWeaponService = {}

-- ============================================================
-- Private helpers
-- ============================================================

-- Removes the world weapon Model (EquippedWorldWeapon) and the WorldWeaponGrip Motor6D
-- from a character.  Safe to call when neither is present (no-op in that case).
local function removeWorldWeaponFromCharacter(character: Model)
    local existing = character:FindFirstChild(Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME)
    if existing then
        existing:Destroy()
    end
    local rightArmInst = character:FindFirstChild(Constants.WORLD_WEAPON_R6_RIGHT_ARM_NAME)
    if rightArmInst then
        local motor = rightArmInst:FindFirstChild(Constants.WORLD_WEAPON_GRIP_MOTOR_NAME)
        if motor then
            motor:Destroy()
        end
    end
end

-- Connects CharacterRemoving and CharacterAdded listeners for one player.
-- Old connections for this player are disconnected before new ones are created.
local function setupPlayerLifecycle(player: Player)
    -- Disconnect stale connections (e.g. called a second time after reconnect).
    local old = playerLifecycleConns[player]
    if old then
        for _, c in ipairs(old) do
            c:Disconnect()
        end
    end
    local conns: { RBXScriptConnection } = {}
    playerLifecycleConns[player] = conns

    -- CharacterRemoving fires when the character is removed (death, reset, leaving).
    -- Remove the world weapon model from the old character and clear equipped state.
    local charRemovingConn = player.CharacterRemoving:Connect(function(removedChar: Model)
        removeWorldWeaponFromCharacter(removedChar)
        equippedWeapon[player] = nil
        Logger.debug("[WorldWeaponService] CharacterRemoving: world weapon cleared for " .. player.Name)
    end)
    table.insert(conns, charRemovingConn)

    -- CharacterAdded fires when a new character spawns.
    -- State should already be nil from CharacterRemoving, but reset as a safety guard.
    local charAddedConn = player.CharacterAdded:Connect(function(_newChar: Model)
        equippedWeapon[player] = nil
    end)
    table.insert(conns, charAddedConn)
end

-- ============================================================
-- Public API
-- ============================================================

-- Clones the world model for weaponName and attaches it to the player's R6 Right Arm.
-- Returns without attaching if any precondition fails; all failures are logged via Logger.warn().
function WorldWeaponService:EquipWeapon(player: Player, weaponName: string)
    assert(typeof(player) == "Instance" and player:IsA("Player"),
        "[WorldWeaponService] EquipWeapon: player must be a Player")
    assert(typeof(weaponName) == "string",
        "[WorldWeaponService] EquipWeapon: weaponName must be a string")

    -- Resolve WeaponData entry.
    local rawData = WeaponData[weaponName]
    if not rawData then
        Logger.warn("[WorldWeaponService] EquipWeapon: no WeaponData entry for: " .. weaponName)
        return
    end
    local data = rawData :: any

    -- Resolve worldModelName from WeaponData.
    local worldModelName: any = data.worldModelName
    if typeof(worldModelName) ~= "string" or (worldModelName :: string) == "" then
        Logger.warn("[WorldWeaponService] EquipWeapon: worldModelName missing in WeaponData for: "
            .. weaponName)
        return
    end
    local wmName: string = worldModelName :: string

    -- Locate ReplicatedStorage/WorldModels folder.
    local worldFolder = ReplicatedStorage:FindFirstChild(Constants.WORLD_WEAPON_FOLDER_NAME)
    if not worldFolder then
        Logger.warn("[WorldWeaponService] EquipWeapon: ReplicatedStorage/"
            .. Constants.WORLD_WEAPON_FOLDER_NAME .. " folder not found."
            .. " Create a Folder named '" .. Constants.WORLD_WEAPON_FOLDER_NAME
            .. "' in ReplicatedStorage and place the gun-only AKS74 Model inside it.")
        return
    end

    -- Locate the world model asset.
    local worldAsset = worldFolder:FindFirstChild(wmName)
    if not worldAsset or not worldAsset:IsA("Model") then
        Logger.warn("[WorldWeaponService] EquipWeapon: ReplicatedStorage/"
            .. Constants.WORLD_WEAPON_FOLDER_NAME .. "/" .. wmName .. " not found."
            .. " Add a gun-only Model named '" .. wmName
            .. "' containing a BasePart named Handle.")
        return
    end

    -- Locate the player's character.
    local character = player.Character
    if not character then
        Logger.warn("[WorldWeaponService] EquipWeapon: " .. player.Name .. " has no Character")
        return
    end

    -- Locate R6 Right Arm.
    local rightArmInst = character:FindFirstChild(Constants.WORLD_WEAPON_R6_RIGHT_ARM_NAME)
    if not rightArmInst or not rightArmInst:IsA("BasePart") then
        Logger.warn("[WorldWeaponService] EquipWeapon: '"
            .. Constants.WORLD_WEAPON_R6_RIGHT_ARM_NAME
            .. "' not found on " .. player.Name
            .. " (expected R6 rig; check CharacterRigType in default.project.json)")
        return
    end
    local rightArm = rightArmInst :: BasePart

    -- Remove any old world weapon first (guard against double-equip).
    removeWorldWeaponFromCharacter(character)

    -- Clone the world model asset.
    local clone = (worldAsset :: Model):Clone()
    clone.Name = Constants.WORLD_WEAPON_CHARACTER_MODEL_NAME

    -- Configure all BasePart descendants so the model does not interfere with physics.
    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") then
            local p = desc :: BasePart
            p.CanCollide = false
            p.CanQuery   = false
            p.CanTouch   = false
            p.Massless   = true
            p.Anchored   = false
        end
    end

    -- Locate Handle — required for the Motor6D attachment.
    local handleInst = clone:FindFirstChild(Constants.WORLD_WEAPON_HANDLE_PART_NAME)
    if not handleInst or not handleInst:IsA("BasePart") then
        clone:Destroy()
        Logger.warn("[WorldWeaponService] EquipWeapon: BasePart named '"
            .. Constants.WORLD_WEAPON_HANDLE_PART_NAME
            .. "' not found in WorldModels/" .. wmName
            .. ". Add a BasePart named Handle to the gun-only world model asset.")
        return
    end
    local handle = handleInst :: BasePart

    -- Parent clone to character (must happen before Motor6D is created so Handle
    -- is inside the same model hierarchy as Right Arm when the joint activates).
    clone.Parent = character

    -- Attach Handle to Right Arm via Motor6D.
    -- Motor6D (not Weld or WeldConstraint) so character animations drive arm movement.
    -- Part0 = Right Arm (moves with the arm), Part1 = Handle (gun follows the arm).
    local motor    = Instance.new("Motor6D")
    motor.Name     = Constants.WORLD_WEAPON_GRIP_MOTOR_NAME
    motor.Part0    = rightArm
    motor.Part1    = handle
    motor.C0       = Constants.WORLD_AKS74_GRIP_C0
    motor.C1       = Constants.WORLD_AKS74_GRIP_C1
    motor.Parent   = rightArm

    equippedWeapon[player] = weaponName

    Logger.debug("[WorldWeaponService] EquipWeapon: "
        .. weaponName .. " attached to " .. player.Name)
end

-- Removes the world weapon model and Motor6D from the player's character.
-- Also clears the server-side equipped state for this player.
function WorldWeaponService:HolsterWeapon(player: Player)
    assert(typeof(player) == "Instance" and player:IsA("Player"),
        "[WorldWeaponService] HolsterWeapon: player must be a Player")

    local character = player.Character
    if character then
        removeWorldWeaponFromCharacter(character)
    end
    equippedWeapon[player] = nil

    Logger.debug("[WorldWeaponService] HolsterWeapon: " .. player.Name)
end

-- Returns true while a world weapon model is attached to the player's character.
function WorldWeaponService:IsWeaponEquipped(player: Player): boolean
    assert(typeof(player) == "Instance" and player:IsA("Player"),
        "[WorldWeaponService] IsWeaponEquipped: player must be a Player")
    return equippedWeapon[player] ~= nil
end

-- Holsters the weapon, disconnects all lifecycle connections, and clears all state
-- for this player.  Called from Players.PlayerRemoving.
function WorldWeaponService:CleanupPlayer(player: Player)
    assert(typeof(player) == "Instance" and player:IsA("Player"),
        "[WorldWeaponService] CleanupPlayer: player must be a Player")

    self:HolsterWeapon(player)

    -- Disconnect all character lifecycle connections for this player.
    local conns = playerLifecycleConns[player]
    if conns then
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
        playerLifecycleConns[player] = nil
    end

    equippedWeapon[player] = nil

    Logger.debug("[WorldWeaponService] CleanupPlayer: " .. player.Name)
end

-- Connects remote handler, player lifecycle listeners, and character cleanup.
-- Called once at server start (self-start at the bottom of this file).
function WorldWeaponService:Init()
    -- ── Remote handler ────────────────────────────────────────────────────────
    -- Fired by GunController when key 1 is pressed to equip or holster the AKS74.
    -- All input is validated before any server action is taken.
    WeaponEquipState.OnServerEvent:Connect(function(
        player: Player,
        weaponName: any,
        isEquipped: any
    )
        -- Type guards — remote input is untrusted.
        if typeof(weaponName) ~= "string" then
            Logger.warn("[WorldWeaponService] WeaponEquipState: non-string weaponName from "
                .. player.Name)
            return
        end
        if typeof(isEquipped) ~= "boolean" then
            Logger.warn("[WorldWeaponService] WeaponEquipState: non-boolean isEquipped from "
                .. player.Name)
            return
        end
        if not WeaponData[weaponName] then
            Logger.warn("[WorldWeaponService] WeaponEquipState: unknown weapon '"
                .. weaponName .. "' from " .. player.Name)
            return
        end
        -- Guard: only AKS74 has a world model for this stage.
        -- Remove this guard when additional weapons with worldModelName are added.
        if weaponName ~= "AKS74" then
            Logger.warn("[WorldWeaponService] WeaponEquipState: '"
                .. weaponName .. "' has no world model yet — add worldModelName to WeaponData")
            return
        end

        if isEquipped then
            self:EquipWeapon(player, weaponName)
        else
            self:HolsterWeapon(player)
        end
    end)

    -- ── Player lifecycle ──────────────────────────────────────────────────────
    -- Set up CharacterRemoving / CharacterAdded listeners for each player.
    -- Handles already-connected players at server start and future joiners.
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayerLifecycle(player)
    end
    Players.PlayerAdded:Connect(function(player: Player)
        setupPlayerLifecycle(player)
    end)

    -- Clean up all state when a player leaves so we do not hold stale references.
    Players.PlayerRemoving:Connect(function(player: Player)
        self:CleanupPlayer(player)
    end)

    Logger.debug("[WorldWeaponService] Ready")
end

-- ============================================================
-- Self-start
-- ============================================================
-- No central ServerInit.lua exists in this project; each server service is a
-- self-starting Script.  Init() is called here so connections are established
-- when the Script loads at server start.

WorldWeaponService:Init()

return WorldWeaponService
