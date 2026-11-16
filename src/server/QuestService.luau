--[[
	QuestService.luau
	The mentor's story chain (Config.Quests.Story): one step at a time,
	it leads a new player through every system. Progress comes from
	GameEvents (Kill, Boss, Loot, Enhance, Train) or is read from the save
	(Class, Learn = skill points spent, Stat = stat points spent, Level,
	Room = record room).

	Save: data.Story = { Step, Count, Seen } (Seen = the step the player
	already heard about; a new / finished step shows "!" over the mentor).

	Player attributes for the client:
	  Tracker     JSON { Title, Text, Progress, Target, Ready } (HUD tracker)
	  StoryMarker true = "!" over the mentor
	  StoryPlace  where the floor guide leads: Academy / Training / Forge /
	              Gates / Mentor ("" = nowhere)

	Remote Quest (RemoteFunction):
	  ("Talk", npcId) -> dialog payload (mentor)
	  ("Claim")       -> ok, message (reward of a finished step)
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local Q = Config.Quests
local STORY = Q.Story
local COUNTED = { Kill = true, Boss = true, Loot = true, Enhance = true, Train = true }

local QuestService = {}

local function story(data)
	if type(data.Story) ~= "table" then
		data.Story = { Step = 1, Count = 0, Seen = 0 }
	end
	local s = data.Story
	s.Step = math.max(1, math.floor(tonumber(s.Step) or 1))
	s.Count = math.max(0, tonumber(s.Count) or 0)
	s.Seen = tonumber(s.Seen) or 0
	return s
end

local function progressOf(data, def): number
	local s = story(data)
	if def.Kind == "Class" then
		return if (data.Class or "") ~= "" then 1 else 0
	elseif def.Kind == "Learn" then
		if (data.Class or "") == "" then
			return 0
		end
		return PlayerState.SpentPoints(PlayerState.ClassRecord(data, data.Class))
	elseif def.Kind == "Stat" then
		local spent = 0
		for _, value in pairs(data.Attributes or {}) do
			spent += value
		end
		return spent
	elseif def.Kind == "Level" then
		return data.Level or 1
	elseif def.Kind == "Room" then
		return data.RoomReached or 0
	end
	return s.Count
end

-- Current step def (nil = the chain is finished), progress, ready.
local function current(data)
	local s = story(data)
	local def = STORY[s.Step]
	if not def then
		return nil, 0, false
	end
	local progress = math.min(progressOf(data, def), def.Target)
	return def, progress, progress >= def.Target
end

local notified = {} -- [player] = step already announced as done

local function publish(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local s = story(data)
	local def, progress, ready = current(data)
	if not def then
		player:SetAttribute("Tracker", nil)
		player:SetAttribute("StoryMarker", false)
		player:SetAttribute("StoryPlace", "")
		return
	end
	player:SetAttribute("Tracker", HttpService:JSONEncode({
		Title = def.Title,
		Text = if ready then Q.Ready else def.Text,
		Progress = progress,
		Target = def.Target,
		Ready = ready,
	}))
	local unseen = s.Seen < s.Step
	player:SetAttribute("StoryMarker", ready or unseen)
	player:SetAttribute("StoryPlace", if ready or unseen then "Mentor" else (def.Place or ""))
	if ready and notified[player] ~= s.Step then
		notified[player] = s.Step
		Remotes.Notify(player, Q.Ready, "gold")
	end
end
QuestService.Refresh = publish

local function rewardText(def, data): string
	return Q.Texts.Reward:format(Format.Number(def.Xp * math.max(1, data.Level or 1)), Format.Number(def.Credits))
end

local function talk(player, npcId)
	local data = DataService.Get(player)
	local npc = Config.Npcs[npcId or ""]
	if not data or not npc then
		return nil
	end
	local payload = { Npc = npcId, Name = npc.Name, Title = npc.Title }
	if npcId ~= "Mentor" then
		return payload -- the gate keeper: the client opens the daily quests
	end
	local s = story(data)
	local def, progress, ready = current(data)
	if not def then
		payload.Text = Q.Done
		return payload
	end
	s.Seen = s.Step
	payload.Text = if ready then Q.ReadyTalk else def.Talk
	payload.Quest = { Title = def.Title, Text = def.Text, Progress = progress, Target = def.Target, Step = s.Step, Steps = #STORY }
	payload.Ready = ready
	payload.Reward = rewardText(def, data)
	publish(player)
	return payload
end

local function claim(player)
	local data = DataService.Get(player)
	if not data then
		return false, "Подожди секунду"
	end
	local s = story(data)
	local def, _, ready = current(data)
	if not def or not ready then
		return false, "Задание ещё не выполнено"
	end
	local xp = def.Xp * math.max(1, data.Level or 1)
	PlayerState.AddCredits(player, def.Credits)
	ProgressionService.AddXp(player, xp)
	s.Step += 1
	s.Count = 0
	publish(player)
	return true, ("+%s XP, +%s кр."):format(Format.Number(xp), Format.Number(def.Credits))
end

function QuestService.Init()
	GameEvents.Connect(function(player, kind, amount)
		local data = DataService.Get(player)
		if not data then
			return
		end
		local def = current(data)
		if def and def.Kind == kind and COUNTED[kind] then
			local s = story(data)
			s.Count = math.min(def.Target, s.Count + (amount or 1))
		end
		publish(player)
	end)

	local allow = RateLimit.new(0.3)
	Remotes.Get("Quest").OnServerInvoke = function(player, action, arg)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Talk" then
			return talk(player, arg)
		elseif action == "Claim" then
			return claim(player)
		end
		return false, "Неверный запрос"
	end

	local function join(player)
		task.spawn(function()
			while player.Parent and not PlayerState.IsReady(player) do
				task.wait(0.5)
			end
			publish(player)
		end)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in ipairs(Players:GetPlayers()) do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		notified[player] = nil
	end)
end

return QuestService
