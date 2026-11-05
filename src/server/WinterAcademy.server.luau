-- Procedural Winter Academy world. All names and designs are original.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local old = Workspace:FindFirstChild("WinterAcademy")
if old then old:Destroy() end

local world = Instance.new("Folder")
world.Name = "WinterAcademy"
world.Parent = Workspace

local function part(name, size, cf, color, material, parent)
 local p = Instance.new("Part")
 p.Name = name
 p.Size = size
 p.CFrame = cf
 p.Anchored = true
 p.Color = color
 p.Material = material or Enum.Material.SmoothPlastic
 p.TopSurface = Enum.SurfaceType.Smooth
 p.BottomSurface = Enum.SurfaceType.Smooth
 p.Parent = parent or world
 return p
end

local function ball(name, size, cf, color, material)
 local p = part(name,size,cf,color,material)
 p.Shape = Enum.PartType.Ball
 return p
end

local function neon(name,size,cf,color)
 return part(name,size,cf,color,Enum.Material.Neon)
end

Lighting.ClockTime = 18.4
Lighting.Brightness = 2
Lighting.Ambient = Color3.fromRGB(105,115,155)
Lighting.OutdoorAmbient = Color3.fromRGB(90,105,145)
Lighting.FogColor = Color3.fromRGB(100,115,165)
Lighting.FogEnd = 850

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.28
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(180,195,255)
atmosphere.Decay = Color3.fromRGB(70,75,125)
atmosphere.Parent = Lighting

local bloom = Lighting:FindFirstChild("WinterBloom") or Instance.new("BloomEffect")
bloom.Name = "WinterBloom"
bloom.Intensity = 0.45
bloom.Size = 28
bloom.Threshold = 1.4
bloom.Parent = Lighting

-- Snowy courtyard and stone walkways
part("Snow courtyard",Vector3.new(300,2,300),CFrame.new(0,-1,0),Color3.fromRGB(222,232,255),Enum.Material.Snow)
part("Main stone avenue",Vector3.new(34,0.35,190),CFrame.new(0,0.15,5),Color3.fromRGB(105,112,145),Enum.Material.Cobblestone)
part("Central plaza",Vector3.new(112,0.45,78),CFrame.new(0,0.2,-15),Color3.fromRGB(126,132,165),Enum.Material.Slate)

-- Academy facade, wings and towers
part("Academy central hall",Vector3.new(100,48,22),CFrame.new(0,24,-92),Color3.fromRGB(54,57,91),Enum.Material.Slate)
part("Hall roof",Vector3.new(110,4,28),CFrame.new(0,50,-92),Color3.fromRGB(35,39,72),Enum.Material.Slate)
for _,x in {-58,58} do
 part("Academy wing",Vector3.new(28,34,24),CFrame.new(x,17,-83),Color3.fromRGB(65,66,104),Enum.Material.Slate)
 for y=10,34,12 do
  for z=-94,-73,10 do
   part("Glowing window",Vector3.new(3,6,0.5),CFrame.new(x,y,z),Color3.fromRGB(255,190,105),Enum.Material.Neon)
  end
 end
end
for _,x in {-68,-34,34,68} do
 part("Tower",Vector3.new(16,66,16),CFrame.new(x,33,-92),Color3.fromRGB(49,53,88),Enum.Material.Slate)
 local roof = part("Tower spire",Vector3.new(19,3,19),CFrame.new(x,67,-92),Color3.fromRGB(120,74,130),Enum.Material.Metal)
 roof.Shape = Enum.PartType.Cylinder
 part("Spire tip",Vector3.new(2,12,2),CFrame.new(x,75,-92),Color3.fromRGB(245,190,105),Enum.Material.Neon)
 for y=20,48,14 do
  part("Tower window",Vector3.new(4,7,0.5),CFrame.new(x,y,-83.7),Color3.fromRGB(255,188,100),Enum.Material.Neon)
 end
end
part("Academy crest backing",Vector3.new(18,15,1),CFrame.new(0,36,-79),Color3.fromRGB(115,70,130),Enum.Material.Metal)
part("Academy crest",Vector3.new(8,8,1.2),CFrame.new(0,36,-77.8),Color3.fromRGB(255,197,92),Enum.Material.Neon)

-- Grand staircase
for i=1,7 do
 part("Entrance stair "..i,Vector3.new(44,1.2,4),CFrame.new(0,i*1.1,-62+(i*3)),Color3.fromRGB(130,139,174),Enum.Material.Slate)
end

