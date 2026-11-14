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
	OwnedArmor = {}, -- [armorId] = true
	EquippedArmor = { Helmet = "", Chest = "", Legs = "" },
	Materials = {}, -- [materialId] = count
	OwnedPets = {},
	EquippedPet = "",
	RoomReached = 0, -- highest dungeon room cleared (0 = none, 20 = all)
	TrainersUnlocked = { ["1"] = true }, -- trainer ids whose Aura requirement was reached (permanent)
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
	BaseDamage = 1, -- damage of one click with weapon x1 and no Aura
	CritChance = 0.1, -- 10% chance per click
	CritMultiplier = 5, -- crit = damage x5
	Cooldown = 0.1, -- min seconds between accepted clicks per player (anti-macro)
	Range = 60, -- max studs between player and a clicked mob
	MeleeRange = 16, -- a click with no target hits the nearest mob within this range
}

-- Aura = strength + currency. It comes ONLY from clicks, auto-click and
-- trainers (mobs give materials, never Aura).
--   click anywhere            -> ClickBase
--   click on a trainer        -> + TrainerClickBonus x trainer multiplier
--   standing on a trainer     -> TrainerTickBase x trainer multiplier every
--                                TrainerTickInterval seconds, no clicks needed
-- Every gain is then multiplied by pets / rebirths / passes / boosts.
Config.Aura = {
	ClickBase = 1,
	TrainerClickBonus = 1,
	TrainerTickInterval = 1,
	TrainerTickBase = 3,
	TrainerCheckInterval = 0.2, -- how often the server looks which trainer a player stands on
	AutoClickInterval = 0.35, -- server-side auto-click period
	-- Without the "AutoClick" game pass the auto-click toggle works only
	-- while standing on a trainer; with the pass it works everywhere.
	AutoClickFreeOnTrainer = true,
}

-- Damage of one click = weapon base x AuraPower(Aura) x armor set bonus
-- x pets x passes x boosts x rebirths. AuraPower grows with the
-- logarithm of Aura: 0 -> x1, 1K -> x3.25, 100K -> x4.75, 10M -> x6.25.
Config.Damage = {
	AuraPowerK = 0.75,
}

function Config.AuraPower(aura: number): number
	return 1 + math.log10(math.max(0, aura) + 1) * Config.Damage.AuraPowerK
end

-- Robux game passes. Id = 0 means "not created yet": buttons show
-- "Скоро" and nothing is checked. Put the real ids from the Creator
-- Dashboard here (see README).
Config.VipAuraMultiplier = 1.5

