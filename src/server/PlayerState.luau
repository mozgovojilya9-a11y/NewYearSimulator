--[[
	PlayerState.luau
	The one place that knows how the economy works: how hard a player
	hits, what multiplies their Aura, and how Aura is added or spent.
	Every service goes through here instead of poking leaderstats or
	the data table directly, so balance changes live in one file.

	Aura lives in leaderstats.Aura (Main.server mirrors it into the save
	data). Everything else lives in the DataService table and is pushed
	to the client as Player attributes by PlayerState.Sync.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Passes = require(script.Parent.Passes)

local PlayerState = {}

local function auraValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Aura")
end

function PlayerState.IsReady(player): boolean
	return DataService.Get(player) ~= nil and auraValue(player) ~= nil
end

-- Damage of one click before crit: weapon base x AuraPower(Aura) x
-- rebirths (x armor set / pets / passes / boosts as those systems exist).
function PlayerState.Damage(player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	local weapon = Config.ItemById.Weapon[data.EquippedWeapon]
	local damage = Config.Click.BaseDamage * (if weapon then weapon.Damage else 1)
	damage *= Config.AuraPower(PlayerState.GetAura(player))
	damage *= Config.RebirthMultiplier(data.Rebirths)
	return math.max(1, math.floor(damage))
end
PlayerState.ClickPower = PlayerState.Damage

-- Aura changes on every click, and damage depends on it: keep the
-- "ClickPower" attribute (HUD, barrier hints) fresh.
function PlayerState.RefreshPower(player)
	local damage = PlayerState.Damage(player)
	if player:GetAttribute("ClickPower") ~= damage then
		player:SetAttribute("ClickPower", damage)
	end
end

-- Multiplier applied to every Aura gain (clicks, trainers, rewards).
function PlayerState.AuraMultiplier(player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	local pet = Config.ItemById.Pet[data.EquippedPet]
	local multiplier = if pet then 1 + pet.Bonus else 1
	multiplier *= Config.RebirthMultiplier(data.Rebirths)
	if (data.BoostUntil or 0) > os.time() then
		multiplier *= Config.Progression.Boost.Multiplier
	end
	if Passes.Owns(player, "VIP") then
		multiplier *= Config.VipAuraMultiplier
	end
	return multiplier
end

-- Rolls a crit on top of a base amount.
function PlayerState.RollCrit(amount: number): (number, boolean)
	if math.random() < Config.Click.CritChance then
		return amount * Config.Click.CritMultiplier, true
	end
	return amount, false
end

-- Adds Aura after applying the Aura multiplier. Returns what was added.
function PlayerState.GiveAura(player, baseAmount: number): number
	local aura = auraValue(player)
	if not aura then
		return 0
	end
	local amount = math.max(1, math.floor(baseAmount * PlayerState.AuraMultiplier(player)))
	aura.Value += amount
	return amount
end

function PlayerState.GetAura(player): number
	local aura = auraValue(player)
	return if aura then aura.Value else 0
end

function PlayerState.SetAura(player, amount: number)
	local aura = auraValue(player)
	if aura then
		aura.Value = amount
	end
end

-- Spends Aura if the player can afford it. Returns true on success.
function PlayerState.SpendAura(player, cost: number): boolean
	local aura = auraValue(player)
	if not aura or aura.Value < cost then
		return false
	end
	aura.Value -= cost
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

-- Multiplier for the chances of Rare+ drops (passes / boosts).
function PlayerState.LootLuck(player): number
	local luck = 1
	if Passes.Owns(player, "LootLuck") then
		luck *= 2
	end
	return luck
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

-- Gives a pet if the player doesn't own it yet. Returns true if given.
function PlayerState.GrantPet(player, petId: string): boolean
	local data = DataService.Get(player)
	if not data or data.OwnedPets[petId] or not Config.ItemById.Pet[petId] then
		return false
	end
	data.OwnedPets[petId] = true
	if data.EquippedPet == "" then
		data.EquippedPet = petId
	end
	PlayerState.Sync(player)
	return true
end

-- Pushes everything the client UI needs into Player attributes.
-- Call after any change to the data table that is not Aura.
function PlayerState.Sync(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("RoomReached", data.RoomReached)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("Xp", data.Xp)
	player:SetAttribute("XpNext", math.floor(Config.Progression.Level.XpBase * data.Level ^ 1.5))
	player:SetAttribute("BoostUntil", data.BoostUntil or 0)
	publishMaterials(player, data)
	local unlocked = {}
	for id in pairs(data.TrainersUnlocked) do
		table.insert(unlocked, id)
	end
	player:SetAttribute("TrainersUnlocked", table.concat(unlocked, ","))
	PlayerState.RefreshPower(player)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Rebirths.Value = data.Rebirths
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
	player:SetAttribute("AuraMultiplier", PlayerState.AuraMultiplier(player))
end

return PlayerState
