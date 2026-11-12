--[[
	PlayerData.luau
	Read-only view of what the server publishes about the local player
	as attributes (PlayerState.Sync): JSON tables (Materials, Pets) and
	comma lists (owned items, passes). Decoded lazily and cached until
	the attribute changes.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local PlayerData = {}

local cache = {} -- [attribute] = decoded value

local function invalidate(attribute: string)
	cache[attribute] = nil
end

local watched = {}
local function watch(attribute: string)
	if not watched[attribute] then
		watched[attribute] = true
		player:GetAttributeChangedSignal(attribute):Connect(function()
			invalidate(attribute)
		end)
	end
end

-- JSON attribute -> table ({} when missing or broken).
function PlayerData.Table(attribute: string)
	watch(attribute)
	local value = cache[attribute]
	if value == nil then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute(attribute) or "{}")
		value = if ok and type(decoded) == "table" then decoded else {}
		cache[attribute] = value
	end
	return value
end

-- "a,b,c" attribute -> { a = true, b = true, c = true }.
function PlayerData.Set(attribute: string)
	watch(attribute)
	local value = cache[attribute]
	if value == nil then
		value = {}
		for id in string.gmatch(player:GetAttribute(attribute) or "", "[^,]+") do
			value[id] = true
		end
		cache[attribute] = value
	end
	return value
end

function PlayerData.Materials()
	return PlayerData.Table("Materials")
end

function PlayerData.MaterialCount(materialId: string): number
	return PlayerData.Materials()[materialId] or 0
end

function PlayerData.HasPass(key: string): boolean
	return PlayerData.Set("Passes")[key] == true
end

-- Calls fn now-and-later whenever any of the attributes changes.
function PlayerData.Changed(attributes: { string }, fn: () -> ())
	for _, attribute in ipairs(attributes) do
		watch(attribute)
		player:GetAttributeChangedSignal(attribute):Connect(fn)
	end
end

return PlayerData
