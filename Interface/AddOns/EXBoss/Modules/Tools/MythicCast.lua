---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- [[ EXBoss Tools: MythicCast ]]
-- =============================================================
local ondev0808 = false
if ondev0808 then
    return
end


local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local ExBoss = _G.ExBoss
if not ExBoss then return end
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExBoss.Tools.MythicCast"
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.MythicCast = ExBoss.UI.MythicCast or {}
local Module = ExBoss.UI.MythicCast
local LSM = LibStub("LibSharedMedia-3.0") -- 假定 ExwindTools 环境中有 LSM
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end
local EXWIND_PLAYER_TARGET_ATLAS = "icons_64x64_deadly"

-- ------------------------------------------------------------
-- 常量定义
-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- 本地变量
-- ------------------------------------------------------------
local activeBars                = {}
local usedBarsList              = {}
local runtimeCollection         = nil
local worldCollection           = nil
local panelCollection           = nil
local panelPreview              = nil
local panelSurface              = nil
local panelDock                 = nil
local worldEditing              = false
local anchorFrame               = nil
local anchorController          = nil
local GUIPage                   = nil
local STANDARD_CONFIG_BINDING    = nil
local UpdateCast
local RefreshAll
local ReLayout
local CreateAnchor
local StartFramePicker
local ReleaseBar
local ReleaseActiveBarForUnit
local MYTHIC_PREVIEW_BAR_COUNT  = 6

-- 常用 API 引用
local CreateFrame               = _G.CreateFrame
local UIParent                  = _G.UIParent
local C_ClassColor              = _G.C_ClassColor
local string                    = _G.string
local type                      = _G.type
local pairs                     = _G.pairs
local math                      = _G.math
local table                     = _G.table

local ipairs                    = _G.ipairs
local UnitExists                = _G.UnitExists
local UnitAffectingCombat       = _G.UnitAffectingCombat
local UnitCastingInfo           = _G.UnitCastingInfo
local UnitChannelInfo           = _G.UnitChannelInfo
local UnitCastingDuration       = _G.UnitCastingDuration
local UnitChannelDuration       = _G.UnitChannelDuration
local PlayerIsSpellTarget       = _G.PlayerIsSpellTarget
local GetRaidTargetIndex        = _G.GetRaidTargetIndex
local UnitSpellTargetName       = _G.UnitSpellTargetName
local UnitLevel                 = _G.UnitLevel
local CreateColor               = _G.CreateColor
local C_Timer                   = _G.C_Timer
local IsInInstance              = _G.IsInInstance

local pendingCastUpdates        = {}
local castUpdateGeneration      = 0

-- ------------------------------------------------------------
-- 1. Grid 布局定义
-- ------------------------------------------------------------
-- 所有设置控件均由下方封装组布局生成。

-- 唯一可编辑默认值真源。Grid 导出的 EX_DEFAULTS 可直接覆盖本表；
-- 禁止把页面视觉分组误写成 ModuleDB 的嵌套路径。
local EX_DEFAULTS               = {
    anchor = {
        attachToCustom = false,
        customAttachTarget = "",
        posX = 532,
        posY = 240,
    },
    font_spell = {
        a = 1,
        autoWidth = false,
        b = 1,
        drawLayer = "OVERLAY",
        drawSubLevel = 0,
        enabled = true,
        fixedWidth = 200,
        font = "默认",
        g = 1,
        gradientEnabled = false,
        gradientLength = 0,
        gradientStart = 0,
        justifyH = "LEFT",
        justifyV = "MIDDLE",
        maxWidth = 0,
        outline = "OUTLINE",
        r = 1,
        rotation = 0,
        shadow = false,
        shadowColorA = 1,
        shadowColorB = 0,
        shadowColorG = 0,
        shadowColorR = 0,
        shadowX = 1,
        shadowY = -1,
        size = 16,
        x = 3,
        y = -0.20070117660737,
    },
    font_target = {
        a = 1,
        autoWidth = false,
        b = 0.40392160415649,
        drawLayer = "OVERLAY",
        drawSubLevel = 0,
        enabled = true,
        fixedWidth = 200,
        font = "默认",
        g = 0.80000007152557,
        gradientEnabled = false,
        gradientLength = 0,
        gradientStart = 0,
        justifyH = "RIGHT",
        justifyV = "MIDDLE",
        maxWidth = 0,
        outline = "OUTLINE",
        r = 0.27058824896812,
        rotation = 0,
        shadow = false,
        shadowColorA = 1,
        shadowColorB = 0,
        shadowColorG = 0,
        shadowColorR = 0,
        shadowX = 1,
        shadowY = -1,
        size = 16,
        x = -2,
        y = -2.3983239546824,
    },
    font_timer = {
        a = 1,
        autoWidth = false,
        b = 1,
        drawLayer = "OVERLAY",
        drawSubLevel = 0,
        enabled = true,
        fixedWidth = 200,
        font = "默认",
        g = 1,
        gradientEnabled = false,
        gradientLength = 0,
        gradientStart = 0,
        justifyH = "LEFT",
        justifyV = "MIDDLE",
        maxWidth = 0,
        outline = "OUTLINE",
        r = 1,
        rotation = 0,
        shadow = false,
        shadowColorA = 1,
        shadowColorB = 0,
        shadowColorG = 0,
        shadowColorR = 0,
        shadowX = 9,
        shadowY = -1,
        size = 17,
        x = 202.73690890251,
        y = 0,
    },
    layout = {
        direction = "UP",
        maxVisible = 6,
        spacing = 1,
    },
    moduleCommon = {
        disabledBossEncounterIDs = "",
        enabled = true,
        hideLevel91Casts = false,
        hideLevel92Casts = false,
        locked = true,
        nonInterruptColorA = 1,
        nonInterruptColorB = 0.16862745583057,
        nonInterruptColorG = 0.1294117718935,
        nonInterruptColorR = 1,
        spacing = 1,
    },
    elements = {
        raidMarker = {
            texture = { enabled = true, x = 0, y = 0, width = 25, height = 25 },
        },
        playerTargetIndicator = {
            texture = {
                enabled = true, x = -150, y = 1, width = 25, height = 25,
                atlas = "icons_64x64_enrage",
            },
        },
    },
    timerGroup = {
        barBgColorA = 0.71539187431335,
        barBgColorB = 0.27843138575554,
        barBgColorG = 0.27843138575554,
        barBgColorR = 0.27843138575554,
        barColorA = 1,
        barColorB = 1,
        barColorG = 0.90980398654938,
        barColorR = 0.29019609093666,
        borderColorA = 1,
        borderColorB = 0,
        borderColorG = 0,
        borderColorR = 0,
        borderPadding = 1.1000003814697,
        borderSize = 1,
        borderTexture = "EX_WhiteBorder",
        fillDirection = "LEFT_TO_RIGHT",
        height = 25,
        iconBorderColorA = 1,
        iconBorderColorB = 0,
        iconBorderColorG = 0,
        iconBorderColorR = 0,
        iconBorderPadding = 0.10000038146973,
        iconBorderSize = 0.5,
        iconBorderTexture = "EX_WhiteBorder",
        iconHeight = 25,
        iconOffsetX = -1,
        iconOffsetY = 0,
        iconSide = "LEFT",
        iconWidth = 25,
        progressMode = "REMAINING",
        showBorder = true,
        showIcon = true,
        showIconBorder = true,
        texture = "EX_WhiteTexture",
        width = 200,
    },
}

