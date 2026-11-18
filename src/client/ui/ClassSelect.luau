--[[
	ClassSelect.luau
	"ВЫБОР КЛАССА" screen (owner mockup docs/design/ui_class_and_skilltree.png,
	top half): three big class cards with the class art (a ViewportFrame
	with the player's own character in the class armor set holding the
	class weapon, frozen in a fight pose: Config.Classes[i].Art), role
	tags, and a details panel on the right (description, key abilities,
	difficulty, "Выбрать класс"). Нано-кредиты and Кристаллы at the top.

	Opens by itself for every player without a class (old saves too) and
	cannot be closed until a class is picked (the first pick is free); the
	Academy terminal opens it again with a "Назад" button
	(ClassSelect.Open(true)). Changing the class asks first: a dialog with
	the class preview and the price in credits, Кристаллы or Robux
	(Config.ClassChange).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ArmorBuilder = require(ReplicatedStorage.Shared.ArmorBuilder)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local Icons = require(script.Parent.Icons)
local Popups = require(script.Parent.Popups)
local Style = require(script.Parent.Style)
local Window = require(script.Parent.Windows.Window)

local player = Players.LocalPlayer
local classRemote = ReplicatedStorage:WaitForChild("Class")
player:WaitForChild("leaderstats")

local C = Style.Colors
local Z = 60

local ClassSelect = {}

local screen = Instance.new("Frame")
screen.Name = "ClassSelect"
screen.Size = UDim2.fromScale(1, 1)
screen.BackgroundColor3 = Color3.fromRGB(6, 7, 9)
screen.BackgroundTransparency = 0.04
screen.ZIndex = Z
screen.Visible = false
screen.Active = true
screen.Parent = Style.Gui
local vignette = Instance.new("UIGradient")
vignette.Rotation = 90
vignette.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.02), NumberSequenceKeypoint.new(0.5, 0.12), NumberSequenceKeypoint.new(1, 0.02) })
vignette.Parent = screen

local W, H = 1180, 560
local body = Instance.new("Frame")
body.Name = "Body"
body.AnchorPoint = Vector2.new(0.5, 0.5)
body.Position = UDim2.fromScale(0.5, 0.5)
body.Size = UDim2.fromOffset(W, H)
body.BackgroundTransparency = 1
body.ZIndex = Z
body.Parent = screen
local fit = Instance.new("UISizeConstraint")
fit.MaxSize = Vector2.new(W, H)
fit.Parent = body

-- header
local title = Style.Label(body, "ВЫБОР КЛАССА", 34, C.Text, { Font = Style.FontTitle, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(500, 42), ZIndex = Z + 2 })
local _ = title
for _, side in ipairs({ -1, 1 }) do
	Style.Rule(body, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 330, 0, 22), Size = UDim2.fromOffset(150, 2), Color = C.Gold, ZIndex = Z + 1 })
end
Style.Label(body, "Выбери свой стиль игры. Класс можно сменить позже в Академии.", 15, C.Muted, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(700, 20), ZIndex = Z + 2 })

local back = Style.Button(body, { Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(120, 36), Text = "Назад", TextSize = 15, ZIndex = Z + 2, Icon = "back" })
back.Visible = false

local creditsPlate = Style.Panel(body, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(150, 36), ZIndex = Z + 1, Border = C.Line, Cut = 6 })
local creditsIcon = Icons.Make(creditsPlate, "credits", 20, C.Gold, Z + 2)
creditsIcon.AnchorPoint = Vector2.new(0, 0.5)
creditsIcon.Position = UDim2.new(0, 10, 0.5, 0)
local creditsLabel = Style.Label(creditsPlate, "0", 16, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -46, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 2 })
local crystalsPlate = Style.Panel(body, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -160, 0, 4), Size = UDim2.fromOffset(120, 36), ZIndex = Z + 1, Border = C.Line, Cut = 6 })
local crystalsIcon = Icons.Make(crystalsPlate, "crystal", 20, Config.Crystals.Color, Z + 2)
crystalsIcon.AnchorPoint = Vector2.new(0, 0.5)
crystalsIcon.Position = UDim2.new(0, 10, 0.5, 0)
local crystalsLabel = Style.Label(crystalsPlate, "0", 16, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -46, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 2 })
local function refreshCredits()
	creditsLabel.Text = Format.Number(player:GetAttribute("Credits") or 0)
	crystalsLabel.Text = Format.Number(player:GetAttribute("Crystals") or 0)
