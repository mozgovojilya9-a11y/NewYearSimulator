--[[
	Combat.luau
	The click. Every click / tap that is not on UI (and while no window
	is open) is sent to the server as ClickHit:FireServer(mob?) -- the
	mob under the cursor, if any. The server swings the weapon, hits a
	mob in the dungeon and answers with "Hit" / "Kill" / "Credits",
	which become popups, flashes, particles, sounds and camera shake here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)
local Swing = require(script.Parent.Swing)
local Window = require(script.Parent.ui.Windows.Window)

local player = Players.LocalPlayer

local Combat = {}

Combat.OnDummyHit = nil -- set by PolygonHud: (model, damage, isCrit)

local clickHit = ReplicatedStorage:WaitForChild("ClickHit")
local lanesFolder = Workspace:WaitForChild("Dungeon"):WaitForChild("Lanes")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { lanesFolder }

-- Hub: only the Polygon dummies can be targeted.
local hubParams = RaycastParams.new()
hubParams.FilterType = Enum.RaycastFilterType.Include
task.spawn(function()
	local hub = Workspace:WaitForChild("Hub")
	local polygon = hub:WaitForChild("Polygon", 30)
	if polygon then
		hubParams.FilterDescendantsInstances = { polygon }
	end
end)

local function dummyFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("Dummy") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local lastSent = 0

-- A mob is a Model with a Humanoid and a "Room" attribute.
local function mobFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("Room") and model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function click(ray: Ray, charged: boolean?)
	if Window.AnyOpen() then
		return
	end
	local now = os.clock()
	if now - lastSent < Config.Click.Cooldown / math.max(0.1, player:GetAttribute("Stat_AttackSpeed") or 1) then
		return
	end
	lastSent = now
	local target = nil
	if player:GetAttribute("Zone") == "Dungeon" then
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
		target = result and mobFromPart(result.Instance)
	elseif #hubParams.FilterDescendantsInstances > 0 then
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 300, hubParams)
		target = result and dummyFromPart(result.Instance)
	end
	Swing.Local()
	clickHit:FireServer(target, charged == true)
end

---------------------------------------------------------------------
-- Class controls: Q / E / R abilities, Shift dash, F block (Клинок),
-- held attack = charged shot (Стрелок). Phones: taps on the HUD slots.
---------------------------------------------------------------------

local abilityRemote = ReplicatedStorage:WaitForChild("Ability")
local CB = Config.Combat
local Hud = require(script.Parent.ui.Hud)

local function classId(): string
	return player:GetAttribute("Class") or ""
end

-- Point under the mouse (abilities aim there); nil on touch.
local function aimPoint(): Vector3?
	if Style.IsTouch() then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	return result and result.Position
end

local function useSlot(slot: string)
	if Window.AnyOpen() then
		return
	end
	if slot == "Dash" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			return
		end
		local direction = humanoid.MoveDirection
		if direction.Magnitude < 0.1 then
			direction = root.CFrame.LookVector
		end
		abilityRemote:FireServer("Dash", direction)
	elseif slot == "Block" then
		local on = not player:GetAttribute("Blocking")
		abilityRemote:FireServer("Block", on)
	else
		abilityRemote:FireServer("Use", slot, aimPoint())
		Swing.Local()
	end
end
Hud.OnAbility = useSlot

-- The server answers a dash with the distance: move our own character
-- (we own its physics) quickly along the direction.
abilityRemote.OnClientEvent:Connect(function(kind, direction, distance, seconds)
	if kind ~= "Dash" then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or typeof(direction) ~= "Vector3" then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / seconds)
	velocity.MaxForce = math.huge
	velocity.Parent = root
	Style.PlaySound("Swing", 1.4, 0.4)
	task.delay(seconds, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end)

-- A visible "press E" prompt (loot, NPC, station) wins over the E ability.
local ProximityPromptService = game:GetService("ProximityPromptService")
local shownPrompts = 0
ProximityPromptService.PromptShown:Connect(function(prompt)
	shownPrompts += 1
	prompt.PromptHidden:Once(function()
		shownPrompts = math.max(0, shownPrompts - 1)
	end)
end)

