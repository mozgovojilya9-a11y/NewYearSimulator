--[[
	DungeonGenerator.luau
	Builds the 20-room dungeon far from the hub (Workspace.Dungeon) at
	server start. Pure construction: all gameplay rules live in
	DungeonService.

	Layout: corridor -> room -> corridor -> room ... in a straight line
	towards -Z from Config.DungeonLayout.Origin. Room sizes, mob counts
	and spots are random but seeded (Config.Dungeon.Seed), so every
	server builds the same dungeon. Rooms are open-topped brick boxes
	with tiled floors; the exit is a translucent Barrier part carrying
	a SurfaceGui with the enemy counter.
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

local folders = {}

local function biomeFor(room: number)
	return L.Biomes[math.min(#L.Biomes, math.ceil(room / D.BossEvery))]
end

local function pickMobSpots(rng: Random, center: Vector3, size: number, count: number)
	local spots = {}
	local half = size / 2 - 8
	for _ = 1, count do
		local chosen
		for _ = 1, 25 do
			local candidate = center + Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half * 0.7, half * 0.5))
			local ok = true
			for _, other in ipairs(spots) do
				if (other.Position - candidate).Magnitude < 9 then
					ok = false
					break
				end
			end
			chosen = candidate
			if ok then
				break
			end
		end
		table.insert(spots, { Position = chosen, Kind = rng:NextInteger(1, #Config.MobLooks.Kinds) })
	end
	return spots
end

local function corridor(parent, biome, x, zStart, groundY)
	local length = L.CorridorLength
	local width = L.DoorWidth + 4
	local z = zStart - length / 2
	WorldKit.TiledFloor(parent, Vector3.new(x, groundY, z), width, length, L.TileSize, biome.Floor, biome.FloorB, 12)
	local h = L.DoorHeight + 2
	for _, dir in ipairs({ -1, 1 }) do
		local wx = x + dir * (width / 2 + L.WallThickness / 2)
		WorldKit.CastleWall(parent, Vector3.new(wx, groundY, zStart), Vector3.new(wx, groundY, zStart - length), h, L.WallThickness, biome.StoneA, biome.StoneB, 0)
	end
end

-- Barrier text: enemies counter, stage, recommended damage (+ boss line).
local function barrierLines(index, isBoss, total)
	local lines = {
		{ Name = "Enemies", Text = Texts.Enemies:format(0, total), Size = 90 },
		{ Text = Texts.Stage:format(index), Size = 44, Transparency = 0.35 },
		{ Text = Texts.Recommended:format(Format.Number(Config.RecommendedDamage(index))), Size = 26, Transparency = 0.2 },
	}
	if isBoss then
		table.insert(lines, 1, { Text = Texts.Boss, Size = 60, Color = Config.Theme.Magenta })
	end
	return lines
end

local function buildRoom(parent, rng, index, x, zFront, groundY)
	local biome = biomeFor(index)
	local isBoss = Config.IsBossRoom(index)
	local size = if isBoss then math.floor(L.RoomSizeMax * L.BossRoomScale) else rng:NextInteger(L.RoomSizeMin, L.RoomSizeMax)
	local center = Vector3.new(x, groundY, zFront - size / 2)
	local zBack = zFront - size
	local h = L.WallHeight
	local t = L.WallThickness

	local model = Instance.new("Model")
	model.Name = ("Room%02d"):format(index)
	model.Parent = parent

	-- Floor: tiles (capped so the whole room stays under the part budget).
	WorldKit.TiledFloor(model, center, size, size, L.TileSize, biome.Floor, biome.FloorB, 64)

	-- Walls with merlons. Front/back have doorways.
	local half = size / 2 + t / 2
	WorldKit.CastleWall(model, Vector3.new(x - half, groundY, zFront), Vector3.new(x - half, groundY, zBack), h, t, biome.StoneA, biome.StoneB, L.MerlonSize)
	WorldKit.CastleWall(model, Vector3.new(x + half, groundY, zFront), Vector3.new(x + half, groundY, zBack), h, t, biome.StoneA, biome.StoneB, L.MerlonSize)
	local gap = { Center = half, Width = L.DoorWidth }
	WorldKit.CastleWall(model, Vector3.new(x - half, groundY, zFront + t / 2), Vector3.new(x + half, groundY, zFront + t / 2), h, t, biome.StoneA, biome.StoneB, L.MerlonSize, gap)
	local isLast = index == D.Rooms
	WorldKit.CastleWall(model, Vector3.new(x - half, groundY, zBack - t / 2), Vector3.new(x + half, groundY, zBack - t / 2), h, t, biome.StoneA, biome.StoneB, L.MerlonSize, if isLast then nil else gap)
	-- Lintels above the doorways.
	local frontLintel = WorldKit.Brick(model, Vector3.new(L.DoorWidth, h - L.DoorHeight, t), CFrame.new(x, groundY + L.DoorHeight + (h - L.DoorHeight) / 2, zFront + t / 2), biome.StoneB, "Lintel")
	-- Stage number over the entrance, readable from the corridor (+Z side).
	WorldKit.SurfaceText(frontLintel, Enum.NormalId.Back, { { Text = Texts.Entrance:format(index), Size = 56, Color = biome.Accent } }, 30)
	if not isLast then
		WorldKit.Brick(model, Vector3.new(L.DoorWidth, h - L.DoorHeight, t), CFrame.new(x, groundY + L.DoorHeight + (h - L.DoorHeight) / 2, zBack - t / 2), biome.StoneB, "Lintel")
	end


	-- Corner lights in the biome color + neon trim strips on the walls.
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

	local spots
	if isBoss then
		-- Round arena in the middle.
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
		spots = { { Position = center + Vector3.new(0, 1, 0) } }
	else
		spots = pickMobSpots(rng, center, size, rng:NextInteger(D.MobsMin, D.MobsMax))
	end

	-- Exit barrier (none after the last room).
	local barrier
	if not isLast then
		barrier = WorldKit.Part(folders.Barriers, {
			Name = "Barrier" .. index,
			Size = Vector3.new(L.DoorWidth, L.DoorHeight, 1),
			Position = Vector3.new(x, groundY + L.DoorHeight / 2, zBack - t / 2),
			Color = if isBoss then L.BossBarrierColor else biome.Accent,
			Material = Enum.Material.ForceField,
			Transparency = 0.4,
		})
		barrier:SetAttribute("Room", index)
		barrier:SetAttribute("Boss", isBoss)
		barrier:SetAttribute("Total", #spots)
		barrier:SetAttribute("Alive", #spots)
		-- Players approach from +Z, i.e. the part's Back face.
		WorldKit.SurfaceText(barrier, Enum.NormalId.Back, barrierLines(index, isBoss, #spots), 28)
	end

	model:SetAttribute("Room", index)
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("ZFront", zFront)
	model:SetAttribute("ZBack", zBack)

	local entryPosition = Vector3.new(x, groundY + 3, zFront - 6)
	return {
		Index = index,
		IsBoss = isBoss,
		Biome = biome,
		Center = center,
		Size = size,
		Entry = CFrame.lookAt(entryPosition, Vector3.new(x, groundY + 3, center.Z)),
		Barrier = barrier,
		MobSpots = spots,
	}
end

-- Builds the whole dungeon. Returns { Folder, Mobs, Drops, Rooms = { [i] = room } }.
function DungeonGenerator.Build()
	local root = Instance.new("Folder")
	root.Name = "Dungeon"
	for _, name in ipairs({ "Geometry", "Barriers", "Mobs", "Drops" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		folders[name] = folder
	end

	local origin = L.Origin
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	-- A big dark slab under the whole dungeon so nothing falls through
	-- and the Baseplate colour never shows.
	local totalLength = D.Rooms * (L.CorridorLength + L.RoomSizeMax * L.BossRoomScale) + 40
	WorldKit.Part(folders.Geometry, {
		Name = "Bedrock",
		Size = Vector3.new(L.RoomSizeMax * L.BossRoomScale + 60, 4, totalLength),
		Position = Vector3.new(origin.X, groundY - 2.6, origin.Z - totalLength / 2 + 20),
		Color = Color3.fromRGB(20, 14, 32),
		Material = Enum.Material.Slate,
	})

	local rng = Random.new(D.Seed)
	local x = origin.X
	local z = origin.Z

	local rooms = {}
	for index = 1, D.Rooms do
		corridor(folders.Geometry, biomeFor(index), x, z, groundY)
		z -= L.CorridorLength
		local room = buildRoom(folders.Geometry, rng, index, x, z, groundY)
		rooms[index] = room
		z -= room.Size
	end

	root:SetAttribute("GateZ", origin.Z)
	root.Parent = Workspace
	return { Folder = root, Mobs = folders.Mobs, Drops = folders.Drops, Rooms = rooms }
end

return DungeonGenerator
