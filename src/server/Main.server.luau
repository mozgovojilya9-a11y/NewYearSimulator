--[[
	Main.server.luau
	Entry point: builds the world, starts every service, wires player
	join/leave into DataService and exposes progress through leaderstats
	(Level, Room). Also runs the autosave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Atmosphere = require(script.Parent.Atmosphere)
local Bounds = require(script.Parent.Bounds)
local ClickService = require(script.Parent.ClickService)
local CraftService = require(script.Parent.CraftService)
local DataService = require(script.Parent.DataService)
local DevService = require(script.Parent.DevService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local EquipmentService = require(script.Parent.EquipmentService)
local HubService = require(script.Parent.HubService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local LootService = require(script.Parent.LootService)
local MobAI = require(script.Parent.MobAI)
local PetService = require(script.Parent.PetService)
local Passes = require(script.Parent.Passes)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)
local Remotes = require(script.Parent.Remotes)
local ShopService = require(script.Parent.ShopService)
local StatService = require(script.Parent.StatService)
local StoreService = require(script.Parent.StoreService)
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

-- Starts one service. An error in it is printed to Output with the
-- service name and does NOT stop the other services or player setup.
local function start(name: string, fn, ...)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn(("[Main] %s не запустился: %s"):format(name, tostring(err)))
	end
end

-- Create every RemoteEvent before any client can look for it.
Remotes.Init()
start("Passes", Passes.Init)
Passes.OnChanged = PlayerState.Sync
start("StatService", StatService.Init)
start("Atmosphere", Atmosphere.Init)
local hub = HubService.Init()
start("LeaderboardService", LeaderboardService.Init, hub.Leaderboards)
start("DungeonRuns", DungeonRuns.Init)
start("Bounds", Bounds.Init, hub)
start("MobAI", MobAI.Init)
start("ClickService", ClickService.Init)
start("ShopService", ShopService.Init)
start("CraftService", CraftService.Init, hub)
start("PetService", PetService.Init)
start("StoreService", StoreService.Init)
start("TravelService", TravelService.Init, hub)
start("EquipmentService", EquipmentService.Init)
start("ProgressionService", ProgressionService.Init)
start("LootService", LootService.Init) -- after ProgressionService: both listen to kills
start("DevService", DevService.Init) -- Studio only

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

	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = data.Level
	level.Parent = leaderstats

	local room = Instance.new("IntValue")
	room.Name = "Room"
	room.Value = data.RoomReached
	room.Parent = leaderstats

	-- Parented last: its appearance means "data is loaded" (PlayerState.IsReady,
	-- clients wait for it).
	leaderstats.Parent = player

	-- One-time messages from save migrations (e.g. clicker compensation).
	if type(data.Notice) == "string" and data.Notice ~= "" then
		local notice = data.Notice
		data.Notice = nil
		task.delay(6, function()
			if player.Parent then
				Remotes.Notify(player, notice, "gold")
			end
		end)
	end

	PlayerState.Sync(player)
	task.spawn(Passes.Load, player)
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
