--[[
	HubGenerator.luau
	Builds the hub "Нано-Цитадель" at server start (Workspace.Hub): a
	plaza of a floating technopolis. Graphite / dark steel / concrete,
	warm white light, thin cyan and magenta neon lines (Config.Nano).
	Building blocks: NanoKit; owner props (GameAssets) where they fit.

	Zones (Config.HubLayout, south = spawn, north = gates):
	  Spawn plaza + entrance arch, the avenue with lamps and pylons,
	  the holo tower in the middle, the Gates (portal to the dungeon),
	  the Fabricator hall (forge), the Incubator (pet eggs), the wheel,
	  the store kiosk, the Polygon arena (dummies: PolygonService), the
	  leaderboards; perimeter walls with corner pylons, a bridge over the
	  avenue, floating platforms, cables, vents, cargo, drones.
	Moving things (drones, rings, fans, platforms, flicker) are tagged for
	the client (HubLife.luau); prompts only open client windows.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local L = Config.HubLayout
local N = Config.Nano
local T = Config.Theme
local Texts = L.Texts
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local EAST = Vector3.new(1, 0, 0)
local WEST = Vector3.new(-1, 0, 0)
local SOUTH = Vector3.new(0, 0, 1)

local root, base

local function at(offset: Vector3): Vector3
	return base + offset
end

-- Ground-level frame at an offset whose front (-Z) looks along `dir`.
local function frame(offset: Vector3, dir: Vector3): CFrame
	local pos = at(offset)
	return CFrame.lookAt(pos, pos + dir)
end

-- Spot light pointing down from a part.
local function downlight(part: BasePart, range: number, angle: number?, brightness: number?)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = N.WarmLight
	light.Range = range
	light.Angle = angle or 110
	light.Brightness = brightness or 1.5
	light.Parent = part
	return light
end

---------------------------------------------------------------------
-- Plaza, walls, bounds
---------------------------------------------------------------------

local function buildPlaza()
	local half = L.Size / 2
	local center = base + L.Center
	NanoKit.Floor(root, center, L.Size, L.Size, L.TileSize, N.Concrete, N.ConcreteLight)
	-- the technopolis deck around the plaza
	Panel(root, "Deck", Vector3.new(L.Size * 2.4, 1, L.Size * 2.4), CFrame.new(center + Vector3.new(0, -1.1, 0)), N.Graphite, M.Plate)

	local corners = {
		Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half), Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		NanoKit.Wall(root, center + corners[i], center + corners[i % 4 + 1], L.WallHeight, L.WallThickness, if i % 2 == 0 then N.Magenta else N.Cyan)
	end
	for i, c in ipairs(corners) do
		NanoKit.Pylon(root, center + c, L.TowerHeight, if i % 2 == 0 then N.Magenta else N.Cyan, L.TowerSize)
	end
	-- cables from the corner pylons to the holo tower
	local towerTop = at(L.Plaza.Offset) + Vector3.new(0, 22, 0)
	for _, c in ipairs(corners) do
		NanoKit.Cable(root, center + c + Vector3.new(0, L.TowerHeight - 2, 0), towerTop, 6)
	end

	-- Map bounds: invisible walls on the wall line up to HubWallExtra
	-- above the walls, plus a lid. Nothing leads onto the walls.
	local bounds = NanoKit.Model(root, "Bounds")
	local B = Config.Bounds
	local t = L.WallThickness
	local boundH = L.WallHeight + B.HubWallExtra + 2
	local span = L.Size + t + B.Overlap * 2
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Invisible(bounds, Vector3.new(span, boundH, t), center + Vector3.new(0, boundH / 2 - 1, side * half))
		WorldKit.Invisible(bounds, Vector3.new(t, boundH, span), center + Vector3.new(side * half, boundH / 2 - 1, 0))
	end
	WorldKit.Invisible(bounds, Vector3.new(span, 2, span), center + Vector3.new(0, boundH, 0), "Lid")
end

---------------------------------------------------------------------
-- Avenue, spawn, side paths
---------------------------------------------------------------------

local function path(name: string, a: Vector3, b: Vector3, width: number, accent: Color3?)
	local pa, pb = at(a), at(b)
	local length = (pb - pa).Magnitude
	if length < 0.5 then
		return
	end
	local cf = CFrame.lookAt((pa + pb) / 2 + Vector3.new(0, 0.06, 0), pb + Vector3.new(0, 0.06, 0))
	Panel(root, name, Vector3.new(width, 0.12, length), cf, N.Steel, M.Plate)
	if accent then
		for _, side in ipairs({ -1, 1 }) do
			NanoKit.Strip(root, (cf * CFrame.new(side * (width / 2 - 0.3), 0.08, -length / 2)).Position, (cf * CFrame.new(side * (width / 2 - 0.3), 0.08, length / 2)).Position, accent, 0.16)
		end
	end
end

local function buildAvenue()
	local zEnd = L.Portal.Offset.Z + 8
	path("Avenue", Vector3.new(0, 0, 4), Vector3.new(0, 0, zEnd), L.AvenueWidth, N.Cyan)
	-- guide dashes in the middle (they lead to the gates)
	for z = -6, zEnd + 6, -9 do
		Panel(root, "Guide", Vector3.new(1.4, 0.06, 3), CFrame.new(at(Vector3.new(0, 0.16, z))), N.Cyan, M.Neon, { CanCollide = false })
	end
	-- lamps along the avenue
	local w = L.AvenueWidth / 2 + 3
	for z = -10, zEnd + 10, -L.LampSpacing do
		for _, side in ipairs({ -1, 1 }) do
			NanoKit.Lamp(root, at(Vector3.new(side * w, 0, z)), 9, Vector3.new(-side, 0, 0))
		end
	end
	-- side paths to every zone
	local s = L.SidePathWidth
	local half = L.AvenueWidth / 2
	path("PathForge", Vector3.new(half, 0, L.Forge.Offset.Z), Vector3.new(L.Forge.Offset.X - L.Forge.Size.X / 2, 0, L.Forge.Offset.Z), s, N.Magenta)
	path("PathStore", Vector3.new(L.Plaza.Radius, 0, L.Store.Offset.Z), Vector3.new(L.Store.Offset.X - 4, 0, L.Store.Offset.Z), s, N.Gold)
	path("PathPets", Vector3.new(-half, 0, L.Egg.Offset.Z), Vector3.new(L.Egg.Offset.X + L.Egg.Radius, 0, L.Egg.Offset.Z), s, N.Magenta)
	path("PathWheel", Vector3.new(-L.Plaza.Radius, 0, L.Wheel.Offset.Z), Vector3.new(L.Wheel.Offset.X + 4, 0, L.Wheel.Offset.Z), s, N.Gold)
	path("PathPolygon", Vector3.new(-half, 0, L.Polygon.Offset.Z), Vector3.new(L.Polygon.Offset.X + L.Polygon.Size.X / 2, 0, L.Polygon.Offset.Z), s, N.Cyan)
	path("PathLeaders", Vector3.new(-half, 0, 5), Vector3.new(L.Leaderboards[1].Offset.X + 2, 0, 5), s, nil)

	-- spawn pad + entrance arch with the title
	local pad = at(Vector3.zero)
	local flat = CFrame.Angles(0, 0, math.rad(90))
	NanoKit.Cylinder(root, "SpawnPad", 0.3, 14, CFrame.new(pad + Vector3.new(0, 0.15, 0)) * flat, N.Steel, M.Plate)
	local ring = NanoKit.Cylinder(root, "SpawnRing", 0.06, 13, CFrame.new(pad + Vector3.new(0, 0.33, 0)) * flat, N.Cyan, M.Neon)
	ring.CanCollide = false
	NanoKit.Cylinder(root, "SpawnInner", 0.08, 12.4, CFrame.new(pad + Vector3.new(0, 0.36, 0)) * flat, N.Steel, M.Plate).CanCollide = false
	NanoKit.Tag(ring, "Pulse", { Period = 3 })
	local _, beam = NanoKit.Arch(root, frame(Vector3.new(0, 0, -16), SOUTH), L.AvenueWidth + 6, 14, N.Cyan)
	WorldKit.SurfaceText(beam, Enum.NormalId.Back, { { Text = Texts.Title, Size = 64, Color = N.Gold } }, 50)
	WorldKit.SurfaceText(beam, Enum.NormalId.Front, { { Text = Texts.Title, Size = 64, Color = N.Gold } }, 50)
	NanoKit.PostSign(root, frame(Vector3.new(11, 0, -10), SOUTH), Texts.Guide, N.Cyan)
end

---------------------------------------------------------------------
-- Holo tower (center)
---------------------------------------------------------------------

local function buildTower()
	local P = L.Plaza
	local pos = at(P.Offset)
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local m = NanoKit.Model(root, "HoloTower")
	NanoKit.Cylinder(m, "Plaza", 0.3, P.Radius * 2, CFrame.new(pos + Vector3.new(0, 0.15, 0)) * flat, N.ConcreteDark, M.Concrete)
	NanoKit.Cylinder(m, "PlazaRing", 0.08, P.Radius * 2 - 1, CFrame.new(pos + Vector3.new(0, 0.32, 0)) * flat, N.Cyan, M.Neon).CanCollide = false
	NanoKit.Cylinder(m, "PlazaInner", 0.1, P.Radius * 2 - 1.6, CFrame.new(pos + Vector3.new(0, 0.35, 0)) * flat, N.ConcreteDark, M.Concrete).CanCollide = false
	NanoKit.Column(m, "Base", 2, 9, pos, N.Graphite, M.Metal)
	NanoKit.Column(m, "Shaft", 20, 3, pos + Vector3.new(0, 2, 0), N.Steel, M.Metal)
	local core = NanoKit.Column(m, "Core", 16, 1.2, pos + Vector3.new(0, 4, 0), N.Cyan, M.Neon)
	core.CanCollide = false
	NanoKit.Column(m, "CoreGlass", 18, 3.4, pos + Vector3.new(0, 3, 0), N.Glass, M.Glass).Transparency = 0.55
	NanoKit.Column(m, "Crown", 1.5, 5, pos + Vector3.new(0, 22, 0), N.SteelLight, M.Metal)
	for i, h in ipairs({ 8, 13, 18 }) do
		local ring = NanoKit.Cylinder(m, "Ring", 0.4, 8 - i, CFrame.new(pos + Vector3.new(0, h, 0)) * flat * CFrame.Angles(math.rad(i * 15), 0, 0), if i == 2 then N.Magenta else N.Cyan, M.Neon)
		ring.CanCollide = false
		ring.Transparency = 0.2
		NanoKit.Tag(ring, "Spin", { Speed = if i % 2 == 0 then -35 else 45, Axis = "Y" })
	end
	WorldKit.Light(core, N.Cyan, 26, 1.2)
	-- four hologram boards around the top
	for i = 0, 3 do
		local angle = i * math.pi / 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local center = pos + Vector3.new(0, 15.5, 0) + dir * 3.4
		NanoKit.HoloSign(m, CFrame.lookAt(center, center + dir), Vector2.new(8, 2.4), { { Text = Texts.Title, Size = 40, Color = N.Cyan } }, N.Cyan)
	end
	-- benches and plant capsules
	for _, bench in ipairs(L.Benches) do
		NanoKit.Bench(root, frame(bench.Offset, bench.Facing))
	end
	for _, offset in ipairs(L.PlantCapsules) do
		NanoKit.PlantCapsule(root, at(offset))
	end
	local hologram = NanoKit.Prop(m, "Prop_Hologram", frame(P.Offset + Vector3.new(0, 0, P.Radius - 3), SOUTH), 5)
	if hologram then
		for _, p in ipairs(Assets.Parts(hologram)) do
			p.CanCollide = false
		end
	end
end

---------------------------------------------------------------------
-- Gates (portal)
---------------------------------------------------------------------

local function buildGates()
	local P = L.Portal
	local cf = frame(P.Offset, SOUTH) -- faces the spawn
	local m = NanoKit.Model(root, "Gates")
	-- stepped platform
	Panel(m, "Step1", Vector3.new(P.Width + 14, 0.6, 14), cf * CFrame.new(0, 0.3, 2), N.ConcreteDark, M.Concrete)
	Panel(m, "Step2", Vector3.new(P.Width + 8, 0.6, 9), cf * CFrame.new(0, 0.9, 3), N.Steel, M.Plate)
	-- massive frame
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (P.Width / 2 + 2.5)
		Panel(m, "Pillar", Vector3.new(5, P.Height + 4, 6), cf * CFrame.new(x, (P.Height + 4) / 2 + 1.2, 4), N.Graphite, M.Metal)
		Panel(m, "PillarFace", Vector3.new(3.4, P.Height, 0.4), cf * CFrame.new(x, P.Height / 2 + 2.6, 0.9), N.Steel, M.Plate)
		NanoKit.Strip(m, (cf * CFrame.new(x, 2.4, 0.6)).Position, (cf * CFrame.new(x, P.Height + 3, 0.6)).Position, N.Magenta, 0.2)
		Panel(m, "Buttress", Vector3.new(3, 8, 8), cf * CFrame.new(side * (P.Width / 2 + 6), 5.2, 6) * CFrame.Angles(0, 0, math.rad(side * -8)), N.ConcreteDark, M.Concrete)
		local lamp = Panel(m, "Lamp", Vector3.new(1, 1, 1), cf * CFrame.new(x, P.Height + 6, 0.4), N.WarmLight, M.Neon, { CanCollide = false })
		WorldKit.Light(lamp, N.WarmLight, 24, 1.5)
	end
	Panel(m, "Lintel", Vector3.new(P.Width + 12, 4, 6), cf * CFrame.new(0, P.Height + 5.2, 4), N.Graphite, M.Metal)
	Panel(m, "LintelTrim", Vector3.new(P.Width + 13, 0.5, 6.6), cf * CFrame.new(0, P.Height + 7.4, 4), N.SteelLight, M.Plate)
	local sign = Panel(m, "Sign", Vector3.new(P.Width + 4, 3.4, 0.3), cf * CFrame.new(0, P.Height + 5.2, 0.85), T.PanelDark, M.Smooth)
	WorldKit.SurfaceText(sign, Enum.NormalId.Front, { { Text = Texts.Portal, Size = 70, Color = N.Gold }, { Text = Texts.PortalSub, Size = 30, Color = N.Cyan } }, 50)
	NanoKit.Tag(sign, "Flicker")
	-- dark tunnel behind the field
	Panel(m, "Tunnel", Vector3.new(P.Width + 2, P.Height + 2, 1), cf * CFrame.new(0, P.Height / 2 + 2, 7.6), Color3.fromRGB(12, 12, 18), M.Smooth)
	-- the energy field: touching it starts a run (TravelService)
	local field = Panel(m, "PortalField", Vector3.new(P.Width, P.Height, 0.6), cf * CFrame.new(0, P.Height / 2 + 1.2, 3), N.Magenta, Enum.Material.ForceField, { CanCollide = false, Transparency = 0.15, CastShadow = false })
	field:SetAttribute("Portal", true)
	local glow = Panel(m, "FieldGlow", Vector3.new(P.Width - 2, P.Height - 2, 0.2), cf * CFrame.new(0, P.Height / 2 + 1.2, 3.5), N.Cyan, M.Neon, { CanCollide = false, CanTouch = false, Transparency = 0.75, CastShadow = false })
	NanoKit.Tag(glow, "Pulse", { Period = 2 })
	WorldKit.Light(field, N.Magenta, 30, 1.6)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(N.Magenta, N.Cyan)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Rate = 20
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Parent = field
	-- cargo and props around the gates
	NanoKit.CargoStack(m, frame(P.Offset + Vector3.new(P.Width / 2 + 12, 0, 6), SOUTH))
	NanoKit.Prop(m, "Prop_Door", frame(P.Offset + Vector3.new(-(P.Width / 2 + 13), 0, 6), SOUTH), 10)
	return field
end

---------------------------------------------------------------------
-- Fabricator (forge hall)
---------------------------------------------------------------------

-- Hall with an open front, glass upper walls and a roof; inside: the
-- reactor core ("Hearth": Glow light, Fire, Sparks), the press table
-- ("Anvil": Sparks) under a manipulator hammer and the console with the
-- prompt. CraftService flares the Hearth and the Anvil on a craft.
local function buildForge()
	local F = L.Forge
	local cf = frame(F.Offset, WEST) -- the open front faces the avenue
	local w, d, h = F.Size.X, F.Size.Y, F.Height
	local m = NanoKit.Model(root, "Forge")
	Panel(m, "Floor", Vector3.new(w, 0.6, d), cf * CFrame.new(0, 0.3, 0), N.Steel, M.Plate)
	NanoKit.Strip(m, (cf * CFrame.new(-w / 2, 0.62, -d / 2 + 0.3)).Position, (cf * CFrame.new(w / 2, 0.62, -d / 2 + 0.3)).Position, N.Magenta, 0.16)
	-- back + side walls: concrete lower part, glass upper part
	local walls = {
		{ CFrame.new(0, 0, d / 2), w }, -- back
		{ CFrame.new(-w / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0), d },
		{ CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0), d },
	}
	for _, wall in ipairs(walls) do
		local wcf = cf * wall[1]
		Panel(m, "WallLow", Vector3.new(wall[2], h * 0.45, 1), wcf * CFrame.new(0, h * 0.225, 0), N.ConcreteLight, M.Concrete)
		Panel(m, "WallGlass", Vector3.new(wall[2] - 2, h * 0.5, 0.4), wcf * CFrame.new(0, h * 0.7, 0), N.Glass, M.Glass, { Transparency = 0.55 })
		Panel(m, "WallBeam", Vector3.new(wall[2], 0.8, 1.2), wcf * CFrame.new(0, h - 0.4, 0), N.Graphite, M.Metal)
	end
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			NanoKit.Column(m, "Column", h, 1.6, (cf * CFrame.new(dx * (w / 2 - 0.4), 0, dz * (d / 2 - 0.4))).Position, N.Graphite, M.Metal)
		end
	end
	Panel(m, "Roof", Vector3.new(w + 2, 1, d + 2), cf * CFrame.new(0, h + 0.5, 0), N.Graphite, M.Metal)
	Panel(m, "Skylight", Vector3.new(w * 0.5, 0.3, d * 0.4), cf * CFrame.new(0, h + 1.05, 0), N.Glass, M.Glass, { Transparency = 0.4 })
	-- front sign on the roof edge
	local sign = Panel(m, "Sign", Vector3.new(w * 0.7, 3, 0.3), cf * CFrame.new(0, h + 2.6, -d / 2 - 0.4), T.PanelDark, M.Smooth)
	WorldKit.SurfaceText(sign, Enum.NormalId.Front, { { Text = Texts.Forge, Size = 60, Color = N.Gold }, { Text = Texts.ForgeSub, Size = 26, Color = N.Cyan } }, 50)
	NanoKit.Tag(sign, "Flicker")
	-- ceiling lights
	for _, dx in ipairs({ -0.25, 0.25 }) do
		local lamp = Panel(m, "CeilingLamp", Vector3.new(w * 0.3, 0.2, 1), cf * CFrame.new(dx * w, h - 0.15, 0), N.WarmLight, M.Neon, { CanCollide = false })
		downlight(lamp, h + 6, 120, 1.6)
	end

	-- Reactor core at the back (owner Trainer_Machine if present, else a
	-- procedural reactor with spinning rings).
	local coreCf = cf * CFrame.new(0, 0.6, d / 2 - 5)
	local machine = NanoKit.Prop(m, "Trainer_Machine", coreCf, h * 0.75)
	local hearthCf = if machine then coreCf * CFrame.new(0, h * 0.4, -3.6) else coreCf * CFrame.new(0, 4.5, 0)
	local hearth = Panel(m, "Hearth", Vector3.new(2.6, 2.6, 2.6), hearthCf, N.Cyan, M.Neon, { CanCollide = false, Shape = Enum.PartType.Ball, Transparency = 0.1 })
	if not machine then
		NanoKit.Column(m, "ReactorBase", 2, 7, coreCf.Position, N.Graphite, M.Metal)
		NanoKit.Column(m, "ReactorGlass", 6, 4.6, coreCf.Position + Vector3.new(0, 2, 0), N.Glass, M.Glass).Transparency = 0.6
		NanoKit.Column(m, "ReactorCap", 1.2, 6, coreCf.Position + Vector3.new(0, 8, 0), N.SteelLight, M.Metal)
		for i = 1, 2 do
			local ring = NanoKit.Cylinder(m, "ReactorRing", 0.3, 6 + i, CFrame.new(coreCf.Position + Vector3.new(0, 3 + i * 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), if i == 1 then N.Cyan else N.Magenta, M.Neon)
			ring.CanCollide = false
			NanoKit.Tag(ring, "Spin", { Speed = if i == 1 then 60 else -40, Axis = "Y" })
		end
	end
	local glow = WorldKit.Light(hearth, N.Cyan, 20, 1.6)
	glow.Name = "Glow"
	local fire = Instance.new("Fire")
	fire.Name = "Fire"
	fire.Color = N.Cyan
	fire.SecondaryColor = N.Magenta
	fire.Size = 7
	fire.Heat = 6
	fire.Parent = hearth
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(N.Cyan, Color3.new(1, 1, 1))
	sparks.LightEmission = 0.8
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Rate = 0
	sparks.Parent = hearth
	NanoKit.Tag(hearth, "Pulse", { Period = 1.6 })

	-- Press table ("Anvil") under a manipulator hammer
	local anvilCf = cf * CFrame.new(-5, 0.6, 1)
	Panel(m, "AnvilBase", Vector3.new(4, 2.4, 3), anvilCf * CFrame.new(0, 1.2, 0), N.Graphite, M.Metal)
	local anvil = Panel(m, "Anvil", Vector3.new(4.6, 0.6, 3.4), anvilCf * CFrame.new(0, 2.7, 0), N.SteelLight, M.Plate)
	NanoKit.Strip(m, (anvilCf * CFrame.new(-2.3, 3.02, -1.7)).Position, (anvilCf * CFrame.new(2.3, 3.02, -1.7)).Position, N.Magenta, 0.1)
	local anvilSparks = sparks:Clone()
	anvilSparks.Color = ColorSequence.new(N.Gold, Color3.new(1, 1, 1))
	anvilSparks.SpreadAngle = Vector2.new(80, 80)
	anvilSparks.Parent = anvil
	NanoKit.Column(m, "ArmPost", h - 1, 1, (anvilCf * CFrame.new(3.4, 0, 1.6)).Position, N.Steel, M.Metal)
	Panel(m, "Manipulator", Vector3.new(5, 0.8, 0.8), anvilCf * CFrame.new(1, h - 3, 1.6), N.Gold, M.Metal)
	local hammer = Panel(m, "Hammer", Vector3.new(1.4, 2.2, 1.4), anvilCf * CFrame.new(-1, h - 4.6, 1.6), N.Graphite, M.Metal)
	NanoKit.Tag(hammer, "Bob", { Amplitude = 0.6, Period = 2.2 })

	-- Console with the prompt (front, near the opening)
	local consoleCf = cf * CFrame.new(5, 0.6, -6)
	local console = Panel(m, "ConsoleBase", Vector3.new(3, 3, 1.6), consoleCf * CFrame.new(0, 1.5, 0), N.Graphite, M.Metal)
	Panel(m, "Screen", Vector3.new(2.8, 1.6, 0.2), consoleCf * CFrame.new(0, 3.6, 0.2) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(20, 30, 40), M.Glass)
	local screenGlow = Panel(m, "ScreenGlow", Vector3.new(2.4, 1.2, 0.05), consoleCf * CFrame.new(0, 3.6, 0.08) * CFrame.Angles(math.rad(-25), 0, 0), N.Cyan, M.Neon, { CanCollide = false, Transparency = 0.5 })
	NanoKit.Tag(screenGlow, "Flicker")
	local prompt = WorldKit.Prompt(console, L.Prompts.Forge, "", { Action = "OpenForge" }, 14)

	-- decor: refiner, cargo, pipes, vent
	NanoKit.Prop(m, "Trainer_Refiner", cf * CFrame.new(w / 2 - 4, 0.6, d / 2 - 4), 7, function(p, c)
		return NanoKit.CargoStack(p, c)
	end)
	NanoKit.CargoStack(m, cf * CFrame.new(-w / 2 + 4, 0.6, d / 2 - 4))
	NanoKit.Prop(m, "Prop_Pipes", cf * CFrame.new(0, 0.6, d / 2 + 1.5))
	NanoKit.Vent(m, cf * CFrame.new(w / 2 + 0.6, h * 0.3, 4) * CFrame.Angles(0, math.rad(-90), 0), 2.6)
	return prompt, m
end

---------------------------------------------------------------------
-- Incubator (pet eggs)
---------------------------------------------------------------------

local function egg(parent, cf: CFrame, scale: number, color: Color3)
	local shell = Panel(parent, "EggShell", Vector3.new(2.6, 3.4, 2.6) * scale, cf, Color3.fromRGB(240, 238, 248), M.Smooth, { Shape = Enum.PartType.Ball, CanCollide = false })
	for i = 1, 4 do
		local angle = i * math.pi / 2
		Panel(parent, "EggLine", Vector3.new(0.12, 2.6, 0.12) * scale, cf * CFrame.new(math.cos(angle) * 1.3 * scale, 0, math.sin(angle) * 1.3 * scale), color, M.Neon, { CanCollide = false })
	end
	return shell
end

local function buildIncubator()
	local E = L.Egg
	local cf = frame(E.Offset, EAST)
	local pos = cf.Position
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local m = NanoKit.Model(root, "Egg")
	NanoKit.Cylinder(m, "Platform", 1, E.Radius * 2, CFrame.new(pos + Vector3.new(0, 0.5, 0)) * flat, N.Graphite, M.Metal)
	NanoKit.Cylinder(m, "PlatformRing", 0.1, E.Radius * 2 - 0.6, CFrame.new(pos + Vector3.new(0, 1.02, 0)) * flat, N.Magenta, M.Neon).CanCollide = false
	NanoKit.Cylinder(m, "PlatformTop", 0.12, E.Radius * 2 - 1.2, CFrame.new(pos + Vector3.new(0, 1.05, 0)) * flat, N.Steel, M.Plate).CanCollide = false
	-- glass dome on ribs
	local apex = pos + Vector3.new(0, 9, 0)
	for i = 0, 5 do
		local angle = i * math.pi / 3
		local foot = pos + Vector3.new(math.cos(angle) * (E.Radius - 0.6), 1, math.sin(angle) * (E.Radius - 0.6))
		local length = (apex - foot).Magnitude
		Panel(m, "Rib", Vector3.new(0.5, 0.5, length), CFrame.lookAt((foot + apex) / 2, apex), N.SteelLight, M.Metal, { CanCollide = false })
	end
	Panel(m, "Dome", Vector3.new(E.Radius * 1.7, E.Radius * 1.4, E.Radius * 1.7), CFrame.new(pos + Vector3.new(0, 4, 0)), N.Glass, M.Glass, { Shape = Enum.PartType.Ball, Transparency = 0.82, CanCollide = false, CastShadow = false })
	-- pedestal with the big egg + halo rings
	local pedestal = Panel(m, "Pedestal", Vector3.new(4, 2.2, 4), CFrame.new(pos + Vector3.new(0, 2.1, 0)), N.Steel, M.Plate)
	local big = egg(m, CFrame.new(pos + Vector3.new(0, 5.2, 0)), 1, N.Magenta)
	NanoKit.Tag(big, "Bob", { Amplitude = 0.35, Period = 2.6 })
	for i = 1, 2 do
		local ring = NanoKit.Cylinder(m, "Halo", 0.2, 4.6 + i, CFrame.new(pos + Vector3.new(0, 4.4 + i * 0.9, 0)) * flat * CFrame.Angles(math.rad(i * 20), 0, 0), if i == 1 then N.Magenta else N.Cyan, M.Neon)
		ring.CanCollide = false
		ring.Transparency = 0.3
		NanoKit.Tag(ring, "Spin", { Speed = if i == 1 then 50 else -70, Axis = "Y" })
	end
	WorldKit.Light(big, N.Magenta, 18, 1.2)
	-- incubation pods around
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local p = pos + Vector3.new(math.cos(angle) * (E.Radius - 3.2), 1, math.sin(angle) * (E.Radius - 3.2))
		NanoKit.Column(m, "PodBase", 0.8, 2.6, p, N.Graphite, M.Metal)
		NanoKit.Column(m, "Pod", 3, 2.2, p + Vector3.new(0, 0.8, 0), N.Glass, M.Glass).Transparency = 0.6
		egg(m, CFrame.new(p + Vector3.new(0, 2.2, 0)), 0.45, if i % 2 == 0 then N.Cyan else N.Gold)
		NanoKit.Column(m, "PodLid", 0.3, 2.4, p + Vector3.new(0, 3.8, 0), N.SteelLight, M.Metal)
	end
	NanoKit.PostSign(m, frame(E.Offset + Vector3.new(E.Radius + 2, 0, E.Radius - 2), EAST), Texts.Pets, N.Magenta, Texts.PetsSub)
	return WorldKit.Prompt(pedestal, L.Prompts.Egg, "", { Action = "OpenPets" }, 14)
end

---------------------------------------------------------------------
-- Wheel of fortune (the client spins the "Spin" model)
---------------------------------------------------------------------

local function buildWheel()
	local cf = frame(L.Wheel.Offset, EAST)
	local m = NanoKit.Model(root, "Wheel")
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Strut", Vector3.new(1, 13, 1.4), cf * CFrame.new(side * 6.4, 6.5, 1.6), N.Graphite, M.Metal)
		NanoKit.Strip(m, (cf * CFrame.new(side * 6.4, 1, 0.85)).Position, (cf * CFrame.new(side * 6.4, 12, 0.85)).Position, N.Gold, 0.12)
	end
	Panel(m, "Board", Vector3.new(12, 12, 1), cf * CFrame.new(0, 6.6, 2.2), N.Steel, M.Plate)
	local spin = Instance.new("Model")
	spin.Name = "Spin"
	spin.Parent = m
	local disc = WorldKit.Part(spin, {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 9, 9),
		CFrame = cf * CFrame.new(0, 6.6, 1) * CFrame.Angles(0, math.rad(90), 0),
		Color = N.Graphite,
		Material = M.Metal,
	})
	spin.PrimaryPart = disc
	local colors = { N.Magenta, N.Gold, N.Cyan, T.Green, T.Purple, T.Orange, T.Red, T.Blue }
	for i = 0, 7 do
		local angle = i * math.pi / 4
		WorldKit.Part(spin, {
			Name = "Segment",
			Size = Vector3.new(1.4, 3.2, 0.3),
			CFrame = cf * CFrame.new(math.cos(angle) * 2.8, 6.6 + math.sin(angle) * 2.8, 0.45) * CFrame.Angles(0, 0, angle + math.rad(90)),
			Color = colors[i + 1],
			Material = M.Neon,
			CanCollide = false,
		})
	end
	WorldKit.Part(m, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.8, 1.8), CFrame = cf * CFrame.new(0, 6.6, 0.4) * CFrame.Angles(0, math.rad(90), 0), Color = N.SteelLight, Material = M.Metal })
	WorldKit.Part(m, { Name = "Pointer", Size = Vector3.new(0.8, 1.6, 0.6), CFrame = cf * CFrame.new(0, 11.6, 0.4), Color = N.Gold, Material = M.Neon })
	NanoKit.HoloSign(m, cf * CFrame.new(0, 14.6, 1.6), Vector2.new(12, 2.8), { { Text = Texts.Wheel, Size = 44, Color = N.Gold }, { Name = "Status", Text = Texts.WheelFree, Size = 26, Color = T.Green } }, N.Gold)
	m:SetAttribute("Wheel", true)
	return WorldKit.Prompt(disc, L.Prompts.Wheel, "", { Action = "Wheel" }, 14)
