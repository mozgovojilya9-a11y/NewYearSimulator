--[[
	RunSummary.luau
	Results of a gate run (GateState "Result"): the grade letter S/A/B/C
	(or "Провал"), the location, time, damage, kills, deaths, the grade's
	loot bonus, everything picked up during the run, and the buttons
	"Ещё раз" (the same location) and "В хаб". After a won run a timer
	shows when the team is sent back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local ItemIcon = require(script.Parent.Parent.ItemIcon)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local GR = Config.Grades
local T = GR.Texts
local player = Players.LocalPlayer
local gateRemote = ReplicatedStorage:WaitForChild("Gate")
local travel = ReplicatedStorage:WaitForChild("Travel")

local RunSummary = {}

local window = Window.new("Итоги", C.Gold, Vector2.new(640, 470), "trophy")
local content = window.Content

local gradeColor = {}
for _, grade in ipairs(GR) do
	gradeColor[grade.Id] = grade.Color
end

-- left: the grade
local gradePanel = Style.Panel(content, { Size = UDim2.fromOffset(170, 200), Fill = C.PanelDark, Border = C.GoldDim, Cut = 12, ZIndex = 33 })
local gradeLetter = Style.Label(gradePanel, "", 110, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 120), ZIndex = 34 })
local gradeScale = Instance.new("UIScale")
gradeScale.Parent = gradeLetter
local resultLine = Style.Label(gradePanel, "", 14, C.Text, { Position = UDim2.fromOffset(6, 146), Size = UDim2.new(1, -12, 0, 18), ZIndex = 34 })
local bonusLine = Style.Label(gradePanel, "", 11, C.Gold, { Position = UDim2.fromOffset(6, 168), Size = UDim2.new(1, -12, 0, 26), TextWrapped = true, ZIndex = 34 })

-- right: numbers
local stats = Style.Panel(content, { Position = UDim2.fromOffset(182, 0), Size = UDim2.new(1, -182, 0, 200), Fill = C.PanelDark, Border = C.Line, Cut = 12, ZIndex = 33 })
local locationLine = Style.Label(stats, "", 18, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
local rows = {}
for i, key in ipairs({ "Time", "Damage", "Kills", "Deaths" }) do
	local y = 44 + (i - 1) * 36
	Style.Label(stats, T[key], 15, C.Muted, { Position = UDim2.fromOffset(14, y), Size = UDim2.new(0.5, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	rows[key] = Style.Label(stats, "", 22, C.Text, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y - 2), Size = UDim2.new(0.5, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
end

-- loot
Style.Label(content, Style.Upper(T.Loot), 13, C.Gold, { Position = UDim2.fromOffset(2, 210), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local lootHolder = Instance.new("Frame")
lootHolder.Position = UDim2.fromOffset(0, 230)
lootHolder.Size = UDim2.new(1, 0, 0, 132)
lootHolder.BackgroundTransparency = 1
lootHolder.ZIndex = 32
lootHolder.Parent = content
local lootGrid = Window.Grid(lootHolder, UDim2.fromOffset(60, 60), 6)
local noLoot = Style.Label(lootHolder, T.NoLoot, 13, C.Muted, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 20), ZIndex = 33 })

-- buttons
local returnLine = Style.Label(content, "", 12, C.Muted, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, -50), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local again = Style.Button(content, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 44), Text = Style.Upper(T.Again), TextSize = 16, Color = C.Gold, Icon = "reset", ZIndex = 34 })
local hub = Style.Button(content, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 44), Text = Style.Upper(T.Hub), TextSize = 16, Color = C.Card, Icon = "back", ZIndex = 34 })

local returnAt = nil

again.Activated:Connect(function()
	window.Close()
	task.spawn(function()
		local ok, message = gateRemote:InvokeServer("Again")
		if not ok and message then
			Popups.Toast(message, "bad")
		end
	end)
end)
hub.Activated:Connect(function()
	window.Close()
	if player:GetAttribute("Zone") == "Dungeon" then
		task.spawn(travel.InvokeServer, travel, "Hub")
	end
end)

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function show(summary)
	local won = summary.Result == "Won"
	local grade = summary.Grade
	gradeLetter.Text = if won and grade then grade else "—"
	gradeLetter.TextColor3 = if won and grade then gradeColor[grade] or C.Gold else C.Red
	gradeScale.Scale = 1.6
	Style.Tween(gradeScale, 0.35, { Scale = 1 })
	resultLine.Text = Style.Upper(if won then T.Won elseif summary.Result == "Failed" then T.Failed else T.Left)
	resultLine.TextColor3 = if won then C.Gold else C.Muted
	bonusLine.Text = if won and (summary.Bonus or 0) > 0 then T.Bonus:format(summary.Bonus) else ""
	locationLine.Text = Style.Upper(summary.Location or "") .. "  •  " .. (summary.Rank or "") .. (if summary.Red then "  •  " .. Config.RedGate.Texts.Name else "")
	locationLine.TextColor3 = if summary.Red then Config.RedGate.Color else C.Gold
	rows.Time.Text = clock(summary.Time or 0)
	rows.Damage.Text = Format.Number(summary.Damage or 0)
	rows.Kills.Text = tostring(summary.Kills or 0)
	rows.Deaths.Text = tostring(summary.Deaths or 0)
	for _, child in ipairs(lootGrid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local loot = if type(summary.Loot) == "table" then summary.Loot else {}
	table.sort(loot, function(a, b)
		return (Config.Rarity[a.R] or Config.Rarity.Common).Index > (Config.Rarity[b.R] or Config.Rarity.Common).Index
	end)
	for order, entry in ipairs(loot) do
		local view = Items.Resolve({ B = entry.B, K = entry.K, R = entry.R, L = entry.L or 1, Q = 1, E = 0 })
		if view then
			local cell = Instance.new("Frame")
			cell.BackgroundTransparency = 1
			cell.LayoutOrder = order
			cell.ZIndex = 33
			cell.Parent = lootGrid
			ItemIcon.Create(cell, view.Kind, view, UDim2.fromScale(1, 1), UDim2.new())
		end
	end
	noLoot.Visible = #loot == 0
	returnAt = if won then os.clock() + (summary.Return or GR.ReturnSeconds) - 6 else nil
	returnLine.Text = ""
	again.Visible = summary.LocationId ~= nil and not summary.Red
	Style.PlaySound(if won then Config.Sounds.Forged else Config.Sounds.Barrier, 1, 0.7)
	window.Open()
end

task.spawn(function()
	while true do
		task.wait(0.5)
		if returnAt and window.IsOpen() then
			returnLine.Text = T.Return:format(math.max(0, math.ceil(returnAt - os.clock())))
		end
	end
end)

ReplicatedStorage:WaitForChild("GateState").OnClientEvent:Connect(function(kind, summary)
	if kind == "Result" and type(summary) == "table" then
		task.delay(0.4, show, summary)
	end
end)

RunSummary.Window = window
return RunSummary
