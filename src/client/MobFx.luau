--[[
	MobFx.luau
	Client-side life of dungeon mobs (only visuals; the server owns
	positions, health and hits):
	- procedural animation through the Motor6D joints MobBuilder made
	  (Role attribute): idle breathing, walking (from the root velocity),
	  hovering for flying mobs, hopping for slimes,
	- attack: while the server's "Telegraph" attribute is on the mob
	  glows red and winds up, then strikes when it turns off,
	- hit recoil on every "Hits" bump,
	- death ("Dying"): the parts burst apart, spin and fade,
	- the boss health bar at the top of the screen while a boss is near.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Format = require(game:GetService("ReplicatedStorage").Shared.Format)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local lanes = Workspace:WaitForChild("Dungeon"):WaitForChild("Lanes")

local MobFx = {}

local mobs = {} -- [model] = state

-- Hitstop: the mob keeps its pose for a moment.
function MobFx.Freeze(model, seconds: number)
	local s = mobs[model]
	if s then
		s.frozenUntil = os.clock() + seconds
	end
end

local function joints(model)
	local list = {}
	for _, motor in ipairs(model:GetDescendants()) do
		if motor:IsA("Motor6D") and motor:GetAttribute("Role") then
			table.insert(list, { motor = motor, role = motor:GetAttribute("Role") })
		end
	end
	return list
end

---------------------------------------------------------------------
-- Death: break apart
---------------------------------------------------------------------

local debrisFolder = Instance.new("Folder")
debrisFolder.Name = "LocalMobDebris"
debrisFolder.Parent = Workspace

-- Metal shards and sparks flying out (one-piece models have no parts to
-- throw, so they shatter into these).
local function shards(model, center: Vector3)
	local color = model:GetAttribute("Color") or Style.Colors.Magenta
	local size = model:GetExtentsSize()
	local count = math.clamp(math.floor(size.Y * 2), 6, 16)
	for i = 1, count do
		local chunk = Instance.new("Part")
		local s = math.random() * 0.5 + 0.35
		chunk.Size = Vector3.new(s, s * (0.4 + math.random()), s)
		chunk.Color = if i % 3 == 0 then color else Color3.fromRGB(70, 72, 80)
		chunk.Material = if i % 3 == 0 then Enum.Material.Neon else Enum.Material.Metal
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		local start = CFrame.new(center + Vector3.new((math.random() - 0.5) * size.X, (math.random() - 0.3) * size.Y * 0.8, (math.random() - 0.5) * size.Z))
		chunk.CFrame = start
		chunk.Parent = debrisFolder
		local away = start.Position - center
		away = Vector3.new(away.X, 0, away.Z)
		away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(1, 0, 0)
		local velocity = away * math.random(12, 26) + Vector3.new(0, math.random(14, 26), 0)
		local spin = CFrame.Angles(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)
		local born = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - born
			if t > 1 or not chunk.Parent then
				connection:Disconnect()
				chunk:Destroy()
				return
			end
			chunk.CFrame = CFrame.new(start.Position + velocity * t + Vector3.new(0, -50 * t * t, 0)) * CFrame.identity:Lerp(spin, t)
			chunk.Transparency = math.max(0, (t - 0.6) / 0.4)
		end)
	end
	-- a flash of light where it broke
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(2, 2, 2)
	flash.CFrame = CFrame.new(center)
	flash.Color = color
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.2
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Parent = debrisFolder
	Style.Tween(flash, 0.25, { Size = Vector3.new(1, 1, 1) * math.max(5, size.Y * 1.2), Transparency = 1 })
	task.delay(0.3, function()
		flash:Destroy()
	end)
end

local function burst(model)
	if Style.HideEffects then
		return
	end
	local center = model:GetPivot().Position
	shards(model, center)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local chunk = p:Clone()
			chunk:ClearAllChildren()
			chunk.Anchored = true
			chunk.CanCollide = false
			chunk.CanQuery = false
			chunk.CanTouch = false
			chunk.Parent = debrisFolder
			p.LocalTransparencyModifier = 1
			local away = chunk.Position - center
			away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 1, 0)
			local velocity = away * math.random(10, 22) + Vector3.new(0, math.random(12, 22), 0)
			local spin = CFrame.Angles(math.random() * 6 - 3, math.random() * 6 - 3, math.random() * 6 - 3)
			local start = chunk.CFrame
			local born = os.clock()
			local base = chunk.Transparency
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local t = os.clock() - born
				if t > 0.9 or not chunk.Parent then
					connection:Disconnect()
					chunk:Destroy()
					return
				end
				local offset = velocity * t + Vector3.new(0, -45 * t * t, 0)
				chunk.CFrame = CFrame.new(start.Position + offset) * start.Rotation:Lerp(start.Rotation * spin, t)
				chunk.Transparency = base + (1 - base) * (t / 0.9)
			end)
		end
	end