local FONT_FIELDS               = { "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
    "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA",
    "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart", "gradientLength", "drawLayer", "drawSubLevel",
    "x", "y" }
local TIMER_FIELDS              = { "width", "height", "texture", "barColorR", "barColorG", "barColorB", "barColorA",
    "barBgColorR", "barBgColorG", "barBgColorB", "barBgColorA", "showBorder", "borderTexture", "borderColorR",
    "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding", "showIcon", "iconSide",
    "iconWidth", "iconHeight", "iconOffsetX", "iconOffsetY", "showIconBorder", "iconBorderTexture", "iconBorderColorR",
    "iconBorderColorG", "iconBorderColorB", "iconBorderColorA", "iconBorderSize", "iconBorderPadding", "fillDirection",
    "progressMode" }
local DEFAULT_SCHEMA            = {
    { group = "font_spell",  fields = FONT_FIELDS },
    { group = "font_target", fields = FONT_FIELDS },
    { group = "font_timer",  fields = FONT_FIELDS },
    { group = "anchor",      root = true,                                                                    fields = { "posX", "posY", "attachToCustom", "customAttachTarget" } },
    { group = "layout",      fields = { "direction", "maxVisible", "spacing" } },
    {
        group = "moduleCommon",
        root = true,
        fields = {
            "enabled", "disabledBossEncounterIDs", "hideLevel91Casts", "hideLevel92Casts", "locked",
            "nonInterruptColorA", "nonInterruptColorB", "nonInterruptColorG", "nonInterruptColorR", "spacing",
        }
    },
    { group = "timerGroup", fields = TIMER_FIELDS },
    {
        group = "elements",
        fields = {
            raidMarker = { texture = { "enabled", "x", "y", "width", "height" } },
            playerTargetIndicator = { texture = { "enabled", "x", "y", "width", "height", "atlas" } },
        },
    },
}

