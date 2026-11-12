--[[
	ShopService.luau
	Buying and equipping items from any Config.Shop category
	(weapons are equip-only: they are crafted; pets are paid with Aura).

	Client calls ShopRequest:InvokeServer(action, category, id) where
	action is "Buy" or "Equip". Returns (ok: boolean, message: string).
	Prices and ownership are checked here, never on the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local ShopService = {}


-- Armor: ("Equip", "Armor", armorId) or ("Unequip", "Armor", slot).
function ShopService.HandleArmor(player, action, id)
	local data = DataService.Get(player)
	if not data or not PlayerState.IsReady(player) then
		return false, "Неверный запрос"
	end
	if action == "Equip" then
		local piece = Config.ItemById.Armor[id]
		if not piece or not data.OwnedArmor[id] then
			return false, "Сначала выкуй в Кузнице"
		end
		data.EquippedArmor[piece.Slot] = id
		PlayerState.Sync(player)
		return true, "Надето: " .. piece.Name
	elseif action == "Unequip" then
		if not Config.ArmorSlotNames[id] then
			return false, "Неверный запрос"
		end
		data.EquippedArmor[id] = ""
		PlayerState.Sync(player)
		return true, "Снято: " .. Config.ArmorSlotNames[id]
	end
	return false, "Неверный запрос"
end

function ShopService.Handle(player, action, category, id)
	if type(action) ~= "string" or type(category) ~= "string" or type(id) ~= "string" then
		return false, "Неверный запрос"
	end
	if category == "Armor" then
		return ShopService.HandleArmor(player, action, id)
	end
	local shop = Config.Shop[category]
	local item = shop and Config.ItemById[category][id]
	local data = DataService.Get(player)
	if not item or not data or not PlayerState.IsReady(player) then
		return false, "Неверный запрос"
	end

	local owned = data[shop.OwnedKey]

	if action == "Buy" then
		if shop.Purchasable == false then
			return false, "Оружие куётся в Кузнице" -- weapons are crafted, never bought
		end
		if owned[id] then
			return false, "Уже куплено"
		end
		if item.Cost > 0 and not PlayerState.SpendAura(player, item.Cost) then
			return false, "Не хватает Ауры"
		end
		owned[id] = true
		data[shop.EquippedKey] = id -- buying equips right away
		PlayerState.Sync(player)
		return true, "Куплено: " .. item.Name
	elseif action == "Equip" then
		if not owned[id] then
			return false, if category == "Weapon" then "Сначала выкуй в Кузнице" else "Сначала получи"
		end
		data[shop.EquippedKey] = id
		PlayerState.Sync(player)
		return true, "Надето: " .. item.Name
	end

	return false, "Неверный запрос"
end

function ShopService.Init()
	local remote = Remotes.Get("ShopRequest")
	local allow = RateLimit.new(0.2)

	remote.OnServerInvoke = function(player, action, category, id)
		if not allow(player) then
			return false, "Слишком быстро"
		end
		return ShopService.Handle(player, action, category, id)
	end
end

return ShopService
