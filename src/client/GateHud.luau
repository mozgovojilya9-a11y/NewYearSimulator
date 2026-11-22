--[[
	GateHud.luau
	On-screen life of a gate run (GateState from DungeonRuns):
	  * the run panel at the top: the location, "УЧАСТОК 2/3 · врагов 4/6"
	    with a kill bar (or the boss arena); red border in Red Gates;
	  * the boss intro: black bars, the camera looks at the boss portal,
	    the boss name and title, then back to the player;
	  * "ФАЗА 2" banners;
	  * the combo counter (GateHud.Hit from Combat) and the dodge / shield
	    popups;
	  * the group invite popup (PartyEvent "Invite").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)

local C = Style.Colors
local WT = Config.Sections.Texts
local player = Players.LocalPlayer
local stateRemote = ReplicatedStorage:WaitForChild("GateState")
local partyRemote = ReplicatedStorage:WaitForChild("Party")
local partyEvent = ReplicatedStorage:WaitForChild("PartyEvent")

local GateHud = {}

local TOP = Config.Hud.TopLeftReserved.Y + 4

---------------------------------------------------------------------
-- Wave panel
---------------------------------------------------------------------

local panel, shape = Style.Panel(Style.Gui, {
	Name = "WavePanel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP),
	Size = UDim2.fromOffset(380, 78),
	Fill = C.PanelDark,
	Border = C.GoldDim,
	Cut = 10,
	ZIndex = 6,
	Visible = false,
})
local zoneLine = Style.Label(panel, "", 12, C.Muted, { Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, 0, 0, 14), ZIndex = 7 })
local waveLine = Style.Label(panel, "", 23, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), ZIndex = 7 })
local countLine = Style.Label(panel, "", 13, C.Muted, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 16), ZIndex = 7, Visible = false })
local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 0, 56)
barBack.Size = UDim2.new(1, -60, 0, 6)
barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
barBack.BorderSizePixel = 0
barBack.ZIndex = 7
barBack.Parent = panel
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = C.Gold
barFill.BorderSizePixel = 0
barFill.ZIndex = 8
barFill.Parent = barBack
local waveScale = Instance.new("UIScale")
waveScale.Parent = waveLine

-- the run contract (Config.Contracts) under the run panel
local CTR = Config.Contracts
local contractPanel, contractShape = Style.Panel(Style.Gui, {
	Name = "ContractPanel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP + 84),
	Size = UDim2.fromOffset(380, 30),
	Fill = C.PanelDark,
	Border = CTR.Colors.Active,
	Cut = 6,
	ZIndex = 6,
	Visible = false,
})
local contractLine = Style.Label(contractPanel, "", 14, C.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 7, RichText = true })
local contractDeadline = nil -- os.clock() when a Time contract runs out

local state = nil
local lastWave = nil

local function render()
	local s = state
	panel.Visible = s ~= nil and player:GetAttribute("Zone") == "Dungeon"
	if not panel.Visible then
		contractPanel.Visible = false
		return
	end
	shape.SetBorder(if s.Red then Config.RedGate.Color else C.GoldDim)
	zoneLine.Text = Style.Upper(s.Location or "") .. (if s.Red then "  •  " .. Config.RedGate.Texts.Name else "")
	zoneLine.TextColor3 = if s.Red then Config.RedGate.Color else C.Muted
	countLine.Visible = false
	barBack.Visible = true
	if s.Phase == "Done" then
		waveLine.Text = Style.Upper(Config.Grades.Texts.Won)
		waveLine.TextColor3 = C.Gold
		barBack.Visible = false
	elseif s.Zone > s.Zones then
		waveLine.Text = WT.Boss
		waveLine.TextColor3 = Config.DungeonLayout.BossBarrierColor
		barBack.Visible = false
		countLine.Visible = s.Phase == "Enter"
		countLine.Text = WT.Enter
	else
		local total = math.max(1, s.Total or 1)
		local alive = s.Alive or 0
		waveLine.Text = WT.Section:format(s.Zone, s.Zones) .. "  ·  " .. Style.Upper(WT.Enemies:format(alive, total))
		waveLine.TextColor3 = if alive == 0 then C.Green else C.Text
		Style.Tween(barFill, 0.2, { Size = UDim2.fromScale(1 - alive / total, 1) })
	end
	local k = s.Contract
	contractPanel.Visible = k ~= nil and s.Phase ~= "Done" or (k ~= nil and k.Done)
	if k then
		local color = if k.Done then CTR.Colors.Done elseif k.Failed then CTR.Colors.Failed else CTR.Colors.Active
		contractShape.SetBorder(color)
		contractLine.TextColor3 = color
		contractLine.Text = CTR.Texts.Title .. "  ·  " .. k.Text .. (if k.Done then "  ·  ВЫПОЛНЕН" elseif k.Failed then "  ·  ПРОВАЛЕН" else "")
		contractDeadline = if k.Deadline and not k.Done and not k.Failed then os.clock() + k.Deadline else nil
	end
	local key = tostring(s.Zone) .. ":" .. tostring(s.Phase)
	if key ~= lastWave then
		lastWave = key
		waveScale.Scale = 1.25
		Style.Tween(waveScale, 0.3, { Scale = 1 })
	end
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Dungeon" then
		state = nil
	end
	render()
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		if contractDeadline and contractPanel.Visible and state and state.Contract then
			local left = math.max(0, math.ceil(contractDeadline - os.clock()))
			contractLine.Text = CTR.Texts.Title .. "  ·  " .. state.Contract.Text .. ("  (%d:%02d)"):format(left // 60, left % 60)
			if left <= 0 then
				contractLine.TextColor3 = CTR.Colors.Failed
			end
		end
	end
end)