end

---------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Rigged mobs (real R15 characters): AnimationTracks, cached per mob
---------------------------------------------------------------------

local CLIPS = Config.Enemies.Clips

-- the clips of one mob: the shared ones + its rig's own set
-- (Config.Enemies.ClipSets by the kind's ClipSet or Rig)
local function clipsFor(model: Model)
	local def = Config.Mobs.Defs[model:GetAttribute("Kind") or ""]
	local set = def and Config.Enemies.ClipSets[def.ClipSet or def.Rig or ""]
	if not set then
		return CLIPS
	end
	local merged = table.clone(CLIPS)
	for name, clip in pairs(set) do
		merged[name] = clip
	end
	return merged
end

local function loadTrack(state, name: string)
	local clip = state.clips[name]
	if not clip or (clip.Id or "") == "" or not state.animator then
		return nil
	end
	local cached = state.tracks[name]
	if cached ~= nil then
		return cached or nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = clip.Id
	local ok, track = pcall(state.animator.LoadAnimation, state.animator, animation)
	if not ok or not track then
		state.tracks[name] = false
		return nil
	end
	track.Looped = clip.Loop == true
	track.Priority = if name == "Idle" or name == "Walk" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
	state.tracks[name] = track
	return track
end

-- plays the working part of a clip in `seconds` (or at its own speed)
local function playClip(state, name: string, seconds: number?)
	local track = loadTrack(state, name)
	if not track then
		return nil
	end
	local clip = state.clips[name]
	local from, to = clip.From or 0, clip.To or track.Length
	local speed = if seconds then (to - from) / math.max(0.05, seconds) else 1
	track:Play(0.08, 1, speed)
	track.TimePosition = from
	return track
end

-- the parts fade out into particles of the mob color
local function dissolve(model)
	local color = model:GetAttribute("Color") or Style.Colors.Magenta
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local attachment = Instance.new("Attachment")
			attachment.Parent = p
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
			emitter.LightEmission = 0.7
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			emitter.Lifetime = NumberRange.new(0.5, 1)
			emitter.Speed = NumberRange.new(2, 6)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Acceleration = Vector3.new(0, 6, 0)
			emitter.Rate = 0
			emitter.Parent = attachment
			emitter:Emit(math.clamp(math.floor(p.Size.Magnitude * 3), 4, 18))
			local start = os.clock()
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local t = (os.clock() - start) / 0.45
				if t >= 1 or not p.Parent then
					connection:Disconnect()
					if p.Parent then
						p.LocalTransparencyModifier = 1
					end
					return
				end
				p.LocalTransparencyModifier = t
			end)
		end
	end
end

---------------------------------------------------------------------
-- Boss: rage glow (phase 2) and the slow-motion death
---------------------------------------------------------------------

local BOSS = Config.Enemies.Boss
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local function rage(model, root)
	if model:FindFirstChild("RageGlow") then
		return
	end
	local color = BOSS.Rage.Color
	local glow = Instance.new("Highlight")
	glow.Name = "RageGlow"
	glow.FillColor = color
	glow.FillTransparency = 0.75
	glow.OutlineColor = color
	glow.OutlineTransparency = 0.1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = model
	if Style.HideEffects then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RageAura"
	attachment.Parent = root
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(color, Color3.fromRGB(255, 200, 120))
	embers.LightEmission = 0.8
	local h = model:GetAttribute("Height") or 18
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, h * 0.03), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(0.6, 1.2)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, h * 0.4, 0)
	embers.Rate = 40
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	embers.Parent = attachment
	-- the roar moment: a red pulse of the whole body
	glow.FillTransparency = 0.1
	TweenService:Create(glow, TweenInfo.new(0.8), { FillTransparency = 0.75 }):Play()