end
player:GetAttributeChangedSignal("Credits"):Connect(refreshCredits)
player:GetAttributeChangedSignal("Crystals"):Connect(refreshCredits)
refreshCredits()

---------------------------------------------------------------------
-- Class art: the player's character in a ViewportFrame
---------------------------------------------------------------------

local function characterModel(classId: string): Model?
	local character = player.Character
	if not character then
		return nil
	end
	character.Archivable = true
	local clone = character:Clone()
	if not clone then
		return nil
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	-- the player's own gear off, the class look on
	for _, child in ipairs(clone:GetChildren()) do
		if child.Name == "EquippedWeapon" or child.Name == "EnergyShield" or child.Name:match("^Armor_") then
			child:Destroy()
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local class = Config.ClassById[classId]
	local art = class.Art or {}
	for _, piece in ipairs(Config.Armor) do
		if piece.Set == art.Set then
			pcall(ArmorBuilder.Attach, clone, piece)
		end
	end
	-- the class weapon welded to the right hand (so it follows the pose)
	local weapon = Config.ItemById.Weapon[player:GetAttribute("EquippedWeapon") or ""] or Config.Weapons[1]
	local look = table.clone(weapon)
	look.Class = classId
	look.Rarity = "Epic"
	local ok, model = pcall(WeaponBuilder.Build, look)
	local r15 = clone:FindFirstChild("RightHand")
	local hand = r15 or clone:FindFirstChild("Right Arm")
	if ok and model and hand and model.PrimaryPart then
		WeaponBuilder.SetAnchored(model, false)
		local grip = if r15 then Config.Equipment.GripR15 else Config.Equipment.GripR6
		model:PivotTo(hand.CFrame * grip)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Massless = true
				p.CanCollide = false
			end
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = model.PrimaryPart
		weld.Parent = model.PrimaryPart
		model.Parent = clone
	end
	if classId == "Blade" then
		local arm = clone:FindFirstChild("LeftLowerArm") or clone:FindFirstChild("Left Arm")
		if arm then
			local S = Config.Equipment.Shield
			local plate = Instance.new("Part")
			plate.Shape = Enum.PartType.Cylinder
			plate.Size = Vector3.new(0.12, S.Size, S.Size)
			plate.Color = S.Color
			plate.Material = Enum.Material.Neon
			plate.Transparency = 0.55
			plate.Massless = true
			plate.CanCollide = false
			plate.CFrame = arm.CFrame * S.Offset
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = arm
			weld.Part1 = plate
			weld.Parent = plate
			plate.Parent = clone
		end
	end
	-- only the root is anchored: the joints can take the pose
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
		end
	end
	return clone
end

-- Freezes the model in the class's fight pose (Config.Classes[i].Art).
local function pose(model: Model, classId: string)
	local art = Config.ClassById[classId].Art
	local clip = art and Config.Animations.Clips[art.Clip]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not clip or (clip.Id or "") == "" or not animator or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = clip.Id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action4
		track:Play(0)
		track.TimePosition = art.At or clip.Hit or 0
		track:AdjustSpeed(0)
	end
end

local function setArt(viewport: ViewportFrame, classId: string)
	viewport:ClearAllChildren()
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model = characterModel(classId)
	if not model then
		local icon = Icons.Make(viewport, Config.ClassById[classId].Icon, 110, Config.ClassById[classId].Color, viewport.ZIndex + 1)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.45)
		return
	end
	model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180 + 20), 0))
	model.Parent = world
	pose(model, classId)
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	local distance = size.Y * 1.55
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, size.Y * 0.08, distance), cf.Position + Vector3.new(0, size.Y * 0.05, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	-- a gentle turn
	task.spawn(function()
		local start = os.clock()
		while model.Parent and screen.Visible do
			local a = math.sin((os.clock() - start) * 0.6) * math.rad(14)
			model:PivotTo(CFrame.Angles(0, math.rad(200) + a, 0))
			RunService.RenderStepped:Wait()
		end
	end)
end

---------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------

local CARD_W, CARD_H = 272, 420
local cards = {}
local selected = nil
local canClose = false

local details = Style.Panel(body, {
	Name = "Details",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 84),
	Size = UDim2.fromOffset(W - 3 * CARD_W - 3 * 18, CARD_H),
	ZIndex = Z + 1,
	Fill = C.Panel,
	Transparency = 0.06,
	Border = C.GoldDim,
	Cut = 12,
})

