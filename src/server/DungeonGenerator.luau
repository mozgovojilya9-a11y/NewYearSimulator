--[[
	DungeonGenerator.luau
	Geometry for personal dungeon runs. The room layout (sizes, mob
	spots, kinds) is computed once from Config.Dungeon.Seed and shared by
	every lane; rooms are then instanced on demand per lane
	(Workspace.Dungeon.Lanes.Lane_k) and destroyed when passed, so a run
	only ever holds the current and the next room.

	Rooms are open-top brick boxes with tiled floors; the exit is a
	translucent Barrier part carrying a SurfaceGui with the enemy counter.
	All gameplay rules live in DungeonRuns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local WorldKit = require(script.Parent.WorldKit)

local DungeonGenerator = {}

local L = Config.DungeonLayout
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
		table.insert(spots, { Offset = chosen, Kind = rng:NextInteger(1, #Config.MobLooks.Kinds) })
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
		{ Name = "Stage", Text = Texts.Stage:format(index), Size = 44, Transparency = 0.35 },
		{ Name = "Recommended", Text = Texts.Recommended:format(Format.Number(Config.RecommendedDamage(index))), Size = 26, Transparency = 0.2 },
	}
	if isBoss then
		table.insert(lines, 1, { Name = "BossLine", Text = Texts.Boss, Size = 60, Color = Config.Theme.Magenta })
	end
	return lines
end

function DungeonGenerator.BuildCorridor(parent: Instance, index: number, x: number)
	local biome = biomeFor(index)
	local length = L.CorridorLength
	local width = L.DoorWidth + 4
	local zStart = layout[index].ZFront + length
	local z = zStart - length / 2
	local model = Instance.new("Model")
	model.Name = ("Corridor%02d"):format(index)
	model.Parent = parent
	WorldKit.TiledFloor(model, Vector3.new(x, groundY, z), width, length, L.TileSize, biome.Floor, biome.FloorB, 12)
	local h = L.DoorHeight + 2
	for _, dir in ipairs({ -1, 1 }) do
		local wx = x + dir * (width / 2 + L.WallThickness / 2)
		WorldKit.CastleWall(model, Vector3.new(wx, groundY, zStart), Vector3.new(wx, groundY, zStart - length), h, L.WallThickness, biome.StoneA, biome.StoneB, 0)
	end
	return model
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

	WorldKit.TiledFloor(model, center, size, size, L.TileSize, biome.Floor, biome.FloorB, 64)

	local half = size / 2 + t / 2
	WorldKit.CastleWall(model, Vector3.new(x - half, groundY, zFront), Vector3.new(x - half, groundY, zBack), h, t, biome.StoneA, biome.StoneB, L.MerlonSize)
	WorldKit.CastleWall(model, Vector3.new(x + half, groundY, zFront), Vector3.new(x + half, groundY, zBack), h, t, biome.StoneA, biome.StoneB, L.MerlonSize)
	local gap = { Center = half, Width = L.DoorWidth }
	WorldKit.CastleWall(model, Vector3.new(x - half, groundY, zFront + t / 2), Vector3.new(x + half, groundY, zFront + t / 2), h, t, biome.StoneA, biome.StoneB, L.MerlonSize, gap)
	local isLast = index == D.Rooms
	WorldKit.CastleWall(model, Vector3.new(x - half, groundY, zBack - t / 2), Vector3.new(x + half, groundY, zBack - t / 2), h, t, biome.StoneA, biome.StoneB, L.MerlonSize, if isLast then nil else gap)
	local frontLintel = WorldKit.Brick(model, Vector3.new(L.DoorWidth, h - L.DoorHeight, t), CFrame.new(x, groundY + L.DoorHeight + (h - L.DoorHeight) / 2, zFront + t / 2), biome.StoneB, "Lintel")
	WorldKit.SurfaceText(frontLintel, Enum.NormalId.Back, { { Text = Texts.Entrance:format(index), Size = 56, Color = biome.Accent } }, 50)
	if not isLast then
		WorldKit.Brick(model, Vector3.new(L.DoorWidth, h - L.DoorHeight, t), CFrame.new(x, groundY + L.DoorHeight + (h - L.DoorHeight) / 2, zBack - t / 2), biome.StoneB, "Lintel")
	end

	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			local lamp = WorldKit.Part(model, {
				Name = "Lamp",
				Size = Vector3.new(1, 1, 1),
				Position = Vector3.new(x + dx * (size / 2 - 1.5), groundY + h * 0.6, center.Z + dz * (size / 2 - 1.5)),
				Color = biome.Light,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			WorldKit.Light(lamp, biome.Light, size * 0.8, 1.2)
		end
		WorldKit.Part(model, {
			Name = "Trim",
			Size = Vector3.new(0.25, 0.25, size),
			Position = Vector3.new(x + dx * (size / 2 - 0.1), groundY + 2.2, center.Z),
			Color = biome.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end

	if isBoss then
		local arenaR = size * 0.28
		WorldKit.Part(model, {
			Name = "Arena",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, arenaR * 2, arenaR * 2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = biome.StoneA,
			Material = Enum.Material.Plastic,
			TopSurface = Enum.SurfaceType.Studs,
		})
		WorldKit.Part(model, {
			Name = "ArenaRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, arenaR * 2 + 2, arenaR * 2 + 2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = L.BossBarrierColor,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanCollide = false,
			CanQuery = false,
		})
		for i = 0, 5 do
			local angle = i * math.pi / 3
			WorldKit.Brick(model, Vector3.new(2.5, 9, 2.5), CFrame.new(center + Vector3.new(math.cos(angle) * (arenaR + 4), 4.5, math.sin(angle) * (arenaR + 4))), biome.StoneB, "Pillar")
		end
	end

	local barrier
	if not isLast then
		barrier = WorldKit.Part(model, {
			Name = "Barrier",
			Size = Vector3.new(L.DoorWidth, L.DoorHeight, 1),
			Position = Vector3.new(x, groundY + L.DoorHeight / 2, zBack - t / 2),
			Color = if isBoss then L.BossBarrierColor else biome.Accent,
			Material = Enum.Material.ForceField,
			Transparency = 0.4,
		})
		barrier:SetAttribute("Room", index)
		WorldKit.SurfaceText(barrier, Enum.NormalId.Back, barrierLines(index, isBoss, #info.Spots), 50)
	end

	model:SetAttribute("Room", index)
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("X", x)
	model:SetAttribute("Size", size)
	model:SetAttribute("ZFront", zFront)
	model:SetAttribute("ZBack", zBack)

	local entryPosition = Vector3.new(x, groundY + 3, zFront - 6)
	local spots = {}
	for _, spot in ipairs(info.Spots) do
		table.insert(spots, { Position = center + spot.Offset, Kind = spot.Kind })
	end
	return {
		Index = index,
		IsBoss = isBoss,
		Biome = biome,
		Center = center,
		Size = size,
		Entry = CFrame.lookAt(entryPosition, Vector3.new(x, groundY + 3, center.Z)),
		Barrier = barrier,
		Model = model,
		MobSpots = spots,
	}
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
