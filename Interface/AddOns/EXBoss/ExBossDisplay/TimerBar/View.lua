---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/TimerBar/View.lua
-- BOSS 技能倒计时条 HUD
--
-- 结构：AnchorController 管固定语义锚点 + EXUI TimerBarCollection
-- 进度：运行时由原生 Duration 驱动；Panel/World 样本使用静态 Progress
-- 编辑模式：AnchorController → 游戏内预览
-- =============================================================

-- =============================================================
-- 依赖检查与语言环境判断
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI     = ExwindTools.UI

local TimerBar = ExBoss.UI.TimerBar
local L        = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local function TraceColor(stage, timer, color, note)
    local trace = ExBoss and ExBoss.ColorTrace
    if trace and type(trace.Record) == "function" then trace:Record(stage, timer, color, note) end
end
local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

-- =============================================================
-- 模块常量与运行时状态
-- =============================================================
local MODULE_KEY                  = "ExBoss.TimerBar"
local TEST_PREFIX                 = "__exboss_test_"
local PREWARM_PREFIX              = "__exboss_prewarm_timerbar_"
local LEGACY_EVENT_KEY            = "encounter" .. "EventID"
local DEFAULT_ANCHOR_X            = -237
local DEFAULT_ANCHOR_Y            = 245
local TIME_SYNC_EPSILON           = 0.01
-- TimerBar 只声明垂直集合能力；WidgetLayout 负责执行并在非法旧值进入时
-- 回退本列表的首项（UP），绝不把横向方向作为兼容后门。
local TIMERBAR_ALLOWED_DIRECTIONS = { "UP", "DOWN" }

-- 运行时状态
local anchorFrame                 = nil
local anchorController            = nil
local runtimeCollection           = nil
local worldCollection             = nil
local panelPreview                = nil
local panelSurface                = nil
local panelDock                   = nil
local activeBars                  = {} -- [timerID] = TimerBar renderer record
local barList                     = {} -- renderer records; only the collection positions their ItemRoot
local _worldEditing               = false
local _sortDirty                  = false
local _testSeed                   = 0
local testTimers                  = {} -- [timerID] = { castTime, duration }
-- 非时间轴来源的独立倒数。供副本通用机制使用，不能写进 Scheduler._active。
local externalTimers              = {} -- [timerID] = timer
local CreateAnchor                = nil
local EnsureAnchorController      = nil
local _runtimeCache               = nil
local UpdateAnchorFrameSize       = nil
local FormatTime                  = nil
local _runtimeDurationTextOptions = nil
local _prewarmSerial              = 0

-- =============================================================
-- 计时条 DB 默认值
-- =============================================================
-- TimerBar 的唯一配置真源。新版本只读取 EXBOSS12S2.ModuleDB，绝不建立第二份
-- 配置镜像或旧结构回退。
local DEFAULT_DB                  = {
    enabled = true,
    hideLongTimersEnabled = true,
    hideLongTimersSeconds = 30,
    anchorX = DEFAULT_ANCHOR_X,
    anchorY = DEFAULT_ANCHOR_Y,
    attachToCustom = false,
    customAttachTarget = "",
    layout = { direction = "UP", spacing = 1, maxVisible = 6 },
    font_spell = {
        font = "默认",
        size = 16,
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        enabled = true,
        autoWidth = false,
        fixedWidth = 200,
        maxWidth = 0,
        justifyH = "LEFT",
        justifyV = "MIDDLE",
        outline = "OUTLINE",
        shadow = false,
        shadowColorR = 0,
        shadowColorG = 0,
        shadowColorB = 0,
        shadowColorA = 1,
        shadowX = 1,
        shadowY = -1,
        rotation = 0,
        gradientEnabled = false,
        gradientStart = 0,
        gradientLength = 0,
        x = 3,
        y = -0.79971738581881,
    },
    font_timer = {
        font = "默认",
        size = 16,
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        enabled = true,
        autoWidth = false,
        fixedWidth = 200,
        maxWidth = 0,
        justifyH = "RIGHT",
        justifyV = "MIDDLE",
        outline = "OUTLINE",
        shadow = false,
        shadowColorR = 0,
        shadowColorG = 0,
        shadowColorB = 0,
        shadowColorA = 1,
        shadowX = 1,
        shadowY = -1,
        rotation = 0,
        gradientEnabled = false,
        gradientStart = 0,
        gradientLength = 0,
        x = -2,
        y = 2.1179517119663e-05,
    },
    timerGroup = {
        width = 200,
        height = 25,
        texture = "EX_WhiteTexture",
        barColorR = 1.0,
        barColorG = 0.7,
        barColorB = 0.0,
        barColorA = 1.0,
        barBgColorR = 0.0,
        barBgColorG = 0.0,
        barBgColorB = 0.0,
        barBgColorA = 0.5,
        showBorder = true,
        borderTexture = "EX_WhiteBorder",
        borderColorR = 0.0,
        borderColorG = 0.0,
        borderColorB = 0.0,
        borderColorA = 1.0,
        borderSize = 1,
        borderPadding = 0,
        showIcon = true,
        iconSide = "LEFT",
        iconWidth = 24,
        iconHeight = 24,
        iconOffsetX = -1,
        iconOffsetY = 0,
        includeExternalIconInBounds = false,
        showIconBorder = true,
        iconBorderTexture = "EX_WhiteBorder",
        iconBorderColorR = 0.0,
        iconBorderColorG = 0.0,
        iconBorderColorB = 0.0,
        iconBorderColorA = 1.0,
        iconBorderSize = 1,
        iconBorderPadding = 0,
        fillDirection = "LEFT_TO_RIGHT",
        progressMode = "ELAPSED",
    },
    elements = {
        alertIcons = {
            texture = { enabled = true, width = 25, height = 25, x = -24.001646045594, y = -0.79952677016524 },
        },
    },
}

-- =============================================================
-- 配置 Schema 声明与注册
-- =============================================================
-- Preserve the current single ModuleDB declaration and schema while restoring
-- the V1 renderer below.  Runtime and settings pages therefore continue to
-- read/write the same root fields and four-state fill configuration.
local EX_DEFAULTS                 = {
    module = {
        enabled = DEFAULT_DB.enabled,
        hideLongTimersEnabled = DEFAULT_DB.hideLongTimersEnabled,
        hideLongTimersSeconds = DEFAULT_DB.hideLongTimersSeconds,
        anchorX = DEFAULT_DB.anchorX,
        anchorY = DEFAULT_DB.anchorY,
        attachToCustom = DEFAULT_DB.attachToCustom,
        customAttachTarget = DEFAULT_DB.customAttachTarget,
    },
    layout = DEFAULT_DB.layout,
    font_spell = DEFAULT_DB.font_spell,
    font_timer = DEFAULT_DB.font_timer,
    timerGroup = DEFAULT_DB.timerGroup,
    elements = DEFAULT_DB.elements,
}
local FONT_FIELDS                 = { "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth",
    "maxWidth", "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB",
    "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart", "gradientLength", "drawLayer",
    "drawSubLevel", "x", "y" }
local TIMER_FIELDS                = { "width", "height", "texture", "barColorR", "barColorG", "barColorB", "barColorA",
    "barBgColorR", "barBgColorG", "barBgColorB", "barBgColorA", "showBorder", "borderTexture", "borderColorR",
    "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding", "showIcon", "iconSide", "iconWidth",
    "iconHeight", "iconOffsetX", "iconOffsetY", "includeExternalIconInBounds", "showIconBorder", "iconBorderTexture",
    "iconBorderColorR", "iconBorderColorG", "iconBorderColorB", "iconBorderColorA", "iconBorderSize", "iconBorderPadding",
    "fillDirection", "progressMode" }
local DEFAULT_SCHEMA              = {
    { group = "module",     root = true,                                                                       fields = { "enabled", "hideLongTimersEnabled", "hideLongTimersSeconds", "anchorX", "anchorY", "attachToCustom", "customAttachTarget" } },
    { group = "layout",     fields = { "direction", "spacing", "maxVisible" } },
    { group = "font_spell", fields = FONT_FIELDS },
    { group = "font_timer", fields = FONT_FIELDS },
    { group = "timerGroup", fields = TIMER_FIELDS },
    { group = "elements",   fields = { alertIcons = { texture = { "enabled", "width", "height", "x", "y" } } } },
}
ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

