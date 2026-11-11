--[[
	Effects.luau
	Server-side particle bursts that every player sees (mob deaths,
	rebirths). Parts are temporary and cleaned up by Debris.
]]

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Effects = {}

function Effects.Burst(position: Vector3, color: Color3, count: number, speed: number?, size: number?)
	local anchor = Instance.new("Part")
	anchor.Name = "Burst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(255, 240, 255))
	emitter.LightEmission = 0.7
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size or 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(12, speed or 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(count)

	Debris:AddItem(anchor, 2)
end

return Effects
