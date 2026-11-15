--[[
	AbilityService.luau
	Combat of the classes, server-authoritative.

	Basic attack (ClickService -> AbilityService.Basic):
	  Клинок  3-hit combo, the 3rd hit is stronger and also hits mobs
	          next to the target; block [F] -Combat.Block.Reduction damage
	  Импульс 2 thrusts + a 360-degree 3rd hit around the player
	  Стрелок ranged shots, every 3rd a volley on several targets; a held
	          attack (>= ChargeSeconds) is a charged shot
	Abilities on Q / E / R: learned active nodes of the skill tree
	(Config.SkillTrees, kinds listed in Config above the trees), cooldowns
	per rank, published as Ready_<slot> (server time) + CooldownMax_<slot>.
	Dash (Shift): every class; Импульс's dash hits everyone on its path.
	Incoming damage (MobAI): shield / block / thorns / cheat death.
	Targets: the player's own run mobs in the dungeon, the Polygon dummies
	in the hub. Visual effects: Ability:FireAllClients("Fx", ...) (client
	AbilityFx).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local EquipmentService = require(script.Parent.EquipmentService)
local PlayerState = require(script.Parent.PlayerState)
local PolygonService = require(script.Parent.PolygonService)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)
local WorldKit = require(script.Parent.WorldKit)

local AbilityService = {}

local CB = Config.Combat
local SK = Config.Skills

local states = {} -- [player] = state

local function state(player)
	local s = states[player]
	if not s then
		s = { combo = 0, lastHit = 0, shots = 0, cooldowns = {}, buffs = {}, blocking = false, chargeStart = nil, cheatAt = -math.huge }
		states[player] = s
	end
	return s
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function fx(kind: string, ...)
	Remotes.Get("Ability"):FireAllClients("Fx", kind, ...)
end

---------------------------------------------------------------------
-- Buffs
---------------------------------------------------------------------

local function buff(player, name: string): number
	local b = state(player).buffs[name]
	if b and b.untilTime > now() then
		return b.value
	end
	return 0
end

local function setBuff(player, name: string, value: number, seconds: number)
	state(player).buffs[name] = { value = value, untilTime = now() + seconds }
end

function AbilityService.AttackSpeedMult(player): number
	return 1 + buff(player, "Haste")
end

---------------------------------------------------------------------
-- Targets and hits
---------------------------------------------------------------------

-- Enemies within `range` of `position`: run mobs in the dungeon, dummies
-- in the hub. Nearest first: { model, distance }.
local function enemiesNear(player, position: Vector3, range: number)
	if DungeonRuns.HasRun(player) then
		return DungeonRuns.MobsNear(player, position, range)
	end
	return PolygonService.Near(position, range)
end

-- Enemies in front (angle from `direction` <= maxAngle degrees).
local function enemiesInFront(player, origin: Vector3, direction: Vector3, range: number, maxAngle: number)
	local list = {}
	for _, e in ipairs(enemiesNear(player, origin, range)) do
		local to = e.model:GetPivot().Position - origin
		to = Vector3.new(to.X, 0, to.Z)
		if to.Magnitude < 3 or math.deg(math.acos(math.clamp(to.Unit:Dot(direction), -1, 1))) <= maxAngle then
			table.insert(list, e)
		end
	end
	return list
end

local function aimDirection(player, aim): Vector3
	local root = rootOf(player)
	if not root then
		return Vector3.new(0, 0, -1)
	end
	if typeof(aim) == "Vector3" then
		local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		if flat.Magnitude > 0.5 then
			return flat.Unit
		end
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- Damage roll with buffs: (damage, isCrit).
local function roll(player, power: number, isAbility: boolean?)
	local damage, isCrit = StatService.RollHit(player)
	local stats = StatService.Get(player)
	local mult = power * (1 + buff(player, "Rage"))
	if isAbility then
		mult *= 1 + (stats.AbilityPct or 0)
	end
	local humanoid = humanoidOf(player)
	if humanoid and (stats.LowHpDamage or 0) > 0 and humanoid.Health / math.max(1, humanoid.MaxHealth) < SK.LowHp then
		mult *= 1 + stats.LowHpDamage
	end
	return damage * mult, isCrit
end

local function setStatus(model: Model, attribute: string, seconds: number)
	local untilTime = now() + seconds
	if (model:GetAttribute(attribute) or 0) < untilTime then
		model:SetAttribute(attribute, untilTime)
	end
end

function AbilityService.Stun(player, model: Model, seconds: number)
	if not DungeonRuns.IsMob(model) then
		return
	end
	local stats = StatService.Get(player)
	seconds = math.min(CB.MaxStun, seconds * (1 + (stats.ControlPct or 0)))
	-- bosses shrug control off faster
	if model:GetAttribute("Boss") then
		seconds *= 0.5
	end
	setStatus(model, "StunUntil", seconds)
	fx("Stun", model, seconds)
end

function AbilityService.Slow(player, model: Model, seconds: number)
	if not DungeonRuns.IsMob(model) then
		return
	end
	local stats = StatService.Get(player)
	setStatus(model, "SlowUntil", seconds * (1 + (stats.ControlPct or 0)))
end

-- One hit on an enemy (mob or dummy) with on-hit effects.
local function hit(player, model: Model, damage: number, isCrit: boolean?)
	if DungeonRuns.IsMob(model) then
		local dealt = DungeonRuns.Damage(player, model, damage, isCrit)
		if dealt > 0 then
			local stats = StatService.Get(player)
			if (stats.Lifesteal or 0) > 0 then
				local humanoid = humanoidOf(player)
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + dealt * stats.Lifesteal)
				end
			end
			if model.Parent and not model:GetAttribute("Dying") then
				if (stats.SlowOnHit or 0) > 0 and math.random() < stats.SlowOnHit then
					AbilityService.Slow(player, model, CB.OnHitSlow)
				end
				if (stats.StunOnHit or 0) > 0 and math.random() < stats.StunOnHit then
					AbilityService.Stun(player, model, CB.OnHitStun)
				end
			end
		end
		return dealt
	end
	return PolygonService.Damage(player, model, damage, isCrit)
