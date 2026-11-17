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
local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)

local PlayerState = {}

PlayerState.OnSynced = nil -- set by StatService: recompute stats after every Sync

function PlayerState.IsReady(player): boolean
	return DataService.Get(player) ~= nil and player:FindFirstChild("leaderstats") ~= nil
end

---------------------------------------------------------------------
-- Armor
---------------------------------------------------------------------

-- The equipped item of a slot ("Weapon" / "Helmet" / "Chest" / "Legs")
-- as an Items view with final numbers (or nil).
function PlayerState.EquippedIn(player, slot: string)
	local data = DataService.Get(player)
	local item = data and data.Items[data.Equipped[slot] or ""]
	return if item then Items.Resolve(item) else nil
end

function PlayerState.Weapon(player)
	return PlayerState.EquippedIn(player, "Weapon")
end

-- The equipped armor piece in a slot (or nil).
function PlayerState.ArmorIn(player, slot: string)
	return PlayerState.EquippedIn(player, slot)
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
-- Boosts
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

---------------------------------------------------------------------
-- Нано-ядра (from salvaged items, spent in the forge)
---------------------------------------------------------------------

function PlayerState.GetCores(player): number
	local data = DataService.Get(player)
	return if data then data.Cores or 0 else 0
end

function PlayerState.AddCores(player, amount: number): number
	local data = DataService.Get(player)
	amount = math.floor(amount)
	if not data or amount <= 0 then
		return 0
	end
	data.Cores = (data.Cores or 0) + amount
	player:SetAttribute("Cores", data.Cores)
	return amount
end

function PlayerState.SpendCores(player, cost: number): boolean
	local data = DataService.Get(player)
	if not data or (data.Cores or 0) < cost then
		return false
	end
	data.Cores -= cost
	player:SetAttribute("Cores", data.Cores)
	return true
end

---------------------------------------------------------------------
-- Items (gear instances: Shared.Items)
---------------------------------------------------------------------

function PlayerState.ItemCount(player): number
	local data = DataService.Get(player)
	local n = 0
	if data then
		for _ in pairs(data.Items) do
			n += 1
		end
	end
	return n
end

-- "Items" = JSON array of instances, "Equipped" = JSON { slot = uid }; the
-- look attributes (base id, rarity, enhance per slot) drive the character.
local function publishItems(player, data)
	local list = {}
	for _, item in pairs(data.Items) do
		table.insert(list, item)
	end
	player:SetAttribute("Items", HttpService:JSONEncode(list))
	player:SetAttribute("Equipped", HttpService:JSONEncode(data.Equipped))
	player:SetAttribute("Cores", data.Cores or 0)
	for _, slot in ipairs({ "Weapon", "Helmet", "Chest", "Legs" }) do
		local item = data.Items[data.Equipped[slot] or ""]
		player:SetAttribute("Equipped" .. slot, if item then item.B else "")
		player:SetAttribute("Look" .. slot, if item then ("%s|%d|%s"):format(item.R, item.E or 0, item.C or "") else "")
	end
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
	publishItems(player, data)
	player:SetAttribute("Artifacts", HttpService:JSONEncode({ Owned = data.Artifacts, Slots = data.ArtifactSlots }))
	player:SetAttribute("Attributes", HttpService:JSONEncode(data.Attributes))
	local spentStats = 0
	for _, value in pairs(data.Attributes) do
		spentStats += value
	end
	player:SetAttribute("StatPoints", math.max(0, Config.StatPointsAtLevel(data.Level) - spentStats))

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Level.Value = data.Level
		leaderstats.Room.Value = data.RoomReached
	end

	local set = PlayerState.ActiveSet(player)
	player:SetAttribute("ArmorSet", if set then set.Id else "")
	if PlayerState.OnSynced then
		PlayerState.OnSynced(player) -- StatService recomputes every stat
	end
end

return PlayerState
