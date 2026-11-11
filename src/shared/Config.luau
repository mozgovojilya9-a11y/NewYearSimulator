--[[
	Config.luau
	Shared, read-only game configuration. EVERY balance number and
	layout constant lives here; server and client logic only read it.
	It contains no secrets (the client can see it).
]]

local Config = {}

Config.DataStoreName = "AuraClicker_v1"

-- Default data for a brand-new player. DataService backfills any
-- fields missing from an older save, so new fields can be added here
-- safely. IDs stored in saves (weapons, backpacks, pets) must never be
-- renamed without a migration.
Config.StartingData = {
	Aura = 0,
	Rebirths = 0,
	EquippedWeapon = "Stick",
	OwnedWeapons = { Stick = true },
	OwnedBackpacks = {},
	EquippedBackpack = "",
	OwnedPets = {},
	EquippedPet = "",
	RoomReached = 0, -- highest dungeon room cleared (0 = none, 20 = all)
	LastSeen = 0, -- os.time() of the last save, used for offline income
}

-- Autosave interval (seconds) as a safety net in addition to
-- save-on-leave.
Config.AutosaveInterval = 120

---------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------

Config.Click = {
	BaseDamage = 1, -- damage of one click with weapon x1
	CritChance = 0.1, -- 10% chance per click
	CritMultiplier = 5, -- crit = damage x5
	Cooldown = 0.1, -- min seconds between accepted clicks per player (anti-macro)
	Range = 60, -- max studs between player and target
}

---------------------------------------------------------------------
-- Hub (room 0)
---------------------------------------------------------------------

-- All positions are offsets from the SpawnLocation. The dungeon
-- entrance is in the -Z direction.
Config.Hub = {
	FloorRadius = 46,
	TrainerRate = 0.25, -- trainer click gives ClickPower x this (mobs give much more)
	Trainers = {
		Vector3.new(26, 0, -8),
		Vector3.new(26, 0, 4),
		Vector3.new(26, 0, 16),
	},
	-- One pedestal per unique weapon, in Config.Weapons order (Unique = true).
	Stands = {
		Vector3.new(-26, 0, -8),
		Vector3.new(-26, 0, 4),
		Vector3.new(-26, 0, 16),
	},
	Altar = Vector3.new(0, 0, 30),
	StandSpinSeconds = 4, -- one full turn of the weapon on its pedestal
}

---------------------------------------------------------------------
-- Dungeon
---------------------------------------------------------------------

