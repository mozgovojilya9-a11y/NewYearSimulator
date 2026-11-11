--[[
	ClickService.luau
	One RemoteEvent for every click on a target: ClickHit:FireServer(model).

	The client only says WHAT it clicked. The server checks:
	  - the target is a real dungeon mob or hub trainer,
	  - the player's character is within Config.Click.Range,
	  - the per-player cooldown (Config.Click.Cooldown, anti-macro),
	then rolls damage/crit itself and replies to that client:
	  ("Hit", mob, damage, isCrit)      -- DungeonService
	  ("Kill", position, auraGained)    -- DungeonService
	  ("Train", trainer, aura, isCrit)  -- trainers
	Numbers sent by the client are never used.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonService = require(script.Parent.DungeonService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local ClickService = {}

local trainersFolder = nil

local function isTrainer(target)
	return trainersFolder ~= nil and target.Parent == trainersFolder
end

-- trainers: the Hub.Trainers folder from HubGenerator (may be nil).
function ClickService.Init(trainers: Folder?)
	trainersFolder = trainers
	local remote = Remotes.Get("ClickHit")
	local allow = RateLimit.new(Config.Click.Cooldown)

	remote.OnServerEvent:Connect(function(player, target)
		if typeof(target) ~= "Instance" or not target:IsA("Model") then
			return
		end
		local mob = DungeonService.IsMob(target)
		if not mob and not isTrainer(target) then
			return
		end
		if not PlayerState.IsReady(player) then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - target:GetPivot().Position).Magnitude > Config.Click.Range then
			return
		end
		if not allow(player) then
			return
		end

		if mob then
			DungeonService.Hit(player, target)
		else
			local amount, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player) * Config.Hub.TrainerRate)
			local gained = PlayerState.GiveAura(player, amount)
			remote:FireClient(player, "Train", target, gained, isCrit)
		end
	end)
end

return ClickService
