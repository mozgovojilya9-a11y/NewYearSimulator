--[[
	Hud.luau
	The whole screen layer in the reference style (Config.Ui):

	  top left     profile (avatar, name, class with icon, rank, level badge,
	               XP bar) under the Roblox buttons; the icon bar under it
	               (Inventory [G], Skills [K], Quests [J], Shop) with red
	               count badges; the current quest tracker below
	  top center   objective + the dungeon damage hint, boost timers
	  top right    settings and sound
	  bottom       HP bar and the ability slots Q / E / R / dash (center),
	               credits (left), the big gold "ИГРАТЬ" button (right; in
	               the dungeon it becomes "В ХАБ [B]")
	Level-up banner. No tiles, no emoji.

	Data comes from Player attributes: Level, Xp, XpNext, SkillPoints,
	Class, Credits, Zone, RewardReady, Tracker (JSON: Title, Text,
	Progress, Target), Loadout (JSON: slot -> { Id, Icon, Name }),
	Ready_<slot> (server time when the slot is ready again) and
	CooldownMax_<slot>.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Icons = require(script.Parent.Icons)
local Popups = require(script.Parent.Popups)
local Style = require(script.Parent.Style)
local Window = require(script.Parent.Windows.Window)
local Gates = require(script.Parent.Windows.Gates)
local Artifacts = require(script.Parent.Windows.Artifacts)
local Inventory = require(script.Parent.Windows.Inventory)
local Status = require(script.Parent.Windows.Status)
local SystemNotice = require(script.Parent.SystemNotice)
local Reward = require(script.Parent.Windows.Reward)
local Settings = require(script.Parent.Windows.Settings)
local Skills = require(script.Parent.Windows.Skills)
local Store = require(script.Parent.Windows.Store)
local Teleport = require(script.Parent.Windows.Teleport)

local player = Players.LocalPlayer
player:WaitForChild("leaderstats") -- data loaded
local roomState = ReplicatedStorage:WaitForChild("RoomState")

local C = Style.Colors
local U = Config.Ui
local T = U.Texts
local TOP = Config.Hud.TopLeftReserved.Y + 4 -- below the Roblox buttons
local LEFT = 14

local Hud = {}
Hud.OnAbility = nil -- (slot) set by the combat module: a tap on an ability slot

-- Inventory [G] and Status [C] share header tabs with the artifacts.
local Stats = require(script.Parent.Windows.Stats)
Window.Group({ { Window = Inventory.Window, Text = "Инвентарь" }, { Window = Artifacts.Window, Text = "Артефакты" }, { Window = Status.Window, Text = "Статус" }, { Window = Stats.Window, Text = "Статистика" } })

local function decode(attribute: string)
	local raw = player:GetAttribute(attribute)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok then value else nil
end

---------------------------------------------------------------------
-- Profile (top left)
---------------------------------------------------------------------

local P = U.Profile
local profile = Style.Panel(Style.Gui, {
	Name = "Profile",
	Position = UDim2.fromOffset(LEFT, TOP),
	Size = UDim2.fromOffset(P.Width, P.Height),
	ZIndex = 5,
})

-- the profile opens the Статистика window
local profileButton = Instance.new("TextButton")
profileButton.Name = "OpenStats"
profileButton.Size = UDim2.fromScale(1, 1)
profileButton.BackgroundTransparency = 1
profileButton.Text = ""
profileButton.ZIndex = 9
profileButton.Parent = profile
profileButton.Activated:Connect(function()
	if Window.Current() == Stats.Window then
		Window.CloseAll()
	else
		Stats.Open()
	end
end)

local avatarFrame = Style.Panel(profile, {
	Position = UDim2.fromOffset(10, (P.Height - P.Avatar) / 2),
	Size = UDim2.fromOffset(P.Avatar, P.Avatar),
	ZIndex = 6,
	Fill = C.CardDark,
	Transparency = 0,
	Border = C.GoldDim,
	Cut = 8,
})
local avatar = Instance.new("ImageLabel")
avatar.Name = "Avatar"
avatar.Position = UDim2.fromOffset(4, 4)
avatar.Size = UDim2.new(1, -8, 1, -8)
avatar.BackgroundTransparency = 1
avatar.ZIndex = 7
avatar.Parent = avatarFrame
task.spawn(function()
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and image then
		avatar.Image = image
	else
		Icons.Make(avatarFrame, "user", 40, C.Muted, 8).Position = UDim2.fromOffset(13, 13)
	end
end)

-- level badge over the avatar's corner
local badge = Style.Panel(profile, {
	Name = "LevelBadge",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(10 + P.Avatar - 4, (P.Height + P.Avatar) / 2 - 4),
	Size = UDim2.fromOffset(30, 26),
	ZIndex = 9,
	Fill = C.Gold,
	Transparency = 0,
	Border = Color3.fromRGB(255, 226, 140),
	Cut = 6,
	Thickness = 1,
})
local levelLabel = Style.Label(badge, "1", 15, Color3.fromRGB(26, 20, 8), { Font = Style.FontTitle, Size = UDim2.fromScale(1, 1), ZIndex = 10 })
levelLabel:FindFirstChildOfClass("UIStroke").Enabled = false

local x0 = 10 + P.Avatar + 12
local nameLabel = Style.Label(profile, player.DisplayName, 17, C.Text, {
	Font = Style.FontTitle,
	Position = UDim2.fromOffset(x0, 8),
	Size = UDim2.new(1, -x0 - 10, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 6,
})
local _ = nameLabel
local classIcon = Icons.Make(profile, "user", 15, C.Gold, 7)
classIcon.Position = UDim2.fromOffset(x0, 32)
local classLabel = Style.Label(profile, "", 13, C.Gold, {
	Position = UDim2.fromOffset(x0 + 20, 31),
	Size = UDim2.new(1, -x0 - 30, 0, 16),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	RichText = true,
	ZIndex = 6,
})
local xpTrack, xpFill = Style.Bar(profile, {
	Position = UDim2.fromOffset(x0, 56),
	Size = UDim2.new(1, -x0 - 12, 0, 7),
	Color = C.Xp,
	ZIndex = 6,
})
local _ = xpTrack
local xpText = Style.Label(profile, "", 11, C.Muted, {
	Position = UDim2.fromOffset(x0, 66),
	Size = UDim2.new(1, -x0 - 12, 0, 13),
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 6,
})

local function refreshProfile()
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("Xp") or 0
	local xpNext = math.max(1, player:GetAttribute("XpNext") or 100)
	levelLabel.Text = tostring(level)
	Style.Tween(xpFill, 0.3, { Size = UDim2.fromScale(math.clamp(xp / xpNext, 0, 1), 1) })
	xpText.Text = ("%s / %s XP"):format(Format.Number(xp), Format.Number(xpNext))
	local classId = player:GetAttribute("Class") or ""
	local classDef = Config.Classes and Config.ClassById and Config.ClassById[classId]
	local rank = Config.RankFor(level)
	Icons.Set(classIcon, if classDef then classDef.Icon else "user", C.Gold)
	local hex = string.format("#%02X%02X%02X", C.Muted.R * 255, C.Muted.G * 255, C.Muted.B * 255)
	local title = player:GetAttribute("Title")
	local shown = if type(title) == "string" and title ~= "" then title else rank.Name
	classLabel.Text = (if classDef then Style.Upper(classDef.Name) else Style.Upper(T.NoClass)) .. ('  <font color="%s">%s</font>'):format(hex, shown)
end
for _, attribute in ipairs({ "Level", "Xp", "XpNext", "Class", "Title" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshProfile)
end
refreshProfile()

---------------------------------------------------------------------
-- Icon bar (under the profile)
---------------------------------------------------------------------

local B = U.BarButton
local bar = Instance.new("Frame")
bar.Name = "IconBar"
bar.Position = UDim2.fromOffset(LEFT, TOP + P.Height + 8)
bar.Size = UDim2.fromOffset(P.Width, B)
bar.BackgroundTransparency = 1
bar.ZIndex = 5
bar.Parent = Style.Gui
local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.Padding = UDim.new(0, 7)
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.Parent = bar

local actions = {
	Inventory = { Open = Inventory.Open, Windows = { Inventory.Window, Artifacts.Window } },
	Status = { Open = Status.Open, Windows = { Status.Window } },
	Skills = { Open = Skills.Open, Windows = { Skills.Window } },
	Quests = { Open = Reward.OpenQuests, Windows = { Reward.Window } },
	Shop = { Open = function()
		Store.Open()
	end, Windows = { Store.Window } },
	Teleport = { Open = Teleport.Open, Windows = { Teleport.Window } },
}

local barButtons = {} -- [id] = api
for order, def in ipairs(U.Bar) do
	local keyText = if def.Key then def.Key.Name else nil
	local button, api = Style.IconButton(bar, { Name = def.Id, Icon = def.Icon, Size = B, LayoutOrder = order, ZIndex = 6, Key = keyText })
	barButtons[def.Id] = api
	local action = actions[def.Id]
	button.Activated:Connect(function()
		local open = Window.Current()
		for _, w in ipairs(action.Windows) do
			if open == w then
				Window.CloseAll()
				return
			end
		end
		action.Open()
	end)
	-- tooltip
	local tip = Style.Plate(button, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.fromOffset(110, 24), ZIndex = 20 })
	tip.Visible = false
	Style.Label(tip, def.Label .. (if keyText and not Style.IsTouch() then " [" .. keyText .. "]" else ""), 12, C.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 21 })
	button.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	button.MouseLeave:Connect(function()
		tip.Visible = false
	end)
end

Window.OnChanged = function(open)
	for id, action in pairs(actions) do
		local active = false
		for _, w in ipairs(action.Windows) do
			if w == open then
				active = true
			end
		end
		barButtons[id].SetActive(active)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	for _, def in ipairs(U.Bar) do
		if def.Key and input.KeyCode == def.Key then
			local action = actions[def.Id]
			local open = Window.Current()
			for _, w in ipairs(action.Windows) do
				if open == w then
					Window.CloseAll()
					return
				end
			end
			action.Open()
			return
		end
	end
end)

local function refreshBadges()
	barButtons.Status.Badge(player:GetAttribute("StatPoints") or 0)
	barButtons.Skills.Badge(player:GetAttribute("SkillPoints") or 0)
	barButtons.Quests.Badge(if player:GetAttribute("RewardReady") then 1 else (player:GetAttribute("QuestsReady") or 0))
end
for _, attribute in ipairs({ "SkillPoints", "StatPoints", "RewardReady", "QuestsReady" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshBadges)
end
refreshBadges()

---------------------------------------------------------------------
-- Quest tracker (left, under the bar)
---------------------------------------------------------------------

local tracker = Style.Panel(Style.Gui, {
	Name = "QuestTracker",
	Position = UDim2.fromOffset(LEFT, TOP + P.Height + 8 + B + 12),
	Size = UDim2.fromOffset(250, 96),
	ZIndex = 5,
	Border = C.Line,
	Cut = 8,
})
local trackerButton = Instance.new("TextButton")
trackerButton.Size = UDim2.fromScale(1, 1)
trackerButton.BackgroundTransparency = 1
trackerButton.Text = ""
trackerButton.ZIndex = 9
trackerButton.Parent = tracker
trackerButton.Activated:Connect(function()
	actions.Quests.Open()
end)
local qIcon = Icons.Make(tracker, "quest", 14, C.Gold, 6)
qIcon.Position = UDim2.fromOffset(10, 9)
Style.Label(tracker, T.Quest, 11, C.Gold, { Position = UDim2.fromOffset(28, 8), Size = UDim2.new(1, -36, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 })
local qTitle = Style.Label(tracker, "", 15, C.Text, { Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 })
local qText = Style.Label(tracker, "", 12, C.Muted, { Position = UDim2.fromOffset(10, 46), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 6 })
local qTrack, qFill = Style.Bar(tracker, { Position = UDim2.fromOffset(10, 80), Size = UDim2.new(1, -64, 0, 5), Color = C.Gold, ZIndex = 6 })
local _ = qTrack
local qCount = Style.Label(tracker, "", 12, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 74), Size = UDim2.fromOffset(48, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 })

local lastQuest, lastReady = nil, false
local function refreshTracker()
	local q = decode("Tracker")
	if type(q) == "table" and q.Title then
		local ST = Config.System.Texts
		if lastQuest ~= nil and q.Title ~= lastQuest then
			SystemNotice.Show(ST.NewQuest, { q.Title, q.Text or "" })
		elseif lastQuest == q.Title and q.Ready and not lastReady then
			SystemNotice.Show(ST.QuestDone, { q.Title, ST.QuestBack }, "gold")
		end
		lastQuest, lastReady = q.Title, q.Ready == true
		qTitle.Text = q.Title
		qText.Text = q.Text or ""
		local target = math.max(1, tonumber(q.Target) or 1)
		local progress = math.clamp(tonumber(q.Progress) or 0, 0, target)
		qFill.Size = UDim2.fromScale(progress / target, 1)
		qCount.Text = ("%d/%d"):format(progress, target)
		qFill.Parent.Visible = true
	else
		qTitle.Text = T.NoQuest
		qText.Text = ""
		qCount.Text = ""
		qFill.Parent.Visible = false
	end
end
player:GetAttributeChangedSignal("Tracker"):Connect(refreshTracker)
refreshTracker()

---------------------------------------------------------------------
-- Objective (top center) and the dungeon damage hint
---------------------------------------------------------------------

local objective = Style.Label(Style.Gui, "", 20, C.Text, {
	Name = "Objective",
	Font = Style.FontTitle,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP),
	Size = UDim2.fromOffset(600, 26),
	ZIndex = 5,
})
local objectiveScale = Instance.new("UIScale")
objectiveScale.Parent = objective

-- Second line: your damage vs the room's recommended damage.
local hintPlate = Style.Plate(Style.Gui, {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP + 32),
	Size = UDim2.fromOffset(320, 28),
	ZIndex = 5,
})
local hintLabel = Style.Label(hintPlate, "", 14, C.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 6 })
hintPlate.Visible = false

