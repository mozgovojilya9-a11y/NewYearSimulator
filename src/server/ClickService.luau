--[[
	ClickService.luau
	The attack. Every click / tap on the screen (not on UI) is one
	ClickHit:FireServer(mob?). The server:
	  - applies the per-player cooldown (Config.Click.Cooldown divided by
	    the AttackSpeed stat, anti-macro),
	  - swings the weapon (everyone sees it),
	  - attacks with the class style (AbilityService.Basic): the mob or
	    dummy the client pointed at if it is in range, else the nearest;
	    `charged` = the Стрелок held the attack (checked on the server).
	A click gives nothing by itself (no clicker income): progress comes
	from kills, quests, gear and levels.
	Replies to that client:
	  ("Hit", mob, damage, isCrit)         -- DungeonRuns
	  ("Kill", position, isBoss)           -- DungeonRuns
	  ("Credits", amount, position)        -- ProgressionService
	Numbers sent by the client are never used.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityService = require(script.Parent.AbilityService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)

local ClickService = {}

local function click(player, target, charged)
	if not PlayerState.IsReady(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- the swing / shot animation is started inside (it knows the combo step)
	-- Class attacks (combo / 360 / shots) on run mobs in the dungeon and
	AbilityService.Basic(player, target, charged == true)
end

function ClickService.Init()
	local remote = Remotes.Get("ClickHit")
	-- Cooldown depends on the player's AttackSpeed stat.
	local lastClick = {}
	remote.OnServerEvent:Connect(function(player, target, charged)
		local now = os.clock()
		if now - (lastClick[player] or 0) >= StatService.ClickCooldown(player) / AbilityService.AttackSpeedMult(player) * 0.9 then
			lastClick[player] = now
			click(player, target, charged)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClick[player] = nil
	end)
end

return ClickService
