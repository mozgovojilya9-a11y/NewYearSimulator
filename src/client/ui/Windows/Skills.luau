--[[
	Skills.luau
	"ДРЕВО НАВЫКОВ" window ([K]) after the owner mockup
	(docs/design/ui_class_and_skilltree.png, bottom half):
	  top     "Сбросить (cost)" and "Очки навыков: N"
	  left    the 3 classes (current one with the level; others can be
	          viewed, changing the class happens in the Academy)
	  center  4 branches (Атака / Защита / Контроль / Выживание) of the
	          viewed class, 8 nodes each with ranks (2/3), links, the
	          capstone crown at the bottom; locked nodes show the level
	  right   the selected node: description, numbers per rank
	          (Урон 120% -> 160% -> 200%, Перезарядка 10с -> 8с -> 6с),
	          "Изучить", Q / E / R for learned actives
	Data: attributes SkillState (JSON), Class, Level, SkillPoints;
	actions: Class remote ("Learn" / "Reset" / "Equip").
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Icons = require(script.Parent.Parent.Icons)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local classRemote = ReplicatedStorage:WaitForChild("Class")

local C = Style.Colors
local SK = Config.Skills

local Skills = {}

local window = Window.new("Навыки", C.Gold, Vector2.new(1120, 540), "skills")
local content = window.Content
local Z = 33

local viewed = nil -- class id shown in the tree
local selectedNode = nil

local function state()
	local raw = player:GetAttribute("SkillState")
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw or "{}")
	return if ok and type(value) == "table" then value else {}
end

local function record(classId: string)
	local s = state()
	local r = s.Classes and s.Classes[classId]
	return if type(r) == "table" then r else { Skills = {}, Loadout = {}, Resets = 0, Spent = 0 }
end

local function rankOf(r, nodeId: string): number
	return (r.Skills or {})[nodeId] or 0
end

---------------------------------------------------------------------
-- Top bar: reset + points
---------------------------------------------------------------------

local pointsPlate = Style.Panel(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(210, 36), ZIndex = Z, Fill = C.CardDark, Transparency = 0.1, Border = C.GoldDim, Cut = 6 })
local pointsIcon = Icons.Make(pointsPlate, "star", 20, C.Gold, Z + 1)
pointsIcon.AnchorPoint = Vector2.new(0, 0.5)
pointsIcon.Position = UDim2.new(0, 10, 0.5, 0)
local pointsLabel = Style.Label(pointsPlate, "", 15, C.Text, { Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -46, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, ZIndex = Z + 1 })
local resetButton = Style.Button(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -222, 0, 0), Size = UDim2.fromOffset(250, 36), Text = "Сбросить", TextSize = 14, ZIndex = Z, Icon = "reset" })

---------------------------------------------------------------------
-- Left: classes
---------------------------------------------------------------------

local LEFT, RIGHT = 200, 290
local classButtons = {}
for order, class in ipairs(Config.Classes) do
	local b = Instance.new("TextButton")
	b.Name = class.Id
	b.Position = UDim2.fromOffset(0, 48 + (order - 1) * 78)
	b.Size = UDim2.fromOffset(LEFT, 70)
	b.BackgroundTransparency = 1
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = Z
	b.Parent = content
	local shape = Style.Chamfer(b, { Fill = C.Card, Transparency = 0.1, Border = C.Line, Cut = 8 })
	local icon = Icons.Make(b, class.Icon, 34, C.Gold, Z + 1)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	Style.Label(b, class.Name, 17, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(56, 14), Size = UDim2.new(1, -62, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 1 })
	local sub = Style.Label(b, "", 12, C.Muted, { Position = UDim2.fromOffset(56, 38), Size = UDim2.new(1, -62, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 1 })
	classButtons[class.Id] = { button = b, shape = shape, sub = sub, icon = icon }
	b.Activated:Connect(function()
		viewed = class.Id
		selectedNode = nil
		Skills.Refresh()
	end)
end
local hint = Style.Label(content, "Сменить класс можно в Академии классов", 12, C.Muted, { Position = UDim2.fromOffset(0, 48 + 3 * 78 + 6), Size = UDim2.fromOffset(LEFT, 34), TextWrapped = true, ZIndex = Z })
local _ = hint

---------------------------------------------------------------------
-- Center: 4 branches
---------------------------------------------------------------------

local treePanel = Style.Panel(content, { Position = UDim2.fromOffset(LEFT + 12, 48), Size = UDim2.new(1, -(LEFT + RIGHT + 24), 1, -48), ZIndex = Z - 1, Fill = C.PanelDark, Transparency = 0.15, Border = C.Line, Cut = 10 })
local NODE = 42
local ROW = 72
local COLW = 40
local branchUis = {} -- [branchIndex] = { header, count, column, nodes = { [position] = ui } }

local function line(parent, a: Vector2, b: Vector2, z: number)
	local d = b - a
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude, 2)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = C.Line
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

