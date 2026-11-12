--[[
	EquipmentService.luau
	Puts the equipped weapon in the character's right hand (WeldConstraint)
	for every rig type and rebuilds it when the player equips something
	else or respawns. Everyone sees it because the server builds it.

	Swings: on every accepted click the server bumps the character's
	"Swing" attribute; clients animate the arm (client Swing.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)

local EquipmentService = {}

local E = Config.Equipment

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
	local model = WeaponBuilder.Build(weapon)
	model.Name = "EquippedWeapon"
	model:SetAttribute("WeaponId", weapon.Id)
	model.Parent = character
	weld(hand, model.PrimaryPart, if isR15(character) then E.GripR15 else E.GripR6)
end

local function refreshAll(player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	refreshWeapon(player, character)
end
EquipmentService.Refresh = refreshAll

-- Called by ClickService after an accepted click.
function EquipmentService.Swing(player)
	local character = player.Character
	if character then
		character:SetAttribute("Swing", (character:GetAttribute("Swing") or 0) + 1)
	end
end

function EquipmentService.Init()
	local function onPlayer(player)
		player:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
			refreshAll(player)
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