local hintRoom = nil
local function refreshHint()
	-- the gate runs show waves instead (GateHud); the old room hint is off
	if true then
		hintPlate.Visible = false
		return
	end
	if not hintRoom then
		hintPlate.Visible = false
		return
	end
	-- the goal is the next record room when the current one is far below it
	local reached = player:GetAttribute("RoomReached") or 0
	local goal = math.max(hintRoom, math.min(Config.Dungeon.Rooms, reached + 1))
	local recommended = Config.RecommendedDamage(goal)
	local mine = player:GetAttribute("ClickPower") or 1
	local enough = mine >= recommended
	hintLabel.Text = Config.Hud.DamageHint:format(Format.Number(mine), goal, Format.Number(recommended))
	hintLabel.TextColor3 = if enough then C.Green else Color3.fromRGB(240, 110, 100)
	hintPlate.Visible = true
end
player:GetAttributeChangedSignal("ClickPower"):Connect(refreshHint)

-- The objective line shows for a few seconds when the goal changes
-- (entering the hub, a new quest) and fades out: the lasting goal lives
-- in the quest tracker (Config.Hud.ObjectiveSeconds).
local currentRoomAlive = nil
local shownGoal = nil
local hideToken = 0
local function setObjective(text)
	if shownGoal == text then
		return
	end
	shownGoal = text
	objective.Text = Style.Upper(text)
	objective.TextTransparency = 0
	objective.Visible = true
	objectiveScale.Scale = 1.15
	Style.Tween(objectiveScale, 0.25, { Scale = 1 })
	hideToken += 1
	local token = hideToken
	task.delay(Config.Hud.ObjectiveSeconds, function()
		if token == hideToken then
			Style.Tween(objective, 0.5, { TextTransparency = 1 })
			task.delay(0.55, function()
				if token == hideToken then
					objective.Visible = false
				end
			end)
		end
	end)
