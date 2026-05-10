---@diagnostic disable: inject-field, undefined-field
-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, NotEvenClose = ...

NotEvenClose = LibStub("AceAddon-3.0"):NewAddon(NotEvenClose, "NotEvenClose", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0")
LibRealmInfo = LibStub("LibRealmInfo")

-- Set up DataBroker for minimap button
NecLDB = LibStub("LibDataBroker-1.1"):NewDataObject("NotEvenClose", {
  type = "data source",
  text = "NotEvenClose",
  label = "NotEvenClose",
  icon = "Interface\\AddOns\\NotEvenClose\\logo",
  OnClick = function()
    if NecFrame and NecFrame:IsShown() then
      NecFrame:Hide()
    else
      NotEvenClose:PrintProfile(false)
    end
  end,
  OnTooltipShow = function(tt)
    tt:AddLine("NotEvenClose")
    tt:AddLine(" ")
    tt:AddLine("Click to show NotEvenClose input")
    tt:AddLine("To toggle minimap button, type '/nec minimap'")
  end
})

LibDBIcon = LibStub("LibDBIcon-1.0")

local NecFrame = nil

local NEC_PROFILE_REQ = "NEC_PROFILE_REQ"
local NEC_PROFILE_RESP = "NEC_PROFILE_RESP"

-- GetAddOnMetadata was global until 10.1. It's now in C_AddOns. This line will use C_AddOns if available and work in either WoW build
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- load stuff from extras.lua
-- local upgradeTable        = NotEvenClose.upgradeTable
local specNames           = NotEvenClose.SpecNames

-- Most of the guts of this addon were based on a variety of other ones, including
-- Statslog, AskMrRobot, and BonusScanner. And a bunch of hacking around with AceGUI.
-- Many thanks to the authors of those addons, and to reia for fixing my awful amateur
-- coding mistakes regarding objects and namespaces.

function NotEvenClose:OnInitialize()
  -- init databroker
  self.db = LibStub("AceDB-3.0"):New("NotEvenCloseDB", {
    profile = {
      minimap = {
        hide = false,
      },
      frame = {
        point = "CENTER",
        relativeFrame = nil,
        relativePoint = "CENTER",
        ofsx = 0,
        ofsy = 0,
        width = 750,
        height = 400,
      },
    },
  });
  LibDBIcon:Register("NotEvenClose", NecLDB, self.db.profile.minimap)
  NotEvenClose:UpdateMinimapButton()
  NotEvenClose:RegisterChatCommand('nec', 'HandleChatCommand')
  AddonCompartmentFrame:RegisterAddon({
    text = "NotEvenClose",
    icon = "Interface\\AddOns\\NotEvenClose\\logo",
    notCheckable = true,
    func = function()
      NotEvenClose:PrintProfile(false)
    end,
  })
end

function NotEvenClose:OnEnable()

end

function NotEvenClose:OnDisable()

end

function NotEvenClose:UpdateMinimapButton()
  if (self.db.profile.minimap.hide) then
    LibDBIcon:Hide("NotEvenClose")
  else
    LibDBIcon:Show("NotEvenClose")
  end
end

function NotEvenClose:HandleChatCommand(input)
  local args = {strsplit(' ', input)}

  local debugOutput = false

  for _, arg in ipairs(args) do
    if arg == 'debug' then
      debugOutput = true
    elseif arg == 'minimap' then
      self.db.profile.minimap.hide = not self.db.profile.minimap.hide
      DEFAULT_CHAT_FRAME:AddMessage(
        "NotEvenClose: Minimap button is now " .. (self.db.profile.minimap.hide and "hidden" or "shown")
      )
      NotEvenClose:UpdateMinimapButton()
      return
    end
  end

  self:PrintProfile(debugOutput)
end

-- method to add spaces to UnitRace names for proper tokenization
local function FormatRace(str)
  str = str or ""
  local matches = {}
  for match, _ in string.gmatch(str, '([%u][%l]*)') do
    matches[#matches+1] = match
  end
  return string.join(' ', unpack(matches))
end

local function GetClass()
  local _, classFilename, _ = UnitClass("player")
  if classFilename == "DEATHKNIGHT" then return "Death Knight" end
  if classFilename == "DEMONHUNTER" then return "Demon Hunter" end
  return classFilename:lower():gsub("^%l", string.upper)
end

local function GetBuffString()
  local buffs = {}
  AuraUtil.ForEachAura("player", "HELPFUL", 999999, function(...)
    local _, _, _, _, _, _, _, _, _, spellId, _, _, _, _, _ = ...;
    table.insert(buffs, spellId)
  end)
  return table.concat(buffs, ",")
end

local function GetSpellListString()
  local spellList = {}
  for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
    local offset, numSlots = skillLineInfo.itemIndexOffset, skillLineInfo.numSpellBookItems
    for j = offset+1, offset+numSlots do
      local spellBookItemInfo = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
      table.insert(spellList, spellBookItemInfo.actionID)
    end
  end

  return table.concat(spellList, ",")
end

local function GetTalentListString()
  local configId = C_ClassTalents.GetActiveConfigID()
  local configInfo = C_Traits.GetConfigInfo(configId)

  if not configInfo then
    return nil
  end

  ---@type table<number, number>
  local talentsMap = {}

  for _, treeId in ipairs(configInfo.treeIDs) do
    local nodes = C_Traits.GetTreeNodes(treeId)

    for _, treeNodeId in ipairs(nodes) do
      local treeNode = C_Traits.GetNodeInfo(configId, treeNodeId)

      if treeNode.activeEntry and treeNode.activeRank > 0 then
        local entryInfo = C_Traits.GetEntryInfo(configId, treeNode.activeEntry.entryID)

        if entryInfo.definitionID then
          local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)

          local spellId = definitionInfo.spellID
          if spellId and IsPlayerSpell(spellId) then
            talentsMap[spellId] = treeNode.activeRank
          end
        end
      end
    end
  end

  local talentsMapString = '['
  for k, v in pairs(talentsMap) do
    talentsMapString = talentsMapString .. '[' .. k .. ',' .. v .. '],'
  end
  return talentsMapString:sub(1, -2) .. ']'
end

function NotEvenClose:GetMainFrame(text)
  -- Frame code largely adapted from https://www.wowinterface.com/forums/showpost.php?p=323901&postcount=2
  if not NecFrame then
    -- Main Frame
    local frameConfig = self.db.profile.frame
    local f = CreateFrame("Frame", "NecFrame", UIParent, "DialogBoxFrame")
    f:ClearAllPoints()
    -- load position from local DB
    f:SetPoint(
      frameConfig.point,
      frameConfig.relativeFrame,
      frameConfig.relativePoint,
      frameConfig.ofsx,
      frameConfig.ofsy
    )
    f:SetSize(frameConfig.width, frameConfig.height)
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight",
      edgeSize = 16,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
      if button == "LeftButton" then
        self:StartMoving()
      end
    end)
    f:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
      self:StopMovingOrSizing()
      -- save position between sessions
      local point, relativeFrame, relativeTo, ofsx, ofsy = self:GetPoint()
      frameConfig.point = point
      frameConfig.relativeFrame = relativeFrame
      frameConfig.relativePoint = relativeTo
      frameConfig.ofsx = ofsx
      frameConfig.ofsy = ofsy
    end)

    -- scroll frame
    local sf = CreateFrame("ScrollFrame", "NecScrollFrame", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("LEFT", 16, 0)
    sf:SetPoint("RIGHT", -32, 0)
    sf:SetPoint("TOP", 0, -32)
    sf:SetPoint("BOTTOM", NecFrameButton, "TOP", 0, 0)

    -- edit box
    local eb = CreateFrame("EditBox", "NecEditBox", NecScrollFrame)
    eb:SetSize(sf:GetSize())
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)

    -- resizing
    f:SetResizable(true)
    if f.SetMinResize then
      -- older function from shadowlands and before
      -- Can remove when Dragonflight is in full swing
      f:SetMinResize(150, 100)
    else
      -- new func for dragonflight
      f:SetResizeBounds(150, 100, nil, nil)
    end
    local rb = CreateFrame("Button", "SimcResizeButton", f)
    rb:SetPoint("BOTTOMRIGHT", -6, 7)
    rb:SetSize(16, 16)

    rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    rb:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
        if button == "LeftButton" then
            f:StartSizing("BOTTOMRIGHT")
            self:GetHighlightTexture():Hide() -- more noticeable
        end
    end)
    rb:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
        f:StopMovingOrSizing()
        self:GetHighlightTexture():Show()
        eb:SetWidth(sf:GetWidth())

        -- save size between sessions
        frameConfig.width = f:GetWidth()
        frameConfig.height = f:GetHeight()
    end)

    NecFrame = f
  end
  NecEditBox:SetText(text)
  NecEditBox:HighlightText()
  return NecFrame
