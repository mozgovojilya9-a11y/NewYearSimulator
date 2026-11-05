-- Winter Academy client HUD: responsive layout, clear actions and animated panels.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local state = nil
local selectedZone = 1
local autoTrain = false
local activePanel = nil
local notice
local toastToken = 0
local rewardToken = 0

local COLORS = {
    background = Color3.fromRGB(17, 16, 34),
    panel = Color3.fromRGB(29, 25, 52),
    panelSoft = Color3.fromRGB(43, 36, 72),
    panelLight = Color3.fromRGB(59, 48, 94),
    gold = Color3.fromRGB(255, 199, 105),
    goldSoft = Color3.fromRGB(255, 225, 171),
    cream = Color3.fromRGB(255, 245, 224),
    muted = Color3.fromRGB(173, 169, 199),
    purple = Color3.fromRGB(146, 93, 218),
    blue = Color3.fromRGB(68, 137, 207),
    cyan = Color3.fromRGB(75, 195, 218),
    green = Color3.fromRGB(61, 157, 116),
    red = Color3.fromRGB(190, 70, 94),
}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function formatNumber(number)
    number = tonumber(number) or 0
    local index = 1
    while number >= 1000 and index < #SUFFIXES do
        number /= 1000
        index += 1
    end
    if index == 1 then
        return tostring(math.floor(number))
    end
    return ("%.2f%s"):format(number, SUFFIXES[index])
end

local function create(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(object, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, object)
end

local function addStroke(object, color, thickness, transparency)
    create("UIStroke", {
        Color = color or COLORS.gold,
        Thickness = thickness or 1.5,
        Transparency = transparency or 0.12,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

local function addGradient(object, color)
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.14)),
            ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.22)),
        }),
        Rotation = 90,
    }, object)
end

local function makeLabel(parent, text, size, position, color, font, alignment)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Text = text or "",
        TextSize = size or 14,
        TextColor3 = color or COLORS.cream,
        Font = font or Enum.Font.GothamMedium,
        TextXAlignment = alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = true,
        Position = position or UDim2.new(),
        Size = UDim2.new(1, 0, 0, 26),
    }, parent)
end

local function animate(object, duration, properties, style)
    local tween = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.18, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        properties
    )
    tween:Play()
    return tween
end

local function makeButton(parent, text, color, size, position, callback, options)
    options = options or {}
    local b = create("TextButton", {
        Name = options.Name or "ActionButton",
        Size = size,
        Position = position,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = options.TextColor or COLORS.cream,
        TextSize = options.TextSize or 14,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = options.Font or Enum.Font.GothamBold,
        AutoButtonColor = false,
        ClipsDescendants = true,
        ZIndex = options.ZIndex or 4,
    }, parent)
    addCorner(b, options.Radius or 11)
    addStroke(b, options.StrokeColor or COLORS.gold, options.StrokeThickness or 1.2, 0.22)
    addGradient(b, color)

    local scale = create("UIScale", { Scale = 1 }, b)
    b.MouseEnter:Connect(function()
        animate(scale, 0.12, { Scale = 1.035 })
    end)
    b.MouseLeave:Connect(function()
        animate(scale, 0.12, { Scale = 1 })
    end)
    b.Activated:Connect(function()
        animate(scale, 0.07, { Scale = 0.965 })
        task.delay(0.08, function()
            if scale.Parent then animate(scale, 0.12, { Scale = 1 }) end
        end)
        callback()
    end)
    return b
end

