--[[
	Forge.luau
	"Кузница": craft weapons and armor from materials (Config.Recipes).

	Left: recipe list with an Оружие / Броня filter; a lock marks recipes
	that cannot be forged yet and the first missing material is shown in
	red ("Кость 12/20"). Right: rotating model preview, stats compared
	with what is equipped (+ green / - red), the full cost and the
	"Выковать" button.

	The craft animation (~2.5 s, skippable on repeat crafts):
	  1. material icons fly from the list along arcs onto the anvil,
	  2. three hammer strikes: sparks, window shake, sound, a glow of the
	     result's rarity color that grows with every strike,
	  3. flash, the item appears big and spinning with rotating light
	     rays of its rarity color behind it and its name popping in.
	(The server also flares the hub forge for everyone nearby.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local MaterialBuilder = require(ReplicatedStorage.Shared.MaterialBuilder)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local Preview = require(script.Parent.Parent.Preview)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local craftRemote = ReplicatedStorage:WaitForChild("Craft")
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local Forge = {}

local Texts = Config.Forge.Texts
local GREEN, RED = Style.Colors.Green, Style.Colors.Red

local window = Window.new("Кузница", Style.Colors.Orange, Vector2.new(790, 510))
local content = window.Content

---------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------

local function itemOf(recipe)
	return Config.ItemById[recipe.Kind][recipe.Id]
end

local function isOwned(recipe): boolean
	return PlayerData.Set(if recipe.Kind == "Weapon" then "OwnedWeapon" else "OwnedArmor")[recipe.Id] == true
end

-- Sorted material list of a recipe: { { material, need, have } }.
local function costOf(recipe)
	local list = {}
	for materialId, need in pairs(recipe.Materials) do
		local material = Config.MaterialById[materialId]
		if material then
			table.insert(list, { material = material, need = need, have = PlayerData.MaterialCount(materialId) })
		end
	end
	table.sort(list, function(a, b)
		return a.material.Order < b.material.Order
	end)
	return list
end

-- "ok" | "materials" | "aura" | "owned", plus the first missing entry.
local function stateOf(recipe)
	if isOwned(recipe) then
		return "owned"
	end
	for _, entry in ipairs(costOf(recipe)) do
		if entry.have < entry.need then
			return "materials", entry
		end
	end
	if aura.Value < recipe.Aura then
		return "aura"
	end
	return "ok"
end

---------------------------------------------------------------------
-- Left: filter + recipe list
---------------------------------------------------------------------

local LEFT = 318
local left = Instance.new("Frame")
left.Size = UDim2.new(0, LEFT, 1, 0)
left.BackgroundTransparency = 1
left.ZIndex = 32
left.Parent = content
local tabs, selectTab = Window.Tabs(left, { { Id = "Weapon", Text = "⚔ Оружие" }, { Id = "Armor", Text = "🛡 Броня" } }, Style.Colors.Orange, 153)

local listHolder = Instance.new("Frame")
listHolder.Position = UDim2.fromOffset(0, 48)
listHolder.Size = UDim2.new(1, 0, 1, -48)
listHolder.BackgroundTransparency = 1
listHolder.ZIndex = 32
listHolder.Parent = left
local list = Window.List(listHolder)

local rows = {} -- [recipeId] = { button, stroke, status, lock, recipe }
local selected = nil -- recipe
local showDetails -- defined below

for _, recipe in ipairs(Config.Recipes) do
	local item = itemOf(recipe)
	local rarity = Config.Rarity[item.Rarity]
	local row = Instance.new("TextButton")
	row.Name = recipe.Id
	row.LayoutOrder = recipe.Order
	row.Size = UDim2.new(1, -10, 0, 66)
	row.BackgroundColor3 = Style.Colors.Card
	row.AutoButtonColor = false
	row.Text = ""
	row.ZIndex = 33
	row.Parent = list
	Style.Corner(row, UDim.new(0, 12))
	local stroke = Style.Stroke(row, 2.5, rarity.Color)
	Preview.Create(row, recipe.Kind, item, UDim2.fromOffset(52, 52), UDim2.fromOffset(7, 7))
	local name = Style.Label(row, item.Name, 17, rarity.Color, { Position = UDim2.fromOffset(66, 6), Size = UDim2.new(1, -104, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 35 })
	if rarity.Rainbow then
		Style.Rainbow(name)
	end
	local status = Style.Label(row, "", 15, Style.Colors.Muted, { Position = UDim2.fromOffset(66, 34), Size = UDim2.new(1, -104, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 35 })
	local lock = Style.Label(row, "🔒", 22, Style.Colors.Text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(30, 30), ZIndex = 35 })
	rows[recipe.Id] = { button = row, stroke = stroke, status = status, lock = lock, recipe = recipe }
	row.Activated:Connect(function()
		showDetails(recipe)
	end)
end

local function refreshRows()
	for _, row in pairs(rows) do
		local recipe = row.recipe
		local state, missing = stateOf(recipe)
		row.button.Visible = recipe.Kind == tabs.Current
		row.lock.Visible = state == "materials" or state == "aura"
		row.stroke.Thickness = if selected == recipe then 4.5 else 2.5
		row.button.BackgroundColor3 = if selected == recipe then Style.Lighter(Style.Colors.Card, 0.12) else Style.Colors.Card
		if state == "owned" then
			row.status.Text = "Выковано ✓"
			row.status.TextColor3 = Style.Colors.Muted
		elseif state == "ok" then
			row.status.Text = "Можно ковать!"
			row.status.TextColor3 = GREEN
		elseif state == "aura" then
			row.status.Text = ("Аура %s/%s"):format(Format.Number(aura.Value), Format.Number(recipe.Aura))
			row.status.TextColor3 = RED
		else
			row.status.Text = ("%s %d/%d"):format(missing.material.Name, missing.have, missing.need)
			row.status.TextColor3 = RED
		end
	end
end

---------------------------------------------------------------------
-- Right: preview, stats, cost, button
---------------------------------------------------------------------

local right = Instance.new("Frame")
right.Position = UDim2.fromOffset(LEFT + 12, 0)
right.Size = UDim2.new(1, -(LEFT + 12), 1, 0)
right.BackgroundTransparency = 1
right.ZIndex = 32
right.Parent = content

local previewHolder = Instance.new("Frame")
previewHolder.Size = UDim2.fromOffset(190, 190)
previewHolder.BackgroundTransparency = 1
previewHolder.ZIndex = 32
previewHolder.Parent = right

local nameLabel = Style.Label(right, "", 24, Style.Colors.Text, { Position = UDim2.fromOffset(200, 0), Size = UDim2.new(1, -200, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 33 })
local rarityLabel = Style.Label(right, "", 16, Style.Colors.Text, { Position = UDim2.fromOffset(200, 36), Size = UDim2.new(1, -200, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local statLabels = {}
for i = 1, 4 do
	statLabels[i] = Style.Label(right, "", 17, Style.Colors.Text, { Position = UDim2.fromOffset(200, 34 + i * 30), Size = UDim2.new(1, -200, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, RichText = true, ZIndex = 33 })
end

local costTitle = Style.Label(right, "Нужно для ковки:", 17, Style.Colors.Gold, { Position = UDim2.fromOffset(0, 198), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local costRows = {}
for i = 1, 5 do
	local plate = Style.Plate(right, { Position = UDim2.fromOffset(((i - 1) % 2) * 214, 224 + math.floor((i - 1) / 2) * 38), Size = UDim2.fromOffset(206, 32), Color = Style.Colors.Card, ZIndex = 33 })
	local chip = Instance.new("Frame")
	chip.Position = UDim2.fromOffset(6, 6)
	chip.Size = UDim2.fromOffset(20, 20)
	chip.ZIndex = 34
	chip.Parent = plate
	Style.Corner(chip, UDim.new(0, 6))
	local text = Style.Label(plate, "", 16, Style.Colors.Text, { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -38, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 34 })
	costRows[i] = { plate = plate, chip = chip, text = text }
end

local craftButton, setCraftColor = Style.Button(right, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 54), Color = GREEN, Text = Texts.Craft, TextSize = 24, ZIndex = 34, Shadow = false })

local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

-- "+16" green / "-3" red / "" when equal.
local function delta(value: number, suffix: string?): string
	if math.abs(value) < 0.0001 then
		return ""
	end
	return ('  <font color="%s">%s%s%s</font>'):format(hex(if value > 0 then GREEN else RED), if value > 0 then "+" else "-", Format.Number(math.abs(value)), suffix or "")
end

local function refreshDetails()
	local recipe = selected
	if not recipe then
		return
	end
	local item = itemOf(recipe)
	local rarity = Config.Rarity[item.Rarity]
	nameLabel.Text = item.Name
	nameLabel.TextColor3 = rarity.Color
	rarityLabel.Text = rarity.Name .. (if item.Biome then "  •  " .. Config.DungeonLayout.Biomes[item.Biome].Name else "")
	rarityLabel.TextColor3 = rarity.Color

	for _, label in ipairs(statLabels) do
		label.Text = ""
	end
	if recipe.Kind == "Weapon" then
		local current = Config.ItemById.Weapon[player:GetAttribute("EquippedWeapon") or ""]
		local currentDamage = if current then current.Damage else 1
		statLabels[1].Text = ("⚔ Урон оружия: %s%s"):format(Format.Number(item.Damage), delta(item.Damage - currentDamage))
		statLabels[2].Text = ("Сейчас: %s (%s)"):format(Format.Number(currentDamage), if current then current.Name else "—")
		local mine = player:GetAttribute("ClickPower") or 1
		statLabels[3].Text = ("Твой удар станет около %s"):format(Format.Number(mine / math.max(1, currentDamage) * item.Damage))
	else
		local current = Config.ItemById.Armor[player:GetAttribute("Equipped" .. item.Slot) or ""]
		local set = Config.ArmorSets[item.Set]
		statLabels[1].Text = ("❤ Здоровье: +%d%s"):format(item.Health, delta(item.Health - (if current then current.Health else 0)))
		statLabels[2].Text = ("🛡 Защита: +%d%%%s"):format(math.floor(item.Defense * 100 + 0.5), delta((item.Defense - (if current then current.Defense else 0)) * 100, "%"))
		statLabels[3].Text = ("%s: %s"):format(Config.ArmorSlotNames[item.Slot], if current then "сейчас " .. current.Name else "слот пуст")
		statLabels[4].Text = ('<font color="%s">%s (3 части): +%d%% урона</font>'):format(hex(Style.Colors.Gold), set.Name, math.floor(set.Bonus * 100 + 0.5))
	end

	local cost = costOf(recipe)
	for i, row in ipairs(costRows) do
		local entry = cost[i]
		if entry then
			row.plate.Visible = true
			row.chip.BackgroundColor3 = Config.Rarity[entry.material.Rarity].Color
			row.text.Text = ("%s %s/%s"):format(entry.material.Name, Format.Number(entry.have), Format.Number(entry.need))
			row.text.TextColor3 = if entry.have >= entry.need then GREEN else RED
		elseif i == #cost + 1 then
			row.plate.Visible = true
			row.chip.BackgroundColor3 = Style.Colors.Gold
			row.text.Text = ("Аура %s/%s"):format(Format.Number(aura.Value), Format.Number(recipe.Aura))
			row.text.TextColor3 = if aura.Value >= recipe.Aura then GREEN else RED
		else
			row.plate.Visible = false
		end
	end

	local state = stateOf(recipe)
	if state == "owned" then
		craftButton.Text = Texts.Owned
		setCraftColor(Color3.fromRGB(110, 110, 130))
	elseif state == "ok" then
		craftButton.Text = "⚒ " .. Texts.Craft
		setCraftColor(GREEN)
	else
		craftButton.Text = if state == "aura" then Texts.NoAura else Texts.Missing
		setCraftColor(Color3.fromRGB(110, 110, 130))
	end
end

function showDetails(recipe)
	if selected ~= recipe then
		selected = recipe
		previewHolder:ClearAllChildren()
		local item = itemOf(recipe)
		local viewport = Preview.Create(previewHolder, recipe.Kind, item, UDim2.fromScale(1, 1), UDim2.new())
		if viewport then
			Style.Stroke(viewport, 3, Config.Rarity[item.Rarity].Color)
		end
	end
	refreshDetails()
	refreshRows()
end

---------------------------------------------------------------------
-- Craft animation
---------------------------------------------------------------------

local overlay = Instance.new("TextButton") -- a button: swallows clicks on the window below
overlay.Name = "CraftAnimation"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Style.Colors.PanelDark
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = window.Frame
Style.Corner(overlay, UDim.new(0, 20))

local animToken = 0
local crafts = 0 -- crafts this session: the Skip button appears from the 2nd one
local skipRequested = false

local skipButton = Style.Button(overlay, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(170, 44), Color = Style.Colors.Blue, Text = Texts.Skip, TextSize = 18, ZIndex = 70, Shadow = false })
skipButton.Activated:Connect(function()
	skipRequested = true
end)

local ANVIL = Vector2.new(0.5, 0.66) -- center of the anvil face (scale)
local STEEL = Color3.fromRGB(78, 78, 96)

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for key, value in pairs(props) do
		f[key] = value
	end
	f.Parent = parent
	return f
end

-- Static icon of a material (ViewportFrame with a fixed camera).
local function materialChip(parent, material)
	local viewport = Instance.new("ViewportFrame")
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Size = UDim2.fromOffset(50, 50)
	viewport.BackgroundColor3 = Style.Colors.CardDark
	viewport.Ambient = Color3.fromRGB(200, 200, 215)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.ZIndex = 56
	viewport.Parent = parent
	Style.Corner(viewport, UDim.new(0.5, 0))
	Style.Stroke(viewport, 2.5, Config.Rarity[material.Rarity].Color)
	local model = MaterialBuilder.Build(material)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(2.6, 1.6, -4), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function sparks(parent, at: UDim2, color: Color3, count: number)
	for _ = 1, count do
		local spark = frame(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = at, Size = UDim2.fromOffset(7, 7), BackgroundColor3 = if math.random() < 0.5 then color else Color3.fromRGB(255, 240, 180), ZIndex = 62, Rotation = math.random(0, 90) })
		local angle = math.rad(math.random(200, 340)) -- upwards fan
		local distance = math.random(60, 170)
		Style.Tween(spark, 0.45, { Position = at + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance + 30), BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.5, function()
			spark:Destroy()
		end)
	end
end

local function shakeWindow()
	local home = UDim2.fromScale(0.5, 0.5)
	task.spawn(function()
		for i = 1, 5 do
			local power = (6 - i) * 2.4
			window.Frame.Position = home + UDim2.fromOffset((math.random() - 0.5) * power * 2, (math.random() - 0.5) * power * 2)
			task.wait(0.025)
		end
		window.Frame.Position = home
	end)
end

local function closeOverlay()
	animToken += 1
	overlay.Visible = false
	for _, child in ipairs(overlay:GetChildren()) do
		if child ~= skipButton and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	window.Frame.Position = UDim2.fromScale(0.5, 0.5)
end

-- Step 3: the forged item, big, with rotating rays and its name.
local function reveal(recipe, token)
	local item = itemOf(recipe)
	local rarity = Config.Rarity[item.Rarity]
	for _, child in ipairs(overlay:GetChildren()) do
		if child ~= skipButton and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	skipButton.Visible = false

	local flash = frame(overlay, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 69 })
	Style.Corner(flash, UDim.new(0, 20))
	Style.Tween(flash, 0.45, { BackgroundTransparency = 1 })
	task.delay(0.5, function()
		flash:Destroy()
	end)
	Style.PlaySound(Config.Sounds.Forged, 1.1 + rarity.Index * 0.05, 0.7)
	Popups.Shake(0.4, 0.25)

	-- Rays: a rotating fan of bars behind the item.
	local rays = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(4, 4), BackgroundTransparency = 1, ZIndex = 52 })
	for i = 0, 11 do
		local holder = frame(rays, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 440), BackgroundTransparency = 1, Rotation = i * 30, ZIndex = 52 })
		local ray = frame(holder, { Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = rarity.Color, BackgroundTransparency = 0.35, ZIndex = 52 })
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
		gradient.Parent = ray
	end
	local glow = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(250, 250), BackgroundColor3 = rarity.Color, BackgroundTransparency = 0.55, ZIndex = 53 })
	Style.Corner(glow, UDim.new(0.5, 0))

	local holder = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(250, 250), BackgroundTransparency = 1, ZIndex = 54 })
	local viewport = Preview.Create(holder, recipe.Kind, item, UDim2.fromScale(1, 1), UDim2.new())
	if viewport then
		viewport.BackgroundTransparency = 1
	end
	local grow = Instance.new("UIScale")
	grow.Scale = 0.2
	grow.Parent = holder
	Style.Tween(grow, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	local name = Style.Label(overlay, item.Name, 40, rarity.Color, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(1, -40, 0, 50), TextScaled = true, ZIndex = 60 })
	if rarity.Rainbow then
		Style.Rainbow(name)
	end
	local nameScale = Instance.new("UIScale")
	nameScale.Scale = 0
	nameScale.Parent = name
	task.delay(0.2, function()
		Style.Tween(nameScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	Style.Label(overlay, rarity.Name, 22, Style.Colors.Text, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.83), Size = UDim2.new(1, -40, 0, 28), ZIndex = 60 })

	local done = Style.Button(overlay, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(220, 46), Color = GREEN, Text = "Отлично!", TextSize = 22, ZIndex = 70, Shadow = false })
	done.Activated:Connect(closeOverlay)

	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if token ~= animToken or not rays.Parent then
			connection:Disconnect()
			return
		end
		rays.Rotation += dt * 28
	end)
	task.delay(6, function()
		if token == animToken then
			closeOverlay()
		end
	end)
