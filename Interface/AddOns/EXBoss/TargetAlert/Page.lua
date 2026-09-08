---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- TargetAlert/Page.lua
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end
local L                               = (ExBoss and ExBoss.L) or
setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY               = "ExBoss.TargetAlert"
local TARGET_IDENTITY_UNIT_CHANGED    = "ExBoss.TargetIdentity.UnitChanged"
local TARGET_IDENTITY_ROSTER_REVISION = "ExBoss.TargetIdentity.RosterRevision"

local ExwindFactory                   = _G.ExwindFactory
local LSM                             = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ------------------------------------------------------------
-- 本地变量
-- ------------------------------------------------------------
local activeBars                      = {}
local usedBarsList                    = {}
local previewBars                     = {}
local anchorFrame                     = nil
local editHandleFrame                 = nil
local anchorController                = nil
local isPreviewing                    = false
local TogglePreview
local UpdateCast
local RefreshAll
local ReLayout

local CreateFrame                = _G.CreateFrame
local UIParent                   = _G.UIParent
local WorldFrame                 = _G.WorldFrame
local UnitName                   = _G.UnitName
local UnitClass                  = _G.UnitClass
local C_ClassColor               = _G.C_ClassColor
local string                     = _G.string
local type                       = _G.type
local pairs                      = _G.pairs
local next                       = _G.next
local select                     = _G.select
local tonumber                   = _G.tonumber
local math                       = _G.math
local table                      = _G.table
local ipairs                     = _G.ipairs
local print                      = _G.print
local UnitExists                 = _G.UnitExists
local UnitAffectingCombat        = _G.UnitAffectingCombat
local UnitCastingInfo            = _G.UnitCastingInfo
local UnitChannelInfo            = _G.UnitChannelInfo
local UnitCastingDuration        = _G.UnitCastingDuration
local UnitChannelDuration        = _G.UnitChannelDuration
local GetTime                    = _G.GetTime
local UnitGUID                   = _G.UnitGUID
local UnitLevel                  = _G.UnitLevel
local C_Spell                    = _G.C_Spell
local IsMouseButtonDown          = _G.IsMouseButtonDown
local IsKeyDown                  = _G.IsKeyDown
local ResetCursor                = _G.ResetCursor
local SetCursor                  = _G.SetCursor
local GetMouseFocus              = _G.GetMouseFocus
local GetMouseFoci               = _G.GetMouseFoci
local GameTooltip                = _G.GameTooltip
local C_StringUtil               = _G.C_StringUtil
local C_Timer                    = _G.C_Timer
local PlaySoundFile              = _G.PlaySoundFile

local pendingCombatRechecks      = {}
local combatRecheckGeneration    = 0
local pendingTargetSoundDispatch = false

-- ------------------------------------------------------------
-- 1. Grid 布局定义
-- ------------------------------------------------------------
local EX_LAYOUT
local function EX_RegisterLayout()
    EX_LAYOUT = {
        { key = "header", type = "header", x = 1, y = 5, w = 200, h = 8, label = L["被点名提示 (TargetAlert)"], labelSize = 24 },
        { key = "enabled", type = "checkbox", x = 1, y = 16, w = 23, h = 8, label = L["启用"], labelSize = 18 },
        { key = "attachToCustom", type = "checkbox", x = 1, y = 27, w = 30, h = 8, label = L["自由依附"] },
        { key = "customAttachTarget", type = "input", x = 35, y = 27, w = 83, h = 8, label = L["目标路径"] },
        { key = "btn_pick_frame", type = "button", x = 126, y = 27, w = 53, h = 8, label = L["鼠标选取"] },
        { key = "locked", type = "checkbox", x = 35, y = 43, w = 38, h = 8, label = L["锁定位置"] },
        { key = "preview", type = "checkbox", x = 76, y = 43, w = 30, h = 8, label = L["预览模式"] },
        { key = "btn_reset_pos", type = "button", x = 126, y = 65, w = 53, h = 8, label = L["重置位置"] },
        { key = "posX", type = "slider", x = 1, y = 65, w = 57, h = 8, label = L["整体水平位置"], min = -1000, max = 1000 },
        { key = "posY", type = "slider", x = 61, y = 65, w = 57, h = 8, label = L["整体垂直位置"], min = -1000, max = 1000 },
        { key = "hideLevel92Casts", type = "checkbox", x = 1, y = 43, w = 26, h = 8, label = L["隐藏92级读条"] },
        { key = "hideLevel91Casts", type = "checkbox", x = 1, y = 50, w = 26, h = 8, label = L["隐藏91级读条"] },
        { key = "showSpellName", type = "checkbox", x = 35, y = 50, w = 38, h = 8, label = L["显示法术名称"] },
        { key = "enableForDps", type = "checkbox", x = 35, y = 16, w = 38, h = 8, label = L["|cffff120aDPS职责下开启|r"], labelSize = 17 },
        { key = "enableForHeal", type = "checkbox", x = 76, y = 16, w = 34, h = 8, label = L["|cff02ff0a治疗职责下开启|r"], labelSize = 17 },
        { key = "icon_header", type = "header", x = 1, y = 76, w = 200, h = 8, label = L["图标外观"], labelSize = 20 },
        { key = "iconModeSize", type = "slider", x = 1, y = 92, w = 57, h = 8, label = L["图标尺寸"], min = 20, max = 80 },
        { key = "iconSpacing", type = "slider", x = 1, y = 107, w = 57, h = 8, label = L["图标间距"], min = -40, max = 80 },
        { key = "spacing", type = "slider", x = 65, y = 107, w = 57, h = 8, label = L["垂直间距"], min = 0, max = 50 },
        { key = "iconStyle", type = "dropdown", x = 126, y = 107, w = 57, h = 8, label = L["图标样式"], items = { { L["图标+文字"], "图标+文字" }, { L["单图标"], "单图标" } } },
        { key = "growDirection", type = "dropdown", x = 126, y = 92, w = 57, h = 8, label = L["增长方向"], items = { { L["向下"], "向下" }, { L["向上"], "向上" }, { L["向右"], "向右" }, { L["向左"], "向左" }, { L["居中"], "居中" } } },
        { key = "maxBars", type = "slider", x = 65, y = 92, w = 57, h = 8, label = L["最大显示数量"], min = 1, max = 15 },
        { key = "voice_header", type = "header", x = 1, y = 122, w = 200, h = 8, label = L["语音设置"], labelSize = 20 },
        { key = "singleTargetSoundEnabled", type = "checkbox", x = 1, y = 137, w = 34, h = 8, label = L["启用单点音效"] },
        { key = "singleTargetLSM", type = "lsm_sound", x = 39, y = 137, w = 68, h = 8, label = L["单点名LSM音效"], search = true },
        { key = "btn_single_target_sound_test", type = "button", x = 114, y = 137, w = 19, h = 8, label = L["试听"] },
        { key = "multiTargetSoundEnabled", type = "checkbox", x = 1, y = 152, w = 34, h = 8, label = L["启用双点音效"] },
        { key = "multiTargetLSM", type = "lsm_sound", x = 39, y = 152, w = 68, h = 8, label = L["多点名LSM音效"], search = true },
        { key = "btn_multi_target_sound_test", type = "button", x = 114, y = 152, w = 19, h = 8, label = L["试听"] },
        { key = "targetDetectDelay", type = "slider", x = 141, y = 144, w = 57, h = 8, label = L["检测延迟(秒)"], min = 0, max = 1, step = 0.01 },
        { key = "font_timer", type = "fontgroup", x = 1, y = 167, w = 200, h = 50, label = L["时间文本设置"], labelSize = 20 },
        { key = "font_spell", type = "fontgroup", x = 1, y = 227, w = 200, h = 50, label = L["法术名称"], labelSize = 20 },
        { key = "iconSettings", type = "icongroup", x = 1, y = 288, w = 200, h = 50, label = L["图标设置(只在单图标生效)"] },
    }

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)
end
EX_RegisterLayout()