end

function NotEvenClose:AppendToMainFrame(text)
  if not NecFrame or not NecEditBox then return end

  local newText = NecEditBox:GetText()
  newText = newText .. "\n##################\n\n"
  newText = newText .. text
  NecEditBox:SetText(newText)
  NecEditBox:HighlightText()
end

function NotEvenClose:GetNecProfile()
  -- addon metadata
  local versionComment = '# NotEvenClose Addon ' .. GetAddOnMetadata('NotEvenClose', 'Version')
  local wowVersion, wowBuild, _, wowToc = GetBuildInfo()
  local wowVersionComment = '# WoW ' .. wowVersion .. '.' .. wowBuild .. ', TOC ' .. wowToc

  -- Basic player info
  local stamina, _, _, _ = UnitStat("player", 3)
  local _, armor, _, _ = UnitArmor("player")
  local versatilityRaw = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)
  local avoidanceRaw = GetCombatRating(CR_AVOIDANCE)

  local strength, _, _, _ = UnitStat("player", LE_UNIT_STAT_STRENGTH)
  local agility, _, _, _ = UnitStat("player", LE_UNIT_STAT_AGILITY)
  local intellect, _, _, _ = UnitStat("player", LE_UNIT_STAT_INTELLECT)
  local mainStat = math.max(strength, agility, intellect)

  local playerName = UnitName('player')

  -- Race info
  local _, playerRace = UnitRace('player')

  -- fix some races to match SimC format
  if playerRace == 'Scourge' then --lulz
    playerRace = 'Undead'
  else
    playerRace = FormatRace(playerRace)
  end

  -- Spec info
  local className = GetClass()
  local globalSpecID
  local specId = GetSpecialization()
  if specId then
    globalSpecID,_,_,_,_,_ = GetSpecializationInfo(specId)
  end
  local playerSpec = specNames[globalSpecID] or 'unknown'

  -- create a header comment with basic player info and a date
  local headerComment = (
    "# " .. playerName .. ' - ' .. playerSpec
    .. ' - ' .. date('%Y-%m-%d %H:%M') .. ' - '
 )

  -- Build the output string for the player (not including gear)
  local printError = nil
  local Profile = ''

  Profile = Profile .. headerComment .. '\n'
  Profile = Profile .. versionComment .. '\n'
  Profile = Profile .. wowVersionComment .. '\n'
  Profile = Profile .. '\n'

  Profile = Profile .. playerRace .. '\n'
  Profile = Profile .. "class=" .. className .. '\n'
  Profile = Profile .. 'spec=' .. playerSpec .. '\n'
  Profile = Profile .. "stamina=" .. stamina .. '\n'
  Profile = Profile .. "versatilityRaw=" .. versatilityRaw .. '\n'
  Profile = Profile .. "avoidanceRaw=" .. avoidanceRaw .. '\n'
  Profile = Profile .. "armor=" .. armor .. '\n'
  Profile = Profile .. "mainStat=" .. mainStat .. '\n'
  Profile = Profile .. "buffs=" .. GetBuffString() .. '\n'
  Profile = Profile .. "spells=" .. GetSpellListString() .. '\n'
  Profile = Profile .. "talents=" .. GetTalentListString() .. '\n'

  -- sanity checks - if there's anything that makes the output completely invalid, punt!
  if specId==nil then
    printError = "Error: You need to pick a spec!"
  end

  return Profile, printError
