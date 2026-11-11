--[[
	ProgressionService.luau
	The "come back every 5 minutes" layer, all server-authoritative:
	- daily reward with a 7-day streak,
	- wheel of fortune (free spin every N hours),
	- 3 daily quests picked from a pool (kills, rooms, trainer clicks,
	  bosses, runs),
	- player level from XP (every 5 levels a small Aura reward),
	- temporary x2 Aura boosts (BoostUntil, counted in AuraMultiplier).

	Client: Progression:InvokeServer("Status") -> table;
	("ClaimDaily") / ("Spin") / ("ClaimQuest", index) -> ok, message, extra.
	The player attribute "RewardReady" drives the "!" badge.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local ProgressionService = {}

local P = Config.Progression

local function dayIndex(): number
	return math.floor(os.time() / 86400)
end

local function auraScale(data): number
	return 1 + data.RoomReached / 2
end

---------------------------------------------------------------------
-- Boosts
---------------------------------------------------------------------

local function giveBoost(player, data, minutes: number)
	local now = os.time()
	local base = math.max(now, data.BoostUntil or 0)
	data.BoostUntil = base + minutes * 60
	PlayerState.Sync(player)
end

---------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------

local function ensureQuests(data)
	local today = dayIndex()
	if data.Quests.Day == today and #data.Quests.List > 0 then
		return
	end
	local pool = table.clone(P.Quests.Pool)
	local rng = Random.new(today * 7919 + 17)
	local list = {}
	for _ = 1, math.min(P.Quests.PerDay, #pool) do
		local pick = rng:NextInteger(1, #pool)
		local def = table.remove(pool, pick)
		table.insert(list, { Id = def.Id, Progress = 0, Claimed = false })
	end
	data.Quests = { Day = today, List = list }
end

local function questDef(id: string)
	for _, def in ipairs(P.Quests.Pool) do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function questProgress(player, kind: string, amount: number, absolute: boolean?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	ensureQuests(data)
	local changed = false
	for _, quest in ipairs(data.Quests.List) do
		local def = questDef(quest.Id)
		if def and def.Kind == kind and not quest.Claimed and quest.Progress < def.Target then
			local before = quest.Progress
			quest.Progress = if absolute then math.max(quest.Progress, amount) else quest.Progress + amount
			quest.Progress = math.min(quest.Progress, def.Target)
			if quest.Progress ~= before then
				changed = true
				if quest.Progress >= def.Target then
					Remotes.Notify(player, "✅ Задание выполнено: " .. def.Text, "gold")
				end
			end
		end
	end
	if changed then
		ProgressionService.RefreshReady(player)
	end
end

---------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------

local function xpToNext(level: number): number
	return math.floor(P.Level.XpBase * level ^ 1.5)
end

local function addXp(player, data, amount: number)
	data.Xp += amount
	local leveled = false
	while data.Xp >= xpToNext(data.Level) do
		data.Xp -= xpToNext(data.Level)
		data.Level += 1
		leveled = true
		if data.Level % P.Level.RewardEvery == 0 then
			local reward = P.Level.RewardAura * data.Level
			PlayerState.GiveAura(player, reward)
			Remotes.Notify(player, ("🎉 Уровень %d! Награда: +%s Ауры"):format(data.Level, Format.Number(reward)), "gold")
		else
			Remotes.Notify(player, ("⬆ Уровень %d!"):format(data.Level), "good")
		end
	end
	if leveled then
		PlayerState.Sync(player)
	else
		player:SetAttribute("Xp", data.Xp)
	end
end

---------------------------------------------------------------------
-- Status / claims
---------------------------------------------------------------------

local function dailyState(data)
	local now = os.time()
	local since = now - (data.Daily.LastClaim or 0)
	local canClaim = since >= P.Daily.CooldownHours * 3600
	local streak = data.Daily.Streak or 0
	if since > P.Daily.StreakWindowHours * 3600 then
		streak = 0 -- missed a day: next claim is day 1
	end
	local nextDay = streak % 7 + 1
	return canClaim, nextDay, math.max(0, P.Daily.CooldownHours * 3600 - since), streak
end

local function wheelState(data)
	local since = os.time() - (data.WheelLast or 0)
	return since >= P.Wheel.CooldownHours * 3600, math.max(0, P.Wheel.CooldownHours * 3600 - since)
end

function ProgressionService.RefreshReady(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	ensureQuests(data)
	local ready = dailyState(data) or wheelState(data)
	if not ready then
		for _, quest in ipairs(data.Quests.List) do
			local def = questDef(quest.Id)
			if def and not quest.Claimed and quest.Progress >= def.Target then
				ready = true
				break
			end
		end
	end
	player:SetAttribute("RewardReady", ready == true)
end

local function status(player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	ensureQuests(data)
	local canDaily, nextDay, dailyWait, streak = dailyState(data)
	local canSpin, spinWait = wheelState(data)
	local quests = {}
	for i, quest in ipairs(data.Quests.List) do
		local def = questDef(quest.Id)
		if def then
			quests[i] = { Text = def.Text, Target = def.Target, Progress = quest.Progress, Claimed = quest.Claimed, Aura = math.floor(def.Aura * auraScale(data)) }
		end
	end
	local dailyAura = {}
	for day, amount in ipairs(P.Daily.Aura) do
		dailyAura[day] = math.floor(amount * auraScale(data))
	end
	return {
		Daily = { CanClaim = canDaily, NextDay = nextDay, Wait = dailyWait, Streak = streak, Aura = dailyAura },
		Wheel = { CanSpin = canSpin, Wait = spinWait },
		Quests = quests,
		Level = data.Level,
		Xp = data.Xp,
		XpNext = xpToNext(data.Level),
		BoostUntil = data.BoostUntil,
	}
end

local function claimDaily(player)
	local data = DataService.Get(player)
	if not data then
		return false, "Данные ещё загружаются"
	end
	local canClaim, nextDay, wait, streak = dailyState(data)
	if not canClaim then
		return false, ("Следующая награда через %d ч %d мин"):format(wait // 3600, (wait % 3600) // 60)
	end
	local amount = math.floor(P.Daily.Aura[nextDay] * auraScale(data))
	PlayerState.GiveAura(player, amount)
	data.Daily.LastClaim = os.time()
	data.Daily.Streak = streak + 1
	local message = ("День %d: +%s Ауры"):format(nextDay, Format.Number(amount))
	if nextDay == 7 and P.Daily.Day7Boost then
		giveBoost(player, data, 30)
		message ..= " и x2 Аура на 30 мин!"
	end
	ProgressionService.RefreshReady(player)
	return true, message, nextDay
end

local function spin(player)
	local data = DataService.Get(player)
	if not data then
		return false, "Данные ещё загружаются"
	end
	local canSpin, wait = wheelState(data)
	if not canSpin then
		return false, ("Следующее вращение через %d ч %d мин"):format(wait // 3600, (wait % 3600) // 60)
	end
	local total = 0
	for _, prize in ipairs(P.Wheel.Prizes) do
		total += prize.Weight
	end
	local roll = math.random() * total
	local index = #P.Wheel.Prizes
	for i, prize in ipairs(P.Wheel.Prizes) do
		roll -= prize.Weight
		if roll <= 0 then
			index = i
			break
		end
	end
	local prize = P.Wheel.Prizes[index]
	data.WheelLast = os.time()
	local message
	if prize.Kind == "Aura" then
		local amount = math.floor(prize.Amount * auraScale(data))
		PlayerState.GiveAura(player, amount)
		message = "+" .. Format.Number(amount) .. " Ауры"
	elseif prize.Kind == "Boost" then
		giveBoost(player, data, prize.Minutes)
		message = ("x2 Аура на %d мин"):format(prize.Minutes)
	else -- Egg: a random pet you don't own, or Aura if you own them all
		local candidates = {}
		for _, pet in ipairs(Config.Pets) do
			if not data.OwnedPets[pet.Id] then
				table.insert(candidates, pet)
			end
		end
		if #candidates > 0 then
			local pet = candidates[math.random(#candidates)]
			PlayerState.GrantPet(player, pet.Id)
			message = "Питомец: " .. pet.Name .. "!"
		else
			local amount = math.floor(1000 * auraScale(data))
			PlayerState.GiveAura(player, amount)
			message = "Все питомцы уже есть: +" .. Format.Number(amount) .. " Ауры"
		end
	end
	ProgressionService.RefreshReady(player)
	return true, message, index
end

local function claimQuest(player, index)
	local data = DataService.Get(player)
	if not data or type(index) ~= "number" then
		return false, "Неверный запрос"
	end
	ensureQuests(data)
	local quest = data.Quests.List[index]
	local def = quest and questDef(quest.Id)
	if not def then
		return false, "Нет такого задания"
	end
	if quest.Claimed then
		return false, "Уже получено"
	end
	if quest.Progress < def.Target then
		return false, "Задание ещё не выполнено"
	end
	quest.Claimed = true
	local amount = math.floor(def.Aura * auraScale(data))
	PlayerState.GiveAura(player, amount)
	ProgressionService.RefreshReady(player)
	return true, "+" .. Format.Number(amount) .. " Ауры"
end

---------------------------------------------------------------------
-- Hooks from gameplay
---------------------------------------------------------------------

function ProgressionService.OnKill(player, room: number, isBoss: boolean)
	local data = DataService.Get(player)
	if not data then
		return
	end
	questProgress(player, "Kill", 1)
	if isBoss then
		questProgress(player, "Boss", 1)
	end
	addXp(player, data, (if isBoss then P.Level.XpPerBoss else P.Level.XpPerKill) * room)
end

function ProgressionService.OnRoomCleared(player, room: number)
	questProgress(player, "Room", room, true)
	local data = DataService.Get(player)
	if data and room >= Config.RebirthRequirement and room == Config.RebirthRequirement then
		Remotes.Notify(player, "🔁 Можно переродиться! Иди к алтарю", "gold")
	end
end

function ProgressionService.OnRunStarted(player)
	questProgress(player, "Run", 1)
end

function ProgressionService.OnTrainerClick(player)
	questProgress(player, "Train", 1)
end

function ProgressionService.Init()
	local allow = RateLimit.new(0.3)
	Remotes.Get("Progression").OnServerInvoke = function(player, action, arg)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Status" then
			return true, status(player)
		elseif action == "ClaimDaily" then
			return claimDaily(player)
		elseif action == "Spin" then
			return spin(player)
		elseif action == "ClaimQuest" then
			return claimQuest(player, arg)
		end
		return false, "Неверный запрос"
	end

	DungeonRuns.OnKill = ProgressionService.OnKill
	DungeonRuns.OnRoomCleared = ProgressionService.OnRoomCleared
	DungeonRuns.OnRunStarted = ProgressionService.OnRunStarted

	-- Badge refresh: on join (after data loads) and once a minute (timers).
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerState.IsReady(player) then
					ProgressionService.RefreshReady(player)
				end
			end
		end
	end)
end

return ProgressionService