local EX_DEFAULTS = {
    enableForDps             = true,
    enableForHeal            = true,
    enabled                  = false,
    singleTargetSoundEnabled = true,
    multiTargetSoundEnabled  = true,
    showSpellName            = false,
    font_spell               = {
        a = 1,
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        size = 16,
        x = 0,
        y = 18,
    },
    font_timer               = {
        a = 1,
        b = 0,
        font = "默认",
        g = 0.68627452850342,
        outline = "THICKOUTLINE",
        r = 1,
        shadow = false,
        shadowX = 1.5,
        shadowY = -1.5,
        size = 28,
        x = 0,
        y = 0,
    },
    displayMode              = "icon",
    iconStyle                = "图标+文字",
    iconSettings             = { width = 36, height = 36, showBorder = false, borderTexture = "EX_WhiteBorder", borderSize = 1, borderPadding = 0, showIcon = true },
    iconModeSize             = 30,
    iconModeTimerSize        = 28,
    iconSpacing              = -23,
    growDirection            = "向上",
    hideLevel92Casts         = true,
    hideLevel91Casts         = true,
    locked                   = true,
    maxBars                  = 6,
    posX                     = 14,
    posY                     = 75,
    preview                  = false,
    singleTargetLSM          = "",
    multiTargetLSM           = "",
    targetDetectDelay        = 0.10,
    targetLSM                = "",
    showTimer                = true,
    spacing                  = 8,
    attachToCustom           = false,
    customAttachTarget       = "",
    timerOffsetX             = 0,
    timerOffsetY             = 0,
    timerGroup               = {
        barBgColor  = { a = 0.5, b = 0, g = 0, r = 0 },
        barBgColorA = 0.71539187431335,
        barBgColorB = 0.27843138575554,
        barBgColorG = 0.27843138575554,
        barBgColorR = 0.27843138575554,
        barColor    = { a = 1, b = 0, g = 0.7, r = 1 },
        barColorA   = 1,
        barColorB   = 1,
        barColorG   = 0.90980398654938,
        barColorR   = 0.29019609093666,
        height      = 28,
        iconOffsetX = 0,
        iconOffsetY = 0,
        iconSide    = "LEFT",
        iconSize    = 30,
        showIcon    = true,
        texture     = "EX_WhiteTexture",
        width       = 224,
    },
}

local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)

local function GetAnchorPointForDirection(dir)
    if dir == "向上" then
        return "BOTTOM"
    elseif dir == "向下" then
        return "TOP"
    elseif dir == "向右" then
        return "LEFT"
    elseif dir == "向左" then
        return "RIGHT"
    elseif dir == "居中" then
        return "CENTER"
    end
    return "TOP"
end

local function EnsureAnchorController()
    if anchorController then
        return anchorController
    end

    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExTargetAlertAnchor",
        title = L["被点名提示"],
        getDB = function()
            return EX_DB
        end,
        offsetXKey = "posX",
        offsetYKey = "posY",
        restoreKeys = {
            "locked",
            "preview",
        },
        syncWidgets = {
            "posX",
            "posY",
            "attachToCustom",
            "customAttachTarget",
        },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        widgetRanges = {
            posX = { min = -1000, max = 1000, step = 1 },
            posY = { min = -1000, max = 1000, step = 1 },
        },
        initialWidth = 200,
        initialHeight = 20,
        clampedToScreen = true,
        getAnchorPoint = function()
            return GetAnchorPointForDirection(EX_DB.growDirection or "向上")
        end,
        relativePoint = "CENTER",
        onCreateFrame = function(_, frame)
            frame:Hide()
        end,
    })

    return anchorController
