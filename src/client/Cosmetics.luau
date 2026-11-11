--[[
	Cosmetics.luau
	Shows every player's equipped pet floating next to them. Purely
	visual and local: each client builds the pet from the "EquippedPet"
	attribute the server sets. (Weapons and backpacks are welded to the
	character by the server: EquipmentService.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Cosmetics = {}

local folder = Instance.new("Folder")
folder.Name = "LocalCosmetics"
folder.Parent = Workspace

local visuals = {} -- [player] = { petId, pet: Model? }

local function part(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function makePet(def)
	local model = Instance.new("Model")
	model.Name = def.Name
	local body = part("Body", Vector3.one * def.Size, def.Color, model)
	body.Shape = Enum.PartType.Ball
	body.Material = Enum.Material.Neon
	model.PrimaryPart = body
	local eyeSize = def.Size * 0.22
	for _, side in ipairs({ -1, 1 }) do
		local eye = part("Eye", Vector3.one * eyeSize, Color3.new(0, 0, 0), model)
		eye.Shape = Enum.PartType.Ball
		eye.CFrame = body.CFrame * CFrame.new(side * def.Size * 0.2, def.Size * 0.12, -def.Size * 0.42)
	end
	if def.Wings then
		for _, side in ipairs({ -1, 1 }) do
			local wing = part("Wing", Vector3.new(def.Size * 0.9, 0.15, def.Size * 0.5), def.Color:Lerp(Color3.new(1, 1, 1), 0.4), model)
			wing.CFrame = body.CFrame * CFrame.new(side * def.Size * 0.75, def.Size * 0.15, def.Size * 0.1) * CFrame.Angles(0, 0, side * math.rad(20))
		end
	end
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = body
	model.Parent = folder
	return model
end

local function sync(v, player)
	local petId = player:GetAttribute("EquippedPet") or ""
	if v.petId ~= petId then
		if v.pet then
			v.pet:Destroy()
		end
		local def = Config.ItemById.Pet[petId]
		v.pet = if def then makePet(def) else nil
		v.petId = petId
	end
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local v = visuals[player]
		if not v then
			v = {}
			visuals[player] = v
		end
		sync(v, player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if v.pet and root then
			local bob = math.sin(t * 3 + player.UserId % 7) * 0.4
			local target = root.CFrame * CFrame.new(3, 1.5 + bob, 2)
			local current = v.pet:GetPivot()
			if (current.Position - target.Position).Magnitude > 40 then
				v.pet:PivotTo(target)
			else
				v.pet:PivotTo(current:Lerp(target, math.min(1, dt * 8)))
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local v = visuals[player]
	if v and v.pet then
		v.pet:Destroy()
	end
	visuals[player] = nil
end)

return Cosmetics
