-- LifebloomAlert.lua
-- Alerts for Lifebloom pandemic range and missing Lifebloom, with full options UI.
-- Only active when logged in as a Restoration Druid.

-------------------------------------------------------------------------------
-- 1. CONSTANTS & DEFAULTS
-------------------------------------------------------------------------------

local ADDON_NAME = "LifebloomAlert"
local LIFEBLOOM_SPELL_ID = 33763
local LIFEBLOOM_NAME = C_Spell.GetSpellName(LIFEBLOOM_SPELL_ID) or "Lifebloom"
local LIFEBLOOM_ICON = C_Spell.GetSpellTexture(LIFEBLOOM_SPELL_ID)
local SOUND_CHANNEL_LIST = { "Master", "SFX", "Music", "Ambience", "Dialog" }

local SOUND_LIST = {
    { label = "Text To Speech",         value = "tts"  },
    { label = "Raid Warning",           value = 8959   },
    { label = "Ready Check",            value = 8960   },
    { label = "Alarm Clock Warning 2",  value = 12867  },
    { label = "PvP Flag Taken",         value = 8174   },
    { label = "Level Up",               value = 888    },
    { label = "Alarm Clock Warning 3",  value = 12889  },
    { label = "Drum",                   value = 185583 },
}

local TTS_VOICE_LIST = {}

local OUTLINE_LIST  = { "None", "Outline", "Thick Outline" }
local OUTLINE_FLAGS = { "", "OUTLINE", "THICKOUTLINE" }

local BUILTIN_FONTS = {
    { label = "FRIZQT__ (Default)", path = "Fonts\\FRIZQT__.TTF" },
    { label = "Arial Narrow",       path = "Fonts\\ARIALN.TTF"   },
    { label = "Morpheus",           path = "Fonts\\MORPHEUS.TTF" },
    { label = "Skurri",             path = "Fonts\\SKURRI.TTF"   },
}

local DEFAULTS = {
    -- General
    activeInSolo      = true,
    activeInDungeons  = true,
    activeInRaids     = true,
	activeInPvP	  	  = false,

    -- Refresh timer alert
    timerEnabled      = true,
    timerUsePandemic  = true,
    timerCustomSecs   = 4.5,
    timerSoundChoice  = 1,
    timerTTSText      = "Lifebloom",
    timerTTSVoice     = 0,
    timerTTSRate      = 0,

    -- No-Lifebloom alert
    noLBEnabled       = false,
    noLBFrequency     = 5,
    noLBSoundChoice   = 1,
    noLBTTSText       = "Lifebloom",
    noLBTTSVoice      = 0,
    noLBTTSRate       = 0,

    -- Volume
    ttsVolume         = 100,
    soundChannel      = "Master",

    -- Timer text alert
    timerTextEnabled  = false,
    timerTextMsg      = "Lifebloom",
    timerTextX        = 0,
    timerTextY        = 0,
    timerTextScale    = 1.0,
    timerTextR        = 1.0,
    timerTextG        = 0.8,
    timerTextB        = 0.0,
    timerTextA        = 1.0,
    timerTextFlash    = true,
    timerTextFont     = "Fonts\\FRIZQT__.TTF",
    timerTextOutline  = 2,

    -- No-LB text alert
    noLBTextEnabled   = false,
    noLBTextMsg       = "Lifebloom Missing",
    noLBTextX         = 0,
    noLBTextY         = -50,
    noLBTextScale     = 1.0,
    noLBTextR         = 1.0,
    noLBTextG         = 0.2,
    noLBTextB         = 0.2,
    noLBTextA         = 1.0,
    noLBTextFlash     = true,
    noLBTextFont      = "Fonts\\FRIZQT__.TTF",
    noLBTextOutline   = 2,

    -- Cursor icon
    cursorEnabled     = false,
    cursorScale       = 1.0,
    cursorOffsetX     = 20,
    cursorOffsetY     = -20,
    cursorTextR       = 1.0,
    cursorTextG       = 1.0,
    cursorTextB       = 1.0,
    cursorTextSize    = 14,
}

-------------------------------------------------------------------------------
-- 2. SAVED VARIABLES & SPEC CHECK
-------------------------------------------------------------------------------

local db

local function IsRestorationDruid()
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return false end
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == 105
end

local function IsActiveInCurrentContent()
    if IsInRaid() then
        return db.activeInRaids
    elseif IsInGroup() then
        return db.activeInDungeons
    else
        return db.activeInSolo
    end
end

local function IsInPvP()
    return C_PvP.IsActiveBattlefield() or C_PvP.IsArena()
end

-------------------------------------------------------------------------------
-- 3. SOUND HELPERS
-------------------------------------------------------------------------------

