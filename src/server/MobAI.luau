--[[
	MobAI.luau
	Brains for dungeon mobs (one tick every Config.Dungeon.Mob tick):
	- see the run's player within AggroRange -> Humanoid:MoveTo them,
	- within AttackRange -> telegraph (model attribute "Telegraph", the
	  client flashes it red) then hit the player's Humanoid,
	- bosses additionally slam the ground every BossSlamEvery seconds:
	  a red warning circle appears for BossSlamWarning seconds, then
	  everyone still inside takes heavy damage (you can run out).
	Also handles the player's out-of-combat health regeneration.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonRuns = require(script.Parent.DungeonRuns)
local WorldKit = require(script.Parent.WorldKit)

local MobAI = {}

local M = Config.Dungeon.Mob
local P = Config.Player
local TICK = 0.3

local mobs = {} -- [model] = { run, humanoid, root, lastAttack, busy, lastSlam }
local lastDamaged = {} -- [player] = os.clock() of the last hit taken

local function damagePlayer(player, amount: number)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
		lastDamaged[player] = os.clock()
	end
end

local function playerRoot(run)
	local character = run.player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function attack(state, model, root)
	state.busy = true
	model:SetAttribute("Telegraph", true)
	task.wait(M.TelegraphSeconds)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		local target = playerRoot(state.run)
		if target and (target.Position - state.root.Position).Magnitude <= M.AttackRange + 2 then
			damagePlayer(state.run.player, model:GetAttribute("Damage") or 1)
		end
	end
	state.lastAttack = os.clock()
	state.busy = false
end

local function slam(state, model)
	state.busy = true
	local center = state.root.Position
	local groundY = center.Y - state.root.Size.Y / 2 - (state.humanoid.HipHeight or 0)
	local warning = WorldKit.Part(Workspace, {
		Name = "SlamWarning",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, M.BossSlamRadius * 2, M.BossSlamRadius * 2),
		CFrame = CFrame.new(center.X, groundY + 0.3, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.Theme.Red,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	TweenService:Create(warning, TweenInfo.new(M.BossSlamWarning, Enum.EasingStyle.Linear), { Transparency = 0.15 }):Play()
	task.wait(M.BossSlamWarning)
	warning:Destroy()
	if mobs[model] and model.Parent then
		local flash = WorldKit.Part(Workspace, {
			Name = "SlamHit",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, M.BossSlamRadius * 2, M.BossSlamRadius * 2),
			CFrame = CFrame.new(center.X, groundY + 0.4, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Config.Theme.Gold,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		TweenService:Create(flash, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		task.delay(0.4, flash.Destroy, flash)
		local target = playerRoot(state.run)
		if target then
			local flat = Vector3.new(target.Position.X - center.X, 0, target.Position.Z - center.Z)
			if flat.Magnitude <= M.BossSlamRadius then
				damagePlayer(state.run.player, (model:GetAttribute("Damage") or 1) * M.BossSlamDamageMultiplier)
			end
		end
	end
	state.lastSlam = os.clock()
	state.busy = false
end

local function tick()
	local now = os.clock()
	for model, state in pairs(mobs) do
		if not model.Parent or state.humanoid.Health <= 0 then
			mobs[model] = nil
			continue
		end
		if state.busy then
			continue
		end
		local target = playerRoot(state.run)
		if not target then
			continue
		end
		local distance = (target.Position - state.root.Position).Magnitude
		local isBoss = model:GetAttribute("Boss") == true

		if isBoss and distance <= M.AggroRange and now - state.lastSlam >= M.BossSlamEvery then
			state.humanoid:MoveTo(state.root.Position)
			task.spawn(slam, state, model)
		elseif distance <= M.AttackRange then
			state.humanoid:MoveTo(state.root.Position)
			if now - state.lastAttack >= M.AttackCooldown then
				task.spawn(attack, state, model, state.root)
			end
		elseif distance <= M.AggroRange then
			state.humanoid.WalkSpeed = if isBoss then M.BossWalkSpeed else M.WalkSpeed
			state.humanoid:MoveTo(target.Position)
		else
			state.humanoid:MoveTo(state.root.Position)
		end
	end
end

-- Out-of-combat regeneration (the default Roblox Health script is
-- replaced by src/character/Health.server.luau, which does nothing).
local function regenerate()
	for _, player in ipairs(Players:GetPlayers()) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
			local since = os.clock() - (lastDamaged[player] or 0)
			if since >= P.RegenDelay then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + P.RegenPerSecond * TICK)
			end
		end
	end
end

function MobAI.Register(run, model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		return
	end
	pcall(root.SetNetworkOwner, root, nil) -- the server drives mobs
	mobs[model] = { run = run, humanoid = humanoid, root = root, lastAttack = 0, lastSlam = os.clock(), busy = false }
end

function MobAI.Unregister(model)
	mobs[model] = nil
end

function MobAI.Init()
	DungeonRuns.OnMobSpawned = MobAI.Register
	DungeonRuns.OnMobRemoved = MobAI.Unregister
	Players.PlayerRemoving:Connect(function(player)
		lastDamaged[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			tick()
			regenerate()
		end
	end)
end

return MobAI
