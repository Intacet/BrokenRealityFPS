--!strict
-- ModuleScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > FreeAimController
--
-- Stage 1 free-aim foundation (visual / input only).
-- Tracks a screen-space aim offset driven by mouse delta, smoothed and clamped
-- to a circular deadzone radius.  Exposes the offset for CrosshairUI and
-- ViewModelController to consume each frame via GunController.
--
-- What this module does NOT do:
--   - Change bullet direction or camera.CFrame       (Stage 2 only — see DEBT-063)
--   - Modify server remotes, damage, or hit validation
--   - Replace the Roblox camera system
--
-- Initialized by ClientInit via loadAndInit() which calls :Init().
-- GunController:Start() pushes state (SetSprinting, SetAiming, SetReloading,
-- SetWeaponEquipped) and reads offsets (GetSmoothedAimOffset,
-- GetNormalizedAimOffset) each RenderStepped.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules    = ReplicatedStorage:WaitForChild("Modules")
local Constants  = require(Modules:WaitForChild("Constants"))
local Logger     = require(Modules:WaitForChild("Logger"))

-- ============================================================
-- Module-level state
-- ============================================================

-- Raw aim offset in screen pixels, clamped to the active deadzone radius.
local aimOffset: Vector2 = Vector2.zero

-- Smoothed version of aimOffset; CrosshairUI uses this for display.
local smoothedOffset: Vector2 = Vector2.zero

-- Master enabled flag.  Can be toggled at runtime; suppressed when false.
local enabled: boolean = true

-- Updated each frame by GunController to reflect current game state.
local weaponEquipped: boolean = false
local isAiming:       boolean = false
local isSprinting:    boolean = false
local isReloading:    boolean = false

-- Cleanup table for RBXScriptConnections created in Init().
local _connections: { RBXScriptConnection } = {}

-- ============================================================
-- Private helpers
-- ============================================================

-- Returns true when the free-aim system should NOT update the aim offset
-- (it instead lerps back toward zero).
local function isSuppressed(): boolean
    if not enabled then return true end
    if not weaponEquipped then return true end
    if isSprinting and Constants.FREE_AIM_DISABLE_WHILE_SPRINTING then return true end
    if isReloading and Constants.FREE_AIM_DISABLE_WHILE_RELOADING then return true end
    return false
end

-- Returns the active deadzone radius in pixels based on ADS state.
local function activeRadius(): number
    if isAiming then
        return Constants.FREE_AIM_ADS_RADIUS_PIXELS
    end
    return Constants.FREE_AIM_RADIUS_PIXELS
end

-- Clamps vector v to a circle of radius r.  Returns v unchanged if within radius.
local function clampCircle(v: Vector2, r: number): Vector2
    local mag = v.Magnitude
    if mag <= r then return v end
    return v * (r / mag)
end

-- ============================================================
-- Controller
-- ============================================================

local FreeAimController = {}

-- Starts the per-frame aim-offset tracking loop and resets state on respawn.
-- Called once by ClientInit before GunController:Start().
function FreeAimController:Init(): ()
    Logger.debug("[FreeAimController] Initialized — free aim " ..
        (Constants.FREE_AIM_ENABLED and "ENABLED" or "DISABLED"))

    local renderConn = RunService.RenderStepped:Connect(function(dt: number)
        if not Constants.FREE_AIM_ENABLED then
            aimOffset      = Vector2.zero
            smoothedOffset = Vector2.zero
            return
        end

        local suppressed = isSuppressed()

        if suppressed then
            -- Smoothly return offset toward zero while suppressed.
            local returnSpeed = isAiming
                and Constants.FREE_AIM_ADS_RETURN_SPEED
                or  Constants.FREE_AIM_RETURN_SPEED
            aimOffset      = aimOffset:Lerp(Vector2.zero, math.min(1, dt * returnSpeed))
            smoothedOffset = smoothedOffset:Lerp(
                Vector2.zero,
                math.min(1, dt * Constants.FREE_AIM_CROSSHAIR_SMOOTH_SPEED)
            )
            return
        end

        local radius = activeRadius()
        local delta  = UserInputService:GetMouseDelta()

        -- Push aim point by scaled mouse delta, then clamp to circular radius.
        aimOffset = aimOffset + delta * Constants.FREE_AIM_MOUSE_GAIN
        aimOffset = clampCircle(aimOffset, radius)

        -- Return toward center when the mouse is still.
        if delta.Magnitude < 0.5 then
            local returnSpeed = isAiming
                and Constants.FREE_AIM_ADS_RETURN_SPEED
                or  Constants.FREE_AIM_RETURN_SPEED
            aimOffset = aimOffset:Lerp(Vector2.zero, math.min(1, dt * returnSpeed))
        end

        -- Smooth the crosshair position; this is what CrosshairUI displays.
        smoothedOffset = smoothedOffset:Lerp(
            aimOffset,
            math.min(1, dt * Constants.FREE_AIM_CROSSHAIR_SMOOTH_SPEED)
        )
    end)
    table.insert(_connections, renderConn)

    -- Reset all state on character respawn so free aim starts clean.
    local respawnConn = Players.LocalPlayer.CharacterAdded:Connect(function(_: Model)
        aimOffset      = Vector2.zero
        smoothedOffset = Vector2.zero
        weaponEquipped = false
        isAiming       = false
        isSprinting    = false
        isReloading    = false
        Logger.debug("[FreeAimController] Offset and state reset on character respawn")
    end)
    table.insert(_connections, respawnConn)
