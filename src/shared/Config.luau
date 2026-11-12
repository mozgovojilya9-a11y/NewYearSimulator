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
-- pets) must never be renamed without a migration.
Config.StartingData = {
	Aura = 0,
	Rebirths = 0,
	EquippedWeapon = "Stick",
	OwnedWeapons = { Stick = true }, -- crafted (or legacy bought) weapons
	OwnedPets = {},
	EquippedPet = "",
	RoomReached = 0, -- highest dungeon room cleared (0 = none, 20 = all)
	TrainersUnlocked = { ["1"] = true }, -- hub platforms unlocked by Aura (permanent)
	-- Engagement systems (ProgressionService)
	Daily = { LastClaim = 0, Streak = 0 },
	WheelLast = 0,
	Quests = { Day = 0, List = {} },
	Level = 1,
	Xp = 0,
	BoostUntil = 0,
	LastSeen = 0, -- os.time() of the last save
}
-- Fields from older versions that are ignored on load (never written back):
-- OwnedBackpacks, EquippedBackpack.

Config.AutosaveInterval = 120

-- Startup cleanup of the place. Everything in Workspace except these
-- names (plus Terrain and the camera) is destroyed before the hub and
-- dungeon are generated, so old builds can't leak into the new look.
Config.World = {
	PurgeWorkspace = true,
	Keep = { "SpawnLocation", "Baseplate" },
}

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

	-- Difficulty curve. "Recommended damage" for room r grows faster than
	-- a single run can pay for, so the loop is: run -> stuck -> trainers /
	-- weapons -> deeper run. Mob HP = RecommendedDamage(r) x ClicksToKill.
	RecommendedBase = 2,
	RecommendedGrowth = 1.42, -- r1 = 2, r5 ~ 8, r10 ~ 47, r15 ~ 280, r20 ~ 1650
	ClicksToKill = 8, -- normal mob dies in ~8 clicks at recommended damage
	BossClicksToKill = 50,

	-- Personal runs: every portal entry starts a new run from room 1 in
	-- the player's own lane; only the current and next rooms exist.
	Lanes = { Max = 16, Spacing = 260 },
	RoomsAhead = 1,

	-- Mob behaviour (stage 5): aggro, walking, telegraphed melee hits and
	-- the boss ground slam. Damage to the player grows per room.
	Mob = {
		AggroRange = 40,
		AttackRange = 4.5,
		WalkSpeed = 10,
		BossWalkSpeed = 7,
		AttackCooldown = 1.6,
		TelegraphSeconds = 0.5,
		DamageBase = 8,
		DamageGrowth = 1.12, -- r20 ~ 70 per hit (player HP 100)
		BossDamageMultiplier = 2.5,
		BossSlamEvery = 6,
		BossSlamRadius = 12,
		BossSlamWarning = 1, -- seconds the red circle shows before the hit
		BossSlamDamageMultiplier = 4,
	},

	-- Every boss kill rolls these in order; the first unowned pet that
	-- hits is given to the player.
	BossPetDrops = {
		{ PetId = "Spark", Chance = 0.25 },
		{ PetId = "Dragon", Chance = 0.05 },
	},
}

-- The player in combat. Health regenerates only when nothing hit the
-- player for RegenDelay seconds (the default Roblox regen is disabled).
Config.Player = {
	RegenDelay = 4,
	RegenPerSecond = 6,
}

-- Map bounds: nobody can leave the playable area. Invisible walls rise
-- HubWallExtra studs above the castle walls; every dungeon room and
-- corridor is a closed invisible box (walls overlap by Overlap studs).
-- A character below FallY (relative to the ground) is teleported back
-- without dying; FallenPartsDestroyHeight sits far below that.
Config.Bounds = {
	FallY = -25,
	DestroyY = -500,
	HubWallExtra = 60,
	DungeonCeiling = 34, -- studs above the room floor
	Overlap = 1,
	CheckInterval = 0.5,
	Text = "Ты вернулся на карту",
}

function Config.IsBossRoom(room: number): boolean
	return room % Config.Dungeon.BossEvery == 0
end

