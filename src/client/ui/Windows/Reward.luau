--[[
	Reward.luau
	"Награда" window: what the dungeon pays out — boss pet drops, the
	offline backpack income rule and the rebirth bonus. Read-only info
	built from Config so it never drifts from the real numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local Reward = {}

local window = Window.new("Награды", Style.Colors.Gold, Vector2.new(480, 400))
local list = Window.List(window.Content)

local function row(order, icon, title, text, color)
	local card = Instance.new("Frame")
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -8, 0, 64)
	card.BackgroundColor3 = Style.Lighter(color, 0.82)
	card.ZIndex = 33
	card.Parent = list
	Style.Corner(card, UDim.new(0, 14))
	Style.Stroke(card, 3, color)
	Style.Label(card, icon, 30, Style.Colors.Text, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(50, 64), ZIndex = 34 })
	Style.Label(card, title, 18, Style.Colors.Outline, { Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -70, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 }):FindFirstChildOfClass("UIStroke").Transparency = 1
	Style.Label(card, text, 14, Style.Colors.Outline, { Position = UDim2.fromOffset(62, 32), Size = UDim2.new(1, -70, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 34 }):FindFirstChildOfClass("UIStroke").Transparency = 1
end

local order = 0
for _, drop in ipairs(Config.Dungeon.BossPetDrops) do
	order += 1
	local pet = Config.ItemById.Pet[drop.PetId]
	row(order, "🐾", pet.Name, ("Шанс %d%% с каждого босса • +%d%% ко всей Ауре"):format(math.floor(drop.Chance * 100 + 0.5), math.floor(pet.Bonus * 100 + 0.5)), (Style.RarityColor(pet.Rarity)))
end
order += 1
row(order, "🎒", "Офлайн-доход", ("Рюкзак приносит %d%% дохода, пока тебя нет (до %d ч)"):format(math.floor(Config.Offline.Efficiency * 100 + 0.5), Config.Offline.MaxHours), Style.Colors.Orange)
order += 1
row(order, "🔁", "Перерождение", ("Пройди этап %d: +x%s к Ауре навсегда"):format(Config.RebirthRequirement, tostring(Config.Rebirth.MultiplierPerRebirth)), Style.Colors.Purple)
order += 1
row(order, "👑", "Боссы", ("Каждый %d-й этап — босс с наградой x%s"):format(Config.Dungeon.BossEvery, tostring(Config.Dungeon.BossRewardMultiplier)), Style.Colors.Gold)

Reward.Window = window
Reward.Open = window.Open
return Reward
