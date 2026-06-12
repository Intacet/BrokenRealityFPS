--!strict
-- LocalScript
-- Location in Studio: StarterPlayer > StarterPlayerScripts > Controllers > GraphicsQuality
--
-- Forces the client to render at Roblox quality level 21 (maximum) on join.
-- Level 21 enables:
--   • Maximum shadow draw distance and cascade count
--   • Full-resolution texture streaming
--   • Maximum particle render count
--   • Highest-detail LOD meshes
--
-- Players on low-end hardware will experience frame drops.
-- This is intentional: the game targets high-fidelity presentation.
-- To allow quality scaling, remove this script or change QualityLevel21 to Automatic.

local UserGameSettings = UserSettings():GetService("UserGameSettings")
UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel21
