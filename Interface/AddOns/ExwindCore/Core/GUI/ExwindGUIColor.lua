-- Fixed colors for ExwindCore settings and configuration surfaces.
-- Dynamic/user-selected colors and runtime/business status colors do not belong here.
--
-- =========================================================================
-- 基底：Radix Slate (dark) 的 12 階骨架。
--   調校參數 {"c":10,"b":80,"l":13,"d":56,"h":261,"i":-10,"ib":-12}
--   = 色味 0.010、色相 261、整體亮度 +1.3、卡片階距 Δ5.0、
--     輸入框比卡片微凹 0.9、輸入框邊框比卡片邊框柔 1.2。
--
-- 階級用途沿用 Radix 規範：
--   1-2 背景 / 3-5 元件三態 / 6-8 邊框 / 9-10 實心填充 / 11-12 文字
-- 深藍統一交互填充、選中與焦點；選中文字用白色，淺藍保留前景強調。
-- =========================================================================
--
-- 實心藍的取捨。白字壓在藍底上的 WCAG 對比：
--     #0090ff (Radix blue-9)  3.26  未過 AA
--     #2870bd (Radix blue-8)  5.07  過 AA
-- true  = 所有實心填充統一用 #2870bd，白字與白勾都過 AA（建議）
-- false = 用較亮的 #0090ff，勾選框更跳，但主按鈕白字未達 AA
-- 主要按鈕漸層依 true 調校，切換 false 時須另調漸層。
local SOLID_AA = true
--
-- =========================================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local function Hex(r, g, b, a)
    return { r / 255, g / 255, b / 255, a == nil and 1 or a }
end

local function H(s, a)
    return Hex(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16), a)
end

-- =========================================================================
-- 原始值。每個都標了 CIE L*，改動時請維持相鄰階的距離。
-- =========================================================================
local C = {
    canvas    = "131619",  -- 最外層背景
    panel     = "171a1f",  -- 側欄 / 導覽 / 面板
    card      = "1c1f24",  -- 外卡
    cardAlt   = "202328",  -- L* 13.4   交替底色
    head      = "1f2328",  -- 卡片標題列 / 子卡
    ctrl      = "14171c",  -- 輸入框 / 次要按鈕
    ctrlHover = "1f2328",
    pop       = "23272c",  -- 彈出層，必須高於它蓋住的東西
    popSearch = "14171c",

    bSubtle   = "292d31",  -- 分隔線 / 子卡邊框 / 非互動邊框
    bDef      = "3b3f44",  -- 面板 / 外卡邊框
    bHover    = "4f5458",
    bStrong   = "686d72",
    iBorder   = "373b3f",  -- 輸入框邊框
    iHover    = "4b5054",

    text      = "d8dadc",
    dim       = "96989b",
    ph        = "6a6d71",
    dis       = "5b5f62",

    aFg       = "70b8ff",  -- L* 72.9   淺藍：前景、focus、圖示、裝飾條
    aText     = "c2e6ff",  -- L* 89.5   選中文字 / 卡片標題
    aBright   = "0090ff",  -- L* 59.1   Radix blue-9
    aSolid    = "2870bd",  -- L* 46.6   Radix blue-8，白字 5.07
    aHover    = "3b9eff",  -- L* 63.8
    aDeep     = "1f5d9e",  -- 比 aSolid 再深一階，按下時用

    danger    = "ff9592",
    dangerB   = "e5484d",
    dangerHi   = "ffb3b0",  -- 危險按鈕懸停 / 按下文字
    dangerSoft = "7a363b",  -- 危險按鈕平常的暗紅外框

    ccSelected = "1d2530",  -- 勾選卡片選中底色

    thumb      = "c2c6cc",  -- 滑桿滑塊一般
    thumbDown  = "adb2b8",  -- 滑桿滑塊拖曳中

    -- 次要按鈕（B5）
    btnTop         = "272b31",
    btnBottom      = "202428",
    btnHoverTop    = "30363c",
    btnHoverBottom = "30363c",  -- 悬停：亮一档（方案 E）
    btnPressed     = "373e45",  -- 按下：比悬停再亮一点，不变暗（方案 E）

    -- 主要按鈕（白字對比皆 ≥ 4.46，依 SOLID_AA = true 調校）
    priTop         = "2e77c6",
    priHoverTop    = "3178ce",
    priHoverBottom = "2d74c3",

    -- 危險按鈕・灰底紅字 懸停 / 按下
    dgHoverTop     = "30363c",
    dgHoverBottom  = "30363c",
    dgPressed      = "373e45",  -- 按下：比悬停再亮一点，不变暗（方案 E）

    -- 危險按鈕・紅色實心（只用在最後確認對話框，白字對比 ≥ 4.9）
    dsTop          = "c4434a",
    dsBottom       = "b93a3f",
    dsHoverTop     = "ca484e",
    dsHoverBottom  = "bf3e43",
    dsPressed      = "a8343a",
    -- 狀態色：成功（綠）。資訊用既有的藍，錯誤用既有的紅
    okFg       = "4cc38a",  -- 成功文字 / 圖示，壓在卡片上對比 7.46
    okBorder   = "235c43",  -- 成功提示外框
    okSolid    = "218358",  -- 成功實心（白字對比 4.72），預留，本批未使用
    infoBorder = "24476b",  -- 資訊提示外框
    errBorder  = "6b2f33", -- 錯誤提示外框；與 infoBorder / okBorder 同檔亮度

}