end

-- This is the workhorse function that constructs the profile
function NotEvenClose:PrintProfile(debugOutput)
  print("NEC: Requesting data from party members. They will only repond if they have the addon.")
  NotEvenClose:SendCommMessage(NEC_PROFILE_REQ, "hi", "PARTY")

  local NotEvenCloseProfile, necPrintError = NotEvenClose:GetNecProfile()

  local f = NotEvenClose:GetMainFrame(necPrintError or NotEvenCloseProfile)
  f:Show()
end

-------------
--- COMMS ---
-------------

function NotEvenClose:OnReqReceived(prefix, message, distribution, sender)
  -- print("NEC: data requested by " .. sender)
  local Profile, necPrintError = NotEvenClose:GetNecProfile()
  NotEvenClose:SendCommMessage(NEC_PROFILE_RESP, necPrintError or Profile, "PARTY")
end

function NotEvenClose:OnRespReceived(prefix, profile, distribution, sender)
  local playerName = UnitName('player')
  if sender == playerName then return end

  print("NEC: data received from " .. sender)
  NotEvenClose:AppendToMainFrame(profile)
end

NotEvenClose:RegisterComm(NEC_PROFILE_REQ, "OnReqReceived")
NotEvenClose:RegisterComm(NEC_PROFILE_RESP, "OnRespReceived")
