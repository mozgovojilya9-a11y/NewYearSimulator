--[[
	WeaponBuilder.luau
	Builds a weapon Model out of Parts for a Config.Weapons entry
	(weapon.Shape picks the builder). Used for the character's hand and
	forge racks (server) and ViewportFrames (client), so it lives in
	Shared and depends on nothing else.

	Convention: PrimaryPart = "Handle"; its +Y axis points along the
	blade and the grip point is the handle's center. All parts are
	unanchored, massless and welded to the Handle, so the model can be
	anchored (racks, previews) or welded to a hand (characters).

	Every craftable weapon has its own silhouette in its biome's theme
	(10-20 parts). Legendary and above glow: a PointLight and a particle
	emitter. Every weapon carries a disabled Trail along the blade that
	the client switches on during a swing (Swing.luau).
]]

local WeaponBuilder = {}

local WOOD = Color3.fromRGB(120, 80, 45)
local DARK = Color3.fromRGB(60, 40, 30)
local GOLD = Color3.fromRGB(255, 201, 60)
local STEEL = Color3.fromRGB(190, 195, 210)
local IRON = Color3.fromRGB(80, 80, 95)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(20, 15, 30)
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass
local WOODM = Enum.Material.Wood
local SLATE = Enum.Material.Slate
local ICE = Enum.Material.Ice

local GLOW_FROM = { Legendary = true, Mythic = true, Secret = true }

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

