--[[
	HubGenerator.luau
	Builds the hub, "Цитадель Ауры", at server start (Workspace.Hub).
	Pure construction from Parts; logic lives in HubService (trainers)
	and on the client (prompts only open windows).

	Top view (south = spawn, north = portal), see Config.HubLayout:

	                 [ PORTAL ]
	     TRAINERS        |          FORGE
	     (2 rows of 4)   |      (big building)
	     Eggs        [FOUNTAIN]     Premium showcase
	     Wheel           |      (Robux trainers, store)
	     Leaderboards [ SPAWN ]     Rebirth altar

	Every object is built in its own frame `cf` (ground level, -Z = the
	side that faces the visitor), so it can be turned to face the path.
	Signs follow the text rule (WorldKit.SurfaceText): vertical boards at
	eye height facing the player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local TrainerBuilder = require(script.Parent.TrainerBuilder)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local L = Config.HubLayout
local T = Config.Theme
local Texts = L.Texts

local WOOD = Color3.fromRGB(120, 80, 50)
local WOOD_DARK = Color3.fromRGB(85, 55, 35)
local IRON = Color3.fromRGB(75, 75, 88)
local WEST = Vector3.new(-1, 0, 0)
local EAST = Vector3.new(1, 0, 0)
local SOUTH = Vector3.new(0, 0, 1)

local root, base

local function at(offset: Vector3): Vector3
	return base + offset
end

-- Ground-level frame at an offset whose front (-Z) looks along `dir`.
local function frame(offset: Vector3, dir: Vector3): CFrame
	local pos = at(offset)
	return CFrame.lookAt(pos, pos + dir)
end

local function part(parent, name, size, cf, color, material, props)
	local p = WorldKit.Part(parent, { Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic })
	for key, value in pairs(props or {}) do
		p[key] = value
	end
	return p
end

-- Vertical sign board: text on the front (and optionally back) face.
local function sign(parent, cf: CFrame, size: Vector3, lines, twoSided: boolean?)
	local board = WorldKit.Part(parent, { Name = "Sign", Size = size, CFrame = cf, Color = T.PanelDark, CanCollide = false })
	WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 50)
	if twoSided then
		WorldKit.SurfaceText(board, Enum.NormalId.Back, lines, 50)
	end
	return board
end

-- Zone name on two posts, at eye height, readable from both sides.
local function zoneSign(parent, offset: Vector3, dir: Vector3, text: string, color: Color3?)
	local cf = frame(offset, dir)
	for _, side in ipairs({ -1, 1 }) do
		part(parent, "SignPost", Vector3.new(0.6, 5.2, 0.6), cf * CFrame.new(side * 4.6, 2.6, 0), WOOD_DARK, Enum.Material.Wood)
	end
	return sign(parent, cf * CFrame.new(0, 6.3, 0), Vector3.new(10.4, 2.8, 0.4), { { Text = text, Size = 50, Color = color or T.Gold } }, true)
end

---------------------------------------------------------------------
-- Courtyard, walls, towers, bounds
---------------------------------------------------------------------

local function buildCourtyard()
	local half = L.Size / 2
	local center = base + L.Center
	WorldKit.TiledFloor(root, center - Vector3.new(0, 0.05, 0), L.Size, L.Size, L.TileSize, T.TileA, T.TileB, 196)
	WorldKit.Part(root, {
		Name = "Grass",
		Size = Vector3.new(L.Size * 2.5, 1, L.Size * 2.5),
		Position = center + Vector3.new(0, -0.6, 0),
		Color = T.Grass,
		Material = Enum.Material.Grass,
	})

	local corners = {
		Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half), Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		WorldKit.CastleWall(root, center + corners[i], center + corners[i % 4 + 1], L.WallHeight, L.WallThickness, T.StoneA, T.StoneB, L.MerlonSize, nil, T.StoneLight)
	end

	for i, c in ipairs(corners) do
		local tower = Instance.new("Model")
		tower.Name = "Tower" .. i
		tower.Parent = root
		local pos = center + c
		WorldKit.Brick(tower, Vector3.new(L.TowerSize, L.TowerHeight, L.TowerSize), CFrame.new(pos + Vector3.new(0, L.TowerHeight / 2, 0)), T.StoneDark)
		WorldKit.Brick(tower, Vector3.new(L.TowerSize + 2, 2, L.TowerSize + 2), CFrame.new(pos + Vector3.new(0, L.TowerHeight + 1, 0)), T.StoneLight, "Cap")
		for _, dx in ipairs({ -1, 1 }) do
			for _, dz in ipairs({ -1, 1 }) do
				WorldKit.Brick(tower, Vector3.new(2, 2, 2), CFrame.new(pos + Vector3.new(dx * (L.TowerSize / 2), L.TowerHeight + 3, dz * (L.TowerSize / 2))), T.StoneLight, "Merlon")
			end
		end
		WorldKit.Part(tower, { Name = "Pole", Size = Vector3.new(0.4, 10, 0.4), Position = pos + Vector3.new(0, L.TowerHeight + 7, 0), Color = T.StoneDark })
		WorldKit.Part(tower, { Name = "Flag", Size = Vector3.new(5, 3, 0.2), Position = pos + Vector3.new(2.7, L.TowerHeight + 10.5, 0), Color = if i % 2 == 0 then T.Magenta else T.Cyan, CanCollide = false })
	end

	-- Map bounds: invisible walls on the wall line up to HubWallExtra
	-- above the walls, plus a lid. Nothing leads onto the walls.
	local bounds = Instance.new("Model")
	bounds.Name = "Bounds"
	bounds.Parent = root
	local B = Config.Bounds
	local t = L.WallThickness
	local boundH = L.WallHeight + B.HubWallExtra + 2
	local span = L.Size + t + B.Overlap * 2
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Invisible(bounds, Vector3.new(span, boundH, t), center + Vector3.new(0, boundH / 2 - 1, side * half))
		WorldKit.Invisible(bounds, Vector3.new(t, boundH, span), center + Vector3.new(side * half, boundH / 2 - 1, 0))
	end
	WorldKit.Invisible(bounds, Vector3.new(span, 2, span), center + Vector3.new(0, boundH, 0), "Lid")

	-- Flags along the walls.
	for i = -2, 2 do
		for _, zSide in ipairs({ -1, 1 }) do
			local pos = center + Vector3.new(i * 30, L.WallHeight + 2, zSide * (half - 2))
			WorldKit.Part(root, { Name = "Pole", Size = Vector3.new(0.3, 6, 0.3), Position = pos + Vector3.new(0, 3, 0), Color = T.StoneDark })
			WorldKit.Part(root, { Name = "Flag", Size = Vector3.new(3, 2, 0.2), Position = pos + Vector3.new(1.6, 5, 0), Color = if (i + zSide) % 2 == 0 then T.Gold else T.Magenta, CanCollide = false })
		end
	end
end

---------------------------------------------------------------------
-- Paths, chevrons, lanterns
---------------------------------------------------------------------

local function chevron(position: Vector3, yaw: number)
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Part(root, {
			Name = "Chevron",
			Size = Vector3.new(1.4, 0.15, 5),
			CFrame = CFrame.new(position + Vector3.new(0, 0.26, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(side * 2.2, 0, 0) * CFrame.Angles(0, side * math.rad(35), 0),
			Color = T.Chevron,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Chevrons along a straight segment from a to b (ground offsets).
local function chevronLine(a: Vector3, b: Vector3)
	local delta = b - a
	local length = delta.Magnitude
	local dir = delta.Unit
	local yaw = math.atan2(-dir.X, -dir.Z)
	local d = L.ChevronSpacing / 2
	while d < length - 2 do
		chevron(at(a + dir * d), yaw)
		d += L.ChevronSpacing
	end
end

-- Flat axis-aligned strip from a to b (ground offsets).
local function strip(name: string, a: Vector3, b: Vector3, width: number, color: Color3)
	local d = b - a
	local alongX = math.abs(d.X) > math.abs(d.Z)
	WorldKit.Part(root, {
		Name = name,
		Size = if alongX then Vector3.new(math.abs(d.X), 0.2, width) else Vector3.new(width, 0.2, math.abs(d.Z)),
		Position = at((a + b) / 2 + Vector3.new(0, 0.08, 0)),
		Color = color,
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
	})
end

local function lantern(parent, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Lantern"
	model.Parent = parent
	part(model, "Foot", Vector3.new(1.4, 0.5, 1.4), CFrame.new(position + Vector3.new(0, 0.25, 0)), IRON, Enum.Material.Metal)
	part(model, "Post", Vector3.new(0.5, 7, 0.5), CFrame.new(position + Vector3.new(0, 3.8, 0)), IRON, Enum.Material.Metal)
	part(model, "Cap", Vector3.new(1.8, 0.4, 1.8), CFrame.new(position + Vector3.new(0, 9.1, 0)), IRON, Enum.Material.Metal)
	local lamp = part(model, "Lamp", Vector3.new(1.2, 1.4, 1.2), CFrame.new(position + Vector3.new(0, 8.2, 0)), Color3.fromRGB(255, 225, 150), Enum.Material.Glass, { CanCollide = false })
	WorldKit.Light(lamp, Color3.fromRGB(255, 215, 150), 18, 0.9)
	return model
end

local function buildPaths()
	local F = L.Fountain
	local pathColor = T.Path
	local sideColor = T.Path:Lerp(Color3.new(1, 1, 1), 0.25)
	local zStart = 8
	local zEnd = L.Portal.Offset.Z + L.Portal.Radius - 2
	-- Main straight path, with a round plaza around the fountain.
	strip("Path", Vector3.new(0, 0, zStart), Vector3.new(0, 0, zEnd), L.PathWidth, pathColor)
	WorldKit.Part(root, {
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.24, F.PlazaRadius * 2, F.PlazaRadius * 2),
		CFrame = CFrame.new(at(F.Offset + Vector3.new(0, 0.1, 0))) * CFrame.Angles(0, 0, math.rad(90)),
		Color = pathColor,
		Material = Enum.Material.Plastic,
	})
	chevronLine(Vector3.new(0, 0, 2), Vector3.new(0, 0, F.Offset.Z + F.PlazaRadius))
	chevronLine(Vector3.new(0, 0, F.Offset.Z - F.PlazaRadius), Vector3.new(0, 0, zEnd + 6))

	-- Side paths to every zone.
	local w = L.SidePathWidth
	local half = L.PathWidth / 2
	local trainerZ = L.TrainerSpots["1"].Z
	strip("PathTrainers", Vector3.new(-half, 0, trainerZ), Vector3.new(L.TrainerSpots["1"].X + L.TrainerSize / 2, 0, trainerZ), w, sideColor)
	strip("PathTrainerRow", Vector3.new(-27, 0, trainerZ + w / 2), Vector3.new(-27, 0, L.TrainerSpots["4"].Z), w, sideColor)
	strip("PathForge", Vector3.new(half, 0, L.Forge.Offset.Z), Vector3.new(L.Forge.Offset.X - 16, 0, L.Forge.Offset.Z), w, sideColor)
	strip("PathPets", Vector3.new(-half, 0, L.Egg.Offset.Z), Vector3.new(L.Egg.Offset.X + 5, 0, L.Egg.Offset.Z), w, sideColor)
	strip("PathWheel", Vector3.new(-F.PlazaRadius + 2, 0, L.Wheel.Offset.Z), Vector3.new(L.Wheel.Offset.X + 4, 0, L.Wheel.Offset.Z), w, sideColor)
	strip("PathPremium", Vector3.new(F.PlazaRadius - 2, 0, L.Store.Offset.Z), Vector3.new(L.TrainerSpots.Gold.X - L.TrainerSize / 2, 0, L.Store.Offset.Z), w, sideColor)
	strip("PathAltar", Vector3.new(half, 0, L.Altar.Offset.Z), Vector3.new(L.Altar.Offset.X - 7, 0, L.Altar.Offset.Z), w, sideColor)
	strip("PathLeaders", Vector3.new(-half, 0, 5), Vector3.new(L.Leaderboards[1].Offset.X + 2, 0, 5), w, sideColor)
	-- New players are led to the first trainer.
	chevronLine(Vector3.new(-half - 1, 0, trainerZ), Vector3.new(L.TrainerSpots["1"].X + L.TrainerSize / 2 + 1, 0, trainerZ))

	-- Lanterns on both sides of the main path.
	local z = zStart - 6
	while z > zEnd + 4 do
		if math.abs(z - F.Offset.Z) > F.PlazaRadius + 2 then
			lantern(root, at(Vector3.new(-half - 2, 0, z)))
			lantern(root, at(Vector3.new(half + 2, 0, z)))
		end
		z -= L.LanternSpacing
	end
end

---------------------------------------------------------------------
-- Portal + guide NPC
---------------------------------------------------------------------

local function buildPortal()
	local P = L.Portal
	local model = Instance.new("Model")
	model.Name = "Portal"
	model.Parent = root
	local pos = at(P.Offset)
	local pillarW = 4
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(pillarW, P.ArchHeight, 6), CFrame.new(pos + Vector3.new(side * (P.ArchWidth / 2 - pillarW / 2), P.ArchHeight / 2, 0)), T.StoneDark)
		WorldKit.Torch(model, pos + Vector3.new(side * (P.ArchWidth / 2 + 3), 0, 3), T.Magenta)
	end
	local lintel = WorldKit.Brick(model, Vector3.new(P.ArchWidth, 5, 6), CFrame.new(pos + Vector3.new(0, P.ArchHeight + 2.5, 0)), T.StoneLight, "Lintel")
	WorldKit.SurfaceText(lintel, Enum.NormalId.Back, { { Text = Texts.Portal, Size = 70, Color = T.Gold } }, 50)
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(2, 2, 2), CFrame.new(pos + Vector3.new(side * (P.ArchWidth / 2 - 1), P.ArchHeight + 6, 0)), T.StoneDark, "Merlon")
	end
	-- Steps up to the portal.
	WorldKit.Brick(model, Vector3.new(P.ArchWidth + 4, 0.6, 10), CFrame.new(pos + Vector3.new(0, 0.3, 4)), T.StoneDark, "Step")

	local disc = WorldKit.Part(model, {
		Name = "PortalDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, P.Radius * 2, P.Radius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, P.Radius + 1, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Color = T.Magenta,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		CanCollide = false,
	})
	local ring = WorldKit.Part(model, {
		Name = "PortalRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, P.Radius * 2 + 2, P.Radius * 2 + 2),
		CFrame = disc.CFrame,
		Color = T.Purple,
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		CanCollide = false,
		CanQuery = false,
	})
	TweenService:Create(disc, TweenInfo.new(P.SpinSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = disc.CFrame * CFrame.Angles(math.rad(180), 0, 0) }):Play()
	TweenService:Create(ring, TweenInfo.new(P.SpinSeconds * 1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = ring.CFrame * CFrame.Angles(math.rad(-180), 0, 0) }):Play()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(T.Magenta, T.Cyan)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.Rate = 18
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = disc
	WorldKit.Light(disc, T.Magenta, 24, 1.2)
	disc:SetAttribute("Portal", true)
	return disc
end

local function buildNpc()
	local cf = frame(L.Npc.Offset, SOUTH) -- faces the spawn
	local model = Instance.new("Model")
	model.Name = "Guide"
	model.Parent = root
	local skin = Color3.fromRGB(255, 205, 150)
	WorldKit.Brick(model, Vector3.new(2, 2, 1), cf * CFrame.new(0, 3, 0), T.Cyan, "Torso")
	local head = WorldKit.Brick(model, Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(0, 4.7, 0), skin, "Head")
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	for _, side in ipairs({ -1, 1 }) do
		-- one arm points north, at the portal
		WorldKit.Brick(model, Vector3.new(0.9, 2, 0.9), cf * CFrame.new(side * 1.45, 3, 0) * CFrame.Angles(if side > 0 then math.rad(-110) else 0, 0, 0), skin, "Arm")
		WorldKit.Brick(model, Vector3.new(0.9, 2, 0.9), cf * CFrame.new(side * 0.5, 1, 0), Color3.fromRGB(60, 50, 90), "Leg")
	end
	WorldKit.Brick(model, Vector3.new(2.2, 0.6, 2.2), cf * CFrame.new(0, 5.6, 0), T.Gold, "Hat")
	sign(model, cf * CFrame.new(0, 7.2, 0), Vector3.new(7.5, 1.9, 0.3), { { Text = Texts.Npc, Size = 40, Color = T.Gold } }, true)
end

---------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------

-- One trainer = a square territory (the server gives Aura to whoever
-- stands inside it), the big object at its back, a sign at eye height
-- beside it and a lock box the client shows per player.
local function buildTrainer(parent, def)
	local offset = L.TrainerSpots[def.Id]
	local pos = at(offset)
	local dir = if offset.X < 0 then EAST else WEST -- faces the main path
	local cf = frame(offset, dir)
	local S = L.TrainerSize

	local model = Instance.new("Model")
	model.Name = "Trainer_" .. def.Id

	WorldKit.Part(model, {
		Name = "Platform",
		Size = Vector3.new(S, 0.6, S),
		Position = pos + Vector3.new(0, 0.3, 0),
		Color = def.Color,
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
	})
	WorldKit.Part(model, {
		Name = "Rim",
		Size = Vector3.new(S + 1.2, 0.3, S + 1.2),
		Position = pos + Vector3.new(0, 0.15, 0),
		Color = def.Color:Lerp(Color3.new(0, 0, 0), 0.45),
	})
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			WorldKit.Brick(model, Vector3.new(1, 1.4, 1), CFrame.new(pos + Vector3.new(dx * (S / 2 + 0.1), 0.7, dz * (S / 2 + 0.1))), if def.Premium then T.Gold else T.StoneDark, "Post")
		end
	end

	-- The object sits at the back of the territory, facing the path.
	local object = TrainerBuilder.Build(def, cf * CFrame.new(0, 0.6, S / 2 - 3))
	object.Name = "Object"
	object.Parent = model
	model.PrimaryPart = model.Platform
	model:SetAttribute("TrainerId", def.Id)
	model:SetAttribute("Multiplier", def.Multiplier)
	model:SetAttribute("Center", pos)
	model:SetAttribute("Half", S / 2)

	-- Requirement line (the client repaints it per player: HubFx).
	local reqText = Texts.TrainerOpen
	if def.Pass then
		local pass = Config.GamePasses[def.Pass]
		reqText = if pass and pass.Id > 0 then Texts.TrainerLockedPass:format(pass.Price) else Texts.TrainerSoon
		model:SetAttribute("RequirePass", def.Pass)
	elseif def.Rebirths then
		reqText = Texts.TrainerLockedRebirth:format(def.Rebirths)
		model:SetAttribute("RequireRebirths", def.Rebirths)
	elseif def.Aura then
		reqText = Texts.TrainerLockedAura:format(Format.Number(def.Aura))
		model:SetAttribute("RequireAura", def.Aura)
	end
	model:SetAttribute("RequireText", reqText)

	-- Sign: vertical board at eye height beside the territory (south
	-- side, in the gap between two trainers), facing the path.
	local signCf = CFrame.lookAt(pos + Vector3.new(0, 0, S / 2 + 4), pos + Vector3.new(0, 0, S / 2 + 4) + dir)
	part(model, "SignPole", Vector3.new(0.5, 2.6, 0.5), signCf * CFrame.new(0, 1.3, 0), WOOD_DARK, Enum.Material.Wood)
	sign(model, signCf * CFrame.new(0, 4.6, 0), Vector3.new(7.4, 4.2, 0.4), {
		{ Name = "Mult", Text = Texts.Trainer:format(tostring(def.Multiplier)) .. " Аура", Size = 56, Color = T.Gold },
		{ Name = "Title", Text = def.Name, Size = 26 },
		{ Name = "Req", Text = reqText, Size = 26, Color = T.Green },
	})

	-- Lock: invisible on the server; a locked-out client makes it solid.
	WorldKit.Part(model, {
		Name = "Lock",
		Size = Vector3.new(S + 0.4, 12, S + 0.4),
		Position = pos + Vector3.new(0, 6.6, 0),
		Color = Color3.fromRGB(60, 50, 80),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})

	model.Parent = parent
	return model
end

---------------------------------------------------------------------
-- Forge (the main visual object of the hub)
---------------------------------------------------------------------

local function buildForge(parent)
	local F = L.Forge
	local cf = frame(F.Offset, WEST) -- the open front faces the main path
	local model = Instance.new("Model")
	model.Name = "Forge"
	model.Parent = parent
	local brickA = Color3.fromRGB(150, 92, 72)
	local brickB = Color3.fromRGB(128, 76, 60)
	local roofColor = Color3.fromRGB(96, 52, 48)
	local stone = Color3.fromRGB(92, 88, 104)

	-- Shell: floor, back wall, side walls (front third open), posts, beam.
	WorldKit.Brick(model, Vector3.new(36, 0.6, 30), cf * CFrame.new(0, 0.3, 0), stone, "Floor")
	WorldKit.Brick(model, Vector3.new(36, 14, 2), cf * CFrame.new(0, 7, 14), brickA, "BackWall")
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(2, 14, 20), cf * CFrame.new(side * 17, 7, 4), brickB, "SideWall")
		part(model, "Post", Vector3.new(2.4, 14, 2.4), cf * CFrame.new(side * 17, 7, -13.6), WOOD_DARK, Enum.Material.Wood)
		-- stepped gable
		for i = 1, 3 do
			WorldKit.Brick(model, Vector3.new(2, 2.4, 30 - i * 8), cf * CFrame.new(side * 17, 14 + (i - 0.5) * 2.4, 0), if i % 2 == 0 then brickA else brickB, "Gable")
		end
	end
	part(model, "Beam", Vector3.new(36, 2, 2.4), cf * CFrame.new(0, 13, -13.6), WOOD_DARK, Enum.Material.Wood)
	-- Roof: two slopes meeting at the ridge.
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Roof", Vector3.new(39, 1, 18.6), cf * CFrame.new(0, 17.9, side * 8.3) * CFrame.Angles(math.rad(side * 24), 0, 0), roofColor, Enum.Material.Slate)
	end
	part(model, "Ridge", Vector3.new(39.4, 1, 1.6), cf * CFrame.new(0, 21.7, 0), WOOD_DARK, Enum.Material.Wood)

	-- Hearth (горн) with chimney: fire, smoke and sparks.
	WorldKit.Brick(model, Vector3.new(12, 8, 6), cf * CFrame.new(-8, 4, 10), stone, "HearthBody")
	part(model, "Hood", Vector3.new(13, 2, 7), cf * CFrame.new(-8, 9, 9.6), IRON, Enum.Material.Metal)
	part(model, "Mouth", Vector3.new(7, 3.6, 0.6), cf * CFrame.new(-8, 3.2, 6.9), Color3.fromRGB(25, 18, 20))
	part(model, "Coals", Vector3.new(6, 0.8, 1.6), cf * CFrame.new(-8, 1.9, 6.6), Color3.fromRGB(60, 30, 25), Enum.Material.Slate)
	local hearth = part(model, "Hearth", Vector3.new(5, 1.2, 1), cf * CFrame.new(-8, 2.7, 6.5), T.Orange, Enum.Material.Neon, { CanCollide = false })
	local fire = Instance.new("Fire")
	fire.Name = "Fire"
	fire.Color = T.Orange
	fire.SecondaryColor = T.Gold
	fire.Size = 7
	fire.Heat = 12
	fire.Parent = hearth
	WorldKit.Light(hearth, Color3.fromRGB(255, 160, 80), 26, 1.6).Name = "Glow"
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(T.Gold, T.Orange)
	sparks.LightEmission = 0.8
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.Acceleration = Vector3.new(0, 6, 0)
	sparks.Rate = 8
	sparks.Parent = hearth
	WorldKit.Brick(model, Vector3.new(5, 15, 5), cf * CFrame.new(-8, 15.5, 11), stone, "Chimney")
	local chimneyTop = part(model, "ChimneyTop", Vector3.new(6, 1, 6), cf * CFrame.new(-8, 23.5, 11), Color3.fromRGB(70, 66, 80), Enum.Material.Slate)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 115, 125)
	smoke.Opacity = 0.25
	smoke.RiseVelocity = 6
	smoke.Size = 3
	smoke.Parent = chimneyTop
	-- Bellows and coal.
	part(model, "Bellows", Vector3.new(3, 1.6, 4.4), cf * CFrame.new(0.6, 1.6, 9.4) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(140, 90, 50), Enum.Material.Fabric)
	part(model, "BellowsNozzle", Vector3.new(0.6, 0.6, 2), cf * CFrame.new(-1.2, 1.6, 8.4) * CFrame.Angles(0, math.rad(70), 0), IRON, Enum.Material.Metal)
	for i = 1, 4 do
		part(model, "Coal", Vector3.new(1.6, 1.2, 1.6), cf * CFrame.new(-15 + (i % 2) * 1.3, 0.9 + math.floor(i / 3) * 0.9, 4 + i * 0.9) * CFrame.Angles(0, i, 0), Color3.fromRGB(35, 32, 40), Enum.Material.Slate)
	end

	-- Anvil with the hammer: the ProximityPrompt lives here.
	part(model, "AnvilBlock", Vector3.new(3.4, 1.4, 2.6), cf * CFrame.new(3, 1.3, -3), WOOD, Enum.Material.Wood)
	part(model, "AnvilWaist", Vector3.new(1.6, 1, 1.4), cf * CFrame.new(3, 2.5, -3), IRON, Enum.Material.Metal)
	local anvil = part(model, "Anvil", Vector3.new(4.4, 1, 2), cf * CFrame.new(3, 3.5, -3), Color3.fromRGB(58, 58, 70), Enum.Material.Metal)
	part(model, "AnvilHorn", Vector3.new(1.8, 0.6, 1.2), cf * CFrame.new(6, 3.6, -3), Color3.fromRGB(58, 58, 70), Enum.Material.Metal)
	part(model, "HammerHandle", Vector3.new(0.35, 2.8, 0.35), cf * CFrame.new(2, 4.5, -3) * CFrame.Angles(0, 0, math.rad(62)), WOOD, Enum.Material.Wood, { CanCollide = false })
	part(model, "HammerHead", Vector3.new(1.4, 1, 1), cf * CFrame.new(3.3, 5.15, -3) * CFrame.Angles(0, 0, math.rad(62)), IRON, Enum.Material.Metal, { CanCollide = false })
	local anvilSparks = sparks:Clone()
	anvilSparks.Name = "Sparks"
	anvilSparks.Rate = 0
	anvilSparks.SpreadAngle = Vector2.new(70, 70)
	anvilSparks.Speed = NumberRange.new(8, 16)
	anvilSparks.Parent = anvil

	-- Props: quench barrel, crates, tool rack.
	local barrel = part(model, "Barrel", Vector3.new(3.2, 3, 3), cf * CFrame.new(9, 2.1, -6) * CFrame.Angles(0, 0, math.rad(90)), WOOD, Enum.Material.Wood)
	barrel.Shape = Enum.PartType.Cylinder
	local water = part(model, "Water", Vector3.new(0.2, 2.6, 2.6), cf * CFrame.new(9, 3.55, -6) * CFrame.Angles(0, 0, math.rad(90)), T.Cyan, Enum.Material.Glass, { Transparency = 0.3, CanCollide = false })
	water.Shape = Enum.PartType.Cylinder
	part(model, "Crate", Vector3.new(3, 3, 3), cf * CFrame.new(-14, 2.1, -9), Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
	part(model, "Crate", Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(-13.6, 4.7, -9.2) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(165, 118, 72), Enum.Material.WoodPlanks)

	-- Showcase racks: craftable weapons on the left, armor stands on the right.
	part(model, "WeaponRack", Vector3.new(0.6, 6, 13), cf * CFrame.new(-15.6, 5.4, -1), WOOD_DARK, Enum.Material.WoodPlanks)
	for i, weaponId in ipairs(F.SampleWeapons) do
		local weapon = Config.ItemById.Weapon[weaponId]
		if weapon then
			local sample = WeaponBuilder.Build(weapon)
			sample.Name = "Sample_" .. weaponId
			WeaponBuilder.SetAnchored(sample, true)
			sample:PivotTo(cf * CFrame.new(-14.9, 3.1, -6.5 + i * 2.7) * CFrame.Angles(0, math.rad(90), 0))
			sample.Parent = model
		end
	end
	local stands = Instance.new("Folder")
	stands.Name = "ArmorStands"
	stands.Parent = model
	for i = 1, 3 do
		local standCf = cf * CFrame.new(14, 0.6, -8 + i * 5) * CFrame.Angles(0, math.rad(-90), 0)
		local stand = Instance.new("Model")
		stand.Name = "ArmorStand" .. i
		stand.Parent = stands
		part(stand, "Foot", Vector3.new(2, 0.4, 2), standCf * CFrame.new(0, 0.2, 0), WOOD_DARK, Enum.Material.Wood)
		part(stand, "Pole", Vector3.new(0.4, 2, 0.4), standCf * CFrame.new(0, 1.2, 0), WOOD_DARK, Enum.Material.Wood)
		part(stand, "Legs", Vector3.new(1.9, 2, 0.9), standCf * CFrame.new(0, 2, 0), WOOD, Enum.Material.Wood)
		part(stand, "Torso", Vector3.new(2, 2, 1), standCf * CFrame.new(0, 4, 0), WOOD, Enum.Material.Wood)
		part(stand, "Head", Vector3.new(1.2, 1.2, 1.2), standCf * CFrame.new(0, 5.6, 0), WOOD, Enum.Material.Wood)
		stand:SetAttribute("Frame", standCf)
	end

	lantern(model, (cf * CFrame.new(-21, 0, -17)).Position)
	lantern(model, (cf * CFrame.new(21, 0, -17)).Position)
	sign(model, cf * CFrame.new(0, 10.4, -15), Vector3.new(17, 3.6, 0.4), { { Text = Texts.Forge, Size = 60, Color = T.Gold } })
	zoneSign(parent, F.SignOffset, WEST, Texts.Forge, T.Orange)
	local prompt = WorldKit.Prompt(anvil, L.Prompts.Forge, "", { Action = "OpenForge" }, 16)
	return prompt, model
end

---------------------------------------------------------------------
-- Premium showcase, altar, wheel, eggs, leaderboards, fountain
---------------------------------------------------------------------

local function buildStore(parent)
	local cf = frame(L.Store.Offset, WEST)
	local model = Instance.new("Model")
	model.Name = "Store"
	model.Parent = parent
	local counter = WorldKit.Brick(model, Vector3.new(6, 3, 4), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(70, 50, 110), "Counter")
	part(model, "Top", Vector3.new(6.6, 0.4, 4.6), cf * CFrame.new(0, 3.2, 0), T.Gold, Enum.Material.Metal)
	local gem = part(model, "Gem", Vector3.new(1.6, 1.6, 1.6), cf * CFrame.new(0, 5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), T.Cyan, Enum.Material.Glass, { CanCollide = false, Transparency = 0.1 })
	TweenService:Create(gem, TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = gem.CFrame * CFrame.Angles(0, math.rad(180), 0) }):Play()
	WorldKit.Light(gem, T.Cyan, 12, 1)
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Pole", Vector3.new(0.5, 8, 0.5), cf * CFrame.new(side * 3.2, 4, 1.6), T.Gold, Enum.Material.Metal)
	end
	for i = 0, 3 do
		part(model, "Awning", Vector3.new(1.75, 0.3, 5), cf * CFrame.new(-2.63 + i * 1.75, 8.1, 0) * CFrame.Angles(math.rad(10), 0, 0), if i % 2 == 0 then T.Gold else T.Panel, nil, { CanCollide = false })
	end
	sign(model, cf * CFrame.new(0, 1.6, -2.05), Vector3.new(5.6, 2, 0.1), { { Text = Texts.Store, Size = 44, Color = T.Gold }, { Text = "Robux", Size = 22 } })
	zoneSign(parent, L.Store.SignOffset, WEST, Texts.Premium, T.Gold)
	return WorldKit.Prompt(counter, L.Prompts.Store, "", { Action = "OpenStore" }, 12)
end

local function buildAltar(parent)
	local cf = frame(L.Altar.Offset, WEST)
	local pos = cf.Position
	local model = Instance.new("Model")
	model.Name = "Altar"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(14, 2, 14), CFrame.new(pos + Vector3.new(0, 1, 0)), T.StoneDark, "Base")
	WorldKit.Brick(model, Vector3.new(10, 1.5, 10), CFrame.new(pos + Vector3.new(0, 2.75, 0)), T.StoneLight, "Step")
	local crystal = WorldKit.Part(model, {
		Name = "Crystal",
		Size = Vector3.new(3.2, 8, 3.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = T.Purple,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
	})
	part(model, "CrystalCore", Vector3.new(1.2, 5, 1.2), crystal.CFrame, T.Magenta, Enum.Material.Neon, { CanCollide = false })
	TweenService:Create(crystal, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = crystal.CFrame * CFrame.Angles(0, math.rad(180), 0) }):Play()
	WorldKit.Light(crystal, T.Purple, 22, 1.4)
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local p = pos + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
		WorldKit.Brick(model, Vector3.new(2, 7, 2), CFrame.new(p + Vector3.new(0, 3.5, 0)), T.StoneB, "Pillar")
		WorldKit.Part(model, { Name = "Rune", Size = Vector3.new(1, 2.4, 0.2), CFrame = CFrame.lookAt(p + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0)) * CFrame.new(0, 0, -1.05), Color = T.Magenta, Material = Enum.Material.Neon, CanCollide = false })
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(T.Purple, T.Magenta)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Rate = 14
	emitter.Parent = crystal
	zoneSign(parent, L.Altar.Offset + Vector3.new(-10, 0, 9), WEST, Texts.Altar, T.Purple:Lerp(Color3.new(1, 1, 1), 0.45))
	return WorldKit.Prompt(crystal, L.Prompts.Rebirth, "", { Action = "RebirthAltar" }, 16)
