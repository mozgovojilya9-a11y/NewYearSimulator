--[[
	Combat.luau
	Day 3: click (or tap) a mob in the world to hit it. The client only
	reports *which* mob was clicked; the server checks range/cooldown,
	rolls damage and answers with "Hit" / "Kill" events which we turn
	into popups, flashes and sounds here.
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

local mobHit = ReplicatedStorage:WaitForChild("MobHit")
local mobsFolder = Workspace:WaitForChild("AuraZone"):WaitForChild("Mobs")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { mobsFolder }

local lastSent = 0

local function mobFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	if model and model.Parent == mobsFolder then
		return model
	end
	return nil
end

local function tryHitAt(ray: Ray)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local model = result and mobFromPart(result.Instance)
	if not model then
		return
	end

	local now = os.clock()
	if now - lastSent < Config.Click.Cooldown then
		return
	end
	lastSent = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - model:GetPivot().Position).Magnitude > Config.Zone.HitDistance then
		Ui.Toast("Подойди ближе к мобу!", Ui.Colors.Muted)
		return
	end

	mobHit:FireServer(model)
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

-- Brief white flash on the mob that was hit.
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

mobHit.OnClientEvent:Connect(function(kind, ...)
	if kind == "Hit" then
		local model, damage, isCrit = ...
		if not model or not model.Parent then
			return
		end
		local top = model:GetPivot().Position + Vector3.new(0, model:GetExtentsSize().Y / 2, 0)
		Ui.WorldPopup(
			top,
			(if isCrit then "КРИТ! -" else "-") .. Format.Number(damage),
			if isCrit then Ui.Colors.Crit else Ui.Colors.Text,
			if isCrit then 36 else 26
		)
		flash(model, isCrit)
		Ui.PlaySound(Config.Sounds.Hit, if isCrit then 0.8 else 1 + (math.random() - 0.5) * 0.2, 0.4)
	elseif kind == "Kill" then
		local position, aura, gems = ...
		Ui.WorldPopup(position + Vector3.new(0, 2, 0), "+" .. Format.Number(aura) .. " ✨", Ui.Colors.Aura, 32)
		if gems > 0 then
			task.delay(0.15, function()
				Ui.WorldPopup(position + Vector3.new(0, 4, 0), "+" .. gems .. " 💎", Ui.Colors.Gems, 32)
			end)
		end
		Ui.PlaySound(Config.Sounds.Click, 1.4, 0.6)
	end
end)

return Combat
