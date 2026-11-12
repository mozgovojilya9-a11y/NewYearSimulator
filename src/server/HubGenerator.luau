--[[
	HubGenerator.luau
	Builds the hub, "Цитадель Ауры", around the SpawnLocation at
	server start (Workspace.Hub). Pure construction from Parts; the
	prompts it creates are wired by HubService.

	Layout (looking forward from the spawn = -Z):
	  center: purple path with yellow chevrons -> dungeon portal arch
	  left:   row of 8 trainer platforms (chevrons lead there first)
	  back:   rebirth altar, shop stall, wheel of fortune, pet egg,
	          two leaderboards on the wall, fountain in the middle
	  around: castle walls, corner towers, flags, torches, trees, bushes,
	          an NPC pointing at the dungeon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local TrainerBuilder = require(script.Parent.TrainerBuilder)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local L = Config.HubLayout
local T = Config.Theme
local Texts = L.Texts

local root, base

local function at(offset: Vector3): Vector3
	return base + offset
end

local function sign(parent, position: Vector3, size: Vector3, lines, faces)
	local part = WorldKit.Part(parent, { Name = "Sign", Size = size, CFrame = CFrame.new(position), Color = T.PanelDark, CanCollide = false })
	for _, face in ipairs(faces or { Enum.NormalId.Front }) do
		WorldKit.SurfaceText(part, face, lines, 50)
	end
	return part
end

---------------------------------------------------------------------
-- Courtyard, walls, towers
---------------------------------------------------------------------

local function buildCourtyard()
	local half = L.Size / 2
	WorldKit.TiledFloor(root, base - Vector3.new(0, 0.05, 0), L.Size, L.Size, L.TileSize, T.TileA, T.TileB, 196)
	WorldKit.Part(root, {
		Name = "Grass",
		Size = Vector3.new(L.Size * 2.5, 1, L.Size * 2.5),
		Position = base + Vector3.new(0, -0.6, 0),
		Color = T.Grass,
		Material = Enum.Material.Grass,
	})

	local corners = {
		Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half), Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		local gap = if i == 1 then { Center = half, Width = L.Portal.ArchWidth + 2 } else nil
		WorldKit.CastleWall(root, at(corners[i]), at(corners[i % 4 + 1]), L.WallHeight, L.WallThickness, T.StoneA, T.StoneB, L.MerlonSize, gap, T.StoneLight)
	end

	for i, c in ipairs(corners) do
		local tower = Instance.new("Model")
		tower.Name = "Tower" .. i
		tower.Parent = root
		local pos = at(c)
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
	-- Map bounds: invisible walls on the wall line (they also close the
	-- gap behind the portal arch) up to HubWallExtra above the walls, + lid.
	local bounds = Instance.new("Model")
	bounds.Name = "Bounds"
	bounds.Parent = root
	local B = Config.Bounds
	local t = L.WallThickness
	local boundH = L.WallHeight + B.HubWallExtra + 2
	local span = L.Size + t + B.Overlap * 2
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Invisible(bounds, Vector3.new(span, boundH, t), base + Vector3.new(0, boundH / 2 - 1, side * half))
		WorldKit.Invisible(bounds, Vector3.new(t, boundH, span), base + Vector3.new(side * half, boundH / 2 - 1, 0))
	end
	WorldKit.Invisible(bounds, Vector3.new(span, 2, span), base + Vector3.new(0, boundH, 0), "Lid")

	-- Flags along the walls too.
	for i = -2, 2 do
		for _, zSide in ipairs({ -1, 1 }) do
			local pos = at(Vector3.new(i * 30, L.WallHeight + 2, zSide * (half - 2)))
			WorldKit.Part(root, { Name = "Pole", Size = Vector3.new(0.3, 6, 0.3), Position = pos + Vector3.new(0, 3, 0), Color = T.StoneDark })
			WorldKit.Part(root, { Name = "Flag", Size = Vector3.new(3, 2, 0.2), Position = pos + Vector3.new(1.6, 5, 0), Color = if (i + zSide) % 2 == 0 then T.Gold else T.Magenta, CanCollide = false })
		end
	end
end

---------------------------------------------------------------------
-- Paths and chevrons
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

local function buildPaths()
	-- Main path: spawn -> portal.
	local zStart = 12
	local zEnd = L.Portal.Offset.Z + L.Portal.Radius
	WorldKit.Part(root, {
		Name = "Path",
		Size = Vector3.new(L.PathWidth, 0.2, zStart - zEnd),
		Position = at(Vector3.new(0, 0.08, (zStart + zEnd) / 2)),
		Color = T.Path,
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
	})
	-- Chevrons: spawn -> the first trainer, and spawn -> portal.
	local first = L.TrainerSpots["1"]
	chevronLine(Vector3.new(-L.PathWidth / 2, 0, 2), Vector3.new(first.X + L.TrainerSize / 2 + 2, 0, first.Z))
	chevronLine(Vector3.new(0, 0, 4), Vector3.new(0, 0, zEnd + 6))

	for i = 1, L.TorchesAlongPath do
		local tz = zStart - (i / (L.TorchesAlongPath + 1)) * (zStart - zEnd)
		WorldKit.Torch(root, at(Vector3.new(-L.PathWidth / 2 - 2, 0, tz)))
		WorldKit.Torch(root, at(Vector3.new(L.PathWidth / 2 + 2, 0, tz)))
	end
end

---------------------------------------------------------------------
-- Portal + NPC
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
	end
	local lintel = WorldKit.Brick(model, Vector3.new(P.ArchWidth, 5, 6), CFrame.new(pos + Vector3.new(0, P.ArchHeight + 2.5, 0)), T.StoneLight, "Lintel")
	WorldKit.SurfaceText(lintel, Enum.NormalId.Back, { { Text = Texts.Portal, Size = 70, Color = T.Gold } }, 50)
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(2, 2, 2), CFrame.new(pos + Vector3.new(side * (P.ArchWidth / 2 - 1), P.ArchHeight + 6, 0)), T.Magenta, "Merlon")
	end

	local disc = WorldKit.Part(model, {
		Name = "PortalDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, P.Radius * 2, P.Radius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, P.Radius + 1, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Color = T.Magenta,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
	})
	local ring = WorldKit.Part(model, {
		Name = "PortalRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, P.Radius * 2 + 2, P.Radius * 2 + 2),
		CFrame = disc.CFrame,
		Color = T.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
	})
	TweenService:Create(disc, TweenInfo.new(P.SpinSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = disc.CFrame * CFrame.Angles(math.rad(180), 0, 0) }):Play()
	TweenService:Create(ring, TweenInfo.new(P.SpinSeconds * 1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = ring.CFrame * CFrame.Angles(math.rad(-180), 0, 0) }):Play()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(T.Magenta, T.Cyan)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.Rate = 25
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = disc
	WorldKit.Light(disc, T.Magenta, 30, 2)
	disc:SetAttribute("Portal", true)
	return disc
end

local function buildNpc()
	local pos = at(L.Npc.Offset)
	local model = Instance.new("Model")
	model.Name = "Guide"
	model.Parent = root
	local cf = CFrame.lookAt(pos, Vector3.new(base.X, pos.Y, base.Z))
	local skin = Color3.fromRGB(255, 205, 150)
	local shirt = T.Cyan
	WorldKit.Brick(model, Vector3.new(2, 2, 1), cf * CFrame.new(0, 3, 0), shirt, "Torso")
	local head = WorldKit.Brick(model, Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(0, 4.7, 0), skin, "Head")
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(0.9, 2, 0.9), cf * CFrame.new(side * 1.45, 3, 0) * CFrame.Angles(if side > 0 then math.rad(-70) else 0, 0, 0), skin, "Arm")
		WorldKit.Brick(model, Vector3.new(0.9, 2, 0.9), cf * CFrame.new(side * 0.5, 1, 0), Color3.fromRGB(60, 50, 90), "Leg")
	end
	WorldKit.Brick(model, Vector3.new(2.2, 0.6, 2.2), cf * CFrame.new(0, 5.6, 0), T.Gold, "Hat")
	sign(model, pos + Vector3.new(0, 7.5, 0), Vector3.new(7, 1.8, 0.3), { { Text = Texts.Npc, Size = 40, Color = T.Gold } }, { Enum.NormalId.Front, Enum.NormalId.Back })
