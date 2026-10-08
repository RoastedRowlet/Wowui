---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/RingProgressPage.lua
-- 圆环进度设置页：页面外壳、Dock、watch、Grid 生命周期均由 StandardModulePage 拥有。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
local L = ExBoss and ExBoss.GetLocale and ExBoss:GetLocale() or {}

ExBoss.UI.Panel.RingProgressPage = ExBoss.UI.Panel.RingProgressPage or {}
local Page = ExBoss.UI.Panel.RingProgressPage
local MODULE_KEY = "ExBoss.RingProgress"

local function GetRingProgress()
    local module = ExBoss.UI and ExBoss.UI.RingProgress
    if not module
        or type(module.GetDB) ~= "function"
        or type(module.GetAnchorGroupOptions) ~= "function"
        or type(module.StandardSliderContract) ~= "table"
        or type(module.StandardSliderContract.groupPaths) ~= "table"
        or type(module.ShowPanelPreview) ~= "function"
        or type(module.RefreshPanelPreview) ~= "function"
        or type(module.ReleasePanelPreview) ~= "function"
        or type(module.ShowTestCast) ~= "function"
        or type(module.ShowTestChannel) ~= "function" then
        error("RingProgressPage requires RingProgress standard display contract", 2)
    end
    return module
end

local ANCHOR_OPTS = GetRingProgress():GetAnchorGroupOptions()

-- 页面只保留真实配置字段与 Grid 几何；不再自行管理 PreviewDock、watch、onHide、
-- private focus callback 或 Slider 生命周期。
-- [卡片/Grid 迁移边界：RingProgress 设置页]
-- 允许：普通 sections 单声明及纯展示排列；Core 统一测量，原语义选项保留。
-- 禁止：修改 key/type/path/opts、测试施法/引导回调、动态背景启用逻辑、预览或释放合同。
-- fontgroup 必须整体引用；旧 header/divider/背景项只绘制与定位，不自动成为内容/回收容器。
local LAYOUT = {
    version = 1,
    title = L["圆环进度设置"] or "圆环进度设置",
    sections = {
        { kind = "settings", id = "general", title = L["通用设置"] or "通用设置",
            description = { key = "desc", type = "description", label = L["屏幕中央显示圆环进度"] or "屏幕中央显示圆环进度" },
            items = {
                { key = "enabled", type = "switch", label = L["启用"] or "启用" },
            } },
        { kind = "composite", id = "anchor", title = L["锚点设置"] or "锚点设置",
            component = "anchorgroup", key = "anchor", opts = ANCHOR_OPTS },
        { kind = "settings", id = "ring-appearance", title = L["外观"] or "外观",
            items = {
                { key = "castFillMode", type = "select", label = L["施法填充方式"] or "施法填充方式", options = { { value = "cw_fill", label = L["顺时针填满"] or "顺时针填满" }, { value = "cw_decay", label = L["顺时针消退"] or "顺时针消退" }, { value = "ccw_fill", label = L["逆时针填满"] or "逆时针填满" }, { value = "ccw_decay", label = L["逆时针消退"] or "逆时针消退" } } },
                { key = "channelFillMode", type = "select", label = L["引导填充方式"] or "引导填充方式", options = { { value = "cw_fill", label = L["顺时针填满"] or "顺时针填满" }, { value = "cw_decay", label = L["顺时针消退"] or "顺时针消退" }, { value = "ccw_fill", label = L["逆时针填满"] or "逆时针填满" }, { value = "ccw_decay", label = L["逆时针消退"] or "逆时针消退" } } },
                { key = "style", type = "select", label = L["圆环样式"] or "圆环样式", options = { { value = "thin1", label = L["细环 1"] or "细环 1" }, { value = "thin2", label = L["细环 2"] or "细环 2" }, { value = "classic", label = L["标准环"] or "标准环" } } },
                { key = "size", type = "slider", label = L["圆环尺寸"] or "圆环尺寸", min = 20, max = 360, step = 2 },
                { key = "ringColor", type = "color", label = L["颜色"] or "颜色" },
                { key = "alpha", type = "slider", label = L["透明度"] or "透明度", min = 0.1, max = 1, step = 0.05 },
                { key = "testCast", type = "button", label = L["测试施法"] or "测试施法", func = function()
                    GetRingProgress():ShowTestCast()
                end },
                { key = "testChannel", type = "button", label = L["测试引导"] or "测试引导", func = function()
                    GetRingProgress():ShowTestChannel()
                end },
            } },
        { kind = "settings", id = "background", title = L["背景圆环"] or "背景圆环",
            items = {
                { key = "bgEnabled", type = "switch", label = L["启用背景圆环"] or "启用背景圆环" },
                { key = "bgColor", type = "color", label = L["背景颜色"] or "背景颜色" },
                { key = "bgAlpha", type = "slider", label = L["背景透明度"] or "背景透明度", min = 0.05, max = 1, step = 0.05 },
            } },
        { kind = "composite", id = "spell-font", title = L["法术名称"] or "法术名称",
            component = "fontgroup", key = "font_spell" },
        { kind = "composite", id = "timer-font", title = L["时间文本"] or "时间文本",
            component = "fontgroup", key = "font_timer" },
    },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

local function RenderRingProgressPanelPreview(dock)
    GetRingProgress():ShowPanelPreview(dock)
end

local function RefreshRingProgressPanelPreview()
    GetRingProgress():RefreshPanelPreview()
end

local function ReleaseRingProgressPanelPreview()
    GetRingProgress():ReleasePanelPreview()
end

local function ApplyScrollSkin(scrollFrame)
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
    end
end

-- [生命周期边界] StandardModulePage 继续拥有 Scroll、preview surface、Slider 与 release；布局迁移不得改其回调。
local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = LAYOUT,
    getColumns = 200,
    preview = {
        height = 260,
        render = RenderRingProgressPanelPreview,
        refresh = RefreshRingProgressPanelPreview,
        release = ReleaseRingProgressPanelPreview,
    },
    applyScrollSkin = ApplyScrollSkin,
    sliderContract = function()
        local contract = GetRingProgress().StandardSliderContract
        if type(contract) ~= "table" then error("RingProgress standard Slider contract is unavailable", 2) end
        return { groupPaths = contract.groupPaths }
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end
