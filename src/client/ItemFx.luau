--[[
	ItemFx.luau
	Animated rarity effects of items tagged "ItemFx" (WeaponBuilder sets
	the tag and the attributes Fx = "Mythic" | "Secret", FxColor,
	FxLength). Local only, also inside ViewportFrame previews:
	  Mythic - two energy rings turning around the blade + lightning arcs
	  Secret - the same, and every glowing part cycles through the rainbow
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ItemFx = {}

local entries = {} -- [model] = state

local function ring(model, color: Color3, diameter: number)
	local p = Instance.new("Part")
	p.Name = "FxRing"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.06, diameter, diameter)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.25
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local handle = model.PrimaryPart or model:FindFirstChild("Handle")
	if not handle then
		return
	end
	local color = model:GetAttribute("FxColor") or Color3.fromRGB(255, 61, 184)
	local length = model:GetAttribute("FxLength") or 4
	local state = { handle = handle, color = color, length = length, phase = math.random() * 6, rings = {}, beams = {}, glow = {} }
	for i, at in ipairs({ 0.45, 0.8 }) do
		state.rings[i] = { part = ring(model, color, 0.9 + i * 0.25), at = at }
	end
	-- lightning: beams between attachments on the handle, curve jitters
	for i = 1, 2 do
		local a0 = Instance.new("Attachment")
		a0.Name = "FxA0"
		a0.Position = Vector3.new(0, length * 0.3, 0)
		a0.Parent = handle
		local a1 = Instance.new("Attachment")
		a1.Name = "FxA1"
		a1.Position = Vector3.new(0, length * (0.85 + i * 0.05), 0)
		a1.Parent = handle
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		beam.LightEmission = 1
		beam.Width0 = 0.12
		beam.Width1 = 0.05
		beam.Segments = 12
		beam.FaceCamera = true
		beam.Parent = handle
		state.beams[i] = beam
	end
	if model:GetAttribute("Fx") == "Secret" then
		for _, d in ipairs(model:GetDescendants()) do
			if (d:IsA("BasePart") and d.Material == Enum.Material.Neon) or d:IsA("Light") or d:IsA("Trail") or d:IsA("ParticleEmitter") then
				table.insert(state.glow, d)
			end
		end
		for _, r in ipairs(state.rings) do
			table.insert(state.glow, r.part)
		end
	end
	entries[model] = state
end

for _, model in ipairs(CollectionService:GetTagged("ItemFx")) do
	add(model)
end
CollectionService:GetInstanceAddedSignal("ItemFx"):Connect(function(model)
	task.defer(add, model)
end)
CollectionService:GetInstanceRemovedSignal("ItemFx"):Connect(function(model)
	entries[model] = nil
end)

local lastJitter = 0
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local jitter = t - lastJitter > 0.07
	if jitter then
		lastJitter = t
	end
	for model, s in pairs(entries) do
		if not model.Parent or not s.handle.Parent then
			entries[model] = nil
			continue
		end
		local base = s.handle.CFrame
		for i, r in ipairs(s.rings) do
			local spin = t * (if i == 1 then 3 else -2.4) + s.phase
			local y = s.length * r.at + math.sin(t * 2 + i) * 0.15
			r.part.CFrame = base * CFrame.new(0, y, 0) * CFrame.Angles(0, spin, math.rad(90)) * CFrame.Angles(math.rad(12 * i), 0, 0)
		end
		if jitter then
			for _, beam in ipairs(s.beams) do
				beam.CurveSize0 = (math.random() - 0.5) * 2.4
				beam.CurveSize1 = (math.random() - 0.5) * 2.4
				beam.Transparency = NumberSequence.new(if math.random() < 0.25 then 1 else 0.1)
			end
		end
		if #s.glow > 0 then
			local color = Color3.fromHSV((t * 0.35 + s.phase) % 1, 0.75, 1)
			for _, g in ipairs(s.glow) do
				if g:IsA("BasePart") or g:IsA("Light") then
					g.Color = color
				elseif g:IsA("Trail") or g:IsA("ParticleEmitter") then
					g.Color = ColorSequence.new(color)
				end
			end
		end
	end
end)

return ItemFx
