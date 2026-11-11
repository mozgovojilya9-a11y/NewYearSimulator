--[[
	ClickService.luau
	Server-authoritative click handling (Day 2).

	The client only *asks* for a click by firing ClickHit with no
	arguments. The server decides whether the click is allowed
	(per-player cooldown), how much Aura it is worth (base damage +
	crit roll), applies it to leaderstats.Aura, and then tells that
	client the result so it can show the right popup.

	Anything the client might send along with FireServer is ignored on
	purpose -- the amount is never taken from the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ClickService = {}

local lastClickAt = {} -- [player] = os.clock() of last accepted click
local remote

-- Rolls the Aura value of a single click. Kept separate so later days
-- (weapons, pets, rebirth multipliers) can extend it in one place.
local function rollClick(_player)
	local amount = Config.Click.BaseDamage
	local isCrit = math.random() < Config.Click.CritChance
	if isCrit then
		amount *= Config.Click.CritMultiplier
	end
	return amount, isCrit
end

local function onClick(player)
	local now = os.clock()
	local last = lastClickAt[player]
	if last and now - last < Config.Click.Cooldown then
		return -- too fast: silently drop (anti-spam / autoclicker cap)
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local aura = leaderstats and leaderstats:FindFirstChild("Aura")
	if not aura then
		return -- data not loaded yet
	end

	lastClickAt[player] = now

	local amount, isCrit = rollClick(player)
	aura.Value += amount -- Main.server keeps DataService cache in sync

	remote:FireClient(player, amount, isCrit)
end

function ClickService.Init()
	remote = ReplicatedStorage:FindFirstChild(Config.ClickRemoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.ClickRemoteName
		remote.Parent = ReplicatedStorage
	end

	remote.OnServerEvent:Connect(onClick)

	Players.PlayerRemoving:Connect(function(player)
		lastClickAt[player] = nil
	end)
end

return ClickService
