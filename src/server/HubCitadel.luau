--[[
	HubCitadel.luau
	The hub "Нано-Цитадель" built from scratch after concept sheet
	docs/design/concept/01_hub_map.png (Config.Citadel): an open floating
	island, no roofs.

	  ground level (y 0): 1 the spawn forecourt (south) with two pylons and
	    3 the mentor; 2 the round atrium with the hologram cube on a dais,
	    sakuras in metal tubs, benches, lamps;
	  the terrace (2F, a ring around the atrium, y = TerraceHeight): stairs
	    up from the atrium (north, west, east), a bridge across the
	    atrium's north part, a glass railing along the edge;
	  on the terrace, against the thick rim wall with warm light slits:
	    7 Зал Врат (north): the ring portal with the rank letters E-S,
	      8 leaderboards and 9 the quest board + Смотритель Врат on its
	      sides, tall pylons and towers behind;
	    6 Кузница (north-east): forge core, anvil with the manipulator,
	      conveyors along the wall;
	    4 Академия (east): three class characters under glass domes;
	    5 Терминал снабжения (west): the capsule machine and six display
	      capsules by rarity;
	    the АФК portal (south-east) with the light bridge to the AFK island,
	    the Red Gates (north-west, event).
	  Under it: a dark plinth with lit windows, rock, crystals, far
	  islands, a sea of clouds (HubIsland.Scenery).

	Round shapes (terrace, rim wall, trims) are cut with GeometryService
	(one clean part each); if that fails they fall back to segments.
	Returns the same hub table the services always used.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local GeometryService = game:GetService("GeometryService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)
local HubIsland = require(script.Parent.HubIsland)

local HubCitadel = {}

local CD = Config.Citadel
local K = CD.Colors
local L = Config.HubLayout
local LC = L.Colors
local N = Config.Nano
local T = Config.Theme
local Texts = L.Texts
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local root, base, C
local TH = CD.TerraceHeight

---------------------------------------------------------------------
-- Geometry helpers
---------------------------------------------------------------------

local function at(x: number, y: number, z: number): Vector3
	return base + Vector3.new(x, y, z)
end

-- A point on the circle around the island centre: theta degrees
-- clockwise from north, r studs out, y up.
local function P(theta: number, r: number, y: number?): Vector3
	local a = math.rad(theta)
	return C + Vector3.new(math.sin(a) * r, y or 0, -math.cos(a) * r)
end

-- Ground frame at (theta, r, y) whose -Z (LookVector) faces the centre.
local function faceIn(theta: number, r: number, y: number?): CFrame
	local p = P(theta, r, y)
	return CFrame.lookAt(p, Vector3.new(C.X, p.Y, C.Z))
end

-- Is the angle inside one of the gaps { centre, half width }?
local function inGap(theta: number, gaps): boolean
	for _, g in ipairs(gaps) do
		local d = (theta - g[1] + 540) % 360 - 180
		if math.abs(d) <= g[2] then
			return true
		end
	end
	return false
end

local function flatDisc(parent, name, diameter, y, pos: Vector3, color, material)
	local d = NanoKit.Cylinder(parent, name, 0.08, diameter, CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	d.CanCollide = false
	d.CastShadow = false
	return d
end

local function tempCylinder(diameter: number, y0: number, y1: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.Size = Vector3.new(y1 - y0, diameter, diameter)
	p.CFrame = CFrame.new(C + Vector3.new(0, (y0 + y1) / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = Workspace
	return p
end

-- A flat ring rIn..rOut between y0 and y1 around the centre, minus the
-- `cuts` boxes ({ Size, CFrame }). One clean union; segments if CSG fails.
local function ring(parent, name: string, rIn: number, rOut: number, y0: number, y1: number, color: Color3, material: Enum.Material, cuts)
	cuts = cuts or {}
	local outer = tempCylinder(rOut * 2, y0, y1)
	outer.Color = color
	outer.Material = material
	local subtract = { tempCylinder(rIn * 2, y0 - 1, y1 + 1) }
	for _, c in ipairs(cuts) do
		local box = Instance.new("Part")
		box.Anchored = true
		box.Size = c.Size
		box.CFrame = c.CFrame
		box.Parent = Workspace
		table.insert(subtract, box)
	end
	local ok, result = pcall(function()
		return GeometryService:SubtractAsync(outer, subtract, {
			CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
			RenderFidelity = Enum.RenderFidelity.Precise,
			SplitApart = false,
		})
	end)
	outer:Destroy()
	for _, s in ipairs(subtract) do
		s:Destroy()
	end
	if ok and result and result[1] then
		local u = result[1]
		u.Name = name
		u.Anchored = true
		u.UsePartColor = true
		u.Color = color
		u.Material = material
		u.Parent = parent
		return u
	end
	-- fallback: narrow blocks around the circle, skipping the cut boxes
	warn("[HubCitadel] CSG failed for " .. name .. ", using segments: " .. tostring(result))
	local m = NanoKit.Model(parent, name)
	local n = math.max(24, math.floor(rOut * 0.9))
	local depth = rOut - rIn
	for i = 0, n - 1 do
		local theta = (i + 0.5) / n * 360
		local mid = P(theta, (rIn + rOut) / 2, (y0 + y1) / 2)
		local skip = false
		for _, c in ipairs(cuts) do
			local rel = c.CFrame:PointToObjectSpace(mid)
			if math.abs(rel.X) < c.Size.X / 2 and math.abs(rel.Z) < c.Size.Z / 2 then
				skip = true
			end
		end
		if not skip then
			local w = 2 * rOut * math.sin(math.pi / n) + 0.15
			local cf = CFrame.lookAt(mid, Vector3.new(C.X, mid.Y, C.Z))
			Panel(m, "Segment", Vector3.new(w, y1 - y0, depth), cf, color, material)
		end
	end
	return m
end

-- A box cut along the radius at `theta`: width across, from r0 to r1.
local function radialCut(theta: number, width: number, r0: number, r1: number, y0: number, y1: number)
	local mid = P(theta, (r0 + r1) / 2, (y0 + y1) / 2)
	return { Size = Vector3.new(width, y1 - y0, r1 - r0), CFrame = CFrame.lookAt(mid, Vector3.new(C.X, mid.Y, C.Z)) }
end

-- The spawn corridor cut (south): the full width from the atrium out.
local function corridorCut(y0: number, y1: number)
	local w = CD.Corridor * 2
	return { Size = Vector3.new(w, y1 - y0, 90), CFrame = CFrame.new(C + Vector3.new(0, (y0 + y1) / 2, CD.AtriumRadius - 10 + 45)) }
end

---------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------

local function spot(parent: Instance, face: Enum.NormalId, range: number, brightness: number, angle: number?, color: Color3?)
	local light = Instance.new("SpotLight")
	light.Face = face
	light.Color = color or N.WarmLight
	light.Range = range
	light.Brightness = brightness
	light.Angle = angle or 120
	light.Shadows = false
	light.Parent = parent
	return light
end

local function text(part: BasePart, face: Enum.NormalId, lines)
	return WorldKit.SurfaceText(part, face, lines, 60)
end

-- Dark sign plate with a gold frame. cf = plate centre, -Z face reads.
local function signPlate(parent, cf: CFrame, size: Vector2, lines, bothSides: boolean?)
	local m = NanoKit.Model(parent, "Sign")
	local plate = Panel(m, "Plate", Vector3.new(size.X, size.Y, 0.3), cf, T.PanelDark, M.Smooth, { CanCollide = false })
	text(plate, Enum.NormalId.Front, lines)
	if bothSides then
		text(plate, Enum.NormalId.Back, lines)
	end
	local fw, fh, b = size.X / 2 + 0.15, size.Y / 2 + 0.15, 0.3
	Panel(m, "FrameTop", Vector3.new(size.X + 0.6, b, 0.5), cf * CFrame.new(0, fh, 0), K.Trim, M.Metal, { CanCollide = false })
	Panel(m, "FrameBottom", Vector3.new(size.X + 0.6, b, 0.5), cf * CFrame.new(0, -fh, 0), K.Trim, M.Metal, { CanCollide = false })
	Panel(m, "FrameLeft", Vector3.new(b, size.Y + 0.6, 0.5), cf * CFrame.new(-fw, 0, 0), K.Trim, M.Metal, { CanCollide = false })
	Panel(m, "FrameRight", Vector3.new(b, size.Y + 0.6, 0.5), cf * CFrame.new(fw, 0, 0), K.Trim, M.Metal, { CanCollide = false })
	return m, plate
end

-- A hall sign on the rim wall's inner face at `theta` (sheet 01: a dark
-- plate with a gold frame and a warm light over it).
local function wallSign(theta: number, title: string, sub: string?)
	-- standing on the front edge of the hall's roof, seen from the atrium
	local PV = CD.Pavilion
	local cf = faceIn(theta, CD.TerraceOuter - PV.RoofDepth - 1.2, TH + PV.Height + 2.6)
	local lines = { { Text = title, Size = 80, Color = N.Gold } }
	if sub then
		table.insert(lines, { Text = sub, Size = 36, Color = T.Text })
	end
	local m = signPlate(root, cf, Vector2.new(18, if sub then 4.4 else 3.2), lines)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Stand", Vector3.new(0.5, 2.6, 0.5), cf * CFrame.new(sx * 6, -2.6, 0.3), K.Wall, M.Metal, { CanCollide = false })
	end
	return m
end

-- A sakura (owner prop, else a plant capsule) in a metal tub with a gold rim.
local function hasProp(name: string): boolean
	local assets = ServerStorage:FindFirstChild("GameAssets")
	local props = assets and assets:FindFirstChild("Props")
	return props ~= nil and props:FindFirstChild(name) ~= nil
end

local function sakura(parent, p: Vector3, size: number?)
	local m = NanoKit.Model(parent, "Sakura")
	if hasProp("Prop_Sakura") then
		-- the model has its own pot: straight on the floor
		NanoKit.Prop(m, "Prop_Sakura", CFrame.new(p) * CFrame.Angles(0, (p.X * 13 + p.Z * 7) % 6.28, 0), CD.TreeHeight)
		return m
	end
	local s = size or 5
	Panel(m, "Tub", Vector3.new(s, 2, s), CFrame.new(p + Vector3.new(0, 1, 0)), K.Wall, M.Metal)
	Panel(m, "TubRim", Vector3.new(s + 0.4, 0.3, s + 0.4), CFrame.new(p + Vector3.new(0, 2.05, 0)), K.Trim, M.Metal)
	Panel(m, "Soil", Vector3.new(s - 0.6, 0.2, s - 0.6), CFrame.new(p + Vector3.new(0, 2.05, 0)), Color3.fromRGB(70, 96, 58), Enum.Material.Grass, { CanCollide = false })
	NanoKit.Prop(m, "Prop_Sakura", CFrame.new(p + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, (p.X * 13 + p.Z * 7) % 6.28, 0), CD.TreeHeight, function(pp, c)
		return NanoKit.PlantCapsule(pp, c.Position, 1.3)
	end)
	return m
end

-- A warm lamp post: graphite pole, gold ring, a lantern with a warm light.
local function lampPost(parent, p: Vector3)
	local m = NanoKit.Model(parent, "LampPost")
	NanoKit.Column(m, "Foot", 0.8, 1.8, p, K.WallDark, M.Metal)
	NanoKit.Column(m, "Pole", 8, 0.5, p, K.Wall, M.Metal)
	NanoKit.Column(m, "Ring", 0.3, 0.9, p + Vector3.new(0, 5, 0), K.Trim, M.Metal)
	NanoKit.Column(m, "Lantern", 1.6, 1.3, p + Vector3.new(0, 8, 0), K.Slit, M.Neon).CanCollide = false
	NanoKit.Column(m, "Cap", 0.4, 1.8, p + Vector3.new(0, 9.6, 0), K.Trim, M.Metal)
	WorldKit.Light(m:FindFirstChild("Lantern"), K.Slit, 18, 1)
	return m
end

-- A tall square pylon with gold light slits and a cap (spawn, gates).
local function pylon(parent, cf: CFrame, height: number, width: number)
	local m = NanoKit.Model(parent, "Pylon")
	Panel(m, "Body", Vector3.new(width, height, width), cf * CFrame.new(0, height / 2, 0), K.Wall, M.Metal)
	Panel(m, "Base", Vector3.new(width + 1.2, 1.6, width + 1.2), cf * CFrame.new(0, 0.8, 0), K.WallDark, M.Metal)
	Panel(m, "Cap", Vector3.new(width + 0.8, 1, width + 0.8), cf * CFrame.new(0, height + 0.5, 0), K.Trim, M.Metal)
	for _, z in ipairs({ -1, 1 }) do
		for _, x in ipairs({ -0.28, 0.28 }) do
			Panel(m, "Slit", Vector3.new(0.35, height * 0.62, 0.12), cf * CFrame.new(x * width, height * 0.52, z * (width / 2 + 0.03)), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		end
	end
	return m
end

-- A crest banner hanging on the -Z face of `cf` (centre at the top edge).
local function hangingBanner(parent, cf: CFrame, width: number, length: number)
	local m = NanoKit.Model(parent, "Banner")
	Panel(m, "Bar", Vector3.new(width + 1, 0.4, 0.4), cf, K.Trim, M.Metal, { CanCollide = false })
	local cloth = cf * CFrame.new(0, -length / 2 - 0.2, -0.1)
	Panel(m, "Cloth", Vector3.new(width, length, 0.12), cloth, CD.BannerCloth, Enum.Material.Fabric, { CanCollide = false })
	Panel(m, "Trim", Vector3.new(width, 0.25, 0.16), cloth * CFrame.new(0, -length / 2 + 0.3, 0), K.Trim, M.Metal, { CanCollide = false })
	local face = cloth * CFrame.new(0, length * 0.1, -0.08)
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			Panel(m, "Wing", Vector3.new(width * (0.3 - k * 0.07), 0.22, 0.05), face * CFrame.new(side * width * 0.2, 0.4 - k * 0.45, 0) * CFrame.Angles(0, 0, math.rad(side * (28 - k * 6))), K.Trim, M.Metal, { CanCollide = false })
		end
	end
	Panel(m, "Diamond", Vector3.new(0.7, 0.7, 0.05), face * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(45)), K.Trim, M.Metal, { CanCollide = false })
	Panel(m, "Blade", Vector3.new(0.18, 2, 0.05), face * CFrame.new(0, -0.6, 0), K.Trim, M.Metal, { CanCollide = false })
	return m
end

-- Straight stairs: foot centre on the ground, going along `dir` up `rise`.
local function stairs(parent, foot: Vector3, dir: Vector3, width: number, rise: number, run: number)
	local m = NanoKit.Model(parent, "Stairs")
	local steps = math.ceil(rise / 0.75)
	local tread = run / steps
	local look = CFrame.lookAt(foot, foot + dir)
	for i = 1, steps do
		local h = rise * i / steps
		local cf = look * CFrame.new(0, h / 2, -tread * (i - 0.5))
		Panel(m, "Step", Vector3.new(width, h, tread + 0.05), cf, if i % 2 == 0 then K.Floor else K.FloorDark, M.Concrete)
		Panel(m, "Nosing", Vector3.new(width, 0.1, 0.3), look * CFrame.new(0, h + 0.02, -tread * i + 0.15), K.Trim, M.Metal, { CanCollide = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		local a = (look * CFrame.new(sx * (width / 2 + 0.6), 0, 0)).Position
		local b = (look * CFrame.new(sx * (width / 2 + 0.6), rise, -run)).Position
		local length = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		Panel(m, "Stringer", Vector3.new(1.2, 1.6, length), cf, K.Wall, M.Metal)
		Panel(m, "Handrail", Vector3.new(0.3, 0.3, length), cf * CFrame.new(0, 3.4, 0), K.Trim, M.Metal)
		Panel(m, "Glass", Vector3.new(0.12, 2.6, length - 1), cf * CFrame.new(0, 2, 0), LC.Glass, M.Glass, { Transparency = 0.7 })
		NanoKit.Strip(m, (cf * CFrame.new(0, 0.9, -length / 2)).Position, (cf * CFrame.new(0, 0.9, length / 2)).Position, K.Slit, 0.12)
	end
	return m
end

-- A glass railing along a straight line a -> b (heights from a / b).
local function railing(parent, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	Panel(parent, "Rail", Vector3.new(0.3, 0.3, length), cf * CFrame.new(0, 3.4, 0), K.Trim, M.Metal)
	Panel(parent, "RailGlass", Vector3.new(0.12, 2.8, length), cf * CFrame.new(0, 1.9, 0), LC.Glass, M.Glass, { Transparency = 0.72 })
	Panel(parent, "RailBase", Vector3.new(0.5, 0.5, length), cf * CFrame.new(0, 0.25, 0), K.Wall, M.Metal)
end

local function console(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Console")
	Panel(m, "Base", Vector3.new(3.2, 2.7, 1.6), cf * CFrame.new(0, 1.35, 0), K.Wall, M.Metal)
	Panel(m, "Desk", Vector3.new(3.4, 0.3, 1.9), cf * CFrame.new(0, 2.85, -0.1) * CFrame.Angles(math.rad(14), 0, 0), LC.Steel, M.Metal)
	local screen = Panel(m, "Screen", Vector3.new(3, 1.7, 0.15), cf * CFrame.new(0, 3.9, 0.55) * CFrame.Angles(math.rad(-12), 0, 0), LC.Screen, M.Glass)
	text(screen, Enum.NormalId.Front, { { Text = Texts.Console, Size = 22, Color = T.Green } })
	for i = -1, 1 do
		Panel(m, "Key", Vector3.new(0.6, 0.12, 0.35), cf * CFrame.new(i * 0.9, 3.02, -0.4) * CFrame.Angles(math.rad(14), 0, 0), if i == 0 then N.Gold else LC.Dado, M.Smooth, { CanCollide = false })
	end
	return m
end

---------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------

local function robot(parent, cf: CFrame, color: Color3, s: number)
	local m = NanoKit.Model(parent, "Robot")
	Panel(m, "Legs", Vector3.new(1.6, 2.6, 1) * s, cf * CFrame.new(0, 1.5 * s, 0), LC.Steel, M.Metal)
	Panel(m, "Body", Vector3.new(2.4, 2.4, 1.4) * s, cf * CFrame.new(0, 4 * s, 0), LC.Beam, M.Metal)
	Panel(m, "Chest", Vector3.new(1.6, 1, 0.1) * s, cf * CFrame.new(0, 4.2 * s, -0.75 * s), N.Gold, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Arm", Vector3.new(0.6, 2.4, 0.6) * s, cf * CFrame.new(sx * 1.6 * s, 3.8 * s, 0), LC.Steel, M.Metal)
	end
	local head = Panel(m, "Head", Vector3.new(1.4, 1.2, 1.3) * s, cf * CFrame.new(0, 5.9 * s, 0), LC.Steel, M.Metal)
	Panel(m, "Visor", Vector3.new(1.1, 0.3, 0.1) * s, cf * CFrame.new(0, 5.95 * s, -0.66 * s), color, M.Neon, { CanCollide = false })
	return m, head
end

-- NPC: model, dais, name plate, the hidden "!" marker (QuestGuide shows
-- it) and the "Говорить" prompt (Action = Talk).
local function npc(id: string, modelName: string, cf: CFrame)
	local def = Config.Npcs[id]
	local m = NanoKit.Model(root, "NPC_" .. id)
	local height = if id == "GateKeeper" then 8 else 7
	local prop = Assets.Prop(modelName, height)
	local top
	if prop then
		Assets.PlaceOnGround(prop, cf)
		prop.Parent = m
		local box, size = prop:GetBoundingBox()
		top = box.Position.Y + size.Y / 2
	else
		local _, head = robot(m, cf, def.Color, height / 7)
		top = head.Position.Y + head.Size.Y / 2
	end
	NanoKit.Cylinder(m, "Dais", 0.3, 5, CFrame.new(cf.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), LC.Steel, M.Plate)
	flatDisc(m, "DaisRing", 5.3, 0.2, cf.Position, def.Color:Lerp(LC.Steel, 0.5), M.Smooth)
	local anchor = Panel(m, "Anchor", Vector3.new(1, 1, 1), CFrame.new(cf.Position.X, top + 0.5, cf.Position.Z), LC.Steel, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	local plate = Instance.new("BillboardGui")
	plate.Name = "NamePlate"
	plate.Size = UDim2.fromOffset(220, 46)
	plate.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
	plate.MaxDistance = 80
	plate.LightInfluence = 0
	plate.Parent = anchor
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = T.PanelDark
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = plate
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = def.Color
	stroke.Thickness = 1.5
	stroke.Parent = frame
	for i, line in ipairs({ { def.Name, 18, N.Gold }, { def.Title, 13, def.Color } }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 0, if i == 1 then 0.05 else 0.55, 0)
		label.Size = UDim2.new(1, 0, if i == 1 then 0.5 else 0.4, 0)
		label.Font = T.Font
		label.TextSize = line[2]
		label.TextColor3 = line[3]
		label.Text = line[1]
		label.Parent = frame
	end
	local marker = Instance.new("BillboardGui")
	marker.Name = "Marker"
	marker.Size = UDim2.fromOffset(40, 50)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	marker.MaxDistance = 250
	marker.AlwaysOnTop = true
	marker.Enabled = false
	marker.LightInfluence = 0
	marker.Parent = anchor
	local bang = Instance.new("TextLabel")
	bang.Name = "Bang"
	bang.Size = UDim2.fromScale(1, 1)
	bang.BackgroundTransparency = 1
	bang.Font = T.FontTitle or T.Font
	bang.TextScaled = true
	bang.TextColor3 = N.Gold
	bang.Text = "!"
	bang.Parent = marker
	local bangStroke = Instance.new("UIStroke")
	bangStroke.Thickness = 3
	bangStroke.Parent = bang
	m:SetAttribute("Npc", id)
	local prompt = WorldKit.Prompt(anchor, L.Prompts.Talk, def.Name, { Action = "Talk", Npc = id }, 12)
	prompt.RequiresLineOfSight = false
	return m, prompt
end

---------------------------------------------------------------------
-- The island: deck, plinth, atrium floor, terrace, rim wall
---------------------------------------------------------------------

local function buildGround()
	local m = NanoKit.Model(root, "Ground")
	local R = CD.IslandRadius
	-- the deck everyone walks on (ground level) and the dark plinth under it
	local deck = NanoKit.Cylinder(m, "Deck", 1, R * 2, CFrame.new(C + Vector3.new(0, -0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), K.Floor, M.Concrete)
	deck.CastShadow = false
	NanoKit.Cylinder(m, "Plinth", CD.PlinthDepth, R * 2 - 1, CFrame.new(C + Vector3.new(0, -1 - CD.PlinthDepth / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), K.WallDark, M.Metal)
	-- lit windows around the plinth (sheet 01: warm slits along the island side)
	local n = math.floor(R * 2 * math.pi / CD.PlinthWindowEvery)
	for i = 0, n - 1 do
		local theta = (i + 0.5) / n * 360
		local cf = faceIn(theta, R - 0.45, -CD.PlinthDepth * 0.45)
		Panel(m, "PlinthWindow", Vector3.new(2.2, 3.4, 0.2), cf * CFrame.new(0, 0, 0.1) * CFrame.Angles(0, math.rad(180), 0), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
	end
	ring(m, "PlinthBand", R - 0.6, R + 0.4, -2.4, -1.4, K.Trim, M.Metal)
	-- the spawn forecourt sticks out south of the circle (square front)
	local w = CD.Corridor * 2
	local front = CD.ForecourtFront
	local back = 0
	local depth = front - back
	Panel(m, "ForecourtDeck", Vector3.new(w + 4, 1, depth), CFrame.new(at(0, -0.5, (front + back) / 2)), K.Floor, M.Concrete)
	Panel(m, "ForecourtPlinth", Vector3.new(w + 3, CD.PlinthDepth, depth - 1), CFrame.new(at(0, -1 - CD.PlinthDepth / 2, (front + back) / 2 - 0.5)), K.WallDark, M.Metal)
	-- the low front balustrade with gold cap and warm slits, low side walls
	local function lowWall(a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		Panel(m, "LowWall", Vector3.new(1.6, 3, length), cf * CFrame.new(0, 1.5, 0), K.Wall, M.Metal)
		Panel(m, "LowWallCap", Vector3.new(2, 0.4, length + 0.4), cf * CFrame.new(0, 3.2, 0), K.Trim, M.Metal)
		for k = 1, math.floor(length / 4) do
			Panel(m, "LowWallSlit", Vector3.new(1.7, 1.2, 0.5), cf * CFrame.new(0, 1.6, -length / 2 + k * 4 - 2), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		end
	end
	local half = w / 2 + 2
	local sideStart = C.Z - base.Z + math.sqrt(math.max(0, (CD.WallInner + 4) ^ 2 - half ^ 2))
	lowWall(at(-half, 0, front - 0.8), at(half, 0, front - 0.8))
	lowWall(at(-half + 0.8, 0, sideStart), at(-half + 0.8, 0, front - 0.8))
	lowWall(at(half - 0.8, 0, sideStart), at(half - 0.8, 0, front - 0.8))
	WorldKit.Invisible(m, Vector3.new(w + 6, 60, 2), at(0, 30, front + 0.5), "EdgeWall")
	-- the atrium floor pattern: light stone with darker bands and a gold ring
	local A = CD.AtriumRadius
	local f = NanoKit.Model(m, "AtriumFloor")
	local layers = {
		{ A * 2, K.FloorDark }, { A * 2 - 2, K.Floor },
		{ 74, K.FloorDark }, { 72, K.Floor },
		{ 44, K.Trim }, { 43, K.FloorDark }, { 30, K.Floor },
	}
	for i, l in ipairs(layers) do
		flatDisc(f, "Band", l[1], 0.02 * i, C, l[2], if l[2] == K.Trim then M.Metal else M.Concrete)
	end
	-- radial tile joints (thin dark lines from the dais to the edge)
	for i = 0, 15 do
		local theta = i * 22.5
		local a, b = P(theta, 22, 0.17), P(theta, A - 1.5, 0.17)
		Panel(f, "Joint", Vector3.new(0.25, 0.04, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), K.FloorDark, M.Smooth, { CanCollide = false, CastShadow = false })
	end
	return m
end

local function buildTerrace()
	local m = NanoKit.Model(root, "Terrace")
	local A, O = CD.AtriumRadius, CD.TerraceOuter
	local cuts = { corridorCut(-1, TH + 2) }
	-- the terrace (2nd level ring) with its tiled top
	ring(m, "TerraceBody", A, CD.WallInner + 0.5, 0, TH, K.Stone, M.Concrete, cuts)
	ring(m, "TerraceTop", A, O + 0.2, TH - 0.2, TH + 0.05, K.Floor, M.Concrete, cuts)
	-- gold trim along the terrace edge (over the atrium), cut at the stairs
	local stairCuts = { corridorCut(-1, TH + 2) }
	for _, s in ipairs(CD.Stairs) do
		table.insert(stairCuts, radialCut(s.Theta, s.Width + 1, A - 3, A + 3, 0, TH + 3))
	end
	ring(m, "EdgeTrim", A - 0.6, A + 0.6, TH - 0.5, TH + 0.25, K.Trim, M.Metal, stairCuts)
	ring(m, "EdgeBand", A - 0.35, A + 0.2, TH - 2.6, TH - 2.1, K.Slit, M.Neon, stairCuts)
	-- pilasters on the retaining face (towards the atrium) with warm slits
	local gaps = {}
	for _, s in ipairs(CD.Stairs) do
		table.insert(gaps, { s.Theta, math.deg(math.asin((s.Width / 2 + 2) / A)) })
	end
	table.insert(gaps, { 180, math.deg(math.asin((CD.Corridor + 1.5) / A)) })
	local step = 360 / CD.Pilasters
	for i = 0, CD.Pilasters - 1 do
		local theta = i * step + step / 2
		if not inGap(theta, gaps) then
			local cf = faceIn(theta, A - 0.6, 0)
			Panel(m, "Pilaster", Vector3.new(2.6, TH - 0.6, 1.2), cf * CFrame.new(0, (TH - 0.6) / 2, 0), K.Wall, M.Metal)
			Panel(m, "PilasterSlit", Vector3.new(0.4, TH * 0.55, 0.12), cf * CFrame.new(0, TH * 0.42, -0.65), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		end
	end
	-- the glass railing along the edge, open at the stairs, the bridge and the corridor
	local railGaps = table.clone(gaps)
	for _, side in ipairs({ -1, 1 }) do
		local x = math.sqrt(A * A - CD.Bridge.Z ^ 2)
		table.insert(railGaps, { (360 + side * math.deg(math.atan2(x, CD.Bridge.Z))) % 360, math.deg(math.asin((CD.Bridge.Width / 2 + 0.5) / A)) })
	end
	local n = 96
	for i = 0, n - 1 do
		local t0, t1 = i / n * 360, (i + 1) / n * 360
		if not inGap((t0 + t1) / 2, railGaps) then
			railing(m, P(t0, A + 0.9, TH), P(t1, A + 0.9, TH))
		end
	end
	-- stairs from the atrium up to the terrace
	for _, s in ipairs(CD.Stairs) do
		local foot = P(s.Theta, A - s.Run, 0)
		local top = P(s.Theta, A, 0)
		stairs(m, foot, (top - foot).Unit, s.Width, TH, s.Run)
	end
	-- the bridge across the north part of the atrium (2nd level)
	local B = CD.Bridge
	local x = math.sqrt(A * A - B.Z ^ 2) + 1
	local bz = C.Z - B.Z
	local bm = NanoKit.Model(m, "Bridge")
	Panel(bm, "Deck", Vector3.new(x * 2, 0.8, B.Width), CFrame.new(Vector3.new(C.X, C.Y + TH - 0.4, bz)), K.Floor, M.Concrete)
	Panel(bm, "Girder", Vector3.new(x * 2, 1.6, B.Width - 2), CFrame.new(Vector3.new(C.X, C.Y + TH - 1.6, bz)), K.Wall, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		local zz = bz + side * B.Width / 2
		railing(bm, Vector3.new(C.X - x + 1, C.Y + TH, zz), Vector3.new(C.X + x - 1, C.Y + TH, zz))
		NanoKit.Strip(bm, Vector3.new(C.X - x, C.Y + TH - 2.5, zz), Vector3.new(C.X + x, C.Y + TH - 2.5, zz), K.Slit, 0.16)
	end
	for _, sx in ipairs(B.Columns) do
		NanoKit.Column(bm, "Column", TH - 1, 2, Vector3.new(C.X + sx, C.Y, bz), K.Wall, M.Metal)
		NanoKit.Column(bm, "ColumnBase", 1, 3, Vector3.new(C.X + sx, C.Y, bz), K.Trim, M.Metal)
	end
	-- crest banners hanging under the bridge, facing the spawn
	for _, sx in ipairs({ -12, 12 }) do
		hangingBanner(bm, CFrame.new(Vector3.new(C.X + sx, C.Y + TH - 2.6, bz + B.Width / 2 - 0.6)) * CFrame.Angles(0, math.rad(180), 0), 4, 5)
	end
	return m
end

local function buildRimWall()
	local m = NanoKit.Model(root, "RimWall")
	local cuts = { corridorCut(-1, CD.WallTop + 3) }
	local I, O = CD.WallInner, CD.WallOuter
	ring(m, "Wall", I, O, 0, CD.WallTop, K.Wall, M.Metal, cuts)
	ring(m, "WallCap", I - 0.4, O + 0.4, CD.WallTop, CD.WallTop + 0.8, K.WallLight, M.Metal, cuts)
	ring(m, "WallGold", I - 0.3, O + 0.3, CD.WallTop - 1.6, CD.WallTop - 1, K.Trim, M.Metal, cuts)
	ring(m, "WallDado", I - 0.3, I + 0.2, TH, TH + 2, K.WallDark, M.Metal, cuts)
	-- warm light slits on both faces (inner: above the halls' signs, outer: windows)
	local signs = {}
	for _, theta in pairs(CD.Signs) do
		table.insert(signs, { theta, 9 })
	end
	table.insert(signs, { 0, 22 }) -- the portal
	local corridorGap = { { 180, math.deg(math.asin((CD.Corridor + 2) / I)) + 1 } }
	local n = math.floor(360 / CD.SlitEvery)
	for i = 0, n - 1 do
		local theta = (i + 0.5) * CD.SlitEvery
		if not inGap(theta, corridorGap) then
			if not inGap(theta, signs) then
				local cf = faceIn(theta, I - 0.08, TH)
				Panel(m, "Slit", Vector3.new(0.5, 5.5, 0.15), cf * CFrame.new(0, 6.4, 0), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
			end
			local out = faceIn(theta, O + 0.08, 0)
			for _, y in ipairs(CD.WindowRows) do
				Panel(m, "Window", Vector3.new(1.4, 3.2, 0.15), out * CFrame.new(0, y, 0), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
			end
		end
	end
	-- buttresses on the outer face (sheet 01: the segmented, lit outer wall)
	local nb = math.floor(360 / CD.ButtressEvery)
	for i = 0, nb - 1 do
		local theta = (i + 0.5) * CD.ButtressEvery
		if not inGap(theta, { { 180, 16 } }) then
			local cf = faceIn(theta, O + 1.2, -CD.PlinthDepth)
			local h = CD.WallTop + CD.PlinthDepth + 2.5
			Panel(m, "Buttress", Vector3.new(4.4, h, 3), cf * CFrame.new(0, h / 2, 0), K.WallDark, M.Metal)
			Panel(m, "ButtressCap", Vector3.new(5, 0.8, 3.6), cf * CFrame.new(0, h + 0.4, 0), K.Trim, M.Metal)
			Panel(m, "ButtressSlit", Vector3.new(0.5, h * 0.55, 0.14), cf * CFrame.new(0, h * 0.5, 1.55), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		end
	end
	-- the cut ends at the corridor get thick end posts with slits
	for _, sx in ipairs({ -1, 1 }) do
		local zIn = C.Z + math.sqrt(I * I - CD.Corridor ^ 2)
		local zOut = C.Z + math.sqrt(O * O - CD.Corridor ^ 2)
		local p = Vector3.new(C.X + sx * (CD.Corridor + 1.4), C.Y, (zIn + zOut) / 2)
		local h = CD.WallTop + 4
		pylon(m, CFrame.lookAt(p, p + Vector3.new(0, 0, 1)), h, 3.6)
	end
	-- nobody jumps over the wall (it is the island edge)
	local k = 48
	for i = 0, k - 1 do
		local theta = (i + 0.5) / k * 360
		if not inGap(theta, corridorGap) then
			local cf = faceIn(theta, O + 1, CD.WallTop + 40)
			WorldKit.Invisible(m, Vector3.new(2 * (O + 1) * math.sin(math.pi / k) + 0.5, 80, 1), cf.Position, "EdgeWall").CFrame = cf
		end
	end
	return m
end

---------------------------------------------------------------------
-- Spawn and atrium
---------------------------------------------------------------------

local function buildSpawn()
	local m = NanoKit.Model(root, "Spawn")
	local p = at(0, 0, 0)
	-- the cyan spawn ring (sheet 01)
	flatDisc(m, "SpawnPlate", 15, 0.05, p, LC.Steel, M.Plate)
	flatDisc(m, "SpawnRing", 12, 0.07, p, CD.SpawnRing, M.Neon).Transparency = 0.2
	flatDisc(m, "SpawnInner", 10.6, 0.09, p, LC.Steel, M.Plate)
	flatDisc(m, "SpawnCore", 4, 0.11, p, CD.SpawnRing:Lerp(LC.Steel, 0.5), M.Smooth)
	local light = Panel(m, "SpawnLight", Vector3.new(0.4, 0.4, 0.4), CFrame.new(p + Vector3.new(0, 6, 0)), CD.SpawnRing, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	WorldKit.Light(light, CD.SpawnRing, 16, 0.8)
	-- two pylons with crest banners in front of the spawn
	for _, sx in ipairs({ -1, 1 }) do
		local pp = at(sx * CD.SpawnPylons.X, 0, CD.SpawnPylons.Z)
		local cf = CFrame.lookAt(pp, pp + Vector3.new(0, 0, 1))
		pylon(m, cf, CD.SpawnPylons.Height, 5)
		hangingBanner(m, cf * CFrame.new(0, CD.SpawnPylons.Height - 2, -2.7), 3.6, 9)
		sakura(m, at(sx * (CD.Corridor - 4), 0, 6), 4.4)
	end
	-- the city title over the corridor, between the two end posts
	local zIn = C.Z + math.sqrt(CD.WallInner ^ 2 - CD.Corridor ^ 2)
	local gate = CFrame.lookAt(Vector3.new(C.X, C.Y, zIn), Vector3.new(C.X, C.Y, zIn + 10))
	Panel(m, "Lintel", Vector3.new(CD.Corridor * 2 + 5, 2.4, 3), gate * CFrame.new(0, CD.WallTop + 1.2, 0), K.Wall, M.Metal)
	Panel(m, "LintelGold", Vector3.new(CD.Corridor * 2 + 5.4, 0.5, 3.3), gate * CFrame.new(0, CD.WallTop - 0.1, 0), K.Trim, M.Metal)
	signPlate(m, gate * CFrame.new(0, CD.WallTop + 1.2, -1.7), Vector2.new(22, 2.2), { { Text = Texts.Title, Size = 70, Color = N.Gold } })
	return m
end

local function buildAtrium()
	local m = NanoKit.Model(root, "Atrium")
	-- 2: the hologram cube on its dais in the centre
	HubIsland.Hologram(m, C)
	local D = CD.Atrium
	for _, theta in ipairs(D.Trees) do
		sakura(m, P(theta, D.TreeRadius, 0), 5)
	end
	for _, theta in ipairs(D.Benches) do
		local p = P(theta, D.BenchRadius, 0)
		NanoKit.Bench(m, CFrame.lookAt(p, Vector3.new(C.X, p.Y, C.Z))) -- facing the hologram
	end
	for _, theta in ipairs(D.Lamps) do
		lampPost(m, P(theta, D.LampRadius, 0))
	end
	-- sakuras along the foot of the terrace wall (between the stairs)
	for _, theta in ipairs(D.WallTrees) do
		sakura(m, P(theta, CD.AtriumRadius - 4.5, 0), 4.4)
	end
	-- small planters around the hologram dais
	for _, theta in ipairs(D.DaisPlanters) do
		local p = P(theta, D.DaisPlanterRadius, 0)
		local cf = CFrame.lookAt(p, Vector3.new(C.X, p.Y, C.Z))
		Panel(m, "DaisPlanter", Vector3.new(5, 1.4, 2.2), cf * CFrame.new(0, 0.7, 0), K.Wall, M.Metal)
		Panel(m, "DaisPlanterRim", Vector3.new(5.2, 0.25, 2.4), cf * CFrame.new(0, 1.45, 0), K.Trim, M.Metal)
		for k = -1, 1 do
			Panel(m, "Flower", Vector3.new(1.6, 1.4, 1.6), cf * CFrame.new(k * 1.5, 1.9, 0), if k == 0 then Color3.fromRGB(236, 168, 196) else Color3.fromRGB(84, 138, 72), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	return m
end

---------------------------------------------------------------------
-- 7 Gate hall (north)
---------------------------------------------------------------------

local function buildGates()
	local G = CD.Gate
	local m = NanoKit.Model(root, "Gates")
	local theta = CD.Signs.Gates
	-- the dais in front of the wall with two steps
	local dais = faceIn(theta, G.R, TH)
	Panel(m, "Dais", Vector3.new(G.DaisWidth, G.DaisHeight, G.DaisDepth), dais * CFrame.new(0, G.DaisHeight / 2, 0), K.WallDark, M.Plate)
	Panel(m, "DaisEdge", Vector3.new(G.DaisWidth + 0.2, 0.25, 0.5), dais * CFrame.new(0, G.DaisHeight, -G.DaisDepth / 2 + 0.2), K.Trim, M.Metal)
	for k = 1, 2 do
		local h = G.DaisHeight * (3 - k) / 3
		Panel(m, "DaisStep", Vector3.new(G.DaisWidth - k * 2, h, 1.6), dais * CFrame.new(0, h / 2, -G.DaisDepth / 2 - 1.6 * k + 0.8), K.Floor, M.Concrete)
	end
	-- the ring portal (segments) with a warm inner line and nodes
	local R = G.Radius
	local center = dais * CFrame.new(0, G.DaisHeight + R + 1, 0)
	local GR = Config.HubIsland.GateRing
	for i = 0, GR.Segments - 1 do
		local a = (i + 0.5) / GR.Segments * math.pi * 2
		local seg = R * math.pi * 2 / GR.Segments + 0.3
		local pcf = center * CFrame.Angles(0, 0, a) * CFrame.new(R, 0, 0)
		Panel(m, "Ring", Vector3.new(GR.Thick, seg, GR.Depth), pcf, K.Wall, M.Metal, { CanCollide = false })
		Panel(m, "RingLine", Vector3.new(0.35, seg, 0.3), pcf * CFrame.new(-GR.Thick / 2 - 0.05, 0, -GR.Depth / 2 - 0.1), K.Slit, M.Neon, { CanCollide = false })
		Panel(m, "RingGold", Vector3.new(0.4, seg, GR.Depth + 0.2), pcf * CFrame.new(GR.Thick / 2, 0, 0), K.Trim, M.Metal, { CanCollide = false })
		if i % 5 == 0 then
			Panel(m, "RingNode", Vector3.new(GR.Thick + 1.6, 2.4, GR.Depth + 1), pcf, K.WallDark, M.Metal, { CanCollide = false })
		end
	end
	-- the violet field (players walk into it: hub.Portal)
	local colors = Config.HubIsland.PortalColors
	local field = NanoKit.Cylinder(m, "PortalField", 0.6, R * 2 - 1.5, center * CFrame.Angles(0, math.rad(90), 0), colors[1], Enum.Material.ForceField)
	field.CanCollide = false
	field.CastShadow = false
	field.Transparency = 0.15
	field:SetAttribute("Portal", true)
	local glow = NanoKit.Cylinder(m, "PortalGlow", 0.2, R * 2 - 2, center * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.rad(90), 0), colors[2], M.Neon)
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CastShadow = false
	glow.Transparency = 0.55
	NanoKit.Tag(glow, "Pulse", { Period = 2.6 })
	local core = NanoKit.Cylinder(m, "PortalCore", 0.25, R * 0.9, center * CFrame.new(0, 0, 0.4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(230, 210, 255), M.Neon)
	core.CanCollide = false
	core.CanQuery = false
	core.Transparency = 0.7
	NanoKit.Tag(core, "Pulse", { Period = 1.8 })
	WorldKit.Light(field, colors[1], 34, 2)
	-- the rank letters E D C B A S over the ring, in hexagon badges
	local ranks = Config.Gates.Ranks
	local spacing = GR.BadgeSize + 1.4
	for i, rank in ipairs(ranks) do
		local x = -(i - (#ranks + 1) / 2) * spacing -- E on the left as seen from the atrium
		local y = R + GR.BadgeSize * 1.1 - math.abs(x) * 0.22
		local bcf = center * CFrame.new(x, y, -0.6)
		local color = GR.RankColors[rank] or N.Gold
		NanoKit.Cylinder(m, "Badge", 0.6, GR.BadgeSize + 0.6, bcf * CFrame.Angles(0, math.rad(90), 0), K.Wall, M.Metal)
		Panel(m, "BadgeFace", Vector3.new(GR.BadgeSize * 0.8, GR.BadgeSize * 0.8, 0.2), bcf * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(24, 24, 30), M.Smooth)
		Panel(m, "BadgeRim", Vector3.new(GR.BadgeSize * 0.86, GR.BadgeSize * 0.86, 0.12), bcf * CFrame.new(0, 0, -0.32) * CFrame.Angles(0, 0, math.rad(45)), color, M.Neon, { CanCollide = false })
		local label = Panel(m, "BadgeLetter", Vector3.new(GR.BadgeSize * 0.7, GR.BadgeSize * 0.7, 0.1), bcf * CFrame.new(0, 0, -0.56), color, M.Smooth, { Transparency = 1, CanCollide = false })
		WorldKit.SurfaceText(label, Enum.NormalId.Front, { { Text = rank, Size = 120, Color = color } }, 60)
	end
	-- two tall pylons beside the ring with crest banners, lamps on the dais
	for _, sx in ipairs({ -1, 1 }) do
		local pcf = dais * CFrame.new(sx * (R + 6), G.DaisHeight, 1)
		pylon(m, pcf, G.PylonHeight, 5)
		hangingBanner(m, pcf * CFrame.new(0, G.PylonHeight - 3, -2.7), 3.6, 10)
		local lamp = Panel(m, "Lamp", Vector3.new(1.8, 0.6, 1.2), pcf * CFrame.new(-sx * 3, G.PylonHeight * 0.7, -2), LC.Steel, M.Metal)
		spot(lamp, Enum.NormalId.Bottom, 30, 1.4, 100, K.Slit)
	end
	-- towers of the citadel behind the gate (scenery, as on the sheet)
	for _, t in ipairs(G.Towers) do
		local p = P(theta + t[1], t[2], -CD.PlinthDepth)
		local w, h = t[3], t[4] + CD.PlinthDepth
		local tm = NanoKit.Model(m, "Tower")
		Panel(tm, "Body", Vector3.new(w, h, w), CFrame.new(p + Vector3.new(0, h / 2, 0)), K.Wall, M.Metal, { CastShadow = false })
		Panel(tm, "Top", Vector3.new(w * 0.7, h * 0.12, w * 0.7), CFrame.new(p + Vector3.new(0, h + h * 0.06, 0)), K.WallLight, M.Metal, { CastShadow = false })
		Panel(tm, "Crown", Vector3.new(w + 0.6, 0.8, w + 0.6), CFrame.new(p + Vector3.new(0, h, 0)), K.Trim, M.Metal, { CastShadow = false })
		for b = 1, 4 do
			Panel(tm, "Windows", Vector3.new(w + 0.1, 0.6, w + 0.1), CFrame.new(p + Vector3.new(0, h * b / 5, 0)), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		end
		for _, d in ipairs(tm:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
	end
	return field
end

-- The Red Gates (event, GateService): a smaller arch on the terrace.
-- Field, curtains and light stay hidden until the event.
local function buildRedGate()
	local R = Config.RedGate
	local m = NanoKit.Model(root, "RedGate")
	local cf = faceIn(CD.Signs.RedGate, CD.TerraceOuter - 4, TH)
	local w, h = 12, 16
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Pylon", Vector3.new(3, h + 3, 4), cf * CFrame.new(side * (w / 2 + 1.5), (h + 3) / 2, 0), K.Wall, M.Metal)
		Panel(m, "PylonFace", Vector3.new(1.6, h - 2, 0.3), cf * CFrame.new(side * (w / 2 + 1.5), h / 2, -2.1), LC.Steel, M.Plate)
	end
	Panel(m, "Lintel", Vector3.new(w + 6, 3, 4), cf * CFrame.new(0, h + 1.5, 0), K.Wall, M.Metal)
	Panel(m, "LintelGold", Vector3.new(w + 6.4, 0.4, 4.3), cf * CFrame.new(0, h + 3.1, 0), K.Trim, M.Metal)
	Panel(m, "Back", Vector3.new(w, h, 0.6), cf * CFrame.new(0, h / 2, 1.7), LC.Tunnel, M.Smooth)
	local plate = Panel(m, "Sign", Vector3.new(w + 4, 2.4, 0.3), cf * CFrame.new(0, h + 4.6, -0.4), T.PanelDark, M.Smooth, { CanCollide = false })
	text(plate, Enum.NormalId.Front, { { Text = R.Texts.Name, Size = 56, Color = R.Color } })
	local parts = {}
	local field = Panel(m, "RedField", Vector3.new(w, h, 0.6), cf * CFrame.new(0, h / 2, -0.6), R.Color, Enum.Material.ForceField, { CanCollide = false, Transparency = 1, CastShadow = false })
	field:SetAttribute("OnTransparency", 0.2)
	table.insert(parts, field)
	for i = 1, 3 do
		local curtain = Panel(m, "RedCurtain", Vector3.new(w / 3 + 0.4, h - 0.4, 0.1), cf * CFrame.new(-w / 2 + w * (i - 0.5) / 3, h / 2, -0.9 - (i % 2) * 0.2), R.Color, M.Neon, { CanCollide = false, CanQuery = false, Transparency = 1, CastShadow = false })
		curtain:SetAttribute("OnTransparency", 0.82)
		NanoKit.Tag(curtain, "Pulse", { Period = 1.4 + i * 0.3 })
		table.insert(parts, curtain)
	end
	local light = WorldKit.Light(field, R.Color, 26, 1.6)
	light.Enabled = false
	local prompt = WorldKit.Prompt(field, R.Texts.Enter, R.Texts.Name, { Action = "RedGate" }, 12)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	return { Model = m, Parts = parts, Prompt = prompt, Light = light }
end

-- 8 leaderboards and 9 the quest board: free-standing boards on legs.
local function board(cf: CFrame, name: string, size: Vector2)
	local m = NanoKit.Model(root, name)
	local y = 2.4 + size.Y / 2
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Leg", Vector3.new(0.8, y + size.Y / 2, 0.8), cf * CFrame.new(sx * (size.X / 2 - 0.6), (y + size.Y / 2) / 2, 0.4), K.Wall, M.Metal)
	end
	Panel(m, "Frame", Vector3.new(size.X + 0.8, size.Y + 0.8, 0.4), cf * CFrame.new(0, y, 0.2), K.Trim, M.Metal)
	local face = Panel(m, "Board", Vector3.new(size.X, size.Y, 0.3), cf * CFrame.new(0, y, -0.1), T.PanelDark, M.Smooth)
	local lamp = Panel(m, "Lamp", Vector3.new(4, 0.4, 0.7), cf * CFrame.new(0, y + size.Y / 2 + 1, -1), LC.Steel, M.Metal)
	spot(lamp, Enum.NormalId.Bottom, 14, 0.8, 110)
	return m, face
end

local function leaderboard(cf: CFrame, def)
	local _, face = board(cf, "Leaderboard_" .. def.Kind, Vector2.new(9, 11.6))
	local lines = { { Name = "Title", Text = def.Title, Size = 30, Color = N.Gold } }
	for i = 1, Config.Leaderboards.Top do
		table.insert(lines, { Name = "Row" .. i, Text = i .. ". —", Size = 18 })
	end
	return WorldKit.SurfaceText(face, Enum.NormalId.Front, lines, 50)
end

---------------------------------------------------------------------
-- 6 Forge (north-east)
---------------------------------------------------------------------

-- Owner model without neon edges / glows (they read as cheap outlines).
local function tame(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Material = M.Metal
			d.Color = LC.Steel:Lerp(d.Color, 0.15)
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	return model
end

local function buildForge()
	local F = CD.Forge
	local theta = CD.Signs.Forge
	local m = NanoKit.Model(root, "Forge")
	local center = P(theta, F.R, TH)
	local face = CFrame.lookAt(center, Vector3.new(C.X, center.Y, C.Z))
	-- the round work floor
	NanoKit.Cylinder(m, "Platform", 0.6, F.Platform, CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), K.WallDark, M.Plate)
	flatDisc(m, "PlatformRing", F.Platform + 1, 0.1, center, K.Trim, M.Metal) -- shows as a gold rim
	-- the anvil with the gold manipulator arm (sheet 01 / 02)
	local anvilCf = face * CFrame.new(0, 0.6, 0)
	Panel(m, "AnvilBase", Vector3.new(4, 2.6, 3), anvilCf * CFrame.new(0, 1.3, 0), K.Wall, M.Metal)
	local anvil = Panel(m, "Anvil", Vector3.new(5, 0.7, 3.4), anvilCf * CFrame.new(0, 2.95, 0), LC.Steel, M.Plate)
	Panel(m, "AnvilHorn", Vector3.new(1.6, 0.6, 1.2), anvilCf * CFrame.new(3.2, 2.95, 0), LC.Steel, M.Plate)
	local sparksTemplate = Instance.new("ParticleEmitter")
	sparksTemplate.Name = "Sparks"
	sparksTemplate.Color = ColorSequence.new(N.Gold, Color3.new(1, 1, 1))
	sparksTemplate.LightEmission = 0.8
	sparksTemplate.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparksTemplate.Lifetime = NumberRange.new(0.4, 0.9)
	sparksTemplate.Speed = NumberRange.new(8, 16)
	sparksTemplate.SpreadAngle = Vector2.new(70, 70)
	sparksTemplate.Rate = 0
	sparksTemplate.Parent = anvil
	-- the arm: a post behind the anvil, two gold segments, the hammer head
	local post = anvilCf * CFrame.new(5, 0, 6)
	NanoKit.Column(m, "ArmBase", 1.6, 5, post.Position, K.WallDark, M.Metal)
	NanoKit.Column(m, "ArmBaseGold", 0.4, 5.3, post.Position + Vector3.new(0, 1.5, 0), K.Trim, M.Metal)
	local shoulder = (post * CFrame.new(0, 3, 0)).Position
	local elbow = (post * CFrame.new(-1.5, 11.5, -1)).Position
	local wrist = (anvilCf * CFrame.new(0.3, 8.6, 0)).Position
	for _, seg in ipairs({ { shoulder, elbow, 1.8 }, { elbow, wrist, 1.4 } }) do
		local a, b, w = seg[1], seg[2], seg[3]
		Panel(m, "ArmSegment", Vector3.new(w, w, (b - a).Magnitude + 0.6), CFrame.lookAt((a + b) / 2, b), F.Arm, M.Metal)
		Panel(m, "ArmPiston", Vector3.new(0.4, 0.4, (b - a).Magnitude * 0.8), CFrame.lookAt((a + b) / 2, b) * CFrame.new(w / 2 + 0.3, 0, 0), K.WallDark, M.Metal)
	end
	for _, j in ipairs({ shoulder, elbow, wrist }) do
		Panel(m, "ArmJoint", Vector3.new(2.4, 2.4, 2.4), CFrame.new(j), K.WallDark, M.Metal, { Shape = Enum.PartType.Ball })
	end
	local hammer = Panel(m, "Hammer", Vector3.new(2.4, 2.8, 2.4), CFrame.new(wrist - Vector3.new(0, 2.6, 0)), K.Wall, M.Metal)
	Panel(m, "HammerFace", Vector3.new(2.6, 0.5, 2.6), CFrame.new(wrist - Vector3.new(0, 4, 0)), K.Trim, M.Metal, { CanCollide = false })
	NanoKit.Tag(hammer, "Bob", { Amplitude = 0.8, Period = 1.8 })
	-- the furnace beside the anvil: a graphite block with a glowing mouth
	local fcf = face * CFrame.new(-7, 0.6, 1.5)
	Panel(m, "Furnace", Vector3.new(6, 7, 5), fcf * CFrame.new(0, 3.5, 0), K.Wall, M.Metal)
	Panel(m, "FurnaceGold", Vector3.new(6.3, 0.5, 5.3), fcf * CFrame.new(0, 7.1, 0), K.Trim, M.Metal)
	Panel(m, "FurnaceMouth", Vector3.new(3.4, 2.6, 0.2), fcf * CFrame.new(0, 2.6, -2.45), Color3.fromRGB(255, 120, 40), M.Neon, { CanCollide = false })
	Panel(m, "FurnaceBrow", Vector3.new(4.2, 0.5, 0.6), fcf * CFrame.new(0, 4.2, -2.5), K.Trim, M.Metal)
	NanoKit.Column(m, "Chimney", 8, 2, (fcf * CFrame.new(0, 7.3, 0.8)).Position, K.WallDark, M.Metal)
	NanoKit.Column(m, "ChimneyRing", 0.4, 2.4, (fcf * CFrame.new(0, 14.6, 0.8)).Position, K.Trim, M.Metal)
	local hearthPos = (fcf * CFrame.new(0, 2.6, -1.4)).Position
	local hearth = Panel(m, "Hearth", Vector3.new(2.2, 2.2, 2.2), CFrame.new(hearthPos), Color3.fromRGB(255, 120, 40), M.Neon, { CanCollide = false, Shape = Enum.PartType.Ball, Transparency = 0.15 })
	local glowLight = WorldKit.Light(hearth, Color3.fromRGB(255, 130, 60), 26, 1.8)
	glowLight.Name = "Glow"
	local fire = Instance.new("Fire")
	fire.Name = "Fire"
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 200, 80)
	fire.Size = 5
	fire.Heat = 6
	fire.Parent = hearth
	local hearthSparks = sparksTemplate:Clone()
	hearthSparks.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80), Color3.new(1, 1, 1))
	hearthSparks.Parent = hearth
	NanoKit.Tag(hearth, "Pulse", { Period = 1.6 })
	-- the console with the forge prompt, in front towards the atrium
	local cp = P(theta + F.ConsoleShift, F.R - 9, TH)
	local c = console(m, CFrame.lookAt(cp, Vector3.new(C.X, cp.Y, C.Z))) -- the screen faces whoever comes from the atrium
	local prompt = WorldKit.Prompt(c:FindFirstChild("Base"), L.Prompts.Forge, "", { Action = "OpenForge" }, 12)
	-- conveyors along the wall with sliding crates, crate stacks at the ends
	for _, span in ipairs(F.Belts) do
		local a, b = P(theta + span[1], CD.TerraceOuter - 4, TH), P(theta + span[2], CD.TerraceOuter - 4, TH)
		local len = (b - a).Magnitude
		local bcf = CFrame.lookAt((a + b) / 2, b)
		Panel(m, "BeltFrame", Vector3.new(4, 2, len), bcf * CFrame.new(0, 1, 0), K.Wall, M.Metal)
		Panel(m, "Belt", Vector3.new(3.4, 0.2, len), bcf * CFrame.new(0, 2.1, 0), Color3.fromRGB(30, 30, 32), M.Smooth)
		for _, side in ipairs({ -1, 1 }) do
			Panel(m, "Guard", Vector3.new(0.3, 0.6, len), bcf * CFrame.new(side * 1.9, 2.4, 0), F.Arm, M.Metal)
		end
		for i = 0, 3 do
			local box = Panel(m, "BeltCrate", Vector3.new(1.8, 1.6, 1.8), bcf * CFrame.new(0, 3, len / 2 - 1), LC.Steel, M.Plate, { CanCollide = false })
			box.CFrame = CFrame.lookAt(box.Position, (bcf * CFrame.new(0, 3, -len / 2)).Position)
			NanoKit.Tag(box, "Conveyor", { Length = len - 2, Speed = 2.5, Start = i * (len - 2) / 4 })
		end
		local stack = CFrame.lookAt(b, Vector3.new(C.X, b.Y, C.Z)) * CFrame.new(0, 0, -4)
		NanoKit.Crate(m, stack, Vector3.new(3, 3, 3))
		NanoKit.Crate(m, stack * CFrame.new(3.2, 0, 0), Vector3.new(3, 3, 3))
		NanoKit.Crate(m, stack * CFrame.new(1.6, 3, 0), Vector3.new(3, 3, 3))
	end
	return prompt, m
end

---------------------------------------------------------------------
-- 4 Academy (east)
---------------------------------------------------------------------

-- A display copy of a class character (GameAssets/Avatars/<class.Avatar>).
local function displayAvatar(parent, class, cf: CFrame)
	local source = ServerStorage:FindFirstChild("GameAssets")
	source = source and source:FindFirstChild("Avatars")
	local own = source and source:FindFirstChild(class.Avatar or "")
	if not (own and own:IsA("Model")) then
		return nil
	end
	own.Archivable = true
	local model = own:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	local _, size = model:GetBoundingBox()
	if size.Y > 0.1 then
		pcall(model.ScaleTo, model, model:GetScale() * L.Academy.DisplayHeight / size.Y)
	end
	Assets.PlaceOnGround(model, cf)
	model.Name = "ClassDisplay_" .. class.Id
	model.Parent = parent
	-- the class idle stance (not a T-pose): only the root stays anchored,
	-- the limbs hang on their joints and the server plays the idle clip
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local acts = Config.Animations.Acts[class.Id]
	local clip = acts and Config.Animations.Clips[acts.Idle or ""]
	if humanoid and rootPart and clip and (clip.Id or "") ~= "" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = d == rootPart
				d.Massless = true
			end
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local animation = Instance.new("Animation")
		animation.AnimationId = clip.Id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok and track then
			track.Looped = true
			track:Play(0.2)
		end
	end
	return model
end

local function buildAcademy()
	local A = CD.Academy
	local theta = CD.Signs.Academy
	local m = NanoKit.Model(root, "Academy")
	local pedestals = {}
	for i, class in ipairs(Config.Classes) do
		local t = theta + (i - 2) * A.Spread
		local p = P(t, A.R, TH)
		local look = Vector3.new(C.X, p.Y, C.Z)
		NanoKit.Cylinder(m, "PedestalBase", 1.2, 6.4, CFrame.new(p + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), K.Wall, M.Metal)
		local top = NanoKit.Cylinder(m, "Pedestal", 0.5, 5.4, CFrame.new(p + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), LC.Steel, M.Plate)
		local rim = NanoKit.Cylinder(m, "PedestalRing", 0.2, 5.65, CFrame.new(p + Vector3.new(0, 1.45, 0)) * CFrame.Angles(0, 0, math.rad(90)), class.Color, M.Neon)
		rim.CanCollide = false
		local avatar = displayAvatar(m, class, CFrame.lookAt(p + Vector3.new(0, 1.7, 0), look + Vector3.new(0, 1.7, 0)))
		-- the glass capsule in the class color (sheet 01)
		local glass = NanoKit.Column(m, "Dome", 9, 5.6, p + Vector3.new(0, 1.7, 0), class.Color:Lerp(Color3.new(1, 1, 1), 0.6), M.Glass)
		glass.Transparency = 0.82
		glass.CanCollide = false
		NanoKit.Column(m, "DomeCap", 0.7, 6, p + Vector3.new(0, 10.7, 0), K.Wall, M.Metal)
		NanoKit.Column(m, "DomeGold", 0.25, 6.1, p + Vector3.new(0, 10.6, 0), K.Trim, M.Metal)
		local capLight = NanoKit.Column(m, "DomeLight", 0.2, 5.4, p + Vector3.new(0, 10.5, 0), class.Color, M.Neon)
		capLight.CanCollide = false
		WorldKit.Light(capLight, class.Color, 14, 1.4)
		if not avatar then
			local look2 = table.clone(Config.Weapons[1])
			look2.Class = class.Id
			look2.Rarity = "Rare"
			local ok, model = pcall(WeaponBuilder.Build, look2)
			if ok and model then
				WeaponBuilder.SetAnchored(model, true)
				local size = model:GetExtentsSize()
				pcall(model.ScaleTo, model, math.clamp(5 / math.max(size.X, size.Y, size.Z, 0.1), 0.5, 4))
				local box = model:GetBoundingBox()
				model:PivotTo(model:GetPivot() + (p + Vector3.new(0, 5, 0) - box.Position))
				model.Parent = m
				NanoKit.Tag(model, "Spin", { Speed = 30, Axis = "Y" })
			end
		end
		signPlate(m, CFrame.lookAt(p, look) * CFrame.new(0, 12.4, 0), Vector2.new(6.4, 1.6), { { Text = class.Name, Size = 44, Color = class.Color } }, true)
		pedestals[i] = top
	end
	local tp = P(theta + A.TerminalShift, A.R - 11, TH)
	local terminal = console(m, CFrame.lookAt(tp, Vector3.new(C.X, tp.Y, C.Z)))
	terminal.Name = "Terminal"
	return { Model = m, Pedestals = pedestals, Terminal = terminal }
end

---------------------------------------------------------------------
-- 5 Supply terminal (west) and the AFK portal (south-east)
---------------------------------------------------------------------

local function buildSupply()
	local S = CD.Supply
	local theta = CD.Signs.Supply
	local m = NanoKit.Model(root, "SupplyTerminal")
	local p = P(theta, S.R, TH)
	local cf = CFrame.lookAt(p, Vector3.new(C.X, p.Y, C.Z))
	local color = Config.Crystals.Color
	NanoKit.Column(m, "Dais", 0.6, 12, p, LC.Dado, M.Plate)
	local edge = NanoKit.Column(m, "DaisEdge", 0.12, 12.4, p + Vector3.new(0, 0.3, 0), K.Trim, M.Metal)
	edge.CanCollide = false
	-- the capsule machine in a glass tube with the reward core (sheet 01)
	local machine = NanoKit.Prop(m, L.Supply.Model, cf * CFrame.new(0, 0.6, 0), L.Supply.Height, function(par, c)
		local mm = NanoKit.Model(par, "CapsuleMachine")
		NanoKit.Column(mm, "Base", 1.4, 7, c.Position, K.Wall, M.Metal)
		NanoKit.Column(mm, "BaseGold", 0.3, 7.2, c.Position + Vector3.new(0, 1.3, 0), K.Trim, M.Metal)
		local tube = NanoKit.Column(mm, "Tube", 7, 6, c.Position + Vector3.new(0, 1.4, 0), color:Lerp(Color3.new(1, 1, 1), 0.6), M.Glass)
		tube.Transparency = 0.75
		NanoKit.Column(mm, "Cap", 1, 7, c.Position + Vector3.new(0, 8.4, 0), K.Wall, M.Metal)
		local orb = Panel(mm, "Core", Vector3.new(2.6, 2.6, 2.6), CFrame.new(c.Position + Vector3.new(0, 4.8, 0)), Color3.fromRGB(255, 214, 140), M.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		NanoKit.Tag(orb, "Pulse", { Period = 2 })
		for k = 0, 2 do
			NanoKit.Column(mm, "Halo", 0.15, 4.4 - k * 0.6, c.Position + Vector3.new(0, 3.4 + k * 1.4, 0), color, M.Neon).CanCollide = false
		end
		return mm
	end)
	local box = machine and select(2, machine:GetBoundingBox()) or Vector3.new(6, 9, 6)
	local bulb = Panel(m, "Light", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, box.Y + 3, -3), color, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	WorldKit.Light(bulb, color, 22, 1.6)
	local anchor = Panel(m, "PromptAnchor", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3.5, -4), color, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	local prompt = WorldKit.Prompt(anchor, L.Prompts.Supply, "", { Action = "OpenSupply" })
	-- six display capsules along the wall, one per rarity, a weapon spinning inside
	local CP = L.Capsules
	local classes = { "Blade", "Pulse", "Gunner" }
	local count = #CP.Rarities
	for i, rarityId in ipairs(CP.Rarities) do
		local rarity = Config.Rarity[rarityId]
		local t = theta + (i - (count + 1) / 2) * S.CapsuleStep
		local q = P(t, CD.TerraceOuter - 3.5, TH)
		local c = rarity and rarity.Color or T.Cyan
		NanoKit.Column(m, "CapsuleBase", 1.2, CP.Diameter + 1, q, K.Wall, M.Metal)
		local ringPart = NanoKit.Column(m, "CapsuleRing", 0.2, CP.Diameter + 0.4, q + Vector3.new(0, 1.15, 0), c, M.Neon)
		ringPart.CanCollide = false
		local glass = NanoKit.Column(m, "CapsuleGlass", CP.Height, CP.Diameter, q + Vector3.new(0, 1.2, 0), c:Lerp(Color3.new(1, 1, 1), 0.55), M.Glass)
		glass.Transparency = 0.8
		NanoKit.Column(m, "CapsuleCap", 0.8, CP.Diameter + 0.6, q + Vector3.new(0, 1.2 + CP.Height, 0), K.Wall, M.Metal)
		local topLight = NanoKit.Column(m, "CapsuleTopLight", 0.15, CP.Diameter - 0.4, q + Vector3.new(0, 1.15 + CP.Height, 0), c, M.Neon)
		topLight.CanCollide = false
		WorldKit.Light(topLight, c, 10, 1)
		local look = table.clone(Config.Weapons[1])
		look.Class = classes[(i - 1) % #classes + 1]
		look.Rarity = rarityId
		local ok, model = pcall(WeaponBuilder.Build, look)
		if ok and model then
			WeaponBuilder.SetAnchored(model, true)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			local size = model:GetExtentsSize()
			pcall(model.ScaleTo, model, math.clamp(CP.ItemSize / math.max(size.X, size.Y, size.Z, 0.1), 0.3, 4))
			local mid = q + Vector3.new(0, 1.2 + CP.Height / 2, 0)
			model:PivotTo(CFrame.new(model:GetPivot().Position) * CFrame.Angles(0, 0, math.rad(80)))
			local b = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + (mid - b.Position))
			model.WorldPivot = CFrame.new(mid) * model:GetPivot().Rotation
			model.Parent = m
			NanoKit.Tag(model, "Spin", { Speed = 24, Axis = "Y" })
		end
	end
	return m, prompt
end

-- The AFK portal on the terrace and the light bridge to the AFK island.
local function buildAfkPortal()
	local theta = CD.Signs.Afk
	local m = NanoKit.Model(root, "AfkPortal")
	local cf = faceIn(theta, CD.TerraceOuter - 3, TH)
	local color = CD.AfkColor
	-- a round gazebo-like frame (sheet 01: the ring on the AFK platform)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Post", Vector3.new(1.6, 11, 1.6), cf * CFrame.new(sx * 5, 5.5, 0), K.Wall, M.Metal)
		NanoKit.Strip(m, (cf * CFrame.new(sx * 5, 0.6, -0.85)).Position, (cf * CFrame.new(sx * 5, 10.4, -0.85)).Position, color, 0.18)
	end
	Panel(m, "Lintel", Vector3.new(11.6, 1.4, 1.8), cf * CFrame.new(0, 11.4, 0), K.Wall, M.Metal)
	Panel(m, "LintelGold", Vector3.new(11.8, 0.35, 2), cf * CFrame.new(0, 12.2, 0), K.Trim, M.Metal)
	local field = Panel(m, "Field", Vector3.new(8.4, 10, 0.2), cf * CFrame.new(0, 5.5, 0), color, M.Neon, { Transparency = 0.75, CanCollide = false })
	NanoKit.Tag(field, "Pulse", { Period = 3 })
	WorldKit.Light(field, color, 18, 1.4)
	signPlate(m, cf * CFrame.new(0, 14.2, -0.4), Vector2.new(9, 2.4), { { Text = Texts.AfkPortal, Size = 60, Color = N.Gold }, { Text = Texts.AfkPortalSub, Size = 28, Color = color } })
	local anchor = Panel(m, "PromptAnchor", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3, -3), color, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	WorldKit.Prompt(anchor, L.Prompts.Afk, "", { Action = "OpenAfk" })
	-- the bridge: from the outer wall behind the portal down to the AFK island
	local from = P(theta, CD.WallOuter + 0.5, TH - 0.5)
	local o = Config.AFK.Origin
	local dir = Vector3.new(from.X - o.X, 0, from.Z - o.Z).Unit
	local to = Vector3.new(o.X, o.Y - 0.3, o.Z) + dir * (Config.AFK.Radius - 2)
	local length = (to - from).Magnitude
	local bcf = CFrame.lookAt((from + to) / 2, to)
	Panel(m, "BridgeGlass", Vector3.new(CD.AfkBridgeWidth, 0.3, length), bcf, color, M.Glass, { Transparency = 0.6, CanCollide = false, CastShadow = false })
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Strip(m, (bcf * CFrame.new(side * CD.AfkBridgeWidth / 2, 0.2, -length / 2)).Position, (bcf * CFrame.new(side * CD.AfkBridgeWidth / 2, 0.2, length / 2)).Position, color, 0.3)
	end
	return m
end

---------------------------------------------------------------------
-- Hall pavilions: side walls out of the rim wall and a roof over the hall
---------------------------------------------------------------------

local function pavilion(theta: number, half: number, depth: number)
	local m = NanoKit.Model(root, "Pavilion")
	local O = CD.TerraceOuter
	local h = CD.Pavilion.Height
	for _, side in ipairs({ -1, 1 }) do
		local t = theta + side * half
		local cf = faceIn(t, O - depth / 2, TH)
		Panel(m, "SideWall", Vector3.new(2.6, h, depth), cf * CFrame.new(0, h / 2, 0), K.Wall, M.Metal)
		Panel(m, "SideCap", Vector3.new(3, 0.6, depth + 0.4), cf * CFrame.new(0, h + 0.3, 0), K.Trim, M.Metal)
		-- the front post with two warm slits (faces the atrium)
		local front = faceIn(t, O - depth, TH)
		Panel(m, "Post", Vector3.new(3.4, h + 1.4, 3), front * CFrame.new(0, (h + 1.4) / 2, 0), K.WallDark, M.Metal)
		for _, x in ipairs({ -0.8, 0.8 }) do
			Panel(m, "PostSlit", Vector3.new(0.35, h * 0.7, 0.12), front * CFrame.new(x, h * 0.5, -1.53), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		end
		Panel(m, "PostCap", Vector3.new(3.8, 0.6, 3.4), front * CFrame.new(0, h + 1.7, 0), K.Trim, M.Metal)
		NanoKit.Column(m, "PostLamp", 0.6, 1.4, (front * CFrame.new(0, h + 2, 0)).Position, K.Slit, M.Neon).CanCollide = false
	end
	-- the roof: straight slabs between the side walls, a gold fascia in front
	local steps = math.max(2, math.ceil(half / 6))
	for i = 0, steps - 1 do
		local t0 = theta - half + (2 * half) * i / steps
		local t1 = theta - half + (2 * half) * (i + 1) / steps
		local roofDepth = CD.Pavilion.RoofDepth
		local a, b = P(t0, O - roofDepth / 2 + 1, TH + h), P(t1, O - roofDepth / 2 + 1, TH + h)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, Vector3.new(C.X, mid.Y, C.Z))
		local w = (b - a).Magnitude + 0.6
		Panel(m, "Roof", Vector3.new(w, 1.2, roofDepth), cf * CFrame.new(0, 0, -1), K.Wall, M.Metal)
		Panel(m, "Fascia", Vector3.new(w, 1.4, 0.4), cf * CFrame.new(0, 0, -roofDepth / 2 - 1), K.Trim, M.Metal)
		local glow = Panel(m, "RoofLight", Vector3.new(w - 1, 0.15, 1.2), cf * CFrame.new(0, -0.65, -roofDepth / 2 + 2), K.Slit, M.Neon, { CanCollide = false, CastShadow = false })
		if i % 2 == 0 then
			spot(glow, Enum.NormalId.Bottom, h + 8, 1.2, 110, K.Slit)
		end
	end
	return m
end

---------------------------------------------------------------------
-- Terrace dressing: sakuras, benches, lamps, banners (tidy, by the rail)
---------------------------------------------------------------------

local function buildTerraceDecor()
	local m = NanoKit.Model(root, "TerraceDecor")
	local D = CD.TerraceDecor
	for _, theta in ipairs(D.Trees) do
		sakura(m, P(theta, CD.AtriumRadius + 5, TH), 4.6)
	end
	for _, theta in ipairs(D.Benches) do
		local p = P(theta, CD.AtriumRadius + 5, TH)
		-- along the rail, facing out to the wall (the halls)
		NanoKit.Bench(m, CFrame.lookAt(p, p + (p - C) * Vector3.new(1, 0, 1)))
	end
	for _, theta in ipairs(D.Lamps) do
		lampPost(m, P(theta, CD.AtriumRadius + 3.5, TH))
	end
	-- tile joints on the terrace (thin radial lines, like the sheet's paving)
	local n = math.floor(360 / D.JointEvery)
	for i = 0, n - 1 do
		local theta = i * D.JointEvery
		if not inGap(theta, { { 180, 20 } }) then
			local a, b = P(theta, CD.AtriumRadius + 2.5, TH + 0.08), P(theta, CD.TerraceOuter - 0.5, TH + 0.08)
			Panel(m, "Joint", Vector3.new(0.22, 0.04, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), K.FloorDark, M.Smooth, { CanCollide = false, CastShadow = false })
		end
	end
	-- long planters along the wall in the free arcs (tidy, like the sheet)
	for _, arc in ipairs(D.WallPlanters) do
		local steps = math.max(1, math.floor((arc[2] - arc[1]) / 3))
		for i = 0, steps - 1 do
			local t0 = arc[1] + (arc[2] - arc[1]) * i / steps
			local t1 = arc[1] + (arc[2] - arc[1]) * (i + 1) / steps
			local a, b = P(t0, CD.TerraceOuter - 2, TH), P(t1, CD.TerraceOuter - 2, TH)
			local mid = (a + b) / 2
			local cf = CFrame.lookAt(mid, Vector3.new(C.X, mid.Y, C.Z))
			local w = (b - a).Magnitude + 0.1
			Panel(m, "PlanterBox", Vector3.new(w, 1.6, 3.4), cf * CFrame.new(0, 0.8, 0), K.Wall, M.Metal)
			Panel(m, "PlanterRim", Vector3.new(w, 0.25, 3.7), cf * CFrame.new(0, 1.68, 0), K.Trim, M.Metal)
			Panel(m, "PlanterGrass", Vector3.new(w, 0.2, 3), cf * CFrame.new(0, 1.62, 0), Color3.fromRGB(78, 120, 64), Enum.Material.Grass, { CanCollide = false })
			local bush = Panel(m, "Bush", Vector3.new(2.6, 2, 2.6), cf * CFrame.new(0, 2.3, 0), if i % 3 == 1 then Color3.fromRGB(236, 168, 196) else Color3.fromRGB(84, 138, 72), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
			bush.Size = Vector3.new(2.8, 2, 2.8)
		end
		-- a sakura at each end of the planter
		sakura(m, P(arc[1] + 1.5, CD.TerraceOuter - 6.5, TH), 4)
		sakura(m, P(arc[2] - 1.5, CD.TerraceOuter - 6.5, TH), 4)
	end
	for _, theta in ipairs(D.Banners) do
		-- banners on the wall face between the halls
		hangingBanner(m, faceIn(theta, CD.WallInner - 0.25, CD.WallTop - 2.4), 4, 8)
	end
	return m
end

---------------------------------------------------------------------

function HubCitadel.Build()
	root = Instance.new("Folder")
	root.Name = "Hub"
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	base = Vector3.new(origin.X, groundY, origin.Z)
	C = base + CD.Center
	if spawn then
		spawn.CFrame = CFrame.new(spawn.Position) -- players appear facing north (the gates)
		spawn.Transparency = 1
		for _, d in ipairs(spawn:GetChildren()) do
			if d:IsA("Decal") then
				d.Transparency = 1
			end
		end
	end

	buildGround()
	buildTerrace()
	buildRimWall()
	buildSpawn()
	buildAtrium()
	local portal = buildGates()
	local redGate = buildRedGate()
	local forgePrompt, forge = buildForge()
	local academy = buildAcademy()
	local supply, supplyPrompt = buildSupply()
	buildAfkPortal()
	buildTerraceDecor()
	for _, pv in ipairs(CD.Pavilion.Halls) do
		pavilion(CD.Signs[pv[1]], pv[2], pv[3])
	end

	-- hall signs on the rim wall
	wallSign(CD.Signs.Forge, Texts.Forge, Texts.ForgeSub)
	wallSign(CD.Signs.Academy, Texts.Academy, Texts.AcademySub)
	wallSign(CD.Signs.Supply, Texts.Supply, Texts.SupplySub)

	-- 8 leaderboards and 9 the quest board beside the gate
	local boards = {}
	for i, def in ipairs(L.Leaderboards) do
		local theta = CD.Boards[i] or CD.Boards[1]
		boards[def.Kind] = leaderboard(faceIn(theta, CD.TerraceOuter - 6, TH), def)
	end
	local _, qface = board(faceIn(CD.QuestBoard, CD.TerraceOuter - 6, TH), "QuestBoard", Vector2.new(9.6, 7.6))
	WorldKit.SurfaceText(qface, Enum.NormalId.Front, { { Text = Texts.QuestBoard, Size = 44, Color = N.Gold }, { Text = Texts.QuestBoardSub, Size = 22, Color = T.Cyan } }, 50)
	local boardPrompt = WorldKit.Prompt(qface, L.Prompts.Board, "", { Action = "Talk", Npc = "GateKeeper" }, 12)

	-- NPCs: the mentor beside the spawn facing it, the gate keeper by the board
	local mp = at(L.Mentor.Offset.X, 0, L.Mentor.Offset.Z)
	local mentor = npc("Mentor", L.Models.Mentor, CFrame.lookAt(mp, at(L.Mentor.Face.X, 0, L.Mentor.Face.Z)))
	local gp = P(CD.GateKeeper, CD.TerraceOuter - 14, TH)
	local keeper = npc("GateKeeper", L.Models.GateKeeper, CFrame.lookAt(gp, Vector3.new(C.X, gp.Y, C.Z)))

	-- the sky around: rock under the island, far islands, clouds
	HubIsland.Scenery(root, C, CD.IslandRadius, CD.PlinthDepth + 1)

	local waypoints = {}
	for name, offset in pairs(L.Waypoints) do
		waypoints[name] = base + offset
	end
	root:SetAttribute("Center", C)
	root.Parent = Workspace
	return {
		Folder = root,
		Portal = portal,
		RedGate = redGate,
		Forge = forge,
		ForgePrompt = forgePrompt,
		Academy = academy,
		Leaderboards = boards,
		BoardPrompt = boardPrompt,
		Npcs = { Mentor = mentor, GateKeeper = keeper },
		Guide = { Folder = root, Supply = supply, SupplyPrompt = supplyPrompt },
		Waypoints = waypoints,
		SpawnCFrame = CFrame.lookAt(at(0, 4, 0), at(0, 4, -10)),
		GroundY = base.Y,
	}
end

return HubCitadel
