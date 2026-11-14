--[[
	Cosmetics.luau
	Every player's equipped pets float around them (built locally from
	the "EquippedPets" attribute the server sets). Purely visual. Other
	players' pets can be hidden in Settings (Style.HideOtherPets).
	(Weapons and armor are welded to the character by the server.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PetBuilder = require(ReplicatedStorage.Shared.PetBuilder)
local Style = require(script.Parent.ui.Style)

local localPlayer = Players.LocalPlayer

local Cosmetics = {}

local folder = Instance.new("Folder")
folder.Name = "LocalCosmetics"
folder.Parent = Workspace

local visuals = {} -- [player] = { key = string, pets = { Model } }

local function clear(v)
	for _, pet in ipairs(v.pets) do
		pet:Destroy()
	end
	v.pets = {}
end

local function sync(v, player)
	local hidden = Style.HideOtherPets and player ~= localPlayer
	local key = if hidden then "" else (player:GetAttribute("EquippedPets") or "")
	if v.key == key then
		return
	end
	v.key = key
	clear(v)
	for entry in string.gmatch(key, "[^,]+") do
		local petId, tierText = string.match(entry, "^(%w+):(%d)$")
		local pet = petId and Config.PetById[petId]
		if pet then
			local model = PetBuilder.Build(pet, tonumber(tierText))
			model.Parent = folder
			table.insert(v.pets, model)
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local v = visuals[player]
		if not v then
			v = { key = nil, pets = {} }
			visuals[player] = v
		end
		sync(v, player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local count = #v.pets
		for i, pet in ipairs(v.pets) do
			if root then
				-- a fan behind the player
				local spread = if count > 1 then (i - 1) / (count - 1) - 0.5 else 0
				local bob = math.sin(t * 3 + i + player.UserId % 7) * 0.35
				local target = root.CFrame * CFrame.new(spread * 6, 1.4 + bob, 3.2 + math.abs(spread) * 1.5)
				local current = pet:GetPivot()
				if (current.Position - target.Position).Magnitude > 40 then
					pet:PivotTo(target)
				else
					pet:PivotTo(current:Lerp(target, math.min(1, dt * 7)))
				end
				local halo = pet:FindFirstChild("Halo")
				if halo and halo:GetAttribute("Rainbow") then
					halo.Color = Color3.fromHSV((t * 0.5 + i * 0.2) % 1, 0.7, 1)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local v = visuals[player]
	if v then
		clear(v)
	end
	visuals[player] = nil
end)

return Cosmetics
