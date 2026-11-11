--[[
	Window.luau
	Base for centered windows: dimmed background, rounded panel, colored
	header plate, close cross, scale 0.8 -> 1 on open. One window is
	open at a time.

		local window = Window.new("Магазин", Style.Colors.Green)
		window.Content -- Frame to fill
		window.Open() / window.Close() / window.Toggle()
]]

local Style = require(script.Parent.Parent.Style)

local Window = {}

local openWindow = nil

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

function Window.CloseAll()
	if openWindow then
		local w = openWindow
		openWindow = nil
		Style.Tween(w.Frame.Scale, 0.12, { Scale = 0.85 })
		Style.Tween(dim, 0.15, { BackgroundTransparency = 1 })
		task.delay(0.12, function()
			if openWindow ~= w then
				w.Frame.Visible = false
			end
			if not openWindow then
				dim.Visible = false
			end
		end)
	end
end
dim.Activated:Connect(Window.CloseAll)

function Window.new(title: string, color: Color3, size: Vector2?)
	local w = size or Vector2.new(520, 420)
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(w.X, w.Y)
	frame.BackgroundColor3 = Style.Colors.Panel
	frame.Visible = false
	frame.ZIndex = 31
	frame.Parent = Style.Gui
	Style.Corner(frame, UDim.new(0, 20))
	Style.Stroke(frame, 3, Style.Colors.Outline)
	local panelScale = Instance.new("UIScale")
	panelScale.Name = "Scale"
	panelScale.Parent = frame

	-- Keep the window inside small screens.
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(w.X, w.Y)
	fit.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, -18)
	header.Size = UDim2.fromOffset(math.min(w.X - 80, 320), 50)
	header.BackgroundColor3 = color
	header.ZIndex = 33
	header.Parent = frame
	Style.Corner(header, UDim.new(0, 16))
	Style.Stroke(header, 3, Style.Colors.Outline)
	Style.Gradient(header, color)
	Style.Label(header, title, 28, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 34 })

	local closeButton = Style.Button(frame, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -12),
		Size = UDim2.fromOffset(44, 44),
		Color = Style.Colors.Red,
		Text = "✕",
		TextSize = 26,
		ZIndex = 34,
		Radius = UDim.new(0.5, 0),
		Shadow = false,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(16, 44)
	content.Size = UDim2.new(1, -32, 1, -58)
	content.BackgroundTransparency = 1
	content.ZIndex = 32
	content.Parent = frame

	local window = { Frame = frame, Content = content, OnOpen = nil }

	function window.Open()
		if openWindow and openWindow ~= window then
			openWindow.Frame.Visible = false
		end
		openWindow = window
		dim.Visible = true
		Style.Tween(dim, 0.2, { BackgroundTransparency = 0.45 })
		frame.Visible = true
		panelScale.Scale = 0.8
		Style.Tween(panelScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		if window.OnOpen then
			window.OnOpen()
		end
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

-- Vertical list with its own scrolling.
function Window.List(parent)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Style.Colors.Purple
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 32
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

return Window
