--[[
	HubGenerator.luau
	Builds the hub (room 0) around the SpawnLocation at server start
	(Workspace.Hub). Pure construction; HubService wires the prompts.

	- Trainers (Hub.Trainers): immortal dummies. Clicking one gives Aura
	  at Config.Hub.TrainerRate (handled by ClickService).
	- Weapon stand: one pedestal per unique weapon with the weapon
	  spinning on top (TweenService) and a "Купить" ProximityPrompt
	  (attribute WeaponId).
	- Rebirth altar: crystal with a ProximityPrompt (attribute
	  Action = "RebirthAltar") that opens the client confirmation window.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local WorldKit = require(script.Parent.WorldKit)

local HubGenerator = {}

local H = Config.Hub

local function label(parent: BasePart, text: string, height: number, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Parent = parent

	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.GothamBold
	text_.TextScaled = true
	text_.TextColor3 = color or Color3.new(1, 1, 1)
	text_.Text = text
	text_.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = text_
	return gui
end

local function buildTrainer(parent, position: Vector3, facing: Vector3, index: number)
	local model = Instance.new("Model")
	model.Name = "Trainer" .. index

	local post = WorldKit.Part(model, {
		Name = "Post",
		Size = Vector3.new(0.8, 3, 0.8),
		Position = position + Vector3.new(0, 1.5, 0),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	})
	local body = WorldKit.Part(model, {
		Name = "Body",
		Size = Vector3.new(3, 4, 2),
		CFrame = CFrame.lookAt(position + Vector3.new(0, 5, 0), Vector3.new(facing.X, position.Y + 5, facing.Z)),
		Color = Color3.fromRGB(215, 185, 120),
		Material = Enum.Material.Fabric,
	})
	local head = WorldKit.Part(model, {
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.4,
		CFrame = body.CFrame * CFrame.new(0, 3.2, 0),
		Color = Color3.fromRGB(215, 185, 120),
		Material = Enum.Material.Fabric,
	})
	head.Shape = Enum.PartType.Ball
	-- Red target circle on the chest.
	WorldKit.Part(model, {
		Name = "Target",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 2, 2),
		CFrame = body.CFrame * CFrame.new(0, 0.3, -1.05) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(220, 60, 60),
		CanCollide = false,
	})
	model.PrimaryPart = body
	label(post, ("Тренажёр • x%s"):format(tostring(H.TrainerRate)), 10, Color3.fromRGB(205, 160, 255))

	model.Parent = parent
	return model
end

local function buildStand(parent, position: Vector3, weapon)
	local pedestal = WorldKit.Part(parent, {
		Name = "Pedestal_" .. weapon.Id,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 6, 6),
		CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 50, 80),
		Material = Enum.Material.Marble,
	})

	-- The weapon: anchored blade that spins; guard and handle are welded
	-- to it so they spin along.
	local bladeHeight = 4.5
	local blade = WorldKit.Part(parent, {
		Name = "Display_" .. weapon.Id,
		Size = Vector3.new(0.5, bladeHeight, 0.2),
		Position = position + Vector3.new(0, 3 + 1.6 + bladeHeight / 2, 0),
		Orientation = Vector3.zero,
		Color = weapon.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	for _, piece in ipairs({
		{ "Guard", Vector3.new(1.8, 0.3, 0.4), -bladeHeight / 2 - 0.15, Color3.fromRGB(255, 205, 70) },
		{ "Handle", Vector3.new(0.35, 1.3, 0.35), -bladeHeight / 2 - 0.95, Color3.fromRGB(70, 45, 30) },
	}) do
		local part = WorldKit.Part(blade, {
			Name = piece[1],
			Size = piece[2],
			CFrame = blade.CFrame * CFrame.new(0, piece[3], 0),
			Color = piece[4],
			Anchored = false,
			CanCollide = false,
			Massless = true,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = blade
		weld.Part1 = part
		weld.Parent = part
	end
	WorldKit.Light(blade, weapon.Color, 14, 2)

	TweenService:Create(
		blade,
		TweenInfo.new(H.StandSpinSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Orientation = Vector3.new(0, 360, 0) }
	):Play()

	label(pedestal, ("%s\n%s ✨ • урон x%s"):format(weapon.Name, Format.Number(weapon.Cost), Format.Number(weapon.Damage)), 9, weapon.Color)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Купить"
	prompt.ObjectText = ("%s — %s Ауры"):format(weapon.Name, Format.Number(weapon.Cost))
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("WeaponId", weapon.Id)
	prompt.Parent = pedestal
	return prompt
end

local function buildAltar(parent, position: Vector3)
	WorldKit.Part(parent, {
		Name = "AltarBase",
		Size = Vector3.new(8, 1.5, 8),
		Position = position + Vector3.new(0, 0.75, 0),
		Color = Color3.fromRGB(45, 30, 70),
		Material = Enum.Material.Marble,
	})
	local crystal = WorldKit.Part(parent, {
		Name = "AltarCrystal",
		Size = Vector3.new(2.5, 6, 2.5),
		CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.rad(45), math.rad(10)),
		Color = Color3.fromRGB(190, 110, 255),
		Material = Enum.Material.Neon,
	})
	WorldKit.Light(crystal, Color3.fromRGB(190, 110, 255), 24, 2.5)

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(220, 170, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Lifetime = NumberRange.new(1.5, 2.5)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Rate = 18
	sparkles.Parent = crystal

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ребёрт"
	prompt.ObjectText = "Алтарь ребёрта"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "RebirthAltar")
	prompt.Parent = crystal
	return prompt
end

-- Returns { Folder, Trainers = Folder, StandPrompts = { ProximityPrompt }, AltarPrompt }.
function HubGenerator.Build()
	local root = Instance.new("Folder")
	root.Name = "Hub"
	local trainers = Instance.new("Folder")
	trainers.Name = "Trainers"
	trainers.Parent = root

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local groundY = if spawn then spawn.Position.Y - spawn.Size.Y / 2 else 0
	local base = Vector3.new(origin.X, groundY, origin.Z)

	WorldKit.Part(root, {
		Name = "HubFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, H.FloorRadius * 2, H.FloorRadius * 2),
		CFrame = CFrame.new(base + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 50, 110),
		Transparency = 0.3,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	WorldKit.Sign(root, base + Vector3.new(0, 16, 0), "✨ AURA CLICKER ✨", Color3.fromRGB(255, 220, 120), 420)

	for index, offset in ipairs(H.Trainers) do
		buildTrainer(trainers, base + offset, base, index)
	end
	WorldKit.Sign(root, base + H.Trainers[2] + Vector3.new(0, 14, 0), "🥊 Тренажёры", nil, 260)

	local standPrompts = {}
	local standIndex = 0
	for _, weapon in ipairs(Config.Weapons) do
		if weapon.Unique then
			standIndex += 1
			local offset = H.Stands[standIndex]
			if offset then
				table.insert(standPrompts, buildStand(root, base + offset, weapon))
			end
		end
	end
	WorldKit.Sign(root, base + H.Stands[2] + Vector3.new(0, 15, 0), "⚔ Уникальное оружие", Color3.fromRGB(255, 205, 70), 300)

	local altarPrompt = buildAltar(root, base + H.Altar)
	WorldKit.Sign(root, base + H.Altar + Vector3.new(0, 12, 0), "🔁 Алтарь ребёрта", nil, 300)

	root.Parent = Workspace
	return { Folder = root, Trainers = trainers, StandPrompts = standPrompts, AltarPrompt = altarPrompt }
end

return HubGenerator
