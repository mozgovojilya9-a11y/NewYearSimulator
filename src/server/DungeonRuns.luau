--[[
	DungeonRuns.luau
	Personal dungeon runs. Every portal entry starts a NEW run from room
	1 in the player's own lane (private mobs, private barriers). Only the
	current and the next room exist; passed rooms are destroyed.

	Run ends on: death, "Назад"/leaving, clearing room 20. The best room
	is kept in RoomReached (record for the leaderboard and rebirth).
	Mobs give no Aura; loot comes with the drop stage (LootService).
	Mob AI / player damage: see MobAI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonGenerator = require(script.Parent.DungeonGenerator)
local Effects = require(script.Parent.Effects)
local MobBuilder = require(script.Parent.MobBuilder)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local WorldKit = require(script.Parent.WorldKit)

local DungeonRuns = {}

local D = Config.Dungeon
local Looks = Config.MobLooks
local Texts = Config.DungeonLayout.Texts

local world -- DungeonGenerator.Init() result
local runs = {} -- [player] = run
local laneOwner = {} -- [lane] = player
local mobInfo = {} -- [model] = { run = run, room = index }

-- Hooks: MobAI listens to mob spawn/removal, TravelService to run end,
-- ProgressionService to kills / clears / run starts, LootService to
-- kills (position, kind, boss).
DungeonRuns.OnMobSpawned = nil
DungeonRuns.OnMobRemoved = nil
DungeonRuns.OnRunEnded = nil
DungeonRuns.OnKill = nil
DungeonRuns.OnRoomCleared = nil
DungeonRuns.OnRunStarted = nil

---------------------------------------------------------------------
-- Rooms and mobs
---------------------------------------------------------------------

local function buildMob(run, room, spot)
	local isBoss = room.IsBoss
	local look
	if isBoss then
		local bossDef = Looks.Bosses[room.Index]
		look = {}
		for _, kind in ipairs(Looks.Kinds) do
			if kind.Kind == bossDef.Kind then
				for k, v in pairs(kind) do
					look[k] = v
				end
			end
		end
		look.Name = bossDef.Name
		look.Color = bossDef.Color
	else
		look = Looks.Kinds[spot.Kind]
	end

	local facing = Vector3.new(room.Entry.Position.X, spot.Position.Y, room.Entry.Position.Z)
	local model = MobBuilder.Build(look, if isBoss then Looks.BossScale else 1, CFrame.lookAt(spot.Position, facing))
	if isBoss then
		MobBuilder.Decorate(model, Looks.Bosses[room.Index].Crown, Looks.BossScale)
	end
	local health = Config.MobHealth(room.Index, isBoss)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = health
	humanoid.Health = health
	model:SetAttribute("Room", room.Index)
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("Kind", look.Kind)
	model:SetAttribute("Damage", Config.MobDamage(room.Index, isBoss))
	local height = model:GetAttribute("Height") or 6
	WorldKit.HealthGui(model.PrimaryPart, if isBoss then look.Name else nil, height - (model.PrimaryPart.Position.Y - spot.Position.Y) + 1.5)
	WorldKit.UpdateHealth(model.PrimaryPart, health, health)
	model.Parent = room.Model
	return model
end

local function roomBarrierText(room, alive, total)
	if room.Barrier then
		local label = room.Barrier:FindFirstChild("Text") and room.Barrier.Text:FindFirstChild("Enemies")
		if label then
			label.Text = if alive <= 0 then Texts.Cleared else Texts.Enemies:format(total - alive, total)
			if alive <= 0 then
				label.TextColor3 = Config.Theme.Green
			end
		end
	end
end

-- The barrier is private, so its "Рекомендуемый урон" line can be
-- colored for this player: green when their damage is enough.
local function refreshRecommended(run, room)
	if not room or not room.Barrier then
		return
	end
	local label = room.Barrier:FindFirstChild("Text") and room.Barrier.Text:FindFirstChild("Recommended")
	if label then
		local enough = PlayerState.ClickPower(run.player) >= Config.RecommendedDamage(room.Index)
		label.TextColor3 = if enough then Config.Theme.Green else Config.Theme.Red
	end
end

local function openBarrier(room)
	local barrier = room.Barrier
	if not barrier then
		return
	end
	barrier.CanCollide = false
	TweenService:Create(barrier, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	task.delay(2, function()
		local gui = barrier:FindFirstChild("Text")
		if gui then
			gui.Enabled = false
		end
	end)
end

local function ensureRoom(run, index)
	if index > D.Rooms or run.rooms[index] then
		return
	end
	local x = DungeonGenerator.LaneX(run.lane)
	DungeonGenerator.BuildCorridor(run.folder, index, x)
	local room = DungeonGenerator.BuildRoom(run.folder, index, x)
	room.Alive = 0
	room.Total = #room.MobSpots
	room.Mobs = {}
	for _, spot in ipairs(room.MobSpots) do
		local model = buildMob(run, room, spot)
		mobInfo[model] = { run = run, room = index }
		room.Mobs[model] = true
		room.Alive += 1
		if DungeonRuns.OnMobSpawned then
			DungeonRuns.OnMobSpawned(run, model)
		end
	end
	run.rooms[index] = room
	refreshRecommended(run, room)
end

local function destroyRoom(run, index)
	local room = run.rooms[index]
	if not room then
		return
	end
	for model in pairs(room.Mobs) do
		mobInfo[model] = nil
		if DungeonRuns.OnMobRemoved then
			DungeonRuns.OnMobRemoved(model)
		end
	end
	room.Model:Destroy()
	local corridor = run.folder:FindFirstChild(("Corridor%02d"):format(index))
	if corridor then
		corridor:Destroy()
	end
	run.rooms[index] = nil
end

---------------------------------------------------------------------
-- Runs
---------------------------------------------------------------------

local function freeLane(): number?
	for lane = 1, D.Lanes.Max do
		if not laneOwner[lane] then
			return lane
		end
	end
	return nil
end

local function endRun(player, reason: string)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	laneOwner[run.lane] = nil
	if run.diedConnection then
		run.diedConnection:Disconnect()
	end
	for index in pairs(run.rooms) do
		destroyRoom(run, index)
	end
	run.folder:Destroy()

	local record = PlayerState.GetRoomReached(player)
	Remotes.Get("RunEnded"):FireClient(player, reason, run.best, run.loot, record, run.newRecord)
	player:SetAttribute("Zone", "Hub")
	if reason ~= "Died" and DungeonRuns.OnRunEnded then
		DungeonRuns.OnRunEnded(player)
	end
end

function DungeonRuns.EndRun(player, reason: string?)
	endRun(player, reason or "Left")
end

function DungeonRuns.HasRun(player): boolean
	return runs[player] ~= nil
end

function DungeonRuns.GetRun(player)
	return runs[player]
end

-- Starts a fresh run. Returns the entry CFrame or nil, message.
function DungeonRuns.StartRun(player)
	if runs[player] then
		endRun(player, "Left")
	end
	local lane = freeLane()
	if not lane then
		return nil, "Все полосы заняты, попробуй через минуту"
	end
	local run = {
		player = player,
		lane = lane,
		folder = DungeonGenerator.LaneFolder(lane),
		rooms = {},
		current = 1,
		best = 0,
		loot = {}, -- [materialId] = count picked up this run (LootService fills it)
		newRecord = false,
	}
	runs[player] = run
	laneOwner[lane] = player
	for index = 1, 1 + D.RoomsAhead do
		ensureRoom(run, index)
	end
	for index, room in pairs(run.rooms) do
		roomBarrierText(room, room.Alive, room.Total)
		Remotes.Get("RoomState"):FireClient(player, index, room.Alive, room.Total)
	end
	if DungeonRuns.OnRunStarted then
		DungeonRuns.OnRunStarted(player)
	end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		run.diedConnection = humanoid.Died:Connect(function()
			if runs[player] == run then
				endRun(player, "Died")
			end
		end)
	end
	return run.rooms[1].Entry
end

-- Entry CFrame of the room the run is currently in (for fall recovery).
function DungeonRuns.CurrentEntry(player): CFrame?
	local run = runs[player]
	local room = run and run.rooms[run.current]
	return room and room.Entry
end

local function roomCleared(run, index)
	local room = run.rooms[index]
	openBarrier(room)
	run.best = math.max(run.best, index)
	if DungeonRuns.OnRoomCleared then
		DungeonRuns.OnRoomCleared(run.player, index)
	end
	if PlayerState.ReachRoom(run.player, index) then
		run.newRecord = true
		Remotes.Notify(run.player, Texts.NewRecord, "gold")
	end
	if index == D.Rooms then
		Remotes.Notify(run.player, Texts.RunWon, "gold")
		task.delay(4, function()
			if runs[run.player] == run then
				endRun(run.player, "Won")
			end
		end)
		return
	end
	Remotes.Notify(run.player, ("Этап %d пройден!"):format(index), "gold")
	run.current = index + 1
	ensureRoom(run, index + 1 + D.RoomsAhead)
	local nextRoom = run.rooms[index + 1 + D.RoomsAhead]
	if nextRoom then
		Remotes.Get("RoomState"):FireClient(run.player, nextRoom.Index, nextRoom.Alive, nextRoom.Total)
	end
	destroyRoom(run, index - 1)
end

local function kill(model)
	local info = mobInfo[model]
	mobInfo[model] = nil
	local run = info.run
	local room = run.rooms[info.room]
	if DungeonRuns.OnMobRemoved then
		DungeonRuns.OnMobRemoved(model)
	end

	local position = model:GetPivot().Position
	local isBoss = model:GetAttribute("Boss") == true
	local kind = model:GetAttribute("Kind")
	local color = (model:FindFirstChild("Torso") or model.PrimaryPart).Color
	model:Destroy()
	Effects.Burst(position, color, if isBoss then 90 else 25, if isBoss then 35 else 22, if isBoss then 2 else 1)

	local player = run.player
	Remotes.Get("ClickHit"):FireClient(player, "Kill", position, isBoss)
	if DungeonRuns.OnKill then
		DungeonRuns.OnKill(player, info.room, isBoss, position, kind)
	end

	if room then
		room.Mobs[model] = nil
		room.Alive -= 1
		roomBarrierText(room, room.Alive, room.Total)
		Remotes.Get("RoomState"):FireClient(player, info.room, room.Alive, room.Total)
		if room.Alive <= 0 then
			roomCleared(run, info.room)
		end
	end
end

function DungeonRuns.IsMob(model): boolean
	return mobInfo[model] ~= nil
end

-- Called by ClickService after cooldown and range checks.
function DungeonRuns.Hit(player, model)
	local info = mobInfo[model]
	if not info or info.run.player ~= player then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local damage, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player))
	humanoid.Health = math.max(0, humanoid.Health - damage)
	WorldKit.UpdateHealth(model.PrimaryPart, humanoid.Health, humanoid.MaxHealth)
	Remotes.Get("ClickHit"):FireClient(player, "Hit", model, damage, isCrit)
	if humanoid.Health <= 0 then
		kill(model)
	end
end

-- Weapon changed mid-run: recolor the hint on the rooms that exist.
function DungeonRuns.RefreshHints(player)
	local run = runs[player]
	if run then
		for _, room in pairs(run.rooms) do
			refreshRecommended(run, room)
		end
	end
end

function DungeonRuns.RunOf(model)
	local info = mobInfo[model]
	return info and info.run
end

function DungeonRuns.Init()
	world = DungeonGenerator.Init()
	Players.PlayerRemoving:Connect(function(player)
		if runs[player] then
			endRun(player, "Left")
		end
	end)
	local function watch(player)
		player.CharacterRemoving:Connect(function()
			if runs[player] then
				endRun(player, "Died")
			end
		end)
		player:GetAttributeChangedSignal("ClickPower"):Connect(function()
			DungeonRuns.RefreshHints(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
end

return DungeonRuns
