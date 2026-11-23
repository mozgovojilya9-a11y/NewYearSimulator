--[[
	HubService.luau
	Builds the hub (HubCitadel) at server start and hands out its
	parts (portal, forge, prompts, leaderboards, spawn) to the services.
]]

local HubCitadel = require(script.Parent.HubCitadel)

local HubService = {}

local hub

function HubService.Init()
	hub = HubCitadel.Build()
	return hub
end

function HubService.Get()
	return hub
end

return HubService
