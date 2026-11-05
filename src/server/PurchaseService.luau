-- Secure MarketplaceService receipt handling. Product IDs remain disabled until configured.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PurchaseService = {}
local started = false

local function findPassById(passId)
    for key, pass in pairs(Config.GamePasses) do
        if pass.Id and pass.Id > 0 and pass.Id == passId then
            return key
        end
    end
    return nil
end

function PurchaseService.RefreshPasses(player, dataService)
    local data = dataService.Get(player)
    if not data then
        return false
    end

    data.GamePasses = data.GamePasses or {}
    local changed = false
    for key, pass in pairs(Config.GamePasses) do
        if pass.Id and pass.Id > 0 then
            local ok, owns = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
            end)
            -- Keep the previous entitlement when Roblox temporarily fails to answer.
            if ok and data.GamePasses[key] ~= (owns == true) then
                data.GamePasses[key] = owns == true
                changed = true
            end
        end
    end

    if changed then
        dataService.Save(player)
    end
    return true
end

local function grantProduct(data, product)
    local reward = product.Reward
    if type(reward) ~= "table" then
        return false
    end

    if reward.Type == "Wins" then
        data.Wins += math.max(0, math.floor(tonumber(reward.Amount) or 0))
        return true
    elseif reward.Type == "LightningBoost" then
        data.PremiumBoosts = data.PremiumBoosts or {}
        table.insert(data.PremiumBoosts, {
            Multiplier = math.clamp(tonumber(reward.Multiplier) or 1, 1, 10),
            Expires = os.time() + math.max(1, math.floor(tonumber(reward.Duration) or 60)),
        })
        return true
    elseif reward.Type == "Pet" then
        local petId = reward.PetId
        if type(petId) ~= "string" or not Config.PetById[petId] then
            return false
        end
        data.OwnedPets = data.OwnedPets or {}
        data.EquippedPets = data.EquippedPets or {}
        data.OwnedPets[petId] = (tonumber(data.OwnedPets[petId]) or 0) + 1
        local slotLimit = Config.PetSlots + (data.GamePasses and data.GamePasses.ExtraPetSlot == true and 1 or 0)
        if not table.find(data.EquippedPets, petId) and #data.EquippedPets < slotLimit then
            table.insert(data.EquippedPets, petId)
        end
        return true
    end
    return false
end

function PurchaseService.Start(dataService)
    if started then
        return
    end
    started = true

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
        if not purchased then return end
        local key = findPassById(passId)
        if not key then return end
        local data = dataService.Get(player)
        if not data then return end
        data.GamePasses = data.GamePasses or {}
        data.GamePasses[key] = true
        dataService.Save(player)
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local refresh = remotes and remotes:FindFirstChild("PassChanged")
        if refresh then refresh:FireClient(player) end
    end)

    MarketplaceService.ProcessReceipt = function(receiptInfo)
        local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
        if not player then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local entry = Config.DeveloperProductById[receiptInfo.ProductId]
        if not entry then
            warn(("[PurchaseService] Product ID %s is not configured. Receipt will remain pending."):format(tostring(receiptInfo.ProductId)))
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local receiptKey = tostring(receiptInfo.PurchaseId)
        local granted = dataService.ApplyReceipt(player, receiptKey, function(data)
            return grantProduct(data, entry.Product)
        end)

        if not granted then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local changed = remotes and remotes:FindFirstChild("PurchaseChanged")
        if changed then changed:FireClient(player) end
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
end

return PurchaseService
