---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/CastProgressBarPage.lua
-- 设置页只承载 V2 声明与 EXUI 唯一标准预览面板。
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

-- 保留原设置块次序与组合控件身份；运行期锚点选项由 owner 提供。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "module-common", title = L["通用"],
            children = {
                { kind = "component", id = "moduleCommon", component = "modulecommonsettings", path = "moduleCommon", opts = COMMON_OPTS },
            } },
        { kind = "card", id = "anchor-card", title = L["锚点"],
            children = {
                { kind = "component", id = "anchor", component = "anchorgroup", path = "anchor", optionsRef = "anchor" },
            } },
        { kind = "card", id = "timer-bar", title = L["外观"],
            children = {
                { kind = "component", id = "timerGroup", component = "timerbargroup", path = "timerGroup", opts = {} },
            } },
        { kind = "card", id = "spell-font", title = L["法术名称"],
            children = {
                { kind = "component", id = "font_spell", component = "fontgroup", path = "font_spell", opts = {} },
            } },
        { kind = "card", id = "timer-font", title = L["时间文本"],
            children = {
                { kind = "component", id = "font_timer", component = "fontgroup", path = "font_timer", opts = {} },
            } },
    },
}

local function CreatePageOwner()
    return { options = { anchor = ANCHOR_GROUP_OPTS } }
end

local function RebindModuleCommon(context)
    local common = context.modulePage and context.modulePage:Find("moduleCommon")
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
    title = L["施法进度条设置"],
    layout = LAYOUT,
    ownerFactory = CreatePageOwner,
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