local dIconFrame = Style.Panel(details, { Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(52, 52), ZIndex = Z + 2, Fill = C.CardDark, Transparency = 0, Border = C.GoldDim, Cut = 8 })
local dIcon = Icons.Make(dIconFrame, "sword", 32, C.Gold, Z + 3)
dIcon.AnchorPoint = Vector2.new(0.5, 0.5)
dIcon.Position = UDim2.fromScale(0.5, 0.5)
local dName = Style.Label(details, "", 24, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(82, 18), Size = UDim2.new(1, -96, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 2 })
local dSub = Style.Label(details, "Базовый класс", 13, C.Muted, { Position = UDim2.fromOffset(82, 48), Size = UDim2.new(1, -96, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 2 })
local dText = Style.Label(details, "", 14, C.Text, { Position = UDim2.fromOffset(18, 84), Size = UDim2.new(1, -36, 0, 92), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = Z + 2 })
Style.Label(details, "Ключевые умения", 16, C.Gold, { Position = UDim2.fromOffset(18, 184), Size = UDim2.new(1, -36, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 2 })
local keyRow = Instance.new("Frame")
keyRow.Position = UDim2.fromOffset(18, 212)
keyRow.Size = UDim2.new(1, -36, 0, 64)
keyRow.BackgroundTransparency = 1
keyRow.ZIndex = Z + 2
keyRow.Parent = details
local keyLayout = Instance.new("UIListLayout")
keyLayout.FillDirection = Enum.FillDirection.Horizontal
keyLayout.Padding = UDim.new(0, 12)
keyLayout.Parent = keyRow
local keyCells = {}
for i = 1, 3 do
	local cell = Style.Panel(keyRow, { Size = UDim2.fromOffset(56, 56), LayoutOrder = i, ZIndex = Z + 2, Fill = C.CardDark, Transparency = 0, Border = C.GoldDim, Cut = 8 })
	local icon = Icons.Make(cell, "lock", 32, C.Text, Z + 3)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	local name = Style.Label(cell, "", 10, C.Muted, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(84, 24), TextWrapped = true, ZIndex = Z + 3 })
	keyCells[i] = { icon = icon, name = name }
end
Style.Label(details, "Сложность", 15, C.Text, { Position = UDim2.fromOffset(18, 306), Size = UDim2.fromOffset(110, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 2 })
local diffBars = {}
for i = 1, 5 do
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(130 + (i - 1) * 30, 312)
	bar.Size = UDim2.fromOffset(26, 8)
	bar.BorderSizePixel = 0
	bar.ZIndex = Z + 2
	bar.Parent = details
	diffBars[i] = bar
end
local chooseButton = Style.Button(details, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -36, 0, 52), Color = C.Gold, Text = "Выбрать класс", TextSize = 20, ZIndex = Z + 3 })

local CC = Config.ClassChange
local freeLine = Style.Label(details, CC.Texts.Free, 13, C.Green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -76), Size = UDim2.new(1, -36, 0, 16), ZIndex = Z + 3 })

local function showDetails(class)
	selected = class
	Icons.Set(dIcon, class.Icon, class.Color)
	dName.Text = class.Name
	dText.Text = class.Text
	local current = player:GetAttribute("Class") == class.Id
	dSub.Text = if current then "Твой текущий класс" else "Базовый класс"
	for i, cell in ipairs(keyCells) do
		local node = Config.SkillById[class.Key[i] or ""]
		Icons.Set(cell.icon, if node then node.Icon else "lock", class.Color)
		cell.name.Text = if node then node.Name else ""
	end
	for i, bar in ipairs(diffBars) do
		bar.BackgroundColor3 = if i <= class.Difficulty then C.Text else C.Line
	end
	local hasClass = (player:GetAttribute("Class") or "") ~= ""
	chooseButton.Text = if current then "Текущий класс" elseif hasClass then "Сменить класс" else "Выбрать класс"
	freeLine.Visible = not hasClass
	for id, card in pairs(cards) do
		local on = id == class.Id
		card.shape.SetBorder(if on then card.class.Color else C.Line)
		card.glow.Visible = on
	end
end

