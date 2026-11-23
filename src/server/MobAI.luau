--[[
	MobAI.luau
	Brains of the gate enemies (Config.Enemies). Every attack warns first:
	  Melee   walks up, flashes red (model "Telegraph"), hits in front
	  Swarm   fast and weak, comes in packs, short wind-up
	  Ranged  keeps its distance, draws its shot line on the floor, fires
	          along it: whoever is still on the line is hit
	  Shield  slow, its energy shield blocks hits from the front
	          (DungeonRuns), bashes up close
	  Healer  stays away from the players and heals the most hurt ally
	          (green beam), never attacks
	  Bomber  runs at the player, flashes and blows itself up
	  Blinker blinks behind a far player, then strikes
	Elites (bigger, aura) also do a shockwave: a circle around them, and
	carry affixes (Config.Enemies.Affixes): Explosive, Vampire, Shielded,
	Swift, Summoner, Thorns (Thorns / Shielded live in DungeonRuns.Damage).
	Bosses: phase 2 (rage) at Config.Enemies.Boss.Phases of health (banner
	"ФАЗА 2", red glow, faster), special attacks every few seconds - Slam
	(circle around), Charge (rectangle, then a dash along it), Cone (fan in
	front), Wave (an energy ring runs out along the floor: jump over it),
	Barrage (circles under the players); from phase 2 also Volley (a fan
	of projectiles) and Summon (adds from the arena portals). Between
	specials the boss chases and hits. While "Intro" is set (the entrance
	cutscene) the boss does nothing.

	Section groups stand still on their post until a member comes within
	Config.Sections.Aggro studs or one of them is hit ("Awake"); then the
	whole group (same "Group" attribute) wakes with a short "!" reaction.

	A target = the nearest living member of the run. Stun / slow from the
	skills (StunUntil / SlowUntil) and the short hit stagger (StaggerUntil)
	stop or slow the brain. Also: the player's out-of-combat regeneration.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local AbilityService = require(script.Parent.AbilityService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local EquipmentService = require(script.Parent.EquipmentService)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)
local Telegraph = require(script.Parent.Telegraph)

local MobAI = {}

local E = Config.Enemies
local BOSS = E.Boss
local AFFIX = Config.AffixById
local P = Config.Player
local TICK = 0.2
local RED = E.TelegraphColor
local SECTIONS = Config.Sections

local mobs = {} -- [model] = state
local lastDamaged = {} -- [player] = os.clock() of the last hit taken
local lastHurt = {} -- [player] = os.clock() of the last flinch

local function now(): number
	return Workspace:GetServerTimeNow()
end

function MobAI.DamagePlayer(player, amount: number, attacker: Model?)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local taken = amount * (1 - StatService.Get(player).Defense) -- armor
		taken = AbilityService.Incoming(player, taken, attacker) -- dodge, shield, block, thorns, cheat death
		if taken > 0 then
			humanoid:TakeDamage(math.max(1, taken))
			-- Vampire elites drink what they deal
			local affixes = attacker and attacker.Parent and attacker:GetAttribute("Affixes")
			local mobHumanoid = affixes and affixes:find("Vampire", 1, true) and attacker:FindFirstChildOfClass("Humanoid")
			if mobHumanoid and mobHumanoid.Health > 0 then
				mobHumanoid.Health = math.min(mobHumanoid.MaxHealth, mobHumanoid.Health + taken * AFFIX.Vampire.Heal)
				require(script.Parent.WorldKit).UpdateHealth(attacker.PrimaryPart, mobHumanoid.Health, mobHumanoid.MaxHealth)
				AbilityService.Fx("Heal", attacker)
			end
			DungeonRuns.NoteDamageTaken(player, taken)
			-- the "hit taken" flinch (not too often, never over an attack)
			local t = os.clock()
			if t - (lastHurt[player] or 0) >= Config.Combat.HurtEvery then
				lastHurt[player] = t
				EquipmentService.Act(player, "Hurt")
			end
		end
		lastDamaged[player] = os.clock()
	end
end
local damagePlayer = MobAI.DamagePlayer

local function statusOf(model): (boolean, number)
	local t = now()
	local stunned = (model:GetAttribute("StunUntil") or 0) > t or (model:GetAttribute("StaggerUntil") or 0) > t
	local slow = if (model:GetAttribute("SlowUntil") or 0) > t then Config.Combat.SlowFactor else 1
	return stunned, slow
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

-- Nearest living member of the run: player, root, surface distance.
local function target(state)
	local best, bestRoot, bestDistance = nil, nil, math.huge
	for _, player in ipairs(DungeonRuns.Members(state.run)) do
		local root = rootOf(player)
		if root then
			local d = (root.Position - state.root.Position).Magnitude - state.reach
			if d < bestDistance then
				best, bestRoot, bestDistance = player, root, d
			end
		end
	end
	return best, bestRoot, bestDistance
end

local function groundOf(state): number
	return state.run.groundY or (state.root.Position.Y - 3)
end

local function face(state, position: Vector3)
	local p = state.root.Position
	local flat = Vector3.new(position.X, p.Y, position.Z)
	if (flat - p).Magnitude > 0.1 then
		state.root.CFrame = CFrame.lookAt(p, flat)
	end
end

local function stop(state)
	state.humanoid:MoveTo(state.root.Position)
end

local function membersIn(state, test)
	local list = {}
	for _, player in ipairs(DungeonRuns.Members(state.run)) do
		local root = rootOf(player)
		if root and test(root.Position) then
			table.insert(list, player)
		end
	end
	return list
end

---------------------------------------------------------------------
-- Basic attacks
---------------------------------------------------------------------

-- the strike: a short lunge at the target (Config.Enemies.Lunge)
local function lunge(state, targetRoot)
	local L = E.Lunge
	local from = state.root.Position
	local to = Vector3.new(targetRoot.Position.X, from.Y, targetRoot.Position.Z)
	local gap = (to - from).Magnitude - state.reach - 1.5
	if gap <= 0.2 or L.Distance <= 0 then
		return
	end
	local step = (to - from).Unit * math.min(L.Distance, gap)
	local look = CFrame.lookAt(from, to).Rotation
	local start = os.clock()
	while os.clock() - start < L.Seconds and state.root.Parent do
		local t = (os.clock() - start) / L.Seconds
		state.root.CFrame = CFrame.new(from + step * (1 - (1 - t) ^ 2)) * look
		task.wait()
	end
end

local function knock(player, fromPosition: Vector3, strength: number)
	local root = rootOf(player)
	if root then
		local away = root.Position - fromPosition
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 0.1 then
			Remotes.Get("ClickHit"):FireClient(player, "Knock", away.Unit * strength)
		end
	end
end

local function melee(state, model, role)
	state.busy = true
	model:SetAttribute("Telegraph", true)
	task.wait(role.Telegraph)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		local _, targetRoot = target(state)
		if targetRoot then
			lunge(state, targetRoot)
		end
		local player, _, distance = target(state)
		if player and distance <= role.Range + 2.5 then
			damagePlayer(player, model:GetAttribute("Damage") or 1, model)
			knock(player, state.root.Position, if state.elite or state.isBoss then E.Lunge.KnockElite else E.Lunge.Knock)
		end
	end
	state.recoverUntil = os.clock() + E.Recover -- a short pause after the strike
	state.lastAttack = os.clock()
	state.busy = false
end

-- World geometry only: mobs, players and effects never block a shot.
local function worldRay(state, from: Vector3, to: Vector3): RaycastResult?
	local ignore = { state.run.fxFolder }
	for _, other in ipairs(DungeonRuns.LiveMobs(state.run)) do
		table.insert(ignore, other)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return Workspace:Raycast(from, to - from, params)
end

-- Is there a clear line from the mob's gun to the target's chest?
local function canSee(state, root: BasePart): boolean
	local from = state.root.Position + Vector3.new(0, 1.5, 0)
	return worldRay(state, from, root.Position) == nil
end

-- A projectile flying from -> to: damage on arrival for whoever is still
-- in its path (`width`) by then. Walls stop it (to is clipped).
local function fireBolt(state, model, from: Vector3, to: Vector3, width: number, mult: number)
	local hit = worldRay(state, from, to)
	if hit then
		to = hit.Position
	end
	local P_ = E.Projectile
	local color = model:GetAttribute("Color") or RED
	AbilityService.Fx("Bolt", from, to, color, P_.Speed, P_.Size)
	local damage = (model:GetAttribute("Damage") or 1) * mult
	for _, player in ipairs(membersIn(state, function(p)
		return Telegraph.ToSegment(p, from, to) <= width / 2 + 1
	end)) do
		local root = rootOf(player)
		local along = if root then (root.Position - from).Magnitude else 0
		task.delay(along / P_.Speed, function()
			-- still in the path when it arrives?
			local r = rootOf(player)
			if r and Telegraph.ToSegment(r.Position, from, to) <= width / 2 + 1.5 then
				damagePlayer(player, damage, model)
			end
		end)
	end
end

local function shoot(state, model, role)
	state.busy = true
	local _, root = target(state)
	if not root then
		state.busy = false
		return
	end
	stop(state)
	face(state, root.Position)
	local from = state.root.Position + Vector3.new(0, 1.5, 0)
	local direction = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	local to = from + (if direction.Magnitude > 0.1 then direction.Unit else state.root.CFrame.LookVector) * role.Range
	to = Vector3.new(to.X, root.Position.Y, to.Z)
	local wall = worldRay(state, from, to)
	if wall then
		to = wall.Position -- the line on the floor ends at the wall too
	end
	model:SetAttribute("Telegraph", true)
	Telegraph.Line(state.run.fxFolder, from, to, role.Width, role.Telegraph, RED)
	task.wait(role.Telegraph)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		fireBolt(state, model, from, to, role.Width, 1)
	end
	state.lastAttack = os.clock()
	state.busy = false
end

local function heal(state, model, role)
	state.busy = true
	local best, worst = nil, 1
	for _, other in ipairs(DungeonRuns.LiveMobs(state.run)) do
		local humanoid = other:FindFirstChildOfClass("Humanoid")
		if other ~= model and humanoid and (other.PrimaryPart.Position - state.root.Position).Magnitude <= role.Range then
			local share = humanoid.Health / humanoid.MaxHealth
			if share < worst then
				best, worst = other, share
			end
		end
	end
	if best then
		local humanoid = best:FindFirstChildOfClass("Humanoid")
		AbilityService.Fx("Beam", state.root.Position + Vector3.new(0, 1, 0), best.PrimaryPart.Position, E.HealColor, 0.6)
		AbilityService.Fx("Heal", best)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * role.Heal)
		local gui = best.PrimaryPart:FindFirstChild("HealthGui")
		if gui then
			require(script.Parent.WorldKit).UpdateHealth(best.PrimaryPart, humanoid.Health, humanoid.MaxHealth)
		end
	end
	state.lastAttack = os.clock()
	task.wait(0.4)
	state.busy = false
end

-- Elite / boss: circle around the mob.
local function shockwave(state, model, radius: number, seconds: number, mult: number)
	state.busy = true
	stop(state)
	local center = Vector3.new(state.root.Position.X, groundOf(state), state.root.Position.Z)
	model:SetAttribute("Telegraph", true)
	Telegraph.Circle(state.run.fxFolder, center, radius, seconds, RED)
	task.wait(seconds)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		AbilityService.Fx("Ring", center, radius, Config.Theme.Gold)
		for _, player in ipairs(membersIn(state, function(p)
			return Telegraph.InCircle(p, center, radius)
		end)) do
			damagePlayer(player, (model:GetAttribute("Damage") or 1) * mult, model)
		end
	end
	state.busy = false
end

---------------------------------------------------------------------
-- New roles and elite affixes
---------------------------------------------------------------------

local function hasAffix(model, id: string): boolean
	local affixes = model:GetAttribute("Affixes")
	return affixes ~= nil and affixes:find(id, 1, true) ~= nil
end

-- A blast on the floor: red circle for `delay`, then damage inside.
local function blast(run, center: Vector3, radius: number, delay: number, damage: number, attacker)
	Telegraph.Circle(run.fxFolder, center, radius, delay, RED)
	task.delay(delay, function()
		AbilityService.Fx("Ring", center, radius, Config.Theme.Orange)
		for _, player in ipairs(DungeonRuns.Members(run)) do
			local root = rootOf(player)
			if root and Telegraph.InCircle(root.Position, center, radius) then
				damagePlayer(player, damage, if attacker and attacker.Parent then attacker else nil)
			end
		end
	end)
end

-- Bomber: stop, glow, blow up (it dies without loot).
local function selfDestruct(state, model, role)
	state.busy = true
	stop(state)
	local center = Vector3.new(state.root.Position.X, groundOf(state), state.root.Position.Z)
	model:SetAttribute("Telegraph", true)
	blast(state.run, center, role.Radius, role.Telegraph, model:GetAttribute("Damage") or 1, nil)
	task.wait(role.Telegraph)
	if mobs[model] and model.Parent then
		DungeonRuns.Kill(model)
	end
end

-- Blinker: a flash where it stands, a short wind-up, then it appears
-- behind the target, facing it.
local function blink(state, model, targetRoot)
	state.busy = true
	stop(state)
	local color = model:GetAttribute("Color") or Config.Theme.Magenta
	local from = state.root.Position
	AbilityService.Fx("Ring", Vector3.new(from.X, groundOf(state), from.Z), 4, color)
	model:SetAttribute("Telegraph", true)
	task.wait(0.35)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent and targetRoot.Parent then
		local behind = targetRoot.CFrame * CFrame.new(0, 0, 4)
		local spot = Vector3.new(behind.X, from.Y, behind.Z)
		model:PivotTo(CFrame.lookAt(spot, Vector3.new(targetRoot.Position.X, spot.Y, targetRoot.Position.Z)))
		AbilityService.Fx("Ring", Vector3.new(spot.X, groundOf(state), spot.Z), 4, color)
		state.lastAttack = os.clock() - state.role.Cooldown + 0.2 -- strikes almost at once
	end
	state.lastBlink = os.clock()
	state.busy = false
end

-- Elite affix timers: the Shielded bubble and Summoner adds.
local function eliteAffixes(state, model, clock: number)
	if hasAffix(model, "Shielded") and clock >= (state.nextBubble or 0) then
		local a = AFFIX.Shielded
		state.nextBubble = clock + a.Every
		model:SetAttribute("BubbleUntil", now() + a.Seconds)
		AbilityService.Fx("Shield", model, a.Seconds, a.Color)
	end
	if hasAffix(model, "Summoner") and clock >= (state.nextSummon or (clock + 3)) then
		local a = AFFIX.Summoner
		state.nextSummon = clock + a.Every
		state.adds = state.adds or {}
		local alive = {}
		for _, add in ipairs(state.adds) do
			if add.Parent and not add:GetAttribute("Dying") then
				table.insert(alive, add)
			end
		end
		state.adds = alive
		if #alive >= a.Count * 2 then
			return
		end
		local pool = {}
		for _, id in ipairs(state.run.location.Mobs) do
			local def = Config.Mobs.Defs[id]
			if def and (def.Role == "Swarm" or def.Role == "Bomber") then
				table.insert(pool, id)
			end
		end
		if #pool == 0 then
			pool = { state.run.location.Mobs[1] }
		end
		AbilityService.Fx("Ring", Vector3.new(state.root.Position.X, groundOf(state), state.root.Position.Z), 6, a.Color)
		for i = 1, a.Count do
			local angle = math.rad(i * 360 / a.Count)
			local at = state.root.Position + Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4)
			local add = DungeonRuns.SpawnMob(state.run, pool[state.run.rng:NextInteger(1, #pool)], Vector3.new(at.X, groundOf(state), at.Z), {
				Tier = model:GetAttribute("Room"),
				Zone = "Adds", -- not counted in the section
			})
			if add then
				table.insert(state.adds, add)
			end
		end
	end
end

---------------------------------------------------------------------
-- Boss specials
---------------------------------------------------------------------

local function charge(state, model)
	state.busy = true
	local _, root = target(state)
	if not root then
		state.busy = false
		return
	end
	stop(state)
	local c = BOSS.Charge
	face(state, root.Position)
	local start = Vector3.new(state.root.Position.X, groundOf(state), state.root.Position.Z)
	local look = Vector3.new(root.Position.X - start.X, 0, root.Position.Z - start.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, 1)
	local cf = CFrame.lookAt(start, start + look)
	model:SetAttribute("Telegraph", true)
	Telegraph.Rect(state.run.fxFolder, cf, c.Length, c.Width, c.Telegraph, RED)
	task.wait(c.Telegraph)
	model:SetAttribute("Telegraph", false)
	if not (mobs[model] and model.Parent) then
		state.busy = false
		return
	end
	-- the dash itself
	state.humanoid.WalkSpeed = c.Speed
	state.humanoid:MoveTo(start + look * c.Length)
	for _, player in ipairs(membersIn(state, function(p)
		return Telegraph.InRect(p, cf, c.Length, c.Width)
	end)) do
		damagePlayer(player, (model:GetAttribute("Damage") or 1) * c.Mult, model)
	end
	task.wait(c.Length / c.Speed + 0.1)
	state.humanoid.WalkSpeed = state.speed
	state.busy = false
end

local function barrage(state, model)
	state.busy = true
	stop(state)
	local b = BOSS.Barrage
	local spots = {}
	for _, player in ipairs(DungeonRuns.Members(state.run)) do
		local root = rootOf(player)
		if root then
			table.insert(spots, Vector3.new(root.Position.X, groundOf(state), root.Position.Z))
		end
	end
	local count = b.Count + (state.phase - 1) * b.PerPhase
	local center = state.run.map and state.run.map.Arena.Center or state.root.Position
	local half = (state.run.map and state.run.map.Arena.Size or 60) * 0.38
	while #spots < count do
		table.insert(spots, Vector3.new(center.X + state.run.rng:NextNumber(-half, half), groundOf(state), center.Z + state.run.rng:NextNumber(-half, half)))
	end
	model:SetAttribute("Telegraph", true)
	for _, spot in ipairs(spots) do
		Telegraph.Circle(state.run.fxFolder, spot, b.Radius, b.Telegraph, RED)
	end
	task.wait(b.Telegraph)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		for _, spot in ipairs(spots) do
			AbilityService.Fx("Ring", spot, b.Radius, Config.Theme.Orange)
			AbilityService.Fx("Beam", spot + Vector3.new(0, 30, 0), spot, Config.Theme.Orange, 1.2)
		end
		for _, player in ipairs(membersIn(state, function(p)
			for _, spot in ipairs(spots) do
				if Telegraph.InCircle(p, spot, b.Radius) then
					return true
				end
			end
			return false
		end)) do
			damagePlayer(player, (model:GetAttribute("Damage") or 1) * b.Mult, model)
		end
	end
	state.busy = false
end

local function summon(state, model)
	state.busy = true
	stop(state)
	local run = state.run
	local arena = run.map and run.map.Arena
	local pool = run.location.Mobs
	model:SetAttribute("Telegraph", true)
	task.wait(0.6)
	model:SetAttribute("Telegraph", false)
	for _, player in ipairs(DungeonRuns.Members(run)) do
		Remotes.Notify(player, BOSS.Texts.Summon:format(model:GetAttribute("MobName") or ""), "red")
	end
	if arena then
		for i = 1, BOSS.Summon.Count do
			local portal = arena.Portals[(i - 1) % #arena.Portals + 1]
			local id = pool[run.rng:NextInteger(1, #pool)]
			task.delay(i * 0.25, function()
				if mobs[model] then
					DungeonRuns.SpawnMob(run, id, portal.Position, { Tier = run.location.BossTier - 1, Zone = "Boss" })
				end
			end)
		end
	end
	state.busy = false
end

local function cone(state, model)
	state.busy = true
	local _, root = target(state)
	if not root then
		state.busy = false
		return
	end
	stop(state)
	face(state, root.Position)
	local c = BOSS.Cone
	local start = Vector3.new(state.root.Position.X, groundOf(state), state.root.Position.Z)
	local look = Vector3.new(root.Position.X - start.X, 0, root.Position.Z - start.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, 1)
	local cf = CFrame.lookAt(start, start + look)
	model:SetAttribute("Telegraph", true)
	Telegraph.Cone(state.run.fxFolder, cf, c.Radius, c.Angle, c.Telegraph, RED)
	task.wait(c.Telegraph)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		local color = model:GetAttribute("Color") or RED
		for i = -2, 2 do
			local dir = CFrame.Angles(0, math.rad(c.Angle / 4 * i), 0):VectorToWorldSpace(look)
			AbilityService.Fx("Beam", start + Vector3.new(0, 1.5, 0), start + Vector3.new(0, 1, 0) + dir * c.Radius, color, 0.8)
		end
		for _, player in ipairs(membersIn(state, function(p)
			return Telegraph.InCone(p, cf, c.Radius, c.Angle)
		end)) do
			damagePlayer(player, (model:GetAttribute("Damage") or 1) * c.Mult, model)
		end
	end
	state.busy = false
end

-- Energy rings run out along the floor from the boss; a player on the
-- ground inside the ring's band is hit (a jump clears it).
local function wave(state, model)
	state.busy = true
	stop(state)
	local w = BOSS.Wave
	local center = Vector3.new(state.root.Position.X, groundOf(state), state.root.Position.Z)
	model:SetAttribute("Telegraph", true)
	Telegraph.Circle(state.run.fxFolder, center, 6, w.Telegraph, RED)
	task.wait(w.Telegraph)
	model:SetAttribute("Telegraph", false)
	if not (mobs[model] and model.Parent) then
		state.busy = false
		return
	end
	local rings = w.Rings + (state.phase - 1) * w.PerPhase
	local color = if model:GetAttribute("Rage") then BOSS.Rage.Color else (model:GetAttribute("Color") or RED)
	local damage = (model:GetAttribute("Damage") or 1) * w.Mult
	for ring = 1, rings do
		AbilityService.Fx("Wave", center, w.Radius, w.Speed, color)
		task.spawn(function()
			local hit = {}
			local start = os.clock()
			while true do
				local radius = (os.clock() - start) * w.Speed
				if radius > w.Radius then
					break
				end
				for _, player in ipairs(DungeonRuns.Members(state.run)) do
					local root = rootOf(player)
					local humanoid = root and player.Character:FindFirstChildOfClass("Humanoid")
					if root and not hit[player] and humanoid.FloorMaterial ~= Enum.Material.Air then
						local d = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
						if math.abs(d - radius) <= w.Band then
							hit[player] = true
							damagePlayer(player, damage, model)
						end
					end
				end
				task.wait(0.05)
			end
		end)
		if ring < rings then
			task.wait(w.Gap)
		end
	end
	task.wait(0.3)
	state.busy = false
end

-- A fan of projectiles at the target.
local function volley(state, model)
	state.busy = true
	local _, root = target(state)
	if not root then
		state.busy = false
		return
	end
	stop(state)
	face(state, root.Position)
	local v = BOSS.Volley
	local from = state.root.Position + Vector3.new(0, 2, 0)
	local look = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	look = if look.Magnitude > 0.1 then look.Unit else state.root.CFrame.LookVector
	local lines = {}
	for i = 1, v.Count do
		local a = -v.Spread / 2 + v.Spread * (i - 1) / math.max(1, v.Count - 1)
		local dir = CFrame.Angles(0, math.rad(a), 0):VectorToWorldSpace(look)
		local to = from + dir * v.Range
		to = Vector3.new(to.X, root.Position.Y, to.Z)
		local wall = worldRay(state, from, to)
		if wall then
			to = wall.Position
		end
		table.insert(lines, to)
		Telegraph.Line(state.run.fxFolder, from, to, v.Width, v.Telegraph, RED)
	end
	model:SetAttribute("Telegraph", true)
	task.wait(v.Telegraph)
	model:SetAttribute("Telegraph", false)
	if mobs[model] and model.Parent then
		for _, to in ipairs(lines) do
			fireBolt(state, model, from, to, v.Width, v.Mult)
		end
	end
	state.busy = false
end

local function bossPhase(state, model)
	local humanoid = state.humanoid
	local share = humanoid.Health / math.max(1, humanoid.MaxHealth)
	local phase = 1
	for i, threshold in ipairs(BOSS.Phases) do
		if share <= threshold then
			phase = i + 1
		end
	end
	if phase > state.phase then
		state.phase = phase
		model:SetAttribute("Phase", phase)
		if phase >= 2 and not model:GetAttribute("Rage") then
			model:SetAttribute("Rage", true) -- clients: red glow (MobFx)
			state.speed *= BOSS.Rage.Speed
		end
		for _, player in ipairs(DungeonRuns.Members(state.run)) do
			Remotes.Get("GateState"):FireClient(player, "Phase", phase)
		end
		-- a short roar: everyone around is pushed back
		task.spawn(shockwave, state, model, 10, 0.8, 1)
		return true
	end
	return false
end

local function bossSpecial(state, model)
	local options = { slam = true, charge = true, barrage = true, cone = true, wave = true }
	if state.phase >= BOSS.Volley.FromPhase then
		options.volley = true
	end
	if state.phase >= BOSS.Summon.FromPhase and not state.summoned then
		state.summoned = true
		return summon(state, model)
	end
	local keys = {}
	for key in pairs(options) do
		if key ~= state.lastPick then
			table.insert(keys, key)
		end
	end
	local pick = keys[state.run.rng:NextInteger(1, #keys)]
	state.lastPick = pick
	if pick == "slam" then
		local s = BOSS.Slam
		shockwave(state, model, s.Radius + (state.phase - 1) * 2, s.Telegraph, s.Mult)
	elseif pick == "charge" then
		charge(state, model)
	elseif pick == "cone" then
		cone(state, model)
	elseif pick == "wave" then
		wave(state, model)
	elseif pick == "volley" then
		volley(state, model)
	else
		barrage(state, model)
	end
end

---------------------------------------------------------------------
-- Brain tick
---------------------------------------------------------------------

-- Wakes every sleeping mob of the same section group.
local function wakeGroup(state, model)
	local group = model:GetAttribute("Group")
	for other, otherState in pairs(mobs) do
		if otherState.run == state.run and other:GetAttribute("Group") == group and not other:GetAttribute("Awake") then
			other:SetAttribute("Awake", true)
		end
	end
end

local function tick()
	local clock = os.clock()
	for model, state in pairs(mobs) do
		if not model.Parent or state.humanoid.Health <= 0 or model:GetAttribute("Dying") then
			mobs[model] = nil
			continue
		end
		if state.busy or model:GetAttribute("Intro") then
			continue -- attacking, or the boss entrance is still playing
		end
		local player, targetRoot, distance = target(state)
		if not player then
			stop(state)
			continue
		end
		-- asleep on the post: notice a player close by, then the group comes
		if not state.awake then
			if not model:GetAttribute("Awake") and distance <= SECTIONS.Aggro then
				model:SetAttribute("Awake", true)
			end
			if model:GetAttribute("Awake") then
				state.awake = true
				state.readyAt = clock + 0.35 + math.random() * 0.4 -- the "!" moment
				state.lastAttack = clock - math.random()
				wakeGroup(state, model)
				face(state, targetRoot.Position)
			end
			continue
		end
		if clock < (state.readyAt or 0) or clock < (state.recoverUntil or 0) then
			continue
		end
		local stunned, slow = statusOf(model)
		if stunned then
			continue
		end
		state.humanoid.WalkSpeed = state.speed * slow
		local role = state.role

		if state.isBoss then
			if bossPhase(state, model) then
				continue
			end
			local every = BOSS.Every * BOSS.PhaseSpeed[state.phase]
			if clock - state.lastSpecial >= every then
				state.lastSpecial = clock
				task.spawn(bossSpecial, state, model)
			elseif distance <= 6 then
				stop(state)
				if clock - state.lastAttack >= 1.6 * BOSS.PhaseSpeed[state.phase] then
					task.spawn(melee, state, model, { Telegraph = 0.6, Range = 6 })
				end
			else
				state.humanoid:MoveTo(targetRoot.Position)
			end
			continue
		end

		if state.elite then
			eliteAffixes(state, model, clock)
		end
		if state.elite and clock - state.lastShock >= E.Elite.Shockwave.Every and distance <= E.Elite.Shockwave.Radius then
			state.lastShock = clock
			local s = E.Elite.Shockwave
			task.spawn(shockwave, state, model, s.Radius, s.Telegraph, s.Mult)
			continue
		end

		local kind = model:GetAttribute("Role")
		local cooldown = (role.Cooldown or 2) * state.cooldownMult
		if kind == "Bomber" then
			if distance <= role.Range then
				task.spawn(selfDestruct, state, model, role)
			else
				state.humanoid:MoveTo(targetRoot.Position)
			end
			continue
		end
		if kind == "Blinker" and distance > role.BlinkFrom and clock - (state.lastBlink or 0) >= role.Blink then
			task.spawn(blink, state, model, targetRoot)
			continue
		end
		if kind == "Healer" then
			-- keep away from the players, heal now and then
			if distance < role.Keep then
				local away = state.root.Position - targetRoot.Position
				away = Vector3.new(away.X, 0, away.Z)
				state.humanoid:MoveTo(state.root.Position + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)) * 10)
			else
				stop(state)
			end
			if clock - state.lastAttack >= role.Every then
				task.spawn(heal, state, model, role)
			end
		elseif kind == "Ranged" or kind == "Turret" then
			if distance > role.Range - 4 or not canSee(state, targetRoot) then
				-- too far, or a wall in the way: come closer
				state.humanoid:MoveTo(targetRoot.Position)
			elseif distance < role.Keep * 0.6 then
				local away = state.root.Position - targetRoot.Position
				away = Vector3.new(away.X, 0, away.Z)
				state.humanoid:MoveTo(state.root.Position + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)) * 8)
			else
				if clock - state.lastAttack >= cooldown then
					stop(state)
					task.spawn(shoot, state, model, role)
				elseif clock >= (state.nextStrafe or 0) then
					-- side-step between shots
					state.nextStrafe = clock + E.Strafe.Every
					local to = targetRoot.Position - state.root.Position
					local side = Vector3.new(-to.Z, 0, to.X)
					if side.Magnitude > 0.1 then
						state.humanoid:MoveTo(state.root.Position + side.Unit * E.Strafe.Distance * (if math.random() < 0.5 then -1 else 1))
					end
				end
			end
		else
			if distance <= role.Range then
				stop(state)
				face(state, targetRoot.Position)
				if clock - state.lastAttack >= cooldown then
					task.spawn(melee, state, model, role)
				end
			elseif distance > E.Surround.From then
				state.humanoid:MoveTo(targetRoot.Position)
			else
				-- close in from its own side: the group surrounds the player
				local a = state.slot
				local ring = math.max(2, role.Range * 0.6)
				state.humanoid:MoveTo(targetRoot.Position + Vector3.new(math.cos(a) * ring, 0, math.sin(a) * ring))
			end
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
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + StatService.Get(player).Regen * TICK)
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
	local isBoss = model:GetAttribute("Boss") == true
	local roleName = model:GetAttribute("Role") or "Melee"
	local role = E.Roles[roleName] or E.Roles.Melee
	local speed = if isBoss then Config.Dungeon.Mob.BossWalkSpeed + 3 else role.Speed
	local cooldownMult = 1
	if hasAffix(model, "Swift") then
		speed *= AFFIX.Swift.Speed
		cooldownMult = AFFIX.Swift.Cooldown
	end
	humanoid.WalkSpeed = speed
	mobs[model] = {
		run = run,
		humanoid = humanoid,
		root = root,
		reach = math.max(root.Size.X, root.Size.Z) / 2,
		role = role,
		speed = speed,
		isBoss = isBoss,
		elite = model:GetAttribute("Elite") == true,
		phase = 1,
		awake = model:GetAttribute("Awake") ~= false,
		lastAttack = os.clock() - math.random() * 1.5,
		lastSpecial = os.clock(),
		lastShock = os.clock() - math.random() * 3,
		busy = false,
		cooldownMult = cooldownMult,
		slot = math.random() * math.pi * 2, -- its side when surrounding the player
	}
	if isBoss then
		model:SetAttribute("Phase", 1)
	end
end

function MobAI.Unregister(model)
	local state = mobs[model]
	mobs[model] = nil
	-- Explosive elites: a last blast where they fell
	if state and hasAffix(model, "Explosive") and state.humanoid.Health <= 0 then
		local a = AFFIX.Explosive
		local p = state.root.Position
		blast(state.run, Vector3.new(p.X, groundOf(state), p.Z), a.Radius, a.Delay, (model:GetAttribute("Damage") or 1) * a.Mult, nil)
	end
end

function MobAI.Init()
	DungeonRuns.OnMobSpawned = MobAI.Register
	DungeonRuns.OnMobRemoved = MobAI.Unregister
	Players.PlayerRemoving:Connect(function(player)
		lastDamaged[player] = nil
		lastHurt[player] = nil
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
