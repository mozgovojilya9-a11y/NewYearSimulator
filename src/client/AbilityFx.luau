--[[
	AbilityFx.luau
	Visual effects of class attacks and abilities, drawn locally from the
	server's Ability:FireAllClients("Fx", kind, ...):
	  Ring   (center, radius, color)          expanding ground ring
	  Beam   (from, to, color, width)         plasma bolt / energy line
	  Area   (center, radius, seconds, color) disc on the ground (trap, strike)
	  Shield (character, seconds, color)      bubble around the player
	  Aura   (character, seconds, color)      glow of a buff (rage, haste)
	  Heal   (character)                      green burst
	  Stun   (model, seconds)                 spinning ring over a mob
	  Dash   (character, seconds)             speed streak
	  Bolt   (from, to, color, speed, size)   enemy projectile in flight
	Everything is non-colliding, anchored and removed after its time.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Style = require(script.Parent.ui.Style)

local remote = ReplicatedStorage:WaitForChild("Ability")

local AbilityFx = {}

local folder = Instance.new("Folder")
folder.Name = "AbilityFx"
folder.Parent = Workspace

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for key, value in pairs(props) do
		p[key] = value
	end
	p.Parent = folder
	return p
end

local function tween(instance, seconds, props)
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function groundY(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local result = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -20, 0), params)
	return if result then result.Position.Y else position.Y - 3
end

local handlers = {}

-- A burst of particles at a point (dust / sparks), removed after it.
local function burst(position: Vector3, color: Color3, count: number, speed: number, size: number, lifetime: number, up: boolean?)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 1.8) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = if up then Vector2.new(25, 25) else Vector2.new(180, 8)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(attachment, lifetime + 0.2)
end

-- Shockwave on the ground: a bright edge that runs out to the radius, a
-- filled disc that fades, a dust ring and a short flash of light.
function handlers.Ring(center: Vector3, radius: number, color: Color3)
	local y = groundY(center) + 0.15
	local flat = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	local edge = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2, 2), CFrame = flat, Color = color, Transparency = 0.05 })
	local fill = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 2, 2), CFrame = flat * CFrame.new(0.02, 0, 0), Color = color, Transparency = 0.45, Material = Enum.Material.SmoothPlastic })
	tween(edge, 0.3, { Size = Vector3.new(0.25, radius * 2, radius * 2), Transparency = 1 })
	tween(fill, 0.45, { Size = Vector3.new(0.12, radius * 2, radius * 2), Transparency = 1 })
	Debris:AddItem(edge, 0.35)
	Debris:AddItem(fill, 0.5)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 1.6
	light.Brightness = 3
	light.Parent = fill
	tween(light, 0.4, { Brightness = 0 })
	burst(Vector3.new(center.X, y + 0.5, center.Z), Color3.fromRGB(150, 145, 140), math.clamp(math.floor(radius * 2), 10, 36), radius * 2.2, 1.2, 0.7)
	if radius >= 8 then
		Style.PlaySound("Explosion", 1.1, 0.35)
	end
end

-- Plasma bolt / energy line: a hot core inside a wide glow, an impact
-- flash and sparks where it lands.
function handlers.Beam(from: Vector3, to: Vector3, color: Color3, width: number?)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local w = width or 0.4
	local cf = CFrame.lookAt((from + to) / 2, to)
	local glow = part({ Size = Vector3.new(w * 2.2, w * 2.2, length), CFrame = cf, Color = color, Transparency = 0.55 })
	local core = part({ Size = Vector3.new(w * 0.7, w * 0.7, length), CFrame = cf, Color = Color3.new(1, 1, 1), Transparency = 0.05 })
	tween(glow, 0.22, { Size = Vector3.new(w * 0.3, w * 0.3, length), Transparency = 1 })
	tween(core, 0.16, { Size = Vector3.new(w * 0.1, w * 0.1, length), Transparency = 1 })
	Debris:AddItem(glow, 0.25)
	Debris:AddItem(core, 0.2)
	local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(w * 4, w * 4, w * 4), CFrame = CFrame.new(to), Color = color, Transparency = 0.2 })
	tween(flash, 0.25, { Size = Vector3.new(w * 9, w * 9, w * 9), Transparency = 1 })
	Debris:AddItem(flash, 0.3)
	burst(to, color, math.clamp(math.floor(w * 25), 6, 24), 18, 0.25, 0.35)
end

