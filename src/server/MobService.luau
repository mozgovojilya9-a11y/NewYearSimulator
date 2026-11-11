--[[
	MobService.luau
	Day 3: builds the first zone at runtime (Workspace.AuraZone), spawns
	mobs, applies click damage, pays out rewards on death and respawns.

	Flow: the client raycasts what it clicked and fires MobHit(model).
	The server validates everything (model is a live mob, player is in
	range, cooldown passed), rolls damage itself and replies:
		FireClient(player, "Hit", model, damage, isCrit)
		FireClient(player, "Kill", position, auraGained, gemsGained)

	Every player who damaged a mob gets the full reward when it dies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Effects = require(script.Parent.Effects)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local MobService = {}

local zoneFolder
local mobsFolder
local remote
local spawnInfo = {} -- [model] = { def = mobDef, cframe = CFrame }
local damagers = {} -- [model] = { [player] = true }

local HEALTH_FULL = Color3.fromRGB(90, 220, 110)
local HEALTH_LOW = Color3.fromRGB(230, 70, 70)

---------------------------------------------------------------------
-- Zone layout
---------------------------------------------------------------------

local function findGroundY(position: Vector3, fallback: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { zoneFolder }
	local result = Workspace:Raycast(position + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
	return if result then result.Position.Y else fallback
end

local function makeSign(position: Vector3, text: string)
	local anchor = Instance.new("Part")
	anchor.Name = "Sign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = zoneFolder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 60)
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(220, 190, 255)
	label.Text = text
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(40, 15, 70)
	stroke.Parent = label
end

-- Returns a list of { def, cframe } for every mob slot in the zone.
local function buildZone()
	zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "AuraZone"
	zoneFolder.Parent = Workspace

	mobsFolder = Instance.new("Folder")
	mobsFolder.Name = "Mobs"
	mobsFolder.Parent = zoneFolder

	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawnLocation then spawnLocation.Position else Vector3.zero
	local center = origin + Config.Zone.Offset
	local groundY = findGroundY(center, origin.Y)
	center = Vector3.new(center.X, groundY, center.Z)

	-- Direction from the spawn towards the zone: the boss stands at the
	-- far side so new players meet the weak mobs first.
	local away = Vector3.new(center.X - origin.X, 0, center.Z - origin.Z)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, -1)

	local radius = Config.Zone.Radius
	local disc = Instance.new("Part")
	disc.Name = "Floor"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = Color3.fromRGB(120, 70, 200)
	disc.Transparency = 0.55
	disc.Parent = zoneFolder

	-- Day 6: slow sparkles rising from the zone floor.
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(200, 150, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Lifetime = NumberRange.new(3, 5)
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.Rate = 12
	sparkles.EmissionDirection = Enum.NormalId.Right -- disc is rotated: its +X points up
	sparkles.Parent = disc

	makeSign(center - away * radius + Vector3.new(0, 10, 0), Config.Zone.Name)

	local slots = {}
	local normal = {}
	for _, def in ipairs(Config.Mobs) do
		for _ = 1, def.Count do
			if def.Boss then
				local pos = center + away * (radius * 0.75)
				table.insert(slots, { def = def, position = pos })
			else
				table.insert(normal, def)
			end
		end
	end

	-- Spread normal mobs over two rings around the center.
	for i, def in ipairs(normal) do
		local angle = (i / #normal) * math.pi * 2
		local ringRadius = if i % 2 == 0 then radius * 0.3 else radius * 0.52
		local pos = center + Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
		table.insert(slots, { def = def, position = pos })
	end

	for _, slot in ipairs(slots) do
		local pos = slot.position + Vector3.new(0, slot.def.Size.Y / 2, 0)
		local lookAt = Vector3.new(origin.X, pos.Y, origin.Z)
		slot.cframe = CFrame.lookAt(pos, lookAt)
	end

	return slots
end

---------------------------------------------------------------------
-- Mob model
---------------------------------------------------------------------

local function makePart(name, size, color, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function updateHealthBar(model)
	local body = model:FindFirstChild("Body")
	local gui = body and body:FindFirstChild("HealthGui")
	if not gui then
		return
	end
	local health = model:GetAttribute("Health")
	local maxHealth = model:GetAttribute("MaxHealth")
	local ratio = math.clamp(health / maxHealth, 0, 1)

	gui.Bar.Fill.Size = UDim2.fromScale(ratio, 1)
	gui.Bar.Fill.BackgroundColor3 = HEALTH_LOW:Lerp(HEALTH_FULL, ratio)
	gui.Bar.HpText.Text = Format.Number(health) .. " / " .. Format.Number(maxHealth)
end

local function makeHealthGui(def, body)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthGui"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(if def.Boss then 220 else 140, if def.Boss then 52 else 42)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.Size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Parent = body

	local name = Instance.new("TextLabel")
	name.Name = "MobName"
	name.Size = UDim2.new(1, 0, 0.5, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = if def.Boss then Color3.fromRGB(255, 205, 70) else Color3.new(1, 1, 1)
	name.Text = def.Name
	name.Parent = gui
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 2
	nameStroke.Parent = name

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0, 0.55)
	bar.Size = UDim2.fromScale(1, 0.42)
	bar.BackgroundColor3 = Color3.fromRGB(25, 20, 35)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.4, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HEALTH_FULL
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "HpText"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.ZIndex = 2
	text.Parent = bar
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 1.5
	textStroke.Parent = text
end

local function spawnMob(def, cframe)
	local model = Instance.new("Model")
	model.Name = def.Name

	local body = makePart("Body", def.Size, def.Color, cframe, model)
	if def.Shape == "Ball" then
		body.Shape = Enum.PartType.Ball
	end
	if def.Boss then
		body.Material = Enum.Material.Neon
	end
	model.PrimaryPart = body

	-- Two eyes on the front face so mobs "look" at players.
	local eyeSize = math.max(0.5, def.Size.X * 0.18)
	for _, side in ipairs({ -1, 1 }) do
		local offset = CFrame.new(side * def.Size.X * 0.22, def.Size.Y * 0.18, -def.Size.Z / 2 + eyeSize * 0.3)
		local eye = makePart("Eye", Vector3.one * eyeSize, Color3.new(1, 1, 1), cframe * offset, model)
		eye.Shape = Enum.PartType.Ball
		eye.CanCollide = false
		local pupil = makePart("Pupil", Vector3.one * eyeSize * 0.5, Color3.new(0, 0, 0), cframe * offset * CFrame.new(0, 0, -eyeSize * 0.35), model)
		pupil.Shape = Enum.PartType.Ball
		pupil.CanCollide = false
	end

	model:SetAttribute("MobId", def.Id)
	model:SetAttribute("Health", def.Health)
	model:SetAttribute("MaxHealth", def.Health)

	makeHealthGui(def, body)
	updateHealthBar(model)

	spawnInfo[model] = { def = def, cframe = cframe }
	damagers[model] = {}
	model.Parent = mobsFolder
end

local function killMob(model)
	local info = spawnInfo[model]
	local who = damagers[model] or {}
	spawnInfo[model] = nil
	damagers[model] = nil

	local def = info.def
	local position = model.PrimaryPart.Position
	model:Destroy()
	if def.Boss then
		Effects.Burst(position, def.Color, 90, 35, 2)
	else
		Effects.Burst(position, def.Color, 25)
	end

	for player in pairs(who) do
		if player.Parent and PlayerState.IsReady(player) then
			local aura = PlayerState.GiveAura(player, def.Reward)
			local gems = 0
			if math.random() < def.GemChance then
				gems = def.Gems
				PlayerState.AddGems(player, gems)
			end
			remote:FireClient(player, "Kill", position, aura, gems)
		end
	end

	task.delay(def.Respawn, spawnMob, def, info.cframe)
end

---------------------------------------------------------------------
-- Hits
---------------------------------------------------------------------

local function onHit(player, model)
	-- Never trust the argument: it must be one of our live mobs.
	if typeof(model) ~= "Instance" or model.Parent ~= mobsFolder or not spawnInfo[model] then
		return
	end
	local health = model:GetAttribute("Health")
	if type(health) ~= "number" or health <= 0 then
		return
	end
	if not PlayerState.IsReady(player) then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - model.PrimaryPart.Position).Magnitude > Config.Zone.HitDistance then
		return
	end

	if not MobService.allow(player) then
		return
	end

	local damage, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player))
	health = math.max(0, health - damage)
	model:SetAttribute("Health", health)
	damagers[model][player] = true
	updateHealthBar(model)

	remote:FireClient(player, "Hit", model, damage, isCrit)

	if health <= 0 then
		killMob(model)
	end
end

function MobService.Init()
	remote = Remotes.Get("MobHit")
	MobService.allow = RateLimit.new(Config.Click.Cooldown)

	for _, slot in ipairs(buildZone()) do
		spawnMob(slot.def, slot.cframe)
	end

	remote.OnServerEvent:Connect(onHit)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		for _, set in pairs(damagers) do
			set[player] = nil
		end
	end)
end

return MobService
