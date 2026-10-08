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
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"] },
        { path = "flashDuration", type = "slider", label = L["持续时间(秒)"], min = 0.5, max = 6, step = 0.5 },
        { key = "test", type = "button", label = L["测试文字公告"], onClick = TestFlashText },
    },
}
local ANCHOR_OPTS = GetFlashText():GetStandardAnchorGroupOptions()
if type(ANCHOR_OPTS) ~= "table" then
    error("FlashTextMediumPage requires standard AnchorController group options", 2)
end
-- [普通 sections 声明边界：FlashTextMedium 设置页]
-- Core 统一测量和排列；本页仅声明原复合控件及其语义选项。
-- 禁止：修改 key/type/path、语义 opts、测试按钮回调、预览、Slider 或释放合同。
-- modulecommonsettings/anchorgroup/fontgroup 是完整组合，不能拆成原子控件重拼。
local LAYOUT = {
    version = 1,
    title = L["文字公告(中)"],
    sections = {
        { kind = "composite", id = "module-common", title = L["通用设置"],
            component = "modulecommonsettings", key = "moduleCommon", opts = COMMON_OPTS },
        { kind = "composite", id = "anchor", title = L["锚点设置"],
            component = "anchorgroup", key = "anchor", opts = ANCHOR_OPTS },
        { kind = "composite", id = "text-font", title = L["外观"],
            component = "fontgroup", key = "font_text", opts = { unboundedWidth = true } },
    },
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

-- [生命周期边界] StandardModulePage 继续拥有 Scroll、Watch、预览与 release；布局迁移不得另建页面外壳。
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
