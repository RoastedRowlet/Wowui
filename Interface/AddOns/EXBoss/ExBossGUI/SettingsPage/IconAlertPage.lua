---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/IconAlertPage.lua
-- IconAlert 设置页只承载 Grid 与 EXUI 标准预览面板。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
ExBoss.UI.Panel.IconAlertPage = ExBoss.UI.Panel.IconAlertPage or {}
local Page = ExBoss.UI.Panel.IconAlertPage

local MODULE_KEY = "ExBoss.IconAlert"

local function GetIconAlert()
    return ExBoss.UI and ExBoss.UI.IconAlert
end

local ICON_COMMON_FIELDS = {
    { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
}

local COMMON_OPTS = {
    bindRoot = true,
    poolType = "IconAlertModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = ICON_COMMON_FIELDS,
}

-- 此对象由 IconAlert View 的唯一 ANCHOR_SCHEMA 创建。Page 不得复制 key、默认
-- 位置或 picker 映射；否则世界整体拖动与 AnchorGroup 会再次变成两份合同。
local iconAlert = GetIconAlert()
if not iconAlert or type(iconAlert.GetStandardAnchorGroupOptions) ~= "function" then
    error("IconAlertPage requires IconAlert standard anchor contract", 2)
end
local ANCHOR_OPTS = iconAlert:GetStandardAnchorGroupOptions()

local LAYOUT_OPTS = {
    -- 图标集合允许四向增长及以整组为锚点的两个居中方向；几何由 WidgetLayout
    -- 统一计算，页面只声明本模块允许暴露的选项。
    allowedDirections = { "LEFT", "RIGHT", "UP", "DOWN", "CENTER_HORIZONTAL", "CENTER_VERTICAL" },
    includeMaxPerRow = false,
    maxVisibleMin = 1,
    maxVisibleMax = 8,
    defaultMaxVisible = 5,
}

local GRID_LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["图标设置"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 11, w = 200, h = 22, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "anchorGroup", type = "anchorgroup", x = 1, y = 33, w = 200, h = 20, measure = true, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "layout", type = "widgetlayout", x = 1, y = 55, w = 200, h = 20, measure = true, label = L["排列设置"], opts = LAYOUT_OPTS },
    { key = "icon", type = "icongroup", x = 1, y = 77, w = 200, h = 50, label = L["图标本体"], labelSize = 20 },
    { key = "font_text", type = "fontgroup", x = 1, y = 129, w = 200, h = 50, label = L["名称子元素"], labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 1, y = 181, w = 200, h = 50, label = L["倒数文本"], labelSize = 20 },
    { key = "font_stacks", type = "fontgroup", x = 1, y = 233, w = 200, h = 50, label = L["层数文本"], labelSize = 20 },
    { key = "glow", type = "glow_settings", x = 1, y = 285, w = 200, h = 50, measure = true, label = L["发光子元素"] },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, GRID_LAYOUT)

-- Page 只提供本模块既有布局和标准声明；Dock、Scroll、Watch、延迟 Render 与
-- OnHide/release 全由 StandardModulePage 统一拥有。
local function RenderStandardPreview(dock)
    local iconAlert = GetIconAlert()
    if not iconAlert or type(iconAlert.ShowPanelPreview) ~= "function" then
        error("IconAlert standard preview renderer is unavailable", 2)
    end
    iconAlert:ShowPanelPreview(dock)
end

local function ReleaseStandardPreview()
    local iconAlert = GetIconAlert()
    if iconAlert and type(iconAlert.ReleasePanelPreview) == "function" then
        iconAlert:ReleasePanelPreview()
    end
end

local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = GRID_LAYOUT,
    preview = {
        height = 160,
        render = RenderStandardPreview,
        refresh = RenderStandardPreview,
        release = ReleaseStandardPreview,
    },
    applyScrollSkin = function(scrollFrame)
        if ExBoss.UI and type(ExBoss.UI.ApplyModernScrollBarSkin) == "function" then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
    end,
    sliderContract = function()
        local iconAlert = GetIconAlert()
        local contract = iconAlert and iconAlert.StandardSliderContract
        if type(contract) ~= "table" then error("IconAlert standard Slider contract is unavailable", 2) end
        return {
            groupPaths = contract.groupPaths,
        }
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end
