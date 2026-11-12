--[[
	Passes.luau
	Game pass ownership with a per-player cache. Config.GamePasses holds
	the ids; Id = 0 means the pass does not exist yet (never owned, the
	UI shows "Скоро"). Ownership is checked once on join
	(UserOwnsGamePassAsync) and updated instantly after an in-game
	purchase (PromptGamePassPurchaseFinished). The client reads the
	"Passes" player attribute ("VIP,AutoClick,...").
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Passes = {}

local owned = {} -- [player] = { [key] = true }

Passes.OnChanged = nil -- set by Main: re-sync stats after a pass arrives

local function publish(player)
	local list = {}
	for key in pairs(owned[player] or {}) do
		table.insert(list, key)
	end
	table.sort(list)
	player:SetAttribute("Passes", table.concat(list, ","))
	if Passes.OnChanged then
		Passes.OnChanged(player)
	end
end

function Passes.Owns(player, key: string): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
end

function Passes.Grant(player, key: string)
	if not Config.GamePasses[key] then
		return
	end
	owned[player] = owned[player] or {}
	if not owned[player][key] then
		owned[player][key] = true
		publish(player)
	end
end

-- Yields: asks Roblox about every configured pass. Call in a new thread.
function Passes.Load(player)
	owned[player] = owned[player] or {}
	for key, pass in pairs(Config.GamePasses) do
		if pass.Id > 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and has and player.Parent then
				owned[player][key] = true
			end
		end
	end
	if player.Parent then
		publish(player)
	else
		owned[player] = nil
	end
end

function Passes.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in pairs(Config.GamePasses) do
			if pass.Id == passId then
				Passes.Grant(player, key)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return Passes
