--[[
	Combat.luau
	The click. Every click / tap that is not on UI (and while no window
	is open) is sent to the server as ClickHit:FireServer(mob?) -- the
	mob under the cursor, if any. The server gives Aura for the click,
	adds the trainer bonus, hits a mob in the dungeon and answers with
	"Aura" / "Tick" / "Hit" / "Kill", which become popups, flashes,
	particles, sounds and camera shake here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local HubFx = require(script.Parent.HubFx)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)
local Swing = require(script.Parent.Swing)
local Window = require(script.Parent.ui.Windows.Window)

local player = Players.LocalPlayer

local Combat = {}

local clickHit = ReplicatedStorage:WaitForChild("ClickHit")
local lanesFolder = Workspace:WaitForChild("Dungeon"):WaitForChild("Lanes")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { lanesFolder }

local lastSent = 0

-- A mob is a Model with a Humanoid and a "Room" attribute.
local function mobFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("Room") and model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function click(ray: Ray)
	if Window.AnyOpen() then
		return
	end
	local now = os.clock()
	if now - lastSent < Config.Click.Cooldown then
		return
	end
	lastSent = now
	local target = nil
	if player:GetAttribute("Zone") == "Dungeon" then
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
		target = result and mobFromPart(result.Instance)
	end
	Swing.Local()
	clickHit:FireServer(target)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- the click landed on a button / window
	end
	local camera = Workspace.CurrentCamera
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		click(camera:ViewportPointToRay(mouse.X, mouse.Y))
	elseif input.UserInputType == Enum.UserInputType.Touch then
		click(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	end
end)

---------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------

local function flash(model, isCrit)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = if isCrit then Style.Colors.Gold else Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Style.Tween(highlight, 0.18, { FillTransparency = 1 })
	task.delay(0.18, function()
		highlight:Destroy()
	end)
end

local function hitParticles(position: Vector3, color: Color3, count: number)
	if Style.HideEffects then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	task.delay(1, function()
		attachment:Destroy()
	end)
end
Combat.Particles = hitParticles

local function topOf(model)
	return model:GetPivot().Position + Vector3.new(0, model:GetExtentsSize().Y / 2, 0)
end

local function trainerTop(model)
	local object = model:FindFirstChild("Object") or model
	local height = object:GetAttribute("Height") or 6
	local center = model:GetAttribute("Center")
	local base = if center then Vector3.new(object:GetPivot().Position.X, center.Y, object:GetPivot().Position.Z) else object:GetPivot().Position
	return base + Vector3.new(0, height + 1.5, 0), object
end

local function headPosition(): Vector3?
	local head = player.Character and player.Character:FindFirstChild("Head")
	return head and head.Position + Vector3.new(0, 2.5, 0)
end

clickHit.OnClientEvent:Connect(function(kind, ...)
	if kind == "Aura" then
		local gained, isCrit, trainer = ...
		local color = if isCrit then Style.Colors.Gold else Style.Colors.Cyan
		local text = (if isCrit then "КРИТ! +" else "+") .. Format.Number(gained)
		if trainer and trainer.Parent then
			local position, object = trainerTop(trainer)
			Popups.World(position, text, color, if isCrit then 40 else 28, isCrit)
			flash(object, isCrit)
			HubFx.Squash(trainer)
			hitParticles(object:GetPivot().Position + Vector3.new(0, 2, 0), color, if isCrit then 12 else 4)
		else
			local position = headPosition()
			if position then
				Popups.World(position, text, color, if isCrit then 34 else 24, isCrit)
			end
		end
		Style.PlaySound(Config.Sounds.Click, if isCrit then 0.7 else 1 + (math.random() - 0.5) * 0.15, 0.35)
		if isCrit then
			Popups.Shake(Config.Hud.ShakeCrit.Amplitude, Config.Hud.ShakeCrit.Seconds)
		end
	elseif kind == "Tick" then
		local trainer, gained = ...
		if trainer and trainer.Parent then
			local position = trainerTop(trainer)
			Popups.World(position + Vector3.new(0, 1, 0), "+" .. Format.Number(gained) .. " ✨", Style.Colors.Green, 30, false)
			HubFx.Squash(trainer)
		end
	elseif kind == "Hit" then
		local model, damage, isCrit = ...
		if not model or not model.Parent then
			return
		end
		Popups.World(topOf(model), (if isCrit then "КРИТ! " else "") .. Format.Number(damage), if isCrit then Style.Colors.Gold else Style.Colors.Text, if isCrit then 44 else 30, isCrit)
		flash(model, isCrit)
		hitParticles(model:GetPivot().Position, if isCrit then Style.Colors.Gold else Style.Colors.Orange, if isCrit then 16 else 7)
		Style.PlaySound(Config.Sounds.Hit, if isCrit then 0.8 else 1 + (math.random() - 0.5) * 0.2, 0.4)
		if isCrit then
			Popups.Shake(Config.Hud.ShakeCrit.Amplitude, Config.Hud.ShakeCrit.Seconds)
		end
	elseif kind == "Kill" then
		local position, isBoss = ...
		hitParticles(position, if isBoss then Style.Colors.Gold else Style.Colors.Magenta, if isBoss then 60 else 20)
		if isBoss then
			Popups.Shake(Config.Hud.ShakeBoss.Amplitude, Config.Hud.ShakeBoss.Seconds)
			Popups.Toast("👑 Босс побеждён!", "gold")
			Style.PlaySound(Config.Sounds.BossDeath, 1, 0.8)
		end
	end
end)

return Combat
