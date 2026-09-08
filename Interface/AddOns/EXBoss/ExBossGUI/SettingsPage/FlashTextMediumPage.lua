---@diagnostic disable: undefined-global, undefined-field, need-check-nil
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

ExBoss.UI.Panel.FlashTextMediumPage = ExBoss.UI.Panel.FlashTextMediumPage or {}
local Page = ExBoss.UI.Panel.FlashTextMediumPage
local MODULE_KEY = "ExBoss.FlashTextMedium"

local function GetFlashText()
    local module = ExBoss.UI and ExBoss.UI.FlashTextMedium
    if not module or type(module.ShowPanelPreview) ~= "function" then
        error("FlashTextMediumPage requires FlashTextMedium unified renderer API", 2)
    end
    return module
end

local function TestFlashText()
    GetFlashText():Show({ text = L["中字提示测试文字"], duration = 1.5 })
end

local COMMON_OPTS = {
    bindRoot = true, poolType = "FlashTextMediumModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
        { path = "flashDuration", type = "slider", label = L["持续时间(秒)"], min = 0.5, max = 6, step = 0.5, row = 2 },
        { key = "test", type = "button", label = L["测试文字公告"], onClick = TestFlashText, row = 2 },
    },
}
local ANCHOR_OPTS = GetFlashText():GetStandardAnchorGroupOptions()
if type(ANCHOR_OPTS) ~= "table" then
    error("FlashTextMediumPage requires standard AnchorController group options", 2)
end
local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["文字公告(中)"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 30, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 43, w = 200, h = 25, measure = true, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "font_text", type = "fontgroup", x = 1, y = 71, w = 200, h = 50, label = L["文字公告(中)"], labelSize = 20,
        opts = { unboundedWidth = true } },
}
ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

-- 页面只声明既有布局、样本入口和 Slider 合同；Dock、Scroll、Watch、延迟
-- Render、ActivePage 所有权与 OnHide/release 均由 StandardModulePage 统一拥有。
local function RenderStandardPreview(dock)
    GetFlashText():ShowPanelPreview(dock)
end

local function ReleaseStandardPreview()
    local module = ExBoss.UI and ExBoss.UI.FlashTextMedium
    if module and type(module.ReleasePanelPreview) == "function" then module:ReleasePanelPreview() end
end

local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = LAYOUT,
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
        local module = GetFlashText()
        local contract = module.StandardSliderContract
        if type(contract) ~= "table" then error("FlashTextMedium standard Slider contract is unavailable", 2) end
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
