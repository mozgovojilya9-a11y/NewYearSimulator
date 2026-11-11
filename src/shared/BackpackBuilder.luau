--[[
	BackpackBuilder.luau
	Builds a backpack Model out of Parts for a Config.Backpacks entry.
	Used by hub stands, the character's back and the shop viewports.

	Convention: PrimaryPart = "Body", centered at the origin; -Z is the
	side that touches the player's back. Parts are unanchored, massless
	and welded to Body.
]]

local BackpackBuilder = {}

local function part(model, name, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function weldAll(model, body)
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = p
			weld.Parent = p
		end
	end
end

local STRAP = Color3.fromRGB(60, 40, 30)

local builders = {}

-- Small sack with a tied neck.
builders.Pouch = function(model, o, item)
	local body = part(model, "Body", item.Size, o, item.Color, Enum.Material.Fabric)
	part(model, "Neck", Vector3.new(item.Size.X * 0.5, 0.3, item.Size.Z * 0.8), o * CFrame.new(0, item.Size.Y / 2 + 0.1, 0), STRAP)
	part(model, "Strap", Vector3.new(item.Size.X + 0.1, 0.2, item.Size.Z + 0.1), o * CFrame.new(0, 0, 0), STRAP)
	return body
end

-- Box bag with two straps and a buckle.
builders.Satchel = function(model, o, item)
	local body = part(model, "Body", item.Size, o, item.Color, Enum.Material.Fabric)
	part(model, "Flap", Vector3.new(item.Size.X, item.Size.Y * 0.4, 0.15), o * CFrame.new(0, item.Size.Y * 0.3, item.Size.Z / 2 + 0.05), item.Color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric)
	part(model, "Buckle", Vector3.new(0.4, 0.3, 0.1), o * CFrame.new(0, item.Size.Y * 0.1, item.Size.Z / 2 + 0.15), Color3.fromRGB(255, 201, 60))
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Strap", Vector3.new(0.25, item.Size.Y, 0.15), o * CFrame.new(side * item.Size.X * 0.3, 0, item.Size.Z / 2 + 0.05), STRAP)
	end
	return body
end

-- Crystal pack: dark frame with a cluster of neon shards.
builders.AuraPack = function(model, o, item)
	local body = part(model, "Body", item.Size * Vector3.new(1, 0.8, 0.7), o, Color3.fromRGB(45, 30, 70))
	local shards = {
		{ Vector3.new(0.6, 1.8, 0.6), CFrame.new(0, 0.8, 0.5) * CFrame.Angles(0, math.rad(45), 0) },
		{ Vector3.new(0.45, 1.3, 0.45), CFrame.new(-0.6, 0.4, 0.5) * CFrame.Angles(0, math.rad(30), math.rad(15)) },
		{ Vector3.new(0.45, 1.2, 0.45), CFrame.new(0.6, 0.3, 0.5) * CFrame.Angles(0, math.rad(60), math.rad(-15)) },
	}
	for i, shard in ipairs(shards) do
		part(model, "Shard" .. i, shard[1], o * shard[2], item.Color, Enum.Material.Neon)
	end
	local light = Instance.new("PointLight")
	light.Color = item.Color
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = body
	return body
end

-- Portal pack: ring with a glowing swirling disc.
builders.StarPack = function(model, o, item)
	local body = part(model, "Body", Vector3.new(item.Size.X * 0.6, item.Size.Y * 0.6, 0.6), o, Color3.fromRGB(45, 30, 70))
	local ring = part(model, "Ring", Vector3.new(0.5, item.Size.Y + 0.4, item.Size.Y + 0.4), o * CFrame.new(0, 0.2, 0.4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 201, 60))
	ring.Shape = Enum.PartType.Cylinder
	local disc = part(model, "Disc", Vector3.new(0.3, item.Size.Y, item.Size.Y), o * CFrame.new(0, 0.2, 0.4) * CFrame.Angles(0, math.rad(90), 0), item.Color, Enum.Material.Neon, 0.2)
	disc.Shape = Enum.PartType.Cylinder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(item.Color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.Rate = 10
	emitter.Parent = disc
	local light = Instance.new("PointLight")
	light.Color = item.Color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = body
	return body
end

function BackpackBuilder.Build(item): Model
	local model = Instance.new("Model")
	model.Name = item.Id
	local build = builders[item.Id] or builders.Satchel
	local body = build(model, CFrame.new(), item)
	model.PrimaryPart = body
	weldAll(model, body)
	return model
end

function BackpackBuilder.SetAnchored(model: Model, anchored: boolean)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = anchored
		end
	end
end

return BackpackBuilder
