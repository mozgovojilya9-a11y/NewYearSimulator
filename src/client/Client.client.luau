--[[
	Client.client.luau
	Client entry point. Each feature lives in its own ModuleScript next
	to this script; requiring it builds its UI and hooks up its events.
]]

local modules = script.Parent

require(modules:WaitForChild("Ui"))
require(modules:WaitForChild("ClickButton"))
require(modules:WaitForChild("Combat"))
require(modules:WaitForChild("TopBar")) -- waits for leaderstats