-- DEFAULTS 只是 EX_DEFAULTS 的一次编译视图，供运行时缺省值读取；不是第二份默认表。
local DEFAULTS                  = ExwindTools:DeclareModuleDefaults(EXWIND_MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

local function GetDB()
    return ExwindTools:GetModuleDB(EXWIND_MODULE_KEY)
end

local EX_DB = GetDB()
local disabledBossEncounterRaw = nil
local disabledBossEncounterSet = nil

-- 模块通用卡只包含模块本身的通用业务开关；两个额外材质各自有独立卡片。
local COMMON_FIELDS = {
    { path = "enabled", type = "checkbox", label = L["启用"] },
    { path = "hideLevel91Casts", type = "checkbox", label = L["隐藏 91 级读条"] },
    { path = "hideLevel92Casts", type = "checkbox", label = L["隐藏 92 级读条"] },
    { path = "disabledBossEncounterIDs", type = "input", label = L["首领战禁用 ID"] },
    { path = "nonInterruptColor", type = "color", label = L["不可打断颜色"] },
}

local COMMON_POOL_TYPE = "MythicCastModuleCommonSettingsGroup"
local COMMON_OPTS = {
    bindRoot = true,
    poolType = COMMON_POOL_TYPE,
    columns = 4,
    fields = COMMON_FIELDS,
}
-- 两张额外子元素卡必须复用 TimerBar 的标准控件树；Mythic 仅声明已有 DB 字段
-- 与业务范围。标准 Slider 生命周期会在 Render 后统一接管所有 Slider 输入路径。
local RAID_MARKER_EXTRA_OPTS = ExwindTools:BuildStandardTimerBarAlertIconsGroupOptions({
    timerBarKey = "timerGroup",
}, {
    paths = {
        show = "elements.raidMarker.texture.enabled",
        width = "elements.raidMarker.texture.width",
        height = "elements.raidMarker.texture.height",
        x = "elements.raidMarker.texture.x",
        y = "elements.raidMarker.texture.y",
    },
    ranges = {
        width = { min = 10, max = 64, step = 1 }, height = { min = 10, max = 64, step = 1 },
        x = { min = -1000, max = 1000, step = 1 }, y = { min = -1000, max = 1000, step = 1 },
    },
})
local PLAYER_TARGET_INDICATOR_EXTRA_OPTS = ExwindTools:BuildStandardTimerBarAlertIconsGroupOptions({
    timerBarKey = "timerGroup",
}, {
    paths = {
        show = "elements.playerTargetIndicator.texture.enabled",
        width = "elements.playerTargetIndicator.texture.width",
        height = "elements.playerTargetIndicator.texture.height",
        x = "elements.playerTargetIndicator.texture.x",
        y = "elements.playerTargetIndicator.texture.y",
    },
    ranges = {
        width = { min = 8, max = 64, step = 1 }, height = { min = 8, max = 64, step = 1 },
        x = { min = -1000, max = 1000, step = 1 }, y = { min = -1000, max = 1000, step = 1 },
    },
})
-- 整体位置只有这个标准 Anchor 声明：运行时 AnchorController 和 Grid 的
-- anchorgroup 必须使用同一次 CreateStandardModuleAnchor 的返回合同，不能各自
-- 复制 posX/posY 或 frame picker。
local ANCHOR_SCHEMA = {
    moduleKey = EXWIND_MODULE_KEY,
    frameName = "ExBossMythicCastAnchor",
    title = L["大米怪物施法"],
    getDB = function() return EX_DB end,
    offsetXKey = "posX",
    offsetYKey = "posY",
    defaultOffsetX = DEFAULTS.posX,
    defaultOffsetY = DEFAULTS.posY,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    restoreKeys = { "locked" },
    syncWidgets = { "posX", "posY", "attachToCustom", "customAttachTarget" },
    widgetRanges = {
        posX = { min = -1000, max = 1000, step = 1 },
        posY = { min = -1000, max = 1000, step = 1 },
    },
    initialWidth = 200,
    initialHeight = 20,
    clampedToScreen = true,
    -- Direction only changes later offsets; item #1 never changes anchor.
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
}
-- CreateStandardModuleAnchor 只创建 controller 声明，不创建 Frame；因此可在 Grid
-- export/layout 前建立同一份 AnchorGroup opts，仍由 CreateAnchor 延迟 Ensure 实体。
anchorController, ANCHOR_OPTS = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)
local LAYOUT_OPTS = {
    allowedDirections = { "UP", "DOWN" },
    includeMaxPerRow = false,
    maxVisibleMin = 1,
    maxVisibleMax = 6,
    defaultMaxVisible =
        EX_DEFAULTS.layout.maxVisible
}
local FONT_OPTS = { offsetMin = -1000, offsetMax = 1000, shadowOffsetMin = -1000, shadowOffsetMax = 1000 }
local TIMER_BAR_OPTS = { iconOffsetMin = -1000, iconOffsetMax = 1000 }
local GridExporter = ExwindTools.Grid
if GridExporter and GridExporter.RegisterExportReference then
    GridExporter:RegisterExportReference(COMMON_OPTS, "COMMON_OPTS")
    GridExporter:RegisterExportReference(RAID_MARKER_EXTRA_OPTS, "RAID_MARKER_EXTRA_OPTS")
    GridExporter:RegisterExportReference(PLAYER_TARGET_INDICATOR_EXTRA_OPTS, "PLAYER_TARGET_INDICATOR_EXTRA_OPTS")
    GridExporter:RegisterExportReference(ANCHOR_OPTS, "ANCHOR_OPTS")
    GridExporter:RegisterExportReference(LAYOUT_OPTS, "LAYOUT_OPTS")
    GridExporter:RegisterExportReference(FONT_OPTS, "FONT_OPTS")
    GridExporter:RegisterExportReference(TIMER_BAR_OPTS, "TIMER_BAR_OPTS")
end

local EX_LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["大米怪物施法"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 30, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "raidMarkerExtra", type = "modulecommonsettings", x = 1, y = 42, w = 200, h = 50, label = L["额外子元素－团队标记"], opts = RAID_MARKER_EXTRA_OPTS },
    { key = "playerTargetIndicatorExtra", type = "modulecommonsettings", x = 1, y = 94, w = 200, h = 50, label = L["额外子元素－玩家目标提示"], opts = PLAYER_TARGET_INDICATOR_EXTRA_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 146, w = 200, h = 20, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "layout", type = "widgetlayout", x = 1, y = 168, w = 200, h = 23, measure = true, label = L["排列设置"], opts = LAYOUT_OPTS },
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 193, w = 200, h = 52, label = L["计时条外观"], opts = TIMER_BAR_OPTS },
    { key = "font_spell", type = "fontgroup", x = 1, y = 248, w = 200, h = 50, label = L["法术名称"], opts = {
        offsetMin = FONT_OPTS.offsetMin, offsetMax = FONT_OPTS.offsetMax,
        shadowOffsetMin = FONT_OPTS.shadowOffsetMin, shadowOffsetMax = FONT_OPTS.shadowOffsetMax,
    } },
    { key = "font_target", type = "fontgroup", x = 1, y = 300, w = 200, h = 50, label = L["施法目标"], opts = {
        offsetMin = FONT_OPTS.offsetMin, offsetMax = FONT_OPTS.offsetMax,
        shadowOffsetMin = FONT_OPTS.shadowOffsetMin, shadowOffsetMax = FONT_OPTS.shadowOffsetMax,
    } },
    { key = "font_timer", type = "fontgroup", x = 1, y = 352, w = 200, h = 50, label = L["时间文字"], opts = {
        offsetMin = FONT_OPTS.offsetMin, offsetMax = FONT_OPTS.offsetMax,
        shadowOffsetMin = FONT_OPTS.shadowOffsetMin, shadowOffsetMax = FONT_OPTS.shadowOffsetMax,
    } },
}


ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)

local function GetLayoutDB()
    return EX_DB.layout or EX_DEFAULTS.layout
end

local function EnsureAnchorController()
    return anchorController
end

local function GetColor(dbKey)
    local r, g, b, a = EX_DB[dbKey .. "R"], EX_DB[dbKey .. "G"], EX_DB[dbKey .. "B"], EX_DB[dbKey .. "A"]
    if r == nil and EX_DB[dbKey] and type(EX_DB[dbKey]) == "table" then
        return EX_DB[dbKey].r, EX_DB[dbKey].g, EX_DB[dbKey].b, EX_DB[dbKey].a
    end
    return r or 1, g or 1, b or 1, a or 1
end

