--[[
	HubIsland.luau
	The sky around the hub (concept sheet 01_hub_map.png, Config.HubIsland):
	the place's grey Baseplate is removed, rock layers narrow downwards
	under the island into a point with a few glowing crystals, distant
	small islands with towers, a sea of clouds far below; plus the
	atrium's hologram cube. HubCitadel builds the island itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

local HubIsland = {}

local I = Config.HubIsland
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local ROCK = Enum.Material.Slate

-- One rock chunk (a rotated block, slightly random).
local function rock(parent, rng: Random, center: Vector3, size: Vector3, color: Color3)
	local cf = CFrame.new(center) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.25, 0.25))
	return Panel(parent, "Rock", size, cf, color, ROCK, { CastShadow = false })
end

-- The underside: layers of rock chunks on an ellipse that shrinks with
-- depth, ending in a point (rx / rz = ellipse radii at the top).
local function underside(parent, rng: Random, top: Vector3, rx: number, rz: number, depth: number, color: Color3, layers: number)
	for k = 1, layers do
		local t = k / layers
		local s = (1 - t) ^ 0.55
		local y = top.Y - depth * t
		local count = math.max(3, math.floor(18 * s + 2))
		local chunk = math.max(10, (rx + rz) * 0.22 * s)
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local p = Vector3.new(top.X + math.cos(a) * rx * s * 0.82, y, top.Z + math.sin(a) * rz * s * 0.82)
			rock(parent, rng, p, Vector3.new(chunk * rng:NextNumber(0.8, 1.3), depth / layers * 1.6, chunk * rng:NextNumber(0.8, 1.3)), color)
		end
		-- the core of the layer
		rock(parent, rng, Vector3.new(top.X, y, top.Z), Vector3.new(rx * s * 1.5, depth / layers * 1.8, rz * s * 1.5), color)
	end
end

-- A distant floating island with a few towers (scenery only).
local function farIsland(parent, rng: Random, def)
	local m = NanoKit.Model(parent, "FarIsland")
	local p = def.At
	local r = def.Radius
	Panel(m, "Top", Vector3.new(r * 2, 4, r * 1.6), CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), I.RimColor, M.Concrete, { CastShadow = false })
	underside(m, rng, p - Vector3.new(0, 2, 0), r, r * 0.8, r * 1.6, I.RockColor, 4)
	for i = 1, def.Towers do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, r * 0.55)
		local h = rng:NextNumber(r * 0.8, r * 2.2)
		local w = rng:NextNumber(r * 0.18, r * 0.32)
		local base = p + Vector3.new(math.cos(a) * d, 2, math.sin(a) * d)
		Panel(m, "Tower", Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, h / 2, 0)), I.TowerColor, M.Metal, { CastShadow = false })
		Panel(m, "TowerCap", Vector3.new(w * 0.6, h * 0.15, w * 0.6), CFrame.new(base + Vector3.new(0, h + h * 0.075, 0)), I.TowerColor, M.Metal, { CastShadow = false })
		-- warm window bands
		for b = 1, 3 do
			Panel(m, "Windows", Vector3.new(w + 0.1, 0.5, w + 0.1), CFrame.new(base + Vector3.new(0, h * b / 4, 0)), I.Warm, M.Neon, { CanCollide = false, CastShadow = false })
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	return m
end