local chargeStart = nil -- os.clock() while the Стрелок holds the attack
local chargeRay = nil

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- the click landed on a button / window
	end
	for _, def in ipairs(Config.Ui.AbilitySlots) do
		if input.KeyCode == def.Key and not (input.KeyCode == Enum.KeyCode.E and shownPrompts > 0) then
			if def.Slot == "Block" then
				if classId() == "Blade" then
					abilityRemote:FireServer("Block", true)
				end
			else
				useSlot(def.Slot)
			end
			return
		end
	end
	local camera = Workspace.CurrentCamera
	local ray
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	end
	if not ray then
		return
	end
	if classId() == "Gunner" and not Window.AnyOpen() then
		chargeStart = os.clock()
		chargeRay = ray
		abilityRemote:FireServer("Charge")
		return
	end
	click(ray)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == CB.Block.Key and classId() == "Blade" then
		abilityRemote:FireServer("Block", false)
		return
	end
	if chargeStart and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		local held = os.clock() - chargeStart
		chargeStart = nil
		local camera = Workspace.CurrentCamera
		local ray = chargeRay
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mouse = UserInputService:GetMouseLocation()
			ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		end
		lastSent = 0 -- the press itself was not sent
		click(ray, held >= CB.Gunner.ChargeSeconds)
	end
end)

---------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------

local function flash(model, isCrit)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = if isCrit then Style.Colors.Gold else Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Style.Tween(highlight, 0.18, { FillTransparency = 1 })
	task.delay(0.18, function()
		highlight:Destroy()
	end)
end

local function hitParticles(position: Vector3, color: Color3, count: number)
	if Style.HideEffects then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	task.delay(1, function()
		attachment:Destroy()
	end)
end
Combat.Particles = hitParticles

local function topOf(model)
	return model:GetPivot().Position + Vector3.new(0, model:GetExtentsSize().Y / 2, 0)
end

local function headPosition(): Vector3?
	local head = player.Character and player.Character:FindFirstChild("Head")
	return head and head.Position + Vector3.new(0, 2.5, 0)
end

clickHit.OnClientEvent:Connect(function(kind, ...)
	if kind == "Hit" then
		local model, damage, isCrit = ...
		if not model or not model.Parent then
			return
		end
		Popups.World(topOf(model), (if isCrit then "КРИТ! " else "") .. Format.Number(damage), if isCrit then Style.Colors.Gold else Style.Colors.Text, if isCrit then 44 else 30, isCrit)
		flash(model, isCrit)
		hitParticles(model:GetPivot().Position, if isCrit then Style.Colors.Gold else Style.Colors.Orange, if isCrit then 16 else 7)
		Style.PlaySound(Config.Sounds.Hit, if isCrit then 0.8 else 1 + (math.random() - 0.5) * 0.2, 0.4)
		if isCrit then
			Popups.Shake(Config.Hud.ShakeCrit.Amplitude, Config.Hud.ShakeCrit.Seconds)
		end
	elseif kind == "Dummy" then
		local model, damage, isCrit = ...
		if model and model.Parent then
			Popups.World(topOf(model), (if isCrit then "КРИТ! " else "") .. Format.Number(damage), if isCrit then Style.Colors.Gold else Style.Colors.Text, if isCrit then 44 else 30, isCrit)
			hitParticles(model:GetPivot().Position, if isCrit then Style.Colors.Gold else Style.Colors.Cyan, if isCrit then 14 else 6)
			Style.PlaySound(Config.Sounds.Hit, if isCrit then 0.8 else 1 + (math.random() - 0.5) * 0.2, 0.35)
		end
		if Combat.OnDummyHit then
			Combat.OnDummyHit(model, damage, isCrit)
		end
	elseif kind == "Credits" then
		local amount, position = ...
		local at = if typeof(position) == "Vector3" then position + Vector3.new(0, 3, 0) else headPosition()
		if at then
			Popups.World(at, "+" .. Format.Number(amount) .. " кр.", Style.Colors.Gold, 26, false)
		end
	elseif kind == "Kill" then
		local position, isBoss = ...
		hitParticles(position, if isBoss then Style.Colors.Gold else Style.Colors.Magenta, if isBoss then 60 else 20)
		if isBoss then
			Popups.Shake(Config.Hud.ShakeBoss.Amplitude, Config.Hud.ShakeBoss.Seconds)
			Popups.Toast("Босс побеждён!", "gold")
			Style.PlaySound(Config.Sounds.BossDeath, 1, 0.8)
		end
	end
end)

return Combat
