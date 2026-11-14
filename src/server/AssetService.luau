--[[
	AssetService.luau
	At server start: if the owner put models into ServerStorage/GameAssets,
	a cleaned copy goes to ReplicatedStorage/GameAssets (Shared.Assets: no
	scripts, no sounds, only what draws the model), so the server builders
	and the client previews can use them. The original in ServerStorage is
	never touched.

	Then it prints a report to Output: every model with its class, number
	of parts and size in studs (to see what the Prop_Misc_* models are),
	plus which expected names (Config.Assets.Expected) are missing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Assets = require(ReplicatedStorage.Shared.Assets)

local AssetService = {}

local function fmt(v: Vector3): string
	return ("%.1f × %.1f × %.1f"):format(v.X, v.Y, v.Z)
end

local function report(copy: Instance)
	local lines = { "[AssetService] GameAssets:" }
	for _, category in ipairs(copy:GetChildren()) do
		for _, item in ipairs(category:GetChildren()) do
			local model = Assets.Get(category.Name, item.Name)
			if model then
				local _, size = model:GetBoundingBox()
				table.insert(lines, ("  %s/%s  (%s, деталей: %d)  размер: %s"):format(category.Name, item.Name, item.ClassName, #Assets.Parts(model), fmt(size)))
				model:Destroy()
			else
				table.insert(lines, ("  %s/%s  (%s) — нет деталей, не используется"):format(category.Name, item.Name, item.ClassName))
			end
		end
	end
	local missing = {}
	for category, names in pairs(Config.Assets.Expected) do
		for _, name in ipairs(names) do
			if not Assets.Has(category, name) then
				table.insert(missing, category .. "/" .. name)
			end
		end
	end
	if #missing > 0 then
		table.sort(missing)
		table.insert(lines, "  Нет моделей (будут процедурные): " .. table.concat(missing, ", "))
	end
	print(table.concat(lines, "\n"))
end

function AssetService.Init()
	local source = ServerStorage:FindFirstChild("GameAssets")
	local old = ReplicatedStorage:FindFirstChild("GameAssets")
	if old then
		old:Destroy()
	end
	if not source then
		print("[AssetService] ServerStorage/GameAssets не найдена — все модели процедурные")
		return
	end
	local copy = source:Clone()
	local removed = Assets.Sanitize(copy)
	copy.Parent = ReplicatedStorage
	if removed > 0 then
		print(("[AssetService] GameAssets: убрано лишних объектов (скрипты, звуки и т.п.): %d"):format(removed))
	end
	report(copy)
end

return AssetService
