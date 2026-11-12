--[[
	ArmorBuilder.luau
	Armor from Parts. A piece (Config.Armor entry) is a list of small
	parts, each placed relative to a body anchor: "Head", "Torso",
	"LeftShin", "RightShin". The same list is used to
	  - dress a real character (Attach: parts welded to the rig, R6 / R15),
	  - build a standalone model for previews and forge stands (Build,
	    BuildSet: parts placed where an R6 body would have them).
	Each set (Config.ArmorSets[set].Style) has its own silhouette and
	colors so it is recognizable from afar:
	  Bone  - ivory plates, horns and ribs
	  Ice   - light-blue ice with crystal spikes
	  Lava  - black slate with glowing orange cracks and big horns
	  Abyss - purple metal, gold trim, magenta glow, crest and cape
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
local function specs(piece)
	local set = Config.ArmorSets[piece.Set]
	local s = set.Style
	local main, trim, glow, material = s.Main, s.Trim, s.Glow, s.Material
	local list = {}
	local function add(anchor, name, size, offset, color, mat, transparency)
		table.insert(list, { Anchor = anchor, Name = name, Size = size, Offset = offset, Color = color, Material = mat or material, Transparency = transparency or 0 })
	end
	local NEON = Enum.Material.Neon
	local GLASS = Enum.Material.Glass

	if piece.Slot == "Helmet" then
		add("Head", "Shell", Vector3.new(1.46, 0.8, 1.46), CFrame.new(0, 0.38, 0), main)
		add("Head", "Neck", Vector3.new(1.46, 0.7, 0.3), CFrame.new(0, -0.3, 0.6), main)
		add("Head", "Brow", Vector3.new(1.52, 0.22, 0.22), CFrame.new(0, 0.05, -0.68), trim)
		for _, x in ipairs({ -1, 1 }) do
			add("Head", "Cheek", Vector3.new(0.2, 0.7, 1), CFrame.new(x * 0.68, -0.3, -0.05), trim)
		end
		if s.Kind == "Bone" then
			for _, x in ipairs({ -1, 1 }) do
				add("Head", "Horn", Vector3.new(0.26, 0.8, 0.26), CFrame.new(x * 0.7, 0.95, 0) * rad(0, 0, x * -28), main)
			end
			for i = -1, 1 do
				add("Head", "Ridge", Vector3.new(0.22, 0.3, 0.36), CFrame.new(0, 0.9, i * 0.42), trim)
			end
			add("Head", "Gem", Vector3.new(0.26, 0.26, 0.1), CFrame.new(0, 0.42, -0.74) * rad(0, 0, 45), glow, NEON)
		elseif s.Kind == "Ice" then
			for i = -1, 1 do
				add("Head", "Spike", Vector3.new(0.3, 0.9 - math.abs(i) * 0.25, 0.3), CFrame.new(i * 0.42, 1.15 - math.abs(i) * 0.1, 0) * rad(0, 45, i * -14), trim, GLASS, 0.15)
			end
			add("Head", "Gem", Vector3.new(0.3, 0.3, 0.12), CFrame.new(0, 0.42, -0.74) * rad(0, 0, 45), glow, NEON)
			add("Head", "Frost", Vector3.new(1.5, 0.12, 1.5), CFrame.new(0, 0.82, 0), trim, Enum.Material.Ice)
		elseif s.Kind == "Lava" then
			for _, x in ipairs({ -1, 1 }) do
				add("Head", "Horn", Vector3.new(0.34, 0.9, 0.34), CFrame.new(x * 0.82, 0.8, 0) * rad(0, 0, x * -40), trim)
				add("Head", "HornTip", Vector3.new(0.24, 0.6, 0.24), CFrame.new(x * 1.12, 1.4, 0) * rad(0, 0, x * -8), glow, NEON)
			end
			add("Head", "Visor", Vector3.new(1.05, 0.16, 0.1), CFrame.new(0, -0.18, -0.72), glow, NEON)
			add("Head", "Crack", Vector3.new(0.1, 0.5, 0.1), CFrame.new(0.3, 0.45, -0.72) * rad(0, 0, 25), glow, NEON)
		else -- Abyss
			add("Head", "Peak", Vector3.new(1.1, 0.4, 1.1), CFrame.new(0, 0.95, 0), main)
			add("Head", "Crest", Vector3.new(0.16, 1, 1.4), CFrame.new(0, 1.25, 0.15), glow, NEON)
			add("Head", "Visor", Vector3.new(1.05, 0.16, 0.1), CFrame.new(0, -0.15, -0.72), glow, NEON)
			add("Head", "Crown", Vector3.new(1.54, 0.16, 1.54), CFrame.new(0, 0.6, 0), trim)
		end
	elseif piece.Slot == "Chest" then
		add("Torso", "Plate", Vector3.new(2.2, 2.06, 1.24), CFrame.new(), main)
		add("Torso", "Belt", Vector3.new(2.26, 0.3, 1.3), CFrame.new(0, -0.85, 0), trim)
		for _, x in ipairs({ -1, 1 }) do
			add("Torso", "Shoulder", Vector3.new(1, 0.5, 1.34), CFrame.new(x * 1.42, 0.95, 0) * rad(0, 0, x * -12), trim)
		end
		if s.Kind == "Bone" then
			for i = 0, 2 do
				add("Torso", "Rib", Vector3.new(1.7 - i * 0.2, 0.14, 0.1), CFrame.new(0, 0.5 - i * 0.38, -0.66), trim)
			end
			add("Torso", "Spine", Vector3.new(0.2, 1.3, 0.1), CFrame.new(0, 0.1, -0.67), trim)
			for _, x in ipairs({ -1, 1 }) do
				add("Torso", "ShoulderSpike", Vector3.new(0.24, 0.6, 0.24), CFrame.new(x * 1.6, 1.4, 0) * rad(0, 0, x * -25), main)
			end
		elseif s.Kind == "Ice" then
			add("Torso", "Emblem", Vector3.new(0.7, 0.7, 0.1), CFrame.new(0, 0.25, -0.66) * rad(0, 0, 45), glow, NEON)
			for _, x in ipairs({ -1, 1 }) do
				add("Torso", "Shard", Vector3.new(0.3, 0.9, 0.3), CFrame.new(x * 1.55, 1.45, 0) * rad(0, 45, x * -22), trim, GLASS, 0.15)
				add("Torso", "Shard", Vector3.new(0.22, 0.6, 0.22), CFrame.new(x * 1.2, 1.35, 0.3) * rad(0, 45, x * -8), trim, GLASS, 0.15)
			end
		elseif s.Kind == "Lava" then
			add("Torso", "Core", Vector3.new(0.6, 0.6, 0.1), CFrame.new(0, 0.3, -0.66) * rad(0, 0, 45), glow, NEON)
			add("Torso", "Crack", Vector3.new(0.1, 0.9, 0.1), CFrame.new(-0.5, -0.1, -0.66) * rad(0, 0, 30), glow, NEON)
			add("Torso", "Crack", Vector3.new(0.1, 0.7, 0.1), CFrame.new(0.55, -0.25, -0.66) * rad(0, 0, -35), glow, NEON)
			for _, x in ipairs({ -1, 1 }) do
				add("Torso", "ShoulderHorn", Vector3.new(0.3, 0.8, 0.3), CFrame.new(x * 1.7, 1.4, 0) * rad(0, 0, x * -35), trim)
			end
		else -- Abyss
			add("Torso", "Emblem", Vector3.new(0.7, 0.7, 0.1), CFrame.new(0, 0.25, -0.66) * rad(0, 0, 45), glow, NEON)
			add("Torso", "Collar", Vector3.new(2, 0.4, 1.1), CFrame.new(0, 1.15, 0.1), trim)
			add("Torso", "Cape", Vector3.new(1.9, 2.9, 0.12), CFrame.new(0, -0.55, 0.78) * rad(-6, 0, 0), main, Enum.Material.Fabric)
			add("Torso", "CapeTrim", Vector3.new(1.9, 0.2, 0.14), CFrame.new(0, -1.9, 0.92) * rad(-6, 0, 0), glow, NEON)
		end
	else -- Legs
		for _, anchor in ipairs({ "LeftShin", "RightShin" }) do
			add(anchor, "Greave", Vector3.new(1.16, 1.06, 1.16), CFrame.new(0, -0.02, 0), main)
			add(anchor, "Knee", Vector3.new(0.76, 0.4, 0.3), CFrame.new(0, 0.5, -0.56), trim)
			add(anchor, "Toe", Vector3.new(1.16, 0.3, 0.4), CFrame.new(0, -0.42, -0.7), trim)
			if s.Kind == "Bone" then
				add(anchor, "KneeSpike", Vector3.new(0.2, 0.5, 0.2), CFrame.new(0, 0.7, -0.75) * rad(-40, 0, 0), main)
			elseif s.Kind == "Ice" then
				add(anchor, "KneeCrystal", Vector3.new(0.3, 0.6, 0.3), CFrame.new(0, 0.7, -0.7) * rad(-25, 45, 0), trim, GLASS, 0.15)
			elseif s.Kind == "Lava" then
				add(anchor, "Band", Vector3.new(1.2, 0.14, 1.2), CFrame.new(0, 0.1, 0), glow, NEON)
			else
				add(anchor, "Band", Vector3.new(1.2, 0.14, 1.2), CFrame.new(0, 0.3, 0), glow, NEON)
				add(anchor, "Fin", Vector3.new(0.12, 0.7, 0.5), CFrame.new(0, 0.1, 0.75), trim)
			end
		end
	end
	return list
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
	model.Parent = character
	return model
end

return ArmorBuilder