-- Enemy projectile: a glowing plasma ball with a trail flying from -> to
-- at `speed` studs/s (the server hits at the same arrival time), a flash
-- and sparks where it lands (a wall stops it: the server clips `to`).
function handlers.Bolt(from: Vector3, to: Vector3, color: Color3, speed: number, size: number?)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local s = size or 0.9
	local seconds = distance / math.max(1, speed)
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), CFrame = CFrame.new(from), Color = Color3.new(1, 1, 1) })
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(s * 2, s * 2, s * 2), CFrame = CFrame.new(from), Color = color, Transparency = 0.6 })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, s * 0.4, 0)
	a0.Parent = glow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -s * 0.4, 0)
	a1.Parent = glow
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 0.8
	trail.Lifetime = 0.18
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.FaceCamera = true
	trail.Parent = glow
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = glow
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min(1, (os.clock() - start) / seconds)
		local cf = CFrame.new(from:Lerp(to, t))
		ball.CFrame = cf
		glow.CFrame = cf
		if t >= 1 then
			connection:Disconnect()
			ball:Destroy()
			glow:Destroy()
			local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(s * 2, s * 2, s * 2), CFrame = CFrame.new(to), Color = color, Transparency = 0.2 })
			tween(flash, 0.25, { Size = Vector3.new(s * 6, s * 6, s * 6), Transparency = 1 })
			Debris:AddItem(flash, 0.3)
			burst(to, color, 10, 16, 0.25, 0.35)
		end
	end)
	-- muzzle flash
	local muzzle = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.5, s * 1.5, s * 1.5), CFrame = CFrame.new(from), Color = color, Transparency = 0.3 })
	tween(muzzle, 0.15, { Size = Vector3.new(s * 3, s * 3, s * 3), Transparency = 1 })
	Debris:AddItem(muzzle, 0.2)
end

-- A heavy landing (the boss entrance): a shock ring, a cloud of grey dust
-- rolling outwards and debris sparks.
function handlers.Impact(center: Vector3, radius: number, color: Color3)
	local y = groundY(center)
	handlers.Ring(Vector3.new(center.X, y, center.Z), radius, color)
	local holder = part({ Size = Vector3.new(radius, 0.2, radius), CFrame = CFrame.new(center.X, y + 0.5, center.Z), Transparency = 1 })
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(120, 118, 115), Color3.fromRGB(70, 68, 66))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1.2, 2)
	dust.Speed = NumberRange.new(radius * 0.8, radius * 1.4)
	dust.SpreadAngle = Vector2.new(5, 180)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Drag = 3
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Rate = 0
	dust.LightInfluence = 1
	dust.Parent = holder
	dust:Emit(60)
	burst(Vector3.new(center.X, y + 1, center.Z), color, 30, 30, 0.35, 0.6, true)
	Style.PlaySound("BossLand", 0.6, 0.9)
	Style.PlaySound("BossRoar", 1, 0.8)
	Debris:AddItem(holder, 2.2)
end

-- Boss ground wave: a low wall of energy running out from `center` along
-- the floor at `speed` up to `radius` (players jump over it).
function handlers.Wave(center: Vector3, radius: number, speed: number, color: Color3)
	local y = groundY(center)
	local count = 40
	local segments = {}
	for i = 1, count do
		segments[i] = part({ Size = Vector3.new(1, 1.6, 0.35), Color = color, Transparency = 0.25 })
	end
	local dust = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2, 2), CFrame = CFrame.new(center.X, y + 0.05, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.6 })
	local start = os.clock()
	local seconds = radius / math.max(1, speed)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - start) / seconds
		if t >= 1 then
			connection:Disconnect()
			for _, p in ipairs(segments) do
				p:Destroy()
			end
			dust:Destroy()
			return
		end
		local r = math.max(0.5, t * radius)
		local width = 2 * math.pi * r / count + 0.15
		for i, p in ipairs(segments) do
			local a = (i / count) * math.pi * 2
			local at = Vector3.new(center.X + math.cos(a) * r, y + 0.8, center.Z + math.sin(a) * r)
			p.Size = Vector3.new(width, 1.6 * (1 - t * 0.4), 0.35)
			p.CFrame = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
			p.Transparency = 0.25 + t * 0.6
		end
		dust.Size = Vector3.new(0.1, r * 2, r * 2)
		dust.Transparency = 0.6 + t * 0.4
	end)
	Style.PlaySound("Explosion", 0.7, 0.4)
end

