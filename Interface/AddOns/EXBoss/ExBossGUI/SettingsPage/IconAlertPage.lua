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
    { path = "enabled", type = "checkbox", label = L["启用"] },
}

local COMMON_OPTS = {
    bindRoot = true,
    poolType = "IconAlertModuleCommonSettingsGroup",
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

-- [卡片/Grid 迁移边界：IconAlert 设置页]
-- 允许：普通 sections 单声明及纯展示排列；Core 统一测量，原语义选项保留。
-- 禁止：修改 key/type/path/opts、允许增长方向、预览、Slider 或释放合同。
-- modulecommonsettings/anchorgroup/widgetlayout/icongroup/fontgroup/glow_settings 必须整体引用，不能拆开重拼。
local GRID_LAYOUT = {
    version = 1,
    title = L["图标设置"],
    sections = {
        { kind = "composite", id = "module-common", title = L["通用"],
            component = "modulecommonsettings", key = "moduleCommon", opts = COMMON_OPTS },
        { kind = "composite", id = "layout", title = L["排列设置"],
            component = "widgetlayout", key = "layout", opts = LAYOUT_OPTS },
        { kind = "composite", id = "anchor", title = L["锚点"],
            component = "anchorgroup", key = "anchorGroup", opts = ANCHOR_OPTS },
        { kind = "composite", id = "icon", title = L["外观"],
            component = "icongroup", key = "icon" },
        { kind = "composite", id = "glow", title = L["发光子元素"],
            component = "glow_settings", key = "glow" },
        { kind = "composite", id = "name-font", title = L["名称子元素"],
            component = "fontgroup", key = "font_text" },
        { kind = "composite", id = "time-font", title = L["倒数文本"],
            component = "fontgroup", key = "font_time" },
        { kind = "composite", id = "stacks-font", title = L["层数文本"],
            component = "fontgroup", key = "font_stacks" },
    },
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

-- [生命周期边界] StandardModulePage 继续拥有 Dock、Scroll、Watch、preview 与 release；布局迁移不得另建生命周期。
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
