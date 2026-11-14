--[[
	DungeonGenerator.luau
	Geometry for personal dungeon runs. The room layout (sizes, mob
	spots, kinds) is computed once from Config.Dungeon.Seed and shared by
	every lane; rooms are then instanced on demand per lane
	(Workspace.Dungeon.Lanes.Lane_k) and destroyed when passed, so a run
	only ever holds the current and the next room.

	"Нано-фабрика": closed factory halls (plate floors, concrete panel
	walls with pipes, monitors and lamps, a ceiling with warm lamp rows),
	a conveyor, the biome's machine and owner props; boss rooms are round
	arenas with a column ring and a boss platform. The exit is an energy
	field Barrier with the hologram counter (SurfaceGui). All gameplay
	rules live in DungeonRuns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

local DungeonGenerator = {}

local L = Config.DungeonLayout
local M = NanoKit.Materials
local Panel = NanoKit.Panel
local D = Config.Dungeon
local Texts = L.Texts

local root, lanesFolder
local groundY = 0
local layout = {} -- [index] = { Index, IsBoss, Size, ZFront, ZBack, Spots = { {Offset, Kind} } }

local function biomeFor(room: number)
	return L.Biomes[math.min(#L.Biomes, math.ceil(room / D.BossEvery))]
end
DungeonGenerator.BiomeFor = biomeFor

---------------------------------------------------------------------
-- Seeded layout (shared by all lanes)
---------------------------------------------------------------------

local function pickSpots(rng: Random, size: number, count: number)
	local spots = {}
	local half = size / 2 - 8
	for _ = 1, count do
		local chosen
		for _ = 1, 25 do
			local candidate = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half * 0.7, half * 0.5))
			local ok = true
			for _, other in ipairs(spots) do
				if (other.Offset - candidate).Magnitude < 9 then
					ok = false
					break
				end
			end
			chosen = candidate
			if ok then
				break
			end
		end
		table.insert(spots, { Offset = chosen, Kind = rng:NextInteger(1, Config.MobLooks.KindsPerBiome) })
	end
	return spots
end

local function computeLayout()
	local rng = Random.new(D.Seed)
	local z = L.Origin.Z
	for index = 1, D.Rooms do
		z -= L.CorridorLength
		local isBoss = Config.IsBossRoom(index)
		local size = if isBoss then math.floor(L.RoomSizeMax * L.BossRoomScale) else rng:NextInteger(L.RoomSizeMin, L.RoomSizeMax)
		local spots = if isBoss then { { Offset = Vector3.new(0, 1, size * 0.12), Kind = 1 } } else pickSpots(rng, size, rng:NextInteger(D.MobsMin, D.MobsMax))
		layout[index] = { Index = index, IsBoss = isBoss, Size = size, ZFront = z, ZBack = z - size, Spots = spots }
		z -= size
	end
	return z
end

function DungeonGenerator.Layout(index: number)
	return layout[index]
end

function DungeonGenerator.LaneX(lane: number): number
	return L.Origin.X + (lane - 1) * D.Lanes.Spacing
end

---------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------

local function barrierLines(index, isBoss, total)
	local lines = {
		{ Name = "Enemies", Text = Texts.Enemies:format(0, total), Size = 90 },
		{ Name = "Stage", Text = Texts.Stage:format(index), Size = 44, Color = Config.Theme.Gold },
		{ Name = "Recommended", Text = Texts.Recommended:format(Format.Number(Config.RecommendedDamage(index))), Size = 34 },
	}
	if isBoss then
		table.insert(lines, 1, { Name = "BossLine", Text = Texts.Boss, Size = 60, Color = Config.Theme.Magenta })
	end
	return lines
end

-- Invisible closed box around a rectangle of floor: side walls from below
-- the floor to the ceiling, extended past both ends by Overlap, + ceiling.
-- Door gaps (front/back, along Z) are left open below DoorHeight.
local function boundBox(model: Model, x: number, zFront: number, zBack: number, halfWidth: number, frontDoor: boolean, backDoor: boolean, closeEnds: boolean)
	local B = Config.Bounds
	local t = L.WallThickness
	local height = B.DungeonCeiling + 2
	local y = groundY + height / 2 - 1
	local length = zFront - zBack
	local zMid = (zFront + zBack) / 2
	local bounds = Instance.new("Model")
	bounds.Name = "Bounds"
	bounds.Parent = model
	for _, dir in ipairs({ -1, 1 }) do
		WorldKit.Invisible(bounds, Vector3.new(t, height, length + (t + B.Overlap) * 2), Vector3.new(x + dir * (halfWidth + t / 2), y, zMid))
	end
	WorldKit.Invisible(bounds, Vector3.new((halfWidth + t + B.Overlap) * 2, 2, length + (t + B.Overlap) * 2), Vector3.new(x, groundY + B.DungeonCeiling + 1, zMid), "Ceiling")
	if closeEnds then
		local full = (halfWidth + t + B.Overlap) * 2
		for _, e in ipairs({ { z = zFront + t / 2, door = frontDoor }, { z = zBack - t / 2, door = backDoor } }) do
			if e.door then
				local sideW = full / 2 - L.DoorWidth / 2 + B.Overlap
				for _, dir in ipairs({ -1, 1 }) do
					WorldKit.Invisible(bounds, Vector3.new(sideW, height, t), Vector3.new(x + dir * (L.DoorWidth / 2 - B.Overlap + sideW / 2), y, e.z))
				end
				local above = height - L.DoorHeight
				WorldKit.Invisible(bounds, Vector3.new(L.DoorWidth + 2, above, t), Vector3.new(x, groundY + L.DoorHeight + above / 2 - 1, e.z))
			else
				WorldKit.Invisible(bounds, Vector3.new(full, height, t), Vector3.new(x, y, e.z))
			end
		end
	end
	return bounds
end

---------------------------------------------------------------------
-- Factory kit (walls, ceilings, machinery)
---------------------------------------------------------------------

-- Straight wall from `a` to `b` (ground points, inner face toward
-- `inward`): plates with seams, a pipe run, monitors, wall lamps. A door
-- gap of L.DoorWidth in the middle when `door` is true.
local function factoryWall(parent, biome, a: Vector3, b: Vector3, inward: Vector3, door: boolean)
	local h, t = L.WallHeight, L.WallThickness
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local pieces = {}
	if door then
		local gapStart = length / 2 - L.DoorWidth / 2
		table.insert(pieces, { 0, gapStart })
		table.insert(pieces, { gapStart + L.DoorWidth, length })
	else
		table.insert(pieces, { 0, length })
	end
	for _, piece in ipairs(pieces) do
		local from, to = piece[1], piece[2]
		local segLength = to - from
		local count = math.max(1, math.floor(segLength / 8))
		local seg = segLength / count
		for i = 0, count - 1 do
			local c = a + dir * (from + seg * (i + 0.5))
			local cf = CFrame.lookAt(c + Vector3.new(0, h / 2, 0), c + Vector3.new(0, h / 2, 0) + inward)
			Panel(parent, "WallPanel", Vector3.new(seg - 0.25, h, t), cf * CFrame.new(0, 0, t / 2), if i % 2 == 0 then biome.StoneA else biome.StoneB, M.Concrete)
			Panel(parent, "Seam", Vector3.new(0.5, h, t + 0.3), cf * CFrame.new(seg / 2, 0, t / 2), biome.Metal, M.Metal)
			Panel(parent, "Plinth", Vector3.new(seg, 1.2, 0.5), cf * CFrame.new(0, -h / 2 + 0.6, -0.2), biome.Metal, M.Plate)
		end
		-- pipe run at two heights + an accent line
		local p0, p1 = a + dir * from + inward * 0.6, a + dir * to + inward * 0.6
		for k, y in ipairs({ h * 0.62, h * 0.7 }) do
			local mid = (p0 + p1) / 2 + Vector3.new(0, y, 0)
			NanoKit.Cylinder(parent, "Pipe", segLength, if k == 1 then 0.9 else 0.6, CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, math.rad(90), 0), biome.Metal, M.Metal).CanCollide = false
		end
		NanoKit.Strip(parent, p0 + Vector3.new(0, 1.3, 0) - inward * 0.3, p1 + Vector3.new(0, 1.3, 0) - inward * 0.3, biome.Accent, 0.12)
	end
	-- monitors and wall lamps on the longest piece
	local longest = pieces[1]
	for _, piece in ipairs(pieces) do
		if piece[2] - piece[1] > longest[2] - longest[1] then
			longest = piece
		end
	end
	local span = longest[2] - longest[1]
	if span > 10 then
		for k = 1, L.MonitorsPerWall do
			local c = a + dir * (longest[1] + span * k / (L.MonitorsPerWall + 1)) + inward * 0.35
			local cf = CFrame.lookAt(c + Vector3.new(0, h * 0.4, 0), c + Vector3.new(0, h * 0.4, 0) + inward)
			Panel(parent, "MonitorFrame", Vector3.new(4.2, 2.6, 0.4), cf, biome.Metal, M.Metal)
			local screen = Panel(parent, "Monitor", Vector3.new(3.8, 2.2, 0.1), cf * CFrame.new(0, 0, -0.22), biome.Glow, M.Neon, { CanCollide = false, Transparency = 0.55 })
			NanoKit.Tag(screen, "Flicker")
			NanoKit.Tag(screen, "Pulse", { Period = 3 + k })
			local lampPos = c + dir * (span / (L.MonitorsPerWall + 1) / 2) + Vector3.new(0, h * 0.82, 0)
			local lamp = Panel(parent, "WallLamp", Vector3.new(1.6, 0.5, 0.8), CFrame.lookAt(lampPos, lampPos + inward) * CFrame.new(0, 0, -0.3), biome.Light, M.Neon, { CanCollide = false })
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Color = biome.Light
			light.Range = h + 4
			light.Angle = 100
			light.Brightness = 1.4
			light.Parent = lamp
		end
	end
end

-- Closed ceiling with lamp rows (warm downlights) and a cable or two.
local function factoryCeiling(parent, biome, center: Vector3, width: number, depth: number)
	local h = L.WallHeight
	Panel(parent, "Ceiling", Vector3.new(width + L.WallThickness * 2, 1, depth + L.WallThickness * 2), CFrame.new(center + Vector3.new(0, h + 0.5, 0)), biome.Metal, M.Plate)
	for i = 1, math.floor(width / 10) do
		Panel(parent, "Girder", Vector3.new(1, 1.4, depth), CFrame.new(center + Vector3.new(-width / 2 + i * 10, h - 0.7, 0)), biome.Metal, M.Metal, { CanCollide = false })
	end
	for r = 1, L.LampRows do
		local x = center.X - width / 2 + width * r / (L.LampRows + 1)
		for k = 1, 2 do
			local z = center.Z - depth / 2 + depth * k / 3
			local lamp = Panel(parent, "CeilingLamp", Vector3.new(3, 0.3, 1.4), CFrame.new(x, groundY + h - 1.6, z), biome.Light, M.Neon, { CanCollide = false })
			Panel(parent, "LampHood", Vector3.new(3.6, 0.6, 2), CFrame.new(x, groundY + h - 1.2, z), biome.Metal, M.Metal, { CanCollide = false })
			Panel(parent, "LampRod", Vector3.new(0.2, 1.2, 0.2), CFrame.new(x, groundY + h - 0.4, z), biome.Metal, M.Metal, { CanCollide = false })
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Color = biome.Light
			light.Range = h + 6
			light.Angle = 120
			light.Brightness = 2.2
			light.Shadows = true
			light.Parent = lamp
		end
	end
	NanoKit.Cable(parent, center + Vector3.new(-width / 2 + 2, h - 1, -depth / 2 + 3), center + Vector3.new(width / 2 - 2, h - 1, -depth / 2 + 6), 2.5, biome.Metal)
end

-- Conveyor along one side wall with crates riding on it.
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

-- Owner props (crates, barrels, misc) in the front corners and on the
-- wall opposite the conveyor (`side` = the conveyor's side).
local function scatterProps(parent, center: Vector3, size: number, index: number, side: number)
	local rng = Random.new(D.Seed + index * 31)
	local spots = {
		CFrame.new(center + Vector3.new(-size / 2 + 9, 0, size / 2 - 5)),
		CFrame.new(center + Vector3.new(size / 2 - 9, 0, size / 2 - 5)),
		CFrame.new(center + Vector3.new(-side * (size / 2 - 4), 0, 0)),
	}
	for k, cf in ipairs(spots) do
		local roll = rng:NextInteger(1, 3)
		if roll == 1 then
			NanoKit.CargoStack(parent, cf * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0))
		elseif roll == 2 then
			NanoKit.Barrel(parent, cf)
			NanoKit.Barrel(parent, cf * CFrame.new(2.4, 0, 0.6))
		else
			local name = "Prop_Misc_" .. ((index + k) % 4 + 1)
			local size3 = Assets.Size("Props", name)
			if size3 and size3.Y <= L.WallHeight - 3 and math.max(size3.X, size3.Z) <= 12 then
				NanoKit.Prop(parent, name, cf)
			else
				NanoKit.CargoStack(parent, cf)
			end
		end
	end
end

---------------------------------------------------------------------
-- Corridor, room, boss arena
---------------------------------------------------------------------

function DungeonGenerator.BuildCorridor(parent: Instance, index: number, x: number)
	local biome = biomeFor(index)
	local length = L.CorridorLength
	local width = L.DoorWidth + 4
	local zStart = layout[index].ZFront + length
	local z = zStart - length / 2
	local model = Instance.new("Model")
	model.Name = ("Corridor%02d"):format(index)
	model.Parent = parent
	local center = Vector3.new(x, groundY, z)
	Panel(model, "Floor", Vector3.new(width, 1, length), CFrame.new(center + Vector3.new(0, -0.5, 0)), biome.Floor, M.Plate)
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Strip(model, center + Vector3.new(side * (width / 2 - 1), 0.05, length / 2), center + Vector3.new(side * (width / 2 - 1), 0.05, -length / 2), biome.Accent, 0.16)
		local wx = x + side * (width / 2 + L.WallThickness / 2)
		Panel(model, "Wall", Vector3.new(L.WallThickness, L.DoorHeight + 2, length), CFrame.new(wx, groundY + (L.DoorHeight + 2) / 2, z), biome.StoneB, M.Concrete)
		local mid = Vector3.new(x + side * (width / 2 - 0.5), groundY + L.DoorHeight - 2, z)
		NanoKit.Cylinder(model, "Pipe", length, 0.8, CFrame.lookAt(mid, mid + Vector3.new(0, 0, -1)) * CFrame.Angles(0, math.rad(90), 0), biome.Metal, M.Metal).CanCollide = false
	end
	Panel(model, "Roof", Vector3.new(width + L.WallThickness * 2, 1, length), CFrame.new(x, groundY + L.DoorHeight + 2.5, z), biome.Metal, M.Plate)
	local lamp = Panel(model, "Lamp", Vector3.new(2.4, 0.3, 1.2), CFrame.new(x, groundY + L.DoorHeight + 1.8, z), biome.Light, M.Neon, { CanCollide = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = biome.Light
	light.Range = L.DoorHeight + 6
	light.Angle = 120
	light.Brightness = 1.8
	light.Parent = lamp
	boundBox(model, x, zStart, zStart - length, width / 2, false, false, false)
	return model
end

-- Boss arena: round hall inside the square room, ring of columns, raised
-- boss platform, hologram ring above.
local function bossArena(model, biome, center: Vector3, size: number)
	local r = size * 0.42
	local flat = CFrame.Angles(0, 0, math.rad(90))
	NanoKit.Cylinder(model, "ArenaFloor", 0.3, r * 2, CFrame.new(center + Vector3.new(0, 0.15, 0)) * flat, biome.FloorB, M.Plate)
	NanoKit.Cylinder(model, "ArenaRing", 0.08, r * 2 - 1, CFrame.new(center + Vector3.new(0, 0.32, 0)) * flat, L.BossBarrierColor, M.Neon).CanCollide = false
	NanoKit.Cylinder(model, "ArenaInner", 0.1, r * 2 - 1.8, CFrame.new(center + Vector3.new(0, 0.35, 0)) * flat, biome.FloorB, M.Plate).CanCollide = false
	-- boss platform
	NanoKit.Cylinder(model, "BossPlatform", 1.2, size * 0.28, CFrame.new(center + Vector3.new(0, 0.6, size * 0.12)) * flat, biome.Metal, M.Metal)
	NanoKit.Cylinder(model, "BossPlatformGlow", 0.1, size * 0.28 - 0.6, CFrame.new(center + Vector3.new(0, 1.22, size * 0.12)) * flat, biome.Glow, M.Neon).CanCollide = false
	-- ring of columns with glowing caps
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local p = center + Vector3.new(math.cos(angle) * (r + 2), 0, math.sin(angle) * (r + 2))
		NanoKit.Column(model, "ArenaColumn", L.WallHeight, 2.2, p, biome.Metal, M.Metal)
		NanoKit.Column(model, "ColumnBand", 0.4, 2.4, p + Vector3.new(0, 3, 0), biome.Accent, M.Neon).CanCollide = false
		local cap = NanoKit.Column(model, "ColumnCap", 1, 2.8, p + Vector3.new(0, L.WallHeight - 3, 0), L.BossBarrierColor, M.Neon)
		cap.CanCollide = false
		WorldKit.Light(cap, L.BossBarrierColor, 16, 0.8)
	end
	-- hologram ring above the platform
	local holo = NanoKit.Cylinder(model, "HoloRing", 0.3, size * 0.32, CFrame.new(center + Vector3.new(0, L.WallHeight - 3.5, size * 0.12)) * flat, L.BossBarrierColor, M.Neon)
	holo.CanCollide = false
	holo.Transparency = 0.4
	NanoKit.Tag(holo, "Spin", { Speed = 30, Axis = "Y" })
end

-- Builds room `index` for a lane at x. Returns room info.
function DungeonGenerator.BuildRoom(parent: Instance, index: number, x: number)
	local info = layout[index]
	local biome = biomeFor(index)
	local isBoss = info.IsBoss
	local size = info.Size
	local zFront, zBack = info.ZFront, info.ZBack
	local center = Vector3.new(x, groundY, zFront - size / 2)
	local h = L.WallHeight
	local t = L.WallThickness

	local model = Instance.new("Model")
	model.Name = ("Room%02d"):format(index)
	model.Parent = parent

	NanoKit.Floor(model, center, size, size, math.max(8, size / 6), biome.Floor, biome.FloorB, M.Plate)
	-- guide line from the entrance to the exit
	NanoKit.Strip(model, Vector3.new(x, groundY + 0.06, zFront - 1), Vector3.new(x, groundY + 0.06, zBack + 1), biome.Accent, 0.22)

	local half = size / 2
	local isLast = index == D.Rooms
	factoryWall(model, biome, Vector3.new(x - half, groundY, zFront), Vector3.new(x - half, groundY, zBack), Vector3.new(1, 0, 0), false)
	factoryWall(model, biome, Vector3.new(x + half, groundY, zBack), Vector3.new(x + half, groundY, zFront), Vector3.new(-1, 0, 0), false)
	factoryWall(model, biome, Vector3.new(x + half, groundY, zFront), Vector3.new(x - half, groundY, zFront), Vector3.new(0, 0, -1), true)
	factoryWall(model, biome, Vector3.new(x - half, groundY, zBack), Vector3.new(x + half, groundY, zBack), Vector3.new(0, 0, 1), not isLast)
	-- door frames with the stage number over the entrance
	local frontLintel = Panel(model, "Lintel", Vector3.new(L.DoorWidth, h - L.DoorHeight, t), CFrame.new(x, groundY + L.DoorHeight + (h - L.DoorHeight) / 2, zFront + t / 2), biome.Metal, M.Metal)
	WorldKit.SurfaceText(frontLintel, Enum.NormalId.Back, { { Text = Texts.Entrance:format(index), Size = 56, Color = biome.Accent } }, 50)
	for _, z in ipairs({ zFront + t / 2, zBack - t / 2 }) do
		if z == zFront + t / 2 or not isLast then
			for _, side in ipairs({ -1, 1 }) do
				Panel(model, "DoorFrame", Vector3.new(1, L.DoorHeight, t + 0.6), CFrame.new(x + side * (L.DoorWidth / 2 + 0.5), groundY + L.DoorHeight / 2, z), biome.Metal, M.Metal)
				NanoKit.Strip(model, Vector3.new(x + side * L.DoorWidth / 2, groundY + 0.3, z), Vector3.new(x + side * L.DoorWidth / 2, groundY + L.DoorHeight - 0.3, z), if isBoss then L.BossBarrierColor else biome.Accent, 0.18)
			end
		end
	end
	if not isLast then
		Panel(model, "Lintel", Vector3.new(L.DoorWidth, h - L.DoorHeight, t), CFrame.new(x, groundY + L.DoorHeight + (h - L.DoorHeight) / 2, zBack - t / 2), biome.Metal, M.Metal)
	end
	if L.Ceiling then
		factoryCeiling(model, biome, center, size, size)
	end

	if isBoss then
		bossArena(model, biome, center, size)
	else
		-- machinery: conveyor on one side, the biome machine in a corner,
		-- owner props along the walls
		local side = if index % 2 == 0 then 1 else -1
		conveyor(model, biome, Vector3.new(x + side * (half - 4), groundY, zFront - 6), Vector3.new(x + side * (half - 4), groundY, zBack + 10))
		machine(model, biome, CFrame.new(Vector3.new(x - side * (half - 6), groundY, zBack + 7)))
		scatterProps(model, center, size, index, side)
	end

	-- The barrier: an energy field in the exit doorway with the hologram
	-- "0/3 врагов · Этап N · Рекомендовано: X" (DungeonRuns updates it).
	local barrier
	if not isLast then
		barrier = WorldKit.Part(model, {
			Name = "Barrier",
			Size = Vector3.new(L.DoorWidth, L.DoorHeight, 1),
			Position = Vector3.new(x, groundY + L.DoorHeight / 2, zBack - t / 2),
			Color = if isBoss then L.BossBarrierColor else biome.Accent,
			Material = Enum.Material.ForceField,
			Transparency = 0.25,
			CastShadow = false,
		})
		barrier:SetAttribute("Room", index)
		WorldKit.SurfaceText(barrier, Enum.NormalId.Back, barrierLines(index, isBoss, #info.Spots), 50)
		WorldKit.Light(barrier, if isBoss then L.BossBarrierColor else biome.Accent, 18, 1)
	end

	-- Bounds: closed invisible box + the seal of the entrance doorway
	-- (on from the start in room 1, switched on when the room behind is
	-- removed: DungeonGenerator.Seal).
	boundBox(model, x, zFront, zBack, size / 2, true, not isLast, true)
	local seal = WorldKit.Part(model, {
		Name = "FrontSeal",
		Size = Vector3.new(L.DoorWidth + 2, L.DoorHeight + 1, 2),
		Position = Vector3.new(x, groundY + (L.DoorHeight + 1) / 2 - 0.5, zFront + t / 2),
		Color = biome.Metal,
		Material = M.Plate,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})

	model:SetAttribute("Room", index)
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("X", x)
	model:SetAttribute("Size", size)
	model:SetAttribute("ZFront", zFront)
	model:SetAttribute("ZBack", zBack)

	local entryPosition = Vector3.new(x, groundY + 3, zFront - 6)
	local spots = {}
	for _, spot in ipairs(info.Spots) do
		local position = center + spot.Offset
		if isBoss then
			position += Vector3.new(0, 0.2, 0) -- on top of the boss platform (1.2 high)
		end
		table.insert(spots, { Position = position, Kind = spot.Kind })
	end
	return {
		Index = index,
		IsBoss = isBoss,
		Biome = biome,
		Center = center,
		Size = size,
		Entry = CFrame.lookAt(entryPosition, Vector3.new(x, groundY + 3, center.Z)),
		Barrier = barrier,
		Seal = seal,
		ZFront = zFront,
		ZBack = zBack,
		Model = model,
		MobSpots = spots,
	}
end

-- Closes the entrance doorway of a room for good (brick plug).
function DungeonGenerator.Seal(room)
	local seal = room.Seal
	if seal and seal.Parent then
		seal.Transparency = 0
		seal.CanCollide = true
	end
end

-- Folder for a lane (created on demand).
function DungeonGenerator.LaneFolder(lane: number): Folder
	local name = "Lane_" .. lane
	local folder = lanesFolder:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = lanesFolder
	end
	return folder
end

-- Creates the Dungeon root, bedrock under every lane and the layout.
function DungeonGenerator.Init()
	root = Instance.new("Folder")
	root.Name = "Dungeon"
	lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = root

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0

	local zEnd = computeLayout()
	local totalLength = L.Origin.Z - zEnd + 40
	local totalWidth = D.Lanes.Max * D.Lanes.Spacing
	WorldKit.Part(root, {
		Name = "Bedrock",
		Size = Vector3.new(totalWidth, 4, totalLength),
		Position = Vector3.new(L.Origin.X + totalWidth / 2 - D.Lanes.Spacing / 2, groundY - 2.6, L.Origin.Z - totalLength / 2 + 20),
		Color = Color3.fromRGB(20, 14, 32),
		Material = Enum.Material.Slate,
	})

	root:SetAttribute("GateZ", L.Origin.Z)
	root.Parent = Workspace
	return { Folder = root, Lanes = lanesFolder }
end

function DungeonGenerator.GroundY(): number
	return groundY
end

return DungeonGenerator
