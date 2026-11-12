--[[
	LootService.luau
	Mobs drop MATERIALS (never Aura). Server-authoritative and personal:

	- On every kill the rarity is rolled (Config.Rarities, multiplied by
	  loot luck for Rare+), then a material of that rarity is picked from
	  the mob's drop table (Config.Mobs.Defs[kind].Drops). Bosses drop
	  Config.Loot.BossDrops items, the first one at least BossGuaranteed.
	- The drop exists only as a server record + a visual on the OWNER's
	  client (Loot:FireClient "Spawn"): nobody else sees it or can take it.
	- Pick up = the owner holds E on the drop (client ProximityPrompt) and
	  fires Loot:FireServer(id); the server checks owner, lifetime,
	  distance and that the hold time could have passed, then adds the
	  material to the inventory.
	- Drops vanish after Config.Loot.Lifetime seconds or when the run ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonGenerator = require(script.Parent.DungeonGenerator)
local DungeonRuns = require(script.Parent.DungeonRuns)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local LootService = {}

local LOOT = Config.Loot
local LUCK_FROM = Config.Rarity[LOOT.LuckFrom].Index

local drops = {} -- [id] = { player, material, position, born, expires }
local nextId = 0
local dropsByRarity = {} -- [mobKind] = { [rarityIndex] = { materialId, ... } }

for kind, def in pairs(Config.Mobs.Defs) do
	local byRarity = {}
	for _, materialId in ipairs(def.Drops) do
		local material = Config.MaterialById[materialId]
		if material then
			local index = Config.Rarity[material.Rarity].Index
			byRarity[index] = byRarity[index] or {}
			table.insert(byRarity[index], materialId)
		end
	end
	dropsByRarity[kind] = byRarity
end

-- Rolls a rarity index. luck multiplies the chance of LuckFrom and above;
-- minIndex (optional) forbids anything lower.
local function rollRarity(luck: number, minIndex: number?): number
	local weights = {}
	local total = 0
	for index, rarity in ipairs(Config.Rarities) do
		local weight = rarity.Chance
		if index >= LUCK_FROM then
			weight *= luck
		end
		if minIndex and index < minIndex then
			weight = 0
		end
		weights[index] = weight
		total += weight
	end
	local roll = math.random() * total
	for index, weight in ipairs(weights) do
		roll -= weight
		if roll <= 0 and weight > 0 then
			return index
		end
	end
	return minIndex or 1
end

local function pickMaterial(kind: string, rarityIndex: number): string?
	local byRarity = dropsByRarity[kind]
	if not byRarity then
		return nil
	end
	for index = rarityIndex, 1, -1 do
		local list = byRarity[index]
		if list then
			return list[math.random(#list)]
		end
	end
	for index = rarityIndex + 1, #Config.Rarities do
		local list = byRarity[index]
		if list then
			return list[math.random(#list)]
		end
	end
	return nil
end

local function spawnDrop(player, materialId: string, position: Vector3)
	nextId += 1
	local id = nextId
	local now = os.clock()
	drops[id] = { player = player, material = materialId, position = position, born = now, expires = now + LOOT.Lifetime }
	Remotes.Get("Loot"):FireClient(player, "Spawn", id, materialId, position, LOOT.Lifetime)

	local material = Config.MaterialById[materialId]
	local rarity = Config.Rarity[material.Rarity]
	if rarity.Announce then
		local text = LOOT.Texts.Announce:format(player.DisplayName, rarity.Name, material.Name)
		Remotes.Get("Announce"):FireAllClients(text, rarity.Color)
	end
end

function LootService.OnKill(player, room: number, isBoss: boolean, position: Vector3, kind: string)
	if not PlayerState.IsReady(player) or not dropsByRarity[kind] then
		return
	end
	local luck = PlayerState.LootLuck(player)
	local count = 1
	if isBoss then
		count = LOOT.BossDrops
		luck *= LOOT.BossLuck
	elseif math.random() < LOOT.ExtraDropChance then
		count = 2
	end
	local groundY = DungeonGenerator.GroundY()
	for i = 1, count do
		local minIndex = if isBoss and i == 1 then Config.Rarity[LOOT.BossGuaranteed].Index else nil
		local materialId = pickMaterial(kind, rollRarity(luck, minIndex))
		if materialId then
			local angle = math.random() * math.pi * 2
			local radius = if count > 1 then 2.5 + math.random() * 2 else 0
			spawnDrop(player, materialId, Vector3.new(position.X + math.cos(angle) * radius, groundY, position.Z + math.sin(angle) * radius))
		end
	end
end

local function pickUp(player, id)
	local drop = drops[id]
	if type(id) ~= "number" or not drop or drop.player ~= player then
		return
	end
	local now = os.clock()
	if now > drop.expires or now - drop.born < LOOT.HoldSeconds * 0.8 then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - drop.position).Magnitude > LOOT.PickupRange then
		return
	end
	drops[id] = nil
	local total = PlayerState.AddMaterial(player, drop.material, 1)
	local run = DungeonRuns.GetRun(player)
	if run then
		run.loot[drop.material] = (run.loot[drop.material] or 0) + 1
	end
	Remotes.Get("Loot"):FireClient(player, "Picked", id, drop.material, total)
end

-- Removes every drop of a player (run ended / left the game).
function LootService.Clear(player)
	for id, drop in pairs(drops) do
		if drop.player == player then
			drops[id] = nil
		end
	end
	if player.Parent then
		Remotes.Get("Loot"):FireClient(player, "Clear")
	end
end

function LootService.Init()
	local allow = RateLimit.new(0.05)
	Remotes.Get("Loot").OnServerEvent:Connect(function(player, id)
		if allow(player) then
			pickUp(player, id)
		end
	end)

	-- Chain onto the kill hook (ProgressionService listens to it too).
	local previous = DungeonRuns.OnKill
	DungeonRuns.OnKill = function(player, room, isBoss, position, kind)
		if previous then
			previous(player, room, isBoss, position, kind)
		end
		LootService.OnKill(player, room, isBoss, position, kind)
	end
	DungeonRuns.OnRunClosed = LootService.Clear
	Players.PlayerRemoving:Connect(LootService.Clear)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for id, drop in pairs(drops) do
				if now > drop.expires then
					drops[id] = nil
					if drop.player.Parent then
						Remotes.Get("Loot"):FireClient(drop.player, "Remove", id)
					end
				end
			end
		end
	end)
end

return LootService
