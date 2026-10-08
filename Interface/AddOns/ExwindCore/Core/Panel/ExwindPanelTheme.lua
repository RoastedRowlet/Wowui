-- =========================================================
-- ExwindPanelTheme.lua
-- 三合一面板的唯一视觉与几何真源。
-- 本文件只定义 Shell token；不读取 Provider 数据、不创建业务控件。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local GC = ExwindTools.GUIColors
if not GC then error("ExwindGUIColor.lua must load before ExwindPanelTheme.lua") end

ExwindTools.PanelTheme = ExwindTools.PanelTheme or {
    Layout = {
        APP_RAIL_WIDTH = 58,
        HEADER_HEIGHT = 26,
        -- Tab 只是路由切换，不应占用接近一列控件的垂直空间。
        TOP_TAB_HEIGHT = GC and ExwindTools.GUIMetrics.size.tabHeight or 38,
        TOP_TAB_FONT_SIZE = 14,
        CONTENT_GUTTER = 12,
        -- 所有 B+C 左右布局的唯一比例：B=25%，C=75%。不得由 Provider 覆写。
        NAV_RATIO = 0.25,
        PREVIEW_DOCK_HEIGHT = 160, -- 标准顶部预览外框最小高度，Shell 同时以此为上限
        SPLIT_CONTENT_GRID_COLS = 200,
        FULL_CONTENT_GRID_COLS = 64,
        DEFAULT_WIDTH = 1440,
        DEFAULT_HEIGHT = 900,
        MIN_WIDTH = 1100,
        MIN_HEIGHT = 700,
    },

    Color = {
        panel = GC.panel,
        rail = GC.shell.rail,
        header = GC.shell.header,
        nav = GC.shell.nav,
        content = GC.panel,
        card = GC.shell.card,
        cardAlt = GC.shell.cardAlt,
        border = GC.shell.border,
        borderSoft = GC.shell.borderSoft,
        text = GC.shell.text,
        muted = GC.shell.muted,
        quiet = GC.shell.quiet,
        cyan = GC.shell.cyan,
        violet = GC.shell.violet,
        gold = GC.shell.gold,
        success = { 0.23, 0.85, 0.61, 1 },
        danger = { 0.95, 0.40, 0.47, 1 },
    },

    -- Compatibility geometry token. Runtime card appearance is owned by
    -- EXUI:ApplyControlAppearance so Grid and PanelTheme cannot compete.
    GridCard = {
        accentWidth = 4,
        contentInsetLeft = 8,
    },

    Backdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    },
}

-- Legacy entrypoint retained for callers outside Grid. `style` is deliberately
-- ignored: the shared control appearance is the sole visual authority.
function ExwindTools.PanelTheme.ApplyGridCardStyle(frame, style)
    if not frame then return end
    local EXUI = ExwindTools.UI
    if EXUI and EXUI.ApplyControlAppearance then
        return EXUI:ApplyControlAppearance(frame)
    end
end
