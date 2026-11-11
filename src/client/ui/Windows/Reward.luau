--[[
	Reward.luau
	"Награды" window with three tabs, all backed by the Progression
	remote: Ежедневная (7-day streak), Задания (3 daily quests) and
	Колесо (free spin every N hours, spins the hub wheel visually).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local progression = ReplicatedStorage:WaitForChild("Progression")

local Reward = {}

local window = Window.new("Награды", Style.Colors.Gold, Vector2.new(540, 440))
local content = window.Content

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 40)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 33
tabBar.Parent = content
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

local pages = {}
local function page(name, title, order, color)
	local tab, setColor = Style.Button(tabBar, { Size = UDim2.fromOffset(150, 38), Color = color, Text = title, TextSize = 18, ZIndex = 34, LayoutOrder = order, Shadow = false })
	local holder = Instance.new("Frame")
	holder.Position = UDim2.fromOffset(0, 48)
	holder.Size = UDim2.new(1, 0, 1, -48)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.ZIndex = 32
	holder.Parent = content
	pages[name] = { tab = tab, setColor = setColor, holder = holder, color = color }
	tab.Activated:Connect(function()
		Reward.ShowTab(name)
	end)
	return holder
end

function Reward.ShowTab(name)
	for key, p in pairs(pages) do
		p.holder.Visible = key == name
		p.setColor(if key == name then p.color else Color3.fromRGB(150, 140, 170))
	end
end

local dailyPage = page("Daily", "Ежедневная", 1, Style.Colors.Gold)
local questPage = page("Quests", "Задания", 2, Style.Colors.Green)
local wheelPage = page("Wheel", "Колесо", 3, Style.Colors.Magenta)

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d:%02d"):format(seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

local busy = false
local function call(action, arg, onDone)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, payload, extra = progression:InvokeServer(action, arg)
		busy = false
		onDone(ok, payload, extra)
	end)
end

---------------------------------------------------------------------
-- Daily
---------------------------------------------------------------------

local dailyCells = {}
local dailyGrid = Instance.new("Frame")
dailyGrid.Size = UDim2.new(1, 0, 0, 170)
dailyGrid.BackgroundTransparency = 1
dailyGrid.ZIndex = 33
dailyGrid.Parent = dailyPage
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(118, 78)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.Parent = dailyGrid
for day = 1, 7 do
	local cell = Instance.new("Frame")
	cell.LayoutOrder = day
	cell.BackgroundColor3 = Style.Lighter(Style.Colors.Gold, 0.8)
	cell.ZIndex = 33
	cell.Parent = dailyGrid
	Style.Corner(cell, UDim.new(0, 12))
	local stroke = Style.Stroke(cell, 3, Style.Colors.Gold)
	Style.Label(cell, "День " .. day, 16, Style.Colors.Outline, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 20), ZIndex = 34 }):FindFirstChildOfClass("UIStroke").Transparency = 1
	local amount = Style.Label(cell, "", 20, Style.Colors.Purple, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 24), ZIndex = 34 })
	local note = Style.Label(cell, if day == 7 then "+ x2 буст" else "", 13, Style.Colors.Outline, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 16), ZIndex = 34 })
	note:FindFirstChildOfClass("UIStroke").Transparency = 1
	dailyCells[day] = { cell = cell, stroke = stroke, amount = amount }
end
local dailyInfo = Style.Label(dailyPage, "", 18, Style.Colors.Outline, { Position = UDim2.fromOffset(0, 180), Size = UDim2.new(1, 0, 0, 24), ZIndex = 34 })
dailyInfo:FindFirstChildOfClass("UIStroke").Transparency = 1
local dailyButton, setDailyColor = Style.Button(dailyPage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 214), Size = UDim2.fromOffset(280, 54), Color = Style.Colors.Green, Text = "Забрать", TextSize = 22, ZIndex = 34, Shadow = false })

---------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------

