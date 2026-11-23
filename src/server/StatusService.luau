--[[
	StatusService.luau
	"Статус": stat points (Config.Attributes). Every level above 1 gives
	PointsPerLevel points; the player spends them on Сила / Ловкость /
	Живучесть / Восприятие. Spent points are a StatService source.
	Free points = StatPointsAtLevel(level) - spent (attribute StatPoints,
	published by PlayerState.Sync).

	Status:InvokeServer("Add", attributeId, count) -> ok, message
	Status:InvokeServer("Reset")                   -> ok, message (credits)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)

local A = Config.Attributes
local T = A.Texts

local StatusService = {}

local function spent(data): number
	local total = 0
	for _, value in pairs(data.Attributes) do
		total += value
	end
	return total
end

function StatusService.ResetCost(data): number
	return A.ResetCost + A.ResetPerLevel * (data.Level or 1)
end

local function add(player, data, id, count)
	local def = Config.AttributeById[id or ""]
	count = math.floor(tonumber(count) or 1)
	if not def or count < 1 then
		return false, "Неверный запрос"
	end
	local free = Config.StatPointsAtLevel(data.Level) - spent(data)
	if free <= 0 then
		return false, T.NoPoints
	end
	count = math.min(count, free)
	data.Attributes[id] = (data.Attributes[id] or 0) + count
	PlayerState.Sync(player)
	GameEvents.Fire(player, "Stat", count)
	return true, ""
end

local function reset(player, data)
	if spent(data) == 0 then
		return false, T.Nothing
	end
	if not PlayerState.SpendCredits(player, StatusService.ResetCost(data)) then
		return false, T.NoCredits
	end
	for _, def in ipairs(A.List) do
		data.Attributes[def.Id] = 0
	end
	PlayerState.Sync(player)
	return true, T.ResetDone
end

function StatusService.Init()
	table.insert(StatService.Sources, function(_player, data)
		local bonus = {}
		for _, def in ipairs(A.List) do
			local points = data.Attributes[def.Id] or 0
			if points > 0 then
				for stat, per in pairs(def.PerPoint) do
					bonus[stat] = (bonus[stat] or 0) + per * points
				end
			end
		end
		return bonus
	end)
	local allow = RateLimit.new(0.08)
	Remotes.Get("Status").OnServerInvoke = function(player, action, id, count)
		local data = DataService.Get(player)
		if not allow(player) or not data or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Add" then
			return add(player, data, id, count)
		elseif action == "Reset" then
			return reset(player, data)
		elseif action == "Ascend" then
			-- spend Возвышение points into a line (Config.Ascension)
			local line
			for _, l in ipairs(Config.Ascension.Lines) do
				if l.Id == id then
					line = l
				end
			end
			local A = data.Ascension
			if not line or type(A) ~= "table" then
				return false, "Неверный запрос"
			end
			A.Spent = if type(A.Spent) == "table" then A.Spent else {}
			local spentA = 0
			for _, v in pairs(A.Spent) do
				spentA += v
			end
			local free = (A.Points or 0) - spentA
			local n = math.min(math.max(1, math.floor(tonumber(count) or 1)), free)
			if n <= 0 then
				return false, Config.Ascension.Texts.NoPoints
			end
			A.Spent[line.Id] = (A.Spent[line.Id] or 0) + n
			PlayerState.Sync(player)
			return true, ""
		end
		return false, "Неверный запрос"
	end
end

return StatusService