local function BuildFullSoundList()
    local list = {}
    for _, entry in ipairs(SOUND_LIST) do
        list[#list + 1] = { label = entry.label, value = entry.value }
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local lsmSounds = LSM:List("sound")
        if lsmSounds then
            for _, name in ipairs(lsmSounds) do
                list[#list + 1] = { label = name, value = "lsm:" .. name }
            end
        end
    end
    return list
end

local function GetSoundEntry(index)
    local list = BuildFullSoundList()
    return list[index] or list[1]
end

local function SpeakTTS(text, voice, rate)
    text = (text and text ~= "") and text or "Lifebloom"
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return end

    local voices = C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() or {}
    local validVoice = voices[1] and voices[1].voiceID or 0
    for i = 1, #voices do
        if voices[i].voiceID == voice then
            validVoice = voice
            break
        end
    end

    local vol  = db.ttsVolume or 100
    local rate = rate or C_TTSSettings.GetSpeechRate() or 0

    C_Timer.After(0.01, function()
        C_VoiceChat.SpeakText(validVoice, text, rate, vol, true)
    end)
end

local function PlayAlert(soundIndex, ttsText, ttsVoice, ttsRate)
    local entry = GetSoundEntry(soundIndex)
    if not entry then return end

    local channel = db.soundChannel or "SFX"

    if entry.value == "tts" then
        SpeakTTS(ttsText, ttsVoice, ttsRate)
    elseif type(entry.value) == "string" and entry.value:sub(1, 4) == "lsm:" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local path = LSM:Fetch("sound", entry.value:sub(5))
            if path then PlaySoundFile(path, channel) end
        end
    elseif type(entry.value) == "number" then
        PlaySound(entry.value, channel)
    end
end

-------------------------------------------------------------------------------
-- 4. FONT HELPERS
-------------------------------------------------------------------------------

local function BuildFontDropItems()
    local items = {}
    for _, f in ipairs(BUILTIN_FONTS) do
        items[#items + 1] = f.label
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local lsmFonts = LSM:List("font")
        if lsmFonts then
            for _, name in ipairs(lsmFonts) do
                items[#items + 1] = name
            end
        end
    end
    return items
end

local function GetFontPath(index)
    if index <= #BUILTIN_FONTS then
        return BUILTIN_FONTS[index].path
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local lsmFonts = LSM:List("font")
        local lsmIndex = index - #BUILTIN_FONTS
        if lsmFonts and lsmFonts[lsmIndex] then
            return LSM:Fetch("font", lsmFonts[lsmIndex])
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetFontIndexFromPath(path)
    for i, f in ipairs(BUILTIN_FONTS) do
        if f.path == path then return i end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local lsmFonts = LSM:List("font")
        if lsmFonts then
            for i, name in ipairs(lsmFonts) do
                if LSM:Fetch("font", name) == path then
                    return #BUILTIN_FONTS + i
                end
            end
        end
    end
    return 1
end

-------------------------------------------------------------------------------
-- 5. TEXT ALERT FRAMES
-------------------------------------------------------------------------------

local timerTextFrame
local noLBTextFrame
local TEXT_FONT   = "Fonts\\FRIZQT__.TTF"
local TEXT_SIZE   = 24
local FLASH_SPEED = 2.5

local function CreateTextAlertFrame(name)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(300, 60)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(TEXT_FONT, TEXT_SIZE, "OUTLINE")
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    f.text = fs

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(1)
    anim:SetToAlpha(0.2)
    anim:SetDuration(1 / FLASH_SPEED)
    anim:SetSmoothing("IN_OUT")
    f.flashAnim = ag

    f:Hide()
    return f
end

local function ApplyTextFrameSettings(f, enabled, x, y, scale, r, g, b, a, flash, msg, font, outline)
    font = font or TEXT_FONT
    local outlineFlag = OUTLINE_FLAGS[outline or 2]
    f.text:SetText(msg)
    f.text:SetTextColor(r, g, b, a or 1)
    local fontSize = TEXT_SIZE * scale
    f.text:SetFont(font, fontSize, outlineFlag)
    f:SetSize(400 * scale, 80 * scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    f:SetScale(1)
    if flash then
        f.flashAnim:Play()
    else
        f.flashAnim:Stop()
        f:SetAlpha(1)
    end
end

local function ShowTimerTextAlert()
    if not db.timerTextEnabled then return end
    ApplyTextFrameSettings(
        timerTextFrame, db.timerTextEnabled,
        db.timerTextX, db.timerTextY,
        db.timerTextScale,
        db.timerTextR, db.timerTextG, db.timerTextB,
        db.timerTextA or 1,
        db.timerTextFlash, db.timerTextMsg or "Lifebloom",
        db.timerTextFont, db.timerTextOutline)
    timerTextFrame:Show()
end

local function HideTimerTextAlert()
    timerTextFrame.flashAnim:Stop()
    timerTextFrame:Hide()
end

local function ShowNoLBTextAlert()
    if not db.noLBTextEnabled then return end
    ApplyTextFrameSettings(
        noLBTextFrame, db.noLBTextEnabled,
        db.noLBTextX, db.noLBTextY,
        db.noLBTextScale,
        db.noLBTextR, db.noLBTextG, db.noLBTextB,
        db.noLBTextA or 1,
        db.noLBTextFlash, db.noLBTextMsg or "Lifebloom Missing",
        db.noLBTextFont, db.noLBTextOutline)
    noLBTextFrame:Show()
end

local function HideNoLBTextAlert()
    noLBTextFrame.flashAnim:Stop()
    noLBTextFrame:Hide()
end

local function SetTextFrameMovable(f, enabled)
    f:SetMovable(enabled)
    f:EnableMouse(enabled)
    if enabled then
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx = UIParent:GetWidth()  / 2
            local cy = UIParent:GetHeight() / 2
            local fx = self:GetLeft() + self:GetWidth()  / 2 - cx
            local fy = self:GetTop()  - self:GetHeight() / 2 - cy
            if f == timerTextFrame then
                db.timerTextX = fx
                db.timerTextY = fy
            else
                db.noLBTextX = fx
                db.noLBTextY = fy
            end
        end)
        f:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    else
        f:SetScript("OnDragStart", nil)
        f:SetScript("OnDragStop",  nil)
        f:SetBackdrop(nil)
    end
end

-------------------------------------------------------------------------------
-- 6. CURSOR ICON
-------------------------------------------------------------------------------

local cursorFrame
local cursorTesting = false

local function CreateCursorFrame()
    local f = CreateFrame("Frame", "LBACursorFrame", UIParent)
    f:SetSize(40, 40)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(false)

    local icon = f:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture(LIFEBLOOM_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    local timer = f:CreateFontString(nil, "OVERLAY")
    timer:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    timer:SetPoint("CENTER", f, "CENTER", 0, 0)
    timer:SetJustifyH("CENTER")
    timer:SetText("")
    f.timer = timer

    f:Hide()
    return f
end

local function UpdateCursorFrame()
    if not cursorFrame then return end

    local scale    = db.cursorScale or 1.0
    local size     = 40 * scale
    local offsetX  = db.cursorOffsetX or 20
    local offsetY  = db.cursorOffsetY or -20
    local fontSize = db.cursorTextSize or 14

    cursorFrame:SetSize(size, size)
    cursorFrame.timer:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    cursorFrame.timer:SetTextColor(
        db.cursorTextR or 1,
        db.cursorTextG or 1,
        db.cursorTextB or 1,
        1)

    cursorFrame:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            x / uiScale + offsetX,
            y / uiScale + offsetY)
    end)
end

local function ShowCursorFrame(remaining)
    if not db.cursorEnabled and not cursorTesting then return end
    UpdateCursorFrame()
    if remaining then
        cursorFrame.timer:SetText(string.format("%.1f", remaining))
    else
        cursorFrame.timer:SetText("")
    end
    cursorFrame:Show()
end

local function HideCursorFrame()
    if cursorFrame then
        cursorFrame:Hide()
        cursorFrame:SetScript("OnUpdate", nil)
    end
end

-------------------------------------------------------------------------------
-- 7. CORE LOGIC
-------------------------------------------------------------------------------

local coreFrame = CreateFrame("Frame")
local lastAlerts       = {}
local lastNoLBAlert    = 0
local timerTextShowing = false
local noLBTextShowing  = false

local function CheckUnit(unit)
    local aura = C_UnitAuras.GetAuraDataBySpellName(unit, LIFEBLOOM_NAME, "HELPFUL|PLAYER")
    if aura and aura.expirationTime then
        local remaining = aura.expirationTime - GetTime()
        local guid = UnitGUID(unit)
        local threshold = db.timerUsePandemic and 4.5 or (db.timerCustomSecs or 4.5)

        if db.timerEnabled then
            if remaining <= (threshold + 0.3) and remaining >= (threshold - 0.3) then
                if not lastAlerts[guid] or (GetTime() - lastAlerts[guid] > 8) then
                    PlayAlert(db.timerSoundChoice, db.timerTTSText, db.timerTTSVoice, db.timerTTSRate)
                    lastAlerts[guid] = GetTime()
                end
            elseif remaining > (threshold + 0.5) or remaining <= 0 then
                lastAlerts[guid] = nil
            end
        end

        if db.timerTextEnabled then
            if remaining <= threshold then
                if not timerTextShowing then
                    timerTextShowing = true
                    ShowTimerTextAlert()
                end
            else
                if timerTextShowing then
                    timerTextShowing = false
                    HideTimerTextAlert()
                end
            end
        end

        return true, remaining
    end
    return false, nil
end

local function ScanForLifebloom()
    local found        = false
    local minRemaining = nil

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unitFound, rem = CheckUnit("raid" .. i)
            if unitFound then
                found = true
                if rem and (not minRemaining or rem < minRemaining) then
                    minRemaining = rem
                end
            end
        end
    elseif IsInGroup() then
        local unitFound, rem = CheckUnit("player")
        if unitFound then
            found = true
            if rem and (not minRemaining or rem < minRemaining) then
                minRemaining = rem
            end
        end
        for i = 1, GetNumGroupMembers() do
            unitFound, rem = CheckUnit("party" .. i)
            if unitFound then
                found = true
                if rem and (not minRemaining or rem < minRemaining) then
                    minRemaining = rem
                end
            end
        end
    else
        local unitFound, rem = CheckUnit("player")
        if unitFound then
            found = true
            minRemaining = rem
        end
    end

    if not found and timerTextShowing then
        timerTextShowing = false
        HideTimerTextAlert()
    end

    local inCombat = UnitAffectingCombat("player")

    -- sound alert
    if db.noLBEnabled and not found and inCombat then
        local now  = GetTime()
        local freq = db.noLBFrequency or 5
        if now - lastNoLBAlert >= freq then
            PlayAlert(db.noLBSoundChoice, db.noLBTTSText, db.noLBTTSVoice, db.noLBTTSRate)
            lastNoLBAlert = now
        end
    elseif found then
        lastNoLBAlert = 0
    end

    -- no-LB text alert
    if db.noLBTextEnabled and not found and inCombat then
        if not noLBTextShowing then
            noLBTextShowing = true
            ShowNoLBTextAlert()
        end
    else
        if noLBTextShowing then
            noLBTextShowing = false
            HideNoLBTextAlert()
        end
    end

    -- cursor icon logic
    if cursorTesting then
        -- test mode: scan loop does not touch cursor
    elseif db.cursorEnabled then
        local threshold = db.timerUsePandemic and 4.5 or (db.timerCustomSecs or 4.5)
        if not found and inCombat then
            ShowCursorFrame(nil)
        elseif found and minRemaining and minRemaining <= threshold then
            ShowCursorFrame(minRemaining)
        else
            HideCursorFrame()
        end
    else
        HideCursorFrame()
    end
end

coreFrame:SetScript("OnUpdate", function(self, elapsed)
    if not db then return end
    if not IsRestorationDruid() then return end
    if not IsActiveInCurrentContent() then return end
	if not db.activeInPvP and IsInPvP() then return end
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.1 then return end
    self.timer = 0
    ScanForLifebloom()
end)

-------------------------------------------------------------------------------
-- 8. OPTIONS PANEL
-------------------------------------------------------------------------------

local optionsPanel
local scrollDropdown = nil
local timerTTSEditBox
local noLBTTSEditBox

local function GetOrCreateScrollDropdown()
    if scrollDropdown then return scrollDropdown end

    local popup = CreateFrame("Frame", "LBAScrollDropdown", UIParent, "BackdropTemplate")
    popup:SetSize(260, 230)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(220, 10)
    scrollFrame:SetScrollChild(content)

    popup.scrollFrame = scrollFrame
    popup.content     = content
    popup.buttons     = {}

    local closeOnClick = CreateFrame("Frame", nil, UIParent)
    closeOnClick:SetAllPoints()
    closeOnClick:SetFrameStrata("DIALOG")
    closeOnClick:EnableMouse(true)
    closeOnClick:Hide()
    closeOnClick:SetScript("OnMouseDown", function()
        popup:Hide()
        closeOnClick:Hide()
    end)
    popup.closeOnClick = closeOnClick

    scrollDropdown = popup
    return popup
end

local function ShowScrollDropdown(anchorFrame, itemsFunc, getIndex, setIndex)
    local popup   = GetOrCreateScrollDropdown()
    local content = popup.content

    for _, btn in ipairs(popup.buttons) do
        btn:Hide()
        btn:ClearAllPoints()
    end

    local items  = type(itemsFunc) == "function" and itemsFunc() or itemsFunc
    local btnH   = 20
    local totalH = #items * btnH
    content:SetSize(220, totalH)

    for i, label in ipairs(items) do
        local btn = popup.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, content)
            btn:SetHeight(btnH)
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:SetHighlightFontObject("GameFontHighlightSmall")
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            btn:RegisterForClicks("AnyUp")
            popup.buttons[i] = btn
        end

        btn:SetText(label)
        btn:SetWidth(content:GetWidth())
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 0, -(i - 1) * btnH)
        btn:Show()

        local idx = i
        btn:SetScript("OnClick", function()
            setIndex(idx)
            popup:Hide()
            popup.closeOnClick:Hide()
        end)

        if i == getIndex() then
            btn:GetNormalFontObject():SetTextColor(1, 0.82, 0)
        else
            btn:GetNormalFontObject():SetTextColor(1, 1, 1)
        end
    end

    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    popup:Show()
    popup.closeOnClick:Show()
end

local function CreateScrollDropdown(parent, label, x, y, itemsFunc, getIndex, setIndex, previewFunc)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(220, 22)
    btn:SetPoint("TOPLEFT", x, y - 22)

    local function RefreshText()
        local items = type(itemsFunc) == "function" and itemsFunc() or itemsFunc
        local idx   = getIndex()
        local text  = items[idx] or "Select..."
        if #text > 20 then text = text:sub(1, 20) .. "..." end
        btn:SetText(text .. " ▼")
    end
    RefreshText()

    btn:SetScript("OnClick", function(self)
        ShowScrollDropdown(self, itemsFunc, getIndex, function(idx)
            setIndex(idx)
            RefreshText()
        end)
    end)

    if previewFunc then
        local pbtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        pbtn:SetSize(70, 22)
        pbtn:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        pbtn:SetText("Preview")
        pbtn:SetScript("OnClick", function()
            previewFunc(getIndex())
        end)
    end

    return lbl, btn
end

local function BuildSoundDropItems()
    local items = {}
    for _, entry in ipairs(SOUND_LIST) do
        if entry.value == "tts" then
            items[#items + 1] = entry.label
        else
            items[#items + 1] = "Blizzard: " .. entry.label
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local lsmSounds = LSM:List("sound")
        if lsmSounds then
            for _, name in ipairs(lsmSounds) do
                items[#items + 1] = name
            end
        end
    end
    return items
end

local function BuildVoiceDropItems()
    local items = {}
    for i, v in ipairs(TTS_VOICE_LIST) do
        items[i] = v.name or ("Voice " .. i)
    end
    if #items == 0 then items[1] = "Default" end
    return items
end

local function CreateCheckbox(parent, label, x, y, getVal, setVal)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text:SetText(label)
    cb:SetChecked(getVal())
    cb:SetScript("OnClick", function(self)
        setVal(self:GetChecked())
    end)
    return cb
end

local function CreateEditBox(parent, label, x, y, width, getVal, setVal)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)

    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", x, y - 20)
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); setVal(self:GetText()) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) setVal(self:GetText()) end)
    eb:SetText(tostring(getVal()))
    return lbl, eb
