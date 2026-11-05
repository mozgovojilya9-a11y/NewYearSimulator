-- Authoritative server gameplay for the Winter Academy vertical slice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(ServerScriptService.DataService)

DataService.Start()

local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remoteFolder then
    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = "Remotes"
    remoteFolder.Parent = ReplicatedStorage
end

local function getRemote(name)
    local remote = remoteFolder:FindFirstChild(name)
    if remote and not remote:IsA("RemoteEvent") then
        remote:Destroy()
        remote = nil
    end
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remoteFolder
    end
    return remote
end

local R = {}
for _, name in ipairs({
    "RequestState", "Train", "Fight", "Attack", "Rebirth",
    "BuyHero", "EquipHero", "UseAbility", "SellItem",
    "State", "Notice", "CombatFX",
}) do
    R[name] = getRemote(name)
end

local initialized = {}
local lastTrain = {}
local lastAbility = {}
local buffs = {}
local battles = {}
local activeMonsterModels = Workspace:FindFirstChild("ActiveMonsters")
if not activeMonsterModels then
    activeMonsterModels = Instance.new("Folder")
    activeMonsterModels.Name = "ActiveMonsters"
    activeMonsterModels.Parent = Workspace
end

local function notice(player, text)
    R.Notice:FireClient(player, text)
end

local function equippedHero(data)
    return Config.HeroById[data.EquippedHero] or Config.HeroById.snowman
end

local function stageRequirement(stage)
    return math.floor(Config.Stages.BaseRequirement * Config.Stages.Growth ^ math.max(0, stage - 1))
end

local function rebirthCost(rebirths)
    return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths)
end

local function rebirthMultiplier(data)
    return 1 + data.Rebirths * Config.Rebirth.BonusPerRebirth
end

local function buffMultiplier(player, key)
    local row = buffs[player] and buffs[player][key]
    if row and os.clock() < row.Expires then
        return row.Multiplier
    end
    return 1
end

