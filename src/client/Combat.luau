--[[
	Combat.luau
	Click (or tap) a dungeon mob or a hub trainer to hit it. The client
	only reports WHICH model was clicked (ClickHit:FireServer(model));
	the server checks range/cooldown/room access, rolls damage and
	answers with "Hit" / "Kill" / "Pickup" / "Train", which become
	popups, flashes, knockback, particles and camera shake here.
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

local player = Players.LocalPlayer

local Combat = {}

local clickHit = ReplicatedStorage:WaitForChild("ClickHit")
local mobsFolder = Workspace:WaitForChild("Dungeon"):WaitForChild("Mobs")
local trainersFolder = Workspace:WaitForChild("Hub"):WaitForChild("Trainers")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { mobsFolder, trainersFolder }

local lastSent = 0
local lastHint = 0

local function targetFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	if model and (model.Parent == mobsFolder or model.Parent == trainersFolder) then
		return model
	end
	return nil
end

local function hint(text)
	if os.clock() - lastHint > 1.5 then
		lastHint = os.clock()
		Popups.Toast(text)
	end
end

local function tryHitAt(ray: Ray)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local target = result and targetFromPart(result.Instance)
	if not target then
		return
	end
	local now = os.clock()
	if now - lastSent < Config.Click.Cooldown then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - target:GetPivot().Position).Magnitude > Config.Click.Range then
		hint("Подойди ближе!")
		return
	end
	local room = target:GetAttribute("Room")
	if room and (player:GetAttribute("RoomReached") or 0) < room - 1 then
		hint(("Сначала пройди этап %d"):format(room - 1))
		return
	end
	-- Trainers: you have to stand on the platform.
	local center = target:GetAttribute("Center")
	if center and root then
		local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		if flat.Magnitude > (target:GetAttribute("Radius") or 5) + 1 then
			hint("Встань на платформу тренажёра")
			return
		end
	end
	lastSent = now
	clickHit:FireServer(target)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local camera = Workspace.CurrentCamera
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		tryHitAt(camera:ViewportPointToRay(mouse.X, mouse.Y))
	elseif input.UserInputType == Enum.UserInputType.Touch then
		tryHitAt(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	end
end)

---------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------

local function flash(model, isCrit)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = if isCrit then Style.Colors.Gold else Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Style.Tween(highlight, 0.18, { FillTransparency = 1 })
	task.delay(0.18, function()
		highlight:Destroy()
	end)
end

-- Local knockback: nudge the (anchored, replicated) model back and return.
local knocking = {}
local function knockback(model)
	if knocking[model] then
		return
	end
	knocking[model] = true
	local origin = model:GetPivot()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local away = if root then (origin.Position - root.Position) * Vector3.new(1, 0, 1) else Vector3.new(0, 0, -1)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, -1)
	task.spawn(function()
		for i = 1, 4 do
			if not model.Parent then
				break
			end
			local k = (if i <= 2 then i else 4 - i) * 0.35
			model:PivotTo(origin * CFrame.new(0, 0, 0) + away * k)
			task.wait(0.03)
		end
		if model.Parent then
			model:PivotTo(origin)
		end
		knocking[model] = nil
	end)
end

local function hitParticles(position: Vector3, color: Color3, count: number)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
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

-- Death: a few colored cubes burst out and fade (local only).
local function pop(position: Vector3, color: Color3, big: boolean)
	local count = if big then 14 else 7
	for _ = 1, count do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.one * (if big then 1.4 else 0.8)
		chunk.Color = color
		chunk.Material = Enum.Material.Neon
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.Position = position
		chunk.Velocity = Vector3.new((math.random() - 0.5) * 40, 20 + math.random() * 25, (math.random() - 0.5) * 40)
		chunk.RotVelocity = Vector3.new(math.random() * 10, math.random() * 10, math.random() * 10)
		chunk.Parent = Workspace
		Style.Tween(chunk, 0.9, { Transparency = 1, Size = Vector3.one * 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(1, function()
			chunk:Destroy()
		end)
	end
	hitParticles(position, color, if big then 60 else 20)
end

local function topOf(model)
	return model:GetPivot().Position + Vector3.new(0, model:GetExtentsSize().Y / 2, 0)
end

clickHit.OnClientEvent:Connect(function(kind, ...)
	if kind == "Hit" then
		local model, damage, isCrit = ...
		if not model or not model.Parent then
			return
		end
		Popups.World(topOf(model), (if isCrit then "КРИТ! " else "") .. Format.Number(damage), if isCrit then Style.Colors.Gold else Style.Colors.Text, if isCrit then 44 else 30, isCrit)
		flash(model, isCrit)
		knockback(model)
		hitParticles(model:GetPivot().Position, if isCrit then Style.Colors.Gold else Style.Colors.Cyan, if isCrit then 14 else 5)
		Style.PlaySound(Config.Sounds.Hit, if isCrit then 0.8 else 1 + (math.random() - 0.5) * 0.2, 0.4)
		if isCrit then
			Popups.Shake(Config.Hud.ShakeCrit.Amplitude, Config.Hud.ShakeCrit.Seconds)
		end
	elseif kind == "Train" then
		local model, aura, isCrit = ...
		if not model or not model.Parent then
			return
		end
		local object = model:FindFirstChild("Object") or model
		local height = object:GetAttribute("Height") or 6
		Popups.World(object:GetPivot().Position + Vector3.new(0, height + 1, 0), "+" .. Format.Number(aura) .. " ✨", if isCrit then Style.Colors.Gold else Style.Colors.Cyan, if isCrit then 40 else 28, isCrit)
		flash(object, isCrit)
		HubFx.Squash(model)
		Style.PlaySound(Config.Sounds.Click, if isCrit then 0.7 else 1 + (math.random() - 0.5) * 0.15, 0.5)
		if isCrit then
			Popups.Shake(Config.Hud.ShakeCrit.Amplitude, Config.Hud.ShakeCrit.Seconds)
		end
	elseif kind == "Kill" then
		local position, isBoss = ...
		pop(position, if isBoss then Style.Colors.Gold else Style.Colors.Magenta, isBoss)
		if isBoss then
			Popups.Shake(Config.Hud.ShakeBoss.Amplitude, Config.Hud.ShakeBoss.Seconds)
			Popups.Toast("👑 Босс побеждён!", "gold")
			Style.PlaySound(Config.Sounds.BossDeath, 1, 0.8)
		end
	elseif kind == "Pickup" then
		local position, aura = ...
		Popups.World(position + Vector3.new(0, 2, 0), "+" .. Format.Number(aura) .. " ✨", Style.Colors.Gold, 34, false)
		hitParticles(position, Config.MobLooks.Drop.Color, 12)
		Style.PlaySound(Config.Sounds.Pickup, 1.5, 0.5)
	end
end)

return Combat
