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
	Credits = 0, -- "Нано-кредиты": eggs, cosmetics
	EquippedWeapon = "Stick",
	OwnedWeapons = { Stick = true }, -- crafted (or legacy bought) weapons
	OwnedArmor = {}, -- [armorId] = true
	EquippedArmor = { Helmet = "", Chest = "", Legs = "" },
	Materials = {}, -- [materialId] = count
	Pets = {}, -- [petId] = { ["1"] = count, ["2"] = count, ["3"] = count } (tiers)
	EquippedPets = {}, -- { "petId:tier", ... }
	PetIndex = {}, -- [petId] = true once hatched
	RoomReached = 0, -- highest dungeon room cleared (0 = none, 20 = all)
	-- Engagement systems (ProgressionService)
	Daily = { LastClaim = 0, Streak = 0 },
	WheelLast = 0,
	Quests = { Day = 0, List = {} },
	Level = 1,
	Xp = 0,
	SkillPoints = 0, -- 1 per level up; spent in the skill tree (later)
	Boosts = { Xp = 0, Damage = 0, Loot = 0, Credits = 0 }, -- timed x2 boosts: os.time() they end
	LastSeen = 0, -- os.time() of the last save
}
-- Fields from older versions that are migrated / dropped on load
-- (DataService): OwnedBackpacks, EquippedBackpack, OwnedPets, EquippedPet.

-- Version of the save format. Bump it when the format changes and add
-- a step to DataService.Migrations; old saves are upgraded step by step
-- on load and never lose progress.
--   1 = everything before the version number existed
--   2 = Aura is power (never spent), Нано-кредиты, skill points
--   3 = action-RPG: Aura, rebirths and trainers removed (credits as
--       compensation, Config.Migration), x2 boosts in Boosts
Config.SchemaVersion = 3

-- One-time compensation (schema 2 -> 3) for the removed clicker: Aura and
-- rebirths turn into Нано-кредиты. Moderate on purpose.
--   credits = PerAuraDigit x log10(Aura + 1) + PerRebirth x rebirths, capped
Config.Migration = {
	PerAuraDigit = 40, -- 1M Aura -> 240
	PerRebirth = 120, -- 8 rebirths -> 960
	Max = 3000,
	Notice = "Игра обновилась: Аура и перерождения убраны. Компенсация: +%s нано-кредитов!",
}

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
	BaseDamage = 1, -- damage of one hit with a weapon of Damage 1
	Cooldown = 0.1, -- min seconds between accepted clicks at AttackSpeed 1 (anti-macro)
	Range = 60, -- max studs between player and a clicked mob
	MeleeRange = 16, -- a click with no target hits the nearest mob within this range
}

-- Base character stats before any bonus (StatService adds level, gear,
-- set, pets, passes, boosts; class and skills later).
Config.Stats = {
	CritChance = 0.08, -- share of hits that crit
	CritDamage = 2, -- crit hit = damage x this
	AttackSpeed = 1, -- x click rate (cooldown = Click.Cooldown / AttackSpeed)
	Luck = 1, -- x chances of Rare+ drops
	Regen = 6, -- HP per second out of combat (after Player.RegenDelay)
	Dash = 0, -- dash distance in studs (the dash itself comes with classes)
	-- Level: every level above 1 adds these (base stats grow, gear stays
	-- the main source of power).
	DamagePerLevel = 0.05, -- damage x(1 + 0.05 per level): lvl 10 x1.45, 30 x2.45, 50 x3.45
	HealthPerLevel = 6, -- + max HP per level
	DefensePerLevel = 0.002, -- + defense share per level (lvl 30: +5.8%)
	-- Names for the UI (Equipment window).
	Names = {
		Damage = "Урон", MaxHealth = "Макс. HP", Defense = "Защита", AttackSpeed = "Скорость атаки",
		CritChance = "Шанс крита", CritDamage = "Крит. урон", Luck = "Удача", Regen = "Регенерация",
		Dash = "Рывок", GearScore = "Gear Score",
	},
}

-- Damage multiplier of the player's level.
function Config.LevelMult(level: number): number
	return 1 + (math.max(1, level) - 1) * Config.Stats.DamagePerLevel
end

-- Item level ("уровень предмета") of gear. Weapons: from their damage
-- (Stick 1, biome 1 ~10-29, biome 2 ~35-52, biome 3 ~58-76, biome 4
-- ~81-99); armor: the ItemLevel of its set. Gear Score = the sum over the
-- weapon and the three armor slots (empty slot = 0).
Config.ItemLevel = {
	WeaponK = 31, -- weapon item level = 1 + WeaponK x log10(Damage)
}

function Config.ItemLevelOf(item): number
	if not item then
		return 0
	end
	if item.ItemLevel then
		return item.ItemLevel
	end
	return math.floor(1 + Config.ItemLevel.WeaponK * math.log10(math.max(1, item.Damage or 1)))
end

-- "Нано-кредиты": the spendable currency. Earned from
-- mobs (more in deeper rooms, bosses x BossMultiplier), daily reward,
-- quests, the wheel and level rewards. Spent on eggs (and cosmetics).
Config.Credits = {
	Name = "Нано-кредиты",
	Icon = "💠",
	PerKill = 2, -- room 1 mob
	Growth = 1.2, -- x per room: room 10 ~ 10, room 20 ~ 64
	BossMultiplier = 8,
}

-- Timed x2 boosts (data.Boosts[kind] = os.time() it ends; wheel, daily
-- reward and Robux products start them).
Config.BoostKinds = { "Xp", "Damage", "Loot", "Credits" }
Config.BoostNames = { Xp = "Опыт", Damage = "Урон", Loot = "Удача", Credits = "Кредиты" }

function Config.KillCredits(room: number, isBoss: boolean): number
	local c = Config.Credits
	return math.max(1, math.floor(c.PerKill * c.Growth ^ (math.max(1, room) - 1) * (if isBoss then c.BossMultiplier else 1)))
end

-- Robux game passes. Id = 0 means "not created yet": buttons show
-- "Скоро" and nothing is checked. Put the real ids from the Creator
-- Dashboard here (see README).
Config.VipBonus = 0.2 -- VIP: +20% XP and credits (passes Xp2x / Credits2x: x2)

-- Order = position in the store. Icon = emoji on the card.
Config.GamePasses = {
	VIP = { Id = 0, Order = 1, Icon = "👑", Name = "VIP", Price = 199, Text = "+20% опыта и кредитов, VIP-тег" },
	Damage2x = { Id = 0, Order = 2, Icon = "⚔", Name = "x2 Урон", Price = 149, Text = "Навсегда удваивает урон" },
	Xp2x = { Id = 0, Order = 3, Icon = "⭐", Name = "x2 Опыт", Price = 149, Text = "Навсегда удваивает опыт" },
	Credits2x = { Id = 0, Order = 4, Icon = "💠", Name = "x2 Кредиты", Price = 149, Text = "Навсегда удваивает нано-кредиты" },
	TripleEgg = { Id = 0, Order = 5, Icon = "🥚", Name = "Открытие 3 яиц", Price = 249, Text = "Открывай по 3 яйца сразу" },
	FastEgg = { Id = 0, Order = 6, Icon = "💨", Name = "Быстрые яйца", Price = 79, Text = "Вылупление в 3 раза быстрее" },
	Luck = { Id = 0, Order = 7, Icon = "🍀", Name = "Удача x2", Price = 199, Text = "x2 шанс эпических и лучше питомцев" },
	LootLuck = { Id = 0, Order = 8, Icon = "💎", Name = "Удача добычи x2", Price = 199, Text = "x2 шанс редких материалов с мобов" },
	PetSlots = { Id = 0, Order = 9, Icon = "🐾", Name = "+3 слота питомцев", Price = 99, Text = "Носи на 3 питомца больше" },
}

-- Developer Products (bought again and again). Id = 0 -> "Скоро".
-- Kind: Credits (Amount of Нано-кредиты), Boost (Boost + Minutes),
-- Chest (Biome, Rolls: random materials of that biome, loot luck x Luck),
-- Weapon / ArmorSet (exclusive gear, granted once), WheelSkip.
Config.Products = {
	{ Key = "CreditsSmall", Id = 0, Tab = "Packs", Icon = "💠", Name = "Горсть кредитов", Price = 25, Kind = "Credits", Amount = 400 },
	{ Key = "CreditsMedium", Id = 0, Tab = "Packs", Icon = "💠", Name = "Пачка кредитов", Price = 79, Kind = "Credits", Amount = 1500 },
	{ Key = "CreditsLarge", Id = 0, Tab = "Packs", Icon = "💠", Name = "Сейф кредитов", Price = 199, Kind = "Credits", Amount = 5000 },
	{ Key = "WheelSkip", Id = 0, Tab = "Packs", Icon = "🎡", Name = "Крутить колесо сейчас", Price = 25, Kind = "WheelSkip" },

	{ Key = "BoostXp15", Id = 0, Tab = "Boosts", Icon = "⭐", Name = "x2 Опыт · 15 мин", Price = 25, Kind = "Boost", Boost = "Xp", Minutes = 15 },
	{ Key = "BoostXp60", Id = 0, Tab = "Boosts", Icon = "⭐", Name = "x2 Опыт · 60 мин", Price = 69, Kind = "Boost", Boost = "Xp", Minutes = 60 },
	{ Key = "BoostDamage15", Id = 0, Tab = "Boosts", Icon = "⚔", Name = "x2 Урон · 15 мин", Price = 29, Kind = "Boost", Boost = "Damage", Minutes = 15 },
	{ Key = "BoostDamage60", Id = 0, Tab = "Boosts", Icon = "⚔", Name = "x2 Урон · 60 мин", Price = 79, Kind = "Boost", Boost = "Damage", Minutes = 60 },
	{ Key = "BoostLoot15", Id = 0, Tab = "Boosts", Icon = "💎", Name = "x2 Удача добычи · 15 мин", Price = 29, Kind = "Boost", Boost = "Loot", Minutes = 15 },
	{ Key = "BoostLoot60", Id = 0, Tab = "Boosts", Icon = "💎", Name = "x2 Удача добычи · 60 мин", Price = 79, Kind = "Boost", Boost = "Loot", Minutes = 60 },

	{ Key = "ChestCatacombs", Id = 0, Tab = "Chests", Icon = "💀", Name = "Контейнер цеха", Price = 49, Kind = "Chest", Biome = 1, Rolls = 30, Luck = 2 },
	{ Key = "ChestIce", Id = 0, Tab = "Chests", Icon = "❄", Name = "Контейнер криолаборатории", Price = 99, Kind = "Chest", Biome = 2, Rolls = 30, Luck = 2 },
	{ Key = "ChestLava", Id = 0, Tab = "Chests", Icon = "🔥", Name = "Контейнер реактора", Price = 149, Kind = "Chest", Biome = 3, Rolls = 30, Luck = 2 },
	{ Key = "ChestAbyss", Id = 0, Tab = "Chests", Icon = "🌀", Name = "Контейнер Нексуса", Price = 199, Kind = "Chest", Biome = 4, Rolls = 30, Luck = 2 },

	{ Key = "WeaponPatron", Id = 0, Tab = "Exclusive", Icon = "🗡", Name = "Клинок Покровителя", Price = 149, Kind = "Weapon", Item = "PatronBlade" },
	{ Key = "WeaponComet", Id = 0, Tab = "Exclusive", Icon = "☄", Name = "Кометное копьё", Price = 249, Kind = "Weapon", Item = "CometSword" },
	{ Key = "WeaponCrown", Id = 0, Tab = "Exclusive", Icon = "👑", Name = "Коронный излучатель", Price = 399, Kind = "Weapon", Item = "CrownBlade" },
	{ Key = "ArmorRoyal", Id = 0, Tab = "Exclusive", Icon = "🛡", Name = "Королевский сет", Price = 299, Kind = "ArmorSet", Item = "Royal" },
}
Config.ProductById = {} -- [product id] = product (only real ids)
Config.ProductByKey = {}
for _, product in ipairs(Config.Products) do
	Config.ProductByKey[product.Key] = product
	if product.Id > 0 then
		Config.ProductById[product.Id] = product
	end
