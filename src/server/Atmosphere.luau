--[[
	Atmosphere.luau
	Base look of the world from Config.Lighting.Hub: clear day, blue
	sky, light haze (Atmosphere), tiny bloom (only neon glows) and a
	gentle color correction. No fog: Atmosphere does the depth. The client (Zone.luau) tweens the same
	properties to the Dungeon preset when the player is in the dungeon.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Atmosphere = {}

local function ensure(className: string, name: string)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

function Atmosphere.Init()
	-- Wipe whatever an older version of the place left in Lighting
	-- (skies, atmospheres, clouds, blur, extra effects): only the
	-- effects this module creates below may exist.
	for _, child in ipairs(Lighting:GetChildren()) do
		child:Destroy()
	end

	local hub = Config.Lighting.Hub
	Lighting.ClockTime = hub.ClockTime
	Lighting.Brightness = hub.Brightness
	Lighting.ExposureCompensation = hub.ExposureCompensation
	Lighting.Ambient = hub.Ambient
	Lighting.OutdoorAmbient = hub.OutdoorAmbient
	Lighting.GlobalShadows = true

	local sky = ensure("Sky", "Sky")
	sky.StarCount = 1500
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8

	local atmosphere = ensure("Atmosphere", "Atmosphere")
	atmosphere.Density = hub.Atmosphere.Density
	atmosphere.Color = hub.Atmosphere.Color
	atmosphere.Decay = hub.Atmosphere.Decay
	atmosphere.Glare = hub.Atmosphere.Glare
	atmosphere.Haze = hub.Atmosphere.Haze

	local bloom = ensure("BloomEffect", "Bloom")
	bloom.Intensity = hub.Bloom
	bloom.Size = Config.Lighting.BloomSize
	bloom.Threshold = Config.Lighting.BloomThreshold

	local cc = ensure("ColorCorrectionEffect", "ColorCorrection")
	cc.Saturation = hub.Saturation
	cc.Contrast = hub.Contrast
	cc.TintColor = hub.Tint
end

return Atmosphere
