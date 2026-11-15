--[[
	PolygonService.luau
	Test dummies on the hub Polygon (Config.HubLayout.Polygon.Dummies):
	owner models GameAssets/Trainers/Trainer_Dummy / Trainer_Bag scaled to
	Config.Polygon.DummyHeight, or procedural ones. Hitting a dummy uses
	the real damage roll (StatService) and gives NOTHING: it only reports
	the number to the player (ClickHit "Dummy", model, damage, isCrit),
	whose client shows damage, DPS and combo (PolygonHud).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local NanoKit = require(script.Parent.NanoKit)
local Remotes = require(script.Parent.Remotes)
local StatService = require(script.Parent.StatService)

local PolygonService = {}

local N = Config.Nano
local M = NanoKit.Materials
local P = Config.Polygon

local dummies = {} -- [model] = true

-- Procedural dummies: a target dummy on a post and a hanging bag.
local function proceduralDummy(parent, cf: CFrame, height: number)
	local m = NanoKit.Model(parent, "Dummy")
	local s = height / 6.5
	NanoKit.Cylinder(m, "Base", 0.6 * s, 3 * s, cf * CFrame.new(0, 0.3 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), N.Graphite, M.Metal)
	NanoKit.Column(m, "Post", 2.4 * s, 0.5 * s, (cf * CFrame.new(0, 0.6 * s, 0)).Position, N.Steel, M.Metal)
	NanoKit.Panel(m, "Torso", Vector3.new(2.2, 2.6, 1.2) * s, cf * CFrame.new(0, 4 * s, 0), N.SteelLight, M.Plate)
	NanoKit.Panel(m, "Head", Vector3.new(1.2, 1.2, 1.2) * s, cf * CFrame.new(0, 5.9 * s, 0), N.SteelLight, M.Metal)
	NanoKit.Panel(m, "Visor", Vector3.new(0.9, 0.25, 0.1) * s, cf * CFrame.new(0, 6 * s, -0.62 * s), N.Cyan, M.Neon, { CanCollide = false })
	for i, r in ipairs({ 1.6, 1, 0.45 }) do
		NanoKit.Cylinder(m, "Target", 0.08, r * s, cf * CFrame.new(0, 4 * s, -0.62 * s - i * 0.01) * CFrame.Angles(0, math.rad(90), 0), if i % 2 == 1 then Config.Theme.Red else Color3.new(1, 1, 1), M.Smooth).CanCollide = false
	end
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Panel(m, "Arm", Vector3.new(1.8, 0.5, 0.5) * s, cf * CFrame.new(side * 1.9 * s, 4.6 * s, 0) * CFrame.Angles(0, 0, math.rad(side * -20)), N.Steel, M.Metal)
	end
	return m
end

local function proceduralBag(parent, cf: CFrame, height: number)
	local m = NanoKit.Model(parent, "Bag")
	local s = height / 6.5
	for _, side in ipairs({ -1, 1 }) do
		NanoKit.Column(m, "Frame", 7.5 * s, 0.45 * s, (cf * CFrame.new(side * 2 * s, 0, 0)).Position, N.Graphite, M.Metal)
	end
	NanoKit.Panel(m, "Bar", Vector3.new(4.6, 0.4, 0.4) * s, cf * CFrame.new(0, 7.5 * s, 0), N.Graphite, M.Metal)
	NanoKit.Panel(m, "Chain", Vector3.new(0.15, 1, 0.15) * s, cf * CFrame.new(0, 6.9 * s, 0), N.SteelLight, M.Metal, { CanCollide = false })
	NanoKit.Column(m, "Bag", 4 * s, 1.8 * s, (cf * CFrame.new(0, 2.4 * s, 0)).Position, Color3.fromRGB(60, 60, 70), Enum.Material.Fabric)
	NanoKit.Column(m, "Band", 0.25 * s, 1.9 * s, (cf * CFrame.new(0, 4.2 * s, 0)).Position, N.Cyan, M.Neon)
	return m
end

local function place(parent, def, center: Vector3)
	local pos = center + def.Offset + Vector3.new(0, 0.4, 0)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)) -- faces the avenue (+X)
	local height = P.DummyHeight * (if def.Big then P.BigScale else 1)
	local model = Assets.Prop(def.Kind, height)
	if model then
		Assets.PlaceOnGround(model, cf)
		model.Parent = parent
	elseif def.Kind == "Trainer_Bag" then
		model = proceduralBag(parent, cf, height)
	else
		model = proceduralDummy(parent, cf, height)
	end
	model.Name = "Dummy"
	model:SetAttribute("Dummy", true)
	model:SetAttribute("Hits", 0)
	dummies[model] = true
	return model
end

function PolygonService.IsDummy(model): boolean
	return typeof(model) == "Instance" and dummies[model] == true
end

-- Nearest dummy within range of a position (attack without a target).
function PolygonService.Nearest(position: Vector3, range: number)
	local best, bestDistance = nil, range
	for model in pairs(dummies) do
		local distance = (model:GetPivot().Position - position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = model, distance
		end
	end
	return best
end

-- A hit on a dummy: real damage roll, reported to this player only.
function PolygonService.Hit(player, model)
	local damage, isCrit = StatService.RollHit(player)
	return PolygonService.Damage(player, model, damage, isCrit)
end

-- A ready-made amount of damage (abilities, class attacks).
function PolygonService.Damage(player, model, damage: number, isCrit: boolean?)
	if not dummies[model] then
		return 0
	end
	damage = math.max(1, math.floor(damage))
	model:SetAttribute("Hits", (model:GetAttribute("Hits") or 0) + 1)
	Remotes.Get("ClickHit"):FireClient(player, "Dummy", model, damage, isCrit == true)
	return damage
end

-- Dummies within `range` of `position`, nearest first.
function PolygonService.Near(position: Vector3, range: number)
	local list = {}
	for model in pairs(dummies) do
		if model.Parent then
			local distance = (model:GetPivot().Position - position).Magnitude - 1.5
			if distance <= range then
				table.insert(list, { model = model, distance = distance })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance
	end)
	return list
end

function PolygonService.Init(hub)
	local folder = NanoKit.Model(hub.Polygon, "Dummies")
	for _, def in ipairs(Config.HubLayout.Polygon.Dummies) do
		place(folder, def, hub.PolygonCenter)
	end
end

return PolygonService