end

local function CreateSlider(parent, label, x, y, minVal, maxVal, step, getVal, setVal)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label .. ": " .. tostring(getVal()))

    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", x, y - 22)
    sl:SetSize(220, 16)
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetValue(getVal())
    sl.Low:SetText(tostring(minVal))
    sl.High:SetText(tostring(maxVal))
    sl.Text:SetText("")

    sl:SetScript("OnValueChanged", function(self, val)
        local rounded = math.floor(val / step + 0.5) * step
        setVal(rounded)
        lbl:SetText(label .. ": " .. tostring(rounded))
    end)

    return lbl, sl
end

local function CreateColorPicker(parent, label, x, y, getR, getG, getB, getA, onChange)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)

    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(24, 24)
    swatch:SetPoint("TOPLEFT", x + 160, y - 4)
    swatch:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    swatch:SetBackdropColor(getR(), getG(), getB(), getA and getA() or 1)
    swatch:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    swatch:SetScript("OnClick", function()
        local function swatchFunc()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            onChange(r, g, b, a)
            swatch:SetBackdropColor(r, g, b, a)
        end
        local function cancelFunc(prev)
            onChange(prev.r, prev.g, prev.b, prev.opacity)
            swatch:SetBackdropColor(prev.r, prev.g, prev.b, prev.opacity)
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r          = getR(),
            g          = getG(),
            b          = getB(),
            opacity    = getA and getA() or 1,
            hasOpacity = getA ~= nil,
            swatchFunc = swatchFunc,
            cancelFunc = cancelFunc,
        })
    end)

    return lbl, swatch