local function GetDisabledBossEncounterSet()
    local raw = EX_DB.disabledBossEncounterIDs
    if raw == disabledBossEncounterRaw then
        return disabledBossEncounterSet
    end

    disabledBossEncounterRaw = raw
    disabledBossEncounterSet = nil
    if type(raw) ~= "string" or raw == "" then
        return nil
    end

    local set = {}
    for token in string.gmatch(raw, "[^,;/|%s]+") do
        local encounterID = tonumber(token)
        if encounterID and encounterID > 0 then
            set[encounterID] = true
        end
    end

    if next(set) ~= nil then
        disabledBossEncounterSet = set
    end
    return disabledBossEncounterSet
end

local function IsDisabledInBossEncounter()
    if ExwindTools.State.IsBossEncounter ~= true then
        return false
    end

    local encounterID = tonumber(ExwindTools.State.EncounterID) or 0
    if encounterID <= 0 then
        return false
    end

    local disabledSet = GetDisabledBossEncounterSet()
    return type(disabledSet) == "table" and disabledSet[encounterID] == true
end

-- 标准条体只由 EXUI TimerBarWidget 承担；模块仅声明自己的三段文字语义。
-- 不使用 showTarget/showTimer 顶层开关，两个文字的显示由各自 fontgroup.enabled 控制。
local MYTHIC_TIMER_BAR_SCHEMA = {
    timerBarKey = "timerGroup",
    layoutKey = "layout",
    offsetXKey = "posX",
    offsetYKey = "posY",
    -- false 明确覆盖 StandardTimerBar 默认的 showTarget/showTimer 持久化键；
    -- 目标与时间可见性只受各自 fontgroup.enabled 控制。
    showTextBKey = false,
    showTextCKey = false,
    textA = { key = "font_spell", role = "spellName", gridKey = "font_spell" },
    textB = { key = "font_target", role = "targetName", gridKey = "font_target", optional = true },
    textC = { key = "font_timer", role = "time", gridKey = "font_timer" },
}

local function ScheduleCastUpdate(unit)
    if not C_Timer or pendingCastUpdates[unit] then return end
    local generation = castUpdateGeneration
    pendingCastUpdates[unit] = true
    C_Timer.After(0.1, function()
        if generation ~= castUpdateGeneration then return end
        pendingCastUpdates[unit] = nil
        if not EX_DB.enabled or worldEditing
            or IsDisabledInBossEncounter() or not UnitExists(unit) then
            return
        end
        if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
            return
        end
        if not UnitAffectingCombat(unit) then
            ReleaseActiveBarForUnit(unit)
            return
        end
        UpdateCast(unit)
    end)
end

local function SyncAnchorVisibility()
    if not anchorFrame then return end
    anchorFrame:SetShown(EX_DB.enabled == true or worldEditing)
end

CreateAnchor = function()
    if anchorFrame then
        SyncAnchorVisibility()
        return
    end
    anchorFrame = EnsureAnchorController():Ensure()

    SyncAnchorVisibility()
end

StartFramePicker = function()
    EnsureAnchorController():StartFramePicker()
end

-- =============================================================
-- 事件处理与状态管理
-- =============================================================

local function OnEvent(event, unit)
    -- [Fix] 严格过滤：仅监控敌对单位血条(nameplate)，排除玩家以及友方/队友单位
    if not EX_DB.enabled or IsDisabledInBossEncounter() or not unit then return end
    -- 终止事件必须在 UnitCanAttack 等动态状态过滤之前释放。读条结束时姓名板可能已
    -- 不再被判定为可攻击，若先过滤会遗留名称与条体。
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if string.match(unit, "^nameplate%d+$") then
            ReleaseActiveBarForUnit(unit)
        end
        return
    end
    if not string.match(unit, "^nameplate%d+$") or UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then
        return
    end
    -- 姓名板加入时只让已进入战斗的单位进入施法刷新链路；施法开始事件仍由
    -- ScheduleCastUpdate 的短延迟复查处理，避免进战瞬间的事件顺序漏报。
    if event == "NAME_PLATE_UNIT_ADDED" and not UnitAffectingCombat(unit) then
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        ScheduleCastUpdate(unit)
        return
    end
    UpdateCast(unit)
end

local function OnUnitRemoved(event, unit)
    pendingCastUpdates[unit] = nil
    ReleaseActiveBarForUnit(unit)
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
    for _, e in ipairs(events) do
        ExwindTools:RegisterEvent(e, EXWIND_MODULE_KEY, OnEvent)
    end
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
    for _, e in ipairs(events) do
        ExwindTools:UnregisterEvent(e, EXWIND_MODULE_KEY)
    end

    -- 彻底清理
    for unit, bar in pairs(activeBars) do
        ReleaseBar(bar)
    end
    activeBars = {}
    usedBarsList = {}
    castUpdateGeneration = castUpdateGeneration + 1
    pendingCastUpdates = {}
    ReLayout()
end

local function CheckEnvStatus()
    -- State 在模块按需加载时可能还未完成第一次刷新；原生副本类型是当前状态的
    -- 直接来源。二者任一确认是五人副本即可注册，离开副本后的 State 更新会再清理。
    local inInstance, instanceType = IsInInstance()
    local isParty = (inInstance == true and instanceType == "party")
        or (ExwindTools.State and ExwindTools.State.InstanceType == "party")
    local disabledInEncounter = IsDisabledInBossEncounter()

    if isParty and EX_DB.enabled and not disabledInEncounter then
        EnableEnvEvents()
    else
        DisableEnvEvents()
    end
end

-- 监听 InstanceType 变化 (进入/离开副本)
ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY, function(newType)
    CheckEnvStatus()
end)

ExwindTools:WatchState("IsBossEncounter", EXWIND_MODULE_KEY, function()
    CheckEnvStatus()
end)

ExwindTools:WatchState("EncounterID", EXWIND_MODULE_KEY, function()
    CheckEnvStatus()
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if info.key == "btn_reset_pos" then
        EX_DB.posX, EX_DB.posY = 0, 100
        EX_DB.attachToCustom = false
        EX_DB.customAttachTarget = ""
        EnsureAnchorController():SyncWidgets()
        if anchorFrame then
            EnsureAnchorController():ApplyPosition()
        end
        RefreshAll()
    elseif info.key == "btn_pick_frame" then
        StartFramePicker()
    end
end)

