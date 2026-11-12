--[[
	Swing.luau
	Weapon swing for every character. The server bumps a character's
	"Swing" attribute on every accepted click, trainer tick and hit, so
	all clients see everyone's swings; the local player also swings at
	once on their own click (Swing.Local) so it feels instant.

	Procedural: the right shoulder Motor6D (R6 "Right Shoulder", R15
	"RightShoulder") is tweened base -> wind-up -> strike -> base, the
	torso leans via the root joint, and the weapon's Trail is switched
	on. Three variants play in turn: overhead, horizontal, thrust
	(Config.Animations.Swing). If Config.Animations.SwingIds has ids,
	those animations are played instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local S = Config.Animations.Swing

local Swing = {}

local baseC0 = {} -- [motor] = original C0
local swinging = {} -- [character] = true
local variantOf = {} -- [character] = index of the next variant
local tracks = {} -- [character] = { AnimationTrack }

local function joints(character)
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		local lowerTorso = character:FindFirstChild("LowerTorso")
		return upperArm:FindFirstChild("RightShoulder"), lowerTorso and lowerTorso:FindFirstChild("Root")
	end
	local torso = character:FindFirstChild("Torso")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return torso and torso:FindFirstChild("Right Shoulder"), rootPart and rootPart:FindFirstChild("RootJoint")
end

-- C0 that turns the joint's child by `world` (a rotation in the parent
-- part's space) whatever the joint's own axes are (R6 joints are rotated).
local function rotated(base: CFrame, world: CFrame): CFrame
	local r = base.Rotation
	return base * (r:Inverse() * world * r)
end

local function pose(key): CFrame
	return CFrame.Angles(0, math.rad(key.Yaw or 0), 0) * CFrame.Angles(math.rad(key.Pitch or 0), 0, 0)
end

local function setTrail(character, enabled: boolean)
	local weapon = character:FindFirstChild("EquippedWeapon")
	local handle = weapon and weapon:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail")
	if trail then
		trail.Enabled = enabled
	end
end

-- Uploaded animations (optional).
local function playUploaded(character, index: number): boolean
	local ids = Config.Animations.SwingIds
	if #ids == 0 then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	tracks[character] = tracks[character] or {}
	local slot = (index - 1) % #ids + 1
	local track = tracks[character][slot]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = ids[slot]
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if not ok then
			return false
		end
		track = loaded
		track.Priority = Enum.AnimationPriority.Action
		tracks[character][slot] = track
	end
	track:Play(0.05)
	return true
end

local function play(character)
	if swinging[character] then
		return
	end
	local index = variantOf[character] or 1
	variantOf[character] = index % #S.Variants + 1

	swinging[character] = true
	setTrail(character, true)
	task.delay(S.TrailSeconds, function()
		if character.Parent then
			setTrail(character, false)
		end
	end)

	if playUploaded(character, index) then
		task.wait(S.WindSeconds + S.StrikeSeconds + S.ReturnSeconds)
		swinging[character] = nil
		return
	end

	local shoulder, rootJoint = joints(character)
	if not shoulder then
		swinging[character] = nil
		return
	end
	local variant = S.Variants[index]
	baseC0[shoulder] = baseC0[shoulder] or shoulder.C0
	local armBase = baseC0[shoulder]
	local rootBase
	if rootJoint then
		baseC0[rootJoint] = baseC0[rootJoint] or rootJoint.C0
		rootBase = baseC0[rootJoint]
	end

	-- wind-up
	Style.Tween(shoulder, S.WindSeconds, { C0 = rotated(armBase, pose(variant.Wind)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if rootJoint then
		Style.Tween(rootJoint, S.WindSeconds, { C0 = rotated(rootBase, CFrame.Angles(math.rad(variant.Lean * 0.4), math.rad(-(variant.Twist or 0)), 0)) })
	end
	task.wait(S.WindSeconds)
	-- strike
	Style.Tween(shoulder, S.StrikeSeconds, { C0 = rotated(armBase, pose(variant.Strike)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if rootJoint then
		Style.Tween(rootJoint, S.StrikeSeconds, { C0 = rotated(rootBase, CFrame.Angles(math.rad(-variant.Lean), math.rad(variant.Twist or 0), 0)) })
	end
	task.wait(S.StrikeSeconds)
	-- back
	Style.Tween(shoulder, S.ReturnSeconds, { C0 = armBase }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if rootJoint then
		Style.Tween(rootJoint, S.ReturnSeconds, { C0 = rootBase })
	end
	task.wait(S.ReturnSeconds)
	swinging[character] = nil
end

local lastLocal = 0
local lastSeen = {} -- [character] = last Swing value handled

local function watch(character)
	lastSeen[character] = character:GetAttribute("Swing") or 0
	character:GetAttributeChangedSignal("Swing"):Connect(function()
		local value = character:GetAttribute("Swing") or 0
		if value == lastSeen[character] then
			return
		end
		lastSeen[character] = value
		-- The local player already played this swing on click.
		if character == player.Character and os.clock() - lastLocal < 0.3 then
			return
		end
		task.spawn(play, character)
	end)
	character.Destroying:Connect(function()
		swinging[character] = nil
		variantOf[character] = nil
		tracks[character] = nil
		lastSeen[character] = nil
	end)
end

local function watchPlayer(other)
	if other.Character then
		watch(other.Character)
	end
	other.CharacterAdded:Connect(watch)
end
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Instant local swing on our own click.
function Swing.Local()
	lastLocal = os.clock()
	if player.Character then
		Style.PlaySound(Config.Sounds.Swing, 1.25 + (math.random() - 0.5) * 0.2, 0.18)
		task.spawn(play, player.Character)
	end
end

return Swing
