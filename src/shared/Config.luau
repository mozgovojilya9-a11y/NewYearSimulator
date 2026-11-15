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
	RoomReached = 0, -- highest dungeon room cleared (0 = none, 20 = all)
	-- Engagement systems (ProgressionService)
	Daily = { LastClaim = 0, Streak = 0 },
	WheelLast = 0,
	Quests = { Day = 0, List = {} },
	Level = 1,
	Xp = 0,
	SkillPoints = 0, -- old field (points are now Config.Skills.PointsAtLevel per class)
	Class = "", -- "" until the player picks one (class selection screen)
	Story = { Step = 1, Count = 0, Seen = 0 }, -- mentor chain: current step, progress counter, step already heard
	Classes = {}, -- [classId] = { Skills = { [nodeId] = rank }, Loadout = { Q = nodeId, ... }, Resets = n }
	Boosts = { Xp = 0, Damage = 0, Loot = 0, Credits = 0 }, -- timed x2 boosts: os.time() they end
	LastSeen = 0, -- os.time() of the last save
}
-- Fields from older versions that are migrated / dropped on load
-- (DataService): OwnedBackpacks, EquippedBackpack, OwnedPets, EquippedPet,
-- Pets, EquippedPets, PetIndex (pets were removed in schema 4).

-- Version of the save format. Bump it when the format changes and add
-- a step to DataService.Migrations; old saves are upgraded step by step
-- on load and never lose progress.
--   1 = everything before the version number existed
--   2 = Aura is power (never spent), Нано-кредиты, skill points
--   3 = action-RPG: Aura, rebirths and trainers removed (credits as
--       compensation, Config.Migration), x2 boosts in Boosts
--   4 = pets removed (credits as compensation, Config.PetMigration)
--   5 = gear above the player's progress replaced (Config.ItemMigration)
Config.SchemaVersion = 5

-- One-time compensation (schema 2 -> 3) for the removed clicker: Aura and
-- rebirths turn into Нано-кредиты. Moderate on purpose.
--   credits = PerAuraDigit x log10(Aura + 1) + PerRebirth x rebirths, capped
Config.Migration = {
	PerAuraDigit = 40, -- 1M Aura -> 240
	PerRebirth = 120, -- 8 rebirths -> 960
	Max = 3000,
	Notice = "Игра обновилась: Аура и перерождения убраны. Компенсация: +%s нано-кредитов!",
}

-- Schema 4 -> 5: gear from old versions that is stronger than the
-- player's progress (e.g. a biome-4 weapon with the record at room 0)
-- one-shot the dungeon. The allowed biome = RoomReached // RoomsPerBiome + 1;
-- weapons above the strongest normal weapon of that biome and armor sets
-- of a later biome are replaced by the best of the allowed biome (same
-- class / slot), plus credits per replaced item. Robux items stay.
Config.ItemMigration = {
	RoomsPerBiome = 5,
	ByRarity = { Common = 20, Uncommon = 40, Rare = 80, Epic = 160, Legendary = 320, Mythic = 600, Secret = 1000 },
	Max = 8000,
	Notice = "Старое снаряжение пересчитано под новый баланс. Компенсация: +%s нано-кредитов!",
}