-- Mentor plinths and original mentor silhouettes
local mentors = {
 {"Арон Вейл",Color3.fromRGB(63,83,125),Color3.fromRGB(195,160,255)},
 {"Герман Рид",Color3.fromRGB(130,65,75),Color3.fromRGB(255,175,120)},
 {"Луна Грей",Color3.fromRGB(100,110,155),Color3.fromRGB(160,220,255)},
 {"Северус Кроу",Color3.fromRGB(40,48,72),Color3.fromRGB(180,145,235)},
 {"Альбус Рейн",Color3.fromRGB(190,185,205),Color3.fromRGB(255,220,140)},
 {"Волдемар Кейн",Color3.fromRGB(72,65,83),Color3.fromRGB(245,105,130)},
}
for i,m in ipairs(mentors) do
 local x = (i-3.5)*18
 local z = -43
 part("Mentor plinth "..i,Vector3.new(12,1,10),CFrame.new(x,1,z),Color3.fromRGB(73,67,115),Enum.Material.Marble)
 neon("Mentor rune "..i,Vector3.new(9,0.18,7),CFrame.new(x,1.65,z),m[3])
 local model = Instance.new("Model")
 model.Name = "Mentor - "..m[1]
 model.Parent = world
 local torso = part("Robe",Vector3.new(4,5,2),CFrame.new(x,5,z),m[2],Enum.Material.Fabric,model)
 local head = ball("Head",Vector3.new(2.5,2.5,2.5),CFrame.new(x,8.7,z),Color3.fromRGB(235,205,180),Enum.Material.SmoothPlastic)
 head.Parent = model
 local hair = ball("Hair",Vector3.new(2.7,1.2,2.7),CFrame.new(x,9.7,z),m[2],Enum.Material.Fabric)
 hair.Parent = model
 local badge = part("Mentor insignia",Vector3.new(0.8,1.1,0.25),CFrame.new(x,6,z-1.12),m[3],Enum.Material.Neon,model)
 local title = Instance.new("BillboardGui")
 title.Name = "MentorName"
 title.Size = UDim2.fromOffset(180,48)
 title.StudsOffset = Vector3.new(0,5.4,0)
 title.AlwaysOnTop = true
 title.Parent = torso
 local text = Instance.new("TextLabel")
 text.Size = UDim2.fromScale(1,1)
 text.BackgroundColor3 = Color3.fromRGB(24,22,44)
 text.BackgroundTransparency = 0.12
 text.TextColor3 = Color3.fromRGB(255,224,155)
 text.TextStrokeTransparency = 0.3
 text.Font = Enum.Font.GothamBold
 text.TextScaled = true
 text.Text = m[1]
 text.Parent = title
end

-- Snow-covered fir trees and warm lanterns
local function tree(x,z,s)
 local trunk = part("Fir trunk",Vector3.new(2*s,5*s,2*s),CFrame.new(x,2.5*s,z),Color3.fromRGB(92,63,53),Enum.Material.Wood)
 for i=1,3 do
  local foliage = ball("Snowy fir",Vector3.new((10-i*1.6)*s,7*s,(10-i*1.6)*s),CFrame.new(x,(5+i*3)*s,z),Color3.fromRGB(37,78,79),Enum.Material.Grass)
  local snow = ball("Snow cap",Vector3.new((8-i)*s,2*s,(8-i)*s),CFrame.new(x,(8+i*3)*s,z-0.3*s),Color3.fromRGB(226,237,255),Enum.Material.Snow)
 end
end
for _,pos in ipairs({{-78,-35},{78,-35},{-82,18},{82,18},{-55,55},{55,55},{-105,-85},{105,-85}}) do tree(pos[1],pos[2],1.2) end

for _,x in {-42,-22,22,42} do
 for _,z in {-5,30,65} do
  part("Lantern post",Vector3.new(0.8,9,0.8),CFrame.new(x,4.5,z),Color3.fromRGB(43,42,67),Enum.Material.Metal)
  ball("Warm lantern",Vector3.new(3,3,3),CFrame.new(x,9,z),Color3.fromRGB(255,190,105),Enum.Material.Neon)
  local light = Instance.new("PointLight")
  light.Color = Color3.fromRGB(255,180,100)
  light.Range = 22
  light.Brightness = 1.8
  light.Parent = world:FindFirstChild("Warm lantern")
 end
end

-- Seasonal trees and gift clusters
for _,x in {-95,95} do
 for _,z in {-12,12,36} do
  local gift = part("Wrapped gift",Vector3.new(5,4,5),CFrame.new(x,2,z),Color3.fromRGB(150,48,88),Enum.Material.SmoothPlastic)
  part("Gift ribbon",Vector3.new(5.2,0.5,0.8),gift.CFrame,Color3.fromRGB(255,205,105),Enum.Material.Neon)
 end
end

-- Spawn point
local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
if not spawn then
 spawn = Instance.new("SpawnLocation")
 spawn.Parent = Workspace
end
spawn.Name = "AcademySpawn"
spawn.Size = Vector3.new(8,1,8)
spawn.CFrame = CFrame.new(0,2,58)
spawn.Color = Color3.fromRGB(125,92,160)
spawn.Material = Enum.Material.Neon
spawn.Neutral = true
spawn.Anchored = true
