--[[
	ArmorBuilder.luau
	Armor from Parts. A piece (Config.Armor entry) is a list of small
	parts, each placed relative to a body anchor: "Head", "Torso",
	"LeftShin", "RightShin". The same list is used to
	  - dress a real character (Attach: parts welded to the rig, R6 / R15),
	  - build a standalone model for previews and forge stands (Build,
	    BuildSet: parts placed where an R6 body would have them).
	Nano armor: every set shares a fitted base (shell, layered plates,
	visor, back power pack) so the full set reads as one suit; the Kind
	(Config.ArmorSets[set].Style.Kind) adds its silhouette:
	  Assembly - graphite + amber, welding visor, tool rail
	  Cryo     - white plates, ice-blue visor, coolant tubes
	  Thermo   - dark plate, glowing grilles, heat sink fins
	  Nexus    - black-violet, magenta lines, crest and an energy tail
	  Royal    - white and gold, cyan gem, cape
	Rarity: glowing inserts from Rare, a light from Epic, particles from
	Legendary.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ArmorBuilder = {}

-- Where the anchors are on an R6-proportioned body standing on y = 0.
local DUMMY = {
	Head = CFrame.new(0, 4.5, 0),
	Torso = CFrame.new(0, 3, 0),
	LeftShin = CFrame.new(-0.5, 0.5, 0),
	RightShin = CFrame.new(0.5, 0.5, 0),
}

local function rad(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- Returns { { Anchor, Name, Size, Offset, Color, Material, Transparency } }.
-- Every set shares one nano-armor base (a fitted shell, layered plates,
-- a visor, a back power pack) so a full set reads as one suit; the Kind
-- adds its own silhouette. Glowing inserts appear from Rare up (Config
-- rarity rules): below that the accents are painted metal.
local function specs(piece)
	local set = Config.ArmorSets[piece.Set]
	local s = set.Style
	local main, trim, glow, material = s.Main, s.Trim, s.Glow, s.Material
	local visor = s.Visor or glow
	local rank = Config.Rarity[set.Rarity].Index
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass
	local METAL = Enum.Material.Metal
	local glowMat = if rank >= Config.Rarity.Rare.Index then NEON else METAL
	local list = {}
	local function add(anchor, name, size, offset, color, mat, transparency)
		table.insert(list, { Anchor = anchor, Name = name, Size = size, Offset = offset, Color = color, Material = mat or material, Transparency = transparency or 0 })
	end
	local kind = s.Kind

	if piece.Slot == "Helmet" then
		add("Head", "Shell", Vector3.new(1.5, 0.75, 1.5), CFrame.new(0, 0.4, 0.02), main)
		add("Head", "Crown", Vector3.new(1.3, 0.25, 1.3), CFrame.new(0, 0.85, 0.05), trim, METAL)
		add("Head", "Back", Vector3.new(1.5, 0.95, 0.35), CFrame.new(0, -0.15, 0.62), main)
		for _, x in ipairs({ -1, 1 }) do
			add("Head", "EarModule", Vector3.new(0.3, 0.7, 0.7), CFrame.new(x * 0.78, -0.05, 0.05), trim, METAL)
			add("Head", "EarLight", Vector3.new(0.06, 0.3, 0.3), CFrame.new(x * 0.94, -0.05, 0.05), glow, glowMat)
		end
		add("Head", "Visor", Vector3.new(1.3, 0.42, 0.12), CFrame.new(0, 0.05, -0.72), visor, if kind == "Assembly" then GLASS else NEON, if kind == "Assembly" then 0.15 else 0.2)
		add("Head", "VisorFrame", Vector3.new(1.44, 0.12, 0.16), CFrame.new(0, 0.3, -0.72), trim, METAL)
		add("Head", "Jaw", Vector3.new(1.2, 0.35, 0.3), CFrame.new(0, -0.38, -0.6), main)
		if kind == "Assembly" then
			add("Head", "WeldVisor", Vector3.new(1.36, 0.5, 0.1), CFrame.new(0, 0.62, -0.62) * rad(-55, 0, 0), Color3.fromRGB(30, 34, 40), GLASS, 0.1)
			add("Head", "Lamp", Vector3.new(0.3, 0.22, 0.3), CFrame.new(0.55, 0.75, -0.45), Color3.fromRGB(255, 240, 210), METAL)
		elseif kind == "Cryo" then
			add("Head", "Tube", Vector3.new(0.18, 0.18, 1.2), CFrame.new(0, 0.95, 0.15), glow, GLASS, 0.3)
			for _, x in ipairs({ -1, 1 }) do
				add("Head", "Vent", Vector3.new(0.12, 0.4, 0.5), CFrame.new(x * 0.62, 0.5, 0.35), trim, METAL)
			end
		elseif kind == "Thermo" then
			for i = -1, 1 do
				add("Head", "Fin", Vector3.new(0.1, 0.45, 0.9), CFrame.new(i * 0.3, 1.05, 0.15), trim, METAL)
			end
			add("Head", "Grille", Vector3.new(0.9, 0.12, 0.08), CFrame.new(0, -0.38, -0.76), glow, glowMat)
		elseif kind == "Nexus" then
			add("Head", "Crest", Vector3.new(0.14, 0.7, 1.5), CFrame.new(0, 1.15, 0.15), glow, glowMat)
			for _, x in ipairs({ -1, 1 }) do
				add("Head", "Blade", Vector3.new(0.12, 0.25, 0.9), CFrame.new(x * 0.75, 0.75, 0.3) * rad(0, x * 12, x * -30), trim, METAL)
			end
		else -- Royal
			add("Head", "Crest", Vector3.new(0.16, 0.6, 1.4), CFrame.new(0, 1.1, 0.15), trim, METAL)
			add("Head", "Gem", Vector3.new(0.26, 0.26, 0.1), CFrame.new(0, 0.55, -0.74) * rad(0, 0, 45), glow, glowMat)
		end
	elseif piece.Slot == "Chest" then
		add("Torso", "Core", Vector3.new(2.14, 2.02, 1.14), CFrame.new(), main)
		add("Torso", "Plate", Vector3.new(1.7, 1, 0.2), CFrame.new(0, 0.42, -0.64), main)
		add("Torso", "PlateTrim", Vector3.new(1.8, 0.12, 0.24), CFrame.new(0, -0.1, -0.64), trim, METAL)
		for i = 0, 2 do
			add("Torso", "Ab", Vector3.new(1.2 - i * 0.1, 0.22, 0.16), CFrame.new(0, -0.35 - i * 0.26, -0.6), trim, METAL)
		end
		add("Torso", "Reactor", Vector3.new(0.5, 0.5, 0.1), CFrame.new(0, 0.42, -0.76) * rad(0, 0, 45), glow, glowMat)
		add("Torso", "Belt", Vector3.new(2.2, 0.26, 1.22), CFrame.new(0, -0.88, 0), trim, METAL)
		for _, x in ipairs({ -1, 1 }) do
			add("Torso", "Pauldron", Vector3.new(1.05, 0.5, 1.3), CFrame.new(x * 1.42, 0.9, 0) * rad(0, 0, x * -14), main)
			add("Torso", "PauldronLayer", Vector3.new(0.9, 0.3, 1.18), CFrame.new(x * 1.5, 0.62, 0) * rad(0, 0, x * -18), trim, METAL)
			add("Torso", "PauldronLight", Vector3.new(0.6, 0.06, 1.2), CFrame.new(x * 1.42, 1.17, 0) * rad(0, 0, x * -14), glow, glowMat)
		end
		-- back power pack
		add("Torso", "Pack", Vector3.new(1.4, 1.5, 0.5), CFrame.new(0, 0.2, 0.8), trim, METAL)
		add("Torso", "PackCore", Vector3.new(0.5, 0.9, 0.08), CFrame.new(0, 0.2, 1.06), glow, glowMat)
		if kind == "Assembly" then
			add("Torso", "ToolRail", Vector3.new(1.8, 0.2, 0.2), CFrame.new(0, -0.6, 0.74), Color3.fromRGB(255, 176, 50), METAL)
			add("Torso", "Hazard", Vector3.new(0.9, 0.18, 0.06), CFrame.new(0, 0.8, -0.74), Color3.fromRGB(255, 176, 50), METAL)
		elseif kind == "Cryo" then
			for _, x in ipairs({ -1, 1 }) do
				add("Torso", "Coolant", Vector3.new(0.32, 1.3, 0.32), CFrame.new(x * 0.5, 0.25, 1.05), glow, GLASS, 0.3)
			end
		elseif kind == "Thermo" then
			for i = -1, 1 do
				add("Torso", "HeatSink", Vector3.new(0.12, 0.9, 0.5), CFrame.new(i * 0.35, 1.1, 0.85), trim, METAL)
			end
			add("Torso", "Vent", Vector3.new(1.2, 0.1, 0.08), CFrame.new(0, 0.1, -0.76), glow, glowMat)
		elseif kind == "Nexus" then
			add("Torso", "Collar", Vector3.new(2, 0.4, 1.1), CFrame.new(0, 1.15, 0.1), trim, METAL)
			add("Torso", "Tail", Vector3.new(0.5, 2.6, 0.1), CFrame.new(0, -0.9, 1.0) * rad(-8, 0, 0), glow, glowMat, 0.3)
		else -- Royal
			add("Torso", "Collar", Vector3.new(2, 0.4, 1.1), CFrame.new(0, 1.15, 0.1), trim, METAL)
			add("Torso", "Cape", Vector3.new(1.9, 2.8, 0.12), CFrame.new(0, -0.55, 0.92) * rad(-6, 0, 0), Color3.fromRGB(40, 60, 110), Enum.Material.Fabric)
		end
	else -- Legs
		for _, anchor in ipairs({ "LeftShin", "RightShin" }) do
			add(anchor, "Greave", Vector3.new(1.14, 1.04, 1.14), CFrame.new(0, 0, 0), main)
			add(anchor, "Knee", Vector3.new(0.8, 0.45, 0.32), CFrame.new(0, 0.5, -0.56), trim, METAL)
			add(anchor, "Boot", Vector3.new(1.18, 0.35, 1.5), CFrame.new(0, -0.42, -0.12), trim, METAL)
			add(anchor, "Sole", Vector3.new(1.2, 0.08, 1.52), CFrame.new(0, -0.62, -0.12), glow, glowMat)
			add(anchor, "Shin", Vector3.new(0.12, 0.6, 0.08), CFrame.new(0, 0.05, -0.6), glow, glowMat)
			if kind == "Thermo" then
				add(anchor, "Fin", Vector3.new(0.1, 0.5, 0.5), CFrame.new(0, 0.2, 0.62), trim, METAL)
			elseif kind == "Nexus" or kind == "Royal" then
				add(anchor, "Wing", Vector3.new(0.1, 0.6, 0.5), CFrame.new(0, 0.15, 0.65), trim, METAL)
			elseif kind == "Cryo" then
				add(anchor, "Tube", Vector3.new(0.14, 0.8, 0.14), CFrame.new(0.4, 0, 0.5), glow, GLASS, 0.3)
			end
		end
	end
	return list
end

-- Rarity effects on a built / attached armor model (Config rules): Epic
-- and above glow (PointLight on the brightest part), Legendary and above
-- also emit particles. Secret gets the "ItemFx" tag (rainbow, client).
local function rarityFx(model: Model, piece)
	local set = Config.ArmorSets[piece.Set]
	local rarity = Config.Rarity[set.Rarity]
	local glowPart = model:FindFirstChild("Reactor") or model:FindFirstChild("Visor") or model:FindFirstChild("Sole") or model:FindFirstChild("PackCore")
	if not glowPart or rarity.Index < Config.Rarity.Epic.Index then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = set.Style.Glow
	light.Range = 7
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = glowPart
	if rarity.Index >= Config.Rarity.Legendary.Index then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(set.Style.Glow, Color3.new(1, 1, 1))
		emitter.LightEmission = 0.7
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.2, 1)
		emitter.Lifetime = NumberRange.new(0.5, 1)
		emitter.Speed = NumberRange.new(0.3, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 6
		emitter.Parent = glowPart
	end
	model:SetAttribute("Rarity", set.Rarity)
end

local function makePart(spec)
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Size = spec.Size
	part.Color = spec.Color
	part.Material = spec.Material
	part.Transparency = spec.Transparency
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function addPieceTo(model: Model, piece, origin: CFrame)
	for _, spec in ipairs(specs(piece)) do
		local part = makePart(spec)
		part.Anchored = true
		part.CFrame = origin * DUMMY[spec.Anchor] * spec.Offset
		part.Parent = model
	end
end

local function withRoot(model: Model, center: CFrame)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = center
	root.Parent = model
	model.PrimaryPart = root
	return model
end

-- Standalone anchored model of one piece (for ViewportFrames).
function ArmorBuilder.Build(piece): Model
	local model = Instance.new("Model")
	model.Name = piece.Id
	addPieceTo(model, piece, CFrame.new())
	rarityFx(model, piece)
	local center = if piece.Slot == "Helmet" then DUMMY.Head elseif piece.Slot == "Chest" then DUMMY.Torso else CFrame.new(0, 0.5, 0)
	return withRoot(model, center)
end

-- All three pieces of a set as one anchored model; the pivot is on the
-- ground between the feet (for the forge stands).
function ArmorBuilder.BuildSet(setId: string): Model
	local model = Instance.new("Model")
	model.Name = "ArmorSet_" .. setId
	for _, piece in ipairs(Config.Armor) do
		if piece.Set == setId then
			addPieceTo(model, piece, CFrame.new())
		end
	end
	return withRoot(model, CFrame.new())
end

-- Finds the body part and correction for an anchor on a real rig.
local function rigAnchor(character: Model, anchor: string): (BasePart?, CFrame)
	if anchor == "Head" then
		return character:FindFirstChild("Head"), CFrame.new()
	elseif anchor == "Torso" then
		local upper = character:FindFirstChild("UpperTorso")
		if upper then
			-- R15: the torso is UpperTorso + LowerTorso; shift down to their middle
			return upper, CFrame.new(0, -0.2, 0)
		end
		return character:FindFirstChild("Torso"), CFrame.new()
	end
	local side = if anchor == "LeftShin" then "Left" else "Right"
	local lower = character:FindFirstChild(side .. "LowerLeg")
	if lower then
		return lower, CFrame.new()
	end
	return character:FindFirstChild(side .. " Leg"), CFrame.new(0, -0.5, 0) -- R6: the shin is the lower half of the leg
end

-- Dresses a character: returns a Model of parts welded to its limbs.
function ArmorBuilder.Attach(character: Model, piece): Model
	local model = Instance.new("Model")
	model.Name = "Armor_" .. piece.Slot
	model:SetAttribute("ArmorId", piece.Id)
	for _, spec in ipairs(specs(piece)) do
		local limb, correction = rigAnchor(character, spec.Anchor)
		if limb then
			local part = makePart(spec)
			part.Anchored = false
			part.CFrame = limb.CFrame * correction * spec.Offset
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = limb
			weld.Part1 = part
			weld.Parent = part
			part.Parent = model
		end
	end
	rarityFx(model, piece)
	model.Parent = character
	return model
end

return ArmorBuilder
