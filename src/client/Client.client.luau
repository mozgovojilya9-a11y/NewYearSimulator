--[[
	Client.client.luau
	Day 1 UI: a slim top bar showing the local player's Aura and the
	current online count. Reads leaderstats.Aura directly, so it stays
	correct no matter what system changes Aura later (clicks, mobs,
	pets, rebirth, ...).
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TopBar"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

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
auraLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
auraLabel.TextXAlignment = Enum.TextXAlignment.Left
auraLabel.Text = "Аура: 0"
auraLabel.Parent = bar

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

local leaderstats = player:WaitForChild("leaderstats")
local aura = leaderstats:WaitForChild("Aura")

local function updateAura()
	auraLabel.Text = "Аура: " .. aura.Value
end

aura.Changed:Connect(updateAura)
updateAura()
