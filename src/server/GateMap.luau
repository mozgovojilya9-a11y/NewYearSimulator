--[[
	GateMap.luau
	Builds the map of a gate location for one run (Config.Gates.Locations,
	Config.GateMap, the biome look of Config.DungeonLayout.Biomes):

	  [start] Section 1 -> corridor -> Section 2 -> ... -> corridor -> Boss arena

	A section ("zone" in code) is a square hall with a roof and its own
	layout (Config.GateMap.Layouts, shuffled per location): pillars, a
	cross, a core machine, a split wall, a junk yard or cover lanes; worn
	floor plates, the biome decor along a wall, hanging lamps. Post = where the section's enemy
	group stands (in front of the exit). Zones snake left / right (seeded per location, so a location
	always looks the same). The exit of a zone is an energy barrier that
	the run opens as soon as the section's group is dead; the boss arena is an octagon
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

-- Glowing crystal clusters (sheet 07 Crystal Caverns).
local function crystalCluster(parent, biome, p: Vector3, scale: number, rng: Random)
	local m = NanoKit.Model(parent, "Crystals")
	for i = 1, rng:NextInteger(3, 6) do
		local h = rng:NextNumber(3, 8) * scale
		local w = rng:NextNumber(0.8, 1.8) * scale
		local color = if i % 3 == 0 then biome.Glow else biome.Accent
		local c = Panel(m, "Crystal", Vector3.new(w, h, w), CFrame.new(p + Vector3.new(rng:NextNumber(-1.5, 1.5) * scale, h * 0.4, rng:NextNumber(-1.5, 1.5) * scale)) * CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, 6.28), rng:NextNumber(-0.45, 0.45)), color, M.Glass, { Transparency = 0.15 })
		if i == 1 then
			WorldKit.Light(c, color, 16 * scale, 1.2)
			local core = Panel(m, "CrystalCore", Vector3.new(w * 0.4, h * 0.7, w * 0.4), c.CFrame, color, M.Neon, { CanCollide = false, Transparency = 0.2 })
			local _ = core
		end
	end
	Panel(m, "Rock", Vector3.new(4, 1.6, 4) * scale, CFrame.new(p + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0.2), biome.StoneB, Enum.Material.Rock)
	return m
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
	elseif theme == "Crystal" then
		crystalCluster(parent, biome, cf.Position, 2.6, Random.new(5))
	elseif theme == "Orbital" then
		local core = Panel(parent, "OrbitalCore", Vector3.new(4, 4, 4), cf * CFrame.new(0, 7, 0), biome.Glow, M.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, Transparency = 0.15 })
		NanoKit.Tag(core, "Pulse", { Period = 2 })
		NanoKit.Column(parent, "CorePylon", 4, 5, cf.Position, biome.Metal, M.Metal)
		WorldKit.Light(core, biome.Glow, 26, 1.6)
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
	elseif kind == "Crystal" then
		local rng = Random.new(math.floor(from.X * 7 + from.Z * 3))
		local count = math.max(3, math.floor(length / 9))
		for i = 1, count do
			local p = from + dir * (length * (i - 0.5) / count) + Vector3.new(-side * rng:NextNumber(0, 3), 0, 0)
			crystalCluster(parent, biome, p, rng:NextNumber(0.9, 1.5), rng)
		end
	elseif kind == "Orbital" then
		-- holo screens on the wall and light lines on the floor
		local count = math.max(2, math.floor(length / 14))
		for i = 1, count do
			local p = from + dir * (length * (i - 0.5) / count)
			local cf = CFrame.lookAt(p + Vector3.new(0, 7, 0), p + Vector3.new(-side, 7, 0))
			local screen = Panel(parent, "HoloScreen", Vector3.new(6, 3.6, 0.1), cf, biome.Accent, M.Neon, { CanCollide = false, Transparency = 0.6 })
			for r = 1, 3 do
				Panel(parent, "HoloLine", Vector3.new(4.4 - r * 0.8, 0.15, 0.05), cf * CFrame.new(0, 1 - r * 0.6, -0.08), Color3.new(1, 1, 1), M.Neon, { CanCollide = false, Transparency = 0.3 })
			end
			WorldKit.Light(screen, biome.Accent, 12, 0.8)
		end
		for _, off in ipairs({ -1.5, 1.5 }) do
			NanoKit.Strip(parent, from + Vector3.new(-side * (4 + off), 0.06, 0), to + Vector3.new(-side * (4 + off), 0.06, 0), biome.Accent, 0.25)
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
		part.Color = biome.Floor:Lerp(Color3.new(1, 1, 1), 0.12) -- dark: the texture stays calm
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

