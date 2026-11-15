--[[
	Training.luau
	Client side of the Training hall stations (TrainingService):
	  * while the player attribute Training = "<stationId>": a panel at the
	    bottom "Тренировка: <станция>" with a bar to the next XP tick and
	    the "Выйти" button (Space / Jump also exits);
	  * the exercise, played procedurally on the joints' Transform (never
	    C0; R6 and R15): press (both arms up), punches, squats, aiming;
	  * "+N XP" pops over the head on every tick (Training "Gain").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(script.Parent.ui.Style)
local Popups = require(script.Parent.ui.Popups)

local TR = Config.Training
local C = Style.Colors
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Training")

local byId = {}
for _, def in ipairs(TR.Stations) do
	byId[def.Id] = def
end

local Training = {}

---------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------

local panel = Style.Panel(Style.Gui, {
	Name = "TrainingPanel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(440, 92),
	ZIndex = 20,
	Border = C.GoldDim,
	Cut = 10,
	Visible = false,
})
local title = Style.Label(panel, "", 16, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -150, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
local hint = Style.Label(panel, TR.Texts.Hint:format(TR.Tick), 12, C.Muted, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -150, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 })
local _ = hint
local _, fill = Style.Bar(panel, { Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -150, 0, 8), Color = C.Gold, ZIndex = 21 })
local exit = Style.Button(panel, {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(116, 48),
	Text = Style.Upper(TR.Texts.Exit),
	Color = C.Card,
	TextSize = 16,
	ZIndex = 21,
})
exit.Activated:Connect(function()
	remote:FireServer("Stop")
end)

local current -- station id or nil
local started = 0

UserInputService.InputBegan:Connect(function(input, processed)
	if current and not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA) then
		remote:FireServer("Stop")
	end
end)
UserInputService.JumpRequest:Connect(function()
	if current then
		remote:FireServer("Stop")
	end
end)

remote.OnClientEvent:Connect(function(kind, xp)
	if kind == "Gain" then
		started = os.clock()
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head then
			Popups.World(head.Position + Vector3.new(0, 2, 0), TR.Texts.Gain:format(xp), C.Gold, 22)
		end
	end
end)

---------------------------------------------------------------------
-- Exercise on the joints (Motor6D or AnimationConstraint .Transform)
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
		return joint.C0.Rotation -- read only
	end
	local attachment = joint.Attachment0
	return if attachment then attachment.CFrame.Rotation else CFrame.identity
end

-- the Animator rewrites Transform while it plays; keep its base value
local written = {}
local function apply(joint, world: CFrame?)
	if not joint or not joint.Parent then
		return
	end
	local record = written[joint]
	local now = joint.Transform
	local base = if record and now:FuzzyEq(record.mine, 1e-4) then record.base else now
	if world then
		local r = jointRotation(joint)
		local mine = (r:Inverse() * world * r) * base
		joint.Transform = mine
		written[joint] = { mine = mine, base = base }
	else
		joint.Transform = base
		written[joint] = nil
	end
end

local joints = {}
local function bind(character)
	joints = {
		Right = findJoint(character, { "RightShoulder", "Right Shoulder" }),
		Left = findJoint(character, { "LeftShoulder", "Left Shoulder" }),
		Root = findJoint(character, { "Root", "RootJoint" }),
	}
end

local function arm(pitch: number, yaw: number?): CFrame
	return CFrame.Angles(math.rad(pitch), math.rad(yaw or 0), 0)
end

-- pose for station `id` at time t: right, left, root (CFrames in parent space)
local function poseFor(id: string, t: number)
	local s = (math.sin(t * math.pi * 2 / 1.6) + 1) / 2 -- 0..1, 1.6 s period
	if id == "Power" then
		local a = 60 + 110 * s -- press overhead
		return arm(a, 0), arm(a, 0), nil
	elseif id == "Dummy" then
		local phase = (t * 2.4) % 2
		local right = if phase < 1 then 90 * math.sin(phase * math.pi) else 20
		local left = if phase >= 1 then 90 * math.sin((phase - 1) * math.pi) else 20
		return arm(right + 10), arm(left + 10), CFrame.Angles(0, math.rad((phase < 1 and -1 or 1) * 10), 0)
	elseif id == "Gravity" then
		return arm(80 * s + 10), arm(80 * s + 10), CFrame.new(0, -1.1 * s, 0) * CFrame.Angles(math.rad(-12 * s), 0, 0)
	end
	-- Laser: aim with the right arm, small recoil, left arm supports
	local recoil = if (t % 1.2) < 0.12 then 8 else 0
	return arm(92 + recoil, 0), arm(80, -35), nil
end

RunService.Stepped:Connect(function()
	if not current then
		return
	end
	local t = os.clock() - started
	local right, left, root = poseFor(current, os.clock())
	apply(joints.Right, right)
	apply(joints.Left, left)
	apply(joints.Root, root)
	fill.Size = UDim2.fromScale(math.clamp(t / TR.Tick, 0, 1), 1)
end)

local function refresh()
	local id = player:GetAttribute("Training")
	local def = byId[id or ""]
	if def then
		current = def.Id
		started = os.clock()
		if player.Character then
			bind(player.Character)
		end
		title.Text = Style.Upper(TR.Texts.Panel:format(def.Name))
		panel.Visible = true
	else
		current = nil
		panel.Visible = false
		for _, joint in pairs(joints) do
			apply(joint, nil)
		end
	end
end
player:GetAttributeChangedSignal("Training"):Connect(refresh)
player.CharacterAdded:Connect(bind)
refresh()

return Training
