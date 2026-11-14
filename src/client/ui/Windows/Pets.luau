--[[
	Pets.luau
	"Питомцы" window with three tabs:
	  Мои    - grid of owned pets (stacks per tier), equip / unequip,
	           merge 3 equal pets into the next tier, "Надеть лучших";
	           the header shows slots and the total bonus.
	  Яйца   - the eggs (Config.Eggs) with their chances; hatch 1, or 3
	           with the "Открытие 3 яиц" pass. Hatch animation: the eggs
	           shake, crack with a flash and show the pets (faster with
	           the "Быстрые яйца" pass).
	  Индекс - every pet in the game; unknown ones are dark silhouettes.
	Everything is decided by the server (Pets remote).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.Parent.Parent.PlayerData)
local Popups = require(script.Parent.Parent.Popups)
local Preview = require(script.Parent.Parent.Preview)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local petsRemote = ReplicatedStorage:WaitForChild("Pets")
local aura = player:WaitForChild("leaderstats"):WaitForChild("Aura")

local Pets = {}

local window = Window.new("Питомцы", Style.Colors.Magenta, Vector2.new(720, 500))
local content = window.Content
local tabs, selectTab = Window.Tabs(content, { { Id = "Mine", Text = "🐾 Мои" }, { Id = "Eggs", Text = "🥚 Яйца" }, { Id = "Index", Text = "📖 Индекс" } }, Style.Colors.Magenta, 140)

local pages = {}
local function page(id)
	local holder = Instance.new("Frame")
	holder.Position = UDim2.fromOffset(0, 48)
	holder.Size = UDim2.new(1, 0, 1, -48)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 32
	holder.Visible = false
	holder.Parent = content
	pages[id] = holder
	return holder
end

local busy = false
local function call(action, arg, extra, onDone)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message, results = petsRemote:InvokeServer(action, arg, extra)
		busy = false
		if onDone then
			onDone(ok, message, results)
		elseif message then
			Popups.Toast(message, if ok then "good" else "bad")
		end
	end)
end

local function percent(value: number): string
	return "+" .. Format.Number(math.floor(value * 100 + 0.5)) .. "%"
end

---------------------------------------------------------------------
-- Мои
---------------------------------------------------------------------

local mine = page("Mine")
local summary = Style.Label(mine, "", 18, Style.Colors.Gold, { Size = UDim2.new(1, -190, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 33 })
local bestButton = Style.Button(mine, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(180, 32), Color = Style.Colors.Green, Text = "Надеть лучших", TextSize = 17, ZIndex = 34, Shadow = false })
bestButton.Activated:Connect(function()
	call("EquipBest")
end)
local mineHolder = Instance.new("Frame")
mineHolder.Position = UDim2.fromOffset(0, 38)
mineHolder.Size = UDim2.new(1, 0, 1, -38)
mineHolder.BackgroundTransparency = 1
mineHolder.ZIndex = 32
mineHolder.Parent = mine
local mineGrid = Window.Grid(mineHolder, UDim2.fromOffset(160, 200))
local mineEmpty = Style.Label(mineHolder, "Питомцев пока нет — открой яйцо!", 20, Style.Colors.Muted, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 30), ZIndex = 33 })

local cards = {} -- [key] = ui

