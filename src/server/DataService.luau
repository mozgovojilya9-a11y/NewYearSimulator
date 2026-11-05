-- Загрузка, кэш и сохранение данных игроков (DataStore).
-- ВАЖНО: в Studio включите Game Settings → Security → Enable Studio Access to API Services.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local store = DataStoreService:GetDataStore("NewYearSim_v1")

local DEFAULT = {
	Power = 0,
	Wins = 0,
	Rebirths = 0,
	Stage = 1,
	Zone = 1,
	OwnedHeroes = { snowman = true },
	EquippedHero = "snowman",
}

local DataService = {}
local cache = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function withRetry(fn, attempts)
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("DataStore: попытка %d не удалась: %s"):format(i, tostring(result)))
		task.wait(1)
	end
	return false, nil
end

function DataService.Load(player)
	local key = "player_" .. player.UserId
	local ok, saved = withRetry(function()
		return store:GetAsync(key)
	end, 3)

	if not ok then
		-- Не кэшируем и не сохраняем пустые данные, чтобы не затереть прогресс.
		player:Kick("Не удалось загрузить данные. Зайдите ещё раз.")
		return nil
	end

	local data = saved or {}
	for k, v in DEFAULT do
		if data[k] == nil then
			data[k] = deepCopy(v)
		end
	end

	if not player.Parent then
		return nil -- игрок вышел, пока грузились данные
	end

	cache[player] = data
	return data
end

function DataService.Get(player)
	return cache[player]
end

function DataService.Save(player)
	local data = cache[player]
	if not data then
		return
	end
	withRetry(function()
		store:UpdateAsync("player_" .. player.UserId, function()
			return data
		end)
	end, 3)
end

function DataService.Release(player)
	DataService.Save(player)
	cache[player] = nil
end

function DataService.Start()
	task.spawn(function()
		while true do
			task.wait(Config.SaveInterval)
			for player in cache do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in cache do
			pending += 1
			task.spawn(function()
				DataService.Save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return DataService