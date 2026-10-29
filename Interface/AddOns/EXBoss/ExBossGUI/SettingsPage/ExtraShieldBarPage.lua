---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- ExtraShieldBar 设置页：声明 V2 布局与标准合同入口。Dock、Scroll、
-- Watch、OnHide/release、组合控件回读均由 EXUI:CreateStandardModulePage 统一拥有。

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
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用"] },
    },
}

-- 锚点字段、默认位置、FramePicker 与整体拖动全部由 Display 的唯一
-- ANCHOR_SCHEMA 返回；Page 不复制任何 DB key 或默认值。
local SHIELD_ANCHOR_OPTS = GetExtraShieldBar():GetStandardAnchorGroupOptions()
if type(SHIELD_ANCHOR_OPTS) ~= "table" then
    error("ExtraShieldBarPage requires standard AnchorGroup options", 2)
end

-- 保留原设置块次序与组合控件身份；运行期锚点选项由 owner 提供。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "module-common", title = L["通用设置"],
            children = {
                { kind = "component", id = "moduleCommon", component = "modulecommonsettings", path = "moduleCommon", opts = SHIELD_COMMON_OPTS },
            } },
        { kind = "card", id = "anchor-card", title = L["锚点设置"],
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
        { kind = "card", id = "timer-font", title = L["数值文本"],
            children = {
                { kind = "component", id = "font_timer", component = "fontgroup", path = "font_timer", opts = {} },
            } },
    },
}

local function CreatePageOwner()
    return { options = { anchor = SHIELD_ANCHOR_OPTS } }
end

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

local function RebindModuleCommon(context)
    local group = context.modulePage and context.modulePage:Find("moduleCommon")
    if group and type(group.RebindDB) == "function" then group:RebindDB(context.config) end
end

-- [生命周期边界] StandardModulePage 继续拥有 Scroll、preview 与 release；布局迁移不得改这些回调。
local StandardPage = EXUI:CreateStandardModulePage({
    moduleKey = MODULE_KEY,
    page = Page,
    title = L["额外护盾条设置"],
    layout = LAYOUT,
    ownerFactory = CreatePageOwner,
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
