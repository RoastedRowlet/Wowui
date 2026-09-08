---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/CastProgressBarPage.lua
-- 设置页只承载 Grid 与 EXUI 唯一标准预览面板。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
ExBoss.UI.Panel.CastProgressBarPage = ExBoss.UI.Panel.CastProgressBarPage or {}
local Page = ExBoss.UI.Panel.CastProgressBarPage

local MODULE_KEY = "ExBoss.CastProgressBar"

local function GetCastProgressBar()
    return ExBoss.UI and ExBoss.UI.CastProgressBar
end

local function GetDB()
    local module = GetCastProgressBar()
    if not module or type(module.GetDB) ~= "function" then
        error("CastProgressBarPage requires CastProgressBar:GetDB", 2)
    end
    return module:GetDB()
end

local function GetAnchorGroupOptions()
    local module = GetCastProgressBar()
    if not module or type(module.GetAnchorGroupOptions) ~= "function" then
        error("CastProgressBarPage requires CastProgressBar:GetAnchorGroupOptions", 2)
    end
    return module:GetAnchorGroupOptions()
end

local ANCHOR_GROUP_OPTS = GetAnchorGroupOptions()

local SLIDER_GROUP_PATHS = {
    layout = "layout",
    timerGroup = "timerGroup",
    font_spell = "font_spell",
    font_timer = "font_timer",
}

-- 与 BunBar 共用的模块化首屏：把实际影响施法条整体行为的选项集中，
-- 条体与两组文字仍各自保留完整的专属编辑器。
local COMMON_OPTS = {
    bindRoot = true,
    poolType = "CastProgressBarModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
        { path = "layout.direction", type = "dropdown", label = L["增长方向"], items = { { L["向上"], "UP" }, { L["向下"], "DOWN" } }, row = 1 },
        { path = "layout.maxVisible", type = "slider", label = L["最大显示"], min = 1, max = 5, step = 1, row = 1 },
        { path = "layout.spacing", type = "slider", label = L["条目间距"], min = -24, max = 24, step = 1, row = 1 },
        { path = "timerGroup.progressMode", type = "dropdown", label = L["进度方向"], items = { { L["剩余时间"], "REMAINING" }, { L["已过时间"], "ELAPSED" } }, row = 2 },
        { path = "timerGroup.iconSide", type = "dropdown", label = L["图标位置"], items = { { L["左侧"], "LEFT" }, { L["右侧"], "RIGHT" }, { L["居中"], "CENTER" } }, row = 2 },
        { path = "timerGroup.showIcon", type = "checkbox", label = L["显示图标"], row = 2 },
        { path = "timerGroup.showBorder", type = "checkbox", label = L["显示边框"], row = 2 },
    },
}

local GRID_LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["施法进度条设置"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 48, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 61, w = 200, h = 20, measure = true, label = L["锚点设置"], opts = ANCHOR_GROUP_OPTS },
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 84, w = 200, h = 50, label = L["施法条外观"], labelSize = 20 },
    { key = "font_spell", type = "fontgroup", x = 1, y = 137, w = 200, h = 50, label = L["法术名称"], labelSize = 20 },
    { key = "font_timer", type = "fontgroup", x = 1, y = 190, w = 200, h = 50, label = L["时间文本"], labelSize = 20 },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, GRID_LAYOUT)

local function RebindModuleCommon(context)
    local state = context.grid and context.grid.ContainerStates and context.grid.ContainerStates[context.scrollChild]
    local common = state and state.widgets and state.widgets.moduleCommon
    if common and type(common.RebindDB) == "function" then common:RebindDB(context.config) end
end

local function RenderCastProgressPanelPreview(dock)
    local module = GetCastProgressBar()
    if module and type(module.ShowPanelPreview) == "function" then
        module:ShowPanelPreview(dock)
    end
end

local function RefreshCastProgressPanelPreview(dock)
    local module = GetCastProgressBar()
    if module and type(module.RefreshPanelPreview) == "function" then
        module:RefreshPanelPreview(dock)
    end
end

local function ReleaseCastProgressPanelPreview()
    local module = GetCastProgressBar()
    if module and type(module.ReleasePanelPreview) == "function" then
        module:ReleasePanelPreview()
    end
end

local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = GRID_LAYOUT,
    getColumns = 200,
    preview = { height = 1, render = RenderCastProgressPanelPreview, refresh = RefreshCastProgressPanelPreview, release = ReleaseCastProgressPanelPreview },
    previewDock = {
        dockPolicy = "external-left",
        anchorResolver = function(contentFrame)
            local panel = ExBoss.UI and ExBoss.UI.Panel
            return (panel and panel._frame) or contentFrame:GetParent() or contentFrame
        end,
        width = 310, offsetX = -8, offsetY = 0,
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
        RebindModuleCommon(context)
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end