function handlers.Area(center: Vector3, radius: number, seconds: number, color: Color3)
	local y = groundY(center) + 0.1
	local disc = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.65,
	})
	local edge = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, radius * 2 + 0.6, radius * 2 + 0.6),
		CFrame = disc.CFrame * CFrame.new(-0.02, 0, 0),
		Color = color,
		Transparency = 0.35,
	})
	task.delay(seconds, function()
		tween(disc, 0.25, { Transparency = 1 })
		tween(edge, 0.25, { Transparency = 1 })
	end)
	Debris:AddItem(disc, seconds + 0.3)
	Debris:AddItem(edge, seconds + 0.3)
end

local function rootOf(character): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function follow(p: BasePart, character, seconds: number, offset: Vector3?)
	local connection
	local ends = os.clock() + seconds
	connection = RunService.RenderStepped:Connect(function()
		local root = rootOf(character)
		if not root or os.clock() > ends or not p.Parent then
			connection:Disconnect()
			return
		end
		p.CFrame = CFrame.new(root.Position + (offset or Vector3.zero))
	end)
end

function handlers.Shield(character, seconds: number, color: Color3)
	local root = rootOf(character)
	if not root then
		return
	end
	local bubble = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), CFrame = root.CFrame, Color = color, Material = Enum.Material.ForceField, Transparency = 0.2 })
	follow(bubble, character, seconds)
	task.delay(seconds, function()
		tween(bubble, 0.2, { Transparency = 1 })
	end)
	Debris:AddItem(bubble, seconds + 0.3)
end

function handlers.Aura(character, seconds: number, color: Color3)
	local root = rootOf(character)
	if not root then
		return
	end
	local glow = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 5, 5), CFrame = root.CFrame, Color = color, Transparency = 0.4 })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = glow
	local connection
	local ends = os.clock() + seconds
	connection = RunService.RenderStepped:Connect(function()
		local r = rootOf(character)
		if not r or os.clock() > ends or not glow.Parent then
			connection:Disconnect()
			return
		end
		glow.CFrame = CFrame.new(r.Position.X, groundY(r.Position) + 0.15, r.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	end)
	Debris:AddItem(glow, seconds)
end

function handlers.Heal(character)
	local root = rootOf(character)
	if root then
		handlers.Ring(root.Position, 6, Color3.fromRGB(90, 230, 110))
		local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = root.CFrame, Color = Color3.fromRGB(90, 230, 110), Transparency = 0.3 })
		tween(glow, 0.5, { Size = Vector3.new(9, 9, 9), Transparency = 1 })
		Debris:AddItem(glow, 0.55)
	end
end

function handlers.Stun(model, seconds: number)
	if not model or not model.Parent then
		return
	end
	local size = model:GetExtentsSize()
	local ring = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 2.4, 2.4),
		Color = Style.Colors.Gold,
		Transparency = 0.2,
	})
	local ends = os.clock() + seconds
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not model.Parent or os.clock() > ends then
			connection:Disconnect()
			ring:Destroy()
			return
		end
		ring.CFrame = CFrame.new(model:GetPivot().Position + Vector3.new(0, size.Y / 2 + 1, 0)) * CFrame.Angles(0, os.clock() * 6, math.rad(90))
	end)
end

function handlers.Dash(character, seconds: number)
	local root = rootOf(character)
	if not root then
		return
	end
	local attachment0 = Instance.new("Attachment")
	attachment0.Position = Vector3.new(0, 1, 0)
	attachment0.Parent = root
	local attachment1 = Instance.new("Attachment")
	attachment1.Position = Vector3.new(0, -1, 0)
	attachment1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(Style.Colors.Cyan)
	trail.LightEmission = 0.6
	trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = root
	task.delay(seconds + 0.3, function()
		trail:Destroy()
		attachment0:Destroy()
		attachment1:Destroy()
	end)
end

---------------------------------------------------------------------
-- Weapon attacks and abilities of the classes (27.11): the shot leaves
-- the gun's muzzle, the spear stabs from its tip, every ability has its
-- own shape. Colors come from the weapon's rarity (server).
---------------------------------------------------------------------

