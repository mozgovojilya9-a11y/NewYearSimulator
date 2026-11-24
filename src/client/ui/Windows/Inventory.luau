--[[
	Inventory.luau
	"Инвентарь": the player's gear (item instances).
	  left   - the paper doll (sheet 02): the player's character turning in a
	           viewport, the four worn slots around it; set bonus, Gear
	           Score, монеты / ядра under it
	  center - filters by type, sorting, mass salvage by rarity, the grid
	           (rarity frame, +N, lock, green arrow = better than worn)
	  right  - the selected item: stats compared with what is worn in its
	           slot, bonus props, Надеть / Снять, lock, Разобрать
	The server does everything (Items remote) and publishes the result as
	player attributes (PlayerData.Items / Equipped).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local ItemIcon = require(script.Parent.Parent.ItemIcon)
local Icons = require(script.Parent.Parent.Icons)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Items")

local Inventory = {}

local window = Window.new("Инвентарь", nil, Vector2.new(960, 560), "bag")
local content = window.Content

local SLOTS = { "Weapon", "Helmet", "Chest", "Legs" }
local SLOT_NAMES = { Weapon = "Оружие", Helmet = "Шлем", Chest = "Нагрудник", Legs = "Поножи" }
local SLOT_ICONS = { Weapon = "sword", Helmet = "helmet", Chest = "armor", Legs = "legs" }
local CLASS_NAMES = { Any = "любой класс" }
for _, class in ipairs(Config.Classes) do
	CLASS_NAMES[class.Id] = class.Name
end
local GREEN, RED = Color3.fromRGB(90, 230, 110), Color3.fromRGB(255, 96, 96)

local selected -- uid
local filter = "All"
local sortMode = 1
local SORTS = {
	{ Name = "Сила", Key = function(v) return v.Score end },
	{ Name = "Редкость", Key = function(v) return Config.Rarity[v.Rarity].Index * 1000 + v.Score end },
	{ Name = "Уровень", Key = function(v) return v.ItemLevel * 10 + Config.Rarity[v.Rarity].Index end },
	{ Name = "Новые", Key = function(v) return tonumber(string.sub(v.Uid, 2)) or 0 end },
}
local refresh

local busy = false
local function request(action, arg, quiet)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = remote:InvokeServer(action, arg)
		busy = false
		if message and message ~= "" and not (quiet and ok) then
			Popups.Toast(message, if ok then "good" else "bad")
		end
		if ok and action == "Equip" then
			Style.PlaySound(Config.Sounds.Unsheath, 1.1, 0.5)
		end
	end)
end

-- Main stat line of a view: "Урон 124" / "+86 HP · 3.5%".
function Inventory.StatText(view): string
	if view.Kind == "Weapon" then
		return "Урон " .. Format.Number(view.Damage)
	end
	return ("+%s HP  •  защита %s%%"):format(Format.Number(view.Health), tostring(math.floor(view.Defense * 1000 + 0.5) / 10))
end

---------------------------------------------------------------------
-- Left: worn slots
---------------------------------------------------------------------

local LEFT = 320
local SLOT = 70
-- the paper doll (sheet 02): the player's character turning slowly on a
-- gold pedestal in the middle, the worn slots around it (rarity frames),
-- the three artifact slots under it
local DOLL_H = 300
local SLOT_AT = { Weapon = { 0, 20 }, Chest = { 0, 20 + SLOT + 26 }, Helmet = { LEFT - SLOT, 20 }, Legs = { LEFT - SLOT, 20 + SLOT + 26 } }
local doll = Instance.new("ViewportFrame")
doll.Name = "Doll"
doll.Position = UDim2.fromOffset(SLOT - 6, 0)
doll.Size = UDim2.fromOffset(LEFT - 2 * SLOT + 12, DOLL_H)
doll.BackgroundTransparency = 1
doll.Ambient = Color3.fromRGB(170, 160, 150)
doll.LightColor = Color3.fromRGB(255, 236, 210)
doll.LightDirection = Vector3.new(-0.4, -1, -0.6)
doll.ZIndex = 33
doll.Parent = content
local dollCamera = Instance.new("Camera")
dollCamera.FieldOfView = 30
dollCamera.Parent = doll
doll.CurrentCamera = dollCamera
-- the gold pedestal ring under the figure
local pedestal = Instance.new("Frame")
pedestal.AnchorPoint = Vector2.new(0.5, 1)
pedestal.Position = UDim2.new(0, LEFT / 2, 0, DOLL_H - 4)
pedestal.Size = UDim2.fromOffset(170, 20)
pedestal.BackgroundColor3 = C.Gold
pedestal.BackgroundTransparency = 0.92
pedestal.BorderSizePixel = 0
pedestal.ZIndex = 32
pedestal.Parent = content
Style.Corner(pedestal, UDim.new(1, 0))
Style.Stroke(pedestal, 2, C.Gold).LineJoinMode = Enum.LineJoinMode.Round
local pedestalCore = Instance.new("Frame")
pedestalCore.AnchorPoint = Vector2.new(0.5, 0.5)
pedestalCore.Position = UDim2.fromScale(0.5, 0.5)
pedestalCore.Size = UDim2.new(0.62, 0, 0.5, 0)
pedestalCore.BackgroundColor3 = C.Gold
pedestalCore.BackgroundTransparency = 0.8
pedestalCore.BorderSizePixel = 0
pedestalCore.ZIndex = 32
pedestalCore.Parent = pedestal
Style.Corner(pedestalCore, UDim.new(1, 0))
local dollModel, dollAngle = nil, 0
local function rebuildDoll()
	if dollModel then
		dollModel:Destroy()
		dollModel = nil
	end
	local character = player.Character
	if not character then
		return
	end
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	if not ok or not copy then
		return
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	copy:PivotTo(CFrame.new(0, 0, 0))
	-- straight into the viewport: a WorldModel there did not redraw until
	-- something else changed (seen in Studio)
	copy.Parent = doll
	dollModel = copy
	local box, size = copy:GetBoundingBox()
	local look = box.Position
	dollCamera.CFrame = CFrame.lookAt(look + Vector3.new(0, size.Y * 0.05, size.Y * 2.3), look)
end
game:GetService("RunService").RenderStepped:Connect(function(dt)
	if dollModel and window.IsOpen() then
		dollAngle += dt * 0.5
		dollModel:PivotTo(CFrame.Angles(0, dollAngle, 0))
	end
end)
local slotCards = {}
for index, slot in ipairs(SLOTS) do
	local card = Instance.new("TextButton")
	card.Name = slot
	local at = SLOT_AT[slot]
	card.Position = UDim2.fromOffset(at[1], at[2])
	card.Size = UDim2.fromOffset(SLOT, SLOT)
	card.LayoutOrder = index
	card.BackgroundTransparency = 1
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 33
	card.Parent = content
	local _, shape = Style.Panel(card, { Size = UDim2.fromScale(1, 1), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33, Thickness = 2 })
	-- a dim slot icon while the slot is empty
	local hint = Icons.Make(card, SLOT_ICONS[slot], 30, C.Line, 34)
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.5)
	local icon = Instance.new("Frame")
	icon.Position = UDim2.fromOffset(4, 4)
	icon.Size = UDim2.fromOffset(SLOT - 8, SLOT - 8)
	icon.BackgroundTransparency = 1
	icon.ZIndex = 34
	icon.Parent = card
	-- the slot name under the tile; the name / stat show in the card on the right
	Style.Label(card, Style.Upper(SLOT_NAMES[slot]), 10, C.Muted, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), Size = UDim2.new(1, 10, 0, 12), ZIndex = 35 })
	local name = Style.Label(card, "", 1, C.Text, { Visible = false, ZIndex = 35 })
	local stat = Style.Label(card, "", 1, C.Gold, { Visible = false, ZIndex = 35 })
	local plusN = Style.Label(card, "", 12, C.Gold, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -2), Size = UDim2.fromOffset(30, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 38 })
	slotCards[slot] = { icon = icon, name = name, stat = stat, shape = shape, hint = hint, plusN = plusN, shown = nil }
	card.Activated:Connect(function()
		local worn = PlayerData.Worn(slot)
		if worn then
			selected = worn.Uid
		end
		filter = if slot == "Weapon" then "Weapon" else slot
		refresh()
	end)