end

---------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------

-- One trainer = a square territory (the server gives Aura to whoever
-- stands inside it), the big object at its back, a sign at eye height
-- between the platforms and a lock box the client shows per player.
local function buildTrainer(parent, def)
	local pos = at(L.TrainerSpots[def.Id])
	local dirX = if pos.X < base.X then 1 else -1 -- faces the main path
	local front = Vector3.new(dirX, 0, 0)
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
	local objectPos = pos - front * (S / 2 - 3) + Vector3.new(0, 0.6, 0)
	local object = TrainerBuilder.Build(def, CFrame.lookAt(objectPos, objectPos + front))
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

	-- Sign: vertical board at eye height beside the platform, facing the path.
	local signPos = pos + Vector3.new(0, 0, S / 2 + 4)
	WorldKit.Part(model, { Name = "SignPole", Size = Vector3.new(0.5, 2.6, 0.5), Position = signPos + Vector3.new(0, 1.3, 0), Color = T.StoneDark })
	local board = sign(model, signPos + Vector3.new(0, 4.6, 0), Vector3.new(0.4, 4.2, 7.4), {
		{ Name = "Mult", Text = Texts.Trainer:format(tostring(def.Multiplier)) .. " Аура", Size = 56, Color = T.Gold },
		{ Name = "Title", Text = def.Name, Size = 26 },
		{ Name = "Req", Text = reqText, Size = 26, Color = T.Green },
	}, { if dirX > 0 then Enum.NormalId.Right else Enum.NormalId.Left })
	board.Name = "Sign"

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
-- Back row: altar, stall, wheel, egg, leaderboards, fountain
---------------------------------------------------------------------

