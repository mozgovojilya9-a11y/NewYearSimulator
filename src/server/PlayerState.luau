--[[
	PlayerState.luau
	The one place that knows how the economy works: how hard a player
	hits, what multiplies their Aura, and how currencies are added or
	spent. Every service goes through here instead of poking leaderstats
	or the data table directly, so balance changes live in one file.

	Aura lives in leaderstats.Aura (Main.server mirrors it into the save
	data). Everything else lives in the DataService table and is pushed
	to the client as Player attributes by PlayerState.Sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local PlayerState = {}

local function auraValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Aura")
end

function PlayerState.IsReady(player): boolean
	return DataService.Get(player) ~= nil and auraValue(player) ~= nil
end

-- Damage of one click before crit (mobs and trainers).
function PlayerState.ClickPower(player): number
	local data = DataService.Get(player)
	local weapon = data and Config.ItemById.Weapon[data.EquippedWeapon]
	local weaponDamage = if weapon then weapon.Damage else 1
	return Config.Click.BaseDamage * weaponDamage
end

-- Multiplier applied to every Aura gain (clicks, kills, passive income).
function PlayerState.AuraMultiplier(player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	local pet = Config.ItemById.Pet[data.EquippedPet]
	local petMultiplier = if pet then 1 + pet.Bonus else 1
	local boost = if (data.BoostUntil or 0) > os.time() then Config.Progression.Boost.Multiplier else 1
	return petMultiplier * Config.RebirthMultiplier(data.Rebirths) * boost
end

-- Passive Aura per second from the equipped backpack, before the
-- Aura multiplier (GiveAura applies it).
function PlayerState.BasePerSecond(player): number
	local data = DataService.Get(player)
	local backpack = data and Config.ItemById.Backpack[data.EquippedBackpack]
	return if backpack then backpack.PerSecond else 0
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
	local unlocked = {}
	for index in pairs(data.TrainersUnlocked) do
		table.insert(unlocked, index)
	end
	player:SetAttribute("TrainersUnlocked", table.concat(unlocked, ","))
	player:SetAttribute("ClickPower", PlayerState.ClickPower(player))

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
	player:SetAttribute(
		"AuraPerSecond",
		math.floor(PlayerState.BasePerSecond(player) * PlayerState.AuraMultiplier(player))
	)
end

return PlayerState

