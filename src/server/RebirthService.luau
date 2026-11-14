--[[
	RebirthService.luau
	RebirthRequest:InvokeServer() -> (ok, message). Opened from the hub
	altar, but the server re-checks everything.

	Requirement: Aura >= Config.RebirthAura(rebirths).
	Resets Aura and the room record; keeps level, weapons, armor,
	materials, pets, credits. Rebirths + 1 -> permanent training
	multiplier Config.RebirthMultiplier(n).
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
	local need = Config.RebirthAura(data.Rebirths)
	if PlayerState.GetAura(player) < need then
		return false, ("Нужно %s Ауры (сейчас %s)"):format(Format.Number(need), Format.Number(PlayerState.GetAura(player)))
	end

	data.Rebirths += 1
	PlayerState.SetAura(player, 0)
	data.RoomReached = 0
	PlayerState.Sync(player)
	task.spawn(DataService.Save, player) -- big moment: don't wait for the autosave

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position, Color3.fromRGB(200, 140, 255), 120, 40, 1.6)
	end

	return true, ("Ребёрт %d! Тренировка навсегда x%s"):format(
		data.Rebirths,
		Format.Decimal(Config.RebirthMultiplier(data.Rebirths))
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
