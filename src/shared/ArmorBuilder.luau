--[[
	ArmorBuilder.luau
	Fitted nano armor (concept sheet 06). The base of every piece is a
	SHELL: a copy of the wearer's own body part (MeshPart / head mesh),
	a little bigger, repainted in metal - so the armor follows the shape
	of any avatar instead of being a box. On top come rounded details
	(ellipsoid pauldrons and knee caps, a curved visor, wedge crests and
	fins), placed relative to the body part's size.

	Three layers:
	  * the wearer's CLASS gives the silhouette: Blade = heavy plate (thick
	    shells, big layered pauldrons, closed helm with a crest, tabard),
	    Pulse = light (hood and mask, thin plates, sash, coat tails, arm
	    fins), Gunner = tactical (wide visor + headset, vest with pouches,
	    backpack, knee pads);
	  * the item RARITY gives the finish: Common bare metal, Uncommon green
	    lines, Rare blue, Epic violet glow + spikes, Legendary gold plates +
	    wings / energy blades + particles, Mythic red, Secret pink;
	  * the SET (Config.ArmorSets[set].Style) its colors and one signature
	    detail by Kind: Assembly lamp + hazard stripe, Cryo coolant tubes,
	    Thermo heat fins, Nexus energy tail, Orbit halo, Royal gem + cape.

	ArmorBuilder.Attach(character, piece, classId) dresses a rig (R15; R6
	works with box shells). ArmorBuilder.Build(piece, classId) makes a
	standalone model for icons / drops: it dresses a copy of a class
	character (ReplicatedStorage.ClassPreviews) and keeps only the armor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ArmorBuilder = {}

local GOLD = Color3.fromRGB(255, 201, 60)
local UNDER = Color3.fromRGB(32, 32, 38) -- the dark undersuit
local CLOTH = Color3.fromRGB(38, 40, 62)
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local FABRIC = Enum.Material.Fabric

-- Body part sizes of the plain R15 rig: details are scaled by the real
-- part's size against these.
local REF = {
	Head = Vector3.new(1.16, 1.18, 1.16),
	UpperTorso = Vector3.new(1.94, 1.7, 1),
	LowerTorso = Vector3.new(1.99, 0.4, 1),
	UpperArm = Vector3.new(1, 1.24, 1),
	LowerArm = Vector3.new(1, 1.12, 1),
	Hand = Vector3.new(0.98, 0.32, 1.03),
	UpperLeg = Vector3.new(0.99, 1.36, 0.97),
	LowerLeg = Vector3.new(0.99, 1.3, 0.97),
	Foot = Vector3.new(1, 0.31, 1),
}

-- R6: the R15 part names live in parts of the R6 limbs
-- { limb, centre offset (share of its height), height share }
local R6 = {
	UpperTorso = { "Torso", 0.2, 0.6 },
	LowerTorso = { "Torso", -0.4, 0.2 },
	LeftUpperArm = { "Left Arm", 0.25, 0.5 },
	RightUpperArm = { "Right Arm", 0.25, 0.5 },
	LeftLowerArm = { "Left Arm", -0.2, 0.4 },
	RightLowerArm = { "Right Arm", -0.2, 0.4 },
	LeftHand = { "Left Arm", -0.45, 0.1 },
	RightHand = { "Right Arm", -0.45, 0.1 },
	LeftUpperLeg = { "Left Leg", 0.25, 0.5 },
	RightUpperLeg = { "Right Leg", 0.25, 0.5 },
	LeftLowerLeg = { "Left Leg", -0.2, 0.4 },
	RightLowerLeg = { "Right Leg", -0.2, 0.4 },
	LeftFoot = { "Left Leg", -0.45, 0.1 },
	RightFoot = { "Right Leg", -0.45, 0.1 },
}

local function refOf(anchor: string): Vector3
	local short = anchor:gsub("^Left", ""):gsub("^Right", "")
	return REF[anchor] or REF[short] or Vector3.one
end

local function rad(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

---------------------------------------------------------------------
-- The design: a list of specs per piece / class / rarity / set
---------------------------------------------------------------------
-- spec = { Anchor, Name, Shape = "Shell" | "Block" | "Ball" | "Wedge",
--   Scale (Shell: multiplier of the body part), Size (studs on the plain
--   rig), At (position as a share of the half size, -1..1 = the surface),
--   Shift (studs), Rot (CFrame), Color, Material, Transparency }

local function specs(piece, classId: string?)
	local set = Config.ArmorSets[piece.Set]
	local s = set.Style
	local rarity = Config.Rarity[piece.Rarity or set.Rarity] or Config.Rarity[set.Rarity]
	local rank = rarity.Index
	local legendary = rank >= Config.Rarity.Legendary.Index
	local epic = rank >= Config.Rarity.Epic.Index
	local rare = rank >= Config.Rarity.Rare.Index
	local material = s.Material
	-- plates: the set color; Common / Uncommon closer to bare light steel
	-- (sheet 06), Legendary gold, Mythic red-gold
	local P = s.Main
	local T = s.Trim
	if rank <= Config.Rarity.Uncommon.Index then
		P = s.Main:Lerp(Color3.fromRGB(176, 180, 188), 0.45)
	end
	if legendary then
		P = s.Main:Lerp(GOLD, 0.75)
		T = Color3.fromRGB(150, 108, 40)
		material = METAL
	end
	if rank >= Config.Rarity.Mythic.Index then
		P = s.Main:Lerp(rarity.Color, 0.35):Lerp(GOLD, 0.3)
	end
	local A = if rank > 1 then rarity.Color else T -- Common: no colored lines
	local AM = if rank > 1 then NEON else METAL
	local G = s.Glow
	local class = if classId == "Pulse" or classId == "Gunner" then classId else "Blade"
	local kind = s.Kind
	local list = {}
	local function add(spec)
		spec.Material = spec.Material or material
		spec.Transparency = spec.Transparency or 0
		spec.At = spec.At or Vector3.zero
		spec.Shift = spec.Shift or Vector3.zero
		spec.Rot = spec.Rot or CFrame.new()
		table.insert(list, spec)
	end
	local function shell(anchor, name, scale, color, mat, transparency)
		add({ Anchor = anchor, Name = name, Shape = "Shell", Scale = scale, Color = color, Material = mat, Transparency = transparency })
	end
	local function ball(anchor, name, size, at, color, mat, shift, rot, transparency)
		add({ Anchor = anchor, Name = name, Shape = "Ball", Size = size, At = at, Color = color, Material = mat, Shift = shift, Rot = rot, Transparency = transparency })
	end
	local function block(anchor, name, size, at, color, mat, shift, rot, transparency)
		add({ Anchor = anchor, Name = name, Shape = "Block", Size = size, At = at, Color = color, Material = mat, Shift = shift, Rot = rot, Transparency = transparency })
	end
	local function wedge(anchor, name, size, at, color, mat, shift, rot, transparency)
		add({ Anchor = anchor, Name = name, Shape = "Wedge", Size = size, At = at, Color = color, Material = mat, Shift = shift, Rot = rot, Transparency = transparency })
	end
	local V = Vector3.new
	local sides = { { "Left", -1 }, { "Right", 1 } }

	if piece.Slot == "Helmet" then
		if class == "Blade" then
			shell("Head", "Shell", V(1.22, 1.14, 1.22), P)
			wedge("Head", "Crest", V(0.22, 0.42, 1.3), V(0, 1, 0.1), T, METAL, V(0, 0.2, 0))
			for _, sd in ipairs(sides) do
				local x = sd[2]
				ball("Head", "Cheek", V(0.32, 0.85, 0.85), V(x * 1, -0.25, -0.25), P)
				block("Head", "CrestLine", V(0.05, 0.3, 1.1), V(x * 0.1, 1, 0.1), A, AM, V(0, 0.18, 0))
				if epic then
					wedge("Head", "Horn", V(0.14, 0.55, 0.9), V(x * 0.95, 0.75, 0.2), T, METAL, nil, rad(0, 0, x * -35))
				end
			end
			ball("Head", "Face", V(0.95, 0.5, 0.42), V(0, -0.5, -1), P, nil, V(0, 0, -0.04))
			ball("Head", "Visor", V(1.1, 0.2, 0.42), V(0, 0.12, -1), G, NEON, V(0, 0, -0.05))
			if legendary then
				wedge("Head", "CrownFin", V(0.16, 0.8, 1.2), V(0, 1, 0.3), P, METAL, V(0, 0.5, 0), rad(-12, 0, 0))
			end
		elseif class == "Pulse" then
			shell("Head", "Hood", V(1.24, 1.16, 1.26), UNDER, FABRIC)
			wedge("Head", "HoodPeak", V(1, 0.22, 0.55), V(0, 0.9, -0.85), UNDER, FABRIC, nil, rad(-15, 0, 0))
			ball("Head", "Mask", V(1.05, 0.6, 0.5), V(0, -0.38, -0.92), P)
			ball("Head", "Visor", V(1.1, 0.16, 0.42), V(0, 0.12, -0.98), if rare then A else G, NEON)
			ball("Head", "Scarf", V(1.55, 0.45, 1.45), V(0, -1.1, 0), CLOTH, FABRIC)
			for _, sd in ipairs(sides) do
				local x = sd[2]
				wedge("Head", "EarFin", V(0.08, 0.38, 0.7), V(x * 1.05, 0.35, 0.2), T, METAL, nil, rad(0, 0, x * -20))
				block("Head", "EarLine", V(0.04, 0.3, 0.55), V(x * 1.12, 0.35, 0.2), A, AM, nil, rad(0, 0, x * -20))
				if epic then
					block("Head", "Antenna", V(0.07, 0.65, 0.07), V(x * 0.45, 1, 0.4), A, NEON, V(0, 0.3, 0), rad(-15, 0, x * -15))
				end
			end
		else -- Gunner
			shell("Head", "Shell", V(1.2, 1.1, 1.2), P)
			block("Head", "Ridge", V(0.85, 0.12, 0.95), V(0, 1, 0.1), T, METAL, V(0, 0.08, 0))
			ball("Head", "Visor", V(1.2, 0.6, 0.55), V(0, 0, -0.98), G, NEON, nil, nil, 0.25)
			ball("Head", "Chin", V(0.9, 0.3, 0.4), V(0, -0.8, -0.85), P)
			for _, sd in ipairs(sides) do
				local x = sd[2]
				ball("Head", "EarCup", V(0.36, 0.62, 0.62), V(x * 1.08, 0, 0), T, METAL)
				ball("Head", "EarLight", V(0.08, 0.24, 0.24), V(x * 1.3, 0, 0), A, AM)
			end
			if rare then
				block("Head", "Antenna", V(0.06, 0.95, 0.06), V(0.6, 1, 0.4), T, METAL, V(0, 0.45, 0))
			end
			if legendary then
				for _, sd in ipairs(sides) do
					wedge("Head", "Fin", V(0.1, 0.6, 0.7), V(sd[2] * 0.6, 0.9, 0.7), G, NEON, nil, rad(25, 0, sd[2] * -20), 0.15)
				end
			end
		end
		-- the set's signature detail
		if kind == "Assembly" then
			ball("Head", "Lamp", V(0.3, 0.26, 0.3), V(0.6, 0.85, -0.7), Color3.fromRGB(255, 240, 210), NEON)
		elseif kind == "Cryo" then
			block("Head", "Tube", V(0.16, 0.16, 1.1), V(-0.45, 1, 0.1), G, GLASS, V(0, 0.08, 0), nil, 0.3)
		elseif kind == "Thermo" then
			for i = -1, 1 do
				wedge("Head", "HeatFin", V(0.08, 0.3, 0.6), V(i * 0.3, 1, 0.4), T, METAL, V(0, 0.15, 0))
			end
		elseif kind == "Orbit" then
			for k = 0, 9 do
				local a = k / 10 * math.pi * 2
				block("Head", "Halo", V(0.1, 0.08, 0.55), V(math.cos(a) * 0.85, 1, math.sin(a) * 0.85), G, NEON, V(0, 0.45, 0), rad(0, -math.deg(a), 0), 0.1)
			end
		elseif kind == "Royal" then
			ball("Head", "Gem", V(0.24, 0.24, 0.12), V(0, 0.55, -1.08), G, NEON)
		end
	elseif piece.Slot == "Chest" then
		-- the undersuit on the torso and arms
		shell("UpperTorso", "Suit", V(1.03, 1.02, 1.06), UNDER, FABRIC)
		shell("LowerTorso", "SuitLow", V(1.03, 1.05, 1.06), UNDER, FABRIC)
		for _, sd in ipairs(sides) do
			shell(sd[1] .. "UpperArm", "Sleeve", V(1.06, 1.01, 1.06), UNDER, FABRIC)
			shell(sd[1] .. "LowerArm", "SleeveLow", V(1.05, 1.01, 1.05), UNDER, FABRIC)
		end
		if class == "Blade" then
			shell("UpperTorso", "Plate", V(1.13, 1.05, 1.26), P)
			shell("LowerTorso", "Belt", V(1.12, 1.2, 1.24), T, METAL)
			block("UpperTorso", "Reactor", V(0.42, 0.42, 0.12), V(0, 0.25, -1), A, AM, V(0, 0, -0.16), rad(0, 0, 45))
			ball("UpperTorso", "Gorget", V(1.45, 0.45, 1.2), V(0, 1, 0), T, METAL)
			block("LowerTorso", "Buckle", V(0.5, 0.34, 0.12), V(0, 0, -1), A, AM, V(0, 0, -0.14))
			block("LowerTorso", "Tabard", V(0.9, 1.2, 0.08), V(0, -1, -1), CLOTH, FABRIC, V(0, -0.6, -0.12))
			block("LowerTorso", "TabardLine", V(0.07, 1, 0.1), V(0, -1, -1), A, AM, V(0, -0.55, -0.15))
			for _, sd in ipairs(sides) do
				local side, x = sd[1], sd[2]
				ball("UpperTorso", "Pauldron", V(1.45, 0.85, 1.5), V(x * 1, 0.85, 0), P, nil, V(x * 0.12, 0.12, 0))
				ball("UpperTorso", "PauldronLayer", V(1.25, 0.55, 1.32), V(x * 1, 0.6, 0), T, METAL, V(x * 0.3, -0.12, 0))
				ball("UpperTorso", "PauldronRim", V(1.15, 0.12, 1.25), V(x * 1, 0.85, 0), A, AM, V(x * 0.12, 0.52, 0))
				if epic then
					wedge("UpperTorso", "Spike", V(0.18, 0.75, 0.4), V(x * 1, 0.85, 0), T, METAL, V(x * 0.12, 0.8, 0), rad(0, 0, x * -15))
				end
				shell(side .. "UpperArm", "ArmPlate", V(1.13, 0.75, 1.13), P)
				shell(side .. "LowerArm", "Gauntlet", V(1.2, 1.04, 1.2), P)
				ball(side .. "LowerArm", "Cuff", V(1.25, 0.2, 1.25), V(0, -0.85, 0), T, METAL)
				block(side .. "LowerArm", "GauntletLine", V(0.05, 0.6, 0.15), V(x * 1, 0.1, 0), A, AM, V(x * 0.12, 0, 0))
				shell(side .. "Hand", "Glove", V(1.12, 1.2, 1.1), T, METAL)
			end
		elseif class == "Pulse" then
			shell("UpperTorso", "Plate", V(1.07, 1.03, 1.12), P)
			shell("LowerTorso", "Belt", V(1.06, 0.7, 1.12), T, METAL)
			block("UpperTorso", "Sash", V(2.3, 0.2, 1.18), V(0, 0, 0), T, METAL, nil, rad(0, 0, 38))
			block("UpperTorso", "Reactor", V(0.28, 0.28, 0.08), V(0, 0.45, -1), A, AM, V(0, 0, -0.1), rad(0, 0, 45))
			for _, sd in ipairs(sides) do
				local side, x = sd[1], sd[2]
				block("UpperTorso", "VLine", V(0.07, 0.8, 0.08), V(x * 0.36, 0.1, -1), A, AM, V(0, 0, -0.08), rad(0, 0, x * 25))
				ball("UpperTorso", "Pauldron", V(0.95, 0.42, 1.1), V(x * 1, 0.9, 0), P, nil, V(x * 0.05, 0.02, 0), rad(0, 0, x * -22))
				ball("UpperTorso", "PauldronTip", V(0.75, 0.08, 1), V(x * 1, 0.9, 0), A, AM, V(x * 0.05, 0.2, 0), rad(0, 0, x * -22))
				block("LowerTorso", "CoatTail", V(0.7, 1.6, 0.08), V(x * 0.5, -1, 1), UNDER, FABRIC, V(0, -0.75, 0.06), rad(8, 0, 0))
				shell(side .. "LowerArm", "Bracer", V(1.1, 0.95, 1.1), P)
				wedge(side .. "LowerArm", "ArmFin", V(0.08, 0.7, 0.6), V(x * 1, 0.2, 0.2), T, METAL, V(x * 0.1, 0, 0))
				block(side .. "LowerArm", "FinLine", V(0.04, 0.55, 0.45), V(x * 1, 0.2, 0.2), A, AM, V(x * 0.15, 0, 0))
				if epic then
					block(side .. "LowerArm", "EnergyBlade", V(0.06, 1.4, 0.45), V(x * 1, 0.5, 0.6), A, NEON, V(x * 0.15, 0.3, 0.1), rad(25, 0, 0), 0.3)
				end
			end
		else -- Gunner
			shell("UpperTorso", "Vest", V(1.15, 1.04, 1.3), P)
			shell("LowerTorso", "Belt", V(1.12, 1.25, 1.26), T, METAL)
			ball("UpperTorso", "Collar", V(1.5, 0.35, 1.2), V(0, 1, 0), T, METAL)
			block("UpperTorso", "Reactor", V(0.38, 0.22, 0.08), V(0.5, 0.5, -1), A, AM, V(0, 0, -0.16))
			for i = -1, 1 do
				ball("UpperTorso", "Pouch", V(0.5, 0.42, 0.3), V(i * 0.6, -0.75, -1), T, METAL, V(0, 0, -0.16))
			end
			block("UpperTorso", "Pack", V(1.3, 1.25, 0.55), V(0, 0.05, 1), T, METAL, V(0, 0, 0.35))
			block("UpperTorso", "PackCore", V(0.45, 0.18, 0.06), V(0, 0.5, 1), A, AM, V(0, 0, 0.64))
			if rare then
				block("UpperTorso", "PackAntenna", V(0.06, 1.3, 0.06), V(0.5, 1, 1), T, METAL, V(0, 0.6, 0.35))
			end
			if epic then
				block("UpperTorso", "AmmoBelt", V(2.3, 0.18, 0.25), V(0, 0.1, -1), T, METAL, V(0, 0, -0.18), rad(0, 0, -35))
			end
			for _, sd in ipairs(sides) do
				local side, x = sd[1], sd[2]
				block("UpperTorso", "Strap", V(0.16, 1.6, 0.06), V(x * 0.42, 0.1, -1), Color3.fromRGB(44, 44, 48), FABRIC, V(0, 0, -0.17), rad(0, 0, x * 16))
				ball("UpperTorso", "Pauldron", V(1.1, 0.55, 1.25), V(x * 1, 0.85, 0), P, nil, V(x * 0.1, 0.05, 0), rad(0, 0, x * -10))
				block("UpperTorso", "PauldronLine", V(0.05, 0.25, 0.9), V(x * 1, 0.85, 0), A, AM, V(x * 0.62, 0, 0), rad(0, 0, x * -10))
				ball(side .. "UpperArm", "ElbowPad", V(1.1, 0.4, 1.1), V(0, -0.85, 0), T, METAL)
				shell(side .. "LowerArm", "Glove", V(1.12, 1, 1.12), P)
				if side == "Left" then
					block(side .. "LowerArm", "WristPad", V(0.28, 0.3, 0.5), V(x * 1, 0.2, 0), T, METAL, V(x * 0.12, 0, 0))
					block(side .. "LowerArm", "WristScreen", V(0.04, 0.2, 0.38), V(x * 1, 0.2, 0), A, AM, V(x * 0.27, 0, 0))
				end
			end
		end
		-- every tier: a crest on the chest (two wings + a diamond) and studs
		-- on the shoulders, so even Common reads as crafted armor
		local crestColor = if legendary then GOLD else T
		for _, sd in ipairs(sides) do
			local x = sd[2]
			wedge("UpperTorso", "CrestWing", V(0.08, 0.22, 0.55), V(x * 0.22, 0.62, -1), crestColor, METAL, V(0, 0, -0.2), rad(0, 90, x * 70))
			ball("UpperTorso", "Stud", V(0.16, 0.16, 0.16), V(x * 1, 0.85, 0), crestColor, METAL, V(x * 0.45, 0.45, -0.35))
			ball("UpperTorso", "Stud", V(0.16, 0.16, 0.16), V(x * 1, 0.85, 0), crestColor, METAL, V(x * 0.45, 0.45, 0.35))
		end
		block("UpperTorso", "CrestGem", V(0.2, 0.2, 0.1), V(0, 0.62, -1), A, AM, V(0, 0, -0.22), rad(0, 0, 45))
		-- Legendary: wings (Blade), energy blades (Pulse), energy fins (Gunner)
		if legendary then
			for _, sd in ipairs(sides) do
				local x = sd[2]
				for k = 0, 2 do
					if class == "Blade" then
						local rot = rad(-10, 0, x * (-48 - k * 18))
						local shift = V(x * (0.6 + k * 0.55), 0.55 - k * 0.2, 0.45)
						wedge("UpperTorso", "Wing", V(0.14, 2.4 - k * 0.45, 0.55), V(x * 0.3, 0.5, 1), P, METAL, shift, rot)
						block("UpperTorso", "WingEdge", V(0.05, 2.3 - k * 0.45, 0.06), V(x * 0.3, 0.5, 1), A, NEON, shift + V(0, 0, -0.3), rot)
					elseif class == "Pulse" then
						block("UpperTorso", "EnergyWing", V(0.07, 2.6 - k * 0.5, 0.22), V(x * 0.3, 0.4, 1), A, NEON, V(x * (0.5 + k * 0.45), 0.3 + k * 0.1, 0.35), rad(0, 0, x * (-42 - k * 15)), 0.2)
					else
						wedge("UpperTorso", "EnergyFin", V(0.08, 1.8 - k * 0.35, 0.5), V(x * 0.4, 0.3, 1), G, NEON, V(x * (0.5 + k * 0.35), 0, 0.6), rad(0, 0, x * (-20 - k * 14)), 0.15)
					end
				end
			end
			if class == "Blade" then
				block("UpperTorso", "Cape", V(1.8, 2.6, 0.08), V(0, 0.6, 1), Color3.fromRGB(46, 34, 20), FABRIC, V(0, -1.2, 0.2), rad(-6, 0, 0))
			end
		end
		-- the set's signature detail
		if kind == "Assembly" then
			block("UpperTorso", "Hazard", V(0.9, 0.14, 0.06), V(0, -0.55, -1), Color3.fromRGB(255, 176, 50), METAL, V(0, 0, -0.18))
		elseif kind == "Cryo" then
			for _, sd in ipairs(sides) do
				block("UpperTorso", "Coolant", V(0.24, 1.1, 0.24), V(sd[2] * 0.75, 0.1, 1), G, GLASS, V(0, 0, 0.2), nil, 0.3)
			end
		elseif kind == "Thermo" then
			block("LowerTorso", "Vent", V(1.1, 0.1, 0.08), V(0, 0, -1), G, NEON, V(0, 0, -0.16))
		elseif kind == "Nexus" then
			block("LowerTorso", "Tail", V(0.4, 2.2, 0.06), V(0, -1, 1), G, NEON, V(0, -1, 0.2), rad(-8, 0, 0), 0.35)
		elseif kind == "Royal" and not (legendary and class == "Blade") then
			block("UpperTorso", "Cape", V(1.8, 2.8, 0.1), V(0, 0.6, 1), Color3.fromRGB(40, 60, 110), FABRIC, V(0, -1.3, 0.2), rad(-6, 0, 0))
		end
	else -- Legs
		for _, sd in ipairs(sides) do
			local side, x = sd[1], sd[2]
			local thigh, shin, foot = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
			shell(thigh, "Suit", V(1.04, 1.01, 1.05), UNDER, FABRIC)
			if class == "Blade" then
				shell(thigh, "Cuisse", V(1.14, 0.9, 1.16), P)
				block(thigh, "Tasset", V(0.9, 0.6, 0.1), V(0, 0.75, -1), T, METAL, V(0, 0, -0.14), rad(10, 0, 0))
				block(thigh, "CuisseLine", V(0.45, 0.05, 0.06), V(0, -0.4, -1), A, AM, V(0, 0, -0.1))
				shell(shin, "Greave", V(1.16, 1.0, 1.18), P)
				ball(shin, "Knee", V(0.78, 0.62, 0.5), V(0, 1, -1), P, nil, V(0, -0.05, -0.05))
				ball(shin, "KneeLine", V(0.5, 0.08, 0.2), V(0, 1, -1), A, AM, V(0, -0.05, -0.28))
				shell(foot, "Boot", V(1.16, 1.45, 1.12), T, METAL)
			elseif class == "Pulse" then
				shell(thigh, "ThighWrap", V(1.07, 0.95, 1.08), UNDER, FABRIC)
				ball(thigh, "ThighPlate", V(0.62, 0.6, 0.22), V(0, 0, -1), P, nil, V(0, 0, -0.04))
				block(thigh, "ThighLine", V(0.05, 0.5, 0.05), V(x * 0.55, 0, -1), A, AM, V(0, 0, -0.1))
				shell(shin, "Greave", V(1.1, 1.0, 1.12), P)
				wedge(shin, "AnkleFin", V(0.08, 0.42, 0.62), V(x * 1, -0.5, 0.2), T, METAL, V(x * 0.08, 0, 0), rad(0, 0, x * -12))
				block(shin, "FinLine", V(0.04, 0.34, 0.5), V(x * 1, -0.5, 0.2), A, AM, V(x * 0.13, 0, 0), rad(0, 0, x * -12))
				shell(foot, "Boot", V(1.08, 1.25, 1.06), UNDER, FABRIC)
			else
				shell(thigh, "Cargo", V(1.13, 0.98, 1.14), P:Lerp(UNDER, 0.3))
				block(thigh, "Pocket", V(0.24, 0.5, 0.55), V(x * 1, -0.1, 0), T, METAL, V(x * 0.12, 0, 0))
				if side == "Right" then
					block(thigh, "Holster", V(0.28, 0.7, 0.45), V(x * 1, -0.3, 0.3), UNDER, FABRIC, V(x * 0.3, 0, 0))
				end
				shell(shin, "Shin", V(1.12, 1, 1.14), P)
				ball(shin, "KneePad", V(0.85, 0.55, 0.5), V(0, 1, -1), T, METAL, V(0, -0.05, -0.05))
				ball(shin, "KneeLine", V(0.55, 0.08, 0.2), V(0, 1, -1), A, AM, V(0, -0.05, -0.3))
				shell(foot, "Boot", V(1.2, 1.55, 1.14), UNDER, METAL)
			end
			block(foot, "Sole", V(1.02, 0.07, 1.06), V(0, -1, 0), A, AM, V(0, -0.02, 0))
			if legendary then
				wedge(shin, "Wing", V(0.08, 0.55, 0.5), V(x * 1, 0.1, 0.4), A, NEON, V(x * 0.1, 0, 0), rad(0, 0, x * -15))
			end
			if kind == "Cryo" then
				block(shin, "Tube", V(0.13, 0.8, 0.13), V(x * 0.6, 0, 1), G, GLASS, V(0, 0, 0.1), nil, 0.3)
			elseif kind == "Thermo" then
				wedge(shin, "HeatFin", V(0.1, 0.5, 0.45), V(0, 0.3, 1), T, METAL, V(0, 0, 0.18))
			end
		end
	end
	return list
end

---------------------------------------------------------------------
-- Building the parts on a body
---------------------------------------------------------------------

-- The body box an anchor stands for: (body part, its CFrame, its size,
-- the part to copy for a shell or nil).
local function bodyBox(character: Model, anchor: string)
	local part = character:FindFirstChild(anchor)
	if part and part:IsA("BasePart") then
		return part, part.CFrame, part.Size, part
	end
	local r6 = R6[anchor]
	local limb = r6 and character:FindFirstChild(r6[1])
	if limb and limb:IsA("BasePart") then
		local size = Vector3.new(limb.Size.X, limb.Size.Y * r6[3], limb.Size.Z)
		return limb, limb.CFrame * CFrame.new(0, limb.Size.Y * r6[2], 0), size, nil
	end
	return nil
end

local function finish(part: BasePart, spec)
	part.Name = spec.Name
	part.Color = spec.Color
	part.Material = spec.Material
	part.Transparency = spec.Transparency
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = spec.Shape == "Shell"
	if part:IsA("Part") then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	return part
end

-- One spec on a body box -> a part (not parented, not welded).
local function makePart(spec, cf: CFrame, size: Vector3, source: BasePart?)
	if spec.Shape == "Shell" then
		local part
		local mesh = source and source:FindFirstChildOfClass("SpecialMesh")
		if source and (source:IsA("MeshPart") or mesh) then
			local archivable = source.Archivable
			source.Archivable = true
			part = source:Clone()
			source.Archivable = archivable
			part:ClearAllChildren()
			if mesh then
				mesh:Clone().Parent = part
			end
			if part:IsA("MeshPart") then
				part.TextureID = ""
			end
		else
			part = Instance.new("Part")
		end
		part.Size = size * spec.Scale
		part.CFrame = cf
		return finish(part, spec)
	end
	local ref = refOf(spec.Anchor)
	local k = Vector3.new(math.clamp(size.X / ref.X, 0.7, 1.5), math.clamp(size.Y / ref.Y, 0.7, 1.5), math.clamp(size.Z / ref.Z, 0.7, 1.5))
	local part
	if spec.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		if spec.Shape == "Ball" then
			local sphere = Instance.new("SpecialMesh")
			sphere.MeshType = Enum.MeshType.Sphere
			sphere.Parent = part
		end
	end
	part.Size = spec.Size * k
	local at = spec.At
	local pos = Vector3.new(at.X * size.X / 2, at.Y * size.Y / 2, at.Z * size.Z / 2) + spec.Shift * k
	part.CFrame = cf * CFrame.new(pos) * spec.Rot
	return finish(part, spec)
end

-- Rarity effects: Epic and above give a light in the rarity color,
-- Legendary and above also particles; +10 enhance adds a pale glow.
local function rarityFx(model: Model, piece)
	local set = Config.ArmorSets[piece.Set]
	local rarity = Config.Rarity[piece.Rarity or set.Rarity] or Config.Rarity[set.Rarity]
	local glowPart = model:FindFirstChild("Reactor") or model:FindFirstChild("Visor") or model:FindFirstChild("Sole") or model:FindFirstChild("PackCore")
	model:SetAttribute("Rarity", rarity.Id)
	if glowPart and piece.Glow then
		local glow = Instance.new("PointLight")
		glow.Name = "EnhanceGlow"
		glow.Color = Color3.fromRGB(190, 245, 255)
		glow.Range = 8
		glow.Brightness = 1.2
		glow.Shadows = false
		glow.Parent = glowPart
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "EnhanceSparks"
		sparks.Color = ColorSequence.new(Color3.fromRGB(190, 245, 255), Color3.new(1, 1, 1))
		sparks.LightEmission = 0.9
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new(0.1, 1)
		sparks.Lifetime = NumberRange.new(0.5, 0.9)
		sparks.Speed = NumberRange.new(0.4, 1.2)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 5
		sparks.Parent = glowPart
	end
	-- the client (ArmorFx) animates Rare+ armor: pulsing lines, orbiting
	-- energy motes (Epic+), a turning halo behind the back (Legendary+)
	if rarity.Index >= Config.Rarity.Rare.Index then
		model:SetAttribute("FxRank", rarity.Index)
		model:SetAttribute("FxColor", rarity.Color)
		model:SetAttribute("FxSlot", piece.Slot)
		game:GetService("CollectionService"):AddTag(model, "ArmorFx")
	end
	-- Epic+: a glowing sheen over the main plates
	if rarity.Index >= Config.Rarity.Epic.Index then
		for _, part in ipairs(model:GetChildren()) do
			if part:IsA("BasePart") and (part.Name == "Plate" or part.Name == "Shell" or part.Name == "Vest" or part.Name == "Gauntlet" or part.Name == "Greave" or part.Name == "Cuisse" or part.Name == "Shin") then
				local sheen = part:Clone()
				sheen.Name = "Sheen"
				sheen:ClearAllChildren()
				if part:FindFirstChildOfClass("SpecialMesh") then
					part:FindFirstChildOfClass("SpecialMesh"):Clone().Parent = sheen
				end
				sheen.Size = part.Size * 1.025
				sheen.CFrame = part.CFrame
				sheen.Material = Enum.Material.Neon
				sheen.Color = rarity.Color
				sheen.Transparency = if rarity.Index >= Config.Rarity.Legendary.Index then 0.8 else 0.86
				sheen.CastShadow = false
				if not part.Anchored then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part
					weld.Part1 = sheen
					weld.Parent = sheen
				end
				sheen.Parent = model
			end
		end
	end
	if not glowPart or rarity.Index < Config.Rarity.Epic.Index then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 7
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = glowPart
	if rarity.Index >= Config.Rarity.Legendary.Index then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		emitter.LightEmission = 0.7
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.2, 1)
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 6
		emitter.Parent = glowPart
		-- gold sparkles drifting up from the whole piece
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "LegendSparkles"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(rarity.Color:Lerp(Color3.new(1, 1, 1), 0.3))
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Transparency = NumberSequence.new(0.1, 1)
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(0.6, 1.4)
		sparkle.Acceleration = Vector3.new(0, 1.5, 0)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 8
		sparkle.Parent = glowPart
	end
end

-- Dresses a character: returns a Model of parts welded to its body.
function ArmorBuilder.Attach(character: Model, piece, classId: string?): Model
	local model = Instance.new("Model")
	model.Name = "Armor_" .. piece.Slot
	model:SetAttribute("ArmorId", piece.Id)
	for _, spec in ipairs(specs(piece, classId)) do
		local body, cf, size, source = bodyBox(character, spec.Anchor)
		if body then
			local part = makePart(spec, cf, size, source)
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
			part.Parent = model
		end
	end
	rarityFx(model, piece)
	model.Parent = character
	return model
end

---------------------------------------------------------------------
-- Standalone models (icons, drops, stands)
---------------------------------------------------------------------

-- Where an R15 body has its parts (standing on y = 0, facing -Z): the
-- fallback body when no class character is at hand.
local BOXES = {
	Head = { CFrame.new(0, 5.25, 0), REF.Head },
	UpperTorso = { CFrame.new(0, 3.95, 0), REF.UpperTorso },
	LowerTorso = { CFrame.new(0, 2.9, 0), REF.LowerTorso },
	LeftUpperArm = { CFrame.new(-1.5, 4.0, 0), REF.UpperArm },
	RightUpperArm = { CFrame.new(1.5, 4.0, 0), REF.UpperArm },
	LeftLowerArm = { CFrame.new(-1.5, 2.85, 0), REF.LowerArm },
	RightLowerArm = { CFrame.new(1.5, 2.85, 0), REF.LowerArm },
	LeftHand = { CFrame.new(-1.5, 2.15, 0), REF.Hand },
	RightHand = { CFrame.new(1.5, 2.15, 0), REF.Hand },
	LeftUpperLeg = { CFrame.new(-0.5, 2.0, 0), REF.UpperLeg },
	RightUpperLeg = { CFrame.new(0.5, 2.0, 0), REF.UpperLeg },
	LeftLowerLeg = { CFrame.new(-0.5, 0.95, 0), REF.LowerLeg },
	RightLowerLeg = { CFrame.new(0.5, 0.95, 0), REF.LowerLeg },
	LeftFoot = { CFrame.new(-0.5, 0.16, 0), REF.Foot },
	RightFoot = { CFrame.new(0.5, 0.16, 0), REF.Foot },
}

-- A copy of a class character (ReplicatedStorage.ClassPreviews) to take
-- the body shapes from.
local function mannequin(classId: string?): Model?
	local folder = ReplicatedStorage:FindFirstChild("ClassPreviews")
	local source = folder and (folder:FindFirstChild(classId or "") or folder:FindFirstChild("Blade"))
	if not source or not source:IsA("Model") or not source:FindFirstChild("UpperTorso") then
		return nil
	end
	source.Archivable = true
	local copy = source:Clone()
	local _, size = copy:GetBoundingBox()
	copy:PivotTo(CFrame.new(0, size.Y / 2, 0))
	return copy
end

local function standalone(pieces, classId: string?, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local body = mannequin(classId)
	for _, piece in ipairs(pieces) do
		for _, spec in ipairs(specs(piece, classId)) do
			local cf, size, source
			if body then
				local found
				found, cf, size, source = bodyBox(body, spec.Anchor)
				if not found then
					continue
				end
			else
				local box = BOXES[spec.Anchor]
				if not box then
					continue
				end
				cf, size = box[1], box[2]
			end
			local part = makePart(spec, cf, size, source)
			part.Anchored = true
			part.Parent = model
		end
	end
	if body then
		body:Destroy()
	end
	for _, piece in ipairs(pieces) do
		rarityFx(model, piece)
	end
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	local box = model:GetBoundingBox()
	root.CFrame = CFrame.new(box.Position)
	root.Parent = model
	model.PrimaryPart = root
	return model
end

-- One piece as an anchored model; classId = whose silhouette (the
-- viewer's class; Blade when unknown).
function ArmorBuilder.Build(piece, classId: string?): Model
	return standalone({ piece }, classId, piece.Id)
end

-- All three pieces of a set (optionally of one rarity) as one model.
function ArmorBuilder.BuildSet(setId: string, classId: string?, rarity: string?): Model
	local pieces = {}
	for _, piece in ipairs(Config.Armor) do
		if piece.Set == setId then
			table.insert(pieces, if rarity then setmetatable({ Rarity = rarity }, { __index = piece }) else piece)
		end
	end
	return standalone(pieces, classId, "ArmorSet_" .. setId)
end

return ArmorBuilder
