--[[
	TravelService.luau
	Moves characters between the hub and the dungeon and keeps the
	player's "Zone" attribute ("Hub" | "Dungeon") up to date.

	- Travel:InvokeServer("Dungeon") or touching the portal starts a NEW
	  run (DungeonRuns.StartRun) and teleports to room 1 of its lane.
	- Travel:InvokeServer("Hub"), key B / Back button, ends the run and
	  teleports to the hub spawn.
]]

local Players = game:GetService("Players")

local DungeonRuns = require(script.Parent.DungeonRuns)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local TravelService = {}

local hub

local function teleport(player, cframe: CFrame, zone: string)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, "Персонаж ещё не появился"
	end
	character:PivotTo(cframe)
	player:SetAttribute("Zone", zone)
	return true, zone
end

function TravelService.ToHub(player, reason: string?)
	if DungeonRuns.HasRun(player) then
		DungeonRuns.EndRun(player, reason or "Left")
	end
	return teleport(player, hub.SpawnCFrame, "Hub")
end

function TravelService.EnterDungeon(player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, "Персонаж ещё не появился"
	end
	local entry, message = DungeonRuns.StartRun(player)
	if not entry then
		return false, message
	end
	return teleport(player, entry, "Dungeon")
end

function TravelService.Init(hubInfo)
	hub = hubInfo
	local allow = RateLimit.new(1)

	-- Runs that end without a death (Back, room 20, leaving) return here.
	DungeonRuns.OnRunEnded = function(player)
		teleport(player, hub.SpawnCFrame, "Hub")
	end

	Remotes.Get("Travel").OnServerInvoke = function(player, destination)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if destination == "Hub" then
			return TravelService.ToHub(player, "Left")
		elseif destination == "Dungeon" then
			return TravelService.EnterDungeon(player)
		end
		return false, "Неверный запрос"
	end

	local portalAllow = RateLimit.new(2)
	hub.Portal.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and PlayerState.IsReady(player) and portalAllow(player) and not DungeonRuns.HasRun(player) then
			TravelService.EnterDungeon(player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Zone", "Hub")
		end)
	end)
end

return TravelService
