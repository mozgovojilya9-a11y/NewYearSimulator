--[[
	Equipment.luau
	"Снаряжение": four slots (weapon + helmet / chest / legs) on the
	left; pick a slot to see everything owned for it on the right and
	equip it with one click (armor can also be taken off). The bottom bar
	shows the resulting stats: damage per click, health, defense and the
	set bonus (all three pieces of one set).
	The server does the equipping (ShopRequest) and publishes the result
	as player attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local Preview = require(script.Parent.Parent.Preview)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local shopRequest = ReplicatedStorage:WaitForChild("ShopRequest")

local Equipment = {}

local window = Window.new("Снаряжение", Style.Colors.Green, Vector2.new(740, 500))
local content = window.Content

-- Slots: the weapon + the three armor slots.
local SLOTS = { { Id = "Weapon", Name = "Оружие", Category = "Weapon", Attribute = "EquippedWeapon", Owned = "OwnedWeapon" } }
for _, slot in ipairs(Config.ArmorSlots) do
	table.insert(SLOTS, { Id = slot, Name = Config.ArmorSlotNames[slot], Category = "Armor", Attribute = "Equipped" .. slot, Owned = "OwnedArmor" })
end

local busy = false
local function request(action, category, id)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = shopRequest:InvokeServer(action, category, id)
		busy = false
		Popups.Toast(message or "", if ok then "good" else "bad")
		if ok then
			Style.PlaySound(Config.Sounds.Unsheath, 1.1, 0.5)
		end
	end)
end

---------------------------------------------------------------------
-- Left: slots
---------------------------------------------------------------------

local LEFT = 236
local STATS = 70
local slotCards = {}
local selectedSlot = SLOTS[1]
local refresh -- defined below

for index, slot in ipairs(SLOTS) do
	local card = Instance.new("TextButton")
	card.Name = slot.Id
	card.Position = UDim2.fromOffset(0, (index - 1) * 90)
	card.Size = UDim2.fromOffset(LEFT, 82)
	card.BackgroundColor3 = Style.Colors.Card
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 33
	card.Parent = content
	Style.Corner(card, UDim.new(0, 12))
	local stroke = Style.Stroke(card, 3, Style.Colors.Outline)
	local icon = Instance.new("Frame")
	icon.Position = UDim2.fromOffset(8, 8)
	icon.Size = UDim2.fromOffset(66, 66)
	icon.BackgroundColor3 = Style.Colors.CardDark
	icon.ZIndex = 34
	icon.Parent = card
	Style.Corner(icon, UDim.new(0, 10))
	Style.Label(card, slot.Name, 15, Style.Colors.Muted, { Position = UDim2.fromOffset(84, 8), Size = UDim2.new(1, -92, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local name = Style.Label(card, "", 18, Style.Colors.Text, { Position = UDim2.fromOffset(84, 28), Size = UDim2.new(1, -92, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 35 })
	local stat = Style.Label(card, "", 15, Style.Colors.Gold, { Position = UDim2.fromOffset(84, 54), Size = UDim2.new(1, -92, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 35 })
	slotCards[slot.Id] = { card = card, stroke = stroke, icon = icon, name = name, stat = stat, shown = nil }
	card.Activated:Connect(function()
		selectedSlot = slot
		refresh()
	end)
end

---------------------------------------------------------------------
-- Right: owned items for the selected slot
---------------------------------------------------------------------

local right = Instance.new("Frame")
right.Position = UDim2.fromOffset(LEFT + 12, 0)
right.Size = UDim2.new(1, -(LEFT + 12), 1, -(STATS + 8))
right.BackgroundTransparency = 1
right.ZIndex = 32
right.Parent = content
local header = Style.Label(right, "", 20, Style.Colors.Gold, { Size = UDim2.new(1, -150, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local takeOff = Style.Button(right, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(140, 32), Color = Style.Colors.Red, Text = "Снять", TextSize = 17, ZIndex = 34, Shadow = false })
takeOff.Activated:Connect(function()
	if selectedSlot.Category == "Armor" then
		request("Unequip", "Armor", selectedSlot.Id)
	end
end)
local gridHolder = Instance.new("Frame")
gridHolder.Position = UDim2.fromOffset(0, 38)
gridHolder.Size = UDim2.new(1, 0, 1, -38)
gridHolder.BackgroundTransparency = 1
gridHolder.ZIndex = 32
gridHolder.Parent = right
local grid = Window.Grid(gridHolder, UDim2.fromOffset(146, 162))
local empty = Style.Label(gridHolder, "Здесь пока пусто.\nВыкуй снаряжение в Кузнице!", 20, Style.Colors.Muted, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 70), TextWrapped = true, ZIndex = 33 })

local itemCards = {} -- [category .. id] = { card, stroke, state, item }

local function describe(category, item): string
	if category == "Weapon" then
		return "Урон " .. Format.Number(item.Damage)
	end
	return ("+%d HP  •  %d%%"):format(item.Health, math.floor(item.Defense * 100 + 0.5))
end

local function itemCard(category, item)
	local key = category .. item.Id
	if itemCards[key] then
		return itemCards[key]
	end
	local rarity = Config.Rarity[item.Rarity] or Config.Rarity.Common
	local card, stroke = Style.Card(grid, rarity.Color, rarity.Rainbow)
	card.Name = item.Id
	Preview.Create(card, category, item, UDim2.new(1, -16, 0, 78), UDim2.fromOffset(8, 8))
	Style.Label(card, item.Name, 15, rarity.Color, { Position = UDim2.fromOffset(4, 88), Size = UDim2.new(1, -8, 0, 20), TextScaled = true, ZIndex = 35 })
	Style.Label(card, describe(category, item), 14, Style.Colors.Text, { Position = UDim2.fromOffset(4, 108), Size = UDim2.new(1, -8, 0, 18), TextScaled = true, ZIndex = 35 })
	local button, setColor = Style.Button(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -16, 0, 28), Color = Style.Colors.Blue, Text = "Надеть", TextSize = 15, ZIndex = 36, Shadow = false })
	button.Activated:Connect(function()
		request("Equip", category, item.Id)
	end)
	itemCards[key] = { card = card, stroke = stroke, button = button, setColor = setColor, item = item, category = category }
	return itemCards[key]
end

---------------------------------------------------------------------
-- Bottom: total stats
---------------------------------------------------------------------

local stats = Style.Plate(content, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, STATS), Color = Style.Colors.CardDark, ZIndex = 33 })
local statsLine = Style.Label(stats, "", 20, Style.Colors.Text, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 34 })
local setLine = Style.Label(stats, "", 17, Style.Colors.Gold, { Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 34 })

function refresh()
	-- Slots
	for _, slot in ipairs(SLOTS) do
		local ui = slotCards[slot.Id]
		local equippedId = player:GetAttribute(slot.Attribute) or ""
		local item = Config.ItemById[slot.Category][equippedId]
		ui.stroke.Color = if slot == selectedSlot then Style.Colors.Green else Style.Colors.Outline
		ui.stroke.Thickness = if slot == selectedSlot then 4 else 3
		if ui.shown ~= equippedId then
			ui.shown = equippedId
			ui.icon:ClearAllChildren()
			Style.Corner(ui.icon, UDim.new(0, 10))
			if item then
				Preview.Create(ui.icon, slot.Category, item, UDim2.fromScale(1, 1), UDim2.new())
			end
		end
		if item then
			local rarity = Config.Rarity[item.Rarity] or Config.Rarity.Common
			ui.name.Text = item.Name
			ui.name.TextColor3 = rarity.Color
			ui.stat.Text = describe(slot.Category, item)
		else
			ui.name.Text = "Пусто"
			ui.name.TextColor3 = Style.Colors.Muted
			ui.stat.Text = ""
		end
	end

	-- Items of the selected slot (strongest first).
	local slot = selectedSlot
	local owned = PlayerData.Set(slot.Owned)
	local equippedId = player:GetAttribute(slot.Attribute) or ""
	header.Text = "Выбери: " .. slot.Name
	takeOff.Visible = slot.Category == "Armor" and equippedId ~= ""
	local shown = 0
	for _, entry in pairs(itemCards) do
		entry.card.Visible = false
	end
	for _, item in ipairs(Config.Shop[slot.Category] and Config.Shop[slot.Category].Items or Config.Armor) do
		if owned[item.Id] and (slot.Category == "Weapon" or item.Slot == slot.Id) then
			local entry = itemCard(slot.Category, item)
			entry.card.Visible = true
			entry.card.LayoutOrder = -math.floor(if slot.Category == "Weapon" then item.Damage else item.Health)
			if item.Id == equippedId then
				entry.button.Text = "Надето ✓"
				entry.setColor(Color3.fromRGB(110, 110, 130))
			else
				entry.button.Text = "Надеть"
				entry.setColor(Style.Colors.Blue)
			end
			shown += 1
		end
	end
	empty.Visible = shown == 0

	-- Totals
	local defense = math.floor((player:GetAttribute("Defense") or 0) * 100 + 0.5)
	statsLine.Text = ("⚔ Урон за удар: %s     ❤ Здоровье: %s     🛡 Защита: %d%%"):format(Format.Number(player:GetAttribute("ClickPower") or 1), Format.Number(player:GetAttribute("MaxHealth") or Config.Player.Health), defense)
	local activeSet = Config.ArmorSets[player:GetAttribute("ArmorSet") or ""]
	if activeSet then
		setLine.Text = ("Бонус сета «%s» (3/3): +%d%% урона"):format(activeSet.Name, math.floor(activeSet.Bonus * 100 + 0.5))
		setLine.TextColor3 = Style.Colors.Gold
	else
		-- how close the best partial set is
		local counts, best, bestCount = {}, nil, 0
		for _, armorSlot in ipairs(Config.ArmorSlots) do
			local piece = Config.ItemById.Armor[player:GetAttribute("Equipped" .. armorSlot) or ""]
			if piece then
				counts[piece.Set] = (counts[piece.Set] or 0) + 1
				if counts[piece.Set] > bestCount then
					best, bestCount = piece.Set, counts[piece.Set]
				end
			end
		end
		if best then
			local set = Config.ArmorSets[best]
			setLine.Text = ("%s: %d/3 — собери все части для +%d%% урона"):format(set.Name, bestCount, math.floor(set.Bonus * 100 + 0.5))
		else
			setLine.Text = "Бонус сета: надень 3 части одного сета брони"
		end
		setLine.TextColor3 = Style.Colors.Muted
	end
end

PlayerData.Changed({ "OwnedWeapon", "OwnedArmor", "EquippedWeapon", "EquippedHelmet", "EquippedChest", "EquippedLegs", "ArmorSet", "MaxHealth", "Defense", "ClickPower" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = refresh

Equipment.Window = window
Equipment.Open = window.Open
return Equipment