end
if tostring(EX_DB.singleTargetLSM or "") == "" and tostring(EX_DB.targetLSM or "") ~= "" then
    EX_DB.singleTargetLSM = tostring(EX_DB.targetLSM or "")
end

local function GetTargetDetectDelay()
    local value = tonumber(EX_DB.targetDetectDelay)
    if value == nil then
        value = tonumber(EX_DEFAULTS.targetDetectDelay) or 0.10
    end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return tonumber(string.format("%.2f", value)) or 0.10
end

local function IsRoleEnabled()
    local roleKey = ExwindTools and ExwindTools.State and tostring(ExwindTools.State.RoleKey or ""):lower() or "unknown"
    if roleKey == "dps" then
        return EX_DB.enableForDps == true
    end
    if roleKey == "heal" then
        return EX_DB.enableForHeal == true
    end
    return false
end

local function PlayTargetLSMSoundByKey(key)
    if key == "" or not (LSM and type(LSM.Fetch) == "function" and PlaySoundFile) then
        return false
    end
    local soundPath = LSM:Fetch("sound", key, true)
    if type(soundPath) ~= "string" or soundPath == "" then
        return false
    end
    pcall(PlaySoundFile, soundPath, "Master")
    return true
end

local function CountActiveTargetBars()
    local count = 0
    for _, bar in pairs(activeBars) do
        if bar and bar.unit then
            count = count + 1
        end
    end
    return count
end

local function PlayConfiguredTargetSoundForCount(count)
    count = tonumber(count) or 0
    if count >= 2 then
        if EX_DB.multiTargetSoundEnabled ~= true then
            return false
        end
        return PlayTargetLSMSoundByKey(tostring(EX_DB.multiTargetLSM or ""))
    end
    if count == 1 then
        if EX_DB.singleTargetSoundEnabled ~= true then
            return false
        end
        return PlayTargetLSMSoundByKey(tostring(EX_DB.singleTargetLSM or ""))
    end
    return false
end

local function ScheduleTargetSoundDispatch()
    if pendingTargetSoundDispatch then
        return
    end
    pendingTargetSoundDispatch = true
    if not C_Timer then
        pendingTargetSoundDispatch = false
        PlayConfiguredTargetSoundForCount(CountActiveTargetBars())
        return
    end
    C_Timer.After(0, function()
        pendingTargetSoundDispatch = false
        PlayConfiguredTargetSoundForCount(CountActiveTargetBars())
    end)
end


local function ApplyIconBorder(bar, iconFrame, iconDb)
    if not bar.IconBorder then return end
    local edgeTex = iconDb and iconDb.showBorder and iconDb.borderTexture
        and iconDb.borderTexture ~= "None"
        and LSM and LSM:Fetch("border", iconDb.borderTexture) or nil
    if edgeTex then
        local edgeSize = iconDb.borderSize or 1
        local pad      = iconDb.borderPadding or 0
        bar.IconBorder:ClearAllPoints()
        bar.IconBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -pad, pad)
        bar.IconBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", pad, -pad)
        bar.IconBorder:SetBackdrop({ edgeFile = edgeTex, edgeSize = edgeSize })
        bar.IconBorder:SetBackdropBorderColor(
            iconDb.borderColorR or 1,
            iconDb.borderColorG or 1,
            iconDb.borderColorB or 1,
            iconDb.borderColorA or 1)
        bar.IconBorder:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
        bar.IconBorder:Show()
    else
        bar.IconBorder:Hide()
    end
end

