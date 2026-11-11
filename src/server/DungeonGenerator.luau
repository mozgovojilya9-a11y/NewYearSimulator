--[[
	DungeonGenerator.luau
	Builds the 20-room dungeon out of Parts at server start
	(Workspace.Dungeon) and builds mob models on request. Pure
	construction: all gameplay rules live in DungeonService.

	Layout: a gate near the hub, then corridor -> room -> corridor ->
	room ... in a straight line towards -Z. Room sizes, mob counts,
	mob spots and mob looks are random but seeded (Config.Dungeon.Seed),
	so every server builds the same dungeon.

	Every room except the last has an exit Door part (attribute Room=r).
	The server keeps doors solid; each client opens the doors of rooms
	that player has cleared (see client Dungeon.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldKit = require(script.Parent.WorldKit)

local DungeonGenerator = {}

local D = Config.Dungeon
local WALL = 2 -- wall thickness

local folders = {}

local function themeFor(room: number)
	return D.Themes[math.min(#D.Themes, math.ceil(room / D.BossEvery))]
end

local function wall(parent, theme, size: Vector3, position: Vector3)
	return WorldKit.Part(parent, {
		Name = "Wall",
		Size = size,
		Position = position,
		Color = theme.Wall,
		Material = theme.Material,
	})
end

-- A wall across the X axis at z, with an optional doorway in the middle.
local function crossWall(parent, theme, centerX, width, z, groundY, withDoorway)
	local h = D.WallHeight
	if not withDoorway then
		wall(parent, theme, Vector3.new(width, h, WALL), Vector3.new(centerX, groundY + h / 2, z))
		return
	end
	local side = (width - D.DoorWidth) / 2
	for _, dir in ipairs({ -1, 1 }) do
		wall(parent, theme, Vector3.new(side, h, WALL), Vector3.new(centerX + dir * (D.DoorWidth / 2 + side / 2), groundY + h / 2, z))
	end
	local lintel = h - D.DoorHeight
	wall(parent, theme, Vector3.new(D.DoorWidth, lintel, WALL), Vector3.new(centerX, groundY + D.DoorHeight + lintel / 2, z))
end

local function corridor(parent, theme, x, zStart, groundY)
	local length = D.CorridorLength
	local width = D.DoorWidth + 4
	local z = zStart - length / 2
	WorldKit.Part(parent, {
		Name = "CorridorFloor",
		Size = Vector3.new(width, 1, length),
		Position = Vector3.new(x, groundY - 0.3, z),
		Color = theme.Floor,
		Material = theme.Material,
	})
	local h = D.DoorHeight + 2
	for _, dir in ipairs({ -1, 1 }) do
		wall(parent, theme, Vector3.new(WALL, h, length), Vector3.new(x + dir * (width / 2 + WALL / 2), groundY + h / 2, z))
	end
end

local function torch(parent, theme, position)
	local flame = WorldKit.Part(parent, {
		Name = "Torch",
		Size = Vector3.new(1, 1.6, 1),
		Position = position,
		Color = theme.Light,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	WorldKit.Light(flame, theme.Light, 22, 1.4)
end

local function pickMobSpots(rng: Random, center: Vector3, size: number, count: number)
	local spots = {}
	local half = size / 2 - 8
	for _ = 1, count do
		local chosen
		for _ = 1, 25 do
			local candidate = center + Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half * 0.6))
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
		table.insert(spots, { Position = chosen, Kind = rng:NextInteger(1, #D.MobKinds) })
	end
	return spots
end

local function buildRoom(parent, rng, index, x, zFront, groundY)
	local theme = themeFor(index)
	local isBoss = Config.IsBossRoom(index)
	local size = if isBoss then D.RoomSizeMax else rng:NextInteger(D.RoomSizeMin, D.RoomSizeMax)
	local center = Vector3.new(x, groundY, zFront - size / 2)
	local zBack = zFront - size

	local model = Instance.new("Model")
	model.Name = ("Room%02d"):format(index)
	model.Parent = parent

	WorldKit.Part(model, {
		Name = "Floor",
		Size = Vector3.new(size, 1, size),
		Position = Vector3.new(x, groundY - 0.3, center.Z),
		Color = theme.Floor,
		Material = theme.Material,
	})

	local h = D.WallHeight
	for _, dir in ipairs({ -1, 1 }) do
		wall(model, theme, Vector3.new(WALL, h, size + WALL * 2), Vector3.new(x + dir * (size / 2 + WALL / 2), groundY + h / 2, center.Z))
	end
	crossWall(model, theme, x, size + WALL * 2, zFront + WALL / 2, groundY, true)

	local isLast = index == D.Rooms
	crossWall(model, theme, x, size + WALL * 2, zBack - WALL / 2, groundY, not isLast)

	local door
	if not isLast then
		door = WorldKit.Part(folders.Doors, {
			Name = "Door" .. index,
			Size = Vector3.new(D.DoorWidth, D.DoorHeight, 1.5),
			Position = Vector3.new(x, groundY + D.DoorHeight / 2, zBack - WALL / 2),
			Color = theme.Light,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		})
		door:SetAttribute("Room", index)
		-- The sign lives inside the door so the client hides both together.
		WorldKit.Sign(door, door.Position + Vector3.new(0, 0, 1.5), "🔒 Убей всех мобов", Color3.fromRGB(255, 120, 120), 260)
	end

	-- Corner torches.
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			torch(model, theme, Vector3.new(x + dx * (size / 2 - 1.5), groundY + 8, center.Z + dz * (size / 2 - 1.5)))
		end
	end

	local title = if isBoss
		then ("Комната %d — БОСС"):format(index)
		else ("Комната %d • %s"):format(index, theme.Name)
	WorldKit.Sign(model, Vector3.new(x, groundY + h + 4, zFront + 2), title, if isBoss then Color3.fromRGB(255, 205, 70) else nil, 360)

	local spots
	if isBoss then
		WorldKit.Part(model, {
			Name = "BossCircle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 26, 26),
			CFrame = CFrame.new(x, groundY + 0.25, center.Z - size * 0.12) * CFrame.Angles(0, 0, math.rad(90)),
			Color = theme.Light,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
			CanCollide = false,
			CanQuery = false,
		})
		spots = { { Position = Vector3.new(x, groundY, center.Z - size * 0.12) } }
	else
		spots = pickMobSpots(rng, center, size, rng:NextInteger(D.MobsMin, D.MobsMax))
	end

	local entryPosition = Vector3.new(x, groundY + 3, zFront - 6)
	return {
		Index = index,
		IsBoss = isBoss,
		Center = center,
		Size = size,
		Entry = CFrame.lookAt(entryPosition, Vector3.new(x, groundY + 3, center.Z)),
		Door = door,
		MobSpots = spots,
	}
end

-- Builds the whole dungeon. Returns { Folder, Mobs, Rooms = { [i] = room } }.
function DungeonGenerator.Build()
	local root = Instance.new("Folder")
	root.Name = "Dungeon"
	for _, name in ipairs({ "Geometry", "Doors", "Mobs" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		folders[name] = folder
	end

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y - spawn.Size.Y / 2 else 0

	local rng = Random.new(D.Seed)
	local x = origin.X
	local z = origin.Z - D.StartOffset

	-- Gate from the hub.
	local gateTheme = D.Themes[1]
	crossWall(folders.Geometry, gateTheme, x, D.DoorWidth + 12, z, groundY, true)
	WorldKit.Sign(folders.Geometry, Vector3.new(x, groundY + D.WallHeight + 4, z + 2), "⚔ ДАНЖ ⚔", Color3.fromRGB(255, 120, 90), 260)
	torch(folders.Geometry, gateTheme, Vector3.new(x - D.DoorWidth / 2 - 2, groundY + 8, z + 2))
	torch(folders.Geometry, gateTheme, Vector3.new(x + D.DoorWidth / 2 + 2, groundY + 8, z + 2))

	local rooms = {}
	for index = 1, D.Rooms do
		corridor(folders.Geometry, themeFor(index), x, z, groundY)
		z -= D.CorridorLength
		local room = buildRoom(folders.Geometry, rng, index, x, z, groundY)
		rooms[index] = room
		z -= room.Size
	end

	root.Parent = Workspace
	return { Folder = root, Mobs = folders.Mobs, Rooms = rooms }
end

-- Builds one mob for a room spot and parents it to Dungeon.Mobs.
-- Health lives in its Humanoid; attributes carry Room/Boss/Reward.
function DungeonGenerator.BuildMob(room, spot)
	local isBoss = room.IsBoss
	local look = if isBoss then D.Bosses[room.Index] else D.MobKinds[spot.Kind]
	local size = look.Size * (if isBoss then D.BossScale else 1)
	local health = Config.MobHealth(room.Index, isBoss)

	local position = spot.Position + Vector3.new(0, size.Y / 2 + 0.2, 0)
	local facing = Vector3.new(room.Entry.Position.X, position.Y, room.Entry.Position.Z)

	local model = Instance.new("Model")
	model.Name = look.Name

	local body = WorldKit.Part(model, {
		Name = "HumanoidRootPart",
		Size = size,
		CFrame = CFrame.lookAt(position, facing),
		Color = look.Color,
	})
	if look.Shape == "Ball" then
		body.Shape = Enum.PartType.Ball
	end
	model.PrimaryPart = body
	WorldKit.Eyes(model, body)

	if isBoss then
		local crown = WorldKit.Part(model, {
			Name = "Crown",
			Size = Vector3.new(size.X * 0.6, size.Y * 0.15, size.Z * 0.6),
			CFrame = body.CFrame * CFrame.new(0, size.Y / 2 + size.Y * 0.075, 0),
			Color = Color3.fromRGB(255, 205, 70),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		WorldKit.Light(crown, look.Color, 30, 2)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	model:SetAttribute("Room", room.Index)
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("Reward", Config.MobReward(room.Index, isBoss))

	WorldKit.HealthGui(body, if isBoss then "БОСС: " .. look.Name else look.Name, size.Y, isBoss)
	WorldKit.UpdateHealth(body, health, health)

	model.Parent = folders.Mobs
	return model
end

return DungeonGenerator