-- 實心填充三態，由 SOLID_AA 決定
local SOLID        = SOLID_AA and C.aSolid  or C.aBright
local SOLID_HOVER  = SOLID_AA and "3b88d8" or C.aHover
local SOLID_ACTIVE = SOLID_AA and C.aDeep   or C.aSolid

-- 疊層用中性灰 + alpha，在深底上比純白 alpha 穩定
local function NeutralA(a) local c = H(C.dim);    return { c[1], c[2], c[3], a } end
local function AccentA(a)  local c = H(SOLID);    return { c[1], c[2], c[3], a } end
local function DangerA(a)  local c = H(C.danger); return { c[1], c[2], c[3], a } end

local function WhiteA(a) return { 1, 1, 1, a } end
local function BlackA(a) return { 0, 0, 0, a } end

ExwindTools.GUIColors = {
    -- ---------- 表面 ----------
    page            = H(C.canvas),
    panel           = H(C.panel),
    panelBorder     = H(C.bDef),
    header          = H(C.head),
    headerHover     = H(C.bSubtle),
    headerDivider   = H(C.bSubtle),
    card            = H(C.card),
    cardBorder      = H(C.bDef),
    cardHoverBorder = H(C.bHover), -- [改] 原 H(SOLID_HOVER)
    subcard         = H(C.head),
    subcardBorder   = H(C.bSubtle),
    subcardHoverBorder = H(C.bHover), -- [改] 原 H(SOLID_HOVER)
    sectionDivider  = H(C.bSubtle),
    rowHover        = AccentA(0.08),

    -- ---------- 文字 ----------
    text            = H(C.text),
    textDim         = H(C.dim),
    textPlaceholder = H(C.ph),
    textDisabled    = H(C.dis),
    white           = Hex(0xff, 0xff, 0xff),
    transparent     = { 0, 0, 0, 0 },

    -- ---------- 強調色 ----------
    accent       = H(C.aFg),
    accentHover  = H(C.aText),
    accentActive = H(C.aHover),
    selectedText = WhiteA(1),
    focusRing    = H(SOLID),
    modifiedBorder = H(SOLID),

    primaryFill       = H(SOLID),
    primaryFillHover  = H(SOLID_HOVER),
    primaryFillActive = H(SOLID_ACTIVE),
    primaryText       = Hex(0xff, 0xff, 0xff),

    -- ---------- 輸入框 ----------
    input               = H(C.ctrl),
    inputBorder         = H(C.iBorder),
    inputHover          = H(C.ctrlHover),
    inputHoverBorder    = H(C.iHover), -- [改] 原 H(SOLID_HOVER)
    inputFocusBorder    = H(SOLID),       -- 深蓝试色；原 H(C.aFg) / #70b8ff
    inputDisabled       = H(C.ctrl),
    inputDisabledBorder = H(C.bSubtle),

    -- ---------- 彈出層 ----------
    popup             = H(C.pop),
    popupBorder       = H(C.bDef), -- [改] 原 H(C.aFg)
    popupSearch       = H(C.popSearch),
    popupSearchBorder = H(C.iBorder), -- [改] 原 H(C.aFg)
    popupDivider      = H(C.bSubtle),
    menuHover         = NeutralA(0.10), -- [改] 原 AccentA(0.08)
    listSelected      = AccentA(0.13), -- 列表与技能卡使用主色半透明选中底色
    menuSelected      = H(SOLID), -- [改] 原 AccentA(0.13)
    menuSelectedHover = H(SOLID_HOVER), -- [改] 原 AccentA(0.20)

    -- ---------- 滑桿 ----------
    -- 轨道是空的（不画已走过那一段的填充），所以悬停反馈全靠轨道自己换色：
    -- 常态灰 -> 悬停亮灰白 -> 拖动中近白。三档都是中性灰阶，不带蓝
    -- （用户 2026-10-05 推翻同日早些时候的主色系悬停：悬停变蓝是错的，应变高亮白）。
    -- 用的是既有文字灰阶 C.dim / C.text 两个亮度档，不是纯白，避免深底上刺眼；
    -- 不透明取值，不随卡片／子卡／输入框底色变化。拖块仍是蓝色（sliderKnob 一族，
    -- 本次未改），所以拖动时靠色相而不是靠明暗区分轨道与拖块。
    sliderTrack       = H(C.bHover),
    sliderTrackHover  = H(C.dim),
    sliderTrackActive = H(C.text),
    sliderThumb       = H(C.aFg),
    sliderThumbHover  = H(C.aText),
    sliderThumbActive = H(C.aHover),

    -- ---------- 核取方塊 ----------
    checkboxBorder        = H(C.iHover),
    checkboxHoverBorder   = H(C.bStrong), -- [改] 原 H(SOLID_HOVER)
    checkboxChecked       = H(SOLID),
    checkboxCheckedHover  = H(SOLID_HOVER),
    checkboxCheckedActive = H(SOLID_ACTIVE),
    disabledFill          = H(C.ctrl),
    disabledBorder        = H(C.bSubtle),
    switchOn              = H(SOLID),
    switchOnHover         = H(SOLID_HOVER),
    switchOff             = H(C.bHover),
    switchOffHover        = AccentA(0.13),
    switchKnobOn          = Hex(0xff, 0xff, 0xff),
    switchKnobOff         = H(C.dim),

    -- ---------- 選項 / 分段 / 工具狀態 ----------
    tagBorder        = H(C.bDef),
    tagText          = H(C.dim),
    tagHoverBorder   = H(C.bHover), -- [改] 原 H(SOLID_HOVER)
    tagHoverText     = H(C.text),
    tagSelected      = AccentA(0.13),
    tagSelectedBorder = H(SOLID), -- [改] 原 H(C.aFg)
    tagSelectedText  = WhiteA(1),
    tagSelectedHover = AccentA(0.20),
    segmentSelected  = H(SOLID), -- [改] 原 AccentA(0.13)
    segmentText      = H(C.dim),
    toolHover        = AccentA(0.08),
    toolActive       = NeutralA(0.16),
    toolOn           = AccentA(0.13),

    -- ---------- 次要 / 危險 ----------
    secondaryFill        = H(C.btnBottom), -- [改] 原 H(C.ctrl)
    secondaryText        = H(C.text),
    secondaryBorder      = H(C.bDef),
    secondaryHoverFill   = H(C.btnHoverBottom), -- [改] 原 AccentA(0.13)
    secondaryHoverBorder = H("4c5157"), -- 方案 E：描边亮一档； -- [改] 原 H(SOLID_HOVER)
    secondaryPressedFill = H(C.btnPressed), -- [改] 原 H(C.bSubtle)
    secondaryPressedBorder = H("5a6067"), -- 按下：描边再亮
    secondaryPressedText = H(C.text), -- [改] 原 H(C.dim)
    dangerBorder      = H(C.dangerSoft), -- [改] 原 H(C.dangerB)
    dangerText        = H(C.danger),
    dangerHoverFill   = H(C.dgHoverBottom), -- [改] 原 DangerA(0.14)
    dangerPressedFill = H(C.dgPressed), -- [改] 原 DangerA(0.22)

    -- 勾選卡片（C1 角標）
    checkCard               = H(C.head), -- [新]
    checkCardBorder         = H(C.bSubtle), -- [新]
    checkCardHoverBorder    = H(C.bHover), -- [新]
    checkCardSelected       = H(C.ccSelected), -- [新]
    checkCardSelectedBorder = H(SOLID), -- [新]
    checkCardCorner         = H(SOLID), -- [新]
    checkCardCornerCheck    = Hex(0xff, 0xff, 0xff), -- [新]
    checkCardText           = H(C.dim), -- [新]
    checkCardSelectedText   = Hex(0xff, 0xff, 0xff), -- [新]
    checkCardDesc           = H(C.dim), -- [新]

    -- 彈出層 / 下拉選單
    popupShadow       = BlackA(0.55), -- [新]
    menuSelectedText  = Hex(0xff, 0xff, 0xff), -- [新]
    menuCheck         = Hex(0xff, 0xff, 0xff), -- [新]

    -- 下拉選單試聽圖示（音波）
    menuPreviewIcon          = H(C.text), -- [新]
    menuPreviewIconRow       = H(C.dim), -- [新]
    menuPreviewIconHover     = Hex(0xff, 0xff, 0xff), -- [新]
    menuPreviewPlaying       = H(SOLID), -- [新]
    menuPreviewSelected      = WhiteA(0.75), -- [新]
    menuPreviewSelectedHover = Hex(0xff, 0xff, 0xff), -- [新]

    -- 滑桿
    sliderThumbShadow = BlackA(0.60), -- [新]
    -- 现行滑条拖块：深蓝；按下不再变暗，只比常态略亮；轨道保持灰色 sliderTrack。
    sliderKnob        = H(SOLID),
    sliderKnobHover   = H("3582d4"),
    sliderKnobPressed = H("428ad7"),
    sliderThumbRing   = AccentA(0.20), -- [新]

    -- 分段選擇器
    segmentTrack        = H(C.ctrl), -- [新]
    segmentTrackBorder  = H(C.iBorder), -- [新]
    segmentSelectedText = Hex(0xff, 0xff, 0xff), -- [新]
    segmentHoverText    = H(C.text), -- [新]

    -- 按鈕共用
    buttonInset = BlackA(0.45), -- [新]

    -- 主要按鈕
    primaryTop            = H(C.priTop), -- [新]
    primaryBottom         = H(SOLID), -- [新]
    primaryHoverTop       = H(SOLID_HOVER), -- [新]
    primaryHoverBottom    = H(SOLID_HOVER), -- [新]
    primaryButtonHoverFill = H("3582d4"), -- 方案 E：悬停亮一档
    primaryPressedFill    = H("428ad7"),
    primaryPressedBorder  = H("2a7ed5"), -- [新]
    primaryBorder         = H(SOLID_ACTIVE), -- [新]
    primaryHoverBorder    = H("256fbc"), -- [新]
    primaryHighlight      = WhiteA(0.14), -- [新]
    primaryHoverHighlight = WhiteA(0.18), -- [新]

    -- 次要按鈕
    secondaryTop            = H(C.btnTop), -- [新]
    secondaryBottom         = H(C.btnBottom), -- [新]
    secondaryHoverTop       = H(C.btnHoverTop), -- [新]
    secondaryHoverBottom    = H(C.btnHoverBottom), -- [新]
    secondaryHoverText      = H(C.text), -- [新]
    secondaryHighlight      = WhiteA(0.06), -- [新]
    secondaryHoverHighlight = WhiteA(0.09), -- [新]

    -- 危險按鈕・灰底紅字
    dangerTop            = H(C.btnTop), -- [新]
    dangerBottom         = H(C.btnBottom), -- [新]
    dangerHoverTop       = H(C.dgHoverTop), -- [新]
    dangerHoverBottom    = H(C.dgHoverBottom), -- [新]
    dangerHoverBorder    = H("934147"),
    dangerPressedBorder  = H("a84a51"), -- [新]
    dangerHoverText      = H(C.danger), -- [新]
    dangerHighlight      = WhiteA(0.06), -- [新]
    dangerHoverHighlight = WhiteA(0.08), -- [新]

    -- 危險按鈕・紅色實心
    dangerSolidTop            = H(C.dsTop), -- [新]
    dangerSolidBottom         = H(C.dsBottom), -- [新]
    dangerSolidHoverTop       = H(C.dsHoverTop), -- [新]
    dangerSolidHoverBottom    = H(C.dsHoverBottom), -- [新]
    dangerSolidPressedFill    = H(C.dsPressed), -- [新]
    dangerSolidBorder         = H(C.dsPressed), -- [新]
    dangerSolidHoverBorder    = H(C.dsBottom), -- [新]
    dangerSolidText           = Hex(0xff, 0xff, 0xff), -- [新]
    dangerSolidHighlight      = WhiteA(0.14), -- [新]
    dangerSolidHoverHighlight = WhiteA(0.18), -- [新]
    -- 頁籤（T1）
    tabText          = H(C.dim), -- [新]
    tabHoverText     = H(C.text), -- [新]
    tabSelectedText  = Hex(0xff, 0xff, 0xff), -- [新]
    tabIndicator     = H(SOLID), -- 主色深藍（原 H(C.aFg)）      -- 主色指示條，高度見 GM.size.tabIndicatorHeight -- [新]
    tabDivider       = H(C.bSubtle), -- [新]

    -- 三态筛选 Chip（CreateTriStateChip）的语义主色；真源在此，控件不再写死 RGBA。
    triInclude       = { 0.30, 0.78, 0.48, 1 }, -- 只看（include）
    triExclude       = { 0.933, 0.443, 0.502, 1 }, -- 排除（exclude）

    -- 選項組（G1）
    optionRow             = H(C.head), -- [新]
    optionRowBorder       = H(C.bSubtle), -- [新]
    optionRowHoverBorder  = H(C.bHover), -- [新]
    optionRowSelected     = H(C.ccSelected), -- [新]
    optionRowSelectedBorder = H(SOLID), -- [新]
    optionTitle           = H(C.text), -- [新]
    optionTitleSelected   = Hex(0xff, 0xff, 0xff), -- [新]
    optionDesc            = H(C.dim), -- [新]
    radioBorder           = H(C.iHover), -- [新]
    radioHoverBorder      = H(C.bStrong), -- [新]
    radioSelected         = H(SOLID), -- [新]
    radioDot              = Hex(0xff, 0xff, 0xff), -- [新]

    -- 確認彈窗（D1）
    dialog         = H(C.pop), -- [新]
    dialogBorder   = H(C.bDef), -- [新]
    dialogShadow   = BlackA(0.55), -- [新]
    dialogOverlay  = { 8 / 255, 10 / 255, 12 / 255, 0.60 }, -- [新]
    dialogTitle    = Hex(0xff, 0xff, 0xff), -- [新]
    dialogText     = H(C.dim), -- [新]

    -- 狀態提示（S1）
    statusInfoFg     = H(C.aFg), -- [新]
    statusInfoBorder = H(C.infoBorder), -- [新]
    statusInfoTint   = { H(C.aFg)[1], H(C.aFg)[2], H(C.aFg)[3], 0.10 }, -- [新]
    statusOkFg       = H(C.okFg), -- [新]
    statusOkBorder   = H(C.okBorder), -- [新]
    statusOkTint     = { H(C.okFg)[1], H(C.okFg)[2], H(C.okFg)[3], 0.10 }, -- [新]
    statusErrFg      = H(C.danger), -- [新]
    statusErrBorder  = H(C.errBorder), -- [新]
    statusErrTint    = DangerA(0.10), -- [新]
    statusDesc       = H(C.dim), -- [新]
    statusNoticeBase = H(C.card), -- 頁內狀態提示的合成基底
    toast            = H(C.pop),       -- Toast 底色，上面再疊對應的 Tint -- [新]
    toastShadow      = BlackA(0.55), -- [新]

    -- 右鍵選單（R3）
    contextMenu          = H(C.pop), -- [新]
    contextMenuBorder    = H(C.bDef), -- [新]
    contextMenuShadow    = BlackA(0.55), -- [新]
    contextMenuTitle     = H(C.ph), -- [新]
    contextMenuText      = H(C.text), -- [新]
    contextMenuIcon      = H(C.dim), -- [新]
    contextMenuHover     = NeutralA(0.10), -- [新]
    contextMenuDivider   = H(C.bSubtle), -- [新]
    contextMenuDanger    = H(C.danger), -- [新]
    contextMenuDangerHover = DangerA(0.10), -- [新]
    contextMenuDisabled  = H(C.dis), -- [新]
    contextMenuCheck     = WhiteA(1), -- [新]

    -- ---------- FontString 內嵌色 ----------
    markup = {
        accent       = "|cff" .. C.aFg,
        selectedText = "|cffffffff",
        text         = "|cff" .. C.text,
        textDim      = "|cff" .. C.dim,
        placeholder  = "|cff" .. C.ph,
        textDisabled = "|cff" .. C.dis,
        danger       = "|cff" .. C.danger,
        ok           = "|cff" .. C.okFg,
    },

    -- ---------- Shell ----------
    -- 六個原本重複的 divider 全部指向同一個 borderSoft。
    shell = {
        rail       = H(C.panel),
        header     = H(C.panel),
        nav        = H(C.panel),
        card       = H(C.card),
        cardAlt    = H(C.cardAlt),        -- 不再與 card 同值
        border     = H(C.bDef),
        borderSoft = H(C.bSubtle),
        text       = H(C.text),
        muted      = H(C.dim),
        quiet      = H(C.ph),

        -- Provider 身分色，不屬於中性階梯，維持原值
        cyan   = { 0.28, 0.80, 0.91, 1 },
        violet = { 0.62, 0.55, 1.00, 1 },
        gold   = { 0.95, 0.77, 0.35, 1 },

        toolsSidebar        = H(C.panel),
        toolsSidebarBorder  = H(C.bDef),
        toolsSidebarDivider = H(C.bSubtle),
        toolsAmbientMask    = H(C.panel),
        toolsTopLine        = H(C.bSubtle),
        toolsBottomLine     = H(C.bSubtle),
        toolsRightPanel     = { 0, 0, 0, 0 },

        sidebarDisabledText = H(C.dis),
        sidebarDisabledRail = H(C.bSubtle),
        sidebarHoverText    = H(C.text),
        sidebarHoverRail    = H(C.bHover),
        sidebarIdleText     = H(C.dim),
        sidebarIdleRail     = H(C.bDef),

        railActive      = AccentA(0.13),
        railTransparent = { 0, 0, 0, 0 },
        railHover       = NeutralA(0.08),
    },
}

