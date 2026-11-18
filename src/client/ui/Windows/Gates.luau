--[[
	Gates.luau
	"Врата" (the gold "Играть" button and the big gate in the Gate hall).
	  left   - rank cards E … S: letter in the rank color, lock + condition
	  center - the locations of the selected rank: art (the biome's
	           landmark model in a viewport over the biome colors), name,
	           recommended level / Gear Score (green when you have it),
	           zones, waves, boss, your best grade; the Red Gates card on
	           top while the event is on
	  right  - the selected location and the group: Соло / Группой,
	           Найти группу (search with a timer), the members, Пригласить,
	           Покинуть группу
	The server decides everything (Gate / Party remotes).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Parent.Icons)
local Popups = require(script.Parent.Parent.Popups)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local travel = ReplicatedStorage:WaitForChild("Travel")
local gateRemote = ReplicatedStorage:WaitForChild("Gate")
local partyRemote = ReplicatedStorage:WaitForChild("Party")
local partyEvent = ReplicatedStorage:WaitForChild("PartyEvent")
local C = Style.Colors
local G = Config.Gates
local T = G.Texts
local PT = Config.Party.Texts
local GREEN, RED = Color3.fromRGB(90, 230, 110), Color3.fromRGB(255, 96, 96)

local Gates = {}

local window = Window.new("Врата", C.Gold, Vector2.new(960, 540), "gate")
local content = window.Content

local selectedRank = "E"
local selectedLocation = G.Locations[1].Id
local party = nil -- { Id, Leader, Members }
local search = nil -- { Location, Ends, Count }
local refresh

local biomeOf = {}
for _, biome in ipairs(Config.DungeonLayout.Biomes) do
	biomeOf[biome.Theme] = biome
end

local function decode(attribute: string)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute(attribute) or "{}")
	return if ok and type(value) == "table" then value else {}
end

local busy = false
local function call(remote, ...)
	if busy then
		return
	end
	busy = true
	local args = table.pack(...)
	task.spawn(function()
		local ok, message = remote:InvokeServer(table.unpack(args, 1, args.n))
		busy = false
		if message and message ~= "" then
			Popups.Toast(message, if ok then "good" else "bad")
		end
		if ok and remote == gateRemote then
			Window.CloseAll()
		end
	end)
end

function Gates.Go(destination: string)
	if destination == "Hub" then
		call(travel, "Hub")
	end
end

---------------------------------------------------------------------
-- Left: ranks
---------------------------------------------------------------------

