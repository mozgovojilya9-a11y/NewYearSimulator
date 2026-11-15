--[[
	Style.luau
	The one place for the UI look (reference style): dark graphite panels
	with cut corners and thin gold lines, dark buttons with a gold border,
	one gold "main" button style, monochrome line icons (ui/Icons), a dense
	bold font with Cyrillic. Colors / sizes: Config.Theme, Config.Ui.

	Root ScreenGui (respects the Roblox top-bar inset), mobile UIScale,
	helpers: Panel / Chamfer (cut-corner panel from Frames), Button,
	IconButton, Label, Plate, Card, Bar, sounds (Config.Sounds, replaced
	by GameAssets/Audio/<key> when the owner uploads one).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(script.Parent.Icons)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Style = {}

local C = Config.Theme
local U = Config.Ui
Style.Colors = C
Style.Font = C.Font
Style.FontTitle = C.FontTitle or C.Font
Style.Icons = Icons
Style.Muted = false -- sound toggle (Settings window)
Style.Shake = true
Style.HideEffects = false -- Settings: skip hit particles and other extras
Style.MusicOn = true -- Settings: background music (Config.Sounds.Music)

-- Root ScreenGui. IgnoreGuiInset is OFF so nothing lands under the
-- Roblox buttons in the top-left corner.
local gui = Instance.new("ScreenGui")
gui.Name = "AuraClickerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
Style.Gui = gui

-- Mobile: scale the whole HUD down on narrow screens.
local scale = Instance.new("UIScale")
scale.Parent = gui
Style.Scale = scale
local function refit()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / Config.Hud.MobileScaleWidth, viewport.Y / 620), 0.55, 1)
end
refit()
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)

-- UPPER CASE that also works for Cyrillic (string.upper is ASCII only).
function Style.Upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if code >= 0x430 and code <= 0x44F then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		elseif code >= 97 and code <= 122 then
			code -= 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

function Style.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------

function Style.Tween(instance, time, props, style, direction)
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

function Style.Lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Style.Darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Style.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 3)
	corner.Parent = parent
	return corner
end

function Style.Stroke(parent, thickness, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 1.5
	stroke.Color = color or C.Outline
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = parent
	return stroke
end

-- Subtle top-lighter vertical gradient.
function Style.Gradient(parent, color: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Style.Lighter(color, 0.12), Style.Darker(color, 0.18))
	gradient.Parent = parent
	return gradient
end

-- Animated rainbow gradient (secret rarity).
function Style.Rainbow(parent)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 120)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
	})
	gradient.Parent = parent
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not gradient.Parent then
			connection:Disconnect()
			return
		end
		gradient.Rotation = (os.clock() * 90) % 360
	end)
	return gradient
end

-- Kept for old callers: the flat reference style has no drop shadows.
function Style.Shadow(element, _offset: number?)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Visible = false
	shadow.Parent = element.Parent
	return shadow
end

---------------------------------------------------------------------
-- Cut-corner panel (no images): a body of three rects + four corner
-- triangles (a hard-edged transparency gradient at 45 degrees), the
-- border of eight thin lines. Pieces never overlap, so the panel can be
-- see-through. Content goes into the frame itself with a higher ZIndex.
---------------------------------------------------------------------

local CORNERS = {
	-- position (scale x, scale y, offset sign x, offset sign y), gradient rotation
	{ 0, 0, 0, 0, 45 },
	{ 1, 0, -1, 0, 135 },
	{ 0, 1, 0, -1, 315 },
	{ 1, 1, -1, -1, 225 },
}
local HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.49, 1),
	NumberSequenceKeypoint.new(0.51, 0),
	NumberSequenceKeypoint.new(1, 0),
})

