--[[
	HubService.luau
	Builds the hub and runs its logic:
	- Weapon / backpack stand prompts: buy (or equip if owned) through
	  ShopService; unique weapons are stand-only (fromStand = true).
	- The unique stand rotates through Config.Weapons[Unique] every
	  Config.Hub.StandRotationMinutes with an honest countdown on its sign.
	- Trainers: which platform a player stands on, whether it is
	  unlocked (Config.Hub.TrainerRequirements), and the auto-click loop.
	The altar / shop / egg / wheel prompts only open client windows, so
	the client handles them (Prompts.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local HubGenerator = require(script.Parent.HubGenerator)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)
local ShopService = require(script.Parent.ShopService)

local HubService = {}

local hub
local trainerModels = {} -- [index] = Model
local autoClick = {} -- [player] = true

---------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------

function HubService.TrainerUnlocked(player, index: number): boolean
	local req = Config.Hub.TrainerRequirements[index]
	local data = DataService.Get(player)
	if not req or not data then
		return false
	end
	if req.Aura and PlayerState.GetAura(player) < req.Aura and not data.TrainersUnlocked[tostring(index)] then
		return false
	end
	if req.Rebirths and data.Rebirths < req.Rebirths then
		return false
	end
	return true
end

-- Aura requirements unlock permanently once reached (spending later
-- doesn't re-lock the platform).
local function rememberUnlocks(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local changed = false
	for index in ipairs(Config.Hub.TrainerMultipliers) do
		if not data.TrainersUnlocked[tostring(index)] and HubService.TrainerUnlocked(player, index) then
			data.TrainersUnlocked[tostring(index)] = true
			changed = true
			if index > 1 then
				Remotes.Notify(player, ("Тренажёр x%s открыт!"):format(tostring(Config.Hub.TrainerMultipliers[index])), "gold")
			end
		end
	end
	if changed then
		PlayerState.Sync(player)
	end
end

-- Index of the platform the player's character stands on, or nil.
function HubService.TrainerUnderPlayer(player): number?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	for index, model in ipairs(trainerModels) do
		local center = model:GetAttribute("Center")
		local radius = model:GetAttribute("Radius")
		local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		if flat.Magnitude <= radius + 1 and math.abs(root.Position.Y - center.Y) < 8 then
			return index
		end
	end
	return nil
end

-- One trainer click for the player standing on `index`. Returns
-- gained aura and crit flag, or nil if not allowed.
function HubService.TrainerClick(player, index: number)
	if not HubService.TrainerUnlocked(player, index) then
		return nil
	end
	local multiplier = Config.Hub.TrainerMultipliers[index] or 1
	local amount, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player) * Config.Hub.TrainerRate * multiplier)
	local gained = PlayerState.GiveAura(player, amount)
	return gained, isCrit, trainerModels[index]
end

function HubService.TrainerIndexOf(model): number?
	return model and model:GetAttribute("Index")
end

---------------------------------------------------------------------
-- Stands
---------------------------------------------------------------------

local function wireStandPrompt(prompt, category: string, attribute: string)
	local allow = RateLimit.new(0.5)
	prompt.Triggered:Connect(function(player)
		if not allow(player) then
			return
		end
		local id = prompt:GetAttribute(attribute)
		local data = DataService.Get(player)
		if not data or not Config.ItemById[category][id] then
			return
		end
		local shop = Config.Shop[category]
		local action = if data[shop.OwnedKey][id] then "Equip" else "Buy"
		local ok, message = ShopService.Handle(player, action, category, id, true)
		Remotes.Notify(player, message, if ok then "gold" else "bad")
	end)
end

local function formatClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function runUniqueRotation()
	local stand = hub.UniqueStand
	if not stand then
		return
	end
	local uniques = {}
	for _, weapon in ipairs(Config.Weapons) do
		if weapon.Unique then
			table.insert(uniques, weapon)
		end
	end
	local period = Config.Hub.StandRotationMinutes * 60
	task.spawn(function()
		while true do
			-- Honest schedule: the slot is derived from wall-clock time,
			-- so every server shows the same weapon at the same time.
			local now = os.time()
			local slot = math.floor(now / period)
			local weapon = uniques[slot % #uniques + 1]
			stand.Show(weapon)
			local nextSwitch = (slot + 1) * period
			while os.time() < nextSwitch do
				stand.SetNote(Config.HubLayout.Texts.Stand .. "  " .. Config.HubLayout.Texts.StandTimer:format(formatClock(nextSwitch - os.time())))
				task.wait(1)
			end
		end
	end)
end

---------------------------------------------------------------------

function HubService.Init()
	hub = HubGenerator.Build()
	for _, model in ipairs(hub.Trainers:GetChildren()) do
		trainerModels[model:GetAttribute("Index")] = model
	end

	for _, prompt in ipairs(hub.WeaponPrompts) do
		wireStandPrompt(prompt, "Weapon", "WeaponId")
	end
	for _, prompt in ipairs(hub.BackpackPrompts) do
		wireStandPrompt(prompt, "Backpack", "BackpackId")
	end
	runUniqueRotation()

	-- Auto-click: toggle from the HUD; the server repeats trainer clicks
	-- while the player stands on an unlocked platform.
	local remote = Remotes.Get("AutoClick")
	remote.OnServerEvent:Connect(function(player, enabled)
		autoClick[player] = if enabled == true then true else nil
		player:SetAttribute("AutoClick", enabled == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		autoClick[player] = nil
	end)
	local clickRemote = Remotes.Get("ClickHit")
	task.spawn(function()
		while true do
			task.wait(Config.Hub.AutoClickInterval)
			for player in pairs(autoClick) do
				if PlayerState.IsReady(player) then
					local index = HubService.TrainerUnderPlayer(player)
					if index then
						local gained, isCrit, model = HubService.TrainerClick(player, index)
						if gained then
							clickRemote:FireClient(player, "Train", model, gained, isCrit)
						end
					end
				end
			end
		end
	end)

	-- Unlock bookkeeping: check every few seconds and on join.
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerState.IsReady(player) then
					rememberUnlocks(player)
				end
			end
		end
	end)

	return hub
end

return HubService