local function buildAltar(parent)
	local pos = at(L.Altar.Offset)
	local model = Instance.new("Model")
	model.Name = "Altar"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(14, 2, 14), CFrame.new(pos + Vector3.new(0, 1, 0)), T.StoneDark, "Base")
	WorldKit.Brick(model, Vector3.new(10, 1.5, 10), CFrame.new(pos + Vector3.new(0, 2.75, 0)), T.StoneLight, "Step")
	local crystal = WorldKit.Part(model, {
		Name = "Crystal",
		Size = Vector3.new(3.5, 9, 3.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = T.Purple,
		Material = Enum.Material.Neon,
	})
	TweenService:Create(crystal, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = crystal.CFrame * CFrame.Angles(0, math.rad(180), 0) }):Play()
	WorldKit.Light(crystal, T.Purple, 28, 2.5)
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local p = pos + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
		WorldKit.Brick(model, Vector3.new(2, 7, 2), CFrame.new(p + Vector3.new(0, 3.5, 0)), T.StoneB, "Pillar")
		WorldKit.Part(model, { Name = "Rune", Size = Vector3.new(1.2, 3, 0.2), CFrame = CFrame.lookAt(p + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0)) * CFrame.new(0, 0, -1.05), Color = T.Magenta, Material = Enum.Material.Neon, CanCollide = false })
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(T.Purple, T.Magenta)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Rate = 20
	emitter.Parent = crystal
	sign(model, pos + Vector3.new(0, 15, 0), Vector3.new(14, 2.4, 0.4), { { Text = Texts.Altar, Size = 44, Color = T.Purple } }, { Enum.NormalId.Front, Enum.NormalId.Back })
	return WorldKit.Prompt(crystal, L.Prompts.Rebirth, "Алтарь", { Action = "RebirthAltar" }, 14)
end

