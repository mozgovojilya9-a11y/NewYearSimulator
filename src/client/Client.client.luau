--[[
	Client.client.luau
	Day 1: slim top bar with the local player's Aura and online count.
	Day 2: a big "punching bag" click button. Clicking asks the server
	for a hit (ClickHit); the server answers with the real amount and
	whether it was a crit, and only then do we show the floating
	"+N" popup. The client never decides how much Aura it gets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COLOR_NORMAL = Color3.fromRGB(255, 255, 255)
local COLOR_CRIT = Color3.fromRGB(255, 205, 70)
local COLOR_BUTTON = Color3.fromRGB(150, 90, 255)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AuraClickerUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

---------------------------------------------------------------------
-- Top bar
---------------------------------------------------------------------

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.Size = UDim2.new(1, 0, 0, 44)
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
bar.BackgroundTransparency = 0.15
bar.BorderSizePixel = 0
bar.Parent = screenGui

local auraLabel = Instance.new("TextLabel")
auraLabel.Name = "AuraLabel"
auraLabel.Size = UDim2.new(0.5, -12, 1, 0)
auraLabel.Position = UDim2.new(0, 12, 0, 0)
auraLabel.BackgroundTransparency = 1
auraLabel.Font = Enum.Font.GothamBold
auraLabel.TextSize = 20
auraLabel.TextColor3 = COLOR_NORMAL
auraLabel.TextXAlignment = Enum.TextXAlignment.Left
auraLabel.Text = "Аура: 0"
auraLabel.Parent = bar

local auraLabelScale = Instance.new("UIScale")
auraLabelScale.Parent = auraLabel

local onlineLabel = Instance.new("TextLabel")
onlineLabel.Name = "OnlineLabel"
onlineLabel.Size = UDim2.new(0.5, -12, 1, 0)
onlineLabel.Position = UDim2.new(0.5, 0, 0, 0)
onlineLabel.BackgroundTransparency = 1
onlineLabel.Font = Enum.Font.Gotham
onlineLabel.TextSize = 16
onlineLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
onlineLabel.TextXAlignment = Enum.TextXAlignment.Right
onlineLabel.Text = "Онлайн: 0"
onlineLabel.Parent = bar

local function updateOnline()
	onlineLabel.Text = "Онлайн: " .. #Players:GetPlayers()
end

Players.PlayerAdded:Connect(updateOnline)
Players.PlayerRemoving:Connect(updateOnline)
updateOnline()

---------------------------------------------------------------------
-- Click button ("punching bag")
---------------------------------------------------------------------

local BUTTON_SIZE = 170

local clickButton = Instance.new("TextButton")
clickButton.Name = "ClickButton"
clickButton.AnchorPoint = Vector2.new(0.5, 0.5)
clickButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
clickButton.Position = UDim2.new(0.5, 0, 0.62, 0)
clickButton.BackgroundColor3 = COLOR_BUTTON
clickButton.AutoButtonColor = false
clickButton.Font = Enum.Font.GothamBlack
clickButton.TextSize = 26
clickButton.TextColor3 = COLOR_NORMAL
clickButton.Text = "КЛИК!"
clickButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = clickButton

local stroke = Instance.new("UIStroke")
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Thickness = 4
stroke.Color = Color3.fromRGB(220, 190, 255)
stroke.Parent = clickButton

local buttonScale = Instance.new("UIScale")
buttonScale.Parent = clickButton

local clickSound = Instance.new("Sound")
clickSound.Name = "ClickSound"
clickSound.SoundId = Config.Sounds.Click
clickSound.Volume = 0.5
clickSound.Parent = SoundService

---------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function playClickSound(isCrit)
	local s = clickSound:Clone()
	s.PlaybackSpeed = if isCrit then 0.7 else 1 + (math.random() - 0.5) * 0.15
	s.Volume = if isCrit then 0.8 else 0.5
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

-- Floating "+N" that rises from a random point on the button and fades.
local function spawnPopup(amount, isCrit)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(200, 50)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if isCrit then 40 else 26
	label.TextColor3 = if isCrit then COLOR_CRIT else COLOR_NORMAL
	label.Text = if isCrit then ("КРИТ! +%d"):format(amount) else ("+%d"):format(amount)
	label.ZIndex = 5

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2
	textStroke.Color = Color3.fromRGB(30, 10, 60)
	textStroke.Parent = label

	local startX = (math.random() - 0.5) * BUTTON_SIZE * 0.8
	local startY = (math.random() - 0.5) * BUTTON_SIZE * 0.4
	local base = clickButton.Position
	label.Position = base + UDim2.fromOffset(startX, startY - BUTTON_SIZE * 0.3)
	label.Parent = screenGui

	local scale = Instance.new("UIScale")
	scale.Scale = if isCrit then 0.4 else 0.7
	scale.Parent = label
	tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)

	local rise = if isCrit then 140 else 100
	local lifetime = if isCrit then 1.1 else 0.8
	tween(label, lifetime, {
		Position = label.Position + UDim2.fromOffset(startX * 0.3, -rise),
		TextTransparency = 1,
	})
	tween(textStroke, lifetime, { Transparency = 1 })

	task.delay(lifetime, function()
		label:Destroy()
	end)
end

-- Expanding golden ring + short shake on crit.
local function critBurst()
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = clickButton.Position
	ring.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 0
	ring.Parent = screenGui

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 6
	ringStroke.Color = COLOR_CRIT
	ringStroke.Parent = ring

	tween(ring, 0.4, { Size = UDim2.fromOffset(BUTTON_SIZE * 1.9, BUTTON_SIZE * 1.9) })
	tween(ringStroke, 0.4, { Transparency = 1, Thickness = 1 })
	task.delay(0.4, function()
		ring:Destroy()
	end)

	clickButton.BackgroundColor3 = COLOR_CRIT
	tween(clickButton, 0.35, { BackgroundColor3 = COLOR_BUTTON })

	local base = UDim2.new(0.5, 0, 0.62, 0)
	task.spawn(function()
		for i = 1, 5 do
			local power = (6 - i) * 2
			clickButton.Position = base + UDim2.fromOffset(math.random(-power, power), math.random(-power, power))
			task.wait(0.025)
		end
		clickButton.Position = base
	end)
end

-- Instant tactile "squish" on press, before the server answers.
local function squish()
	buttonScale.Scale = 0.9
	tween(buttonScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
end

---------------------------------------------------------------------
-- Aura counter: smoothly counts up instead of jumping
---------------------------------------------------------------------

local leaderstats = player:WaitForChild("leaderstats")
local aura = leaderstats:WaitForChild("Aura")

local displayed = Instance.new("NumberValue")
displayed.Value = aura.Value

displayed.Changed:Connect(function(v)
	auraLabel.Text = "Аура: " .. math.floor(v + 0.5)
end)
auraLabel.Text = "Аура: " .. aura.Value

local counterTween
aura.Changed:Connect(function(newValue)
	if counterTween then
		counterTween:Cancel()
	end
	counterTween = tween(displayed, 0.25, { Value = newValue })

	auraLabelScale.Scale = 1.15
	tween(auraLabelScale, 0.2, { Scale = 1 })
end)

---------------------------------------------------------------------
-- Networking
---------------------------------------------------------------------

local clickRemote = ReplicatedStorage:WaitForChild(Config.ClickRemoteName)

-- Local throttle matches the server cooldown so we don't spam requests
-- the server would drop anyway. The server still enforces it.
local lastSent = 0

clickButton.Activated:Connect(function()
	local now = os.clock()
	if now - lastSent < Config.Click.Cooldown then
		return
	end
	lastSent = now

	squish()
	clickRemote:FireServer()
end)

-- Server confirmed a click: show what we actually got.
clickRemote.OnClientEvent:Connect(function(amount, isCrit)
	playClickSound(isCrit)
	spawnPopup(amount, isCrit)
	if isCrit then
		critBurst()
	end
end)
