--[[
	Artifacts.luau
	"Артефакты": three slots on top (what is equipped), below every owned
	artifact as a row: icon, name in its rarity color, level pips, the
	effect at the current level (and at the next one), Вставить / Снять
	and Улучшить when there are enough spare copies.
	The server does everything (Artifacts remote).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local Icons = require(script.Parent.Parent.Icons)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local A = Config.Artifacts
local T = A.Texts
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Artifacts")

local Artifacts = {}

local window = Window.new("Артефакты", nil, Vector2.new(760, 520), "gem")
local content = window.Content

local busy = false
local function request(action, id)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = remote:InvokeServer(action, id)
		busy = false
		if message and message ~= "" then
			Popups.Toast(message, if ok then "gold" else "bad")
		end
		if ok then
			Style.PlaySound("Ui", 1.2, 0.5)
		end
	end)
end

-- slots
local SLOT_H = 96
local slots = {}
for i = 1, A.Slots do
	local card = Instance.new("TextButton")
	card.Position = UDim2.new((i - 1) / A.Slots, if i == 1 then 0 else 4, 0, 0)
	card.Size = UDim2.new(1 / A.Slots, -6, 0, SLOT_H)
	card.BackgroundTransparency = 1
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 33
	card.Parent = content
	local _, shape = Style.Panel(card, { Size = UDim2.fromScale(1, 1), Fill = C.PanelDark, Border = C.Line, Cut = 10, ZIndex = 33 })
	local _ = shape
	Style.Label(card, Style.Upper(T.Slot:format(i)), 11, C.Muted, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local iconHolder = Instance.new("Frame")
	iconHolder.Position = UDim2.fromOffset(12, 30)
	iconHolder.Size = UDim2.fromOffset(52, 52)
	iconHolder.BackgroundTransparency = 1
	iconHolder.ZIndex = 34
	iconHolder.Parent = card
	local name = Style.Label(card, "", 15, C.Text, { Position = UDim2.fromOffset(72, 30), Size = UDim2.new(1, -82, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
	local text = Style.Label(card, "", 12, C.Muted, { Position = UDim2.fromOffset(72, 52), Size = UDim2.new(1, -82, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
	slots[i] = { iconHolder = iconHolder, name = name, text = text, shown = nil, id = "" }
	card.Activated:Connect(function()
		if slots[i].id ~= "" then
			request("Unequip", slots[i].id)
		end
	end)
end

local listHolder = Instance.new("Frame")
listHolder.Position = UDim2.fromOffset(0, SLOT_H + 12)
listHolder.Size = UDim2.new(1, 0, 1, -(SLOT_H + 12))
listHolder.BackgroundTransparency = 1
listHolder.ZIndex = 32
listHolder.Parent = content
local list = Window.List(listHolder)
local empty = Style.Label(listHolder, T.None, 14, C.Muted, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, ZIndex = 33 })

local rows = {} -- [id] = ui

local function rowFor(def)
	if rows[def.Id] then
		return rows[def.Id]
	end
	local rarity = Config.Rarity[def.Rarity] or Config.Rarity.Rare
	local row = Style.Panel(list, { Size = UDim2.new(1, -8, 0, 72), Fill = C.PanelDark, Border = rarity.Color:Lerp(C.Line, 0.4), Cut = 8, ZIndex = 33 })
	row.Name = def.Id
	row.LayoutOrder = def.Order
	local icon = Icons.Make(row, def.Icon or "star", 34, rarity.Color, 35)
	icon.Position = UDim2.fromOffset(14, 19)
	Style.Label(row, def.Name, 16, rarity.Color, { Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -330, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local level = Style.Label(row, "", 12, C.Gold, { Position = UDim2.fromOffset(62, 29), Size = UDim2.new(1, -330, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local text = Style.Label(row, "", 12, C.Text, { Position = UDim2.fromOffset(62, 46), Size = UDim2.new(1, -330, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, ZIndex = 35 })
	local equip, equipColor = Style.Button(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -150, 0.5, 0), Size = UDim2.fromOffset(108, 34), Text = "", TextSize = 13, Color = C.Gold, ZIndex = 36 })
	local upgrade, upgradeColor = Style.Button(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(132, 34), Text = "", TextSize = 12, Color = C.Card, ZIndex = 36 })
	local ui = { row = row, level = level, text = text, equip = equip, equipColor = equipColor, upgrade = upgrade, upgradeColor = upgradeColor, worn = false }
	equip.Activated:Connect(function()
		request(if ui.worn then "Unequip" else "Equip", def.Id)
	end)
	upgrade.Activated:Connect(function()
		request("Upgrade", def.Id)
	end)
	rows[def.Id] = ui
	return ui
end

local function refresh()
	local state = PlayerData.Table("Artifacts")
	local owned = if type(state.Owned) == "table" then state.Owned else {}
	local worn = {}
	for i = 1, A.Slots do
		local id = (type(state.Slots) == "table" and state.Slots[i]) or ""
		local def = Config.ArtifactById[id]
		local record = def and owned[id]
		local slot = slots[i]
		slot.id = if record then id else ""
		if slot.shown ~= slot.id then
			slot.shown = slot.id
			slot.iconHolder:ClearAllChildren()
			if record then
				local icon = Icons.Make(slot.iconHolder, def.Icon or "star", 40, (Config.Rarity[def.Rarity] or Config.Rarity.Rare).Color, 35)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.fromScale(0.5, 0.5)
			end
		end
		if record then
			worn[id] = true
			slot.name.Text = def.Name
			slot.name.TextColor3 = (Config.Rarity[def.Rarity] or Config.Rarity.Rare).Color
			slot.text.Text = Config.ArtifactText(def, record.Level or 1)
		else
			slot.name.Text = T.Empty
			slot.name.TextColor3 = C.Muted
			slot.text.Text = ""
		end
	end
	local count = 0
	for _, def in ipairs(A.List) do
		local record = owned[def.Id]
		if record then
			count += 1
			local ui = rowFor(def)
			local level = record.Level or 1
			ui.row.Visible = true
			ui.worn = worn[def.Id] == true
			ui.level.Text = T.Level:format(level, A.MaxLevel) .. "   " .. string.rep("◆", level) .. string.rep("◇", A.MaxLevel - level)
			local now = Config.ArtifactText(def, level)
			ui.text.Text = if level < A.MaxLevel then now .. '   <font color="#9E988C">→ ' .. Config.ArtifactText(def, level + 1) .. "</font>" else now
			ui.equip.Text = if ui.worn then T.Unequip else T.Equip
			ui.equipColor(if ui.worn then C.Card else C.Gold)
			if level >= A.MaxLevel then
				ui.upgrade.Text = T.Max
				ui.upgradeColor(C.Card)
				ui.upgrade.TextTransparency = 0.5
			else
				local copies = record.Copies or 0
				ui.upgrade.Text = T.Upgrade:format(copies, level)
				ui.upgradeColor(if copies >= level then C.Gold else C.Card)
				ui.upgrade.TextTransparency = if copies >= level then 0 else 0.4
			end
		elseif rows[def.Id] then
			rows[def.Id].row.Visible = false
		end
	end
	empty.Visible = count == 0
end

PlayerData.Changed({ "Artifacts" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = refresh
local _ = player

Artifacts.Window = window
Artifacts.Open = window.Open
return Artifacts