end
objective.Visible = false

local function refreshObjective()
	local zone = player:GetAttribute("Zone")
	if zone == "Dungeon" then
		-- GateHud shows the sections there
		hideToken += 1
		objective.Visible = false
		shownGoal = nil
		return
	end
	setObjective(Config.Hud.Objectives.Hub)
end

-- A new quest in the tracker is a new goal: show its title for a moment.
local lastQuest = nil
player:GetAttributeChangedSignal("Tracker"):Connect(function()
	local ok, q = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Tracker") or "")
	local title = ok and type(q) == "table" and q.Title or nil
	if title and title ~= lastQuest and player:GetAttribute("Zone") ~= "Dungeon" then
		if lastQuest ~= nil then
			setObjective(Config.Hud.Objectives.Quest:format(title))
		end
	end
	lastQuest = title
end)

-- Hud.SetCurrentRoom is called by Zone.luau with the room the player stands in.
local currentRoom = nil
local roomAlive = {}
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

-- Timed x2 boosts (under the objective).
local boostLabel = Style.Label(Style.Gui, "", 13, C.Gold, {
	Name = "Boost",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP + 64),
	Size = UDim2.fromOffset(420, 18),
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
		boostLabel.Text = Style.Upper(table.concat(parts, "   ·   "))
		boostLabel.Visible = #parts > 0
		task.wait(1)
	end
end)