for order, class in ipairs(Config.Classes) do
	local x = (order - 1) * (CARD_W + 18)
	local frame = Instance.new("TextButton")
	frame.Name = class.Id
	frame.Position = UDim2.fromOffset(x, 84)
	frame.Size = UDim2.fromOffset(CARD_W, CARD_H)
	frame.BackgroundTransparency = 1
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.ZIndex = Z + 1
	frame.Parent = body
	local shape = Style.Chamfer(frame, { Fill = Color3.fromRGB(14, 16, 22), Transparency = 0.02, Border = C.Line, Cut = 14, Thickness = 2 })
	-- color glow of the selected card
	local glow = Instance.new("Frame")
	glow.Position = UDim2.fromOffset(4, 4)
	glow.Size = UDim2.new(1, -8, 1, -8)
	glow.BackgroundColor3 = class.Color
	glow.BackgroundTransparency = 0.82
	glow.BorderSizePixel = 0
	glow.ZIndex = Z + 1
	glow.Visible = false
	glow.Parent = frame
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	g.Parent = glow
	local viewport = Instance.new("ViewportFrame")
	viewport.Position = UDim2.fromOffset(6, 6)
	viewport.Size = UDim2.new(1, -12, 0, 250)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 150, 160)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = Z + 2
	viewport.Parent = frame
	local iconFrame = Style.Panel(frame, { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(42, 42), ZIndex = Z + 3, Fill = C.CardDark, Transparency = 0.2, Border = class.Color, Cut = 6 })
	local icon = Icons.Make(iconFrame, class.Icon, 26, class.Color, Z + 4)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	Style.Label(frame, class.Name, 30, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(18, 262), Size = UDim2.new(1, -36, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 3 })
	Style.Label(frame, class.Short, 14, C.Muted, { Position = UDim2.fromOffset(18, 298), Size = UDim2.new(1, -36, 0, 54), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = Z + 3 })
	local tags = Instance.new("Frame")
	tags.Position = UDim2.fromOffset(12, CARD_H - 50)
	tags.Size = UDim2.new(1, -24, 0, 34)
	tags.BackgroundTransparency = 1
	tags.ZIndex = Z + 3
	tags.Parent = frame
	local tagLayout = Instance.new("UIListLayout")
	tagLayout.FillDirection = Enum.FillDirection.Horizontal
	tagLayout.Padding = UDim.new(0, 6)
	tagLayout.Parent = tags
	for i, tag in ipairs(class.Tags) do
		local chip = Style.Panel(tags, { Size = UDim2.fromOffset(78, 32), LayoutOrder = i, ZIndex = Z + 3, Fill = C.Card, Transparency = 0.1, Border = C.Line, Cut = 5 })
		local ti = Icons.Make(chip, tag.Icon, 14, class.Color, Z + 4)
		ti.AnchorPoint = Vector2.new(0, 0.5)
		ti.Position = UDim2.new(0, 6, 0.5, 0)
		local tl = Style.Label(chip, tag.Text, 11, C.Text, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -24, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = Z + 4 })
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 12
		cap.Parent = tl
	end
	cards[class.Id] = { frame = frame, shape = shape, glow = glow, viewport = viewport, class = class }
	frame.Activated:Connect(function()
		Style.PlaySound("Ui", 1, 0.4)
		showDetails(class)
	end)
end

---------------------------------------------------------------------
-- Class change dialog (preview + price in credits / Кристаллы / Robux)
---------------------------------------------------------------------


local dim = Instance.new("TextButton")
dim.Name = "ChangeDim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.35
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = Z + 10
dim.Visible = false
dim.Parent = screen
local dialog = Style.Panel(dim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 380), ZIndex = Z + 11, Fill = C.Panel, Transparency = 0.02, Border = C.Gold, Cut = 14 })
local dialogFit = Instance.new("UIScale")
dialogFit.Parent = dialog
Style.Label(dialog, CC.Texts.Title, 22, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 26), ZIndex = Z + 12 })
local preview = Instance.new("ViewportFrame")
preview.Position = UDim2.fromOffset(18, 52)
preview.Size = UDim2.fromOffset(220, 310)
preview.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
preview.BackgroundTransparency = 0.2
preview.Ambient = Color3.fromRGB(150, 150, 160)
preview.LightColor = Color3.fromRGB(255, 240, 220)
preview.LightDirection = Vector3.new(-0.4, -1, -0.6)
preview.ZIndex = Z + 12
preview.Parent = dialog
local askLine = Style.Label(dialog, "", 20, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(256, 58), Size = UDim2.new(1, -274, 0, 50), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 12 })
Style.Label(dialog, CC.Texts.Note, 13, C.Muted, { Position = UDim2.fromOffset(256, 112), Size = UDim2.new(1, -274, 0, 44), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = Z + 12 })
local payButtons = {}
local robuxColor = nil
for i, kind in ipairs({ "Credits", "Crystals", "Robux" }) do
	local button, setColor = Style.Button(dialog, {
		Position = UDim2.fromOffset(256, 166 + (i - 1) * 50),
		Size = UDim2.new(1, -274, 0, 42),
		Color = if kind == "Robux" then C.Green else C.Card,
		Icon = if kind == "Credits" then "credits" elseif kind == "Crystals" then "crystal" else "gem",
		Text = "",
		TextSize = 17,
		ZIndex = Z + 12,
	})
	payButtons[kind] = button
	if kind == "Robux" then
		robuxColor = setColor
	end