end

local function playCraft(recipe)
	animToken += 1
	local token = animToken
	skipRequested = false
	crafts += 1
	skipButton.Visible = crafts > 1
	overlay.Visible = true
	local item = itemOf(recipe)
	local rarity = Config.Rarity[item.Rarity]

	-- waits; false when the animation was replaced / skipped
	local function wait(seconds: number): boolean
		local elapsed = 0
		while elapsed < seconds do
			elapsed += task.wait()
			if token ~= animToken or skipRequested then
				return false
			end
		end
		return true
	end

	-- Scene: anvil, hammer, glow.
	local anvilPos = UDim2.fromScale(ANVIL.X, ANVIL.Y)
	local glow = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = anvilPos + UDim2.fromOffset(0, -30), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = rarity.Color, BackgroundTransparency = 0.8, ZIndex = 51 })
	Style.Corner(glow, UDim.new(0.5, 0))
	local top = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = anvilPos, Size = UDim2.fromOffset(240, 40), BackgroundColor3 = STEEL, ZIndex = 53 })
	Style.Corner(top, UDim.new(0, 8))
	Style.Stroke(top, 3)
	local horn = frame(overlay, { AnchorPoint = Vector2.new(1, 0), Position = anvilPos + UDim2.fromOffset(-112, 5), Size = UDim2.fromOffset(74, 24), BackgroundColor3 = STEEL, ZIndex = 52 })
	Style.Corner(horn, UDim.new(0.5, 0))
	Style.Stroke(horn, 3)
	local waist = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = anvilPos + UDim2.fromOffset(0, 38), Size = UDim2.fromOffset(96, 40), BackgroundColor3 = Style.Darker(STEEL, 0.2), ZIndex = 52 })
	Style.Stroke(waist, 3)
	local foot = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = anvilPos + UDim2.fromOffset(0, 76), Size = UDim2.fromOffset(170, 30), BackgroundColor3 = STEEL, ZIndex = 53 })
	Style.Corner(foot, UDim.new(0, 8))
	Style.Stroke(foot, 3)

	-- Hammer: rotates around its pivot (the handle end, right of the anvil).
	local hammer = frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = anvilPos + UDim2.fromOffset(150, -34), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Rotation = 55, ZIndex = 58 })
	local handle = frame(hammer, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(150, 16), BackgroundColor3 = Color3.fromRGB(150, 100, 60), ZIndex = 58 })
	Style.Corner(handle, UDim.new(0.5, 0))
	Style.Stroke(handle, 3)
	local head = frame(hammer, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -150, 0.5, 0), Size = UDim2.fromOffset(52, 68), BackgroundColor3 = Color3.fromRGB(120, 120, 140), ZIndex = 59 })
	Style.Corner(head, UDim.new(0, 8))
	Style.Stroke(head, 3)

	local title = Style.Label(overlay, "Куём: " .. item.Name, 28, Style.Colors.Text, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 36), ZIndex = 60 })
	title.TextColor3 = rarity.Color

	task.spawn(function()
		-- 1. Materials fly from the list (left) onto the anvil along arcs.
		local cost = costOf(recipe)
		local flights = 0
		for index, entry in ipairs(cost) do
			for copy = 1, 3 do
				flights += 1
				local chip = materialChip(overlay, entry.material)
				local from = Vector2.new(0.13 + (copy - 1) * 0.035, 0.24 + (index - 1) * 0.15)
				local to = Vector2.new(ANVIL.X + (math.random() - 0.5) * 0.08, ANVIL.Y - 0.03)
				local control = (from + to) / 2 + Vector2.new(0, -0.42)
				chip.Position = UDim2.fromScale(from.X, from.Y)
				local progress = Instance.new("NumberValue")
				progress.Changed:Connect(function(t)
					local point = from * (1 - t) ^ 2 + control * 2 * (1 - t) * t + to * t ^ 2
					chip.Position = UDim2.fromScale(point.X, point.Y)
					chip.Rotation = t * 360
				end)
				task.delay((flights - 1) * 0.05, function()
					if token ~= animToken then
						return
					end
					local tween = TweenService:Create(progress, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 })
					tween:Play()
					tween.Completed:Once(function()
						progress:Destroy()
						if chip.Parent then
							sparks(overlay, chip.Position, Config.Rarity[entry.material.Rarity].Color, 3)
							chip:Destroy()
							Style.PlaySound(Config.Sounds.Click, 1.4 + flights * 0.03, 0.25)
						end
					end)
				end)
			end
		end
		if not wait(0.55 + flights * 0.05) then
			return if token == animToken then reveal(recipe, token) else nil
		end

		-- 2. Three hammer strikes; the glow grows with each one.
		for strike = 1, Config.Forge.Strikes do
			Style.Tween(hammer, 0.16, { Rotation = 62 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if not wait(0.17) then
				return if token == animToken then reveal(recipe, token) else nil
			end
			Style.Tween(hammer, 0.07, { Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if not wait(0.08) then
				return if token == animToken then reveal(recipe, token) else nil
			end
			sparks(overlay, anvilPos + UDim2.fromOffset(0, -4), rarity.Color, 16)
			shakeWindow()
			Style.PlaySound(Config.Sounds.Hammer, 0.55 + strike * 0.08, 0.8)
			local size = 60 + strike * 90
			Style.Tween(glow, 0.2, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0.75 - strike * 0.12 })
			if not wait(0.16) then
				return if token == animToken then reveal(recipe, token) else nil
			end
		end
		if not wait(0.1) then
			return if token == animToken then reveal(recipe, token) else nil
		end

		-- 3. The result.
		reveal(recipe, token)
	end)
end

---------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------

local busy = false
craftButton.Activated:Connect(function()
	local recipe = selected
	if busy or not recipe then
		return
	end
	local state = stateOf(recipe)
	if state ~= "ok" then
		Popups.Toast(if state == "owned" then Texts.Owned elseif state == "aura" then Texts.NoAura else Texts.Missing, "bad")
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = craftRemote:InvokeServer(recipe.Id)
		busy = false
		if ok then
			playCraft(recipe)
			Popups.Toast("⚒ " .. (message or ""), "gold")
		else
			Popups.Toast(message or "", "bad")
		end
	end)
end)

local function refresh()
	refreshRows()
	refreshDetails()
end

tabs.Changed = function(kind)
	-- keep the selection inside the visible tab
	if not selected or selected.Kind ~= kind then
		for _, recipe in ipairs(Config.Recipes) do
			if recipe.Kind == kind and stateOf(recipe) ~= "owned" then
				showDetails(recipe)
				return
			end
		end
		for _, recipe in ipairs(Config.Recipes) do
			if recipe.Kind == kind then
				showDetails(recipe)
				return
			end
		end
	end
	refresh()
end
selectTab("Weapon")

PlayerData.Changed({ "Materials", "OwnedWeapon", "OwnedArmor", "EquippedWeapon", "EquippedHelmet", "EquippedChest", "EquippedLegs", "ClickPower" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
local lastAuraRefresh = 0
aura.Changed:Connect(function()
	-- Aura changes on every click: refresh at most 4 times a second
	if window.IsOpen() and os.clock() - lastAuraRefresh > 0.25 then
		lastAuraRefresh = os.clock()
		refresh()
	end
end)
window.OnOpen = function()
	closeOverlay()
	refresh()
end

Forge.Window = window
Forge.Open = window.Open
return Forge
