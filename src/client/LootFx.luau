--[[
	LootFx.luau
	The player's own loot. The server only tells THIS client about its
	drops (Loot "Spawn"), so nobody else sees or steals them.
	  Item     - the item's model floats and turns over the ground, a beam
	             of the rarity color, a name plate (name, rarity, item
	             level, green arrow when it is better than what is worn);
	             picked up by HOLDING E (button on phones)
	  Chest    - boss chest: hold E, the lid swings open with a burst and
	             the items fly out as normal drops
	  Artifact - a floating core with a gold beam
	Legendary+ flashes the screen (the server also writes it to chat).
	Picked items go to the loot feed on the right side of the screen
	(click a row to see the item in the inventory).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local ArmorBuilder = require(ReplicatedStorage.Shared.ArmorBuilder)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local PlayerData = require(script.Parent.PlayerData)
local Popups = require(script.Parent.ui.Popups)
local ItemIcon = require(script.Parent.ui.ItemIcon)
local Icons = require(script.Parent.ui.Icons)
local Style = require(script.Parent.ui.Style)
local SystemNotice = require(script.Parent.ui.SystemNotice)
local Inventory = require(script.Parent.ui.Windows.Inventory)

local LOOT = Config.Loot
local C = Style.Colors
local player = Players.LocalPlayer
local lootRemote = ReplicatedStorage:WaitForChild("Loot")
local announceRemote = ReplicatedStorage:WaitForChild("Announce")
local GREEN = Color3.fromRGB(90, 230, 110)
local FLASH_FROM = Config.Rarity[LOOT.FlashFrom].Index

local LootFx = {}

local folder = Instance.new("Folder")
folder.Name = "LocalLoot"
folder.Parent = Workspace

local drops = {} -- [id] = { holder, model, base, phase, kind, lid }

local function remove(id)
	local drop = drops[id]
	if drop then
		drops[id] = nil
		drop.holder:Destroy()
	end
end

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for key, value in pairs(props) do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function isBetter(view): boolean
	return Items.CanUse(view, player:GetAttribute("Class")) and Items.IsBetter(view, PlayerData.Worn(view.Slot))
end

-- Beam of light + ground ring of a color.
local function beam(holder, ground: Vector3, color: Color3, strong: boolean)
	local height = LOOT.BeamHeight
	part(holder, {
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, if strong then 0.5 else 0.3, if strong then 0.5 else 0.3),
		CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = if strong then 0.6 else 0.75,
	})
	part(holder, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, 4.4, 4.4),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
end

local plateIndex = 0
local function plate(anchor: BasePart, title: string, color: Color3, sub: string, better: boolean)
	plateIndex += 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Size = UDim2.fromOffset(190, if better then 62 else 46)
	-- neighbours sit at different heights so their plates don't stack
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2 + (plateIndex % 3) * 1.5, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true -- the beam never covers the text
	gui.Parent = anchor
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = C.PanelDark
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Style.Corner(frame, UDim.new(0, 3))
	Style.Stroke(frame, 1.5, color)
	Style.Label(frame, title, 15, color, { Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	Style.Label(frame, sub, 12, C.Text, { Position = UDim2.fromOffset(4, 24), Size = UDim2.new(1, -8, 0, 16) })
	if better then
		Style.Label(frame, "▲ " .. LOOT.Texts.Better, 12, GREEN, { Position = UDim2.fromOffset(4, 42), Size = UDim2.new(1, -8, 0, 16) })
	end
	return gui
end

local function prompt(anchor: BasePart, id: number, action: string, object: string)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = LOOT.HoldSeconds
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = LOOT.PromptDistance
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Custom
	p:SetAttribute("NoPlate", true) -- the drop already has a name plate
	p.Parent = anchor
	p.Triggered:Connect(function()
		lootRemote:FireServer(id)
	end)
	return p
end

local function still(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
end

local function spawnItem(id: number, instance, position: Vector3)
	local view = Items.Resolve(instance)
	if not view then
		return
	end
	local rarity = Config.Rarity[view.Rarity] or Config.Rarity.Common
	local holder = Instance.new("Model")
	holder.Name = "Drop" .. id
	holder.Parent = folder
	local center = position + Vector3.new(0, LOOT.FloatHeight, 0)
	local anchor = part(holder, { Name = "Anchor", Size = Vector3.new(1.5, 1.5, 1.5), CFrame = CFrame.new(center), Transparency = 1 })

	local ok, model = pcall(function()
		if view.Kind == "Weapon" then
			return WeaponBuilder.Build(view)
		end
		return ArmorBuilder.Build(view)
	end)
	if ok and model then
		still(model)
		local size = model:GetExtentsSize()
		pcall(model.ScaleTo, model, math.clamp(2.6 / math.max(size.X, size.Y, size.Z, 0.1), 0.3, 2))
		local tilt = if view.Kind == "Weapon" then CFrame.Angles(0, 0, math.rad(35)) else CFrame.new()
		model:PivotTo(CFrame.new(model:GetPivot().Position) * tilt)
		local box = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() + (center - box.Position))
		model.WorldPivot = CFrame.new(center) * model:GetPivot().Rotation
		model.Parent = holder
	else
		model = nil
	end

	local strong = rarity.Index >= Config.Rarity.Epic.Index
	beam(holder, position, rarity.Color, strong)
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = if strong then 14 else 9
	light.Brightness = if strong then 1.6 else 0.9
	light.Parent = anchor
	if rarity.Index >= FLASH_FROM and not Style.HideEffects then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		emitter.LightEmission = 0.7
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.8, 1.5)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 16
		emitter.Parent = anchor
	end

	local stat = if view.Kind == "Weapon" then "Урон " .. view.Damage else "+" .. view.Health .. " HP"
	plate(anchor, view.Name, rarity.Color, ("%s  •  ур. %d  •  %s"):format(rarity.Name, view.ItemLevel, stat), isBetter(view))
	prompt(anchor, id, LOOT.Texts.Pickup, view.Name)

	if rarity.Index >= FLASH_FROM then
		Popups.Flash(rarity.Color)
		Popups.Shake(0.5, 0.35)
		Style.PlaySound(Config.Sounds.RareDrop, 1.3, 0.7)
	elseif strong then
		Style.PlaySound(Config.Sounds.RareDrop, 1.1, 0.5)
	end
	drops[id] = { holder = holder, model = model, base = center, phase = math.random() * 6, kind = "Item", view = view, tilt = if view.Kind == "Weapon" then CFrame.Angles(0, 0, math.rad(35)) else nil }
end

local function spawnChest(id: number, payload, position: Vector3)
	local color = Config.Gates.Colors[payload.Rank or "E"] or C.Gold
	local holder = Instance.new("Model")
	holder.Name = "Chest" .. id
	holder.Parent = folder
	local s = LOOT.Chest.Scale
	local cf = CFrame.new(position)
	local root = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.Position
	if root then
		cf = CFrame.lookAt(position, Vector3.new(root.X, position.Y, root.Z))
	end
	local dark, steel = Color3.fromRGB(30, 32, 38), Color3.fromRGB(86, 90, 100)
	local body = part(holder, { Name = "Body", Size = Vector3.new(4.4, 2.2, 3) * s, CFrame = cf * CFrame.new(0, 1.1 * s, 0), Color = dark, Material = Enum.Material.Metal, CanCollide = true })
	for _, x in ipairs({ -1.6, 0, 1.6 }) do
		part(holder, { Name = "Band", Size = Vector3.new(0.4, 2.3, 3.1) * s, CFrame = cf * CFrame.new(x * s, 1.1 * s, 0), Color = steel, Material = Enum.Material.DiamondPlate })
	end
	part(holder, { Name = "Seam", Size = Vector3.new(4.5, 0.12, 3.1) * s, CFrame = cf * CFrame.new(0, 2.2 * s, 0), Color = color, Material = Enum.Material.Neon })
	part(holder, { Name = "Lock", Size = Vector3.new(0.8, 0.9, 0.3) * s, CFrame = cf * CFrame.new(0, 1.9 * s, -1.55 * s), Color = C.Gold, Material = Enum.Material.Metal })
	-- the lid: a model that turns around its back edge (hinge)
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	lid.Parent = holder
	part(lid, { Name = "Top", Size = Vector3.new(4.4, 0.9, 3) * s, CFrame = cf * CFrame.new(0, 2.7 * s, 0), Color = dark, Material = Enum.Material.Metal })
	for _, x in ipairs({ -1.6, 0, 1.6 }) do
		part(lid, { Name = "Band", Size = Vector3.new(0.4, 1, 3.1) * s, CFrame = cf * CFrame.new(x * s, 2.7 * s, 0), Color = steel, Material = Enum.Material.DiamondPlate })
	end
	part(lid, { Name = "Crest", Size = Vector3.new(1.2, 0.2, 1.2) * s, CFrame = cf * CFrame.new(0, 3.2 * s, 0) * CFrame.Angles(0, math.rad(45), 0), Color = C.Gold, Material = Enum.Material.Metal })
	local hinge = cf * CFrame.new(0, 2.25 * s, 1.5 * s)
	lid.WorldPivot = hinge
	beam(holder, position, color, true)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Brightness = 1.6
	light.Parent = body
	plate(body, LOOT.Texts.ChestName, C.Gold, "Ранг " .. (payload.Rank or "E"), false)
	prompt(body, id, LOOT.Texts.OpenChest, LOOT.Texts.ChestName)
	Style.PlaySound(Config.Sounds.RareDrop, 0.9, 0.6)
	drops[id] = { holder = holder, kind = "Chest", lid = lid, hinge = hinge, body = body, color = color }
end

local function openChest(id: number)
	local drop = drops[id]
	if not drop or drop.kind ~= "Chest" then
		return
	end
	drops[id] = nil
	for _, d in ipairs(drop.holder:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	local seconds = LOOT.Chest.OpenSeconds
	local started = os.clock()
	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(drop.color, Color3.new(1, 1, 1))
	burst.LightEmission = 0.9
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	burst.Lifetime = NumberRange.new(0.6, 1.2)
	burst.Speed = NumberRange.new(10, 18)
	burst.SpreadAngle = Vector2.new(35, 35)
	burst.EmissionDirection = Enum.NormalId.Top
	burst.Rate = 0
	burst.Parent = drop.body
	Style.PlaySound(Config.Sounds.Unsheath, 0.8, 0.7)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - started) / (seconds * 0.7), 0, 1)
		local eased = 1 - (1 - a) ^ 3
		if drop.lid.Parent then
			drop.lid:PivotTo(drop.hinge * CFrame.Angles(math.rad(105) * eased, 0, 0))
		end
		if a >= 1 then
			connection:Disconnect()
		end
	end)
	task.delay(seconds * 0.6, function()
		burst:Emit(40)
		Style.PlaySound(Config.Sounds.RareDrop, 1.2, 0.7)
	end)
	task.delay(seconds + 2.5, function()
		for _, d in ipairs(drop.holder:GetDescendants()) do
			if d:IsA("BasePart") then
				TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.6)
		drop.holder:Destroy()
	end)
