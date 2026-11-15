--[[
	Popups.luau
	Floating damage numbers in the world, toasts on the right edge of
	the screen, a big centered banner (level up), full-screen fade
	(teleports) and camera shake.
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
toastHolder.Position = UDim2.new(1, -16, 0, 64)
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
	local color = KIND_COLORS[kind] or Style.Colors.GoldDim
	local width = 320
	local plate = Style.Panel(toastHolder, {
		Name = "Toast",
		Size = UDim2.fromOffset(width, 40),
		ZIndex = 41,
		Fill = Style.Colors.PanelDark,
		Transparency = 0.08,
		Border = Style.Colors.Line,
		Cut = 6,
	})
	plate.LayoutOrder = math.floor(os.clock() * 1000)
	-- kind color: a thin bar on the left edge (the text itself stays light)
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(6, 8)
	bar.Size = UDim2.new(0, 3, 1, -16)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = 42
	bar.Parent = plate
	local label = Style.Label(plate, text, 15, Style.Colors.Text, {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -26, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 42,
	})
	-- grow for long texts (two or three lines)
	local bounds = game:GetService("TextService"):GetTextSize(text, 15, Style.Font, Vector2.new(width - 26, 200))
	plate.Size = UDim2.fromOffset(width, math.max(40, bounds.Y + 18))

	local pop = Instance.new("UIScale")
	pop.Scale = 0.9
	pop.Parent = plate
	Style.Tween(pop, 0.15, { Scale = 1 })

	task.delay(Config.Hud.ToastSeconds, function()
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("Frame") then
				Style.Tween(d, 0.3, { BackgroundTransparency = 1 })
			elseif d:IsA("TextLabel") then
				Style.Tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				Style.Tween(d, 0.3, { Transparency = 1 })
			end
		end
		task.wait(0.3)
		plate:Destroy()
	end)
	local _ = label
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

-- Short bright flash of a color over the whole screen (rare drops).
function Popups.Flash(color: Color3)
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1.2, 1.2)
	flash.Position = UDim2.fromScale(-0.1, -0.1)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.35
	flash.BorderSizePixel = 0
	flash.ZIndex = 90
	flash.Parent = Style.Gui
	Style.Tween(flash, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.75, function()
		flash:Destroy()
	end)
end

-- Big centered banner (level up and other big moments): title, a huge
-- line and up to two small lines. Pops in, holds, fades out.
local bannerToken = 0
function Popups.Banner(title: string, big: string, lines: { string }?, color: Color3?)
	color = color or Style.Colors.Gold
	bannerToken += 1
	local token = bannerToken
	local old = Style.Gui:FindFirstChild("Banner")
	if old then
		old:Destroy()
	end
	local count = #(lines or {})
	local plate = Style.Panel(Style.Gui, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(460, 150 + count * 24),
		ZIndex = 80,
		Fill = Style.Colors.PanelDark,
		Transparency = 0.06,
		Border = color,
		Cut = 16,
		Thickness = 2,
	})
	Style.Label(plate, Style.Upper(title), 18, color, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22), ZIndex = 81 })
	Style.Rule(plate, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.new(0.7, 0, 0, 1), Color = color, ZIndex = 81 })
	Style.Label(plate, big, 54, Style.Colors.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 64), ZIndex = 81 })
	for i, line in ipairs(lines or {}) do
		Style.Label(plate, line, 16, if i == 1 then Style.Colors.Gold else Style.Colors.Muted, { Position = UDim2.fromOffset(0, 118 + (i - 1) * 24), Size = UDim2.new(1, 0, 0, 22), ZIndex = 81 })
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = plate
	Style.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.8, function()
		if token ~= bannerToken or not plate.Parent then
			return
		end
		Style.Tween(scale, 0.25, { Scale = 0.6 })
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("TextLabel") then
				Style.Tween(d, 0.25, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				Style.Tween(d, 0.25, { Transparency = 1 })
			end
		end
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("Frame") then
				Style.Tween(d, 0.25, { BackgroundTransparency = 1 })
			end
		end
		task.wait(0.3)
		plate:Destroy()
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
