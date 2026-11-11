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

-- Damage of one click before crit. Used both for the click button and
-- for hitting mobs.
function PlayerState.ClickPower(_player): number
	return Config.Click.BaseDamage
end

-- Multiplier applied to every Aura gain (clicks, kills, passive income).
function PlayerState.AuraMultiplier(_player): number
	return 1
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
	return aura and aura.Value or 0
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

function PlayerState.AddGems(player, amount: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.Gems += amount
	player:SetAttribute("Gems", data.Gems)
end

function PlayerState.SpendGems(player, cost: number): boolean
	local data = DataService.Get(player)
	if not data or data.Gems < cost then
		return false
	end
	data.Gems -= cost
	player:SetAttribute("Gems", data.Gems)
	return true
end

-- Pushes everything the client UI needs into Player attributes.
-- Call after any change to the data table that is not Aura.
function PlayerState.Sync(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Gems", data.Gems)
	player:SetAttribute("ClickPower", PlayerState.ClickPower(player))
	player:SetAttribute("AuraMultiplier", PlayerState.AuraMultiplier(player))
end

return PlayerState