local function getHumanoid(player)
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function cloneDictionary(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function pushState(player)
    local data = DataService.Get(player)
    if not data then
        return
    end

    local stats = player:FindFirstChild("leaderstats")
    if stats then
        local powerValue = stats:FindFirstChild("Power")
        local winsValue = stats:FindFirstChild("Wins")
        local rebirthValue = stats:FindFirstChild("Rebirths")
        if powerValue then powerValue.Value = math.floor(data.Power) end
        if winsValue then winsValue.Value = data.Wins end
        if rebirthValue then rebirthValue.Value = data.Rebirths end
    end

    local battle = battles[player]
    local hero = equippedHero(data)
    local humanoid = getHumanoid(player)
    R.State:FireClient(player, {
        Power = data.Power,
        Wins = data.Wins,
        Rebirths = data.Rebirths,
        Stage = data.Stage,
        Zone = data.Zone,
        Owned = cloneDictionary(data.OwnedHeroes),
        Equipped = data.EquippedHero,
        Inventory = cloneDictionary(data.Inventory),
        TotalKills = data.TotalKills,
        HighestStage = data.HighestStage,
        StageRequirement = stageRequirement(data.Stage),
        RebirthCost = rebirthCost(data.Rebirths),
        HeroPowerMult = hero.PowerMult,
        HeroWinMult = hero.WinMult,
        HeroName = hero.Name,
        BattleActive = battle ~= nil,
        BattleMonster = battle and battle.Name or nil,
        BattleHealth = battle and battle.Health or 0,
        BattleMaxHealth = battle and battle.MaxHealth or 0,
        PlayerHealth = humanoid and humanoid.Health or 100,
        PlayerMaxHealth = humanoid and humanoid.MaxHealth or 100,
    })
end

local function withData(handler)
    return function(player, ...)
        local data = DataService.Get(player)
        if data then
            handler(player, data, ...)
        end
    end
end

local function makePart(parent, name, size, cf, color, material, shape)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cf
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    if shape then
        part.Shape = shape
    end
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function monsterStats(stage)
    local index = math.min(stage, #Config.Monsters)
    local base = Config.Monsters[index]
    local extraStages = math.max(0, stage - index)
    local growth = Config.Combat.MonsterHealthGrowth ^ extraStages
    return {
        Id = base.Id,
        Name = extraStages > 0 and ("Древний " .. base.Name) or base.Name,
        Rarity = base.Rarity,
        Health = math.floor(base.Health * growth),
        Damage = math.floor(base.Damage * (Config.Combat.MonsterDamageGrowth ^ extraStages)),
        Reward = math.floor(base.Reward * (Config.Combat.RewardWinsGrowth ^ extraStages)),
        Color = base.Color,
    }
end

local function createMonsterModel(monster)
    local model = Instance.new("Model")
    model.Name = "AcademyMonster"
    model.Parent = activeMonsterModels

    local core = makePart(model, "Core", Vector3.new(5.3, 6.2, 3.8), CFrame.new(0, 4.2, 8), monster.Color, Enum.Material.Neon)
    core.Shape = Enum.PartType.Ball
    local armor = makePart(model, "RuneArmor", Vector3.new(6.4, 4.2, 4.4), core.CFrame * CFrame.new(0, -0.4, 0), Color3.fromRGB(35, 34, 65), Enum.Material.Slate)
    local head = makePart(model, "Mask", Vector3.new(4.3, 3.4, 3.2), CFrame.new(0, 8.3, 8), monster.Color:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Glass)
    head.Shape = Enum.PartType.Ball
    makePart(model, "EyeLeft", Vector3.new(0.55, 0.55, 0.25), head.CFrame * CFrame.new(-0.9, 0.2, -1.5), Color3.fromRGB(255, 221, 132), Enum.Material.Neon, Enum.PartType.Ball)
    makePart(model, "EyeRight", Vector3.new(0.55, 0.55, 0.25), head.CFrame * CFrame.new(0.9, 0.2, -1.5), Color3.fromRGB(255, 221, 132), Enum.Material.Neon, Enum.PartType.Ball)
    makePart(model, "HornLeft", Vector3.new(0.9, 2.4, 0.9), head.CFrame * CFrame.new(-1.45, 1.8, 0), Color3.fromRGB(35, 35, 65), Enum.Material.Slate, Enum.PartType.Ball)
    makePart(model, "HornRight", Vector3.new(0.9, 2.4, 0.9), head.CFrame * CFrame.new(1.45, 1.8, 0), Color3.fromRGB(35, 35, 65), Enum.Material.Slate, Enum.PartType.Ball)

    for _, side in ipairs({ -1, 1 }) do
        local arm = makePart(model, side < 0 and "LeftArm" or "RightArm", Vector3.new(1.5, 4.5, 1.5), core.CFrame * CFrame.new(side * 3.1, 0.1, 0), Color3.fromRGB(45, 43, 76), Enum.Material.Slate)
        arm.Shape = Enum.PartType.Cylinder
        local rune = makePart(model, "ArmRune", Vector3.new(1.62, 0.18, 1.62), arm.CFrame * CFrame.new(0, 0, -0.78), monster.Color, Enum.Material.Neon)
        rune.Shape = Enum.PartType.Cylinder
    end

    local aura = makePart(model, "Aura", Vector3.new(8.5, 8.5, 8.5), core.CFrame, monster.Color, Enum.Material.ForceField, Enum.PartType.Ball)
    aura.Transparency = 0.72
    aura.CastShadow = false
    model.PrimaryPart = core

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "MonsterStatus"
    billboard.Adornee = head
    billboard.Size = UDim2.fromOffset(220, 58)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.MaxDistance = 120
    billboard.AlwaysOnTop = false
    billboard.Parent = model

    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.Size = UDim2.new(1, 0, 0, 28)
    name.Font = Enum.Font.GothamBold
    name.Text = monster.Name
    name.TextColor3 = Color3.fromRGB(255, 239, 211)
    name.TextStrokeTransparency = 0.25
    name.TextSize = 17
    name.Parent = billboard

    local track = Instance.new("Frame")
    track.Position = UDim2.fromOffset(10, 31)
    track.Size = UDim2.new(1, -20, 0, 14)
    track.BackgroundColor3 = Color3.fromRGB(38, 28, 53)
    track.BorderSizePixel = 0
    track.Parent = billboard
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = Color3.fromRGB(255, 94, 125)
    fill.BorderSizePixel = 0
    fill.Parent = track
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    return model, fill
end

local function updateMonsterHealth(battle)
    if not battle.Model or not battle.Model.Parent then
        return
    end
    local billboard = battle.Model:FindFirstChild("MonsterStatus")
    local track = billboard and billboard:FindFirstChildWhichIsA("Frame")
    local fill = track and track:FindFirstChild("Fill")
    if fill then
        TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromScale(math.clamp(battle.Health / battle.MaxHealth, 0, 1), 1),
        }):Play()
    end