local function rot(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

local function lighter(c, a)
	return c:Lerp(WHITE, a)
end

local function darker(c, a)
	return c:Lerp(Color3.new(0, 0, 0), a)
end

-- Grip shared by most weapons: handle, wrap rings, pommel.
local function grip(m, length, color, pommel)
	local handle = part(m, "Handle", Vector3.new(0.34, length, 0.34), at(0, length / 2, 0), color or DARK, Enum.Material.Fabric)
	for i = 1, 3 do
		part(m, "Wrap", Vector3.new(0.4, 0.1, 0.4), at(0, length * i / 4, 0), darker(color or DARK, 0.35))
	end
	part(m, "Pommel", Vector3.new(0.52, 0.3, 0.52), at(0, -0.1, 0), pommel or GOLD, METAL)
	return handle
end

-- Straight blade made of segments that narrow to the tip.
local function blade(m, y0, length, width, color, material, transparency)
	part(m, "Blade", Vector3.new(width, length * 0.72, 0.16), at(0, y0 + length * 0.36, 0), color, material, transparency)
	part(m, "BladeTaper", Vector3.new(width * 0.7, length * 0.18, 0.15), at(0, y0 + length * 0.81, 0), color, material, transparency)
	part(m, "Tip", Vector3.new(width * 0.4, length * 0.1, 0.14), at(0, y0 + length * 0.95, 0), color, material, transparency)
	return y0 + length
end

local builders = {}

---------------------------------------------------------------------
-- Starter + legacy
---------------------------------------------------------------------

builders.Stick = function(m)
	local handle = part(m, "Handle", Vector3.new(0.4, 1.2, 0.4), at(0, 0.6, 0), WOOD, WOODM)
	part(m, "Blade", Vector3.new(0.35, 2.4, 0.35), at(0, 2.3, 0) * rot(0, 0, 6), WOOD, WOODM)
	part(m, "Knot", Vector3.new(0.5, 0.4, 0.5), at(0.1, 1.9, 0), DARK, WOODM)
	part(m, "Twig", Vector3.new(0.15, 0.7, 0.15), at(0.35, 2.9, 0) * rot(0, 0, -40), WOOD, WOODM)
	part(m, "Leaf", Vector3.new(0.4, 0.08, 0.25), at(0.65, 3.2, 0) * rot(0, 0, -20), Color3.fromRGB(90, 190, 80))
	return handle
end

local function plainSword(m, w, bladeLen, bladeW, neon, guardColor)
	local handle = grip(m, 1.2, DARK, guardColor or GOLD)
	part(m, "Guard", Vector3.new(1.6, 0.25, 0.45), at(0, 1.3, 0), guardColor or GOLD, METAL)
	blade(m, 1.42, bladeLen, bladeW, w.Color, if neon then NEON else METAL)
	return handle
end

builders.WoodSword = function(m, w)
	return plainSword(m, w, 2.6, 0.6, false, WOOD)
end
builders.IronSword = function(m, w)
	return plainSword(m, w, 3.2, 0.65, false)
end
builders.AuraKatana = function(m, w)
	local handle = grip(m, 1.5, DARK)
	part(m, "Guard", Vector3.new(0.9, 0.15, 0.9), at(0, 1.55, 0), GOLD, METAL)
	part(m, "Blade", Vector3.new(0.45, 2.2, 0.12), at(0, 2.7, 0) * rot(0, 0, 4), w.Color, NEON)
	part(m, "Blade2", Vector3.new(0.4, 1.8, 0.12), at(-0.2, 4.6, 0) * rot(0, 0, 12), w.Color, NEON)
	return handle
end
builders.StormBlade = function(m, w)
	local handle = plainSword(m, w, 3.6, 1.0, true, Color3.fromRGB(40, 80, 140))
	part(m, "Core", Vector3.new(0.25, 3, 0.2), at(0, 3.3, 0), WHITE, NEON)
	return handle
end
builders.EclipseScythe = function(m, w)
	local handle = part(m, "Handle", Vector3.new(0.35, 5, 0.35), at(0, 2.5, 0), DARK)
	part(m, "Head", Vector3.new(2.6, 0.5, 0.2), at(1.1, 5.1, 0), w.Color, NEON)
	part(m, "Edge", Vector3.new(2.2, 0.4, 0.15), at(2.3, 4.4, 0) * rot(0, 0, -50), w.Color, NEON)
	part(m, "Edge2", Vector3.new(1.4, 0.3, 0.15), at(2.9, 3.4, 0) * rot(0, 0, -80), w.Color, NEON)
	part(m, "Ring", Vector3.new(0.9, 0.9, 0.3), at(0, 5.1, 0), GOLD)
	return handle
end
builders.StarAuraSword = function(m, w)
	local handle = plainSword(m, w, 4.2, 1.1, true, GOLD)
	part(m, "Core", Vector3.new(0.3, 3.6, 0.2), at(0, 3.6, 0), WHITE, NEON)
	for i = 1, 3 do
		part(m, "Star" .. i, Vector3.new(0.6, 0.6, 0.25), at(0, 2 + i * 1.1, 0) * rot(0, 0, 45), GOLD, NEON)
	end
	return handle
end

---------------------------------------------------------------------
-- 1. Катакомбы: bone, slime, rust, skulls
---------------------------------------------------------------------

builders.BoneSword = function(m, w)
	local bone = w.Color
	local handle = grip(m, 1.2, Color3.fromRGB(90, 70, 55), bone)
	-- guard: a small bone across
	part(m, "Guard", Vector3.new(1.5, 0.28, 0.3), at(0, 1.32, 0), bone)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "GuardKnob", Vector3.new(0.42, 0.42, 0.42), at(x * 0.8, 1.32, 0), lighter(bone, 0.3)).Shape = Enum.PartType.Ball
	end
	-- blade: a long sharpened bone with notches
	part(m, "Blade", Vector3.new(0.55, 2.2, 0.22), at(0, 2.55, 0), bone)
	part(m, "BladeTaper", Vector3.new(0.42, 0.7, 0.2), at(0.03, 3.95, 0) * rot(0, 0, -3), bone)
	part(m, "Tip", Vector3.new(0.26, 0.5, 0.18), at(0.08, 4.5, 0) * rot(0, 0, -8), lighter(bone, 0.25))
	for i = 0, 2 do
		part(m, "Notch", Vector3.new(0.2, 0.14, 0.24), at(-0.26, 2 + i * 0.6, 0), darker(bone, 0.3))
		part(m, "Tooth", Vector3.new(0.22, 0.3, 0.14), at(0.34, 2.2 + i * 0.6, 0) * rot(0, 0, -30), lighter(bone, 0.3))
	end
	part(m, "Crack", Vector3.new(0.06, 0.9, 0.24), at(0.05, 3, 0) * rot(0, 0, 12), darker(bone, 0.45))
	return handle
end

builders.SlimeDagger = function(m, w)
	local c = w.Color
	local handle = grip(m, 1, Color3.fromRGB(70, 90, 60), Color3.fromRGB(60, 150, 70))
	part(m, "Guard", Vector3.new(1.1, 0.24, 0.5), at(0, 1.1, 0), Color3.fromRGB(60, 150, 70))
	-- wavy translucent blade with a bright core
	part(m, "Blade", Vector3.new(0.6, 1, 0.2), at(0.06, 1.75, 0) * rot(0, 0, -6), c, GLASS, 0.25)
	part(m, "Blade2", Vector3.new(0.52, 0.9, 0.2), at(-0.06, 2.6, 0) * rot(0, 0, 8), c, GLASS, 0.25)
	part(m, "Tip", Vector3.new(0.34, 0.7, 0.18), at(0.04, 3.3, 0) * rot(0, 0, -5), c, GLASS, 0.25)
	part(m, "Core", Vector3.new(0.14, 1.9, 0.22), at(0, 2.3, 0), lighter(c, 0.5), NEON)
	for i = 1, 4 do
		local drip = part(m, "Drip", Vector3.new(0.26, 0.26, 0.26), at(if i % 2 == 0 then 0.36 else -0.36, 1.4 + i * 0.42, 0), c, GLASS, 0.2)
		drip.Shape = Enum.PartType.Ball
	end
	local blob = part(m, "Blob", Vector3.new(0.5, 0.5, 0.5), at(0, 1.1, -0.3), c, GLASS, 0.2)
	blob.Shape = Enum.PartType.Ball
	part(m, "Eye", Vector3.new(0.14, 0.2, 0.06), at(0, 1.14, -0.56), BLACK)
	return handle
