---@diagnostic disable: undefined-global
local Tools = _G.ExwindTools
local EXUI = Tools.UI
local L = ExBoss.L
local Mod = ExBoss.UI.DungeonExtras
local KEY = "ExBoss.DungeonExtras"
local Page = {}
ExBoss.UI.Panel.DungeonExtrasPage = Page

local COMMON_OPTS = {
    bindRoot = true, poolType = "DungeonExtrasCommonSettingsGroup",
    fixedLayout = { logicalWidth = 200, controlW = 190, controlH = 6, slotX = { 3 }, firstY = 0, rowStep = 14 },
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用副本额外提示"], row = 1 },
        { path = "rubyWindFire", type = "checkbox", label = L["红玉新生法池：尾王风火图"], row = 2 },
        { path = "altarTrashHealth", type = "checkbox", label = L["毒牙祭坛：指定小怪血量"], row = 3 },
        { path = "healthColor", type = "checkbox", label = L["血量条随剩余血量染色"], row = 4 },
    },
}
local LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["副本额外设置"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 64, label = L["已接管的副本提示"], opts = COMMON_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 76, w = 200, h = 20, measure = true, label = L["统一锚点"], opts = Mod:GetStandardAnchorGroupOptions() },
    { key = "layout", type = "widgetlayout", x = 1, y = 99, w = 200, h = 23, measure = true, label = L["血量条排列"],
        opts = { allowedDirections = { "UP", "DOWN" }, includeMaxPerRow = false, maxVisibleMin = 1, maxVisibleMax = 6, defaultMaxVisible = 6 } },
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 125, w = 200, h = 52, label = L["血量条外观"] },
    { key = "font_spell", type = "fontgroup", x = 1, y = 180, w = 200, h = 50, label = L["单位名称"] },
    { key = "font_timer", type = "fontgroup", x = 1, y = 233, w = 200, h = 50, label = L["血量百分比"] },
}
Tools:RegisterModuleLayout(KEY, LAYOUT)
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
