--[[
	Atmosphere.luau
	Base look of the world from Config.Lighting.Hub: bright day, soft
	bloom and color correction. The client (Zone.luau) tweens the same
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
	local hub = Config.Lighting.Hub
	Lighting.ClockTime = hub.ClockTime
	Lighting.Brightness = hub.Brightness
	Lighting.ExposureCompensation = hub.ExposureCompensation
	Lighting.Ambient = hub.Ambient
	Lighting.OutdoorAmbient = hub.OutdoorAmbient
	Lighting.FogColor = hub.FogColor
	Lighting.FogEnd = hub.FogEnd
	Lighting.GlobalShadows = true

	local bloom = ensure("BloomEffect", "Bloom")
	bloom.Intensity = hub.Bloom
	bloom.Size = 24
	bloom.Threshold = 1.1

	local cc = ensure("ColorCorrectionEffect", "ColorCorrection")
	cc.Saturation = hub.Saturation
	cc.Contrast = hub.Contrast
	cc.TintColor = hub.Tint
end

return Atmosphere
