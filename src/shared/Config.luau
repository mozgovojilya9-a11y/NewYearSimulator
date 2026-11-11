--[[
	Config.luau
	Shared, read-only game configuration and tuning values.
	Server and client both require this module; it contains no secrets.
]]

local Config = {}

Config.DataStoreName = "AuraClicker_v1"

-- Default data for a brand-new player. DataService backfills any
-- fields missing from an older save, so new fields can be added here
-- safely as the game grows.
Config.StartingData = {
	Aura = 0,
	Zone = 1,
	EquippedWeapon = "Stick",
	Rebirths = 0,
}

-- Autosave interval (seconds) as a safety net in addition to
-- save-on-leave.
Config.AutosaveInterval = 120

-- Click mechanic (Day 2). The server is the source of truth for every
-- number here; the client only reads them for visuals/throttling.
Config.Click = {
	BaseDamage = 1, -- Aura gained per normal click
	CritChance = 0.1, -- 10% chance per click
	CritMultiplier = 5, -- crit click = BaseDamage * CritMultiplier
	Cooldown = 0.1, -- minimum seconds between accepted clicks per player
}

-- Name of the RemoteEvent the server creates in ReplicatedStorage.
-- Client -> Server: FireServer() asks for a click.
-- Server -> Client: FireClient(player, amount, isCrit) confirms it.
Config.ClickRemoteName = "ClickHit"

-- Built-in Roblox client sounds, so no uploaded asset is needed.
-- Swap for your own rbxassetid:// later if you want.
Config.Sounds = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
}

return Config
