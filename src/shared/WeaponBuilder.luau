--[[
	WeaponBuilder.luau
	Builds a weapon Model out of Parts for a Config.Weapons entry. Used
	by the hub stands (server), the character hand (server) and the
	shop ViewportFrames (client), so it lives in Shared and depends on
	nothing else.

	Convention: PrimaryPart = "Handle". The handle's +Y axis points
	along the blade; the grip point is the handle's origin. All parts
	are unanchored, massless and welded to the Handle, so the model can
	be anchored (stands) or welded to a hand (characters).
]]

local WeaponBuilder = {}

local function part(model, name, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function weldAll(model, handle)
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		end
	end
end

local WOOD = Color3.fromRGB(120, 80, 45)
local DARK = Color3.fromRGB(60, 40, 30)
local GOLD = Color3.fromRGB(255, 201, 60)

-- Generic sword: handle, guard, blade (optionally neon), tip.
local function sword(model, origin, bladeLen, bladeW, color, neon, guardColor)
	local handle = part(model, "Handle", Vector3.new(0.35, 1.2, 0.35), origin * CFrame.new(0, 0.6, 0), DARK)
	part(model, "Pommel", Vector3.new(0.5, 0.3, 0.5), origin * CFrame.new(0, -0.05, 0), guardColor or GOLD)
	part(model, "Guard", Vector3.new(1.6, 0.25, 0.45), origin * CFrame.new(0, 1.3, 0), guardColor or GOLD)
	local blade = part(model, "Blade", Vector3.new(bladeW, bladeLen, 0.15), origin * CFrame.new(0, 1.45 + bladeLen / 2, 0), color, if neon then Enum.Material.Neon else Enum.Material.Metal)
	local tip = part(model, "Tip", Vector3.new(bladeW * 0.5, 0.5, 0.15), origin * CFrame.new(0, 1.45 + bladeLen + 0.25, 0), color, if neon then Enum.Material.Neon else Enum.Material.Metal)
	return handle, blade, tip
end

local builders = {}

builders.Stick = function(model, origin)
	local handle = part(model, "Handle", Vector3.new(0.4, 1.2, 0.4), origin * CFrame.new(0, 0.6, 0), WOOD, Enum.Material.Wood)
	part(model, "Blade", Vector3.new(0.35, 2.4, 0.35), origin * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(6)), WOOD, Enum.Material.Wood)
	part(model, "Knot", Vector3.new(0.5, 0.4, 0.5), origin * CFrame.new(0.1, 1.9, 0), DARK, Enum.Material.Wood)
	return handle
end

builders.WoodSword = function(model, origin, weapon)
	local handle = sword(model, origin, 2.6, 0.6, weapon.Color, false, WOOD)
	return handle
end

builders.IronSword = function(model, origin, weapon)
	local handle = sword(model, origin, 3.2, 0.65, weapon.Color, false)
	return handle
end

builders.AuraKatana = function(model, origin, weapon)
	local handle = part(model, "Handle", Vector3.new(0.3, 1.5, 0.3), origin * CFrame.new(0, 0.75, 0), DARK)
	part(model, "Guard", Vector3.new(0.9, 0.15, 0.9), origin * CFrame.new(0, 1.55, 0), GOLD)
	-- Slightly curved: two blade segments at a small angle.
	part(model, "Blade", Vector3.new(0.45, 2.2, 0.12), origin * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(4)), weapon.Color, Enum.Material.Neon)
	part(model, "Blade2", Vector3.new(0.4, 1.8, 0.12), origin * CFrame.new(-0.2, 4.6, 0) * CFrame.Angles(0, 0, math.rad(12)), weapon.Color, Enum.Material.Neon)
	return handle
end

builders.StormBlade = function(model, origin, weapon)
	local handle = sword(model, origin, 3.6, 1.0, weapon.Color, true, Color3.fromRGB(40, 80, 140))
	part(model, "Core", Vector3.new(0.25, 3, 0.2), origin * CFrame.new(0, 3.3, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
	return handle
end

builders.EclipseScythe = function(model, origin, weapon)
	local handle = part(model, "Handle", Vector3.new(0.35, 5, 0.35), origin * CFrame.new(0, 2.5, 0), DARK)
	part(model, "Head", Vector3.new(2.6, 0.5, 0.2), origin * CFrame.new(1.1, 5.1, 0), weapon.Color, Enum.Material.Neon)
	part(model, "Edge", Vector3.new(2.2, 0.4, 0.15), origin * CFrame.new(2.3, 4.4, 0) * CFrame.Angles(0, 0, math.rad(-50)), weapon.Color, Enum.Material.Neon)
	part(model, "Edge2", Vector3.new(1.4, 0.3, 0.15), origin * CFrame.new(2.9, 3.4, 0) * CFrame.Angles(0, 0, math.rad(-80)), weapon.Color, Enum.Material.Neon)
	part(model, "Ring", Vector3.new(0.9, 0.9, 0.3), origin * CFrame.new(0, 5.1, 0), GOLD)
	return handle
end

builders.StarAuraSword = function(model, origin, weapon)
	local handle = sword(model, origin, 4.2, 1.1, weapon.Color, true, GOLD)
	part(model, "Core", Vector3.new(0.3, 3.6, 0.2), origin * CFrame.new(0, 3.6, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	for i = 1, 3 do
		part(model, "Star" .. i, Vector3.new(0.6, 0.6, 0.25), origin * CFrame.new(0, 2 + i * 1.1, 0) * CFrame.Angles(0, 0, math.rad(45)), GOLD, Enum.Material.Neon)
	end
	return handle
end

-- Returns a Model named after the weapon, PrimaryPart "Handle".
function WeaponBuilder.Build(weapon): Model
	local model = Instance.new("Model")
	model.Name = weapon.Id
	local origin = CFrame.new()
	local build = builders[weapon.Id] or builders.IronSword
	local handle = build(model, origin, weapon)
	model.PrimaryPart = handle
	weldAll(model, handle)
	return model
end

-- Total length along +Y (for placing on pedestals / in viewports).
function WeaponBuilder.Length(model: Model): number
	return model:GetExtentsSize().Y
end

function WeaponBuilder.SetAnchored(model: Model, anchored: boolean)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = anchored
		end
	end
end

return WeaponBuilder