local questRows = {}
local questList = Instance.new("Frame")
questList.Size = UDim2.fromScale(1, 1)
questList.BackgroundTransparency = 1
questList.ZIndex = 33
questList.Parent = questPage
local questLayout = Instance.new("UIListLayout")
questLayout.Padding = UDim.new(0, 10)
questLayout.SortOrder = Enum.SortOrder.LayoutOrder
questLayout.Parent = questList
for i = 1, Config.Progression.Quests.PerDay do
	local card = Instance.new("Frame")
	card.LayoutOrder = i
	card.Size = UDim2.new(1, -8, 0, 84)
	card.BackgroundColor3 = Style.Lighter(Style.Colors.Green, 0.82)
	card.ZIndex = 33
	card.Parent = questList
	Style.Corner(card, UDim.new(0, 14))
	Style.Stroke(card, 3, Style.Colors.Green)
	local text = Style.Label(card, "", 18, Style.Colors.Outline, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -180, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	text:FindFirstChildOfClass("UIStroke").Transparency = 1
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(14, 42)
	track.Size = UDim2.new(1, -190, 0, 22)
	track.BackgroundColor3 = Style.Colors.PanelDark
	track.ZIndex = 34
	track.Parent = card
	Style.Corner(track, UDim.new(0.5, 0))
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Style.Colors.Green
	fill.ZIndex = 35
	fill.Parent = track
	Style.Corner(fill, UDim.new(0.5, 0))
	local progressText = Style.Label(track, "", 14, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 36 })
	local button, setColor = Style.Button(card, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 50), Color = Style.Colors.Gold, TextSize = 16, ZIndex = 35, Shadow = false })
	button.Activated:Connect(function()
		call("ClaimQuest", i, function(ok, message)
			Popups.Toast(message or "", if ok then "gold" else "bad")
			Reward.Refresh()
		end)
	end)
	questRows[i] = { card = card, text = text, fill = fill, progressText = progressText, button = button, setColor = setColor }
end

---------------------------------------------------------------------
-- Wheel
---------------------------------------------------------------------

local prizeList = Instance.new("Frame")
prizeList.Size = UDim2.new(1, 0, 0, 200)
prizeList.BackgroundTransparency = 1
prizeList.ZIndex = 33
prizeList.Parent = wheelPage
local prizeLayout = Instance.new("UIGridLayout")
prizeLayout.CellSize = UDim2.fromOffset(240, 36)
prizeLayout.CellPadding = UDim2.fromOffset(8, 6)
prizeLayout.SortOrder = Enum.SortOrder.LayoutOrder
prizeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
prizeLayout.Parent = prizeList
local prizeColors = { Style.Colors.Magenta, Style.Colors.Gold, Style.Colors.Cyan, Style.Colors.Green, Style.Colors.Purple, Style.Colors.Orange, Style.Colors.Red, Style.Colors.Blue }
local prizeCells = {}
for i, prize in ipairs(Config.Progression.Wheel.Prizes) do
	local cell = Style.Plate(prizeList, { Size = UDim2.fromOffset(240, 36), Color = prizeColors[(i - 1) % #prizeColors + 1], Transparency = 0.15, ZIndex = 33 })
	cell.LayoutOrder = i
	Style.Label(cell, prize.Label, 16, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 34 })
	prizeCells[i] = cell
end
local wheelInfo = Style.Label(wheelPage, "", 18, Style.Colors.Outline, { Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 24), ZIndex = 34 })
wheelInfo:FindFirstChildOfClass("UIStroke").Transparency = 1
local spinButton, setSpinColor = Style.Button(wheelPage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 244), Size = UDim2.fromOffset(280, 54), Color = Style.Colors.Magenta, Text = "Крутить!", TextSize = 22, ZIndex = 34, Shadow = false })

