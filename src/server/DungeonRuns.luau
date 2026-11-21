--[[
	DungeonRuns.luau
	Gate runs ("Врата"). A run = one location (Config.Gates.Locations)
	for a solo player or a group (up to Config.Party.Max), built for the
	run by GateMap and destroyed when it ends.

	Flow (no waves, no waiting): the team appears at section 1. Every
	section already holds its group of enemies (Config.Gates.Locations
	Sections = { 5, 6, 4 }), standing in front of the exit. They notice a
	player who comes close (Config.Sections.Aggro) or hits one of them and
	the whole group attacks together (MobAI). The moment the group is dead
	the exit barrier opens. "УЧАСТОК 2/3 · врагов 4/6" goes to every member
	(GateState "Wave"). The boss arena closes behind the team, the boss
	gets an intro (GateState "Boss") and fights in phases (MobAI). After
	the boss: grade S/A/B/C by time and deaths, every member gets a boss
	chest (better grade -> more items), the results window ("Result") and
	the way back after Config.Grades.ReturnSeconds.

	Difficulty grows with the team: more enemies (Config.Sections.GroupCount)
	and more health (GroupHealth) per extra member. Red runs
	(Config.RedGate) are harder (more enemies per section), use the Red
	loot table and can't be left before the boss is down.

	A member who dies leaves the run (back to the hub on respawn); the run
	ends when nobody is left. Kills give every member XP / credits and
	personal loot (hooks below).

	The old API stays for the rest of the game: HasRun, GetRun, EndRun,
	IsMob, MobsNear, NearestMob, Damage, Hit, RunOf, RecoveryCFrame and
	the hooks OnMobSpawned / OnMobRemoved / OnKill / OnRoomCleared /
	OnRunStarted / OnRunEnded / OnRunClosed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Effects = require(script.Parent.Effects)
local GateMap = require(script.Parent.GateMap)
local MobBuilder = require(script.Parent.MobBuilder)
local PlayerState = require(script.Parent.PlayerState)
local StatService = require(script.Parent.StatService)
local Remotes = require(script.Parent.Remotes)
local WorldKit = require(script.Parent.WorldKit)

local DungeonRuns = {}

local W = Config.Sections
local PORTAL_SECONDS = 1.1 -- the boss portal glows this long
local E = Config.Enemies
local CB = Config.Combat
local Looks = Config.MobLooks
local GR = Config.Grades

local runs = {} -- [run] = true
local runOf = {} -- [player] = run
local slots = {} -- [slot] = run
local mobInfo = {} -- [model] = { run = run, zone = index|"Boss" }
local nextRunId = 0

-- Hooks (other services set them)
DungeonRuns.OnMobSpawned = nil -- (run, model)
DungeonRuns.OnMobRemoved = nil -- (model)
DungeonRuns.OnRunEnded = nil -- (player) sent back to the hub (not on death)
DungeonRuns.OnKill = nil -- (player, tier, isBoss, position, kind, info)
DungeonRuns.OnRoomCleared = nil -- (player, tier) a location was closed (its boss tier)
DungeonRuns.OnRunStarted = nil -- (player)
DungeonRuns.OnRunClosed = nil -- (player) left the run for any reason
DungeonRuns.OnBossDefeated = nil -- (run, chestPosition, grade)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function members(run)
	local list = {}
	for _, player in ipairs(run.players) do
		if player.Parent and runOf[player] == run then
			table.insert(list, player)
		end
	end
	return list
end
DungeonRuns.Members = members

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function send(run, kind: string, payload)
	for _, player in ipairs(members(run)) do
		Remotes.Get("GateState"):FireClient(player, kind, payload)
	end
end

local function notifyAll(run, text: string, kind: string?)
	for _, player in ipairs(members(run)) do
		Remotes.Notify(player, text, kind)
	end
end

-- Extra team members make groups bigger and enemies tougher.
local function teamScale(run)
	local extra = math.max(0, #run.players - 1)
	return 1 + W.GroupCount * extra, 1 + W.GroupHealth * extra
end

local function inside(position: Vector3, center: Vector3, size: number): boolean
	return math.abs(position.X - center.X) <= size / 2 and math.abs(position.Z - center.Z) <= size / 2
end

local function anyMemberIn(run, center: Vector3, size: number): boolean
	for _, player in ipairs(members(run)) do
		local root = rootOf(player)
		if root and inside(root.Position, center, size - 6) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Mobs
---------------------------------------------------------------------

local function waveState(run)
	local zone = run.zones and run.zones[run.zoneIndex]
	return {
		Location = run.location.Name,
		Zone = run.zoneIndex,
		Zones = if run.zones then #run.zones else 0,
		Alive = if zone then zone.Alive else run.alive,
		Total = if zone then zone.Total else run.total,
		Phase = run.phase,
		Red = run.red,
	}
end

local function pushState(run)
	send(run, "Wave", waveState(run))
end

-- Portal glow, then the enemy appears.
local function openPortal(run, position: Vector3, color: Color3)
	local ring = WorldKit.Part(run.fxFolder, {
		Name = "PortalFx",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1, 1),
		CFrame = CFrame.new(position.X, run.groundY + 0.25, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local column = WorldKit.Part(run.fxFolder, {
		Name = "PortalBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10, 4, 4),
		CFrame = CFrame.new(position.X, run.groundY + 5, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	TweenService:Create(ring, TweenInfo.new(PORTAL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 7, 7) }):Play()
	TweenService:Create(column, TweenInfo.new(PORTAL_SECONDS), { Transparency = 0.55 }):Play()
	task.delay(PORTAL_SECONDS + 0.4, function()
		TweenService:Create(ring, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(column, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.delay(0.6, function()
			ring:Destroy()
			column:Destroy()
		end)
	end)
end

local function decorateElite(model)
	local aura = Instance.new("Highlight")
	aura.Name = "EliteAura"
	aura.FillTransparency = 0.85
	aura.FillColor = E.Elite.Aura
	aura.OutlineColor = E.Elite.Aura
	aura.OutlineTransparency = 0.1
	aura.DepthMode = Enum.HighlightDepthMode.Occluded
	aura.Parent = model
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(E.Elite.Aura, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 14
	emitter.Parent = model.PrimaryPart
end

-- Energy plate in front of a shield bearer (blocks hits from the front).
local function addShield(model)
	local root = model.PrimaryPart
	local height = model:GetAttribute("Height") or 6
	local plate = Instance.new("Part")
	plate.Name = "EnergyShield"
	plate.Size = Vector3.new(4.2, height * 0.75, 0.25)
	plate.Material = Enum.Material.ForceField
	plate.Color = model:GetAttribute("Color") or Config.Theme.Cyan
	plate.Transparency = 0.15
	plate.CanCollide = false
	plate.CanQuery = true
	plate.CanTouch = false
	plate.Massless = true
	plate.CFrame = root.CFrame * CFrame.new(0, 0, -(root.Size.Z / 2 + 1.4))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = plate
	weld.Parent = plate
	plate.Parent = model
end

-- Builds and registers one enemy. opts: Elite, Boss, Tier, Zone, Asleep
local function spawnMob(run, defId: string, position: Vector3, opts)
	local def = Config.Mobs.Defs[defId]
	if not def then
		return nil
	end
	opts = opts or {}
	local isBoss = opts.Boss == true
	local elite = opts.Elite == true
	local role = E.Roles[def.Role or "Melee"] or E.Roles.Melee
	local scale = if isBoss then Looks.BossScale elseif elite then E.Elite.Scale else 1
	local facing = run.facing or (position + Vector3.new(0, 0, 10))
	local model = MobBuilder.Build(def, scale, CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z)))
	local _, healthScale = teamScale(run)
	local tier = opts.Tier or run.location.Tier
	local health = Config.MobHealth(tier, isBoss) * (if isBoss then 1 else role.Health) * healthScale
	local damage = Config.MobDamage(tier, isBoss) * (if isBoss then 1 else role.Damage)
	if elite then
		health *= E.Elite.Health
		damage *= E.Elite.Damage
	end
	if run.red then
		health *= Config.RedGate.Health
		damage *= Config.RedGate.Damage
	end
	health = math.max(1, math.floor(health))
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = health
	humanoid.Health = health
	local name = (if elite then E.Elite.Prefix else "") .. def.Name
	model:SetAttribute("Room", tier) -- clients find mobs by this attribute
	model:SetAttribute("Boss", isBoss)
	model:SetAttribute("Elite", elite)
	model:SetAttribute("Role", if isBoss then "Boss" else def.Role or "Melee")
	model:SetAttribute("Kind", def.Id)
	model:SetAttribute("MobName", name)
	model:SetAttribute("Damage", math.max(1, math.floor(damage)))
	local height = model:GetAttribute("Height") or 6
	WorldKit.HealthGui(model.PrimaryPart, if isBoss or elite then name else nil, height - (model.PrimaryPart.Position.Y - position.Y) + 1.5)
	WorldKit.UpdateHealth(model.PrimaryPart, health, health)
	if elite then
		decorateElite(model)
	end
	if def.Role == "Shield" then
		addShield(model)
	end
	model:SetAttribute("Group", if type(opts.Zone) == "number" then opts.Zone else 0)
	model:SetAttribute("Awake", opts.Asleep ~= true)
	model.Parent = run.mobFolder
	mobInfo[model] = { run = run, zone = opts.Zone or run.zoneIndex }
	run.mobs[model] = true
	if DungeonRuns.OnMobSpawned then
		DungeonRuns.OnMobSpawned(run, model)
	end
	return model
end
DungeonRuns.SpawnMob = spawnMob

-- The group of a section: roles mixed, at most one healer (never in
-- section 1), elites by Config.Sections.Elites.
local function groupList(run, zoneIndex: number, count: number)
	local countScale = teamScale(run)
	count = math.floor(count * countScale + 0.5) + (if run.red then Config.RedGate.ExtraEnemies else 0)
	local table_ = run.location.Elites or W.Elites -- a location may set its own (the very first one has none)
	local elites = table_[math.min(zoneIndex, #table_)] + (if #run.players > 2 then 1 else 0)
	elites = math.min(elites, count - 1)
	local pool = run.location.Mobs
	local list = {}
	local rng = run.rng
	local healer = false
	while #list < count - elites do
		local id = pool[rng:NextInteger(1, #pool)]
		local def = Config.Mobs.Defs[id]
		if def and def.Role == "Healer" then
			if healer or zoneIndex == 1 then
				continue
			end
			healer = true
		end
		table.insert(list, { Id = id })
	end
	for _ = 1, elites do
		local id
		repeat
			id = pool[rng:NextInteger(1, #pool)]
		until Config.Mobs.Defs[id].Role ~= "Swarm" and Config.Mobs.Defs[id].Role ~= "Healer"
		table.insert(list, { Id = id, Elite = true })
	end
	return list
end

-- Spots of a group around the zone's post, away from covers / landmark.
local function groupSpots(run, zone, count: number)
	local spots = {}
	local post = zone.Post
	local tries = 0
	while #spots < count and tries < 200 do
		tries += 1
		local p
		if #spots == 0 then
			p = post
		else
			local a = run.rng:NextNumber(0, math.pi * 2)
			local r = run.rng:NextNumber(3.5, W.Spread)
			p = post + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r * 0.7)
		end
		local free = true
		for _, b in ipairs(zone.Blocks) do
			if Vector3.new(p.X - b.X, 0, p.Z - b.Z).Magnitude < 7 then
				free = false
			end
		end
		for _, q in ipairs(spots) do
			if (p - q).Magnitude < 3.6 then
				free = false
			end
		end
		if free or tries > 150 then
			table.insert(spots, p)
		end
	end
	return spots
end

-- Puts the section's group on its post (asleep until a player comes).
local function placeGroup(run, zone, count: number)
	local list = groupList(run, zone.Index, count)
	local spots = groupSpots(run, zone, #list)
	local tier = run.location.Tier + (zone.Index - 1) * run.location.TierStep
	zone.Total = #list
	zone.Alive = #list
	run.facing = zone.Entry.Position -- they look at the way the team comes from
	for i, entry in ipairs(list) do
		local position = Vector3.new(spots[i].X, run.groundY + 3, spots[i].Z)
		local model = spawnMob(run, entry.Id, position, { Elite = entry.Elite, Tier = tier, Zone = zone.Index, Asleep = true })
		if not model then
			zone.Alive -= 1
			zone.Total -= 1
		end
		if i % 3 == 0 then
			task.wait()
		end
	end
end

local function openBarrier(part)
	if not part then
		return
	end
	part.CanCollide = false
	TweenService:Create(part, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	local light = part:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = false
	end
end

local function closeBarrier(part)
	if not part then
		return
	end
	part.CanCollide = true
	TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 0.2 }):Play()
end

---------------------------------------------------------------------
-- Run flow
---------------------------------------------------------------------

local function waitUntil(run, check)
	while runs[run] and not check() do
		task.wait(0.25)
	end
	return runs[run] ~= nil
end

local function gradeFor(run)
	local elapsed = os.clock() - run.started
	local par = run.location.ParSeconds or 300
	local index = #GR
	for i, grade in ipairs(GR) do
		if elapsed <= par * grade.Time then
			index = i
			break
		end
	end
	index = math.min(#GR, index + run.deaths * GR.DeathStep)
	return GR[index], elapsed
end

local function summaryFor(run, player, result: string, grade, elapsed)
	local stats = run.stats[player] or { damage = 0, kills = 0, deaths = 0 }
	return {
		Result = result,
		Location = run.location.Name,
		LocationId = run.location.Id,
		Rank = run.location.Rank,
		Red = run.red,
		Grade = grade and grade.Id or nil,
		Bonus = grade and grade.Items or 0,
		Time = math.floor(elapsed or (os.clock() - run.started)),
		Damage = math.floor(stats.damage),
		Kills = stats.kills,
		Deaths = run.deaths,
		Loot = run.loot[player] or {},
		Return = GR.ReturnSeconds,
	}
end

local endRun -- defined below

local function bossFight(run)
	local arena = run.map.Arena
	run.zoneIndex = #run.zones + 1
	run.phase = "Enter"
	pushState(run)
	if not waitUntil(run, function()
		return anyMemberIn(run, arena.Center, arena.Size)
	end) then
		return
	end
	-- pull stragglers in and close the arena
	task.wait(1)
	for _, player in ipairs(members(run)) do
		local root = rootOf(player)
		if root and not inside(root.Position, arena.Center, arena.Size) then
			player.Character:PivotTo(arena.Entry)
		end
	end
	closeBarrier(arena.Gate)
	local def = Config.Mobs.Defs[run.location.Boss]
	run.phase = "Boss"
	run.alive, run.total = 1, 1
	pushState(run)
	send(run, "Boss", { Name = def.Name, Title = def.Title or "", Seconds = E.Boss.IntroSeconds, Position = arena.Spawn.Position })
	openPortal(run, arena.Spawn.Position, Config.DungeonLayout.BossBarrierColor)
	task.wait(E.Boss.IntroSeconds)
	if not runs[run] then
		return
	end
	run.facing = arena.Center + Vector3.new(0, 0, arena.Size)
	local boss = spawnMob(run, run.location.Boss, arena.Spawn.Position, { Boss = true, Tier = run.location.BossTier, Zone = "Boss" })
	run.boss = boss
end

-- A section is done the moment its group is dead: the exit opens.
local function zoneFlow(run, zone)
	run.zoneIndex = zone.Index
	run.phase = "Fight"
	pushState(run)
	if not waitUntil(run, function()
		return zone.Alive <= 0
	end) then
		return false
	end
	openBarrier(zone.Exit)
	notifyAll(run, W.Texts.Cleared, "gold")
	-- a breather: the team gets part of its health back
	for _, player in ipairs(members(run)) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * W.ClearHeal)
			pcall(Effects.Burst, humanoid.Parent:GetPivot().Position, Color3.fromRGB(90, 230, 110), 14, 16, 1)
		end
	end
	return true
end

local function runFlow(run)
	for _, zone in ipairs(run.zones) do
		if not zoneFlow(run, zone) then
			return
		end
	end
	bossFight(run)
end

-- Boss down: grade, chests, results, the way back.
local function bossDefeated(run, position: Vector3)
	run.finished = true
	local grade, elapsed = gradeFor(run)
	run.grade = grade
	run.phase = "Done"
	pushState(run)
	local tier = run.location.BossTier
	for _, player in ipairs(members(run)) do
		local data = DataService.Get(player)
		if data then
			data.Gates = if type(data.Gates) == "table" then data.Gates else { Cleared = {} }
			data.Gates.Cleared = if type(data.Gates.Cleared) == "table" then data.Gates.Cleared else {}
			local best = data.Gates.Cleared[run.location.Id]
			-- Кристаллы: every boss, more for the first clear of a location
			local crystals = Config.Crystals.Boss + (if best == nil then Config.Crystals.FirstClear else 0)
			if PlayerState.AddCrystals(player, crystals) > 0 then
				Remotes.Notify(player, Config.Crystals.Texts.Got:format(crystals), "gold")
			end
			local order = { S = 1, A = 2, B = 3, C = 4 }
			if not best or order[grade.Id] < (order[best] or 9) then
				data.Gates.Cleared[run.location.Id] = grade.Id
			end
			-- the fastest clear of this location (Статистика)
			data.Gates.BestTime = if type(data.Gates.BestTime) == "table" then data.Gates.BestTime else {}
			local seconds = math.floor(elapsed)
			local old = tonumber(data.Gates.BestTime[run.location.Id])
			if not old or seconds < old then
				data.Gates.BestTime[run.location.Id] = seconds
			end
			PlayerState.Sync(player)
		end
		if PlayerState.ReachRoom(player, tier) then
			Remotes.Notify(player, Config.DungeonLayout.Texts.NewRecord, "gold")
		end
		if DungeonRuns.OnRoomCleared then
			DungeonRuns.OnRoomCleared(player, tier)
		end
	end
	if DungeonRuns.OnBossDefeated then
		DungeonRuns.OnBossDefeated(run, position, grade)
	end
	task.delay(6, function()
		for _, player in ipairs(members(run)) do
			Remotes.Get("GateState"):FireClient(player, "Result", summaryFor(run, player, "Won", grade, elapsed))
		end
	end)
	task.delay(GR.ReturnSeconds, function()
		if runs[run] then
			for _, player in ipairs(members(run)) do
				endRun(player, "Won")
			end
		end
	end)
end

---------------------------------------------------------------------
-- Kills and damage
---------------------------------------------------------------------

local function kill(model, killer)
	local info = mobInfo[model]
	mobInfo[model] = nil
	local run = info.run
	run.mobs[model] = nil
	if DungeonRuns.OnMobRemoved then
		DungeonRuns.OnMobRemoved(model)
	end
	local position = model:GetPivot().Position
	local isBoss = model:GetAttribute("Boss") == true
	local elite = model:GetAttribute("Elite") == true
	local kind = model:GetAttribute("Kind")
	local tier = model:GetAttribute("Room") or run.location.Tier
	local color = model:GetAttribute("Color") or Config.Theme.Magenta
	model:SetAttribute("Dying", true)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	local gui = model.PrimaryPart and model.PrimaryPart:FindFirstChild("HealthGui")
	if gui then
		gui.Enabled = false
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.CanCollide = false
		end
	end
	task.delay(0.15, function()
		model:Destroy()
	end)
	Effects.Burst(position, color, if isBoss then 90 elseif elite then 45 else 25, if isBoss then 35 else 22, if isBoss then 2 else 1)

	local enemy = if run.red and not isBoss then "Red" elseif isBoss then "Boss" elseif elite then "Elite" else "Normal"
	local role = model:GetAttribute("Role")
	local weight = W.Reward * (if elite then W.EliteReward elseif role == "Swarm" then W.SwarmReward else 1)
	local lootInfo = { Rank = run.location.Rank, Enemy = enemy, Elite = elite, Red = run.red, Weight = weight }
	if killer and run.stats[killer] then
		run.stats[killer].kills += 1
	end
	for _, player in ipairs(members(run)) do
		Remotes.Get("ClickHit"):FireClient(player, "Kill", position, isBoss)
		if DungeonRuns.OnKill then
			DungeonRuns.OnKill(player, tier, isBoss, position, kind, lootInfo)
		end
	end
	if isBoss then
		bossDefeated(run, Vector3.new(position.X, run.groundY, position.Z))
		return
	end
	local zone = type(info.zone) == "number" and run.zones[info.zone]
	if zone then
		zone.Alive = math.max(0, zone.Alive - 1)
		if info.zone == run.zoneIndex then
			pushState(run)
		end
	end
end

function DungeonRuns.IsMob(model): boolean
	return mobInfo[model] ~= nil
end

function DungeonRuns.RunOf(model)
	local info = mobInfo[model]
	return info and info.run
end

local function liveMobs(run)
	local list = {}
	for model in pairs(run.mobs) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if model.PrimaryPart and humanoid and humanoid.Health > 0 and not model:GetAttribute("Dying") then
			table.insert(list, model)
		end
	end
	return list
end
DungeonRuns.LiveMobs = liveMobs

-- Every living mob of the player's run within `range` of `position`
-- (measured from the mob's surface), nearest first.
function DungeonRuns.MobsNear(player, position: Vector3, range: number)
	local run = runOf[player]
	local list = {}
	if not run then
		return list
	end
	for _, model in ipairs(liveMobs(run)) do
		local root = model.PrimaryPart
		local distance = (root.Position - position).Magnitude - math.max(root.Size.X, root.Size.Z) / 2
		if distance <= range then
			table.insert(list, { model = model, distance = distance })
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance
	end)
	return list
end

function DungeonRuns.NearestMob(player, position: Vector3, range: number)
	local near = DungeonRuns.MobsNear(player, position, range)
	return near[1] and near[1].model
end

function DungeonRuns.Hit(player, model)
	local damage, isCrit = StatService.RollHit(player)
	return DungeonRuns.Damage(player, model, damage, isCrit)
end

-- A shield bearer blocks hits that come from its front.
local function blocked(model, player): boolean
	if model:GetAttribute("Role") ~= "Shield" or (model:GetAttribute("StunUntil") or 0) > Workspace:GetServerTimeNow() then
		return false
	end
	local root, from = model.PrimaryPart, rootOf(player)
	if not root or not from then
		return false
	end
	local to = from.Position - root.Position
	to = Vector3.new(to.X, 0, to.Z)
	if to.Magnitude < 0.1 then
		return false
	end
	local look = root.CFrame.LookVector
	local angle = math.deg(math.acos(math.clamp(to.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit), -1, 1)))
	return angle <= E.Roles.Shield.Front
end

-- Deals a ready-made amount of damage to a mob of the player's run
-- (abilities, basic attacks). flag = "Heavy" (3rd combo hit, ability) or
-- "Execute" (finisher): stronger knockback and feedback on the client.
-- Returns the damage dealt (0 if none).
function DungeonRuns.Damage(player, model, damage: number, isCrit: boolean?, flag: string?)
	local info = mobInfo[model]
	if not info or runOf[player] ~= info.run then
		return 0
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end
	local run = info.run
	local isBlocked = blocked(model, player)
	if isBlocked then
		damage *= 1 - E.Roles.Shield.Block
	end
	damage = math.max(1, math.floor(damage))
	if not model:GetAttribute("Awake") then
		model:SetAttribute("Awake", true) -- MobAI wakes the whole group
	end
	humanoid.Health = math.max(0, humanoid.Health - damage)
	model:SetAttribute("Hits", (model:GetAttribute("Hits") or 0) + 1)
	WorldKit.UpdateHealth(model.PrimaryPart, humanoid.Health, humanoid.MaxHealth)
	local stats = run.stats[player]
	if stats then
		stats.damage += damage
	end
	Remotes.Get("ClickHit"):FireClient(player, "Hit", model, damage, isCrit == true, isBlocked, flag)
	-- knockback + a short stagger (not on bosses)
	local root, from = model.PrimaryPart, rootOf(player)
	if root and from and not model:GetAttribute("Boss") and humanoid.Health > 0 and not isBlocked then
		local away = root.Position - from.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 0.1 then
			local k = CB.Knockback
			local strength = if flag == "Execute" then CB.Execute.Knockback elseif flag == "Heavy" or isCrit then k.CritMult else 1
			local speed = k.Normal * strength * (if model:GetAttribute("Elite") then k.EliteMult else 1)
			root.AssemblyLinearVelocity = away.Unit * speed + Vector3.new(0, speed * 0.25, 0)
			model:SetAttribute("StaggerUntil", Workspace:GetServerTimeNow() + k.Stagger)
		end
	end
	if humanoid.Health <= 0 then
		kill(model, player)
	end
	return damage
end

-- MobAI reports damage a member took (for the grade / results).
function DungeonRuns.NoteDamageTaken(player, amount: number)
	local run = runOf[player]
	if run and run.stats[player] then
		run.stats[player].taken += amount
	end
end

---------------------------------------------------------------------
-- Start / end
---------------------------------------------------------------------

local function freeSlot(): number?
	for slot = 1, Config.GateMap.MaxRuns do
		if not slots[slot] then
			return slot
		end
	end
	return nil
end

local function leave(player, reason: string)
	local run = runOf[player]
	if not run then
		return
	end
	runOf[player] = nil
	local index = table.find(run.players, player)
	if index then
		table.remove(run.players, index)
	end
	local connections = run.connections[player]
	if connections then
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		run.connections[player] = nil
	end
	if player.Parent then
		player:SetAttribute("Zone", "Hub")
		player:SetAttribute("Biome", "")
		player:SetAttribute("GateRun", "")
		-- a failed run gets its results; leaving on purpose just goes home
		if not run.finished and reason == "Died" then
			Remotes.Get("GateState"):FireClient(player, "Result", summaryFor(run, player, "Failed", nil, nil))
		end
	end
	if DungeonRuns.OnRunClosed then
		DungeonRuns.OnRunClosed(player)
	end
	if reason ~= "Died" and DungeonRuns.OnRunEnded and player.Parent then
		DungeonRuns.OnRunEnded(player)
	end
	-- nobody left: the run and its map go away
	if #members(run) == 0 and runs[run] then
		runs[run] = nil
		slots[run.slot] = nil
		for model in pairs(run.mobs) do
			mobInfo[model] = nil
			if DungeonRuns.OnMobRemoved then
				DungeonRuns.OnMobRemoved(model)
			end
		end
		run.map.Folder:Destroy()
	end
end
endRun = leave

function DungeonRuns.EndRun(player, reason: string?)
	leave(player, reason or "Left")
end

function DungeonRuns.HasRun(player): boolean
	return runOf[player] ~= nil
end

function DungeonRuns.GetRun(player)
	return runOf[player]
end

-- Can this player leave the run right now? (Red gates: only after the boss)
function DungeonRuns.CanLeave(player): boolean
	local run = runOf[player]
	return not run or not run.red or run.finished == true
end

-- Starts a run of `location` for `players` (opts.Red). Teleports them
-- to the start. Returns run or nil, message.
function DungeonRuns.Start(location, players, opts)
	opts = opts or {}
	local slot = freeSlot()
	if not slot then
		return nil, "Все Врата заняты, попробуй через минуту"
	end
	for _, player in ipairs(players) do
		if runOf[player] then
			leave(player, "Left")
		end
	end
	nextRunId += 1
	local run = {
		id = nextRunId,
		slot = slot,
		location = location,
		players = table.clone(players),
		red = opts.Red == true,
		mobs = {},
		stats = {},
		loot = {},
		connections = {},
		deaths = 0,
		zoneIndex = 1,
		alive = 0,
		total = 0,
		phase = "Enter",
		rng = Random.new(),
		groundY = GateMap.GroundY(),
	}
	slots[slot] = run
	runs[run] = true
	run.map = GateMap.Build(location, slot)
	run.zones = run.map.Zones
	local mobFolder = Instance.new("Folder")
	mobFolder.Name = "Mobs"
	mobFolder.Parent = run.map.Folder
	run.mobFolder = mobFolder
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "Fx"
	fxFolder.Parent = run.map.Folder
	run.fxFolder = fxFolder
	run.started = os.clock()

	for i, player in ipairs(players) do
		runOf[player] = run
		run.stats[player] = { damage = 0, kills = 0, taken = 0 }
		run.loot[player] = {}
		local character = player.Character
		if character then
			character:PivotTo(run.map.Start * CFrame.new((i - 1) * 3 - 4.5, 0, 0))
		end
		player:SetAttribute("Zone", "Dungeon")
		player:SetAttribute("Biome", location.Biome)
		player:SetAttribute("GateRun", location.Id)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local list = {}
		if humanoid then
			table.insert(list, humanoid.Died:Connect(function()
				if runOf[player] == run then
					if run.finished then
						return -- the boss is down: a late death changes nothing
					end
					run.deaths += 1
					local d = DataService.Get(player)
					if d then
						d.Stats = if type(d.Stats) == "table" then d.Stats else {}
						d.Stats.Deaths = (tonumber(d.Stats.Deaths) or 0) + 1
					end
					task.delay(2, function()
						if runOf[player] == run then
							leave(player, "Died")
						end
					end)
				end
			end))
		end
		run.connections[player] = list
		if DungeonRuns.OnRunStarted then
			DungeonRuns.OnRunStarted(player)
		end
	end
	-- every section's group stands ready before anyone gets there
	for i, zone in ipairs(run.zones) do
		placeGroup(run, zone, location.Sections[i] or location.Sections[#location.Sections])
	end
	pushState(run)
	task.spawn(runFlow, run)
	return run
end

-- Where to put a player who fell off: the entry of the zone they are in.
function DungeonRuns.RecoveryCFrame(player): CFrame?
	local run = runOf[player]
	if not run then
		return nil
	end
	if run.zoneIndex > #run.zones then
		return run.map.Arena.Entry
	end
	local zone = run.zones[run.zoneIndex] or run.zones[1]
	return zone.Entry
end

-- Something picked up during the run (LootService): for the results.
function DungeonRuns.NoteLoot(player, entry)
	local run = runOf[player]
	if run and run.loot[player] then
		table.insert(run.loot[player], entry)
	end
end

function DungeonRuns.Init()
	GateMap.Init()
	Players.PlayerRemoving:Connect(function(player)
		if runOf[player] then
			leave(player, "Left")
		end
	end)
end

function DungeonRuns.GroundY(): number
	return GateMap.GroundY()
end

return DungeonRuns
