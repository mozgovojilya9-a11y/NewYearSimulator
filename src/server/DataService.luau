--[[
	DataService.luau
	Server-only module. Owns loading, caching and saving each player's
	persistent data. Nothing outside ServerScriptService should touch
	the DataStore directly -- go through this module instead.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local store = DataStoreService:GetDataStore(Config.DataStoreName)
local cache = {} -- [userId] = data table

local function deepCopy(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Loads (or initializes) a player's data and stores it in the cache.
-- Safe to call once per PlayerAdded.
function DataService.Load(player)
	local key = "player_" .. player.UserId
	local data

	local ok, err = pcall(function()
		data = store:GetAsync(key)
	end)

	if not ok then
		warn(("[DataService] GetAsync failed for %s: %s"):format(player.Name, tostring(err)))
	end

	if type(data) ~= "table" then
		data = deepCopy(Config.StartingData)
	else
		-- Backfill any fields added to StartingData since this player's
		-- last save, without clobbering their existing progress.
		for key2, defaultValue in pairs(Config.StartingData) do
			if data[key2] == nil then
				data[key2] = defaultValue
			end
		end
	end

	cache[player.UserId] = data
	return data
end

-- Returns the cached data table for a player, or nil if not loaded.
function DataService.Get(player)
	return cache[player.UserId]
end

-- Persists the cached data table for a player to the DataStore.
function DataService.Save(player)
	local data = cache[player.UserId]
	if not data then
		return
	end

	local key = "player_" .. player.UserId
	local ok, err = pcall(function()
		store:SetAsync(key, data)
	end)

	if not ok then
		warn(("[DataService] SetAsync failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

-- Saves and clears a player's cache entry. Call on PlayerRemoving.
function DataService.Release(player)
	DataService.Save(player)
	cache[player.UserId] = nil
end

return DataService
