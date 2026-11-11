--[[
	HubGenerator.luau
	Builds the hub, "Цитадель Ауры", around the SpawnLocation at
	server start (Workspace.Hub). Pure construction from Parts; the
	prompts it creates are wired by HubService.

	Layout (looking forward from the spawn = -Z):
	  center: purple path with yellow chevrons -> dungeon portal arch
	  left:   3 trainer rings with dummies
	  right:  unique-weapon stand (3 pedestals)
	  back:   rebirth altar (left), shop stall (center), pet egg (right)
	  around: castle walls, corner towers, flags, torches, block trees.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local L = Config.HubLayout
local T = Config.Theme
local Texts = L.Texts

local root, base

local function at(offset: Vector3): Vector3
	return base + offset
end

---------------------------------------------------------------------
-- Courtyard, walls, towers
---------------------------------------------------------------------

local function buildCourtyard()
	local half = L.Size / 2
	-- Tiles sit 0.05 below the spawn pad so the two tops don't z-fight.
	WorldKit.TiledFloor(root, base - Vector3.new(0, 0.05, 0), L.Size, L.Size, L.TileSize, T.StoneA, T.StoneB, 144)

	-- Grass apron around the citadel so the Baseplate doesn't show grey.
	WorldKit.Part(root, {
		Name = "Grass",
		Size = Vector3.new(L.Size * 2.2, 1, L.Size * 2.2),
		Position = base + Vector3.new(0, -0.6, 0),
		Color = T.Grass,
		Material = Enum.Material.Grass,
	})

	local corners = {
		Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half), Vector3.new(-half, 0, half),
	}
	for i = 1, 4 do
		local a = at(corners[i])
		local b = at(corners[i % 4 + 1])
		local gap = nil
		if i == 1 then -- front wall: gate for the portal arch
			gap = { Center = half, Width = L.Portal.ArchWidth + 2 }
		end
		WorldKit.CastleWall(root, a, b, L.WallHeight, L.WallThickness, T.StoneA, T.StoneB, L.MerlonSize, gap)
	end

	-- Towers with flags.
	for i, c in ipairs(corners) do
		local tower = Instance.new("Model")
		tower.Name = "Tower" .. i
		tower.Parent = root
		local pos = at(c)
		WorldKit.Brick(tower, Vector3.new(L.TowerSize, L.TowerHeight, L.TowerSize), CFrame.new(pos + Vector3.new(0, L.TowerHeight / 2, 0)), T.StoneB)
		WorldKit.Brick(tower, Vector3.new(L.TowerSize + 2, 2, L.TowerSize + 2), CFrame.new(pos + Vector3.new(0, L.TowerHeight + 1, 0)), T.StoneA, "Cap")
		for _, dx in ipairs({ -1, 1 }) do
			for _, dz in ipairs({ -1, 1 }) do
				WorldKit.Brick(tower, Vector3.new(2, 2, 2), CFrame.new(pos + Vector3.new(dx * (L.TowerSize / 2), L.TowerHeight + 3, dz * (L.TowerSize / 2))), T.StoneDark, "Merlon")
			end
		end
		WorldKit.Part(tower, { Name = "Pole", Size = Vector3.new(0.4, 10, 0.4), Position = pos + Vector3.new(0, L.TowerHeight + 7, 0), Color = T.StoneDark })
		local flag = WorldKit.Part(tower, {
			Name = "Flag",
			Size = Vector3.new(5, 3, 0.2),
			Position = pos + Vector3.new(2.7, L.TowerHeight + 10.5, 0),
			Color = if i % 2 == 0 then T.Magenta else T.Cyan,
			CanCollide = false,
		})
		WorldKit.SurfaceText(flag, Enum.NormalId.Front, { { Text = "✦", Size = 60, Color = T.Gold } }, 30)
	end
end

---------------------------------------------------------------------
-- Path with chevrons -> portal
---------------------------------------------------------------------

local function buildPath()
	local zStart = 10
	local zEnd = L.Portal.Offset.Z + L.Portal.Radius
	local length = zStart - zEnd
	local center = at(Vector3.new(0, 0.08, (zStart + zEnd) / 2))
	WorldKit.Part(root, {
		Name = "Path",
		Size = Vector3.new(L.PathWidth, 0.2, length),
		Position = center,
		Color = T.Path,
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
	})
	-- Chevrons: two angled bars forming a "^" pointing forward (-Z).
	local z = zStart - 4
	while z > zEnd + 4 do
		for _, side in ipairs({ -1, 1 }) do
			WorldKit.Part(root, {
				Name = "Chevron",
				Size = Vector3.new(1.4, 0.15, 5),
				CFrame = CFrame.new(at(Vector3.new(side * 2.2, 0.26, z))) * CFrame.Angles(0, side * math.rad(35), 0),
				Color = T.Chevron,
				CanCollide = false,
				CanQuery = false,
			})
		end
		z -= L.ChevronSpacing
	end
	-- Torches along the path.
	for i = 1, L.TorchesAlongPath do
		local tz = zStart - (i / (L.TorchesAlongPath + 1)) * length
		WorldKit.Torch(root, at(Vector3.new(-L.PathWidth / 2 - 2, 0, tz)))
		WorldKit.Torch(root, at(Vector3.new(L.PathWidth / 2 + 2, 0, tz)))
	end
end

local function buildPortal()
	local P = L.Portal
	local model = Instance.new("Model")
	model.Name = "Portal"
	model.Parent = root
	local pos = at(P.Offset)
	local pillarW = 4
	-- Arch: two pillars + lintel, in bricks.
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(pillarW, P.ArchHeight, 6), CFrame.new(pos + Vector3.new(side * (P.ArchWidth / 2 - pillarW / 2), P.ArchHeight / 2, 0)), T.StoneDark)
	end
	local lintel = WorldKit.Brick(model, Vector3.new(P.ArchWidth, 5, 6), CFrame.new(pos + Vector3.new(0, P.ArchHeight + 2.5, 0)), T.StoneA, "Lintel")
	WorldKit.SurfaceText(lintel, Enum.NormalId.Back, { { Text = Texts.Portal, Size = 70, Color = T.Gold } }, 24)
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Brick(model, Vector3.new(2, 2, 2), CFrame.new(pos + Vector3.new(side * (P.ArchWidth / 2 - 1), P.ArchHeight + 6, 0)), T.Magenta, "Merlon")
	end

	-- Spinning portal disc.
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
	-- Spin: rotate around the disc's own axis (its X after the 90° turn).
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

	-- Arrival pad in front of the portal.
	disc:SetAttribute("Portal", true)
	return disc