end

builders.Cleaver = function(m, w)
	local rust = w.Color
	local handle = grip(m, 1.3, WOOD, IRON)
	part(m, "Collar", Vector3.new(0.5, 0.3, 0.5), at(0, 1.4, 0), IRON, METAL)
	-- wide chipped blade, offset to one side
	part(m, "Blade", Vector3.new(1.5, 2.3, 0.18), at(0.45, 2.7, 0), STEEL, Enum.Material.CorrodedMetal)
	part(m, "Spine", Vector3.new(0.3, 2.5, 0.24), at(-0.25, 2.75, 0), IRON, METAL)
	part(m, "Edge", Vector3.new(0.14, 2.3, 0.1), at(1.24, 2.7, 0), lighter(STEEL, 0.4), METAL)
	part(m, "Top", Vector3.new(1.3, 0.3, 0.18), at(0.35, 3.95, 0) * rot(0, 0, 10), STEEL, Enum.Material.CorrodedMetal)
	for i = 0, 2 do
		part(m, "Rust", Vector3.new(0.5 + i * 0.1, 0.4, 0.2), at(0.2 + i * 0.3, 1.9 + i * 0.7, 0) * rot(0, 0, i * 25), rust, Enum.Material.CorrodedMetal)
		part(m, "Chip", Vector3.new(0.22, 0.26, 0.22), at(1.26, 2 + i * 0.7, 0) * rot(0, 0, 45), IRON)
	end
	local hole = part(m, "Hole", Vector3.new(0.2, 0.36, 0.36), at(0.9, 3.6, 0) * rot(0, 90, 0), BLACK)
	hole.Shape = Enum.PartType.Cylinder
	return handle
end

builders.SkullMace = function(m, w)
	local c = w.Color
	local bone = Color3.fromRGB(225, 220, 235)
	local handle = grip(m, 1.4, Color3.fromRGB(70, 50, 80), c)
	part(m, "Shaft", Vector3.new(0.3, 1.6, 0.3), at(0, 2.2, 0), IRON, METAL)
	part(m, "Collar", Vector3.new(0.7, 0.3, 0.7), at(0, 3, 0), GOLD, METAL)
	-- the head is a skull
	part(m, "Skull", Vector3.new(1.5, 1.3, 1.4), at(0, 3.9, 0), bone)
	part(m, "Jaw", Vector3.new(1, 0.4, 1), at(0, 3.15, -0.1), darker(bone, 0.1))
	for _, x in ipairs({ -1, 1 }) do
		part(m, "Socket", Vector3.new(0.4, 0.4, 0.1), at(x * 0.36, 3.95, -0.7), BLACK)
		part(m, "EyeGlow", Vector3.new(0.2, 0.2, 0.08), at(x * 0.36, 3.95, -0.74), c, NEON)
		part(m, "Spike", Vector3.new(0.3, 0.8, 0.3), at(x * 0.95, 4.1, 0) * rot(0, 0, x * -75), IRON, METAL)
	end
	part(m, "SpikeTop", Vector3.new(0.3, 0.8, 0.3), at(0, 4.9, 0), IRON, METAL)
	part(m, "SpikeBack", Vector3.new(0.3, 0.3, 0.8), at(0, 4, 0.95), IRON, METAL)
	for i = -1, 1 do
		part(m, "Tooth", Vector3.new(0.2, 0.24, 0.08), at(i * 0.28, 3.38, -0.62), WHITE)
	end
	part(m, "Rune", Vector3.new(0.3, 0.4, 0.08), at(0, 4.35, -0.71) * rot(0, 0, 45), c, NEON)
	return handle
end

---------------------------------------------------------------------
-- 2. Ледяной грот: ice, fur, crystals
---------------------------------------------------------------------