end
Config.Store = {
	PurchaseStore = "AuraClicker_Purchases_v1", -- PurchaseId -> granted (idempotent receipts)
	DuplicateCreditsPerRobux = 20, -- an exclusive you already own turns into credits
	Tabs = {
		{ Id = "Passes", Text = "Пассы" },
		{ Id = "Packs", Text = "Кредиты" },
		{ Id = "Boosts", Text = "Бусты" },
		{ Id = "Chests", Text = "Сундуки" },
		{ Id = "Exclusive", Text = "Эксклюзив" },
	},
}

Config.Dungeon = {
	Rooms = 20,
	BossEvery = 5, -- rooms 5, 10, 15, 20
	Seed = 2026, -- same layout on every server

	MobsMin = 3,
	MobsMax = 5,

	-- Difficulty curve: "recommended damage" of a room = the damage a
	-- typical player has when they get there (tools/pacing.py). Mob HP =
	-- RecommendedDamage(r) x ClicksToKill: at the recommended damage a mob
	-- takes ~7-8 hits, a boss ~46 (crit 8% x2 included).
	RecommendedRoom1 = 1, -- room 1: a Stick is enough
	RampTo = 5, -- rooms 1..RampTo-1 ramp up to the curve below
	RecommendedBase = 2.85,
	RecommendedGrowth = 1.348,
	LateFrom = 15, -- after this room the curve gets steeper
	LateGrowth = 1.947,
	ClicksToKill = 8,
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
		BossSlamRadius = 16,
		BossSlamWarning = 1, -- seconds the red circle shows before the hit
		BossSlamDamageMultiplier = 4,
	},
}

-- Materials: what mobs drop and what the forge consumes. Biome = index
-- into Config.DungeonLayout.Biomes. Shape = mini-model built from Parts
-- by Shared.MaterialBuilder. Ids are stored in saves: never rename.
Config.Materials = {
	-- 1. Сборочный цех
	{ Id = "Bone", Name = "Болт", Biome = 1, Rarity = "Common", Shape = "Bone", Color = Color3.fromRGB(235, 230, 215) },
	{ Id = "Slime", Name = "Смазка", Biome = 1, Rarity = "Uncommon", Shape = "Blob", Color = Color3.fromRGB(110, 235, 120) },
	{ Id = "RustyIron", Name = "Ржавая пластина", Biome = 1, Rarity = "Rare", Shape = "Ingot", Color = Color3.fromRGB(165, 95, 60) },
	{ Id = "CursedSkull", Name = "Чип управления", Biome = 1, Rarity = "Epic", Shape = "Skull", Color = Color3.fromRGB(190, 120, 255) },
	{ Id = "CatacombHeart", Name = "Сердце фабрики", Biome = 1, Rarity = "Secret", Shape = "Heart", Color = Color3.fromRGB(255, 90, 160) },
	-- 2. Криолаборатория
	{ Id = "Ice", Name = "Криогель", Biome = 2, Rarity = "Common", Shape = "Cube", Color = Color3.fromRGB(170, 225, 255) },
	{ Id = "YetiFur", Name = "Термоизоляция", Biome = 2, Rarity = "Uncommon", Shape = "Fur", Color = Color3.fromRGB(240, 245, 250) },
	{ Id = "FrostCrystal", Name = "Крио-кристалл", Biome = 2, Rarity = "Rare", Shape = "Crystal", Color = Color3.fromRGB(90, 190, 255) },
	{ Id = "EternalIce", Name = "Вечный хладагент", Biome = 2, Rarity = "Legendary", Shape = "Star", Color = Color3.fromRGB(140, 240, 255) },
	-- 3. Плавильный реактор
	{ Id = "Obsidian", Name = "Шлак", Biome = 3, Rarity = "Common", Shape = "Shards", Color = Color3.fromRGB(45, 35, 60) },
	{ Id = "Ember", Name = "Раскалённая окалина", Biome = 3, Rarity = "Uncommon", Shape = "Coal", Color = Color3.fromRGB(255, 130, 40) },
	{ Id = "MagmaCore", Name = "Плазменное ядро", Biome = 3, Rarity = "Rare", Shape = "Core", Color = Color3.fromRGB(255, 110, 30) },
	{ Id = "FirePlume", Name = "Огненный конденсатор", Biome = 3, Rarity = "Epic", Shape = "Feather", Color = Color3.fromRGB(255, 170, 50) },
	{ Id = "VolcanoHeart", Name = "Сердце реактора", Biome = 3, Rarity = "Mythic", Shape = "Heart", Color = Color3.fromRGB(255, 80, 40) },
	-- 4. Ядро Нексуса
	{ Id = "DarkShard", Name = "Осколок данных", Biome = 4, Rarity = "Common", Shape = "Shards", Color = Color3.fromRGB(70, 40, 120) },
	{ Id = "ShadowDust", Name = "Квантовая пыль", Biome = 4, Rarity = "Uncommon", Shape = "Dust", Color = Color3.fromRGB(120, 90, 170) },
	{ Id = "AuraEssence", Name = "Эссенция Нексуса", Biome = 4, Rarity = "Rare", Shape = "Vial", Color = Color3.fromRGB(255, 61, 184) },
	{ Id = "AbyssEye", Name = "Око Нексуса", Biome = 4, Rarity = "Legendary", Shape = "Eye", Color = Color3.fromRGB(170, 80, 255) },
}
Config.MaterialById = {}
for order, material in ipairs(Config.Materials) do
	material.Order = order
	Config.MaterialById[material.Id] = material
end

-- Loot. A drop is personal: only the player whose run killed the mob
-- sees it and can pick it up, and only by HOLDING E (ProximityPrompt).
Config.Loot = {
	HoldSeconds = 0.5,
	Lifetime = 60, -- seconds a drop stays on the ground
	PickupRange = 16, -- server-side distance check
	PromptDistance = 10,
	ExtraDropChance = 0.3, -- normal mobs: 1 drop + this chance of a second one
	BossDrops = 4,
	BossGuaranteed = "Rare", -- the first boss drop is at least this rarity
	BossLuck = 4, -- boss drops: chances of Rare+ multiplied by this
	LuckFrom = "Rare", -- luck multiplies this rarity and everything above
	FloatHeight = 2.4,
	SpreadRadius = 4.5, -- several drops lie on a circle of this radius around the kill
	BossSpreadRadius = 7,
	DetailDistance = 14, -- closer than this the plate shows name + rarity; farther only a small name tag
	PlateSmall = Vector2.new(120, 26),
	PlateFull = Vector2.new(160, 46),
	SpinSeconds = 4,
	BeamHeight = 14,
	Texts = {
		Pickup = "Подобрать",
		Announce = "%s выбил %s предмет: %s!",
		Picked = "+%d %s",
	},
}