-- 模块可能在 PLAYER_ENTERING_WORLD 之后按需加载；不能只依赖该事件，否则锚点
-- 从未创建、环境事件从未注册，后续条体即使被创建也没有可见的父层。
local function InitializeMythicCastRuntime()
    CreateAnchor()
    SyncAnchorVisibility()
    RefreshAll()
    CheckEnvStatus()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    C_Timer.After(1, InitializeMythicCastRuntime)
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

-- 覆盖按需加载：回调会在本文件完成加载后执行，不重置用户当前的预览状态。
C_Timer.After(0, InitializeMythicCastRuntime)

function Module:GetModuleDB()
    return GetDB()
end

function Module:RefreshVisuals(options)
    RefreshAll(options)
end

function Module:Clear()
    DisableEnvEvents()
end

function Module:Shutdown()
    self:Clear()
    ExwindTools:UnwatchState("InstanceType", EXWIND_MODULE_KEY)
    ExwindTools:UnwatchState("IsBossEncounter", EXWIND_MODULE_KEY)
    ExwindTools:UnwatchState("EncounterID", EXWIND_MODULE_KEY)
    ExwindTools:UnwatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY)
end

local PREVIEW_SAMPLES = {
    { name = L["测试施法"] .. " 1", remaining = 2.5, icon = 136197 },
    { name = L["测试施法"] .. " 2", remaining = 4.0, icon = 136243 },
    { name = L["测试施法"] .. " 3", remaining = 6.5, icon = 136048 },
    { name = L["测试施法"] .. " 4", remaining = 8.0, icon = 136184 },
    { name = L["测试施法"] .. " 5", remaining = 10.0, icon = 136116 },
}

-- Panel/world 的静态目标统一显示当前玩家身份。只读 ExwindState 的普通身份
-- 快照，绝不读取任何真实施法目标或 Secret runtime 值。
local function GetPreviewTargetIdentity()
    local state = ExwindTools.State or {}
    local classID = tonumber(state.ClassID) or 0
    local class = EXDB and EXDB.Classes and EXDB.Classes[classID]
    local rgb = class and class.colorRGB
    local color = rgb and CreateColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255) or nil
    local name = type(state.PlayerName) == "string" and state.PlayerName or ""
    return name ~= "" and name or L["玩家"], color
end

-- =============================================================
-- 唯一 Renderer：真实、世界编辑、设置页只更换宿主与输入，不更换可见树。
-- StandardTimerBarCollection 是三文字/Secret 条体的明确 EXUI 入口；它不理解
-- Mythic 的单位、团队标记或业务判断。
-- =============================================================
local function EnsureCollection(kind, parent)
    if kind == "runtime" then
        if not runtimeCollection then
            runtimeCollection = ExwindTools.UI:CreateStandardTimerBarCollection(parent, "runtime", EXWIND_MODULE_KEY, {
                schema = MYTHIC_TIMER_BAR_SCHEMA,
            })
        end
        return runtimeCollection
    end
    if kind == "world" then
        if worldCollection then worldCollection:Release() end
        worldCollection = ExwindTools.UI:CreateStandardTimerBarCollection(parent, "world", EXWIND_MODULE_KEY, {
            schema = MYTHIC_TIMER_BAR_SCHEMA,
        })
        return worldCollection
    end
    error("MythicCast collection kind is unsupported: " .. tostring(kind), 2)
end

local RAID_MARKER_ELEMENT_ID = "elements.raidMarker"
local PLAYER_TARGET_ELEMENT_ID = "elements.playerTargetIndicator"

-- 只声明现有 presentation 的五个可交互语义槽。EXUI 统一生成 slot、处理右键
-- Focus、局部移动 DB 写回与 Grid 回读；模块不得再保留私有 intent handler。
local INTERACTION_SCHEMA = {
    ["core.spellName"] = {
        textRole = "A", movable = true, guiKey = "font_spell", tooltip = L["法术名称"],
        position = { x = "font_spell.x", y = "font_spell.y" },
    },
    ["core.targetName"] = {
        textRole = "B", movable = true, guiKey = "font_target", tooltip = L["施法目标"],
        position = { x = "font_target.x", y = "font_target.y" },
    },
    ["core.time"] = {
        textRole = "C", movable = true, guiKey = "font_timer", tooltip = L["时间文字"],
        position = { x = "font_timer.x", y = "font_timer.y" },
    },
    [RAID_MARKER_ELEMENT_ID] = {
        movable = true, guiKey = "raidMarkerExtra", tooltip = L["团队标记"],
        position = { x = "elements.raidMarker.texture.x", y = "elements.raidMarker.texture.y" },
    },
    [PLAYER_TARGET_ELEMENT_ID] = {
        movable = true, guiKey = "playerTargetIndicatorExtra", tooltip = L["玩家目标提示"],
        position = { x = "elements.playerTargetIndicator.texture.x", y = "elements.playerTargetIndicator.texture.y" },
    },
}

local function BuildMythicInteraction()
    return EXUI:BuildStandardPreviewInteraction("StandardTimerBar", EX_DB, INTERACTION_SCHEMA)
end