end

local function BuildTextAlertSection(content, yOff, prefix, titleText, defaultMsg)
    local sec = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sec:SetPoint("TOPLEFT", 10, yOff)
    sec:SetText(titleText)
    yOff = yOff - 25

    local f = prefix == "timer" and timerTextFrame or noLBTextFrame
    local unlocked = false

    local function RefreshLivePreview()
        if not unlocked then return end
        ApplyTextFrameSettings(f, true,
            db[prefix .. "TextX"], db[prefix .. "TextY"],
            db[prefix .. "TextScale"],
            db[prefix .. "TextR"], db[prefix .. "TextG"], db[prefix .. "TextB"],
            db[prefix .. "TextA"],
            db[prefix .. "TextFlash"], db[prefix .. "TextMsg"] or defaultMsg,
            db[prefix .. "TextFont"], db[prefix .. "TextOutline"])
    end

    CreateCheckbox(content, "Enable text alert", 10, yOff,
        function() return db[prefix .. "TextEnabled"] end,
        function(v) db[prefix .. "TextEnabled"] = v end)
    yOff = yOff - 30

    local msgLabel
    local _, msgEB = CreateEditBox(content, "Alert Text (press Enter to save):", 10, yOff, 300,
        function() return db[prefix .. "TextMsg"] or defaultMsg end,
        function(v)
            v = (v and v ~= "") and v or defaultMsg
            db[prefix .. "TextMsg"] = v
            msgLabel:SetText("Current: " .. v)
            RefreshLivePreview()
        end)
    msgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgLabel:SetPoint("TOPLEFT", 10, yOff - 44)
    msgLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    msgLabel:SetText("Current: " .. (db[prefix .. "TextMsg"] or defaultMsg))
    yOff = yOff - 64

    CreateCheckbox(content, "Flash text", 10, yOff,
        function() return db[prefix .. "TextFlash"] end,
        function(v) db[prefix .. "TextFlash"] = v; RefreshLivePreview() end)
    yOff = yOff - 30

    CreateSlider(content, "Text Scale", 10, yOff, 0.5, 3.0, 0.1,
        function() return db[prefix .. "TextScale"] end,
        function(v) db[prefix .. "TextScale"] = v; RefreshLivePreview() end)
    yOff = yOff - 45

    CreateColorPicker(content, "Text Color", 10, yOff,
        function() return db[prefix .. "TextR"] end,
        function() return db[prefix .. "TextG"] end,
        function() return db[prefix .. "TextB"] end,
        function() return db[prefix .. "TextA"] or 1 end,
        function(r, g, b, a)
            db[prefix .. "TextR"] = r
            db[prefix .. "TextG"] = g
            db[prefix .. "TextB"] = b
            db[prefix .. "TextA"] = a
            RefreshLivePreview()
        end)
    yOff = yOff - 35

    CreateScrollDropdown(content, "Font:", 10, yOff, BuildFontDropItems,
        function() return GetFontIndexFromPath(db[prefix .. "TextFont"] or TEXT_FONT) end,
        function(v)
            db[prefix .. "TextFont"] = GetFontPath(v)
            RefreshLivePreview()
        end)
    yOff = yOff - 52

    CreateScrollDropdown(content, "Outline:", 10, yOff, OUTLINE_LIST,
        function() return db[prefix .. "TextOutline"] or 2 end,
        function(v)
            db[prefix .. "TextOutline"] = v
            RefreshLivePreview()
        end)
    yOff = yOff - 52

    local testBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 22)
    testBtn:SetPoint("TOPLEFT", 10, yOff)
    testBtn:SetText("Test Alert")
    testBtn:SetScript("OnClick", function()
        ApplyTextFrameSettings(f, true,
            db[prefix .. "TextX"], db[prefix .. "TextY"],
            db[prefix .. "TextScale"],
            db[prefix .. "TextR"], db[prefix .. "TextG"], db[prefix .. "TextB"],
            db[prefix .. "TextA"],
            db[prefix .. "TextFlash"], db[prefix .. "TextMsg"] or defaultMsg,
            db[prefix .. "TextFont"], db[prefix .. "TextOutline"])
        f:Show()
        C_Timer.After(3, function()
            if not (prefix == "timer" and timerTextShowing) and
               not (prefix == "noLB" and noLBTextShowing) then
                f.flashAnim:Stop()
                f:Hide()
            end
        end)
    end)

    local unlockBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    unlockBtn:SetSize(150, 22)
    unlockBtn:SetPoint("LEFT", testBtn, "RIGHT", 6, 0)
    unlockBtn:SetText("Unlock & Move Text")
    unlockBtn:SetScript("OnClick", function(self)
        unlocked = not unlocked
        if unlocked then
            ApplyTextFrameSettings(f, true,
                db[prefix .. "TextX"], db[prefix .. "TextY"],
                db[prefix .. "TextScale"],
                db[prefix .. "TextR"], db[prefix .. "TextG"], db[prefix .. "TextB"],
                db[prefix .. "TextA"],
                db[prefix .. "TextFlash"], db[prefix .. "TextMsg"] or defaultMsg,
                db[prefix .. "TextFont"], db[prefix .. "TextOutline"])
            f:Show()
            SetTextFrameMovable(f, true)
            self:SetText("Click to Lock")
        else
            SetTextFrameMovable(f, false)
            f:Hide()
            self:SetText("Unlock & Move Text")
        end
    end)
    yOff = yOff - 35

    return yOff
