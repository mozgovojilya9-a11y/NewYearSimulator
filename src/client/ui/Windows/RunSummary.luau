--[[
	RunSummary.luau
	Window shown when a dungeon run ends (death, Back, or room 20):
	how far you got, Aura earned this run, your record.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local RunSummary = {}

local Texts = Config.DungeonLayout.Texts
local TITLES = { Died = Texts.RunDied, Left = Texts.RunLeft, Won = Texts.RunWon }
local COLORS = { Died = Style.Colors.Red, Left = Style.Colors.Blue, Won = Style.Colors.Gold }

local window = Window.new("Итоги забега", Style.Colors.Purple, Vector2.new(460, 340))
local content = window.Content
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = content

local title = Style.Label(content, "", 30, Style.Colors.Red, { LayoutOrder = 1, ZIndex = 33 })
local function stat(order, icon)
	local plate = Style.Plate(content, { Size = UDim2.new(1, -20, 0, 48), Transparency = 0.1, ZIndex = 33 })
	plate.LayoutOrder = order
	Style.Label(plate, icon, 26, Style.Colors.Text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(40, 48), ZIndex = 34 })
	return Style.Label(plate, "", 22, Style.Colors.Text, { Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -64, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
end
local roomLabel = stat(2, "🏰")
local auraLabel = stat(3, "✨")
local recordLabel = stat(4, "🏆")

local again = Style.Button(content, { Size = UDim2.fromOffset(260, 54), Color = Style.Colors.Green, Text = "В подземелье!", TextSize = 22, ZIndex = 34, LayoutOrder = 5, Shadow = false })
local travel = ReplicatedStorage:WaitForChild("Travel")
again.Activated:Connect(function()
	window.Close()
	task.spawn(function()
		local ok, message = travel:InvokeServer("Dungeon")
		if not ok then
			Popups.Toast(message or "", "bad")
		end
	end)
end)

ReplicatedStorage:WaitForChild("RunEnded").OnClientEvent:Connect(function(reason, room, aura, record, isNewRecord)
	title.Text = TITLES[reason] or Texts.RunLeft
	title.TextColor3 = COLORS[reason] or Style.Colors.Text
	roomLabel.Text = ("Дошёл до этапа %d"):format(room)
	auraLabel.Text = ("Заработано %s Ауры"):format(Format.Number(aura))
	recordLabel.Text = ("Рекорд: этап %d%s"):format(record, if isNewRecord then "  — НОВЫЙ!" else "")
	recordLabel.TextColor3 = if isNewRecord then Style.Colors.Gold else Style.Colors.Text
	task.delay(0.6, window.Open)
end)

RunSummary.Window = window
return RunSummary
