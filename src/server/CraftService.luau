--[[
	CraftService.luau
	The forge. Craft:InvokeServer(recipeId) -> (ok, message).

	The server checks the recipe (Config.Recipes), that the item is not
	owned yet, the materials and the Aura fee; then takes them, grants
	the weapon / armor piece and equips it when it is an upgrade. On
	success the hub forge flares up for everyone nearby: the hearth
	flashes and sparks fly over the anvil (the craft animation itself is
	played by the client's Forge window).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local CraftService = {}

local Texts = Config.Forge.Texts
local forge -- hub Forge model

-- World effect seen by everyone near the forge.
local function flare()
	if not forge then
		return
	end
	local hearth = forge:FindFirstChild("Hearth")
	local anvil = forge:FindFirstChild("Anvil")
	if hearth then
		local glow = hearth:FindFirstChild("Glow")
		local fire = hearth:FindFirstChild("Fire")
		local sparks = hearth:FindFirstChild("Sparks")
		if glow then
			glow.Brightness = 6
			TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 1.6 }):Play()
		end
		if fire then
			fire.Size = 16
			TweenService:Create(fire, TweenInfo.new(1.6), { Size = 7 }):Play()
		end
		if sparks then
			sparks:Emit(40)
		end
	end
	local anvilSparks = anvil and anvil:FindFirstChild("Sparks")
	if anvilSparks then
		task.spawn(function()
			for _ = 1, Config.Forge.Strikes do
				anvilSparks:Emit(25)
				task.wait(0.35)
			end
		end)
	end
end

local function craft(player, recipeId)
	local data = DataService.Get(player)
	local recipe = if type(recipeId) == "string" then Config.RecipeById[recipeId] else nil
	if not data or not recipe or not PlayerState.IsReady(player) then
		return false, "Неверный запрос"
	end
	local owned = if recipe.Kind == "Weapon" then data.OwnedWeapons else data.OwnedArmor
	if owned[recipe.Id] then
		return false, Texts.Owned
	end
	if not PlayerState.HasMaterials(player, recipe.Materials) then
		return false, Texts.Missing
	end
	if not PlayerState.SpendAura(player, recipe.Aura) then
		return false, Texts.NoAura
	end
	for materialId, count in pairs(recipe.Materials) do
		PlayerState.AddMaterial(player, materialId, -count)
	end

	owned[recipe.Id] = true
	local item
	if recipe.Kind == "Weapon" then
		item = Config.ItemById.Weapon[recipe.Id]
		local current = Config.ItemById.Weapon[data.EquippedWeapon]
		if not current or item.Damage > current.Damage then
			data.EquippedWeapon = item.Id
		end
	else
		item = Config.ItemById.Armor[recipe.Id]
		local current = PlayerState.ArmorIn(player, item.Slot)
		if not current or item.Health > current.Health then
			data.EquippedArmor[item.Slot] = item.Id
		end
	end
	PlayerState.Sync(player)
	task.spawn(DataService.Save, player) -- crafted gear is precious: save right away
	flare()
	return true, Texts.Done:format(item.Name)
end

function CraftService.Init(hub)
	forge = hub.Forge
	local allow = RateLimit.new(0.5)
	Remotes.Get("Craft").OnServerInvoke = function(player, recipeId)
		if not allow(player) then
			return false, "Слишком быстро"
		end
		return craft(player, recipeId)
	end
end

return CraftService
