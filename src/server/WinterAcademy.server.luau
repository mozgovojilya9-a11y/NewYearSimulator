-- Original low-poly Winter Academy environment. Built as coherent Roblox models,
-- with intentionally separated mentor plinths, training court and combat arena.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local old = Workspace:FindFirstChild("WinterAcademy")
if old then old:Destroy() end

local oldBaseplate = Workspace:FindFirstChild("Baseplate")
if oldBaseplate then oldBaseplate:Destroy() end

local world = Instance.new("Folder")
world.Name = "WinterAcademy"
world.Parent = Workspace

local function makePart(parent, name, size, cf, color, material, shape, anchored)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.Anchored = anchored ~= false
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CastShadow = true
    if shape then p.Shape = shape end
    p.Parent = parent
    return p
end

local function model(parent, name)
    local m = Instance.new("Model")
    m.Name = name
    m.Parent = parent
    return m
end

local function light(part, color, range, brightness)
    local point = Instance.new("PointLight")
    point.Color = color
    point.Range = range
    point.Brightness = brightness
    point.Shadows = true
    point.Parent = part
    return point
end

local function trim(parent, name, size, cf, color)
    return makePart(parent, name, size, cf, color, Enum.Material.Metal)
end

-- Lighting: twilight, cold sky and warm windows.
Lighting.ClockTime = 18.2
Lighting.Brightness = 2.1
Lighting.ExposureCompensation = 0.12
Lighting.Ambient = Color3.fromRGB(88, 96, 142)
Lighting.OutdoorAmbient = Color3.fromRGB(83, 94, 139)
Lighting.FogColor = Color3.fromRGB(85, 99, 151)
Lighting.FogStart = 100
Lighting.FogEnd = 420
Lighting.EnvironmentDiffuseScale = 0.35
Lighting.EnvironmentSpecularScale = 0.55

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.24
atmosphere.Offset = 0.12
atmosphere.Color = Color3.fromRGB(171, 190, 255)
atmosphere.Decay = Color3.fromRGB(64, 72, 122)
atmosphere.Glare = 0.22
atmosphere.Haze = 1.6
atmosphere.Parent = Lighting

local bloom = Lighting:FindFirstChild("AcademyBloom") or Instance.new("BloomEffect")
bloom.Name = "AcademyBloom"
bloom.Intensity = 0.38
bloom.Size = 24
bloom.Threshold = 1.35
bloom.Parent = Lighting

local colorCorrection = Lighting:FindFirstChild("AcademyColor") or Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "AcademyColor"
colorCorrection.TintColor = Color3.fromRGB(218, 224, 255)
colorCorrection.Contrast = 0.12
colorCorrection.Saturation = 0.08
colorCorrection.Brightness = -0.02
colorCorrection.Parent = Lighting

-- Ground, stone avenue and central square.
makePart(world, "Snowfield", Vector3.new(320, 2, 320), CFrame.new(0, -1.2, 0), Color3.fromRGB(202, 218, 248), Enum.Material.Snow)
makePart(world, "AcademyApproach", Vector3.new(30, 0.5, 164), CFrame.new(0, 0.05, 21), Color3.fromRGB(78, 82, 119), Enum.Material.Cobblestone)
makePart(world, "CentralCourtyard", Vector3.new(116, 0.65, 82), CFrame.new(0, 0.2, -29), Color3.fromRGB(106, 107, 145), Enum.Material.Slate)
makePart(world, "CourtyardBorderNorth", Vector3.new(118, 0.6, 2), CFrame.new(0, 0.58, -71), Color3.fromRGB(193, 206, 237), Enum.Material.Marble)
makePart(world, "CourtyardBorderSouth", Vector3.new(118, 0.6, 2), CFrame.new(0, 0.58, 13), Color3.fromRGB(193, 206, 237), Enum.Material.Marble)

-- Decorative inlaid path lines.
for _, x in ipairs({ -54, -36, 36, 54 }) do
    trim(world, "PathInlay", Vector3.new(0.22, 0.12, 72), CFrame.new(x, 0.62, -29), Color3.fromRGB(171, 134, 239))
