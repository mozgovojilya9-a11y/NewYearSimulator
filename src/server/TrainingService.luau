--[[
	TrainingService.luau
	Training hall stations (Config.Training, built by HubGenerator):
	E on a station -> the client asks Training:FireServer("Start", index).
	The server checks the level lock, puts the player on the station's
	spot facing it, stops walking, and every Tick seconds gives a little
	XP (station Xp x player level; much less than fights). The session
	ends on "Выйти" ("Stop"), death, walking away or leaving the hub.

	Player attribute Training = "<stationId>" while training (the client
	plays the exercise and shows the panel), "" otherwise.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local PlayerState = require(script.Parent.PlayerState)
local ProgressionService = require(script.Parent.ProgressionService)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local TR = Config.Training

local TrainingService = {}

local stations = {} -- [index] = { Def, Spot (CFrame), Face (CFrame) }
local sessions = {} -- [player] = { Station, Spot, WalkSpeed, JumpPower, Ticks }

local function humanoidOf(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

local function stop(player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	player:SetAttribute("Training", "")
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = session.WalkSpeed
		humanoid.JumpPower = session.JumpPower
	end
end
TrainingService.Stop = stop

local function start(player, index)
	local station = stations[index]
	local data = DataService.Get(player)
	if not station or not data or player:GetAttribute("Zone") ~= "Hub" then
		return
	end
	local humanoid, root = humanoidOf(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if (root.Position - station.Spot.Position).Magnitude > 14 then
		return
	end
	if (data.Level or 1) < station.Def.Level then
		Remotes.Notify(player, TR.Texts.Locked:format(station.Def.Level), "red")
		return
	end
	for other, session in pairs(sessions) do
		if other ~= player and session.Station == index then
			Remotes.Notify(player, TR.Texts.Busy, "red")
			return
		end
	end
	stop(player)
	sessions[player] = { Station = index, Spot = station.Spot.Position, WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, Ticks = 0 }
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	-- stand on the spot, facing the machine
	local spot = station.Spot.Position
	local look = station.Face.Position
	root.CFrame = CFrame.lookAt(Vector3.new(spot.X, root.Position.Y, spot.Z), Vector3.new(look.X, root.Position.Y, look.Z))
	player:SetAttribute("Training", station.Def.Id)
end

local function tick()
	for player, session in pairs(sessions) do
		local humanoid, root = humanoidOf(player)
		local station = stations[session.Station]
		if not humanoid or not root or humanoid.Health <= 0 or player:GetAttribute("Zone") ~= "Hub" or (root.Position - session.Spot).Magnitude > TR.MaxDistance then
			stop(player)
		else
			local data = DataService.Get(player)
			if data then
				local xp = station.Def.Xp * math.max(1, data.Level or 1)
				ProgressionService.AddXp(player, xp)
				Remotes.Get("Training"):FireClient(player, "Gain", xp)
				session.Ticks += 1
				if session.Ticks == 1 then
					GameEvents.Fire(player, "Train", 1)
				end
			end
		end
	end
end

function TrainingService.Init(hub)
	for _, s in ipairs(hub.Stations or {}) do
		-- Spot = where the player stands, Face = the machine (the player looks at it)
		stations[s.Index] = { Def = s.Def, Spot = s.Spot, Face = s.Face }
	end
	local allow = RateLimit.new(0.4)
	Remotes.Get("Training").OnServerEvent:Connect(function(player, action, index)
		if not allow(player) or not PlayerState.IsReady(player) then
			return
		end
		if action == "Start" and type(index) == "number" then
			start(player, index)
		elseif action == "Stop" then
			stop(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Training", "")
		player.CharacterAdded:Connect(function()
			sessions[player] = nil
			player:SetAttribute("Training", "")
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(TR.Tick)
			tick()
		end
	end)
end

return TrainingService