local function UpdateBarVisuals(bar)
    local db = EX_DB
    local StaticDB = ExwindTools.DB_Static
    local group = db.timerGroup or {}
    local iconSz = math.max(20, db.iconModeSize or 36)
    local timerFontSz = math.max(8, (db.font_timer and db.font_timer.size) or db.iconModeTimerSize or 16)
    local iconSpacing = db.iconSpacing or 4
    local spellFont = db.font_spell or {}
    -- 文字 XY 偏移来自 font_timer 的 x/y 字段
    local ftx = (db.font_timer and db.font_timer.x) or 0
    local fty = (db.font_timer and db.font_timer.y) or 0
    local style = db.iconStyle or "图标+文字"

    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    if bar.bg then bar.bg:SetAlpha(0) end
    bar:SetBackdrop(nil)
    local sbTex2 = bar:GetStatusBarTexture()
    if sbTex2 then sbTex2:SetAlpha(0) end
    if bar.TextFrame then
        bar.TextFrame:SetFrameLevel(bar:GetFrameLevel() + 3)
    end

    if style == "单图标" then
        -- 用 iconSettings 宽高，图标填满，倒计时叠在图标上
        local iconW = math.max(20, (db.iconSettings and db.iconSettings.width) or iconSz)
        local iconH = math.max(20, (db.iconSettings and db.iconSettings.height) or iconSz)
        bar:SetSize(iconW, iconH)

        if bar.IconFrame then
            bar.IconFrame:ClearAllPoints()
            bar.IconFrame:SetAllPoints(bar)
            bar.IconFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
            bar.IconFrame:Show()
        end
        ApplyIconBorder(bar, bar.IconFrame or bar, db.iconSettings)
        if bar.Icon then
            bar.Icon:ClearAllPoints()
            bar.Icon:SetAllPoints(bar.IconFrame or bar)
            bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bar.Icon:SetVertexColor(1, 1, 1, 1)
            bar.Icon:Show()
        end
        if bar.Icon2 then bar.Icon2:Hide() end
        if bar.TimerText then
            bar.TimerText:ClearAllPoints()
            bar.TimerText:SetPoint("CENTER", bar.IconFrame or bar, "CENTER", ftx, fty)
            bar.TimerText:SetJustifyH("CENTER")
            if StaticDB and db.font_timer then
                StaticDB:ApplyFont(bar.TimerText, db.font_timer)
            else
                local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                bar.TimerText:SetFont(font, timerFontSz, "OUTLINE")
                bar.TimerText:SetTextColor(1, 1, 1, 1)
            end
            bar.TimerText:SetWidth(iconW)
            bar.TimerText:SetShown(bar._isPreview == true and EX_DB.showTimer == true)
        end
        if bar.SpellText then
            bar.SpellText:ClearAllPoints()
            bar.SpellText:SetPoint("CENTER", bar.IconFrame or bar, "CENTER", spellFont.x or 0, spellFont.y or 0)
            bar.SpellText:SetJustifyH("CENTER")
            if StaticDB and db.font_spell then
                StaticDB:ApplyFont(bar.SpellText, db.font_spell)
            else
                local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                local spellFontSz = math.max(8, spellFont.size or 16)
                bar.SpellText:SetFont(font, spellFontSz, spellFont.outline or "OUTLINE")
                bar.SpellText:SetTextColor(spellFont.r or 1, spellFont.g or 1, spellFont.b or 1, spellFont.a or 1)
            end
            bar.SpellText:SetWidth(math.max(iconW + 60, 120))
            bar.SpellText:SetMaxLines(1)
            bar.SpellText:SetWordWrap(false)
            if bar.SpellText.SetNonSpaceWrap then
                bar.SpellText:SetNonSpaceWrap(false)
            end
            bar.SpellText:SetShown(EX_DB.showSpellName == true)
        end
    else
        -- 图标+文字模式：[Icon2] [TimerText] [Icon]
        local textW  = math.max(48, timerFontSz * 4)
        local frameW = math.max((group.width or 120), iconSz * 2 + math.abs(iconSpacing) * 2 + textW)
        local frameH = math.max((group.height or iconSz), iconSz)
        bar:SetSize(frameW, frameH)

        -- 先清 TimerText 锚点，切断 单图标 模式遗留的 TimerText→IconFrame 依赖
        -- 之后 IconFrame→TimerText→bar 是单向链，不会循环
        if bar.TimerText then bar.TimerText:ClearAllPoints() end
        if bar.IconFrame then bar.IconFrame:ClearAllPoints() end
        if bar.Icon2 then bar.Icon2:ClearAllPoints() end

        -- TimerText 先锚到 bar（无任何对 IconFrame 的依赖）
        if bar.TimerText then
            bar.TimerText:SetPoint("CENTER", bar, "CENTER", ftx, fty)
            bar.TimerText:SetJustifyH("CENTER")
            if StaticDB and db.font_timer then
                StaticDB:ApplyFont(bar.TimerText, db.font_timer)
            else
                local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                bar.TimerText:SetFont(font, timerFontSz, "OUTLINE")
                bar.TimerText:SetTextColor(1, 1, 1, 1)
            end
            bar.TimerText:SetWidth(textW)
            bar.TimerText:SetShown(bar._isPreview == true and EX_DB.showTimer == true)
        end
        if bar.SpellText then
            bar.SpellText:ClearAllPoints()
            bar.SpellText:SetPoint("CENTER", bar, "CENTER", spellFont.x or 0, spellFont.y or 0)
            bar.SpellText:SetJustifyH("CENTER")
            if StaticDB and db.font_spell then
                StaticDB:ApplyFont(bar.SpellText, db.font_spell)
            else
                local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                local spellFontSz = math.max(8, spellFont.size or 16)
                bar.SpellText:SetFont(font, spellFontSz, spellFont.outline or "OUTLINE")
                bar.SpellText:SetTextColor(spellFont.r or 1, spellFont.g or 1, spellFont.b or 1, spellFont.a or 1)
            end
            bar.SpellText:SetWidth(math.max(frameW - 12, 120))
            bar.SpellText:SetMaxLines(1)
            bar.SpellText:SetWordWrap(false)
            if bar.SpellText.SetNonSpaceWrap then
                bar.SpellText:SetNonSpaceWrap(false)
            end
            bar.SpellText:SetShown(EX_DB.showSpellName == true)
        end

        -- IconFrame / Icon 锚到 TimerText 右侧（IconFrame→TimerText→bar，单向）
        if bar.IconFrame then
            bar.IconFrame:SetSize(iconSz, iconSz)
            bar.IconFrame:SetPoint("LEFT", bar.TimerText, "RIGHT", iconSpacing, 0)
            bar.IconFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
            bar.IconFrame:Show()
        end
        ApplyIconBorder(bar, bar.IconFrame or bar, db.iconSettings)
        if bar.Icon then
            bar.Icon:ClearAllPoints()
            bar.Icon:SetAllPoints(bar.IconFrame or bar)
            bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bar.Icon:SetVertexColor(1, 1, 1, 1)
            bar.Icon:Show()
        end

        -- Icon2 锚到 TimerText 左侧
        if bar.Icon2 then
            bar.Icon2:SetSize(iconSz, iconSz)
            bar.Icon2:SetPoint("RIGHT", bar.TimerText, "LEFT", -iconSpacing, 0)
            bar.Icon2:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bar.Icon2:SetVertexColor(1, 1, 1, 1)
            bar.Icon2:Show()
        end
    end

    if bar.Text then bar.Text:Hide() end
    if bar.Cooldown then
        bar.Cooldown:ClearAllPoints()
        if style == "单图标" and bar.IconFrame then
            bar.Cooldown:SetAllPoints(bar.IconFrame)
            -- 必须高于 IconFrame，否则扫圈渲染在图标后面（被遮住）
            bar.Cooldown:SetFrameLevel(bar.IconFrame:GetFrameLevel() + 2)
        else
            bar.Cooldown:SetAllPoints(bar)
            bar.Cooldown:SetFrameLevel(bar:GetFrameLevel() + 1)
        end
        bar.Cooldown:SetReverse(true)
        -- 单图标模式：开启扫描动画让图标倒计时可见；图标+文字模式关闭避免干扰
        bar.Cooldown:SetDrawSwipe(style == "单图标")
        bar.Cooldown:SetDrawEdge(style == "单图标")
        bar.Cooldown:SetDrawBling(false)
        if bar.Cooldown.SetMinimumCountdownDuration then
            bar.Cooldown:SetMinimumCountdownDuration(0)
        end
        if bar.Cooldown.SetCountdownMillisecondsThreshold then
            bar.Cooldown:SetCountdownMillisecondsThreshold(10)
        end
        if bar.Cooldown.SetCountdownAbbrevThreshold then
            bar.Cooldown:SetCountdownAbbrevThreshold(0)
        end
        bar.Cooldown:SetHideCountdownNumbers(bar._isPreview or not EX_DB.showTimer)

        local countdown = bar.Cooldown.GetCountdownFontString and bar.Cooldown:GetCountdownFontString() or nil
        if countdown then
            if StaticDB and db.font_timer then
                StaticDB:ApplyFont(countdown, db.font_timer)
            else
                local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
                countdown:SetFont(font, timerFontSz, "OUTLINE")
            end
            countdown:ClearAllPoints()
            local cdAnchor = (style == "单图标" and bar.IconFrame) or bar
            countdown:SetPoint("CENTER", cdAnchor, "CENTER", ftx, fty)
            countdown:SetJustifyH("CENTER")
        end
    end
