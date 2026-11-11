--[[
	TravelService.luau
	Moves characters between the hub and the dungeon and keeps the
	player's "Zone" attribute ("Hub" | "Dungeon") up to date, which the
	client uses for lighting, the objective text and the Back button.

	- Travel:InvokeServer("Hub") / ("Room", n) -> ok, message
	  (n must be unlocked: RoomReached >= n - 1).
	- Touching the hub portal sends the player to their furthest
	  unlocked room.
	- Key B / the Back button on the client call Travel("Hub").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonService = require(script.Parent.DungeonService)
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

function TravelService.ToHub(player)
	return teleport(player, hub.SpawnCFrame, "Hub")
end

function TravelService.ToRoom(player, room: number)
	if type(room) ~= "number" or room ~= math.floor(room) or room < 1 or room > Config.Dungeon.Rooms then
		return false, "Неверная комната"
	end
	if PlayerState.GetRoomReached(player) < room - 1 then
		return false, "Этап ещё закрыт"
	end
	return teleport(player, DungeonService.GetRoom(room).Entry, "Dungeon")
end

-- Furthest unlocked room.
function TravelService.EnterDungeon(player)
	local room = math.min(PlayerState.GetRoomReached(player) + 1, Config.Dungeon.Rooms)
	return TravelService.ToRoom(player, room)
end

function TravelService.Init(hubInfo)
	hub = hubInfo
	local allow = RateLimit.new(1)

	Remotes.Get("Travel").OnServerInvoke = function(player, destination, room)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if destination == "Hub" then
			return TravelService.ToHub(player)
		elseif destination == "Room" then
			return TravelService.ToRoom(player, room)
		elseif destination == "Dungeon" then
			return TravelService.EnterDungeon(player)
		end
		return false, "Неверный запрос"
	end

	-- Portal: walk into the disc.
	local portalAllow = RateLimit.new(2)
	hub.Portal.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and PlayerState.IsReady(player) and portalAllow(player) then
			TravelService.EnterDungeon(player)
		end
	end)

	-- Everyone spawns in the hub.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Zone", "Hub")
		end)
	end)
end

return TravelService
