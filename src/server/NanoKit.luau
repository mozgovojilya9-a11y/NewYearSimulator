--[[
	NanoKit.luau
	Building blocks of the nano-future architecture (hub and dungeon):
	panels, pylons, arches, canopies, bridges, railings, cables, vents,
	crates, benches, plant capsules, lamps, holographic signs, floating
	platforms and drones. Materials: Metal, DiamondPlate, Concrete, Glass,
	Foil, SmoothPlastic; Neon only as thin strips and cores
	(Config.Nano palette).

	Everything is anchored. Living things are tagged for the client
	(HubLife.luau animates them locally, nothing moves on the server):
	  "Spin"    attribute Speed (deg/s), Axis ("X" | "Y" | "Z"), Local
	            (true: the part's own axis, else the world axis)
	  "Bob"     attributes Amplitude (studs), Period (s)
	  "Flicker" holographic parts / signs: short dips of transparency
	  "Pulse"   neon parts / lights breathing
	  "Drone"   a drone model + attributes P1..Pn (route) and Speed

	Owner props (GameAssets/Props, Trainers) are used through NanoKit.Prop
	with a procedural fallback.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local WorldKit = require(script.Parent.WorldKit)

local N = Config.Nano
local METAL = Enum.Material.Metal
local PLATE = Enum.Material.DiamondPlate
local CONCRETE = Enum.Material.Concrete
local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon
local FOIL = Enum.Material.Foil
local SMOOTH = Enum.Material.SmoothPlastic

local NanoKit = {}
NanoKit.Materials = { Metal = METAL, Plate = PLATE, Concrete = CONCRETE, Glass = GLASS, Neon = NEON, Foil = FOIL, Smooth = SMOOTH }

local function tag(instance: Instance, name: string, attributes: { [string]: any }?)
	CollectionService:AddTag(instance, name)
	for key, value in pairs(attributes or {}) do
		instance:SetAttribute(key, value)
	end
	return instance
end
NanoKit.Tag = tag

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
NanoKit.Model = model

-- Plain anchored block.
function NanoKit.Panel(parent, name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, props: { [string]: any }?)
	local p = WorldKit.Part(parent, { Name = name, Size = size, CFrame = cf, Color = color or N.Steel, Material = material or METAL })
	for key, value in pairs(props or {}) do
		p[key] = value
	end
	return p
end
local Panel = NanoKit.Panel

-- Thin neon strip between two points (accent light line).
function NanoKit.Strip(parent, from: Vector3, to: Vector3, color: Color3?, width: number?)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return nil
	end
	local w = width or 0.18
	return Panel(parent, "Strip", Vector3.new(w, w, length), CFrame.lookAt((from + to) / 2, to), color or N.Cyan, NEON, { CanCollide = false, CastShadow = false })
end

-- Cylinder lying along `cf`'s X axis.
local function cylinder(parent, name, length, diameter, cf, color, material)
	return Panel(parent, name, Vector3.new(length, diameter, diameter), cf, color, material, { Shape = Enum.PartType.Cylinder })
end
NanoKit.Cylinder = cylinder

-- Vertical cylinder (axis = Y) standing on `pos`.
local function column(parent, name, height, diameter, pos: Vector3, color, material)
	return cylinder(parent, name, height, diameter, CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
end
NanoKit.Column = column

---------------------------------------------------------------------
-- Structures
---------------------------------------------------------------------

-- Pylon: base plinth, ribbed shaft, neon seam, cap with a warm light.
function NanoKit.Pylon(parent, pos: Vector3, height: number, accent: Color3?, width: number?)
	local w = width or 2.4
	local m = model(parent, "Pylon")
	Panel(m, "Plinth", Vector3.new(w + 1.4, 1, w + 1.4), CFrame.new(pos + Vector3.new(0, 0.5, 0)), N.ConcreteDark, CONCRETE)
	Panel(m, "Shaft", Vector3.new(w, height - 2, w), CFrame.new(pos + Vector3.new(0, height / 2, 0)), N.Graphite, METAL)
	for i = 1, math.floor(height / 4) do
		Panel(m, "Rib", Vector3.new(w + 0.3, 0.3, w + 0.3), CFrame.new(pos + Vector3.new(0, i * 4, 0)), N.SteelLight, PLATE)
	end
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Strip(m, pos + Vector3.new(side * (w / 2 + 0.02), 1.5, 0), pos + Vector3.new(side * (w / 2 + 0.02), height - 1.5, 0), accent or N.Cyan, 0.14)
	end
	local cap = Panel(m, "Cap", Vector3.new(w + 0.8, 1, w + 0.8), CFrame.new(pos + Vector3.new(0, height - 0.5, 0)), N.SteelLight, METAL)
	local beacon = Panel(m, "Beacon", Vector3.new(0.8, 0.5, 0.8), CFrame.new(pos + Vector3.new(0, height + 0.25, 0)), accent or N.Cyan, NEON, { CanCollide = false })
	tag(beacon, "Pulse", { Period = 2.4 })
	WorldKit.Light(cap, N.WarmLight, 22, 1.2)
	return m
end

-- Arch: two pylons and a beam with an underside light strip.
-- cf: ground center, X = across the arch.
function NanoKit.Arch(parent, cf: CFrame, width: number, height: number, accent: Color3?)
	local m = model(parent, "Arch")
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Pylon(m, (cf * CFrame.new(side * width / 2, 0, 0)).Position, height, accent, 2.6)
	end
	local beam = Panel(m, "Beam", Vector3.new(width + 3, 2.2, 3), cf * CFrame.new(0, height + 0.6, 0), N.Graphite, METAL)
	Panel(m, "BeamTrim", Vector3.new(width + 3.4, 0.4, 3.4), cf * CFrame.new(0, height + 1.9, 0), N.SteelLight, PLATE)
	NanoKit.Strip(m, (cf * CFrame.new(-width / 2, height - 0.55, 0)).Position, (cf * CFrame.new(width / 2, height - 0.55, 0)).Position, accent or N.Cyan, 0.2)
	return m, beam
end

-- Canopy roof on four slim columns, light strips underneath.
-- cf: ground center; size: X x Z footprint, height = roof height.
function NanoKit.Canopy(parent, cf: CFrame, size: Vector2, height: number, accent: Color3?)
	local m = model(parent, "Canopy")
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			column(m, "Post", height, 0.7, (cf * CFrame.new(dx * (size.X / 2 - 0.6), 0, dz * (size.Y / 2 - 0.6))).Position, N.SteelLight, METAL)
		end
	end
	local roof = Panel(m, "Roof", Vector3.new(size.X + 1, 0.6, size.Y + 1), cf * CFrame.new(0, height + 0.3, 0), N.Graphite, METAL)
	Panel(m, "RoofGlass", Vector3.new(size.X - 2, 0.2, size.Y - 2), cf * CFrame.new(0, height + 0.7, 0), N.Glass, GLASS, { Transparency = 0.45 })
	for _, dz in ipairs({ -1, 1 }) do
		NanoKit.Strip(m, (cf * CFrame.new(-size.X / 2, height - 0.05, dz * size.Y / 2)).Position, (cf * CFrame.new(size.X / 2, height - 0.05, dz * size.Y / 2)).Position, accent or N.Cyan, 0.15)
	end
	local glow = Panel(m, "Downlight", Vector3.new(size.X * 0.5, 0.1, 0.5), cf * CFrame.new(0, height - 0.05, 0), N.WarmLight, NEON, { CanCollide = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = N.WarmLight
	light.Range = height + 8
	light.Angle = 110
	light.Brightness = 1.4
	light.Parent = glow
	return m, roof
end

-- Railing from `a` to `b` (ground points): posts, top rail, glass panels.
function NanoKit.Railing(parent, a: Vector3, b: Vector3, height: number?, accent: Color3?)
	local h = height or 3.2
	local m = model(parent, "Railing")
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local posts = math.max(1, math.floor(length / 6))
	for i = 0, posts do
		local p = a + dir * (length * i / posts)
		Panel(m, "Post", Vector3.new(0.35, h, 0.35), CFrame.new(p + Vector3.new(0, h / 2, 0)), N.SteelLight, METAL)
	end
	local mid = (a + b) / 2
	Panel(m, "Rail", Vector3.new(0.3, 0.3, length), CFrame.lookAt(mid + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0)), N.SteelLight, METAL)
	Panel(m, "Glass", Vector3.new(0.12, h - 0.8, length - 0.4), CFrame.lookAt(mid + Vector3.new(0, h / 2, 0), b + Vector3.new(0, h / 2, 0)), N.Glass, GLASS, { Transparency = 0.6 })
	NanoKit.Strip(m, a + Vector3.new(0, h - 0.3, 0), b + Vector3.new(0, h - 0.3, 0), accent or N.Cyan, 0.08)
	return m
end

-- Elevated walkway between two ground points (decor; ramps not needed).
function NanoKit.Bridge(parent, a: Vector3, b: Vector3, height: number, width: number, accent: Color3?)
	local m = model(parent, "Bridge")
	local length = (b - a).Magnitude
	local mid = (a + b) / 2 + Vector3.new(0, height, 0)
	local cf = CFrame.lookAt(mid, b + Vector3.new(0, height, 0))
	Panel(m, "Deck", Vector3.new(width, 0.8, length), cf, N.Steel, PLATE)
	Panel(m, "Under", Vector3.new(width - 1, 1.2, length), cf * CFrame.new(0, -1, 0), N.Graphite, METAL)
	for _, side in ipairs({ -1, 1 }) do
		local s0 = (cf * CFrame.new(side * (width / 2 - 0.2), 0.4, -length / 2)).Position
		local s1 = (cf * CFrame.new(side * (width / 2 - 0.2), 0.4, length / 2)).Position
		NanoKit.Railing(m, s0, s1, 2.6, accent)
		NanoKit.Strip(m, (cf * CFrame.new(side * width / 2, -0.4, -length / 2)).Position, (cf * CFrame.new(side * width / 2, -0.4, length / 2)).Position, accent or N.Cyan, 0.12)
	end
	return m
end

-- Sagging cable between two points (a few straight segments).
function NanoKit.Cable(parent, a: Vector3, b: Vector3, sag: number?, color: Color3?)
	local m = model(parent, "Cable")
	local segments = 6
	local s = sag or 2.5
	local prev = a
	for i = 1, segments do
		local t = i / segments
		local p = a:Lerp(b, t) - Vector3.new(0, s * 4 * t * (1 - t), 0)
		local length = (p - prev).Magnitude
		Panel(m, "Segment", Vector3.new(0.22, 0.22, length + 0.1), CFrame.lookAt((prev + p) / 2, p), color or N.Graphite, SMOOTH, { CanCollide = false, CastShadow = false })
		prev = p
	end
	return m
end

-- Wall vent: frame + slats + a slow fan behind (Spin).
function NanoKit.Vent(parent, cf: CFrame, size: number?)
	local s = size or 3
	local m = model(parent, "Vent")
	Panel(m, "Frame", Vector3.new(s + 0.4, s + 0.4, 0.4), cf, N.SteelLight, METAL)
	Panel(m, "Back", Vector3.new(s, s, 0.2), cf * CFrame.new(0, 0, 0.3), N.Graphite, METAL)
	for i = 1, 4 do
		Panel(m, "Slat", Vector3.new(s, 0.12, 0.3), cf * CFrame.new(0, -s / 2 + i * s / 5, -0.15) * CFrame.Angles(math.rad(30), 0, 0), N.Steel, METAL, { CanCollide = false })
	end
	local fan = Panel(m, "Fan", Vector3.new(s * 0.8, 0.25, 0.1), cf * CFrame.new(0, 0, 0.15), N.Steel, METAL, { CanCollide = false })
	tag(fan, "Spin", { Speed = 240, Axis = "Z", Local = true })
	return m
end

-- Procedural cargo crate.
local function crate(parent, cf: CFrame, size: Vector3)
	local m = model(parent, "Crate")
	Panel(m, "Body", size, cf * CFrame.new(0, size.Y / 2, 0), N.Steel, PLATE)
	for _, dy in ipairs({ 0.15, size.Y - 0.15 }) do
		Panel(m, "Band", Vector3.new(size.X + 0.1, 0.25, size.Z + 0.1), cf * CFrame.new(0, dy, 0), N.Graphite, METAL)
	end
	Panel(m, "Label", Vector3.new(size.X * 0.5, size.Y * 0.3, 0.06), cf * CFrame.new(0, size.Y / 2, -size.Z / 2 - 0.03), N.Gold, SMOOTH, { CanCollide = false })
	return m
end

-- Owner prop if present (GameAssets/Props or Trainers), placed on the
-- ground at `cf`; else `fallback(parent, cf)` (or nothing).
-- height: optional target height of the owner model.
function NanoKit.Prop(parent, name: string, cf: CFrame, height: number?, fallback)
	local prop = Assets.Prop(name, height)
	if prop then
		Assets.PlaceOnGround(prop, cf)
		prop.Parent = parent
		return prop
	end
	if fallback then
		return fallback(parent, cf)
	end
	return nil
end

-- Always our own crate: the owner's Prop_Crate (10 studs, cyan neon
-- edges, noisy texture) read as "cyan grids" in rooms and is not used.
function NanoKit.Crate(parent, cf: CFrame, size: Vector3?)
	return crate(parent, cf, size or Vector3.new(3, 3, 3))
end

function NanoKit.Barrel(parent, cf: CFrame)
	local owner = Assets.Prop("Prop_Barrel", 3.2)
	if owner then
		-- the owner's barrel without its cyan neon rings (they fight every biome)
		for _, d in ipairs(owner:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == NEON then
				d.Material = METAL
				d.Color = N.Graphite
			end
		end
		Assets.PlaceOnGround(owner, cf)
		owner.Parent = parent
		return owner
	end
	return NanoKit.Prop(parent, "Prop_Barrel", cf, 3.2, function(p, c)
		local m = model(p, "Barrel")
		column(m, "Body", 3.2, 2.2, c.Position, N.SteelLight, METAL)
		for _, y in ipairs({ 0.5, 2.7 }) do
			column(m, "Hoop", 0.25, 2.35, c.Position + Vector3.new(0, y, 0), N.Graphite, METAL)
		end
		column(m, "Glow", 0.12, 1.2, c.Position + Vector3.new(0, 3.2, 0), N.Cyan, NEON)
		return m
	end)
end

-- A stack of crates and barrels around `cf`.
function NanoKit.CargoStack(parent, cf: CFrame)
	local m = model(parent, "Cargo")
	NanoKit.Crate(m, cf)
	NanoKit.Crate(m, cf * CFrame.new(3.4, 0, 0.3) * CFrame.Angles(0, math.rad(12), 0), Vector3.new(2.6, 2.6, 2.6))
	NanoKit.Barrel(m, cf * CFrame.new(-2.8, 0, 1.2))
	return m
end

function NanoKit.Bench(parent, cf: CFrame)
	local m = model(parent, "Bench")
	Panel(m, "Seat", Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.6, 0), N.Steel, PLATE)
	Panel(m, "Back", Vector3.new(6, 1.4, 0.3), cf * CFrame.new(0, 2.6, 0.8) * CFrame.Angles(math.rad(-10), 0, 0), N.Graphite, METAL)
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Leg", Vector3.new(0.4, 1.4, 1.6), cf * CFrame.new(side * 2.5, 0.7, 0), N.Graphite, METAL)
	end
	NanoKit.Strip(m, (cf * CFrame.new(-3, 1.38, -0.9)).Position, (cf * CFrame.new(3, 1.38, -0.9)).Position, N.Cyan, 0.08)
	return m
end

-- Plant in a glass capsule (the "green" of the technopolis).
function NanoKit.PlantCapsule(parent, pos: Vector3, scale: number?)
	local s = scale or 1
	local m = model(parent, "PlantCapsule")
	column(m, "Base", 1 * s, 3 * s, pos, N.Graphite, METAL)
	column(m, "Soil", 0.3 * s, 2.6 * s, pos + Vector3.new(0, 1 * s, 0), Color3.fromRGB(70, 50, 38), Enum.Material.Ground)
	for i = 1, 5 do
		local angle = i * math.pi * 2 / 5
		Panel(m, "Leaf", Vector3.new(0.4, 2.4, 1) * s, CFrame.new(pos + Vector3.new(math.cos(angle) * 0.5, 2.3, math.sin(angle) * 0.5) * s) * CFrame.Angles(0, -angle, math.rad(18)), N.Leaf, Enum.Material.Grass, { CanCollide = false })
	end
	column(m, "Capsule", 3.2 * s, 2.8 * s, pos + Vector3.new(0, 1.2 * s, 0), N.Glass, GLASS).Transparency = 0.7
	column(m, "Lid", 0.4 * s, 3 * s, pos + Vector3.new(0, 4.4 * s, 0), N.SteelLight, METAL)
	column(m, "LidGlow", 0.1 * s, 2.2 * s, pos + Vector3.new(0, 4.8 * s, 0), N.Cyan, NEON)
	return m
end

-- Street lamp with a warm downlight (owner Prop_Lamp if present).
function NanoKit.Lamp(parent, pos: Vector3, height: number?, facing: Vector3?)
	local h = height or 9
	return NanoKit.Prop(parent, "Prop_Lamp", CFrame.lookAt(pos, pos + (facing or Vector3.new(0, 0, -1))), h, function(p, c)
		local m = model(p, "Lamp")
		column(m, "Pole", h, 0.5, c.Position, N.Graphite, METAL)
		local arm = Panel(m, "Arm", Vector3.new(0.4, 0.4, 2.4), c * CFrame.new(0, h - 0.2, -1), N.Graphite, METAL)
		local head = Panel(m, "Head", Vector3.new(1.4, 0.4, 0.8), c * CFrame.new(0, h - 0.5, -2), N.SteelLight, METAL)
		Panel(m, "Bulb", Vector3.new(1, 0.1, 0.5), c * CFrame.new(0, h - 0.72, -2), N.WarmLight, NEON, { CanCollide = false })
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Color = N.WarmLight
		light.Range = h + 10
		light.Angle = 100
		light.Brightness = 2
		light.Parent = head
		local _ = arm
		return m
	end)
end

-- Holographic sign: dark plate with text on both faces, a thin neon
-- frame, flickers a little (client). cf: center of the board.
function NanoKit.HoloSign(parent, cf: CFrame, size: Vector2, lines, accent: Color3?)
	local m = model(parent, "HoloSign")
	local board = Panel(m, "Board", Vector3.new(size.X, size.Y, 0.3), cf, Config.Theme.PanelDark, SMOOTH, { CanCollide = false })
	WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 60)
	WorldKit.SurfaceText(board, Enum.NormalId.Back, lines, 60)
	local c = accent or N.Cyan
	local hw, hh = size.X / 2 + 0.1, size.Y / 2 + 0.1
	for _, seg in ipairs({ { -hw, -hh, hw, -hh }, { -hw, hh, hw, hh }, { -hw, -hh, -hw, hh }, { hw, -hh, hw, hh } }) do
		NanoKit.Strip(m, (cf * CFrame.new(seg[1], seg[2], 0)).Position, (cf * CFrame.new(seg[3], seg[4], 0)).Position, c, 0.12)
	end
	tag(board, "Flicker")
	return m, board
end

-- Sign on a post (eye height), readable from both sides.
function NanoKit.PostSign(parent, ground: CFrame, text: string, accent: Color3?, subtitle: string?)
	local m = model(parent, "PostSign")
	column(m, "Post", 5.4, 0.45, ground.Position, N.Graphite, METAL)
	local lines = { { Text = text, Size = 48, Color = accent or N.Gold } }
	if subtitle then
		table.insert(lines, { Text = subtitle, Size = 24 })
	end
	NanoKit.HoloSign(m, ground * CFrame.new(0, 6.6, 0), Vector2.new(9.5, if subtitle then 3.4 else 2.6), lines, accent)
	return m
end

-- Floating platform with thrusters, bobbing (client).
function NanoKit.FloatingPlatform(parent, cf: CFrame, size: Vector3, accent: Color3?)
	local m = model(parent, "FloatingPlatform")
	local deck = Panel(m, "Deck", size, cf, N.Steel, PLATE)
	Panel(m, "Under", Vector3.new(size.X - 1, 0.8, size.Z - 1), cf * CFrame.new(0, -size.Y / 2 - 0.4, 0), N.Graphite, METAL)
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			local thruster = cylinder(m, "Thruster", 0.6, 1.2, cf * CFrame.new(dx * (size.X / 2 - 1.2), -size.Y / 2 - 0.9, dz * (size.Z / 2 - 1.2)) * CFrame.Angles(0, 0, math.rad(90)), accent or N.Cyan, NEON)
			thruster.CanCollide = false
		end
	end
	m.PrimaryPart = deck
	tag(m, "Bob", { Amplitude = 0.8, Period = 4 + math.random() * 2 })
	return m
end

-- Patrol drone flying along `route` (client moves it).
function NanoKit.Drone(parent, route: { Vector3 }, speed: number?, accent: Color3?)
	local m = model(parent, "Drone")
	local body = Panel(m, "Body", Vector3.new(1.8, 0.6, 1.8), CFrame.new(route[1]), N.Graphite, METAL, { CanCollide = false })
	Panel(m, "Eye", Vector3.new(0.6, 0.3, 0.2), CFrame.new(route[1] + Vector3.new(0, 0, -0.95)), accent or N.Cyan, NEON, { CanCollide = false })
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			local rotor = Panel(m, "Rotor", Vector3.new(1.4, 0.08, 0.2), CFrame.new(route[1] + Vector3.new(dx * 1.3, 0.4, dz * 1.3)), N.SteelLight, METAL, { CanCollide = false })
			Panel(m, "Arm", Vector3.new(0.2, 0.2, 1.4), CFrame.lookAt(route[1] + Vector3.new(dx * 0.65, 0.2, dz * 0.65), route[1] + Vector3.new(dx * 1.3, 0.2, dz * 1.3)), N.Steel, METAL, { CanCollide = false })
			local _ = rotor
		end
	end
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = N.WarmLight
	light.Range = 14
	light.Angle = 50
	light.Brightness = 1
	light.Parent = body
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then
			p.CastShadow = false
			p.CanQuery = false
		end
	end
	m.PrimaryPart = body
	tag(m, "Drone", { Speed = speed or 8 })
	for i, point in ipairs(route) do
		m:SetAttribute("P" .. i, point)
	end
	return m
end

-- Wall of concrete panels with vertical neon seams from `a` to `b`.
function NanoKit.Wall(parent, a: Vector3, b: Vector3, height: number, thickness: number, accent: Color3?)
	local m = model(parent, "Wall")
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local count = math.max(1, math.floor(length / 12))
	local seg = length / count
	for i = 0, count - 1 do
		local c = a + dir * (seg * (i + 0.5))
		local cf = CFrame.lookAt(c + Vector3.new(0, height / 2, 0), c + Vector3.new(0, height / 2, 0) + dir)
		Panel(m, "Panel", Vector3.new(thickness, height, seg - 0.3), cf, if i % 2 == 0 then N.Concrete else N.ConcreteLight, CONCRETE)
		Panel(m, "Seam", Vector3.new(thickness + 0.2, height, 0.3), cf * CFrame.new(0, 0, seg / 2), N.Graphite, METAL)
		for _, side in ipairs({ -1, 1 }) do
			NanoKit.Strip(m, (cf * CFrame.new(side * (thickness / 2 + 0.12), -height / 2 + 1, seg / 2)).Position, (cf * CFrame.new(side * (thickness / 2 + 0.12), height / 2 - 1, seg / 2)).Position, accent or N.Cyan, 0.12)
		end
	end
	local mid = (a + b) / 2
	Panel(m, "Coping", Vector3.new(thickness + 0.8, 0.6, length), CFrame.lookAt(mid + Vector3.new(0, height + 0.3, 0), b + Vector3.new(0, height + 0.3, 0)), N.Graphite, METAL)
	return m
end

-- Floor of large tiles (concrete / plate checker), few parts.
function NanoKit.Floor(parent, center: Vector3, width: number, depth: number, tile: number, colorA: Color3?, colorB: Color3?, material: Enum.Material?)
	local m = model(parent, "Floor")
	local nx, nz = math.max(1, math.floor(width / tile)), math.max(1, math.floor(depth / tile))
	local tw, td = width / nx, depth / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local pos = center + Vector3.new(-width / 2 + tw * (ix + 0.5), -0.5, -depth / 2 + td * (iz + 0.5))
			Panel(m, "Tile", Vector3.new(tw - 0.06, 1, td - 0.06), CFrame.new(pos), if (ix + iz) % 2 == 0 then colorA or N.Concrete else colorB or N.ConcreteLight, material or CONCRETE)
		end
	end
	Panel(m, "Grout", Vector3.new(width, 0.9, depth), CFrame.new(center + Vector3.new(0, -0.56, 0)), N.Graphite, METAL)
	return m
end

return NanoKit