-- Root UI and adaptive scale.
local gui = create("ScreenGui", {
    Name = "WinterAcademyUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    DisplayOrder = 30,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

local root = create("Frame", {
    Name = "Root",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
}, gui)

local rootScale = create("UIScale", { Scale = 1 }, root)
local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local scale = math.clamp(viewport.X / 1420, 0.72, 1.08)
    if viewport.X < 700 then scale = math.clamp(viewport.X / 570, 0.68, 0.9) end
    rootScale.Scale = scale
end

-- Soft darkened HUD cards with a restrained gold frame.
local function makeCard(parent, name, size, position, accent)
    local card = create("Frame", {
        Name = name,
        Size = size,
        Position = position,
        BackgroundColor3 = COLORS.background,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
    }, parent)
    addCorner(card, 14)
    addStroke(card, accent or COLORS.gold, 1.5, 0.14)
    return card
end

-- Header.
local brand = makeCard(root, "Brand", UDim2.fromScale(0.205, 0.085), UDim2.fromScale(0.018, 0.025), COLORS.purple)
makeLabel(brand, "✦ ЗИМНЯЯ АКАДЕМИЯ", 18, UDim2.fromScale(0.07, 0.12), COLORS.gold, Enum.Font.GothamBlack)
makeLabel(brand, "ПУТЬ УЧЕНИКА  ·  ГЛАВА I", 10, UDim2.fromScale(0.08, 0.58), COLORS.muted, Enum.Font.GothamMedium)

local stageCard = makeCard(root, "StageHeader", UDim2.fromScale(0.34, 0.085), UDim2.fromScale(0.33, 0.025), COLORS.blue)
local stageTitle = makeLabel(stageCard, "ЭТАП 1  ·  СНЕЖНЫЙ ДВОР", 15, UDim2.fromScale(0.05, 0.08), COLORS.gold, Enum.Font.GothamBold)
local stageHint = makeLabel(stageCard, "Следующая цель: Снежный гоблин", 11, UDim2.fromScale(0.05, 0.53), COLORS.cream, Enum.Font.GothamMedium)

local mentorBadge = makeCard(root, "EquippedMentor", UDim2.fromScale(0.19, 0.085), UDim2.fromScale(0.79, 0.025), COLORS.purple)
local mentorName = makeLabel(mentorBadge, "НАСТАВНИК: Снежок Хранитель", 12, UDim2.fromScale(0.06, 0.12), COLORS.cream, Enum.Font.GothamBold)
local mentorBonus = makeLabel(mentorBadge, "Молния ×1.00", 10, UDim2.fromScale(0.06, 0.56), COLORS.muted, Enum.Font.GothamMedium)

-- Left navigation. Only sections that actually work are shown.
local navigation = makeCard(root, "Navigation", UDim2.fromScale(0.16, 0.39), UDim2.fromScale(0.018, 0.23), COLORS.purple)
makeLabel(navigation, "АКАДЕМИЯ", 11, UDim2.fromScale(0.08, 0.035), COLORS.muted, Enum.Font.GothamBold)

-- Resource card is tall enough for all lines; no stat is placed outside the frame.
local resources = makeCard(root, "Resources", UDim2.fromScale(0.19, 0.22), UDim2.fromScale(0.018, 0.68), COLORS.gold)
makeLabel(resources, "ВАШ ПРОГРЕСС", 10, UDim2.fromScale(0.07, 0.07), COLORS.muted, Enum.Font.GothamBold)
local lightningValue = makeLabel(resources, "⚡  Молния: 0", 17, UDim2.fromScale(0.07, 0.23), COLORS.gold, Enum.Font.GothamBold)
local winsValue = makeLabel(resources, "✦  Победы: 0", 15, UDim2.fromScale(0.07, 0.47), COLORS.cream, Enum.Font.GothamBold)
local rebirthValue = makeLabel(resources, "↻  Перерождения: 0", 13, UDim2.fromScale(0.07, 0.70), COLORS.muted, Enum.Font.GothamMedium)

-- Main progress card.
local progress = makeCard(root, "PowerProgress", UDim2.fromScale(0.46, 0.13), UDim2.fromScale(0.27, 0.69), COLORS.gold)
local powerTitle = makeLabel(progress, "⚡  МОЛНИЯ  0", 21, UDim2.fromScale(0.04, 0.04), COLORS.gold, Enum.Font.GothamBlack)
local levelTitle = makeLabel(progress, "Уровень 1  ·  0 / 100", 12, UDim2.fromScale(0.04, 0.42), COLORS.cream, Enum.Font.GothamMedium)
local progressTrack = create("Frame", {
    Size = UDim2.fromScale(0.92, 0.17),
    Position = UDim2.fromScale(0.04, 0.75),
    BackgroundColor3 = COLORS.panelSoft,
    BorderSizePixel = 0,
}, progress)
addCorner(progressTrack, 8)
local progressFill = create("Frame", {
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = COLORS.gold,
    BorderSizePixel = 0,
}, progressTrack)
addCorner(progressFill, 8)
addGradient(progressFill, COLORS.gold)

-- Battle status: visible only while a monster is active.
local battleCard = makeCard(root, "BattleStatus", UDim2.fromScale(0.34, 0.105), UDim2.fromScale(0.33, 0.135), COLORS.red)
battleCard.Visible = false
local battleName = makeLabel(battleCard, "ПРОТИВНИК", 14, UDim2.fromScale(0.05, 0.04), COLORS.gold, Enum.Font.GothamBold)
local battleNumbers = makeLabel(battleCard, "90 / 90 HP", 11, UDim2.fromScale(0.05, 0.4), COLORS.cream, Enum.Font.GothamMedium)
local battleTrack = create("Frame", {
    Size = UDim2.fromScale(0.9, 0.15),
    Position = UDim2.fromScale(0.05, 0.76),
    BackgroundColor3 = COLORS.panelSoft,
    BorderSizePixel = 0,
}, battleCard)
addCorner(battleTrack, 7)
local battleFill = create("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = COLORS.red,
    BorderSizePixel = 0,
}, battleTrack)
addCorner(battleFill, 7)

-- Bottom action bar.
local actions = create("Frame", {
    Name = "Actions",
    Size = UDim2.fromScale(0.76, 0.105),
    Position = UDim2.fromScale(0.12, 0.855),
    BackgroundTransparency = 1,
}, root)
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0.012, 0),
}, actions)

local function actionButton(text, color, callback, name)
    return makeButton(actions, text, color, UDim2.new(0.19, 0, 0.82, 0), UDim2.new(), callback, {
        Name = name, TextSize = 13, Radius = 12,
    })
end

local autoButton
local fightButton
local trainButton = actionButton("ТРЕНИРОВКА", COLORS.green, function()
    Remotes.Train:FireServer(selectedZone)
end, "Train")
autoButton = actionButton("АВТО: ВЫКЛ", COLORS.purple, function()
    autoTrain = not autoTrain
    autoButton.Text = autoTrain and "АВТО: ВКЛ" or "АВТО: ВЫКЛ"
    notice(autoTrain and "Автотренировка включена" or "Автотренировка выключена")
end, "AutoTrain")
fightButton = actionButton("НАЧАТЬ БОЙ", COLORS.red, function()
    if state and state.BattleActive then
        Remotes.Attack:FireServer()
    else
        Remotes.Fight:FireServer()
    end
end, "Fight")
local abilityButton = actionButton("СПОСОБНОСТЬ", COLORS.blue, function()
    Remotes.UseAbility:FireServer()
end, "Ability")
local rebirthButton = actionButton("ПЕРЕРОЖДЕНИЕ", COLORS.panelLight, function()
    Remotes.Rebirth:FireServer()
end, "Rebirth")

-- Modal panel factory.
local panels = {}
local panelContents = {}
local function createPanel(name, title)
    local panel = create("Frame", {
        Name = name,
        Size = UDim2.fromScale(0.49, 0.61),
        Position = UDim2.fromScale(0.255, 0.18),
        BackgroundColor3 = COLORS.background,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
        ClipsDescendants = true,
    }, root)
    addCorner(panel, 18)
    addStroke(panel, COLORS.gold, 2, 0.08)
    local panelScale = create("UIScale", { Scale = 0.92 }, panel)
    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, 54),
        BackgroundColor3 = COLORS.panelSoft,
        BorderSizePixel = 0,
        ZIndex = 21,
    }, panel)
    addCorner(header, 16)
    makeLabel(header, title, 19, UDim2.fromScale(0.04, 0.04), COLORS.gold, Enum.Font.GothamBlack)
    makeButton(header, "✕", COLORS.red, UDim2.fromOffset(40, 38), UDim2.new(1, -48, 0, 8), function()
        panel.Visible = false
        if activePanel == name then activePanel = nil end
    end, { TextSize = 18, ZIndex = 22, Radius = 10 })

    local body = create("ScrollingFrame", {
        Name = "Content",
        Size = UDim2.new(1, -22, 1, -68),
        Position = UDim2.fromOffset(11, 61),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = COLORS.gold,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 21,
    }, panel)
    create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, body)

    panels[name] = panel
    panelContents[name] = body
    panel:SetAttribute("PanelScale", 1)
    panelScale.Scale = 0.94
    return panel, body
