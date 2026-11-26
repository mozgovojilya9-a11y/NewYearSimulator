--[[
	Stats.luau
	"Статистика": everything about the character on one screen (server
	ProgressionService.Summary through Progression "Stats"):
	  left    level, class, rank title, XP, Gear Score, damage, HP
	  middle  characteristics (Сила / Ловкость / Живучесть / Восприятие
	          points and the stats they make)
	  right   time in the game, kills, bosses, runs, deaths, pulls, wallet
	  bottom  gate records: best grade and the fastest clear per location
	Opens from the profile (top left) and the Инвентарь / Статус tabs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Icons = require(script.Parent.Parent.Icons)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local player = Players.LocalPlayer
local progression = ReplicatedStorage:WaitForChild("Progression")

local Stats = {}

local window = Window.new("Статистика", C.Gold, Vector2.new(860, 540), "trophy")
local content = window.Content

local function panel(x: number, w: number, h: number, title: string)
	local p = Style.Panel(content, { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, h), Fill = C.PanelDark, Border = C.Line, Cut = 10, ZIndex = 33 })
	Style.Label(p, Style.Upper(title), 13, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	return p
end

local function rows(parent, list, y0: number)
	local out = {}
	for i, label in ipairs(list) do
		local y = y0 + (i - 1) * 26
		Style.Label(parent, label, 14, C.Muted, { Position = UDim2.fromOffset(12, y), Size = UDim2.new(0.6, -12, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
		out[i] = Style.Label(parent, "", 15, C.Text, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y), Size = UDim2.new(0.5, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
	end
	return out
end

-- left: the hero
local hero = panel(0, 250, 300, "Персонаж")
local levelBig = Style.Label(hero, "", 48, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(12, 28), Size = UDim2.fromOffset(110, 54), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local classIcon = Icons.Make(hero, "sword", 30, C.Gold, 34)
classIcon.Position = UDim2.fromOffset(120, 36)
local className = Style.Label(hero, "", 17, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(156, 32), Size = UDim2.new(1, -164, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local title = Style.Label(hero, "", 13, C.Muted, { Position = UDim2.fromOffset(156, 54), Size = UDim2.new(1, -164, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local xpTrack = Instance.new("Frame")
xpTrack.Position = UDim2.fromOffset(12, 90)
xpTrack.Size = UDim2.new(1, -24, 0, 12)
xpTrack.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
xpTrack.BorderSizePixel = 0
xpTrack.ZIndex = 34
xpTrack.Parent = hero
local xpFill = Instance.new("Frame")
xpFill.BackgroundColor3 = C.Gold
xpFill.BorderSizePixel = 0
xpFill.ZIndex = 35
xpFill.Parent = xpTrack
local xpText = Style.Label(hero, "", 12, C.Muted, { Position = UDim2.fromOffset(12, 104), Size = UDim2.new(1, -24, 0, 16), ZIndex = 34 })
local heroRows = rows(hero, { "Gear Score", "Урон удара", "Макс. HP", "Защита" }, 130)

-- middle: characteristics
local chars = panel(262, 270, 300, "Характеристики")
local charRows = rows(chars, { "Сила", "Ловкость", "Живучесть", "Восприятие", "Шанс крита", "Крит. урон", "Скорость атаки", "Удача", "Регенерация" }, 32)

-- right: activity and wallet
local activity = panel(544, 0, 300, "Активность")
activity.Size = UDim2.new(1, -544, 0, 300)
local actRows = rows(activity, { "Время в игре", "Убито роботов", "Побеждено боссов", "Забегов во Врата", "Смертей", "Круток", "Нано-кредиты", "Нано-ядра", "Кристаллы" }, 32)

-- bottom: gate records
local records = panel(0, 0, 0, "Рекорды Врат")
records.Position = UDim2.fromOffset(0, 312)
records.Size = UDim2.new(1, 0, 1, -312)
-- three columns, scrolls when there are more locations than fit
local recordList = Instance.new("ScrollingFrame")
recordList.Position = UDim2.fromOffset(12, 30)
recordList.Size = UDim2.new(1, -24, 1, -36)
recordList.BackgroundTransparency = 1
recordList.BorderSizePixel = 0
recordList.ScrollBarThickness = 4
recordList.ScrollBarImageColor3 = C.GoldDim
recordList.AutomaticCanvasSize = Enum.AutomaticSize.Y
recordList.CanvasSize = UDim2.new()
recordList.ClipsDescendants = true
recordList.ZIndex = 34
recordList.Parent = records
local recordLayout = Instance.new("UIGridLayout")
recordLayout.CellSize = UDim2.new(1 / 3, -8, 0, 26)
recordLayout.CellPadding = UDim2.fromOffset(8, 4)
recordLayout.SortOrder = Enum.SortOrder.LayoutOrder
recordLayout.Parent = recordList

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function playTime(seconds: number): string
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	return if h > 0 then ("%d ч %d мин"):format(h, m) else ("%d мин"):format(m)
end

local function pct(x: number): string
	return ("%d%%"):format(math.floor((x or 0) * 100 + 0.5))
end

local function render(s)
	levelBig.Text = tostring(s.Level)
	local class = Config.ClassById[s.Class]
	Icons.Set(classIcon, if class then class.Icon else "user", if class then class.Color else C.Muted)
	className.Text = if class then class.Name else "Без класса"
	title.Text = s.Title or ""
	xpFill.Size = UDim2.fromScale(math.clamp(s.Xp / math.max(1, s.XpNext), 0, 1), 1)
	xpText.Text = ("%s / %s XP"):format(Format.Number(s.Xp), Format.Number(s.XpNext))
	heroRows[1].Text = Format.Number(s.GearScore)
	heroRows[2].Text = Format.Number(s.Damage)
	heroRows[3].Text = Format.Number(s.MaxHealth)
	heroRows[4].Text = pct(s.Defense)
	local a = s.Attributes
	charRows[1].Text = tostring(a.Str)
	charRows[2].Text = tostring(a.Agi)
	charRows[3].Text = tostring(a.Vit)
	charRows[4].Text = tostring(a.Per)
	charRows[5].Text = pct(s.CritChance)
	charRows[6].Text = ("x%.2f"):format(s.CritDamage or 2)
	charRows[7].Text = ("x%.2f"):format(s.AttackSpeed or 1)
	charRows[8].Text = ("x%.2f"):format(s.Luck or 1)
	charRows[9].Text = ("%.1f HP/с"):format(s.Regen or 0)
	actRows[1].Text = playTime(s.PlaySeconds or 0)
	actRows[2].Text = Format.Number(s.Kills)
	actRows[3].Text = Format.Number(s.Bosses)
	actRows[4].Text = Format.Number(s.Runs)
	actRows[5].Text = Format.Number(s.Deaths)
	actRows[6].Text = Format.Number(s.Pulls)
	actRows[7].Text = Format.Number(s.Credits)
	actRows[8].Text = Format.Number(s.Cores)
	actRows[9].Text = Format.Number(s.Crystals)
	for _, child in ipairs(recordList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, g in ipairs(s.Gates or {}) do
		local cell = Instance.new("Frame")
		cell.LayoutOrder = i
		cell.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
		cell.BorderSizePixel = 0
		cell.ZIndex = 34
		cell.Parent = recordList
		local rankColor = Config.Gates.Colors and Config.Gates.Colors[g.Rank] or C.Gold
		Style.Label(cell, g.Rank, 14, rankColor, { Font = Style.FontTitle, Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(18, 26), ZIndex = 35 })
		Style.Label(cell, g.Name, 12, C.Text, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -96, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
		local result = if g.Grade then ("%s · %s"):format(g.Grade, if g.Seconds then clock(g.Seconds) else "—") else "—"
		Style.Label(cell, result, 12, if g.Grade then C.Gold else C.Muted, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.fromOffset(64, 26), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
	end
end

function Stats.Open()
	window.Open()
	task.spawn(function()
		local ok, s = progression:InvokeServer("Stats")
		if ok and type(s) == "table" then
			render(s)
		end
	end)
end
window.OnOpen = function()
	task.spawn(function()
		local ok, s = progression:InvokeServer("Stats")
		if ok and type(s) == "table" then
			render(s)
		end
	end)
end

Stats.Window = window
return Stats
