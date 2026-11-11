--[[
	MobBuilder.luau
	Builds block "aura monster" models: head, torso, arms, legs,
	HumanoidRootPart + Humanoid (R6-like, anchored, no animation).
	Looks come from Config.MobLooks. Faces are the built-in Roblox face
	texture (rbxasset://textures/face.png) or small glowing Parts.
	Pure construction; health/rewards are set by DungeonService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldKit = require(script.Parent.WorldKit)

local MobBuilder = {}

local FACE = "rbxasset://textures/face.png"

local function limb(model, name, size, cframe, color, transparency)
	local part = WorldKit.Part(model, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Plastic,
		Transparency = transparency or 0,
		CanCollide = false,
	})
	return part
end

local function eyes(model, head: BasePart, color: Color3, scale: number)
	local s = head.Size
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Part(model, {
			Name = "Eye",
			Size = Vector3.new(0.35, 0.5, 0.2) * scale,
			CFrame = head.CFrame * CFrame.new(side * s.X * 0.22, s.Y * 0.08, -s.Z / 2 - 0.05 * scale),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
end

-- look: entry from Config.MobLooks.Kinds (or a boss def merged with
-- its kind). scale: overall size multiplier. Returns the Model with
-- PrimaryPart = HumanoidRootPart and attribute Height.
function MobBuilder.Build(look, scale: number, cframe: CFrame)
	local color = look.Color
	local model = Instance.new("Model")
	model.Name = look.Name

	local s = scale * (look.Scale or 1)
	local torsoSize = Vector3.new(2, 2, 1) * s
	local legH = 2 * s
	local rootY = legH + torsoSize.Y / 2 -- torso center above the ground
	local base = cframe * CFrame.new(0, rootY, 0)

	local root = WorldKit.Part(model, {
		Name = "HumanoidRootPart",
		Size = torsoSize,
		CFrame = base,
		Transparency = 1,
		CanCollide = false,
	})
	model.PrimaryPart = root

	local height
	if look.Shape == "Jelly" then
		-- Slime: one translucent jelly cube sitting on the ground with a face.
		local cube = Vector3.new(4, 3.4, 4) * s
		local body = limb(model, "Torso", cube, cframe * CFrame.new(0, cube.Y / 2, 0), color, look.Transparency)
		body.Material = Enum.Material.Glass
		body.CanCollide = true
		local core = limb(model, "Core", cube * 0.35, body.CFrame, color, 0)
		core.Material = Enum.Material.Neon
		local face = Instance.new("Decal")
		face.Texture = FACE
		face.Face = Enum.NormalId.Front
		face.Parent = body
		root.CFrame = body.CFrame
		height = cube.Y
	else
		local thin = if look.Thin then 0.6 else 1
		local torso = limb(model, "Torso", torsoSize, base, color)
		torso.CanCollide = true
		local headSize = Vector3.new(1.4, 1.4, 1.4) * s * (look.HeadScale or 1)
		local head = limb(model, "Head", headSize, base * CFrame.new(0, torsoSize.Y / 2 + headSize.Y / 2, 0), color)
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
			limb(model, if side < 0 then "Left Arm" else "Right Arm", armSize, base * CFrame.new(side * (torsoSize.X / 2 + armSize.X / 2), 0, 0) * CFrame.Angles(math.rad(-20), 0, 0), color)
			limb(model, if side < 0 then "Left Leg" else "Right Leg", legSize, base * CFrame.new(side * torsoSize.X / 4, -(torsoSize.Y / 2 + legSize.Y / 2), 0), color)
		end
		if look.Outline then
			-- Shade: a glowing ring at the feet + neon edge on the torso.
			WorldKit.Part(model, {
				Name = "Aura",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, 4.5 * s, 4.5 * s),
				CFrame = cframe * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = look.Outline,
				Material = Enum.Material.Neon,
				Transparency = 0.4,
				CanCollide = false,
			})
			limb(model, "Edge", torsoSize + Vector3.new(0.15, 0.15, 0.15), base, look.Outline, 0.6).Material = Enum.Material.Neon
		end
		height = legH + torsoSize.Y + headSize.Y
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	model:SetAttribute("Height", height)
	return model
end

-- Crown + particle aura for bosses.
function MobBuilder.Decorate(model: Model, crownColor: Color3, scale: number)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("Torso")
	if not head then
		return
	end
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)
	local crown = WorldKit.Part(model, {
		Name = "Crown",
		Size = Vector3.new(head.Size.X * 0.8, 0.5 * scale, head.Size.Z * 0.8),
		CFrame = top * CFrame.new(0, 0.25 * scale, 0),
		Color = crownColor,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	for i = 0, 3 do
		local angle = i * math.pi / 2
		WorldKit.Part(model, {
			Name = "Spike",
			Size = Vector3.new(0.4, 1.2, 0.4) * scale,
			CFrame = top * CFrame.new(math.cos(angle) * head.Size.X * 0.35, 0.9 * scale, math.sin(angle) * head.Size.Z * 0.35),
			Color = crownColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
	WorldKit.Light(crown, crownColor, 30, 2)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(crownColor, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Rate = 14
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = model.PrimaryPart
end

return MobBuilder
