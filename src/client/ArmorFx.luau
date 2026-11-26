--[[
	ArmorFx.luau
	Living effects of Rare+ armor (ArmorBuilder tags the piece "ArmorFx"
	with FxRank = rarity index, FxColor, FxSlot). Local only, also in the
	inventory doll:
	  Rare+       the glowing lines breathe (transparency pulse)
	  Epic+       chest: three energy motes orbit the body
	  Legendary+  chest: a turning halo ring behind the back
	The parts live inside the armor model and follow its torso part.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local ArmorFx = {}

local entries = {} -- [model] = state
local NEON = Enum.Material.Neon

local function part(model, size: Vector3, color: Color3, shape)
	local p = Instance.new("Part")
	p.Name = "FxPart"
	p.Size = size
	p.Color = color
	p.Material = NEON
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	return p
end

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local rank = model:GetAttribute("FxRank") or 0
	local color = model:GetAttribute("FxColor") or Color3.new(1, 1, 1)
	local s = { lines = {}, motes = {}, halo = nil, anchor = nil, phase = math.random() * 6 }
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Material == NEON and p.Name ~= "Sheen" then
			table.insert(s.lines, { part = p, base = p.Transparency })
		end
	end
	if model:GetAttribute("FxSlot") == "Chest" then
		s.anchor = model:FindFirstChild("Plate") or model:FindFirstChild("Vest") or model:FindFirstChild("Suit")
		if s.anchor and rank >= Config.Rarity.Epic.Index then
			for i = 1, 3 do
				local mote = part(model, Vector3.new(0.35, 0.35, 0.35), color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.PartType.Ball)
				local trailA = Instance.new("Attachment")
				trailA.Position = Vector3.new(0, 0.15, 0)
				trailA.Parent = mote
				local trailB = Instance.new("Attachment")
				trailB.Position = Vector3.new(0, -0.15, 0)
				trailB.Parent = mote
				local trail = Instance.new("Trail")
				trail.Attachment0 = trailA
				trail.Attachment1 = trailB
				trail.Color = ColorSequence.new(color)
				trail.LightEmission = 1
				trail.Lifetime = 0.35
				trail.Transparency = NumberSequence.new(0.2, 1)
				trail.Parent = mote
				s.motes[i] = mote
			end
		end
		if s.anchor and rank >= Config.Rarity.Legendary.Index then
			local halo = Instance.new("Model")
			halo.Name = "FxHalo"
			halo.Parent = model
			local n = 20
			for k = 0, n - 1 do
				local a = (k + 0.5) / n * math.pi * 2
				local seg = part(halo, Vector3.new(0.12, 0.12, 2.3 * math.pi * 2 / n + 0.05), color, nil)
				seg:SetAttribute("A", a)
			end
			-- spikes of the crown-like halo
			for k = 0, 7 do
				local spike = part(halo, Vector3.new(0.1, 0.55, 0.1), color:Lerp(Color3.new(1, 1, 1), 0.4), nil)
				spike:SetAttribute("A", (k + 0.5) / 8 * math.pi * 2)
				spike:SetAttribute("Spike", true)
			end
			s.halo = halo
		end
	end
	entries[model] = s
end

local function remove(model)
	entries[model] = nil
end

for _, model in ipairs(CollectionService:GetTagged("ArmorFx")) do
	add(model)
end
CollectionService:GetInstanceAddedSignal("ArmorFx"):Connect(function(model)
	task.defer(add, model) -- after its parts are in
end)
CollectionService:GetInstanceRemovedSignal("ArmorFx"):Connect(remove)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, s in pairs(entries) do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		local pulse = (math.sin(t * 3 + s.phase) + 1) / 2
		for _, line in ipairs(s.lines) do
			if line.part.Parent then
				line.part.Transparency = math.clamp(line.base + pulse * 0.45, 0, 0.9)
			end
		end
		local anchor = s.anchor
		if anchor and anchor.Parent then
			local base = anchor.CFrame
			for i, mote in ipairs(s.motes) do
				local a = t * 2.2 + i * math.pi * 2 / 3
				mote.CFrame = base * CFrame.new(math.cos(a) * 1.9, math.sin(t * 1.7 + i) * 0.9, math.sin(a) * 1.4)
			end
			if s.halo then
				local center = base * CFrame.new(0, 0.9, 1.25) -- behind the back, at the shoulders
				for _, seg in ipairs(s.halo:GetChildren()) do
					local a = seg:GetAttribute("A") + t * 0.8
					if seg:GetAttribute("Spike") then
						seg.CFrame = center * CFrame.Angles(0, 0, a) * CFrame.new(0, 1.45, 0)
					else
						seg.CFrame = center * CFrame.Angles(0, 0, a) * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, math.rad(90), 0)
					end
				end
			end
		end
	end
end)

return ArmorFx
