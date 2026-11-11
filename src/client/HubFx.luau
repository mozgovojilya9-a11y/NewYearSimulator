--[[
	HubFx.luau
	Local-only life for the hub:
	- trainer objects "breathe" (Model:ScaleTo) and squash when hit,
	- locked trainer platforms: barrier + lock sign shown only while
	  THIS player hasn't met the requirement (server validates clicks),
	- the wheel's "free spin" status line.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local hub = Workspace:WaitForChild("Hub")
local trainers = hub:WaitForChild("Trainers")

local HubFx = {}

local objects = {} -- [index] = { model, phase, squash }

local function indexTrainers()
	objects = {}
	for _, model in ipairs(trainers:GetChildren()) do
		local index = model:GetAttribute("Index")
		local object = model:FindFirstChild("Object")
		if index and object then
			objects[index] = { model = model, object = object, phase = index * 0.7, squash = 0 }
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
		local s = breathe * (1 - entry.squash * 0.15)
		if entry.object.Parent then
			pcall(entry.object.ScaleTo, entry.object, s)
		end
	end
end)

function HubFx.Squash(model: Model)
	for _, entry in pairs(objects) do
		if entry.model == model or entry.object == model then
			entry.squash = 1
		end
	end
end

---------------------------------------------------------------------
-- Locks (per player)
---------------------------------------------------------------------

local function unlockedSet()
	local set = {}
	for index in string.gmatch(player:GetAttribute("TrainersUnlocked") or "1", "[^,]+") do
		set[tonumber(index)] = true
	end
	return set
end

local function isUnlocked(model, unlocked): boolean
	local index = model:GetAttribute("Index")
	local reqRebirths = model:GetAttribute("RequireRebirths")
	if reqRebirths and (player:GetAttribute("Rebirths") or 0) < reqRebirths then
		return false
	end
	local reqAura = model:GetAttribute("RequireAura")
	if reqAura and not unlocked[index] then
		return false
	end
	return true
end

local function refreshLocks()
	local unlocked = unlockedSet()
	for _, model in ipairs(trainers:GetChildren()) do
		local lock = model:FindFirstChild("Lock")
		if lock then
			local open = isUnlocked(model, unlocked)
			for _, part in ipairs(lock:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = not open
					part.Transparency = if open then 1 elseif part.Name == "Barrier" then 0.35 else 0
					for _, gui in ipairs(part:GetChildren()) do
						if gui:IsA("SurfaceGui") then
							gui.Enabled = not open
						end
					end
				end
			end
			local object = model:FindFirstChild("Object")
			if object then
				for _, part in ipairs(object:GetDescendants()) do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = if open then 0 else 0.5
					end
				end
			end
		end
	end
end
player:GetAttributeChangedSignal("TrainersUnlocked"):Connect(refreshLocks)
player:GetAttributeChangedSignal("Rebirths"):Connect(refreshLocks)
trainers.ChildAdded:Connect(function()
	task.defer(refreshLocks)
end)
refreshLocks()

return HubFx
