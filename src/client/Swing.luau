--[[
	Swing.luau
	Fight animations of every character. The server sets the character's
	"Act" attribute ("Combo2#57": the action and a counter) on every
	attack, ability, dash and hit taken, so all clients see everyone's
	moves; the local player plays its own attacks at once on the click
	(Swing.Local) so they feel instant, and the echo is skipped.

	Act -> clip: Config.Animations.Acts[class][act] (or .Shared) names a
	clip of Config.Animations.Clips. A generated clip plays only its
	working part From..To squeezed into Seconds (R15 only). Without a clip
	(no id, R6 rig) the procedural swing plays: the right shoulder and the
	torso through Motor6D.Transform (C0 is never written). The weapon's
	Trail is on during melee moves.

	Also: the class idle stance (looped) while standing with a weapon, the
	block pose held while "Blocking", and the AnimationTrack guard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)

local player = Players.LocalPlayer
local A = Config.Animations
local S = A.Swing
local CB = Config.Combat

local Swing = {}

local MELEE = { Combo1 = true, Combo2 = true, Combo3 = true, Strike = true, Stun = true, Wave = true, Spin = true, Quake = true, Trap = true }
local PROCEDURAL_VARIANT = { Combo1 = 2, Combo2 = 3, Combo3 = 1, Shot1 = 3, Shot2 = 3, Charged = 3, Strike = 1, Stun = 3, Wave = 2, Spin = 2, Quake = 1 }

local chars = {} -- [character] = state
local active = {} -- [character] = procedural swing { started, variant, shoulder, root }

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function ownerClass(character): string
	local owner = Players:GetPlayerFromCharacter(character)
	return owner and owner:GetAttribute("Class") or ""
end

local function clipFor(character, act: string)
	local acts = A.Acts[ownerClass(character)]
	local name = (acts and acts[act]) or A.Acts.Shared[act]
	local clip = name and A.Clips[name]
	return clip, name
end

-- The slash itself (22.11): a glowing crescent in the class color drawn
-- at the strike moment - an arc of short neon blades that sweeps in, then
-- widens and fades. Combo3 / Spin = a wide (Pulse: full circle) slash,
-- a spear thrust = a straight stab. Config.Combat.Slash.
local SL = CB.Slash
local slashFolder = Instance.new("Folder")
slashFolder.Name = "SlashFx"
slashFolder.Parent = workspace

local function slashArc(character, act: string)
	if Style.HideEffects or not SL then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local class = ownerClass(character)
	local def = Config.ClassById[class]
	local color = def and def.Color or Config.Theme.Cyan
	local shape = (SL.Shapes[class] and SL.Shapes[class][act]) or SL.Shapes.Default[act] or SL.Shapes.Default.Combo1
	local base = root.CFrame * CFrame.new(0, shape.Height or 0.3, 0) * CFrame.Angles(0, 0, math.rad(shape.Tilt or 0))
	local blades = {}
	if shape.Stab then
		-- a straight stab forward
		local length = shape.Radius
		local core = Instance.new("Part")
		core.Anchored, core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow = true, false, false, false, false
		core.Material = Enum.Material.Neon
		core.Color = color
		core.Size = Vector3.new(0.35, 0.35, length)
		core.CFrame = base * CFrame.new(0, 0, -length / 2 - 1)
		core.Transparency = 0.1
		core.Parent = slashFolder
		table.insert(blades, core)
	else
		local count = shape.Count or 14
		local from, to = math.rad(shape.From), math.rad(shape.To)
		local radius = shape.Radius
		local step = (to - from) / count
		for i = 0, count - 1 do
			local a = from + step * (i + 0.5)
			local t = i / math.max(1, count - 1)
			local blade = Instance.new("Part")
			blade.Anchored, blade.CanCollide, blade.CanQuery, blade.CanTouch, blade.CastShadow = true, false, false, false, false
			blade.Material = Enum.Material.Neon
			blade.Color = color:Lerp(Color3.new(1, 1, 1), 0.35 * (1 - math.abs(t - 0.5) * 2))
			-- thicker in the middle of the arc, thin at the ends (a crescent)
			local thick = (shape.Thick or 0.5) * (0.35 + 0.65 * math.sin(t * math.pi))
			blade.Size = Vector3.new(0.12, thick, radius * math.abs(step) * 1.4)
			blade.CFrame = base * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -radius) * CFrame.Angles(0, math.rad(90), 0)
			blade.Transparency = 1
			blade.Parent = slashFolder
			blades[i + 1] = blade
			-- sweep in, blade after blade
			task.delay(SL.Sweep * t, function()
				if blade.Parent then
					blade.Transparency = 0.05
				end
			end)
		end
	end
	task.delay(SL.Sweep, function()
		for _, blade in ipairs(blades) do
			Style.Tween(blade, SL.Fade, { Transparency = 1, Size = blade.Size * Vector3.new(1, 0.3, 1.3) })
		end
		task.delay(SL.Fade + 0.05, function()
			for _, blade in ipairs(blades) do
				blade:Destroy()
			end
		end)
	end)
end

