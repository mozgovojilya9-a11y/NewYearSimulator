--[[
	StatService.luau
	The ONE place that turns everything a player has into final numbers.
	Sources: level, weapon, armor pieces, armor set bonus, pets, rebirths,
	game passes, boosts (class and skills will plug in here later).

	Stats (all final, ready to use):
	  Damage       one hit before crit
	  MaxHealth    max HP
	  Defense      share of incoming damage removed (0..0.8)
	  AttackSpeed  x click rate
	  CritChance   0..1
	  CritDamage   crit hit = Damage x this
	  Luck         x chances of Rare+ drops
	  Regen        HP per second out of combat
	  Dash         dash distance (studs)
	  TrainingMult x training from gear (weapon x armor pieces)
	  AuraMultiplier  everything that multiplies training except the level
	  AuraGain     Aura of one training tick on a x1 trainer

	Every system reads stats ONLY through StatService.Get(player).
	Stats are recomputed on every change (PlayerState.Sync, Aura change,
	pass bought, boost started / ended) and pushed to the client as
	attributes: the old names (ClickPower, MaxHealth, Defense,
	AuraMultiplier) plus "Stat_<Name>" for every stat and a JSON "Stats".
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Passes = require(script.Parent.Passes)
local PlayerState = require(script.Parent.PlayerState)

local StatService = {}

local cache = {} -- [player] = stats table
local published = {} -- [player] = { [attribute] = value }

local function auraOf(player): number
	return PlayerState.GetAura(player)
end

-- Pure computation from the save data + the current Aura.
local function compute(player)
	local data = DataService.Get(player)
	local base = Config.Stats
	local stats = {
		Damage = 1,
		MaxHealth = Config.Player.Health,
		Defense = 0,
		AttackSpeed = base.AttackSpeed,
		CritChance = base.CritChance,
		CritDamage = base.CritDamage,
		Luck = base.Luck,
		Regen = base.Regen,
		Dash = base.Dash,
		TrainingMult = 1,
		AuraMultiplier = 1,
		AuraGain = 1,
	}
	if not data then
		return stats
	end

	-- Level
	local level = data.Level or 1
	stats.MaxHealth += (level - 1) * base.HealthPerLevel

	-- Weapon
	local weapon = Config.ItemById.Weapon[data.EquippedWeapon]
	local weaponDamage = if weapon then weapon.Damage else 1
	if weapon then
		stats.TrainingMult *= weapon.TrainingMult or 1
	end

	-- Armor pieces + set bonus
	for _, slot in ipairs(Config.ArmorSlots) do
		local piece = PlayerState.ArmorIn(player, slot)
		if piece then
			stats.MaxHealth += piece.Health
			stats.Defense += piece.Defense
			stats.TrainingMult *= piece.TrainingMult or 1
		end
	end
	stats.Defense = math.min(0.8, stats.Defense)
	local set = PlayerState.ActiveSet(player)
	local damageMult = 1
	if set then
		damageMult *= 1 + set.Bonus
	end

	-- Pets
	local petAura, petDamage = PlayerState.PetBonus(player)
	damageMult *= 1 + petDamage

	-- Passes and boosts
	if Passes.Owns(player, "Damage2x") then
		damageMult *= 2
	end
	if PlayerState.BoostActive(player, "Damage") then
		damageMult *= 2
	end
	if Passes.Owns(player, "LootLuck") then
		stats.Luck *= 2
	end
	if PlayerState.BoostActive(player, "Loot") then
		stats.Luck *= 2
	end

	-- Damage = weapon x PowerMult(Aura) x bonuses
	local damage = Config.Click.BaseDamage * weaponDamage * Config.PowerMult(auraOf(player)) * damageMult
	stats.Damage = math.max(1, math.floor(damage))

	-- Training: everything except the level-based BaseAura
	local auraMult = stats.TrainingMult * (1 + petAura) * Config.RebirthMultiplier(data.Rebirths)
	if PlayerState.BoostActive(player, "Aura") then
		auraMult *= Config.Progression.Boost.Multiplier
	end
	if Passes.Owns(player, "VIP") then
		auraMult *= Config.VipAuraMultiplier
	end
	if Passes.Owns(player, "Aura2x") then
		auraMult *= 2
	end
	stats.AuraMultiplier = auraMult
	stats.AuraGain = Config.Aura.TrainerTickBase * Config.BaseAura(level) * auraMult

	return stats
end

local function round(value: number, digits: number): number
	local m = 10 ^ digits
	return math.floor(value * m + 0.5) / m
end

local function set(player, attribute: string, value)
	local mine = published[player]
	if mine[attribute] ~= value then
		mine[attribute] = value
		player:SetAttribute(attribute, value)
	end
end

local function publish(player, stats)
	published[player] = published[player] or {}
	-- Old attribute names (HUD and windows read them).
	set(player, "ClickPower", stats.Damage)
	set(player, "MaxHealth", stats.MaxHealth)
	set(player, "Defense", round(stats.Defense, 3))
	set(player, "AuraMultiplier", round(stats.AuraMultiplier, 2))
	for name, value in pairs(stats) do
		set(player, "Stat_" .. name, if math.floor(value) == value then value else round(value, 3))
	end
	local rounded = {}
	for name, value in pairs(stats) do
		rounded[name] = round(value, 3)
	end
	set(player, "Stats", HttpService:JSONEncode(rounded))
end

-- Recomputes and publishes. Call after anything that changes stats.
function StatService.Refresh(player)
	if not player.Parent then
		return
	end
	local stats = compute(player)
	cache[player] = stats
	publish(player, stats)
	return stats
end

-- Final stats (computed on demand if missing).
function StatService.Get(player)
	return cache[player] or StatService.Refresh(player) or compute(player)
end

-- Damage of one hit with a crit roll. Returns damage, isCrit.
function StatService.RollHit(player): (number, boolean)
	local stats = StatService.Get(player)
	if math.random() < stats.CritChance then
		return math.floor(stats.Damage * stats.CritDamage), true
	end
	return stats.Damage, false
end

-- Seconds a player must wait between accepted clicks.
function StatService.ClickCooldown(player): number
	return Config.Click.Cooldown / math.max(0.1, StatService.Get(player).AttackSpeed)
end

function StatService.Init()
	-- Every Sync (gear, pets, level, rebirth, boosts) refreshes stats.
	PlayerState.OnSynced = StatService.Refresh
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
		published[player] = nil
	end)
	-- Boosts end on their own: re-check every few seconds.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerState.IsReady(player) then
					StatService.Refresh(player)
				end
			end
		end
	end)
end

return StatService