end

-- Main academy: central keep, two side wings and four towers.
local castle = model(world, "TheWinterAcademy")
makePart(castle, "CentralKeep", Vector3.new(76, 44, 25), CFrame.new(0, 22, -105), Color3.fromRGB(48, 48, 82), Enum.Material.Slate)
makePart(castle, "KeepFoundation", Vector3.new(84, 4, 31), CFrame.new(0, 2, -105), Color3.fromRGB(83, 79, 119), Enum.Material.Marble)
makePart(castle, "KeepUpperCornice", Vector3.new(81, 2, 28), CFrame.new(0, 44.5, -105), Color3.fromRGB(111, 83, 153), Enum.Material.Metal)
makePart(castle, "SnowRoof", Vector3.new(82, 3, 29), CFrame.new(0, 47, -105), Color3.fromRGB(214, 226, 250), Enum.Material.Snow)

for _, side in ipairs({ -1, 1 }) do
    local x = side * 53
    makePart(castle, "EastWestWing", Vector3.new(29, 31, 24), CFrame.new(x, 16.5, -95), Color3.fromRGB(58, 56, 92), Enum.Material.Slate)
    makePart(castle, "WingRoof", Vector3.new(33, 2, 28), CFrame.new(x, 33, -95), Color3.fromRGB(196, 207, 236), Enum.Material.Snow)
    for y = 10, 27, 10 do
        makePart(castle, "WingWindowFrame", Vector3.new(5.2, 7.2, 0.55), CFrame.new(x, y, -82.7), Color3.fromRGB(28, 31, 58), Enum.Material.Metal)
        local window = makePart(castle, "WarmWingWindow", Vector3.new(3.6, 5.6, 0.3), CFrame.new(x, y, -82.3), Color3.fromRGB(255, 197, 105), Enum.Material.Neon)
        light(window, Color3.fromRGB(255, 182, 100), 13, 0.7)
    end
end

local function makeTower(x, z, height, name)
    local tower = model(castle, name)
    local baseY = height / 2
    makePart(tower, "TowerBody", Vector3.new(17, height, 17), CFrame.new(x, baseY, z), Color3.fromRGB(43, 44, 79), Enum.Material.Slate)
    makePart(tower, "TowerLowerRing", Vector3.new(19, 2, 19), CFrame.new(x, 4, z), Color3.fromRGB(111, 81, 148), Enum.Material.Metal)
    makePart(tower, "TowerUpperRing", Vector3.new(19, 2, 19), CFrame.new(x, height - 2, z), Color3.fromRGB(111, 81, 148), Enum.Material.Metal)
    local dome = makePart(tower, "DomeRoof", Vector3.new(21, 13, 21), CFrame.new(x, height + 5, z), Color3.fromRGB(66, 46, 111), Enum.Material.Slate, Enum.PartType.Ball)
    dome.CanCollide = false
    local tip = makePart(tower, "AuroraSpire", Vector3.new(1.5, 8, 1.5), CFrame.new(x, height + 15, z), Color3.fromRGB(255, 202, 111), Enum.Material.Neon)
    light(tip, Color3.fromRGB(255, 192, 100), 18, 1.1)

    for y = 17, height - 10, 13 do
        makePart(tower, "WindowFrame", Vector3.new(5.2, 7.6, 0.65), CFrame.new(x, y, z - 8.7), Color3.fromRGB(24, 25, 50), Enum.Material.Metal)
        local window = makePart(tower, "GlowingWindow", Vector3.new(3.7, 6, 0.3), CFrame.new(x, y, z - 8.3), Color3.fromRGB(255, 202, 115), Enum.Material.Neon)
        light(window, Color3.fromRGB(255, 183, 105), 15, 0.65)
    end
end

makeTower(-43, -105, 59, "WestTower")
makeTower(43, -105, 59, "EastTower")
makeTower(-77, -92, 48, "FarWestTower")
makeTower(77, -92, 48, "FarEastTower")