local function BuildMythicPresentation(record, mode)
    local group = EX_DB.timerGroup or {}
    local elements = EX_DB.elements or {}
    local raidMarkerStyle = elements.raidMarker and elements.raidMarker.texture
    local playerTargetStyle = elements.playerTargetIndicator and elements.playerTargetIndicator.texture
    -- GetRaidTargetIndex() is nil for an unmarked unit.  The native raid-marker
    -- texture API accepts an opaque index but does not accept nil, so the
    -- producer must make this ordinary presence declaration before forwarding
    -- the native value to EXCORE.
    local hasRaidTargetIndex = record.extra and record.extra.hasRaidTargetIndex == true
    local normalColor = CreateColor(group.barColorR or 1, group.barColorG or 0.7, group.barColorB or 0, group.barColorA or 1)
    local nrR, nrG, nrB, nrA = GetColor("nonInterruptColor")
    local presentation = {
        db = EX_DB,
        schema = MYTHIC_TIMER_BAR_SCHEMA,
        content = record.content,
        -- 施法由原生 Duration direction=0 左→右填满；引导 direction=1 在同一
        -- 左锚条体上右→左消退。这里不能再让旧 timerGroup.fillDirection 覆盖
        -- 该固定业务语义。
        styleOverrides = {
            timerBar = { fillDirection = "LEFT_TO_RIGHT" },
        },
        regionElements = {
            {
                id = "raidMarker",
                kind = "texture",
                stylePath = "elements.raidMarker.texture",
                style = raidMarkerStyle,
                shown = raidMarkerStyle.enabled ~= false,
                anchor = { point = "RIGHT", relativeElement = "core.root", relativePoint = "LEFT" },
                bounds = { width = raidMarkerStyle.width, height = raidMarkerStyle.height },
                content = {
                    shown = hasRaidTargetIndex,
                    hasRaidTargetIndex = hasRaidTargetIndex,
                    raidTargetIndex = record.extra and record.extra.raidTargetIndex,
                },
                interaction = { elementID = RAID_MARKER_ELEMENT_ID, guiTarget = "raidMarkerExtra", movable = true },
            },
            {
                id = "playerTargetIndicator",
                kind = "texture",
                stylePath = "elements.playerTargetIndicator.texture",
                style = playerTargetStyle,
                shown = playerTargetStyle.enabled ~= false,
                anchor = { point = "CENTER", relativeElement = "core.root", relativePoint = "CENTER" },
                bounds = { width = playerTargetStyle.width, height = playerTargetStyle.height },
                content = {
                    atlas = playerTargetStyle.atlas or EXWIND_PLAYER_TARGET_ATLAS,
                    hasShownFromBoolean = true,
                    shownFromBoolean = record.extra and record.extra.isPlayerTarget,
                },
                interaction = { elementID = PLAYER_TARGET_ELEMENT_ID, guiTarget = "playerTargetIndicatorExtra", movable = true },
            },
        },
        interaction = BuildMythicInteraction(),
    }
    if mode == "runtime" then
        presentation.fillFromBoolean = {
            value = record.notInterruptible,
            trueColor = CreateColor(nrR, nrG, nrB, nrA),
            falseColor = normalColor,
        }
        presentation.textShownFromBoolean = { B = record.shouldShowTarget }
        if record.targetColor then presentation.textColors = { B = record.targetColor } end
    else
        presentation.fillColor = normalColor
        if record.targetColor then presentation.textColors = { B = record.targetColor } end
    end
    return presentation
end

local function ApplyRecord(collection, record, mode)
    local item = collection:AcquireItem(record.id)
    record.item = item
    collection:ApplyItem(item, BuildMythicPresentation(record, mode))
    return item
end

