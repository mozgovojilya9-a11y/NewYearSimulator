-- Shared balance and content definitions for the Winter Academy vertical slice.
-- Existing IDs are preserved so previously saved player data remains compatible.

local Config = {}

Config.TrainCooldown = 0.45
Config.SaveInterval = 60

Config.Zones = {
    { Id = "courtyard", Name = "Снежный двор", Requirement = 0, Multiplier = 1 },
    { Id = "aurora", Name = "Зал северного сияния", Requirement = 1000, Multiplier = 5 },
    { Id = "runes", Name = "Башня древних рун", Requirement = 50000, Multiplier = 25 },
    { Id = "sanctum", Name = "Полярное святилище", Requirement = 1000000, Multiplier = 150 },
}

Config.Rebirth = {
    BaseCost = 1000,
    CostGrowth = 5,
    BonusPerRebirth = 0.5,
}

Config.Stages = {
    BaseRequirement = 100,
    Growth = 1.6,
}

Config.Combat = {
    AttackCooldown = 0.9,
    EnemyAttackInterval = 2.6,
    MinimumDamage = 8,
    BaseDamage = 12,
    PowerDamageScale = 0.16,
    MonsterHealthGrowth = 1.28,
    MonsterDamageGrowth = 1.18,
    PlayerDamage = 8,
    RewardWinsGrowth = 1.25,
}

-- IDs are intentionally stable. Do not rename these IDs without a DataStore migration.
Config.Heroes = {
    {
        Id = "snowman", Name = "Снежок Хранитель", Rarity = "Ученик", Cost = 0,
        PowerMult = 1, WinMult = 1,
        Ability = { Name = "Ледяной барьер", Cooldown = 30, Duration = 5, Boosts = { Power = 1.5 } },
        Color = Color3.fromRGB(173, 224, 255),
    },
    {
        Id = "reindeer", Name = "Терен Вейл", Rarity = "Искатель", Cost = 50,
        PowerMult = 1.6, WinMult = 1.1,
        Ability = { Name = "Искра скорости", Cooldown = 40, Duration = 10, Boosts = { Power = 2 } },
        Color = Color3.fromRGB(139, 177, 255),
    },
    {
        Id = "trapkid", Name = "Кайрен Рид", Rarity = "Искатель", Cost = 120,
        PowerMult = 2.2, WinMult = 1.25,
        Ability = { Name = "Рунная защита", Cooldown = 35, Duration = 8, Boosts = { Power = 1.8 } },
        Color = Color3.fromRGB(255, 153, 122),
    },
    {
        Id = "grum", Name = "Лиора Грей", Rarity = "Магистр", Cost = 500,
        PowerMult = 3.4, WinMult = 1.5,
        Ability = { Name = "Сияние победы", Cooldown = 60, Duration = 15, Boosts = { Wins = 3 } },
        Color = Color3.fromRGB(174, 135, 255),
    },
    {
        Id = "merlin", Name = "Эдрик Нокс", Rarity = "Магистр", Cost = 800,
        PowerMult = 5, WinMult = 1.8,
        Ability = { Name = "Звёздный импульс", Cooldown = 40, Duration = 12, Boosts = { Power = 2.5 } },
        Color = Color3.fromRGB(125, 245, 226),
    },
    {
        Id = "santa", Name = "Ориан Вельт", Rarity = "Легендарный", Cost = 5000,
        PowerMult = 7.5, WinMult = 2.5,
        Ability = { Name = "Дар полярной звезды", Cooldown = 90, Duration = 20, Boosts = { Power = 3, Wins = 2 } },
        Color = Color3.fromRGB(255, 211, 112),
    },
    {
        Id = "malrik", Name = "Малрик Соль", Rarity = "Мифический", Cost = 16000,
        PowerMult = 11, WinMult = 3.5,
        Ability = { Name = "Разлом сумерек", Cooldown = 110, Duration = 18, Boosts = { Power = 4, Wins = 2.5 } },
        Color = Color3.fromRGB(255, 105, 153),
    },
}

Config.HeroById = {}
for _, hero in ipairs(Config.Heroes) do
    Config.HeroById[hero.Id] = hero
end

Config.Monsters = {
    { Id = "snow_goblin", Name = "Снежный гоблин", Rarity = "Обычный", Health = 90, Damage = 5, Reward = 8, Color = Color3.fromRGB(112, 210, 232) },
    { Id = "frost_sentinel", Name = "Ледяной страж", Rarity = "Необычный", Health = 155, Damage = 8, Reward = 15, Color = Color3.fromRGB(110, 173, 255) },
    { Id = "shadow_hunter", Name = "Теневой охотник", Rarity = "Редкий", Health = 260, Damage = 12, Reward = 28, Color = Color3.fromRGB(166, 112, 232) },
    { Id = "rune_keeper", Name = "Хранитель рун", Rarity = "Эпический", Health = 430, Damage = 18, Reward = 52, Color = Color3.fromRGB(255, 176, 103) },
    { Id = "polar_beast", Name = "Полярный зверь", Rarity = "Легендарный", Health = 720, Damage = 25, Reward = 95, Color = Color3.fromRGB(255, 112, 142) },
}

Config.Items = {
    ice_shard = { Name = "Осколок инея", Rarity = "Обычный", Value = 12, Description = "Холодный кристалл для первых рецептов.", Color = Color3.fromRGB(135, 220, 255) },
    rune_dust = { Name = "Рунная пыль", Rarity = "Необычный", Value = 28, Description = "Светящаяся пыль со старых печатей.", Color = Color3.fromRGB(187, 145, 255) },
    frost_core = { Name = "Ядро стража", Rarity = "Редкий", Value = 75, Description = "Сердце ледяного защитника.", Color = Color3.fromRGB(105, 185, 255) },
    shadow_essence = { Name = "Сумрачная эссенция", Rarity = "Эпический", Value = 180, Description = "Редкая эссенция теневого существа.", Color = Color3.fromRGB(210, 115, 255) },
    aurora_fragment = { Name = "Фрагмент авроры", Rarity = "Легендарный", Value = 420, Description = "Осколок северного сияния.", Color = Color3.fromRGB(255, 199, 105) },
}

Config.DropPools = {
    { Id = "ice_shard", Weight = 70, MinStage = 1 },
    { Id = "rune_dust", Weight = 25, MinStage = 1 },
    { Id = "frost_core", Weight = 18, MinStage = 3 },
    { Id = "shadow_essence", Weight = 10, MinStage = 6 },
    { Id = "aurora_fragment", Weight = 4, MinStage = 10 },
}

Config.RarityColors = {
    ["Обычный"] = Color3.fromRGB(180, 190, 208),
    ["Необычный"] = Color3.fromRGB(104, 211, 155),
    ["Редкий"] = Color3.fromRGB(91, 168, 255),
    ["Эпический"] = Color3.fromRGB(184, 113, 255),
    ["Легендарный"] = Color3.fromRGB(255, 190, 87),
    ["Мифический"] = Color3.fromRGB(255, 100, 155),
    ["Ученик"] = Color3.fromRGB(180, 220, 245),
    ["Искатель"] = Color3.fromRGB(104, 211, 155),
    ["Магистр"] = Color3.fromRGB(184, 113, 255),
}

return Config