end

local mentorsPanel, mentorsBody = createPanel("Mentors", "НАСТАВНИКИ АКАДЕМИИ")
local worldsPanel, worldsBody = createPanel("Worlds", "МИРЫ И ТРЕНИРОВОЧНЫЕ ЗОНЫ")
local inventoryPanel, inventoryBody = createPanel("Inventory", "ИНВЕНТАРЬ И ТРОФЕИ")
local questsPanel, questsBody = createPanel("Quests", "ИСПЫТАНИЯ УЧЕНИКА")
local petsPanel, petsBody = createPanel("Pets", "ПИТОМЦЫ И МАГИЧЕСКИЕ ЯЙЦА")
local craftPanel, craftBody = createPanel("Craft", "МАСТЕРСКАЯ АРТЕФАКТОВ")
local shopPanel, shopBody = createPanel("Shop", "ЛАВКА И ПРЕМИУМ")

local function clearRows(body)
    for _, child in ipairs(body:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end

local function makeListRow(body, title, detail, accent, buttonText, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, -6, 0, 76),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
        ZIndex = 22,
    }, body)
    addCorner(row, 11)
    addStroke(row, accent or COLORS.purple, 1.1, 0.32)

    local marker = create("Frame", {
        Size = UDim2.new(0, 4, 1, -14),
        Position = UDim2.fromOffset(7, 7),
        BackgroundColor3 = accent or COLORS.gold,
        BorderSizePixel = 0,
        ZIndex = 23,
    }, row)
    addCorner(marker, 3)

    makeLabel(row, title, 14, UDim2.fromOffset(20, 8), COLORS.cream, Enum.Font.GothamBold).Size = UDim2.new(0.61, 0, 0, 25)
    local detailLabel = makeLabel(row, detail, 11, UDim2.fromOffset(20, 36), COLORS.muted, Enum.Font.GothamMedium)
    detailLabel.Size = UDim2.new(0.61, 0, 0, 28)

    if buttonText and callback then
        makeButton(row, buttonText, accent or COLORS.purple, UDim2.new(0.29, 0, 0, 42), UDim2.new(0.68, 0, 0.5, -21), callback, {
            TextSize = 12, ZIndex = 24, Radius = 9,
        })
    end
    return row
end

