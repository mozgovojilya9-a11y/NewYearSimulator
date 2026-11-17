--[[
	TravelService.luau
	Moves characters between the hub and the gate runs and keeps the
	player's "Zone" attribute ("Hub" | "Dungeon") up to date.

	- Entering the gates: GateService (Gate remote, the gates window).
	- Touching the big gate in the Gate hall opens the gates window
	  (GateState "Open" to that player).
	- Travel:InvokeServer("Hub"), key B / the "В хаб" button, leaves the
	  run and teleports to the hub spawn. Red Gates can't be left before
	  their boss is down.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
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
		if not DungeonRuns.CanLeave(player) then
			return false, Config.RedGate.Texts.NoExit
		end
		DungeonRuns.EndRun(player, reason or "Left")
		return true, "Hub" -- OnRunEnded teleports
	end
	return teleport(player, hub.SpawnCFrame, "Hub")
end

function TravelService.Init(hubInfo)
	hub = hubInfo
	local allow = RateLimit.new(1)

	-- Runs that end without a death (leaving, a closed location) return here.
	DungeonRuns.OnRunEnded = function(player)
		teleport(player, hub.SpawnCFrame, "Hub")
	end

	Remotes.Get("Travel").OnServerInvoke = function(player, destination)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if destination == "Hub" then
			local ok, message = TravelService.ToHub(player, "Left")
			if not ok then
				Remotes.Notify(player, message, "bad")
			end
			return ok, message
		end
		return false, "Неверный запрос"
	end

	-- the big gate opens the gates window
	local portalAllow = RateLimit.new(3)
	hub.Portal.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and PlayerState.IsReady(player) and portalAllow(player) and not DungeonRuns.HasRun(player) then
			Remotes.Get("GateState"):FireClient(player, "Open")
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if not DungeonRuns.HasRun(player) then
				player:SetAttribute("Zone", "Hub")
			end
		end)
	end)
end

return TravelService
