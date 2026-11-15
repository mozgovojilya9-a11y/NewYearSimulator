--[[
	Window.luau
	Base for centered windows in the reference style: dark cut-corner
	panel with a thin gold border, a gold icon plate and the title in the
	header, a gold rule under it, the close cross in a square frame,
	underlined tabs. One window is open at a time.

		local window = Window.new("Магазин", accent, Vector2.new(720, 500), "gem")
		window.Content -- Frame to fill (below the header)
		window.Open() / window.Close() / window.Toggle()

	Window.Group({ { Window = a, Text = "Снаряжение" }, { Window = b, Text = "Материалы" } })
	puts header tabs on every window of the group that switch between them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Parent.Icons)
local Style = require(script.Parent.Parent.Style)

local C = Style.Colors
local U = Config.Ui

local Window = {}

local HEADER = 58 -- header height inside the panel
local TITLE_ICONS = {
	["Магазин"] = "gem",
	["Награды"] = "trophy",
	["Задания"] = "quest",
	["Кузница"] = "hammer",
	["Фабрикатор"] = "hammer",
	["Инвентарь"] = "bag",
	["Снаряжение"] = "shield",
	["Материалы"] = "bag",
	["Настройки"] = "gear",
	["Итоги забега"] = "trophy",
	["Навыки"] = "skills",
	["Врата"] = "gate",
}

local openWindow = nil
Window.OnChanged = nil -- (window | nil) called when the open window changes (HUD highlights)

local dim = Instance.new("TextButton") -- a button so clicks outside close the window
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1.2, 1.2)
dim.Position = UDim2.fromScale(-0.1, -0.1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = 30
dim.Visible = false
dim.Parent = Style.Gui

local function changed()
	if Window.OnChanged then
		Window.OnChanged(openWindow)
	end
end

function Window.CloseAll()
	if openWindow then
		local w = openWindow
		openWindow = nil
		Style.Tween(w.Frame.Scale, 0.1, { Scale = 0.94 })
		Style.Tween(dim, 0.15, { BackgroundTransparency = 1 })
		task.delay(0.1, function()
			if openWindow ~= w then
				w.Frame.Visible = false
			end
			if not openWindow then
				dim.Visible = false
			end
		end)
		changed()
	end
end
dim.Activated:Connect(Window.CloseAll)

-- True while any window is open (world clicks are ignored then).
function Window.AnyOpen(): boolean
	return openWindow ~= nil
end

function Window.Current()
	return openWindow
end

function Window.new(title: string, _accent: Color3?, size: Vector2?, icon: string?)
	local inner = size or Vector2.new(520, 420)
	local w = Vector2.new(inner.X, inner.Y + 22) -- the header lives inside the panel now
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.52)
	frame.Size = UDim2.fromOffset(w.X, w.Y)
	frame.Visible = false
	frame.ZIndex = 31
	frame.Parent = Style.Gui
	Style.Chamfer(frame, { Fill = C.Panel, Transparency = U.WindowTransparency, Border = C.GoldDim, Cut = 14 })
	local panelScale = Instance.new("UIScale")
	panelScale.Name = "Scale"
	panelScale.Parent = frame

	-- Keep the window inside small screens.
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(w.X, w.Y)
	fit.Parent = frame

	-- header: gold icon plate + title + rule
	local plate = Instance.new("Frame")
	plate.Name = "IconPlate"
	plate.Position = UDim2.fromOffset(16, 13)
	plate.Size = UDim2.fromOffset(34, 34)
	plate.ZIndex = 33
	plate.Parent = frame
	Style.Chamfer(plate, { Fill = C.Gold, Transparency = 0, Border = Color3.fromRGB(255, 226, 140), Cut = 7, Thickness = 1 })
	local plateIcon = Icons.Make(plate, icon or TITLE_ICONS[title] or "star", 22, Color3.fromRGB(28, 22, 10), 35)
	plateIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	plateIcon.Position = UDim2.fromScale(0.5, 0.5)
	local titleLabel = Style.Label(frame, Style.Upper(title), 21, C.Gold, {
		Name = "Title",
		Font = Style.FontTitle,
		Position = UDim2.fromOffset(62, 13),
		Size = UDim2.new(0.5, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 34,
	})
	Style.Rule(frame, { Position = UDim2.fromOffset(12, HEADER), Size = UDim2.new(1, -24, 0, 1), ZIndex = 33 })

	local closeButton = Style.IconButton(frame, {
		Name = "Close",
		Icon = "close",
		Size = 34,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 13),
		ZIndex = 34,
		Cut = 6,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(16, HEADER + 12)
	content.Size = UDim2.new(1, -32, 1, -(HEADER + 24))
	content.BackgroundTransparency = 1
	content.ZIndex = 32
	content.Parent = frame

	local window = { Frame = frame, Content = content, OnOpen = nil, Title = titleLabel }

	function window.Open()
		if openWindow and openWindow ~= window then
			openWindow.Frame.Visible = false
		end
		openWindow = window
		dim.Visible = true
		Style.Tween(dim, 0.2, { BackgroundTransparency = 0.5 })
		frame.Visible = true
		panelScale.Scale = 0.94
		Style.Tween(panelScale, 0.16, { Scale = 1 })
		if window.OnOpen then
			window.OnOpen()
		end
		if window.OnGroupOpen then
			window.OnGroupOpen()
		end
		changed()
	end

	function window.Close()
		if openWindow == window then
			Window.CloseAll()
		end
	end

	function window.Toggle()
		if openWindow == window then
			Window.CloseAll()
		else
			window.Open()
		end
	end

	function window.IsOpen()
		return openWindow == window
	end

	closeButton.Activated:Connect(window.Close)
	return window
end

-- Header tabs shared by several windows (they open each other).
function Window.Group(entries)
	for _, entry in ipairs(entries) do
		local frame = entry.Window.Frame
		local bar = Instance.new("Frame")
		bar.Name = "GroupTabs"
		bar.AnchorPoint = Vector2.new(1, 0)
		bar.Position = UDim2.new(1, -60, 0, 14)
		bar.Size = UDim2.new(0.55, 0, 0, 34)
		bar.BackgroundTransparency = 1
		bar.ZIndex = 34
		bar.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = bar
		local labels = {}
		for order, other in ipairs(entries) do
			local tab = Instance.new("TextButton")
			tab.LayoutOrder = order
			tab.Size = UDim2.fromOffset(120, 34)
			tab.BackgroundTransparency = 1
			tab.Font = Style.Font
			tab.TextSize = 15
			tab.Text = Style.Upper(other.Text)
			tab.TextColor3 = if other.Window == entry.Window then C.Gold else C.Muted
			tab.ZIndex = 35
			tab.Parent = bar
			local underline = Instance.new("Frame")
			underline.AnchorPoint = Vector2.new(0.5, 1)
			underline.Position = UDim2.new(0.5, 0, 1, 0)
			underline.Size = UDim2.new(0.8, 0, 0, 2)
			underline.BackgroundColor3 = C.Gold
			underline.BorderSizePixel = 0
			underline.Visible = other.Window == entry.Window
			underline.ZIndex = 35
			underline.Parent = tab
			labels[order] = tab
			tab.Activated:Connect(function()
				if other.Window ~= entry.Window then
					other.Window.Open()
				end
			end)
		end
		-- the group's title shows the group name of the first entry
		entry.Window.Title.Size = UDim2.new(0.35, 0, 0, 34)
	end
end

-- Vertical list with its own scrolling.
function Window.List(parent)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = C.GoldDim
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 32
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

-- Scrolling grid of fixed-size cells.
function Window.Grid(parent, cellSize: UDim2, padding: number?)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = C.GoldDim
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 32
	list.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cellSize
	layout.CellPadding = UDim2.fromOffset(padding or 8, padding or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.Parent = list
	return list
end

-- Row of underlined tabs at the top of `parent`. defs = { { Id, Text } }.
-- Returns a table with .Changed (callback, set by the caller) and a
-- function select(id) that highlights the tab and calls .Changed(id).
function Window.Tabs(parent, defs, _accent: Color3?, width: number?)
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.Size = UDim2.new(1, 0, 0, 40)
	bar.BackgroundTransparency = 1
	bar.ZIndex = 33
	bar.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	Style.Rule(bar, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), Color = C.Line, ZIndex = 33 })

	local tabs = { Changed = nil, Bar = bar, Current = nil }
	local looks = {}
	local function select(id)
		tabs.Current = id
		for tabId, look in pairs(looks) do
			look(tabId == id)
		end
		if tabs.Changed then
			tabs.Changed(id)
		end
	end
	for order, def in ipairs(defs) do
		local tab = Instance.new("TextButton")
		tab.LayoutOrder = order
		tab.Size = UDim2.fromOffset(width or 130, 38)
		tab.BackgroundColor3 = C.Card
		tab.BackgroundTransparency = 1
		tab.Font = Style.Font
		tab.TextSize = 15
		tab.Text = Style.Upper(def.Text)
		tab.TextColor3 = C.Muted
		tab.AutoButtonColor = false
		tab.ZIndex = 34
		tab.Parent = bar
		local underline = Instance.new("Frame")
		underline.AnchorPoint = Vector2.new(0.5, 1)
		underline.Position = UDim2.new(0.5, 0, 1, 0)
		underline.Size = UDim2.new(1, -8, 0, 2)
		underline.BackgroundColor3 = C.Gold
		underline.BorderSizePixel = 0
		underline.Visible = false
		underline.ZIndex = 35
		underline.Parent = tab
		looks[def.Id] = function(active)
			tab.TextColor3 = if active then C.Gold else C.Muted
			tab.BackgroundTransparency = if active then 0.6 else 1
			underline.Visible = active
		end
		tab.Activated:Connect(function()
			Style.PlaySound("Ui", 1, 0.35)
			select(def.Id)
		end)
	end
	return tabs, select
end

return Window