Config.Dungeon = {
	Rooms = 20,
	BossEvery = 5, -- rooms 5, 10, 15, 20
	Seed = 2026, -- same layout on every server

	StartOffset = 50, -- studs from the SpawnLocation to the dungeon gate (towards -Z)
	RoomSizeMin = 46,
	RoomSizeMax = 60,
	WallHeight = 18,
	DoorWidth = 14,
	DoorHeight = 12,
	CorridorLength = 18,

	MobsMin = 3,
	MobsMax = 5,

	-- Normal mob HP in room r = BaseHealth * HealthGrowth^(r-1).
	BaseHealth = 6,
	HealthGrowth = 1.45,
	RewardPerHealth = 2, -- Aura per kill = HP x this
	BossHealthMultiplier = 15,
	BossRewardMultiplier = 1.5, -- on top of RewardPerHealth
	BossScale = 2.3,

	RoomRespawnDelay = 6, -- seconds after a room is cleared before its mobs return
	BossRespawnDelay = 20,

	-- Every boss kill rolls these in order; the first unowned pet that
	-- hits is given to each player who damaged the boss.
	BossPetDrops = {
		{ PetId = "Spark", Chance = 0.25 },
		{ PetId = "Dragon", Chance = 0.05 },
	},

	-- One theme per 5 rooms.
	Themes = {
		{ Name = "Каменные залы", Floor = Color3.fromRGB(95, 95, 105), Wall = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Slate, Light = Color3.fromRGB(255, 190, 120) },
		{ Name = "Ледяные пещеры", Floor = Color3.fromRGB(170, 215, 240), Wall = Color3.fromRGB(120, 175, 220), Material = Enum.Material.Ice, Light = Color3.fromRGB(150, 220, 255) },
		{ Name = "Огненные недра", Floor = Color3.fromRGB(70, 40, 35), Wall = Color3.fromRGB(110, 45, 30), Material = Enum.Material.Basalt, Light = Color3.fromRGB(255, 110, 50) },
		{ Name = "Бездна Ауры", Floor = Color3.fromRGB(40, 25, 60), Wall = Color3.fromRGB(70, 40, 110), Material = Enum.Material.Marble, Light = Color3.fromRGB(190, 110, 255) },
	},

	-- Looks of normal mobs (picked randomly per spot).
	MobKinds = {
		{ Name = "Слизень", Size = Vector3.new(4, 4, 4), Shape = "Ball", Color = Color3.fromRGB(110, 230, 120) },
		{ Name = "Гоблин", Size = Vector3.new(3, 5, 3), Color = Color3.fromRGB(150, 120, 70) },
		{ Name = "Скелет", Size = Vector3.new(3, 6, 3), Color = Color3.fromRGB(225, 220, 200) },
		{ Name = "Тень", Size = Vector3.new(4, 7, 4), Color = Color3.fromRGB(70, 50, 110) },
	},

	Bosses = {
		[5] = { Name = "Каменный Голем", Size = Vector3.new(5, 6, 5), Color = Color3.fromRGB(120, 120, 130) },
		[10] = { Name = "Ледяной Страж", Size = Vector3.new(5, 6, 5), Color = Color3.fromRGB(140, 210, 255) },
		[15] = { Name = "Огненный Владыка", Size = Vector3.new(5, 6, 5), Color = Color3.fromRGB(255, 100, 40) },
		[20] = { Name = "Повелитель Пустоты", Size = Vector3.new(5, 6, 5), Color = Color3.fromRGB(170, 90, 255) },
	},
}

function Config.IsBossRoom(room: number): boolean
	return room % Config.Dungeon.BossEvery == 0
end

function Config.MobHealth(room: number, isBoss: boolean): number
	local d = Config.Dungeon
	local health = d.BaseHealth * d.HealthGrowth ^ (room - 1)
	if isBoss then
		health *= d.BossHealthMultiplier
	end
	return math.floor(health)
end

function Config.MobReward(room: number, isBoss: boolean): number
	local d = Config.Dungeon
	local reward = Config.MobHealth(room, isBoss) * d.RewardPerHealth
	if isBoss then
		reward *= d.BossRewardMultiplier
	end
	return math.floor(reward)
end

---------------------------------------------------------------------
-- Items. IDs are saved in player data: never rename them.
---------------------------------------------------------------------

-- Weapons: Damage multiplies click power. Unique weapons are bought
-- only at the hub stand (ProximityPrompt), the rest in the shop.
-- One weapon is active at a time.
Config.Weapons = {
	{ Id = "Stick", Name = "Палка", Damage = 1, Cost = 0, Color = Color3.fromRGB(150, 110, 70) },
	{ Id = "WoodSword", Name = "Деревянный меч", Damage = 3, Cost = 100, Color = Color3.fromRGB(200, 150, 90) },
	{ Id = "IronSword", Name = "Железный меч", Damage = 10, Cost = 1200, Color = Color3.fromRGB(190, 200, 215) },
	{ Id = "AuraKatana", Name = "Катана Ауры", Damage = 35, Cost = 12000, Color = Color3.fromRGB(190, 110, 255) },
	{ Id = "StormBlade", Name = "Клинок Бури", Damage = 120, Cost = 60000, Unique = true, Color = Color3.fromRGB(90, 200, 255) },
	{ Id = "EclipseScythe", Name = "Коса Затмения", Damage = 450, Cost = 300000, Unique = true, Color = Color3.fromRGB(255, 120, 60) },
	{ Id = "StarAuraSword", Name = "Меч Звёздной Ауры", Damage = 1600, Cost = 1500000, Unique = true, Color = Color3.fromRGB(255, 230, 120) },
}