Config.GamePasses = {
	VIP = { Id = 0, Name = "VIP", Price = 199, Text = "x1.5 Аура, VIP-тег и VIP-тренажёр" },
	GoldTrainer = { Id = 0, Name = "Золотой тренажёр", Price = 299, Text = "Доступ к тренажёру x500" },
	AbyssTrainer = { Id = 0, Name = "Тренажёр бездны", Price = 499, Text = "Доступ к тренажёру x1000" },
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
	RecommendedBase = 3,
	RecommendedGrowth = 1.5, -- r1 = 3, r5 ~ 15, r10 ~ 115, r15 ~ 875, r20 ~ 6650
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
		BossSlamRadius = 16,
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

-- Materials: what mobs drop and what the forge consumes. Biome = index
-- into Config.DungeonLayout.Biomes. Shape = mini-model built from Parts
-- by Shared.MaterialBuilder. Ids are stored in saves: never rename.
Config.Materials = {
	-- 1. Катакомбы
	{ Id = "Bone", Name = "Кость", Biome = 1, Rarity = "Common", Shape = "Bone", Color = Color3.fromRGB(235, 230, 215) },
	{ Id = "Slime", Name = "Слизь", Biome = 1, Rarity = "Uncommon", Shape = "Blob", Color = Color3.fromRGB(110, 235, 120) },
	{ Id = "RustyIron", Name = "Ржавое железо", Biome = 1, Rarity = "Rare", Shape = "Ingot", Color = Color3.fromRGB(165, 95, 60) },
	{ Id = "CursedSkull", Name = "Проклятый череп", Biome = 1, Rarity = "Epic", Shape = "Skull", Color = Color3.fromRGB(190, 120, 255) },
	{ Id = "CatacombHeart", Name = "Сердце катакомб", Biome = 1, Rarity = "Secret", Shape = "Heart", Color = Color3.fromRGB(255, 90, 160) },
	-- 2. Ледяной грот
	{ Id = "Ice", Name = "Лёд", Biome = 2, Rarity = "Common", Shape = "Cube", Color = Color3.fromRGB(170, 225, 255) },
	{ Id = "YetiFur", Name = "Мех йети", Biome = 2, Rarity = "Uncommon", Shape = "Fur", Color = Color3.fromRGB(240, 245, 250) },
	{ Id = "FrostCrystal", Name = "Морозный кристалл", Biome = 2, Rarity = "Rare", Shape = "Crystal", Color = Color3.fromRGB(90, 190, 255) },
	{ Id = "EternalIce", Name = "Вечный лёд", Biome = 2, Rarity = "Legendary", Shape = "Star", Color = Color3.fromRGB(140, 240, 255) },
	-- 3. Лавовая кузня
	{ Id = "Obsidian", Name = "Обсидиан", Biome = 3, Rarity = "Common", Shape = "Shards", Color = Color3.fromRGB(45, 35, 60) },
	{ Id = "Ember", Name = "Тлеющий уголь", Biome = 3, Rarity = "Uncommon", Shape = "Coal", Color = Color3.fromRGB(255, 130, 40) },
	{ Id = "MagmaCore", Name = "Магма-ядро", Biome = 3, Rarity = "Rare", Shape = "Core", Color = Color3.fromRGB(255, 110, 30) },
	{ Id = "FirePlume", Name = "Огненное перо", Biome = 3, Rarity = "Epic", Shape = "Feather", Color = Color3.fromRGB(255, 170, 50) },
	{ Id = "VolcanoHeart", Name = "Сердце вулкана", Biome = 3, Rarity = "Mythic", Shape = "Heart", Color = Color3.fromRGB(255, 80, 40) },
	-- 4. Бездна ауры
	{ Id = "DarkShard", Name = "Осколок тьмы", Biome = 4, Rarity = "Common", Shape = "Shards", Color = Color3.fromRGB(70, 40, 120) },
	{ Id = "ShadowDust", Name = "Теневая пыль", Biome = 4, Rarity = "Uncommon", Shape = "Dust", Color = Color3.fromRGB(120, 90, 170) },
	{ Id = "AuraEssence", Name = "Аура-эссенция", Biome = 4, Rarity = "Rare", Shape = "Vial", Color = Color3.fromRGB(255, 61, 184) },
	{ Id = "AbyssEye", Name = "Глаз бездны", Biome = 4, Rarity = "Legendary", Shape = "Eye", Color = Color3.fromRGB(170, 80, 255) },
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
	SpinSeconds = 4,
	BeamHeight = 14,
	Texts = {
		Pickup = "Подобрать",
		Announce = "%s выбил %s предмет: %s!",
		Picked = "+%d %s",
	},
}

-- Mobs: 3 kinds + a boss per biome. Drops = materials this mob can
-- drop; the rarity is rolled first (Config.Rarities), then a material of
-- that rarity is picked from this list (nearest lower rarity, else the
-- nearest higher one, when the mob has none of the rolled rarity).
-- The model of every kind is built by MobBuilder (one builder per id).
Config.Mobs = {
	Biomes = {
		{ Kinds = { "ZombieMiner", "SkeletonArcher", "AcidSlime" }, Boss = "SlimeKing" },
		{ Kinds = { "SnowGolem", "IceSpider", "Yeti" }, Boss = "IceBoneLord" },
		{ Kinds = { "FireImp", "MagmaGolem", "GoblinSmith" }, Boss = "FireChief" },
		{ Kinds = { "ShadowKnight", "FlyingEye", "AuraGhost" }, Boss = "AbyssLord" },
	},
	Defs = {
		ZombieMiner = { Name = "Зомби-шахтёр", Drops = { "Bone", "RustyIron", "CursedSkull", "CatacombHeart" } },
		SkeletonArcher = { Name = "Скелет-лучник", Drops = { "Bone", "Slime", "RustyIron", "CursedSkull", "CatacombHeart" } },
		AcidSlime = { Name = "Кислотный слизень", Drops = { "Slime", "RustyIron", "CursedSkull", "CatacombHeart" } },
		SlimeKing = { Name = "Король Слизней", Boss = true, Drops = { "Bone", "Slime", "RustyIron", "CursedSkull", "CatacombHeart" } },

		SnowGolem = { Name = "Снежный голем", Drops = { "Ice", "FrostCrystal", "EternalIce" } },
		IceSpider = { Name = "Ледяной паук", Drops = { "Ice", "YetiFur", "FrostCrystal", "EternalIce" } },
		Yeti = { Name = "Йети", Drops = { "YetiFur", "FrostCrystal", "EternalIce" } },
		IceBoneLord = { Name = "Ледяной Костяной Лорд", Boss = true, Drops = { "Ice", "YetiFur", "FrostCrystal", "EternalIce" } },

		FireImp = { Name = "Огненный бес", Drops = { "Ember", "Obsidian", "FirePlume", "VolcanoHeart" } },
		MagmaGolem = { Name = "Магма-голем", Drops = { "Obsidian", "MagmaCore", "FirePlume", "VolcanoHeart" } },
		GoblinSmith = { Name = "Гоблин-кузнец", Drops = { "Obsidian", "Ember", "MagmaCore", "VolcanoHeart" } },
		FireChief = { Name = "Огненный Вождь", Boss = true, Drops = { "Obsidian", "Ember", "MagmaCore", "FirePlume", "VolcanoHeart" } },

		ShadowKnight = { Name = "Теневой рыцарь", Drops = { "DarkShard", "ShadowDust", "AuraEssence", "AbyssEye" } },
		FlyingEye = { Name = "Летающий глаз", Drops = { "DarkShard", "AuraEssence", "AbyssEye" } },
		AuraGhost = { Name = "Аура-призрак", Drops = { "ShadowDust", "AuraEssence", "AbyssEye" } },
		AbyssLord = { Name = "Повелитель Бездны", Boss = true, Drops = { "DarkShard", "ShadowDust", "AuraEssence", "AbyssEye" } },
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
	Health = 100, -- base max health (+ armor)
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

-- Weapons: Damage is the weapon base (see Config.Damage for the full
-- formula). One weapon is active. Weapons are CRAFTED at the forge from
-- materials (Config.Recipes): 4 per biome, each stronger than the last.
-- Shape = model built by Shared.WeaponBuilder. Legacy = bought in an
-- older version of the game: still owned and usable, not craftable.
-- Ids are stored in saves: never rename.
Config.Weapons = {
	{ Id = "Stick", Name = "Палка", Rarity = "Common", Damage = 1, Shape = "Stick", Color = Color3.fromRGB(150, 110, 70) },
	-- 1. Катакомбы
	{ Id = "BoneSword", Name = "Костяной меч", Rarity = "Common", Damage = 2, Biome = 1, Shape = "BoneSword", Color = Color3.fromRGB(235, 230, 215) },
	{ Id = "SlimeDagger", Name = "Слизневый кинжал", Rarity = "Uncommon", Damage = 3, Biome = 1, Shape = "SlimeDagger", Color = Color3.fromRGB(110, 235, 120) },
	{ Id = "RustCleaver", Name = "Ржавый тесак", Rarity = "Rare", Damage = 5, Biome = 1, Shape = "Cleaver", Color = Color3.fromRGB(165, 95, 60) },
	{ Id = "SkullMace", Name = "Булава Черепов", Rarity = "Epic", Damage = 8, Biome = 1, Shape = "SkullMace", Color = Color3.fromRGB(190, 120, 255) },
	-- 2. Ледяной грот
	{ Id = "IceBlade", Name = "Ледяной клинок", Rarity = "Uncommon", Damage = 12, Biome = 2, Shape = "IceBlade", Color = Color3.fromRGB(170, 225, 255) },
	{ Id = "YetiClub", Name = "Дубина йети", Rarity = "Rare", Damage = 18, Biome = 2, Shape = "YetiClub", Color = Color3.fromRGB(240, 245, 250) },
	{ Id = "FrostSpear", Name = "Морозное копьё", Rarity = "Epic", Damage = 28, Biome = 2, Shape = "FrostSpear", Color = Color3.fromRGB(90, 190, 255) },
	{ Id = "EternalBlade", Name = "Клинок Вечного льда", Rarity = "Legendary", Damage = 43, Biome = 2, Shape = "EternalBlade", Color = Color3.fromRGB(140, 240, 255) },
	-- 3. Лавовая кузня
	{ Id = "ObsidianAxe", Name = "Обсидиановый топор", Rarity = "Rare", Damage = 66, Biome = 3, Shape = "ObsidianAxe", Color = Color3.fromRGB(60, 45, 80) },
	{ Id = "EmberSword", Name = "Угольный меч", Rarity = "Epic", Damage = 100, Biome = 3, Shape = "EmberSword", Color = Color3.fromRGB(255, 130, 40) },
	{ Id = "MagmaHammer", Name = "Лавовый молот", Rarity = "Epic", Damage = 160, Biome = 3, Shape = "MagmaHammer", Color = Color3.fromRGB(255, 110, 30) },
	{ Id = "PhoenixBlade", Name = "Клинок Феникса", Rarity = "Legendary", Damage = 250, Biome = 3, Shape = "PhoenixBlade", Color = Color3.fromRGB(255, 170, 50) },
	-- 4. Бездна ауры
	{ Id = "ShadowKatana", Name = "Теневая катана", Rarity = "Epic", Damage = 380, Biome = 4, Shape = "ShadowKatana", Color = Color3.fromRGB(120, 90, 170) },
	{ Id = "DuskScythe", Name = "Коса сумрака", Rarity = "Legendary", Damage = 600, Biome = 4, Shape = "DuskScythe", Color = Color3.fromRGB(170, 80, 255) },
	{ Id = "AbyssBlade", Name = "Клинок бездны", Rarity = "Legendary", Damage = 920, Biome = 4, Shape = "AbyssBlade", Color = Color3.fromRGB(255, 61, 184) },
	{ Id = "AuraReaver", Name = "Разрушитель Ауры", Rarity = "Mythic", Damage = 1450, Biome = 4, Shape = "AuraReaver", Color = Color3.fromRGB(255, 230, 120) },
	-- Legacy (bought for Aura before crafting existed)
	{ Id = "WoodSword", Name = "Деревянный меч", Rarity = "Common", Damage = 3, Legacy = true, Shape = "WoodSword", Color = Color3.fromRGB(200, 150, 90) },
	{ Id = "IronSword", Name = "Железный меч", Rarity = "Rare", Damage = 10, Legacy = true, Shape = "IronSword", Color = Color3.fromRGB(190, 200, 215) },
	{ Id = "AuraKatana", Name = "Катана Ауры", Rarity = "Epic", Damage = 35, Legacy = true, Shape = "AuraKatana", Color = Color3.fromRGB(190, 110, 255) },
	{ Id = "StormBlade", Name = "Клинок Бури", Rarity = "Legendary", Damage = 120, Legacy = true, Shape = "StormBlade", Color = Color3.fromRGB(90, 200, 255) },
	{ Id = "EclipseScythe", Name = "Коса Затмения", Rarity = "Legendary", Damage = 450, Legacy = true, Shape = "EclipseScythe", Color = Color3.fromRGB(255, 120, 60) },
	{ Id = "StarAuraSword", Name = "Меч Звёздной Ауры", Rarity = "Mythic", Damage = 1600, Legacy = true, Shape = "StarAuraSword", Color = Color3.fromRGB(255, 230, 120) },
}

-- Armor: one set per biome, three pieces each (Helmet / Chest / Legs).
-- Health adds to the base Config.Player.Health, Defense is the share of
-- incoming damage removed. Wearing all 3 pieces of a set gives its
-- Bonus (damage multiplier). Style = look built by Shared.ArmorBuilder.
Config.ArmorSlots = { "Helmet", "Chest", "Legs" }
Config.ArmorSlotNames = { Helmet = "Шлем", Chest = "Нагрудник", Legs = "Поножи" }
Config.ArmorSets = {
	Bone = { Name = "Костяной сет", Biome = 1, Rarity = "Uncommon", Health = 20, Defense = 0.03, Bonus = 0.10,
		Style = { Kind = "Bone", Main = Color3.fromRGB(235, 228, 205), Trim = Color3.fromRGB(150, 135, 110), Glow = Color3.fromRGB(110, 235, 120), Material = Enum.Material.SmoothPlastic } },
	Ice = { Name = "Ледяной сет", Biome = 2, Rarity = "Rare", Health = 45, Defense = 0.05, Bonus = 0.20,
		Style = { Kind = "Ice", Main = Color3.fromRGB(150, 215, 255), Trim = Color3.fromRGB(240, 250, 255), Glow = Color3.fromRGB(46, 230, 255), Material = Enum.Material.Ice } },
	Lava = { Name = "Лавовый сет", Biome = 3, Rarity = "Epic", Health = 90, Defense = 0.07, Bonus = 0.35,
		Style = { Kind = "Lava", Main = Color3.fromRGB(50, 38, 42), Trim = Color3.fromRGB(120, 55, 40), Glow = Color3.fromRGB(255, 130, 30), Material = Enum.Material.Slate } },
	Abyss = { Name = "Сет бездны", Biome = 4, Rarity = "Legendary", Health = 160, Defense = 0.09, Bonus = 0.50,
		Style = { Kind = "Abyss", Main = Color3.fromRGB(60, 35, 110), Trim = Color3.fromRGB(255, 201, 60), Glow = Color3.fromRGB(255, 61, 184), Material = Enum.Material.Metal } },
}
Config.ArmorSetOrder = { "Bone", "Ice", "Lava", "Abyss" }
Config.Armor = {}
do
	local adjective = { Bone = { "Костяной", "Костяные" }, Ice = { "Ледяной", "Ледяные" }, Lava = { "Лавовый", "Лавовые" } }
	local noun = { Helmet = "шлем", Chest = "нагрудник", Legs = "поножи" }
	local nounCapital = { Helmet = "Шлем", Chest = "Нагрудник", Legs = "Поножи" }
	for _, setId in ipairs(Config.ArmorSetOrder) do
		local set = Config.ArmorSets[setId]
		set.Id = setId
		for _, slot in ipairs(Config.ArmorSlots) do
			local name = if setId == "Abyss" then nounCapital[slot] .. " бездны" else adjective[setId][if slot == "Legs" then 2 else 1] .. " " .. noun[slot]
			table.insert(Config.Armor, {
				Id = setId .. slot, -- "BoneHelmet", "IceChest", ... (stored in saves)
				Name = name,
				Slot = slot,
				Set = setId,
				Biome = set.Biome,
				Rarity = set.Rarity,
				Health = if slot == "Chest" then math.floor(set.Health * 1.5) else set.Health,
				Defense = set.Defense,
				Color = set.Style.Main,
			})
		end
	end
end

-- Forge recipes: materials + an Aura fee -> the item (Id = weapon or
-- armor id). Shown in this order inside each tab.
Config.Recipes = {
	-- Weapons
	{ Id = "BoneSword", Kind = "Weapon", Aura = 50, Materials = { Bone = 8 } },
	{ Id = "SlimeDagger", Kind = "Weapon", Aura = 200, Materials = { Bone = 12, Slime = 6 } },
	{ Id = "RustCleaver", Kind = "Weapon", Aura = 800, Materials = { Bone = 20, RustyIron = 4 } },
	{ Id = "SkullMace", Kind = "Weapon", Aura = 3000, Materials = { Bone = 30, Slime = 12, RustyIron = 6, CursedSkull = 1 } },
	{ Id = "IceBlade", Kind = "Weapon", Aura = 5000, Materials = { Ice = 15, RustyIron = 3 } },
	{ Id = "YetiClub", Kind = "Weapon", Aura = 10000, Materials = { Ice = 25, YetiFur = 10 } },
	{ Id = "FrostSpear", Kind = "Weapon", Aura = 20000, Materials = { Ice = 40, YetiFur = 15, FrostCrystal = 6 } },
	{ Id = "EternalBlade", Kind = "Weapon", Aura = 40000, Materials = { Ice = 60, FrostCrystal = 10, EternalIce = 1 } },
	{ Id = "ObsidianAxe", Kind = "Weapon", Aura = 60000, Materials = { Obsidian = 30, Ember = 10 } },
	{ Id = "EmberSword", Kind = "Weapon", Aura = 100000, Materials = { Obsidian = 45, Ember = 20, MagmaCore = 5 } },
	{ Id = "MagmaHammer", Kind = "Weapon", Aura = 160000, Materials = { Obsidian = 70, MagmaCore = 8, FirePlume = 2 } },
	{ Id = "PhoenixBlade", Kind = "Weapon", Aura = 250000, Materials = { Obsidian = 100, MagmaCore = 14, FirePlume = 5 } },
	{ Id = "ShadowKatana", Kind = "Weapon", Aura = 350000, Materials = { DarkShard = 40, ShadowDust = 15 } },
	{ Id = "DuskScythe", Kind = "Weapon", Aura = 500000, Materials = { DarkShard = 60, ShadowDust = 25, AuraEssence = 8 } },
	{ Id = "AbyssBlade", Kind = "Weapon", Aura = 750000, Materials = { DarkShard = 90, AuraEssence = 12, AbyssEye = 1 } },
	{ Id = "AuraReaver", Kind = "Weapon", Aura = 1200000, Materials = { DarkShard = 140, AuraEssence = 20, AbyssEye = 3, EternalIce = 2 } },
	-- Armor
	{ Id = "BoneHelmet", Kind = "Armor", Aura = 150, Materials = { Bone = 10, Slime = 3 } },
	{ Id = "BoneChest", Kind = "Armor", Aura = 400, Materials = { Bone = 18, Slime = 6, RustyIron = 2 } },
	{ Id = "BoneLegs", Kind = "Armor", Aura = 250, Materials = { Bone = 14, Slime = 4 } },
	{ Id = "IceHelmet", Kind = "Armor", Aura = 8000, Materials = { Ice = 20, YetiFur = 8 } },
	{ Id = "IceChest", Kind = "Armor", Aura = 15000, Materials = { Ice = 35, YetiFur = 14, FrostCrystal = 4 } },
	{ Id = "IceLegs", Kind = "Armor", Aura = 11000, Materials = { Ice = 28, YetiFur = 10, FrostCrystal = 2 } },
	{ Id = "LavaHelmet", Kind = "Armor", Aura = 80000, Materials = { Obsidian = 35, Ember = 12, MagmaCore = 3 } },
	{ Id = "LavaChest", Kind = "Armor", Aura = 140000, Materials = { Obsidian = 60, Ember = 20, MagmaCore = 6, FirePlume = 1 } },
	{ Id = "LavaLegs", Kind = "Armor", Aura = 100000, Materials = { Obsidian = 45, Ember = 15, MagmaCore = 4 } },
	{ Id = "AbyssHelmet", Kind = "Armor", Aura = 400000, Materials = { DarkShard = 50, ShadowDust = 20, AuraEssence = 5 } },
	{ Id = "AbyssChest", Kind = "Armor", Aura = 700000, Materials = { DarkShard = 80, ShadowDust = 30, AuraEssence = 10, AbyssEye = 1 } },
	{ Id = "AbyssLegs", Kind = "Armor", Aura = 500000, Materials = { DarkShard = 60, ShadowDust = 24, AuraEssence = 6 } },
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
		NoAura = "Не хватает Ауры",
		Skip = "Пропустить",
		Done = "Выковано: %s!",
	},
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
	MultiplierPerRebirth = 0.25, -- applies to Aura gains AND damage
}

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

-- Hub trainers. Requirements: Aura (remembered forever once reached),
-- Rebirths, or a game pass (Premium). Ids are stored in saves
-- (TrainersUnlocked) -- never rename them.
Config.Trainers = {
	{ Id = "1", Kind = "Dummy", Name = "Манекен", Multiplier = 1, Color = Color3.fromRGB(90, 230, 110) },
	{ Id = "2", Kind = "Boulder", Name = "Валун", Multiplier = 3, Aura = 500, Color = Color3.fromRGB(70, 140, 255) },
	{ Id = "3", Kind = "IceCube", Name = "Ледяной куб", Multiplier = 6, Aura = 5000, Color = Color3.fromRGB(46, 230, 255) },
	{ Id = "4", Kind = "Mimic", Name = "Сундук-мимик", Multiplier = 12, Aura = 50000, Color = Color3.fromRGB(255, 150, 50) },
	{ Id = "5", Kind = "Skull", Name = "Гигантский череп", Multiplier = 25, Aura = 500000, Color = Color3.fromRGB(230, 230, 240), Particles = true },
	{ Id = "6", Kind = "Pumpkin", Name = "Тыква-монстр", Multiplier = 50, Rebirths = 1, Color = Color3.fromRGB(255, 120, 30), Particles = true },
	{ Id = "7", Kind = "Golem", Name = "Кристальный голем", Multiplier = 100, Rebirths = 2, Color = Color3.fromRGB(150, 80, 255), Particles = true },
	{ Id = "8", Kind = "Core", Name = "Аура-ядро", Multiplier = 250, Rebirths = 4, Color = Color3.fromRGB(255, 61, 184), Particles = true },
	{ Id = "VIP", Kind = "Throne", Name = "VIP-трон", Multiplier = 100, Pass = "VIP", Premium = true, Color = Color3.fromRGB(255, 201, 60), Particles = true },
	{ Id = "Gold", Kind = "Idol", Name = "Золотой идол", Multiplier = 500, Pass = "GoldTrainer", Premium = true, Color = Color3.fromRGB(255, 215, 80), Particles = true },
	{ Id = "Abyss", Kind = "AbyssPortal", Name = "Портал бездны", Multiplier = 1000, Pass = "AbyssTrainer", Premium = true, Color = Color3.fromRGB(170, 80, 255), Particles = true },
}
Config.TrainerById = {}
for _, trainer in ipairs(Config.Trainers) do
	Config.TrainerById[trainer.Id] = trainer
end

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
			{ Id = "train500", Kind = "Train", Target = 300, Text = "Кликни на тренажёре 300 раз", Aura = 400 },
			{ Id = "train1500", Kind = "Train", Target = 1000, Text = "Кликни на тренажёре 1000 раз", Aura = 1200 },
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
	AuraStore = "AuraClicker_TopAura_v1",
	RoomStore = "AuraClicker_TopRoom_v1",
	RefreshSeconds = 60,
	Top = 10,
}

-- Shop categories (what is owned / equipped and how to describe it).
Config.Shop = {
	Weapon = { Title = "Оружие", Items = Config.Weapons, OwnedKey = "OwnedWeapons", EquippedKey = "EquippedWeapon", Purchasable = false,
		Describe = function(item) return "Урон " .. item.Damage end },
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

Config.ItemById.Armor = {}
for order, piece in ipairs(Config.Armor) do
	piece.Order = order
	Config.ItemById.Armor[piece.Id] = piece
end

-- All remotes live directly in ReplicatedStorage, created by the server.
Config.Remotes = {
	ClickHit = "RemoteEvent", -- C->S (mob or nil) on every click; S->C ("Aura"|"Tick"|"Hit"|"Kill", ...)
	ShopRequest = "RemoteFunction", -- ("Equip", "Weapon"|"Armor", id) | ("Unequip", "Armor", slot) | pets -> ok, message
	Craft = "RemoteFunction", -- (recipeId) -> ok, message
	RebirthRequest = "RemoteFunction", -- () -> ok, message
	Travel = "RemoteFunction", -- ("Hub") | ("Room", n) -> ok, message
	Notify = "RemoteEvent", -- S->C (text, kind) toast
	AutoClick = "RemoteEvent", -- C->S (enabled: boolean)
	RoomState = "RemoteEvent", -- S->C (room, alive, total) for the player's own run
	RunEnded = "RemoteEvent", -- S->C (reason, room, auraEarned, record, isNewRecord)
	Progression = "RemoteFunction", -- ("Status") | ("ClaimDaily") | ("Spin") | ("ClaimQuest", index) -> ok, payload
	Loot = "RemoteEvent", -- S->C ("Spawn", id, materialId, position, lifetime) | ("Picked", id, materialId, total) | ("Remove", id) | ("Clear"); C->S (id) pick up
	Announce = "RemoteEvent", -- S->all (text, color) system chat line + toast
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
-- VISUAL: hub layout
---------------------------------------------------------------------

-- All offsets are from the SpawnLocation; north (the portal) is -Z,
-- west is -X. Top view:
--
--                 [ PORTAL ]
--     TRAINERS        |          FORGE
--     (2 rows of 4)   |      (big building)
--     Eggs        [FOUNTAIN]     Premium showcase
--     Wheel           |      (Robux trainers, store)
--     Leaderboards [ SPAWN ]     Rebirth altar
Config.HubLayout = {
	Name = "Цитадель Ауры",
	Size = 176, -- courtyard side (square)
	Center = Vector3.new(0, 0, -60), -- courtyard center: the spawn sits near the south wall
	TileSize = 8,
	WallHeight = 14,
	WallThickness = 4,
	TowerSize = 12,
	TowerHeight = 24,
	MerlonSize = 2,

	PathWidth = 16, -- main straight path spawn -> portal
	SidePathWidth = 7,
	ChevronSpacing = 9,
	LanternSpacing = 24,

	Portal = { Offset = Vector3.new(0, 0, -138), Radius = 7, ArchWidth = 22, ArchHeight = 20, SpinSeconds = 6 },
	Fountain = { Offset = Vector3.new(0, 0, -52), Radius = 7, PlazaRadius = 17 },

	-- Trainers: a square "territory" each. Regular ones stand west of the
	-- path in 2 rows of 4 (step 20) facing the path, premium ones east.
	TrainerSize = 12,
	TrainerSpots = {
		["1"] = Vector3.new(-38, 0, -76), ["2"] = Vector3.new(-38, 0, -96), ["3"] = Vector3.new(-38, 0, -116), ["4"] = Vector3.new(-38, 0, -136),
		["5"] = Vector3.new(-60, 0, -76), ["6"] = Vector3.new(-60, 0, -96), ["7"] = Vector3.new(-60, 0, -116), ["8"] = Vector3.new(-60, 0, -136),
		VIP = Vector3.new(50, 0, -24), Gold = Vector3.new(50, 0, -44), Abyss = Vector3.new(50, 0, -64),
	},

	-- The forge: the main visual object of the hub (north-east). Samples
	-- on its racks are a showcase of craftable gear, not a shop.
	Forge = {
		Offset = Vector3.new(54, 0, -108),
		SignOffset = Vector3.new(30, 0, -96),
		SampleWeapons = { "BoneSword", "FrostSpear", "MagmaHammer", "AbyssBlade" },
		SampleArmor = { "Bone", "Lava", "Abyss" }, -- armor sets on the three stands
	},
	Store = { Offset = Vector3.new(36, 0, -55), SignOffset = Vector3.new(30, 0, -33) }, -- premium kiosk beside the Robux trainers
	Egg = { Offset = Vector3.new(-46, 0, -28) },
	Wheel = { Offset = Vector3.new(-46, 0, -50) },
	Altar = { Offset = Vector3.new(48, 0, 6) },
	Leaderboards = { -- free-standing boards west of the spawn, facing it
		{ Offset = Vector3.new(-44, 0, -4), Kind = "Aura", Title = "Топ Ауры" },
		{ Offset = Vector3.new(-44, 0, 15), Kind = "Room", Title = "Глубже всех в данже" },
	},
	Npc = { Offset = Vector3.new(11, 0, -12) },

	Trees = { Vector3.new(-78, 0, 18), Vector3.new(78, 0, 18), Vector3.new(-78, 0, -44), Vector3.new(78, 0, -84), Vector3.new(20, 0, -138), Vector3.new(-20, 0, -138), Vector3.new(80, 0, -138) },
	Bushes = { Vector3.new(-22, 0, 14), Vector3.new(22, 0, 14), Vector3.new(-70, 0, -40), Vector3.new(70, 0, -8), Vector3.new(-78, 0, -100), Vector3.new(24, 0, -76), Vector3.new(-22, 0, -124), Vector3.new(72, 0, -76) },
	FlowerBeds = { Vector3.new(-18, 0, -34), Vector3.new(18, 0, -34), Vector3.new(-18, 0, -70), Vector3.new(18, 0, -70) },
	Benches = { -- offset + facing direction
		{ Offset = Vector3.new(-13, 0, -52), Facing = Vector3.new(1, 0, 0) },
		{ Offset = Vector3.new(13, 0, -52), Facing = Vector3.new(-1, 0, 0) },
		{ Offset = Vector3.new(-14, 0, -14), Facing = Vector3.new(1, 0, 0) },
		{ Offset = Vector3.new(-14, 0, -100), Facing = Vector3.new(1, 0, 0) },
	},

	Texts = {
		Portal = "ПОДЗЕМЕЛЬЕ",
		Trainer = "x%s",
		TrainerOpen = "Встань сюда!",
		TrainerLockedAura = "Нужно %s Ауры",
		TrainerLockedRebirth = "Нужно перерождений: %d",
		TrainerLockedPass = "Game Pass · %d R$",
		TrainerSoon = "Скоро",
		TrainerHud = "Тренажёр x%s  ·  +%s/сек",
		Trainers = "ТРЕНАЖЁРЫ",
		Forge = "КУЗНИЦА",
		Premium = "ПРЕМИУМ",
		Store = "МАГАЗИН",
		Pets = "ПИТОМЦЫ",
		Altar = "АЛТАРЬ ПЕРЕРОЖДЕНИЯ",
		Wheel = "КОЛЕСО УДАЧИ",
		WheelFree = "Бесплатное вращение!",
		Egg = "Яйца питомцев",
		Npc = "Подземелье там!",
	},
	Prompts = {
		Rebirth = "Переродиться",
		Forge = "Кузница",
		Store = "Магазин",
		Egg = "Питомцы",
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

-- Mob presentation shared by every kind (the kinds: Config.Mobs).
Config.MobLooks = {
	BossScale = 2.5,
	KindsPerBiome = 3,
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
		{ Id = "Forge", Icon = "⚒", Label = "Кузница", Color = Color3.fromRGB(255, 120, 40) },
		{ Id = "Inventory", Icon = "🎒", Label = "Инвентарь", Color = Color3.fromRGB(70, 140, 255) },
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
	Hit = "rbxasset://sounds/swordslash.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav",
	Rebirth = "rbxasset://sounds/electronicpingshort.wav",
	Barrier = "", -- TODO: barrier dissolve
	Portal = "", -- TODO: portal whoosh
	BossDeath = "", -- TODO: boss explosion
	Ui = "", -- TODO: button click
}

return Config