-- Mobs of the Nano-factory: 3 kinds + a boss per biome. Asset = owner
-- model (GameAssets/Mobs, MobBuilder); one model can serve several mobs:
-- Height in studs (bosses x Config.MobLooks.BossScale), Tint = color the
-- parts lean to (TintAmount 0..1), Glow = color of neon parts, Turn =
-- degrees to turn the model if it faces backwards. No model -> the
-- procedural mob Builder. Drops = materials this mob can drop; the rarity
-- is rolled first (Config.Rarities), then a material of that rarity is
-- picked from this list (nearest lower rarity, else the nearest higher).
Config.Mobs = {
	Biomes = {
		{ Kinds = { "SpiderBot", "Assembler", "Loader" }, Boss = "ForemanMech" },
		{ Kinds = { "CryoBot", "CryoAndroid", "FrostSpider" }, Boss = "CryoOverseer" },
		{ Kinds = { "Smelter", "HeavyMech", "SlagBot" }, Boss = "MoltenColossus" },
		{ Kinds = { "NexusSentinel", "NexusDrone", "PhaseAndroid" }, Boss = "Juggernaut" },
	},
	Defs = {
		-- 1. Сборочный цех
		SpiderBot = { Name = "Паукобот", Asset = "Mob_SpiderBot", Height = 3.6, Builder = "IceSpider", Drops = { "Bone", "Slime", "RustyIron", "CatacombHeart" } },
		Assembler = { Name = "Робот-сборщик", Asset = "Mob_Robot", Height = 5.5, Builder = "ZombieMiner", Drops = { "Bone", "RustyIron", "CursedSkull", "CatacombHeart" } },
		Loader = { Name = "Бот-погрузчик", Asset = "Mob_Bot2", Height = 5, Builder = "SkeletonArcher", Drops = { "Slime", "Bone", "CursedSkull", "CatacombHeart" } },
		ForemanMech = { Name = "Мех-бригадир", Boss = true, Asset = "Mob_Mech", Height = 6, Tint = Color3.fromRGB(255, 170, 60), TintAmount = 0.25, Glow = Color3.fromRGB(255, 190, 70), Builder = "SlimeKing", Drops = { "Bone", "Slime", "RustyIron", "CursedSkull", "CatacombHeart" } },
		-- 2. Криолаборатория
		CryoBot = { Name = "Крио-бот", Asset = "Mob_BlueBot", Height = 5, Glow = Color3.fromRGB(120, 230, 255), Builder = "SnowGolem", Drops = { "Ice", "FrostCrystal", "EternalIce" } },
		CryoAndroid = { Name = "Крио-андроид", Asset = "Mob_Android", Height = 6, Tint = Color3.fromRGB(170, 220, 255), TintAmount = 0.4, Glow = Color3.fromRGB(46, 230, 255), Builder = "Yeti", Drops = { "YetiFur", "FrostCrystal", "EternalIce" } },
		FrostSpider = { Name = "Ледяной паукобот", Asset = "Mob_SpiderBot", Height = 4.2, Tint = Color3.fromRGB(160, 215, 255), TintAmount = 0.5, Glow = Color3.fromRGB(120, 230, 255), Builder = "IceSpider", Drops = { "Ice", "YetiFur", "FrostCrystal", "EternalIce" } },
		CryoOverseer = { Name = "Крио-надзиратель", Boss = true, Asset = "Mob_Overseer", Height = 6, Tint = Color3.fromRGB(150, 210, 255), TintAmount = 0.45, Glow = Color3.fromRGB(46, 230, 255), Builder = "IceBoneLord", Drops = { "Ice", "YetiFur", "FrostCrystal", "EternalIce" } },
		-- 3. Плавильный реактор
		Smelter = { Name = "Андроид-плавильщик", Asset = "Mob_RedAndroid", Height = 6, Glow = Color3.fromRGB(255, 140, 40), Builder = "FireImp", Drops = { "Ember", "Obsidian", "FirePlume", "VolcanoHeart" } },
		HeavyMech = { Name = "Тяжёлый мех", Asset = "Mob_Mech", Height = 6.5, Tint = Color3.fromRGB(90, 70, 60), TintAmount = 0.4, Glow = Color3.fromRGB(255, 120, 30), Builder = "MagmaGolem", Drops = { "Obsidian", "MagmaCore", "FirePlume", "VolcanoHeart" } },
		SlagBot = { Name = "Шлакобот", Asset = "Mob_Bot2", Height = 5, Tint = Color3.fromRGB(255, 130, 40), TintAmount = 0.4, Glow = Color3.fromRGB(255, 160, 60), Builder = "GoblinSmith", Drops = { "Obsidian", "Ember", "MagmaCore", "VolcanoHeart" } },
		MoltenColossus = { Name = "Плавильный колосс", Boss = true, Asset = "Mob_Android", Height = 6.2, Tint = Color3.fromRGB(255, 110, 30), TintAmount = 0.45, Glow = Color3.fromRGB(255, 150, 40), Builder = "FireChief", Drops = { "Obsidian", "Ember", "MagmaCore", "FirePlume", "VolcanoHeart" } },
		-- 4. Ядро Нексуса
		NexusSentinel = { Name = "Страж Нексуса", Asset = "Mob_Overseer", Height = 6, Tint = Color3.fromRGB(120, 60, 200), TintAmount = 0.4, Glow = Color3.fromRGB(255, 61, 184), Builder = "ShadowKnight", Drops = { "DarkShard", "ShadowDust", "AuraEssence", "AbyssEye" } },
		NexusDrone = { Name = "Дрон Нексуса", Asset = "Mob_Robot", Height = 5.5, Tint = Color3.fromRGB(150, 80, 255), TintAmount = 0.45, Glow = Color3.fromRGB(255, 61, 184), Builder = "FlyingEye", Drops = { "DarkShard", "AuraEssence", "AbyssEye" } },
		PhaseAndroid = { Name = "Фазовый андроид", Asset = "Mob_RedAndroid", Height = 6, Tint = Color3.fromRGB(170, 80, 255), TintAmount = 0.5, Glow = Color3.fromRGB(46, 230, 255), Builder = "AuraGhost", Drops = { "ShadowDust", "AuraEssence", "AbyssEye" } },
		Juggernaut = { Name = "Джаггернаут", Boss = true, Asset = "Boss_Juggernaut", Height = 6.4, Glow = Color3.fromRGB(255, 61, 184), Builder = "AbyssLord", Drops = { "DarkShard", "ShadowDust", "AuraEssence", "AbyssEye" } },
	},
}
for id, def in pairs(Config.Mobs.Defs) do
	def.Id = id
end