-- Main entrance, pillars, arched-looking layered portal and banners.
for _, x in ipairs({ -24, -12, 12, 24 }) do
    makePart(castle, "EntryPillar", Vector3.new(3, 25, 3), CFrame.new(x, 12.5, -88), Color3.fromRGB(103, 84, 144), Enum.Material.Marble)
    makePart(castle, "PillarCapital", Vector3.new(5, 1.7, 5), CFrame.new(x, 25.5, -88), Color3.fromRGB(255, 198, 111), Enum.Material.Metal)
end
makePart(castle, "MainDoorFrame", Vector3.new(25, 28, 2), CFrame.new(0, 14, -82), Color3.fromRGB(119, 83, 164), Enum.Material.Metal)
makePart(castle, "MainDoor", Vector3.new(18, 23, 1), CFrame.new(0, 12, -80.7), Color3.fromRGB(32, 27, 58), Enum.Material.Wood)
makePart(castle, "DoorRune", Vector3.new(8, 8, 0.35), CFrame.new(0, 13, -80), Color3.fromRGB(178, 119, 255), Enum.Material.Neon)
for _, x in ipairs({ -31, 31 }) do
    makePart(castle, "AcademyBannerPole", Vector3.new(0.7, 17, 0.7), CFrame.new(x, 26, -83), Color3.fromRGB(219, 174, 95), Enum.Material.Metal)
    makePart(castle, "AcademyBanner", Vector3.new(7, 12, 0.5), CFrame.new(x, 28, -82.5), x < 0 and Color3.fromRGB(107, 56, 164) or Color3.fromRGB(43, 92, 153), Enum.Material.Fabric)
    makePart(castle, "BannerSigil", Vector3.new(2.8, 2.8, 0.65), CFrame.new(x, 30, -82), Color3.fromRGB(255, 207, 119), Enum.Material.Neon)
end

-- Wide ceremonial stairs from the plaza to the academy.
for i = 1, 9 do
    makePart(world, "CeremonialStep", Vector3.new(54, 1.15, 3.4), CFrame.new(0, i * 0.85, -77 + i * 3.2), Color3.fromRGB(130, 129, 168), Enum.Material.Marble)
    makePart(world, "StepGoldEdge", Vector3.new(54, 0.16, 0.22), CFrame.new(0, i * 0.85 + 0.58, -75.3 + i * 3.2), Color3.fromRGB(255, 196, 111), Enum.Material.Metal)
end

-- Mentor gallery: individually spaced pedestals and readable nameplates.
local mentorPositions = {
    Vector3.new(-50, 0, -42), Vector3.new(-34, 0, -53), Vector3.new(-17, 0, -61),
    Vector3.new(0, 0, -64), Vector3.new(17, 0, -61), Vector3.new(34, 0, -53), Vector3.new(50, 0, -42),
}
local skin = Color3.fromRGB(236, 205, 176)

