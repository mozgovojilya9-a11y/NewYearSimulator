--[[
	Shop.luau
	Shop window (tabs: Оружие / Рюкзаки) and Pets window, built from
	Config.Shop. Cards are colored by rarity (mythic = animated rainbow).
	Buttons only ASK the server (ShopRequest); what is owned/equipped
	comes back through Player attributes set by PlayerState.Sync.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.Parent.Popups)
local Preview = require(script.Parent.Parent.Preview)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local shopRequest = ReplicatedStorage:WaitForChild("ShopRequest")
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local Shop = {}

function Shop.OwnedSet(category)
	local set = {}
	local text = player:GetAttribute("Owned" .. category) or ""
	for id in string.gmatch(text, "[^,]+") do
		set[id] = true
	end
	return set
end

local busy = false
function Shop.Request(action, category, id)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = shopRequest:InvokeServer(action, category, id)
		busy = false
		Popups.Toast(message or "", if ok then "good" else "bad")
		if ok then
			Style.PlaySound(Config.Sounds.Buy, if action == "Buy" then 1.6 else 1.2, 0.6)
			if action == "Buy" and category == "Pet" then
				local pet = Config.ItemById.Pet[id]
				local color, rainbow = Style.RarityColor(pet and pet.Rarity)
				Popups.Hatch(pet and pet.Name or "", color, rainbow)
			end
		end
	end)
end

-- Is there anything in a category the player can afford right now?
function Shop.HasAffordable(category): boolean
	local owned = Shop.OwnedSet(category)
	for _, item in ipairs(Config.Shop[category].Items) do
		if not owned[item.Id] and not item.Unique and aura.Value >= item.Cost then
			return true
		end
	end
	return false
end

local function makeCard(parent, category, item, order)
	local shop = Config.Shop[category]
	local rarityColor, rainbow = Style.RarityColor(item.Rarity)

	local card = Instance.new("Frame")
	card.Name = item.Id
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -8, 0, 72)
	card.BackgroundColor3 = Style.Lighter(rarityColor, 0.82)
	card.ZIndex = 33
	card.Parent = parent
	Style.Corner(card, UDim.new(0, 14))
	local stroke = Style.Stroke(card, 3, rarityColor)
	if rainbow then
		Style.Rainbow(stroke)
	end

	-- Rotating model preview; pets fall back to a color swatch.
	if not Preview.Create(card, category, item, UDim2.fromOffset(52, 52), UDim2.fromOffset(10, 10)) then
		local swatch = Instance.new("Frame")
		swatch.Position = UDim2.fromOffset(10, 10)
		swatch.Size = UDim2.fromOffset(52, 52)
		swatch.BackgroundColor3 = item.Color
		swatch.ZIndex = 34
		swatch.Parent = card
		Style.Corner(swatch, UDim.new(0, 12))
		Style.Stroke(swatch, 2.5)
		Style.Gradient(swatch, item.Color)
	end

	Style.Label(card, item.Name, 20, Style.Colors.Outline, {
		Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -230, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 34,
	}):FindFirstChildOfClass("UIStroke").Transparency = 1
	local rarityLabel = Style.Label(card, (Config.Rarity[item.Rarity] or Config.Rarity.Common).Name, 14, rarityColor, {
		Position = UDim2.fromOffset(72, 32), Size = UDim2.new(1, -230, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34,
	})
	rarityLabel:FindFirstChildOfClass("UIStroke").Thickness = 1
	if rainbow then
		Style.Rainbow(rarityLabel)
	end
	Style.Label(card, shop.Describe(item), 14, Style.Colors.Outline, {
		Position = UDim2.fromOffset(72, 50), Size = UDim2.new(1, -230, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34,
	}):FindFirstChildOfClass("UIStroke").Transparency = 1

	local button, setColor = Style.Button(card, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(140, 46),
		Color = Style.Colors.Green,
		TextSize = 18,
		ZIndex = 35,
		Shadow = false,
	})

	local state = "buy"
	button.Activated:Connect(function()
		if state == "buy" then
			Shop.Request("Buy", category, item.Id)
		elseif state == "equip" then
			Shop.Request("Equip", category, item.Id)
		elseif state == "stand" then
			Popups.Toast("Это оружие продаётся на стенде в хабе", "gold")
		end
	end)

	return function(owned, equipped)
		if equipped == item.Id then
			state = "equipped"
			button.Text = "Надето ✓"
			setColor(Color3.fromRGB(120, 120, 140))
		elseif owned[item.Id] then
			state = "equip"
			button.Text = "Надеть"
			setColor(Style.Colors.Blue)
		elseif item.Unique then
			state = "stand"
			button.Text = "Стенд в хабе"
			setColor(Style.Colors.Gold)
		else
			state = "buy"
			button.Text = Format.Number(item.Cost) .. " ✨"
			setColor(if aura.Value >= item.Cost then Style.Colors.Green else Style.Colors.Red)
		end
	end
end

-- Window with one tab per category. Returns window + showTab(category).
local function makeWindow(title: string, color: Color3, categories: { string })
	local window = Window.new(title, color)
	local content = window.Content
	local hasTabs = #categories > 1

	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, if hasTabs then 40 else 0)
	tabBar.BackgroundTransparency = 1
	tabBar.Visible = hasTabs
	tabBar.ZIndex = 33
	tabBar.Parent = content
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local pages = {}
	local updaters = {}

	local function showTab(category)
		for name, page in pairs(pages) do
			page.list.Visible = name == category
			page.setColor(if name == category then color else Color3.fromRGB(150, 140, 170))
		end
	end

	for index, category in ipairs(categories) do
		local shop = Config.Shop[category]
		local tab, setColor = Style.Button(tabBar, { Size = UDim2.fromOffset(140, 38), Color = color, Text = shop.Title, TextSize = 18, ZIndex = 34, LayoutOrder = index, Shadow = false })
		tab.Activated:Connect(function()
			showTab(category)
		end)

		local holder = Instance.new("Frame")
		holder.Position = UDim2.fromOffset(0, if hasTabs then 48 else 0)
		holder.Size = UDim2.new(1, 0, 1, if hasTabs then -48 else 0)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 32
		holder.Parent = content
		local list = Window.List(holder)

		pages[category] = { list = holder, setColor = setColor }
		updaters[category] = {}
		for order, item in ipairs(shop.Items) do
			table.insert(updaters[category], makeCard(list, category, item, order))
		end
	end

	local function refresh()
		for category, list in pairs(updaters) do
			local owned = Shop.OwnedSet(category)
			local equipped = player:GetAttribute("Equipped" .. category)
			for _, update in ipairs(list) do
				update(owned, equipped)
			end
		end
	end
	for _, category in ipairs(categories) do
		player:GetAttributeChangedSignal("Owned" .. category):Connect(refresh)
		player:GetAttributeChangedSignal("Equipped" .. category):Connect(refresh)
	end
	aura.Changed:Connect(function()
		if window.IsOpen() then
			refresh()
		end
	end)
	window.OnOpen = refresh
	showTab(categories[1])
	refresh()
	return window, showTab
end

local shopWindow, showShopTab = makeWindow("Мастерская", Style.Colors.Green, { "Weapon", "Backpack" })
local petsWindow = makeWindow("Питомцы", Style.Colors.Magenta, { "Pet" })

Shop.Window = shopWindow
Shop.PetsWindow = petsWindow

function Shop.Open(tab: string?)
	showShopTab(tab or "Weapon")
	shopWindow.Open()
end

function Shop.OpenPets()
	petsWindow.Open()
end

return Shop