-- A steel drum in the biome's metal (the owner's white barrel shouted).
local function drum(parent, biome, cf: CFrame)
	local p = cf.Position
	NanoKit.Column(parent, "Drum", 3, 2.2, p, biome.Metal:Lerp(biome.Accent, 0.18), M.Metal)
	for _, y in ipairs({ 0.5, 2.4 }) do
		NanoKit.Column(parent, "DrumBand", 0.25, 2.35, p + Vector3.new(0, y, 0), biome.Metal:Lerp(Color3.new(0, 0, 0), 0.4), M.Metal)
	end
end

-- Cover block (waist high, you can hide behind it from shots).
local function cover(parent, biome, cf: CFrame, rng: Random)
	local m = NanoKit.Model(parent, "Cover")
	local w = rng:NextNumber(7, 11)
	Panel(m, "Block", Vector3.new(w, 4.4, 2.4), cf * CFrame.new(0, 2.2, 0), biome.StoneB, biome.PanelMaterial or M.Metal)
	Panel(m, "Cap", Vector3.new(w + 0.4, 0.5, 2.8), cf * CFrame.new(0, 4.6, 0), biome.Metal, M.Plate)
	NanoKit.Strip(m, (cf * CFrame.new(-w / 2, 3.4, -1.25)).Position, (cf * CFrame.new(w / 2, 3.4, -1.25)).Position, biome.Accent, 0.12)
	-- a biome detail on top / beside
	local theme = biome.Theme
	if theme == "Cryo" then
		local tank = NanoKit.Column(m, "Tank", 5, 2.2, (cf * CFrame.new(w / 2 + 1.6, 0, 0)).Position, biome.Glow, M.Smooth)
		tank.Transparency = 0.55
	elseif theme == "Smelter" then
		drum(m, biome, cf * CFrame.new(w / 2 + 1.8, 0, 0.4))
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

-- A big solid structure (no neon): foot, body, cap.
local function mass(parent, biome, cf: CFrame, size: Vector3, color: Color3?)
	local m = NanoKit.Model(parent, "Mass")
	Panel(m, "Foot", Vector3.new(size.X + 0.8, 1.2, size.Z + 0.8), cf * CFrame.new(0, 0.6, 0), biome.Metal, M.Metal)
	Panel(m, "Body", size, cf * CFrame.new(0, size.Y / 2, 0), color or biome.StoneB, biome.WallMaterial or M.Concrete)
	Panel(m, "Cap", Vector3.new(size.X + 0.6, 0.8, size.Z + 0.6), cf * CFrame.new(0, size.Y + 0.4, 0), biome.Metal, M.Metal)
	-- panel seams so big blocks don't read as one flat box
	local seams = math.floor(size.X / 6)
	for i = 1, seams do
		local x = -size.X / 2 + i * size.X / (seams + 1)
		for _, z in ipairs({ -size.Z / 2 - 0.05, size.Z / 2 + 0.05 }) do
			Panel(m, "Seam", Vector3.new(0.3, size.Y - 1.6, 0.2), cf * CFrame.new(x, size.Y / 2, z), biome.Metal, M.Metal, { CanCollide = false })
		end
	end
	return m
end

-- A round support pillar up to the roof, with a lamp ring at head height.
local function pillar(parent, biome, p: Vector3, height: number, lit: boolean)
	NanoKit.Column(parent, "PillarFoot", 1.4, 6, p, biome.Metal, M.Metal)
	NanoKit.Column(parent, "Pillar", height, 4, p, biome.StoneA, biome.WallMaterial or M.Concrete)
	NanoKit.Column(parent, "PillarBand", 0.8, 4.6, p + Vector3.new(0, height * 0.62, 0), biome.Metal, M.Metal)
	if lit then
		local lamp = NanoKit.Column(parent, "PillarLamp", 0.3, 4.8, p + Vector3.new(0, height * 0.62 - 0.4, 0), biome.Light, M.Neon)
		lamp.CanCollide = false
		WorldKit.Light(lamp, biome.Light, 26, 0.9)
	end
