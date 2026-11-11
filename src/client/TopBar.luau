--[[
	TopBar.luau
	Slim bar at the top: Aura (smoothly counts up), Gems and online
	count. Reads leaderstats.Aura and the "Gems" player attribute, so it
	stays correct whatever system changes them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local TopBar = {}

local bar = Instance.new("Frame")
bar.Name = "TopBar"
bar.Size = UDim2.new(1, 0, 0, 44)
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
bar.BackgroundTransparency = 0.15
bar.BorderSizePixel = 0
bar.Parent = Ui.Gui
TopBar.Frame = bar

local function makeLabel(name, xScale, xOffset, width, align, font, size, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(width, -12, 1, 0)
	label.Position = UDim2.new(xScale, xOffset, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = align
	label.Parent = bar
	return label
end

local auraLabel = makeLabel("AuraLabel", 0, 12, 0.4, Enum.TextXAlignment.Left, Enum.Font.GothamBold, 20, Ui.Colors.Text)
local gemsLabel = makeLabel("GemsLabel", 0.4, 0, 0.25, Enum.TextXAlignment.Left, Enum.Font.GothamBold, 18, Ui.Colors.Gems)
local onlineLabel = makeLabel("OnlineLabel", 0.65, 0, 0.35, Enum.TextXAlignment.Right, Enum.Font.Gotham, 16, Ui.Colors.Muted)

local auraScale = Instance.new("UIScale")
auraScale.Parent = auraLabel
local gemsScale = Instance.new("UIScale")
gemsScale.Parent = gemsLabel

-- Online
local function updateOnline()
	onlineLabel.Text = "Онлайн: " .. #Players:GetPlayers()
end
Players.PlayerAdded:Connect(updateOnline)
Players.PlayerRemoving:Connect(updateOnline)
updateOnline()

-- Gems
local function updateGems()
	gemsLabel.Text = "💎 " .. Format.Number(player:GetAttribute("Gems") or 0)
end
player:GetAttributeChangedSignal("Gems"):Connect(function()
	updateGems()
	gemsScale.Scale = 1.25
	Ui.Tween(gemsScale, 0.25, { Scale = 1 })
end)
updateGems()

-- Stats line under the bar: damage, passive income, multiplier.
local statsLabel = Instance.new("TextLabel")
statsLabel.Name = "Stats"
statsLabel.AnchorPoint = Vector2.new(0.5, 0)
statsLabel.Position = UDim2.new(0.5, 0, 0, 48)
statsLabel.AutomaticSize = Enum.AutomaticSize.X
statsLabel.Size = UDim2.fromOffset(0, 26)
statsLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
statsLabel.BackgroundTransparency = 0.3
statsLabel.Font = Enum.Font.GothamBold
statsLabel.TextSize = 15
statsLabel.TextColor3 = Ui.Colors.Muted
statsLabel.Parent = Ui.Gui
Ui.Corner(statsLabel, UDim.new(0, 8))
local statsPadding = Instance.new("UIPadding")
statsPadding.PaddingLeft = UDim.new(0, 12)
statsPadding.PaddingRight = UDim.new(0, 12)
statsPadding.Parent = statsLabel

local function updateStats()
	local parts = {
		"⚔ Урон: " .. Format.Number(player:GetAttribute("ClickPower") or 1),
	}
	local perSecond = player:GetAttribute("AuraPerSecond") or 0
	if perSecond > 0 then
		table.insert(parts, "🎒 +" .. Format.Number(perSecond) .. "/сек")
	end
	local multiplier = player:GetAttribute("AuraMultiplier") or 1
	table.insert(parts, "✖ Аура x" .. (math.floor(multiplier * 100 + 0.5) / 100))
	statsLabel.Text = table.concat(parts, "   ")
end
for _, attribute in ipairs({ "ClickPower", "AuraPerSecond", "AuraMultiplier" }) do
	player:GetAttributeChangedSignal(attribute):Connect(updateStats)
end
updateStats()

-- Aura: animate the shown number towards the real value.
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local displayed = Instance.new("NumberValue")
displayed.Value = aura.Value

local function renderAura(value)
	auraLabel.Text = "✨ Аура: " .. Format.Number(value)
end
displayed.Changed:Connect(renderAura)
renderAura(aura.Value)

local counterTween
aura.Changed:Connect(function(newValue)
	if counterTween then
		counterTween:Cancel()
	end
	-- Spending (shop/rebirth) snaps down, gains count up.
	if newValue < displayed.Value then
		displayed.Value = newValue
		return
	end
	counterTween = Ui.Tween(displayed, 0.25, { Value = newValue })

	auraScale.Scale = 1.12
	Ui.Tween(auraScale, 0.2, { Scale = 1 })
end)

return TopBar