end

-- The camera holds on the falling boss, the world drains of color, the
-- death clip plays slowly, then one big burst of light and particles.
local function bossDeath(model, state)
	local seconds = BOSS.DeathSlowmo
	for _, track in pairs(state.tracks or {}) do
		if track and track.IsPlaying then
			track:AdjustSpeed(0.25)
		end
	end
	local camera = Workspace.CurrentCamera
	local center = model:GetPivot().Position
	local h = model:GetAttribute("Height") or 18
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	if camera and myRoot and (myRoot.Position - center).Magnitude < 120 then
		local oldType = camera.CameraType
		local from = camera.CFrame
		local side = Vector3.new(from.Position.X - center.X, 0, from.Position.Z - center.Z)
		side = if side.Magnitude > 0.1 then side.Unit else Vector3.new(0, 0, 1)
		local eye = center + side * h * 1.6 + Vector3.new(0, h * 0.45, 0)
		camera.CameraType = Enum.CameraType.Scriptable
		TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(eye, center + Vector3.new(0, h * 0.3, 0)) }):Play()
		task.delay(0.5, function()
			TweenService:Create(camera, TweenInfo.new(seconds - 0.6, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(eye - side * h * 0.35, center + Vector3.new(0, h * 0.3, 0)) }):Play()
		end)
		task.delay(seconds, function()
			camera.CFrame = from
			camera.CameraType = oldType
		end)
	end
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "BossDeathGrade"
	grade.Parent = Lighting
	TweenService:Create(grade, TweenInfo.new(0.4), { Saturation = -0.7, Contrast = 0.15 }):Play()
	task.delay(seconds * 0.65, function()
		-- the final burst
		grade.TintColor = Color3.fromRGB(255, 245, 230)
		grade.Brightness = 0.35
		TweenService:Create(grade, TweenInfo.new(0.6), { Saturation = 0, Contrast = 0, Brightness = 0 }):Play()
		Style.PlaySound(Config.Sounds.BossDeath, 0.8, 0.9)
		if model.Parent then
			shards(model, model:GetPivot().Position)
			dissolve(model)
		end
		task.delay(0.7, function()
			grade:Destroy()
		end)
	end)
end

