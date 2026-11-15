--[[
	HubGenerator.luau
	Builds the hub "Атриум Нано-Цитадели" at server start (Workspace.Hub):
	one closed hall (Config.HubLayout.Hall) instead of an open plaza.

	  Hall      walls (dado, panels, cornice with a cable tray, upper band
	            with vents), metal pilasters every Bay studs (thin light
	            strip, knee braces, warm bracket lamps), steel trusses
	            under the ceiling, a glass skylight between them (the only
	            sky), pendant lamps, dark concrete floor with metal borders
	            and painted markings.
	  Gates     the far (north) wall: massive frame, energy curtains,
	            a big sign above (touching the field starts a run).
	  Arches    doors in the side walls with a hanging sign on cables;
	            behind each a compact room that keeps a station working
	            (Forge, Egg, Polygon, Store; their full halls come later).
	  Bays      the other wall bays: leaderboards, the wheel and decor
	            sets (benches, consoles, racks, cargo, pipes) - dense along
	            the walls, the center of the hall stays free.

	Owner props (GameAssets) are used only where they fit the style and
	are tamed: no neon edges, human scale (Config.HubLayout sizes).
	Moving / living things are tagged for the client (HubLife.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local L = Config.HubLayout
local A = L.Hall
local C = L.Colors
local N = Config.Nano
local T = Config.Theme
local Texts = L.Texts
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local W2 = A.Width / 2
local H = A.Height
local WT = A.WallThickness
local ZS = A.SouthZ -- inner face of the south wall
local ZN = A.SouthZ - A.Length -- inner face of the north wall
local ZC = (ZS + ZN) / 2

local root, base
local screenIndex = 0

local function at(x: number, y: number, z: number): Vector3
	return base + Vector3.new(x, y, z)
end

-- Ground frame on a wall's inner face: -Z (look) points into the hall,
-- +X runs along the wall.
local function sideFrame(side: number, z: number): CFrame
	local p = at(side * W2, 0, z)
	return CFrame.lookAt(p, p + Vector3.new(-side, 0, 0))
end
local function northFrame(x: number): CFrame
	local p = at(x, 0, ZN)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end
local function southFrame(x: number): CFrame
	local p = at(x, 0, ZS)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, -1))
end

local function spot(parent: Instance, face: Enum.NormalId, range: number, brightness: number, angle: number?, color: Color3?)
	local light = Instance.new("SpotLight")
	light.Face = face
	light.Color = color or N.WarmLight
	light.Range = range
	light.Brightness = brightness
	light.Angle = angle or 120
	light.Shadows = false -- only the pendants cast shadows (mobile)
	light.Parent = parent
	return light
end

-- Owner model without neon edges / glows (they read as cheap outlines).
local function tame(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Material = M.Metal
			d.Color = C.Steel:Lerp(d.Color, 0.15)
		elseif d:IsA("Highlight") or d:IsA("SelectionBox") or d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	return model
end

local function ownerProp(parent, name: string, cf: CFrame, height: number)
	local prop = NanoKit.Prop(parent, name, cf, height)
	if prop then
		tame(prop)
	end
	return prop
end

-- Text on one face of a part (dark plate, SurfaceGui).
local function text(part: BasePart, face: Enum.NormalId, lines)
	return WorldKit.SurfaceText(part, face, lines, 60)
end

-- Dark sign plate with a steel frame (no neon). cf = plate center,
-- front (-Z) = the reading side.
local function signPlate(parent, cf: CFrame, size: Vector2, lines, bothSides: boolean?)
	local m = NanoKit.Model(parent, "Sign")
	local plate = Panel(m, "Plate", Vector3.new(size.X, size.Y, 0.3), cf, T.PanelDark, M.Smooth, { CanCollide = false })
	text(plate, Enum.NormalId.Front, lines)
	if bothSides then
		text(plate, Enum.NormalId.Back, lines)
	end
	local fw, fh, b = size.X / 2 + 0.15, size.Y / 2 + 0.15, 0.3
	Panel(m, "FrameTop", Vector3.new(size.X + 0.6, b, 0.5), cf * CFrame.new(0, fh, 0), C.Steel, M.Metal, { CanCollide = false })
	Panel(m, "FrameBottom", Vector3.new(size.X + 0.6, b, 0.5), cf * CFrame.new(0, -fh, 0), C.Steel, M.Metal, { CanCollide = false })
	Panel(m, "FrameLeft", Vector3.new(b, size.Y + 0.6, 0.5), cf * CFrame.new(-fw, 0, 0), C.Steel, M.Metal, { CanCollide = false })
	Panel(m, "FrameRight", Vector3.new(b, size.Y + 0.6, 0.5), cf * CFrame.new(fw, 0, 0), C.Steel, M.Metal, { CanCollide = false })
	return m, plate
end

---------------------------------------------------------------------
-- Walls
---------------------------------------------------------------------

-- One wall from `a` to `b` (ground points on the inner face), `inward`
-- = normal into the hall. openings: { { U = distance from a to the
-- center, Width, Height } } sorted by U. Builds the structural slab and
-- the dressing of the inner face.
local function wall(name: string, a: Vector3, b: Vector3, inward: Vector3, openings)
	local m = NanoKit.Model(root, name)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local function frameAt(u: number): CFrame
		local p = a + dir * u
		return CFrame.lookAt(p, p + inward)
	end
	-- solid stretches between the openings
	local solids, u0 = {}, -WT
	for _, o in ipairs(openings) do
		table.insert(solids, { u0, o.U - o.Width / 2 })
		u0 = o.U + o.Width / 2
	end
	table.insert(solids, { u0, length + WT })

	for _, s in ipairs(solids) do
		local w = s[2] - s[1]
		if w > 0.05 then
			local cf = frameAt((s[1] + s[2]) / 2)
			-- frameAt: X runs opposite to `dir` (lookAt), the size is symmetric
			Panel(m, "Slab", Vector3.new(w, H + 1, WT), cf * CFrame.new(0, (H + 1) / 2, WT / 2), C.WallSlab, M.Concrete)
			local inner = math.max(0, w - (if s[1] < 0 then WT else 0) - (if s[2] > length then WT else 0))
			if inner > 0.5 then
				local center = (math.max(s[1], 0) + math.min(s[2], length)) / 2
				local fc = frameAt(center)
				Panel(m, "Dado", Vector3.new(inner, 4, 0.35), fc * CFrame.new(0, 2, -0.17), C.Dado, M.Metal)
				Panel(m, "Kick", Vector3.new(inner, 0.35, 0.55), fc * CFrame.new(0, 4.1, -0.27), C.Steel, M.Metal)
				-- tall wall panels with reveals between them
				local count = math.max(1, math.floor(inner / 5.5 + 0.5))
				local pw = inner / count
				for i = 0, count - 1 do
					local pc = fc * CFrame.new(-inner / 2 + pw * (i + 0.5), 12, -0.09)
					Panel(m, "WallPanel", Vector3.new(pw - 0.4, 14, 0.18), pc, C.WallPanel, M.Concrete)
				end
			end
		end
	end
	-- headers over the openings
	for _, o in ipairs(openings) do
		local cf = frameAt(o.U)
		local hh = H + 1 - o.Height
		Panel(m, "Header", Vector3.new(o.Width, hh, WT), cf * CFrame.new(0, o.Height + hh / 2, WT / 2), C.WallSlab, M.Concrete)
	end
	-- cornice with a cable tray, upper band (continuous)
	local fc = frameAt(length / 2)
	Panel(m, "Cornice", Vector3.new(length, 1.2, 1.0), fc * CFrame.new(0, 20.6, -0.5), C.Steel, M.Metal)
	Panel(m, "CorniceLip", Vector3.new(length, 0.3, 1.3), fc * CFrame.new(0, 20.0, -0.65), C.Beam, M.Metal)
	Panel(m, "Tray", Vector3.new(length, 0.2, 1.1), fc * CFrame.new(0, 21.3, -0.6), C.Beam, M.Metal)
	Panel(m, "TrayLip", Vector3.new(length, 0.6, 0.12), fc * CFrame.new(0, 21.6, -1.1), C.Beam, M.Metal)
	for i, color in ipairs({ Color3.fromRGB(30, 30, 34), Color3.fromRGB(60, 34, 34), Color3.fromRGB(36, 40, 52) }) do
		NanoKit.Cylinder(m, "Cable", length, 0.32, fc * CFrame.new(0, 21.6, -0.3 - i * 0.24) * CFrame.Angles(0, 0, 0), color, M.Smooth).CanCollide = false
	end
	Panel(m, "UpperBand", Vector3.new(length, H - 22, 0.25), fc * CFrame.new(0, 22 + (H - 22) / 2, -0.12), C.Dado, M.Metal)
	return m, frameAt
end

-- Metal pilaster on a wall: plinth, shaft, recessed light strip, capital,
-- knee brace up to the truss, warm bracket lamp.
local function pilaster(parent, cf: CFrame, withBrace: boolean)
	local m = NanoKit.Model(parent, "Pilaster")
	Panel(m, "Shaft", Vector3.new(2.4, H, 1.4), cf * CFrame.new(0, H / 2, -0.7), C.Steel, M.Metal)
	Panel(m, "Plinth", Vector3.new(3.2, 1.6, 2.2), cf * CFrame.new(0, 0.8, -1.1), C.Dado, M.Metal)
	Panel(m, "Channel", Vector3.new(0.7, 14.6, 0.12), cf * CFrame.new(0, 10, -1.44), C.Dado, M.Metal, { CanCollide = false })
	NanoKit.Strip(m, (cf * CFrame.new(0, 2.8, -1.5)).Position, (cf * CFrame.new(0, 17.2, -1.5)).Position, N.Cyan, 0.14)
	Panel(m, "Capital", Vector3.new(3.2, 1.2, 2.4), cf * CFrame.new(0, H - A.TrussDepth - 0.6, -1.2), C.Beam, M.Metal)
	if withBrace then
		local p1 = (cf * CFrame.new(0, H - 9, -1.4)).Position
		local p2 = (cf * CFrame.new(0, H - A.TrussDepth - 0.4, -5)).Position
		Panel(m, "Brace", Vector3.new(0.6, 0.6, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2), C.Beam, M.Metal)
	end
	-- bracket lamp
	Panel(m, "LampArm", Vector3.new(0.35, 0.35, 1.8), cf * CFrame.new(0, 11.2, -2.2), C.Beam, M.Metal)
	local head = Panel(m, "LampHead", Vector3.new(1.3, 0.5, 1), cf * CFrame.new(0, 11, -3.1), C.Steel, M.Metal)
	Panel(m, "Bulb", Vector3.new(1, 0.1, 0.7), cf * CFrame.new(0, 10.72, -3.1), N.WarmLight, M.Neon, { CanCollide = false, CastShadow = false })
	spot(head, Enum.NormalId.Bottom, L.Lamp.Range, L.Lamp.Brightness, L.Lamp.Angle)
	return m
end

---------------------------------------------------------------------
-- Floor, ceiling, trusses, skylight
---------------------------------------------------------------------

local function flatDisc(parent, name, diameter, y, pos: Vector3, color, material)
	return NanoKit.Cylinder(parent, name, 0.1, diameter, CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
end

local function buildFloor()
	local m = NanoKit.Model(root, "Floor")
	Panel(m, "Foundation", Vector3.new(A.Width + 120, 1, A.Length + 120), CFrame.new(at(0, -1.6, ZC)), C.Ceiling, M.Concrete)
	NanoKit.Floor(m, at(0, 0, ZC), A.Width, A.Length, A.FloorTile, C.Floor, C.Floor, M.Concrete)
	-- metal borders along the walls
	local bw = 2.2
	Panel(m, "Border", Vector3.new(A.Width, 0.1, bw), CFrame.new(at(0, 0.05, ZS - bw / 2)), C.Steel, M.Plate)
	Panel(m, "Border", Vector3.new(A.Width, 0.1, bw), CFrame.new(at(0, 0.05, ZN + bw / 2)), C.Steel, M.Plate)
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "Border", Vector3.new(bw, 0.1, A.Length - bw * 2), CFrame.new(at(side * (W2 - bw / 2), 0.05, ZC)), C.Steel, M.Plate)
		Panel(m, "BorderLine", Vector3.new(0.25, 0.1, A.Length - bw * 2), CFrame.new(at(side * (W2 - bw - 0.6), 0.04, ZC)), C.Paint, M.Smooth, { CanCollide = false })
	end
	-- runner from the spawn to the gates with painted edge lines
	local z0, z1 = ZS - 3, ZN + L.Portal.FrameDepth + 6
	Panel(m, "Runner", Vector3.new(9, 0.08, z0 - z1), CFrame.new(at(0, 0.04, (z0 + z1) / 2)), C.Runner, M.Concrete, { CanCollide = false })
	for _, x in ipairs({ -4.8, 4.8 }) do
		Panel(m, "RunnerLine", Vector3.new(0.3, 0.1, z0 - z1), CFrame.new(at(x, 0.05, (z0 + z1) / 2)), C.Paint, M.Smooth, { CanCollide = false })
	end
	-- chevrons near the gates
	for i = 0, 2 do
		local z = z1 + 2 + i * 3
		for _, sx in ipairs({ -1, 1 }) do
			local p = at(sx * 1.4, 0.06, z)
			Panel(m, "Chevron", Vector3.new(3.2, 0.1, 0.4), CFrame.new(p) * CFrame.Angles(0, math.rad(sx * -35), 0), C.Paint, M.Smooth, { CanCollide = false })
		end
	end
	-- emblem in the middle of the hall (flat, the center stays free)
	local center = at(0, 0, ZC)
	flatDisc(m, "EmblemRing", 18, 0.05, center, C.Paint, M.Smooth).CanCollide = false
	flatDisc(m, "EmblemField", 17.2, 0.06, center, C.Runner, M.Concrete).CanCollide = false
	flatDisc(m, "EmblemSteel", 11, 0.07, center, C.Steel, M.Plate).CanCollide = false
	flatDisc(m, "EmblemInner", 10, 0.08, center, C.Runner, M.Concrete).CanCollide = false
	flatDisc(m, "EmblemCore", 3, 0.09, center, C.Paint, M.Smooth).CanCollide = false
	-- spawn plate
	flatDisc(m, "SpawnRing", 7.8, 0.06, at(0, 0, 0), C.Paint, M.Smooth).CanCollide = false
	flatDisc(m, "SpawnPlate", 7.2, 0.07, at(0, 0, 0), C.Steel, M.Plate).CanCollide = false
end

local function buildCeiling()
	local m = NanoKit.Model(root, "Ceiling")
	local S = A.Skylight
	local sw = S.HalfWidth
	local outerX = W2 + WT
	-- solid ceiling around the skylight
	local cy = H + 0.5
	Panel(m, "Roof", Vector3.new(outerX - sw, 1, A.Length + WT * 2), CFrame.new(at(-(sw + outerX) / 2, cy, ZC)), C.Ceiling, M.Metal)
	Panel(m, "Roof", Vector3.new(outerX - sw, 1, A.Length + WT * 2), CFrame.new(at((sw + outerX) / 2, cy, ZC)), C.Ceiling, M.Metal)
	Panel(m, "Roof", Vector3.new(sw * 2, 1, ZS + WT - S.FromZ), CFrame.new(at(0, cy, (ZS + WT + S.FromZ) / 2)), C.Ceiling, M.Metal)
	Panel(m, "Roof", Vector3.new(sw * 2, 1, S.ToZ - (ZN - WT)), CFrame.new(at(0, cy, (S.ToZ + ZN - WT) / 2)), C.Ceiling, M.Metal)
	-- skylight: glass, purlins, mullions, frame
	local len = S.FromZ - S.ToZ
	local zc = (S.FromZ + S.ToZ) / 2
	Panel(m, "Glass", Vector3.new(sw * 2, 0.2, len), CFrame.new(at(0, H + 0.4, zc)), C.Glass, M.Glass, { Transparency = 0.6, CastShadow = false })
	for x = -sw, sw, S.Purlin do
		Panel(m, "Purlin", Vector3.new(0.6, 0.8, len), CFrame.new(at(x, H - 0.1, zc)), C.Beam, M.Metal)
	end
	for z = S.ToZ + S.Mullion, S.FromZ - S.Mullion, S.Mullion do
		Panel(m, "Mullion", Vector3.new(sw * 2, 0.3, 0.3), CFrame.new(at(0, H + 0.15, z)), C.Beam, M.Metal)
	end
	for _, x in ipairs({ -sw, sw }) do
		Panel(m, "SkyFrame", Vector3.new(1.2, 1.4, len + 1.2), CFrame.new(at(x, H - 0.4, zc)), C.Steel, M.Metal)
	end
	for _, z in ipairs({ S.FromZ, S.ToZ }) do
		Panel(m, "SkyFrame", Vector3.new(sw * 2 + 1.2, 1.4, 1.2), CFrame.new(at(0, H - 0.4, z)), C.Steel, M.Metal)
	end
end

-- Lattice truss across the hall at `z` (top chord under the ceiling).
local function truss(parent, z: number)
	local m = NanoKit.Model(parent, "Truss")
	local d = A.TrussDepth
	local yTop, yBottom = H - 0.4, H - d
	Panel(m, "TopChord", Vector3.new(A.Width, 0.8, 1.2), CFrame.new(at(0, yTop, z)), C.Beam, M.Metal)
	Panel(m, "BottomChord", Vector3.new(A.Width, 0.8, 1.4), CFrame.new(at(0, yBottom, z)), C.Beam, M.Metal)
	local step = 4
	local n = math.floor(A.Width / step)
	for i = 0, n do
		local x = -W2 + i * step
		Panel(m, "Strut", Vector3.new(0.4, d - 0.6, 0.6), CFrame.new(at(x, (yTop + yBottom) / 2, z)), C.Steel, M.Metal)
		if i < n then
			local x2 = x + step
			local p1 = at(x, if i % 2 == 0 then yBottom else yTop, z)
			local p2 = at(x2, if i % 2 == 0 then yTop else yBottom, z)
			Panel(m, "Diagonal", Vector3.new(0.35, 0.35, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2), C.Steel, M.Metal)
		end
	end
	-- pendant lamps
	for _, x in ipairs(A.PendantX) do
		local top = at(x, yBottom - 0.4, z)
		local drop = L.Pendant.Drop
		Panel(m, "PendantRod", Vector3.new(0.12, drop, 0.12), CFrame.new(top - Vector3.new(0, drop / 2, 0)), C.Beam, M.Metal, { CanCollide = false, CastShadow = false })
		local shade = NanoKit.Cylinder(m, "Shade", 0.9, 2.4, CFrame.new(top - Vector3.new(0, drop + 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Metal)
		shade.CanCollide = false
		local bulb = NanoKit.Cylinder(m, "Bulb", 0.1, 1.8, CFrame.new(top - Vector3.new(0, drop + 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), N.WarmLight, M.Neon)
		bulb.CanCollide = false
		bulb.CastShadow = false
		local light = Instance.new("PointLight")
		light.Color = N.WarmLight
		light.Range = L.Pendant.Range
		light.Brightness = L.Pendant.Brightness
		light.Shadows = true
		light.Parent = bulb
	end
	return m
end

---------------------------------------------------------------------
-- Gates (north wall)
---------------------------------------------------------------------

local function buildGates()
	local P = L.Portal
	local m = NanoKit.Model(root, "Gates")
	local cf = northFrame(0) -- looks south, into the hall
	local fw, fd = P.FrameWidth, P.FrameDepth
	local half = P.Width / 2
	-- dais in front of the gates
	Panel(m, "Dais", Vector3.new(P.Width + fw * 2 + 4, 0.5, fd + 5), cf * CFrame.new(0, 0.25, -(fd + 5) / 2), C.Steel, M.Plate)
	Panel(m, "DaisEdge", Vector3.new(P.Width + fw * 2 + 4.4, 0.2, 0.6), cf * CFrame.new(0, 0.45, -(fd + 5) + 0.2), C.Paint, M.Smooth)
	-- massive side blocks
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (half + fw / 2)
		Panel(m, "Pylon", Vector3.new(fw, P.Height + 5, fd), cf * CFrame.new(x, (P.Height + 5) / 2, -fd / 2), C.Beam, M.Metal)
		Panel(m, "PylonFace", Vector3.new(fw - 1.4, P.Height - 2, 0.3), cf * CFrame.new(x, P.Height / 2 + 1, -fd - 0.1), C.Steel, M.Plate)
		Panel(m, "PylonBase", Vector3.new(fw + 1, 2, fd + 1), cf * CFrame.new(x, 1.5, -fd / 2), C.Dado, M.Metal)
		for i = 1, 3 do
			Panel(m, "Band", Vector3.new(fw + 0.3, 0.4, fd + 0.3), cf * CFrame.new(x, 2.5 + i * (P.Height / 3.4), -fd / 2), C.Steel, M.Metal)
		end
		-- light strip on the inner jamb
		NanoKit.Strip(m, (cf * CFrame.new(side * (half + 0.05), 2, -fd + 0.6)).Position, (cf * CFrame.new(side * (half + 0.05), P.Height - 0.5, -fd + 0.6)).Position, N.Cyan, 0.16)
		-- lamp on the front face, lighting the dais
		local lamp = Panel(m, "Lamp", Vector3.new(1.6, 0.6, 1), cf * CFrame.new(x, P.Height - 1, -fd - 0.6), C.Steel, M.Metal)
		spot(lamp, Enum.NormalId.Bottom, 24, 1.6, 100)
	end
	-- lintel + cap
	local lw = P.Width + fw * 2
	Panel(m, "Lintel", Vector3.new(lw, 4.6, fd), cf * CFrame.new(0, P.Height + 2.3, -fd / 2), C.Beam, M.Metal)
	Panel(m, "LintelFace", Vector3.new(lw - 2, 2.6, 0.3), cf * CFrame.new(0, P.Height + 2.3, -fd - 0.1), C.Steel, M.Plate)
	Panel(m, "Cap", Vector3.new(lw + 1.2, 0.8, fd + 0.8), cf * CFrame.new(0, P.Height + 5, -fd / 2), C.Steel, M.Metal)
	-- dark tunnel behind the opening
	Panel(m, "TunnelBack", Vector3.new(P.Width + 2, P.Height + 2, 1), cf * CFrame.new(0, P.Height / 2, WT + 7), C.Tunnel, M.Smooth)
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "TunnelSide", Vector3.new(1, P.Height + 2, 8), cf * CFrame.new(side * (half + 1), P.Height / 2, WT + 3), C.Tunnel, M.Smooth)
	end
	Panel(m, "TunnelTop", Vector3.new(P.Width + 2, 1, 8), cf * CFrame.new(0, P.Height + 1, WT + 3), C.Tunnel, M.Smooth)
	-- energy field (touch = start a run) + curtains
	local field = Panel(m, "PortalField", Vector3.new(P.Width, P.Height, 0.6), cf * CFrame.new(0, P.Height / 2, -fd + 1.6), N.Cyan, Enum.Material.ForceField, { CanCollide = false, Transparency = 0.25, CastShadow = false })
	field:SetAttribute("Portal", true)
	-- energy curtains: overlapping translucent light sheets that breathe
	local n = P.Curtains
	for i = 1, n do
		local x = -half + P.Width * (i - 0.5) / n
		local color = if i % 2 == 0 then N.Magenta else N.Cyan
		local curtain = Panel(m, "Curtain", Vector3.new(P.Width / n + 0.6, P.Height - 0.4, 0.1), cf * CFrame.new(x, P.Height / 2, -fd + 2.1 + (i % 2) * 0.25), color, M.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, Transparency = P.CurtainTransparency, CastShadow = false })
		NanoKit.Tag(curtain, "Pulse", { Period = 2.2 + i * 0.35 })
	end
	Panel(m, "FieldGlow", Vector3.new(P.Width, P.Height, 0.1), cf * CFrame.new(0, P.Height / 2, -fd + 2.9), N.Cyan, M.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, Transparency = 0.86, CastShadow = false })
	WorldKit.Light(field, N.Cyan, 22, 1.2)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(N.Cyan, N.Magenta)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.Rate = 12
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Parent = field
	-- the big sign above the gates
	-- (standing on the front edge of the cap, low enough that the trusses
	-- don't hide it from the spawn)
	local sh = P.SignHeight
	local signCf = cf * CFrame.new(0, P.Height + 5.6 + sh / 2, -fd - 0.1)
	signPlate(m, signCf, Vector2.new(lw + 4, sh), { { Text = Texts.Portal, Size = 96, Color = N.Gold }, { Text = Texts.PortalSub, Size = 36, Color = N.Cyan } })
	for _, side in ipairs({ -1, 1 }) do
		Panel(m, "SignLeg", Vector3.new(0.6, 1, 0.6), cf * CFrame.new(side * (lw / 2 - 2), P.Height + 5.6, -fd - 0.1), C.Beam, M.Metal)
	end
	return field
end

---------------------------------------------------------------------
-- Entrance (south wall, behind the spawn)
---------------------------------------------------------------------

-- Frame of a doorway. jambs = false where pilasters already flank it.
local function archFrame(parent, cf: CFrame, w: number, h: number, jambs: boolean)
	local m = NanoKit.Model(parent, "ArchFrame")
	for _, side in ipairs({ -1, 1 }) do
		if jambs then
			Panel(m, "Jamb", Vector3.new(1.4, h, 2.8), cf * CFrame.new(side * (w / 2 + 0.7), h / 2, -0.2), C.Steel, M.Metal)
			Panel(m, "JambBase", Vector3.new(1.8, 1.2, 3.2), cf * CFrame.new(side * (w / 2 + 0.7), 0.6, -0.2), C.Dado, M.Metal)
		end
		-- chamfered upper corners
		Panel(m, "Chamfer", Vector3.new(2.2, 2.2, 2.8), cf * CFrame.new(side * (w / 2 - 0.2), h - 0.2, -0.2) * CFrame.Angles(0, 0, math.rad(45)), C.Steel, M.Metal)
	end
	Panel(m, "Lintel", Vector3.new(w + 2.8, 2.2, 2.8), cf * CFrame.new(0, h + 1.1, -0.2), C.Steel, M.Metal)
	Panel(m, "LintelTrim", Vector3.new(w + 3.2, 0.35, 3.1), cf * CFrame.new(0, h + 2.35, -0.2), C.Beam, M.Metal)
	Panel(m, "Keystone", Vector3.new(2, 2.6, 3.1), cf * CFrame.new(0, h + 1.2, -0.25), C.Beam, M.Metal)
	Panel(m, "Threshold", Vector3.new(w, 0.12, WT + 1.6), cf * CFrame.new(0, 0.06, WT / 2 - 0.4), C.Steel, M.Plate)
	return m
end

local function buildEntrance()
	local E = L.Entrance
	local cf = southFrame(0)
	local m = NanoKit.Model(root, "Entrance")
	archFrame(m, cf, E.Width, E.Height, true)
	-- closed double door (the city outside comes later)
	for _, side in ipairs({ -1, 1 }) do
		local leaf = cf * CFrame.new(side * E.Width / 4, E.Height / 2, WT / 2)
		Panel(m, "Door", Vector3.new(E.Width / 2 - 0.1, E.Height, 0.6), leaf, C.Steel, M.Metal)
		for i = 1, 3 do
			Panel(m, "DoorRib", Vector3.new(E.Width / 2 - 1, 0.3, 0.75), leaf * CFrame.new(0, -E.Height / 2 + i * E.Height / 4, 0), C.Beam, M.Metal)
		end
	end
	Panel(m, "DoorSeam", Vector3.new(0.3, E.Height, 0.8), cf * CFrame.new(0, E.Height / 2, WT / 2), C.Beam, M.Metal)
	-- title above the entrance (seen when turning around at the spawn)
	signPlate(m, cf * CFrame.new(0, E.Height + 5.5, -0.4), Vector2.new(18, 4), { { Text = Texts.Title, Size = 72, Color = N.Gold }, { Text = Texts.TitleSub, Size = 30, Color = N.Cyan } })
end

---------------------------------------------------------------------
-- Hanging sign over an arch (on two cables down from the ceiling)
---------------------------------------------------------------------

local function hangingSign(parent, cf: CFrame, title: string, sub: string?, accent: Color3)
	local lines = { { Text = title, Size = 64, Color = N.Gold } }
	if sub then
		table.insert(lines, { Text = sub, Size = 38, Color = accent })
	end
	local y = L.Arch.Height + 5.2
	local size = Vector2.new(10, if sub then 3.2 else 2.4)
	local m = signPlate(parent, cf * CFrame.new(0, y, -2.4), size, lines, true)
	for _, sx in ipairs({ -1, 1 }) do
		local a = (cf * CFrame.new(sx * (size.X / 2 - 0.8), y + size.Y / 2 + 0.3, -2.4)).Position
		local b = Vector3.new(a.X, base.Y + H, a.Z)
		Panel(m, "Cable", Vector3.new(0.14, b.Y - a.Y, 0.14), CFrame.new((a + b) / 2), C.Beam, M.Metal, { CanCollide = false, CastShadow = false })
		Panel(m, "Clamp", Vector3.new(0.5, 0.4, 0.5), CFrame.new(a), C.Steel, M.Metal, { CanCollide = false })
	end
	return m
end

---------------------------------------------------------------------
-- Decor sets (one wall bay, ~10 studs; cf = bay center on the wall)
---------------------------------------------------------------------

local function crate(parent, cf: CFrame, s: number)
	local m = NanoKit.Model(parent, "Crate")
	Panel(m, "Body", Vector3.new(s, s, s), cf * CFrame.new(0, s / 2, 0), C.Steel, M.Plate)
	for _, dy in ipairs({ 0.18, s - 0.18 }) do
		Panel(m, "Band", Vector3.new(s + 0.08, 0.3, s + 0.08), cf * CFrame.new(0, dy, 0), C.Beam, M.Metal)
	end
	for _, dx in ipairs({ -1, 1 }) do
		Panel(m, "Edge", Vector3.new(0.3, s, s + 0.08), cf * CFrame.new(dx * (s / 2 - 0.1), s / 2, 0), C.Beam, M.Metal)
	end
	Panel(m, "Label", Vector3.new(s * 0.4, s * 0.22, 0.05), cf * CFrame.new(0, s * 0.6, -s / 2 - 0.03), C.Paint, M.Smooth, { CanCollide = false })
	return m
end

local function barrel(parent, cf: CFrame)
	return ownerProp(parent, "Prop_Barrel", cf, L.BarrelHeight) or (function()
		local m = NanoKit.Model(parent, "Barrel")
		NanoKit.Column(m, "Body", L.BarrelHeight, 2.1, cf.Position, C.Steel, M.Metal)
		for _, y in ipairs({ 0.5, L.BarrelHeight - 0.5 }) do
			NanoKit.Column(m, "Hoop", 0.25, 2.25, cf.Position + Vector3.new(0, y, 0), C.Beam, M.Metal)
		end
		return m
	end)()
end

local function planter(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Planter")
	Panel(m, "Box", Vector3.new(2.4, 1.8, 2.4), cf * CFrame.new(0, 0.9, 0), C.Dado, M.Metal)
	Panel(m, "Rim", Vector3.new(2.6, 0.25, 2.6), cf * CFrame.new(0, 1.85, 0), C.Steel, M.Metal)
	Panel(m, "Soil", Vector3.new(2.1, 0.2, 2.1), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(58, 44, 34), Enum.Material.Ground)
	for i = 1, 6 do
		local angle = i * math.pi * 2 / 6
		local h = 2.2 + (i % 3) * 0.5
		Panel(m, "Leaf", Vector3.new(0.35, h, 0.9), cf * CFrame.new(math.cos(angle) * 0.45, 1.8 + h / 2, math.sin(angle) * 0.45) * CFrame.Angles(0, -angle, math.rad(16)), N.Leaf, Enum.Material.Grass, { CanCollide = false })
	end
	return m
end

local function bench(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Bench")
	Panel(m, "Seat", Vector3.new(5.6, 0.35, 1.7), cf * CFrame.new(0, 1.6, 0), C.Steel, M.Plate)
	Panel(m, "Back", Vector3.new(5.6, 1.3, 0.3), cf * CFrame.new(0, 2.55, 0.75) * CFrame.Angles(math.rad(-10), 0, 0), C.Beam, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Leg", Vector3.new(0.4, 1.45, 1.5), cf * CFrame.new(sx * 2.4, 0.72, 0), C.Beam, M.Metal)
	end
	return m
end

-- Wall screen: dark glass in a frame with two lines of text.
local function wallScreen(parent, cf: CFrame, size: Vector2)
	screenIndex = screenIndex % #L.Screens + 1
	local s = L.Screens[screenIndex]
	local m = NanoKit.Model(parent, "Screen")
	Panel(m, "Frame", Vector3.new(size.X + 0.5, size.Y + 0.5, 0.3), cf * CFrame.new(0, 0, 0.1), C.Beam, M.Metal, { CanCollide = false })
	local glass = Panel(m, "Display", Vector3.new(size.X, size.Y, 0.1), cf * CFrame.new(0, 0, -0.1), C.Screen, M.Glass, { CanCollide = false })
	text(glass, Enum.NormalId.Front, { { Text = s.Title, Size = 34, Color = N.Cyan }, { Text = s.Line, Size = 24, Color = T.Text } })
	NanoKit.Tag(glass, "Flicker")
	return m
end

local function console(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Console")
	Panel(m, "Base", Vector3.new(3.2, 2.7, 1.6), cf * CFrame.new(0, 1.35, 0), C.Beam, M.Metal)
	Panel(m, "Desk", Vector3.new(3.4, 0.3, 1.9), cf * CFrame.new(0, 2.85, -0.1) * CFrame.Angles(math.rad(14), 0, 0), C.Steel, M.Metal)
	local screen = Panel(m, "Screen", Vector3.new(3, 1.7, 0.15), cf * CFrame.new(0, 3.9, 0.55) * CFrame.Angles(math.rad(-12), 0, 0), C.Screen, M.Glass)
	text(screen, Enum.NormalId.Front, { { Text = Texts.Console, Size = 22, Color = T.Green } })
	for i = -1, 1 do
		Panel(m, "Key", Vector3.new(0.6, 0.12, 0.35), cf * CFrame.new(i * 0.9, 3.02, -0.4) * CFrame.Angles(math.rad(14), 0, 0), if i == 0 then N.Gold else C.Dado, M.Smooth, { CanCollide = false })
	end
	return m
end

local function rack(parent, cf: CFrame, width: number)
	local m = NanoKit.Model(parent, "Rack")
	local h, d = 6.4, 1.6
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Post", Vector3.new(0.3, h, d), cf * CFrame.new(sx * width / 2, h / 2, 0), C.Beam, M.Metal)
	end
	for i = 0, 3 do
		local y = 0.4 + i * 1.9
		Panel(m, "Shelf", Vector3.new(width, 0.2, d), cf * CFrame.new(0, y, 0), C.Steel, M.Plate)
		if i < 3 then
			for j = 0, 2 do
				if (i + j) % 3 ~= 2 then
					local s = 1.1 + ((i * 3 + j) % 2) * 0.3
					crate(m, cf * CFrame.new(-width / 2 + 0.9 + j * (width - 1.8) / 2, y + 0.1, 0), s)
				end
			end
		end
	end
	return m
end

local function cargo(parent, cf: CFrame)
	local m = NanoKit.Model(parent, "Cargo")
	local s = L.CrateSize
	crate(m, cf * CFrame.new(-2.4, 0, -1.9), s)
	crate(m, cf * CFrame.new(-2.2, s, -1.9) * CFrame.Angles(0, math.rad(14), 0), s * 0.75)
	crate(m, cf * CFrame.new(0.9, 0, -1.6) * CFrame.Angles(0, math.rad(-8), 0), s * 0.8)
	barrel(m, cf * CFrame.new(3.3, 0, -1.7))
	if not ownerProp(m, "Prop_Misc_4", cf * CFrame.new(1.2, 0, -4.2), L.CanisterHeight) then
		barrel(m, cf * CFrame.new(1.2, 0, -4.2))
	end
	return m
end

-- One decor set in a wall bay.
local function decorSet(kind: string, cf: CFrame)
	local m = NanoKit.Model(root, "Decor_" .. kind)
	if kind == "Bench" then
		bench(m, cf * CFrame.new(0, 0, -1.7))
		planter(m, cf * CFrame.new(-3.6, 0, -1.6))
		planter(m, cf * CFrame.new(3.6, 0, -1.6))
		wallScreen(m, cf * CFrame.new(0, 7.6, -0.45), Vector2.new(6.4, 3.2))
	elseif kind == "Console" then
		console(m, cf * CFrame.new(-2.4, 0, -1.3))
		console(m, cf * CFrame.new(2.4, 0, -1.3))
		wallScreen(m, cf * CFrame.new(0, 8.2, -0.45), Vector2.new(7.6, 3.4))
	elseif kind == "Rack" then
		rack(m, cf * CFrame.new(-1.2, 0, -1.2), 5.6)
		planter(m, cf * CFrame.new(3.3, 0, -1.6))
		wallScreen(m, cf * CFrame.new(0, 9.4, -0.45), Vector2.new(7, 2.8))
	elseif kind == "Cargo" then
		cargo(m, cf)
	elseif kind == "Pipes" then
		if not ownerProp(m, "Prop_Pipes", cf * CFrame.new(-1.5, 0, -0.9), L.PipesHeight) then
			for i = 0, 2 do
				NanoKit.Column(m, "Pipe", 9, 0.8, (cf * CFrame.new(-3 + i * 1.2, 0, -0.7)).Position, C.Steel, M.Metal)
			end
		end
		barrel(m, cf * CFrame.new(2.4, 0, -1.6))
		barrel(m, cf * CFrame.new(3.6, 0, -3.4))
		Panel(m, "Grate", Vector3.new(6, 0.12, 2.4), cf * CFrame.new(0, 0.06, -1.4), C.Beam, M.Plate)
	end
	return m
end

---------------------------------------------------------------------
-- Leaderboard and wheel (wall bays)
---------------------------------------------------------------------

local function leaderboard(cf: CFrame, kind: string)
	local m = NanoKit.Model(root, "Leaderboard_" .. kind)
	Panel(m, "Frame", Vector3.new(8.8, 11.4, 0.3), cf * CFrame.new(0, 7.6, -0.15), C.Steel, M.Metal)
	local board = Panel(m, "Board", Vector3.new(8, 10.6, 0.3), cf * CFrame.new(0, 7.6, -0.45), T.PanelDark, M.Smooth)
	local lines = { { Name = "Title", Text = L.Leaderboards[kind], Size = 30, Color = N.Gold } }
	for i = 1, Config.Leaderboards.Top do
		table.insert(lines, { Name = "Row" .. i, Text = i .. ". —", Size = 18 })
	end
	local frame = WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 50)
	local lamp = Panel(m, "Lamp", Vector3.new(4, 0.4, 0.7), cf * CFrame.new(0, 13.8, -1.2), C.Steel, M.Metal)
	Panel(m, "LampArm", Vector3.new(0.3, 0.3, 1), cf * CFrame.new(0, 13.8, -0.5), C.Beam, M.Metal)
	spot(lamp, Enum.NormalId.Bottom, 14, 0.8, 110)
	planter(m, cf * CFrame.new(-4.4, 0, -1.6))
	return frame
end

local function buildWheel(cf: CFrame)
	local m = NanoKit.Model(root, "Wheel")
	local cy = 7.2
	Panel(m, "Board", Vector3.new(8.4, 8.4, 0.8), cf * CFrame.new(0, cy, -0.4), C.Steel, M.Plate)
	for _, sx in ipairs({ -1, 1 }) do
		Panel(m, "Strut", Vector3.new(0.8, 11, 1.2), cf * CFrame.new(sx * 4.6, 5.5, -0.6), C.Beam, M.Metal)
	end
	local spin = Instance.new("Model")
	spin.Name = "Spin"
	spin.Parent = m
	local disc = WorldKit.Part(spin, {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 7, 7),
		CFrame = cf * CFrame.new(0, cy, -1.1) * CFrame.Angles(0, math.rad(90), 0),
		Color = C.Beam,
		Material = M.Metal,
	})
	spin.PrimaryPart = disc
	local colors = { N.Magenta, N.Gold, N.Cyan, T.Green, T.Purple, T.Orange, T.Red, T.Blue }
	for i = 0, 7 do
		local angle = i * math.pi / 4
		WorldKit.Part(spin, {
			Name = "Segment",
			Size = Vector3.new(1.1, 2.4, 0.2),
			CFrame = cf * CFrame.new(math.cos(angle) * 2.1, cy + math.sin(angle) * 2.1, -1.45) * CFrame.Angles(0, 0, angle + math.rad(90)),
			Color = colors[i + 1],
			Material = M.Smooth,
			CanCollide = false,
		})
	end
	WorldKit.Part(m, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.4, 1.4), CFrame = cf * CFrame.new(0, cy, -1.6) * CFrame.Angles(0, math.rad(90), 0), Color = C.Steel, Material = M.Metal })
	WorldKit.Part(m, { Name = "Pointer", Size = Vector3.new(0.6, 1.2, 0.5), CFrame = cf * CFrame.new(0, cy + 3.9, -1.6), Color = N.Gold, Material = M.Metal })
	signPlate(m, cf * CFrame.new(0, cy + 6, -0.6), Vector2.new(8.4, 2.4), { { Text = Texts.Wheel, Size = 40, Color = N.Gold }, { Name = "Status", Text = Texts.WheelFree, Size = 22, Color = T.Green } })
	m:SetAttribute("Wheel", true)
	return WorldKit.Prompt(disc, L.Prompts.Wheel, "", { Action = "Wheel" }, 12)
end

---------------------------------------------------------------------
-- Side rooms behind the arches (temporary, compact)
---------------------------------------------------------------------

-- Shell of a room. cf: ground center of the doorway on the room side,
-- -Z points into the room. Returns the room model.
local function roomShell(name: string, cf: CFrame)
	local R = L.Room
	local w, d, h = R.Width, R.Depth, R.Height
	local m = NanoKit.Model(root, name)
	Panel(m, "Floor", Vector3.new(w, 1, d), cf * CFrame.new(0, -0.5, -d / 2), C.Floor, M.Concrete)
	Panel(m, "FloorBorder", Vector3.new(w - 4, 0.08, d - 4), cf * CFrame.new(0, 0.04, -d / 2), C.Runner, M.Concrete, { CanCollide = false })
	local walls = {
		{ CFrame.new(0, 0, -d), w + 2 }, -- back
		{ CFrame.new(-w / 2, 0, -d / 2) * CFrame.Angles(0, math.rad(90), 0), d },
		{ CFrame.new(w / 2, 0, -d / 2) * CFrame.Angles(0, math.rad(-90), 0), d },
	}
	-- each wall frame has +Z pointing into the room
	for _, wl in ipairs(walls) do
		local wcf = cf * wl[1]
		Panel(m, "Wall", Vector3.new(wl[2], h + 1, 1), wcf * CFrame.new(0, (h + 1) / 2, 0), C.WallSlab, M.Concrete)
		Panel(m, "Dado", Vector3.new(wl[2] - 1, 3.6, 0.3), wcf * CFrame.new(0, 1.8, 0.65), C.Dado, M.Metal)
	end
	Panel(m, "Ceiling", Vector3.new(w + 2, 1, d + 1), cf * CFrame.new(0, h + 0.5, -d / 2), C.Ceiling, M.Metal)
	for _, z in ipairs({ -d * 0.3, -d * 0.7 }) do
		Panel(m, "Beam", Vector3.new(w, 1.2, 0.9), cf * CFrame.new(0, h - 0.6, z), C.Beam, M.Metal)
	end
	local panel = Panel(m, "CeilingLight", Vector3.new(5, 0.2, 2), cf * CFrame.new(0, h - 0.1, -d / 2), N.WarmLight, M.Neon, { CanCollide = false, CastShadow = false })
	local light = Instance.new("PointLight")
	light.Color = N.WarmLight
	light.Range = 26
	light.Brightness = 1.2
	light.Shadows = true
	light.Parent = panel
	return m
end

local function roomFrame(side: number, z: number): CFrame
	local p = at(side * (W2 + WT), 0, z)
	return CFrame.lookAt(p, p + Vector3.new(side, 0, 0))
end

local function buildForgeRoom(cf: CFrame)
	local m = roomShell("Forge", cf)
	local d = L.Room.Depth
	-- reactor core at the back ("Hearth": Glow, Fire, Sparks)
	local coreCf = cf * CFrame.new(0, 0, -d + 4)
	NanoKit.Column(m, "ReactorBase", 1.6, 6, coreCf.Position, C.Dado, M.Metal)
	-- (SmoothPlastic, not Glass: Roblox glass hides the neon core behind it)
	NanoKit.Column(m, "ReactorGlass", 5.4, 4, coreCf.Position + Vector3.new(0, 1.6, 0), C.Glass, M.Smooth).Transparency = 0.75
	NanoKit.Column(m, "ReactorCap", 1, 5.4, coreCf.Position + Vector3.new(0, 7, 0), C.Steel, M.Metal)
	local hearth = Panel(m, "Hearth", Vector3.new(2.2, 2.2, 2.2), coreCf * CFrame.new(0, 4.3, 0), N.Cyan, M.Neon, { CanCollide = false, Shape = Enum.PartType.Ball, Transparency = 0.1 })
	local glow = WorldKit.Light(hearth, N.Cyan, 18, 1.6)
	glow.Name = "Glow"
	local fire = Instance.new("Fire")
	fire.Name = "Fire"
	fire.Color = N.Cyan
	fire.SecondaryColor = N.Magenta
	fire.Size = 5
	fire.Heat = 5
	fire.Parent = hearth
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(N.Cyan, Color3.new(1, 1, 1))
	sparks.LightEmission = 0.8
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Rate = 0
	sparks.Parent = hearth
	NanoKit.Tag(hearth, "Pulse", { Period = 1.6 })
	-- press table ("Anvil") under a manipulator
	local anvilCf = cf * CFrame.new(-4.5, 0, -10)
	Panel(m, "AnvilBase", Vector3.new(4, 2.4, 3), anvilCf * CFrame.new(0, 1.2, 0), C.Beam, M.Metal)
	local anvil = Panel(m, "Anvil", Vector3.new(4.6, 0.6, 3.4), anvilCf * CFrame.new(0, 2.7, 0), C.Steel, M.Plate)
	local anvilSparks = sparks:Clone()
	anvilSparks.Color = ColorSequence.new(N.Gold, Color3.new(1, 1, 1))
	anvilSparks.SpreadAngle = Vector2.new(80, 80)
	anvilSparks.Parent = anvil
	NanoKit.Column(m, "ArmPost", 12, 0.9, (anvilCf * CFrame.new(-2.8, 0, 0)).Position, C.Steel, M.Metal)
	Panel(m, "Manipulator", Vector3.new(4.4, 0.7, 0.7), anvilCf * CFrame.new(-0.8, 11, 0), N.Gold, M.Metal)
	local hammer = Panel(m, "Hammer", Vector3.new(1.3, 2, 1.3), anvilCf * CFrame.new(0.6, 9.4, 0), C.Beam, M.Metal)
	NanoKit.Tag(hammer, "Bob", { Amplitude = 0.6, Period = 2.2 })
	-- console with the prompt, by the door
	local consoleCf = cf * CFrame.new(4.5, 0, -5) * CFrame.Angles(0, math.rad(90), 0) -- faces the room
	local c = console(m, consoleCf)
	local prompt = WorldKit.Prompt(c:FindFirstChild("Base"), L.Prompts.Forge, "", { Action = "OpenForge" }, 12)
	-- shelves with parts
	rack(m, cf * CFrame.new(L.Room.Width / 2 - 1.2, 0, -14) * CFrame.Angles(0, math.rad(-90), 0), 6)
	cargo(m, cf * CFrame.new(-L.Room.Width / 2 + 0.6, 0, -17) * CFrame.Angles(0, math.rad(-90), 0))
	return prompt, m
end

local function egg(parent, cf: CFrame, scale: number, color: Color3)
	local shell = Panel(parent, "EggShell", Vector3.new(2.6, 3.4, 2.6) * scale, cf, Color3.fromRGB(240, 238, 248), M.Smooth, { Shape = Enum.PartType.Ball, CanCollide = false })
	for i = 1, 4 do
		local angle = i * math.pi / 2
		Panel(parent, "EggLine", Vector3.new(0.1, 2.6, 0.1) * scale, cf * CFrame.new(math.cos(angle) * 1.3 * scale, 0, math.sin(angle) * 1.3 * scale), color, M.Smooth, { CanCollide = false })
	end
	return shell
end

local function buildEggRoom(cf: CFrame)
	local m = roomShell("Egg", cf)
	local center = cf * CFrame.new(0, 0, -L.Room.Depth / 2 - 1)
	local pos = center.Position
	NanoKit.Cylinder(m, "Platform", 0.8, 10, CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Beam, M.Metal)
	NanoKit.Cylinder(m, "PlatformTop", 0.1, 9.2, CFrame.new(pos + Vector3.new(0, 0.82, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Plate).CanCollide = false
	local pedestal = Panel(m, "Pedestal", Vector3.new(3.6, 2, 3.6), CFrame.new(pos + Vector3.new(0, 1.8, 0)), C.Steel, M.Plate)
	NanoKit.Column(m, "Capsule", 5, 4.4, pos + Vector3.new(0, 2.8, 0), C.Glass, M.Glass).Transparency = 0.75
	NanoKit.Column(m, "CapsuleLid", 0.6, 4.8, pos + Vector3.new(0, 7.8, 0), C.Steel, M.Metal)
	local big = egg(m, CFrame.new(pos + Vector3.new(0, 4.6, 0)), 0.9, N.Magenta)
	NanoKit.Tag(big, "Bob", { Amplitude = 0.3, Period = 2.6 })
	WorldKit.Light(big, N.Magenta, 14, 0.8)
	-- incubation pods along the side walls
	for i, z in ipairs({ -6, -16 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local p = (cf * CFrame.new(sx * (L.Room.Width / 2 - 2.2), 0, z)).Position
			NanoKit.Column(m, "PodBase", 0.8, 2.6, p, C.Beam, M.Metal)
			NanoKit.Column(m, "Pod", 3, 2.2, p + Vector3.new(0, 0.8, 0), C.Glass, M.Glass).Transparency = 0.6
			egg(m, CFrame.new(p + Vector3.new(0, 2.2, 0)), 0.45, if (i + sx) % 2 == 0 then N.Cyan else N.Gold)
			NanoKit.Column(m, "PodLid", 0.3, 2.4, p + Vector3.new(0, 3.8, 0), C.Steel, M.Metal)
		end
	end
	return WorldKit.Prompt(pedestal, L.Prompts.Egg, "", { Action = "OpenPets" }, 12)
end

local function buildStoreRoom(cf: CFrame)
	local m = roomShell("Store", cf)
	local counterCf = cf * CFrame.new(0, 0, -10)
	local counter = Panel(m, "Counter", Vector3.new(7, 3, 2.4), counterCf * CFrame.new(0, 1.5, 0), C.Beam, M.Metal)
	Panel(m, "CounterTop", Vector3.new(7.4, 0.3, 2.8), counterCf * CFrame.new(0, 3.15, 0), N.Gold, M.Metal)
	local gem = Panel(m, "Gem", Vector3.new(1.6, 1.6, 1.6), counterCf * CFrame.new(0, 5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), N.Cyan, M.Glass, { CanCollide = false, Transparency = 0.15 })
	NanoKit.Tag(gem, "Spin", { Speed = 60, Axis = "Y" })
	WorldKit.Light(gem, N.Cyan, 12, 0.8)
	for _, sx in ipairs({ -1, 1 }) do
		rack(m, cf * CFrame.new(sx * (L.Room.Width / 2 - 1.2), 0, -12) * CFrame.Angles(0, math.rad(sx * -90), 0), 8)
	end
	signPlate(m, cf * CFrame.new(0, 9, -L.Room.Depth + 0.8) * CFrame.Angles(0, math.rad(180), 0), Vector2.new(10, 2.8), { { Text = Texts.Store, Size = 56, Color = N.Gold }, { Text = Texts.StoreSub, Size = 26, Color = T.Green } })
	return WorldKit.Prompt(counter, L.Prompts.Store, "", { Action = "OpenStore" }, 12)
end

local function buildPolygonRoom(cf: CFrame)
	local m = roomShell("Polygon", cf)
	local d = L.Room.Depth
	-- painted lanes on the floor
	for i = -1, 1 do
		Panel(m, "Lane", Vector3.new(0.3, 0.1, d - 6), cf * CFrame.new(i * 6, 0.06, -d / 2), C.Paint, M.Smooth, { CanCollide = false })
	end
	-- board on the back wall
	signPlate(m, cf * CFrame.new(0, L.Room.Height - 3, -d + 0.8) * CFrame.Angles(0, math.rad(180), 0), Vector2.new(12, 3.4), { { Text = Texts.Polygon, Size = 60, Color = N.Cyan }, { Text = Texts.PolygonSub, Size = 26 } })
	-- floodlights over the dummies
	for _, sx in ipairs({ -1, 1 }) do
		local head = Panel(m, "Floodlight", Vector3.new(2, 0.8, 1), cf * CFrame.new(sx * 6, L.Room.Height - 2, -6) * CFrame.Angles(math.rad(-50), 0, 0), C.Steel, M.Metal)
		spot(head, Enum.NormalId.Front, 30, 1.6, 70)
	end
	ownerProp(m, "Trainer_Weights", cf * CFrame.new(L.Room.Width / 2 - 3, 0, -4), 2)
	rack(m, cf * CFrame.new(-L.Room.Width / 2 + 1.2, 0, -5) * CFrame.Angles(0, math.rad(90), 0), 5)
	local center = (cf * CFrame.new(0, 0, -d / 2)).Position
	return m, center
end

---------------------------------------------------------------------

function HubGenerator.Build()
	root = Instance.new("Folder")
	root.Name = "Hub"

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	base = Vector3.new(origin.X, groundY, origin.Z)
	if spawn then
		-- players appear facing the gates; the default look stays hidden
		spawn.CFrame = CFrame.new(spawn.Position)
		spawn.Transparency = 1
		for _, d in ipairs(spawn:GetChildren()) do
			if d:IsA("Decal") then
				d.Transparency = 1
			end
		end
	end

	buildFloor()
	buildCeiling()

	-- walls with openings
	local P = L.Portal
	local northOpen = { { U = W2, Width = P.Width, Height = P.Height } }
	local southOpen = { { U = W2, Width = L.Entrance.Width, Height = L.Entrance.Height } }
	wall("NorthWall", at(-W2, 0, ZN), at(W2, 0, ZN), Vector3.new(0, 0, 1), northOpen)
	wall("SouthWall", at(W2, 0, ZS), at(-W2, 0, ZS), Vector3.new(0, 0, -1), southOpen)
	for _, side in ipairs({ -1, 1 }) do
		local openings = {}
		for _, bay in ipairs(L.Bays) do
			if bay.Side == side and bay.Kind == "Arch" then
				table.insert(openings, { U = ZS - bay.Z, Width = L.Arch.Width, Height = L.Arch.Height })
			end
		end
		table.sort(openings, function(a, b)
			return a.U < b.U
		end)
		wall(if side < 0 then "WestWall" else "EastWall", at(side * W2, 0, ZS), at(side * W2, 0, ZN), Vector3.new(-side, 0, 0), openings)
	end

	-- pilasters + trusses on the bay lines, clerestory vents
	local structure = NanoKit.Model(root, "Structure")
	local z = ZS - A.Bay
	while z > ZN + 1 do
		for _, side in ipairs({ -1, 1 }) do
			pilaster(structure, sideFrame(side, z), true)
		end
		truss(structure, z)
		z -= A.Bay
	end
	for _, x in ipairs(L.SouthPilasters) do
		pilaster(structure, southFrame(x), false)
	end
	for _, bay in ipairs(L.Bays) do
		NanoKit.Vent(structure, sideFrame(bay.Side, bay.Z) * CFrame.new(0, 26, -0.4), 3)
	end

	local portal = buildGates()
	buildEntrance()

	-- side wall bays
	local boards = {}
	local forgePrompt, forge, eggPrompt, storePrompt, wheelPrompt, polygon, polygonCenter
	for _, bay in ipairs(L.Bays) do
		local cf = sideFrame(bay.Side, bay.Z)
		if bay.Kind == "Arch" then
			archFrame(root, cf, L.Arch.Width, L.Arch.Height, false)
			local rcf = roomFrame(bay.Side, bay.Z)
			if bay.Room == "Forge" then
				forgePrompt, forge = buildForgeRoom(rcf)
				hangingSign(root, cf, Texts.Forge, Texts.ForgeSub, N.Cyan)
			elseif bay.Room == "Egg" then
				eggPrompt = buildEggRoom(rcf)
				hangingSign(root, cf, Texts.Pets, Texts.PetsSub, N.Magenta)
			elseif bay.Room == "Store" then
				storePrompt = buildStoreRoom(rcf)
				hangingSign(root, cf, Texts.Store, Texts.StoreSub, T.Green)
			elseif bay.Room == "Polygon" then
				polygon, polygonCenter = buildPolygonRoom(rcf)
				hangingSign(root, cf, Texts.Polygon, Texts.PolygonSub, N.Cyan)
			end
		elseif bay.Kind == "Board" then
			boards[bay.Board] = leaderboard(cf, bay.Board)
		elseif bay.Kind == "Wheel" then
			wheelPrompt = buildWheel(cf)
		else
			decorSet(bay.Kind, cf)
		end
	end
	for _, bay in ipairs(L.NorthBays) do
		decorSet(bay.Kind, northFrame(bay.X))
	end
	for _, bay in ipairs(L.SouthBays) do
		decorSet(bay.Kind, southFrame(bay.X))
	end

	root:SetAttribute("Center", at(0, 0, ZC))
	root.Parent = Workspace
	return {
		Folder = root,
		Polygon = polygon,
		PolygonCenter = polygonCenter,
		Portal = portal,
		Forge = forge,
		ForgePrompt = forgePrompt,
		StorePrompt = storePrompt,
		WheelPrompt = wheelPrompt,
		EggPrompt = eggPrompt,
		Leaderboards = boards,
		SpawnCFrame = CFrame.lookAt(at(0, 4, 0), at(0, 4, -10)),
		GroundY = base.Y,
	}
end

return HubGenerator