---------------------------------------------------------------------
-- Boss intro
---------------------------------------------------------------------

local bars = {}
for i, anchor in ipairs({ 0, 1 }) do
	local bar = Instance.new("Frame")
	bar.Name = "IntroBar" .. i
	bar.AnchorPoint = Vector2.new(0, anchor)
	-- the top bar also covers the Roblox top bar area (the GUI starts below it)
	bar.Position = UDim2.new(0, 0, anchor, if anchor == 0 then -80 else 0)
	bar.Size = UDim2.new(1, 0, 0, 0)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BorderSizePixel = 0
	bar.ZIndex = 80
	bar.Parent = Style.Gui
	bars[i] = bar
end
local introName = Style.Label(Style.Gui, "", 56, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(1, 0, 0, 52), ZIndex = 81, Visible = false })
local introTitle = Style.Label(Style.Gui, "", 18, Config.DungeonLayout.BossBarrierColor, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.79), Size = UDim2.new(1, 0, 0, 22), ZIndex = 81, Visible = false })

local function bossIntro(info)
	local camera = Workspace.CurrentCamera
	local seconds = info.Seconds or 3
	for _, bar in ipairs(bars) do
		Style.Tween(bar, 0.35, { Size = UDim2.new(1, 0, 0.12, if bar.Name == "IntroBar1" then 80 else 0) })
	end
	introName.Text = Style.Upper(info.Name or "")
	introTitle.Text = info.Title or ""
	introName.Visible, introTitle.Visible = false, false
	Style.PlaySound(Config.Sounds.Portal, 0.6, 0.9)
	local dropAt = info.DropAt or seconds * 0.5
	local oldType = camera.CameraType
	local target = typeof(info.Position) == "Vector3" and info.Position
	if target then
		-- circle the arena while the boss falls, then hold on it from the front
		camera.CameraType = Enum.CameraType.Scriptable
		local from = camera.CFrame
		local center = if typeof(info.Center) == "Vector3" then info.Center else target
		local radius = math.max(30, (info.Size or 60) * 0.42)
		local height = info.Height or 18
		local orbit = math.rad(Config.Enemies.Boss.Intro.Orbit)
		local toTarget = Vector3.new(target.X - center.X, 0, target.Z - center.Z)
		local endAngle = if toTarget.Magnitude > 0.1 then math.atan2(toTarget.Z, toTarget.X) + math.pi else 0
		local startAngle = endAngle - orbit
		local focus = target + Vector3.new(0, height * 0.45, 0)
		local start = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t >= seconds - 0.2 then
				connection:Disconnect()
				camera.CFrame = from
				camera.CameraType = oldType
				return
			end
			if t < dropAt then
				local k = t / dropAt
				k = 1 - (1 - k) * (1 - k)
				local a = startAngle + orbit * k
				local eye = center + Vector3.new(math.cos(a) * radius, height * 0.8 + 6, math.sin(a) * radius)
				camera.CFrame = CFrame.lookAt(eye, center:Lerp(focus, k))
			else
				-- after the landing: slowly push in on the boss
				local k = math.min(1, (t - dropAt) / math.max(0.1, seconds - dropAt))
				local dir = Vector3.new(math.cos(endAngle), 0, math.sin(endAngle))
				local eye = target + dir * (radius * (0.75 - 0.15 * k)) + Vector3.new(0, height * 0.55, 0)
				camera.CFrame = CFrame.lookAt(eye, focus)
			end
		end)
	end
	task.delay(dropAt, function()
		-- the landing: shake, then the big name and title
		Popups.Shake(1.1, 0.6)
		introName.Visible, introTitle.Visible = true, true
		introName.TextTransparency, introTitle.TextTransparency = 1, 1
		local nameScale = introName:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		nameScale.Scale = 1.5
		nameScale.Parent = introName
		Style.Tween(nameScale, 0.35, { Scale = 1 })
		Style.Tween(introName, 0.3, { TextTransparency = 0 })
		Style.Tween(introTitle, 0.6, { TextTransparency = 0 })
	end)
	task.delay(seconds, function()
		for _, bar in ipairs(bars) do
			Style.Tween(bar, 0.35, { Size = UDim2.new(1, 0, 0, 0) })
		end
		Style.Tween(introName, 0.4, { TextTransparency = 1 })
		Style.Tween(introTitle, 0.4, { TextTransparency = 1 })
		task.delay(0.45, function()
			introName.Visible, introTitle.Visible = false, false
		end)
	end)
