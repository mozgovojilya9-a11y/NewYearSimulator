--[[
	ClickButton.luau
	Day 2: the big round "КЛИК!" button. Clicking asks the server for a
	hit (ClickHit); the server answers with the real amount and whether
	it was a crit, and only then do we show the floating "+N" popup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Ui)

local ClickButton = {}

local BUTTON_SIZE = 130
local BUTTON_POSITION = UDim2.new(0.5, 0, 1, -100) -- bottom middle: clear of mobile thumbstick/jump
local COLOR_BUTTON = Ui.Colors.Accent

local button = Instance.new("TextButton")
button.Name = "ClickButton"
button.AnchorPoint = Vector2.new(0.5, 0.5)
button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
button.Position = BUTTON_POSITION
button.BackgroundColor3 = COLOR_BUTTON
button.AutoButtonColor = false
button.Font = Enum.Font.GothamBlack
button.TextSize = 26
button.TextColor3 = Ui.Colors.Text
button.Text = "КЛИК!"
button.Parent = Ui.Gui
ClickButton.Button = button

Ui.Corner(button, UDim.new(0.5, 0))
local stroke = Ui.Stroke(button, 4, Color3.fromRGB(220, 190, 255))
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local buttonScale = Instance.new("UIScale")
buttonScale.Parent = button

-- Floating "+N" that rises from a random point on the button and fades.
local function spawnPopup(amount, isCrit)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(220, 50)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if isCrit then 38 else 26
	label.TextColor3 = if isCrit then Ui.Colors.Crit else Ui.Colors.Text
	label.Text = (if isCrit then "КРИТ! +" else "+") .. Format.Number(amount)
	label.ZIndex = 5
	local textStroke = Ui.Stroke(label, 2)

	local startX = (math.random() - 0.5) * BUTTON_SIZE * 0.8
	local startY = (math.random() - 0.5) * BUTTON_SIZE * 0.4
	label.Position = BUTTON_POSITION + UDim2.fromOffset(startX, startY - BUTTON_SIZE * 0.3)
	label.Parent = Ui.Gui

	local scale = Instance.new("UIScale")
	scale.Scale = if isCrit then 0.4 else 0.7
	scale.Parent = label
	Ui.Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)

	local rise = if isCrit then 140 else 100
	local lifetime = if isCrit then 1.1 else 0.8
	Ui.Tween(label, lifetime, {
		Position = label.Position + UDim2.fromOffset(startX * 0.3, -rise),
		TextTransparency = 1,
	})
	Ui.Tween(textStroke, lifetime, { Transparency = 1 })

	task.delay(lifetime, function()
		label:Destroy()
	end)
end

-- Expanding golden ring + short shake on crit.
local function critBurst()
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = BUTTON_POSITION
	ring.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 0
	ring.Parent = Ui.Gui
	Ui.Corner(ring, UDim.new(0.5, 0))
	local ringStroke = Ui.Stroke(ring, 6, Ui.Colors.Crit)

	Ui.Tween(ring, 0.4, { Size = UDim2.fromOffset(BUTTON_SIZE * 1.9, BUTTON_SIZE * 1.9) })
	Ui.Tween(ringStroke, 0.4, { Transparency = 1, Thickness = 1 })
	task.delay(0.4, function()
		ring:Destroy()
	end)

	button.BackgroundColor3 = Ui.Colors.Crit
	Ui.Tween(button, 0.35, { BackgroundColor3 = COLOR_BUTTON })

	task.spawn(function()
		for i = 1, 5 do
			local power = (6 - i) * 2
			button.Position = BUTTON_POSITION + UDim2.fromOffset(math.random(-power, power), math.random(-power, power))
			task.wait(0.025)
		end
		button.Position = BUTTON_POSITION
	end)
end

local clickRemote = ReplicatedStorage:WaitForChild("ClickHit")

-- Local throttle matches the server cooldown so we don't spam requests
-- the server would drop anyway. The server still enforces it.
local lastSent = 0

button.Activated:Connect(function()
	local now = os.clock()
	if now - lastSent < Config.Click.Cooldown then
		return
	end
	lastSent = now

	-- Instant tactile squish before the server answers.
	buttonScale.Scale = 0.9
	Ui.Tween(buttonScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)

	clickRemote:FireServer()
end)

-- Server confirmed a click: show what we actually got.
clickRemote.OnClientEvent:Connect(function(amount, isCrit)
	Ui.PlaySound(Config.Sounds.Click, if isCrit then 0.7 else 1 + (math.random() - 0.5) * 0.15, if isCrit then 0.8 else 0.5)
	spawnPopup(amount, isCrit)
	if isCrit then
		critBurst()
	end
end)

return ClickButton
