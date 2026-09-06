-- XPBuddy - professional XP tracker for WoW 3.3.5a
-- v2.2.1 - Astral / stock 3.3.5 compatibility

local ADDON = "XPBuddy"
local MEDIA = "Interface\\AddOns\\XPBuddy\\Textures\\"

local DEFAULTS = {
  enabled = true,
  locked = false,
  showBackdrop = true,
  scale = 1.0,
  fontSize = 12,
  point = "CENTER",
  relPoint = "CENTER",
  x = 0,
  y = 120,
  sessionStartTime = 0,
  sessionLevel = 1,
  sessionXPAtLevel = 0,
  sessionXPGained = 0,
  autoResetOnLogin = true,
}

local function EnsureDB()
  if not XPBuddyDB or type(XPBuddyDB) ~= "table" then XPBuddyDB = {} end
  for k, v in pairs(DEFAULTS) do
    if XPBuddyDB[k] == nil then XPBuddyDB[k] = v end
  end
end

-- WoW 3.3.5 does not reliably provide Region:SetShown().
-- Use explicit Show/Hide calls so Astral and stock Wrath clients behave the same.
local function SetVisible(region, shown)
  if not region then return end
  if shown then
    region:Show()
  else
    region:Hide()
  end
end

local function Num(n)
  n = math.floor(tonumber(n) or 0)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  return tostring(n)
end

local function Clock(sec)
  if not sec or sec <= 0 or sec == math.huge then return "Calculating..." end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  if h > 0 then return string.format("%dh %02dm", h, m) end
  if m > 0 then return string.format("%dm %02ds", m, s) end
  return string.format("%ds", s)
end

local f = CreateFrame("Frame", "XPBuddyFrame", UIParent)
f:SetSize(360, 180)
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")

f.art = f:CreateTexture(nil, "BACKGROUND")
f.art:SetAllPoints(f)
f.art:SetTexture(MEDIA.."Panel")

f.headerGlow = f:CreateTexture(nil, "ARTWORK")
f.headerGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
f.headerGlow:SetPoint("TOPLEFT", 24, -23)
f.headerGlow:SetPoint("TOPRIGHT", -24, -23)
f.headerGlow:SetHeight(42)
f.headerGlow:SetGradientAlpha("VERTICAL", 0.15,0.35,0.75,0.05, 0.15,0.35,0.75,0)

f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
f.title:SetPoint("TOPLEFT", 34, -31)
f.title:SetTextColor(1, .82, .35)
f.title:SetShadowOffset(1,-1)
f.title:SetText("XPBUDDY")

f.level = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.level:SetPoint("TOPRIGHT", -34, -34)
f.level:SetTextColor(.85,.9,1)

f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 1, -2)
f.subtitle:SetText("SESSION PROGRESS")

-- XP bar shell
f.barBG = CreateFrame("Frame", nil, f)
f.barBG:SetPoint("TOPLEFT", 32, -82)
f.barBG:SetPoint("TOPRIGHT", -32, -82)
f.barBG:SetHeight(26)
f.barBG:SetBackdrop({
  bgFile="Interface\\Buttons\\WHITE8X8",
  edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
  tile=false, edgeSize=10,
  insets={left=3,right=3,top=3,bottom=3}
})
f.barBG:SetBackdropColor(.015,.02,.035,.95)
f.barBG:SetBackdropBorderColor(.52,.36,.12,1)

f.rested = CreateFrame("StatusBar", nil, f.barBG)
f.rested:SetPoint("TOPLEFT", 4, -4)
f.rested:SetPoint("BOTTOMRIGHT", -4, 4)
f.rested:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
f.rested:SetStatusBarColor(.48, .20, .72, .90)
f.rested:SetMinMaxValues(0,1)

-- Completed quest XP projection. This sits behind the current-XP bar so the
-- amber section shows how far ready-to-turn-in quests would advance the player.
f.quest = CreateFrame("StatusBar", nil, f.barBG)
f.quest:SetPoint("TOPLEFT", 4, -4)
f.quest:SetPoint("BOTTOMRIGHT", -4, 4)
f.quest:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
f.quest:SetStatusBarColor(.95, .55, .08, .95)
f.quest:SetMinMaxValues(0,1)

