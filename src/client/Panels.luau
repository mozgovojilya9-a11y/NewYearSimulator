--[[
	Panels.luau
	Left-side menu buttons and centered windows. Only one window is open
	at a time. Shop, Pets and Rebirth all build on this.

		local window = Panels.Create("Магазин")
		Panels.AddMenuButton("🛒", "Магазин", color, window)
		window.Content -- Frame to fill
]]

local Ui = require(script.Parent.Ui)

local Panels = {}

local openWindow = nil

local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.AnchorPoint = Vector2.new(0, 0.5)
menu.Position = UDim2.new(0, 12, 0.5, 0)
menu.Size = UDim2.fromOffset(84, 400)
menu.BackgroundTransparency = 1
menu.Parent = Ui.Gui
local menuLayout = Instance.new("UIListLayout")
menuLayout.Padding = UDim.new(0, 10)
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
menuLayout.Parent = menu

local function close()
	if openWindow then
		openWindow.Frame.Visible = false
		openWindow = nil
	end
end
Panels.Close = close

function Panels.Create(title: string)
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(480, 400)
	frame.BackgroundColor3 = Ui.Colors.Panel
	frame.Visible = false
	frame.ZIndex = 10
	frame.Parent = Ui.Gui
	Ui.Corner(frame, UDim.new(0, 16))
	Ui.Stroke(frame, 3, Ui.Colors.Accent)

	-- Shrink on small (phone) screens.
	local fit = Instance.new("UIScale")
	fit.Parent = frame
	local function refit()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1024, 768)
		fit.Scale = math.min(1, (viewport.X - 24) / 480, (viewport.Y - 100) / 400)
	end
	refit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)

	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.Size = UDim2.new(1, -60, 0, 48)
	header.Position = UDim2.fromOffset(18, 0)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 24
	header.TextColor3 = Ui.Colors.Text
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = title
	header.ZIndex = 11
	header.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 8)
	closeButton.Size = UDim2.fromOffset(34, 34)
	closeButton.BackgroundColor3 = Ui.Colors.Bad
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.TextSize = 18
	closeButton.TextColor3 = Ui.Colors.Text
	closeButton.Text = "X"
	closeButton.ZIndex = 11
	closeButton.Parent = frame
	Ui.Corner(closeButton, UDim.new(0.5, 0))
	closeButton.Activated:Connect(close)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(12, 52)
	content.Size = UDim2.new(1, -24, 1, -64)
	content.BackgroundTransparency = 1
	content.ZIndex = 11
	content.Parent = frame

	local window = { Frame = frame, Content = content, OnOpen = nil }

	function window.Open()
		if openWindow == window then
			close()
			return
		end
		close()
		openWindow = window
		frame.Visible = true
		refit()
		local target = fit.Scale
		fit.Scale = target * 0.85
		Ui.Tween(fit, 0.18, { Scale = target }, Enum.EasingStyle.Back)
		if window.OnOpen then
			window.OnOpen()
		end
	end

	return window
end

local menuOrder = 0
function Panels.AddMenuButton(icon: string, label: string, color: Color3, target)
	menuOrder += 1

	local button = Instance.new("TextButton")
	button.Name = label
	button.LayoutOrder = menuOrder
	button.Size = UDim2.fromOffset(84, 70)
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = menu
	Ui.Corner(button, UDim.new(0, 14))
	Ui.Stroke(button, 2)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0.6, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextSize = 28
	iconLabel.Text = icon
	iconLabel.Parent = button

	local textLabel = Instance.new("TextLabel")
	textLabel.Position = UDim2.fromScale(0, 0.58)
	textLabel.Size = UDim2.new(1, 0, 0.35, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 13
	textLabel.TextColor3 = Ui.Colors.Text
	textLabel.Text = label
	textLabel.Parent = button
	Ui.Stroke(textLabel, 1.5)

	-- target: a window from Panels.Create, or a plain function.
	if type(target) == "function" then
		button.Activated:Connect(target)
	else
		button.Activated:Connect(target.Open)
	end
	return button
end

return Panels