builders.IceBlade = function(m, w)
	local c = w.Color
	local handle = grip(m, 1.2, Color3.fromRGB(60, 90, 130), lighter(c, 0.5))
	part(m, "Guard", Vector3.new(1.5, 0.3, 0.45), at(0, 1.3, 0), lighter(c, 0.5), ICE)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "GuardIcicle", Vector3.new(0.22, 0.6, 0.22), at(x * 0.7, 1, 0), lighter(c, 0.6), ICE)
	end
	blade(m, 1.45, 3, 0.7, c, GLASS, 0.2)
	part(m, "Core", Vector3.new(0.16, 2.4, 0.2), at(0, 2.75, 0), WHITE, ICE)
	for i = 0, 2 do
		part(m, "Shard", Vector3.new(0.24, 0.6, 0.14), at(if i % 2 == 0 then 0.42 else -0.42, 2 + i * 0.75, 0) * rot(0, 0, if i % 2 == 0 then -35 else 35), lighter(c, 0.3), GLASS, 0.15)
	end
	part(m, "Frost", Vector3.new(0.8, 0.12, 0.22), at(0, 1.6, 0), WHITE, ICE)
	return handle
end

builders.YetiClub = function(m, w)
	local fur = w.Color
	local handle = grip(m, 1.4, Color3.fromRGB(110, 80, 60), Color3.fromRGB(170, 215, 245))
	part(m, "Shaft", Vector3.new(0.5, 1.4, 0.5), at(0, 2, 0), Color3.fromRGB(125, 90, 60), WOODM)
	-- heavy head wrapped in fur with ice spikes
	part(m, "Head", Vector3.new(1.3, 2, 1.3), at(0, 3.6, 0), Color3.fromRGB(140, 100, 65), WOODM)
	part(m, "FurBand", Vector3.new(1.5, 0.5, 1.5), at(0, 2.8, 0), fur, Enum.Material.Fabric)
	part(m, "FurBand2", Vector3.new(1.5, 0.4, 1.5), at(0, 4.5, 0), fur, Enum.Material.Fabric)
	for i = 0, 3 do
		local angle = i * 90
		part(m, "IceSpike", Vector3.new(0.34, 0.9, 0.34), at(0, 3.3 + (i % 2) * 0.6, 0) * rot(0, angle, 0) * at(0, 0, -0.95) * rot(-90, 0, 0), Color3.fromRGB(170, 225, 255), GLASS, 0.15)
	end
	for i = 0, 3 do
		part(m, "Tuft", Vector3.new(0.3, 0.5, 0.3), at(0, 2.5, 0) * rot(0, i * 90 + 45, 0) * at(0, 0, -0.7) * rot(25, 0, 0), lighter(fur, 0.3), Enum.Material.Fabric)
	end
	part(m, "Cap", Vector3.new(0.9, 0.5, 0.9), at(0, 4.85, 0), Color3.fromRGB(170, 225, 255), ICE)
	return handle
end

builders.FrostSpear = function(m, w)
	local c = w.Color
	local handle = part(m, "Handle", Vector3.new(0.3, 1.4, 0.3), at(0, 0.7, 0), Color3.fromRGB(70, 100, 140), Enum.Material.Fabric)
	part(m, "Shaft", Vector3.new(0.24, 3.4, 0.24), at(0, 3.1, 0), Color3.fromRGB(215, 235, 250), ICE)
	part(m, "Butt", Vector3.new(0.4, 0.5, 0.4), at(0, -0.2, 0) * rot(0, 45, 0), c, GLASS, 0.1)
	for i = 1, 3 do
		part(m, "Ring", Vector3.new(0.4, 0.14, 0.4), at(0, 1.3 + i * 1, 0), lighter(c, 0.3), METAL)
	end
	-- crystal spearhead with side prongs
	part(m, "Socket", Vector3.new(0.5, 0.4, 0.5), at(0, 4.9, 0), STEEL, METAL)
	part(m, "Blade", Vector3.new(0.6, 1.4, 0.3), at(0, 5.8, 0) * rot(0, 45, 0), c, GLASS, 0.15)
	part(m, "Tip", Vector3.new(0.34, 0.8, 0.2), at(0, 6.8, 0) * rot(0, 45, 0), lighter(c, 0.4), GLASS, 0.1)
	part(m, "Core", Vector3.new(0.14, 1.6, 0.14), at(0, 5.9, 0), WHITE, NEON)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "Prong", Vector3.new(0.22, 0.9, 0.18), at(x * 0.42, 5.4, 0) * rot(0, 0, x * -28), c, GLASS, 0.15)
		part(m, "Snow", Vector3.new(0.2, 0.2, 0.2), at(x * 0.3, 4.6, 0), WHITE, ICE)
	end
	return handle
end

