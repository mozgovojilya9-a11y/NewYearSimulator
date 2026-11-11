--[[
	MobBuilder.luau
	Builds block "aura monster" rigs: an unanchored HumanoidRootPart with
	every limb welded to it and a Humanoid with the right HipHeight, so
	Humanoid:MoveTo walks the whole mob (MobAI). Looks come from
	Config.MobLooks; faces are the built-in rbxasset face texture or
	small glowing Parts. Pure construction; health/rewards are set by
	DungeonRuns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MobBuilder = {}

local FACE = "rbxasset://textures/face.png"

local function part(model, name, size, cframe, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props or {}) do
		p[key] = value
	end
	p.Parent = model
	return p
end

local function weld(root, p)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
end

local function eyes(model, head: BasePart, color: Color3, scale: number)
	local s = head.Size
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Eye", Vector3.new(0.35, 0.5, 0.2) * scale, head.CFrame * CFrame.new(side * s.X * 0.22, s.Y * 0.08, -s.Z / 2 - 0.05 * scale), color, { Material = Enum.Material.Neon })
	end
end

-- look: entry from Config.MobLooks.Kinds (boss defs are merged in by
-- DungeonRuns). scale: overall size multiplier. cframe: ground-level,
-- -Z = facing. Returns the Model (PrimaryPart = HumanoidRootPart).
function MobBuilder.Build(look, scale: number, cframe: CFrame)
	local color = look.Color
	local model = Instance.new("Model")
	model.Name = look.Name
	local s = scale * (look.Scale or 1)

	local root, height, hipHeight
	if look.Shape == "Jelly" then
		local cube = Vector3.new(4, 3.4, 4) * s
		root = part(model, "HumanoidRootPart", cube, cframe * CFrame.new(0, cube.Y / 2, 0), color, { Transparency = 1, Massless = false, CanCollide = true })
		local body = part(model, "Torso", cube, root.CFrame, color, { Material = Enum.Material.Glass, Transparency = look.Transparency or 0.3 })
		part(model, "Core", cube * 0.35, root.CFrame, color, { Material = Enum.Material.Neon })
		local face = Instance.new("Decal")
		face.Texture = FACE
		face.Face = Enum.NormalId.Front
		face.Parent = body
		height = cube.Y
		hipHeight = 0
	else
		local torsoSize = Vector3.new(2, 2, 1) * s
		local legH = 2 * s
		local base = cframe * CFrame.new(0, legH + torsoSize.Y / 2, 0)
		root = part(model, "HumanoidRootPart", torsoSize, base, color, { Transparency = 1, Massless = false, CanCollide = true })
		local thin = if look.Thin then 0.6 else 1
		part(model, "Torso", torsoSize, base, color)
		local headSize = Vector3.new(1.4, 1.4, 1.4) * s * (look.HeadScale or 1)
		local head = part(model, "Head", headSize, base * CFrame.new(0, torsoSize.Y / 2 + headSize.Y / 2, 0), color)
		if look.EyeColor then
			eyes(model, head, look.EyeColor, s)
		else
			local face = Instance.new("Decal")
			face.Texture = FACE
			face.Face = Enum.NormalId.Front
			face.Parent = head
		end
		local armSize = Vector3.new(0.9 * thin, 2, 0.9 * thin) * s
		local legSize = Vector3.new(0.9 * thin, 2, 0.9 * thin) * s
		for _, side in ipairs({ -1, 1 }) do
			part(model, if side < 0 then "Left Arm" else "Right Arm", armSize, base * CFrame.new(side * (torsoSize.X / 2 + armSize.X / 2), 0, 0) * CFrame.Angles(math.rad(-20), 0, 0), color)
			part(model, if side < 0 then "Left Leg" else "Right Leg", legSize, base * CFrame.new(side * torsoSize.X / 4, -(torsoSize.Y / 2 + legSize.Y / 2), 0), color)
		end
		if look.Outline then
			local ring = part(model, "Aura", Vector3.new(0.2, 4.5 * s, 4.5 * s), cframe * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), look.Outline, { Material = Enum.Material.Neon, Transparency = 0.4 })
			ring.Shape = Enum.PartType.Cylinder
			part(model, "Edge", torsoSize + Vector3.new(0.15, 0.15, 0.15), base, look.Outline, { Material = Enum.Material.Neon, Transparency = 0.6 })
		end
		height = legH + torsoSize.Y + headSize.Y
		hipHeight = legH
	end

	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= root then
			weld(root, p)
		end
	end
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = true
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	model:SetAttribute("Height", height)
	return model
end

-- Crown + particle aura for bosses (welded to the root as well).
function MobBuilder.Decorate(model: Model, crownColor: Color3, scale: number)
	local root = model.PrimaryPart
	local head = model:FindFirstChild("Head") or model:FindFirstChild("Torso")
	if not head or not root then
		return
	end
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)
	local crown = part(model, "Crown", Vector3.new(head.Size.X * 0.8, 0.5 * scale, head.Size.Z * 0.8), top * CFrame.new(0, 0.25 * scale, 0), crownColor, { Material = Enum.Material.Neon })
	weld(root, crown)
	for i = 0, 3 do
		local angle = i * math.pi / 2
		local spike = part(model, "Spike", Vector3.new(0.4, 1.2, 0.4) * scale, top * CFrame.new(math.cos(angle) * head.Size.X * 0.35, 0.9 * scale, math.sin(angle) * head.Size.Z * 0.35), crownColor, { Material = Enum.Material.Neon })
		weld(root, spike)
	end
	local light = Instance.new("PointLight")
	light.Color = crownColor
	light.Range = 30
	light.Brightness = 2
	light.Parent = crown
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(crownColor, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Rate = 14
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = root
end

return MobBuilder
