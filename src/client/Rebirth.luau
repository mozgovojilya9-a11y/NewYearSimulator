--[[
	Rebirth.luau
	Day 6: rebirth window. Shows cost, current/next multiplier and what
	gets reset. The button needs two presses ("Точно?") so nobody resets
	by accident. The server does the actual rebirth.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Panels = require(script.Parent.Panels)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local rebirthRequest = ReplicatedStorage:WaitForChild("RebirthRequest")
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local Rebirth = {}

local window = Panels.Create("Ребёрт")
local content = window.Content

local function textLine(order, size, color, font)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 8)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Parent = content
	return label
end

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = content

local countLabel = textLine(1, 20, Ui.Colors.Text)
local multiplierLabel = textLine(2, 26, Ui.Colors.Crit, Enum.Font.GothamBlack)
local costLabel = textLine(3, 20, Ui.Colors.Aura)
local infoLabel = textLine(4, 15, Ui.Colors.Muted, Enum.Font.Gotham)
infoLabel.Text = "Сбросится: Аура, оружие и ранцы.\nОстанутся: 💎, питомцы и множитель ребёрта (навсегда)."

local button = Instance.new("TextButton")
button.LayoutOrder = 5
button.Size = UDim2.fromOffset(260, 56)
button.Font = Enum.Font.GothamBlack
button.TextSize = 22
button.TextColor3 = Ui.Colors.Text
button.Parent = content
Ui.Corner(button, UDim.new(0, 14))
Ui.Stroke(button, 2)

local progress = Instance.new("Frame")
progress.LayoutOrder = 6
progress.Size = UDim2.fromOffset(260, 12)
progress.BackgroundColor3 = Ui.Colors.PanelLight
progress.Parent = content
Ui.Corner(progress, UDim.new(0.5, 0))
local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = Ui.Colors.Accent
progressFill.Parent = progress
Ui.Corner(progressFill, UDim.new(0.5, 0))

local confirming = false

local function refresh()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local cost = Config.RebirthCost(rebirths)
	local affordable = aura.Value >= cost

	countLabel.Text = "Ребёртов: " .. rebirths
	multiplierLabel.Text = ("Множитель: x%s → x%s"):format(
		tostring(Config.RebirthMultiplier(rebirths)),
		tostring(Config.RebirthMultiplier(rebirths + 1))
	)
	costLabel.Text = "Цена: " .. Format.Number(cost) .. " ✨"
	progressFill.Size = UDim2.fromScale(math.clamp(aura.Value / cost, 0, 1), 1)

	if confirming then
		button.Text = "Точно? Нажми ещё раз"
		button.BackgroundColor3 = Ui.Colors.Crit
	elseif affordable then
		button.Text = "Сделать ребёрт"
		button.BackgroundColor3 = Ui.Colors.Good
	else
		button.Text = "Не хватает Ауры"
		button.BackgroundColor3 = Color3.fromRGB(120, 60, 70)
	end
end

-- Full-screen purple flash for the player who rebirthed.
local function flash()
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
	overlay.BackgroundTransparency = 0.1
	overlay.ZIndex = 50
	overlay.Parent = Ui.Gui
	Ui.Tween(overlay, 1.2, { BackgroundTransparency = 1 })
	task.delay(1.2, function()
		overlay:Destroy()
	end)
end

local busy = false
button.Activated:Connect(function()
	if busy then
		return
	end
	local cost = Config.RebirthCost(player:GetAttribute("Rebirths") or 0)
	if aura.Value < cost then
		Ui.Toast("Нужно " .. Format.Number(cost) .. " Ауры", Ui.Colors.Bad)
		return
	end

	if not confirming then
		confirming = true
		refresh()
		task.delay(3, function()
			confirming = false
			refresh()
		end)
		return
	end

	confirming = false
	busy = true
	local ok, message = rebirthRequest:InvokeServer()
	busy = false
	Ui.Toast(message or "", if ok then Ui.Colors.Crit else Ui.Colors.Bad)
	if ok then
		flash()
		Ui.PlaySound(Config.Sounds.Rebirth, 0.5, 0.9)
		task.delay(0.15, Ui.PlaySound, Config.Sounds.Rebirth, 0.75, 0.9)
		task.delay(0.3, Ui.PlaySound, Config.Sounds.Rebirth, 1, 0.9)
		Panels.Close()
	end
	refresh()
end)

-- One-time hint when a rebirth becomes affordable.
local notified = false
aura.Changed:Connect(function()
	if window.Frame.Visible then
		refresh()
	end
	local cost = Config.RebirthCost(player:GetAttribute("Rebirths") or 0)
	if not notified and aura.Value >= cost then
		notified = true
		Ui.Toast("🔁 Доступен ребёрт! Открой меню «Ребёрт»", Ui.Colors.Crit)
	end
end)
player:GetAttributeChangedSignal("Rebirths"):Connect(function()
	notified = false
	refresh()
end)
window.OnOpen = refresh
refresh()

Panels.AddMenuButton("🔁", "Ребёрт", Color3.fromRGB(150, 80, 220), window)

return Rebirth
