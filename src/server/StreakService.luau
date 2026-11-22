--[[
	StreakService.luau
	Охотничий азарт: a kill streak in the gates (Config.Streak). Every kill
	within Window seconds of the previous one adds stacks; stacks raise XP,
	drop chance and credits (Mult). Milestones pay a bonus (OnMilestone,
	set by LootService). The client gets ClickHit "Streak" (count, window
	seconds, xp %, loot %, milestone text?) and "StreakEnd".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local S = Config.Streak

local StreakService = {}
StreakService.OnMilestone = nil -- (player, milestone, room, position, rank)

local streaks = {} -- [player] = { count, last, reached = { [At] = true } }

local function send(player, ...)
	Remotes.Get("ClickHit"):FireClient(player, ...)
end

-- The current multiplier of `kind` ("Xp" / "Loot" / "Credits").
function StreakService.Mult(player, kind: string): number
	local s = streaks[player]
	if not s or os.clock() - s.last > S.Window then
		return 1
	end
	return 1 + s.count * (S.Per[kind] or 0)
end

function StreakService.Count(player): number
	local s = streaks[player]
	return if s and os.clock() - s.last <= S.Window then s.count else 0
end

function StreakService.Kill(player, enemy: string?, room: number, position: Vector3?, rank: string?)
	local now = os.clock()
	local s = streaks[player]
	if not s or now - s.last > S.Window then
		s = { count = 0, last = now, reached = {} }
		streaks[player] = s
	end
	s.count = math.min(S.Max, s.count + (if enemy == "Elite" or enemy == "Boss" then S.Elite else 1))
	s.last = now
	local token = {}
	s.token = token
	local text = nil
	for _, m in ipairs(S.Milestones) do
		if s.count >= m.At and not s.reached[m.At] then
			s.reached[m.At] = true
			text = m.Text
			if StreakService.OnMilestone then
				task.spawn(StreakService.OnMilestone, player, m, room, position, rank)
			end
		end
	end
	send(player, "Streak", s.count, S.Window, math.floor((StreakService.Mult(player, "Xp") - 1) * 100 + 0.5), math.floor((StreakService.Mult(player, "Loot") - 1) * 100 + 0.5), text)
	-- the end of the window: tell the client (unless a newer kill came)
	task.delay(S.Window + 0.05, function()
		if streaks[player] == s and s.token == token and player.Parent then
			if s.count >= S.Milestones[1].At then
				send(player, "StreakEnd", s.count)
			end
			streaks[player] = nil
		end
	end)
end

function StreakService.Init()
	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
	end)
end

return StreakService
