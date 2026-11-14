--[[
	Assets.luau
	Owner-made models from ServerStorage/GameAssets (folders Weapons,
	Armor, Mobs, Props, Trainers; model name = id from Config). The server
	(AssetService) copies a CLEANED copy to ReplicatedStorage/GameAssets
	at start, so clients can use them in previews too.

	Cleaning (Assets.Sanitize) keeps only what draws the model: parts,
	meshes, textures, attachments, joints, lights and particles. Scripts
	of any kind, Sounds and everything else (prompts, click detectors,
	GUIs, values...) are deleted, on the copy and again on every clone.

	Assets.Get(folder, id) -> a fresh clean clone, or nil when the owner
	has no such model (the caller then builds its procedural model).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

-- Classes that may stay in a model (IsA checks, so subclasses count:
-- BasePart covers Part / MeshPart / UnionOperation / WedgePart ...).
local KEEP = {
	"BasePart", "Model", "Folder", "Attachment", "Decal", "Texture",
	"SurfaceAppearance", "SpecialMesh", "DataModelMesh", "JointInstance",
	"WeldConstraint", "Motor6D", "Bone", "Light", "ParticleEmitter",
	"Beam", "Trail", "Highlight", "Humanoid", "AnimationController",
	"Animator", "BodyColors", "Shirt", "Pants", "Accessory", "WrapLayer",
	"WrapTarget",
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

-- Removes everything that is not part of the look. Returns the number of
-- removed instances (for the Output report).
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

-- A clean clone of GameAssets/<folder>/<id>, or nil.
function Assets.Get(folderName: string, id: string): Instance?
	local root = ReplicatedStorage:FindFirstChild("GameAssets")
	local folder = root and root:FindFirstChild(folderName)
	local source = folder and folder:FindFirstChild(id)
	if not source then
		return nil
	end
	local clone = source:Clone()
	Assets.Sanitize(clone)
	return clone
end

return Assets
