--[[
	HubService.luau
	Builds the hub and runs the trainers.

	Which trainer a player stands on is decided ONLY by the server, by
	coordinates: every Config.Aura.TrainerCheckInterval seconds the
	character position is compared with each trainer's square territory
	(no Touched / TouchEnded, they are unreliable). The result is the
	player attribute "OnTrainer" = trainer id or nil; it is set only for
	trainers the player has unlocked.

	While "OnTrainer" is set the player receives Aura automatically every
	Config.Aura.TrainerTickInterval seconds (base x trainer multiplier);
	clicks add a bonus on top (ClickService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local EquipmentService = require(script.Parent.EquipmentService)
local HubGenerator = require(script.Parent.HubGenerator)
local Passes = require(script.Parent.Passes)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)

local HubService = {}

local A = Config.Aura

local hub
local trainers = {} -- [id] = { def, model, center: Vector3, half: number }

function HubService.TrainerUnlocked(player, def): boolean
	local data = DataService.Get(player)
	if not def or not data then
		return false
	end
	if def.Pass then
		return Passes.Owns(player, def.Pass)
	end
	if def.Rebirths and data.Rebirths < def.Rebirths then
		return false
	end
	if def.Aura and not data.TrainersUnlocked[def.Id] and PlayerState.GetAura(player) < def.Aura then
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
	for _, def in ipairs(Config.Trainers) do
		if def.Aura and not data.TrainersUnlocked[def.Id] and PlayerState.GetAura(player) >= def.Aura then
			data.TrainersUnlocked[def.Id] = true
			changed = true
			Remotes.Notify(player, ("Тренажёр x%s «%s» открыт!"):format(tostring(def.Multiplier), def.Name), "gold")
		end
	end
	if changed then
		PlayerState.Sync(player)
	end
end

local function trainerAt(position: Vector3)
	for _, trainer in pairs(trainers) do
		local d = position - trainer.center
		if math.abs(d.X) <= trainer.half and math.abs(d.Z) <= trainer.half and d.Y > -1 and d.Y < 14 then
			return trainer
		end
	end
	return nil
end

-- The trainer record ({ def, model, ... }) the player is training on, or nil.
function HubService.TrainerOf(player)
	local id = player:GetAttribute("OnTrainer")
	return if id then trainers[id] else nil
end

local function detect()
	for _, player in ipairs(Players:GetPlayers()) do
		local found = nil
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and PlayerState.IsReady(player) then
			local trainer = trainerAt(root.Position)
			if trainer and HubService.TrainerUnlocked(player, trainer.def) then
				found = trainer.def.Id
			end
		end
		if player:GetAttribute("OnTrainer") ~= found then
			player:SetAttribute("OnTrainer", found)
		end
	end
end

local function tick(remote)
	for _, player in ipairs(Players:GetPlayers()) do
		local trainer = HubService.TrainerOf(player)
		if trainer and PlayerState.IsReady(player) then
			local gained = PlayerState.GiveAura(player, A.TrainerTickBase * trainer.def.Multiplier)
			EquipmentService.Swing(player)
			remote:FireClient(player, "Tick", trainer.model, gained)
		end
	end
end

function HubService.Init()
	hub = HubGenerator.Build()
	for _, model in ipairs(hub.Trainers:GetChildren()) do
		local def = Config.TrainerById[model:GetAttribute("TrainerId")]
		if def then
			trainers[def.Id] = { def = def, model = model, center = model:GetAttribute("Center"), half = model:GetAttribute("Half") + 0.5 }
		end
	end

	task.spawn(function()
		while true do
			task.wait(A.TrainerCheckInterval)
			detect()
		end
	end)

	local remote = Remotes.Get("ClickHit")
	task.spawn(function()
		while true do
			task.wait(A.TrainerTickInterval)
			tick(remote)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(2)
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
