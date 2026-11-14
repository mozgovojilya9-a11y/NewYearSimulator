--[[
	PetService.luau
	Pets:InvokeServer(action, ...) -> (ok, message, results?)
	  ("Hatch", eggId, triple)  pay the egg's Aura price (x3 with the
	                            "Open 3" pass) and roll pets by weight;
	                            results = { petId, ... } for the animation
	  ("Equip", "petId:tier")   up to PlayerState.PetSlots
	  ("Unequip", "petId:tier")
	  ("Merge", "petId:tier")   Config.PetMerge equal pets -> one of the
	                            next tier (equipped copies are unequipped)
	  ("EquipBest")             fills the slots with the strongest pets
	Everything is checked here; the client only draws the result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Passes = require(script.Parent.Passes)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local PetService = {}

local LUCK_FROM = Config.Rarity[Config.Hatch.LuckFrom].Index

local function countOf(data, petId: string, tier: number): number
	local tiers = data.Pets[petId]
	return if tiers then tiers[tostring(tier)] or 0 else 0
end

local function equippedCount(data, key: string): number
	local n = 0
	for _, k in ipairs(data.EquippedPets) do
		if k == key then
			n += 1
		end
	end
	return n
end

local function removeEquipped(data, key: string): boolean
	for i, k in ipairs(data.EquippedPets) do
		if k == key then
			table.remove(data.EquippedPets, i)
			return true
		end
	end
	return false
end

function PetService.Roll(player, egg)
	local luck = if Passes.Owns(player, "Luck") then 2 else 1
	local total = 0
	local weights = {}
	for i, entry in ipairs(egg.Pets) do
		local pet = Config.PetById[entry.Id]
		local weight = entry.Weight
		if pet and Config.Rarity[pet.Rarity].Index >= LUCK_FROM then
			weight *= luck
		end
		weights[i] = weight
		total += weight
	end
	local roll = math.random() * total
	for i, weight in ipairs(weights) do
		roll -= weight
		if roll <= 0 then
			return egg.Pets[i].Id
		end
	end
	return egg.Pets[#egg.Pets].Id
end

local function hatch(player, data, eggId, triple)
	local egg = Config.EggById[eggId]
	if not egg then
		return false, "Нет такого яйца"
	end
	local count = 1
	if triple == true then
		if not Passes.Owns(player, "TripleEgg") then
			return false, "Нужен пасс «Открытие 3 яиц»"
		end
		count = Config.Hatch.TripleCount
	end
	if not PlayerState.SpendAura(player, egg.Cost * count) then
		return false, "Не хватает Ауры"
	end
	local results = {}
	for _ = 1, count do
		local petId = PetService.Roll(player, egg)
		if PlayerState.GrantPet(player, petId) then
			table.insert(results, petId)
		end
	end
	local refunded = count - #results
	if refunded > 0 then -- storage full: the unhatched eggs are refunded
		PlayerState.SetAura(player, PlayerState.GetAura(player) + egg.Cost * refunded)
	end
	PlayerState.Sync(player)
	if #results == 0 then
		return false, "Хранилище питомцев заполнено"
	end
	return true, "Вылупилось!", results
end

local function equip(player, data, key)
	local pet, tier = PlayerState.ParsePetKey(key)
	if not pet then
		return false, "Неверный запрос"
	end
	if equippedCount(data, key) >= countOf(data, pet.Id, tier) then
		return false, "Нет свободного такого питомца"
	end
	if #data.EquippedPets >= PlayerState.PetSlots(player) then
		return false, ("Все слоты заняты (%d)"):format(PlayerState.PetSlots(player))
	end
	table.insert(data.EquippedPets, key)
	PlayerState.Sync(player)
	return true, "Питомец с тобой: " .. pet.Name
end

local function unequip(player, data, key)
	if not removeEquipped(data, key) then
		return false, "Этот питомец не надет"
	end
	PlayerState.Sync(player)
	return true, "Питомец отдыхает"
end

local function merge(player, data, key)
	local pet, tier = PlayerState.ParsePetKey(key)
	if not pet or tier >= #Config.PetTiers then
		return false, "Этого питомца уже нельзя улучшить"
	end
	local need = Config.PetMerge
	if countOf(data, pet.Id, tier) < need then
		return false, ("Нужно %d одинаковых"):format(need)
	end
	local tiers = data.Pets[pet.Id]
	tiers[tostring(tier)] -= need
	-- equipped copies that no longer exist are taken off
	while equippedCount(data, key) > tiers[tostring(tier)] do
		removeEquipped(data, key)
	end
	tiers[tostring(tier + 1)] = (tiers[tostring(tier + 1)] or 0) + 1
	if #data.EquippedPets < PlayerState.PetSlots(player) then
		table.insert(data.EquippedPets, pet.Id .. ":" .. (tier + 1))
	end
	PlayerState.Sync(player)
	return true, ("%s %s!"):format(Config.PetTiers[tier + 1].Name, pet.Name), { pet.Id .. ":" .. (tier + 1) }
end

local function equipBest(player, data)
	local all = {}
	for petId, tiers in pairs(data.Pets) do
		local pet = Config.PetById[petId]
		if pet then
			for tierText, count in pairs(tiers) do
				local tier = tonumber(tierText)
				for _ = 1, count do
					table.insert(all, { key = petId .. ":" .. tierText, power = pet.Bonus * Config.PetTiers[tier].Multiplier })
				end
			end
		end
	end
	table.sort(all, function(a, b)
		return a.power > b.power
	end)
	data.EquippedPets = {}
	for i = 1, math.min(#all, PlayerState.PetSlots(player)) do
		table.insert(data.EquippedPets, all[i].key)
	end
	PlayerState.Sync(player)
	return true, "Надеты лучшие питомцы"
end

function PetService.Init()
	local allow = RateLimit.new(0.25)
	Remotes.Get("Pets").OnServerInvoke = function(player, action, arg, extra)
		local data = DataService.Get(player)
		if not allow(player) or not data or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Hatch" then
			return hatch(player, data, arg, extra)
		elseif action == "Equip" then
			return equip(player, data, arg)
		elseif action == "Unequip" then
			return unequip(player, data, arg)
		elseif action == "Merge" then
			return merge(player, data, arg)
		elseif action == "EquipBest" then
			return equipBest(player, data)
		end
		return false, "Неверный запрос"
	end
end

return PetService