end
-- the three artifact slots under the figure (sheet 02); a click opens Артефакты
local ART = 56
local artSlots = {}
for i = 1, Config.Artifacts.Slots do
	local card = Instance.new("TextButton")
	card.Name = "Artifact" .. i
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0, LEFT / 2 + (i - (Config.Artifacts.Slots + 1) / 2) * (ART + 14), 0, DOLL_H + 4)
	card.Size = UDim2.fromOffset(ART, ART)
	card.BackgroundTransparency = 1
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 33
	card.Parent = content
	local _, shape = Style.Panel(card, { Size = UDim2.fromScale(1, 1), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33, Thickness = 2 })
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 34
	holder.Parent = card
	artSlots[i] = { shape = shape, holder = holder, shown = nil }
	card.Activated:Connect(function()
		require(script.Parent.Artifacts).Open()
	end)
end
local function refreshArtifacts()
	local state = PlayerData.Table("Artifacts")
	local owned = if type(state.Owned) == "table" then state.Owned else {}
	for i, ui in ipairs(artSlots) do
		local id = (type(state.Slots) == "table" and state.Slots[i]) or ""
		local def = Config.ArtifactById[id]
		local has = def ~= nil and owned[id] ~= nil
		local color = if has then (Config.Rarity[def.Rarity] or Config.Rarity.Rare).Color else C.Line
		ui.shape.SetBorder(color)
		local key = if has then id else ""
		if ui.shown ~= key then
			ui.shown = key
			ui.holder:ClearAllChildren()
			local icon = Icons.Make(ui.holder, if has then def.Icon or "star" else "gem", 28, if has then color else C.Line, 35)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
