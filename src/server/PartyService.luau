--[[
	PartyService.luau
	Groups of up to Config.Party.Max players.
	  Party:InvokeServer("Invite", userId)   the target gets a popup
	  Party:InvokeServer("Accept", partyId) / ("Decline", partyId)
	  Party:InvokeServer("Leave")
	  Party:InvokeServer("Search", locationId)  queue for a location: when
	      the queue fills a group, or after Config.Party.SearchSeconds, the
	      group found so far is sent in together (GateService.Launch)
	  Party:InvokeServer("Cancel")           leave the queue
	PartyEvent (S->C): ("State", { Id, Leader, Members = { {UserId, Name} } } | nil)
	                   ("Invite", { Id, From })
	                   ("Search", { Location, Ends } | nil)
	The leader starts gate runs for the whole group (GateService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local PA = Config.Party
local T = PA.Texts

local PartyService = {}

local parties = {} -- [id] = { Id, Leader, Members = { player } }
local partyOf = {} -- [player] = party
local invites = {} -- [player] = { [partyId] = expires }
local queues = {} -- [locationId] = { players = {}, ends = number }
local queueOf = {} -- [player] = locationId
local nextId = 0

PartyService.Launch = nil -- set by GateService: (locationId, players) -> ok, message

local function publish(party)
	local payload = nil
	if party then
		payload = { Id = party.Id, Leader = party.Leader.UserId, Members = {} }
		for _, member in ipairs(party.Members) do
			table.insert(payload.Members, { UserId = member.UserId, Name = member.DisplayName })
		end
		for _, member in ipairs(party.Members) do
			Remotes.Get("PartyEvent"):FireClient(member, "State", payload)
		end
	end
end

function PartyService.PartyOf(player)
	return partyOf[player]
end

-- The players a leader takes with them (just the player when solo).
function PartyService.TeamOf(player)
	local party = partyOf[player]
	if not party then
		return { player }
	end
	return table.clone(party.Members)
end

function PartyService.IsLeader(player): boolean
	local party = partyOf[player]
	return not party or party.Leader == player
end

local function leaveParty(player)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	if player.Parent then
		Remotes.Get("PartyEvent"):FireClient(player, "State", nil)
	end
	for _, member in ipairs(party.Members) do
		Remotes.Notify(member, T.Left:format(player.DisplayName))
	end
	if #party.Members <= 1 then
		for _, member in ipairs(party.Members) do
			partyOf[member] = nil
			Remotes.Get("PartyEvent"):FireClient(member, "State", nil)
		end
		parties[party.Id] = nil
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	publish(party)
end

local function invite(player, userId)
	local target = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not target or target == player then
		return false, "Игрок не найден"
	end
	if partyOf[target] then
		return false, T.InGroup
	end
	local party = partyOf[player]
	if not party then
		nextId += 1
		party = { Id = nextId, Leader = player, Members = { player } }
		parties[party.Id] = party
		partyOf[player] = party
		publish(party)
	end
	if #party.Members >= PA.Max then
		return false, T.Full
	end
	invites[target] = invites[target] or {}
	invites[target][party.Id] = os.clock() + PA.InviteSeconds
	Remotes.Get("PartyEvent"):FireClient(target, "Invite", { Id = party.Id, From = player.DisplayName, Seconds = PA.InviteSeconds })
	return true, "Приглашение отправлено: " .. target.DisplayName
end

local function accept(player, partyId)
	local list = invites[player]
	local expires = list and list[partyId]
	local party = parties[partyId]
	if not expires or expires < os.clock() or not party then
		return false, "Приглашение устарело"
	end
	list[partyId] = nil
	if #party.Members >= PA.Max then
		return false, T.Full
	end
	leaveParty(player)
	table.insert(party.Members, player)
	partyOf[player] = party
	for _, member in ipairs(party.Members) do
		Remotes.Notify(member, T.Joined:format(player.DisplayName), "good")
	end
	publish(party)
	return true, ""
end

---------------------------------------------------------------------
-- Search (matchmaking per location)
---------------------------------------------------------------------

local function dequeue(player)
	local locationId = queueOf[player]
	if not locationId then
		return
	end
	queueOf[player] = nil
	local q = queues[locationId]
	if q then
		local index = table.find(q.players, player)
		if index then
			table.remove(q.players, index)
		end
		if #q.players == 0 then
			queues[locationId] = nil
		end
	end
	if player.Parent then
		Remotes.Get("PartyEvent"):FireClient(player, "Search", nil)
	end
end

local function launchQueue(locationId)
	local q = queues[locationId]
	if not q then
		return
	end
	queues[locationId] = nil
	local team = {}
	for _, player in ipairs(q.players) do
		queueOf[player] = nil
		if player.Parent then
			Remotes.Get("PartyEvent"):FireClient(player, "Search", nil)
			table.insert(team, player)
		end
	end
	if #team > 0 and PartyService.Launch then
		PartyService.Launch(locationId, team)
	end
end

local function search(player, locationId)
	local location = Config.LocationById[locationId or ""]
	if not location or not location.Ready then
		return false, "Неверный запрос"
	end
	if partyOf[player] then
		return false, "Ты уже в группе: начинает лидер"
	end
	dequeue(player)
	local q = queues[locationId]
	if not q then
		q = { players = {}, ends = Workspace:GetServerTimeNow() + PA.SearchSeconds }
		queues[locationId] = q
	end
	table.insert(q.players, player)
	queueOf[player] = locationId
	for _, member in ipairs(q.players) do
		Remotes.Get("PartyEvent"):FireClient(member, "Search", { Location = locationId, Ends = q.ends, Count = #q.players })
	end
	if #q.players >= PA.Max then
		launchQueue(locationId)
	end
	return true, ""
end

function PartyService.Init()
	local allow = RateLimit.new(0.3)
	Remotes.Get("Party").OnServerInvoke = function(player, action, arg)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Invite" then
			return invite(player, arg)
		elseif action == "Accept" then
			return accept(player, tonumber(arg))
		elseif action == "Decline" then
			if invites[player] then
				invites[player][tonumber(arg) or 0] = nil
			end
			return true, ""
		elseif action == "Leave" then
			leaveParty(player)
			return true, ""
		elseif action == "Search" then
			return search(player, arg)
		elseif action == "Cancel" then
			dequeue(player)
			return true, ""
		end
		return false, "Неверный запрос"
	end
	Players.PlayerRemoving:Connect(function(player)
		dequeue(player)
		leaveParty(player)
		invites[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local t = Workspace:GetServerTimeNow()
			for locationId, q in pairs(queues) do
				if t >= q.ends then
					launchQueue(locationId)
				end
			end
		end
	end)
end

PartyService.Dequeue = dequeue
return PartyService
