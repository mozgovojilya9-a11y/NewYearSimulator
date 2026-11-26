--[[
	LevelUp.luau
	The level-up moment (Config.LevelUpFx):
	  * on ANY character whose "LevelUpFx" attribute bumps (server sets it):
	    a pillar of light and a ring of gold particles — everyone sees it;
	  * for the local player (LevelUp remote: level, skill points gained,
	    previous level): a flash, a short camera zoom, the sound
	    Config.Assets.Sounds.LevelUp and the window
	    the golden "[ СИСТЕМА ] УРОВЕНЬ ПОВЫШЕН" notification of sheet 02
	    (old -> new level, stat and skill points); no dim, no buttons, it
	    fades by itself. Several level-ups in a row become one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.Popups)
local Style = require(script.Parent.Style)
local Icons = require(script.Parent.Icons)

local FX = Config.LevelUpFx
local T = FX.Texts
local C = Style.Colors
local player = Players.LocalPlayer

local LevelUp = {}
LevelUp.OnSpend = nil -- set by the HUD: opens the Статус window

---------------------------------------------------------------------
-- The light on a character (everyone)
---------------------------------------------------------------------

local folder = Instance.new("Folder")
folder.Name = "LevelUpFx"
folder.Parent = Workspace

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = folder
	return p
end

local function pillar(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or Style.HideEffects then
		return
	end
	local base = root.Position - Vector3.new(0, 3, 0)
	local beam = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(60, 1, 1), CFrame = CFrame.new(base + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = FX.PillarColor, Transparency = 0.2 })
	local core = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(60, 0.4, 0.4), CFrame = beam.CFrame, Color = Color3.new(1, 1, 1), Transparency = 0.1 })
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2), CFrame = CFrame.new(base + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = FX.RingColor, Transparency = 0.1 })
	local light = Instance.new("PointLight")
	light.Color = FX.PillarColor
	light.Range = 22
	light.Brightness = 4
	light.Parent = core
	local info = TweenInfo.new(FX.PillarSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(beam, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = Vector3.new(60, 6, 6) }):Play()
	task.delay(0.25, function()
		TweenService:Create(beam, info, { Size = Vector3.new(60, 0.2, 0.2), Transparency = 1 }):Play()
		TweenService:Create(core, info, { Transparency = 1 }):Play()
		TweenService:Create(light, info, { Brightness = 0 }):Play()
	end)
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 22, 22), Transparency = 1 }):Play()
	-- a ring of gold particles rising around the character
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(FX.RingColor, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(15, 180)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Shape = Enum.ParticleEmitterShape.Cylinder
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(60)
	task.delay(FX.PillarSeconds + 0.5, function()
		beam:Destroy()
		core:Destroy()
		ring:Destroy()
		attachment:Destroy()
	end)
end

local function watch(character)
	character:GetAttributeChangedSignal("LevelUpFx"):Connect(function()
		pillar(character)
	end)
end
local function watchPlayer(other)
	if other.Character then
		watch(other.Character)
	end
	other.CharacterAdded:Connect(watch)
end
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)

---------------------------------------------------------------------
-- The notification (sheet 02): golden wings, "[ СИСТЕМА ]",
-- "УРОВЕНЬ ПОВЫШЕН", "Ур. 7  »  Ур. 8", the points gained. No dim, no
-- buttons: it fades by itself after FX.BannerSeconds or on a tap.
---------------------------------------------------------------------

local W = 520
local banner = Instance.new("TextButton")
banner.Name = "LevelUpWindow"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.36)
banner.Size = UDim2.fromOffset(W, 300)
banner.BackgroundTransparency = 1
banner.Text = ""
banner.AutoButtonColor = false
banner.ZIndex = 90
banner.Visible = false
banner.Parent = Style.Gui
local fit = Instance.new("UIScale")
fit.Parent = banner
local panel = Style.Panel(banner, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Fill = Color3.fromRGB(14, 12, 10), Transparency = 0.08, Border = C.Gold, Cut = 14, ZIndex = 91 })
-- golden wings and a diamond over the panel
local crest = Instance.new("Frame")
crest.AnchorPoint = Vector2.new(0.5, 0)
crest.Position = UDim2.fromScale(0.5, 0)
crest.Size = UDim2.fromOffset(300, 70)
crest.BackgroundTransparency = 1
crest.ZIndex = 93
crest.Parent = banner
local function bar(x: number, y: number, w: number, rot: number)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, x, 0, y)
	f.Size = UDim2.fromOffset(w, 6)
	f.Rotation = rot
	f.BackgroundColor3 = C.Gold
	f.BorderSizePixel = 0
	f.ZIndex = 94
	f.Parent = crest
	return f
end
for _, side in ipairs({ -1, 1 }) do
	for k = 0, 3 do
		bar(side * (52 + k * 14), 38 + k * 7, 90 - k * 16, side * (-18 + k * 4))
	end
