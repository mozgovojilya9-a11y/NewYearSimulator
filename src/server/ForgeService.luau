--[[
	ForgeService.luau
	Кузница (Фабрикатор): everything is paid with credits and Нано-ядра,
	numbers and chances in Config.Forge / Shared.Items.

	Forge:InvokeServer(action, uid, arg) -> ok, message, extra
	  ("Enhance", uid)        +1 (up to +15). From +10 it can fail: the
	                          item stays as it is, the cost is spent and
	                          the next try on it gets +Pity chance.
	                          extra = { Success, Enhance }
	  ("Ascend", uid)         rarity one step up; consumes one more item
	                          of the same base (the weakest spare one)
	  ("Reforge", uid, index) rerolls bonus prop `index`
	Salvage lives in ItemService (the inventory uses it too).

	Every action plays the forge in the world for everyone nearby: the
	hearth flares, the hammer strikes, sparks and a flash in the color of
	the result (rarity color, gold for a successful enhance, red for a
	failed one).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.GameEvents)
local ItemService = require(script.Parent.ItemService)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local F = Config.Forge
local T = F.Texts

local ForgeService = {}

local forge -- hub Forge model
local rng = Random.new()

-- World effect seen by everyone near the forge.
local function flare(color: Color3)
	if not forge then
		return
	end
	local hearth = forge:FindFirstChild("Hearth")
	local anvil = forge:FindFirstChild("Anvil")
	if hearth then
		local glow = hearth:FindFirstChild("Glow")
		local fire = hearth:FindFirstChild("Fire")
		local sparks = hearth:FindFirstChild("Sparks")
		if glow then
			local base = glow.Color
			glow.Brightness = 6
			glow.Color = color
			TweenService:Create(glow, TweenInfo.new(F.AnimationSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 1.8, Color = base }):Play()
		end
		if fire then
			fire.Size = 14
			TweenService:Create(fire, TweenInfo.new(F.AnimationSeconds), { Size = 5 }):Play()
		end
		if sparks then
			sparks:Emit(40)
		end
	end
	local anvilSparks = anvil and anvil:FindFirstChild("Sparks")
	if anvilSparks then
		task.spawn(function()
			for i = 1, F.Strikes do
				if i == F.Strikes then
					anvilSparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
				end
				anvilSparks:Emit(25)
				task.wait(F.AnimationSeconds / (F.Strikes + 1))
			end
			anvilSparks.Color = ColorSequence.new(Config.Nano.Gold, Color3.new(1, 1, 1))
		end)
	end
end

local function pay(player, credits: number, cores: number): (boolean, string?)
	if PlayerState.GetCredits(player) < credits then
		return false, T.NoCredits
	end
	if PlayerState.GetCores(player) < cores then
		return false, T.NoCores
	end
	PlayerState.SpendCredits(player, credits)
	PlayerState.SpendCores(player, cores)
	return true, nil
end

local function enhance(player, data, item)
	if (item.E or 0) >= F.MaxEnhance then
		return false, T.Max
	end
	local credits, cores = Items.EnhanceCost(item)
	local ok, reason = pay(player, credits, cores)
	if not ok then
		return false, reason
	end
	local chance = Items.EnhanceChance(item)
	local success = rng:NextNumber() < chance
	if success then
		item.E = (item.E or 0) + 1
		item.F = nil
		GameEvents.Fire(player, "Enhance", 1)
	else
		item.F = (item.F or 0) + 1
	end
	PlayerState.Sync(player)
	flare(if success then Config.Nano.Gold else Config.Theme.Red)
	local view = Items.Resolve(item)
	return success, if success then T.Success:format(view.Name) else T.Fail, { Success = success, Enhance = item.E or 0 }
end

-- The spare item an ascend consumes: same base, not worn / locked /
-- starter, the weakest one.
function ForgeService.Twin(data, item)
	local best
	for uid, other in pairs(data.Items) do
		if uid ~= item.U and other.B == item.B and ItemService.CanSalvage(data, other) then
			if not best or Items.Score(other) < Items.Score(best) then
				best = other
			end
		end
	end
	return best
end

local function ascend(player, data, item)
	local nextRarity = Items.NextRarity(item.R)
	local credits, cores = Items.AscendCost(item)
	if not nextRarity or not credits then
		return false, T.MaxRarity
	end
	local twin = ForgeService.Twin(data, item)
	if not twin then
		return false, T.NoTwin:format(Items.Base(item).Name)
	end
	local ok, reason = pay(player, credits, cores)
	if not ok then
		return false, reason
	end
	data.Items[twin.U] = nil
	item.R = nextRarity
	Items.FillProps(rng, item, false)
	PlayerState.Sync(player)
	local rarity = Config.Rarity[nextRarity]
	flare(rarity.Color)
	return true, T.Ascended:format(Items.Base(item).Name, rarity.Name)
end

local function reforge(player, data, item, index)
	local props = item.P
	if type(props) ~= "table" or #props == 0 then
		return false, T.NoProps
	end
	if type(index) ~= "number" or not props[index] then
		return false, "Выбери свойство"
	end
	local cost = Items.ReforgeCost(item)
	if not PlayerState.SpendCredits(player, cost) then
		return false, T.NoCredits
	end
	-- a different stat than the ones the item already has
	local have = {}
	for _, prop in ipairs(props) do
		have[prop.S] = true
	end
	local prop = Items.RollProp(rng, item.R, have)
	if not prop then
		return false, "Неверный запрос"
	end
	props[index] = prop
	PlayerState.Sync(player)
	flare(Config.Nano.Cyan)
	return true, T.Reforged:format(Items.PropText(prop))
end

function ForgeService.Init(hub)
	forge = hub.Forge
	local allow = RateLimit.new(0.25)
	Remotes.Get("Forge").OnServerInvoke = function(player, action, uid, arg)
		local data = DataService.Get(player)
		if not allow(player) or not data or not PlayerState.IsReady(player) then
			return false, "Подожди секунду"
		end
		local item = type(uid) == "string" and data.Items[uid]
		if not item then
			return false, "Нет такого предмета"
		end
		if action == "Enhance" then
			return enhance(player, data, item)
		elseif action == "Ascend" then
			return ascend(player, data, item)
		elseif action == "Reforge" then
			return reforge(player, data, item, arg)
		end
		return false, "Неверный запрос"
	end
	local _ = Format
end

return ForgeService
