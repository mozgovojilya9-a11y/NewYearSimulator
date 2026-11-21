--[[
	AfkService.luau
	The AFK zone (Config.AFK): a calm floating platform far above the city,
	reached by the HUD button "АФК" [Z] or the portal in the Зал снабжения.
	  Remote Afk ("Enter") / ("Leave") -> ok, message
	While a player is there (Zone = "Afk"), every Tick seconds the server
	gives a little XP, credits, sometimes Кристаллы and with a chance an
	item (Common / Uncommon / Rare only). Rewarded ticks are limited per
	hour (data.Afk = { HourStart, Ticks }); after the limit only
	MinCredits. The session counters go to the client (AfkTick) for the
	AFK window. Nothing can hurt the player there and invisible walls keep
	everyone on the platform; a fall puts the player back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local DungeonRuns = require(script.Parent.DungeonRuns)
local GameEvents = require(script.Parent.GameEvents)
local ItemService = require(script.Parent.ItemService)
local NanoKit = require(script.Parent.NanoKit)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local WorldKit = require(script.Parent.WorldKit)

local AfkService = {}

local A = Config.AFK
local T = A.Texts
local M = NanoKit.Materials
local Panel = NanoKit.Panel

local hub
local spawnCFrame
local sessions = {} -- [player] = { started, xp, credits, crystals, items }
local rng = Random.new()

---------------------------------------------------------------------
-- The place: a round garden platform, the city far below
---------------------------------------------------------------------

local function build()
	local folder = Instance.new("Model")
	folder.Name = "AfkZone"
	local o = A.Origin
	local R = A.Radius
	local stone = Color3.fromRGB(150, 146, 140)
	local warm = Color3.fromRGB(255, 214, 160)
	local violet = Config.Crystals.Color
	-- floor: a stone disc with a lighter inner ring and a thin violet rim
	NanoKit.Cylinder(folder, "Floor", 3, R * 2, CFrame.new(o + Vector3.new(0, -1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), stone, M.Concrete)
	NanoKit.Cylinder(folder, "Inner", 0.2, R * 1.1, CFrame.new(o + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(176, 170, 160), Enum.Material.Pavement).CanCollide = false
	NanoKit.Cylinder(folder, "Lawn", 0.15, R * 1.7, CFrame.new(o + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(96, 128, 88), Enum.Material.Grass).CanCollide = false
	-- a thin violet line along the edge (segments, not a disc)
	-- the underside: a cone of rock so it reads as a floating island
	for i = 1, 4 do
		local r = R * (1 - i * 0.2)
		NanoKit.Cylinder(folder, "Rock", 5, r * 2, CFrame.new(o + Vector3.new(0, -3 - i * 5, 0)) * CFrame.Angles(0, 0, math.rad(90)), stone:Lerp(Color3.new(0, 0, 0), 0.2 + i * 0.1), M.Concrete)
	end
	-- a low glass railing and an invisible wall around it (nobody falls)
	local segments = 36
	for i = 1, segments do
		local a = (i - 0.5) / segments * math.pi * 2
		local p = o + Vector3.new(math.cos(a) * (R - 1), 0, math.sin(a) * (R - 1))
		local cf = CFrame.lookAt(p, Vector3.new(o.X, p.Y, o.Z)) -- -Z looks at the middle
		local w = 2 * math.pi * R / segments + 0.4
		Panel(folder, "Glass", Vector3.new(w, 3, 0.3), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(190, 210, 230), M.Glass, { Transparency = 0.6 })
		Panel(folder, "EdgeLine", Vector3.new(w, 0.12, 0.2), cf * CFrame.new(0, 0.07, -0.4), violet, M.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.3 })
		Panel(folder, "Rail", Vector3.new(w, 0.3, 0.6), cf * CFrame.new(0, 3.1, 0), Color3.fromRGB(140, 140, 150), M.Metal)
		WorldKit.Invisible(folder, Vector3.new(w, 30, 1), (cf * CFrame.new(0, 15, 0.8)).Position, "Wall").CFrame = cf * CFrame.new(0, 15, 0.8)
	end
	WorldKit.Invisible(folder, Vector3.new(R * 2.4, 2, R * 2.4), o + Vector3.new(0, 32, 0), "Lid")
	-- benches in a ring facing the middle, warm lamps between them (Seats:
	-- a player can sit and rest)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local p = o + Vector3.new(math.cos(a) * (R - 9), 0, math.sin(a) * (R - 9))
		local cf = CFrame.lookAt(p, Vector3.new(o.X, p.Y, o.Z))
		Panel(folder, "BenchBase", Vector3.new(6, 1.2, 2), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(60, 60, 68), M.Metal)
		local seat = Instance.new("Seat")
		seat.Name = "Seat"
		seat.Size = Vector3.new(5.6, 0.5, 1.8)
		seat.CFrame = cf * CFrame.new(0, 1.45, 0)
		seat.Color = Color3.fromRGB(120, 88, 70)
		seat.Material = Enum.Material.WoodPlanks
		seat.Anchored = true
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.Parent = folder
		Panel(folder, "Back", Vector3.new(5.6, 2, 0.4), cf * CFrame.new(0, 2.6, 1), Color3.fromRGB(120, 88, 70), Enum.Material.WoodPlanks)
		-- a lamp post between two benches
		local la = a + math.pi / 8
		local lp = o + Vector3.new(math.cos(la) * (R - 5), 0, math.sin(la) * (R - 5))
		NanoKit.Column(folder, "LampPost", 9, 0.5, lp, Color3.fromRGB(50, 50, 58), M.Metal)
		local bulb = NanoKit.Cylinder(folder, "Lamp", 0.8, 1.6, CFrame.new(lp + Vector3.new(0, 9.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), warm, M.Neon)
		bulb.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = warm
		light.Range = 16
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = bulb
	end
	-- small trees in planters
	for i = 1, 6 do
		local a = (i + 0.5) / 6 * math.pi * 2
		local p = o + Vector3.new(math.cos(a) * 16, 0, math.sin(a) * 16)
		NanoKit.Column(folder, "Planter", 1.6, 4.6, p, Color3.fromRGB(80, 78, 86), M.Concrete)
		NanoKit.Column(folder, "Trunk", 5, 0.7, p + Vector3.new(0, 1.6, 0), Color3.fromRGB(90, 66, 50), Enum.Material.Wood)
		local crown = Panel(folder, "Crown", Vector3.new(5, 4.2, 5), CFrame.new(p + Vector3.new(0, 8, 0)), Color3.fromRGB(110, 150, 120), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		NanoKit.Tag(crown, "Bob", { Amplitude = 0.15, Period = 5 + i * 0.3 })
	end
	-- the centre: a slow hologram crystal over a fountain basin
	NanoKit.Cylinder(folder, "Basin", 1.2, 10, CFrame.new(o + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(110, 108, 120), M.Concrete)
	local water = NanoKit.Cylinder(folder, "Water", 0.2, 8.6, CFrame.new(o + Vector3.new(0, 1.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 150, 200), M.Glass)
	water.Transparency = 0.35
	water.CanCollide = false
	local crystal = Panel(folder, "Crystal", Vector3.new(2.2, 4, 2.2), CFrame.new(o + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(45)), violet, M.Glass, { Transparency = 0.25, CanCollide = false })
	NanoKit.Tag(crystal, "Spin", { Speed = 18, Axis = "Y" })
	NanoKit.Tag(crystal, "Bob", { Amplitude = 0.5, Period = 4 })
	local glow = Instance.new("PointLight")
	glow.Color = violet
	glow.Range = 20
	glow.Brightness = 1.2
	glow.Parent = crystal
	-- the way back: a small arch with an "E" circle
	local back = o + Vector3.new(0, 0, R - 4)
	local bcf = CFrame.lookAt(back, Vector3.new(o.X, back.Y, o.Z))
	for _, sx in ipairs({ -1, 1 }) do
		Panel(folder, "ExitPost", Vector3.new(0.8, 8, 0.8), bcf * CFrame.new(sx * 3.5, 4, 0), Color3.fromRGB(60, 60, 70), M.Metal)
	end
	Panel(folder, "ExitTop", Vector3.new(8, 0.8, 1), bcf * CFrame.new(0, 8.2, 0), Color3.fromRGB(60, 60, 70), M.Metal)
	local field = Panel(folder, "ExitField", Vector3.new(6, 7.4, 0.15), bcf * CFrame.new(0, 4, 0), Config.Theme.Cyan, M.Neon, { Transparency = 0.75, CanCollide = false })
	NanoKit.Tag(field, "Pulse", { Period = 3 })
	local anchor = Panel(folder, "ExitAnchor", Vector3.new(1, 1, 1), bcf * CFrame.new(0, 3, -2.5), Config.Theme.Cyan, M.Smooth, { Transparency = 1, CanCollide = false, CanQuery = false })
	WorldKit.Prompt(anchor, "Выйти", "", { Action = "LeaveAfk" })
	-- the city far below: dark towers with thin window lines
	local towerColor = Color3.fromRGB(34, 38, 52)
	for i = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(R + 60, R + 420)
		local h = rng:NextNumber(60, 260)
		local w = rng:NextNumber(14, 34)
		local base = o + Vector3.new(math.cos(a) * d, -520, math.sin(a) * d)
		local tower = Panel(folder, "Tower", Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, h / 2, 0)), towerColor, M.Glass, { CanCollide = false, CastShadow = false })
		tower.Transparency = 0.05
		if i % 2 == 0 then
			local line = Panel(folder, "Windows", Vector3.new(w + 0.2, 0.6, w + 0.2), CFrame.new(base + Vector3.new(0, h * rng:NextNumber(0.3, 0.9), 0)), if i % 4 == 0 then warm else Config.Theme.Cyan, M.Neon, { CanCollide = false, CastShadow = false })
			line.Transparency = 0.3
		end
	end
	-- two more small floating islands to the sides
	for _, off in ipairs({ Vector3.new(-120, -40, -60), Vector3.new(130, -70, 40) }) do
		local p = o + off
		NanoKit.Cylinder(folder, "Island", 3, 26, CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)), stone, M.Concrete).CanCollide = false
		NanoKit.Cylinder(folder, "IslandRock", 10, 16, CFrame.new(p + Vector3.new(0, -6, 0)) * CFrame.Angles(0, 0, math.rad(90)), stone:Lerp(Color3.new(0, 0, 0), 0.35), M.Concrete).CanCollide = false
		local tree = Panel(folder, "IslandTree", Vector3.new(7, 6, 7), CFrame.new(p + Vector3.new(0, 6, 0)), Color3.fromRGB(110, 150, 120), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		local _ = tree
	end
	folder.Parent = workspace
	return folder
end

---------------------------------------------------------------------
-- Enter / leave
---------------------------------------------------------------------

local function arrival(i: number?): CFrame
	local o = A.Origin
	local p = o + Vector3.new(((i or 0) % 5 - 2) * 3, 4, A.Radius - 16)
	return CFrame.lookAt(p, Vector3.new(o.X, p.Y, o.Z))
end

local function send(player)
	local s = sessions[player]
	local data = DataService.Get(player)
	if not s or not data then
		return
	end
	local resetIn = math.max(0, 3600 - (os.time() - (data.Afk.HourStart or 0)))
	Remotes.Get("AfkTick"):FireClient(player, {
		Seconds = os.time() - s.started,
		Xp = s.xp,
		Credits = s.credits,
		Crystals = s.crystals,
		Items = s.items,
		Limited = data.Afk.Ticks >= A.HourLimit and resetIn > 0 and data.Afk.HourStart > 0,
		LeftTicks = math.max(0, A.HourLimit - data.Afk.Ticks),
		ResetIn = resetIn,
	})
end

function AfkService.Enter(player)
	if player:GetAttribute("Zone") ~= "Hub" or DungeonRuns.HasRun(player) then
		return false, T.Busy
	end
	local character = player.Character
	if not character then
		return false, T.Busy
	end
	character:PivotTo(arrival(#Players:GetPlayers()))
	player:SetAttribute("Zone", "Afk")
	sessions[player] = { started = os.time(), xp = 0, credits = 0, crystals = 0, items = 0 }
	send(player)
	Remotes.Notify(player, T.Welcome, "gold")
	return true
end

function AfkService.Leave(player)
	if player:GetAttribute("Zone") ~= "Afk" then
		return false
	end
	sessions[player] = nil
	if player.Character then
		player.Character:PivotTo(spawnCFrame)
	end
	player:SetAttribute("Zone", "Hub")
	return true
end

---------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------

local function rollRarity(): string
	local total = 0
	for _, w in pairs(A.Items) do
		total += w
	end
	local list = {}
	for id, w in pairs(A.Items) do
		table.insert(list, { id = id, w = w })
	end
	table.sort(list, function(a, b)
		return Config.Rarity[a.id].Index < Config.Rarity[b.id].Index
	end)
	local roll = rng:NextNumber() * total
	for _, e in ipairs(list) do
		roll -= e.w
		if roll <= 0 then
			return e.id
		end
	end
	return list[1].id
end

local function tick(player)
	local data = DataService.Get(player)
	local s = sessions[player]
	if not data or not s then
		return
	end
	local now = os.time()
	if now - (data.Afk.HourStart or 0) >= 3600 then
		data.Afk.HourStart = now
		data.Afk.Ticks = 0
	end
	local tier = math.max(1, data.RoomReached or 0)
	if data.Afk.Ticks >= A.HourLimit then
		s.credits += PlayerState.AddCredits(player, A.MinCredits)
		send(player)
		return
	end
	data.Afk.Ticks += 1
	-- XP: a share of the way to the next level
	local xp = math.max(1, math.floor(Config.XpToNext(data.Level) * A.XpShare))
	ProgressionService.AddXp(player, xp)
	s.xp += xp
	s.credits += PlayerState.AddCredits(player, math.max(1, math.floor(Config.KillCredits(tier, false) * A.CreditsTicks)))
	if rng:NextNumber() < A.CrystalChance then
		s.crystals += PlayerState.AddCrystals(player, 1)
		Remotes.Notify(player, "+1 Кристалл (АФК)", "gold")
	end
	if rng:NextNumber() < A.ItemChance and ItemService.HasRoom(player) then
		local level = math.max(1, tier * Config.Items.LevelPerRoom)
		local view = ItemService.Give(player, ItemService.Generate(player, level, rollRarity()))
		if view then
			s.items += 1
			Remotes.Notify(player, ("Предмет (АФК): %s"):format(view.Name), "gold")
		end
	end
	GameEvents.Fire(player, "Afk", A.Tick)
	send(player)
end

function AfkService.Init(hubInfo)
	hub = hubInfo
	spawnCFrame = hub.SpawnCFrame
	build()
	local allow = RateLimit.new(0.5)
	Remotes.Get("Afk").OnServerInvoke = function(player, action)
		if not allow(player) or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		if action == "Enter" then
			return AfkService.Enter(player)
		elseif action == "Leave" then
			return AfkService.Leave(player)
		end
		return false, "Неверный запрос"
	end
	task.spawn(function()
		while true do
			task.wait(A.Tick)
			for player in pairs(sessions) do
				if player.Parent and player:GetAttribute("Zone") == "Afk" then
					task.spawn(tick, player)
				else
					sessions[player] = nil
				end
			end
		end
	end)
	-- nobody leaves the platform: a fall puts the player back
	task.spawn(function()
		while true do
			task.wait(1)
			for player in pairs(sessions) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and root.Position.Y < A.Origin.Y - 30 then
					root.AssemblyLinearVelocity = Vector3.zero
					player.Character:PivotTo(arrival())
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	-- a new character starts in the hub again
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			sessions[player] = nil
			if player:GetAttribute("Zone") == "Afk" then
				player:SetAttribute("Zone", "Hub")
			end
		end)
	end)
end

return AfkService
