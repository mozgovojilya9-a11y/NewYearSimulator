--[[
	TravelService.luau
	Travel:InvokeServer("Hub") or ("Room", n) -> ok, message.
	Teleports the character to the hub spawn or to the entrance of an
	unlocked room (RoomReached >= n - 1), so long walks back are optional.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonService = require(script.Parent.DungeonService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local TravelService = {}

local function hubCFrame()
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local position = if spawn then spawn.Position + Vector3.new(0, 4, 0) else Vector3.new(0, 5, 0)
	return CFrame.new(position)
end

function TravelService.Init()
	local allow = RateLimit.new(1)

	Remotes.Get("Travel").OnServerInvoke = function(player, destination, room)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			return false, "Персонаж ещё не появился"
		end

		if destination == "Hub" then
			character:PivotTo(hubCFrame())
			return true, "Хаб"
		elseif destination == "Room" then
			if type(room) ~= "number" or room ~= math.floor(room) or room < 1 or room > Config.Dungeon.Rooms then
				return false, "Неверная комната"
			end
			if PlayerState.GetRoomReached(player) < room - 1 then
				return false, "Комната ещё закрыта"
			end
			character:PivotTo(DungeonService.GetRoom(room).Entry)
			return true, "Комната " .. room
		end

		return false, "Неверный запрос"
	end
end

return TravelService