-- The atrium's centre: a hologram cube (wire edges, glass core) spinning
-- over a stepped pedestal with two tilted rings (Config.HubIsland.Hologram).
function HubIsland.Hologram(parent, p: Vector3)
	local H = I.Hologram
	local m = NanoKit.Model(parent, "Hologram")
	NanoKit.Column(m, "Step1", 0.8, H.Base + 4, p, I.RimColor, M.Metal)
	NanoKit.Column(m, "Step2", 0.8, H.Base + 1.5, p + Vector3.new(0, 0.8, 0), Color3.fromRGB(58, 58, 64), M.Metal)
	NanoKit.Column(m, "GoldRim", 0.25, H.Base + 1.7, p + Vector3.new(0, 1.5, 0), I.Gold, M.Metal)
	local lens = NanoKit.Column(m, "Lens", 0.2, H.Base - 1, p + Vector3.new(0, 1.62, 0), H.Color, M.Neon)
	lens.CanCollide = false
	local c = p + Vector3.new(0, H.Height, 0)
	local cube = Panel(m, "Cube", Vector3.new(H.Size, H.Size, H.Size), CFrame.new(c) * CFrame.Angles(math.rad(35), math.rad(45), 0), H.Color, M.Glass, { Transparency = 0.82, CanCollide = false, CastShadow = false })
	local edges = Instance.new("SelectionBox")
	edges.Adornee = cube
	edges.Color3 = H.Color
	edges.LineThickness = 0.12
	edges.SurfaceColor3 = H.Color
	edges.SurfaceTransparency = 0.9
	edges.Parent = cube
	NanoKit.Tag(cube, "Spin", { Speed = 25, Axis = "Y" })
	local core = Panel(m, "Core", Vector3.new(H.Size * 0.4, H.Size * 0.4, H.Size * 0.4), CFrame.new(c), Color3.new(1, 1, 1), M.Neon, { Transparency = 0.35, CanCollide = false, CastShadow = false })
	NanoKit.Tag(core, "Spin", { Speed = -40, Axis = "Y" })
	NanoKit.Tag(core, "Pulse", { Period = 2.4 })
	-- two thin tilted orbit rings (segment by segment: a hollow ring)
	for i, tilt in ipairs({ 14, -10 }) do
		local r = H.Size * (0.85 + i * 0.15)
		local ringCf = CFrame.new(c - Vector3.new(0, H.Size * 0.25 * i, 0)) * CFrame.Angles(math.rad(tilt), 0, 0)
		local n = 28
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * math.pi * 2
			Panel(m, "Orbit", Vector3.new(0.18, 0.18, r * math.pi * 2 / n + 0.1), ringCf * CFrame.Angles(0, a, 0) * CFrame.new(r, 0, 0), H.Color, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.2 })
		end
	end
	-- a light column from the lens
	local beam = NanoKit.Column(m, "Beam", H.Height - 1, H.Base - 2, p + Vector3.new(0, 1.7, 0), H.Color, M.Neon)
	beam.Transparency = 0.88
	beam.CanCollide = false
	WorldKit.Light(core, H.Color, 30, 1.4)
	return m
end

-- Rock under the island (centre `center`, radius `radius`, its plinth
-- `depth` deep), crystals, far islands and the clouds.
function HubIsland.Scenery(root, center: Vector3, radius: number, depth: number)
	local rng = Random.new(I.Seed)
	local folder = NanoKit.Model(root, "Sky")
	local plate = Workspace:FindFirstChild("Baseplate")
	if plate and plate:IsA("BasePart") then
		plate:Destroy() -- the hub floats
	end
	local top = center - Vector3.new(0, depth, 0)
	underside(folder, rng, top, radius * 0.92, radius * 0.92, I.RockDepth, I.RockColor, I.RockLayers)
	for _ = 1, I.Crystals do
		local a = rng:NextNumber(0, math.pi * 2)
		local t = rng:NextNumber(0.15, 0.6)
		local s = (1 - t) ^ 0.8
		local p = top + Vector3.new(math.cos(a) * radius * s * 0.85, -I.RockDepth * t, math.sin(a) * radius * s * 0.85)
		Panel(folder, "Crystal", Vector3.new(3, rng:NextNumber(8, 16), 3), CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), a, math.rad(150 + rng:NextNumber(-20, 20))), I.CrystalColor, M.Neon, { CanCollide = false, Transparency = 0.15 })
	end
	for _, def in ipairs(I.FarIslands) do
		farIsland(folder, rng, { At = center + def[1], Radius = def[2], Towers = def[3] })
	end
	for _, c in ipairs(I.CloudSea) do
		Panel(folder, "CloudSea", Vector3.new(4000, 2, 4000), CFrame.new(center + Vector3.new(0, c[1], 0)), I.CloudColor, M.Smooth, { Transparency = c[2], CanCollide = false, CanQuery = false, CastShadow = false })
	end
	return folder
end

return HubIsland
