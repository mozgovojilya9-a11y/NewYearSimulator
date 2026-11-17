--[[
	Items.luau
	Gear as item INSTANCES (shared by the server and the client UI).

	Saved instance (short keys keep the save and the attribute small):
	  U  uid ("i12")            B  base id (Config.Weapons / Config.Armor)
	  K  "W" weapon | "A" armor R  rarity id
	  L  item level             Q  roll of the main stat (around 1)
	  E  enhance level (0..15)  P  bonus props { { S = statId, V = value }, ... }
	  Lk locked (true)          F  failed enhances in a row (pity)
	  C  "Any" = usable by every class (starter, gear from old saves)
	  St starter item (can't be salvaged)

	Items.Resolve(instance) -> a view with final numbers that also reads
	like the base (Id, Shape, Color, Class, Slot, Set...), so the weapon /
	armor builders and the UI take it directly:
	  Uid, Kind ("Weapon" | "Armor"), Name, Rarity, ItemLevel, Enhance,
	  Damage | Health + Defense, Props, Locked, Score, Class, Slot, Inst
	All formulas: Config.Items / Config.Forge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local I = Config.Items
local F = Config.Forge

local Items = {}

function Items.Base(instance)
	if type(instance) ~= "table" then
		return nil
	end
	if instance.K == "W" then
		return Config.ItemById.Weapon[instance.B]
	end
	return Config.ItemById.Armor[instance.B]
end

function Items.EnhanceMult(enhance: number?): number
	return 1 + F.PerLevel * (enhance or 0)
end

-- Main stats of an item level / rarity / roll before the enhance.
function Items.WeaponDamage(level: number, rarityId: string, roll: number): number
	return I.Weapon.Base * I.Weapon.Growth ^ level * (I.RarityMult[rarityId] or 1) * roll
end

function Items.ArmorHealth(level: number, rarityId: string, roll: number, slot: string): number
	local a = I.Armor
	return (a.HealthBase + a.HealthPerLevel * level) * (I.RarityMult[rarityId] or 1) * roll * (if slot == "Chest" then a.ChestMult else 1)
end

function Items.ArmorDefense(level: number): number
	return I.Armor.DefenseBase + I.Armor.DefensePerLevel * level
end

function Items.Score(instance): number
	return math.floor((instance.L or 1) * (I.ScoreRarity[instance.R] or 1) + I.ScorePerEnhance * (instance.E or 0) + 0.5)
end

local viewMeta = {}

function Items.Resolve(instance)
	local base = Items.Base(instance)
	if not base then
		return nil
	end
	local enhance = instance.E or 0
	local mult = Items.EnhanceMult(enhance)
	local level = instance.L or 1
	local roll = instance.Q or 1
	local view = {
		Inst = instance,
		Uid = instance.U,
		Kind = if instance.K == "W" then "Weapon" else "Armor",
		Name = base.Name .. (if enhance > 0 then " +" .. enhance else ""),
		BaseName = base.Name,
		Rarity = instance.R,
		ItemLevel = level,
		Enhance = enhance,
		Props = instance.P or {},
		Locked = instance.Lk == true,
		Starter = instance.St == true,
		Score = Items.Score(instance),
		Glow = enhance >= F.GlowFrom, -- builders add the +10 glow
	}
	if instance.K == "W" then
		view.Damage = math.max(1, math.floor(Items.WeaponDamage(level, instance.R, roll) * mult + 0.5))
		view.Class = if instance.C == "Any" then "Any" else base.Class
		view.Slot = "Weapon"
	else
		view.Health = math.max(1, math.floor(Items.ArmorHealth(level, instance.R, roll, base.Slot) * mult + 0.5))
		view.Defense = math.floor(Items.ArmorDefense(level) * mult * 1000 + 0.5) / 1000
	end
	viewMeta[base] = viewMeta[base] or { __index = base }
	return setmetatable(view, viewMeta[base])
end

-- The same view with the look of class `classId` (weapons usable by any
-- class are drawn as the player's class weapon).
function Items.LookFor(view, classId: string?)
	if view and view.Kind == "Weapon" and classId and Config.ClassById[classId] and view.Class ~= classId then
		local look = setmetatable(table.clone(view), getmetatable(view))
		look.Class = classId
		return look
	end
	return view
end

function Items.CanUse(view, classId: string?): boolean
	if view.Kind ~= "Weapon" then
		return true
	end
	return view.Class == "Any" or view.Class == classId
end

-- Is `view` better than what is worn in its slot (`worn` view or nil)?
function Items.IsBetter(view, worn): boolean
	if not worn then
		return true
	end
	return view.Score > worn.Score
end

-- Text of a bonus prop: "+4.5% Шанс крита".
function Items.PropText(prop): string
	local def = Config.BonusById[prop.S]
	if not def then
		return ""
	end
	if def.Pct then
		return ("+%s%% %s"):format(tostring(math.floor(prop.V * 1000 + 0.5) / 10), def.Name)
	end
	return ("+%s %s"):format(tostring(math.floor(prop.V * 10 + 0.5) / 10), def.Name)
end

---------------------------------------------------------------------
-- Generation (server; rng = Random)
---------------------------------------------------------------------

function Items.RollProp(rng: Random, rarityId: string, exclude: { [string]: boolean }?)
	local pool = {}
	for _, def in ipairs(I.Bonuses) do
		if not (exclude and exclude[def.Id]) then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		return nil
	end
	local def = pool[rng:NextInteger(1, #pool)]
	local scale = I.BonusScale[rarityId] or 1
	local value = (def.Min + (def.Max - def.Min) * rng:NextNumber()) * scale
	value = if def.Pct then math.floor(value * 1000 + 0.5) / 1000 else math.floor(value * 10 + 0.5) / 10
	return { S = def.Id, V = value }
end

-- Fills instance.P up to the minimum count of its rarity (new drops roll
-- between min and max; ascended items get what is missing).
function Items.FillProps(rng: Random, instance, toMax: boolean?)
	local range = I.BonusCount[instance.R]
	if not range then
		return
	end
	instance.P = instance.P or {}
	local want = if toMax then rng:NextInteger(range[1], range[2]) else range[1]
	local have = {}
	for _, prop in ipairs(instance.P) do
		have[prop.S] = true
	end
	while #instance.P < want do
		local prop = Items.RollProp(rng, instance.R, have)
		if not prop then
			break
		end
		have[prop.S] = true
		table.insert(instance.P, prop)
	end
end

local weaponsByClass, armorByBiome = nil, nil
local function index()
	if weaponsByClass then
		return
	end
	weaponsByClass, armorByBiome = {}, {}
	for _, w in ipairs(Config.Weapons) do
		if w.Biome and not w.Robux and not w.Legacy then
			weaponsByClass[w.Class] = weaponsByClass[w.Class] or {}
			table.insert(weaponsByClass[w.Class], w)
		end
	end
	for _, piece in ipairs(Config.Armor) do
		if piece.Biome then
			armorByBiome[piece.Biome] = armorByBiome[piece.Biome] or {}
			table.insert(armorByBiome[piece.Biome], piece)
		end
	end
end

-- The look (base) of a drop follows its item level: biome 1..4.
local function biomeFor(level: number): number
	return math.clamp(math.ceil(level / (I.MaxLevel / 4)), 1, 4)
end

-- A new instance without a uid (ItemService gives one).
-- opts: Level, Rarity, Class (the player's class or ""), Kind ("W" | "A" | nil), Slot
function Items.Generate(rng: Random, opts)
	index()
	local level = math.clamp(math.floor(opts.Level or 1), 1, I.MaxLevel)
	local kind = opts.Kind or (if rng:NextNumber() < I.WeaponShare then "W" else "A")
	local biome = biomeFor(level)
	local base
	if kind == "W" then
		local classes = { "Blade", "Pulse", "Gunner" }
		local classId = opts.Class
		if not weaponsByClass[classId or ""] or rng:NextNumber() > I.OwnClassChance then
			classId = classes[rng:NextInteger(1, #classes)]
		end
		local pool, any = {}, weaponsByClass[classId]
		for _, w in ipairs(any) do
			if w.Biome == biome then
				table.insert(pool, w)
			end
		end
		if #pool == 0 then
			pool = any
		end
		base = pool[rng:NextInteger(1, #pool)]
	else
		local pool = {}
		for _, piece in ipairs(armorByBiome[biome] or {}) do
			if not opts.Slot or piece.Slot == opts.Slot then
				table.insert(pool, piece)
			end
		end
		base = pool[rng:NextInteger(1, #pool)]
	end
	local instance = {
		B = base.Id,
		K = kind,
		R = opts.Rarity or "Common",
		L = level,
		Q = math.floor((I.Roll[1] + (I.Roll[2] - I.Roll[1]) * rng:NextNumber()) * 100 + 0.5) / 100,
		E = 0,
	}
	Items.FillProps(rng, instance, true)
	return instance
end

-- An instance that reproduces a catalog item from an old save (same
-- damage / health as it had), usable by any class.
function Items.FromCatalog(kind: string, base)
	local level, roll
	if kind == "W" then
		local damage = math.max(1, base.Damage or 1)
		level = math.clamp(math.floor(math.log(damage / (I.Weapon.Base * (I.RarityMult[base.Rarity] or 1))) / math.log(I.Weapon.Growth) + 0.5), 1, I.MaxLevel)
		roll = damage / Items.WeaponDamage(level, base.Rarity, 1)
	else
		local health = math.max(1, base.Health or 1)
		local per = health / ((I.RarityMult[base.Rarity] or 1) * (if base.Slot == "Chest" then I.Armor.ChestMult else 1))
		level = math.clamp(math.floor((per - I.Armor.HealthBase) / I.Armor.HealthPerLevel + 0.5), 1, I.MaxLevel)
		roll = health / Items.ArmorHealth(level, base.Rarity, 1, base.Slot)
	end
	return {
		B = base.Id,
		K = kind,
		R = base.Rarity or "Common",
		L = level,
		Q = math.floor(math.clamp(roll, 0.2, 3) * 1000 + 0.5) / 1000,
		E = 0,
		C = if kind == "W" then "Any" else nil,
	}
end

---------------------------------------------------------------------
-- Forge math (shown by the client, enforced by the server)
---------------------------------------------------------------------

function Items.EnhanceCost(instance): (number, number)
	local target = (instance.E or 0) + 1
	local e = F.Enhance
	local credits = math.floor(e.Credits * (1 + (instance.L or 1) / 10) * e.Growth ^ (target - 1) + 0.5)
	local cores = math.ceil(target * e.CoresPerLevel * (Config.Rarity[instance.R] or Config.Rarity.Common).Index / 2)
	return credits, cores
end

function Items.EnhanceChance(instance): (number, number)
	local target = (instance.E or 0) + 1
	local base = F.Chance[target - F.ChanceFrom + 1] or 1
	local pity = if base < 1 then (instance.F or 0) * F.Pity else 0
	return math.min(1, base + pity), pity
end

-- Cores spent on the enhance levels an item has.
function Items.EnhanceCoresSpent(instance): number
	local total = 0
	local index = (Config.Rarity[instance.R] or Config.Rarity.Common).Index
	for target = 1, instance.E or 0 do
		total += math.ceil(target * F.Enhance.CoresPerLevel * index / 2)
	end
	return total
end

function Items.SalvageCores(instance): number
	local cores = (F.Salvage.Cores[instance.R] or 1) * (1 + (instance.L or 1) / 50)
	return math.max(1, math.floor(cores + Items.EnhanceCoresSpent(instance) * F.Salvage.EnhanceRefund + 0.5))
end

function Items.NextRarity(rarityId: string): string?
	local rarity = Config.Rarity[rarityId]
	local next = rarity and Config.Rarities[rarity.Index + 1]
	return next and next.Id
end

function Items.AscendCost(instance): (number?, number?)
	local next = Items.NextRarity(instance.R)
	if not next then
		return nil, nil
	end
	return F.Ascend.Credits[next], F.Ascend.Cores[next]
end

function Items.ReforgeCost(instance): number
	return math.floor(F.Reforge.Credits * (Config.Rarity[instance.R] or Config.Rarity.Common).Index * (1 + (instance.L or 1) / 20) + 0.5)
end

return Items