local function buildStall(parent)
	local pos = at(L.Shop.Offset)
	local model = Instance.new("Model")
	model.Name = "Shop"
	model.Parent = parent
	local counter = WorldKit.Brick(model, Vector3.new(14, 3.5, 4), CFrame.new(pos + Vector3.new(0, 1.75, 0)), Color3.fromRGB(150, 100, 60), "Counter")
	-- Workbench: anvil + tools on the counter.
	WorldKit.Part(model, { Name = "Anvil", Size = Vector3.new(2.4, 1.2, 1.2), Position = pos + Vector3.new(-3, 4.1, 0), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal })
	WorldKit.Part(model, { Name = "Hammer", Size = Vector3.new(0.3, 2, 0.3), CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(30)), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood })
	WorldKit.Part(model, { Name = "HammerHead", Size = Vector3.new(1.2, 0.7, 0.7), CFrame = CFrame.new(pos + Vector3.new(0.5, 5.3, 0)) * CFrame.Angles(0, 0, math.rad(30)), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Metal })
	for i, c in ipairs({ T.Green, T.Blue, T.Purple }) do
		WorldKit.Part(model, { Name = "Goods", Size = Vector3.new(1.3, 1.3, 1.3), Position = pos + Vector3.new(2 + i * 1.6, 4.2, 0), Color = c, Material = Enum.Material.Neon, CanCollide = false })
	end
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Part(model, { Name = "Post", Size = Vector3.new(0.6, 9, 0.6), Position = pos + Vector3.new(side * 6.5, 4.5, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood })
	end
	for i = 0, 6 do
		WorldKit.Part(model, {
			Name = "Awning",
			Size = Vector3.new(2, 0.4, 7),
			CFrame = CFrame.new(pos + Vector3.new(-6 + i * 2, 9.2, -1)) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = if i % 2 == 0 then T.Magenta else Color3.fromRGB(250, 246, 255),
			CanCollide = false,
		})
	end
	WorldKit.SurfaceText(counter, Enum.NormalId.Front, { { Text = Texts.Shop, Size = 48, Color = T.Gold } }, 50)
	return WorldKit.Prompt(counter, L.Prompts.Shop, "Мастерская", { Action = "OpenShop" }, 12)
end

local function buildWheel(parent)
	local pos = at(L.Wheel.Offset)
	local model = Instance.new("Model")
	model.Name = "Wheel"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(12, 12, 2), CFrame.new(pos + Vector3.new(0, 6, 2)), T.StoneB, "Board")
	local wheel = WorldKit.Part(model, {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 9, 9),
		CFrame = CFrame.new(pos + Vector3.new(0, 6, 0.6)) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(250, 246, 255),
	})
	-- Colored wedges as pegs around the rim + a hub.
	local colors = { T.Magenta, T.Gold, T.Cyan, T.Green, T.Purple, T.Orange, T.Red, T.Blue }
	for i = 0, 7 do
		local angle = i * math.pi / 4
		WorldKit.Part(wheel, {
			Name = "Peg",
			Size = Vector3.new(1.2, 2.6, 0.5),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(angle) * 3.2, 6 + math.sin(angle) * 3.2, 0.1)) * CFrame.Angles(0, 0, angle + math.rad(90)),
			Color = colors[i + 1],
			CanCollide = false,
		})
	end
	WorldKit.Part(model, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.6, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 6, 0.1)) * CFrame.Angles(0, math.rad(90), 0), Color = T.Gold })
	WorldKit.Part(model, { Name = "Pointer", Size = Vector3.new(0.8, 1.6, 0.6), CFrame = CFrame.new(pos + Vector3.new(0, 11.2, 0.1)), Color = T.Red })
	sign(model, pos + Vector3.new(0, 13.5, 1), Vector3.new(12, 2.6, 0.4), { { Text = Texts.Wheel, Size = 44, Color = T.Gold }, { Name = "Status", Text = Texts.WheelFree, Size = 26, Color = T.Green } })
	model:SetAttribute("Wheel", true)
	return WorldKit.Prompt(wheel, L.Prompts.Wheel, "Колесо удачи", { Action = "Wheel" }, 12)
end

local function buildEgg(parent)
	local pos = at(L.Egg.Offset)
	local model = Instance.new("Model")
	model.Name = "Egg"
	model.Parent = parent
	local ped = WorldKit.Brick(model, Vector3.new(6, 3, 6), CFrame.new(pos + Vector3.new(0, 1.5, 0)), T.StoneDark, "Pedestal")
	local egg = WorldKit.Part(model, { Name = "EggShell", Shape = Enum.PartType.Ball, Size = Vector3.new(3.5, 4.5, 3.5), Position = pos + Vector3.new(0, 5.3, 0), Color = Color3.fromRGB(255, 240, 250) })
	for i = 1, 5 do
		local angle = i * math.pi * 2 / 5
		WorldKit.Part(model, { Name = "Spot", Shape = Enum.PartType.Ball, Size = Vector3.one, CFrame = CFrame.new(pos + Vector3.new(math.cos(angle) * 1.5, 5.3 + math.sin(i) * 0.8, math.sin(angle) * 1.5)), Color = if i % 2 == 0 then T.Magenta else T.Cyan, Material = Enum.Material.Neon, CanCollide = false })
	end
	TweenService:Create(egg, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = egg.Position + Vector3.new(0, 0.5, 0) }):Play()
	sign(model, pos + Vector3.new(0, 10, 0), Vector3.new(7, 2.4, 0.4), { { Text = "🥚 Питомцы", Size = 34 }, { Text = Texts.Egg, Size = 26, Color = T.Gold } })
	return WorldKit.Prompt(ped, L.Prompts.Egg, "Яйцо питомцев", { Action = "OpenPets" }, 12)
