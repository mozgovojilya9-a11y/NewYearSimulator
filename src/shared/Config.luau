--[[
	Config.luau
	Shared, read-only game configuration. EVERY balance number, color,
	size, text and layout constant lives here; server and client logic
	only read it. It contains no secrets (the client can see it).

	Sections: data -> balance (click, dungeon, items, rebirth, offline)
	-> visual (theme, lighting, hub layout, dungeon look, mobs, HUD).
]]

local Config = {}

Config.DataStoreName = "AuraClicker_v1"

-- Default data for a brand-new player. DataService backfills any
-- fields missing from an older save. IDs stored in saves (weapons,
-- backpacks, pets) must never be renamed without a migration.
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

Config.AutosaveInterval = 120

---------------------------------------------------------------------
-- BALANCE
---------------------------------------------------------------------

Config.Click = {
	BaseDamage = 1, -- damage of one click with weapon x1
	CritChance = 0.1, -- 10% chance per click
	CritMultiplier = 5, -- crit = damage x5
	Cooldown = 0.1, -- min seconds between accepted clicks per player (anti-macro)
	Range = 60, -- max studs between player and target
}

Config.Dungeon = {
	Rooms = 20,
	BossEvery = 5, -- rooms 5, 10, 15, 20
	Seed = 2026, -- same layout on every server

	MobsMin = 3,
	MobsMax = 5,

	-- Normal mob HP in room r = BaseHealth * HealthGrowth^(r-1).
	BaseHealth = 6,
	HealthGrowth = 1.45,
	RewardPerHealth = 2, -- Aura per kill = HP x this
	BossHealthMultiplier = 15,
	BossRewardMultiplier = 1.5,

	RoomRespawnDelay = 6, -- seconds after a room is cleared before its mobs return
	BossRespawnDelay = 20,

	DropLifetime = 25, -- seconds an Aura crystal waits to be picked up before auto-collect

	-- Every boss kill rolls these in order; the first unowned pet that
	-- hits is given to each player who damaged the boss.
	BossPetDrops = {
		{ PetId = "Spark", Chance = 0.25 },
		{ PetId = "Dragon", Chance = 0.05 },
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

-- Damage per click a player "should" have for a room (shown on the
-- barrier as a hint): enough to kill a normal mob in ~5 clicks.
function Config.RecommendedDamage(room: number): number
	return math.max(1, math.floor(Config.MobHealth(room, false) / 5))
end

-- Weapons: Damage multiplies click power. Unique weapons are bought
-- only at the hub stand, the rest in the shop. One weapon is active.
Config.Weapons = {
	{ Id = "Stick", Name = "Палка", Rarity = "Common", Damage = 1, Cost = 0, Color = Color3.fromRGB(150, 110, 70) },
	{ Id = "WoodSword", Name = "Деревянный меч", Rarity = "Common", Damage = 3, Cost = 100, Color = Color3.fromRGB(200, 150, 90) },
	{ Id = "IronSword", Name = "Железный меч", Rarity = "Rare", Damage = 10, Cost = 1200, Color = Color3.fromRGB(190, 200, 215) },
	{ Id = "AuraKatana", Name = "Катана Ауры", Rarity = "Epic", Damage = 35, Cost = 12000, Color = Color3.fromRGB(190, 110, 255) },
	{ Id = "StormBlade", Name = "Клинок Бури", Rarity = "Legendary", Damage = 120, Cost = 60000, Unique = true, Color = Color3.fromRGB(90, 200, 255) },
	{ Id = "EclipseScythe", Name = "Коса Затмения", Rarity = "Legendary", Damage = 450, Cost = 300000, Unique = true, Color = Color3.fromRGB(255, 120, 60) },
	{ Id = "StarAuraSword", Name = "Меч Звёздной Ауры", Rarity = "Mythic", Damage = 1600, Cost = 1500000, Unique = true, Color = Color3.fromRGB(255, 230, 120) },
}

-- Backpacks: passive Aura per second (x Aura multiplier), also offline.
Config.Backpacks = {
	{ Id = "Pouch", Name = "Мешочек", Rarity = "Common", PerSecond = 2, Cost = 300, Color = Color3.fromRGB(170, 120, 80), Size = Vector3.new(1.2, 1.2, 0.6) },
	{ Id = "Satchel", Name = "Ранец", Rarity = "Rare", PerSecond = 10, Cost = 3000, Color = Color3.fromRGB(70, 120, 200), Size = Vector3.new(1.6, 1.8, 0.8) },
	{ Id = "AuraPack", Name = "Ранец Ауры", Rarity = "Epic", PerSecond = 50, Cost = 25000, Color = Color3.fromRGB(180, 100, 255), Size = Vector3.new(1.9, 2.2, 1), Neon = true },
	{ Id = "StarPack", Name = "Ранец Звёзд", Rarity = "Legendary", PerSecond = 250, Cost = 400000, Color = Color3.fromRGB(255, 220, 110), Size = Vector3.new(2.1, 2.5, 1.1), Neon = true },
}

-- Pets: +Bonus to all Aura gains (multiplier = 1 + Bonus).
Config.Pets = {
	{ Id = "Spark", Name = "Искорка", Rarity = "Epic", Bonus = 0.25, Cost = 5000, Color = Color3.fromRGB(255, 220, 90), Size = 1.4 },
	{ Id = "Dragon", Name = "Дракончик Ауры", Rarity = "Mythic", Bonus = 0.75, Cost = 250000, Color = Color3.fromRGB(170, 90, 255), Size = 2, Wings = true },
}
Config.PetSlots = 1 -- shown as "N/1" in the HUD

Config.Offline = {
	Efficiency = 0.5,
	MaxHours = 8,
	MinSeconds = 60,
}

-- Rebirth at the hub altar: requires RoomReached >= RebirthRequirement.
-- Resets Aura, weapons, backpacks and dungeon progress; keeps pets.
Config.RebirthRequirement = 20
Config.Rebirth = {
	MultiplierPerRebirth = 0.1,
}

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

-- Hub trainers: clicking one gives ClickPower x TrainerRate x the
-- trainer's own multiplier (left -> right). Immortal, no dungeon needed.
Config.Hub = {
	TrainerRate = 0.25,
	TrainerMultipliers = { 1, 3, 6 },
}

-- Shop categories (what is owned / equipped and how to describe it).
Config.Shop = {
	Weapon = { Title = "Оружие", Items = Config.Weapons, OwnedKey = "OwnedWeapons", EquippedKey = "EquippedWeapon",
		Describe = function(item) return "Урон x" .. item.Damage .. (if item.Unique then " • стенд в хабе" else "") end },
	Backpack = { Title = "Рюкзаки", Items = Config.Backpacks, OwnedKey = "OwnedBackpacks", EquippedKey = "EquippedBackpack",
		Describe = function(item) return "+" .. item.PerSecond .. " Ауры/сек (и офлайн)" end },
	Pet = { Title = "Питомцы", Items = Config.Pets, OwnedKey = "OwnedPets", EquippedKey = "EquippedPet",
		Describe = function(item) return "+" .. math.floor(item.Bonus * 100 + 0.5) .. "% ко всей Ауре • дроп с боссов" end },
}

Config.ItemById = {} -- [category][id] = item
for category, shop in pairs(Config.Shop) do
	Config.ItemById[category] = {}
	for _, item in ipairs(shop.Items) do
		Config.ItemById[category][item.Id] = item
	end
end

-- All remotes live directly in ReplicatedStorage, created by the server.
Config.Remotes = {
	ClickHit = "RemoteEvent", -- C->S (target); S->C ("Hit"|"Train"|"Kill"|"Pickup", ...)
	ShopRequest = "RemoteFunction", -- (action, category, id) -> ok, message
	RebirthRequest = "RemoteFunction", -- () -> ok, message
	Travel = "RemoteFunction", -- ("Hub") | ("Room", n) -> ok, message
	Notify = "RemoteEvent", -- S->C (text, kind) toast
	RoomState = "RemoteEvent", -- S->C (room, alive, total) for barrier counters
}

---------------------------------------------------------------------
-- VISUAL: theme
---------------------------------------------------------------------

-- "Цитадель Ауры": bright cartoon brick world. Light lilac stone base,
-- three loud accents. Neon is used only on trims, portals and runes.
Config.Theme = {
	Font = Enum.Font.FredokaOne,
	Magenta = Color3.fromRGB(255, 61, 184), -- #FF3DB8
	Cyan = Color3.fromRGB(46, 230, 255), -- #2EE6FF
	Gold = Color3.fromRGB(255, 201, 60), -- #FFC93C
	Purple = Color3.fromRGB(150, 80, 255),
	Green = Color3.fromRGB(90, 230, 110),
	Red = Color3.fromRGB(240, 70, 80),
	Orange = Color3.fromRGB(255, 150, 50),
	Blue = Color3.fromRGB(70, 140, 255),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(220, 215, 235),
	Outline = Color3.fromRGB(20, 10, 35),
	Panel = Color3.fromRGB(250, 246, 255), -- window body (light)
	PanelDark = Color3.fromRGB(40, 28, 70), -- HUD plates
	-- Stone: two close tints alternate in 4x4 / 8x8 blocks for a tile look.
	StoneA = Color3.fromRGB(225, 214, 245),
	StoneB = Color3.fromRGB(208, 194, 235),
	StoneDark = Color3.fromRGB(150, 130, 190),
	Path = Color3.fromRGB(120, 60, 220), -- player's path
	Chevron = Color3.fromRGB(255, 220, 70),
	Grass = Color3.fromRGB(120, 210, 90),
}

-- Rarity colors, identical in the shop, on pedestals and pets.
-- Mythic additionally gets an animated rainbow gradient in the UI.
Config.Rarity = {
	Common = { Name = "Обычное", Color = Color3.fromRGB(190, 190, 205) },
	Rare = { Name = "Редкое", Color = Config.Theme.Blue },
	Epic = { Name = "Эпическое", Color = Config.Theme.Purple },
	Legendary = { Name = "Легендарное", Color = Config.Theme.Gold },
	Mythic = { Name = "Мифическое", Color = Config.Theme.Magenta, Rainbow = true },
}

-- Lighting presets. The server applies Hub at start; the client tweens
-- between presets when the player's "Zone" attribute changes.
Config.Lighting = {
	TransitionSeconds = 1,
	Hub = {
		ClockTime = 14, Brightness = 2.2, ExposureCompensation = 0.1,
		Ambient = Color3.fromRGB(150, 140, 170), OutdoorAmbient = Color3.fromRGB(170, 160, 200),
		Saturation = 0.15, Contrast = 0.05, Tint = Color3.fromRGB(255, 252, 248), Bloom = 0.35,
		FogColor = Color3.fromRGB(205, 190, 255), FogEnd = 900,
	},
	Dungeon = {
		ClockTime = 1, Brightness = 1, ExposureCompensation = 0.05,
		Ambient = Color3.fromRGB(70, 60, 95), OutdoorAmbient = Color3.fromRGB(60, 50, 85),
		Saturation = 0.2, Contrast = 0.1, Tint = Color3.fromRGB(235, 230, 255), Bloom = 0.6,
		FogColor = Color3.fromRGB(25, 15, 40), FogEnd = 320,
	},
}

---------------------------------------------------------------------
-- VISUAL: hub layout (offsets from the SpawnLocation; forward = -Z)
---------------------------------------------------------------------

Config.HubLayout = {
	Name = "Цитадель Ауры",
	Size = 128, -- courtyard side (square)
	TileSize = 8,
	WallHeight = 14,
	WallThickness = 4,
	TowerSize = 12,
	TowerHeight = 24,
	MerlonSize = 2,

	PathWidth = 14,
	ChevronSpacing = 9,

	Portal = { Offset = Vector3.new(0, 0, -58), Radius = 7, ArchWidth = 22, ArchHeight = 20, SpinSeconds = 6 },
	Trainers = { -- rings left of the path
		{ Offset = Vector3.new(-30, 0, -6), Color = Color3.fromRGB(90, 230, 110) },
		{ Offset = Vector3.new(-30, 0, 10), Color = Color3.fromRGB(70, 140, 255) },
		{ Offset = Vector3.new(-30, 0, 26), Color = Color3.fromRGB(150, 80, 255) },
	},
	TrainerRingRadius = 5,
	Stand = { Offset = Vector3.new(30, 0, 4), Spacing = 12, SpinSeconds = 4, FloatHeight = 0.8, FloatSeconds = 1.6 }, -- 3 pedestals in a row along Z
	Altar = { Offset = Vector3.new(-40, 0, 48) },
	Shop = { Offset = Vector3.new(0, 0, 50) }, -- stall near the back wall
	Egg = { Offset = Vector3.new(40, 0, 48) },
	Trees = { Vector3.new(-50, 0, -40), Vector3.new(50, 0, -40), Vector3.new(52, 0, 20) },
	TorchesAlongPath = 4,

	Texts = {
		Portal = "ПОДЗЕМЕЛЬЕ",
		Trainer = "x%s Мощность",
		Stand = "Лимитированное!",
		Altar = "АЛТАРЬ ПЕРЕРОЖДЕНИЯ",
		Shop = "МАСТЕРСКАЯ",
		Egg = "Новинка!",
	},
	Prompts = {
		Rebirth = "Переродиться",
		Shop = "Открыть",
		Egg = "Открыть",
		Buy = "Купить",
		Collect = "Собрать",
	},
}

---------------------------------------------------------------------
-- VISUAL: dungeon look
---------------------------------------------------------------------

Config.DungeonLayout = {
	Origin = Vector3.new(0, 0, -1600), -- far from the hub: never visible from it
	RoomSizeMin = 46,
	RoomSizeMax = 56,
	BossRoomScale = 1.7, -- boss room side = RoomSizeMax x this
	WallHeight = 16,
	WallThickness = 4,
	TileSize = 6,
	DoorWidth = 14,
	DoorHeight = 12,
	CorridorLength = 20,
	MerlonSize = 2,
	MaxPartsPerRoom = 150, -- design budget (tiles are capped to respect it)

	-- One biome per 5 rooms.
	Biomes = {
		{ Name = "Неоновые катакомбы", StoneA = Color3.fromRGB(60, 58, 72), StoneB = Color3.fromRGB(48, 46, 60), Floor = Color3.fromRGB(70, 68, 84), FloorB = Color3.fromRGB(58, 56, 70), Accent = Color3.fromRGB(100, 255, 90), Light = Color3.fromRGB(110, 255, 100) },
		{ Name = "Ледяной грот", StoneA = Color3.fromRGB(150, 205, 240), StoneB = Color3.fromRGB(125, 185, 230), Floor = Color3.fromRGB(170, 220, 245), FloorB = Color3.fromRGB(150, 205, 238), Accent = Color3.fromRGB(46, 230, 255), Light = Color3.fromRGB(80, 220, 255) },
		{ Name = "Лавовая кузня", StoneA = Color3.fromRGB(120, 40, 40), StoneB = Color3.fromRGB(95, 30, 32), Floor = Color3.fromRGB(70, 30, 30), FloorB = Color3.fromRGB(58, 24, 24), Accent = Color3.fromRGB(255, 140, 40), Light = Color3.fromRGB(255, 120, 40) },
		{ Name = "Бездна ауры", StoneA = Color3.fromRGB(95, 60, 160), StoneB = Color3.fromRGB(75, 45, 135), Floor = Color3.fromRGB(60, 35, 110), FloorB = Color3.fromRGB(50, 28, 95), Accent = Color3.fromRGB(255, 201, 60), Light = Color3.fromRGB(200, 140, 255) },
	},
	BossBarrierColor = Color3.fromRGB(255, 61, 184),

	Texts = {
		Enemies = "%d/%d врагов",
		Stage = "Этап %d",
		Recommended = "Рекомендуемый урон: %s",
		Boss = "БИТВА С БОССОМ",
		Cleared = "Пройдено!",
		Locked = "Пройди комнату %d",
		Entrance = "ЭТАП %d",
	},
}

-- Mob looks: block "aura monsters". Scale is relative to a 4-stud
-- torso; bosses multiply it by BossScale. Faces come from the built-in
-- rbxasset face texture or from small Parts (Skeleton / Shade eyes).
Config.MobLooks = {
	BossScale = 2.5,
	Kinds = {
		{ Kind = "Slime", Name = "Слизень", Shape = "Jelly", Color = Color3.fromRGB(90, 240, 120), Transparency = 0.35, Scale = 1 },
		{ Kind = "Goblin", Name = "Гоблин", Shape = "Humanoid", Color = Color3.fromRGB(90, 190, 70), HeadScale = 1.5, Scale = 1 },
		{ Kind = "Skeleton", Name = "Скелет", Shape = "Humanoid", Color = Color3.fromRGB(240, 240, 230), Thin = true, EyeColor = Color3.fromRGB(46, 230, 255), Scale = 1.05 },
		{ Kind = "Shade", Name = "Тень", Shape = "Humanoid", Color = Color3.fromRGB(20, 15, 35), Outline = Color3.fromRGB(170, 80, 255), EyeColor = Color3.fromRGB(255, 61, 184), Scale = 1.1 },
	},
	-- Boss per boss room: base kind + name + crown color.
	Bosses = {
		[5] = { Kind = "Slime", Name = "Король Слизней", Color = Color3.fromRGB(60, 220, 100), Crown = Color3.fromRGB(255, 201, 60) },
		[10] = { Kind = "Skeleton", Name = "Ледяной Костяной Лорд", Color = Color3.fromRGB(200, 235, 255), Crown = Color3.fromRGB(46, 230, 255) },
		[15] = { Kind = "Goblin", Name = "Огненный Вождь", Color = Color3.fromRGB(230, 90, 40), Crown = Color3.fromRGB(255, 150, 50) },
		[20] = { Kind = "Shade", Name = "Повелитель Бездны", Color = Color3.fromRGB(15, 10, 30), Crown = Color3.fromRGB(255, 61, 184) },
	},
	HealthBar = { MaxDistance = 50, Width = 4.5, Height = 0.9 }, -- studs (BillboardGui scale units)
	Drop = { Color = Color3.fromRGB(190, 120, 255), BeamColor = Color3.fromRGB(230, 180, 255) },
}

---------------------------------------------------------------------
-- VISUAL: HUD
---------------------------------------------------------------------

Config.Hud = {
	TopLeftReserved = Vector2.new(320, 60), -- never put UI here (Roblox buttons)
	Objectives = {
		Hub = "Войди в подземелье!",
		Fight = "Уничтожь врагов!",
		Cleared = "Иди дальше!",
		Done = "Данж пройден! Иди к алтарю",
	},
	-- Quick damage upgrades (bottom center) = these shop weapons, in order.
	-- Prices and damage come from Config.Weapons; the server shop sells them.
	QuickUpgrades = { "WoodSword", "IronSword", "AuraKatana", "StormBlade" },
	QuickUpgradeColors = { Color3.fromRGB(90, 230, 110), Color3.fromRGB(70, 140, 255), Color3.fromRGB(150, 80, 255), Color3.fromRGB(255, 201, 60) },
	MenuButtons = { -- 2x3 grid on the left
		{ Id = "Shop", Icon = "🛒", Label = "Магазин", Color = Color3.fromRGB(90, 230, 110) },
		{ Id = "Backpack", Icon = "🎒", Label = "Рюкзак", Color = Color3.fromRGB(255, 150, 50) },
		{ Id = "Pets", Icon = "🐾", Label = "Питомцы", Color = Color3.fromRGB(255, 61, 184) },
		{ Id = "Rebirth", Icon = "🔁", Label = "Перерождение", Color = Color3.fromRGB(150, 80, 255) },
		{ Id = "Reward", Icon = "🎁", Label = "Награда", Color = Color3.fromRGB(255, 201, 60) },
		{ Id = "Travel", Icon = "🌀", Label = "Телепорт", Color = Color3.fromRGB(46, 230, 255) },
	},
	ToastSeconds = 4,
	ShakeCrit = { Amplitude = 0.25, Seconds = 0.15 },
	ShakeBoss = { Amplitude = 0.8, Seconds = 0.5 },
	BackKey = Enum.KeyCode.B,
	MobileScaleWidth = 1100, -- UIScale = min(1, viewportWidth / this)
}

-- Sounds. Only built-in rbxasset:// files that ship with the Roblox
-- client are used; empty slots are TODO: put your own rbxassetid://
-- there when you have uploaded sounds (never guess IDs).
Config.Sounds = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav",
	Rebirth = "rbxasset://sounds/electronicpingshort.wav",
	Pickup = "rbxasset://sounds/electronicpingshort.wav",
	Barrier = "", -- TODO: barrier dissolve
	Portal = "", -- TODO: portal whoosh
	BossDeath = "", -- TODO: boss explosion
	Ui = "", -- TODO: button click
}

return Config
