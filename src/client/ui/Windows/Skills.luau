--[[
	Skills.luau
	Skill tree window ([K]). Placeholder until the class trees exist:
	shows the unspent skill points.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Style = require(script.Parent.Parent.Style)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local C = Style.Colors

local Skills = {}

local window = Window.new("Навыки", C.Gold, Vector2.new(560, 300), "skills")
local label = Style.Label(window.Content, "", 18, C.Text, { Size = UDim2.fromScale(1, 1), TextWrapped = true, ZIndex = 34 })

local function refresh()
	label.Text = ("Очков навыков: %d\nДерево навыков класса появится здесь."):format(player:GetAttribute("SkillPoints") or 0)
end
player:GetAttributeChangedSignal("SkillPoints"):Connect(refresh)
refresh()

Skills.Window = window
Skills.Open = window.Open
Skills.Toggle = window.Toggle

local _ = ReplicatedStorage
return Skills
