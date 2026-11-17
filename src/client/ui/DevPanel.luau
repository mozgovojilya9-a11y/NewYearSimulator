--[[
	DevPanel.luau
	Testing panel, ONLY in Studio (RunService:IsStudio(); the server
	creates the "Dev" remote only there). A small "DEV" button on the
	right edge opens: reset progress, +1 / +5 levels, +100 credits,
	10 of every material, and a random item of a chosen rarity.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Popups = require(script.Parent.Popups)
local Style = require(script.Parent.Style)

local DevPanel = {}

if not RunService:IsStudio() then
	return DevPanel
end

local remote = ReplicatedStorage:WaitForChild("Dev", 15)
if not remote then
	return DevPanel
end

local toggle = Style.Button(Style.Gui, {
	Name = "DevToggle",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, -150),
	Size = UDim2.fromOffset(64, 34),
	Color = Style.Colors.Orange,
	Text = "DEV",
	TextSize = 18,
	ZIndex = 20,
	Shadow = false,
})

local panel = Style.Plate(Style.Gui, {
	Name = "DevPanel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0.5, -126),
	Size = UDim2.fromOffset(250, 330),
	ZIndex = 20,
})
panel.Visible = false
Style.Stroke(panel, 2.5, Style.Colors.Orange)
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = panel
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = panel

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

local busy = false
local function call(action, arg)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = remote:InvokeServer(action, arg)
		busy = false
		Popups.Toast("DEV: " .. tostring(message or ""), if ok then "good" else "bad")
	end)
end

local order = 0
local function button(text, color, onClick)
	order += 1
	local b = Style.Button(panel, { Size = UDim2.fromOffset(226, 34), Color = color, Text = text, TextSize = 16, ZIndex = 21, LayoutOrder = order, Shadow = false })
	b.Activated:Connect(onClick)
	return b
end

local confirmReset = false
local resetButton
resetButton = button("Сбросить прогресс", Style.Colors.Red, function()
	if not confirmReset then
		confirmReset = true
		resetButton.Text = "Точно? Нажми ещё раз"
		task.delay(3, function()
			confirmReset = false
			resetButton.Text = "Сбросить прогресс"
		end)
		return
	end
	confirmReset = false
	resetButton.Text = "Сбросить прогресс"
	call("Reset")
end)
button("+1 уровень", Style.Colors.Blue, function()
	call("Level", 1)
end)
button("+5 уровней", Style.Colors.Blue, function()
	call("Level", 5)
end)
button(("+%d кредитов"):format(Config.Dev.Credits), Style.Colors.Cyan, function()
	call("Credits")
end)
button(("+%d нано-ядер"):format(Config.Dev.Cores), Style.Colors.Green, function()
	call("Cores")
end)
button("Предмет на землю", Style.Colors.Card, function()
	call("Drop", "Item")
end)
button("Сундук босса на землю", Style.Colors.Card, function()
	call("Drop", "Chest")
end)
button("Случайный артефакт", Style.Colors.Card, function()
	call("Artifact")
end)
button("Открыть ранги Врат", Style.Colors.Card, function()
	call("Unlock")
end)
button("Красные Врата сейчас", Style.Colors.Red, function()
	call("Red")
end)

order += 1
Style.Label(panel, "Случайный предмет:", 15, Style.Colors.Gold, { Size = UDim2.fromOffset(226, 20), LayoutOrder = order, ZIndex = 21 })
order += 1
local grid = Instance.new("Frame")
grid.Size = UDim2.fromOffset(226, 66)
grid.BackgroundTransparency = 1
grid.LayoutOrder = order
grid.ZIndex = 21
grid.Parent = panel
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(52, 30)
gridLayout.CellPadding = UDim2.fromOffset(6, 6)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid
for i, rarity in ipairs(Config.Rarities) do
	local b = Style.Button(grid, { Color = rarity.Color, Text = rarity.Name, TextSize = 12, ZIndex = 22, LayoutOrder = i, Shadow = false })
	b.TextScaled = true -- long Russian names shrink to fit
	b.Activated:Connect(function()
		call("Item", rarity.Id)
	end)
end

return DevPanel
