--[[
	ClickService.luau
	Server-authoritative click button (Day 2).

	The client only *asks* for a click by firing ClickHit with no
	arguments. The server checks the per-player cooldown, rolls the
	crit, adds the Aura through PlayerState and tells that client the
	result so it can show the right popup.

	Anything the client sends along with FireServer is ignored on
	purpose -- the amount is never taken from the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)
local Remotes = require(script.Parent.Remotes)

local ClickService = {}

function ClickService.Init()
	local remote = Remotes.Get("ClickHit")
	local allow = RateLimit.new(Config.Click.Cooldown)

	remote.OnServerEvent:Connect(function(player)
		if not PlayerState.IsReady(player) or not allow(player) then
			return -- not loaded yet, or clicking too fast
		end

		local amount, isCrit = PlayerState.RollCrit(PlayerState.ClickPower(player))
		local gained = PlayerState.GiveAura(player, amount)

		remote:FireClient(player, gained, isCrit)
	end)
end

return ClickService
