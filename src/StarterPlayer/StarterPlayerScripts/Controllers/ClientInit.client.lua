--!strict
-- LocalScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ClientInit
--
-- Thin runner that requires every client controller ModuleScript and calls Start().
-- This is the only LocalScript in the Controllers folder. All controllers are
-- ModuleScripts so they can be required by each other without running automatically.
--
-- Initialization order is explicit and load-order-safe:
--   1.  MatchController      — must be first; owns GetPhase() which GunController reads
--   2.  MatchUI              — reads RoundStateChanged; needs PlayerGui
--   3.  HUD                  — reads HealthChanged, TeamStatusUpdate, RoundStateChanged; needs PlayerGui
--   4.  DeathScreen          — reads RagdollApplied, RoundStateChanged; needs PlayerGui
--   5.  KillFeedUI           — reads KillFeed; needs PlayerGui; no deps on other controllers
--   6.  CrosshairUI          — reads RoundStateChanged, exposes ShowHitmarker() + SetFreeAimOffset();
--                              needs PlayerGui
--   7.  ViewModelController  — reads RoundStateChanged, exposes PlayFireAnimation(),
--                              SetFreeAimOffset(), GetIsReloading(); no PlayerGui
--                              requires MovementController at module level (no circular)
--   8.  SoundController      — reads HitConfirmed, RagdollApplied; no PlayerGui; must start before GunController
--   9.  MovementController   — reads RoundStateChanged; uses MatchController:GetPhase(); owns
--                              movementState and Humanoid.WalkSpeed; reads camera.CFrame for
--                              direction detection (does NOT write camera.CFrame or CameraOffset);
--                              must start before GunController reads GetMoveState() / IsADSBlocked()
--   10. FreeAimController    — Stage 1 free-aim; requires only Constants + Logger (no circular);
--                              must Init() before GunController:Start() so the RenderStepped loop
--                              is live when GunController begins pushing state each frame
--   11. FootstepController   — Stage 1 timer-based footstep audio; requires MovementController
--                              (position 9) for GetMoveState(); no dep on GunController
--   12. GunController        — reads MatchController:GetPhase(); calls ViewModelController,
--                              CrosshairUI, SoundController, MovementController, FreeAimController
--
-- GunController requires ViewModelController, CrosshairUI, SoundController, MovementController,
-- and FreeAimController at module level, so all five must be initialized before GunController:Start().
-- DeathScreen and KillFeedUI have no deps on other controllers and none depend on them.
--
-- To add a new controller: require it here and call its Start() (or init()+Start())
-- inside the appropriate helper. Keep the order intentional and document any dependency.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Logger  = require(Modules:WaitForChild("Logger"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- Helpers
-- ============================================================

-- Requires a controller module and calls its Start() method.
-- Both steps are guarded so a failure in one controller does not prevent
-- the others from initializing, and no failure is ever silent.
local function loadAndStart(name: string, getModule: () -> any)
    local loadOk, controller = pcall(getModule)
    if not loadOk then
        Logger.warn("[ClientInit] Failed to require " .. name .. ": " .. tostring(controller))
        return
    end
    local startOk, startErr = pcall(function()
        controller:Start()
    end)
    if startOk then
        Logger.debug("[ClientInit] " .. name .. " initialized")
    else
        Logger.warn("[ClientInit] " .. name .. " Start() error: " .. tostring(startErr))
    end
end

-- Requires a module that exposes a single Init() method (capital I, no Start()).
-- Used for controllers that initialize via one call rather than the init()+Start() split.
-- FreeAimController follows this pattern — it starts its RenderStepped loop inside Init().
local function loadAndInit(name: string, getModule: () -> any)
    local loadOk, controller = pcall(getModule)
    if not loadOk then
        Logger.warn("[ClientInit] Failed to require " .. name .. ": " .. tostring(controller))
        return
    end
    local initOk, initErr = pcall(function()
        controller:Init()
    end)
    if initOk then
        Logger.debug("[ClientInit] " .. name .. " initialized")
    else
        Logger.warn("[ClientInit] " .. name .. " Init() error: " .. tostring(initErr))
    end
end

-- Requires a non-UI module that has both init() and Start() with no PlayerGui argument.
-- Used for controllers that set up internal state in init() before connecting events in Start().
local function loadInitNoGuiAndStart(name: string, getModule: () -> any)
    local loadOk, controller = pcall(getModule)
    if not loadOk then
        Logger.warn("[ClientInit] Failed to require " .. name .. ": " .. tostring(controller))
        return
    end
    local initOk, initErr = pcall(function()
        controller:init()
    end)
    if not initOk then
        Logger.warn("[ClientInit] " .. name .. " init() error: " .. tostring(initErr))
        return
    end
    local startOk, startErr = pcall(function()
        controller:Start()
    end)
    if startOk then
        Logger.debug("[ClientInit] " .. name .. " initialized")
    else
        Logger.warn("[ClientInit] " .. name .. " Start() error: " .. tostring(startErr))
    end
end

-- Requires a UI module that needs PlayerGui, calls init(playerGui), then Start().
-- Used for UI controllers that create their ScreenGui in init().
local function loadInitAndStart(name: string, getModule: () -> any)
    local loadOk, controller = pcall(getModule)
    if not loadOk then
        Logger.warn("[ClientInit] Failed to require " .. name .. ": " .. tostring(controller))
        return
    end
    local initOk, initErr = pcall(function()
        controller:init(playerGui)
    end)
    if not initOk then
        Logger.warn("[ClientInit] " .. name .. " init() error: " .. tostring(initErr))
        return
    end
    local startOk, startErr = pcall(function()
        controller:Start()
    end)
    if startOk then
        Logger.debug("[ClientInit] " .. name .. " initialized")
    else
        Logger.warn("[ClientInit] " .. name .. " Start() error: " .. tostring(startErr))
    end
end

-- ============================================================
-- Initialization — order is intentional, do not reorder without reading above
-- ============================================================

-- 1. MatchController — must start first; other controllers read GetPhase()
loadAndStart("MatchController", function()
    return require(script.Parent:WaitForChild("MatchController"))
end)

-- 2. MatchUI — no dependency on other controllers; needs PlayerGui
loadInitAndStart("MatchUI", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("MatchUI"))
end)

-- 3. HUD — no dependency on other controllers; needs PlayerGui
loadInitAndStart("HUD", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("HUD"))
end)