end

---------------------------------------------------------------------
-- Охотничий азарт (kill streak, server StreakService)
---------------------------------------------------------------------

local ST = Config.Streak
local streakPanel = Style.Panel(Style.Gui, {
	Name = "StreakPanel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.4, 0),
	Size = UDim2.fromOffset(230, 74),
	Fill = C.PanelDark,
	Border = ST.Color,
	Cut = 8,
	ZIndex = 6,
	Visible = false,
})
local streakTitle = Style.Label(streakPanel, "", 26, ST.Color, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 30), ZIndex = 7 })
local streakBonus = Style.Label(streakPanel, "", 13, C.Text, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 16), ZIndex = 7 })
local streakBack = Instance.new("Frame")
streakBack.AnchorPoint = Vector2.new(0.5, 0)
streakBack.Position = UDim2.new(0.5, 0, 0, 58)
streakBack.Size = UDim2.new(1, -30, 0, 5)
streakBack.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
streakBack.BorderSizePixel = 0
streakBack.ZIndex = 7
streakBack.Parent = streakPanel
local streakFill = Instance.new("Frame")
streakFill.Size = UDim2.fromScale(1, 1)
streakFill.BackgroundColor3 = ST.Color
streakFill.BorderSizePixel = 0
streakFill.ZIndex = 8
streakFill.Parent = streakBack
local streakScale = Instance.new("UIScale")
streakScale.Parent = streakTitle
local streakTween

function GateHud.Streak(count: number, window: number, xpPct: number, lootPct: number, milestone: string?)
	if count < 2 then
		return
	end
	streakPanel.Visible = true
	streakTitle.Text = ST.Texts.Title .. "  ×" .. tostring(count)
	streakBonus.Text = ST.Texts.Bonus:format(xpPct, lootPct)
	streakScale.Scale = if milestone then 1.5 else 1.15
	Style.Tween(streakScale, 0.2, { Scale = 1 })
	if streakTween then
		streakTween:Cancel()
	end
	streakFill.Size = UDim2.fromScale(1, 1)
	streakTween = TweenService:Create(streakFill, TweenInfo.new(window, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
	streakTween:Play()
	if milestone then
		Popups.Banner(ST.Texts.Title, milestone, {}, ST.Color)
		Popups.Shake(0.5, 0.3)
	end
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Dungeon" then
		streakPanel.Visible = false
	end
end)

function GateHud.StreakEnd(count: number)
	streakTitle.Text = ST.Texts.Lost
	streakBonus.Text = "×" .. tostring(count)
	task.delay(1.5, function()
		if streakTitle.Text == ST.Texts.Lost then
			streakPanel.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- Combo, dodge, shield
---------------------------------------------------------------------

local CB = Config.Combat
local combo = Style.Label(Style.Gui, "", 30, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 230, 1, -200), Size = UDim2.fromOffset(240, 34), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Visible = false })
local comboScale = Instance.new("UIScale")
comboScale.Parent = combo
local comboCount, comboAt = 0, 0

