--[[
	Client.client.luau
	Client entry point. Hides the default player list (leaderstats still
	hold the data) and requires every module; each one builds its own
	UI / hooks when required.
]]

local StarterGui = game:GetService("StarterGui")

local function hidePlayerList()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end
task.spawn(hidePlayerList)

local modules = script.Parent
local ui = modules:WaitForChild("ui")
local windows = ui:WaitForChild("Windows")

require(ui:WaitForChild("Style"))
require(ui:WaitForChild("Popups"))
require(windows:WaitForChild("Window"))
require(windows:WaitForChild("Shop")) -- waits for leaderstats
require(windows:WaitForChild("Rebirth"))
require(windows:WaitForChild("Reward"))
require(windows:WaitForChild("Settings"))
require(ui:WaitForChild("Buttons"))
require(ui:WaitForChild("Hud"))
require(modules:WaitForChild("HubFx"))
require(modules:WaitForChild("Combat"))
require(modules:WaitForChild("Zone"))
require(modules:WaitForChild("Prompts"))
require(modules:WaitForChild("Cosmetics"))