end

local function buildLeaderboards(parent)
	local boards = {}
	for _, def in ipairs(L.Leaderboards) do
		local pos = at(def.Offset)
		local board = WorldKit.Part(parent, {
			Name = "Leaderboard_" .. def.Kind,
			Size = Vector3.new(16, 14, 0.6),
			Position = pos + Vector3.new(0, 9, 0),
			Color = T.PanelDark,
		})
		WorldKit.Part(parent, { Name = "Frame", Size = Vector3.new(17, 15, 0.4), Position = pos + Vector3.new(0, 9, 0.2), Color = T.Gold })
		local lines = { { Name = "Title", Text = "🏆 " .. def.Title, Size = 34, Color = T.Gold } }
		for i = 1, Config.Leaderboards.Top do
			table.insert(lines, { Name = "Row" .. i, Text = i .. ". —", Size = 18 })
		end
		local gui = WorldKit.SurfaceText(board, Enum.NormalId.Front, lines, 50)
		boards[def.Kind] = gui
	end
	return boards
end

local function buildFountain(parent)
	local F = L.Fountain
	local pos = at(F.Offset)
	local model = Instance.new("Model")
	model.Name = "Fountain"
	model.Parent = parent
	WorldKit.Part(model, { Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, F.Radius * 2, F.Radius * 2), CFrame = CFrame.new(pos + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = T.StoneDark })
	WorldKit.Part(model, { Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, F.Radius * 2 - 1.5, F.Radius * 2 - 1.5), CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = T.Cyan, Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
	WorldKit.Brick(model, Vector3.new(2, 4, 2), CFrame.new(pos + Vector3.new(0, 3.5, 0)), T.StoneLight, "Column")
	local crystal = WorldKit.Part(model, { Name = "Crystal", Size = Vector3.new(2, 4, 2), CFrame = CFrame.new(pos + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = T.Magenta, Material = Enum.Material.Neon })
	TweenService:Create(crystal, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = crystal.CFrame * CFrame.Angles(0, math.rad(180), 0) }):Play()
	WorldKit.Light(crystal, T.Magenta, 24, 2)
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

local function buildTree(parent, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Tree"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(2, 6, 2), CFrame.new(position + Vector3.new(0, 3, 0)), Color3.fromRGB(120, 80, 50), "Trunk")
	WorldKit.Brick(model, Vector3.new(8, 5, 8), CFrame.new(position + Vector3.new(0, 8, 0)), Color3.fromRGB(70, 190, 100), "Leaves")
	WorldKit.Brick(model, Vector3.new(5, 4, 5), CFrame.new(position + Vector3.new(0, 12, 0)), Color3.fromRGB(95, 215, 125), "Leaves")
end

local function buildBush(parent, position: Vector3)
	WorldKit.Brick(parent, Vector3.new(3, 2.2, 3), CFrame.new(position + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(80, 200, 110), "Bush")
	WorldKit.Brick(parent, Vector3.new(2, 1.6, 2), CFrame.new(position + Vector3.new(1.2, 1.2, 0.8)), Color3.fromRGB(100, 220, 130), "Bush")
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

	local altarPrompt = buildAltar(root)
	local shopPrompt = buildStall(root)
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

	root:SetAttribute("Center", base)
	root.Parent = Workspace
	return {
		Folder = root,
		Trainers = trainers,
		Portal = portal,
		AltarPrompt = altarPrompt,
		ShopPrompt = shopPrompt,
		WheelPrompt = wheelPrompt,
		EggPrompt = eggPrompt,
		Leaderboards = boards,
		SpawnCFrame = CFrame.new(base + Vector3.new(0, 4, 0)),
		GroundY = base.Y,
	}
end

return HubGenerator
