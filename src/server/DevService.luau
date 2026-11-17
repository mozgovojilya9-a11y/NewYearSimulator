--[[
	DevService.luau
	DEV panel actions for testing. Exists ONLY in Studio
	(RunService:IsStudio()): in a published game the "Dev" remote is never
	created, so nothing here can be called.

	Dev:InvokeServer(action, arg) -> ok, message
	  "Reset"      fresh progress (everything back to the start)
	  "Level", n   +n levels (1 or 5)
	  "Credits"    +Config.Dev.Credits Нано-кредиты
	  "Cores"      +Config.Dev.Cores Нано-ядра
	  "Item", rarityId   a random weapon or armor piece of that rarity
	  "Drop", "Item" | "Chest"   a drop / boss chest on the ground
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ArtifactService = require(script.Parent.ArtifactService)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local ItemService = require(script.Parent.ItemService)
local LootService = require(script.Parent.LootService)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)

local DevService = {}

local actions = {}

function actions.Reset(player)
	if DungeonRuns.HasRun(player) then
		DungeonRuns.EndRun(player, "Left")
	end
	DataService.Reset(player)
	PlayerState.Sync(player)
	player:LoadCharacter()
	return true, "Прогресс сброшен"
end

function actions.Level(player, count)
	count = if count == 5 then 5 else 1
	ProgressionService.GrantLevels(player, count)
	return true, ("+%d ур."):format(count)
end

function actions.Credits(player)
	PlayerState.AddCredits(player, Config.Dev.Credits)
	return true, ("+%d кредитов"):format(Config.Dev.Credits)
end

function actions.Cores(player)
	PlayerState.AddCores(player, Config.Dev.Cores)
	return true, ("+%d нано-ядер"):format(Config.Dev.Cores)
end

-- A random weapon or armor piece of that rarity at the player's progress.
function actions.Item(player, rarityId)
	local rarity = type(rarityId) == "string" and Config.Rarity[rarityId]
	if not rarity then
		return false, "Нет такой редкости"
	end
	local data = DataService.Get(player)
	local level = math.max(1, data.RoomReached) * Config.Items.LevelPerRoom
	local view = ItemService.Give(player, ItemService.Generate(player, level, rarityId), { Force = true })
	return true, ("Получено: %s"):format(view.Name)
end

-- Drops on the ground next to the player: "Item" / "Chest".
function actions.Drop(player, what)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "Нет персонажа"
	end
	local data = DataService.Get(player)
	local room = math.max(1, data.RoomReached)
	local position = root.Position + root.CFrame.LookVector * 8 - Vector3.new(0, 3, 0)
	if what == "Chest" then
		LootService.DropChest(player, room, position)
		return true, "Сундук босса"
	end
	LootService.DropItem(player, room, "Boss", position)
	return true, "Предмет на земле"
end

-- A random artifact (or the next copy of one).
function actions.Artifact(player)
	local id = ArtifactService.Roll(player, "S")
	ArtifactService.Give(player, id)
	return true, "Артефакт: " .. Config.ArtifactById[id].Name
end

-- Gates: open every rank (marks a location of each ready rank cleared),
-- start the Red Gates now.
function actions.Unlock(player)
	local data = DataService.Get(player)
	data.Gates = if type(data.Gates) == "table" then data.Gates else { Cleared = {} }
	data.Gates.Cleared = data.Gates.Cleared or {}
	for _, location in ipairs(Config.Gates.Locations) do
		if location.Ready and not data.Gates.Cleared[location.Id] then
			data.Gates.Cleared[location.Id] = "C"
		end
	end
	data.Level = math.max(data.Level, 16)
	PlayerState.Sync(player)
	require(script.Parent.GateService).Publish(player)
	return true, "Ранги E и D открыты"
end

function actions.Red()
	require(script.Parent.GateService).OpenRed()
	return true, "Красные Врата открыты"
end

function DevService.Init()
	if not RunService:IsStudio() then
		return -- never in a live game
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = "Dev"
	remote.Parent = ReplicatedStorage
	remote.OnServerInvoke = function(player, action, arg)
		local fn = actions[action]
		if not fn or not PlayerState.IsReady(player) then
			return false, "Неверный запрос"
		end
		return fn(player, arg)
	end
end

return DevService