end

---------------------------------------------------------------------
-- Basic attack (per class)
---------------------------------------------------------------------

local function pickTarget(player, target, range: number)
	local root = rootOf(player)
	if not root then
		return nil
	end
	if typeof(target) == "Instance" and target:IsA("Model") and (DungeonRuns.IsMob(target) or PolygonService.IsDummy(target)) then
		local surface = (target:GetPivot().Position - root.Position).Magnitude - 2
		if surface <= range then
			return target
		end
	end
	local near = enemiesNear(player, root.Position, range)
	return near[1] and near[1].model
end

-- Returns true when something was hit.
function AbilityService.Basic(player, target, charged: boolean?): boolean
	local classId = PlayerState.ClassOf(player)
	local root = rootOf(player)
	if not root then
		return false
	end
	local s = state(player)
	local stats = StatService.Get(player)
	if classId == "Gunner" then
		local G = CB.Gunner
		local main = pickTarget(player, target, G.Range)
		if not main then
			return false
		end
		local isCharged = false
		if charged and s.chargeStart and os.clock() - s.chargeStart >= G.ChargeSeconds * 0.9 then
			isCharged = true
		end
		s.chargeStart = nil
		s.shots += 1
		local damage, isCrit = roll(player, if isCharged then G.ChargeMult * (1 + (stats.ChargeBonus or 0)) else 1)
		hit(player, main, damage, isCrit)
		fx("Beam", root.Position + Vector3.new(0, 1, 0), main:GetPivot().Position, if isCharged then Config.Theme.Gold else CB.FxColor, if isCharged then 0.8 else 0.35)
		if s.shots % G.VolleyEvery == 0 then
			local count = G.VolleyTargets + math.floor(stats.VolleyBonus or 0)
			local n = 0
			for _, e in ipairs(enemiesNear(player, root.Position, G.Range)) do
				if e.model ~= main and n < count - 1 then
					n += 1
					local d, c = roll(player, G.VolleyMult)
					hit(player, e.model, d, c)
					fx("Beam", root.Position + Vector3.new(0, 1, 0), e.model:GetPivot().Position, CB.FxColor, 0.3)
				end
			end
		end
		return true
	end

	local def = if classId == "Pulse" then CB.Pulse elseif classId == "Blade" then CB.Blade else nil
	if not def then
		-- no class yet: a plain hit
		local main = pickTarget(player, target, Config.Click.MeleeRange)
		if main then
			local damage, isCrit = StatService.RollHit(player)
			hit(player, main, damage, isCrit)
			return true
		end
		return false
	end
	local t = os.clock()
	s.combo = if t - s.lastHit <= def.ComboWindow then s.combo % 3 + 1 else 1
	s.lastHit = t
	local step = s.combo
	local power = def.Combo[step] * (if step == 3 then 1 + (stats.ComboBonus or 0) else 1)
	if classId == "Pulse" and step == 3 then
		local any = false
		for _, e in ipairs(enemiesNear(player, root.Position, def.ThirdRadius)) do
			local d, c = roll(player, power)
			hit(player, e.model, d, c)
			any = true
		end
		fx("Ring", root.Position, def.ThirdRadius, Config.ClassById.Pulse.Color)
		return any
	end
	local main = pickTarget(player, target, def.Range)
	if not main then
		return false
	end
	local damage, isCrit = roll(player, power)
	hit(player, main, damage, isCrit)
	if classId == "Blade" and step == 3 then
		local center = main:GetPivot().Position
		for _, e in ipairs(enemiesNear(player, center, def.ThirdArc)) do
			if e.model ~= main then
				local d, c = roll(player, power * 0.6)
				hit(player, e.model, d, c)
			end
		end
		fx("Ring", center, def.ThirdArc, Config.ClassById.Blade.Color)
	end
	return true