end

-- A pile of junk: crates, barrels, owner props.
local function clutter(parent, biome, rng: Random, p: Vector3)
	local m = NanoKit.Model(parent, "Clutter")
	local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local kind = rng:NextInteger(1, 4)
	if kind == 1 then
		NanoKit.Crate(m, cf, Vector3.new(3.4, 3.4, 3.4))
		NanoKit.Crate(m, cf * CFrame.new(3.6, 0, 0.4) * CFrame.Angles(0, 0.3, 0), Vector3.new(2.8, 2.8, 2.8))
		drum(m, biome, cf * CFrame.new(-3, 0, 1.2))
	elseif kind == 2 then
		NanoKit.Crate(m, cf, Vector3.new(4, 4, 4))
		NanoKit.Crate(m, cf * CFrame.new(0, 4, 0) * CFrame.Angles(0, 0.4, 0), Vector3.new(3, 3, 3))
		drum(m, biome, cf * CFrame.new(3.4, 0, 1))
	elseif kind == 3 then
		NanoKit.Prop(m, "Prop_Pipes", cf, 6, function(pp, c)
			return drum(pp, biome, c)
		end)
		drum(m, biome, cf * CFrame.new(-3, 0, 0))
		drum(m, biome, cf * CFrame.new(-3.2, 0, 2.4))
	else
		-- a fallen girder over two broken blocks
		Panel(m, "Debris", Vector3.new(3, 2, 3), cf * CFrame.new(-3, 1, 0), biome.StoneB, M.Concrete)
		Panel(m, "Debris", Vector3.new(2.4, 1.6, 2.6), cf * CFrame.new(3, 0.8, 0.6), biome.StoneB, M.Concrete)
		Panel(m, "FallenGirder", Vector3.new(10, 1, 1.4), cf * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(8)), biome.Metal, M.Metal)
	end
	return m
end

