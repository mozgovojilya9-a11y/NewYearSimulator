--[[
	Gates.luau
	"Врата" window (the gold "Играть" button in the hub): the game modes
	from Config.Ui.Modes. Open modes start a run (Travel remote), locked
	ones show "Скоро".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Parent.Icons)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local travel = ReplicatedStorage:WaitForChild("Travel")
local C = Style.Colors
local T = Config.Ui.Texts

local Gates = {}

local window = Window.new("Врата", C.Gold, Vector2.new(560, 360), "gate")
local list = Window.List(window.Content)

local busy = false
function Gates.Go(destination: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = travel:InvokeServer(destination)
		busy = false
		if not ok then
			Popups.Toast(message or "", "bad")
		else
			Window.CloseAll()
		end
	end)
end

for order, mode in ipairs(Config.Ui.Modes) do
	local row = Style.Panel(list, {
		Size = UDim2.new(1, -8, 0, 84),
		LayoutOrder = order,
		ZIndex = 33,
		Fill = C.Card,
		Transparency = 0.1,
		Border = if mode.Locked then C.Line else C.GoldDim,
		Cut = 8,
	})
	local iconFrame = Style.Panel(row, { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(60, 60), ZIndex = 34, Fill = C.PanelDark, Transparency = 0, Border = C.Line, Cut = 6 })
	local icon = Icons.Make(iconFrame, mode.Icon, 38, if mode.Locked then C.Muted else C.Gold, 35)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	Style.Label(row, Style.Upper(mode.Name), 19, if mode.Locked then C.Muted else C.Text, {
		Font = Style.FontTitle,
		Position = UDim2.fromOffset(86, 14),
		Size = UDim2.new(1, -240, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 35,
	})
	Style.Label(row, mode.Text, 14, C.Muted, {
		Position = UDim2.fromOffset(86, 42),
		Size = UDim2.new(1, -240, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 35,
	})
	local button = Style.Button(row, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(130, 42),
		Color = if mode.Locked then C.Card else C.Gold,
		Text = if mode.Locked then Style.Upper(T.Locked) else Style.Upper(T.Enter),
		TextSize = 17,
		ZIndex = 36,
		Icon = if mode.Locked then "lock" else "play",
	})
	button.Activated:Connect(function()
		if mode.Locked then
			Popups.Toast(mode.Name .. ": скоро", "gold")
		elseif mode.Id == "Dungeon" then
			Gates.Go("Dungeon")
		end
	end)
end

Gates.Window = window
Gates.Open = function()
	if player:GetAttribute("Zone") == "Dungeon" then
		return
	end
	window.Open()
end

return Gates
