-- ═══════════════════════════════════════════════════════════════════════════
-- ArcUI_ButtonPressHighlight.lua
-- Visual feedback overlay on CDM / Arc Auras frames when pressing keybinds
-- Two modes:
--   "hold"  = overlay persists while the action button is pushed
--   "flash" = overlay flashes briefly then auto-releases
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON, ns = ...
ns.ButtonPressHighlight = ns.ButtonPressHighlight or {}
local BPH = ns.ButtonPressHighlight

-- ═══════════════════════════════════════════════════════════════════════════
-- LOCALS
-- ═══════════════════════════════════════════════════════════════════════════
local buttonCache    = {}         -- all scanned action bar buttons
local bindMap        = {}         -- [keybindString] = { spellID=, itemID=, buttons={} }
local activeOverlays = {}         -- [key] = { texture=, buttons={}, id= }
local modifierState  = {}         -- track shift/ctrl/alt
local isActive       = false
local enhancedFrames               -- lazy CDMEnhance reference
local texPool                      -- CreateTexturePool (lazy init)
local watcherFrame                 -- keyboard/mouse event watcher
local updateFrame                  -- OnUpdate for hold-mode cleanup
local bindsDirty     = true        -- flag to rebuild on next keypress

-- Mouse button name → keybind string
local mouseButtonMap = {
  ["MiddleButton"] = "BUTTON3",
  ["Button4"]      = "BUTTON4",
  ["Button5"]      = "BUTTON5",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- MASQUE SHAPE INTEGRATION
-- Match overlay shape to Masque skins (circle, hex, etc.) by copying the
-- mask texture from the parent frame's Icon child.
-- ═══════════════════════════════════════════════════════════════════════════
local cachedMasqueAPI

local function GetMasqueAPI()
  if cachedMasqueAPI == nil then
    cachedMasqueAPI = LibStub and LibStub("Masque", true) or false
  end
  return cachedMasqueAPI or nil
end

local function GetMasqueShape(frame)
  if not frame then return nil end
  -- Respect the global toggle shared with ACH
  if ns.db and ns.db.profile and ns.db.profile.cdmEnhance
      and ns.db.profile.cdmEnhance.glowUseMasqueShapes == false then
    return nil
  end
  local mcfg = frame._MSQ_CFG
  if not mcfg or not mcfg.Enabled or mcfg.BaseSkin then return nil end
  return mcfg.Shape
end

-- Find mask textures applied to the parent frame's Icon child
-- Returns a list of mask texture objects we should copy onto our overlay
local function FindIconMasks(parentFrame)
  if not parentFrame then return nil end
  local icon = parentFrame.Icon or parentFrame.icon
  if not icon then
    -- Try first texture child as fallback
    for _, child in pairs({ parentFrame:GetRegions() }) do
      if child:IsObjectType("Texture") and child:GetDrawLayer() == "BACKGROUND" then
        icon = child
        break
      end
    end
  end
  if not icon or not icon.GetMaskTexture then return nil end

  local masks = {}
  local i = 1
  while true do
    local mask = icon:GetMaskTexture(i)
    if not mask then break end
    tinsert(masks, mask)
    i = i + 1
  end

  return #masks > 0 and masks or nil
end

-- Apply Masque shape masks to an overlay texture
local function ApplyMasqueShapeToTexture(tex, parentFrame)
  if not tex or not parentFrame then return end

  -- Check BPH-specific toggle
  local db = BPH._getDB and BPH._getDB() or nil
  if db and db.useMasqueShapes == false then return end

  local shape = GetMasqueShape(parentFrame)
  if not shape then
    -- No Masque shape — remove any previously applied masks
    if tex._bphMasks then
      for _, mask in ipairs(tex._bphMasks) do
        tex:RemoveMaskTexture(mask)
      end
      tex._bphMasks = nil
      tex._bphMasqueShape = nil
    end
    return
  end

  -- Already applied this shape
  if tex._bphMasqueShape == shape then return end

  -- Remove old masks first
  if tex._bphMasks then
    for _, mask in ipairs(tex._bphMasks) do
      tex:RemoveMaskTexture(mask)
    end
    tex._bphMasks = nil
  end

  -- Copy masks from the parent's icon
  local masks = FindIconMasks(parentFrame)
  if masks then
    tex._bphMasks = {}
    for _, mask in ipairs(masks) do
      tex:AddMaskTexture(mask)
      tinsert(tex._bphMasks, mask)
    end
  end

  tex._bphMasqueShape = shape
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DB ACCESS (char-level, same pattern as ACH)
-- ═══════════════════════════════════════════════════════════════════════════
local BPH_DEFAULTS = {
  enabled         = false,
  mode            = "flash",     -- "hold" or "flash"
  flashDuration   = 0.1,
  textureType     = 1,           -- 1=color, 2=quest border, 3=custom
  color           = { r = 0.95, g = 0.95, b = 0.32, a = 0.45 },
  useCustomColor  = false,
  customColor     = { r = 0.2, g = 0.6, b = 1.0, a = 0.5 },
  customTexture   = "",
  txLeft = 0, txRight = 1, txTop = 0, txBottom = 1,
  onArcAuras      = false,
  useMasqueShapes = false,
}

local function GetDB()
  if not ArcUIDB then return nil end
  if not ArcUIDB.char then ArcUIDB.char = {} end

  local playerName = UnitName("player")
  local realmName  = GetRealmName()
  if not playerName or playerName == "" or not realmName or realmName == "" then
    return nil
  end

  local charKey = playerName .. " - " .. realmName
  if not ArcUIDB.char[charKey] then ArcUIDB.char[charKey] = {} end
  local charDB = ArcUIDB.char[charKey]

  if not charDB.bphSettings then
    charDB.bphSettings = {}
    for k, v in pairs(BPH_DEFAULTS) do
      if type(v) == "table" then
        charDB.bphSettings[k] = {}
        for kk, vv in pairs(v) do charDB.bphSettings[k][kk] = vv end
      else
        charDB.bphSettings[k] = v
      end
    end
  end

  return charDB.bphSettings
end

-- Expose for Masque shape helper
BPH._getDB = GetDB

local function IsEnabled()
  local db = GetDB()
  return db and db.enabled or false
end

local function GetMode()
  local db = GetDB()
  return db and db.mode or "flash"
end

local function GetFlashDuration()
  local db = GetDB()
  return db and db.flashDuration or 0.1
end

local function GetTextureType()
  local db = GetDB()
  return db and db.textureType or 1
end

local function GetColor()
  local db = GetDB()
  if not db then return 0.95, 0.95, 0.32, 0.45 end
  if db.useCustomColor and db.customColor then
    local c = db.customColor
    return c.r or 0.2, c.g or 0.6, c.b or 1.0, c.a or 0.5
  end
  local c = db.color
  return c.r or 0.95, c.g or 0.95, c.b or 0.32, c.a or 0.45
end

local function IsArcAurasEnabled()
  local db = GetDB()
  return db and db.onArcAuras or false
end

local function UseMasqueShapes()
  local db = GetDB()
  return db and db.useMasqueShapes or false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TEXTURE SETUP (built once from settings, called on Enable/settings change)
-- ═══════════════════════════════════════════════════════════════════════════
local SetOverlayTexture  -- function(texture) — configured at Enable time

local function BuildOverlayFunc()
  local db = GetDB()
  if not db then return end

  local texType = db.textureType or 1
  local r, g, b, a = GetColor()

  if texType == 1 then
    SetOverlayTexture = function(tex)
      tex:SetColorTexture(r, g, b, a)
    end
  elseif texType == 2 then
    if db.useCustomColor then
      SetOverlayTexture = function(tex)
        tex:SetTexture([[Interface\ContainerFrame\UI-Icon-QuestBorder]])
        tex:SetDesaturated(true)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(r, g, b, a)
      end
    else
      SetOverlayTexture = function(tex)
        tex:SetTexture([[Interface\ContainerFrame\UI-Icon-QuestBorder]])
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetDesaturated(false)
      end
    end
  elseif texType == 3 then
    local path = db.customTexture or ""
    local tL, tR = db.txLeft or 0, db.txRight or 1
    local tT, tB = db.txTop or 0, db.txBottom or 1
    if db.useCustomColor then
      SetOverlayTexture = function(tex)
        tex:SetTexture(path)
        tex:SetTexCoord(tL, tR, tT, tB)
        tex:SetDesaturated(true)
        tex:SetVertexColor(r, g, b, a)
      end
    else
      SetOverlayTexture = function(tex)
        tex:SetTexture(path)
        tex:SetTexCoord(tL, tR, tT, tB)
        tex:SetDesaturated(false)
      end
    end
  elseif texType == 4 then
    -- Blizzard Pushed (UI-HUD-ActionBar-IconFrame-Down)
    if db.useCustomColor then
      SetOverlayTexture = function(tex)
        tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
        tex:SetDesaturated(true)
        tex:SetVertexColor(r, g, b, a)
      end
    else
      SetOverlayTexture = function(tex)
        tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
      end
    end
  elseif texType == 5 then
    -- Blizzard Highlight (UI-HUD-ActionBar-IconFrame-Mouseover)
    if db.useCustomColor then
      SetOverlayTexture = function(tex)
        tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover", false)
        tex:SetDesaturated(true)
        tex:SetVertexColor(r, g, b, a)
      end
    else
      SetOverlayTexture = function(tex)
        tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover", false)
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
      end
    end
  elseif texType == 6 then
    -- Blizzard Flash (UI-HUD-ActionBar-IconFrame-Flash)
    if db.useCustomColor then
      SetOverlayTexture = function(tex)
        tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Flash", false)
        tex:SetDesaturated(true)
        tex:SetVertexColor(r, g, b, a)
      end
    else
      SetOverlayTexture = function(tex)
        tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Flash", false)
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
      end
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SLOT → BINDING MAPPINGS (matches ArcUI_Keybinds.lua exactly)
-- ═══════════════════════════════════════════════════════════════════════════
local SLOT_MAPPINGS = {
  { startSlot = 1,   binding = "ACTIONBUTTON" },           -- Action Bar 1
  { startSlot = 61,  binding = "MULTIACTIONBAR1BUTTON" },  -- MultiBarBottomLeft
  { startSlot = 49,  binding = "MULTIACTIONBAR2BUTTON" },  -- MultiBarBottomRight
  { startSlot = 25,  binding = "MULTIACTIONBAR3BUTTON" },  -- MultiBarRight
  { startSlot = 37,  binding = "MULTIACTIONBAR4BUTTON" },  -- MultiBarLeft
  { startSlot = 145, binding = "MULTIACTIONBAR5BUTTON" },  -- MultiBar5
  { startSlot = 157, binding = "MULTIACTIONBAR6BUTTON" },  -- MultiBar6
  { startSlot = 169, binding = "MULTIACTIONBAR7BUTTON" },  -- MultiBar7
}

-- slot → list of button frames (used in hold mode to check PUSHED state)
local slotToButtons = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- BUTTON CACHE: scan ElvUI + Blizzard action bars, build slot→buttons map
-- ═══════════════════════════════════════════════════════════════════════════
local function BuildButtonCache()
  wipe(buttonCache)
  wipe(slotToButtons)

  -- ElvUI bars 1–15
  for i = 1, 15 do
    local bar = "ElvUI_Bar" .. i
    for j = 1, 12 do
      local btn = _G[bar .. "Button" .. j]
      if btn then tinsert(buttonCache, btn) end
    end
  end

  -- Blizzard bars
  local blizzBars = {
    "Action", "MultiBarBottomLeft", "MultiBarRight", "MultiBarBottomRight",
    "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "Stance",
  }
  for _, barName in ipairs(blizzBars) do
    for i = 1, 12 do
      local btn = _G[barName .. "Button" .. i]
      if btn then tinsert(buttonCache, btn) end
    end
  end

  -- Build slot → buttons map for hold-mode PUSHED checks
  for _, btn in ipairs(buttonCache) do
    local ok, forbidden = pcall(function() return btn:IsForbidden() end)
    if ok and not forbidden and btn.action then
      local slot = btn._state_action or btn.action
      if slot then
        if not slotToButtons[slot] then slotToButtons[slot] = {} end
        tinsert(slotToButtons[slot], btn)
      end
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTION HELPERS
-- ═══════════════════════════════════════════════════════════════════════════
local function GetActionSpellID(slot)
  local actionType, id = GetActionInfo(slot)
  if actionType == "spell" then return id end
  if actionType == "macro" then return GetMacroSpell(id) end
  return nil
end

local function GetActionItemID(slot)
  local actionType, id = GetActionInfo(slot)
  if actionType == "item" then return id end
  if actionType == "macro" then return GetMacroItem(id) end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BIND MAP: keybind string → { spellID=, itemID=, buttons={} }
-- Uses correct slot→binding mapping (same as ArcUI_Keybinds.lua)
-- ═══════════════════════════════════════════════════════════════════════════
local function RebuildBindMap()
  wipe(bindMap)

  local function RegisterBinding(bindingName, slot)
    if not HasAction(slot) then return end
    local spellID = GetActionSpellID(slot)
    local itemID  = GetActionItemID(slot)
    if not (spellID or itemID) then return end
    local buttons = slotToButtons[slot] or {}
    local binds = { GetBindingKey(bindingName) }
    for _, key in ipairs(binds) do
      if key and key ~= "" and not bindMap[key] then
        bindMap[key] = { spellID = spellID, itemID = itemID, buttons = buttons }
      end
    end
  end

  -- Pass 1: ElvUI buttons with keyBoundTarget (covers all ElvUI bars 1-15 with correct
  -- binding names, including ELVUIBAR13/14/15BUTTON for bars 13-15)
  local slotsCoveredByElvUI = {}
  for _, btn in ipairs(buttonCache) do
    local ok, forbidden = pcall(function() return btn:IsForbidden() end)
    if ok and not forbidden and btn.keyBoundTarget and btn.keyBoundTarget ~= "" then
      local slot = btn._state_action or btn.action
      if slot then
        slotsCoveredByElvUI[slot] = true
        RegisterBinding(btn.keyBoundTarget, slot)
      end
    end
  end

  -- Pass 2: Standard Blizzard slot mappings for any slot not already handled by ElvUI
  for _, mapping in ipairs(SLOT_MAPPINGS) do
    for i = 1, 12 do
      local slot = mapping.startSlot + i - 1
      if not slotsCoveredByElvUI[slot] then
        RegisterBinding(mapping.binding .. i, slot)
      end
    end
  end

  -- Bonus bars (stances/forms): slots 73-120 use ACTIONBUTTON bindings when active
  local bonusOffset = C_ActionBar and C_ActionBar.GetBonusBarOffset
    and C_ActionBar.GetBonusBarOffset()
  if bonusOffset and not issecretvalue(bonusOffset) and bonusOffset > 0 then
    local bonusStart = 72 + ((bonusOffset - 1) * 12) + 1
    for i = 1, 12 do
      local slot = bonusStart + i - 1
      if slot <= 120 and not slotsCoveredByElvUI[slot] then
        RegisterBinding("ACTIONBUTTON" .. i, slot)
      end
    end
  end

  bindsDirty = false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CDM FRAME MATCHING (pcall-safe for secret values)
-- ═══════════════════════════════════════════════════════════════════════════
local function CDMFrameMatchesSpell(frame, targetSpellID)
  if not frame or not targetSpellID then return false end
  local info = frame.cooldownInfo
  if not info then return false end

  local ok, matched = pcall(function()
    if info.spellID and info.spellID == targetSpellID then return true end
    if info.overrideSpellID and info.overrideSpellID == targetSpellID then return true end
    if info.overrideTooltipSpellID and info.overrideTooltipSpellID == targetSpellID then return true end
    if info.linkedSpellID and info.linkedSpellID == targetSpellID then return true end
    if info.linkedSpellIDs then
      for _, linkedID in ipairs(info.linkedSpellIDs) do
        if linkedID == targetSpellID then return true end
      end
    end
    if frame.GetAuraSpellID then
      local auraSpellID = frame:GetAuraSpellID()
      if auraSpellID and auraSpellID == targetSpellID then return true end
    end
    return false
  end)

  return ok and matched or false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- OVERLAY MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════
local function CleanupTextureMasks(tex)
  if tex and tex._bphMasks then
    for _, mask in ipairs(tex._bphMasks) do
      tex:RemoveMaskTexture(mask)
    end
    tex._bphMasks = nil
    tex._bphMasqueShape = nil
  end
end

local function ReleaseAllOverlays()
  if not texPool then return end
  for key, data in pairs(activeOverlays) do
    if data and data.texture then
      CleanupTextureMasks(data.texture)
      texPool:Release(data.texture)
    end
    activeOverlays[key] = nil
  end
end

local function ReleaseOverlay(key)
  local data = activeOverlays[key]
  if not data then return end
  if data.texture then
    CleanupTextureMasks(data.texture)
    if texPool then texPool:Release(data.texture) end
  end
  activeOverlays[key] = nil
end

local function ShowOverlayOnFrame(frame, key, bindInfo)
  if not frame or not SetOverlayTexture then return end
  if activeOverlays[key] then return end  -- already showing

  if not texPool then
    texPool = CreateTexturePool(UIParent, "OVERLAY", 7)
  end

  local tex = texPool:Acquire()
  SetOverlayTexture(tex)
  tex:SetParent(frame)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", frame, "TOPLEFT")
  tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")

  -- Apply Masque shape mask if enabled
  if UseMasqueShapes() then
    ApplyMasqueShapeToTexture(tex, frame)
  end

  tex:Show()

  activeOverlays[key] = {
    texture = tex,
    buttons = bindInfo and bindInfo.buttons or {},
    spellID = bindInfo and bindInfo.spellID,
    itemID  = bindInfo and bindInfo.itemID,
  }

  -- Flash mode: auto-release after duration
  if GetMode() == "flash" then
    local dur = GetFlashDuration()
    C_Timer.After(dur, function()
      if activeOverlays[key] and activeOverlays[key].texture == tex then
        ReleaseOverlay(key)
      end
    end)
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FIND MATCHING CDM FRAMES FOR A SPELL/ITEM
-- ═══════════════════════════════════════════════════════════════════════════
local function FindAndHighlightCDMFrames(spellID, itemID, bindInfo)
  if not enhancedFrames then
    if ns.CDMEnhance and ns.CDMEnhance.GetEnhancedFrames then
      enhancedFrames = ns.CDMEnhance.GetEnhancedFrames()
    end
  end

  if enhancedFrames and spellID then
    for cdID, data in pairs(enhancedFrames) do
      if data and data.frame and data.frame:IsShown() then
        if CDMFrameMatchesSpell(data.frame, spellID) then
          ShowOverlayOnFrame(data.frame, "cdm_" .. cdID, bindInfo)
        end
      end
    end
  end

  -- Arc Auras Cooldown frames
  if IsArcAurasEnabled() and spellID then
    local AACooldown = ns.ArcAurasCooldown
    if AACooldown and AACooldown.spellsByID then
      local arcID = AACooldown.spellsByID[spellID]
      if arcID and AACooldown.spellData then
        local fd = AACooldown.spellData[arcID]
        if fd and fd.frame and fd.frame:IsShown() and not fd.frame._arcHiddenNotInSpec then
          ShowOverlayOnFrame(fd.frame, "aa_" .. arcID, bindInfo)
        end
      end
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HOLD MODE: OnUpdate checks if buttons are still pushed
-- ═══════════════════════════════════════════════════════════════════════════
local holdElapsed = 0
local function OnUpdate_Hold(self, elapsed)
  holdElapsed = holdElapsed + elapsed
  if holdElapsed < 0.03 then return end
  holdElapsed = 0

  if not IsShiftKeyDown()   then modifierState["LSHIFT"] = nil end
  if not IsControlKeyDown() then modifierState["LCTRL"]  = nil end
  if not IsAltKeyDown()     then modifierState["LALT"]   = nil end

  for key, data in pairs(activeOverlays) do
    local stillPushed = false
    if data.buttons then
      for _, btn in ipairs(data.buttons) do
        if btn:GetButtonState() == "PUSHED" then
          stillPushed = true
          break
        end
      end
    end
    if not stillPushed then
      ReleaseOverlay(key)
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FLASH MODE: OnUpdate just tracks modifiers (overlays self-release via timer)
-- ═══════════════════════════════════════════════════════════════════════════
local function OnUpdate_Flash(self, elapsed)
  holdElapsed = holdElapsed + elapsed
  if holdElapsed < 0.03 then return end
  holdElapsed = 0

  if not IsShiftKeyDown()   then modifierState["LSHIFT"] = nil end
  if not IsControlKeyDown() then modifierState["LCTRL"]  = nil end
  if not IsAltKeyDown()     then modifierState["LALT"]   = nil end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEY / MOUSE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════
local function GetCurrentModifier()
  for modKey in pairs(modifierState) do
    return modKey:match("^.(.*)")  -- "LSHIFT" → "SHIFT"
  end
  return nil
end

local function HandleKeyDown(self, key)
  if not isActive then return end
  if bindsDirty then RebuildBindMap() end

  local mod = GetCurrentModifier()
  local fullKey = mod and (mod .. "-" .. key) or key

  local bindInfo = bindMap[fullKey]
  if bindInfo then
    FindAndHighlightCDMFrames(bindInfo.spellID, bindInfo.itemID, bindInfo)
  end
end

local function HandleMouseDown(self, button)
  if not isActive then return end
  local mapped = mouseButtonMap[button]
  if mapped then
    HandleKeyDown(nil, mapped)
  end
end

local function HandleModifier(self, event, key, state)
  if event == "MODIFIER_STATE_CHANGED" then
    modifierState[key] = (state == 1) or nil
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BINDING REFRESH (throttled)
-- ═══════════════════════════════════════════════════════════════════════════
local lastBindRefresh = 0
local function ScheduleBindRefresh()
  if not isActive then return end
  local now = GetTime()
  if now - lastBindRefresh < 0.2 then return end
  lastBindRefresh = now

  if InCombatLockdown() then
    bindsDirty = true
  else
    C_Timer.After(1, function()
      if isActive then
        RebuildBindMap()
      end
    end)
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API: Enable / Disable / Refresh
-- ═══════════════════════════════════════════════════════════════════════════
function BPH.Enable()
  if isActive then return end
  isActive = true

  BuildButtonCache()
  RebuildBindMap()
  BuildOverlayFunc()

  if not watcherFrame then
    watcherFrame = CreateFrame("Frame", nil, UIParent)
  end
  watcherFrame:SetScript("OnKeyDown", HandleKeyDown)
  watcherFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MODIFIER_STATE_CHANGED" then
      HandleModifier(self, event, ...)
    elseif event == "SPELLS_CHANGED" or event == "ACTIONBAR_SLOT_CHANGED"
      or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_ENTERING_WORLD"
      or event == "UPDATE_BINDINGS" then
      ScheduleBindRefresh()
    end
  end)
  watcherFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
  watcherFrame:RegisterEvent("SPELLS_CHANGED")
  watcherFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  watcherFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
  watcherFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  watcherFrame:RegisterEvent("UPDATE_BINDINGS")
  watcherFrame:SetPropagateKeyboardInput(true)

  if not updateFrame then
    updateFrame = CreateFrame("Frame")
  end
  if GetMode() == "hold" then
    updateFrame:SetScript("OnUpdate", OnUpdate_Hold)
  else
    updateFrame:SetScript("OnUpdate", OnUpdate_Flash)
  end

  if EventRegistry then
    EventRegistry:RegisterFrameEventAndCallback("GLOBAL_MOUSE_DOWN", function(_, button)
      HandleMouseDown(nil, button)
    end, BPH)
  end

  if ns.devMode then
    print("|cff00FF00[ArcUI]|r Button Press Highlight enabled")
  end
