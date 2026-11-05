-- Главный серверный скрипт: тренировка, бои, перерождение, герои и способности.
-- Вся логика и проверки на сервере, клиент только отправляет запросы.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(ServerScriptService.DataService)

DataService.Start()

-- RemoteEvent'ы
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
local R = {}
for _, name in { "RequestState", "Train", "Fight", "Rebirth", "BuyHero", "EquipHero", "UseAbility", "State", "Notice" } do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	R[name] = remote
end
Remotes.Parent = ReplicatedStorage

-- Временные данные (не сохраняются)
local lastTrain = {}
local abilityReadyAt = {}
local buffs = {} -- [player] = { Power = {Mult, Expires}, Wins = {Mult, Expires} }

local function getBuff(player, stat)
	local buff = buffs[player] and buffs[player][stat]
	if buff and os.clock() < buff.Expires then
		return buff.Mult
	end
	return 1
end

local function equippedHero(data)
	return Config.HeroById[data.EquippedHero]
end

local function stageRequirement(stage)
	return math.floor(Config.Stages.BaseRequirement * Config.Stages.Growth ^ (stage - 1))
end

local function rebirthCost(rebirths)
	return Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths
end

local function rebirthMult(data)
	return 1 + data.Rebirths * Config.Rebirth.BonusPerRebirth
end

local function notice(player, text)
	R.Notice:FireClient(player, text)
end

local function pushState(player)
	local data = DataService.Get(player)
	if not data then
		return
	end

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Power.Value = math.floor(data.Power)
		stats.Wins.Value = data.Wins
		stats.Rebirths.Value = data.Rebirths
	end

	R.State:FireClient(player, {
		Power = data.Power,
		Wins = data.Wins,
		Rebirths = data.Rebirths,
		Stage = data.Stage,
		Zone = data.Zone,
		Owned = data.OwnedHeroes,
		Equipped = data.EquippedHero,
		StageRequirement = stageRequirement(data.Stage),
		RebirthCost = rebirthCost(data.Rebirths),
	})
end

-- Обёртка: обработчик вызывается только если данные игрока загружены
local function withData(handler)
	return function(player, ...)
		local data = DataService.Get(player)
		if data then
			handler(player, data, ...)
		end
	end
end

R.RequestState.OnServerEvent:Connect(pushState)

R.Train.OnServerEvent:Connect(withData(function(player, data, zoneIndex)
	if type(zoneIndex) ~= "number" then
		return
	end
	local zone = Config.Zones[math.floor(zoneIndex)]
	if not zone then
		return
	end
	if data.Power < zone.Requirement then
		return notice(player, "Зона закрыта: нужно больше мощности")
	end

	local t = os.clock()
	if t - (lastTrain[player] or 0) < Config.TrainCooldown then
		return
	end
	lastTrain[player] = t

	data.Zone = math.floor(zoneIndex)
	data.Power += zone.Multiplier * rebirthMult(data) * equippedHero(data).PowerMult * getBuff(player, "Power")
	pushState(player)
end))

-- Пока бой = проверка мощности. Настоящие бои с врагами добавим следующим шагом.
R.Fight.OnServerEvent:Connect(withData(function(player, data)
	local required = stageRequirement(data.Stage)
	if data.Power < required then
		return notice(player, ("Для этапа %d нужна мощность %d"):format(data.Stage, required))
	end

	local reward = math.floor(data.Stage * equippedHero(data).WinMult * getBuff(player, "Wins"))
	data.Wins += reward
	data.Stage += 1
	notice(player, ("Победа! +%d побед"):format(reward))
	pushState(player)
end))

R.Rebirth.OnServerEvent:Connect(withData(function(player, data)
	if data.Power < rebirthCost(data.Rebirths) then
		return notice(player, "Не хватает мощности для перерождения")
	end
	data.Power = 0
	data.Stage = 1
	data.Zone = 1
	data.Rebirths += 1
	notice(player, "Перерождение! Бонус к мощности увеличен")
	pushState(player)
end))

R.BuyHero.OnServerEvent:Connect(withData(function(player, data, heroId)
	local hero = type(heroId) == "string" and Config.HeroById[heroId]
	if not hero or data.OwnedHeroes[heroId] then
		return
	end
	if data.Wins < hero.Cost then
		return notice(player, "Не хватает побед")
	end
	data.Wins -= hero.Cost
	data.OwnedHeroes[heroId] = true
	data.EquippedHero = heroId
	notice(player, hero.Name .. " куплен и надет!")
	pushState(player)
end))

R.EquipHero.OnServerEvent:Connect(withData(function(player, data, heroId)
	if type(heroId) ~= "string" or not data.OwnedHeroes[heroId] or not Config.HeroById[heroId] then
		return
	end
	data.EquippedHero = heroId
	pushState(player)
end))

R.UseAbility.OnServerEvent:Connect(withData(function(player, data)
	local ability = equippedHero(data).Ability
	local t = os.clock()
	if t < (abilityReadyAt[player] or 0) then
		return notice(player, "Способность перезаряжается")
	end
	abilityReadyAt[player] = t + ability.Cooldown

	if ability.Combat then
		return notice(player, ability.Name .. "! (боевой эффект появится вместе с боями)")
	end

	buffs[player] = buffs[player] or {}
	for stat, mult in ability.Boosts do
		buffs[player][stat] = { Mult = mult, Expires = t + ability.Duration }
	end
	notice(player, ("%s! Бонус на %d сек"):format(ability.Name, ability.Duration))
end))

local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Power", "Wins", "Rebirths" } do
		local value = Instance.new("NumberValue")
		value.Name = name
		value.Parent = stats
	end
	stats.Parent = player

	if DataService.Load(player) then
		pushState(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	DataService.Release(player)
	lastTrain[player] = nil
	abilityReadyAt[player] = nil
	buffs[player] = nil
end)