---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/RingProgressPage.lua
-- 圆环进度设置页：页面外壳、Dock、watch、V2 生命周期均由 StandardModulePage 拥有。
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

-- 保留原设置块次序、控件身份与字段；运行期锚点选项和测试动作由 owner 提供。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "general", title = L["通用设置"] or "通用设置",
            children = {
                { kind = "control", id = "enabled", controlType = "switch", path = "enabled", label = L["启用"] or "启用",
                    description = L["屏幕中央显示圆环进度"] or "屏幕中央显示圆环进度" },
            } },
        { kind = "card", id = "anchor-card", title = L["锚点设置"] or "锚点设置",
            children = {
                { kind = "component", id = "anchor", component = "anchorgroup", path = "anchor", optionsRef = "anchor" },
            } },
        { kind = "card", id = "ring-appearance", title = L["外观"] or "外观",
            children = {
                { kind = "control", id = "castFillMode", controlType = "select", path = "castFillMode", size = "wide", label = L["施法填充方式"] or "施法填充方式", options = { { value = "cw_fill", label = L["顺时针填满"] or "顺时针填满" }, { value = "cw_decay", label = L["顺时针消退"] or "顺时针消退" }, { value = "ccw_fill", label = L["逆时针填满"] or "逆时针填满" }, { value = "ccw_decay", label = L["逆时针消退"] or "逆时针消退" } } },
                { kind = "control", id = "channelFillMode", controlType = "select", path = "channelFillMode", size = "wide", label = L["引导填充方式"] or "引导填充方式", options = { { value = "cw_fill", label = L["顺时针填满"] or "顺时针填满" }, { value = "cw_decay", label = L["顺时针消退"] or "顺时针消退" }, { value = "ccw_fill", label = L["逆时针填满"] or "逆时针填满" }, { value = "ccw_decay", label = L["逆时针消退"] or "逆时针消退" } } },
                { kind = "control", id = "style", controlType = "select", path = "style", label = L["圆环样式"] or "圆环样式", options = { { value = "thin1", label = L["细环 1"] or "细环 1" }, { value = "thin2", label = L["细环 2"] or "细环 2" }, { value = "classic", label = L["标准环"] or "标准环" } } },
                { kind = "control", id = "size", controlType = "slider", path = "size", label = L["圆环尺寸"] or "圆环尺寸", min = 20, max = 360, step = 2 },
                { kind = "control", id = "ringColor", controlType = "color", path = "ringColor", label = L["颜色"] or "颜色" },
                { kind = "control", id = "alpha", controlType = "slider", path = "alpha", label = L["透明度"] or "透明度", min = 0.1, max = 1, step = 0.05 },
                { kind = "setting", id = "testCast_row", label = L["测试施法"] or "测试施法", children = {
                    { kind = "button", id = "testCast", text = L["测试施法"] or "测试施法", action = "testCast" },
                } },
                { kind = "setting", id = "testChannel_row", label = L["测试引导"] or "测试引导", children = {
                    { kind = "button", id = "testChannel", text = L["测试引导"] or "测试引导", action = "testChannel" },
                } },
            } },
        { kind = "card", id = "background", title = L["背景圆环"] or "背景圆环",
            children = {
                { kind = "control", id = "bgEnabled", controlType = "switch", path = "bgEnabled", label = L["启用背景圆环"] or "启用背景圆环" },
                { kind = "control", id = "bgColor", controlType = "color", path = "bgColor", label = L["背景颜色"] or "背景颜色" },
                { kind = "control", id = "bgAlpha", controlType = "slider", path = "bgAlpha", label = L["背景透明度"] or "背景透明度", min = 0.05, max = 1, step = 0.05 },
            } },
        { kind = "card", id = "spell-font", title = L["法术名称"] or "法术名称",
            children = {
                { kind = "component", id = "font_spell", component = "fontgroup", path = "font_spell", opts = {} },
            } },
        { kind = "card", id = "timer-font", title = L["时间文本"] or "时间文本",
            children = {
                { kind = "component", id = "font_timer", component = "fontgroup", path = "font_timer", opts = {} },
            } },
    },
}

local function CreatePageOwner()
    return {
        options = { anchor = ANCHOR_OPTS },
        actions = {
            testCast = function()
                GetRingProgress():ShowTestCast()
            end,
            testChannel = function()
                GetRingProgress():ShowTestChannel()
            end,
        },
    }
end

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
    title = L["圆环进度设置"] or "圆环进度设置",
    layout = LAYOUT,
    ownerFactory = CreatePageOwner,
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
