--[[
	HubService.luau
	Builds the hub (HubGenerator) at server start and hands out its
	parts (portal, forge, prompts, leaderboards, spawn) to the services.
]]

local HubGenerator = require(script.Parent.HubGenerator)

local HubService = {}

local hub

function HubService.Init()
	hub = HubGenerator.Build()
	return hub
end

function HubService.Get()
	return hub
end

return HubService