-- =============================================================
-- DB 快捷访问
-- =============================================================
local function DB()
    return ExwindTools:GetModuleDB(MODULE_KEY)
end

function TimerBar:GetDB()
    return DB()
end

-- =============================================================
-- 显示名称与角标文字处理
-- =============================================================
local function IsSpellCountDisplayEnabled()
    local root = _G.EXBOSS12S2
    return type(root) == "table"
        and type(root.ui) == "table"
        and type(root.ui.general) == "table"
        and root.ui.general.showSpellOccurrenceCount == true
end

local function FormatOccurrenceCountText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    if not IsSpellCountDisplayEnabled() then
        return ""
    end
    if timer.useOccurrenceCount ~= true then
        return ""
    end
    local count = tonumber(timer.occurrenceCount)
    if not count or count <= 0 then
        return ""
    end
    return string.format("(%d)", count)
end

local function ResolveTimerBarDisplayName(timer)
    local usingRename = type(timer) == "table" and type(timer.timerBarName) == "string" and timer.timerBarName ~= ""
    local name = type(timer) == "table" and (timer.timerBarName or timer.displayName) or nil
    if not name and type(timer) == "table" and timer.spellID then
        local info = C_Spell.GetSpellInfo(timer.spellID)
        name = info and info.name
    end
    if not name then
        name = "???"
    end
    if usingRename then
        local countText = FormatOccurrenceCountText(timer)
        if countText ~= "" then
            name = string.format("%s %s", name, countText)
            return name, ""
        end
    end
    if type(timer) == "table" and timer.occurrenceDisplayMode == "inline" then
        local countText = FormatOccurrenceCountText(timer)
        if countText ~= "" then
            name = string.format("%s %s", name, countText)
        end
        return name, ""
    end
    if type(timer) == "table" and timer.occurrenceDisplayMode == "none" then
        return name, ""
    end
    return name, FormatOccurrenceCountText(timer)
end

-- =============================================================
-- 数值换算与样式默认值
-- =============================================================
local function SafeNum(v, def)
    local n = tonumber(v)
    if not n then return def end
    return n
end

local function CopyTextStyle(style)
    local copy = {}
    for key, value in pairs(type(style) == "table" and style or {}) do
        copy[key] = value
    end
    return copy
end

local function ApplyTimerTextColor(style, color)
    if type(color) ~= "table" then return style end
    local r, g, b = tonumber(color.r), tonumber(color.g), tonumber(color.b)
    if not (r and g and b) then return style end
    style.r, style.g, style.b, style.a = r, g, b, tonumber(color.a) or 1
    return style
end

local DEFAULT_STYLE = {
    width = 200,
    height = 25,
    texture = "EX_WhiteTexture",
    barColorR = 1.0,
    barColorG = 0.7,
    barColorB = 0.0,
    barColorA = 1.0,
    barBgColorR = 0.0,
    barBgColorG = 0.0,
    barBgColorB = 0.0,
    barBgColorA = 0.5,
    showBorder = true,
    borderTexture = "EX_WhiteBorder",
    borderColorR = 0.0,
    borderColorG = 0.0,
    borderColorB = 0.0,
    borderColorA = 1.0,
    borderSize = 1,
    borderPadding = 0,
    showIcon = true,
    iconSide = "LEFT",
    iconWidth = 24,
    iconHeight = 24,
    iconOffsetX = -1,
    iconOffsetY = 0,
    includeExternalIconInBounds = false,
    showIconBorder = true,
    iconBorderTexture = "EX_WhiteBorder",
    iconBorderColorR = 0.0,
    iconBorderColorG = 0.0,
    iconBorderColorB = 0.0,
    iconBorderColorA = 1.0,
    iconBorderSize = 1,
    iconBorderPadding = 0,
    fillDirection = "LEFT_TO_RIGHT",
    progressMode = "ELAPSED",
}

local DEFAULT_FONT_NAME = {
    font = "默认",
    size = 16,
    r = 1,
    g = 1,
    b = 1,
    a = 1,
    enabled = true,
    autoWidth = false,
    fixedWidth = 200,
    maxWidth = 0,
    justifyH = "LEFT",
    justifyV = "MIDDLE",
    outline = "OUTLINE",
    shadow = false,
    shadowColorR = 0,
    shadowColorG = 0,
    shadowColorB = 0,
    shadowColorA = 1,
    shadowX = 1,
    shadowY = -1,
    rotation = 0,
    gradientEnabled = false,
    gradientStart = 0,
    gradientLength = 0,
    x = 2.0001694361367,
    y = -0.79971738581881,
}

local DEFAULT_FONT_TIME = {
    font = "默认",
    size = 16,
    r = 1,
    g = 1,
    b = 1,
    a = 1,
    enabled = true,
    autoWidth = false,
    fixedWidth = 200,
    maxWidth = 0,
    justifyH = "RIGHT",
    justifyV = "MIDDLE",
    outline = "OUTLINE",
    shadow = false,
    shadowColorR = 0,
    shadowColorG = 0,
    shadowColorB = 0,
    shadowColorA = 1,
    shadowX = 1,
    shadowY = -1,
    rotation = 0,
    gradientEnabled = false,
    gradientStart = 0,
    gradientLength = 0,
    x = 2,
    y = 2.1179517119663e-05,
}

local function GetStyleDB(db)
    if type(db) == "table" and type(db.timerGroup) == "table" then
        return db.timerGroup
    end
    return db
end

local function ResolveStyle(db)
    local src = GetStyleDB(db)
    if type(src) ~= "table" then
        return DEFAULT_STYLE
    end

    local style = {}
    for k, v in pairs(DEFAULT_STYLE) do
        if src[k] ~= nil then
            style[k] = src[k]
        else
            style[k] = v
        end
    end
    return style
end

-- =============================================================
-- 预览样本数据
-- =============================================================
-- 计时条预览样例唯一真源：设置页面板与游戏世界编辑模式都把这些普通
-- 状态交给同一个 EXUI TimerBarCollection。
local PREVIEW_SPELL_IDS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }
-- 设置页只物化当前需要的 1–6 条样本；隐藏槽位不应常驻并参与 Slider live 重套。
local PANEL_PREVIEW_MIN_SAMPLES = 1
local PANEL_PREVIEW_MAX_SAMPLES = 6
local PANEL_PREVIEW_PADDING = 28
local PANEL_PREVIEW_ABSOLUTE_MIN_HEIGHT = 120
local PREVIEW_FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark；仅 API 不可用时的静态预览回退。

local function MakeFallbackPreviewSample(index, spellID)
    return {
        spellID = spellID,
        name = string.format("%s %d", L["测试技能"] or "测试技能", index),
        iconID = PREVIEW_FALLBACK_ICON,
        duration = 15,
        remaining = math.min(15, index * 3),
        iconFlags = (index % 3 == 1 and 128) or (index % 3 == 2 and 256) or 1,
    }
end

