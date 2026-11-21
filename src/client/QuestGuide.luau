--[[
	QuestGuide.luau
	The new player's path (plan's yellow dashes):
	  * gold chevrons crawl on the floor from the player along the route
	    to the story quest's place (player attribute StoryPlace, routes in
	    Config.HubLayout.Guide.Routes); only in the hub;
	  * "!" over the mentor when he has something new / a reward
	    (StoryMarker), over the gate keeper when a daily reward waits
	    (RewardReady). The "!" gently bobs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local G = Config.HubLayout.Guide
local player = Players.LocalPlayer

local QuestGuide = {}

local folder = Instance.new("Folder")
folder.Name = "QuestGuide"
folder.Parent = Workspace

-- chevron = two thin bars forming ">" lying on the floor
local pool = {}
local function chevron(i: number)
	local c = pool[i]
	if c then
		return c
	end
	local model = Instance.new("Model")
	model.Name = "Chevron"
	local parts = {}
	for k, side in ipairs({ -1, 1 }) do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = G.Color
		p.Transparency = 0.2
		p.Size = Vector3.new(0.28, 0.06, 1.5)
		p.Parent = model
		parts[k] = { Part = p, Side = side }
	end
	model.Parent = folder
	c = { Model = model, Parts = parts }
	pool[i] = c
	return c
end

local function place(c, pos: Vector3, dir: Vector3, alpha: number)
	local cf = CFrame.lookAt(pos, pos + dir)
	for _, entry in ipairs(c.Parts) do
		entry.Part.CFrame = cf * CFrame.Angles(0, math.rad(entry.Side * 40), 0) * CFrame.new(0, 0, 0.55)
		entry.Part.Transparency = alpha
	end
end

local function hideFrom(n: number)
	for i = n, #pool do
		for _, entry in ipairs(pool[i].Parts) do
			entry.Part.Transparency = 1
		end
	end
end

local base -- spawn point on the floor
local function getBase()
	if base then
		return base
	end
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		base = Vector3.new(spawn.Position.X, spawn.Position.Y + spawn.Size.Y / 2, spawn.Position.Z)
	end
	return base
end

-- closest point on segment ab to p (2D on the floor) and its distance
local function closest(p: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	local q = Vector3.new(a.X + ab.X * t, 0, a.Z + ab.Z * t)
	return (Vector3.new(p.X, 0, p.Z) - q).Magnitude, t
end

local function route(place: string)
	local list = G.Routes[place]
	local b = getBase()
	if not list or not b then
		return nil
	end
	local points = {}
	for i, offset in ipairs(list) do
		points[i] = b + offset + Vector3.new(0, 0.18, 0)
	end
	if place == "Mentor" then
		local npc = Workspace:FindFirstChild("Hub") and Workspace.Hub:FindFirstChild("NPC_Mentor")
		local anchor = npc and npc:FindFirstChild("Anchor")
		if anchor then
			points[#points] = Vector3.new(anchor.Position.X, b.Y + 0.18, anchor.Position.Z)
		end
	end
	return points
end

local function draw(points, from: Vector3, shift: number)
	-- start on the segment nearest to the player
	local best, bestIndex = math.huge, 1
	for i = 1, #points - 1 do
		local d = closest(from, points[i], points[i + 1])
		if d < best then
			best, bestIndex = d, i
		end
	end
	local path = { Vector3.new(from.X, points[1].Y, from.Z) }
	for i = bestIndex + 1, #points do
		table.insert(path, points[i])
	end
	local goal = path[#path]
	if (Vector3.new(from.X, goal.Y, from.Z) - goal).Magnitude < 7 then
		hideFrom(1)
		return
	end
	-- chevrons at distances shift, shift + Step, ... along the path
	-- (shift grows with time, so they crawl towards the goal)
	local count = 0
	local distance = shift + 2.5
	local segment, segStart = 1, 0
	while count < G.Max and segment < #path do
		local a, b = path[segment], path[segment + 1]
		local seg = (b - a).Magnitude
		if distance > segStart + seg then
			segStart += seg
			segment += 1
		else
			local dir = if seg > 0 then (b - a) / seg else Vector3.zAxis
			count += 1
			place(chevron(count), a + dir * (distance - segStart), dir, 0.25 + 0.6 * count / G.Max)
			distance += G.Step
		end
	end
	hideFrom(count + 1)
end

-- NPC "!" markers
local function marker(npcName: string): BillboardGui?
	local hub = Workspace:FindFirstChild("Hub")
	local npc = hub and hub:FindFirstChild(npcName)
	local anchor = npc and npc:FindFirstChild("Anchor")
	return anchor and anchor:FindFirstChild("Marker")
end

local last = 0
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local mentor = marker("NPC_Mentor")
	if mentor then
		mentor.Enabled = player:GetAttribute("StoryMarker") == true
		mentor.StudsOffsetWorldSpace = Vector3.new(0, 4.2 + math.sin(now * 3) * 0.3, 0)
	end
	local keeper = marker("NPC_GateKeeper")
	if keeper then
		keeper.Enabled = player:GetAttribute("RewardReady") == true
		keeper.StudsOffsetWorldSpace = Vector3.new(0, 4.2 + math.sin(now * 3) * 0.3, 0)
	end
	if now - last < 1 / 30 then
		return
	end
	last = now
	local place = player:GetAttribute("StoryPlace") or ""
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if place == "" or not root or player:GetAttribute("Zone") ~= "Hub" then
		hideFrom(1)
		return
	end
	local points = route(place)
	if not points then
		hideFrom(1)
		return
	end
	draw(points, root.Position, (now * G.Speed) % G.Step)
end)

return QuestGuide
