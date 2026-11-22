--[[
	MarketService.luau
	Чёрный рынок (Config.Market): personal offers for credits that change
	every RefreshSeconds. The offers of a window are built once per player
	(item instances are rolled then, so what is shown is what is bought);
	bought slots are remembered in data.Market { W = window, B = { [slot] = true } }.

	Market:InvokeServer("List")       -> ok, { Offers = {...}, EndsIn = seconds }
	Market:InvokeServer("Buy", slot)  -> ok, message
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local M = Config.Market
local T = M.Texts

local MarketService = {}

local cache = {} -- [player] = { window, offers }

local function windowNow(): number
	return os.time() // M.RefreshSeconds
end

-- the best rarity the player's gate rank can drop (from any enemy)
local function rarityCap(rank: string): number
	local best = 1
	local tables = Config.Loot.Tables[rank]
	if tables then
		for _, weights in pairs(tables) do
			for id, w in pairs(weights) do
				local r = Config.Rarity[id]
				if r and w > 0 then
					best = math.max(best, r.Index)
				end
			end
		end
	end
	return best
end

local function build(player, data, window)
	local rng = Random.new(window * 7919 + player.UserId % 100000)
	local room = math.max(1, data.RoomReached or 1)
	local unit = Config.KillCredits(room, false)
	local rank = Config.RankForRoom(room)
	local cap = rarityCap(rank)
	local offers = {}
	for slot, def in ipairs(M.Slots) do
		if def.Chance and rng:NextNumber() > def.Chance then
			continue
		end
		local offer = { Slot = slot, Kind = def.Kind, Price = math.max(10, math.floor(unit * def.Price)) }
		if def.Kind == "Item" then
			local rarity = Config.Rarity[def.Rarity]
			if rarity.Index > cap then
				rarity = Config.Rarities[cap]
			end
			local kinds = { "W", "W", "A", "A", "A" } -- weapon or armor
			local instance = ItemService.Generate(player, data.Level or 1, rarity.Id, kinds[rng:NextInteger(1, #kinds)])
			local view = instance and Items.Resolve(instance)
			if not view then
				continue
			end
			offer.Instance = instance
			offer.Name = view.Name
			offer.Rarity = rarity.Id
			offer.Level = view.ItemLevel
			offer.Slot2 = view.Slot
		elseif def.Kind == "Cores" then
			offer.Amount = def.Amount
			offer.Name = T.Cores:format(def.Amount)
		elseif def.Kind == "Boost" then
			offer.Minutes = def.Minutes
			offer.Boost = def.Boost
			offer.Name = T.Boost:format(def.Minutes)
		elseif def.Kind == "Crystals" then
			offer.Amount = def.Amount
			offer.Name = T.Crystals:format(def.Amount)
		end
		table.insert(offers, offer)
	end
	return offers
end

local function offersFor(player, data)
	local window = windowNow()
	local c = cache[player]
	if not c or c.window ~= window then
		c = { window = window, offers = build(player, data, window) }
		cache[player] = c
	end
	data.Market = if type(data.Market) == "table" and data.Market.W == window then data.Market else { W = window, B = {} }
	return c.offers, data.Market
end

local function list(player, data)
	local offers, state = offersFor(player, data)
	local out = {}
	for _, o in ipairs(offers) do
		table.insert(out, {
			Slot = o.Slot,
			Kind = o.Kind,
			Name = o.Name,
			Rarity = o.Rarity,
			Level = o.Level,
			ItemSlot = o.Slot2,
			Price = o.Price,
			Bought = state.B[tostring(o.Slot)] == true,
		})
	end
	return { Offers = out, EndsIn = M.RefreshSeconds - os.time() % M.RefreshSeconds }
end

local function buy(player, data, slot)
	local offers, state = offersFor(player, data)
	local offer
	for _, o in ipairs(offers) do
		if o.Slot == tonumber(slot) then
			offer = o
		end
	end
	if not offer or state.B[tostring(offer.Slot)] then
		return false, "Неверный запрос"
	end
	if offer.Kind == "Item" and not ItemService.HasRoom(player) then
		return false, T.Full
	end
	if not PlayerState.SpendCredits(player, offer.Price) then
		return false, T.NoCredits
	end
	state.B[tostring(offer.Slot)] = true
	if offer.Kind == "Item" then
		ItemService.Give(player, offer.Instance, { Force = true })
	elseif offer.Kind == "Cores" then
		PlayerState.AddCores(player, offer.Amount)
	elseif offer.Kind == "Boost" then
		PlayerState.AddBoost(player, offer.Boost, offer.Minutes)
	elseif offer.Kind == "Crystals" then
		PlayerState.AddCrystals(player, offer.Amount)
	end
	PlayerState.Sync(player)
	return true, T.Done:format(offer.Name)
end

function MarketService.Init()
	local allow = RateLimit.new(0.3)
	Remotes.Get("Market").OnServerInvoke = function(player, action, arg)
		local data = DataService.Get(player)
		if not allow(player) or not data or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "List" then
			return true, list(player, data)
		elseif action == "Buy" then
			return buy(player, data, arg)
		end
		return false, "Неверный запрос"
	end
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return MarketService