local function petCard(key, pet, tier)
	if cards[key] then
		return cards[key]
	end
	local rarity = Config.Rarity[pet.Rarity]
	local tierDef = Config.PetTiers[tier]
	local card = Style.Card(mineGrid, tierDef.Color or rarity.Color, tierDef.Rainbow or rarity.Rainbow)
	card.Name = key
	Preview.Create(card, "Pet", { Pet = pet, Tier = tier }, UDim2.new(1, -16, 0, 74), UDim2.fromOffset(8, 8))
	local title = (if tierDef.Name ~= "" then tierDef.Name .. " " else "") .. pet.Name
	Style.Label(card, title, 15, rarity.Color, { Position = UDim2.fromOffset(4, 84), Size = UDim2.new(1, -8, 0, 20), TextScaled = true, ZIndex = 35 })
	local bonus = pet.Bonus * tierDef.Multiplier
	local damage = (pet.DamageBonus or 0) * tierDef.Multiplier
	Style.Label(card, percent(bonus) .. " Аура" .. (if damage > 0 then "  " .. percent(damage) .. " урон" else ""), 13, Style.Colors.Text, { Position = UDim2.fromOffset(4, 104), Size = UDim2.new(1, -8, 0, 18), TextScaled = true, ZIndex = 35 })
	local count = Style.Label(card, "", 14, Style.Colors.Gold, { Position = UDim2.fromOffset(4, 122), Size = UDim2.new(1, -8, 0, 18), ZIndex = 35 })
	local equip, setEquipColor = Style.Button(card, { Position = UDim2.fromOffset(6, 142), Size = UDim2.new(1, -12, 0, 24), Color = Style.Colors.Blue, Text = "Надеть", TextSize = 14, ZIndex = 36, Shadow = false })
	local mergeButton, setMergeColor = Style.Button(card, { Position = UDim2.fromOffset(6, 170), Size = UDim2.new(1, -12, 0, 24), Color = Style.Colors.Purple, Text = "", TextSize = 13, ZIndex = 36, Shadow = false })
	local ui = { card = card, count = count, equip = equip, setEquipColor = setEquipColor, merge = mergeButton, setMergeColor = setMergeColor, state = nil }
	equip.Activated:Connect(function()
		call(if ui.state == "unequip" then "Unequip" else "Equip", key)
	end)
	mergeButton.Activated:Connect(function()
		call("Merge", key, nil, function(ok, message)
			Popups.Toast(message or "", if ok then "gold" else "bad")
			if ok then
				Popups.Flash(Config.PetTiers[math.min(tier + 1, #Config.PetTiers)].Color or Style.Colors.Gold)
				Style.PlaySound(Config.Sounds.Forged, 1.3, 0.6)
			end
		end)
	end)
	cards[key] = ui
	return ui
end

local function refreshMine()
	local owned = PlayerData.Table("Pets")
	local equipped = {}
	local equippedTotal = 0
	for key in string.gmatch(player:GetAttribute("EquippedPets") or "", "[^,]+") do
		equipped[key] = (equipped[key] or 0) + 1
		equippedTotal += 1
	end
	local slots = player:GetAttribute("PetSlots") or Config.PetSlots
	for _, ui in pairs(cards) do
		ui.card.Visible = false
	end
	local any = false
	for petId, tiers in pairs(owned) do
		local pet = Config.PetById[petId]
		if pet and type(tiers) == "table" then
			for tierText, n in pairs(tiers) do
				local tier = tonumber(tierText)
				if tier and n > 0 and Config.PetTiers[tier] then
					any = true
					local key = petId .. ":" .. tier
					local ui = petCard(key, pet, tier)
					ui.card.Visible = true
					ui.card.LayoutOrder = -(pet.Bonus * Config.PetTiers[tier].Multiplier * 1000)
					local on = equipped[key] or 0
					ui.count.Text = ("x%d%s"):format(n, if on > 0 then ("  •  надето %d"):format(on) else "")
					if on >= n then
						ui.state = "unequip"
						ui.equip.Text = "Снять"
						ui.setEquipColor(Style.Colors.Red)
					else
						ui.state = "equip"
						ui.equip.Text = "Надеть"
						ui.setEquipColor(if equippedTotal < slots then Style.Colors.Blue else Color3.fromRGB(110, 110, 130))
					end
					local canMerge = tier < #Config.PetTiers
					ui.merge.Visible = canMerge
					if canMerge then
						ui.merge.Text = ("Слить %d/%d → %s"):format(math.min(n, Config.PetMerge), Config.PetMerge, Config.PetTiers[tier + 1].Name)
						ui.setMergeColor(if n >= Config.PetMerge then Style.Colors.Purple else Color3.fromRGB(110, 110, 130))
					end
				end
			end
		end
	end
	mineEmpty.Visible = not any
	summary.Text = ("Надето %d/%d  •  Аура x%s"):format(equippedTotal, slots, tostring(math.floor((player:GetAttribute("AuraMultiplier") or 1) * 100 + 0.5) / 100))
end

---------------------------------------------------------------------
-- Яйца + hatch animation
---------------------------------------------------------------------

local eggsPage = page("Eggs")
local eggList = Window.List(eggsPage)
local eggRows = {}

local overlay = Instance.new("TextButton")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Style.Colors.PanelDark
overlay.AutoButtonColor = false
overlay.Text = ""
overlay.Visible = false
overlay.ZIndex = 50
overlay.Parent = window.Frame
Style.Corner(overlay, UDim.new(0, 20))

local function playHatch(egg, results)
	overlay.Visible = true
	for _, child in ipairs(overlay:GetChildren()) do
		if not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	local seconds = if PlayerData.HasPass("FastEgg") then Config.Hatch.FastSeconds else Config.Hatch.Seconds
	local n = #results
	local slots = {}
	for i, petId in ipairs(results) do
		local x = (i - 0.5) / n
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(x, 0.42)
		holder.Size = UDim2.fromOffset(180, 200)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 52
		holder.Parent = overlay
		local eggShape = Instance.new("Frame")
		eggShape.AnchorPoint = Vector2.new(0.5, 0.5)
		eggShape.Position = UDim2.fromScale(0.5, 0.5)
		eggShape.Size = UDim2.fromOffset(110, 140)
		eggShape.BackgroundColor3 = egg.Color
		eggShape.ZIndex = 53
		eggShape.Parent = holder
		Style.Corner(eggShape, UDim.new(0.5, 0))
		Style.Stroke(eggShape, 4)
		for s = 1, 3 do
			local spot = Instance.new("Frame")
			spot.Position = UDim2.fromScale(0.2 + s * 0.17, 0.25 + (s % 2) * 0.3)
			spot.Size = UDim2.fromOffset(18, 18)
			spot.BackgroundColor3 = Style.Darker(egg.Color, 0.3)
			spot.ZIndex = 54
			spot.Parent = eggShape
			Style.Corner(spot, UDim.new(0.5, 0))
		end
		slots[i] = { holder = holder, egg = eggShape, petId = petId }
	end
	task.spawn(function()
		-- shake harder and harder
		local steps = math.max(6, math.floor(seconds / 0.08))
		for step = 1, steps do
			for _, slot in ipairs(slots) do
				slot.egg.Rotation = (if step % 2 == 0 then 1 else -1) * (4 + step * 22 / steps)
			end
			task.wait(seconds / steps)
		end
		Popups.Flash(Color3.new(1, 1, 1))
		Popups.Shake(0.4, 0.2)
		Style.PlaySound(Config.Sounds.Forged, 1.4, 0.6)
		local bestRarity = 1
		for _, slot in ipairs(slots) do
			local pet = Config.PetById[slot.petId]
			local rarity = Config.Rarity[pet.Rarity]
			bestRarity = math.max(bestRarity, rarity.Index)
			slot.egg:Destroy()
			local glow = Instance.new("Frame")
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.fromScale(0.5, 0.42)
			glow.Size = UDim2.fromOffset(160, 160)
			glow.BackgroundColor3 = rarity.Color
			glow.BackgroundTransparency = 0.6
			glow.ZIndex = 52
			glow.Parent = slot.holder
			Style.Corner(glow, UDim.new(0.5, 0))
			local viewport = Preview.Create(slot.holder, "Pet", { Pet = pet, Tier = 1 }, UDim2.fromOffset(150, 150), UDim2.fromOffset(15, 0))
			if viewport then
				viewport.BackgroundTransparency = 1
				viewport.ZIndex = 54
			end
			local name = Style.Label(slot.holder, pet.Name, 22, rarity.Color, { Position = UDim2.new(0, 0, 1, -46), Size = UDim2.new(1, 0, 0, 26), TextScaled = true, ZIndex = 55 })
			if rarity.Rainbow then
				Style.Rainbow(name)
			end
			Style.Label(slot.holder, rarity.Name, 16, Style.Colors.Text, { Position = UDim2.new(0, 0, 1, -20), Size = UDim2.new(1, 0, 0, 20), ZIndex = 55 })
			local pop = Instance.new("UIScale")
			pop.Scale = 0.2
			pop.Parent = slot.holder
			Style.Tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		if bestRarity >= Config.Rarity.Legendary.Index then
			Popups.Flash(Config.Rarities[bestRarity].Color)
		end
		local done = Style.Button(overlay, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(220, 46), Color = Style.Colors.Green, Text = "Отлично!", TextSize = 22, ZIndex = 60, Shadow = false })
		done.Activated:Connect(function()
			overlay.Visible = false
		end)
	end)
end

local function hatch(egg, triple)
	call("Hatch", egg.Id, triple, function(ok, message, results)
		if ok and type(results) == "table" then
			playHatch(egg, results)
		else
			Popups.Toast(message or "", "bad")
		end
	end)
end

for order, egg in ipairs(Config.Eggs) do
	local row = Style.Card(eggList, egg.Color)
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -10, 0, 128)
	local icon = Instance.new("Frame")
	icon.Position = UDim2.fromOffset(14, 14)
	icon.Size = UDim2.fromOffset(78, 100)
	icon.BackgroundColor3 = egg.Color
	icon.ZIndex = 34
	icon.Parent = row
	Style.Corner(icon, UDim.new(0.5, 0))
	Style.Stroke(icon, 3)
	Style.Label(row, egg.Name, 22, egg.Color, { Position = UDim2.fromOffset(104, 8), Size = UDim2.new(1, -300, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
	-- chances
	local total = 0
	for _, entry in ipairs(egg.Pets) do
		total += entry.Weight
	end
	local parts = {}
	for _, entry in ipairs(egg.Pets) do
		local pet = Config.PetById[entry.Id]
		table.insert(parts, ("%s %s%%"):format(pet.Name, tostring(math.floor(entry.Weight / total * 1000 + 0.5) / 10)))
	end
	Style.Label(row, table.concat(parts, "  •  "), 14, Style.Colors.Muted, { Position = UDim2.fromOffset(104, 40), Size = UDim2.new(1, -300, 0, 76), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 35 })
	local one, setOne = Style.Button(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 14), Size = UDim2.fromOffset(176, 46), Color = Style.Colors.Green, Text = "", TextSize = 17, ZIndex = 36, Shadow = false })
	local three, setThree = Style.Button(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 68), Size = UDim2.fromOffset(176, 46), Color = Style.Colors.Purple, Text = "", TextSize = 17, ZIndex = 36, Shadow = false })
	one.Activated:Connect(function()
		hatch(egg, false)
	end)
	three.Activated:Connect(function()
		if PlayerData.HasPass("TripleEgg") then
			hatch(egg, true)
		else
			Popups.Toast("Открытие 3 яиц — Game Pass в Магазине", "gold")
		end
	end)
	eggRows[egg.Id] = { egg = egg, one = one, setOne = setOne, three = three, setThree = setThree }
