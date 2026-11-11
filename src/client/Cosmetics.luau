--[[
	Cosmetics.luau
	Shows every player's equipped backpack (on their back) and
	pet (floating next to them). Purely visual and local: each client
	builds the parts itself from the "EquippedBackpack"/"EquippedPet"
	attributes the server sets, so nothing here can affect gameplay.
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

local visuals = {} -- [player] = { petId, pet: Model?, packId, pack: Part? }

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
			wing.CFrame = body.CFrame
				* CFrame.new(side * def.Size * 0.75, def.Size * 0.15, def.Size * 0.1)
				* CFrame.Angles(0, 0, side * math.rad(20))
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

local function makePack(def)
	local pack = part("Backpack", def.Size, def.Color, folder)
	if def.Neon then
		pack.Material = Enum.Material.Neon
	end
	local strap = part("Strap", Vector3.new(def.Size.X + 0.05, 0.2, def.Size.Z + 0.05), def.Color:Lerp(Color3.new(0, 0, 0), 0.4), pack)
	strap.Name = "Strap"
	return pack
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

	local packId = player:GetAttribute("EquippedBackpack") or ""
	if v.packId ~= packId then
		if v.pack then
			v.pack:Destroy()
		end
		local def = Config.ItemById.Backpack[packId]
		v.pack = if def then makePack(def) else nil
		v.packDef = def
		v.packId = packId
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

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if v.pack then
			if root then
				local cf = root.CFrame * CFrame.new(0, 0.3, 0.5 + v.packDef.Size.Z / 2)
				v.pack.CFrame = cf
				v.pack.Strap.CFrame = cf * CFrame.new(0, v.packDef.Size.Y * 0.2, 0)
				v.pack.Transparency = 0
				v.pack.Strap.Transparency = 0
			else
				v.pack.Transparency = 1
				v.pack.Strap.Transparency = 1
			end
		end

		if v.pet and root then
			local bob = math.sin(t * 3 + player.UserId % 7) * 0.4
			local target = root.CFrame * CFrame.new(3, 1.5 + bob, 2)
			local current = v.pet:GetPivot()
			-- Snap if far away (respawn/teleport), otherwise glide.
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
	if v then
		if v.pet then
			v.pet:Destroy()
		end
		if v.pack then
			v.pack:Destroy()
		end
		visuals[player] = nil
	end
end)

return Cosmetics
