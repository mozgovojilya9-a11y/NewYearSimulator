--[[
	SystemNotice.luau
	Notifications of the "System" (like in Solo Leveling): translucent
	cyan windows at the top of the screen, in the same cut-corner style as
	the rest of the UI:
	    [ СИСТЕМА ]
	    Уровень повышен!
	    Уровень 12  •  +1 очко навыка  •  +3 очка характеристик
	SystemNotice.Show(title, lines, kind)  kind: nil | "gold" | "red"
	Shown one under another (Config.System.Max at once), each slides in,
	holds for Config.System.Seconds and fades. The server can send one
	through the System remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.Style)

local S = Config.System
local C = Style.Colors

local SystemNotice = {}

local holder = Instance.new("Frame")
holder.Name = "SystemNotices"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Position = UDim2.new(0.5, 0, 0, S.Top)
holder.Size = UDim2.fromOffset(S.Width, 400)
holder.BackgroundTransparency = 1
holder.ZIndex = 60
holder.Parent = Style.Gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = holder

local order = 0
local shown = {}

function SystemNotice.Show(title: string, lines: { string }?, kind: string?)
	lines = lines or {}
	local accent = if kind == "gold" then C.Gold elseif kind == "red" then C.Red else C.Cyan
	order += 1
	local height = 58 + #lines * 20
	local wrap = Instance.new("Frame")
	wrap.Name = "Notice"
	wrap.Size = UDim2.fromOffset(S.Width, height)
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = order
	wrap.ZIndex = 60
	wrap.Parent = holder
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(S.Width, 400)
	limit.Parent = wrap
	local panel = Style.Panel(wrap, {
		Size = UDim2.fromScale(1, 1),
		Fill = S.Fill,
		Transparency = S.Transparency,
		Border = accent,
		Cut = 12,
		ZIndex = 60,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = panel
	-- side brackets
	for _, x in ipairs({ 0, 1 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(x, 0.5)
		bar.Position = UDim2.new(x, if x == 0 then 6 else -6, 0.5, 0)
		bar.Size = UDim2.new(0, 2, 1, -26)
		bar.BackgroundColor3 = accent
		bar.BorderSizePixel = 0
		bar.ZIndex = 61
		bar.Parent = panel
	end
	Style.Label(panel, S.Tag, 12, accent, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 14), ZIndex = 62 })
	Style.Label(panel, title, 19, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(16, 24), Size = UDim2.new(1, -32, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62 })
	for i, line in ipairs(lines) do
		Style.Label(panel, line, 13, accent:Lerp(C.Text, 0.55), { Position = UDim2.fromOffset(16, 50 + (i - 1) * 20), Size = UDim2.new(1, -32, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62 })
	end
	Style.Tween(scale, 0.18, { Scale = 1 })
	Style.PlaySound("Ui", 1.6, 0.4)
	table.insert(shown, wrap)
	while #shown > S.Max do
		table.remove(shown, 1):Destroy()
	end
	task.delay(S.Seconds, function()
		if not wrap.Parent then
			return
		end
		Style.Tween(scale, 0.25, { Scale = 0.85 })
		for _, d in ipairs(wrap:GetDescendants()) do
			if d:IsA("TextLabel") then
				Style.Tween(d, 0.25, { TextTransparency = 1 })
			elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
				Style.Tween(d, 0.25, { BackgroundTransparency = 1 })
			elseif d:IsA("UIStroke") then
				Style.Tween(d, 0.25, { Transparency = 1 })
			end
		end
		task.wait(0.28)
		local index = table.find(shown, wrap)
		if index then
			table.remove(shown, index)
		end
		wrap:Destroy()
	end)
end

-- Every server notice is an important moment: a sound and (gold / red)
-- a short flash of the screen edge.
local Popups = require(script.Parent.Popups)
ReplicatedStorage:WaitForChild("System").OnClientEvent:Connect(function(title, lines, kind)
	if type(title) == "string" then
		SystemNotice.Show(title, if type(lines) == "table" then lines else nil, kind)
		Style.PlaySound(if kind == "red" then "Barrier" else "Forged", if kind == "gold" then 1.25 else 1, 0.5)
		if kind == "gold" or kind == "red" then
			Popups.Flash(if kind == "red" then C.Red else C.Gold)
		end
	end
end)

return SystemNotice
