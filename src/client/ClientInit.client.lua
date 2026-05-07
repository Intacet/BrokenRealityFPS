--!strict
-- LocalScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > ClientInit
--
-- Thin runner that requires every client controller ModuleScript and calls Start().
-- This is the only LocalScript in the Controllers folder. All controllers are
-- ModuleScripts so they can be required by each other without running automatically.
--
-- Initialization order is explicit and load-order-safe:
--   1. MatchController — must start first; other controllers read GetPhase()
--   2. GunController   — reads MatchController:GetPhase() on every shot attempt
--
-- To add a new controller: require it here and call its Start() inside loadAndStart().
-- Keep the order intentional — document any dependency in a comment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Logger  = require(Modules:WaitForChild("Logger"))

-- ============================================================
-- Helper
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

-- ============================================================
-- Initialization — order is intentional, do not reorder without reading above
-- ============================================================

loadAndStart("MatchController", function()
    return require(script.Parent:WaitForChild("MatchController"))
end)

loadAndStart("GunController", function()
    return require(script.Parent:WaitForChild("GunController"))
end)

Logger.debug("[ClientInit] Startup complete")
