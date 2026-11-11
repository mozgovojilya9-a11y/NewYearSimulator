--[[
	Prompts.luau
	Custom look for every ProximityPrompt (Style = Custom on the
	server): a round key button "E" and the action text in the game
	font. Also routes prompts that only open client windows
	(Action = OpenShop / OpenPets / RebirthAltar).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)
local Rebirth = require(script.Parent.ui.Windows.Rebirth)
local Reward = require(script.Parent.ui.Windows.Reward)
local Shop = require(script.Parent.ui.Windows.Shop)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Prompts = {}

local ACTIONS = {
	OpenShop = function()
		Shop.Open("Weapon")
	end,
	OpenPets = Shop.OpenPets,
	RebirthAltar = Rebirth.Open,
	Wheel = Reward.OpenWheel,
}

-- Stand prompts say Buy / Equip / Equipped depending on ownership.
local function standText(prompt: ProximityPrompt): string
	local category, id
	if prompt:GetAttribute("WeaponId") then
		category, id = "Weapon", prompt:GetAttribute("WeaponId")
	elseif prompt:GetAttribute("BackpackId") then
		category, id = "Backpack", prompt:GetAttribute("BackpackId")
	else
		return prompt.ActionText
	end
	local prompts = Config.HubLayout.Prompts
	if player:GetAttribute("Equipped" .. category) == id then
		return prompts.Equipped
	elseif Shop.OwnedSet(category)[id] then
		return prompts.Equip
	end
	return prompts.Buy
end

local function keyText(prompt: ProximityPrompt): string
	if prompt.KeyboardKeyCode ~= Enum.KeyCode.Unknown then
		return prompt.KeyboardKeyCode.Name
	end
	return "E"
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptUI"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(240, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40
	gui.Parent = playerGui

	local plate = Instance.new("Frame")
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromOffset(0, 56)
	plate.AutomaticSize = Enum.AutomaticSize.X
	plate.BackgroundColor3 = Style.Colors.PanelDark
	plate.BackgroundTransparency = 0.15
	plate.Parent = gui
	Style.Corner(plate, UDim.new(0, 16))
	Style.Stroke(plate, 2.5, Style.Colors.Cyan)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = plate
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = plate

	local key = Instance.new("TextLabel")
	key.Size = UDim2.fromOffset(40, 40)
	key.BackgroundColor3 = Style.Colors.Cyan
	key.Font = Style.Font
	key.TextSize = 22
	key.TextColor3 = Style.Colors.Outline
	key.Text = if inputType == Enum.ProximityPromptInputType.Touch then "👆" else keyText(prompt)
	key.LayoutOrder = 1
	key.Parent = plate
	Style.Corner(key, UDim.new(0.5, 0))
	Style.Stroke(key, 2.5)
	Style.Gradient(key, Style.Colors.Cyan)

	local text = Instance.new("TextLabel")
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromOffset(0, 40)
	text.BackgroundTransparency = 1
	text.Font = Style.Font
	text.TextSize = 20
	text.TextColor3 = Style.Colors.Text
	text.Text = standText(prompt) .. "  ·  " .. prompt.ObjectText
	text.LayoutOrder = 2
	text.Parent = plate
	Style.Stroke(text, 2)

	-- Hold progress ring: the key button fills while holding.
	local holdFill = Instance.new("Frame")
	holdFill.AnchorPoint = Vector2.new(0, 1)
	holdFill.Position = UDim2.fromScale(0, 1)
	holdFill.Size = UDim2.fromScale(1, 0)
	holdFill.BackgroundColor3 = Style.Colors.Gold
	holdFill.BackgroundTransparency = 0.3
	holdFill.ZIndex = 2
	holdFill.Parent = key
	Style.Corner(holdFill, UDim.new(0.5, 0))

	local pop = Instance.new("UIScale")
	pop.Scale = 0.6
	pop.Parent = plate
	Style.Tween(pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)

	local beginConnection = prompt.PromptButtonHoldBegan:Connect(function()
		Style.Tween(holdFill, prompt.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	end)
	local endConnection = prompt.PromptButtonHoldEnded:Connect(function()
		Style.Tween(holdFill, 0.1, { Size = UDim2.fromScale(1, 0) })
	end)

	prompt.PromptHidden:Wait()
	beginConnection:Disconnect()
	endConnection:Disconnect()
	Style.Tween(pop, 0.12, { Scale = 0.6 })
	task.wait(0.12)
	gui:Destroy()
end)

-- Hub interactions that only open client windows.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local action = ACTIONS[prompt:GetAttribute("Action")]
	if action then
		action()
	end
end)

return Prompts
