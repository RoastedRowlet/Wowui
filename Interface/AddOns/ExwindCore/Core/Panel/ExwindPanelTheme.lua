-- =========================================================
-- ExwindPanelTheme.lua
-- 三合一面板的唯一视觉与几何真源。
-- 本文件只定义 Shell token；不读取 Provider 数据、不创建业务控件。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExwindTools.PanelTheme = ExwindTools.PanelTheme or {
    Layout = {
        APP_RAIL_WIDTH = 58,
        HEADER_HEIGHT = 26,
        -- Tab 只是路由切换，不应占用接近一列控件的垂直空间。
        TOP_TAB_HEIGHT = 32,
        TOP_TAB_FONT_SIZE = 14,
        CONTENT_GUTTER = 12,
        -- 所有 B+C 左右布局的唯一比例：B=25%，C=75%。不得由 Provider 覆写。
        NAV_RATIO = 0.25,
        PREVIEW_DOCK_HEIGHT = 160,
        SPLIT_CONTENT_GRID_COLS = 200,
        FULL_CONTENT_GRID_COLS = 64,
        DEFAULT_WIDTH = 1440,
        DEFAULT_HEIGHT = 900,
        MIN_WIDTH = 1100,
        MIN_HEIGHT = 700,
    },

    Color = {
        panel = { 0.055, 0.070, 0.095, 0.985 },
        rail = { 0.065, 0.080, 0.110, 1 },
        header = { 0.055, 0.070, 0.095, 0.96 },
        nav = { 0.070, 0.090, 0.120, 1 },
        content = { 0.045, 0.058, 0.080, 1 },
        card = { 0.085, 0.105, 0.140, 0.96 },
        cardAlt = { 0.070, 0.086, 0.118, 0.94 },
        border = { 0.185, 0.225, 0.290, 1 },
        borderSoft = { 0.125, 0.155, 0.205, 0.92 },
        text = { 0.89, 0.92, 0.96, 1 },
        muted = { 0.56, 0.62, 0.70, 1 },
        quiet = { 0.34, 0.40, 0.48, 1 },
        cyan = { 0.28, 0.80, 0.91, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold = { 0.95, 0.77, 0.35, 1 },
        success = { 0.23, 0.85, 0.61, 1 },
        danger = { 0.95, 0.40, 0.47, 1 },
    },

    -- Grid 卡片的唯一外观规格。卡片可传入 accentColor / borderColor，
    -- 但结构（正方形卡片、左侧强调线）不能由业务页面各自发明。
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

local function EnsureCardTexture(frame, key, profile)
    local texture = frame[key]
    if not texture then
        texture = ExwindTools.UI:CreateVisualTexture(frame, profile or _G.EXBASEFRAME)
        frame[key] = texture
    end
    -- PanelTheme 在 VisualLayers 之前载入；调用发生在运行期，因此这里再取
    -- EXUI，避免加载顺序把 Theme 绑定到一套旧层级。
    local EXUI = ExwindTools.UI
    if EXUI and EXUI.ApplyVisualLayer then
        EXUI:ApplyVisualLayer(texture, profile or _G.EXBASEFRAME, frame)
    end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    return texture
end

-- Grid 的 card 元素从对象池取出后在此重新套用视觉。纹理属于卡片对象本身，
-- 因此复用时不会额外创建 Frame，也不会形成每次渲染新增的对象树。
function ExwindTools.PanelTheme.ApplyGridCardStyle(frame, style)
    if not frame then return end

    style = style or {}
    local spec = ExwindTools.PanelTheme.GridCard
    local bg = style.background or ExwindTools.PanelTheme.Color.cardAlt
    local border = style.border or ExwindTools.PanelTheme.Color.borderSoft
    local accent = style.accent or ExwindTools.PanelTheme.Color.cyan

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end

    -- 正方形卡片：仅左侧保留粗强调线；不要使用整圈外框或 glow。
    if frame.Accent then
        frame.Accent:ClearAllPoints()
        local EXUI = ExwindTools.UI
        if EXUI and EXUI.ApplyVisualLayer then
            EXUI:ApplyVisualLayer(frame.Accent, _G.EXBASEFRAME, frame)
        end
        frame.Accent:SetColorTexture(accent[1], accent[2], accent[3], accent[4] or 1)
        frame.Accent:SetWidth(spec.accentWidth)
        frame.Accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.Accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.Accent:Show()
    end

    -- 停用前一版整圈发光边框与拆分边线，避免对象池复用时残留。
    if frame._exCardFrameGlow then frame._exCardFrameGlow:Hide() end
    if frame._exCardTopEdge then frame._exCardTopEdge:Hide() end
    if frame._exCardRightEdge then frame._exCardRightEdge:Hide() end
    if frame._exCardBottomEdge then frame._exCardBottomEdge:Hide() end
    if frame._exCardGlowHost then frame._exCardGlowHost:Hide() end
    if frame._exCardTopGlow then frame._exCardTopGlow:Hide() end
    if frame._exCardRightGlow then frame._exCardRightGlow:Hide() end
    if frame._exCardBottomGlow then frame._exCardBottomGlow:Hide() end
end
