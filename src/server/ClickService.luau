--[[
	ClickService.luau
	The attack. Every click / tap on the screen (not on UI) is one
	ClickHit:FireServer(mob?). The server:
	  - applies the per-player cooldown (Config.Click.Cooldown divided by
	    the AttackSpeed stat, anti-macro),
	  - swings the weapon (everyone sees it),
	  - in a dungeon run hits a mob: the one the client pointed at (if it
	    is a real mob of this player's run within Config.Click.Range) or
	    the nearest one within Config.Click.MeleeRange.
	A click gives nothing by itself (no clicker income): progress comes
	from kills, quests, gear and levels.
	Replies to that client:
	  ("Hit", mob, damage, isCrit)         -- DungeonRuns
	  ("Kill", position, isBoss)           -- DungeonRuns
	  ("Credits", amount, position)        -- ProgressionService
	  ("Dummy", model, damage, isCrit)     -- PolygonService (hub dummies)
	Numbers sent by the client are never used.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonRuns = require(script.Parent.DungeonRuns)
local EquipmentService = require(script.Parent.EquipmentService)
local PlayerState = require(script.Parent.PlayerState)
local PolygonService = require(script.Parent.PolygonService)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)

local ClickService = {}

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
	else
		-- Hub: test dummies on the Polygon (no rewards, numbers only).
		local dummy = nil
		if PolygonService.IsDummy(target) and (root.Position - target:GetPivot().Position).Magnitude <= Config.Polygon.Range then
			dummy = target
		else
			dummy = PolygonService.Nearest(root.Position, Config.Click.MeleeRange)
		end
		if dummy then
			PolygonService.Hit(player, dummy)
		end
	end
end

function ClickService.Init()
	local remote = Remotes.Get("ClickHit")
	-- Cooldown depends on the player's AttackSpeed stat.
	local lastClick = {}
	remote.OnServerEvent:Connect(function(player, target)
		local now = os.clock()
		if now - (lastClick[player] or 0) >= StatService.ClickCooldown(player) * 0.9 then
			lastClick[player] = now
			click(player, target)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClick[player] = nil
	end)
end

return ClickService
