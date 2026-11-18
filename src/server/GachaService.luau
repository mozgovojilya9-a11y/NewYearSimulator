--[[
	GachaService.luau
	Pulls at the Терминал снабжения (Config.Gacha), server-authoritative.
	Remote "Gacha" (RemoteFunction):
	  ("Info")                  -> { Pity = { [banner] = {...} }, Restricted }
	  ("Pull", bannerId, count) -> ok, results | message
	count = 1 or 10. Price in Кристаллы; where PolicyService says paid random
	items are restricted (ArePaidRandomItemsRestricted) only the earned
	crystals can pay (the player attribute "PaidPullsOff" tells the UI).
	A result: an item of the banner's kind for the player's class; the
	rarity is rolled by Config.Gacha.Rates with the pity counters
	(data.Gacha[banner] = { Pulls, SinceEpic, SinceLegendary }); an item
	whose base + rarity is already owned is a duplicate -> Нано-ядра.
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local GachaService = {}

local GA = Config.Gacha
local rng = Random.new()
local restricted = {} -- [player] = true when paid pulls are off

GachaService.OnPulled = nil -- (player, count) quests / achievements

local function rank(rarityId: string): number
	return (Config.Rarity[rarityId] or Config.Rarity.Common).Index
end

local function rollRarity(counter)
	-- pity first
	if counter.SinceLegendary + 1 >= GA.Pity.Legendary then
		return "Legendary"
	end
	local total = 0
	for _, w in pairs(GA.Rates) do
		total += w
	end
	local roll = rng:NextNumber() * total
	local pick = "Uncommon"
	-- walk rarities from the lowest so the order is stable
	local list = {}
	for id, w in pairs(GA.Rates) do
		table.insert(list, { id = id, w = w })
	end
	table.sort(list, function(a, b)
		return rank(a.id) < rank(b.id)
	end)
	for _, entry in ipairs(list) do
		roll -= entry.w
		if roll <= 0 then
			pick = entry.id
			break
		end
	end
	if counter.SinceEpic + 1 >= GA.Pity.Epic and rank(pick) < rank("Epic") then
		pick = "Epic"
	end
	return pick
end

local function counterOf(data, bannerId: string)
	data.Gacha = if type(data.Gacha) == "table" then data.Gacha else {}
	local c = data.Gacha[bannerId]
	if type(c) ~= "table" then
		c = { Pulls = 0, SinceEpic = 0, SinceLegendary = 0 }
		data.Gacha[bannerId] = c
	end
	c.Pulls = tonumber(c.Pulls) or 0
	c.SinceEpic = tonumber(c.SinceEpic) or 0
	c.SinceLegendary = tonumber(c.SinceLegendary) or 0
	return c
end

local function info(player)
	local data = DataService.Get(player)
	local pity = {}
	for _, banner in ipairs(GA.Banners) do
		local c = counterOf(data, banner.Id)
		pity[banner.Id] = { Epic = GA.Pity.Epic - c.SinceEpic, Legendary = GA.Pity.Legendary - c.SinceLegendary, Pulls = c.Pulls }
	end
	return { Pity = pity, Restricted = restricted[player] == true }
end

local function pull(player, bannerId, count)
	local data = DataService.Get(player)
	local banner
	for _, b in ipairs(GA.Banners) do
		if b.Id == bannerId then
			banner = b
		end
	end
	if not data or not banner or (count ~= 1 and count ~= 10) then
		return false, "Неверный запрос"
	end
	if PlayerState.ItemCount(player) + count > Config.Items.MaxInventory then
		return false, GA.Texts.Full
	end
	local cost = if count == 10 then GA.Cost.Ten else GA.Cost.One
	if not PlayerState.SpendCrystals(player, cost, restricted[player] == true) then
		return false, GA.Texts.NotEnough:format(cost)
	end
	local counter = counterOf(data, banner.Id)
	local owned = {}
	for _, item in pairs(data.Items) do
		owned[tostring(item.B) .. ":" .. tostring(item.R)] = true
	end
	local level = math.max(GA.MinLevel, (data.RoomReached or 0) * Config.Items.LevelPerRoom)
	local results = {}
	local cores = 0
	for _ = 1, count do
		local rarityId = rollRarity(counter)
		counter.Pulls += 1
		counter.SinceEpic = if rank(rarityId) >= rank("Epic") then 0 else counter.SinceEpic + 1
		counter.SinceLegendary = if rank(rarityId) >= rank("Legendary") then 0 else counter.SinceLegendary + 1
		local instance = ItemService.Generate(player, level, rarityId, banner.Kind)
		local key = tostring(instance.B) .. ":" .. tostring(instance.R)
		local entry = { B = instance.B, K = instance.K, R = instance.R, L = instance.L }
		if owned[key] then
			local amount = GA.DuplicateCores[rarityId] or 5
			cores += amount
			entry.Dup = amount
		else
			owned[key] = true
			ItemService.Give(player, instance, { Force = true, NoSync = true })
		end
		table.insert(results, entry)
	end
	if cores > 0 then
		PlayerState.AddCores(player, cores)
	end
	PlayerState.Sync(player)
	require(script.Parent.ProgressionService).Count(player, "Pulls", count)
	if GachaService.OnPulled then
		GachaService.OnPulled(player, count)
	end
	return true, results, info(player)
end

local function checkPolicy(player)
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	local off = ok and type(policy) == "table" and policy.ArePaidRandomItemsRestricted == true
	restricted[player] = off or nil
	player:SetAttribute("PaidPullsOff", off)
end

function GachaService.Init()
	local allow = RateLimit.new(0.2)
	local pullAllow = RateLimit.new(1) -- one pull request per second
	Remotes.Get("Gacha").OnServerInvoke = function(player, action, a, b)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Info" then
			return true, info(player)
		elseif action == "Pull" then
			if not pullAllow(player) then
				return false, "Подожди секунду"
			end
			return pull(player, a, b)
		end
		return false, "Неверный запрос"
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPolicy, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(checkPolicy, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		restricted[player] = nil
	end)
end

return GachaService
