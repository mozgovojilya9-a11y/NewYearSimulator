--[[
	LootService.luau
	Personal loot: ready gear (and rarely artifacts) from killed mobs.

	A normal mob may drop one item (Config.Loot.DropChance + the player's
	DropChance stat). A boss leaves a CHEST: holding E opens it and its
	items (BossItems, the first at least BossMinRarity of the rank, maybe
	an artifact) fly out as normal drops. Every drop is personal and is
	picked up by holding E; the server checks owner, distance, age and
	the inventory cap.

	Rarity: Config.Loot.Tables[gate rank][enemy type]; the player's Luck
	multiplies the weights of the LuckTop highest rarities the table
	allows (never opens a rarity the rank does not have).
	Item level: room x Config.Items.LevelPerRoom -+ LevelSpread.

	Remote Loot:
	  S->C ("Spawn", id, kind, payload, position, lifetime)
	        kind "Item" (payload = instance) | "Chest" ({ Rank }) | "Artifact" ({ Id })
	       ("Open", id)                      the chest opens (animation)
	       ("Picked", id, kind, payload)     payload = the saved instance / artifact info
	       ("Remove", id) | ("Clear")
	  C->S (id)                              pick up / open
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonRuns = require(script.Parent.DungeonRuns)
local GameEvents = require(script.Parent.GameEvents)
local ItemService = require(script.Parent.ItemService)
local PlayerState = require(script.Parent.PlayerState)
local StatService = require(script.Parent.StatService)
local StreakService = require(script.Parent.StreakService)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local LootService = {}

local LOOT = Config.Loot
local rng = Random.new()

local drops = {} -- [id] = { player, kind, payload, position, born, expires, room, rank }
local nextId = 0

-- Set by ArtifactService: (player) -> artifactId to drop, and
-- (player, artifactId) -> info for the client when it is picked up.
LootService.RollArtifact = nil
LootService.GiveArtifact = nil

-- Rolls a rarity id from the table of a rank / enemy type for the player.
-- minRarity (optional): nothing below it (clamped to what the table has).
function LootService.RollRarity(player, rank: string, enemy: string, minRarity: string?): string
	local byRank = LOOT.Tables[rank] or LOOT.Tables.E
	local weights = byRank[enemy] or byRank.Normal
	local luck = math.clamp(if player then StatService.Get(player).Luck else 1, 1, LOOT.LuckCap)
	-- the rarities this table allows, lowest first
	local allowed = {}
	for _, rarity in ipairs(Config.Rarities) do
		if (weights[rarity.Id] or 0) > 0 then
			table.insert(allowed, rarity)
		end
	end
	local minIndex = if minRarity then math.min(Config.Rarity[minRarity].Index, allowed[#allowed].Index) else 0
	local total, list = 0, {}
	for i, rarity in ipairs(allowed) do
		local weight = weights[rarity.Id]
		if i > #allowed - LOOT.LuckTop and #allowed > 1 then
			weight *= luck
		end
		if rarity.Index < minIndex then
			weight = 0
		end
		list[i] = weight
		total += weight
	end
	local roll = rng:NextNumber() * total
	for i, weight in ipairs(list) do
		roll -= weight
		if roll <= 0 and weight > 0 then
			return allowed[i].Id
		end
	end
	return allowed[#allowed].Id
end

local function itemLevel(room: number): number
	return math.clamp(room * Config.Items.LevelPerRoom + rng:NextInteger(-Config.Items.LevelSpread, Config.Items.LevelSpread), 1, Config.Items.MaxLevel)
end

local function spawnDrop(player, kind: string, payload, position: Vector3, extra)
	nextId += 1
	local id = nextId
	local now = os.clock()
	local drop = { player = player, kind = kind, payload = payload, position = position, born = now, expires = now + LOOT.Lifetime }
	for key, value in pairs(extra or {}) do
		drop[key] = value
	end
	drops[id] = drop
	Remotes.Get("Loot"):FireClient(player, "Spawn", id, kind, payload, position, LOOT.Lifetime)
	if kind == "Item" then
		local rarity = Config.Rarity[payload.R]
		if rarity.Index >= Config.Rarity[LOOT.FlashFrom].Index then
			local base = Config.ItemById[if payload.K == "W" then "Weapon" else "Armor"][payload.B]
			Remotes.Get("Announce"):FireAllClients(LOOT.Texts.Announce:format(player.DisplayName, rarity.Name, base.Name), rarity.Color)
		end
	end
	return id
end

-- One gear drop of a tier for the player at `position` (rank: the gate
-- rank of the run, else the rank of the tier).
function LootService.DropItem(player, room: number, enemy: string, position: Vector3, minRarity: string?, rank: string?)
	rank = rank or Config.RankForRoom(room)
	local rarityId = LootService.RollRarity(player, rank, enemy, minRarity)
	local instance = ItemService.Generate(player, itemLevel(room), rarityId)
	return spawnDrop(player, "Item", instance, position)
end

-- Boss chest. opts: Rank, Extra (more items: the run grade), MinStep
-- (first item a step rarer), Red.
function LootService.DropChest(player, room: number, position: Vector3, enemy: string?, opts)
	opts = opts or {}
	local rank = opts.Rank or Config.RankForRoom(room)
	return spawnDrop(player, "Chest", { Rank = rank, Red = opts.Red }, position, { room = room, enemy = enemy or "Boss", rank = rank, extra = opts.Extra or 0, minStep = opts.MinStep or 0 })
end

-- info (gate runs): { Rank, Enemy = "Normal" | "Elite" | "Red", Red }.
-- Bosses drop their chest from DungeonRuns.OnBossDefeated (grade bonus).
function LootService.OnKill(player, room: number, isBoss: boolean, position: Vector3, _kind: string, info)
	if not PlayerState.IsReady(player) or isBoss then
		return
	end
	info = info or {}
	local enemy = info.Enemy or "Normal"
	local ground = Vector3.new(position.X, DungeonRuns.GroundY(), position.Z)
	-- spread a little so drops of a group don't sit in one spot
	ground += Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
	local chance = ((LOOT.DropChance[enemy] or LOOT.DropChance.Normal) + (StatService.Get(player).DropChance or 0)) * StreakService.Mult(player, "Loot")
	if rng:NextNumber() < chance then
		LootService.DropItem(player, room, enemy, ground, nil, info.Rank)
	end
	-- elites and red-gate enemies may drop an artifact too
	if LootService.RollArtifact and rng:NextNumber() < (LOOT.ArtifactChance[enemy] or 0) then
		spawnDrop(player, "Artifact", { Id = LootService.RollArtifact(player, info.Rank or Config.RankForRoom(room)) }, ground + Vector3.new(2, 0, 0))
	end
end

local function openChest(player, id, drop)
	drops[id] = nil
	Remotes.Get("Loot"):FireClient(player, "Open", id)
	local room, enemy = drop.room or 1, drop.enemy or "Boss"
	local rank = drop.rank or Config.RankForRoom(room)
	task.delay(LOOT.Chest.OpenSeconds, function()
		if not player.Parent then
			return
		end
		local count = LOOT.BossItems + (drop.extra or 0)
		local artifact = LootService.RollArtifact and rng:NextNumber() < (LOOT.ArtifactChance[enemy] or 0) and LootService.RollArtifact(player, rank)
		local total = count + (if artifact then 1 else 0)
		local start = rng:NextNumber() * math.pi * 2
		for i = 1, total do
			local angle = start + (i - 1) * math.pi * 2 / total
			local position = drop.position + Vector3.new(math.cos(angle) * LOOT.SpreadRadius, 0, math.sin(angle) * LOOT.SpreadRadius)
			if i <= count then
				local minRarity = nil
				if i == 1 then
					minRarity = LOOT.BossMinRarity[rank]
					for _ = 1, drop.minStep or 0 do
						local nextRarity = Config.Rarities[Config.Rarity[minRarity].Index + 1]
						minRarity = if nextRarity then nextRarity.Id else minRarity
					end
				end
				LootService.DropItem(player, room, enemy, position, minRarity, rank)
			else
				spawnDrop(player, "Artifact", { Id = artifact }, position)
			end
		end
	end)
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
	if drop.kind == "Chest" then
		openChest(player, id, drop)
		return
	end
	if drop.kind == "Artifact" then
		if not LootService.GiveArtifact then
			return
		end
		drops[id] = nil
		local info = LootService.GiveArtifact(player, drop.payload.Id)
		Remotes.Get("Loot"):FireClient(player, "Picked", id, "Artifact", info)
		return
	end
	if not ItemService.HasRoom(player) then
		Remotes.Notify(player, Config.Items.Texts.Full:format(Config.Items.MaxInventory), "red")
		return
	end
	drops[id] = nil
	local view = ItemService.Give(player, drop.payload)
	if view then
		DungeonRuns.NoteLoot(player, { B = drop.payload.B, K = drop.payload.K, R = drop.payload.R, L = drop.payload.L, E = 0 })
	end
	Remotes.Get("Loot"):FireClient(player, "Picked", id, "Item", drop.payload)
	GameEvents.Fire(player, "Loot", 1)
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
	DungeonRuns.OnKill = function(player, room, isBoss, position, kind, info)
		if previous then
			previous(player, room, isBoss, position, kind, info) -- keep `info` (enemy kind, rank, weight)
		end
		LootService.OnKill(player, room, isBoss, position, kind, info)
	end
	DungeonRuns.OnRunClosed = LootService.Clear
	-- Охотничий азарт milestones: extra items (and a chest at the top one)
	StreakService.OnMilestone = function(player, milestone, room, position, rank)
		if not position or not PlayerState.IsReady(player) then
			return
		end
		local ground = Vector3.new(position.X, DungeonRuns.GroundY(), position.Z)
		for i = 1, milestone.Items or 0 do
			local angle = i * math.pi * 2 / math.max(1, milestone.Items)
			LootService.DropItem(player, room, "Elite", ground + Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3), nil, rank)
		end
		if milestone.Chest then
			LootService.DropChest(player, room, ground + Vector3.new(0, 0, 4), "Elite", { Rank = rank })
		end
		if milestone.Credits then
			local credits = PlayerState.AddCredits(player, Config.KillCredits(room, false) * milestone.Credits * StatService.Get(player).CreditsMult)
			if credits and credits > 0 then
				Remotes.Get("ClickHit"):FireClient(player, "Credits", credits, position)
			end
		end
	end
	-- boss down: a chest for every member, more items for a better grade
	DungeonRuns.OnBossDefeated = function(run, position, grade)
		for i, player in ipairs(DungeonRuns.Members(run)) do
			local offset = Vector3.new((i - 1) * 6 - (#run.players - 1) * 3, 0, 4)
			LootService.DropChest(player, run.location.BossTier, position + offset, if run.red then "Red" else "Boss", {
				Rank = run.location.Rank,
				Extra = grade.Items + (run.contractItems or 0), -- + the contract bonus
				MinStep = grade.MinStep,
				Red = run.red,
			})
		end
	end
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