local function piece(parent, name, z, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- Turns `frame` into a cut-corner panel. opts: Fill, Transparency, Border
-- (color or false), Thickness, Cut. Returns a table { SetFill, SetBorder }.
function Style.Chamfer(frame: GuiObject, opts)
	opts = opts or {}
	local cut = opts.Cut or U.Cut
	local fill = opts.Fill or C.Panel
	local transparency = opts.Transparency or 0
	local border = if opts.Border == nil then C.GoldDim else opts.Border
	local t = opts.Thickness or U.Border
	local z = frame.ZIndex
	frame.BackgroundTransparency = 1
	local shape = {}

	local body = {
		piece(frame, "_Mid", z, fill, transparency),
		piece(frame, "_Top", z, fill, transparency),
		piece(frame, "_Bottom", z, fill, transparency),
	}
	body[1].Position = UDim2.fromOffset(0, cut)
	body[1].Size = UDim2.new(1, 0, 1, -cut * 2)
	body[2].Position = UDim2.fromOffset(cut, 0)
	body[2].Size = UDim2.new(1, -cut * 2, 0, cut)
	body[3].Position = UDim2.new(0, cut, 1, -cut)
	body[3].Size = UDim2.new(1, -cut * 2, 0, cut)
	for _, c in ipairs(CORNERS) do
		local f = piece(frame, "_Corner", z, fill, transparency)
		f.Position = UDim2.new(c[1], c[3] * cut, c[2], c[4] * cut)
		f.Size = UDim2.fromOffset(cut, cut)
		local g = Instance.new("UIGradient")
		g.Rotation = c[5]
		g.Transparency = HALF
		g.Parent = f
		table.insert(body, f)
	end
	shape.Body = body

	local lines = {}
	if border then
		local function edge(pos: UDim2, size: UDim2)
			local f = piece(frame, "_Edge", z, border, 0)
			f.Position = pos
			f.Size = size
			table.insert(lines, f)
		end
		edge(UDim2.fromOffset(cut, 0), UDim2.new(1, -cut * 2, 0, t))
		edge(UDim2.new(0, cut, 1, -t), UDim2.new(1, -cut * 2, 0, t))
		edge(UDim2.fromOffset(0, cut), UDim2.new(0, t, 1, -cut * 2))
		edge(UDim2.new(1, -t, 0, cut), UDim2.new(0, t, 1, -cut * 2))
		local diag = cut * math.sqrt(2)
		for i, c in ipairs(CORNERS) do
			local f = piece(frame, "_Edge", z, border, 0)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.new(c[1], (if c[1] == 0 then 1 else -1) * cut / 2, c[2], (if c[2] == 0 then 1 else -1) * cut / 2)
			f.Size = UDim2.fromOffset(diag + t * 0.5, t)
			f.Rotation = if i == 1 or i == 4 then -45 else 45
			table.insert(lines, f)
		end
	end
	shape.Lines = lines

	function shape.SetFill(color: Color3, alpha: number?)
		for _, f in ipairs(body) do
			f.BackgroundColor3 = color
			if alpha then
				f.BackgroundTransparency = alpha
			end
		end
	end
	function shape.SetBorder(color: Color3)
		for _, f in ipairs(lines) do
			f.BackgroundColor3 = color
		end
	end
	function shape.SetTransparency(alpha: number)
		for _, f in ipairs(body) do
			f.BackgroundTransparency = alpha
		end
	end
	function shape.SetBorderTransparency(alpha: number)
		for _, f in ipairs(lines) do
			f.BackgroundTransparency = alpha
		end
	end
	return shape
end

-- New cut-corner panel. props: Name, Size, Position, AnchorPoint, ZIndex,
-- Fill, Transparency, Border, Cut, Thickness, LayoutOrder, Visible.
function Style.Panel(parent, props: { [string]: any }?)
	props = props or {}
	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Panel"
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.Position = props.Position or UDim2.new()
	frame.Size = props.Size or UDim2.fromOffset(200, 60)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = props.ZIndex or 1
	frame.LayoutOrder = props.LayoutOrder or 0
	if props.Visible ~= nil then
		frame.Visible = props.Visible
	end
	frame.Parent = parent
	local shape = Style.Chamfer(frame, {
		Fill = props.Fill or C.Panel,
		Transparency = props.Transparency or U.PanelTransparency,
		Border = props.Border,
		Cut = props.Cut,
		Thickness = props.Thickness,
	})
	return frame, shape
end

---------------------------------------------------------------------
-- Text
---------------------------------------------------------------------

function Style.Label(parent, text: string, size: number, color: Color3?, props: { [string]: any }?)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Style.Font
	label.TextSize = size
	label.TextColor3 = color or C.Text
	label.Text = text
	label.Size = UDim2.new(1, 0, 0, size + 6)
	for key, value in pairs(props or {}) do
		label[key] = value
	end
	label.Parent = parent
	Style.Stroke(label, math.max(1, size / 18), C.Outline)
	return label
end

---------------------------------------------------------------------
-- Buttons. Dark body + thin gold border; "main" colors (gold, green,
-- orange) become the one gold button style; red = a dark red danger
-- button. setColor(color) restyles (tabs: color = active, Card = idle).
---------------------------------------------------------------------

local function isMain(color: Color3): boolean
	return color == C.Gold or color == C.Green or color == C.Orange
end
local function isIdle(color: Color3): boolean
	if color == C.Card or color == C.CardDark then
		return true
	end
	-- old code passes greys for "disabled"
	local h, s, v = color:ToHSV()
	local _ = h
	return s < 0.18 and v < 0.7
end

-- (A UIGradient tints the text too, so it only shades from white to light
-- grey; the button color itself is the background.)
local SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
function Style.ButtonLook(button: GuiButton, stroke: UIStroke, gradient: UIGradient, color: Color3)
	gradient.Color = SHADE
	if isIdle(color) then
		button.BackgroundColor3 = C.CardDark
		stroke.Color = C.Line
		if button:IsA("TextButton") then
			button.TextColor3 = C.Muted
		end
	elseif isMain(color) then
		button.BackgroundColor3 = C.Gold
		stroke.Color = Color3.fromRGB(255, 226, 140)
		if button:IsA("TextButton") then
			button.TextColor3 = Color3.fromRGB(24, 20, 12)
		end
	elseif color == C.Red then
		button.BackgroundColor3 = Color3.fromRGB(84, 26, 28)
		stroke.Color = Color3.fromRGB(200, 70, 70)
		if button:IsA("TextButton") then
			button.TextColor3 = C.Text
		end
	else
		-- any accent: a dark button whose border carries a hint of it
		button.BackgroundColor3 = C.Card
		stroke.Color = C.GoldDim:Lerp(color, 0.25)
		if button:IsA("TextButton") then
			button.TextColor3 = C.Text
		end
	end
end

-- props: Size, Position, AnchorPoint, Color, Text, TextSize, ZIndex,
-- LayoutOrder, Name, Icon (line icon name, drawn left of the text).
function Style.Button(parent, props: { [string]: any })
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.Position = props.Position or UDim2.new()
	button.Size = props.Size or UDim2.fromOffset(120, 40)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Style.Font
	button.TextSize = math.min(props.TextSize or 18, 22)
	button.Text = props.Text or ""
	button.ZIndex = props.ZIndex or 2
	button.LayoutOrder = props.LayoutOrder or 0
	button.Parent = parent
	Style.Corner(button, UDim.new(0, 3))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = U.Border
	stroke.Parent = button
	local color = props.Color or C.Card
	Style.ButtonLook(button, stroke, gradient, color)
	if props.Icon then
		local icon = Icons.Make(button, props.Icon, math.floor(button.Size.Y.Offset * 0.5), button.TextColor3, button.ZIndex + 1)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, button.Size.Y.Offset * 0.5 + 8)
		pad.Parent = button
	end

	local pressScale = Instance.new("UIScale")
	pressScale.Parent = button
	button.MouseButton1Down:Connect(function()
		Style.Tween(pressScale, 0.06, { Scale = 0.96 })
	end)
	local function release()
		Style.Tween(pressScale, 0.12, { Scale = 1 })
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.MouseEnter:Connect(function()
		stroke.Thickness = U.Border + 0.5
	end)
	button.MouseLeave:Connect(function()
		stroke.Thickness = U.Border
	end)
	button.Activated:Connect(function()
		Style.PlaySound("Ui", 1, 0.35)
	end)

	local function setColor(newColor: Color3)
		Style.ButtonLook(button, stroke, gradient, newColor)
		local icon = button:FindFirstChild("Icon")
		if icon then
			Icons.Paint(icon, button.TextColor3)
		end
	end
	return button, setColor
