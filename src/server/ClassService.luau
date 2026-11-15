--[[
	ClassService.luau
	Classes and skill trees (server-authoritative):
	  ("Choose", classId)        pick / change the class (each class keeps
	                             its own tree progress)
	  ("Learn", nodeId)          +1 rank: the class's node, unlock level
	                             reached, the node above learned, a free point
	  ("Reset")                  all points of the current class back; the
	                             first reset of a class is free, then
	                             Config.Skills.ResetCost(level) credits
	  ("Equip", slot, nodeId)    put a learned active on Q / E / R (nil = clear)
	Everything is published by PlayerState.Sync (attributes Class,
	SkillPoints, SkillState, Loadout); stats by StatService.
	The Academy terminal in the hub opens the class screen on the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local WorldKit = require(script.Parent.WorldKit)

local ClassService = {}

ClassService.OnChosen = nil -- (player, classId) quests listen
ClassService.OnLearned = nil -- (player, node)

local SK = Config.Skills
local T = Config.Combat.Texts

local function rankOf(record, nodeId: string): number
	local r = record.Skills[nodeId]
	return if type(r) == "number" then r else 0
end

-- Can this node get one more rank? Returns ok, reason.
function ClassService.CanLearn(data, record, node): (boolean, string?)
	if rankOf(record, node.Id) >= node.MaxRank then
		return false, "Максимальный уровень"
	end
	if data.Level < node.Level then
		return false, ("Откроется на %d уровне"):format(node.Level)
	end
	local layout = SK.Layout[node.Position]
	local function learned(position)
		local id = node.Class .. "_" .. node.Branch .. position
		return rankOf(record, id) > 0
	end
	if layout.Needs and not learned(layout.Needs) then
		return false, "Сначала изучи навык выше"
	end
	if layout.NeedsAny then
		local any = false
		for _, position in ipairs(layout.NeedsAny) do
			if learned(position) then
				any = true
			end
		end
		if not any then
			return false, "Сначала изучи навык выше"
		end
	end
	if SK.PointsAtLevel(data.Level) - PlayerState.SpentPoints(record) <= 0 then
		return false, "Нет очков навыков"
	end
	return true
end

local function choose(player, data, classId)
	if not Config.ClassById[classId] then
		return false, "Нет такого класса"
	end
	local first = (data.Class or "") == ""
	data.Class = classId
	PlayerState.ClassRecord(data, classId)
	PlayerState.Sync(player)
	GameEvents.Fire(player, "Class", 1)
	if ClassService.OnChosen then
		ClassService.OnChosen(player, classId, first)
	end
	return true, ("Класс: %s"):format(Config.ClassById[classId].Name)
end

local function learn(player, data, nodeId)
	local node = Config.SkillById[nodeId or ""]
	if not node or node.Class ~= data.Class then
		return false, "Этот навык не твоего класса"
	end
	local record = PlayerState.ClassRecord(data, data.Class)
	local ok, reason = ClassService.CanLearn(data, record, node)
	if not ok then
		return false, reason
	end
	record.Skills[node.Id] = rankOf(record, node.Id) + 1
	-- a new active goes to the first free slot
	if node.Active and record.Skills[node.Id] == 1 then
		for _, slot in ipairs(SK.Slots) do
			if not Config.SkillById[record.Loadout[slot] or ""] then
				record.Loadout[slot] = node.Id
				break
			end
		end
	end
	PlayerState.Sync(player)
	GameEvents.Fire(player, "Learn", 1)
	if ClassService.OnLearned then
		ClassService.OnLearned(player, node)
	end
	return true, T.Learned:format(node.Name)
end

local function reset(player, data)
	if (data.Class or "") == "" then
		return false, T.NeedClass
	end
	local record = PlayerState.ClassRecord(data, data.Class)
	if PlayerState.SpentPoints(record) == 0 then
		return false, "Нечего сбрасывать"
	end
	if record.Resets > 0 then
		local cost = SK.ResetCost(data.Level)
		if not PlayerState.SpendCredits(player, cost) then
			return false, ("Нужно %s нано-кредитов"):format(Format.Number(cost))
		end
	end
	record.Resets += 1
	record.Skills = {}
	record.Loadout = {}
	PlayerState.Sync(player)
	return true, T.Reset
end

local function equip(player, data, slot, nodeId)
	if not table.find(SK.Slots, slot) then
		return false, "Нет такого слота"
	end
	local record = PlayerState.ClassRecord(data, data.Class)
	if nodeId == nil then
		record.Loadout[slot] = nil
	else
		local node = Config.SkillById[nodeId]
		if not node or node.Class ~= data.Class or not node.Active or rankOf(record, nodeId) == 0 then
			return false, "Приём не изучен"
		end
		for _, other in ipairs(SK.Slots) do
			if record.Loadout[other] == nodeId then
				record.Loadout[other] = nil
			end
		end
		record.Loadout[slot] = nodeId
	end
	PlayerState.Sync(player)
	return true
end

function ClassService.Init(hub)
	local allow = RateLimit.new(0.15)
	Remotes.Get("Class").OnServerInvoke = function(player, action, a, b)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		local data = DataService.Get(player)
		if action == "Choose" then
			return choose(player, data, a)
		elseif (data.Class or "") == "" then
			return false, T.NeedClass
		elseif action == "Learn" then
			return learn(player, data, a)
		elseif action == "Reset" then
			return reset(player, data)
		elseif action == "Equip" then
			return equip(player, data, a, b)
		end
		return false, "Неверный запрос"
	end

	-- Academy: the terminal opens the class screen (client Prompts).
	local academy = hub and hub.Academy
	local terminal = academy and academy.Terminal
	local base = terminal and terminal:FindFirstChild("Base")
	if base then
		WorldKit.Prompt(base, Config.HubLayout.Prompts.Academy, "", { Action = "OpenClasses" }, 12)
	end
end

return ClassService
