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
	ClickHit = "RemoteEvent", -- C->S (mob or nil) on every click; S->C ("Aura"|"Tick"|"Hit"|"Kill", ...)
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
		SampleWeapons = { "IronSword", "AuraKatana", "StormBlade", "StarAuraSword" },
		SampleArmor = {},
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
