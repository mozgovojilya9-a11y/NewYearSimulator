--[[
	PlayerState.luau
	Access to the player's state: credits, level, materials, armor,
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
-- Class and skills (each class keeps its own tree progress)
---------------------------------------------------------------------

function PlayerState.ClassOf(player): string
	local data = DataService.Get(player)
	local id = data and data.Class or ""
	return if Config.ClassById[id] then id else ""
end

-- The record of a class in the save (created on demand).
function PlayerState.ClassRecord(data, classId: string)
	data.Classes = if type(data.Classes) == "table" then data.Classes else {}
	local record = data.Classes[classId]
	if type(record) ~= "table" then
		record = {}
		data.Classes[classId] = record
	end
	record.Skills = if type(record.Skills) == "table" then record.Skills else {}
	record.Loadout = if type(record.Loadout) == "table" then record.Loadout else {}
	record.Resets = if type(record.Resets) == "number" then record.Resets else 0
	return record
end

function PlayerState.SpentPoints(record): number
	local spent = 0
	for nodeId, rank in pairs(record.Skills) do
		if Config.SkillById[nodeId] and type(rank) == "number" then
			spent += rank
		end
	end
	return spent
end

-- [nodeId] = rank of the player's current class ({} without a class).
function PlayerState.SkillRanks(player)
	local data = DataService.Get(player)
	local classId = PlayerState.ClassOf(player)
	if not data or classId == "" then
		return {}
	end
	return PlayerState.ClassRecord(data, classId).Skills
end

function PlayerState.FreePoints(player): number
	local data = DataService.Get(player)
	local classId = PlayerState.ClassOf(player)
	if not data or classId == "" then
		return 0
	end
	return math.max(0, Config.Skills.PointsAtLevel(data.Level) - PlayerState.SpentPoints(PlayerState.ClassRecord(data, classId)))
end

local function publishSkills(player, data)
	local classId = PlayerState.ClassOf(player)
	player:SetAttribute("Class", classId)
	player:SetAttribute("SkillPoints", PlayerState.FreePoints(player))
	local state = { Class = classId, Classes = {} }
	for _, class in ipairs(Config.Classes) do
		local record = PlayerState.ClassRecord(data, class.Id)
		state.Classes[class.Id] = { Skills = record.Skills, Loadout = record.Loadout, Resets = record.Resets, Spent = PlayerState.SpentPoints(record) }
	end
	player:SetAttribute("SkillState", HttpService:JSONEncode(state))
	local loadout = {}
	if classId ~= "" then
		local record = PlayerState.ClassRecord(data, classId)
		for _, slot in ipairs(Config.Skills.Slots) do
			local node = Config.SkillById[record.Loadout[slot] or ""]
			if node and (record.Skills[node.Id] or 0) > 0 then
				loadout[slot] = { Id = node.Id, Icon = node.Icon, Name = node.Name }
			end
		end
	end
	player:SetAttribute("Loadout", HttpService:JSONEncode(loadout))
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
	publishSkills(player, data)
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
	if PlayerState.OnSynced then
		PlayerState.OnSynced(player) -- StatService recomputes every stat
	end
end

return PlayerState