end

local function refreshEggs()
	local triple = PlayerData.HasPass("TripleEgg")
	for _, row in pairs(eggRows) do
		local cost = row.egg.Cost
		row.one.Text = "Открыть: " .. Format.Number(cost) .. " ✨"
		row.setOne(if aura.Value >= cost then Style.Colors.Green else Style.Colors.Red)
		row.three.Text = if triple then "x3: " .. Format.Number(cost * Config.Hatch.TripleCount) .. " ✨" else "🔒 Открыть 3"
		row.setThree(if triple and aura.Value >= cost * Config.Hatch.TripleCount then Style.Colors.Purple else Color3.fromRGB(110, 110, 130))
	end
end

---------------------------------------------------------------------
-- Индекс
---------------------------------------------------------------------

local indexPage = page("Index")
local indexTitle = Style.Label(indexPage, "", 18, Style.Colors.Gold, { Size = UDim2.new(1, 0, 0, 28), ZIndex = 33 })
local indexHolder = Instance.new("Frame")
indexHolder.Position = UDim2.fromOffset(0, 34)
indexHolder.Size = UDim2.new(1, 0, 1, -34)
indexHolder.BackgroundTransparency = 1
indexHolder.ZIndex = 32
indexHolder.Parent = indexPage
local indexGrid = Window.Grid(indexHolder, UDim2.fromOffset(124, 150))
local indexCards = {}
for _, pet in ipairs(Config.Pets) do
	local rarity = Config.Rarity[pet.Rarity]
	local card = Style.Card(indexGrid, rarity.Color, rarity.Rainbow)
	card.LayoutOrder = pet.Order
	local viewport = Preview.Create(card, "Pet", { Pet = pet, Tier = 1 }, UDim2.new(1, -16, 0, 80), UDim2.fromOffset(8, 8))
	local name = Style.Label(card, pet.Name, 14, rarity.Color, { Position = UDim2.fromOffset(4, 92), Size = UDim2.new(1, -8, 0, 20), TextScaled = true, ZIndex = 35 })
	Style.Label(card, rarity.Name, 13, Style.Colors.Muted, { Position = UDim2.fromOffset(4, 114), Size = UDim2.new(1, -8, 0, 16), ZIndex = 35 })
	indexCards[pet.Id] = { viewport = viewport, name = name, pet = pet }
