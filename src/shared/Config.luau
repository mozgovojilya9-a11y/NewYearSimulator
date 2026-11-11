--[[
	Config.luau
	Shared, read-only game configuration and tuning values.
	Server and client both require this module; it contains no secrets.
]]

local Config = {}

Config.DataStoreName = "AuraClicker_v1"

-- Default data for a brand-new player. DataService backfills any
-- fields missing from an older save, so new fields can be added here
-- safely as the game grows.
Config.StartingData = {
	Aura = 0,
	Zone = 1,
	EquippedWeapon = "Stick",
	Rebirths = 0,
	Gems = 0, -- Day 3: second currency, dropped by mobs
	OwnedWeapons = { Stick = true }, -- Day 4
	OwnedBackpacks = {}, -- Day 5
	EquippedBackpack = "",
	OwnedPets = {}, -- Day 5
	EquippedPet = "",
}

-- Autosave interval (seconds) as a safety net in addition to
-- save-on-leave.
Config.AutosaveInterval = 120

-- Click mechanic (Day 2). The server is the source of truth for every
-- number here; the client only reads them for visuals/throttling.
Config.Click = {
	BaseDamage = 1, -- Aura gained per normal click
	CritChance = 0.1, -- 10% chance per click
	CritMultiplier = 5, -- crit click = BaseDamage * CritMultiplier
	Cooldown = 0.1, -- minimum seconds between accepted clicks per player
}

-- Built-in Roblox client sounds, so no uploaded asset is needed.
-- Swap for your own rbxassetid:// later if you want.
Config.Sounds = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav", -- played at a higher pitch
	Rebirth = "rbxasset://sounds/electronicpingshort.wav", -- played at a low pitch
}

-- Day 3: the first zone and its mobs.
-- The zone is generated at runtime in Workspace.AuraZone (nothing is
-- placed in Workspace by hand), Offset is relative to the SpawnLocation.
Config.Zone = {
	Name = "Поляна Ауры",
	Offset = Vector3.new(0, 0, -70),
	Radius = 48,
	HitDistance = 80, -- max studs between player and mob to land a hit
}

-- Each mob: HP, Aura reward on kill, gem drop chance/amount, respawn
-- time and how many copies live in the zone at once. Everyone who hit
-- a mob gets the full reward when it dies (no kill-stealing).
Config.Mobs = {
	{
		Id = "Slime", Name = "Слизень", Health = 8, Reward = 15,
		GemChance = 0.05, Gems = 1, Respawn = 3, Count = 4,
		Size = Vector3.new(4, 4, 4), Shape = "Ball", Color = Color3.fromRGB(110, 230, 120),
	},
	{
		Id = "Goblin", Name = "Гоблин", Health = 40, Reward = 80,
		GemChance = 0.15, Gems = 1, Respawn = 4, Count = 3,
		Size = Vector3.new(3, 5, 3), Shape = "Block", Color = Color3.fromRGB(150, 120, 70),
	},
	{
		Id = "Shade", Name = "Тень", Health = 200, Reward = 450,
		GemChance = 0.4, Gems = 2, Respawn = 6, Count = 2,
		Size = Vector3.new(4, 7, 4), Shape = "Block", Color = Color3.fromRGB(70, 50, 110),
	},
	{
		Id = "Guardian", Name = "Страж Ауры", Health = 2500, Reward = 6000,
		GemChance = 1, Gems = 5, Respawn = 45, Count = 1, Boss = true,
		Size = Vector3.new(9, 12, 9), Shape = "Block", Color = Color3.fromRGB(170, 90, 255),
	},
}

Config.MobById = {}
for _, mob in ipairs(Config.Mobs) do
	Config.MobById[mob.Id] = mob
end

-- All RemoteEvents/RemoteFunctions live directly in ReplicatedStorage
-- and are created by the server on startup.
Config.Remotes = {
	ClickHit = "RemoteEvent",
	MobHit = "RemoteEvent",
	ShopRequest = "RemoteFunction", -- Day 4: (action, category, id) -> ok, message
	RebirthRequest = "RemoteFunction", -- Day 6: () -> ok, message
}

