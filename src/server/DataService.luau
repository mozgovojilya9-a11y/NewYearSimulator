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
local Items = require(ReplicatedStorage.Shared.Items)
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
		data.SchemaVersion = Config.SchemaVersion -- new player: nothing to migrate
	else
		-- Read the version BEFORE backfilling (saves without it are v1).
		local version = if type(data.SchemaVersion) == "number" then data.SchemaVersion else 1
		-- Backfill any fields added to StartingData since this player's
		-- last save, without clobbering their existing progress.
		for field, defaultValue in pairs(Config.StartingData) do
			if data[field] == nil then
				-- copy tables so players never share one default table
				data[field] = if type(defaultValue) == "table" then deepCopy(defaultValue) else defaultValue
			end
		end
		DataService.Migrate(data, version, player)
	end
	DataService.Sanitize(data)

	-- Fields of removed systems: dropped so they are never written back.
	data.Aura = nil
	data.Rebirths = nil
	data.TrainersUnlocked = nil
	data.BoostUntil = nil
	data.OwnedBackpacks = nil
	data.EquippedBackpack = nil
	data.OwnedPets = nil -- pets (removed in schema 4, compensated there)
	data.EquippedPet = nil
	data.Pets = nil
	data.EquippedPets = nil
	data.PetIndex = nil
	data.Materials = nil -- crafting (removed in schema 6, compensated there)
	data.OwnedWeapons = nil
	data.OwnedArmor = nil
	data.EquippedWeapon = nil
	data.EquippedArmor = nil

	if player.Parent == nil then
		noSave[player.UserId] = nil
		return nil -- left during the load
	end

	cache[player.UserId] = data
	return data
end

---------------------------------------------------------------------
-- Migrations: Migrations[v] upgrades a save from version v to v + 1.
---------------------------------------------------------------------

