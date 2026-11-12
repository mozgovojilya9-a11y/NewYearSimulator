--[[
	MaterialBuilder.luau
	Mini-models of crafting materials built from Parts (no assets), one
	builder per Config.Materials[i].Shape. Used for drops in the world
	(client), inventory / recipe cards (ViewportFrame) and the forge
	animation. Every model is ~2 studs big, centered on its invisible
	PrimaryPart "Root"; parts are anchored and never collide.
]]

local MaterialBuilder = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(20, 15, 30)

local function p(model, name, size, cf, color, material, transparency, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local BALL = Enum.PartType.Ball
local builders = {}

builders.Bone = function(m, c)
	local tilt = CFrame.Angles(0, 0, math.rad(35))
	p(m, "Shaft", Vector3.new(0.45, 1.9, 0.45), tilt, c)
	for _, y in ipairs({ -1, 1 }) do
		for _, x in ipairs({ -1, 1 }) do
			p(m, "Knob", Vector3.new(0.6, 0.6, 0.6), tilt * CFrame.new(x * 0.28, y * 1.05, 0), lighter(c, 0.3), nil, nil, BALL)
		end
	end
	p(m, "Crack", Vector3.new(0.47, 0.08, 0.47), tilt * CFrame.new(0, 0.2, 0), darker(c, 0.35))
end

builders.Blob = function(m, c)
	p(m, "Body", Vector3.new(1.9, 1.5, 1.9), CFrame.new(0, -0.1, 0), c, Enum.Material.Glass, 0.3, BALL)
	p(m, "Top", Vector3.new(1.1, 1, 1.1), CFrame.new(0.15, 0.55, 0), c, Enum.Material.Glass, 0.3, BALL)
	p(m, "Core", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, -0.1, 0), lighter(c, 0.5), Enum.Material.Neon, 0, BALL)
	p(m, "Drip", Vector3.new(0.5, 0.5, 0.5), CFrame.new(-0.9, -0.5, 0.4), c, Enum.Material.Glass, 0.3, BALL)
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Eye", Vector3.new(0.22, 0.32, 0.1), CFrame.new(x * 0.32, 0.1, -0.9), BLACK)
	end
end

builders.Ingot = function(m, c)
	p(m, "Base", Vector3.new(2, 0.6, 1), CFrame.new(0, -0.3, 0), c, Enum.Material.CorrodedMetal)
	p(m, "Top", Vector3.new(1.6, 0.5, 0.7), CFrame.new(0, 0.25, 0), lighter(c, 0.12), Enum.Material.CorrodedMetal)
	p(m, "Second", Vector3.new(1.7, 0.5, 0.8), CFrame.new(0.2, 0.75, 0.1) * CFrame.Angles(0, math.rad(28), 0), darker(c, 0.15), Enum.Material.CorrodedMetal)
	p(m, "Shine", Vector3.new(0.5, 0.08, 0.3), CFrame.new(-0.4, 0.52, -0.1), Color3.fromRGB(215, 215, 225), Enum.Material.Metal)
	p(m, "Rust", Vector3.new(0.5, 0.2, 1.02), CFrame.new(0.5, -0.3, 0), Color3.fromRGB(120, 60, 35), Enum.Material.CorrodedMetal)
end

builders.Skull = function(m, c)
	local bone = Color3.fromRGB(225, 220, 235)
	p(m, "Cranium", Vector3.new(1.6, 1.4, 1.5), CFrame.new(0, 0.3, 0), bone)
	p(m, "Jaw", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, -0.6, -0.1), darker(bone, 0.1))
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Socket", Vector3.new(0.45, 0.45, 0.12), CFrame.new(x * 0.4, 0.35, -0.75), BLACK)
		p(m, "Glow", Vector3.new(0.22, 0.22, 0.1), CFrame.new(x * 0.4, 0.35, -0.8), c, Enum.Material.Neon)
		p(m, "Horn", Vector3.new(0.3, 0.8, 0.3), CFrame.new(x * 0.85, 1.1, 0) * CFrame.Angles(0, 0, x * math.rad(-30)), c)
	end
	for i = -1, 1 do
		p(m, "Tooth", Vector3.new(0.22, 0.26, 0.1), CFrame.new(i * 0.3, -0.38, -0.66), WHITE)
	end
	p(m, "Rune", Vector3.new(0.3, 0.4, 0.08), CFrame.new(0, 0.85, -0.76) * CFrame.Angles(0, 0, math.rad(45)), c, Enum.Material.Neon)
end

