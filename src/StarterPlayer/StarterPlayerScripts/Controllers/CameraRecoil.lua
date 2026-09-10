--!strict
-- Local camera presentation only. Server hit/damage validation is unchanged.
local RunService = game:GetService("RunService")
local Constants = require(game:GetService("ReplicatedStorage").Modules.Constants)
local Recoil = {}
local position = Vector2.zero
local velocity = Vector2.zero
local applied = CFrame.new()
local appliedCamera: Camera? = nil
local started = false
local random = Random.new()
local BEFORE = "BR_RecoilRemove"
local AFTER = "BR_RecoilApply"

local function removeApplied()
	if appliedCamera and workspace.CurrentCamera == appliedCamera then
		appliedCamera.CFrame = appliedCamera.CFrame * applied:Inverse()
	end
	appliedCamera = nil
	applied = CFrame.new()
end

function Recoil.Reset()
	removeApplied()
	position = Vector2.zero
	velocity = Vector2.zero
end

function Recoil.Kick(up: number, side: number)
	-- Critical spring impulse: isolated peak displacement is approximately up degrees.
	local scale = Constants.CAMERA_RECOIL_SPRING * math.exp(1)
	velocity += Vector2.new(up, random:NextNumber(-side, side)) * scale
	local limit = Constants.CAMERA_RECOIL_MAX_VELOCITY
	velocity = Vector2.new(math.clamp(velocity.X,-limit,limit),math.clamp(velocity.Y,-limit,limit))
end

function Recoil.GetOffset(): CFrame
	return CFrame.Angles(math.rad(position.X),math.rad(position.Y),0)
end

function Recoil.Start()
	if started then return end
	started = true
	-- Remove only our previous offset before the default camera consumes mouse input.
	RunService:BindToRenderStep(BEFORE,Enum.RenderPriority.Camera.Value-1,removeApplied)
	RunService:BindToRenderStep(AFTER,Enum.RenderPriority.Camera.Value+1,function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then return end
		local omega = Constants.CAMERA_RECOIL_SPRING
		local decay = math.exp(-omega*dt)
		local c = velocity + position*omega
		position = (position+c*dt)*decay
		velocity = (velocity-c*(omega*dt))*decay
		position = Vector2.new(
			math.clamp(position.X,0,Constants.CAMERA_RECOIL_MAX_PITCH),
			math.clamp(position.Y,-Constants.CAMERA_RECOIL_MAX_YAW,Constants.CAMERA_RECOIL_MAX_YAW)
		)
		applied = Recoil.GetOffset()
		camera.CFrame *= applied
		appliedCamera = camera
	end)
end

function Recoil.destroy()
	RunService:UnbindFromRenderStep(BEFORE)
	RunService:UnbindFromRenderStep(AFTER)
	Recoil.Reset()
	started = false
end
return Recoil
