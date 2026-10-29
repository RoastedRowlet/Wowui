---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/TimerBarPage.lua
-- 计时条设置页（V2 声明）
--
-- 标准接入：页面外壳由 EXUI:CreateStandardModulePage 统一拥有；本文件只声明
-- 既有布局、标准 Slider 生命周期和 TimerBar 的 Preview Surface 调用。
-- =============================================================

-- =============================================================
-- 模块引导与常量
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.TimerBarPage = ExBoss.UI.Panel.TimerBarPage or {}
local Page = ExBoss.UI.Panel.TimerBarPage

local MODULE_KEY = "ExBoss.TimerBar"

-- =============================================================
-- 模块控件规格
-- =============================================================
local TIMER_BAR_COMMON_FIELDS = {
    { path = "hideLongTimersSeconds", type = "slider", label = L["只显示最后几秒"], min = 1, max = 60, step = 1, row = 2 },
}

local TIMER_BAR_COMMON_OPTS = {
    bindRoot = true,
    poolType = "TimerBarModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = TIMER_BAR_COMMON_FIELDS,
    presentation = "settings-list",
}

local TIMER_BAR_EXTRA_TEXTURE_OPTS = ExwindTools:BuildStandardTimerBarAlertIconsGroupOptions({
    timerBarKey = "timerGroup",
}, {
    paths = {
        show = "elements.alertIcons.texture.enabled",
        width = "elements.alertIcons.texture.width",
        height = "elements.alertIcons.texture.height",
        x = "elements.alertIcons.texture.x",
        y = "elements.alertIcons.texture.y",
    },
    ranges = {
        width = { min = 8, max = 128, step = 1 }, height = { min = 8, max = 128, step = 1 },
        x = { min = -1000, max = 1000, step = 1 }, y = { min = -1000, max = 1000, step = 1 },
    },
})
TIMER_BAR_EXTRA_TEXTURE_OPTS.presentation = "settings-list"

-- 此对象由 TimerBar View 的唯一 ANCHOR_SCHEMA 创建。Page 不得复制 key、默认
-- 位置或 picker 映射；否则世界整体拖动与 AnchorGroup 会再次变成两份合同。
local timerBar = ExBoss.UI and ExBoss.UI.TimerBar
if not timerBar or type(timerBar.GetStandardAnchorGroupOptions) ~= "function" then
    error("TimerBarPage requires TimerBar standard anchor contract", 2)
end
local TIMER_BAR_ANCHOR_OPTS = timerBar:GetStandardAnchorGroupOptions()

local TIMER_BAR_LAYOUT_OPTS = {
    -- TimerBar is a vertical semantic collection.  Do not expose horizontal
    -- directions merely because the generic Grid widget can render them.
    allowedDirections = { "UP", "DOWN" },
    includeMaxPerRow = false,
    maxVisibleMin = 1,
    maxVisibleMax = 6,
    defaultMaxVisible = 6,
}

local SLIDER_GROUP_PATHS = {
    moduleCommon = "",
    extraTexture = "",
    layout = "layout",
    timerGroup = "timerGroup",
    font_spell = "font_spell",
    font_timer = "font_timer",
}

-- =============================================================
-- V2 纯布局声明
-- =============================================================

-- 保留原设置块次序与组合控件身份；带回调的选项由 owner 提供。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "timeline-enabled", title = L["时间轴样式选择"],
            children = {
                { kind = "control", id = "timer", controlType = "switch", ref = "timelineEnabled" },
            } },
        { kind = "card", id = "module-common", title = L["通用设置"],
            children = {
                { kind = "component", id = "moduleCommon", component = "modulecommonsettings", path = "moduleCommon", opts = TIMER_BAR_COMMON_OPTS },
            } },
        { kind = "card", id = "layout-card", title = L["排列设置"],
            children = {
                { kind = "component", id = "layout", component = "widgetlayout", path = "layout", opts = TIMER_BAR_LAYOUT_OPTS },
            } },
        { kind = "card", id = "anchor", title = L["锚点设置"],
            children = {
                { kind = "component", id = "anchorGroup", component = "anchorgroup", path = "anchorGroup", optionsRef = "anchor" },
            } },
        { kind = "card", id = "timer-bar", title = L["计时条外观"],
            children = {
                { kind = "component", id = "timerGroup", component = "timerbargroup", path = "timerGroup", opts = {} },
            } },
        { kind = "card", id = "extra-texture", title = L["额外子元素－材质"],
            children = {
                { kind = "component", id = "extraTexture", component = "modulecommonsettings", path = "extraTexture", optionsRef = "extraTexture" },
            } },
        { kind = "card", id = "spell-font", title = L["法术名称"],
            children = {
                { kind = "component", id = "font_spell", component = "fontgroup", path = "font_spell", opts = {} },
            } },
        { kind = "card", id = "timer-font", title = L["时间文本"],
            children = {
                { kind = "component", id = "font_timer", component = "fontgroup", path = "font_timer", opts = {} },
            } },
    },
}

local function CreatePageOwner()
    return {
        options = {
            anchor = TIMER_BAR_ANCHOR_OPTS,
            extraTexture = TIMER_BAR_EXTRA_TEXTURE_OPTS,
        },
        controls = {
            timelineEnabled = EXUI:CreateSettingsV2Control({ controlType = "switch", label = L["启用"] }, function()
                return EXUI:CreateSettingsV2Binding("ExBoss.GeneralOverview", _G.EXBOSS12S2, "ui.general.timelineBars.timer")
            end),
        },
    }
end

-- =============================================================
-- 标准页面合同
-- =============================================================
local function GetTimerBar()
    return ExBoss.UI and ExBoss.UI.TimerBar
end

local function RebindTimerBarModuleCommon(context)
    for _, key in ipairs({ "moduleCommon", "extraTexture" }) do
        local group = context.modulePage and context.modulePage:Find(key)
        if group and type(group.RebindDB) == "function" then
            group:RebindDB(context.config)
        end
    end
end

local function RenderTimerBarPanelPreview(dock)
    local timerBar = GetTimerBar()
    if timerBar and type(timerBar.ShowPanelPreview) == "function" then
        timerBar:ShowPanelPreview(dock)
    end
end

local function ReleaseTimerBarPanelPreview()
    local timerBar = GetTimerBar()
    if timerBar and type(timerBar.ReleasePanelPreview) == "function" then
        timerBar:ReleasePanelPreview()
    end
end

-- [生命周期边界] StandardModulePage 继续拥有 Scroll、延迟 Render、preview 与 release；布局迁移不得重建这些生命周期。
local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    title = L["计时条设置"],
    layout = LAYOUT,
    ownerFactory = CreatePageOwner,
    preview = {
        -- 模块合同下限：TimerBar 预览至少显示两条，不能从 1px Dock 开始。
        height = 120,
        render = RenderTimerBarPanelPreview,
        release = ReleaseTimerBarPanelPreview,
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
    afterLayout = function(context)
        RebindTimerBarModuleCommon(context)
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end

function Page:RefreshTimelineBarControls()
    return StandardPage:RefreshControls()
end
