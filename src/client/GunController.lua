--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > GunController
--
-- Owns client-side weapon input and shot reporting.
-- Reads left mouse button clicks, performs a client-side raycast to produce
-- origin + direction, and fires WeaponFired to GunService for server-authoritative
-- validation. Never decides whether a hit landed — that is GunService's job.
--
-- What this controller does NOT do:
--   - Decide if a shot hit or apply damage  →  GunService + DamageService (server)
--   - Render a viewmodel or muzzle flash    →  ViewModelController
--   - Show ammo count UI                    →  HUD (driven by AmmoChanged remote)
--
-- Initialized by ClientInit.client.lua after MatchController:Start() has run.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local WeaponData = require(Modules:WaitForChild("WeaponData"))
local Logger     = require(Modules:WaitForChild("Logger"))

-- MatchController is a sibling ModuleScript in StarterPlayerScripts/Controllers.
local MatchController      = require(script.Parent:WaitForChild("MatchController"))
local ViewModelController  = require(script.Parent:WaitForChild("ViewModelController"))
local CrosshairUI          = require(script.Parent:WaitForChild("UI"):WaitForChild("CrosshairUI"))
local SoundController      = require(script.Parent:WaitForChild("SoundController"))

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local WeaponFired     = Remotes:WaitForChild("WeaponFired")     :: RemoteEvent
local HitConfirmed    = Remotes:WaitForChild("HitConfirmed")    :: RemoteEvent
local HealthChanged   = Remotes:WaitForChild("HealthChanged")   :: RemoteEvent
local AmmoChanged     = Remotes:WaitForChild("AmmoChanged")     :: RemoteEvent
local ReloadRequest   = Remotes:WaitForChild("ReloadRequest")   :: RemoteEvent

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Configuration
-- ============================================================

-- Must stay in sync with GunService's DEFAULT_WEAPON until DEBT-013 is resolved
-- and both sides are updated to pass the weapon name in the WeaponFired payload.
local CURRENT_WEAPON = "AssaultRifle"

-- ============================================================
-- State
-- ============================================================

-- Timestamp of the last accepted shot on the client.
-- Prevents the client from sending WeaponFired events faster than the weapon
-- allows — events that would be silently rejected by GunService anyway.
local lastShotTime: number = 0

-- Local mirror of the server-authoritative ammo state.
-- Updated exclusively by AmmoChanged — never mutated by this controller.
-- Starts at 0/0 until the first AmmoChanged fires (on TeamAssigned/PREP).
local currentMag:     number = 0
local currentReserve: number = 0

-- ============================================================
-- Controller
-- ============================================================

local GunController = {}

