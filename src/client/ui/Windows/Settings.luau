--[[
	Settings.luau
	Small settings window: sound on/off, camera shake on/off.
]]

local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local Settings = {}

local window = Window.new("Настройки", Style.Colors.Blue, Vector2.new(380, 260))
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 12)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = window.Content

local function toggle(order, label, get, set)
	local button, setColor = Style.Button(window.Content, { Size = UDim2.fromOffset(300, 54), TextSize = 22, ZIndex = 34, LayoutOrder = order, Shadow = false })
	local function refresh()
		local on = get()
		button.Text = label .. ": " .. (if on then "ВКЛ" else "ВЫКЛ")
		setColor(if on then Style.Colors.Green else Style.Colors.Red)
	end
	button.Activated:Connect(function()
		set(not get())
		refresh()
	end)
	refresh()
end

toggle(1, "🔊 Звук", function()
	return not Style.Muted
end, function(on)
	Style.Muted = not on
end)
toggle(2, "📳 Тряска камеры", function()
	return Style.Shake
end, function(on)
	Style.Shake = on
end)

Settings.Window = window
Settings.Open = window.Open

function Settings.ToggleSound()
	Style.Muted = not Style.Muted
	return not Style.Muted
end

return Settings
