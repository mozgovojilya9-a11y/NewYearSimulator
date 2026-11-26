--[[
	Atmosphere.luau
	Base look of the world from Config.Lighting.Hub, made for
	LightingStyle = Realistic (+ PrioritizeLightingQuality): the owner sets
	them in Studio; the server tries too (pcall: in some versions only
	Studio may change them). Clear sky with clouds and a light haze, soft
	shadows, bloom practically off, minimal color correction. The client
	(Zone.luau) tweens the same properties to the Dungeon preset.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Atmosphere = {}

local function ensure(parent: Instance, className: string, name: string)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function Atmosphere.Init()
	-- Wipe whatever an older version of the place left in Lighting: only
	-- the effects this module creates below may exist.
	for _, child in ipairs(Lighting:GetChildren()) do
		child:Destroy()
	end

	local L = Config.Lighting
	local hub = L.Hub
	pcall(function()
		Lighting.LightingStyle = Enum.LightingStyle.Realistic
	end)
	pcall(function()
		Lighting.PrioritizeLightingQuality = true
	end)
	Lighting.GlobalShadows = true
	pcall(function()
		Lighting.ShadowSoftness = L.ShadowSoftness
	end)
	Lighting.ClockTime = hub.ClockTime
	Lighting.Brightness = hub.Brightness
	Lighting.ExposureCompensation = hub.ExposureCompensation
	Lighting.Ambient = hub.Ambient
	Lighting.OutdoorAmbient = hub.OutdoorAmbient
	Lighting.EnvironmentDiffuseScale = hub.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = hub.EnvironmentSpecularScale

	local sky = ensure(Lighting, "Sky", "Sky")
	sky.StarCount = L.Sky and L.Sky.StarCount or 1500
	sky.SunAngularSize = 11
	sky.MoonAngularSize = 8
	sky.CelestialBodiesShown = if L.Sky then L.Sky.CelestialBodies else true

	local atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere")
	atmosphere.Density = hub.Atmosphere.Density
	atmosphere.Offset = hub.Atmosphere.Offset
	atmosphere.Color = hub.Atmosphere.Color
	atmosphere.Decay = hub.Atmosphere.Decay
	atmosphere.Glare = hub.Atmosphere.Glare
	atmosphere.Haze = hub.Atmosphere.Haze

	local bloom = ensure(Lighting, "BloomEffect", "Bloom")
	bloom.Intensity = hub.Bloom
	bloom.Size = L.BloomSize
	bloom.Threshold = L.BloomThreshold

	local cc = ensure(Lighting, "ColorCorrectionEffect", "ColorCorrection")
	cc.Saturation = hub.Saturation
	cc.Contrast = hub.Contrast
	cc.TintColor = hub.Tint

	-- Soft clouds over the hub (Terrain clouds, no assets needed).
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = ensure(terrain, "Clouds", "Clouds")
		clouds.Cover = L.Clouds.Cover
		clouds.Density = L.Clouds.Density
		clouds.Color = L.Clouds.Color
	end
end

return Atmosphere