end

-- Square icon button in a cut-corner frame (HUD bar, close, settings).
-- props: Size (px), Icon, Position, AnchorPoint, ZIndex, LayoutOrder,
-- Key (hotkey text shown in the corner), Name, Cut.
-- Returns button, { SetActive(bool), Badge(count|nil), Icon }.
function Style.IconButton(parent, props: { [string]: any })
	local size = props.Size or U.BarButton
	local z = props.ZIndex or 3
	local button = Instance.new("TextButton")
	button.Name = props.Name or "IconButton"
	button.AnchorPoint = props.AnchorPoint or Vector2.zero
	button.Position = props.Position or UDim2.new()
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = z
	button.LayoutOrder = props.LayoutOrder or 0
	button.Parent = parent
	local shape = Style.Chamfer(button, { Fill = C.PanelDark, Transparency = U.PanelTransparency, Border = C.GoldDim, Cut = props.Cut or U.CutSmall })
	local icon = Icons.Make(button, props.Icon or "circle", math.floor(size * 0.56), C.Text, z + 1)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	if props.Key and not Style.IsTouch() then
		local key = Style.Label(button, props.Key, 11, C.GoldDim, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.fromOffset(20, 12),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = z + 2,
		})
		key.Name = "Key"
	end
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -3, 0, 3)
	badge.Size = UDim2.fromOffset(18, 18)
	badge.BackgroundColor3 = Color3.fromRGB(196, 40, 40)
	badge.Font = Style.Font
	badge.TextSize = 12
	badge.TextColor3 = C.Text
	badge.Text = ""
	badge.ZIndex = z + 3
	badge.Visible = false
	badge.Parent = button
	Style.Corner(badge, UDim.new(0.5, 0))
	Style.Stroke(badge, 1, Color3.fromRGB(20, 6, 6))

	local hover = false
	local active = false
	local function look()
		shape.SetBorder(if active or hover then C.Gold else C.GoldDim)
		Icons.Paint(icon, if active then C.Gold else C.Text)
	end
	button.MouseEnter:Connect(function()
		hover = true
		look()
	end)
	button.MouseLeave:Connect(function()
		hover = false
		look()
	end)
	button.Activated:Connect(function()
		Style.PlaySound("Ui", 1, 0.35)
	end)
	local api = { Icon = icon, Shape = shape }
	function api.SetActive(on: boolean)
		active = on
		look()
	end
	function api.Badge(count: number?)
		if count and count > 0 then
			badge.Text = if count > 9 then "9+" else tostring(count)
			badge.Visible = true
		else
			badge.Visible = false
		end
	end
	return button, api
