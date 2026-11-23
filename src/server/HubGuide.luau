--[[
	HubGuide.luau
	Way-finding and the "life" of the hub (Config.HubLayout.Signs /
	Centers / Supply), built by HubGenerator after the halls:
	  * the atrium garden: trees, grass beds, benches (22.11: the colored
	    floor lines and sign posts are gone - less noise, less text);
	  * the central object of a hall (an AI model from GameAssets/Props,
	    procedural fallback) with its own colored light;
	  * the Терминал снабжения corner in the atrium (pulls: GachaService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)

local HubGuide = {}

local L = Config.HubLayout
local G = L.Signs
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local function colorOf(hall: string): Color3
	if hall == "Supply" then
		return Config.Crystals.Color
	end
	local theme = L.Themes[hall]
	return theme and theme.Accent or Config.Theme.Gold
end

-- A floor line along points (offsets from `base`) with chevrons.
local function path(parent, base: Vector3, points, color: Color3)
	local m = NanoKit.Model(parent, "Path")
	local y = base.Y + 0.06
	for i = 1, #points - 1 do
		local a = Vector3.new(base.X + points[i][1], y, base.Z + points[i][2])
		local b = Vector3.new(base.X + points[i + 1][1], y, base.Z + points[i + 1][2])
		local length = (b - a).Magnitude
		if length < 0.1 then
			continue
		end
		local cf = CFrame.lookAt((a + b) / 2, b)
		-- the line (+ a little overlap so corners are closed)
		Panel(m, "Line", Vector3.new(G.Width, 0.1, length + G.Width), cf, color:Lerp(Color3.new(0, 0, 0), 0.25), M.Smooth, { CanCollide = false, CastShadow = false })
		-- chevrons pointing along the way
		local dir = (b - a).Unit
		local n = math.floor(length / G.ChevronEvery)
		for k = 1, n do
			local p = a + dir * (k * G.ChevronEvery - G.ChevronEvery / 2)
			local look = CFrame.lookAt(p, p + dir)
			for _, side in ipairs({ -1, 1 }) do
				Panel(m, "Chevron", Vector3.new(0.3, 0.12, 1.5), look * CFrame.new(side * 0.42, 0.02, 0.1) * CFrame.Angles(0, math.rad(side * 40), 0), color, M.Neon, { CanCollide = false, CastShadow = false })
			end
		end
	end
	return m
end

local DIR = { N = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1), E = Vector3.new(1, 0, 0), W = Vector3.new(-1, 0, 0) }

-- A post with arrow plates (one per hall), names on both faces.
local function post(parent, base: Vector3, def)
	local m = NanoKit.Model(parent, "SignPost")
	local p = Vector3.new(base.X + def.At[1], base.Y, base.Z + def.At[2])
	local height = 5.5 + #def.Arrows * 1.9
	NanoKit.Column(m, "Pole", height, 0.5, p, Config.HubLayout.Colors.Steel, M.Metal)
	NanoKit.Column(m, "Foot", 0.5, 1.8, p, Config.HubLayout.Colors.Dado, M.Metal)
	for i, arrow in ipairs(def.Arrows) do
		local dir = DIR[arrow.Dir] or DIR.N
		local color = colorOf(arrow.To)
		local y = height - 1 - (i - 1) * 1.9
		local center = p + Vector3.new(0, y, 0) + dir * 3.3
		local cf = CFrame.lookAt(center, center + dir) * CFrame.Angles(0, math.rad(90), 0) -- plate faces sideways, long axis along dir
		local plate = Panel(m, "Arrow", Vector3.new(6, 1.4, 0.24), cf, Color3.fromRGB(16, 18, 22), M.Smooth, { CanCollide = false })
		Panel(m, "Stripe", Vector3.new(6, 0.14, 0.28), cf * CFrame.new(0, -0.62, 0), color, M.Neon, { CanCollide = false, CastShadow = false })
		-- the tip: a diamond at the far end in the hall color
		Panel(m, "Tip", Vector3.new(1.05, 1.05, 0.26), cf * CFrame.new(3.05, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), color, M.Smooth, { CanCollide = false })
		local name = G.Names[arrow.To] or arrow.To
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			WorldKit.SurfaceText(plate, face, { { Text = name, Size = 64, Color = color } }, 60)
		end
	end
	return m
end

-- The central object of a hall with its own light.
local function center(parent, base: Vector3, def)
	local p = Vector3.new(base.X + def.At[1], base.Y, base.Z + def.At[2])
	if def.Hologram then
		return require(script.Parent.HubIsland).Hologram(parent, p) -- the atrium's hologram cube
	end
	local cf = CFrame.new(p)
	local prop = NanoKit.Prop(parent, def.Model, cf, def.Height, nil)
	if not prop then
		return nil
	end
	prop.Name = "Center_" .. def.Hall
	for _, d in ipairs(prop:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = not def.Flat
			d.CastShadow = not def.Flat
		end
	end
	-- own light, from a small invisible bulb above it
	local bulb = Panel(parent, "CenterLight_" .. def.Hall, Vector3.new(0.4, 0.4, 0.4), CFrame.new(p + Vector3.new(0, (def.Height or 6) + 3, 0)), def.Light, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local light = Instance.new("PointLight")
	light.Color = def.Light
	light.Range = 26
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = bulb
	-- a slow floating glow ring at its foot
	local ring = NanoKit.Cylinder(parent, "CenterRing_" .. def.Hall, 0.12, 9, CFrame.new(p + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), def.Light, M.Neon)
	ring.CanCollide = false
	ring.Transparency = 0.55
	NanoKit.Tag(ring, "Pulse", { Period = 2.6 })
	return prop
end

-- Терминал снабжения: the capsule machine on a dais, a hologram sign,
-- a light; returns the part that carries the prompt.
local function supply(parent, base: Vector3)
	local S = L.Supply
	local m = NanoKit.Model(parent, "SupplyTerminal")
	local p = Vector3.new(base.X + S.At[1], base.Y, base.Z + S.At[2])
	local face = Vector3.new(base.X + S.Face[1], base.Y, base.Z + S.Face[2])
	local cf = CFrame.lookAt(p, face)
	local color = Config.Crystals.Color
	NanoKit.Column(m, "Dais", 0.6, 12, p, Config.HubLayout.Colors.Dado, M.Plate)
	local edge = NanoKit.Column(m, "DaisEdge", 0.12, 12.4, p + Vector3.new(0, 0.3, 0), color, M.Neon)
	edge.Transparency = 0.4
	local machine = NanoKit.Prop(m, S.Model, cf * CFrame.new(0, 0.6, 0), S.Height, function(par, c)
		local mm = NanoKit.Model(par, "CapsuleMachine")
		Panel(mm, "Body", Vector3.new(5, 5, 4), c * CFrame.new(0, 2.5, 0), Color3.fromRGB(34, 34, 40), M.Metal)
		local dome = Panel(mm, "Dome", Vector3.new(4.4, 4.4, 4.4), c * CFrame.new(0, 6.6, 0), color, M.Glass, { Shape = Enum.PartType.Ball, Transparency = 0.45 })
		local _ = dome
		Panel(mm, "Trim", Vector3.new(5.2, 0.3, 4.2), c * CFrame.new(0, 5.05, 0), Config.Theme.Gold, M.Metal)
		return mm
	end)
	local box = machine and select(2, machine:GetBoundingBox()) or Vector3.new(5, 9, 4)
	-- the sign above
	local sign = Panel(m, "Sign", Vector3.new(9, 2.2, 0.25), cf * CFrame.new(0, 0.6 + box.Y + 2, 0), Color3.fromRGB(14, 14, 18), M.Smooth, { CanCollide = false })
	WorldKit.SurfaceText(sign, Enum.NormalId.Front, { { Text = "ТЕРМИНАЛ СНАБЖЕНИЯ", Size = 52, Color = Config.Theme.Gold }, { Text = "Крутки за Кристаллы", Size = 30, Color = color } }, 60)
	WorldKit.SurfaceText(sign, Enum.NormalId.Back, { { Text = "ТЕРМИНАЛ СНАБЖЕНИЯ", Size = 52, Color = Config.Theme.Gold } }, 60)
	local bulb = Panel(m, "Light", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, box.Y + 4, -3), color, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 1.8
	light.Parent = bulb
	-- the press point in front of the machine
	local anchor = Panel(m, "PromptAnchor", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3.5, -3.5), color, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	local prompt = WorldKit.Prompt(anchor, L.Prompts.Supply, "", { Action = "OpenSupply" })
	return m, prompt
end

-- Display capsules along the Supply hall wall (sheet 01): glass tubes
-- lit in a rarity color, a spinning weapon of that rarity inside.
local function capsules(parent, base: Vector3)
	local CP = L.Capsules
	local m = NanoKit.Model(parent, "Capsules")
	local classes = { "Blade", "Pulse", "Gunner" }
	for i, rarityId in ipairs(CP.Rarities) do
		local rarity = Config.Rarity[rarityId]
		local p = base + CP.From + CP.Step * (i - 1)
		local color = rarity and rarity.Color or Config.Theme.Cyan
		NanoKit.Column(m, "CapsuleBase", 1.2, CP.Diameter + 1, p, Color3.fromRGB(46, 46, 52), M.Metal)
		local ring = NanoKit.Column(m, "CapsuleRing", 0.2, CP.Diameter + 0.4, p + Vector3.new(0, 1.15, 0), color, M.Neon)
		ring.CanCollide = false
		local glass = NanoKit.Column(m, "CapsuleGlass", CP.Height, CP.Diameter, p + Vector3.new(0, 1.2, 0), color:Lerp(Color3.new(1, 1, 1), 0.55), M.Glass)
		glass.Transparency = 0.8
		NanoKit.Column(m, "CapsuleCap", 0.8, CP.Diameter + 0.6, p + Vector3.new(0, 1.2 + CP.Height, 0), Color3.fromRGB(46, 46, 52), M.Metal)
		local top = NanoKit.Column(m, "CapsuleTopLight", 0.15, CP.Diameter - 0.4, p + Vector3.new(0, 1.15 + CP.Height, 0), color, M.Neon)
		top.CanCollide = false
		WorldKit.Light(top, color, 12, 1.2)
		local look = table.clone(Config.Weapons[1])
		look.Class = classes[(i - 1) % #classes + 1]
		look.Rarity = rarityId
		local ok, model = pcall(WeaponBuilder.Build, look)
		if ok and model then
			WeaponBuilder.SetAnchored(model, true)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			local size = model:GetExtentsSize()
			pcall(model.ScaleTo, model, math.clamp(CP.ItemSize / math.max(size.X, size.Y, size.Z, 0.1), 0.3, 4))
			local center = p + Vector3.new(0, 1.2 + CP.Height / 2, 0)
			model:PivotTo(CFrame.new(model:GetPivot().Position) * CFrame.Angles(0, 0, math.rad(70)))
			local box = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + (center - box.Position))
			model.WorldPivot = CFrame.new(center) * model:GetPivot().Rotation
			model.Parent = m
			NanoKit.Tag(model, "Spin", { Speed = 24, Axis = "Y" })
		end
	end
	return m
end

-- The atrium garden (22.11, instead of the colored floor lines and the
-- sign posts): trees in planters (GameAssets/Props/Prop_Tree, else the
-- glass plant capsule), grass beds with a stone rim, benches facing the
-- middle (Config.HubLayout.Garden).
local function garden(parent, base: Vector3)
	local GD = L.Garden
	local m = NanoKit.Model(parent, "Garden")
	for i, t in ipairs(GD.Trees) do
		local p = base + Vector3.new(t[1], 0, t[2])
		NanoKit.Prop(m, GD.Models[(i - 1) % #GD.Models + 1], CFrame.new(p) * CFrame.Angles(0, math.rad((t[1] * 7 + t[2] * 3) % 360), 0), GD.TreeHeight, function(pp, cf)
			return NanoKit.PlantCapsule(pp, cf.Position, 1.6)
		end)
	end
	for _, b in ipairs(GD.Beds) do
		local p = base + Vector3.new(b[1], 0, b[2])
		local size = Vector3.new(b[3], 0.6, b[4])
		Panel(m, "BedRim", size + Vector3.new(1.2, 0, 1.2), CFrame.new(p + Vector3.new(0, 0.3, 0)), Color3.fromRGB(96, 94, 92), M.Concrete)
		Panel(m, "Grass", size + Vector3.new(0, 0.1, 0), CFrame.new(p + Vector3.new(0, 0.36, 0)), Color3.fromRGB(74, 120, 62), Enum.Material.Grass)
		for k = -1, 1, 2 do
			NanoKit.PlantCapsule(m, p + Vector3.new(k * b[3] * 0.3, 0.6, 0), 0.8)
		end
	end
	for _, b in ipairs(GD.Benches) do
		local p = base + Vector3.new(b[1], 0, b[2])
		NanoKit.Bench(m, CFrame.lookAt(p, base + Vector3.new(b[3], 0, b[4])))
	end
	return m
end

function HubGuide.Build(root, base: Vector3)
	local folder = NanoKit.Model(root, "Guide")
	garden(folder, base)
	capsules(folder, base)
	for _, def in ipairs(L.Centers) do
		center(folder, base, def)
	end
	local terminal, prompt = supply(root, base)
	return { Folder = folder, Supply = terminal, SupplyPrompt = prompt }
end

return HubGuide
