--[[
	WorldKit.luau
	Small helpers for building the world from code: anchored parts,
	floating signs, lights and health bars. Used by HubGenerator and
	DungeonGenerator; it never parents anything to Workspace by itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)

local WorldKit = {}

local HEALTH_FULL = Color3.fromRGB(90, 220, 110)
local HEALTH_LOW = Color3.fromRGB(230, 70, 70)

-- Anchored, smooth part. props are applied on top of the defaults.
function WorldKit.Part(parent: Instance, props: { [string]: any })
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

-- Invisible, non-colliding anchor at a position.
function WorldKit.Anchor(parent: Instance, position: Vector3, name: string?)
	return WorldKit.Part(parent, {
		Name = name or "Anchor",
		Size = Vector3.one,
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

-- Big floating text above a position.
function WorldKit.Sign(parent: Instance, position: Vector3, text: string, color: Color3?, width: number?)
	local anchor = WorldKit.Anchor(parent, position, "Sign")

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width or 300, 56)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or Color3.fromRGB(220, 190, 255)
	label.Text = text
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 10, 50)
	stroke.Parent = label

	return anchor, label
end

function WorldKit.Light(parent: Instance, color: Color3, range: number?, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 16
	light.Brightness = brightness or 1.5
	light.Parent = parent
	return light
end

-- Name + HP bar above a part. Update it with WorldKit.UpdateHealth.
function WorldKit.HealthGui(body: BasePart, name: string, height: number, isBoss: boolean)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthGui"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(if isBoss then 240 else 140, if isBoss then 56 else 42)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Parent = body

	local title = Instance.new("TextLabel")
	title.Name = "MobName"
	title.Size = UDim2.fromScale(1, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = if isBoss then Color3.fromRGB(255, 205, 70) else Color3.new(1, 1, 1)
	title.Text = name
	title.Parent = gui
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 2
	titleStroke.Parent = title

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0, 0.55)
	bar.Size = UDim2.fromScale(1, 0.42)
	bar.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.4, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HEALTH_FULL
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "HpText"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.ZIndex = 2
	text.Parent = bar
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 1.5
	textStroke.Parent = text

	return gui
end

function WorldKit.UpdateHealth(body: BasePart, health: number, maxHealth: number)
	local gui = body:FindFirstChild("HealthGui")
	if not gui then
		return
	end
	local ratio = math.clamp(health / maxHealth, 0, 1)
	gui.Bar.Fill.Size = UDim2.fromScale(ratio, 1)
	gui.Bar.Fill.BackgroundColor3 = HEALTH_LOW:Lerp(HEALTH_FULL, ratio)
	gui.Bar.HpText.Text = Format.Number(health) .. " / " .. Format.Number(maxHealth)
end

-- Two eyes (white + black pupil) on the front (-Z) face of a part.
function WorldKit.Eyes(parent: Instance, body: BasePart)
	local size = body.Size
	local eyeSize = math.max(0.5, size.X * 0.18)
	for _, side in ipairs({ -1, 1 }) do
		local offset = CFrame.new(side * size.X * 0.22, size.Y * 0.18, -size.Z / 2 + eyeSize * 0.3)
		local eye = WorldKit.Part(parent, {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * eyeSize,
			Color = Color3.new(1, 1, 1),
			CFrame = body.CFrame * offset,
			CanCollide = false,
		})
		eye.Shape = Enum.PartType.Ball
		WorldKit.Part(parent, {
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * eyeSize * 0.5,
			Color = Color3.new(0, 0, 0),
			CFrame = body.CFrame * offset * CFrame.new(0, 0, -eyeSize * 0.35),
			CanCollide = false,
		})
	end
end

return WorldKit
