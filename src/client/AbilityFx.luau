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
