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

-- [卡片/Grid 迁移边界：BunBar 设置页]
-- 允许：普通 sections 单声明及纯展示排列；Core 统一测量，原语义选项保留。
-- 禁止：修改 key/type/path/opts、字段业务次序、external-left 预览、回调或释放链。
-- modulecommonsettings/anchorgroup/icongroup/fontgroup 必须整体引用；旧背景/标题项不自动拥有相邻控件。
local LAYOUT = {
    version = 1,
    title = L["束状条设置"],
    sections = {
        { kind = "settings", id = "timeline-enabled", title = L["时间轴样式选择"],
            binding = { moduleKey = "ExBoss.GeneralOverview", getConfig = function() return _G.EXBOSS12S2 end },
            items = { { key = "bun", type = "switch", label = L["启用"], parentKey = "ui.general.timelineBars" } } },
        { kind = "composite", id = "module-common", title = L["通用设置"],
            component = "modulecommonsettings", key = "moduleCommon", opts = COMMON_OPTS },
        { kind = "composite", id = "anchor", title = L["锚点设置"],
            component = "anchorgroup", key = "anchor", opts = ANCHOR_OPTS },
        { kind = "composite", id = "main-icon", title = L["外观"],
            component = "icongroup", key = "icon", opts = {} },
        { kind = "composite", id = "alert-icons", title = L["业务提示 Atlas"],
            component = "icongroup", key = "alertIcons", opts = { enableOffset = true } },
        { kind = "composite", id = "spell-font", title = L["法术名称"],
            component = "fontgroup", key = "font_spell", opts = {} },
        { kind = "composite", id = "timer-font", title = L["图标倒数时间"],
            component = "fontgroup", key = "font_timer", opts = {} },
    },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

local function RebindModuleCommon(context)
    -- state.widgets 的 moduleCommon key 是组合控件身份；迁移后仍按同 key 查找，不能按视觉位置推断。
    local common = context.grid and context.grid.FindMountedWidget
        and context.grid:FindMountedWidget(context.scrollChild, "moduleCommon")
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

-- [生命周期边界] StandardModulePage 继续拥有 Dock、Scroll、Watch、Grid focus 与 preview release；布局迁移不得改这些回调。
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

function Page:RefreshTimelineBarControls()
    local control = StandardPage.cardSession and StandardPage.cardSession:GetWidget("timeline-enabled", "bun")
    if control then control:SetChecked(ExBoss.DisplayPolicy.IsTimelineBarEnabled("bun")) end
end