-- Damage per click a player "should" have for a room (barrier hint).
function Config.RecommendedDamage(room: number): number
	local d = Config.Dungeon
	return math.max(1, math.floor(d.RecommendedBase * d.RecommendedGrowth ^ (room - 1)))
end

function Config.MobHealth(room: number, isBoss: boolean): number
	local d = Config.Dungeon
	return Config.RecommendedDamage(room) * (if isBoss then d.BossClicksToKill else d.ClicksToKill)
end

function Config.MobDamage(room: number, isBoss: boolean): number
	local m = Config.Dungeon.Mob
	local damage = m.DamageBase * m.DamageGrowth ^ (room - 1)
	if isBoss then
		damage *= m.BossDamageMultiplier
	end
	return math.floor(damage)
end

-- Weapons: Damage is the weapon base. Weapons are crafted at the forge
-- (recipes arrive with the crafting stage); these entries are the
-- legacy list so already-owned weapons keep working. One weapon is active.
Config.Weapons = {
	{ Id = "Stick", Name = "Палка", Rarity = "Common", Damage = 1, Cost = 0, Color = Color3.fromRGB(150, 110, 70) },
	{ Id = "WoodSword", Name = "Деревянный меч", Rarity = "Common", Damage = 3, Cost = 100, Color = Color3.fromRGB(200, 150, 90) },
	{ Id = "IronSword", Name = "Железный меч", Rarity = "Rare", Damage = 10, Cost = 1200, Color = Color3.fromRGB(190, 200, 215) },
	{ Id = "AuraKatana", Name = "Катана Ауры", Rarity = "Epic", Damage = 35, Cost = 12000, Color = Color3.fromRGB(190, 110, 255) },
	{ Id = "StormBlade", Name = "Клинок Бури", Rarity = "Legendary", Damage = 120, Cost = 60000, Unique = true, Color = Color3.fromRGB(90, 200, 255) },
	{ Id = "EclipseScythe", Name = "Коса Затмения", Rarity = "Legendary", Damage = 450, Cost = 300000, Unique = true, Color = Color3.fromRGB(255, 120, 60) },
	{ Id = "StarAuraSword", Name = "Меч Звёздной Ауры", Rarity = "Mythic", Damage = 1600, Cost = 1500000, Unique = true, Color = Color3.fromRGB(255, 230, 120) },
}

-- Pets: +Bonus to all Aura gains (multiplier = 1 + Bonus).
Config.Pets = {
	{ Id = "Spark", Name = "Искорка", Rarity = "Epic", Bonus = 0.25, Cost = 5000, Color = Color3.fromRGB(255, 220, 90), Size = 1.4 },
	{ Id = "Dragon", Name = "Дракончик Ауры", Rarity = "Mythic", Bonus = 0.75, Cost = 250000, Color = Color3.fromRGB(170, 90, 255), Size = 2, Wings = true },
}
Config.PetSlots = 1 -- shown as "N/1" in the HUD

-- Rebirth at the hub altar: requires RoomReached >= RebirthRequirement.
-- Resets Aura and the room record; keeps weapons, armor, items, pets.
Config.RebirthRequirement = 20
Config.Rebirth = {
	MultiplierPerRebirth = 0.1,
}

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

-- Hub trainers: standing on a platform and clicking its object gives
-- ClickPower x TrainerRate x the platform multiplier. Platforms unlock
-- by Aura (early) or rebirths (late). Auto-click repeats a trainer
-- click every AutoClickInterval seconds while the toggle is on and the
-- player stands on an unlocked platform (the AFK progression loop).
Config.Hub = {
	TrainerRate = 0.25,
	TrainerMultipliers = { 1, 3, 6, 12, 25, 50, 100, 250 },
	TrainerRequirements = {
		{},
		{ Aura = 500 },
		{ Aura = 5000 },
		{ Aura = 50000 },
		{ Rebirths = 1 },
		{ Rebirths = 2 },
		{ Rebirths = 3 },
		{ Rebirths = 5 },
	},
	AutoClickInterval = 0.5,
}