end

local totals = Style.Panel(content, { Position = UDim2.fromOffset(0, DOLL_H + ART + 12), Size = UDim2.new(0, LEFT, 1, -(DOLL_H + ART + 12)), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33 })
local scoreLabel = Style.Label(totals, "", 15, C.Gold, { Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local setLabel = Style.Label(totals, "", 11, C.Muted, { Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 34 })
local moneyLabel = Style.Label(totals, "", 1, C.Text, { Visible = false, ZIndex = 34 }) -- the wallet is in the HUD now
local countLabel = Style.Label(totals, "", 12, C.Muted, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9), Size = UDim2.new(0.5, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })

---------------------------------------------------------------------
-- Center: filters, sort, mass salvage, grid
---------------------------------------------------------------------

local center = Instance.new("Frame")
center.Position = UDim2.fromOffset(LEFT + 12, 0)
center.Size = UDim2.new(1, -(LEFT + 12), 1, 0)
center.BackgroundTransparency = 1
center.ZIndex = 32
center.Parent = content

-- filter chips as icons (sheet 02), then sorting and mass salvage
local FILTERS = { { "All", "all" }, { "Weapon", "sword" }, { "Helmet", "helmet" }, { "Chest", "armor" }, { "Legs", "legs" } }
local filterButtons = {}
for i, def in ipairs(FILTERS) do
	local button, api = Style.IconButton(center, { Icon = def[2], Size = 38, Position = UDim2.fromOffset((i - 1) * 44, 0), ZIndex = 34, Cut = 6 })
	filterButtons[def[1]] = api
	button.Activated:Connect(function()
		filter = def[1]
		refresh()
	end)
end
local sortButton = Style.Button(center, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -46, 0, 0), Size = UDim2.fromOffset(150, 38), Text = "", TextSize = 12, Color = C.Card, Icon = "sort", ZIndex = 34 })
sortButton.Activated:Connect(function()
	sortMode = sortMode % #SORTS + 1
	refresh()
end)
local salvageButton = Style.IconButton(center, { Icon = "recycle", Size = 38, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), ZIndex = 34, Cut = 6 })

local gridHolder = Instance.new("Frame")
gridHolder.Position = UDim2.fromOffset(0, 48)
gridHolder.Size = UDim2.new(1, 0, 1, -48)
gridHolder.BackgroundTransparency = 1
gridHolder.ZIndex = 32
gridHolder.Parent = center
local CELL = 78
local grid = Window.Grid(gridHolder, UDim2.fromOffset(CELL, CELL), 6)
local empty = Style.Label(gridHolder, "Пусто. Предметы падают с роботов во Вратах.", 14, C.Muted, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, ZIndex = 33 })

local cells = {} -- [uid] = { button, key, ... }

