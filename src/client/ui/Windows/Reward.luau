--[[
	Reward.luau
	"Награды" window with three tabs, all backed by the Progression
	remote: Ежедневная (7-day login calendar, Кристаллы on day 7),
	Задания (the story step, 3 daily and 3 weekly quests: reward, progress
	bar, "Забрать") and Колесо (free spin every N hours).
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

local window = Window.new("Награды", Style.Colors.Gold, Vector2.new(620, 520))
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
local refreshAchievements -- set below
local function page(name, title, order, color)
	local tab, setColor = Style.Button(tabBar, { Size = UDim2.fromOffset(140, 38), Color = color, Text = title, TextSize = 18, ZIndex = 34, LayoutOrder = order, Shadow = false })
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
	if name == "Achievements" and refreshAchievements then
		refreshAchievements()
	end
	for key, p in pairs(pages) do
		p.holder.Visible = key == name
		p.setColor(if key == name then p.color else Color3.fromRGB(150, 140, 170))
	end
end

local dailyPage = page("Daily", "Ежедневная", 1, Style.Colors.Gold)
local questPage = page("Quests", "Задания", 2, Style.Colors.Green)
local wheelPage = page("Wheel", "Колесо", 3, Style.Colors.Magenta)
local achPage = page("Achievements", "Достижения", 4, Style.Colors.Gold)

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d:%02d"):format(seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

local busy = false
local function call(action, arg, onDone, arg2)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, payload, extra = progression:InvokeServer(action, arg, arg2)
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
	cell.BackgroundColor3 = Style.Darker(Style.Colors.Gold, 0.72)
	cell.ZIndex = 33
	cell.Parent = dailyGrid
	Style.Corner(cell, UDim.new(0, 12))
	local stroke = Style.Stroke(cell, 3, Style.Colors.Gold)
	Style.Label(cell, "День " .. day, 16, Style.Colors.Text, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 20), ZIndex = 34 })
	local amount = Style.Label(cell, "", 20, Style.Colors.Gold, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 24), ZIndex = 34 })
	local note = Style.Label(cell, if day == 7 then "+ x2 буст" else "", 13, Style.Colors.Text, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 16), ZIndex = 34 })
	dailyCells[day] = { cell = cell, stroke = stroke, amount = amount, note = note }
end
local dailyInfo = Style.Label(dailyPage, "", 18, Style.Colors.Text, { Position = UDim2.fromOffset(0, 180), Size = UDim2.new(1, 0, 0, 24), ZIndex = 34 })
local dailyButton, setDailyColor = Style.Button(dailyPage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 214), Size = UDim2.fromOffset(280, 54), Color = Style.Colors.Green, Text = "Забрать", TextSize = 22, ZIndex = 34, Shadow = false })

---------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------

local HttpService = game:GetService("HttpService")
local questRemote = ReplicatedStorage:WaitForChild("Quest")

local questList = Instance.new("ScrollingFrame")
questList.Size = UDim2.fromScale(1, 1)
questList.BackgroundTransparency = 1
questList.BorderSizePixel = 0
questList.ScrollBarThickness = 5
questList.ScrollBarImageColor3 = Style.Colors.Gold
questList.CanvasSize = UDim2.new()
questList.AutomaticCanvasSize = Enum.AutomaticSize.Y
questList.ZIndex = 33
questList.Parent = questPage
local questLayout = Instance.new("UIListLayout")
questLayout.Padding = UDim.new(0, 8)
questLayout.SortOrder = Enum.SortOrder.LayoutOrder
questLayout.Parent = questList

