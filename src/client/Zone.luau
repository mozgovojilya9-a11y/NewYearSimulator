--[[
	Zone.luau
	Everything that depends on where this player is:
	- Lighting preset (Config.Lighting.Hub / .Dungeon) tweened when the
	  "Zone" attribute changes, plus a screen fade on teleport; haze color
	  follows the biome of the room the player stands in.
	- Which dungeon room the player stands in (objective text, hint line).
	Barriers are private per run and opened by the server, so nothing is
	faked locally any more.
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
local lanes = dungeonFolder:WaitForChild("Lanes")

local Zone = {}

---------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------

local bloom = Lighting:WaitForChild("Bloom", 10)
local cc = Lighting:WaitForChild("ColorCorrection", 10)
local atmosphere = Lighting:WaitForChild("Atmosphere", 10)

local function applyLighting(presetName: string)
	local p = Config.Lighting[presetName]
	local t = Config.Lighting.TransitionSeconds
	Style.Tween(Lighting, t, { ClockTime = p.ClockTime, Brightness = p.Brightness, ExposureCompensation = p.ExposureCompensation, Ambient = p.Ambient, OutdoorAmbient = p.OutdoorAmbient })
	if bloom then
		Style.Tween(bloom, t, { Intensity = p.Bloom })
	end
	if cc then
		Style.Tween(cc, t, { Saturation = p.Saturation, Contrast = p.Contrast, TintColor = p.Tint })
	end
	if atmosphere then
		Style.Tween(atmosphere, t, { Density = p.Atmosphere.Density, Color = p.Atmosphere.Color, Decay = p.Atmosphere.Decay, Glare = p.Atmosphere.Glare, Haze = p.Atmosphere.Haze })
	end
end

local function applyBiome(room: number?)
	if not atmosphere or not room then
		return
	end
	local biomes = Config.DungeonLayout.Biomes
	local biome = biomes[math.min(#biomes, math.ceil(room / Config.Dungeon.BossEvery))]
	Style.Tween(atmosphere, Config.Lighting.TransitionSeconds, { Color = biome.Atmosphere.Color, Decay = biome.Atmosphere.Decay })
	Style.Tween(Lighting, Config.Lighting.TransitionSeconds, { Ambient = biome.Lighting.Ambient, OutdoorAmbient = biome.Lighting.OutdoorAmbient })
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
		Popups.Fade(Color3.new(0, 0, 0), 0.3)
		Style.PlaySound(Config.Sounds.Portal, 1, 0.6)
	end
end
player:GetAttributeChangedSignal("Zone"):Connect(onZone)
onZone()

---------------------------------------------------------------------
-- Current room (scans every lane's room models)
---------------------------------------------------------------------

local currentRoom = nil
task.spawn(function()
	while true do
		task.wait(0.3)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local found = nil
		if root and player:GetAttribute("Zone") == "Dungeon" then
			local p = root.Position
			for _, lane in ipairs(lanes:GetChildren()) do
				for _, model in ipairs(lane:GetChildren()) do
					local index = model:GetAttribute("Room")
					if index then
						local x = model:GetAttribute("X")
						local size = model:GetAttribute("Size")
						if math.abs(p.X - x) <= size / 2 + 3 and p.Z <= model:GetAttribute("ZFront") + 2 and p.Z >= model:GetAttribute("ZBack") - 2 then
							found = index
							break
						end
					end
				end
				if found then
					break
				end
			end
		end
		if found ~= currentRoom then
			currentRoom = found
			Hud.SetCurrentRoom(found)
			applyBiome(found)
		end
	end
end)

return Zone
