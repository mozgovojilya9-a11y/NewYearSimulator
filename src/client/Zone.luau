--[[
	Zone.luau
	Everything that depends on where this player is:
	- Lighting preset (Config.Lighting.Hub / .Dungeon) tweened when the
	  "Zone" attribute changes, plus a screen fade on teleport.
	- Which dungeon room the player stands in (for the objective text).
	- Barriers: the exit barrier of every room this player has cleared
	  dissolves locally ("Пройдено!"); barriers stay solid on the server
	  and for players who haven't cleared that room.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.ui.Hud)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local dungeonFolder = Workspace:WaitForChild("Dungeon")
local geometry = dungeonFolder:WaitForChild("Geometry")
local barriers = dungeonFolder:WaitForChild("Barriers")
local roomState = ReplicatedStorage:WaitForChild("RoomState")

local Zone = {}

---------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------

local bloom = Lighting:WaitForChild("Bloom", 10)
local cc = Lighting:WaitForChild("ColorCorrection", 10)

local function applyLighting(presetName: string)
	local p = Config.Lighting[presetName]
	local t = Config.Lighting.TransitionSeconds
	Style.Tween(Lighting, t, { ClockTime = p.ClockTime, Brightness = p.Brightness, ExposureCompensation = p.ExposureCompensation, Ambient = p.Ambient, OutdoorAmbient = p.OutdoorAmbient, FogColor = p.FogColor, FogEnd = p.FogEnd })
	if bloom then
		Style.Tween(bloom, t, { Intensity = p.Bloom })
	end
	if cc then
		Style.Tween(cc, t, { Saturation = p.Saturation, Contrast = p.Contrast, TintColor = p.Tint })
	end
end

local lastZone = nil
local function onZone()
	local zone = player:GetAttribute("Zone") or "Hub"
	if zone == lastZone then
		return
	end
	local first = lastZone == nil
	lastZone = zone
	applyLighting(if zone == "Dungeon" then "Dungeon" else "Hub")
	if not first then
		Popups.Fade(if zone == "Dungeon" then Color3.new(0, 0, 0) else Style.Colors.Panel, 0.3)
		Style.PlaySound(Config.Sounds.Portal, 1, 0.6)
	end
end
player:GetAttributeChangedSignal("Zone"):Connect(onZone)
onZone()

---------------------------------------------------------------------
-- Current room
---------------------------------------------------------------------

local rooms = {} -- { model, index, zFront, zBack }
local function indexRooms()
	rooms = {}
	for _, model in ipairs(geometry:GetChildren()) do
		local index = model:GetAttribute("Room")
		if index then
			table.insert(rooms, { index = index, zFront = model:GetAttribute("ZFront"), zBack = model:GetAttribute("ZBack") })
		end
	end
end
indexRooms()
geometry.ChildAdded:Connect(indexRooms)

local currentRoom = nil
task.spawn(function()
	while true do
		task.wait(0.3)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local found = nil
		if root and player:GetAttribute("Zone") == "Dungeon" then
			local z = root.Position.Z
			for _, room in ipairs(rooms) do
				if z <= room.zFront + 2 and z >= room.zBack - 2 then
					found = room.index
					break
				end
			end
		end
		if found ~= currentRoom then
			currentRoom = found
			Hud.SetCurrentRoom(found)
		end
	end
end)

---------------------------------------------------------------------
-- Barriers
---------------------------------------------------------------------

local function setBarrier(barrier: BasePart, open: boolean)
	barrier.CanCollide = not open
	Style.Tween(barrier, 0.6, { Transparency = if open then 1 else 0.4 })
	local gui = barrier:FindFirstChild("Text")
	if gui then
		for _, label in ipairs(gui:GetChildren()) do
			if label:IsA("TextLabel") then
				if open then
					label.Visible = label.Name == "Enemies"
				else
					label.Visible = true
				end
			end
		end
		local enemies = gui:FindFirstChild("Enemies")
		if enemies and open then
			enemies.Text = Config.DungeonLayout.Texts.Cleared
			enemies.TextColor3 = Style.Colors.Green
		end
	end
end

local initialized = false
local function refreshBarriers()
	local reached = player:GetAttribute("RoomReached") or 0
	for _, barrier in ipairs(barriers:GetChildren()) do
		local room = barrier:GetAttribute("Room")
		if room then
			local open = reached >= room
			if barrier:GetAttribute("OpenLocally") ~= open then
				barrier:SetAttribute("OpenLocally", open) -- local-only marker
				if open and initialized then
					Style.PlaySound(Config.Sounds.Barrier, 1, 0.6)
				end
				setBarrier(barrier, open)
			end
		end
	end
	initialized = true
end
player:GetAttributeChangedSignal("RoomReached"):Connect(refreshBarriers)
barriers.ChildAdded:Connect(function()
	task.defer(refreshBarriers)
end)
refreshBarriers()

-- Keep "Пройдено!" on cleared barriers even after the server rewrites
-- the counter text on respawn.
roomState.OnClientEvent:Connect(function(room)
	local reached = player:GetAttribute("RoomReached") or 0
	if reached >= room then
		for _, barrier in ipairs(barriers:GetChildren()) do
			if barrier:GetAttribute("Room") == room then
				local enemies = barrier:FindFirstChild("Text") and barrier.Text:FindFirstChild("Enemies")
				if enemies then
					enemies.Text = Config.DungeonLayout.Texts.Cleared
					enemies.TextColor3 = Style.Colors.Green
				end
			end
		end
	end
end)

-- Barrier counters animate: pulse the number when it changes.
roomState.OnClientEvent:Connect(function(room, alive, total)
	for _, barrier in ipairs(barriers:GetChildren()) do
		if barrier:GetAttribute("Room") == room and not barrier:GetAttribute("OpenLocally") then
			local enemies = barrier:FindFirstChild("Text") and barrier.Text:FindFirstChild("Enemies")
			if enemies then
				enemies.Text = Config.DungeonLayout.Texts.Enemies:format(total - alive, total)
			end
		end
	end
end)

return Zone
