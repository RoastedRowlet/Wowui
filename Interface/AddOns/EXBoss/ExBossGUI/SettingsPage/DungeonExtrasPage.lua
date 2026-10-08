---@diagnostic disable: undefined-global
local Tools = _G.ExwindTools
local EXUI = Tools.UI
local L = ExBoss.L
local Mod = ExBoss.UI.DungeonExtras
local KEY = "ExBoss.DungeonExtras"
local Page = {}
ExBoss.UI.Panel.DungeonExtrasPage = Page

local COMMON_OPTS = {
    bindRoot = true,
    poolType = "DungeonExtrasCommonSettingsGroup",
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用副本额外提示"] },
        { path = "rubyWindFire", type = "checkbox", label = L["红玉新生法池：尾王风火图"] },
        { path = "altarTrashHealth", type = "checkbox", label = L["毒牙祭坛：指定小怪血量"] },
        { path = "healthColor", type = "checkbox", label = L["血量条随剩余血量染色"] },
    },
}
-- [卡片/Grid 迁移边界：DungeonExtras 设置页]
-- 允许：普通 sections 单声明及纯展示排列；Core 统一测量，原语义选项保留。
-- 禁止：修改业务开关 path/key、增长方向、StandardConfigBinding、预览或释放合同。
-- modulecommonsettings/anchorgroup/widgetlayout/timerBarGroup/fontgroup 必须整体引用；风火图业务样式不并入血量条卡片。
local LAYOUT = {
    version = 1,
    title = L["副本额外设置"],
    sections = {
        { kind = "composite", id = "module-common", title = L["通用"],
            component = "modulecommonsettings", key = "moduleCommon", opts = COMMON_OPTS },
        { kind = "composite", id = "layout", title = L["血量条排列"],
            component = "widgetlayout", key = "layout", opts = { allowedDirections = { "UP", "DOWN" }, includeMaxPerRow = false, maxVisibleMin = 1, maxVisibleMax = 6, defaultMaxVisible = 6 } },
        { kind = "composite", id = "anchor", title = L["锚点"],
            component = "anchorgroup", key = "anchor", opts = Mod:GetStandardAnchorGroupOptions() },
        { kind = "composite", id = "timer-bar", title = L["外观"],
            component = "timerbargroup", key = "timerGroup" },
        { kind = "composite", id = "spell-font", title = L["单位名称"],
            component = "fontgroup", key = "font_spell" },
        { kind = "composite", id = "timer-font", title = L["血量百分比"],
            component = "fontgroup", key = "font_timer" },
    },
}
Tools:RegisterModuleLayout(KEY, LAYOUT)
-- [生命周期边界] StandardModulePage 继续拥有 Scroll、preview 与 release；布局迁移不得另建页面生命周期。
local standardPage = EXUI:CreateStandardModulePage({
    moduleKey = KEY, page = Page, binding = Mod.StandardConfigBinding, layout = LAYOUT, getColumns = 200,
    preview = { height = 202,
        render = function(dock) Mod:ShowPanelPreview(dock) end,
        refresh = function() Mod:RefreshPanelPreview() end,
        release = function() Mod:ReleasePanelPreview() end },
    applyScrollSkin = function(scrollFrame) ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame) end,
    sliderContract = function()
        return { groupPaths = { moduleCommon = "", layout = "layout", timerGroup = "timerGroup", font_spell = "font_spell", font_timer = "font_timer" } }
    end,
})
function Page:Render(contentFrame) return standardPage:Render(contentFrame) end
function Page:Hide() return standardPage:Hide() end
