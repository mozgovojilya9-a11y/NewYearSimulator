--[[
	Hud.luau
	Objective text (top center), counters (bottom left: Aura, rebirths,
	pets) and the bottom-center stack: damage, player health (dungeon),
	room progress bar and the 4 quick damage-upgrade buttons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.Popups)
local Shop = require(script.Parent.Windows.Shop)
local Style = require(script.Parent.Style)

local player = Players.LocalPlayer
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")
local roomState = ReplicatedStorage:WaitForChild("RoomState")

local Hud = {}

---------------------------------------------------------------------
-- Objective (top center)
---------------------------------------------------------------------

local objective = Style.Label(Style.Gui, "", 30, Style.Colors.Text, {
	Name = "Objective",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, Config.Hud.TopLeftReserved.Y + 4), -- below the Roblox buttons' row
	Size = UDim2.fromOffset(600, 40),
	ZIndex = 5,
})
local objectiveScale = Instance.new("UIScale")
objectiveScale.Parent = objective

-- Second line: recommended damage for the room you are in.
local hintLabel = Style.Label(Style.Gui, "", 20, Style.Colors.Text, {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, Config.Hud.TopLeftReserved.Y + 46),
	Size = UDim2.fromOffset(600, 26),
	ZIndex = 5,
})
hintLabel.Visible = false

local hintRoom = nil
local function refreshHint()
	if not hintRoom then
		hintLabel.Visible = false
		return
	end
	local recommended = Config.RecommendedDamage(hintRoom)
	local mine = player:GetAttribute("ClickPower") or 1
	hintLabel.Text = Config.DungeonLayout.Texts.Recommended:format(Format.Number(recommended)) .. ("  (у тебя %s)"):format(Format.Number(mine))
	hintLabel.TextColor3 = if mine >= recommended then Style.Colors.Green else Style.Colors.Red
	hintLabel.Visible = true
end
player:GetAttributeChangedSignal("ClickPower"):Connect(refreshHint)

local currentRoomAlive = nil -- alive count in the room the player is in (nil = unknown)
local function setObjective(text)
	if objective.Text ~= text then
		objective.Text = text
		objectiveScale.Scale = 1.2
		Style.Tween(objectiveScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function refreshObjective()
	local zone = player:GetAttribute("Zone")
	local reached = player:GetAttribute("RoomReached") or 0
	if zone ~= "Dungeon" then
		setObjective(if reached >= Config.Dungeon.Rooms then Config.Hud.Objectives.Done else Config.Hud.Objectives.Hub)
	elseif currentRoomAlive == 0 then
		setObjective(Config.Hud.Objectives.Cleared)
	else
		setObjective(Config.Hud.Objectives.Fight)
	end
end

-- Hud.SetCurrentRoom is called by Zone.luau with the room the player stands in.
local currentRoom = nil
local roomAlive = {} -- [room] = alive
function Hud.SetCurrentRoom(room: number?)
	currentRoom = room
	currentRoomAlive = if room then roomAlive[room] else nil
	hintRoom = room
	refreshHint()
	refreshObjective()
end
roomState.OnClientEvent:Connect(function(room, alive)
	roomAlive[room] = alive
	if room == currentRoom then
		currentRoomAlive = alive
		refreshObjective()
	end
end)
player:GetAttributeChangedSignal("Zone"):Connect(refreshObjective)
player:GetAttributeChangedSignal("RoomReached"):Connect(refreshObjective)
refreshObjective()

---------------------------------------------------------------------
-- Counters (bottom left)
---------------------------------------------------------------------

local counters = Instance.new("Frame")
counters.Name = "Counters"
counters.AnchorPoint = Vector2.new(0, 1)
counters.Position = UDim2.new(0, 16, 1, -16)
counters.Size = UDim2.fromOffset(230, 210)
counters.BackgroundTransparency = 1
counters.Parent = Style.Gui
local countersLayout = Instance.new("UIListLayout")
countersLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
countersLayout.Padding = UDim.new(0, 6)
countersLayout.SortOrder = Enum.SortOrder.LayoutOrder
countersLayout.Parent = counters

local function counter(order, icon, color)
	local plate = Style.Plate(counters, { Size = UDim2.new(1, 0, 0, 44), Transparency = 0.2 })
	plate.LayoutOrder = order
	Style.Label(plate, icon, 26, Style.Colors.Text, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 44), ZIndex = 2 }):FindFirstChildOfClass("UIStroke").Transparency = 1
	local value = Style.Label(plate, "0", 24, color, { Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -60, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2 })
	local scale = Instance.new("UIScale")
	scale.Parent = value
	return value, scale
