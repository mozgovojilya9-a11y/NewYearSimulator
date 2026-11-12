--[[
	Preview.luau
	ViewportFrame with a slowly rotating Part model (weapon, material)
	for cards. Models come from the shared builders so the preview
	always matches what the character carries.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MaterialBuilder = require(ReplicatedStorage.Shared.MaterialBuilder)
local WeaponBuilder = require(ReplicatedStorage.Shared.WeaponBuilder)
local Style = require(script.Parent.Style)

local Preview = {}

local function buildFor(category: string, item)
	if category == "Weapon" then
		local model = WeaponBuilder.Build(item)
		WeaponBuilder.SetAnchored(model, true)
		return model
	elseif category == "Material" then
		return MaterialBuilder.Build(item)
	end
	return nil
end

-- Returns the ViewportFrame (or nil when the category has no model).
function Preview.Create(parent, category: string, item, size: UDim2, position: UDim2)
	local model = buildFor(category, item)
	if not model then
		return nil
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = size
	viewport.Position = position
	viewport.BackgroundColor3 = Style.Colors.CardDark
	viewport.BackgroundTransparency = 0
	viewport.Ambient = Color3.fromRGB(180, 180, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -0.5)
	viewport.ZIndex = parent.ZIndex + 1
	viewport.Parent = parent
	Style.Corner(viewport, UDim.new(0, 10))

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model:PivotTo(CFrame.new())
	model.Parent = world

	local extents = model:GetExtentsSize()
	local radius = math.max(extents.X, extents.Y, extents.Z)
	local center = model:GetBoundingBox().Position

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local angle = math.random() * math.pi * 2
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not viewport.Parent then
			connection:Disconnect()
			return
		end
		if not viewport.Visible then
			return
		end
		angle += dt * 1.2
		local distance = radius * 1.6 + 1
		local eye = center + Vector3.new(math.cos(angle) * distance, radius * 0.35, math.sin(angle) * distance)
		camera.CFrame = CFrame.lookAt(eye, center)
	end)
	return viewport
end

-- Rarity color helper for cards that have no model (pets).
function Preview.Color(item): Color3
	return item.Color or Config.Theme.Purple
end

return Preview
