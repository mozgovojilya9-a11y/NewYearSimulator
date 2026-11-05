-- Клиент: интерфейс собирается кодом, поэтому в Studio ничего рисовать не нужно.
-- Клиент только показывает данные и отправляет запросы, все проверки на сервере.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local state = nil
local selectedZone = 1
local autoTrain = false
local heroSig = nil

local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(60, 180, 75)
local BLUE = Color3.fromRGB(50, 110, 220)
local GRAY = Color3.fromRGB(90, 90, 100)
local RED = Color3.fromRGB(210, 60, 60)
local PURPLE = Color3.fromRGB(150, 70, 200)
local ORANGE = Color3.fromRGB(235, 150, 30)
local CYAN = Color3.fromRGB(40, 170, 190)

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function fmt(n)
	local i = 1
	while n >= 1000 and i < #SUFFIX do
		n /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(n))
	end
	return ("%.2f%s"):format(n, SUFFIX[i])
end

local function make(class, props, parent)
	local obj = Instance.new(class)
	for k, v in props do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function button(text, color, width, parent, onClick)
	local b = make("TextButton", {
		Size = UDim2.fromScale(width, 1),
		BackgroundColor3 = color,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = WHITE,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0.2, 0) }, b)
	b.Activated:Connect(onClick)
	return b
end

local gui = make("ScreenGui", { Name = "SimUI", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))

-- Статистика
local statsLabel = make("TextLabel", {
	Size = UDim2.fromScale(0.28, 0.2),
	Position = UDim2.fromScale(0.01, 0.55),
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = WHITE,
	TextStrokeTransparency = 0,
	Text = "Загрузка...",
}, gui)

-- Уведомления
local noticeLabel = make("TextLabel", {
	Size = UDim2.fromScale(0.5, 0.07),
	Position = UDim2.fromScale(0.25, 0.12),
	BackgroundTransparency = 1,
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = Color3.fromRGB(255, 240, 150),
	TextStrokeTransparency = 0,
	Visible = false,
}, gui)

-- Ряд зон
local zoneBar = make("Frame", {
	Size = UDim2.fromScale(0.7, 0.08),
	Position = UDim2.fromScale(0.15, 0.78),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0.01, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, zoneBar)

-- Ряд действий
local bar = make("Frame", {
	Size = UDim2.fromScale(0.7, 0.1),
	Position = UDim2.fromScale(0.15, 0.88),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0.01, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, bar)

-- Панель героев
local heroPanel = make("Frame", {
	Size = UDim2.fromScale(0.5, 0.6),
	Position = UDim2.fromScale(0.25, 0.2),
	BackgroundColor3 = Color3.fromRGB(20, 30, 60),
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0.04, 0) }, heroPanel)
make("TextLabel", {
	Size = UDim2.fromScale(1, 0.09),
	BackgroundTransparency = 1,
	Text = "Герои",
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = WHITE,
}, heroPanel)
local heroList = make("ScrollingFrame", {
	Size = UDim2.fromScale(0.96, 0.88),
	Position = UDim2.fromScale(0.02, 0.1),
	BackgroundTransparency = 1,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
}, heroPanel)
make("UIListLayout", { Padding = UDim.new(0, 6) }, heroList)

local zoneButtons = {}
for i, zone in Config.Zones do
	zoneButtons[i] = button(zone.Name, BLUE, 0.24, zoneBar, function()
		selectedZone = i
		if state then
			-- обновим подсветку сразу, не дожидаясь ответа сервера
			for j, b in zoneButtons do
				if state.Power >= Config.Zones[j].Requirement then
					b.BackgroundColor3 = (j == selectedZone) and GREEN or BLUE
				end
			end
		end
	end)
end

local function rebuildHeroes()
	for _, child in heroList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if not state then
		return
	end

	for i, hero in Config.Heroes do
		local row = make("Frame", {
			Size = UDim2.new(1, -10, 0, 60),
			BackgroundColor3 = Color3.fromRGB(40, 55, 100),
			LayoutOrder = i,
		}, heroList)
		make("UICorner", { CornerRadius = UDim.new(0.15, 0) }, row)
		make("TextLabel", {
			Size = UDim2.fromScale(0.62, 1),
			BackgroundTransparency = 1,
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = ("%s (%s)\nx%s мощность · %s"):format(hero.Name, hero.Rarity, hero.PowerMult, hero.Ability.Name),
		}, row)

		local label, action
		if state.Equipped == hero.Id then
			label = "Надето"
		elseif state.Owned[hero.Id] then
			label = "Надеть"
			action = function()
				Remotes.EquipHero:FireServer(hero.Id)
			end
		else
			label = "Купить " .. fmt(hero.Cost)
			action = function()
				Remotes.BuyHero:FireServer(hero.Id)
			end
		end

		local b = make("TextButton", {
			Size = UDim2.fromScale(0.34, 0.8),
			Position = UDim2.fromScale(0.64, 0.1),
			BackgroundColor3 = action and GREEN or GRAY,
			Text = label,
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			TextColor3 = WHITE,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0.2, 0) }, b)
		if action then
			b.Activated:Connect(action)
		end
	end
