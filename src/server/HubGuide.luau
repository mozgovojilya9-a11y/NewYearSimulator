--[[
	HubGuide.luau
	Way-finding and the "life" of the hub (Config.HubLayout.Signs /
	Centers / Supply), built by HubGenerator after the halls:
	  * colored lines on the floor from the spawn arch to every hall, in
	    the hall's Accent color (docs/design/hub_plan.png), with chevrons
	    pointing the way;
	  * sign posts with arrow plates at the forks (hall names);
	  * the central object of a hall (an AI model from GameAssets/Props,
	    procedural fallback) with its own colored light;
	  * the Терминал снабжения corner in the atrium (pulls: GachaService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

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

function HubGuide.Build(root, base: Vector3)
	local folder = NanoKit.Model(root, "Guide")
	for _, def in ipairs(G.Paths) do
		path(folder, base, def.Points, colorOf(def.To))
	end
	for _, def in ipairs(G.Posts) do
		post(folder, base, def)
	end
	for _, def in ipairs(L.Centers) do
		center(folder, base, def)
	end
	local terminal, prompt = supply(root, base)
	return { Folder = folder, Supply = terminal, SupplyPrompt = prompt }
end

return HubGuide