-- Engagement loop: things to do every few minutes.
-- Aura rewards scale with the player's record room so they stay relevant.
Config.Progression = {
	Daily = {
		CooldownHours = 20, -- can claim again after this
		StreakWindowHours = 48, -- longer gap resets the streak
		Aura = { 100, 200, 350, 500, 800, 1200, 2500 }, -- day 1..7, x (1 + record/2)
		Day7Boost = true, -- day 7 also grants a boost
	},
	Wheel = {
		CooldownHours = 4,
		Prizes = { -- weights sum does not need to be 100
			{ Kind = "Aura", Amount = 150, Weight = 30, Label = "Аура" },
			{ Kind = "Aura", Amount = 400, Weight = 22, Label = "Аура+" },
			{ Kind = "Aura", Amount = 1200, Weight = 10, Label = "Много Ауры" },
			{ Kind = "Boost", Minutes = 15, Weight = 16, Label = "x2 Аура 15 мин" },
			{ Kind = "Aura", Amount = 250, Weight = 12, Label = "Аура" },
			{ Kind = "Egg", Weight = 6, Label = "Яйцо питомца" },
			{ Kind = "Aura", Amount = 600, Weight = 10, Label = "Аура++" },
			{ Kind = "Boost", Minutes = 30, Weight = 4, Label = "x2 Аура 30 мин" },
		},
	},
	Boost = { Multiplier = 2 },
	Quests = { -- 3 per day are picked from this pool
		Pool = {
			{ Id = "kill30", Kind = "Kill", Target = 30, Text = "Убей 30 мобов", Aura = 300 },
			{ Id = "kill80", Kind = "Kill", Target = 80, Text = "Убей 80 мобов", Aura = 900 },
			{ Id = "room5", Kind = "Room", Target = 5, Text = "Дойди до этапа 5", Aura = 500 },
			{ Id = "room10", Kind = "Room", Target = 10, Text = "Дойди до этапа 10", Aura = 1500 },
			{ Id = "train500", Kind = "Train", Target = 500, Text = "Покликай на тренажёре 500 раз", Aura = 400 },
			{ Id = "train1500", Kind = "Train", Target = 1500, Text = "Покликай на тренажёре 1500 раз", Aura = 1200 },
			{ Id = "boss2", Kind = "Boss", Target = 2, Text = "Победи 2 боссов", Aura = 1000 },
			{ Id = "runs3", Kind = "Run", Target = 3, Text = "Соверши 3 забега", Aura = 350 },
		},
		PerDay = 3,
	},
	Level = {
		XpPerKill = 10, -- x room index
		XpPerBoss = 100, -- x room index
		XpBase = 100, -- xp to next level = XpBase x level^1.5
		RewardEvery = 5, -- levels
		RewardAura = 500, -- x level
	},
}

-- Equipment on the character (visual only). Grip = offset of the weapon
-- Handle from the hand part. Swing: shoulder Motor6D rotation per rig
-- type and timing.
Config.Equipment = {
	GripR6 = CFrame.new(0, -1, -0.6) * CFrame.Angles(math.rad(-90), 0, 0),
	GripR15 = CFrame.new(0, -0.3, -0.6) * CFrame.Angles(math.rad(-90), 0, 0),
	Swing = {
		RaiseR6 = CFrame.Angles(0, 0, math.rad(110)),
		RaiseR15 = CFrame.Angles(math.rad(-110), 0, 0),
		UpSeconds = 0.06,
		DownSeconds = 0.1,
	},
}

-- Leaderboards (OrderedDataStore). Scores are written on every save.
Config.Leaderboards = {
	AuraStore = "AuraClicker_TopAura_v1",
	RoomStore = "AuraClicker_TopRoom_v1",
	RefreshSeconds = 60,
	Top = 10,
}

