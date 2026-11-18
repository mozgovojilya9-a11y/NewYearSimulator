--[[
	Supply.luau
	"Терминал снабжения" window (the capsule machine in the atrium, action
	OpenSupply): banners "Оружие" / "Броня" on the left, the banner panel
	(text, pity counters, crystal balance) in the middle, the rates table
	on the right (Config.Gacha.Rates, as they are on the server), buttons
	"Крутка x1" / "Крутка x10". A pull shows capsules that open one by one:
	shake, a flash in the rarity color, the item (or "Дубликат: +N ядер").
	Where paid random items are restricted (PaidPullsOff) a note says only
	earned crystals are spent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local Icons = require(script.Parent.Parent.Icons)
local ItemIcon = require(script.Parent.Parent.ItemIcon)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local C = Style.Colors
local GA = Config.Gacha
local T = GA.Texts
local CRYSTAL = Config.Crystals.Color
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Gacha")

local Supply = {}

local window = Window.new("Терминал снабжения", CRYSTAL, Vector2.new(780, 470), "crystal")
local content = window.Content

local current = GA.Banners[1]
local pity = {}

---------------------------------------------------------------------
-- Left: banners
---------------------------------------------------------------------

local bannerButtons = {}
for i, banner in ipairs(GA.Banners) do
	local b = Instance.new("TextButton")
	b.Name = banner.Id
	b.Position = UDim2.fromOffset(0, (i - 1) * 96)
	b.Size = UDim2.fromOffset(200, 86)
	b.BackgroundTransparency = 1
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 33
	b.Parent = content
	local shape = Style.Chamfer(b, { Fill = C.PanelDark, Transparency = 0.05, Border = C.Line, Cut = 10, Thickness = 2 })
	local icon = Icons.Make(b, banner.Icon, 30, C.Gold, 34)
	icon.Position = UDim2.fromOffset(14, 14)
	Style.Label(b, banner.Name, 20, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(54, 14), Size = UDim2.new(1, -60, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	Style.Label(b, banner.Text, 12, C.Muted, { Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -24, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 34 })
	bannerButtons[banner.Id] = shape
	b.Activated:Connect(function()
		current = banner
		Supply.Refresh()
	end)
end

---------------------------------------------------------------------
-- Middle: the banner panel
---------------------------------------------------------------------

local mid = Style.Panel(content, { Position = UDim2.fromOffset(212, 0), Size = UDim2.fromOffset(330, 330), Fill = C.PanelDark, Border = C.GoldDim, Cut = 12, ZIndex = 33 })
local capsuleArt = Instance.new("Frame")
capsuleArt.AnchorPoint = Vector2.new(0.5, 0)
capsuleArt.Position = UDim2.new(0.5, 0, 0, 18)
capsuleArt.Size = UDim2.fromOffset(120, 120)
capsuleArt.BackgroundColor3 = CRYSTAL
capsuleArt.BackgroundTransparency = 0.2
capsuleArt.ZIndex = 34
capsuleArt.Parent = mid
Style.Corner(capsuleArt, UDim.new(0.5, 0))
local artGrad = Instance.new("UIGradient")
artGrad.Rotation = 90
artGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(60, 40, 90))
artGrad.Parent = capsuleArt
local artIcon = Icons.Make(capsuleArt, "sword", 56, C.Text, 35)
artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
artIcon.Position = UDim2.fromScale(0.5, 0.5)
local bannerTitle = Style.Label(mid, "", 24, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 28), ZIndex = 34 })
local pityEpic = Style.Label(mid, "", 15, Config.Rarity.Epic.Color, { Position = UDim2.fromOffset(0, 188), Size = UDim2.new(1, 0, 0, 20), ZIndex = 34 })
local pityLeg = Style.Label(mid, "", 15, Config.Rarity.Legendary.Color, { Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 20), ZIndex = 34 })
local balance = Style.Label(mid, "", 18, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 244), Size = UDim2.new(1, 0, 0, 22), ZIndex = 34 })
local note = Style.Label(mid, T.Restricted, 11, C.Muted, { Position = UDim2.fromOffset(12, 272), Size = UDim2.new(1, -24, 0, 50), TextWrapped = true, ZIndex = 34 })
note.Visible = false

---------------------------------------------------------------------
-- Right: rates
---------------------------------------------------------------------

