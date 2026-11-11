--[[
	RebirthService.luau
	Day 6: RebirthRequest:InvokeServer() -> (ok, message).

	Spends the rebirth cost, then resets Aura, weapons and backpacks.
	Gems, pets and the rebirth count are kept; the new rebirth count
	raises the permanent Aura multiplier (see Config.RebirthMultiplier).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Effects = require(script.Parent.Effects)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local RebirthService = {}

local function rebirth(player)
	local data = DataService.Get(player)
	if not data or not PlayerState.IsReady(player) then
		return false, "Данные ещё загружаются"
	end

	local cost = Config.RebirthCost(data.Rebirths)
	if PlayerState.GetAura(player) < cost then
		return false, "Нужно " .. Format.Number(cost) .. " Ауры"
	end

	data.Rebirths += 1
	PlayerState.SetAura(player, 0)
	data.OwnedWeapons = { Stick = true }
	data.EquippedWeapon = "Stick"
	data.OwnedBackpacks = {}
	data.EquippedBackpack = ""
	PlayerState.Sync(player)
	task.spawn(DataService.Save, player) -- big moment: don't wait for the autosave

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position, Color3.fromRGB(200, 140, 255), 120, 40, 1.6)
	end

	return true, ("Ребёрт %d! Аура теперь x%s"):format(
		data.Rebirths,
		tostring(PlayerState.AuraMultiplier(player))
	)
end

function RebirthService.Init()
	local remote = Remotes.Get("RebirthRequest")
	local allow = RateLimit.new(1)

	remote.OnServerInvoke = function(player)
		if not allow(player) then
			return false, "Слишком быстро"
		end
		return rebirth(player)
	end
end

return RebirthService