builders.EternalBlade = function(m, w)
	local c = w.Color
	local handle = grip(m, 1.4, Color3.fromRGB(40, 70, 120), GOLD)
	-- winged guard
	part(m, "Guard", Vector3.new(1.2, 0.34, 0.5), at(0, 1.52, 0), GOLD, METAL)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "Wing", Vector3.new(0.9, 0.26, 0.3), at(x * 0.95, 1.75, 0) * rot(0, 0, x * 28), lighter(c, 0.4), ICE)
		part(m, "WingTip", Vector3.new(0.5, 0.2, 0.24), at(x * 1.5, 2.15, 0) * rot(0, 0, x * 50), WHITE, ICE)
	end
	local gem = part(m, "Gem", Vector3.new(0.44, 0.44, 0.3), at(0, 1.52, -0.14) * rot(0, 0, 45), WHITE, NEON)
	-- broad blade with a glowing fuller and floating shards
	blade(m, 1.7, 3.8, 0.95, c, GLASS, 0.12)
	part(m, "Fuller", Vector3.new(0.22, 3, 0.2), at(0, 3.3, 0), WHITE, NEON)
	for i = 0, 3 do
		part(m, "Rune", Vector3.new(0.3, 0.12, 0.22), at(0, 2.3 + i * 0.7, 0), Color3.fromRGB(46, 160, 255), NEON)
	end
	for i = 0, 2 do
		part(m, "Shard", Vector3.new(0.2, 0.6, 0.12), at(if i % 2 == 0 then 0.85 else -0.85, 2.6 + i * 1, 0) * rot(0, 0, if i % 2 == 0 then -20 else 20), lighter(c, 0.4), GLASS, 0.1)
	end
	return handle, gem
end

---------------------------------------------------------------------
-- 3. Лавовая кузня: obsidian, embers, magma
---------------------------------------------------------------------

builders.ObsidianAxe = function(m, w)
	local c = w.Color
	local glow = Color3.fromRGB(255, 120, 40)
	local handle = grip(m, 1.6, Color3.fromRGB(70, 45, 35), IRON)
	part(m, "Shaft", Vector3.new(0.32, 2.6, 0.32), at(0, 2.9, 0), Color3.fromRGB(85, 55, 40), WOODM)
	part(m, "Binding", Vector3.new(0.5, 0.7, 0.5), at(0, 3.8, 0), IRON, METAL)
	-- jagged double-stepped obsidian head
	part(m, "Head", Vector3.new(1.3, 1.5, 0.3), at(0.8, 3.8, 0), c, GLASS, 0.05)
	part(m, "HeadWide", Vector3.new(0.6, 2.2, 0.26), at(1.6, 3.8, 0), c, GLASS, 0.05)
	part(m, "Edge", Vector3.new(0.16, 2.5, 0.14), at(1.96, 3.8, 0), lighter(c, 0.5), GLASS)
	part(m, "Beard", Vector3.new(0.5, 0.7, 0.24), at(1.5, 2.6, 0) * rot(0, 0, 20), c, GLASS, 0.05)
	part(m, "BackSpike", Vector3.new(0.9, 0.4, 0.26), at(-0.6, 3.8, 0) * rot(0, 0, 8), c, GLASS, 0.05)
	part(m, "TopSpike", Vector3.new(0.3, 0.8, 0.26), at(0, 4.6, 0), c, GLASS, 0.05)
	for i = 0, 2 do
		part(m, "Vein", Vector3.new(0.7, 0.08, 0.32), at(0.9 + i * 0.25, 3.3 + i * 0.5, 0) * rot(0, 0, 25 - i * 20), glow, NEON)
	end
	return handle
end

builders.EmberSword = function(m, w)
	local c = w.Color
	local coal = Color3.fromRGB(45, 38, 42)
	local handle = grip(m, 1.3, Color3.fromRGB(80, 40, 30), IRON)
	part(m, "Guard", Vector3.new(1.7, 0.3, 0.5), at(0, 1.42, 0), coal, SLATE)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "GuardHorn", Vector3.new(0.3, 0.6, 0.3), at(x * 0.85, 1.75, 0) * rot(0, 0, x * -20), coal, SLATE)
	end
	-- charred blade split by glowing cracks
	blade(m, 1.6, 3.4, 0.8, coal, SLATE)
	part(m, "Heat", Vector3.new(0.2, 2.8, 0.2), at(0, 3.1, 0), c, NEON)
	for i = 0, 3 do
		part(m, "Crack", Vector3.new(0.5, 0.08, 0.2), at(if i % 2 == 0 then 0.18 else -0.18, 2.1 + i * 0.65, 0) * rot(0, 0, if i % 2 == 0 then 30 else -30), Color3.fromRGB(255, 200, 80), NEON)
	end
	for i = 0, 2 do
		part(m, "Ember", Vector3.new(0.16, 0.16, 0.16), at(if i % 2 == 0 then 0.55 else -0.55, 2.6 + i * 0.9, 0) * rot(20, 30, 40), c, NEON)
	end
	return handle
end

