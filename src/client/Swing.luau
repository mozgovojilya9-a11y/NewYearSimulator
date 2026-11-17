--[[
	Swing.luau
	Weapon swing for every character. The server bumps a character's
	"Swing" attribute on every accepted click, trainer tick and hit, so
	all clients see everyone's swings; the local player also swings at
	once on their own click (Swing.Local) so it feels instant.

	Procedural: every frame (RunService.Stepped, after the Animator)
	the right shoulder (R6 "Right Shoulder", R15 "RightShoulder"; Motor6D
	or AnimationConstraint) gets a rotation through its Transform:
	base -> wind-up -> strike -> base; the torso leans via the root
	joint. C0 is never written (read-only in new rigs). The weapon's
	Trail is switched on during the swing. Three variants play in turn: overhead, horizontal, thrust
	(Config.Animations.Swing). If Config.Animations.SwingIds has ids,
	those animations are played instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local S = Config.Animations.Swing

local Swing = {}

local active = {} -- [character] = { started, variant, shoulder, root }
local swinging = {} -- [character] = true
local variantOf = {} -- [character] = index of the next variant
local tracks = {} -- [character] = { AnimationTrack }

local function findJoint(character, names)
	for _, name in ipairs(names) do
		local joint = character:FindFirstChild(name, true)
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			return joint
		end
	end
	return nil
end

-- R15 "RightShoulder" / "Root", R6 "Right Shoulder" / "RootJoint".
-- Motor6D or (new avatar joints) AnimationConstraint: both have Transform.
local function joints(character)
	return findJoint(character, { "RightShoulder", "Right Shoulder" }), findJoint(character, { "Root", "RootJoint" })
end

-- Rotation of the joint frame inside its parent part (C0 for a Motor6D,
-- Attachment0 for an AnimationConstraint). Only READ, never written.
local function jointRotation(joint): CFrame
	if joint:IsA("Motor6D") then
		return joint.C0.Rotation
	end
	local attachment = joint.Attachment0
	return if attachment then attachment.CFrame.Rotation else CFrame.identity
end

-- Transform offset that turns the joint's child by `world` (a rotation
-- in the parent part's space) whatever the joint's own axes are.
local function offsetFor(joint, world: CFrame): CFrame
	local r = jointRotation(joint)
	return r:Inverse() * world * r
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
	active[character] = {
		started = os.clock(),
		variant = S.Variants[index],
		shoulder = shoulder,
		root = rootJoint,
	}
	task.wait(S.WindSeconds + S.StrikeSeconds + S.ReturnSeconds)
	swinging[character] = nil
end

---------------------------------------------------------------------
-- Procedural pose, applied every frame on top of the Animator
---------------------------------------------------------------------

local function quadOut(t)
	return 1 - (1 - t) * (1 - t)
end
local function quadIn(t)
	return t * t
end

-- Arm and torso rotations (parent space) at time t of a swing, or nil
-- when the swing is over.
local function sample(swing, t: number): (CFrame?, CFrame?)
	local v = swing.variant
	local wind, strike = pose(v.Wind), pose(v.Strike)
	local leanWind = CFrame.Angles(math.rad(v.Lean * 0.4), math.rad(-(v.Twist or 0)), 0)
	local leanStrike = CFrame.Angles(math.rad(-v.Lean), math.rad(v.Twist or 0), 0)
	if t < S.WindSeconds then
		local a = quadOut(t / S.WindSeconds)
		return CFrame.identity:Lerp(wind, a), CFrame.identity:Lerp(leanWind, a)
	end
	t -= S.WindSeconds
	if t < S.StrikeSeconds then
		local a = quadIn(t / S.StrikeSeconds)
		return wind:Lerp(strike, a), leanWind:Lerp(leanStrike, a)
	end
	t -= S.StrikeSeconds
	if t < S.ReturnSeconds then
		local a = quadOut(t / S.ReturnSeconds)
		return strike:Lerp(CFrame.identity, a), leanStrike:Lerp(CFrame.identity, a)
	end
	return nil, nil
end

-- The Animator rewrites Transform each frame while it plays something;
-- when it does not, our last value would stay and pile up. Remember
-- what we wrote and what the Animator's own value was.
local written = {} -- [joint] = { mine = CFrame, base = CFrame }

local function apply(joint, rotation: CFrame?)
	if not joint or not joint.Parent then
		return
	end
	local record = written[joint]
	local current = joint.Transform
	local base = if record and current:FuzzyEq(record.mine, 1e-4) then record.base else current
	if rotation then
		local mine = offsetFor(joint, rotation) * base
		joint.Transform = mine
		written[joint] = { mine = mine, base = base }
	else
		joint.Transform = base
		written[joint] = nil
	end
end

RunService.Stepped:Connect(function()
	local now = os.clock()
	for character, swing in pairs(active) do
		local arm, lean = sample(swing, now - swing.started)
		apply(swing.shoulder, arm)
		apply(swing.root, lean)
		if not arm or not character.Parent then
			active[character] = nil
		end
	end
end)

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
		for _, track in pairs(tracks[character] or {}) do
			track:Stop(0)
			track:Destroy()
		end
		tracks[character] = nil
		lastSeen[character] = nil
		active[character] = nil
	end)
end

-- Guard against "AnimationTrack limit of 64 tracks exceeded": whatever
-- plays animations on a rig (default Animate, emotes, owner models), an
-- Animator never keeps more than MaxTracks playing; the oldest one-shot
-- tracks are stopped and destroyed first (looped idle/walk survive).
local MAX_TRACKS = Config.Animations.MaxTracks or 24
local function guardAnimator(animator: Animator)
	local order = {} -- tracks in the order they started
	animator.AnimationPlayed:Connect(function(track)
		table.insert(order, track)
		local playing = animator:GetPlayingAnimationTracks()
		if #playing <= MAX_TRACKS then
			if #order > MAX_TRACKS * 2 then
				order = playing -- drop finished ones from the list
			end
			return
		end
		local excess = #playing - MAX_TRACKS
		local kept = {}
		for _, old in ipairs(order) do
			if excess > 0 and old ~= track and not old.Looped and old.IsPlaying then
				old:Stop(0)
				old:Destroy()
				excess -= 1
			elseif old.IsPlaying then
				table.insert(kept, old)
			end
		end
		order = kept
	end)
end
local function guardCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if animator then
		guardAnimator(animator)
	end
end

local function watchPlayer(other)
	if other.Character then
		task.spawn(guardCharacter, other.Character)
	end
	other.CharacterAdded:Connect(function(character)
		task.spawn(guardCharacter, character)
	end)
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
-- Hitstop: every running swing holds its pose for `seconds`.
function Swing.Freeze(seconds: number)
	for _, swing in pairs(active) do
		swing.started += seconds
	end
end

function Swing.Local()
	lastLocal = os.clock()
	if player.Character then
		Style.PlaySound(Config.Sounds.Swing, 1.25 + (math.random() - 0.5) * 0.2, 0.18)
		task.spawn(play, player.Character)
	end
end

return Swing