-- Spins the hub wheel disc locally (anchored part, local CFrame change).
local function spinHubWheel(prizeIndex)
	local hub = Workspace:FindFirstChild("Hub")
	local wheel = hub and hub:FindFirstChild("Wheel")
	local disc = wheel and wheel:FindFirstChild("Disc")
	if not disc then
		return
	end
	local n = #Config.Progression.Wheel.Prizes
	local target = (prizeIndex - 1) / n * 360 + 360 * 4
	TweenService:Create(disc, TweenInfo.new(3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { CFrame = disc.CFrame * CFrame.Angles(math.rad(target), 0, 0) }):Play()
	local cell = prizeCells[prizeIndex]
	if cell then
		task.delay(3, function()
			local s = Instance.new("UIScale")
			s.Parent = cell
			Style.Tween(s, 0.25, { Scale = 1.15 }, Enum.EasingStyle.Back)
			task.delay(1.2, function()
				Style.Tween(s, 0.2, { Scale = 1 })
			end)
		end)
	end
end

---------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------

local lastStatus = nil
local function render(s)
	lastStatus = s
	-- Daily
	for day, cell in ipairs(dailyCells) do
		cell.amount.Text = Format.Number(s.Daily.Aura[day] or 0) .. " ✨"
		local claimed = day <= (s.Daily.Streak % 7) and not (s.Daily.Streak % 7 == 0 and day == 7)
		local isNext = day == s.Daily.NextDay
		cell.stroke.Color = if isNext then Style.Colors.Green elseif claimed then Style.Colors.Purple else Style.Colors.Gold
		cell.stroke.Thickness = if isNext then 4 else 3
		cell.cell.BackgroundColor3 = if claimed then Style.Lighter(Style.Colors.Purple, 0.75) else Style.Lighter(Style.Colors.Gold, 0.8)
	end
	if s.Daily.CanClaim then
		dailyInfo.Text = ("Серия: %d дн.  •  сегодня день %d"):format(s.Daily.Streak, s.Daily.NextDay)
		dailyButton.Text = "Забрать награду"
		setDailyColor(Style.Colors.Green)
	else
		dailyInfo.Text = ("Серия: %d дн.  •  следующая через %s"):format(s.Daily.Streak, clock(s.Daily.Wait))
		dailyButton.Text = "Уже получено"
		setDailyColor(Color3.fromRGB(120, 120, 140))
	end
	-- Quests
	for i, row in ipairs(questRows) do
		local q = s.Quests[i]
		if q then
			row.card.Visible = true
			row.text.Text = q.Text .. ("  (+%s ✨)"):format(Format.Number(q.Aura))
			row.fill.Size = UDim2.fromScale(math.clamp(q.Progress / q.Target, 0, 1), 1)
			row.progressText.Text = ("%d / %d"):format(q.Progress, q.Target)
			if q.Claimed then
				row.button.Text = "Получено ✓"
				row.setColor(Color3.fromRGB(120, 120, 140))
			elseif q.Progress >= q.Target then
				row.button.Text = "Забрать"
				row.setColor(Style.Colors.Gold)
			else
				row.button.Text = "В процессе"
				row.setColor(Color3.fromRGB(150, 140, 170))
			end
		else
			row.card.Visible = false
		end
	end
	-- Wheel
	if s.Wheel.CanSpin then
		wheelInfo.Text = Config.HubLayout.Texts.WheelFree
		spinButton.Text = "Крутить!"
		setSpinColor(Style.Colors.Magenta)
	else
		wheelInfo.Text = "Следующее вращение через " .. clock(s.Wheel.Wait)
		spinButton.Text = "Ждём…"
		setSpinColor(Color3.fromRGB(120, 120, 140))
	end
end

function Reward.Refresh()
	call("Status", nil, function(ok, payload)
		if ok and type(payload) == "table" then
			render(payload)
		end
	end)
end

dailyButton.Activated:Connect(function()
	call("ClaimDaily", nil, function(ok, message)
		Popups.Toast(message or "", if ok then "gold" else "bad")
		if ok then
			Style.PlaySound(Config.Sounds.Buy, 1.5, 0.6)
		end
		Reward.Refresh()
	end)
end)

spinButton.Activated:Connect(function()
	call("Spin", nil, function(ok, message, prizeIndex)
		if ok then
			spinHubWheel(prizeIndex)
			task.delay(3, function()
				Popups.Toast("🎡 " .. (message or ""), "gold")
				Style.PlaySound(Config.Sounds.Buy, 1.3, 0.6)
			end)
		else
			Popups.Toast(message or "", "bad")
		end
		Reward.Refresh()
	end)
end)

-- Countdown text ticks while the window is open.
task.spawn(function()
	while true do
		task.wait(1)
		if window.IsOpen() and lastStatus then
			if not lastStatus.Daily.CanClaim then
				lastStatus.Daily.Wait = math.max(0, lastStatus.Daily.Wait - 1)
			end
			if not lastStatus.Wheel.CanSpin then
				lastStatus.Wheel.Wait = math.max(0, lastStatus.Wheel.Wait - 1)
			end
			if (not lastStatus.Daily.CanClaim and lastStatus.Daily.Wait == 0) or (not lastStatus.Wheel.CanSpin and lastStatus.Wheel.Wait == 0) then
				Reward.Refresh()
			else
				render(lastStatus)
			end
		end
	end
end)

window.OnOpen = Reward.Refresh
Reward.ShowTab("Daily")

Reward.Window = window
function Reward.Open()
	Reward.ShowTab("Daily")
	window.Open()
end
function Reward.OpenQuests()
	Reward.ShowTab("Quests")
	window.Open()
end
function Reward.OpenWheel()
	Reward.ShowTab("Wheel")
	window.Open()
end

player:GetAttributeChangedSignal("RewardReady"):Connect(function()
	if window.IsOpen() then
		Reward.Refresh()
	end
end)

return Reward