local function watch(model: Model)
	if mobs[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root or not model.Parent then
		return
	end
	local state = {
		root = root,
		joints = joints(model),
		phase = math.random() * 6,
		walk = 0,
		windup = 0,
		strike = 0,
		recoil = 0,
		float = model:GetAttribute("Float") == true,
		hop = model:GetAttribute("Hop") == true,
	}
	state.solid = #state.joints <= 1 -- one-piece model: only the Core moves
	-- a real rig: AnimationTracks instead of joint math
	if model:GetAttribute("Rigged") then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		state.rig = true
		state.clips = clipsFor(model)
		state.animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		state.tracks = {}
		state.joints = {}
		local idle = loadTrack(state, "Idle")
		if idle then
			idle:Play(0.3)
		end
		local walk = loadTrack(state, "Walk")
		if walk then
			walk:Play(0, 0.001, 1)
		end
	end
	mobs[model] = state

	local highlight, warning
	model:GetAttributeChangedSignal("Telegraph"):Connect(function()
		if model:GetAttribute("Telegraph") then
			state.windingUp = true
			if state.rig then
				-- wind up to the strike pose and hold there
				local clips = state.clips or CLIPS
				local name = if (model:GetAttribute("Role") == "Ranged" or model:GetAttribute("Role") == "Turret") and clips.Shoot and clips.Shoot.Id ~= "" then "Shoot" else "Attack"
				local clip = clips[name]
				local share = (clip.To - clip.From) / math.max(0.05, clip.Hit - clip.From)
				local track = playClip(state, name, Config.Enemies.WindUp * share)
				if track then
					state.attackTrack = track
					task.delay(math.max(0, (clip.Hit - clip.From) / track.Speed - 0.02), function()
						if state.windingUp and track.IsPlaying then
							track:AdjustSpeed(0)
						end
					end)
				end
			end
			if not warning and not Style.HideEffects then
				-- the red warning sign over the head: a dark diamond with a red "!"
				warning = Instance.new("BillboardGui")
				warning.Name = "Warning"
				warning.Size = UDim2.fromOffset(26, 26)
				warning.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 6) * 0.6 + 2.2, 0)
				warning.AlwaysOnTop = true
				warning.LightInfluence = 0
				warning.Adornee = root
				local diamond = Instance.new("Frame")
				diamond.AnchorPoint = Vector2.new(0.5, 0.5)
				diamond.Position = UDim2.fromScale(0.5, 0.5)
				diamond.Size = UDim2.fromScale(0.7, 0.7)
				diamond.Rotation = 45
				diamond.BackgroundColor3 = Color3.fromRGB(24, 18, 22)
				diamond.BackgroundTransparency = 0.1
				local stroke = Instance.new("UIStroke")
				stroke.Color = Style.Colors.Red
				stroke.Thickness = 2.5
				stroke.Parent = diamond
				diamond.Parent = warning
				local mark = Style.Label(warning, "!", 18, Style.Colors.Red, { Font = Style.FontTitle, Size = UDim2.fromScale(1, 1) })
				local scale = Instance.new("UIScale")
				scale.Scale = 0.4
				scale.Parent = diamond
				local markScale = Instance.new("UIScale")
				markScale.Scale = 0.4
				markScale.Parent = mark
				warning.Parent = root
				Style.Tween(scale, 0.15, { Scale = 1 })
				Style.Tween(markScale, 0.15, { Scale = 1 })
			end
			-- 23.11 owner: no red fill over the whole mob - a thin red outline
			-- only (the wind-up pose and the small "!" say the rest)
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.FillTransparency = 1
				highlight.OutlineColor = Style.Colors.Red
				highlight.OutlineTransparency = 0.35
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = model
			end
		else
			state.windingUp = false
			state.strike = 1
			if state.attackTrack and state.attackTrack.IsPlaying then
				state.attackTrack:AdjustSpeed(2.2) -- the strike itself is fast
			end
			if highlight then
				highlight:Destroy()
				highlight = nil
			end
			if warning then
				warning:Destroy()
				warning = nil
			end
		end
	end)
	model:GetAttributeChangedSignal("Hits"):Connect(function()
		state.recoil = 1
		if state.rig and not state.windingUp then
			playClip(state, "Hurt", 0.3)
		end
	end)
	-- the group noticed the player: a short "!" over the head
	model:GetAttributeChangedSignal("Awake"):Connect(function()
		if model:GetAttribute("Awake") and not Style.HideEffects then
			local tag = Instance.new("BillboardGui")
			tag.Name = "Alert"
			tag.Size = UDim2.fromOffset(40, 48)
			tag.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 6) * 0.6 + 2.5, 0)
			tag.AlwaysOnTop = true
			tag.LightInfluence = 0
			tag.Adornee = root
			local label = Style.Label(tag, Config.Sections.Texts.Alert, 40, Style.Colors.Gold, { Font = Style.FontTitle, Size = UDim2.fromScale(1, 1) })
			local scale = Instance.new("UIScale")
			scale.Scale = 0.2
			scale.Parent = label
			tag.Parent = root
			Style.Tween(scale, 0.18, { Scale = 1.15 })
			task.delay(0.9, function()
				Style.Tween(label, 0.25, { TextTransparency = 1 })
				task.delay(0.3, function()
					tag:Destroy()
				end)
			end)
		end
	end)
	model:GetAttributeChangedSignal("Rage"):Connect(function()
		if model:GetAttribute("Rage") then
			rage(model, root)
		end
	end)
	if model:GetAttribute("Rage") then
		rage(model, root)
	end
	model:GetAttributeChangedSignal("Dying"):Connect(function()
		if model:GetAttribute("Dying") then
			mobs[model] = nil
			if model:GetAttribute("Boss") then
				if state.rig then
					playClip(state, "Death", BOSS.DeathSlowmo * 0.6)
				end
				bossDeath(model, state)
				return
			end
			if state.rig then
				-- fall, then fall apart into particles
				for _, track in pairs(state.tracks) do
					if track and track ~= state.tracks.Death then
						track:Stop(0.1)
					end
				end
				playClip(state, "Death", 0.7)
				shards(model, model:GetPivot().Position)
				task.delay(if CLIPS.Death.Id ~= "" then 0.7 else 0.1, function()
					if model.Parent then
						dissolve(model)
					end
				end)
			else
				burst(model)
			end
		end
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			mobs[model] = nil
		end
	end)