---------------------------------------------------------------------
-- Top right: settings, sound
---------------------------------------------------------------------

local topRight = Instance.new("Frame")
topRight.Name = "TopRight"
topRight.AnchorPoint = Vector2.new(1, 0)
topRight.Position = UDim2.new(1, -14, 0, 10)
topRight.Size = UDim2.fromOffset(96, 42)
topRight.BackgroundTransparency = 1
topRight.Parent = Style.Gui
local trLayout = Instance.new("UIListLayout")
trLayout.FillDirection = Enum.FillDirection.Horizontal
trLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
trLayout.Padding = UDim.new(0, 6)
trLayout.SortOrder = Enum.SortOrder.LayoutOrder
trLayout.Parent = topRight

local settingsButton = Style.IconButton(topRight, { Name = "Settings", Icon = "gear", Size = 42, LayoutOrder = 1, ZIndex = 6 })
settingsButton.Activated:Connect(Settings.Open)
local soundButton, soundApi = Style.IconButton(topRight, { Name = "Sound", Icon = "sound", Size = 42, LayoutOrder = 2, ZIndex = 6 })
soundButton.Activated:Connect(function()
	local on = Settings.ToggleSound()
	Icons.Set(soundApi.Icon, if on then "sound" else "mute", if on then C.Text else C.Muted)
end)

