--[[
	Main.server.luau
	Entry point: wires up player join/leave to DataService, and exposes
	current progress through standard Roblox leaderstats so the top bar
	UI (and the default Roblox leaderboard) can read it.
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ClickService = require(script.Parent.ClickService)
local DungeonService = require(script.Parent.DungeonService)
local ShopService = require(script.Parent.ShopService)
local RebirthService = require(script.Parent.RebirthService)
local TravelService = require(script.Parent.TravelService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

-- Create every RemoteEvent before any client can look for it.
Remotes.Init()
DungeonService.Init()
ClickService.Init(nil)
ShopService.Init()
RebirthService.Init()
TravelService.Init()

local started = {} -- players whose setup already ran (PlayerAdded + the startup loop can both fire)

local function onPlayerAdded(player)
	if started[player] then
		return
	end
	started[player] = true

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

	-- Keep the cached data table in sync whenever Aura changes, from
	-- wherever it changes (clicks, mobs, backpacks, rebirth).
	aura.Changed:Connect(function(newValue)
		data.Aura = newValue
	end)

	PlayerState.Sync(player)
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

-- Day 5: passive income from backpacks, once per second.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			if PlayerState.IsReady(player) then
				local perSecond = PlayerState.BasePerSecond(player)
				if perSecond > 0 then
					PlayerState.GiveAura(player, perSecond)
				end
			end
		end
	end
end)

-- Safety-net autosave loop in case of a crash before PlayerRemoving fires.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.Save(player)
		end
	end
end)
