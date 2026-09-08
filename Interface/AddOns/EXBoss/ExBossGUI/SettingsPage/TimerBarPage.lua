---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/TimerBarPage.lua
-- 计时条设置页（ExwindGrid 渲染）
--
-- 标准接入：页面外壳由 EXUI:CreateStandardModulePage 统一拥有；本文件只声明
-- 既有布局、标准 Slider 生命周期和 TimerBar 的 Preview Surface 调用。
-- =============================================================

-- =============================================================
-- 模块引导与常量
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.TimerBarPage = ExBoss.UI.Panel.TimerBarPage or {}
local Page = ExBoss.UI.Panel.TimerBarPage

local MODULE_KEY = "ExBoss.TimerBar"
local BASE_GRID_COLS = 200
local MIN_GRID_COLS = 200
local MAX_GRID_COLS = 200
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}

-- =============================================================
-- 模块控件规格
-- =============================================================
local TIMER_BAR_COMMON_FIELDS = {
    { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
    { path = "hideLongTimersSeconds", type = "slider", label = L["只显示最后几秒"], min = 1, max = 60, step = 1, row = 2 },
}

local TIMER_BAR_COMMON_OPTS = {
    bindRoot = true,
    poolType = "TimerBarModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = TIMER_BAR_COMMON_FIELDS,
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
-- Grid 纯布局声明
-- =============================================================

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["计时条设置"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 11, w = 200, h = 29, label = L["模块通用设置"], opts = TIMER_BAR_COMMON_OPTS },
    { key = "extraTexture", type = "modulecommonsettings", x = 1, y = 42, w = 200, h = 50, label = L["额外子元素－材质"], opts = TIMER_BAR_EXTRA_TEXTURE_OPTS },
    { key = "anchorGroup", type = "anchorgroup", x = 1, y = 94, w = 200, h = 20, measure = true, label = L["锚点设置"], opts = TIMER_BAR_ANCHOR_OPTS },
    { key = "layout", type = "widgetlayout", x = 1, y = 116, w = 200, h = 20, measure = true, label = L["排列设置"], opts = TIMER_BAR_LAYOUT_OPTS },
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 139, w = 200, h = 50, label = L["计时条外观"], labelSize = 20 },
    { key = "font_spell", type = "fontgroup", x = 1, y = 193, w = 200, h = 50, label = L["法术名称"], labelSize = 20 },
    { key = "font_timer", type = "fontgroup", x = 1, y = 246, w = 200, h = 50, label = L["时间文本"], labelSize = 20 },
}



-- =============================================================
-- Grid 布局缩放与注册
-- =============================================================
local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then
        return BASE_GRID_COLS
    end
    local cols = math.floor(((w - 20) / TARGET_CELL_PX) + 0.5)
    if cols < MIN_GRID_COLS then cols = MIN_GRID_COLS end
    if cols > MAX_GRID_COLS then cols = MAX_GRID_COLS end
    return cols
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then
        return LAYOUT
    end
    local cached = LAYOUT_CACHE[toCols]
    if cached then
        return cached
    end

    local scale = toCols / BASE_GRID_COLS
    local function ScaleItems(src)
        local out = {}
        for _, item in ipairs(src) do
            local row = {}
            for k, v in pairs(item) do
                if k ~= "children" then
                    row[k] = v
                end
            end
            if type(item.x) == "number" and type(item.w) == "number" then
                local nx = math.floor(((item.x - 1) * scale) + 1 + 0.5)
                local nw = math.max(1, math.floor(item.w * scale + 0.5))
                if nx < 1 then nx = 1 end
                if nx > toCols then nx = toCols end
                if nx + nw - 1 > toCols then
                    nw = math.max(1, toCols - nx + 1)
                end
                row.x = nx
                row.w = nw
            end
            if type(item.children) == "table" then
                row.children = ScaleItems(item.children)
            end
            out[#out + 1] = row
        end
        return out
    end

    cached = ScaleItems(items)
    LAYOUT_CACHE[toCols] = cached
    return cached
end

-- 注册布局（加载时执行一次）
ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

-- =============================================================
-- 标准页面合同
-- =============================================================
local function GetTimerBar()
    return ExBoss.UI and ExBoss.UI.TimerBar
end

local function RebindTimerBarModuleCommon(grid, container, db)
    local state = grid and grid.ContainerStates and grid.ContainerStates[container]
    local widgets = state and state.widgets
    for _, key in ipairs({ "moduleCommon", "extraTexture" }) do
        local group = widgets and widgets[key]
        if group and type(group.RebindDB) == "function" then
            group:RebindDB(db)
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

local StandardPage = ExwindTools.UI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = function(context)
        return ScaleLayout(LAYOUT, ResolveGridCols(context.scrollChild:GetWidth()))
    end,
    getColumns = function(context)
        return ResolveGridCols(context.scrollChild:GetWidth())
    end,
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
    afterGridLayout = function(context)
        RebindTimerBarModuleCommon(context.grid, context.scrollChild, context.config)
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end