---------------------------------------------------------------------
-- Bottom center: HP + ability slots
---------------------------------------------------------------------

local S = U.AbilitySize
local bottom = Instance.new("Frame")
bottom.Name = "BottomCenter"
bottom.AnchorPoint = Vector2.new(0.5, 1)
bottom.Position = UDim2.new(0.5, 0, 1, -14)
bottom.Size = UDim2.fromOffset(U.HealthWidth, S + 40)
bottom.BackgroundTransparency = 1
bottom.Parent = Style.Gui

local slotRow = Instance.new("Frame")
slotRow.Name = "Abilities"
slotRow.AnchorPoint = Vector2.new(0.5, 0)
slotRow.Position = UDim2.fromScale(0.5, 0)
slotRow.Size = UDim2.fromOffset(#U.AbilitySlots * (S + 8) - 8, S)
slotRow.BackgroundTransparency = 1
slotRow.Parent = bottom
local slotLayout = Instance.new("UIListLayout")
slotLayout.FillDirection = Enum.FillDirection.Horizontal
slotLayout.Padding = UDim.new(0, 8)
slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotLayout.Parent = slotRow

local slots = {} -- [slot] = { button, icon, shade, timer, keyLabel, shape }
for order, def in ipairs(U.AbilitySlots) do
	local button = Instance.new("TextButton")
	button.Name = "Slot_" .. def.Slot
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(S, S)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = 6
	button.Parent = slotRow
	local shape = Style.Chamfer(button, { Fill = C.PanelDark, Transparency = U.PanelTransparency, Border = C.Line, Cut = 8 })
	local icon = Icons.Make(button, def.Icon or "lock", math.floor(S * 0.52), C.Line, 7)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.new(0, 3, 1, -3)
	shade.Size = UDim2.new(1, -6, 0, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.ZIndex = 8
	shade.Parent = button
	local timer = Style.Label(button, "", 18, C.Text, { Font = Style.FontTitle, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	local keyLabel = Style.Label(button, def.Label or def.Slot, 11, C.GoldDim, {
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.fromOffset(S - 12, 13),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	})
	keyLabel.Visible = not Style.IsTouch()
	slots[def.Slot] = { button = button, icon = icon, shade = shade, timer = timer, keyLabel = keyLabel, shape = shape, def = def }
	button.Activated:Connect(function()
		if Hud.OnAbility then
			Hud.OnAbility(def.Slot)
		end
	end)
end

local function refreshLoadout()
	local loadout = decode("Loadout") or {}
	local classId = player:GetAttribute("Class") or ""
	local shown = 0
	for slot, ui in pairs(slots) do
		local visible = ui.def.Class == nil or ui.def.Class == classId
		ui.button.Visible = visible
		if visible then
			shown += 1
		end
		local entry = loadout[slot]
		local fixed = (slot == "Dash" or slot == "Block") and classId ~= ""
		local filled = (type(entry) == "table" and entry.Icon ~= nil) or fixed
		local iconName = if type(entry) == "table" and entry.Icon then entry.Icon else (ui.def.Icon or "lock")
		local active = slot == "Block" and player:GetAttribute("Blocking") == true
		Icons.Set(ui.icon, iconName, if active then C.Gold elseif filled then C.Text else C.Line)
		ui.shape.SetBorder(if active then C.Gold elseif filled then C.GoldDim else C.Line)
	end
	slotRow.Size = UDim2.fromOffset(shown * (S + 8) - 8, S)
end
player:GetAttributeChangedSignal("Loadout"):Connect(refreshLoadout)
player:GetAttributeChangedSignal("Class"):Connect(refreshLoadout)
player:GetAttributeChangedSignal("Blocking"):Connect(refreshLoadout)
refreshLoadout()

-- Cooldowns (every frame, cheap).
RunService.RenderStepped:Connect(function()
	local now = Workspace:GetServerTimeNow()
	for slot, ui in pairs(slots) do
		local readyAt = player:GetAttribute("Ready_" .. slot) or 0
		local total = math.max(0.1, player:GetAttribute("CooldownMax_" .. slot) or 1)
		local left = readyAt - now
		if left > 0 then
			ui.shade.Size = UDim2.new(1, -6, math.clamp(left / total, 0, 1), -6)
			ui.timer.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
		else
			ui.shade.Size = UDim2.new(1, -6, 0, 0)
			ui.timer.Text = ""
		end
	end
end)

-- HP bar
local hpTrack, hpFill, hpText = Style.Bar(bottom, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 20),
	Color = C.Health,
	Border = C.GoldDim,
	ZIndex = 6,
	TextSize = 13,
})
local _ = hpTrack
local function refreshHealth()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		hpFill.Size = UDim2.fromScale(ratio, 1)
		hpText.Text = ("%d / %d"):format(math.floor(humanoid.Health + 0.5), humanoid.MaxHealth)
	end
end
local function watchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.HealthChanged:Connect(refreshHealth)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHealth)
	refreshHealth()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

---------------------------------------------------------------------
-- Bottom left: credits and Кристаллы
---------------------------------------------------------------------

local credits = Style.Panel(Style.Gui, {
	Name = "Credits",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, LEFT, 1, -14),
	Size = UDim2.fromOffset(250, 42),
	ZIndex = 5,
	Border = C.Line,
	Cut = 8,
})
local creditsIcon = Icons.Make(credits, "credits", 24, C.Gold, 6)
creditsIcon.AnchorPoint = Vector2.new(0, 0.5)
creditsIcon.Position = UDim2.new(0, 12, 0.5, 0)
local creditsValue = Style.Label(credits, "0", 19, C.Text, {
	Font = Style.FontTitle,
	Position = UDim2.fromOffset(44, 0),
	Size = UDim2.fromOffset(100, 42),
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
})
local creditsScale = Instance.new("UIScale")
creditsScale.Parent = creditsValue
local lastCredits = player:GetAttribute("Credits") or 0
local function refreshCredits()
	local value = player:GetAttribute("Credits") or 0
	creditsValue.Text = Format.Number(value)
	if value > lastCredits then
		creditsScale.Scale = 1.15
		Style.Tween(creditsScale, 0.25, { Scale = 1 })
	end
	lastCredits = value
