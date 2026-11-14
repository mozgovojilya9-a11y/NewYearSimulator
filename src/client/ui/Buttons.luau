--[[
	Buttons.luau
	Left 2-column menu grid (with "!" badges), top-right round buttons
	(settings, sound) and the Back button shown in the dungeon (key B).
	The top-left corner (Config.Hud.TopLeftReserved) is left empty for
	the Roblox buttons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Popups = require(script.Parent.Popups)
local Style = require(script.Parent.Style)
local Equipment = require(script.Parent.Windows.Equipment)
local Forge = require(script.Parent.Windows.Forge)
local Inventory = require(script.Parent.Windows.Inventory)
local Rebirth = require(script.Parent.Windows.Rebirth)
local Reward = require(script.Parent.Windows.Reward)
local Settings = require(script.Parent.Windows.Settings)
local Pets = require(script.Parent.Windows.Pets)

local player = Players.LocalPlayer
local travel = ReplicatedStorage:WaitForChild("Travel")
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local Buttons = {}

---------------------------------------------------------------------
-- Travel
---------------------------------------------------------------------

local travelBusy = false
local function go(destination)
	if travelBusy then
		return
	end
	travelBusy = true
	task.spawn(function()
		local ok, message = travel:InvokeServer(destination)
		travelBusy = false
		if not ok then
			Popups.Toast(message or "", "bad")
		end
	end)
end
Buttons.Go = go

---------------------------------------------------------------------
-- Left grid
---------------------------------------------------------------------

local BUTTON = 78
local GAP = 8
local ROWS = math.ceil(#Config.Hud.MenuButtons / 2)
local grid = Instance.new("Frame")
grid.Name = "Menu"
grid.Position = UDim2.fromOffset(16, Config.Hud.TopLeftReserved.Y + 20)
grid.Size = UDim2.fromOffset(BUTTON * 2 + GAP, BUTTON * ROWS + GAP * (ROWS - 1))
grid.BackgroundTransparency = 1
grid.Parent = Style.Gui
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(BUTTON, BUTTON)
gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local badges = {}

local actions = {
	Forge = Forge.Open,
	Inventory = Inventory.Open,
	Equipment = Equipment.Open,
	Pets = Pets.Open,
	Rebirth = Rebirth.Open,
	Reward = Reward.Open,
	Travel = function()
		go(if player:GetAttribute("Zone") == "Dungeon" then "Hub" else "Dungeon")
	end,
}

for order, def in ipairs(Config.Hud.MenuButtons) do
	local button = Style.Button(grid, { Name = def.Id, Color = def.Color, TextSize = 1, ZIndex = 2, LayoutOrder = order, Shadow = false })
	Style.Label(button, def.Icon, 30, Style.Colors.Text, { Size = UDim2.new(1, 0, 0.6, 0), ZIndex = 3 }):FindFirstChildOfClass("UIStroke").Transparency = 1
	Style.Label(button, def.Label, 13, Style.Colors.Text, { Position = UDim2.fromScale(0, 0.62), Size = UDim2.new(1, 0, 0.3, 0), TextScaled = true, ZIndex = 3 })

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 6, 0, -6)
	badge.Size = UDim2.fromOffset(26, 26)
	badge.BackgroundColor3 = Style.Colors.Red
	badge.Font = Style.Font
	badge.TextSize = 18
	badge.TextColor3 = Style.Colors.Text
	badge.Text = "!"
	badge.ZIndex = 4
	badge.Visible = false
	badge.Parent = button
	Style.Corner(badge, UDim.new(0.5, 0))
	Style.Stroke(badge, 2)
	badges[def.Id] = badge

	button.Activated:Connect(actions[def.Id] or function() end)
end

local function setBadge(id, visible)
	if badges[id] then
		badges[id].Visible = visible == true
	end
end
local function refreshBadges()
	setBadge("Pets", Pets.CanHatch() and (player:GetAttribute("EquippedPets") or "") == "")
	setBadge("Rebirth", Rebirth.CanRebirth())
	setBadge("Reward", player:GetAttribute("RewardReady") == true)
end
aura.Changed:Connect(refreshBadges)
for _, attribute in ipairs({ "EquippedPets", "RoomReached", "RewardReady" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshBadges)
end
refreshBadges()

---------------------------------------------------------------------
-- Top-right round buttons
---------------------------------------------------------------------

local topRight = Instance.new("Frame")
topRight.Name = "TopRight"
topRight.AnchorPoint = Vector2.new(1, 0)
topRight.Position = UDim2.new(1, -16, 0, 12)
topRight.Size = UDim2.fromOffset(110, 48)
topRight.BackgroundTransparency = 1
topRight.Parent = Style.Gui
local trLayout = Instance.new("UIListLayout")
trLayout.FillDirection = Enum.FillDirection.Horizontal
trLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
trLayout.Padding = UDim.new(0, 8)
trLayout.SortOrder = Enum.SortOrder.LayoutOrder
trLayout.Parent = topRight

local settingsButton = Style.Button(topRight, { Size = UDim2.fromOffset(48, 48), Color = Style.Colors.Blue, Text = "⚙", TextSize = 26, Radius = UDim.new(0.5, 0), LayoutOrder = 1, Shadow = false })
settingsButton.Activated:Connect(Settings.Open)
local soundButton, setSoundColor = Style.Button(topRight, { Size = UDim2.fromOffset(48, 48), Color = Style.Colors.Green, Text = "🔊", TextSize = 24, Radius = UDim.new(0.5, 0), LayoutOrder = 2, Shadow = false })
soundButton.Activated:Connect(function()
	local on = Settings.ToggleSound()
	soundButton.Text = if on then "🔊" else "🔇"
	setSoundColor(if on then Style.Colors.Green else Style.Colors.Red)
end)

---------------------------------------------------------------------
-- Back button (dungeon only, key B)
---------------------------------------------------------------------

local back = Style.Button(Style.Gui, {
	Name = "Back",
	Position = UDim2.fromOffset(16, Config.Hud.TopLeftReserved.Y + 20 + BUTTON * ROWS + GAP * (ROWS - 1) + 12),
	Size = UDim2.fromOffset(BUTTON * 2 + GAP, 44),
	Color = Style.Colors.Red,
	Text = "← Назад  [B]",
	TextSize = 20,
})
back.Visible = false
back.Activated:Connect(function()
	go("Hub") -- ends the current run
end)

local function refreshZone()
	back.Visible = player:GetAttribute("Zone") == "Dungeon"
end
player:GetAttributeChangedSignal("Zone"):Connect(refreshZone)
refreshZone()

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Config.Hud.BackKey and player:GetAttribute("Zone") == "Dungeon" then
		go("Hub")
	end
end)

return Buttons
