--[[
	GameEvents.luau
	Tiny signal for gameplay facts quests listen to, so services don't
	require each other in circles:
	  GameEvents.Fire(player, kind, amount)
	  kind: Kill, Boss, Loot, Craft, Train, Learn, Class, Room, Level
	  GameEvents.Connect(function(player, kind, amount) ... end)
]]

local GameEvents = {}

local listeners = {}

function GameEvents.Connect(callback)
	table.insert(listeners, callback)
end

function GameEvents.Fire(player, kind: string, amount: number?)
	for _, callback in ipairs(listeners) do
		task.spawn(callback, player, kind, amount or 1)
	end
end

return GameEvents
