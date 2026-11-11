--[[
	Rebirth.luau
	Rebirth confirmation window. It opens when the player triggers the
	altar's ProximityPrompt in the hub (prompt attribute
	Action = "RebirthAltar"). The button needs two presses ("Точно?").
	The server re-checks the requirement and does the reset.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Panels = require(script.Parent.Panels)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local rebirthRequest = ReplicatedStorage:WaitForChild("RebirthRequest")

local Rebirth = {}

local window = Panels.Create("Алтарь ребёрта")
local content = window.Content

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = content

local function textLine(order, size, color, font)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 8)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.Parent = content
	return label
end

local countLabel = textLine(1, 20, Ui.Colors.Text)
local multiplierLabel = textLine(2, 26, Ui.Colors.Crit, Enum.Font.GothamBlack)
local requirementLabel = textLine(3, 20, Ui.Colors.Aura)
local infoLabel = textLine(4, 15, Ui.Colors.Muted, Enum.Font.Gotham)
infoLabel.Text = "Сбросится: Аура, оружие, ранцы и прогресс данжа.\nОстанутся: питомцы и множитель ребёрта (навсегда)."

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
local required = Config.RebirthRequirement

local function canRebirth()
	return (player:GetAttribute("RoomReached") or 0) >= required
end

local function refresh()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local reached = player:GetAttribute("RoomReached") or 0

	countLabel.Text = "Ребёртов: " .. rebirths
	multiplierLabel.Text = ("Множитель Ауры: x%s → x%s"):format(
		tostring(Config.RebirthMultiplier(rebirths)),
		tostring(Config.RebirthMultiplier(rebirths + 1))
	)
	requirementLabel.Text = ("Условие: пройти комнату %d (сейчас %d/%d)"):format(required, reached, required)
	progressFill.Size = UDim2.fromScale(math.clamp(reached / required, 0, 1), 1)

	if confirming then
		button.Text = "Точно? Нажми ещё раз"
		button.BackgroundColor3 = Ui.Colors.Crit
	elseif canRebirth() then
		button.Text = "Сделать ребёрт"
		button.BackgroundColor3 = Ui.Colors.Good
	else
		button.Text = "Условие не выполнено"
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
local confirmToken = 0
button.Activated:Connect(function()
	if busy then
		return
	end
	if not canRebirth() then
		Ui.Toast(("Сначала пройди комнату %d"):format(required), Ui.Colors.Bad)
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

player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
player:GetAttributeChangedSignal("RoomReached"):Connect(refresh)
window.OnOpen = refresh
refresh()

function Rebirth.Open()
	if not window.Frame.Visible then
		window.Open()
	end
end

-- The altar in the hub opens this window.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt:GetAttribute("Action") == "RebirthAltar" then
		Rebirth.Open()
	end
end)

return Rebirth
