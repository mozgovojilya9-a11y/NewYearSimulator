--[[
	Combat.luau
	Click (or tap) a dungeon mob or a hub trainer to hit it. The client
	only reports WHICH model was clicked (ClickHit:FireServer(model));
	the server checks range/cooldown/room access, rolls damage and
	answers with "Hit" / "Kill" / "Train", which we turn into popups,
	flashes and sounds here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Combat = {}

local clickHit = ReplicatedStorage:WaitForChild("ClickHit")
local mobsFolder = Workspace:WaitForChild("Dungeon"):WaitForChild("Mobs")
local trainersFolder = Workspace:WaitForChild("Hub", 10)
trainersFolder = trainersFolder and trainersFolder:WaitForChild("Trainers", 10)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = if trainersFolder then { mobsFolder, trainersFolder } else { mobsFolder }

local lastSent = 0
local lastHint = 0

local function targetFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	if model and (model.Parent == mobsFolder or (trainersFolder and model.Parent == trainersFolder)) then
		return model
	end
	return nil
end

local function hint(text)
	if os.clock() - lastHint > 1.5 then
		lastHint = os.clock()
		Ui.Toast(text, Ui.Colors.Muted)
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
		hint(("Сначала пройди комнату %d"):format(room - 1))
		return
	end

	lastSent = now
	clickHit:FireServer(target)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- clicked a UI button, not the world
	end
	local camera = Workspace.CurrentCamera
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		tryHitAt(camera:ViewportPointToRay(mouse.X, mouse.Y))
	elseif input.UserInputType == Enum.UserInputType.Touch then
		tryHitAt(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	end
end)

-- Brief flash on the model that was hit.
local function flash(model, isCrit)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = if isCrit then Ui.Colors.Crit else Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	Ui.Tween(highlight, 0.2, { FillTransparency = 1 })
	task.delay(0.2, function()
		highlight:Destroy()
	end)
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
		Ui.WorldPopup(
			topOf(model),
			(if isCrit then "КРИТ! -" else "-") .. Format.Number(damage),
			if isCrit then Ui.Colors.Crit else Ui.Colors.Text,
			if isCrit then 36 else 26
		)
		flash(model, isCrit)
		Ui.PlaySound(Config.Sounds.Hit, if isCrit then 0.8 else 1 + (math.random() - 0.5) * 0.2, 0.4)
	elseif kind == "Train" then
		local model, aura, isCrit = ...
		if not model or not model.Parent then
			return
		end
		Ui.WorldPopup(
			topOf(model),
			(if isCrit then "КРИТ! +" else "+") .. Format.Number(aura) .. " ✨",
			if isCrit then Ui.Colors.Crit else Ui.Colors.Aura,
			if isCrit then 34 else 24
		)
		flash(model, isCrit)
		Ui.PlaySound(Config.Sounds.Click, if isCrit then 0.7 else 1 + (math.random() - 0.5) * 0.15, 0.5)
	elseif kind == "Kill" then
		local position, aura = ...
		Ui.WorldPopup(position + Vector3.new(0, 2, 0), "+" .. Format.Number(aura) .. " ✨", Ui.Colors.Aura, 32)
		Ui.PlaySound(Config.Sounds.Click, 1.4, 0.6)
	end
end)

return Combat
