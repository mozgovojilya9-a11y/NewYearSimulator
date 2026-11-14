--[[
	StoreService.luau
	Robux purchases.

	Game passes: ownership is cached by Passes (UserOwnsGamePassAsync on
	join + PromptGamePassPurchaseFinished for instant delivery).

	Developer products: MarketplaceService.ProcessReceipt, idempotent:
	every PurchaseId is recorded in the DataStore Config.Store.PurchaseStore
	(UpdateAsync). A receipt that is already recorded returns
	PurchaseGranted without giving anything again; the reward is given
	only to a loaded, present player and the player's data is saved right
	after, otherwise Roblox is told NotProcessedYet and retries later.
]]

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)

local StoreService = {}

local purchases = DataStoreService:GetDataStore(Config.Store.PurchaseStore)

-- Random materials of a biome; loot luck applies to Rare+.
local function chestRewards(biome: number, rolls: number, luck: number)
	local byRarity = {}
	for _, material in ipairs(Config.Materials) do
		if material.Biome == biome then
			local index = Config.Rarity[material.Rarity].Index
			byRarity[index] = byRarity[index] or {}
			table.insert(byRarity[index], material.Id)
		end
	end
	local luckFrom = Config.Rarity[Config.Loot.LuckFrom].Index
	local result = {}
	for _ = 1, rolls do
		local total = 0
		local weights = {}
		for index, rarity in ipairs(Config.Rarities) do
			local weight = if byRarity[index] then rarity.Chance * (if index >= luckFrom then luck else 1) else 0
			weights[index] = weight
			total += weight
		end
		local roll = math.random() * total
		for index, weight in ipairs(weights) do
			roll -= weight
			if roll <= 0 and weight > 0 then
				local list = byRarity[index]
				local id = list[math.random(#list)]
				result[id] = (result[id] or 0) + 1
				break
			end
		end
	end
	return result
end

-- Gives a product to a loaded player. Returns a message or nil on failure.
local function grant(player, product): string?
	local data = DataService.Get(player)
	if not data or not PlayerState.IsReady(player) then
		return nil
	end
	if product.Kind == "Aura" then
		local amount = math.floor(product.Amount * (1 + data.RoomReached / 2))
		PlayerState.SetAura(player, PlayerState.GetAura(player) + amount)
		return ("+%s Ауры!"):format(Format.Number(amount))
	elseif product.Kind == "Boost" then
		PlayerState.AddBoost(player, product.Boost, product.Minutes)
		return product.Name .. " активирован!"
	elseif product.Kind == "WheelSkip" then
		data.WheelLast = 0
		player:SetAttribute("RewardReady", true)
		return "Колесо удачи можно крутить!"
	elseif product.Kind == "Chest" then
		local rewards = chestRewards(product.Biome, product.Rolls, product.Luck * PlayerState.LootLuck(player))
		local parts = {}
		for materialId, count in pairs(rewards) do
			PlayerState.AddMaterial(player, materialId, count)
			table.insert(parts, ("%s x%d"):format(Config.MaterialById[materialId].Name, count))
		end
		return product.Name .. ": " .. table.concat(parts, ", ")
	elseif product.Kind == "Weapon" then
		local weapon = Config.ItemById.Weapon[product.Item]
		if not weapon then
			return nil
		end
		if data.OwnedWeapons[weapon.Id] then
			-- already owned: give Aura instead so the purchase is never wasted
			local amount = 5000 * product.Price
			PlayerState.SetAura(player, PlayerState.GetAura(player) + amount)
			return ("%s уже есть: +%s Ауры"):format(weapon.Name, Format.Number(amount))
		end
		data.OwnedWeapons[weapon.Id] = true
		data.EquippedWeapon = weapon.Id
		PlayerState.Sync(player)
		return "Получено: " .. weapon.Name .. "!"
	elseif product.Kind == "ArmorSet" then
		local got = false
		for _, piece in ipairs(Config.Armor) do
			if piece.Set == product.Item then
				if not data.OwnedArmor[piece.Id] then
					got = true
				end
				data.OwnedArmor[piece.Id] = true
				data.EquippedArmor[piece.Slot] = piece.Id
			end
		end
		PlayerState.Sync(player)
		if not got then
			local amount = 5000 * product.Price
			PlayerState.SetAura(player, PlayerState.GetAura(player) + amount)
			return ("Сет уже есть: +%s Ауры"):format(Format.Number(amount))
		end
		return "Получено: " .. Config.ArmorSets[product.Item].Name .. "!"
	end
	return nil
end

local function processReceipt(receipt)
	local product = Config.ProductById[receipt.ProductId]
	if not product then
		warn("[StoreService] unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = tostring(receipt.PurchaseId)

	-- Already granted earlier (server crashed after granting, or a retry)?
	local ok, done = pcall(purchases.GetAsync, purchases, key)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if done then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted on the next join
	end
	local message = grant(player, product)
	if not message then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Mark the receipt; UpdateAsync makes a parallel duplicate harmless.
	local marked = pcall(purchases.UpdateAsync, purchases, key, function(old)
		if old then
			return nil
		end
		return { UserId = receipt.PlayerId, Product = product.Key, Time = os.time() }
	end)
	task.spawn(DataService.Save, player)
	if not marked then
		warn("[StoreService] could not record purchase " .. key)
	end
	Remotes.Get("StoreNotify"):FireClient(player, message)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- VIP tag over the head of every VIP player (everyone sees it).
local function vipTag(player, character)
	local head = character:WaitForChild("Head", 10)
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.fromOffset(70, 26)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Config.Theme.PanelDark
	label.Font = Config.Theme.Font
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Gold
	label.Text = "👑 VIP"
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

local function refreshVip(player)
	local has = string.find("," .. (player:GetAttribute("Passes") or "") .. ",", ",VIP,", 1, true) ~= nil
	if has and player.Character then
		task.spawn(vipTag, player, player.Character)
	end
end

function StoreService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	local function onPlayer(player)
		player:GetAttributeChangedSignal("Passes"):Connect(function()
			refreshVip(player)
		end)
		player.CharacterAdded:Connect(function()
			refreshVip(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return StoreService