builders.MagmaHammer = function(m, w)
	local c = w.Color
	local rock = Color3.fromRGB(60, 42, 44)
	local handle = grip(m, 1.6, Color3.fromRGB(70, 45, 35), IRON)
	part(m, "Shaft", Vector3.new(0.36, 2.2, 0.36), at(0, 2.7, 0), IRON, METAL)
	part(m, "Collar", Vector3.new(0.7, 0.3, 0.7), at(0, 3.75, 0), GOLD, METAL)
	-- huge two-faced head of volcanic rock with a molten core
	part(m, "Head", Vector3.new(2.6, 1.6, 1.5), at(0, 4.6, 0), rock, SLATE)
	local core = part(m, "Core", Vector3.new(2.7, 0.5, 0.6), at(0, 4.6, 0), c, NEON)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "Face", Vector3.new(0.3, 1.8, 1.7), at(x * 1.4, 4.6, 0), IRON, METAL)
		part(m, "FaceGlow", Vector3.new(0.1, 1, 1), at(x * 1.58, 4.6, 0), Color3.fromRGB(255, 200, 80), NEON)
		part(m, "Crack", Vector3.new(0.9, 0.1, 1.54), at(x * 0.6, 5.1, 0) * rot(0, 0, x * 20), c, NEON)
		part(m, "Crack", Vector3.new(0.7, 0.1, 1.54), at(x * 0.6, 4.1, 0) * rot(0, 0, x * -25), c, NEON)
	end
	part(m, "TopSpike", Vector3.new(0.5, 0.7, 0.5), at(0, 5.7, 0) * rot(0, 45, 0), rock, SLATE)
	part(m, "Drip", Vector3.new(0.2, 0.5, 0.2), at(0.5, 3.6, 0.5), c, NEON)
	return handle, core
end

builders.PhoenixBlade = function(m, w)
	local c = w.Color
	local red = Color3.fromRGB(255, 70, 40)
	local handle = grip(m, 1.4, Color3.fromRGB(110, 30, 25), GOLD)
	-- guard: phoenix wings
	part(m, "Guard", Vector3.new(0.9, 0.36, 0.5), at(0, 1.54, 0), GOLD, METAL)
	for _, x in ipairs({ -1, 1 }) do
		for i = 0, 2 do
			part(m, "Feather", Vector3.new(0.8 - i * 0.12, 0.2, 0.2), at(x * (0.7 + i * 0.28), 1.7 + i * 0.3, 0) * rot(0, 0, x * (25 + i * 14)), c:Lerp(red, i / 3), NEON)
		end
	end
	local head = part(m, "BirdHead", Vector3.new(0.4, 0.4, 0.5), at(0, 1.58, -0.36), GOLD, METAL)
	part(m, "Beak", Vector3.new(0.16, 0.16, 0.3), at(0, 1.52, -0.7), Color3.fromRGB(255, 240, 180))
	-- flame-shaped blade
	part(m, "Blade", Vector3.new(0.85, 1.4, 0.16), at(0.05, 2.5, 0) * rot(0, 0, -4), c, NEON)
	part(m, "Blade2", Vector3.new(0.75, 1.3, 0.16), at(-0.06, 3.7, 0) * rot(0, 0, 6), c:Lerp(red, 0.3), NEON)
	part(m, "Blade3", Vector3.new(0.55, 1, 0.15), at(0.05, 4.75, 0) * rot(0, 0, -6), c:Lerp(red, 0.6), NEON)
	part(m, "Tip", Vector3.new(0.3, 0.7, 0.14), at(-0.02, 5.5, 0) * rot(0, 0, 4), red, NEON)
	part(m, "Core", Vector3.new(0.2, 3.2, 0.18), at(0, 3.5, 0), Color3.fromRGB(255, 245, 200), NEON)
	for i = 0, 2 do
		part(m, "Flame", Vector3.new(0.24, 0.5, 0.12), at(if i % 2 == 0 then 0.55 else -0.55, 2.8 + i * 1, 0) * rot(0, 0, if i % 2 == 0 then -30 else 30), red, NEON)
	end
	return handle, head
end

---------------------------------------------------------------------
-- 4. Бездна ауры: shadow, essence, eyes
---------------------------------------------------------------------