end
player:GetAttributeChangedSignal("Credits"):Connect(refreshCredits)
refreshCredits()
local crystalsIcon = Icons.Make(credits, "crystal", 22, Config.Crystals.Color, 6)
crystalsIcon.AnchorPoint = Vector2.new(0, 0.5)
crystalsIcon.Position = UDim2.new(0, 152, 0.5, 0)
local crystalsValue = Style.Label(credits, "0", 19, C.Text, {
	Font = Style.FontTitle,
	Position = UDim2.fromOffset(180, 0),
	Size = UDim2.fromOffset(64, 42),
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
})
local function refreshCrystals()
	crystalsValue.Text = Format.Number(player:GetAttribute("Crystals") or 0)
end
player:GetAttributeChangedSignal("Crystals"):Connect(refreshCrystals)
refreshCrystals()

-- Playtime gift (EngageService): above the wallet, the next gift and a
-- timer; when ready it glows gold and a click claims it.
local GF = Config.Gifts
local gift = Instance.new("TextButton")
gift.Name = "Gift"
gift.AnchorPoint = Vector2.new(0, 1)
gift.Position = UDim2.new(0, LEFT, 1, -62)
gift.Size = UDim2.fromOffset(250, 36)
gift.BackgroundTransparency = 1
gift.Text = ""
gift.ZIndex = 5
gift.Parent = Style.Gui
local giftShape = Style.Chamfer(gift, { Fill = C.PanelDark, Transparency = 0.12, Border = C.Line, Cut = 6, Thickness = 1.5 })
local giftIcon = Icons.Make(gift, "chest", 20, C.Gold, 6)
giftIcon.AnchorPoint = Vector2.new(0, 0.5)
giftIcon.Position = UDim2.new(0, 12, 0.5, 0)
local giftText = Style.Label(gift, "", 14, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -50, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 })
local giftPulse = Instance.new("UIScale")
giftPulse.Parent = gift
local giftReady = false
local function rewardOf(def): string
	local parts = {}
	if def.Crystals then
		table.insert(parts, def.Crystals .. " крист.")
	end
	if def.Credits then
		table.insert(parts, Format.Number(def.Credits) .. " кр.")
	end
	if def.Cores then
		table.insert(parts, def.Cores .. " ядер")
	end
	return table.concat(parts, " + ")
