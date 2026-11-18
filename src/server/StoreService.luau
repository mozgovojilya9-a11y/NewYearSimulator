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
local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local LootService = require(script.Parent.LootService)
local PlayerState = require(script.Parent.PlayerState)
local StatService = require(script.Parent.StatService)
local Remotes = require(script.Parent.Remotes)

local StoreService = {}

local purchases = DataStoreService:GetDataStore(Config.Store.PurchaseStore)

-- Gives a product to a loaded player. Returns a message or nil on failure.
local function grant(player, product): string?
	local data = DataService.Get(player)
	if not data or not PlayerState.IsReady(player) then
		return nil
	end
	if product.Kind == "Credits" then
		local amount = PlayerState.AddCredits(player, product.Amount)
		return ("+%s нано-кредитов!"):format(Format.Number(amount))
	elseif product.Kind == "Crystals" then
		local amount = PlayerState.AddCrystals(player, product.Amount)
		return Config.Crystals.Texts.Got:format(amount) .. "!"
	elseif product.Kind == "ClassChange" then
		return require(script.Parent.ClassService).GrantPaidChange(player)
	elseif product.Kind == "Boost" then
		PlayerState.AddBoost(player, product.Boost, product.Minutes)
		return product.Name .. " активирован!"
	elseif product.Kind == "WheelSkip" then
		data.WheelLast = 0
		player:SetAttribute("RewardReady", true)
		return "Колесо удачи можно крутить!"
	elseif product.Kind == "Chest" then
		-- gear container: Rolls items from the Boss table of the gate rank
		local names = {}
		local level = 5
		for room, rank in ipairs(Config.Gates.RankByRoom) do
			if rank == product.Rank then
				level = room * Config.Items.LevelPerRoom
			end
		end
		for i = 1, product.Rolls do
			local rarityId = LootService.RollRarity(player, product.Rank, "Boss", if i == 1 then Config.Loot.BossMinRarity[product.Rank] else nil)
			local view = ItemService.Give(player, ItemService.Generate(player, level, rarityId), { Force = true, NoSync = true })
			if view then
				table.insert(names, ("%s (%s)"):format(view.Name, Config.Rarity[view.Rarity].Name))
			end
		end
		PlayerState.Sync(player)
		return product.Name .. ": " .. table.concat(names, ", ")
	elseif product.Kind == "Weapon" then
		local weapon = Config.ItemById.Weapon[product.Item]
		if not weapon then
			return nil
		end
		for _, item in pairs(data.Items) do
			if item.B == weapon.Id then
				-- already owned: give credits instead so the purchase is never wasted
				local amount = PlayerState.AddCredits(player, Config.Store.DuplicateCreditsPerRobux * product.Price)
				return ("%s уже есть: +%s нано-кредитов"):format(weapon.Name, Format.Number(amount))
			end
		end
		ItemService.Give(player, Items.FromCatalog("W", weapon), { Force = true, Equip = true })
		return "Получено: " .. weapon.Name .. "!"
	elseif product.Kind == "ArmorSet" then
		local owned = {}
		for _, item in pairs(data.Items) do
			owned[item.B] = true
		end
		local got = false
		for _, piece in ipairs(Config.Armor) do
			if piece.Set == product.Item and not owned[piece.Id] then
				got = true
				ItemService.Give(player, Items.FromCatalog("A", piece), { Force = true, Equip = true, NoSync = true })
			end
		end
		PlayerState.Sync(player)
		if not got then
			local amount = PlayerState.AddCredits(player, Config.Store.DuplicateCreditsPerRobux * product.Price)
			return ("Сет уже есть: +%s нано-кредитов"):format(Format.Number(amount))
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
	label.Text = "VIP"
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
