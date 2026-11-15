--[[
	LootFx.luau
	The player's own loot drops. The server only tells THIS client about
	them (Loot "Spawn"), so nobody else sees or steals a drop. Each drop:
	the material's mini-model floating and spinning, a beam of the rarity
	color, a name plate, and a ProximityPrompt that must be HELD (E, or
	the on-screen button on phones) -- no touch pickup, no auto-collect.
	Legendary+ adds particles and a sound; Mythic / Secret flash the
	screen (the server also announces them in everyone's chat).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MaterialBuilder = require(ReplicatedStorage.Shared.MaterialBuilder)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)

local LOOT = Config.Loot
local lootRemote = ReplicatedStorage:WaitForChild("Loot")
local announceRemote = ReplicatedStorage:WaitForChild("Announce")

local LootFx = {}

local folder = Instance.new("Folder")
folder.Name = "LocalLoot"
folder.Parent = Workspace

local drops = {} -- [id] = { model, anchor, base: Vector3, phase, rainbow: { Beam | PointLight }? }

local function remove(id)
	local drop = drops[id]
	if drop then
		drops[id] = nil
		drop.holder:Destroy()
	end
end

-- Name plate. Far away it is a small name tag; within
-- LOOT.DetailDistance it grows and shows the rarity (see RenderStepped).
local function plate(anchor: BasePart, material, rarity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(LOOT.PlateSmall.X, LOOT.PlateSmall.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Parent = anchor
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Style.Colors.PanelDark
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Style.Corner(frame, UDim.new(0, 3))
	Style.Stroke(frame, 1.5, rarity.Color)
	local nameLabel = Style.Label(frame, material.Name, 15, rarity.Color, { Size = UDim2.fromScale(1, 1), TextScaled = true })
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = frame
	local rarityLabel = Style.Label(frame, rarity.Name, 14, rarity.Color, { Position = UDim2.new(0, 0, 0.55, 0), Size = UDim2.fromScale(1, 0.45), TextScaled = true })
	rarityLabel.Visible = false
	if rarity.Rainbow then
		Style.Rainbow(rarityLabel)
	end
	return { gui = gui, name = nameLabel, rarity = rarityLabel, detailed = false }
end

-- Switches a plate between the small tag and the detailed card.
local function setDetailed(p, detailed: boolean)
	if p.detailed == detailed then
		return
	end
	p.detailed = detailed
	local size = if detailed then LOOT.PlateFull else LOOT.PlateSmall
	p.gui.Size = UDim2.fromOffset(size.X, size.Y)
	p.rarity.Visible = detailed
	p.name.Size = if detailed then UDim2.fromScale(1, 0.55) else UDim2.fromScale(1, 1)
	p.name.TextColor3 = if detailed then Style.Colors.Text else p.rarity.TextColor3
end

local function spawn(id, materialId, position: Vector3)
	local material = Config.MaterialById[materialId]
	if not material or drops[id] then
		return
	end
	local rarity = Config.Rarity[material.Rarity]

	local holder = Instance.new("Model")
	holder.Name = "Drop_" .. materialId
	holder.Parent = folder

	-- Fixed anchor on the ground: prompt, plate, beam and light hang on it.
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(2, 2, 2)
	anchor.Position = position + Vector3.new(0, LOOT.FloatHeight, 0)
	anchor.Parent = holder

	local model = MaterialBuilder.Build(material)
	model:PivotTo(CFrame.new(anchor.Position))
	model.Parent = holder

	-- Beam straight up in the rarity color.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -LOOT.FloatHeight + 0.2, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, LOOT.BeamHeight, 0)
	a1.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(rarity.Color)
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.Width0 = 1.6
	beam.Width1 = 0.5
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	beam.FaceCamera = true
	beam.Parent = anchor

	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 10
	light.Brightness = 1
	light.Parent = anchor

	local namePlate = plate(anchor, material, rarity)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = LOOT.Texts.Pickup
	prompt.ObjectText = material.Name
	prompt.HoldDuration = LOOT.HoldSeconds
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = LOOT.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("NoPlate", true) -- the drop already has a name plate
	prompt.Parent = anchor
	prompt.Triggered:Connect(function()
		lootRemote:FireServer(id)
	end)

	if rarity.Fx and not Style.HideEffects then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		emitter.LightEmission = 0.7
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.8, 1.5)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 16
		emitter.Parent = anchor
	end
	if rarity.Fx then
		Style.PlaySound(Config.Sounds.RareDrop, if rarity.Announce then 1.5 else 1.15, 0.7)
	end
	if rarity.Announce then
		Popups.Flash(rarity.Color)
		Popups.Shake(0.5, 0.35)
	end

	drops[id] = { holder = holder, model = model, plate = namePlate, base = anchor.Position, phase = math.random() * 6, rainbow = if rarity.Rainbow then { beam = beam, light = light } else nil }

	-- Pop-in.
	pcall(model.ScaleTo, model, 0.2)
	task.spawn(function()
		for i = 1, 8 do
			if not model.Parent then
				return
			end
			pcall(model.ScaleTo, model, 0.2 + i / 8 * 1.0)
			task.wait(0.02)
		end
	end)
end

-- Float + spin (+ rainbow for Secret drops).
local player = Players.LocalPlayer

-- Plates never overlap: nearest first, each one that would cover an
-- already placed plate on screen is lifted by whole plate heights
-- (BillboardGui.SizeOffset), so a pile of drops reads as a neat stack.
local function declutter(root)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local list = {}
	for _, drop in pairs(drops) do
		local gui = drop.plate.gui
		local point, onScreen = camera:WorldToViewportPoint(drop.base + Vector3.new(0, 2.2, 0))
		if onScreen then
			local distance = if root then (root.Position - drop.base).Magnitude else point.Z
			table.insert(list, { gui = gui, x = point.X, y = point.Y, w = gui.Size.X.Offset, h = gui.Size.Y.Offset, d = distance })
		else
			gui.SizeOffset = Vector2.zero
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local placed = {}
	for _, p in ipairs(list) do
		local lift = 0
		local moved = true
		while moved and lift < 8 do
			moved = false
			local y = p.y - lift * (p.h + 4)
			for _, q in ipairs(placed) do
				if math.abs(p.x - q.x) < (p.w + q.w) / 2 and math.abs(y - q.y) < (p.h + q.h) / 2 + 2 then
					lift += 1
					moved = true
					break
				end
			end
		end
		p.gui.SizeOffset = Vector2.new(0, lift * (p.h + 4) / math.max(1, p.h))
		table.insert(placed, { x = p.x, y = p.y - lift * (p.h + 4), w = p.w, h = p.h })
	end
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	declutter(root)
	for _, drop in pairs(drops) do
		if root then
			setDetailed(drop.plate, (root.Position - drop.base).Magnitude <= LOOT.DetailDistance)
		end
		local bob = math.sin(t * 2 + drop.phase) * 0.35
		drop.model:PivotTo(CFrame.new(drop.base + Vector3.new(0, bob, 0)) * CFrame.Angles(0, (t / LOOT.SpinSeconds) * math.pi * 2 + drop.phase, 0))
		if drop.rainbow then
			local color = Color3.fromHSV((t * 0.4) % 1, 0.8, 1)
			drop.rainbow.beam.Color = ColorSequence.new(color)
			drop.rainbow.light.Color = color
		end
	end
end)

lootRemote.OnClientEvent:Connect(function(kind, id, materialId, extra)
	if kind == "Spawn" then
		spawn(id, materialId, extra)
	elseif kind == "Picked" then
		local drop = drops[id]
		local material = Config.MaterialById[materialId]
		if material then
			local rarity = Config.Rarity[material.Rarity]
			local position = if drop then drop.base else nil
			if position then
				Popups.World(position + Vector3.new(0, 1.5, 0), LOOT.Texts.Picked:format(1, material.Name), rarity.Color, 28, false)
			end
			Style.PlaySound(Config.Sounds.Pickup, 1.5 + rarity.Index * 0.08, 0.5)
		end
		remove(id)
	elseif kind == "Remove" then
		remove(id)
	elseif kind == "Clear" then
		for dropId in pairs(drops) do
			remove(dropId)
		end
	end
end)

-- Server-wide announcement (mythic / secret drops): chat line + toast.
local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end
announceRemote.OnClientEvent:Connect(function(text, color)
	text = tostring(text)
	Popups.Toast(text, "gold")
	task.spawn(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			local rich = ('<font color="%s"><b>%s</b></font>'):format(hex(if typeof(color) == "Color3" then color else Style.Colors.Gold), text)
			pcall(general.DisplaySystemMessage, general, rich)
		end
	end)
end)

return LootFx
