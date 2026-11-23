--[[
	ClassPreviewService.luau
	The class screen (sheet 03) shows the player's OWN avatar in the class
	armor: the server builds an R15 rig from the player's HumanoidDescription
	into ReplicatedStorage.ClassPreviews.<UserId>. The unique class
	characters stay as the fallback (and stand in the Academy):
	rigged R15 models in ServerStorage/GameAssets/Avatars named
	Config.Classes[i].Avatar (made with the Studio avatar generator). The
	server copies them, cleaned (no scripts, only the root anchored, an
	Animator added), into ReplicatedStorage.ClassPreviews.<ClassId>; the
	client clones them into a ViewportFrame + WorldModel and animates them.
	A missing model is replaced by a plain rigged R15 mannequin in the class
	colors (never blocks).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ClassPreviewService = {}

local function clean(model: Model)
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

-- A plain R15 mannequin painted in the class colors.
local function mannequin(class): Model?
	local description = Instance.new("HumanoidDescription")
	local main = class.Color:Lerp(Color3.fromRGB(40, 42, 50), 0.55)
	description.HeadColor = Color3.fromRGB(70, 72, 80)
	description.TorsoColor = main
	description.LeftArmColor = main
	description.RightArmColor = main
	description.LeftLegColor = Color3.fromRGB(46, 48, 56)
	description.RightLegColor = Color3.fromRGB(46, 48, 56)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	return if ok then model else nil
end

-- The player's own avatar as an R15 rig (sheet 03: the class preview is
-- the player in the class armor): ClassPreviews.<UserId>. Only the server
-- can build a rig from a HumanoidDescription.
local function buildAvatar(folder, player)
	local description
	local ok = pcall(function()
		description = Players:GetHumanoidDescriptionFromUserId(math.max(1, player.UserId))
	end)
	if not ok or not description then
		description = Instance.new("HumanoidDescription")
	end
	local model
	ok = pcall(function()
		model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model or not player.Parent then
		return
	end
	clean(model)
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
	local folder = Instance.new("Folder")
	folder.Name = "ClassPreviews"
	local source = ServerStorage:FindFirstChild("GameAssets") and ServerStorage.GameAssets:FindFirstChild("Avatars")
	for _, class in ipairs(Config.Classes) do
		local model
		local own = source and source:FindFirstChild(class.Avatar or "")
		if own and own:IsA("Model") and own:FindFirstChildOfClass("Humanoid") then
			own.Archivable = true
			model = own:Clone()
		else
			model = mannequin(class)
		end
		if model then
			clean(model)
			model.Name = class.Id
			model:PivotTo(CFrame.new(0, -500, 0))
			model.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
	Players.PlayerAdded:Connect(function(player)
		task.spawn(buildAvatar, folder, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(buildAvatar, folder, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local model = folder:FindFirstChild(tostring(player.UserId))
		if model then
			model:Destroy()
		end
	end)
end

return ClassPreviewService