end

local function buildWheel(parent)
	local cf = frame(L.Wheel.Offset, EAST)
	local model = Instance.new("Model")
	model.Name = "Wheel"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(12, 12, 2), cf * CFrame.new(0, 6, 2), T.StoneB, "Board")
	-- Everything that turns is one model the client pivots around the disc.
	local spin = Instance.new("Model")
	spin.Name = "Spin"
	spin.Parent = model
	local disc = WorldKit.Part(spin, {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 9, 9),
		CFrame = cf * CFrame.new(0, 6, 0.6) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(250, 246, 255),
	})
	spin.PrimaryPart = disc
	local colors = { T.Magenta, T.Gold, T.Cyan, T.Green, T.Purple, T.Orange, T.Red, T.Blue }
	for i = 0, 7 do
		local angle = i * math.pi / 4
		WorldKit.Part(spin, {
			Name = "Peg",
			Size = Vector3.new(1.2, 2.6, 0.5),
			CFrame = cf * CFrame.new(math.cos(angle) * 3.2, 6 + math.sin(angle) * 3.2, 0.1) * CFrame.Angles(0, 0, angle + math.rad(90)),
			Color = colors[i + 1],
			CanCollide = false,
		})
	end
	WorldKit.Part(model, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.6, 1.6), CFrame = cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.rad(90), 0), Color = T.Gold })
	WorldKit.Part(model, { Name = "Pointer", Size = Vector3.new(0.8, 1.6, 0.6), CFrame = cf * CFrame.new(0, 11.2, 0.1), Color = T.Red })
	sign(model, cf * CFrame.new(0, 13.6, 1), Vector3.new(12, 2.8, 0.4), { { Text = Texts.Wheel, Size = 44, Color = T.Gold }, { Name = "Status", Text = Texts.WheelFree, Size = 26, Color = T.Green } })
	model:SetAttribute("Wheel", true)
	return WorldKit.Prompt(disc, L.Prompts.Wheel, "", { Action = "Wheel" }, 14)
