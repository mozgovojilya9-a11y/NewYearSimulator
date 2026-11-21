--[[
	LevelUp.luau
	The level-up moment (Config.LevelUpFx):
	  * on ANY character whose "LevelUpFx" attribute bumps (server sets it):
	    a pillar of light and a ring of gold particles — everyone sees it;
	  * for the local player (LevelUp remote: level, skill points gained,
	    previous level): a flash, a short camera zoom, the sound
	    Config.Assets.Sounds.LevelUp and the window
	    "[СИСТЕМА] УРОВЕНЬ ПОВЫШЕН" in the Solo Leveling style: old → new
	    level, stat and skill points, what opened (skill tree nodes of the
	    class, gate ranks, a new title), "Распределить" (opens Статус) and
	    "Позже". Several level-ups in a row become one window.
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
-- The window
---------------------------------------------------------------------

local dim = Instance.new("TextButton")
dim.Name = "LevelUpWindow"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = 90
dim.Visible = false
dim.Parent = Style.Gui

local panel = Style.Panel(dim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 420), Fill = Color3.fromRGB(8, 12, 20), Transparency = 0.06, Border = Config.Theme.Cyan, Cut = 14, ZIndex = 91 })
local fit = Instance.new("UIScale")
fit.Parent = panel
-- thin cyan lines top and bottom
Style.Rule(panel, { Position = UDim2.fromOffset(24, 54), Size = UDim2.new(1, -48, 0, 1), Color = Config.Theme.Cyan, ZIndex = 92 })
local bottomRule = Style.Rule(panel, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -84), Size = UDim2.new(1, -48, 0, 1), Color = Config.Theme.Cyan, ZIndex = 92 })
local _ = bottomRule
Style.Label(panel, T.System, 14, Config.Theme.Cyan, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 16), ZIndex = 92 })
local title = Style.Label(panel, T.Title, 30, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 30), ZIndex = 92 })
local levels = Style.Label(panel, "", 46, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 52), ZIndex = 92 })
local levelScale = Instance.new("UIScale")
levelScale.Parent = levels
local stats = Style.Label(panel, "", 17, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 0, 22), ZIndex = 92 })
local skills = Style.Label(panel, "", 17, Config.Theme.Cyan, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 22), ZIndex = 92 })
local stronger = Style.Label(panel, "", 13, C.Muted, { Position = UDim2.fromOffset(0, 172), Size = UDim2.new(1, 0, 0, 18), ZIndex = 92 })
Style.Label(panel, T.Opened, 13, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(32, 200), Size = UDim2.new(1, -64, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 92 })
local opened = Style.Label(panel, "", 14, C.Text, { Position = UDim2.fromOffset(32, 220), Size = UDim2.new(1, -64, 0, 104), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 92 })
local spend = Style.Button(panel, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -20), Size = UDim2.new(0.5, -30, 0, 50), Color = C.Gold, Text = T.Spend, TextSize = 18, ZIndex = 93 })
local later = Style.Button(panel, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -20), Size = UDim2.new(0.5, -30, 0, 50), Color = C.CardDark, Text = T.Later, TextSize = 18, ZIndex = 93 })

local function close()
	dim.Visible = false
end
later.Activated:Connect(close)
spend.Activated:Connect(function()
	close()
	if LevelUp.OnSpend then
		LevelUp.OnSpend()
	end
end)

-- What opened between two levels (old, new].
local function openedBetween(from: number, to: number): { string }
	local list = {}
	local class = player:GetAttribute("Class") or ""
	local nodes = {}
	for _, node in pairs(Config.SkillById) do
		if node.Class == class and node.Level and node.Level > from and node.Level <= to then
			table.insert(nodes, node)
		end
	end
	table.sort(nodes, function(a, b)
		return a.Level < b.Level
	end)
	local branchNames = {}
	for _, b in ipairs(Config.Skills.Branches) do
		branchNames[b.Id] = b.Name
	end
	if #nodes <= 3 then
		for _, node in ipairs(nodes) do
			table.insert(list, T.Node:format(node.Name, branchNames[node.Branch] or ""))
		end
	else
		table.insert(list, T.Nodes:format(#nodes))
	end
	for _, rank in ipairs(Config.Gates.Ranks) do
		local info = Config.Gates.RankInfo[rank]
		if info and info.Level > from and info.Level <= to then
			table.insert(list, T.Gate:format(rank))
		end
	end
	for _, r in ipairs(Config.Ranks) do
		if r.Level > from and r.Level <= to then
			table.insert(list, T.Rank:format(r.Name))
		end
	end
	return list
end

local function show(from: number, to: number, skillPoints: number)
	levels.Text = T.Levels:format(from, to)
	stats.Text = T.Stats:format((to - from) * Config.Attributes.PointsPerLevel)
	skills.Text = T.Skills:format(skillPoints)
	stronger.Text = T.Stronger:format(Format.Number(player:GetAttribute("ClickPower") or 1), Format.Number(player:GetAttribute("MaxHealth") or Config.Player.Health))
	local list = openedBetween(from, to)
	opened.Text = if #list > 0 then "•  " .. table.concat(list, "\n•  ") else "—"
	-- the panel is as tall as its lines
	panel.Size = UDim2.fromOffset(520, 236 + math.max(1, #list) * 20 + 100)
	local camera = Workspace.CurrentCamera
	fit.Scale = math.min(1, (camera.ViewportSize.X - 24) / 520, (camera.ViewportSize.Y - 24) / 420)
	dim.Visible = true
	panel.Position = UDim2.new(0.5, 0, 0.5, 30)
	Style.Tween(panel, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
	levelScale.Scale = 1.6
	Style.Tween(levelScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	title.TextTransparency = 1
	Style.Tween(title, 0.4, { TextTransparency = 0 })
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