builders.ShadowKatana = function(m, w)
	local c = w.Color
	local dark = Color3.fromRGB(30, 22, 48)
	local handle = grip(m, 1.6, dark, c)
	for i = 0, 3 do
		part(m, "Diamond", Vector3.new(0.2, 0.2, 0.36), at(0, 0.3 + i * 0.36, 0) * rot(0, 0, 45), c)
	end
	part(m, "Guard", Vector3.new(0.9, 0.16, 0.9), at(0, 1.7, 0) * rot(0, 45, 0), IRON, METAL)
	-- long curved blade: 4 segments bending back
	local y, x, tilt = 1.8, 0, 0
	for i = 1, 4 do
		local length = 1.2 - i * 0.08
		tilt += 5
		part(m, if i == 1 then "Blade" else "Blade" .. i, Vector3.new(0.42 - i * 0.04, length + 0.1, 0.12), at(x - math.sin(math.rad(tilt)) * length / 2, y + length / 2, 0) * rot(0, 0, tilt), dark, METAL)
		part(m, "Edge" .. i, Vector3.new(0.08, length + 0.1, 0.14), at(x - math.sin(math.rad(tilt)) * length / 2 + 0.2, y + length / 2, 0) * rot(0, 0, tilt), c, NEON)
		x -= math.sin(math.rad(tilt)) * length
		y += math.cos(math.rad(tilt)) * length
	end
	part(m, "Tip", Vector3.new(0.2, 0.4, 0.1), at(x - 0.05, y + 0.15, 0) * rot(0, 0, tilt + 10), c, NEON)
	part(m, "Tassel", Vector3.new(0.12, 0.7, 0.12), at(0.2, -0.5, 0) * rot(0, 0, 15), c, Enum.Material.Fabric)
	return handle
end

builders.DuskScythe = function(m, w)
	local c = w.Color
	local dark = Color3.fromRGB(35, 25, 60)
	local handle = part(m, "Handle", Vector3.new(0.34, 1.6, 0.34), at(0, 0.8, 0), dark, Enum.Material.Fabric)
	part(m, "Shaft", Vector3.new(0.28, 4, 0.28), at(0, 3.6, 0), Color3.fromRGB(50, 38, 80), METAL)
	part(m, "Butt", Vector3.new(0.4, 0.6, 0.4), at(0, -0.25, 0) * rot(0, 45, 0), c, GLASS, 0.1)
	for i = 1, 3 do
		part(m, "Ring", Vector3.new(0.42, 0.12, 0.42), at(0, 1.4 + i * 1.2, 0), GOLD, METAL)
	end
	part(m, "Socket", Vector3.new(0.7, 0.7, 0.4), at(0, 5.6, 0), dark, METAL)
	local eye = part(m, "Eye", Vector3.new(0.36, 0.36, 0.2), at(0, 5.6, -0.2), c, NEON)
	eye.Shape = Enum.PartType.Ball
	-- crescent blade: 4 segments curving down
	local px, py, angle = 0.3, 5.75, -8
	for i = 1, 4 do
		local length = 1.1 - i * 0.1
		angle -= 22
		local dx, dy = math.cos(math.rad(angle)) * length, math.sin(math.rad(angle)) * length
		part(m, if i == 1 then "Blade" else "Blade" .. i, Vector3.new(length + 0.1, 0.6 - i * 0.09, 0.14), at(px + dx / 2, py + dy / 2, 0) * rot(0, 0, angle), dark, METAL)
		part(m, "Edge" .. i, Vector3.new(length + 0.1, 0.1, 0.16), at(px + dx / 2 + math.sin(math.rad(angle)) * 0.25, py + dy / 2 - math.cos(math.rad(angle)) * 0.25, 0) * rot(0, 0, angle), c, NEON)
		px += dx
		py += dy
	end
	part(m, "BackSpike", Vector3.new(0.7, 0.26, 0.14), at(-0.6, 5.7, 0) * rot(0, 0, -15), dark, METAL)
	return handle, eye
end

builders.AbyssBlade = function(m, w)
	local c = w.Color
	local dark = Color3.fromRGB(28, 16, 52)
	local purple = Color3.fromRGB(150, 80, 255)
	local handle = grip(m, 1.4, dark, GOLD)
	-- guard: claws around an eye
	part(m, "Guard", Vector3.new(1.3, 0.4, 0.6), at(0, 1.55, 0), dark, METAL)
	local eye = part(m, "Eye", Vector3.new(0.5, 0.5, 0.3), at(0, 1.55, -0.26), WHITE)
	eye.Shape = Enum.PartType.Ball
	part(m, "Iris", Vector3.new(0.24, 0.3, 0.1), at(0, 1.55, -0.42), c, NEON)
	for _, x in ipairs({ -1, 1 }) do
		part(m, "Claw", Vector3.new(0.3, 0.9, 0.3), at(x * 0.85, 1.95, 0) * rot(0, 0, x * -30), purple, METAL)
		part(m, "ClawTip", Vector3.new(0.2, 0.5, 0.2), at(x * 0.95, 2.6, 0) * rot(0, 0, x * 10), GOLD, METAL)
	end
	-- black blade with a magenta rift down the middle
	for _, x in ipairs({ -1, 1 }) do
		part(m, "BladeHalf", Vector3.new(0.4, 3.2, 0.18), at(x * 0.3, 3.4, 0), dark, GLASS, 0.05)
		part(m, "Taper", Vector3.new(0.3, 0.9, 0.16), at(x * 0.2, 5.4, 0) * rot(0, 0, x * 10), dark, GLASS, 0.05)
		part(m, "Barb", Vector3.new(0.4, 0.2, 0.14), at(x * 0.62, 2.6, 0) * rot(0, 0, x * 35), purple, METAL)
		part(m, "Barb", Vector3.new(0.34, 0.18, 0.14), at(x * 0.6, 3.8, 0) * rot(0, 0, x * 35), purple, METAL)
	end
	local rift = part(m, "Blade", Vector3.new(0.2, 3.9, 0.2), at(0, 3.7, 0), c, NEON)
	part(m, "Tip", Vector3.new(0.16, 0.6, 0.14), at(0, 6, 0), c, NEON)
	return handle, rift
