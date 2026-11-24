--[[
	Status.luau
	"Статус" (sheet 02_ui_kit.png): the four attributes in rows - icon in a
	frame, "Сила (СИЛ)", the value and a gold "+"; on the right the free points in a big number and the
	reset for credits; along the bottom the main stats АТАКА / ЗАЩИТА /
	HP / КРИТ. The server does the math (Status remote, StatService).
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

local window = Window.new("Статус", nil, Vector2.new(780, 470), "user")
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

-- left: the four attribute rows (sheet 02): an icon in a frame, "Сила
-- (СИЛ)", the value and a gold "+"
local LEFT = 520
local ROW = 52
local rows = {}
for i, def in ipairs(A.List) do
	local row = Style.Panel(content, { Position = UDim2.fromOffset(0, (i - 1) * (ROW + 8)), Size = UDim2.fromOffset(LEFT, ROW), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33 })
	local box = Style.Panel(row, { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(ROW - 12, ROW - 12), Fill = C.CardDark, Border = C.GoldDim, Cut = 5, ZIndex = 34 })
	local icon = Icons.Make(box, def.Icon, 24, C.Gold, 35)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	Style.Label(row, ("%s (%s)"):format(def.Name, def.Short or ""), 16, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(ROW + 8, 0), Size = UDim2.new(1, -(ROW + 150), 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
	local value = Style.Label(row, "0", 22, C.Text, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -56, 0.5, 0), Size = UDim2.fromOffset(80, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
	local plus, plusApi = Style.IconButton(row, { Icon = "plus", Size = 36, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 36, Cut = 6 })
	plus.Activated:Connect(function()
		request("Add", def.Id, 1)
	end)
	rows[def.Id] = { value = value, plusApi = plusApi }
end

-- right: free points and the reset
local side = Style.Panel(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(1, -(LEFT + 12), 0, 4 * (ROW + 8) - 8), Fill = C.PanelDark, Border = C.Line, Cut = 10, ZIndex = 33 })
Style.Label(side, T.FreeTitle, 13, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 18), ZIndex = 34 })
local freeLabel = Style.Label(side, "0", 50, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 56), ZIndex = 34 })
local freeScale = Instance.new("UIScale")
freeScale.Parent = freeLabel
local resetButton = Style.Button(side, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(1, -36, 0, 44), Text = "", TextSize = 15, Color = C.Card, Icon = "reset", ZIndex = 34 })
local resetCost = Style.Label(side, "", 11, C.Muted, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -20, 0, 14), ZIndex = 34 })
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