-- Called by ClientInit after MatchController:Start() has run.
-- Ordering matters: the InputBegan handler calls MatchController:GetPhase() on
-- every click, so MatchController must be initialized first.
function GunController:Start()

    -- ── Input handler ─────────────────────────────────────────────────────────

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        -- Ignore input already consumed by a UI element (chat, menu, etc.).
        if gameProcessed then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        -- Phase gate: refuse to fire outside the ACTIVE phase.
        -- GetPhase() returns whatever the server last told us — close enough for
        -- a client-side guard. The server enforces this independently.
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then
            return
        end

        local weaponDef = WeaponData[CURRENT_WEAPON]
        if not weaponDef then
            Logger.warn("[GunController] No WeaponData entry for:", CURRENT_WEAPON)
            return
        end

        -- Dry fire: magazine empty — play click and stop here.
        -- This check runs before the rate limit so an empty-mag click always
        -- gives immediate audio feedback without waiting for the cooldown window.
        if currentMag <= 0 then
            SoundController:PlayDryFire()
            return
        end

        -- Client-side rate limit: mirrors the server's fireRate check so the client
        -- does not spam WeaponFired events that GunService will silently discard.
        local now = os.clock()
        if now - lastShotTime < weaponDef.fireRate then
            return
        end

        local character = LocalPlayer.Character
        if not character then
            return
        end

        -- ── Client-side raycast ─────────────────────────────────────────────────
        -- Cast from the camera center forward. The local character is excluded so
        -- the ray does not immediately self-hit (the camera sits inside the torso).
        --
        -- The result is NOT used for damage — GunService re-runs the ray on the
        -- server from the same origin + direction inputs. The result will feed
        -- client-side hit-effect visuals once the viewmodel is built.
        local camera    = workspace.CurrentCamera
        local origin    = camera.CFrame.Position
        local direction = camera.CFrame.LookVector

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { character }

        workspace:Raycast(origin, direction.Unit * weaponDef.range, params)

        -- Record the shot time only after all guards pass. Aborted shots (wrong
        -- phase, no character, no weapon def) do not consume the cooldown window.
        lastShotTime = now

        -- Fire the shot request. The server validates origin + direction with its
        -- own raycast and decides whether damage is applied.
        WeaponFired:FireServer(origin, direction, now)

        -- ── Client-side audio and visuals (cosmetic only, no gameplay impact) ───

        SoundController:PlayGunshot()

        -- Snap gun body back; RenderStepped in ViewModelController lerps it forward.
        ViewModelController:PlayFireAnimation()

        -- Brief muzzle flash: a glowing sphere at the barrel tip, removed after 0.05 s.
        local flash         = Instance.new("Part")
        flash.Name          = "MuzzleFlash"
        flash.Size          = Vector3.new(0.3, 0.3, 0.3)
        flash.BrickColor    = BrickColor.new("Bright yellow")
        flash.Material      = Enum.Material.Neon
        flash.CanCollide    = false
        flash.CastShadow    = false
        flash.Anchored      = true
        flash.CFrame        = ViewModelController:GetBarrelTipCFrame()
        flash.Parent        = workspace.CurrentCamera
        local flashMesh     = Instance.new("SpecialMesh")
        flashMesh.MeshType  = Enum.MeshType.Sphere
        flashMesh.Parent    = flash
        task.delay(0.05, function()
            flash:Destroy()
        end)
    end)

    -- ── Reload input handler ──────────────────────────────────────────────────

    UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if gameProcessed then
            return
        end
        if input.KeyCode ~= Enum.KeyCode.R then
            return
        end
        if MatchController:GetPhase() ~= Constants.Phase.ACTIVE then
            return
        end
        -- Fire the request first so the server acts immediately, then play the
        -- sound optimistically. The server will no-op if the reload is invalid
        -- (full mag, empty reserve) and fire AmmoChanged to keep the client in sync.
        ReloadRequest:FireServer()
        SoundController:PlayReload()
        Logger.debug("[GunController] Reload requested")
    end)

    -- ── Server event listeners ────────────────────────────────────────────────

    -- GunService confirmed a hit on the server. Show the hitmarker and log.
    HitConfirmed.OnClientEvent:Connect(function()
        CrosshairUI:ShowHitmarker()
        Logger.debug("[GunController] HIT")
    end)

    -- GunService updated this player's ammo. Cache for dry-fire check and GetAmmo().
    -- HUD listens to AmmoChanged independently for its display.
    AmmoChanged.OnClientEvent:Connect(function(mag: number, reserve: number)
        currentMag     = mag
        currentReserve = reserve
        Logger.debug(string.format("[GunController] Ammo: %d / %d", mag, reserve))
    end)

    -- DamageService updated this player's health.
    HealthChanged.OnClientEvent:Connect(function(current: number, maximum: number)
        Logger.debug(string.format("[GunController] Health: %d / %d", current, maximum))
    end)

    Logger.debug("[GunController] Ready")
end

-- Returns the locally cached magazine and reserve ammo counts.
-- These mirror the server-authoritative values from the last AmmoChanged event.
function GunController:GetAmmo(): (number, number)
    return currentMag, currentReserve
end

return GunController
