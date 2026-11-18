--[[
	Prompts.luau
	Custom look for every ProximityPrompt (Style = Custom): a plain
	circle with "E" and one short word under it (Config.Interact; phones:
	tap the circle). Loot is held: the circle fills. Also routes prompts that only open client windows
	(Action = OpenForge / OpenStore / Wheel).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)
local Forge = require(script.Parent.ui.Windows.Forge)
local Store = require(script.Parent.ui.Windows.Store)
local Reward = require(script.Parent.ui.Windows.Reward)
local ClassSelect = require(script.Parent.ui.ClassSelect)
local Dialog = require(script.Parent.ui.Windows.Dialog)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Prompts = {}

local ACTIONS = {
	OpenForge = function()
		Forge.Open()
	end,
	OpenStore = function()
		Store.Open()
	end,
	Wheel = function()
		Reward.OpenWheel()
	end,
	OpenClasses = function()
		ClassSelect.Open(true)
	end,
	-- NPC: the mentor opens the story dialog, the gate keeper the daily quests
	Talk = function(prompt)
		local npc = prompt:GetAttribute("Npc")
		if npc == "GateKeeper" then
			Reward.OpenQuests()
			return
		end
		local ok, payload = pcall(function()
			return ReplicatedStorage:WaitForChild("Quest"):InvokeServer("Talk", npc)
		end)
		if ok and type(payload) == "table" then
			Dialog.Open(payload)
		end
	end,
	Train = function(prompt)
		ReplicatedStorage:WaitForChild("Training"):FireServer("Start", prompt:GetAttribute("Index"))
	end,
}


local IA = Config.Interact

-- A plain circle with the key letter and one short word under it. A held
-- prompt (loot) fills the circle while held. On phones the circle itself
-- is the button (tap; loot: hold the tap).
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return
	end
	local size = IA.Size
	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptUI"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(120, size + 26)
	-- loot drops carry their own name plate above: their circle sits lower
	gui.StudsOffsetWorldSpace = Vector3.new(0, if prompt:GetAttribute("NoPlate") then -1.4 else math.min(adornee.Size.Y / 2 + 1.5, 6), 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40
	gui.Active = true
	gui.LightInfluence = 0
	gui.Parent = playerGui

	local circle = Instance.new("TextButton")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0)
	circle.Position = UDim2.fromScale(0.5, 0)
	circle.Size = UDim2.fromOffset(size, size)
	circle.BackgroundColor3 = Style.Colors.PanelDark
	circle.BackgroundTransparency = 0.15
	circle.AutoButtonColor = false
	circle.Text = ""
	circle.Parent = gui
	Style.Corner(circle, UDim.new(0.5, 0))
	Style.Stroke(circle, 2, Style.Colors.Gold)

	-- hold fill (loot): a gold disc that grows from the centre
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = Style.Colors.Gold
	fill.BackgroundTransparency = 0.35
	fill.Parent = circle
	Style.Corner(fill, UDim.new(0.5, 0))

	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local key = Style.Label(circle, if touch then "" else IA.Key, 26, Style.Colors.Text, { Font = Style.FontTitle, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	if touch then
		local icon = require(script.Parent.ui.Icons).Make(circle, "tap", 26, Style.Colors.Text, 3)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	end
	local _ = key
	local word = prompt.ActionText:match("^(%S+)") or prompt.ActionText
	Style.Label(gui, word, 15, Style.Colors.Text, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, size + 4), Size = UDim2.new(1, 0, 0, 18) })

	circle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	circle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)

	local pop = Instance.new("UIScale")
	pop.Scale = 0.5
	pop.Parent = circle
	Style.Tween(pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)

	local beginConnection = prompt.PromptButtonHoldBegan:Connect(function()
		if prompt.HoldDuration > 0 then
			Style.Tween(fill, prompt.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
	end)
	local endConnection = prompt.PromptButtonHoldEnded:Connect(function()
		Style.Tween(fill, 0.1, { Size = UDim2.fromScale(0, 0) })
	end)
	local triggered = prompt.Triggered:Connect(function()
		pop.Scale = 1.2
		Style.Tween(pop, 0.15, { Scale = 1 })
	end)

	prompt.PromptHidden:Wait()
	beginConnection:Disconnect()
	endConnection:Disconnect()
	triggered:Disconnect()
	Style.Tween(pop, 0.12, { Scale = 0.5 })
	task.wait(0.12)
	gui:Destroy()
end)

-- Hub interactions that only open client windows.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local action = ACTIONS[prompt:GetAttribute("Action")]
	if action then
		action(prompt)
	end
end)

return Prompts