local function cellFor(view)
	local key = ("%s|%s|%d"):format(view.Id, view.Rarity, view.Enhance)
	local cell = cells[view.Uid]
	if cell and cell.key == key then
		return cell
	end
	if cell then
		cell.button:Destroy()
	end
	local rarity = Config.Rarity[view.Rarity] or Config.Rarity.Common
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
	local plus = Style.Label(button, if view.Enhance > 0 then "+" .. view.Enhance else "", 13, if view.Glow then Color3.fromRGB(190, 245, 255) else C.Gold, { Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(30, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 38 })
	local _ = plus
	Style.Label(button, tostring(view.ItemLevel), 11, C.Text, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -2), Size = UDim2.fromOffset(30, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 38 })
	local lock = Icons.Make(button, "lock", 16, C.Gold, 38)
	lock.AnchorPoint = Vector2.new(1, 0)
	lock.Position = UDim2.new(1, -3, 0, 3)
	local arrow = Style.Label(button, "▲", 14, GREEN, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -2), Size = UDim2.fromOffset(16, 16), ZIndex = 38 })
	local worn = Style.Label(button, "НАДЕТО", 9, C.Gold, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(1, 0, 0, 12), ZIndex = 38 })
	local _2 = rarity
	button.Activated:Connect(function()
		selected = view.Uid
		refresh()
	end)
	cell = { button = button, key = key, select = select, lock = lock, arrow = arrow, worn = worn }
	cells[view.Uid] = cell
	return cell
end

-- mass salvage overlay
local overlay = Style.Panel(center, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 236), Fill = C.PanelDark, Transparency = 0.02, Border = C.GoldDim, Cut = 8, ZIndex = 40, Visible = false })
Style.Label(overlay, "РАЗОБРАТЬ ВСЁ ЭТОЙ РЕДКОСТИ И НИЖЕ", 12, C.Gold, { Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 })
Style.Label(overlay, "Надетые, под замком и заточенные предметы не трогаем.", 11, C.Muted, { Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 })
local overlayRows = {}
local MASS = { "Common", "Uncommon", "Rare", "Epic" }
local armed -- rarity id waiting for the second click
for i, rarityId in ipairs(MASS) do
	local rarity = Config.Rarity[rarityId]
	local button, setColor = Style.Button(overlay, { Position = UDim2.fromOffset(10, 48 + (i - 1) * 36), Size = UDim2.new(1, -20, 0, 30), Text = "", TextSize = 13, Color = C.Card, ZIndex = 41 })
	button.TextColor3 = rarity.Color
	overlayRows[rarityId] = { button = button, setColor = setColor }
	button.Activated:Connect(function()
		if armed ~= rarityId then
			armed = rarityId
			refresh()
			return
		end
		armed = nil
		overlay.Visible = false
		request("SalvageRarity", rarityId)
	end)
end
local overlayClose = Style.Button(overlay, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(120, 26), Text = "Отмена", TextSize = 12, Color = C.Card, ZIndex = 41 })
overlayClose.Activated:Connect(function()
	overlay.Visible = false
	armed = nil
end)
salvageButton.Activated:Connect(function()
	overlay.Visible = not overlay.Visible
	armed = nil
	refresh()
end)

local function massPreview(rarityId): (number, number)
	local limit = Config.Rarity[rarityId].Index
	local count, cores = 0, 0
	for _, view in pairs(PlayerData.Items()) do
		if Config.Rarity[view.Rarity].Index <= limit and view.Enhance == 0 and not view.Locked and not view.Starter and not PlayerData.IsWorn(view.Uid) then
			count += 1
			cores += Items.SalvageCores(view.Inst)
		end
	end
	return count, cores
end

---------------------------------------------------------------------
-- Right: the selected item
---------------------------------------------------------------------

-- the selected item: a card floating over the grid (sheet 02 tooltip)
local details, detailsShape = Style.Panel(content, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), Size = UDim2.fromOffset(300, 352), Fill = C.PanelDark, Transparency = 0.02, Border = C.Gold, Cut = 10, ZIndex = 44, Thickness = 2 })
for _, d in ipairs({ details }) do
	d.ZIndex = 44
