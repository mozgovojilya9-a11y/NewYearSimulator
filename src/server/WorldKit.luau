--[[
	WorldKit.luau
	Helpers for building the world from code in the "brick" look:
	stud-topped blocks, tiled floors, crenellated walls, surface signs,
	beams and health bars. Used by HubGenerator and DungeonGenerator;
	it never parents anything to Workspace by itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local WorldKit = {}

local Theme = Config.Theme
local BAR_FULL = Color3.fromRGB(90, 230, 110)
local BAR_LOW = Color3.fromRGB(240, 70, 80)

-- Anchored part. props are applied on top of the defaults.
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

-- A "brick": plastic block with studs on top and bevel-looking sides.
function WorldKit.Brick(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, name: string?)
	return WorldKit.Part(parent, {
		Name = name or "Brick",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
	})
end

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

-- Invisible collision-only part (map bounds).
function WorldKit.Invisible(parent: Instance, size: Vector3, position: Vector3, name: string?)
	return WorldKit.Part(parent, {
		Name = name or "Bound",
		Size = size,
		Position = position,
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

-- Floor of alternating-tint tiles. Tile count is capped so a room
-- never spends more than maxParts on its floor.
function WorldKit.TiledFloor(parent: Instance, center: Vector3, width: number, depth: number, tile: number, colorA: Color3, colorB: Color3, maxParts: number?)
	local nx = math.max(1, math.floor(width / tile))
	local nz = math.max(1, math.floor(depth / tile))
	if maxParts and nx * nz > maxParts then
		local scale = math.sqrt(nx * nz / maxParts)
		tile = tile * scale
		nx = math.max(1, math.floor(width / tile))
		nz = math.max(1, math.floor(depth / tile))
	end
	local tw = width / nx
	local td = depth / nz
	local x0 = center.X - width / 2 + tw / 2
	local z0 = center.Z - depth / 2 + td / 2
	local folder = Instance.new("Model")
	folder.Name = "Floor"
	folder.Parent = parent
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			WorldKit.Brick(folder, Vector3.new(tw, 1, td), CFrame.new(x0 + ix * tw, center.Y - 0.5, z0 + iz * td), if (ix + iz) % 2 == 0 then colorA else colorB, "Tile")
		end
	end
	return folder
end

-- Wall built from big bricks of two alternating tints, with merlons
-- (battlements) along the top. axis: "X" (runs along X) or "Z".
function WorldKit.CastleWall(parent: Instance, from: Vector3, to: Vector3, height: number, thickness: number, colorA: Color3, colorB: Color3, merlon: number?, gap: { Center: number, Width: number }?, merlonColor: Color3?)
	local model = Instance.new("Model")
	model.Name = "Wall"
	model.Parent = parent
	local delta = to - from
	local length = delta.Magnitude
	local dir = delta.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	-- The wall is laid in runs that end exactly at the gap edges, so the
	-- opening is never wider than gap.Width (no holes beside a doorway).
	local runs = { { 0, length } }
	if gap then
		runs = { { 0, gap.Center - gap.Width / 2 }, { gap.Center + gap.Width / 2, length } }
	end
	local brick = 0
	for _, run in ipairs(runs) do
		local runLength = run[2] - run[1]
		if runLength > 0.05 then
			local count = math.max(1, math.floor(runLength / 8 + 0.5))
			local segment = runLength / count
			for i = 0, count - 1 do
				local s = run[1] + i * segment + segment / 2
				local pos = from + dir * s + Vector3.new(0, height / 2, 0)
				WorldKit.Brick(model, Vector3.new(segment, height, thickness), CFrame.lookAt(pos, pos + right), if brick % 2 == 0 then colorA else colorB)
				brick += 1
			end
		end
	end
	if merlon and merlon > 0 then
		local mcount = math.floor(length / (merlon * 2))
		for i = 0, mcount do
			local s = i * merlon * 2 + merlon / 2
			if s < length and not (gap and math.abs(s - gap.Center) < gap.Width / 2) then
				local pos = from + dir * s + Vector3.new(0, height + merlon / 2, 0)
				WorldKit.Brick(model, Vector3.new(merlon, merlon, thickness), CFrame.lookAt(pos, pos + right), merlonColor or colorA:Lerp(Color3.new(1, 1, 1), 0.35), "Merlon")
			end
		end
	end
	return model
end

-- Text on a face of a part (SurfaceGui). The text rule of the game:
-- an opaque dark plate (Theme.PanelDark, rounded) under white / yellow
-- FredokaOne text with a black stroke, LightInfluence 0, 50-75 px per
-- stud. The plate hugs the lines, so it also works on barriers and
-- stone walls. Labels are found with gui:FindFirstChild(name, true).
local function faceStuds(part: BasePart, face: Enum.NormalId): (number, number)
	local s = part.Size
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		return s.X, s.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	end
	return s.X, s.Z
end

function WorldKit.SurfaceText(part: BasePart, face: Enum.NormalId, lines: { { Text: string, Size: number, Color: Color3?, Name: string? } }, pixelsPerStud: number?)
	local pps = math.clamp(pixelsPerStud or 50, 50, 75)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part

	local studsW, studsH = faceStuds(part, face)
	local canvasW, canvasH = studsW * pps, studsH * pps
	local gap = 4
	local total = 0
	for _, line in ipairs(lines) do
		total += line.Size * 1.3 + gap
	end
	local scale = math.min(1.6, (canvasH - 28) / math.max(1, total))

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromOffset(canvasW - 8, math.min(canvasH - 8, total * scale + 20))
	plate.BackgroundColor3 = Theme.PanelDark
	plate.BackgroundTransparency = 0
	plate.BorderSizePixel = 0
	plate.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = plate
	local border = Instance.new("UIStroke")
	border.Thickness = 3
	border.Color = Theme.Outline
	border.Parent = plate

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, gap * scale)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = plate

	local labels = {}
	for i, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = line.Name or ("Line" .. i)
		label.LayoutOrder = i
		label.Size = UDim2.new(1, -20, 0, line.Size * 1.3 * scale)
		label.BackgroundTransparency = 1
		label.Font = Theme.Font
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = line.Color or Theme.Text
		label.Text = line.Text
		label.Parent = plate
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = label
		labels[i] = label
	end
	return gui, labels
end

function WorldKit.Light(parent: Instance, color: Color3, range: number?, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 16
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Vertical light beam between two positions.
function WorldKit.Beam(parent: Instance, from: Vector3, to: Vector3, colors: ColorSequence, width: number?)
	local a0 = WorldKit.Anchor(parent, from, "BeamStart")
	local a1 = WorldKit.Anchor(parent, to, "BeamEnd")
	local att0 = Instance.new("Attachment")
	att0.Parent = a0
	local att1 = Instance.new("Attachment")
	att1.Parent = a1
	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = colors
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = width or 3
	beam.Width1 = (width or 3) * 0.3
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	beam.FaceCamera = true
	beam.Parent = a0
	return beam, a0, a1
end

-- Torch: wooden post, neon ember and a Fire effect.
function WorldKit.Torch(parent: Instance, position: Vector3, color: Color3?)
	local post = WorldKit.Part(parent, {
		Name = "Torch",
		Size = Vector3.new(0.8, 5, 0.8),
		Position = position + Vector3.new(0, 2.5, 0),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	})
	local ember = WorldKit.Part(post, {
		Name = "Ember",
		Size = Vector3.new(1.2, 1, 1.2),
		Position = position + Vector3.new(0, 5.4, 0),
		Color = color or Theme.Orange,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local fire = Instance.new("Fire")
	fire.Color = color or Theme.Orange
	fire.SecondaryColor = Theme.Gold
	fire.Size = 4
	fire.Heat = 8
	fire.Parent = ember
	WorldKit.Light(ember, color or Theme.Orange, 18, 1.4)
	return post
end

-- Thin HP bar above a part, sized in studs so bars don't overlap.
-- Name is shown only when `name` is given (bosses).
function WorldKit.HealthGui(body: BasePart, name: string?, heightOffset: number)
	local hb = Config.MobLooks.HealthBar
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthGui"
	gui.Adornee = body
	gui.Size = UDim2.new(hb.Width, 0, hb.Height * (if name then 2.2 else 1), 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, heightOffset, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = hb.MaxDistance
	gui.LightInfluence = 0
	gui.Parent = body

	if name then
		local title = Instance.new("TextLabel")
		title.Name = "MobName"
		title.Size = UDim2.fromScale(1, 0.55)
		title.BackgroundTransparency = 1
		title.Font = Theme.Font
		title.TextScaled = true
		title.TextColor3 = Theme.Gold
		title.Text = name
		title.Parent = gui
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Color = Theme.Outline
		s.Parent = title
	end

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.fromScale(1, if name then 0.42 else 1)
	bar.BackgroundColor3 = Color3.fromRGB(25, 15, 40)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0.5, 0)
	c1.Parent = bar
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Theme.Outline
	st.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_FULL
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.5, 0)
	c2.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "HpText"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Theme.Font
	text.TextScaled = true
	text.TextColor3 = Theme.Text
	text.ZIndex = 2
	text.Parent = bar
	local ts = Instance.new("UIStroke")
	ts.Thickness = 1.5
	ts.Color = Theme.Outline
	ts.Parent = text
	return gui
end

function WorldKit.UpdateHealth(body: BasePart, health: number, maxHealth: number)
	local gui = body:FindFirstChild("HealthGui")
	if not gui then
		return
	end
	local ratio = math.clamp(health / maxHealth, 0, 1)
	gui.Bar.Fill.Size = UDim2.fromScale(ratio, 1)
	gui.Bar.Fill.BackgroundColor3 = BAR_LOW:Lerp(BAR_FULL, ratio)
	gui.Bar.HpText.Text = Format.Number(health) .. "/" .. Format.Number(maxHealth)
end

-- Styled ProximityPrompt. The client draws it (Style = Custom).
function WorldKit.Prompt(parent: Instance, actionText: string, objectText: string, attributes: { [string]: any }?, distance: number?, holdDuration: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration or 0.3
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	for key, value in pairs(attributes or {}) do
		prompt:SetAttribute(key, value)
	end
	prompt.Parent = parent
	return prompt
end

return WorldKit
