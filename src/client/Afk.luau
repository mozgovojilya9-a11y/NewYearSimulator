--[[
	Afk.luau
	Client side of the AFK zone (server AfkService, Config.AFK):
	  * the panel on the right while Zone = "Afk": time in the zone, what
	    was earned (XP / credits / Кристаллы / items), the chances per
	    tick, the hourly limit line and the "Выйти" button;
	  * Afk.Toggle() for the HUD button "АФК" [Z] and the portal circle;
	  * Roblox kicks after 20 idle minutes: ONLY inside the AFK zone a
	    VirtualUser click on Idled keeps the player in the game.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Popups = require(script.Parent.ui.Popups)
local Style = require(script.Parent.ui.Style)

local A = Config.AFK
local T = A.Texts
local C = Style.Colors
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Afk")

local Afk = {}

local panel = Style.Panel(Style.Gui, {
	Name = "AfkPanel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(300, 410),
	Fill = C.PanelDark,
	Border = Config.Crystals.Color,
	Cut = 12,
	ZIndex = 8,
	Visible = false,
})
Style.Label(panel, T.Title, 22, C.Gold, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 26), ZIndex = 9 })
local timeLabel = Style.Label(panel, "0:00", 34, C.Text, { Font = Style.FontTitle, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 38), ZIndex = 9 })
Style.Label(panel, Style.Upper(T.Got), 12, C.Muted, { Position = UDim2.fromOffset(16, 88), Size = UDim2.new(1, -32, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 })
local rows = {}
for i, key in ipairs({ "Xp", "Credits", "Crystals", "Items" }) do
	local y = 106 + (i - 1) * 24
	Style.Label(panel, T[key], 14, C.Muted, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(0.6, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 })
	rows[key] = Style.Label(panel, "0", 16, if key == "Crystals" then Config.Crystals.Color else C.Text, { Font = Style.FontTitle, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, y), Size = UDim2.new(0.4, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 9 })
end
-- chances per tick
Style.Label(panel, Style.Upper(T.Chances:format(A.Tick)), 12, C.Muted, { Position = UDim2.fromOffset(16, 208), Size = UDim2.new(1, -32, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 })
do
	local lines = {
		{ "Опыт", "каждый раз", C.Text },
		{ "Кредиты", "каждый раз", C.Text },
		{ "Кристалл", ("%g%%"):format(A.CrystalChance * 100), Config.Crystals.Color },
		{ "Предмет", ("%g%%"):format(A.ItemChance * 100), C.Gold },
	}
	local total = 0
	for _, w in pairs(A.Items) do
		total += w
	end
	local rarityLine = {}
	for _, r in ipairs(Config.Rarities) do
		if A.Items[r.Id] then
			table.insert(rarityLine, ("%s %d%%"):format(r.Name, math.floor(A.Items[r.Id] / total * 100 + 0.5)))
		end
	end
	for i, line in ipairs(lines) do
		local y = 226 + (i - 1) * 20
		Style.Label(panel, line[1], 13, C.Muted, { Position = UDim2.fromOffset(16, y), Size = UDim2.new(0.6, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 })
		Style.Label(panel, line[2], 13, line[3], { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, y), Size = UDim2.new(0.4, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 9 })
	end
	Style.Label(panel, table.concat(rarityLine, " · "), 11, C.Muted, { Position = UDim2.fromOffset(16, 308), Size = UDim2.new(1, -32, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9 })
end
local limitLabel = Style.Label(panel, "", 12, C.Muted, { Position = UDim2.fromOffset(16, 328), Size = UDim2.new(1, -32, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 9 })
local leave = Style.Button(panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -32, 0, 42), Color = C.Card, Icon = "back", Text = Style.Upper(T.Leave), TextSize = 16, ZIndex = 10 })

local state = nil
local stateClock = os.clock()

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	return if h > 0 then ("%d:%02d:%02d"):format(h, (seconds % 3600) // 60, seconds % 60) else ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function render()
	local inZone = player:GetAttribute("Zone") == "Afk"
	panel.Visible = inZone
	if not inZone or not state then
		return
	end
	local elapsed = os.clock() - stateClock
	timeLabel.Text = clock(state.Seconds + elapsed)
	-- the rewards hologram on the island shows our own timer
	local zone = workspace:FindFirstChild("AfkZone")
	local screen = zone and zone:FindFirstChild("HoloScreen", true)
	local holo = screen and screen:FindFirstChild("AfkHologram")
	if holo and holo:FindFirstChild("Timer") then
		holo.Timer.Text = clock(state.Seconds + elapsed)
	end
	rows.Xp.Text = Format.Number(state.Xp)
	rows.Credits.Text = Format.Number(state.Credits)
	rows.Crystals.Text = Format.Number(state.Crystals)
	rows.Items.Text = Format.Number(state.Items)
	if state.Limited then
		limitLabel.Text = T.Limit:format(A.MinCredits, A.Tick, clock(state.ResetIn - elapsed))
		limitLabel.TextColor3 = Color3.fromRGB(240, 140, 110)
	else
		limitLabel.Text = T.LimitLeft:format(clock(state.LeftTicks * A.Tick))
		limitLabel.TextColor3 = C.Muted
	end
end

ReplicatedStorage:WaitForChild("AfkTick").OnClientEvent:Connect(function(s)
	if type(s) == "table" then
		state = s
		stateClock = os.clock()
		render()
	end
end)
player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Afk" then
		state = nil
	end
	render()
end)
task.spawn(function()
	while true do
		task.wait(1)
		render()
	end
end)

local busy = false
function Afk.Toggle()
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local inZone = player:GetAttribute("Zone") == "Afk"
		local ok, message = remote:InvokeServer(if inZone then "Leave" else "Enter")
		busy = false
		if not ok and message then
			Popups.Toast(message, "bad")
		end
	end)
end
leave.Activated:Connect(function()
	if player:GetAttribute("Zone") == "Afk" then
		Afk.Toggle()
	end
end)

-- No idle kick while resting in the AFK zone (only there).
player.Idled:Connect(function()
	if player:GetAttribute("Zone") == "Afk" then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end
end)

return Afk