end

local function BuildCursorSection(content, yOff)
    local sec = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sec:SetPoint("TOPLEFT", 10, yOff)
    sec:SetText("Cursor Reminder Icon")
    yOff = yOff - 25

    CreateCheckbox(content, "Enable cursor icon", 10, yOff,
        function() return db.cursorEnabled end,
        function(v)
            db.cursorEnabled = v
            if not v and not cursorTesting then HideCursorFrame() end
        end)
    yOff = yOff - 30

    CreateSlider(content, "Icon Scale", 10, yOff, 0.5, 3.0, 0.1,
        function() return db.cursorScale or 1.0 end,
        function(v)
            db.cursorScale = v
            if cursorFrame and cursorFrame:IsShown() then UpdateCursorFrame() end
        end)
    yOff = yOff - 45

    CreateSlider(content, "X Offset", 10, yOff, -100, 100, 1,
        function() return db.cursorOffsetX or 20 end,
        function(v)
            db.cursorOffsetX = v
            if cursorFrame and cursorFrame:IsShown() then UpdateCursorFrame() end
        end)
    yOff = yOff - 45

    CreateSlider(content, "Y Offset", 10, yOff, -100, 100, 1,
        function() return db.cursorOffsetY or -20 end,
        function(v)
            db.cursorOffsetY = v
            if cursorFrame and cursorFrame:IsShown() then UpdateCursorFrame() end
        end)
    yOff = yOff - 45

    CreateSlider(content, "Timer Text Size", 10, yOff, 8, 32, 1,
        function() return db.cursorTextSize or 14 end,
        function(v)
            db.cursorTextSize = v
            if cursorFrame and cursorFrame:IsShown() then UpdateCursorFrame() end
        end)
    yOff = yOff - 45

    CreateColorPicker(content, "Timer Text Color", 10, yOff,
        function() return db.cursorTextR or 1 end,
        function() return db.cursorTextG or 1 end,
        function() return db.cursorTextB or 1 end,
        nil,
        function(r, g, b)
            db.cursorTextR = r
            db.cursorTextG = g
            db.cursorTextB = b
            if cursorFrame and cursorFrame:IsShown() then UpdateCursorFrame() end
        end)
    yOff = yOff - 35

    local testBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 22)
    testBtn:SetPoint("TOPLEFT", 10, yOff)
    testBtn:SetText("Test Icon")
    testBtn:SetScript("OnClick", function(self)
        cursorTesting = not cursorTesting
        if cursorTesting then
            ShowCursorFrame(3.7)
            self:SetText("Hide Icon")
        else
            HideCursorFrame()
            self:SetText("Test Icon")
        end
    end)
    yOff = yOff - 35

    return yOff