local rates = Style.Panel(content, { Position = UDim2.fromOffset(554, 0), Size = UDim2.new(1, -554, 0, 330), Fill = C.PanelDark, Border = C.Line, Cut = 12, ZIndex = 33 })
Style.Label(rates, Style.Upper(T.Rates), 15, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
do
	local list = {}
	for id, w in pairs(GA.Rates) do
		table.insert(list, { id = id, w = w })
	end
	table.sort(list, function(a, b)
		return Config.Rarity[a.id].Index > Config.Rarity[b.id].Index
	end)
	for i, entry in ipairs(list) do
		local r = Config.Rarity[entry.id]
		local y = 40 + (i - 1) * 32
		local dot = Instance.new("Frame")
		dot.Position = UDim2.fromOffset(14, y + 7)
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = r.Color
		dot.BorderSizePixel = 0
		dot.ZIndex = 34
		dot.Parent = rates
		Style.Corner(dot, UDim.new(0.5, 0))
		Style.Label(rates, r.Name, 15, r.Color, { Position = UDim2.fromOffset(32, y), Size = UDim2.new(0.6, -32, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
		Style.Label(rates, ("%s%%"):format(tostring(entry.w)), 16, C.Text, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y), Size = UDim2.fromOffset(70, 24), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
	end
	local y = 40 + #list * 32 + 8
	Style.Label(rates, ("Гарант: Эпический+ каждые %d круток, Легендарный — каждые %d. Дубликат превращается в Нано-ядра."):format(GA.Pity.Epic, GA.Pity.Legendary), 12, C.Muted, { Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 64), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 34 })
end

---------------------------------------------------------------------
-- Bottom: buttons
---------------------------------------------------------------------

local one = Style.Button(content, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 212, 1, 0), Size = UDim2.fromOffset(240, 56), Color = C.Card, Icon = "crystal", Text = ("%s  ·  %d"):format(Style.Upper(T.One), GA.Cost.One), TextSize = 17, ZIndex = 34 })
local ten = Style.Button(content, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(300, 56), Color = C.Gold, Icon = "crystal", Text = ("%s  ·  %d"):format(Style.Upper(T.Ten), GA.Cost.Ten), TextSize = 17, ZIndex = 34 })

---------------------------------------------------------------------
-- Reveal overlay
---------------------------------------------------------------------

local overlay = Instance.new("TextButton")
overlay.Name = "Reveal"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(6, 6, 10)
overlay.BackgroundTransparency = 0.04
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.ZIndex = 50
overlay.Visible = false
overlay.Parent = content
local grid = Instance.new("Frame")
grid.AnchorPoint = Vector2.new(0.5, 0)
grid.Position = UDim2.new(0.5, 0, 0, 10)
grid.Size = UDim2.new(1, -20, 1, -80)
grid.BackgroundTransparency = 1
grid.ZIndex = 51
grid.Parent = overlay
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(136, 170)
gridLayout.CellPadding = UDim2.fromOffset(10, 10)
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid
local doneButton = Style.Button(overlay, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(220, 48), Color = C.Gold, Text = Style.Upper(T.Skip), TextSize = 17, ZIndex = 53 })

local revealing = false
local skip = false

local function capsule(order: number)
	local cell = Instance.new("Frame")
	cell.BackgroundTransparency = 1
	cell.LayoutOrder = order
	cell.ZIndex = 52
	cell.Parent = grid
	local ball = Instance.new("Frame")
	ball.Name = "Capsule"
	ball.AnchorPoint = Vector2.new(0.5, 0.5)
	ball.Position = UDim2.new(0.5, 0, 0, 62)
	ball.Size = UDim2.fromOffset(92, 92)
	ball.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
	ball.ZIndex = 53
	ball.Parent = cell
	Style.Corner(ball, UDim.new(0.5, 0))
	Style.Stroke(ball, 2, C.Line).LineJoinMode = Enum.LineJoinMode.Round
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(80, 80, 90))
	g.Parent = ball
	local seam = Instance.new("Frame")
	seam.AnchorPoint = Vector2.new(0.5, 0.5)
	seam.Position = UDim2.fromScale(0.5, 0.5)
	seam.Size = UDim2.new(1, 0, 0, 3)
	seam.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	seam.BorderSizePixel = 0
	seam.ZIndex = 54
	seam.Parent = ball
	return cell, ball
end