end

local function spawnArtifact(id: number, payload, position: Vector3)
	local def = Config.ArtifactById and Config.ArtifactById[payload.Id]
	if not def then
		return
	end
	local rarity = Config.Rarity[def.Rarity] or Config.Rarity.Epic
	local holder = Instance.new("Model")
	holder.Name = "Artifact" .. id
	holder.Parent = folder
	local center = position + Vector3.new(0, LOOT.FloatHeight, 0)
	local anchor = part(holder, { Name = "Anchor", Size = Vector3.new(1.5, 1.5, 1.5), CFrame = CFrame.new(center), Transparency = 1 })
	local model = Instance.new("Model")
	model.Parent = holder
	part(model, { Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = CFrame.new(center), Color = rarity.Color, Material = Enum.Material.Neon })
	for i = 0, 1 do
		part(model, { Name = "Ring", Size = Vector3.new(2.4, 0.14, 0.14), CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(90 * i), math.rad(35)), Color = C.Gold, Material = Enum.Material.Metal })
		part(model, { Name = "Ring", Size = Vector3.new(0.14, 0.14, 2.4), CFrame = CFrame.new(center) * CFrame.Angles(math.rad(35), math.rad(90 * i), 0), Color = C.Gold, Material = Enum.Material.Metal })
	end
	model.WorldPivot = CFrame.new(center)
	beam(holder, position, C.Gold, true)
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = anchor
	plate(anchor, def.Name, rarity.Color, LOOT.Texts.Artifact .. "  •  " .. rarity.Name, false)
	prompt(anchor, id, LOOT.Texts.Pickup, def.Name)
	Popups.Flash(rarity.Color)
	Style.PlaySound(Config.Sounds.RareDrop, 1.4, 0.7)
	drops[id] = { holder = holder, model = model, base = center, phase = math.random() * 6, kind = "Artifact" }
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, drop in pairs(drops) do
		if drop.model and drop.model.Parent then
			local y = math.sin(t * 2 + drop.phase) * 0.25
			drop.model:PivotTo(CFrame.new(drop.base + Vector3.new(0, y, 0)) * CFrame.Angles(0, t * 1.2 + drop.phase, 0) * (drop.tilt or CFrame.new()))
		end
	end
