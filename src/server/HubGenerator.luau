--[[
	HubGenerator.luau
	Builds the hub "Нано-Цитадель" (Workspace.Hub) after the owner's plan
	docs/design/hub_plan.png (Config.HubLayout):

	  1 Spawn plaza (south)       3 Mentor next to it, facing the spawn
	  2 Atrium ~200x150, 2 levels: balcony along the walls on columns,
	    a bridge across the middle, two stairs up to it, glass skylight
	    on trusses, runners on the floor and the center ring
	  4 Academy of classes (SE)   3 class pedestals, the class terminal
	  5 Зал снабжения (W)         capsule machine (pulls), AFK portal
	  6 Fabricator (NE)           the central forge, a conveyor
	  7 Gate hall (N)             giant gates on the spawn axis
	  8 Leaderboards, 9 Quest board + Смотритель Врат at the gate arch

	Every hall has its own colors and light (Themes), its central object,
	decor groups along the walls and in corners; the middle and the paths
	stay free. Wide arches connect the halls, hall signs hang under the
	balcony edge above each arch. Owner / AI-generated models come from
	GameAssets (Config.HubLayout.Models), procedural ones are the
	fallback. Living things are tagged for the client (HubLife.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local L = Config.HubLayout
local C = L.Colors
local N = Config.Nano
local T = Config.Theme
local Texts = L.Texts
local M = NanoKit.Materials
local Panel = NanoKit.Panel
local WT = L.WallThickness

local root, base
local screenIndex = 0
local lampIndex = 0

local function at(x: number, y: number, z: number): Vector3
	return base + Vector3.new(x, y, z)
end

local function theme(name: string)
	return L.Themes[name] or L.Themes.Atrium
end

-- AI material from MaterialService: the part takes the variant's base
-- material too (a variant only shows on its own base material).
local MaterialService = game:GetService("MaterialService")
local function variant(part: BasePart, name: string?)
	local mv = name and name ~= "" and MaterialService:FindFirstChild(name, true)
	if mv and mv:IsA("MaterialVariant") then
		part.Material = mv.BaseMaterial
		part.MaterialVariant = name
	end
	return part
end

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

-- Owner model without neon edges / glows (they read as cheap outlines).
local function tame(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Material = M.Metal
			d.Color = C.Steel:Lerp(d.Color, 0.15)
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	return model
end

local function ownerProp(parent, name: string, cf: CFrame, height: number?, keepGlow: boolean?)
	if name == "" then
		return nil
	end
	local prop = NanoKit.Prop(parent, name, cf, height)
	if prop and not keepGlow then
		tame(prop)
	end
	return prop
end

local function text(part: BasePart, face: Enum.NormalId, lines)
	return WorldKit.SurfaceText(part, face, lines, 60)
end

-- Dark sign plate with a steel frame (no neon). cf = plate center, front (-Z) reads.
local function signPlate(parent, cf: CFrame, size: Vector2, lines, bothSides: boolean?)
	local m = NanoKit.Model(parent, "Sign")
	local plate = Panel(m, "Plate", Vector3.new(size.X, size.Y, 0.3), cf, T.PanelDark, M.Smooth, { CanCollide = false })
	text(plate, Enum.NormalId.Front, lines)
	if bothSides then
		text(plate, Enum.NormalId.Back, lines)
	end
	local fw, fh, b = size.X / 2 + 0.15, size.Y / 2 + 0.15, 0.3
	Panel(m, "FrameTop", Vector3.new(size.X + 0.6, b, 0.5), cf * CFrame.new(0, fh, 0), C.Steel, M.Metal, { CanCollide = false })
	Panel(m, "FrameBottom", Vector3.new(size.X + 0.6, b, 0.5), cf * CFrame.new(0, -fh, 0), C.Steel, M.Metal, { CanCollide = false })
	Panel(m, "FrameLeft", Vector3.new(b, size.Y + 0.6, 0.5), cf * CFrame.new(-fw, 0, 0), C.Steel, M.Metal, { CanCollide = false })
	Panel(m, "FrameRight", Vector3.new(b, size.Y + 0.6, 0.5), cf * CFrame.new(fw, 0, 0), C.Steel, M.Metal, { CanCollide = false })
	return m, plate
end

---------------------------------------------------------------------
-- Rects and walls
---------------------------------------------------------------------

-- A hall rect { X0, X1, Z0 (south), Z1 (north) }.
local function rect(name)
	local r = L.Halls[name].Rect
	return r[1], r[2], r[3], r[4]
end

-- Ground frame on a wall point: -Z looks into the hall, +X runs along.
-- shift moves the frame into the hall (a side hall's face of a shared
-- atrium wall is WT further in than the atrium's line).
local function wallFrame(side: string, hall: string, along: number, shift: number?): CFrame
	local x0, x1, z0, z1 = rect(hall)
	local p, inward
	if side == "N" then
		p, inward = at(along, 0, z1), Vector3.new(0, 0, 1)
	elseif side == "S" then
		p, inward = at(along, 0, z0), Vector3.new(0, 0, -1)
	elseif side == "W" then
		p, inward = at(x0, 0, along), Vector3.new(1, 0, 0)
	else
		p, inward = at(x1, 0, along), Vector3.new(-1, 0, 0)
	end
	p += inward * (shift or 0)
	return CFrame.lookAt(p, p + inward)
end

-- Wall endpoints (a -> b along the inner face) of a hall side.
local function sideLine(side: string, hall: string): (Vector3, Vector3)
	local x0, x1, z0, z1 = rect(hall)
	if side == "N" then
		return at(x0, 0, z1), at(x1, 0, z1)
	elseif side == "S" then
		return at(x1, 0, z0), at(x0, 0, z0)
	elseif side == "W" then
		return at(x0, 0, z0), at(x0, 0, z1)
	end
	return at(x1, 0, z1), at(x1, 0, z0)
end

-- Opening on a side from a world coordinate along it (x for N/S, z for W/E).
local function opening(side: string, hall: string, coord: number, width: number, height: number)
	local a = sideLine(side, hall)
	local u = if side == "N" or side == "S" then math.abs((base.X + coord) - a.X) else math.abs((base.Z + coord) - a.Z)
	return { U = u, Width = width, Height = height }
end

-- One wall with dressing. opts: Height, Theme, Openings, NoSlab.
local function wall(name: string, a: Vector3, b: Vector3, inward: Vector3, opts)
	local H = opts.Height
	local th = theme(opts.Theme)
	local openings = opts.Openings or {}
	table.sort(openings, function(p, q)
		return p.U < q.U
	end)
	local m = NanoKit.Model(root, name)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local function frameAt(u: number): CFrame
		local p = a + dir * u
		return CFrame.lookAt(p, p + inward)
	end
	local solids, u0 = {}, -WT
	for _, o in ipairs(openings) do
		table.insert(solids, { u0, o.U - o.Width / 2 })
		u0 = o.U + o.Width / 2
	end
	table.insert(solids, { u0, length + WT })
	local slab = th.Wall:Lerp(Color3.new(0, 0, 0), 0.3)
	local cornice = math.min(20.6, H - 4)
	for _, s in ipairs(solids) do
		local w = s[2] - s[1]
		if w > 0.05 then
			if not opts.NoSlab then
				local cf = frameAt((s[1] + s[2]) / 2)
				Panel(m, "Slab", Vector3.new(w, H + 1, WT), cf * CFrame.new(0, (H + 1) / 2, WT / 2), slab, M.Concrete)
			end
			local u1, u2 = math.max(s[1], 0), math.min(s[2], length)
			local inner = u2 - u1
			if inner > 0.5 then
				local fc = frameAt((u1 + u2) / 2)
				Panel(m, "Dado", Vector3.new(inner, 4, 0.35), fc * CFrame.new(0, 2, -0.17), C.Dado, M.Metal)
				Panel(m, "Kick", Vector3.new(inner, 0.35, 0.55), fc * CFrame.new(0, 4.1, -0.27), C.Steel, M.Metal)
				local count = math.max(1, math.floor(inner / 6 + 0.5))
				local pw = inner / count
				local ph = cornice - 6
				for i = 0, count - 1 do
					local pc = fc * CFrame.new(-inner / 2 + pw * (i + 0.5), 5 + ph / 2, -0.09)
					variant(Panel(m, "WallPanel", Vector3.new(pw - 0.4, ph, 0.18), pc, th.Wall, M.Concrete), L.Materials.Wall)
				end
			end
		end
	end
	if not opts.NoSlab then
		for _, o in ipairs(openings) do
			local cf = frameAt(o.U)
			local hh = H + 1 - o.Height
			Panel(m, "Header", Vector3.new(o.Width, hh, WT), cf * CFrame.new(0, o.Height + hh / 2, WT / 2), slab, M.Concrete)
		end
	end
	local fc = frameAt(length / 2)
	Panel(m, "Cornice", Vector3.new(length, 1.2, 1.0), fc * CFrame.new(0, cornice, -0.5), C.Steel, M.Metal)
	Panel(m, "CorniceLip", Vector3.new(length, 0.3, 1.3), fc * CFrame.new(0, cornice - 0.6, -0.65), C.Beam, M.Metal)
	-- thin accent light under the cornice (the hall color)
	NanoKit.Strip(m, (fc * CFrame.new(-length / 2, cornice - 0.85, -1.2)).Position, (fc * CFrame.new(length / 2, cornice - 0.85, -1.2)).Position, th.Accent, 0.1)
	if H - cornice > 2 then
		Panel(m, "UpperBand", Vector3.new(length, H - cornice - 0.6, 0.25), fc * CFrame.new(0, cornice + 0.6 + (H - cornice - 0.6) / 2, -0.12), C.Dado, M.Metal)
	end
	return m
end

-- Metal pilaster with a thin light strip (hall accent); every other one
-- carries a warm lamp (keeps the light count sane).
local function pilaster(parent, cf: CFrame, H: number, th)
	local m = NanoKit.Model(parent, "Pilaster")
	local channel = math.min(14.6, H - 6)
	Panel(m, "Shaft", Vector3.new(2.4, H, 1.4), cf * CFrame.new(0, H / 2, -0.7), C.Steel, M.Metal)
	Panel(m, "Plinth", Vector3.new(3.2, 1.6, 2.2), cf * CFrame.new(0, 0.8, -1.1), C.Dado, M.Metal)
	Panel(m, "Channel", Vector3.new(0.7, channel, 0.12), cf * CFrame.new(0, 2.8 + channel / 2, -1.44), C.Dado, M.Metal, { CanCollide = false })
	NanoKit.Strip(m, (cf * CFrame.new(0, 3, -1.5)).Position, (cf * CFrame.new(0, 2.6 + channel, -1.5)).Position, th.Accent, 0.14)
	lampIndex += 1
	if lampIndex % 2 == 0 then
		Panel(m, "LampArm", Vector3.new(0.35, 0.35, 1.8), cf * CFrame.new(0, 11.2, -2.2), C.Beam, M.Metal)
		local head = Panel(m, "LampHead", Vector3.new(1.3, 0.5, 1), cf * CFrame.new(0, 11, -3.1), C.Steel, M.Metal)
		Panel(m, "Bulb", Vector3.new(1, 0.1, 0.7), cf * CFrame.new(0, 10.72, -3.1), th.Light, M.Neon, { CanCollide = false, CastShadow = false })
		spot(head, Enum.NormalId.Bottom, L.Lamp.Range, L.Lamp.Brightness, L.Lamp.Angle, th.Light)
	end
	return m
end

-- Pilasters along a side, skipping openings / boards ({ Coord, Width }).
local function pilasters(hall: string, side: string, H: number, th, blocked, shift: number?)
	local x0, x1, z0, z1 = rect(hall)
	local from, to
	if side == "N" or side == "S" then
		from, to = x0, x1
	else
		from, to = z1, z0
	end
	local m = NanoKit.Model(root, "Pilasters_" .. hall .. side)
	local c = from + L.Pilaster
	while c < to - 2 do
		local free = true
		for _, o in ipairs(blocked or {}) do
			if math.abs(c - o.Coord) < o.Width / 2 + 2.5 then
				free = false
			end
		end
		if free then
			pilaster(m, wallFrame(side, hall, c, shift), H, th)
		end
		c += L.Pilaster
	end
end

local function archFrame(parent, cf: CFrame, w: number, h: number, th)
	local m = NanoKit.Model(parent, "ArchFrame")
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Jamb", Vector3.new(1.6, h, 3), cf * CFrame.new(side * (w / 2 + 0.8), h / 2, -0.2), C.Steel, M.Metal)
		Panel(m, "JambBase", Vector3.new(2, 1.2, 3.4), cf * CFrame.new(side * (w / 2 + 0.8), 0.6, -0.2), C.Dado, M.Metal)
		Panel(m, "Chamfer", Vector3.new(2.6, 2.6, 3), cf * CFrame.new(side * (w / 2 - 0.3), h - 0.3, -0.2) * CFrame.Angles(0, 0, math.rad(45)), C.Steel, M.Metal)
		NanoKit.Strip(m, (cf * CFrame.new(side * (w / 2 + 0.05), 1.4, -1.75)).Position, (cf * CFrame.new(side * (w / 2 + 0.05), h - 1.6, -1.75)).Position, th.Accent, 0.12)
	end
	Panel(m, "Lintel", Vector3.new(w + 3.2, 2.4, 3), cf * CFrame.new(0, h + 1.2, -0.2), C.Steel, M.Metal)
	Panel(m, "LintelTrim", Vector3.new(w + 3.6, 0.35, 3.3), cf * CFrame.new(0, h + 2.55, -0.2), C.Beam, M.Metal)
	Panel(m, "Keystone", Vector3.new(2.2, 2.8, 3.3), cf * CFrame.new(0, h + 1.3, -0.25), th.Accent:Lerp(C.Beam, 0.75), M.Metal)
	Panel(m, "Threshold", Vector3.new(w, 0.12, WT + 2), cf * CFrame.new(0, 0.06, WT / 2 - 0.3), C.Steel, M.Plate)
	return m
end

-- Hall sign hanging under the balcony edge in front of an arch.
local function hangingSign(parent, cf: CFrame, title: string, sub: string?, accent: Color3)
	local by, depth = L.Balcony.Height, L.Balcony.Depth
	local lines = { { Text = title, Size = 92, Color = N.Gold } }
	if sub then
		table.insert(lines, { Text = sub, Size = 44, Color = accent })
	end
	local size = Vector2.new(24, if sub then 5 else 3.6)
	local y = by - 2.4 - size.Y / 2
	local pcf = cf * CFrame.new(0, y, -(depth - 0.6))
	local m = signPlate(parent, pcf * CFrame.Angles(0, math.rad(180), 0), size, lines, true)
	for _, sx in ipairs({ -1, 1 }) do
		local a = (pcf * CFrame.new(sx * (size.X / 2 - 1), size.Y / 2 + 0.2, 0)).Position
		local b = Vector3.new(a.X, base.Y + by - 1.4, a.Z)
		Panel(m, "Cable", Vector3.new(0.14, b.Y - a.Y, 0.14), CFrame.new((a + b) / 2), C.Beam, M.Metal, { CanCollide = false, CastShadow = false })
	end
	return m
end

---------------------------------------------------------------------
-- Floors and ceilings
---------------------------------------------------------------------

local function flatDisc(parent, name, diameter, y, pos: Vector3, color, material)
	local d = NanoKit.Cylinder(parent, name, 0.1, diameter, CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	d.CanCollide = false
	return d
end

local function floor(hall: string, th)
	local x0, x1, z0, z1 = rect(hall)
	local m = NanoKit.Model(root, "Floor_" .. hall)
	local w, d = x1 - x0, z0 - z1
	local center = at((x0 + x1) / 2, 0, (z0 + z1) / 2)
	local tiles = NanoKit.Floor(m, center, w, d, 10, th.Floor, th.Floor:Lerp(Color3.new(0, 0, 0), 0.08), M.Concrete)
	for _, tile in ipairs(tiles:GetChildren()) do
		if tile.Name == "Tile" then
			variant(tile, if hall == "Forge" then L.Materials.ForgeFloor else L.Materials.Floor)
		end
	end
	-- metal borders along the walls
	local bw = 2
	Panel(m, "Border", Vector3.new(w, 0.1, bw), CFrame.new(center + Vector3.new(0, 0.05, d / 2 - bw / 2)), C.Steel, M.Plate)
	Panel(m, "Border", Vector3.new(w, 0.1, bw), CFrame.new(center + Vector3.new(0, 0.05, -d / 2 + bw / 2)), C.Steel, M.Plate)
	Panel(m, "Border", Vector3.new(bw, 0.1, d - bw * 2), CFrame.new(center + Vector3.new(-w / 2 + bw / 2, 0.05, 0)), C.Steel, M.Plate)
	Panel(m, "Border", Vector3.new(bw, 0.1, d - bw * 2), CFrame.new(center + Vector3.new(w / 2 - bw / 2, 0.05, 0)), C.Steel, M.Plate)
	return m
end

-- Flat ceiling with beams and light panels (side halls).
local function ceiling(hall: string, H: number, th)
	local x0, x1, z0, z1 = rect(hall)
	local m = NanoKit.Model(root, "Ceiling_" .. hall)
	local w, d = x1 - x0, z0 - z1
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	Panel(m, "Roof", Vector3.new(w + WT * 2, 1, d + WT * 2), CFrame.new(at(cx, H + 0.5, cz)), C.Ceiling, M.Metal)
	local step = 12
	local zz = z0 - step
	while zz > z1 + 1 do
		Panel(m, "Beam", Vector3.new(w, 1.4, 1), CFrame.new(at(cx, H - 0.7, zz)), C.Beam, M.Metal)
		zz -= step
	end
	for ix = -1, 1 do
		local zl = z0 - step / 2 - (if ix == 0 then step else 0)
		while zl > z1 + 1 do
			local panel = Panel(m, "LightPanel", Vector3.new(4, 0.15, 2.2), CFrame.new(at(cx + ix * w / 3, H - 0.1, zl)), th.Light, M.Neon, { CanCollide = false, CastShadow = false })
			spot(panel, Enum.NormalId.Bottom, math.min(60, H + 14), 1.3, 120, th.Light)
			zl -= step * 2
		end
	end
	return m
end

---------------------------------------------------------------------
-- Decor (groups along walls / in corners)
---------------------------------------------------------------------

local function crate(parent, cf: CFrame, s: number)
	local m = NanoKit.Model(parent, "Crate")
	Panel(m, "Body", Vector3.new(s, s, s), cf * CFrame.new(0, s / 2, 0), C.Steel, M.Plate)
	for _, dy in ipairs({ 0.18, s - 0.18 }) do
		Panel(m, "Band", Vector3.new(s + 0.08, 0.3, s + 0.08), cf * CFrame.new(0, dy, 0), C.Beam, M.Metal)
	end
	for _, dx in ipairs({ -1, 1 }) do
		Panel(m, "Edge", Vector3.new(0.3, s, s + 0.08), cf * CFrame.new(dx * (s / 2 - 0.1), s / 2, 0), C.Beam, M.Metal)
	end
	Panel(m, "Label", Vector3.new(s * 0.4, s * 0.22, 0.05), cf * CFrame.new(0, s * 0.6, -s / 2 - 0.03), C.Paint, M.Smooth, { CanCollide = false })
	return m
end

local function barrel(parent, cf: CFrame)
	local prop = ownerProp(parent, "Prop_Barrel", cf, L.BarrelHeight)
	if prop then
		return prop
	end
	local m = NanoKit.Model(parent, "Barrel")
	NanoKit.Column(m, "Body", L.BarrelHeight, 2.1, cf.Position, C.Steel, M.Metal)
	for _, y in ipairs({ 0.5, L.BarrelHeight - 0.5 }) do
		NanoKit.Column(m, "Hoop", 0.25, 2.25, cf.Position + Vector3.new(0, y, 0), C.Beam, M.Metal)
	end
	return m
end

local function planter(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Planter")
	Panel(m, "Box", Vector3.new(2.6, 1.8, 2.6), cf * CFrame.new(0, 0.9, 0), C.Dado, M.Metal)
	Panel(m, "Rim", Vector3.new(2.8, 0.25, 2.8), cf * CFrame.new(0, 1.85, 0), C.Steel, M.Metal)
	Panel(m, "Soil", Vector3.new(2.3, 0.2, 2.3), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(58, 44, 34), Enum.Material.Ground)
	for i = 1, 7 do
		local angle = i * math.pi * 2 / 7
		local h = 2.4 + (i % 3) * 0.6
		Panel(m, "Leaf", Vector3.new(0.35, h, 1), cf * CFrame.new(math.cos(angle) * 0.5, 1.8 + h / 2, math.sin(angle) * 0.5) * CFrame.Angles(0, -angle, math.rad(16)), N.Leaf, Enum.Material.Grass, { CanCollide = false })
	end
	-- glass capsule (plan: plants in capsules)
	local glass = NanoKit.Column(m, "Capsule", 4.2, 3.2, (cf * CFrame.new(0, 1.9, 0)).Position, C.Glass, M.Smooth)
	glass.Transparency = 0.82
	glass.CanCollide = false
	NanoKit.Column(m, "Lid", 0.4, 3.4, (cf * CFrame.new(0, 6.1, 0)).Position, C.Steel, M.Metal)
	return m
end

local function bench(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Bench")
	Panel(m, "Seat", Vector3.new(5.6, 0.35, 1.7), cf * CFrame.new(0, 1.6, 0), C.Steel, M.Plate)
	Panel(m, "Back", Vector3.new(5.6, 1.3, 0.3), cf * CFrame.new(0, 2.55, 0.75) * CFrame.Angles(math.rad(-10), 0, 0), C.Beam, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Leg", Vector3.new(0.4, 1.45, 1.5), cf * CFrame.new(sx * 2.4, 0.72, 0), C.Beam, M.Metal)
	end
	return m
end

local function wallScreen(parent, cf: CFrame, size: Vector2)
	screenIndex = screenIndex % #L.Screens + 1
	local s = L.Screens[screenIndex]
	local m = NanoKit.Model(parent, "Screen")
	Panel(m, "Frame", Vector3.new(size.X + 0.5, size.Y + 0.5, 0.3), cf * CFrame.new(0, 0, 0.1), C.Beam, M.Metal, { CanCollide = false })
	local glass = Panel(m, "Display", Vector3.new(size.X, size.Y, 0.1), cf * CFrame.new(0, 0, -0.1), C.Screen, M.Glass, { CanCollide = false })
	text(glass, Enum.NormalId.Front, { { Text = s.Title, Size = 34, Color = N.Cyan }, { Text = s.Line, Size = 24, Color = T.Text } })
	NanoKit.Tag(glass, "Flicker")
	return m
end

local function console(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Console")
	Panel(m, "Base", Vector3.new(3.2, 2.7, 1.6), cf * CFrame.new(0, 1.35, 0), C.Beam, M.Metal)
	Panel(m, "Desk", Vector3.new(3.4, 0.3, 1.9), cf * CFrame.new(0, 2.85, -0.1) * CFrame.Angles(math.rad(14), 0, 0), C.Steel, M.Metal)
	local screen = Panel(m, "Screen", Vector3.new(3, 1.7, 0.15), cf * CFrame.new(0, 3.9, 0.55) * CFrame.Angles(math.rad(-12), 0, 0), C.Screen, M.Glass)
	text(screen, Enum.NormalId.Front, { { Text = Texts.Console, Size = 22, Color = T.Green } })
	for i = -1, 1 do
		Panel(m, "Key", Vector3.new(0.6, 0.12, 0.35), cf * CFrame.new(i * 0.9, 3.02, -0.4) * CFrame.Angles(math.rad(14), 0, 0), if i == 0 then N.Gold else C.Dado, M.Smooth, { CanCollide = false })
	end
	return m
end

local function rack(parent, cf: CFrame, width: number)
	local m = NanoKit.Model(parent, "Rack")
	local h, d = 6.4, 1.6
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Post", Vector3.new(0.3, h, d), cf * CFrame.new(sx * width / 2, h / 2, 0), C.Beam, M.Metal)
	end
	for i = 0, 3 do
		local y = 0.4 + i * 1.9
		Panel(m, "Shelf", Vector3.new(width, 0.2, d), cf * CFrame.new(0, y, 0), C.Steel, M.Plate)
		if i < 3 then
			for j = 0, 2 do
				if (i + j) % 3 ~= 2 then
					local s = 1.1 + ((i * 3 + j) % 2) * 0.3
					crate(m, cf * CFrame.new(-width / 2 + 0.9 + j * (width - 1.8) / 2, y + 0.1, 0), s)
				end
			end
		end
	end
	return m
end

local function cargo(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Cargo")
	local s = L.CrateSize
	crate(m, cf * CFrame.new(-2.4, 0, -1.9), s)
	crate(m, cf * CFrame.new(-2.2, s, -1.9) * CFrame.Angles(0, math.rad(14), 0), s * 0.75)
	crate(m, cf * CFrame.new(0.9, 0, -1.6) * CFrame.Angles(0, math.rad(-8), 0), s * 0.8)
	barrel(m, cf * CFrame.new(3.3, 0, -1.7))
	if not ownerProp(m, "Prop_Misc_4", cf * CFrame.new(1.2, 0, -4.2), L.CanisterHeight) then
		barrel(m, cf * CFrame.new(1.2, 0, -4.2))
	end
	return m
end

local function decorSet(kind: string, cf: CFrame)
	local m = NanoKit.Model(root, "Decor_" .. kind)
	if kind == "Bench" then
		bench(m, cf * CFrame.new(0, 0, -1.7))
		planter(m, cf * CFrame.new(-4.2, 0, -1.8))
		planter(m, cf * CFrame.new(4.2, 0, -1.8))
		wallScreen(m, cf * CFrame.new(0, 7.6, -0.45), Vector2.new(6.4, 3.2))
	elseif kind == "Console" then
		console(m, cf * CFrame.new(-2.4, 0, -1.3))
		console(m, cf * CFrame.new(2.4, 0, -1.3))
		wallScreen(m, cf * CFrame.new(0, 8.2, -0.45), Vector2.new(7.6, 3.4))
	elseif kind == "Rack" then
		rack(m, cf * CFrame.new(-1.2, 0, -1.2), 5.6)
		planter(m, cf * CFrame.new(3.6, 0, -1.8))
		wallScreen(m, cf * CFrame.new(0, 9.4, -0.45), Vector2.new(7, 2.8))
	elseif kind == "Cargo" then
		cargo(m, cf)
	elseif kind == "Plant" then
		planter(m, cf * CFrame.new(-1.8, 0, -1.8))
		planter(m, cf * CFrame.new(1.8, 0, -1.8))
	elseif kind == "Pipes" then
		if not ownerProp(m, "Prop_Pipes", cf * CFrame.new(-1.5, 0, -0.9), L.PipesHeight) then
			for i = 0, 2 do
				NanoKit.Column(m, "Pipe", 9, 0.8, (cf * CFrame.new(-3 + i * 1.2, 0, -0.7)).Position, C.Steel, M.Metal)
			end
		end
		barrel(m, cf * CFrame.new(2.4, 0, -1.6))
		barrel(m, cf * CFrame.new(3.6, 0, -3.4))
	end
	return m
end

-- A corner frame: 5 studs in from both walls, facing the hall center.
local function cornerFrame(hall: string, corner: string): CFrame
	local x0, x1, z0, z1 = rect(hall)
	local x = if corner:find("W") then x0 + 5 else x1 - 5
	local z = if corner:find("S") then z0 - 5 else z1 + 5
	local p = at(x, 0, z)
	local center = at((x0 + x1) / 2, 0, (z0 + z1) / 2)
	return CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)) * CFrame.new(0, 0, 2.5)
end

---------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------

-- Procedural robot (fallback when GameAssets has no model).
local function robot(parent, cf: CFrame, color: Color3, s: number)
	local m = NanoKit.Model(parent, "Robot")
	Panel(m, "Base", Vector3.new(2.6, 0.4, 2.6) * s, cf * CFrame.new(0, 0.2 * s, 0), C.Beam, M.Metal)
	Panel(m, "Legs", Vector3.new(1.6, 2.6, 1) * s, cf * CFrame.new(0, 1.7 * s, 0), C.Steel, M.Metal)
	Panel(m, "Body", Vector3.new(2.4, 2.4, 1.4) * s, cf * CFrame.new(0, 4.2 * s, 0), C.Beam, M.Metal)
	Panel(m, "Chest", Vector3.new(1.6, 1, 0.1) * s, cf * CFrame.new(0, 4.4 * s, -0.75 * s), N.Gold, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Arm", Vector3.new(0.6, 2.4, 0.6) * s, cf * CFrame.new(sx * 1.6 * s, 4 * s, 0) * CFrame.Angles(0, 0, math.rad(sx * 6)), C.Steel, M.Metal)
		Panel(m, "Shoulder", Vector3.new(0.9, 0.6, 1) * s, cf * CFrame.new(sx * 1.5 * s, 5.3 * s, 0), C.Steel, M.Metal)
	end
	local head = Panel(m, "Head", Vector3.new(1.4, 1.2, 1.3) * s, cf * CFrame.new(0, 6.1 * s, 0), C.Steel, M.Metal)
	Panel(m, "Visor", Vector3.new(1.1, 0.3, 0.1) * s, cf * CFrame.new(0, 6.15 * s, -0.66 * s), color, M.Neon, { CanCollide = false })
	m.PrimaryPart = head
	return m, head
end

-- NPC: model (GameAssets or procedural), name plate, "!" marker (hidden;
-- the client shows it) and the "Поговорить" prompt (Action = Talk).
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
	-- a small dais so the NPC reads as a place
	NanoKit.Cylinder(m, "Dais", 0.3, 5, CFrame.new(cf.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Plate)
	flatDisc(m, "DaisRing", 5.3, 0.2, cf.Position, def.Color:Lerp(C.Steel, 0.5), M.Smooth)
	local anchor = Panel(m, "Anchor", Vector3.new(1, 1, 1), CFrame.new(cf.Position.X, top + 0.5, cf.Position.Z), C.Steel, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
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
-- Halls
---------------------------------------------------------------------

local function buildAtrium()
	local H = L.Halls.Atrium.Height
	local th = theme("Atrium")
	local x0, x1, z0, z1 = rect("Atrium")
	local B = L.Balcony
	local by, depth = B.Height, B.Depth
	floor("Atrium", th)
	local doorsBySide = {}
	for _, side in ipairs({ "N", "S", "W", "E" }) do
		local openings, list = {}, {}
		for _, d in ipairs(L.Doors) do
			if d.Side == side then
				table.insert(openings, opening(side, "Atrium", d.At, d.Width, d.Height))
				table.insert(list, { Coord = d.At, Width = d.Width, Height = d.Height, To = d.To })
			end
		end
		doorsBySide[side] = list
		local blocked = table.clone(list)
		if side == "N" then
			for _, b in ipairs(L.Leaderboards) do
				table.insert(blocked, { Coord = b.At, Width = 10 })
			end
			table.insert(blocked, { Coord = L.QuestBoard.At, Width = 11 })
		end
		local a, b = sideLine(side, "Atrium")
		wall("AtriumWall" .. side, a, b, wallFrame(side, "Atrium", 0).LookVector, { Height = H, Theme = "Atrium", Openings = openings })
		pilasters("Atrium", side, by - 0.5, th, blocked)
	end

	-- runners: spawn -> gates (N-S), training <-> academy (E-W), center ring
	local m = NanoKit.Model(root, "Markings")
	local ez = -44
	Panel(m, "RunnerNS", Vector3.new(9, 0.08, z0 - z1), CFrame.new(at(0, 0.04, (z0 + z1) / 2)), C.Runner, M.Concrete, { CanCollide = false })
	Panel(m, "RunnerEW", Vector3.new(x1 - x0, 0.08, 9), CFrame.new(at(0, 0.05, ez)), C.Runner, M.Concrete, { CanCollide = false })
	for _, x in ipairs({ -4.8, 4.8 }) do
		Panel(m, "Line", Vector3.new(0.3, 0.1, z0 - z1), CFrame.new(at(x, 0.06, (z0 + z1) / 2)), C.Paint, M.Smooth, { CanCollide = false })
	end
	for _, z in ipairs({ -4.8, 4.8 }) do
		Panel(m, "Line", Vector3.new(x1 - x0, 0.1, 0.3), CFrame.new(at(0, 0.07, ez + z)), C.Paint, M.Smooth, { CanCollide = false })
	end
	local center = at(0, 0, L.Bridge.Z)
	flatDisc(m, "Ring", 34, 0.09, center, C.Paint, M.Smooth)
	flatDisc(m, "RingField", 33, 0.1, center, C.Runner, M.Concrete)
	flatDisc(m, "RingSteel", 18, 0.11, center, C.Steel, M.Plate)
	flatDisc(m, "RingInner", 17, 0.12, center, C.Runner, M.Concrete)
	flatDisc(m, "Core", 5, 0.13, center, th.Accent:Lerp(C.Steel, 0.5), M.Smooth)

	-- balcony along the walls (2nd level) on columns
	local bal = NanoKit.Model(root, "Balcony")
	local ix0, ix1, iz0, iz1 = x0 + depth, x1 - depth, z0 - depth, z1 + depth
	local slabs = {
		{ (x0 + x1) / 2, (z0 + iz0) / 2, x1 - x0, z0 - iz0 }, -- south
		{ (x0 + x1) / 2, (iz1 + z1) / 2, x1 - x0, iz1 - z1 }, -- north
		{ (x0 + ix0) / 2, (iz0 + iz1) / 2, ix0 - x0, iz0 - iz1 }, -- west
		{ (ix1 + x1) / 2, (iz0 + iz1) / 2, x1 - ix1, iz0 - iz1 }, -- east
	}
	for _, s in ipairs(slabs) do
		variant(Panel(bal, "Deck", Vector3.new(s[3], 0.8, s[4]), CFrame.new(at(s[1], by - 0.4, s[2])), th.Floor, M.Concrete), L.Materials.Floor)
		Panel(bal, "Under", Vector3.new(s[3], 0.6, s[4]), CFrame.new(at(s[1], by - 1.1, s[2])), C.Ceiling, M.Metal)
	end
	local bz, bw = L.Bridge.Z, L.Bridge.Width
	local function rail(parent, a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		if length < 1 then
			return
		end
		local cf = CFrame.lookAt((a + b) / 2, b)
		Panel(parent, "Rail", Vector3.new(0.3, 0.3, length), cf * CFrame.new(0, 3.4, 0), C.Steel, M.Metal)
		Panel(parent, "RailGlass", Vector3.new(0.12, 2.8, length), cf * CFrame.new(0, 1.9, 0), C.Glass, M.Smooth, { Transparency = 0.7 })
		Panel(parent, "RailBase", Vector3.new(0.4, 0.4, length), cf * CFrame.new(0, 0.3, 0), C.Beam, M.Metal)
		-- edge fascia under the deck with the accent line
		NanoKit.Strip(parent, (cf * CFrame.new(0, -1.5, -length / 2)).Position, (cf * CFrame.new(0, -1.5, length / 2)).Position, th.Accent, 0.1)
	end
	rail(bal, at(ix0, by, iz0), at(ix1, by, iz0))
	rail(bal, at(ix0, by, iz1), at(ix1, by, iz1))
	rail(bal, at(ix0, by, iz0), at(ix0, by, bz + bw / 2))
	rail(bal, at(ix0, by, bz - bw / 2), at(ix0, by, iz1))
	rail(bal, at(ix1, by, iz0), at(ix1, by, bz + bw / 2))
	rail(bal, at(ix1, by, bz - bw / 2), at(ix1, by, iz1))
	-- columns on the inner edge, floor -> ceiling, with lamps under the deck
	local columnCount = 0
	local function column(px: number, pz: number)
		local p = at(px, 0, pz)
		NanoKit.Column(bal, "Column", H, 1.8, p, C.Steel, M.Metal)
		NanoKit.Column(bal, "ColumnBase", 1.2, 2.6, p, C.Dado, M.Metal)
		NanoKit.Column(bal, "ColumnRing", 0.5, 2.4, p + Vector3.new(0, by - 1.6, 0), C.Beam, M.Metal)
		columnCount += 1
		if columnCount % 2 == 0 then
			local lamp = Panel(bal, "UnderLamp", Vector3.new(1.4, 0.2, 1.4), CFrame.new(p + Vector3.new(0, by - 1.5, 0)), th.Light, M.Neon, { CanCollide = false, CastShadow = false })
			spot(lamp, Enum.NormalId.Bottom, 26, 1, 110, th.Light)
		end
	end
	local c = ix0
	while c <= ix1 + 0.1 do
		column(c, iz0)
		column(c, iz1)
		c += B.Column
	end
	c = iz0 - B.Column
	while c > iz1 + 1 do
		if math.abs(c - bz) > bw / 2 + 1.5 then
			column(ix0, c)
			column(ix1, c)
		end
		c -= B.Column
	end

	-- bridge across the middle (2nd level) + stairs up to it
	local bridge = NanoKit.Model(root, "Bridge")
	local bl = ix1 - ix0
	variant(Panel(bridge, "Deck", Vector3.new(bl, 0.8, bw), CFrame.new(at(0, by - 0.4, bz)), th.Floor, M.Concrete), L.Materials.Floor)
	Panel(bridge, "Girder", Vector3.new(bl, 1.4, bw - 2), CFrame.new(at(0, by - 1.5, bz)), C.Beam, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Strip(bridge, at(-bl / 2, by - 2.25, bz + side * (bw / 2 - 1)), at(bl / 2, by - 2.25, bz + side * (bw / 2 - 1)), th.Accent, 0.12)
	end
	local sw = L.StairWidth
	local function bridgeRail(z: number, gaps)
		local xs = { -bl / 2 }
		for _, gx in ipairs(gaps) do
			table.insert(xs, gx - sw / 2)
			table.insert(xs, gx + sw / 2)
		end
		table.insert(xs, bl / 2)
		table.sort(xs)
		for i = 1, #xs - 1, 2 do
			rail(bridge, at(xs[i], by, z), at(xs[i + 1], by, z))
		end
	end
	local southX, northX = {}, {}
	for _, st in ipairs(L.Stairs) do
		table.insert(if st.Z0 > bz then southX else northX, st.X)
	end
	bridgeRail(bz + bw / 2, southX)
	bridgeRail(bz - bw / 2, northX)
	for _, st in ipairs(L.Stairs) do
		local top = if st.Z0 > bz then bz + bw / 2 else bz - bw / 2
		local run = st.Z0 - top
		local steps = math.ceil(by / 0.8)
		local tread = run / steps
		local rise = by / steps
		local sm = NanoKit.Model(root, "Stairs")
		for i = 1, steps do
			local h = rise * i
			local z = st.Z0 - tread * (i - 0.5)
			Panel(sm, "Step", Vector3.new(sw, h, math.abs(tread) + 0.05), CFrame.new(at(st.X, h / 2, z)), if i % 2 == 0 then th.Floor else th.Floor:Lerp(C.Steel, 0.2), M.Concrete)
			Panel(sm, "Nosing", Vector3.new(sw, 0.12, 0.3), CFrame.new(at(st.X, h + 0.02, z + (tread / 2 - math.sign(tread) * 0.15))), C.Paint, M.Smooth, { CanCollide = false })
		end
		for _, sx in ipairs({ -1, 1 }) do
			local a = at(st.X + sx * (sw / 2 + 0.2), 0, st.Z0)
			local b = at(st.X + sx * (sw / 2 + 0.2), by, top)
			local length = (b - a).Magnitude
			local cf = CFrame.lookAt((a + b) / 2, b)
			Panel(sm, "Stringer", Vector3.new(0.4, 1.2, length), cf, C.Beam, M.Metal)
			Panel(sm, "Handrail", Vector3.new(0.25, 0.25, length), cf * CFrame.new(0, 3.4, 0), C.Steel, M.Metal)
			Panel(sm, "Glass", Vector3.new(0.1, 2.8, length - 1), cf * CFrame.new(0, 1.9, 0), C.Glass, M.Smooth, { Transparency = 0.72 })
		end
	end

	-- ceiling: solid around a skylight on trusses with pendant lamps
	local S = L.Skylight
	local sx0, sx1, sz0, sz1 = S.Rect[1], S.Rect[2], S.Rect[3], S.Rect[4]
	local roof = NanoKit.Model(root, "AtriumCeiling")
	local cy = H + 0.5
	local ox0, ox1, oz0, oz1 = x0 - WT, x1 + WT, z0 + WT, z1 - WT
	Panel(roof, "Roof", Vector3.new(sx0 - ox0, 1, oz0 - oz1), CFrame.new(at((ox0 + sx0) / 2, cy, (oz0 + oz1) / 2)), C.Ceiling, M.Metal)
	Panel(roof, "Roof", Vector3.new(ox1 - sx1, 1, oz0 - oz1), CFrame.new(at((sx1 + ox1) / 2, cy, (oz0 + oz1) / 2)), C.Ceiling, M.Metal)
	Panel(roof, "Roof", Vector3.new(sx1 - sx0, 1, oz0 - sz0), CFrame.new(at((sx0 + sx1) / 2, cy, (oz0 + sz0) / 2)), C.Ceiling, M.Metal)
	Panel(roof, "Roof", Vector3.new(sx1 - sx0, 1, sz1 - oz1), CFrame.new(at((sx0 + sx1) / 2, cy, (sz1 + oz1) / 2)), C.Ceiling, M.Metal)
	Panel(roof, "Glass", Vector3.new(sx1 - sx0, 0.2, sz0 - sz1), CFrame.new(at((sx0 + sx1) / 2, H + 0.4, (sz0 + sz1) / 2)), C.Glass, M.Glass, { Transparency = 0.6, CastShadow = false })
	local z = sz0
	local yTop, yBottom = H - 0.4, H - 3
	while z >= sz1 - 0.1 do
		Panel(roof, "TopChord", Vector3.new(ix1 - ix0, 0.8, 1.2), CFrame.new(at(0, yTop, z)), C.Beam, M.Metal)
		Panel(roof, "BottomChord", Vector3.new(ix1 - ix0, 0.8, 1.4), CFrame.new(at(0, yBottom, z)), C.Beam, M.Metal)
		local n = math.floor((ix1 - ix0) / 6)
		for i = 0, n do
			local xx = ix0 + i * 6
			Panel(roof, "Strut", Vector3.new(0.4, 2.2, 0.6), CFrame.new(at(xx, (yTop + yBottom) / 2, z)), C.Steel, M.Metal)
			if i < n then
				local p1 = at(xx, if i % 2 == 0 then yBottom else yTop, z)
				local p2 = at(xx + 6, if i % 2 == 0 then yTop else yBottom, z)
				Panel(roof, "Diagonal", Vector3.new(0.35, 0.35, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2), C.Steel, M.Metal)
			end
		end
		for _, px in ipairs({ -36, 0, 36 }) do
			local top = at(px, yBottom - 0.4, z)
			Panel(roof, "PendantRod", Vector3.new(0.12, L.Pendant.Drop, 0.12), CFrame.new(top - Vector3.new(0, L.Pendant.Drop / 2, 0)), C.Beam, M.Metal, { CanCollide = false, CastShadow = false })
			local shade = NanoKit.Cylinder(roof, "Shade", 0.9, 2.6, CFrame.new(top - Vector3.new(0, L.Pendant.Drop + 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Metal)
			shade.CanCollide = false
			local bulb = NanoKit.Cylinder(roof, "Bulb", 0.1, 2, CFrame.new(top - Vector3.new(0, L.Pendant.Drop + 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), th.Light, M.Neon)
			bulb.CanCollide = false
			bulb.CastShadow = false
			local light = Instance.new("PointLight")
			light.Color = th.Light
			light.Range = L.Pendant.Range
			light.Brightness = L.Pendant.Brightness
			light.Parent = bulb
		end
		z -= S.Truss
	end
	for zz = sz0 - S.Mullion, sz1 + S.Mullion, -S.Mullion do
		Panel(roof, "Mullion", Vector3.new(sx1 - sx0, 0.3, 0.3), CFrame.new(at((sx0 + sx1) / 2, H + 0.15, zz)), C.Beam, M.Metal)
	end

	-- arches (themed by the hall behind) + hall signs under the balcony
	for side, list in pairs(doorsBySide) do
		for _, d in ipairs(list) do
			local cf = wallFrame(side, "Atrium", d.Coord)
			local target = L.Halls[d.To]
			local tth = theme(target.Theme)
			archFrame(root, cf, d.Width, d.Height, tth)
			if d.To ~= "Spawn" then
				hangingSign(root, cf, Texts[d.To] or target.Name, Texts[d.To .. "Sub"], tth.Accent)
			end
		end
	end
end

-- A side hall: floor, walls (the side shared with the atrium is dressed
-- from inside only, WT further in), pilasters, ceiling, its big name over
-- the entrance. extra = more openings { Side, At, Width, Height }.
local function sideHall(name: string, sharedSide: string, extra)
	local def = L.Halls[name]
	local th = theme(def.Theme)
	local H = def.Height
	floor(name, th)
	for _, side in ipairs({ "N", "S", "W", "E" }) do
		local shared = side == sharedSide
		local shift = if shared then WT else 0
		local inward = wallFrame(side, name, 0).LookVector
		local a, b = sideLine(side, name)
		a += inward * shift
		b += inward * shift
		local openings, list = {}, {}
		if shared then
			for _, d in ipairs(L.Doors) do
				if d.To == name then
					table.insert(openings, opening(side, name, d.At, d.Width, d.Height))
					table.insert(list, { Coord = d.At, Width = d.Width })
				end
			end
		end
		for _, o in ipairs(extra or {}) do
			if o.Side == side then
				table.insert(openings, opening(side, name, o.At, o.Width, o.Height))
				table.insert(list, { Coord = o.At, Width = o.Width + 8 })
			end
		end
		wall(name .. "Wall" .. side, a, b, inward, { Height = H, Theme = def.Theme, Openings = openings, NoSlab = shared })
		pilasters(name, side, H, th, list, shift)
	end
	ceiling(name, H, th)
	for _, d in ipairs(L.Doors) do
		if d.To == name and name ~= "Spawn" then
			local cf = wallFrame(sharedSide, name, d.At, WT)
			signPlate(root, cf * CFrame.new(0, d.Height + 3.2, -0.6), Vector2.new(16, 3.4), { { Text = Texts[name] or def.Name, Size = 60, Color = N.Gold }, { Text = Texts[name .. "Sub"] or "", Size = 30, Color = th.Accent } })
		end
	end
end

local function buildSpawn()
	sideHall("Spawn", "N")
	local th = theme("Spawn")
	local m = NanoKit.Model(root, "SpawnPlaza")
	flatDisc(m, "SpawnRing", 12, 0.06, at(0, 0, 0), C.Paint, M.Smooth)
	flatDisc(m, "SpawnPlate", 11.4, 0.07, at(0, 0, 0), C.Steel, M.Plate)
	flatDisc(m, "SpawnGlow", 9, 0.08, at(0, 0, 0), th.Accent:Lerp(C.Steel, 0.6), M.Smooth)
	-- closed city door on the south wall with the city title
	local cf = wallFrame("S", "Spawn", 0)
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Door", Vector3.new(6, 12, 0.6), cf * CFrame.new(side * 3, 6, -0.5), C.Steel, M.Metal)
		Panel(m, "DoorRib", Vector3.new(5, 0.3, 0.75), cf * CFrame.new(side * 3, 4, -0.55), C.Beam, M.Metal)
		Panel(m, "DoorRib", Vector3.new(5, 0.3, 0.75), cf * CFrame.new(side * 3, 8, -0.55), C.Beam, M.Metal)
		NanoKit.Strip(m, (cf * CFrame.new(side * 6.4, 0.5, -0.9)).Position, (cf * CFrame.new(side * 6.4, 12, -0.9)).Position, th.Accent, 0.14)
	end
	Panel(m, "DoorFrame", Vector3.new(14, 1.2, 1.2), cf * CFrame.new(0, 12.6, -0.6), C.Beam, M.Metal)
	signPlate(m, cf * CFrame.new(0, 15.6, -0.6), Vector2.new(20, 3.6), { { Text = Texts.Title, Size = 72, Color = N.Gold }, { Text = Texts.TitleSub, Size = 30, Color = th.Accent } })
end

-- Gate hall: giant gates on the spawn axis, set into the north wall.
-- Red Gates (event, GateService): a smaller gate on the west wall of the
-- Gate hall. Its field, curtains and light are hidden until the event.
local function buildRedGate()
	local R = Config.RedGate
	local m = NanoKit.Model(root, "RedGate")
	local cf = wallFrame("W", "Gates", -194)
	local w, h = 12, 16
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Pylon", Vector3.new(3, h + 3, 4), cf * CFrame.new(side * (w / 2 + 1.5), (h + 3) / 2, -2), C.Beam, M.Metal)
		Panel(m, "PylonFace", Vector3.new(1.6, h - 2, 0.3), cf * CFrame.new(side * (w / 2 + 1.5), h / 2, -4.1), C.Steel, M.Plate)
	end
	Panel(m, "Lintel", Vector3.new(w + 6, 3, 4), cf * CFrame.new(0, h + 1.5, -2), C.Beam, M.Metal)
	Panel(m, "Back", Vector3.new(w, h, 0.6), cf * CFrame.new(0, h / 2, -0.4), C.Tunnel, M.Smooth)
	local plate = Panel(m, "Sign", Vector3.new(w + 4, 2.4, 0.3), cf * CFrame.new(0, h + 4.4, -2.4), T.PanelDark, M.Smooth, { CanCollide = false })
	text(plate, Enum.NormalId.Front, { { Text = R.Texts.Name, Size = 56, Color = R.Color } })
	local parts = {}
	local field = Panel(m, "RedField", Vector3.new(w, h, 0.6), cf * CFrame.new(0, h / 2, -2.6), R.Color, Enum.Material.ForceField, { CanCollide = false, Transparency = 1, CastShadow = false })
	field:SetAttribute("OnTransparency", 0.2)
	table.insert(parts, field)
	for i = 1, 3 do
		local curtain = Panel(m, "RedCurtain", Vector3.new(w / 3 + 0.4, h - 0.4, 0.1), cf * CFrame.new(-w / 2 + w * (i - 0.5) / 3, h / 2, -2.9 - (i % 2) * 0.2), R.Color, M.Neon, { CanCollide = false, CanQuery = false, Transparency = 1, CastShadow = false })
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

local function buildGates()
	local P = L.Portal
	sideHall("Gates", "S", { { Side = "N", At = 0, Width = P.Width, Height = P.Height } })
	local th = theme("Gates")
	local m = NanoKit.Model(root, "Gates")
	local cf = wallFrame("N", "Gates", 0)
	local fw, fd = P.FrameWidth, P.FrameDepth
	local half = P.Width / 2
	Panel(m, "Dais", Vector3.new(P.Width + fw * 2 + 8, 0.6, fd + 8), cf * CFrame.new(0, 0.3, -(fd + 8) / 2), C.Steel, M.Plate)
	Panel(m, "DaisEdge", Vector3.new(P.Width + fw * 2 + 8.4, 0.2, 0.6), cf * CFrame.new(0, 0.55, -(fd + 8) + 0.2), th.Accent, M.Smooth)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (half + fw / 2)
		Panel(m, "Pylon", Vector3.new(fw, P.Height + 6, fd), cf * CFrame.new(x, (P.Height + 6) / 2, -fd / 2), C.Beam, M.Metal)
		Panel(m, "PylonFace", Vector3.new(fw - 1.6, P.Height - 2, 0.3), cf * CFrame.new(x, P.Height / 2 + 1, -fd - 0.1), C.Steel, M.Plate)
		Panel(m, "PylonBase", Vector3.new(fw + 1.4, 2.4, fd + 1.4), cf * CFrame.new(x, 1.8, -fd / 2), C.Dado, M.Metal)
		for i = 1, 4 do
			Panel(m, "Band", Vector3.new(fw + 0.3, 0.4, fd + 0.3), cf * CFrame.new(x, 2 + i * (P.Height / 4.4), -fd / 2), C.Steel, M.Metal)
		end
		NanoKit.Strip(m, (cf * CFrame.new(side * (half + 0.05), 2, -fd + 0.6)).Position, (cf * CFrame.new(side * (half + 0.05), P.Height - 0.5, -fd + 0.6)).Position, th.Accent, 0.2)
		local lamp = Panel(m, "Lamp", Vector3.new(1.8, 0.6, 1.2), cf * CFrame.new(x, P.Height - 1, -fd - 0.7), C.Steel, M.Metal)
		spot(lamp, Enum.NormalId.Bottom, 30, 1.8, 100, th.Light)
		-- tall obelisks further out (the reference's columns)
		local px = side * (half + fw + 9)
		NanoKit.Column(m, "Obelisk", P.Height + 10, 3.4, (cf * CFrame.new(px, 0, -4)).Position, C.Beam, M.Metal)
		NanoKit.Column(m, "ObeliskBase", 2, 5, (cf * CFrame.new(px, 0, -4)).Position, C.Dado, M.Metal)
		NanoKit.Strip(m, (cf * CFrame.new(px, 3, -5.8)).Position, (cf * CFrame.new(px, P.Height + 8, -5.8)).Position, th.Accent, 0.18)
	end
	local lw = P.Width + fw * 2
	Panel(m, "Lintel", Vector3.new(lw, 5.4, fd), cf * CFrame.new(0, P.Height + 2.7, -fd / 2), C.Beam, M.Metal)
	Panel(m, "LintelFace", Vector3.new(lw - 2, 3, 0.3), cf * CFrame.new(0, P.Height + 2.7, -fd - 0.1), C.Steel, M.Plate)
	Panel(m, "Cap", Vector3.new(lw + 1.4, 0.8, fd + 0.8), cf * CFrame.new(0, P.Height + 5.8, -fd / 2), C.Steel, M.Metal)
	-- dark tunnel behind the opening
	Panel(m, "TunnelBack", Vector3.new(P.Width + 2, P.Height + 2, 1), cf * CFrame.new(0, P.Height / 2, WT + 8), C.Tunnel, M.Smooth)
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "TunnelSide", Vector3.new(1, P.Height + 2, 9), cf * CFrame.new(side * (half + 1), P.Height / 2, WT + 3.5), C.Tunnel, M.Smooth)
	end
	Panel(m, "TunnelTop", Vector3.new(P.Width + 2, 1, 9), cf * CFrame.new(0, P.Height + 1, WT + 3.5), C.Tunnel, M.Smooth)
	Panel(m, "TunnelFloor", Vector3.new(P.Width + 2, 1, 9), cf * CFrame.new(0, -0.5, WT + 3.5), C.Tunnel, M.Smooth)
	local field = Panel(m, "PortalField", Vector3.new(P.Width, P.Height, 0.6), cf * CFrame.new(0, P.Height / 2, -fd + 1.8), th.Accent, Enum.Material.ForceField, { CanCollide = false, Transparency = 0.3, CastShadow = false })
	field:SetAttribute("Portal", true)
	for i = 1, P.Curtains do
		local x = -half + P.Width * (i - 0.5) / P.Curtains
		local color = if i % 2 == 0 then N.Magenta else th.Accent
		local curtain = Panel(m, "Curtain", Vector3.new(P.Width / P.Curtains + 0.6, P.Height - 0.4, 0.1), cf * CFrame.new(x, P.Height / 2, -fd + 2.3 + (i % 2) * 0.25), color, M.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, Transparency = P.CurtainTransparency, CastShadow = false })
		NanoKit.Tag(curtain, "Pulse", { Period = 2.2 + i * 0.35 })
	end
	WorldKit.Light(field, th.Accent, 30, 1.4)
	local sh = P.SignHeight
	signPlate(m, cf * CFrame.new(0, P.Height + 6.2 + sh / 2, -fd - 0.1), Vector2.new(lw + 6, sh), { { Text = Texts.Portal, Size = 96, Color = N.Gold }, { Text = Texts.PortalSub, Size = 36, Color = th.Accent } })
	return field
end

-- Зал снабжения (west, where the training hall was): the capsule
-- machine in the middle (HubGuide builds it), the AFK portal by the north
-- wall, benches and plants along the walls, a soft violet light.
local function buildSupplyHall()
	sideHall("Supply", "E")
	local th = theme("Supply")
	local folder = NanoKit.Model(root, "SupplyHall")
	-- a round carpet of light under the machine
	local c = at(L.Supply.At[1], 0, L.Supply.At[2])
	flatDisc(folder, "Carpet", 22, 0.08, c, th.Floor:Lerp(th.Accent, 0.18), M.Smooth)
	flatDisc(folder, "CarpetRim", 22.6, 0.06, c, th.Accent, M.Neon).Transparency = 0.6
	-- the AFK portal: an arch with a slow violet field (prompt "АФК")
	local A = L.AfkPortal
	local p = at(A.At[1], 0, A.At[2])
	local cf = CFrame.lookAt(p, at(A.Face[1], 0, A.Face[2]))
	local portal = NanoKit.Model(folder, "AfkPortal")
	for _, sx in ipairs({ -1, 1 }) do
		Panel(portal, "Post", Vector3.new(1.6, 11, 1.6), cf * CFrame.new(sx * 5, 5.5, 0), C.Steel, M.Metal)
		NanoKit.Strip(portal, (cf * CFrame.new(sx * 5, 0.5, -0.85)).Position, (cf * CFrame.new(sx * 5, 10.5, -0.85)).Position, th.Accent, 0.16)
	end
	Panel(portal, "Lintel", Vector3.new(11.6, 1.4, 1.8), cf * CFrame.new(0, 11.4, 0), C.Steel, M.Metal)
	local field = Panel(portal, "Field", Vector3.new(8.4, 10, 0.2), cf * CFrame.new(0, 5.5, 0), th.Accent, M.Neon, { Transparency = 0.72, CanCollide = false })
	NanoKit.Tag(field, "Pulse", { Period = 3 })
	local light = Instance.new("PointLight")
	light.Color = th.Accent
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = field
	signPlate(portal, cf * CFrame.new(0, 13.4, -0.4), Vector2.new(10, 2.6), { { Text = Texts.AfkPortal, Size = 60, Color = N.Gold }, { Text = Texts.AfkPortalSub, Size = 28, Color = th.Accent } })
	local anchor = Panel(portal, "PromptAnchor", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3, -3), th.Accent, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	WorldKit.Prompt(anchor, L.Prompts.Afk, "", { Action = "OpenAfk" })
	return folder
end

-- Fabricator: the central forge (Hearth / Anvil names are used by
-- CraftService), the console with the prompt, a conveyor by the east wall.
local function buildForge()
	sideHall("Forge", "W")
	local th = theme("Forge")
	local x0, x1, z0, z1 = rect("Forge")
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local m = NanoKit.Model(root, "Forge")
	local center = at(cx, 0, cz)
	for i = 0, 3 do
		Panel(m, "Octagon", Vector3.new(16, 0.8, 6.6), CFrame.new(center + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, math.rad(i * 45), 0), C.Beam, M.Plate)
	end
	flatDisc(m, "OctRing", 17.4, 0.05, center, th.Accent:Lerp(C.Steel, 0.4), M.Smooth)
	local core = ownerProp(m, L.Models.ForgeCore, CFrame.new(center + Vector3.new(0, 0.8, 0)), 12, true)
	local hearthPos = center + Vector3.new(0, 5, 0)
	if core then
		local box = core:GetBoundingBox()
		hearthPos = box.Position
	else
		NanoKit.Column(m, "ReactorBase", 2, 7, center + Vector3.new(0, 0.8, 0), C.Dado, M.Metal)
		local glass = NanoKit.Column(m, "ReactorGlass", 6, 4.4, center + Vector3.new(0, 2.8, 0), C.Glass, M.Smooth)
		glass.Transparency = 0.75
		glass.CanCollide = false
		NanoKit.Column(m, "ReactorCap", 1, 6, center + Vector3.new(0, 8.8, 0), C.Steel, M.Metal)
		NanoKit.Column(m, "Chimney", 10, 2.4, center + Vector3.new(0, 9.8, 0), C.Beam, M.Metal)
		for i = 0, 5 do
			local a = i * math.pi / 3
			NanoKit.Column(m, "Cage", 8.4, 0.4, center + Vector3.new(math.cos(a) * 3.2, 0.8, math.sin(a) * 3.2), C.Steel, M.Metal)
		end
	end
	local hearth = Panel(m, "Hearth", Vector3.new(2.6, 2.6, 2.6), CFrame.new(hearthPos), Color3.fromRGB(255, 120, 40), M.Neon, { CanCollide = false, Shape = Enum.PartType.Ball, Transparency = 0.1 })
	local glow = WorldKit.Light(hearth, Color3.fromRGB(255, 130, 60), 26, 1.8)
	glow.Name = "Glow"
	local fire = Instance.new("Fire")
	fire.Name = "Fire"
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 200, 80)
	fire.Size = 5
	fire.Heat = 6
	fire.Parent = hearth
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80), Color3.new(1, 1, 1))
	sparks.LightEmission = 0.8
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Rate = 0
	sparks.Parent = hearth
	NanoKit.Tag(hearth, "Pulse", { Period = 1.6 })
	if core then
		-- the model has its own hammer arm: a small hidden anvil spot for the sparks
		hearth.Size = Vector3.new(1.8, 1.8, 1.8)
		hearth.Transparency = 0.35
		local box, size = core:GetBoundingBox()
		local anvil = Panel(m, "Anvil", Vector3.new(1, 1, 1), CFrame.new(box.Position - Vector3.new(0, size.Y * 0.15, 0)), C.Steel, M.Smooth, { Transparency = 1, CanCollide = false })
		local anvilSparks = sparks:Clone()
		anvilSparks.Color = ColorSequence.new(N.Gold, Color3.new(1, 1, 1))
		anvilSparks.Parent = anvil
	else
		-- press table ("Anvil") with the manipulator, in front of the core
		local anvilCf = CFrame.lookAt(center + Vector3.new(-10, 0.8, 0), center + Vector3.new(-20, 0.8, 0))
		Panel(m, "AnvilBase", Vector3.new(4, 2.4, 3), anvilCf * CFrame.new(0, 1.2, 0), C.Beam, M.Metal)
		local anvil = Panel(m, "Anvil", Vector3.new(4.6, 0.6, 3.4), anvilCf * CFrame.new(0, 2.7, 0), C.Steel, M.Plate)
		local anvilSparks = sparks:Clone()
		anvilSparks.Color = ColorSequence.new(N.Gold, Color3.new(1, 1, 1))
		anvilSparks.Parent = anvil
		NanoKit.Column(m, "ArmPost", 12, 0.9, (anvilCf * CFrame.new(-3, 0, 1)).Position, C.Steel, M.Metal)
		Panel(m, "Manipulator", Vector3.new(4.4, 0.7, 0.7), anvilCf * CFrame.new(-1, 11, 1), N.Gold, M.Metal)
		local hammer = Panel(m, "Hammer", Vector3.new(1.3, 2, 1.3), anvilCf * CFrame.new(0.4, 9.4, 1), C.Beam, M.Metal)
		NanoKit.Tag(hammer, "Bob", { Amplitude = 0.6, Period = 2.2 })
	end
	-- console with the prompt next to the press
	local c = console(m, CFrame.lookAt(at(x0 + 9, 0, cz + 9), at(x0, 0, cz + 9)))
	local prompt = WorldKit.Prompt(c:FindFirstChild("Base"), L.Prompts.Forge, "", { Action = "OpenForge" }, 12)
	-- conveyor belt along the east wall with sliding crates
	local belt = NanoKit.Model(root, "Conveyor")
	local bx = x1 - 5
	local len = (z0 - z1) - 16
	Panel(belt, "Frame", Vector3.new(4, 2, len), CFrame.new(at(bx, 1, cz)), C.Beam, M.Metal)
	Panel(belt, "Belt", Vector3.new(3.4, 0.2, len), CFrame.new(at(bx, 2.1, cz)), Color3.fromRGB(30, 30, 32), M.Smooth)
	for _, side in ipairs({ -1, 1 }) do
		Panel(belt, "Guard", Vector3.new(0.3, 0.6, len), CFrame.new(at(bx + side * 1.9, 2.4, cz)), C.Steel, M.Metal)
	end
	for i = 0, 5 do
		local box = Panel(belt, "BeltCrate", Vector3.new(1.8, 1.6, 1.8), CFrame.lookAt(at(bx, 3, cz + len / 2 - 1), at(bx, 3, cz - len / 2)), C.Steel, M.Plate, { CanCollide = false })
		NanoKit.Tag(box, "Conveyor", { Length = len - 2, Speed = 2.5, Start = i * (len - 2) / 6 })
	end
	for _, zz in ipairs({ z0 - 4, z1 + 4 }) do
		Panel(belt, "Hopper", Vector3.new(5, 5, 4), CFrame.new(at(bx, 2.5, zz)), C.Steel, M.Metal)
		NanoKit.Strip(belt, at(bx - 2.5, 4.8, zz + (if zz > cz then -2.05 else 2.05)), at(bx + 2.5, 4.8, zz + (if zz > cz then -2.05 else 2.05)), th.Accent, 0.12)
	end
	return prompt, m
end

-- Academy: 3 class pedestals around the center with the class weapon
-- floating over each, facing the entrance; the terminal by the door.
local function buildAcademy()
	sideHall("Academy", "W")
	local th = theme("Academy")
	local x0, x1, z0, z1 = rect("Academy")
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local m = NanoKit.Model(root, "Academy")
	local center = at(cx + 4, 0, cz)
	flatDisc(m, "Ring", 34, 0.06, center, th.Accent:Lerp(C.Steel, 0.4), M.Smooth)
	flatDisc(m, "RingField", 33.2, 0.07, center, th.Floor, M.Concrete)
	local spots = { Vector3.new(-6, 0, -11), Vector3.new(8, 0, 0), Vector3.new(-6, 0, 11) }
	local pedestals = {}
	local entrance = at(x0, 0, cz)
	for i, class in ipairs(Config.Classes) do
		local p = center + spots[i]
		local face = CFrame.lookAt(p, Vector3.new(entrance.X, p.Y, entrance.Z))
		NanoKit.Cylinder(m, "PedestalBase", 1.2, 6, CFrame.new(p + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Beam, M.Metal)
		local top = NanoKit.Cylinder(m, "Pedestal", 0.5, 5, CFrame.new(p + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Plate)
		-- thin glowing edge only (the ring sits inside the top, its rim shows)
		local ring = NanoKit.Cylinder(m, "PedestalRing", 0.2, 5.25, CFrame.new(p + Vector3.new(0, 1.45, 0)) * CFrame.Angles(0, 0, math.rad(90)), class.Color, M.Neon)
		ring.CanCollide = false
		NanoKit.Cylinder(m, "PedestalInlay", 0.06, 3.2, CFrame.new(p + Vector3.new(0, 1.66, 0)) * CFrame.Angles(0, 0, math.rad(90)), class.Color:Lerp(C.Beam, 0.7), M.Metal).CanCollide = false
		local look = table.clone(Config.Weapons[1])
		look.Class = class.Id
		look.Rarity = "Rare"
		local ok, model = pcall(WeaponBuilder.Build, look)
		if ok and model then
			WeaponBuilder.SetAnchored(model, true)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
				end
			end
			local size = model:GetExtentsSize()
			pcall(model.ScaleTo, model, math.clamp(5 / math.max(size.X, size.Y, size.Z, 0.1), 0.5, 4))
			-- upright over the pedestal: rotate, then move the box center there
			model:PivotTo(CFrame.new(model:GetPivot().Position) * CFrame.Angles(0, 0, math.rad(70)))
			local box = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + (p + Vector3.new(0, 5, 0) - box.Position))
			model.WorldPivot = CFrame.new(p + Vector3.new(0, 5, 0)) * model:GetPivot().Rotation -- spins in place
			model.Name = "ClassWeapon_" .. class.Id
			model.Parent = m
			NanoKit.Tag(model, "Spin", { Speed = 30, Axis = "Y" })
		end
		signPlate(m, face * CFrame.new(0, 10, 0), Vector2.new(7, 1.8), { { Text = class.Name, Size = 44, Color = class.Color } }, true)
		local lampPart = Panel(m, "Spot", Vector3.new(1.4, 0.4, 0.8), CFrame.lookAt(p + Vector3.new(-4, L.Halls.Academy.Height - 1.5, 0), p), C.Steel, M.Metal, { CanCollide = false })
		spot(lampPart, Enum.NormalId.Front, 28, 1.6, 40, class.Color:Lerp(th.Light, 0.6))
		pedestals[i] = top
	end
	local terminal = console(m, CFrame.lookAt(at(x0 + 7, 0, cz - 14), at(x0 + 7, 0, cz + 20)))
	terminal.Name = "Terminal"
	local _ = x1 + z0 + z1
	return { Model = m, Pedestals = pedestals, Terminal = terminal }
end

local function leaderboard(cf: CFrame, def)
	local m = NanoKit.Model(root, "Leaderboard_" .. def.Kind)
	Panel(m, "Frame", Vector3.new(9.8, 12.4, 0.3), cf * CFrame.new(0, 8.2, -0.15), C.Steel, M.Metal)
	local board = Panel(m, "Board", Vector3.new(9, 11.6, 0.3), cf * CFrame.new(0, 8.2, -0.45), T.PanelDark, M.Smooth)
	local lines = { { Name = "Title", Text = def.Title, Size = 30, Color = N.Gold } }
	for i = 1, Config.Leaderboards.Top do
		table.insert(lines, { Name = "Row" .. i, Text = i .. ". —", Size = 18 })
	end
	local frame = WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 50)
	local lamp = Panel(m, "Lamp", Vector3.new(4, 0.4, 0.7), cf * CFrame.new(0, 14.9, -1.2), C.Steel, M.Metal)
	spot(lamp, Enum.NormalId.Bottom, 14, 0.8, 110)
	return frame
end

---------------------------------------------------------------------

function HubGenerator.Build()
	root = Instance.new("Folder")
	root.Name = "Hub"

	lampIndex = 0

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	base = Vector3.new(origin.X, groundY, origin.Z)
	if spawn then
		spawn.CFrame = CFrame.new(spawn.Position) -- players appear facing north (the gates)
		spawn.Transparency = 1
		for _, d in ipairs(spawn:GetChildren()) do
			if d:IsA("Decal") then
				d.Transparency = 1
			end
		end
	end
	-- one big foundation under everything (nobody falls out)
	Panel(root, "Foundation", Vector3.new(420, 1, 300), CFrame.new(at(-10, -1.6, -100)), C.Ceiling, M.Concrete)

	buildAtrium()
	buildSpawn()
	local portal = buildGates()
	local redGate = buildRedGate()
	buildSupplyHall()
	local forgePrompt, forge = buildForge()
	local academy = buildAcademy()

	-- 8 leaderboards and 9 the quest board by the Gate hall arch
	local boards = {}
	for _, def in ipairs(L.Leaderboards) do
		boards[def.Kind] = leaderboard(wallFrame("N", "Atrium", def.At), def)
	end
	local qcf = wallFrame("N", "Atrium", L.QuestBoard.At)
	local qb = NanoKit.Model(root, "QuestBoard")
	Panel(qb, "Frame", Vector3.new(10.4, 8.4, 0.3), qcf * CFrame.new(0, 6.6, -0.15), C.Steel, M.Metal)
	local qboard = Panel(qb, "Board", Vector3.new(9.6, 7.6, 0.3), qcf * CFrame.new(0, 6.6, -0.45), T.PanelDark, M.Smooth)
	WorldKit.SurfaceText(qboard, Enum.NormalId.Front, { { Text = Texts.QuestBoard, Size = 44, Color = N.Gold }, { Text = Texts.QuestBoardSub, Size = 22, Color = theme("Gates").Accent } }, 50)
	local qlamp = Panel(qb, "Lamp", Vector3.new(4, 0.4, 0.7), qcf * CFrame.new(0, 11.4, -1.2), C.Steel, M.Metal)
	spot(qlamp, Enum.NormalId.Bottom, 14, 0.8, 110)
	local boardPrompt = WorldKit.Prompt(qboard, L.Prompts.Board, "", { Action = "Talk", Npc = "GateKeeper" }, 12)

	-- decor groups
	for _, d in ipairs(L.Decor) do
		local cf = if d.Corner then cornerFrame(d.Hall, d.Corner) else wallFrame(d.Wall, d.Hall, d.At)
		decorSet(d.Kind, cf)
	end

	-- NPCs: the mentor next to the spawn facing it, the gate keeper by the board
	local mp = at(L.Mentor.Offset.X, 0, L.Mentor.Offset.Z)
	local mentor = npc("Mentor", L.Models.Mentor, CFrame.lookAt(mp, at(L.Mentor.Face.X, 0, L.Mentor.Face.Z)))
	local gp = at(L.GateKeeper.Offset.X, 0, L.GateKeeper.Offset.Z)
	local keeper = npc("GateKeeper", L.Models.GateKeeper, CFrame.lookAt(gp, gp + Vector3.new(0, 0, 10)))

	-- way-finding: floor lines, sign posts, hall centerpieces, the supply terminal
	local guide = require(script.Parent.HubGuide).Build(root, base)

	local waypoints = {}
	for name, offset in pairs(L.Waypoints) do
		waypoints[name] = base + offset
	end
	root:SetAttribute("Center", at(0, 0, L.Bridge.Z))
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
		Guide = guide,
		Waypoints = waypoints,
		SpawnCFrame = CFrame.lookAt(at(0, 4, 0), at(0, 4, -10)),
		GroundY = base.Y,
	}
end

return HubGenerator