DataService.Migrations = {
	-- 1 -> 2: Aura became power (never spent) and Нано-кредиты appeared.
	-- Aura is kept exactly as it was (Aura spent in the old economy is not
	-- given back, nothing is taken either). Levels already reached grant
	-- their skill points now.
	[1] = function(data)
		data.Credits = if type(data.Credits) == "number" then data.Credits else 0
		if type(data.SkillPoints) ~= "number" or data.SkillPoints == 0 then
			data.SkillPoints = math.max(0, (data.Level or 1) - 1) * Config.Progression.Level.SkillPointsPerLevel
		end
	end,
	-- 2 -> 3: the clicker is gone (action-RPG). Aura, rebirths and
	-- trainers are removed; their worth becomes Нано-кредиты once
	-- (Config.Migration), with a message on the next join. The old x2
	-- Aura boost time moves to the x2 XP boost.
	[2] = function(data)
		local m = Config.Migration
		local aura = if type(data.Aura) == "number" and data.Aura == data.Aura then math.max(0, data.Aura) else 0
		local rebirths = if type(data.Rebirths) == "number" then math.max(0, data.Rebirths) else 0
		local credits = math.floor(math.min(m.Max, m.PerAuraDigit * math.log10(aura + 1) + m.PerRebirth * rebirths))
		if credits > 0 then
			data.Credits = (if type(data.Credits) == "number" then data.Credits else 0) + credits
			data.Notice = m.Notice:format(tostring(credits))
		end
		data.Boosts = if type(data.Boosts) == "table" then data.Boosts else {}
		if type(data.BoostUntil) == "number" and data.BoostUntil > (data.Boosts.Xp or 0) then
			data.Boosts.Xp = data.BoostUntil
		end
		data.Aura = nil
		data.Rebirths = nil
		data.TrainersUnlocked = nil
		data.BoostUntil = nil
	end,
	-- 3 -> 4: pets are gone. Every pet (stacks by tier, plus the very old
	-- one-of-each OwnedPets) becomes Нано-кредиты once (Config.PetMigration),
	-- with a message on the next join.
	[3] = function(data)
		local m = Config.PetMigration
		local total = 0
		local function add(petId, tier, count)
			local rarity = m.PetRarity[petId]
			if rarity and type(count) == "number" and count > 0 then
				total += (m.ByRarity[rarity] or 0) * (m.TierMult[tostring(tier)] or 1) * math.floor(count)
			end
		end
		if type(data.Pets) == "table" then
			for petId, tiers in pairs(data.Pets) do
				if type(tiers) == "table" then
					for tier, count in pairs(tiers) do
						add(petId, tier, count)
					end
				end
			end
		end
		if type(data.OwnedPets) == "table" then
			for petId in pairs(data.OwnedPets) do
				add(petId, "1", 1)
			end
		end
		local credits = math.floor(math.min(m.Max, total))
		if credits > 0 then
			data.Credits = (if type(data.Credits) == "number" then data.Credits else 0) + credits
			local notice = m.Notice:format(tostring(credits))
			data.Notice = if type(data.Notice) == "string" and data.Notice ~= "" then data.Notice .. "\n" .. notice else notice
		end
		data.Pets = nil
		data.EquippedPets = nil
		data.PetIndex = nil
		data.OwnedPets = nil
		data.EquippedPet = nil
	end,
	-- 4 -> 5: gear stronger than the player's progress is replaced by the
	-- best gear of the biome the player can reach (Config.ItemMigration).
	[4] = function(data)
		DataService.FitGearToProgress(data)
	end,
	-- 5 -> 6: crafting is gone. Owned catalog gear becomes item instances
	-- with the same numbers (usable by any class), what was equipped stays
	-- equipped; materials turn into credits + Нано-ядра once.
	[5] = function(data)
		DataService.GearToItems(data)
		local m = Config.CraftMigration
		local credits, cores = 0, 0
		if type(data.Materials) == "table" then
			for materialId, count in pairs(data.Materials) do
				local rarity = m.MaterialRarity[materialId]
				if rarity and type(count) == "number" and count > 0 then
					credits += (m.Credits[rarity] or 0) * count
					cores += (m.Cores[rarity] or 0) * count
				end
			end
		end
		credits = math.floor(math.min(m.MaxCredits, credits))
		cores = math.floor(math.min(m.MaxCores, cores) + 0.5)
		if credits > 0 or cores > 0 then
			data.Credits = (if type(data.Credits) == "number" then data.Credits else 0) + credits
			data.Cores = (if type(data.Cores) == "number" then data.Cores else 0) + cores
			local notice = m.Notice:format(tostring(credits), tostring(cores))
			data.Notice = if type(data.Notice) == "string" and data.Notice ~= "" then data.Notice .. "\n" .. notice else notice
		end
		data.Materials = nil
	end,
}

-- Adds an instance to data.Items with a fresh uid. Returns the uid.
function DataService.AddItem(data, instance): string
	data.Items = if type(data.Items) == "table" then data.Items else {}
	data.NextItem = if type(data.NextItem) == "number" then data.NextItem else 1
	local uid = "i" .. data.NextItem
	while data.Items[uid] do
		data.NextItem += 1
		uid = "i" .. data.NextItem
	end
	data.NextItem += 1
	instance.U = uid
	data.Items[uid] = instance
	return uid
end

-- Schema 6: OwnedWeapons / OwnedArmor / EquippedWeapon / EquippedArmor
-- (catalog ids) -> item instances.
function DataService.GearToItems(data)
	data.Items = if type(data.Items) == "table" then data.Items else {}
	data.Equipped = if type(data.Equipped) == "table" then data.Equipped else { Weapon = "", Helmet = "", Chest = "", Legs = "" }
	if type(data.OwnedWeapons) == "table" then
		for id in pairs(data.OwnedWeapons) do
			local base = Config.ItemById.Weapon[id]
			if base then
				local instance = Items.FromCatalog("W", base)
				if id == Config.Items.Starter then
					instance.St = true
				end
				local uid = DataService.AddItem(data, instance)
				if data.EquippedWeapon == id then
					data.Equipped.Weapon = uid
				end
			end
		end
	end
	if type(data.OwnedArmor) == "table" then
		for id in pairs(data.OwnedArmor) do
			local base = Config.ItemById.Armor[id]
			if base then
				local uid = DataService.AddItem(data, Items.FromCatalog("A", base))
				if type(data.EquippedArmor) == "table" and data.EquippedArmor[base.Slot] == id then
					data.Equipped[base.Slot] = uid
				end
			end
		end
	end
	data.OwnedWeapons = nil
	data.OwnedArmor = nil
	data.EquippedWeapon = nil
	data.EquippedArmor = nil
