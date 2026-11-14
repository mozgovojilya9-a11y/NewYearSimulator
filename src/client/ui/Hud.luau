--[[
	Hud.luau
	Objective text (top center), bottom left: credits and the level bar,
	bottom center: damage, player health (dungeon) and the record room
	bar; the level-up banner and the boost timer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.Popups)
local Style = require(script.Parent.Style)

local player = Players.LocalPlayer
player:WaitForChild("leaderstats") -- data loaded
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
counters.Size = UDim2.fromOffset(260, 130)
counters.BackgroundTransparency = 1
counters.Parent = Style.Gui
local countersLayout = Instance.new("UIListLayout")
countersLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
countersLayout.Padding = UDim.new(0, 6)
countersLayout.SortOrder = Enum.SortOrder.LayoutOrder
countersLayout.Parent = counters

local function counter(order, icon, color, parent: Instance?, size: UDim2?)
	local plate = Style.Plate(parent or counters, { Size = size or UDim2.new(1, 0, 0, 44) })
	plate.LayoutOrder = order
	Style.Label(plate, icon, 24, Style.Colors.Text, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 36, 1, 0), ZIndex = 2 }):FindFirstChildOfClass("UIStroke").Transparency = 1
	local value = Style.Label(plate, "0", 24, color, { Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -50, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 2 })
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 24
	cap.Parent = value
	local scale = Instance.new("UIScale")
	scale.Parent = value
	return value, scale
end

local creditsValue = counter(1, Config.Credits.Icon, Style.Colors.Cyan)

local function refreshCounters()
	creditsValue.Text = Format.Number(player:GetAttribute("Credits") or 0)
end
player:GetAttributeChangedSignal("Credits"):Connect(refreshCounters)
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
end
player:GetAttributeChangedSignal("ClickPower"):Connect(refreshDamage)
refreshDamage()

local function bar(order, color, width)
	local track = Instance.new("Frame")
	track.LayoutOrder = order
	track.Size = UDim2.fromOffset(width, 24)
	track.BackgroundColor3 = Style.Colors.PanelDark
	track.BackgroundTransparency = 0
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
local progressTrack, progressFill, progressText = bar(3, Style.Colors.Orange, 420)
progressTrack.Size = UDim2.fromOffset(420, 26)
progressText.TextScaled = true -- long goal names shrink instead of overflowing
progressText.Size = UDim2.new(1, -20, 1, -4)
progressText.Position = UDim2.fromOffset(10, 2)
local progressCap = Instance.new("UITextSizeConstraint")
progressCap.MaxTextSize = 16
progressCap.Parent = progressText

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

-- Bottom bar: the record room of the dungeon.
local function refreshProgress()
	local reached = player:GetAttribute("RoomReached") or 0
	progressFill.Size = UDim2.fromScale(math.clamp(reached / Config.Dungeon.Rooms, 0, 1), 1)
	progressText.Text = if reached >= Config.Dungeon.Rooms then "Данж пройден!" else ("Рекорд: этап %d/%d"):format(reached, Config.Dungeon.Rooms)
end
player:GetAttributeChangedSignal("RoomReached"):Connect(refreshProgress)
refreshProgress()

---------------------------------------------------------------------
-- Level bar (bottom left, above the counters) and boost timer
---------------------------------------------------------------------

local levelTrack = Instance.new("Frame")
levelTrack.Name = "Level"
levelTrack.LayoutOrder = -1
levelTrack.Size = UDim2.new(1, 0, 0, 28)
levelTrack.BackgroundColor3 = Style.Colors.PanelDark
levelTrack.BackgroundTransparency = 0
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
local levelText = Style.Label(levelTrack, "", 16, Style.Colors.Text, { Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 1, -4), TextScaled = true, ZIndex = 4 })
local levelTextCap = Instance.new("UITextSizeConstraint")
levelTextCap.MaxTextSize = 16
levelTextCap.Parent = levelText

local function refreshLevel()
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("Xp") or 0
	local xpNext = math.max(1, player:GetAttribute("XpNext") or 100)
	Style.Tween(levelFill, 0.3, { Size = UDim2.fromScale(math.clamp(xp / xpNext, 0, 1), 1) })
	local points = player:GetAttribute("SkillPoints") or 0
	local gearScore = player:GetAttribute("Stat_GearScore") or 0
	levelText.Text = ("Ур. %d  •  GS %d  •  %s/%s XP"):format(level, gearScore, Format.Number(xp), Format.Number(xpNext)) .. (if points > 0 then ("  ⭐%d"):format(points) else "")
end
for _, attribute in ipairs({ "Level", "Xp", "XpNext", "SkillPoints", "Stat_GearScore" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshLevel)
end
refreshLevel()

-- Level up: big banner, flash, sound.
local levelUpRemote = ReplicatedStorage:WaitForChild("LevelUp")
local LT = Config.Progression.Level.Texts
levelUpRemote.OnClientEvent:Connect(function(level, points)
	level = tonumber(level) or 1
	task.wait(0.1) -- let the new MaxHealth attribute arrive
	local lines = {
		LT.Points:format(tonumber(points) or 1),
		LT.Growth:format(Format.Number(player:GetAttribute("ClickPower") or 1), Format.Number(player:GetAttribute("MaxHealth") or Config.Player.Health)),
	}
	Popups.Banner(LT.Title, ("Ур. %d"):format(level), lines, Style.Colors.Gold)
	Popups.Flash(Style.Colors.Gold)
	Style.PlaySound(Config.Sounds.Forged, 1.2, 0.7)
end)

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
		local parts = {}
		for _, kind in ipairs(Config.BoostKinds) do
			local left = (player:GetAttribute("Boost" .. kind) or 0) - os.time()
			if left > 0 then
				table.insert(parts, ("x2 %s %d:%02d"):format(Config.BoostNames[kind], left // 60, left % 60))
			end
		end
		boostLabel.Text = "⚡ " .. table.concat(parts, "   ")
		boostLabel.Visible = #parts > 0
		task.wait(1)
	end
end)

return Hud