-- One-time compensation (schema 3 -> 4) for the removed pets: every pet
-- the player had (stacks by tier) turns into Нано-кредиты.
--   credits = sum of ByRarity[rarity] x TierMult[tier] per pet, capped
-- (old pet ids -> rarity are listed here: Config.Pets no longer exists)
Config.PetMigration = {
	PetRarity = {
		Blob = "Common", Bunny = "Common", Bat = "Uncommon", Spark = "Rare", IceFox = "Rare",
		Imp = "Epic", Golem = "Epic", Dragon = "Legendary", Phoenix = "Legendary", AbyssEye = "Mythic",
	},
	ByRarity = { Common = 15, Uncommon = 30, Rare = 60, Epic = 150, Legendary = 400, Mythic = 1000 },
	TierMult = { ["1"] = 1, ["2"] = 3, ["3"] = 9 }, -- 3 equal pets merged into one of the next tier
	Max = 6000,
	Notice = "Игра обновилась: питомцы убраны. Компенсация: +%s нано-кредитов!",
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
	Icon = "credits",
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

-- Order = position in the store. Icon = line icon on the card (ui/Icons).
Config.GamePasses = {
	VIP = { Id = 0, Order = 1, Icon = "crown", Name = "VIP", Price = 199, Text = "+20% опыта и кредитов, VIP-тег" },
	Damage2x = { Id = 0, Order = 2, Icon = "sword", Name = "x2 Урон", Price = 149, Text = "Навсегда удваивает урон" },
	Xp2x = { Id = 0, Order = 3, Icon = "star", Name = "x2 Опыт", Price = 149, Text = "Навсегда удваивает опыт" },
	Credits2x = { Id = 0, Order = 4, Icon = "credits", Name = "x2 Кредиты", Price = 149, Text = "Навсегда удваивает нано-кредиты" },
	LootLuck = { Id = 0, Order = 8, Icon = "gem", Name = "Удача добычи x2", Price = 199, Text = "x2 шанс редких материалов с мобов" },
}

-- Developer Products (bought again and again). Id = 0 -> "Скоро".
-- Kind: Credits (Amount of Нано-кредиты), Boost (Boost + Minutes),
-- Chest (Biome, Rolls: random materials of that biome, loot luck x Luck),
-- Weapon / ArmorSet (exclusive gear, granted once), WheelSkip.
Config.Products = {
	{ Key = "CreditsSmall", Id = 0, Tab = "Packs", Icon = "credits", Name = "Горсть кредитов", Price = 25, Kind = "Credits", Amount = 400 },
	{ Key = "CreditsMedium", Id = 0, Tab = "Packs", Icon = "credits", Name = "Пачка кредитов", Price = 79, Kind = "Credits", Amount = 1500 },
	{ Key = "CreditsLarge", Id = 0, Tab = "Packs", Icon = "credits", Name = "Сейф кредитов", Price = 199, Kind = "Credits", Amount = 5000 },
	{ Key = "WheelSkip", Id = 0, Tab = "Packs", Icon = "wheel", Name = "Крутить колесо сейчас", Price = 25, Kind = "WheelSkip" },

	{ Key = "BoostXp15", Id = 0, Tab = "Boosts", Icon = "star", Name = "x2 Опыт · 15 мин", Price = 25, Kind = "Boost", Boost = "Xp", Minutes = 15 },
	{ Key = "BoostXp60", Id = 0, Tab = "Boosts", Icon = "star", Name = "x2 Опыт · 60 мин", Price = 69, Kind = "Boost", Boost = "Xp", Minutes = 60 },
	{ Key = "BoostDamage15", Id = 0, Tab = "Boosts", Icon = "sword", Name = "x2 Урон · 15 мин", Price = 29, Kind = "Boost", Boost = "Damage", Minutes = 15 },
	{ Key = "BoostDamage60", Id = 0, Tab = "Boosts", Icon = "sword", Name = "x2 Урон · 60 мин", Price = 79, Kind = "Boost", Boost = "Damage", Minutes = 60 },
	{ Key = "BoostLoot15", Id = 0, Tab = "Boosts", Icon = "gem", Name = "x2 Удача добычи · 15 мин", Price = 29, Kind = "Boost", Boost = "Loot", Minutes = 15 },
	{ Key = "BoostLoot60", Id = 0, Tab = "Boosts", Icon = "gem", Name = "x2 Удача добычи · 60 мин", Price = 79, Kind = "Boost", Boost = "Loot", Minutes = 60 },

	{ Key = "ChestCatacombs", Id = 0, Tab = "Chests", Icon = "chest", Name = "Контейнер цеха", Price = 49, Kind = "Chest", Biome = 1, Rolls = 30, Luck = 2 },
	{ Key = "ChestIce", Id = 0, Tab = "Chests", Icon = "chest", Name = "Контейнер криолаборатории", Price = 99, Kind = "Chest", Biome = 2, Rolls = 30, Luck = 2 },
	{ Key = "ChestLava", Id = 0, Tab = "Chests", Icon = "chest", Name = "Контейнер реактора", Price = 149, Kind = "Chest", Biome = 3, Rolls = 30, Luck = 2 },
	{ Key = "ChestAbyss", Id = 0, Tab = "Chests", Icon = "chest", Name = "Контейнер Нексуса", Price = 199, Kind = "Chest", Biome = 4, Rolls = 30, Luck = 2 },

	{ Key = "WeaponPatron", Id = 0, Tab = "Exclusive", Icon = "sword", Name = "Клинок Покровителя", Price = 149, Kind = "Weapon", Item = "PatronBlade" },
	{ Key = "WeaponComet", Id = 0, Tab = "Exclusive", Icon = "spear", Name = "Кометное копьё", Price = 249, Kind = "Weapon", Item = "CometSword" },
	{ Key = "WeaponCrown", Id = 0, Tab = "Exclusive", Icon = "crown", Name = "Коронный излучатель", Price = 399, Kind = "Weapon", Item = "CrownBlade" },
	{ Key = "ArmorRoyal", Id = 0, Tab = "Exclusive", Icon = "shield", Name = "Королевский сет", Price = 299, Kind = "ArmorSet", Item = "Royal" },
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
		ForemanMech = { Name = "Мех-бригадир", Boss = true, Asset = "Boss_Foreman", Turn = 90, AltAsset = "Mob_Mech", Height = 6, Tint = Color3.fromRGB(255, 170, 60), TintAmount = 0.25, Glow = Color3.fromRGB(255, 190, 70), Builder = "SlimeKing", Drops = { "Bone", "Slime", "RustyIron", "CursedSkull", "CatacombHeart" } },
		-- 2. Криолаборатория
		CryoBot = { Name = "Крио-бот", Asset = "Mob_BlueBot", Height = 5, Glow = Color3.fromRGB(120, 230, 255), Builder = "SnowGolem", Drops = { "Ice", "FrostCrystal", "EternalIce" } },
		CryoAndroid = { Name = "Крио-андроид", Asset = "Mob_Android", Height = 6, Tint = Color3.fromRGB(170, 220, 255), TintAmount = 0.4, Glow = Color3.fromRGB(46, 230, 255), Builder = "Yeti", Drops = { "YetiFur", "FrostCrystal", "EternalIce" } },
		FrostSpider = { Name = "Ледяной паукобот", Asset = "Mob_SpiderBot", Height = 4.2, Tint = Color3.fromRGB(160, 215, 255), TintAmount = 0.5, Glow = Color3.fromRGB(120, 230, 255), Builder = "IceSpider", Drops = { "Ice", "YetiFur", "FrostCrystal", "EternalIce" } },
		CryoOverseer = { Name = "Крио-надзиратель", Boss = true, Asset = "Boss_Cryo", AltAsset = "Mob_Overseer", Height = 6, Tint = Color3.fromRGB(150, 210, 255), TintAmount = 0.45, Glow = Color3.fromRGB(46, 230, 255), Builder = "IceBoneLord", Drops = { "Ice", "YetiFur", "FrostCrystal", "EternalIce" } },
		-- 3. Плавильный реактор
		Smelter = { Name = "Андроид-плавильщик", Asset = "Mob_RedAndroid", Height = 6, Glow = Color3.fromRGB(255, 140, 40), Builder = "FireImp", Drops = { "Ember", "Obsidian", "FirePlume", "VolcanoHeart" } },
		HeavyMech = { Name = "Тяжёлый мех", Asset = "Mob_Mech", Height = 6.5, Tint = Color3.fromRGB(90, 70, 60), TintAmount = 0.4, Glow = Color3.fromRGB(255, 120, 30), Builder = "MagmaGolem", Drops = { "Obsidian", "MagmaCore", "FirePlume", "VolcanoHeart" } },
		SlagBot = { Name = "Шлакобот", Asset = "Mob_Bot2", Height = 5, Tint = Color3.fromRGB(255, 130, 40), TintAmount = 0.4, Glow = Color3.fromRGB(255, 160, 60), Builder = "GoblinSmith", Drops = { "Obsidian", "Ember", "MagmaCore", "VolcanoHeart" } },
		MoltenColossus = { Name = "Плавильный колосс", Boss = true, Asset = "Boss_Molten", AltAsset = "Mob_Android", Height = 6.2, Tint = Color3.fromRGB(255, 110, 30), TintAmount = 0.45, Glow = Color3.fromRGB(255, 150, 40), Builder = "FireChief", Drops = { "Obsidian", "Ember", "MagmaCore", "FirePlume", "VolcanoHeart" } },
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

---------------------------------------------------------------------
-- CLASSES, COMBAT, SKILL TREES
---------------------------------------------------------------------

-- Exactly 3 classes. Weapon models follow the class (Config.Assets.
-- WeaponModels[Class]); any owned weapon works with any class, its look
-- and the attack style come from the class. Tags = role tags on the
-- class card (Icon + Text), Difficulty 1..5, Key = 3 node ids shown as
-- the "key abilities" on the selection screen.
Config.Classes = {
	{
		Id = "Blade", Name = "Клинок", Icon = "sword", Color = Color3.fromRGB(46, 200, 255),
		Short = "Ближний бой: нано-меч и энергощит. Комбо из 3 ударов, блок.",
		Text = "Боец ближнего боя. Держит удар энергощитом, рубит комбо из трёх ударов, третий бьёт по дуге. Блок [F] снимает 70% урона.",
		Tags = { { Icon = "shield", Text = "Танк" }, { Icon = "sword", Text = "Урон" }, { Icon = "bolt", Text = "Контроль" } },
		Difficulty = 2,
		Key = { "Blade_A3", "Blade_D1", "Blade_C1" },
	},
	{
		Id = "Pulse", Name = "Импульс", Icon = "spear", Color = Color3.fromRGB(255, 61, 184),
		Short = "Энерго-копьё: 2 удара и удар на 360°, рывок с ударом.",
		Text = "Подвижный боец с энерго-копьём. Два быстрых укола и третий удар на 360° по всем вокруг. Рывок [Shift] бьёт всех на пути.",
		Tags = { { Icon = "burst", Text = "Область" }, { Icon = "dash", Text = "Мобильность" }, { Icon = "flame", Text = "Бурст" } },
		Difficulty = 3,
		Key = { "Pulse_A3", "Pulse_A6", "Pulse_C3" },
	},
	{
		Id = "Gunner", Name = "Стрелок", Icon = "blaster", Color = Color3.fromRGB(255, 201, 60),
		Short = "Плазменный бластер: каждый 3-й выстрел залп, заряженный выстрел.",
		Text = "Бьёт издалека. Каждый третий выстрел — залп по нескольким целям. Зажми атаку, чтобы зарядить мощный выстрел. Турели и ловушки.",
		Tags = { { Icon = "target", Text = "Точность" }, { Icon = "dash", Text = "Дистанция" }, { Icon = "sword", Text = "Урон" } },
		Difficulty = 3,
		Key = { "Gunner_A1", "Gunner_A3", "Gunner_S3" },
	},
}
Config.ClassById = {}
for order, class in ipairs(Config.Classes) do
	class.Order = order
	Config.ClassById[class.Id] = class
end

-- Basic attacks, block, dash (numbers of the class mechanics).
Config.Combat = {
	Blade = { Range = 10, Combo = { 1, 1, 1.6 }, ComboWindow = 1.4, ThirdArc = 7 }, -- 3rd hit also hits mobs within ThirdArc of the target
	Pulse = { Range = 12, Combo = { 1, 1.1, 1.3 }, ComboWindow = 1.4, ThirdRadius = 11 }, -- 3rd hit: everyone around
	Gunner = { Range = 70, VolleyEvery = 3, VolleyTargets = 3, VolleyMult = 0.8, ChargeSeconds = 0.9, ChargeMult = 3 },
	Block = { Reduction = 0.7, WalkSpeed = 8, Key = Enum.KeyCode.F },
	Dash = { Distance = 16, Cooldown = 4, Seconds = 0.22, PulseMult = 1.4, Width = 6 },
	AutoAim = 26, -- abilities without a target hit the nearest enemy within this range
	MaxStun = 4, -- seconds
	SlowFactor = 0.45, -- slowed mobs move at this share of their speed
	OnHitStun = 0.8, -- seconds of a StunOnHit proc
	OnHitSlow = 2,
	FxColor = Color3.fromRGB(46, 230, 255),
	Texts = {
		NeedClass = "Сначала выбери класс",
		Cooldown = "Перезарядка",
		NoTarget = "Нет цели рядом",
		Learned = "Изучено: %s",
		Reset = "Навыки сброшены",
	},
}

-- Skill points and reset.
Config.Skills = {
	PointsAtLevel = function(level: number): number
		return math.max(1, level) -- 1 point at level 1, +1 per level
	end,
	ResetCost = function(level: number): number
		return 100 + 15 * level -- Нано-кредиты; the first reset of each class is free
	end,
	Slots = { "Q", "E", "R" }, -- active abilities equipped at once
	-- Node layout in a branch (8 nodes): row / column on the grid and the
	-- node that must be learned first. Position 8 is the capstone (crown).
	Layout = {
		{ Row = 0, Col = 0 },
		{ Row = 1, Col = -1, Needs = 1 },
		{ Row = 1, Col = 1, Needs = 1 },
		{ Row = 2, Col = -1, Needs = 2 },
		{ Row = 2, Col = 1, Needs = 3 },
		{ Row = 3, Col = -1, Needs = 4 },
		{ Row = 3, Col = 1, Needs = 5 },
		{ Row = 4, Col = 0, NeedsAny = { 6, 7 } },
	},
	Levels = { 1, 3, 5, 8, 10, 15, 20, 30 }, -- unlock level by position
	Branches = {
		{ Id = "A", Name = "Атака", Icon = "sword" },
		{ Id = "D", Name = "Защита", Icon = "shield" },
		{ Id = "C", Name = "Контроль", Icon = "vortex" },
		{ Id = "S", Name = "Выживание", Icon = "plus" },
	},
	-- Stat names of passives (shown on the node card).
	StatNames = {
		DamagePct = "Урон", HealthPct = "Макс. HP", Defense = "Защита", CritChance = "Шанс крита",
		CritDamage = "Крит. урон", AttackSpeed = "Скорость атаки", Regen = "Регенерация, HP/с", Dash = "Рывок, studs",
		Lifesteal = "Вампиризм", Thorns = "Отражение урона", ComboBonus = "Урон 3-го удара", BlockBonus = "Сила блока",
		SlowOnHit = "Шанс замедлить", StunOnHit = "Шанс оглушить", ControlPct = "Длительность контроля",
		AbilityPct = "Урон приёмов", CooldownPct = "Быстрее перезарядка", LowHpDamage = "Урон при HP < 35%",
		CheatDeath = "Спасение от смерти", DashPower = "Урон рывка", ChargeBonus = "Урон заряженного выстрела",
		VolleyBonus = "Целей в залпе", Luck = "Удача",
	},
	-- Stats shown as whole numbers (others are percents).
	FlatStats = { Regen = true, Dash = true, VolleyBonus = true, CheatDeath = true },
	CheatDeathCooldown = 120, -- seconds between two saves of "Феникс"-like capstones
	LowHp = 0.35,
}

-- Ability kinds (AbilityService):
--   Strike  one target in front (Range), Power x hit
--   Shot    one target far away (Range), Power x hit, a plasma beam
--   Spin    everyone within Radius, Power x hit (Hits times)
--   Wave    a cone in front (Range), Power x hit + slow Duration
--   Volley  up to Targets enemies in front (Range), Power x hit each
--   Stun    one target (Range): Power x hit + stun Duration
--   Pull    everyone within Radius flies to you + stun Duration, Power x hit
--   Quake   everyone within Radius: Power x hit + stun Duration
--   Trap    an area under the nearest enemy: Power x hit per second + slow, Duration
--   Barrage an area under the nearest enemy (Radius): Power x hit
--   Turret  a turret for Duration: Power x hit every second to the nearest enemy (Range)
--   Shield  -Value share of incoming damage for Duration (+ Heal share of max HP)
--   Rage    +Value damage for Duration
--   Haste   +Value attack speed for Duration
--   Heal    +Value share of max HP
-- Every number list is per rank (rank 1, 2, 3). Cooldowns in seconds.
local function tree(classId: string, branches)
	local nodes = {}
	for b, list in ipairs(branches) do
		local branch = Config.Skills.Branches[b]
		for position, def in ipairs(list) do
			def.Id = classId .. "_" .. branch.Id .. position
			def.Class = classId
			def.Branch = branch.Id
			def.Position = position
			def.Level = def.Level or Config.Skills.Levels[position]
			def.Kind = if position == 8 then "Capstone" elseif def.Ability then "Active" else "Passive"
			def.Active = def.Ability ~= nil
			table.insert(nodes, def)
		end
	end
	return nodes
end

local function P(name, icon, maxRank, stats, text)
	return { Name = name, Icon = icon, MaxRank = maxRank, Stats = stats, Text = text }
end
local function A(name, icon, maxRank, ability, text)
	ability.Name = name
	return { Name = name, Icon = icon, MaxRank = maxRank, Ability = ability, Text = text }
end

Config.SkillTrees = {
	Blade = tree("Blade", {
		{ -- Атака
			A("Рассекающий удар", "slash", 3, { Kind = "Strike", Power = { 1.8, 2.2, 2.6 }, Cooldown = { 6, 5, 4 }, Range = 11 }, "Мощный удар по врагу перед тобой."),
			P("Острота", "sword", 3, { DamagePct = { 0.04, 0.08, 0.12 } }, "Весь урон выше."),
			A("Круговой удар", "spin", 3, { Kind = "Spin", Power = { 1.2, 1.6, 2.0 }, Cooldown = { 10, 8, 6 }, Radius = 10 }, "Наносит урон всем врагам вокруг тебя."),
			P("Мастер комбо", "combo", 2, { ComboBonus = { 0.25, 0.5 } }, "Третий удар комбо бьёт сильнее."),
			P("Холодный расчёт", "target", 2, { CritChance = { 0.04, 0.08 } }, "Чаще критические удары."),
			A("Ярость клинка", "flame", 3, { Kind = "Rage", Value = { 0.25, 0.35, 0.45 }, Duration = { 6, 6, 7 }, Cooldown = { 20, 18, 16 } }, "На время весь урон выше."),
			P("Казнь", "skull", 2, { CritDamage = { 0.25, 0.5 } }, "Криты бьют больнее."),
			A("Буря клинков", "burst", 1, { Kind = "Spin", Power = { 3.2 }, Hits = 3, Cooldown = { 25 }, Radius = 14 }, "Три круговых удара подряд по всем вокруг."),
		},
		{ -- Защита
			A("Энергощит", "shield", 3, { Kind = "Shield", Value = { 0.4, 0.5, 0.6 }, Duration = { 3, 3.5, 4 }, Cooldown = { 14, 12, 10 } }, "Щит снимает часть урона."),
			P("Броня", "shield", 3, { Defense = { 0.03, 0.06, 0.09 } }, "Защита выше."),
			P("Стойкость", "heart", 3, { HealthPct = { 0.06, 0.12, 0.18 } }, "Больше здоровья."),
			P("Отражение", "wave", 2, { Thorns = { 0.15, 0.3 } }, "Часть полученного урона бьёт обратно."),
			P("Мастер блока", "shield", 2, { BlockBonus = { 0.05, 0.1 } }, "Блок [F] снимает ещё больше урона."),
			A("Бастион", "chevron", 2, { Kind = "Shield", Value = { 0.7, 0.8 }, Heal = { 0.1, 0.15 }, Duration = { 3, 4 }, Cooldown = { 30, 26 } }, "Мощный щит и немного лечения."),
			P("Закалка", "plus", 2, { HealthPct = { 0.1, 0.2 } }, "Ещё больше здоровья."),
			A("Неуязвимость", "crown", 1, { Kind = "Shield", Value = { 1 }, Duration = { 3 }, Cooldown = { 45 } }, "3 секунды без урона."),
		},
		{ -- Контроль
			A("Оглушающий удар", "bolt", 3, { Kind = "Stun", Power = { 1.2, 1.4, 1.6 }, Duration = { 1, 1.5, 2 }, Cooldown = { 10, 9, 8 }, Range = 11 }, "Удар оглушает врага."),
			P("Подсечка", "trap", 3, { SlowOnHit = { 0.1, 0.2, 0.3 } }, "Удары могут замедлить врага."),
			A("Притяжение", "vortex", 2, { Kind = "Pull", Power = { 0.6, 0.8 }, Duration = { 0.6, 1 }, Cooldown = { 15, 12 }, Radius = 14 }, "Стягивает врагов к тебе."),
			P("Шоковый клинок", "bolt", 2, { StunOnHit = { 0.05, 0.1 } }, "Удары могут оглушить врага."),
			A("Ударная волна", "wave", 2, { Kind = "Wave", Power = { 1.5, 2.0 }, Duration = { 2, 3 }, Cooldown = { 12, 10 }, Range = 16 }, "Волна перед тобой бьёт и замедляет."),
			P("Цепь контроля", "chevron", 2, { ControlPct = { 0.25, 0.5 } }, "Оглушение и замедление дольше."),
			A("Разлом", "trap", 2, { Kind = "Trap", Power = { 0.4, 0.6 }, Duration = { 4, 5 }, Cooldown = { 18, 15 }, Radius = 9 }, "Разлом под врагом жжёт и замедляет."),
			A("Землетрясение", "crown", 1, { Kind = "Quake", Power = { 2.5 }, Duration = { 2.5 }, Cooldown = { 35 }, Radius = 16 }, "Удар по земле оглушает всех вокруг."),
		},
		{ -- Выживание
			P("Регенерация", "regen", 3, { Regen = { 3, 6, 9 } }, "Здоровье восстанавливается быстрее."),
			P("Вампиризм", "heart", 3, { Lifesteal = { 0.02, 0.04, 0.06 } }, "Удары лечат тебя."),
			A("Второе дыхание", "plus", 2, { Kind = "Heal", Value = { 0.2, 0.3 }, Cooldown = { 30, 25 } }, "Мгновенно лечит."),
			P("Быстрые ноги", "dash", 2, { Dash = { 4, 8 } }, "Рывок дальше."),
			P("Живучесть", "heart", 2, { HealthPct = { 0.08, 0.16 } }, "Больше здоровья."),
			P("Адреналин", "flame", 2, { LowHpDamage = { 0.2, 0.4 } }, "Урон выше, когда здоровья мало."),
			P("Темп", "chevron", 2, { AttackSpeed = { 0.06, 0.12 } }, "Атакуешь быстрее."),
			P("Феникс", "crown", 1, { CheatDeath = { 1 } }, "Смертельный удар оставляет 50% HP (раз в 2 минуты)."),
		},
	}),
	Pulse = tree("Pulse", {
		{ -- Атака
			A("Удар импульса", "spear", 3, { Kind = "Strike", Power = { 1.7, 2.1, 2.5 }, Cooldown = { 6, 5, 4 }, Range = 13 }, "Мощный выпад копьём."),
			P("Резонанс", "sword", 3, { DamagePct = { 0.04, 0.08, 0.12 } }, "Весь урон выше."),
			A("Энерговихрь", "spin", 3, { Kind = "Spin", Power = { 1.3, 1.7, 2.1 }, Cooldown = { 10, 8, 6 }, Radius = 12 }, "Вихрь бьёт всех вокруг."),
			P("Перегрузка", "flame", 2, { CritDamage = { 0.25, 0.5 } }, "Криты бьют больнее."),
			P("Пробой", "bolt", 2, { AbilityPct = { 0.1, 0.2 } }, "Приёмы бьют сильнее."),
			A("Энергокопьё", "arrow", 3, { Kind = "Wave", Power = { 1.8, 2.2, 2.6 }, Duration = { 0.5, 0.5, 0.5 }, Cooldown = { 12, 10, 9 }, Range = 20 }, "Луч энергии пронзает врагов в линию."),
			P("Накал", "target", 2, { CritChance = { 0.04, 0.08 } }, "Чаще критические удары."),
			A("Сверхновая", "burst", 1, { Kind = "Spin", Power = { 4 }, Cooldown = { 28 }, Radius = 18 }, "Огромный взрыв энергии вокруг."),
		},
		{ -- Защита
			A("Кинетический щит", "shield", 3, { Kind = "Shield", Value = { 0.35, 0.45, 0.55 }, Duration = { 3, 3.5, 4 }, Cooldown = { 14, 12, 10 } }, "Щит снимает часть урона."),
			P("Плотность", "shield", 3, { Defense = { 0.03, 0.06, 0.09 } }, "Защита выше."),
			P("Энергоядро", "heart", 3, { HealthPct = { 0.05, 0.1, 0.15 } }, "Больше здоровья."),
			P("Отдача", "wave", 2, { Thorns = { 0.15, 0.3 } }, "Часть полученного урона бьёт обратно."),
			P("Поглощение", "regen", 2, { Lifesteal = { 0.02, 0.04 } }, "Удары лечат тебя."),
			A("Отражающее поле", "chevron", 2, { Kind = "Shield", Value = { 0.6, 0.75 }, Heal = { 0.1, 0.15 }, Duration = { 3, 4 }, Cooldown = { 28, 24 } }, "Мощный щит и немного лечения."),
			P("Стабилизатор", "plus", 2, { HealthPct = { 0.1, 0.2 } }, "Ещё больше здоровья."),
			A("Абсолютное поле", "crown", 1, { Kind = "Shield", Value = { 1 }, Duration = { 3 }, Cooldown = { 45 } }, "3 секунды без урона."),
		},
		{ -- Контроль
			A("Электрошок", "bolt", 3, { Kind = "Stun", Power = { 1.2, 1.4, 1.6 }, Duration = { 1, 1.5, 2 }, Cooldown = { 10, 9, 8 }, Range = 13 }, "Разряд оглушает врага."),
			P("Вязкое поле", "trap", 3, { SlowOnHit = { 0.1, 0.2, 0.3 } }, "Удары могут замедлить врага."),
			A("Гравиколодец", "vortex", 2, { Kind = "Pull", Power = { 0.7, 0.9 }, Duration = { 0.8, 1.2 }, Cooldown = { 15, 12 }, Radius = 16 }, "Стягивает врагов в одну точку."),
			P("Разряд", "bolt", 2, { StunOnHit = { 0.05, 0.1 } }, "Удары могут оглушить врага."),
			A("Импульсная волна", "wave", 2, { Kind = "Wave", Power = { 1.4, 1.9 }, Duration = { 2, 3 }, Cooldown = { 12, 10 }, Range = 18 }, "Волна бьёт и замедляет врагов перед тобой."),
			P("Длительность", "chevron", 2, { ControlPct = { 0.25, 0.5 } }, "Оглушение и замедление дольше."),
			A("Энергосеть", "trap", 2, { Kind = "Trap", Power = { 0.4, 0.6 }, Duration = { 4, 5 }, Cooldown = { 18, 15 }, Radius = 10 }, "Сеть под врагом жжёт и замедляет."),
			A("Коллапс", "crown", 1, { Kind = "Quake", Power = { 2.6 }, Duration = { 2.5 }, Cooldown = { 35 }, Radius = 18 }, "Гравитационный удар оглушает всех вокруг."),
		},
		{ -- Выживание
			P("Подзарядка", "regen", 3, { Regen = { 3, 6, 9 } }, "Здоровье восстанавливается быстрее."),
			P("Вектор", "dash", 3, { Dash = { 3, 6, 9 } }, "Рывок дальше."),
			A("Восстановление", "plus", 2, { Kind = "Heal", Value = { 0.2, 0.3 }, Cooldown = { 30, 25 } }, "Мгновенно лечит."),
			P("Таран", "arrow", 2, { DashPower = { 0.5, 1 } }, "Рывок бьёт сильнее."),
			P("Живучесть", "heart", 2, { HealthPct = { 0.08, 0.16 } }, "Больше здоровья."),
			P("Манёвр", "chevron", 2, { AttackSpeed = { 0.06, 0.12 } }, "Атакуешь быстрее."),
			P("Ускоритель", "reset", 2, { CooldownPct = { 0.08, 0.16 } }, "Приёмы перезаряжаются быстрее."),
			P("Бессмертие", "crown", 1, { CheatDeath = { 1 } }, "Смертельный удар оставляет 50% HP (раз в 2 минуты)."),
		},
	}),
	Gunner = tree("Gunner", {
		{ -- Атака
			A("Прицельный выстрел", "target", 3, { Kind = "Shot", Power = { 2.0, 2.5, 3.0 }, Cooldown = { 6, 5, 4 }, Range = 80 }, "Мощный выстрел по одной цели."),
			P("Калибровка", "sword", 3, { DamagePct = { 0.04, 0.08, 0.12 } }, "Весь урон выше."),
			A("Залп", "volley", 3, { Kind = "Volley", Power = { 1.2, 1.5, 1.8 }, Targets = 5, Cooldown = { 10, 9, 8 }, Range = 60 }, "Бьёт по пяти целям сразу."),
			P("Бронебойность", "skull", 2, { CritDamage = { 0.25, 0.5 } }, "Криты бьют больнее."),
			P("Заряд", "charge", 2, { ChargeBonus = { 0.5, 1 } }, "Заряженный выстрел сильнее."),
			A("Шквал", "flame", 3, { Kind = "Haste", Value = { 0.3, 0.45, 0.6 }, Duration = { 5, 6, 6 }, Cooldown = { 20, 18, 16 } }, "На время стреляешь намного быстрее."),
			P("Снайпер", "eye", 2, { CritChance = { 0.05, 0.1 } }, "Чаще критические выстрелы."),
			A("Орбитальный удар", "burst", 1, { Kind = "Barrage", Power = { 4 }, Cooldown = { 28 }, Radius = 12, Range = 70 }, "Удар с орбиты по области у врага."),
		},
		{ -- Защита
			A("Энергобарьер", "shield", 3, { Kind = "Shield", Value = { 0.35, 0.45, 0.55 }, Duration = { 3, 3.5, 4 }, Cooldown = { 14, 12, 10 } }, "Барьер снимает часть урона."),
			P("Покрытие", "shield", 3, { Defense = { 0.03, 0.06, 0.09 } }, "Защита выше."),
			P("Запас прочности", "heart", 3, { HealthPct = { 0.05, 0.1, 0.15 } }, "Больше здоровья."),
			P("Отражатель", "wave", 2, { Thorns = { 0.15, 0.3 } }, "Часть полученного урона бьёт обратно."),
			P("Отступление", "dash", 2, { Dash = { 4, 8 } }, "Рывок дальше."),
			A("Укрытие", "chevron", 2, { Kind = "Shield", Value = { 0.6, 0.75 }, Heal = { 0.1, 0.15 }, Duration = { 3, 4 }, Cooldown = { 28, 24 } }, "Мощный барьер и немного лечения."),
			P("Закалка", "plus", 2, { HealthPct = { 0.1, 0.2 } }, "Ещё больше здоровья."),
			A("Купол", "crown", 1, { Kind = "Shield", Value = { 1 }, Duration = { 3 }, Cooldown = { 45 } }, "3 секунды без урона."),
		},
		{ -- Контроль
			A("Шоковая пуля", "bolt", 3, { Kind = "Stun", Power = { 1.2, 1.4, 1.6 }, Duration = { 1, 1.5, 2 }, Cooldown = { 10, 9, 8 }, Range = 70 }, "Выстрел оглушает врага."),
			P("Криопатрон", "trap", 3, { SlowOnHit = { 0.1, 0.2, 0.3 } }, "Выстрелы могут замедлить врага."),
			A("Ловушка", "trap", 2, { Kind = "Trap", Power = { 0.5, 0.7 }, Duration = { 5, 6 }, Cooldown = { 16, 13 }, Radius = 9 }, "Ловушка под врагом жжёт и замедляет."),
			P("Оглушение", "bolt", 2, { StunOnHit = { 0.05, 0.1 } }, "Выстрелы могут оглушить врага."),
			A("Импульсная граната", "burst", 2, { Kind = "Barrage", Power = { 1.6, 2.1 }, Cooldown = { 12, 10 }, Radius = 9, Range = 60 }, "Граната бьёт по области у врага."),
			P("Контроль", "chevron", 2, { ControlPct = { 0.25, 0.5 } }, "Оглушение и замедление дольше."),
			A("Грависеть", "vortex", 2, { Kind = "Pull", Power = { 0.5, 0.7 }, Duration = { 0.8, 1.2 }, Cooldown = { 16, 13 }, Radius = 16 }, "Стягивает врагов к тебе."),
			A("ЭМИ-взрыв", "crown", 1, { Kind = "Quake", Power = { 2.4 }, Duration = { 2.5 }, Cooldown = { 35 }, Radius = 18 }, "ЭМИ оглушает всех вокруг."),
		},
		{ -- Выживание (инженер)
			A("Аптечка", "plus", 3, { Kind = "Heal", Value = { 0.15, 0.22, 0.3 }, Cooldown = { 30, 27, 24 } }, "Мгновенно лечит."),
			P("Регенерация", "regen", 3, { Regen = { 3, 6, 9 } }, "Здоровье восстанавливается быстрее."),
			A("Турель", "turret", 3, { Kind = "Turret", Power = { 0.5, 0.7, 0.9 }, Duration = { 8, 10, 12 }, Cooldown = { 20, 18, 16 }, Range = 40 }, "Ставит турель, которая стреляет сама."),
			P("Охотник", "heart", 2, { Lifesteal = { 0.02, 0.04 } }, "Выстрелы лечат тебя."),
			P("Инженерия", "drone", 2, { AbilityPct = { 0.1, 0.2 } }, "Приёмы и турели бьют сильнее."),
			P("Перезарядка", "reset", 2, { CooldownPct = { 0.08, 0.16 } }, "Приёмы перезаряжаются быстрее."),
			P("Широкий залп", "volley", 2, { VolleyBonus = { 1, 2 } }, "Залп каждого 3-го выстрела бьёт больше целей."),
			A("Боевой дрон", "crown", 1, { Kind = "Turret", Power = { 1.4 }, Duration = { 15 }, Cooldown = { 30 }, Range = 50, Drone = true }, "Дрон летает рядом и стреляет."),
		},
	}),
}
Config.SkillById = {}
for _, nodes in pairs(Config.SkillTrees) do
	for _, node in ipairs(nodes) do
		Config.SkillById[node.Id] = node
	end
end

-- The value of a per-rank list at `rank` (lists shorter than the rank
-- repeat their last value).
function Config.RankValue(list, rank: number)
	if type(list) ~= "table" then
		return list
	end
	return list[math.clamp(rank, 1, #list)]
end

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
		Owned = "Уже выковано",
		Missing = "Не хватает материалов",
		Skip = "Пропустить",
		Done = "Выковано: %s!",
	},
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
			{ Kind = "Credits", Amount = 160, Weight = 6, Label = "Кредиты+++" },
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
	-- Клинок's energy shield on the left forearm (rim part; X = disc axis)
	Shield = { Size = 2.6, Color = Color3.fromRGB(46, 200, 255), Offset = CFrame.new(-0.35, 0, 0) },
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
		Mobs = { "Boss_Juggernaut", "Boss_Foreman", "Boss_Cryo", "Boss_Molten", "Mob_SpiderBot", "Mob_Mech", "Mob_RedAndroid", "Mob_Overseer", "Mob_Robot", "Mob_Android", "Mob_BlueBot", "Mob_Bot2" },
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
	-- Interface icons: [icon name] = "rbxassetid://..." replaces the line
	-- icon drawn by ui/Icons (names: see Icons.Names). A Decal / ImageLabel
	-- / Texture named like the icon in ServerStorage/GameAssets/Icons does
	-- the same without editing Config. Sounds: a Sound named like a
	-- Config.Sounds key in ServerStorage/GameAssets/Audio replaces it.
	UiIcons = {},
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
	ShopRequest = "RemoteFunction", -- ("Equip", "Weapon"|"Armor", id) | ("Unequip", "Armor", slot) -> ok, message
	Craft = "RemoteFunction", -- (recipeId) -> ok, message
	Travel = "RemoteFunction", -- ("Hub") | ("Room", n) -> ok, message
	Notify = "RemoteEvent", -- S->C (text, kind) toast
	RoomState = "RemoteEvent", -- S->C (room, alive, total) for the player's own run
	RunEnded = "RemoteEvent", -- S->C (reason, room, auraEarned, record, isNewRecord)
	Progression = "RemoteFunction", -- ("Status") | ("ClaimDaily") | ("Spin") | ("ClaimQuest", index) -> ok, payload
	Loot = "RemoteEvent", -- S->C ("Spawn", id, materialId, position, lifetime) | ("Picked", id, materialId, total) | ("Remove", id) | ("Clear"); C->S (id) pick up
	Announce = "RemoteEvent", -- S->all (text, color) system chat line + toast
	StoreNotify = "RemoteEvent", -- S->C (text) after a Robux purchase was granted
	LevelUp = "RemoteEvent", -- S->C (level, skillPoints gained) big "Новый уровень!" banner
	Class = "RemoteFunction", -- ("Choose", classId) | ("Learn", nodeId) | ("Reset") | ("Equip", slot, nodeId|nil) -> ok, message
	Ability = "RemoteEvent", -- C->S ("Use", slot, aim) | ("Dash", direction) | ("Block", on) | ("Charge"); S->C ("Dash", direction, distance, seconds); S->all ("Fx", kind, ...)
	Quest = "RemoteFunction", -- ("Talk", npcId) -> dialog payload | ("Claim") -> ok, message
	Training = "RemoteEvent", -- C->S ("Start", stationIndex) | ("Stop"); S->C ("Gain", xp)
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
	Font = Enum.Font.GothamBold, -- dense bold font with Cyrillic (FredokaOne has none)
	FontTitle = Enum.Font.GothamBlack,
	Magenta = Color3.fromRGB(255, 61, 184), -- #FF3DB8
	Cyan = Color3.fromRGB(46, 230, 255), -- #2EE6FF
	Gold = Color3.fromRGB(255, 201, 60), -- #FFC93C
	Purple = Color3.fromRGB(150, 80, 255),
	Green = Color3.fromRGB(90, 230, 110),
	Red = Color3.fromRGB(240, 70, 80),
	Orange = Color3.fromRGB(255, 150, 50),
	Blue = Color3.fromRGB(70, 140, 255),
	Text = Color3.fromRGB(236, 232, 222),
	Muted = Color3.fromRGB(158, 152, 140),
	Outline = Color3.fromRGB(6, 6, 8),
	Panel = Color3.fromRGB(17, 18, 22), -- window body (dark graphite, reference UI)
	PanelDark = Color3.fromRGB(12, 13, 16), -- HUD plates and every text plate
	Card = Color3.fromRGB(30, 31, 37), -- cards / buttons inside windows
	CardDark = Color3.fromRGB(14, 15, 18), -- slots, viewport backgrounds
	GoldDim = Color3.fromRGB(176, 140, 62), -- thin borders, inactive gold
	Line = Color3.fromRGB(74, 66, 48), -- quiet borders and separators
	Health = Color3.fromRGB(196, 54, 54),
	Xp = Color3.fromRGB(255, 201, 60),
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

-- Hub "Нано-Цитадель" after the owner's plan docs/design/hub_plan.png.
-- Offsets from the SpawnLocation (ground level); north is -Z, east +X.
-- Rects are { X0, X1, Z0, Z1 } (X0 < X1, Z0 > Z1: south edge first).
--
--                [ 7 ЗАЛ ВРАТ ]                     north
--   [ 5 ]  8 ┌──────────────────────┐ 9   [ 6 ФАБРИКАТОР ]
--   ТРЕНИ-   │   2 АТРИУМ, 2 яруса,  │
--   РОВОЧ-   │   мост, лестницы      │      [ 4 АКАДЕМИЯ ]
--   НЫЙ      └──────────┬───────────┘
--                  [ 1 СПАВН ] 3 Наставник           south
--
-- Every hall has its own colors (Theme), central object and decor groups
-- along the walls and in the corners; the middle and the paths stay free.
Config.HubLayout = {
	Name = "Нано-Цитадель",
	WallThickness = 2,
	Pilaster = 12, -- pilasters on the walls every N studs
	Halls = {
		Spawn = { Rect = { -20, 20, 15, -15 }, Height = 20, Theme = "Spawn", Name = "СПАВН" },
		Atrium = { Rect = { -100, 100, -15, -165 }, Height = 34, Theme = "Atrium", Name = "АТРИУМ" },
		Gates = { Rect = { -60, 60, -165, -220 }, Height = 42, Theme = "Gates", Name = "ЗАЛ ВРАТ" },
		Training = { Rect = { -180, -100, -30, -150 }, Height = 22, Theme = "Training", Name = "ТРЕНИРОВОЧНЫЙ ЗАЛ" },
		Forge = { Rect = { 100, 162, -100, -165 }, Height = 24, Theme = "Forge", Name = "ФАБРИКАТОР" },
		Academy = { Rect = { 100, 162, -15, -76 }, Height = 22, Theme = "Academy", Name = "АКАДЕМИЯ КЛАССОВ" },
	},
	-- Wide arches between halls (on the atrium walls): side + center.
	Doors = {
		{ Side = "S", At = 0, Width = 20, Height = 14, To = "Spawn" },
		{ Side = "N", At = 0, Width = 24, Height = 18, To = "Gates" },
		{ Side = "W", At = -45, Width = 18, Height = 14, To = "Training" },
		{ Side = "E", At = -43, Width = 18, Height = 14, To = "Academy" },
		{ Side = "E", At = -135, Width = 18, Height = 14, To = "Forge" },
	},
	-- Atrium: balcony (2nd level) along the walls, a bridge across, stairs.
	Balcony = { Height = 22, Depth = 22, Column = 12 },
	Bridge = { Z = -90, Width = 12 },
	Stairs = { { X = -42, Z0 = -46 }, { X = 42, Z0 = -46 }, { X = -42, Z0 = -134 }, { X = 42, Z0 = -134 } }, -- foot of each stair -> the bridge (2 from the south, 2 from the north)
	StairWidth = 8,
	Skylight = { Rect = { -60, 60, -40, -140 }, Mullion = 5, Truss = 12 },
	-- Hall colors. Accent = thin light strips and signs, Light = lamps.
	Themes = {
		Spawn = { Floor = Color3.fromRGB(70, 68, 84), Wall = Color3.fromRGB(122, 116, 140), Accent = Color3.fromRGB(170, 150, 255), Light = Color3.fromRGB(235, 228, 255) },
		Atrium = { Floor = Color3.fromRGB(84, 82, 82), Wall = Color3.fromRGB(150, 143, 134), Accent = Color3.fromRGB(46, 230, 255), Light = Color3.fromRGB(255, 226, 190) },
		Gates = { Floor = Color3.fromRGB(46, 70, 72), Wall = Color3.fromRGB(80, 118, 120), Accent = Color3.fromRGB(40, 230, 200), Light = Color3.fromRGB(200, 255, 245) },
		Training = { Floor = Color3.fromRGB(88, 62, 46), Wall = Color3.fromRGB(150, 108, 76), Accent = Color3.fromRGB(255, 140, 50), Light = Color3.fromRGB(255, 210, 160) },
		Forge = { Floor = Color3.fromRGB(64, 40, 40), Wall = Color3.fromRGB(112, 66, 62), Accent = Color3.fromRGB(255, 80, 60), Light = Color3.fromRGB(255, 180, 130) },
		Academy = { Floor = Color3.fromRGB(86, 74, 42), Wall = Color3.fromRGB(160, 136, 84), Accent = Color3.fromRGB(255, 201, 60), Light = Color3.fromRGB(255, 232, 180) },
	},
	-- AI-generated MaterialVariants (MaterialService, made in Studio);
	-- missing names simply fall back to the base material.
	Materials = { Floor = "NanoFloor", Wall = "NanoWall", ForgeFloor = "NanoFloor" }, -- the AI "ForgeFloor" looked like lava camo: off
	-- Shared colors of the structure.
	Colors = {
		Paint = Color3.fromRGB(176, 140, 62),
		Dado = Color3.fromRGB(54, 52, 52),
		Steel = Color3.fromRGB(92, 92, 96),
		Beam = Color3.fromRGB(60, 60, 64),
		Ceiling = Color3.fromRGB(48, 46, 46),
		Glass = Color3.fromRGB(190, 212, 226),
		Tunnel = Color3.fromRGB(10, 12, 18),
		Screen = Color3.fromRGB(16, 22, 30),
		Runner = Color3.fromRGB(62, 61, 62),
	},
	Lamp = { Range = 26, Brightness = 1.8, Angle = 120 },
	Pendant = { Range = 34, Brightness = 1.2, Drop = 4 },
	Portal = { Width = 20, Height = 26, FrameWidth = 7, FrameDepth = 6, Curtains = 5, CurtainTransparency = 0.86, SignHeight = 6 },
	-- Decor groups (plan squares): hall, Kind, offset from the hall's
	-- corner ("SW", "NE", ...) or a wall point { Side, At }.
	Decor = {
		{ Hall = "Spawn", Wall = "W", At = 0, Kind = "Bench" },
		{ Hall = "Spawn", Corner = "SW", Kind = "Plant" },
		{ Hall = "Spawn", Corner = "SE", Kind = "Plant" },
		{ Hall = "Atrium", Corner = "SW", Kind = "Cargo" },
		{ Hall = "Atrium", Corner = "SE", Kind = "Cargo" },
		{ Hall = "Atrium", Corner = "NW", Kind = "Pipes" },
		{ Hall = "Atrium", Corner = "NE", Kind = "Pipes" },
		{ Hall = "Atrium", Wall = "S", At = -40, Kind = "Bench" },
		{ Hall = "Atrium", Wall = "S", At = 40, Kind = "Bench" },
		{ Hall = "Atrium", Wall = "S", At = -70, Kind = "Console" },
		{ Hall = "Atrium", Wall = "S", At = 70, Kind = "Console" },
		{ Hall = "Atrium", Wall = "W", At = -80, Kind = "Rack" },
		{ Hall = "Atrium", Wall = "W", At = -105, Kind = "Bench" },
		{ Hall = "Atrium", Wall = "W", At = -130, Kind = "Console" },
		{ Hall = "Atrium", Wall = "E", At = -80, Kind = "Bench" },
		{ Hall = "Atrium", Wall = "E", At = -100, Kind = "Rack" },
		{ Hall = "Gates", Corner = "NW", Kind = "Plant" },
		{ Hall = "Gates", Corner = "NE", Kind = "Plant" },
		{ Hall = "Gates", Corner = "SW", Kind = "Console" },
		{ Hall = "Gates", Corner = "SE", Kind = "Console" },
		{ Hall = "Training", Corner = "NW", Kind = "Plant" },
		{ Hall = "Training", Corner = "SW", Kind = "Plant" },
		{ Hall = "Training", Wall = "W", At = -90, Kind = "Rack" },
		{ Hall = "Forge", Corner = "SW", Kind = "Cargo" },
		{ Hall = "Forge", Corner = "NW", Kind = "Rack" },
		{ Hall = "Forge", Corner = "SE", Kind = "Pipes" },
		{ Hall = "Academy", Corner = "SW", Kind = "Plant" },
		{ Hall = "Academy", Corner = "SE", Kind = "Plant" },
		{ Hall = "Academy", Corner = "NE", Kind = "Plant" },
		{ Hall = "Academy", Wall = "S", At = 131, Kind = "Bench" },
	},
	Leaderboards = { -- on the atrium north wall, either side of the Gate hall arch
		{ Kind = "Level", Title = "Топ уровней", At = -42 },
		{ Kind = "Room", Title = "Глубже всех в данже", At = -66 },
	},
	QuestBoard = { At = 42 }, -- 9: board + the Смотритель Врат NPC
	Mentor = { Offset = Vector3.new(13, 0, -8), Face = Vector3.new(0, 0, 4) }, -- 3: next to the spawn, facing it
	GateKeeper = { Offset = Vector3.new(54, 0, -150) },
	-- Training hall stations (2 rows along the long walls) and the dummies.
	TrainingRows = { X = { -168, -112 }, Z0 = -64, Step = 17 },
	Polygon = {
		Center = Vector3.new(-140, 0, -135),
		Dummies = {
			{ Offset = Vector3.new(-8, 0, 0), Kind = "Trainer_Dummy" },
			{ Offset = Vector3.new(0, 0, 0), Kind = "Trainer_Dummy", Big = true },
			{ Offset = Vector3.new(8, 0, 0), Kind = "Trainer_Bag" },
		},
		Facing = Vector3.new(0, 0, 1), -- dummies face south (into the hall)
	},
	-- First path of a new player (plan's yellow dashes): waypoints the floor
	-- guide follows from the spawn into each hall (client QuestGuide).
	Waypoints = {
		Spawn = Vector3.new(0, 0, 0),
		AtriumSouth = Vector3.new(0, 0, -30),
		AtriumCenter = Vector3.new(0, 0, -90),
		AtriumNorth = Vector3.new(0, 0, -150),
		TrainingDoor = Vector3.new(-104, 0, -45),
		AcademyDoor = Vector3.new(104, 0, -43),
		ForgeDoor = Vector3.new(104, 0, -135),
		GatesDoor = Vector3.new(0, 0, -168),
	},
	-- Floor guide (plan's yellow dashes): gold chevrons on the floor from
	-- the player along the route to the story quest's place (client
	-- QuestGuide). Points are offsets from the spawn, walked in order.
	Guide = {
		Step = 4, -- studs between chevrons
		Max = 36, -- chevrons drawn at most
		Speed = 3, -- studs per second they crawl forward
		Color = Color3.fromRGB(255, 201, 60),
		Routes = {
			Mentor = { Vector3.new(0, 0, 0), Vector3.new(10, 0, -5) },
			Academy = { Vector3.new(0, 0, 0), Vector3.new(0, 0, -30), Vector3.new(0, 0, -44), Vector3.new(104, 0, -44), Vector3.new(118, 0, -44) },
			Training = { Vector3.new(0, 0, 0), Vector3.new(0, 0, -30), Vector3.new(0, 0, -44), Vector3.new(-104, 0, -44), Vector3.new(-120, 0, -44) },
			Forge = { Vector3.new(0, 0, 0), Vector3.new(0, 0, -30), Vector3.new(0, 0, -44), Vector3.new(88, 0, -44), Vector3.new(88, 0, -135), Vector3.new(104, 0, -135), Vector3.new(116, 0, -135) },
			Gates = { Vector3.new(0, 0, 0), Vector3.new(0, 0, -30), Vector3.new(0, 0, -150), Vector3.new(0, 0, -168), Vector3.new(0, 0, -200) },
		},
	},
	Screens = {
		{ Title = "ЦИТАДЕЛЬ · СТАТУС", Line = "Энергосеть: норма" },
		{ Title = "НАНО-ФАБРИКА", Line = "Активность роботов растёт" },
		{ Title = "ВРАТА", Line = "Канал в подземелье открыт" },
		{ Title = "ФАБРИКАТОР", Line = "Материалы в снаряжение" },
	},
	CrateSize = 3,
	BarrelHeight = 3.2,
	CanisterHeight = 2.6,
	PipesHeight = 8,
	-- Owner / AI-generated models (GameAssets/Props); procedural if missing.
	Models = {
		Mentor = "NPC_Mentor",
		GateKeeper = "NPC_GateKeeper",
		ForgeCore = "Prop_ForgeCore",
		Stations = { Power = "Station_Power", Dummy = "Station_Dummy", Gravity = "Station_Gravity", Laser = "Station_Laser" },
	},
	Texts = {
		Title = "НАНО-ЦИТАДЕЛЬ",
		TitleSub = "Добро пожаловать",
		Portal = "ВРАТА",
		PortalSub = "Подземелье · Нано-фабрика",
		Polygon = "МАНЕКЕНЫ",
		PolygonSub = "Проверь урон и комбо",
		Forge = "ФАБРИКАТОР",
		ForgeSub = "Крафт оружия и брони",
		Training = "ТРЕНИРОВОЧНЫЙ ЗАЛ",
		TrainingSub = "Станции: опыт за тренировку",
		Academy = "АКАДЕМИЯ",
		AcademySub = "Классы: смена и обучение",
		Gates = "ЗАЛ ВРАТ",
		GatesSub = "Режимы и подземелье",
		QuestBoard = "ЗАДАНИЯ",
		QuestBoardSub = "Ежедневные · у Смотрителя",
		Console = "СИСТЕМЫ В НОРМЕ",
		Wheel = "КОЛЕСО УДАЧИ",
		WheelFree = "Бесплатное вращение!",
	},
	Prompts = {
		Forge = "Фабрикатор",
		Academy = "Сменить класс",
		Talk = "Поговорить",
		Board = "Задания",
		Train = "Тренироваться",
	},
}

-- Training hall stations: E to start, a panel with "Выйти", the station
-- animation; a little XP every Tick seconds (Xp x player level), stronger
-- stations open by level. XP from training is smaller than from fights.
Config.Training = {
	Tick = 3,
	MaxDistance = 8, -- moving away ends the session
	Stations = {
		{ Id = "Power", Name = "Силовой стенд", Icon = "chevron", Level = 1, Xp = 2, Count = 2 },
		{ Id = "Dummy", Name = "Робот-манекен", Icon = "sword", Level = 5, Xp = 3, Count = 2 },
		{ Id = "Gravity", Name = "Гравиплатформа", Icon = "vortex", Level = 12, Xp = 4, Count = 2 },
		{ Id = "Laser", Name = "Лазерный тир", Icon = "target", Level = 20, Xp = 5, Count = 2 },
	},
	Texts = {
		Locked = "Откроется на %d уровне",
		Panel = "Тренировка: %s",
		Exit = "Выйти",
		Gain = "+%d XP за тренировку",
		Busy = "Станция занята",
		Hint = "Опыт каждые %d с",
	},
}

-- NPCs (name plate + "Поговорить"). The mentor runs the story chain
-- (Config.Quests.Story), the gate keeper the daily quests.
Config.Npcs = {
	Mentor = { Name = "Наставник Арк", Title = "Наставник", Color = Color3.fromRGB(46, 230, 255) },
	GateKeeper = { Name = "Смотритель Врат", Title = "Ежедневные задания", Color = Color3.fromRGB(40, 230, 200) },
}

-- The mentor's story chain: leads a new player through every system
-- (plan's first path: spawn -> mentor -> academy -> training -> forge ->
-- gates). Kind: Class (pick a class), Train (training sessions), Kill,
-- Learn (skill ranks), Loot (materials picked up), Craft, Boss, Room
-- (record room), Level. Target = waypoint / place the floor guide leads to.
-- Rewards: XP x player level and credits, on talking to the mentor.
Config.Quests = {
	Story = {
		{ Id = "class", Title = "Выбери свой путь", Text = "Выбери класс в Академии классов.", Kind = "Class", Target = 1, Place = "Academy", Xp = 30, Credits = 40,
			Talk = "Добро пожаловать в Нано-Цитадель! Первым делом выбери свой путь: Клинок, Импульс или Стрелок. Академия — на востоке атриума." },
		{ Id = "train", Title = "Разминка", Text = "Потренируйся на станции в Тренировочном зале.", Kind = "Train", Target = 1, Place = "Training", Xp = 30, Credits = 40,
			Talk = "Отлично! Теперь разомнись: в Тренировочном зале на западе станции дают опыт." },
		{ Id = "kill", Title = "Первый бой", Text = "Победи 5 роботов в подземелье.", Kind = "Kill", Target = 5, Place = "Gates", Xp = 40, Credits = 60,
			Talk = "Пора в бой. Врата на севере ведут в Нано-фабрику. Победи пятерых роботов." },
		{ Id = "learn", Title = "Первое очко навыка", Text = "Изучи навык в дереве навыков [K].", Kind = "Learn", Target = 1, Xp = 40, Credits = 60,
			Talk = "За уровни ты получаешь очки навыков. Открой дерево навыков [K] и изучи первый приём." },
		{ Id = "loot", Title = "Добыча", Text = "Подбери 8 материалов с роботов (удерживай E).", Kind = "Loot", Target = 8, Place = "Gates", Xp = 50, Credits = 80,
			Talk = "Роботы роняют материалы. Подходи и удерживай E, чтобы подобрать." },
		{ Id = "craft", Title = "Первый крафт", Text = "Создай предмет в Фабрикаторе.", Kind = "Craft", Target = 1, Place = "Forge", Xp = 60, Credits = 100,
			Talk = "Из материалов делают снаряжение. Фабрикатор — на северо-востоке." },
		{ Id = "boss", Title = "Первый босс", Text = "Победи босса на 5-м этапе.", Kind = "Boss", Target = 1, Place = "Gates", Xp = 80, Credits = 150,
			Talk = "Каждый 5-й этап — босс. Покажи ему, на что способен твой класс." },
		{ Id = "room7", Title = "Глубже", Text = "Дойди до 7-го этапа.", Kind = "Room", Target = 7, Place = "Gates", Xp = 90, Credits = 180,
			Talk = "Дальше — Криолаборатория. Дойди до 7-го этапа." },
		{ Id = "skills5", Title = "Сборка", Text = "Вложи 5 очков в дерево навыков.", Kind = "Learn", Target = 5, Xp = 90, Credits = 180,
			Talk = "Собери свою сборку: вложи пять очков в навыки." },
		{ Id = "level10", Title = "Оператор", Text = "Достигни 10-го уровня.", Kind = "Level", Target = 10, Xp = 100, Credits = 220,
			Talk = "Звание Оператора — на 10-м уровне. Продолжай!" },
		{ Id = "room10", Title = "Второй босс", Text = "Дойди до 10-го этапа.", Kind = "Room", Target = 10, Place = "Gates", Xp = 120, Credits = 300,
			Talk = "На 10-м этапе ждёт следующий босс." },
		{ Id = "craft3", Title = "Арсенал", Text = "Создай 3 предмета в Фабрикаторе.", Kind = "Craft", Target = 3, Place = "Forge", Xp = 120, Credits = 300,
			Talk = "Сильное снаряжение — главный источник силы. Создай ещё три предмета." },
		{ Id = "room15", Title = "Сердце реактора", Text = "Дойди до 15-го этапа.", Kind = "Room", Target = 15, Place = "Gates", Xp = 160, Credits = 500,
			Talk = "Плавильный реактор горяч. Дойди до 15-го этапа." },
		{ Id = "level30", Title = "Страж", Text = "Достигни 30-го уровня.", Kind = "Level", Target = 30, Xp = 200, Credits = 800,
			Talk = "Страж Цитадели — 30-й уровень. Ты почти легенда." },
	},
	Done = "Все задания Наставника выполнены. Ежедневные задания — у Смотрителя Врат.",
	Ready = "Задание выполнено! Вернись к Наставнику.",
	ReadyTalk = "Отлично, задание выполнено! Держи награду — и сразу дам следующее.",
	Texts = { Accept = "Принять", Claim = "Получить награду", Later = "Позже", Close = "Закрыть", Reward = "Награда: %s XP, %s кр." },
}
Config.QuestById = {}
for index, q in ipairs(Config.Quests.Story) do
	q.Index = index
	Config.QuestById[q.Id] = q
end

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
	-- WallMaterial / FloorMaterial / PanelMaterial = the biome's surfaces;
	-- Decor = its side-wall set (Assembly: conveyor, Cryo: cryo tanks and
	-- frost, Smelter: molten channel under grating, Nexus: server racks
	-- and data pillars).
	Biomes = {
		{ Name = "Сборочный цех", Theme = "Assembly", WallMaterial = Enum.Material.Concrete, FloorMaterial = Enum.Material.DiamondPlate, PanelMaterial = Enum.Material.Metal, Decor = "Assembly",
			StoneA = Color3.fromRGB(128, 130, 138), StoneB = Color3.fromRGB(108, 110, 118), Floor = Color3.fromRGB(62, 64, 70), FloorB = Color3.fromRGB(52, 54, 60),
			Metal = Color3.fromRGB(70, 74, 84), Accent = Color3.fromRGB(255, 190, 60), Light = Color3.fromRGB(255, 222, 180), Glow = Color3.fromRGB(255, 170, 50),
			Atmosphere = { Color = Color3.fromRGB(140, 130, 115), Decay = Color3.fromRGB(80, 70, 60) },
			Lighting = { Ambient = Color3.fromRGB(92, 88, 82), OutdoorAmbient = Color3.fromRGB(80, 78, 76) } },
		{ Name = "Криолаборатория", Theme = "Cryo", WallMaterial = Enum.Material.SmoothPlastic, FloorMaterial = Enum.Material.SmoothPlastic, PanelMaterial = Enum.Material.Glass, Decor = "Cryo",
			StoneA = Color3.fromRGB(176, 196, 214), StoneB = Color3.fromRGB(150, 172, 192), Floor = Color3.fromRGB(64, 78, 96), FloorB = Color3.fromRGB(54, 66, 84),
			Metal = Color3.fromRGB(90, 104, 122), Accent = Color3.fromRGB(46, 230, 255), Light = Color3.fromRGB(220, 240, 255), Glow = Color3.fromRGB(120, 230, 255),
			Atmosphere = { Color = Color3.fromRGB(150, 180, 205), Decay = Color3.fromRGB(80, 105, 135) },
			Lighting = { Ambient = Color3.fromRGB(84, 92, 104), OutdoorAmbient = Color3.fromRGB(80, 88, 100) } },
		{ Name = "Плавильный реактор", Theme = "Smelter", WallMaterial = Enum.Material.Metal, FloorMaterial = Enum.Material.DiamondPlate, PanelMaterial = Enum.Material.Metal, Decor = "Smelter",
			StoneA = Color3.fromRGB(122, 104, 96), StoneB = Color3.fromRGB(102, 86, 80), Floor = Color3.fromRGB(56, 46, 44), FloorB = Color3.fromRGB(46, 38, 36),
			Metal = Color3.fromRGB(70, 60, 58), Accent = Color3.fromRGB(255, 120, 40), Light = Color3.fromRGB(255, 200, 150), Glow = Color3.fromRGB(255, 110, 30),
			Atmosphere = { Color = Color3.fromRGB(170, 120, 95), Decay = Color3.fromRGB(110, 60, 40) },
			Lighting = { Ambient = Color3.fromRGB(100, 82, 74), OutdoorAmbient = Color3.fromRGB(88, 74, 68) } },
		{ Name = "Ядро Нексуса", Theme = "Nexus", WallMaterial = Enum.Material.Foil, FloorMaterial = Enum.Material.SmoothPlastic, PanelMaterial = Enum.Material.Foil, Decor = "Nexus",
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
	ToastSeconds = 4,
	ShakeCrit = { Amplitude = 0.25, Seconds = 0.15 },
	ShakeBoss = { Amplitude = 0.8, Seconds = 0.5 },
	DamageHint = "Твой урон %s  •  этап %d: нужно %s", -- HUD plate in the dungeon: the room you stand in or your next record room
	BackKey = Enum.KeyCode.B,
	MobileScaleWidth = 1100, -- UIScale = min(1, viewportWidth / this)
}

-- Interface in the reference style: dark graphite panels with cut corners,
-- thin gold lines, monochrome line icons (ui/Icons), dense bold font.
-- No bright tiles, no emoji. Sizes are for a 1280x720 screen; the HUD is
-- scaled down on small screens (Hud.MobileScaleWidth).
Config.Ui = {
	Cut = 10, -- corner cut of panels (px)
	CutSmall = 6,
	Border = 1.5, -- thin gold line
	PanelTransparency = 0.12, -- HUD panels are slightly see-through
	WindowTransparency = 0.04,
	-- Top-left: profile under the Roblox buttons, the icon bar under it.
	Profile = { Width = 300, Height = 86, Avatar = 66 },
	-- Icon bar: Id = window, Key = hotkey (shown on the button; hidden on touch).
	Bar = {
		{ Id = "Inventory", Icon = "bag", Label = "Инвентарь", Key = Enum.KeyCode.G },
		{ Id = "Skills", Icon = "skills", Label = "Навыки", Key = Enum.KeyCode.K },
		{ Id = "Quests", Icon = "quest", Label = "Задания", Key = Enum.KeyCode.J },
		{ Id = "Shop", Icon = "gem", Label = "Магазин" },
	},
	BarButton = 50,
	-- Bottom center: HP and the ability slots (Q / E / R / dash).
	AbilitySlots = {
		{ Slot = "Q", Key = Enum.KeyCode.Q },
		{ Slot = "E", Key = Enum.KeyCode.E },
		{ Slot = "R", Key = Enum.KeyCode.R },
		{ Slot = "Dash", Key = Enum.KeyCode.LeftShift, Label = "Shift", Icon = "dash" },
		{ Slot = "Block", Key = Enum.KeyCode.F, Label = "F", Icon = "shield", Class = "Blade" }, -- hold
	},
	AbilitySize = 62,
	HealthWidth = 420,
	-- Bottom right: the big gold button. In the hub it opens the Gates
	-- window (modes), in the dungeon it brings you back to the hub.
	Play = { Text = "ИГРАТЬ", Back = "В ХАБ", BackKey = Enum.KeyCode.B },
	Modes = {
		{ Id = "Dungeon", Name = "Нано-фабрика", Text = "Подземелье: 20 этапов, босс каждые 5", Icon = "gate" },
		{ Id = "Bosses", Name = "Испытание боссов", Text = "Скоро", Icon = "skull", Locked = true },
		{ Id = "Raid", Name = "Рейд Нексуса", Text = "Скоро · группы до 4 игроков", Icon = "crown", Locked = true },
	},
	Texts = {
		NoClass = "Без класса",
		Quest = "ЗАДАНИЕ",
		NoQuest = "Поговори с Наставником в атриуме",
		Gates = "ВРАТА",
		GatesSub = "Выбери режим",
		Enter = "Войти",
		Locked = "Закрыто",
		CreditsName = "кредитов",
	},
}

-- Ranks by level (shown under the name in the profile).
Config.Ranks = {
	{ Level = 1, Name = "Новобранец" },
	{ Level = 10, Name = "Оператор" },
	{ Level = 20, Name = "Страж" },
	{ Level = 35, Name = "Командор" },
	{ Level = 50, Name = "Легенда Нексуса" },
}

function Config.RankFor(level: number)
	local rank = Config.Ranks[1]
	for _, r in ipairs(Config.Ranks) do
		if level >= r.Level then
			rank = r
		end
	end
	return rank
end

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
