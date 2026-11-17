--[[
	Dialog.luau
	NPC dialog at the bottom of the screen (reference style: dark cut
	panel, gold line): the NPC's name and role, what they say, the quest
	card (title, objective, progress, reward) and the buttons
	"Получить награду" (when the step is done) / "Закрыть".
	Dialog.Open(payload) with the payload of Quest:InvokeServer("Talk").
	Closes itself when the player walks away.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.Parent.Style)
local Icons = require(script.Parent.Parent.Icons)
local Popups = require(script.Parent.Parent.Popups)

local C = Style.Colors
local Q = Config.Quests
local player = Players.LocalPlayer

local Dialog = {}

local WIDTH, HEIGHT = 640, 230

local panel = Style.Panel(Style.Gui, {
	Name = "Dialog",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(WIDTH, HEIGHT),
	ZIndex = 30,
	Border = C.GoldDim,
	Cut = 12,
	Visible = false,
})
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(WIDTH, HEIGHT)
panel.Size = UDim2.new(1, -32, 0, HEIGHT)
limit.Parent = panel

local plate = Style.Panel(panel, { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(40, 40), Fill = C.PanelDark, Border = C.Gold, Cut = 6, ZIndex = 31 })
local plateIcon = Icons.Make(plate, "quest", 22, C.Gold, 32)
plateIcon.AnchorPoint = Vector2.new(0.5, 0.5)
plateIcon.Position = UDim2.fromScale(0.5, 0.5)

local nameLabel = Style.Label(panel, "", 20, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(64, 12), Size = UDim2.new(1, -80, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
local roleLabel = Style.Label(panel, "", 13, C.Cyan, { Position = UDim2.fromOffset(64, 36), Size = UDim2.new(1, -80, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
Style.Rule(panel, { Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 0, 1), ZIndex = 31 })
local speech = Style.Label(panel, "", 16, C.Text, {
	Position = UDim2.fromOffset(16, 70),
	Size = UDim2.new(1, -32, 0, 44),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 31,
})

-- quest card
local card = Style.Panel(panel, { Position = UDim2.fromOffset(14, 118), Size = UDim2.new(1, -228, 0, 98), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 31 })
local stepLabel = Style.Label(card, "", 11, C.Gold, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32 })
local questTitle = Style.Label(card, "", 16, C.Text, { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32 })
local questText = Style.Label(card, "", 12, C.Muted, { Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 32 })
local _, fill = Style.Bar(card, { Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -80, 0, 6), Color = C.Gold, ZIndex = 32 })
local countLabel = Style.Label(card, "", 12, C.Text, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 58), Size = UDim2.fromOffset(60, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 32 })
local rewardLabel = Style.Label(card, "", 12, C.Gold, { Position = UDim2.fromOffset(10, 76), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32 })

local claimButton = Style.Button(panel, {
	Name = "Claim",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 118),
	Size = UDim2.fromOffset(196, 44),
	Text = Style.Upper(Q.Texts.Claim),
	Color = C.Gold,
	TextSize = 16,
	ZIndex = 31,
})
local closeButton = Style.Button(panel, {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 172),
	Size = UDim2.fromOffset(196, 44),
	Text = Style.Upper(Q.Texts.Close),
	Color = C.Card,
	TextSize = 16,
	ZIndex = 31,
})

local openedAt -- where the player stood when the dialog opened

function Dialog.Close()
	panel.Visible = false
	openedAt = nil
end

function Dialog.Open(payload)
	nameLabel.Text = Style.Upper(payload.Name or "")
	roleLabel.Text = payload.Title or ""
	speech.Text = payload.Text or ""
	local q = payload.Quest
	card.Visible = q ~= nil
	if q then
		stepLabel.Text = ("ЗАДАНИЕ %d / %d"):format(q.Step or 1, q.Steps or 1)
		questTitle.Text = q.Title or ""
		questText.Text = q.Text or ""
		local target = math.max(1, q.Target or 1)
		local progress = math.clamp(q.Progress or 0, 0, target)
		fill.Size = UDim2.fromScale(progress / target, 1)
		countLabel.Text = ("%d/%d"):format(progress, target)
		rewardLabel.Text = payload.Reward or ""
	end
	claimButton.Visible = payload.Ready == true
	closeButton.Text = Style.Upper(if q and not payload.Ready then Q.Texts.Accept else Q.Texts.Close)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	openedAt = root and root.Position
	panel.Visible = true
	Style.PlaySound("Ui", 0.9, 0.5)
end

claimButton.Activated:Connect(function()
	local ok, message = ReplicatedStorage:WaitForChild("Quest"):InvokeServer("Claim")
	if ok then
		Popups.Toast(message, "gold")
		Style.PlaySound(Config.Sounds.Buy, 1, 0.6)
		Dialog.Close()
		-- the next step at once
		local next = ReplicatedStorage.Quest:InvokeServer("Talk", "Mentor")
		if type(next) == "table" then
			Dialog.Open(next)
		end
	elseif message then
		Popups.Toast(message, "red")
	end
end)
closeButton.Activated:Connect(Dialog.Close)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and panel.Visible and input.KeyCode == Enum.KeyCode.Escape then
		Dialog.Close()
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		if panel.Visible and openedAt then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root or (root.Position - openedAt).Magnitude > 16 then
				Dialog.Close()
			end
		end
	end
end)

return Dialog
