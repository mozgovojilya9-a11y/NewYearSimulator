--[[
	Swing.luau
	Procedural weapon swing for every character: when a character's
	"Swing" attribute changes (server bumps it per accepted click) the
	right shoulder Motor6D is tweened forward and back. The local player also swings
	immediately on their own click (Swing.Local) so it feels instant.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local S = Config.Equipment.Swing

local Swing = {}

local baseC0 = {} -- [motor] = original C0
local swinging = {} -- [character] = true

local function shoulderOf(character)
	local r15 = character:FindFirstChild("RightUpperArm")
	if r15 then
		return r15:FindFirstChild("RightShoulder"), true
	end
	local torso = character:FindFirstChild("Torso")
	return torso and torso:FindFirstChild("Right Shoulder"), false
end

local function play(character)
	if swinging[character] then
		return
	end
	local motor, isR15 = shoulderOf(character)
	if not motor then
		return
	end
	swinging[character] = true
	if not baseC0[motor] then
		baseC0[motor] = motor.C0
	end
	local base = baseC0[motor]
	local raise = if isR15 then S.RaiseR15 else S.RaiseR6

	local up = Style.Tween(motor, S.UpSeconds, { C0 = base * raise }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	up.Completed:Wait()
	Style.Tween(motor, S.DownSeconds, { C0 = base }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
	swinging[character] = nil
end

local lastLocal = 0
local lastSeen = {} -- [character] = last Swing value handled

local function watch(character)
	lastSeen[character] = character:GetAttribute("Swing") or 0
	character:GetAttributeChangedSignal("Swing"):Connect(function()
		local value = character:GetAttribute("Swing") or 0
		if value == lastSeen[character] then
			return
		end
		lastSeen[character] = value
		-- The local player already played this swing on click.
		if character == player.Character and os.clock() - lastLocal < 0.3 then
			return
		end
		task.spawn(play, character)
	end)
end

local function watchPlayer(other)
	if other.Character then
		watch(other.Character)
	end
	other.CharacterAdded:Connect(watch)
end
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Instant local swing on our own click.
function Swing.Local()
	lastLocal = os.clock()
	if player.Character then
		task.spawn(play, player.Character)
	end
end

return Swing