end

local function refreshIndex()
	local known = PlayerData.Set("PetIndex")
	local found = 0
	for petId, ui in pairs(indexCards) do
		local isKnown = known[petId] == true
		if isKnown then
			found += 1
		end
		ui.name.Text = if isKnown then ui.pet.Name else "???"
		if ui.viewport then
			ui.viewport.ImageColor3 = if isKnown then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		end
	end
	indexTitle.Text = ("Открыто питомцев: %d / %d"):format(found, #Config.Pets)
end

---------------------------------------------------------------------

local function refresh()
	refreshMine()
	refreshEggs()
	refreshIndex()
end

tabs.Changed = function(id)
	for key, holder in pairs(pages) do
		holder.Visible = key == id
	end
	refresh()
end
selectTab("Mine")

PlayerData.Changed({ "Pets", "EquippedPets", "PetIndex", "PetSlots", "Passes", "AuraMultiplier" }, function()
	if window.IsOpen() then
		refresh()
	end
end)
local lastAura = 0
aura.Changed:Connect(function()
	if window.IsOpen() and os.clock() - lastAura > 0.3 then
		lastAura = os.clock()
		refreshEggs()
	end
end)
window.OnOpen = function()
	overlay.Visible = false
	refresh()
end

-- Is there an egg the player can afford right now? (menu badge)
function Pets.CanHatch(): boolean
	return aura.Value >= Config.Eggs[1].Cost
end

Pets.Window = window
function Pets.Open()
	selectTab("Mine")
	window.Open()
end
function Pets.OpenEggs()
	selectTab("Eggs")
	window.Open()
end
return Pets