local function section(order: number, text: string)
	return Style.Label(questList, text, 14, Style.Colors.Gold, { Font = Style.FontTitle, LayoutOrder = order, Size = UDim2.new(1, -10, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
end

-- One quest card: title, reward line, progress bar, button.
local function questCard(order: number, onClaim)
	local card = Instance.new("Frame")
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -10, 0, 78)
	card.BackgroundTransparency = 1
	card.ZIndex = 33
	card.Parent = questList
	Style.Chamfer(card, { Fill = Style.Colors.PanelDark, Transparency = 0.05, Border = Style.Colors.Line, Cut = 8, Thickness = 1.5 })
	local title = Style.Label(card, "", 16, Style.Colors.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 34 })
	local reward = Style.Label(card, "", 12, Style.Colors.Gold, { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -170, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(12, 50)
	track.Size = UDim2.new(1, -182, 0, 16)
	track.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	track.BorderSizePixel = 0
	track.ZIndex = 34
	track.Parent = card
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Style.Colors.Gold
	fill.BorderSizePixel = 0
	fill.ZIndex = 35
	fill.Parent = track
	local progress = Style.Label(track, "", 12, Style.Colors.Text, { Size = UDim2.fromScale(1, 1), ZIndex = 36 })
	local button, setColor = Style.Button(card, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(146, 44), Color = Style.Colors.Gold, TextSize = 15, ZIndex = 35, Shadow = false })
	button.Activated:Connect(onClaim)
	local row = { card = card, title = title, reward = reward, fill = fill, progress = progress, button = button, setColor = setColor }
	function row.Set(q, rewardText)
		card.Visible = q ~= nil
		if not q then
			return
		end
		title.Text = q.Text
		reward.Text = rewardText
		local share = math.clamp(q.Progress / math.max(1, q.Target), 0, 1)
		fill.Size = UDim2.fromScale(share, 1)
		fill.BackgroundColor3 = if share >= 1 then Style.Colors.Green else Style.Colors.Gold
		progress.Text = ("%s / %s"):format(Format.Number(q.Progress), Format.Number(q.Target))
		if q.Claimed then
			button.Text = "Получено"
			setColor(Color3.fromRGB(70, 70, 80))
		elseif q.Progress >= q.Target then
			button.Text = "Забрать"
			setColor(Style.Colors.Green)
		else
			button.Text = "В процессе"
			setColor(Style.Colors.CardDark)
		end
	end
	return row
end

local function rewardLine(q): string
	local parts = { ("+%s кр."):format(Format.Number(q.Credits or 0)) }
	if (q.Xp or 0) > 0 then
		table.insert(parts, ("+%s XP"):format(Format.Number(q.Xp)))
	end
	if (q.Crystals or 0) > 0 then
		table.insert(parts, ("+%d Кристаллов"):format(q.Crystals))
	end
	return "Награда: " .. table.concat(parts, "  ·  ")
end

local claimQuest -- defined below (needs Reward.Refresh)
section(1, "СЮЖЕТ")
local storyRow = questCard(2, function()
	task.spawn(function()
		local ok, message = questRemote:InvokeServer("Claim")
		Popups.Toast(message or "", if ok then "gold" else "bad")
		if ok then
			Style.PlaySound("Forged", 1.2, 0.5)
		end
		Reward.Refresh()
	end)
end)
local dailyHeader = section(10, "ЕЖЕДНЕВНЫЕ")
local questRows = {}
for i = 1, Config.Progression.Quests.PerDay do
	questRows[i] = questCard(10 + i, function()
		claimQuest(i, "Daily")
	end)
end
local weeklyHeader = section(20, "НЕДЕЛЬНЫЕ")
local weeklyRows = {}
for i = 1, Config.Progression.Weekly.PerWeek do
	weeklyRows[i] = questCard(20 + i, function()
		claimQuest(i, "Weekly")
	end)
end

local function renderStory()
	local ok, q = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Tracker") or "")
	if not ok or type(q) ~= "table" or not q.Title then
		storyRow.Set(nil)
		return
	end
	local target = tonumber(q.Target) or 1
	local progress = if q.Ready then target else (tonumber(q.Progress) or 0)
	storyRow.Set({ Text = q.Title .. " — " .. (q.Text or ""), Progress = progress, Target = target, Claimed = false }, q.Reward or "Награда у Наставника: опыт и кредиты")
	if q.Ready or progress >= target then
		storyRow.button.Text = "Забрать"
	end
end
player:GetAttributeChangedSignal("Tracker"):Connect(renderStory)

---------------------------------------------------------------------
-- Achievements (EngageService): reward in Кристаллы, some give a title
---------------------------------------------------------------------

local engage = ReplicatedStorage:WaitForChild("Engage")
local achList = Instance.new("ScrollingFrame")
achList.Size = UDim2.fromScale(1, 1)
achList.BackgroundTransparency = 1
achList.BorderSizePixel = 0
achList.ScrollBarThickness = 5
achList.ScrollBarImageColor3 = Style.Colors.Gold
achList.CanvasSize = UDim2.new()
achList.AutomaticCanvasSize = Enum.AutomaticSize.Y
achList.ZIndex = 33
achList.Parent = achPage
local achLayout = Instance.new("UIListLayout")
achLayout.Padding = UDim.new(0, 6)
achLayout.SortOrder = Enum.SortOrder.LayoutOrder
achLayout.Parent = achList

local function renderAchievements(list)
	for _, child in ipairs(achList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, a in ipairs(list) do
		local row = Instance.new("Frame")
		row.LayoutOrder = if a.Done then 100 + i else i
		row.Size = UDim2.new(1, -10, 0, 60)
		row.BackgroundTransparency = 1
		row.ZIndex = 33
		row.Parent = achList
		Style.Chamfer(row, { Fill = Style.Colors.PanelDark, Transparency = 0.05, Border = if a.Done then Style.Colors.GoldDim else Style.Colors.Line, Cut = 8, Thickness = 1.5 })
		local icon = Style.Icons.Make(row, if a.Done then "check" else "trophy", 24, if a.Done then Style.Colors.Gold else Style.Colors.Muted, 34)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		Style.Label(row, a.Name, 15, if a.Done then Style.Colors.Gold else Style.Colors.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(46, 6), Size = UDim2.new(1, -220, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
		Style.Label(row, a.Text .. ("  ·  %d / %d"):format(a.Progress, a.Target), 12, Style.Colors.Muted, { Position = UDim2.fromOffset(46, 30), Size = UDim2.new(1, -220, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
		local reward = ("+%d крист."):format(a.Crystals or 0) .. (if a.Title then "  ·  титул" else "")
		Style.Label(row, reward, 12, Config.Crystals.Color, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(160, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
		if a.Done and a.Title then
			local wear = Style.Button(row, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -6), Size = UDim2.fromOffset(130, 24), Color = if player:GetAttribute("Title") == a.Title then Style.Colors.Gold else Style.Colors.Card, Text = if player:GetAttribute("Title") == a.Title then "Надет" else "Надеть титул", TextSize = 12, ZIndex = 35 })
			wear.Activated:Connect(function()
				task.spawn(function()
					local same = player:GetAttribute("Title") == a.Title
					local ok, message = engage:InvokeServer("Title", if same then "" else a.Id)
					Popups.Toast(message or "", if ok then "gold" else "bad")
					local ok2, fresh = engage:InvokeServer("Achievements")
					if ok2 then
						renderAchievements(fresh)
					end
				end)
			end)
		end
	end
end

refreshAchievements = function()
	task.spawn(function()
		local ok, list = engage:InvokeServer("Achievements")
		if ok and type(list) == "table" then
			renderAchievements(list)
		end
	end)
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
local wheelInfo = Style.Label(wheelPage, "", 18, Style.Colors.Text, { Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 24), ZIndex = 34 })
local spinButton, setSpinColor = Style.Button(wheelPage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 244), Size = UDim2.fromOffset(280, 54), Color = Style.Colors.Magenta, Text = "Крутить!", TextSize = 22, ZIndex = 34, Shadow = false })

-- Spins the hub wheel locally: the "Spin" model (disc + pegs) is
-- pivoted around the disc axis.
local function spinHubWheel(prizeIndex)
	local hub = Workspace:FindFirstChild("Hub")
	local wheel = hub and hub:FindFirstChild("Wheel")
	local spin = wheel and wheel:FindFirstChild("Spin")
	if spin and spin.PrimaryPart then
		local n = #Config.Progression.Wheel.Prizes
		local target = (prizeIndex - 1) / n * 360 + 360 * 4
		local start = spin:GetPivot()
		local value = Instance.new("NumberValue")
		value.Changed:Connect(function(v)
			if spin.Parent then
				spin:PivotTo(start * CFrame.Angles(math.rad(v), 0, 0))
			end
		end)
		local tween = TweenService:Create(value, TweenInfo.new(3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = target })
		tween:Play()
		tween.Completed:Once(function()
			value:Destroy()
		end)
	end
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
		local crystals = (s.DailyCrystals or {})[day] or 0
		cell.amount.Text = Format.Number(s.Daily.Credits[day] or 0) .. " кр."
		cell.note.Text = (if crystals > 0 then "+" .. crystals .. " крист." else "") .. (if day == 7 then " · x2" else "")
		cell.note.TextColor3 = if crystals > 0 then Config.Crystals.Color else Style.Colors.Text
		local claimed = day <= (s.Daily.Streak % 7) and not (s.Daily.Streak % 7 == 0 and day == 7)
		local isNext = day == s.Daily.NextDay
		cell.stroke.Color = if isNext then Style.Colors.Green elseif claimed then Style.Colors.Purple else Style.Colors.Gold
		cell.stroke.Thickness = if isNext then 4 else 3
		cell.cell.BackgroundColor3 = if claimed then Style.Darker(Style.Colors.Purple, 0.72) else Style.Darker(Style.Colors.Gold, 0.72)
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
	renderStory()
	for i, row in ipairs(questRows) do
		local q = s.Quests[i]
		row.Set(q, if q then rewardLine(q) else "")
	end
	for i, row in ipairs(weeklyRows) do
		local q = s.Weekly and s.Weekly[i]
		row.Set(q, if q then rewardLine(q) else "")
	end
	dailyHeader.Text = ("ЕЖЕДНЕВНЫЕ  ·  новые через %s"):format(clock(s.DayLeft or 0))
	local week = s.WeekLeft or 0
	weeklyHeader.Text = ("НЕДЕЛЬНЫЕ  ·  новые через %d д %d ч"):format(week // 86400, (week % 86400) // 3600)
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

claimQuest = function(index: number, setName: string)
	call("ClaimQuest", index, function(ok, message)
		Popups.Toast(message or "", if ok then "gold" else "bad")
		if ok then
			Style.PlaySound("Forged", 1.2, 0.5)
			Popups.Flash(Style.Colors.Gold)
		end
		Reward.Refresh()
	end, setName)
end

-- Status is asked right after a claim; the server's rate limit may turn
-- it down, so it is asked again a moment later until it answers.
function Reward.Refresh(tries: number?)
	task.delay(0.35, function()
		if busy then
			if (tries or 0) < 5 then
				Reward.Refresh((tries or 0) + 1)
			end
			return
		end
		call("Status", nil, function(ok, payload)
			if ok and type(payload) == "table" then
				render(payload)
			elseif (tries or 0) < 5 then
				Reward.Refresh((tries or 0) + 1)
			end
		end)
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
				Popups.Toast(message or "", "gold")
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

window.OnOpen = function()
	Reward.Refresh()
end
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
