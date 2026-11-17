--[[
	GateHud.luau
	On-screen life of a gate run (GateState from DungeonRuns):
	  * the wave panel at the top: "ЗОНА 1/3 • Сборочный цех",
	    "ВОЛНА 2/4" (elite wave in gold), the enemy counter / the rest
	    timer / "проход открыт" / the boss arena; red border in Red Gates;
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
local W = Config.Waves
local WT = W.Texts
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
local zoneLine = Style.Label(panel, "", 12, C.Muted, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), ZIndex = 7 })
local waveLine = Style.Label(panel, "", 26, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 30), ZIndex = 7 })
local countLine = Style.Label(panel, "", 14, C.Text, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 18), ZIndex = 7 })
local waveScale = Instance.new("UIScale")
waveScale.Parent = waveLine

local state = nil
local lastWave = nil

local function render()
	local s = state
	panel.Visible = s ~= nil and player:GetAttribute("Zone") == "Dungeon"
	if not panel.Visible then
		return
	end
	shape.SetBorder(if s.Red then Config.RedGate.Color elseif s.Elite and s.Phase == "Fight" then C.Gold else C.GoldDim)
	local zoneText = if s.Zone > s.Zones then WT.Boss else WT.Zone:format(s.Zone, s.Zones)
	zoneLine.Text = Style.Upper(zoneText .. "  •  " .. (s.Location or "")) .. (if s.Red then "  •  " .. Config.RedGate.Texts.Name else "")
	zoneLine.TextColor3 = if s.Red then Config.RedGate.Color else C.Muted
	if s.Phase == "Boss" or (s.Zone > s.Zones and s.Phase ~= "Done") then
		waveLine.Text = WT.Boss
		waveLine.TextColor3 = Config.DungeonLayout.BossBarrierColor
		countLine.Text = if s.Phase == "Enter" then WT.Enter else ""
	elseif s.Phase == "Done" then
		waveLine.Text = Config.Grades.Texts.Won
		waveLine.TextColor3 = C.Gold
		countLine.Text = ""
	elseif s.Phase == "Cleared" then
		waveLine.Text = Style.Upper(WT.Cleared:match("^[^—]+") or WT.Cleared)
		waveLine.TextColor3 = C.Green
		countLine.Text = WT.Cleared:match("—%s*(.+)$") or ""
	elseif s.Phase == "Enter" or (s.Wave == 0 and s.Phase ~= "Rest") then
		waveLine.Text = WT.Zone:format(s.Zone, s.Zones)
		waveLine.TextColor3 = C.Text
		countLine.Text = WT.Enter
	else
		local title = WT.Wave:format(math.max(1, if s.Phase == "Rest" then s.Wave + 1 else s.Wave), s.Waves)
		waveLine.Text = if s.Elite and s.Phase == "Fight" then WT.Elite .. "  " .. title:match("%d+/%d+") else title
		waveLine.TextColor3 = if s.Elite and s.Phase == "Fight" then C.Gold else C.Text
		if s.Phase == "Rest" and s.Rest then
			countLine.Text = WT.Rest:format(math.max(0, math.ceil(s.Rest - Workspace:GetServerTimeNow())))
			countLine.TextColor3 = C.Muted
		else
			countLine.Text = WT.Enemies:format(s.Alive or 0)
			countLine.TextColor3 = C.Text
		end
	end
	local key = tostring(s.Zone) .. ":" .. tostring(s.Wave) .. ":" .. tostring(s.Phase)
	if key ~= lastWave then
		lastWave = key
		waveScale.Scale = 1.25
		Style.Tween(waveScale, 0.3, { Scale = 1 })
	end
end

task.spawn(function()
	while true do
		task.wait(0.25)
		if state and state.Phase == "Rest" then
			render()
		end
	end
end)
player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Dungeon" then
		state = nil
	end
	render()
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
local introName = Style.Label(Style.Gui, "", 46, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(1, 0, 0, 52), ZIndex = 81, Visible = false })
local introTitle = Style.Label(Style.Gui, "", 18, Config.DungeonLayout.BossBarrierColor, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.79), Size = UDim2.new(1, 0, 0, 22), ZIndex = 81, Visible = false })

local function bossIntro(info)
	local camera = Workspace.CurrentCamera
	local seconds = info.Seconds or 3
	for _, bar in ipairs(bars) do
		Style.Tween(bar, 0.35, { Size = UDim2.new(1, 0, 0.12, if bar.Name == "IntroBar1" then 80 else 0) })
	end
	introName.Text = Style.Upper(info.Name or "")
	introTitle.Text = info.Title or ""
	introName.Visible, introTitle.Visible = true, true
	introName.TextTransparency, introTitle.TextTransparency = 1, 1
	Style.Tween(introName, 0.5, { TextTransparency = 0 })
	Style.Tween(introTitle, 0.7, { TextTransparency = 0 })
	Style.PlaySound(Config.Sounds.Portal, 0.6, 0.9)
	local oldType = camera.CameraType
	local target = typeof(info.Position) == "Vector3" and info.Position
	if target then
		camera.CameraType = Enum.CameraType.Scriptable
		local from = camera.CFrame
		local goal = CFrame.lookAt(target + Vector3.new(0, 10, 34), target + Vector3.new(0, 4, 0))
		TweenService:Create(camera, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal }):Play()
		task.delay(seconds - 0.2, function()
			camera.CFrame = from
			camera.CameraType = oldType
		end)
	end
	task.delay(seconds * 0.7, function()
		Popups.Shake(0.9, 0.5)
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
		Popups.Banner("БОСС", Config.Enemies.Boss.Texts.Phase:format(tonumber(payload) or 2), {}, Config.DungeonLayout.BossBarrierColor)
		Popups.Shake(0.7, 0.4)
	end
end)

return GateHud
