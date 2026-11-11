--[[
	Remotes.luau
	Creates every RemoteEvent / RemoteFunction listed in Config.Remotes
	directly under ReplicatedStorage, and hands them out to services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = {}

function Remotes.Get(name)
	local className = Config.Remotes[name]
	assert(className, "Unknown remote: " .. tostring(name))

	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

-- Shows a toast on one player's screen. kind: "good" | "bad" | "gold" | nil
function Remotes.Notify(player, text: string, kind: string?)
	Remotes.Get("Notify"):FireClient(player, text, kind)
end

function Remotes.Init()
	for name in pairs(Config.Remotes) do
		Remotes.Get(name)
	end
end

return Remotes
