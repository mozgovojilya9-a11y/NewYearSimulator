--[[
	PlayerState.luau
	Access to the player's state: credits, level, materials, armor, pets,
	boosts. Every service goes through here instead of poking the data
	table directly. Final numbers (damage, HP, ...) are computed by
	StatService, never here.

	Everything lives in the DataService table and is pushed to the
	client as Player attributes by PlayerState.Sync; leaderstats (Level,
	Room) appear once the data is loaded.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Passes = require(script.Parent.Passes)

local PlayerState = {}

PlayerState.OnSynced = nil -- set by StatService: recompute stats after every Sync

function PlayerState.IsReady(player): boolean
	return DataService.Get(player) ~= nil and player:FindFirstChild("leaderstats") ~= nil
end

---------------------------------------------------------------------
-- Armor
---------------------------------------------------------------------

-- The equipped armor piece in a slot (or nil).
function PlayerState.ArmorIn(player, slot: string)
	local data = DataService.Get(player)
	local id = data and data.EquippedArmor[slot]
	return if id and id ~= "" and data.OwnedArmor[id] then Config.ItemById.Armor[id] else nil
end

-- The armor set whose 3 pieces are all equipped (or nil).
function PlayerState.ActiveSet(player)
	local setId = nil
	for _, slot in ipairs(Config.ArmorSlots) do
		local piece = PlayerState.ArmorIn(player, slot)
		if not piece or (setId and piece.Set ~= setId) then
			return nil
		end
		setId = piece.Set
	end
	return Config.ArmorSets[setId]
end

---------------------------------------------------------------------
-- Нано-кредиты (the spendable currency)
---------------------------------------------------------------------

function PlayerState.GetCredits(player): number
	local data = DataService.Get(player)
	return if data then data.Credits or 0 else 0
end

-- Adds credits (amount > 0). Returns the amount added.
function PlayerState.AddCredits(player, amount: number): number
	local data = DataService.Get(player)
	amount = math.floor(amount)
	if not data or amount <= 0 then
		return 0
	end
	data.Credits = (data.Credits or 0) + amount
	player:SetAttribute("Credits", data.Credits)
	return amount
end

-- Spends credits if the player can afford it. Returns true on success.
function PlayerState.SpendCredits(player, cost: number): boolean
	local data = DataService.Get(player)
	if not data or (data.Credits or 0) < cost then
		return false
	end
	data.Credits -= cost
	player:SetAttribute("Credits", data.Credits)
	return true
end

function PlayerState.GetRoomReached(player): number
	local data = DataService.Get(player)
	return if data then data.RoomReached else 0
end

-- Records that the player cleared a room. Returns true if it is a new record.
function PlayerState.ReachRoom(player, room: number): boolean
	local data = DataService.Get(player)
	if not data or data.RoomReached >= room then
		return false
	end
	data.RoomReached = room
	PlayerState.Sync(player)
	return true
end

---------------------------------------------------------------------
-- Materials (inventory)
---------------------------------------------------------------------

-- Timed boosts: "Xp", "Damage", "Loot", "Credits" (os.time() they end).
function PlayerState.BoostActive(player, kind: string): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	return (data.Boosts[kind] or 0) > os.time()
end

function PlayerState.AddBoost(player, kind: string, minutes: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local now = os.time()
	data.Boosts[kind] = math.max(now, data.Boosts[kind] or 0) + minutes * 60
	PlayerState.Sync(player)
end

local function publishMaterials(player, data)
	player:SetAttribute("Materials", HttpService:JSONEncode(data.Materials))
end

function PlayerState.MaterialCount(player, materialId: string): number
	local data = DataService.Get(player)
	return if data then data.Materials[materialId] or 0 else 0
end

-- Adds (or removes, with a negative amount) a material. Returns the new count.
function PlayerState.AddMaterial(player, materialId: string, amount: number): number
	local data = DataService.Get(player)
	if not data or not Config.MaterialById[materialId] then
		return 0
	end
	local count = math.max(0, (data.Materials[materialId] or 0) + amount)
	data.Materials[materialId] = if count > 0 then count else nil
	publishMaterials(player, data)
	return count
end

-- True when the player owns every { materialId = count } of `cost`.
function PlayerState.HasMaterials(player, cost: { [string]: number }): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	for materialId, count in pairs(cost) do
		if (data.Materials[materialId] or 0) < count then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------

-- "Spark:2" -> pet def, tier (or nil).
function PlayerState.ParsePetKey(key: string)
	if type(key) ~= "string" then
		return nil, nil
	end
	local petId, tierText = string.match(key, "^(%w+):(%d)$")
	local pet = petId and Config.PetById[petId]
	local tier = tonumber(tierText)
	if not pet or not tier or not Config.PetTiers[tier] then
		return nil, nil
	end
	return pet, tier
end

function PlayerState.PetSlots(player): number
	return Config.PetSlots + (if Passes.Owns(player, "PetSlots") then Config.PetSlotsPass else 0)
end

-- Sum of the equipped pets' bonuses (shares): damage, max HP.
function PlayerState.PetBonus(player): (number, number)
	local data = DataService.Get(player)
	if not data then
		return 0, 0
	end
	local damage, health = 0, 0
	for _, key in ipairs(data.EquippedPets) do
		local pet, tier = PlayerState.ParsePetKey(key)
		if pet then
			local multiplier = Config.PetTiers[tier].Multiplier
			damage += (pet.Damage or 0) * multiplier
			health += (pet.Health or 0) * multiplier
		end
	end
	return damage, health
end

-- Adds one pet (tier 1). Returns false when the storage is full.
function PlayerState.GrantPet(player, petId: string): boolean
	local data = DataService.Get(player)
	if not data or not Config.PetById[petId] then
		return false
	end
	local total = 0
	for _, tiers in pairs(data.Pets) do
		for _, count in pairs(tiers) do
			total += count
		end
	end
	if total >= Config.PetStorage then
		return false
	end
	data.Pets[petId] = data.Pets[petId] or {}
	data.Pets[petId]["1"] = (data.Pets[petId]["1"] or 0) + 1
	data.PetIndex[petId] = true
	if #data.EquippedPets < PlayerState.PetSlots(player) then
		table.insert(data.EquippedPets, petId .. ":1")
	end
	return true
end

-- Pushes everything the client UI needs into Player attributes.
-- Call after any change to the data table.
function PlayerState.Sync(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Credits", data.Credits or 0)
	player:SetAttribute("RoomReached", data.RoomReached)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("Xp", data.Xp)
	player:SetAttribute("XpNext", Config.XpToNext(data.Level))
	player:SetAttribute("SkillPoints", data.SkillPoints or 0)
	for _, kind in ipairs(Config.BoostKinds) do
		player:SetAttribute("Boost" .. kind, data.Boosts[kind] or 0)
	end
	publishMaterials(player, data)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Level.Value = data.Level
		leaderstats.Room.Value = data.RoomReached
	end

	-- Shop state per category: "EquippedWeapon" = "IronSword",
	-- "OwnedWeapon" = "Stick,WoodSword,IronSword".
	for category, shop in pairs(Config.Shop) do
		local owned = {}
		for _, item in ipairs(shop.Items) do
			if data[shop.OwnedKey][item.Id] then
				table.insert(owned, item.Id)
			end
		end
		player:SetAttribute("Owned" .. category, table.concat(owned, ","))
		player:SetAttribute("Equipped" .. category, data[shop.EquippedKey] or "")
	end
	-- Armor: owned list, one attribute per slot, derived stats.
	local ownedArmor = {}
	for _, piece in ipairs(Config.Armor) do
		if data.OwnedArmor[piece.Id] then
			table.insert(ownedArmor, piece.Id)
		end
	end
	player:SetAttribute("OwnedArmor", table.concat(ownedArmor, ","))
	for _, slot in ipairs(Config.ArmorSlots) do
		local piece = PlayerState.ArmorIn(player, slot)
		player:SetAttribute("Equipped" .. slot, if piece then piece.Id else "")
	end
	local set = PlayerState.ActiveSet(player)
	player:SetAttribute("ArmorSet", if set then set.Id else "")
	-- Pets
	player:SetAttribute("Pets", HttpService:JSONEncode(data.Pets))
	player:SetAttribute("EquippedPets", table.concat(data.EquippedPets, ","))
	local index = {}
	for petId in pairs(data.PetIndex) do
		table.insert(index, petId)
	end
	player:SetAttribute("PetIndex", table.concat(index, ","))
	player:SetAttribute("PetSlots", PlayerState.PetSlots(player))
	if PlayerState.OnSynced then
		PlayerState.OnSynced(player) -- StatService recomputes every stat
	end
end

return PlayerState
