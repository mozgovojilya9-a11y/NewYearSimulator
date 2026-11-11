--[[
	Ui.luau
	Shared client helpers: the single ScreenGui, colors, tweens, sounds,
	world-space popups and toast messages. Every other client module
	builds on top of this.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Ui = {}

Ui.Colors = {
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(200, 200, 215),
	Crit = Color3.fromRGB(255, 205, 70),
	Aura = Color3.fromRGB(205, 160, 255),
	Gems = Color3.fromRGB(110, 230, 255),
	Accent = Color3.fromRGB(150, 90, 255),
	Panel = Color3.fromRGB(28, 22, 42),
	PanelLight = Color3.fromRGB(45, 36, 66),
	Good = Color3.fromRGB(90, 210, 120),
	Bad = Color3.fromRGB(235, 85, 85),
	Outline = Color3.fromRGB(30, 10, 60),
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AuraClickerUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui
Ui.Gui = screenGui

function Ui.Tween(instance, time, props, style, direction)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

function Ui.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 10)
	corner.Parent = parent
	return corner
end

function Ui.Stroke(parent, thickness, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2
	stroke.Color = color or Ui.Colors.Outline
	stroke.Parent = parent
	return stroke
end

-- Plays a one-shot sound. Each call gets its own Sound so overlapping
-- clicks don't cut each other off.
function Ui.PlaySound(soundId: string, speed: number?, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Floating text at a 3D position, visible only to this player.
function Ui.WorldPopup(position: Vector3, text: string, color: Color3, textSize: number?)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Adornee = attachment
	gui.Size = UDim2.fromOffset(240, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffset = Vector3.new((math.random() - 0.5) * 3, 0, 0)
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = textSize or 28
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	local stroke = Ui.Stroke(label, 2)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = label
	Ui.Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)

	Ui.Tween(gui, 0.9, { StudsOffset = gui.StudsOffset + Vector3.new(0, 4, 0) })
	Ui.Tween(label, 0.9, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Ui.Tween(stroke, 0.9, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	task.delay(0.9, function()
		gui:Destroy()
		attachment:Destroy()
	end)
end

-- Short message in the upper middle of the screen.
local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 96)
toastHolder.Size = UDim2.fromOffset(420, 200)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = screenGui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toastHolder

function Ui.Toast(text: string, color: Color3?)
	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 34)
	label.BackgroundColor3 = Ui.Colors.Panel
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = color or Ui.Colors.Text
	label.Text = text
	label.Parent = toastHolder
	Ui.Corner(label)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = label

	task.delay(2.2, function()
		Ui.Tween(label, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.wait(0.3)
		label:Destroy()
	end)
end

return Ui
