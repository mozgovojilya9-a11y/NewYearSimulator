--[[
	AssetService.luau
	At server start: if the owner put models into ServerStorage/GameAssets,
	a cleaned copy goes to ReplicatedStorage/GameAssets (Shared.Assets:
	no scripts, no sounds, only what draws the model), so the builders on
	the server and the client previews can use them. The original in
	ServerStorage is never touched.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)

local AssetService = {}

function AssetService.Init()
	local source = ServerStorage:FindFirstChild("GameAssets")
	if not source then
		return
	end
	local old = ReplicatedStorage:FindFirstChild("GameAssets")
	if old then
		old:Destroy()
	end
	local copy = source:Clone()
	local removed = Assets.Sanitize(copy)
	copy.Parent = ReplicatedStorage
	if removed > 0 then
		print(("[AssetService] GameAssets: убрано лишних объектов (скрипты, звуки и т.п.): %d"):format(removed))
	end
end

return AssetService
