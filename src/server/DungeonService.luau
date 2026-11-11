--[[
	DungeonService.luau
	Dungeon rules: spawning room mobs, applying click damage, rewards,
	boss pet drops, room clearing and dungeon progress (RoomReached).

	- A player may damage mobs in room r only if RoomReached >= r - 1.
	- Everyone who damaged a mob gets its full Aura reward when it dies.
	- When the last mob of a room dies, every player who damaged any
	  mob in that room gets credit for clearing it (RoomReached = r),
	  which opens the exit door for them. The room respawns after a delay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonGenerator = require(script.Parent.DungeonGenerator)
local Effects = require(script.Parent.Effects)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local WorldKit = require(script.Parent.WorldKit)

local DungeonService = {}

local D = Config.Dungeon
local dungeon -- result of DungeonGenerator.Build()
local mobInfo = {} -- [model] = { room = r, damagers = { [player] = true } }
local roomState = {} -- [r] = { alive = number, participants = { [player] = true } }

local function spawnRoom(index)
	local room = dungeon.Rooms[index]
	local state = roomState[index]
	state.alive = 0
	state.participants = {}
	for _, spot in ipairs(room.MobSpots) do
		local model = DungeonGenerator.BuildMob(room, spot)
		mobInfo[model] = { room = index, damagers = {} }
		state.alive += 1
	end
end

local function rollPetDrop(player)
	for _, drop in ipairs(D.BossPetDrops) do
		if math.random() < drop.Chance and PlayerState.GrantPet(player, drop.PetId) then
			Remotes.Notify(player, "🐾 Выпал питомец: " .. Config.ItemById.Pet[drop.PetId].Name .. "!", "gold")
			return
		end
	end
end

local function roomCleared(index)
	local state = roomState[index]
	for player in pairs(state.participants) do
		if player.Parent and PlayerState.ReachRoom(player, index) then
			if index == D.Rooms then
				Remotes.Notify(player, "🏆 Данж пройден! Иди к алтарю ребёрта в хабе", "gold")
			else
				Remotes.Notify(player, ("Комната %d пройдена! Дверь открыта"):format(index), "gold")
			end
		end
	end
	state.participants = {}

	local delay = if dungeon.Rooms[index].IsBoss then D.BossRespawnDelay else D.RoomRespawnDelay
	task.delay(delay, spawnRoom, index)
end

local function kill(model)
	local info = mobInfo[model]
	mobInfo[model] = nil

	local position = model:GetPivot().Position
	local reward = model:GetAttribute("Reward")
	local isBoss = model:GetAttribute("Boss") == true
	local color = model.PrimaryPart.Color
	model:Destroy()
	Effects.Burst(position, color, if isBoss then 90 else 25, if isBoss then 35 else 22, if isBoss then 2 else 1)

	local remote = Remotes.Get("ClickHit")
	for player in pairs(info.damagers) do
		if player.Parent and PlayerState.IsReady(player) then
			local gained = PlayerState.GiveAura(player, reward)
			remote:FireClient(player, "Kill", position, gained)
			if isBoss then
				rollPetDrop(player)
			end
		end
	end

	local state = roomState[info.room]
	state.alive -= 1
	if state.alive <= 0 then
		roomCleared(info.room)
	end
end

function DungeonService.IsMob(model): boolean
	return mobInfo[model] ~= nil
end

-- Called by ClickService after the cooldown and range checks.
function DungeonService.Hit(player, model)
	local info = mobInfo[model]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not info or not humanoid or humanoid.Health <= 0 then
		return
	end
	if PlayerState.GetRoomReached(player) < info.room - 1 then
		return -- hasn't unlocked this room (the client shows the hint)
	end

	local damage, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player))
	humanoid.Health = math.max(0, humanoid.Health - damage)
	info.damagers[player] = true
	roomState[info.room].participants[player] = true
	WorldKit.UpdateHealth(model.PrimaryPart, humanoid.Health, humanoid.MaxHealth)

	Remotes.Get("ClickHit"):FireClient(player, "Hit", model, damage, isCrit)

	if humanoid.Health <= 0 then
		kill(model)
	end
end

function DungeonService.GetRoom(index)
	return dungeon.Rooms[index]
end

function DungeonService.Init()
	dungeon = DungeonGenerator.Build()
	for index = 1, D.Rooms do
		roomState[index] = { alive = 0, participants = {} }
		spawnRoom(index)
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, info in pairs(mobInfo) do
			info.damagers[player] = nil
		end
		for _, state in pairs(roomState) do
			state.participants[player] = nil
		end
	end)
end

return DungeonService
