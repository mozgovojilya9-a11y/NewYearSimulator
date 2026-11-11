--[[
	Popups.luau
	Floating damage numbers in the world, toasts on the right edge of
	the screen, full-screen fade (teleports) and camera shake.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.Style)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Popups = {}

-- Floating text at a 3D position (local only). isCrit: bigger, gold,
-- tilted, with a bounce.
function Popups.World(position: Vector3, text: string, color: Color3, size: number?, isCrit: boolean?)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Adornee = attachment
	gui.Size = UDim2.fromOffset(260, 80)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.StudsOffset = Vector3.new((math.random() - 0.5) * 3, 0, 0)
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Style.Font
	label.TextSize = size or 30
	label.TextColor3 = color
	label.Text = text
	label.Rotation = if isCrit then (math.random() - 0.5) * 24 else 0
	label.Parent = gui
	local stroke = Style.Stroke(label, if isCrit then 4 else 3)

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = if isCrit then 0.3 else 0.6
	uiScale.Parent = label
	Style.Tween(uiScale, if isCrit then 0.3 else 0.18, { Scale = if isCrit then 1.25 else 1 }, Enum.EasingStyle.Back)
	if isCrit then
		task.delay(0.3, function()
			Style.Tween(uiScale, 0.3, { Scale = 1 })
		end)
	end

	local life = if isCrit then 1.1 else 0.85
	Style.Tween(gui, life, { StudsOffset = gui.StudsOffset + Vector3.new(0, if isCrit then 6 else 4, 0) })
	task.delay(life * 0.5, function()
		Style.Tween(label, life * 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Style.Tween(stroke, life * 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
	task.delay(life, function()
		gui:Destroy()
		attachment:Destroy()
	end)
end

---------------------------------------------------------------------
-- Toasts (right edge, under the top-right buttons)
---------------------------------------------------------------------

local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.AnchorPoint = Vector2.new(1, 0)
toastHolder.Position = UDim2.new(1, -16, 0, 70)
toastHolder.Size = UDim2.fromOffset(340, 400)
toastHolder.BackgroundTransparency = 1
toastHolder.ZIndex = 40 -- above open windows
toastHolder.Parent = Style.Gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.Padding = UDim.new(0, 6)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHolder

local KIND_COLORS = {
	good = Style.Colors.Green,
	bad = Style.Colors.Red,
	gold = Style.Colors.Gold,
}

function Popups.Toast(text: string, kind: string?)
	local color = KIND_COLORS[kind] or Style.Colors.Text
	local plate = Instance.new("TextLabel")
	plate.AutomaticSize = Enum.AutomaticSize.XY
	plate.Size = UDim2.fromOffset(0, 40)
	plate.BackgroundColor3 = Style.Colors.PanelDark
	plate.BackgroundTransparency = 0.15
	plate.Font = Style.Font
	plate.TextSize = 20
	plate.TextColor3 = color
	plate.TextWrapped = true
	plate.Text = text
	plate.ZIndex = 41
	plate.LayoutOrder = math.floor(os.clock() * 1000)
	plate.Parent = toastHolder
	Style.Corner(plate)
	Style.Stroke(plate, 2.5, color)
	local ts = Instance.new("UIStroke")
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Thickness = 2
	ts.Color = Style.Colors.Outline
	ts.Parent = plate
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = plate
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(340, 200)
	sizeConstraint.Parent = plate

	local pop = Instance.new("UIScale")
	pop.Scale = 0.7
	pop.Parent = plate
	Style.Tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(Config.Hud.ToastSeconds, function()
		Style.Tween(plate, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.wait(0.3)
		plate:Destroy()
	end)
end

-- Server -> client toasts.
task.spawn(function()
	local notify = ReplicatedStorage:WaitForChild("Notify")
	notify.OnClientEvent:Connect(function(text, kind)
		Popups.Toast(tostring(text), kind)
	end)
end)

---------------------------------------------------------------------
-- Screen fade + camera shake
---------------------------------------------------------------------

local fade = Instance.new("Frame")
fade.Name = "Fade"
fade.Size = UDim2.fromScale(1.2, 1.2)
fade.Position = UDim2.fromScale(-0.1, -0.1)
fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 1
fade.ZIndex = 100
fade.Visible = false
fade.Parent = Style.Gui

-- Quick dip to black and back (teleports). color optional.
function Popups.Fade(color: Color3?, seconds: number?)
	local t = seconds or 0.35
	fade.BackgroundColor3 = color or Color3.new(0, 0, 0)
	fade.Visible = true
	fade.BackgroundTransparency = 1
	Style.Tween(fade, t, { BackgroundTransparency = 0 })
	task.delay(t + 0.1, function()
		Style.Tween(fade, t * 1.5, { BackgroundTransparency = 1 })
		task.wait(t * 1.5)
		fade.Visible = false
	end)
end

-- Egg hatch: shaking egg, flash, then the pet's name in its rarity color.
function Popups.Hatch(petName: string, color: Color3, rainbow: boolean?)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.Size = UDim2.fromOffset(300, 220)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 60
	holder.Parent = Style.Gui

	local egg = Style.Label(holder, "🥚", 120, Style.Colors.Text, { Size = UDim2.new(1, 0, 0, 150), ZIndex = 61 })
	egg:FindFirstChildOfClass("UIStroke").Transparency = 1
	task.spawn(function()
		for i = 1, 10 do
			egg.Rotation = (if i % 2 == 0 then 1 else -1) * (4 + i * 1.5)
			task.wait(0.09)
		end
		egg.Rotation = 0
		Popups.Fade(Color3.new(1, 1, 1), 0.15)
		Popups.Shake(0.4, 0.2)
		task.wait(0.15)
		egg.Text = "🐾"
		local name = Style.Label(holder, petName, 34, color, { Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 44), ZIndex = 61 })
		if rainbow then
			Style.Rainbow(name)
		end
		local pop = Instance.new("UIScale")
		pop.Scale = 0.3
		pop.Parent = holder
		Style.Tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(2.2)
		Style.Tween(pop, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.3)
		holder:Destroy()
	end)
end

local shakeUntil = 0
local shakeAmplitude = 0
function Popups.Shake(amplitude: number, seconds: number)
	if not Style.Shake then
		return
	end
	shakeAmplitude = math.max(shakeAmplitude, amplitude)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera or os.clock() > shakeUntil then
		shakeAmplitude = 0
		return
	end
	local remaining = (shakeUntil - os.clock())
	local a = shakeAmplitude * math.min(1, remaining * 4)
	camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
end)

return Popups
