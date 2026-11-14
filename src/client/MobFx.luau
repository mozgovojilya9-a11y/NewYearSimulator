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
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local lanes = Workspace:WaitForChild("Dungeon"):WaitForChild("Lanes")

local MobFx = {}

local mobs = {} -- [model] = state

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

local function burst(model)
	if Style.HideEffects then
		return
	end
	local center = model:GetPivot().Position
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
	mobs[model] = state

	local highlight
	model:GetAttributeChangedSignal("Telegraph"):Connect(function()
		if model:GetAttribute("Telegraph") then
			state.windingUp = true
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.FillColor = Style.Colors.Red
				highlight.FillTransparency = 0.45
				highlight.OutlineColor = Style.Colors.Red
				highlight.OutlineTransparency = 0
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = model
			end
		else
			state.windingUp = false
			state.strike = 1
			if highlight then
				highlight:Destroy()
				highlight = nil
			end
		end
	end)
	model:GetAttributeChangedSignal("Hits"):Connect(function()
		state.recoil = 1
	end)
	model:GetAttributeChangedSignal("Dying"):Connect(function()
		if model:GetAttribute("Dying") then
			mobs[model] = nil
			burst(model)
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
		local velocity = s.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		s.walk += (math.clamp(speed / 8, 0, 1) - s.walk) * math.min(1, dt * 8)
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
				local lift = 0
				if s.float then
					lift = math.sin(t * 2.4 + s.phase) * 0.5
				elseif s.hop then
					lift = math.abs(math.sin(t * 7 + s.phase)) * 0.6 * s.walk
				end
				local squash = if s.hop then 1 else 0
				cf = CFrame.new(0, lift + breathe * (1 + squash * 4), 0)
					* A(-s.recoil * 0.25 + s.windup * 0.1 - strikeArc * 0.18, 0, math.sin(t * 9 + s.phase) * 0.05 * s.walk)
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
-- Boss health bar (top of the screen)
---------------------------------------------------------------------

local bar = Style.Plate(Style.Gui, {
	Name = "BossBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 140), -- under the objective + hint lines
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
				if model:GetAttribute("Boss") and model.Parent then
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
			bossName.Text = "👑 " .. (boss:GetAttribute("MobName") or boss.Name)
			local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
			Style.Tween(fill, 0.1, { Size = UDim2.fromScale(ratio, 1) })
			hpText.Text = Format.Number(humanoid.Health) .. " / " .. Format.Number(humanoid.MaxHealth)
		end
	end
end)

return MobFx