end)

---------------------------------------------------------------------
-- Loot feed (right side)
---------------------------------------------------------------------

local feed = Instance.new("Frame")
feed.Name = "LootFeed"
feed.AnchorPoint = Vector2.new(1, 0.5)
feed.Position = UDim2.new(1, -12, 0.5, -40)
feed.Size = UDim2.fromOffset(250, 300)
feed.BackgroundTransparency = 1
feed.ZIndex = 8
feed.Parent = Style.Gui
local feedLayout = Instance.new("UIListLayout")
feedLayout.Padding = UDim.new(0, 6)
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Center
feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
feedLayout.Parent = feed
local feedOrder = 0
local feedRows = {}

local function feedRow(color: Color3, title: string, sub: string, better: boolean, makeIcon, onClick)
	feedOrder += 1
	local row = Instance.new("TextButton")
	row.Name = "Row"
	row.Size = UDim2.fromOffset(250, 50)
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Text = ""
	row.LayoutOrder = feedOrder
	row.ZIndex = 8
	row.Parent = feed
	Style.Panel(row, { Size = UDim2.fromScale(1, 1), Fill = C.PanelDark, Transparency = 0.1, Border = color, Cut = 6, ZIndex = 8 })
	local iconHolder = Instance.new("Frame")
	iconHolder.Position = UDim2.fromOffset(6, 5)
	iconHolder.Size = UDim2.fromOffset(40, 40)
	iconHolder.BackgroundTransparency = 1
	iconHolder.ZIndex = 9
	iconHolder.Parent = row
	makeIcon(iconHolder)
	Style.Label(row, title, 13, color, { Position = UDim2.fromOffset(52, 6), Size = UDim2.new(1, -78, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 10 })
	Style.Label(row, sub, 11, C.Muted, { Position = UDim2.fromOffset(52, 26), Size = UDim2.new(1, -78, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 10 })
	if better then
		Style.Label(row, "▲", 18, GREEN, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(18, 20), ZIndex = 10 })
	end
	if onClick then
		row.Activated:Connect(onClick)
	end
	table.insert(feedRows, row)
	while #feedRows > LOOT.Feed.Max do
		table.remove(feedRows, 1):Destroy()
	end
	task.delay(LOOT.Feed.Seconds, function()
		local index = table.find(feedRows, row)
		if index then
			table.remove(feedRows, index)
			row:Destroy()
		end
	end)
end

-- A picked item in the feed (also used for rewards).
function LootFx.FeedItem(instance)
	local view = Items.Resolve(instance)
	if not view then
		return
	end
	local rarity = Config.Rarity[view.Rarity] or Config.Rarity.Common
	local stat = if view.Kind == "Weapon" then "Урон " .. view.Damage else "+" .. view.Health .. " HP"
	-- compare with what was worn BEFORE this item arrived
	local better = Items.CanUse(view, player:GetAttribute("Class")) and Items.IsBetter(view, PlayerData.Worn(view.Slot))
	feedRow(rarity.Color, view.Name, ("%s  •  ур. %d  •  %s"):format(rarity.Name, view.ItemLevel, stat), better, function(holder)
		ItemIcon.Create(holder, view.Kind, view, UDim2.fromScale(1, 1), UDim2.new())
	end, function()
		Inventory.Show(view.Uid)
	end)
end

function LootFx.FeedArtifact(info)
	local def = Config.ArtifactById and Config.ArtifactById[info and info.Id or ""]
	if not def then
		return
	end
	local rarity = Config.Rarity[def.Rarity] or Config.Rarity.Epic
	feedRow(rarity.Color, def.Name, if info.New then LOOT.Texts.Artifact .. "  •  новый!" else LOOT.Texts.Artifact .. "  •  дубликат", info.New == true, function(holder)
		local icon = Icons.Make(holder, def.Icon or "star", 28, rarity.Color, 10)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	end)
end

---------------------------------------------------------------------

lootRemote.OnClientEvent:Connect(function(action, id, kind, payload, position)
	if action == "Spawn" then
		remove(id)
		if kind == "Item" then
			spawnItem(id, payload, position)
		elseif kind == "Chest" then
			spawnChest(id, payload, position)
		elseif kind == "Artifact" then
			spawnArtifact(id, payload, position)
		end
	elseif action == "Open" then
		openChest(id)
	elseif action == "Picked" then
		if kind == "Item" then
			LootFx.FeedItem(payload)
			local rarity = Config.Rarity[payload.R] or Config.Rarity.Common
			if rarity.Index >= Config.Rarity[Config.System.ItemFrom].Index then
				local view = Items.Resolve(payload)
				SystemNotice.Show(Config.System.Texts.Got:format(view.Name), { rarity.Name .. "  •  " .. Config.Items.Texts.Level:format(view.ItemLevel) }, if rarity.Index >= FLASH_FROM then "gold" else nil)
			end
			Style.PlaySound(Config.Sounds.Pickup, 1.4 + rarity.Index * 0.08, 0.5)
		elseif kind == "Artifact" then
			LootFx.FeedArtifact(payload)
			local def = Config.ArtifactById[payload and payload.Id or ""]
			if def then
				SystemNotice.Show(Config.System.Texts.Artifact:format(def.Name), { Config.ArtifactText(def, payload.Level or 1) }, "gold")
			end
			Style.PlaySound(Config.Sounds.Pickup, 2, 0.6)
		end
		remove(id)
	elseif action == "Remove" then
		remove(id)
	elseif action == "Clear" then
		for dropId in pairs(drops) do
			remove(dropId)
		end
	end
end)

-- Server-wide announcement (legendary+ drops): chat line + toast.
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
