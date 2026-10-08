-- ==================================================
-- ExTools.CombatTimer
-- 战斗时间业务模块；中央 Text owner 独占所有显示宿主。
-- ==================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.CombatTimer"
local RUNTIME_ITEM_ID = "combattimer:runtime"
local PREVIEW_ITEM_ID = "combattimer:preview"
local C_DurationUtil, C_StringUtil, Enum = _G.C_DurationUtil, _G.C_StringUtil, _G.Enum
local running, combatStartTime, combatEndTime = false, 0, 0
local RefreshActiveSurfaces

-- EXUI_STANDARD_DECLARATION_BEGIN
-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller, changedPath, phase)
        return RefreshActiveSurfaces(controller, changedPath,
            phase)
    end,
    moduleKey = MODULE_KEY,
    kind = "text",
    version = 1,
    -- =========================================================
    -- 二、默认配置与配置访问 | Defaults and Configuration Access
    -- =========================================================
    defaults = {
        font_text = {
            a = 1,
            attachToCustom = false,
            b = 1,
            customAttachTarget = "",
            font = "默认",
            g = 1,
            outline = "OUTLINE",
            r = 1,
            shadow = true,
            shadowX = 1,
            shadowY = -1,
            size = 25,
            x = -325,
            y = -232,
        },
        root = {
            enabled = true,
            hideOutOfCombat = false,
            keepTimeOnLeaveCombat = true,
            layout = {
                direction = "DOWN",
                maxVisible = 1,
                spacing = 0,
            },
            leftText = "[",
            resetOnBoss = true,
            rightText = "]",
        },
    },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    anchor = {
        -- font_text.x/y 是整体 Anchor 的唯一 DB 坐标，不是文字局部位置。
        dbPath = "font_text",
        xKey = "x",
        yKey = "y",
        defaultX = 0,
        defaultY = 0,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 200,
        initialHeight = 48,
        clampedToScreen = false,
        bindRoot = true,
    },
    preview = {
        positionGuiKeys = {},
        elements = {
            ["combattimer.display"] = {
                guiKey = "font_text", movable = false, tooltip = L["战斗时间计时器"],
            },
        },
    },
    -- [卡片迁移边界：设置页] 仅可按统一规范调整下列 gui.static/gui.fields 的 x/y/w/h 与卡片分组。
    -- key/type/opts、DB path、anchor/preview/defaults 及原生 Duration/刷新回调均属绑定或业务合同，禁止修改；复合控件整体引用，header 不等于容器。
    -- =========================================================
    -- 三、GUI 声明 | GUI Declarations
    -- =========================================================
    gui = {
        version = 1,
        sections = {
            {
                kind = "settings", id = "common", title = L["通用设置"],
                items = {
                    { key = "enabled", label = L["启用计时器"], type = "switch" },
                    { key = "resetOnBoss", label = L["首领重置"], type = "switch" },
                    { key = "hideOutOfCombat", label = L["脱战隐藏"], type = "switch" },
                    { key = "keepTimeOnLeaveCombat", label = L["脱战停表"], type = "switch" },
                    { key = "leftText", label = L["前缀文字 (左)"], type = "input" },
                    { key = "rightText", label = L["后缀文字 (右)"], type = "input" },
                },
            },
            {
                kind = "composite", id = "anchor", title = L["锚点设置"],
                component = "anchorgroup", key = "anchorGroup", parentKey = "font_text",
            },
            {
                kind = "composite", id = "font_text", title = L["字体与整体位置"],
                component = "fontgroup", key = "font_text",
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterTextModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end
-- EXUI_STANDARD_DECLARATION_END

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local TEXT_WIDTH, MIN_TEXT_HEIGHT = 200, 48

local function Num(value, fallback) return tonumber(value) or fallback end
local function GetTextHeight()
    return math.max(MIN_TEXT_HEIGHT, Num(DB.font_text.size, 24) * 1.5)
end
local function FormatClock(seconds)
    seconds = math.max(0, Num(seconds, 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- 原生 elapsed Duration 格式合同：中央只原样消费，不进行 Lua OnUpdate。
local CLOCK_MINUTES_FORMATTER = C_StringUtil.CreateNumericRuleFormatter()
CLOCK_MINUTES_FORMATTER:SetBreakpoints({ {
    threshold = 0,
    format = "%02.0f",
    components = { { div = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down } },
} })
local CLOCK_SECONDS_FORMATTER = C_StringUtil.CreateNumericRuleFormatter()
CLOCK_SECONDS_FORMATTER:SetBreakpoints({ {
    threshold = 0,
    format = "%02.0f",
    components = { { mod = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down } },
} })

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function BuildNativeClockOptions()
    local prefix, suffix = DB.leftText or "", DB.rightText or ""
    local zero = prefix .. "00:00" .. suffix
    return {
        formatString = prefix .. "{}:{}" .. suffix,
        components = {
            { property = Enum.DurationTextBindingProperty.ElapsedDuration, formatter = CLOCK_MINUTES_FORMATTER },
            { property = Enum.DurationTextBindingProperty.ElapsedDuration, formatter = CLOCK_SECONDS_FORMATTER },
        },
        expiredText = zero,
        zeroDurationText = zero,
    }
end

local function BuildPresentation(preview)
    local elapsed, nativeElapsedDuration = 0, nil
    if preview then
        elapsed = 45
    elseif running then
        nativeElapsedDuration = C_DurationUtil.CreateDuration()
        nativeElapsedDuration:SetTimeFromStart(combatStartTime, 86400, 1)
    elseif DB.keepTimeOnLeaveCombat and combatEndTime > combatStartTime then
        elapsed = combatEndTime - combatStartTime
    end
    local textHeight = GetTextHeight()
    return {
        text = (DB.leftText or "") .. FormatClock(elapsed) .. (DB.rightText or ""),
        durationObject = nativeElapsedDuration,
        durationOptions = nativeElapsedDuration and BuildNativeClockOptions() or nil,
        -- Direct reference to the one ModuleDB style table. No style cache/copy.
        style = DB.font_text,
        semanticSlot = "combattimer.display",
        declaredBounds = {
            left = -TEXT_WIDTH * .5,
            right = TEXT_WIDTH * .5,
            bottom = -textHeight * .5,
            top = textHeight * .5,
        },
        anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        interaction = preview and EXUI:BuildStandardPreviewInteraction("Text", DB, MODULE_SPEC.preview.elements) or nil,
    }
end

local function BuildEntry(itemID, preview)
    return { itemID = itemID, presentation = BuildPresentation(preview) }
end
local function ShouldShowRuntime()
    return DB.enabled == true and not (DB.hideOutOfCombat and not running)
end

-- Both preview hosts and runtime are submitted from the same presentation
-- builder. The central owner creates/releases all three display hosts.
local function RefreshVisuals()
    central:SetPreview({ BuildEntry(PREVIEW_ITEM_ID, true) }, LAYOUT)
    if ShouldShowRuntime() then
        central:SetRuntime({ BuildEntry(RUNTIME_ITEM_ID, false) }, LAYOUT)
    else
        central:Clear()
    end
end

RefreshActiveSurfaces = function(controller, changedPath, phase)
    -- enabled changes the existence of the runtime text itself: when disabled
    -- it has been released, so a reapply-only pass cannot make it visible.
    if changedPath == "enabled" and phase == "committed" then
        RefreshVisuals()
        return false
    end
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildEntry(PREVIEW_ITEM_ID, true).presentation
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and ShouldShowRuntime() then
        controller.runtimeEntries[1].presentation = BuildEntry(RUNTIME_ITEM_ID, false).presentation
    end
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- Existing combat timer business.
local function StartTimer()
    if running then return end
    combatStartTime, running = GetTime(), true
    RefreshVisuals()
end
local function StopTimer()
    if running then combatEndTime = GetTime() end
    running = false
    RefreshVisuals()
end
local function ResetTimer()
    combatStartTime = GetTime()
    RefreshVisuals()
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("PLAYER_REGEN_DISABLED", MODULE_KEY, function()
    if DB.enabled then
        ResetTimer(); StartTimer()
    end
end)
ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", MODULE_KEY, function()
    if DB.enabled then StopTimer() end
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    if DB.enabled and InCombatLockdown() then StartTimer() else StopTimer() end
    RefreshVisuals()
end)
ExwindTools:WatchState("IsBossEncounter", MODULE_KEY, function(isBoss)
    if isBoss and DB.resetOnBoss then
        ResetTimer(); StartTimer()
    end
end)
-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
RefreshVisuals()
ExwindTools:ReportReady(MODULE_KEY)
