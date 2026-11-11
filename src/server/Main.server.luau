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
local MobService = require(script.Parent.MobService)
local ShopService = require(script.Parent.ShopService)
local RebirthService = require(script.Parent.RebirthService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

-- Create every RemoteEvent before any client can look for it.
Remotes.Init()
ClickService.Init()
MobService.Init()
ShopService.Init()
RebirthService.Init()

local function onPlayerAdded(player)
	local data = DataService.Load(player)

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

	-- Keep the cached data table in sync whenever Aura changes, from
	-- wherever it changes (ClickService, later mobs/pets/rebirth).
	aura.Changed:Connect(function(newValue)
		data.Aura = newValue
	end)

	PlayerState.Sync(player)
end

local function onPlayerRemoving(player)
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
