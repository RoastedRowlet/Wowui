---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ExtraShieldBar 设置页：只声明既有 Grid 布局与标准合同入口。Dock、Scroll、
-- Watch、OnHide/release、Grid 回读均由 EXUI:CreateStandardModulePage 统一拥有。

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.UI.Panel.ExtraShieldBarPage = ExBoss.UI.Panel.ExtraShieldBarPage or {}
local Page = ExBoss.UI.Panel.ExtraShieldBarPage
local MODULE_KEY = "ExBoss.ExtraShieldBar"

local function GetExtraShieldBar()
    local module = ExBoss.UI and ExBoss.UI.ExtraShieldBar
    if not module or type(module.GetStandardAnchorGroupOptions) ~= "function"
        or type(module.ShowPanelPreview) ~= "function" then
        error("ExtraShieldBarPage requires ExtraShieldBar standard display contract", 2)
    end
    return module
end

local SHIELD_COMMON_OPTS = {
    bindRoot = true,
    poolType = "ExtraShieldBarModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
    },
}

-- 锚点字段、默认位置、FramePicker 与整体拖动全部由 Display 的唯一
-- ANCHOR_SCHEMA 返回；Page 不复制任何 DB key 或默认值。
local SHIELD_ANCHOR_OPTS = GetExtraShieldBar():GetStandardAnchorGroupOptions()
if type(SHIELD_ANCHOR_OPTS) ~= "table" then
    error("ExtraShieldBarPage requires standard AnchorGroup options", 2)
end

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["额外护盾条设置"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 9, w = 200, h = 20, label = L["模块通用设置"], opts = SHIELD_COMMON_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 31, w = 200, h = 20, measure = true, label = L["锚点设置"], opts = SHIELD_ANCHOR_OPTS },
    -- ExtraShield 是固定单条 Body；没有第二条可排列，故不凭空显示 layout 卡。
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 54, w = 200, h = 50, label = L["计时条外观"], labelSize = 20 },
    { key = "font_spell", type = "fontgroup", x = 1, y = 107, w = 200, h = 50, label = L["法术名称"], labelSize = 20 },
    { key = "font_timer", type = "fontgroup", x = 1, y = 160, w = 200, h = 50, label = L["数值文本"], labelSize = 20 },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

local function RenderStandardPreview(dock)
    GetExtraShieldBar():ShowPanelPreview(dock)
end

local function RefreshStandardPreview(dock)
    local module = GetExtraShieldBar()
    if type(module.RefreshPanelPreview) == "function" then
        module:RefreshPanelPreview(dock)
    else
        module:ShowPanelPreview(dock)
    end
end

local function ReleaseStandardPreview()
    local module = ExBoss.UI and ExBoss.UI.ExtraShieldBar
    if module and type(module.ReleasePanelPreview) == "function" then
        module:ReleasePanelPreview()
    end
end

local function RebindModuleCommon(grid, container, db)
    local state = grid and grid.ContainerStates and grid.ContainerStates[container]
    local group = state and state.widgets and state.widgets.moduleCommon
    if group and type(group.RebindDB) == "function" then group:RebindDB(db) end
end

local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    layout = LAYOUT,
    preview = {
        height = 160,
        render = RenderStandardPreview,
        refresh = RefreshStandardPreview,
        release = ReleaseStandardPreview,
    },
    applyScrollSkin = function(scrollFrame)
        if ExBoss.UI and type(ExBoss.UI.ApplyModernScrollBarSkin) == "function" then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
    end,
    sliderContract = function()
        local module = GetExtraShieldBar()
        local contract = module.StandardSliderContract
        if type(contract) ~= "table" then error("ExtraShieldBar standard Slider contract is unavailable", 2) end
        return {
            groupPaths = contract.groupPaths,
        }
    end,
    afterGridLayout = function(context)
        RebindModuleCommon(context.grid, context.scrollChild, context.config)
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end
