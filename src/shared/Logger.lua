--!strict
-- ModuleScript
-- Location in Studio: ReplicatedStorage > Modules > Logger
--
-- Centralised output module. All services and controllers use this instead of
-- calling print() or warn() directly.
--
-- Set DEBUG_MODE to false before shipping to silence all debug output without
-- touching any other file. Logger.warn() is always active regardless of the flag.

local Logger = {}

local DEBUG_MODE = true

-- Prints to Output only when DEBUG_MODE is true.
-- Use for development tracing: phase transitions, health resets, team assignments.
function Logger.debug(...)
    if DEBUG_MODE then
        print("[DEBUG]", ...)
    end
end

-- Always calls Roblox warn() so output appears red in the Output window.
-- Use for unexpected states: missing assets, malformed payloads, nil where a
-- value was required, pcall errors.
function Logger.warn(...)
    warn("[WARN]", ...)
end

return Logger
