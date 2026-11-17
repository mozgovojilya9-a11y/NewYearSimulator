--[[
	ArtifactService.luau
	Artifacts (Config.Artifacts): 3 slots, passive bonuses (a StatService
	source) and special effects hooked into combat:
	  Lightning / Chain  AbilityService.OnHit
	  Explode / KillHeal DungeonRuns.OnKill
	  Shield             AbilityService.OnIncoming
	They drop from boss chests (LootService asks RollArtifact / GiveArtifact)
	and come from rewards (ArtifactService.Give). A duplicate is a spare
	copy; N copies upgrade level N -> N + 1; at the max level a duplicate
	turns into Нано-ядра.

	Save: data.Artifacts[id] = { Level, Copies }, data.ArtifactSlots = { id, id, id }.
	Client: Artifacts:InvokeServer("Equip" | "Unequip" | "Upgrade", id) -> ok, message
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local AbilityService = require(script.Parent.AbilityService)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local LootService = require(script.Parent.LootService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)

local A = Config.Artifacts
local T = A.Texts

local ArtifactService = {}

local rng = Random.new()
local hits = {} -- [player] = hit counter (Lightning)
local shieldUntil = {} -- [player] = os.clock() the emergency shield ends
local shieldReady = {} -- [player] = os.clock() it can trigger again

-- Equipped artifacts of a player: { { Def, Level }, ... }.
local function equipped(player)
	local data = DataService.Get(player)
	local list = {}
	if data then
		for _, id in ipairs(data.ArtifactSlots) do
			local def = Config.ArtifactById[id or ""]
			local record = def and data.Artifacts[id]
			if record then
				table.insert(list, { Def = def, Level = record.Level or 1 })
			end
		end
	end
	return list
end

-- The equipped artifact with an effect: (def, value) or nil.
local function effect(player, kind: string)
	for _, entry in ipairs(equipped(player)) do
		if entry.Def.Effect == kind then
			return entry.Def, Config.ArtifactValue(entry.Def.Value, entry.Level)
		end
	end
	return nil, 0
end

-- Adds an artifact (or a copy of it). Returns info for the client:
-- { Id, New, Level, Copies, Cores }.
function ArtifactService.Give(player, id: string)
	local data = DataService.Get(player)
	local def = Config.ArtifactById[id]
	if not data or not def then
		return nil
	end
	local record = data.Artifacts[id]
	local info = { Id = id }
	if not record then
		data.Artifacts[id] = { Level = 1, Copies = 0 }
		info.New = true
		-- a free slot takes it at once
		for i = 1, A.Slots do
			if (data.ArtifactSlots[i] or "") == "" then
				data.ArtifactSlots[i] = id
				break
			end
		end
		Remotes.Notify(player, T.Got:format(def.Name), "gold")
	elseif record.Level >= A.MaxLevel then
		local cores = A.DuplicateCores[def.Rarity] or 5
		data.Cores = (data.Cores or 0) + cores
		info.Cores = cores
		Remotes.Notify(player, T.ToCores:format(def.Name, cores), "gold")
	else
		record.Copies = (record.Copies or 0) + 1
		Remotes.Notify(player, T.Duplicate:format(def.Name, record.Copies), "gold")
	end
	record = data.Artifacts[id]
	info.Level, info.Copies = record.Level, record.Copies
	PlayerState.Sync(player)
	return info
end

-- A random artifact id a gate rank can drop.
function ArtifactService.Roll(_player, rank: string): string
	local maxIndex = Config.Rarity[A.MaxRank[rank] or "Rare"].Index
	local pool, total = {}, 0
	for _, def in ipairs(A.List) do
		if Config.Rarity[def.Rarity].Index <= maxIndex then
			local weight = A.Weights[def.Rarity] or 1
			table.insert(pool, { def, weight })
			total += weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, entry in ipairs(pool) do
		roll -= entry[2]
		if roll <= 0 then
			return entry[1].Id
		end
	end
	return pool[1][1].Id
end

local function equip(player, data, id)
	if not data.Artifacts[id] then
		return false, "Нет такого артефакта"
	end
	for i = 1, A.Slots do
		if data.ArtifactSlots[i] == id then
			return true, ""
		end
	end
	for i = 1, A.Slots do
		if (data.ArtifactSlots[i] or "") == "" then
			data.ArtifactSlots[i] = id
			PlayerState.Sync(player)
			return true, ""
		end
	end
	return false, T.NoSlot
end

local function unequip(player, data, id)
	for i = 1, A.Slots do
		if data.ArtifactSlots[i] == id then
			data.ArtifactSlots[i] = ""
			PlayerState.Sync(player)
			return true, ""
		end
	end
	return false, "Не надет"
end

local function upgrade(player, data, id)
	local record = data.Artifacts[id]
	local def = Config.ArtifactById[id]
	if not record or not def then
		return false, "Нет такого артефакта"
	end
	if record.Level >= A.MaxLevel then
		return false, T.Max
	end
	local need = record.Level
	if (record.Copies or 0) < need then
		return false, ("Нужно копий: %d"):format(need)
	end
	record.Copies -= need
	record.Level += 1
	PlayerState.Sync(player)
	return true, T.Upgraded:format(def.Name, record.Level)
end

function ArtifactService.Init()
	-- passive bonuses
	table.insert(StatService.Sources, function(player)
		local bonus = {}
		for _, entry in ipairs(equipped(player)) do
			for stat, range in pairs(entry.Def.Stats or {}) do
				bonus[stat] = (bonus[stat] or 0) + Config.ArtifactValue(range, entry.Level)
			end
		end
		return bonus
	end)

	-- Lightning (every N-th hit) and Chain (crits jump)
	table.insert(AbilityService.OnHit, function(player, model, dealt, isCrit)
		local position = model:GetPivot().Position
		local storm, stormValue = effect(player, "Lightning")
		if storm then
			hits[player] = (hits[player] or 0) + 1
			if hits[player] % storm.Every == 0 then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local from = if root then root.Position + Vector3.new(0, 12, 0) else position + Vector3.new(0, 14, 0)
				local color = Config.Nano.Cyan
				AbilityService.Fx("Beam", from, position, color, 0.6)
				DungeonRuns.Damage(player, model, dealt * stormValue, false)
				local count = 0
				for _, e in ipairs(DungeonRuns.MobsNear(player, position, storm.Radius)) do
					if e.model ~= model and count < storm.Targets then
						count += 1
						AbilityService.Fx("Beam", position, e.model:GetPivot().Position, color, 0.4)
						DungeonRuns.Damage(player, e.model, dealt * stormValue, false)
					end
				end
			end
		end
		if isCrit then
			local chain, chainValue = effect(player, "Chain")
			if chain then
				local count = 0
				for _, e in ipairs(DungeonRuns.MobsNear(player, position, chain.Radius)) do
					if e.model ~= model and count < chain.Targets then
						count += 1
						AbilityService.Fx("Beam", position, e.model:GetPivot().Position, Config.Nano.Gold, 0.35)
						DungeonRuns.Damage(player, e.model, dealt * chainValue, false)
					end
				end
			end
		end
	end)

	-- Emergency shield at low HP
	table.insert(AbilityService.OnIncoming, function(player, amount)
		local now = os.clock()
		local aegis, value = effect(player, "Shield")
		if not aegis then
			return amount
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and (shieldUntil[player] or 0) < now and (shieldReady[player] or 0) <= now and (humanoid.Health - amount) / math.max(1, humanoid.MaxHealth) < aegis.Below then
			shieldUntil[player] = now + aegis.Seconds
			shieldReady[player] = now + aegis.Cooldown
			AbilityService.Fx("Shield", player.Character, aegis.Seconds, Config.Nano.Gold)
		end
		if (shieldUntil[player] or 0) >= now then
			amount *= 1 - value
		end
		return amount
	end)

	-- Explosion / heal on kill
	local previous = DungeonRuns.OnKill
	DungeonRuns.OnKill = function(player, room, isBoss, position, kind)
		if previous then
			previous(player, room, isBoss, position, kind)
		end
		local boom, boomValue = effect(player, "Explode")
		if boom then
			AbilityService.Fx("Ring", position, boom.Radius, Config.Theme.Orange)
			local damage = StatService.Get(player).Damage * boomValue
			for _, e in ipairs(DungeonRuns.MobsNear(player, position, boom.Radius)) do
				DungeonRuns.Damage(player, e.model, damage, false)
			end
		end
		local heal, healValue = effect(player, "KillHeal")
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if heal and humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * healValue)
		end
	end

	-- drops
	LootService.RollArtifact = ArtifactService.Roll
	LootService.GiveArtifact = ArtifactService.Give

	local allow = RateLimit.new(0.2)
	Remotes.Get("Artifacts").OnServerInvoke = function(player, action, id)
		local data = DataService.Get(player)
		if not allow(player) or not data or not PlayerState.IsReady(player) or type(id) ~= "string" then
			return false, "Подожди секунду"
		end
		if action == "Equip" then
			return equip(player, data, id)
		elseif action == "Unequip" then
			return unequip(player, data, id)
		elseif action == "Upgrade" then
			return upgrade(player, data, id)
		end
		return false, "Неверный запрос"
	end
	Players.PlayerRemoving:Connect(function(player)
		hits[player] = nil
		shieldUntil[player] = nil
		shieldReady[player] = nil
	end)
end

return ArtifactService