local function setTrail(character, enabled: boolean)
	local weapon = character:FindFirstChild("EquippedWeapon")
	local handle = weapon and weapon:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail")
	if trail then
		trail.Enabled = enabled
	end
end

local function stateOf(character)
	local s = chars[character]
	if not s then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		s = {
			humanoid = humanoid,
			animator = humanoid and humanoid:FindFirstChildOfClass("Animator"),
			r15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15,
			tracks = {}, -- [clip name] = AnimationTrack
			current = nil, -- { track, ends }
			idle = nil, -- { name, track }
			busyUntil = 0,
		}
		chars[character] = s
	end
	return s
end

-- Loaded track of a clip (R15 + id), or nil.
local function trackOf(character, name: string?, clip)
	if not name or not clip or (clip.Id or "") == "" then
		return nil
	end
	local s = stateOf(character)
	if not s.r15 then
		return nil
	end
	if not s.animator or not s.animator.Parent then
		s.animator = s.humanoid and s.humanoid:FindFirstChildOfClass("Animator")
		if not s.animator then
			return nil
		end
	end
	local track = s.tracks[name]
	if track == false then
		return nil
	end
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = clip.Id
		local ok, loaded = pcall(s.animator.LoadAnimation, s.animator, animation)
		if not ok or not loaded then
			s.tracks[name] = false
			return nil
		end
		track = loaded
		track.Looped = clip.Loop == true
		track.Priority = if clip.Loop then Enum.AnimationPriority.Idle elseif clip.Hold then Enum.AnimationPriority.Action3 else Enum.AnimationPriority.Action2
		s.tracks[name] = track
	end
	return track
end

---------------------------------------------------------------------
-- Procedural swing (fallback)
---------------------------------------------------------------------

local function findJoint(character, names)
	for _, name in ipairs(names) do
		local joint = character:FindFirstChild(name, true)
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			return joint
		end
	end
	return nil
end

local function jointRotation(joint): CFrame
	if joint:IsA("Motor6D") then
		return joint.C0.Rotation
	end
	local attachment = joint.Attachment0
	return if attachment then attachment.CFrame.Rotation else CFrame.identity
end

local function offsetFor(joint, world: CFrame): CFrame
	local r = jointRotation(joint)
	return r:Inverse() * world * r
end

local function pose(key): CFrame
	return CFrame.Angles(0, math.rad(key.Yaw or 0), 0) * CFrame.Angles(math.rad(key.Pitch or 0), 0, 0)
end

local function quadOut(t)
	return 1 - (1 - t) * (1 - t)
end
local function quadIn(t)
	return t * t
end

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
-- when it does not, our last value would stay and pile up.
local written = {} -- [joint] = { mine, base }

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

local function procedural(character, act: string)
	local index = PROCEDURAL_VARIANT[act]
	if not index then
		return
	end
	local shoulder = findJoint(character, { "RightShoulder", "Right Shoulder" })
	if not shoulder then
		return
	end
	active[character] = {
		started = os.clock(),
		variant = S.Variants[index],
		shoulder = shoulder,
		root = findJoint(character, { "Root", "RootJoint" }),
	}
end

---------------------------------------------------------------------
-- Playing an action
---------------------------------------------------------------------

local function stopIdle(s)
	if s.idle then
		s.idle.track:Stop(0.15)
		s.idle = nil
	end
end

local function play(character, act: string)
	if not character.Parent then
		return
	end
	local s = stateOf(character)
	local clip, name = clipFor(character, act)
	local seconds = if clip and clip.Seconds then clip.Seconds else S.WindSeconds + S.StrikeSeconds + S.ReturnSeconds
	-- a flinch never cuts an attack or an ability
	if act == "Hurt" and os.clock() < s.busyUntil then
		return
	end
	if MELEE[act] then
		-- the crescent appears at the clip's strike moment
		local strikeAt = if clip and clip.Hit then (clip.Hit - clip.From) / math.max(0.05, (clip.To - clip.From) / math.max(0.05, clip.Seconds)) else S.WindSeconds
		task.delay(strikeAt * 0.85, slashArc, character, act)
		setTrail(character, true)
		task.delay(math.max(S.TrailSeconds, seconds), function()
			if character.Parent then
				setTrail(character, false)
			end
		end)
	end
	if act ~= "Hurt" then
		s.busyUntil = os.clock() + seconds
	end
	local track = trackOf(character, name, clip)
	if not track then
		procedural(character, act)
		return
	end
	stopIdle(s)
	if s.current and s.current.track ~= track and s.current.track.IsPlaying then
		s.current.track:Stop(0.06)
	end
	local speed = (clip.To - clip.From) / math.max(0.05, clip.Seconds)
	track:Play(0.06, 1, speed)
	track.TimePosition = clip.From
	local entry = { track = track }
	s.current = entry
	task.delay(clip.Seconds, function()
		if s.current ~= entry then
			return
		end
		if clip.Hold and s.busyUntil == math.huge then
			track:AdjustSpeed(0) -- held (block) until released
			return
		end
		track:Stop(0.15)
		s.current = nil
	end)
end

