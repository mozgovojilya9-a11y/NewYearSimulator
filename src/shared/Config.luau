-- Общие настройки игры: зоны, перерождение, этапы и герои.
-- Всё, что хочется "подкрутить" в балансе, меняется здесь.

local Config = {}

Config.TrainCooldown = 0.15 -- минимальная пауза между тренировками (сек)
Config.SaveInterval = 60 -- автосохранение (сек)

-- Зоны тренировок: Requirement = нужная мощность, Multiplier = множитель за клик
Config.Zones = {
	{ Name = "Заснеженная деревня", Requirement = 0, Multiplier = 1 },
	{ Name = "Мастерская Деда Мороза", Requirement = 1000, Multiplier = 5 },
	{ Name = "Ледяной замок", Requirement = 50000, Multiplier = 25 },
	{ Name = "Полярная ночь", Requirement = 1000000, Multiplier = 150 },
}

-- Перерождение: цена = BaseCost * CostGrowth ^ (число перерождений)
Config.Rebirth = {
	BaseCost = 1000,
	CostGrowth = 5,
	BonusPerRebirth = 0.5, -- +50% к мощности за каждое перерождение
}

-- Этапы боёв: нужная мощность = BaseRequirement * Growth ^ (этап - 1)
Config.Stages = {
	BaseRequirement = 100,
	Growth = 1.6,
}

-- Герои. Ability.Boosts = временные бонусы, Ability.Combat = боевой эффект (появится с боями)
Config.Heroes = {
	{
		Id = "snowman", Name = "Снеговик", Rarity = "Обычный", Cost = 0,
		PowerMult = 1, WinMult = 1,
		Ability = { Name = "Ледяной щит", Cooldown = 30, Duration = 5, Combat = true },
	},
	{
		Id = "reindeer", Name = "Северный олень Рудик", Rarity = "Редкий", Cost = 50,
		PowerMult = 1.5, WinMult = 1,
		Ability = { Name = "Рывок", Cooldown = 40, Duration = 10, Boosts = { Power = 2 } },
	},
	{
		Id = "trapkid", Name = "Тимка-Ловушка", Rarity = "Редкий", Cost = 120,
		PowerMult = 1.3, WinMult = 1.2,
		Ability = { Name = "Домашняя оборона", Cooldown = 35, Duration = 3, Combat = true },
	},
	{
		Id = "grum", Name = "Хмурый Грум", Rarity = "Эпический", Cost = 500,
		PowerMult = 2, WinMult = 1.5,
		Ability = { Name = "Украсть праздник", Cooldown = 60, Duration = 15, Boosts = { Wins = 3 } },
	},
	{
		Id = "merlin", Name = "Мерлинчик Снегов", Rarity = "Эпический", Cost = 800,
		PowerMult = 3, WinMult = 1,
		Ability = { Name = "Ледяная вспышка", Cooldown = 40, Duration = 0, Combat = true },
	},
	{
		Id = "santa", Name = "Дед Мороз", Rarity = "Легендарный", Cost = 5000,
		PowerMult = 5, WinMult = 2,
		Ability = { Name = "Новогодние подарки", Cooldown = 90, Duration = 20, Boosts = { Power = 3, Wins = 2 } },
	},
}

Config.HeroById = {}
for _, hero in Config.Heroes do
	Config.HeroById[hero.Id] = hero
end

return Config