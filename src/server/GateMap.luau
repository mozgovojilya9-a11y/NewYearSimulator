--[[
	GateMap.luau
	Builds the map of a gate location for one run (Config.Gates.Locations,
	Config.GateMap, the biome look of Config.DungeonLayout.Biomes):

	  [start] Zone 1 -> corridor -> Zone 2 -> ... -> corridor -> Boss arena

	A zone is a square hall without a roof: floor with the biome's AI
	material (FloorVariant), walls with pilasters and a thin accent line,
	cover blocks in a ring (the middle stays free to fight), the biome's
	AI landmark model (or the procedural machine) in a corner, the biome
	decor along a wall, lamp pylons and spawn portals (hatches) by the
	walls. Zones snake left / right (seeded per location, so a location
	always looks the same). The exit of a zone is an energy barrier that
	the run opens when the zone is cleared; the boss arena is an octagon
	with a platform, big pylons and the landmark.

	GateMap.Build(location, slot) -> map (see the end of Build), built in
	small chunks with task.wait() so the server never stalls; the run
	destroys map.Folder when it ends. Everything is in Workspace.Dungeon
	.Lanes (the client modules watch that folder).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MaterialService = game:GetService("MaterialService")

local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

local GateMap = {}

local G = Config.GateMap
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local root, lanesFolder
local groundY = 0
local roof -- defined below (zones and the arena use it)

local biomeByTheme = {}
for _, biome in ipairs(Config.DungeonLayout.Biomes) do
	biomeByTheme[biome.Theme] = biome
end

function GateMap.Biome(theme: string)
	return biomeByTheme[theme] or Config.DungeonLayout.Biomes[1]
end

---------------------------------------------------------------------
-- Decor kit (machines and wall sets of every biome)
---------------------------------------------------------------------

local function conveyor(parent, biome, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt((from + to) / 2 + Vector3.new(0, 1.4, 0), to + Vector3.new(0, 1.4, 0))
	Panel(parent, "ConveyorFrame", Vector3.new(4, 1.2, length), cf * CFrame.new(0, -0.6, 0), biome.Metal, M.Metal)
	Panel(parent, "Belt", Vector3.new(3.4, 0.2, length), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(30, 30, 34), M.Smooth)
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Strip(parent, (cf * CFrame.new(side * 1.9, 0.05, -length / 2)).Position, (cf * CFrame.new(side * 1.9, 0.05, length / 2)).Position, biome.Accent, 0.1)
	end
	for i = 1, 3 do
		NanoKit.Crate(parent, cf * CFrame.new(0, 0.2, -length / 2 + length * i / 4) * CFrame.Angles(0, math.rad(i * 20), 0), Vector3.new(2.2, 2.2, 2.2))
	end
end

-- The biome's signature machine in a room corner.
local function machine(parent, biome, cf: CFrame)
	local theme = biome.Theme
	if theme == "Cryo" then
		for k = -1, 1, 2 do
			local p = (cf * CFrame.new(k * 2.2, 0, 0)).Position
			NanoKit.Column(parent, "TankBase", 1, 3.2, p, biome.Metal, M.Metal)
			local tank = NanoKit.Column(parent, "Tank", 7, 2.8, p + Vector3.new(0, 1, 0), biome.Glow, M.Glass)
			tank.Transparency = 0.45
			NanoKit.Column(parent, "TankCap", 0.8, 3.2, p + Vector3.new(0, 8, 0), biome.Metal, M.Metal)
			WorldKit.Light(tank, biome.Glow, 12, 0.8)
		end
	elseif theme == "Smelter" then
		NanoKit.Column(parent, "Crucible", 4, 6, cf.Position, biome.Metal, M.Metal)
		local melt = NanoKit.Column(parent, "Melt", 0.3, 5, cf.Position + Vector3.new(0, 4, 0), biome.Glow, M.Neon)
		melt.CanCollide = false
		NanoKit.Tag(melt, "Pulse", { Period = 1.8 })
		WorldKit.Light(melt, biome.Glow, 22, 1.6)
		local fire = Instance.new("Fire")
		fire.Color = biome.Glow
		fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
		fire.Size = 5
		fire.Heat = 4
		fire.Parent = melt
	elseif theme == "Infected" then
		-- a biomass growth swallowing a machine
		Panel(parent, "DeadMachine", Vector3.new(5, 4, 3.4), cf * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(8)), biome.Metal, M.Metal)
		for i = 1, 4 do
			local a = i * math.pi / 2
			local sac = Panel(parent, "Sac", Vector3.new(2.4, 2.4, 2.4), cf * CFrame.new(math.cos(a) * 2.6, 1.4 + (i % 2) * 2, math.sin(a) * 2.2), biome.Glow, M.Smooth, { Shape = Enum.PartType.Ball, Transparency = 0.25, CanCollide = false })
			NanoKit.Tag(sac, "Pulse", { Period = 1.6 + i * 0.3 })
		end
		WorldKit.Light(parent:FindFirstChild("DeadMachine") or parent, biome.Glow, 16, 1)
	elseif theme == "Nexus" then
		local core = Panel(parent, "DataCore", Vector3.new(3, 3, 3), cf * CFrame.new(0, 5, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), biome.Glow, M.Neon, { CanCollide = false, Transparency = 0.2 })
		NanoKit.Tag(core, "Spin", { Speed = 50, Axis = "Y" })
		NanoKit.Column(parent, "CorePylon", 2.5, 4, cf.Position, biome.Metal, M.Metal)
		WorldKit.Light(core, biome.Glow, 20, 1.4)
	else -- Assembly: robotic arm over a workbench
		Panel(parent, "Bench", Vector3.new(6, 2.6, 3), cf * CFrame.new(0, 1.3, 0), biome.Metal, M.Plate)
		NanoKit.Column(parent, "ArmBase", 3, 1.4, (cf * CFrame.new(2, 2.6, 0)).Position, biome.Accent, M.Metal)
		Panel(parent, "ArmUpper", Vector3.new(0.8, 4, 0.8), cf * CFrame.new(1.2, 6.5, 0) * CFrame.Angles(0, 0, math.rad(30)), biome.Accent, M.Metal)
		local tool = Panel(parent, "ArmTool", Vector3.new(0.6, 1.4, 0.6), cf * CFrame.new(-0.4, 7.8, 0), biome.Metal, M.Metal)
		NanoKit.Tag(tool, "Bob", { Amplitude = 0.5, Period = 1.4 })
	end
end

-- The biome's side-wall set (from -> to along a side wall, `side` = which
-- wall): every biome reads differently at a glance.
local function biomeDecor(parent, biome, from: Vector3, to: Vector3, side: number)
	local kind = biome.Decor or "Assembly"
	local length = (to - from).Magnitude
	local dir = (to - from).Unit
	local cf = CFrame.lookAt((from + to) / 2, to)
	if kind == "Cryo" then
		-- cryo tanks with frozen robots inside + frost on the floor
		local count = math.max(2, math.floor(length / 9))
		for i = 1, count do
			local p = from + dir * (length * (i - 0.5) / count)
			NanoKit.Column(parent, "TankBase", 1, 4, p, biome.Metal, M.Metal)
			local tank = NanoKit.Column(parent, "CryoTank", 7.5, 3.4, p + Vector3.new(0, 1, 0), biome.Glow, M.Smooth)
			tank.Transparency = 0.6
			tank.CanCollide = true
			Panel(parent, "Frozen", Vector3.new(1.2, 3.6, 0.8), CFrame.new(p + Vector3.new(0, 4.4, 0)), biome.Metal, M.Metal, { CanCollide = false })
			NanoKit.Column(parent, "TankCap", 1, 4, p + Vector3.new(0, 8.5, 0), biome.Metal, M.Metal)
			if i % 2 == 1 then
				WorldKit.Light(tank, biome.Glow, 14, 0.7)
			end
			-- frost patch
			local frost = NanoKit.Cylinder(parent, "Frost", 0.06, 6 + (i % 2) * 2, CFrame.new(p + Vector3.new(-side * 4, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(225, 240, 255), M.Smooth)
			frost.CanCollide = false
			frost.Transparency = 0.35
		end
	elseif kind == "Smelter" then
		-- molten channel along the wall under a steel grating
		Panel(parent, "ChannelBed", Vector3.new(3.2, 0.3, length), cf * CFrame.new(0, 0.05, 0), Color3.fromRGB(30, 22, 20), M.Metal, { CanCollide = false })
		local melt = Panel(parent, "Melt", Vector3.new(2.4, 0.12, length), cf * CFrame.new(0, 0.22, 0), biome.Glow, M.Neon, { CanCollide = false, CastShadow = false })
		NanoKit.Tag(melt, "Pulse", { Period = 2.4 })
		for z = -length / 2 + 1, length / 2 - 1, 1.6 do
			Panel(parent, "Grate", Vector3.new(3.4, 0.2, 0.3), cf * CFrame.new(0, 0.36, z), biome.Metal, M.Metal)
		end
		for _, k in ipairs({ -0.3, 0.3 }) do
			local light = Panel(parent, "MeltLight", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, 1, length * k), biome.Glow, M.Smooth, { CanCollide = false, Transparency = 1 })
			WorldKit.Light(light, biome.Glow, 18, 1.2)
		end
		-- crucibles on the channel ends
		for _, k in ipairs({ -1, 1 }) do
			local p = (cf * CFrame.new(-side * 4.5, 0, k * (length / 2 - 4))).Position
			NanoKit.Column(parent, "Crucible", 3.2, 4.4, p, biome.Metal, M.Metal)
			local top = NanoKit.Column(parent, "CrucibleMelt", 0.2, 3.6, p + Vector3.new(0, 3.1, 0), biome.Glow, M.Neon)
			top.CanCollide = false
			NanoKit.Column(parent, "CrucibleRim", 0.4, 4.8, p + Vector3.new(0, 3, 0), biome.Metal, M.Metal)
		end
	elseif kind == "Nexus" then
		-- server racks along the wall + floating data pillars
		local count = math.max(3, math.floor(length / 5))
		for i = 1, count do
			local p = from + dir * (length * (i - 0.5) / count) + Vector3.new(side * 0.8, 0, 0)
			local rack = Panel(parent, "ServerRack", Vector3.new(2.4, 9, 3.4), CFrame.lookAt(p + Vector3.new(0, 4.5, 0), p + Vector3.new(-side, 4.5, 0)), biome.Metal, M.Foil)
			for r = 1, 6 do
				local led = Panel(parent, "RackLed", Vector3.new(0.1, 0.12, 2.4), rack.CFrame * CFrame.new(0, -4.5 + r * 1.3, -1.25) * CFrame.Angles(0, math.rad(90), 0), if (i + r) % 3 == 0 then biome.Accent else biome.Glow, M.Neon, { CanCollide = false })
				local _ = led
			end
		end
		for _, k in ipairs({ -0.25, 0.25 }) do
			local p = (cf * CFrame.new(-side * 7, 0, length * k)).Position
			NanoKit.Column(parent, "PillarBase", 1, 3, p, biome.Metal, M.Foil)
			local cube = Panel(parent, "DataCube", Vector3.new(1.8, 1.8, 1.8), CFrame.new(p + Vector3.new(0, 4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), biome.Glow, M.Glass, { CanCollide = false, Transparency = 0.25 })
			NanoKit.Tag(cube, "Spin", { Speed = 40, Axis = "Y" })
			NanoKit.Tag(cube, "Bob", { Amplitude = 0.5, Period = 2.6 })
			WorldKit.Light(cube, biome.Glow, 14, 0.9)
		end
	elseif kind == "Infected" then
		-- biomass pools and spore pods along the wall
		local count = math.max(3, math.floor(length / 10))
		for i = 1, count do
			local p = from + dir * (length * (i - 0.5) / count)
			local pool = NanoKit.Cylinder(parent, "Biomass", 0.25, 5 + (i % 3) * 2, CFrame.new(p + Vector3.new(-side * 2, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.Floor:Lerp(biome.Glow, 0.25), M.Smooth)
			pool.CanCollide = false
			local pod = Panel(parent, "SporePod", Vector3.new(2.2, 3, 2.2), CFrame.new(p + Vector3.new(0, 1.5, 0)), biome.Glow, M.Smooth, { Shape = Enum.PartType.Ball, Transparency = 0.2, CanCollide = false })
			NanoKit.Tag(pod, "Pulse", { Period = 2 + i * 0.25 })
			if i % 2 == 1 then
				WorldKit.Light(pod, biome.Glow, 12, 0.8)
			end
		end
	else
		conveyor(parent, biome, from, to)
	end
end

-- Owner props (crates, barrels, misc) in the front corners and on the
-- wall opposite the conveyor (`side` = the conveyor's side).

---------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------

-- Floor with the biome's AI material when it exists.
local function floorPart(parent, center: Vector3, sizeX: number, sizeZ: number, biome, name: string)
	local part = Panel(parent, name, Vector3.new(sizeX, 1, sizeZ), CFrame.new(center + Vector3.new(0, -0.5, 0)), biome.Floor, biome.FloorMaterial or M.Plate)
	local variant = biome.FloorVariant and MaterialService:FindFirstChild(biome.FloorVariant, true)
	if variant and variant:IsA("MaterialVariant") then
		if variant.StudsPerTile < G.FloorTile then
			variant.StudsPerTile = G.FloorTile -- big tiles: calmer floor
		end
		part.Material = variant.BaseMaterial
		part.MaterialVariant = variant.Name
		part.Color = biome.Floor:Lerp(Color3.new(1, 1, 1), 0.45)
	end
	return part
end

-- Wall from a to b (ground points), inner side `inward`; gaps = list of
-- { center = distance from a, width }.
local function wall(parent, biome, a: Vector3, b: Vector3, inward: Vector3, height: number, gaps)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local t = 3
	local cuts = {}
	for _, g in ipairs(gaps or {}) do
		table.insert(cuts, { g.center - g.width / 2, g.center + g.width / 2 })
	end
	table.sort(cuts, function(x, y)
		return x[1] < y[1]
	end)
	local pieces, u = {}, -t
	for _, c in ipairs(cuts) do
		table.insert(pieces, { u, c[1] })
		u = c[2]
	end
	table.insert(pieces, { u, length + t })
	for _, piece in ipairs(pieces) do
		local w = piece[2] - piece[1]
		if w > 0.2 then
			local mid = a + dir * ((piece[1] + piece[2]) / 2)
			local cf = CFrame.lookAt(mid, mid + inward)
			Panel(parent, "Wall", Vector3.new(w, height, t), cf * CFrame.new(0, height / 2, t / 2), biome.StoneA, biome.WallMaterial or M.Concrete)
			Panel(parent, "Base", Vector3.new(w, 1.6, 0.6), cf * CFrame.new(0, 0.8, -0.3), biome.Metal, M.Metal)
			Panel(parent, "Top", Vector3.new(w + 0.2, 1, t + 1.2), cf * CFrame.new(0, height + 0.5, t / 2), biome.Metal, M.Metal)
			NanoKit.Strip(parent, (cf * CFrame.new(-w / 2, 2.4, -0.62)).Position, (cf * CFrame.new(w / 2, 2.4, -0.62)).Position, biome.Accent, 0.14)
			-- pilasters every 14 studs
			local count = math.floor(w / 14)
			for i = 1, count do
				local x = -w / 2 + i * (w / (count + 1))
				Panel(parent, "Pilaster", Vector3.new(2, height - 1, 1.2), cf * CFrame.new(x, (height - 1) / 2, -0.6), biome.StoneB, biome.PanelMaterial or M.Metal)
			end
		end
	end
end

-- Energy barrier in a doorway (closed until the run opens it).
local function barrier(parent, cf: CFrame, width: number, height: number, color: Color3)
	local part = WorldKit.Part(parent, {
		Name = "Barrier",
		Size = Vector3.new(width, height, 1),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CastShadow = false,
	})
	WorldKit.Light(part, color, 16, 1)
	return part
end

-- Door frame with the zone label over it.
local function doorFrame(parent, biome, cf: CFrame, width: number, height: number, label: string?)
	for _, side in ipairs({ -1, 1 }) do
		Panel(parent, "DoorPost", Vector3.new(2.2, height + 2, 3.6), cf * CFrame.new(side * (width / 2 + 1.1), (height + 2) / 2, 0), biome.Metal, M.Metal)
		NanoKit.Strip(parent, (cf * CFrame.new(side * (width / 2 + 0.05), 0.5, -1.85)).Position, (cf * CFrame.new(side * (width / 2 + 0.05), height, -1.85)).Position, biome.Accent, 0.16)
	end
	local lintel = Panel(parent, "Lintel", Vector3.new(width + 4.4, 3, 3.6), cf * CFrame.new(0, height + 1.5, 0), biome.Metal, M.Metal)
	if label then
		WorldKit.SurfaceText(lintel, Enum.NormalId.Back, { { Text = label, Size = 60, Color = biome.Accent } }, 50)
		WorldKit.SurfaceText(lintel, Enum.NormalId.Front, { { Text = label, Size = 60, Color = biome.Accent } }, 50)
	end
end

-- Cover block (waist high, you can hide behind it from shots).
local function cover(parent, biome, cf: CFrame, rng: Random)
	local m = NanoKit.Model(parent, "Cover")
	local w = rng:NextNumber(7, 11)
	Panel(m, "Block", Vector3.new(w, 4.4, 2.4), cf * CFrame.new(0, 2.2, 0), biome.StoneB, biome.PanelMaterial or M.Metal)
	Panel(m, "Cap", Vector3.new(w + 0.4, 0.5, 2.8), cf * CFrame.new(0, 4.6, 0), biome.Metal, M.Plate)
	NanoKit.Strip(m, (cf * CFrame.new(-w / 2, 3.4, -1.25)).Position, (cf * CFrame.new(w / 2, 3.4, -1.25)).Position, biome.Accent, 0.12)
	NanoKit.Strip(m, (cf * CFrame.new(-w / 2, 3.4, 1.25)).Position, (cf * CFrame.new(w / 2, 3.4, 1.25)).Position, biome.Accent, 0.12)
	-- a biome detail on top / beside
	local theme = biome.Theme
	if theme == "Cryo" then
		local tank = NanoKit.Column(m, "Tank", 5, 2.2, (cf * CFrame.new(w / 2 + 1.6, 0, 0)).Position, biome.Glow, M.Smooth)
		tank.Transparency = 0.55
	elseif theme == "Smelter" then
		NanoKit.Barrel(m, cf * CFrame.new(w / 2 + 1.8, 0, 0.4))
	elseif theme == "Infected" then
		local sac = Panel(m, "Growth", Vector3.new(3, 2.2, 3), cf * CFrame.new(-w / 4, 4.9, 0), biome.Glow, M.Smooth, { Shape = Enum.PartType.Ball, Transparency = 0.25, CanCollide = false })
		NanoKit.Tag(sac, "Pulse", { Period = 2.2 })
	elseif theme == "Nexus" then
		local cube = Panel(m, "Cube", Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(w / 4, 6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), biome.Glow, M.Glass, { CanCollide = false, Transparency = 0.3 })
		NanoKit.Tag(cube, "Spin", { Speed = 40, Axis = "Y" })
	else
		NanoKit.Crate(m, cf * CFrame.new(w / 2 + 1.8, 0, 0) * CFrame.Angles(0, math.rad(rng:NextInteger(-20, 20)), 0), Vector3.new(2.6, 2.6, 2.6))
	end
	return m
end

-- Roof over a hall: dark plates on girders with two glowing light slits
-- (or just an invisible lid when Config.GateMap.Ceiling is off).
roof = function(parent, biome, center: Vector3, sizeX: number, sizeZ: number, height: number)
	if not G.Ceiling then
		WorldKit.Invisible(parent, Vector3.new(sizeX + 6, 2, sizeZ + 6), center + Vector3.new(0, height + 18, 0), "Lid")
		return
	end
	Panel(parent, "Roof", Vector3.new(sizeX + 6, 1.2, sizeZ + 6), CFrame.new(center + Vector3.new(0, height + 0.6, 0)), biome.Metal:Lerp(Color3.new(0, 0, 0), 0.35), M.Metal)
	local count = math.floor(sizeZ / 16)
	for i = 1, count do
		local z = -sizeZ / 2 + i * sizeZ / (count + 1)
		Panel(parent, "Girder", Vector3.new(sizeX, 1.6, 1.2), CFrame.new(center + Vector3.new(0, height - 0.8, z)), biome.Metal, M.Metal, { CanCollide = false })
	end
	for _, x in ipairs({ -sizeX * 0.22, sizeX * 0.22 }) do
		local slit = Panel(parent, "LightSlit", Vector3.new(1.4, 0.2, sizeZ * 0.8), CFrame.new(center + Vector3.new(x, height - 0.1, 0)), biome.Light, M.Neon, { CanCollide = false, CastShadow = false })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Color = biome.Light
		light.Range = height + 6
		light.Brightness = 1.2
		light.Angle = 120
		light.Parent = slit
	end
end

-- Spawn portal / hatch: a dark disc with a thin ring (the run makes it
-- glow when an enemy comes out).
local function portal(parent, biome, position: Vector3)
	local m = NanoKit.Model(parent, "Portal")
	NanoKit.Cylinder(m, "Hatch", 0.3, 6, CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(18, 18, 22), M.Metal).CanCollide = false
	local ring = NanoKit.Cylinder(m, "Ring", 0.32, 6.6, CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.Accent, M.Neon)
	ring.CanCollide = false
	ring.Transparency = 0.5
	for i = 0, 3 do
		local a = i * math.pi / 2
		Panel(m, "Clamp", Vector3.new(1, 0.5, 1.6), CFrame.new(position + Vector3.new(math.cos(a) * 3.2, 0.25, math.sin(a) * 3.2)) * CFrame.Angles(0, -a, 0), biome.Metal, M.Metal)
	end
	return m, ring
end

local function pylon(parent, biome, position: Vector3)
	local m = NanoKit.Model(parent, "Pylon")
	Panel(m, "Foot", Vector3.new(2.6, 1, 2.6), CFrame.new(position + Vector3.new(0, 0.5, 0)), biome.Metal, M.Metal)
	Panel(m, "Mast", Vector3.new(1.1, 13, 1.1), CFrame.new(position + Vector3.new(0, 7, 0)), biome.Metal, M.Metal)
	local head = Panel(m, "Lamp", Vector3.new(2.6, 0.6, 2.6), CFrame.new(position + Vector3.new(0, 13.6, 0)), biome.Metal, M.Metal)
	Panel(m, "Bulb", Vector3.new(2.2, 0.15, 2.2), CFrame.new(position + Vector3.new(0, 13.25, 0)), biome.Light, M.Neon, { CanCollide = false, CastShadow = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = biome.Light
	light.Range = 34
	light.Angle = 110
	light.Brightness = 2
	light.Shadows = false
	light.Parent = head
	return m
end

local function landmark(parent, biome, cf: CFrame, height: number)
	local prop = biome.Landmark and NanoKit.Prop(parent, biome.Landmark, cf, height)
	if prop then
		prop.Name = "Landmark"
		for _, d in ipairs(prop:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = true
			end
		end
		local box = prop:GetBoundingBox()
		local glow = Instance.new("PointLight")
		glow.Color = biome.Glow
		glow.Range = 24
		glow.Brightness = 1.4
		glow.Parent = prop:FindFirstChildWhichIsA("BasePart", true)
		local _ = box
		return prop
	end
	local m = NanoKit.Model(parent, "Landmark")
	machine(m, biome, cf)
	return m
end

---------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------

-- A square zone. exitX / entryX = door offsets along X (nil = no door).
local function buildZone(folder, biome, rng: Random, index: number, center: Vector3, size: number, entryX: number?, exitX: number?)
	local m = NanoKit.Model(folder, ("Zone%d"):format(index))
	local half = size / 2
	local H = G.WallHeight
	local C = G.Corridor
	floorPart(m, center, size, size, biome, "Floor")
	-- floor markings: a ring in the middle and two lanes between the doors
	local ring = NanoKit.Cylinder(m, "Ring", 0.08, 26, CFrame.new(center + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.Accent:Lerp(biome.Floor, 0.55), M.Smooth)
	ring.CanCollide = false
	local inner = NanoKit.Cylinder(m, "RingInner", 0.09, 25, CFrame.new(center + Vector3.new(0, 0.045, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.FloorB, biome.FloorMaterial or M.Plate)
	inner.CanCollide = false
	-- walls with door gaps (south = entry, north = exit)
	local sw, se, nw, ne = center + Vector3.new(-half, 0, half), center + Vector3.new(half, 0, half), center + Vector3.new(-half, 0, -half), center + Vector3.new(half, 0, -half)
	wall(m, biome, sw, se, Vector3.new(0, 0, -1), H, if entryX then { { center = entryX + half, width = C.Width } } else nil)
	wall(m, biome, ne, nw, Vector3.new(0, 0, 1), H, if exitX then { { center = half - exitX, width = C.Width } } else nil)
	wall(m, biome, nw, sw, Vector3.new(1, 0, 0), H, nil)
	wall(m, biome, se, ne, Vector3.new(-1, 0, 0), H, nil)
	local exitBarrier
	if exitX then
		local cf = CFrame.lookAt(center + Vector3.new(exitX, 0, -half), center + Vector3.new(exitX, 0, -half - 1))
		doorFrame(m, biome, cf, C.Width, C.Height, G.Texts.Zone:format(index + 1))
		exitBarrier = barrier(m, cf, C.Width, C.Height, biome.Accent)
	end
	-- lamp pylons near the corners
	local inset = half - 7
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		pylon(m, biome, center + Vector3.new(c[1] * inset, 0, c[2] * inset))
	end
	task.wait()
	-- landmark in a corner (seeded), decor along the opposite side wall
	local corner = rng:NextInteger(1, 4)
	local signs = ({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } })[corner]
	local lmPos = center + Vector3.new(signs[1] * (half - 13), 0, signs[2] * (half - 15))
	landmark(m, biome, CFrame.lookAt(lmPos, Vector3.new(center.X, lmPos.Y, center.Z)), 16)
	local side = -signs[1]
	local decorX = center.X + side * (half - 4)
	biomeDecor(m, biome, Vector3.new(decorX, center.Y, center.Z + half - 16), Vector3.new(decorX, center.Y, center.Z - half + 16), side)
	-- covers in a ring between the middle and the walls
	local covers = {}
	for i = 1, G.Covers do
		local a = (i - 1) / G.Covers * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local r = rng:NextNumber(half * 0.42, half * 0.62)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		-- keep the door lanes free
		local free = true
		for _, dx in ipairs({ entryX, exitX }) do
			if dx and math.abs(p.X - (center.X + dx)) < C.Width and math.abs(math.abs(p.Z - center.Z) - half) < 22 then
				free = false
			end
		end
		if (p - lmPos).Magnitude < 16 then
			free = false
		end
		if free then
			table.insert(covers, cover(m, biome, CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)), rng))
		end
	end
	-- spawn portals by the walls
	local portals = {}
	local spots = { Vector3.new(-half + 8, 0, -half * 0.3), Vector3.new(half - 8, 0, -half * 0.3), Vector3.new(-half * 0.45, 0, -half + 8), Vector3.new(half * 0.45, 0, -half + 8), Vector3.new(-half + 8, 0, half * 0.35), Vector3.new(half - 8, 0, half * 0.35) }
	for i = 1, math.min(G.Portals, #spots) do
		local p = center + spots[(i + index) % #spots + 1]
		local _, ringPart = portal(m, biome, p)
		table.insert(portals, { Position = p + Vector3.new(0, 3, 0), Ring = ringPart })
	end
	roof(m, biome, center, size, size, H)
	m.Parent = folder
	return {
		Index = index,
		Model = m,
		Center = center,
		Size = size,
		Portals = portals,
		Exit = exitBarrier,
		Entry = CFrame.lookAt(center + Vector3.new(entryX or 0, 3, half - 8), center + Vector3.new(0, 3, 0)),
	}
end

local function buildCorridor(folder, biome, from: Vector3, to: Vector3)
	local m = NanoKit.Model(folder, "Corridor")
	local C = G.Corridor
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	floorPart(m, mid, C.Width + 6, length, biome, "Floor").CFrame = cf * CFrame.new(0, -0.5, 0)
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Wall", Vector3.new(3, C.Height + 2, length), cf * CFrame.new(side * (C.Width / 2 + 1.5), (C.Height + 2) / 2, 0), biome.StoneB, biome.WallMaterial or M.Concrete)
		NanoKit.Strip(m, (cf * CFrame.new(side * (C.Width / 2 - 0.1), 2, -length / 2)).Position, (cf * CFrame.new(side * (C.Width / 2 - 0.1), 2, length / 2)).Position, biome.Accent, 0.14)
	end
	Panel(m, "Roof", Vector3.new(C.Width + 6, 1, length), cf * CFrame.new(0, C.Height + 2.5, 0), biome.Metal, M.Metal)
	local lamp = Panel(m, "Lamp", Vector3.new(3, 0.3, 1.4), cf * CFrame.new(0, C.Height + 1.8, 0), biome.Light, M.Neon, { CanCollide = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = biome.Light
	light.Range = C.Height + 8
	light.Brightness = 1.6
	light.Angle = 120
	light.Parent = lamp
	m.Parent = folder
	return m
end

local function buildArena(folder, biome, center: Vector3, size: number, entryX: number, boss)
	local m = NanoKit.Model(folder, "Arena")
	local half = size / 2
	local H = G.WallHeight + 4
	local C = G.Corridor
	floorPart(m, center, size, size, biome, "Floor")
	-- octagon: 4 straight walls + 4 cut corners
	local cut = size * 0.22
	local pts = {
		center + Vector3.new(-half + cut, 0, half), center + Vector3.new(half - cut, 0, half),
		center + Vector3.new(half, 0, half - cut), center + Vector3.new(half, 0, -half + cut),
		center + Vector3.new(half - cut, 0, -half), center + Vector3.new(-half + cut, 0, -half),
		center + Vector3.new(-half, 0, -half + cut), center + Vector3.new(-half, 0, half - cut),
	}
	for i = 1, 8 do
		local a, b = pts[i], pts[i % 8 + 1]
		local mid = (a + b) / 2
		local inward = Vector3.new(center.X - mid.X, 0, center.Z - mid.Z).Unit
		local gaps = nil
		if i == 1 then
			gaps = { { center = (entryX + half) - cut, width = C.Width } }
		end
		wall(m, biome, a, b, inward, H, gaps)
	end
	-- corner fill under the cut walls (so the floor reads as an octagon)
	local entry = CFrame.lookAt(center + Vector3.new(entryX, 0, half), center + Vector3.new(entryX, 0, half - 1))
	doorFrame(m, biome, entry, C.Width, C.Height, G.Texts.Boss)
	local gate = barrier(m, entry, C.Width, C.Height, Config.DungeonLayout.BossBarrierColor)
	gate.CanCollide = false
	gate.Transparency = 1
	-- rings and the boss platform
	for i, r in ipairs({ 0.82, 0.55, 0.3 }) do
		local disc = NanoKit.Cylinder(m, "ArenaRing", 0.08 + i * 0.01, size * r, CFrame.new(center + Vector3.new(0, 0.04 + i * 0.01, 0)) * CFrame.Angles(0, 0, math.rad(90)), if i % 2 == 1 then biome.Accent:Lerp(biome.Floor, 0.5) else biome.FloorB, M.Smooth)
		disc.CanCollide = false
	end
	-- big pylons on the diagonals
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local p = center + Vector3.new(c[1] * half * 0.52, 0, c[2] * half * 0.52)
		NanoKit.Column(m, "Pillar", H - 4, 4.4, p, biome.Metal, M.Metal)
		NanoKit.Column(m, "PillarBase", 2, 6.4, p, biome.StoneB, M.Metal)
		NanoKit.Strip(m, p + Vector3.new(0, 2.5, -2.3), p + Vector3.new(0, H - 6, -2.3), biome.Glow, 0.2)
		local cap = NanoKit.Column(m, "PillarCap", 1, 5, p + Vector3.new(0, H - 4, 0), biome.Glow, M.Neon)
		cap.CanCollide = false
		WorldKit.Light(cap, biome.Glow, 30, 1.2)
	end
	landmark(m, biome, CFrame.lookAt(center + Vector3.new(0, 0, -half + 12), center), 22)
	roof(m, biome, center, size, size, H)
	m.Parent = folder
	local spawn = center + Vector3.new(0, 4, -size * 0.18)
	return {
		Model = m,
		Center = center,
		Size = size,
		Gate = gate,
		Entry = CFrame.lookAt(center + Vector3.new(entryX, 3, half - 8), center + Vector3.new(0, 3, 0)),
		Spawn = CFrame.lookAt(spawn, Vector3.new(center.X, spawn.Y, center.Z + half)),
		Portals = {
			{ Position = center + Vector3.new(-half * 0.5, 3, 0) }, { Position = center + Vector3.new(half * 0.5, 3, 0) },
			{ Position = center + Vector3.new(0, 3, -half * 0.55) }, { Position = center + Vector3.new(0, 3, half * 0.35) },
		},
		Boss = boss,
	}
end

---------------------------------------------------------------------

local function slotOrigin(slot: number): Vector3
	return Vector3.new(G.Origin.X + (slot - 1) * G.SlotSpacing, groundY, G.Origin.Z)
end

-- Builds the whole location for a run in `slot`. Returns the map.
function GateMap.Build(location, slot: number)
	local biome = GateMap.Biome(location.Biome)
	local rng = Random.new(location.Seed or 1)
	local folder = Instance.new("Folder")
	folder.Name = ("Run_%d"):format(slot)
	folder:SetAttribute("Location", location.Id)
	folder.Parent = lanesFolder
	local size, C = G.ZoneSize, G.Corridor
	local center = slotOrigin(slot)
	-- bedrock under the whole run
	local zones = {}
	local entryX = 0
	for index = 1, #location.Zones do
		local exitX = rng:NextInteger(-math.floor(size * 0.28), math.floor(size * 0.28))
		local zone = buildZone(folder, biome, rng, index, center, size, entryX, exitX)
		table.insert(zones, zone)
		-- the next room's door sits right in front of this exit
		local doorOut = center + Vector3.new(exitX, 0, -size / 2)
		local nextSize = if index == #location.Zones then G.BossSize else size
		local nextEntryX = rng:NextInteger(-math.floor(nextSize * 0.2), math.floor(nextSize * 0.2))
		local nextCenter = Vector3.new(doorOut.X - nextEntryX, center.Y, doorOut.Z - C.Length - nextSize / 2)
		buildCorridor(folder, biome, doorOut, Vector3.new(doorOut.X, center.Y, doorOut.Z - C.Length))
		center = nextCenter
		entryX = nextEntryX
		task.wait()
	end
	local arena = buildArena(folder, biome, center, G.BossSize, entryX, location.Boss)
	-- bedrock and the lowest point
	local first = zones[1].Center
	local minZ, maxZ = center.Z - G.BossSize, first.Z + size
	WorldKit.Part(folder, {
		Name = "Bedrock",
		Size = Vector3.new(size * 4, 4, maxZ - minZ),
		Position = Vector3.new(first.X, groundY - 3, (minZ + maxZ) / 2),
		Color = Color3.fromRGB(16, 14, 22),
		Material = Enum.Material.Slate,
		Transparency = 1,
	})
	return {
		Folder = folder,
		Biome = biome,
		Zones = zones,
		Arena = arena,
		Start = zones[1].Entry,
	}
end

-- Root folders (Workspace.Dungeon.Lanes, kept for the client modules).
function GateMap.Init()
	root = Instance.new("Folder")
	root.Name = "Dungeon"
	lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = root
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	root.Parent = Workspace
	return { Folder = root, Lanes = lanesFolder }
end

function GateMap.GroundY(): number
	return groundY
end

return GateMap
