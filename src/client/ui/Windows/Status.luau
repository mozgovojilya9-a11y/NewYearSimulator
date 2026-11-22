--[[
	Status.luau
	"Статус": name, class, rank and level on top; the four attributes as
	bars (they grow by themselves with the level, split by the class:
	Config.Attributes.Auto); МОЩЬ - one number to chase; every final stat
	on the right. The server does the math (StatService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Icons = require(script.Parent.Parent.Icons)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local A = Config.Attributes
local player = Players.LocalPlayer

local Status = {}

local window = Window.new("Статус", nil, Vector2.new(760, 500), "user")
local content = window.Content

-- header: name, class, rank, level
local head = Style.Panel(content, { Size = UDim2.new(1, 0, 0, 58), Fill = C.PanelDark, Border = C.Cyan:Lerp(C.Line, 0.5), Cut = 10, ZIndex = 33 })
local nameLabel = Style.Label(head, player.DisplayName, 20, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.6, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local _ = nameLabel
local classLabel = Style.Label(head, "", 13, C.Gold, { Position = UDim2.fromOffset(14, 33), Size = UDim2.new(0.6, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local levelLabel = Style.Label(head, "", 26, C.Cyan, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), Size = UDim2.fromOffset(220, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
local pointsLabel = Style.Label(head, "", 13, C.Gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 35), Size = UDim2.fromOffset(260, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })

-- left: attributes - they grow by themselves (Config.Attributes.Auto),
-- shown as bars; no buttons
local LEFT = 430
local rows = {}
for i, def in ipairs(A.List) do
	local row = Style.Panel(content, { Position = UDim2.fromOffset(0, 68 + (i - 1) * 62), Size = UDim2.fromOffset(LEFT, 54), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33 })
	local icon = Icons.Make(row, def.Icon, 26, C.Cyan, 35)
	icon.Position = UDim2.fromOffset(14, 14)
	Style.Label(row, Style.Upper(def.Name), 15, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(52, 7), Size = UDim2.fromOffset(170, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	Style.Label(row, def.Text, 11, C.Muted, { Position = UDim2.fromOffset(200, 9), Size = UDim2.fromOffset(150, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local value = Style.Label(row, "0", 22, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.fromOffset(60, 24), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(52, 34)
	back.Size = UDim2.new(1, -66, 0, 6)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	back.BorderSizePixel = 0
	back.ZIndex = 35
	back.Parent = row
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.Cyan
	fill.BorderSizePixel = 0
	fill.ZIndex = 36
	fill.Parent = back
	rows[def.Id] = { value = value, fill = fill }
end
local powerLabel = Style.Label(content, "", 34, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.fromOffset(LEFT, 40), ZIndex = 34 })
local refresh

-- right: final stats
local stats = Style.Panel(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 68), Size = UDim2.new(1, -(LEFT + 12), 1, -68), Fill = C.PanelDark, Border = C.Line, Cut = 10, ZIndex = 33 })
Style.Label(stats, "ХАРАКТЕРИСТИКИ", 12, C.Gold, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local STAT_ROWS = {
	{ "Damage", "Урон" }, { "MaxHealth", "Макс. HP" }, { "Defense", "Защита", "pct" }, { "AttackSpeed", "Скорость атаки", "x" },
	{ "CritChance", "Шанс крита", "pct" }, { "CritDamage", "Крит. урон", "x" }, { "Luck", "Удача", "x" }, { "DropChance", "Шанс добычи", "plus" },
	{ "Regen", "Регенерация", "hp" }, { "Lifesteal", "Вампиризм", "pct" }, { "GearScore", "Gear Score" },
}
local statLabels = {}
for i, def in ipairs(STAT_ROWS) do
	local y = 30 + (i - 1) * 24
	Style.Label(stats, def[2], 13, C.Muted, { Position = UDim2.fromOffset(12, y), Size = UDim2.new(0.6, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	statLabels[i] = Style.Label(stats, "", 14, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y), Size = UDim2.new(0.4, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
end

local function statText(value: number, kind: string?): string
	if kind == "pct" then
		return tostring(math.floor(value * 1000 + 0.5) / 10) .. "%"
	elseif kind == "plus" then
		return "+" .. tostring(math.floor(value * 1000 + 0.5) / 10) .. "%"
	elseif kind == "x" then
		return "x" .. tostring(math.floor(value * 100 + 0.5) / 100)
	elseif kind == "hp" then
		return tostring(math.floor(value * 10 + 0.5) / 10) .. " HP/с"
	end
	return Format.Number(value)
end

function refresh()
	local level = player:GetAttribute("Level") or 1
	local class = Config.ClassById[player:GetAttribute("Class") or ""]
	classLabel.Text = (if class then class.Name else Config.Ui.Texts.NoClass) .. "  •  " .. Config.RankFor(level).Name
	levelLabel.Text = "УРОВЕНЬ " .. level
	pointsLabel.Text = ""
	local spent = PlayerData.Table("Attributes")
	local used = 0
	for _, v in pairs(spent) do
		used += v
	end
	local free = math.max(0, Config.StatPointsAtLevel(level) - used)
	local shares = A.Auto[player:GetAttribute("Class") or ""] or A.Auto.Default
	local totals, top = {}, 1
	for _, def in ipairs(A.List) do
		totals[def.Id] = math.floor((spent[def.Id] or 0) + free * (shares[def.Id] or 0))
		top = math.max(top, totals[def.Id])
	end
	for _, def in ipairs(A.List) do
		local row = rows[def.Id]
		row.value.Text = tostring(totals[def.Id])
		Style.Tween(row.fill, 0.3, { Size = UDim2.fromScale(totals[def.Id] / top, 1) })
	end
	local all = PlayerData.Table("Stats")
	for i, def in ipairs(STAT_ROWS) do
		statLabels[i].Text = statText(all[def[1]] or 0, def[3])
	end
	-- one number to chase: МОЩЬ
	local dps = (all.Damage or 1) * (all.AttackSpeed or 1) * (1 + (all.CritChance or 0) * math.max(0, (all.CritDamage or 1.5) - 1))
	powerLabel.Text = "МОЩЬ  " .. Format.Number(math.floor(dps * 10 + (all.MaxHealth or 100) / 2))
end

PlayerData.Changed({ "Attributes", "StatPoints", "Stats", "Level", "Class" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = function()
	refresh()
end

Status.Window = window
Status.Open = window.Open
return Status