local GetSemanticLayout
local function BuildSampleRecords()
    local records = {}
    -- Panel/World always materialize the maximum legal preview slots.  Changing
    -- maxVisible can then reveal or hide existing items through layout only;
    -- GUI refresh never needs to Acquire or Render a new sample item.
    local count = MYTHIC_PREVIEW_BAR_COUNT
    for index = 1, count do
        local sample = PREVIEW_SAMPLES[((index - 1) % #PREVIEW_SAMPLES) + 1]
        local targetName, targetColor = GetPreviewTargetIdentity()
        local record = {
            id = "mythiccast-sample:" .. index,
            content = { icon = sample.icon, textA = sample.name, textB = targetName, textC = string.format("%.1f", sample.remaining), progress = sample.remaining, maximum = 15 },
            -- 预览必须完整展示该可配置 Atlas；真实运行仍使用每单位原生 Boolean。
            extra = { hasRaidTargetIndex = true, raidTargetIndex = 8, isPlayerTarget = true },
            targetColor = targetColor,
        }
        records[#records + 1] = record
    end
    return records
end

local function RenderSampleCollection(collection)
    if not collection then return end
    local records, items = BuildSampleRecords(), {}
    for _, record in ipairs(records) do
        ApplyRecord(collection, record, collection.interactionMode)
        items[#items + 1] = record.item
    end
    collection:SetItems(items, GetSemanticLayout())
end

-- StandardPreviewSurface 只负责复用/释放同一 panel session；样本仍完全由本模块
-- 的唯一 presentation 生成，不能在页面私建第二个 Collection。
local function BuildMythicPanelPresentation(_, mode)
    if mode ~= "panel" then error("MythicCast panel surface only accepts panel mode", 2) end
    local records, entries = BuildSampleRecords(), {}
    for _, record in ipairs(records) do
        entries[#entries + 1] = {
            itemID = record.id,
            presentation = BuildMythicPresentation(record, "panel"),
        }
    end
    return { entries = entries, layout = GetSemanticLayout() }
end

local function RenderPanelPreview()
    if not panelSurface or not panelDock then return end
    panelPreview = panelSurface:Render({
        dock = panelDock,
        ruleKey = EXWIND_MODULE_KEY,
        state = true,
    })
    panelCollection = panelPreview:GetCollection()
end

GetSemanticLayout = function()
    local layout = GetLayoutDB()
    return {
        direction = tostring(layout.direction or "UP"):upper() == "UP" and "UP" or "DOWN",
        spacing = tonumber(layout.spacing) or 0,
        maxVisible = math.max(1, math.min(MYTHIC_PREVIEW_BAR_COUNT, math.floor(tonumber(layout.maxVisible) or MYTHIC_PREVIEW_BAR_COUNT))),
    }
end

ReLayout = function()
    if worldEditing then return end
    if runtimeCollection then
        local items = {}
        for _, record in ipairs(usedBarsList) do
            if record.item then items[#items + 1] = record.item end
        end
        runtimeCollection:SetItems(items, GetSemanticLayout())
    end
    EnsureAnchorController():ApplyPosition()
end

RefreshAll = function(options)
    -- 无参调用保留既有完整刷新；标准 Slider commit 明确标记只有无法直接
    -- Patch 的结构字段才重建当前 Panel Preview。
    local rebuildPanelPreview = options == nil or options.rebuildPanelPreview == true
    if worldEditing then
        if worldCollection then RenderSampleCollection(worldCollection) end
    else
        for unit in pairs(activeBars) do UpdateCast(unit) end
        ReLayout()
    end
    if rebuildPanelPreview then
        RenderPanelPreview()
    end
end

ReleaseBar = function(record)
    if record and runtimeCollection then runtimeCollection:ReleaseItem(record.id) end
end

ReleaseActiveBarForUnit = function(unit)
    local record = activeBars[unit]
    if not record then return false end
    activeBars[unit] = nil
    for index, used in ipairs(usedBarsList) do
        if used == record then table.remove(usedBarsList, index); break end
    end
    ReleaseBar(record)
    ReLayout()
    return true
end

UpdateCast = function(unit)
    if worldEditing then return end
    if IsDisabledInBossEncounter() or not UnitAffectingCombat(unit) then
        ReleaseActiveBarForUnit(unit)
        return
    end
    local unitLevel = UnitLevel(unit)
    if (EX_DB.hideLevel91Casts and unitLevel == 91) or (EX_DB.hideLevel92Casts and unitLevel == 92) then
        ReleaseActiveBarForUnit(unit)
        return
    end
    local castDuration, channelDuration = UnitCastingDuration(unit), UnitChannelDuration(unit)
    local duration = castDuration or channelDuration
    if not duration then
        ReleaseActiveBarForUnit(unit)
        return
    end

    local record = activeBars[unit]
    if not record then
        record = { id = unit, unit = unit }
        activeBars[unit] = record
        usedBarsList[#usedBarsList + 1] = record
    end
    local name, texture, notInterruptible
    if channelDuration then
        name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
    else
        name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    end
    local targetName = UnitSpellTargetName and UnitSpellTargetName(unit)
    local shouldShowTarget = UnitShouldDisplaySpellTargetName(unit)
    local targetColor = nil
    if EX_DB.font_target and EX_DB.font_target.enabled ~= false and shouldShowTarget then
        local classFilename = UnitSpellTargetClass(unit)
        targetColor = C_ClassColor.GetClassColor(classFilename)
    end
    record.content = {
        icon = texture, iconMode = "SECRET",
        textA = name, textAMode = "SECRET",
        textB = targetName, textBMode = "SECRET",
        secretDuration = duration,
        interpolation = Enum.StatusBarInterpolation.None,
        direction = channelDuration and 1 or 0,
    }
    record.notInterruptible = notInterruptible
    record.shouldShowTarget = shouldShowTarget
    record.targetColor = targetColor
    local raidTargetIndex = GetRaidTargetIndex(unit)
    record.extra = {
        hasRaidTargetIndex = raidTargetIndex ~= nil,
        raidTargetIndex = raidTargetIndex,
        isPlayerTarget = PlayerIsSpellTarget and PlayerIsSpellTarget(unit),
    }
    CreateAnchor()
    local collection = EnsureCollection("runtime", anchorFrame)
    ApplyRecord(collection, record, "runtime")
    ReLayout()
end

function Module:RenderWorld(host)
    CreateAnchor()
    worldEditing = true
    SyncAnchorVisibility()
    if runtimeCollection then runtimeCollection:SetItems({}, GetSemanticLayout()) end
    RenderSampleCollection(EnsureCollection("world", host))
end

function Module:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    SyncAnchorVisibility()
    ReLayout()
end

function Module:GetWorldBounds()
    return worldCollection and worldCollection:GetWorldBounds() or nil
end

local function ResizePanelDock()
    if not panelDock or not panelCollection then return end
    local _, height = panelCollection:GetBounds()
    panelDock:SetHeight(math.max(60, (height or 0) + 28))
end

function Module:ShowPanelPreview(dock)
    if not dock then return end
    if not panelSurface then error("MythicCast standard panel surface is not initialized", 2) end
    panelDock = dock
    RenderPanelPreview()
    ResizePanelDock()
end

function Module:RefreshPanelPreview()
    if panelPreview then
        RenderPanelPreview()
        ResizePanelDock()
    end
end

function Module:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelCollection = nil
    panelDock = nil
end

local SLIDER_GROUP_PATHS = {
    raidMarkerExtra = "",
    playerTargetIndicatorExtra = "",
    layout = "layout",
    timerGroup = "timerGroup",
    font_spell = "font_spell",
    font_target = "font_target",
    font_timer = "font_timer",
}

-- 唯一正式 config 根、预览移动与 Slider 的路径白名单。此处不缓存 DB，也不创建
-- 兼容表；reset 后 GetDB 仍返回同一模块唯一新表。
local STANDARD_SCHEMA_PATHS = {
    ["posX"] = true, ["posY"] = true,
    ["attachToCustom"] = true, ["customAttachTarget"] = true,
}
for _, path in ipairs({
    "elements.raidMarker.texture.enabled",
    "elements.raidMarker.texture.width", "elements.raidMarker.texture.height",
    "elements.raidMarker.texture.x", "elements.raidMarker.texture.y",
    "elements.playerTargetIndicator.texture.enabled",
    "elements.playerTargetIndicator.texture.width", "elements.playerTargetIndicator.texture.height",
    "elements.playerTargetIndicator.texture.x", "elements.playerTargetIndicator.texture.y",
    "layout.direction", "layout.spacing", "layout.maxVisible",
    "timerGroup.width", "timerGroup.height",
    "timerGroup.borderSize", "timerGroup.borderPadding",
    "timerGroup.iconOffsetX", "timerGroup.iconWidth", "timerGroup.iconHeight",
    "timerGroup.iconOffsetY", "timerGroup.iconBorderSize", "timerGroup.iconBorderPadding",
}) do
    STANDARD_SCHEMA_PATHS[path] = true
end
for _, key in ipairs({ "font_spell", "font_target", "font_timer" }) do
    for _, field in ipairs({
        "size", "x", "y", "shadowX", "shadowY", "fixedWidth", "maxWidth",
        "gradientStart", "gradientLength", "rotation",
    }) do
        STANDARD_SCHEMA_PATHS[key .. "." .. field] = true
    end
end
for _, paths in pairs({
    { "font_spell.autoWidth" },
    { "font_target.autoWidth" },
    { "font_timer.autoWidth" },
    { "font_spell.x", "font_spell.y" },
    { "font_target.x", "font_target.y" },
    { "font_timer.x", "font_timer.y" },
    { "elements.raidMarker.texture.x", "elements.raidMarker.texture.y" },
    { "elements.playerTargetIndicator.texture.x", "elements.playerTargetIndicator.texture.y" },
}) do
    for _, path in ipairs(paths) do STANDARD_SCHEMA_PATHS[path] = true end
end

STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = EXWIND_MODULE_KEY,
    getConfig = GetDB,
    reapplyExisting = function(phase)
        local function replace(target, source)
            if not source then return end
            for key in pairs(target) do target[key] = nil end
            for key, value in pairs(source) do target[key] = value end
        end
        local samples = {}
        for _, record in ipairs(BuildSampleRecords()) do samples[record.id] = record end
        local runtime = {}
        for _, record in ipairs(usedBarsList) do runtime[record.id] = record end
        local function reapply(collection, resolver, layout)
            if collection and type(collection.ReapplyCurrentItems) == "function" then
                collection:ReapplyCurrentItems(function(presentation, item)
                    local nextPresentation = resolver(item and item.id)
                    if nextPresentation then replace(presentation, nextPresentation) end
                end, { reapplyLayout = false })
            end
            if collection and type(collection.ReapplyCurrentLayout) == "function" then
                collection:ReapplyCurrentLayout(layout)
            end
        end
        local function samplePresentation(mode)
            return function(id)
                local record = samples[id]
                return record and BuildMythicPresentation(record, mode) or nil
            end
        end
        local function runtimePresentation(id)
            local record = runtime[id]
            return record and BuildMythicPresentation(record, "runtime") or nil
        end
        local layout = GetSemanticLayout()
        reapply(panelPreview, samplePresentation("panel"), layout)
        -- This is intentionally after the in-place layout pass: maxVisible,
        -- spacing and direction immediately update the preview dock height.
        ResizePanelDock()
        reapply(worldCollection, samplePresentation("world"), layout)
        reapply(runtimeCollection, runtimePresentation, layout)
    end,
    schemaPaths = STANDARD_SCHEMA_PATHS,
})

local function RefreshActiveSurfaces(_, _, phase)
    return STANDARD_CONFIG_BINDING.reapplyExisting(phase)
end
EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 同一 module/dock/rule 只复用这一个 Core panel session；切换 dock 或释放页面时
-- Surface 负责释放旧 hitbox 与 collection，MythicCast 不再私有管理 panel tree。
panelSurface = EXUI:CreateStandardPreviewSurface({
    moduleKey = EXWIND_MODULE_KEY,
    kind = "timerbar",
    binding = STANDARD_CONFIG_BINDING,
    buildPresentation = BuildMythicPanelPresentation,
    collectionOptions = {
        schema = MYTHIC_TIMER_BAR_SCHEMA,
        contentCenter = true,
    },
    interactionSchema = INTERACTION_SCHEMA,
    requiredPositionGuiKeys = {
        "font_spell", "font_target", "font_timer", "raidMarkerExtra", "playerTargetIndicatorExtra",
    },
})

-- 世界编辑只换成普通样本 collection；Core 仍拥有 SelectionFrame、整体拖动与右键。
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "mythiccast",
    name = L["大米怪物施法"],
    settingsPage = "mythiccast",
    appearanceProfile = "basicTimerBar",
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 28 },
    getAnchor = function()
        CreateAnchor()
        return anchorFrame
    end,
    RenderWorld = function(host) return Module:RenderWorld(host) end,
    ReleaseWorld = function() return Module:ReleaseWorld() end,
    GetWorldBounds = function() return Module:GetWorldBounds() end,
})

-- 重置注册（供 ToolsPage 重置按钮调用）
ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[EXWIND_MODULE_KEY] = function()
    local moduleDB = _G.EXBOSS12S2 and _G.EXBOSS12S2.ModuleDB
    if not moduleDB then return end

    -- 重置不能保留旧表再逐项清空：页面、运行时和预览均以 EX_DB 为唯一引用，
    -- 直接丢弃本模块整张 DB 后再由唯一 EX_DEFAULTS 声明创建，才能保证没有旧字段或旧引用残留。
    moduleDB[EXWIND_MODULE_KEY] = nil
    EX_DB = GetDB()
    EXUI:NotifyModuleValueChanged(EXWIND_MODULE_KEY, "*", "committed")
end

-- =============================================================
-- GUI 渲染接口（由 GlobalSettingsPage embed 调用）
-- =============================================================
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.UI.Panel.MythicCastPage = ExBoss.UI.Panel.MythicCastPage or {}
GUIPage = ExBoss.UI.Panel.MythicCastPage

-- Page 只声明既有 layout、Preview 调用和 Slider 合同；Dock、Scroll、延迟
-- Render、watch、OnHide/release 与 ActivePage 全由 StandardModulePage 拥有。
local function RenderMythicCastPanelPreview(dock)
    Module:ShowPanelPreview(dock)
end

local function RefreshMythicCastPanelPreview(dock)
    Module:RefreshPanelPreview(dock)
end

local function ReleaseMythicCastPanelPreview()
    Module:ReleasePanelPreview()
end

local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = EXWIND_MODULE_KEY,
    page = GUIPage,
    binding = STANDARD_CONFIG_BINDING,
    layout = EX_LAYOUT,
    getColumns = 200,
    preview = {
        height = 172,
        render = RenderMythicCastPanelPreview,
        refresh = RefreshMythicCastPanelPreview,
        release = ReleaseMythicCastPanelPreview,
    },
    applyScrollSkin = function(scrollFrame)
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
    end,
    sliderContract = function()
        return {
            groupPaths = SLIDER_GROUP_PATHS,
        }
    end,
})

function GUIPage:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function GUIPage:Hide()
    return StandardPage:Hide()
end
