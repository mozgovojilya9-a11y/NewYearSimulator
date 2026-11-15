--[[
	HubLife.luau
	Makes the world alive, locally on every client (nothing moves on the
	server, so it costs no network). Works on CollectionService tags set
	by NanoKit (hub and dungeon):
	  "Spin"    part / model turns around its Axis at Speed deg/s
	  "Bob"     part / model floats up and down (Amplitude, Period)
	  "Flicker" holographic boards dip in transparency now and then
	  "Pulse"   neon parts breathe (transparency) with Period
	  "Drone"   a drone model flies its route P1..Pn at Speed, rotors spin
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local HubLife = {}

local entries = {} -- [instance] = { kind, base CFrame, phase, ... }

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		return instance:GetPivot()
	end
	return nil
end

local function setPivot(instance: Instance, cf: CFrame)
	if instance:IsA("BasePart") then
		instance.CFrame = cf
	elseif instance:IsA("Model") then
		instance:PivotTo(cf)
	end
end

local function add(kind: string, instance: Instance)
	local base = pivotOf(instance)
	if not base and kind ~= "Flicker" then
		return
	end
	local entry = { kind = kind, base = base, phase = math.random() * 10, instance = instance }
	if kind == "Drone" then
		local route = {}
		local i = 1
		while instance:GetAttribute("P" .. i) do
			table.insert(route, instance:GetAttribute("P" .. i))
			i += 1
		end
		if #route < 2 then
			return
		end
		local length = 0
		for k = 1, #route do
			length += (route[k % #route + 1] - route[k]).Magnitude
		end
		entry.route = route
		entry.length = length
		entry.rotors = {}
		for _, p in ipairs(instance:GetChildren()) do
			if p.Name == "Rotor" then
				table.insert(entry.rotors, { part = p, offset = base:ToObjectSpace(p.CFrame) })
			end
		end
		entry.parts = {}
		for _, p in ipairs(instance:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "Rotor" then
				table.insert(entry.parts, { part = p, offset = base:ToObjectSpace(p.CFrame) })
			end
		end
	elseif kind == "Pulse" and instance:IsA("BasePart") then
		entry.transparency = instance.Transparency
	end
	entries[instance] = entry
end

for _, kind in ipairs({ "Spin", "Bob", "Flicker", "Pulse", "Drone", "Conveyor" }) do
	for _, instance in ipairs(CollectionService:GetTagged(kind)) do
		add(kind, instance)
	end
	CollectionService:GetInstanceAddedSignal(kind):Connect(function(instance)
		task.defer(add, kind, instance)
	end)
	CollectionService:GetInstanceRemovedSignal(kind):Connect(function(instance)
		entries[instance] = nil
	end)
end

local AXES = {
	X = function(a)
		return CFrame.Angles(a, 0, 0)
	end,
	Y = function(a)
		return CFrame.Angles(0, a, 0)
	end,
	Z = function(a)
		return CFrame.Angles(0, 0, a)
	end,
}

-- Point at distance d along a closed route.
local function along(route, d: number)
	for k = 1, #route do
		local a, b = route[k], route[k % #route + 1]
		local seg = (b - a).Magnitude
		if d <= seg then
			return a:Lerp(b, d / math.max(seg, 0.001)), (b - a).Unit
		end
		d -= seg
	end
	return route[1], (route[2] - route[1]).Unit
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for instance, e in pairs(entries) do
		if not instance.Parent then
			entries[instance] = nil
			continue
		end
		local kind = e.kind
		if kind == "Spin" then
			local axis = AXES[instance:GetAttribute("Axis") or "Y"] or AXES.Y
			-- around the world axis through the center, or the part's own axis
			local base = e.base
			local angle = math.rad((instance:GetAttribute("Speed") or 30) * t)
			if instance:GetAttribute("Local") then
				setPivot(instance, base * axis(angle))
			else
				setPivot(instance, CFrame.new(base.Position) * axis(angle) * base.Rotation)
			end
		elseif kind == "Conveyor" then
			-- slides along its own -Z (look) and wraps after Length studs
			local length = instance:GetAttribute("Length") or 20
			local speed = instance:GetAttribute("Speed") or 3
			local d = ((t * speed) + (instance:GetAttribute("Start") or 0)) % length
			setPivot(instance, e.base * CFrame.new(0, 0, -d))
		elseif kind == "Bob" then
			local amp = instance:GetAttribute("Amplitude") or 0.5
			local period = instance:GetAttribute("Period") or 3
			setPivot(instance, e.base + Vector3.new(0, math.sin((t + e.phase) * math.pi * 2 / period) * amp, 0))
		elseif kind == "Pulse" and instance:IsA("BasePart") then
			local period = instance:GetAttribute("Period") or 2
			instance.Transparency = math.clamp((e.transparency or 0) + (math.sin((t + e.phase) * math.pi * 2 / period) + 1) * 0.18, 0, 0.95)
		elseif kind == "Flicker" then
			-- short dips a few times a minute
			local dip = math.sin(t * 23 + e.phase * 7) > 0.97 or (math.floor(t * 3 + e.phase) % 37 == 0)
			for _, g in ipairs(instance:GetChildren()) do
				if g:IsA("SurfaceGui") then
					g.Enabled = true
					local plate = g:FindFirstChild("Plate")
					if plate then
						plate.BackgroundTransparency = if dip then 0.35 else 0
					end
				end
			end
		elseif kind == "Drone" then
			local speed = instance:GetAttribute("Speed") or 8
			local d = ((t + e.phase) * speed) % e.length
			local pos, dir = along(e.route, d)
			local bob = math.sin(t * 2 + e.phase) * 0.4
			local frame = CFrame.lookAt(pos + Vector3.new(0, bob, 0), pos + Vector3.new(dir.X, 0, dir.Z) + Vector3.new(0, bob, 0)) * CFrame.Angles(math.rad(-8), 0, 0)
			for _, p in ipairs(e.parts) do
				p.part.CFrame = frame * p.offset
			end
			for i, r in ipairs(e.rotors) do
				r.part.CFrame = frame * r.offset * CFrame.Angles(0, t * 40 + i, 0)
			end
		end
	end
end)

return HubLife
