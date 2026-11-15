--[[
	EquipmentService.luau
	What the character wears, built by the server so everyone sees it:
	- the equipped weapon in the right hand (WeldConstraint, R6 and R15),
	- the equipped armor pieces welded to the head / torso / shins
	  (Shared.ArmorBuilder),
	- max health from armor (player attribute "MaxHealth").
	Rebuilt when the player equips something else or respawns.

	Swings: on every accepted click / trainer tick the server bumps the
	character's "Swing" attribute; clients animate the arm (Swing.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ArmorBuilder = require(ReplicatedStorage.Shared.ArmorBuilder)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)

local EquipmentService = {}

local E = Config.Equipment
local refreshShield

local function isR15(character): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
end

local function weld(part0: BasePart, part1: BasePart, offset: CFrame)
	part1.CFrame = part0.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part1
end

-- Клинок carries an energy shield on the left arm.
refreshShield = function(player, character)
	local old = character:FindFirstChild("EnergyShield")
	if old then
		old:Destroy()
	end
	if player:GetAttribute("Class") ~= "Blade" then
		return
	end
	local arm = character:FindFirstChild(if isR15(character) then "LeftLowerArm" else "Left Arm")
	if not arm then
		return
	end
	local S = E.Shield
	local model = Instance.new("Model")
	model.Name = "EnergyShield"
	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Shape = Enum.PartType.Cylinder
	plate.Size = Vector3.new(0.12, S.Size, S.Size)
	plate.Color = S.Color
	plate.Material = Enum.Material.ForceField
	plate.Transparency = 0.15
	plate.CanCollide = false
	plate.CanQuery = false
	plate.Massless = true
	plate.Parent = model
	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(0.2, 0.9, 0.9)
	rim.Color = Color3.fromRGB(70, 74, 84)
	rim.Material = Enum.Material.Metal
	rim.CanCollide = false
	rim.CanQuery = false
	rim.Massless = true
	rim.Parent = model
	model.PrimaryPart = rim
	model.Parent = character
	weld(arm, rim, S.Offset)
	weld(rim, plate, CFrame.new(-0.08, 0, 0))
end

local function refreshWeapon(player, character)
	local old = character:FindFirstChild("EquippedWeapon")
	if old then
		old:Destroy()
	end
	local weapon = Config.ItemById.Weapon[player:GetAttribute("EquippedWeapon") or ""]
	local hand = character:FindFirstChild(if isR15(character) then "RightHand" else "Right Arm")
	if not weapon or not hand then
		return
	end
	-- the look follows the player's class (sword / spear / blaster)
	local classId = player:GetAttribute("Class") or ""
	local look = weapon
	if Config.ClassById[classId] and weapon.Class ~= classId then
		look = table.clone(weapon)
		look.Class = classId
	end
	local model = WeaponBuilder.Build(look)
	model.Name = "EquippedWeapon"
	model:SetAttribute("WeaponId", weapon.Id)
	model.Parent = character
	weld(hand, model.PrimaryPart, if isR15(character) then E.GripR15 else E.GripR6)
	refreshShield(player, character)
end

local function refreshArmor(player, character)
	for _, slot in ipairs(Config.ArmorSlots) do
		local id = player:GetAttribute("Equipped" .. slot) or ""
		local name = "Armor_" .. slot
		local old = character:FindFirstChild(name)
		if not old or old:GetAttribute("ArmorId") ~= id then
			if old then
				old:Destroy()
			end
			local piece = Config.ItemById.Armor[id]
			if piece then
				ArmorBuilder.Attach(character, piece)
			end
		end
	end
end

-- Max health follows the armor; the current health keeps its share.
local function refreshHealth(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local maxHealth = player:GetAttribute("MaxHealth")
	if humanoid and maxHealth and humanoid.MaxHealth ~= maxHealth then
		local share = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = maxHealth
		if humanoid.Health > 0 then
			humanoid.Health = math.max(1, maxHealth * share)
		end
	end
end

local function refreshAll(player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	refreshWeapon(player, character)
	refreshArmor(player, character)
	refreshHealth(player, character)
end
EquipmentService.Refresh = refreshAll

-- Called after an accepted click / trainer tick.
function EquipmentService.Swing(player)
	local character = player.Character
	if character then
		character:SetAttribute("Swing", (character:GetAttribute("Swing") or 0) + 1)
	end
end

function EquipmentService.Init()
	local function onPlayer(player)
		local function onCharacter()
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				return character
			end
			return nil
		end
		player:GetAttributeChangedSignal("Class"):Connect(function()
			local character = onCharacter()
			if character then
				refreshWeapon(player, character)
			end
		end)
		player:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
			local character = onCharacter()
			if character then
				refreshWeapon(player, character)
			end
		end)
		for _, slot in ipairs(Config.ArmorSlots) do
			player:GetAttributeChangedSignal("Equipped" .. slot):Connect(function()
				local character = onCharacter()
				if character then
					refreshArmor(player, character)
				end
			end)
		end
		player:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			local character = onCharacter()
			if character then
				refreshHealth(player, character)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2) -- let the rig finish assembling
			refreshAll(player)
		end)
		if player.Character then
			task.defer(refreshAll, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return EquipmentService
