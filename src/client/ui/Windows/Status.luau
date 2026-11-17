--[[
	Status.luau
	"Статус" (like the status window in Solo Leveling): name, class,
	rank and level on top; the four attributes with "+" buttons and what
	a point gives; free points; every final stat on the right; reset of
	the points for credits. The server does the math (Status remote,
	StatService); this window only shows the published attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local Icons = require(script.Parent.Parent.Icons)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local A = Config.Attributes
local T = A.Texts
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Status")

local Status = {}

local window = Window.new("Статус", nil, Vector2.new(760, 500), "user")
local content = window.Content

local busy = false
local function request(action, id, count)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = remote:InvokeServer(action, id, count)
		busy = false
		if message and message ~= "" then
			Popups.Toast(message, if ok then "good" else "bad")
		end
		if ok then
			Style.PlaySound("Ui", 1.3, 0.5)
		end
	end)
end

-- header: name, class, rank, level
local head = Style.Panel(content, { Size = UDim2.new(1, 0, 0, 58), Fill = C.PanelDark, Border = C.Cyan:Lerp(C.Line, 0.5), Cut = 10, ZIndex = 33 })
local nameLabel = Style.Label(head, player.DisplayName, 20, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(0.6, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local _ = nameLabel
local classLabel = Style.Label(head, "", 13, C.Gold, { Position = UDim2.fromOffset(14, 33), Size = UDim2.new(0.6, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local levelLabel = Style.Label(head, "", 26, C.Cyan, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), Size = UDim2.fromOffset(220, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
local pointsLabel = Style.Label(head, "", 13, C.Gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 35), Size = UDim2.fromOffset(260, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })

-- left: attributes
local LEFT = 430
local rows = {}
for i, def in ipairs(A.List) do
	local row = Style.Panel(content, { Position = UDim2.fromOffset(0, 68 + (i - 1) * 80), Size = UDim2.fromOffset(LEFT, 72), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33 })
	local icon = Icons.Make(row, def.Icon, 30, C.Cyan, 35)
	icon.Position = UDim2.fromOffset(14, 21)
	Style.Label(row, Style.Upper(def.Name), 16, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(56, 8), Size = UDim2.fromOffset(170, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	Style.Label(row, table.concat(def.Lines, "\n"), 11, C.Muted, { Position = UDim2.fromOffset(56, 30), Size = UDim2.fromOffset(230, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
	local value = Style.Label(row, "0", 26, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -108, 0.5, 0), Size = UDim2.fromOffset(70, 30), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
	local plus, plusApi = Style.IconButton(row, { Icon = "plus", Size = 40, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -56, 0.5, 0), ZIndex = 36, Cut = 6 })
	local plus5 = Style.Button(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(40, 40), Text = "+5", TextSize = 13, Color = C.Card, ZIndex = 36 })
	plus.Activated:Connect(function()
		request("Add", def.Id, 1)
	end)
	plus5.Activated:Connect(function()
		request("Add", def.Id, 5)
	end)
	rows[def.Id] = { value = value, plusApi = plusApi, plus5 = plus5 }
end
local resetButton = Style.Button(content, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromOffset(LEFT, 34), Text = "", TextSize = 13, Color = C.Card, Icon = "reset", ZIndex = 34 })
local resetArmed = false
local refresh
resetButton.Activated:Connect(function()
	if not resetArmed then
		resetArmed = true
		refresh()
		task.delay(3, function()
			if resetArmed then
				resetArmed = false
				refresh()
			end
		end)
		return
	end
	resetArmed = false
	request("Reset")
end)

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
	local free = player:GetAttribute("StatPoints") or 0
	pointsLabel.Text = T.Points:format(free)
	pointsLabel.TextColor3 = if free > 0 then C.Gold else C.Muted
	local spent = PlayerData.Table("Attributes")
	for _, def in ipairs(A.List) do
		local row = rows[def.Id]
		row.value.Text = tostring(spent[def.Id] or 0)
		row.plusApi.SetActive(free > 0)
		row.plus5.TextTransparency = if free > 0 then 0 else 0.5
	end
	local all = PlayerData.Table("Stats")
	for i, def in ipairs(STAT_ROWS) do
		statLabels[i].Text = statText(all[def[1]] or 0, def[3])
	end
	resetButton.Text = if resetArmed then "Точно сбросить?" else T.Reset:format(Format.Number(A.ResetCost + A.ResetPerLevel * level))
end

PlayerData.Changed({ "Attributes", "StatPoints", "Stats", "Level", "Class" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
window.OnOpen = function()
	resetArmed = false
	refresh()
end

Status.Window = window
Status.Open = window.Open
return Status
