--[[
	MobFx.luau
	Client-side mob feedback: a red Highlight while a mob telegraphs an
	attack (model attribute "Telegraph" set by the server MobAI).
]]

local Workspace = game:GetService("Workspace")

local Style = require(script.Parent.ui.Style)

local MobFx = {}

local lanes = Workspace:WaitForChild("Dungeon"):WaitForChild("Lanes")

local function watch(model: Model)
	local highlight
	model:GetAttributeChangedSignal("Telegraph"):Connect(function()
		if model:GetAttribute("Telegraph") then
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.FillColor = Style.Colors.Red
				highlight.FillTransparency = 0.35
				highlight.OutlineColor = Style.Colors.Red
				highlight.OutlineTransparency = 0
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = model
			end
		elseif highlight then
			highlight:Destroy()
			highlight = nil
		end
	end)
end

lanes.DescendantAdded:Connect(function(instance)
	if instance:IsA("Humanoid") and instance.Parent then
		watch(instance.Parent)
	end
end)
for _, instance in ipairs(lanes:GetDescendants()) do
	if instance:IsA("Humanoid") and instance.Parent then
		watch(instance.Parent)
	end
end

return MobFx