end

builders.AuraReaver = function(m, w)
	local c = w.Color
	local magenta = Color3.fromRGB(255, 61, 184)
	local cyan = Color3.fromRGB(46, 230, 255)
	local handle = grip(m, 1.5, Color3.fromRGB(60, 35, 110), GOLD)
	-- crown-shaped guard
	part(m, "Guard", Vector3.new(1.8, 0.36, 0.6), at(0, 1.66, 0), GOLD, METAL)
	for i = -2, 2 do
		part(m, "CrownPoint", Vector3.new(0.24, 0.5 - math.abs(i) * 0.08, 0.24), at(i * 0.4, 2.05 - math.abs(i) * 0.04, 0), GOLD, METAL)
	end
	part(m, "GuardGem", Vector3.new(0.4, 0.4, 0.3), at(0, 1.66, -0.2) * rot(0, 0, 45), magenta, NEON)
	-- great blade: gold frame around a core of pure aura
	for _, x in ipairs({ -1, 1 }) do
		part(m, "Frame", Vector3.new(0.26, 3.9, 0.22), at(x * 0.5, 4, 0), c, METAL)
		part(m, "FrameTaper", Vector3.new(0.24, 1.1, 0.2), at(x * 0.3, 6.3, 0) * rot(0, 0, x * 20), c, METAL)
		part(m, "Fin", Vector3.new(0.5, 0.24, 0.16), at(x * 0.85, 3, 0) * rot(0, 0, x * 40), cyan, NEON)
		part(m, "Fin", Vector3.new(0.4, 0.2, 0.16), at(x * 0.82, 4.4, 0) * rot(0, 0, x * 40), magenta, NEON)
	end
	local core = part(m, "Blade", Vector3.new(0.76, 4.4, 0.14), at(0, 4.2, 0), WHITE, NEON)
	part(m, "Tip", Vector3.new(0.3, 0.7, 0.14), at(0, 7, 0), WHITE, NEON)
	for i = 0, 2 do
		local star = part(m, "Star", Vector3.new(0.42, 0.42, 0.2), at(0, 2.9 + i * 1.3, 0) * rot(0, 0, 45), if i == 1 then cyan else magenta, NEON)
		star.Name = "Star" .. i
	end
	local orb = part(m, "Orb", Vector3.new(0.5, 0.5, 0.5), at(0, 7.7, 0), magenta, NEON)
	orb.Shape = Enum.PartType.Ball
	return handle, core
end

---------------------------------------------------------------------

local function weldAll(model, handle)
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		end
	end
end

-- Returns a Model named after the weapon, PrimaryPart "Handle".
function WeaponBuilder.Build(weapon): Model
	local model = Instance.new("Model")
	model.Name = weapon.Id
	local build = builders[weapon.Shape or weapon.Id] or builders.IronSword
	local handle, glowPart = build(model, weapon)
	model.PrimaryPart = handle

	-- Highest point of the weapon: the trail runs from above the grip to it.
	local top = 0
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			top = math.max(top, p.Position.Y + p.Size.Y / 2)
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = Vector3.new(0, 1.2 - handle.Position.Y, 0)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = Vector3.new(0, top - handle.Position.Y, 0)
	a1.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(weapon.Color:Lerp(WHITE, 0.4), weapon.Color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.18
	trail.LightEmission = 0.5
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = handle

	-- High tiers glow.
	if GLOW_FROM[weapon.Rarity] then
		local source = glowPart or model:FindFirstChild("Blade") or handle
		local light = Instance.new("PointLight")
		light.Color = weapon.Color
		light.Range = 10
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = source
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Color = ColorSequence.new(weapon.Color, WHITE)
		emitter.LightEmission = 0.7
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.2, 1)
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = if weapon.Rarity == "Legendary" then 8 else 16
		emitter.Parent = source
	end

	weldAll(model, handle)
	return model
end

-- Total length along +Y (for placing on racks / in viewports).
function WeaponBuilder.Length(model: Model): number
	return model:GetExtentsSize().Y
end

function WeaponBuilder.SetAnchored(model: Model, anchored: boolean)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = anchored
		end
	end
end

return WeaponBuilder
