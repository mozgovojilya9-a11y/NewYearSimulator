--[[
	HubService.luau
	Builds the hub and wires its prompts:
	- Weapon stand prompt: buys the unique weapon (or equips it if already
	  owned) through ShopService with fromStand = true.
	- The rebirth altar prompt is handled on the client (it only opens a
	  window); the rebirth itself goes through RebirthService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local HubGenerator = require(script.Parent.HubGenerator)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local ShopService = require(script.Parent.ShopService)

local HubService = {}

-- Returns the hub description from HubGenerator.Build().
function HubService.Init()
	local hub = HubGenerator.Build()
	local allow = RateLimit.new(0.5)

	for _, prompt in ipairs(hub.StandPrompts) do
		local weaponId = prompt:GetAttribute("WeaponId")
		prompt.Triggered:Connect(function(player)
			if not allow(player) then
				return
			end
			local data = DataService.Get(player)
			if not data or not Config.ItemById.Weapon[weaponId] then
				return
			end
			local action = if data.OwnedWeapons[weaponId] then "Equip" else "Buy"
			local ok, message = ShopService.Handle(player, action, "Weapon", weaponId, true)
			Remotes.Notify(player, message, if ok then "gold" else "bad")
		end)
	end

	return hub
end

return HubService
