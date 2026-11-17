--[[
	GateService.luau
	Entering the gates.
	  Gate:InvokeServer("Start", locationId)  solo, or the whole group if
	      the player leads one (a countdown first, Config.Party.Countdown)
	  Gate:InvokeServer("Again")              the same location again
	  Gate:InvokeServer("Red")                the active Red Gates
	Rules: a class is needed; a rank opens at its Level once any location
	of the previous rank was cleared (data.Gates.Cleared); every member of
	a group must be in the hub.

	Red Gates (Config.RedGate): every Interval seconds the server opens
	them for Duration seconds on a random ready location (announcement,
	system notice, the red portal in the Gate hall lights up). The state
	is the ReplicatedStorage attribute "RedGate" (JSON: Location, Ends).

	Player attribute "GateRanks" = JSON { E = true, ... } of the open
	ranks, "GateBest" = JSON { [locationId] = grade } (the gates window).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local PartyService = require(script.Parent.PartyService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local G = Config.Gates
local T = G.Texts
local RG = Config.RedGate

local GateService = {}

local lastLocation = {} -- [player] = locationId
local red = nil -- { Location = location, Ends = serverTime }
local redPortal = nil -- hub red gate parts

local function cleared(data)
	local gates = data and type(data.Gates) == "table" and data.Gates
	return (gates and type(gates.Cleared) == "table" and gates.Cleared) or {}
end

-- Is `rank` open for this player? Returns ok, reason.
function GateService.RankOpen(player, rank: string): (boolean, string?)
	local info = G.RankInfo[rank]
	local data = DataService.Get(player)
	if not info or not data then
		return false, T.Locked
	end
	if (data.Level or 1) < info.Level then
		return false, T.NeedLevel:format(info.Level)
	end
	if info.Requires then
		local done = false
		for locationId in pairs(cleared(data)) do
			local location = Config.LocationById[locationId]
			if location and location.Rank == info.Requires then
				done = true
			end
		end
		if not done then
			return false, T.NeedRank:format(info.Requires)
		end
	end
	return true, nil
end

local function publish(player)
	local ranks = {}
	for _, rank in ipairs(G.Ranks) do
		ranks[rank] = (GateService.RankOpen(player, rank))
	end
	player:SetAttribute("GateRanks", HttpService:JSONEncode(ranks))
	player:SetAttribute("GateBest", HttpService:JSONEncode(cleared(DataService.Get(player))))
end
GateService.Publish = publish

local function check(player, location): (boolean, string?)
	if not location or not location.Ready then
		return false, T.Soon
	end
	if (player:GetAttribute("Class") or "") == "" then
		return false, Config.Combat.Texts.NeedClass
	end
	if DungeonRuns.HasRun(player) then
		return false, T.Busy
	end
	return GateService.RankOpen(player, location.Rank)
end

-- Sends `players` into `location` (after the group countdown).
function GateService.Launch(locationId: string, players, opts)
	local location = Config.LocationById[locationId]
	local team = {}
	for _, player in ipairs(players) do
		local ok, reason = check(player, location)
		if ok then
			table.insert(team, player)
		else
			Remotes.Notify(player, reason or T.Locked, "bad")
		end
	end
	if #team == 0 then
		return false, T.Locked
	end
	if #team > 1 then
		for i = Config.Party.Countdown, 1, -1 do
			for _, player in ipairs(team) do
				Remotes.Notify(player, Config.Party.Texts.Starting:format(i), "gold")
			end
			task.wait(1)
		end
	end
	local alive = {}
	for _, player in ipairs(team) do
		if player.Parent and player.Character and not DungeonRuns.HasRun(player) then
			table.insert(alive, player)
			lastLocation[player] = locationId
			PartyService.Dequeue(player)
		end
	end
	if #alive == 0 then
		return false, T.Busy
	end
	local run, message = DungeonRuns.Start(location, alive, opts)
	if not run then
		return false, message
	end
	return true, location.Name
end

local function start(player, locationId, opts)
	local location = Config.LocationById[locationId or ""]
	local ok, reason = check(player, location)
	if not ok then
		return false, reason
	end
	if not PartyService.IsLeader(player) then
		return false, T.NotLeader
	end
	local team = PartyService.TeamOf(player)
	if #team > 1 then
		task.spawn(GateService.Launch, locationId, team, opts)
		return true, ""
	end
	return GateService.Launch(locationId, team, opts)
end

---------------------------------------------------------------------
-- Red Gates
---------------------------------------------------------------------

local function setRedPortal(on: boolean)
	if not redPortal then
		return
	end
	for _, part in ipairs(redPortal.Parts) do
		part.Transparency = if on then part:GetAttribute("OnTransparency") or 0.2 else 1
	end
	if redPortal.Prompt then
		redPortal.Prompt.Enabled = on
	end
	if redPortal.Light then
		redPortal.Light.Enabled = on
	end
end

local function publishRed()
	if red then
		ReplicatedStorage:SetAttribute("RedGate", HttpService:JSONEncode({ Location = red.Location.Id, Ends = red.Ends }))
	else
		ReplicatedStorage:SetAttribute("RedGate", "")
	end
	setRedPortal(red ~= nil)
end

function GateService.OpenRed(location)
	local pool = {}
	for _, l in ipairs(G.Locations) do
		if l.Ready then
			table.insert(pool, l)
		end
	end
	location = location or pool[math.random(#pool)]
	red = { Location = location, Ends = Workspace:GetServerTimeNow() + RG.Duration }
	publishRed()
	local minutes = math.floor(RG.Duration / 60)
	local line = RG.Texts.OpenLine:format(location.Name, location.Rank, minutes, RG.Duration % 60)
	Remotes.Get("Announce"):FireAllClients(RG.Texts.Open .. " " .. line, RG.Color)
	for _, player in ipairs(Players:GetPlayers()) do
		Remotes.Get("System"):FireClient(player, RG.Texts.Open, { line }, "red")
	end
	task.delay(RG.Duration, function()
		if red and red.Ends <= Workspace:GetServerTimeNow() + 1 then
			red = nil
			publishRed()
			Remotes.Get("Announce"):FireAllClients(RG.Texts.Closed, RG.Color)
		end
	end)
end

local function enterRed(player)
	if not red then
		return false, RG.Texts.Closed
	end
	return start(player, red.Location.Id, { Red = true })
end

---------------------------------------------------------------------

function GateService.Init(hub)
	redPortal = hub.RedGate
	if redPortal and redPortal.Prompt then
		redPortal.Prompt.Triggered:Connect(function(player)
			local ok, message = enterRed(player)
			if not ok and message then
				Remotes.Notify(player, message, "bad")
			end
		end)
	end
	PartyService.Launch = GateService.Launch
	-- a closed location may open the next rank
	local previous = DungeonRuns.OnRoomCleared
	DungeonRuns.OnRoomCleared = function(player, tier)
		if previous then
			previous(player, tier)
		end
		publish(player)
	end
	local allow = RateLimit.new(0.8)
	Remotes.Get("Gate").OnServerInvoke = function(player, action, arg)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Start" then
			return start(player, arg)
		elseif action == "Again" then
			local locationId = lastLocation[player]
			if not locationId then
				return false, "Неверный запрос"
			end
			if DungeonRuns.HasRun(player) then
				DungeonRuns.EndRun(player, "Won")
			end
			return start(player, locationId)
		elseif action == "Red" then
			return enterRed(player)
		end
		return false, "Неверный запрос"
	end
	-- the gate ranks follow level and clears
	local function watch(player)
		task.spawn(function()
			while player.Parent and not PlayerState.IsReady(player) do
				task.wait(0.5)
			end
			publish(player)
		end)
		player:GetAttributeChangedSignal("Level"):Connect(function()
			publish(player)
		end)
		player:GetAttributeChangedSignal("RoomReached"):Connect(function()
			publish(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastLocation[player] = nil
	end)
	publishRed()
	task.spawn(function()
		task.wait(RG.First)
		while true do
			if not red then
				GateService.OpenRed()
			end
			task.wait(RG.Interval)
		end
	end)
end

return GateService
