--[[
	StatService.luau
	The ONE place that turns everything a player has into final numbers.
	Sources: level, weapon and armor (item instances with enhance and
	bonus props), armor set bonus, skill tree passives of the current
	class, artifacts, stat points ("Статус"), game passes, boosts.

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
	  GearScore    sum of item scores: weapon + 3 armor slots
	  DropChance   + chance that a mob drops an item (Восприятие)
	  XpMult       x XP earned (passes, VIP, boosts)
	  CreditsMult  x Нано-кредиты earned (passes, VIP, boosts)

	Damage = BaseDamage x weapon Damage x LevelMult(level) x set bonus
	         x passes x boosts (x skills / class later).

	Every system reads stats ONLY through StatService.Get(player).
	Stats are recomputed on every change (PlayerState.Sync: gear, level,
	pass bought, boost started / ended) and pushed to the client as
	attributes: the old names (ClickPower, MaxHealth, Defense) plus
	"Stat_<Name>" for every stat and a JSON "Stats".
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

-- Combat stats that only skills give (used by AbilityService / MobAI).
StatService.CombatStats = { "Lifesteal", "Thorns", "ComboBonus", "BlockBonus", "SlowOnHit", "StunOnHit", "ControlPct", "AbilityPct", "CooldownPct", "LowHpDamage", "CheatDeath", "DashPower", "ChargeBonus", "VolleyBonus", "CheatDeathHaste" }
local published = {} -- [player] = { [attribute] = value }

-- Extra stat sources: function(player, data) -> { [stat] = value } (same
-- names as skill passives: DamagePct, HealthPct, Health, Defense,
-- CritChance, CritDamage, AttackSpeed, Regen, Luck, DropChance + combat
-- stats). ArtifactService and StatusService register here.
StatService.Sources = {}

-- Pure computation from the save data.
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
		GearScore = 0,
		DropChance = 0,
		XpMult = 1,
		CreditsMult = 1,
	}
	-- combat stats of skill passives (0 = none)
	for _, name in ipairs(StatService.CombatStats) do
		stats[name] = 0
	end
	if not data then
		return stats
	end

	-- Level
	local level = data.Level or 1
	stats.MaxHealth += (level - 1) * base.HealthPerLevel
	stats.Defense += (level - 1) * base.DefensePerLevel

	-- Gear: weapon + armor pieces (item instances), their bonus props, set bonus
	local gear = {} -- sums of bonus props
	local weapon = PlayerState.Weapon(player)
	local weaponDamage = if weapon then weapon.Damage else 1
	local function wear(view)
		stats.GearScore += view.Score
		for _, prop in ipairs(view.Props) do
			gear[prop.S] = (gear[prop.S] or 0) + prop.V
		end
	end
	if weapon then
		wear(weapon)
	end
	for _, slot in ipairs(Config.ArmorSlots) do
		local piece = PlayerState.ArmorIn(player, slot)
		if piece then
			stats.MaxHealth += piece.Health
			stats.Defense += piece.Defense
			wear(piece)
		end
	end
	-- set bonuses: 2 pieces of one set -> Set2, all 3 -> Set2 + Set3
	local damageMult = 1
	local setBonus = {}
	local counts = {}
	for _, slot in ipairs(Config.ArmorSlots) do
		local piece = PlayerState.ArmorIn(player, slot)
		if piece and piece.Set then
			counts[piece.Set] = (counts[piece.Set] or 0) + 1
		end
	end
	for setId, n in pairs(counts) do
		local def = Config.ArmorSets[setId]
		if def then
			for stat, v in pairs(if n >= 2 then def.Set2 or {} else {}) do
				setBonus[stat] = (setBonus[stat] or 0) + v
			end
			for stat, v in pairs(if n >= 3 then def.Set3 or {} else {}) do
				setBonus[stat] = (setBonus[stat] or 0) + v
			end
		end
	end
	-- Возвышение points
	local asc = {}
	if type(data.Ascension) == "table" and type(data.Ascension.Spent) == "table" then
		for _, line in ipairs(Config.Ascension.Lines) do
			local n = data.Ascension.Spent[line.Id] or 0
			if n > 0 then
				asc[line.Stat] = (asc[line.Stat] or 0) + n * line.Per
			end
		end
	end

	-- Skill tree passives of the current class
	local skill = {}
	for nodeId, rank in pairs(PlayerState.SkillRanks(player)) do
		local node = Config.SkillById[nodeId]
		if node and node.Stats and type(rank) == "number" and rank > 0 then
			for stat, list in pairs(node.Stats) do
				skill[stat] = (skill[stat] or 0) + Config.RankValue(list, rank)
			end
		end
	end
	-- every extra source (gear props, artifacts, stat points) adds into `bonus`
	local bonus = {}
	local function add(source)
		for stat, value in pairs(source) do
			bonus[stat] = (bonus[stat] or 0) + value
		end
	end
	add(skill)
	add(gear)
	add(setBonus)
	add(asc)
	for _, source in ipairs(StatService.Sources) do
		add(source(player, data) or {})
	end
	damageMult *= 1 + (bonus.DamagePct or 0)
	stats.MaxHealth = math.floor((stats.MaxHealth + (bonus.Health or 0)) * (1 + (bonus.HealthPct or 0)))
	stats.Defense = math.min(0.8, stats.Defense + (bonus.Defense or 0))
	stats.CritChance = math.min(0.75, stats.CritChance + (bonus.CritChance or 0))
	stats.CritDamage += bonus.CritDamage or 0
	stats.AttackSpeed += bonus.AttackSpeed or 0
	stats.Regen += bonus.Regen or 0
	stats.Dash += bonus.Dash or 0
	stats.Luck += bonus.Luck or 0
	stats.DropChance = bonus.DropChance or 0
	for _, name in ipairs(StatService.CombatStats) do
		stats[name] = bonus[name] or 0
	end

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

	-- XP and credits multipliers
	local vip = if Passes.Owns(player, "VIP") then 1 + Config.VipBonus else 1
	stats.XpMult = vip * (if Passes.Owns(player, "Xp2x") then 2 else 1) * (if PlayerState.BoostActive(player, "Xp") then 2 else 1) * (1 + (bonus.XpPct or 0))
	stats.CreditsMult = vip * (if Passes.Owns(player, "Credits2x") then 2 else 1) * (if PlayerState.BoostActive(player, "Credits") then 2 else 1)

	-- Damage = weapon x level x bonuses
	local damage = Config.Click.BaseDamage * weaponDamage * Config.LevelMult(level) * damageMult
	stats.Damage = math.max(1, math.floor(damage))

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
	-- Every Sync (gear, level, boosts) refreshes stats.
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