-- The muzzle / tip of the weapon in a character's hand: the far end of
-- the weapon model along the character's facing (else the chest).
local function muzzleOf(character): (Vector3, Vector3)
	local root = rootOf(character)
	local look = if root then root.CFrame.LookVector else Vector3.zAxis
	local weapon = character and character:FindFirstChild("EquippedWeapon")
	if weapon and weapon:IsA("Model") then
		local best, bestDot
		for _, p in ipairs(weapon:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local corner = (p.CFrame * CFrame.new(p.Size.X / 2 * sx, p.Size.Y / 2 * sy, p.Size.Z / 2 * sz)).Position
							local d = corner:Dot(look)
							if not bestDot or d > bestDot then
								best, bestDot = corner, d
							end
						end
					end
				end
			end
		end
		if best then
			return best, look
		end
	end
	local pos = if root then root.Position + Vector3.new(0, 1, 0) + look * 1.5 else Vector3.zero
	return pos, look
end

-- a four-point star flash (two crossed thin plates) facing `look`
local function starFlash(at: Vector3, look: Vector3, color: Color3, size: number)
	local cf = CFrame.lookAt(at, at + look)
	local pieces = {}
	for _, angle in ipairs({ 0, 90, 45, 135 }) do
		local long = if angle % 90 == 0 then size * 1.8 else size
		local plate = part({ Size = Vector3.new(0.08, long, 0.08), CFrame = cf * CFrame.Angles(0, 0, math.rad(angle)), Color = color:Lerp(Color3.new(1, 1, 1), 0.4), Transparency = 0.05 })
		table.insert(pieces, plate)
		tween(plate, 0.12, { Size = Vector3.new(0.02, long * 1.6, 0.02), Transparency = 1 })
		Debris:AddItem(plate, 0.15)
	end
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = CFrame.new(at), Color = color, Transparency = 0.15 })
	tween(ball, 0.12, { Size = Vector3.new(size * 1.8, size * 1.8, size * 1.8), Transparency = 1 })
	Debris:AddItem(ball, 0.15)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 10
	light.Brightness = 3
	light.Parent = ball
end

-- a fast tracer: a bright streak that flies from -> to and sparks on arrival
local function tracer(from: Vector3, to: Vector3, color: Color3, width: number, speed: number, onHit)
	local distance = (to - from).Magnitude
	if distance < 0.2 then
		return
	end
	local dir = (to - from).Unit
	local length = math.min(distance, 3 + width * 6)
	local core = part({ Size = Vector3.new(width * 0.45, width * 0.45, length), Color = Color3.new(1, 1, 1) })
	local glow = part({ Size = Vector3.new(width * 1.4, width * 1.4, length * 1.15), Color = color, Transparency = 0.45 })
	local seconds = distance / speed
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min(1, (os.clock() - start) / math.max(0.01, seconds))
		local head = from:Lerp(to, t)
		local cf = CFrame.lookAt(head - dir * length / 2, head)
		core.CFrame = cf
		glow.CFrame = cf
		if t >= 1 then
			connection:Disconnect()
			core:Destroy()
			glow:Destroy()
			local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(width * 2, width * 2, width * 2), CFrame = CFrame.new(to), Color = color, Transparency = 0.1 })
			tween(flash, 0.2, { Size = Vector3.new(width * 6, width * 6, width * 6), Transparency = 1 })
			Debris:AddItem(flash, 0.25)
			burst(to, color, math.clamp(math.floor(width * 20), 6, 26), 22, 0.18, 0.3)
			if onHit then
				onHit()
			end
		end
	end)
end

-- Стрелок: the shot from the muzzle. charged = bigger, a shock ring at
-- the muzzle and a stronger hit.
function handlers.Shot(character, to: Vector3, color: Color3, charged: boolean?)
	local from, look = muzzleOf(character)
	local w = if charged then 0.75 else 0.32
	starFlash(from, look, color, if charged then 1.4 else 0.7)
	if charged then
		local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1, 1), CFrame = CFrame.lookAt(from, from + look) * CFrame.Angles(0, math.rad(90), 0), Color = color, Transparency = 0.1 })
		tween(ring, 0.3, { Size = Vector3.new(0.05, 6, 6), Transparency = 1 })
		Debris:AddItem(ring, 0.35)
	end
	tracer(from, to, color, w, if charged then 160 else 240, function()
		if charged then
			handlers.Ring(to, 6, color)
		end
	end)
end

-- Импульс: a straight energy stab from the spear tip.
function handlers.Thrust(character, length: number, color: Color3)
	local from, look = muzzleOf(character)
	local to = from + look * length
	local cf = CFrame.lookAt((from + to) / 2, to)
	local core = part({ Size = Vector3.new(0.18, 0.18, 0.5), CFrame = CFrame.lookAt(from, to), Color = Color3.new(1, 1, 1) })
	local glow = part({ Size = Vector3.new(0.7, 0.7, length), CFrame = cf, Color = color, Transparency = 0.5 })
	tween(core, 0.1, { Size = Vector3.new(0.18, 0.18, length), CFrame = cf })
	tween(glow, 0.25, { Size = Vector3.new(0.1, 0.1, length * 1.1), Transparency = 1 })
	Debris:AddItem(core, 0.3)
	Debris:AddItem(glow, 0.3)
	task.delay(0.1, function()
		tween(core, 0.15, { Transparency = 1 })
		starFlash(to, look, color, 1)
	end)
