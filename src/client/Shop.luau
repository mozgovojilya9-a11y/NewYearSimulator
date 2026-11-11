--[[
	Shop.luau
	Day 4: shop windows built from Config.Shop categories. One window can
	hold several categories as tabs (Оружие / Ранцы), and the same code
	builds the Pets window.

	Buttons only *ask* the server (ShopRequest); what is owned/equipped
	comes back through Player attributes set by PlayerState.Sync.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Panels = require(script.Parent.Panels)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local shopRequest = ReplicatedStorage:WaitForChild("ShopRequest")
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local Shop = {}

local CURRENCY_ICON = { Aura = "✨", Gems = "💎" }

local function balance(currency)
	if currency == "Gems" then
		return player:GetAttribute("Gems") or 0
	end
	return aura.Value
end

local function ownedSet(category)
	local set = {}
	local text = player:GetAttribute("Owned" .. category) or ""
	for id in string.gmatch(text, "[^,]+") do
		set[id] = true
	end
	return set
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
		Ui.Toast(message or "", if ok then Ui.Colors.Good else Ui.Colors.Bad)
		if ok then
			Ui.PlaySound(Config.Sounds.Buy, if action == "Buy" then 1.6 else 1.2, 0.6)
		end
	end)
end

local function makeRow(parent, category, item, order)
	local shop = Config.Shop[category]

	local row = Instance.new("Frame")
	row.Name = item.Id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 64)
	row.BackgroundColor3 = Ui.Colors.PanelLight
	row.Parent = parent
	Ui.Corner(row, UDim.new(0, 12))

	local swatch = Instance.new("Frame")
	swatch.Position = UDim2.fromOffset(10, 10)
	swatch.Size = UDim2.fromOffset(44, 44)
	swatch.BackgroundColor3 = item.Color
	swatch.Parent = row
	Ui.Corner(swatch, UDim.new(0.3, 0))
	Ui.Stroke(swatch, 2)

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(66, 8)
	name.Size = UDim2.new(1, -210, 0, 26)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextColor3 = Ui.Colors.Text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = item.Name
	name.Parent = row

	local stat = Instance.new("TextLabel")
	stat.Position = UDim2.fromOffset(66, 34)
	stat.Size = UDim2.new(1, -210, 0, 20)
	stat.BackgroundTransparency = 1
	stat.Font = Enum.Font.Gotham
	stat.TextSize = 15
	stat.TextColor3 = Ui.Colors.Aura
	stat.TextXAlignment = Enum.TextXAlignment.Left
	stat.Text = shop.Describe(item)
	stat.Parent = row

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(130, 44)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Ui.Colors.Text
	button.Parent = row
	Ui.Corner(button, UDim.new(0, 10))
	Ui.Stroke(button, 1.5)

	local state = "buy"
	button.Activated:Connect(function()
		if state == "buy" then
			request("Buy", category, item.Id)
		elseif state == "equip" then
			request("Equip", category, item.Id)
		end
	end)

	return function(owned, equipped)
		if equipped == item.Id then
			state = "equipped"
			button.Text = "Надето"
			button.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
			button.AutoButtonColor = false
		elseif owned[item.Id] then
			state = "equip"
			button.Text = "Надеть"
			button.BackgroundColor3 = Color3.fromRGB(70, 130, 230)
			button.AutoButtonColor = true
		else
			state = "buy"
			button.Text = Format.Number(item.Cost) .. " " .. CURRENCY_ICON[shop.Currency]
			local affordable = balance(shop.Currency) >= item.Cost
			button.BackgroundColor3 = if affordable then Ui.Colors.Good else Color3.fromRGB(120, 60, 70)
			button.AutoButtonColor = affordable
		end
	end
end

-- Builds a window with one tab per category and a menu button for it.
function Shop.MakeWindow(title: string, icon: string, color: Color3, categories: { string })
	local window = Panels.Create(title)
	local content = window.Content

	local hasTabs = #categories > 1
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, if hasTabs then 36 else 0)
	tabBar.BackgroundTransparency = 1
	tabBar.Visible = hasTabs
	tabBar.Parent = content
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabBar

	local pages = {}
	local updaters = {} -- [category] = { update functions }

	local function showTab(category)
		for name, page in pairs(pages) do
			page.list.Visible = name == category
			page.tab.BackgroundColor3 = if name == category then Ui.Colors.Accent else Ui.Colors.PanelLight
		end
	end

	for index, category in ipairs(categories) do
		local shop = Config.Shop[category]

		local tab = Instance.new("TextButton")
		tab.LayoutOrder = index
		tab.Size = UDim2.fromOffset(120, 34)
		tab.Font = Enum.Font.GothamBold
		tab.TextSize = 16
		tab.TextColor3 = Ui.Colors.Text
		tab.Text = shop.Title
		tab.Parent = tabBar
		Ui.Corner(tab, UDim.new(0, 10))
		tab.Activated:Connect(function()
			showTab(category)
		end)

		local list = Instance.new("ScrollingFrame")
		list.Position = UDim2.fromOffset(0, if hasTabs then 44 else 0)
		list.Size = UDim2.new(1, 0, 1, if hasTabs then -44 else 0)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.Parent = content
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list

		pages[category] = { list = list, tab = tab }
		updaters[category] = {}
		for order, item in ipairs(shop.Items) do
			table.insert(updaters[category], makeRow(list, category, item, order))
		end
	end

	local function refresh()
		for category, list in pairs(updaters) do
			local owned = ownedSet(category)
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
	player:GetAttributeChangedSignal("Gems"):Connect(refresh)
	aura.Changed:Connect(function()
		if window.Frame.Visible then
			refresh()
		end
	end)
	window.OnOpen = refresh

	showTab(categories[1])
	refresh()
	Panels.AddMenuButton(icon, title, color, window)
	return window
end

Shop.MakeWindow("Магазин", "🛒", Color3.fromRGB(70, 160, 90), { "Weapon", "Backpack" })
Shop.MakeWindow("Питомцы", "🐾", Color3.fromRGB(230, 150, 60), { "Pet" })

return Shop
