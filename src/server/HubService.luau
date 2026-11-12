--[[
	HubService.luau
	Builds the hub and runs the trainer logic: which platform a player
	stands on, whether it is unlocked (Config.Hub.TrainerRequirements)
	and the auto-click loop. Altar / shop / egg / wheel prompts only open
	client windows, so the client handles them (Prompts.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local HubGenerator = require(script.Parent.HubGenerator)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)

local HubService = {}

local hub
local trainerModels = {} -- [index] = Model
local autoClick = {} -- [player] = true

HubService.OnTrainerClick = nil -- set by ProgressionService (quests)

function HubService.TrainerUnlocked(player, index: number): boolean
	local req = Config.Hub.TrainerRequirements[index]
	local data = DataService.Get(player)
	if not req or not data then
		return false
	end
	if req.Aura and PlayerState.GetAura(player) < req.Aura and not data.TrainersUnlocked[tostring(index)] then
		return false
	end
	if req.Rebirths and data.Rebirths < req.Rebirths then
		return false
	end
	return true
end

-- Aura requirements unlock permanently once reached.
local function rememberUnlocks(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local changed = false
	for index in ipairs(Config.Hub.TrainerMultipliers) do
		if not data.TrainersUnlocked[tostring(index)] and HubService.TrainerUnlocked(player, index) then
			data.TrainersUnlocked[tostring(index)] = true
			changed = true
			if index > 1 then
				Remotes.Notify(player, ("Тренажёр x%s открыт!"):format(tostring(Config.Hub.TrainerMultipliers[index])), "gold")
			end
		end
	end
	if changed then
		PlayerState.Sync(player)
	end
end

function HubService.TrainerUnderPlayer(player): number?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	for index, model in ipairs(trainerModels) do
		local center = model:GetAttribute("Center")
		local radius = model:GetAttribute("Radius")
		local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		if flat.Magnitude <= radius + 1 and math.abs(root.Position.Y - center.Y) < 8 then
			return index
		end
	end
	return nil
end

function HubService.TrainerClick(player, index: number)
	if not HubService.TrainerUnlocked(player, index) then
		return nil
	end
	local multiplier = Config.Hub.TrainerMultipliers[index] or 1
	local amount, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player) * Config.Hub.TrainerRate * multiplier)
	local gained = PlayerState.GiveAura(player, amount)
	if HubService.OnTrainerClick then
		HubService.OnTrainerClick(player)
	end
	return gained, isCrit, trainerModels[index]
end

function HubService.TrainerIndexOf(model): number?
	return model and model:GetAttribute("Index")
end

function HubService.Init()
	hub = HubGenerator.Build()
	for _, model in ipairs(hub.Trainers:GetChildren()) do
		trainerModels[model:GetAttribute("Index")] = model
	end

	local remote = Remotes.Get("AutoClick")
	remote.OnServerEvent:Connect(function(player, enabled)
		autoClick[player] = if enabled == true then true else nil
		player:SetAttribute("AutoClick", enabled == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		autoClick[player] = nil
	end)
	local clickRemote = Remotes.Get("ClickHit")
	task.spawn(function()
		while true do
			task.wait(Config.Hub.AutoClickInterval)
			for player in pairs(autoClick) do
				if PlayerState.IsReady(player) then
					local index = HubService.TrainerUnderPlayer(player)
					if index then
						local gained, isCrit, model = HubService.TrainerClick(player, index)
						if gained then
							clickRemote:FireClient(player, "Train", model, gained, isCrit)
						end
					end
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerState.IsReady(player) then
					rememberUnlocks(player)
				end
			end
		end
	end)

	return hub
end

return HubService