local function open(cell, ball, entry)
	local rarity = Config.Rarity[entry.R] or Config.Rarity.Common
	local high = rarity.Index >= Config.Rarity.Epic.Index
	if not skip then
		-- shake, stronger for rare things
		for i = 1, (if high then 6 else 3) do
			Style.Tween(ball, 0.05, { Rotation = (if i % 2 == 0 then 1 else -1) * (if high then 14 else 8) })
			task.wait(0.06)
		end
		ball.Rotation = 0
		Style.Tween(ball, 0.12, { BackgroundColor3 = rarity.Color, Size = UDim2.fromOffset(110, 110) })
		task.wait(0.12)
	end
	Style.PlaySound(if rarity.Index >= Config.Rarity.Legendary.Index then "RareDrop" elseif high then "Forged" else "Pickup", if high then 1 else 1.3, if skip then 0.15 else 0.45)
	if high and not skip then
		Popups.Flash(rarity.Color)
	end
	ball.Visible = false
	local view = Items.Resolve({ B = entry.B, K = entry.K, R = entry.R, L = entry.L or 1, Q = 1, E = 0 })
	if view then
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 14)
		holder.Size = UDim2.fromOffset(96, 96)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 53
		holder.Parent = cell
		ItemIcon.Create(holder, view.Kind, view, UDim2.fromScale(1, 1), UDim2.new())
		Style.Label(cell, view.Name, 13, rarity.Color, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 114), Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, ZIndex = 53 })
	end
	Style.Label(cell, if entry.Dup then T.Duplicate:format(entry.Dup) else rarity.Name, 12, if entry.Dup then C.Muted else rarity.Color, { Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 18), ZIndex = 53 })
end

local function reveal(results)
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	revealing = true
	skip = false
	doneButton.Text = Style.Upper(T.Skip)
	overlay.Visible = true
	local cells = {}
	for i = 1, #results do
		local cell, ball = capsule(i)
		cells[i] = { cell, ball }
	end
	task.wait(0.25)
	for i, entry in ipairs(results) do
		if not overlay.Visible then
			break
		end
		open(cells[i][1], cells[i][2], entry)
		if not skip then
			task.wait(GA.RevealSeconds * (if #results > 1 then 0.4 else 1))
		end
	end
	revealing = false
	doneButton.Text = Style.Upper(T.Done)
end

doneButton.Activated:Connect(function()
	if revealing then
		skip = true
	else
		overlay.Visible = false
	end
end)

local busy = false
local lastPull = 0
local function doPull(count: number)
	if busy or revealing or os.clock() - lastPull < 1 then
		return -- a double tap never buys twice
	end
	lastPull = os.clock()
	busy = true
	local ok, results, newInfo = remote:InvokeServer("Pull", current.Id, count)
	busy = false
	if not ok then
		Popups.Toast(tostring(results), "bad")
		return
	end
	if type(newInfo) == "table" then
		pity = newInfo.Pity or pity
	end
	Supply.Refresh()
	task.spawn(reveal, results)
end
one.Activated:Connect(function()
	doPull(1)
end)
ten.Activated:Connect(function()
	doPull(10)
end)

---------------------------------------------------------------------

function Supply.Refresh()
	for id, shape in pairs(bannerButtons) do
		shape.SetBorder(if id == current.Id then C.Gold else C.Line)
	end
	Icons.Set(artIcon, current.Icon, C.Text)
	bannerTitle.Text = Style.Upper(current.Name)
	local p = pity[current.Id] or { Epic = GA.Pity.Epic, Legendary = GA.Pity.Legendary }
	pityEpic.Text = T.PityEpic:format(p.Epic)
	pityLeg.Text = T.PityLegendary:format(p.Legendary)
	local total = player:GetAttribute("Crystals") or 0
	local free = player:GetAttribute("CrystalsFree") or total
	local off = player:GetAttribute("PaidPullsOff") == true
	balance.Text = ("Кристаллы: %s"):format(Format.Number(if off then free else total))
	note.Visible = off
end

function Supply.Open()
	window.Open()
	Supply.Refresh()
	task.spawn(function()
		local ok, data = remote:InvokeServer("Info")
		if ok and type(data) == "table" then
			pity = data.Pity or {}
			Supply.Refresh()
		end
	end)
end

player:GetAttributeChangedSignal("Crystals"):Connect(function()
	if window.IsOpen() then
		Supply.Refresh()
	end
end)

Supply.Window = window
return Supply
