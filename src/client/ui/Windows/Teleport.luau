--[[
	Teleport.luau
	"Телепорт" window (HUD bar button, [T]): the halls of the hub
	(Config.HubLayout.Teleports) with a short line about each; a tap moves
	the player there (server TravelService "Hall:<id>", only in the hub).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Parent.Icons)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local player = Players.LocalPlayer
local travel = ReplicatedStorage:WaitForChild("Travel")

local Teleport = {}

local LINES = {
	Spawn = "Начало пути и Наставник",
	Gates = "Врата рангов E–S и Красные Врата",
	Forge = "Заточка, возвышение, разбор",
	Academy = "Выбор и смена класса",
	Supply = "Крутки за Кристаллы и портал в АФК-зону",
}

local list = Config.HubLayout.Teleports
local window = Window.new("Телепорт", C.Cyan, Vector2.new(460, 70 + #list * 62), "map")
local content = window.Content

for i, def in ipairs(list) do
	local color = (Config.HubLayout.Themes[def.Id] or {}).Accent or Config.Crystals.Color
	local row = Instance.new("TextButton")
	row.Name = def.Id
	row.Position = UDim2.fromOffset(0, (i - 1) * 62)
	row.Size = UDim2.new(1, 0, 0, 54)
	row.BackgroundTransparency = 1
	row.Text = ""
	row.AutoButtonColor = false
	row.ZIndex = 33
	row.Parent = content
	local shape = Style.Chamfer(row, { Fill = C.PanelDark, Transparency = 0.05, Border = C.Line, Cut = 8, Thickness = 1.5 })
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, -12)
	stripe.Position = UDim2.fromOffset(6, 6)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 34
	stripe.Parent = row
	local icon = Icons.Make(row, def.Icon, 28, color, 34)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 20, 0.5, 0)
	Style.Label(row, def.Name, 18, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(60, 6), Size = UDim2.new(1, -170, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	Style.Label(row, LINES[def.Id] or "", 13, C.Muted, { Position = UDim2.fromOffset(60, 29), Size = UDim2.new(1, -170, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	local go = Style.Label(row, "ПЕРЕЙТИ", 14, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(90, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
	local _ = go
	row.MouseEnter:Connect(function()
		shape.SetBorder(color)
	end)
	row.MouseLeave:Connect(function()
		shape.SetBorder(C.Line)
	end)
	row.Activated:Connect(function()
		if player:GetAttribute("Zone") == "Dungeon" then
			Popups.Toast("Телепорт работает только в хабе", "bad")
			return
		end
		window.Close()
		Style.PlaySound("Portal", 1.3, 0.5)
		Popups.Flash(color)
		task.spawn(travel.InvokeServer, travel, "Hall:" .. def.Id)
	end)
end

function Teleport.Open()
	window.Open()
end

Teleport.Window = window
return Teleport
