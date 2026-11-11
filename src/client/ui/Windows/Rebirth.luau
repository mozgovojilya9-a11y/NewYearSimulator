--[[
	Rebirth.luau
	Rebirth confirmation window. Opened from the altar prompt or the
	menu button. Two presses ("Точно?") protect against misclicks; the
	server re-checks the requirement and does the reset.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local rebirthRequest = ReplicatedStorage:WaitForChild("RebirthRequest")

local Rebirth = {}

local window = Window.new("Перерождение", Style.Colors.Purple, Vector2.new(480, 400))
local content = window.Content
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = content

local function line(order, size, color)
	local label = Style.Label(content, "", size, color, { LayoutOrder = order, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 33 })
	if color == Style.Colors.Outline then
		label:FindFirstChildOfClass("UIStroke").Transparency = 1
	end
	return label
end

local countLabel = line(1, 22, Style.Colors.Outline)
local multiplierLabel = line(2, 30, Style.Colors.Gold)
local requirementLabel = line(3, 20, Style.Colors.Purple)
local infoLabel = line(4, 16, Style.Colors.Outline)
infoLabel.Text = "Сбросится: Аура, оружие, рюкзаки и прогресс данжа.\nОстанутся: питомцы и множитель перерождения (навсегда)."

local progress = Instance.new("Frame")
progress.LayoutOrder = 5
progress.Size = UDim2.fromOffset(300, 18)
progress.BackgroundColor3 = Style.Lighter(Style.Colors.Purple, 0.75)
progress.ZIndex = 33
progress.Parent = content
Style.Corner(progress, UDim.new(0.5, 0))
Style.Stroke(progress, 2)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Style.Colors.Purple
fill.ZIndex = 34
fill.Parent = progress
Style.Corner(fill, UDim.new(0.5, 0))

local button, setColor = Style.Button(content, { Size = UDim2.fromOffset(300, 58), Color = Style.Colors.Green, TextSize = 24, ZIndex = 34, LayoutOrder = 6, Shadow = false })

local required = Config.RebirthRequirement
local confirming = false
local confirmToken = 0

function Rebirth.CanRebirth(): boolean
	return (player:GetAttribute("RoomReached") or 0) >= required
end

local function refresh()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local reached = player:GetAttribute("RoomReached") or 0
	countLabel.Text = "Перерождений: " .. rebirths
	multiplierLabel.Text = ("Множитель Ауры: x%s → x%s"):format(tostring(Config.RebirthMultiplier(rebirths)), tostring(Config.RebirthMultiplier(rebirths + 1)))
	requirementLabel.Text = ("Условие: пройти этап %d (сейчас %d/%d)"):format(required, reached, required)
	fill.Size = UDim2.fromScale(math.clamp(reached / required, 0, 1), 1)
	if confirming then
		button.Text = "Точно? Нажми ещё раз"
		setColor(Style.Colors.Gold)
	elseif Rebirth.CanRebirth() then
		button.Text = "Переродиться"
		setColor(Style.Colors.Green)
	else
		button.Text = "Условие не выполнено"
		setColor(Style.Colors.Red)
	end
end

local busy = false
button.Activated:Connect(function()
	if busy then
		return
	end
	if not Rebirth.CanRebirth() then
		Popups.Toast(("Сначала пройди этап %d"):format(required), "bad")
		return
	end
	if not confirming then
		confirming = true
		confirmToken += 1
		local token = confirmToken
		refresh()
		task.delay(3, function()
			if token == confirmToken then
				confirming = false
				refresh()
			end
		end)
		return
	end
	confirming = false
	busy = true
	local ok, message = rebirthRequest:InvokeServer()
	busy = false
	Popups.Toast(message or "", if ok then "gold" else "bad")
	if ok then
		Popups.Fade(Style.Colors.Purple, 0.5)
		Popups.Shake(Config.Hud.ShakeBoss.Amplitude, Config.Hud.ShakeBoss.Seconds)
		Style.PlaySound(Config.Sounds.Rebirth, 0.5, 0.9)
		task.delay(0.15, Style.PlaySound, Config.Sounds.Rebirth, 0.75, 0.9)
		task.delay(0.3, Style.PlaySound, Config.Sounds.Rebirth, 1, 0.9)
		window.Close()
	end
	refresh()
end)

player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
player:GetAttributeChangedSignal("RoomReached"):Connect(refresh)
window.OnOpen = refresh
refresh()

Rebirth.Window = window
Rebirth.Open = window.Open
return Rebirth
