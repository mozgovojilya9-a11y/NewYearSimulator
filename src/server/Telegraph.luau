--[[
	Telegraph.luau
	Warnings of enemy attacks on the floor (seen by everyone): an outline
	that appears at once and a fill that grows until the moment of the hit.
	  Telegraph.Circle(parent, center, radius, seconds, color)
	  Telegraph.Rect(parent, cframe, length, width, seconds, color)
	      cframe = start point on the floor, looking along the attack
	  Telegraph.Line(parent, from, to, width, seconds, color)  (a shot)
	Each returns the parts; they remove themselves after `seconds` (+ a
	short flash). Helpers InCircle / InRect / InCone test a position.
]]

local TweenService = game:GetService("TweenService")

local Telegraph = {}

local function part(parent, props)
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
	p.Parent = parent
	return p
end

local function flashAndRemove(parts, seconds: number)
	task.delay(seconds, function()
		for _, p in ipairs(parts) do
			if p.Parent then
				p.Transparency = 0.1
				TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.3)
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

function Telegraph.Circle(parent, center: Vector3, radius: number, seconds: number, color: Color3)
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local at = CFrame.new(center.X, center.Y + 0.08, center.Z) * flat
	local edge = part(parent, { Name = "WarnEdge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, radius * 2, radius * 2), CFrame = at, Color = color, Transparency = 0.5 })
	local inner = part(parent, { Name = "WarnInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, radius * 2 - 0.6, radius * 2 - 0.6), CFrame = at * CFrame.new(0.01, 0, 0), Color = Color3.fromRGB(20, 8, 8), Transparency = 0.45 })
	local fill = part(parent, { Name = "WarnFill", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 0.2, 0.2), CFrame = at * CFrame.new(0.02, 0, 0), Color = color, Transparency = 0.62 })
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(0.08, radius * 2 - 0.6, radius * 2 - 0.6) }):Play()
	local parts = { edge, inner, fill }
	flashAndRemove(parts, seconds)
	return parts
end

function Telegraph.Rect(parent, cf: CFrame, length: number, width: number, seconds: number, color: Color3)
	local base = CFrame.new(cf.Position + Vector3.new(0, 0.08, 0)) * cf.Rotation
	local mid = base * CFrame.new(0, 0, -length / 2)
	local edge = part(parent, { Name = "WarnEdge", Size = Vector3.new(width, 0.06, length), CFrame = mid, Color = color, Transparency = 0.5 })
	local inner = part(parent, { Name = "WarnInner", Size = Vector3.new(width - 0.5, 0.07, length - 0.5), CFrame = mid * CFrame.new(0, 0.01, 0), Color = Color3.fromRGB(20, 8, 8), Transparency = 0.45 })
	local fill = part(parent, { Name = "WarnFill", Size = Vector3.new(width - 0.5, 0.08, 0.2), CFrame = base * CFrame.new(0, 0.02, -0.1), Color = color, Transparency = 0.62 })
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(width - 0.5, 0.08, length - 0.5), CFrame = mid * CFrame.new(0, 0.02, 0) }):Play()
	local parts = { edge, inner, fill }
	flashAndRemove(parts, seconds)
	return parts
end

function Telegraph.Line(parent, from: Vector3, to: Vector3, width: number, seconds: number, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return {}
	end
	local line = part(parent, { Name = "WarnLine", Size = Vector3.new(0.18, 0.18, length), CFrame = CFrame.lookAt((from + to) / 2, to), Color = color, Transparency = 0.55 })
	local floorFrom = Vector3.new(from.X, to.Y - 2.8, from.Z)
	local floorTo = Vector3.new(to.X, to.Y - 2.8, to.Z)
	local strip = part(parent, { Name = "WarnStrip", Size = Vector3.new(width, 0.06, (floorTo - floorFrom).Magnitude), CFrame = CFrame.lookAt((floorFrom + floorTo) / 2, floorTo), Color = color, Transparency = 0.7 })
	TweenService:Create(strip, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Transparency = 0.55 }):Play()
	local parts = { line, strip }
	flashAndRemove(parts, seconds)
	return parts
