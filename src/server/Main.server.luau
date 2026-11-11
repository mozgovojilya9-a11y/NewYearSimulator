--[[
	Main.server.luau
	Entry point: wires up player join/leave to DataService, and exposes
	current progress through standard Roblox leaderstats so the top bar
	UI (and the default Roblox leaderboard) can read it.
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local ClickService = require(script.Parent.ClickService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

-- Create the ClickHit RemoteEvent before any client can look for it.
ClickService.Init()

local function onPlayerAdded(player)
	local data = DataService.Load(player)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local aura = Instance.new("IntValue")
	aura.Name = "Aura"
	aura.Value = data.Aura
	aura.Parent = leaderstats

	-- Keep the cached data table in sync whenever Aura changes, from
	-- wherever it changes (ClickService, later mobs/pets/rebirth).
	aura.Changed:Connect(function(newValue)
		data.Aura = newValue
	end)
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

-- Safety-net autosave loop in case of a crash before PlayerRemoving fires.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.Save(player)
		end
	end
end)
