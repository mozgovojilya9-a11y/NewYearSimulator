--[[
	TrainerBuilder.luau
	Builds the big object that stands on each trainer territory
	(Config.Trainers[i].Kind). Every object is a Model of anchored,
	non-colliding Parts; the client "breathes" it with Model:ScaleTo and
	squashes it on every Aura tick / click (HubFx). Expensive trainers
	(def.Particles) also emit particles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldKit = require(script.Parent.WorldKit)

local TrainerBuilder = {}

local T = Config.Theme
local FACE = "rbxasset://textures/face.png"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(20, 15, 30)

local function p(model, name, size, cframe, color, material, transparency)
	return WorldKit.Part(model, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
		CanCollide = false,
		CanQuery = false,
	})
end

-- Eyes with a white highlight dot.
local function eyes(model, cf, spread, y, z, size, color)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Eye", Vector3.new(size, size * 1.3, 0.25), cf * CFrame.new(side * spread, y, z), color or BLACK)
		p(model, "EyeShine", Vector3.new(size * 0.35, size * 0.35, 0.1), cf * CFrame.new(side * spread + size * 0.2, y + size * 0.3, z - 0.15), WHITE)
	end
end

local builders = {}

builders.Dummy = function(model, cf, color)
	p(model, "Base", Vector3.new(3, 0.5, 3), cf * CFrame.new(0, 0.25, 0), Color3.fromRGB(90, 60, 35), Enum.Material.Wood)
	p(model, "Post", Vector3.new(0.8, 3, 0.8), cf * CFrame.new(0, 1.9, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	local body = p(model, "Body", Vector3.new(3, 4, 2), cf * CFrame.new(0, 5, 0), Color3.fromRGB(230, 200, 150), Enum.Material.Fabric)
	local head = p(model, "Head", Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(0, 8.1, 0), Color3.fromRGB(230, 200, 150), Enum.Material.Fabric)
	p(model, "Arms", Vector3.new(6, 0.8, 0.8), cf * CFrame.new(0, 6, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	for i, ringSize in ipairs({ 2.2, 1.4, 0.6 }) do
		local ring = p(model, "Target", Vector3.new(0.12, ringSize, ringSize), cf * CFrame.new(0, 5.2, -1.02 - i * 0.04) * CFrame.Angles(0, math.rad(90), 0), if i % 2 == 1 then color else WHITE)
		ring.Shape = Enum.PartType.Cylinder
	end
	p(model, "Patch", Vector3.new(0.9, 0.9, 0.1), cf * CFrame.new(-0.8, 3.7, -1.02) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(190, 150, 100), Enum.Material.Fabric)
	p(model, "Helmet", Vector3.new(2.5, 0.6, 2.5), cf * CFrame.new(0, 9.4, 0), Color3.fromRGB(150, 150, 165), Enum.Material.Metal)
	local face = Instance.new("Decal")
	face.Texture = FACE
	face.Face = Enum.NormalId.Front
	face.Parent = head
	return body, 9.8
end

builders.Boulder = function(model, cf, color)
	local rock = p(model, "Rock", Vector3.new(5.5, 5, 5.5), cf * CFrame.new(0, 2.6, 0) * CFrame.Angles(math.rad(10), math.rad(20), math.rad(5)), Color3.fromRGB(120, 125, 140), Enum.Material.Slate)
	p(model, "Rock2", Vector3.new(3.5, 3, 3.5), cf * CFrame.new(1.2, 5.2, 0.4) * CFrame.Angles(math.rad(-15), math.rad(40), 0), Color3.fromRGB(140, 145, 160), Enum.Material.Slate)
	p(model, "Rock3", Vector3.new(2.4, 2, 2.4), cf * CFrame.new(-2.4, 1, 1.6) * CFrame.Angles(0, math.rad(25), math.rad(10)), Color3.fromRGB(105, 110, 125), Enum.Material.Slate)
	p(model, "Moss", Vector3.new(3, 0.3, 2.6), cf * CFrame.new(1.2, 6.75, 0.4) * CFrame.Angles(math.rad(-15), math.rad(40), 0), Color3.fromRGB(90, 160, 80), Enum.Material.Grass)
	for i = 1, 4 do
		p(model, "Vein", Vector3.new(0.3, 1.4, 0.2), cf * CFrame.new(-2 + i * 0.9, 2.2 + i * 0.5, -2.75) * CFrame.Angles(0, 0, math.rad(25 * i)), color, Enum.Material.Neon)
	end
	eyes(model, cf, 1, 3.4, -2.85, 0.6, BLACK)
	p(model, "Brow", Vector3.new(3, 0.4, 0.3), cf * CFrame.new(0, 4.3, -2.85) * CFrame.Angles(0, 0, math.rad(4)), Color3.fromRGB(80, 85, 100), Enum.Material.Slate)
	return rock, 7.5
end

builders.IceCube = function(model, cf, color)
	local cube = p(model, "Cube", Vector3.new(5, 5, 5), cf * CFrame.new(0, 2.5, 0), Color3.fromRGB(170, 225, 255), Enum.Material.Glass, 0.35)
	p(model, "Heart", Vector3.new(1.8, 1.8, 1.8), cf * CFrame.new(0, 2.5, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), color, Enum.Material.Neon)
	p(model, "Cap", Vector3.new(5.4, 0.6, 5.4), cf * CFrame.new(0, 5.2, 0), Color3.fromRGB(235, 248, 255), Enum.Material.Ice)
	for i = -1, 1 do
		p(model, "Icicle", Vector3.new(0.6, 1.4 + math.abs(i) * 0.5, 0.6), cf * CFrame.new(i * 1.7, 4.4 - math.abs(i) * 0.25, -2.6), Color3.fromRGB(215, 240, 255), Enum.Material.Ice)
		p(model, "Spike", Vector3.new(0.8, 1.6, 0.8), cf * CFrame.new(i * 1.6, 6.2, i * 0.8) * CFrame.Angles(0, math.rad(45), math.rad(i * 12)), Color3.fromRGB(200, 235, 255), Enum.Material.Ice)
	end
	eyes(model, cf, 1, 2.9, -2.6, 0.55, Color3.fromRGB(20, 40, 80))
	p(model, "Mouth", Vector3.new(1.4, 0.3, 0.2), cf * CFrame.new(0, 1.7, -2.6), Color3.fromRGB(20, 40, 80))
	return cube, 7
end

builders.Mimic = function(model, cf, color)
	local chest = p(model, "Chest", Vector3.new(5, 2.6, 3.6), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(140, 85, 45), Enum.Material.Wood)
	p(model, "Lid", Vector3.new(5, 1.4, 3.6), cf * CFrame.new(0, 3.4, 0.9) * CFrame.Angles(math.rad(-40), 0, 0), Color3.fromRGB(160, 100, 50), Enum.Material.Wood)
	p(model, "Band", Vector3.new(5.1, 0.4, 3.7), cf * CFrame.new(0, 1.3, 0), color, Enum.Material.Metal)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Strap", Vector3.new(0.5, 2.7, 3.7), cf * CFrame.new(side * 1.8, 1.3, 0), T.Gold, Enum.Material.Metal)
		p(model, "Foot", Vector3.new(1, 0.5, 1), cf * CFrame.new(side * 1.9, 0.1, -1.2), Color3.fromRGB(100, 60, 30), Enum.Material.Wood)
	end
	p(model, "Lock", Vector3.new(0.9, 1, 0.3), cf * CFrame.new(0, 1.5, -1.9), T.Gold, Enum.Material.Metal)
	p(model, "Tongue", Vector3.new(1.6, 0.3, 2.6), cf * CFrame.new(0, 2.7, -1.4) * CFrame.Angles(math.rad(12), 0, 0), Color3.fromRGB(255, 80, 120))
	for i = -2, 2 do
		p(model, "Tooth", Vector3.new(0.5, 0.8, 0.3), cf * CFrame.new(i * 0.9, 2.9, -1.75), WHITE)
		p(model, "Tooth", Vector3.new(0.5, 0.8, 0.3), cf * CFrame.new(i * 0.9, 3.6, -1.4) * CFrame.Angles(math.rad(-40), 0, 0), WHITE)
	end
	eyes(model, cf * CFrame.Angles(math.rad(-40), 0, 0), 1.2, 4.6, -0.3, 0.55, Color3.fromRGB(255, 220, 60))
	for i = 1, 3 do
		p(model, "Coin", Vector3.new(0.7, 0.15, 0.7), cf * CFrame.new(-1 + i * 0.6, 2.72 + i * 0.05, 0.3), T.Gold, Enum.Material.Metal)
	end
	return chest, 5.8
end

builders.Skull = function(model, cf, color)
	local skull = p(model, "Skull", Vector3.new(5, 4.5, 4.5), cf * CFrame.new(0, 3.4, 0), Color3.fromRGB(235, 235, 240))
	p(model, "Jaw", Vector3.new(4, 1.2, 3.5), cf * CFrame.new(0, 0.7, -0.4), Color3.fromRGB(220, 220, 228))
	p(model, "Cheeks", Vector3.new(5.4, 1, 3), cf * CFrame.new(0, 1.8, -0.4), Color3.fromRGB(226, 226, 234))
	for i = -2, 2 do
		p(model, "Tooth", Vector3.new(0.6, 0.7, 0.3), cf * CFrame.new(i * 0.8, 1.25, -2.15), WHITE)
		p(model, "ToothLow", Vector3.new(0.5, 0.5, 0.3), cf * CFrame.new(i * 0.8, 0.95, -2.2), Color3.fromRGB(240, 240, 235))
	end
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Socket", Vector3.new(1.5, 1.5, 0.4), cf * CFrame.new(side * 1.2, 3.8, -2.2) * CFrame.Angles(0, 0, side * math.rad(-10)), BLACK)
		p(model, "Glow", Vector3.new(0.6, 0.6, 0.3), cf * CFrame.new(side * 1.2, 3.8, -2.32), color, Enum.Material.Neon)
		p(model, "Horn", Vector3.new(0.9, 2.4, 0.9), cf * CFrame.new(side * 2.6, 6, 0) * CFrame.Angles(0, 0, side * math.rad(-28)), Color3.fromRGB(200, 195, 180))
	end
	p(model, "Nose", Vector3.new(0.7, 0.9, 0.3), cf * CFrame.new(0, 2.7, -2.25), BLACK)
	p(model, "Crack", Vector3.new(0.2, 1.6, 0.1), cf * CFrame.new(0.9, 5, -2.27) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(120, 120, 130))
	return skull, 7.2
end

builders.Pumpkin = function(model, cf, color)
	local body = p(model, "Body", Vector3.new(5.5, 4.5, 5.5), cf * CFrame.new(0, 2.3, 0), Color3.fromRGB(255, 130, 30))
	for i = -1, 1 do
		p(model, "Rib", Vector3.new(0.5, 4.6, 5.6), cf * CFrame.new(i * 1.8, 2.3, 0), Color3.fromRGB(225, 105, 20))
	end
	p(model, "Stem", Vector3.new(0.8, 1.4, 0.8), cf * CFrame.new(0, 5.2, 0) * CFrame.Angles(0, 0, math.rad(15)), Color3.fromRGB(70, 130, 50))
	p(model, "Leaf", Vector3.new(1.8, 0.2, 1), cf * CFrame.new(0.9, 4.8, 0) * CFrame.Angles(0, math.rad(20), math.rad(-10)), Color3.fromRGB(90, 170, 70))
	p(model, "Vine", Vector3.new(0.3, 0.3, 2.4), cf * CFrame.new(-1.2, 4.7, 0.8) * CFrame.Angles(0, math.rad(-35), 0), Color3.fromRGB(70, 130, 50))
	p(model, "Mouth", Vector3.new(3.4, 0.9, 0.3), cf * CFrame.new(0, 1.3, -2.8), BLACK)
	p(model, "MouthGlow", Vector3.new(3, 0.5, 0.2), cf * CFrame.new(0, 1.3, -2.86), Color3.fromRGB(255, 220, 90), Enum.Material.Neon)
	for i = -1, 1 do
		p(model, "Fang", Vector3.new(0.5, 0.6, 0.3), cf * CFrame.new(i * 1.1, 1.65, -2.9), Color3.fromRGB(255, 130, 30))
		p(model, "FangLow", Vector3.new(0.5, 0.5, 0.3), cf * CFrame.new(i * 1.1 + 0.55, 0.95, -2.9), Color3.fromRGB(255, 130, 30))
	end
	for _, side in ipairs({ -1, 1 }) do
		p(model, "EyeHole", Vector3.new(1.1, 1.2, 0.3), cf * CFrame.new(side * 1.2, 3.3, -2.8) * CFrame.Angles(0, 0, side * math.rad(20)), BLACK)
		p(model, "EyeGlow", Vector3.new(0.5, 0.6, 0.2), cf * CFrame.new(side * 1.2, 3.2, -2.9), color, Enum.Material.Neon)
	end
	return body, 6.5
end

builders.Golem = function(model, cf, color)
	local stone = Color3.fromRGB(90, 70, 140)
	local dark = Color3.fromRGB(70, 52, 118)
	local torso = p(model, "Torso", Vector3.new(3.5, 3.5, 2.5), cf * CFrame.new(0, 4.2, 0), stone, Enum.Material.Slate)
	p(model, "Head", Vector3.new(2, 2, 2), cf * CFrame.new(0, 7, 0), stone, Enum.Material.Slate)
	p(model, "Belt", Vector3.new(3.7, 0.6, 2.7), cf * CFrame.new(0, 2.7, 0), dark, Enum.Material.Slate)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Arm", Vector3.new(1.4, 3, 1.4), cf * CFrame.new(side * 2.6, 4.4, 0) * CFrame.Angles(0, 0, side * math.rad(10)), dark, Enum.Material.Slate)
		p(model, "Fist", Vector3.new(1.8, 1.6, 1.8), cf * CFrame.new(side * 3, 2.4, 0), stone, Enum.Material.Slate)
		p(model, "Leg", Vector3.new(1.4, 2.5, 1.4), cf * CFrame.new(side * 0.9, 1.25, 0), dark, Enum.Material.Slate)
		p(model, "Shoulder", Vector3.new(1.2, 1.6, 1.2), cf * CFrame.new(side * 2.6, 6.4, 0) * CFrame.Angles(0, math.rad(45), side * math.rad(15)), color, Enum.Material.Glass, 0.15)
		p(model, "BackCrystal", Vector3.new(0.9, 2.2, 0.9), cf * CFrame.new(side * 0.9, 6, 1.3) * CFrame.Angles(math.rad(25), 0, side * math.rad(18)), color, Enum.Material.Glass, 0.15)
	end
	p(model, "Heart", Vector3.new(1.3, 1.3, 0.4), cf * CFrame.new(0, 4.4, -1.3) * CFrame.Angles(0, 0, math.rad(45)), color, Enum.Material.Neon)
	p(model, "HeadCrystal", Vector3.new(0.8, 1.4, 0.8), cf * CFrame.new(0, 8.5, 0) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Glass, 0.15)
	eyes(model, cf, 0.5, 7.1, -1.05, 0.4, color)
	return torso, 9.4
end

builders.Core = function(model, cf, color)
	p(model, "Base", Vector3.new(4.5, 1, 4.5), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(45, 30, 70))
	p(model, "Step", Vector3.new(3.2, 0.6, 3.2), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(65, 45, 100))
	local core = p(model, "Core", Vector3.new(2.6, 2.6, 2.6), cf * CFrame.new(0, 4.4, 0), color, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	local shell = p(model, "Shell", Vector3.new(3.6, 3.6, 3.6), cf * CFrame.new(0, 4.4, 0), Color3.fromRGB(255, 200, 240), Enum.Material.Glass, 0.6)
	shell.Shape = Enum.PartType.Ball
	for i = 0, 2 do
		local ring = p(model, "Ring", Vector3.new(0.25, 5.4, 5.4), cf * CFrame.new(0, 4.4, 0) * CFrame.Angles(math.rad(i * 60), math.rad(i * 30), math.rad(90)), T.Gold, Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
	end
	for i = 0, 3 do
		local angle = i * math.pi / 2
		p(model, "Prong", Vector3.new(0.5, 2.4, 0.5), cf * CFrame.new(math.cos(angle) * 1.8, 2.4, math.sin(angle) * 1.8) * CFrame.Angles(math.sin(angle) * 0.35, 0, -math.cos(angle) * 0.35), Color3.fromRGB(65, 45, 100))
		p(model, "Rune", Vector3.new(0.5, 0.5, 0.1), cf * CFrame.new(math.cos(angle) * 2.26, 0.5, math.sin(angle) * 2.26) * CFrame.Angles(0, -angle + math.pi / 2, 0), color, Enum.Material.Neon)
	end
	WorldKit.Light(core, color, 14, 1.2)
	return core, 7.6
end

-- Premium: golden throne with a crown floating above the seat.
builders.Throne = function(model, cf, color)
	local red = Color3.fromRGB(190, 40, 60)
	local seat = p(model, "Seat", Vector3.new(4, 1, 3.4), cf * CFrame.new(0, 2.6, 0), color, Enum.Material.Metal)
	p(model, "Step1", Vector3.new(6.4, 0.7, 5.4), cf * CFrame.new(0, 0.35, 0), Color3.fromRGB(70, 50, 110))
	p(model, "Step2", Vector3.new(5.2, 0.7, 4.4), cf * CFrame.new(0, 1.05, 0), Color3.fromRGB(95, 70, 140))
	p(model, "SeatBase", Vector3.new(3.6, 0.8, 3), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(180, 140, 40), Enum.Material.Metal)
	p(model, "Cushion", Vector3.new(3.4, 0.5, 2.8), cf * CFrame.new(0, 3.3, -0.1), red, Enum.Material.Fabric)
	p(model, "Back", Vector3.new(4, 6, 0.8), cf * CFrame.new(0, 6, 1.3), color, Enum.Material.Metal)
	p(model, "BackCushion", Vector3.new(3, 4.2, 0.3), cf * CFrame.new(0, 5.8, 0.82), red, Enum.Material.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Arm", Vector3.new(0.8, 1.6, 3.2), cf * CFrame.new(side * 2.1, 3.8, 0), color, Enum.Material.Metal)
		p(model, "ArmGem", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(side * 2.1, 4.8, -1.4) * CFrame.Angles(math.rad(45), 0, math.rad(45)), T.Magenta, Enum.Material.Glass)
		p(model, "Spire", Vector3.new(0.7, 2.2, 0.7), cf * CFrame.new(side * 1.7, 10, 1.3), color, Enum.Material.Metal)
	end
	p(model, "TopGem", Vector3.new(1.2, 1.2, 0.5), cf * CFrame.new(0, 9.4, 1.2) * CFrame.Angles(0, 0, math.rad(45)), T.Cyan, Enum.Material.Glass)
	p(model, "CrownBand", Vector3.new(1.8, 0.5, 1.8), cf * CFrame.new(0, 5.2, -0.2), T.Gold, Enum.Material.Metal)
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		p(model, "CrownSpike", Vector3.new(0.4, 0.8, 0.4), cf * CFrame.new(math.cos(angle) * 0.75, 5.8, -0.2 + math.sin(angle) * 0.75), T.Gold, Enum.Material.Metal)
	end
	return seat, 11
end

-- Premium: golden idol with raised arms and gem eyes.
builders.Idol = function(model, cf, color)
	local gold = color
	local darkGold = Color3.fromRGB(200, 150, 40)
	p(model, "Pedestal", Vector3.new(5, 1.2, 5), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(70, 60, 90), Enum.Material.Slate)
	p(model, "Plinth", Vector3.new(3.8, 0.8, 3.8), cf * CFrame.new(0, 1.6, 0), darkGold, Enum.Material.Metal)
	local body = p(model, "Body", Vector3.new(3.2, 3.6, 2.4), cf * CFrame.new(0, 4.2, 0), gold, Enum.Material.Metal)
	p(model, "Belly", Vector3.new(2, 1.6, 0.4), cf * CFrame.new(0, 3.8, -1.3), darkGold, Enum.Material.Metal)
	p(model, "Head", Vector3.new(2.6, 2.4, 2.4), cf * CFrame.new(0, 7.2, 0), gold, Enum.Material.Metal)
	p(model, "Headdress", Vector3.new(3.6, 1, 1), cf * CFrame.new(0, 8.8, 0.2), darkGold, Enum.Material.Metal)
	for i = -1, 1 do
		p(model, "Feather", Vector3.new(0.7, 1.6 - math.abs(i) * 0.4, 0.3), cf * CFrame.new(i * 1.1, 9.9 - math.abs(i) * 0.2, 0.2), if i == 0 then T.Magenta else T.Cyan, Enum.Material.Glass)
	end
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Arm", Vector3.new(0.9, 2.6, 0.9), cf * CFrame.new(side * 2.3, 5.8, 0) * CFrame.Angles(0, 0, side * math.rad(-35)), gold, Enum.Material.Metal)
		p(model, "Hand", Vector3.new(1.2, 1, 1.2), cf * CFrame.new(side * 3.1, 7.2, 0), darkGold, Enum.Material.Metal)
		p(model, "Leg", Vector3.new(1.2, 1, 1.6), cf * CFrame.new(side * 0.9, 2.4, -0.3), darkGold, Enum.Material.Metal)
		p(model, "EyeGem", Vector3.new(0.6, 0.6, 0.3), cf * CFrame.new(side * 0.6, 7.5, -1.25), Color3.fromRGB(90, 255, 160), Enum.Material.Neon)
	end
	p(model, "Mouth", Vector3.new(1.4, 0.35, 0.2), cf * CFrame.new(0, 6.6, -1.25), BLACK)
	p(model, "ChestGem", Vector3.new(0.9, 0.9, 0.3), cf * CFrame.new(0, 5.2, -1.3) * CFrame.Angles(0, 0, math.rad(45)), T.Red, Enum.Material.Glass)
	return body, 11
end

-- Premium: abyss portal in a broken stone arch with floating shards.
builders.AbyssPortal = function(model, cf, color)
	local stone = Color3.fromRGB(50, 40, 75)
	p(model, "Base", Vector3.new(6.5, 0.8, 3.4), cf * CFrame.new(0, 0.4, 0), stone, Enum.Material.Slate)
	for _, side in ipairs({ -1, 1 }) do
		p(model, "Pillar", Vector3.new(1.3, 7, 1.6), cf * CFrame.new(side * 2.6, 4.3, 0), stone, Enum.Material.Slate)
		p(model, "PillarRune", Vector3.new(0.4, 2.4, 0.1), cf * CFrame.new(side * 2.6, 4.3, -0.85), color, Enum.Material.Neon)
		p(model, "Claw", Vector3.new(0.6, 1.8, 0.6), cf * CFrame.new(side * 3, 8.4, 0) * CFrame.Angles(0, 0, side * math.rad(30)), Color3.fromRGB(30, 22, 50), Enum.Material.Slate)
	end
	p(model, "Lintel", Vector3.new(6.6, 1.2, 1.6), cf * CFrame.new(0, 8.3, 0) * CFrame.Angles(0, 0, math.rad(3)), stone, Enum.Material.Slate)
	local disc = p(model, "Void", Vector3.new(0.3, 5.6, 3.8), cf * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(25, 10, 50), Enum.Material.Glass, 0.1)
	p(model, "Swirl", Vector3.new(0.2, 4.2, 2.6), cf * CFrame.new(0, 4.6, -0.12) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Neon, 0.35)
	p(model, "Eye", Vector3.new(1.4, 0.8, 0.2), cf * CFrame.new(0, 4.8, -0.3), Color3.fromRGB(255, 80, 120), Enum.Material.Neon)
	p(model, "Pupil", Vector3.new(0.4, 0.8, 0.1), cf * CFrame.new(0, 4.8, -0.42), BLACK)
	for i = 1, 5 do
		local angle = i * math.pi * 2 / 5
		p(model, "Shard", Vector3.new(0.5, 1.2, 0.5), cf * CFrame.new(math.cos(angle) * 3.8, 5 + math.sin(angle * 2) * 2.4, -0.6 + math.sin(angle) * 0.6) * CFrame.Angles(angle, angle * 2, 0), Color3.fromRGB(110, 60, 190), Enum.Material.Glass, 0.2)
	end
	WorldKit.Light(disc, color, 14, 1.2)
	return disc, 10
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
	if def.Particles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(def.Color, WHITE)
		emitter.LightEmission = 0.6
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.2, 1)
		emitter.Lifetime = NumberRange.new(1.2, 2)
		emitter.Speed = NumberRange.new(1.5, 3.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = if def.Premium then 14 else 7
		emitter.Parent = primary
	end
	return model, height
end

return TrainerBuilder
