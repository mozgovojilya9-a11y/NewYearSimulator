--[[
	ItemIcon.luau
	Item icons for cards and slots. If the owner uploaded a picture
	(Config.Assets.Icons[item id] = "rbxassetid://..."), it is shown;
	otherwise the item's 3D model (the same builders as on the character)
	is rendered once into a still ViewportFrame: a three-quarter view
	that fits the model, weapons turned diagonally, on a background in the
	color of the item's rarity (dark at the bottom, rarity glow on top).

		ItemIcon.Create(parent, category, item, size, position) -> Frame
	category: "Weapon" | "Armor" | "Material"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Preview = require(script.Parent.Preview)
local Style = require(script.Parent.Style)

local ItemIcon = {}

local function rarityOf(category: string, item)
	local id = item.Rarity
	return Config.Rarity[id or "Common"] or Config.Rarity.Common
end

local function idOf(category: string, item): string?
	return item.Id
end

-- Camera angle per category (the model is centered at the origin).
local VIEW = {
	Weapon = CFrame.Angles(0, math.rad(20), 0) * CFrame.Angles(math.rad(-12), 0, 0),
	Armor = CFrame.Angles(0, math.rad(-28), 0) * CFrame.Angles(math.rad(-14), 0, 0),
	Material = CFrame.Angles(0, math.rad(-35), 0) * CFrame.Angles(math.rad(-25), 0, 0),
}

function ItemIcon.Create(parent: GuiObject, category: string, item, size: UDim2, position: UDim2): Frame
	local rarity = rarityOf(category, item)
	local zIndex = parent.ZIndex + 1

	local frame = Instance.new("Frame")
	frame.Name = "Icon"
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Style.Colors.CardDark
	frame.ZIndex = zIndex
	frame.Parent = parent
	Style.Corner(frame, UDim.new(0, 10))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(rarity.Color:Lerp(Style.Colors.CardDark, 0.35), Style.Colors.CardDark)
	gradient.Parent = frame
	local stroke = Style.Stroke(frame, 2, rarity.Color)
	if rarity.Rainbow then
		Style.Rainbow(stroke)
	end

	local imageId = Config.Assets.Icons[idOf(category, item) or ""]
	if imageId and imageId ~= "" then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(0.9, 0.9)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.BackgroundTransparency = 1
		image.Image = imageId
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = zIndex + 1
		image.Parent = frame
		return frame
	end

	local model = Preview.Build(category, item)
	if not model then
		return frame
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 170, 185)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.8)
	viewport.ZIndex = zIndex + 1
	viewport.Parent = frame

	-- the model goes straight into the viewport: inside a WorldModel some
	-- icons stayed empty (no redraw), seen in Studio
	local world = viewport
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	-- weapons lie diagonally across the icon
	local turn = if category == "Weapon" then CFrame.Angles(0, 0, math.rad(-40)) else CFrame.new()
	model:PivotTo(turn)
	model.Parent = world
	local box, extents = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-box.Position) * model:GetPivot()) -- center at the origin
	local radius = extents.Magnitude / 2

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local view = VIEW[category] or VIEW.Material
	camera.CFrame = view * CFrame.new(0, 0, distance)
	-- a viewport sometimes stays empty until something changes: nudge the
	-- camera on the next frames so it redraws (seen in Studio)
	task.spawn(function()
		for i, delay in ipairs({ 0.05, 0.3, 0.8, 1.6 }) do
			task.wait(delay)
			if not camera.Parent then
				return
			end
			camera.CFrame = view * CFrame.new(0, 0, distance + (if i % 2 == 1 then 0.001 else 0))
		end
	end)
	return frame
end

return ItemIcon