end

-- ============================================================
-- Public API — state setters (called by GunController each frame/event)
-- ============================================================

-- Toggles the free-aim system on or off.  Off → offsets lerp to zero.
function FreeAimController:SetEnabled(enabled_: boolean): ()
    assert(typeof(enabled_) == "boolean", "[FreeAimController] SetEnabled: expected boolean")
    enabled = enabled_
    Logger.debug("[FreeAimController] Free aim " .. (enabled_ and "enabled" or "disabled"))
end

-- Returns true when the free-aim system is enabled.
function FreeAimController:IsEnabled(): boolean
    return enabled
end

-- Notifies whether a weapon is currently equipped in the player's hands.
-- Free aim is suppressed (offsets lerp to zero) when no weapon is equipped.
function FreeAimController:SetWeaponEquipped(isEquipped: boolean): ()
    assert(typeof(isEquipped) == "boolean", "[FreeAimController] SetWeaponEquipped: expected boolean")
    weaponEquipped = isEquipped
    Logger.debug("[FreeAimController] Weapon equipped: " .. tostring(isEquipped))
end

-- Notifies whether the player is currently aiming down sights (ADS).
-- ADS uses a smaller deadzone radius and faster return speed.
function FreeAimController:SetAiming(isAiming_: boolean): ()
    assert(typeof(isAiming_) == "boolean", "[FreeAimController] SetAiming: expected boolean")
    isAiming = isAiming_
end

-- Notifies whether the player is currently sprinting.
-- Suppresses free aim when FREE_AIM_DISABLE_WHILE_SPRINTING is true.
function FreeAimController:SetSprinting(isSprinting_: boolean): ()
    assert(typeof(isSprinting_) == "boolean", "[FreeAimController] SetSprinting: expected boolean")
    isSprinting = isSprinting_
end

-- Notifies whether the player is currently reloading.
-- Suppresses free aim when FREE_AIM_DISABLE_WHILE_RELOADING is true.
function FreeAimController:SetReloading(isReloading_: boolean): ()
    assert(typeof(isReloading_) == "boolean", "[FreeAimController] SetReloading: expected boolean")
    isReloading = isReloading_
end

-- Instantly resets the aim offset and smoothed offset to zero.
-- Called on holster (when FREE_AIM_RESET_ON_HOLSTER is true) and on respawn.
function FreeAimController:ResetOffset(): ()
    aimOffset      = Vector2.zero
    smoothedOffset = Vector2.zero
end

-- ============================================================
-- Public API — offset readers
-- ============================================================

-- Returns the raw clamped aim offset in screen pixels.
-- Rarely needed externally; prefer GetSmoothedAimOffset for display.
function FreeAimController:GetAimOffset(): Vector2
    return aimOffset
end

-- Returns the smoothed aim offset in screen pixels.
-- Used by CrosshairUI:SetFreeAimOffset() to move the crosshair.
function FreeAimController:GetSmoothedAimOffset(): Vector2
    return smoothedOffset
end

-- Returns the smoothed aim offset normalized to [-1, 1] in each axis,
-- relative to the active deadzone radius.
-- Used by ViewModelController:SetFreeAimOffset() to drive the weapon lean.
function FreeAimController:GetNormalizedAimOffset(): Vector2
    local r = activeRadius()
    if r <= 0 then return Vector2.zero end
    return smoothedOffset / r
end

-- Returns the viewport point (pixels) corresponding to the current free-aim offset.
-- Computed as screen-center + smoothedOffset.
-- Exposed for HUD markers or debug overlays; not used in Stage 1 firing.
function FreeAimController:GetAimViewportPoint(): Vector2
    local camera = workspace.CurrentCamera
    local vp     = camera.ViewportSize
    return Vector2.new(vp.X * 0.5 + smoothedOffset.X, vp.Y * 0.5 + smoothedOffset.Y)
end

-- Stage 2 API: returns a Ray from the camera through the free-aim viewport point.
-- NOT wired into firing in Stage 1 — this is a forward-declared API only.
-- See DEBT-063 before enabling for gameplay or local raycast prediction.
function FreeAimController:GetAimRay(maxDistance: number?): Ray
    assert(
        maxDistance == nil or typeof(maxDistance) == "number",
        "[FreeAimController] GetAimRay: maxDistance must be nil or number"
    )
    local camera = workspace.CurrentCamera
    if not camera then
        Logger.warn("[FreeAimController] GetAimRay: workspace.CurrentCamera unavailable")
        return Ray.new(Vector3.zero, Vector3.new(0, 0, -1))
    end
    local dist  = maxDistance or 500
    local vp    = self:GetAimViewportPoint()
    local ray3D = camera:ViewportPointToRay(vp.X, vp.Y)
    return Ray.new(ray3D.Origin, ray3D.Direction * dist)
end

return FreeAimController