end

local function SaveAnchorPosition()
    EnsureAnchorController():SavePosition()
end

ReLayout = function()
    if not anchorFrame then return end
    local group    = EX_DB.timerGroup or {}
    local iconSz   = math.max(20, EX_DB.iconModeSize or 36)
    local style    = EX_DB.iconStyle or "图标+文字"
    local spacing  = EX_DB.spacing or 0
    local list     = isPreviewing and previewBars or usedBarsList
    local dir      = EX_DB.growDirection or "向上"
    local isCenter = (dir == "居中")
    local isHoriz  = isCenter or dir == "向右" or dir == "向左"
    local maxLimit = EX_DB.maxBars or 5

    -- 单图标模式使用 iconSettings 宽高；否则使用 iconModeSize
    local barW, barH
    if style == "单图标" and EX_DB.iconSettings then
        barW = math.max(20, EX_DB.iconSettings.width or iconSz)
        barH = math.max(20, EX_DB.iconSettings.height or iconSz)
    else
        barW = group.width or 220
        barH = math.max(20, iconSz)
    end

    local visibleCount = 0
    for i, bar in ipairs(list) do
        if i <= maxLimit then
            visibleCount = visibleCount + 1
            bar:Show()
            bar:EnableMouse(false)
        else
            bar:Hide()
        end
    end

    local step = (isHoriz and barW or barH) + spacing
    local anchorW, anchorH
    if isHoriz then
        anchorW = math.max(20, visibleCount * barW + math.max(0, visibleCount - 1) * spacing)
        anchorH = math.max(20, barH)
    else
        anchorW = group.width or 220
        anchorH = math.max(20, visibleCount * barH + math.max(0, visibleCount - 1) * spacing)
        anchorH = math.max(20, anchorH * 1.1)
    end
    anchorFrame:SetSize(anchorW, anchorH)

    -- 条体始终相对 AnchorController 的唯一 anchor 排列；旧的私有背景手柄与标题
    -- 已删除，不能再承担编辑模式视觉或输入。
    for i, bar in ipairs(list) do
        if i <= maxLimit then
            bar:ClearAllPoints()
            if isCenter then
                local offset = (i - ((visibleCount + 1) / 2)) * step
                bar:SetPoint("CENTER", anchorFrame, "CENTER", offset, 0)
            else
                local offset = (i - 1) * step
                if dir == "向上" then
                    bar:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, offset)
                elseif dir == "向下" then
                    bar:SetPoint("TOP", anchorFrame, "TOP", 0, -offset)
                elseif dir == "向右" then
                    bar:SetPoint("LEFT", anchorFrame, "LEFT", offset, 0)
                else -- 向左
                    bar:SetPoint("RIGHT", anchorFrame, "RIGHT", -offset, 0)
                end
            end
        end
    end

    if editHandleFrame then
        editHandleFrame:ClearAllPoints()
        editHandleFrame:SetAllPoints(anchorFrame)
    end

    EnsureAnchorController():ApplyPosition()
end

RefreshAll = function()
    if isPreviewing then
        TogglePreview(false)
        TogglePreview(true)
    else
        for unit, bar in pairs(activeBars) do
            UpdateBarVisuals(bar)
            UpdateCast(unit)
        end
    end
    ReLayout()
    if anchorFrame then
        anchorFrame:Show()
        anchorFrame:EnableMouse(not EX_DB.locked)
    end
