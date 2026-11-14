--[[
	MobBuilder.luau
	Detailed dungeon mobs built from Parts (20-40 each): 3 kinds + a boss
	per biome (Config.Mobs). No assets.

	Rig: an invisible collidable HumanoidRootPart carries a Humanoid
	(R15 mode, HipHeight) so Humanoid:MoveTo walks the mob (MobAI). An
	invisible "Core" part hangs on the root by a Motor6D; static body
	parts are welded to the Core, limbs hang on the Core by Motor6Ds
	with a "Role" attribute (Head, ArmL, ArmR, LegL, LegR, Wing, Tail).
	Clients animate those joints procedurally (MobFx): idle, walk,
	attack wind-up + strike, hit recoil, death burst.

	Part names never match Roblox limb names (Head, Torso...), so the
	Humanoid does not fight over their collisions.
]]

local MobBuilder = {}

local V = Vector3.new
local C = CFrame.new
local function R(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end
local rgb = Color3.fromRGB

local WHITE = Color3.new(1, 1, 1)
local BLACK = rgb(20, 15, 30)
local BONE = rgb(235, 230, 215)
local GOLD = rgb(255, 201, 60)
local IRON = rgb(85, 85, 100)
local STEEL = rgb(170, 175, 190)
local WOOD = rgb(120, 80, 50)
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local SLATE = Enum.Material.Slate
local FABRIC = Enum.Material.Fabric
local ICE = Enum.Material.Ice
local WOODM = Enum.Material.Wood
local BALL = Enum.PartType.Ball

local function darker(c, a)
	return c:Lerp(Color3.new(0, 0, 0), a)
end
local function lighter(c, a)
	return c:Lerp(WHITE, a)
end

---------------------------------------------------------------------
-- Rig
---------------------------------------------------------------------

local Rig = {}
Rig.__index = Rig

-- rootSize / rootY: unscaled size and center height of the root box.
function Rig.new(name: string, scale: number, origin: CFrame, rootSize: Vector3, rootY: number)
	local self = setmetatable({}, Rig)
	self.s = scale
	self.origin = origin
	self.model = Instance.new("Model")
	self.model.Name = name
	self.root = self:raw("HumanoidRootPart", rootSize, C(0, rootY, 0), WHITE, nil, 1)
	self.root.Massless = false
	self.root.CanCollide = true
	self.core = self:raw("Core", V(0.5, 0.5, 0.5), C(0, rootY, 0), WHITE, nil, 1)
	self.core.CanQuery = false
	local joint = Instance.new("Motor6D")
	joint.Name = "CoreJoint"
	joint.Part0 = self.root
	joint.Part1 = self.core
	joint:SetAttribute("Role", "Core")
	joint.Parent = self.root
	self.hipHeight = (rootY - rootSize.Y / 2) * scale
	self.model.PrimaryPart = self.root
	return self
end

-- cf is in the mob's unscaled ground space (y up, -Z front).
function Rig:world(cf: CFrame): CFrame
	return self.origin * (C(cf.Position * self.s) * cf.Rotation)
end

function Rig:raw(name, size, cf, color, material, transparency, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * self.s
	p.CFrame = self:world(cf)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = self.model
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Static part of the body (moves with the Core).
function Rig:body(name, size, cf, color, material, transparency, shape)
	local p = self:raw(name, size, cf, color, material, transparency, shape)
	weld(self.core, p)
	return p
end

-- Animated limb: hangs on the Core by a Motor6D at `joint` (ground space).
function Rig:limb(role: string, joint: Vector3, name, size, cf, color, material, transparency, shape)
	local p = self:raw(name, size, cf, color, material, transparency, shape)
	local pivot = self:world(C(joint))
	local motor = Instance.new("Motor6D")
	motor.Name = "Joint_" .. name
	motor.Part0 = self.core
	motor.Part1 = p
	motor.C0 = self.core.CFrame:ToObjectSpace(pivot)
	motor.C1 = p.CFrame:ToObjectSpace(pivot)
	motor:SetAttribute("Role", role)
	motor.Parent = self.core
	return p, motor
end

-- Part that rides on a limb (or any other part).
function Rig:on(parent, name, size, cf, color, material, transparency, shape)
	local p = self:raw(name, size, cf, color, material, transparency, shape)
	weld(parent, p)
	return p
end

-- Eyes with pupils and a white highlight, on `parent` (front = -Z).
function Rig:eyes(parent, spread, y, z, size, iris, white)
	for _, x in ipairs({ -1, 1 }) do
		self:on(parent, "Eye", V(size, size * 1.15, 0.12), C(x * spread, y, z), white or WHITE)
		self:on(parent, "Pupil", V(size * 0.55, size * 0.65, 0.1), C(x * spread, y - size * 0.08, z - 0.06), iris or BLACK)
		self:on(parent, "Shine", V(size * 0.22, size * 0.22, 0.08), C(x * spread + size * 0.16, y + size * 0.2, z - 0.1), WHITE)
	end
end

function Rig:finish(height: number, color: Color3, float: boolean?)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = self.hipHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = true
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = self.model
	self.model:SetAttribute("Height", height * self.s)
	self.model:SetAttribute("Color", color)
	self.model:SetAttribute("Float", float == true)
	return self.model
end

-- Two-legged base: chest, head, arms with hands, legs with feet.
-- o: Skin, Shirt, Pants, Shoes, LegH, Chest (Vector3), Head (Vector3),
--    Arm (width), ArmLen, Leg (width), material.
local function biped(rig, o)
	local legH = o.LegH or 2
	local chest = o.Chest or V(2, 2, 1)
	local headSize = o.Head or V(1.4, 1.4, 1.4)
	local aw = o.Arm or 0.9
	local armLen = o.ArmLen or 2
	local lw = o.Leg or 0.9
	local shoulderY = legH + chest.Y
	local b = {}
	b.legH, b.chestSize, b.headSize, b.shoulderY = legH, chest, headSize, shoulderY
	b.headY = shoulderY + headSize.Y / 2
	b.top = shoulderY + headSize.Y
	b.chest = rig:body("Chest", chest, C(0, legH + chest.Y / 2, 0), o.Shirt, o.Material)
	b.head = rig:limb("Head", V(0, shoulderY, 0), "Skull", headSize, C(0, b.headY, 0), o.Skin, o.Material)
	local armX = chest.X / 2 + aw / 2
	b.armX = armX
	b.handY = shoulderY - armLen
	b.armR = rig:limb("ArmR", V(armX, shoulderY - 0.25, 0), "ArmR", V(aw, armLen, aw), C(armX, shoulderY - armLen / 2, 0), o.Sleeve or o.Skin, o.Material)
	b.armL = rig:limb("ArmL", V(-armX, shoulderY - 0.25, 0), "ArmL", V(aw, armLen, aw), C(-armX, shoulderY - armLen / 2, 0), o.Sleeve or o.Skin, o.Material)
	rig:on(b.armR, "HandR", V(aw + 0.1, 0.5, aw + 0.1), C(armX, b.handY + 0.2, 0), o.Skin, o.Material)
	rig:on(b.armL, "HandL", V(aw + 0.1, 0.5, aw + 0.1), C(-armX, b.handY + 0.2, 0), o.Skin, o.Material)
	local legX = chest.X / 4
	b.legR = rig:limb("LegR", V(legX, legH, 0), "LegR", V(lw, legH, lw), C(legX, legH / 2, 0), o.Pants, o.Material)
	b.legL = rig:limb("LegL", V(-legX, legH, 0), "LegL", V(lw, legH, lw), C(-legX, legH / 2, 0), o.Pants, o.Material)
	rig:on(b.legR, "FootR", V(lw + 0.15, 0.45, lw + 0.5), C(legX, 0.22, -0.2), o.Shoes or darker(o.Pants, 0.4))
	rig:on(b.legL, "FootL", V(lw + 0.15, 0.45, lw + 0.5), C(-legX, 0.22, -0.2), o.Shoes or darker(o.Pants, 0.4))
	return b
end

local builders = {}

---------------------------------------------------------------------
-- 1. Катакомбы
---------------------------------------------------------------------

builders.ZombieMiner = function(name, s, origin)
	local skin, cloth = rgb(120, 175, 105), rgb(110, 80, 55)
	local rig = Rig.new(name, s, origin, V(2, 2, 1), 3)
	local b = biped(rig, { Skin = skin, Shirt = cloth, Pants = rgb(70, 75, 100), Sleeve = skin })
	local hz = -b.headSize.Z / 2
	-- overalls
	rig:body("Bib", V(1.3, 1.1, 0.1), C(0, 3.3, -0.55), rgb(80, 95, 140), FABRIC)
	for _, x in ipairs({ -1, 1 }) do
		rig:body("Strap", V(0.25, 1, 0.12), C(x * 0.55, 3.75, -0.55), rgb(80, 95, 140), FABRIC)
	end
	rig:body("Tear", V(0.5, 0.3, 0.1), C(-0.5, 2.5, -0.55) * R(0, 0, 20), skin)
	rig:body("Belt", V(2.1, 0.3, 1.1), C(0, 2.2, 0), rgb(60, 40, 30))
	-- face: uneven eyes, teeth
	rig:eyes(b.head, 0.32, b.headY + 0.15, hz, 0.36, rgb(180, 30, 30), rgb(240, 240, 200))
	rig:on(b.head, "Mouth", V(0.8, 0.22, 0.1), C(0, b.headY - 0.35, hz), BLACK)
	for i = -1, 1 do
		rig:on(b.head, "Tooth", V(0.16, 0.2, 0.1), C(i * 0.24, b.headY - 0.28, hz - 0.03), WHITE)
	end
	rig:on(b.head, "Scar", V(0.08, 0.5, 0.08), C(0.45, b.headY + 0.1, hz) * R(0, 0, 20), rgb(70, 110, 60))
	-- miner helmet with a lamp
	rig:on(b.head, "Helmet", V(1.6, 0.6, 1.6), C(0, b.top + 0.1, 0), rgb(240, 200, 60))
	rig:on(b.head, "Brim", V(1.9, 0.14, 1.9), C(0, b.top - 0.15, 0), rgb(210, 170, 40))
	local lamp = rig:on(b.head, "Lamp", V(0.4, 0.4, 0.2), C(0, b.top + 0.15, -0.85), rgb(255, 245, 190), NEON)
	local light = Instance.new("SpotLight")
	light.Color = rgb(255, 240, 190)
	light.Range = 18 * s
	light.Brightness = 1.2
	light.Face = Enum.NormalId.Front
	light.Parent = lamp
	-- pickaxe in the right hand, bone sticking out of the left arm
	rig:on(b.armR, "PickHandle", V(0.22, 2.6, 0.22), C(b.armX, b.handY + 0.6, -0.5) * R(60, 0, 0), WOOD, WOODM)
	rig:on(b.armR, "PickHead", V(1.8, 0.3, 0.3), C(b.armX, b.handY + 1.25, -1.6) * R(60, 0, 0), IRON, METAL)
	rig:on(b.armL, "Bone", V(0.2, 0.6, 0.2), C(-b.armX - 0.3, b.handY + 1.2, 0) * R(0, 0, 50), BONE)
	return rig:finish(b.top + 0.5, skin)
end

builders.SkeletonArcher = function(name, s, origin)
	local dark = rgb(60, 55, 70)
	local rig = Rig.new(name, s, origin, V(2, 2, 1), 3)
	local b = biped(rig, { Skin = BONE, Shirt = dark, Pants = BONE, Arm = 0.5, Leg = 0.5, Chest = V(1.3, 2, 0.6), Shoes = BONE })
	local hz = -b.headSize.Z / 2
	rig:body("Spine", V(0.3, 2, 0.3), C(0, 3, 0.1), BONE)
	for i = 0, 3 do
		rig:body("Rib", V(1.5 - i * 0.12, 0.16, 0.9), C(0, 3.8 - i * 0.42, 0), BONE)
	end
	rig:body("Pelvis", V(1.3, 0.4, 0.7), C(0, 2.1, 0), darker(BONE, 0.1))
	-- skull: sockets with a cold glow, nose, teeth
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Socket", V(0.4, 0.42, 0.12), C(x * 0.32, b.headY + 0.15, hz), BLACK)
		rig:on(b.head, "Glow", V(0.16, 0.16, 0.08), C(x * 0.32, b.headY + 0.15, hz - 0.05), rgb(46, 230, 255), NEON)
	end
	rig:on(b.head, "Nose", V(0.16, 0.22, 0.1), C(0, b.headY - 0.12, hz), BLACK)
	rig:on(b.head, "Jaw", V(1, 0.3, 1), C(0, b.headY - 0.62, -0.1), darker(BONE, 0.08))
	for i = -2, 2 do
		rig:on(b.head, "Tooth", V(0.14, 0.18, 0.08), C(i * 0.18, b.headY - 0.42, hz - 0.02), WHITE)
	end
	rig:on(b.head, "Hood", V(1.6, 0.5, 1.6), C(0, b.top + 0.05, 0.05), rgb(70, 110, 80), FABRIC)
	rig:on(b.head, "HoodBack", V(1.6, 1.2, 0.3), C(0, b.headY + 0.1, 0.8), rgb(70, 110, 80), FABRIC)
	-- bow in the left hand
	for i, a in ipairs({ -28, 0, 28 }) do
		rig:on(b.armL, "Bow" .. i, V(0.18, 1.1, 0.18), C(-b.armX, b.handY + 0.3 + (i - 2) * 1, -0.6 - math.abs(i - 2) * -0.25) * R(a, 0, 0), WOOD, WOODM)
	end
	rig:on(b.armL, "String", V(0.05, 2.9, 0.05), C(-b.armX, b.handY + 0.3, -0.15), WHITE)
	-- quiver with arrows on the back
	rig:body("Quiver", V(0.6, 1.6, 0.5), C(0.35, 3.3, 0.6) * R(0, 0, -15), rgb(110, 70, 45), FABRIC)
	for i = 0, 2 do
		rig:body("Arrow", V(0.08, 0.7, 0.08), C(0.45 + i * 0.14, 4.35, 0.6) * R(0, 0, -15), WOOD)
		rig:body("Fletch", V(0.2, 0.2, 0.06), C(0.52 + i * 0.14, 4.7, 0.6) * R(0, 0, -15), rgb(200, 60, 60))
	end
	return rig:finish(b.top + 0.4, BONE)
end

-- Slime body shared by the acid slime and the Slime King.
local function slimeBody(rig, color, y)
	local glass = function(name, size, cf, transparency)
		return rig:body(name, size, cf, color, GLASS, transparency or 0.3, BALL)
	end
	rig:body("Puddle", V(0.3, 5, 5), C(0, 0.15, 0) * R(0, 0, 90), darker(color, 0.2), GLASS, 0.4, Enum.PartType.Cylinder)
	local body = glass("Body", V(4, 4, 4), C(0, y, 0))
	glass("Top", V(2.6, 2.6, 2.6), C(0.2, y + 1.3, 0))
	rig:body("CoreGlow", V(1.5, 1.5, 1.5), C(0, y - 0.2, 0), lighter(color, 0.45), NEON, 0, BALL)
	rig:eyes(body, 0.6, y + 0.4, -1.92, 0.6, BLACK)
	rig:on(body, "Mouth", V(1.2, 0.3, 0.12), C(0, y - 0.5, -1.95), BLACK)
	for _, x in ipairs({ -1, 1 }) do
		rig:on(body, "Fang", V(0.22, 0.3, 0.1), C(x * 0.4, y - 0.42, -1.99), WHITE)
		glass("Drip", V(0.7, 0.7, 0.7), C(x * 1.9, y - 1, 0.5))
		glass("Blob", V(1.1, 1.1, 1.1), C(x * 1.6, 0.6, -1))
	end
	for i = 1, 3 do
		rig:body("Bubble", V(0.4, 0.4, 0.4), C(-1 + i * 0.6, y + 0.3 + i * 0.3, 0.6), WHITE, GLASS, 0.5, BALL)
	end
	-- things it has eaten
	rig:body("BoneInside", V(0.25, 1.1, 0.25), C(0.7, y - 0.6, 0.5) * R(30, 0, 40), BONE)
	rig:body("SkullInside", V(0.6, 0.6, 0.6), C(-0.8, y - 0.7, 0.3) * R(10, 30, 0), BONE)
	return body
end

builders.AcidSlime = function(name, s, origin)
	local color = rgb(150, 240, 70)
	local rig = Rig.new(name, s, origin, V(4, 3.4, 4), 1.7)
	slimeBody(rig, color, 1.9)
	rig.model:SetAttribute("Hop", true)
	return rig:finish(4.4, color)
end

builders.SlimeKing = function(name, s, origin)
	local color = rgb(60, 220, 100)
	local rig = Rig.new(name, s, origin, V(4, 3.4, 4), 1.7)
	local body = slimeBody(rig, color, 1.9)
	rig.model:SetAttribute("Hop", true)
	-- crown
	rig:on(body, "CrownBand", V(2, 0.5, 2), C(0.2, 4.3, 0), GOLD, METAL)
	for i = 0, 4 do
		local angle = i * math.pi * 2 / 5
		rig:on(body, "CrownPoint", V(0.4, 0.8, 0.4), C(0.2 + math.cos(angle) * 0.8, 4.9, math.sin(angle) * 0.8), GOLD, METAL)
		rig:on(body, "CrownGem", V(0.26, 0.26, 0.26), C(0.2 + math.cos(angle) * 0.8, 5.4, math.sin(angle) * 0.8), rgb(255, 70, 90), GLASS, 0, BALL)
	end
	-- royal mustache, cape collar and a sceptre stuck in the jelly
	for _, x in ipairs({ -1, 1 }) do
		rig:on(body, "Mustache", V(0.9, 0.24, 0.14), C(x * 0.6, 1.75, -2) * R(0, 0, x * -18), rgb(30, 110, 50))
	end
	rig:body("Collar", V(4.4, 0.7, 2.4), C(0, 0.9, 1.3), rgb(190, 40, 60), FABRIC)
	rig:body("CollarFur", V(4.5, 0.3, 2.5), C(0, 1.3, 1.3), WHITE, FABRIC)
	local arm = rig:limb("ArmR", V(2, 2, 0), "Sceptre", V(0.3, 3.6, 0.3), C(2.4, 2.6, -0.4) * R(0, 0, -20), GOLD, METAL)
	rig:on(arm, "SceptreOrb", V(0.9, 0.9, 0.9), C(3.05, 4.5, -0.4), rgb(120, 255, 150), NEON, 0, BALL)
	return rig:finish(5.8, color)
end

---------------------------------------------------------------------
-- 2. Ледяной грот
---------------------------------------------------------------------

builders.SnowGolem = function(name, s, origin)
	local snow = rgb(240, 247, 255)
	local rig = Rig.new(name, s, origin, V(3, 4, 3), 2)
	rig:body("Bottom", V(3.4, 3.4, 3.4), C(0, 1.7, 0), snow, nil, 0, BALL)
	local mid = rig:body("Middle", V(2.6, 2.6, 2.6), C(0, 3.9, 0), snow, nil, 0, BALL)
	local head = rig:limb("Head", V(0, 5, 0), "SnowHead", V(1.9, 1.9, 1.9), C(0, 5.7, 0), snow, nil, 0, BALL)
	for i = 0, 2 do
		rig:on(mid, "Button", V(0.3, 0.3, 0.2), C(0, 3.3 + i * 0.55, -1.28 + math.abs(i - 1) * 0.1), BLACK, nil, 0, BALL)
	end
	rig:eyes(head, 0.36, 5.9, -0.9, 0.34, BLACK, BLACK)
	rig:on(head, "Carrot", V(0.26, 0.26, 0.9), C(0, 5.62, -1.3), rgb(255, 140, 40))
	for i = -2, 2 do
		rig:on(head, "Smile", V(0.14, 0.14, 0.1), C(i * 0.22, 5.25 + math.abs(i) * 0.07, -0.9), BLACK)
	end
	-- bucket hat and scarf
	rig:on(head, "HatBrim", V(1.7, 0.16, 1.7), C(0, 6.55, 0), rgb(70, 80, 110))
	rig:on(head, "Hat", V(1.2, 0.9, 1.2), C(0, 7.05, 0), rgb(90, 100, 135), METAL)
	rig:body("Scarf", V(2.2, 0.45, 2.2), C(0, 4.95, 0), rgb(220, 60, 70), FABRIC)
	rig:body("ScarfEnd", V(0.5, 1.3, 0.2), C(0.7, 4.3, -1.15) * R(0, 0, 8), rgb(220, 60, 70), FABRIC)
	-- stick arms with twig fingers, ice spikes on the shoulders
	for _, x in ipairs({ -1, 1 }) do
		local role = if x > 0 then "ArmR" else "ArmL"
		local arm = rig:limb(role, V(x * 1.2, 4.3, 0), role, V(0.3, 2.4, 0.3), C(x * 2, 3.5, 0) * R(0, 0, x * 40), WOOD, WOODM)
		rig:on(arm, "Twig", V(0.18, 0.7, 0.18), C(x * 2.9, 2.5, 0) * R(0, 0, x * 80), WOOD, WOODM)
		rig:on(arm, "Twig", V(0.18, 0.7, 0.18), C(x * 2.6, 2.3, 0) * R(0, 0, x * 10), WOOD, WOODM)
		rig:on(mid, "IceSpike", V(0.5, 1.1, 0.5), C(x * 0.9, 5, 0.5) * R(-20, 0, x * -25), rgb(170, 225, 255), GLASS, 0.15)
		rig:body("SnowFoot", V(1.4, 0.7, 1.6), C(x * 0.9, 0.35, -0.9), snow)
	end
	return rig:finish(7.6, snow)
end

builders.IceSpider = function(name, s, origin)
	local shell, pale = rgb(110, 190, 245), rgb(200, 235, 255)
	local rig = Rig.new(name, s, origin, V(3, 1.6, 3.4), 1.9)
	local thorax = rig:body("Thorax", V(1.8, 1.3, 1.8), C(0, 1.9, -0.3), shell, ICE)
	rig:body("Abdomen", V(2.6, 2.2, 2.6), C(0, 2.3, 1.7), shell, ICE, 0, BALL)
	rig:body("AbdomenMark", V(1, 0.1, 1), C(0, 3.4, 1.7) * R(0, 45, 0), pale, NEON)
	local head = rig:limb("Head", V(0, 1.9, -1.1), "SpiderHead", V(1.2, 1, 1), C(0, 1.85, -1.6), darker(shell, 0.15), ICE)
	for i = 0, 2 do
		for _, x in ipairs({ -1, 1 }) do
			rig:on(head, "Eye", V(0.24 - i * 0.04, 0.24 - i * 0.04, 0.1), C(x * (0.18 + i * 0.17), 2.05 + i * 0.12, -2.12), rgb(255, 60, 90), if i == 0 then NEON else GLASS, 0, BALL)
		end
	end
	for _, x in ipairs({ -1, 1 }) do
		rig:on(head, "Fang", V(0.2, 0.6, 0.2), C(x * 0.3, 1.3, -2.05) * R(15, 0, x * 12), pale, GLASS, 0.1)
	end
	-- 8 legs: thigh up and out, shin down
	for i = 0, 3 do
		for _, x in ipairs({ -1, 1 }) do
			local z = -0.9 + i * 0.6
			local role = if (i + (if x > 0 then 0 else 1)) % 2 == 0 then "LegL" else "LegR"
			local leg = rig:limb(role, V(x * 0.8, 2, z), "Thigh" .. i .. x, V(1.9, 0.3, 0.3), C(x * 1.65, 2.6, z + (i - 1.5) * 0.25) * R(0, x * (i - 1.5) * -14, x * 38), shell, ICE)
			rig:on(leg, "Shin", V(0.26, 3, 0.26), C(x * 2.75, 1.55, z + (i - 1.5) * 0.5) * R(0, 0, x * 14), pale, ICE)
		end
	end
	-- ice crystals on the back
	for i = 0, 2 do
		rig:body("Crystal", V(0.5, 1.3 - i * 0.2, 0.5), C(-0.6 + i * 0.6, 3.7 - math.abs(i - 1) * 0.2, 1.7 + (i - 1) * 0.3) * R(-15 + i * 12, 45, (i - 1) * 18), pale, GLASS, 0.15)
	end
	rig:on(thorax, "Frost", V(1.4, 0.12, 1.4), C(0, 2.6, -0.3), WHITE, ICE)
	return rig:finish(4.2, shell)
end

builders.Yeti = function(name, s, origin)
	local fur, face = rgb(225, 235, 248), rgb(110, 160, 215)
	local rig = Rig.new(name, s, origin, V(2.8, 2.6, 1.6), 3.1)
	local b = biped(rig, { Skin = fur, Shirt = fur, Pants = fur, Chest = V(2.8, 2.6, 1.6), Head = V(1.8, 1.6, 1.6), Arm = 1.1, ArmLen = 3, Leg = 1.1, LegH = 1.8, Shoes = face, Material = FABRIC })
	local hz = -b.headSize.Z / 2
	rig:body("Belly", V(1.8, 1.6, 0.14), C(0, 2.9, -0.82), lighter(face, 0.35))
	rig:on(b.head, "FacePlate", V(1.3, 1, 0.14), C(0, b.headY - 0.1, hz - 0.02), face)
	rig:eyes(b.head, 0.32, b.headY + 0.12, hz - 0.1, 0.3, rgb(255, 220, 60), BLACK)
	rig:on(b.head, "Brow", V(1.2, 0.2, 0.16), C(0, b.headY + 0.42, hz - 0.1) * R(0, 0, 0), darker(face, 0.35))
	rig:on(b.head, "Mouth", V(0.9, 0.28, 0.1), C(0, b.headY - 0.45, hz - 0.1), BLACK)
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Fang", V(0.18, 0.34, 0.12), C(x * 0.32, b.headY - 0.36, hz - 0.14), WHITE)
		rig:on(b.head, "Horn", V(0.4, 1, 0.4), C(x * 0.9, b.top + 0.2, 0) * R(0, 0, x * -30), rgb(90, 110, 150))
		rig:on(b.head, "HornTip", V(0.26, 0.6, 0.26), C(x * 1.25, b.top + 0.85, 0) * R(0, 0, x * -5), rgb(200, 220, 240))
		rig:body("ShoulderFur", V(1.4, 0.8, 1.9), C(x * 1.6, 4.5, 0) * R(0, 0, x * -12), WHITE, FABRIC)
		local arm = if x > 0 then b.armR else b.armL
		for c = -1, 1 do
			rig:on(arm, "Claw", V(0.2, 0.5, 0.2), C(x * b.armX + c * 0.35, b.handY - 0.2, -0.3) * R(25, 0, 0), rgb(60, 70, 95))
		end
	end
	for i = 0, 4 do
		rig:body("Tuft", V(0.5, 0.7, 0.4), C(-1.2 + i * 0.6, 4.3 - (i % 2) * 1.3, 0.85) * R(-20, 0, (i - 2) * 10), WHITE, FABRIC)
	end
	rig:on(b.head, "HeadTuft", V(0.7, 0.6, 0.7), C(0, b.top + 0.2, 0.1) * R(0, 45, 0), WHITE, FABRIC)
	return rig:finish(b.top + 1, fur)
end

builders.IceBoneLord = function(name, s, origin)
	local bone, ice, glow = rgb(205, 235, 255), rgb(120, 210, 255), rgb(46, 230, 255)
	local rig = Rig.new(name, s, origin, V(2, 2, 1), 3)
	local b = biped(rig, { Skin = bone, Shirt = rgb(40, 60, 100), Pants = bone, Arm = 0.55, Leg = 0.55, Chest = V(1.5, 2, 0.7), Shoes = ice })
	local hz = -b.headSize.Z / 2
	for i = 0, 3 do
		rig:body("Rib", V(1.7 - i * 0.12, 0.18, 1), C(0, 3.8 - i * 0.42, 0), bone)
	end
	rig:body("Heart", V(0.5, 0.5, 0.5), C(0, 3.4, -0.2) * R(45, 45, 0), glow, NEON)
	rig:body("Pelvis", V(1.5, 0.45, 0.8), C(0, 2.1, 0), darker(bone, 0.1))
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Socket", V(0.42, 0.46, 0.12), C(x * 0.32, b.headY + 0.15, hz), BLACK)
		rig:on(b.head, "Glow", V(0.2, 0.2, 0.08), C(x * 0.32, b.headY + 0.15, hz - 0.05), glow, NEON)
		rig:body("Pauldron", V(1.1, 0.6, 1.2), C(x * 1.2, 4.1, 0) * R(0, 0, x * -15), ice, ICE)
		rig:body("PauldronSpike", V(0.36, 1, 0.36), C(x * 1.5, 4.8, 0) * R(0, 0, x * -30), lighter(ice, 0.4), GLASS, 0.15)
	end
	rig:on(b.head, "Nose", V(0.18, 0.24, 0.1), C(0, b.headY - 0.12, hz), BLACK)
	rig:on(b.head, "Jaw", V(1, 0.3, 1), C(0, b.headY - 0.62, -0.1), darker(bone, 0.1))
	for i = -2, 2 do
		rig:on(b.head, "Tooth", V(0.14, 0.2, 0.08), C(i * 0.18, b.headY - 0.42, hz - 0.02), WHITE)
		-- crown of ice
		rig:on(b.head, "CrownSpike", V(0.26, 0.9 - math.abs(i) * 0.18, 0.26), C(i * 0.3, b.top + 0.4 - math.abs(i) * 0.08, 0) * R(0, 45, i * -8), lighter(ice, 0.3), GLASS, 0.15)
	end
	rig:on(b.head, "CrownBand", V(1.5, 0.26, 1.5), C(0, b.top + 0.05, 0), ice, ICE)
	rig:body("Cape", V(1.9, 3.4, 0.14), C(0, 2.6, 0.55) * R(-8, 0, 0), rgb(40, 60, 110), FABRIC)
	rig:body("CapeTrim", V(1.9, 0.24, 0.16), C(0, 1, 0.78) * R(-8, 0, 0), glow, NEON)
	-- great ice sword in the right hand
	rig:on(b.armR, "SwordHilt", V(0.24, 0.9, 0.24), C(b.armX, b.handY + 0.2, -0.5) * R(75, 0, 0), IRON, METAL)
	rig:on(b.armR, "SwordGuard", V(1.2, 0.24, 0.3), C(b.armX, b.handY + 0.35, -1) * R(75, 0, 0), GOLD, METAL)
	rig:on(b.armR, "SwordBlade", V(0.6, 3, 0.16), C(b.armX, b.handY + 0.78, -2.6) * R(75, 0, 0), ice, GLASS, 0.15)
	rig:on(b.armR, "SwordCore", V(0.16, 2.6, 0.18), C(b.armX, b.handY + 0.76, -2.5) * R(75, 0, 0), WHITE, NEON)
	return rig:finish(b.top + 1.2, bone)
end

---------------------------------------------------------------------
-- 3. Лавовая кузня
---------------------------------------------------------------------

builders.FireImp = function(name, s, origin)
	local skin, dark = rgb(235, 80, 50), rgb(150, 35, 30)
	local rig = Rig.new(name, s, origin, V(1.6, 1.6, 1), 2.2)
	local b = biped(rig, { Skin = skin, Shirt = skin, Pants = dark, Chest = V(1.6, 1.6, 1), Head = V(1.9, 1.7, 1.7), Arm = 0.6, ArmLen = 1.6, Leg = 0.6, LegH = 1.4, Shoes = BLACK })
	local hz = -b.headSize.Z / 2
	rig:body("Belly", V(1, 0.9, 0.12), C(0, 2.1, -0.52), rgb(255, 150, 90))
	rig:eyes(b.head, 0.42, b.headY + 0.15, hz, 0.46, BLACK, rgb(255, 230, 90))
	rig:on(b.head, "Grin", V(1.2, 0.3, 0.1), C(0, b.headY - 0.45, hz), BLACK)
	for i = -2, 2 do
		rig:on(b.head, "Tooth", V(0.16, 0.22, 0.1), C(i * 0.24, b.headY - 0.38, hz - 0.03) * R(0, 0, 45), WHITE)
	end
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Horn", V(0.36, 0.8, 0.36), C(x * 0.7, b.top + 0.25, 0) * R(0, 0, x * -22), dark)
		rig:on(b.head, "HornTip", V(0.22, 0.5, 0.22), C(x * 0.95, b.top + 0.8, 0) * R(0, 0, x * 5), BLACK)
		rig:on(b.head, "Ear", V(0.7, 0.4, 0.16), C(x * 1.2, b.headY + 0.1, 0) * R(0, 0, x * 25), skin)
		local wing = rig:limb("Wing", V(x * 0.5, 2.7, 0.55), "Wing" .. x, V(1.5, 0.9, 0.1), C(x * 1.3, 3, 0.7) * R(0, x * -20, x * 25), dark)
		rig:on(wing, "WingTip", V(0.9, 0.6, 0.1), C(x * 2.2, 3.5, 0.9) * R(0, x * -20, x * 50), BLACK)
	end
	-- flame on the head
	rig:on(b.head, "Flame", V(0.6, 0.9, 0.6), C(0, b.top + 0.4, 0) * R(0, 45, 0), rgb(255, 150, 40), NEON)
	rig:on(b.head, "FlameTip", V(0.3, 0.6, 0.3), C(0.1, b.top + 1, 0) * R(0, 45, 10), rgb(255, 230, 100), NEON)
	-- tail and trident
	local tail = rig:limb("Tail", V(0, 1.6, 0.5), "Tail", V(0.25, 0.25, 1.5), C(0, 1.4, 1.2) * R(-20, 0, 0), skin)
	rig:on(tail, "TailEnd", V(0.2, 0.2, 1), C(0, 1.9, 2.2) * R(-50, 0, 0), skin)
	rig:on(tail, "TailSpade", V(0.5, 0.5, 0.14), C(0, 2.5, 2.6) * R(0, 0, 45), dark)
	rig:on(b.armR, "Trident", V(0.16, 3.4, 0.16), C(b.armX, b.handY + 1.1, -0.45), IRON, METAL)
	rig:on(b.armR, "TridentBar", V(1, 0.16, 0.16), C(b.armX, b.handY + 2.7, -0.45), IRON, METAL)
	for i = -1, 1 do
		rig:on(b.armR, "Prong", V(0.16, 0.7, 0.16), C(b.armX + i * 0.42, b.handY + 3.1, -0.45), rgb(255, 150, 40), METAL)
	end
	return rig:finish(b.top + 1.3, skin)
end

builders.MagmaGolem = function(name, s, origin)
	local rock, dark, lava = rgb(95, 60, 55), rgb(60, 40, 42), rgb(255, 120, 30)
	local rig = Rig.new(name, s, origin, V(3.4, 3, 2.2), 3)
	local b = biped(rig, { Skin = rock, Shirt = rock, Pants = dark, Chest = V(3.4, 3, 2.2), Head = V(1.5, 1.2, 1.4), Arm = 1.4, ArmLen = 3.2, Leg = 1.3, LegH = 1.5, Shoes = dark, Material = SLATE })
	local hz = -b.headSize.Z / 2
	-- molten core and cracks
	rig:body("CoreGlow", V(1.3, 1.3, 0.2), C(0, 3.2, -1.1) * R(0, 0, 45), lava, NEON)
	for i, crack in ipairs({ { -1, 3.9, 30 }, { 0.9, 3.8, -35 }, { -0.8, 2.3, -25 }, { 1, 2.2, 40 } }) do
		rig:body("Crack" .. i, V(1.1, 0.14, 0.12), C(crack[1], crack[2], -1.12) * R(0, 0, crack[3]), rgb(255, 190, 70), NEON)
	end
	rig:body("BackRock", V(2.4, 1.6, 1), C(0, 4.2, 1.3) * R(-15, 0, 0), dark, SLATE)
	rig:body("BackSpike", V(0.7, 1.4, 0.7), C(0.6, 5.2, 1.2) * R(-20, 30, 10), dark, SLATE)
	rig:body("BackSpike", V(0.6, 1.1, 0.6), C(-0.7, 5, 1.2) * R(-20, 0, -15), dark, SLATE)
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Eye", V(0.4, 0.24, 0.1), C(x * 0.36, b.headY + 0.1, hz - 0.02) * R(0, 0, x * -12), rgb(255, 220, 90), NEON)
		rig:body("Shoulder", V(1.9, 1.3, 2.2), C(x * 2.3, 4.5, 0) * R(0, 0, x * -10), dark, SLATE)
		local arm = if x > 0 then b.armR else b.armL
		rig:on(arm, "Fist", V(1.9, 1.5, 1.9), C(x * b.armX, b.handY + 0.2, 0), rock, SLATE)
		rig:on(arm, "ArmCrack", V(0.14, 1.4, 0.12), C(x * b.armX, b.handY + 1.8, -0.72) * R(0, 0, x * 15), lava, NEON)
		rig:on(arm, "Knuckle", V(1.5, 0.3, 0.2), C(x * b.armX, b.handY + 0.1, -0.98), dark, SLATE)
	end
	rig:on(b.head, "Jaw", V(1.3, 0.4, 1.3), C(0, b.headY - 0.55, -0.1), dark, SLATE)
	rig:on(b.head, "MouthGlow", V(0.8, 0.14, 0.1), C(0, b.headY - 0.34, hz - 0.04), lava, NEON)
	rig:on(b.head, "Crest", V(0.5, 0.6, 1), C(0, b.top + 0.2, 0), dark, SLATE)
	return rig:finish(b.top + 0.9, rock)
end

builders.GoblinSmith = function(name, s, origin)
	local skin, leather = rgb(115, 175, 75), rgb(120, 75, 45)
	local rig = Rig.new(name, s, origin, V(2, 1.8, 1.1), 2.5)
	local b = biped(rig, { Skin = skin, Shirt = rgb(150, 140, 120), Pants = rgb(80, 60, 50), Chest = V(2, 1.8, 1.1), Head = V(1.9, 1.6, 1.6), Arm = 0.8, ArmLen = 1.9, Leg = 0.8, LegH = 1.6, Shoes = BLACK })
	local hz = -b.headSize.Z / 2
	rig:body("Apron", V(1.7, 2.1, 0.12), C(0, 2.3, -0.6), leather, FABRIC)
	rig:body("ApronPocket", V(0.8, 0.5, 0.1), C(0, 1.9, -0.67), darker(leather, 0.25), FABRIC)
	rig:body("Belt", V(2.1, 0.3, 1.2), C(0, 1.75, 0), BLACK)
	rig:body("Tongs", V(0.14, 1, 0.14), C(-0.8, 1.4, -0.65) * R(0, 0, 12), IRON, METAL)
	rig:body("Pouch", V(0.5, 0.5, 0.3), C(0.8, 1.5, -0.65), darker(leather, 0.3), FABRIC)
	-- goggles pushed over the eyes, long nose, ears
	rig:on(b.head, "GoggleStrap", V(1.95, 0.22, 1.65), C(0, b.headY + 0.25, 0), BLACK)
	for _, x in ipairs({ -1, 1 }) do
		local lens = rig:on(b.head, "Goggle", V(0.14, 0.62, 0.62), C(x * 0.42, b.headY + 0.25, hz - 0.05) * R(0, 90, 0), rgb(255, 190, 80), GLASS, 0.15, Enum.PartType.Cylinder)
		lens.Name = "Goggle"
		rig:on(b.head, "GoggleRim", V(0.1, 0.76, 0.76), C(x * 0.42, b.headY + 0.25, hz) * R(0, 90, 0), rgb(160, 120, 50), METAL, 0, Enum.PartType.Cylinder)
		rig:on(b.head, "Ear", V(1, 0.5, 0.16), C(x * 1.35, b.headY + 0.1, 0.1) * R(0, 0, x * 22), skin)
		rig:on(b.head, "EarTip", V(0.5, 0.3, 0.14), C(x * 1.95, b.headY + 0.42, 0.1) * R(0, 0, x * 40), darker(skin, 0.15))
	end
	rig:on(b.head, "Nose", V(0.36, 0.4, 0.8), C(0, b.headY - 0.1, hz - 0.35), darker(skin, 0.12))
	rig:on(b.head, "Mouth", V(1, 0.2, 0.1), C(0, b.headY - 0.5, hz), BLACK)
	rig:on(b.head, "Tusk", V(0.18, 0.3, 0.12), C(-0.36, b.headY - 0.4, hz - 0.03), WHITE)
	rig:on(b.head, "Tusk", V(0.18, 0.3, 0.12), C(0.36, b.headY - 0.4, hz - 0.03), WHITE)
	rig:on(b.head, "Bandana", V(1.95, 0.4, 1.65), C(0, b.top - 0.1, 0), rgb(200, 60, 50), FABRIC)
	-- forge hammer in the right hand, glove on the left
	rig:on(b.armR, "HammerHandle", V(0.24, 2.4, 0.24), C(b.armX, b.handY + 0.7, -0.5) * R(50, 0, 0), WOOD, WOODM)
	rig:on(b.armR, "HammerHead", V(1.3, 0.8, 0.8), C(b.armX, b.handY + 1.5, -1.45) * R(50, 0, 0), IRON, METAL)
	rig:on(b.armR, "HammerHot", V(0.3, 0.82, 0.82), C(b.armX + 0.55, b.handY + 1.5, -1.45) * R(50, 0, 0), rgb(255, 140, 40), NEON)
	rig:on(b.armL, "Glove", V(1, 0.8, 1), C(-b.armX, b.handY + 0.3, 0), leather, FABRIC)
	return rig:finish(b.top + 0.4, skin)
end

builders.FireChief = function(name, s, origin)
	local skin, armor, fire = rgb(215, 95, 45), rgb(70, 50, 45), rgb(255, 150, 40)
	local rig = Rig.new(name, s, origin, V(2.6, 2.2, 1.4), 2.9)
	local b = biped(rig, { Skin = skin, Shirt = armor, Pants = rgb(90, 55, 40), Chest = V(2.6, 2.2, 1.4), Head = V(1.9, 1.6, 1.6), Arm = 1, ArmLen = 2.4, Leg = 1, LegH = 1.8, Shoes = BLACK })
	local hz = -b.headSize.Z / 2
	rig:body("ChestPlate", V(2.2, 1.5, 0.16), C(0, 3.2, -0.74), IRON, METAL)
	rig:body("ChestRune", V(0.7, 0.7, 0.1), C(0, 3.3, -0.84) * R(0, 0, 45), fire, NEON)
	rig:body("Belt", V(2.7, 0.4, 1.5), C(0, 2, 0), BLACK)
	rig:body("BeltSkull", V(0.6, 0.6, 0.3), C(0, 2, -0.8), BONE)
	for i = -2, 2 do
		rig:body("NecklaceTooth", V(0.18, 0.36, 0.12), C(i * 0.4, 4 - math.abs(i) * 0.08, -0.76), WHITE)
	end
	rig:body("Cape", V(2.6, 3.4, 0.14), C(0, 2.6, 0.82) * R(-7, 0, 0), rgb(150, 35, 30), FABRIC)
	-- face: war paint, tusks, burning eyes
	rig:eyes(b.head, 0.4, b.headY + 0.12, hz, 0.4, rgb(255, 230, 90), rgb(255, 120, 30))
	rig:on(b.head, "Paint", V(1.9, 0.2, 0.08), C(0, b.headY - 0.15, hz - 0.01), WHITE)
	rig:on(b.head, "Mouth", V(1.1, 0.26, 0.1), C(0, b.headY - 0.5, hz), BLACK)
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Tusk", V(0.24, 0.6, 0.2), C(x * 0.5, b.headY - 0.32, hz - 0.06) * R(0, 0, x * -8), WHITE)
		rig:on(b.head, "Ear", V(0.9, 0.5, 0.16), C(x * 1.3, b.headY, 0.1) * R(0, 0, x * 20), skin)
		-- horned helmet
		rig:on(b.head, "HelmHorn", V(0.5, 1.2, 0.5), C(x * 1.1, b.top + 0.4, 0) * R(0, 0, x * -35), BONE)
		rig:on(b.head, "HelmHornTip", V(0.34, 0.8, 0.34), C(x * 1.55, b.top + 1.2, 0) * R(0, 0, x * -5), darker(BONE, 0.25))
		rig:body("Pauldron", V(1.5, 0.8, 1.7), C(x * 1.8, 4.2, 0) * R(0, 0, x * -12), IRON, METAL)
		rig:body("PauldronSpike", V(0.4, 0.9, 0.4), C(x * 2.1, 4.9, 0) * R(0, 0, x * -25), BONE)
	end
	rig:on(b.head, "Helm", V(2, 0.7, 1.7), C(0, b.top + 0.1, 0), IRON, METAL)
	rig:on(b.head, "HelmCrest", V(0.3, 0.7, 1.6), C(0, b.top + 0.7, 0), rgb(200, 50, 40), FABRIC)
	-- flaming club
	rig:on(b.armR, "Club", V(0.4, 3, 0.4), C(b.armX, b.handY + 0.9, -0.7) * R(55, 0, 0), WOOD, WOODM)
	rig:on(b.armR, "ClubHead", V(1.2, 1.6, 1.2), C(b.armX, b.handY + 2.1, -2.35) * R(55, 0, 0), rgb(60, 42, 44), SLATE)
	local flame = rig:on(b.armR, "ClubFlame", V(0.8, 1, 0.8), C(b.armX, b.handY + 2.75, -3.2) * R(55, 45, 0), fire, NEON)
	local fireFx = Instance.new("Fire")
	fireFx.Color = fire
	fireFx.SecondaryColor = GOLD
	fireFx.Size = 3 * s
	fireFx.Heat = 6
	fireFx.Parent = flame
	for i = 0, 2 do
		rig:on(b.armR, "ClubSpike", V(0.26, 0.6, 0.26), C(b.armX + (i - 1) * 0.6, b.handY + 2.3 + i * 0.1, -2.5) * R(55, 0, (i - 1) * -70), BONE)
	end
	return rig:finish(b.top + 1.8, skin)
end

---------------------------------------------------------------------
-- 4. Бездна ауры
---------------------------------------------------------------------

builders.ShadowKnight = function(name, s, origin)
	local armor, trim, glow = rgb(38, 30, 60), rgb(110, 80, 170), rgb(255, 61, 184)
	local rig = Rig.new(name, s, origin, V(2.2, 2.1, 1.2), 3.05)
	local b = biped(rig, { Skin = armor, Shirt = armor, Pants = rgb(28, 22, 46), Chest = V(2.2, 2.1, 1.2), Head = V(1.4, 1.4, 1.4), Arm = 0.9, Leg = 0.95, Shoes = trim, Material = METAL })
	local hz = -b.headSize.Z / 2
	rig:body("Breastplate", V(1.9, 1.3, 0.16), C(0, 3.4, -0.64), trim, METAL)
	rig:body("Emblem", V(0.6, 0.6, 0.1), C(0, 3.45, -0.74) * R(0, 0, 45), glow, NEON)
	rig:body("Tasset", V(2.3, 0.6, 1.3), C(0, 2.1, 0), trim, METAL)
	rig:body("Cape", V(2.1, 3.3, 0.12), C(0, 2.6, 0.72) * R(-7, 0, 0), rgb(60, 30, 100), FABRIC)
	rig:on(b.head, "Visor", V(1, 0.18, 0.1), C(0, b.headY + 0.12, hz - 0.02), glow, NEON)
	rig:on(b.head, "VisorSlit", V(0.14, 0.6, 0.1), C(0, b.headY - 0.2, hz - 0.02), BLACK)
	rig:on(b.head, "HelmRim", V(1.5, 0.2, 1.5), C(0, b.headY - 0.6, 0), trim, METAL)
	rig:on(b.head, "Plume", V(0.3, 0.9, 1.3), C(0, b.top + 0.4, 0.2), glow, FABRIC)
	rig:on(b.head, "PlumeBase", V(0.5, 0.3, 0.5), C(0, b.top + 0.05, 0), trim, METAL)
	for _, x in ipairs({ -1, 1 }) do
		rig:body("Pauldron", V(1.2, 0.7, 1.4), C(x * 1.55, 4.75, 0) * R(0, 0, x * -14), trim, METAL)
		rig:body("PauldronSpike", V(0.3, 0.7, 0.3), C(x * 1.8, 5.3, 0) * R(0, 0, x * -25), armor, METAL)
		local leg = if x > 0 then b.legR else b.legL
		rig:on(leg, "Knee", V(0.8, 0.4, 0.3), C(x * 0.55, 1.2, -0.55), trim, METAL)
	end
	-- sword (right) and kite shield (left)
	rig:on(b.armR, "SwordHilt", V(0.22, 0.8, 0.22), C(b.armX, b.handY + 0.2, -0.45) * R(70, 0, 0), BLACK)
	rig:on(b.armR, "SwordGuard", V(1.1, 0.2, 0.3), C(b.armX, b.handY + 0.38, -0.9) * R(70, 0, 0), trim, METAL)
	rig:on(b.armR, "SwordBlade", V(0.45, 2.8, 0.12), C(b.armX, b.handY + 0.9, -2.35) * R(70, 0, 0), rgb(25, 18, 40), METAL)
	rig:on(b.armR, "SwordEdge", V(0.1, 2.8, 0.14), C(b.armX + 0.22, b.handY + 0.9, -2.35) * R(70, 0, 0), glow, NEON)
	rig:on(b.armL, "Shield", V(0.2, 2.2, 1.6), C(-b.armX - 0.55, b.handY + 0.9, -0.1), armor, METAL)
	rig:on(b.armL, "ShieldRim", V(0.22, 2.4, 0.2), C(-b.armX - 0.57, b.handY + 0.9, -0.1), trim, METAL)
	rig:on(b.armL, "ShieldEye", V(0.1, 0.5, 0.5), C(-b.armX - 0.68, b.handY + 1.1, -0.1), glow, NEON, 0, Enum.PartType.Cylinder)
	rig:body("AuraRing", V(0.14, 4.4, 4.4), C(0, 0.12, 0) * R(0, 0, 90), trim, GLASS, 0.6, Enum.PartType.Cylinder)
	return rig:finish(b.top + 1, trim)
end

-- Eye body shared by the flying eye and nothing else (kept for clarity).
builders.FlyingEye = function(name, s, origin)
	local iris = rgb(190, 110, 255)
	local rig = Rig.new(name, s, origin, V(3, 3, 3), 4.5)
	local ball = rig:body("Ball", V(3, 3, 3), C(0, 4.5, 0), rgb(245, 240, 250), nil, 0, BALL)
	rig:on(ball, "Iris", V(1.7, 1.7, 0.4), C(0, 4.5, -1.32), iris, nil, 0, BALL)
	rig:on(ball, "Pupil", V(0.5, 1.1, 0.2), C(0, 4.5, -1.52), BLACK)
	rig:on(ball, "Shine", V(0.4, 0.4, 0.12), C(0.4, 4.9, -1.5), WHITE)
	rig:on(ball, "LidTop", V(3.1, 0.9, 3.1), C(0, 5.5, 0.1) * R(-12, 0, 0), rgb(120, 70, 170))
	rig:on(ball, "LidBottom", V(3.1, 0.6, 3.1), C(0, 3.4, 0.1) * R(10, 0, 0), rgb(100, 55, 150))
	for i = 0, 3 do
		local angle = i * math.pi / 2 + 0.6
		rig:on(ball, "Vein", V(0.1, 0.9, 0.1), C(math.cos(angle) * 1.15, 4.5 + math.sin(angle) * 1.15, -0.9) * R(0, 0, math.deg(angle) + 90), rgb(220, 60, 90))
	end
	for _, x in ipairs({ -1, 1 }) do
		local wing = rig:limb("Wing", V(x * 1.4, 5, 0.3), "Wing" .. x, V(2.2, 0.2, 1.2), C(x * 2.5, 5.5, 0.4) * R(0, 0, x * 25), rgb(70, 40, 110))
		rig:on(wing, "WingMembrane", V(1.8, 0.1, 1.6), C(x * 3.3, 5.6, 0.6) * R(0, 0, x * 5), rgb(120, 70, 170), nil, 0.15)
		rig:on(wing, "WingClaw", V(0.2, 0.5, 0.2), C(x * 4.2, 5.9, 0.2), BLACK)
		rig:on(ball, "Horn", V(0.4, 0.9, 0.4), C(x * 0.9, 6.2, 0) * R(0, 0, x * -30), rgb(60, 35, 95))
	end
	for i = 0, 3 do
		local x = -0.9 + i * 0.6
		local tail = rig:limb("Tail", V(x, 3.2, 0.3), "Tentacle" .. i, V(0.3, 1.5, 0.3), C(x, 2.5, 0.4), rgb(120, 70, 170))
		rig:on(tail, "TentacleTip", V(0.2, 1, 0.2), C(x, 1.4, 0.55) * R(15, 0, 0), iris)
	end
	return rig:finish(6.8, iris, true)
end

builders.AuraGhost = function(name, s, origin)
	local robe, pale, glow = rgb(120, 90, 190), rgb(190, 170, 240), rgb(255, 255, 255)
	local rig = Rig.new(name, s, origin, V(2, 3, 1.2), 3.5)
	-- tapering robe, floats above the floor
	rig:body("Robe", V(2, 1.8, 1.2), C(0, 4.1, 0), robe, FABRIC)
	rig:body("RobeMid", V(1.6, 1.3, 1), C(0, 2.7, 0.1), darker(robe, 0.1), FABRIC, 0.1)
	rig:body("RobeLow", V(1.1, 1, 0.8), C(0, 1.7, 0.2), darker(robe, 0.2), FABRIC, 0.25)
	for i = 0, 3 do
		rig:body("Tatter", V(0.4, 0.9 + (i % 2) * 0.4, 0.14), C(-0.6 + i * 0.4, 1, 0.2 + (i % 2) * 0.2) * R(0, 0, (i - 1.5) * 8), darker(robe, 0.25), FABRIC, 0.35)
	end
	rig:body("Sash", V(2.05, 0.3, 1.25), C(0, 3.5, 0), pale, FABRIC)
	rig:body("Chain", V(0.14, 1.2, 0.14), C(0.5, 2.9, -0.6) * R(0, 0, 10), IRON, METAL)
	local head = rig:limb("Head", V(0, 5, 0), "Hood", V(1.7, 1.6, 1.7), C(0, 5.8, 0), robe, FABRIC)
	rig:on(head, "Void", V(1.2, 1.1, 0.14), C(0, 5.7, -0.82), BLACK)
	for _, x in ipairs({ -1, 1 }) do
		rig:on(head, "EyeGlow", V(0.3, 0.2, 0.1), C(x * 0.3, 5.8, -0.9) * R(0, 0, x * -15), glow, NEON)
		local role = if x > 0 then "ArmR" else "ArmL"
		local arm = rig:limb(role, V(x * 1.1, 4.7, 0), "Sleeve" .. x, V(0.7, 2, 0.8), C(x * 1.4, 3.8, -0.2) * R(-25, 0, x * 12), robe, FABRIC)
		rig:on(arm, "Hand", V(0.5, 0.4, 0.5), C(x * 1.6, 2.75, -0.75), pale)
		for c = -1, 1 do
			rig:on(arm, "Claw", V(0.1, 0.5, 0.1), C(x * 1.6 + c * 0.17, 2.4, -0.85) * R(20, 0, 0), pale)
		end
	end
	rig:on(head, "HoodPeak", V(0.9, 0.6, 1), C(0, 6.7, 0.3) * R(-25, 0, 0), darker(robe, 0.1), FABRIC)
	rig:on(head, "MouthGlow", V(0.4, 0.12, 0.1), C(0, 5.4, -0.9), glow, NEON)
	-- aura orbs circling the body
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		rig:body("Orb", V(0.5, 0.5, 0.5), C(math.cos(angle) * 1.9, 3.4 + i * 0.7, math.sin(angle) * 1.9), rgb(255, 61, 184), GLASS, 0.2, BALL)
	end
	return rig:finish(7.2, robe, true)
end

builders.AbyssLord = function(name, s, origin)
	local armor, trim, glow, gold = rgb(24, 16, 44), rgb(90, 50, 160), rgb(255, 61, 184), GOLD
	local rig = Rig.new(name, s, origin, V(2.6, 2.4, 1.4), 3.4)
	local b = biped(rig, { Skin = armor, Shirt = armor, Pants = rgb(18, 12, 34), Chest = V(2.6, 2.4, 1.4), Head = V(1.5, 1.5, 1.5), Arm = 1, ArmLen = 2.5, Leg = 1, LegH = 2.2, Shoes = trim, Material = METAL })
	local hz = -b.headSize.Z / 2
	rig:body("ChestCore", V(0.9, 0.9, 0.3), C(0, 3.7, -0.72) * R(0, 0, 45), glow, NEON)
	rig:body("ChestFrame", V(1.5, 1.5, 0.16), C(0, 3.7, -0.68) * R(0, 0, 45), gold, METAL)
	rig:body("Ribs", V(2.2, 0.2, 0.12), C(0, 2.9, -0.72), trim, METAL)
	rig:body("Tasset", V(2.7, 0.7, 1.5), C(0, 2.3, 0), trim, METAL)
	rig:body("Cape", V(2.8, 4, 0.14), C(0, 2.7, 0.85) * R(-8, 0, 0), rgb(50, 20, 90), FABRIC)
	rig:body("CapeTrim", V(2.8, 0.26, 0.16), C(0, 0.85, 1.12) * R(-8, 0, 0), glow, NEON)
	rig:body("Collar", V(2.2, 1, 0.3), C(0, 5, 0.75) * R(12, 0, 0), trim, METAL)
	-- three eyes, horned crown
	for i = -1, 1 do
		rig:on(b.head, "Eye", V(0.3, 0.22, 0.1), C(i * 0.4, b.headY + 0.1 + (if i == 0 then 0.32 else 0), hz - 0.02), glow, NEON)
	end
	rig:on(b.head, "Jaw", V(1.2, 0.4, 0.14), C(0, b.headY - 0.45, hz - 0.02), trim, METAL)
	rig:on(b.head, "CrownBand", V(1.6, 0.3, 1.6), C(0, b.top, 0), gold, METAL)
	rig:on(b.head, "CrownGem", V(0.34, 0.34, 0.2), C(0, b.top + 0.1, hz - 0.1) * R(0, 0, 45), glow, NEON)
	for _, x in ipairs({ -1, 1 }) do
		rig:on(b.head, "Horn", V(0.5, 1.3, 0.5), C(x * 0.95, b.top + 0.55, 0) * R(0, 0, x * -30), trim, METAL)
		rig:on(b.head, "HornTip", V(0.32, 0.9, 0.32), C(x * 1.4, b.top + 1.45, 0) * R(0, 0, x * 5), gold, METAL)
		rig:body("Pauldron", V(1.6, 0.9, 1.8), C(x * 1.9, 5.3, 0) * R(0, 0, x * -14), trim, METAL)
		rig:body("PauldronSpike", V(0.4, 1.1, 0.4), C(x * 2.3, 6.1, 0) * R(0, 0, x * -28), gold, METAL)
		rig:body("PauldronEye", V(0.1, 0.5, 0.5), C(x * 2.72, 5.3, 0), glow, NEON, 0, Enum.PartType.Cylinder)
		local arm = if x > 0 then b.armR else b.armL
		rig:on(arm, "Gauntlet", V(1.2, 0.9, 1.2), C(x * b.armX, b.handY + 0.5, 0), trim, METAL)
		-- floating shards of the abyss
		rig:body("Shard", V(0.5, 1.3, 0.5), C(x * 3.3, 4.2, 0.8) * R(20, 30, x * 15), rgb(110, 60, 190), GLASS, 0.2)
		rig:body("Shard", V(0.4, 1, 0.4), C(x * 2.9, 6.9, -0.4) * R(-15, 60, x * -20), rgb(110, 60, 190), GLASS, 0.2)
	end
	-- scythe-staff in the right hand
	rig:on(b.armR, "Staff", V(0.3, 6, 0.3), C(b.armX, b.handY + 1.6, -0.6), rgb(50, 38, 80), METAL)
	rig:on(b.armR, "StaffBlade", V(2.2, 0.6, 0.16), C(b.armX - 1, b.handY + 4.5, -0.6) * R(0, 0, 18), armor, METAL)
	rig:on(b.armR, "StaffEdge", V(2.2, 0.12, 0.18), C(b.armX - 1.08, b.handY + 4.22, -0.6) * R(0, 0, 18), glow, NEON)
	rig:on(b.armR, "StaffOrb", V(0.8, 0.8, 0.8), C(b.armX, b.handY + 4.9, -0.6), glow, NEON, 0, BALL)
	return rig:finish(b.top + 2, trim)
end

---------------------------------------------------------------------

-- def: Config.Mobs.Defs entry. cframe: ground level, -Z = facing.
-- Returns the Model (PrimaryPart = HumanoidRootPart).
function MobBuilder.Build(def, scale: number, cframe: CFrame): Model
	local build = builders[def.Id] or builders.ZombieMiner
	local model = build(def.Name, scale * (def.Scale or 1), cframe)
	model:SetAttribute("Kind", def.Id)
	if def.Boss then
		-- every boss has an aura of particles
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(model:GetAttribute("Color"), WHITE)
		emitter.LightEmission = 0.5
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(1, 2)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.Rate = 12
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = model.PrimaryPart
		local light = Instance.new("PointLight")
		light.Color = model:GetAttribute("Color")
		light.Range = 26
		light.Brightness = 1.2
		light.Parent = model.PrimaryPart
	end
	return model
end

return MobBuilder
