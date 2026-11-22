--[[
	Store.luau
	"Магазин". Tabs (Config.Store.Tabs): Рынок (Чёрный рынок for credits,
	MarketService) / Кристаллы / Пассы / Бусты / Смена класса (Robux). Every card
	shows icon, name, what it gives and the price. Items whose
	id in Config is still 0 show a grey "Скоро" button. Buying opens the
	Roblox purchase prompt; the server grants it (passes: Passes.luau,
	products: StoreService ProcessReceipt) and confirms with a toast.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer

local Store = {}

local window = Window.new("Магазин", Style.Colors.Cyan, Vector2.new(720, 500))
local content = window.Content
local tabs, selectTab = Window.Tabs(content, Config.Store.Tabs, Style.Colors.Cyan, 156)

local tabLine = Style.Label(content, "", 13, Style.Colors.Muted, { Position = UDim2.fromOffset(4, 46), Size = UDim2.new(1, -8, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local holder = Instance.new("Frame")
holder.Position = UDim2.fromOffset(0, 70)
holder.Size = UDim2.new(1, 0, 1, -70)
holder.BackgroundTransparency = 1
holder.ZIndex = 32
holder.Parent = content
local grid = Window.Grid(holder, UDim2.fromOffset(222, 178))

local GREY = Color3.fromRGB(110, 110, 130)
local cards = {} -- { card, tab, refresh }

local function describe(product): string
	if product.Kind == "Credits" then
		return ("+%s нано-кредитов: заточка в Кузнице, сбросы"):format(Format.Number(product.Amount))
	elseif product.Kind == "Crystals" then
		return ("+%d Кристаллов: %d круток x1 в Терминале снабжения"):format(product.Amount, math.floor(product.Amount / Config.Gacha.Cost.One))
	elseif product.Kind == "ClassChange" then
		local cc = Config.ClassChange
		return ("Выбери новый класс в Академии. Оплата там: Robux, %d Кристаллов или кредиты"):format(cc.Crystals)
	elseif product.Kind == "Boost" then
		local what = ({ Xp = "весь опыт", Damage = "весь урон", Loot = "шанс редкой добычи" })[product.Boost] or ""
		return ("x2 %s на %d минут. Время складывается"):format(what, product.Minutes)
	elseif product.Kind == "Chest" then
		return ("%d предмета ранга %s, первый не ниже «%s»"):format(product.Rolls, product.Rank, Config.Rarity[Config.Loot.BossMinRarity[product.Rank]].Name)
	elseif product.Kind == "Weapon" then
		local weapon = Config.ItemById.Weapon[product.Item]
		return weapon and ("Оружие: урон %s"):format(Format.Number(weapon.Damage)) or ""
	elseif product.Kind == "ArmorSet" then
		local set = Config.ArmorSets[product.Item]
		return set and ("3 части: +%d HP, +%d%% урона"):format(set.Health * 3, math.floor(set.Bonus * 100 + 0.5)) or ""
	elseif product.Kind == "WheelSkip" then
		return "Сбрасывает таймер колеса удачи"
	end
	return ""
end

local function card(tab: string, order: number, icon: string, name: string, text: string, price: number, id: number, onBuy, isOwned)
	local c = Style.Card(grid, Style.Colors.Cyan)
	c.LayoutOrder = order
	local glyph = Style.Icons.Make(c, icon, 34, Style.Colors.Gold, 35)
	glyph.AnchorPoint = Vector2.new(0.5, 0)
	glyph.Position = UDim2.new(0.5, 0, 0, 10)
	Style.Label(c, name, 18, Style.Colors.Gold, { Position = UDim2.fromOffset(6, 48), Size = UDim2.new(1, -12, 0, 22), TextScaled = true, ZIndex = 35 })
	Style.Label(c, text, 13, Style.Colors.Text, { Position = UDim2.fromOffset(8, 72), Size = UDim2.new(1, -16, 0, 52), TextWrapped = true, ZIndex = 35 })
	local button, setColor = Style.Button(c, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 40), Color = Style.Colors.Green, Text = "", TextSize = 18, ZIndex = 36, Shadow = false })
	local function refresh()
		c.Visible = tabs.Current == tab
		if tab == "ClassChange" then
			button.Text = "Выбрать класс"
			setColor(Style.Colors.Gold)
		elseif id <= 0 then
			button.Text = ("R$ %d · скоро"):format(price)
			setColor(GREY)
		elseif isOwned and isOwned() then
			button.Text = "Куплено"
			setColor(GREY)
		else
			button.Text = "R$ " .. price
			setColor(Style.Colors.Green)
		end
	end
	button.Activated:Connect(function()
		if tab == "ClassChange" then
			onBuy() -- the class screen: pay with credits, Кристаллы or Robux there
		elseif id <= 0 then
			Popups.Toast("Скоро в продаже!", "gold")
		elseif isOwned and isOwned() then
			Popups.Toast("Уже куплено", "good")
		else
			onBuy()
		end
	end)
	table.insert(cards, { refresh = refresh })
end

-- Passes (sorted by Order)
local passKeys = {}
for key in pairs(Config.GamePasses) do
	table.insert(passKeys, key)
end
table.sort(passKeys, function(a, b)
	return (Config.GamePasses[a].Order or 99) < (Config.GamePasses[b].Order or 99)
end)
for _, key in ipairs(passKeys) do
	local pass = Config.GamePasses[key]
	card("Passes", pass.Order or 99, pass.Icon or "star", pass.Name, pass.Text, pass.Price, pass.Id, function()
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end, function()
		return PlayerData.HasPass(key)
	end)
end
-- Products
for order, product in ipairs(Config.Products) do
	if not product.Tab then
		continue -- not sold in the store
	end
	local sort = order + (if product.Kind == "Crystals" then -100 else 0)
	card(product.Tab, sort, product.Icon or "gem", product.Name, describe(product), product.Price, product.Id, function()
		if product.Kind == "ClassChange" then
			window.Close()
			require(script.Parent.Parent.ClassSelect).Open(true) -- pick the class, pay there
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end, nil)
end

---------------------------------------------------------------------
-- Чёрный рынок (MarketService): offers for credits, new every 10 min
---------------------------------------------------------------------

local MT = Config.Market.Texts
local marketRemote = ReplicatedStorage:WaitForChild("Market")
local marketHolder = Instance.new("Frame")
marketHolder.Position = UDim2.fromOffset(0, 70)
marketHolder.Size = UDim2.new(1, 0, 1, -70)
marketHolder.BackgroundTransparency = 1
marketHolder.ZIndex = 32
marketHolder.Visible = false
marketHolder.Parent = content
local marketGrid = Window.Grid(marketHolder, UDim2.fromOffset(222, 178))
local marketCards = {}
local marketEnds = 0
local loadMarket

local KIND_ICON = { Cores = "gear", Boost = "bolt", Crystals = "crystal" }

local function marketCard(o)
	local rarity = o.Rarity and Config.Rarity[o.Rarity]
	local color = if rarity then rarity.Color else Style.Colors.Cyan
	local c = Style.Card(marketGrid, color)
	c.LayoutOrder = o.Slot
	local icon = if o.Kind == "Item" then (if o.ItemSlot == "Weapon" then "sword" else "shield") else (KIND_ICON[o.Kind] or "gem")
	local glyph = Style.Icons.Make(c, icon, 34, color, 35)
	glyph.AnchorPoint = Vector2.new(0.5, 0)
	glyph.Position = UDim2.new(0.5, 0, 0, 10)
	Style.Label(c, o.Name or "", 16, color, { Font = Style.FontTitle, Position = UDim2.fromOffset(6, 50), Size = UDim2.new(1, -12, 0, 20), TextScaled = true, ZIndex = 35 })
	local sub = if rarity then rarity.Name .. "  ·  ур. " .. tostring(o.Level or 1) else ""
	Style.Label(c, sub, 13, Style.Colors.Muted, { Position = UDim2.fromOffset(6, 74), Size = UDim2.new(1, -12, 0, 18), ZIndex = 35 })
	local button, setColor = Style.Button(c, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 40), Color = Style.Colors.Green, Text = "", TextSize = 18, ZIndex = 36, Shadow = false, Icon = if o.Bought then nil else "credits" })
	if o.Bought then
		button.Text = MT.Bought
		setColor(GREY)
	else
		button.Text = Format.Number(o.Price)
		setColor(if (player:GetAttribute("Credits") or 0) >= o.Price then Style.Colors.Green else GREY)
	end
	button.Activated:Connect(function()
		if o.Bought then
			return
		end
		task.spawn(function()
			local ok, message = marketRemote:InvokeServer("Buy", o.Slot)
			Popups.Toast(tostring(message or ""), if ok then "gold" else "bad")
			if ok then
				Style.PlaySound(Config.Sounds.Buy, 1.1, 0.6)
				loadMarket()
			end
		end)
	end)
	table.insert(marketCards, c)
end

function loadMarket()
	task.spawn(function()
		local ok, info = marketRemote:InvokeServer("List")
		if not ok or type(info) ~= "table" then
			return
		end
		for _, c in ipairs(marketCards) do
			c:Destroy()
		end
		marketCards = {}
		marketEnds = os.clock() + (info.EndsIn or 0)
		for _, o in ipairs(info.Offers or {}) do
			marketCard(o)
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		if window.IsOpen() and tabs.Current == "Market" then
			local left = math.max(0, math.ceil(marketEnds - os.clock()))
			tabLine.Text = MT.Refresh:format(left // 60, left % 60)
			if left <= 0 and marketEnds > 0 then
				marketEnds = 0
				loadMarket()
			end
		end
	end
end)

local function refresh()
	for _, c in ipairs(cards) do
		c.refresh()
	end
	for _, t in ipairs(Config.Store.Tabs) do
		if t.Id == tabs.Current then
			tabLine.Text = t.Line or ""
		end
	end
	local market = tabs.Current == "Market"
	marketHolder.Visible = market
	holder.Visible = not market
	if market and window.IsOpen() then
		loadMarket()
	end
end
tabs.Changed = refresh
selectTab("Market")
PlayerData.Changed({ "Passes" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = refresh

ReplicatedStorage:WaitForChild("StoreNotify").OnClientEvent:Connect(function(text)
	Popups.Toast(tostring(text), "gold")
	Popups.Flash(Style.Colors.Cyan)
	Style.PlaySound(Config.Sounds.Forged, 1.2, 0.6)
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, _, purchased)
	if who == player and purchased then
		Popups.Toast("Пасс куплен! Спасибо!", "gold")
	end
end)

Store.Window = window
function Store.Open(tab: string?)
	selectTab(tab or "Market")
	window.Open()
end
return Store
