--[[
	AssetService.luau
	At server start: if the owner put models into ServerStorage/GameAssets,
	a cleaned copy goes to ReplicatedStorage/GameAssets (Shared.Assets: no
	scripts, no sounds, only what draws the model), so the server builders
	and the client previews can use them. The original in ServerStorage is
	never touched.

	Icons and Audio are special: GameAssets/Icons/<name> (Decal, Texture,
	ImageLabel or ImageButton) becomes a StringValue with the image id and
	GameAssets/Audio/<key> (Sound) a bare Sound in ReplicatedStorage/
	GameAssets/{Icons, Audio}; ui/Icons and Style.PlaySound prefer them.

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

local MEDIA = { Icons = true, Audio = true }

local function imageOf(instance: Instance): string?
	for _, prop in ipairs({ "Image", "Texture" }) do
		local ok, value = pcall(function()
			return (instance :: any)[prop]
		end)
		if ok and type(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

-- Owner icons / sounds -> clean replacements (ids only, nothing that runs).
local function media(source: Instance, copy: Instance)
	local icons = source:FindFirstChild("Icons")
	if icons then
		local folder = Instance.new("Folder")
		folder.Name = "Icons"
		for _, d in ipairs(icons:GetDescendants()) do
			local image = imageOf(d)
			if image and not folder:FindFirstChild(d.Name) then
				local value = Instance.new("StringValue")
				value.Name = d.Name
				value.Value = image
				value.Parent = folder
			end
		end
		folder.Parent = copy
	end
	local audio = source:FindFirstChild("Audio")
	if audio then
		local folder = Instance.new("Folder")
		folder.Name = "Audio"
		for _, d in ipairs(audio:GetDescendants()) do
			if d:IsA("Sound") and d.SoundId ~= "" and not folder:FindFirstChild(d.Name) then
				local sound = Instance.new("Sound")
				sound.Name = d.Name
				sound.SoundId = d.SoundId
				sound.Volume = d.Volume
				sound.PlaybackSpeed = d.PlaybackSpeed
				sound.Parent = folder
			end
		end
		folder.Parent = copy
	end
end

local function report(copy: Instance)
	local lines = { "[AssetService] GameAssets:" }
	for _, category in ipairs(copy:GetChildren()) do
		if MEDIA[category.Name] then
			table.insert(lines, ("  %s: %d"):format(category.Name, #category:GetChildren()))
			continue
		end
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
	for name in pairs(MEDIA) do
		local folder = copy:FindFirstChild(name)
		if folder then
			folder:Destroy() -- rebuilt clean by media()
		end
	end
	local removed = Assets.Sanitize(copy)
	media(source, copy)
	copy.Parent = ReplicatedStorage
	if removed > 0 then
		print(("[AssetService] GameAssets: убрано лишних объектов (скрипты, звуки и т.п.): %d"):format(removed))
	end
	report(copy)
end

return AssetService