end

---------------------------------------------------------------------
-- Plates, cards, bars
---------------------------------------------------------------------

-- Dark cut-corner HUD plate (the text rule: light text on a dark plate).
function Style.Plate(parent, props: { [string]: any })
	local frame = Style.Panel(parent, {
		Name = props.Name or "Plate",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(200, 40),
		ZIndex = props.ZIndex or 1,
		Fill = if props.Color and props.Color ~= C.PanelDark then Style.Darker(props.Color, 0.55):Lerp(C.PanelDark, 0.6) else C.PanelDark,
		Transparency = props.Transparency or U.PanelTransparency,
		Border = if props.Border == nil then C.Line else props.Border,
		Cut = props.Cut or U.CutSmall,
	})
	return frame
end

-- Card for window grids: dark body with a rarity-colored frame
-- (animated rainbow for the top rarities). Returns card, stroke.
function Style.Card(parent, color: Color3, rainbow: boolean?)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = C.Card
	card.BorderSizePixel = 0
	card.ZIndex = 33
	card.Parent = parent
	Style.Corner(card, UDim.new(0, 3))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Style.Lighter(C.Card, 0.05), C.CardDark)
	gradient.Parent = card
	local stroke = Style.Stroke(card, 1.5, color:Lerp(C.Line, 0.35))
	if rainbow then
		Style.Rainbow(stroke)
	end
	return card, stroke