local function buildMentor(hero, index, position)
    local display = model(world, "Mentor_" .. hero.Id)
    local x, z = position.X, position.Z
    local accent = hero.Color or Color3.fromRGB(192, 156, 255)

    makePart(world, "MentorPedestal_" .. hero.Id, Vector3.new(11, 1.35, 9), CFrame.new(x, 0.9, z), Color3.fromRGB(57, 48, 91), Enum.Material.Marble)
    makePart(world, "MentorPedestalTrim_" .. hero.Id, Vector3.new(10.3, 0.2, 8.3), CFrame.new(x, 1.67, z), accent, Enum.Material.Neon)

    local pivot = CFrame.new(x, 2, z)
    local torso = makePart(display, "RobeBody", Vector3.new(3.2, 4.1, 1.8), pivot * CFrame.new(0, 2.9, 0), hero.Color, Enum.Material.Fabric)
    local robeHem = makePart(display, "RobeHem", Vector3.new(4.1, 1.2, 2.3), pivot * CFrame.new(0, 0.85, 0), hero.Color:Lerp(Color3.new(0, 0, 0), 0.18), Enum.Material.Fabric)
    local head = makePart(display, "Head", Vector3.new(1.85, 1.85, 1.75), pivot * CFrame.new(0, 5.45, -0.03), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    makePart(display, "HairCap", Vector3.new(2, 0.85, 1.9), head.CFrame * CFrame.new(0, 0.73, 0.08), hero.Color:Lerp(Color3.new(0.08, 0.07, 0.14), 0.35), Enum.Material.Fabric, Enum.PartType.Ball)
    makePart(display, "Collar", Vector3.new(2, 0.48, 2), torso.CFrame * CFrame.new(0, 1.65, -0.08), accent, Enum.Material.Neon)
    makePart(display, "Belt", Vector3.new(3.25, 0.25, 1.9), torso.CFrame * CFrame.new(0, -0.55, -0.02), Color3.fromRGB(221, 178, 98), Enum.Material.Metal)

    for _, side in ipairs({ -1, 1 }) do
        local arm = makePart(display, "RobeSleeve", Vector3.new(0.95, 3.1, 1.05), torso.CFrame * CFrame.new(side * 2.03, 0.05, 0), hero.Color, Enum.Material.Fabric)
        arm.CFrame *= CFrame.Angles(0, 0, side * math.rad(7))
        makePart(display, "Glove", Vector3.new(0.82, 0.82, 0.82), arm.CFrame * CFrame.new(0, -1.55, 0), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
        local boot = makePart(display, "Boot", Vector3.new(1.05, 1.5, 1.35), pivot * CFrame.new(side * 0.82, 0.2, -0.12), Color3.fromRGB(31, 31, 52), Enum.Material.SmoothPlastic)
        boot.CanCollide = false
    end

    local cape = makePart(display, "Cape", Vector3.new(3.7, 3.8, 0.35), torso.CFrame * CFrame.new(0, -0.05, 1.02), hero.Color:Lerp(Color3.new(0, 0, 0), 0.24), Enum.Material.Fabric)
    local staff = makePart(display, "ArcaneStaff", Vector3.new(0.22, 5.6, 0.22), pivot * CFrame.new(2.7, 2.8, 0.25) * CFrame.Angles(0, 0, math.rad(-7)), Color3.fromRGB(100, 68, 48), Enum.Material.Wood)
    makePart(display, "StaffCrystal", Vector3.new(0.95, 0.95, 0.95), staff.CFrame * CFrame.new(0, 2.95, 0), accent, Enum.Material.Neon, Enum.PartType.Ball)
    display.PrimaryPart = torso

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "StudyMentor"
    prompt.ActionText = "Изучить"
    prompt.ObjectText = hero.Name
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.HoldDuration = 0.15
    prompt.MaxActivationDistance = 13
    prompt.RequiresLineOfSight = false
    prompt:SetAttribute("OpenMenu", "Mentors")
    prompt:SetAttribute("MentorId", hero.Id)
    prompt.Parent = torso

    local plate = Instance.new("BillboardGui")
    plate.Name = "MentorNameplate"
    plate.Adornee = head
    plate.Size = UDim2.fromOffset(148, 52)
    plate.StudsOffset = Vector3.new(0, 3.2, 0)
    plate.MaxDistance = 82
    plate.AlwaysOnTop = false
    plate.Parent = display

    local backing = Instance.new("Frame")
    backing.Size = UDim2.fromScale(1, 1)
    backing.BackgroundColor3 = Color3.fromRGB(21, 18, 39)
    backing.BackgroundTransparency = 0.08
    backing.BorderSizePixel = 0
    backing.Parent = plate
    local rounded = Instance.new("UICorner")
    rounded.CornerRadius = UDim.new(0, 8)
    rounded.Parent = backing
    local outline = Instance.new("UIStroke")
    outline.Color = accent
    outline.Thickness = 1.5
    outline.Parent = backing
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(5, 3)
    title.Size = UDim2.new(1, -10, 0, 22)
    title.Font = Enum.Font.GothamBold
    title.Text = hero.Name
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(255, 235, 204)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Parent = backing
    local detail = Instance.new("TextLabel")
    detail.BackgroundTransparency = 1
    detail.Position = UDim2.fromOffset(5, 27)
    detail.Size = UDim2.new(1, -10, 0, 18)
    detail.Font = Enum.Font.GothamMedium
    detail.Text = hero.Rarity .. "  ·  ×" .. tostring(hero.PowerMult)
    detail.TextSize = 10
    detail.TextColor3 = accent
    detail.TextTruncate = Enum.TextTruncate.AtEnd
    detail.Parent = backing
end

for index, hero in ipairs(Config.Heroes) do
    local position = mentorPositions[index] or Vector3.new((index - 4) * 16, 0, -45)
    buildMentor(hero, index, position)
end

-- Training court, with distinct runic targets.
local training = model(world, "TrainingCourt")
makePart(training, "TrainingFloor", Vector3.new(48, 0.7, 40), CFrame.new(-82, 0.1, 4), Color3.fromRGB(67, 75, 113), Enum.Material.Slate)
for index, color in ipairs({
    Color3.fromRGB(87, 202, 255), Color3.fromRGB(177, 111, 255), Color3.fromRGB(255, 189, 94),
}) do
    local x = -96 + index * 14
    local plinth = makePart(training, "FocusPlinth", Vector3.new(8, 1.1, 8), CFrame.new(x, 1, 0), Color3.fromRGB(40, 40, 72), Enum.Material.Marble)
    makePart(training, "FocusRune", Vector3.new(6.5, 0.18, 6.5), plinth.CFrame * CFrame.new(0, 0.68, 0), color, Enum.Material.Neon)
    local crystal = makePart(training, "FocusCrystal", Vector3.new(2.4, 4, 2.4), CFrame.new(x, 3.6, -2), color, Enum.Material.Neon, Enum.PartType.Ball)
    light(crystal, color, 18, 1)
end

-- Combat arena and portal at the end of the central avenue.
local arena = model(world, "FirstTrialArena")
makePart(arena, "ArenaBase", Vector3.new(120, 1.2, 48), CFrame.new(0, 0.25, 8), Color3.fromRGB(54, 51, 86), Enum.Material.Slate)
makePart(arena, "ArenaInset", Vector3.new(112, 0.18, 40), CFrame.new(0, 0.94, 8), Color3.fromRGB(83, 72, 128), Enum.Material.Marble)
for _, radius in ipairs({ 12, 18 }) do
    local ring = makePart(arena, "RunicRing", Vector3.new(radius * 2, 0.16, radius * 2), CFrame.new(0, 1.08, 8), Color3.fromRGB(167, 111, 245), Enum.Material.Neon, Enum.PartType.Cylinder)
    ring.Transparency = 0.48
    ring.CanCollide = false
end
for _, x in ipairs({ -25, 25 }) do
    makePart(arena, "ArenaPillar", Vector3.new(2.5, 11, 2.5), CFrame.new(x, 5.5, -5), Color3.fromRGB(39, 38, 70), Enum.Material.Slate)
    local flame = makePart(arena, "ArenaFlame", Vector3.new(2.1, 2.1, 2.1), CFrame.new(x, 11.8, -5), Color3.fromRGB(180, 123, 255), Enum.Material.Neon, Enum.PartType.Ball)
    light(flame, Color3.fromRGB(153, 112, 255), 22, 1.2)
end
local combatSpawn = makePart(arena, "CombatStart", Vector3.new(5, 0.2, 5), CFrame.new(0, 1.2, 29), Color3.fromRGB(255, 195, 92), Enum.Material.Neon)
combatSpawn.Transparency = 1
combatSpawn.CanCollide = false

-- Warm lantern rows with restrained lighting for performance.
for _, x in ipairs({ -58, -39, 39, 58 }) do
    for _, z in ipairs({ -8, -35, -65 }) do
        makePart(world, "LanternPost", Vector3.new(0.75, 8, 0.75), CFrame.new(x, 4, z), Color3.fromRGB(38, 36, 61), Enum.Material.Metal)
        local housing = makePart(world, "LanternHousing", Vector3.new(2.1, 2.1, 2.1), CFrame.new(x, 8.4, z), Color3.fromRGB(255, 202, 119), Enum.Material.Neon, Enum.PartType.Ball)
        light(housing, Color3.fromRGB(255, 182, 99), 19, 0.75)
    end
end

-- Low-poly snow firs: tiered foliage, snow caps, trunk and tiny baubles.
local function makeFir(x, z, scale)
    local tree = model(world, "SnowFir")
    makePart(tree, "Trunk", Vector3.new(1.6 * scale, 4 * scale, 1.6 * scale), CFrame.new(x, 2 * scale, z), Color3.fromRGB(93, 64, 55), Enum.Material.Wood)
    for tier = 1, 4 do
        local y = (3.2 + tier * 2.2) * scale
        local width = (9 - tier * 1.45) * scale
        local foliage = makePart(tree, "FirTier", Vector3.new(width, 4.3 * scale, width), CFrame.new(x, y, z), Color3.fromRGB(27, 78 + tier * 5, 76), Enum.Material.Grass, Enum.PartType.Ball)
        foliage.CanCollide = false
        local snow = makePart(tree, "SnowCap", Vector3.new(width * 0.88, 1.05 * scale, width * 0.88), foliage.CFrame * CFrame.new(0, 1.6 * scale, 0), Color3.fromRGB(229, 239, 255), Enum.Material.Snow, Enum.PartType.Ball)
        snow.CanCollide = false
    end
    local ornament = makePart(tree, "AuroraBauble", Vector3.new(0.65, 0.65, 0.65), CFrame.new(x + 1.5 * scale, 7 * scale, z - 2 * scale), Color3.fromRGB(255, 182, 99), Enum.Material.Neon, Enum.PartType.Ball)
    ornament.CanCollide = false
end

for _, entry in ipairs({
    { -110, -58, 1.5 }, { 110, -58, 1.5 }, { -104, 8, 1.25 }, { 104, 8, 1.25 },
    { -72, 48, 1.1 }, { 72, 48, 1.1 }, { -126, -108, 1.6 }, { 126, -108, 1.6 },
    { -90, 87, 1.35 }, { 90, 87, 1.35 },
}) do
    makeFir(entry[1], entry[2], entry[3])
end

-- Gift clusters and decorative academy standards.
for _, x in ipairs({ -112, 112 }) do
    for index, z in ipairs({ -18, 2, 22 }) do
        local gift = makePart(world, "WinterGift", Vector3.new(4.5, 3.4, 4.5), CFrame.new(x, 1.8, z), index % 2 == 0 and Color3.fromRGB(153, 61, 111) or Color3.fromRGB(55, 112, 159), Enum.Material.SmoothPlastic)
        makePart(world, "GiftGoldBand", Vector3.new(4.7, 0.35, 0.8), gift.CFrame, Color3.fromRGB(255, 207, 117), Enum.Material.Neon)
        makePart(world, "GiftTopBand", Vector3.new(0.8, 0.3, 4.7), gift.CFrame * CFrame.new(0, 1.85, 0), Color3.fromRGB(255, 207, 117), Enum.Material.Neon)
    end
end

-- The spawn is aligned with the main avenue and the combat arena is ahead.
local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
if not spawn then
    spawn = Instance.new("SpawnLocation")
    spawn.Parent = Workspace
end
spawn.Name = "AcademySpawn"
spawn.Size = Vector3.new(8, 1, 8)
spawn.CFrame = CFrame.new(0, 1.2, 70)
spawn.Color = Color3.fromRGB(126, 93, 173)
spawn.Material = Enum.Material.Neon
spawn.Neutral = true
spawn.Anchored = true
