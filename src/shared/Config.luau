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

return Config
