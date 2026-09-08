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
local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["圆环进度设置"] or "圆环进度设置", labelSize = 25 },
    { key = "desc", type = "description", x = 1, y = 11, w = 200, h = 3, label = L["屏幕中央显示圆环进度"] or "屏幕中央显示圆环进度", labelSize = 18 },
    { key = "div_func", type = "divider", x = 1, y = 17, w = 200, h = 3, label = L["功能"] or "功能" },
    { key = "enabled", type = "checkbox", x = 3, y = 20, w = 46, h = 6, label = L["启用"] or "启用" },
    { key = "anchor", type = "anchorgroup", x = 1, y = 28, w = 200, h = 23, label = L["锚点设置"] or "锚点设置", opts = ANCHOR_OPTS },
    { key = "castFillMode", type = "dropdown", x = 4, y = 57, w = 44, h = 6, label = L["施法填充方式"] or "施法填充方式", items = {
        { L["顺时针填满"] or "顺时针填满", "cw_fill" },
        { L["顺时针消退"] or "顺时针消退", "cw_decay" },
        { L["逆时针填满"] or "逆时针填满", "ccw_fill" },
        { L["逆时针消退"] or "逆时针消退", "ccw_decay" },
    }, labelPos = "top" },
    { key = "channelFillMode", type = "dropdown", x = 52, y = 57, w = 44, h = 6, label = L["引导填充方式"] or "引导填充方式", items = {
        { L["顺时针填满"] or "顺时针填满", "cw_fill" },
        { L["顺时针消退"] or "顺时针消退", "cw_decay" },
        { L["逆时针填满"] or "逆时针填满", "ccw_fill" },
        { L["逆时针消退"] or "逆时针消退", "ccw_decay" },
    }, labelPos = "top" },
    { key = "style", type = "dropdown", x = 103, y = 57, w = 44, h = 6, label = L["圆环样式"] or "圆环样式", items = {
        { L["细环 1"] or "细环 1", "thin1" },
        { L["细环 2"] or "细环 2", "thin2" },
        { L["标准环"] or "标准环", "classic" },
    }, labelPos = "top" },
    { key = "size", type = "slider", x = 4, y = 70, w = 44, h = 6, label = L["圆环尺寸"] or "圆环尺寸", min = 20, max = 360, step = 2 },
    { key = "ringColor", type = "color", x = 52, y = 70, w = 44, h = 6, label = L["颜色"] or "颜色" },
    { key = "alpha", type = "slider", x = 103, y = 70, w = 44, h = 6, label = L["透明度"] or "透明度", min = 0.1, max = 1, step = 0.05 },
    { key = "testCast", type = "button", x = 151, y = 70, w = 23, h = 6, label = L["测试施法"] or "测试施法", func = function()
        GetRingProgress():ShowTestCast()
    end },
    { key = "testChannel", type = "button", x = 176, y = 70, w = 23, h = 6, label = L["测试引导"] or "测试引导", func = function()
        GetRingProgress():ShowTestChannel()
    end },
    { key = "div_bg", type = "divider", x = 1, y = 82, w = 200, h = 3, label = L["背景圆环"] or "背景圆环" },
    { key = "bgEnabled", type = "checkbox", x = 1, y = 85, w = 48, h = 6, label = L["启用背景圆环"] or "启用背景圆环" },
    { key = "bgColor", type = "color", x = 4, y = 95, w = 44, h = 6, label = L["背景颜色"] or "背景颜色" },
    { key = "bgAlpha", type = "slider", x = 52, y = 95, w = 44, h = 6, label = L["背景透明度"] or "背景透明度", min = 0.05, max = 1, step = 0.05 },
    { key = "font_spell", type = "fontgroup", x = 1, y = 107, w = 200, h = 50, label = L["法术名称"] or "法术名称", labelSize = 20 },
    { key = "font_timer", type = "fontgroup", x = 1, y = 158, w = 200, h = 50, label = L["时间文本"] or "时间文本", labelSize = 20 },
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
