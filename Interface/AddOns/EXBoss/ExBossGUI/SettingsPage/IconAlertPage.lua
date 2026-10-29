---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/IconAlertPage.lua
-- IconAlert 设置页只承载 V2 声明与 EXUI 标准预览面板。
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

-- 保留组合控件身份、绑定与排列次序；运行期锚点选项由 owner 提供。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "module-common", title = L["通用"],
            children = {
                { kind = "component", id = "moduleCommon", component = "modulecommonsettings", path = "moduleCommon", opts = COMMON_OPTS },
            } },
        { kind = "card", id = "layout-card", title = L["排列设置"],
            children = {
                { kind = "component", id = "layout", component = "widgetlayout", path = "layout", opts = LAYOUT_OPTS },
            } },
        { kind = "card", id = "anchor", title = L["锚点"],
            children = {
                { kind = "component", id = "anchorGroup", component = "anchorgroup", path = "anchorGroup", optionsRef = "anchor" },
            } },
        { kind = "card", id = "icon-card", title = L["外观"],
            children = {
                { kind = "component", id = "icon", component = "icongroup", path = "icon", opts = {} },
            } },
        { kind = "card", id = "glow-card", title = L["发光子元素"],
            children = {
                { kind = "component", id = "glow", component = "glow_settings", path = "glow", opts = {} },
            } },
        { kind = "card", id = "name-font", title = L["名称子元素"],
            children = {
                { kind = "component", id = "font_text", component = "fontgroup", path = "font_text", opts = {} },
            } },
        { kind = "card", id = "time-font", title = L["倒数文本"],
            children = {
                { kind = "component", id = "font_time", component = "fontgroup", path = "font_time", opts = {} },
            } },
        { kind = "card", id = "stacks-font", title = L["层数文本"],
            children = {
                { kind = "component", id = "font_stacks", component = "fontgroup", path = "font_stacks", opts = {} },
            } },
    },
}

local function CreatePageOwner()
    return { options = { anchor = ANCHOR_OPTS } }
end

-- Page 只提供本模块既有布局和 V2 声明；Dock、Scroll、Watch、延迟 Render 与
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
    title = L["图标设置"],
    layout = LAYOUT,
    ownerFactory = CreatePageOwner,
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