end

-- a crescent (Wave): an arc of energy that runs forward along `dir`
function handlers.Crescent(from: Vector3, dir: Vector3, range: number, color: Color3)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	local count = 13
	local radius = 3
	local blades = {}
	for i = 1, count do
		blades[i] = part({ Size = Vector3.new(0.15, 1, 0.8), Color = color, Transparency = 0.1 })
	end
	local start = os.clock()
	local seconds = range / 55
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - start) / seconds
		if t >= 1 then
			connection:Disconnect()
			for _, b in ipairs(blades) do
				b:Destroy()
			end
			return
		end
		local center = from + dir * (range * t)
		local base = CFrame.lookAt(center, center + dir)
		local r = radius * (1 + t * 0.8)
		for i, b in ipairs(blades) do
			local k = (i - 1) / (count - 1)
			local a = math.rad(-70 + 140 * k)
			local thick = 0.4 + 1.2 * math.sin(k * math.pi)
			b.Size = Vector3.new(0.12, thick, r * 0.24)
			b.CFrame = base * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -r) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, 0)
			b.Transparency = 0.1 + t * 0.8
		end
	end)
	Style.PlaySound("Swing", 0.8, 0.4)
end

-- Pull: an energy vortex that shrinks into the center
function handlers.Vortex(center: Vector3, radius: number, color: Color3)
	local y = groundY(center) + 0.2
	for k = 0, 2 do
		local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, radius * 2, radius * 2), CFrame = CFrame.new(center.X, y + k * 0.6, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.25 + k * 0.15 })
		task.delay(k * 0.08, function()
			tween(ring, 0.45, { Size = Vector3.new(0.2, 1, 1), Transparency = 1 })
		end)
		Debris:AddItem(ring, 0.7)
	end
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(center.X, y + 1.5, center.Z), Color = color, Transparency = 0.2 })
	tween(core, 0.5, { Size = Vector3.new(4, 4, 4), Transparency = 1 })
	Debris:AddItem(core, 0.55)
	burst(Vector3.new(center.X, y + 1, center.Z), color, 24, 12, 0.3, 0.5)
end

-- Spin: energy blades whirling around the character
function handlers.Whirl(character, radius: number, color: Color3, seconds: number)
	local root = rootOf(character)
	if not root then
		return
	end
	local count = 3
	local blades = {}
	for i = 1, count do
		blades[i] = part({ Size = Vector3.new(0.15, 0.9, radius * 0.9), Color = color, Transparency = 0.15 })
	end
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		if t >= seconds or not root.Parent then
			connection:Disconnect()
			for _, b in ipairs(blades) do
				tween(b, 0.15, { Transparency = 1 })
				Debris:AddItem(b, 0.2)
			end
			return
		end
		local spin = t * 18
		for i, b in ipairs(blades) do
			local a = spin + (i - 1) * math.pi * 2 / count
			b.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius * 0.5)
		end
	end)
end

-- Strike / Stun: a crossed slash on the target and sparks
function handlers.Cross(at: Vector3, color: Color3, size: number?)
	local s = size or 4
	local cam = Workspace.CurrentCamera
	local face = if cam then CFrame.lookAt(at, cam.CFrame.Position) else CFrame.new(at)
	for _, angle in ipairs({ 45, -45 }) do
		local slash = part({ Size = Vector3.new(0.3, 0.1, 0.1), CFrame = face * CFrame.Angles(0, 0, math.rad(angle)), Color = color:Lerp(Color3.new(1, 1, 1), 0.3) })
		tween(slash, 0.1, { Size = Vector3.new(s, 0.3, 0.1) })
		task.delay(0.12, function()
			tween(slash, 0.2, { Size = Vector3.new(s * 1.2, 0.02, 0.1), Transparency = 1 })
		end)
		Debris:AddItem(slash, 0.4)
	end
	burst(at, color, 16, 20, 0.25, 0.35)
end

remote.OnClientEvent:Connect(function(kind, fxKind, ...)
	if kind ~= "Fx" or Style.HideEffects then
		return
	end
	local handler = handlers[fxKind]
	if handler then
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[AbilityFx] " .. tostring(fxKind) .. ": " .. tostring(err))
		end
	end
end)

return AbilityFx
