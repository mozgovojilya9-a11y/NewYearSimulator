--[[
	Settings.luau
	Settings window: sound, music, camera shake, hide effects, hide other
	Choices live in Style flags for this session.
	Music plays Config.Sounds.Music in a loop when an id is set there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local Settings = {}

local window = Window.new("Настройки", Style.Colors.Blue, Vector2.new(420, 520))
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = window.Content

-- Background music (only when an uploaded id is configured).
local music
local function refreshMusic()
	local id = Config.Sounds.Music
	if not id or id == "" then
		return
	end
	if not music then
		music = Instance.new("Sound")
		music.Name = "Music"
		music.SoundId = id
		music.Looped = true
		music.Volume = 0.25
		music.Parent = SoundService
	end
	if Style.MusicOn and not Style.Muted then
		if not music.IsPlaying then
			music:Play()
		end
	else
		music:Stop()
	end
end

local toggles = {}
local function toggle(order, label, get, set)
	local button, setColor = Style.Button(window.Content, { Size = UDim2.fromOffset(330, 52), TextSize = 21, ZIndex = 34, LayoutOrder = order, Shadow = false })
	local function refresh()
		local on = get()
		button.Text = label .. ": " .. (if on then "ВКЛ" else "ВЫКЛ")
		setColor(if on then Style.Colors.Green else Style.Colors.Red)
	end
	button.Activated:Connect(function()
		set(not get())
		refresh()
		refreshMusic()
	end)
	refresh()
	table.insert(toggles, refresh)
end

toggle(1, "Звук", function()
	return not Style.Muted
end, function(on)
	Style.Muted = not on
end)
toggle(2, "Музыка", function()
	return Style.MusicOn
end, function(on)
	Style.MusicOn = on
end)
toggle(3, "Тряска камеры", function()
	return Style.Shake
end, function(on)
	Style.Shake = on
end)
toggle(4, "Эффекты", function()
	return not Style.HideEffects
end, function(on)
	Style.HideEffects = not on
end)

-- Promo codes (Config.Codes, checked by the server).
local CT = Config.Codes.Texts
local codeRow = Instance.new("Frame")
codeRow.Size = UDim2.fromOffset(330, 90)
codeRow.BackgroundTransparency = 1
codeRow.LayoutOrder = 10
codeRow.ZIndex = 34
codeRow.Parent = window.Content
Style.Label(codeRow, "ПРОМОКОД", 14, Style.Colors.Gold, { Font = Style.FontTitle, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local box = Instance.new("TextBox")
box.Position = UDim2.fromOffset(0, 24)
box.Size = UDim2.new(1, -150, 0, 44)
box.BackgroundColor3 = Style.Colors.PanelDark
box.BorderSizePixel = 0
box.Font = Style.FontTitle
box.TextSize = 18
box.TextColor3 = Style.Colors.Text
box.PlaceholderText = CT.Placeholder
box.PlaceholderColor3 = Style.Colors.Muted
box.Text = ""
box.ClearTextOnFocus = false
box.ZIndex = 35
box.Parent = codeRow
Style.Stroke(box, 1.5, Style.Colors.Line)
local redeem = Style.Button(codeRow, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.fromOffset(140, 44), Color = Style.Colors.Gold, Text = CT.Redeem, TextSize = 15, ZIndex = 35 })
local engage = ReplicatedStorage:WaitForChild("Engage")
redeem.Activated:Connect(function()
	local text = box.Text
	if text == "" then
		return
	end
	task.spawn(function()
		local ok, message = engage:InvokeServer("Code", text)
		require(script.Parent.Parent.Popups).Toast(message or "", if ok then "gold" else "bad")
		if ok then
			box.Text = ""
		end
	end)
end)

refreshMusic()

Settings.Window = window
Settings.Open = function()
	for _, refresh in ipairs(toggles) do
		refresh()
	end
	window.Open()
end

-- Top-right sound button.
function Settings.ToggleSound()
	Style.Muted = not Style.Muted
	refreshMusic()
	return not Style.Muted
end

return Settings
