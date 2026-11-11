--[[
	Dungeon.luau
	- Opens (locally) the exit doors of every room this player has
	  cleared: CanCollide off + fade out. Doors stay solid on the server
	  and for players who haven't cleared that room. Damage is still
	  checked by the server, so walking through a door early gives
	  nothing.
	- Menu buttons to travel to the hub or the furthest unlocked room.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Panels = require(script.Parent.Panels)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local travel = ReplicatedStorage:WaitForChild("Travel")
local doorsFolder = Workspace:WaitForChild("Dungeon"):WaitForChild("Doors")

local Dungeon = {}

local function setDoor(door: BasePart, open: boolean)
	door.CanCollide = not open
	Ui.Tween(door, 0.6, { Transparency = if open then 1 else 0.35 })
	for _, gui in ipairs(door:GetDescendants()) do
		if gui:IsA("BillboardGui") then
			gui.Enabled = not open
		end
	end
end

local function refreshDoors()
	local reached = player:GetAttribute("RoomReached") or 0
	for _, door in ipairs(doorsFolder:GetChildren()) do
		local room = door:GetAttribute("Room")
		if room then
			local open = reached >= room
			if door:GetAttribute("OpenLocally") ~= open then
				door:SetAttribute("OpenLocally", open) -- local-only marker
				setDoor(door, open)
			end
		end
	end
end

player:GetAttributeChangedSignal("RoomReached"):Connect(refreshDoors)
doorsFolder.ChildAdded:Connect(refreshDoors) -- doors may stream in later
refreshDoors()

local busy = false
local function go(destination, room)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = travel:InvokeServer(destination, room)
		busy = false
		if not ok then
			Ui.Toast(message or "", Ui.Colors.Bad)
		end
	end)
end

Panels.AddMenuButton("🏠", "Хаб", Color3.fromRGB(70, 130, 220), function()
	go("Hub")
end)

Panels.AddMenuButton("⚔", "Данж", Color3.fromRGB(200, 70, 70), function()
	local reached = player:GetAttribute("RoomReached") or 0
	local room = math.min(reached + 1, Config.Dungeon.Rooms)
	Ui.Toast(("Комната %d"):format(room), Ui.Colors.Muted)
	go("Room", room)
end)

return Dungeon
