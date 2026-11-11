--[[
	RebirthService.luau
	RebirthRequest:InvokeServer() -> (ok, message). Opened from the hub
	altar, but the server re-checks everything.

	Requirement: RoomReached >= Config.RebirthRequirement.
	Resets Aura, weapons, backpacks and dungeon progress; keeps pets.
	Rebirths + 1 -> permanent multiplier Config.RebirthMultiplier(n).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
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
	if data.RoomReached < Config.RebirthRequirement then
		return false, ("Сначала пройди комнату %d (сейчас: %d)"):format(Config.RebirthRequirement, data.RoomReached)
	end

	data.Rebirths += 1
	PlayerState.SetAura(player, 0)
	data.OwnedWeapons = { Stick = true }
	data.EquippedWeapon = "Stick"
	data.OwnedBackpacks = {}
	data.EquippedBackpack = ""
	data.RoomReached = 0
	PlayerState.Sync(player)
	task.spawn(DataService.Save, player) -- big moment: don't wait for the autosave

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position, Color3.fromRGB(200, 140, 255), 120, 40, 1.6)
	end

	return true, ("Ребёрт %d! Аура навсегда x%s"):format(
		data.Rebirths,
		tostring(Config.RebirthMultiplier(data.Rebirths))
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