end

local rebirthButton

local function refresh()
	if not state then
		return
	end

	statsLabel.Text = ("Мощность: %s\nПобеды: %s\nПерерождения: %d\nЭтап: %d (нужно %s)"):format(
		fmt(state.Power), fmt(state.Wins), state.Rebirths, state.Stage, fmt(state.StageRequirement)
	)

	for i, zone in Config.Zones do
		local unlocked = state.Power >= zone.Requirement
		local b = zoneButtons[i]
		b.Text = unlocked and zone.Name or (zone.Name .. " 🔒 " .. fmt(zone.Requirement))
		b.BackgroundColor3 = (i == selectedZone) and GREEN or (unlocked and BLUE or GRAY)
	end

	rebirthButton.Text = "Перерождение " .. fmt(state.RebirthCost)

	-- Список героев перестраиваем только при изменениях, чтобы не ломать нажатия
	if heroPanel.Visible then
		local owned = 0
		for _ in state.Owned do
			owned += 1
		end
		local sig = state.Equipped .. "|" .. tostring(state.Wins) .. "|" .. owned
		if sig ~= heroSig then
			heroSig = sig
			rebuildHeroes()
		end
	end
end

-- Кнопки действий
button("Тренировка", GREEN, 0.15, bar, function()
	Remotes.Train:FireServer(selectedZone)
end)

local autoButton
autoButton = button("Авто: выкл", BLUE, 0.15, bar, function()
	autoTrain = not autoTrain
	autoButton.Text = autoTrain and "Авто: вкл" or "Авто: выкл"
end)

button("В бой", RED, 0.15, bar, function()
	Remotes.Fight:FireServer()
end)

rebirthButton = button("Перерождение", PURPLE, 0.15, bar, function()
	Remotes.Rebirth:FireServer()
end)

button("Герои", ORANGE, 0.15, bar, function()
	heroPanel.Visible = not heroPanel.Visible
	heroSig = nil
	refresh()
end)

button("Способность", CYAN, 0.15, bar, function()
	Remotes.UseAbility:FireServer()
end)

-- Автотренировка
task.spawn(function()
	while true do
		if autoTrain then
			Remotes.Train:FireServer(selectedZone)
		end
		task.wait(Config.TrainCooldown + 0.02)
	end
end)

-- Уведомления
local noticeId = 0
Remotes.Notice.OnClientEvent:Connect(function(text)
	noticeId += 1
	local id = noticeId
	noticeLabel.Text = text
	noticeLabel.Visible = true
	task.delay(2.5, function()
		if id == noticeId then
			noticeLabel.Visible = false
		end
	end)
end)

-- Состояние от сервера
Remotes.State.OnClientEvent:Connect(function(newState)
	if not state then
		selectedZone = newState.Zone
	end
	state = newState
	refresh()
end)

Remotes.RequestState:FireServer()