-- A hanging lamp (cable + shade + warm downlight).
local function hangingLamp(parent, biome, p: Vector3, height: number)
	Panel(parent, "LampCable", Vector3.new(0.15, 5, 0.15), CFrame.new(p + Vector3.new(0, height - 2.5, 0)), Color3.fromRGB(20, 20, 24), M.Metal, { CanCollide = false })
	local shade = NanoKit.Cylinder(parent, "LampShade", 1, 3.6, CFrame.new(p + Vector3.new(0, height - 5.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.Metal, M.Metal)
	shade.CanCollide = false
	local bulb = NanoKit.Cylinder(parent, "LampBulb", 0.1, 3, CFrame.new(p + Vector3.new(0, height - 6.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.Light, M.Neon)
	bulb.CanCollide = false
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = biome.Light
	light.Range = height + 4
	light.Angle = 100
	light.Brightness = 2.2
	light.Shadows = true
	light.Parent = shade
end

-- An overhead gantry crane: two rails along the side walls, a bridge
-- beam across, a trolley with a hook block (sheet 07 factory).
local function crane(parent, biome, center: Vector3, half: number, H: number, rng: Random)
	local m = NanoKit.Model(parent, "Crane")
	local y = H - 3
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "CraneRail", Vector3.new(1.4, 1.2, half * 2 - 4), CFrame.new(center + Vector3.new(side * (half - 2), y, 0)), biome.Metal, M.Metal, { CanCollide = false })
	end
	local z = rng:NextNumber(-half * 0.4, half * 0.4)
	Panel(m, "CraneBeam", Vector3.new(half * 2 - 4, 1.8, 2), CFrame.new(center + Vector3.new(0, y - 1.4, z)), Color3.fromRGB(210, 160, 40), M.Metal, { CanCollide = false })
	for k = -1, 1, 2 do
		Panel(m, "HazardStripe", Vector3.new(half * 2 - 4, 0.3, 0.1), CFrame.new(center + Vector3.new(0, y - 1.4 + k * 0.5, z - 1.05)), Color3.fromRGB(30, 30, 30), M.Smooth, { CanCollide = false })
	end
	local x = rng:NextNumber(-half * 0.5, half * 0.5)
	Panel(m, "Trolley", Vector3.new(3, 1.6, 3), CFrame.new(center + Vector3.new(x, y - 3, z)), biome.Metal, M.Metal, { CanCollide = false })
	Panel(m, "Cable", Vector3.new(0.2, 6, 0.2), CFrame.new(center + Vector3.new(x, y - 6.8, z)), Color3.fromRGB(20, 20, 24), M.Metal, { CanCollide = false })
	local hook = Panel(m, "HookBlock", Vector3.new(2, 2, 1.4), CFrame.new(center + Vector3.new(x, y - 10.6, z)), Color3.fromRGB(210, 160, 40), M.Metal, { CanCollide = false })
	NanoKit.Tag(hook, "Bob", { Amplitude = 0.4, Period = 3 })
	local lamp = Panel(m, "CraneLamp", Vector3.new(1.2, 0.3, 1.2), CFrame.new(center + Vector3.new(x, y - 3.9, z)), biome.Light, M.Neon, { CanCollide = false })
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Color = biome.Light
	spot.Range = H
	spot.Angle = 70
	spot.Brightness = 2
	spot.Parent = lamp
	return m
end

-- A catwalk along a side wall at mid height with a railing and posts.
local function catwalk(parent, biome, center: Vector3, half: number, side: number)
	local m = NanoKit.Model(parent, "Catwalk")
	local y = 10
	local x = center.X + side * (half - 3.5)
	local length = half * 2 - 10
	Panel(m, "Deck", Vector3.new(5, 0.5, length), CFrame.new(x, center.Y + y, center.Z), biome.Metal, M.Plate, { CanCollide = false })
	NanoKit.Railing(m, Vector3.new(x - side * 2.5, center.Y + y + 0.25, center.Z - length / 2), Vector3.new(x - side * 2.5, center.Y + y + 0.25, center.Z + length / 2), 3, biome.Accent)
	for z = -length / 2, length / 2, 12 do
		Panel(m, "CatwalkPost", Vector3.new(0.6, y, 0.6), CFrame.new(x, center.Y + y / 2, center.Z + z), biome.Metal, M.Metal, { CanCollide = false })
	end
	return m
end

-- Zone layouts: every section has its own shape (Config.GateMap.Layouts).
--   Pillars  a hall of thick round pillars
--   Cross    solid blocks fill the corners: a cross-shaped room
--   Core     a big machine block in the middle, the fight goes around it
--   Split    a low wall across the room with two gaps
--   Yard     a cluttered storage yard: junk piles everywhere
--   Lanes    long cover walls in two rows (shooting lanes)
-- free(p, r) tells if a spot keeps the door lanes and the post clear.
local LAYOUTS = {}

function LAYOUTS.Pillars(m, biome, rng, center, half, H, free, add)
	for _, x in ipairs({ -0.5, 0, 0.5 }) do
		for _, z in ipairs({ -0.45, 0.05, 0.5 }) do
			local p = center + Vector3.new(x * half * 1.2, 0, z * half * 1.2)
			if free(p, 6) then
				pillar(m, biome, p, H, (x + z) ~= 0)
				add(p)
			end
		end
	end
end

function LAYOUTS.Cross(m, biome, rng, center, half, H, free, add)
	local s = half * 0.62
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local p = center + Vector3.new(c[1] * (half - s / 2), 0, c[2] * (half - s / 2))
		if free(p, s * 0.5) then
			mass(m, biome, CFrame.new(p), Vector3.new(s, H * 0.55, s))
			add(p)
			add(p + Vector3.new(-c[1] * s * 0.3, 0, -c[2] * s * 0.3))
		end
	end
end

function LAYOUTS.Core(m, biome, rng, center, half, H, free, add)
	local size = half * 0.5
	local p = center + Vector3.new(0, 0, half * 0.12)
	mass(m, biome, CFrame.new(p), Vector3.new(size, 7, size), biome.Metal)
	landmark(m, biome, CFrame.new(p + Vector3.new(0, 7.8, 0)), 14)
	add(p)
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		add(p + Vector3.new(c[1] * size * 0.35, 0, c[2] * size * 0.35))
	end
	-- cables from the core up into the roof
	for _, k in ipairs({ -1, 1 }) do
		NanoKit.Cable(m, p + Vector3.new(k * size * 0.4, 8, 0), center + Vector3.new(k * half * 0.9, H - 2, 0), 4, Color3.fromRGB(26, 26, 30))
	end
end

function LAYOUTS.Split(m, biome, rng, center, half, H, free, add)
	local z = center.Z + half * 0.05
	local gapA = rng:NextNumber(-half * 0.6, -half * 0.2)
	local gapB = rng:NextNumber(half * 0.2, half * 0.6)
	local cuts = { -half, gapA - 6, gapA + 6, gapB - 6, gapB + 6, half }
	for i = 1, #cuts - 1, 2 do
		local x1, x2 = cuts[i], cuts[i + 1]
		local w = x2 - x1
		if w > 2 then
			local p = Vector3.new(center.X + (x1 + x2) / 2, center.Y, z)
			mass(m, biome, CFrame.new(p), Vector3.new(w, 5, 3))
			for x = x1 + 4, x2 - 4, 8 do
				add(Vector3.new(center.X + x, center.Y, z))
			end
		end
	end
end

function LAYOUTS.Yard(m, biome, rng, center, half, H, free, add)
	for _ = 1, 11 do
		local p = center + Vector3.new(rng:NextNumber(-half * 0.8, half * 0.8), 0, rng:NextNumber(-half * 0.8, half * 0.8))
		if free(p, 7) then
			clutter(m, biome, rng, p)
			add(p)
		end
	end
end

function LAYOUTS.Lanes(m, biome, rng, center, half, H, free, add)
	for _, x in ipairs({ -0.45, 0.45 }) do
		for _, z in ipairs({ -0.35, 0.3 }) do
			local p = center + Vector3.new(x * half, 0, z * half)
			if free(p, 6) then
				cover(m, biome, CFrame.lookAt(p, p + Vector3.new(1, 0, 0)), rng)
				add(p)
			end
		end
	end
	for _ = 1, 2 do
		local p = center + Vector3.new(rng:NextNumber(-half * 0.15, half * 0.15), 0, rng:NextNumber(-half * 0.1, half * 0.4))
		if free(p, 6) then
			cover(m, biome, CFrame.new(p), rng)
			add(p)
		end
	end
end

-- A square zone. exitX / entryX = door offsets along X (nil = no door).
local function buildZone(folder, biome, rng: Random, index: number, center: Vector3, size: number, entryX: number?, exitX: number?, layout: string)
	local m = NanoKit.Model(folder, ("Zone%d"):format(index))
	m:SetAttribute("Layout", layout)
	local half = size / 2
	local H = G.WallHeight
	local C = G.Corridor
	floorPart(m, center, size, size, biome, "Floor")
	-- walls with door gaps (south = entry, north = exit)
	local sw, se, nw, ne = center + Vector3.new(-half, 0, half), center + Vector3.new(half, 0, half), center + Vector3.new(-half, 0, -half), center + Vector3.new(half, 0, -half)
	wall(m, biome, sw, se, Vector3.new(0, 0, -1), H, if entryX then { { center = entryX + half, width = C.Width } } else nil)
	wall(m, biome, ne, nw, Vector3.new(0, 0, 1), H, if exitX then { { center = half - exitX, width = C.Width } } else nil)
	wall(m, biome, nw, sw, Vector3.new(1, 0, 0), H, nil)
	wall(m, biome, se, ne, Vector3.new(-1, 0, 0), H, nil)
	local exitBarrier
	if exitX then
		local cf = CFrame.lookAt(center + Vector3.new(exitX, 0, -half), center + Vector3.new(exitX, 0, -half - 1))
		doorFrame(m, biome, cf, C.Width, C.Height, nil)
		exitBarrier = barrier(m, cf, C.Width, C.Height, biome.Accent)
	end
	task.wait()
	-- where the section's group stands: the far half, in front of the exit
	local post = center + Vector3.new((exitX or 0) * 0.5, 0, -half * 0.42)
	local blocks = {}
	local function add(p: Vector3)
		table.insert(blocks, p)
	end
	-- keep both door lanes and the post free
	local function free(p: Vector3, r: number): boolean
		for _, d in ipairs({ { entryX, half }, { exitX, -half } }) do
			if d[1] and math.abs(p.X - (center.X + d[1])) < C.Width / 2 + r + 2 and math.abs(p.Z - (center.Z + d[2])) < 20 + r then
				return false
			end
		end
		return Vector3.new(p.X - post.X, 0, p.Z - post.Z).Magnitude > 9 + r
	end
	LAYOUTS[layout](m, biome, rng, center, half, H, free, add)
	task.wait()
	-- the biome's look: its machine set along one side wall
	if layout ~= "Cross" then
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local decorX = center.X + side * (half - 4)
		biomeDecor(m, biome, Vector3.new(decorX, center.Y, center.Z + half - 18), Vector3.new(decorX, center.Y, center.Z - half + 18), side)
	end
	-- tidy storage: crate stacks squared to the walls in two corners
	for _, cx in ipairs({ -1, 1 }) do
		local base = center + Vector3.new(cx * (half - 5), 0, -half + 5)
		if free(base, 3) then
			NanoKit.Crate(m, CFrame.new(base), Vector3.new(4, 4, 4))
			NanoKit.Crate(m, CFrame.new(base + Vector3.new(-cx * 4.4, 0, 0)), Vector3.new(4, 4, 4))
			NanoKit.Crate(m, CFrame.new(base + Vector3.new(0, 4, 0)), Vector3.new(4, 4, 4))
			table.insert(blocks, base)
		end
	end
	-- biome set pieces
	if biome.Theme == "Assembly" or biome.Theme == "Smelter" then
		crane(m, biome, center, half, H, rng)
		if layout ~= "Cross" then
			catwalk(m, biome, center, half, if rng:NextNumber() < 0.5 then -1 else 1)
		end
	elseif biome.Theme == "Crystal" then
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			local p = center + Vector3.new(c[1] * (half - 6), 0, c[2] * (half - 6))
			if free(p, 4) then
				crystalCluster(m, biome, p, 1.8, rng)
			end
		end
	end
	-- light: hanging lamps on a loose grid (pillars carry their own)
	if layout ~= "Pillars" then
		for _, x in ipairs({ -0.4, 0.4 }) do
			for _, z in ipairs({ -0.4, 0.4 }) do
				hangingLamp(m, biome, center + Vector3.new(x * half + rng:NextNumber(-4, 4), 0, z * half + rng:NextNumber(-4, 4)), H)
			end
		end
	end
	roof(m, biome, center, size, size, H)
	m.Parent = folder
	-- trap spots: free floor away from the doors and the post
	local hazards = {}
	local tries = 0
	while #hazards < G.Hazards.Count and tries < 40 do
		tries += 1
		local p = center + Vector3.new(rng:NextNumber(-half * 0.6, half * 0.6), 0, rng:NextNumber(-half * 0.6, half * 0.6))
		local ok = free(p, G.Hazards.Radius)
		for _, b in ipairs(blocks) do
			if Vector3.new(p.X - b.X, 0, p.Z - b.Z).Magnitude < G.Hazards.Radius + 5 then
				ok = false
			end
		end
		for _, h in ipairs(hazards) do
			if (h - p).Magnitude < G.Hazards.Radius * 2.5 then
				ok = false
			end
		end
		if ok then
			table.insert(hazards, p)
			-- the trap's plate: a steel disc with dim marks on the rim (no glowing
			-- arrows on the floor - owner, 23.11)
			local kind = G.Hazards.Kinds[biome.Theme] or G.Hazards.Kinds.Assembly
			local plate = NanoKit.Cylinder(m, "HazardPlate", 0.12, G.Hazards.Radius * 2, CFrame.new(p + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), biome.Metal:Lerp(Color3.new(0, 0, 0), 0.3), M.Plate)
			plate.CanCollide = false
			for k = 0, 7 do
				local a = k / 8 * math.pi * 2
				Panel(m, "HazardMark", Vector3.new(1.2, 0.05, 0.4), CFrame.new(p + Vector3.new(math.cos(a) * (G.Hazards.Radius - 0.8), 0.14, math.sin(a) * (G.Hazards.Radius - 0.8))) * CFrame.Angles(0, -a, 0), kind.Color:Lerp(Color3.new(0, 0, 0), 0.45), M.Smooth, { CanCollide = false, CastShadow = false })
			end
		end
	end
	return {
		Index = index,
		Model = m,
		Center = center,
		Size = size,
		Hazards = hazards,
		Post = post,
		Blocks = blocks,
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
	doorFrame(m, biome, entry, C.Width, C.Height, nil)
	local gate = barrier(m, entry, C.Width, C.Height, Config.DungeonLayout.BossBarrierColor)
	gate.CanCollide = false
	gate.Transparency = 1
	-- rings and the boss platform
	for i, r in ipairs({ 0.82, 0.55, 0.3 }) do
		local disc = NanoKit.Cylinder(m, "ArenaRing", 0.08 + i * 0.01, size * r, CFrame.new(center + Vector3.new(0, 0.04 + i * 0.01, 0)) * CFrame.Angles(0, 0, math.rad(90)), if i % 2 == 1 then biome.Floor:Lerp(Color3.new(0, 0, 0), 0.3) else biome.FloorB, M.Smooth)
		disc.CanCollide = false
	end
	-- thin red glowing rings on the floor (sheet 07 boss arena)
	for i, r in ipairs({ 0.84, 0.57, 0.32, 0.12 }) do
		local ring = size * r / 2
		local n = math.floor(ring * 1.2) + 12
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * math.pi * 2
			Panel(m, "ArenaGlow", Vector3.new(0.35, 0.05, ring * math.pi * 2 / n + 0.05), CFrame.new(center + Vector3.new(math.cos(a) * ring, 0.13 + i * 0.01, math.sin(a) * ring)) * CFrame.Angles(0, -a, 0), Config.DungeonLayout.BossBarrierColor, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.25 })
		end
	end
	-- banners with the crest on the back wall
	for _, x in ipairs({ -0.3, 0.3 }) do
		local p = center + Vector3.new(size * x, H * 0.5, -half + 2)
		Panel(m, "ArenaBanner", Vector3.new(6, 14, 0.2), CFrame.new(p), Color3.fromRGB(60, 22, 34), Enum.Material.Fabric, { CanCollide = false })
		Panel(m, "BannerTrim", Vector3.new(6, 0.4, 0.3), CFrame.new(p + Vector3.new(0, 7, 0.05)), Color3.fromRGB(226, 182, 92), M.Metal, { CanCollide = false })
		Panel(m, "BannerCrest", Vector3.new(1.6, 1.6, 0.1), CFrame.new(p + Vector3.new(0, 2, 0.15)) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(226, 182, 92), M.Neon, { CanCollide = false })
		for _, sx in ipairs({ -1, 1 }) do
			Panel(m, "BannerWing", Vector3.new(2.4, 0.3, 0.1), CFrame.new(p + Vector3.new(sx * 1.6, 1, 0.15)) * CFrame.Angles(0, 0, math.rad(sx * 25)), Color3.fromRGB(226, 182, 92), M.Metal, { CanCollide = false })
		end
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
	local order = table.clone(G.Layouts)
	for i = #order, 2, -1 do -- shuffle (seeded): a location keeps its look
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	-- every room its own size (Config.GateMap.Sizes, seeded)
	local sizes = {}
	for index = 1, #location.Sections do
		sizes[index] = G.Sizes[rng:NextInteger(1, #G.Sizes)]
	end
	size = sizes[1]
	for index = 1, #location.Sections do
		size = sizes[index]
		local exitX = rng:NextInteger(-math.floor(size * 0.28), math.floor(size * 0.28))
		local layout = order[(index - 1) % #order + 1]
		local zone = buildZone(folder, biome, rng, index, center, size, entryX, exitX, layout)
		table.insert(zones, zone)
		-- the next room's door sits right in front of this exit
		local doorOut = center + Vector3.new(exitX, 0, -size / 2)
		local nextSize = if index == #location.Sections then G.BossSize else sizes[index + 1]
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
	local minZ, maxZ = center.Z - G.BossSize, first.Z + sizes[1]
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