end

local function buildEgg(parent)
	local cf = frame(L.Egg.Offset, EAST)
	local model = Instance.new("Model")
	model.Name = "Egg"
	model.Parent = parent
	local ped = WorldKit.Brick(model, Vector3.new(6, 3, 6), cf * CFrame.new(0, 1.5, 0), T.StoneDark, "Pedestal")
	part(model, "Nest", Vector3.new(4.6, 0.8, 4.6), cf * CFrame.new(0, 3.3, 0), Color3.fromRGB(190, 150, 90), Enum.Material.Fabric)
	local egg = WorldKit.Part(model, { Name = "EggShell", Shape = Enum.PartType.Ball, Size = Vector3.new(3.5, 4.5, 3.5), CFrame = cf * CFrame.new(0, 5.6, 0), Color = Color3.fromRGB(255, 240, 250) })
	for i = 1, 5 do
		local angle = i * math.pi * 2 / 5
		WorldKit.Part(model, { Name = "Spot", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = cf * CFrame.new(math.cos(angle) * 1.5, 5.6 + math.sin(i) * 0.8, math.sin(angle) * 1.5), Color = if i % 2 == 0 then T.Magenta else T.Cyan, CanCollide = false })
	end
	TweenService:Create(egg, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = egg.Position + Vector3.new(0, 0.4, 0) }):Play()
	zoneSign(parent, L.Egg.Offset + Vector3.new(7, 0, 7), EAST, Texts.Pets, T.Magenta:Lerp(Color3.new(1, 1, 1), 0.4))
	return WorldKit.Prompt(ped, L.Prompts.Egg, "", { Action = "OpenPets" }, 14)
