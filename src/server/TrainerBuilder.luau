--[[
	TrainerBuilder.luau
	Builds the big clickable object that sits on each trainer platform
	(Config.HubLayout.Trainers[i].Kind). Every object is a Model of
	anchored Parts with PrimaryPart "Core" at its base center, so the
	client can "breathe" it with Model:ScaleTo and squash it on hits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldKit = require(script.Parent.WorldKit)

local TrainerBuilder = {}

local T = Config.Theme
local FACE = "rbxasset://textures/face.png"

local function p(model, name, size, cframe, color, material, transparency)
	return WorldKit.Part(model, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
		CanCollide = false,
	})
end

local function eyes(model, cf, spread, y, z, size, color)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Eye", Vector3.new(size, size * 1.3, 0.25), cf * CFrame.new(side * spread, y, z), color or Color3.new(0, 0, 0), Enum.Material.Neon)
	end
end

local builders = {}

builders.Dummy = function(model, cf, color)
	p(model, "Post", Vector3.new(0.8, 3, 0.8), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	local body = p(model, "Body", Vector3.new(3, 4, 2), cf * CFrame.new(0, 5, 0), Color3.fromRGB(230, 200, 150), Enum.Material.Fabric)
	p(model, "Head", Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(0, 8.1, 0), Color3.fromRGB(230, 200, 150), Enum.Material.Fabric)
	local target = p(model, "Target", Vector3.new(2, 2, 0.2), cf * CFrame.new(0, 5.3, -1.1), color, Enum.Material.Neon)
	target.Shape = Enum.PartType.Cylinder
	target.CFrame = cf * CFrame.new(0, 5.3, -1.1) * CFrame.Angles(0, math.rad(90), 0)
	target.Size = Vector3.new(0.2, 2, 2)
	local face = Instance.new("Decal")
	face.Texture = FACE
	face.Face = Enum.NormalId.Front
	face.Parent = model.Head
	return body, 9.5
end

builders.Boulder = function(model, cf, color)
	local rock = p(model, "Rock", Vector3.new(5.5, 5, 5.5), cf * CFrame.new(0, 2.6, 0) * CFrame.Angles(math.rad(10), math.rad(20), math.rad(5)), Color3.fromRGB(120, 125, 140), Enum.Material.Slate)
	p(model, "Rock2", Vector3.new(3.5, 3, 3.5), cf * CFrame.new(1.2, 5.2, 0.4) * CFrame.Angles(math.rad(-15), math.rad(40), 0), Color3.fromRGB(140, 145, 160), Enum.Material.Slate)
	for i = 1, 3 do
		p(model, "Vein", Vector3.new(0.3, 1.5, 0.3), cf * CFrame.new(-1.5 + i, 3 + i * 0.4, -2.6) * CFrame.Angles(0, 0, math.rad(30 * i)), color, Enum.Material.Neon)
	end
	return rock, 7.5
end

builders.IceCube = function(model, cf, color)
	local cube = p(model, "Cube", Vector3.new(5, 5, 5), cf * CFrame.new(0, 2.5, 0), Color3.fromRGB(170, 225, 255), Enum.Material.Glass, 0.3)
	p(model, "Core", Vector3.new(2, 2, 2), cf * CFrame.new(0, 2.5, 0), color, Enum.Material.Neon)
	p(model, "Cap", Vector3.new(5.4, 0.6, 5.4), cf * CFrame.new(0, 5.2, 0), Color3.fromRGB(230, 245, 255), Enum.Material.Ice)
	eyes(model, cf, 1, 3.2, -2.6, 0.5, Color3.fromRGB(20, 40, 80))
	return cube, 6.5
end

builders.Mimic = function(model, cf, color)
	local chest = p(model, "Chest", Vector3.new(5, 2.6, 3.6), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(140, 85, 45), Enum.Material.Wood)
	p(model, "Lid", Vector3.new(5, 1.4, 3.6), cf * CFrame.new(0, 3.4, 0.9) * CFrame.Angles(math.rad(-40), 0, 0), Color3.fromRGB(160, 100, 50), Enum.Material.Wood)
	p(model, "Band", Vector3.new(5.1, 0.4, 3.7), cf * CFrame.new(0, 1.3, 0), color)
	p(model, "Tongue", Vector3.new(1.6, 0.3, 2.4), cf * CFrame.new(0, 2.7, -1.2) * CFrame.Angles(math.rad(10), 0, 0), Color3.fromRGB(255, 80, 120))
	for i = -2, 2 do
		p(model, "Tooth", Vector3.new(0.5, 0.8, 0.3), cf * CFrame.new(i * 0.9, 2.9, -1.75), Color3.new(1, 1, 1))
		p(model, "Tooth", Vector3.new(0.5, 0.8, 0.3), cf * CFrame.new(i * 0.9, 3.6, -1.4) * CFrame.Angles(math.rad(-40), 0, 0), Color3.new(1, 1, 1))
	end
	eyes(model, cf * CFrame.Angles(math.rad(-40), 0, 0), 1.2, 4.6, -0.3, 0.5, Color3.fromRGB(255, 220, 60))
	return chest, 5.5
end

builders.Skull = function(model, cf, color)
	local skull = p(model, "Skull", Vector3.new(5, 4.5, 4.5), cf * CFrame.new(0, 3.2, 0), Color3.fromRGB(235, 235, 240))
	p(model, "Jaw", Vector3.new(4, 1.2, 3.5), cf * CFrame.new(0, 0.7, -0.4), Color3.fromRGB(220, 220, 228))
	for i = -2, 2 do
		p(model, "Tooth", Vector3.new(0.5, 0.6, 0.3), cf * CFrame.new(i * 0.8, 1.2, -2.1), Color3.new(1, 1, 1))
	end
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Socket", Vector3.new(1.4, 1.4, 0.4), cf * CFrame.new(side * 1.2, 3.6, -2.2), Color3.fromRGB(20, 15, 30))
		p(model, "Glow", Vector3.new(0.7, 0.7, 0.3), cf * CFrame.new(side * 1.2, 3.6, -2.3), color, Enum.Material.Neon)
	end
	p(model, "Nose", Vector3.new(0.6, 0.9, 0.3), cf * CFrame.new(0, 2.6, -2.25), Color3.fromRGB(20, 15, 30))
	return skull, 6
end

builders.Pumpkin = function(model, cf, color)
	local body = p(model, "Body", Vector3.new(5.5, 4.5, 5.5), cf * CFrame.new(0, 2.3, 0), Color3.fromRGB(255, 130, 30))
	for i = -1, 1 do
		p(model, "Rib", Vector3.new(0.5, 4.6, 5.6), cf * CFrame.new(i * 1.8, 2.3, 0), Color3.fromRGB(225, 105, 20))
	end
	p(model, "Stem", Vector3.new(0.8, 1.4, 0.8), cf * CFrame.new(0, 5.2, 0) * CFrame.Angles(0, 0, math.rad(15)), Color3.fromRGB(70, 130, 50))
	p(model, "Mouth", Vector3.new(3.4, 0.9, 0.3), cf * CFrame.new(0, 1.3, -2.8), color, Enum.Material.Neon)
	p(model, "Fang", Vector3.new(0.5, 0.6, 0.3), cf * CFrame.new(-1, 1.9, -2.85), color, Enum.Material.Neon)
	p(model, "Fang", Vector3.new(0.5, 0.6, 0.3), cf * CFrame.new(1, 1.9, -2.85), color, Enum.Material.Neon)
	eyes(model, cf, 1.2, 3.3, -2.8, 0.8, color)
	return body, 6.5
end

builders.Golem = function(model, cf, color)
	local torso = p(model, "Torso", Vector3.new(3.5, 3.5, 2.5), cf * CFrame.new(0, 4.2, 0), Color3.fromRGB(90, 70, 140), Enum.Material.Slate)
	p(model, "Head", Vector3.new(2, 2, 2), cf * CFrame.new(0, 7, 0), Color3.fromRGB(90, 70, 140), Enum.Material.Slate)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Arm", Vector3.new(1.4, 4, 1.4), cf * CFrame.new(side * 2.6, 3.8, 0) * CFrame.Angles(0, 0, side * math.rad(10)), Color3.fromRGB(80, 60, 130), Enum.Material.Slate)
		p(model, "Leg", Vector3.new(1.4, 2.5, 1.4), cf * CFrame.new(side * 0.9, 1.25, 0), Color3.fromRGB(80, 60, 130), Enum.Material.Slate)
		p(model, "Shoulder", Vector3.new(1.2, 1.6, 1.2), cf * CFrame.new(side * 2.6, 6.2, 0) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Neon)
	end
	p(model, "Heart", Vector3.new(1.4, 1.4, 0.4), cf * CFrame.new(0, 4.4, -1.3), color, Enum.Material.Neon)
	eyes(model, cf, 0.5, 7.1, -1.05, 0.4, color)
	return torso, 8.5
end

builders.Core = function(model, cf, color)
	p(model, "Base", Vector3.new(4, 1, 4), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(45, 30, 70))
	local core = p(model, "Core", Vector3.new(3, 3, 3), cf * CFrame.new(0, 4, 0), color, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	for i = 0, 2 do
		local ring = p(model, "Ring", Vector3.new(0.3, 5, 5), cf * CFrame.new(0, 4, 0) * CFrame.Angles(math.rad(i * 60), math.rad(i * 30), math.rad(90)), T.Gold, Enum.Material.Neon, 0.2)
		ring.Shape = Enum.PartType.Cylinder
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = core
	return core, 7
end

-- Returns the Model and its visual height. cf: ground-level CFrame
-- facing the player side (-Z = front).
function TrainerBuilder.Build(def, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = def.Name
	local build = builders[def.Kind] or builders.Dummy
	local primary, height = build(model, cf, def.Color)
	model.PrimaryPart = primary
	model:SetAttribute("Height", height)
	return model, height
end

return TrainerBuilder
