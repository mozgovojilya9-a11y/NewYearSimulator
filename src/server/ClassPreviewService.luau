--[[
	ClassPreviewService.luau
	The class screen shows the player's OWN avatar in the class armor with
	the class weapon. Players:CreateHumanoidModelFromDescription works only
	on the server, so the server builds an R15 rig from the player's
	HumanoidDescription (Players:GetHumanoidDescriptionFromUserId) and puts
	it into ReplicatedStorage.ClassPreviews.<UserId>; the client clones it
	into a ViewportFrame + WorldModel and dresses / animates it there.
	If the avatar can't be loaded, a plain rigged R15 mannequin (default
	HumanoidDescription) is used instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassPreviewService = {}

local folder

local function strip(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
end

local function build(player)
	local description
	local ok = pcall(function()
		description = Players:GetHumanoidDescriptionFromUserId(math.max(1, player.UserId))
	end)
	if not ok or not description then
		description = Instance.new("HumanoidDescription") -- a plain mannequin
	end
	local model
	ok = pcall(function()
		model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		ok = pcall(function()
			model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
	end
	if not model or not player.Parent then
		return
	end
	strip(model)
	model.Name = tostring(player.UserId)
	model.Archivable = true
	model:PivotTo(CFrame.new(0, -500, 0))
	local old = folder:FindFirstChild(model.Name)
	if old then
		old:Destroy()
	end
	model.Parent = folder
end

function ClassPreviewService.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClassPreviews"
	folder.Parent = ReplicatedStorage
	Players.PlayerAdded:Connect(function(player)
		task.spawn(build, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(build, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local model = folder:FindFirstChild(tostring(player.UserId))
		if model then
			model:Destroy()
		end
	end)
end

return ClassPreviewService
