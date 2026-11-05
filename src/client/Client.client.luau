-- Winter Academy UI: original magical-academy theme, responsive and functional.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local state = nil
local selectedZone = 1
local autoTrain = false
local heroSig = nil

local C = {
 ink = Color3.fromRGB(24,22,43), panel = Color3.fromRGB(37,34,62),
 panel2 = Color3.fromRGB(54,48,82), gold = Color3.fromRGB(255,195,91),
 cream = Color3.fromRGB(255,239,205), purple = Color3.fromRGB(137,83,190),
 blue = Color3.fromRGB(65,111,184), green = Color3.fromRGB(54,130,92),
 red = Color3.fromRGB(153,55,68), muted = Color3.fromRGB(177,177,204),
}
local SUFFIX = {"","K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc"}
local function fmt(n)
 local i=1
 while n>=1000 and i<#SUFFIX do n/=1000; i+=1 end
 return i==1 and tostring(math.floor(n)) or ("%.2f%s"):format(n,SUFFIX[i])
end
local function make(class,props,parent)
 local o=Instance.new(class)
 for k,v in props do o[k]=v end
 o.Parent=parent
 return o
end
local function corner(o,r)
 make("UICorner",{CornerRadius=UDim.new(0,r or 12)},o)
end
local function stroke(o,color,thick)
 make("UIStroke",{Color=color or C.gold,Thickness=thick or 1.5,Transparency=0.12},o)
end
local function label(parent,text,size,pos,font,color)
 return make("TextLabel",{BackgroundTransparency=1,Text=text,TextSize=size,
  Position=pos or UDim2.new(),Size=UDim2.new(1,0,0,30),Font=font or Enum.Font.GothamBold,
  TextColor3=color or C.cream,TextXAlignment=Enum.TextXAlignment.Left,
  TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true},parent)
end
local function button(parent,text,color,size,pos,callback)
 local b=make("TextButton",{Size=size,Position=pos,BackgroundColor3=color,Text=text,
  TextColor3=C.cream,TextSize=16,Font=Enum.Font.GothamBold,TextWrapped=true,
  AutoButtonColor=false},parent)
 corner(b,10); stroke(b,C.gold,1.3)
 b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(.12),{BackgroundColor3=color:Lerp(Color3.new(1,1,1),.12)}):Play() end)
 b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(.12),{BackgroundColor3=color}):Play() end)
 b.Activated:Connect(callback)
 return b
end

local gui=make("ScreenGui",{Name="WinterAcademyUI",ResetOnSpawn=false,IgnoreGuiInset=true},player:WaitForChild("PlayerGui"))
local root=make("Frame",{Name="Root",Size=UDim2.fromScale(1,1),BackgroundTransparency=1},gui)

-- Header event cards
local header=make("Frame",{Size=UDim2.fromScale(.42,.085),Position=UDim2.fromScale(.29,.018),BackgroundTransparency=1},root)
local event1=make("Frame",{Size=UDim2.fromScale(.49,1),BackgroundColor3=C.panel},header); corner(event1,12); stroke(event1,C.purple)
label(event1,"✦ ТЕНЕВЫЕ ВРАГИ",14,UDim2.fromScale(.08,.08),Enum.Font.GothamBold,C.gold)
label(event1,"Атака начнётся скоро",11,UDim2.fromScale(.08,.48),Enum.Font.Gotham,C.cream)
local event2=make("Frame",{Size=UDim2.fromScale(.49,1),Position=UDim2.fromScale(.51,0),BackgroundColor3=C.panel},header); corner(event2,12); stroke(event2,C.red)
label(event2,"✧ РЕЙД НА БАШНЮ",14,UDim2.fromScale(.08,.08),Enum.Font.GothamBold,C.gold)
label(event2,"Готовься к испытанию",11,UDim2.fromScale(.08,.48),Enum.Font.Gotham,C.cream)

