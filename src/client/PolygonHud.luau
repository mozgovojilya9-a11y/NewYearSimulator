--[[
	PolygonHud.luau
	The Polygon panel: while this player hits the dummies it shows the
	last hit, DPS (damage of the last Config.Polygon.DpsWindow seconds),
	the combo (hits less than ComboGap apart), the best hit and the total.
	Hidden after ResetSeconds without hits. Dummies wobble when hit
	(local only). Nothing is rewarded: it is a test range.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Combat = require(script.Parent.Combat)
local Style = require(script.Parent.ui.Style)

local P = Config.Polygon

local PolygonHud = {}

local plate = Style.Plate(Style.Gui, {
	Name = "PolygonPanel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, Config.Hud.TopLeftReserved.Y + 116), -- below the objective and boost lines
	Size = UDim2.fromOffset(460, 70),
	ZIndex = 5,
})
plate.Visible = false
Style.Stroke(plate, 2.5, Style.Colors.Cyan)
local title = Style.Label(plate, P.Texts.Title, 18, Style.Colors.Cyan, { Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 20), ZIndex = 6 })
local line = Style.Label(plate, "", 20, Style.Colors.Text, { Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 24), TextScaled = true, ZIndex = 6 })
local best = Style.Label(plate, "", 15, Style.Colors.Gold, { Position = UDim2.fromOffset(8, 46), Size = UDim2.new(1, -16, 0, 18), TextScaled = true, ZIndex = 6 })
local _ = title
local scale = Instance.new("UIScale")
scale.Parent = plate

local hits = {} -- { time, damage }
local combo = 0
local lastHit = 0
local bestHit = 0
local total = 0

local wobble = {} -- [model] = { base = CFrame, t0 = time }

Combat.OnDummyHit = function(model, damage, isCrit)
	local now = os.clock()
	if now - lastHit > P.ResetSeconds then
		hits, combo, bestHit, total = {}, 0, 0, 0
	end
	combo = if now - lastHit <= P.ComboGap then combo + 1 else 1
	lastHit = now
	table.insert(hits, { now, damage })
	bestHit = math.max(bestHit, damage)
	total += damage
	plate.Visible = true
	scale.Scale = if isCrit then 1.12 else 1.05
	Style.Tween(scale, 0.18, { Scale = 1 })
	PolygonHud.Last = damage
	if model and model.Parent then
		local w = wobble[model]
		wobble[model] = { base = if w then w.base else model:GetPivot(), t0 = now, crit = isCrit }
	end
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	-- panel
	if plate.Visible then
		if now - lastHit > P.ResetSeconds then
			plate.Visible = false
		else
			local sum = 0
			local first = now
			for i = #hits, 1, -1 do
				local h = hits[i]
				if now - h[1] > P.DpsWindow then
					table.remove(hits, i)
				else
					sum += h[2]
					first = math.min(first, h[1])
				end
			end
			local window = math.clamp(now - first, 1, P.DpsWindow)
			line.Text = P.Texts.Line:format(Format.Number(PolygonHud.Last or 0), Format.Number(sum / window), combo)
			line.TextColor3 = if combo >= 10 then Style.Colors.Gold else Style.Colors.Text
			best.Text = P.Texts.Best:format(Format.Number(bestHit), Format.Number(total))
		end
	end
	-- dummy wobble
	for model, w in pairs(wobble) do
		local t = now - w.t0
		if not model.Parent or t > 0.6 then
			if model.Parent then
				model:PivotTo(w.base)
			end
			wobble[model] = nil
		else
			local amount = math.sin(t * 30) * (0.6 - t) * (if w.crit then 0.35 else 0.2)
			model:PivotTo(w.base * CFrame.Angles(amount, 0, 0))
		end
	end
end)

return PolygonHud
