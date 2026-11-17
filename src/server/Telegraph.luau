--[[
	Telegraph.luau
	Warnings of enemy attacks on the floor (seen by everyone): an outline
	that appears at once and a fill that grows until the moment of the hit.
	  Telegraph.Circle(parent, center, radius, seconds, color)
	  Telegraph.Rect(parent, cframe, length, width, seconds, color)
	      cframe = start point on the floor, looking along the attack
	  Telegraph.Line(parent, from, to, width, seconds, color)  (a shot)
	Each returns the parts; they remove themselves after `seconds` (+ a
	short flash). Helpers InCircle / InRect test a position.
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
	local edge = part(parent, { Name = "WarnEdge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, radius * 2, radius * 2), CFrame = at, Color = color, Transparency = 0.35 })
	local inner = part(parent, { Name = "WarnInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, radius * 2 - 0.6, radius * 2 - 0.6), CFrame = at * CFrame.new(0.01, 0, 0), Color = Color3.fromRGB(20, 8, 8), Transparency = 0.45 })
	local fill = part(parent, { Name = "WarnFill", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 0.2, 0.2), CFrame = at * CFrame.new(0.02, 0, 0), Color = color, Transparency = 0.4 })
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(0.08, radius * 2 - 0.6, radius * 2 - 0.6) }):Play()
	local parts = { edge, inner, fill }
	flashAndRemove(parts, seconds)
	return parts
end

function Telegraph.Rect(parent, cf: CFrame, length: number, width: number, seconds: number, color: Color3)
	local base = CFrame.new(cf.Position + Vector3.new(0, 0.08, 0)) * cf.Rotation
	local mid = base * CFrame.new(0, 0, -length / 2)
	local edge = part(parent, { Name = "WarnEdge", Size = Vector3.new(width, 0.06, length), CFrame = mid, Color = color, Transparency = 0.35 })
	local inner = part(parent, { Name = "WarnInner", Size = Vector3.new(width - 0.5, 0.07, length - 0.5), CFrame = mid * CFrame.new(0, 0.01, 0), Color = Color3.fromRGB(20, 8, 8), Transparency = 0.45 })
	local fill = part(parent, { Name = "WarnFill", Size = Vector3.new(width - 0.5, 0.08, 0.2), CFrame = base * CFrame.new(0, 0.02, -0.1), Color = color, Transparency = 0.4 })
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
	local line = part(parent, { Name = "WarnLine", Size = Vector3.new(0.18, 0.18, length), CFrame = CFrame.lookAt((from + to) / 2, to), Color = color, Transparency = 0.25 })
	local floorFrom = Vector3.new(from.X, to.Y - 2.8, from.Z)
	local floorTo = Vector3.new(to.X, to.Y - 2.8, to.Z)
	local strip = part(parent, { Name = "WarnStrip", Size = Vector3.new(width, 0.06, (floorTo - floorFrom).Magnitude), CFrame = CFrame.lookAt((floorFrom + floorTo) / 2, floorTo), Color = color, Transparency = 0.7 })
	TweenService:Create(strip, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Transparency = 0.35 }):Play()
	local parts = { line, strip }
	flashAndRemove(parts, seconds)
	return parts
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