end

local auraValue, auraScale = counter(1, "✨", Style.Colors.Gold)
local rebirthValue = counter(2, "🔁", Style.Colors.Purple)
local petValue = counter(3, "🐾", Style.Colors.Magenta)

-- Auto-click toggle (works only while standing on a trainer platform).
local autoClickRemote = ReplicatedStorage:WaitForChild("AutoClick")
local autoButton, setAutoColor = Style.Button(counters, { Size = UDim2.new(1, 0, 0, 44), Color = Style.Colors.Red, Text = "⚡ Авто-клик: ВЫКЛ", TextSize = 18, LayoutOrder = 0, Shadow = false })
local autoOn = false
local function renderAuto()
	autoButton.Text = "⚡ Авто-клик: " .. (if autoOn then "ВКЛ" else "ВЫКЛ")
	setAutoColor(if autoOn then Style.Colors.Green else Style.Colors.Red)
end
autoButton.Activated:Connect(function()
	autoOn = not autoOn
	autoClickRemote:FireServer(autoOn)
	renderAuto()
	if autoOn then
		Popups.Toast("Авто-клик работает на платформе тренажёра", "gold")
	end
end)
renderAuto()

local displayed = Instance.new("NumberValue")
displayed.Value = aura.Value
displayed.Changed:Connect(function(v)
	auraValue.Text = Format.Number(v)
end)
auraValue.Text = Format.Number(aura.Value)
local counterTween
aura.Changed:Connect(function(newValue)
	if counterTween then
		counterTween:Cancel()
	end
	if newValue < displayed.Value then
		displayed.Value = newValue
		return
	end
	counterTween = Style.Tween(displayed, 0.25, { Value = newValue })
	auraScale.Scale = 1.15
	Style.Tween(auraScale, 0.2, { Scale = 1 })
end)

local function refreshCounters()
	rebirthValue.Text = tostring(player:GetAttribute("Rebirths") or 0)
	local owned = 0
	for _ in pairs(Shop.OwnedSet("Pet")) do
		owned += 1
	end
	petValue.Text = ("%d/%d"):format(owned, #Config.Pets)
end
player:GetAttributeChangedSignal("Rebirths"):Connect(refreshCounters)
player:GetAttributeChangedSignal("OwnedPet"):Connect(refreshCounters)
refreshCounters()

---------------------------------------------------------------------
-- Bottom center: damage, health, progress, quick upgrades
---------------------------------------------------------------------

local stack = Instance.new("Frame")
stack.Name = "BottomCenter"
stack.AnchorPoint = Vector2.new(0.5, 1)
stack.Position = UDim2.new(0.5, 0, 1, -12)
stack.Size = UDim2.fromOffset(440, 190)
stack.BackgroundTransparency = 1
stack.Parent = Style.Gui
local stackLayout = Instance.new("UIListLayout")
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
stackLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
stackLayout.Padding = UDim.new(0, 6)
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Parent = stack

local damageLabel = Style.Label(stack, "", 32, Style.Colors.Gold, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 38), ZIndex = 3 })
local function refreshDamage()
	damageLabel.Text = Format.Number(player:GetAttribute("ClickPower") or 1) .. " Урон"
	local mult = player:GetAttribute("AuraMultiplier") or 1
	if mult ~= 1 then
		damageLabel.Text ..= ("  •  Аура x%s"):format(tostring(math.floor(mult * 100 + 0.5) / 100))
	end
end
player:GetAttributeChangedSignal("ClickPower"):Connect(refreshDamage)
player:GetAttributeChangedSignal("AuraMultiplier"):Connect(refreshDamage)
refreshDamage()