builders.Heart = function(m, c)
	for _, x in ipairs({ -1, 1 }) do
		p(m, "Lobe", Vector3.new(1.15, 1.15, 1), CFrame.new(x * 0.45, 0.4, 0), c, nil, 0, BALL)
		p(m, "Vein", Vector3.new(0.12, 0.9, 0.12), CFrame.new(x * 0.5, 0, -0.45) * CFrame.Angles(0, 0, x * math.rad(25)), darker(c, 0.35))
	end
	p(m, "Body", Vector3.new(1.3, 1.3, 0.9), CFrame.new(0, -0.15, 0) * CFrame.Angles(0, 0, math.rad(45)), c)
	p(m, "Core", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.1, -0.35), lighter(c, 0.6), Enum.Material.Neon, 0, BALL)
	p(m, "Tube", Vector3.new(0.35, 0.6, 0.35), CFrame.new(0.2, 1.05, 0) * CFrame.Angles(0, 0, math.rad(-15)), darker(c, 0.25))
end

builders.Cube = function(m, c)
	p(m, "Ice", Vector3.new(1.6, 1.6, 1.6), CFrame.Angles(math.rad(12), math.rad(25), 0), c, Enum.Material.Glass, 0.25)
	p(m, "Inner", Vector3.new(0.8, 0.8, 0.8), CFrame.Angles(math.rad(12), math.rad(25), 0), lighter(c, 0.6), Enum.Material.Ice)
	p(m, "Chip", Vector3.new(0.6, 0.6, 0.6), CFrame.new(1, -0.5, 0.5) * CFrame.Angles(0.5, 0.8, 0.2), c, Enum.Material.Glass, 0.25)
	p(m, "Chip", Vector3.new(0.4, 0.4, 0.4), CFrame.new(-0.9, -0.6, -0.6) * CFrame.Angles(0.2, 0.3, 0.9), lighter(c, 0.3), Enum.Material.Ice)
	p(m, "Frost", Vector3.new(1.2, 0.1, 1.2), CFrame.new(0, 0.85, 0) * CFrame.Angles(math.rad(12), math.rad(25), 0), WHITE, Enum.Material.Ice)
end

builders.Fur = function(m, c)
	p(m, "Hide", Vector3.new(1.8, 0.35, 1.4), CFrame.new(0, -0.5, 0), darker(c, 0.3), Enum.Material.Fabric)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local lean = CFrame.Angles(math.sin(angle) * 0.4, 0, -math.cos(angle) * 0.4)
		p(m, "Tuft", Vector3.new(0.4, 1 + (i % 3) * 0.2, 0.4), CFrame.new(math.cos(angle) * 0.55, 0.1, math.sin(angle) * 0.42) * lean, if i % 2 == 0 then c else darker(c, 0.1), Enum.Material.Fabric)
	end
	p(m, "TuftTop", Vector3.new(0.5, 1.3, 0.5), CFrame.new(0, 0.3, 0), lighter(c, 0.4), Enum.Material.Fabric)
end

builders.Crystal = function(m, c)
	p(m, "Rock", Vector3.new(1.5, 0.5, 1.3), CFrame.new(0, -0.8, 0), Color3.fromRGB(70, 80, 105), Enum.Material.Slate)
	p(m, "Main", Vector3.new(0.7, 2, 0.7), CFrame.new(0, 0.15, 0) * CFrame.Angles(0, math.rad(45), 0), c, Enum.Material.Glass, 0.15)
	p(m, "MainCore", Vector3.new(0.25, 1.5, 0.25), CFrame.new(0, 0.15, 0) * CFrame.Angles(0, math.rad(45), 0), lighter(c, 0.6), Enum.Material.Neon)
	p(m, "Side", Vector3.new(0.5, 1.3, 0.5), CFrame.new(0.55, -0.2, 0.1) * CFrame.Angles(0, math.rad(20), math.rad(-28)), c, Enum.Material.Glass, 0.15)
	p(m, "Side", Vector3.new(0.45, 1.1, 0.45), CFrame.new(-0.5, -0.3, -0.15) * CFrame.Angles(0, math.rad(60), math.rad(30)), lighter(c, 0.2), Enum.Material.Glass, 0.15)
	p(m, "Small", Vector3.new(0.3, 0.7, 0.3), CFrame.new(0.1, -0.45, 0.55) * CFrame.Angles(math.rad(35), 0, 0), c, Enum.Material.Glass, 0.15)
end