f.bar = CreateFrame("StatusBar", nil, f.barBG)
f.bar:SetPoint("TOPLEFT", 4, -4)
f.bar:SetPoint("BOTTOMRIGHT", -4, 4)
f.bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
f.bar:SetStatusBarColor(.18, .48, .95, 1)
f.bar:SetMinMaxValues(0,1)

f.barText = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
f.barText:SetPoint("CENTER", f.bar, "CENTER", 0, 0)
f.barText:SetShadowOffset(1,-1)

local function StatBlock(x, label)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetSize(92,45)
  holder:SetPoint("TOPLEFT", x, -116)

  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  holder.label:SetPoint("TOP", 0, 0)
  holder.label:SetText(label)
  holder.label:SetTextColor(.62,.66,.72)

  holder.value = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  holder.value:SetPoint("TOP", holder.label, "BOTTOM", 0, -5)
  holder.value:SetTextColor(.95,.95,1)
  holder.value:SetShadowOffset(1,-1)
  return holder
end

f.statRate = StatBlock(32, "XP / HOUR")
f.statTime = StatBlock(134, "TIME TO LEVEL")
f.statGain = StatBlock(236, "SESSION GAIN")

local function Divider(x)
  local t=f:CreateTexture(nil,"ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetPoint("TOPLEFT",x,-119)
  t:SetSize(1,37)
  t:SetVertexColor(.45,.32,.13,.75)
end
Divider(126); Divider(228)

local resetBtn = CreateFrame("Button", "XPBuddyHUDResetButton", f)
resetBtn:SetSize(24,24)
resetBtn:SetPoint("BOTTOMRIGHT",-24,19)
resetBtn:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
resetBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
resetBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self,"ANCHOR_TOP")
  GameTooltip:AddLine("Reset XP Session",1,.82,.35)
  GameTooltip:AddLine("Clears XP/hour and session gain.",.8,.8,.8)
  GameTooltip:Show()
end)
resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

f.lockIcon = f:CreateTexture(nil,"OVERLAY")
f.lockIcon:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
f.lockIcon:SetSize(18,18)
f.lockIcon:SetPoint("BOTTOMLEFT",25,20)
f.lockIcon:Hide()

f:SetScript("OnDragStart", function(self)
  if XPBuddyDB.locked then return end
  self:StartMoving()
end)
f:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint()
  XPBuddyDB.point, XPBuddyDB.relPoint, XPBuddyDB.x, XPBuddyDB.y = point, relPoint, x, y
end)

local lastLevel, lastXP, lastMax

local function ResetSession()
  XPBuddyDB.sessionStartTime = GetTime()
  XPBuddyDB.sessionLevel = UnitLevel("player")
  XPBuddyDB.sessionXPAtLevel = UnitXP("player")
  XPBuddyDB.sessionXPGained = 0
  lastLevel, lastXP, lastMax = nil, nil, nil
end

resetBtn:SetScript("OnClick", function()
  ResetSession()
  DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441XPBuddy|r: Session reset.")
end)

local function AccumulateSession()
  local lvl, xp, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  if not lastLevel then
    lastLevel, lastXP, lastMax = lvl, xp, max
    return
  end
  if lvl == lastLevel then
    local delta=xp-lastXP
    if delta>0 then XPBuddyDB.sessionXPGained=(XPBuddyDB.sessionXPGained or 0)+delta end
  elseif lvl>lastLevel then
    local remainder=math.max(0,(lastMax or 0)-(lastXP or 0))
    XPBuddyDB.sessionXPGained=(XPBuddyDB.sessionXPGained or 0)+remainder+xp
  end
  lastLevel,lastXP,lastMax=lvl,xp,max
end

local function ApplyVisibility()
  EnsureDB()
  if XPBuddyDB.enabled == false then
    f:Hide()
  else
    f:Show()
  end
end