end
local plusBig = Style.Label(details, "", 24, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 10), Size = UDim2.fromOffset(60, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 46 })
local closeCard = Style.IconButton(details, { Icon = "close", Size = 28, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), ZIndex = 47, Cut = 5 })
local iconHolder = Instance.new("Frame")
iconHolder.Position = UDim2.fromOffset(12, 12)
iconHolder.Size = UDim2.fromOffset(84, 84)
iconHolder.BackgroundTransparency = 1
iconHolder.ZIndex = 34
iconHolder.Parent = details
local dName = Style.Label(details, "", 16, C.Text, { Position = UDim2.fromOffset(104, 12), Size = UDim2.new(1, -170, 0, 38), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
local dRarity = Style.Label(details, "", 12, C.Muted, { Position = UDim2.fromOffset(104, 52), Size = UDim2.new(1, -114, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local dLevel = Style.Label(details, "", 12, C.Muted, { Position = UDim2.fromOffset(104, 68), Size = UDim2.new(1, -114, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local dClass = Style.Label(details, "", 12, C.Muted, { Position = UDim2.fromOffset(104, 84), Size = UDim2.new(1, -114, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
Style.Rule(details, { Position = UDim2.fromOffset(10, 106), Size = UDim2.new(1, -20, 0, 1), ZIndex = 34 })
local lines = {}
for i = 1, 9 do
	local label = Style.Label(details, "", 13, C.Text, { Position = UDim2.fromOffset(12, 112 + (i - 1) * 20), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
	lines[i] = label
end
local dCompare = Style.Label(details, "", 11, C.Muted, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -92), Size = UDim2.new(1, -24, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, TextWrapped = true, ZIndex = 35 })
local equipButton, equipColor = Style.Button(details, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -50), Size = UDim2.new(1, -66, 0, 36), Text = "Надеть", TextSize = 15, Color = C.Gold, ZIndex = 35 })
local lockButton, lockApi = Style.IconButton(details, { Icon = "lock", Size = 36, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -50), ZIndex = 35, Cut = 6 })
local scrapButton = Style.Button(details, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 32), Text = "", TextSize = 13, Color = C.Card, ZIndex = 35 })
local dEmpty = Style.Label(details, "", 1, C.Muted, { Visible = false, ZIndex = 35 })
closeCard.Activated:Connect(function()
	selected = nil
	refresh()
end)

-- the card floats over the grid: everything in it is drawn above the cells
local function lift(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") and d.ZIndex < 44 then -- the card's own body / frame is at 44
			d.ZIndex += 12
		end
	end
end
lift(details)

local scrapArmed = false
equipButton.Activated:Connect(function()
	local view = PlayerData.Items()[selected or ""]
	if not view then
		return
	end
	if PlayerData.IsWorn(view.Uid) then
		if view.Kind == "Armor" then
			request("Unequip", view.Slot)
		end
	else
		request("Equip", view.Uid)
	end
end)
lockButton.Activated:Connect(function()
	if selected then
		request("Lock", selected, true)
	end
end)
scrapButton.Activated:Connect(function()
	local view = PlayerData.Items()[selected or ""]
	if not view then
		return
	end
	if not scrapArmed then
		scrapArmed = true
		refresh()
		task.delay(3, function()
			if scrapArmed then
				scrapArmed = false
				refresh()
			end
		end)
		return
	end
	scrapArmed = false
	request("Salvage", { view.Uid })
end)

local function diff(now: number, worn: number?, percent: boolean?): string
	if not worn or now == worn then
		return ""
	end
	local d = now - worn
	local text = if percent then tostring(math.floor(math.abs(d) * 1000 + 0.5) / 10) .. "%" else Format.Number(math.abs(math.floor(d + 0.5)))
	return (' <font color="#%s">(%s%s)</font>'):format(if d > 0 then "5AE66E" else "FF6060", if d > 0 then "+" else "−", text)
end

local shownIcon
local function showDetails()
	local view = PlayerData.Items()[selected or ""]
	local has = view ~= nil
	details.Visible = has
	dEmpty.Visible = false
	for _, o in ipairs({ dName, dRarity, dLevel, dClass, dCompare, equipButton, lockButton, scrapButton, iconHolder }) do
		o.Visible = has
	end
	for _, label in ipairs(lines) do
		label.Text = ""
	end
	if not view then
		shownIcon = nil
		return
	end
	local rarity = Config.Rarity[view.Rarity] or Config.Rarity.Common
	local iconKey = ("%s|%s|%d"):format(view.Uid, view.Rarity, view.Enhance)
	if shownIcon ~= iconKey then
		shownIcon = iconKey
		iconHolder:ClearAllChildren()
		ItemIcon.Create(iconHolder, view.Kind, view, UDim2.fromScale(1, 1), UDim2.new())
		lift(iconHolder)
	end
	dName.Text = view.BaseName or view.Name
	dName.TextColor3 = rarity.Color
	plusBig.Text = if view.Enhance > 0 then "+" .. view.Enhance else ""
	detailsShape.SetBorder(rarity.Color)
	dRarity.Text = rarity.Name .. "  •  " .. SLOT_NAMES[view.Slot]
	dRarity.TextColor3 = rarity.Color
	dLevel.Text = Config.Items.Texts.Level:format(view.ItemLevel)
	local usable = Items.CanUse(view, player:GetAttribute("Class"))
	if view.Kind == "Weapon" then
		dClass.Text = "Класс: " .. (CLASS_NAMES[view.Class] or view.Class)
		dClass.TextColor3 = if usable then C.Muted else RED
	else
		local set = Config.ArmorSets[view.Set or ""]
		dClass.Text = if set then set.Name else ""
		dClass.TextColor3 = C.Muted
	end

	local isWorn = PlayerData.IsWorn(view.Uid)
	local worn = if isWorn then nil else PlayerData.Worn(view.Slot)
	local n = 0
	local function line(text)
		n += 1
		if lines[n] then
			lines[n].Text = text
		end
	end
	if view.Kind == "Weapon" then
		line("Урон  <b>" .. Format.Number(view.Damage) .. "</b>" .. diff(view.Damage, worn and worn.Damage))
	else
		line("Макс. HP  <b>+" .. Format.Number(view.Health) .. "</b>" .. diff(view.Health, worn and worn.Health))
		line("Защита  <b>" .. tostring(math.floor(view.Defense * 1000 + 0.5) / 10) .. "%</b>" .. diff(view.Defense, worn and worn.Defense, true))
	end
	line("Gear Score  <b>" .. view.Score .. "</b>" .. diff(view.Score, worn and worn.Score))
	for _, prop in ipairs(view.Props) do
		line('<font color="#2EE6FF">' .. Items.PropText(prop) .. "</font>")
	end
	if isWorn then
		dCompare.Text = "Этот предмет надет."
	elseif worn then
		dCompare.Text = "Надето: " .. worn.Name .. " — " .. Inventory.StatText(worn)
	else
		dCompare.Text = "Слот пуст."
	end

	if isWorn then
		equipButton.Text = if view.Kind == "Armor" then "Снять" else "В руке"
		equipColor(C.Card)
	elseif not usable then
		equipButton.Text = "Чужой класс"
		equipColor(C.Card)
	else
		equipButton.Text = "Надеть"
		equipColor(C.Gold)
	end
	lockApi.SetActive(view.Locked)
	local canScrap = not isWorn and not view.Locked and not view.Starter
	scrapButton.Text = if not canScrap then (if view.Locked then "Под замком" elseif view.Starter then "Стартовое оружие" else "Надето")
		elseif scrapArmed then "Точно разобрать?"
		else ("Разобрать  •  +%s ядер"):format(Format.Number(Items.SalvageCores(view.Inst)))
	scrapButton.Active = canScrap
	scrapButton.TextTransparency = if canScrap then 0 else 0.5
end

---------------------------------------------------------------------

function refresh()
	local items = PlayerData.Items()
	-- worn slots
	for _, slot in ipairs(SLOTS) do
		local ui = slotCards[slot]
		local view = PlayerData.Worn(slot)
		local key = if view then ("%s|%s|%d"):format(view.Uid, view.Rarity, view.Enhance) else ""
		if ui.shown ~= key then
			ui.shown = key
			ui.icon:ClearAllChildren()
			if view then
				ItemIcon.Create(ui.icon, view.Kind, Items.LookFor(view, player:GetAttribute("Class")), UDim2.fromScale(1, 1), UDim2.new())
			end
		end
		ui.hint.Visible = view == nil
		ui.plusN.Text = if view and view.Enhance > 0 then "+" .. view.Enhance else ""
		ui.shape.SetBorder(if view then (Config.Rarity[view.Rarity] or Config.Rarity.Common).Color else C.Line)
		if view then
			ui.name.Text = view.Name
			ui.name.TextColor3 = (Config.Rarity[view.Rarity] or Config.Rarity.Common).Color
			ui.stat.Text = Inventory.StatText(view)
		else
			ui.name.Text = "Пусто"
			ui.name.TextColor3 = C.Muted
			ui.stat.Text = ""
		end
	end
	scoreLabel.Text = "GEAR SCORE  " .. Format.Number(player:GetAttribute("Stat_GearScore") or 0)
	-- set bonuses (Config.ArmorSets Set2 / Set3): the set with the most worn pieces
	do
		local counts, best, bestN = {}, nil, 0
		for _, slot in ipairs({ "Helmet", "Chest", "Legs" }) do
			local worn = PlayerData.Worn(slot)
			local base = worn and Config.ItemById.Armor and Config.ItemById.Armor[worn.Id]
			local setId = worn and (worn.Set or (base and base.Set)) -- the view reads its base
			if setId then
				counts[setId] = (counts[setId] or 0) + 1
				if counts[setId] > bestN then
					best, bestN = setId, counts[setId]
				end
			end
		end
		local def = best and Config.ArmorSets[best]
		local function line(bonus)
			local parts = {}
			for stat, v in pairs(bonus or {}) do
				local name = Config.SetStatNames[stat] or stat
				local text = if stat == "Regen" or stat == "SlowOnHit" then ("+%s %s"):format(tostring(v), name) else ("+%d%% %s"):format(math.floor(v * 100 + 0.5), name)
				table.insert(parts, text)
			end
			return table.concat(parts, ", ")
		end
		if def then
			setLabel.Text = ("«%s» %d/3\n2: %s\n3: %s"):format(def.Name, bestN, line(def.Set2), line(def.Set3))
			setLabel.TextColor3 = if bestN >= 3 then C.Gold elseif bestN >= 2 then C.Text else C.Muted
		else
			setLabel.Text = "Собери 2–3 части одного сета брони: бонусы"
			setLabel.TextColor3 = C.Muted
		end
	end
	refreshArtifacts()
	moneyLabel.Text = ("%s кр.   •   %s ядер"):format(Format.Number(player:GetAttribute("Credits") or 0), Format.Number(player:GetAttribute("Cores") or 0))

	-- grid
	local list = {}
	local total = 0
	for _, view in pairs(items) do
		total += 1
		if filter == "All" or view.Slot == filter then
			table.insert(list, view)
		end
	end
	countLabel.Text = ("%d / %d"):format(total, Config.Items.MaxInventory)
	local sort = SORTS[sortMode]
	sortButton.Text = sort.Name
	table.sort(list, function(a, b)
		local ka, kb = sort.Key(a), sort.Key(b)
		if ka ~= kb then
			return ka > kb
		end
		return a.Uid < b.Uid
	end)
	for id, api in pairs(filterButtons) do
		api.SetActive(id == filter)
	end
	local alive = {}
	for order, view in ipairs(list) do
		local cell = cellFor(view)
		alive[view.Uid] = true
		cell.button.Visible = true
		cell.button.LayoutOrder = order
		cell.select.Visible = view.Uid == selected
		cell.lock.Visible = view.Locked
		local isWorn = PlayerData.IsWorn(view.Uid)
		cell.worn.Visible = isWorn
		cell.arrow.Visible = not isWorn and Items.CanUse(view, player:GetAttribute("Class")) and Items.IsBetter(view, PlayerData.Worn(view.Slot))
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
		scrapArmed = false
	end
	-- mass salvage rows
	if overlay.Visible then
		for _, rarityId in ipairs(MASS) do
			local row = overlayRows[rarityId]
			local count, cores = massPreview(rarityId)
			row.button.Text = if armed == rarityId then ("Точно? Разобрать %d шт."):format(count)
				else ("%s и ниже:  %d шт.  →  +%s ядер"):format(Config.Rarity[rarityId].Name, count, Format.Number(cores))
			row.setColor(if armed == rarityId then C.Red else C.Card)
			row.button.TextColor3 = if armed == rarityId then C.Text else Config.Rarity[rarityId].Color
		end
	end
	showDetails()
end

PlayerData.Changed({ "Items", "Equipped", "Cores", "Credits", "ArmorSet", "Stat_GearScore", "Class", "Artifacts" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = function()
	overlay.Visible = false
	armed = nil
	refresh()
	task.defer(rebuildDoll) -- the doll wears what the character wears now
end
-- equipment changed while open: dress the doll again (the server swaps
-- the models on the character a moment later)
PlayerData.Changed({ "Equipped" }, function()
	if window.IsOpen() then
		task.delay(0.4, rebuildDoll)
	end
end)

-- Opens the inventory with an item selected (loot feed click).
function Inventory.Show(uid: string?)
	selected = uid or selected
	filter = "All"
	window.Open()
end

Inventory.Window = window
Inventory.Open = window.Open
return Inventory