local function bar(order, color, width)
	local track = Instance.new("Frame")
	track.LayoutOrder = order
	track.Size = UDim2.fromOffset(width, 24)
	track.BackgroundColor3 = Style.Colors.PanelDark
	track.BackgroundTransparency = 0.2
	track.ZIndex = 2
	track.Parent = stack
	Style.Corner(track, UDim.new(0.5, 0))
	Style.Stroke(track, 2.5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.ZIndex = 3
	fill.Parent = track
	Style.Corner(fill, UDim.new(0.5, 0))
	Style.Gradient(fill, color)
	local text = Style.Label(track, "", 16, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	return track, fill, text
end

local healthTrack, healthFill, healthText = bar(2, Style.Colors.Red, 320)
local progressTrack, progressFill, progressText = bar(3, Style.Colors.Orange, 380)

local function refreshHealth()
	local inDungeon = player:GetAttribute("Zone") == "Dungeon"
	healthTrack.Visible = inDungeon
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		healthFill.Size = UDim2.fromScale(ratio, 1)
		healthText.Text = ("%d/%d"):format(math.floor(humanoid.Health + 0.5), humanoid.MaxHealth)
	end
end
player:GetAttributeChangedSignal("Zone"):Connect(refreshHealth)
player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.HealthChanged:Connect(refreshHealth)
	refreshHealth()
end)
if player.Character then
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthChanged:Connect(refreshHealth)
	end
end
refreshHealth()

local function refreshProgress()
	local reached = player:GetAttribute("RoomReached") or 0
	progressFill.Size = UDim2.fromScale(math.clamp(reached / Config.Dungeon.Rooms, 0, 1), 1)
	if reached >= Config.Dungeon.Rooms then
		progressText.Text = "Перерождение доступно!"
	else
		progressText.Text = ("Этап %d/%d"):format(reached, Config.Dungeon.Rooms)
	end
end
player:GetAttributeChangedSignal("RoomReached"):Connect(refreshProgress)
refreshProgress()

-- Quick damage upgrades: the next 4 weapons STRONGER than the equipped
-- one ("+gain / price"). Owned stronger weapons show "Надеть"; unique
-- ones point to the hub stand; no upgrades left -> "Макс".
local row = Instance.new("Frame")
row.LayoutOrder = 4
row.Size = UDim2.fromOffset(440, 64)
row.BackgroundTransparency = 1
row.Parent = stack
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.Padding = UDim.new(0, 8)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = row

local quickSlots = {}
for order = 1, 4 do
	local color = Config.Hud.QuickUpgradeColors[order] or Style.Colors.Green
	local button, setColor = Style.Button(row, { Size = UDim2.fromOffset(100, 60), Color = color, TextSize = 1, LayoutOrder = order, Shadow = false })
	local top = Style.Label(button, "", 20, Style.Colors.Text, { Size = UDim2.new(1, 0, 0.55, 0), ZIndex = 3 })
	local bottom = Style.Label(button, "", 14, Style.Colors.Text, { Position = UDim2.fromScale(0, 0.52), Size = UDim2.new(1, 0, 0.4, 0), ZIndex = 3 })
	local slot = { button = button, setColor = setColor, top = top, bottom = bottom, color = color, state = "none", weaponId = nil }
	button.Activated:Connect(function()
		if slot.state == "buy" then
			Shop.Request("Buy", "Weapon", slot.weaponId)
		elseif slot.state == "equip" then
			Shop.Request("Equip", "Weapon", slot.weaponId)
		elseif slot.state == "stand" then
			Popups.Toast("Это оружие продаётся на стенде в хабе", "gold")
		end
	end)
	quickSlots[order] = slot
end

local function refreshQuick()
	local owned = Shop.OwnedSet("Weapon")
	local current = player:GetAttribute("ClickPower") or 1
	local currentWeapon = Config.ItemById.Weapon[player:GetAttribute("EquippedWeapon") or ""]
	local currentDamage = if currentWeapon then currentWeapon.Damage else 1
	-- Candidates: stronger than what is equipped, cheapest first (Config order).
	local upgrades = {}
	for _, weapon in ipairs(Config.Weapons) do
		if weapon.Damage > currentDamage then
			table.insert(upgrades, weapon)
		end
	end
	for order, slot in ipairs(quickSlots) do
		local weapon = upgrades[order]
		if not weapon then
			slot.state = "none"
			slot.weaponId = nil
			slot.top.Text = "Макс"
			slot.bottom.Text = if order == 1 then "Лучшее оружие!" else ""
			slot.setColor(Color3.fromRGB(110, 110, 130))
			continue
		end
		slot.weaponId = weapon.Id
		local delta = (weapon.Damage - currentDamage) * Config.Click.BaseDamage * (current / math.max(1, currentDamage * Config.Click.BaseDamage))
		slot.top.Text = "+" .. Format.Number(math.floor(delta + 0.5))
		if owned[weapon.Id] then
			slot.state = "equip"
			slot.bottom.Text = "Надеть"
			slot.setColor(Style.Colors.Blue)
		elseif weapon.Unique then
			slot.state = "stand"
			slot.bottom.Text = "Стенд в хабе"
			slot.setColor(Style.Colors.Gold)
		else
			slot.state = "buy"
			slot.bottom.Text = Format.Number(weapon.Cost) .. " ✨"
			slot.setColor(if aura.Value >= weapon.Cost then slot.color else Style.Darker(slot.color, 0.5))
		end
	end
end
aura.Changed:Connect(refreshQuick)
player:GetAttributeChangedSignal("OwnedWeapon"):Connect(refreshQuick)
player:GetAttributeChangedSignal("EquippedWeapon"):Connect(refreshQuick)
player:GetAttributeChangedSignal("ClickPower"):Connect(refreshQuick)
refreshQuick()

---------------------------------------------------------------------
-- Level bar (bottom left, above the counters) and boost timer
---------------------------------------------------------------------

local levelTrack = Instance.new("Frame")
levelTrack.Name = "Level"
levelTrack.LayoutOrder = -1
levelTrack.Size = UDim2.new(1, 0, 0, 26)
levelTrack.BackgroundColor3 = Style.Colors.PanelDark
levelTrack.BackgroundTransparency = 0.2
levelTrack.ZIndex = 2
levelTrack.Parent = counters
Style.Corner(levelTrack, UDim.new(0.5, 0))
Style.Stroke(levelTrack, 2.5)
local levelFill = Instance.new("Frame")
levelFill.Size = UDim2.fromScale(0, 1)
levelFill.BackgroundColor3 = Style.Colors.Cyan
levelFill.ZIndex = 3
levelFill.Parent = levelTrack
Style.Corner(levelFill, UDim.new(0.5, 0))
Style.Gradient(levelFill, Style.Colors.Cyan)
local levelText = Style.Label(levelTrack, "", 15, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 4 })

local function refreshLevel()
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("Xp") or 0
	local xpNext = math.max(1, player:GetAttribute("XpNext") or 100)
	Style.Tween(levelFill, 0.3, { Size = UDim2.fromScale(math.clamp(xp / xpNext, 0, 1), 1) })
	levelText.Text = ("Ур. %d   %s / %s XP"):format(level, Format.Number(xp), Format.Number(xpNext))
end
for _, attribute in ipairs({ "Level", "Xp", "XpNext" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshLevel)
end
refreshLevel()

local boostLabel = Style.Label(Style.Gui, "", 20, Style.Colors.Gold, {
	Name = "Boost",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, Config.Hud.TopLeftReserved.Y + 74),
	Size = UDim2.fromOffset(400, 26),
	ZIndex = 5,
})
boostLabel.Visible = false
task.spawn(function()
	while true do
		local until_ = player:GetAttribute("BoostUntil") or 0
		local left = until_ - os.time()
		if left > 0 then
			boostLabel.Text = ("⚡ x%s Аура  %d:%02d"):format(tostring(Config.Progression.Boost.Multiplier), left // 60, left % 60)
			boostLabel.Visible = true
		else
			boostLabel.Visible = false
		end
		task.wait(1)
	end
end)

return Hud