local function ApplyAppearance()
  EnsureDB()
  local fs=XPBuddyDB.fontSize or 12
  f.title:SetFont(GameFontNormalLarge:GetFont(),fs+4,"OUTLINE")
  f.level:SetFont(GameFontHighlight:GetFont(),fs+1,"OUTLINE")
  f.barText:SetFont(GameFontHighlightSmall:GetFont(),math.max(10,fs-1),"OUTLINE")
  f.statRate.value:SetFont(GameFontHighlight:GetFont(),fs,"OUTLINE")
  f.statTime.value:SetFont(GameFontHighlight:GetFont(),fs,"OUTLINE")
  f.statGain.value:SetFont(GameFontHighlight:GetFont(),fs,"OUTLINE")
  SetVisible(f.art, XPBuddyDB.showBackdrop ~= false)
  SetVisible(f.headerGlow, XPBuddyDB.showBackdrop ~= false)
  local scale = tonumber(XPBuddyDB.scale) or 1
  if scale < 0.35 then scale = 0.35 end
  if scale > 2.00 then scale = 2.00 end
  f:SetScale(scale)
  SetVisible(f.lockIcon, XPBuddyDB.locked and XPBuddyDB.enabled ~= false)
  f:EnableMouse(XPBuddyDB.enabled ~= false and not XPBuddyDB.locked)
  ApplyVisibility()
end

local function Reanchor()
  EnsureDB()
  f:ClearAllPoints()
  f:SetPoint(XPBuddyDB.point,UIParent,XPBuddyDB.relPoint,XPBuddyDB.x,XPBuddyDB.y)
end

local function GetCompletedQuestXP()
  local total = 0
  local completed = 0
  local entries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0

  for i = 1, entries do
    local title, level, tag, suggestedGroup, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
    if title and not isHeader and isComplete == 1 then
      local rewardXP = GetQuestLogRewardXP and GetQuestLogRewardXP(i) or 0
      if rewardXP and rewardXP > 0 then
        total = total + rewardXP
        completed = completed + 1
      end
    end
  end

  return total, completed
end

local function UpdateTexts()
  local xp,max,lvl=UnitXP("player"),UnitXPMax("player"),UnitLevel("player")
  local rest=GetXPExhaustion() or 0
  local toLevel=math.max(0,max-xp)
  local now=GetTime()
  local elapsed=math.max(0,now-(XPBuddyDB.sessionStartTime or now))
  AccumulateSession()
  local gained=XPBuddyDB.sessionXPGained or 0
  local rate=(elapsed>0) and (gained*3600/elapsed) or 0
  local eta=(rate>0) and (toLevel/rate*3600) or math.huge

  local questXP, completedQuests = GetCompletedQuestXP()
  local projectedXP = math.min(max, xp + questXP)

  f.level:SetText("LEVEL "..lvl)

  -- Draw back-to-front: rested, completed quest projection, current XP.
  f.rested:SetMinMaxValues(0,math.max(1,max))
  f.rested:SetValue(math.min(max,xp+rest))

  f.quest:SetMinMaxValues(0,math.max(1,max))
  f.quest:SetValue(projectedXP)
  SetVisible(f.quest, questXP > 0)

  f.bar:SetMinMaxValues(0,math.max(1,max))
  f.bar:SetValue(xp)

  local pct=(max>0) and (xp/max*100) or 0
  local projectedText = ""
  if questXP > 0 then
    local willDing = (xp + questXP) >= max
    projectedText = string.format("  |cffff9d20+%s quest XP%s|r",
      Num(questXP), willDing and " • DING" or "")
  end
  f.barText:SetText(string.format("%s / %s  •  %.1f%%%s",
    Num(xp),Num(max),pct,projectedText))

  f.statRate.value:SetText(Num(rate))
  f.statTime.value:SetText(Clock(eta))
  f.statGain.label:SetText(completedQuests > 0 and ("QUESTS READY: "..completedQuests) or "SESSION GAIN")
  f.statGain.value:SetText(completedQuests > 0 and Num(questXP) or Num(gained))
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_XP_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_FINISHED")
f:SetScript("OnEvent", function(self,event)
  if event=="PLAYER_LOGIN" then
    EnsureDB()
    if XPBuddyDB.autoResetOnLogin or (XPBuddyDB.sessionStartTime or 0)<=0 then ResetSession() end
    Reanchor(); ApplyAppearance(); UpdateTexts()
  elseif event=="PLAYER_ENTERING_WORLD" then
    Reanchor(); ApplyAppearance(); UpdateTexts()
  else
    UpdateTexts()
  end
end)