end

local function InitCastBarStructure(bar)
    bar:SetClampedToScreen(true)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bar.bg = bg
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.SpellText   = bar.TextFrame:CreateFontString(nil, "OVERLAY")
    bar.TimerText   = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.Cooldown    = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")

    -- 图标封装 Frame（用于样式渲染）
    local iconFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    iconFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.IconFrame = iconFrame

    local iconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    iconBorder:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
    iconBorder:Hide()
    bar.IconBorder = iconBorder

    bar.Icon       = iconFrame:CreateTexture(nil, "ARTWORK")
    bar.Icon2      = bar:CreateTexture(nil, "OVERLAY")
end

if ExwindFactory then
    ExwindFactory:InitPool("ExTargetAlertBar", "StatusBar", "BackdropTemplate", InitCastBarStructure)
end

local function AcquireBar()
    if not ExwindFactory then return end
    local bar      = ExwindFactory:Acquire("ExTargetAlertBar", anchorFrame)
    bar._isPreview = nil
    bar.unit       = nil
    UpdateBarVisuals(bar)
    return bar
end

local function ReleaseBar(bar)
    if not ExwindFactory or not bar then return end
    bar:SetScript("OnUpdate", nil)
    if bar.Cooldown then bar.Cooldown:Clear() end
    ExwindFactory:Release("ExTargetAlertBar", bar)
end

local function ScheduleCombatRecheck(unit)
    if not C_Timer or pendingCombatRechecks[unit] then return end
    local generation = combatRecheckGeneration
    local delay = GetTargetDetectDelay()
    pendingCombatRechecks[unit] = true
    C_Timer.After(delay, function()
        if generation ~= combatRecheckGeneration then return end
        pendingCombatRechecks[unit] = nil
        if not EX_DB.enabled or isPreviewing or not UnitExists(unit) then return end
        if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
            return
        end
        if UnitAffectingCombat(unit) then
            UpdateCast(unit, false)
        end
    end)
end

local function InvalidatePlayerTargetAlpha(bar, shouldHide)
    if not bar then return end
    bar._playerTargetRecheckToken = (bar._playerTargetRecheckToken or 0) + 1
    if shouldHide and bar.SetAlpha then
        bar:SetAlpha(0)
    end
end

local function UpdatePlayerTargetAlpha(bar, unit)
    if not bar then return end

    if bar._isPreview or not unit then
        bar:SetAlpha(1)
        return
    end
    bar:SetAlpha(1)
end

UpdateCast = function(unit, allowCombatRecheck, skipTargetDelay)
    if isPreviewing then return end
    if not IsRoleEnabled() then return end

    local unitLevel = UnitLevel(unit)
    if (EX_DB.hideLevel91Casts and unitLevel == 91) or (EX_DB.hideLevel92Casts and unitLevel == 92) then
        local bar = activeBars[unit]
        if bar then
            activeBars[unit] = nil
            for i, b in ipairs(usedBarsList) do
                if b == bar then
                    table.remove(usedBarsList, i); break
                end
            end
            ReleaseBar(bar); ReLayout()
        end
        return
    end

    local inCombat = UnitAffectingCombat(unit)
    if not inCombat and unit ~= "player" then
        local bar = activeBars[unit]
        if allowCombatRecheck and not bar then ScheduleCombatRecheck(unit) end
        if bar then
            activeBars[unit] = nil
            for i, b in ipairs(usedBarsList) do
                if b == bar then
                    table.remove(usedBarsList, i); break
                end
            end
            ReleaseBar(bar); ReLayout()
        end
        return
    end

    local objCast = UnitCastingDuration(unit)
    local objChannel = UnitChannelDuration(unit)
    local activeObj = objCast or objChannel
    local isChanneling = objChannel ~= nil
    local activeName
    local activeTexture

    if isChanneling then
        local channelName, _, channelTexture = UnitChannelInfo(unit)
        activeName = channelName
        activeTexture = channelTexture
    else
        local castName, _, castTexture = UnitCastingInfo(unit)
        activeName = castName
        activeTexture = castTexture
    end

    if not activeObj then
        local bar = activeBars[unit]
        if bar then
            activeBars[unit] = nil
            for i, b in ipairs(usedBarsList) do
                if b == bar then
                    table.remove(usedBarsList, i); break
                end
            end
            ReleaseBar(bar); ReLayout()
        end
        return
    end

    local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
    local isPlayerIdentityMatch = targetIdentity
        and type(targetIdentity.IsObservedTargetMatchingPlayerIdentity) == "function"
        and targetIdentity.IsObservedTargetMatchingPlayerIdentity(unit) == true or false
    if isPlayerIdentityMatch ~= true then
        local bar = activeBars[unit]
        if bar then
            activeBars[unit] = nil
            for i, b in ipairs(usedBarsList) do
                if b == bar then
                    table.remove(usedBarsList, i); break
                end
            end
            ReleaseBar(bar); ReLayout()
        end
        return
    end

    local bar = activeBars[unit]
    local created = false
    if not bar then
        bar = AcquireBar()
        activeBars[unit] = bar
        table.insert(usedBarsList, bar)
        created = true
        ReLayout()
    end
    bar.unit = unit
    InvalidatePlayerTargetAlpha(bar, false)
    if created then
        ScheduleTargetSoundDispatch()
    end

    bar.Icon:SetTexture(activeTexture)
    bar.Icon:SetVertexColor(1, 1, 1, 1)
    if bar.Icon2 then
        bar.Icon2:SetTexture(activeTexture)
        bar.Icon2:SetVertexColor(1, 1, 1, 1)
    end
    if bar.SpellText then
        bar.SpellText:SetText(activeName)
        bar.SpellText:SetShown(EX_DB.showSpellName == true)
    end

    UpdatePlayerTargetAlpha(bar, unit)
    bar:SetScript("OnUpdate", nil)

    if bar.SetTimerDuration then
        bar:SetTimerDuration(activeObj, Enum.StatusBarInterpolation.None, (isChanneling and 1 or 0))
    end
    if bar.Cooldown then
        bar.Cooldown:SetHideCountdownNumbers(not EX_DB.showTimer or bar._isPreview)
        if bar._isPreview then
            bar.Cooldown:Clear()
        elseif bar.Cooldown.SetCooldownFromDurationObject then
            bar.Cooldown:SetCooldownFromDurationObject(activeObj, true)
        end
    end
    if bar.TimerText then
        if bar._isPreview and EX_DB.showTimer then
            bar.TimerText:Show()
        else
            bar.TimerText:SetText("")
            bar.TimerText:Hide()
        end
    end