end

---------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------

local turrets = {} -- [model] = true

local function spawnTurret(player, ability, rank: number)
	local root = rootOf(player)
	if not root then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Turret"
	local base = WorldKit.Part(model, {
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 2.4, 2.4),
		CFrame = CFrame.new(root.Position + root.CFrame.RightVector * 3 - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
	})
	local head = WorldKit.Part(model, {
		Name = "Head",
		Size = Vector3.new(1.4, 1, 1.8),
		CFrame = base.CFrame * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, 1, 0),
		Color = Config.Theme.Gold,
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
	})
	local eye = WorldKit.Part(model, { Name = "Eye", Size = Vector3.new(0.5, 0.3, 0.1), CFrame = head.CFrame * CFrame.new(0, 0.1, -0.92), Color = CB.FxColor, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
	local _ = eye
	if ability.Drone then
		base.Transparency = 1
	end
	model.Parent = Workspace
	turrets[model] = true
	local duration = Config.RankValue(ability.Duration, rank)
	local power = Config.RankValue(ability.Power, rank)
	task.spawn(function()
		local ends = os.clock() + duration
		while os.clock() < ends and model.Parent and player.Parent do
			local r = rootOf(player)
			if ability.Drone and r then
				local p = r.Position + Vector3.new(2.5, 3.5, 2)
				model:PivotTo(CFrame.new(p))
			end
			local origin = head.Position
			local near = enemiesNear(player, origin, ability.Range or 40)
			if near[1] then
				local d, c = roll(player, power, true)
				hit(player, near[1].model, d, c)
				fx("Beam", origin, near[1].model:GetPivot().Position, Config.Theme.Gold, 0.25)
			end
			task.wait(1)
		end
		turrets[model] = nil
		model:Destroy()
	end)
end

local function area(player, ability, rank: number, center: Vector3)
	local radius = ability.Radius or 9
	local power = Config.RankValue(ability.Power, rank)
	if ability.Kind == "Trap" then
		local duration = Config.RankValue(ability.Duration, rank)
		fx("Area", center, radius, duration, Color3.fromRGB(255, 120, 40))
		task.spawn(function()
			for _ = 1, math.max(1, math.floor(duration)) do
				for _, e in ipairs(enemiesNear(player, center, radius)) do
					local d, c = roll(player, power, true)
					hit(player, e.model, d, c)
					AbilityService.Slow(player, e.model, 1.2)
				end
				task.wait(1)
			end
		end)
	else -- Barrage: a strike after a short warning
		fx("Area", center, radius, 0.6, Config.Theme.Gold)
		task.delay(0.6, function()
			for _, e in ipairs(enemiesNear(player, center, radius)) do
				local d, c = roll(player, power, true)
				hit(player, e.model, d, c)
			end
			fx("Ring", center, radius, Config.Theme.Gold)
		end)
	end
end

-- Runs one ability. Returns ok, message.
local function execute(player, node, rank: number, aim): (boolean, string?)
	local ability = node.Ability
	local kind = ability.Kind
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local direction = aimDirection(player, aim)
	local origin = root.Position
	local power = Config.RankValue(ability.Power, rank) or 1
	local color = (Config.ClassById[node.Class] or {}).Color or CB.FxColor

	if kind == "Shield" then
		local duration = Config.RankValue(ability.Duration, rank)
		setBuff(player, "Shield", Config.RankValue(ability.Value, rank), duration)
		if ability.Heal then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * Config.RankValue(ability.Heal, rank))
		end
		fx("Shield", player.Character, duration, color)
		return true
	elseif kind == "Rage" or kind == "Haste" then
		local duration = Config.RankValue(ability.Duration, rank)
		setBuff(player, kind, Config.RankValue(ability.Value, rank), duration)
		fx("Aura", player.Character, duration, if kind == "Rage" then Color3.fromRGB(255, 90, 60) else Config.Theme.Gold)
		return true
	elseif kind == "Heal" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * Config.RankValue(ability.Value, rank))
		fx("Heal", player.Character)
		return true
	elseif kind == "Turret" then
		spawnTurret(player, ability, rank)
		return true
	end

	if kind == "Spin" or kind == "Quake" then
		local radius = ability.Radius or 10
		local hits = ability.Hits or 1
		task.spawn(function()
			for i = 1, hits do
				local r = rootOf(player)
				local center = if r then r.Position else origin
				for _, e in ipairs(enemiesNear(player, center, radius)) do
					local d, c = roll(player, power, true)
					hit(player, e.model, d, c)
					if kind == "Quake" and e.model.Parent then
						AbilityService.Stun(player, e.model, Config.RankValue(ability.Duration, rank))
					end
				end
				fx("Ring", center, radius, if kind == "Quake" then Config.Theme.Gold else color)
				if i < hits then
					task.wait(0.35)
				end
			end
		end)
		return true
	elseif kind == "Pull" then
		local radius = ability.Radius or 14
		local list = enemiesNear(player, origin, radius)
		if #list == 0 then
			return false, Config.Combat.Texts.NoTarget
		end
		for _, e in ipairs(list) do
			if DungeonRuns.IsMob(e.model) and not e.model:GetAttribute("Boss") then
				local p = e.model:GetPivot()
				local to = Vector3.new(origin.X - p.X, 0, origin.Z - p.Z)
				if to.Magnitude > 4 then
					e.model:PivotTo(p + to.Unit * (to.Magnitude - 4))
				end
			end
			local d, c = roll(player, power, true)
			hit(player, e.model, d, c)
			if e.model.Parent then
				AbilityService.Stun(player, e.model, Config.RankValue(ability.Duration, rank))
			end
		end
		fx("Ring", origin, radius, Color3.fromRGB(160, 90, 255))
		return true
	elseif kind == "Wave" then
		local list = enemiesInFront(player, origin, direction, ability.Range or 16, 35)
		for _, e in ipairs(list) do
			local d, c = roll(player, power, true)
			hit(player, e.model, d, c)
			if e.model.Parent then
				AbilityService.Slow(player, e.model, Config.RankValue(ability.Duration, rank))
			end
		end
		fx("Beam", origin, origin + direction * (ability.Range or 16), color, 0.6)
		return true
	elseif kind == "Volley" then
		local list = enemiesInFront(player, origin, direction, ability.Range or 60, 60)
		if #list == 0 then
			list = enemiesNear(player, origin, ability.Range or 60)
		end
		if #list == 0 then
			return false, Config.Combat.Texts.NoTarget
		end
		for i = 1, math.min(#list, ability.Targets or 3) do
			local d, c = roll(player, power, true)
			hit(player, list[i].model, d, c)
			fx("Beam", origin + Vector3.new(0, 1, 0), list[i].model:GetPivot().Position, color, 0.4)
		end
		return true
	elseif kind == "Trap" or kind == "Barrage" then
		local near = enemiesNear(player, origin, ability.Range or CB.AutoAim)
		local center = if near[1] then near[1].model:GetPivot().Position elseif typeof(aim) == "Vector3" and (aim - origin).Magnitude < 40 then aim else origin + direction * 8
		area(player, ability, rank, center)
		return true
	end

	-- single target: Strike / Shot / Stun
	local range = ability.Range or 11
	local list = enemiesInFront(player, origin, direction, range, 60)
	local target = list[1] and list[1].model or (enemiesNear(player, origin, math.min(range, CB.AutoAim))[1] or {}).model
	if not target then
		return false, Config.Combat.Texts.NoTarget
	end
	local d, c = roll(player, power, true)
	hit(player, target, d, c)
	if kind == "Stun" and target.Parent then
		AbilityService.Stun(player, target, Config.RankValue(ability.Duration, rank))
	end
	if kind == "Shot" or range > 30 then
		fx("Beam", origin + Vector3.new(0, 1, 0), target:GetPivot().Position, color, 0.6)
	else
		fx("Ring", target:GetPivot().Position, 4, color)
	end
	return true
end

local function setCooldown(player, slot: string, seconds: number)
	local s = state(player)
	s.cooldowns[slot] = os.clock() + seconds
	player:SetAttribute("Ready_" .. slot, now() + seconds)
	player:SetAttribute("CooldownMax_" .. slot, seconds)
end

local function ready(player, slot: string): boolean
	return os.clock() >= (state(player).cooldowns[slot] or 0)
end

function AbilityService.Use(player, slot: string, aim)
	if not table.find(SK.Slots, slot) or not ready(player, slot) then
		return
	end
	local classId = PlayerState.ClassOf(player)
	local data = DataService.Get(player)
	if classId == "" or not data then
		Remotes.Notify(player, Config.Combat.Texts.NeedClass, "bad")
		return
	end
	local ranks = PlayerState.SkillRanks(player)
	local record = PlayerState.ClassRecord(data, classId)
	local node = Config.SkillById[record.Loadout[slot] or ""]
	local rank = node and ranks[node.Id] or 0
	if not node or not node.Active or rank <= 0 then
		return
	end
	local ok, message = execute(player, node, rank, aim)
	if ok then
		local stats = StatService.Get(player)
		local cooldown = Config.RankValue(node.Ability.Cooldown, rank) * (1 - math.min(0.5, stats.CooldownPct or 0))
		setCooldown(player, slot, cooldown)
		EquipmentService.Swing(player)
	elseif message then
		Remotes.Notify(player, message, "bad")
	end
end

function AbilityService.Dash(player, direction)
	if typeof(direction) ~= "Vector3" or not ready(player, "Dash") then
		return
	end
	local classId = PlayerState.ClassOf(player)
	if classId == "" then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	flat = flat.Unit
	local stats = StatService.Get(player)
	local distance = CB.Dash.Distance + (stats.Dash or 0)
	setCooldown(player, "Dash", CB.Dash.Cooldown)
	Remotes.Get("Ability"):FireClient(player, "Dash", flat, distance, CB.Dash.Seconds)
	fx("Dash", player.Character, CB.Dash.Seconds)
	if classId == "Pulse" then
		local origin = root.Position
		task.delay(CB.Dash.Seconds * 0.5, function()
			for _, e in ipairs(enemiesNear(player, origin + flat * distance / 2, distance / 2 + CB.Dash.Width)) do
				local p = e.model:GetPivot().Position
				local along = (p - origin):Dot(flat)
				local side = ((p - origin) - flat * along)
				side = Vector3.new(side.X, 0, side.Z)
				if along >= -2 and along <= distance + 2 and side.Magnitude <= CB.Dash.Width then
					local d, c = roll(player, CB.Dash.PulseMult + (stats.DashPower or 0), true)
					hit(player, e.model, d, c)
				end
			end
		end)
	end
end

function AbilityService.Block(player, on: boolean)
	local s = state(player)
	local humanoid = humanoidOf(player)
	on = on == true and PlayerState.ClassOf(player) == "Blade"
	s.blocking = on
	player:SetAttribute("Blocking", on)
	if humanoid then
		humanoid.WalkSpeed = if on then CB.Block.WalkSpeed else 16
	end
end

---------------------------------------------------------------------
-- Incoming damage (MobAI): returns the damage that should be taken.
---------------------------------------------------------------------

function AbilityService.Incoming(player, amount: number, attacker: Model?): number
	local s = state(player)
	local stats = StatService.Get(player)
	local shield = buff(player, "Shield")
	if shield > 0 then
		amount *= 1 - math.min(1, shield)
	end
	if s.blocking then
		amount *= 1 - math.min(0.95, CB.Block.Reduction + (stats.BlockBonus or 0))
	end
	if attacker and (stats.Thorns or 0) > 0 and DungeonRuns.IsMob(attacker) then
		DungeonRuns.Damage(player, attacker, amount * stats.Thorns * 3, false)
	end
	local humanoid = humanoidOf(player)
	if humanoid and (stats.CheatDeath or 0) > 0 and humanoid.Health - amount <= 0 and os.clock() - s.cheatAt >= SK.CheatDeathCooldown then
		s.cheatAt = os.clock()
		humanoid.Health = humanoid.MaxHealth * 0.5
		fx("Heal", player.Character)
		Remotes.Notify(player, "Спасение от смерти!", "gold")
		return 0
	end
	return amount
end

function AbilityService.Init()
	local allow = RateLimit.new(0.08)
	Remotes.Get("Ability").OnServerEvent:Connect(function(player, action, a, b)
		if not allow(player) or not PlayerState.IsReady(player) then
			return
		end
		if action == "Use" and type(a) == "string" then
			AbilityService.Use(player, a, b)
		elseif action == "Dash" then
			AbilityService.Dash(player, a)
		elseif action == "Block" then
			AbilityService.Block(player, a == true)
		elseif action == "Charge" then
			state(player).chargeStart = os.clock()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	-- abilities never carry over between characters
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local s = states[player]
			if s then
				s.buffs = {}
				s.blocking = false
			end
			player:SetAttribute("Blocking", false)
		end)
	end)
end

return AbilityService
