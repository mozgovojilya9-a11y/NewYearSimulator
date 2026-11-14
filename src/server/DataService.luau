--[[
	DataService.luau
	Server-only module. Owns loading, caching and saving each player's
	persistent data. Nothing outside ServerScriptService should touch
	the DataStore directly -- go through this module instead.

	Safety rules:
	- Loads are retried. If the DataStore still fails, the player plays
	  on default data but that data is NEVER saved, so a temporary
	  Roblox outage can't overwrite real progress with zeros.
	- Saves are retried.
	- If the player leaves while their data is still loading, the
	  result is discarded instead of being cached forever.
	- On server shutdown every loaded player is saved (BindToClose).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LeaderboardService = require(script.Parent.LeaderboardService)

local DataService = {}

local RETRIES = 3
local RETRY_DELAY = 2

local store = DataStoreService:GetDataStore(Config.DataStoreName)
local cache = {} -- [userId] = data table
local noSave = {} -- [userId] = true when load failed

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

local function keyFor(player)
	return "player_" .. player.UserId
end

-- Runs fn up to RETRIES times. Returns ok, result.
local function withRetries(label, player, fn)
	local lastError
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(("[DataService] %s failed for %s (attempt %d/%d): %s"):format(
			label, player.Name, attempt, RETRIES, tostring(result)
		))
		if attempt < RETRIES then
			task.wait(RETRY_DELAY)
		end
	end
	return false, lastError
end

-- Loads (or initializes) a player's data and stores it in the cache.
-- Returns nil if the player left before loading finished.
function DataService.Load(player)
	local key = keyFor(player)
	local ok, data = withRetries("GetAsync", player, function()
		return store:GetAsync(key)
	end)

	if not ok then
		noSave[player.UserId] = true
		warn(("[DataService] Could not load %s; progress this session will NOT be saved."):format(player.Name))
	end

	if type(data) ~= "table" then
		data = deepCopy(Config.StartingData)
	else
		-- Backfill any fields added to StartingData since this player's
		-- last save, without clobbering their existing progress.
		for field, defaultValue in pairs(Config.StartingData) do
			if data[field] == nil then
				-- copy tables so players never share one default table
				data[field] = if type(defaultValue) == "table" then deepCopy(defaultValue) else defaultValue
			end
		end
	end

	-- Fields of removed systems: dropped so they are never written back.
	data.OwnedBackpacks = nil
	data.EquippedBackpack = nil
	-- Old pets (one of each, one equipped) -> pet stacks.
	if type(data.OwnedPets) == "table" then
		for petId in pairs(data.OwnedPets) do
			if Config.PetById[petId] then
				data.Pets[petId] = data.Pets[petId] or { ["1"] = 0 }
				data.Pets[petId]["1"] = (data.Pets[petId]["1"] or 0) + 1
				data.PetIndex[petId] = true
			end
		end
		if type(data.EquippedPet) == "string" and data.Pets[data.EquippedPet] then
			table.insert(data.EquippedPets, data.EquippedPet .. ":1")
		end
	end
	data.OwnedPets = nil
	data.EquippedPet = nil

	if player.Parent == nil then
		noSave[player.UserId] = nil
		return nil -- left during the load
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
	if not data or noSave[player.UserId] then
		return
	end

	data.LastSeen = os.time() -- for offline income on the next join
	local key = keyFor(player)
	local ok = withRetries("SetAsync", player, function()
		store:SetAsync(key, data, { player.UserId })
	end)
	if ok then
		LeaderboardService.Record(player.UserId, data)
	end
end

-- Saves and clears a player's cache entry. Call on PlayerRemoving.
function DataService.Release(player)
	DataService.Save(player)
	cache[player.UserId] = nil
	noSave[player.UserId] = nil
end

-- Server shutdown: save everyone in parallel and wait (Roblox gives
-- BindToClose up to 30 seconds).
game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if cache[player.UserId] then
			pending += 1
			task.spawn(function()
				DataService.Save(player)
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

return DataService
