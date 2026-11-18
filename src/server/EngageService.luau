--[[
	EngageService.luau
	Things that bring players back (server-authoritative):
	  * playtime gifts (Config.Gifts): minutes played today, a gift ready at
	    each step; attributes GiftNext (index), GiftAt (play seconds today
	    when it is ready), GiftPlayed (play seconds today);
	  * promo codes (Config.Codes), once per player;
	  * achievements (Config.Achievements) from the save counters, reward in
	    Кристаллы + a title the player can wear (attribute "Title").
	Remote Engage (RemoteFunction):
	  ("Gift")              -> ok, message
	  ("Code", text)        -> ok, message
	  ("Achievements")      -> true, { { Id, Name, Text, Target, Progress, Done, Crystals, Title } }
	  ("Title", id | "")    -> ok, message
	Every reward also fires a System notice and a sound on the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local EngageService = {}

local GF = Config.Gifts
local played = {} -- [player] = play seconds today (counted here)

local function today(): number
	return math.floor(os.time() / 86400)
end

local function system(player, title: string, lines, color: string?)
	Remotes.Get("System"):FireClient(player, title, lines, color or "gold")
end

-- Gives a reward table { Credits, Crystals, Cores }; returns its text.
local function give(player, reward): string
	local parts = {}
	if (reward.Crystals or 0) > 0 then
		PlayerState.AddCrystals(player, reward.Crystals)
		table.insert(parts, ("+%d Кристаллов"):format(reward.Crystals))
	end
	if (reward.Credits or 0) > 0 then
		PlayerState.AddCredits(player, reward.Credits)
		table.insert(parts, ("+%s кр."):format(Format.Number(reward.Credits)))
	end
	if (reward.Cores or 0) > 0 then
		PlayerState.AddCores(player, reward.Cores)
		table.insert(parts, ("+%d ядер"):format(reward.Cores))
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------
-- Playtime gifts
---------------------------------------------------------------------

local function gifts(data)
	if type(data.Gifts) ~= "table" or data.Gifts.Day ~= today() then
		data.Gifts = { Day = today(), Claimed = {}, Played = 0 }
	end
	data.Gifts.Claimed = if type(data.Gifts.Claimed) == "table" then data.Gifts.Claimed else {}
	data.Gifts.Played = tonumber(data.Gifts.Played) or 0
	return data.Gifts
end

local function publishGift(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local g = gifts(data)
	local nextIndex = 0
	for i in ipairs(GF.List) do
		if not g.Claimed[tostring(i)] then
			nextIndex = i
			break
		end
	end
	player:SetAttribute("GiftNext", nextIndex)
	player:SetAttribute("GiftAt", if nextIndex > 0 then GF.List[nextIndex].Minute * 60 else 0)
	player:SetAttribute("GiftPlayed", g.Played)
end

local function claimGift(player)
	local data = DataService.Get(player)
	if not data then
		return false, "Подожди секунду"
	end
	local g = gifts(data)
	for i, def in ipairs(GF.List) do
		if not g.Claimed[tostring(i)] then
			if g.Played < def.Minute * 60 then
				return false, GF.Texts.Next:format(("%d мин"):format(math.ceil((def.Minute * 60 - g.Played) / 60)))
			end
			g.Claimed[tostring(i)] = true
			local text = give(player, def)
			publishGift(player)
			system(player, GF.Texts.Ready, { text }, "gold")
			return true, GF.Texts.Got:format(text)
		end
	end
	return false, GF.Texts.Done
end

---------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------

local function redeem(player, text)
	local data = DataService.Get(player)
	if not data or type(text) ~= "string" then
		return false, Config.Codes.Texts.Bad
	end
	local code = text:upper():gsub("%s+", "")
	local def = Config.Codes[code]
	if code == "TEXTS" or type(def) ~= "table" or (def.Ends and os.time() > def.Ends) then
		return false, Config.Codes.Texts.Bad
	end
	data.Codes = if type(data.Codes) == "table" then data.Codes else {}
	if data.Codes[code] then
		return false, Config.Codes.Texts.Used
	end
	data.Codes[code] = true
	local reward = give(player, def)
	system(player, "Код активирован", { reward }, "gold")
	return true, Config.Codes.Texts.Ok:format(reward)
end

---------------------------------------------------------------------
-- Achievements
---------------------------------------------------------------------

local function progressOf(data, kind: string): number
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	if kind == "Level" then
		return data.Level or 1
	elseif kind == "PlayHours" then
		return math.floor((stats.PlaySeconds or 0) / 3600)
	elseif kind == "RankD" or kind == "GradeS" then
		local cleared = (type(data.Gates) == "table" and type(data.Gates.Cleared) == "table") and data.Gates.Cleared or {}
		for id, grade in pairs(cleared) do
			local location = Config.LocationById[id]
			if kind == "RankD" and location and Config.GateRankIndex[location.Rank] >= Config.GateRankIndex.D then
				return 1
			elseif kind == "GradeS" and grade == "S" then
				return 1
			end
		end
		return 0
	elseif kind == "Enhance" then
		local best = 0
		for _, item in pairs(data.Items or {}) do
			best = math.max(best, tonumber(item.E) or 0)
		end
		return best
	end
	return tonumber(stats[kind]) or 0
end

local function checkAchievements(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Achievements = if type(data.Achievements) == "table" then data.Achievements else {}
	for _, def in ipairs(Config.Achievements) do
		if not data.Achievements[def.Id] and progressOf(data, def.Kind) >= def.Target then
			data.Achievements[def.Id] = true
			local reward = give(player, { Crystals = def.Crystals })
			local lines = { def.Text, reward }
			if def.Title then
				table.insert(lines, ("Титул: «%s»"):format(def.Title))
			end
			system(player, "Достижение: " .. def.Name, lines, "gold")
		end
	end
end

local function achievementList(player)
	local data = DataService.Get(player)
	local list = {}
	for _, def in ipairs(Config.Achievements) do
		local done = data and type(data.Achievements) == "table" and data.Achievements[def.Id] == true
		table.insert(list, {
			Id = def.Id,
			Name = def.Name,
			Text = def.Text,
			Target = def.Target,
			Progress = if data then math.min(def.Target, progressOf(data, def.Kind)) else 0,
			Done = done,
			Crystals = def.Crystals,
			Title = def.Title,
		})
	end
	return list
end

local function setTitle(player, id)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	if id == "" or id == nil then
		data.Title = ""
		player:SetAttribute("Title", "")
		return true, "Титул снят"
	end
	for _, def in ipairs(Config.Achievements) do
		if def.Id == id and def.Title and type(data.Achievements) == "table" and data.Achievements[id] then
			data.Title = def.Title
			player:SetAttribute("Title", def.Title)
			return true, "Титул: " .. def.Title
		end
	end
	return false, "Титул ещё не получен"
end

---------------------------------------------------------------------

function EngageService.Init()
	local allow = RateLimit.new(0.3)
	Remotes.Get("Engage").OnServerInvoke = function(player, action, arg)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Gift" then
			return claimGift(player)
		elseif action == "Code" then
			return redeem(player, arg)
		elseif action == "Achievements" then
			return true, achievementList(player)
		elseif action == "Title" then
			return setTitle(player, arg)
		end
		return false, "Неверный запрос"
	end
	GameEvents.Connect(function(player)
		checkAchievements(player)
	end)
	-- the play clock (today) and a slow achievement check
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerState.IsReady(player) and DataService.Get(player)
				if data then
					local g = gifts(data)
					g.Played += 10
					publishGift(player)
					played[player] = g.Played
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerState.IsReady(player) then
					checkAchievements(player)
				end
			end
		end
	end)
	local function onPlayer(player)
		task.spawn(function()
			while player.Parent and not PlayerState.IsReady(player) do
				task.wait(0.5)
			end
			local data = DataService.Get(player)
			if data then
				player:SetAttribute("Title", if type(data.Title) == "string" then data.Title else "")
				publishGift(player)
				checkAchievements(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		played[player] = nil
	end)
end

return EngageService