-- Block: the pose is held while the owner's "Blocking" is on.
local function setBlock(character, on: boolean)
	local s = stateOf(character)
	if on then
		play(character, "Block")
		s.busyUntil = math.huge
	else
		s.busyUntil = 0
		local clip, name = clipFor(character, "Block")
		local track = trackOf(character, name, clip)
		if track and track.IsPlaying then
			track:Stop(0.15)
		end
		if s.current and s.current.track == track then
			s.current = nil
		end
	end
end

---------------------------------------------------------------------
-- Idle stance with the weapon (looped, Idle priority: walking wins)
---------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(0.2)
		local now = os.clock()
		for character, s in pairs(chars) do
			if not character.Parent then
				chars[character] = nil
				continue
			end
			local humanoid = s.humanoid
			local standing = humanoid and humanoid.Health > 0 and humanoid.MoveDirection.Magnitude < 0.1
				and character:FindFirstChild("EquippedWeapon") ~= nil and now >= s.busyUntil
			local clip, name = clipFor(character, "Idle")
			if standing and clip then
				if not s.idle or s.idle.name ~= name then
					stopIdle(s)
					local track = trackOf(character, name, clip)
					if track then
						track:Play(0.3)
						s.idle = { name = name, track = track }
					end
				end
			elseif s.idle then
				stopIdle(s)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Watching characters
---------------------------------------------------------------------

local lastLocal = {} -- [act] = os.clock() of the local prediction

local function watch(character)
	stateOf(character)
	local owner = Players:GetPlayerFromCharacter(character)
	character:GetAttributeChangedSignal("Act"):Connect(function()
		local value = character:GetAttribute("Act")
		local act = type(value) == "string" and value:match("^([^#]+)")
		if not act then
			return
		end
		-- the local player already played this attack on click
		if character == player.Character and os.clock() - (lastLocal[act] or 0) < 0.4 then
			return
		end
		task.spawn(play, character, act)
	end)
	if owner then
		owner:GetAttributeChangedSignal("Blocking"):Connect(function()
			if owner.Character == character then
				setBlock(character, owner:GetAttribute("Blocking") == true)
			end
		end)
	end
	character.Destroying:Connect(function()
		local s = chars[character]
		if s then
			for _, track in pairs(s.tracks) do
				if track then
					track:Stop(0)
					track:Destroy()
				end
			end
		end
		chars[character] = nil
		active[character] = nil
	end)
end

-- Guard against "AnimationTrack limit of 64 tracks exceeded": an
-- Animator never keeps more than MaxTracks playing; the oldest one-shot
-- tracks are stopped and destroyed first (looped idle/walk survive).
local MAX_TRACKS = A.MaxTracks or 24
local function guardAnimator(animator: Animator)
	local order = {}
	animator.AnimationPlayed:Connect(function(track)
		table.insert(order, track)
		local playing = animator:GetPlayingAnimationTracks()
		if #playing <= MAX_TRACKS then
			if #order > MAX_TRACKS * 2 then
				order = playing
			end
			return
		end
		local excess = #playing - MAX_TRACKS
		local kept = {}
		for _, old in ipairs(order) do
			if excess > 0 and old ~= track and not old.Looped and old.IsPlaying then
				old:Stop(0)
				excess -= 1
			elseif old.IsPlaying then
				table.insert(kept, old)
			end
		end
		order = kept
	end)
end

local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if animator then
		guardAnimator(animator)
	end
	watch(character)
end

local function watchPlayer(other)
	if other.Character then
		task.spawn(onCharacter, other.Character)
	end
	other.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, character)
	end)
end
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)

---------------------------------------------------------------------
-- API
---------------------------------------------------------------------

-- Hitstop: running procedural swings hold their pose for `seconds`
-- (animation tracks are paused by Combat).
function Swing.Freeze(seconds: number)
	for _, swing in pairs(active) do
		swing.started += seconds
	end
end

-- The local player's attack, predicted on the click: the same combo
-- step the server will count (Config.Combat[class].ComboWindow).
local combo, lastAttack, shots = 0, 0, 0
function Swing.Local(charged: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local class = player:GetAttribute("Class") or ""
	local act
	if class == "Gunner" then
		act = if charged then "Charged" elseif shots % 2 == 0 then "Shot1" else "Shot2"
		shots += 1
	else
		local def = CB[class]
		local now = os.clock()
		combo = if def and now - lastAttack <= def.ComboWindow then combo % 3 + 1 else 1
		lastAttack = now
		act = "Combo" .. combo
	end
	lastLocal[act] = os.clock()
	if class == "Gunner" then
		Style.PlaySound(Config.Sounds.GunShot, (if charged then 1.1 else 1.6) + (math.random() - 0.5) * 0.15, if charged then 0.5 else 0.3)
	else
		Style.PlaySound(Config.Sounds.Swing, 1.25 + (math.random() - 0.5) * 0.2 - (if act == "Combo3" then 0.25 else 0), 0.22)
	end
	task.spawn(play, character, act)
	return act
end

-- The local combo step that was just played (Combat uses it for juice).
function Swing.Step(): number
	return combo
end

return Swing
