--[[
	Settings.luau
	Settings window: sound, music, camera shake, hide effects, hide other
	players' pets. Choices live in Style flags for this session.
	Music plays Config.Sounds.Music in a loop when an id is set there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local Settings = {}

local window = Window.new("Настройки", Style.Colors.Blue, Vector2.new(420, 420))
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

toggle(1, "🔊 Звук", function()
	return not Style.Muted
end, function(on)
	Style.Muted = not on
end)
toggle(2, "🎵 Музыка", function()
	return Style.MusicOn
end, function(on)
	Style.MusicOn = on
end)
toggle(3, "📳 Тряска камеры", function()
	return Style.Shake
end, function(on)
	Style.Shake = on
end)
toggle(4, "✨ Эффекты", function()
	return not Style.HideEffects
end, function(on)
	Style.HideEffects = not on
end)
toggle(5, "🐾 Чужие питомцы", function()
	return not Style.HideOtherPets
end, function(on)
	Style.HideOtherPets = not on
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