-- Shared interaction states. Colors remain defined above; controls only select states.
local G = ExwindTools.GUIColors
local disabled = { fill=G.disabledFill, border=G.disabledBorder, text=G.textDisabled }
local option = {
    normal={fill=G.transparent, border=G.tagBorder, text=G.tagText},
    hover={fill=G.toolHover, border=G.tagHoverBorder, text=G.tagHoverText},
    pressed={fill=G.primaryFillActive, border=G.focusRing, text=G.white},
    selected={fill=G.segmentSelected, border=G.focusRing, text=G.selectedText},
    disabled=disabled,
}
local secondary = {
    normal={fill=G.secondaryFill, border=G.secondaryBorder, text=G.secondaryText},
    hover={fill=G.secondaryHoverFill, border=G.secondaryHoverBorder, text=G.secondaryHoverText},
    pressed={fill=G.secondaryPressedFill, border=G.secondaryPressedBorder, text=G.secondaryPressedText},
    selected=option.selected, disabled=disabled,
}
local sidebar = {
    normal={fill=G.transparent, border=G.transparent, text=G.shell.sidebarIdleText},
    -- 悬停＝与 EXBoss 首领页首领行同一基准（用户 2026-10-05 要求各处左侧列表统一）：
    -- 只把底色抬一层中性灰叠层 menuHover，不加任何描边。原来用的
    -- secondaryHoverFill（不透明 #30363C）更亮一档、且画器额外加一圈主色描边，
    -- 与基准不一致，也容易被看成选中，故一并取消。
    hover={fill=G.menuHover, border=G.transparent, text=G.shell.sidebarHoverText},
    pressed={fill=G.menuHover, border=G.transparent, text=G.shell.sidebarHoverText},
    -- 侧栏选中＝只描边（用户 2026-10-05 推翻同月 4 日的“主色淡底 + 左侧 3px 指示条 + 纯白字”）：
    -- 底色不动，只加一圈主色描边，文字用常规正文色。这是唯一呈现，没有第二套。
    selected={fill=G.transparent, border=G.primaryFill, text=G.text},
    disabled={fill=G.transparent, border=G.transparent, text=G.shell.sidebarDisabledText},
}
ExwindTools.GUIStates = {
    button=secondary, option=option, pill=option, tab=option,
    danger={
        normal={fill=G.dangerBottom, border=G.dangerBorder, text=G.dangerText},
        hover={fill=G.dangerHoverBottom, border=G.dangerHoverBorder, text=G.dangerHoverText},
        pressed={fill=G.dangerPressedFill, border=G.dangerPressedBorder, text=G.dangerHoverText},
        disabled=disabled,
    },
    dangerSolid={
        normal={fill=G.dangerSolidBottom, border=G.dangerSolidBorder, text=G.dangerSolidText},
        hover={fill=G.dangerSolidHoverBottom, border=G.dangerSolidHoverBorder, text=G.dangerSolidText},
        pressed={fill=G.dangerSolidPressedFill, border=G.dangerSolidHoverBorder, text=G.dangerSolidText},
        disabled=disabled,
    },
    primary={
        normal={fill=G.primaryFill, border=G.primaryBorder, text=G.primaryText},
        hover={fill=G.primaryButtonHoverFill, border=G.primaryHoverBorder, text=G.primaryText},
        pressed={fill=G.primaryPressedFill, border=G.primaryPressedBorder, text=G.primaryText},
        selected=option.selected, disabled=disabled,
    },
    sidebar=sidebar,
}
