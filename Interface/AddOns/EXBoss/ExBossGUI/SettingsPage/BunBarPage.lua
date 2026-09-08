---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- BunBar settings is a declaration-only StandardModulePage.  EXUI owns its
-- external PreviewDock, lifecycle, state watch, Grid focus and Slider paths.

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.BunBarPage = ExBoss.UI.Panel.BunBarPage or {}
local Page = ExBoss.UI.Panel.BunBarPage
local MODULE_KEY = "ExBoss.BunBar"

local function GetBunBar()
    return ExBoss.UI and ExBoss.UI.BunBar
end

local bunBar = GetBunBar()
if not bunBar or type(bunBar.GetStandardAnchorGroupOptions) ~= "function" then
    error("BunBarPage requires BunBar standard anchor contract", 2)
end
local ANCHOR_OPTS = bunBar:GetStandardAnchorGroupOptions()

local COMMON_FIELDS = {
    { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
    { path = "moveDir", type = "dropdown", label = L["移动方向"], items = { { L["向上"], "UP" }, { L["向下"], "DOWN" } }, row = 2 },
    { path = "font_spell.side", type = "dropdown", label = L["名称位置"], items = { { L["图标左边"], "LEFT" }, { L["图标右边"], "RIGHT" } }, row = 2 },
    { path = "hideLongTimersSeconds", type = "slider", label = L["隐藏几秒以上的"], min = 1, max = 60, step = 1, row = 2, column = 4 },
    { path = "width", type = "slider", label = L["轨道长度"], min = 200, max = 1400, step = 1, row = 3 },
    { path = "trackHeight", type = "slider", label = L["轨道宽度"], min = 5, max = 90, step = 1, row = 3 },
    { path = "fiveSecLineWidth", type = "slider", label = L["5秒线粗细"], min = 1, max = 8, step = 1, row = 3 },
    { path = "fiveSecLineColor", type = "color", label = L["5秒线颜色"], row = 3 },
    { path = "bgSettings.texture", type = "lsm_background", label = L["背景材质"], row = 4 },
    { path = "bgSettings.bgColor", type = "color", label = L["背景颜色"], row = 4 },
    { path = "bgSettings.showBorder", type = "checkbox", label = L["启用轨道边框"], row = 4, column = 3 },
    { path = "bgSettings.borderTexture", type = "lsm_border", label = L["边框材质"], row = 5 },
    { path = "bgSettings.borderColor", type = "color", label = L["边框颜色"], row = 5 },
    { path = "bgSettings.edgeSize", type = "slider", label = L["边框粗细"], min = 1, max = 32, step = 1, row = 5 },
    { path = "bgSettings.inset", type = "slider", label = L["边框内距"], min = 0, max = 16, step = 1, row = 5 },
}

local COMMON_OPTS = {
    bindRoot = true,
    poolType = "BunBarModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = COMMON_FIELDS,
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["束状条设置"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 96, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 108, w = 200, h = 22, measure = true, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "icon", type = "icongroup", x = 1, y = 133, w = 200, h = 50, label = L["主图标外观"], opts = {} },
    { key = "alertIcons", type = "icongroup", x = 1, y = 186, w = 200, h = 50, label = L["业务提示 Atlas"], opts = { enableOffset = true } },
    { key = "font_spell", type = "fontgroup", x = 1, y = 239, w = 200, h = 50, label = L["法术名称"], labelSize = 20, opts = {} },
    { key = "font_timer", type = "fontgroup", x = 1, y = 292, w = 200, h = 50, label = L["图标倒数时间"], labelSize = 20, opts = {} },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

local function RebindModuleCommon(context)
    local state = context.grid and context.grid.ContainerStates and context.grid.ContainerStates[context.scrollChild]
    local common = state and state.widgets and state.widgets.moduleCommon
    if common and type(common.RebindDB) == "function" then common:RebindDB(context.config) end
end

local function RenderPreview(dock)
    local module = GetBunBar()
    if not module then error("BunBar preview module is unavailable", 2) end
    return module:ShowPanelPreview(dock)
end

local function ReleasePreview()
    local module = GetBunBar()
    if module then module:ReleasePanelPreview() end
end

local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = LAYOUT,
    getColumns = 200,
    preview = { height = 1, render = RenderPreview, refresh = RenderPreview, release = ReleasePreview },
    previewDock = {
        dockPolicy = "external-left",
        anchorResolver = function(contentFrame)
            local panel = ExBoss.UI and ExBoss.UI.Panel
            return (panel and panel._frame) or contentFrame:GetParent() or contentFrame
        end,
        width = 310, offsetX = -8, offsetY = 0,
    },
    applyScrollSkin = function(scrollFrame)
        if ExBoss.UI and type(ExBoss.UI.ApplyModernScrollBarSkin) == "function" then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
    end,
    sliderContract = function()
        local module = GetBunBar()
        local contract = module and module.StandardSliderContract
        if type(contract) ~= "table" then error("BunBar standard Slider contract is unavailable", 2) end
        return {
            groupPaths = contract.groupPaths,
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
