--[[
	RateLimit.luau
	Per-player cooldown gate. Usage:
		local allow = RateLimit.new(0.1)
		if not allow(player) then return end
]]

local Players = game:GetService("Players")

local RateLimit = {}

function RateLimit.new(cooldown: number)
	local last = {} -- [player] = os.clock() of last allowed call

	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)

	return function(player): boolean
		local now = os.clock()
		local previous = last[player]
		if previous and now - previous < cooldown then
			return false
		end
		last[player] = now
		return true
	end
end

return RateLimit
