--[[
	Forge.luau
	"Кузница" (opens at the forge console in the Фабрикатор).
	  left  - the player's items (grid; the tab filters what fits)
	  right - four tabs:
	    Заточка    +N -> +N+1: stats before / after, cost in монеты and
	               ядра, chance from +10 (with the pity bonus)
	    Возвышение rarity one step up: cost + the spare item it consumes
	    Перековка  pick ONE bonus prop and reroll it
	    Разбор     the item -> Нано-ядра
	The server decides everything (Forge / Items remotes); the window
	plays a short strike animation and shows the result.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local ItemIcon = require(script.Parent.Parent.ItemIcon)
local Style = require(script.Parent.Parent.Style)
local Icons = require(script.Parent.Parent.Icons)
local Window = require(script.Parent.Window)

local C = Style.Colors
local F = Config.Forge
local T = F.Texts
local player = Players.LocalPlayer
local forgeRemote = ReplicatedStorage:WaitForChild("Forge")
local itemsRemote = ReplicatedStorage:WaitForChild("Items")

local Forge = {}

local window = Window.new("Кузница", nil, Vector2.new(940, 540), "hammer")
local content = window.Content

local TABS = { "Enhance", "Ascend", "Reforge", "Salvage" }
local tab = "Enhance"
local selected -- uid
local propIndex = 1
local busy = false
local armed = false
local refresh

---------------------------------------------------------------------
-- Left: items
---------------------------------------------------------------------

local LEFT = 316
local left = Instance.new("Frame")
left.Size = UDim2.new(0, LEFT, 1, 0)
left.BackgroundTransparency = 1
left.ZIndex = 32
left.Parent = content
local money = Style.Label(left, "", 13, C.Gold, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local gridHolder = Instance.new("Frame")
gridHolder.Position = UDim2.fromOffset(0, 24)
gridHolder.Size = UDim2.new(1, 0, 1, -24)
gridHolder.BackgroundTransparency = 1
gridHolder.ZIndex = 32
gridHolder.Parent = left
local grid = Window.Grid(gridHolder, UDim2.fromOffset(68, 68), 6)
local empty = Style.Label(gridHolder, "Нет подходящих предметов", 14, C.Muted, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 20), ZIndex = 33 })

local cells = {}
local function cellFor(view)
	local key = ("%s|%s|%d"):format(view.Id, view.Rarity, view.Enhance)
	local cell = cells[view.Uid]
	if cell and cell.key == key then
		return cell
	end
	if cell then
		cell.button:Destroy()
	end
	local button = Instance.new("TextButton")
	button.Name = view.Uid
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 33
	button.Parent = grid
	ItemIcon.Create(button, view.Kind, view, UDim2.fromScale(1, 1), UDim2.new())
	local select = Instance.new("Frame")
	select.Size = UDim2.fromScale(1, 1)
	select.BackgroundTransparency = 1
	select.ZIndex = 37
	select.Visible = false
	select.Parent = button
	Style.Stroke(select, 3, Color3.new(1, 1, 1))
	Style.Corner(select, UDim.new(0, 10))
	Style.Label(button, if view.Enhance > 0 then "+" .. view.Enhance else "", 13, if view.Glow then Color3.fromRGB(190, 245, 255) else C.Gold, { Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(30, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 38 })
	Style.Label(button, tostring(view.ItemLevel), 11, C.Text, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -2), Size = UDim2.fromOffset(30, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 38 })
	local worn = Style.Label(button, "НАДЕТО", 9, C.Gold, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(1, 0, 0, 12), ZIndex = 38 })
	button.Activated:Connect(function()
		selected = view.Uid
		propIndex = 1
		armed = false
		refresh()
	end)
	cell = { button = button, key = key, select = select, worn = worn }
	cells[view.Uid] = cell
	return cell
end