-- 只供 panel/world 静态样本使用；运行时 timer 不经过这里。正常情况必须通过
-- C_Spell 取得真实名称与图标；客户端短暂未返回资料时，仍交付正式可见的静态
-- fallback，设置页不得因此变成空白。
local function BuildPreviewSamples()
    local samples = {}
    for index, spellID in ipairs(PREVIEW_SPELL_IDS) do
        local info = C_Spell and type(C_Spell.GetSpellInfo) == "function" and C_Spell.GetSpellInfo(spellID) or nil
        if info and info.name and info.iconID then
            samples[#samples + 1] = {
                spellID = spellID,
                name = info.name,
                iconID = info.iconID,
                duration = 15,
                remaining = math.min(15, index * 3),
                iconFlags = (index % 3 == 1 and 128) or (index % 3 == 2 and 256) or 1,
            }
        else
            samples[#samples + 1] = MakeFallbackPreviewSample(index, spellID)
        end
    end
    return samples
end

-- =============================================================
-- 填充模式、进度换算与运行时缓存
-- =============================================================
-- TimerBarWidget 的可见样式只有这一处入口：正常运行、编辑模式与设置页预览共用。
local function Clamp01(v)
    if v <= 0 then return 0 end
    if v >= 1 then return 1 end
    return v
end

local function ResolveFillDirection(db)
    local style = GetStyleDB(db) or DEFAULT_STYLE
    local direction = tostring(style.fillDirection or "LEFT_TO_RIGHT"):upper()
    return direction == "RIGHT_TO_LEFT" and "RIGHT_TO_LEFT" or "LEFT_TO_RIGHT"
end

local function ResolveProgressMode(db)
    local style = GetStyleDB(db) or DEFAULT_STYLE
    local mode = tostring(style.progressMode or "ELAPSED"):upper()
    return mode == "REMAINING" and "REMAINING" or "ELAPSED"
end

local function InvalidateRuntimeCache()
    _runtimeCache = nil
end

local function GetRuntimeCache()
    if _runtimeCache then
        return _runtimeCache
    end
    local db = DB() or {}
    local style = ResolveStyle(db)
    local h = SafeNum(style.height, DEFAULT_STYLE.height)
    if h < 8 then h = 8 end
    local layout = db.layout
    local spacing = SafeNum(layout.spacing, 1)
    local maxBars = math.floor(SafeNum(layout.maxVisible, 6))
    if maxBars < 1 then maxBars = 1 end
    if maxBars > 6 then maxBars = 6 end
    _runtimeCache = {
        fillDirection = ResolveFillDirection(db),
        progressMode = ResolveProgressMode(db),
        height = h,
        spacing = spacing,
        growDir = tostring(layout.direction or "UP"):upper() == "DOWN" and "DOWN" or "UP",
        maxBars = maxBars,
    }
    return _runtimeCache
end


-- 运行、世界编辑和面板预览共同使用统一的 progressMode；方向仅由
-- fillDirection 决定，不能再混入四态旧字段。
local function ResolveTimerBarProgress(remaining, duration, progressMode)
    local d = math.max(1, tonumber(duration) or 1)
    local rem = math.max(0, tonumber(remaining) or 0)
    local ratio = rem / d
    if progressMode == "ELAPSED" then
        ratio = 1 - ratio
    end
    return Clamp01(ratio), 1
end

local function ResolveNativeTimerDirection(progressMode)
    if Enum and Enum.StatusBarTimerDirection then
        return progressMode == "REMAINING"
            and Enum.StatusBarTimerDirection.RemainingTime
            or Enum.StatusBarTimerDirection.ElapsedTime
    end
    return progressMode == "REMAINING" and 1 or 0
end

local function GetRuntimeDurationTextOptions()
    if _runtimeDurationTextOptions then
        return _runtimeDurationTextOptions
    end
    if not (C_StringUtil and type(C_StringUtil.CreateNumericRuleFormatter) == "function"
            and Enum and Enum.DurationTextBindingProperty and Enum.NumericRuleFormatRounding) then
        error("ExBoss.TimerBar requires native Duration text formatting", 2)
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({
        {
            threshold = 0,
            format = "%.1f",
        },
        {
            threshold = 10,
            step = 1,
            rounding = Enum.NumericRuleFormatRounding.Nearest,
            format = "%.0f",
        },
        {
            threshold = 60,
            format = "%d:%02d",
            components = {
                {
                    div = 60,
                    step = 1,
                    rounding = Enum.NumericRuleFormatRounding.Down,
                },
                {
                    mod = 60,
                    step = 1,
                    rounding = Enum.NumericRuleFormatRounding.Down,
                },
            },
        },
    })
    _runtimeDurationTextOptions = {
        property = Enum.DurationTextBindingProperty.RemainingDuration,
        formatter = formatter,
        expiredText = "",
        zeroDurationText = "",
        updateInterval = 0.05,
    }
    return _runtimeDurationTextOptions
end

local function BuildRuntimeDurationTimePresentation(durationObject, progressMode)
    local interpolation = Enum and Enum.StatusBarInterpolation
        and (Enum.StatusBarInterpolation.None or Enum.StatusBarInterpolation.Immediate) or 0
    return {
        mode = "DURATION",
        duration = durationObject,
        interpolation = interpolation,
        direction = ResolveNativeTimerDirection(progressMode),
        textOptions = GetRuntimeDurationTextOptions(),
    }
end

local function SetClickThrough(frame)
    if not frame then return end
    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(false)
    end
end

-- =============================================================
-- 计时器事件与颜色辅助函数
-- =============================================================
local function ResolveTimerEventID(timer)
    if type(timer) ~= "table" then return nil end
    local eventID = tonumber(timer.eventID)
    if eventID then return eventID end
    return tonumber(rawget(timer, LEGACY_EVENT_KEY))
end

local function SafeExtractRGB(c)
    if type(c) ~= "table" then return nil end
    local r = tonumber(c.r)
    local g = tonumber(c.g)
    local b = tonumber(c.b)
    if r and g and b then
        return r, g, b
    end
    if type(c.GetRGB) == "function" then
        local rr, gg, bb = c:GetRGB()
        if tonumber(rr) and tonumber(gg) and tonumber(bb) then
            return tonumber(rr), tonumber(gg), tonumber(bb)
        end
    end
    return nil
end

local function IsBlizzardManagedTimer(timer)
    return type(timer) == "table" and (timer.timelineManaged == true or timer.source == "blizzard")
end

-- =============================================================
-- 警示图标（Alert）系统
-- =============================================================
local ALERT_FLAG_DEFS = {
    { name = "deadly",  bit = 1,   atlases = { "icons_64x64_deadly", "combattimeline-fx-deadlyglow-base", "common-icon-redx" },                                            texture = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "enrage",  bit = 2,   atlases = { "icons_64x64_enrage" },                                                                                                     texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "bleed",   bit = 4,   atlases = { "icons_64x64_bleed", "UI-Debuff-Border-Bleed-Icon", "RaidFrame-Icon-DebuffBleed" },                                         texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "magic",   bit = 8,   atlases = { "icons_64x64_magic", "RaidFrame-Icon-DebuffMagic", "UI-HUD-CoolDownManager-Debuff-Magic" } },
    { name = "disease", bit = 16,  atlases = { "icons_64x64_disease", "RaidFrame-Icon-DebuffDisease", "UI-HUD-CoolDownManager-Debuff-Disease" } },
    { name = "curse",   bit = 32,  atlases = { "icons_64x64_curse", "RaidFrame-Icon-DebuffCurse", "UI-HUD-CoolDownManager-Debuff-Curse" } },
    { name = "poison",  bit = 64,  atlases = { "icons_64x64_poison", "RaidFrame-Icon-DebuffPoison", "UI-HUD-CoolDownManager-Debuff-Poison" } },
    { name = "tank",    bit = 128, atlases = { "icons_64x64_tank", "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "UI-LFG-RoleIcon-Tank-Micro", "UI-LFG-RoleIcon-Tank" },       texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 0, right = 19 / 64, top = 22 / 64, bottom = 41 / 64 } },
    { name = "heal",    bit = 256, atlases = { "icons_64x64_heal", "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "UI-LFG-RoleIcon-Healer-Micro", "UI-LFG-RoleIcon-Healer" }, texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 1 / 64, bottom = 20 / 64 } },
    { name = "damage",  bit = 512, atlases = { "icons_64x64_damage", "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "UI-LFG-RoleIcon-DPS-Micro", "UI-LFG-RoleIcon-DPS" },        texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 22 / 64, bottom = 41 / 64 } },
}

local _alertAtlasExistCache = {}

local function HasFlag(v, b)
    v = tonumber(v) or 0
    b = tonumber(b) or 0
    if v <= 0 or b <= 0 then return false end
    if bit32 and bit32.band then return bit32.band(v, b) ~= 0 end
    if bit and bit.band then return bit.band(v, b) ~= 0 end
    return (v % (b * 2)) >= b
end

local function IsAlertAtlasValid(atlasName)
    if not atlasName or atlasName == "" then return false end
    local cached = _alertAtlasExistCache[atlasName]
    if cached ~= nil then return cached end
    local valid = true
    if C_Texture and C_Texture.GetAtlasInfo then
        valid = C_Texture.GetAtlasInfo(atlasName) ~= nil
    end
    _alertAtlasExistCache[atlasName] = valid and true or false
    return _alertAtlasExistCache[atlasName]
end

local function GetTimerIconFlags(timer)
    return tonumber(type(timer) == "table" and timer.iconFlags or nil) or 0
end

local function ApplyAlertTexture(tex, iconFlags)
    if not tex then return false end
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        tex:Hide()
        return false
    end
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        if HasFlag(flags, cfg.bit) then
            if type(cfg.atlases) == "table" then
                for _, atlas in ipairs(cfg.atlases) do
                    if IsAlertAtlasValid(atlas) then
                        tex:SetTexture(nil)
                        tex:SetTexCoord(0, 1, 0, 1)
                        tex:SetAtlas(atlas, true)
                        tex:Show()
                        return true
                    end
                end
            end
            if cfg.texture and cfg.texture.file then
                tex:SetTexture(cfg.texture.file)
                tex:SetTexCoord(cfg.texture.left or 0, cfg.texture.right or 1, cfg.texture.top or 0,
                    cfg.texture.bottom or 1)
                tex:Show()
                return true
            end
        end
    end
    tex:Hide()
    return false
end

local function CollectAlertVisuals(iconFlags)
    local out = {}
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return out
    end
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        if HasFlag(flags, cfg.bit) then
            local added = false
            if type(cfg.atlases) == "table" then
                for _, atlas in ipairs(cfg.atlases) do
                    if IsAlertAtlasValid(atlas) then
                        out[#out + 1] = { atlas = atlas }
                        added = true
                        break
                    end
                end
            end
            if (not added) and cfg.texture and cfg.texture.file then
                out[#out + 1] = {
                    file = cfg.texture.file,
                    left = cfg.texture.left or 0,
                    right = cfg.texture.right or 1,
                    top = cfg.texture.top or 0,
                    bottom = cfg.texture.bottom or 1,
                }
            end
        end
    end
    return out
end

local function BuildAlertIconMarkup(iconFlags, iconSize, iconYOffset)
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return ""
    end
    local renderSize = tonumber(iconSize) or 16
    local renderYOffset = tonumber(iconYOffset) or 0
    local marks = {}
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        local bitMask = tonumber(cfg.bit) or 0
        if bitMask > 0 and HasFlag(flags, bitMask) then
            local atlasList = cfg.atlases
            local added = false
            if type(atlasList) ~= "table" or #atlasList == 0 then
                atlasList = { "icons_64x64_" .. tostring(cfg.name or "") }
            end
            for _, atlas in ipairs(atlasList) do
                if IsAlertAtlasValid(atlas) then
                    if CreateAtlasMarkup then
                        marks[#marks + 1] = CreateAtlasMarkup(atlas, renderSize, renderSize, 0, renderYOffset)
                    else
                        marks[#marks + 1] = string.format("|A:%s:%d:%d:0:%d|a", atlas, renderSize, renderSize,
                            renderYOffset)
                    end
                    added = true
                    break
                end
            end
            if (not added) and cfg.texture and cfg.texture.file and cfg.texture.file ~= "" then
                local tex = cfg.texture
                local width = tonumber(tex.width) or 64
                local height = tonumber(tex.height) or 64
                if CreateTextureMarkup then
                    marks[#marks + 1] = CreateTextureMarkup(
                        tex.file,
                        width,
                        height,
                        renderSize,
                        renderSize,
                        tonumber(tex.left) or 0,
                        tonumber(tex.right) or 1,
                        tonumber(tex.top) or 0,
                        tonumber(tex.bottom) or 1,
                        0,
                        renderYOffset
                    )
                else
                    marks[#marks + 1] = string.format(
                        "|T%s:%d:%d:0:%d:%d:%d:%d:%d:%d:%d:%d|t",
                        tex.file,
                        renderSize,
                        renderSize,
                        renderYOffset,
                        width,
                        height,
                        math.floor((tonumber(tex.left) or 0) * width),
                        math.floor((tonumber(tex.right) or 1) * width),
                        math.floor((tonumber(tex.top) or 0) * height),
                        math.floor((tonumber(tex.bottom) or 1) * height)
                    )
                end
            end
        end
    end
    return table.concat(marks, " ")
end

local function GetAlertIconStyle(db)
    local elements = type(db) == "table" and db.elements or nil
    local entry = type(elements) == "table" and elements.alertIcons or nil
    local style = type(entry) == "table" and entry.texture or nil
    if type(style) ~= "table" then
        error("ExBoss.TimerBar requires elements.alertIcons.texture", 2)
    end
    return style
end

local ALERT_ELEMENT_ID = "elements.alertIcons"

-- TimerBar 只声明局部语义、GUI key 与正式 DB 路径。EXUI 统一拥有 Panel
-- intent、右键 Focus、X/Y 写回与 Grid 回读；额外材质的实际业务绘制仍留在本模块。
local INTERACTION_SCHEMA = {
    ["core.spellName"] = {
        guiKey = "font_spell",
        movable = true,
        tooltip = L["法术名称"],
        textRole = "label",
        position = { x = "font_spell.x", y = "font_spell.y" },
        anchor = { point = "LEFT", relativeElement = "core.bar", relativePoint = "LEFT" },
    },
    ["core.time"] = {
        guiKey = "font_timer",
        movable = true,
        tooltip = L["时间"],
        textRole = "time",
        position = { x = "font_timer.x", y = "font_timer.y" },
        anchor = { point = "RIGHT", relativeElement = "core.bar", relativePoint = "RIGHT" },
    },
    [ALERT_ELEMENT_ID] = {
        guiKey = "extraTexture",
        movable = true,
        tooltip = L["提示图标"],
        position = { x = "elements.alertIcons.texture.x", y = "elements.alertIcons.texture.y" },
        anchor = { point = "RIGHT", relativeElement = "core.bar", relativePoint = "LEFT" },
    },
}

local function BuildStandardTimerBarInteraction(db)
    return ExwindTools.UI:BuildStandardPreviewInteraction("TimerBar", db, INTERACTION_SCHEMA)
end


-- =============================================================
-- 外观 Presentation 构建
-- =============================================================
-- TimerBar 只有这一份 presentation。真实计时、世界编辑样本、GUI 样本都先
-- 变成这份普通数据，再交给同一个 EXUI TimerBarCollection 物化。这里不创建
-- Frame，也不因宿主不同改变文字、图标、层级或尺寸。
local function BuildTimerBarPresentation(timer, priority, now, runtimeDurationObject)
    local db = DB() or {}
    local sourceStyle = ResolveStyle(db)
    local style = {}
    for key, value in pairs(sourceStyle) do style[key] = value end

    style.fillDirection = ResolveFillDirection(db)
    local progressMode = ResolveProgressMode(db)

    local eventColor = type(timer) == "table" and timer.eventColor or nil
    if type(eventColor) == "table" and tonumber(eventColor.r) and tonumber(eventColor.g) and tonumber(eventColor.b) then
        style.barColorR, style.barColorG, style.barColorB = eventColor.r, eventColor.g, eventColor.b
    end
    -- Keep the pre-refactor contract: bar fill uses eventColor, while the
    -- per-event text override is an independent timerTextColor channel.
    local timerTextColor = type(timer) == "table" and timer.timerTextColor or nil
    local labelStyle = ApplyTimerTextColor(CopyTextStyle(db.font_spell or DEFAULT_FONT_NAME), timerTextColor)
    local timeStyle = ApplyTimerTextColor(CopyTextStyle(db.font_timer or DEFAULT_FONT_TIME), timerTextColor)
    local trace = ExBoss and ExBoss.ColorTrace
    local text = trace and type(trace.Describe) == "function" and trace:Describe(timerTextColor) or "?"
    TraceColor("TimerBar.Presentation", timer, eventColor, "timerText=" .. text)

    local name, occurrence = ResolveTimerBarDisplayName(timer)
    if type(occurrence) == "string" and occurrence ~= "" then
        name = string.format("%s %s", name or "???", occurrence)
    end

    local icon = type(timer) == "table" and timer.iconFileID or nil
    if type(timer) == "table" and timer.spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(timer.spellID)
        icon = info and info.iconID or icon
    end

    local duration = math.max(1, tonumber(type(timer) == "table" and (timer.timerBarDuration or timer.duration)) or 30)
    local castTime = tonumber(type(timer) == "table" and timer.castTime) or ((now or GetTime()) + duration)
    local remaining = math.max(0, castTime - (now or GetTime()))
    local progressValue, progressMaximum = ResolveTimerBarProgress(remaining, duration, progressMode)
    local timePresentation = nil
    local progressPresentation = nil
    if runtimeDurationObject then
        timePresentation = BuildRuntimeDurationTimePresentation(runtimeDurationObject, progressMode)
    else
        -- Panel/world samples stay static.  Only the live runtime surface owns
        -- native Duration objects.
        timePresentation = remaining > 0 and { text = FormatTime(remaining), shown = true } or nil
        progressPresentation = { value = progressValue, maximum = progressMaximum }
    end
    local alert = GetAlertIconStyle(db)
    local visuals = alert.enabled ~= false and CollectAlertVisuals(GetTimerIconFlags(timer)) or {}
    local alertIconWidth = math.max(1, SafeNum(alert.width, 16))
    local alertIconHeight = math.max(1, SafeNum(alert.height, 16))
    local regionElements = {}
    for index, visual in ipairs(visuals) do
        local previousID = index > 1 and ("alertIcon" .. (index - 1)) or nil
        regionElements[#regionElements + 1] = {
            id = "alertIcon" .. index,
            kind = "texture",
            stylePath = "elements.alertIcons.texture",
            style = alert,
            shown = alert.enabled ~= false,
            -- 第一个图标从统一 texture 的 x/y 挂到条体左侧；后续图标仅链式
            -- 锚定在前一个 Region，不能重复叠加同一份 x/y。
            position = previousID and { x = 0, y = 0 } or nil,
            anchor = previousID
                and { point = "RIGHT", relativeElement = "elements." .. previousID, relativePoint = "LEFT", x = -2 }
                or { point = "RIGHT", relativeElement = "core.bar", relativePoint = "LEFT" },
            bounds = { width = alertIconWidth, height = alertIconHeight },
            content = {
                atlas = visual.atlas,
                texture = visual.file,
                texCoord = visual.file and { visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1 } or
                nil,
                shown = alert.enabled ~= false,
            },
            interaction = index == 1 and {
                elementID = ALERT_ELEMENT_ID,
                guiTarget = "extraTexture",
                movable = true,
            } or nil,
        }
    end

    return {
        style = {
            timerBar = style,
            text = { label = labelStyle, time = timeStyle },
        },
        icon = { value = icon },
        label = name or "???",
        -- Runtime Duration uses an empty expired text so the bar can remain at
        -- zero without showing "0.0".  Static previews retain the old text and
        -- progress presentation.
        time = timePresentation,
        progress = progressPresentation,
        regionElements = regionElements,
        interaction = BuildStandardTimerBarInteraction(db),
    }
end

local function ResolveRuntimeTiming(timer, now)
    local duration = math.max(1, tonumber(type(timer) == "table" and (timer.timerBarDuration or timer.duration)) or 30)
    local castTime = tonumber(type(timer) == "table" and timer.castTime) or ((now or GetTime()) + duration)
    return castTime, duration
end

local function EnsureRuntimeDuration(record, now)
    if not record.durationObject then
        if not (C_DurationUtil and type(C_DurationUtil.CreateDuration) == "function") then
            error("ExBoss.TimerBar requires C_DurationUtil.CreateDuration", 2)
        end
        record.durationObject = C_DurationUtil.CreateDuration()
    end
    local currentNow = now or GetTime()
    local castTime, duration = ResolveRuntimeTiming(record.timer, currentNow)
    record.durationObject:SetTimeFromEnd(castTime, duration, 1)
    record.boundCastTime = castTime
    record.boundDuration = duration
    record.boundProgressMode = GetRuntimeCache().progressMode
    record.durationExpired = castTime <= currentNow
    return record.durationObject
end

local function CaptureRuntimeStaticState(record)
    local timer = record and record.timer or nil
    local eventColor = type(timer) == "table" and timer.eventColor or nil
    local timerTextColor = type(timer) == "table" and timer.timerTextColor or nil
    local state = record.staticState or {}
    state.spellID = type(timer) == "table" and timer.spellID or nil
    state.iconFileID = type(timer) == "table" and timer.iconFileID or nil
    state.timerBarName = type(timer) == "table" and timer.timerBarName or nil
    state.displayName = type(timer) == "table" and timer.displayName or nil
    state.occurrenceCount = type(timer) == "table" and timer.occurrenceCount or nil
    state.useOccurrenceCount = type(timer) == "table" and timer.useOccurrenceCount or nil
    state.occurrenceDisplayMode = type(timer) == "table" and timer.occurrenceDisplayMode or nil
    state.iconFlags = type(timer) == "table" and timer.iconFlags or nil
    state.barPriority = type(timer) == "table" and timer.barPriority or nil
    state.occurrenceEnabled = IsSpellCountDisplayEnabled()
    state.eventR = type(eventColor) == "table" and eventColor.r or nil
    state.eventG = type(eventColor) == "table" and eventColor.g or nil
    state.eventB = type(eventColor) == "table" and eventColor.b or nil
    state.eventA = type(eventColor) == "table" and eventColor.a or nil
    state.textR = type(timerTextColor) == "table" and timerTextColor.r or nil
    state.textG = type(timerTextColor) == "table" and timerTextColor.g or nil
    state.textB = type(timerTextColor) == "table" and timerTextColor.b or nil
    state.textA = type(timerTextColor) == "table" and timerTextColor.a or nil
    record.staticState = state
end

local function RuntimeStaticStateChanged(record)
    local state = record and record.staticState or nil
    local timer = record and record.timer or nil
    if not state or type(timer) ~= "table" then return true end
    local eventColor = type(timer.eventColor) == "table" and timer.eventColor or nil
    local timerTextColor = type(timer.timerTextColor) == "table" and timer.timerTextColor or nil
    return state.spellID ~= timer.spellID
        or state.iconFileID ~= timer.iconFileID
        or state.timerBarName ~= timer.timerBarName
        or state.displayName ~= timer.displayName
        or state.occurrenceCount ~= timer.occurrenceCount
        or state.useOccurrenceCount ~= timer.useOccurrenceCount
        or state.occurrenceDisplayMode ~= timer.occurrenceDisplayMode
        or state.iconFlags ~= timer.iconFlags
        or state.barPriority ~= timer.barPriority
        or state.occurrenceEnabled ~= IsSpellCountDisplayEnabled()
        or state.eventR ~= (eventColor and eventColor.r or nil)
        or state.eventG ~= (eventColor and eventColor.g or nil)
        or state.eventB ~= (eventColor and eventColor.b or nil)
        or state.eventA ~= (eventColor and eventColor.a or nil)
        or state.textR ~= (timerTextColor and timerTextColor.r or nil)
        or state.textG ~= (timerTextColor and timerTextColor.g or nil)
        or state.textB ~= (timerTextColor and timerTextColor.b or nil)
        or state.textA ~= (timerTextColor and timerTextColor.a or nil)
end

local function ApplyRecord(collection, record, now, runtime)
    if not collection or not record then return end
    if not record.item then
        record.item = collection:AcquireItem(record.id)
    end
    local durationObject = runtime and EnsureRuntimeDuration(record, now) or nil
    local presentation = BuildTimerBarPresentation(record.timer, record.priority, now, durationObject)
    collection:ApplyItem(record.item, presentation)
    if runtime then
        CaptureRuntimeStaticState(record)
    end
end

local function UpdateRuntimeDuration(collection, record, now)
    if not (collection and record and record.item and record.durationObject) then return false end
    local castTime, duration = ResolveRuntimeTiming(record.timer, now)
    local progressMode = GetRuntimeCache().progressMode
    local expired = castTime <= now
    local needsUpdate = record.boundDuration ~= duration
        or record.boundProgressMode ~= progressMode
        or record.durationExpired ~= expired
    if not needsUpdate and not expired then
        needsUpdate = math.abs(castTime - (tonumber(record.boundCastTime) or castTime)) > TIME_SYNC_EPSILON
    end
    -- Once a Duration has reached zero, Scheduler-owned hold states may keep
    -- writing castTime=now.  The renderer must remain at the endpoint instead
    -- of rebinding the native timer every tick.
    if not needsUpdate then return false end

    record.durationObject:SetTimeFromEnd(castTime, duration, 1)
    collection:UpdateItemTime(record.item,
        BuildRuntimeDurationTimePresentation(record.durationObject, progressMode))
    record.boundCastTime = castTime
    record.boundDuration = duration
    record.boundProgressMode = progressMode
    record.durationExpired = expired
    return true
end

local function ApplyRuntimeAlpha(record, now)
    if not (record and record.item and record.item.root) then return end
    local waiting = record.timer and record.timer.fixedAIWaitingTimelineFinish == true
    if not waiting and record.alphaWaiting == false then return end
    record.item.root:SetAlpha(waiting
        and (0.62 + 0.38 * math.abs(math.sin((now or GetTime()) * 5.5))) or 1)
    record.alphaWaiting = waiting
end

-- =============================================================
-- Acquire / Release
-- =============================================================
local function AcquireBar(timerID, priority)
    if not runtimeCollection or not anchorFrame then return nil end
    local record = { id = timerID, priority = priority or 2, timer = { id = timerID } }
    activeBars[timerID] = record
    table.insert(barList, record)
    _sortDirty = true
    return record
end

local function ReleaseBar(timerID)
    local record = activeBars[timerID]
    if not record then return end
    testTimers[timerID] = nil
    externalTimers[timerID] = nil
    activeBars[timerID] = nil
    for i, entry in ipairs(barList) do
        if entry == record then
            table.remove(barList, i); break
        end
    end
    if runtimeCollection then runtimeCollection:ReleaseItem(timerID) end
    _sortDirty = true
end

-- =============================================================
-- 排列
-- =============================================================
local _sortBuf = {}
-- TimerBar 的整体语义锚点只在此处声明。运行时 AnchorController 与设置页
-- AnchorGroup 必须消费同一次 CreateStandardModuleAnchor 返回的合同，不能再各自
-- 复制 DB key、默认位置或 frame picker 映射。
local ANCHOR_SCHEMA = {
    moduleKey = MODULE_KEY,
    frameName = "ExBoss_TimerBarAnchor",
    title = L["计时条"],
    getDB = DB,
    offsetXKey = "anchorX",
    offsetYKey = "anchorY",
    defaultOffsetX = DEFAULT_ANCHOR_X,
    defaultOffsetY = DEFAULT_ANCHOR_Y,
    syncWidgets = {
        "anchorX",
        "anchorY",
        "attachToCustom",
        "customAttachTarget",
    },
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    widgetRanges = {
        anchorX = { min = -1000, max = 1000, step = 1 },
        anchorY = { min = -600, max = 600, step = 1 },
    },
    initialWidth = DEFAULT_STYLE.width,
    initialHeight = 20,
    clampedToScreen = false,
    frameStrata = "DIALOG",
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    -- 保存的位置就是首个计时条本体的语义原点；新增/移除后续条时，
    -- collection 只能向设置的方向增长，绝不能为了包络重新移动这个原点。
    getAppliedOffsets = function(_, _, offsetX, offsetY)
        return offsetX, offsetY
    end,
    normalizeSavedOffsets = function(_, _, offsetX, offsetY)
        return offsetX, offsetY
    end,
    onCreateFrame = function(_, owner)
        owner:Show()
    end,
}
local anchorGroupOptions = nil

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController, anchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)

    return anchorController
end

function TimerBar:GetStandardAnchorGroupOptions()
    EnsureAnchorController()
    return anchorGroupOptions
end

local function ApplyAnchorPosition(count)
    if not anchorFrame then return end
    EnsureAnchorController():ApplyPosition()
end

UpdateAnchorFrameSize = function()
    if not anchorFrame then return end
    if anchorFrame.__ExwindStandardWorldPreview == true then return end
    local db = DB() or {}
    local style = ResolveStyle(db)
    local width = SafeNum(style.width, DEFAULT_STYLE.width)
    if width < 80 then width = 80 end
    local height = math.max(20, SafeNum(style.height, DEFAULT_STYLE.height))
    -- AnchorFrame 只代表固定底座，不承载 collection 的视觉包络。
    anchorFrame:SetSize(width, height)
end

local function ReLayout(nowOverride)
    if not anchorFrame or not runtimeCollection then return end
    local cache = GetRuntimeCache()
    local now   = nowOverride or GetTime()

    wipe(_sortBuf)
    for _, record in ipairs(barList) do
        -- ReLayout owns positions only.  The missing-item guard covers timers
        -- created while world editing; existing runtime items are never fully
        -- re-applied just because their order changed.
        if not record.item and not _worldEditing then
            ApplyRecord(runtimeCollection, record, now, true)
        end
        if record.item then
            table.insert(_sortBuf, record.item)
        end
    end

    table.sort(_sortBuf, function(a, b)
        local ar = activeBars[a.id]
        local br = activeBars[b.id]
        return ((ar and ar.timer.castTime) or 0) < ((br and br.timer.castTime) or 0)
    end)

    runtimeCollection:SetItems(_sortBuf, {
        mode = "FLOW",
        direction = cache.growDir,
        allowedDirections = TIMERBAR_ALLOWED_DIRECTIONS,
        spacing = cache.spacing,
        maxVisible = cache.maxBars,
    })
    UpdateAnchorFrameSize()
    ApplyAnchorPosition()
    _sortDirty = false
end

local function RefreshRuntimePresentations(nowOverride)
    if not runtimeCollection or _worldEditing then return end
    local now = nowOverride or GetTime()
    for _, record in ipairs(barList) do
        ApplyRecord(runtimeCollection, record, now, true)
    end
    _sortDirty = true
end

-- =============================================================
-- 倒计时文字
-- =============================================================
FormatTime = function(secs)
    if secs >= 60 then
        return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
    elseif secs >= 10 then
        return string.format("%.0f", secs)
    else
        return string.format("%.1f", secs)
    end
end

-- =============================================================
-- OnUpdate 驱动
-- =============================================================
local function RuntimeTick(elapsed, nowOverride)
    local now = nowOverride or GetTime()
    if _sortDirty and not _worldEditing then
        ReLayout(now)
    end

    local toRelease = nil

    for timerID, record in pairs(activeBars) do
        local active = ExBoss.Timeline.Scheduler
            and ExBoss.Timeline.Scheduler._active
            and ExBoss.Timeline.Scheduler._active[timerID]
        if not active then
            active = testTimers[timerID]
        end
        if not active then
            active = externalTimers[timerID]
        end
        if active then
            local remaining = math.max(0, active.castTime - now)
            -- 测试时钟只保存时间字段；保留 record.timer 的名称、图标与业务标记，
            -- 再用当前 active 的时间刷新，不能在 tick 时把视觉 state 换成简化表。
            local renderTimer = record.timer or active
            renderTimer.id = timerID
            renderTimer.castTime = active.castTime or renderTimer.castTime
            renderTimer.duration = active.duration or renderTimer.duration
            renderTimer.timerBarDuration = active.timerBarDuration or renderTimer.timerBarDuration
            renderTimer.fixedAIWaitingTimelineFinish = active.fixedAIWaitingTimelineFinish == true
            record.timer = renderTimer
            if runtimeCollection and not _worldEditing then
                local priority = active.barPriority or renderTimer.barPriority or record.priority or 2
                if record.priority ~= priority then
                    record.priority = priority
                    _sortDirty = true
                end
                if RuntimeStaticStateChanged(record) then
                    ApplyRecord(runtimeCollection, record, now, true)
                    _sortDirty = true
                elseif UpdateRuntimeDuration(runtimeCollection, record, now) then
                    _sortDirty = true
                end
                ApplyRuntimeAlpha(record, now)
            end
            if remaining <= 0 and (testTimers[timerID] or externalTimers[timerID]) then
                if not toRelease then toRelease = {} end
                table.insert(toRelease, timerID)
            end
        else
            if not toRelease then toRelease = {} end
            table.insert(toRelease, timerID)
        end
    end

    if toRelease then
        for _, id in ipairs(toRelease) do ReleaseBar(id) end
    end
    if _sortDirty and not _worldEditing then
        ReLayout(now)
    end
end

local _updateFrame = CreateFrame("Frame")
_updateFrame:Hide()
ExwindTools.UI:RequireLegacyRuntimeTickOwner(MODULE_KEY, "ExBoss.TimerBar runtime OnUpdate")
_updateFrame:SetScript("OnUpdate", function(_, elapsed)
    RuntimeTick(elapsed)
end)
TimerBar._updateFrame = _updateFrame

-- =============================================================
-- 测试计时条构造
-- =============================================================
local function CreateTestBars(count)
    if not anchorFrame then CreateAnchor() end

    count = math.max(1, math.min(tonumber(count) or 5, 12))
    local now = GetTime()
    for i = 1, count do
        _testSeed           = _testSeed + 1
        local timerID       = TEST_PREFIX .. tostring(_testSeed)
        local remaining     = 3 + i * 3
        local duration      = math.max(remaining + 6, 12)
        local prio          = ((i - 1) % 3) + 1

        testTimers[timerID] = {
            castTime = now + remaining,
            duration = duration,
        }

        TimerBar:AddTimer({
            id          = timerID,
            barPriority = prio,
            castTime    = now + remaining,
            duration    = duration,
            displayName = IsNonChineseLocale() and ("Test Spell " .. i) or (L["测试技能 "] .. i),
            spellID     = 136197,
            iconFlags   = (i % 3 == 1 and 128) or (i % 3 == 2 and 256) or 1,
        })

        local record = activeBars[timerID]
        if record then
            record.isTest = true
        end
    end
    _sortDirty = true
end

local function ClearTestBars()
    local toRelease = {}
    for timerID in pairs(testTimers) do
        table.insert(toRelease, timerID)
    end
    for _, timerID in ipairs(toRelease) do
        testTimers[timerID] = nil
        ReleaseBar(timerID)
    end
end

-- =============================================================
-- 锚点创建
-- =============================================================
CreateAnchor = function()
    if anchorFrame then return end
    local db    = DB()
    local style = ResolveStyle(db)
    local w     = SafeNum(style.width, DEFAULT_STYLE.width)
    if w < 80 then w = 80 end

    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(w, 20)
    anchorFrame:Show()
    runtimeCollection = ExwindTools.UI:CreateTimerBarCollection(anchorFrame, "runtime", MODULE_KEY)
    UpdateAnchorFrameSize()
    ApplyAnchorPosition()

    _updateFrame:SetParent(anchorFrame)
    SetClickThrough(_updateFrame)
    _updateFrame:Show()
end

-- =============================================================
-- Dispatcher 回调接口
-- =============================================================
function TimerBar:AddTimer(timer)
    if not anchorFrame then CreateAnchor() end
    if activeBars[timer.id] then return end

    local record = AcquireBar(timer.id, timer.barPriority)
    if not record then return end
    record.timer = timer
    record.priority = timer.barPriority or 2
    if not _worldEditing then ApplyRecord(runtimeCollection, record, GetTime(), true) end
    _sortDirty = true
end

function TimerBar:RefreshTimer(timer)
    if type(timer) ~= "table" then
        return
    end
    local record = activeBars[timer.id]
    if not record then
        return
    end
    record.timer = timer
    record.priority = timer.barPriority or record.priority or 2
    if not _worldEditing then ApplyRecord(runtimeCollection, record, GetTime(), true) end
    _sortDirty = true
end

function TimerBar:OnPreAlert(timer)
    -- TODO: 进度条脉冲动画
end

function TimerBar:OnCast(timer)
    ReleaseBar(timer.id)
end

-- 副本通用机制的独立倒数入口：不接入 Scheduler，因此不会触发普通时间轴回调。
-- 相同 id 再次调用即原地重置倒数与显示内容。
function TimerBar:StartExternalTimer(timer)
    if type(timer) ~= "table" or timer.id == nil then
        return false
    end
    local policy = ExBoss and ExBoss.DisplayPolicy
    if policy and type(policy.ShouldShowTimerOnBar) == "function"
        and policy.ShouldShowTimerOnBar(timer, "timer") ~= true then
        self:StopExternalTimer(timer.id)
        return false
    end
    externalTimers[timer.id] = timer
    if activeBars[timer.id] then
        self:RefreshTimer(timer)
    else
        self:AddTimer(timer)
    end
    return true
end

function TimerBar:StopExternalTimer(timerID)
    externalTimers[timerID] = nil
    ReleaseBar(timerID)
end

function TimerBar:ReleaseAll()
    ClearTestBars()
    for timerID in pairs(activeBars) do
        ReleaseBar(timerID)
    end
end

-- =============================================================
-- 样本渲染（世界编辑 / 设置页预览）
-- =============================================================
local function GetPreviewLayout(sampleCount)
    local layout = (DB() or {}).layout or {}
    return {
        mode = "FLOW",
        -- A legacy CENTER_VERTICAL value must not retain its old centered
        -- semantics. TimerBar always keeps the first bar as its fixed origin.
        direction = tostring(layout.direction or "UP"):upper() == "DOWN" and "DOWN" or "UP",
        allowedDirections = TIMERBAR_ALLOWED_DIRECTIONS,
        spacing = layout.spacing,
        maxVisible = math.max(PANEL_PREVIEW_MIN_SAMPLES,
            math.min(PANEL_PREVIEW_MAX_SAMPLES, math.floor(tonumber(layout.maxVisible) or PANEL_PREVIEW_MAX_SAMPLES))),
    }
end

local function GetPanelPreviewMinimumHeight()
    local style = ResolveStyle(DB() or {})
    local itemHeight = math.max(8, SafeNum(style.height, DEFAULT_STYLE.height))
    local spacing = math.max(0, SafeNum(((DB() or {}).layout or {}).spacing, 1))
    local required = itemHeight * PANEL_PREVIEW_MIN_SAMPLES
        + spacing * (PANEL_PREVIEW_MIN_SAMPLES - 1)
        + PANEL_PREVIEW_PADDING
    return math.max(PANEL_PREVIEW_ABSOLUTE_MIN_HEIGHT, required)
end

local function UpdatePanelPreviewDockHeight()
    if not (panelPreview and panelDock) then return end
    local _, boundsHeight = panelPreview:GetBounds()
    panelDock:SetHeight(math.max(GetPanelPreviewMinimumHeight(), (boundsHeight or 0) + PANEL_PREVIEW_PADDING))
end

local function BuildSampleRecords()
    local records, samples = {}, BuildPreviewSamples()
    -- Panel/world 在初次物化时固定保留全部合法样本槽；maxVisible 仅由当前
    -- layout 决定可见范围，因而 Slider 的 changing/committed 都能原位重套。
    local requested = PANEL_PREVIEW_MAX_SAMPLES
    for index = 1, requested do
        local source = samples[((index - 1) % #samples) + 1]
        records[#records + 1] = {
            id = "timerbar-sample:" .. index,
            priority = index,
            timer = {
                id = "timerbar-sample:" .. index,
                spellID = source.spellID,
                iconFileID = source.iconID,
                duration = source.duration,
                castTime = GetTime() + source.remaining,
                iconFlags = source.iconFlags,
                displayName = source.name,
            },
        }
    end
    return records
end

local function RenderSampleCollection(collection)
    if not collection then return end
    local records, items = BuildSampleRecords(), {}
    for _, record in ipairs(records) do
        ApplyRecord(collection, record, GetTime())
        items[#items + 1] = record.item
    end
    collection:SetItems(items, GetPreviewLayout(#records))
end

-- 设置页只能通过 Core 的 TimerBarPanelPreview 会话物化样本。模块仍只负责
-- BuildTimerBarPresentation；它不再自己 Acquire/Apply/SetItems panel tree。
local function BuildTimerBarPanelPresentation(_, mode)
    if mode ~= "panel" then
        error("TimerBar panel surface only accepts panel mode", 2)
    end
    local records, entries = BuildSampleRecords(), {}
    for _, record in ipairs(records) do
        entries[#entries + 1] = {
            itemID = record.id,
            presentation = BuildTimerBarPresentation(record.timer, record.priority, GetTime()),
        }
    end
    return {
        entries = entries,
        layout = GetPreviewLayout(#records),
    }
end

local function RenderPanelPreview()
    if not panelSurface or not panelDock then return end
    panelPreview = panelSurface:Render({
        dock = panelDock,
        ruleKey = MODULE_KEY,
        state = true,
    })
end

-- =============================================================
-- 世界编辑、面板预览与测试计时条接口
-- =============================================================
function TimerBar:RenderWorld(host)
    if not host then return end
    CreateAnchor()
    _worldEditing = true
    for _, record in ipairs(barList) do
        if record.item and record.item.root then record.item.root:Hide() end
    end
    if worldCollection then worldCollection:Release() end
    -- 世界编辑只开放 AnchorController 的整体拖动；局部文字/额外子元素的
    -- intent 只属于 GUI 面板预览。这里仍是同一可见 renderer，只关闭无视觉 hitbox。
    worldCollection = ExwindTools.UI:CreateTimerBarCollection(host, "world", MODULE_KEY)
    RenderSampleCollection(worldCollection)
end

function TimerBar:GetWorldBounds()
    return worldCollection and worldCollection:GetWorldBounds() or nil
end

function TimerBar:ReleaseWorld()
    if worldCollection then
        worldCollection:Release()
        worldCollection = nil
    end
    _worldEditing = false
    RefreshRuntimePresentations()
    ReLayout()
end

function TimerBar:ShowPanelPreview(dock)
    if not dock then return end
    if not panelSurface then
        error("TimerBar standard panel surface is not initialized", 2)
    end
    panelDock = dock
    -- StandardModulePage 的通用初始高度不能替代模块声明的内容下限；先给 Dock
    -- 足够空间，再物化 Collection，防止首帧被 1px 裁切。
    dock:SetHeight(GetPanelPreviewMinimumHeight())
    RenderPanelPreview()
    UpdatePanelPreviewDockHeight()
end

function TimerBar:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelDock = nil
end

function TimerBar:RefreshVisuals(options)
    -- 仅供运行时业务调用的完整刷新入口；GUI Slider 只走唯一
    -- RefreshActiveSurfaces，绝不从这里重建 Panel。
    local rebuildPanelPreview = options == nil or options.rebuildPanelPreview == true
    InvalidateRuntimeCache()
    if _worldEditing then
        RenderSampleCollection(worldCollection)
        -- Collection 的本体数量/方向变化后，重新按相同本体 bounds 包住覆盖层；
        -- 只刷新 Core overlay，不改变条体或保存锚点。
        if ExwindTools.UI and type(ExwindTools.UI.SetEditModeOverlayVisible) == "function"
            and ExwindTools.UI.EditModeState then
            ExwindTools.UI:SetEditModeOverlayVisible(ExwindTools.UI.EditModeState.overlayVisible)
        end
    else
        RefreshRuntimePresentations()
        ReLayout()
    end
    if rebuildPanelPreview then
        RenderPanelPreview()
    end
    UpdateAnchorFrameSize()
    ApplyAnchorPosition()
end

function TimerBar:CreateTestBars(count)
    CreateTestBars(count)
end

function TimerBar:ClearTestBars()
    ClearTestBars()
end

-- 只物化 runtime Collection 的完整 Item 树，不建立 timer record，也不进入
-- activeBars/barList。协调器会同时持有全部预热对象，最后再统一归还底层池。
function TimerBar:GetPrewarmTargetCount()
    local db = DB()
    if db and db.enabled == false then return 0 end
    return GetRuntimeCache().maxBars
end

function TimerBar:AcquirePrewarmObject()
    if not anchorFrame then CreateAnchor() end
    if not runtimeCollection then return nil end
    _prewarmSerial = _prewarmSerial + 1
    local itemID = PREWARM_PREFIX .. tostring(_prewarmSerial)
    local item = runtimeCollection:AcquireItem(itemID)
    if item and item.root then item.root:Hide() end
    return {
        collection = runtimeCollection,
        itemID = itemID,
        item = item,
    }
end

function TimerBar:ReleasePrewarmObject(handle)
    local collection = type(handle) == "table" and handle.collection or nil
    local itemID = type(handle) == "table" and handle.itemID or nil
    if collection and itemID and collection.released ~= true then
        collection:ReleaseItem(itemID)
    end
end

-- =============================================================
-- 初始化
-- =============================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        CreateAnchor()
    end)
end)

function TimerBar:OnRuntimeTick(elapsed, now)
    RuntimeTick(elapsed, now)
end

TimerBar._active = activeBars

-- TimerBar 是本轮唯一接入新版编辑模式的模块。名称直接解析 L[]；模块只传元数据、
-- anchor、唯一纯预览函数与设置页 preview intent 的业务回写。
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "timerbar",
    name = L["计时条"],
    settingsPage = "timerbar",
    appearanceProfile = "basicTimerBar",
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor = function()
        CreateAnchor()
        return anchorFrame
    end,
    RenderWorld = function(host)
        return TimerBar:RenderWorld(host)
    end,
    ReleaseWorld = function()
        return TimerBar:ReleaseWorld()
    end,
    GetWorldBounds = function()
        return TimerBar:GetWorldBounds()
    end,
})

local STANDARD_CONFIG_BINDING = ExwindTools.UI:RegisterStandardConfigBinding({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    reapplyExisting = function(changedPath, phase)
        -- Runtime's normal business re-layout reads this cache.  Clear it at
        -- the same time as the in-place Slider projection so a later timer
        -- update cannot restore the previous spacing/maxVisible/direction.
        InvalidateRuntimeCache()
        local function replace(target, source)
            if not source then return end
            for key in pairs(target) do target[key] = nil end
            for key, value in pairs(source) do target[key] = value end
        end
        local function reapply(surface, resolver, layout, options)
            if surface and type(surface.ReapplyPanelPresentation) == "function" then
                surface:ReapplyPanelPresentation()
            elseif surface and type(surface.ReapplyCurrentItems) == "function" then
                surface:ReapplyCurrentItems(function(presentation, item)
                    replace(presentation, resolver and resolver(item and item.id))
                end, options)
            end
            if options and options.reapplyLayout == false then return end
            if surface and type(surface.ReapplyCurrentLayout) == "function" then
                surface:ReapplyCurrentLayout(layout)
            end
        end
        local sampleRecords = BuildSampleRecords()
        local samples = {}
        for _, record in ipairs(sampleRecords) do samples[record.id] = record end
        local runtime = {}
        for _, record in ipairs(barList) do runtime[record.id] = record end
        local function samplePresentation(id)
            local record = samples[id]
            return record and BuildTimerBarPresentation(record.timer, record.priority, GetTime()) or nil
        end
        local function runtimePresentation(id)
            local record = runtime[id]
            return record and BuildTimerBarPresentation(record.timer, record.priority, GetTime()) or nil
        end
        local layout = GetPreviewLayout(#sampleRecords)
        -- Slider 的 changing 与 committed 都只重套已物化项和布局；三宿主不得
        -- 因配置写回而重新 Render、Acquire、Release 或重建页面。
        reapply(panelPreview, samplePresentation, layout)
        UpdatePanelPreviewDockHeight()
        reapply(worldCollection, samplePresentation, layout)
        reapply(runtimeCollection, runtimePresentation, layout)
    end,
})

local function RefreshActiveSurfaces(_, changedPath, phase)
    return STANDARD_CONFIG_BINDING.reapplyExisting(changedPath, phase)
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 标准 surface 只在这里创建一次；它只复用/释放 Core 的正式 panel session，
-- 不建立 TimerBar 私有预览树。切 Dock 时由 surface 自动先释放旧 hitbox。
panelSurface = ExwindTools.UI:CreateStandardPreviewSurface({
    moduleKey = MODULE_KEY,
    kind = "timerbar",
    -- The first item remains the World/Runtime semantic root.  Panel only
    -- centres the completed group inside its viewport, never outside the dock.
    buildPresentation = BuildTimerBarPanelPresentation,
    interactionSchema = INTERACTION_SCHEMA,
    requiredPositionGuiKeys = { "font_spell", "font_timer", "extraTexture" },
})