end

-- Replaces gear above the player's progress (schema 5 migration; the DEV
-- panel can call it too). Returns the credits given.
function DataService.FitGearToProgress(data): number
	local m = Config.ItemMigration
	local room = if type(data.RoomReached) == "number" then data.RoomReached else 0
	local biome = math.clamp(room // m.RoomsPerBiome + 1, 1, 4)
	-- the strongest normal weapon of the allowed biomes (per class + overall)
	local cap, bestByClass, best = 1, {}, nil
	for _, w in ipairs(Config.Weapons) do
		if not w.Robux and not w.Legacy and (w.Biome or 0) <= biome then
			cap = math.max(cap, w.Damage)
			if not best or w.Damage > best.Damage then
				best = w
			end
			if not bestByClass[w.Class] or w.Damage > bestByClass[w.Class].Damage then
				bestByClass[w.Class] = w
			end
		end
	end
	local credits = 0
	data.OwnedWeapons = if type(data.OwnedWeapons) == "table" then data.OwnedWeapons else {}
	for id in pairs(table.clone(data.OwnedWeapons)) do
		local w = Config.ItemById.Weapon[id]
		if w and not w.Robux and w.Damage > cap then
			local replacement = bestByClass[w.Class] or best
			data.OwnedWeapons[id] = nil
			credits += m.ByRarity[w.Rarity] or 0
			if replacement then
				data.OwnedWeapons[replacement.Id] = true
				if data.EquippedWeapon == id then
					data.EquippedWeapon = replacement.Id
				end
			end
		end
	end
	if not data.OwnedWeapons[data.EquippedWeapon or ""] then
		data.OwnedWeapons.Stick = true
		data.EquippedWeapon = if best and data.OwnedWeapons[best.Id] then best.Id else "Stick"
	end
	local setOfBiome = nil
	for _, setId in ipairs(Config.ArmorSetOrder) do
		local set = Config.ArmorSets[setId]
		if not set.Robux and set.Biome and set.Biome <= biome then
			setOfBiome = setId
		end
	end
	data.OwnedArmor = if type(data.OwnedArmor) == "table" then data.OwnedArmor else {}
	data.EquippedArmor = if type(data.EquippedArmor) == "table" then data.EquippedArmor else {}
	for id in pairs(table.clone(data.OwnedArmor)) do
		local piece = Config.ItemById.Armor[id]
		local set = piece and Config.ArmorSets[piece.Set]
		if piece and set and not set.Robux and (set.Biome or 0) > biome then
			data.OwnedArmor[id] = nil
			credits += m.ByRarity[piece.Rarity] or 0
			local replacement = setOfBiome and (setOfBiome .. piece.Slot)
			if replacement and Config.ItemById.Armor[replacement] then
				data.OwnedArmor[replacement] = true
			end
			if data.EquippedArmor[piece.Slot] == id then
				data.EquippedArmor[piece.Slot] = replacement or ""
			end
		end
	end
	credits = math.floor(math.min(m.Max, credits))
	if credits > 0 then
		data.Credits = (if type(data.Credits) == "number" then data.Credits else 0) + credits
		local notice = m.Notice:format(tostring(credits))
		data.Notice = if type(data.Notice) == "string" and data.Notice ~= "" then data.Notice .. "\n" .. notice else notice
	end
	return credits
end

function DataService.Migrate(data, fromVersion: number, player)
	local version = fromVersion
	while version < Config.SchemaVersion do
		local step = DataService.Migrations[version]
		if step then
			local ok, err = pcall(step, data)
			if not ok then
				warn(("[DataService] migration %d -> %d failed for %s: %s"):format(version, version + 1, player.Name, tostring(err)))
			end
		end
		version += 1
	end
	data.SchemaVersion = math.max(version, fromVersion)
end

-- Repairs broken values so no system ever crashes on a bad save.
function DataService.Sanitize(data)
	local function number(field, default)
		local v = data[field]
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			data[field] = default
		end
	end
	number("Credits", 0)
	data.Credits = math.max(0, math.floor(data.Credits))
	number("RoomReached", 0)
	number("Level", 1)
	data.Level = math.max(1, math.floor(data.Level))
	number("Xp", 0)
	number("SkillPoints", 0)
	for field, default in pairs(Config.StartingData) do
		if type(default) == "table" and type(data[field]) ~= "table" then
			data[field] = deepCopy(default)
		end
	end
	number("Cores", 0)
	number("Crystals", 0)
	number("CrystalsPaid", 0)
	if type(data.Gacha) ~= "table" then
		data.Gacha = {}
	end
	data.Cores = math.max(0, math.floor(data.Cores))
	number("NextItem", 1)
	-- items: drop broken ones, keep every field in range
	local starter = nil
	for uid, item in pairs(data.Items) do
		local base = type(item) == "table" and Items.Base(item)
		if not base or not Config.Rarity[item.R] then
			data.Items[uid] = nil
		else
			item.U = uid
			item.L = math.clamp(math.floor(tonumber(item.L) or 1), 1, Config.Items.MaxLevel)
			item.E = math.clamp(math.floor(tonumber(item.E) or 0), 0, Config.Forge.MaxEnhance)
			item.Q = math.clamp(tonumber(item.Q) or 1, 0.2, 3)
			if type(item.P) ~= "table" then
				item.P = nil
			end
			if item.K == "W" and item.St then
				starter = uid
			end
		end
	end
	-- the starter weapon always exists (class-free, can't be salvaged)
	if not starter then
		local instance = Items.FromCatalog("W", Config.ItemById.Weapon[Config.Items.Starter])
		instance.St = true
		starter = DataService.AddItem(data, instance)
	end
	for _, slot in ipairs({ "Weapon", "Helmet", "Chest", "Legs" }) do
		local item = data.Items[data.Equipped[slot] or ""]
		local base = item and Items.Base(item)
		local fits = base and (if slot == "Weapon" then item.K == "W" else item.K == "A" and base.Slot == slot)
		if not fits then
			data.Equipped[slot] = if slot == "Weapon" then starter else ""
		end
	end
	for id, record in pairs(data.Artifacts) do
		if not Config.ArtifactById or not Config.ArtifactById[id] or type(record) ~= "table" then
			data.Artifacts[id] = nil
		else
			record.Level = math.clamp(math.floor(tonumber(record.Level) or 1), 1, Config.Artifacts.MaxLevel)
			record.Copies = math.max(0, math.floor(tonumber(record.Copies) or 0))
		end
	end
	for i = 1, 3 do
		local id = data.ArtifactSlots[i]
		if type(id) ~= "string" or (id ~= "" and not data.Artifacts[id]) then
			data.ArtifactSlots[i] = ""
		end
	end
	for _, key in ipairs({ "Str", "Agi", "Vit", "Per" }) do
		data.Attributes[key] = math.max(0, math.floor(tonumber(data.Attributes[key]) or 0))
	end
	for _, kind in ipairs(Config.BoostKinds) do
		if type(data.Boosts[kind]) ~= "number" then
			data.Boosts[kind] = 0
		end
	end
end

-- Replaces a player's progress with a fresh start (DEV panel only).
function DataService.Reset(player)
	if cache[player.UserId] then
		local data = deepCopy(Config.StartingData)
		data.SchemaVersion = Config.SchemaVersion
		DataService.Sanitize(data)
		cache[player.UserId] = data
		return data
	end
	return nil
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
