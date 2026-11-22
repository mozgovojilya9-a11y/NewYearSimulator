--[[
	HubIsland.luau
	The hub as a floating island (concept sheet 01_hub_map.png,
	Config.HubIsland):
	  * the place's grey Baseplate is removed - the hub hangs in the sky;
	  * a thick metal rim slab under the halls with warm light strips and
	    lamps on its edge, then layers of rock narrowing downwards into a
	    point, with a few glowing crystals;
	  * distant small islands with towers around (scenery, far away);
	  * banners with the golden crest on poles in the atrium;
	  * invisible walls around the island edge (nobody falls off; Bounds
	    is the last line of defence).
	HubIsland.Build(root, base) is called by HubGenerator after the halls.
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

-- A banner on a pole with the golden crest (wings + diamond), both sides.
local function banner(parent, cf: CFrame)
	local B = I.Banner
	local m = NanoKit.Model(parent, "Banner")
	NanoKit.Column(m, "PoleFoot", 0.8, 2.4, cf.Position, I.RimColor, M.Metal)
	NanoKit.Column(m, "Pole", B.Height, 0.5, cf.Position, Color3.fromRGB(46, 46, 52), M.Metal)
	local top = cf * CFrame.new(0, B.Height - 0.6, 0)
	Panel(m, "Bar", Vector3.new(B.Width + 1.4, 0.4, 0.4), top, I.Gold, M.Metal)
	local cloth = top * CFrame.new(0, -B.Length / 2 - 0.2, 0)
	Panel(m, "Cloth", Vector3.new(B.Width, B.Length, 0.15), cloth, B.Cloth, Enum.Material.Fabric, { CanCollide = false })
	for _, y in ipairs({ B.Length / 2 - 0.3, -B.Length / 2 + 0.3 }) do
		Panel(m, "Trim", Vector3.new(B.Width, 0.25, 0.22), cloth * CFrame.new(0, y, 0), I.Gold, M.Metal, { CanCollide = false })
	end
	-- the crest: two wings (tilted bars) and a diamond, on both faces
	for _, z in ipairs({ -0.12, 0.12 }) do
		local face = cloth * CFrame.new(0, B.Length * 0.08, z)
		for _, side in ipairs({ -1, 1 }) do
			for k = 0, 2 do
				Panel(m, "Wing", Vector3.new(B.Width * (0.32 - k * 0.07), 0.22, 0.06), face * CFrame.new(side * B.Width * 0.2, 0.4 - k * 0.45, 0) * CFrame.Angles(0, 0, math.rad(side * (28 - k * 6))), I.Gold, M.Metal, { CanCollide = false })
			end
		end
		Panel(m, "Diamond", Vector3.new(0.8, 0.8, 0.06), face * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(45)), I.Gold, M.Neon, { CanCollide = false })
		Panel(m, "Blade", Vector3.new(0.18, 2.2, 0.06), face * CFrame.new(0, -0.6, 0), I.Gold, M.Metal, { CanCollide = false })
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

function HubIsland.Build(root, base: Vector3)
	local rng = Random.new(I.Seed)
	local folder = NanoKit.Model(root, "Island")
	-- 1. no grey floor: the hub floats
	local plate = Workspace:FindFirstChild("Baseplate")
	if plate and plate:IsA("BasePart") then
		plate:Destroy()
	end
	-- 2. the rim slab and the rock under it
	local f = I.Footprint -- { x0, x1, z0, z1 } offsets from the base
	local cx, cz = (f[1] + f[2]) / 2, (f[3] + f[4]) / 2
	local w, d = f[2] - f[1], f[3] - f[4]
	local top = base + Vector3.new(cx, -2, cz)
	Panel(folder, "RimSlab", Vector3.new(w + I.Margin * 2, I.SlabDepth, d + I.Margin * 2), CFrame.new(top - Vector3.new(0, I.SlabDepth / 2, 0)), I.RimColor, M.Metal)
	-- the old dark foundation becomes the island's deck (warm stone)
	local foundation = root:FindFirstChild("Foundation")
	if foundation and foundation:IsA("BasePart") then
		foundation.Size = Vector3.new(w + I.Margin * 2, 1, d + I.Margin * 2)
		foundation.CFrame = CFrame.new(Vector3.new(top.X, foundation.Position.Y, top.Z))
		foundation.Color = I.DeckColor
		foundation.Material = M.Concrete
	end
	-- terraces between the halls: sakura planters, lamps and benches on a
	-- loose grid, never inside a hall
	local function inHall(x: number, z: number): boolean
		for _, hall in pairs(Config.HubLayout.Halls) do
			local r = hall.Rect
			if x > r[1] - 6 and x < r[2] + 6 and z < r[3] + 6 and z > r[4] - 6 then
				return true
			end
		end
		return false
	end
	local k = 0
	for x = f[1] - I.Margin + 8, f[2] + I.Margin - 8, I.TerraceStep do
		for z = f[4] - I.Margin + 8, f[3] + I.Margin - 8, I.TerraceStep do
			if not inHall(x, z) then
				k += 1
				local p = base + Vector3.new(x, -0.6, z)
				if k % 3 == 0 then
					-- a warm lamp post (the owner's lamp glows blue)
					NanoKit.Column(folder, "LampFoot", 0.8, 1.6, p, I.RimColor, M.Metal)
					NanoKit.Column(folder, "LampPost", 8, 0.45, p, Color3.fromRGB(46, 46, 52), M.Metal)
					local head = Panel(folder, "LampHead", Vector3.new(1.6, 0.6, 1.6), CFrame.new(p + Vector3.new(0, 8.3, 0)), I.Gold, M.Metal)
					local bulb = Panel(folder, "LampBulb", Vector3.new(1.2, 0.2, 1.2), CFrame.new(p + Vector3.new(0, 7.95, 0)), I.Warm, M.Neon, { CanCollide = false })
					WorldKit.Light(bulb, I.Warm, 18, 1.2)
					local _ = head
				elseif k % 3 == 1 then
					NanoKit.Prop(folder, "Prop_Sakura", CFrame.new(p) * CFrame.Angles(0, k, 0), 10, function(pp, c)
						return NanoKit.PlantCapsule(pp, c.Position, 1.4)
					end)
				else
					NanoKit.Bench(folder, CFrame.new(p) * CFrame.Angles(0, (k % 4) * math.pi / 2, 0))
				end
			end
		end
	end
	-- warm light strips along the slab sides and lamps under the edge
	local hx, hz = (w + I.Margin * 2) / 2, (d + I.Margin * 2) / 2
	local corners = { Vector3.new(-hx, 0, -hz), Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz) }
	for i = 1, 4 do
		local a, b = top + corners[i], top + corners[i % 4 + 1]
		for _, y in ipairs({ -1.2, -I.SlabDepth + 1.5 }) do
			NanoKit.Strip(folder, a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), I.Warm, 0.5)
		end
		local length = (b - a).Magnitude
		local n = math.floor(length / I.LampEvery)
		for k = 1, n do
			local p = a:Lerp(b, k / (n + 1)) + Vector3.new(0, -I.SlabDepth - 0.5, 0)
			local lamp = Panel(folder, "UnderLamp", Vector3.new(2, 0.6, 2), CFrame.new(p), I.Warm, M.Neon, { CanCollide = false })
			if k % 2 == 0 then
				WorldKit.Light(lamp, I.Warm, 40, 1)
			end
		end
	end
	underside(folder, rng, top - Vector3.new(0, I.SlabDepth, 0), w * 0.5, d * 0.5, I.RockDepth, I.RockColor, I.RockLayers)
	-- glowing crystals sticking out of the rock
	for _ = 1, I.Crystals do
		local a = rng:NextNumber(0, math.pi * 2)
		local t = rng:NextNumber(0.15, 0.6)
		local s = (1 - t) ^ 0.8
		local p = top + Vector3.new(math.cos(a) * w * 0.5 * s * 0.9, -I.SlabDepth - I.RockDepth * t, math.sin(a) * d * 0.5 * s * 0.9)
		local crystal = Panel(folder, "Crystal", Vector3.new(3, rng:NextNumber(8, 16), 3), CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), a, math.rad(150 + rng:NextNumber(-20, 20))), I.CrystalColor, M.Neon, { CanCollide = false, Transparency = 0.15 })
		local _ = crystal
	end
	-- 3. distant islands
	for _, def in ipairs(I.FarIslands) do
		farIsland(folder, rng, { At = base + def[1], Radius = def[2], Towers = def[3] })
	end
	-- a sea of clouds far below
	for i, c in ipairs(I.CloudSea) do
		Panel(folder, "CloudSea", Vector3.new(4000, 2, 4000), CFrame.new(base + Vector3.new(0, c[1], 0)), I.CloudColor, M.Smooth, { Transparency = c[2], CanCollide = false, CanQuery = false, CastShadow = false })
		local _ = i
	end
	-- 4. banners with the crest
	for _, b in ipairs(I.Banners) do
		local p = base + Vector3.new(b[1], 0, b[2])
		banner(folder, CFrame.lookAt(p, base + Vector3.new(b[3], 0, b[4])))
	end
	-- facades: pilasters with warm light lines, a golden cornice and a
	-- light band under it on every outer wall of every hall
	local function insideHall(x: number, z: number): boolean
		for _, hall in pairs(Config.HubLayout.Halls) do
			local r = hall.Rect
			if x > r[1] and x < r[2] and z < r[3] and z > r[4] then
				return true
			end
		end
		return false
	end
	local F = I.Facade
	for _, hall in pairs(Config.HubLayout.Halls) do
		local r, H = hall.Rect, hall.Height
		local sides = {
			{ Vector3.new(r[1], 0, r[3]), Vector3.new(r[2], 0, r[3]), Vector3.new(0, 0, 1) },
			{ Vector3.new(r[1], 0, r[4]), Vector3.new(r[2], 0, r[4]), Vector3.new(0, 0, -1) },
			{ Vector3.new(r[1], 0, r[3]), Vector3.new(r[1], 0, r[4]), Vector3.new(-1, 0, 0) },
			{ Vector3.new(r[2], 0, r[3]), Vector3.new(r[2], 0, r[4]), Vector3.new(1, 0, 0) },
		}
		for _, side in ipairs(sides) do
			local a, b, n = side[1], side[2], side[3]
			local length = (b - a).Magnitude
			local along = (b - a).Unit
			local steps = math.max(1, math.floor(length / F.Step))
			for i = 0, steps do
				local q = a + along * (length * i / steps)
				local out = q + n * 6
				if not insideHall(out.X, out.Z) then
					local wp = base + q + n * (F.Out)
					local look = CFrame.lookAt(wp, wp + n)
					Panel(folder, "Pilaster", Vector3.new(F.Width, H + 1, 1.6), look * CFrame.new(0, (H + 1) / 2, 0), I.RimColor, M.Metal, { CastShadow = false })
					Panel(folder, "PilasterLight", Vector3.new(0.35, H * 0.6, 0.2), look * CFrame.new(0, H * 0.45, -0.9), I.Warm, M.Neon, { CanCollide = false, CastShadow = false })
					if i < steps then
						local q2 = a + along * (length * (i + 0.5) / steps)
						local cp = base + q2 + n * F.Out
						local ccf = CFrame.lookAt(cp, cp + n)
						local seg = length / steps + 0.2
						Panel(folder, "Cornice", Vector3.new(seg, 1.6, 2.6), ccf * CFrame.new(0, H + 0.4, 0), I.Gold, M.Metal, { CastShadow = false })
						Panel(folder, "CorniceLight", Vector3.new(seg, 0.3, 0.2), ccf * CFrame.new(0, H - 1, -0.9), I.Warm, M.Neon, { CanCollide = false, CastShadow = false })
					end
				end
			end
		end
	end
	-- the light bridge to the AFK island
	local AB = I.AfkBridge
	local from = base + AB.From
	local o = Config.AFK.Origin
	local dir = Vector3.new(from.X - o.X, 0, from.Z - o.Z).Unit
	local to = Vector3.new(o.X, from.Y, o.Z) + dir * (Config.AFK.Radius - 2)
	local length = (to - from).Magnitude
	local bcf = CFrame.lookAt((from + to) / 2, to)
	Panel(folder, "BridgeGlass", Vector3.new(AB.Width, 0.3, length), bcf, AB.Color, M.Glass, { Transparency = 0.7, CanCollide = false, CastShadow = false })
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Strip(folder, (bcf * CFrame.new(side * AB.Width / 2, 0.2, -length / 2)).Position, (bcf * CFrame.new(side * AB.Width / 2, 0.2, length / 2)).Position, AB.Color, 0.3)
	end
	local count = math.floor(length / 8)
	for k = 1, count do
		local p = (bcf * CFrame.new(0, 0.25, -length / 2 + k * length / (count + 1))).Position
		local chevron = Panel(folder, "BridgeChevron", Vector3.new(AB.Width * 0.5, 0.1, 0.5), CFrame.lookAt(p, p + bcf.LookVector), AB.Color, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.3 })
		NanoKit.Tag(chevron, "Pulse", { Period = 1.6 + (k % 3) * 0.2 })
	end
	-- 5. nobody walks off the edge
	for i = 1, 4 do
		local a, b = top + corners[i], top + corners[i % 4 + 1]
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		WorldKit.Invisible(folder, Vector3.new(if i % 2 == 1 then length else 2, 120, if i % 2 == 1 then 2 else length), mid + Vector3.new(0, 60, 0), "EdgeWall")
	end
	return folder
end

return HubIsland
