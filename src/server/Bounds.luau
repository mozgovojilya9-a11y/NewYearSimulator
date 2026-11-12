--[[
	Bounds.luau
	Last line of defence against leaving the map. The world itself is
	closed by invisible walls (HubGenerator / DungeonGenerator); if a
	character still ends up below Config.Bounds.FallY, it is teleported
	back softly: hub -> spawn, dungeon -> entrance of the current room.
	No death, the run goes on. FallenPartsDestroyHeight is far below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonRuns = require(script.Parent.DungeonRuns)
local Remotes = require(script.Parent.Remotes)

local Bounds = {}

local B = Config.Bounds

function Bounds.Init(hub)
	local groundY = hub.GroundY
	Workspace.FallenPartsDestroyHeight = groundY + B.DestroyY

	task.spawn(function()
		while true do
			task.wait(B.CheckInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root.Position.Y < groundY + B.FallY then
					local target = DungeonRuns.RecoveryCFrame(player) or hub.SpawnCFrame
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					character:PivotTo(target)
					Remotes.Notify(player, B.Text)
				end
			end
		end
	end)
end

return Bounds
