--[[
	Main.server.luau
	Entry point: builds the world, starts every service, wires player
	join/leave into DataService and exposes progress through leaderstats
	(Aura, Rebirths, Room). Also runs the autosave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Atmosphere = require(script.Parent.Atmosphere)
local ClickService = require(script.Parent.ClickService)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local EquipmentService = require(script.Parent.EquipmentService)
local HubService = require(script.Parent.HubService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MobAI = require(script.Parent.MobAI)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)
local RebirthService = require(script.Parent.RebirthService)
local Remotes = require(script.Parent.Remotes)
local ShopService = require(script.Parent.ShopService)
local TravelService = require(script.Parent.TravelService)

-- Workspace is not managed by Rojo, so leftovers of older versions of
-- the place survive a sync. Remove everything except Config.World.Keep;
-- the hub and dungeon are generated right after.
local function purgeWorkspace()
	local keep = {}
	for _, name in ipairs(Config.World.Keep) do
		keep[name] = true
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if not keep[child.Name] and not child:IsA("Terrain") and not child:IsA("Camera") then
			child:Destroy()
		end
	end
end
if Config.World.PurgeWorkspace then
	purgeWorkspace()
end

-- Create every RemoteEvent before any client can look for it.
Remotes.Init()
Atmosphere.Init()
local hub = HubService.Init()
LeaderboardService.Init(hub.Leaderboards)
DungeonRuns.Init()
MobAI.Init()
ClickService.Init(hub.Trainers)
ShopService.Init()
RebirthService.Init()
TravelService.Init(hub)
EquipmentService.Init()
ProgressionService.Init()
HubService.OnTrainerClick = ProgressionService.OnTrainerClick

local started = {} -- players whose setup already ran (PlayerAdded + the startup loop can both fire)

local function onPlayerAdded(player)
	if started[player] then
		return
	end
	started[player] = true
	player:SetAttribute("Zone", "Hub")

	local data = DataService.Load(player)
	if not data then
		return -- left while loading
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local aura = Instance.new("IntValue")
	aura.Name = "Aura"
	aura.Value = data.Aura
	aura.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths
	rebirths.Parent = leaderstats

	local room = Instance.new("IntValue")
	room.Name = "Room"
	room.Value = data.RoomReached
	room.Parent = leaderstats

	-- Keep the cached data table in sync whenever Aura changes.
	aura.Changed:Connect(function(newValue)
		data.Aura = newValue
	end)

	PlayerState.Sync(player)
	ProgressionService.RefreshReady(player)
end

local function onPlayerRemoving(player)
	started[player] = nil
	DataService.Release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- In Studio the local player can join before this script connects.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Safety-net autosave loop in case of a crash before PlayerRemoving fires.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.Save(player)
		end
	end
end)