end

local function buildLeaderboards(parent)
	local boards = {}
	for _, def in ipairs(L.Leaderboards) do
		local cf = frame(def.Offset, EAST)
		for _, side in ipairs({ -1, 1 }) do
			part(parent, "BoardPost", Vector3.new(0.8, 16, 0.8), cf * CFrame.new(side * 8.2, 8, 0.3), WOOD_DARK, Enum.Material.Wood)
		end
		part(parent, "BoardFrame", Vector3.new(17, 14.6, 0.4), cf * CFrame.new(0, 8.6, 0.3), T.Gold, Enum.Material.Metal)
		local board = part(parent, "Leaderboard_" .. def.Kind, Vector3.new(16, 13.6, 0.6), cf * CFrame.new(0, 8.6, 0), T.PanelDark)
		local lines = { { Name = "Title", Text = def.Title, Size = 34, Color = T.Gold } }
		for i = 1, Config.Leaderboards.Top do
			table.insert(lines, { Name = "Row" .. i, Text = i .. ". —", Size = 18 })
		end
		boards[def.Kind] = WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 50)
	end
	return boards
end

local function buildFountain(parent)
	local F = L.Fountain
	local pos = at(F.Offset)
	local model = Instance.new("Model")
	model.Name = "Fountain"
	model.Parent = parent
	local flat = CFrame.Angles(0, 0, math.rad(90))
	WorldKit.Part(model, { Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, F.Radius * 2, F.Radius * 2), CFrame = CFrame.new(pos + Vector3.new(0, 0.8, 0)) * flat, Color = T.StoneDark })
	WorldKit.Part(model, { Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, F.Radius * 2 - 1.5, F.Radius * 2 - 1.5), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)) * flat, Color = T.Cyan, Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
	WorldKit.Brick(model, Vector3.new(2.4, 4, 2.4), CFrame.new(pos + Vector3.new(0, 3.5, 0)), T.StoneLight, "Column")
	WorldKit.Part(model, { Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 6, 6), CFrame = CFrame.new(pos + Vector3.new(0, 5.6, 0)) * flat, Color = T.StoneDark })
	local crystal = WorldKit.Part(model, { Name = "Crystal", Size = Vector3.new(1.8, 3.6, 1.8), CFrame = CFrame.new(pos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = T.Cyan, Material = Enum.Material.Glass, Transparency = 0.1 })
	TweenService:Create(crystal, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = crystal.CFrame * CFrame.Angles(0, math.rad(180), 0) }):Play()
	WorldKit.Light(crystal, T.Cyan, 18, 1)
	local splash = Instance.new("ParticleEmitter")
	splash.Color = ColorSequence.new(T.Cyan, Color3.new(1, 1, 1))
	splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	splash.Lifetime = NumberRange.new(0.8, 1.4)
	splash.Speed = NumberRange.new(8, 12)
	splash.SpreadAngle = Vector2.new(25, 25)
	splash.Rate = 20
	splash.Acceleration = Vector3.new(0, -20, 0)
	splash.Parent = crystal