end
local diamond = Instance.new("Frame")
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.new(0.5, 0, 0, 36)
diamond.Size = UDim2.fromOffset(34, 34)
diamond.Rotation = 45
diamond.BackgroundColor3 = C.Gold
diamond.BorderSizePixel = 0
diamond.ZIndex = 95
diamond.Parent = crest
local system = Style.Label(panel, T.System, 15, Config.Theme.Cyan, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 18), ZIndex = 92 })
local title = Style.Label(panel, T.Title, 40, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 44), ZIndex = 92 })
local levels = Style.Label(panel, "", 26, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 30), ZIndex = 92 })
Style.Rule(panel, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.new(1, -80, 0, 1), Color = C.GoldDim, ZIndex = 92 })
-- sheet 02: the gains in a column, each with a gold icon
local gainRows = {}
local LABELS = { system, title, levels }
for i = 1, 4 do
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 140 + (i - 1) * 26)
	row.Size = UDim2.fromOffset(260, 24)
	row.BackgroundTransparency = 1
	row.ZIndex = 92
	row.Parent = panel
	local icon = Icons.Make(row, "star", 18, C.Gold, 93)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 0, 0.5, 0)
	local label = Style.Label(row, "", 16, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 93 })
	gainRows[i] = { row = row, icon = icon, label = label }
	table.insert(LABELS, label)
end
local titleScale = Instance.new("UIScale")
titleScale.Parent = title
local shownAt = 0

local function setFade(t: number, seconds: number)
	for _, label in ipairs(LABELS) do
		Style.Tween(label, seconds, { TextTransparency = t })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Style.Tween(stroke, seconds, { Transparency = t })
		end
	end
end

local function hide()
	shownAt = 0
	banner.Visible = false
end
banner.Activated:Connect(hide)

local function show(from: number, to: number, skillPoints: number)
	levels.Text = T.Levels:format(from, to)
	local lines = { { "chevron", T.Stats:format((to - from) * Config.Attributes.PointsPerLevel) } }
	if skillPoints > 0 then
		table.insert(lines, { "skills", T.Skills:format(skillPoints) })
	end
	table.insert(lines, { "heart", T.Health:format(Config.Stats.HealthPerLevel * (to - from)) })
	local damage = (Config.LevelMult(to) / Config.LevelMult(from) - 1) * 100
	table.insert(lines, { "sword", T.Damage:format(tostring(math.floor(damage * 10 + 0.5) / 10)) })
	for i, ui in ipairs(gainRows) do
		local line = lines[i]
		ui.row.Visible = line ~= nil
		if line then
			Icons.Set(ui.icon, line[1], C.Gold)
			ui.label.Text = line[2]
		end
	end
	local camera = Workspace.CurrentCamera
	fit.Scale = math.min(1, (camera.ViewportSize.X - 24) / W)
	banner.Visible = true
	setFade(0, 0)
	banner.Position = UDim2.fromScale(0.5, 0.4)
	Style.Tween(banner, 0.35, { Position = UDim2.fromScale(0.5, 0.36) }, Enum.EasingStyle.Back)
	titleScale.Scale = 1.4
	Style.Tween(titleScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	local stamp = os.clock()
	shownAt = stamp
	task.delay(FX.BannerSeconds or 3.5, function()
		if shownAt ~= stamp then
			return
		end
		setFade(1, 0.5)
		task.delay(0.55, function()
			if shownAt == stamp then
				hide()
			end
		end)
	end)
end

-- the camera leans in and back
local function zoom()
	local camera = Workspace.CurrentCamera
	local fov = camera.FieldOfView
	local half = FX.ZoomSeconds / 2
	TweenService:Create(camera, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = fov - FX.ZoomFov }):Play()
	task.delay(half, function()
		TweenService:Create(camera, TweenInfo.new(half * 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { FieldOfView = fov }):Play()
	end)
end

-- level-ups that arrive close together become one window
local pending = nil
ReplicatedStorage:WaitForChild("LevelUp").OnClientEvent:Connect(function(level, points, previous)
	level = tonumber(level) or 1
	points = tonumber(points) or 1
	previous = tonumber(previous) or (level - 1)
	if pending then
		pending.to = level
		pending.points += points
		return
	end
	pending = { from = previous, to = level, points = points }
	Popups.Flash(Config.Theme.Cyan)
	local id = Config.Assets.Sounds and Config.Assets.Sounds.LevelUp or ""
	if id ~= "" then
		Style.PlaySound(id, 1.1, 0.7)
	end
	zoom()
	task.delay(FX.Gather, function()
		local p = pending
		pending = nil
		if p then
			show(p.from, p.to, p.points)
		end
	end)
end)

LevelUp.Show = show -- (for tests)
return LevelUp
