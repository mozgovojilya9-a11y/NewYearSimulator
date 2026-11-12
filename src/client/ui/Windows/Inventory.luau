--[[
	Inventory.luau
	"Инвентарь": every material the player owns as stacks, sorted by
	rarity (highest first). Filters: all / one biome. Cards show the
	rotating mini-model, name, rarity and count; the frame has the
	rarity color.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Preview = require(script.Parent.Parent.Preview)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer

local Inventory = {}

local window = Window.new("Инвентарь", Style.Colors.Orange, Vector2.new(640, 470))
local content = window.Content

local tabs, setTab = Window.Tabs(content, { { Id = 0, Text = "Все" }, { Id = 1, Text = "Катакомбы" }, { Id = 2, Text = "Лёд" }, { Id = 3, Text = "Лава" }, { Id = 4, Text = "Бездна" } }, Style.Colors.Orange, 104)

local total = Style.Label(content, "", 18, Style.Colors.Muted, { Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), ZIndex = 33 })

local holder = Instance.new("Frame")
holder.Position = UDim2.fromOffset(0, 48)
holder.Size = UDim2.new(1, 0, 1, -78)
holder.BackgroundTransparency = 1
holder.ZIndex = 32
holder.Parent = content
local grid = Window.Grid(holder, UDim2.fromOffset(142, 150))

local empty = Style.Label(holder, "Пока пусто. Материалы падают с мобов в подземелье —\nподбирай их, удерживая E.", 20, Style.Colors.Muted, { Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 60), TextWrapped = true, ZIndex = 33 })

local cards = {} -- [materialId] = { card, count }
local filter = 0

local function makeCard(material)
	local rarity = Config.Rarity[material.Rarity]
	local card = Style.Card(grid, rarity.Color, rarity.Rainbow)
	card.Name = material.Id
	Preview.Create(card, "Material", material, UDim2.new(1, -16, 0, 76), UDim2.fromOffset(8, 8))
	Style.Label(card, material.Name, 15, Style.Colors.Text, { Position = UDim2.fromOffset(4, 88), Size = UDim2.new(1, -8, 0, 20), TextScaled = true, ZIndex = 35 })
	local rarityLabel = Style.Label(card, rarity.Name, 13, rarity.Color, { Position = UDim2.fromOffset(4, 108), Size = UDim2.new(1, -8, 0, 16), ZIndex = 35 })
	if rarity.Rainbow then
		Style.Rainbow(rarityLabel)
	end
	local count = Style.Label(card, "x0", 20, Style.Colors.Gold, { Position = UDim2.fromOffset(4, 124), Size = UDim2.new(1, -8, 0, 22), ZIndex = 35 })
	cards[material.Id] = { card = card, count = count }
	return cards[material.Id]
end

local function refresh()
	local materials = PlayerData.Materials()
	local sum, kinds = 0, 0
	for _, material in ipairs(Config.Materials) do
		local owned = materials[material.Id] or 0
		local entry = cards[material.Id]
		local show = owned > 0 and (filter == 0 or material.Biome == filter)
		if show and not entry then
			entry = makeCard(material)
		end
		if entry then
			entry.card.Visible = show
			entry.count.Text = "x" .. Format.Number(owned)
			-- highest rarity first, then the config order
			entry.card.LayoutOrder = (10 - Config.Rarity[material.Rarity].Index) * 100 + material.Order
		end
		if owned > 0 then
			sum += owned
			kinds += 1
		end
	end
	empty.Visible = sum == 0
	total.Text = ("Всего предметов: %s   •   видов: %d / %d"):format(Format.Number(sum), kinds, #Config.Materials)
end

tabs.Changed = function(id)
	filter = id
	refresh()
end
setTab(0)

player:GetAttributeChangedSignal("Materials"):Connect(function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = refresh

Inventory.Window = window
Inventory.Open = window.Open
return Inventory