builders.Star = function(m, c)
	p(m, "Core", Vector3.new(0.9, 0.9, 0.9), CFrame.new(), lighter(c, 0.5), Enum.Material.Neon, 0, BALL)
	for i = 0, 3 do
		p(m, "Ray", Vector3.new(0.5, 2.4, 0.5), CFrame.Angles(0, 0, i * math.pi / 4) * CFrame.Angles(0, math.rad(45), 0), c, Enum.Material.Glass, 0.2)
	end
	p(m, "RayDepth", Vector3.new(0.5, 0.5, 1.8), CFrame.Angles(0, 0, math.rad(45)), c, Enum.Material.Glass, 0.2)
	local ring = p(m, "Ring", Vector3.new(0.12, 2.6, 2.6), CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(20)), WHITE, Enum.Material.Glass, 0.6, Enum.PartType.Cylinder)
	ring.Name = "Halo"
end

builders.Shards = function(m, c)
	local angles = { { 0, 0, 0, 1.9 }, { 0.5, 0.3, 0.6, 1.3 }, { -0.5, 0.2, -0.5, 1.4 }, { 0.1, -0.5, 0.9, 0.9 }, { -0.2, 0.55, -0.9, 0.8 } }
	for i, a in ipairs(angles) do
		p(m, "Shard", Vector3.new(0.6 - i * 0.05, a[4], 0.5 - i * 0.04), CFrame.new(a[1], a[4] / 2 - 0.9, a[2]) * CFrame.Angles(a[2] * 0.6, i, a[3] * 0.5), if i % 2 == 0 then lighter(c, 0.15) else c, Enum.Material.Glass, 0.05)
	end
	p(m, "Glint", Vector3.new(0.15, 1.2, 0.15), CFrame.new(0.05, 0.1, -0.28), lighter(c, 0.7), Enum.Material.Neon)
end

builders.Coal = function(m, c)
	local coal = Color3.fromRGB(40, 34, 40)
	p(m, "Lump", Vector3.new(1.5, 1.1, 1.3), CFrame.Angles(0.2, 0.5, 0.1), coal, Enum.Material.Slate)
	p(m, "Lump2", Vector3.new(0.9, 0.8, 0.9), CFrame.new(0.7, -0.3, 0.4) * CFrame.Angles(0.6, 0.2, 0.4), coal, Enum.Material.Slate)
	p(m, "Lump3", Vector3.new(0.7, 0.6, 0.7), CFrame.new(-0.7, -0.4, -0.3) * CFrame.Angles(0.1, 0.9, 0.3), darker(coal, 0.2), Enum.Material.Slate)
	p(m, "Glow", Vector3.new(0.9, 0.12, 0.2), CFrame.new(0, 0.2, -0.62) * CFrame.Angles(0.2, 0.5, 0.4), c, Enum.Material.Neon)
	p(m, "Glow", Vector3.new(0.15, 0.7, 0.2), CFrame.new(0.35, 0, -0.55) * CFrame.Angles(0.2, 0.5, -0.3), c, Enum.Material.Neon)
	p(m, "Glow", Vector3.new(0.6, 0.12, 0.6), CFrame.new(-0.1, 0.58, 0) * CFrame.Angles(0.2, 0.5, 0.1), lighter(c, 0.3), Enum.Material.Neon)
end

builders.Core = function(m, c)
	p(m, "Core", Vector3.new(1.2, 1.2, 1.2), CFrame.new(), lighter(c, 0.3), Enum.Material.Neon, 0, BALL)
	local rock = Color3.fromRGB(60, 40, 40)
	local plates = { CFrame.new(0, 0.6, 0), CFrame.new(0, -0.6, 0), CFrame.new(0.6, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), CFrame.new(-0.6, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), CFrame.new(0, 0, 0.6) * CFrame.Angles(math.rad(90), 0, 0), CFrame.new(0, 0, -0.6) * CFrame.Angles(math.rad(90), 0, 0) }
	for i, cf in ipairs(plates) do
		p(m, "Plate", Vector3.new(0.9, 0.35, 0.9), cf * CFrame.Angles(0, i * 0.5, 0), rock, Enum.Material.Slate)
	end
	p(m, "Crack", Vector3.new(0.12, 0.4, 0.5), CFrame.new(0.25, 0.62, 0.1), c, Enum.Material.Neon)
end