-- Day 6: rebirth. Costs Aura, resets Aura/weapons/backpacks, keeps Gems
-- and pets, and permanently multiplies all Aura gains:
--   multiplier = 1 + Rebirths * MultiplierPerRebirth
--   cost       = BaseCost * CostGrowth ^ Rebirths
Config.Rebirth = {
	BaseCost = 50000, -- Day 7 balance: first rebirth after ~10-15 min
	CostGrowth = 3,
	MultiplierPerRebirth = 1,
}

function Config.RebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths)
end

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.MultiplierPerRebirth
end

-- Day 4: weapons. Damage multiplies click power (button and mobs).
-- IDs are saved in player data: never rename them.
Config.Weapons = {
	{ Id = "Stick", Name = "Палка", Damage = 1, Cost = 0, Color = Color3.fromRGB(150, 110, 70) },
	{ Id = "WoodSword", Name = "Деревянный меч", Damage = 3, Cost = 100, Color = Color3.fromRGB(200, 150, 90) },
	{ Id = "IronSword", Name = "Железный меч", Damage = 10, Cost = 1200, Color = Color3.fromRGB(190, 200, 215) },
	{ Id = "AuraKatana", Name = "Катана Ауры", Damage = 35, Cost = 12000, Color = Color3.fromRGB(190, 110, 255) },
}

-- Day 5: backpacks give passive Aura every second (multiplied by the
-- Aura multiplier). Size is the cosmetic box on the player's back.
Config.Backpacks = {
	{ Id = "Pouch", Name = "Мешочек", PerSecond = 2, Cost = 300, Color = Color3.fromRGB(170, 120, 80), Size = Vector3.new(1.2, 1.2, 0.6) },
	{ Id = "Satchel", Name = "Ранец", PerSecond = 10, Cost = 3000, Color = Color3.fromRGB(70, 120, 200), Size = Vector3.new(1.6, 1.8, 0.8) },
	{ Id = "AuraPack", Name = "Ранец Ауры", PerSecond = 50, Cost = 25000, Color = Color3.fromRGB(180, 100, 255), Size = Vector3.new(1.9, 2.2, 1), Neon = true },
}

-- Day 5: pets are bought with Gems and boost all Aura gains:
-- multiplier = 1 + Bonus. One pet can be equipped at a time.
Config.Pets = {
	{ Id = "Spark", Name = "Искорка", Bonus = 0.5, Cost = 10, Color = Color3.fromRGB(255, 220, 90), Size = 1.4 },
	{ Id = "Dragon", Name = "Дракончик Ауры", Bonus = 1.5, Cost = 60, Color = Color3.fromRGB(170, 90, 255), Size = 2, Wings = true },
}

-- Shop categories. Each one says where the list lives, which save
-- fields hold owned/equipped items, the currency and how to describe
-- an item's stat in the UI.
Config.Shop = {
	Weapon = {
		Title = "Оружие",
		Items = Config.Weapons,
		OwnedKey = "OwnedWeapons",
		EquippedKey = "EquippedWeapon",
		Currency = "Aura",
		Describe = function(item)
			return "Урон x" .. item.Damage
		end,
	},
	Backpack = {
		Title = "Ранцы",
		Items = Config.Backpacks,
		OwnedKey = "OwnedBackpacks",
		EquippedKey = "EquippedBackpack",
		Currency = "Aura",
		Describe = function(item)
			return "+" .. item.PerSecond .. " Ауры/сек"
		end,
	},
	Pet = {
		Title = "Питомцы",
		Items = Config.Pets,
		OwnedKey = "OwnedPets",
		EquippedKey = "EquippedPet",
		Currency = "Gems",
		Describe = function(item)
			return "+" .. math.floor(item.Bonus * 100) .. "% ко всей Ауре"
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

return Config