end

local function consider(instance)
	if instance:IsA("Humanoid") and instance.Parent and instance.Parent:IsA("Model") then
		task.spawn(watch, instance.Parent)
	end
end
lanes.DescendantAdded:Connect(consider)
for _, instance in ipairs(lanes:GetDescendants()) do
	consider(instance)
end

---------------------------------------------------------------------
-- Animation (every frame, local Transform only)
---------------------------------------------------------------------

local function A(x, y, z)
	return CFrame.Angles(x, y or 0, z or 0)
end

RunService.Stepped:Connect(function(_, dt)
	local t = os.clock()
	for model, s in pairs(mobs) do
		if not model.Parent then
			mobs[model] = nil
			continue
		end
		if s.frozenUntil and t < s.frozenUntil then
			continue
		end
		local velocity = s.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local pace = if s.clips and s.clips.Walk then s.clips.Walk.Pace or 10 else 10
		s.walk += (math.clamp(speed / (pace * 0.5), 0, 1) - s.walk) * math.min(1, dt * 8)
		if s.rig then
			local walk = s.tracks.Walk
			if walk then
				-- the steps match the mob's own speed (Pace = studs/s at 1x)
				walk:AdjustWeight(math.max(0.001, s.walk), 0.1)
				walk:AdjustSpeed(math.clamp(speed / pace, 0.5, 1.8))
			end
			continue
		end
		s.windup += ((if s.windingUp then 1 else 0) - s.windup) * math.min(1, dt * 10)
		s.strike = math.max(0, s.strike - dt * 5)
		s.recoil = math.max(0, s.recoil - dt * 7)

		local p = t * 2 + s.phase
		local stride = math.sin(t * 9 + s.phase) * 0.7 * s.walk
		local breathe = math.sin(p) * 0.04
		local strikeArc = math.sin(s.strike * math.pi)

		for _, j in ipairs(s.joints) do
			local cf
			local role = j.role
			if role == "Core" then
				-- the whole body: wind-up = lean back and rise, strike = lunge
				-- forward and dip, hit = pushed back; a step bob while walking.
				-- One-piece models (owner / AI meshes) get it stronger.
				local k = if s.solid then 1.6 else 1
				local lift = 0
				if s.float then
					lift = math.sin(t * 2.4 + s.phase) * 0.5
				elseif s.hop then
					lift = math.abs(math.sin(t * 7 + s.phase)) * 0.6 * s.walk
				else
					lift = math.abs(math.sin(t * 9 + s.phase)) * 0.22 * s.walk * k
				end
				local squash = if s.hop then 1 else 0
				cf = CFrame.new(0, lift + breathe * (1 + squash * 4) + s.windup * 0.25 * k, (-strikeArc * 1.1 + s.recoil * 0.5) * k)
					* A((s.recoil * 0.3 + s.windup * 0.25 - strikeArc * 0.4) * k, 0, math.sin(t * 9 + s.phase) * 0.07 * s.walk * k)
			elseif role == "Head" then
				cf = A(breathe * 1.5 - s.recoil * 0.4, math.sin(p * 0.5) * 0.15, 0)
			elseif role == "ArmR" then
				cf = A(-stride + breathe - s.windup * 2.2 + strikeArc * 2.6, 0, 0)
			elseif role == "ArmL" then
				cf = A(stride - breathe - s.windup * 1.2 + strikeArc * 1.4, 0, 0)
			elseif role == "LegR" then
				cf = A(stride, 0, 0)
			elseif role == "LegL" then
				cf = A(-stride, 0, 0)
			elseif role == "Wing" then
				cf = A(0, 0, math.sin(t * 12 + s.phase) * 0.45)
			elseif role == "Tail" then
				cf = A(math.sin(t * 3 + s.phase) * 0.25, math.sin(t * 2 + s.phase) * 0.3, 0)
			end
			if cf then
				j.motor.Transform = cf
			end
		end
	end
end)