builders.Feather = function(m, c)
	local tilt = CFrame.Angles(0, 0, math.rad(-25))
	p(m, "Quill", Vector3.new(0.12, 2.4, 0.12), tilt, Color3.fromRGB(255, 240, 200))
	for i = 0, 4 do
		local y = -0.5 + i * 0.4
		local w = 0.95 - math.abs(i - 2) * 0.22
		local color = c:Lerp(Color3.fromRGB(255, 60, 30), i / 5)
		for _, x in ipairs({ -1, 1 }) do
			p(m, "Vane", Vector3.new(w, 0.36, 0.08), tilt * CFrame.new(x * w / 2, y, 0) * CFrame.Angles(0, 0, x * math.rad(22)), color)
		end
	end
	p(m, "Tip", Vector3.new(0.3, 0.5, 0.1), tilt * CFrame.new(0, 1.35, 0), Color3.fromRGB(255, 235, 120), Enum.Material.Neon)
end

builders.Dust = function(m, c)
	p(m, "Pile", Vector3.new(1.8, 0.5, 1.6), CFrame.new(0, -0.6, 0), darker(c, 0.3), Enum.Material.Sand)
	p(m, "Heap", Vector3.new(1.1, 0.6, 1), CFrame.new(0, -0.2, 0), c, Enum.Material.Sand)
	p(m, "Peak", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.25, 0) * CFrame.Angles(0, math.rad(45), 0), lighter(c, 0.2), Enum.Material.Sand)
	for i = 1, 6 do
		local angle = i * 1.1
		p(m, "Mote", Vector3.new(0.18, 0.18, 0.18), CFrame.new(math.cos(angle) * (0.4 + i * 0.1), 0.3 + i * 0.22, math.sin(angle) * (0.4 + i * 0.08)) * CFrame.Angles(i, i, 0), lighter(c, 0.5), Enum.Material.Neon)
	end
end

builders.Vial = function(m, c)
	p(m, "Glass", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, -0.3, 0), Color3.fromRGB(220, 240, 255), Enum.Material.Glass, 0.55, BALL)
	p(m, "Liquid", Vector3.new(0.95, 0.95, 0.95), CFrame.new(0, -0.38, 0), c, Enum.Material.Neon, 0, BALL)
	p(m, "Neck", Vector3.new(0.5, 0.7, 0.5), CFrame.new(0, 0.55, 0), Color3.fromRGB(220, 240, 255), Enum.Material.Glass, 0.5)
	p(m, "Rim", Vector3.new(0.7, 0.14, 0.7), CFrame.new(0, 0.9, 0), Color3.fromRGB(255, 201, 60), Enum.Material.Metal)
	p(m, "Cork", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 1.1, 0), Color3.fromRGB(150, 105, 65), Enum.Material.Wood)
	p(m, "Label", Vector3.new(0.6, 0.4, 0.05), CFrame.new(0, -0.3, -0.66), Color3.fromRGB(250, 240, 215))
	p(m, "Bubble", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0.2, 0.05, -0.2), WHITE, Enum.Material.Neon, 0, BALL)
end

builders.Eye = function(m, c)
	p(m, "Ball", Vector3.new(1.6, 1.6, 1.6), CFrame.new(), Color3.fromRGB(245, 240, 250), nil, 0, BALL)
	p(m, "Iris", Vector3.new(0.9, 0.9, 0.3), CFrame.new(0, 0, -0.68), c, nil, 0, BALL)
	p(m, "Pupil", Vector3.new(0.3, 0.6, 0.2), CFrame.new(0, 0, -0.8), BLACK)
	p(m, "Shine", Vector3.new(0.2, 0.2, 0.1), CFrame.new(0.22, 0.24, -0.84), WHITE, Enum.Material.Neon)
	for i = 0, 3 do
		local angle = i * math.pi / 2 + 0.5
		p(m, "Vein", Vector3.new(0.08, 0.6, 0.08), CFrame.new(math.cos(angle) * 0.62, math.sin(angle) * 0.62, -0.42) * CFrame.Angles(0, 0, angle + math.pi / 2), Color3.fromRGB(220, 60, 90))
		p(m, "Tendril", Vector3.new(0.2, 0.9, 0.2), CFrame.new(math.cos(angle) * 0.4, math.sin(angle) * 0.4, 1) * CFrame.Angles(math.rad(70 + i * 12), 0, angle), darker(c, 0.4))
	end
end

-- Returns a Model named after the material, PrimaryPart "Root" (center).
function MaterialBuilder.Build(material): Model
	local model = Instance.new("Model")
	model.Name = material.Id
	local root = p(model, "Root", Vector3.new(0.4, 0.4, 0.4), CFrame.new(), WHITE, nil, 1)
	model.PrimaryPart = root
	local build = builders[material.Shape] or builders.Cube
	build(model, material.Color)
	return model
end

return MaterialBuilder