end

---------------------------------------------------------------------
-- Store kiosk
---------------------------------------------------------------------

local function buildStore()
	local cf = frame(L.Store.Offset, WEST)
	local m = NanoKit.Model(root, "Store")
	NanoKit.Canopy(m, cf, Vector2.new(9, 7), 8, N.Gold)
	local counter = Panel(m, "Counter", Vector3.new(6, 3, 2.4), cf * CFrame.new(0, 1.5, 0), N.Graphite, M.Metal)
	Panel(m, "CounterTop", Vector3.new(6.4, 0.3, 2.8), cf * CFrame.new(0, 3.15, 0), N.Gold, M.Metal)
	NanoKit.Strip(m, (cf * CFrame.new(-3, 2.6, -1.25)).Position, (cf * CFrame.new(3, 2.6, -1.25)).Position, N.Gold, 0.12)
	-- hologram (owner Prop_Hologram if present, else a spinning gem)
	NanoKit.Prop(m, "Prop_Hologram", cf * CFrame.new(0, 3.3, 0), 3, function(p, c)
		local gem = Panel(p, "Gem", Vector3.new(1.6, 1.6, 1.6), c * CFrame.new(0, 1.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), N.Cyan, M.Glass, { CanCollide = false, Transparency = 0.15 })
		NanoKit.Tag(gem, "Spin", { Speed = 60, Axis = "Y" })
		WorldKit.Light(gem, N.Cyan, 12, 1)
		return gem
	end)
	NanoKit.PostSign(m, frame(L.Store.Offset + Vector3.new(-6, 0, 6), WEST), Texts.Store, N.Gold, "Robux")
	return WorldKit.Prompt(counter, L.Prompts.Store, "", { Action = "OpenStore" }, 12)
