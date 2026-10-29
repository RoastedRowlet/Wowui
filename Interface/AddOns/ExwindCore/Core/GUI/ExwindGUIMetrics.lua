-- ExwindCore 设置界面的固定数值表：字号、间距、尺寸。
-- 只放纯数据；通用控件与页面专用字号均从本表读取。
-- 必须在 ExwindGUIColor.lua 之后、ExwindGUI.lua 之前加载。
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 默认控件高度：按钮、输入框、下拉触发器、颜色按钮、设置列表普通控件共用这一个值。
-- 只有声明里明确写了 height 的控件才可以不同。
local CONTROL_HEIGHT = 30

ExwindTools.GUIMetrics = {
    -- 设置行规格：照 V1 设置页定案的数值（用户 2026-10-12：原本都调好了，照抄）。
    -- 只有一种设置行：左标签（可带一行说明），右控件，控件列右对齐。
    settings = {
        rowMinHeight = 50,        -- 卡内一行的最小高度（V1 standardRowHeight）
        rowPaddingX = 20,         -- 行左右内边距（V1 rowPaddingX）
        rowPaddingY = 8,          -- 行上下内边距（V1 rowPaddingY）
        cardPaddingX = 20,        -- 卡片左右内边距，与行内边距相同，卡内所有内容左缘统一
        cardPaddingY = 0,         -- 只有设置行的卡片上下内边距：V1 行直接贴卡片，单行卡 = 一行高
        cardGap = 4,              -- 同组卡片之间的间距
        sectionHeaderTop = 20,    -- 节标题上移量：加页面卡片间距 8 后，离上方卡片 24（V1 sectionGroupGap 16 + sectionTop 8）
        sectionHeaderBottom = 8,  -- 节标题离下方卡片（V1 sectionTitleToCardGap）
        labelFont = 15,           -- 标签字号（V1 行标题 title 15）
        descriptionFont = 13,     -- 说明字号（V1 正文 text 13）
        sectionFont = 18,         -- 节标题字号（V1 节标题 cardTitle 18）
        labelDescriptionGap = 6,  -- 标签与说明的间距（V1 descriptionGap）
        controlHeight = 30,       -- 行内控件高度（V1 ordinaryControlHeight）
        controlMinWidth = 104,    -- 控件列最小宽（V1 settingsRowControlMinWidth）
        labelControlGap = 20,     -- 标签列与控件列的间距（V1 columnGap）
        stackGap = 8,             -- 窄时控件换到标签下方的间距（SettingsCardVerticalHeaderContentSpacing 8）
        leadGap = 8,              -- 标签前勾选框 / 图标与标签文字的间距
        leadIconSize = 20,        -- 标签前图标边长（勾选框用 size.checkboxBoxSize）
        controlShortWidth = 72,   -- 控件宽度档位 size="short"（短数字、秒数）
        controlWideWidth = 320,   -- 控件宽度档位 size="wide"（长文字、路径）
        soundSelectorWidth = 320, -- 连体声音选择（来源 | 内容 | ▶）的自然宽
        toggleItemPadX = 44,      -- 多选（角标勾小块）：文字左 14 + 右侧角标区 30
        toggleItemGap = 4,        -- 多选：小块之间的间距
        soundSourceMaxRatio = 0.4, -- 声音选择里“来源”段最多占整段宽的比例
        soundChannelSourceRatio = 0.2, -- 带输出声道时“来源”段最多占的比例（中间的内容段要宽）
        soundChannelRatio = 0.22,  -- 带输出声道时“声道”段占整段宽的比例
        tableCellPadX = 4,        -- 表格单元格左右内距
        multilineHeight = 120,    -- 多行文字框标准高度
        multilineTallHeight = 240, -- 多行文字框 size="tall"（导入导出字符串）
        multilineScrollReserve = 20, -- 多行文字区给滚动留的宽度
        numberStepIconSize = 14,     -- 数字框（CreateNumberInput）加减号图标边长
        sliderValueGap = 6,          -- 设置行滑杆：轨道与右侧数值框之间（数值框是纯输入框，不带加减，用户 10-26 定）
        -- 可选页面样式预设（EXAura 编辑器新版）：页面声明只写预设名，不写像素。
        -- 颜色直接引用 Core 色表 GUIColors 里的项。styles 在下方表外填入。
        styles = {},
        -- 设置页 V2 新种类的默认尺寸（像素 / 字号）。页面样式预设写了同名键就用预设的值，
        -- 所以 EXAura 外观定稿只改这里或预设里的数字，声明不写像素。
        parts = {
            moreRowHeight = 32,        -- 渐进披露“更多 ›”行高
            moreFont = 14,             -- “更多 ›”字号
            moreTextInset = 0,         -- “更多 ›”文字离行左缘
            panelSmallWidth = 380,     -- 二级面板 size="small" 外框宽
            panelSmallHeight = 440,    -- 二级面板 size="small" 外框高
            panelLargeWidth = 560,     -- 二级面板 size="large" 外框宽
            panelLargeHeight = 640,    -- 二级面板 size="large" 外框高
            panelFooterHeight = 46,    -- 二级面板底栏高（放动作按钮）
            panelButtonGap = 8,        -- 底栏按钮之间
            panelAnchorGap = 6,        -- 二级面板与贴靠框体的间距
            summaryPaddingX = 12,      -- 摘要行左右内距
            summaryPaddingY = 8,       -- 摘要行上下内距
            summaryTitleFont = 15,     -- 摘要行标题字号
            summaryTextFont = 13,      -- 摘要行摘要字号
            summaryLineGap = 4,        -- 标题与摘要之间
            summaryIconSize = 20,      -- 摘要行行首图标边长
            summaryButtonSize = 22,    -- 摘要行编辑 / 删除图标按钮边长
            summaryButtonIconSize = 13, -- 摘要行图标按钮里的图标边长
            summaryGap = 8,            -- 行首图标、文字、尾部按钮之间
            sentenceLineHeight = 30,   -- 句子卡每行行高
            sentencePaddingY = 8,      -- 句子卡上下内距
            sentenceLineGap = 4,       -- 句子卡两行之间
            sentenceFragmentIconSize = 18, -- 句子里词前的小图标（法术图标）边长
            sentenceIconGap = 4,       -- 小图标与文字之间
            sentenceTokenPadX = 6,     -- 可点词左右内距
            sentenceTokenPadY = 3,     -- 可点词上下内距
            sentenceUnderlineOffset = 4, -- 悬停词下划线离文字
            sentenceButtonInset = 8,   -- 右上编辑 / 删除按钮离卡角
            stepRailWidth = 40,        -- 步骤条左栏宽（卡标题和内容右移这么多）
            stepTitleFont = 15,        -- 步骤名字号
            stepTitleHeight = 30,      -- 步骤名行高
            stepTitleGap = 6,          -- 步骤名到内容
            stepBottom = 4,            -- 步骤内容下内距（再加组间距到下一步）
            stepDotSize = 26,          -- 步骤圆圈直径（序号写在圈里）
            stepDotBorder = 2,         -- 圆圈边宽
            stepDotX = 0,              -- 圆圈离卡左缘
            stepNumberFont = 13,       -- 序号字号
            stepLineWidth = 2,         -- 连线宽
            stepLineGap = 4,           -- 连线两端离圆点
            -- 预设 stepSide = true 时（步骤名在左栏、内容在右边同一行）用的尺寸：
            stepSideWidth = 132,       -- 左栏宽（序号方块 + 步骤名）
            stepSideNameGap = 8,       -- 序号方块与步骤名之间
            stepSideRadius = 6,        -- 序号方块圆角
            stepSideDivider = 1,       -- 步骤之间横线粗（画在组间距正中）
            optionCardGap = 8,         -- 横排选择卡之间
            optionCardPadX = 12,       -- 选择卡左右内距
            optionCardPadY = 10,       -- 选择卡上下内距
            optionCardIconSize = 20,   -- 选择卡图标边长
            optionCardIconGap = 8,     -- 图标与名字之间
            optionCardNameFont = 15,   -- 选择卡名字字号
            optionCardDescFont = 13,   -- 选择卡描述字号
            optionCardDescGap = 4,     -- 名字到描述
            propsFont = 13,            -- 小字键值区字号（键名与值）
            propsPaddingX = 8,         -- 键值区左右内距
            propsPaddingTop = 4,       -- 键值区上内距
            propsPaddingBottom = 8,    -- 键值区下内距
            propsRowHeight = 28,       -- 每行高
            propsValueHeight = 26,     -- 值框高
            propsKeyWidth = 38,        -- 第一项键名列宽
            propsKeyInset = 6,         -- 第一项键名离列左缘
            propsSecondKeyLeft = 10,   -- 第二项键名左留白
            propsSecondKeyRight = 4,   -- 第二项键名右留白
            propsGap = 4,              -- 键名、值框、按钮之间
            propsShortWidth = 64,      -- size="short" 的值框宽（版本号）
            propsMultilineHeight = 76, -- 多行项点进去后的框高（上限：文字超过这个高在框内滚动）
            propsValueInset = 6,       -- 值框文字左右内距
            propsButtonSize = 24,      -- 框后图标按钮边长
            propsButtonIconSize = 14,  -- 框后图标按钮里的图标边长
            propsPrefixWidth = 28,     -- prefixIcon 项：框内前缀图标占的宽（文字从这里开始）
            propsPrefixInset = 6,      -- 前缀图标离值框左缘
            propsPrefixIconSize = 16,  -- 前缀图标边长（和框里文字相称）
            propsPrefixShortWidth = 78, -- prefixIcon 项 size="short" 的值框宽（含图标）
            propsInlineButtonSize = 22, -- prefixIcon 项：框内右侧图标按钮边长
            propsInlineButtonInset = 2, -- 框内图标按钮离值框右缘
            propsClampPadY = 3,        -- clampLines 多行项：文字上下内距
            propsMoreGap = 4,          -- clampLines 多行项：文字与“展开 / 收起”之间
            catalogCardMinWidth = 96,  -- 预览卡最窄（按它算每行几张，多出的宽平分）
            catalogPreviewHeight = 60, -- 预览卡里预览区高
            catalogIconSize = 32,      -- 预览区里的图标边长（没给绘制回调时）
            catalogLabelFont = 13,     -- 预览卡名字字号
            catalogPadding = 6,        -- 预览卡内距
            catalogLabelGap = 4,       -- 预览区与名字之间
            catalogLabelLines = 1,     -- 预览卡名字最多几行（1 = 不换行；大于 1 时放不下换行，卡高按实际行数）
            catalogGap = 8,            -- 预览卡之间
            catalogTileWidth = 72,     -- 方格卡（catalog presentation="tile"）宽：图标在上、名字在下
            catalogTileIcon = 44,      -- 方格卡图标（或绘制回调的预览区）边长
            catalogTileIconRadius = 6, -- 方格卡里材质图标的圆角
            catalogTileColumns = 4,    -- 方格卡每行最多几张（靠左排，不拉宽）
            catalogTilePadY = 6,       -- 方格卡上下内距
            catalogTileGap = 6,        -- 方格卡之间
            catalogTileLargeWidth = 160, -- 大方格卡（catalog size="large"）宽：样子同方格卡，只是放大
            catalogTileLargeIcon = 76,   -- 大方格卡图标边长
            catalogTileLargeIconRadius = 10, -- 大方格卡里材质图标的圆角
            catalogTileLargeFont = 15,   -- 大方格卡名字字号（比 catalogLabelFont 大一档）
            catalogTileLargePadY = 12,   -- 大方格卡上下内距
            optionCellHeight = 40,     -- 预设 optionCardCells：横排选择卡画成只有名字的格子时格高
            optionCellWidth = 96,      -- 格子参考宽（页面按“左栏 + 4 格”算面板宽时用；实际宽按列数平分）
            optionCellFont = 15,       -- 格子名字字号
            soundTileHeight = 60,      -- 声音选择格子排法（soundselector opts.tiles）每格高
            soundTileGap = 8,          -- 格子之间
            soundTilePadX = 12,        -- 格内左右内距
            soundTileLineGap = 2,      -- 小标题与值之间
            soundTileCaptionFont = 13, -- 小标题字号
            soundTileValueFont = 15,   -- 值字号
            soundTileArrowSize = 12,   -- 下拉箭头边长
            soundTileEditHeight = 26,  -- 内容是输入框（文件路径）时框高
            soundTileSourceWidth = 150, -- 来源格宽
            soundTileChannelWidth = 150, -- 声道格宽
            soundTilePlayWidth = 84,   -- 试听格宽（声音格分剩下的宽）
            soundTileDisabledAlpha = 0.5, -- 停用时格子透明度
            glowTileGap = 6,           -- 发光设置组（glow_settings）预设格之间
            glowTileMinWidth = 72,     -- 预设格最窄（放不下四格时改两格一行）
            glowTileSampleSize = 48,   -- 预设格里样本图标边长
            glowTilePreviewHeight = 78, -- 预设格预览区高（样本外留出发光的位）
            glowTileLabelFont = 13,    -- 预设格名字字号
            glowTileMarkFont = 12,     -- “已改”字号
            glowTilePadY = 6,          -- 预设格上下内距
            glowTileLineGap = 3,       -- 预览、名字、“已改”之间
            glowTileBlockPadY = 10,    -- 预设格整排上下留白
            glowSampleOffsetMax = 4,   -- 预设格样本的发光间距上限（大间距在小格里会出界）
            glowSwatchSize = 18,       -- 颜色行色板边长
            glowSwatchGap = 6,         -- 色板之间
            catalogDimAlpha = 0.4,     -- 记录 dim 的卡（不能选）透明度
            catalogDimHoverAlpha = 0.7, -- dim 卡悬停时透明度
            catalogHeadingFont = 13,   -- 网格上方小标题（title / description）字号
            catalogHeadingGap = 6,     -- 小标题行到卡片
            catalogHeadingNoteGap = 8, -- 小标题与说明之间
            catalogHeadingInset = 2,   -- 小标题离左缘
            entryHeight = 64,          -- 入口卡（catalog presentation="entry"）高
            entryMinWidth = 150,       -- 入口卡最窄
            entryGap = 12,             -- 入口卡之间
            entryPaddingX = 16,        -- 入口卡左右内距
            entryIconSize = 26,        -- 入口卡图标边长
            entryIconGap = 10,         -- 图标与名字之间
            entryLabelFont = 15,       -- 入口卡名字字号
            chipIconSize = 16,         -- 带图标芯片里的图标边长
            chipIconGap = 4,           -- 芯片图标与文字之间
            chipInputWidth = 140,      -- 芯片列表末尾输入框的宽
            chipCornerRemoveSize = 12, -- 方块图标芯片（chipIconCompact）右上角删除叉边长
            triFont = 13,              -- 三态小标签字号
            triPaddingX = 12,          -- 三态小标签左右内距
            triDotSize = 10,           -- 三态小标签文字前的色点直径
            triDotGap = 7,             -- 色点与文字之间
            inlineButtonSize = 22,     -- 输入框内嵌图标按钮边长
            inlineButtonIconSize = 14, -- 内嵌图标按钮里的图标边长
            inlineButtonInset = 4,     -- 内嵌按钮离输入框右缘
            prefixWidth = 18,          -- 数字框前缀（字母或图标）占的宽
            prefixFont = 13,           -- 前缀字母字号
            prefixIconSize = 14,       -- 前缀图标边长
            prefixGap = 6,             -- 前缀（画在输入框外左边）到输入框左缘
            prefixInset = 6,           -- 前缀图标离输入框左缘
            noticePaddingX = 10,       -- 行内提示条左右内距
            noticePaddingY = 8,        -- 行内提示条上下内距
            noticeFont = 13,           -- 行内提示条字号
            urlWidth = 320,            -- 可复制网址框的自然宽
            pickColumns = 2,           -- 分组多选列表的栏数
            pickColumnGap = 16,        -- 两栏之间
            pickGroupFont = 14,        -- 分组标题字号
            pickGroupGap = 10,         -- 组与组之间
            pickTitleGap = 4,          -- 组标题与第一项之间
            pickRowHeight = 26,        -- 每一项的行高
            pickSearchWidth = 200,     -- 搜索框宽
            pickCountFont = 13,        -- 计数字号
            pickHeaderGap = 10,        -- 搜索行与分组之间
            iconPickCell = 40,         -- 图标选取（iconpick）：格子图标边长（职业、专精、英雄天赋、种族）
            iconPickSmall = 28,        -- 小号图标边长（载入页行下的已选图标、“…”方块）
            iconPickGlow = 8,          -- 选中外发光比格子每边大出
            iconPickCardWidth = 120,   -- 副本卡宽（首领卡的最小宽）
            iconPickCardImage = 66,    -- 副本卡上冒险手册按钮图高（按钮图 174×95 的比例）
            iconPickCardName = 22,     -- 副本卡图下的名字行高
            iconPickBossHeight = 64,   -- 首领卡高（同 EXBoss 首领页）
            iconPickModelWidth = 54,   -- 首领卡 3D 头像宽
            iconPickModelHeight = 58,  -- 首领卡 3D 头像高
            iconPickTextGap = 6,       -- 图标与文字之间
            iconPickGap = 4,           -- 同一行里两项之间
            iconPickRowPadY = 2,       -- 行上下内距
            iconPickSeparatorGap = 8,  -- 竖分隔线左右留白
            iconPickSeparatorHeight = 20, -- 竖分隔线高
            iconPickGridGap = 6,       -- 等分格之间
            iconPickTitleHeight = 18,  -- 分组小标题行高
            iconPickTitleFont = 13,    -- 分组小标题字号
            iconPickFont = 14,         -- 副本名、导航项字号
            iconPickHeadHeight = 22,   -- 分组标题（head：可点的小图标 + 名字）行高
            iconPickHeadIcon = 20,     -- 分组标题里的小图标边长
            iconPickSectionGap = 8,    -- 组与组之间
            iconPickColumnGap = 16,    -- 并排的组之间
            iconPickDividerHeight = 7, -- 横分隔线所占行高（线在中间）
            iconPickDimAlpha = 0.45,   -- 没选中的首领卡 3D 头像透明度（模型不能去色）
            iconPickNavWidth = 160,    -- 侧栏导航项（nav）宽
            iconPickNavHeight = 32,    -- 侧栏导航项高
            iconPickNavIcon = 24,      -- 侧栏导航项里的图标边长
            iconPickNavPadX = 6,       -- 侧栏导航项左右内距
            texturePickCell = 52,      -- 材质网格（texturegrid）：格子边长
            texturePickGap = 6,        -- 格子之间；材质预览里材质离示意图标
            texturePickInset = 4,      -- 格子里材质离格边
            texturePickPreviewHeight = 150, -- 材质预览（texturepreview）区高
            texturePickPreviewIcon = 40,    -- 预览中间示意图标边长
            texturePickPreviewSize = 72,    -- 预览里材质的边长（按宽高比放进这个方框）
            quickAnchorGap = 6,        -- 贴词小框与贴靠框体的间距
            quickPopoverWidth = 300,   -- 贴词小框宽
            quickPopoverPadding = 2,   -- 小框外框内距（里面的页面自带页边距）
        },
    },

    -- 圆角角色（视觉半径，像素；必须是 SetControlSurface 白名单 3/4/5/6/8/10 之一；白名单里的 21 只给胶囊按钮组）。
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
        compactButtonPaddingX = 4,     -- 紧凑按钮文字左右内边距：文字限制在按钮内，放不下按钮撑宽
        sliderInputInset = 3,          -- 滑条数值框文字左右内缩；SLIDER_NUMBER_INPUT_INSET
        cardBodyPadding = 12,          -- 设置卡片正文四周留白；ExwindGUISettingsList.lua SETTINGS_CARD_BODY_PADDING
        columnGap = 20,                -- 通用左右两列的列间距（设置行用 settings.labelControlGap）
        descriptionGap = 6,            -- 标题与说明文字的间距；SETTINGS_LIST_DESCRIPTION_GAP
        sectionTop = 8,                -- 分区顶部留白；SETTINGS_LIST_SECTION_TOP
        sectionGroupGap = 16,          -- 分区组之间的间距；SETTINGS_LIST_SECTION_GROUP_GAP
        narrowControlIndent = 28,      -- 窄宽度下控件的缩进；SETTINGS_LIST_NARROW_CONTROL_INDENT
        settingsRowStackGap = 8,       -- 窄版设置行：文字与换到下一行的控件之间的间距
        settingsV2Gap = 8,             -- 设置页 V2 节点间距；ExwindSettingsV2.lua 的 GAP
        settingsV2Padding = 12,        -- 设置页 V2 页面内边距；ExwindSettingsV2.lua 的 PAD
        -- 以下几项原来各处写了不同的数，统一在这里（10-13）。
        sliderInputGap = 10,           -- 滑条轨道与数值框的间距（独立滑条与设置行滑条共用）
        inputTextPadX = 9,             -- 输入框文字与占位文字的左内距
        choiceItemPadX = 20,           -- 选项块：文字宽 + 该值 = 块宽
        choiceIconItemPadX = 42,       -- 带图标的选项块：文字宽 + 该值 = 块宽
        segmentedTrackPad = 3,         -- segmented 轨道四周内距
        segmentedDarkTrackPad = 2,     -- segmented 黑色轨道（options.track = "dark"）四周内距
        connectedTrackPad = 2,         -- connected 轨道四周内距

        -- 树控件（ExwindGUITree.lua CreateTree）。
        treeIndent = 18,               -- 每层缩进
        treePadding = 6,               -- 行左右内边距
        treeSlotGap = 8,               -- 行内相邻元素（折叠箭头/图标/徽标/名称）之间的间距
        treeRowGap = 2,                -- 行与行之间的间距
        -- 群组方向图示与每行个数选择（CreateFlowDirectionPicker / CreatePerLineSelector）。
        flowThumbGap = 6,              -- 方向图示选择格之间的间距
        flowCellGap = 2,               -- 方向图示缩略图里小方块之间的间距
        flowCellInset = 4,             -- 方向图示缩略图里小方块离选择格边缘（三行排的图示不贴格边）
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
        menuShortcutGap = 16,          -- 右键菜单项文字与右侧快捷键（item.shortcut）之间至少留

        -- 页内状态提示与浮动 Toast（ExwindGUIComposite.lua）。
        statusPaddingX = 14,           -- 状态提示左右内边距
        statusPaddingY = 11,           -- 状态提示上内边距
        statusTextIndent = 40,         -- 标题/说明相对左缘的文字起点（图标槽 + 间隙）
        statusDescGap = 4,             -- 标题到说明的间距
        toastScreenMargin = 20,        -- Toast 距屏幕右下的边距
        toastStackGap = 8,             -- 多个 Toast 之间的堆叠间距
        inlineNoticeGap = 4,           -- 贴行提示（ShowInlineNotice）离控件下缘
        inlineNoticePaddingX = 10,     -- 贴行提示左右内距
        inlineNoticePaddingY = 7,      -- 贴行提示上下内距
        inlineNoticeIconGap = 6,       -- 贴行提示图标与文字之间
        inlineNoticeScreenMargin = 8,  -- 贴行提示离屏幕边最少留
        dragThreshold = 4,             -- 空白处拖动（SetDragAnywhere）：按下后鼠标移过这么多屏幕像素才开始拖

        -- 对话框（ShowDialog / ShowConfirmDialog）。
        dialogPaddingX = 20,           -- 左右内边距
        dialogPaddingY = 18,           -- 标题顶部内边距
        dialogSectionGap = 14,         -- 正文、输入、勾选、自定义内容之间的间距
        dialogButtonGap = 8,           -- 按钮间距，也是按钮换行行距的基数

        -- 颜色按钮（CreateColorButton）。
        colorSwatchPaddingX = 10,      -- 色块到按钮左缘的内边距
        colorSwatchGap = 8,            -- 色块到标签的间隙
        colorButtonTextPaddingRight = 8, -- 标签右内边距
        colorPresetGap = 4,            -- 取色面板色块之间（一排 13 个职业色要放得下）
        colorPickerGap = 10,           -- 取色面板：色轮、明度条、透明度条、右栏之间，色轮到常用色一排
        colorPickerSideGap = 6,        -- 取色面板右栏：对比色块、十六进制框、透明度框之间

        -- 复合设置组（ExwindGUIComposite.lua 的 COMPOSITE_* 常量真源）。
        compositePadX = 10,            -- 复合组左右内边距；加上列内控件内缩 10 后与设置行左缘 20 对齐（settings.rowPaddingX）
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
                                           -- 所有页面同一套细滑条，页面预设不再另给粗轨道（用户 10-26：“好丑”）
        timelineTrackHeight = 4,           -- 时间轴滑条轨道粗细（保持原样）
        sliderThumbWidth = 12,             -- Slider 拖块：小圆点（宽高相等）
        sliderThumbHeight = 12,            -- Slider 拖块高；与轨道高度同奇偶
        controlDefaultWidth = 200,
        buttonMinWidth = 104,              -- 按钮最小宽度；BUTTON_STYLE.minWidth
        buttonRadius = 4,                  -- 按钮圆角，等于 radius.control
        buttonPressOffset = 1,             -- 按钮按下时文字向右下移动的像素
        picButtonPressInset = 2,           -- 图片按钮按下时贴图四周内缩的像素（按下反馈）
        -- 滑条数值框（纯输入框，不带加减）：13 号字下 "100.5%" 加上左右各 sliderInputInset(3) 的内缩，框宽 56；
        -- 设置行里数值更长放不下时按最长数值加宽。高度仍是 20 的具名例外。
        sliderInputWidth = 56,
        sliderInputHeight = 20,
        -- 播放指示器（唯一公共入口 EXUI:AcquirePlayingIndicator）：待播时的播放图标，
        -- 播放中换成 5 条竖线（只有中间 3 条跳动）。所有播放入口共用这一组尺寸。
        playIndicatorIconSize = 16,        -- 待播状态的播放图标边长
        playIndicatorBarWidth = 2,         -- 单条竖线宽
        playIndicatorBarMaxHeight = 11,    -- 中间那条竖线的静止高度，也是跳动的上限基数

        menuRowHeight = 30,                -- 菜单行高与勾标尺寸独立。
        menuSearchHeight = 42,             -- 下拉菜单搜索栏高度；EXTERNAL_DROPDOWN_SEARCH_HEIGHT
        menuSearchMinItems = 8,            -- 下拉选项不超过这么多项时不出搜索框，多了才出（用户 10-26）
        menuCheckSize = 16,                -- 菜单勾号边长（用户 2026-10-04：原 14 太小）
        menuScrollBarWidth = 8,
        menuScrollThumbWidth = 4,
        numberStepperWidth = 22,           -- 数字框加减步进列 / 左减右加每个按钮的宽
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
        inlineNoticeMinWidth = 160,        -- 贴行提示最窄（控件比它窄时按它）

        dialogCloseSize = 28,              -- 对话框关闭按钮边长（与 floatingCloseSize 同值，但各自独立）
        dialogCloseGlyphSize = 16,         -- 对话框关闭图标边长；比 Toast 的 14 大一档，对应更大的按钮
        colorButtonDefaultWidth = 225,     -- 颜色按钮默认宽度
        colorSwatchSize = 16,              -- 颜色按钮左侧色块边长
        colorPresetSize = 16,              -- 取色面板色块边长
        colorPickerWheelSize = 128,        -- 取色面板色轮边长（明度条、透明度条同高）
        colorPickerBarWidth = 14,          -- 取色面板明度条、透明度条宽
        colorPickerSideWidth = 84,         -- 取色面板右栏宽（对比色块、十六进制框、透明度框）
        colorPickerSwatchHeight = 20,      -- 取色面板新旧对比色块各高
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
        iconGlyphSize = 18,                -- 图标按钮、只显示图标的分段里的图标边长（默认）
        flowThumbWidth = 58,               -- 群组方向图示选择格宽度
        flowThumbHeight = 54,              -- 群组方向图示选择格高度（三行小方块 + 上下留边放得下）
        perLineMinSquare = 22,             -- 每行个数只用方块（single）时方块最窄，再窄就换到下一行
        perLineInputWidth = 90,            -- 每行个数选择：数字输入框宽度
        treeRowHeight = CONTROL_HEIGHT,    -- 树行高度（默认，CreateTree 可用 options.rowHeight 覆盖）
        treeFoldSize = 12,                 -- 树折叠箭头边长
        treeIconSize = 16,                 -- 树行图标边长
        treeBadgeSize = 22,                -- 树行徽标方块边长
        treePillHeight = 18,               -- 树行右侧数量胶囊高度
        treeEyeSize = 22,                  -- 树行最右眼睛按钮边长（行数据写了 eye 才有）
        treeEyeIconSize = 16,              -- 眼睛按钮里的图标边长
        minTextWidth = 160,                -- 设置列表文字列最小宽度；SETTINGS_LIST_MIN_TEXT_WIDTH
        -- [WEB-REQ 28] 设置列表普通行（按钮/输入/下拉/颜色/滑条）右侧控件的最小可用宽与窄版阈值：
        -- 文字列 >= minTextWidth 放不下时，文字列可收窄到 settingsRowCompactTextWidth，仍放不下才把控件换到下一行。
        settingsRowSliderMinWidth = 158,   -- 滑条（数值框 sliderInputWidth 56 + 间距 sliderValueGap 6 + 轨道 >= 96）
        sliderTrackMinWidth = 96,          -- 滑条轨道最小宽（与上一行同一组数）
        settingsRowCompactTextWidth = 112, -- 窄版时文字列最小宽度
        externalHeaderHeight = 56,         -- 外置卡片头高度；SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT
        fieldRowBreakpoint = 440,          -- 字段行换行断点宽度；SETTINGS_LIST_FIELD_ROW_BREAKPOINT
        compactVoiceBreakpoint = 510,      -- 语音行紧凑布局断点；SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
        compactVoiceSourceBreakpoint = 360, -- 语音来源紧凑断点；SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT

        -- 胶囊按钮组（EXAura 编辑器顶部全局按钮）。
        capsuleHeight = 42,                -- 整条高度
        capsuleRadius = 21,                -- 圆角 = 高度 / 2（SetControlSurface 白名单 21）
        capsuleSegmentPadX = 14,           -- 段内左右内距
        capsuleEdgePadX = 18,              -- 首尾段外侧内距
        capsuleIconSize = 18,              -- 段内图标边长
        capsuleFont = 15,                  -- 段内文字字号
        capsuleAddFont = 18,               -- “新增”段文字字号
        capsuleAddIconSize = 22,           -- “新增”段图标边长
        capsuleDividerInset = 11,          -- 段间竖线上下各缩
        capsuleIconTextGap = 7,            -- 段内图标与文字的间距
        capsuleSegmentMinWidth = 52,       -- 每段最小宽
        capsuleTooltipGap = 8,             -- tooltipAnchor = "below" 时提示上沿离段下沿的距离

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

-- 页面样式预设的数值。派生预设 = 基础预设整份复制后改几项，结果仍是普通数据表。
do
    local GC = ExwindTools.GUIColors
    local styles = ExwindTools.GUIMetrics.settings.styles

    local function Derive(base, changes)
        local style = {}
        for key, value in pairs(base) do style[key] = value end
        for key, value in pairs(changes) do style[key] = value end
        return style
    end

    -- 分组照 6702（10-21 定案）：标题不带底、加减号折叠，行装在圆角带边卡里。
    styles.exaura = {
        catalogLabelLines = 2,          -- 预览卡名字放不下换行，最多两行
        headerHeight = 18,              -- 标题行高
        headerRadius = 6,               -- 标题条圆角（标题条透明，只占位）
        headerFill = GC.transparent,    -- 标题不带底
        headerPaddingLeft = 2,          -- 箭头离标题行左缘
        foldGlyph = "plus",             -- 折叠号画加减号图标（收起“+”、展开“−”；用户 10-24 不要箭头）
        foldWidth = 18,                 -- 加减号边长
        foldNameGap = 6,                -- 加减号与组名间距
        headerFont = 18,                -- 组名字号
        headerText = GC.text,           -- 组名颜色（同标准页节标题）
        noteFont = 13,                  -- 标题右侧字字号
        countNote = false,              -- 没写 note 的标题不显示“N 项”（用户不要标题上的数字）
        headerPaddingRight = 14,        -- 右侧字离标题行右缘
        headerOutset = 0,               -- 标题与下面的卡同宽
        collapsedPadding = 8,           -- 收起时标题下内距（下面再画一条细线）
        cardFill = GC.card,             -- 行装在圆角带边卡里：卡底
        cardBorder = GC.cardBorder,     -- 卡边（同标准页卡片边）
        cardRadius = 10,                -- 卡圆角
        surfaceGap = 8,                 -- 自带外框的件（句子卡、入口卡）之间
        groupGap = 8,                   -- 组与组之间
        firstGroupTop = 6,              -- 第一组离页签
        headerToFirstRow = 6,           -- 标题到卡片
        pagePadding = 6,                -- 页面左右内距（窗口内距 windowPadding 之外再留；用户 10-22 嫌太宽，左右多留一点）
        windowPadding = 8,              -- 浮窗内容区左右下内距（CreateFloatingWindow padding）
        rowMinHeight = 36,              -- 最小行高
        rowPaddingX = 10,               -- 行左右内距
        rowPaddingY = 5,                -- 行上下内距（控件 26 高时一行正好 36）
        tallRowPaddingY = 6,            -- 没有行名、比一行控件高的件（排列图示）再上下各多留
        dividerInset = 0,               -- 行线不缩进（通栏）
        helpIconSize = 16,              -- 行尾小问号边长
        cardHelp = true,                -- 卡片标题旁可以挂“?”说明（卡片写 help）
        settingAutoWidth = true,        -- setting 行（左标签 + 多个子控件）文字列按标签实际字宽；单控件标准行照原算法
        iconButtonSize = 28,            -- 图标按钮（button 写 icon、text 为空）边长
        iconButtonIconSize = 16,        -- 图标按钮里的图标边长
        colorWidth = 132,               -- 不带 label 的颜色控件（色块 + 十六进制色值 + 透明度百分比）宽
        controlHeight = 26,             -- 输入框、下拉等单行控件高（用户 10-22：原 30 太高）
        chipHeight = 26,                -- 芯片、三态小标签高
        summaryPaddingX = 10,           -- 摘要卡 / 句子卡左右内距
        summaryPaddingY = 8,            -- 摘要卡 / 句子卡上下内距
        summaryTextFont = 15,           -- 摘要第二行 / 句子字号
        summaryLineGap = 6,             -- 两行之间
        summaryIconSize = 28,           -- 行首图标块边长
        summaryButtonSize = 28,         -- 右上编辑 / 删除图标按钮边长
        summaryButtonIconSize = 16,     -- 图标按钮里的图标边长
        tabHeight = 34,                 -- 面板页签行高（浮窗 headerTabs 用）；蓝线在行底，行矮一点线就贴近文字
        tabFont = 17,                   -- 页签字号
        quickAnchorGap = 12,            -- 贴词小框离贴靠框体
        multiSeparator = "、",          -- 多选下拉摘要里选中项之间的分隔
        optionCardGap = 6,              -- 横排选择卡之间
        optionCardPadX = 8,             -- 选择卡左右内距（三张一排时描述放得下两行）
        optionCardPadY = 8,             -- 选择卡上下内距
        optionCardFit = true,           -- 选择卡名字不换行放不下、描述超过两行或末行只剩一个字时自动少一列（3→2→1）
        optionCardDescLines = 2,        -- 选择卡描述最多几行（配合 optionCardFit）
        triLabelAbove = true,           -- 只有三态小标签的设置行（过滤类名 + 一串标签）一律类名在上、标签在下
        unlabeledFill = true,           -- 没写 label 的设置行：控件区占满整行（只有按钮时仍靠右）
        chipInputFill = true,           -- 法术芯片末尾的输入框占满所在行剩下的宽
        chipInputColumns = 2,           -- 法术芯片：前几个（chipInputNamedMax）一行两个，图标 + 名字
        chipInputNamedMax = 6,          -- 法术芯片：超过 6 个时多出来的只显示图标，按宽度一行排满再换行
        chipInputFirst = true,          -- 法术芯片：输入框在最上面，新加的往下排，先加入的先变成只有图标
        chipIconCompact = true,         -- 法术芯片：只有图标的画成方块图标，右上角小红叉删除
        chipInputHoverRemove = true,    -- 法术芯片：删除叉都是右上角小叉，鼠标移到芯片上才显示（用户 10-25 定）
        chipInputHeight = 36,           -- 法术芯片高（图标放大，用户 10-25 定；输入框照 controlHeight）
        chipInputIconSize = 28,         -- 法术芯片里的法术图标边长（普通芯片 chipIconSize 16）
        sentencePaddingY = 4,           -- 句子卡（触发页顶部摘要）上下内距：紧凑
        sentenceLineGap = 0,            -- 句子卡两行之间
        sentenceLineHeight = 26,        -- 句子卡每行行高
        triFont = 15,                   -- 三态小标签（光环过滤）字号（用户 10-22 嫌 13 太小）
        segmentTextOffsetY = 1,         -- 分段文字下移 1 像素（中文字形偏上，看起来不居中）
        sliderSelectWidth = true,       -- 不带 label 的滑杆整组（轨道 + 数字框）宽同本页下拉
        sliderInputHeight = 24,         -- 滑杆数值框高 24（同本页控件高）
        -- 滑杆占满标签右边整列（减去数值框）；轨道、拖块用 Core 默认细滑条（用户 10-26）。
        sliderFill = true,
        sliderLabelWidth = 76,          -- 滑杆行的标签列至少这么宽：标签长短不一时滑杆仍从同一处起、一样长（用户 10-26）
        tableEmptyCompact = true,       -- 表格没有记录时不画表头，只留新增按钮（靠右、普通行高）；有记录时表头列不窄于列名
        tableAddLast = true,            -- 表格新增按钮排在所有记录行下面
        tableHeaderCellAligned = true,  -- 表头列名与下面格子里的控件左缘对齐
        perLineSingle = true,           -- 每行个数只用一种控件：上限不超过 10 只给方块，超过只给数字框
        inputFitPlaceholder = true,     -- 输入框至少放得下整句占位字
        -- 作者 / 版本 / 链接 / 说明（props）：字号同面板其他行；写了键名时与其他行名左缘对齐，下面不多留。
        propsKeyRole = "settingsLabel",
        propsValueRole = "control",
        propsRowHeight = 30,            -- 作者 / 版本 / 链接一行：图标代替行名，排紧凑（用户 10-25 定原型 ③）
        propsValueHeight = 26,
        propsPaddingX = 10,             -- 左右同行内距 rowPaddingX：值框右缘和其他行控件对齐
        propsKeyInset = 0,              -- 键名左缘 = propsPaddingX，和其他行名对齐
        propsPaddingTop = 0,
        propsPaddingBottom = 2,
        propsKeyWidth = 44,
        -- 值框平时只显示文字，鼠标悬停或点进去才显出输入框（用户 10-24 要求恢复这样）。
        propsMultilineFixed = true,     -- 说明（多行）一直占两行高，卡片高度固定
        propsMultilineHeight = 44,      -- 说明框高：两行字
        -- 左列表（光环树面板）：树控件外面一圈的排布。搜索框、眼睛高 controlHeight，眼睛图标 iconButtonIconSize。
        listPadding = 8,                -- 四周留白：边距、搜索行空白都落在面板底上，按住能拖整块面板
        listToolInset = 4,              -- 搜索框左缘 / 眼睛右缘离内容区边（列表本身不缩）
        listToolGap = 6,                -- 搜索框与眼睛之间、搜索行与列表之间
        listPinSize = 22,               -- 图钉按钮边长
        listPinX = 12,                  -- 图钉离面板左缘
        listPinY = 18,                  -- 图钉离面板上缘
        listEmptyInset = 7,             -- 没有光环时提示字离列表左上
        listEmptyWidth = 240,           -- 提示字宽
        listRailWidth = 68,             -- 收起时只显示图标列的面板宽
        listRailInset = 6,              -- 图标列离面板左 / 下缘
        listRailTop = 48,               -- 图标列离面板上缘（让出图钉）
        listMiniIcon = 36,              -- 图标列里光环图标边长
        listMiniIconInset = 2,          -- 图标贴图、类型条离图标按钮边
        listMiniKindBar = 3,            -- 图标底部类型条高
        listMiniRingRadius = 4,         -- 选中蓝框圆角
        listMiniGap = 6,                -- 图标 / 白框之间
        listMiniPad = 4,                -- 白框上下内距
        listMiniFolder = 14,            -- 白框顶部文件夹图标边长
        listMiniFolderGap = 3,          -- 文件夹图标到框内第一项
        listMiniBoxInset = 2,           -- 嵌套白框比外框左右各再缩（在 listMiniPad 之外）
        listMiniBoxBottom = 2,          -- 白框底部在 listMiniPad 之外再留
        listMiniBoxMinExtra = 8,        -- 嵌套白框至少比图标宽这么多
        listGhostWidth = 290,           -- 拖动时跟随指针的名字框
        listGhostHeight = 52,
        listGhostOffsetX = 16,          -- 名字框离指针（右、下）
        listGhostOffsetY = 12,
        listDropLine = 2,               -- 落点之前 / 之后的标记线粗
        -- 图标选取（载入页职业专精、种族、副本、首领面板）：格子 40、间距 6，首领面板约 400 宽。
        iconPickGap = 6,               -- 同一行里两项之间
        iconPickGridGap = 6,           -- 等分格之间（副本卡、首领卡）
        iconPickSeparatorGap = 4,      -- 竖分隔线左右留白
        iconPickSeparatorHeight = 32,  -- 竖分隔线高（格子高减上下各 4）
        iconPickRowPadY = 3,           -- 行上下内距（行距 6）
        iconPickSectionGap = 10,       -- 组与组之间
        iconPickColumnGap = 12,        -- 副本列表与首领卡之间
        iconPickNavWidth = 132,        -- 副本列表项宽
        iconPickNavHeight = 32,        -- 副本列表项高
    }

    -- 载入页选取面板（职业与专精 / 种族 / 副本 / 首领）：同 exaura，只是行不装进圆角带边卡（面板里不套内框）。
    styles.exauraPick = Derive(styles.exaura, {})
    styles.exauraPick.cardFill = nil

    -- 元素面板（贴在光环旁的窄面板）：控件收窄，名字和控件放得进同一行。
    styles.exauraPanel = Derive(styles.exaura, {
        shortWidth = 84,                -- 数字框宽：放得下带负号、一位小数的 5 位数（-4000.5），两个数字框加名字仍放得下一行
        prefixWidth = 16,               -- 数字框前缀占的宽（“X”“宽”）
        prefixGap = 4,                  -- 前缀（画在输入框外左边）到输入框左缘
        switchWidth = ExwindTools.GUIMetrics.size.switchTrackWidth, -- 不带文字的开关只占轨道宽
        sliderWidth = 176,              -- 不带文字的滑杆（数字框 48 + 轨道）
    })

    -- 条件面板（添加音效 / 添加动画）：每一步一行——左栏是放大的圆角方块序号 + 步骤名，右边固定 4 格，
    -- 步骤之间一条横线，不套卡片；“什么时候”是只有名字的格子，选中用卡片勾选框的右上角斜角小勾。
    styles.exauraSteps = Derive(styles.exaura, {
        stepSide = true,
        stepDotSize = 30,               -- 序号方块边长（比圆圈大一圈）
        stepDotBorder = 2,
        stepNumberFont = 17,
        stepTitleFont = 15,
        stepTitleHeight = 40,           -- 左栏按第一行（格子高）竖直居中
        groupGap = 13,                  -- 步骤之间（横线画在正中）
        optionCardCells = true,
        optionCardGap = 6,
        catalogTileWidth = 80,          -- 法术卡、动画卡比普通方格卡大一档，图标圆角也更圆
        catalogTileIcon = 52,
        catalogTileIconRadius = 10,
    })

    -- 载入页：文字列按标签实际字宽。
    styles.exauraLoad = Derive(styles.exaura, {
        labelAutoWidth = true,
        controlWidth = 150,             -- 标准控件宽
        shortWidth = 60,                -- size="short" 的宽
        -- 行下已选（职业专精、种族是图标；副本、首领是图标 + 名字）：图标比默认小号大一档，行上下不另留内距。
        iconPickSmall = 32,
        iconPickCell = 32,
        iconPickRowPadY = 0,
        iconPickSpacing = -4,           -- 已选图标行与前后行之间：压进两边的行内距，图标上下各只留 6
    })
end