end

local function rollDrop(stage)
    local available = {}
    local totalWeight = 0
    for _, entry in ipairs(Config.DropPools) do
        if stage >= entry.MinStage then
            local weight = entry.Weight
            if entry.Id == "ice_shard" and stage >= 3 then weight *= 0.55 end
            if entry.Id == "rune_dust" and stage >= 6 then weight *= 1.2 end
            if entry.Id == "frost_core" and stage >= 10 then weight *= 1.6 end
            if entry.Id == "shadow_essence" and stage >= 15 then weight *= 1.8 end
            totalWeight += weight
            table.insert(available, { Id = entry.Id, Weight = weight })
        end
    end

    if #available == 0 then
        return "ice_shard"
    end

    local pick = math.random() * totalWeight
    for _, entry in ipairs(available) do
        pick -= entry.Weight
        if pick <= 0 then
            return entry.Id
        end
    end
    return available[#available].Id
end

local function finishBattle(player, data, battle, victory)
    battles[player] = nil
    if battle.Model and battle.Model.Parent then
        battle.Model:Destroy()
    end

    if victory then
        local monster = battle.Monster
        local hero = equippedHero(data)
        local reward = math.max(1, math.floor(monster.Reward * hero.WinMult * buffMultiplier(player, "Wins")))
        local itemId = rollDrop(data.Stage)
        local item = Config.Items[itemId]
        data.Wins += reward
        data.TotalKills += 1
        data.Stage += 1
        data.HighestStage = math.max(data.HighestStage, data.Stage)
        data.Inventory[itemId] = (tonumber(data.Inventory[itemId]) or 0) + 1
        DataService.Save(player)

        R.CombatFX:FireClient(player, {
            Kind = "Victory",
            Monster = monster.Name,
            Wins = reward,
            ItemId = itemId,
            ItemName = item.Name,
            Rarity = item.Rarity,
            ItemColor = item.Color,
            Quantity = 1,
        })
        notice(player, ("Победа! +%s побед"):format(tostring(reward)))
    else
        R.CombatFX:FireClient(player, { Kind = "Defeat", Monster = battle.Monster.Name })
        notice(player, "Ты проиграл бой. Восстановись и попробуй снова.")
    end
    pushState(player)
end

R.RequestState.OnServerEvent:Connect(function(player)
    pushState(player)
end)

R.Train.OnServerEvent:Connect(withData(function(player, data, zoneIndex)
    if type(zoneIndex) ~= "number" then
        return
    end
    local index = math.floor(zoneIndex)
    local zone = Config.Zones[index]
    if not zone or index > #Config.Zones then
        return
    end
    if data.Power < zone.Requirement then
        return notice(player, "Зона закрыта. Требуется больше молнии.")
    end

    local now = os.clock()
    if now - (lastTrain[player] or 0) < Config.TrainCooldown then
        return
    end
    lastTrain[player] = now

    local hero = equippedHero(data)
    local amount = zone.Multiplier * hero.PowerMult * rebirthMultiplier(data) * buffMultiplier(player, "Power")
    data.Power += amount
    data.Zone = index
    pushState(player)
    R.CombatFX:FireClient(player, { Kind = "Train", Amount = amount })
end))

R.Fight.OnServerEvent:Connect(withData(function(player, data)
    if battles[player] then
        return notice(player, "Бой уже идёт. Используй кнопку «Атаковать».")
    end

    local required = math.max(0, stageRequirement(data.Stage) * 0.9)
    if data.Power < required then
        return notice(player, ("Для боя нужно %s молнии."):format(tostring(math.floor(required))))
    end

    local monster = monsterStats(data.Stage)
    local model, healthFill = createMonsterModel(monster)
    local maxHealth = monster.Health
    battles[player] = {
        Name = monster.Name,
        Monster = monster,
        Model = model,
        HealthFill = healthFill,
        Health = maxHealth,
        MaxHealth = maxHealth,
        NextPlayerAttack = 0,
        NextEnemyAttack = os.clock() + Config.Combat.EnemyAttackInterval,
        StartedAt = os.clock(),
    }

    local character = player.Character
    if character and character.Parent then
        character:PivotTo(CFrame.lookAt(Vector3.new(0, 3, 34), Vector3.new(0, 3, 8)))
    end

    R.CombatFX:FireClient(player, { Kind = "Started", Monster = monster.Name, MaxHealth = maxHealth, Stage = data.Stage })
    pushState(player)
end))

R.Attack.OnServerEvent:Connect(withData(function(player, data)
    local battle = battles[player]
    if not battle then
        return notice(player, "Сначала начни бой с противником.")
    end

    local now = os.clock()
    if now < battle.NextPlayerAttack then
        return
    end
    battle.NextPlayerAttack = now + Config.Combat.AttackCooldown

    local hero = equippedHero(data)
    local damage = math.max(
        Config.Combat.MinimumDamage,
        math.floor((Config.Combat.BaseDamage + data.Power * Config.Combat.PowerDamageScale) * hero.PowerMult * buffMultiplier(player, "Attack"))
    )
    battle.Health = math.max(0, battle.Health - damage)
    updateMonsterHealth(battle)
    R.CombatFX:FireClient(player, {
        Kind = "PlayerHit",
        Damage = damage,
        Health = battle.Health,
        MaxHealth = battle.MaxHealth,
        Monster = battle.Monster.Name,
    })

    if battle.Health <= 0 then
        finishBattle(player, data, battle, true)
        return
    end

    if now >= battle.NextEnemyAttack then
        battle.NextEnemyAttack = now + Config.Combat.EnemyAttackInterval
        local humanoid = getHumanoid(player)
        if humanoid and humanoid.Health > 0 then
            local enemyDamage = math.max(1, battle.Monster.Damage)
            humanoid:TakeDamage(enemyDamage)
            R.CombatFX:FireClient(player, { Kind = "EnemyHit", Damage = enemyDamage, PlayerHealth = humanoid.Health, PlayerMaxHealth = humanoid.MaxHealth })
            if humanoid.Health <= 0 then
                finishBattle(player, data, battle, false)
                return
            end
        end
    end
    pushState(player)
end))

R.Rebirth.OnServerEvent:Connect(withData(function(player, data)
    if battles[player] then
        return notice(player, "Нельзя переродиться во время боя.")
    end
    local cost = rebirthCost(data.Rebirths)
    if data.Power < cost then
        return notice(player, ("Для перерождения нужно %s молнии."):format(tostring(cost)))
    end
    data.Power = 0
    data.Stage = 1
    data.Zone = 1
    data.Rebirths += 1
    DataService.Save(player)
    R.CombatFX:FireClient(player, { Kind = "Rebirth" })
    notice(player, "Перерождение завершено. Постоянный множитель увеличен.")
    pushState(player)
end))

R.BuyHero.OnServerEvent:Connect(withData(function(player, data, heroId)
    if type(heroId) ~= "string" then
        return
    end
    local hero = Config.HeroById[heroId]
    if not hero or data.OwnedHeroes[heroId] then
        return
    end
    if data.Wins < hero.Cost then
        return notice(player, "Не хватает побед для найма наставника.")
    end
    data.Wins -= hero.Cost
    data.OwnedHeroes[heroId] = true
    data.EquippedHero = heroId
    DataService.Save(player)
    notice(player, hero.Name .. " теперь твой наставник!")
    pushState(player)
end))

R.EquipHero.OnServerEvent:Connect(withData(function(player, data, heroId)
    if type(heroId) ~= "string" or not Config.HeroById[heroId] or not data.OwnedHeroes[heroId] then
        return
    end
    data.EquippedHero = heroId
    DataService.Save(player)
    notice(player, "Наставник экипирован: " .. Config.HeroById[heroId].Name)
    pushState(player)
end))

R.UseAbility.OnServerEvent:Connect(withData(function(player, data)
    local hero = equippedHero(data)
    local now = os.clock()
    if now < (lastAbility[player] or 0) then
        return notice(player, "Способность ещё перезаряжается.")
    end
    lastAbility[player] = now + hero.Ability.Cooldown

    buffs[player] = buffs[player] or {}
    local boosts = hero.Ability.Boosts or { Attack = 1.8 }
    for stat, multiplier in pairs(boosts) do
        buffs[player][stat] = {
            Multiplier = multiplier,
            Expires = now + (hero.Ability.Duration or 8),
        }
    end
    R.CombatFX:FireClient(player, { Kind = "Ability", Name = hero.Ability.Name, Duration = hero.Ability.Duration or 8 })
    notice(player, hero.Ability.Name .. " активирована!")
    pushState(player)
end))

R.SellItem.OnServerEvent:Connect(withData(function(player, data, itemId, amount)
    if type(itemId) ~= "string" or type(amount) ~= "number" then
        return
    end
    local item = Config.Items[itemId]
    local quantity = math.clamp(math.floor(amount), 1, 999)
    local owned = tonumber(data.Inventory[itemId]) or 0
    if not item or owned < quantity then
        return notice(player, "Недостаточно предметов для продажи.")
    end

    data.Inventory[itemId] = owned - quantity
    if data.Inventory[itemId] <= 0 then
        data.Inventory[itemId] = nil
    end
    local payout = item.Value * quantity
    data.Wins += payout
    DataService.Save(player)
    notice(player, ("Продано: %s ×%d. +%d побед"):format(item.Name, quantity, payout))
    pushState(player)
end))

local function setupLeaderstats(player)
    local stats = player:FindFirstChild("leaderstats")
    if not stats then
        stats = Instance.new("Folder")
        stats.Name = "leaderstats"
        stats.Parent = player
    end
    for _, statName in ipairs({ "Power", "Wins", "Rebirths" }) do
        if not stats:FindFirstChild(statName) then
            local value = Instance.new("NumberValue")
            value.Name = statName
            value.Parent = stats
        end
    end
end

local function onPlayerAdded(player)
    if initialized[player] then
        return
    end
    initialized[player] = true
    setupLeaderstats(player)
    local data = DataService.Load(player)
    if data then
        pushState(player)
    else
        initialized[player] = nil
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
    local battle = battles[player]
    if battle and battle.Model and battle.Model.Parent then
        battle.Model:Destroy()
    end
    battles[player] = nil
    DataService.Release(player)
    initialized[player] = nil
    lastTrain[player] = nil
    lastAbility[player] = nil
    buffs[player] = nil
end)