end
local giftPlayed, giftClock = 0, os.clock()
local function refreshGift()
	local index = player:GetAttribute("GiftNext") or 0
	local def = GF.List[index]
	gift.Visible = def ~= nil and player:GetAttribute("Zone") ~= "Dungeon"
	if not def then
		return
	end
	local left = (player:GetAttribute("GiftAt") or 0) - (giftPlayed + (os.clock() - giftClock))
	giftReady = left <= 0
	if giftReady then
		giftText.Text = GF.Texts.Ready .. "  " .. rewardOf(def)
		giftText.TextColor3 = C.Gold
		giftShape.SetBorder(C.Gold)
	else
		local s = math.max(0, math.ceil(left))
		giftText.Text = GF.Texts.Next:format(("%d:%02d"):format(s // 60, s % 60)) .. "  ·  " .. rewardOf(def)
		giftText.TextColor3 = C.Text
		giftShape.SetBorder(C.Line)
	end
end
player:GetAttributeChangedSignal("GiftPlayed"):Connect(function()
	giftPlayed = player:GetAttribute("GiftPlayed") or 0
	giftClock = os.clock()
	refreshGift()
end)
player:GetAttributeChangedSignal("GiftNext"):Connect(refreshGift)
player:GetAttributeChangedSignal("Zone"):Connect(refreshGift)
task.spawn(function()
	while true do
		task.wait(1)
		refreshGift()
		if giftReady and gift.Visible then
			giftPulse.Scale = 1.06
			Style.Tween(giftPulse, 0.5, { Scale = 1 })
		end
	end
end)
gift.Activated:Connect(function()
	if not giftReady then
		Popups.Toast(giftText.Text, "gold")
		return
	end
	task.spawn(function()
		local ok, message = ReplicatedStorage:WaitForChild("Engage"):InvokeServer("Gift")
		if not ok then
			Popups.Toast(message or "", "bad")
		end
	end)
end)

---------------------------------------------------------------------
-- Bottom right: ИГРАТЬ / В ХАБ
---------------------------------------------------------------------

local play = Instance.new("TextButton")
play.Name = "Play"
play.AnchorPoint = Vector2.new(1, 1)
play.Position = UDim2.new(1, -16, 1, -14)
play.Size = UDim2.fromOffset(214, 62)
play.BackgroundTransparency = 1
play.Text = ""
play.AutoButtonColor = false
play.ZIndex = 6
play.Parent = Style.Gui
local playShape = Style.Chamfer(play, { Fill = C.Gold, Transparency = 0, Border = Color3.fromRGB(255, 230, 150), Cut = 12, Thickness = 2 })
local playGradient = {} -- the body pieces get a vertical gradient
for _, f in ipairs(playShape.Body) do
	if not f:FindFirstChildOfClass("UIGradient") then
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(255, 214, 104), Color3.fromRGB(196, 146, 40))
		g.Parent = f
		table.insert(playGradient, g)
	end
end
local playIcon = Icons.Make(play, "play", 26, Color3.fromRGB(28, 22, 10), 8)
playIcon.AnchorPoint = Vector2.new(0, 0.5)
playIcon.Position = UDim2.new(0, 22, 0.5, 0)
local playLabel = Style.Label(play, U.Play.Text, 26, Color3.fromRGB(28, 22, 10), {
	Font = Style.FontTitle,
	Position = UDim2.fromOffset(56, 0),
	Size = UDim2.new(1, -66, 1, 0),
	ZIndex = 8,
})
playLabel:FindFirstChildOfClass("UIStroke").Enabled = false
local playScale = Instance.new("UIScale")
playScale.Parent = play
play.MouseButton1Down:Connect(function()
	Style.Tween(playScale, 0.06, { Scale = 0.96 })
end)
play.MouseButton1Up:Connect(function()
	Style.Tween(playScale, 0.12, { Scale = 1 })
end)
play.MouseLeave:Connect(function()
	Style.Tween(playScale, 0.12, { Scale = 1 })
end)

local function inDungeon(): boolean
	return player:GetAttribute("Zone") == "Dungeon"
end
local function refreshPlay()
	local back = inDungeon()
	playLabel.Text = if back then U.Play.Back else U.Play.Text
	local dark = Color3.fromRGB(28, 22, 10)
	if back then
		playShape.SetFill(Color3.fromRGB(40, 36, 30), 0.05)
		playShape.SetBorder(C.GoldDim)
		for _, g in ipairs(playGradient) do
			g.Enabled = false
		end
		playLabel.TextColor3 = C.Gold
		Icons.Set(playIcon, "back", C.Gold)
	else
		playShape.SetFill(C.Gold, 0)
		playShape.SetBorder(Color3.fromRGB(255, 230, 150))
		for _, g in ipairs(playGradient) do
			g.Enabled = true
		end
		playLabel.TextColor3 = dark
		Icons.Set(playIcon, "play", dark)
	end
end
player:GetAttributeChangedSignal("Zone"):Connect(refreshPlay)
refreshPlay()

local backKey = Style.Label(play, "[" .. U.Play.BackKey.Name .. "]", 11, C.GoldDim, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -8, 1, -4),
	Size = UDim2.fromOffset(30, 12),
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 8,
})
local function refreshBackKey()
	backKey.Visible = inDungeon() and not Style.IsTouch()
