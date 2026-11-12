--[[
	Style.luau
	The one place for UI look: colors and font from Config.Theme, the
	root ScreenGui (respects the Roblox top-bar inset), mobile UIScale,
	and helpers for corners, strokes, gradients, shadows, juicy buttons,
	rainbow rarity gradients and sounds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Style = {}

Style.Colors = Config.Theme
Style.Font = Config.Theme.Font
Style.Muted = false -- sound toggle (Settings window)
Style.Shake = true

-- Root ScreenGui. IgnoreGuiInset is OFF so nothing lands under the
-- Roblox buttons in the top-left corner.
local gui = Instance.new("ScreenGui")
gui.Name = "AuraClickerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
Style.Gui = gui

-- Mobile: scale the whole HUD down on narrow screens.
local scale = Instance.new("UIScale")
scale.Parent = gui
Style.Scale = scale
local function refit()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / Config.Hud.MobileScaleWidth, viewport.Y / 620), 0.55, 1)
end
refit()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

function Style.Tween(instance, time, props, style, direction)
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

function Style.Lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Style.Darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Style.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 12)
	corner.Parent = parent
	return corner
end

function Style.Stroke(parent, thickness, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2.5
	stroke.Color = color or Style.Colors.Outline
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Top-lighter vertical gradient.
function Style.Gradient(parent, color: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Style.Lighter(color, 0.3), Style.Darker(color, 0.12))
	gradient.Parent = parent
	return gradient
end

-- Animated rainbow gradient (mythic rarity).
function Style.Rainbow(parent)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 120)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
	})
	gradient.Parent = parent
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not gradient.Parent then
			connection:Disconnect()
			return
		end
		gradient.Rotation = (os.clock() * 90) % 360
	end)
	return gradient
end

-- Soft shadow plate behind an element (same parent, drawn under it).
function Style.Shadow(element, offset: number?)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = element.AnchorPoint
	shadow.Position = element.Position + UDim2.fromOffset(0, offset or 4)
	shadow.Size = element.Size
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.ZIndex = element.ZIndex - 1
	shadow.Parent = element.Parent
	Style.Corner(shadow, UDim.new(0, 14))
	return shadow
end

function Style.Label(parent, text: string, size: number, color: Color3?, props: { [string]: any }?)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Style.Font
	label.TextSize = size
	label.TextColor3 = color or Style.Colors.Text
	label.Text = text
	label.Size = UDim2.new(1, 0, 0, size + 6)
	for key, value in pairs(props or {}) do
		label[key] = value
	end
	label.Parent = parent
	Style.Stroke(label, math.max(2, size / 12))
	return label
end

-- Juicy button: rounded, gradient, outline, shadow, press animation.
-- props: Size, Position, AnchorPoint, Color, Text, TextSize, ZIndex, Parent-less.
function Style.Button(parent, props: { [string]: any })
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.Position = props.Position or UDim2.new()
	button.Size = props.Size or UDim2.fromOffset(120, 44)
	button.BackgroundColor3 = props.Color or Style.Colors.Purple
	button.AutoButtonColor = false
	button.Font = Style.Font
	button.TextSize = props.TextSize or 20
	button.TextColor3 = Style.Colors.Text
	button.Text = props.Text or ""
	button.ZIndex = props.ZIndex or 2
	button.LayoutOrder = props.LayoutOrder or 0
	button.Parent = parent
	Style.Corner(button, props.Radius or UDim.new(0, 14))
	local gradient = Style.Gradient(button, props.Color or Style.Colors.Purple)
	-- One UIStroke per instance: the text stroke lives on the button,
	-- the outline on a transparent child frame of the same shape.
	local ts = Instance.new("UIStroke")
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Thickness = 2
	ts.Color = Color3.new(0, 0, 0)
	ts.Parent = button
	local border = Instance.new("Frame")
	border.Name = "Border"
	border.Size = UDim2.fromScale(1, 1)
	border.BackgroundTransparency = 1
	border.ZIndex = button.ZIndex
	border.Parent = button
	Style.Corner(border, props.Radius or UDim.new(0, 14))
	Style.Stroke(border, 2.5)
	if props.Shadow ~= false and not props.LayoutOrder then
		local shadow = Style.Shadow(button)
		shadow.Visible = button.Visible
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			shadow.Visible = button.Visible
		end)
	end

	local pressScale = Instance.new("UIScale")
	pressScale.Parent = button
	button.MouseButton1Down:Connect(function()
		Style.Tween(pressScale, 0.08, { Scale = 0.92 })
	end)
	local function release()
		Style.Tween(pressScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		Style.PlaySound(Config.Sounds.Ui, 1, 0.4)
	end)

	-- Second return value recolors the button and keeps the gradient in sync.
	local function setColor(color: Color3)
		button.BackgroundColor3 = color
		gradient.Color = ColorSequence.new(Style.Lighter(color, 0.3), Style.Darker(color, 0.12))
	end
	return button, setColor
end

-- Dark opaque HUD plate (the text rule: white text on #1E1B2E).
function Style.Plate(parent, props: { [string]: any })
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Plate"
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.Position = props.Position or UDim2.new()
	frame.Size = props.Size or UDim2.fromOffset(200, 40)
	frame.BackgroundColor3 = props.Color or Style.Colors.PanelDark
	frame.BackgroundTransparency = props.Transparency or 0
	frame.BorderSizePixel = 0
	frame.ZIndex = props.ZIndex or 1
	frame.Parent = parent
	Style.Corner(frame, props.Radius or UDim.new(0, 12))
	Style.Stroke(frame, 2, Style.Colors.Outline)
	return frame
end

-- One-shot sound. Empty ids (TODO slots in Config.Sounds) are skipped.
function Style.PlaySound(soundId: string?, speed: number?, volume: number?)
	if Style.Muted or not soundId or soundId == "" then
		return
	end
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

function Style.RarityColor(rarityId: string?): (Color3, boolean)
	local rarity = Config.Rarity[rarityId or "Common"] or Config.Rarity.Common
	return rarity.Color, rarity.Rainbow == true
end

return Style