end

-- A charging glow at a gun muzzle (ordinary shooters: no line across
-- the floor, the owner found those annoying - 23.11). A small ball that
-- swells until the shot.
function Telegraph.Muzzle(parent, at: Vector3, seconds: number, color: Color3)
	local ball = part(parent, { Name = "WarnMuzzle", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = CFrame.new(at), Color = color, Transparency = 0.2 })
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(1.3, 1.3, 1.3) }):Play()
	local parts = { ball }
	flashAndRemove(parts, seconds)
	return parts
end

-- A flat triangle a-b-c from two WedgeParts (thickness `t`).
local function triangle(parent, a: Vector3, b: Vector3, c: Vector3, t: number, props)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local out = {}
	for i, data in ipairs({ { (a + b) / 2, right, math.abs(ab:Dot(back)) }, { (a + c) / 2, -right, math.abs(ac:Dot(back)) } }) do
		local w = Instance.new("WedgePart")
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
		w.Material = Enum.Material.Neon
		for k, v in pairs(props) do
			w[k] = v
		end
		w.Size = Vector3.new(t, height, data[3])
		w.CFrame = CFrame.fromMatrix(data[1], data[2], up, if i == 1 then back else -back)
		w.Parent = parent
		out[i] = w
	end
	return out
end

-- A cone (fan) on the floor: from cf's position along its look, `radius`
-- long, `angle` degrees wide. The fill brightens until the hit.
function Telegraph.Cone(parent, cf: CFrame, radius: number, angle: number, seconds: number, color: Color3)
	local origin = cf.Position + Vector3.new(0, 0.1, 0)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	local steps = math.max(3, math.ceil(angle / 12))
	local parts = {}
	local function edgePoint(i, r)
		local a = math.rad(-angle / 2 + angle * i / steps)
		local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(look)
		return origin + dir * r
	end
	for i = 0, steps - 1 do
		for _, w in ipairs(triangle(parent, origin, edgePoint(i, radius), edgePoint(i + 1, radius), 0.06, { Name = "WarnCone", Color = color, Transparency = 0.75 })) do
			table.insert(parts, w)
			TweenService:Create(w, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Transparency = 0.55 }):Play()
		end
	end
	-- the outer arc edge
	for i = 0, steps - 1 do
		local p1, p2 = edgePoint(i, radius), edgePoint(i + 1, radius)
		table.insert(parts, part(parent, { Name = "WarnEdge", Size = Vector3.new(0.25, 0.08, (p2 - p1).Magnitude), CFrame = CFrame.lookAt((p1 + p2) / 2, p2) + Vector3.new(0, 0.02, 0), Color = color, Transparency = 0.2 }))
	end
	flashAndRemove(parts, seconds)
	return parts
end

function Telegraph.InCone(position: Vector3, cf: CFrame, radius: number, angle: number): boolean
	local offset = Vector3.new(position.X - cf.Position.X, 0, position.Z - cf.Position.Z)
	if offset.Magnitude > radius + 1 then
		return false
	end
	if offset.Magnitude < 2 then
		return true
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(look), -1, 1))) <= angle / 2 + 4
end

function Telegraph.InCircle(position: Vector3, center: Vector3, radius: number): boolean
	return Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude <= radius
end

-- Is `position` inside the rectangle that starts at cf and runs `length`
-- along cf's look, `width` wide?
function Telegraph.InRect(position: Vector3, cf: CFrame, length: number, width: number): boolean
	local localPos = cf:PointToObjectSpace(position)
	return -localPos.Z >= -1 and -localPos.Z <= length + 1 and math.abs(localPos.X) <= width / 2 + 1
end

-- Distance from a point to the segment a-b on the floor plane.
function Telegraph.ToSegment(position: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(position.X - a.X, 0, position.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

return Telegraph