-- The mob definition for a room: a boss in boss rooms, else kind 1..3.
function Config.MobFor(room: number, kindIndex: number)
	local biome = Config.Mobs.Biomes[math.min(#Config.Mobs.Biomes, math.ceil(room / Config.Dungeon.BossEvery))]
	if Config.IsBossRoom(room) then
		return Config.Mobs.Defs[biome.Boss]
	end
	return Config.Mobs.Defs[biome.Kinds[(kindIndex - 1) % #biome.Kinds + 1]]
end

-- The player in combat. Health regenerates only when nothing hit the
-- player for RegenDelay seconds (the default Roblox regen is disabled).
Config.Player = {
	Health = 100, -- base max health (+ level, + armor)
	RegenDelay = 4, -- seconds without being hit before regen starts (rate: Stats.Regen)
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
-- Damage per hit a player "should" have for a room. Three parts:
--   rooms 1..RampTo-1: smooth ramp (log scale) from RecommendedRoom1,
--   rooms RampTo..LateFrom: RecommendedBase x RecommendedGrowth^(room - 1),
--   rooms after LateFrom: x LateGrowth per room (the long-term goal).
function Config.RecommendedDamage(room: number): number
	local d = Config.Dungeon
	local value
	if room > d.LateFrom then
		value = d.RecommendedBase * d.RecommendedGrowth ^ (d.LateFrom - 1) * d.LateGrowth ^ (room - d.LateFrom)
	elseif room >= d.RampTo then
		value = d.RecommendedBase * d.RecommendedGrowth ^ (room - 1)
	else
		local target = d.RecommendedBase * d.RecommendedGrowth ^ (d.RampTo - 1)
		local a = (room - 1) / (d.RampTo - 1)
		value = math.exp(math.log(d.RecommendedRoom1) * (1 - a) + math.log(target) * a)
	end
	return math.max(1, math.floor(value))
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

-- Weapons: Damage is the weapon base (see Config.Damage for the full
-- formula). One weapon is active. Weapons are CRAFTED at the forge from
-- materials (Config.Recipes): 4 per biome, each stronger than the last.
-- Class = Blade (Клинок: swords) / Pulse (Импульс: spears) / Gunner
-- (Стрелок: blasters): picks the owner model (Config.Assets.WeaponModels).
-- Shape = procedural fallback model (Shared.WeaponBuilder). Legacy = bought in an
-- older version of the game: still owned and usable, not craftable.
-- Ids are stored in saves: never rename.
Config.Weapons = {
	{ Id = "Stick", Name = "Обрезок трубы", Rarity = "Common", Damage = 1, Class = "Blade", Shape = "Stick", Color = Color3.fromRGB(150, 110, 70) },
	-- 1. Катакомбы
	{ Id = "BoneSword", Name = "Нано-клинок", Rarity = "Common", Damage = 2, Class = "Blade", Biome = 1, Shape = "BoneSword", Color = Color3.fromRGB(235, 230, 215) },
	{ Id = "SlimeDagger", Name = "Ионное копьё", Rarity = "Uncommon", Damage = 3, Class = "Pulse", Biome = 1, Shape = "SlimeDagger", Color = Color3.fromRGB(110, 235, 120) },
	{ Id = "RustCleaver", Name = "Плазменный бластер", Rarity = "Rare", Damage = 5, Class = "Gunner", Biome = 1, Shape = "Cleaver", Color = Color3.fromRGB(165, 95, 60) },
	{ Id = "SkullMace", Name = "Клинок-резак", Rarity = "Epic", Damage = 8, Class = "Blade", Biome = 1, Shape = "SkullMace", Color = Color3.fromRGB(190, 120, 255) },
	-- 2. Ледяной грот
	{ Id = "IceBlade", Name = "Крио-клинок", Rarity = "Uncommon", Damage = 12, Class = "Blade", Biome = 2, Shape = "IceBlade", Color = Color3.fromRGB(170, 225, 255) },
	{ Id = "YetiClub", Name = "Крио-копьё", Rarity = "Rare", Damage = 18, Class = "Pulse", Biome = 2, Shape = "YetiClub", Color = Color3.fromRGB(240, 245, 250) },
	{ Id = "FrostSpear", Name = "Крио-бластер", Rarity = "Epic", Damage = 28, Class = "Gunner", Biome = 2, Shape = "FrostSpear", Color = Color3.fromRGB(90, 190, 255) },
	{ Id = "EternalBlade", Name = "Клинок абсолютного нуля", Rarity = "Legendary", Damage = 43, Class = "Blade", Biome = 2, Shape = "EternalBlade", Color = Color3.fromRGB(140, 240, 255) },
	-- 3. Лавовая кузня
	{ Id = "ObsidianAxe", Name = "Термо-клинок", Rarity = "Rare", Damage = 66, Class = "Blade", Biome = 3, Shape = "ObsidianAxe", Color = Color3.fromRGB(60, 45, 80) },
	{ Id = "EmberSword", Name = "Плазменное копьё", Rarity = "Epic", Damage = 100, Class = "Pulse", Biome = 3, Shape = "EmberSword", Color = Color3.fromRGB(255, 130, 40) },
	{ Id = "MagmaHammer", Name = "Магма-пушка", Rarity = "Epic", Damage = 160, Class = "Gunner", Biome = 3, Shape = "MagmaHammer", Color = Color3.fromRGB(255, 110, 30) },
	{ Id = "PhoenixBlade", Name = "Клинок ядра", Rarity = "Legendary", Damage = 250, Class = "Blade", Biome = 3, Shape = "PhoenixBlade", Color = Color3.fromRGB(255, 170, 50) },
	-- 4. Бездна ауры
	{ Id = "ShadowKatana", Name = "Клинок Нексуса", Rarity = "Epic", Damage = 380, Class = "Blade", Biome = 4, Shape = "ShadowKatana", Color = Color3.fromRGB(120, 90, 170) },
	{ Id = "DuskScythe", Name = "Копьё сингулярности", Rarity = "Legendary", Damage = 600, Class = "Pulse", Biome = 4, Shape = "DuskScythe", Color = Color3.fromRGB(170, 80, 255) },
	{ Id = "AbyssBlade", Name = "Аннигилятор", Rarity = "Legendary", Damage = 920, Class = "Gunner", Biome = 4, Shape = "AbyssBlade", Color = Color3.fromRGB(255, 61, 184) },
	{ Id = "AuraReaver", Name = "Разрушитель Нексуса", Rarity = "Mythic", Damage = 1450, Class = "Blade", Biome = 4, Shape = "AuraReaver", Color = Color3.fromRGB(255, 230, 120) },
	-- Robux exclusives (Config.Products): a bit stronger than the tier they
	-- become available at, weaker than the next biome's top weapon.
	{ Id = "PatronBlade", Name = "Клинок Покровителя", Rarity = "Epic", Damage = 10, Class = "Blade", Robux = true, Shape = "StormBlade", Color = Color3.fromRGB(90, 200, 255) },
	{ Id = "CometSword", Name = "Кометное копьё", Rarity = "Legendary", Damage = 55, Class = "Pulse", Robux = true, Shape = "StarAuraSword", Color = Color3.fromRGB(255, 150, 90) },
	{ Id = "CrownBlade", Name = "Коронный излучатель", Rarity = "Mythic", Damage = 300, Class = "Gunner", Robux = true, Shape = "AuraKatana", Color = Color3.fromRGB(255, 215, 80) },
	-- Legacy (from old versions of the game): still owned and usable,
	-- not craftable. Damage kept low so old saves don't one-shot the dungeon.
	{ Id = "WoodSword", Name = "Деревянный меч", Rarity = "Common", Damage = 2, Class = "Blade", Legacy = true, Shape = "WoodSword", Color = Color3.fromRGB(200, 150, 90) },
	{ Id = "IronSword", Name = "Железный меч", Rarity = "Rare", Damage = 4, Class = "Blade", Legacy = true, Shape = "IronSword", Color = Color3.fromRGB(190, 200, 215) },
	{ Id = "AuraKatana", Name = "Катана Ауры", Rarity = "Epic", Damage = 8, Class = "Blade", Legacy = true, Shape = "AuraKatana", Color = Color3.fromRGB(190, 110, 255) },
	{ Id = "StormBlade", Name = "Клинок Бури", Rarity = "Legendary", Damage = 15, Class = "Blade", Legacy = true, Shape = "StormBlade", Color = Color3.fromRGB(90, 200, 255) },
	{ Id = "EclipseScythe", Name = "Коса Затмения", Rarity = "Legendary", Damage = 30, Class = "Blade", Legacy = true, Shape = "EclipseScythe", Color = Color3.fromRGB(255, 120, 60) },
	{ Id = "StarAuraSword", Name = "Меч Звёздной Ауры", Rarity = "Mythic", Damage = 50, Class = "Blade", Legacy = true, Shape = "StarAuraSword", Color = Color3.fromRGB(255, 230, 120) },
}

-- Armor: one set per biome, three pieces each (Helmet / Chest / Legs).
-- Health adds to the base Config.Player.Health, Defense is the share of
-- incoming damage removed. Wearing all 3 pieces of a set gives its
-- Bonus (damage multiplier). Style = look built by Shared.ArmorBuilder.
Config.ArmorSlots = { "Helmet", "Chest", "Legs" }
Config.ArmorSlotNames = { Helmet = "Шлем", Chest = "Нагрудник", Legs = "Поножи" }
Config.ArmorSets = {
	Bone = { Name = "Сет монтажника", Biome = 1, Rarity = "Uncommon", Health = 20, Defense = 0.03, Bonus = 0.10, ItemLevel = 20,
		Style = { Kind = "Assembly", Main = Color3.fromRGB(70, 74, 84), Trim = Color3.fromRGB(255, 176, 50), Glow = Color3.fromRGB(255, 190, 70), Visor = Color3.fromRGB(30, 34, 40), Material = Enum.Material.Metal } },
	Ice = { Name = "Крио-сет", Biome = 2, Rarity = "Rare", Health = 45, Defense = 0.05, Bonus = 0.20, ItemLevel = 45,
		Style = { Kind = "Cryo", Main = Color3.fromRGB(226, 234, 244), Trim = Color3.fromRGB(120, 150, 180), Glow = Color3.fromRGB(46, 230, 255), Visor = Color3.fromRGB(140, 220, 255), Material = Enum.Material.SmoothPlastic } },
	Lava = { Name = "Термо-сет", Biome = 3, Rarity = "Epic", Health = 90, Defense = 0.07, Bonus = 0.35, ItemLevel = 70,
		Style = { Kind = "Thermo", Main = Color3.fromRGB(46, 42, 44), Trim = Color3.fromRGB(110, 70, 50), Glow = Color3.fromRGB(255, 120, 30), Visor = Color3.fromRGB(255, 140, 40), Material = Enum.Material.DiamondPlate } },
	Abyss = { Name = "Сет Нексуса", Biome = 4, Rarity = "Legendary", Health = 160, Defense = 0.09, Bonus = 0.50, ItemLevel = 95,
		Style = { Kind = "Nexus", Main = Color3.fromRGB(34, 26, 52), Trim = Color3.fromRGB(110, 70, 190), Glow = Color3.fromRGB(255, 61, 184), Visor = Color3.fromRGB(255, 61, 184), Material = Enum.Material.Metal } },
	-- Robux exclusive (Config.Products "ArmorRoyal"): between Ice and Lava.
	Royal = { Name = "Королевский сет", Rarity = "Legendary", Health = 70, Defense = 0.06, Bonus = 0.28, ItemLevel = 60, Robux = true,
		Style = { Kind = "Royal", Main = Color3.fromRGB(240, 240, 248), Trim = Color3.fromRGB(255, 201, 60), Glow = Color3.fromRGB(46, 230, 255), Visor = Color3.fromRGB(46, 230, 255), Material = Enum.Material.Metal } },
}
Config.ArmorSetOrder = { "Bone", "Ice", "Lava", "Abyss", "Royal" }
Config.Armor = {}
do
	local adjective = { Bone = { "Монтажный", "Монтажные" }, Ice = { "Крио-", "Крио-" }, Lava = { "Термо-", "Термо-" }, Royal = { "Королевский", "Королевские" } }
	local noun = { Helmet = "шлем", Chest = "нагрудник", Legs = "поножи" }
	local nounCapital = { Helmet = "Шлем", Chest = "Нагрудник", Legs = "Поножи" }
	for _, setId in ipairs(Config.ArmorSetOrder) do
		local set = Config.ArmorSets[setId]
		set.Id = setId
		for _, slot in ipairs(Config.ArmorSlots) do
			local adj = adjective[setId] and adjective[setId][if slot == "Legs" then 2 else 1]
			local name = if setId == "Abyss" then nounCapital[slot] .. " Нексуса"
				elseif adj and string.sub(adj, -1) == "-" then adj .. noun[slot]
				else adj .. " " .. noun[slot]
			table.insert(Config.Armor, {
				Id = setId .. slot, -- "BoneHelmet", "IceChest", ... (stored in saves)
				Name = name,
				Slot = slot,
				Set = setId,
				Biome = set.Biome,
				Rarity = set.Rarity,
				Health = if slot == "Chest" then math.floor(set.Health * 1.5) else set.Health,
				Defense = set.Defense,
				ItemLevel = set.ItemLevel,
				Color = set.Style.Main,
			})
		end
	end
end

-- Forge recipes: materials -> the item (Id = weapon or
-- armor id). Shown in this order inside each tab.
Config.Recipes = {
	-- Weapons
	{ Id = "BoneSword", Kind = "Weapon", Materials = { Bone = 8 } },
	{ Id = "SlimeDagger", Kind = "Weapon", Materials = { Bone = 12, Slime = 6 } },
	{ Id = "RustCleaver", Kind = "Weapon", Materials = { Bone = 20, RustyIron = 4 } },
	{ Id = "SkullMace", Kind = "Weapon", Materials = { Bone = 30, Slime = 12, RustyIron = 6, CursedSkull = 1 } },
	{ Id = "IceBlade", Kind = "Weapon", Materials = { Ice = 15, RustyIron = 3 } },
	{ Id = "YetiClub", Kind = "Weapon", Materials = { Ice = 25, YetiFur = 10 } },
	{ Id = "FrostSpear", Kind = "Weapon", Materials = { Ice = 40, YetiFur = 15, FrostCrystal = 6 } },
	{ Id = "EternalBlade", Kind = "Weapon", Materials = { Ice = 60, FrostCrystal = 10, EternalIce = 1 } },
	{ Id = "ObsidianAxe", Kind = "Weapon", Materials = { Obsidian = 30, Ember = 10 } },
	{ Id = "EmberSword", Kind = "Weapon", Materials = { Obsidian = 45, Ember = 20, MagmaCore = 5 } },
	{ Id = "MagmaHammer", Kind = "Weapon", Materials = { Obsidian = 70, MagmaCore = 8, FirePlume = 2 } },
	{ Id = "PhoenixBlade", Kind = "Weapon", Materials = { Obsidian = 100, MagmaCore = 14, FirePlume = 5 } },
	{ Id = "ShadowKatana", Kind = "Weapon", Materials = { DarkShard = 40, ShadowDust = 15 } },
	{ Id = "DuskScythe", Kind = "Weapon", Materials = { DarkShard = 60, ShadowDust = 25, AuraEssence = 8 } },
	{ Id = "AbyssBlade", Kind = "Weapon", Materials = { DarkShard = 90, AuraEssence = 12, AbyssEye = 1 } },
	{ Id = "AuraReaver", Kind = "Weapon", Materials = { DarkShard = 140, AuraEssence = 20, AbyssEye = 3, EternalIce = 2 } },
	-- Armor
	{ Id = "BoneHelmet", Kind = "Armor", Materials = { Bone = 10, Slime = 3 } },
	{ Id = "BoneChest", Kind = "Armor", Materials = { Bone = 18, Slime = 6, RustyIron = 2 } },
	{ Id = "BoneLegs", Kind = "Armor", Materials = { Bone = 14, Slime = 4 } },
	{ Id = "IceHelmet", Kind = "Armor", Materials = { Ice = 20, YetiFur = 8 } },
	{ Id = "IceChest", Kind = "Armor", Materials = { Ice = 35, YetiFur = 14, FrostCrystal = 4 } },
	{ Id = "IceLegs", Kind = "Armor", Materials = { Ice = 28, YetiFur = 10, FrostCrystal = 2 } },
	{ Id = "LavaHelmet", Kind = "Armor", Materials = { Obsidian = 35, Ember = 12, MagmaCore = 3 } },
	{ Id = "LavaChest", Kind = "Armor", Materials = { Obsidian = 60, Ember = 20, MagmaCore = 6, FirePlume = 1 } },
	{ Id = "LavaLegs", Kind = "Armor", Materials = { Obsidian = 45, Ember = 15, MagmaCore = 4 } },
	{ Id = "AbyssHelmet", Kind = "Armor", Materials = { DarkShard = 50, ShadowDust = 20, AuraEssence = 5 } },
	{ Id = "AbyssChest", Kind = "Armor", Materials = { DarkShard = 80, ShadowDust = 30, AuraEssence = 10, AbyssEye = 1 } },
	{ Id = "AbyssLegs", Kind = "Armor", Materials = { DarkShard = 60, ShadowDust = 24, AuraEssence = 6 } },
}
Config.RecipeById = {}
for order, recipe in ipairs(Config.Recipes) do
	recipe.Order = order
	Config.RecipeById[recipe.Id] = recipe
end

Config.Forge = {
	AnimationSeconds = 2.5,
	Strikes = 3,
	Texts = {
		Craft = "Выковать",
		Owned = "Уже выковано ✓",
		Missing = "Не хватает материалов",
		Skip = "Пропустить",
		Done = "Выковано: %s!",
	},
}

-- Pets hatch from eggs (Нано-кредиты) and follow the player. Every
-- equipped pet adds small stat bonuses x its tier multiplier: Damage and
-- Health are shares (0.02 = +2% damage). Three equal pets of one tier merge into one of the
-- next tier. Shape = look built by Shared.PetBuilder. Ids are stored in
-- saves: never rename.
Config.Pets = {
	{ Id = "Blob", Name = "Слизнячок", Rarity = "Common", Damage = 0.02, Health = 0.03, Shape = "Blob", Color = Color3.fromRGB(110, 235, 120), Size = 1.3 },
	{ Id = "Bunny", Name = "Ушастик", Rarity = "Common", Damage = 0.02, Health = 0.04, Shape = "Ears", Color = Color3.fromRGB(245, 235, 240), Size = 1.3 },
	{ Id = "Bat", Name = "Летучая мышка", Rarity = "Uncommon", Damage = 0.03, Health = 0.05, Shape = "Wings", Color = Color3.fromRGB(120, 90, 170), Size = 1.3 },
	{ Id = "Spark", Name = "Искорка", Rarity = "Rare", Damage = 0.05, Health = 0.06, Shape = "Star", Color = Color3.fromRGB(255, 220, 90), Size = 1.4 },
	{ Id = "IceFox", Name = "Ледяной лис", Rarity = "Rare", Damage = 0.05, Health = 0.08, Shape = "Ears", Color = Color3.fromRGB(170, 225, 255), Size = 1.5 },
	{ Id = "Imp", Name = "Бесёнок", Rarity = "Epic", Damage = 0.08, Health = 0.08, Shape = "Horns", Color = Color3.fromRGB(240, 90, 60), Size = 1.5 },
	{ Id = "Golem", Name = "Мини-голем", Rarity = "Epic", Damage = 0.07, Health = 0.12, Shape = "Crystal", Color = Color3.fromRGB(150, 80, 255), Size = 1.6 },
	{ Id = "Dragon", Name = "Дракончик Ауры", Rarity = "Legendary", Damage = 0.12, Health = 0.12, Shape = "Wings", Color = Color3.fromRGB(170, 90, 255), Size = 2 },
	{ Id = "Phoenix", Name = "Феникс", Rarity = "Legendary", Damage = 0.14, Health = 0.14, Shape = "Wings", Color = Color3.fromRGB(255, 150, 40), Size = 2 },
	{ Id = "AbyssEye", Name = "Око бездны", Rarity = "Mythic", Damage = 0.2, Health = 0.2, Shape = "Eye", Color = Color3.fromRGB(255, 61, 184), Size = 2 },
}
Config.PetById = {}
for order, pet in ipairs(Config.Pets) do
	pet.Order = order
	Config.PetById[pet.Id] = pet
end

Config.PetTiers = {
	{ Name = "", Multiplier = 1 },
	{ Name = "Золотой", Multiplier = 1.6, Color = Color3.fromRGB(255, 201, 60) },
	{ Name = "Радужный", Multiplier = 2.5, Color = Color3.fromRGB(255, 120, 220), Rainbow = true },
}
Config.PetMerge = 3 -- equal pets merged into one of the next tier
Config.PetSlots = 3 -- equipped at once (+ PetSlotsPass with the pass)
Config.PetSlotsPass = 3
Config.PetStorage = 100 -- max pets kept

-- Eggs: price in Нано-кредиты (Cost) and the weight of each pet. Luck (pass / boost)
-- multiplies the weight of Epic and better pets.
Config.Eggs = {
	{ Id = "Basic", Name = "Обычное яйцо", Cost = 150, Color = Color3.fromRGB(240, 235, 225),
		Pets = { { Id = "Blob", Weight = 45 }, { Id = "Bunny", Weight = 35 }, { Id = "Bat", Weight = 15 }, { Id = "Spark", Weight = 5 } } },
	{ Id = "Crystal", Name = "Кристальное яйцо", Cost = 2000, Color = Color3.fromRGB(150, 220, 255),
		Pets = { { Id = "Bat", Weight = 40 }, { Id = "Spark", Weight = 28 }, { Id = "IceFox", Weight = 22 }, { Id = "Imp", Weight = 8 }, { Id = "Dragon", Weight = 2 } } },
	{ Id = "Abyss", Name = "Яйцо бездны", Cost = 25000, Color = Color3.fromRGB(170, 80, 255),
		Pets = { { Id = "IceFox", Weight = 35 }, { Id = "Imp", Weight = 28 }, { Id = "Golem", Weight = 22 }, { Id = "Dragon", Weight = 9 }, { Id = "Phoenix", Weight = 5 }, { Id = "AbyssEye", Weight = 1 } } },
}
Config.EggById = {}
for _, egg in ipairs(Config.Eggs) do
	Config.EggById[egg.Id] = egg
end
Config.Hatch = {
	Seconds = 2.2, -- hatch animation
	FastSeconds = 0.8, -- with the "Быстрые яйца" pass
	TripleCount = 3, -- eggs per hatch with the "Открытие 3 яиц" pass
	LuckFrom = "Epic",
}

-- Pacing model for tools/pacing.py (not used by the game itself): how a
-- typical active player plays, and the owner's time targets. The tool
-- simulates dungeon runs (kills -> XP, credits, materials), crafting and
-- levels with the formulas above; `--tune` suggests XpBase and the room
-- curve (RecommendedRoom1 / Base / Growth) so that the recommended damage
-- of a room = the real damage of a player who gets there on time;
-- `--readme` writes the minute table into README.md.
Config.Pacing = {
	HitsPerSecond = 4, -- attack clicks per second while fighting
	MoveSeconds = 2.5, -- walking to the next mob
	RoomSeconds = 5, -- walking through a doorway / corridor
	RunOverhead = 30, -- back to the hub, forge, portal between runs
	Targets = {
		Stages = { ["1"] = 1, ["5"] = 15, ["10"] = 60, ["15"] = 120, ["20"] = 420 },
		Level = 30,
		LevelMinute = 120,
	},
	ReportMinutes = { 1, 3, 5, 10, 15, 20, 30, 45, 60, 75, 90, 105, 120, 150, 180, 240, 300, 360, 420 },
}

-- Engagement loop: things to do every few minutes.
-- Rewards are Нано-кредиты / XP / boosts and scale with the record room.
Config.Progression = {
	Daily = {
		CooldownHours = 20, -- can claim again after this
		StreakWindowHours = 48, -- longer gap resets the streak
		Credits = { 25, 40, 60, 90, 130, 180, 300 }, -- day 1..7 (Нано-кредиты), x (1 + record room / 4)
		Day7Boost = true, -- day 7 also grants a boost
	},
	Wheel = {
		CooldownHours = 4,
		Prizes = { -- weights sum does not need to be 100; Credits x (1 + record room / 4)
			{ Kind = "Credits", Amount = 30, Weight = 30, Label = "Кредиты" },
			{ Kind = "Credits", Amount = 80, Weight = 22, Label = "Кредиты+" },
			{ Kind = "Credits", Amount = 250, Weight = 10, Label = "Много кредитов" },
			{ Kind = "Boost", Minutes = 15, Weight = 16, Label = "x2 Опыт 15 мин" },
			{ Kind = "Credits", Amount = 50, Weight = 12, Label = "Кредиты" },
			{ Kind = "Egg", Weight = 6, Label = "Яйцо питомца" },
			{ Kind = "Credits", Amount = 120, Weight = 10, Label = "Кредиты++" },
			{ Kind = "Boost", Minutes = 30, Weight = 4, Label = "x2 Опыт 30 мин" },
		},
	},
	Boost = { Multiplier = 2 }, -- every timed boost (Config.BoostKinds) doubles its stat
	Quests = { -- 3 per day are picked from this pool
		Pool = {
			{ Id = "kill30", Kind = "Kill", Target = 30, Text = "Убей 30 мобов", Credits = 40 },
			{ Id = "kill80", Kind = "Kill", Target = 80, Text = "Убей 80 мобов", Credits = 110 },
			{ Id = "room5", Kind = "Room", Target = 5, Text = "Дойди до этапа 5", Credits = 60 },
			{ Id = "room10", Kind = "Room", Target = 10, Text = "Дойди до этапа 10", Credits = 180 },
			{ Id = "boss2", Kind = "Boss", Target = 2, Text = "Победи 2 боссов", Credits = 120 },
			{ Id = "runs3", Kind = "Run", Target = 3, Text = "Соверши 3 забега", Credits = 45 },
		},
		PerDay = 3,
	},
	-- Player level. XP: kills, bosses, quests and a little for training.
	-- Every level: +SkillPointsPerLevel skill point, damage and max HP grow
	-- (Config.Stats), full heal.
	--   XP to the next level = XpBase x level^XpExponent:
	--   lvl 1 -> 49, 10 -> 1.55K, 30 -> 8K, 50 -> 17K
	--   (tuned with tools/pacing.py: level ~30 after 2 hours)
	Level = {
		XpBase = 49,
		XpExponent = 1.5,
		XpPerKill = 10, -- x room index
		XpPerBoss = 80, -- x room index
		XpPerQuest = 40, -- x player level, when a quest reward is claimed
		SkillPointsPerLevel = 1,
		RewardEvery = 5, -- levels
		RewardCredits = 20, -- every RewardEvery levels: x level
		Texts = {
			Title = "Новый уровень!",
			Points = "+%d очко навыка",
			Growth = "Урон %s  •  Макс. HP %s",
		},
	},
}

-- XP needed for the next level at `level` (formula above).
function Config.XpToNext(level: number): number
	local l = Config.Progression.Level
	return math.floor(l.XpBase * math.max(1, level) ^ l.XpExponent)
end

-- Equipment on the character (visual only). Grip = offset of the weapon
-- Handle from the hand part.
Config.Equipment = {
	GripR6 = CFrame.new(0, -1, -0.6) * CFrame.Angles(math.rad(-90), 0, 0),
	GripR15 = CFrame.new(0, -0.3, -0.6) * CFrame.Angles(math.rad(-90), 0, 0),
}

-- Weapon swing. Procedural by default: the right shoulder Motor6D goes
-- base -> Wind -> Strike -> base (rotations are in the torso's space:
-- X = pitch forward, Y = yaw, applied as Yaw * Pitch) while the torso
-- leans by Lean degrees. The variants are played in turn.
-- SwingIds: put your own uploaded animation ids here (rbxassetid://...)
-- and they are played instead, in turn. Never guess ids.
Config.Animations = {
	SwingIds = {},
	MaxTracks = 24, -- an Animator never plays more (Roblox errors at 64)
	Swing = {
		WindSeconds = 0.07,
		StrikeSeconds = 0.08,
		ReturnSeconds = 0.09,
		TrailSeconds = 0.3,
		Variants = {
			{ Name = "Overhead", Wind = { Pitch = 165, Yaw = 0 }, Strike = { Pitch = 35, Yaw = 0 }, Lean = 14 },
			{ Name = "Horizontal", Wind = { Pitch = 90, Yaw = -75 }, Strike = { Pitch = 90, Yaw = 60 }, Lean = 6, Twist = 22 },
			{ Name = "Thrust", Wind = { Pitch = -30, Yaw = 0 }, Strike = { Pitch = 95, Yaw = 0 }, Lean = 18 },
		},
	},
}

-- Leaderboards (OrderedDataStore). Scores are written on every save.
Config.Leaderboards = {
	LevelStore = "AuraClicker_TopLevel_v1",
	RoomStore = "AuraClicker_TopRoom_v1",
	RefreshSeconds = 60,
	Top = 10,
}

-- Shop categories (what is owned / equipped and how to describe it).
Config.Shop = {
	Weapon = { Title = "Оружие", Items = Config.Weapons, OwnedKey = "OwnedWeapons", EquippedKey = "EquippedWeapon", Purchasable = false,
		Describe = function(item) return "Урон " .. item.Damage end },
}

Config.ItemById = {} -- [category][id] = item
for category, shop in pairs(Config.Shop) do
	Config.ItemById[category] = {}
	for _, item in ipairs(shop.Items) do
		Config.ItemById[category][item.Id] = item
	end
end

Config.ItemById.Armor = {}
for order, piece in ipairs(Config.Armor) do
	piece.Order = order
	Config.ItemById.Armor[piece.Id] = piece
end

-- Owner-made models (ServerStorage/GameAssets/<Category>/<Name>, see
-- Shared.Assets and README). Missing model -> procedural fallback.
Config.Assets = {
	-- Names the game looks for (AssetService reports the missing ones).
	Expected = {
		Weapons = { "Weapon_Sword_1", "Weapon_Sword_2", "Weapon_Spear_1", "Weapon_Spear_2", "Weapon_Blaster_1", "Weapon_Blaster_2", "Weapon_Blaster_3" },
		Mobs = { "Boss_Juggernaut", "Mob_SpiderBot", "Mob_Mech", "Mob_RedAndroid", "Mob_Overseer", "Mob_Robot", "Mob_Android", "Mob_BlueBot", "Mob_Bot2" },
		Props = { "Prop_Crate", "Prop_Door", "Prop_Lamp", "Prop_Pipes", "Prop_Hologram", "Prop_Barrel", "Prop_Misc_1", "Prop_Misc_2", "Prop_Misc_3", "Prop_Misc_4" },
		Trainers = { "Trainer_Dummy", "Trainer_Bag", "Trainer_Machine", "Trainer_Refiner", "Trainer_Weights" },
	},
	-- Weapon look by class (Config.Weapons[i].Class): the first entry whose
	-- UpTo rarity is >= the item's rarity. A model named exactly like the
	-- weapon id (GameAssets/Weapons/<id>) wins over this table.
	WeaponModels = {
		Blade = { { Model = "Weapon_Sword_1", UpTo = "Uncommon" }, { Model = "Weapon_Sword_2" } },
		Pulse = { { Model = "Weapon_Spear_1", UpTo = "Uncommon" }, { Model = "Weapon_Spear_2" } },
		Gunner = { { Model = "Weapon_Blaster_1", UpTo = "Uncommon" }, { Model = "Weapon_Blaster_2", UpTo = "Epic" }, { Model = "Weapon_Blaster_3" } },
	},
	-- How a weapon model is held: Length in studs; GripAt = where the hand
	-- is, 0 = rear end .. 1 = tip (default: the Tool's Handle, else 0.12);
	-- Flip = true when the tip and the grip end come out swapped (checked
	-- in Studio: swords and spears are fine as they are).
	WeaponFit = {
		Weapon_Sword_1 = { Length = 4.6 },
		Weapon_Sword_2 = { Length = 5 },
		Weapon_Spear_1 = { Length = 7 },
		Weapon_Spear_2 = { Length = 7.5 },
		-- Gun = held like a pistol: barrel = the Handle's (or longest
		-- part's) front, top = its top; GripDown = share of the height
		-- below the center where the hand is.
		Weapon_Blaster_1 = { Gun = true, Length = 2.6, GripAt = 0.3 },
		Weapon_Blaster_2 = { Gun = true, Length = 3, GripAt = 0.3 },
		Weapon_Blaster_3 = { Gun = true, Flip = true, Length = 3.6, GripAt = 0.3 }, -- rifle: muzzle is on its back side
	},
	-- Item icons: [item id] = "rbxassetid://..." uploaded by the owner.
	-- Empty = the icon is rendered from the 3D model (Shared ItemIcon).
	Icons = {},
}

-- Polygon in the hub: test dummies (no rewards). Damage per hit, DPS and
-- the combo are shown to the player hitting them (client PolygonHud).
Config.Polygon = {
	DummyHeight = 6.5, -- studs (owner Trainer_Dummy / Trainer_Bag are scaled to it)
	BigScale = 1.6, -- the "Big" dummy
	Range = 18, -- max studs between the player and the dummy hit
	ComboGap = 1.5, -- seconds between hits that keep the combo going
	DpsWindow = 5, -- DPS = damage of the last N seconds / N
	ResetSeconds = 4, -- the panel resets after this pause
	Texts = {
		Title = "ПОЛИГОН",
		Line = "Удар %s   •   DPS %s   •   Комбо x%d",
		Best = "Лучший удар %s   •   Всего %s",
	},
}

-- DEV panel (only in Studio, never in a published game).
Config.Dev = {
	Credits = 100,
	Materials = 10, -- of every material
}

-- All remotes live directly in ReplicatedStorage, created by the server.
Config.Remotes = {
	ClickHit = "RemoteEvent", -- C->S (mob or nil) on every attack click; S->C ("Hit"|"Kill"|"Credits", ...)
	ShopRequest = "RemoteFunction", -- ("Equip", "Weapon"|"Armor", id) | ("Unequip", "Armor", slot) | pets -> ok, message
	Craft = "RemoteFunction", -- (recipeId) -> ok, message
	Pets = "RemoteFunction", -- ("Hatch", eggId, triple) | ("Equip"|"Unequip"|"Merge", key) | ("EquipBest") -> ok, message, results
	Travel = "RemoteFunction", -- ("Hub") | ("Room", n) -> ok, message
	Notify = "RemoteEvent", -- S->C (text, kind) toast
	RoomState = "RemoteEvent", -- S->C (room, alive, total) for the player's own run
	RunEnded = "RemoteEvent", -- S->C (reason, room, auraEarned, record, isNewRecord)
	Progression = "RemoteFunction", -- ("Status") | ("ClaimDaily") | ("Spin") | ("ClaimQuest", index) -> ok, payload
	Loot = "RemoteEvent", -- S->C ("Spawn", id, materialId, position, lifetime) | ("Picked", id, materialId, total) | ("Remove", id) | ("Clear"); C->S (id) pick up
	Announce = "RemoteEvent", -- S->all (text, color) system chat line + toast
	StoreNotify = "RemoteEvent", -- S->C (text) after a Robux purchase was granted
	LevelUp = "RemoteEvent", -- S->C (level, skillPoints gained) big "Новый уровень!" banner
}

---------------------------------------------------------------------
-- VISUAL: theme
---------------------------------------------------------------------

-- "Нано-Цитадель": world palette (hub and dungeon architecture). Graphite
-- and dark steel as the base, warm white light, thin cyan / magenta
-- neon accents, gold for UI and rarities.
Config.Nano = {
	Graphite = Color3.fromRGB(38, 40, 46),
	Steel = Color3.fromRGB(74, 78, 88),
	SteelLight = Color3.fromRGB(118, 122, 134),
	Concrete = Color3.fromRGB(146, 146, 150),
	ConcreteLight = Color3.fromRGB(184, 184, 188),
	ConcreteDark = Color3.fromRGB(96, 97, 102),
	Glass = Color3.fromRGB(150, 200, 225),
	WarmLight = Color3.fromRGB(255, 226, 190),
	Cyan = Color3.fromRGB(46, 230, 255),
	Magenta = Color3.fromRGB(255, 61, 184),
	Gold = Color3.fromRGB(255, 201, 60),
	Leaf = Color3.fromRGB(70, 170, 95),
}

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

-- Rarities, lowest to highest. Color is used everywhere (drops, cards,
-- beams). Chance = base chance that a mob drop has this rarity; loot
-- luck multiplies the chances of Rare and above. Fx: particles + sound
-- on the drop; Announce: screen flash + server-wide chat message.
Config.Rarities = {
	{ Id = "Common", Name = "Обычный", Color = Color3.fromRGB(190, 190, 205), Chance = 0.60 },
	{ Id = "Uncommon", Name = "Необычный", Color = Color3.fromRGB(90, 230, 110), Chance = 0.25 },
	{ Id = "Rare", Name = "Редкий", Color = Color3.fromRGB(70, 140, 255), Chance = 0.10 },
	{ Id = "Epic", Name = "Эпический", Color = Color3.fromRGB(170, 90, 255), Chance = 0.04 },
	{ Id = "Legendary", Name = "Легендарный", Color = Color3.fromRGB(255, 201, 60), Chance = 0.009, Fx = true },
	{ Id = "Mythic", Name = "Мифический", Color = Color3.fromRGB(255, 70, 70), Chance = 0.0009, Fx = true, Announce = true },
	{ Id = "Secret", Name = "Секретный", Color = Color3.fromRGB(255, 120, 220), Chance = 0.0001, Fx = true, Announce = true, Rainbow = true },
}
Config.Rarity = {} -- [id] = rarity (+ .Index)
for index, rarity in ipairs(Config.Rarities) do
	rarity.Index = index
	Config.Rarity[rarity.Id] = rarity
end

-- Lighting presets for LightingStyle = Realistic (+ PrioritizeLightingQuality;
-- the owner switches it on in Studio, the server also tries). The server
-- applies Hub at start; the client tweens between presets when the
-- player's "Zone" attribute changes. Rules: Bloom <= 0.05, light color
-- correction, soft shadows, a light Atmosphere, ambient never black.
--   Hub: clear sky with haze, warm white sun.
--   Dungeon: industrial half-dark under ceilings, warm lamps (each biome
--   tints the haze and the ambient: Config.DungeonLayout.Biomes[i]).
Config.Lighting = {
	TransitionSeconds = 1,
	BloomSize = 18,
	BloomThreshold = 1.4, -- only the very brightest pixels may glow
	ShadowSoftness = 0.3,
	Clouds = { Cover = 0.45, Density = 0.55, Color = Color3.fromRGB(245, 248, 255) },
	-- Hub = the Atrium interior: the sun only through the skylight, warm
	-- lamps do the rest; ambient a little warm, almost no haze indoors.
	Hub = {
		ClockTime = 13.5, Brightness = 2.6, ExposureCompensation = 0.1,
		Ambient = Color3.fromRGB(104, 96, 88), OutdoorAmbient = Color3.fromRGB(118, 110, 102),
		EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.8,
		Saturation = 0.04, Contrast = 0.06, Tint = Color3.fromRGB(255, 246, 234), Bloom = 0.04,
		Atmosphere = { Density = 0.12, Offset = 0, Color = Color3.fromRGB(214, 204, 190), Decay = Color3.fromRGB(120, 110, 100), Glare = 0, Haze = 0.6 },
	},
	Dungeon = {
		ClockTime = 14.5, Brightness = 1.4, ExposureCompensation = 0.25,
		Ambient = Color3.fromRGB(86, 82, 80), OutdoorAmbient = Color3.fromRGB(72, 72, 80),
		EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 1,
		Saturation = 0, Contrast = 0.08, Tint = Color3.fromRGB(255, 244, 228), Bloom = 0.05,
		Atmosphere = { Density = 0.42, Offset = 0, Color = Color3.fromRGB(120, 114, 108), Decay = Color3.fromRGB(62, 56, 54), Glare = 0, Haze = 2 },
	},
}

---------------------------------------------------------------------
-- VISUAL: hub layout
---------------------------------------------------------------------

-- Hub "Атриум Нано-Цитадели": a closed hall (walls, ceiling, a glass
-- skylight on steel trusses), arches into the side rooms, the Gates at
-- the far end. Offsets are from the SpawnLocation (ground level); north
-- is -Z (spawn -> gates), east is +X. Top view:
--
--              [========= ВРАТА =========]          north wall
--   Полигон ⌂ |                            | ⌂ Фабрикатор
--   (wheel)    |        (free center)       |  (rack)
--   Магазин ⌂ |                            | ⌂ Инкубатор
--   (board)    |                            |  (board)
--              [====== вход · SPAWN ======]          south wall
--
-- The side rooms behind the arches are temporary compact rooms that keep
-- the stations working (their full halls come later).
Config.HubLayout = {
	Name = "Нано-Цитадель",
	Hall = {
		Width = 60, -- X, inner
		Length = 80, -- Z, inner (south wall -> north wall)
		Height = 32, -- floor -> ceiling
		SouthZ = 8, -- inner face of the south wall (spawn is at 0)
		WallThickness = 2,
		Bay = 12, -- pilaster spacing on the side walls
		FloorTile = 8,
		Skylight = { HalfWidth = 18, FromZ = -4, ToZ = -64, Mullion = 4, Purlin = 6 },
		TrussDepth = 3,
		PendantX = { -12, 12 }, -- pendant lamps on every truss
	},
	-- Hall colors (materials: Concrete / Metal / DiamondPlate / Glass).
	Colors = {
		Floor = Color3.fromRGB(86, 84, 82),
		Runner = Color3.fromRGB(62, 61, 62),
		Paint = Color3.fromRGB(176, 140, 62), -- floor markings (painted, not glowing)
		WallSlab = Color3.fromRGB(104, 100, 96),
		WallPanel = Color3.fromRGB(152, 144, 134),
		Dado = Color3.fromRGB(54, 52, 52),
		Steel = Color3.fromRGB(92, 92, 96),
		Beam = Color3.fromRGB(60, 60, 64),
		Ceiling = Color3.fromRGB(48, 46, 46),
		Glass = Color3.fromRGB(190, 212, 226),
		Tunnel = Color3.fromRGB(10, 12, 18),
		Screen = Color3.fromRGB(16, 22, 30),
	},
	Lamp = { Range = 26, Brightness = 1.8, Angle = 120 }, -- pilaster lamps (warm)
	Pendant = { Range = 32, Brightness = 1.2, Drop = 4 },
	Arch = { Width = 10, Height = 12 },
	Entrance = { Width = 10, Height = 12 },
	Portal = { Width = 14, Height = 18, FrameWidth = 5.5, FrameDepth = 5, Curtains = 5, CurtainTransparency = 0.88, SignHeight = 5.4 },
	Room = { Width = 22, Depth = 22, Height = 16 }, -- temporary side rooms
	-- Side wall bays (Side: -1 west, 1 east; Z = bay center). Kind:
	--   Arch = door into a side room (Room: Forge / Egg / Polygon / Store)
	--   Board = leaderboard, Wheel = wheel of fortune,
	--   Bench / Console / Cargo / Pipes / Rack = decor sets.
	Bays = {
		{ Side = -1, Z = 2, Kind = "Bench" },
		{ Side = 1, Z = 2, Kind = "Bench" },
		{ Side = -1, Z = -10, Kind = "Board", Board = "Level" },
		{ Side = 1, Z = -10, Kind = "Board", Board = "Room" },
		{ Side = -1, Z = -22, Kind = "Arch", Room = "Store" },
		{ Side = 1, Z = -22, Kind = "Arch", Room = "Egg" },
		{ Side = -1, Z = -34, Kind = "Wheel" },
		{ Side = 1, Z = -34, Kind = "Rack" },
		{ Side = -1, Z = -46, Kind = "Arch", Room = "Polygon" },
		{ Side = 1, Z = -46, Kind = "Arch", Room = "Forge" },
		{ Side = -1, Z = -58, Kind = "Console" },
		{ Side = 1, Z = -58, Kind = "Console" },
		{ Side = -1, Z = -68, Kind = "Cargo" },
		{ Side = 1, Z = -68, Kind = "Pipes" },
	},
	-- End wall bays (X = bay center).
	NorthBays = { { X = -21, Kind = "Pipes" }, { X = 21, Kind = "Cargo" } },
	SouthBays = { { X = -12, Kind = "Bench" }, { X = 12, Kind = "Bench" }, { X = -24, Kind = "Rack" }, { X = 24, Kind = "Console" } },
	SouthPilasters = { -18, 18 },
	-- Decor scale: everything next to the player is human-sized.
	CrateSize = 3,
	BarrelHeight = 3.2,
	CanisterHeight = 2.6,
	PipesHeight = 8,

	-- Polygon room: dummies (PolygonService). Offsets from the room center,
	-- they face the entrance (+X).
	Polygon = {
		Dummies = {
			{ Offset = Vector3.new(-6, 0, -7), Kind = "Trainer_Dummy" },
			{ Offset = Vector3.new(-6, 0, 7), Kind = "Trainer_Dummy" },
			{ Offset = Vector3.new(1, 0, -5), Kind = "Trainer_Bag" },
			{ Offset = Vector3.new(1, 0, 5), Kind = "Trainer_Bag" },
			{ Offset = Vector3.new(-7, 0, 0), Kind = "Trainer_Dummy", Big = true },
		},
	},
	Leaderboards = {
		Level = "Топ уровней",
		Room = "Глубже всех в данже",
	},
	-- Wall screens of the decor sets (one line each, cycled).
	Screens = {
		{ Title = "ЦИТАДЕЛЬ · СТАТУС", Line = "Энергосеть: норма" },
		{ Title = "НАНО-ФАБРИКА", Line = "Активность роботов растёт" },
		{ Title = "ВРАТА", Line = "Канал в подземелье открыт" },
		{ Title = "ФАБРИКАТОР", Line = "Материалы → снаряжение" },
	},

	Texts = {
		Title = "НАНО-ЦИТАДЕЛЬ",
		TitleSub = "Атриум",
		Portal = "ВРАТА",
		PortalSub = "Подземелье · Нано-фабрика",
		Polygon = "ПОЛИГОН",
		PolygonSub = "Проверь урон и комбо",
		Forge = "ФАБРИКАТОР",
		ForgeSub = "Крафт оружия и брони",
		Store = "МАГАЗИН",
		StoreSub = "Robux",
		Pets = "ИНКУБАТОР",
		PetsSub = "Яйца питомцев",
		Wheel = "КОЛЕСО УДАЧИ",
		WheelFree = "Бесплатное вращение!",
		Console = "СИСТЕМЫ В НОРМЕ",
	},
	Prompts = {
		Forge = "Фабрикатор",
		Store = "Магазин",
		Egg = "Инкубатор",
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
	MaxPartsPerRoom = 220, -- design budget of one room
	LampRows = 2, -- ceiling light rows per room (warm downlights)
	MonitorsPerWall = 2,
	Ceiling = true, -- closed halls: industrial half-dark under warm lamps

	-- Nano-factory: one biome per 5 rooms. Walls (StoneA/B) are lighter
	-- than the floor (Floor/FloorB) so edges read at a glance; Metal =
	-- pipes / frames, Accent = thin neon lines, Light = lamp color, Glow =
	-- the biome's "hot" color (molten channel, cryo tanks, data cores).
	-- Atmosphere / Lighting tint the haze and the ambient per biome.
	Biomes = {
		{ Name = "Сборочный цех", Theme = "Assembly",
			StoneA = Color3.fromRGB(128, 130, 138), StoneB = Color3.fromRGB(108, 110, 118), Floor = Color3.fromRGB(62, 64, 70), FloorB = Color3.fromRGB(52, 54, 60),
			Metal = Color3.fromRGB(70, 74, 84), Accent = Color3.fromRGB(255, 190, 60), Light = Color3.fromRGB(255, 222, 180), Glow = Color3.fromRGB(255, 170, 50),
			Atmosphere = { Color = Color3.fromRGB(140, 130, 115), Decay = Color3.fromRGB(80, 70, 60) },
			Lighting = { Ambient = Color3.fromRGB(92, 88, 82), OutdoorAmbient = Color3.fromRGB(80, 78, 76) } },
		{ Name = "Криолаборатория", Theme = "Cryo",
			StoneA = Color3.fromRGB(176, 196, 214), StoneB = Color3.fromRGB(150, 172, 192), Floor = Color3.fromRGB(64, 78, 96), FloorB = Color3.fromRGB(54, 66, 84),
			Metal = Color3.fromRGB(90, 104, 122), Accent = Color3.fromRGB(46, 230, 255), Light = Color3.fromRGB(220, 240, 255), Glow = Color3.fromRGB(120, 230, 255),
			Atmosphere = { Color = Color3.fromRGB(150, 180, 205), Decay = Color3.fromRGB(80, 105, 135) },
			Lighting = { Ambient = Color3.fromRGB(84, 92, 104), OutdoorAmbient = Color3.fromRGB(80, 88, 100) } },
		{ Name = "Плавильный реактор", Theme = "Smelter",
			StoneA = Color3.fromRGB(122, 104, 96), StoneB = Color3.fromRGB(102, 86, 80), Floor = Color3.fromRGB(56, 46, 44), FloorB = Color3.fromRGB(46, 38, 36),
			Metal = Color3.fromRGB(70, 60, 58), Accent = Color3.fromRGB(255, 120, 40), Light = Color3.fromRGB(255, 200, 150), Glow = Color3.fromRGB(255, 110, 30),
			Atmosphere = { Color = Color3.fromRGB(170, 120, 95), Decay = Color3.fromRGB(110, 60, 40) },
			Lighting = { Ambient = Color3.fromRGB(100, 82, 74), OutdoorAmbient = Color3.fromRGB(88, 74, 68) } },
		{ Name = "Ядро Нексуса", Theme = "Nexus",
			StoneA = Color3.fromRGB(96, 92, 120), StoneB = Color3.fromRGB(80, 76, 104), Floor = Color3.fromRGB(40, 38, 56), FloorB = Color3.fromRGB(32, 30, 46),
			Metal = Color3.fromRGB(58, 54, 78), Accent = Color3.fromRGB(255, 61, 184), Light = Color3.fromRGB(230, 210, 255), Glow = Color3.fromRGB(46, 230, 255),
			Atmosphere = { Color = Color3.fromRGB(130, 115, 160), Decay = Color3.fromRGB(70, 55, 105) },
			Lighting = { Ambient = Color3.fromRGB(86, 80, 102), OutdoorAmbient = Color3.fromRGB(78, 72, 96) } },
	},
	BossBarrierColor = Color3.fromRGB(255, 61, 184),

	Texts = {
		Enemies = "%d/%d врагов",
		Stage = "Этап %d",
		Recommended = "Рекомендовано: %s",
		Boss = "БИТВА С БОССОМ",
		Cleared = "Пройдено!",
		Entrance = "ЭТАП %d",
		RunDied = "Ты пал в бою",
		RunLeft = "Забег завершён",
		RunWon = "Подземелье пройдено!",
		RunSummary = "Дошёл до этапа %d  •  получено %s кредитов  •  рекорд %d",
		NewRecord = "Новый рекорд этапа!",
	},
}

-- Mob presentation shared by every kind (the kinds: Config.Mobs).
Config.MobLooks = {
	BossScale = 2.6, -- bosses = Height x this (Juggernaut and three regular models)
	KindsPerBiome = 3,
	-- HP bar above a mob, sized in studs. Normal mobs: shown only after the
	-- first hit, drawn in depth (a nearer bar hides a farther one) and only
	-- within MaxDistance; bosses: always, on top, with the name.
	HealthBar = { MaxDistance = 35, BossMaxDistance = 80, Width = 3.6, Height = 0.6 },
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
		Done = "Данж пройден! Улучшай снаряжение",
	},
	MenuButtons = { -- grid on the left, 2 columns
		{ Id = "Forge", Icon = "⚒", Label = "Кузница", Color = Color3.fromRGB(255, 120, 40) },
		{ Id = "Inventory", Icon = "🎒", Label = "Инвентарь", Color = Color3.fromRGB(70, 140, 255) },
		{ Id = "Equipment", Icon = "⚔", Label = "Снаряжение", Color = Color3.fromRGB(90, 230, 110) },
		{ Id = "Pets", Icon = "🐾", Label = "Питомцы", Color = Color3.fromRGB(255, 61, 184) },
		{ Id = "Reward", Icon = "🎁", Label = "Награда", Color = Color3.fromRGB(255, 201, 60) },
		{ Id = "Store", Icon = "💎", Label = "Магазин", Color = Color3.fromRGB(46, 200, 255) },
		{ Id = "Travel", Icon = "🚪", Label = "Телепорт", Color = Color3.fromRGB(70, 60, 190) },
	},
	ToastSeconds = 4,
	ShakeCrit = { Amplitude = 0.25, Seconds = 0.15 },
	ShakeBoss = { Amplitude = 0.8, Seconds = 0.5 },
	DamageHint = "⚔ Твой урон %s  •  нужно %s", -- HUD plate in the dungeon (not the barrier wording)
	BackKey = Enum.KeyCode.B,
	BackButton = { Icon = "←", Label = "Назад [B]", Color = Color3.fromRGB(240, 70, 80) }, -- the Travel cell in the dungeon
	MobileScaleWidth = 1100, -- UIScale = min(1, viewportWidth / this)
}

-- Sounds. Only built-in rbxasset:// files that ship with the Roblox
-- client are used (the classic sword / victory / ping sounds, pitched); empty slots are TODO: put your own rbxassetid://
-- there when you have uploaded sounds (never guess IDs).
Config.Sounds = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Pickup = "rbxasset://sounds/electronicpingshort.wav",
	RareDrop = "rbxasset://sounds/victory.wav", -- legendary+ drop (pitched up for mythic / secret)
	Swing = "rbxasset://sounds/swordslash.wav",
	Hammer = "rbxasset://sounds/swordlunge.wav", -- forge hammer strike (played low)
	Forged = "rbxasset://sounds/victory.wav",
	Unsheath = "rbxasset://sounds/unsheath.wav",
	Music = "", -- TODO: your uploaded background music (rbxassetid://...)
	Hit = "rbxasset://sounds/swordslash.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav",
	Barrier = "", -- TODO: barrier dissolve
	Portal = "", -- TODO: portal whoosh
	BossDeath = "", -- TODO: boss explosion
	Ui = "", -- TODO: button click
}

return Config