end
local cancel = Style.Button(dialog, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -14), Size = UDim2.fromOffset(150, 34), Color = C.CardDark, Text = CC.Texts.Cancel, TextSize = 15, ZIndex = Z + 12 })

local changing = nil
local function closeChange()
	dim.Visible = false
	changing = nil
end
cancel.Activated:Connect(closeChange)

local function openChange(class)
	changing = class
	askLine.Text = CC.Texts.Ask:format(class.Name)
	local level = player:GetAttribute("Level") or 1
	payButtons.Credits.Text = CC.Texts.Credits:format(Format.Number(CC.Credits(level)))
	payButtons.Crystals.Text = CC.Texts.Crystals:format(CC.Crystals)
	local product = Config.ProductByKey[CC.Product]
	local onSale = product ~= nil and product.Id > 0
	payButtons.Robux.Text = if onSale then CC.Texts.Robux:format(product.Price) else CC.Texts.Robux:format(product and product.Price or 0) .. "  ·  " .. CC.Texts.Soon
	if robuxColor then
		robuxColor(if onSale then C.Green else C.CardDark)
	end
	setArt(preview, class.Id)
	local camera = Workspace.CurrentCamera
	dialogFit.Scale = math.min(1, (camera.ViewportSize.X - 24) / 640, (camera.ViewportSize.Y - 24) / 380)
	dim.Visible = true
end

local busy = false
for kind, button in pairs(payButtons) do
	button.Activated:Connect(function()
		if busy or not changing then
			return
		end
		busy = true
		local class = changing
		local ok, message, state = classRemote:InvokeServer("Choose", class.Id, kind)
		busy = false
		if ok and state == "Pending" then
			Popups.Toast(message or "", "gold")
			closeChange()
		elseif ok then
			closeChange()
			Popups.Toast(message or "", "gold")
			Popups.Flash(class.Color)
			Style.PlaySound("Forged", 1.1, 0.6)
			ClassSelect.Close()
		else
			Popups.Toast(message or "", "bad")
		end
	end)
end

chooseButton.Activated:Connect(function()
	if busy or not selected then
		return
	end
	local current = player:GetAttribute("Class") or ""
	if current == selected.Id then
		if canClose then
			ClassSelect.Close()
		end
		return
	end
	if current ~= "" then
		openChange(selected)
		return
	end
	busy = true
	local ok, message = classRemote:InvokeServer("Choose", selected.Id)
	busy = false
	if ok then
		Popups.Toast(message or "", "gold")
		Popups.Flash(selected.Color)
		Style.PlaySound("Forged", 1.1, 0.6)
		ClassSelect.Close()
	else
		Popups.Toast(message or "", "bad")
	end
end)

function ClassSelect.Open(withBack: boolean?)
	Window.CloseAll()
	canClose = withBack == true and (player:GetAttribute("Class") or "") ~= ""
	back.Visible = canClose
	screen.Visible = true
	for id, card in pairs(cards) do
		setArt(card.viewport, id)
	end
	showDetails(Config.ClassById[player:GetAttribute("Class") or ""] or Config.Classes[1])
end

function ClassSelect.Close()
	screen.Visible = false
	closeChange()
end

function ClassSelect.IsOpen(): boolean
	return screen.Visible
end

back.Activated:Connect(function()
	if canClose then
		ClassSelect.Close()
	end
end)

-- Everyone without a class sees the screen (old saves too).
local function check()
	if (player:GetAttribute("Class") or "") == "" and not screen.Visible then
		task.defer(ClassSelect.Open, false)
	end
end
player:GetAttributeChangedSignal("Class"):Connect(check)
task.delay(1, check)
player.CharacterAdded:Connect(function()
	task.delay(1, function()
		if screen.Visible then
			for id, card in pairs(cards) do
				setArt(card.viewport, id)
			end
		end
	end)
end)

return ClassSelect