for b, branch in ipairs(SK.Branches) do
	local column = Instance.new("Frame")
	column.Name = branch.Id
	column.AnchorPoint = Vector2.new(0.5, 0)
	column.Position = UDim2.new((b - 0.5) / #SK.Branches, 0, 0, 8)
	column.Size = UDim2.new(1 / #SK.Branches, -8, 1, -16)
	column.BackgroundTransparency = 1
	column.ZIndex = Z
	column.Parent = treePanel
	local bi = Icons.Make(column, branch.Icon, 18, C.Muted, Z + 1)
	bi.AnchorPoint = Vector2.new(1, 0)
	bi.Position = UDim2.new(0.5, -40, 0, 2)
	local header = Style.Label(column, branch.Name, 15, C.Text, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 6, 0, 0), Size = UDim2.fromOffset(110, 20), ZIndex = Z + 1 })
	local count = Style.Label(column, "0/0", 12, C.Muted, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 6, 0, 20), Size = UDim2.fromOffset(110, 14), ZIndex = Z + 1 })
	if b > 1 then
		local sep = Instance.new("Frame")
		sep.Position = UDim2.new(0, -4, 0, 4)
		sep.Size = UDim2.new(0, 1, 1, -8)
		sep.BackgroundColor3 = C.Line
		sep.BorderSizePixel = 0
		sep.ZIndex = Z
		sep.Parent = column
	end
	local grid = Instance.new("Frame")
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.new(0.5, 0, 0, 44)
	grid.Size = UDim2.fromOffset(COLW * 2 + NODE, ROW * 4 + NODE + 16)
	grid.BackgroundTransparency = 1
	grid.ZIndex = Z
	grid.Parent = column
	local function center(position)
		local layout = SK.Layout[position]
		return Vector2.new(COLW + layout.Col * COLW + NODE / 2, layout.Row * ROW + NODE / 2 + (if position == 8 then 12 else 0))
	end
	local links = {}
	for position, layout in ipairs(SK.Layout) do
		local needs = layout.NeedsAny or (layout.Needs and { layout.Needs }) or {}
		for _, from in ipairs(needs) do
			links[#links + 1] = { from = from, to = position, frame = line(grid, center(from), center(position), Z) }
		end
	end
	local nodes = {}
	for position in ipairs(SK.Layout) do
		local p = center(position)
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(p.X, p.Y)
		button.Size = UDim2.fromOffset(NODE, NODE)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.ZIndex = Z + 2
		button.Parent = grid
		local shape = Style.Chamfer(button, { Fill = C.CardDark, Transparency = 0, Border = C.Line, Cut = 7, Thickness = 1.5 })
		local icon = Icons.Make(button, "lock", 26, C.Muted, Z + 3)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		local rank = Style.Label(button, "", 11, C.Text, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1), Size = UDim2.fromOffset(60, 13), ZIndex = Z + 4 })
		local crown = nil
		if position == 8 then
			crown = Icons.Make(button, "crown", 18, C.Gold, Z + 4)
			crown.AnchorPoint = Vector2.new(0.5, 1)
			crown.Position = UDim2.new(0.5, 0, 0, -2)
		end
		nodes[position] = { button = button, shape = shape, icon = icon, rank = rank, crown = crown }
		button.Activated:Connect(function()
			selectedNode = (viewed or "") .. "_" .. branch.Id .. position
			Style.PlaySound("Ui", 1, 0.35)
			Skills.Refresh()
		end)
	end
	branchUis[b] = { header = header, count = count, nodes = nodes, links = links, branch = branch }