end

-- Thin progress bar: track + fill (+ optional centered text).
-- Returns track, fill, label.
function Style.Bar(parent, props: { [string]: any })
	local track = Instance.new("Frame")
	track.Name = props.Name or "Bar"
	track.AnchorPoint = props.AnchorPoint or Vector2.zero
	track.Position = props.Position or UDim2.new()
	track.Size = props.Size or UDim2.fromOffset(200, 10)
	track.BackgroundColor3 = C.CardDark
	track.BackgroundTransparency = 0.1
	track.BorderSizePixel = 0
	track.ZIndex = props.ZIndex or 2
	track.LayoutOrder = props.LayoutOrder or 0
	track.Parent = parent
	Style.Stroke(track, 1, props.Border or C.Line)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = props.Color or C.Gold
	fill.BorderSizePixel = 0
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Style.Lighter(props.Color or C.Gold, 0.18), Style.Darker(props.Color or C.Gold, 0.2))
	g.Parent = fill
	local label = nil
	if props.TextSize then
		label = Style.Label(track, "", props.TextSize, C.Text, { Size = UDim2.fromScale(1, 1), ZIndex = track.ZIndex + 2 })
	end
	return track, fill, label
end

-- Thin gold separator line.
function Style.Rule(parent, props: { [string]: any })
	local f = Instance.new("Frame")
	f.Name = "Rule"
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.Position = props.Position or UDim2.new()
	f.Size = props.Size or UDim2.new(1, 0, 0, 1)
	f.BackgroundColor3 = props.Color or C.GoldDim
	f.BorderSizePixel = 0
	f.ZIndex = props.ZIndex or 2
	f.Parent = parent
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f
end

---------------------------------------------------------------------
-- Sounds: Style.PlaySound(key | soundId, speed?, volume?). A key of
-- Config.Sounds is replaced by GameAssets/Audio/<key> when it exists.
---------------------------------------------------------------------

local function audioOverride(key: string): Sound?
	local root = ReplicatedStorage:FindFirstChild("GameAssets")
	local folder = root and root:FindFirstChild("Audio")
	local sound = folder and folder:FindFirstChild(key)
	return if sound and sound:IsA("Sound") then sound else nil
end

local reverse = nil -- [soundId] = key, to find overrides for ids passed directly
local function keyOf(soundId: string): string?
	if Config.Sounds[soundId] ~= nil then
		return soundId
	end
	if not reverse then
		reverse = {}
		for key, id in pairs(Config.Sounds) do
			if id ~= "" and not reverse[id] then
				reverse[id] = key
			end
		end
	end
	return reverse[soundId]
end

function Style.SoundId(keyOrId: string?): string?
	if not keyOrId or keyOrId == "" then
		return nil
	end
	local key = keyOf(keyOrId)
	local override = key and audioOverride(key)
	if override then
		return override.SoundId
	end
	if key then
		local id = Config.Sounds[key]
		return if id ~= "" then id else nil
	end
	return keyOrId
end

-- One-shot sound. Empty slots are skipped.
function Style.PlaySound(keyOrId: string?, speed: number?, volume: number?)
	if Style.Muted then
		return
	end
	local id = Style.SoundId(keyOrId)
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function Style.RarityColor(rarityId: string?): (Color3, boolean)
	local rarity = Config.Rarity[rarityId or "Common"] or Config.Rarity.Common
	return rarity.Color, rarity.Rainbow == true
end

return Style
