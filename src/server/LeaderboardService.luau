--[[
	LeaderboardService.luau
	Two OrderedDataStore boards shown on the hub wall: top Aura and
	deepest dungeon room. Scores are pushed on every player save
	(DataService calls Record); the boards refresh every
	Config.Leaderboards.RefreshSeconds. Everything is pcall-wrapped:
	a DataStore hiccup only leaves the old text on the wall.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local LeaderboardService = {}

local L = Config.Leaderboards
local stores = {}
local boards = {} -- [kind] = SurfaceGui

local function store(kind)
	if not stores[kind] then
		stores[kind] = DataStoreService:GetOrderedDataStore(if kind == "Aura" then L.AuraStore else L.RoomStore)
	end
	return stores[kind]
end

-- Called by DataService after a successful save.
function LeaderboardService.Record(userId: number, data)
	task.spawn(function()
		pcall(function()
			store("Aura"):SetAsync(tostring(userId), math.max(0, math.floor(data.Aura)))
		end)
		pcall(function()
			store("Room"):SetAsync(tostring(userId), math.max(0, math.floor(data.RoomReached)))
		end)
	end)
end

local nameCache = {}
local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.Name
	if not name then
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = if ok then result else "?"
	end
	nameCache[userId] = name
	return name
end

local function refresh(kind)
	local gui = boards[kind]
	if not gui then
		return
	end
	local ok, pages = pcall(function()
		return store(kind):GetSortedAsync(false, L.Top)
	end)
	if not ok then
		return
	end
	local rows = pages:GetCurrentPage()
	for i = 1, L.Top do
		local label = gui:FindFirstChild("Row" .. i)
		if label then
			local row = rows[i]
			if row then
				local value = if kind == "Aura" then Format.Number(row.value) .. " ✨" else "этап " .. row.value
				label.Text = ("%d. %s — %s"):format(i, nameFor(tonumber(row.key)), value)
			else
				label.Text = i .. ". —"
			end
		end
	end
end

function LeaderboardService.Init(boardGuis)
	boards = boardGuis or {}
	task.spawn(function()
		while true do
			for kind in pairs(boards) do
				refresh(kind)
			end
			task.wait(L.RefreshSeconds)
		end
	end)
end

return LeaderboardService
