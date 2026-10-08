-- ExwindCore 设置界面的固定数值表：字号、间距、尺寸。
-- 只放纯数据；通用控件与页面专用字号均从本表读取。
-- 必须在 ExwindGUIColor.lua 之后、ExwindGUI.lua 之前加载。
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 默认控件高度：按钮、输入框、下拉触发器、颜色按钮、设置列表普通控件共用这一个值。
-- 只有声明里明确写了 height 的控件才可以不同。
local CONTROL_HEIGHT = 30

ExwindTools.GUIMetrics = {
    -- 圆角角色（视觉半径，像素；必须是 SetControlSurface 白名单 3/4/5/6/8/10 之一）。
    -- thumb：滑块拖块等小件；control：按钮/输入框/下拉/复选框/选项块；
    -- popup：下拉与右键菜单、预览外壳；dialog：确认框等对话框；card：卡片与面板。
    -- Switch 的轨道是整圆胶囊，半径由轨道高度推算，不占用角色。
    radius = { thumb = 3, control = 4, popup = 6, dialog = 8, card = 10 },

    -- 字号（像素）。
    font = {
        tools = { moduleTitle=20, profileTitle=23, profileLabel=14 },
        exboss = { micro=9, chipLabel=10, previewText=14, navigationTitle=16, spellListTitle=17, spellDetailTitle=21 },
        mythicStats = { caption=12, small=14, label=15, column=16, heading=18, row=20, stat=24, summary=32, playerName=44, score=72 },
        pageTitle = 24,   -- 页面大标题；ExwindGUI.lua MODERN.metrics.pageTitle
        title = 15,       -- 一般标题；MODERN.metrics.title
        cardTitle = 18,   -- 卡片标题；MODERN.metrics.cardTitle
        section = 15,     -- 分区标题；MODERN.metrics.section
        text = 13,        -- 正文；MODERN.metrics.text
        control = 13,     -- 控件文字；MODERN.metrics.control
        fieldValue = 15,  -- 输入框/字段值；MODERN.metrics.fieldValue
        button = 15,      -- 按钮文字；MODERN.metrics.button
        hint = 11,        -- 提示/说明小字；MODERN.metrics.hint
        moduleDescription = 12, -- Module management descriptions retain their current size.
        sliderInput = 13, -- 滑条数值框字号（用户 2026-10-05：11 太小）。加大后框宽同批放到 48，
                          -- 让 "100.5" 这类四位带小数的值仍能整体显示。
        small = 12,       -- 次要小字（对话框来源行、模块说明等）。
        label = 14,       -- 表头、弹层内小标题。
        dialogTitle = 22, -- 对话框/提示卡片标题。
    },

    -- 间距 / 内边距 / 圆角前的留白（像素）。
    space = {
        buttonPaddingX = 14,           -- 按钮文字左右内边距；ExwindGUI.lua BUTTON_STYLE.paddingX
        buttonPaddingY = 6,            -- 按钮文字上下内边距；BUTTON_STYLE.paddingY
        sliderInputInset = 3,          -- 滑条数值框文字左右内缩；SLIDER_NUMBER_INPUT_INSET
        cardBodyPadding = 12,          -- 设置卡片正文四周留白；ExwindGUISettingsList.lua SETTINGS_CARD_BODY_PADDING
        rowPaddingX = 20,              -- 设置列表行左右内边距；SETTINGS_LIST_ROW_PADDING_X
        rowPaddingY = 8,               -- 设置列表行上下内边距；SETTINGS_LIST_ROW_PADDING_Y
        columnGap = 20,                -- 设置列表左文字与右控件的列间距；SETTINGS_LIST_COLUMN_GAP
        descriptionGap = 6,            -- 标题与说明文字的间距；SETTINGS_LIST_DESCRIPTION_GAP
        sectionTop = 8,                -- 分区顶部留白；SETTINGS_LIST_SECTION_TOP
        sectionTitleToCardGap = 8,     -- 分区标题到卡片的间距；SETTINGS_LIST_SECTION_TITLE_TO_CARD_GAP
        sectionGroupGap = 16,          -- 分区组之间的间距；SETTINGS_LIST_SECTION_GROUP_GAP
        narrowControlIndent = 28,      -- 窄宽度下控件的缩进；SETTINGS_LIST_NARROW_CONTROL_INDENT
        settingsRowStackGap = 8,       -- 窄版设置行：文字与换到下一行的控件之间的间距
        settingsV2Gap = 8,             -- 设置页 V2 节点间距；ExwindSettingsV2.lua 的 GAP
        settingsV2Padding = 12,        -- 设置页 V2 页面内边距；ExwindSettingsV2.lua 的 PAD

        -- 树控件（ExwindGUITree.lua CreateTree）。
        treeIndent = 18,               -- 每层缩进
        treePadding = 6,               -- 行左右内边距
        treeSlotGap = 8,               -- 行内相邻元素（折叠箭头/图标/徽标/名称）之间的间距
        treeRowGap = 2,                -- 行与行之间的间距
        -- 群组方向图示与每行个数选择（CreateFlowDirectionPicker / CreatePerLineSelector）。
        flowThumbGap = 6,              -- 方向图示选择格之间的间距
        flowCellGap = 2,               -- 方向图示缩略图里小方块之间的间距
        perLineGap = 4,                -- 每行个数方块之间的间距
        toggleDropdownGap = 8,         -- 开关加下拉合一按钮：开关指示方框与文字的间距
        playIndicatorBarGap = 3,       -- 播放指示器相邻竖线的中心间距（AcquirePlayingIndicator）

        -- 专精选择器浮层（ExwindChoiceGroup.lua CreateSpecPicker）。
        specPopupInset = 12,           -- 浮层四周内缩
        specColumnGap = 10,            -- 四个护甲列之间的间距
        specClassGap = 8,              -- 职业块之间的纵向间距
        specTileGap = 4,               -- 同职业内相邻图标格的间距
        specTilePadding = 2,           -- 图标格到选项格边缘的留白；格高 = specTileSize + 2 × 该值
        specHeaderDividerGap = 6,      -- 护甲标题下的分隔线到列内容的间距；线位置 = specColumnHeaderHeight - 该值

        -- 菜单行（下拉菜单的 initializer 与行高亮、右键菜单的自绘行共用这三个键）。
        menuRowPaddingX = 8,           -- 行左右内边距：勾号/图标起点，也是无标记时文字的左内距
        menuRowSlotGap = 6,            -- 行内图标、勾号、箭头与文字之间的间隙
        menuRowHighlightInset = 1,     -- 行高亮块相对行框的左右内缩；菜单外框 inset 已有 6，这里不再叠大留白
        menuEdgePadding = 4,           -- 右键菜单四周外边距，以及行到菜单边的留白
        menuDividerGap = 3,            -- 右键菜单分隔线上下留白

        -- 页内状态提示与浮动 Toast（ExwindGUIComposite.lua）。
        statusPaddingX = 14,           -- 状态提示左右内边距
        statusPaddingY = 11,           -- 状态提示上内边距
        statusTextIndent = 40,         -- 标题/说明相对左缘的文字起点（图标槽 + 间隙）
        statusDescGap = 4,             -- 标题到说明的间距
        toastScreenMargin = 20,        -- Toast 距屏幕右下的边距
        toastStackGap = 8,             -- 多个 Toast 之间的堆叠间距

        -- 对话框（ShowDialog / ShowConfirmDialog）。
        dialogPaddingX = 20,           -- 左右内边距
        dialogPaddingY = 18,           -- 标题顶部内边距
        dialogSectionGap = 14,         -- 正文、输入、勾选、自定义内容之间的间距
        dialogButtonGap = 8,           -- 按钮间距，也是按钮换行行距的基数

        -- 颜色按钮（CreateColorButton）。
        colorSwatchPaddingX = 10,      -- 色块到按钮左缘的内边距
        colorSwatchGap = 8,            -- 色块到标签的间隙
        colorButtonTextPaddingRight = 8, -- 标签右内边距

        -- 复合设置组（ExwindGUIComposite.lua 的 COMPOSITE_* 常量真源）。
        compositePadX = 15,            -- 复合组左右内边距
        compositePadY = 8,             -- 复合组上下内边距
        compositeGap = 12,             -- 复合组列间距
        compositeMinSlotGap = 8,       -- 槽位最小间距
        compositeActionPad = 10,       -- 功能区左右内边距
        compositeActionInnerGap = 16,  -- 功能区中线内间距
        compositeControlInset = 20,    -- 列内控件两侧内缩

        -- EXBoss 技能设置列表专用（ExwindGUISettingsList.lua 的 SETTINGS_LIST_EXBOSS_*）。
        tools = { moduleTitle=20, profileTitle=23, profileLabel=14 },
        exboss = {
            contentPaddingX = 18,  -- 内容左右内边距；SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
            footerPadding = 16,    -- 底部留白；SETTINGS_LIST_EXBOSS_FOOTER_PADDING
            simplePaddingY = 9,    -- 简单行上下内边距；SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y
            fieldPaddingY = 7,     -- 字段行上下内边距；SETTINGS_LIST_EXBOSS_FIELD_PADDING_Y
            fieldColumnGap = 14,   -- 字段行列间距；SETTINGS_LIST_EXBOSS_FIELD_COLUMN_GAP
            voicePaddingY = 10,    -- 语音行上下内边距；SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y
            voiceColumnGap = 10,   -- 语音行列间距；SETTINGS_LIST_EXBOSS_VOICE_COLUMN_GAP
            voiceControlGap = 6,   -- 语音行控件间距；SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP
            cardGap = 7,           -- 卡片选项间距；SETTINGS_LIST_EXBOSS_CARD_GAP
        },
    },

    -- 控件/行高/宽度/断点/圆角（像素）。
    size = {
        controlHeight = CONTROL_HEIGHT,    -- 通用控件高度；ExwindGUI.lua MODERN.metrics.height
        buttonHeight = CONTROL_HEIGHT,     -- 按钮默认高度
        inputHeight = CONTROL_HEIGHT,      -- 输入框默认高度
        dropdownHeight = CONTROL_HEIGHT,   -- 下拉触发器默认高度（箭头与背景切片按 30px 固定几何）
        colorButtonHeight = CONTROL_HEIGHT, -- 颜色按钮默认高度
        checkboxRowHeight = CONTROL_HEIGHT, -- 复选框行高（方框本体在其中居中）
        checkboxBoxSize = 20,              -- 复选框方框本体边长（PaintModernCheckbox / 三态勾选框 / 树行内勾选共用）
        switchTrackWidth = 35,             -- Switch 轨道宽
        switchTrackHeight = 20,            -- Switch 轨道高；轨道圆角 = 高度/2
        switchKnobSize = 16,               -- Switch 圆钮直径
        switchKnobInset = 2,               -- Switch 圆钮到轨道边缘的留白；开启位置 = 轨道宽 - 圆钮 - 留白
        chipHeight = CONTROL_HEIGHT,       -- 选项块（chip）高度
        pillHeight = CONTROL_HEIGHT,       -- Pill 高度
        -- [WEB-REQ 38/40] 分段选项整体高度（轨道）：略高于默认控件高度，34；内部选中块 = 高度 - 6 = 28。
        -- 网页原型按 ×1.25 换算为轨道 42 / 选项 36，Core 以此值为准。
        segmentedItemHeight = 34,
        tabHeight = 38,                    -- 顶部 Tab 高度
        tabIndicatorHeight = 2,            -- Tab 选中下划线高度；两端半圆半径 = 该值 / 2。
                                           -- 下划线走"只填充、不描边"的路径（PaintTabIndicator 把 border 传成
                                           -- 透明），所以不受描边退化影响：2 物理像素仍能取到半径 1 的圆头。
                                           -- 2 物理像素就是下限，再细只剩 1 像素、半径被夹成 0。
        tabIndicatorInset = 12,            -- 下划线相对单个 Tab 两侧的内缩

        -- 专精选择器浮层（ExwindChoiceGroup.lua CreateSpecPicker）。
        specPopupWidth = 680,              -- 浮层目标宽；由"4 专精一行 × specTileSize"反推，改它会改变图标实际边长
        specTileSize = 32,                 -- 专精图标格边长
        specTileMinSize = 24,              -- 列被挤窄时图标格的下限
        specClassHeaderHeight = 20,        -- 职业标题行高
        specColumnHeaderHeight = 40,       -- 护甲列头区高（护甲标题 + 分隔线）
        sliderHeight = 54,                 -- Slider 整体高度（标题行 + 轨道）
        sliderTrackHeight = 4,             -- Slider 轨道粗细；两端圆角由 surface 按高度/2 自动取半圆。
                                           -- 轨道是空的灰条，不再画已走过那一段的填充（用户 2026-10-05）
        timelineTrackHeight = 4,           -- 时间轴滑条轨道粗细（保持原样）
        sliderThumbWidth = 26,             -- Slider 拖块宽
        sliderThumbHeight = 12,            -- Slider 拖块高；与轨道高度同奇偶
        controlDefaultWidth = 200,
        buttonMinWidth = 104,              -- 按钮最小宽度；BUTTON_STYLE.minWidth
        buttonRadius = 4,                  -- 按钮圆角，等于 radius.control
        buttonPressOffset = 1,             -- 按钮按下时文字向右下移动的像素
        picButtonPressInset = 2,           -- 图片按钮按下时贴图四周内缩的像素（按下反馈）
        -- 滑条数值框：13 号字下 "100.5"（5 个字符）加上左右各 sliderInputInset(3) 的内缩
        -- 需要约 42px 可用宽，所以框宽 48；高度仍是 20 的具名例外。
        sliderInputWidth = 48,
        sliderInputHeight = 20,
        -- 播放指示器（唯一公共入口 EXUI:AcquirePlayingIndicator）：待播时的播放图标，
        -- 播放中换成 5 条竖线（只有中间 3 条跳动）。所有播放入口共用这一组尺寸。
        playIndicatorIconSize = 16,        -- 待播状态的播放图标边长
        playIndicatorBarWidth = 2,         -- 单条竖线宽
        playIndicatorBarMaxHeight = 11,    -- 中间那条竖线的静止高度，也是跳动的上限基数

        menuRowHeight = 30,                -- 菜单行高与勾标尺寸独立。
        menuSearchHeight = 42,             -- 下拉菜单搜索栏高度；EXTERNAL_DROPDOWN_SEARCH_HEIGHT
        menuCheckSize = 16,                -- 菜单勾号边长（用户 2026-10-04：原 14 太小）
        menuScrollBarWidth = 8,
        menuScrollThumbWidth = 4,
        numberStepperWidth = 20,
        menuMaxHeight = 400,               -- [WEB-REQ 57] 右键菜单最大高度，对齐 Dropdown 的 SetScrollMode(400)；更长则滚动
        menuMaxWidth = 420,                -- 右键菜单最大宽度（按真实文字测宽，超过则单行截断）
        menuMinWidth = 190,                -- 右键菜单最小宽度
        menuIconSize = 16,                 -- 右键菜单行图标边长（与 treeIconSize 同值）
        menuArrowSize = 14,                -- 右键菜单子菜单箭头边长
        menuTitleHeight = 26,              -- 右键菜单标题槽高

        -- 页内状态提示与浮动 Toast。
        statusIconSize = 16,               -- 左侧状态图标边长
        statusNoticeHeight = 44,           -- 只有标题时的高度
        statusNoticeHeightWithDesc = 68,   -- 带说明时的高度
        toastWidth = 320,                  -- 浮动 Toast 宽度
        toastCloseSize = 18,               -- Toast 关闭按钮边长
        toastCloseGlyphSize = 14,          -- Toast 关闭图标边长

        dialogCloseSize = 28,              -- 对话框关闭按钮边长（与 floatingCloseSize 同值，但各自独立）
        dialogCloseGlyphSize = 16,         -- 对话框关闭图标边长；比 Toast 的 14 大一档，对应更大的按钮
        colorButtonDefaultWidth = 225,     -- 颜色按钮默认宽度
        colorSwatchSize = 16,              -- 颜色按钮左侧色块边长
        cardHeaderHeight = 32,             -- 设置卡片标题栏高度；ExwindGUISettingsList.lua SETTINGS_CARD_HEADER_HEIGHT
        personPortraitAvatar = 56,         -- 人物卡竖排默认圆形头像直径
        homeContactIcon = 48,              -- 首页顶部联系图标
        homeResourceIcon = 24,             -- 首页官方资源图标
        homeThanksAvatar = 72,             -- 首页感谢人物圆形头像直径
        personPortraitRing = 3,            -- 竖排头像外圈：彩环宽 2 + 与头像之间的留缝 1
        personChipAvatar = 20,             -- 人物胶囊（PersonCards layout="chip"）圆形头像直径
        personBadgeSize = 20,              -- 头像右下角的平台角标直径（图标按其 0.7 倍显示）
        personPlatformIcon = 24,           -- 人物卡平台辅助角标，与头像保持主次比例
        floatingHeaderHeight = 32,         -- 非模态浮动窗口（CreateFloatingWindow）标题栏高度，也是拖动条高度
        floatingCloseSize = 28,            -- 浮动窗口关闭按钮边长，与 ShowDialog 的关闭按钮同尺寸
        toggleDropdownArrowWidth = 26,     -- 开关加下拉合一按钮：右半（展开）区域宽度
        toggleDropdownBoxSize = 16,        -- 开关加下拉合一按钮：左侧开关指示方框边长
        flowThumbWidth = 58,               -- 群组方向图示选择格宽度
        flowThumbHeight = 46,              -- 群组方向图示选择格高度
        perLineInputWidth = 90,            -- 每行个数选择：数字输入框宽度
        treeRowHeight = CONTROL_HEIGHT,    -- 树行高度（默认，CreateTree 可用 options.rowHeight 覆盖）
        treeFoldSize = 12,                 -- 树折叠箭头边长
        treeIconSize = 16,                 -- 树行图标边长
        treeBadgeSize = 22,                -- 树行徽标方块边长
        treePillHeight = 18,               -- 树行右侧数量胶囊高度
        minTextWidth = 160,                -- 设置列表文字列最小宽度；SETTINGS_LIST_MIN_TEXT_WIDTH
        -- [WEB-REQ 28] 设置列表普通行（按钮/输入/下拉/颜色/滑条）右侧控件的最小可用宽与窄版阈值：
        -- 文字列 >= minTextWidth 放不下时，文字列可收窄到 settingsRowCompactTextWidth，仍放不下才把控件换到下一行。
        settingsRowControlMinWidth = 104,  -- 与按钮最小宽 buttonMinWidth 一致
        settingsRowSliderMinWidth = 154,   -- 滑条（数值框 sliderInputWidth 48 + 间距 10 + 轨道 >= 96）
        settingsRowCompactTextWidth = 112, -- 窄版时文字列最小宽度
        standardRowHeight = 50,            -- 设置列表标准行高；SETTINGS_LIST_STANDARD_ROW_HEIGHT
        ordinaryControlHeight = CONTROL_HEIGHT, -- 设置列表内普通控件高度
        descriptionMinHeight = 64,         -- 说明区最小高度；SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT
        externalHeaderHeight = 56,         -- 外置卡片头高度；SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT
        fieldRowBreakpoint = 440,          -- 字段行换行断点宽度；SETTINGS_LIST_FIELD_ROW_BREAKPOINT
        compactVoiceBreakpoint = 510,      -- 语音行紧凑布局断点；SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
        compactVoiceSourceBreakpoint = 360, -- 语音来源紧凑断点；SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT

        -- EXBoss 技能设置列表专用（ExwindGUISettingsList.lua 的 SETTINGS_LIST_EXBOSS_*）。
        tools = { moduleTitle=20, profileTitle=23, profileLabel=14 },
        exboss = {
            headerHeight = 53,         -- 头部高度；SETTINGS_LIST_EXBOSS_HEADER_HEIGHT
            simpleRowHeight = 46,      -- 简单行高；SETTINGS_LIST_EXBOSS_SIMPLE_ROW_HEIGHT
            fieldRowHeight = 47,       -- 字段行高；SETTINGS_LIST_EXBOSS_FIELD_ROW_HEIGHT
            voiceRowHeight = 48,       -- 语音行高；SETTINGS_LIST_EXBOSS_VOICE_ROW_HEIGHT
            cardStackBreakpoint = 365, -- 卡片选项改为竖排的断点宽度；SETTINGS_LIST_EXBOSS_CARD_STACK_BREAKPOINT
        },
    },
}