local RANK_W = 176
local rankCards = {}
for i, rank in ipairs(G.Ranks) do
	local info = G.RankInfo[rank]
	local color = G.Colors[rank]
	local card = Instance.new("TextButton")
	card.Name = rank
	card.Position = UDim2.fromOffset(0, (i - 1) * 76)
	card.Size = UDim2.fromOffset(RANK_W, 70)
	card.BackgroundTransparency = 1
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 33
	card.Parent = content
	local _, shape = Style.Panel(card, { Size = UDim2.fromScale(1, 1), Fill = C.PanelDark, Border = C.Line, Cut = 8, ZIndex = 33 })
	Style.Label(card, rank, 34, color, { Font = Style.FontTitle, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(44, 52), ZIndex = 35 })
	Style.Label(card, Style.Upper(info.Name), 14, C.Text, { Position = UDim2.fromOffset(58, 10), Size = UDim2.new(1, -64, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local status = Style.Label(card, "", 11, C.Muted, { Position = UDim2.fromOffset(58, 30), Size = UDim2.new(1, -64, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
	local lock = Icons.Make(card, "lock", 16, C.Muted, 36)
	lock.AnchorPoint = Vector2.new(1, 0)
	lock.Position = UDim2.new(1, -8, 0, 8)
	rankCards[rank] = { shape = shape, status = status, lock = lock }
	card.Activated:Connect(function()
		selectedRank = rank
		for _, l in ipairs(G.Locations) do
			if l.Rank == rank then
				selectedLocation = l.Id
				break
			end
		end
		refresh()
	end)
end

---------------------------------------------------------------------
-- Center: locations
---------------------------------------------------------------------

local CENTER_X = RANK_W + 12
local RIGHT_W = 300
local center = Instance.new("Frame")
center.Position = UDim2.fromOffset(CENTER_X, 0)
center.Size = UDim2.new(1, -(CENTER_X + RIGHT_W + 12), 1, 0)
center.BackgroundTransparency = 1
center.ZIndex = 32
center.Parent = content
local rankTitle = Style.Label(center, "", 18, C.Gold, { Font = Style.FontTitle, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local rankText = Style.Label(center, "", 12, C.Muted, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
local listHolder = Instance.new("Frame")
listHolder.Position = UDim2.fromOffset(0, 46)
listHolder.Size = UDim2.new(1, 0, 1, -46)
listHolder.BackgroundTransparency = 1
listHolder.ZIndex = 32
listHolder.Parent = center
local list = Window.List(listHolder)

-- Location art: the landmark model in a viewport over a biome gradient.
local function art(parent, location, size: UDim2)
	local biome = biomeOf[location.Biome] or Config.DungeonLayout.Biomes[1]
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.BackgroundColor3 = biome.Floor
	frame.BorderSizePixel = 0
	frame.ZIndex = 34
	frame.ClipsDescendants = true
	frame.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(biome.Accent:Lerp(biome.Floor, 0.55), biome.Floor:Lerp(Color3.new(0, 0, 0), 0.5))
	gradient.Parent = frame
	Style.Stroke(frame, 1, biome.Accent:Lerp(C.Line, 0.5))
	local ok, model = pcall(Assets.Prop, biome.Landmark or "", 10)
	-- Studio-AI meshes don't draw inside a ViewportFrame: big icon instead
	if ok and model and model:GetAttribute("Generated") then
		model:Destroy()
		model = nil
	end
	if ok and model then
		local viewport = Instance.new("ViewportFrame")
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundTransparency = 1
		viewport.Ambient = Color3.fromRGB(170, 170, 185)
		viewport.LightColor = Color3.fromRGB(255, 245, 230)
		viewport.LightDirection = Vector3.new(-0.5, -1, -0.6)
		viewport.ZIndex = 35
		viewport.Parent = frame
		local world = Instance.new("WorldModel")
		world.Parent = viewport
		model:PivotTo(CFrame.new())
		model.Parent = world
		local box, extents = model:GetBoundingBox()
		model:PivotTo(CFrame.new(-box.Position) * model:GetPivot())
		local camera = Instance.new("Camera")
		camera.FieldOfView = 34
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		local distance = extents.Magnitude / 2 / math.tan(math.rad(17)) * 0.9
		camera.CFrame = CFrame.Angles(0, math.rad(-30), 0) * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(0, 0, distance)
	else
		-- biome card: a big line icon, the location's rank letter and stripes
		for i = 1, 3 do
			local stripe = Instance.new("Frame")
			stripe.AnchorPoint = Vector2.new(0.5, 0.5)
			stripe.Position = UDim2.new(0.5, (i - 2) * 26, 0.5, 0)
			stripe.Size = UDim2.new(0, 3, 1.6, 0)
			stripe.Rotation = 28
			stripe.BackgroundColor3 = biome.Accent
			stripe.BackgroundTransparency = 0.82
			stripe.BorderSizePixel = 0
			stripe.ZIndex = 35
			stripe.Parent = frame
		end
		local icon = Icons.Make(frame, location.Icon or "gate", 46, biome.Accent, 36)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		local letter = Style.Label(frame, location.Rank, 22, G.Colors[location.Rank] or C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(24, 26), ZIndex = 36 })
		local _ = letter
	end
	return frame
end

local cards = {} -- [locationId] = ui
local function cardFor(location)
	if cards[location.Id] then
		return cards[location.Id]
	end
	local card = Instance.new("TextButton")
	card.Name = location.Id
	card.Size = UDim2.new(1, -8, 0, 108)
	card.BackgroundTransparency = 1
	card.AutoButtonColor = false
	card.Text = ""
	card.LayoutOrder = location.Order + 10
	card.ZIndex = 33
	card.Parent = list
	local _, shape = Style.Panel(card, { Size = UDim2.fromScale(1, 1), Fill = C.Card, Transparency = 0.1, Border = C.Line, Cut = 8, ZIndex = 33 })
	art(card, location, UDim2.fromOffset(150, 92)).Position = UDim2.fromOffset(8, 8)
	Style.Label(card, Style.Upper(location.Name), 16, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(170, 8), Size = UDim2.new(1, -230, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	local rec = Style.Label(card, "", 12, C.Text, { Position = UDim2.fromOffset(170, 32), Size = UDim2.new(1, -180, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, ZIndex = 35 })
	local info = Style.Label(card, "", 11, C.Muted, { Position = UDim2.fromOffset(170, 52), Size = UDim2.new(1, -180, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
	local grade = Style.Label(card, "", 28, C.Gold, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(40, 34), ZIndex = 35 })
	local soon = Style.Label(card, Style.Upper(T.Soon), 13, C.Muted, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -8), Size = UDim2.fromOffset(120, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
	card.Activated:Connect(function()
		selectedLocation = location.Id
		refresh()
	end)
	cards[location.Id] = { card = card, shape = shape, rec = rec, info = info, grade = grade, soon = soon }
	return cards[location.Id]
end

local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function recommendText(location): string
	local level = player:GetAttribute("Level") or 1
	local gs = player:GetAttribute("Stat_GearScore") or 0
	return ('ур. <font color="%s">%d</font>  •  Gear Score <font color="%s">%d</font>'):format(
		hex(if level >= location.Level then GREEN else RED), location.Level,
		hex(if gs >= location.GearScore then GREEN else RED), location.GearScore)
end

-- Red Gates card (only while the event is on)
local redCard = Instance.new("TextButton")
redCard.Name = "Red"
redCard.Size = UDim2.new(1, -8, 0, 64)
redCard.BackgroundTransparency = 1
redCard.AutoButtonColor = false
redCard.Text = ""
redCard.LayoutOrder = 1
redCard.ZIndex = 33
redCard.Visible = false
redCard.Parent = list
Style.Panel(redCard, { Size = UDim2.fromScale(1, 1), Fill = Color3.fromRGB(40, 10, 12), Transparency = 0.05, Border = Config.RedGate.Color, Cut = 8, ZIndex = 33 })
local redIcon = Icons.Make(redCard, "gate", 34, Config.RedGate.Color, 35)
redIcon.Position = UDim2.fromOffset(12, 15)
Style.Label(redCard, Config.RedGate.Texts.Name, 16, Config.RedGate.Color, { Font = Style.FontTitle, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(1, -180, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local redLine = Style.Label(redCard, "", 12, C.Text, { Position = UDim2.fromOffset(56, 32), Size = UDim2.new(1, -180, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local redButton = Style.Button(redCard, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 38), Text = "ВОЙТИ", TextSize = 14, Color = C.Red, ZIndex = 36 })
redButton.Activated:Connect(function()
	call(gateRemote, "Red")
end)

---------------------------------------------------------------------
-- Right: details + group
---------------------------------------------------------------------

local right = Style.Panel(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, RIGHT_W, 1, 0), Fill = C.PanelDark, Border = C.Line, Cut = 10, ZIndex = 33 })
local dName = Style.Label(right, "", 18, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
local dText = Style.Label(right, "", 12, C.Muted, { Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
local dRec = Style.Label(right, "", 12, C.Text, { Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -24, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, ZIndex = 35 })
local dInfo = Style.Label(right, "", 12, C.Text, { Position = UDim2.fromOffset(12, 88), Size = UDim2.new(1, -24, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 35 })
local dDrop = Style.Label(right, "", 11, C.Muted, { Position = UDim2.fromOffset(12, 122), Size = UDim2.new(1, -24, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, ZIndex = 35 })
local startButton, startColor = Style.Button(right, { Position = UDim2.fromOffset(12, 146), Size = UDim2.new(1, -24, 0, 40), Text = "", TextSize = 16, Color = C.Gold, Icon = "play", ZIndex = 35 })
local searchButton, searchColor = Style.Button(right, { Position = UDim2.fromOffset(12, 192), Size = UDim2.new(1, -24, 0, 34), Text = "", TextSize = 13, Color = C.Card, Icon = "user", ZIndex = 35 })
Style.Rule(right, { Position = UDim2.fromOffset(10, 236), Size = UDim2.new(1, -20, 0, 1), ZIndex = 34 })
Style.Label(right, PT.Group, 12, C.Gold, { Position = UDim2.fromOffset(12, 244), Size = UDim2.new(1, -24, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
local memberLabels = {}
for i = 1, Config.Party.Max do
	memberLabels[i] = Style.Label(right, "", 13, C.Text, { Position = UDim2.fromOffset(12, 264 + (i - 1) * 22), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 35 })
end
local inviteButton = Style.Button(right, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -52), Size = UDim2.new(1, -24, 0, 34), Text = PT.InviteTitle, TextSize = 13, Color = C.Card, Icon = "plus", ZIndex = 35 })
local leaveButton = Style.Button(right, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 34), Text = PT.Leave, TextSize = 13, Color = C.Card, ZIndex = 35 })

-- invite list overlay (players on the server)
local overlay = Style.Panel(content, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, RIGHT_W, 1, 0), Fill = C.PanelDark, Transparency = 0.02, Border = C.GoldDim, Cut = 10, ZIndex = 40, Visible = false })
Style.Label(overlay, Style.Upper(PT.InviteTitle), 14, C.Gold, { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 })
local overlayList = Instance.new("Frame")
overlayList.Position = UDim2.fromOffset(10, 36)
overlayList.Size = UDim2.new(1, -20, 1, -86)
overlayList.BackgroundTransparency = 1
overlayList.ZIndex = 41
overlayList.Parent = overlay
local playersList = Window.List(overlayList)
local overlayClose = Style.Button(overlay, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 34), Text = "Закрыть", TextSize = 13, Color = C.Card, ZIndex = 41 })
overlayClose.Activated:Connect(function()
	overlay.Visible = false
end)

local function fillPlayers()
	for _, child in ipairs(playersList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local others = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			others += 1
			local row = Style.Panel(playersList, { Size = UDim2.new(1, -6, 0, 40), Fill = C.Card, Border = C.Line, Cut = 6, ZIndex = 41 })
			Style.Label(row, other.DisplayName, 13, C.Text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -110, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 42 })
			Style.Label(row, "ур. " .. tostring(other:GetAttribute("Level") or 1), 11, C.Muted, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -94, 0.5, 0), Size = UDim2.fromOffset(40, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 42 })
			local button = Style.Button(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(84, 30), Text = "Позвать", TextSize = 12, Color = C.Gold, ZIndex = 43 })
			button.Activated:Connect(function()
				call(partyRemote, "Invite", other.UserId)
			end)
		end
	end
	if others == 0 then
		Style.Label(playersList, PT.Nobody, 13, C.Muted, { Size = UDim2.new(1, -6, 0, 40), TextWrapped = true, ZIndex = 42 })
	end
end
inviteButton.Activated:Connect(function()
	fillPlayers()
	overlay.Visible = true
end)
leaveButton.Activated:Connect(function()
	call(partyRemote, "Leave")
end)

startButton.Activated:Connect(function()
	local location = Config.LocationById[selectedLocation]
	if location and location.Ready then
		call(gateRemote, "Start", location.Id)
	end
end)
searchButton.Activated:Connect(function()
	if search then
		call(partyRemote, "Cancel")
	else
		call(partyRemote, "Search", selectedLocation)
	end
end)

---------------------------------------------------------------------

local function rankOpen(rank: string): (boolean, string)
	local open = decode("GateRanks")
	if open[rank] then
		return true, ""
	end
	local info = G.RankInfo[rank]
	if (player:GetAttribute("Level") or 1) < info.Level then
		return false, T.NeedLevel:format(info.Level)
	end
	if info.Requires then
		return false, T.NeedRank:format(info.Requires)
	end
	return false, T.Locked
end

local function dropText(rank: string): string
	local tables = Config.Loot.Tables[rank]
	local best
	for _, rarity in ipairs(Config.Rarities) do
		if tables and ((tables.Boss[rarity.Id] or 0) > 0 or (tables.Normal[rarity.Id] or 0) > 0) then
			best = rarity
		end
	end
	return if best then ('Добыча до <font color="%s">%s</font>'):format(hex(best.Color), best.Name) else ""
end

function refresh()
	local best = decode("GateBest")
	for _, rank in ipairs(G.Ranks) do
		local ui = rankCards[rank]
		local open, reason = rankOpen(rank)
		ui.status.Text = if open then G.RankInfo[rank].Text else reason
		ui.status.TextColor3 = if open then C.Muted else Color3.fromRGB(200, 120, 110)
		ui.lock.Visible = not open
		ui.shape.SetBorder(if rank == selectedRank then G.Colors[rank] else C.Line)
	end
	local info = G.RankInfo[selectedRank]
	rankTitle.Text = Style.Upper(info.Name)
	rankTitle.TextColor3 = G.Colors[selectedRank]
	rankText.Text = info.Text
	local rankIsOpen = rankOpen(selectedRank)
	for _, location in ipairs(G.Locations) do
		local ui = cardFor(location)
		ui.card.Visible = location.Rank == selectedRank
		if ui.card.Visible then
			ui.rec.Text = "Рек.: " .. recommendText(location)
			local boss = Config.Mobs.Defs[location.Boss]
			ui.info.Text = T.Zones:format(#location.Sections, location.Enemies, boss and boss.Name or "?")
			ui.grade.Text = best[location.Id] or ""
			ui.grade.TextColor3 = C.Gold
			ui.soon.Visible = not location.Ready
			ui.shape.SetBorder(if location.Id == selectedLocation then C.Gold else C.Line)
		end
	end
	-- red gates
	local raw = ReplicatedStorage:GetAttribute("RedGate")
	local ok, red = pcall(HttpService.JSONDecode, HttpService, if type(raw) == "string" and raw ~= "" then raw else "null")
	if ok and type(red) == "table" and red.Location then
		local location = Config.LocationById[red.Location]
		local left = math.max(0, math.floor(red.Ends - Workspace:GetServerTimeNow()))
		redCard.Visible = true
		redLine.Text = ("%s  •  ранг %s  •  %d:%02d"):format(location and location.Name or "?", location and location.Rank or "?", left // 60, left % 60)
	else
		redCard.Visible = false
	end
	-- details
	local location = Config.LocationById[selectedLocation]
	if location then
		local boss = Config.Mobs.Defs[location.Boss]
		dName.Text = Style.Upper(location.Name)
		dText.Text = location.Text or ""
		dRec.Text = "Рекомендуется: " .. recommendText(location)
		dInfo.Text = T.Zones:format(#location.Sections, location.Enemies, boss and boss.Name or "?") .. "\n" .. (if best[location.Id] then T.Best:format(best[location.Id]) else "")
		dDrop.Text = dropText(location.Rank)
		local canStart = location.Ready and rankIsOpen
		local leader = not party or party.Leader == player.UserId
		startButton.Text = if not location.Ready then T.Soon elseif not rankIsOpen then T.Locked elseif not leader then T.NotLeader elseif party then ("%s (%d)"):format(T.Party, #party.Members) else T.Solo
		startColor(if canStart and leader then C.Gold else C.Card)
		startButton.Active = canStart and leader
		searchButton.Visible = canStart and not party
		if search then
			local left = math.max(0, math.ceil(search.Ends - Workspace:GetServerTimeNow()))
			searchButton.Text = PT.Search:format(left) .. "  •  отмена"
			searchColor(C.Gold)
		else
			searchButton.Text = "Найти группу"
			searchColor(C.Card)
		end
	end
	-- group
	local membersList = party and party.Members or {}
	for i, label in ipairs(memberLabels) do
		local member = membersList[i]
		if member then
			label.Text = (if party.Leader == member.UserId then "★ " else "• ") .. member.Name
			label.TextColor3 = if member.UserId == player.UserId then C.Gold else C.Text
		elseif i == 1 then
			label.Text = PT.Solo
			label.TextColor3 = C.Muted
		else
			label.Text = ""
		end
	end
	memberLabels[1].TextWrapped = party == nil
	memberLabels[1].Size = if party then UDim2.new(1, -24, 0, 20) else UDim2.new(1, -24, 0, 40)
	leaveButton.Visible = party ~= nil
end

partyEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "State" then
		party = payload
	elseif kind == "Search" then
		search = payload
	end
	if window.IsOpen() then
		refresh()
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if window.IsOpen() then
			refresh()
		end
	end
end)

window.OnOpen = function()
	overlay.Visible = false
	-- start on the highest open rank
	local open = decode("GateRanks")
	for _, rank in ipairs(G.Ranks) do
		if open[rank] and Config.LocationById[selectedLocation] and Config.LocationById[selectedLocation].Rank ~= rank then
			local any = false
			for _, l in ipairs(G.Locations) do
				if l.Rank == rank and l.Ready then
					any = true
				end
			end
			if any and selectedRank ~= rank and Config.GateRankIndex[rank] > Config.GateRankIndex[selectedRank] then
				selectedRank = rank
			end
		end
	end
	if Config.LocationById[selectedLocation].Rank ~= selectedRank then
		for _, l in ipairs(G.Locations) do
			if l.Rank == selectedRank then
				selectedLocation = l.Id
				break
			end
		end
	end
	refresh()
end

Gates.Window = window
Gates.Open = function()
	if player:GetAttribute("Zone") == "Dungeon" then
		return
	end
	window.Open()
end

ReplicatedStorage:WaitForChild("GateState").OnClientEvent:Connect(function(kind)
	if kind == "Open" and not Window.AnyOpen() then
		Gates.Open()
	end
end)

return Gates