-- 4. DeathScreen — no dependency on other controllers; needs PlayerGui
loadInitAndStart("DeathScreen", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("DeathScreen"))
end)

-- 5. KillFeedUI — no dependency on other controllers; needs PlayerGui
loadInitAndStart("KillFeedUI", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("KillFeedUI"))
end)

-- 6. CrosshairUI — no dependency on other controllers; needs PlayerGui
--    Must start before GunController so ShowHitmarker() is ready when HitConfirmed fires.
loadInitAndStart("CrosshairUI", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("CrosshairUI"))
end)

-- 7. ViewModelController — no PlayerGui; must start before GunController so
--    PlayFireAnimation() and GetBarrelTipCFrame() are available when the first shot fires.
loadAndStart("ViewModelController", function()
    return require(script.Parent:WaitForChild("ViewModelController"))
end)

-- 8. SoundController — no PlayerGui; must start before GunController so PlayGunshot()
--    is available when the first shot fires. Uses init()+Start() (no PlayerGui arg).
loadInitNoGuiAndStart("SoundController", function()
    return require(script.Parent:WaitForChild("SoundController"))
end)

-- 9. MovementController — no PlayerGui; Stage 1: walk/sprint/crouch speed, 8-dir direction
--    detection, phase gating, respawn handling, connection cleanup. Must start before
--    GunController so GetMoveState(), IsADSBlocked(), and GetViewmodelAddCFrame()
--    return valid state when the first shot fires. Depends on MatchController (position 1).
loadAndStart("MovementController", function()
    return require(script.Parent:WaitForChild("MovementController"))
end)

-- 10. FreeAimController — Stage 1 free-aim foundation. Requires only Constants + Logger
--     (no circular dependency). Must Init() before GunController:Start() so the
--     RenderStepped aim-offset loop is live when GunController first reads offsets.
--     GunController requires FreeAimController at module level; caching it here first
--     ensures the module is ready when GunController's require resolves.
loadAndInit("FreeAimController", function()
    return require(script.Parent:WaitForChild("FreeAimController"))
end)

-- 11. FootstepController — Stage 1 timer-based footstep audio. Requires MovementController
--     (position 9) for GetMoveState(). No dependency on FreeAimController or GunController.
--     Must start after MovementController so GetMoveState() returns valid state.
--     Uses Init() pattern (starts Heartbeat loop inside Init; no separate Start()).
--     10-second timeout: if FootstepController.lua is not yet synced by Rojo, WaitForChild
--     returns nil after 10 s, pcall catches the require(nil) error, and ClientInit continues
--     to GunController rather than hanging the entire startup chain.
loadAndInit("FootstepController", function()
    local mod = script.Parent:WaitForChild("FootstepController", 10)
    assert(mod ~= nil, "FootstepController not found — ensure rojo serve is running and the file is synced")
    return require(mod)
end)

-- 12. GunController — reads MatchController:GetPhase(); calls ViewModelController,
--     CrosshairUI, SoundController, MovementController, and FreeAimController at module
--     level — all five must be initialized (Start()ed / Init()ed) first.
loadAndStart("GunController", function()
    return require(script.Parent:WaitForChild("GunController"))
end)

-- 13. BloodController — world blood VFX driven by the BloodEffect remote. No dependency on
--     any other controller; no PlayerGui. Reusable character system, not dummy-specific.
loadAndStart("BloodController", function()
    return require(script.Parent:WaitForChild("BloodController"))
end)

-- 14. DummyDebugUI — developer-only test-dummy overlay. init() builds nothing unless
--     RunService:IsStudio() or the local UserId is in Constants.DEV_USER_IDS. No deps.
loadInitAndStart("DummyDebugUI", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("DummyDebugUI"))
end)

-- 15. LoadoutMenu — pre-round deployment screen (primary weapon + team pick).
--     Reads only RoundStateChanged and the BR_Loadout* Player attributes; no
--     dependency on other controllers. Fires SelectLoadout on Deploy.
loadInitAndStart("LoadoutMenu", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("LoadoutMenu"))
end)

Logger.debug("[ClientInit] Startup complete")
