--[[
	DevService.luau
	DEV panel actions for testing. Exists ONLY in Studio
	(RunService:IsStudio()): in a published game the "Dev" remote is never
	created, so nothing here can be called.

	Dev:InvokeServer(action, arg) -> ok, message
	  "Reset"      fresh progress (everything back to the start)
	  "Level", n   +n levels (1 or 5)
	  "Credits"    +Config.Dev.Credits Нано-кредиты
	  "Materials"  +Config.Dev.Materials of every material (all rarities)
	  "Item", rarityId   a random weapon or armor piece of that rarity
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)

local DevService = {}

local function randomItem(rarityId: string)
	local pool = {}
	for _, weapon in ipairs(Config.Weapons) do
		if weapon.Rarity == rarityId and not weapon.Legacy then
			table.insert(pool, { kind = "Weapon", item = weapon })
		end
	end
	for _, piece in ipairs(Config.Armor) do
		if piece.Rarity == rarityId then
			table.insert(pool, { kind = "Armor", item = piece })
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(#pool)]
end

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

function actions.Materials(player)
	for _, material in ipairs(Config.Materials) do
		PlayerState.AddMaterial(player, material.Id, Config.Dev.Materials)
	end
	return true, ("+%d каждого материала"):format(Config.Dev.Materials)
end

function actions.Item(player, rarityId)
	local rarity = type(rarityId) == "string" and Config.Rarity[rarityId]
	if not rarity then
		return false, "Нет такой редкости"
	end
	local pick = randomItem(rarityId)
	if not pick then
		return false, ("Нет предметов редкости «%s»"):format(rarity.Name)
	end
	local data = DataService.Get(player)
	local item = pick.item
	if pick.kind == "Weapon" then
		data.OwnedWeapons[item.Id] = true
		data.EquippedWeapon = item.Id
	else
		data.OwnedArmor[item.Id] = true
		data.EquippedArmor[item.Slot] = item.Id
	end
	PlayerState.Sync(player)
	return true, ("Получено и надето: %s"):format(item.Name)
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
