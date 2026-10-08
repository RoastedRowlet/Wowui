---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/CastProgressBarPage.lua
-- 设置页只承载 Grid 与 EXUI 唯一标准预览面板。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
ExBoss.UI.Panel.CastProgressBarPage = ExBoss.UI.Panel.CastProgressBarPage or {}
local Page = ExBoss.UI.Panel.CastProgressBarPage

local MODULE_KEY = "ExBoss.CastProgressBar"

local function GetCastProgressBar()
    return ExBoss.UI and ExBoss.UI.CastProgressBar
end

local function GetDB()
    local module = GetCastProgressBar()
    if not module or type(module.GetDB) ~= "function" then
        error("CastProgressBarPage requires CastProgressBar:GetDB", 2)
    end
    return module:GetDB()
end

local function GetAnchorGroupOptions()
    local module = GetCastProgressBar()
    if not module or type(module.GetAnchorGroupOptions) ~= "function" then
        error("CastProgressBarPage requires CastProgressBar:GetAnchorGroupOptions", 2)
    end
    return module:GetAnchorGroupOptions()
end

local ANCHOR_GROUP_OPTS = GetAnchorGroupOptions()

local SLIDER_GROUP_PATHS = {
    layout = "layout",
    timerGroup = "timerGroup",
    font_spell = "font_spell",
    font_timer = "font_timer",
}

-- 与 BunBar 共用的模块化首屏：把实际影响施法条整体行为的选项集中，
-- 条体与两组文字仍各自保留完整的专属编辑器。
local COMMON_OPTS = {
    bindRoot = true,
    poolType = "CastProgressBarModuleCommonSettingsGroup",
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"] },
        { path = "layout.direction", type = "dropdown", label = L["增长方向"], items = { { L["向上"], "UP" }, { L["向下"], "DOWN" } } },
        { path = "layout.maxVisible", type = "slider", label = L["最大显示"], min = 1, max = 5, step = 1 },
        { path = "layout.spacing", type = "slider", label = L["条目间距"], min = -24, max = 24, step = 1 },
        { path = "timerGroup.progressMode", type = "dropdown", label = L["进度方向"], items = { { L["剩余时间"], "REMAINING" }, { L["已过时间"], "ELAPSED" } } },
        { path = "timerGroup.iconSide", type = "dropdown", label = L["图标位置"], items = { { L["左侧"], "LEFT" }, { L["右侧"], "RIGHT" }, { L["居中"], "CENTER" } } },
        { path = "timerGroup.showIcon", type = "checkbox", label = L["显示图标"] },
        { path = "timerGroup.showBorder", type = "checkbox", label = L["显示边框"] },
    },
}

-- [卡片/Grid 迁移边界：CastProgressBar 设置页]
-- 允许：普通 sections 单声明及纯展示排列；Core 统一测量，原语义选项保留。
-- 禁止：修改 key/type/path/opts、字段业务次序、顶部预览内容、回调或释放链。
-- modulecommonsettings/anchorgroup/timerBarGroup/fontgroup 必须整体引用；旧背景/标题项不自动拥有相邻控件。
local GRID_LAYOUT = {
    version = 1,
    title = L["施法进度条设置"],
    sections = {
        { kind = "composite", id = "module-common", title = L["通用"],
            component = "modulecommonsettings", key = "moduleCommon", opts = COMMON_OPTS },
        { kind = "composite", id = "anchor", title = L["锚点"],
            component = "anchorgroup", key = "anchor", opts = ANCHOR_GROUP_OPTS },
        { kind = "composite", id = "timer-bar", title = L["外观"],
            component = "timerbargroup", key = "timerGroup" },
        { kind = "composite", id = "spell-font", title = L["法术名称"],
            component = "fontgroup", key = "font_spell" },
        { kind = "composite", id = "timer-font", title = L["时间文本"],
            component = "fontgroup", key = "font_timer" },
    },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, GRID_LAYOUT)

local function RebindModuleCommon(context)
    -- state.widgets.moduleCommon 是稳定组合控件入口，迁移后必须保留 key 查找语义。
    local common = context.grid and context.grid.FindMountedWidget
        and context.grid:FindMountedWidget(context.scrollChild, "moduleCommon")
    if common and type(common.RebindDB) == "function" then common:RebindDB(context.config) end
end

local function RenderCastProgressPanelPreview(dock)
    local module = GetCastProgressBar()
    if module and type(module.ShowPanelPreview) == "function" then
        module:ShowPanelPreview(dock)
    end
end

local function RefreshCastProgressPanelPreview(dock)
    local module = GetCastProgressBar()
    if module and type(module.RefreshPanelPreview) == "function" then
        module:RefreshPanelPreview(dock)
    end
end

local function ReleaseCastProgressPanelPreview()
    local module = GetCastProgressBar()
    if module and type(module.ReleasePanelPreview) == "function" then
        module:ReleasePanelPreview()
    end
end

-- [生命周期边界] StandardModulePage 继续拥有外置 Dock、Scroll、preview 与 release；布局迁移不得改这些回调。
local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = GRID_LAYOUT,
    getColumns = 200,
    preview = { height = 1, render = RenderCastProgressPanelPreview, refresh = RefreshCastProgressPanelPreview, release = ReleaseCastProgressPanelPreview },
    applyScrollSkin = function(scrollFrame)
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
    end,
    sliderContract = function()
        return {
            groupPaths = SLIDER_GROUP_PATHS,
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
