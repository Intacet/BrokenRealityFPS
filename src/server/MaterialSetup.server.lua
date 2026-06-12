--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > MaterialSetup
--
-- Applies PBR material overrides game-wide via MaterialService MaterialVariants.
-- A MaterialVariant parented to MaterialService automatically overrides every
-- BasePart whose Material matches its BaseMaterial — no per-part iteration needed.
--
-- Concrete texture IDs: sourced from "PBR Concrete Material" on Creator Store
-- and verified in Studio on 2026-06-12.
--
-- To add a second material: copy the makeMV() call pattern below.

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Logger = require(Modules:WaitForChild("Logger"))

-- Enable 2022-era material rendering so MaterialVariants take effect.
MaterialService.Use2022Materials = true

-- Remove stale variants created by a previous run (idempotent in Studio).
for _, child in MaterialService:GetChildren() do
	if child:IsA("MaterialVariant") then
		child:Destroy()
	end
end

local function makeMV(name: string, base: Enum.Material, colorMap: string, normalMap: string, roughnessMap: string)
	local mv = Instance.new("MaterialVariant")
	mv.Name = name
	mv.BaseMaterial = base
	mv.ColorMap = colorMap
	mv.NormalMap = normalMap
	mv.RoughnessMap = roughnessMap
	mv.Parent = MaterialService
end

-- Concrete: exterior walls, structural columns, ground slabs, curbs.
-- Covers all BaseParts with Material = Enum.Material.Concrete.
makeMV(
	"ConcretePBR",
	Enum.Material.Concrete,
	"rbxassetid://100279855158442",
	"rbxassetid://17625608783",
	"rbxassetid://17625606986"
)

Logger.debug("[MaterialSetup] PBR MaterialVariant applied (Concrete).")
