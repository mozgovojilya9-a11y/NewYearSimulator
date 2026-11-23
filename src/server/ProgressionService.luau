--[[
	ProgressionService.luau
	The "come back every 5 minutes" layer, all server-authoritative:
	- daily reward with a 7-day streak,
	- wheel of fortune (free spin every N hours),
	- 3 daily quests picked from a pool (kills, rooms, trainer clicks,
	  bosses, runs),
	- player level from XP (every 5 levels a credits reward),
	- Нано-кредиты for every kill (Config.KillCredits).
	Rewards are credits / XP / boosts.
	- temporary x2 XP boosts (Boosts.Xp).

	Client: Progression:InvokeServer("Status") -> table;
	("ClaimDaily") / ("Spin") / ("ClaimQuest", index) -> ok, message, extra.
	The player attribute "RewardReady" drives the "!" badge.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local DungeonRuns = require(script.Parent.DungeonRuns)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local StatService = require(script.Parent.StatService)
local StreakService = require(script.Parent.StreakService)
local Remotes = require(script.Parent.Remotes)

local ProgressionService = {}

local P = Config.Progression

local function dayIndex(): number
	return math.floor(os.time() / 86400)
end

-- Earned credits: x CreditsMult (passes x2 Credits, VIP, x2 boost).
local function earnCredits(player, amount: number): number
	return PlayerState.AddCredits(player, amount * StatService.Get(player).CreditsMult)
end

-- Credits rewards grow with the record room so they stay relevant.
local function creditScale(data): number
	return 1 + data.RoomReached / 4
end

---------------------------------------------------------------------
-- Boosts
---------------------------------------------------------------------

local function giveBoost(player, _data, minutes: number)
	PlayerState.AddBoost(player, "Xp", minutes)
end

---------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------

-- Two quest sets with the same rules: Daily (data.Quests, new every
-- day) and Weekly (data.Weekly, new every week). Rewards: credits (x the
-- record room), XP and Кристаллы.
local SETS = {
	Daily = { Config = P.Quests, Field = "Quests", Key = "Day", Count = P.Quests.PerDay, Period = 86400, Salt = 17 },
	Weekly = { Config = P.Weekly, Field = "Weekly", Key = "Week", Count = P.Weekly.PerWeek, Period = 86400 * 7, Salt = 31 },
}

local function ensureSet(data, set)
	local index = math.floor(os.time() / set.Period)
	local bucket = data[set.Field]
	if type(bucket) == "table" and bucket[set.Key] == index and type(bucket.List) == "table" and #bucket.List > 0 then
		return bucket
	end
	local pool = table.clone(set.Config.Pool)
	local rng = Random.new(index * 7919 + set.Salt)
	local list = {}
	for _ = 1, math.min(set.Count, #pool) do
		local def = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { Id = def.Id, Progress = 0, Claimed = false })
	end
	bucket = { [set.Key] = index, List = list }
	data[set.Field] = bucket
	return bucket
end

local function ensureQuests(data)
	ensureSet(data, SETS.Daily)
	ensureSet(data, SETS.Weekly)
end

local function defIn(set, id: string)
	for _, def in ipairs(set.Config.Pool) do
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
	for _, set in pairs(SETS) do
		for _, quest in ipairs(data[set.Field].List) do
			local def = defIn(set, quest.Id)
			if def and def.Kind == kind and not quest.Claimed and quest.Progress < def.Target then
				local before = quest.Progress
				quest.Progress = if absolute then math.max(quest.Progress, amount) else quest.Progress + amount
				quest.Progress = math.min(quest.Progress, def.Target)
				if quest.Progress ~= before then
					changed = true
					if quest.Progress >= def.Target then
						Remotes.Notify(player, "Задание выполнено: " .. def.Text, "gold")
					end
				end
			end
		end
	end
	if changed then
		ProgressionService.RefreshReady(player)
	end
end
ProgressionService.QuestProgress = questProgress

---------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------

local xpToNext = Config.XpToNext

-- Adds XP; on level up: skill points, rewards, stats refresh (damage
-- and max HP grow with the level), full heal, big banner on the client.
local function addXp(player, data, amount: number, raw: boolean?)
	if not raw then
		amount *= StatService.Get(player).XpMult -- passes, VIP, x2 boost
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	local maxLevel = P.Level.MaxLevel
	if data.Level >= maxLevel then
		-- max level: XP fills Возвышение points (Config.Ascension)
		local A = data.Ascension
		local AS = Config.Ascension
		if (A.Points or 0) >= AS.MaxPoints then
			return
		end
		A.Xp = (A.Xp or 0) + amount
		local cost = Config.AscensionXp()
		local got = 0
		while A.Xp >= cost and A.Points < AS.MaxPoints do
			A.Xp -= cost
			A.Points += 1
			got += 1
		end
		if got > 0 then
			Remotes.Notify(player, AS.Texts.Got, "gold")
			PlayerState.Sync(player)
		else
			player:SetAttribute("Xp", math.floor(A.Xp))
		end
		return
	end
	data.Xp += amount
	local gained = 0
	while data.Level < maxLevel and data.Xp >= xpToNext(data.Level) do
		data.Xp -= xpToNext(data.Level)
		data.Level += 1
		gained += 1
		data.SkillPoints = (data.SkillPoints or 0) + P.Level.SkillPointsPerLevel
		if data.Level % P.Level.RewardEvery == 0 then
			local reward = earnCredits(player, P.Level.RewardCredits * data.Level)
			Remotes.Notify(player, ("Награда за уровень %d: +%s нано-кредитов"):format(data.Level, Format.Number(reward)), "gold")
		end
	end
	if gained > 0 then
		PlayerState.Sync(player) -- recomputes stats: damage, max HP
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			task.defer(function()
				humanoid.Health = humanoid.MaxHealth -- a level up heals
			end)
		end
		Remotes.Get("LevelUp"):FireClient(player, data.Level, gained * P.Level.SkillPointsPerLevel, data.Level - gained)
		-- everyone sees the light on the character (client LevelUp.luau)
		local character = player.Character
		if character then
			character:SetAttribute("LevelUpFx", (character:GetAttribute("LevelUpFx") or 0) + 1)
		end
		GameEvents.Fire(player, "Level", data.Level)
	else
		player:SetAttribute("Xp", data.Xp)
	end
end

function ProgressionService.AddXp(player, amount: number)
	local data = DataService.Get(player)
	if data then
		addXp(player, data, amount)
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
		for _, set in pairs(SETS) do
			for _, quest in ipairs(data[set.Field].List) do
				local def = defIn(set, quest.Id)
				if def and not quest.Claimed and quest.Progress >= def.Target then
					ready = true
				end
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
	local function listOf(set)
		local list = {}
		for i, quest in ipairs(data[set.Field].List) do
			local def = defIn(set, quest.Id)
			if def then
				list[i] = { Text = def.Text, Target = def.Target, Progress = quest.Progress, Claimed = quest.Claimed, Credits = math.floor(def.Credits * creditScale(data)), Crystals = def.Crystals or 0, Xp = math.floor(Config.KillXp(data.Level) * P.Level.QuestKills * (def.XpMult or 1)) }
			end
		end
		return list
	end
	local quests = listOf(SETS.Daily)
	local weekly = listOf(SETS.Weekly)
	local weekLeft = SETS.Weekly.Period - (os.time() % SETS.Weekly.Period)
	local dayLeft = SETS.Daily.Period - (os.time() % SETS.Daily.Period)
	local dailyCredits = {}
	for day, amount in ipairs(P.Daily.Credits) do
		dailyCredits[day] = math.floor(amount * creditScale(data))
	end
	return {
		Daily = { CanClaim = canDaily, NextDay = nextDay, Wait = dailyWait, Streak = streak, Credits = dailyCredits },
		Wheel = { CanSpin = canSpin, Wait = spinWait },
		Quests = quests,
		Weekly = weekly,
		DayLeft = dayLeft,
		WeekLeft = weekLeft,
		DailyCrystals = P.Daily.Crystals,
		Level = data.Level,
		Xp = data.Xp,
		XpNext = xpToNext(data.Level),
		BoostXp = data.Boosts.Xp,
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
	local amount = earnCredits(player, P.Daily.Credits[nextDay] * creditScale(data))
	data.Daily.LastClaim = os.time()
	data.Daily.Streak = streak + 1
	local message = ("День %d: +%s нано-кредитов"):format(nextDay, Format.Number(amount))
	local crystals = (P.Daily.Crystals or {})[nextDay] or 0
	if crystals > 0 then
		PlayerState.AddCrystals(player, crystals)
		message ..= (", +%d Кристаллов"):format(crystals)
	end
	if nextDay == 7 and P.Daily.Day7Boost then
		giveBoost(player, data, 30)
		message ..= " и x2 Опыт на 30 мин!"
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
	if prize.Kind == "Credits" then
		local amount = earnCredits(player, prize.Amount * creditScale(data))
		message = "+" .. Format.Number(amount) .. " нано-кредитов"
	else -- Boost
		giveBoost(player, data, prize.Minutes)
		message = ("x2 Опыт на %d мин"):format(prize.Minutes)
	end
	ProgressionService.RefreshReady(player)
	return true, message, index
end

local function claimQuest(player, index, setName)
	local data = DataService.Get(player)
	local set = SETS[setName or "Daily"]
	if not data or type(index) ~= "number" or not set then
		return false, "Неверный запрос"
	end
	ensureQuests(data)
	local quest = data[set.Field].List[index]
	local def = quest and defIn(set, quest.Id)
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
	local amount = earnCredits(player, def.Credits * creditScale(data))
	local xp = Config.KillXp(data.Level) * P.Level.QuestKills * (def.XpMult or 1)
	addXp(player, data, xp)
	local crystals = PlayerState.AddCrystals(player, def.Crystals or 0)
	ProgressionService.RefreshReady(player)
	GameEvents.Fire(player, "Quest", 1)
	local text = ("+%s нано-кредитов, +%s XP"):format(Format.Number(amount), Format.Number(xp))
	if crystals > 0 then
		text ..= (", +%d Кристаллов"):format(crystals)
	end
	return true, text
end

---------------------------------------------------------------------
-- Statistics (data.Stats, the Статистика window): counters
---------------------------------------------------------------------

function ProgressionService.Count(player, key: string, amount: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Stats = if type(data.Stats) == "table" then data.Stats else {}
	data.Stats[key] = (tonumber(data.Stats[key]) or 0) + amount
end

-- Everything about the character for the Статистика window.
function ProgressionService.Summary(player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local st = StatService.Get(player)
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local gates = {}
	local cleared = (type(data.Gates) == "table" and type(data.Gates.Cleared) == "table") and data.Gates.Cleared or {}
	local best = (type(data.Gates) == "table" and type(data.Gates.BestTime) == "table") and data.Gates.BestTime or {}
	for _, location in ipairs(Config.Gates.Locations) do
		if location.Ready then
			table.insert(gates, { Name = location.Name, Rank = location.Rank, Grade = cleared[location.Id], Seconds = best[location.Id] })
		end
	end
	local attrs = type(data.Attributes) == "table" and data.Attributes or {}
	return {
		Level = data.Level,
		Xp = data.Xp,
		XpNext = xpToNext(data.Level),
		Class = data.Class or "",
		Title = Config.RankFor(data.Level).Name,
		Damage = st.Damage,
		MaxHealth = st.MaxHealth,
		Defense = st.Defense,
		CritChance = st.CritChance,
		CritDamage = st.CritDamage,
		AttackSpeed = st.AttackSpeed,
		Luck = st.Luck,
		Regen = st.Regen,
		GearScore = st.GearScore,
		Attributes = { Str = attrs.Str or 0, Agi = attrs.Agi or 0, Vit = attrs.Vit or 0, Per = attrs.Per or 0 },
		Kills = stats.Kills or 0,
		Bosses = stats.Bosses or 0,
		Runs = stats.Runs or 0,
		Deaths = stats.Deaths or 0,
		Pulls = stats.Pulls or 0,
		PlaySeconds = stats.PlaySeconds or 0,
		Credits = data.Credits or 0,
		Cores = data.Cores or 0,
		Crystals = (data.Crystals or 0) + (data.CrystalsPaid or 0),
		Gates = gates,
		Achievements = if type(data.Achievements) == "table" then data.Achievements else {},
	}
end

---------------------------------------------------------------------
-- Hooks from gameplay
---------------------------------------------------------------------

-- info (gate runs): Weight = share of a kill's reward (waves have many
-- enemies: swarm counts less, elites more).
function ProgressionService.OnKill(player, room: number, isBoss: boolean, position: Vector3?, _kind, info)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local weight = if isBoss then 1 else (info and info.Weight or 1)
	StreakService.Kill(player, info and info.Enemy, room, position, info and info.Rank) -- Охотничий азарт
	local credits = earnCredits(player, Config.KillCredits(room, isBoss) * weight * StreakService.Mult(player, "Credits"))
	if credits > 0 then
		Remotes.Get("ClickHit"):FireClient(player, "Credits", credits, position)
	end
	questProgress(player, "Kill", 1)
	GameEvents.Fire(player, "Kill", 1)
	ProgressionService.Count(player, "Kills", 1)
	if isBoss then
		ProgressionService.Count(player, "Bosses", 1)
		questProgress(player, "Boss", 1)
		GameEvents.Fire(player, "Boss", 1)
	end
	-- XP by the player's level (Config.KillXp keeps the 160-level pace);
	-- a location far below the player gives less
	local xp = Config.KillXp(data.Level) * (if isBoss then P.Level.BossKills else weight)
	local locLevel = info and info.Level
	if locLevel then
		local gap = data.Level - locLevel - P.Level.EasyGap
		if gap > 0 then
			xp *= math.max(P.Level.EasyMin, 1 - gap * P.Level.EasyDrop)
		end
	end
	local _ = room
	addXp(player, data, xp * StreakService.Mult(player, "Xp"))
end

function ProgressionService.OnRoomCleared(player, room: number)
	questProgress(player, "Room", room, true)
	GameEvents.Fire(player, "Room", room)
end

function ProgressionService.OnRunStarted(player)
	questProgress(player, "Run", 1)
	ProgressionService.Count(player, "Runs", 1)
end


function ProgressionService.Init()
	local allow = RateLimit.new(0.3)
	Remotes.Get("Progression").OnServerInvoke = function(player, action, arg, arg2)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Status" then
			return true, status(player)
		elseif action == "ClaimDaily" then
			return claimDaily(player)
		elseif action == "Spin" then
			return spin(player)
		elseif action == "Stats" then
			return true, ProgressionService.Summary(player)
		elseif action == "ClaimQuest" then
			return claimQuest(player, arg, if arg2 == "Weekly" then "Weekly" else "Daily")
		end
		return false, "Неверный запрос"
	end

	-- the forge and claimed quests feed the weekly goals
	GameEvents.Connect(function(player, kind, amount)
		if kind == "Enhance" or kind == "Quest" then
			questProgress(player, kind, amount or 1)
		end
	end)
	-- time in the game (Статистика)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerState.IsReady(player) then
					ProgressionService.Count(player, "PlaySeconds", 60)
				end
			end
		end
	end)

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