end

---------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------

local function buildTrainer(parent, index, def)
	local pos = at(def.Offset)
	local mult = Config.Hub.TrainerMultipliers[index] or 1
	local model = Instance.new("Model")
	model.Name = "Trainer" .. index

	WorldKit.Part(model, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, L.TrainerRingRadius * 2, L.TrainerRingRadius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = def.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	WorldKit.Part(model, {
		Name = "Post",
		Size = Vector3.new(0.8, 3, 0.8),
		Position = pos + Vector3.new(0, 2, 0),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	})
	local body = WorldKit.Brick(model, Vector3.new(3, 4, 2), CFrame.lookAt(pos + Vector3.new(0, 5.5, 0), Vector3.new(base.X, pos.Y + 5.5, base.Z)), Color3.fromRGB(230, 200, 150), "Body")
	WorldKit.Brick(model, Vector3.new(2.2, 2.2, 2.2), body.CFrame * CFrame.new(0, 3.1, 0), Color3.fromRGB(230, 200, 150), "Head")
	WorldKit.Part(model, {
		Name = "Target",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2, 2),
		CFrame = body.CFrame * CFrame.new(0, 0.3, -1.05) * CFrame.Angles(0, math.rad(90), 0),
		Color = def.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	model.PrimaryPart = body
	model:SetAttribute("Multiplier", mult)

	local sign = WorldKit.Part(model, {
		Name = "Sign",
		Size = Vector3.new(7, 2, 0.4),
		CFrame = body.CFrame * CFrame.new(0, 6, 0),
		Color = T.PanelDark,
		CanCollide = false,
	})
	WorldKit.SurfaceText(sign, Enum.NormalId.Front, { { Text = Texts.Trainer:format(tostring(mult)), Size = 44, Color = def.Color } }, 30)
	model.Parent = parent
	return model
end

---------------------------------------------------------------------
-- Unique weapon stand
---------------------------------------------------------------------

local function buildPedestal(parent, position: Vector3, weapon)
	local rarity = Config.Rarity[weapon.Rarity] or Config.Rarity.Common
	local pedestal = WorldKit.Brick(parent, Vector3.new(6, 3, 6), CFrame.new(position + Vector3.new(0, 1.5, 0)), T.StoneDark, "Pedestal_" .. weapon.Id)
	WorldKit.Part(parent, {
		Name = "PedestalRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 7, 7),
		CFrame = CFrame.new(position + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rarity.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})

	-- The weapon: a blade with guard and handle welded on, spinning and
	-- floating above the pedestal.
	local bladeH = 4.5
	local restY = position.Y + 3 + 1.8 + bladeH / 2
	local blade = WorldKit.Part(parent, {
		Name = "Display_" .. weapon.Id,
		Size = Vector3.new(0.5, bladeH, 0.2),
		Position = Vector3.new(position.X, restY, position.Z),
		Color = weapon.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	for _, piece in ipairs({
		{ "Guard", Vector3.new(1.8, 0.3, 0.4), -bladeH / 2 - 0.15, T.Gold },
		{ "Handle", Vector3.new(0.35, 1.3, 0.35), -bladeH / 2 - 0.95, Color3.fromRGB(70, 45, 30) },
	}) do
		local part = WorldKit.Part(blade, {
			Name = piece[1], Size = piece[2], CFrame = blade.CFrame * CFrame.new(0, piece[3], 0), Color = piece[4],
			Anchored = false, CanCollide = false, Massless = true,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = blade
		weld.Part1 = part
		weld.Parent = part
	end
	WorldKit.Light(blade, weapon.Color, 14, 2)

	-- Spin forever (Orientation) + float up/down (Position), independent tweens.
	TweenService:Create(blade, TweenInfo.new(L.Stand.SpinSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Orientation = Vector3.new(0, 360, 0) }):Play()
	TweenService:Create(blade, TweenInfo.new(L.Stand.FloatSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = blade.Position + Vector3.new(0, L.Stand.FloatHeight, 0) }):Play()

	WorldKit.Beam(parent, position + Vector3.new(0, 3.1, 0), position + Vector3.new(0, 16, 0), ColorSequence.new(rarity.Color, Color3.new(1, 1, 1)), 4)

	local sign = WorldKit.Part(parent, {
		Name = "Sign",
		Size = Vector3.new(7.5, 3, 0.4),
		CFrame = CFrame.new(position + Vector3.new(0, 11.5, 0)),
		Color = T.PanelDark,
		CanCollide = false,
	})
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		WorldKit.SurfaceText(sign, face, {
			{ Text = weapon.Name, Size = 30, Color = rarity.Color },
			{ Text = Format.Number(weapon.Cost) .. " ✨  •  урон x" .. Format.Number(weapon.Damage), Size = 22 },
			{ Text = Texts.Stand, Size = 22, Color = T.Gold },
		}, 30)
	end

	return WorldKit.Prompt(pedestal, L.Prompts.Buy, weapon.Name .. " — " .. Format.Number(weapon.Cost) .. " Ауры", { WeaponId = weapon.Id })
end

---------------------------------------------------------------------
-- Altar, shop stall, egg, trees
---------------------------------------------------------------------

local function buildAltar(parent)
	local pos = at(L.Altar.Offset)
	local model = Instance.new("Model")
	model.Name = "Altar"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(14, 2, 14), CFrame.new(pos + Vector3.new(0, 1, 0)), T.StoneDark, "Base")
	WorldKit.Brick(model, Vector3.new(10, 1.5, 10), CFrame.new(pos + Vector3.new(0, 2.75, 0)), T.StoneA, "Step")
	local crystal = WorldKit.Part(model, {
		Name = "Crystal",
		Size = Vector3.new(3.5, 9, 3.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = T.Purple,
		Material = Enum.Material.Neon,
	})
	TweenService:Create(crystal, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = crystal.CFrame * CFrame.Angles(0, math.rad(180), 0) }):Play()
	WorldKit.Light(crystal, T.Purple, 28, 2.5)
	-- Four rune pillars.
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local p = pos + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
		local pillar = WorldKit.Brick(model, Vector3.new(2, 7, 2), CFrame.new(p + Vector3.new(0, 3.5, 0)), T.StoneB, "Pillar")
		WorldKit.Part(model, { Name = "Rune", Size = Vector3.new(1.2, 3, 0.2), CFrame = CFrame.lookAt(p + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0)) * CFrame.new(0, 0, -1.05), Color = T.Magenta, Material = Enum.Material.Neon, CanCollide = false })
		pillar.Name = "Pillar"
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

	local sign = WorldKit.Part(model, { Name = "Sign", Size = Vector3.new(14, 2.4, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 15, 0)), Color = T.PanelDark, CanCollide = false })
	WorldKit.SurfaceText(sign, Enum.NormalId.Front, { { Text = Texts.Altar, Size = 44, Color = T.Purple } }, 30)
	WorldKit.SurfaceText(sign, Enum.NormalId.Back, { { Text = Texts.Altar, Size = 44, Color = T.Purple } }, 30)
	return WorldKit.Prompt(crystal, L.Prompts.Rebirth, "Алтарь", { Action = "RebirthAltar" }, 14)
end

local function buildStall(parent)
	local pos = at(L.Shop.Offset)
	local model = Instance.new("Model")
	model.Name = "Shop"
	model.Parent = parent
	local counter = WorldKit.Brick(model, Vector3.new(14, 3.5, 4), CFrame.new(pos + Vector3.new(0, 1.75, 0)), Color3.fromRGB(150, 100, 60), "Counter")
	for _, side in ipairs({ -1, 1 }) do
		WorldKit.Part(model, { Name = "Post", Size = Vector3.new(0.6, 9, 0.6), Position = pos + Vector3.new(side * 6.5, 4.5, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood })
	end
	-- Striped awning: white / magenta stripes.
	for i = 0, 6 do
		WorldKit.Part(model, {
			Name = "Awning",
			Size = Vector3.new(2, 0.4, 7),
			CFrame = CFrame.new(pos + Vector3.new(-6 + i * 2, 9.2, -1)) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = if i % 2 == 0 then T.Magenta else Color3.new(1, 1, 1),
			CanCollide = false,
		})
	end
	WorldKit.SurfaceText(counter, Enum.NormalId.Front, { { Text = Texts.Shop, Size = 48, Color = T.Gold } }, 30)
	-- Some goods on the counter.
	for i, c in ipairs({ T.Green, T.Blue, T.Purple }) do
		WorldKit.Part(model, { Name = "Goods", Size = Vector3.new(1.5, 1.5, 1.5), Position = pos + Vector3.new(-4 + i * 2.5, 4.3, 0), Color = c, Material = Enum.Material.Neon, CanCollide = false })
	end
	return WorldKit.Prompt(counter, L.Prompts.Shop, "Мастерская", { Action = "OpenShop" }, 12)
end

local function buildEgg(parent)
	local pos = at(L.Egg.Offset)
	local model = Instance.new("Model")
	model.Name = "Egg"
	model.Parent = parent
	local pedestal = WorldKit.Brick(model, Vector3.new(6, 3, 6), CFrame.new(pos + Vector3.new(0, 1.5, 0)), T.StoneDark, "Pedestal")
	local egg = WorldKit.Part(model, {
		Name = "EggShell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.5, 4.5, 3.5),
		Position = pos + Vector3.new(0, 5.3, 0),
		Color = Color3.fromRGB(255, 240, 250),
		Material = Enum.Material.SmoothPlastic,
	})
	for i = 1, 5 do
		local angle = i * math.pi * 2 / 5
		WorldKit.Part(model, { Name = "Spot", Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(pos + Vector3.new(math.cos(angle) * 1.5, 5.3 + math.sin(i) * 0.8, math.sin(angle) * 1.5)), Color = if i % 2 == 0 then T.Magenta else T.Cyan, Material = Enum.Material.Neon, CanCollide = false })
	end
	TweenService:Create(egg, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = egg.Position + Vector3.new(0, 0.5, 0) }):Play()
	local sign = WorldKit.Part(model, { Name = "Sign", Size = Vector3.new(7, 2.4, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 10, 0)), Color = T.PanelDark, CanCollide = false })
	WorldKit.SurfaceText(sign, Enum.NormalId.Front, { { Text = "🥚 Питомцы", Size = 34 }, { Text = Texts.Egg, Size = 26, Color = T.Gold } }, 30)
	return WorldKit.Prompt(pedestal, L.Prompts.Egg, "Яйцо питомцев", { Action = "OpenPets" }, 12)
end

local function buildTree(parent, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Tree"
	model.Parent = parent
	WorldKit.Brick(model, Vector3.new(2, 6, 2), CFrame.new(position + Vector3.new(0, 3, 0)), Color3.fromRGB(120, 80, 50), "Trunk")
	WorldKit.Brick(model, Vector3.new(8, 5, 8), CFrame.new(position + Vector3.new(0, 8, 0)), Color3.fromRGB(80, 200, 110), "Leaves")
	WorldKit.Brick(model, Vector3.new(5, 4, 5), CFrame.new(position + Vector3.new(0, 12, 0)), Color3.fromRGB(100, 220, 130), "Leaves")
end

---------------------------------------------------------------------

-- Returns { Folder, Trainers, Portal, StandPrompts, AltarPrompt, ShopPrompt, EggPrompt }.
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
	buildPath()
	local portal = buildPortal()

	for i, def in ipairs(L.Trainers) do
		buildTrainer(trainers, i, def)
	end

	local standPrompts = {}
	local standIndex = 0
	for _, weapon in ipairs(Config.Weapons) do
		if weapon.Unique then
			local pos = at(L.Stand.Offset + Vector3.new(0, 0, (standIndex - 1) * L.Stand.Spacing))
			standIndex += 1
			table.insert(standPrompts, buildPedestal(root, pos, weapon))
		end
	end

	local altarPrompt = buildAltar(root)
	local shopPrompt = buildStall(root)
	local eggPrompt = buildEgg(root)
	for _, offset in ipairs(L.Trees) do
		buildTree(root, at(offset))
	end

	root:SetAttribute("Center", base)
	root.Parent = Workspace
	return {
		Folder = root,
		Trainers = trainers,
		Portal = portal,
		StandPrompts = standPrompts,
		AltarPrompt = altarPrompt,
		ShopPrompt = shopPrompt,
		EggPrompt = eggPrompt,
		SpawnCFrame = CFrame.new(base + Vector3.new(0, 4, 0)),
	}
end

return HubGenerator
