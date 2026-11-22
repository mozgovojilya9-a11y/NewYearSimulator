--[[
	LevelUp.luau
	The level-up moment (Config.LevelUpFx):
	  * on ANY character whose "LevelUpFx" attribute bumps (server sets it):
	    a pillar of light and a ring of gold particles — everyone sees it;
	  * for the local player (LevelUp remote: level, skill points gained,
	    previous level): a flash, a short camera zoom, the sound
	    Config.Assets.Sounds.LevelUp and the window
	    a short banner "УРОВЕНЬ / 8 / +1 очко навыков" that fades by
	    itself (no window, no buttons; stats are spent automatically).
	    Several level-ups in a row become one banner.
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
-- The banner (22.11: no window, no buttons - it never stops the game)
---------------------------------------------------------------------

local banner = Instance.new("Frame")
banner.Name = "LevelUpWindow"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.3)
banner.Size = UDim2.fromOffset(420, 120)
banner.BackgroundTransparency = 1
banner.ZIndex = 90
banner.Visible = false
banner.Parent = Style.Gui
local small = Style.Label(banner, T.Title, 18, Config.Theme.Cyan, { Font = Style.FontTitle, Size = UDim2.new(1, 0, 0, 22), ZIndex = 91 })
local big = Style.Label(banner, "", 64, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 70), ZIndex = 91 })
local extra = Style.Label(banner, "", 15, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 20), ZIndex = 91 })
local bigScale = Instance.new("UIScale")
bigScale.Parent = big
local shownAt = 0

local function show(_from: number, to: number, skillPoints: number)
	small.Text = T.Title
	big.Text = tostring(to)
	extra.Text = if skillPoints > 0 then T.Skills:format(skillPoints) else ""
	for _, label in ipairs({ small, big, extra }) do
		label.TextTransparency = 0
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
	banner.Visible = true
	bigScale.Scale = 1.8
	Style.Tween(bigScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local stamp = os.clock()
	shownAt = stamp
	task.delay(FX.BannerSeconds or 1.8, function()
		if shownAt ~= stamp then
			return
		end
		for _, label in ipairs({ small, big, extra }) do
			Style.Tween(label, 0.4, { TextTransparency = 1 })
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				Style.Tween(stroke, 0.4, { Transparency = 1 })
			end
		end
		task.delay(0.45, function()
			if shownAt == stamp then
				banner.Visible = false
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
