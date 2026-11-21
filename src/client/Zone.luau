--[[
	Zone.luau
	Everything that depends on where this player is:
	- Lighting preset (Config.Lighting.Hub / .Dungeon) tweened when the
	  "Zone" attribute changes, plus a screen fade on teleport; haze color
	  follows the biome of the room the player stands in.
	- the haze / ambient of the gate run's biome (attribute "Biome").
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer

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
	Style.Tween(Lighting, t, {
		ClockTime = p.ClockTime, Brightness = p.Brightness, ExposureCompensation = p.ExposureCompensation,
		Ambient = p.Ambient, OutdoorAmbient = p.OutdoorAmbient,
		EnvironmentDiffuseScale = p.EnvironmentDiffuseScale, EnvironmentSpecularScale = p.EnvironmentSpecularScale,
	})
	if bloom then
		Style.Tween(bloom, t, { Intensity = p.Bloom })
	end
	if cc then
		Style.Tween(cc, t, { Saturation = p.Saturation, Contrast = p.Contrast, TintColor = p.Tint })
	end
	if atmosphere then
		Style.Tween(atmosphere, t, { Density = p.Atmosphere.Density, Offset = p.Atmosphere.Offset, Color = p.Atmosphere.Color, Decay = p.Atmosphere.Decay, Glare = p.Atmosphere.Glare, Haze = p.Atmosphere.Haze })
	end
end

-- The haze and ambient follow the biome of the gate run (player
-- attribute "Biome" = Config.DungeonLayout.Biomes[*].Theme).
local function applyBiome()
	local theme = player:GetAttribute("Biome") or ""
	if not atmosphere or theme == "" then
		return
	end
	for _, biome in ipairs(Config.DungeonLayout.Biomes) do
		if biome.Theme == theme then
			Style.Tween(atmosphere, Config.Lighting.TransitionSeconds, { Color = biome.Atmosphere.Color, Decay = biome.Atmosphere.Decay })
			Style.Tween(Lighting, Config.Lighting.TransitionSeconds, { Ambient = biome.Lighting.Ambient, OutdoorAmbient = biome.Lighting.OutdoorAmbient })
		end
	end
end
player:GetAttributeChangedSignal("Biome"):Connect(function()
	task.delay(Config.Lighting.TransitionSeconds + 0.1, applyBiome)
end)

local lastZone = nil
local function onZone()
	local zone = player:GetAttribute("Zone") or "Hub"
	if zone == lastZone then
		return
	end
	local first = lastZone == nil
	lastZone = zone
	applyLighting(if zone == "Dungeon" then "Dungeon" elseif zone == "Afk" then "Afk" else "Hub")
	if not first then
		Popups.Fade(Color3.new(0, 0, 0), 0.3)
		Style.PlaySound(Config.Sounds.Portal, 1, 0.6)
	end
end
player:GetAttributeChangedSignal("Zone"):Connect(onZone)
onZone()

return Zone