local tick=0
f:SetScript("OnUpdate", function(_,dt)
  tick=tick+(dt or 0)
  if tick>=1 then tick=0; UpdateTexts() end
end)

SLASH_XPBUDDY1="/xpb"
SLASH_XPBUDDY2="/xpbuddy"
SlashCmdList["XPBUDDY"]=function(msg)
  msg=(msg or ""):lower():gsub("^%s+",""):gsub("%s+$","")
  if msg=="reset" then
    XPBuddyDB.point,XPBuddyDB.relPoint,XPBuddyDB.x,XPBuddyDB.y="CENTER","CENTER",0,120
    Reanchor()
  elseif msg=="session" then
    ResetSession();UpdateTexts()
  elseif msg=="on" then
    XPBuddyDB.enabled=true;ApplyAppearance()
    DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441XPBuddy|r: Enabled.")
  elseif msg=="off" then
    XPBuddyDB.enabled=false;ApplyAppearance()
    DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441XPBuddy|r: Disabled.")
  elseif msg=="toggle" then
    XPBuddyDB.enabled = (XPBuddyDB.enabled == false)
    ApplyAppearance()
    DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441XPBuddy|r: "..(XPBuddyDB.enabled and "Enabled." or "Disabled."))
  else
    InterfaceOptionsFrame_OpenToCategory(ADDON)
    InterfaceOptionsFrame_OpenToCategory(ADDON)
  end
end

local panel=CreateFrame("Frame",ADDON)
panel.name=ADDON
panel.title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
panel.title:SetPoint("TOPLEFT",16,-16)
panel.title:SetText("XPBuddy Options")
panel.sub=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
panel.sub:SetPoint("TOPLEFT",panel.title,"BOTTOMLEFT",0,-8)
panel.sub:SetText("Professional XP HUD controls • /xpb on | off | toggle")

local function Check(parent,label,tip)
  local b=CreateFrame("CheckButton",nil,parent,"OptionsCheckButtonTemplate")
  b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlight")
  b.text:SetPoint("LEFT",b,"RIGHT",4,0)
  b.text:SetText(label)
  b.tooltipText=label;b.tooltipRequirement=tip
  return b
end

local function Slider(parent,name,label,minv,maxv,step)
  local s=CreateFrame("Slider",name,parent,"OptionsSliderTemplate")
  s:SetMinMaxValues(minv,maxv);s:SetValueStep(step)
  _G[name.."Low"]:SetText(tostring(minv))
  _G[name.."High"]:SetText(tostring(maxv))
  _G[name.."Text"]:SetText(label)
  return s
end

local enableCB=Check(panel,"Enable XPBuddy HUD","Master switch for the XPBuddy HUD. Your settings and session data are preserved while disabled.")
enableCB:SetPoint("TOPLEFT",panel.sub,"BOTTOMLEFT",0,-14)
local lockCB=Check(panel,"Lock Frame","Disable dragging.")
lockCB:SetPoint("TOPLEFT",enableCB,"BOTTOMLEFT",0,-8)
local backCB=Check(panel,"Show Frame Artwork","Toggle the custom frame texture.")
backCB:SetPoint("TOPLEFT",lockCB,"BOTTOMLEFT",0,-8)
local autoCB=Check(panel,"Auto-Reset Session on Login","Start a fresh session each login.")
autoCB:SetPoint("TOPLEFT",backCB,"BOTTOMLEFT",0,-8)
local scaleSL=Slider(panel,"XPBuddyScaleSlider","HUD Scale",0.35,2.0,0.05)
scaleSL:SetPoint("TOPLEFT",autoCB,"BOTTOMLEFT",0,-30)
local fontSL=Slider(panel,"XPBuddyFontSlider","Font Size",8,20,1)
fontSL:SetPoint("TOPLEFT",scaleSL,"BOTTOMLEFT",0,-40)

