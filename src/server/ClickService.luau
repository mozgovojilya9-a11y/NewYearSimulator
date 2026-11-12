--[[
	ClickService.luau
	Every click / tap anywhere on the screen is one ClickHit:FireServer(mob?)
	(the client sends it only when the click was not on UI). The server:
	  - applies the per-player cooldown (Config.Click.Cooldown, anti-macro),
	  - swings the weapon (everyone sees it),
	  - gives Aura: Config.Aura.ClickBase, plus the trainer bonus when the
	    server says the player stands on a trainer ("OnTrainer"),
	  - in a dungeon run hits a mob: the one the client pointed at (if it
	    is a real mob of this player's run within Config.Click.Range) or
	    the nearest one within Config.Click.MeleeRange.
	Replies to that client:
	  ("Aura", gained, isCrit, trainerModel?)
	  ("Tick", trainerModel, gained)       -- HubService, automatic income
	  ("Hit", mob, damage, isCrit)         -- DungeonRuns
	  ("Kill", position, isBoss)           -- DungeonRuns
	Numbers sent by the client are never used.

	Auto-click is a server loop (Config.Aura.AutoClickInterval): the client
	only toggles it. Without the AutoClick pass it works on trainers only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonRuns = require(script.Parent.DungeonRuns)
local EquipmentService = require(script.Parent.EquipmentService)
local HubService = require(script.Parent.HubService)
local Passes = require(script.Parent.Passes)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local ClickService = {}

local A = Config.Aura

local autoClick = {} -- [player] = true
local remote

ClickService.OnTrainerClick = nil -- set by Main (daily quests)

local function click(player, target)
	if not PlayerState.IsReady(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	EquipmentService.Swing(player)

	-- Aura for the click itself (+ trainer bonus).
	local base = A.ClickBase
	local trainer = HubService.TrainerOf(player)
	if trainer then
		base += A.TrainerClickBonus * trainer.def.Multiplier
		if ClickService.OnTrainerClick then
			ClickService.OnTrainerClick(player)
		end
	end
	local amount, isCrit = PlayerState.RollCrit(base)
	local gained = PlayerState.GiveAura(player, amount)
	remote:FireClient(player, "Aura", gained, isCrit, if trainer then trainer.model else nil)

	-- Combat: only inside the player's own run.
	if DungeonRuns.HasRun(player) then
		local mob = nil
		if typeof(target) == "Instance" and target:IsA("Model") and DungeonRuns.IsMob(target) then
			if (root.Position - target:GetPivot().Position).Magnitude <= Config.Click.Range then
				mob = target
			end
		end
		if not mob then
			mob = DungeonRuns.NearestMob(player, root.Position, Config.Click.MeleeRange)
		end
		if mob then
			DungeonRuns.Hit(player, mob)
		end
	end
end

function ClickService.Init()
	remote = Remotes.Get("ClickHit")
	local allow = RateLimit.new(Config.Click.Cooldown)
	remote.OnServerEvent:Connect(function(player, target)
		if allow(player) then
			click(player, target)
		end
	end)

	local toggleAllow = RateLimit.new(0.2)
	Remotes.Get("AutoClick").OnServerEvent:Connect(function(player, enabled)
		if not toggleAllow(player) then
			return
		end
		autoClick[player] = if enabled == true then true else nil
		player:SetAttribute("AutoClick", enabled == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		autoClick[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(A.AutoClickInterval)
			for player in pairs(autoClick) do
				if player.Parent and (HubService.TrainerOf(player) or Passes.Owns(player, "AutoClick")) then
					click(player, nil)
				end
			end
		end
	end)
end

return ClickService