function GateHud.Hit(isCrit: boolean?)
	local now = os.clock()
	if now - comboAt > CB.Combo.Window then
		comboCount = 0
	end
	comboCount += 1
	comboAt = now
	if comboCount >= 3 then
		combo.Visible = true
		combo.Text = CB.Combo.Text:format(comboCount)
		combo.TextColor3 = if comboCount >= 30 then C.Red elseif comboCount >= 15 then C.Orange else C.Gold
		comboScale.Scale = if isCrit then 1.35 else 1.18
		Style.Tween(comboScale, 0.15, { Scale = 1 })
	end
end

task.spawn(function()
	while true do
		task.wait(0.2)
		if combo.Visible and os.clock() - comboAt > CB.Combo.Window then
			combo.Visible = false
			comboCount = 0
		end
	end
end)

function GateHud.Dodge()
	local head = player.Character and player.Character:FindFirstChild("Head")
	if head then
		Popups.World(head.Position + Vector3.new(0, 2.5, 0), CB.Texts.Dodge, C.Cyan, 30, false)
	end
end

function GateHud.Blocked(model)
	if model and model.Parent then
		Popups.World(model:GetPivot().Position + Vector3.new(0, 4, 0), CB.Texts.Blocked, C.Cyan, 24, false)
	end
end

---------------------------------------------------------------------
-- Group invite popup
---------------------------------------------------------------------

local invitePanel = Style.Panel(Style.Gui, {
	Name = "InvitePopup",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP + 96),
	Size = UDim2.fromOffset(380, 92),
	Fill = C.PanelDark,
	Border = C.Gold,
	Cut = 10,
	ZIndex = 50,
	Visible = false,
})
local inviteText = Style.Label(invitePanel, "", 15, C.Text, { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 20), ZIndex = 51 })
local inviteTimer = Style.Label(invitePanel, "", 11, C.Muted, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 14), ZIndex = 51 })
local acceptButton = Style.Button(invitePanel, { Position = UDim2.new(0, 12, 1, -42), Size = UDim2.new(0.5, -16, 0, 32), Text = Config.Party.Texts.Accept, TextSize = 14, Color = C.Gold, ZIndex = 52 })
local declineButton = Style.Button(invitePanel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 1, -42), Size = UDim2.new(0.5, -16, 0, 32), Text = Config.Party.Texts.Decline, TextSize = 14, Color = C.Card, ZIndex = 52 })
local invite = nil

acceptButton.Activated:Connect(function()
	if invite then
		local id = invite.Id
		invite = nil
		invitePanel.Visible = false
		task.spawn(function()
			local ok, message = partyRemote:InvokeServer("Accept", id)
			if not ok and message then
				Popups.Toast(message, "bad")
			end
		end)
	end
end)
declineButton.Activated:Connect(function()
	if invite then
		local id = invite.Id
		invite = nil
		invitePanel.Visible = false
		task.spawn(partyRemote.InvokeServer, partyRemote, "Decline", id)
	end
end)

partyEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "Invite" and type(payload) == "table" then
		invite = { Id = payload.Id, Ends = os.clock() + (payload.Seconds or Config.Party.InviteSeconds) }
		inviteText.Text = Config.Party.Texts.Invite:format(payload.From or "?")
		invitePanel.Visible = true
		Style.PlaySound("Ui", 1.5, 0.6)
	end
end)
RunService.Heartbeat:Connect(function()
	if invite then
		local left = invite.Ends - os.clock()
		if left <= 0 then
			invite = nil
			invitePanel.Visible = false
		else
			inviteTimer.Text = ("%d с"):format(math.ceil(left))
		end
	end
end)

---------------------------------------------------------------------

stateRemote.OnClientEvent:Connect(function(kind, payload)
	if kind == "Wave" and type(payload) == "table" then
		local before = state
		state = payload
		render()
		if payload.Phase == "Fight" and (not before or before.Wave ~= payload.Wave or before.Zone ~= payload.Zone) then
			Style.PlaySound(Config.Sounds.Barrier, 0.8, 0.5)
		end
	elseif kind == "Boss" and type(payload) == "table" then
		bossIntro(payload)
	elseif kind == "Phase" then
		local BT = Config.Enemies.Boss.Texts
		Popups.Banner("БОСС", BT.Phase:format(tonumber(payload) or 2) .. "  ·  " .. BT.Rage, {}, Config.Enemies.Boss.Rage.Color)
		Popups.Shake(0.7, 0.4)
	end
end)

return GateHud