end

---------------------------------------------------------------------
-- Polygon arena (the dummies are placed by PolygonService)
---------------------------------------------------------------------

local function buildPolygon()
	local PG = L.Polygon
	local m = NanoKit.Model(root, "Polygon")
	local pos = at(PG.Offset)
	Panel(m, "Floor", Vector3.new(PG.Size.X, 0.4, PG.Size.Z), CFrame.new(pos + Vector3.new(0, 0.2, 0)), N.Graphite, M.Plate)
	for i = -2, 2 do
		NanoKit.Strip(m, pos + Vector3.new(-PG.Size.X / 2 + 1, 0.42, i * PG.Size.Z / 5), pos + Vector3.new(PG.Size.X / 2 - 1, 0.42, i * PG.Size.Z / 5), N.Cyan, 0.08)
	end
	-- railings on three sides (open towards the avenue, +X)
	local hx, hz = PG.Size.X / 2, PG.Size.Z / 2
	NanoKit.Railing(m, pos + Vector3.new(-hx, 0.4, -hz), pos + Vector3.new(hx, 0.4, -hz), 3.2, N.Cyan)
	NanoKit.Railing(m, pos + Vector3.new(-hx, 0.4, hz), pos + Vector3.new(hx, 0.4, hz), 3.2, N.Cyan)
	NanoKit.Railing(m, pos + Vector3.new(-hx, 0.4, -hz), pos + Vector3.new(-hx, 0.4, hz), 3.2, N.Cyan)
	-- floodlight masts
	for _, dz in ipairs({ -1, 1 }) do
		local mast = pos + Vector3.new(-hx + 2, 0.4, dz * (hz - 2))
		NanoKit.Column(m, "Mast", 14, 0.7, mast, N.Graphite, M.Metal)
		local head = Panel(m, "Floodlight", Vector3.new(2.4, 1, 1.2), CFrame.lookAt(mast + Vector3.new(0, 14, 0), pos), N.SteelLight, M.Metal)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Color = N.WarmLight
		light.Range = 50
		light.Angle = 70
		light.Brightness = 2
		light.Parent = head
	end
	-- board on the back railing + a sign by the avenue
	local boardCenter = pos + Vector3.new(-hx + 0.6, 9, 0)
	NanoKit.HoloSign(m, CFrame.lookAt(boardCenter, boardCenter + EAST), Vector2.new(14, 4), { { Text = Texts.Polygon, Size = 56, Color = N.Cyan }, { Text = Texts.PolygonSub, Size = 26 } }, N.Cyan)
	NanoKit.PostSign(root, frame(Vector3.new(-L.AvenueWidth / 2 - 3, 0, PG.Offset.Z + hz + 2), EAST), Texts.Polygon, N.Cyan, Texts.PolygonSub)
	-- owner decor: weights in the corner
	NanoKit.Prop(m, "Trainer_Weights", CFrame.lookAt(pos + Vector3.new(-hx + 5, 0.4, hz - 5), pos + Vector3.new(0, 0.4, 0)), 4)
	return m
