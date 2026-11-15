--[[
	Assets.luau
	Owner-made models: ServerStorage/GameAssets/<Category>/<Name>
	(categories Weapons, Armor, Mobs, Props, Trainers). At server start
	AssetService copies a CLEANED copy to ReplicatedStorage/GameAssets so
	the server builders and the client previews (ViewportFrames) can use
	them. Every function returns nil when the owner has no such model; the
	caller then builds its procedural fallback.

	Cleaning (Assets.Sanitize) keeps only what draws a model: parts,
	meshes, textures, attachments, joints, lights, particles. Scripts of
	any kind, Sounds and everything else (prompts, click detectors, GUIs,
	values, tools' logic) are removed, on the copy and on every clone.
	Tools and Folders are turned into Models (a Tool is only a source of
	parts: our code does the weapon logic).

	Rules per use:
	  Assets.Prop(name)          anchored, collisions as authored, for decor
	  Assets.Weapon(name, fit)   unanchored, no collision, massless, an
	                             invisible "Handle" at the grip with +Y along
	                             the weapon, scaled to fit.Length
	  Assets.Body(name, height)  unanchored, no collision, massless, scaled
	                             to `height`, for mob rigs (MobBuilder)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

-- Classes that may stay in a model (IsA checks, so subclasses count:
-- BasePart covers Part / MeshPart / UnionOperation / WedgePart ...).
local KEEP = {
	"BasePart", "Model", "Folder", "Attachment", "Decal", "Texture",
	"SurfaceAppearance", "DataModelMesh", "JointInstance",
	"WeldConstraint", "Bone", "Light", "ParticleEmitter",
	"Beam", "Trail", "Highlight", "BodyColors", "Shirt", "Pants",
	"Accessory", "WrapLayer", "WrapTarget",
}

local function allowed(instance: Instance): boolean
	if instance:IsA("LuaSourceContainer") or instance:IsA("Sound") or instance:IsA("SoundGroup") then
		return false -- never: scripts (any kind) and sounds
	end
	for _, className in ipairs(KEEP) do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

-- Removes everything that is not part of the look. Returns how many
-- instances were removed.
function Assets.Sanitize(root: Instance): number
	local removed = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d.Parent and not allowed(d) then
			d:Destroy()
			removed += 1
		end
	end
	return removed
end

local function source(category: string, name: string): Instance?
	local root = ReplicatedStorage:FindFirstChild("GameAssets")
	local folder = root and root:FindFirstChild(category)
	return folder and folder:FindFirstChild(name)
end

function Assets.Has(category: string, name: string?): boolean
	return name ~= nil and source(category, name) ~= nil
end

-- Tool / Folder / single part -> Model (children moved over).
local function asModel(instance: Instance): Model?
	if instance:IsA("Model") and not instance:IsA("Tool") and not instance:IsA("WorldModel") then
		return instance
	end
	local model = Instance.new("Model")
	model.Name = instance.Name
	if instance:IsA("BasePart") then
		instance.Parent = model
	else
		for _, child in ipairs(instance:GetChildren()) do
			child.Parent = model
		end
		instance:Destroy()
	end
	return model
end

local function parts(model: Instance): { BasePart }
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end
Assets.Parts = parts

-- Bounding box in the axes of the model's longest part. Weapons are
-- often built tilted (a spear lying diagonally); a world-axis box would
-- then take the box diagonal for the length and hold it crooked.
local function longestPart(list: { BasePart }): BasePart?
	local longest, best = nil, 0
	for _, p in ipairs(list) do
		local s = p.Size
		local m = math.max(s.X, s.Y, s.Z)
		if m > best then
			longest, best = p, m
		end
	end
	return longest
end

local function alignedBox(model: Model, reference: BasePart?): (CFrame, Vector3)
	local list = parts(model)
	local longest = reference or longestPart(list)
	if not longest then
		return model:GetBoundingBox()
	end
	local rot = longest.CFrame.Rotation
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in ipairs(list) do
		local half = p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local corner = p.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					local v = rot:PointToObjectSpace(corner)
					lo = lo:Min(v)
					hi = hi:Max(v)
				end
			end
		end
	end
	return rot + rot:PointToWorldSpace((lo + hi) / 2), hi - lo
end

-- A clean Model clone of GameAssets/<category>/<name>, or nil.
function Assets.Get(category: string, name: string?): Model?
	local src = name and source(category, name)
	if not src then
		return nil
	end
	local clone = src:Clone()
	Assets.Sanitize(clone)
	local model = asModel(clone)
	if not model or #parts(model) == 0 then
		if model then
			model:Destroy()
		end
		return nil
	end
	-- Upright, world-aligned pivot at the center, so bounding boxes are
	-- axis-aligned and nothing is placed tilted.
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new(model:GetBoundingBox().Position)
	return model
end

-- Size of a model's bounding box (nil when there is no such model).
function Assets.Size(category: string, name: string): Vector3?
	local model = Assets.Get(category, name)
	if not model then
		return nil
	end
	local _, size = model:GetBoundingBox()
	model:Destroy()
	return size
end

local function setAll(model: Instance, props: { [string]: any })
	for _, p in ipairs(parts(model)) do
		for key, value in pairs(props) do
			p[key] = value
		end
	end
end

-- Makes `model` hold together when unanchored: every part welded to `root`.
local function weldTo(model: Instance, root: BasePart)
	for _, p in ipairs(parts(model)) do
		if p ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		end
	end
end

-- Moves a model so its bounding box stands on `ground`: bottom center at
-- ground.Position, the model's front (-Z of its pivot) along ground's.
function Assets.PlaceOnGround(model: Model, ground: CFrame)
	local box, size = model:GetBoundingBox()
	local pivotFromBox = box:ToObjectSpace(model:GetPivot())
	model:PivotTo(ground * CFrame.new(0, size.Y / 2, 0) * pivotFromBox)
end

---------------------------------------------------------------------
-- Props / decor
---------------------------------------------------------------------

-- Anchored decor model. height (optional): scale so the box is this tall.
function Assets.Prop(name: string, height: number?): Model?
	local model = Assets.Get("Props", name) or Assets.Get("Trainers", name)
	if not model then
		return nil
	end
	setAll(model, { Anchored = true, CanTouch = false })
	if height then
		local _, size = model:GetBoundingBox()
		if size.Y > 0.05 then
			model:ScaleTo(model:GetScale() * height / size.Y)
		end
	end
	return model
end

---------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------

-- Guns (fit.Gun): held like a pistol, barrel forward, top up. The axes
-- come from the authored Handle (Tools) or the longest part: barrel =
-- its LookVector (muzzle side; fit.Flip swaps), top = its UpVector.
-- Owner meshes are built this way, a box can't tell top from bottom.
local function gunHold(model: Model, fit): Model?
	local ref = model:FindFirstChild("Handle", true)
	if not (ref and ref:IsA("BasePart")) then
		ref = longestPart(parts(model))
	end
	if not ref then
		model:Destroy()
		return nil
	end
	local box, size = alignedBox(model, ref)
	local tipDir = if fit.Flip then -ref.CFrame.LookVector else ref.CFrame.LookVector
	local up = ref.CFrame.UpVector
	local length = size.Z
	if length < 0.1 then
		model:Destroy()
		return nil
	end
	if ref.Name == "Handle" then
		ref.Name = "Grip"
	end
	local rear = box.Position - tipDir * length / 2
	local gripPoint = rear + tipDir * ((fit.GripAt or 0.3) * length) - up * (size.Y * (fit.GripDown or 0.2))
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.8, 0.3)
	handle.Transparency = 1
	handle.CFrame = CFrame.fromMatrix(gripPoint, tipDir:Cross(up).Unit, tipDir)
	handle.Parent = model
	model.PrimaryPart = handle
	setAll(model, { Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true })
	if fit.Length and fit.Length > 0 then
		model:ScaleTo(model:GetScale() * fit.Length / length)
	end
	weldTo(model, handle)
	return model
end

-- fit: { Length = studs, GripAt = 0..1 from the rear end (optional),
--        Flip = true to swap the tip and the grip end }
-- Returns a Model whose PrimaryPart is a new invisible "Handle" at the grip,
-- +Y pointing along the weapon (to the tip), every part welded to it.
function Assets.Weapon(name: string, fit): Model?
	local model = Assets.Get("Weapons", name)
	if not model then
		return nil
	end
	fit = fit or {}
	if fit.Gun then
		return gunHold(model, fit)
	end
	local box, size = alignedBox(model)
	-- longest axis of the box = the weapon's length
	local axes = { { box.RightVector, size.X }, { box.UpVector, size.Y }, { box.LookVector, size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	local axis, length = axes[1][1], axes[1][2]
	local side = axes[2][1]
	if length < 0.1 then
		model:Destroy()
		return nil
	end

	-- Which end is the grip: the authored Handle (Tools have one), else
	-- the end nearer to the bulk of the parts (guards, receivers).
	local oldHandle = model:FindFirstChild("Handle", true)
	local center = box.Position
	local toward
	if oldHandle and oldHandle:IsA("BasePart") then
		toward = oldHandle.Position
	else
		local sum, total = Vector3.zero, 0
		for _, p in ipairs(parts(model)) do
			local v = p.Size.X * p.Size.Y * p.Size.Z
			sum += p.Position * v
			total += v
		end
		toward = if total > 0 then sum / total else center
	end
	local tipDir = if (toward - center):Dot(axis) > 0 then -axis else axis
	if fit.Flip then
		tipDir = -tipDir
	end
	local rear = center - tipDir * length / 2
	local gripAt = fit.GripAt
	if not gripAt then
		if oldHandle and oldHandle:IsA("BasePart") then
			gripAt = math.clamp((oldHandle.Position - rear):Dot(tipDir) / length, 0, 0.6)
		else
			gripAt = 0.12
		end
	end
	if oldHandle then
		oldHandle.Name = "Grip" -- the new Handle below is the one we use
	end

	local right = side:Cross(tipDir)
	if right.Magnitude < 0.01 then
		right = tipDir:Cross(Vector3.new(0, 0, 1))
	end
	right = right.Unit
	local gripPoint = rear + tipDir * (gripAt * length)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.8, 0.3)
	handle.Transparency = 1
	handle.CFrame = CFrame.fromMatrix(gripPoint, right, tipDir)
	handle.Parent = model
	model.PrimaryPart = handle

	setAll(model, { Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true })
	if fit.Length and fit.Length > 0 then
		model:ScaleTo(model:GetScale() * fit.Length / length)
	end
	weldTo(model, handle)
	return model
end

---------------------------------------------------------------------
-- Mob bodies
---------------------------------------------------------------------

-- Names the Humanoid would treat as limbs: renamed so it does not fight
-- over their collisions.
local LIMB_NAMES = {
	Head = true, Torso = true, HumanoidRootPart = true, UpperTorso = true, LowerTorso = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftUpperLeg = true, RightUpperLeg = true,
}

-- Unanchored body scaled to `height` (studs), standing with its feet at
-- the model origin; parts keep their joints, collide with nothing.
-- Returns model, size (after scaling).
function Assets.Body(name: string, height: number): (Model?, Vector3?)
	local model = Assets.Get("Mobs", name)
	if not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("AnimationController") then
			d:Destroy()
		elseif d:IsA("BasePart") and LIMB_NAMES[d.Name] then
			d.Name = "Body_" .. d.Name:gsub(" ", "")
		end
	end
	local _, size = model:GetBoundingBox()
	if size.Y < 0.1 then
		model:Destroy()
		return nil
	end
	model:ScaleTo(model:GetScale() * height / size.Y)
	setAll(model, { Anchored = true, CanCollide = false, CanQuery = true, CanTouch = false, Massless = true })
	Assets.PlaceOnGround(model, CFrame.new())
	local _, scaled = model:GetBoundingBox()
	return model, scaled
end

return Assets