end

local function CreateAnchor()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()

    editHandleFrame = CreateFrame("Frame", nil, anchorFrame)
    editHandleFrame:SetAllPoints(anchorFrame)

    anchorFrame:SetScript("OnDragStart", function(self)
        if EX_DB.locked then return end
        self.isMoving = true; self:StartMoving()
    end)
    anchorFrame:SetScript("OnDragStop", function(self)
        if not self.isMoving then return end
        self.isMoving = false; self:StopMovingOrSizing(); SaveAnchorPosition()
    end)
    anchorFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not EX_DB.locked then
            local fn = self:GetScript("OnDragStart")
            if type(fn) == "function" then fn(self) end
        end
    end)
    anchorFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.isMoving then
            local fn = self:GetScript("OnDragStop")
            if type(fn) == "function" then fn(self) end
        end
    end)
    RefreshAll()
end

function TogglePreview(enable)
    isPreviewing = enable
    CreateAnchor()
    if enable then
        if anchorFrame then
            anchorFrame:Show()
            anchorFrame:EnableMouse(true)
        end
        for _, bar in pairs(activeBars) do bar:Hide() end
        for i = #previewBars, 1, -1 do
            local bar = previewBars[i]; bar:Hide(); ReleaseBar(bar); table.remove(previewBars, i)
        end

        local maxLimit = EX_DB.maxBars or 5
        for i = 1, maxLimit do
            local bar             = AcquireBar()
            bar._isPreview        = true
            bar._previewRaidIndex = (i - 1) % 8 + 1
            bar.Icon:SetTexture(136197)
            bar.Icon:SetVertexColor(1, 1, 1, 1)
            if bar.Icon2 then
                bar.Icon2:SetTexture(136197); bar.Icon2:SetVertexColor(1, 1, 1, 1)
            end
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0.5)
            UpdateBarVisuals(bar)
            if bar.SpellText then
                bar.SpellText:SetText(L["法术名称"])
                bar.SpellText:SetShown(EX_DB.showSpellName == true)
            end
            if bar.TimerText then
                bar.TimerText:SetText(L["2.5s"]); bar.TimerText:Show()
            end
            table.insert(previewBars, bar)
        end
    else
        for i = #previewBars, 1, -1 do
            local bar = previewBars[i]; bar:Hide(); ReleaseBar(bar); table.remove(previewBars, i)
        end
        for _, bar in pairs(activeBars) do UpdateCast(bar.unit) end
        if anchorFrame then
            anchorFrame:EnableMouse(not EX_DB.locked)
        end
    end
    ReLayout()
end

-- =============================================================
-- 事件处理
-- =============================================================
local function OnEvent(event, unit, castBarID)
    if not EX_DB.enabled or not unit then return end
    if not IsRoleEnabled() then return end
    if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
        if targetIdentity and type(targetIdentity.BeginObservedCast) == "function" then
            targetIdentity.BeginObservedCast(unit, castBarID, { source = "targetalert_tool" })
        end
        UpdateCast(unit, false, true)
        return
    end
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
        if targetIdentity and type(targetIdentity.EndObservedCast) == "function" then
            targetIdentity.EndObservedCast(unit, castBarID)
        end
        local bar = activeBars[unit]
        if bar then
            InvalidatePlayerTargetAlpha(bar, true)
            activeBars[unit] = nil
            for i, b in ipairs(usedBarsList) do
                if b == bar then
                    table.remove(usedBarsList, i); break
                end
            end
            ReleaseBar(bar); ReLayout()
        end
        return
    end
    local allowCombatRecheck = event == "NAME_PLATE_UNIT_ADDED"
    UpdateCast(unit, allowCombatRecheck)
end

local function OnUnitRemoved(_, unit)
    local targetIdentity = ExBoss and ExBoss.TargetIdentity or nil
    if targetIdentity and type(targetIdentity.ClearObservedUnit) == "function" then
        targetIdentity.ClearObservedUnit(unit)
    end
    pendingCombatRechecks[unit] = nil
    local bar = activeBars[unit]
    if bar then
        InvalidatePlayerTargetAlpha(bar, true)
        activeBars[unit] = nil
        for i, b in ipairs(usedBarsList) do
            if b == bar then
                table.remove(usedBarsList, i); break
            end
        end
        ReleaseBar(bar); ReLayout()
    end
end

local areEventsEnabled = false