end

function BPH.Disable()
  if not isActive then return end
  isActive = false

  ReleaseAllOverlays()

  if watcherFrame then
    watcherFrame:SetScript("OnKeyDown", nil)
    watcherFrame:SetScript("OnEvent", nil)
    watcherFrame:UnregisterAllEvents()
  end

  if updateFrame then
    updateFrame:SetScript("OnUpdate", nil)
  end

  if EventRegistry then
    EventRegistry:UnregisterFrameEventAndCallback("GLOBAL_MOUSE_DOWN", BPH)
  end

  if ns.devMode then
    print("|cffFF6600[ArcUI]|r Button Press Highlight disabled")
  end
end

function BPH.Refresh()
  if not isActive then return end
  ReleaseAllOverlays()
  enhancedFrames = nil
  cachedMasqueAPI = nil
  BuildButtonCache()
  RebuildBindMap()
  BuildOverlayFunc()

  if updateFrame then
    if GetMode() == "hold" then
      updateFrame:SetScript("OnUpdate", OnUpdate_Hold)
    else
      updateFrame:SetScript("OnUpdate", OnUpdate_Flash)
    end
  end
end

function BPH.IsActive()
  return isActive
end

function BPH.OnFrameReleased(cdID)
  ReleaseOverlay("cdm_" .. cdID)