-- Shop categories (what is owned / equipped and how to describe it).
Config.Shop = {
	Weapon = { Title = "Оружие", Items = Config.Weapons, OwnedKey = "OwnedWeapons", EquippedKey = "EquippedWeapon", Purchasable = false,
		Describe = function(item) return "Урон x" .. item.Damage end },
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
	ClickHit = "RemoteEvent", -- C->S (target); S->C ("Hit"|"Train"|"Kill", ...)
	ShopRequest = "RemoteFunction", -- (action, category, id) -> ok, message
	RebirthRequest = "RemoteFunction", -- () -> ok, message
	Travel = "RemoteFunction", -- ("Hub") | ("Room", n) -> ok, message
	Notify = "RemoteEvent", -- S->C (text, kind) toast
	AutoClick = "RemoteEvent", -- C->S (enabled: boolean)
	RoomState = "RemoteEvent", -- S->C (room, alive, total) for the player's own run
	RunEnded = "RemoteEvent", -- S->C (reason, room, auraEarned, record, isNewRecord)
	Progression = "RemoteFunction", -- ("Status") | ("ClaimDaily") | ("Spin") | ("ClaimQuest", index) -> ok, payload
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
	Panel = Color3.fromRGB(30, 27, 46), -- window body (#1E1B2E, opaque)
	PanelDark = Color3.fromRGB(30, 27, 46), -- HUD plates and every text plate (#1E1B2E)
	Card = Color3.fromRGB(48, 43, 72), -- cards inside windows
	CardDark = Color3.fromRGB(22, 20, 34), -- slots, viewport backgrounds
	-- Stone: two close tints alternate in 4x4 / 8x8 blocks for a tile look.
	StoneA = Color3.fromRGB(140, 123, 214), -- #8C7BD6 walls
	StoneB = Color3.fromRGB(110, 95, 192), -- #6E5FC0 walls (alternate)
	StoneLight = Color3.fromRGB(190, 178, 240), -- merlons / caps
	StoneDark = Color3.fromRGB(78, 64, 150), -- pedestals, towers
	TileA = Color3.fromRGB(226, 220, 245), -- courtyard tiles (light)
	TileB = Color3.fromRGB(165, 150, 220), -- courtyard tiles (dark)
	Path = Color3.fromRGB(112, 40, 210), -- player's path (saturated purple)
	Chevron = Color3.fromRGB(255, 220, 70),
	Grass = Color3.fromRGB(96, 190, 80),
	Sky = Color3.fromRGB(120, 190, 255),
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
-- between presets when the player's "Zone" attribute changes. Rules:
-- no glow wash (Bloom <= 0.05), neutral haze, ambient never black.
Config.Lighting = {
	TransitionSeconds = 1,
	BloomSize = 24,
	BloomThreshold = 1.2, -- only the very brightest neon pixels may glow
	Hub = {
		ClockTime = 14, Brightness = 2, ExposureCompensation = 0,
		Ambient = Color3.fromRGB(125, 125, 135), OutdoorAmbient = Color3.fromRGB(140, 140, 150),
		Saturation = 0.1, Contrast = 0, Tint = Color3.fromRGB(255, 255, 255), Bloom = 0.03,
		Atmosphere = { Density = 0.2, Color = Color3.fromRGB(200, 220, 255), Decay = Color3.fromRGB(160, 190, 235), Glare = 0, Haze = 0.3 },
	},
	Dungeon = {
		ClockTime = 14, Brightness = 1.6, ExposureCompensation = 0,
		-- Ambient / OutdoorAmbient / Atmosphere colors come from the biome
		-- the player stands in (Config.DungeonLayout.Biomes[i].Lighting).
		Ambient = Color3.fromRGB(120, 120, 130), OutdoorAmbient = Color3.fromRGB(125, 125, 135),
		Saturation = 0.1, Contrast = 0, Tint = Color3.fromRGB(255, 255, 255), Bloom = 0.03,
		Atmosphere = { Density = 0.3, Color = Color3.fromRGB(150, 160, 180), Decay = Color3.fromRGB(90, 100, 130), Glare = 0, Haze = 0.6 },
	},
}

---------------------------------------------------------------------
-- VISUAL: hub layout (offsets from the SpawnLocation; forward = -Z)
---------------------------------------------------------------------

Config.HubLayout = {
	Name = "Цитадель Ауры",
	Size = 176, -- courtyard side (square)
	TileSize = 8,
	WallHeight = 14,
	WallThickness = 4,
	TowerSize = 12,
	TowerHeight = 24,
	MerlonSize = 2,

	PathWidth = 14,
	ChevronSpacing = 9,

	Portal = { Offset = Vector3.new(0, 0, -80), Radius = 7, ArchWidth = 22, ArchHeight = 20, SpinSeconds = 6 },

	-- Trainer row, left of the path, front to back (index 1 nearest the spawn).
	TrainerRow = { X = -30, ZStart = 36, Spacing = -11 },
	TrainerPlatformRadius = 4.5,
	-- Looks: platform color + the object on it (built by TrainerBuilder).
	Trainers = {
		{ Kind = "Dummy", Name = "Манекен", Color = Color3.fromRGB(90, 230, 110) },
		{ Kind = "Boulder", Name = "Валун", Color = Color3.fromRGB(70, 140, 255) },
		{ Kind = "IceCube", Name = "Ледяной куб", Color = Color3.fromRGB(46, 230, 255) },
		{ Kind = "Mimic", Name = "Сундук-мимик", Color = Color3.fromRGB(255, 150, 50) },
		{ Kind = "Skull", Name = "Гигантский череп", Color = Color3.fromRGB(230, 230, 240) },
		{ Kind = "Pumpkin", Name = "Тыква-монстр", Color = Color3.fromRGB(255, 120, 30) },
		{ Kind = "Golem", Name = "Кристальный голем", Color = Color3.fromRGB(150, 80, 255) },
		{ Kind = "Core", Name = "Аура-ядро", Color = Color3.fromRGB(255, 61, 184) },
	},

	-- Back of the courtyard (+Z).
	Altar = { Offset = Vector3.new(-56, 0, 66) },
	Shop = { Offset = Vector3.new(-18, 0, 70) },
	Wheel = { Offset = Vector3.new(18, 0, 70) },
	Egg = { Offset = Vector3.new(56, 0, 66) },
	Fountain = { Offset = Vector3.new(0, 0, 34), Radius = 7 },
	Leaderboards = { -- on the inner face of the back wall
		{ Offset = Vector3.new(-40, 0, 85), Kind = "Aura", Title = "Топ Ауры" },
		{ Offset = Vector3.new(40, 0, 85), Kind = "Room", Title = "Глубже всех в данже" },
	},
	Npc = { Offset = Vector3.new(14, 0, -66) },
	Trees = { Vector3.new(-70, 0, -60), Vector3.new(70, 0, -60), Vector3.new(72, 0, 10), Vector3.new(-72, 0, 10) },
	Bushes = { Vector3.new(-62, 0, 40), Vector3.new(62, 0, 40), Vector3.new(-12, 0, 46), Vector3.new(12, 0, 46), Vector3.new(-66, 0, -20), Vector3.new(66, 0, -20) },
	TorchesAlongPath = 5,

	Texts = {
		Portal = "ПОДЗЕМЕЛЬЕ",
		Trainer = "x%s Мощность",
		TrainerLockedAura = "Нужно %s Ауры",
		TrainerLockedRebirth = "Открывается: Перерождение %d",
		Altar = "АЛТАРЬ ПЕРЕРОЖДЕНИЯ",
		Shop = "МАСТЕРСКАЯ",
		Wheel = "КОЛЕСО УДАЧИ",
		WheelFree = "Бесплатное вращение!",
		Egg = "Новинка!",
		Npc = "Подземелье →",
	},
	Prompts = {
		Rebirth = "Переродиться",
		Shop = "Открыть",
		Egg = "Открыть",
		Wheel = "Крутить",
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
	TorchesPerWall = 2, -- torches on each side wall of a room

	-- One biome per 5 rooms.
	Biomes = {
		-- Walls (StoneA/B) are clearly lighter than the floor (Floor/FloorB),
		-- so edges read at a glance. Atmosphere tints the haze per biome.
		{ Name = "Неоновые катакомбы", StoneA = Color3.fromRGB(120, 118, 140), StoneB = Color3.fromRGB(100, 98, 122), Floor = Color3.fromRGB(58, 56, 72), FloorB = Color3.fromRGB(46, 44, 58), Accent = Color3.fromRGB(100, 255, 90), Light = Color3.fromRGB(150, 255, 140),
			Atmosphere = { Color = Color3.fromRGB(150, 185, 150), Decay = Color3.fromRGB(80, 120, 80) },
			Lighting = { Ambient = Color3.fromRGB(115, 125, 115), OutdoorAmbient = Color3.fromRGB(120, 135, 120) } },
		{ Name = "Ледяной грот", StoneA = Color3.fromRGB(175, 215, 245), StoneB = Color3.fromRGB(150, 195, 235), Floor = Color3.fromRGB(80, 125, 175), FloorB = Color3.fromRGB(65, 105, 155), Accent = Color3.fromRGB(46, 230, 255), Light = Color3.fromRGB(140, 230, 255),
			Atmosphere = { Color = Color3.fromRGB(170, 210, 245), Decay = Color3.fromRGB(100, 150, 210) },
			Lighting = { Ambient = Color3.fromRGB(120, 135, 150), OutdoorAmbient = Color3.fromRGB(130, 145, 165) } },
		{ Name = "Лавовая кузня", StoneA = Color3.fromRGB(165, 75, 60), StoneB = Color3.fromRGB(140, 60, 50), Floor = Color3.fromRGB(75, 30, 30), FloorB = Color3.fromRGB(60, 22, 24), Accent = Color3.fromRGB(255, 140, 40), Light = Color3.fromRGB(255, 160, 80),
			Atmosphere = { Color = Color3.fromRGB(215, 150, 110), Decay = Color3.fromRGB(150, 80, 50) },
			Lighting = { Ambient = Color3.fromRGB(140, 115, 105), OutdoorAmbient = Color3.fromRGB(150, 120, 110) } },
		{ Name = "Бездна ауры", StoneA = Color3.fromRGB(140, 105, 210), StoneB = Color3.fromRGB(118, 85, 185), Floor = Color3.fromRGB(55, 32, 100), FloorB = Color3.fromRGB(44, 25, 85), Accent = Color3.fromRGB(255, 201, 60), Light = Color3.fromRGB(215, 170, 255),
			Atmosphere = { Color = Color3.fromRGB(175, 150, 225), Decay = Color3.fromRGB(110, 80, 170) },
			Lighting = { Ambient = Color3.fromRGB(125, 115, 145), OutdoorAmbient = Color3.fromRGB(135, 125, 155) } },
	},
	BossBarrierColor = Color3.fromRGB(255, 61, 184),

	Texts = {
		Enemies = "%d/%d врагов",
		Stage = "Этап %d",
		Recommended = "Рекомендуемый урон: %s",
		Boss = "БИТВА С БОССОМ",
		Cleared = "Пройдено!",
		Entrance = "ЭТАП %d",
		RunDied = "Ты пал в бою",
		RunLeft = "Забег завершён",
		RunWon = "Подземелье пройдено!",
		RunSummary = "Дошёл до этапа %d  •  заработано %s Ауры  •  рекорд %d",
		NewRecord = "Новый рекорд этапа!",
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
	MenuButtons = { -- grid on the left, 2 columns
		{ Id = "Equipment", Icon = "⚔", Label = "Снаряжение", Color = Color3.fromRGB(90, 230, 110) },
		{ Id = "Pets", Icon = "🐾", Label = "Питомцы", Color = Color3.fromRGB(255, 61, 184) },
		{ Id = "Rebirth", Icon = "🔁", Label = "Перерождение", Color = Color3.fromRGB(150, 80, 255) },
		{ Id = "Reward", Icon = "🎁", Label = "Награда", Color = Color3.fromRGB(255, 201, 60) },
		{ Id = "Travel", Icon = "🚪", Label = "Телепорт", Color = Color3.fromRGB(70, 60, 190) },
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
	Barrier = "", -- TODO: barrier dissolve
	Portal = "", -- TODO: portal whoosh
	BossDeath = "", -- TODO: boss explosion
	Ui = "", -- TODO: button click
}

return Config