-- Возвышение (after the max level, Config.Ascension): 4 lines with "+"
local AS = Config.Ascension
local ascPanel = Style.Panel(content, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -70), Size = UDim2.new(1, 0, 0, 84), Fill = C.PanelDark, Border = C.GoldDim, Cut = 8, ZIndex = 33 })
local ascTitle = Style.Label(ascPanel, AS.Texts.Title, 14, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.6, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local _ = ascTitle
local ascFree = Style.Label(ascPanel, "", 13, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), Size = UDim2.new(0.5, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
local ascLocked = Style.Label(ascPanel, "", 13, C.Muted, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 44), TextWrapped = true, ZIndex = 34 })
local ascCells = {}
for i, line in ipairs(AS.Lines) do
	local cell = Instance.new("Frame")
	cell.BackgroundTransparency = 1
	cell.Position = UDim2.new((i - 1) / #AS.Lines, 8, 0, 30)
	cell.Size = UDim2.new(1 / #AS.Lines, -16, 0, 54)
	cell.ZIndex = 34
	cell.Parent = ascPanel
	local icon = Icons.Make(cell, line.Icon, 20, C.Gold, 35)
	icon.Position = UDim2.fromOffset(0, 4)
	Style.Label(cell, line.Name, 13, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(26, 2), Size = UDim2.new(1, -70, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local value = Style.Label(cell, "0", 11, C.Muted, { Position = UDim2.fromOffset(26, 20), Size = UDim2.new(1, -70, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local plus, plusApi = Style.IconButton(cell, { Icon = "plus", Size = 34, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), ZIndex = 36, Cut = 6 })
	plus.Activated:Connect(function()
		request("Ascend", line.Id, 1)
	end)
	ascCells[line.Id] = { cell = cell, value = value, plusApi = plusApi, line = line }
end

-- bottom: the main stats
local MAIN = {
	{ "Damage", "АТАКА", "sword" }, { "Defense", "ЗАЩИТА", "shield", "pct" },
	{ "MaxHealth", "HP", "heart" }, { "CritChance", "КРИТ", "burst", "pct" },
}
local strip = Style.Panel(content, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 62), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33 })
local mainLabels = {}
for i, def in ipairs(MAIN) do
	local cell = Instance.new("Frame")
	cell.BackgroundTransparency = 1
	cell.Position = UDim2.new((i - 1) / #MAIN, 0, 0, 0)
	cell.Size = UDim2.new(1 / #MAIN, 0, 1, 0)
	cell.ZIndex = 34
	cell.Parent = strip
	local icon = Icons.Make(cell, def[3], 24, C.Muted, 35)
	icon.Position = UDim2.fromOffset(18, 19)
	Style.Label(cell, def[2], 11, C.Muted, { Position = UDim2.fromOffset(52, 10), Size = UDim2.new(1, -56, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	mainLabels[i] = Style.Label(cell, "", 20, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(52, 26), Size = UDim2.new(1, -56, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
end

local lastFree = 0
function refresh()
	local level = player:GetAttribute("Level") or 1
	local free = player:GetAttribute("StatPoints") or 0
	freeLabel.Text = tostring(free)
	freeLabel.TextColor3 = if free > 0 then C.Gold else C.Muted
	if free > lastFree then
		freeScale.Scale = 1.3
		Style.Tween(freeScale, 0.25, { Scale = 1 })
	end
	lastFree = free
	local spent = PlayerData.Table("Attributes")
	for _, def in ipairs(A.List) do
		local row = rows[def.Id]
		row.value.Text = tostring(spent[def.Id] or 0)
		row.plusApi.SetActive(free > 0)
	end
	resetButton.Text = if resetArmed then T.Sure else T.ResetShort
	resetCost.Text = T.ResetCost:format(Format.Number(A.ResetCost + A.ResetPerLevel * level))
	-- Возвышение
	local maxLevel = Config.Progression.Level.MaxLevel
	local ascFreeN = player:GetAttribute("AscensionFree") or 0
	local points = player:GetAttribute("AscensionPoints") or 0
	local open = level >= maxLevel
	ascLocked.Visible = not open
	ascLocked.Text = ("С %d уровня опыт идёт в очки возвышения (до %d)"):format(maxLevel, AS.MaxPoints)
	ascFree.Text = if open then AS.Texts.Free:format(ascFreeN) .. "   ·   " .. AS.Texts.Total:format(points, AS.MaxPoints) else ""
	local spentA = PlayerData.Table("AscensionSpent")
	for id, ui in pairs(ascCells) do
		ui.cell.Visible = open
		local n = spentA[id] or 0
		ui.value.Text = ("%d  ·  %s"):format(n, ui.line.Text)
		ui.plusApi.SetActive(ascFreeN > 0)
	end
	local all = PlayerData.Table("Stats")
	for i, def in ipairs(MAIN) do
		local v = all[def[1]] or 0
		mainLabels[i].Text = if def[4] == "pct" then tostring(math.floor(v * 1000 + 0.5) / 10) .. "%" else Format.Number(v)
	end
end

PlayerData.Changed({ "Attributes", "StatPoints", "Stats", "Level", "Class", "AscensionFree", "AscensionPoints", "AscensionSpent" }, function()
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