end

function BPH.RefreshMasqueShapes()
  cachedMasqueAPI = nil
  for key, data in pairs(activeOverlays) do
    if data and data.texture then
      data.texture._bphMasqueShape = nil
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
  self:UnregisterAllEvents()
  C_Timer.After(2.5, function()
    if IsEnabled() then
      BPH.Enable()
    end
  end)
end)


-- ═══════════════════════════════════════════════════════════════════════════
-- OPTIONS MODULE (ns.ButtonPressHighlightOptions)
-- Exports GetCooldownArgs() for merging into the unified CDMEnhance panel.
-- Uses a CollapsibleHeader that defaults to closed via collapsedSections.
-- ═══════════════════════════════════════════════════════════════════════════
ns.ButtonPressHighlightOptions = ns.ButtonPressHighlightOptions or {}

function ns.ButtonPressHighlightOptions.GetCooldownArgs()
  local function db() return GetDB() end

  -- Lazy accessor for collapsedSections (resolve at call time, not build time)
  local function IsCollapsed()
    local h = ns.OptionsHelpers
    if h and h.collapsedSections then
      return h.collapsedSections.buttonPressHighlight
    end
    return true  -- default collapsed
  end

  local function HideBPH()
    return IsCollapsed()
  end

  local args = {}

  -- ── Collapsible Header (toggle to expand/collapse) ──
  args.bphHeader = {
    type = "toggle",
    name = "|cffFFD100Button Press Highlight|r",
    desc = "Click to expand/collapse.",
    dialogControl = "CollapsibleHeader",
    order = 100,
    width = "full",
    get = function()
      local h = ns.OptionsHelpers
      if h and h.collapsedSections then
        return not h.collapsedSections.buttonPressHighlight
      end
      return false
    end,
    set = function(_, v)
      local h = ns.OptionsHelpers
      if h and h.collapsedSections then
        h.collapsedSections.buttonPressHighlight = not v
      end
    end,
  }

  args.bphDesc = {
    type = "description",
    name = "Flash or hold a highlight overlay on CDM icons when you press the matching keybind on your action bars. Scans ElvUI and Blizzard action bars.",
    order = 100.01,
    fontSize = "medium",
    hidden = HideBPH,
  }

  args.bphEnabled = {
    type = "toggle",
    name = "Enable Button Press Highlight",
    desc = "Show a visual overlay on CDM icons when you press their keybind.",
    order = 100.02,
    width = "full",
    get = function() local d = db(); return d and d.enabled or false end,
    set = function(_, val)
      local d = db()
      if d then d.enabled = val end
      if val then BPH.Enable() else BPH.Disable() end
    end,
    hidden = HideBPH,
  }

  args.bphMode = {
    type = "select",
    name = "Mode",
    desc = "Hold: overlay stays while button is pressed. Flash: brief pulse then auto-releases.",
    order = 100.03,
    width = 1.0,
    values = { hold = "Hold", flash = "Flash" },
    get = function() local d = db(); return d and d.mode or "flash" end,
    set = function(_, val)
      local d = db()
      if d then d.mode = val end
      if isActive then BPH.Refresh() end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = HideBPH,
  }

  args.bphFlashDuration = {
    type = "range",
    name = "Flash Duration",
    desc = "How long the overlay is shown in flash mode (seconds).",
    order = 100.04,
    min = 0.05, max = 0.5, step = 0.01,
    width = 1.0,
    get = function() local d = db(); return d and d.flashDuration or 0.1 end,
    set = function(_, val)
      local d = db()
      if d then d.flashDuration = val end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = function() return HideBPH() or GetMode() ~= "flash" end,
  }

  args.bphTextureType = {
    type = "select",
    name = "Texture",
    desc = "Visual style of the button press overlay.",
    order = 100.05,
    width = 1.0,
    values = { [1] = "Color Fill", [2] = "Quest Border", [3] = "Custom Texture", [4] = "Blizzard Pushed", [5] = "Blizzard Highlight", [6] = "Blizzard Flash" },
    get = function() local d = db(); return d and d.textureType or 1 end,
    set = function(_, val)
      local d = db()
      if d then d.textureType = val end
      if isActive then BuildOverlayFunc() end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = HideBPH,
  }

  args.bphUseCustomColor = {
    type = "toggle",
    name = "Use Custom Color",
    desc = "Override the default yellow highlight with a custom color.",
    order = 100.06,
    width = 1.0,
    get = function() local d = db(); return d and d.useCustomColor or false end,
    set = function(_, val)
      local d = db()
      if d then d.useCustomColor = val end
      if isActive then BuildOverlayFunc() end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = HideBPH,
  }

  args.bphColor = {
    type = "color",
    name = "Overlay Color",
    desc = "Color and opacity of the overlay.",
    order = 100.07,
    hasAlpha = true,
    width = 1.0,
    get = function()
      local d = db()
      if not d then return 0.2, 0.6, 1.0, 0.5 end
      local c = d.customColor or BPH_DEFAULTS.customColor
      return c.r, c.g, c.b, c.a
    end,
    set = function(_, r, g, b, a)
      local d = db()
      if d then d.customColor = { r = r, g = g, b = b, a = a } end
      if isActive then BuildOverlayFunc() end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = function()
      if HideBPH() then return true end
      local d = db()
      return not (d and d.useCustomColor)
    end,
  }

  args.bphCustomTexture = {
    type = "input",
    name = "Custom Texture Path",
    desc = "Interface path for a custom overlay texture (e.g. Interface\\...)",
    order = 100.08,
    width = "full",
    get = function() local d = db(); return d and d.customTexture or "" end,
    set = function(_, val)
      local d = db()
      if d then d.customTexture = val end
      if isActive then BuildOverlayFunc() end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = function() return HideBPH() or GetTextureType() ~= 3 end,
  }

  args.bphTxLeft = {
    type = "range", name = "Tex Left", order = 100.081,
    min = 0, max = 1, step = 0.01, width = 0.5,
    get = function() local d = db(); return d and d.txLeft or 0 end,
    set = function(_, v) local d = db(); if d then d.txLeft = v end; if isActive then BuildOverlayFunc() end end,
    disabled = function() return not IsEnabled() end,
    hidden = function() return HideBPH() or GetTextureType() ~= 3 end,
  }

  args.bphTxRight = {
    type = "range", name = "Tex Right", order = 100.082,
    min = 0, max = 1, step = 0.01, width = 0.5,
    get = function() local d = db(); return d and d.txRight or 1 end,
    set = function(_, v) local d = db(); if d then d.txRight = v end; if isActive then BuildOverlayFunc() end end,
    disabled = function() return not IsEnabled() end,
    hidden = function() return HideBPH() or GetTextureType() ~= 3 end,
  }

  args.bphTxTop = {
    type = "range", name = "Tex Top", order = 100.083,
    min = 0, max = 1, step = 0.01, width = 0.5,
    get = function() local d = db(); return d and d.txTop or 0 end,
    set = function(_, v) local d = db(); if d then d.txTop = v end; if isActive then BuildOverlayFunc() end end,
    disabled = function() return not IsEnabled() end,
    hidden = function() return HideBPH() or GetTextureType() ~= 3 end,
  }

  args.bphTxBottom = {
    type = "range", name = "Tex Bottom", order = 100.084,
    min = 0, max = 1, step = 0.01, width = 0.5,
    get = function() local d = db(); return d and d.txBottom or 1 end,
    set = function(_, v) local d = db(); if d then d.txBottom = v end; if isActive then BuildOverlayFunc() end end,
    disabled = function() return not IsEnabled() end,
    hidden = function() return HideBPH() or GetTextureType() ~= 3 end,
  }

  args.bphUseMasqueShapes = {
    type = "toggle",
    name = "Match Masque Shape",
    desc = "Apply the icon's Masque mask to the overlay so it matches the skin shape (circle, hex, etc.).",
    order = 100.085,
    width = "full",
    get = function() local d = db(); return d and d.useMasqueShapes or false end,
    set = function(_, val)
      local d = db()
      if d then d.useMasqueShapes = val end
      if isActive then BPH.RefreshMasqueShapes() end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = HideBPH,
  }

  args.bphArcAuras = {
    type = "toggle",
    name = "Include Arc Auras Cooldowns",
    desc = "Also highlight matching Arc Auras Cooldown frames on button press.",
    order = 100.09,
    width = "full",
    get = function() local d = db(); return d and d.onArcAuras or false end,
    set = function(_, val)
      local d = db()
      if d then d.onArcAuras = val end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = HideBPH,
  }

  args.bphRefresh = {
    type = "execute",
    name = "Refresh Bindings",
    desc = "Rebuild keybind → spell mapping from your action bars.",
    order = 100.10,
    width = 1.0,
    func = function()
      if isActive then
        BPH.Refresh()
        print("|cff00FF00[ArcUI]|r Button Press Highlight bindings refreshed.")
      end
    end,
    disabled = function() return not IsEnabled() end,
    hidden = HideBPH,
  }

  args.bphStatus = {
    type = "description",
    name = function()
      if not isActive then
        return "|cffFF4444Inactive|r — Enable above to activate."
      end
      local count = 0
      for _ in pairs(bindMap) do count = count + 1 end
      return "|cff00FF00Active|r — " .. count .. " keybinds mapped."
    end,
    order = 100.11,
    fontSize = "medium",
    hidden = HideBPH,
  }

  return args
end