local scaleValue=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
scaleValue:SetPoint("LEFT",scaleSL,"RIGHT",18,0)
scaleValue:SetTextColor(.95,.82,.35)

local function ScalePreset(label, value, anchor, x)
  local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
  b:SetSize(48,20)
  if anchor then b:SetPoint("LEFT",anchor,"RIGHT",6,0) else b:SetPoint("TOPLEFT",scaleSL,"BOTTOMLEFT",0,-18) end
  b:SetText(label)
  b:SetScript("OnClick",function()
    EnsureDB()
    XPBuddyDB.scale=value
    scaleSL:SetValue(value)
    ApplyAppearance()
  end)
  return b
end
local scale50=ScalePreset("50%",0.50)
local scale75=ScalePreset("75%",0.75,scale50)
local scale100=ScalePreset("100%",1.00,scale75)
local scale125=ScalePreset("125%",1.25,scale100)

local resetSessionBtn=CreateFrame("Button","XPBuddyResetSessionBtn",panel,"UIPanelButtonTemplate")
resetSessionBtn:SetSize(140,22)
resetSessionBtn:SetPoint("TOPLEFT",fontSL,"BOTTOMLEFT",0,-32)
resetSessionBtn:SetText("Reset Session")
local resetPosBtn=CreateFrame("Button","XPBuddyResetPosBtn",panel,"UIPanelButtonTemplate")
resetPosBtn:SetSize(160,22)
resetPosBtn:SetPoint("LEFT",resetSessionBtn,"RIGHT",10,0)
resetPosBtn:SetText("Reset Position")

enableCB:SetScript("OnClick",function(self) EnsureDB(); XPBuddyDB.enabled = self:GetChecked() and true or false; ApplyAppearance() end)
lockCB:SetScript("OnClick",function(self) EnsureDB(); XPBuddyDB.locked = self:GetChecked() and true or false; ApplyAppearance() end)
backCB:SetScript("OnClick",function(self) EnsureDB(); XPBuddyDB.showBackdrop = self:GetChecked() and true or false; ApplyAppearance() end)
autoCB:SetScript("OnClick",function(self) EnsureDB(); XPBuddyDB.autoResetOnLogin = self:GetChecked() and true or false end)
scaleSL:SetScript("OnValueChanged",function(self,val)
  EnsureDB()
  XPBuddyDB.scale=tonumber(string.format("%.2f",val))
  scaleValue:SetText(string.format("%d%%",math.floor((XPBuddyDB.scale*100)+0.5)))
  ApplyAppearance()
end)
fontSL:SetScript("OnValueChanged",function(self,val) EnsureDB(); XPBuddyDB.fontSize=math.floor(val+.5);ApplyAppearance() end)
resetSessionBtn:SetScript("OnClick",function() ResetSession();UpdateTexts() end)
resetPosBtn:SetScript("OnClick",function()
  XPBuddyDB.point,XPBuddyDB.relPoint,XPBuddyDB.x,XPBuddyDB.y="CENTER","CENTER",0,120
  Reanchor()
end)

panel.default=function()
  for k,v in pairs(DEFAULTS) do XPBuddyDB[k]=v end
  Reanchor();ApplyAppearance();UpdateTexts()
end
panel.refresh=function()
  enableCB:SetChecked(XPBuddyDB.enabled ~= false)
  lockCB:SetChecked(XPBuddyDB.locked)
  backCB:SetChecked(XPBuddyDB.showBackdrop)
  autoCB:SetChecked(XPBuddyDB.autoResetOnLogin)
  scaleSL:SetValue(XPBuddyDB.scale or 1)
  scaleValue:SetText(string.format("%d%%",math.floor(((XPBuddyDB.scale or 1)*100)+0.5)))
  fontSL:SetValue(XPBuddyDB.fontSize or 12)
end
InterfaceOptions_AddCategory(panel)

local loader=CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent",function()
  Reanchor();ApplyAppearance();UpdateTexts()
end)
