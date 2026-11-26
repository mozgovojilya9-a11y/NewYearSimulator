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

-- One broken module must not take the whole UI down: each is loaded
-- separately and an error is printed to Output with the module name.
local function load(folder: Instance, name: string)
	local ok, err = xpcall(function()
		require(folder:WaitForChild(name))
	end, debug.traceback)
	if not ok then
		warn(("[Client] %s не загрузился: %s"):format(name, tostring(err)))
	end
end

load(ui, "Style")
load(ui, "Popups")
load(ui, "SystemNotice")
load(windows, "Window")
load(windows, "Inventory")
load(windows, "Forge")
load(windows, "Artifacts")
load(windows, "Status")
load(windows, "Store")
load(windows, "Reward")
load(windows, "Settings")
load(windows, "RunSummary")
load(windows, "Gates")
load(windows, "Skills")
load(windows, "Dialog")
load(ui, "Hud")
load(ui, "ClassSelect")
load(modules, "Swing")
load(modules, "MobFx")
load(modules, "GateHud")
load(modules, "Combat")
load(modules, "AbilityFx")
load(modules, "LootFx")
load(modules, "Afk")
load(modules, "Zone")
load(modules, "Prompts")
load(modules, "HubLife")
load(modules, "QuestGuide")
load(modules, "ItemFx")
load(modules, "ArmorFx")