end

---------------------------------------------------------------------
-- Right: node card
---------------------------------------------------------------------

local card = Style.Panel(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 48), Size = UDim2.new(0, RIGHT, 1, -48), ZIndex = Z, Fill = C.Card, Transparency = 0.1, Border = C.GoldDim, Cut = 10 })
local cIconFrame = Style.Panel(card, { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(60, 60), ZIndex = Z + 1, Fill = C.CardDark, Transparency = 0, Border = C.GoldDim, Cut = 8 })
local cIcon = Icons.Make(cIconFrame, "skills", 36, C.Gold, Z + 2)
cIcon.AnchorPoint = Vector2.new(0.5, 0.5)
cIcon.Position = UDim2.fromScale(0.5, 0.5)
local cName = Style.Label(card, "", 18, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(84, 14), Size = UDim2.new(1, -96, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = Z + 1 })
local cRank = Style.Label(card, "", 13, C.Muted, { Position = UDim2.fromOffset(84, 56), Size = UDim2.new(1, -96, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 1 })
local cKind = Style.Label(card, "", 12, C.Gold, { Position = UDim2.fromOffset(14, 84), Size = UDim2.new(1, -28, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 1 })
local cText = Style.Label(card, "", 14, C.Text, { Position = UDim2.fromOffset(14, 104), Size = UDim2.new(1, -28, 0, 54), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = Z + 1 })
local cLines = Style.Label(card, "", 14, C.Text, { Position = UDim2.fromOffset(14, 162), Size = UDim2.new(1, -28, 0, 120), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, RichText = true, LineHeight = 1.25, ZIndex = Z + 1 })
local cNote = Style.Label(card, "", 13, C.Muted, { Position = UDim2.fromOffset(14, 286), Size = UDim2.new(1, -28, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = Z + 1 })
local learnButton = Style.Button(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -62), Size = UDim2.new(1, -28, 0, 42), Color = C.Gold, Text = "Изучить", TextSize = 17, ZIndex = Z + 2 })
local slotRow = Instance.new("Frame")
slotRow.AnchorPoint = Vector2.new(0.5, 1)
slotRow.Position = UDim2.new(0.5, 0, 1, -12)
slotRow.Size = UDim2.new(1, -28, 0, 40)
slotRow.BackgroundTransparency = 1
slotRow.ZIndex = Z + 1
slotRow.Parent = card
local slotLayout = Instance.new("UIListLayout")
slotLayout.FillDirection = Enum.FillDirection.Horizontal
slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotLayout.Padding = UDim.new(0, 8)
slotLayout.Parent = slotRow
local slotButtons = {}
for i, slot in ipairs(SK.Slots) do
	local b, setColor = Style.Button(slotRow, { Size = UDim2.fromOffset(78, 38), Text = slot, TextSize = 16, LayoutOrder = i, ZIndex = Z + 2 })
	slotButtons[slot] = { button = b, setColor = setColor }
end

local GREEN = Color3.fromRGB(110, 220, 120)
local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

-- "Урон: 120% -> <green>160%</green> -> 200%" with the current rank bold.
local function rankLine(label: string, list, rank: number, format)
	if type(list) ~= "table" then
		return nil
	end
	local parts = {}
	for i, v in ipairs(list) do
		local text = format(v)
		if i == rank then
			text = ('<font color="%s"><b>%s</b></font>'):format(hex(GREEN), text)
		elseif i > rank then
			text = ('<font color="%s">%s</font>'):format(hex(C.Text), text)
		else
			text = ('<font color="%s">%s</font>'):format(hex(C.Muted), text)
		end
		table.insert(parts, text)
	end
	return label .. ": " .. table.concat(parts, "  →  ")
end

local function pct(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end
local function secs(v)
	return (if v == math.floor(v) then "%dс" else "%.1fс"):format(v)
end
local VALUE_NAMES = { Shield = "Снижение урона", Rage = "Бонус урона", Haste = "Скорость атаки", Heal = "Лечение" }

local function describe(node, rank: number): string
	local lines = {}
	local function add(line)
		if line then
			table.insert(lines, line)
		end
	end
	if node.Ability then
		local a = node.Ability
		add(rankLine("Урон", a.Power, rank, pct))
		add(rankLine(VALUE_NAMES[a.Kind] or "Сила", a.Value, rank, pct))
		add(rankLine("Лечение", a.Heal, rank, pct))
		add(rankLine("Длительность", a.Duration, rank, secs))
		add(rankLine("Перезарядка", a.Cooldown, rank, secs))
		if a.Radius then
			add(("Радиус: %d studs"):format(a.Radius))
		end
		if a.Targets then
			add(("Целей: %d"):format(a.Targets))
		end
	end
	for stat, list in pairs(node.Stats or {}) do
		local flat = SK.FlatStats[stat]
		add(rankLine(SK.StatNames[stat] or stat, list, rank, function(v)
			return if flat then ("+%s"):format(Format.Number(v)) else "+" .. pct(v)
		end))
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------

function Skills.Refresh()
	local s = state()
	local current = s.Class or ""
	viewed = viewed or (if current ~= "" then current else Config.Classes[1].Id)
	local class = Config.ClassById[viewed]
	local r = record(viewed)
	local level = player:GetAttribute("Level") or 1
	local free = if viewed == current then player:GetAttribute("SkillPoints") or 0 else math.max(0, SK.PointsAtLevel(level) - (r.Spent or 0))
	window.Title.Text = Style.Upper("Древо навыков — " .. class.Name)
	pointsLabel.Text = ('Очки навыков: <font color="#6EDC78"><b>%d</b></font>'):format(free)
	local resetCost = if (r.Resets or 0) == 0 then "бесплатно" else Format.Number(SK.ResetCost(level)) .. " кр."
	resetButton.Text = "Сбросить (" .. resetCost .. ")"
	resetButton.Visible = viewed == current

	for id, ui in pairs(classButtons) do
		local on = id == viewed
		ui.shape.SetBorder(if on then C.Gold else C.Line)
		ui.shape.SetFill(if on then Style.Darker(C.Gold, 0.82) else C.Card, 0.1)
		local cr = record(id)
		ui.sub.Text = if id == current then ("ур. %d"):format(level) elseif (cr.Spent or 0) > 0 then ("вложено %d"):format(cr.Spent) else "не выбран"
	end

	local nodes = Config.SkillTrees[viewed]
	for b, bu in ipairs(branchUis) do
		local spent, max = 0, 0
		for position, ui in pairs(bu.nodes) do
			local id = viewed .. "_" .. bu.branch.Id .. position
			local node = Config.SkillById[id]
			local rank = rankOf(r, id)
			spent += rank
			max += node.MaxRank
			local unlocked = level >= node.Level
			local selected = selectedNode == id
			local border = if selected then C.Text elseif rank >= node.MaxRank then C.Gold elseif rank > 0 then C.GoldDim else C.Line
			ui.shape.SetBorder(border)
			ui.shape.SetFill(if rank > 0 then Style.Darker(class.Color, 0.7) else C.CardDark, 0)
			Icons.Set(ui.icon, if unlocked then node.Icon else "lock", if rank > 0 then C.Text elseif unlocked then C.Muted else C.Line)
			ui.rank.Text = if unlocked then ("%d/%d"):format(rank, node.MaxRank) else ("ур. %d"):format(node.Level)
			ui.rank.TextColor3 = if rank > 0 then C.Text else C.Muted
		end
		for _, link in ipairs(bu.links) do
			local id = viewed .. "_" .. bu.branch.Id .. link.from
			link.frame.BackgroundColor3 = if rankOf(r, id) > 0 then class.Color else C.Line
		end
		bu.header.Text = SK.Branches[b].Name
		bu.count.Text = ("%d/%d"):format(spent, max)
		local _ = nodes
	end

	-- node card
	local node = Config.SkillById[selectedNode or ""]
	if not node then
		node = Config.SkillById[viewed .. "_A1"]
		selectedNode = node.Id
	end
	local rank = rankOf(r, node.Id)
	Icons.Set(cIcon, node.Icon, class.Color)
	cName.Text = node.Name
	cRank.Text = ("Уровень: %d / %d"):format(rank, node.MaxRank)
	cKind.Text = Style.Upper(if node.Kind == "Capstone" then "Капстоун ветки" elseif node.Active then "Активный приём · Q / E / R" else "Пассивный навык")
	cText.Text = node.Text or ""
	cLines.Text = describe(node, math.max(rank, 1))
	local canLearn = viewed == current and rank < node.MaxRank and level >= node.Level and free > 0
	if rank >= node.MaxRank then
		cNote.Text = "Максимальный уровень"
		cNote.TextColor3 = GREEN
	elseif level < node.Level then
		cNote.Text = ("Откроется на %d уровне"):format(node.Level)
		cNote.TextColor3 = C.Muted
	elseif viewed ~= current then
		cNote.Text = "Это дерево другого класса"
		cNote.TextColor3 = C.Muted
	else
		cNote.Text = if free > 0 then "Стоит 1 очко навыка" else "Нет свободных очков: получи уровень"
		cNote.TextColor3 = C.Muted
	end
	learnButton.Visible = viewed == current and rank < node.MaxRank
	learnButton.Text = if canLearn then "Изучить" else "Недоступно"
	local loadout = r.Loadout or {}
	slotRow.Visible = node.Active and rank > 0 and viewed == current
	for slot, ui in pairs(slotButtons) do
		ui.setColor(if loadout[slot] == node.Id then C.Gold else C.Card)
	end
end

learnButton.Activated:Connect(function()
	if not selectedNode then
		return
	end
	local ok, message = classRemote:InvokeServer("Learn", selectedNode)
	if ok then
		Style.PlaySound("Forged", 1.4, 0.4)
	end
	Popups.Toast(message or "", if ok then "gold" else "bad")
	task.wait(0.15)
	Skills.Refresh()
end)
for slot, ui in pairs(slotButtons) do
	ui.button.Activated:Connect(function()
		local r = record(player:GetAttribute("Class") or "")
		local current = (r.Loadout or {})[slot]
		local ok, message = classRemote:InvokeServer("Equip", slot, if current == selectedNode then nil else selectedNode)
		if not ok and message then
			Popups.Toast(message, "bad")
		end
		task.wait(0.15)
		Skills.Refresh()
	end)
end
resetButton.Activated:Connect(function()
	local ok, message = classRemote:InvokeServer("Reset")
	Popups.Toast(message or "", if ok then "gold" else "bad")
	task.wait(0.15)
	Skills.Refresh()
end)

for _, attribute in ipairs({ "SkillState", "SkillPoints", "Level", "Class" }) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if window.IsOpen() then
			Skills.Refresh()
		end
	end)
end

window.OnOpen = function()
	viewed = player:GetAttribute("Class") or ""
	if viewed == "" then
		viewed = Config.Classes[1].Id
	end
	Skills.Refresh()
end

Skills.Window = window
Skills.Open = window.Open
Skills.Toggle = window.Toggle
return Skills
