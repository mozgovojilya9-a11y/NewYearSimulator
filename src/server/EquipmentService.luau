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
local Items = require(ReplicatedStorage.Shared.Items)
local ArmorBuilder = require(ReplicatedStorage.Shared.ArmorBuilder)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local PlayerState = require(script.Parent.PlayerState)

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
	local weapon = PlayerState.Weapon(player)
	local hand = character:FindFirstChild(if isR15(character) then "RightHand" else "Right Arm")
	if not weapon or not hand then
		return
	end
	-- a class-free weapon (starter, old saves) looks like the class weapon
	local look = Items.LookFor(weapon, player:GetAttribute("Class"))
	local model = WeaponBuilder.Build(look)
	model.Name = "EquippedWeapon"
	model:SetAttribute("WeaponId", weapon.Id)
	model.Parent = character
	local classGrip = E.GripClass and E.GripClass[player:GetAttribute("Class") or ""]
	weld(hand, model.PrimaryPart, if isR15(character) then (classGrip or E.GripR15) else E.GripR6)
	refreshShield(player, character)
end

-- Armor replaces the avatar's own clothes and accessories where it sits
-- (a costume made of layered clothing would cover the armor): helmet ->
-- hats / hair / face, chest -> jackets, shirts, shoulder and back items,
-- legs -> pants and shoes. Taking the armor off shows them again.
local ACCESSORY_SLOT = {
	[Enum.AccessoryType.Hat] = "Helmet", [Enum.AccessoryType.Hair] = "Helmet", [Enum.AccessoryType.Face] = "Helmet",
	[Enum.AccessoryType.Eyebrow] = "Helmet", [Enum.AccessoryType.Eyelash] = "Helmet",
	[Enum.AccessoryType.Neck] = "Chest", [Enum.AccessoryType.Shoulder] = "Chest", [Enum.AccessoryType.Front] = "Chest",
	[Enum.AccessoryType.Back] = "Chest", [Enum.AccessoryType.Waist] = "Chest", [Enum.AccessoryType.Jacket] = "Chest",
	[Enum.AccessoryType.Sweater] = "Chest", [Enum.AccessoryType.Shirt] = "Chest", [Enum.AccessoryType.TShirt] = "Chest",
	[Enum.AccessoryType.Pants] = "Legs", [Enum.AccessoryType.Shorts] = "Legs", [Enum.AccessoryType.DressSkirt] = "Legs",
	[Enum.AccessoryType.LeftShoe] = "Legs", [Enum.AccessoryType.RightShoe] = "Legs",
}
local ATTACHMENT_SLOT = {
	HatAttachment = "Helmet", HairAttachment = "Helmet", FaceFrontAttachment = "Helmet", FaceCenterAttachment = "Helmet",
	NeckAttachment = "Chest", BodyFrontAttachment = "Chest", BodyBackAttachment = "Chest", LeftCollarAttachment = "Chest",
	RightCollarAttachment = "Chest", LeftShoulderAttachment = "Chest", RightShoulderAttachment = "Chest",
	WaistFrontAttachment = "Chest", WaistBackAttachment = "Chest", WaistCenterAttachment = "Chest",
	LeftFootAttachment = "Legs", RightFootAttachment = "Legs",
}

local function accessorySlot(accessory: Accessory): string?
	local slot = ACCESSORY_SLOT[accessory.AccessoryType]
	if slot then
		return slot
	end
	local handle = accessory:FindFirstChild("Handle")
	local attachment = handle and handle:FindFirstChildWhichIsA("Attachment")
	return attachment and ATTACHMENT_SLOT[attachment.Name]
end

local function hideUnderArmor(player, character)
	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA("Accessory") then
			local slot = accessorySlot(accessory)
			local covered = slot ~= nil and PlayerState.ArmorIn(player, slot) ~= nil
			for _, part in ipairs(accessory:GetDescendants()) do
				if part:IsA("BasePart") then
					local original = part:GetAttribute("ArmorOrigT")
					if covered then
						if original == nil then
							part:SetAttribute("ArmorOrigT", part.Transparency)
						end
						part.Transparency = 1
					elseif original ~= nil then
						part.Transparency = original
						part:SetAttribute("ArmorOrigT", nil)
					end
				end
			end
		end
	end
	-- classic shirts / pants stay under the armor anyway (the shells cover them)
end

local function refreshArmor(player, character)
	for _, slot in ipairs(Config.ArmorSlots) do
		local piece = PlayerState.ArmorIn(player, slot)
		local classId = player:GetAttribute("Class") or ""
		-- the look follows the item (rarity, enhance) and the class (silhouette)
		local key = if piece then piece.Id .. "|" .. (player:GetAttribute("Look" .. slot) or "") .. "|" .. classId else ""
		local name = "Armor_" .. slot
		local old = character:FindFirstChild(name)
		if not old or old:GetAttribute("LookKey") ~= key then
			if old then
				old:Destroy()
			end
			if piece then
				local model = ArmorBuilder.Attach(character, piece, classId)
				if model then
					model:SetAttribute("LookKey", key)
				end
			end
		end
	end
	hideUnderArmor(player, character)
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

-- An action every client animates (Swing.luau): "Act" = "<name>#<n>",
-- name = Combo1..3 / Shot1 / Shot2 / Charged / an ability Kind / Dash /
-- Hurt (Config.Animations.Acts).
function EquipmentService.Act(player, name: string)
	local character = player.Character
	if character then
		local n = (character:GetAttribute("ActN") or 0) + 1
		character:SetAttribute("ActN", n)
		character:SetAttribute("Act", name .. "#" .. n)
	end
end

-- Called after an accepted attack / ability (weapon trail + the action).
function EquipmentService.Swing(player, act: string?)
	local character = player.Character
	if character then
		if act then
			EquipmentService.Act(player, act)
		end
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
				refreshArmor(player, character) -- the armor silhouette follows the class
			end
		end)
		for _, attribute in ipairs({ "EquippedWeapon", "LookWeapon" }) do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				local character = onCharacter()
				if character then
					refreshWeapon(player, character)
				end
			end)
		end
		for _, slot in ipairs(Config.ArmorSlots) do
			for _, attribute in ipairs({ "Equipped" .. slot, "Look" .. slot }) do
				player:GetAttributeChangedSignal(attribute):Connect(function()
					local character = onCharacter()
					if character then
						refreshArmor(player, character)
					end
				end)
			end
		end
		player:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			local character = onCharacter()
			if character then
				refreshHealth(player, character)
			end
		end)
		local function watchAccessories(character)
			-- avatar accessories arrive a bit later than the rig
			character.ChildAdded:Connect(function(child)
				if child:IsA("Accessory") then
					task.defer(hideUnderArmor, player, character)
				end
			end)
		end
		player.CharacterAdded:Connect(function(character)
			watchAccessories(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2) -- let the rig finish assembling
			refreshAll(player)
		end)
		if player.Character then
			watchAccessories(player.Character)
			task.defer(refreshAll, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return EquipmentService