end

local function RefreshEditBoxes()
    if timerTTSEditBox then timerTTSEditBox:SetText(db.timerTTSText or "") end
    if noLBTTSEditBox  then noLBTTSEditBox:SetText(db.noLBTTSText  or "") end
end

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = ADDON_NAME

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(550, 800)
    scrollFrame:SetScrollChild(content)

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("|cFF00FF96Lifebloom Alert|r  Options")

    local yOff = -45

    -- active in section
    local secActive = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    secActive:SetPoint("TOPLEFT", 10, yOff)
    secActive:SetText("Active In")
    yOff = yOff - 25

    CreateCheckbox(content, "Solo", 10, yOff,
        function() return db.activeInSolo end,
        function(v) db.activeInSolo = v end)
    yOff = yOff - 25

    CreateCheckbox(content, "Dungeons", 10, yOff,
        function() return db.activeInDungeons end,
        function(v) db.activeInDungeons = v end)
    yOff = yOff - 25

    CreateCheckbox(content, "Raids", 10, yOff,
        function() return db.activeInRaids end,
        function(v) db.activeInRaids = v end)
    yOff = yOff - 25
	
	CreateCheckbox(content, "PvP (Battlegrounds & Arena)", 10, yOff,
        function() return db.activeInPvP end,
        function(v) db.activeInPvP = v end)
    yOff = yOff - 35

    local sep_active = content:CreateTexture(nil, "OVERLAY")
    sep_active:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep_active:SetSize(530, 1)
    sep_active:SetPoint("TOPLEFT", 10, yOff)
    yOff = yOff - 15

    -- timer sound alert
    local secTimer = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    secTimer:SetPoint("TOPLEFT", 10, yOff)
    secTimer:SetText("Refresh Timer Alert")
    yOff = yOff - 25

    CreateCheckbox(content, "Enable refresh timer alert", 10, yOff,
        function() return db.timerEnabled end,
        function(v) db.timerEnabled = v end)
    yOff = yOff - 30

    local cbPandemic = CreateCheckbox(content, "Use Pandemic threshold (4.5 sec)", 30, yOff,
        function() return db.timerUsePandemic end,
        function(v) db.timerUsePandemic = v end)
    yOff = yOff - 28

    local cbCustomThresh = CreateCheckbox(content, "Use custom threshold", 30, yOff,
        function() return not db.timerUsePandemic end,
        function(v) db.timerUsePandemic = not v end)
    yOff = yOff - 28

    cbPandemic:SetScript("OnClick", function(self)
        db.timerUsePandemic = self:GetChecked()
        cbCustomThresh:SetChecked(not db.timerUsePandemic)
    end)
    cbCustomThresh:SetScript("OnClick", function(self)
        db.timerUsePandemic = not self:GetChecked()
        cbPandemic:SetChecked(db.timerUsePandemic)
    end)

    local _, threshEB = CreateEditBox(content, "Custom threshold (seconds):", 50, yOff, 80,
        function() return db.timerCustomSecs end,
        function(v)
            local n = tonumber(v)
            if n and n > 0 then
                db.timerCustomSecs = n
                threshLabel:SetText("Current: " .. n .. "s")
            end
        end)
    local threshLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    threshLabel:SetPoint("TOPLEFT", 50, yOff - 44)
    threshLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    threshLabel:SetText("Current: " .. (db.timerCustomSecs or 4.5) .. "s")
    yOff = yOff - 64

    CreateScrollDropdown(content, "Timer Alert Sound:", 10, yOff, BuildSoundDropItems,
        function() return db.timerSoundChoice end,
        function(v) db.timerSoundChoice = v end,
        function(i)
            local entry = GetSoundEntry(i)
            if entry.value == "tts" then
                SpeakTTS(db.timerTTSText, db.timerTTSVoice, db.timerTTSRate)
            elseif type(entry.value) == "string" and entry.value:sub(1,4) == "lsm:" then
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                if LSM then
                    local path = LSM:Fetch("sound", entry.value:sub(5))
                    if path then PlaySoundFile(path, db.soundChannel or "SFX") end
                end
            elseif type(entry.value) == "number" then
                PlaySound(entry.value, db.soundChannel or "SFX")
            end
        end)
    local channelNote4 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelNote4:SetPoint("TOPLEFT", 10, yOff - 58)
    channelNote4:SetTextColor(1, 0.2, 0.2, 1)
    channelNote4:SetText("Volume adjustment only works for non Blizzard sounds and TTS.")
    yOff = yOff - 78

    local timerTTSLabel
    _, timerTTSEditBox = CreateEditBox(content, "TTS Text (press Enter to save):", 10, yOff, 300,
        function() return db.timerTTSText end,
        function(v) db.timerTTSText = v; timerTTSLabel:SetText("Current: " .. v) end)
    timerTTSLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerTTSLabel:SetPoint("TOPLEFT", 10, yOff - 44)
    timerTTSLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    timerTTSLabel:SetText("Current: " .. (db.timerTTSText or "Lifebloom"))
    yOff = yOff - 64

    -- timer text alert
    local sep0 = content:CreateTexture(nil, "OVERLAY")
    sep0:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep0:SetSize(530, 1)
    sep0:SetPoint("TOPLEFT", 10, yOff)
    yOff = yOff - 15

    yOff = BuildTextAlertSection(content, yOff, "timer", "Refresh Timer Text Alert", "Lifebloom")

    -- no lifebloom sound alert
    local sep1 = content:CreateTexture(nil, "OVERLAY")
    sep1:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep1:SetSize(530, 1)
    sep1:SetPoint("TOPLEFT", 10, yOff)
    yOff = yOff - 15

    local secNoLB = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    secNoLB:SetPoint("TOPLEFT", 10, yOff)
    secNoLB:SetText("No Lifebloom Alert  |cFFFF6060(in combat only)|r")
    yOff = yOff - 25

    CreateCheckbox(content, "Enable No-LB sound alert", 10, yOff,
        function() return db.noLBEnabled end,
        function(v) db.noLBEnabled = v end)
    yOff = yOff - 30

    CreateSlider(content, "Alert frequency (sec)", 10, yOff, 1, 30, 1,
        function() return db.noLBFrequency end,
        function(v) db.noLBFrequency = v end)
    yOff = yOff - 55

    CreateScrollDropdown(content, "No-LB Alert Sound:", 10, yOff, BuildSoundDropItems,
        function() return db.noLBSoundChoice end,
        function(v) db.noLBSoundChoice = v end,
        function(i)
            local entry = GetSoundEntry(i)
            if entry.value == "tts" then
                SpeakTTS(db.noLBTTSText, db.noLBTTSVoice, db.noLBTTSRate)
            elseif type(entry.value) == "string" and entry.value:sub(1,4) == "lsm:" then
                local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                if LSM then
                    local path = LSM:Fetch("sound", entry.value:sub(5))
                    if path then PlaySoundFile(path, db.soundChannel or "SFX") end
                end
            elseif type(entry.value) == "number" then
                PlaySound(entry.value, db.soundChannel or "SFX")
            end
        end)
    local channelNote3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelNote3:SetPoint("TOPLEFT", 10, yOff - 58)
    channelNote3:SetTextColor(1, 0.2, 0.2, 1)
    channelNote3:SetText("Volume adjustment only works for non Blizzard sounds and TTS.")
    yOff = yOff - 78

    local noLBTTSLabel
    _, noLBTTSEditBox = CreateEditBox(content, "TTS Text (press Enter to save):", 10, yOff, 300,
        function() return db.noLBTTSText end,
        function(v) db.noLBTTSText = v; noLBTTSLabel:SetText("Current: " .. v) end)
    noLBTTSLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noLBTTSLabel:SetPoint("TOPLEFT", 10, yOff - 44)
    noLBTTSLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    noLBTTSLabel:SetText("Current: " .. (db.noLBTTSText or "Lifebloom"))
    yOff = yOff - 64

    -- no lifebloom text alert
    local sep1b = content:CreateTexture(nil, "OVERLAY")
    sep1b:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep1b:SetSize(530, 1)
    sep1b:SetPoint("TOPLEFT", 10, yOff)
    yOff = yOff - 15

    yOff = BuildTextAlertSection(content, yOff, "noLB", "No Lifebloom Text Alert", "Lifebloom Missing")

    -- cursor icon
    local sep3 = content:CreateTexture(nil, "OVERLAY")
    sep3:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep3:SetSize(530, 1)
    sep3:SetPoint("TOPLEFT", 10, yOff)
    yOff = yOff - 15

    yOff = BuildCursorSection(content, yOff)

    -- volume and tts settings
    local sep2 = content:CreateTexture(nil, "OVERLAY")
    sep2:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    sep2:SetSize(530, 1)
    sep2:SetPoint("TOPLEFT", 10, yOff)
    yOff = yOff - 15

    local secShared = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    secShared:SetPoint("TOPLEFT", 10, yOff)
    secShared:SetText("Volume & TTS Settings")
    yOff = yOff - 25

    CreateScrollDropdown(content, "Alert Sound Channel:", 10, yOff, SOUND_CHANNEL_LIST,
        function()
            local ch = db.soundChannel or "SFX"
            for i, v in ipairs(SOUND_CHANNEL_LIST) do
                if v == ch then return i end
            end
            return 2
        end,
        function(v)
            db.soundChannel = SOUND_CHANNEL_LIST[v]
        end)
    local channelNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelNote:SetPoint("TOPLEFT", 10, yOff - 44)
    channelNote:SetTextColor(0.7, 0.7, 0.7, 1)
    channelNote:SetText("Applies to NON-TTS sounds only. Adjust volume slide that you chose in WoW Sound Settings.")
    local channelNote2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelNote2:SetPoint("TOPLEFT", 10, yOff - 58)
    channelNote2:SetTextColor(1, 0.2, 0.2, 1)
    channelNote2:SetText("Volume adjustment only works for non Blizzard sounds.")
    yOff = yOff - 78

    CreateSlider(content, "TTS Volume", 10, yOff, 0, 100, 5,
        function() return db.ttsVolume or 100 end,
        function(v) db.ttsVolume = v end)
    yOff = yOff - 55

    CreateScrollDropdown(content, "TTS Voice (applies to both alerts):", 10, yOff, BuildVoiceDropItems,
        function()
            local voices = C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() or {}
            for i, v in ipairs(voices) do
                if v.voiceID == db.timerTTSVoice then return i end
            end
            return 1
        end,
        function(v)
            local voices = C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() or {}
            local voiceID = voices[v] and voices[v].voiceID or 0
            db.timerTTSVoice = voiceID
            db.noLBTTSVoice  = voiceID
        end)
    yOff = yOff - 52

    CreateSlider(content, "TTS Rate (applies to both alerts)", 10, yOff, -10, 10, 1,
        function() return db.timerTTSRate or 0 end,
        function(v)
            db.timerTTSRate = v
            db.noLBTTSRate  = v
        end)
    yOff = yOff - 55

    content:SetSize(550, math.abs(yOff) + 30)

    optionsPanel = panel
    return panel