local function EnableEnvEvents()
    if areEventsEnabled then return end
    areEventsEnabled = true
    ExwindTools:RegisterEvent("NAME_PLATE_UNIT_ADDED", EXWIND_MODULE_KEY, OnEvent)
    ExwindTools:RegisterEvent("NAME_PLATE_UNIT_REMOVED", EXWIND_MODULE_KEY, OnUnitRemoved)
    local events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    }
    for _, e in ipairs(events) do ExwindTools:RegisterEvent(e, EXWIND_MODULE_KEY, OnEvent) end
end

local function DisableEnvEvents()
    if not areEventsEnabled then return end
    areEventsEnabled = false
    ExwindTools:UnregisterEvent("NAME_PLATE_UNIT_ADDED", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("NAME_PLATE_UNIT_REMOVED", EXWIND_MODULE_KEY)
    local events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
    }
    for _, e in ipairs(events) do ExwindTools:UnregisterEvent(e, EXWIND_MODULE_KEY) end
    for _, bar in pairs(activeBars) do ReleaseBar(bar) end
    activeBars = {}; usedBarsList = {}
    combatRecheckGeneration = combatRecheckGeneration + 1
    pendingCombatRechecks = {}
    ReLayout()
end

local function CheckEnvStatus()
    local isParty = ExwindTools
        and ExwindTools.State
        and ExwindTools.State.InstanceType == "party"

    if EX_DB.enabled and IsRoleEnabled() and isParty then
        EnableEnvEvents()
    else
        DisableEnvEvents()
    end
end

-- GUI writes arrive through the one Core controller.  Only existing runtime
-- bars are restyled here; creation and preview materialisation remain their
-- normal lifecycle responsibility.
local function RefreshActiveSurfaces()
    for _, bar in pairs(activeBars) do
        UpdateBarVisuals(bar)
    end
    ReLayout()
    if anchorFrame then
        anchorFrame:SetShown(EX_DB.enabled == true)
        anchorFrame:EnableMouse(not EX_DB.locked)
    end
end
EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY .. ".InstanceTypeChanged", function()
    CheckEnvStatus()
    if EX_DB.enabled and IsRoleEnabled() then
        RefreshAll()
    end
end)

ExwindTools:WatchState("RoleKey", EXWIND_MODULE_KEY .. ".RoleChanged", function()
    CheckEnvStatus()
    if EX_DB.enabled and IsRoleEnabled() then
        RefreshAll()
    end
end)

ExwindTools:WatchState(TARGET_IDENTITY_ROSTER_REVISION, EXWIND_MODULE_KEY .. ".TargetIdentityRoster", function()
    if EX_DB.enabled and IsRoleEnabled() then
        RefreshAll()
    end
end)

ExwindTools:WatchState(TARGET_IDENTITY_UNIT_CHANGED, EXWIND_MODULE_KEY .. ".TargetIdentityUnit", function(info)
    if not areEventsEnabled or type(info) ~= "table" then
        return
    end
    local unit = tostring(info.unit or "")
    if string.match(unit, "^nameplate%d+$") then
        UpdateCast(unit, false, true)
    end
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if not info then return end
    if info.key == "btn_single_target_sound_test" then
        if EX_DB.singleTargetSoundEnabled == true then
            PlayTargetLSMSoundByKey(tostring(EX_DB.singleTargetLSM or ""))
        end
        return
    end
    if info.key == "btn_multi_target_sound_test" then
        if EX_DB.multiTargetSoundEnabled == true then
            PlayTargetLSMSoundByKey(tostring(EX_DB.multiTargetLSM or ""))
        end
        return
    end
    if info.key == "btn_reset_pos" then
        EX_DB.posX, EX_DB.posY = 0, 100
        if anchorFrame then
            EnsureAnchorController():ApplyPosition()
        end
        RefreshAll()
    elseif info.key == "btn_pick_frame" then
        EnsureAnchorController():StartFramePicker()
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    EX_DB.preview = false
    EX_DB.locked  = true
    C_Timer.After(1, function()
        CreateAnchor(); TogglePreview(false); RefreshAll(); CheckEnvStatus()
    end)
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

-- =============================================================
-- GUI 渲染接口（由 GlobalSettingsPage embed 调用）
-- =============================================================
ExBoss.UI.Panel.TargetAlertPage = ExBoss.UI.Panel.TargetAlertPage or {}
local GUIPage                   = ExBoss.UI.Panel.TargetAlertPage

local BASE_COLS = 200
local TARGET_CELL               = 18

function GUIPage:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then return end

    if not GUIPage._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_TargetAlertSettingsScroll",
            contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        GUIPage._scrollFrame = sf
        GUIPage._scrollChild = sc
    end

    local sf = GUIPage._scrollFrame
    local sc = GUIPage._scrollChild

    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetAllPoints(contentFrame)
    sc:SetWidth(contentFrame:GetWidth() - 24)

    local cols = math.max(BASE_COLS, math.floor(((contentFrame:GetWidth() - 24 - 20) / TARGET_CELL) + 0.5))
    Grid:SetContainerCols(sc, cols)

    ExwindTools.UI.ActivePageFrame = sc
    ExwindTools.UI.CurrentModule   = EXWIND_MODULE_KEY

    Grid:Render(sc, EX_LAYOUT, EX_DB, EXWIND_MODULE_KEY)

    sf:Show()
end

function GUIPage:Hide()
    if GUIPage._scrollFrame then
        GUIPage._scrollFrame:Hide()
        if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == GUIPage._scrollChild then
            ExwindTools.UI.ActivePageFrame = nil
            ExwindTools.UI.CurrentModule   = nil
        end
    end
end
