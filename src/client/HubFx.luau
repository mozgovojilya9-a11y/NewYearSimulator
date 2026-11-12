--[[
	HubFx.luau
	Local-only life for the hub:
	- trainer objects "breathe" (Model:ScaleTo) and squash on every Aura
	  tick / click (idle animation),
	- locked trainers: THIS player sees a solid force-field box around the
	  territory and the requirement in red on its sign; unlocked ones show
	  a green invitation (the server decides who actually earns Aura).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local hub = Workspace:WaitForChild("Hub")
local trainers = hub:WaitForChild("Trainers")

local HubFx = {}

local Texts = Config.HubLayout.Texts
local objects = {} -- [model] = { object, phase, squash }

local function indexTrainers()
	objects = {}
	for i, model in ipairs(trainers:GetChildren()) do
		local object = model:FindFirstChild("Object")
		if object then
			objects[model] = { object = object, phase = i * 0.7, squash = 0 }
		end
	end
end
indexTrainers()
trainers.ChildAdded:Connect(function()
	task.defer(indexTrainers)
end)

-- Breathing + squash.
RunService.Heartbeat:Connect(function(dt)
	local t = os.clock()
	for _, entry in pairs(objects) do
		entry.squash = math.max(0, entry.squash - dt * 6)
		local breathe = 1 + math.sin(t * 2 + entry.phase) * 0.025
		local s = breathe * (1 - entry.squash * 0.14)
		if entry.object.Parent then
			pcall(entry.object.ScaleTo, entry.object, s)
		end
	end
end)

-- The trainer "flinches".
function HubFx.Squash(model: Model)
	local entry = objects[model]
	if entry then
		entry.squash = 1
	end
end

---------------------------------------------------------------------
-- Locks (per player)
---------------------------------------------------------------------

local function csvSet(text: string?)
	local set = {}
	for id in string.gmatch(text or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function isUnlocked(model, unlocked, passes): boolean
	local pass = model:GetAttribute("RequirePass")
	if pass then
		return passes[pass] == true
	end
	local reqRebirths = model:GetAttribute("RequireRebirths")
	if reqRebirths and (player:GetAttribute("Rebirths") or 0) < reqRebirths then
		return false
	end
	if model:GetAttribute("RequireAura") and not unlocked[model:GetAttribute("TrainerId")] then
		return false
	end
	return true
end

local function refreshLocks()
	local unlocked = csvSet(player:GetAttribute("TrainersUnlocked") or "1")
	local passes = csvSet(player:GetAttribute("Passes"))
	for _, model in ipairs(trainers:GetChildren()) do
		local open = isUnlocked(model, unlocked, passes)
		local lock = model:FindFirstChild("Lock")
		if lock then
			lock.CanCollide = not open
			lock.Transparency = if open then 1 else 0.35
		end
		local sign = model:FindFirstChild("Sign")
		local label = sign and sign:FindFirstChild("Req", true)
		if label then
			label.Text = if open then Texts.TrainerOpen else (model:GetAttribute("RequireText") or "")
			label.TextColor3 = if open then Config.Theme.Green else Config.Theme.Red
		end
		local object = model:FindFirstChild("Object")
		if object then
			for _, part in ipairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = if open then 0 else 0.45
				end
			end
		end
	end
end
for _, attribute in ipairs({ "TrainersUnlocked", "Rebirths", "Passes" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshLocks)
end
trainers.ChildAdded:Connect(function()
	task.defer(refreshLocks)
end)
refreshLocks()

return HubFx