end
player:GetAttributeChangedSignal("Zone"):Connect(refreshBackKey)
refreshBackKey()

play.Activated:Connect(function()
	Style.PlaySound("Ui", 1, 0.4)
	if inDungeon() then
		Gates.Go("Hub")
	else
		Gates.Open()
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == U.Play.BackKey and inDungeon() then
		Gates.Go("Hub")
	end
end)

---------------------------------------------------------------------
-- Level up: big banner, flash, sound
---------------------------------------------------------------------

local levelUpRemote = ReplicatedStorage:WaitForChild("LevelUp")
local LT = Config.Progression.Level.Texts
levelUpRemote.OnClientEvent:Connect(function(level, points)
	level = tonumber(level) or 1
	task.wait(0.1) -- let the new MaxHealth attribute arrive
	local rank = Config.RankFor(level)
	local ST = Config.System.Texts
	local gained = tonumber(points) or 1
	local lines = {
		ST.Level:format(level) .. "  •  " .. ST.SkillPoints:format(gained) .. "  •  " .. ST.StatPoints:format(gained * Config.Attributes.PointsPerLevel),
		LT.Growth:format(Format.Number(player:GetAttribute("ClickPower") or 1), Format.Number(player:GetAttribute("MaxHealth") or Config.Player.Health)),
	}
	if rank.Level == level then
		table.insert(lines, ST.Rank:format(rank.Name))
	end
	SystemNotice.Show(ST.LevelUp, lines, "gold")
	Popups.Flash(C.Gold)
	Style.PlaySound("Forged", 1.2, 0.7)
end)

return Hud