---------------------------------------------------------------------
-- Health bars never pile up: every few frames the bars on screen are
-- sorted nearest first, and a bar that would cover one already placed is
-- lifted above it (the lift is in studs, so it follows the camera).
---------------------------------------------------------------------

local camera = Workspace.CurrentCamera
local placedBars = {}
task.spawn(function()
	while true do
		task.wait(0.12)
		camera = Workspace.CurrentCamera
		local list = {}
		for model in pairs(mobs) do
			local root = model.PrimaryPart
			local gui = root and root:FindFirstChild("HealthGui")
			if gui and gui.Enabled and not model:GetAttribute("Boss") then
				local base = gui:GetAttribute("BaseOffset")
				if not base then
					base = gui.StudsOffsetWorldSpace
					gui:SetAttribute("BaseOffset", base)
				end
				local world = root.Position + base
				local screen, onScreen = camera:WorldToViewportPoint(world)
				if onScreen then
					table.insert(list, { gui = gui, base = base, root = root, screen = screen })
				else
					gui.StudsOffsetWorldSpace = base
				end
			end
		end
		table.sort(list, function(a, b)
			return a.screen.Z < b.screen.Z
		end)
		table.clear(placedBars)
		for _, entry in ipairs(list) do
			-- pixels per stud at this depth: project a point 1 stud higher
			local up = camera:WorldToViewportPoint(entry.root.Position + entry.base + Vector3.new(0, 1, 0))
			local pxPerStud = math.max(1, math.abs(entry.screen.Y - up.Y))
			local size = entry.gui.AbsoluteSize
			local w, h = math.max(30, size.X), math.max(6, size.Y + 4)
			local lift = 0
			local y = entry.screen.Y
			for _ = 1, 6 do
				local hit = false
				for _, other in ipairs(placedBars) do
					if math.abs(entry.screen.X - other.x) < (w + other.w) / 2 and math.abs(y - other.y) < (h + other.h) / 2 then
						hit = true
						y = other.y - (h + other.h) / 2 - 1
					end
				end
				if not hit then
					break
				end
			end
			lift = (entry.screen.Y - y) / pxPerStud
			entry.gui.StudsOffsetWorldSpace = entry.base + Vector3.new(0, lift, 0)
			table.insert(placedBars, { x = entry.screen.X, y = y, w = w, h = h })
		end
	end
end)

---------------------------------------------------------------------
-- Boss health bar (top of the screen)
---------------------------------------------------------------------

local bar = Style.Plate(Style.Gui, {
	Name = "BossBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150), -- under the wave panel
	Size = UDim2.fromOffset(520, 64),
	ZIndex = 6,
})
bar.Visible = false
local bossName = Style.Label(bar, "", 22, Style.Colors.Gold, { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 24), ZIndex = 7 })
local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(12, 32)
track.Size = UDim2.new(1, -24, 0, 22)
track.BackgroundColor3 = Style.Colors.CardDark
track.BorderSizePixel = 0
track.ZIndex = 7
track.Parent = bar
Style.Corner(track, UDim.new(0.5, 0))
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Style.Colors.Red
fill.BorderSizePixel = 0
fill.ZIndex = 8
fill.Parent = track
Style.Corner(fill, UDim.new(0.5, 0))
local hpText = Style.Label(track, "", 16, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 9 })

task.spawn(function()
	while true do
		task.wait(0.1)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local boss, best = nil, 90
		if root and player:GetAttribute("Zone") == "Dungeon" then
			for model in pairs(mobs) do
				if model:GetAttribute("Boss") and model.Parent and not model:GetAttribute("Intro") then
					local distance = (model:GetPivot().Position - root.Position).Magnitude
					if distance < best then
						boss, best = model, distance
					end
				end
			end
		end
		local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
		bar.Visible = humanoid ~= nil
		if humanoid then
			local phase = boss:GetAttribute("Phase") or 1
			bossName.Text = Style.Upper(boss:GetAttribute("MobName") or boss.Name) .. "   " .. string.rep("◆", phase) .. string.rep("◇", #Config.Enemies.Boss.Phases + 1 - phase)
			local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
			Style.Tween(fill, 0.1, { Size = UDim2.fromScale(ratio, 1) })
			hpText.Text = Format.Number(humanoid.Health) .. " / " .. Format.Number(humanoid.MaxHealth)
		end
	end
end)

return MobFx
