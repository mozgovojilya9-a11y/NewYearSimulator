-- Player data persistence. Store name and key format are kept compatible with v1.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local store = DataStoreService:GetDataStore("NewYearSim_v1")

local DEFAULT = {
    Power = 0,
    Wins = 0,
    Rebirths = 0,
    Stage = 1,
    Zone = 1,
    OwnedHeroes = { snowman = true },
    EquippedHero = "snowman",
    Inventory = {},
    OwnedPets = {},
    EquippedPets = {},
    Equipment = { Weapon = nil, Armor = nil },
    GamePasses = {},
    ProcessedReceipts = {},
    PremiumBoosts = {},
    TotalKills = 0,
    HighestStage = 1,
}

local DataService = {}
local cache = {}
local saving = {}
local started = false

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function mergeDefaults(saved)
    local data = type(saved) == "table" and saved or {}
    for key, value in pairs(DEFAULT) do
        if data[key] == nil then
            data[key] = deepCopy(value)
        end
    end

    if type(data.OwnedHeroes) ~= "table" then
        data.OwnedHeroes = { snowman = true }
    end
    if type(data.Inventory) ~= "table" then
        data.Inventory = {}
    end
    if type(data.OwnedPets) ~= "table" then
        data.OwnedPets = {}
    end
    if type(data.EquippedPets) ~= "table" then
        data.EquippedPets = {}
    end
    if type(data.Equipment) ~= "table" then
        data.Equipment = { Weapon = nil, Armor = nil }
    end
    if type(data.GamePasses) ~= "table" then
        data.GamePasses = {}
    end
    if type(data.ProcessedReceipts) ~= "table" then
        data.ProcessedReceipts = {}
    end
    if type(data.PremiumBoosts) ~= "table" then
        data.PremiumBoosts = {}
    end

    -- Preserve every saved hero ID. Only repair an invalid equipped ID.
    if type(data.EquippedHero) ~= "string" or not Config.HeroById[data.EquippedHero] then
        data.EquippedHero = data.OwnedHeroes.snowman and "snowman" or "snowman"
        data.OwnedHeroes.snowman = true
    end
    data.Power = math.max(0, tonumber(data.Power) or 0)
    data.Wins = math.max(0, tonumber(data.Wins) or 0)
    data.Rebirths = math.max(0, math.floor(tonumber(data.Rebirths) or 0))
    data.Stage = math.max(1, math.floor(tonumber(data.Stage) or 1))
    data.Zone = math.clamp(math.floor(tonumber(data.Zone) or 1), 1, #Config.Zones)
    data.TotalKills = math.max(0, math.floor(tonumber(data.TotalKills) or 0))
    data.HighestStage = math.max(data.Stage, math.floor(tonumber(data.HighestStage) or data.Stage))

    local equippedPets = {}
    local seenPets = {}
    for _, petId in ipairs(data.EquippedPets) do
        if type(petId) == "string" and Config.PetById[petId] and (tonumber(data.OwnedPets[petId]) or 0) > 0 and not seenPets[petId] then
            table.insert(equippedPets, petId)
            seenPets[petId] = true
        end
    end
    data.EquippedPets = equippedPets
    data.Equipment.Weapon = type(data.Equipment.Weapon) == "string" and Config.Items[data.Equipment.Weapon] and data.Equipment.Weapon or nil
    data.Equipment.Armor = type(data.Equipment.Armor) == "string" and Config.Items[data.Equipment.Armor] and data.Equipment.Armor or nil
    return data
end

local function withRetry(callback, attempts)
    local lastError = nil
    for attempt = 1, attempts do
        local ok, result = pcall(callback)
        if ok then
            return true, result
        end
        lastError = result
        warn(("[DataService] attempt %d/%d failed: %s"):format(attempt, attempts, tostring(result)))
        task.wait(attempt)
    end
    return false, lastError
end

function DataService.Load(player)
    local key = "player_" .. player.UserId
    local ok, saved = withRetry(function()
        return store:GetAsync(key)
    end, 3)

    if not ok then
        player:Kick("Не удалось загрузить сохранение. Попробуйте войти ещё раз.")
        return nil
    end

    if not player.Parent then
        return nil
    end

    local data = mergeDefaults(deepCopy(saved))
    cache[player] = data
    return data
end

function DataService.Get(player)
    return cache[player]
end

function DataService.Save(player)
    local data = cache[player]
    if not data then
        return false
    end
    local deadline = os.clock() + 6
    while saving[player] and cache[player] and os.clock() < deadline do
        task.wait(0.1)
    end
    if saving[player] or not cache[player] then
        return false
    end

    saving[player] = true
    local snapshot = deepCopy(data)
    local key = "player_" .. player.UserId
    local ok = withRetry(function()
        return store:UpdateAsync(key, function()
            return snapshot
        end)
    end, 3)
    saving[player] = nil
    return ok
end

function DataService.Release(player)
    DataService.Save(player)
    cache[player] = nil
    saving[player] = nil
end

function DataService.Start()
    if started then
        return
    end
    started = true

    task.spawn(function()
        while true do
            task.wait(Config.SaveInterval)
            for player in pairs(cache) do
                task.spawn(DataService.Save, player)
            end
        end
    end)

    game:BindToClose(function()
        local pending = 0
        for player in pairs(cache) do
            pending += 1
            task.spawn(function()
                DataService.Save(player)
                pending -= 1
            end)
        end
        local deadline = os.clock() + 25
        while pending > 0 and os.clock() < deadline do
            task.wait(0.1)
        end
    end)
end

return DataService
