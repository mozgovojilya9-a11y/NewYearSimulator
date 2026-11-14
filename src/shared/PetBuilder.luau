--[[
	PetBuilder.luau
	Pet models from Parts (Config.Pets[i].Shape). Anchored, no collision;
	PrimaryPart "Body" at the center, -Z = face. Tier 2 pets get a gold
	halo, tier 3 a rainbow-ish shimmer (the client colors it over time).
	Used by the followers (client Cosmetics) and the Pets window.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PetBuilder = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(20, 15, 30)
local BALL = Enum.PartType.Ball

local function p(model, name, size, cf, color, material, transparency, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function lighter(c, a)
	return c:Lerp(WHITE, a)
end
local function darker(c, a)
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function face(model, s, c)
	for _, x in ipairs({ -1, 1 }) do
		p(model, "Eye", Vector3.new(0.22, 0.28, 0.1) * s, CFrame.new(x * 0.2 * s, 0.1 * s, -0.46 * s), BLACK)
		p(model, "Shine", Vector3.new(0.08, 0.08, 0.06) * s, CFrame.new(x * 0.2 * s + 0.05 * s, 0.17 * s, -0.5 * s), WHITE)
		p(model, "Blush", Vector3.new(0.16, 0.08, 0.06) * s, CFrame.new(x * 0.32 * s, -0.06 * s, -0.44 * s), lighter(Color3.fromRGB(255, 120, 150), 0.2))
	end
	p(model, "Mouth", Vector3.new(0.14, 0.06, 0.06) * s, CFrame.new(0, -0.08 * s, -0.48 * s), darker(c, 0.6))
end

local shapes = {}

shapes.Blob = function(m, s, c)
	p(m, "Top", Vector3.new(0.6, 0.5, 0.6) * s, CFrame.new(0.1 * s, 0.42 * s, 0.05 * s), c, Enum.Material.Glass, 0.2, BALL)
	p(m, "Core", Vector3.new(0.35, 0.35, 0.35) * s, CFrame.new(0, -0.05 * s, 0.1 * s), lighter(c, 0.5), Enum.Material.Neon, 0, BALL)
end

shapes.Ears = function(m, s, c)
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Ear", Vector3.new(0.22, 0.7, 0.14) * s, CFrame.new(x * 0.22 * s, 0.68 * s, 0) * CFrame.Angles(0, 0, math.rad(x * -12)), c)
		p(m, "EarIn", Vector3.new(0.12, 0.5, 0.06) * s, CFrame.new(x * 0.22 * s, 0.66 * s, -0.08 * s) * CFrame.Angles(0, 0, math.rad(x * -12)), lighter(Color3.fromRGB(255, 150, 180), 0.3))
		p(m, "Paw", Vector3.new(0.24, 0.2, 0.3) * s, CFrame.new(x * 0.2 * s, -0.45 * s, -0.2 * s), lighter(c, 0.3), nil, 0, BALL)
	end
	p(m, "Tail", Vector3.new(0.3, 0.3, 0.3) * s, CFrame.new(0, -0.2 * s, 0.5 * s), lighter(c, 0.5), nil, 0, BALL)
end

shapes.Wings = function(m, s, c)
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Wing", Vector3.new(0.8, 0.08, 0.5) * s, CFrame.new(x * 0.65 * s, 0.15 * s, 0.1 * s) * CFrame.Angles(0, 0, math.rad(x * 22)), lighter(c, 0.3), nil, 0.1)
		p(m, "WingTip", Vector3.new(0.4, 0.08, 0.3) * s, CFrame.new(x * 1.05 * s, 0.35 * s, 0.15 * s) * CFrame.Angles(0, 0, math.rad(x * 40)), darker(c, 0.2))
		p(m, "Horn", Vector3.new(0.1, 0.25, 0.1) * s, CFrame.new(x * 0.18 * s, 0.5 * s, 0), darker(c, 0.4))
	end
end

shapes.Star = function(m, s, c)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		p(m, "Point", Vector3.new(0.25, 0.4, 0.2) * s, CFrame.new(math.sin(a) * 0.55 * s, math.cos(a) * 0.55 * s, 0.05 * s) * CFrame.Angles(0, 0, -a), lighter(c, 0.2), Enum.Material.Neon)
	end
end

shapes.Horns = function(m, s, c)
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Horn", Vector3.new(0.14, 0.4, 0.14) * s, CFrame.new(x * 0.25 * s, 0.55 * s, 0) * CFrame.Angles(0, 0, math.rad(x * -25)), BLACK)
		p(m, "Wing", Vector3.new(0.45, 0.06, 0.3) * s, CFrame.new(x * 0.55 * s, 0.1 * s, 0.25 * s) * CFrame.Angles(0, 0, math.rad(x * 25)), darker(c, 0.3))
	end
	p(m, "Tail", Vector3.new(0.08, 0.08, 0.5) * s, CFrame.new(0, -0.25 * s, 0.6 * s), c)
	p(m, "Flame", Vector3.new(0.22, 0.32, 0.22) * s, CFrame.new(0, 0.62 * s, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
end

shapes.Crystal = function(m, s, c)
	for i = 0, 2 do
		p(m, "Crystal", Vector3.new(0.2, 0.45, 0.2) * s, CFrame.new((i - 1) * 0.25 * s, 0.55 * s, 0.1 * s) * CFrame.Angles(0, math.rad(45), math.rad((i - 1) * -20)), lighter(c, 0.3), Enum.Material.Glass, 0.15)
	end
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Fist", Vector3.new(0.3, 0.3, 0.3) * s, CFrame.new(x * 0.6 * s, -0.2 * s, 0), darker(c, 0.3), Enum.Material.Slate)
	end
end

shapes.Eye = function(m, s, c)
	-- the whole body is an eye: replace the face
	for _, child in ipairs(m:GetChildren()) do
		if child.Name ~= "Body" then
			child:Destroy()
		end
	end
	p(m, "Iris", Vector3.new(0.55, 0.55, 0.15) * s, CFrame.new(0, 0, -0.45 * s), c, nil, 0, BALL)
	p(m, "Pupil", Vector3.new(0.16, 0.36, 0.08) * s, CFrame.new(0, 0, -0.53 * s), BLACK)
	p(m, "Shine", Vector3.new(0.1, 0.1, 0.05) * s, CFrame.new(0.12 * s, 0.12 * s, -0.55 * s), WHITE)
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Wing", Vector3.new(0.7, 0.06, 0.4) * s, CFrame.new(x * 0.65 * s, 0.1 * s, 0.1 * s) * CFrame.Angles(0, 0, math.rad(x * 25)), darker(c, 0.4))
	end
end

-- pet: Config.Pets entry; tier: 1..#Config.PetTiers.
function PetBuilder.Build(pet, tier: number?): Model
	tier = tier or 1
	local model = Instance.new("Model")
	model.Name = pet.Name
	local s = pet.Size or 1.4
	local c = pet.Color
	local tierDef = Config.PetTiers[tier] or Config.PetTiers[1]
	local isEye = pet.Shape == "Eye"
	local body = p(model, "Body", Vector3.new(1, 0.95, 1) * s, CFrame.new(), if isEye then Color3.fromRGB(245, 240, 250) else c, nil, 0, BALL)
	model.PrimaryPart = body
	face(model, s, c)
	local build = shapes[pet.Shape]
	if build then
		build(model, s, c)
	end
	if tier >= 2 then
		local halo = p(model, "Halo", Vector3.new(0.08, 0.7 * s, 0.7 * s), CFrame.new(0, 0.75 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), tierDef.Color, Enum.Material.Neon, 0.1, Enum.PartType.Cylinder)
		halo:SetAttribute("Rainbow", tierDef.Rainbow == true)
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(tierDef.Color, WHITE)
		sparkle.LightEmission = 0.6
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.5, 1)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = if tier >= 3 then 12 else 6
		sparkle.Parent = body
	end
	model:SetAttribute("Tier", tier)
	return model
end

return PetBuilder
