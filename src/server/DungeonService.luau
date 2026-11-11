--[[
	DungeonService.luau
	Dungeon rules: spawning room mobs, click damage, Aura drops, boss pet
	drops, room clearing, barrier counters and progress (RoomReached).

	- A player may damage mobs in room r only if RoomReached >= r - 1.
	- When a mob dies, every player who damaged it gets an Aura crystal
	  (Dungeon.Drops) worth the full reward. Touching it, or the "E"
	  prompt, collects it; after Config.Dungeon.DropLifetime it is
	  collected automatically so nothing is ever lost.
	- When the last mob of a room dies, every player who damaged any
	  mob in that room gets credit (RoomReached = r). The room respawns
	  after a delay. Barriers stay solid on the server; each client
	  dissolves the barriers of rooms that player has cleared.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DungeonGenerator = require(script.Parent.DungeonGenerator)
local Effects = require(script.Parent.Effects)
local MobBuilder = require(script.Parent.MobBuilder)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local WorldKit = require(script.Parent.WorldKit)

local DungeonService = {}

local D = Config.Dungeon
local Looks = Config.MobLooks
local dungeon -- result of DungeonGenerator.Build()
local mobInfo = {} -- [model] = { room = r, damagers = { [player] = true } }
local roomState = {} -- [r] = { alive = number, total = number, participants = { [player] = true } }
local drops = {} -- [part] = { player = Player, amount = number }

---------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------

local function buildMob(room, spot)
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
	local cframe = CFrame.lookAt(spot.Position, facing)
	local model = MobBuilder.Build(look, if isBoss then Looks.BossScale else 1, cframe)
	if isBoss then
		MobBuilder.Decorate(model, Looks.Bosses[room.Index].Crown, Looks.BossScale)
	end

	local health = Config.MobHealth(room.Index, isBoss)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = health
	humanoid.Health = health

	model:SetAttribute("Room", room.Index)
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("Reward", Config.MobReward(room.Index, isBoss))

	local height = model:GetAttribute("Height") or 6
	WorldKit.HealthGui(model.PrimaryPart, if isBoss then look.Name else nil, height - (model.PrimaryPart.Position.Y - spot.Position.Y) + 1.5)
	WorldKit.UpdateHealth(model.PrimaryPart, health, health)

	model.Parent = dungeon.Mobs
	return model
end

local function broadcastRoom(index)
	local state = roomState[index]
	local room = dungeon.Rooms[index]
	if room.Barrier then
		room.Barrier:SetAttribute("Alive", state.alive)
		room.Barrier:SetAttribute("Total", state.total)
		local label = room.Barrier:FindFirstChild("Text") and room.Barrier.Text:FindFirstChild("Enemies")
		if label then
			label.Text = Config.DungeonLayout.Texts.Enemies:format(state.total - state.alive, state.total)
		end
	end
	Remotes.Get("RoomState"):FireAllClients(index, state.alive, state.total)
end

local function spawnRoom(index)
	local room = dungeon.Rooms[index]
	local state = roomState[index]
	state.alive = 0
	state.total = #room.MobSpots
	state.participants = {}
	for _, spot in ipairs(room.MobSpots) do
		local model = buildMob(room, spot)
		mobInfo[model] = { room = index, damagers = {} }
		state.alive += 1
	end
	broadcastRoom(index)
end

---------------------------------------------------------------------
-- Drops
---------------------------------------------------------------------

local function collect(part)
	local drop = drops[part]
	if not drop then
		return
	end
	drops[part] = nil
	local player = drop.player
	if player.Parent and PlayerState.IsReady(player) then
		local gained = PlayerState.GiveAura(player, drop.amount)
		Remotes.Get("ClickHit"):FireClient(player, "Pickup", part.Position, gained)
	end
	part:Destroy()
end

local function spawnDrop(player, position: Vector3, amount: number, index: number)
	local look = Looks.Drop
	local offset = Vector3.new(math.cos(index) * 2.5, 0, math.sin(index) * 2.5)
	local crystal = WorldKit.Part(dungeon.Drops, {
		Name = "AuraCrystal",
		Size = Vector3.new(1.6, 2.6, 1.6),
		CFrame = CFrame.new(position + offset + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = look.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
	})
	crystal:SetAttribute("Owner", player.UserId)
	crystal:SetAttribute("Amount", amount)
	TweenService:Create(crystal, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = crystal.CFrame * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0) }):Play()
	WorldKit.Beam(crystal, crystal.Position, crystal.Position + Vector3.new(0, 14, 0), ColorSequence.new(look.BeamColor, Color3.new(1, 1, 1)), 2)
	WorldKit.Light(crystal, look.Color, 12, 1.5)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(5, 0, 1.2, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = crystal
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Config.Theme.Font
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Text
	label.Text = "+" .. Format.Number(amount)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Config.Theme.Outline
	stroke.Parent = label

	local prompt = WorldKit.Prompt(crystal, Config.HubLayout.Prompts.Collect, "Аура", { Action = "Collect" }, 10)
	prompt.Triggered:Connect(function(who)
		if who == player then
			collect(crystal)
		end
	end)
	crystal.Touched:Connect(function(hit)
		local character = player.Character
		if character and hit:IsDescendantOf(character) then
			collect(crystal)
		end
	end)

	drops[crystal] = { player = player, amount = amount }
	task.delay(D.DropLifetime, collect, crystal)
end

---------------------------------------------------------------------
-- Kills and room clears
---------------------------------------------------------------------

local function rollPetDrop(player)
	for _, drop in ipairs(D.BossPetDrops) do
		if math.random() < drop.Chance and PlayerState.GrantPet(player, drop.PetId) then
			Remotes.Notify(player, "🐾 Новый питомец: " .. Config.ItemById.Pet[drop.PetId].Name .. "!", "gold")
			return
		end
	end
end

local function roomCleared(index)
	local state = roomState[index]
	for player in pairs(state.participants) do
		if player.Parent and PlayerState.ReachRoom(player, index) then
			if index == D.Rooms then
				Remotes.Notify(player, "🏆 Данж пройден! Иди к алтарю перерождения", "gold")
			else
				Remotes.Notify(player, ("Этап %d пройден!"):format(index), "gold")
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
	local color = (model:FindFirstChild("Torso") or model.PrimaryPart).Color
	model:Destroy()
	Effects.Burst(position, color, if isBoss then 90 else 25, if isBoss then 35 else 22, if isBoss then 2 else 1)

	local remote = Remotes.Get("ClickHit")
	local i = 0
	for player in pairs(info.damagers) do
		if player.Parent and PlayerState.IsReady(player) then
			i += 1
			remote:FireClient(player, "Kill", position, isBoss)
			spawnDrop(player, position, reward, i)
			if isBoss then
				rollPetDrop(player)
			end
		end
	end

	local state = roomState[info.room]
	state.alive -= 1
	broadcastRoom(info.room)
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

function DungeonService.GetRoomState(index)
	return roomState[index]
end

function DungeonService.Init()
	dungeon = DungeonGenerator.Build()
	for index = 1, D.Rooms do
		roomState[index] = { alive = 0, total = 0, participants = {} }
		spawnRoom(index)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- Collect pending crystals first so the reward lands in the save.
		for part, drop in pairs(drops) do
			if drop.player == player then
				collect(part)
			end
		end
		for _, info in pairs(mobInfo) do
			info.damagers[player] = nil
		end
		for _, state in pairs(roomState) do
			state.participants[player] = nil
		end
	end)
end

return DungeonService