end

---------------------------------------------------------------------
-- Leaderboards
---------------------------------------------------------------------

local function buildLeaderboards()
	local boards = {}
	for _, def in ipairs(L.Leaderboards) do
		local cf = frame(def.Offset, EAST)
		local m = NanoKit.Model(root, "Leaderboard_" .. def.Kind)
		for _, side in ipairs({ -1, 1 }) do
			Panel(m, "Post", Vector3.new(1, 17, 1.2), cf * CFrame.new(side * 8.6, 8.5, 0.4), N.Graphite, M.Metal)
			NanoKit.Strip(m, (cf * CFrame.new(side * 8.6, 1, -0.25)).Position, (cf * CFrame.new(side * 8.6, 16, -0.25)).Position, N.Gold, 0.12)
		end
		Panel(m, "Frame", Vector3.new(17, 14.6, 0.5), cf * CFrame.new(0, 8.8, 0.35), N.Steel, M.Metal)
		local board = Panel(m, "Board", Vector3.new(16, 13.6, 0.4), cf * CFrame.new(0, 8.8, 0), T.PanelDark, M.Smooth)
		local lines = { { Name = "Title", Text = def.Title, Size = 34, Color = N.Gold } }
		for i = 1, Config.Leaderboards.Top do
			table.insert(lines, { Name = "Row" .. i, Text = i .. ". —", Size = 18 })
		end
		boards[def.Kind] = WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 50)
	end
	return boards