local function fits(view): boolean
	if tab == "Enhance" then
		return view.Enhance < F.MaxEnhance
	elseif tab == "Ascend" then
		return Items.NextRarity(view.Rarity) ~= nil
	elseif tab == "Reforge" then
		return #view.Props > 0
	end
	return not view.Locked and not view.Starter and not PlayerData.IsWorn(view.Uid)
end

---------------------------------------------------------------------
-- Right: tabs + the action panel
---------------------------------------------------------------------

local right = Instance.new("Frame")
right.Position = UDim2.fromOffset(LEFT + 14, 0)
right.Size = UDim2.new(1, -(LEFT + 14), 1, 0)
right.BackgroundTransparency = 1
right.ZIndex = 32
right.Parent = content

local tabButtons = {}
for i, id in ipairs(TABS) do
	local button, setColor = Style.Button(right, { Position = UDim2.new((i - 1) / #TABS, 0, 0, 0), Size = UDim2.new(1 / #TABS, -4, 0, 30), Text = T.Tabs[id], TextSize = 12, Color = C.Card, ZIndex = 34 })
	tabButtons[id] = setColor
	button.Activated:Connect(function()
		tab = id
		armed = false
		refresh()
	end)
end

local panel = Style.Panel(right, { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), Fill = C.PanelDark, Border = C.Line, Cut = 10, ZIndex = 33 })

-- sheet 02: the item now (+N) >>> the item after (+N+1, gold frame)
local CARD = 96
local function itemCard(x: number, gold: boolean)
	local frame, shape = Style.Panel(panel, { Position = UDim2.fromOffset(x, 16), Size = UDim2.fromOffset(CARD, CARD), Fill = C.CardDark, Border = if gold then C.Gold else C.Line, Cut = 8, ZIndex = 34, Thickness = 2 })
	local holder = Instance.new("Frame")
	holder.Position = UDim2.fromOffset(4, 4)
	holder.Size = UDim2.new(1, -8, 1, -8)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 35
	holder.Parent = frame
	local plus = Style.Label(frame, "", 18, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(50, 22), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 38 })
	return { frame = frame, shape = shape, holder = holder, plus = plus, shown = nil }
end
local beforeCard = itemCard(14, false)
local arrows = Style.Label(panel, "»»", 34, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(14 + CARD, 16), Size = UDim2.fromOffset(52, CARD), ZIndex = 35 })
local afterCard = itemCard(14 + CARD + 52, true)
local pName = Style.Label(panel, "", 15, C.Text, { Position = UDim2.fromOffset(14, 20 + CARD), Size = UDim2.fromOffset(2 * CARD + 52, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
local pSub = Style.Label(panel, "", 12, C.Muted, { Position = UDim2.fromOffset(14, 42 + CARD), Size = UDim2.fromOffset(2 * CARD + 52, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })

-- the result box: "РЕЗУЛЬТАТ (+8)" and rows  name  before » after (+diff)
local RX = 14 + 2 * CARD + 52 + 16
local result = Style.Panel(panel, { Position = UDim2.fromOffset(RX, 16), Size = UDim2.new(1, -(RX + 14), 0, 146), Fill = C.CardDark, Border = C.GoldDim, Cut = 8, ZIndex = 34 })
local pHead = Style.Label(result, "", 15, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, ZIndex = 35 })
local rows = {}
for i = 1, 5 do
	local left = Style.Label(result, "", 13, C.Text, { Position = UDim2.fromOffset(12, 34 + (i - 1) * 22), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, ZIndex = 35 })
	local right = Style.Label(result, "", 13, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 34 + (i - 1) * 22), Size = UDim2.new(0.62, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, RichText = true, ZIndex = 35 })
	rows[i] = { left = left, right = right }
end
-- bonus props as buttons (Reforge)
local propButtons = {}
for i = 1, 3 do
	local button, setColor = Style.Button(result, { Position = UDim2.fromOffset(10, 34 + (i - 1) * 36), Size = UDim2.new(1, -20, 0, 32), Text = "", TextSize = 13, Color = C.Card, ZIndex = 36 })
	button.Visible = false
	propButtons[i] = { button = button, setColor = setColor }
	button.Activated:Connect(function()
		propIndex = i
		refresh()
	end)
end

-- the success chance: a big number and a cyan bar
local chanceTitle = Style.Label(panel, "Шанс успеха:", 16, C.Text, { Position = UDim2.fromOffset(14, 182), Size = UDim2.fromOffset(150, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local chanceValue = Style.Label(panel, "", 26, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(150, 180), Size = UDim2.fromOffset(120, 32), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local chanceTrack, chanceFill = Style.Bar(panel, { Position = UDim2.fromOffset(14, 218), Size = UDim2.new(1, -28, 0, 12), Color = C.Cyan, ZIndex = 35 })
local noteLabel = Style.Label(panel, "", 12, C.Muted, { Position = UDim2.fromOffset(14, 236), Size = UDim2.new(1, -28, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, RichText = true, ZIndex = 35 })

-- bottom: the cost pill and the big gold action button
local costPill = Style.Panel(panel, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -258, 0, 50), Fill = C.CardDark, Border = C.Line, Cut = 8, ZIndex = 34 })
Style.Label(costPill, "Цена:", 15, C.Text, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(60, 50), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local coinIcon = Icons.Make(costPill, "credits", 22, C.Gold, 35)
coinIcon.AnchorPoint = Vector2.new(0, 0.5)
coinIcon.Position = UDim2.new(0, 70, 0.5, 0)
local creditCost = Style.Label(costPill, "", 17, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(98, 0), Size = UDim2.fromOffset(100, 50), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local coreIcon = Icons.Make(costPill, "core", 22, C.Cyan, 35)
coreIcon.AnchorPoint = Vector2.new(0, 0.5)
coreIcon.Position = UDim2.new(0, 200, 0.5, 0)
local coreCost = Style.Label(costPill, "", 17, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(228, 0), Size = UDim2.fromOffset(60, 50), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local track, fill = Style.Bar(panel, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -70), Size = UDim2.fromOffset(220, 4), Color = C.Gold, ZIndex = 35 })
track.Visible = false
local action, actionColor = Style.Button(panel, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(220, 50), Text = "", TextSize = 20, Color = C.Gold, ZIndex = 35 })
local hint = Style.Label(panel, T.Pick, 15, C.Muted, { Position = UDim2.fromOffset(0, 180), Size = UDim2.new(1, 0, 0, 22), ZIndex = 36 })

local function colored(text: string, color: Color3): string
	return ('<font color="#%02X%02X%02X">%s</font>'):format(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5), text)
end
local GREEN, RED = Color3.fromRGB(90, 230, 110), Color3.fromRGB(255, 96, 96)

local function setCost(credits: number, cores: number)
	costPill.Visible = true
	local haveCredits = (player:GetAttribute("Credits") or 0) >= credits
	local haveCores = (player:GetAttribute("Cores") or 0) >= cores
	creditCost.Text = Format.Number(credits)
	creditCost.TextColor3 = if haveCredits then C.Text else RED
	coreCost.Text = Format.Number(cores)
	coreCost.TextColor3 = if haveCores then C.Text else RED
	coreIcon.Visible = cores > 0
	coreCost.Visible = cores > 0
end

local function setChance(share: number?)
	local show = share ~= nil
	chanceTitle.Visible = show
	chanceValue.Visible = show
	chanceTrack.Visible = show
	if share then
		chanceValue.Text = math.floor(share * 100 + 0.5) .. "%"
		chanceValue.TextColor3 = if share >= 0.7 then C.Gold elseif share >= 0.4 then C.Orange else RED
		chanceFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	end
end

-- The spare item an ascend would consume (same rule as the server).
local function twinOf(view)
	local best
	for _, other in pairs(PlayerData.Items()) do
		if other.Uid ~= view.Uid and other.Id == view.Id and not other.Locked and not other.Starter and not PlayerData.IsWorn(other.Uid) then
			if not best or other.Score < best.Score then
				best = other
			end
		end
	end
	return best
end

local function showCard(card, view)
	local key = if view then ("%s|%s|%d"):format(view.Uid or view.Id, view.Rarity, view.Enhance) else ""
	if card.shown ~= key then
		card.shown = key
		card.holder:ClearAllChildren()
		if view then
			ItemIcon.Create(card.holder, view.Kind, view, UDim2.fromScale(1, 1), UDim2.new())
		end
	end
	card.plus.Text = if view and view.Enhance > 0 then "+" .. view.Enhance else ""
	if view then
		card.shape.SetBorder((Config.Rarity[view.Rarity] or Config.Rarity.Common).Color)
	end
end

local function showPanel()
	local view = PlayerData.Items()[selected or ""]
	local has = view ~= nil
	hint.Visible = not has
	for _, o in ipairs({ beforeCard.frame, afterCard.frame, arrows, pName, pSub, result, noteLabel, action, costPill }) do
		o.Visible = has
	end
	setChance(nil)
	for _, r in ipairs(rows) do
		r.left.Text = ""
		r.right.Text = ""
	end
	for _, p in ipairs(propButtons) do
		p.button.Visible = false
	end
	if not view then
		return
	end
	local rarity = Config.Rarity[view.Rarity] or Config.Rarity.Common
	showCard(beforeCard, view)
	pName.Text = view.BaseName or view.Name
	pName.TextColor3 = rarity.Color
	pSub.Text = ("%s  •  %s"):format(rarity.Name, Config.Items.Texts.Level:format(view.ItemLevel))
	noteLabel.Text = ""
	costPill.Visible = false
	action.Active = true
	action.TextTransparency = 0
	actionColor(C.Gold)
	local inst = view.Inst
	local n = 0
	local function row(text)
		n += 1
		if rows[n] then
			rows[n].left.Text = text
		end
	end
	local function stat(name: string, before: string, after: string, diff: string?)
		n += 1
		if rows[n] then
			rows[n].left.Text = name
			rows[n].right.Text = ("%s  »  <b>%s</b>%s"):format(before, after, if diff and diff ~= "" then "  " .. colored("(" .. diff .. ")", GREEN) else "")
		end
	end
	local function pct(v: number): string
		return tostring(math.floor(v * 1000 + 0.5) / 10) .. "%"
	end

	if tab == "Enhance" then
		if view.Enhance >= F.MaxEnhance then
			afterCard.frame.Visible = false
			arrows.Visible = false
			pHead.Text = "РЕЗУЛЬТАТ (+" .. view.Enhance .. ")"
			row(T.Max)
			action.Text = T.Max
			action.Active = false
			action.TextTransparency = 0.5
			actionColor(C.Card)
			return
		end
		local nextInst = table.clone(inst)
		nextInst.E = view.Enhance + 1
		local after = Items.Resolve(nextInst)
		showCard(afterCard, after)
		pHead.Text = ("РЕЗУЛЬТАТ (+%d)"):format(view.Enhance + 1)
		if view.Kind == "Weapon" then
			stat("Урон", Format.Number(view.Damage), Format.Number(after.Damage), "+" .. Format.Number(after.Damage - view.Damage))
		else
			stat("Макс. HP", Format.Number(view.Health), Format.Number(after.Health), "+" .. Format.Number(after.Health - view.Health))
			stat("Защита", pct(view.Defense), pct(after.Defense), "+" .. pct(after.Defense - view.Defense))
		end
		stat("Gear Score", tostring(view.Score), tostring(after.Score), "+" .. (after.Score - view.Score))
		if view.Enhance + 1 == F.GlowFrom then
			row(colored("С +" .. F.GlowFrom .. " предмет светится", Color3.fromRGB(190, 245, 255)))
		end
		local credits, cores = Items.EnhanceCost(inst)
		setCost(credits, cores)
		local chance, pity = Items.EnhanceChance(inst)
		setChance(chance)
		noteLabel.Text = if pity > 0 then T.PityNote:format(math.floor(pity * 100 + 0.5)) .. "  •  при неудаче предмет не ломается" elseif chance < 1 then "При неудаче предмет не ломается" else ""
		action.Text = Style.Upper(T.Enhance)
	elseif tab == "Ascend" then
		local nextId = Items.NextRarity(view.Rarity)
		if not nextId then
			afterCard.frame.Visible = false
			arrows.Visible = false
			pHead.Text = rarity.Name
			row(T.MaxRarity)
			action.Text = T.MaxRarity
			action.Active = false
			action.TextTransparency = 0.5
			actionColor(C.Card)
			return
		end
		local nextRarity = Config.Rarity[nextId]
		local nextInst = table.clone(inst)
		nextInst.R = nextId
		local after = Items.Resolve(nextInst)
		showCard(afterCard, after)
		pHead.Text = ("РЕЗУЛЬТАТ  %s"):format(colored(Style.Upper(nextRarity.Name), nextRarity.Color))
		if view.Kind == "Weapon" then
			stat("Урон", Format.Number(view.Damage), Format.Number(after.Damage), "+" .. Format.Number(after.Damage - view.Damage))
		else
			stat("Макс. HP", Format.Number(view.Health), Format.Number(after.Health), "+" .. Format.Number(after.Health - view.Health))
		end
		stat("Gear Score", tostring(view.Score), tostring(after.Score), "+" .. (after.Score - view.Score))
		local range = Config.Items.BonusCount[nextId]
		if range and #view.Props < range[1] then
			row(colored(("+%d бонусное свойство"):format(range[1] - #view.Props), C.Cyan))
		end
		local credits, cores = Items.AscendCost(inst)
		setCost(credits, cores)
		setChance(1)
		local twin = twinOf(view)
		if twin then
			noteLabel.Text = T.Twin:format(twin.Name .. " (" .. (Config.Rarity[twin.Rarity] or rarity).Name .. ")")
			noteLabel.TextColor3 = C.Muted
		else
			noteLabel.Text = T.NoTwin:format(view.BaseName)
			noteLabel.TextColor3 = RED
		end
		action.Text = Style.Upper(T.Ascend)
	elseif tab == "Reforge" then
		afterCard.frame.Visible = false
		arrows.Visible = false
		pHead.Text = "СВОЙСТВА"
		if #view.Props == 0 then
			row(T.NoProps)
			action.Text = T.Reforge
			action.Active = false
			action.TextTransparency = 0.5
			actionColor(C.Card)
			return
		end
		propIndex = math.clamp(propIndex, 1, #view.Props)
		for i, prop in ipairs(view.Props) do
			local p = propButtons[i]
			if p then
				p.button.Visible = true
				p.button.Text = Items.PropText(prop)
				p.setColor(if i == propIndex then C.Gold else C.Card)
			end
		end
		setCost(Items.ReforgeCost(inst), 0)
		noteLabel.Text = "Выбранное свойство заменится случайным другим"
		noteLabel.TextColor3 = C.Muted
		action.Text = Style.Upper(T.Reforge)
	else
		afterCard.frame.Visible = false
		arrows.Visible = false
		pHead.Text = "РАЗБОР"
		local can = not view.Locked and not view.Starter and not PlayerData.IsWorn(view.Uid)
		row(T.Gain:format(Format.Number(Items.SalvageCores(inst))))
		if view.Enhance > 0 then
			row(colored("Вернётся половина ядер заточки", C.Muted))
		end
		action.Text = if not can then (if view.Locked then "Под замком" elseif view.Starter then "Стартовое оружие" else "Надето") elseif armed then "ТОЧНО?" else Style.Upper(T.Salvage)
		action.Active = can
		action.TextTransparency = if can then 0 else 0.5
		actionColor(if armed then C.Red else if can then C.Gold else C.Card)
	end
end

function refresh()
	local items = PlayerData.Items()
	money.Text = ("%s кр.   •   %s нано-ядер"):format(Format.Number(player:GetAttribute("Credits") or 0), Format.Number(player:GetAttribute("Cores") or 0))
	for id, setColor in pairs(tabButtons) do
		setColor(if id == tab then C.Gold else C.Card)
	end
	local list = {}
	for _, view in pairs(items) do
		if fits(view) then
			table.insert(list, view)
		end
	end
	table.sort(list, function(a, b)
		local wa, wb = PlayerData.IsWorn(a.Uid), PlayerData.IsWorn(b.Uid)
		if wa ~= wb then
			return wa
		end
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.Uid < b.Uid
	end)
	local alive = {}
	for order, view in ipairs(list) do
		local cell = cellFor(view)
		alive[view.Uid] = true
		cell.button.Visible = true
		cell.button.LayoutOrder = order
		cell.select.Visible = view.Uid == selected
		cell.worn.Visible = PlayerData.IsWorn(view.Uid)
	end
	for uid, cell in pairs(cells) do
		if not items[uid] then
			cell.button:Destroy()
			cells[uid] = nil
		elseif not alive[uid] then
			cell.button.Visible = false
		end
	end
	empty.Visible = #list == 0
	if selected and not items[selected] then
		selected = nil
	end
	showPanel()
end

-- Strike animation: the bar fills while the server works, then the result.
local function strike(call)
	if busy then
		return
	end
	busy = true
	track.Visible = true
	fill.Size = UDim2.fromScale(0, 1)
	Style.Tween(fill, F.AnimationSeconds * 0.6, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	for i = 1, F.Strikes do
		task.delay((i - 1) * F.AnimationSeconds * 0.2, function()
			Style.PlaySound(Config.Sounds.Hammer, 0.9 + i * 0.08, 0.6)
		end)
	end
	task.spawn(function()
		local started = os.clock()
		local ok, message, extra = call()
		local left = F.AnimationSeconds * 0.6 - (os.clock() - started)
		if left > 0 then
			task.wait(left)
		end
		busy = false
		track.Visible = false
		if message and message ~= "" then
			Popups.Toast(message, if ok then "gold" else "bad")
		end
		if ok then
			Style.PlaySound(Config.Sounds.Forged, 1, 0.7)
		elseif type(extra) == "table" and extra.Success == false then
			Popups.Shake(0.4, 0.25)
		end
		refresh()
	end)
end

action.Activated:Connect(function()
	local view = PlayerData.Items()[selected or ""]
	if not view or busy or not action.Active then
		return
	end
	local uid = view.Uid
	if tab == "Enhance" then
		strike(function()
			return forgeRemote:InvokeServer("Enhance", uid)
		end)
	elseif tab == "Ascend" then
		strike(function()
			return forgeRemote:InvokeServer("Ascend", uid)
		end)
	elseif tab == "Reforge" then
		local index = propIndex
		strike(function()
			return forgeRemote:InvokeServer("Reforge", uid, index)
		end)
	else
		if not armed then
			armed = true
			refresh()
			task.delay(3, function()
				if armed then
					armed = false
					refresh()
				end
			end)
			return
		end
		armed = false
		strike(function()
			return itemsRemote:InvokeServer("Salvage", { uid })
		end)
	end
end)

PlayerData.Changed({ "Items", "Equipped", "Cores", "Credits" }, function()
	if window.IsOpen() and not busy then
		refresh()
	end
end)
window.OnOpen = function()
	armed = false
	if not selected then
		local worn = PlayerData.Worn("Weapon")
		selected = worn and worn.Uid
	end
	refresh()
end

Forge.Window = window
Forge.Open = window.Open
return Forge
