---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/CountdownPage.lua
-- Countdown 只声明既有 Grid 布局；Dock、Scroll、Watch、延迟 Render、释放和
-- Slider 生命周期均由 EXUI 标准合同拥有。Secret runtime 值绝不进入此页面。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
ExBoss.UI.Panel.CountdownPage = ExBoss.UI.Panel.CountdownPage or {}
local Page = ExBoss.UI.Panel.CountdownPage

local MODULE_KEY = "ExBoss.Countdown"

local function GetCountdown()
    local countdown = ExBoss.UI and ExBoss.UI.Countdown
    if not countdown
        or type(countdown.GetDB) ~= "function"
        or type(countdown.ShowPanelPreview) ~= "function"
        or type(countdown.RefreshPanelPreview) ~= "function"
        or type(countdown.ReleasePanelPreview) ~= "function" then
        error("CountdownPage requires Countdown standard renderer API", 2)
    end
    return countdown
end

-- 此对象由 Countdown View 的唯一 ANCHOR_SCHEMA 创建。Page 不得复制正式
-- *_1205 key、默认位置或 picker 映射；否则世界整体拖动与 AnchorGroup 会再次
-- 变成两份合同。
local countdown = GetCountdown()
if type(countdown.GetStandardAnchorGroupOptions) ~= "function" then
    error("CountdownPage requires Countdown standard anchor contract", 2)
end
local ANCHOR_OPTS = countdown:GetStandardAnchorGroupOptions()

local function TestCountdown()
    local countdown = ExBoss.UI and ExBoss.UI.Countdown
    if countdown and type(countdown.Show) == "function" then
        -- 固定普通样本；不读取或替换任何 runtime Secret 文本/图标。
        countdown:Show({
            displayName = L["坦克尖刺"],
            spellID = 46968,
            duration = 5,
            textMode = "NORMAL",
            iconMode = "NORMAL",
        })
    end
end

local COMMON_OPTS = {
    bindRoot = true,
    poolType = "CountdownModuleCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 46, controlH = 6, slotX = { 3, 53, 103, 153 }, firstY = 0, rowStep = 14 },
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"], row = 1 },
        { path = "showDecimal", type = "checkbox", label = L["显示小数点"], row = 1 },
        { path = "stackMax_1205", type = "slider", label = L["最大条数"], min = 1, max = 3, step = 1, row = 2 },
        { path = "stackGap", type = "slider", label = L["上下间距"], min = 0, max = 20, step = 1, row = 2 },
        { path = "growDir", type = "dropdown", label = L["生长方向"], items = { { L["向上生长"], "UP" }, { L["向下生长"], "DOWN" } }, row = 2 },
        { key = "test", type = "button", label = L["测试倒计时"], onClick = TestCountdown, row = 2 },
    },
}

local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["屏幕倒计时"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 64, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 77, w = 200, h = 25, measure = true, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "icon", type = "icongroup", x = 1, y = 105, w = 200, h = 50, label = L["图标外观"] },
    { key = "font_text", type = "fontgroup", x = 1, y = 158, w = 200, h = 50, label = L["提示文字"], labelSize = 20 },
    { key = "font_time", type = "fontgroup", x = 1, y = 211, w = 200, h = 50, label = L["倒计时数字"], labelSize = 20 },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

local function RebindCountdownModuleCommon(grid, container, db)
    local state = grid and grid.ContainerStates and grid.ContainerStates[container]
    local common = state and state.widgets and state.widgets.moduleCommon
    if common and type(common.RebindDB) == "function" then common:RebindDB(db) end
end

local function RenderStandardPreview(dock)
    GetCountdown():ShowPanelPreview(dock)
end

local function RefreshStandardPreview(dock)
    GetCountdown():RefreshPanelPreview(dock)
end

local function ReleaseStandardPreview()
    GetCountdown():ReleasePanelPreview()
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
        local contract = GetCountdown().StandardSliderContract
        if type(contract) ~= "table" then error("Countdown standard Slider contract is unavailable", 2) end
        return {
            groupPaths = contract.groupPaths,
        }
    end,
    afterGridLayout = function(context)
        RebindCountdownModuleCommon(context.grid, context.scrollChild, context.config)
    end,
})

function Page:Render(contentFrame)
    return StandardPage:Render(contentFrame)
end

function Page:Hide()
    return StandardPage:Hide()
end
