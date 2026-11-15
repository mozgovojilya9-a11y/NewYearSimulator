--[[
	Icons.luau
	Monochrome line icons drawn from Frames (lines, circles, rects) in one
	style: thin strokes, no fill, one color. No emoji, no image ids.

		Icons.Make(parent, "bag", 28, color?, zIndex?) -> Frame

	Replaceable without code: if the owner uploads a picture, it wins
	over the drawing:
	  1. ServerStorage/GameAssets/Icons/<name> (Decal / ImageLabel / Texture;
	     AssetService copies the id to ReplicatedStorage/GameAssets/Icons),
	  2. Config.Assets.UiIcons[<name>] = "rbxassetid://...".
	Unknown names draw a plain circle.

	Shapes use coordinates 0..1 inside the icon square (y goes down):
	  { "L", x1, y1, x2, y2 }        line
	  { "P", x1, y1, x2, y2, ... }   polyline (each pair = a point)
	  { "C", cx, cy, r }             circle outline
	  { "D", cx, cy, r }             filled dot
	  { "R", x, y, w, h }            rectangle outline
	  { "H", cx, cy, r }             hexagon outline (pointy top)
	  { "S", cx, cy, rOuter, rInner } five-point star
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Icons = {}

local STROKE = 0.085 -- line width, share of the icon size

local function ring(cx, cy, r, n, start)
	local points = {}
	for i = 0, n do
		local a = start + i * math.pi * 2 / n
		table.insert(points, cx + math.cos(a) * r)
		table.insert(points, cy + math.sin(a) * r)
	end
	return points
end

local function poly(...)
	return { "P", ... }
end

local DEF = {
	bag = { { "R", 0.18, 0.36, 0.64, 0.5 }, poly(0.36, 0.36, 0.36, 0.2, 0.64, 0.2, 0.64, 0.36), { "L", 0.18, 0.56, 0.82, 0.56 }, { "R", 0.44, 0.5, 0.12, 0.12 } },
	skills = { { "H", 0.5, 0.5, 0.4 }, { "H", 0.5, 0.5, 0.17 }, { "L", 0.5, 0.1, 0.5, 0.33 }, { "L", 0.5, 0.67, 0.5, 0.9 } },
	quest = { { "R", 0.24, 0.14, 0.52, 0.72 }, { "L", 0.34, 0.34, 0.66, 0.34 }, { "L", 0.34, 0.5, 0.66, 0.5 }, { "L", 0.34, 0.66, 0.54, 0.66 } },
	gem = { poly(0.18, 0.4, 0.34, 0.18, 0.66, 0.18, 0.82, 0.4, 0.5, 0.84, 0.18, 0.4), { "L", 0.18, 0.4, 0.82, 0.4 }, poly(0.34, 0.18, 0.42, 0.4, 0.5, 0.84, 0.58, 0.4, 0.66, 0.18) },
	gear = { { "C", 0.5, 0.5, 0.2 }, { "C", 0.5, 0.5, 0.06 } },
	sound = { poly(0.14, 0.4, 0.3, 0.4, 0.48, 0.22, 0.48, 0.78, 0.3, 0.6, 0.14, 0.6, 0.14, 0.4), poly(0.6, 0.36, 0.67, 0.5, 0.6, 0.64), poly(0.71, 0.26, 0.82, 0.5, 0.71, 0.74) },
	mute = { poly(0.14, 0.4, 0.3, 0.4, 0.48, 0.22, 0.48, 0.78, 0.3, 0.6, 0.14, 0.6, 0.14, 0.4), { "L", 0.6, 0.38, 0.84, 0.62 }, { "L", 0.84, 0.38, 0.6, 0.62 } },
	play = { poly(0.3, 0.18, 0.82, 0.5, 0.3, 0.82, 0.3, 0.18) },
	back = { poly(0.5, 0.2, 0.2, 0.5, 0.5, 0.8), { "L", 0.2, 0.5, 0.82, 0.5 } },
	credits = { { "H", 0.5, 0.5, 0.4 }, { "H", 0.5, 0.5, 0.2 } },
	close = { { "L", 0.24, 0.24, 0.76, 0.76 }, { "L", 0.76, 0.24, 0.24, 0.76 } },
	lock = { { "R", 0.24, 0.46, 0.52, 0.38 }, poly(0.34, 0.46, 0.34, 0.3, 0.42, 0.2, 0.58, 0.2, 0.66, 0.3, 0.66, 0.46), { "D", 0.5, 0.64, 0.05 } },
	check = { poly(0.18, 0.52, 0.4, 0.74, 0.82, 0.28) },
	chevron = { poly(0.2, 0.5, 0.5, 0.22, 0.8, 0.5), poly(0.2, 0.78, 0.5, 0.5, 0.8, 0.78) },
	star = { { "S", 0.5, 0.54, 0.4, 0.17 } },
	crown = { poly(0.16, 0.74, 0.16, 0.3, 0.34, 0.5, 0.5, 0.22, 0.66, 0.5, 0.84, 0.3, 0.84, 0.74, 0.16, 0.74), { "L", 0.16, 0.84, 0.84, 0.84 } },
	sword = { { "L", 0.28, 0.72, 0.84, 0.16 }, { "L", 0.18, 0.56, 0.44, 0.82 }, { "L", 0.12, 0.88, 0.28, 0.72 } },
	spear = { { "L", 0.14, 0.86, 0.66, 0.34 }, poly(0.6, 0.26, 0.86, 0.14, 0.74, 0.4, 0.6, 0.26), { "L", 0.26, 0.62, 0.38, 0.74 } },
	blaster = { { "R", 0.12, 0.3, 0.6, 0.2 }, { "L", 0.72, 0.4, 0.9, 0.4 }, poly(0.28, 0.5, 0.24, 0.8, 0.38, 0.8, 0.42, 0.5), { "L", 0.46, 0.5, 0.5, 0.62 } },
	shield = { poly(0.5, 0.12, 0.82, 0.24, 0.78, 0.58, 0.5, 0.88, 0.22, 0.58, 0.18, 0.24, 0.5, 0.12), { "L", 0.5, 0.26, 0.5, 0.74 } },
	heart = { { "L", 0.5, 0.22, 0.5, 0.78 }, { "L", 0.22, 0.5, 0.78, 0.5 }, { "C", 0.5, 0.5, 0.4 } },
	bolt = { poly(0.58, 0.1, 0.28, 0.54, 0.5, 0.54, 0.42, 0.9, 0.74, 0.42, 0.52, 0.42, 0.58, 0.1) },
	chest = { { "R", 0.14, 0.4, 0.72, 0.42 }, poly(0.14, 0.4, 0.22, 0.2, 0.78, 0.2, 0.86, 0.4), { "R", 0.44, 0.46, 0.12, 0.14 } },
	wheel = { { "C", 0.5, 0.5, 0.38 }, { "L", 0.5, 0.12, 0.5, 0.88 }, { "L", 0.12, 0.5, 0.88, 0.5 }, { "L", 0.23, 0.23, 0.77, 0.77 }, { "L", 0.77, 0.23, 0.23, 0.77 } },
	hammer = { { "L", 0.42, 0.42, 0.84, 0.86 }, poly(0.16, 0.34, 0.36, 0.14, 0.56, 0.34, 0.36, 0.54, 0.16, 0.34) },
	trophy = { poly(0.3, 0.16, 0.7, 0.16, 0.66, 0.46, 0.5, 0.56, 0.34, 0.46, 0.3, 0.16), poly(0.3, 0.22, 0.16, 0.24, 0.2, 0.38, 0.33, 0.42), poly(0.7, 0.22, 0.84, 0.24, 0.8, 0.38, 0.67, 0.42), { "L", 0.5, 0.56, 0.5, 0.74 }, { "L", 0.32, 0.82, 0.68, 0.82 } },
	gate = { poly(0.18, 0.86, 0.18, 0.36, 0.5, 0.14, 0.82, 0.36, 0.82, 0.86), { "L", 0.5, 0.36, 0.5, 0.86 }, { "L", 0.1, 0.86, 0.9, 0.86 } },
	skull = { { "C", 0.5, 0.44, 0.32 }, { "D", 0.38, 0.44, 0.07 }, { "D", 0.62, 0.44, 0.07 }, { "L", 0.4, 0.76, 0.4, 0.88 }, { "L", 0.6, 0.76, 0.6, 0.88 } },
	target = { { "C", 0.5, 0.5, 0.3 }, { "D", 0.5, 0.5, 0.06 }, { "L", 0.5, 0.06, 0.5, 0.26 }, { "L", 0.5, 0.74, 0.5, 0.94 }, { "L", 0.06, 0.5, 0.26, 0.5 }, { "L", 0.74, 0.5, 0.94, 0.5 } },
	dash = { poly(0.16, 0.24, 0.42, 0.5, 0.16, 0.76), poly(0.42, 0.24, 0.68, 0.5, 0.42, 0.76), { "L", 0.72, 0.5, 0.9, 0.5 } },
	burst = { { "C", 0.5, 0.5, 0.15 } },
	spin = { { "C", 0.5, 0.5, 0.32 }, poly(0.7, 0.14, 0.84, 0.3, 0.64, 0.36), { "L", 0.5, 0.5, 0.74, 0.62 } },
	volley = { { "L", 0.12, 0.28, 0.72, 0.28 }, { "L", 0.12, 0.5, 0.8, 0.5 }, { "L", 0.12, 0.72, 0.72, 0.72 }, poly(0.64, 0.2, 0.74, 0.28, 0.64, 0.36), poly(0.72, 0.42, 0.82, 0.5, 0.72, 0.58), poly(0.64, 0.64, 0.74, 0.72, 0.64, 0.8) },
	drone = { { "R", 0.36, 0.44, 0.28, 0.18 }, { "L", 0.14, 0.4, 0.86, 0.4 }, { "C", 0.16, 0.32, 0.08 }, { "C", 0.84, 0.32, 0.08 }, { "L", 0.5, 0.62, 0.5, 0.78 } },
	turret = { { "R", 0.26, 0.6, 0.48, 0.24 }, { "C", 0.46, 0.46, 0.14 }, { "L", 0.56, 0.4, 0.88, 0.24 }, { "L", 0.2, 0.84, 0.8, 0.84 } },
	trap = { { "L", 0.12, 0.72, 0.88, 0.72 }, poly(0.18, 0.72, 0.28, 0.42, 0.38, 0.72, 0.5, 0.42, 0.62, 0.72, 0.72, 0.42, 0.82, 0.72) },
	slash = { { "L", 0.18, 0.82, 0.8, 0.2 }, { "L", 0.34, 0.86, 0.86, 0.34 } },
	combo = { { "L", 0.12, 0.72, 0.4, 0.2 }, { "L", 0.36, 0.82, 0.64, 0.3 }, { "L", 0.6, 0.9, 0.88, 0.38 } },
	charge = { { "C", 0.5, 0.5, 0.36 }, poly(0.54, 0.22, 0.38, 0.52, 0.52, 0.52, 0.46, 0.78, 0.64, 0.46, 0.5, 0.46, 0.54, 0.22) },
	flame = { poly(0.5, 0.1, 0.74, 0.44, 0.68, 0.8, 0.5, 0.9, 0.32, 0.8, 0.26, 0.44, 0.38, 0.52, 0.5, 0.1) },
	eye = { poly(0.1, 0.5, 0.3, 0.3, 0.5, 0.24, 0.7, 0.3, 0.9, 0.5, 0.7, 0.7, 0.5, 0.76, 0.3, 0.7, 0.1, 0.5), { "C", 0.5, 0.5, 0.12 } },
	regen = { { "C", 0.5, 0.5, 0.36 }, { "L", 0.5, 0.32, 0.5, 0.68 }, { "L", 0.32, 0.5, 0.68, 0.5 } },
	wave = { poly(0.1, 0.6, 0.24, 0.4, 0.38, 0.6, 0.52, 0.4, 0.66, 0.6, 0.8, 0.4, 0.9, 0.52), { "L", 0.1, 0.78, 0.9, 0.78 } },
	vortex = { { "C", 0.5, 0.5, 0.38 }, { "C", 0.5, 0.5, 0.22 }, { "D", 0.5, 0.5, 0.06 } },
	arrow = { { "L", 0.14, 0.86, 0.82, 0.18 }, poly(0.56, 0.18, 0.82, 0.18, 0.82, 0.44) },
	user = { { "C", 0.5, 0.34, 0.17 }, poly(0.18, 0.86, 0.24, 0.62, 0.5, 0.56, 0.76, 0.62, 0.82, 0.86) },
	academy = { poly(0.1, 0.4, 0.5, 0.18, 0.9, 0.4, 0.5, 0.62, 0.1, 0.4), poly(0.26, 0.5, 0.26, 0.72, 0.5, 0.84, 0.74, 0.72, 0.74, 0.5), { "L", 0.86, 0.42, 0.86, 0.7 } },
	map = { poly(0.12, 0.22, 0.38, 0.12, 0.62, 0.22, 0.88, 0.12, 0.88, 0.78, 0.62, 0.88, 0.38, 0.78, 0.12, 0.88, 0.12, 0.22), { "L", 0.38, 0.12, 0.38, 0.78 }, { "L", 0.62, 0.22, 0.62, 0.88 } },
	talk = { poly(0.12, 0.2, 0.88, 0.2, 0.88, 0.66, 0.46, 0.66, 0.26, 0.84, 0.3, 0.66, 0.12, 0.66, 0.12, 0.2), { "L", 0.26, 0.36, 0.74, 0.36 }, { "L", 0.26, 0.5, 0.6, 0.5 } },
	reset = { { "C", 0.5, 0.52, 0.3 }, poly(0.36, 0.12, 0.52, 0.22, 0.38, 0.34) },
	plus = { { "L", 0.5, 0.18, 0.5, 0.82 }, { "L", 0.18, 0.5, 0.82, 0.5 } },
	minus = { { "L", 0.18, 0.5, 0.82, 0.5 } },
}
-- gear spokes and burst rays
for i = 0, 7 do
	local a = i * math.pi / 4
	table.insert(DEF.gear, { "L", 0.5 + math.cos(a) * 0.27, 0.5 + math.sin(a) * 0.27, 0.5 + math.cos(a) * 0.42, 0.5 + math.sin(a) * 0.42 })
	table.insert(DEF.burst, { "L", 0.5 + math.cos(a) * 0.25, 0.5 + math.sin(a) * 0.25, 0.5 + math.cos(a) * 0.43, 0.5 + math.sin(a) * 0.43 })
end

-- Aliases (class ids, windows).
DEF.Blade = DEF.sword
DEF.Pulse = DEF.spear
DEF.Gunner = DEF.blaster
DEF.Inventory = DEF.bag
DEF.Skills = DEF.skills
DEF.Quests = DEF.quest
DEF.Shop = DEF.gem
DEF.Forge = DEF.hammer

Icons.Names = {}
for name in pairs(DEF) do
	table.insert(Icons.Names, name)
end
table.sort(Icons.Names)

---------------------------------------------------------------------

local function imageFor(name: string): string?
	local root = ReplicatedStorage:FindFirstChild("GameAssets")
	local folder = root and root:FindFirstChild("Icons")
	local value = folder and folder:FindFirstChild(name)
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end
	local id = Config.Assets.UiIcons and Config.Assets.UiIcons[name]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function frame(parent: Instance, z: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function line(holder, x1, y1, x2, y2, w, z, color)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	local f = frame(holder, z, color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
	f.Size = UDim2.fromScale(length + w * 0.9, w) -- slight overlap so joints close
	f.Rotation = math.deg(math.atan2(dy, dx))
	return f
end

local function circle(holder, cx, cy, r, w, z, color, px: number, filled: boolean)
	local f = frame(holder, z, color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(r * 2, r * 2)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	if not filled then
		f.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = math.max(1, w * px)
		stroke.Parent = f
	end
	return f
end

local function draw(holder: Frame, shapes, size: number, color: Color3, z: number)
	local w = STROKE
	for _, shape in ipairs(shapes) do
		local kind = shape[1]
		if kind == "L" then
			line(holder, shape[2], shape[3], shape[4], shape[5], w, z, color)
		elseif kind == "P" then
			for i = 2, #shape - 3, 2 do
				line(holder, shape[i], shape[i + 1], shape[i + 2], shape[i + 3], w, z, color)
			end
		elseif kind == "C" then
			circle(holder, shape[2], shape[3], shape[4], w, z, color, size, false)
		elseif kind == "D" then
			circle(holder, shape[2], shape[3], shape[4], w, z, color, size, true)
		elseif kind == "R" then
			local x, y, rw, rh = shape[2], shape[3], shape[4], shape[5]
			line(holder, x, y, x + rw, y, w, z, color)
			line(holder, x + rw, y, x + rw, y + rh, w, z, color)
			line(holder, x + rw, y + rh, x, y + rh, w, z, color)
			line(holder, x, y + rh, x, y, w, z, color)
		elseif kind == "H" then
			local points = ring(shape[2], shape[3], shape[4], 6, -math.pi / 2)
			draw(holder, { { "P", table.unpack(points) } }, size, color, z)
		elseif kind == "S" then
			local points = {}
			for i = 0, 10 do
				local r = if i % 2 == 0 then shape[4] else shape[5]
				local a = -math.pi / 2 + i * math.pi / 5
				table.insert(points, shape[2] + math.cos(a) * r)
				table.insert(points, shape[3] + math.sin(a) * r)
			end
			draw(holder, { { "P", table.unpack(points) } }, size, color, z)
		end
	end
end

-- Draws icon `name` into a new square Frame (size in px). Returns it.
function Icons.Make(parent: Instance, name: string, size: number, color: Color3?, zIndex: number?)
	local c = color or Config.Theme.Text
	local z = zIndex or ((parent:IsA("GuiObject") and parent.ZIndex or 1) + 1)
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder:SetAttribute("Icon", name)
	holder.Parent = parent
	local image = imageFor(name)
	if image then
		local label = Instance.new("ImageLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Image = image
		label.ImageColor3 = Color3.new(1, 1, 1)
		label.ScaleType = Enum.ScaleType.Fit
		label.ZIndex = z
		label.Parent = holder
		return holder
	end
	draw(holder, DEF[name] or { { "C", 0.5, 0.5, 0.36 } }, size, c, z)
	return holder
end

-- Recolors an icon made by Icons.Make (lines and circles).
function Icons.Paint(holder: Instance, color: Color3)
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundColor3 = color
		elseif d:IsA("UIStroke") then
			d.Color = color
		end
	end
end

-- Replaces the drawing inside `holder` with another icon (same size).
function Icons.Set(holder: Frame, name: string, color: Color3?)
	if holder:GetAttribute("Icon") == name then
		if color then
			Icons.Paint(holder, color)
		end
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		child:Destroy()
	end
	holder:SetAttribute("Icon", name)
	local size = holder.AbsoluteSize.X > 0 and holder.AbsoluteSize.X or holder.Size.X.Offset
	local image = imageFor(name)
	if image then
		local label = Instance.new("ImageLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Image = image
		label.ScaleType = Enum.ScaleType.Fit
		label.ZIndex = holder.ZIndex
		label.Parent = holder
		return
	end
	draw(holder, DEF[name] or { { "C", 0.5, 0.5, 0.36 } }, size, color or Config.Theme.Text, holder.ZIndex)
end

return Icons
