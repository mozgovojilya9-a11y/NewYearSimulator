-- Общие настройки игры: зоны, перерождение, этапы и оригинальные наставники.
local Config = {}
Config.TrainCooldown = 0.15
Config.SaveInterval = 60

Config.Zones = {
 {Name="Снежный двор",Requirement=0,Multiplier=1},
 {Name="Зал северного сияния",Requirement=1000,Multiplier=5},
 {Name="Башня древних рун",Requirement=50000,Multiplier=25},
 {Name="Полярное святилище",Requirement=1000000,Multiplier=150},
}
Config.Rebirth = {BaseCost=1000,CostGrowth=5,BonusPerRebirth=0.5}
Config.Stages = {BaseRequirement=100,Growth=1.6}
Config.Heroes = {
 {Id="snowman",Name="Снежок Хранитель",Rarity="Ученик",Cost=0,PowerMult=1,WinMult=1,Ability={Name="Ледяной барьер",Cooldown=30,Duration=5,Combat=true}},
 {Id="reindeer",Name="Арон Вейл",Rarity="Искатель",Cost=50,PowerMult=1.5,WinMult=1,Ability={Name="Искра скорости",Cooldown=40,Duration=10,Boosts={Power=2}}},
 {Id="trapkid",Name="Герман Рид",Rarity="Искатель",Cost=120,PowerMult=1.3,WinMult=1.2,Ability={Name="Рунная защита",Cooldown=35,Duration=3,Combat=true}},
 {Id="grum",Name="Луна Грей",Rarity="Магистр",Cost=500,PowerMult=2,WinMult=1.5,Ability={Name="Сияние победы",Cooldown=60,Duration=15,Boosts={Wins=3}}},
 {Id="merlin",Name="Северус Кроу",Rarity="Магистр",Cost=800,PowerMult=3,WinMult=1,Ability={Name="Звёздный импульс",Cooldown=40,Duration=0,Combat=true}},
 {Id="santa",Name="Альбус Рейн",Rarity="Легендарный",Cost=5000,PowerMult=5,WinMult=2,Ability={Name="Дар полярной звезды",Cooldown=90,Duration=20,Boosts={Power=3,Wins=2}}},
}
Config.HeroById={}
for _,hero in Config.Heroes do Config.HeroById[hero.Id]=hero end
return Config