end

---------------------------------------------------------------------
-- Bridge, floating platforms, drones, cargo, vents, owner props
---------------------------------------------------------------------

-- Owner props of unknown purpose go into PropSlots by their height.
local function sizeClass(height: number): string
	if height < 4 then
		return "Small"
	elseif height <= 10 then
		return "Medium"
	end
	return "Large"
end

local function buildDecor()
	-- bridge across the avenue on two towers
	local BR = L.Bridge
	for _, p in ipairs({ BR.From, BR.To }) do
		NanoKit.Pylon(root, at(p), BR.Height + 4, N.Magenta, 5)
	end
	NanoKit.Bridge(root, at(BR.From), at(BR.To), BR.Height, BR.Width, N.Magenta)
	NanoKit.Cable(root, at(BR.From) + Vector3.new(0, BR.Height + 4, 0), at(L.Portal.Offset) + Vector3.new(-L.Portal.Width / 2, L.Portal.Height + 8, 0), 4)
	NanoKit.Cable(root, at(BR.To) + Vector3.new(0, BR.Height + 4, 0), at(L.Portal.Offset) + Vector3.new(L.Portal.Width / 2, L.Portal.Height + 8, 0), 4)

	for _, fp in ipairs(L.FloatingPlatforms) do
		local platform = NanoKit.FloatingPlatform(root, CFrame.new(at(fp.Offset)), fp.Size, N.Cyan)
		NanoKit.CargoStack(platform, CFrame.new(at(fp.Offset) + Vector3.new(0, fp.Size.Y / 2, 0)))
	end
	for _, route in ipairs(L.DroneRoutes) do
		local points = {}
		for _, offset in ipairs(route) do
			table.insert(points, at(offset))
		end
		NanoKit.Drone(root, points, 9)
	end
	for i, offset in ipairs(L.Cargo) do
		NanoKit.CargoStack(root, CFrame.new(at(offset)) * CFrame.Angles(0, math.rad(i * 37), 0))
	end
	for _, vent in ipairs(L.Vents) do
		local p = at(vent.Offset) + Vector3.new(0, 5, 0)
		NanoKit.Vent(root, CFrame.lookAt(p, p + vent.Facing), 3.4)
	end

	-- owner props of unknown purpose, by size
	local candidates = { Small = {}, Medium = {}, Large = {} }
	for _, name in ipairs({ "Prop_Misc_1", "Prop_Misc_2", "Prop_Misc_3", "Prop_Misc_4", "Prop_Pipes" }) do
		local size = Assets.Size("Props", name)
		if size then
			table.insert(candidates[sizeClass(size.Y)], name)
		end
	end
	local used = { Small = 0, Medium = 0, Large = 0 }
	for _, slot in ipairs(L.PropSlots) do
		local list = candidates[slot.Size]
		if #list > 0 then
			used[slot.Size] += 1
			NanoKit.Prop(root, list[(used[slot.Size] - 1) % #list + 1], frame(slot.Offset, slot.Facing))
		elseif slot.Size ~= "Small" then
			NanoKit.CargoStack(root, frame(slot.Offset, slot.Facing))
		end
	end
end

---------------------------------------------------------------------

function HubGenerator.Build()
	root = Instance.new("Folder")
	root.Name = "Hub"

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	base = Vector3.new(origin.X, groundY, origin.Z)
	if spawn then
		-- our spawn pad replaces the look of the default grey SpawnLocation
		spawn.Transparency = 1
		for _, d in ipairs(spawn:GetChildren()) do
			if d:IsA("Decal") then
				d.Transparency = 1
			end
		end
	end

	buildPlaza()
	buildAvenue()
	buildTower()
	local portal = buildGates()
	local forgePrompt, forge = buildForge()
	local eggPrompt = buildIncubator()
	local wheelPrompt = buildWheel()
	local storePrompt = buildStore()
	local polygon = buildPolygon()
	local boards = buildLeaderboards()
	buildDecor()

	root:SetAttribute("Center", base + L.Center)
	root.Parent = Workspace
	return {
		Folder = root,
		Polygon = polygon,
		PolygonCenter = at(L.Polygon.Offset),
		Portal = portal,
		Forge = forge,
		ForgePrompt = forgePrompt,
		StorePrompt = storePrompt,
		WheelPrompt = wheelPrompt,
		EggPrompt = eggPrompt,
		Leaderboards = boards,
		SpawnCFrame = CFrame.lookAt(base + Vector3.new(0, 4, 0), base + Vector3.new(0, 4, -10)),
		GroundY = base.Y,
	}
end

return HubGenerator