end

---------------------------------------------------------------------
-- Decor
---------------------------------------------------------------------

local function buildTree(parent, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Tree"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(2, 6, 2), CFrame.new(position + Vector3.new(0, 3, 0)), WOOD, "Trunk")
	WorldKit.Brick(model, Vector3.new(8, 5, 8), CFrame.new(position + Vector3.new(0, 8, 0)), Color3.fromRGB(70, 190, 100), "Leaves")
	WorldKit.Brick(model, Vector3.new(5, 4, 5), CFrame.new(position + Vector3.new(0, 12, 0)), Color3.fromRGB(95, 215, 125), "Leaves")
end

local function buildBush(parent, position: Vector3)
	WorldKit.Brick(parent, Vector3.new(3, 2.2, 3), CFrame.new(position + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(80, 200, 110), "Bush")
	WorldKit.Brick(parent, Vector3.new(2, 1.6, 2), CFrame.new(position + Vector3.new(1.2, 1.2, 0.8)), Color3.fromRGB(100, 220, 130), "Bush")
end

local FLOWERS = { T.Magenta, T.Gold, T.Cyan, T.Red, Color3.new(1, 1, 1) }
local function buildFlowerBed(parent, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "FlowerBed"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(8, 1, 5), CFrame.new(position + Vector3.new(0, 0.5, 0)), T.StoneDark, "Border")
	part(model, "Soil", Vector3.new(7, 0.3, 4), CFrame.new(position + Vector3.new(0, 1.1, 0)), Color3.fromRGB(90, 60, 40), Enum.Material.Ground, { CanCollide = false })
	for i = 1, 6 do
		local fx = -3 + ((i - 1) % 3) * 3 + (if i > 3 then 0.8 else -0.6)
		local fz = if i > 3 then 1 else -1
		part(model, "Stem", Vector3.new(0.25, 1.4, 0.25), CFrame.new(position + Vector3.new(fx, 1.9, fz)), Color3.fromRGB(70, 160, 70), nil, { CanCollide = false })
		part(model, "Flower", Vector3.new(0.9, 0.7, 0.9), CFrame.new(position + Vector3.new(fx, 2.8, fz)) * CFrame.Angles(0, i, 0), FLOWERS[(i - 1) % #FLOWERS + 1], nil, { CanCollide = false })
	end
end

local function buildBench(parent, offset: Vector3, dir: Vector3)
	local cf = frame(offset, dir)
	local model = Instance.new("Model")
	model.Name = "Bench"
	model.Parent = parent
	part(model, "Seat", Vector3.new(6, 0.5, 2), cf * CFrame.new(0, 1.6, 0), WOOD, Enum.Material.WoodPlanks)
	part(model, "Back", Vector3.new(6, 1.6, 0.4), cf * CFrame.new(0, 2.8, 0.9) * CFrame.Angles(math.rad(-8), 0, 0), WOOD, Enum.Material.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Leg", Vector3.new(0.5, 1.4, 1.8), cf * CFrame.new(side * 2.5, 0.7, 0), IRON, Enum.Material.Metal)
	end
end

---------------------------------------------------------------------

function HubGenerator.Build()
	root = Instance.new("Folder")
	root.Name = "Hub"
	local trainers = Instance.new("Folder")
	trainers.Name = "Trainers"
	trainers.Parent = root

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y + spawn.Size.Y / 2 else 0
	base = Vector3.new(origin.X, groundY, origin.Z)

	buildCourtyard()
	buildPaths()
	local portal = buildPortal()
	buildNpc()

	for _, def in ipairs(Config.Trainers) do
		buildTrainer(trainers, def)
	end
	zoneSign(root, Vector3.new(-25, 0, L.TrainerSpots["1"].Z + 13), EAST, Texts.Trainers, T.Green)

	local forgePrompt, forge = buildForge(root)
	local storePrompt = buildStore(root)
	local altarPrompt = buildAltar(root)
	local wheelPrompt = buildWheel(root)
	local eggPrompt = buildEgg(root)
	local boards = buildLeaderboards(root)
	buildFountain(root)
	for _, offset in ipairs(L.Trees) do
		buildTree(root, at(offset))
	end
	for _, offset in ipairs(L.Bushes) do
		buildBush(root, at(offset))
	end
	for _, offset in ipairs(L.FlowerBeds) do
		buildFlowerBed(root, at(offset))
	end
	for _, bench in ipairs(L.Benches) do
		buildBench(root, bench.Offset, bench.Facing)
	end

	root:SetAttribute("Center", base + L.Center)
	root.Parent = Workspace
	return {
		Folder = root,
		Trainers = trainers,
		Portal = portal,
		Forge = forge,
		ForgePrompt = forgePrompt,
		StorePrompt = storePrompt,
		AltarPrompt = altarPrompt,
		WheelPrompt = wheelPrompt,
		EggPrompt = eggPrompt,
		Leaderboards = boards,
		SpawnCFrame = CFrame.lookAt(base + Vector3.new(0, 4, 0), base + Vector3.new(0, 4, -10)),
		GroundY = base.Y,
	}
end

return HubGenerator