-- Backpacks: passive Aura per second (x Aura multiplier), also while
-- offline (see Config.Offline). Size is the box on the player's back.
Config.Backpacks = {
	{ Id = "Pouch", Name = "Мешочек", PerSecond = 2, Cost = 300, Color = Color3.fromRGB(170, 120, 80), Size = Vector3.new(1.2, 1.2, 0.6) },
	{ Id = "Satchel", Name = "Ранец", PerSecond = 10, Cost = 3000, Color = Color3.fromRGB(70, 120, 200), Size = Vector3.new(1.6, 1.8, 0.8) },
	{ Id = "AuraPack", Name = "Ранец Ауры", PerSecond = 50, Cost = 25000, Color = Color3.fromRGB(180, 100, 255), Size = Vector3.new(1.9, 2.2, 1), Neon = true },
	{ Id = "StarPack", Name = "Ранец Звёзд", PerSecond = 250, Cost = 400000, Color = Color3.fromRGB(255, 220, 110), Size = Vector3.new(2.1, 2.5, 1.1), Neon = true },
}

-- Pets: +Bonus to all Aura gains (multiplier = 1 + Bonus). Bought for
-- Aura or dropped by bosses (Config.Dungeon.BossPetDrops).
Config.Pets = {
	{ Id = "Spark", Name = "Искорка", Bonus = 0.25, Cost = 5000, Color = Color3.fromRGB(255, 220, 90), Size = 1.4 },
	{ Id = "Dragon", Name = "Дракончик Ауры", Bonus = 0.75, Cost = 250000, Color = Color3.fromRGB(170, 90, 255), Size = 2, Wings = true },
}

-- Offline income from the backpack: on join the player receives
-- PerSecond x seconds away x Efficiency (capped).
Config.Offline = {
	Efficiency = 0.5,
	MaxHours = 8,
	MinSeconds = 60,
}

---------------------------------------------------------------------
-- Rebirth (at the hub altar)
---------------------------------------------------------------------

-- Requirement: clear room RequiredRoom. Resets Aura, weapons,
-- backpacks and dungeon progress; keeps pets. Every rebirth adds
-- MultiplierPerRebirth to the permanent Aura multiplier.
Config.Rebirth = {
	RequiredRoom = 20,
	MultiplierPerRebirth = 0.1,
}
Config.RebirthRequirement = Config.Rebirth.RequiredRoom

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

---------------------------------------------------------------------
-- Shop categories
---------------------------------------------------------------------

Config.Shop = {
	Weapon = {
		Title = "Оружие",
		Items = Config.Weapons,
		OwnedKey = "OwnedWeapons",
		EquippedKey = "EquippedWeapon",
		Describe = function(item)
			return "Урон x" .. item.Damage .. (if item.Unique then " • уникальное" else "")
		end,
	},
	Backpack = {
		Title = "Ранцы",
		Items = Config.Backpacks,
		OwnedKey = "OwnedBackpacks",
		EquippedKey = "EquippedBackpack",
		Describe = function(item)
			return "+" .. item.PerSecond .. " Ауры/сек (и офлайн)"
		end,
	},
	Pet = {
		Title = "Питомцы",
		Items = Config.Pets,
		OwnedKey = "OwnedPets",
		EquippedKey = "EquippedPet",
		Describe = function(item)
			return "+" .. math.floor(item.Bonus * 100 + 0.5) .. "% ко всей Ауре • дроп с боссов"
		end,
	},
}

Config.ItemById = {} -- [category][id] = item
for category, shop in pairs(Config.Shop) do
	Config.ItemById[category] = {}
	for _, item in ipairs(shop.Items) do
		Config.ItemById[category][item.Id] = item
	end
end

---------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------

-- All remotes live directly in ReplicatedStorage, created by the server.
Config.Remotes = {
	ClickHit = "RemoteEvent", -- C->S (target); S->C ("Hit"|"Train"|"Kill", ...)
	ShopRequest = "RemoteFunction", -- (action, category, id) -> ok, message
	RebirthRequest = "RemoteFunction", -- () -> ok, message
	Travel = "RemoteFunction", -- ("Hub") | ("Room", n) -> ok, message
	Notify = "RemoteEvent", -- S->C (text, kind) toast
}

-- Built-in Roblox client sounds (no upload needed). Swap for your own
-- rbxassetid:// if you like.
Config.Sounds = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav",
	Rebirth = "rbxasset://sounds/electronicpingshort.wav",
}

return Config
