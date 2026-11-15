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
local DungeonRuns = require(script.Parent.DungeonRuns)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local StatService = require(script.Parent.StatService)
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
					Remotes.Notify(player, "Задание выполнено: " .. def.Text, "gold")
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
	data.Xp += amount
	local gained = 0
	while data.Xp >= xpToNext(data.Level) do
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
		Remotes.Get("LevelUp"):FireClient(player, data.Level, gained * P.Level.SkillPointsPerLevel)
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

-- Exactly `count` level ups (DEV panel): the missing XP is added raw.
function ProgressionService.GrantLevels(player, count: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local need = xpToNext(data.Level) - data.Xp
	for i = 1, count - 1 do
		need += xpToNext(data.Level + i)
	end
	addXp(player, data, need, true)
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
			quests[i] = { Text = def.Text, Target = def.Target, Progress = quest.Progress, Claimed = quest.Claimed, Credits = math.floor(def.Credits * creditScale(data)) }
		end
	end
	local dailyCredits = {}
	for day, amount in ipairs(P.Daily.Credits) do
		dailyCredits[day] = math.floor(amount * creditScale(data))
	end
	return {
		Daily = { CanClaim = canDaily, NextDay = nextDay, Wait = dailyWait, Streak = streak, Credits = dailyCredits },
		Wheel = { CanSpin = canSpin, Wait = spinWait },
		Quests = quests,
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
	local amount = earnCredits(player, def.Credits * creditScale(data))
	local xp = P.Level.XpPerQuest * data.Level
	addXp(player, data, xp)
	ProgressionService.RefreshReady(player)
	return true, ("+%s нано-кредитов, +%s XP"):format(Format.Number(amount), Format.Number(xp))
end

---------------------------------------------------------------------
-- Hooks from gameplay
---------------------------------------------------------------------

function ProgressionService.OnKill(player, room: number, isBoss: boolean, position: Vector3?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local credits = earnCredits(player, Config.KillCredits(room, isBoss))
	if credits > 0 then
		Remotes.Get("ClickHit"):FireClient(player, "Credits", credits, position)
	end
	questProgress(player, "Kill", 1)
	if isBoss then
		questProgress(player, "Boss", 1)
	end
	addXp(player, data, (if isBoss then P.Level.XpPerBoss else P.Level.XpPerKill) * room)
end

function ProgressionService.OnRoomCleared(player, room: number)
	questProgress(player, "Room", room, true)
end

function ProgressionService.OnRunStarted(player)
	questProgress(player, "Run", 1)
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
