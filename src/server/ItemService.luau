--[[
	ItemService.luau
	The player's gear inventory (item instances, Shared.Items):
	give, equip / unequip, lock, salvage into Нано-ядра.

	Client: Items:InvokeServer(action, arg) -> ok, message
	  ("Equip", uid)            weapon of another class is refused
	  ("Unequip", slot)         armor only (a weapon is always held)
	  ("Lock", uid)             toggle the lock (locked items are never salvaged)
	  ("Salvage", { uid, ... }) chosen items -> cores
	  ("SalvageRarity", rarity) every unlocked, not worn item of that rarity
	                            and below -> cores
	Everything is checked here; the client only draws.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local T = Config.Items.Texts
local SLOTS = { "Weapon", "Helmet", "Chest", "Legs" }

local ItemService = {}

local rng = Random.new()
ItemService.Rng = rng

function ItemService.IsEquipped(data, uid: string): boolean
	for _, slot in ipairs(SLOTS) do
		if data.Equipped[slot] == uid then
			return true
		end
	end
	return false
end

function ItemService.HasRoom(player): boolean
	return PlayerState.ItemCount(player) < Config.Items.MaxInventory
end

-- Adds an instance to the inventory. Returns the view (or nil when full).
-- opts.Force = ignore the cap (store purchases, rewards);
-- opts.Equip = wear it at once when the slot allows.
function ItemService.Give(player, instance, opts)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	if not (opts and opts.Force) and not ItemService.HasRoom(player) then
		return nil
	end
	DataService.AddItem(data, instance)
	local view = Items.Resolve(instance)
	if opts and opts.Equip and view and Items.CanUse(view, PlayerState.ClassOf(player)) then
		data.Equipped[view.Slot] = instance.U
	end
	if not (opts and opts.NoSync) then
		PlayerState.Sync(player)
	end
	return view
end

-- A fresh drop for the player (class-aware).
function ItemService.Generate(player, level: number, rarityId: string, kind: string?)
	return Items.Generate(rng, { Level = level, Rarity = rarityId, Class = PlayerState.ClassOf(player), Kind = kind })
end

-- The best weapon the class can use is put in the hand when the current
-- one does not fit (class switch).
function ItemService.FitWeapon(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local classId = PlayerState.ClassOf(player)
	local current = data.Items[data.Equipped.Weapon or ""]
	local view = current and Items.Resolve(current)
	if view and Items.CanUse(view, classId) then
		return
	end
	local best
	for _, item in pairs(data.Items) do
		if item.K == "W" then
			local v = Items.Resolve(item)
			if v and Items.CanUse(v, classId) and (not best or v.Score > best.Score) then
				best = v
			end
		end
	end
	if best then
		data.Equipped.Weapon = best.Uid
		PlayerState.Sync(player)
	end
end

local function equip(player, data, uid)
	local item = data.Items[uid]
	local view = item and Items.Resolve(item)
	if not view then
		return false, "Нет такого предмета"
	end
	if not Items.CanUse(view, PlayerState.ClassOf(player)) then
		return false, T.WrongClass
	end
	data.Equipped[view.Slot] = uid
	PlayerState.Sync(player)
	return true, T.Equipped:format(view.Name)
end

local function unequip(player, data, slot)
	if slot == "Weapon" or not Config.ArmorSlotNames[slot] then
		return false, "Неверный запрос"
	end
	data.Equipped[slot] = ""
	PlayerState.Sync(player)
	return true, T.Unequipped:format(Config.ArmorSlotNames[slot])
end

local function lock(player, data, uid)
	local item = data.Items[uid]
	if not item then
		return false, "Нет такого предмета"
	end
	item.Lk = if item.Lk then nil else true
	PlayerState.Sync(player)
	return true, ""
end

local function canSalvage(data, item): boolean
	return item ~= nil and not item.Lk and not item.St and not ItemService.IsEquipped(data, item.U)
end
ItemService.CanSalvage = canSalvage

-- Salvages the listed uids (skipping worn / locked / starter). Returns count, cores.
function ItemService.Salvage(player, uids): (number, number)
	local data = DataService.Get(player)
	local count, cores = 0, 0
	if not data then
		return 0, 0
	end
	for _, uid in ipairs(uids) do
		local item = type(uid) == "string" and data.Items[uid]
		if item and canSalvage(data, item) then
			cores += Items.SalvageCores(item)
			data.Items[uid] = nil
			count += 1
		end
	end
	if count > 0 then
		data.Cores = (data.Cores or 0) + cores
		PlayerState.Sync(player)
	end
	return count, cores
end

local function salvageList(player, uids)
	if type(uids) ~= "table" or #uids > Config.Items.MaxInventory then
		return false, "Неверный запрос"
	end
	local count, cores = ItemService.Salvage(player, uids)
	if count == 0 then
		return false, T.NothingToSalvage
	end
	return true, T.Salvaged:format(count, Format.Number(cores))
end

local function salvageRarity(player, data, rarityId)
	local rarity = Config.Rarity[rarityId or ""]
	if not rarity then
		return false, "Неверный запрос"
	end
	local uids = {}
	for uid, item in pairs(data.Items) do
		if Config.Rarity[item.R].Index <= rarity.Index and (item.E or 0) == 0 then
			table.insert(uids, uid)
		end
	end
	return salvageList(player, uids)
end

function ItemService.Init()
	local allow = RateLimit.new(0.15)
	Remotes.Get("Items").OnServerInvoke = function(player, action, arg)
		local data = DataService.Get(player)
		if not allow(player) or not data or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Equip" and type(arg) == "string" then
			return equip(player, data, arg)
		elseif action == "Unequip" and type(arg) == "string" then
			return unequip(player, data, arg)
		elseif action == "Lock" and type(arg) == "string" then
			return lock(player, data, arg)
		elseif action == "Salvage" then
			return salvageList(player, arg)
		elseif action == "SalvageRarity" then
			return salvageRarity(player, data, arg)
		end
		return false, "Неверный запрос"
	end
end

return ItemService