local function openPanel(name)
    local nextPanel = nil
    if activePanel ~= name then
        nextPanel = name
    end
    activePanel = nextPanel
    for key, panel in pairs(panels) do
        panel.Visible = key == nextPanel
    end
    if nextPanel and panels[nextPanel] then
        local panel = panels[nextPanel]
        local scale = panel:FindFirstChildOfClass("UIScale")
        if scale then
            scale.Scale = 0.94
            animate(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
        end
        panel.BackgroundTransparency = 0.12
        animate(panel, 0.16, { BackgroundTransparency = 0 })
    end
end

-- Navigation buttons.
local navButtons = {}
local function addNav(text, color, order, callback)
    local b = makeButton(navigation, text, color, UDim2.new(1, -18, 0, 43), UDim2.new(0, 9, 0, 38 + (order - 1) * 49), callback, {
        TextSize = 12, Radius = 10,
    })
    table.insert(navButtons, b)
    return b
end

local function rebuildInventoryPanel()
    clearRows(inventoryBody)
    local entries = {}
    for itemId, amount in pairs((state and state.Inventory) or {}) do
        local item = Config.Items[itemId]
        if item and tonumber(amount) and amount > 0 then
            table.insert(entries, { Id = itemId, Item = item, Amount = amount })
        end
    end
    table.sort(entries, function(a, b)
        return a.Item.Value > b.Item.Value
    end)

    local equipment = state and state.Equipment or {}
    makeListRow(inventoryBody, "ЭКИПИРОВКА",
        "Оружие: " .. ((equipment.Weapon and Config.Items[equipment.Weapon] and Config.Items[equipment.Weapon].Name) or "пусто")
        .. "  ·  Броня: " .. ((equipment.Armor and Config.Items[equipment.Armor] and Config.Items[equipment.Armor].Name) or "пусто"),
        COLORS.gold, nil, nil)

    for _, entry in ipairs(entries) do
        local item = entry.Item
        local isGear = item.Type == "Weapon" or item.Type == "Armor"
        local equipped = equipment.Weapon == entry.Id or equipment.Armor == entry.Id
        local actionText = isGear and (equipped and "ЭКИПИРОВАНО" or "ЭКИПИРОВАТЬ") or "ПРОДАТЬ 1"
        local detail = item.Rarity .. "  ·  " .. item.Description .. "  ·  Цена: " .. formatNumber(item.Value)
        makeListRow(inventoryBody, item.Name .. "  ×" .. tostring(entry.Amount), detail,
            Config.RarityColors[item.Rarity] or COLORS.cyan, actionText, function()
                if isGear then
                    Remotes.EquipItem:FireServer(entry.Id)
                elseif not equipped then
                    Remotes.SellItem:FireServer(entry.Id, 1)
                end
            end)
    end
    if #entries == 0 then
        makeListRow(inventoryBody, "Пока нет трофеев", "Победи монстра, чтобы получить первый предмет.", COLORS.muted, nil, nil)
    end
end

local function rebuildPetsPanel()
    clearRows(petsBody)
    for eggId, egg in pairs(Config.PetEggs) do
        local chances = {}
        local totalWeight = 0
        for _, drop in ipairs(egg.Drops) do totalWeight += drop.Weight end
        for _, drop in ipairs(egg.Drops) do
            local pet = Config.PetById[drop.Id]
            if pet and totalWeight > 0 then
                local percent = (drop.Weight / totalWeight) * 100
                table.insert(chances, pet.Name .. " " .. string.format("%.1f%%", percent))
            end
        end
        makeListRow(petsBody, egg.Name, "Стоимость: " .. formatNumber(egg.Cost) .. " побед  ·  " .. table.concat(chances, "  |  "),
            COLORS.cyan, "ОТКРЫТЬ", function()
                Remotes.OpenEgg:FireServer(eggId)
            end)
    end
    makeListRow(petsBody, "МОЯ КОЛЛЕКЦИЯ",
        "Экипировано: " .. tostring(#((state and state.EquippedPets) or {})) .. " / " .. tostring((state and state.PetSlots) or Config.PetSlots),
        COLORS.gold, nil, nil)
    local found = 0
    for _, pet in ipairs(Config.Pets) do
        local owned = state and state.OwnedPets and (tonumber(state.OwnedPets[pet.Id]) or 0) or 0
        if owned > 0 then
            found += 1
            local equipped = state and table.find(state.EquippedPets or {}, pet.Id) ~= nil
            local detail = pet.Rarity .. "  ·  Молния ×" .. tostring(pet.PowerMult) .. "  ·  Победы ×" .. tostring(pet.WinMult) .. "  ·  В наличии: " .. tostring(owned)
            makeListRow(petsBody, pet.Name, detail, Config.RarityColors[pet.Rarity] or pet.Color,
                equipped and "СНЯТЬ" or "ЭКИПИРОВАТЬ", function()
                    Remotes.TogglePet:FireServer(pet.Id)
                end)
        end
    end
    if found == 0 then
        makeListRow(petsBody, "Питомцев пока нет", "Открой яйцо, чтобы получить первого компаньона.", COLORS.muted, nil, nil)
    end
end

local function rebuildCraftPanel()
    clearRows(craftBody)
    for recipeId, recipe in pairs(Config.CraftRecipes) do
        local parts = {}
        for itemId, amount in pairs(recipe.Ingredients) do
            local item = Config.Items[itemId]
            local current = state and state.Inventory and (tonumber(state.Inventory[itemId]) or 0) or 0
            table.insert(parts, (item and item.Name or itemId) .. " " .. tostring(current) .. "/" .. tostring(amount))
        end
        table.sort(parts)
        makeListRow(craftBody, recipe.Name, "Этап " .. tostring(recipe.MinStage) .. "  ·  " .. table.concat(parts, ", "),
            Config.RarityColors[(Config.Items[recipe.Output] and Config.Items[recipe.Output].Rarity) or "Редкий"],
            "СОЗДАТЬ", function()
                Remotes.CraftItem:FireServer(recipeId)
            end)
    end
    local equipment = state and state.Equipment or {}
    local weaponName = equipment.Weapon and Config.Items[equipment.Weapon] and Config.Items[equipment.Weapon].Name or "Не экипировано"
    local armorName = equipment.Armor and Config.Items[equipment.Armor] and Config.Items[equipment.Armor].Name or "Не экипировано"
    makeListRow(craftBody, "ТЕКУЩАЯ ЭКИПИРОВКА", "Оружие: " .. weaponName .. "  ·  Броня: " .. armorName, COLORS.gold, nil, nil)
end

addNav("✦  НАСТАВНИКИ", COLORS.purple, 1, function()
    if state then
        clearRows(mentorsBody)
        for _, hero in ipairs(Config.Heroes) do
            local owned = state.Owned and state.Owned[hero.Id] == true
            local equipped = state.Equipped == hero.Id
            local color = Config.RarityColors[hero.Rarity] or COLORS.purple
            local actionText = equipped and "ЭКИПИРОВАН" or (owned and "ВЫБРАТЬ" or ("НАЙМ  ·  " .. formatNumber(hero.Cost)))
            local detail = hero.Rarity .. "   ·   Молния ×" .. tostring(hero.PowerMult) .. "   ·   Победы ×" .. tostring(hero.WinMult)
            makeListRow(mentorsBody, hero.Name, detail, color, actionText, function()
                if equipped then return end
                if owned then
                    Remotes.EquipHero:FireServer(hero.Id)
                else
                    Remotes.BuyHero:FireServer(hero.Id)
                end
            end)
        end
    end
    openPanel("Mentors")
end)

addNav("❄  МИРЫ", COLORS.blue, 2, function()
    clearRows(worldsBody)
    for index, zone in ipairs(Config.Zones) do
        local unlocked = state and state.Power >= zone.Requirement
        makeListRow(worldsBody, zone.Name, "Требуется молния: " .. formatNumber(zone.Requirement) .. "  ·  Множитель тренировки ×" .. tostring(zone.Multiplier),
            unlocked and COLORS.cyan or COLORS.panelLight,
            selectedZone == index and "ВЫБРАНО" or (unlocked and "ВЫБРАТЬ" or "ЗАКРЫТО"),
            function()
                if not unlocked then
                    notice("Для этой зоны пока недостаточно молнии.")
                    return
                end
                selectedZone = index
                notice("Выбрана зона: " .. zone.Name)
                openPanel("Worlds")
            end)
    end
    openPanel("Worlds")
end)

addNav("✧  ИНВЕНТАРЬ", COLORS.green, 3, function()
    rebuildInventoryPanel()
    openPanel("Inventory")
end)

addNav("♜  ИСПЫТАНИЯ", COLORS.red, 4, function()
    clearRows(questsBody)
    local kills = state and state.TotalKills or 0
    local stage = state and state.Stage or 1
    makeListRow(questsBody, "Первое испытание", "Победи первого монстра. Прогресс: " .. math.min(kills, 1) .. " / 1", COLORS.cyan,
        kills >= 1 and "ВЫПОЛНЕНО" or "В ПРОЦЕССЕ", function() end)
    makeListRow(questsBody, "Путь ученика", "Достигни этапа 5. Текущий этап: " .. tostring(stage), COLORS.purple,
        stage >= 5 and "ВЫПОЛНЕНО" or "В ПРОЦЕССЕ", function() end)
    makeListRow(questsBody, "Коллекционер трофеев", "Получи 10 предметов. Побед: " .. tostring(kills), COLORS.gold,
        kills >= 10 and "ВЫПОЛНЕНО" or "В ПРОЦЕССЕ", function() end)
    openPanel("Quests")
end)

addNav("✧  ПИТОМЦЫ", COLORS.cyan, 5, function()
    rebuildPetsPanel()
    openPanel("Pets")
end)

addNav("⚒  КРАФТ", COLORS.purple, 6, function()
    rebuildCraftPanel()
    openPanel("Craft")
end)

addNav("✦  МАГАЗИН", COLORS.gold, 7, function()
    clearRows(shopBody)
    for passKey, pass in pairs(Config.GamePasses) do
        local available = pass.Id and pass.Id > 0
        makeListRow(shopBody, pass.Name, pass.Description .. (available and "" or "  ·  ID ещё не настроен"),
            COLORS.gold, available and "КУПИТЬ ROBUX" or "НУЖЕН ID", function()
                if not available then
                    notice("Добавь ID Game Pass в Config.luau после создания в Creator Dashboard.")
                    return
                end
                MarketplaceService:PromptGamePassPurchase(player, pass.Id)
            end)
    end
    for productKey, product in pairs(Config.DeveloperProducts) do
        local available = product.Id and product.Id > 0
        makeListRow(shopBody, product.Name, product.Description .. (available and "" or "  ·  ID ещё не настроен"),
            COLORS.purple, available and "КУПИТЬ ROBUX" or "НУЖЕН ID", function()
                if not available then
                    notice("Добавь ID Developer Product в Config.luau после создания в Creator Dashboard.")
                    return
                end
                MarketplaceService:PromptProductPurchase(player, product.Id)
            end)
    end
    openPanel("Shop")
end)

-- Toast and animated reward card.
local toast = makeCard(root, "Toast", UDim2.fromScale(0.42, 0.065), UDim2.fromScale(0.29, 0.16), COLORS.gold)
toast.Visible = false
local toastText = makeLabel(toast, "", 14, UDim2.fromScale(0.05, 0.05), COLORS.cream, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
toastText.Size = UDim2.fromScale(0.9, 0.9)

notice = function(text)
    toastToken += 1
    local token = toastToken
    toastText.Text = tostring(text)
    toast.Visible = true
    toast.BackgroundTransparency = 0.35
    local scale = toast:FindFirstChildOfClass("UIScale") or create("UIScale", { Scale = 0.94 }, toast)
    scale.Scale = 0.94
    animate(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
    task.delay(2.6, function()
        if token == toastToken and toast.Parent then
            animate(toast, 0.18, { BackgroundTransparency = 1 })
            task.delay(0.2, function()
                if token == toastToken then toast.Visible = false; toast.BackgroundTransparency = 0.08 end
            end)
        end
    end)
end

local reward = makeCard(root, "RewardPopup", UDim2.fromScale(0.34, 0.28), UDim2.fromScale(0.33, 0.34), COLORS.gold)
reward.Visible = false
local rewardTitle = makeLabel(reward, "ПОБЕДА!", 24, UDim2.fromScale(0.08, 0.07), COLORS.gold, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
rewardTitle.Size = UDim2.fromScale(0.84, 0.18)
local rewardItem = makeLabel(reward, "Осколок инея", 20, UDim2.fromScale(0.08, 0.31), COLORS.cream, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
rewardItem.Size = UDim2.fromScale(0.84, 0.2)
local rewardDetail = makeLabel(reward, "+8 побед  ·  Обычный", 13, UDim2.fromScale(0.08, 0.54), COLORS.muted, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
rewardDetail.Size = UDim2.fromScale(0.84, 0.14)
makeButton(reward, "ПРОДОЛЖИТЬ", COLORS.green, UDim2.fromScale(0.58, 0.2), UDim2.fromScale(0.21, 0.74), function()
    reward.Visible = false
end, { TextSize = 13, ZIndex = 30 })

local function showReward(data, titleText)
    rewardToken += 1
    local token = rewardToken
    rewardTitle.Text = titleText or "НАГРАДА"
    rewardItem.Text = tostring(data.ItemName or "Предмет")
    rewardDetail.Text = data.Detail or ("+%s побед  ·  %s  ·  ×%s"):format(formatNumber(data.Wins or 0), tostring(data.Rarity or ""), tostring(data.Quantity or 1))
    local accent = data.ItemColor or COLORS.gold
    local outline = reward:FindFirstChildOfClass("UIStroke")
    if outline then outline.Color = accent end
    reward.Visible = true
    reward.BackgroundTransparency = 0.2
    local scale = reward:FindFirstChildOfClass("UIScale") or create("UIScale", { Scale = 0.8 }, reward)
    scale.Scale = 0.8
    animate(scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
    task.delay(5, function()
        if token == rewardToken and reward.Parent then
            animate(scale, 0.18, { Scale = 0.94 })
            task.delay(0.2, function()
                if token == rewardToken then reward.Visible = false; scale.Scale = 1 end
            end)
        end
    end)
end

-- Floating feedback text and screen pulse.
local function floatingText(text, color)
    local item = makeLabel(root, text, 22, UDim2.fromScale(0.42, 0.45), color or COLORS.gold, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
    item.Size = UDim2.fromScale(0.16, 0.06)
    item.ZIndex = 40
    animate(item, 0.62, {
        Position = UDim2.fromScale(0.42, 0.34),
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    }, Enum.EasingStyle.Quad)
    task.delay(0.7, function()
        if item.Parent then item:Destroy() end
    end)
end

local pulse = create("Frame", {
    Name = "CombatPulse",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = COLORS.red,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 45,
}, root)

local function flash(color, alpha)
    pulse.BackgroundColor3 = color
    pulse.BackgroundTransparency = 1
    animate(pulse, 0.12, { BackgroundTransparency = 1 - (alpha or 0.24) })
    task.delay(0.12, function()
        if pulse.Parent then animate(pulse, 0.32, { BackgroundTransparency = 1 }) end
    end)
end

-- Responsive layout: desktop composition is preserved; phones receive a compact, usable arrangement.
local function updateResponsiveLayout()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local mobile = viewport.X < 760

    if mobile then
        rootScale.Scale = 1
        brand.Position = UDim2.fromScale(0.02, 0.02)
        brand.Size = UDim2.fromScale(0.29, 0.075)
        stageCard.Position = UDim2.fromScale(0.33, 0.02)
        stageCard.Size = UDim2.fromScale(0.41, 0.075)
        mentorBadge.Position = UDim2.fromScale(0.76, 0.02)
        mentorBadge.Size = UDim2.fromScale(0.22, 0.075)
        navigation.Position = UDim2.fromScale(0.02, 0.20)
        navigation.Size = UDim2.fromScale(0.27, 0.46)
        resources.Position = UDim2.fromScale(0.02, 0.68)
        resources.Size = UDim2.fromScale(0.27, 0.18)
        progress.Position = UDim2.fromScale(0.31, 0.68)
        progress.Size = UDim2.fromScale(0.67, 0.14)
        actions.Position = UDim2.fromScale(0.02, 0.855)
        actions.Size = UDim2.fromScale(0.96, 0.105)
        battleCard.Position = UDim2.fromScale(0.06, 0.115)
        battleCard.Size = UDim2.fromScale(0.88, 0.105)
        for index, nav in ipairs(navButtons) do
            nav.Position = UDim2.new(0, 7, 0, 35 + (index - 1) * 43)
            nav.Size = UDim2.new(1, -14, 0, 37)
            nav.TextSize = 11
        end
        for _, child in ipairs(actions:GetChildren()) do
            if child:IsA("TextButton") then
                child.Size = UDim2.new(0.188, 0, 0.82, 0)
                child.TextSize = 10
            end
        end
        for _, panel in pairs(panels) do
            panel.Position = UDim2.fromScale(0.05, 0.15)
            panel.Size = UDim2.fromScale(0.90, 0.68)
        end
        local brandLabels = {}
        for _, child in ipairs(brand:GetChildren()) do
            if child:IsA("TextLabel") then table.insert(brandLabels, child) end
        end
        if brandLabels[1] then brandLabels[1].TextSize = 12 end
        if brandLabels[2] then brandLabels[2].TextSize = 8 end
        stageTitle.TextSize = 11
        stageHint.TextSize = 9
        mentorName.TextSize = 8
        mentorBonus.TextSize = 8
        lightningValue.TextSize = 13
        winsValue.TextSize = 11
        rebirthValue.TextSize = 9
        powerTitle.TextSize = 15
        levelTitle.TextSize = 9
    else
        rootScale.Scale = math.clamp(viewport.X / 1420, 0.84, 1.08)
        brand.Position = UDim2.fromScale(0.018, 0.025)
        brand.Size = UDim2.fromScale(0.205, 0.085)
        stageCard.Position = UDim2.fromScale(0.33, 0.025)
        stageCard.Size = UDim2.fromScale(0.34, 0.085)
        mentorBadge.Position = UDim2.fromScale(0.79, 0.025)
        mentorBadge.Size = UDim2.fromScale(0.19, 0.085)
        navigation.Position = UDim2.fromScale(0.018, 0.23)
        navigation.Size = UDim2.fromScale(0.16, 0.45)
        resources.Position = UDim2.fromScale(0.018, 0.68)
        resources.Size = UDim2.fromScale(0.19, 0.22)
        progress.Position = UDim2.fromScale(0.27, 0.69)
        progress.Size = UDim2.fromScale(0.46, 0.13)
        actions.Position = UDim2.fromScale(0.12, 0.855)
        actions.Size = UDim2.fromScale(0.76, 0.105)
        battleCard.Position = UDim2.fromScale(0.33, 0.135)
        battleCard.Size = UDim2.fromScale(0.34, 0.105)
        for index, nav in ipairs(navButtons) do
            nav.Position = UDim2.new(0, 9, 0, 38 + (index - 1) * 49)
            nav.Size = UDim2.new(1, -18, 0, 43)
            nav.TextSize = 12
        end
        local brandLabels = {}
        for _, child in ipairs(brand:GetChildren()) do
            if child:IsA("TextLabel") then table.insert(brandLabels, child) end
        end
        if brandLabels[1] then brandLabels[1].TextSize = 18 end
        if brandLabels[2] then brandLabels[2].TextSize = 10 end
        stageTitle.TextSize = 15
        stageHint.TextSize = 11
        mentorName.TextSize = 12
        mentorBonus.TextSize = 10
        lightningValue.TextSize = 17
        winsValue.TextSize = 15
        rebirthValue.TextSize = 13
        powerTitle.TextSize = 21
        levelTitle.TextSize = 12
        for _, child in ipairs(actions:GetChildren()) do
            if child:IsA("TextButton") then
                child.Size = UDim2.new(0.19, 0, 0.82, 0)
                child.TextSize = 13
            end
        end
        for _, panel in pairs(panels) do
            panel.Position = UDim2.fromScale(0.255, 0.18)
            panel.Size = UDim2.fromScale(0.49, 0.61)
        end
    end
end

updateResponsiveLayout()
local function bindViewport()
    local camera = workspace.CurrentCamera
    if camera then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
        updateResponsiveLayout()
    end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
bindViewport()

-- Local-only companion models. They are cosmetic; all bonuses are calculated by the server.
local localPetFolder = Instance.new("Folder")
localPetFolder.Name = "LocalPetCompanions"
localPetFolder.Parent = workspace
local petVisuals = {}
local petVisualSignature = ""

local function makePetPart(parent, name, size, offset, color, shape, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = CFrame.new(offset)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    if shape then part.Shape = shape end
    part.Parent = parent
    return part
end

local function createPetVisual(pet)
    local model = Instance.new("Model")
    model.Name = "Companion_" .. pet.Id
    model.Parent = localPetFolder
    local body = makePetPart(model, "Body", Vector3.new(1.65, 1.35, 1.8), Vector3.new(0, 0, 0), pet.Color, Enum.PartType.Ball)
    local head = makePetPart(model, "Head", Vector3.new(1.15, 1.1, 1.05), Vector3.new(0, 0.65, -0.55), pet.Color:Lerp(Color3.new(1, 1, 1), 0.12), Enum.PartType.Ball)
    makePetPart(model, "EyeLeft", Vector3.new(0.14, 0.18, 0.09), Vector3.new(-0.23, 0.68, -1.03), Color3.fromRGB(24, 24, 38), Enum.PartType.Ball, Enum.Material.Neon)
    makePetPart(model, "EyeRight", Vector3.new(0.14, 0.18, 0.09), Vector3.new(0.23, 0.68, -1.03), Color3.fromRGB(24, 24, 38), Enum.PartType.Ball, Enum.Material.Neon)
    makePetPart(model, "Tail", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0, 0.1, 0.95), pet.Color, Enum.PartType.Ball)
    if pet.Kind == "Fox" or pet.Kind == "Wolf" or pet.Kind == "Lynx" then
        makePetPart(model, "EarLeft", Vector3.new(0.35, 0.75, 0.35), Vector3.new(-0.35, 1.25, -0.58), pet.Color, Enum.PartType.Ball)
        makePetPart(model, "EarRight", Vector3.new(0.35, 0.75, 0.35), Vector3.new(0.35, 1.25, -0.58), pet.Color, Enum.PartType.Ball)
    elseif pet.Kind == "Owl" or pet.Kind == "Drake" then
        local leftWing = Instance.new("WedgePart")
        leftWing.Name = "LeftWing"
        leftWing.Size = Vector3.new(0.45, 1.05, 1.25)
        leftWing.CFrame = CFrame.new(-1.0, 0.1, 0.1)
        leftWing.Anchored = true
        leftWing.CanCollide = false
        leftWing.Color = pet.Color:Lerp(Color3.new(0, 0, 0), 0.15)
        leftWing.Parent = model
        local rightWing = leftWing:Clone()
        rightWing.Name = "RightWing"
        rightWing.CFrame = CFrame.new(1.0, 0.1, 0.1)
        rightWing.Parent = model
    end
    local glow = makePetPart(model, "Glow", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 0.15, 0), pet.Color, Enum.PartType.Ball, Enum.Material.Neon)
    glow.Transparency = 0.82
    model.PrimaryPart = body
    local title = Instance.new("BillboardGui")
    title.Name = "PetName"
    title.Adornee = head
    title.Size = UDim2.fromOffset(120, 24)
    title.StudsOffset = Vector3.new(0, 1.25, 0)
    title.MaxDistance = 45
    title.Parent = model
    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamBold
    text.TextSize = 11
    text.Text = pet.Name
    text.TextColor3 = COLORS.cream
    text.TextStrokeTransparency = 0.35
    text.Parent = title
    return model
end

local function updatePetVisuals()
    local equipped = state and state.EquippedPets or {}
    local signature = table.concat(equipped, "|")
    if signature == petVisualSignature then return end
    petVisualSignature = signature
    for _, child in ipairs(localPetFolder:GetChildren()) do child:Destroy() end
    table.clear(petVisuals)
    for _, petId in ipairs(equipped) do
        local pet = Config.PetById[petId]
        if pet then
            table.insert(petVisuals, createPetVisual(pet))
        end
    end
end

RunService.RenderStepped:Connect(function()
    if #petVisuals == 0 then return end
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    local now = os.clock()
    local count = #petVisuals
    for index, petModel in ipairs(petVisuals) do
        if petModel.Parent then
            local horizontal = (index - (count + 1) / 2) * 2.15
            local bob = math.sin(now * 2.5 + index * 1.4) * 0.2
            local target = rootPart.CFrame * CFrame.new(horizontal, 1.7 + bob, 3.4 + (index - 1) * 0.35)
            petModel:PivotTo(petModel:GetPivot():Lerp(target, 0.18))
        end
    end
end)

-- State refresh updates all persistent labels and progress smoothly.
local function refresh()
    if not state then return end

    lightningValue.Text = "⚡  Молния: " .. formatNumber(state.Power)
    winsValue.Text = "✦  Победы: " .. formatNumber(state.Wins)
    rebirthValue.Text = "↻  Перерождения: " .. tostring(state.Rebirths)
    powerTitle.Text = "⚡  МОЛНИЯ  " .. formatNumber(state.Power)

    local requirement = math.max(1, state.StageRequirement or 100)
    local progressRatio = math.clamp((state.Power or 0) / requirement, 0, 1)
    levelTitle.Text = ("Этап %d  ·  %s / %s  ·  %d%%"):format(
        state.Stage or 1, formatNumber(state.Power), formatNumber(requirement), math.floor(progressRatio * 100)
    )
    animate(progressFill, 0.24, { Size = UDim2.fromScale(progressRatio, 1) })

    stageTitle.Text = ("ЭТАП %d  ·  %s"):format(state.Stage or 1, Config.Zones[selectedZone] and Config.Zones[selectedZone].Name or "АКАДЕМИЯ")
    local monsterIndex = math.min(state.Stage or 1, #Config.Monsters)
    local monster = Config.Monsters[monsterIndex]
    stageHint.Text = ("Следующий противник: %s"):format(state.BattleMonster or (monster and monster.Name or "Страж"))

    mentorName.Text = "НАСТАВНИК: " .. tostring(state.HeroName or "Снежок Хранитель")
    mentorBonus.Text = ("Молния ×%.2f  ·  питомцы ×%.2f"):format(state.HeroPowerMult or 1, state.PetPowerMult or 1)

    battleCard.Visible = state.BattleActive == true
    if state.BattleActive then
        battleName.Text = "ПРОТИВНИК  ·  " .. tostring(state.BattleMonster or "")
        battleNumbers.Text = ("%s / %s HP  ·  ТЫ %s / %s"):format(formatNumber(state.BattleHealth), formatNumber(state.BattleMaxHealth), formatNumber(state.PlayerHealth), formatNumber(state.PlayerMaxHealth))
        local ratio = math.clamp((state.BattleHealth or 0) / math.max(1, state.BattleMaxHealth or 1), 0, 1)
        animate(battleFill, 0.18, { Size = UDim2.fromScale(ratio, 1) })
        fightButton.Text = "АТАКОВАТЬ"
        fightButton.BackgroundColor3 = COLORS.red
    else
        fightButton.Text = "НАЧАТЬ БОЙ"
        fightButton.BackgroundColor3 = COLORS.red
    end

    if activePanel == "Mentors" then
        -- Rebuild when owned/equipped state changes, so labels never show stale costs.
        clearRows(mentorsBody)
        for _, hero in ipairs(Config.Heroes) do
            local owned = state.Owned and state.Owned[hero.Id] == true
            local equipped = state.Equipped == hero.Id
            local detail = hero.Rarity .. "  ·  Молния ×" .. tostring(hero.PowerMult) .. "  ·  " .. hero.Ability.Name
            makeListRow(mentorsBody, hero.Name, detail, Config.RarityColors[hero.Rarity], equipped and "ЭКИПИРОВАН" or (owned and "ВЫБРАТЬ" or ("НАЙМ " .. formatNumber(hero.Cost))), function()
                if owned then Remotes.EquipHero:FireServer(hero.Id) else Remotes.BuyHero:FireServer(hero.Id) end
            end)
        end
    elseif activePanel == "Inventory" then
        rebuildInventoryPanel()
    elseif activePanel == "Pets" then
        rebuildPetsPanel()
    elseif activePanel == "Craft" then
        rebuildCraftPanel()
    end
end

Remotes.State.OnClientEvent:Connect(function(newState)
    state = newState
    if state.Zone then selectedZone = math.clamp(state.Zone, 1, #Config.Zones) end
    refresh()
    updatePetVisuals()
end)

Remotes.Notice.OnClientEvent:Connect(notice)
Remotes.PassChanged.OnClientEvent:Connect(function()
    Remotes.RequestState:FireServer()
end)

local function pulseAtPlayer(color, maxSize)
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local pulsePart = Instance.new("Part")
    pulsePart.Name = "LocalMagicPulse"
    pulsePart.Shape = Enum.PartType.Ball
    pulsePart.Size = Vector3.new(2, 2, 2)
    pulsePart.CFrame = rootPart.CFrame
    pulsePart.Anchored = true
    pulsePart.CanCollide = false
    pulsePart.CanTouch = false
    pulsePart.Material = Enum.Material.Neon
    pulsePart.Color = color
    pulsePart.Transparency = 0.42
    pulsePart.Parent = workspace

    local glow = Instance.new("PointLight")
    glow.Color = color
    glow.Range = 12
    glow.Brightness = 1.5
    glow.Parent = pulsePart

    local tween = TweenService:Create(pulsePart, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(maxSize or 8, maxSize or 8, maxSize or 8),
        Transparency = 1,
    })
    tween:Play()
    tween.Completed:Connect(function()
        if pulsePart.Parent then pulsePart:Destroy() end
    end)
end

local function playArcaneBolt()
    local camera = workspace.CurrentCamera
    local activeFolder = workspace:FindFirstChild("ActiveMonsters")
    local monster = activeFolder and activeFolder:FindFirstChild("AcademyMonster")
    local target = monster and (monster:FindFirstChild("Core") or monster.PrimaryPart)
    if not camera or not target then return end

    local origin = camera.CFrame.Position + camera.CFrame.LookVector * 3 + camera.CFrame.RightVector * 0.65 - camera.CFrame.UpVector * 0.45
    local bolt = Instance.new("Part")
    bolt.Name = "LocalArcaneBolt"
    bolt.Shape = Enum.PartType.Ball
    bolt.Size = Vector3.new(0.7, 0.7, 0.7)
    bolt.Material = Enum.Material.Neon
    bolt.Color = COLORS.gold
    bolt.Anchored = true
    bolt.CanCollide = false
    bolt.CanTouch = false
    bolt.CFrame = CFrame.new(origin)
    bolt.Parent = workspace
    local glow = Instance.new("PointLight")
    glow.Color = COLORS.gold
    glow.Range = 10
    glow.Brightness = 2
    glow.Parent = bolt

    local distance = (target.Position - origin).Magnitude
    local duration = math.clamp(distance / 110, 0.18, 0.46)
    local tween = TweenService:Create(bolt, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
        Position = target.Position,
        Size = Vector3.new(1.3, 1.3, 1.3),
    })
    tween:Play()
    tween.Completed:Connect(function()
        if bolt.Parent then bolt:Destroy() end
    end)
end

Remotes.CombatFX.OnClientEvent:Connect(function(data)
    if type(data) ~= "table" then return end
    if data.Kind == "Train" then
        pulseAtPlayer(COLORS.gold, 5)
        floatingText("+" .. formatNumber(data.Amount) .. " МОЛНИИ", COLORS.gold)
    elseif data.Kind == "Started" then
        notice("Начался бой: " .. tostring(data.Monster))
        flash(COLORS.purple, 0.12)
    elseif data.Kind == "PlayerHit" then
        playArcaneBolt()
        floatingText("-" .. formatNumber(data.Damage), COLORS.gold)
        flash(COLORS.gold, 0.07)
    elseif data.Kind == "EnemyHit" then
        floatingText("-" .. formatNumber(data.Damage) .. " ЗДОРОВЬЯ", COLORS.red)
        flash(COLORS.red, 0.18)
    elseif data.Kind == "Victory" then
        showReward(data, "ПОБЕДА!")
        flash(COLORS.gold, 0.2)
    elseif data.Kind == "EggReveal" then
        showReward({
            ItemName = data.PetName,
            Rarity = data.Rarity,
            Quantity = 1,
            ItemColor = data.PetColor,
            Detail = "Молния ×" .. tostring(data.PowerMult) .. "  ·  Новый питомец в коллекции",
        }, "НОВЫЙ ПИТОМЕЦ")
        flash(COLORS.purple, 0.24)
    elseif data.Kind == "Crafted" then
        showReward({
            ItemName = data.ItemName,
            Rarity = data.Rarity,
            Quantity = 1,
            ItemColor = data.ItemColor,
            Detail = "Предмет создан и добавлен в инвентарь",
        }, "СОЗДАНО")
    elseif data.Kind == "Defeat" then
        notice("Противник оказался сильнее. Попробуй ещё раз.")
        flash(COLORS.red, 0.24)
    elseif data.Kind == "Ability" then
        pulseAtPlayer(COLORS.purple, 11)
        floatingText(tostring(data.Name), COLORS.cyan)
        flash(COLORS.purple, 0.12)
    elseif data.Kind == "Rebirth" then
        floatingText("ВОЗРОЖДЕНИЕ", COLORS.purple)
        flash(COLORS.purple, 0.2)
    end
end)

-- Auto training uses the server cooldown and never spams requests faster than allowed.
task.spawn(function()
    while gui.Parent do
        if autoTrain then
            Remotes.Train:FireServer(selectedZone)
        end
        task.wait(Config.TrainCooldown + 0.08)
    end
end)

Remotes.RequestState:FireServer()
