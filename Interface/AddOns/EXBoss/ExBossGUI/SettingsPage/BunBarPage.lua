---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- BunBar settings is a declaration-only StandardModulePage.  EXUI owns its
-- standard top PreviewDock, lifecycle, state watch, V2 focus and Slider paths.

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
    { path = "moveDir", type = "dropdown", label = L["移动方向"], items = { { L["向上"], "UP" }, { L["向下"], "DOWN" } } },
    { path = "font_spell.side", type = "dropdown", label = L["名称位置"], items = { { L["图标左边"], "LEFT" }, { L["图标右边"], "RIGHT" } } },
    { path = "hideLongTimersSeconds", type = "slider", label = L["隐藏几秒以上的"], min = 1, max = 60, step = 1 },
    { path = "width", type = "slider", label = L["轨道长度"], min = 200, max = 1400, step = 1 },
    { path = "trackHeight", type = "slider", label = L["轨道宽度"], min = 5, max = 90, step = 1 },
    { path = "fiveSecLineWidth", type = "slider", label = L["5秒线粗细"], min = 1, max = 8, step = 1 },
    { path = "fiveSecLineColor", type = "color", label = L["5秒线颜色"] },
    { path = "bgSettings.texture", type = "lsm_background", label = L["背景材质"] },
    { path = "bgSettings.bgColor", type = "color", label = L["背景颜色"] },
    { path = "bgSettings.showBorder", type = "checkbox", label = L["启用轨道边框"] },
    { path = "bgSettings.borderTexture", type = "lsm_border", label = L["边框材质"] },
    { path = "bgSettings.borderColor", type = "color", label = L["边框颜色"] },
    { path = "bgSettings.edgeSize", type = "slider", label = L["边框粗细"], min = 1, max = 32, step = 1 },
    { path = "bgSettings.inset", type = "slider", label = L["边框内距"], min = 0, max = 16, step = 1 },
}

local COMMON_OPTS = {
    bindRoot = true,
    poolType = "BunBarModuleCommonSettingsGroup",
    fields = COMMON_FIELDS,
}

-- 保留原设置块次序与组合控件身份；运行期锚点选项由 owner 提供。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "timeline-enabled", title = L["时间轴样式选择"],
            children = {
                { kind = "control", id = "bun", controlType = "switch", ref = "timelineEnabled" },
            } },
        { kind = "card", id = "module-common", title = L["通用设置"],
            children = {
                { kind = "component", id = "moduleCommon", component = "modulecommonsettings", path = "moduleCommon", opts = COMMON_OPTS },
            } },
        { kind = "card", id = "anchor-card", title = L["锚点设置"],
            children = {
                { kind = "component", id = "anchor", component = "anchorgroup", path = "anchor", optionsRef = "anchor" },
            } },
        { kind = "card", id = "main-icon", title = L["外观"],
            children = {
                { kind = "component", id = "icon", component = "icongroup", path = "icon", opts = {} },
            } },
        { kind = "card", id = "alert-icons", title = L["业务提示 Atlas"],
            children = {
                { kind = "component", id = "alertIcons", component = "icongroup", path = "alertIcons", opts = { enableOffset = true } },
            } },
        { kind = "card", id = "spell-font", title = L["法术名称"],
            children = {
                { kind = "component", id = "font_spell", component = "fontgroup", path = "font_spell", opts = {} },
            } },
        { kind = "card", id = "timer-font", title = L["图标倒数时间"],
            children = {
                { kind = "component", id = "font_timer", component = "fontgroup", path = "font_timer", opts = {} },
            } },
    },
}

local function CreatePageOwner()
    return {
        options = { anchor = ANCHOR_OPTS },
        controls = {
            timelineEnabled = EXUI:CreateSettingsV2Control({ controlType = "switch", label = L["启用"] }, function()
                return EXUI:CreateSettingsV2Binding("ExBoss.GeneralOverview", _G.EXBOSS12S2, "ui.general.timelineBars.bun")
            end),
        },
    }
end

local function RebindModuleCommon(context)
    local common = context.modulePage and context.modulePage:Find("moduleCommon")
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

-- StandardModulePage 继续拥有 Dock、Scroll、回读、定位与 preview release。
local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    title = L["束状条设置"],
    layout = LAYOUT,
    ownerFactory = CreatePageOwner,
    preview = { height = 320, render = RenderPreview, refresh = RenderPreview, release = ReleasePreview },
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
    afterLayout = function(context)
        RebindModuleCommon(context)
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end

function Page:RefreshTimelineBarControls()
    return StandardPage:RefreshControls()
end
