--[[
	ShopService.luau
	Day 4: buying and equipping items from any Config.Shop category
	(weapons now; backpacks and pets plug into the same code).

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

local CURRENCY_NAME = { Aura = "Ауры", Gems = "💎" }

local function spend(player, currency, cost): boolean
	if cost <= 0 then
		return true
	end
	if currency == "Gems" then
		return PlayerState.SpendGems(player, cost)
	end
	return PlayerState.SpendAura(player, cost)
end

local function handle(player, action, category, id)
	if type(action) ~= "string" or type(category) ~= "string" or type(id) ~= "string" then
		return false, "Неверный запрос"
	end
	local shop = Config.Shop[category]
	local item = shop and Config.ItemById[category][id]
	local data = DataService.Get(player)
	if not item or not data or not PlayerState.IsReady(player) then
		return false, "Неверный запрос"
	end

	local owned = data[shop.OwnedKey]

	if action == "Buy" then
		if owned[id] then
			return false, "Уже куплено"
		end
		if not spend(player, shop.Currency, item.Cost) then
			return false, "Не хватает " .. CURRENCY_NAME[shop.Currency]
		end
		owned[id] = true
		data[shop.EquippedKey] = id -- buying equips right away
		PlayerState.Sync(player)
		return true, "Куплено: " .. item.Name
	elseif action == "Equip" then
		if not owned[id] then
			return false, "Сначала купи"
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
		return handle(player, action, category, id)
	end
end

return ShopService