-- Side navigation
local side=make("Frame",{Size=UDim2.fromScale(.145,.54),Position=UDim2.fromScale(.018,.22),BackgroundTransparency=1},root)
local sideLayout=make("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},side)
local panels={}
local function openPanel(name)
 for k,p in panels do p.Visible=(k==name) and not p.Visible end
end
local function sideButton(text,color,order,callback)
 local b=button(side,text,color,UDim2.new(1,0,0,52),UDim2.new(),callback)
 b.LayoutOrder=order
 return b
end

-- Resource panel
local resources=make("Frame",{Size=UDim2.fromScale(.19,.22),Position=UDim2.fromScale(.02,.68),BackgroundColor3=C.ink,BackgroundTransparency=.12},root)
corner(resources,14); stroke(resources,C.gold)
local statsLabel=label(resources,"Загрузка...",17,UDim2.fromScale(.08,.08),Enum.Font.GothamBold,C.gold)
statsLabel.Size=UDim2.fromScale(.86,.84)

-- Right offers
local offers=make("Frame",{Size=UDim2.fromScale(.15,.22),Position=UDim2.fromScale(.83,.37),BackgroundTransparency=1},root)
local offer1=button(offers,"2× ПОБЕДЫ\nСкоро в магазине",C.red,UDim2.new(1,0,.45,0),UDim2.new(),function() openPanel("shop") end)
local offer2=button(offers,"УСИЛЕНИЕ СИЛЫ\nИгровые награды",C.panel2,UDim2.new(1,0,.45,0),UDim2.new(0,.0,.53,0),function() openPanel("shop") end)

-- Bottom progress and action bar
local progress=make("Frame",{Size=UDim2.fromScale(.46,.105),Position=UDim2.fromScale(.27,.73),BackgroundColor3=C.ink,BackgroundTransparency=.08},root)
corner(progress,12); stroke(progress,C.gold)
local powerLabel=label(progress,"✦ СИЛА: 0",20,UDim2.fromScale(.04,.02),Enum.Font.GothamBold,C.gold)
local levelLabel=label(progress,"Уровень 1   •   0 / 100",13,UDim2.fromScale(.04,.42),Enum.Font.Gotham,C.cream)
local track=make("Frame",{Size=UDim2.fromScale(.92,.16),Position=UDim2.fromScale(.04,.77),BackgroundColor3=C.panel2},progress); corner(track,6)
local fill=make("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=C.gold},track); corner(fill,6)

local actions=make("Frame",{Size=UDim2.fromScale(.62,.12),Position=UDim2.fromScale(.19,.86),BackgroundTransparency=1},root)
make("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(.012,0)},actions)
local function action(text,color,fn)
 return button(actions,text,color,UDim2.new(.19,0,.82,0),UDim2.new(),fn)
end

-- Modal panels
local function panel(name,titleText)
 local p=make("Frame",{Name=name,Size=UDim2.fromScale(.48,.56),Position=UDim2.fromScale(.26,.2),BackgroundColor3=C.ink,Visible=false},root)
 corner(p,16); stroke(p,C.gold,2)
 local head=make("Frame",{Size=UDim2.new(1,0,0,48),BackgroundColor3=C.panel2},p); corner(head,14)
 label(head,titleText,21,UDim2.fromScale(.04,0),Enum.Font.GothamBold,C.gold)
 button(head,"✕",C.red,UDim2.fromOffset(42,36),UDim2.new(1,-48,0,6),function() p.Visible=false end)
 local body=make("ScrollingFrame",{Name="Body",Size=UDim2.new(1,-20,1,-62),Position=UDim2.fromOffset(10,55),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=5},p)
 make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},body)
 panels[name]=p
 return p,body
end
local heroPanel,heroBody=panel("mentors","НАСТАВНИКИ АКАДЕМИИ")
local shopPanel,shopBody=panel("shop","ЛАВКА АРТЕФАКТОВ")
local questPanel,questBody=panel("quests","ИСПЫТАНИЯ")
local worldPanel,worldBody=panel("world","МИРЫ АКАДЕМИИ")

local function clearRows(body)
 for _,c in body:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
end
local function row(body,text,buttonText,color,fn)
 local r=make("Frame",{Size=UDim2.new(1,-8,0,62),BackgroundColor3=C.panel},body); corner(r,10)
 label(r,text,14,UDim2.fromScale(.04,.06),Enum.Font.GothamBold,C.cream).Size=UDim2.fromScale(.62,.88)
 button(r,buttonText,color,UDim2.fromScale(.29,.72),UDim2.fromScale(.68,.14),fn)
 return r
end
local function rebuildHeroes()
 clearRows(heroBody)
 if not state then return end
 for _,hero in Config.Heroes do
  local owned=state.Owned[hero.Id]
  local equipped=state.Equipped==hero.Id
  local txt=hero.Name.."  •  "..hero.Rarity.."\nСила ×"..hero.PowerMult.."  |  "..hero.Ability.Name
  row(heroBody,txt,equipped and "НАДЕТО" or (owned and "НАДЕТЬ" or ("КУПИТЬ "..fmt(hero.Cost))),equipped and C.green or C.purple,function()
   if equipped then return end
   if owned then Remotes.EquipHero:FireServer(hero.Id) else Remotes.BuyHero:FireServer(hero.Id) end
  end)
 end
end
for i,z in Config.Zones do
 row(worldBody,z.Name.."\nТребуется сила: "..fmt(z.Requirement),i==1 and "ВЫБРАНО" or "ВЫБРАТЬ",C.blue,function()
  selectedZone=i
  openPanel("world")
 end)
end
row(shopBody,"Зелье северного сияния\nВременный бонус к силе","СКОРО",C.purple,function() end)
row(shopBody,"Сундук древних рун\nНаграды за победы","СКОРО",C.purple,function() end)
row(questBody,"Испытание ученика\nПотренируйся и усили силу","ПОНЯТНО",C.green,function() questPanel.Visible=false end)
row(questBody,"Защитник двора\nПобеди на следующем этапе","ПОНЯТНО",C.green,function() questPanel.Visible=false end)

sideButton("✧ ЛАВКА",C.panel2,1,function() openPanel("shop") end)
sideButton("❄ МИРЫ",C.blue,2,function() openPanel("world") end)
sideButton("✦ НАСТАВНИКИ",C.purple,3,function() rebuildHeroes(); openPanel("mentors") end)
sideButton("♜ ИСПЫТАНИЯ",C.green,4,function() openPanel("quests") end)
sideButton("🎁 НАГРАДЫ",C.red,5,function() openPanel("quests") end)

local trainButton=action("ТРЕНИРОВКА",C.green,function() Remotes.Train:FireServer(selectedZone) end)
local autoButton
autoButton=action("АВТО: ВЫКЛ",C.purple,function()
 autoTrain=not autoTrain
 autoButton.Text=autoTrain and "АВТО: ВКЛ" or "АВТО: ВЫКЛ"
end)
local fightButton=action("ДУЭЛЬ",C.red,function() Remotes.Fight:FireServer() end)
local rebirthButton=action("ВОЗРОЖДЕНИЕ",C.panel2,function() Remotes.Rebirth:FireServer() end)
local abilityButton=action("ЧАРА",C.blue,function() Remotes.UseAbility:FireServer() end)

local notice=label(root,"",18,UDim2.fromScale(.28,.16),Enum.Font.GothamBold,C.gold)
notice.Size=UDim2.fromScale(.44,.05)
notice.TextXAlignment=Enum.TextXAlignment.Center
notice.Visible=false
local noticeToken=0
Remotes.Notice.OnClientEvent:Connect(function(msg)
 noticeToken+=1
 local token=noticeToken
 notice.Text=msg; notice.Visible=true
 task.delay(2.8,function() if token==noticeToken then notice.Visible=false end end)
end)

local function refresh()
 if not state then return end
 statsLabel.Text=("⚡ Сила: %s\n✧ Победы: %s\n♜ Возрождения: %d"):format(fmt(state.Power),fmt(state.Wins),state.Rebirths)
 powerLabel.Text="✦ СИЛА: "..fmt(state.Power)
 local req=state.StageRequirement
 local pct=math.clamp(state.Power/math.max(req,1),0,1)
 levelLabel.Text=("Уровень %d   •   %s / %s  (%d%%)"):format(state.Stage,fmt(state.Power),fmt(req),math.floor(pct*100))
 fill.Size=UDim2.fromScale(pct,1)
 rebirthButton.Text="ВОЗРОЖДЕНИЕ"
 if heroPanel.Visible then rebuildHeroes() end
end
Remotes.State.OnClientEvent:Connect(function(s)
 if not state then selectedZone=s.Zone end
 state=s
 refresh()
end)
Remotes.RequestState:FireServer()

task.spawn(function()
 while true do
  if autoTrain then Remotes.Train:FireServer(selectedZone) end
  task.wait(Config.TrainCooldown+.03)
 end
end)