end

-------------------------------------------------------------------------------
-- 9. INITIALISATION
-------------------------------------------------------------------------------

local category
local pendingOptionsOpen = false

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if pendingOptionsOpen then
        pendingOptionsOpen = false
        RefreshEditBoxes()
        if category then
            Settings.OpenToCategory(category.ID)
        else
            InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        end
    end
end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if type(LifebloomAlertDB) ~= "table" then
            LifebloomAlertDB = {}
        end
        for k, v in pairs(DEFAULTS) do
            if LifebloomAlertDB[k] == nil then
                LifebloomAlertDB[k] = v
            end
        end
        db = LifebloomAlertDB

    elseif event == "PLAYER_LOGIN" then
        if C_VoiceChat and C_VoiceChat.GetTtsVoices then
            TTS_VOICE_LIST = C_VoiceChat.GetTtsVoices() or {}
        end

        timerTextFrame = CreateTextAlertFrame("LBATimerTextFrame")
        noLBTextFrame  = CreateTextAlertFrame("LBANoLBTextFrame")
        cursorFrame    = CreateCursorFrame()

        local panel = BuildOptionsPanel()

        if Settings and Settings.RegisterCanvasLayoutCategory then
            category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
            Settings.RegisterAddOnCategory(category)
        else
            InterfaceOptions_AddCategory(panel)
        end

        SLASH_LIFEBLOOMALERT1 = "/lba"
        SlashCmdList["LIFEBLOOMALERT"] = function()
            if InCombatLockdown() then
                pendingOptionsOpen = true
                print("|cFF00FF96LifebloomAlert:|r Options will open when combat ends.")
                return
            end
            RefreshEditBoxes()
            if category then
                Settings.OpenToCategory(category.ID)
            else
                InterfaceOptionsFrame_OpenToCategory(optionsPanel)
            end
        end

        if not IsRestorationDruid() then
            print("|cFF00FF96LifebloomAlert:|r Loaded, but currently inactive (requires Restoration Druid).")
        else
            print("|cFF00FF96LifebloomAlert:|r Active. Type |cFFFFD100/lba|r to open options.")
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == "player" and IsRestorationDruid() then
            print("|cFF00FF96LifebloomAlert:|r Restoration spec detected — alerts active.")
        end
    end
end)