--!strict
-- LocalScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ClientInit
--
-- Thin runner that requires every client controller ModuleScript and calls Start().
-- This is the only LocalScript in the Controllers folder. All controllers are
-- ModuleScripts so they can be required by each other without running automatically.
--
-- Initialization order is explicit and load-order-safe:
--   1. MatchController      — must be first; owns GetPhase() which GunController reads
--   2. MatchUI              — reads RoundStateChanged; needs PlayerGui
--   3. HUD                  — reads HealthChanged, TeamStatusUpdate, RoundStateChanged; needs PlayerGui
--   4. DeathScreen          — reads RagdollApplied, RoundStateChanged; needs PlayerGui
--   5. CrosshairUI          — reads RoundStateChanged, exposes ShowHitmarker(); needs PlayerGui
--   6. ViewModelController  — reads RoundStateChanged, exposes PlayFireAnimation(); no PlayerGui
--   7. GunController        — reads MatchController:GetPhase(); calls ViewModelController and CrosshairUI
--
-- GunController requires ViewModelController and CrosshairUI at module level, so both
-- must be initialized (Start()ed) before GunController:Start() runs — hence the order above.
-- DeathScreen has no deps on other controllers and none depend on it; position 4 is arbitrary.
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

-- 5. CrosshairUI — no dependency on other controllers; needs PlayerGui
--    Must start before GunController so ShowHitmarker() is ready when HitConfirmed fires.
loadInitAndStart("CrosshairUI", function()
    return require(script.Parent:WaitForChild("UI"):WaitForChild("CrosshairUI"))
end)

-- 6. ViewModelController — no PlayerGui; must start before GunController so
--    PlayFireAnimation() and GetBarrelTipCFrame() are available when the first shot fires.
loadAndStart("ViewModelController", function()
    return require(script.Parent:WaitForChild("ViewModelController"))
end)

-- 7. GunController — reads MatchController:GetPhase(), calls ViewModelController and CrosshairUI
loadAndStart("GunController", function()
    return require(script.Parent:WaitForChild("GunController"))
end)

Logger.debug("[ClientInit] Startup complete")
