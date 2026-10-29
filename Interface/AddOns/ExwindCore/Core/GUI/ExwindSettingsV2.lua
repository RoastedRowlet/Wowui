-- V2 owns presentation. control/component nodes that declare `path` are bound by
-- the standard layer below (read, write, NotifyModuleValueChanged); nodes that
-- declare `ref` keep their owner adapters, records and writes.
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local Pages, Session = {}, {}
UI.SettingsDeclarationSchemaRevision = 19 -- Static declaration rules; bump when accepted schema changes.
local GM = _G.ExwindTools.GUIMetrics
if not GM then error("ExwindGUIMetrics.lua must load before ExwindSettingsV2.lua") end
local POOL, GAP, PAD = "EXUI.SettingsV2.Node", GM.space.settingsV2Gap, GM.space.settingsV2Padding
Factory:InitCompositePool(POOL)

-- 新种类的尺寸：页面样式预设（style）写了同名键用预设的，否则取 GM.settings.parts。
local function Part(style, key)
    local value = style and style[key]
    if value == nil then value = GM.settings.parts[key] end
    if value == nil then error("SettingsV2: GM.settings.parts." .. key .. " missing", 2) end
    return value
end

local Fields = {
    -- note = 页面写了 style 时标题条右侧的灰字（texts 引用名）；不写时显示“N 项”。
    -- addButton = 页面写了 style 时标题条最右侧的小按钮 { text = "＋", action = actions 引用名 }，点击调用 actions[action](context, mouseButton)。
    -- step = { done = predicates 引用名 }（只在样式页）：这张卡是步骤条的一步。Core 在卡左侧画圆圈（里面写序号）和连到下一步的竖线，
    -- 卡标题就是步骤名；done 返回真时圆圈实心主色、白字，页面里第一个没完成的步骤圆圈描主色边。序号按页面里步骤卡的顺序数。
    card = "title titleSource titlePosition titleAlign collapsible collapsed help note addButton children row column span gapBefore minBodyHeight bodyHeight overflow surface step",
    group = "title children", row = "children separator", cell = "children",
    actions = "children position align", columns = "columns children",
    -- 普通设置页的两种语义节点：setting = 左标签右控件；table = 列标题 + 每格控件。
    -- setting 左侧可选 toggle（勾选框，绑定存档 path，没勾时右侧控件变灰）或 icon（标签前的图标）。
    -- help = 页面写了 style 时标签后的小问号，悬停显示这段说明。
    -- helpSource = 同 help，但悬停时才取文字：texts 引用名，texts[helpSource](scope) 返回说明（动态提示，如地图名）；与 help 二选一。
    -- dimLabel = true：这一行写了 enabled、不可用时行名也变淡（不写只灰控件）。
    setting = "label description toggle icon help helpSource dimLabel children",
    -- table 可选记录操作：rowActions = 每行末尾按钮，addAction = 首行新增按钮（input 给出时，同一行首格放该输入框），
    -- selected = 高亮当前行的判断。
    -- 按行绑定的列表（表格里只有一个写了 path 的 repeat 时）：rowActions 每项可写 op = "remove" | "up" | "down"
    -- （代替 action；上移在首行、下移在末行自动变灰），addAction 可写 op = "add"（代替 action / clickKey，不写 input），
    -- 新行复制 repeat.rowDefaults。都整份写回 repeat.path 的数组（一次 commit）。
    -- 这种表格的新增行在最下面；样式页里 op 行操作画成图标按钮（text 进悬停提示）；没写 width/weight 的
    -- 数字框列只占控件宽，其余列分剩余宽。columns 的 width/weight 照旧可写。
    table = "columns children rowActions addAction selected",
    -- repeat 二选一：source = sources 引用名（owner 给记录）；path = 存档里的数组路径，每个元素（表）是一行。
    -- 写了 path 时模板里控件的 path / wrapPath、toggles 的 items[].path、preset 的 values 键、setting.toggle、
    -- 嵌套 repeat 的 path 可写 "@.字段"（@ = 当前行），挂载时换成 "数组路径.行号.字段"，照常读写并通知。
    -- rowDefaults = 新行的默认值（表格 addAction.op = "add" 用，只能和 path 一起写）。
    ["repeat"] = "source template path rowDefaults",
    -- placeholder = 输入框（controlType="input"，path 控件或 owner 用 CreateSettingsV2Control 建的记录控件）的占位字，
    -- 输入框为空时显示、占位灰；不写时没有占位字。
    -- allowEmpty = true 只用在分段（controlType="segment"）：值为空或不在选项里时不高亮任何一项；不写时照旧选第一项。
    -- fitText = true 只用在分段：每段按自己的文字宽（选项文字长短差很多时省宽、放得进一行）；不写时照旧各段等宽。
    -- 分段选项可写 tone = "include"（选中块绿，GC.filterInclude）| "exclude"（选中块红，GC.filterExclude）；不写时主色。
    -- trailingIcon + trailingAction（成对，只用在 input / number）：输入框内右侧的图标按钮（GUIIcons ID，如 "crosshair" 选框体），
    -- 点击调用 actions[trailingAction](context, mouseButton, commit)，commit(value) 写回本控件的 path 并刷新整页。
    -- prefix（一两个字，如 "X"、"宽"）或 prefixIcon（GUIIcons ID），二选一，只用在 input / number：prefix 画在框外左边，prefixIcon 画在框内左侧。
    -- percent = true 只用在滑杆（controlType="slider"）：数字框按百分比显示（0.08 显示 8%），输入 8 或 8% 都写回 0.08；
    -- min / max / step 仍写原始值。
    -- columns（只用在 optionlist）：横排几列的选择卡（图标 + 名字 + 一行描述，选中高亮），选项可写 icon（GUIIcons ID 或材质文件 ID）。
    -- 分段（segment）选项也可写 icon（GUIIcons ID），要写就每项都写：每段只显示图标，选项文字只作悬停提示。
    -- stepper = "right"（只用在 number）：数字框右侧带上加下减步进；不写时照旧不带步进。
    control = "ref custom controlType mode path label description options optionsSource media multiple search min max step inputWidthPercent size items placeholder allowEmpty fitText trailingIcon trailingAction prefix prefixIcon wrapPath noneText percent columns stepper",
    component = "ref custom component path label opts optionsRef",
    text = "text textSource", hint = "text textSource",
    -- icon = 页面写了 style 时的图标按钮（GUIIcons ID，text 必须为空）：宽 = 高，不受按钮最小宽限制。
    -- tip = 图标按钮（写了 icon）的悬停提示文字，按下即收起。
    button = "text action clickKey presentation icon tip",
    -- chips = 页面写了 style 时的一排可点标签（放不下自动换行）。source = sources 引用名，返回记录数组，
    -- 每条 { text = 文字, selected = 是否高亮（可选） }；select / remove / add 都是 actions 引用名（可选）：
    -- 点标签调用 actions[select](context, 记录)，点标签上的 × 调用 actions[remove](context, 记录)，
    -- 写了 add 时末尾多一个“＋”标签，点击调用 actions[add](context)。
    -- tristate = true：三态小标签（过滤）。记录写 state = nil（不限）| "include"（只看，绿底）| "exclude"（排除，红底），
    -- 可带 dot = { r, g, b }（文字前的色点）、tip = 悬停说明；点一下按 不限 → 只看 → 排除 → 不限 循环，
    -- 调用 actions[select](context, 记录, 新状态)（select 必填，owner 写好后 context:RefreshPage()）；不能写 add / remove，记录不写 selected。
    chips = "source select remove add tristate",
    -- summary = 可点摘要卡 / 列表行：一行标题（title 或 titleSource = texts 引用名）+ 可选摘要灰字（text 或 textSource），
    -- 可选 icon（行首图标：GUIIcons ID 或材质文件 ID）。action = 点整行调用 actions[action](context, mouseButton)；
    -- edit / remove = 尾部的编辑（铅笔）/ 删除（×）图标按钮，点击调用 actions[名](context, mouseButton)。
    -- 常作 repeat 的模板：context.scope.item 就是这一行的记录。
    summary = "title titleSource text textSource icon action edit remove",
    -- sentence = 两行句子卡（触发预览、条件规则卡共用），自己画卡面（预设 cardFill / cardBorder / cardRadius）。
    -- lineSource 必填、line2Source 可选：sources 引用名，sources[名](scope) 返回片段数组，每段二选一：
    --   { text = 文字, icon = 文字前小图标（可选） }
    --   { token = 词, action = actions 引用名（可选）, tips = { 悬停列表（可选） }, icon = 词前小图标（可选） }
    -- 有 action 的词画成可点小块，点击调用 actions[action](context, 这一段, 词的框体)（框体可作小浮框的锚）；
    -- 只有 tips 的词带下划线；都没有的词只换强调色。tips 每项是文字，或 { text, icon（可选）, dot = { r, g, b }（可选） }，
    -- 悬停时用提示框逐行列出。数组本身可带 icon 键 = 这一行行首的图标块（GUIIcons ID 或材质文件 ID）。
    -- icon 都是 GUIIcons ID 或材质文件 ID。edit / remove = 右上角编辑（铅笔）/ 删除（垃圾桶）图标按钮，
    -- 点击调用 actions[名](context, mouseButton)；selected = predicates 引用名（可选），为真时卡边换主色。
    -- 片段整句由 owner 按语言模板拼好；放不下时文字段按字（西文按词）换行，词不拆开。
    sentence = "lineSource line2Source edit remove selected",
    -- props = 小字键值区（作者、版本、链接、说明这类资料）：rows = { { 项, 项（可选）, 项（可选） }, ... }，每行 1～3 项，
    -- 项 = { label = 键名, path = 存档字段（字符串）, placeholder = 占位字（可选）, size = "short"（可选，窄框）,
    --        multiline = true（可选：平时一行，点进去展开多行）, trailingIcon + trailingAction（可选，成对：框后的图标按钮，
    --        点击调用 actions[trailingAction](context, mouseButton, 当前值, 全选)，全选() = 聚焦值框并选中全部文字）,
    --        prefixIcon = GUIIcons ID（可选，只给单行项：框内左侧灰色小图标代替键名，填了值图标变亮；
    --        这时 trailingIcon 画在框内右侧，只在有值时显示）,
    --        clampLines = N（可选，只给多行项：平时显示全文、最多 N 行，高度至少 N 行；超过才在右下出“展开”，
    --        点了完整展开、再点“收起”；点文字直接改，改时框高随全文） }。label 可省（不画键名列），不能和 prefixIcon 同写。
    -- 值框平时无边框、悬停显框、点了直接改；回车或离开时写回（多行只在离开时写回）。需要 owner.binding。
    -- 预设 propsMultilineFixed：多行项一直是 propsMultilineHeight 高的多行框（不收成一行预览），整块高度固定（clampLines 项不受它管）。
    props = "rows",
    -- catalog = 预览卡网格（样式卡、动画卡、新增面板共用）：source = sources 引用名，返回记录数组，
    -- 每条 { text = 名字, icon = 预览区图标（GUIIcons ID 或材质文件 ID，可选）, selected = 是否选中（可选） }；
    -- select = 点卡片调用 actions[select](context, 记录)（单选由 owner 写值后 context:RefreshPage()）；
    -- paint = owner.painters 引用名（可选）：painters[paint](预览区 Frame, 记录, context) 只画预览区内部
    -- （锚在这个 Frame 上），返回 nil 或清理函数（卡片重建 / 归还时调用）；写了 paint 时不画 icon。
    -- presentation = "entry"（可选，只在样式页）：入口卡（“添加音效”“添加动画”）——图标在左、名字在右的横条卡，
    -- 一行能放几张就并排几张、平分宽度；selected 的卡描主色边。不能和 paint 一起写。
    -- hover = owner.painters 引用名（可选，必须和 paint 一起写）：鼠标进 / 出卡片时调用
    -- painters[hover](预览区 Frame, 记录, 是否进入, context)（悬停预览动画这类）。
    -- title / description（可选，只在样式页）：网格上方一行小标题（灰字）和跟在后面的说明（更淡的灰字）。
    -- 记录可多带 dim = true（变暗、点了不选，悬停照常预览）和 tip = 悬停说明文字。
    -- presentation = "tile"（可选，只在样式页）：方格卡——图标（或 paint 的预览区）在上、一行名字在下，卡宽固定
    -- catalogTileWidth，每行最多 catalogTileColumns 张、靠左排；材质文件 ID 的图标裁掉自带黑边、圆角铺满；
    -- selected 照卡片勾选框画法（右上角主色斜角 + 白色小勾），多选由 owner 自己按记录切换。可以和 paint / hover 一起写。
    -- 方格卡的记录可多带 coords = { 左, 右, 上, 下 }：材质文件 ID 的图标只取这一块铺满（不再裁黑边），
    -- 例如副本按钮图取中间方块、首领 2:1 头像取中间方形。
    -- size = "large"（可选，只给方格卡）：大方格卡——样子、选中、悬停同方格卡，尺寸换成 catalogTileLarge*（宽、图标、圆角、字号、内距）。
    catalog = "source select paint presentation hover title description size",
    -- chipinput = 带图标的芯片列表 + 输入框（法术列表）：source 同 chips，记录可多带 icon（GUIIcons ID、材质文件 ID 或材质路径）；
    -- add 必填 = 在末尾输入框里回车时调用 actions[add](context, 输入文字)（去掉首尾空白，空字串不调用），随后清空输入框；
    -- remove / select 同 chips；placeholder = 输入框占位字（可选）。记录可带 spellID（法术 ID）：悬停标签显示该法术的提示。
    -- 预设 chipInputColumns + chipInputNamedMax：前 chipInputNamedMax 个标签按 chipInputColumns 列等宽排（图标 + 名字），
    -- 之后的带图标标签只显示图标（不显示文字），按宽度一行排满再换行；输入框排在最后。分列的名字只占一行，放不下省略号截断，
    -- 悬停看全名（带 spellID 的看法术提示）。
    -- 预设 chipInputFirst：输入框在最上面一行，标签从它下面往下加；超过 chipInputNamedMax 时先加入的先变成只有图标，
    -- 只有图标的排在带名字的上面。预设 chipIconCompact：只有图标的标签画成方块图标，右上角一个小红叉删除。
    -- 预设 chipInputHoverRemove：删除叉都是标签右上角的小叉（chipCornerRemoveSize），鼠标移到该标签上才显示。
    -- spanRow = true（可选）：是有行名的设置行里唯一的控件时，输入框和行名同一行（行名右边），
    -- 标签从下一行起、从行名左缘往右排满整行宽；别处写了不起作用。
    chipinput = "source select remove add placeholder spanRow",
    -- url = 可复制的只读网址框（点击全选、Ctrl+C 复制）：text 或 textSource 二选一，空字串时不显示。
    -- notice = 行内提示条（整行宽、文字换行）：text 或 textSource 二选一，tone = "info"（默认）| "ok" | "error"；空字串时不显示。
    url = "text textSource", notice = "text textSource tone",
    -- picklist = 分组多选列表（过滤面板）：source = sources 引用名，返回分组数组
    -- { { title = 组名, items = { { text = 文字, selected = 是否勾上（可选） }, ... } }, ... }（每项是唯一的原表）；
    -- toggle 必填 = 勾选 / 取消时调用 actions[toggle](context, 项, 新状态)，owner 写好后 context:RefreshPage()；
    -- placeholder = 搜索框占位字（可选）。顶上搜索框只筛显示，右侧显示“已选 n/m”；栏数、行高在 GM.settings.parts。
    picklist = "source toggle placeholder",
    -- iconpick = 图标选取（职业专精、种族、副本与首领这类）：source = sources 引用名，返回分组数组；toggle 必填 =
    -- 点一项时调用 actions[toggle](context, 项, 新状态)；remove = actions 引用名（可选）：项右上角出删除小叉（悬停才显示），
    -- 点叉调用 actions[remove](context, 项)。记录格式与排法见 ExwindIconPick.lua。
    iconpick = "source toggle remove",
    -- texturepreview = 材质大预览（按元素自己的颜色染色，可成对）：source = sources 引用名，返回一条记录。
    -- texturegrid = 材质缩略图网格：source = sources 引用名，返回 { tint, items }；select 必填 = 点格子调用
    -- actions[select](context, 项)。记录格式见 ExwindTexturePick.lua。
    texturepreview = "source", texturegrid = "source select",
}
-- advanced = true（所有节点可写）：渐进披露。页面里有这类节点时必须写 page.advanced，Core 在页末自动放一行
-- “高级 ›”（整页只有一行），点开在原位显示这些节点、再点收起。展开状态由 owner 记：
-- page.advanced = { expanded = predicates 引用名（返回是否展开）, toggle = actions 引用名（toggle(context, 新状态)，
-- 里面写下状态即可，Core 随后刷新整页）, visible = predicates 引用名（可选，返回 false 时不显示“高级 ›”这一行） }。
-- 不能用在 layout="grid" 的页面。
-- page.collapse = { state = predicates 引用名, toggle = actions 引用名 }（可选）：可折叠卡片（collapsible）的折叠状态交给 owner 记，
-- 页面重建后照旧。挂载和每次刷新时调用 predicates[state](scope, 卡片 id) 取状态：true = 收起，false = 展开，nil = 用声明的 collapsed；
-- 用户点标题折叠 / 展开时调用 actions[toggle](context, 卡片 id, 新状态)（true = 收起），里面写下即可，Core 随后刷新整页。
local Common = "id kind visible enabled width weight height advanced"
local ControlTypes = { input=true, multiline=true, checkbox=true, switch=true, card=true,
    choice=true, tristate=true, select=true, slider=true, color=true, field=true }
-- Standard binding layer: the control types and composite components a `path`
-- node may declare. Records, choice groups and custom content stay on owners.
-- segment = 单选分段（path 存所选 value）；toggles = 多选（角标勾小块，items 每项一个 boolean path，节点本身不写 path）。
-- multiline = 多行文字（导入导出字符串、备注），高度只能选标准或 size="tall"。
-- optionlist = 单选卡片列表（竖排，每项标题 + 可选说明），path 存所选 value。
-- number = 数字框（path 存数字，可写 min / max / step，宽度默认 short 档），可带前缀字母或图标。
-- preset = 一次写多个字段的预设下拉（节点不写 path）：options = { { label = 文字, values = { ["字段路径"] = 值, ... } }, ... }；
-- 选一项 = 把它的 values 全部写入存档；当前存档正好等于哪一项就显示哪一项，都不等时不选。
-- flow = 带图示的排列方向选择（Core 原生 FlowDirectionPicker，8 个缩略图）：path 存主方向、wrapPath 存换行方向
-- （"RIGHT" / "LEFT" / "UP" / "DOWN"）。
-- perline = 每行个数选择（Core 原生 PerLineSelector）：path 存正整数或 nil（不换行）；max = 方块个数（可选，默认 10），
-- noneText = “不限个数”按钮文字（可选，不写不显示）。
local PathControlTypes = { switch=true, checkbox=true, card=true, input=true, select=true, slider=true, color=true,
    segment=true, toggles=true, multiline=true, optionlist=true, number=true, preset=true, flow=true, perline=true }
local RowControlTypes = { switch=true, input=true, select=true, slider=true, color=true, segment=true, toggles=true,
    multiline=true, optionlist=true, number=true, preset=true, flow=true, perline=true }
local SelectMedia = { font=true, sound=true, statusbar=true, border=true, background=true }
-- soundselector = 连体声音选择（来源 | 内容 | ▶），path 是字段前缀：<path>Source/Label/LSM/Path/TtsText。
local StandardComponents = { fontgroup=true, icongroup=true, timerbargroup=true, anchorgroup=true,
    soundgroup=true, widgetlayout=true, modulecommonsettings=true, glow_settings=true, texturegroup=true,
    soundselector=true }
local PathControlFields = "controlType label description options optionsSource media multiple search min max step inputWidthPercent size items placeholder allowEmpty fitText trailingIcon trailingAction prefix prefixIcon wrapPath noneText percent columns stepper"
local PathOnlyFields = { "label", "description", "options", "optionsSource", "media", "multiple", "search",
    "min", "max", "step", "inputWidthPercent", "size", "items", "component", "opts", "optionsRef", "placeholder", "allowEmpty", "fitText",
    "trailingIcon", "trailingAction", "prefix", "prefixIcon", "wrapPath", "noneText", "percent", "columns", "stepper" }
-- 控件宽度档位：页面不写像素，只能选档位（省略 = 标准宽）。
local ControlSizes = { short=true, wide=true, tall=true }

-- =========================================================
-- 普通页规则（10-13 用户定）：页面标题 → 卡片 → 只有四种内容。
--   1 标准行（setting / 带 label 的 path 控件）  2 表格（table）
--   3 Core 封装控件（component）              4 自定义（只给下面两张名单）
-- 普通页不准写尺寸、灰字、手拼零件、卡片里悬空的按钮；卡片只有一种外观（标题在上）。
-- 名单只在这里改：FreeformPages = 整页自由布局；CustomParts = 普通页里允许的自定义件（节点写 custom="键"）。
-- =========================================================
local FreeformPages = {
    ["ExTools.SpellQueue"] = true,          -- Tools 全职业延迟容限
    ["ExClass.SpellEffectAlpha"] = true,    -- Tools 法术触发透明度
}
-- 调用方还可以在 owner 上再收窄一层：owner.allowedCustom = { [CustomParts 键] = "为什么标准种类做不到" }。
-- 给了它，页面里每个 custom 都必须在里面（挂载 / 打开二级面板时校验，照声明校验的方式报错）；不给照旧只查下面的 Core 名单。
local CustomParts = {
    ["EXBoss.VoiceTimeline"] = true,        -- 首领 / 小怪语音时间轴预览
    ["EXBoss.AuraSoundList"] = true,        -- 副本通用光环声音列表（虚拟滚动）
    ["EXBoss.HomeBrand"] = true,            -- 首页品牌与联系资料（非设置项）
    ["EXBoss.HomePeople"] = true,           -- 首页感谢人物卡（非设置项）
    ["EXAura.LuaEditor"] = true,            -- 代码编辑器
}
local StrictCardFields = { "titlePosition", "titleAlign", "help",
    "minBodyHeight", "bodyHeight", "overflow", "surface", "gapBefore" }
local StrictSizeFields = { "width", "weight", "height", "inputWidthPercent" }
-- 普通页里每种位置能放的节点。
-- group = 样式页里的“块”：一组行合成一块（常作 repeat 的 template，每条记录一块），块内行之间不画线、块与块之间一条线。
local StrictChildren = {
    card = { setting=true, control=true, component=true, table=true, ["repeat"]=true, group=true, chips=true, summary=true, catalog=true, chipinput=true, url=true, notice=true, picklist=true, iconpick=true, sentence=true, props=true, texturepreview=true, texturegrid=true },
    group = { setting=true, control=true, component=true, table=true, chips=true, summary=true, catalog=true, chipinput=true, url=true, notice=true, picklist=true, iconpick=true, sentence=true, props=true, texturepreview=true, texturegrid=true },
    setting = { control=true, button=true, component=true, text=true, chips=true, chipinput=true, url=true },
    table = { row=true, ["repeat"]=true },
    row = { cell=true },
    cell = { control=true, button=true, text=true },
}
local MaxSettingControls = 3
local AdapterMethods = { "mount", "update", "measure", "layout", "setEnabled", "setVisible", "release" }
local ControlMethods = { "mount", "release" }
local Build, MountNode, ReleaseNode, RefreshNode, LayoutNode, CollapseState
local Mounted = setmetatable({}, { __mode = "k" }) -- parent -> 存活的 V2 会话

local function Check(ok, message)
    if not ok then error("SettingsV2: " .. message, 3) end
end

local function Name(value)
    return type(value) == "string" and value ~= ""
end

local function Number(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function Keys(value, fields, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be a plain table")
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in pairs(value) do Check(allowed[field], where .. ": unknown field " .. tostring(field)) end
end

local function Array(value, where)
    Check(type(value) == "table" and getmetatable(value) == nil, where .. " must be an array")
    local count = 0
    for key in pairs(value) do
        Check(type(key) == "number" and key >= 1 and key % 1 == 0, where .. ": invalid array index")
        count = count + 1
    end
    for i = 1, count do Check(value[i] ~= nil, where .. ": sparse array") end
    return count
end

-- Copy declarations only; never used for owner data or records.
local function DeclarationCopy(value, seen)
    local kind = type(value)
    Check(kind == "table" or kind == "string" or kind == "number" or kind == "boolean" or kind == "nil",
        "declarations must contain only data")
    if kind ~= "table" then return value end
    Check(not seen[value] and getmetatable(value) == nil, "cyclic/metatable declaration")
    seen[value] = true
    local copy = {}
    for key, entry in pairs(value) do
        Check(type(key) == "string" or type(key) == "number", "invalid declaration key")
        copy[key] = DeclarationCopy(entry, seen)
    end
    seen[value] = nil
    return copy
end

local function Reference(owner, bucket, name, where)
    Check(Name(name), where .. " requires a named reference")
    if not owner then return end
    local value = owner[bucket] and owner[bucket][name]
    Check(type(value) == "function", where .. ": missing " .. bucket .. "." .. name)
end

-- All expected declaration failures travel as data. No callbacks or metamethods
-- are evaluated during preflight, including owner reference lookup.
local function Issue(path, message, nodeId, code)
    return false, { code=code or "INVALID_SCHEMA", path=path, nodeId=nodeId, message=message }
end

local function Pure(value, path, seen)
    local kind = type(value)
    if kind ~= "table" then
        if kind == "nil" or kind == "string" or kind == "boolean"
            or (kind == "number" and value == value and math.abs(value) < math.huge) then return true end
        return Issue(path, "declarations must contain finite plain data")
    end
    if getmetatable(value) ~= nil or seen[value] then return Issue(path, "cyclic/metatable declaration") end
    seen[value] = true
    for key, entry in next, value do
        if type(key) ~= "string" and type(key) ~= "number" then return Issue(path, "invalid declaration key") end
        local ok, issue = Pure(entry, path .. "." .. tostring(key), seen)
        if not ok then return false, issue end
    end
    seen[value] = nil
    return true
end

local function SchemaKeys(value, fields, path, id)
    if type(value) ~= "table" then return Issue(path, "expected a plain table", id) end
    local allowed = {}
    for field in fields:gmatch("%S+") do allowed[field] = true end
    for field in next, value do
        if not allowed[field] then return Issue(path .. "." .. tostring(field), "unknown field", id) end
    end
    return true
end

local function SchemaArray(value, path, id)
    if type(value) ~= "table" then return Issue(path, "expected an array", id) end
    local count = 0
    for key in next, value do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return Issue(path, "invalid array index", id) end
        count = count + 1
    end
    for i = 1, count do
        if rawget(value, i) == nil then return Issue(path .. "[" .. i .. "]", "sparse array", id) end
    end
    return true, count
end

local function SchemaReference(owner, bucket, name, path, id)
    if not Name(name) then return Issue(path, "named reference required", id) end
    if owner == nil then return true end
    local refs = rawget(owner, bucket)
    if type(refs) ~= "table" or type(rawget(refs, name)) ~= "function" then
        return Issue(path, "missing " .. bucket .. "." .. name, id)
    end
    return true
end

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- path/clickKey nodes write through owner.binding = { moduleKey, config }.
local function SchemaBinding(owner, path, id)
    if owner == nil then return true end
    local binding = rawget(owner, "binding")
    if type(binding) ~= "table" or not Name(rawget(binding, "moduleKey")) or type(rawget(binding, "config")) ~= "table" then
        return Issue(path, "path binding requires owner.binding { moduleKey, config }", id)
    end
    return true
end

-- Shared by declaration nodes and owner-built standard controls.
local function SchemaPathControl(spec, path, id)
    local function fail(field, message) return Issue(path .. "." .. field, message, id) end
    local kind = spec.controlType
    if not PathControlTypes[kind] then return fail("controlType", "path control requires switch/checkbox/card/input/select/slider/color/segment/toggles") end
    if spec.mode ~= nil then return fail("mode", "mode belongs to owner choice controls") end
    for _, field in ipairs({ "label", "description" }) do
        if spec[field] ~= nil and type(spec[field]) ~= "string" then return fail(field, "expected string") end
    end
    if kind == "card" and type(spec.label) ~= "string" then
        return fail("label", "label required")
    end
    if kind ~= "select" and kind ~= "segment" and kind ~= "optionlist" and kind ~= "preset" and (spec.options ~= nil or spec.optionsSource ~= nil) then
        return fail("options", "options require select, segment, optionlist or preset")
    end
    if kind ~= "select" and (spec.media ~= nil or spec.multiple ~= nil or spec.search ~= nil) then
        return fail("media", "media/multiple/search require select")
    end
    if kind ~= "slider" and kind ~= "number" and (spec.min ~= nil or (spec.max ~= nil and kind ~= "perline") or spec.step ~= nil) then return fail("min", "bounds require slider or number") end
    if (spec.wrapPath ~= nil) ~= (kind == "flow") or (kind == "flow" and not Name(spec.wrapPath)) then return fail("wrapPath", "flow requires wrapPath (and only flow takes it)") end
    if spec.noneText ~= nil and (kind ~= "perline" or not Name(spec.noneText)) then return fail("noneText", "noneText is a non-empty string on perline") end
    if spec.percent ~= nil and (kind ~= "slider" or spec.percent ~= true) then return fail("percent", "percent = true only on slider") end
    if kind == "perline" and spec.max ~= nil and not (Number(spec.max) and spec.max % 1 == 0) then return fail("max", "perline max is a positive integer") end
    if spec.columns ~= nil and (kind ~= "optionlist" or not (Number(spec.columns) and spec.columns % 1 == 0 and spec.columns <= 4)) then
        return fail("columns", "columns is an integer 1..4 on optionlist")
    end
    local textBox = kind == "input" or kind == "number"
    if (spec.trailingIcon ~= nil) ~= (spec.trailingAction ~= nil) then return fail("trailingIcon", "trailingIcon and trailingAction go together") end
    if spec.trailingIcon ~= nil then
        if not textBox then return fail("trailingIcon", "trailing button requires input or number") end
        if not (type(spec.trailingIcon) == "string" and _G.ExwindTools.GUIIcons.ids[spec.trailingIcon]) then return fail("trailingIcon", "expected a registered GUIIcons id") end
        if not Name(spec.trailingAction) then return fail("trailingAction", "named reference required") end
    end
    if spec.prefix ~= nil and spec.prefixIcon ~= nil then return fail("prefix", "use prefix or prefixIcon") end
    if (spec.prefix ~= nil or spec.prefixIcon ~= nil) and not textBox then return fail("prefix", "prefix requires input or number") end
    if spec.prefix ~= nil and not (Name(spec.prefix) and #spec.prefix <= 6) then return fail("prefix", "prefix is one or two characters") end
    if spec.prefixIcon ~= nil and not (type(spec.prefixIcon) == "string" and _G.ExwindTools.GUIIcons.ids[spec.prefixIcon]) then return fail("prefixIcon", "expected a registered GUIIcons id") end
    if kind ~= "input" and spec.inputWidthPercent ~= nil then return fail("inputWidthPercent", "requires input") end
    if spec.stepper ~= nil and (kind ~= "number" or spec.stepper ~= "right") then return fail("stepper", "stepper = \"right\" only on number") end
    if spec.placeholder ~= nil and (kind ~= "input" or not Name(spec.placeholder)) then
        return fail("placeholder", "placeholder is a non-empty string on input")
    end
    if spec.allowEmpty ~= nil and (kind ~= "segment" or spec.allowEmpty ~= true) then
        return fail("allowEmpty", "allowEmpty = true only on segment")
    end
    if spec.fitText ~= nil and (kind ~= "segment" or spec.fitText ~= true) then
        return fail("fitText", "fitText = true only on segment")
    end
    if spec.size ~= nil and (not ControlSizes[spec.size]
        or (spec.size == "tall") ~= (kind == "multiline") or (kind ~= "input" and kind ~= "number" and kind ~= "select" and kind ~= "multiline")) then
        return fail("size", "size is short/wide on input, number or select, tall on multiline")
    end
    if (spec.items ~= nil) ~= (kind == "toggles") then return fail("items", "items belong to toggles") end
    if kind == "toggles" then
        local ok, issue = SchemaArray(spec.items, path .. ".items", id)
        if not ok then return false, issue end
        if issue == 0 then return fail("items", "toggles requires items") end
        for i, item in ipairs(spec.items) do
            local at = path .. ".items[" .. i .. "]"
            ok, issue = SchemaKeys(item, "label path", at, id)
            if not ok then return false, issue end
            if type(item.label) ~= "string" or not Name(item.path) then return Issue(at, "toggle item requires label and path", id) end
        end
    elseif kind == "preset" then
        if spec.options == nil then return fail("options", "preset requires options") end
        local ok, issue = SchemaArray(spec.options, path .. ".options", id)
        if not ok then return false, issue end
        if issue == 0 then return fail("options", "preset requires options") end
        for i, option in ipairs(spec.options) do
            local at = path .. ".options[" .. i .. "]"
            ok, issue = SchemaKeys(option, "label values", at, id)
            if not ok then return false, issue end
            if type(option.label) ~= "string" then return Issue(at .. ".label", "expected string", id) end
            if type(option.values) ~= "table" or next(option.values) == nil then return Issue(at .. ".values", "expected { path = value, ... }", id) end
            for fieldPath, fieldValue in next, option.values do
                if not Name(fieldPath) then return Issue(at .. ".values", "keys are field paths", id) end
                if type(fieldValue) ~= "string" and type(fieldValue) ~= "boolean" and not Finite(fieldValue) then
                    return Issue(at .. ".values." .. fieldPath, "expected string, number or boolean", id)
                end
            end
        end
    elseif kind == "segment" or kind == "optionlist" then
        if spec.options == nil then return fail("options", kind .. " requires options") end
        local ok, issue = SchemaArray(spec.options, path .. ".options", id)
        if not ok then return false, issue end
        for i, option in ipairs(spec.options) do
            local at = path .. ".options[" .. i .. "]"
            ok, issue = SchemaKeys(option, kind == "optionlist" and "value label description icon" or "value label tone icon", at, id)
            if not ok then return false, issue end
            if option.tone ~= nil and option.tone ~= "include" and option.tone ~= "exclude" then
                return Issue(at .. ".tone", "expected include or exclude", id)
            end
            if type(option.label) ~= "string" then return Issue(at .. ".label", "expected string", id) end
            if option.description ~= nil and type(option.description) ~= "string" then return Issue(at .. ".description", "expected string", id) end
            if option.icon ~= nil and kind == "optionlist" and spec.columns == nil then return Issue(at .. ".icon", "option icon requires columns", id) end
            if kind == "segment" and (option.icon ~= nil) ~= (spec.options[1].icon ~= nil) then
                return Issue(at .. ".icon", "segment icons go on every option or none", id)
            end
            if kind == "segment" and option.icon ~= nil and type(option.icon) ~= "string" then
                return Issue(at .. ".icon", "segment icon is a GUIIcons id", id)
            end
            if option.icon ~= nil and not ((type(option.icon) == "string" and _G.ExwindTools.GUIIcons.ids[option.icon])
                or (Number(option.icon) and option.icon % 1 == 0)) then
                return Issue(at .. ".icon", "expected a registered GUIIcons id or a texture file id", id)
            end
            if type(option.value) ~= "string" and type(option.value) ~= "boolean" and not Finite(option.value) then
                return Issue(at .. ".value", "expected string, number or boolean", id)
            end
        end
    end
    if kind == "select" then
        local sources = (spec.options ~= nil and 1 or 0) + (spec.optionsSource ~= nil and 1 or 0) + (spec.media ~= nil and 1 or 0)
        if sources ~= 1 then return fail("options", "select requires exactly one of options, optionsSource, media") end
        if spec.multiple ~= nil and type(spec.multiple) ~= "boolean" then return fail("multiple", "expected boolean") end
        if spec.search ~= nil and type(spec.search) ~= "boolean" then return fail("search", "expected boolean") end
        if spec.media ~= nil and (not SelectMedia[spec.media] or spec.multiple ~= nil) then
            return fail("media", "media requires a single font/sound/statusbar/border/background select")
        end
        if spec.optionsSource ~= nil and (type(spec.optionsSource) ~= "string"
            or not spec.optionsSource:match("^[%a_][%w_%.]*$")) then
            return fail("optionsSource", "expected a global provider name")
        end
        if spec.options ~= nil then
            local ok, issue = SchemaArray(spec.options, path .. ".options", id)
            if not ok then return false, issue end
            local seen = {}
            for i, option in ipairs(spec.options) do
                local at = path .. ".options[" .. i .. "]"
                ok, issue = SchemaKeys(option, "value label", at, id)
                if not ok then return false, issue end
                if type(option.label) ~= "string" then return Issue(at .. ".label", "expected string", id) end
                local valueType = type(option.value)
                if valueType ~= "string" and valueType ~= "boolean" and not Finite(option.value) then
                    return Issue(at .. ".value", "expected string, number or boolean", id)
                end
                if seen[option.value] then return Issue(at .. ".value", "duplicate option value", id) end
                seen[option.value] = true
            end
        end
    elseif kind == "slider" then
        for _, field in ipairs({ "min", "max", "step" }) do
            if spec[field] ~= nil and not Finite(spec[field]) then return fail(field, "expected a finite number") end
        end
        if (spec.min or 0) > (spec.max or 100) or (spec.step or 1) <= 0 then return fail("step", "invalid slider bounds or step") end
    elseif kind == "number" then
        for _, field in ipairs({ "min", "max", "step" }) do
            if spec[field] ~= nil and not Finite(spec[field]) then return fail(field, "expected a finite number") end
        end
        if (spec.min and spec.max and spec.min > spec.max) or (spec.step or 1) <= 0 then return fail("step", "invalid number bounds or step") end
    elseif kind == "input" and spec.inputWidthPercent ~= nil and not Number(spec.inputWidthPercent) then
        return fail("inputWidthPercent", "expected a positive finite number")
    end
    return true
end

-- 文字字段二选一：field = 固定文字，sourceField = texts 引用名；required 时必须写一个。
local function SchemaText(node, owner, field, sourceField, required, path, id)
    if node[field] ~= nil and node[sourceField] ~= nil then return Issue(path .. "." .. field, "use " .. field .. " or " .. sourceField, id) end
    if node[sourceField] ~= nil then return SchemaReference(owner, "texts", node[sourceField], path .. "." .. sourceField, id) end
    if node[field] ~= nil and type(node[field]) ~= "string" then return Issue(path .. "." .. field, "expected string", id) end
    if required and node[field] == nil then return Issue(path .. "." .. field, field .. " or " .. sourceField .. " required", id) end
    return true
end

local NoticeToneNames = { info = true, ok = true, error = true }

-- 图标值：GUIIcons 登记的 ID，或材质文件 ID（正整数）。
local function IconValue(value)
    return (type(value) == "string" and _G.ExwindTools.GUIIcons.ids[value] ~= nil) or (Number(value) and value % 1 == 0)
end

-- styled = 页面 style 对应的 GM.settings.styles 预设表（没写 style 为 nil）；note、help 只在样式页里允许。
-- rowScope = 在写了 path 的 repeat 模板里（"@.字段" 只能写在这里）。
local function ValidateNode(node, owner, ids, depth, location, columnCount, path, styled, rowScope)
    if type(node) ~= "table" or not Fields[node.kind] then return Issue(path, "unknown node kind") end
    local kind, id = node.kind, node.id
    local function fail(field, message) return Issue(path .. (field and "." .. field or ""), message, id) end
    local ok, issue = SchemaKeys(node, Common .. " " .. Fields[kind], path, id)
    if not ok then return false, issue end
    local rowField, rowMessage = Session._rows.PathIssue(node, rowScope)
    if rowField then return fail(rowField, rowMessage) end
    if not Name(id) or ids[id] then return fail("id", "missing/duplicate node id") end
    ids[id] = true
    if node.advanced ~= nil and node.advanced ~= true then return fail("advanced", "expected true") end
    local top = location == "page"
    if top and kind ~= "card" and kind ~= "repeat" then return fail("kind", "page accepts card/repeat") end
    if not top and kind == "card" then return fail("kind", "card must be at page level") end
    if kind == "actions" and (location ~= "row" or columnCount) then return fail("kind", "actions requires a flow row") end
    if kind == "cell" and (location ~= "row" or not columnCount) then return fail("kind", "cell requires a shared-column row") end
    for _, field in ipairs({ "width", "weight", "height" }) do
        if node[field] ~= nil and not Number(node[field]) then return fail(field, "expected a positive finite number") end
    end
    if node.width and node.weight then return fail("weight", "width and weight are exclusive") end
    if (node.width or node.weight) and not ((location == "row" or location == "actions") and not columnCount) then
        return fail("width", "width/weight require a flow item")
    end
    if node.height and kind ~= "control" and kind ~= "component" and kind ~= "button" and kind ~= "text" and kind ~= "hint" then
        return fail("height", "height is leaf-only")
    end
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then
            ok, issue = SchemaReference(owner, "predicates", node[field], path .. "." .. field, id)
            if not ok then return false, issue end
        end
    end
    if kind == "card" or kind == "group" then
        if kind == "card" and node.titleSource ~= nil then
            if node.title ~= nil then return fail("title", "use title or titleSource") end
            ok, issue = SchemaReference(owner, "texts", node.titleSource, path .. ".titleSource", id)
            if not ok then return false, issue end
        elseif type(node.title) ~= "string" then return fail("title", "title required") end
        if kind == "card" then
            if node.bodyHeight ~= nil and not Number(node.bodyHeight) then return fail("bodyHeight", "positive finite height required") end
            if node.bodyHeight ~= nil and node.minBodyHeight ~= nil then return fail("minBodyHeight", "bodyHeight and minBodyHeight are exclusive") end
            if node.overflow ~= nil and node.overflow ~= "scroll" then return fail("overflow", "expected scroll") end
            if (node.bodyHeight ~= nil) ~= (node.overflow ~= nil) then return fail("bodyHeight", "bodyHeight and overflow=scroll required together") end
            if node.surface ~= nil and node.surface ~= "none" then return fail("surface", "expected none") end
            for _, field in ipairs({ "row", "column", "span" }) do
                if node[field] ~= nil and (not Number(node[field]) or node[field] % 1 ~= 0) then
                    return fail(field, "expected a positive integer")
                end
            end
            for _, field in ipairs({ "gapBefore", "minBodyHeight" }) do
                if node[field] ~= nil and (not Finite(node[field]) or node[field] < 0) then
                    return fail(field, "expected a non-negative finite number")
                end
            end
            if node.titlePosition ~= nil and node.titlePosition ~= "top" and node.titlePosition ~= "bottom"
                and node.titlePosition ~= "legend" then return fail("titlePosition", "invalid title position") end
            if node.titleAlign ~= nil and node.titleAlign ~= "start" and node.titleAlign ~= "center" then return fail("titleAlign", "invalid title alignment") end
            for _, field in ipairs({ "collapsible", "collapsed" }) do
                if node[field] ~= nil and type(node[field]) ~= "boolean" then return fail(field, "expected boolean") end
            end
            if node.collapsed and not node.collapsible then return fail("collapsed", "collapsed requires collapsible") end
            if node.help ~= nil and not Name(node.help) then return fail("help", "expected non-empty help") end
            if node.note ~= nil then
                if not styled then return fail("note", "note requires a page style") end
                ok, issue = SchemaReference(owner, "texts", node.note, path .. ".note", id)
                if not ok then return false, issue end
            end
            if node.step ~= nil then
                if not styled then return fail("step", "step requires a page style") end
                ok, issue = SchemaKeys(node.step, "done", path .. ".step", id)
                if ok then ok, issue = SchemaReference(owner, "predicates", node.step.done, path .. ".step.done", id) end
                if not ok then return false, issue end
                if node.collapsible then return fail("step", "step cards are not collapsible") end
            end
            if node.addButton ~= nil then
                if not styled then return fail("addButton", "addButton requires a page style") end
                local at = path .. ".addButton"
                ok, issue = SchemaKeys(node.addButton, "text action", at, id)
                if not ok then return false, issue end
                if type(node.addButton.text) ~= "string" or node.addButton.text == "" then return Issue(at .. ".text", "text required", id) end
                ok, issue = SchemaReference(owner, "actions", node.addButton.action, at .. ".action", id)
                if not ok then return false, issue end
            end
        end
    elseif (kind == "control" or kind == "component") and (node.path ~= nil or node.controlType == "toggles" or node.controlType == "preset") then
        if node.ref ~= nil or node.custom ~= nil then return fail("ref", "use ref or path") end
        if node.controlType == "toggles" or node.controlType == "preset" then
            if node.path ~= nil then return fail("path", node.controlType == "toggles" and "toggles writes items[].path, not path" or "preset writes options[].values, not path") end
        elseif not Name(node.path) then return fail("path", "expected a non-empty path") end
        if kind == "control" then
            ok, issue = SchemaPathControl(node, path, id)
            if not ok then return false, issue end
        else
            if not StandardComponents[node.component] then return fail("component", "unknown standard component") end
            if node.label ~= nil and type(node.label) ~= "string" then return fail("label", "expected string") end
            if node.opts ~= nil and type(node.opts) ~= "table" then return fail("opts", "expected a plain table") end
            -- optionsRef names owner.options[ref]: runtime options (callbacks) merged over opts.
            if node.optionsRef ~= nil then
                if not Name(node.optionsRef) then return fail("optionsRef", "expected a named reference") end
                if owner then
                    local options = rawget(owner, "options")
                    if type(options) ~= "table" or type(rawget(options, node.optionsRef)) ~= "table" then
                        return fail("optionsRef", "missing options." .. node.optionsRef)
                    end
                end
            end
        end
        ok, issue = SchemaBinding(owner, path .. ".path", id)
        if ok and node.trailingAction ~= nil then
            ok, issue = SchemaReference(owner, "actions", node.trailingAction, path .. ".trailingAction", id)
        end
        if not ok then return false, issue end
    elseif kind == "control" or kind == "component" then
        if not Name(node.ref) then return fail("ref", "reference required") end
        if node.custom ~= nil and not CustomParts[node.custom] then return fail("custom", "not in the Core custom list") end
        -- 调用方白名单（owner.allowedCustom，可选）：给了就只准用登记过的自定义件；没给照旧只查 Core 名单。
        if node.custom ~= nil and owner and rawget(owner, "allowedCustom") ~= nil
            and rawget(rawget(owner, "allowedCustom"), node.custom) == nil then
            return Issue(path .. ".custom", "自定义件“" .. node.custom .. "”没有登记在本页 owner.allowedCustom 白名单里："
                .. "先确认标准种类做不到，再在 allowedCustom 里加 [\"" .. node.custom .. "\"] = \"为什么标准种类做不到\"，"
                .. "否则改用标准种类", id, "NOT_STANDARD")
        end
        for _, field in ipairs(PathOnlyFields) do
            if node[field] ~= nil then return fail(field, "requires path") end
        end
        if kind == "control" and not ControlTypes[node.controlType] then return fail("controlType", "invalid control type") end
        if node.mode ~= nil and (node.controlType ~= "choice" or (node.mode ~= "single" and node.mode ~= "multiple")) then return fail("mode", "invalid choice mode") end
        if owner then
            local bucket = rawget(owner, kind == "control" and "controls" or "components")
            local adapter = type(bucket) == "table" and rawget(bucket, node.ref)
            if type(adapter) ~= "table" then return fail("ref", "missing owner adapter " .. node.ref) end
            for _, method in ipairs(kind == "control" and ControlMethods or AdapterMethods) do
                if type(rawget(adapter, method)) ~= "function" then return fail("ref", "adapter missing " .. method) end
            end
            for _, method in ipairs(AdapterMethods) do
                if rawget(adapter, method) ~= nil and type(rawget(adapter, method)) ~= "function" then return fail("ref", "invalid adapter " .. method) end
            end
        end
    elseif kind == "button" then
        if type(node.text) ~= "string" then return fail("text", "text required") end
        if (node.action ~= nil) == (node.clickKey ~= nil) then return fail("action", "use action or clickKey") end
        if node.clickKey ~= nil then
            if not Name(node.clickKey) then return fail("clickKey", "expected a non-empty key") end
            ok, issue = SchemaBinding(owner, path .. ".clickKey", id)
        else
            ok, issue = SchemaReference(owner, "actions", node.action, path .. ".action", id)
        end
        if not ok then return false, issue end
        if node.presentation ~= nil and node.presentation ~= "primary" and node.presentation ~= "secondary" and node.presentation ~= "danger" then return fail("presentation", "invalid button presentation") end
        if node.tip ~= nil and (type(node.tip) ~= "string" or node.icon == nil) then return fail("tip", "tip is a string on icon buttons") end
        if node.icon ~= nil then
            if not styled then return fail("icon", "icon requires a page style") end
            if not (type(node.icon) == "string" and _G.ExwindTools.GUIIcons.ids[node.icon]) then
                return fail("icon", "expected a registered GUIIcons id")
            end
            if node.text ~= "" then return fail("text", "icon button requires empty text") end
            if node.presentation ~= nil then return fail("presentation", "icon button has one appearance") end
        end
    elseif kind == "chips" then
        if not styled then return fail("kind", "chips requires a page style") end
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if not ok then return false, issue end
        if node.tristate ~= nil then
            if node.tristate ~= true then return fail("tristate", "expected true") end
            if node.select == nil then return fail("select", "tristate chips require select (actions[select](context, record, nextState))") end
            if node.add ~= nil or node.remove ~= nil then return fail("tristate", "tristate chips take no add / remove") end
        end
        for _, field in ipairs({ "select", "remove", "add" }) do
            if node[field] ~= nil then
                ok, issue = SchemaReference(owner, "actions", node[field], path .. "." .. field, id)
                if not ok then return false, issue end
            end
        end
    elseif kind == "url" or kind == "notice" then
        if (node.text ~= nil) == (node.textSource ~= nil) then return fail("text", "use text or textSource") end
        ok, issue = SchemaText(node, owner, "text", "textSource", true, path, id)
        if not ok then return false, issue end
        if node.tone ~= nil and not NoticeToneNames[node.tone] then return fail("tone", "expected info, ok or error") end
    elseif kind == "iconpick" then
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if ok then ok, issue = SchemaReference(owner, "actions", node.toggle, path .. ".toggle", id) end
        if ok and node.remove ~= nil then ok, issue = SchemaReference(owner, "actions", node.remove, path .. ".remove", id) end
        if not ok then return false, issue end
    elseif kind == "texturepreview" then
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if not ok then return false, issue end
    elseif kind == "texturegrid" then
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if ok then ok, issue = SchemaReference(owner, "actions", node.select, path .. ".select", id) end
        if not ok then return false, issue end
    elseif kind == "picklist" then
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if ok then ok, issue = SchemaReference(owner, "actions", node.toggle, path .. ".toggle", id) end
        if not ok then return false, issue end
        if node.placeholder ~= nil and not Name(node.placeholder) then return fail("placeholder", "expected non-empty string") end
    elseif kind == "chipinput" then
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if ok then ok, issue = SchemaReference(owner, "actions", node.add, path .. ".add", id) end
        for _, field in ipairs({ "select", "remove" }) do
            if ok and node[field] ~= nil then ok, issue = SchemaReference(owner, "actions", node[field], path .. "." .. field, id) end
        end
        if not ok then return false, issue end
        if node.placeholder ~= nil and not Name(node.placeholder) then return fail("placeholder", "expected non-empty string") end
        if node.spanRow ~= nil and node.spanRow ~= true then return fail("spanRow", "expected true") end
    elseif kind == "catalog" then
        if node.presentation ~= nil then
            if node.presentation ~= "entry" and node.presentation ~= "tile" then return fail("presentation", "expected entry or tile") end
            if not styled then return fail("presentation", "entry and tile cards require a page style") end
            if node.presentation == "entry" and node.paint ~= nil then return fail("paint", "entry cards take no painter") end
        end
        if node.size ~= nil then
            if node.size ~= "large" then return fail("size", "expected large") end
            if node.presentation ~= "tile" then return fail("size", "size only applies to tile cards") end
        end
        ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id)
        if ok and node.select ~= nil then ok, issue = SchemaReference(owner, "actions", node.select, path .. ".select", id) end
        if ok and node.paint ~= nil then ok, issue = SchemaReference(owner, "painters", node.paint, path .. ".paint", id) end
        if ok and node.hover ~= nil then
            if node.paint == nil then return fail("hover", "hover requires paint") end
            ok, issue = SchemaReference(owner, "painters", node.hover, path .. ".hover", id)
        end
        if not ok then return false, issue end
        for _, field in ipairs({ "title", "description" }) do
            if node[field] ~= nil then
                if type(node[field]) ~= "string" then return fail(field, "expected string") end
                if not styled then return fail(field, "catalog headings require a page style") end
                if node.presentation ~= nil then return fail(field, "entry and tile cards take no heading") end
            end
        end
    elseif kind == "summary" then
        ok, issue = SchemaText(node, owner, "title", "titleSource", true, path, id)
        if ok then ok, issue = SchemaText(node, owner, "text", "textSource", false, path, id) end
        if not ok then return false, issue end
        for _, field in ipairs({ "action", "edit", "remove" }) do
            if node[field] ~= nil then
                ok, issue = SchemaReference(owner, "actions", node[field], path .. "." .. field, id)
                if not ok then return false, issue end
            end
        end
        if node.icon ~= nil and not IconValue(node.icon) then return fail("icon", "expected a registered GUIIcons id or a texture file id") end
    elseif kind == "props" then
        if not styled then return fail("kind", "props requires a page style") end
        ok, issue = SchemaArray(node.rows, path .. ".rows", id)
        if not ok then return false, issue end
        if issue == 0 then return fail("rows", "props requires rows") end
        ok, issue = SchemaBinding(owner, path .. ".rows", id)
        if not ok then return false, issue end
        for i, row in ipairs(node.rows) do
            local rowPath = path .. ".rows[" .. i .. "]"
            ok, issue = SchemaArray(row, rowPath, id)
            if not ok then return false, issue end
            if issue < 1 or issue > 3 then return Issue(rowPath, "each props row holds 1 to 3 items", id) end
            for j, item in ipairs(row) do
                local at = rowPath .. "[" .. j .. "]"
                ok, issue = SchemaKeys(item, "label prefixIcon path placeholder size multiline clampLines trailingIcon trailingAction", at, id)
                if not ok then return false, issue end
                if item.label ~= nil and not Name(item.label) then return Issue(at .. ".label", "expected non-empty string", id) end
                if item.prefixIcon ~= nil then
                    if item.label ~= nil then return Issue(at .. ".prefixIcon", "prefixIcon replaces label (not both)", id) end
                    if not (type(item.prefixIcon) == "string" and _G.ExwindTools.GUIIcons.ids[item.prefixIcon]) then
                        return Issue(at .. ".prefixIcon", "expected a registered GUIIcons id", id)
                    end
                    if item.multiline then return Issue(at .. ".prefixIcon", "prefixIcon is for single-line items", id) end
                end
                if item.clampLines ~= nil then
                    if not (item.multiline and type(item.clampLines) == "number" and item.clampLines >= 1 and item.clampLines % 1 == 0) then
                        return Issue(at .. ".clampLines", "expected a positive integer on a multiline item", id)
                    end
                end
                if not Name(item.path) then return Issue(at .. ".path", "expected a non-empty path", id) end
                if item.placeholder ~= nil and not Name(item.placeholder) then return Issue(at .. ".placeholder", "expected non-empty string", id) end
                if item.size ~= nil and item.size ~= "short" then return Issue(at .. ".size", "expected short", id) end
                if item.multiline ~= nil and item.multiline ~= true then return Issue(at .. ".multiline", "expected true", id) end
                if (item.trailingIcon ~= nil) ~= (item.trailingAction ~= nil) then return Issue(at .. ".trailingIcon", "trailingIcon and trailingAction go together", id) end
                if item.trailingIcon ~= nil then
                    if not (type(item.trailingIcon) == "string" and _G.ExwindTools.GUIIcons.ids[item.trailingIcon]) then
                        return Issue(at .. ".trailingIcon", "expected a registered GUIIcons id", id)
                    end
                    ok, issue = SchemaReference(owner, "actions", item.trailingAction, at .. ".trailingAction", id)
                    if not ok then return false, issue end
                end
                if item.multiline and (item.size ~= nil or item.trailingIcon ~= nil or #row > 1) then
                    return Issue(at .. ".multiline", "multiline items stand alone (no size, no trailing button)", id)
                end
            end
        end
    elseif kind == "sentence" then
        if not styled then return fail("kind", "sentence requires a page style") end
        ok, issue = SchemaReference(owner, "sources", node.lineSource, path .. ".lineSource", id)
        if ok and node.line2Source ~= nil then ok, issue = SchemaReference(owner, "sources", node.line2Source, path .. ".line2Source", id) end
        for _, field in ipairs({ "edit", "remove" }) do
            if ok and node[field] ~= nil then ok, issue = SchemaReference(owner, "actions", node[field], path .. "." .. field, id) end
        end
        if ok and node.selected ~= nil then ok, issue = SchemaReference(owner, "predicates", node.selected, path .. ".selected", id) end
        if not ok then return false, issue end
    elseif kind == "text" or kind == "hint" then
        if (node.text ~= nil) == (node.textSource ~= nil) then return fail("text", "use text or textSource") end
        if node.text ~= nil and type(node.text) ~= "string" then return fail("text", "expected string") end
        if node.textSource ~= nil then
            ok, issue = SchemaReference(owner, "texts", node.textSource, path .. ".textSource", id)
            if not ok then return false, issue end
        end
    elseif kind == "actions" then
        for _, field in ipairs({ "position", "align" }) do
            local value = node[field]
            if value ~= nil and value ~= "start" and value ~= "center" and value ~= "end" then return fail(field, "invalid alignment") end
        end
    elseif kind == "setting" then
        -- 样式页（预设写了 unlabeledFill）的设置行可以不写 label：卡片标题已经说明这一行时不再重复行名。
        -- 没有 label 的行不能带说明、问号、勾选框、图标（这些都挂在行名上）。
        if node.label == nil and styled and styled.unlabeledFill then
            for _, field in ipairs({ "description", "help", "helpSource", "toggle", "icon" }) do
                if node[field] ~= nil then return fail(field, field .. " requires label") end
            end
        elseif not Name(node.label) then return fail("label", "label required") end
        if node.dimLabel ~= nil and node.dimLabel ~= true then return fail("dimLabel", "expected true") end
        if node.description ~= nil and type(node.description) ~= "string" then return fail("description", "expected string") end
        if node.toggle ~= nil and node.icon ~= nil then return fail("icon", "toggle and icon share the leading slot") end
        if node.help ~= nil then
            if not (styled and styled.helpIconSize) then return fail("help", "help requires a page style with helpIconSize") end
            if not Name(node.help) then return fail("help", "expected non-empty help") end
        end
        if node.helpSource ~= nil then
            if node.help ~= nil then return fail("helpSource", "use help or helpSource") end
            if not (styled and styled.helpIconSize) then return fail("helpSource", "helpSource requires a page style with helpIconSize") end
            ok, issue = SchemaReference(owner, "texts", node.helpSource, path .. ".helpSource", id)
            if not ok then return false, issue end
        end
        if node.toggle ~= nil then
            if not Name(node.toggle) then return fail("toggle", "expected a path") end
            ok, issue = SchemaBinding(owner, path .. ".toggle", id)
            if not ok then return false, issue end
        end
        if node.icon ~= nil and not ((type(node.icon) == "string" and _G.ExwindTools.GUIIcons.ids[node.icon])
            or (Number(node.icon) and node.icon % 1 == 0)) then
            return fail("icon", "expected a registered GUIIcons id or a texture file id")
        end
    elseif kind == "columns" or kind == "table" then
        if kind == "table" then
            local usesOp, addsRow = false, false
            if node.rowActions ~= nil then
                ok, issue = SchemaArray(node.rowActions, path .. ".rowActions", id)
                if not ok then return false, issue end
                for i, action in ipairs(node.rowActions) do
                    local at = path .. ".rowActions[" .. i .. "]"
                    ok, issue = SchemaKeys(action, "id text action op enabled presentation", at, id)
                    if not ok then return false, issue end
                    if not Name(action.id) or ids[action.id] then return Issue(at .. ".id", "missing/duplicate node id", id) end
                    ids[action.id] = true
                    if type(action.text) ~= "string" then return Issue(at .. ".text", "text required", id) end
                    if (action.action ~= nil) == (action.op ~= nil) then return Issue(at, "use action or op", id) end
                    if action.op ~= nil then
                        if action.op ~= "remove" and action.op ~= "up" and action.op ~= "down" then
                            return Issue(at .. ".op", "expected remove/up/down", id)
                        end
                        usesOp = true
                    else ok, issue = SchemaReference(owner, "actions", action.action, at .. ".action", id) end
                    if ok and action.enabled ~= nil then ok, issue = SchemaReference(owner, "predicates", action.enabled, at .. ".enabled", id) end
                    if not ok then return false, issue end
                    if action.presentation ~= nil and action.presentation ~= "danger" then return Issue(at .. ".presentation", "expected danger", id) end
                end
            end
            if node.addAction ~= nil then
                local at = path .. ".addAction"
                ok, issue = SchemaKeys(node.addAction, "id text action clickKey op input", at, id)
                if not ok then return false, issue end
                local add = node.addAction
                if not Name(add.id) or ids[add.id] then return Issue(at .. ".id", "missing/duplicate node id", id) end
                ids[add.id] = true
                if type(add.text) ~= "string" then return Issue(at .. ".text", "text required", id) end
                if ((add.action ~= nil and 1 or 0) + (add.clickKey ~= nil and 1 or 0) + (add.op ~= nil and 1 or 0)) ~= 1 then
                    return Issue(at, "use action, clickKey or op", id)
                end
                if add.op ~= nil then
                    if add.op ~= "add" then return Issue(at .. ".op", "expected add", id) end
                    if add.input ~= nil then return Issue(at .. ".input", "op = add does not take input", id) end
                    usesOp, addsRow = true, true
                elseif add.action ~= nil then ok, issue = SchemaReference(owner, "actions", add.action, at .. ".action", id)
                else ok, issue = SchemaBinding(owner, at .. ".clickKey", id) end
                if ok and add.input ~= nil and not (Name(add.input) and (owner == nil
                    or type(rawget(rawget(owner, "controls") or {}, add.input)) == "table")) then
                    ok, issue = Issue(at .. ".input", "missing controls." .. tostring(add.input), id)
                end
                if not ok then return false, issue end
            end
            if node.selected ~= nil then
                ok, issue = SchemaReference(owner, "predicates", node.selected, path .. ".selected", id)
                if not ok then return false, issue end
            end
            if usesOp then
                local only = type(node.children) == "table" and #node.children == 1 and node.children[1]
                if not (type(only) == "table" and only.kind == "repeat" and only.path ~= nil) then
                    return fail("children", "op requires exactly one repeat child with path")
                end
                if addsRow and only.rowDefaults == nil then return fail("addAction", "op = add requires repeat.rowDefaults") end
            end
        end
        ok, issue = SchemaArray(node.columns, path .. ".columns", id)
        if not ok then return false, issue end
        columnCount = issue
        if columnCount == 0 then return fail("columns", "empty columns") end
        for i, column in ipairs(node.columns) do
            local columnPath = path .. ".columns[" .. i .. "]"
            ok, issue = SchemaKeys(column, kind == "table" and "title width weight" or "width weight", columnPath, id)
            if not ok then return false, issue end
            if kind == "table" and type(column.title) ~= "string" then return Issue(columnPath, "table column title required", id) end
            if (column.width and column.weight) or (column.width ~= nil and not Number(column.width))
                or (column.weight ~= nil and not Number(column.weight)) then return Issue(columnPath, "invalid column width/weight", id) end
        end
    elseif kind == "repeat" then
        if depth >= 2 then return fail("template", "at most two nested repeats") end
        if (node.source ~= nil) == (node.path ~= nil) then return fail("source", "use source or path") end
        if node.path ~= nil then
            if not Name(node.path) then return fail("path", "expected a non-empty path") end
            ok, issue = SchemaBinding(owner, path .. ".path", id)
            if ok and node.rowDefaults ~= nil and type(node.rowDefaults) ~= "table" then ok, issue = fail("rowDefaults", "expected a plain table") end
        elseif node.rowDefaults ~= nil then ok, issue = fail("rowDefaults", "rowDefaults requires path")
        else ok, issue = SchemaReference(owner, "sources", node.source, path .. ".source", id) end
        if not ok then return false, issue end
        if type(node.template) ~= "table" then return fail("template", "template required") end
        if top and node.template.kind ~= "card" then return fail("template", "page repeat template must be card") end
        if columnCount and node.template.kind ~= "row" then return fail("template", "column repeat template must be row") end
        return ValidateNode(node.template, owner, ids, depth + 1, location, columnCount, path .. ".template", styled,
            rowScope or node.path ~= nil)
    end
    if kind == "row" and node.separator ~= nil and type(node.separator) ~= "boolean" then return fail("separator", "expected boolean") end
    if node.children ~= nil then
        ok, issue = SchemaArray(node.children, path .. ".children", id)
        if not ok then return false, issue end
        if kind == "row" and columnCount and issue ~= columnCount then return fail("children", "cell count differs from columns") end
        local actions = 0
        for i, child in ipairs(node.children) do
            local childPath = path .. ".children[" .. i .. "]"
            if type(child) ~= "table" then return Issue(childPath, "expected node", id) end
            if (kind == "columns" or kind == "table") and child.kind ~= "row" and child.kind ~= "repeat" then return Issue(childPath, kind .. " accepts row/repeat", id) end
            if kind == "row" and columnCount and child.kind ~= "cell" then return Issue(childPath, "expected cell", id) end
            if child.kind == "actions" then
                actions = actions + 1
                if actions > 1 or i ~= #node.children then return Issue(childPath, "actions must be unique and last", id) end
            end
            -- setting 右侧按横排处理：子节点与 row 内的流式项同规则。
            ok, issue = ValidateNode(child, owner, ids, depth, kind == "setting" and "row" or kind,
                (kind == "columns" or kind == "table" or kind == "row") and columnCount or nil, childPath, styled, rowScope)
            if not ok then return false, issue end
        end
    elseif kind == "card" or kind == "group" or kind == "row" or kind == "cell" or kind == "actions" or kind == "columns"
        or kind == "setting" or kind == "table" then
        return fail("children", "children required")
    end
    return true
end

-- 普通页规则的第二道校验：只看结构与是否写了尺寸，字段合法性已由 ValidateNode 保证。
local function IsStandardAdapter(owner, node)
    if owner == nil then return true end -- 登记时还没有 owner，挂载时再查
    local bucket = rawget(owner, node.kind == "control" and "controls" or "components")
    local adapter = type(bucket) == "table" and rawget(bucket, node.ref)
    return type(adapter) == "table" and rawget(adapter, "_exStandard") == true
end

local function StrictNode(node, owner, parentKind, path, out, styled)
    local kind = node.kind
    local function fail(field, message)
        local _, issue = Issue(path .. (field and "." .. field or ""), message, node.id, "NOT_STANDARD")
        out[#out + 1] = issue
        return true
    end
    local allowed = StrictChildren[parentKind]
    if allowed and not allowed[kind] then
        return fail("kind", "普通页的 " .. parentKind .. " 里不能放 " .. tostring(kind) .. "（只允许标准行、表格、封装控件，或登记过的自定义）")
    end
    for _, field in ipairs(StrictSizeFields) do
        if node[field] ~= nil then fail(field, "普通页不准写尺寸；宽度用 size 档位，其余由 Core 决定"); break end
    end
    if kind == "card" then
        for _, field in ipairs(StrictCardFields) do
            -- 预设写了 cardHelp 的样式页：卡片标题旁可以挂“?”说明（help），其余外观字段照旧不准写。
            local allowedHelp = field == "help" and styled and styled.cardHelp
            if node[field] ~= nil and not allowedHelp then fail(field, "普通页卡片只有一种外观（标题在上）"); break end
        end
        if node.help ~= nil and styled and styled.cardHelp and not Name(node.help) then fail("help", "expected non-empty help") end
    elseif kind == "chips" then
        if not styled then return fail("kind", "标签排（chips）只用在写了 style 的普通页") end
    elseif kind == "group" then
        if not styled then return fail("kind", "块（group）只用在写了 style 的普通页") end
        if node.title ~= "" then return fail("title", "块（group）不写标题，title 写空字串") end
    elseif kind == "control" or kind == "component" then
        if node.ref ~= nil and node.custom == nil and not IsStandardAdapter(owner, node) then
            return fail("ref", "自定义件必须写 custom=<Core 名单键>；标准控件用 CreateSettingsV2Control/Component 建")
        end
        if kind == "control" and node.path ~= nil then
            if node.controlType == "card" then return fail("controlType", "普通页不用大方块勾选；用开关或 toggles") end
            if node.controlType == "checkbox" and parentKind ~= "cell" then return fail("controlType", "勾选框只用在表格里；设置行用开关或 setting.toggle") end
        end
        if kind == "control" and node.ref ~= nil and node.custom == nil and node.controlType == "card" then
            return fail("controlType", "普通页不用大方块勾选；用开关或 toggles")
        end
        if parentKind == "setting" and node.label ~= nil then return fail("label", "设置行右侧控件不写 label") end
    elseif kind == "setting" then
        local controls = 0
        for _, child in ipairs(node.children or {}) do
            -- 单位文字（秒、%）与样式页的图标按钮（上移、下移、删除）不算控件
            if child.kind ~= "text" and not (child.kind == "button" and child.icon ~= nil) then controls = controls + 1 end
        end
        if controls > MaxSettingControls then fail("children", "设置行右侧最多 3 个控件") end
    elseif kind == "repeat" then
        return StrictNode(node.template, owner, parentKind, path .. ".template", out, styled)
    end
    for i, child in ipairs(node.children or {}) do
        StrictNode(child, owner, kind, path .. ".children[" .. i .. "]", out, styled)
    end
    return true
end

-- 普通页违规照样报 Lua 错误（游戏里弹出、测试工具记录），但不打断加载：
-- 一次能看到全部违规，它们就是迁移清单。同一条只报一次。
local ReportedStrict = {}
local function ReportStrict(where, issues)
    for _, issue in ipairs(issues or {}) do
        local message = "SettingsV2 普通页规则: " .. tostring(where) .. " " .. issue.path .. ": " .. issue.message
        if not ReportedStrict[message] then
            ReportedStrict[message] = true
            geterrorhandler()(message)
        end
    end
end

-- 节点树里有没有 advanced 节点（含 repeat 模板）；只在字段校验通过后调用。
local function HasAdvanced(node)
    if node.advanced == true then return true end
    if node.template and HasAdvanced(node.template) then return true end
    for _, child in ipairs(node.children or {}) do
        if HasAdvanced(child) then return true end
    end
    return false
end

local function Validate(declaration, owner)
    local ok, issue = Pure(declaration, "page", {})
    if not ok then return false, issue end
    ok, issue = SchemaKeys(declaration, "version layout cards columns columnGap rowGap freeform style advanced collapse", "page")
    if not ok then return false, issue end
    if declaration.version ~= 2 then return Issue("page.version", "version must be 2") end
    -- style：可选页面样式，只能写 GM.settings.styles 登记的预设名；不写时一切照旧。
    if declaration.style ~= nil then
        if type(declaration.style) ~= "string" or type(GM.settings.styles[declaration.style]) ~= "table" then
            return Issue("page.style", "not a registered GM.settings.styles preset")
        end
    end
    if declaration.freeform ~= nil and not FreeformPages[declaration.freeform] then
        return Issue("page.freeform", "not in the Core freeform list", nil, "NOT_STANDARD")
    end
    if declaration.layout ~= nil and declaration.layout ~= "stack" and declaration.layout ~= "grid" then return Issue("page.layout", "invalid layout") end
    local grid = declaration.layout == "grid"
    if not grid and (declaration.columns or declaration.columnGap or declaration.rowGap) then
        return Issue("page.columns", "columns and gaps require grid layout")
    end
    if grid then
        ok, issue = SchemaArray(declaration.columns, "page.columns")
        if not ok then return false, issue end
        if #declaration.columns == 0 then return Issue("page.columns", "columns required") end
        for i, column in ipairs(declaration.columns) do
            local at = "page.columns[" .. i .. "]"
            ok, issue = SchemaKeys(column, "weight", at)
            if not ok then return false, issue end
            if not Number(column.weight) then return Issue(at .. ".weight", "positive finite weight required") end
        end
        for _, field in ipairs({ "columnGap", "rowGap" }) do
            if declaration[field] ~= nil and (not Finite(declaration[field]) or declaration[field] < 0) then
                return Issue("page." .. field, "expected a non-negative finite number")
            end
        end
    end
    if owner ~= nil and type(owner) ~= "table" then return Issue("owner", "owner must be a table", nil, "INVALID_ARGUMENT") end
    for _, name in ipairs({ "onHeightChanged", "onContentWidthChanged" }) do
        if owner and rawget(owner, name) ~= nil and type(rawget(owner, name)) ~= "function" then return Issue("owner." .. name, "expected callback", nil, "INVALID_ARGUMENT") end
    end
    if owner and rawget(owner, "allowedCustom") ~= nil then
        local allowed = rawget(owner, "allowedCustom")
        local usage = "owner.allowedCustom 要写成 { [自定义件名] = \"为什么标准种类做不到\" }"
        if type(allowed) ~= "table" then return Issue("owner.allowedCustom", usage, nil, "INVALID_ARGUMENT") end
        for name, reason in next, allowed do
            if not Name(name) or not Name(reason) then
                return Issue("owner.allowedCustom." .. tostring(name), usage .. "，名字和理由都不能为空", nil, "INVALID_ARGUMENT")
            end
        end
    end
    ok, issue = SchemaArray(declaration.cards, "page.cards")
    if not ok then return false, issue end
    local ids, occupied = {}, {}
    for i, node in ipairs(declaration.cards) do
        ok, issue = ValidateNode(node, owner, ids, 0, "page", nil, "page.cards[" .. i .. "]",
            declaration.style and GM.settings.styles[declaration.style])
        if not ok then return false, issue end
        local at = "page.cards[" .. i .. "]"
        if grid then
            if node.kind ~= "card" or not node.row or not node.column then
                return Issue(at, "grid requires cards with row and column", node.id)
            end
            local last = node.column + (node.span or 1) - 1
            if last > #declaration.columns then return Issue(at .. ".span", "card exceeds page columns", node.id) end
            occupied[node.row] = occupied[node.row] or {}
            for column = node.column, last do
                if occupied[node.row][column] then return Issue(at, "overlapping cards", node.id) end
                occupied[node.row][column] = true
            end
        elseif node.row or node.column or node.span or node.gapBefore then
            return Issue(at, "row/column/span/gapBefore require grid layout", node.id)
        end
    end
    -- 渐进披露：有 advanced 节点 ⇔ 写了 page.advanced。
    local hasAdvanced = false
    for _, node in ipairs(declaration.cards) do
        if HasAdvanced(node) then hasAdvanced = true; break end
    end
    if hasAdvanced ~= (declaration.advanced ~= nil) then
        return Issue("page.advanced", "advanced nodes and page.advanced { expanded, toggle } go together")
    end
    if hasAdvanced then
        if grid then return Issue("page.advanced", "advanced nodes require stack layout") end
        ok, issue = SchemaKeys(declaration.advanced, "expanded toggle visible", "page.advanced")
        if ok then ok, issue = SchemaReference(owner, "predicates", declaration.advanced.expanded, "page.advanced.expanded") end
        if ok then ok, issue = SchemaReference(owner, "actions", declaration.advanced.toggle, "page.advanced.toggle") end
        if ok and declaration.advanced.visible ~= nil then
            ok, issue = SchemaReference(owner, "predicates", declaration.advanced.visible, "page.advanced.visible")
        end
        if not ok then return false, issue end
    end
    if declaration.collapse ~= nil then
        ok, issue = SchemaKeys(declaration.collapse, "state toggle", "page.collapse")
        if ok then ok, issue = SchemaReference(owner, "predicates", declaration.collapse.state, "page.collapse.state") end
        if ok then ok, issue = SchemaReference(owner, "actions", declaration.collapse.toggle, "page.collapse.toggle") end
        if not ok then return false, issue end
    end
    local strict = {}
    if declaration.freeform == nil then
        if declaration.columnGap ~= nil or declaration.rowGap ~= nil then
            local _, gapIssue = Issue("page.columnGap", "普通页不准写尺寸；列间距由 Core 决定", nil, "NOT_STANDARD")
            strict[#strict + 1] = gapIssue
        end
        for i, node in ipairs(declaration.cards) do
            -- 第六个参数：样式页传预设表（普通页规则按预设放开个别项，如 cardHelp），非样式页传 false。
            StrictNode(node, owner, "page", "page.cards[" .. i .. "]", strict,
                declaration.style ~= nil and GM.settings.styles[declaration.style])
        end
    end
    return true, nil, strict
end

function UI:ValidateSettingsDeclarationV2(declaration, owner)
    return Validate(declaration, owner)
end

function UI:RegisterSettingsPageV2(pageId, declaration)
    Check(Name(pageId) and Pages[pageId] == nil, "missing/duplicate page id")
    local ok, issue, strict = Validate(declaration)
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    ReportStrict(pageId, strict)
    Pages[pageId] = DeclarationCopy(declaration, {})
end

-- 表格行：直接挂在 table 下，或挂在 table 下的 repeat 里。
local function TableOf(node)
    local parent = node.parent
    if parent and parent.spec.kind == "repeat" then parent = parent.parent end
    return parent and parent.spec.kind == "table" and parent or nil
end

local function Acquire(parent)
    local host = Factory:AcquireCompositeHost(POOL, parent)
    UI:ClearControlSurface(host)
    if host._v2Label then host._v2Label:Hide() end
    if host._v2SettingsSeparator then host._v2SettingsSeparator:Hide() end
    if host._v2RowHelp then host._v2RowHelp:Hide(); host._v2RowHelp._v2Text = nil; host._v2RowHelp._v2TextFn = nil end
    if host._v2More then host._v2More:Hide(); host._v2More._v2OnClick = nil end
    host:SetScript("OnMouseWheel", nil)
    host:EnableMouseWheel(false)
    host:SetSize(1, 1)
    host:Show()
    return host
end

-- Settings GUI lands on whole physical pixels (UI scale is usually fractional);
-- otherwise nine-slice surfaces such as switch knobs show their seams.
local function Place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    PixelUtil.SetPoint(frame, "TOPLEFT", parent, "TOPLEFT", x, -y, 0, 0)
    PixelUtil.SetSize(frame, math.max(1, width), math.max(1, height), 1, 1)
    -- 页面显示前就改过尺寸的控件，游戏里不会补发 OnSizeChanged，外观底板会停在创建时的宽度；
    -- 摆放后按新尺寸重排一次。
    for _, skin in pairs(frame._exModernSurfaces or {}) do
        if skin.active == true and skin.Layout then skin.Layout() end
    end
end

local function Records(node)
    local records
    if node.spec.path then records = Session._rows.Records(node)
    else records = node.session.owner.sources[node.spec.source](node.scope) end
    Array(records, node.spec.id .. " source")
    local seen = {}
    for _, record in ipairs(records) do
        Check(type(record) == "table" and not seen[record], node.spec.id .. ": records must be unique original tables")
        seen[record] = true
    end
    return records
end

local function Current(node)
    if not node.alive or not node.session.alive or node.session.cleanupFailed then return false end
    local scope = node.scope
    while scope do
        local repeatNode = scope._repeatNode
        if not repeatNode.alive then return false end
        local records = Records(repeatNode)
        if records[scope.index] ~= scope.item then return false end
        scope = scope.parent
    end
    return true
end

local function Interactive(node)
    if not Current(node) or not node.session.root:IsVisible() then return false end
    while node do
        if node.visible == false or node.enabled == false then return false end
        if node.spec.kind == "card" and node.frame._exSettingsCardCollapsed then return false end
        node = node.parent
    end
    return true
end

local function Context(node)
    local generation = node.generation
    local function valid() return node.generation == generation and Current(node) end
    -- _exStyle：页面样式预设（没写 style 时为 nil），标准控件自建设置行时一并传给行。
    -- _exOwner：页面 owner，标准控件的内嵌按钮按引用名找 actions。
    local ctx = { scope = node.scope, _exStyle = node.session.style, _exOwner = node.session.owner }
    function ctx:IsCurrent() return valid() end
    function ctx:Guard(callback)
        Check(type(callback) == "function", "Guard expects a callback")
        return function(...)
            if valid() and Interactive(node) then return callback(...) end
        end
    end
    -- [决定] 测量世代：异步高度必须带上“测量它时使用的宽度”（measure 收到的 width）。
    -- 宽度与当前布局宽不一致（旧宽度的迟到报告）一律拒绝并返回 false；同步在 measure 内
    -- 返回高度的 owner 不需要调用。省略 width 表示 owner 保证它按当前宽度测量。
    function ctx:ReportHeight(height, requestedWidth)
        if not valid() then return false end
        Check(type(height) == "number" and height >= 0 and height < math.huge, "invalid reported height")
        Check(requestedWidth == nil or (type(requestedWidth) == "number" and requestedWidth == requestedWidth),
            "invalid reported width")
        if requestedWidth ~= nil and (node.width == nil or math.abs(node.width - requestedWidth) > 0.01) then
            return false
        end
        if node.reportedHeight ~= height then
            node.reportedHeight = height
            node.session:Invalidate()
        end
        return true
    end
    function ctx:Invalidate()
        if not valid() then return false end
        node.reportedHeight = nil
        node.session:Invalidate()
        return true
    end
    -- After a committed write: re-read every bound value and re-evaluate predicates.
    function ctx:RefreshPage()
        if not valid() then return false end
        node.session:Refresh()
        return true
    end
    -- 当前分配宽度（最近一次 measure 收到的 width）；尚未布局时为 nil。
    function ctx:GetRequestedWidth() return valid() and node.width or nil end
    return ctx
end

local function Text(node)
    local text = node.spec.text
    if node.spec.textSource then text = node.session.owner.texts[node.spec.textSource](node.scope) end
    Check(type(text) == "string", node.spec.id .. ": text source must return string")
    node.label:SetText(text)
end

-- Defaults operate on an existing EXUI control, never a value/configuration.
local ControlDefaults = {}
function ControlDefaults.update() end
function ControlDefaults.measure(widget, context, width)
    widget:SetWidth(width)
    return widget:GetHeight()
end
function ControlDefaults.layout(widget, context, width, height)
    Place(widget, widget:GetParent(), 0, 0, width, height)
end
function ControlDefaults.setEnabled(widget, context, enabled)
    local target = widget.checkbox or widget.editBox or widget
    if widget.SetDisabled then widget:SetDisabled(not enabled)
    elseif target.SetEnabled then target:SetEnabled(enabled)
    else Check(enabled, "control needs an owner setEnabled implementation") end
end
function ControlDefaults.setVisible(widget, context, visible)
    if not visible then
        if widget.CloseMenu then widget:CloseMenu() end
        local editBox = widget.editBox or widget
        if editBox.ClearFocus then editBox:ClearFocus() end
    end
    widget:SetShown(visible)
end

-- “?” 说明钮：卡片标题旁（help）与样式页设置行标签后（setting.help）共用这一种画法，悬停用 GameTooltip 显示 _v2Text。
local function HelpGlyph(parent, size)
    local help = CreateFrame("Button", nil, parent)
    help:SetSize(size, size)
    help.glyph = UI:CreateVisualFontString(help, _G.EXFONTFRAME, "GameFontHighlight")
    help.glyph:SetPoint("CENTER", 0, 1)
    help.glyph:SetText("?")
    UI.ControlAppearance.ApplyTextRole(help.glyph, "title", UI.ControlAppearance.colors.muted)
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- _v2TextFn（动态说明）给出时悬停那一刻才取文字。
        local text = self._v2TextFn and self._v2TextFn() or self._v2Text
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return help
end

-- Card accessories live on the pooled card frame and are created once: a "?" beside the title
-- that shows `help` as a tooltip, and a hairline under a folded card's title.
local function CardAccessories(card)
    if card._v2Help then return end
    local header = card._exSettingsCardHeader
    local help = HelpGlyph(header, 22)
    card._v2Help = help
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(UI.ControlAppearance.DungeonAura.line))
    card._v2CollapsedDivider = divider
end

-- 页面样式（session.style）的卡片附件，只在样式页第一次用到这张池化卡片时建：
-- 标题条底板（卡片的子 Frame，层级压在表头下面，表头悬停重画不会擦掉它）和右侧灰字。
local function StyleAccessories(card)
    if card._v2StyleBar then return end
    local bar = CreateFrame("Frame", nil, card)
    bar:EnableMouse(false)
    bar:Hide()
    card._v2StyleBar = bar
    local note = UI:CreateVisualFontString(card._exSettingsCardHeader, _G.EXFONTFRAME, "GameFontHighlightSmall")
    note:SetJustifyH("RIGHT")
    note:Hide()
    card._v2StyleNote = note
    -- 标题条最右侧的小按钮（addButton）：文字字形按钮，与 ? 同一做法；点击回调每次借出时重绑到 _v2OnClick。
    -- 行外的圆角带边卡（预设 cardFill）：卡片的子 Frame，层级在正文下面，盖住正文区。
    local surface = CreateFrame("Frame", nil, card)
    surface:EnableMouse(false)
    surface:Hide()
    card._v2StyleCard = surface
    -- 折叠图标（预设 foldGlyph = "chevron" V 形细线箭头 / "plus" 加减号图标）：画在折叠钮上，代替“+ / −”字形。
    local chevron = card._exSettingsCardToggle:CreateTexture(nil, "ARTWORK")
    chevron:SetPoint("CENTER")
    chevron:Hide()
    card._v2Chevron = chevron
    -- 步骤条（card.step）：左栏的圆圈（外圈 + 内芯两个圆，序号写在圆圈正中）和连到下一步的竖线。
    local stepDot = CreateFrame("Frame", nil, card)
    stepDot:EnableMouse(false)
    stepDot:Hide()
    local stepCore = CreateFrame("Frame", nil, stepDot)
    stepCore:EnableMouse(false)
    -- 外圈、内芯都用圆形材质着色（圆角表面在小尺寸下画不成正圆）。
    local circle = "Interface\\AddOns\\ExwindCore\\Textures\\Materials\\ExwindTools\\PlayerPosition\\Circle.png"
    local stepRing = stepDot:CreateTexture(nil, "BACKGROUND")
    stepRing:SetTexture(circle)
    stepRing:SetAllPoints(stepDot)
    local stepFill = stepCore:CreateTexture(nil, "BACKGROUND")
    stepFill:SetTexture(circle)
    stepFill:SetAllPoints(stepCore)
    local stepFace = CreateFrame("Frame", nil, stepDot)
    stepFace:EnableMouse(false)
    stepFace:SetAllPoints(stepDot)
    local stepNumber = UI:CreateVisualFontString(stepFace, _G.EXFONTFRAME, "GameFontHighlightSmall")
    stepNumber:SetJustifyH("CENTER")
    stepNumber:SetPoint("CENTER", stepFace, "CENTER", 0, 0)
    card._v2StepFace = stepFace
    local stepLine = card:CreateTexture(nil, "ARTWORK")
    stepLine:Hide()
    card._v2Step = { number = stepNumber, dot = stepDot, core = stepCore, line = stepLine, ring = stepRing, fill = stepFill }
    local add = CreateFrame("Button", nil, card._exSettingsCardHeader)
    add:RegisterForClicks("LeftButtonUp")
    add.glyph = UI:CreateVisualFontString(add, _G.EXFONTFRAME, "GameFontHighlight")
    add.glyph:SetPoint("CENTER", 0, 0)
    UI.ControlAppearance.ApplyTextRole(add.glyph, "title", UI.ControlAppearance.colors.muted)
    add:SetScript("OnEnter", function(self) self.glyph:SetTextColor(unpack(UI.ControlAppearance.colors.text)) end)
    add:SetScript("OnLeave", function(self) self.glyph:SetTextColor(unpack(UI.ControlAppearance.colors.muted)) end)
    add:SetScript("OnClick", function(self, mouseButton) if self._v2OnClick then self._v2OnClick(self, mouseButton) end end)
    add:Hide()
    card._v2StyleAdd = add
end

local STYLE_HELP_GAP = 4                -- 问号与标签文字的间距（与卡片标题旁的 ? 相同）

local function ControlAdapter(provider)
    return setmetatable({}, { __index=function(_, method) return rawget(provider, method) or ControlDefaults[method] end })
end

-- =========================================================
-- Standard binding layer
-- =========================================================
-- A binding addresses one value under a module DB root by a dot path; numeric
-- segments are numeric keys. Writes create missing intermediate tables, skip
-- equal values and notify through the single ValueController entry.
local Binding = {}
Binding.__index = Binding

function Binding:Read()
    local value = self.root
    for _, key in ipairs(self.segments) do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

function Binding:Parent(create)
    local parent = self.root
    for i = 1, #self.segments - 1 do
        local key = self.segments[i]
        local child = parent[key]
        if child == nil and create then
            child = {}
            parent[key] = child
        end
        if type(child) ~= "table" then
            Check(child == nil, self.path .. ": segment " .. tostring(key) .. " is not a table")
            return nil
        end
        parent = child
    end
    return parent
end

function Binding:Key()
    return self.segments[#self.segments]
end

function Binding:Notify(phase)
    UI:NotifyModuleValueChanged(self.moduleKey, self.path, phase == "live" and "changing" or "committed")
end

-- phase: "live" (dragging), "commit", or "silent" (no notification).
function Binding:Write(value, phase)
    local parent, key = self:Parent(true), self:Key()
    if parent[key] == value then return false end
    parent[key] = value
    if phase ~= "silent" then self:Notify(phase) end
    return true
end

local function CreateBinding(moduleKey, root, path)
    Check(Name(moduleKey), "binding requires moduleKey")
    Check(type(root) == "table", "binding requires a root table")
    Check(Name(path), "binding requires a path")
    local segments = {}
    for part in path:gmatch("[^%.]+") do segments[#segments + 1] = tonumber(part) or part end
    Check(#segments > 0, "binding requires a path")
    return setmetatable({ moduleKey=moduleKey, root=root, path=path, segments=segments,
        parentPath=path:match("^(.*)%.[^%.]+$") }, Binding)
end

-- 按行绑定的数组（repeat.path，字段说明见文件头 Fields）。
do
    local Rows = {}
    Session._rows = Rows

    local function Relative(path) return type(path) == "string" and path:sub(1, 1) == "@" end

    -- 校验用：返回出错的字段名和说明；没问题返回 nil。
    function Rows.PathIssue(node, rowScope)
        local checks = { { "path", node.path }, { "wrapPath", node.wrapPath } }
        if node.kind == "setting" then checks[#checks + 1] = { "toggle", node.toggle } end
        if node.controlType == "toggles" and type(node.items) == "table" then
            for i, item in ipairs(node.items) do
                if type(item) == "table" then checks[#checks + 1] = { "items[" .. i .. "].path", item.path } end
            end
        end
        if node.controlType == "preset" and type(node.options) == "table" then
            for i, option in ipairs(node.options) do
                for key in pairs(type(option) == "table" and type(option.values) == "table" and option.values or {}) do
                    checks[#checks + 1] = { "options[" .. i .. "].values", key }
                end
            end
        end
        for _, entry in ipairs(checks) do
            local value = entry[2]
            if Relative(value) then
                if not rowScope then return entry[1], "\"@.\" paths only inside a repeat with path" end
                if not (value:match("^@%.[^@]+$") and not value:find("..", 1, true) and value:sub(-1) ~= ".") then
                    return entry[1], "expected \"@.field\""
                end
            end
        end
    end

    local function RowScope(scope)
        while scope and not scope._arrayPath do scope = scope.parent end
        return scope
    end

    -- "@.字段" → "数组路径.行号.字段"；其他路径原样返回。
    function Rows.Path(scope, path)
        if not Relative(path) then return path end
        local row = RowScope(scope)
        Check(row ~= nil, path .. ": row path outside a repeat with path")
        return row._arrayPath .. "." .. row.index .. path:sub(2)
    end

    local function ArrayBinding(session, path)
        local binding = session.owner.binding
        return CreateBinding(binding.moduleKey, binding.config, path)
    end

    function Rows.Records(node)
        return ArrayBinding(node.session, Rows.Path(node.scope, node.spec.path)):Read() or {}
    end

    -- 表格行操作（Core 展开时给按钮标 _op）：复制数组、改动后整份写回，一次 commit。
    function Rows.Run(node, op)
        local path, index
        if op == "add" then
            path = Rows.Path(node.scope, node.spec._arrayPath)
        else
            local row = RowScope(node.scope)
            path, index = row._arrayPath, row.index
        end
        local binding = ArrayBinding(node.session, path)
        local rows = {}
        for i, record in ipairs(binding:Read() or {}) do rows[i] = record end
        if op == "add" then
            rows[#rows + 1] = DeclarationCopy(node.spec._rowDefaults, {})
        elseif op == "remove" then
            if not rows[index] then return end
            table.remove(rows, index)
        else
            local other = op == "up" and index - 1 or index + 1
            if not (rows[index] and rows[other]) then return end
            rows[index], rows[other] = rows[other], rows[index]
        end
        binding:Write(rows, "commit")
        node.context:RefreshPage()
    end

    -- 上移在首行、下移在末行不可用；其他节点不受影响。
    function Rows.Enabled(node)
        local op = node.spec._op
        if op ~= "up" and op ~= "down" then return true end
        local row = RowScope(node.scope)
        if op == "up" then return row.index > 1 end
        return row.index < #Records(row._repeatNode)
    end
end

local function ReleaseBoundWidget(widget)
    UI:RestoreSettingsListControl(widget)
    if widget._exGridOwnedControls then
        for index = #widget._exGridOwnedControls, 1, -1 do
            Factory:ReleaseGridWidget(widget._exGridOwnedControls[index])
            widget._exGridOwnedControls[index] = nil
        end
        widget._exGridOwnedControls = nil
    end
    if widget._isCompositeHost then
        Factory:ReleaseCompositeHost(widget)
    elseif widget._fromPool then
        Factory:Release(widget._fromPool, widget)
    else
        widget:Hide()
        widget:SetParent(nil)
    end
end

-- optionsSource names a global provider (resolved at every mount). A table result
-- is used as-is; a string result keeps the "value:display,..." inline form.
local function SelectItems(spec)
    if spec.options then
        local items = {}
        for i, option in ipairs(spec.options) do items[i] = { option.label, option.value } end
        return items
    end
    local provider = _G
    for part in spec.optionsSource:gmatch("[^%.]+") do
        provider = type(provider) == "table" and provider[part] or nil
    end
    Check(type(provider) == "function", "optionsSource is not a function: " .. spec.optionsSource)
    local data = provider()
    if type(data) == "table" then return data end
    local items = {}
    for entry in tostring(data or ""):gmatch("([^,]+)") do
        local value, display = entry:match("^([^:]+):(.+)$")
        items[#items + 1] = (value and not spec.multiple) and { display, value } or entry
    end
    return items
end

local function IsOrdinaryRowControl(widget)
    local kind = widget._gridType
    if kind == "GridInput" then return widget.IsMultiLine and not widget:IsMultiLine() end
    return kind == "GridDropdown" or kind == "GridLSMDropdown" or kind == "GridMultiselect"
        or kind == "GridColorButton" or kind == "GridSlider"
end

-- ChoiceGroup（choice/tristate/segment/toggles）按选项文字算出的自然宽。
local function ChoiceNaturalWidth(widget)
    if widget.NaturalWidth then return widget:NaturalWidth() end
    if not (widget.buttons and widget.minItemWidth) then return nil end
    -- The existing ChoiceGroup uses these label/icon insets and item gap.
    local width, rowWidth, count, maximum = 0, 0, 0, 0
    for _, button in ipairs(widget.buttons) do
        local itemWidth = math.max(widget.minItemWidth,
            button.label:GetUnboundedStringWidth() + (button._choiceItem.icon and GM.space.choiceIconItemPadX or GM.space.choiceItemPadX))
        maximum = math.max(maximum, itemWidth)
        if count > 0 then rowWidth = rowWidth + widget.gap end
        rowWidth, count = rowWidth + itemWidth, count + 1
        if widget.columns and count == widget.columns then
            width, rowWidth, count = math.max(width, rowWidth), 0, 0
        end
    end
    width = math.max(width, rowWidth)
    if widget.sizing ~= "content" then
        count = math.min(#widget.buttons, widget.columns or #widget.buttons)
        width = count * maximum + math.max(0, count - 1) * widget.gap
    end
    -- 轨道两侧内距，与 ExwindChoiceGroup 的 Layout 同一组数。
    local trackPad = (widget.choiceStyle == "segmented" and widget.mode == "single")
        and (widget.darkTrack and GM.space.segmentedDarkTrackPad or GM.space.segmentedTrackPad)
        or ((widget.choiceStyle == "segmented" or widget.choiceStyle == "connected") and GM.space.connectedTrackPad or 0)
    return math.max(1, width + trackPad * 2)
end

-- 样式页的单行控件高（预设 controlHeight）；没写样式或预设没写时取 GM.size.controlHeight。
local function StyledControlHeight(style)
    return style and style.controlHeight or GM.size.controlHeight
end

-- 样式页图标按钮（button.icon）的边长：预设 iconButtonSize，没写时取控件高。
local function IconButtonSize(style)
    return style and style.iconButtonSize or StyledControlHeight(style)
end

-- 控件宽度档位（size）：页面只能选档位，像素在 GM。
-- style（可选页面样式预设）：没写 size 的输入框、下拉用预设 controlWidth，size="short" 用预设 shortWidth；
-- 分段只有预设写了 segmentEqualWidth 才用 controlWidth（每段平分整列宽）。
local function SizeWidth(spec, style)
    -- 数字框没写 size 时按 short 档。
    if spec.controlType == "number" and not spec.size then
        return style and style.shortWidth or GM.settings.controlShortWidth
    end
    if style then
        if spec.size == "short" and style.shortWidth then return style.shortWidth end
        if not spec.size and style.controlWidth and (spec.controlType == "input" or spec.controlType == "select" or spec.controlType == "preset"
            or (spec.controlType == "segment" and style.segmentEqualWidth)) then
            return style.controlWidth
        end
    end
    if spec.size == "short" then return GM.settings.controlShortWidth end
    if spec.size == "wide" then return GM.settings.controlWideWidth end
end

-- 预设写了 sliderSelectWidth：没写 size 的滑杆整组（轨道 + 数字框）宽同本页没写 size 的下拉
-- （预设 controlWidth，没写时是下拉自身的默认宽），右缘对齐。没写这个预设键时返回 nil，宽度照原来算。
-- 预设写了 sliderFill：没写 size 的滑杆占满所在设置行标签右边的全部宽（带 label 的行文字列按标签字宽；
-- 设置行里不带 label 的滑杆在控件区里分走剩下的宽）。
local function SliderFills(spec, style)
    return style ~= nil and style.sliderFill == true and spec.controlType == "slider" and not spec.size
end

local function SteppedSliderWidth(spec, style)
    if not (style and style.sliderSelectWidth and spec.controlType == "slider") or spec.size then return nil end
    return style.controlWidth or GM.size.controlDefaultWidth
end

-- 输入框 / 数字框的装饰：前缀字母画在框外左边（控件分到的宽先让出 InputLeadReserve，框只放数字），
-- 前缀图标画在框内左侧，右侧内嵌图标按钮。装饰框盖在输入框上面但不接鼠标（只有内嵌按钮接），
-- 框内的装饰让出文字左右的宽；尺寸取 GM.settings.parts。
local DECOR_POOL = "EXUI.SettingsV2.InputDecor"
Factory:InitCompositePool(DECOR_POOL)

local function InputLeadReserve(spec, style)
    if spec.prefix == nil then return 0 end
    return Part(style, "prefixWidth") + Part(style, "prefixGap")
end

local function DecorateInput(host, widget, spec, context, onTrailing)
    local style = context._exStyle
    local editBox = widget.editBox or widget
    local decor, isNew = Factory:AcquireCompositeHost(DECOR_POOL, host)
    if isNew then
        decor.prefix = UI:CreateVisualFontString(decor, _G.EXFONTFRAME, "GameFontHighlightSmall")
        decor.prefix:SetJustifyH("RIGHT")
        decor.prefixIcon = decor:CreateTexture(nil, "OVERLAY")
    end
    decor:EnableMouse(false)
    decor:ClearAllPoints()
    decor:SetAllPoints(widget)
    decor:SetFrameLevel(widget:GetFrameLevel() + 3)
    decor:Show()
    local left, right = 0, 0
    local prefixWidth, inset = Part(style, "prefixWidth"), Part(style, "prefixInset")
    decor.prefix:SetShown(spec.prefix ~= nil)
    decor.prefixIcon:SetShown(spec.prefixIcon ~= nil)
    if spec.prefix then
        UI.ControlAppearance.Font(decor.prefix, Part(style, "prefixFont"), UI.ControlAppearance.colors.muted, "", "GameFontHighlightSmall")
        decor.prefix:SetText(spec.prefix)
        decor.prefix:ClearAllPoints()
        decor.prefix:SetPoint("RIGHT", decor, "LEFT", -Part(style, "prefixGap"), 0)
        decor.prefix:SetWidth(prefixWidth)
    elseif spec.prefixIcon then
        local size = Part(style, "prefixIconSize")
        decor.prefixIcon:SetTexture(UI:GetIcon(spec.prefixIcon))
        decor.prefixIcon:SetVertexColor(unpack(UI.ControlAppearance.colors.muted))
        decor.prefixIcon:SetSize(size, size)
        decor.prefixIcon:ClearAllPoints()
        decor.prefixIcon:SetPoint("CENTER", decor, "LEFT", inset + prefixWidth / 2, 0)
        left = inset + prefixWidth
    end
    if spec.trailingIcon then
        local size = Part(style, "inlineButtonSize")
        decor.trailing = UI:CreateIconButton(decor, size, size, { icon = spec.trailingIcon, appearance = "ghost",
            iconSize = Part(style, "inlineButtonIconSize"),
            onClick = context:Guard(function(_, mouseButton) onTrailing(mouseButton) end) })
        decor.trailing:ClearAllPoints()
        decor.trailing:SetPoint("RIGHT", decor, "RIGHT", -Part(style, "inlineButtonInset"), 0)
        decor.trailing:SetFrameLevel(decor:GetFrameLevel() + 1)
        decor.trailing:Show()
        right = size + Part(style, "inlineButtonInset")
    end
    -- 数字框右侧带步进（stepper = "right"）时，步进列的宽也算进右侧让出的宽（同 CreateNumberInput）。
    local stepped = spec.stepper ~= nil and editBox._exNumberInput ~= nil
    if stepped then right = right + GM.size.numberStepperWidth end
    -- 记在输入框上，外观重画时一并让出；现在先按当前内距加上（数字在让出后的空处居中）。
    editBox._exInsetLeft, editBox._exInsetRight = left, right
    local l, r, t, b = editBox:GetTextInsets()
    if stepped then
        editBox:SetTextInsets(GM.space.inputTextPadX + left, GM.space.inputTextPadX + right, t, b)
    else
        editBox:SetTextInsets(l + left, r + right, t, b)
    end
    return decor
end

local function ReleaseInputDecor(decor, widget)
    local editBox = widget.editBox or widget
    editBox._exInsetLeft, editBox._exInsetRight = nil, nil
    if decor.trailing then decor.trailing:Release(); decor.trailing = nil end
    decor.prefix:SetText("")
    decor.prefixIcon:SetTexture(nil)
    Factory:ReleaseCompositeHost(decor)
end

-- 方向选择与每行个数：存档里的值不合法时按“无选择”显示。
local FlowDirections = { RIGHT = true, LEFT = true, UP = true, DOWN = true }
local function FlowValue(value) return FlowDirections[value] and value or nil end
local function PerLineValue(value)
    return type(value) == "number" and value >= 1 and value % 1 == 0 and value or nil
end

-- 预设选择：第一项 values 全部与当前存档相等的序号；没有时 nil。
local function PresetMatch(spec, bindings)
    for i, option in ipairs(spec.options) do
        local match = true
        for fieldPath, fieldValue in pairs(option.values) do
            if bindings[fieldPath]:Read() ~= fieldValue then match = false; break end
        end
        if match then return i end
    end
    return nil
end

-- bindingFor(context) returns the binding of one mounted control.  A labelled
-- switch/input/select/slider/color is presented as a settings row: label and
-- description on the left, the control on the right, a divider between rows.
-- 图标值写进材质：GUIIcons ID 换成图标路径，其余（材质文件 ID、路径）原样。
local function SetIconTexture(texture, icon)
    if type(icon) == "string" and _G.ExwindTools.GUIIcons.ids[icon] then texture:SetTexture(UI:GetIcon(icon))
    else texture:SetTexture(icon) end
end

-- 卡片勾选框（controlType="card"）的选中画法，给格子类卡片共用：右上角主色斜角（37×37 白块转 45°、
-- 中心锚在右上角，靠只裁自己子对象的一层裁掉卡外那半）+ 压在上面的白色小勾。颜色 checkCardCorner / checkCardCornerCheck。
local CORNER_CHECK_GLYPH = "Interface\\AddOns\\ExwindCore\\Textures\\GUI\\GlyphCheck.tga"
local function CornerCheck(card)
    local mark = card._v2CornerCheck
    if not mark then
        mark = { clip = CreateFrame("Frame", nil, card) }
        mark.clip:EnableMouse(false)
        mark.clip:SetAllPoints(card)
        mark.clip:SetClipsChildren(true)
        mark.corner = mark.clip:CreateTexture(nil, "ARTWORK", nil, 1)
        mark.corner:SetTexture("Interface\\Buttons\\WHITE8X8")
        mark.corner:SetSize(37, 37)
        mark.corner:SetPoint("CENTER", card, "TOPRIGHT", 0, 0)
        mark.corner:SetRotation(math.pi / 4)
        mark.check = mark.clip:CreateTexture(nil, "OVERLAY")
        mark.check:SetTexture(CORNER_CHECK_GLYPH, "CLAMP", "CLAMP", "LINEAR")
        mark.check:SetSize(11, 11)
        mark.check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
        card._v2CornerCheck = mark
    end
    return mark
end
local function PaintCornerCheck(card, selected, enabled)
    local mark = CornerCheck(card)
    local GC = _G.ExwindTools.GUIColors
    mark.clip:SetFrameLevel(card:GetFrameLevel() + 4) -- 压在预览区、图标之上（不接鼠标）
    mark.corner:SetVertexColor(unpack(enabled and GC.checkCardCorner or GC.textDisabled))
    mark.check:SetVertexColor(unpack(enabled and GC.checkCardCornerCheck or GC.textDisabled))
    mark.clip:SetShown(selected)
end
-- 卡片勾选框的底和边（格子类卡片共用，方格卡、发光预设格都用它）：选中换选中底和主色边、右上角主色斜角 + 白勾，悬停边变亮。
function UI:PaintCheckCardSurface(card, selected, hover, enabled, radius)
    local GC = _G.ExwindTools.GUIColors
    UI:SetControlSurface(card, radius, not enabled and GC.disabledFill or (selected and GC.checkCardSelected or GC.checkCard),
        not enabled and GC.disabledBorder or (selected and GC.checkCardSelectedBorder
            or (hover and GC.checkCardHoverBorder or GC.checkCardBorder)))
    PaintCornerCheck(card, selected, enabled)
end

-- 横排选择卡（optionlist 写了 columns）：每张 = 图标 + 名字 + 描述（换行），选中描主色边、换选中底。
-- 预设 optionCardCells：画成只有名字的格子（居中、高 optionCellHeight，描述放进悬停提示），选中照卡片勾选框画法。
-- 宿主提供 SetValue / SetDisabled，OnSizeChanged 时按宽排好并设好自己的高（与竖排单选卡片列表同一套用法）。
local CreateOptionCards
do
local OPTION_CARDS_POOL = "EXUI.SettingsV2.OptionCards"
Factory:InitCompositePool(OPTION_CARDS_POOL)

local function PaintOptionCard(card)
    local host = card._v2Host
    if not host then return end
    local selected = host._v2Value == card._v2Value
    local hover = not host._v2Disabled and card:IsMouseOver()
    if host._v2Cells then
        UI:PaintCheckCardSurface(card, selected, hover, not host._v2Disabled, GM.radius.popup)
        card.name:SetTextColor(unpack(host._v2Disabled and _G.ExwindTools.GUIColors.textDisabled or UI.ControlAppearance.colors.text))
        return
    end
    if card._v2CornerCheck then card._v2CornerCheck.clip:Hide() end
    -- 颜色照标准页的单选卡片（GUIStates.option），和竖排 optionlist 同一套。
    local state = _G.ExwindTools.GUIStates.option[host._v2Disabled and "disabled"
        or (selected and "selected" or (hover and "hover" or "normal"))]
    UI:SetControlSurface(card, GM.radius.card, state.fill, state.border)
    if type(card._v2Icon) == "string" then card.icon:SetVertexColor(unpack(state.text)) end
    card.name:SetTextColor(unpack(state.text))
    -- 选中卡是主色底，灰描述字看不清：选中时描述用选中字色，其余照旧灰字。
    local GC = _G.ExwindTools.GUIColors
    card.desc:SetTextColor(unpack(selected and not host._v2Disabled and state.text or GC.textDim))
end

-- 量一段字不换行时的宽和单行高：宽度放到很大再量，量完由调用方重设宽度。
local OPTION_CARD_MEASURE_WIDTH = 100000
local function SingleLine(region)
    region:SetWidth(OPTION_CARD_MEASURE_WIDTH)
    region:SetHeight(0)
    return math.ceil(region:GetStringWidth()), math.max(1, region:GetStringHeight())
end

-- 预设 optionCardFit：按卡内宽检查每张卡放不放得下，放不下就少一列（3→2→1）。
-- 放得下 = 名字（连图标）不换行放进卡内宽；描述最多 optionCardDescLines 行，且换行时各行均分、末行不剩一个字。
-- 描述均分后的宽记在 card._v2DescWidth，排版时直接用。
local function OptionCardsFit(host, cardWidth, style)
    local padX = Part(style, "optionCardPadX")
    local iconSize, iconGap = Part(style, "optionCardIconSize"), Part(style, "optionCardIconGap")
    local maxLines = style.optionCardDescLines or 2
    local room = math.max(1, cardWidth - padX * 2)
    local fits = true
    for _, card in ipairs(host._v2Cards) do
        if card:IsShown() then
            local nameWidth = math.ceil(card.name:GetUnboundedStringWidth())
            if (card._v2Icon and (iconSize + iconGap) or 0) + nameWidth > room then fits = false end
            local desc = card.desc
            card._v2DescWidth = room
            if (desc:GetText() or "") ~= "" then
                local full, lineHeight = SingleLine(desc)
                local fontSize = select(2, desc:GetFont()) or 0
                if full > room then
                    -- 行数按整宽换行量；再按行数均分宽度（多留一个字宽），行数不变才用均分宽，末行就不会只剩一两个字。
                    desc:SetWidth(room)
                    desc:SetHeight(0)
                    local lines = math.max(2, math.floor(desc:GetStringHeight() / lineHeight + 0.5))
                    if lines > maxLines then fits = false end
                    local balanced = math.min(room, math.ceil(full / lines) + fontSize)
                    desc:SetWidth(balanced)
                    desc:SetHeight(0)
                    if math.floor(desc:GetStringHeight() / lineHeight + 0.5) == lines then
                        card._v2DescWidth = balanced
                    else
                        -- 均分宽放不下同样行数：末行是否只剩一个字按整宽量出的字宽估（剩下不到两个字宽就算孤字）。
                        local rest = full - room * (lines - 1)
                        if rest < fontSize * 2 then fits = false end
                    end
                end
                desc:SetWidth(card._v2DescWidth)
                desc:SetHeight(0)
            end
        end
    end
    return fits
end

local function LayoutOptionCards(host)
    local style = host._v2Style
    local columns, gap = host._v2Columns, Part(style, "optionCardGap")
    local padX, padY = Part(style, "optionCardPadX"), Part(style, "optionCardPadY")
    local iconSize, descGap = Part(style, "optionCardIconSize"), Part(style, "optionCardDescGap")
    local width = math.max(1, host:GetWidth())
    local fit = style and style.optionCardFit and not host._v2Cells
    if fit then
        while columns > 1 and not OptionCardsFit(host, math.max(1, (width - gap * (columns - 1)) / columns), style) do
            columns = columns - 1
        end
        if columns == 1 then OptionCardsFit(host, width, style) end
    end
    local cardWidth = math.max(1, (width - gap * (columns - 1)) / columns)
    local y, rowHeight = 0, 0
    local heights = {}
    for i, card in ipairs(host._v2Cards) do
        if host._v2Cells and card:IsShown() then
            heights[i] = Part(style, "optionCellHeight")
        elseif fit and card:IsShown() then
            -- 宽已由 OptionCardsFit 定好（单行用卡内宽，换行用均分宽）：只量高、摆位置。
            local desc = card.desc
            local headHeight = math.max(iconSize, math.ceil(card.name:GetStringHeight()))
            local hasDesc = (desc:GetText() or "") ~= ""
            desc:SetWidth(card._v2DescWidth)
            desc:SetHeight(0)
            local textHeight = hasDesc and math.ceil(desc:GetStringHeight()) or 0
            desc:SetHeight(math.max(1, textHeight))
            desc:ClearAllPoints()
            desc:SetPoint("TOPLEFT", card, "TOPLEFT", padX, -(padY + headHeight + descGap))
            heights[i] = padY * 2 + headHeight + (hasDesc and (descGap + textHeight) or 0)
        elseif card:IsShown() then
            -- 描述按卡内宽换行，高度按换行后的实际行数给足（显式设高，不靠字串自适应），排在名字行下面。
            local desc = card.desc
            local room = math.max(1, cardWidth - padX * 2)
            desc:SetWidth(room)
            desc:SetHeight(0) -- 先回到自适应高再量，免得上次设的高把多出的行截掉
            local headHeight = math.max(iconSize, math.ceil(card.name:GetStringHeight()))
            local hasDesc = (desc:GetText() or "") ~= ""
            local textHeight = hasDesc and math.ceil(desc:GetStringHeight()) or 0
            -- 描述要换行时按行数均分宽度，免得最后一行只剩一两个字；均分后行数变多就退回整宽。
            local unbounded = hasDesc and desc:GetUnboundedStringWidth() or 0
            local lines = math.ceil(unbounded / room)
            if lines > 1 then
                local fontSize = select(2, desc:GetFont()) or 0
                desc:SetWidth(math.min(room, math.ceil(unbounded / lines) + fontSize))
                desc:SetHeight(0)
                local balanced = math.ceil(desc:GetStringHeight())
                if balanced > textHeight + 0.5 then
                    desc:SetWidth(room)
                    desc:SetHeight(0)
                else
                    textHeight = balanced
                end
            end
            desc:SetHeight(math.max(1, textHeight))
            desc:ClearAllPoints()
            desc:SetPoint("TOPLEFT", card, "TOPLEFT", padX, -(padY + headHeight + descGap))
            heights[i] = padY * 2 + headHeight + (hasDesc and (descGap + textHeight) or 0)
        end
    end
    for i, card in ipairs(host._v2Cards) do
        if card:IsShown() then
            local column = (i - 1) % columns
            if column == 0 then
                y = y + (i > 1 and rowHeight + gap or 0)
                rowHeight = 0
                for j = i, math.min(i + columns - 1, #host._v2Cards) do
                    if heights[j] then rowHeight = math.max(rowHeight, heights[j]) end
                end
            end
            Place(card, host, column * (cardWidth + gap), y, cardWidth, rowHeight)
            PaintOptionCard(card)
        end
    end
    local total = #host._v2Items > 0 and (y + rowHeight) or 1
    if math.abs(host:GetHeight() - total) > 0.5 then host:SetHeight(total) end
    -- 圆角表面按画的那一刻的屏幕位置对齐像素；量高时宿主还没摆到最终位置，只改位置不会再触发重画，
    -- 角块和中间块会错开，选中卡（主色底）上露出一条竖缝。下一帧按最终位置再画一次。
    if not host._v2RepaintPending then
        host._v2RepaintPending = true
        C_Timer.After(0, function()
            host._v2RepaintPending = nil
            for _, card in ipairs(host._v2Cards or {}) do
                if card:IsShown() and card._v2Host == host then PaintOptionCard(card) end
            end
        end)
    end
end

CreateOptionCards = function(parent, options, style)
    local host, isNew = Factory:AcquireCompositeHost(OPTION_CARDS_POOL, parent)
    if isNew then host._v2Cards = {} end
    host._v2Style, host._v2Columns, host._v2Items = style, options.columns, options.items
    host._v2Value, host._v2Disabled, host._v2OnChange = options.value, false, options.onChange
    local cells = style ~= nil and style.optionCardCells == true
    host._v2Cells = cells
    local padX, padY = Part(style, "optionCardPadX"), Part(style, "optionCardPadY")
    local iconSize, iconGap = Part(style, "optionCardIconSize"), Part(style, "optionCardIconGap")
    for i, item in ipairs(options.items) do
        local card = host._v2Cards[i]
        if not card then
            card = CreateFrame("Button", nil, host)
            card:RegisterForClicks("LeftButtonUp")
            card.icon = card:CreateTexture(nil, "ARTWORK")
            card.name = UI:CreateVisualFontString(card, _G.EXFONTFRAME, "GameFontHighlight")
            card.name:SetJustifyH("LEFT")
            card.name:SetWordWrap(false)
            card.desc = UI:CreateVisualFontString(card, _G.EXFONTFRAME, "GameFontHighlightSmall")
            card.desc:SetJustifyH("LEFT")
            card.desc:SetJustifyV("TOP")
            card.desc:SetWordWrap(true)
            card:SetScript("OnEnter", function(self)
                PaintOptionCard(self)
                -- 格子只写名字：描述放进悬停提示。
                if self._v2Host and self._v2Host._v2Cells and self._v2Desc then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(self._v2Desc, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            card:SetScript("OnLeave", function(self)
                PaintOptionCard(self)
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
            card:SetScript("OnClick", function(self)
                local owner = self._v2Host
                if not owner or owner._v2Disabled or owner._v2Value == self._v2Value then return end
                owner._v2Value = self._v2Value
                for _, other in ipairs(owner._v2Cards) do PaintOptionCard(other) end
                if owner._v2OnChange then owner._v2OnChange(self._v2Value) end
            end)
            host._v2Cards[i] = card
        end
        card._v2Host, card._v2Value, card._v2Icon = host, item.id, item.icon
        card._v2Desc = item.description
        UI.ControlAppearance.Font(card.name, Part(style, cells and "optionCellFont" or "optionCardNameFont"),
            UI.ControlAppearance.colors.text, "", "GameFontHighlight")
        UI.ControlAppearance.Font(card.desc, Part(style, "optionCardDescFont"), _G.ExwindTools.GUIColors.textDim, "", "GameFontHighlightSmall")
        card.name:SetText(item.label)
        card.desc:SetText(item.description or "")
        card.icon:ClearAllPoints()
        card.name:ClearAllPoints()
        card.desc:SetShown(not cells)
        card.name:SetJustifyH(cells and "CENTER" or "LEFT")
        if cells then
            card.icon:Hide()
            card.name:SetPoint("LEFT", card, "LEFT", padX, 0)
        elseif item.icon then
            card.icon:SetSize(iconSize, iconSize)
            card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", padX, -padY)
            SetIconTexture(card.icon, item.icon)
            if type(item.icon) ~= "string" then card.icon:SetVertexColor(1, 1, 1, 1) end
            card.icon:Show()
            card.name:SetPoint("LEFT", card.icon, "RIGHT", iconGap, 0)
        else
            card.icon:Hide()
            card.name:SetPoint("LEFT", card, "TOPLEFT", padX, -(padY + iconSize / 2))
        end
        card.name:SetPoint("RIGHT", card, "RIGHT", -padX, 0)
        card:Show()
    end
    for i = #options.items + 1, #host._v2Cards do host._v2Cards[i]:Hide(); host._v2Cards[i]._v2Host = nil end
    function host:SetValue(value)
        self._v2Value = value
        for _, card in ipairs(self._v2Cards) do PaintOptionCard(card) end
    end
    function host:SetDisabled(disabled)
        self._v2Disabled = disabled == true
        for _, card in ipairs(self._v2Cards) do
            card:SetEnabled(not self._v2Disabled)
            PaintOptionCard(card)
        end
    end
    host:SetScript("OnSizeChanged", LayoutOptionCards)
    Factory:AttachPoolRelease(host, function(frame)
        frame:SetScript("OnSizeChanged", nil)
        for _, card in ipairs(frame._v2Cards) do
            card:Hide()
            card:SetEnabled(true)
            card._v2Host, card._v2Value, card._v2Icon = nil, nil, nil
            card.icon:SetTexture(nil)
            card.name:SetText("")
            card.desc:SetText("")
            UI:ClearControlSurface(card)
        end
        frame._v2Style, frame._v2Columns, frame._v2Items, frame._v2OnChange = nil, nil, nil, nil
        frame.SetValue, frame.SetDisabled = nil, nil
    end)
    host:SetWidth(options.width or GM.settings.controlWideWidth)
    host:Show()
    LayoutOptionCards(host)
    return host
end

end

local function StandardControl(spec, bindingFor)
    local states = setmetatable({}, { __mode = "k" })
    local kind = spec.controlType
    local adapter = {}
    function adapter.mount(host, context)
        local binding = bindingFor(context)
        -- 样式页：单行控件高取预设 controlHeight；没写样式时为 nil，一律走原值。
        local style = context._exStyle
        local styledHeight = style and style.controlHeight
        local function Commit(value)
            if not context:IsCurrent() then return end
            binding:Write(value, "commit")
            context:RefreshPage()
        end
        local width, widget, fallback = GM.size.controlDefaultWidth, nil, nil
        local value = kind ~= "toggles" and kind ~= "preset" and kind ~= "flow" and binding:Read() or nil
        local search = { search = spec.search }
        if kind == "toggles" then
            -- binding 是每项一个的列表；勾掉全部也合法。
            local items, selection = {}, {}
            for i, item in ipairs(spec.items) do
                items[i] = { id = i, label = item.label }
                if binding[i]:Read() == true then selection[i] = true end
            end
            widget = UI:CreateToggleGroup(host, { items = items, value = selection, onChange = function(next)
                if not context:IsCurrent() then return end
                for i, itemBinding in ipairs(binding) do itemBinding:Write(next[i] == true, "commit") end
                context:RefreshPage()
            end })
        elseif kind == "multiline" then
            -- 输入时静默写入（不通知），离开焦点时提交通知；按钮读值时拿到的总是最新文字。
            widget = UI:CreateEditBox(host, value or "", width, spec.size == "tall" and GM.settings.multilineTallHeight
                or GM.settings.multilineHeight, nil, {
                onChanged = function(text, userInput)
                    if userInput and context:IsCurrent() then binding:Write(text, "silent") end
                end,
                onEditFocusLost = function(text)
                    if not context:IsCurrent() then return end
                    binding:Write(text, "silent")
                    binding:Notify("committed")
                end,
            })
        elseif kind == "segment" then
            local items = {}
            local GC = _G.ExwindTools.GUIColors
            for i, option in ipairs(spec.options) do
                items[i] = { option.label, option.value, option.icon, selectedFill = option.tone == "include" and GC.filterInclude
                    or option.tone == "exclude" and GC.filterExclude or nil }
            end
            -- 选项写了图标：每段只画图标（选项文字作悬停提示）。
            local iconOnly = spec.options[1] ~= nil and spec.options[1].icon ~= nil or nil
            -- 写了 allowEmpty 才传：值为空时不高亮任何一项；不写时参数与原来一样。
            -- 预设 segmentTextOffsetY：分段文字整体下移几像素（中文字形偏上，看起来不居中）。
            local textOffsetY = style and style.segmentTextOffsetY
            local segmentOptions = (styledHeight or spec.allowEmpty or textOffsetY or spec.fitText or iconOnly) and
                { height = styledHeight, allowEmpty = spec.allowEmpty, textOffsetY = textOffsetY,
                  sizing = spec.fitText and "content" or nil, iconOnly = iconOnly } or nil
            widget = UI:CreateSegmentedControl(host, width, items, value, Commit, segmentOptions)
            -- 给到的宽度放不下全部选项文字时，改用同一组选项的下拉（不截断文字）。
            fallback = UI:CreateDropdown(host, width, nil, items, value, Commit)
            UI:PrepareSettingsListControl(fallback, { ordinaryControl = true, hideLabel = true })
            fallback:Hide()
        elseif kind == "optionlist" then
            local items = {}
            for i, option in ipairs(spec.options) do
                items[i] = { id = option.value, label = option.label, description = option.description, icon = spec.columns and option.icon or nil }
            end
            if spec.columns then
                widget = CreateOptionCards(host, { items = items, value = value, width = width, columns = spec.columns,
                    onChange = Commit }, style)
            else
                widget = UI:CreateOptionList(host, { items = items, value = value, width = width, onChange = Commit })
            end
        elseif kind == "switch" or kind == "checkbox" or kind == "card" then
            widget = UI:CreateCheckbox(host, spec.label or "", value == true, function(checked) Commit(checked == true) end)
            if kind == "switch" and not spec.label then
                -- 设置行右侧的开关不带文字，宽度就是开关本身。
                UI:PrepareSettingsListControl(widget, { presentation = "switch", hideLabel = true })
                widget:SetSize(GM.size.switchTrackWidth, styledHeight or GM.size.controlHeight)
            end
        elseif kind == "slider" then
            -- percent：数字框显示百分比，输入的数（可带 %）除以 100 写回。
            local formatter = spec.percent and function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end or nil
            local parse = spec.percent and function(text)
                local number = tonumber((text:gsub("%%$", "")))
                return number and number / 100 or nil
            end or nil
            -- 拖动、按住加减时 live 已把值写进值表；松手提交的是同一个值，Write 会因“没变”不发通知，
            -- 所以记下“live 改过”，松手时补发 committed，否则只预览不提交的页面永远收不到提交。
            local liveChanged = false
            widget = UI:CreateSlider(host, width, spec.label or "", spec.min or 0, spec.max or 100, value or 0,
                spec.step or 1, formatter, {
                    onLive = function(live)
                        if context:IsCurrent() and binding:Write(live, "live") then liveChanged = true end
                    end,
                    onCommit = function(committed)
                        if not context:IsCurrent() then return end
                        local pending = liveChanged
                        liveChanged = false
                        if not binding:Write(committed, "commit") and pending then binding:Notify("committed") end
                        context:RefreshPage()
                    end,
                    parse = parse,
                })
        elseif kind == "input" then
            -- 写了 placeholder 才有占位字（占位灰）；不写时与原来一样。
            widget = UI:CreateEditBox(host, value or "", width, styledHeight or GM.size.controlHeight, spec.label,
                { onEnter = Commit, onEditFocusLost = Commit,
                    placeholder = spec.placeholder, placeholderDim = spec.placeholder ~= nil or nil })
        elseif kind == "preset" then
            -- 预设：下拉显示当前字段值正好等于哪一项（都不等时不选），选一项 = 把它的 values 全部写入后刷新一次。
            local items = {}
            for i, option in ipairs(spec.options) do items[i] = { option.label, i } end
            widget = UI:CreateDropdown(host, SizeWidth(spec, style) or width, spec.label, items, PresetMatch(spec, binding),
                function(index)
                    if not context:IsCurrent() then return end
                    local option = spec.options[tonumber(index)]
                    if not option then return end
                    for fieldPath, fieldValue in pairs(option.values) do binding[fieldPath]:Write(fieldValue, "commit") end
                    context:RefreshPage()
                end, search)
        elseif kind == "flow" then
            -- 选择格随分到的宽变宽（没有行名、独占一行时占满整行）。
            widget = UI:CreateFlowDirectionPicker(host, { direction = FlowValue(binding.direction:Read()), stretch = true,
                wrap = FlowValue(binding.wrap:Read()), onChange = function(direction, wrap)
                    if not context:IsCurrent() then return end
                    binding.direction:Write(direction, "commit")
                    binding.wrap:Write(wrap, "commit")
                    context:RefreshPage()
                end })
        elseif kind == "perline" then
            -- 预设 perLineSingle：同一个值只给一种控件（上限不超过 10 只给方块，超过只给数字框）。
            widget = UI:CreatePerLineSelector(host, { max = spec.max, value = PerLineValue(value), noneText = spec.noneText,
                single = style and style.perLineSingle or nil,
                onChange = function(count) Commit(count) end })
        elseif kind == "number" then
            -- 数字框：默认不带步进，写了 stepper = "right" 时右侧带上加下减；提交时写数字（清空 = nil）。
            widget = UI:CreateNumberInput(host, SizeWidth(spec, style) or width, { min = spec.min, max = spec.max,
                step = spec.step, allowEmpty = true, stepper = spec.stepper or "none", height = styledHeight or GM.size.controlHeight,
                label = spec.label, onChanged = function(number) Commit(number) end })
            widget:SetNumber(tonumber(value))
        elseif kind == "color" then
            -- 预设写了 colorWidth：不带 label 的颜色控件写色值不写文字（swatchOnly），宽 = colorWidth。
            local swatch = style and style.colorWidth and not spec.label
            widget = UI:CreateColorButton(host, spec.label or "", binding:Parent(false) or binding.root, binding:Key(), true,
                function()
                    if not context:IsCurrent() then return end
                    binding:Notify("committed")
                    context:RefreshPage()
                end, swatch and { swatchOnly = true } or nil)
            if swatch then widget:SetWidth(style.colorWidth) end
        elseif spec.media == "font" then
            widget = UI:CreateLSMDropdown(host, "font", width, spec.label, value, Commit, search)
        elseif spec.media == "sound" then
            widget = UI:CreateLSMSoundDropdown(host, width, spec.label, value, Commit, search)
        elseif spec.media then
            widget = UI:CreateLSMTextureDropdown(host, spec.media, width, spec.label, value, Commit, search)
        elseif spec.multiple then
            if type(value) ~= "table" then
                value = {}
                binding:Write(value, "silent")
            end
            widget = UI:CreateMultiSelectDropdown(host, width, spec.label, SelectItems(spec), value, function()
                if not context:IsCurrent() then return end
                binding:Notify("committed")
                context:RefreshPage()
            end, search)
            -- 预设写了 multiSeparator：摘要里选中项之间用它连接（默认“, ”）。
            if style and style.multiSeparator then
                widget._exMultiSeparator = style.multiSeparator
                widget:RefreshSelectionDisplay()
            end
        else
            widget = UI:CreateDropdown(host, width, spec.label, SelectItems(spec), value, Commit, search)
        end
        -- 预设写了 overlayControls（设置条）：控件用浮层外观；对象池归还时标记自动清掉。
        if style and style.overlayControls then
            UI:SetControlOverlayAppearance(widget, true)
            if fallback then UI:SetControlOverlayAppearance(fallback, true) end
        end
        local state = { binding = binding, host = host, context = context, fallback = fallback,
            styledHeight = styledHeight, lead = InputLeadReserve(spec, style) }
        if spec.prefix or spec.prefixIcon or spec.trailingIcon then
            state.decor = DecorateInput(host, widget, spec, context, function(mouseButton)
                context._exOwner.actions[spec.trailingAction](context, mouseButton, function(next)
                    Commit(next)
                end)
            end)
        end
        if spec.label and RowControlTypes[kind] then
            local ordinary = kind ~= "switch" and IsOrdinaryRowControl(widget)
            state.ordinary = ordinary
            state.valuePosition = kind == "slider" and "right" or nil
            -- 分段按选项文字定宽，档位控件按档位定宽；放不下时设置行自己转上下排，不压窄。
            local fixed
            if kind == "segment" and style and style.segmentEqualWidth and not spec.size then
                fixed = SizeWidth(spec, style) -- 样式页的平分分段占整列宽
            else
                fixed = (kind == "segment" or kind == "toggles") and ChoiceNaturalWidth(widget) or SizeWidth(spec, style)
                    or ((kind == "flow" or kind == "perline") and widget:GetWidth() or nil) -- 原生选择器按自身尺寸
                    or (SliderFills(spec, style) and math.huge) -- 预设 sliderFill：占满标签右边整列
                    or SteppedSliderWidth(spec, style) -- 预设 sliderSelectWidth：滑杆整组和同页下拉一样宽
            end
            local minWidth = fixed or (ordinary and (kind == "slider" and GM.size.settingsRowSliderMinWidth
                or GM.settings.controlMinWidth) or nil)
            -- 样式页没定宽的输入框、下拉：和“设置行 + 不带 label 的同一控件”排法一样（按控件自然宽请求、文字列按标签字宽），
            -- 不走旧的按行宽比例，否则下拉里的选项文字放不下。
            local styledFit = style and ordinary and not fixed and not spec.size
                and (kind == "input" or kind == "select" or kind == "preset")
            local filled = ordinary and SliderFills(spec, style)
            if styledFit then fixed = widget:GetWidth() end
            -- 样式页按预设定宽的输入框、下拉、颜色，放不下时仍可收窄到 controlMinWidth。
            if style and ordinary and fixed and not spec.size then minWidth = math.min(fixed, GM.settings.controlMinWidth) end
            -- 分段放不下时不换到下一行：行可以把它压到 controlMinWidth，压窄后由同一组选项的下拉顶替（见 measure）。
            if kind == "segment" and fixed and not spec.size then minWidth = math.min(fixed, GM.settings.controlMinWidth) end
            state.row = UI:CreateSettingsRow(host, {
                label = spec.label, description = spec.description,
                autoWidth = (styledFit or filled) and style.settingAutoWidth or nil,
                fullWidth = kind == "multiline" or kind == "optionlist", -- 多行文字、单选卡片：标签在上，控件占满整行
                controlKind = ordinary and "ordinary" or nil,
                controlWidth = fixed,
                controlMinWidth = minWidth,
                inputWidthPercent = spec.inputWidthPercent,
                style = context._exStyle,
            })
            UI:PrepareSettingsListControl(widget, {
                ordinaryControl = ordinary, hideLabel = true,
                presentation = kind == "switch" and "switch" or nil,
                valuePosition = state.valuePosition,
                inputWidth = kind == "slider" and style and style.sliderInputWidth or nil,
                inputHeight = kind == "slider" and style and style.sliderInputHeight or nil,
            })
            context._exSettingsRow = true
            -- 占满标签右边的滑杆行：同卡这类行的标签列对齐（见 AlignSliderLabels）。
            if kind == "slider" then widget._v2SliderRow = filled and state.row or nil end
        elseif kind == "slider" and style then
            -- 样式页设置行里不带 label 的滑杆：轨道和数字框排成一行（与带 label 的滑杆同一种排法），高同普通控件。
            state.valuePosition = "right"
            UI:PrepareSettingsListControl(widget, { ordinaryControl = true, hideLabel = true, valuePosition = "right",
                inputWidth = style.sliderInputWidth, inputHeight = style.sliderInputHeight })
        end
        if kind == "slider" and not state.row then widget._v2SliderRow = nil end
        states[widget] = state
        return widget
    end
    function adapter.update(widget)
        if kind == "toggles" then
            local selection = {}
            for i, itemBinding in ipairs(states[widget].binding) do
                if itemBinding:Read() == true then selection[i] = true end
            end
            widget:SetValue(selection)
            return
        end
        -- 预设、排列的绑定是一组（各自在下面的分支里读），不是单个绑定。
        local value
        if kind ~= "preset" and kind ~= "flow" then value = states[widget].binding:Read() end
        if kind == "multiline" then
            if not widget.editBox:HasFocus() then widget.editBox:SetText(value == nil and "" or tostring(value)) end
        elseif kind == "segment" then
            widget:SetValue(value)
            UI:SetDropdownValue(states[widget].fallback, value)
        elseif kind == "optionlist" then
            widget:SetValue(value)
        elseif kind == "switch" or kind == "checkbox" or kind == "card" then
            widget:SetChecked(value == true)
            UI:ApplyControlAppearance(widget)
        elseif kind == "slider" then
            if tonumber(value) then widget:SetEXUIValue(tonumber(value), "silent") end
        elseif kind == "input" then
            if not widget:HasFocus() then widget:SetText(value == nil and "" or tostring(value)) end
        elseif kind == "number" then
            if not widget:HasFocus() then widget:SetNumber(tonumber(value)) end
        elseif kind == "preset" then
            UI:SetDropdownValue(widget, PresetMatch(spec, states[widget].binding))
        elseif kind == "flow" then
            local binding = states[widget].binding
            widget:SetFlow(FlowValue(binding.direction:Read()), FlowValue(binding.wrap:Read()))
        elseif kind == "perline" then
            widget:SetValue(PerLineValue(value))
        elseif kind == "color" then
            widget:UpdateColor()
        elseif spec.multiple then
            widget._selections = type(value) == "table" and value or {}
            widget:RefreshSelectionDisplay()
        else
            UI:SetDropdownValue(widget, value)
        end
    end
    function adapter.measure(widget, context, width)
        local state = states[widget]
        local row = state.row
        if kind == "multiline" then
            -- 文字区在滚动框里，宽度跟随外框（扣掉滚动留位）。
            widget.editBox:GetParent():SetWidth(math.max(1, width - GM.settings.multilineScrollReserve))
        end
        if not row then
            if state.valuePosition then return (UI:UpdateSettingsListControlLayout(widget, width)) end
            widget:SetWidth(math.max(1, width - state.lead))
            if kind == "flow" or kind == "perline" then widget:Relayout() end -- 按新宽摆选择格 / 方块
            if kind == "segment" then
                local natural = ChoiceNaturalWidth(widget)
                state.useFallback = natural ~= nil and width + 0.5 < natural
                if state.useFallback then
                    state.fallback:SetWidth(width)
                    return state.styledHeight or GM.size.controlHeight
                end
            end
            if kind == "optionlist" then
                -- 卡片高度随宽度换行变化：立即按新宽度排一次再读高度。
                local onSize = widget:GetScript("OnSizeChanged")
                if onSize then onSize(widget) end
            end
            if kind == "slider" or kind == "segment" or kind == "toggles" or kind == "multiline" or kind == "optionlist"
                or kind == "flow" or kind == "perline" then
                return widget:GetHeight()
            end
            return spec.height or state.styledHeight or GM.size.controlHeight
        end
        UI:SetSettingsRowLast(row, context._exRowLast ~= false)
        local height, x, y, controlWidth = UI:UpdateSettingsRowLayout(row, width, math.max(1, widget:GetHeight()), nil)
        -- 样式页的行左右内距取预设。
        local rowPaddingX = context._exStyle and context._exStyle.rowPaddingX or GM.settings.rowPaddingX
        if kind == "multiline" or kind == "optionlist" then
            -- 整行控件与标签左缘对齐，左右留行内边距。
            controlWidth = math.max(1, width - rowPaddingX * 2)
            if kind == "multiline" then
                widget.editBox:GetParent():SetWidth(math.max(1, controlWidth - GM.settings.multilineScrollReserve))
            end
        end
        controlWidth = math.max(1, controlWidth - state.lead)
        widget:SetWidth(controlWidth)
        if kind == "optionlist" then
            local onSize = widget:GetScript("OnSizeChanged")
            if onSize then onSize(widget) end
        end
        if kind == "segment" then
            local natural = ChoiceNaturalWidth(widget)
            state.useFallback = natural ~= nil and controlWidth + 0.5 < natural
            if state.useFallback then
                state.fallback:SetWidth(controlWidth)
                -- 样式页：顶替分段的下拉也取预设控件高。
                if state.styledHeight then
                    UI:UpdateSettingsListControlLayout(state.fallback, controlWidth, state.styledHeight)
                end
            end
        end
        if state.ordinary or state.valuePosition then
            UI:UpdateSettingsListControlLayout(widget, controlWidth, state.styledHeight)
        end
        height, x, y = UI:UpdateSettingsRowLayout(row, width, math.max(1, widget:GetHeight()), nil)
        if kind == "multiline" or kind == "optionlist" then x = rowPaddingX end
        state.x, state.y = x + state.lead, y
        return height
    end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        -- 分段放不下时显示同一组选项的下拉，摆在分段原本的位置。
        local shown = state.useFallback and state.fallback or widget
        if state.fallback then
            widget:SetShown(not state.useFallback)
            state.fallback:SetShown(state.useFallback == true)
        end
        if not state.row and state.valuePosition then
            -- 轨道宽已在 measure 里按总宽扣掉数字框排好，这里只定位。
            shown:ClearAllPoints()
            PixelUtil.SetPoint(shown, "TOPLEFT", state.host, "TOPLEFT", 0, 0, 0, 0)
            return
        end
        if not state.row then
            Place(shown, state.host, state.lead, 0, width - state.lead,
                state.useFallback and (state.styledHeight or GM.size.controlHeight) or height)
            return
        end
        state.row:ClearAllPoints()
        state.row:SetPoint("TOPLEFT", state.host, "TOPLEFT", 0, 0)
        shown:ClearAllPoints()
        PixelUtil.SetPoint(shown, "TOPLEFT", state.row, "TOPLEFT", state.x, -state.y, 0, 0)
    end
    function adapter.release(widget, context)
        local state = states[widget]
        states[widget] = nil
        context._exSettingsRow, context._exRowLast = nil, nil
        if state and state.decor then ReleaseInputDecor(state.decor, widget) end
        if kind == "flow" or kind == "perline" then
            widget:SetAlpha(1)
            for _, child in ipairs({ widget:GetChildren() }) do
                if child.SetEnabled then child:SetEnabled(true) end
            end
        end
        ReleaseBoundWidget(widget)
        if state and state.fallback then ReleaseBoundWidget(state.fallback) end
        if state and state.row then state.row:Release() end
    end
    function adapter.setEnabled(widget, context, enabled)
        if kind == "flow" or kind == "perline" then
            -- 原生选择器没有整体停用：逐个停用里面的格子 / 方块 / 输入框，并降低不透明度。
            for _, child in ipairs({ widget:GetChildren() }) do
                if child.SetEnabled then child:SetEnabled(enabled) end
            end
            widget:SetAlpha(enabled and 1 or 0.5)
            return
        end
        ControlDefaults.setEnabled(widget, context, enabled)
        local decor = states[widget] and states[widget].decor
        if decor and decor.trailing then decor.trailing:SetEnabled(enabled) end
        local fallback = states[widget] and states[widget].fallback
        if fallback then ControlDefaults.setEnabled(fallback, context, enabled) end
    end
    function adapter.setVisible(widget, context, visible)
        local state = states[widget]
        if state and state.fallback then
            ControlDefaults.setVisible(state.fallback, context, visible and state.useFallback == true)
            ControlDefaults.setVisible(widget, context, visible and not state.useFallback)
            return
        end
        ControlDefaults.setVisible(widget, context, visible)
    end
    return adapter
end

local DEFAULT_FONT_GROUP = { font = "Friz Quadrata TT", size = 14, r = 1, g = 1, b = 1, a = 1,
    outline = "", shadow = false, x = 0, y = 0 }
local DEFAULT_TIMER_BAR_GROUP = { width = 240, height = 24, texture = "Clean",
    barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
    barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
    showIcon = true, iconSide = "LEFT", iconWidth = 24, iconHeight = 24, iconOffsetX = -5, iconOffsetY = 0 }

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

-- Composite groups bind exactly as the settings-section page did: `path` is the
-- section path plus the component key; opts.bindRoot / opts.bindValue keep
-- their meaning. Components inside a card render body-only.
local function StandardComponent(spec, bindingFor, runtimeOpts)
    local states = setmetatable({}, { __mode = "k" })
    local kind = spec.component
    local adapter = { component = kind }
    function adapter.mount(host, context)
        local binding = bindingFor(context)
        local opts = CopyTable(spec.opts)
        for key, value in pairs(runtimeOpts or {}) do opts[key] = value end
        if opts.bodyOnly == nil then opts.bodyOnly = true end
        if kind == "modulecommonsettings" then
            opts.presentation = opts.presentation or "settings-list"
            opts._exTypedSettings = true
        end
        local key, parentPath, root, fullPath = binding:Key(), binding.parentPath, binding.root, binding.path
        local scoped = parentPath and binding:Parent(false) or root
        local width = math.max(GM.size.controlDefaultWidth, host:GetWidth())
        local function Options(pathPrefix)
            local result = CopyTable(opts)
            result._exWriteContext = { moduleKey = binding.moduleKey, pathPrefix = pathPrefix }
            return result
        end
        local function Notifier(notifyPath)
            return function()
                UI:NotifyModuleValueChanged(binding.moduleKey, notifyPath, "committed")
                context:RefreshPage()
            end
        end
        local widget
        if kind == "fontgroup" then
            local value = binding:Read()
            if not value then
                value = CopyTable(DEFAULT_FONT_GROUP)
                binding:Write(value, "commit")
            end
            widget = UI:CreateFontGroup(host, width, spec.label, value, Notifier(fullPath), Options(fullPath))
        elseif kind == "glow_settings" then
            -- 发光组的设置行跟着页面样式；path 是字段前缀（<path>Enabled / Style …）。
            local glowOpts = Options(fullPath)
            glowOpts.style = context._exStyle
            widget = UI:CreateGlowSettings(host, width, spec.label, scoped, key, Notifier(fullPath), glowOpts)
        elseif kind == "widgetlayout" then
            widget = UI:CreateWidgetLayoutGroup(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "soundgroup" then
            widget = UI:CreateSoundGroup(host, width, spec.label, scoped, key, Notifier(fullPath), Options(fullPath))
        elseif kind == "modulecommonsettings" then
            local bindKey = opts.bindRoot ~= true and key or nil
            local commonPath = bindKey and fullPath or (parentPath or "")
            widget = UI:CreateModuleCommonSettingsGroup(host, width, spec.label, scoped, bindKey,
                Notifier(commonPath), Options(commonPath))
        elseif kind == "anchorgroup" then
            local bindKey = opts.bindRoot ~= true and key or nil
            local anchorPath = bindKey and fullPath or (parentPath or "")
            widget = UI:CreateAnchorGroup(host, width, spec.label, scoped, bindKey, function(_, field)
                local changedPath = anchorPath ~= "" and (anchorPath .. "." .. field) or field
                UI:NotifyModuleValueChanged(binding.moduleKey, changedPath, "committed")
                context:RefreshPage()
            end, Options(anchorPath))
        elseif kind == "texturegroup" then
            local bindValue = opts.bindValue == true
            widget = UI:CreateTextureGroup(host, width, spec.label, bindValue and binding:Read() or scoped,
                not bindValue and key or nil, Notifier(fullPath), Options(fullPath))
        elseif kind == "icongroup" then
            local bindRoot, bindValue = opts.bindRoot == true, opts.bindValue == true
            local source = bindValue and binding:Read() or (bindRoot and root or scoped)
            local bindKey = (not bindRoot and not bindValue) and key or nil
            local iconPath = (bindValue or bindKey) and fullPath or (parentPath or "")
            widget = UI:CreateIconGroup(host, width, spec.label, source, bindKey, Notifier(iconPath), Options(iconPath))
        else -- timerbargroup
            local bindRoot = opts.bindRoot == true
            local value = bindRoot and root or binding:Read()
            if not value then
                value = CopyTable(DEFAULT_TIMER_BAR_GROUP)
                binding:Write(value, "commit")
            end
            local timerPath = bindRoot and (parentPath or "") or fullPath
            widget = UI:CreateTimerBarGroup(host, width, spec.label, value, nil, Notifier(timerPath), Options(timerPath))
        end
        states[widget] = { host = host, opts = opts, scoped = scoped,
            item = { type = kind, key = key, label = spec.label, opts = opts } }
        -- 锚点组本身就是一行设置行，与相邻设置行连成同一列表。
        if widget._exAnchorRow then context._exSettingsRow = true end
        return widget
    end
    function adapter.update(widget)
        UI:RefreshCompositeGroupFromDB(widget)
    end
    function adapter.measure(widget, context, width)
        local state = states[widget]
        if widget._exAnchorRow then UI:SetSettingsRowLast(widget._exAnchorRow, context._exRowLast ~= false) end
        -- 行数随存档变的组（发光）自己按宽排一次给出高。
        if widget._exMeasureHeight then return widget:_exMeasureHeight(width) end
        local measured = UI:MeasureGridComponent(kind, width, state.opts, state.scoped, state.item)
        if type(measured) == "table" then
            local preferred = tonumber(measured.preferredHeight or measured.height)
            local minimum = tonumber(measured.minHeight)
            measured = preferred and minimum and math.max(preferred, minimum) or preferred or minimum
        end
        return tonumber(measured) or widget:GetHeight()
    end
    function adapter.layout(widget, context, width, height)
        Place(widget, states[widget].host, 0, 0, width, height)
        widget._exGridWidth = width
        UI:LayoutCompositeGroup(widget, width, height)
    end
    function adapter.release(widget, context)
        states[widget] = nil
        if widget._exAnchorRow then context._exSettingsRow, context._exRowLast = nil, nil end
        ReleaseBoundWidget(widget)
    end
    adapter.setEnabled, adapter.setVisible = ControlDefaults.setEnabled, ControlDefaults.setVisible
    return adapter
end

-- 连体声音选择：来源 | 内容（语音包 / LSM / 路径 / TTS）| ▶，用 Core 的 LayoutSoundSelector 拼成一段。
-- path 是字段前缀，读写 <path>Source / Label / LSM / Path / TtsText；挂载时不写任何默认值。
-- opts.sources = 可选来源（pack/lsm/file/tts，按顺序）；opts.labelSource = 语音包条目的全局 provider 名；
-- opts.test = ▶ 发出的 clickKey（<moduleKey>.ButtonClicked，播放仍由模块自己做）。
-- opts.channel = true：同一行多一段音频通道下拉（来源 | 内容 | 通道 | ▶），写 <path>Channel
-- （"Master" / "SFX" / "Music" / "Ambience" / "Dialog"，WoW PlaySoundFile 的通道名）；字段为空时显示主音量、不写存档。
-- opts.testTip = ▶ 的悬停提示文字（可选），按下即收起。
-- 只有一种来源时不显示来源段，内容段从左缘开始。
local SoundSources = { pack = "语音包", lsm = "LSM音效", file = "自定义路径", tts = "TTS语音" }
local SoundSuffix = { source = "Source", pack = "Label", lsm = "LSM", file = "Path", tts = "TtsText" }
local SoundChannel = { order = { "Master", "SFX", "Music", "Ambience", "Dialog" } }
SoundChannel.names = { Master = "MASTER_VOLUME", SFX = "FX_VOLUME", Music = "MUSIC_VOLUME",
    Ambience = "AMBIENCE_VOLUME", Dialog = "DIALOG_VOLUME" }

-- 拼接控件的圆角边（与 ExwindGUIComposite 的声音选择器同一标记）：first 左圆右直、middle 两边直、last 右圆左直。
function SoundChannel.JoinEdge(control, edge)
    if not control._exJoinedEdge then
        local release = control._exPoolRelease
        Factory:AttachPoolRelease(control, function(self)
            self._exJoinedEdge = nil
            if release then release(self) end
        end)
    end
    control._exJoinedEdge = edge
    UI:ApplyControlAppearance(control)
    for _, skin in pairs(control._exModernSurfaces or {}) do skin.Layout() end
end

-- ▶ 的悬停提示：池化按钮只挂一次脚本，提示文字按租约写在 _exV2Tip，归还时清掉。
function SoundChannel.PreviewTip(button, tip)
    if not button._exV2TipHooked then
        button._exV2TipHooked = true
        button:HookScript("OnEnter", function(self)
            if not self._exV2Tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self._exV2Tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
        button:HookScript("OnMouseDown", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
    end
    if tip and not button._exV2Tip then
        local release = button._exPoolRelease
        Factory:AttachPoolRelease(button, function(self)
            self._exV2Tip = nil
            if release then release(self) end
        end)
    end
    button._exV2Tip = tip
end

local function SoundSelectorComponent(spec, bindingFor, runtimeOpts)
    local opts = spec.opts or {}
    Check(type(opts.sources) == "table" and #opts.sources > 0, spec.component .. ": opts.sources required")
    for _, source in ipairs(opts.sources) do Check(SoundSources[source] ~= nil, "unknown sound source " .. tostring(source)) end
    Check(opts.labelSource == nil or type(opts.labelSource) == "string", "opts.labelSource must be a provider name")
    Check(opts.test == nil or Name(opts.test), "opts.test must be a clickKey")
    Check(opts.channel == nil or opts.channel == true, "opts.channel must be true")
    Check(opts.testTip == nil or type(opts.testTip) == "string", "opts.testTip must be a string")
    Check(opts.tiles == nil or opts.tiles == true, "opts.tiles must be true")
    -- opts.tiles：一排格子（来源 / 声音 / 声道 / ▶ 试听），实现在 ExwindSoundTiles.lua，读写同下。
    if opts.tiles then
        return UI:CreateSoundTilesAdapter(spec, bindingFor, runtimeOpts, {
            SoundSuffix = SoundSuffix, SoundSources = SoundSources, SoundChannel = SoundChannel,
            CreateBinding = CreateBinding, Acquire = Acquire, Place = Place, SelectItems = SelectItems,
            ReleaseBoundWidget = ReleaseBoundWidget, ControlDefaults = ControlDefaults,
            ReleaseCompositeHost = function(widget) Factory:ReleaseCompositeHost(widget) end })
    end
    local states = setmetatable({}, { __mode = "k" })
    local adapter = { component = spec.component }
    function adapter.mount(host, context)
        local base = bindingFor(context)
        local fields = {}
        for name, suffix in pairs(SoundSuffix) do fields[name] = CreateBinding(base.moduleKey, base.root, base.path .. suffix) end
        if opts.channel then fields.channel = CreateBinding(base.moduleKey, base.root, base.path .. "Channel") end
        local widget = Acquire(host)
        local height, L = GM.size.controlHeight, _G.ExwindTools.L
        local function Commit(name)
            return function(value)
                if not context:IsCurrent() then return end
                fields[name]:Write(value, "commit")
                context:RefreshPage()
            end
        end
        local sourceItems = {}
        for i, source in ipairs(opts.sources) do sourceItems[i] = { L[SoundSources[source]], source } end
        local parts = {
            source = UI:CreateDropdown(widget, GM.size.controlDefaultWidth, nil, sourceItems, fields.source:Read(),
                Commit("source"), { widthFromOptions = true }),
            lsm = UI:CreateLSMSoundDropdown(widget, GM.size.controlDefaultWidth, nil, fields.lsm:Read(), Commit("lsm"), { search = true }),
            file = UI:CreateEditBox(widget, fields.file:Read() or "", GM.size.controlDefaultWidth, height, nil,
                { onEnter = Commit("file"), onEditFocusLost = Commit("file") }),
            tts = UI:CreateEditBox(widget, fields.tts:Read() or "", GM.size.controlDefaultWidth, height, nil,
                { onEnter = Commit("tts"), onEditFocusLost = Commit("tts") }),
        }
        if opts.labelSource then
            parts.pack = UI:CreateDropdown(widget, GM.size.controlDefaultWidth, nil, SelectItems({ optionsSource = opts.labelSource }),
                fields.pack:Read(), Commit("pack"), { search = true })
        end
        local sourceNatural = parts.source:GetWidth()
        local channel
        if opts.channel then
            local channelItems = {}
            for i, name in ipairs(SoundChannel.order) do channelItems[i] = { _G[SoundChannel.names[name]] or name, name } end
            channel = UI:CreateDropdown(widget, GM.size.controlDefaultWidth, nil, channelItems, fields.channel:Read() or "Master",
                Commit("channel"))
            UI:PrepareSettingsListControl(channel, { ordinaryControl = true, hideLabel = true })
        end
        local preview
        preview = UI:CreateButton(widget, height, height, "", function()
            if not context:IsCurrent() then return end
            -- optionsRef 给的 onTest(context, button) 优先：模块自己播放并显示播放状态。
            if runtimeOpts and runtimeOpts.onTest then return runtimeOpts.onTest(context, preview) end
            if not opts.test then return end
            _G.ExwindTools:UpdateState(base.moduleKey .. ".ButtonClicked", { key = opts.test, fullPath = base.path, ts = GetTime() })
        end, { compact = true })
        UI:ApplySoundPreviewAppearance(preview)
        if opts.testTip then SoundChannel.PreviewTip(preview, opts.testTip) end
        for _, part in pairs(parts) do UI:PrepareSettingsListControl(part, { ordinaryControl = true, hideLabel = true }) end
        local contents = {}
        for _, source in ipairs(opts.sources) do contents[source] = parts[source] end
        -- 不在可选来源里的内容件不参与排版和显隐切换，一直藏着，免得停在左上角压住别的控件。
        for name, part in pairs(parts) do if name ~= "source" and not contents[name] then part:Hide() end end
        widget:SetSize(GM.settings.soundSelectorWidth, height)
        states[widget] = { host = host, fields = fields, parts = parts, preview = preview, contents = contents,
            sourceNatural = sourceNatural, enabled = true, channel = channel }
        return widget
    end
    -- 来源字段为空或不在可选来源里（例如只有一个来源、存档本来就没有来源字段）时按第一个来源显示，不写存档。
    local function SourceOf(state)
        local value = state.fields.source:Read()
        return state.contents[value] and value or opts.sources[1]
    end
    local function Refresh(widget)
        local state = states[widget]
        UI:RefreshSoundSelector({ contents = state.contents, preview = state.preview,
            value = SourceOf(state), enabled = state.enabled,
            setUsable = function(control, usable) ControlDefaults.setEnabled(control, nil, usable) end })
    end
    function adapter.update(widget)
        local state = states[widget]
        UI:SetDropdownValue(state.parts.source, SourceOf(state))
        UI:SetDropdownValue(state.parts.lsm, state.fields.lsm:Read())
        if state.parts.pack then UI:SetDropdownValue(state.parts.pack, state.fields.pack:Read()) end
        if state.channel then UI:SetDropdownValue(state.channel, state.fields.channel:Read() or "Master") end
        for _, name in ipairs({ "file", "tts" }) do
            local box = state.parts[name]
            if not box:HasFocus() then box:SetText(state.fields[name]:Read() or "") end
        end
        Refresh(widget)
    end
    function adapter.measure() return GM.size.controlHeight end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        -- 只有一个来源时不显示来源下拉，内容段从左缘开始。带声道时来源、声道都收窄，宽留给中间的内容段。
        local single = #opts.sources == 1
        local sourceRatio = state.channel and GM.settings.soundChannelSourceRatio or GM.settings.soundSourceMaxRatio
        UI:LayoutSoundSelector(widget, { source = state.parts.source, preview = state.preview, contents = state.contents,
            left = 0, right = 0, top = 0, height = GM.size.controlHeight,
            sourceWidth = single and 1 or math.min(state.sourceNatural, width * sourceRatio),
            previewWidth = GM.size.controlHeight,
            paintPreview = function(button) UI:ApplySoundPreviewAppearance(button) end })
        state.parts.source:SetShown(not single)
        if single and context._exStyle then -- 样式页：内容段顶到左缘、左边圆角（普通页照旧）
            for _, control in pairs(state.contents) do
                control:ClearAllPoints()
                control:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
                control:SetPoint("TOPRIGHT", state.preview, "TOPLEFT", 0, 0)
                SoundChannel.JoinEdge(control, "first")
            end
        end
        if state.channel then
            -- 声道段按 soundChannelRatio 取宽，来源段和声道段之间剩下的都给内容段。
            local channelWidth = math.max(1, width * GM.settings.soundChannelRatio)
            local channel = state.channel
            channel._exGridFixedHeight = GM.size.controlHeight
            channel:ClearAllPoints()
            channel:SetPoint("TOPRIGHT", state.preview, "TOPLEFT", 0, 0)
            channel:SetSize(channelWidth, GM.size.controlHeight)
            SoundChannel.JoinEdge(channel, "middle")
            for _, control in pairs(state.contents) do
                control:SetPoint("TOPRIGHT", channel, "TOPLEFT", 0, 0)
            end
        end
        Refresh(widget)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        ControlDefaults.setEnabled(state.parts.source, context, enabled)
        if state.channel then ControlDefaults.setEnabled(state.channel, context, enabled) end
        Refresh(widget)
    end
    adapter.setVisible = ControlDefaults.setVisible
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        for _, part in pairs(state.parts) do ReleaseBoundWidget(part) end
        if state.channel then ReleaseBoundWidget(state.channel) end
        Factory:Release(state.preview._fromPool, state.preview)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

local PathControlSpecFields = PathControlFields .. " height"

function UI:CreateSettingsV2Binding(moduleKey, root, path)
    return CreateBinding(moduleKey, root, path)
end

-- Owner helpers: the same standard controls for records and other owner data.
-- bindingFor(context) returns UI:CreateSettingsV2Binding(...) for that mount.
function UI:CreateSettingsV2Control(spec, bindingFor)
    local ok, issue = SchemaKeys(spec, PathControlSpecFields, "control")
    if ok then ok, issue = SchemaPathControl(spec, "control") end
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Check(type(bindingFor) == "function", "CreateSettingsV2Control requires bindingFor")
    Check(spec.controlType ~= "toggles" and spec.controlType ~= "preset" and spec.controlType ~= "flow",
        "toggles / preset / flow bind several paths; declare them as path nodes")
    local copy = DeclarationCopy(spec, {})
    local adapter = StandardControl(copy, bindingFor)
    adapter._exStandard = true
    adapter._exSpec = copy -- 样式页按它的 size 档位定自然宽（见 Natural）
    return adapter
end

-- runtimeOpts (optional) may carry callbacks; it is merged over spec.opts at mount.
function UI:CreateSettingsV2Component(spec, bindingFor, runtimeOpts)
    local ok, issue = SchemaKeys(spec, "component label opts", "component")
    Check(ok, issue and (issue.path .. ": " .. issue.message))
    Check(StandardComponents[spec.component], "unknown standard component " .. tostring(spec.component))
    Check(type(bindingFor) == "function", "CreateSettingsV2Component requires bindingFor")
    Check(runtimeOpts == nil or type(runtimeOpts) == "table", "runtimeOpts must be a table")
    local adapter = spec.component == "soundselector" and SoundSelectorComponent(DeclarationCopy(spec, {}), bindingFor, runtimeOpts)
        or StandardComponent(DeclarationCopy(spec, {}), bindingFor, runtimeOpts)
    adapter._exStandard = true
    return adapter
end

-- 标签排（chips）：每个标签是一个紧凑按钮（selected 用主要按钮配色），写了 remove 时标签内右侧带 × 图标按钮，
-- 写了 add 时末尾一个“＋”按钮；按宽度从左到右排，放不下换行。记录变了（文字 / 高亮 / 条数 / 记录本身）才重建按钮。
local CHIPS_POOL = "EXUI.SettingsV2.Chips"
Factory:InitCompositePool(CHIPS_POOL)
local CHIP_GAP = GM.space.descriptionGap

-- chipinput（法术列表）与 chips 同一套排法，另加：记录可带 icon（标签内文字前的图标），末尾一个输入框，
-- 回车时调用 actions[add](context, 输入文字) 并清空输入框；没有“＋”标签。
local CHIP_ICON_POOL = "EXUI.SettingsV2.ChipIcon"
Factory:InitCompositePool(CHIP_ICON_POOL)


-- 三态小标签（chips.tristate）：自己画的小块（池化），不限 = 控件底 + 输入框边；只看 = 绿底白字；排除 = 红底白字。
local TriChip = {}
do
local TRI_CHIP_POOL = "EXUI.SettingsV2.TriChip"
Factory:InitCompositePool(TRI_CHIP_POOL)
local TriStates = { include = true, exclude = true }
local TriNext = { include = "exclude", exclude = nil }

local function PaintTriChip(chip)
    local state = chip._v2State
    if not state then return end
    local GC, colors = _G.ExwindTools.GUIColors, UI.ControlAppearance.colors
    local hover = state.enabled and chip:IsMouseOver()
    local fill, border, text
    if state.state == "include" then
        fill = hover and GC.filterIncludeHover or GC.filterInclude
        border, text = fill, GC.white
    elseif state.state == "exclude" then
        fill, border, text = GC.filterExclude, GC.filterExclude, GC.white
    else
        fill, border, text = GC.input, hover and GC.inputHoverBorder or GC.inputBorder, colors.text
    end
    UI:SetControlSurface(chip, GM.radius.control, fill, border)
    chip.label:SetTextColor(unpack(state.enabled and text or colors.muted))
    chip:SetAlpha(state.enabled and 1 or 0.6)
end

local function AcquireTriChip(parent, record, style, onClick)
    local chip, isNew = Factory:AcquireCompositeHost(TRI_CHIP_POOL, parent)
    if isNew then
        chip.button = CreateFrame("Button", nil, chip)
        chip.button:SetAllPoints(chip)
        chip.button:RegisterForClicks("LeftButtonUp")
        chip.label = UI:CreateVisualFontString(chip, _G.EXFONTFRAME, "GameFontHighlightSmall")
        chip.label:SetWordWrap(false)
        chip.dot = CreateFrame("Frame", nil, chip)
        chip.dot:EnableMouse(false)
        chip.button:SetScript("OnEnter", function(self)
            PaintTriChip(chip)
            local tip = chip._v2State and chip._v2State.tip
            if tip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(tip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        chip.button:SetScript("OnLeave", function(self)
            PaintTriChip(chip)
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end)
        chip.button:SetScript("OnMouseDown", function(self)
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end)
        chip.button:SetScript("OnClick", function()
            local state = chip._v2State
            if state and state.onClick then state.onClick() end
        end)
    end
    chip.button:SetFrameLevel(chip:GetFrameLevel() + 3)
    UI.ControlAppearance.Font(chip.label, Part(style, "triFont"), UI.ControlAppearance.colors.text, "", "GameFontHighlightSmall")
    chip.label:SetText(record.text)
    local padX, dotSize = Part(style, "triPaddingX"), Part(style, "triDotSize")
    chip.label:ClearAllPoints()
    if record.dot then
        chip.dot:SetSize(dotSize, dotSize)
        chip.dot:ClearAllPoints()
        chip.dot:SetPoint("LEFT", chip, "LEFT", padX, 0)
        UI:SetControlSurface(chip.dot, dotSize / 2, { record.dot[1], record.dot[2], record.dot[3], 1 }, { 0, 0, 0, 0.35 })
        chip.dot:Show()
        chip.label:SetPoint("LEFT", chip.dot, "RIGHT", Part(style, "triDotGap"), 0)
    else
        chip.dot:Hide()
        chip.label:SetPoint("LEFT", chip, "LEFT", padX, 0)
    end
    chip._v2State = { state = record.state, tip = record.tip, enabled = true, onClick = onClick }
    chip._v2Width = math.ceil(chip.label:GetUnboundedStringWidth()) + padX * 2
        + (record.dot and dotSize + Part(style, "triDotGap") or 0)
    chip:Show()
    PaintTriChip(chip)
    return chip
end

local function ReleaseTriChip(chip)
    if GameTooltip:GetOwner() == chip.button then GameTooltip:Hide() end
    chip._v2State, chip._v2Width = nil, nil
    chip.label:SetText("")
    UI:ClearControlSurface(chip)
    UI:ClearControlSurface(chip.dot)
    chip:SetAlpha(1)
    Factory:ReleaseCompositeHost(chip)
end

TriChip.Acquire, TriChip.Release, TriChip.Paint = AcquireTriChip, ReleaseTriChip, PaintTriChip
TriChip.States, TriChip.Next = TriStates, TriNext
end

local function ChipsAdapter(node)
    local spec, session = node.spec, node.session
    local withInput = spec.kind == "chipinput"
    local states = {}
    local adapter = {}
    -- 样式预设 chipHeight（芯片、三态小标签高）；没写时取控件高。
    local function Height() return session.style and session.style.chipHeight or StyledControlHeight(session.style) end
    -- 预设 chipInputHeight / chipInputIconSize：法术芯片自己的高和图标边长（输入框仍是 Height()）；没写时同普通芯片。
    local function ChipHeight() return withInput and session.style and session.style.chipInputHeight or Height() end
    local function IconSize()
        return withInput and session.style and session.style.chipInputIconSize or Part(session.style, "chipIconSize")
    end
    local function RemoveSize() return math.max(1, ChipHeight() - GM.space.compactButtonPaddingX) end
    local function Columns() return withInput and session.style and session.style.chipInputColumns or nil end
    local function NamedMax() return Columns() and session.style.chipInputNamedMax or nil end
    local function InputFirst() return withInput and session.style and session.style.chipInputFirst == true end
    local function CompactIcon() return withInput and session.style and session.style.chipIconCompact == true end
    local function HoverRemove() return withInput and session.style and session.style.chipInputHoverRemove == true end
    local function ReleaseChips(state)
        for _, chip in ipairs(state.chips) do
            if chip.tri then TriChip.Release(chip.button) else
            if chip.remove then chip.remove:Release() end
            if chip.icon then
                chip.icon.texture:SetTexture(nil)
                Factory:ReleaseCompositeHost(chip.icon)
            end
            if chip.oneLine then chip.oneLine:SetWordWrap(true) end
            Factory:Release(chip.button._fromPool, chip.button)
            end
        end
        state.chips = {}
    end
    local function SetChipEnabled(chip, enabled)
        if chip.tri then
            chip.button._v2State.enabled = enabled
            chip.button.button:SetEnabled(enabled)
            TriChip.Paint(chip.button)
        else
            chip.button:SetEnabled(enabled)
        end
    end
    local function Rebuild(widget, context)
        local state = states[widget]
        local records = Records(node)
        for i, record in ipairs(records) do
            Check(type(record.text) == "string", spec.id .. ": chip text must be string")
            Check(record.selected == nil or type(record.selected) == "boolean", spec.id .. ": chip selected must be boolean")
            Check(record.icon == nil or (withInput and (IconValue(record.icon) or Name(record.icon))),
                spec.id .. ": chip icon (chipinput only) must be a GUIIcons id, file id or texture path")
            Check(record.spellID == nil or (withInput and Finite(record.spellID)),
                spec.id .. ": chip spellID (chipinput only) must be a number")
            if spec.tristate then
                Check(record.selected == nil, spec.id .. ": tristate chips use state, not selected")
                Check(record.state == nil or TriChip.States[record.state], spec.id .. ": chip state must be nil, \"include\" or \"exclude\"")
                Check(record.tip == nil or type(record.tip) == "string", spec.id .. ": chip tip must be string")
                Check(record.dot == nil or (type(record.dot) == "table" and Finite(record.dot[1]) and Finite(record.dot[2])
                    and Finite(record.dot[3])), spec.id .. ": chip dot must be { r, g, b }")
            else
                Check(record.state == nil and record.dot == nil and record.tip == nil,
                    spec.id .. ": state / dot / tip belong to tristate chips")
            end
        end
        local same = state.records and #state.records == #records
        if same then
            for i, record in ipairs(records) do
                local old = state.records[i]
                if old.record ~= record or old.text ~= record.text or old.selected ~= (record.selected == true)
                    or old.icon ~= record.icon or old.state ~= record.state or old.tip ~= record.tip
                    or old.dot ~= record.dot or old.spellID ~= record.spellID then same = false; break end
            end
        end
        if same then return end
        ReleaseChips(state)
        state.records = {}
        local height = ChipHeight()
        for i, record in ipairs(records) do
            state.records[i] = { record = record, text = record.text, selected = record.selected == true, icon = record.icon,
                state = record.state, tip = record.tip, dot = record.dot, spellID = record.spellID }
            if spec.tristate then
                local chip = TriChip.Acquire(widget, record, session.style, context:Guard(function()
                    session.owner.actions[spec.select](context, record, TriChip.Next[record.state] or (record.state == nil and "include" or nil))
                end))
                state.chips[#state.chips + 1] = { button = chip, tri = true }
            else
            local onClick = spec.select and context:Guard(function()
                session.owner.actions[spec.select](context, record)
            end) or nil
            -- 预设 chipInputNamedMax：超过这个数的带图标标签只显示图标（chipInputFirst 时是先加入的那些）。
            local iconOnly
            if NamedMax() ~= nil and record.icon ~= nil then
                if InputFirst() then iconOnly = i <= #records - NamedMax() else iconOnly = i > NamedMax() end
            end
            local compact = iconOnly and CompactIcon()
            local button = UI:CreateButton(widget, GM.size.buttonMinWidth, height, iconOnly and "" or record.text, onClick,
                { variant = record.selected and "primary" or "secondary", compact = true })
            local chip = { button = button, iconOnly = iconOnly or nil, compact = compact or nil }
            -- 分列带名字的标签：名字只占一行、靠左，放不下省略号截断（归还时恢复换行，按钮池里别的按钮照旧）。
            local label = Columns() and not iconOnly and button:GetFontString() or nil
            if label then
                label:SetWordWrap(false)
                label:SetJustifyH("LEFT")
                chip.oneLine = label
            end
            if record.spellID then
                -- 悬停显示法术提示（池归还时会清 OnEnter / OnLeave，每次借出接一次）。
                local spellID = record.spellID
                button:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetSpellByID(spellID)
                    GameTooltip:Show()
                end)
                button:HookScript("OnLeave", function(self)
                    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                end)
            elseif label then
                -- 没有法术 ID 的分列标签：名字被截断时悬停显示全名。
                local text = record.text
                button:HookScript("OnEnter", function(self)
                    if not label:IsTruncated() then return end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(text, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                button:HookScript("OnLeave", function(self)
                    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                end)
            end
            if spec.remove then
                local hover = HoverRemove()
                local corner = compact or hover
                local size = corner and Part(session.style, "chipCornerRemoveSize") or RemoveSize()
                local GC = _G.ExwindTools.GUIColors
                chip.remove = UI:CreateIconButton(button, size, size, { icon = "x", appearance = "ghost",
                    iconSize = corner and size or math.max(1, size - 6),
                    iconColor = corner and GC.dangerText or nil, hoverIconColor = corner and GC.text or nil,
                    onClick = context:Guard(function(_, mouseButton)
                        if mouseButton == "LeftButton" then session.owner.actions[spec.remove](context, record) end
                    end) })
                if hover then
                    -- 小叉整个落在标签里面（离边 2）：鼠标从小叉移出时先回到标签上，标签的 OnLeave 再收起它。
                    chip.remove:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
                elseif compact then
                    chip.remove:SetPoint("CENTER", button, "TOPRIGHT", -size / 2 + 2, -size / 2 + 2)
                else
                    chip.remove:SetPoint("RIGHT", button, "RIGHT", -2, 0)
                end
                chip.remove:SetFrameLevel(button:GetFrameLevel() + 2)
                if hover then
                    -- 平时隐藏，鼠标在这个标签上（含小叉）才显示（池归还时会清 OnEnter / OnLeave，每次借出接一次）。
                    local remove = chip.remove
                    chip.hoverRemove = true
                    remove:Hide()
                    button:HookScript("OnEnter", function() remove:Show() end)
                    button:HookScript("OnLeave", function(self) if not self:IsMouseOver() then remove:Hide() end end)
                else
                    chip.remove:Show()
                    -- 文字右缘让出 × 的位置（下一次借出按钮时 CreateButton 会重设文字锚点）。
                    local label = button:GetFontString()
                    if label then label:SetPoint("RIGHT", button, "RIGHT", -(size + 2), 0) end
                end
            end
            if record.icon then
                -- 文字前的图标：单独的小框（池化），压在按钮上面；文字左缘让出图标位置。
                local iconSize = compact and math.max(1, height - 2) or IconSize()
                local icon, isNew = Factory:AcquireCompositeHost(CHIP_ICON_POOL, button)
                if isNew then icon.texture = icon:CreateTexture(nil, "ARTWORK"); icon.texture:SetAllPoints(icon) end
                icon:EnableMouse(false)
                icon:SetSize(iconSize, iconSize)
                icon:ClearAllPoints()
                if compact then
                    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
                else
                    icon:SetPoint("LEFT", button, "LEFT", GM.space.compactButtonPaddingX, 0)
                end
                icon:SetFrameLevel(button:GetFrameLevel() + 2)
                SetIconTexture(icon.texture, record.icon)
                icon:Show()
                chip.icon = icon
                local label = button:GetFontString()
                if label then
                    label:SetPoint("LEFT", button, "LEFT",
                        GM.space.compactButtonPaddingX + iconSize + Part(session.style, "chipIconGap"), 0)
                end
            end
            state.chips[#state.chips + 1] = chip
            end
        end
        if spec.add and not withInput then
            local add = UI:CreateButton(widget, height, height, "＋", context:Guard(function()
                session.owner.actions[spec.add](context)
            end), { compact = true })
            state.chips[#state.chips + 1] = { button = add, isAdd = true }
        end
        for _, chip in ipairs(state.chips) do SetChipEnabled(chip, state.enabled) end
    end
    local function ChipWidth(chip)
        if chip.isAdd then return Height() end
        if chip.tri then return chip.button._v2Width end
        if chip.compact then return ChipHeight() end
        -- 悬停才显示的角上小叉压在标签上，不占宽。
        local removeRoom = chip.remove and not chip.hoverRemove
        if chip.iconOnly then
            return GM.space.compactButtonPaddingX + IconSize()
                + (removeRoom and RemoveSize() + 4 or GM.space.compactButtonPaddingX)
        end
        local label = chip.button:GetFontString()
        local text = math.ceil(label and label:GetUnboundedStringWidth() or 0)
        return text + GM.space.compactButtonPaddingX * 2 + (removeRoom and RemoveSize() + 2 or 0)
            + (chip.icon and IconSize() + Part(session.style, "chipIconGap") or 0)
    end
    -- 按宽度流式排列；place=true 时同时摆放。返回总高。chipinput 的输入框排在最后一个标签之后。
    local function Flow(widget, width, place)
        local state = states[widget]
        local height, chipHeight = Height(), ChipHeight()
        local x, y, rowHeight = 0, 0, chipHeight
        local items = #state.chips
        local columns = Columns()
        local columnWidth = columns and math.max(1, (width - CHIP_GAP * (columns - 1)) / columns)
        local named = 0
        -- 预设 chipInputFirst：输入框占最上面一整行，标签从下一行起往下排。
        -- spanRow：设置行给出输入框在行名右边的位置（widget._v2Span），标签从它下面起占满整个宽。
        local span = spec.spanRow and widget._v2Span
        local inputFirst = state.input and (InputFirst() or span)
        if inputFirst then
            local inputX, inputY, inputWidth = 0, 0, width
            if span then inputX, inputY, inputWidth = span.x, span.y, span.width end
            if place then Place(state.input, widget, inputX, inputY, inputWidth, height) end
            if #state.chips == 0 then return inputY + height end
            y = inputY + height + CHIP_GAP
        end
        for _, chip in ipairs(state.chips) do
            local chipWidth = math.min(width, ChipWidth(chip))
            if columns and not chip.iconOnly then
                -- 带名字的标签按列等宽排；排在只有图标的标签后面时另起一行。
                chipWidth = columnWidth
                if (named > 0 and named % columns == 0) or (named == 0 and x > 0) then x, y = 0, y + chipHeight + CHIP_GAP end
                named = named + 1
            elseif columns and chip.iconOnly and named > 0 then
                -- 只有图标的标签从带名字的下面一行开始。
                if x > 0 then x, y = 0, y + chipHeight + CHIP_GAP end
                named = 0
            elseif x > 0 and x + chipWidth > width then x, y = 0, y + chipHeight + CHIP_GAP end
            if place then Place(chip.button, widget, x, y, chipWidth, chipHeight) end
            x = x + chipWidth + CHIP_GAP
        end
        if state.input and not inputFirst then
            local inputWidth = math.min(width, Part(session.style, "chipInputWidth"))
            if x > 0 and x + inputWidth > width then x, y = 0, y + chipHeight + CHIP_GAP end
            -- 预设 chipInputFill：输入框占满所在行剩下的宽。
            if session.style and session.style.chipInputFill then inputWidth = math.max(inputWidth, width - x) end
            if place then Place(state.input, widget, x, y, inputWidth, height) end
            rowHeight = x > 0 and math.max(chipHeight, height) or height
            items = items + 1
        end
        return items > 0 and y + rowHeight or 0
    end
    function adapter.mount(host, context)
        local widget = Factory:AcquireCompositeHost(CHIPS_POOL, host)
        widget:Show()
        states[widget] = { chips = {}, enabled = true, host = host }
        if withInput then
            local input
            input = UI:CreateEditBox(widget, "", Part(session.style, "chipInputWidth"), Height(), nil, {
                placeholder = spec.placeholder, placeholderDim = spec.placeholder ~= nil or nil,
                onEnter = context:Guard(function(text)
                    text = strtrim(tostring(text or ""))
                    input:SetText("")
                    if text == "" then return end
                    -- 加入后把焦点还给输入框，方便连续输入；这一格被页面刷新重建时由 layout 接手。
                    session._v2ChipFocus = spec.id
                    session.owner.actions[spec.add](context, text)
                    local state = states[widget]
                    if state and state.input == input and input:IsVisible() then
                        session._v2ChipFocus = nil
                        input:SetFocus()
                    end
                end),
            })
            if session.style and session.style.overlayControls then UI:SetControlOverlayAppearance(input, true) end
            states[widget].input = input
        end
        Rebuild(widget, context)
        local natural = 0
        for i, chip in ipairs(states[widget].chips) do natural = natural + ChipWidth(chip) + (i > 1 and CHIP_GAP or 0) end
        if withInput then natural = natural + (natural > 0 and CHIP_GAP or 0) + Part(session.style, "chipInputWidth") end
        -- 分列排法（预设 chipInputColumns）：控件区要占满行里标签右边的全部宽，每列各占一半；
        -- 自然宽报成整屏宽（行会给到能给的最大宽），最窄只收到输入框宽。
        if Columns() then natural = math.max(natural, UIParent:GetWidth()) end
        widget._exMinWidth = Columns() and Part(session.style, "chipInputWidth") or nil
        widget:SetWidth(math.max(1, natural))
        return widget
    end
    function adapter.update(widget, context) Rebuild(widget, context) end
    function adapter.measure(widget, context, width) return Flow(widget, width, false) end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        Flow(widget, width, true)
        if state.input and session._v2ChipFocus == spec.id and state.input:IsVisible() then
            session._v2ChipFocus = nil
            state.input:SetFocus()
        end
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        for _, chip in ipairs(state.chips) do SetChipEnabled(chip, enabled) end
        if state.input then ControlDefaults.setEnabled(state.input, context, enabled) end
    end
    function adapter.setVisible(widget, context, visible)
        local input = states[widget] and states[widget].input
        if input and not visible then input:ClearFocus() end
        ControlDefaults.setVisible(widget, context, visible)
    end
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        ReleaseChips(state)
        if state.input then
            state.input:ClearFocus()
            ReleaseBoundWidget(state.input)
        end
        widget._exMinWidth, widget._v2Span = nil, nil
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

-- 可点摘要行（summary）：整行一个按钮，行首可选图标，标题一行 + 摘要灰字（换行），尾部可选编辑、删除图标按钮。
-- 只画自己内部；行在卡片里的位置由 Core 排。
local SUMMARY_POOL = "EXUI.SettingsV2.Summary"
Factory:InitCompositePool(SUMMARY_POOL)

local function NodeText(node, field, sourceField)
    local text = node.spec[field]
    if node.spec[sourceField] then text = node.session.owner.texts[node.spec[sourceField]](node.scope) end
    if text == nil then return "" end
    Check(type(text) == "string", node.spec.id .. ": " .. sourceField .. " must return string")
    return text
end

local function SummaryAdapter(node)
    local spec, session = node.spec, node.session
    local style = session.style
    local states = {}
    local adapter = {}
    local colors = _G.ExwindTools.GUIColors
    local function Paint(widget)
        local state = states[widget]
        local hover = state.enabled and widget.button:IsMouseOver()
        UI:SetControlSurface(widget, GM.radius.control, colors.panel, hover and colors.cardHoverBorder or colors.cardBorder)
        local text = UI.ControlAppearance.colors
        widget.title:SetTextColor(unpack(state.enabled and text.text or text.muted))
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(SUMMARY_POOL, host)
        if isNew then
            widget.button = CreateFrame("Button", nil, widget)
            widget.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            widget.button:SetAllPoints(widget)
            widget.icon = widget:CreateTexture(nil, "ARTWORK")
            widget.title = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlight")
            widget.text = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            for _, label in ipairs({ widget.title, widget.text }) do
                label:SetJustifyH("LEFT")
                label:SetJustifyV("TOP")
                label:SetWordWrap(true)
            end
            widget.button:SetScript("OnEnter", function() local s = widget._v2State; if s then s.paint(widget) end end)
            widget.button:SetScript("OnLeave", function() local s = widget._v2State; if s then s.paint(widget) end end)
            widget.button:SetScript("OnClick", function(_, mouseButton)
                local state = widget._v2State
                if state and state.onClick then state.onClick(widget, mouseButton) end
            end)
        end
        local mutedColor = UI.ControlAppearance.colors.muted
        UI.ControlAppearance.Font(widget.title, Part(style, "summaryTitleFont"), UI.ControlAppearance.colors.text, "", "GameFontHighlight")
        UI.ControlAppearance.Font(widget.text, Part(style, "summaryTextFont"), mutedColor, "", "GameFontHighlightSmall")
        local state = { host = host, enabled = true, buttons = {}, paint = Paint }
        states[widget] = state
        widget._v2State = state -- 池化宿主的脚本只建一次，按本次借用的状态响应
        state.onClick = spec.action and context:Guard(function(_, mouseButton)
            session.owner.actions[spec.action](context, mouseButton)
        end) or nil
        widget.button:SetEnabled(spec.action ~= nil)
        widget.icon:SetShown(spec.icon ~= nil)
        if spec.icon then SetIconTexture(widget.icon, spec.icon) end
        local size = Part(style, "summaryButtonSize")
        for _, field in ipairs({ "edit", "remove" }) do
            if spec[field] then
                local iconButton = UI:CreateIconButton(widget, size, size, { icon = field == "edit" and "pencil-line" or "x",
                    appearance = "ghost", iconSize = Part(style, "summaryButtonIconSize"),
                    onClick = context:Guard(function(_, mouseButton)
                        if mouseButton == "LeftButton" then session.owner.actions[spec[field]](context, mouseButton) end
                    end) })
                iconButton:SetFrameLevel(widget.button:GetFrameLevel() + 2)
                iconButton:Show()
                state.buttons[#state.buttons + 1] = iconButton
            end
        end
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        adapter.update(widget)
        return widget
    end
    function adapter.update(widget)
        widget.title:SetText(NodeText(node, "title", "titleSource"))
        widget.text:SetText(NodeText(node, "text", "textSource"))
        Paint(widget)
    end
    -- 文字区宽 = 行宽 − 左右内距 − 行首图标 − 尾部按钮。
    local function TextWidth(widget, width)
        local state, gap = states[widget], Part(style, "summaryGap")
        local room = width - Part(style, "summaryPaddingX") * 2
        if spec.icon then room = room - Part(style, "summaryIconSize") - gap end
        if #state.buttons > 0 then room = room - #state.buttons * Part(style, "summaryButtonSize") - gap end
        return math.max(1, room)
    end
    function adapter.measure(widget, context, width)
        local textWidth = TextWidth(widget, width)
        widget.title:SetWidth(textWidth)
        widget.text:SetWidth(textWidth)
        local height = math.ceil(widget.title:GetStringHeight())
        if (widget.text:GetText() or "") ~= "" then
            height = height + Part(style, "summaryLineGap") + math.ceil(widget.text:GetStringHeight())
        end
        local padY = Part(style, "summaryPaddingY")
        local floor = math.max(spec.icon and Part(style, "summaryIconSize") or 0,
            #states[widget].buttons > 0 and Part(style, "summaryButtonSize") or 0)
        return math.max(height, floor) + padY * 2
    end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        local padX, padY, gap = Part(style, "summaryPaddingX"), Part(style, "summaryPaddingY"), Part(style, "summaryGap")
        local x = padX
        if spec.icon then
            local size = Part(style, "summaryIconSize")
            widget.icon:ClearAllPoints()
            widget.icon:SetPoint("LEFT", widget, "TOPLEFT", x, -height / 2)
            widget.icon:SetSize(size, size)
            x = x + size + gap
        end
        local textWidth = TextWidth(widget, width)
        widget.title:SetWidth(textWidth)
        widget.text:SetWidth(textWidth)
        local textHeight = math.ceil(widget.title:GetStringHeight())
        local hasText = (widget.text:GetText() or "") ~= ""
        if hasText then textHeight = textHeight + Part(style, "summaryLineGap") + math.ceil(widget.text:GetStringHeight()) end
        local top = math.max(padY, (height - textHeight) / 2)
        widget.title:ClearAllPoints()
        widget.title:SetPoint("TOPLEFT", widget, "TOPLEFT", x, -top)
        widget.text:ClearAllPoints()
        widget.text:SetPoint("TOPLEFT", widget.title, "BOTTOMLEFT", 0, -Part(style, "summaryLineGap"))
        widget.text:SetShown(hasText)
        local right = padX
        for i = #state.buttons, 1, -1 do
            local button = state.buttons[i]
            button:ClearAllPoints()
            button:SetPoint("RIGHT", widget, "TOPRIGHT", -right, -height / 2)
            right = right + button:GetWidth()
        end
        Paint(widget)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        widget.button:SetEnabled(enabled and spec.action ~= nil)
        for _, button in ipairs(state.buttons) do button:SetEnabled(enabled) end
        Paint(widget)
    end
    adapter.setVisible = ControlDefaults.setVisible
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        widget._v2State = nil
        for _, button in ipairs(state.buttons) do button:Release() end
        widget.icon:SetTexture(nil)
        widget.title:SetText("")
        widget.text:SetText("")
        UI:ClearControlSurface(widget)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

-- 句子卡（sentence）：两行，片段流式排开；文字段放不下时按字（西文按词）切开换行。
-- 片段对象（文字、词块、小图标、行首图标块）挂在池化宿主上，按需新建、每次布局按序号复用，用不到的收起。
local SentenceAdapter
do
local SENTENCE_POOL = "EXUI.SettingsV2.Sentence"
Factory:InitCompositePool(SENTENCE_POOL)

local function SentenceIcon(texture, icon, tint)
    SetIconTexture(texture, icon)
    if type(icon) == "string" then texture:SetVertexColor(unpack(tint)) else texture:SetVertexColor(1, 1, 1, 1) end
end

-- 一个 UTF-8 串切成字；西文连续字母算一个“词”单位交给上层按空格回退。
local function Utf8Chars(text)
    local chars = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
    return chars
end

local function ValidateFragments(id, line, field, owner)
    Check(type(line) == "table", id .. ": " .. field .. " must return an array of fragments")
    for key in pairs(line) do
        Check(key == "icon" or (type(key) == "number" and key >= 1 and key % 1 == 0), id .. ": " .. field .. " invalid key " .. tostring(key))
    end
    Check(line.icon == nil or IconValue(line.icon), id .. ": " .. field .. ".icon must be a GUIIcons id or file id")
    for i, part in ipairs(line) do
        local at = id .. ": " .. field .. "[" .. i .. "]"
        Check(type(part) == "table", at .. " must be a table")
        Check((part.text ~= nil) ~= (part.token ~= nil), at .. " needs text or token")
        Check(type(part.text or part.token) == "string", at .. " text/token must be string")
        Check(part.icon == nil or IconValue(part.icon), at .. ".icon must be a GUIIcons id or file id")
        if part.text ~= nil then
            Check(part.action == nil and part.tips == nil, at .. ": action / tips belong to token fragments")
        else
            Check(part.action == nil or (Name(part.action) and type(owner.actions and owner.actions[part.action]) == "function"),
                at .. ".action must name an owner action")
            if part.tips ~= nil then
                Check(type(part.tips) == "table", at .. ".tips must be an array")
                for j, tip in ipairs(part.tips) do
                    local entry = type(tip) == "table" and tip or { text = tip }
                    Check(type(entry.text) == "string", at .. ".tips[" .. j .. "] needs text")
                    Check(entry.icon == nil or IconValue(entry.icon), at .. ".tips[" .. j .. "].icon must be a GUIIcons id or file id")
                    Check(entry.dot == nil or (type(entry.dot) == "table" and Finite(entry.dot[1]) and Finite(entry.dot[2])
                        and Finite(entry.dot[3])), at .. ".tips[" .. j .. "].dot must be { r, g, b }")
                end
            end
        end
    end
end

local function SentenceTips(owner, tips)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    for _, tip in ipairs(tips) do
        local entry = type(tip) == "table" and tip or { text = tip }
        local prefix = ""
        if entry.icon then
            local path = type(entry.icon) == "string" and UI:GetIcon(entry.icon) or entry.icon
            prefix = "|T" .. path .. ":16:16|t "
        elseif entry.dot then
            prefix = string.format("|cff%02x%02x%02x●|r ", entry.dot[1] * 255, entry.dot[2] * 255, entry.dot[3] * 255)
        end
        GameTooltip:AddLine(prefix .. entry.text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function PaintSentenceToken(token)
    local state = token._v2State
    if not state then return end
    local GC = _G.ExwindTools.GUIColors
    local hover = state.enabled and token:IsMouseOver()
    token.label:SetTextColor(unpack(hover and GC.accentHover or (state.emphasis and GC.accentHover or GC.accent)))
    if state.clickable then UI:SetControlSurface(token, 3, GC.checkCardSelected, GC.checkCardSelected) end
end

SentenceAdapter = function(node)
    local spec, session = node.spec, node.session
    local style = session.style
    local states = {}
    local adapter = {}
    local function FontSize() return Part(style, "summaryTextFont") end
    local function LineHeight() return Part(style, "sentenceLineHeight") end
    -- 取第 index 个某类片段对象（没有就建）。
    local function Piece(widget, kind, index)
        local list = widget._v2Pieces[kind]
        local piece = list[index]
        if piece then return piece end
        if kind == "text" then
            piece = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlight")
            piece:SetWordWrap(false)
        elseif kind == "icon" then
            piece = widget:CreateTexture(nil, "ARTWORK")
        elseif kind == "token" then
            piece = CreateFrame("Button", nil, widget)
            piece:RegisterForClicks("LeftButtonUp")
            piece.label = UI:CreateVisualFontString(piece, _G.EXFONTFRAME, "GameFontHighlight")
            piece.label:SetWordWrap(false)
            piece.icon = piece:CreateTexture(nil, "ARTWORK")
            piece.underline = piece:CreateTexture(nil, "ARTWORK")
            piece.underline:SetHeight(1)
            piece:SetScript("OnEnter", function(self)
                PaintSentenceToken(self)
                local state = self._v2State
                if state and state.tips then SentenceTips(self, state.tips) end
            end)
            piece:SetScript("OnLeave", function(self)
                PaintSentenceToken(self)
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
            -- 按下就收起悬停提示（点词会弹小框，提示不能还盖着）。
            piece:SetScript("OnMouseDown", function(self)
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
            piece:SetScript("OnClick", function(self)
                local state = self._v2State
                if state and state.onClick then state.onClick(self) end
            end)
        elseif kind == "head" then
            piece = CreateFrame("Frame", nil, widget)
            piece:EnableMouse(false)
            piece.icon = piece:CreateTexture(nil, "ARTWORK")
            piece.icon:SetPoint("CENTER")
        end
        list[index] = piece
        return piece
    end
    -- 文字最长能放进 room 的前缀（按字二分；西文优先退到空格）；返回 前缀, 剩余。
    local function Fit(widget, text, room)
        local measure = widget._v2Measure
        measure:SetText(text)
        if measure:GetUnboundedStringWidth() <= room then return text, "" end
        local chars = Utf8Chars(text)
        local low, high = 0, #chars
        while low < high do
            local mid = math.floor((low + high + 1) / 2)
            measure:SetText(table.concat(chars, "", 1, mid))
            if measure:GetUnboundedStringWidth() <= room then low = mid else high = mid - 1 end
        end
        if low > 0 and low < #chars and chars[low + 1] ~= " " then
            for i = low, 1, -1 do
                if chars[i] == " " then low = i; break end
            end
        end
        return table.concat(chars, "", 1, low), table.concat(chars, "", low + 1)
    end
    -- 按宽度排一行片段；place 为真时同时摆放。返回这一行占了几行高。
    local function FlowLine(widget, line, top, left, width, rightReserve, place, counters)
        local fragmentIcon, gapIcon = Part(style, "sentenceFragmentIconSize"), Part(style, "sentenceIconGap")
        local tokenPadX = Part(style, "sentenceTokenPadX")
        local lineHeight = LineHeight()
        local x, rows = left, 1
        local function Room() return width - (rows == 1 and rightReserve or 0) - x end
        local function NewRow() rows, x = rows + 1, left end
        local function Y() return top + (rows - 1) * lineHeight end
        for _, part in ipairs(line) do
            if part.token then
                local measure = widget._v2Measure
                measure:SetText(part.token)
                local w = math.ceil(measure:GetUnboundedStringWidth()) + (part.icon and fragmentIcon + gapIcon or 0)
                local clickable = part.action ~= nil
                if clickable then w = w + tokenPadX * 2 end
                if x > left and w > Room() then NewRow() end
                if place then
                    counters.token = counters.token + 1
                    local token = Piece(widget, "token", counters.token)
                    local height = clickable and math.min(lineHeight, FontSize() + Part(style, "sentenceTokenPadY") * 2) or lineHeight
                    Place(token, widget, x, Y() + (lineHeight - height) / 2, w, height)
                    UI.ControlAppearance.Font(token.label, FontSize(), UI.ControlAppearance.colors.text, "", "GameFontHighlight")
                    token.label:SetText(part.token)
                    token.label:ClearAllPoints()
                    local inner = clickable and tokenPadX or 0
                    if part.icon then
                        token.icon:SetSize(fragmentIcon, fragmentIcon)
                        token.icon:ClearAllPoints()
                        token.icon:SetPoint("LEFT", token, "LEFT", inner, 0)
                        SentenceIcon(token.icon, part.icon, _G.ExwindTools.GUIColors.accent)
                        token.icon:Show()
                        token.label:SetPoint("LEFT", token.icon, "RIGHT", gapIcon, 0)
                    else
                        token.icon:Hide()
                        token.label:SetPoint("LEFT", token, "LEFT", inner, 0)
                    end
                    local underline = part.tips ~= nil and not clickable
                    token.underline:SetShown(underline)
                    if underline then
                        token.underline:SetColorTexture(unpack(_G.ExwindTools.GUIColors.accent))
                        token.underline:ClearAllPoints()
                        token.underline:SetPoint("TOPLEFT", token.label, "BOTTOMLEFT", 0, -Part(style, "sentenceUnderlineOffset") + 2)
                        token.underline:SetPoint("TOPRIGHT", token.label, "BOTTOMRIGHT", 0, -Part(style, "sentenceUnderlineOffset") + 2)
                    end
                    if not clickable then UI:ClearControlSurface(token) end
                    token._v2State = { clickable = clickable, emphasis = not clickable and part.tips == nil, tips = part.tips,
                        enabled = states[widget].enabled,
                        onClick = clickable and states[widget].context:Guard(function(frame)
                            session.owner.actions[part.action](states[widget].context, part, frame)
                        end) or nil }
                    token:EnableMouse(clickable or part.tips ~= nil)
                    token:SetFrameLevel(widget:GetFrameLevel() + 2)
                    token:Show()
                    PaintSentenceToken(token)
                end
                x = x + w
            else
                if part.icon then
                    if x > left and fragmentIcon > Room() then NewRow() end
                    if place then
                        counters.icon = counters.icon + 1
                        local icon = Piece(widget, "icon", counters.icon)
                        icon:SetSize(fragmentIcon, fragmentIcon)
                        icon:ClearAllPoints()
                        icon:SetPoint("LEFT", widget, "TOPLEFT", x, -(Y() + lineHeight / 2))
                        SentenceIcon(icon, part.icon, UI.ControlAppearance.colors.text)
                        icon:Show()
                    end
                    x = x + fragmentIcon + gapIcon
                end
                local rest = part.text
                while rest ~= "" do
                    local head, tail = Fit(widget, rest, math.max(0, Room()))
                    if head == "" then
                        if x > left then NewRow() head, tail = Fit(widget, rest, math.max(0, Room())) end
                        if head == "" then head = Utf8Chars(rest)[1]; tail = rest:sub(#head + 1) end -- 整行放不下一个字：放一个字
                    end
                    local measure = widget._v2Measure
                    measure:SetText(head)
                    local w = math.ceil(measure:GetUnboundedStringWidth())
                    if place then
                        counters.text = counters.text + 1
                        local label = Piece(widget, "text", counters.text)
                        UI.ControlAppearance.Font(label, FontSize(), UI.ControlAppearance.colors.text, "", "GameFontHighlight")
                        label:SetTextColor(unpack(states[widget].enabled and UI.ControlAppearance.colors.text or UI.ControlAppearance.colors.muted))
                        label:SetText(head)
                        label:ClearAllPoints()
                        label:SetPoint("LEFT", widget, "TOPLEFT", x, -(Y() + lineHeight / 2))
                        label:Show()
                    end
                    x = x + w
                    rest = tail
                    if rest ~= "" then NewRow() end
                end
            end
        end
        return rows
    end
    -- 整张卡排一遍；返回总高。
    local function Arrange(widget, width, place)
        local state = states[widget]
        local padX, padY, gap = Part(style, "summaryPaddingX"), Part(style, "sentencePaddingY"), Part(style, "sentenceLineGap")
        local lineHeight = LineHeight()
        local counters = { text = 0, icon = 0, token = 0, head = 0 }
        local inner = math.max(1, width - padX * 2)
        local reserve = #state.buttons > 0 and (#state.buttons * Part(style, "summaryButtonSize") + Part(style, "summaryGap")) or 0
        local y = padY
        local lines = { state.line1, state.line2 }
        for index, line in ipairs(lines) do
            if line then
                if index == 2 then y = y + gap end
                local left = padX
                if line.icon then
                    local size = Part(style, "summaryIconSize")
                    if place then
                        counters.head = counters.head + 1
                        local head = Piece(widget, "head", counters.head)
                        Place(head, widget, padX, y + (lineHeight - size) / 2, size, size)
                        UI:SetControlSurface(head, 6, _G.ExwindTools.GUIColors.checkCardSelected, _G.ExwindTools.GUIColors.checkCardSelected)
                        local iconSize = Part(style, "summaryButtonIconSize")
                        if type(line.icon) == "string" then head.icon:SetSize(iconSize, iconSize) else head.icon:SetSize(size, size) end
                        SentenceIcon(head.icon, line.icon, _G.ExwindTools.GUIColors.accent)
                        head:SetFrameLevel(widget:GetFrameLevel() + 1)
                        head:Show()
                    end
                    left = padX + size + Part(style, "summaryGap")
                end
                local rows = FlowLine(widget, line, y, left, padX + inner, index == 1 and reserve or 0, place, counters)
                y = y + rows * lineHeight
            end
        end
        if place then
            for kind, used in pairs(counters) do
                local list = widget._v2Pieces[kind]
                for i = used + 1, #list do
                    local piece = list[i]
                    piece:Hide()
                    if kind == "token" then piece._v2State = nil end
                end
            end
        end
        return y + padY
    end
    local function Paint(widget)
        local state = states[widget]
        local GC = _G.ExwindTools.GUIColors
        local radius = style.cardRadius or GM.radius.card
        UI:SetControlSurface(widget, radius, style.cardFill or GC.card,
            state.selected and GC.transparent or (style.cardBorder or GC.cardBorder))
        UI:PaintSelectCell(widget, state.selected, radius)
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(SENTENCE_POOL, host)
        if isNew then
            widget._v2Pieces = { text = {}, icon = {}, token = {}, head = {} }
            widget._v2Measure = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlight")
            widget._v2Measure:Hide()
        end
        UI.ControlAppearance.Font(widget._v2Measure, FontSize(), UI.ControlAppearance.colors.text, "", "GameFontHighlight")
        local state = { host = host, context = context, enabled = true, buttons = {} }
        states[widget] = state
        local size = Part(style, "summaryButtonSize")
        for _, field in ipairs({ "edit", "remove" }) do
            if spec[field] then
                local button = UI:CreateIconButton(widget, size, size, { icon = field == "edit" and "pencil-line" or "trash-2",
                    appearance = "ghost", iconSize = Part(style, "summaryButtonIconSize"),
                    hoverIconColor = field == "remove" and _G.ExwindTools.GUIColors.dangerText or nil,
                    onClick = context:Guard(function(_, mouseButton)
                        if mouseButton == "LeftButton" then session.owner.actions[spec[field]](context, mouseButton) end
                    end) })
                button:SetFrameLevel(widget:GetFrameLevel() + 3)
                button:Show()
                state.buttons[#state.buttons + 1] = button
            end
        end
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        adapter.update(widget, context)
        return widget
    end
    function adapter.update(widget, context)
        local state = states[widget]
        state.line1 = session.owner.sources[spec.lineSource](node.scope)
        ValidateFragments(spec.id, state.line1, "lineSource", session.owner)
        state.line2 = nil
        if spec.line2Source then
            state.line2 = session.owner.sources[spec.line2Source](node.scope)
            ValidateFragments(spec.id, state.line2, "line2Source", session.owner)
        end
        state.selected = false
        if spec.selected then
            state.selected = session.owner.predicates[spec.selected](node.scope)
            Check(type(state.selected) == "boolean", spec.id .. ": predicate must return ordinary boolean")
        end
        Paint(widget)
    end
    function adapter.measure(widget, context, width) return Arrange(widget, width, false) end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        Arrange(widget, width, true)
        local inset, right = Part(style, "sentenceButtonInset"), 0
        for i = #state.buttons, 1, -1 do
            local button = state.buttons[i]
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -(inset + right), -inset)
            right = right + button:GetWidth() + 2
        end
        Paint(widget)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        for _, button in ipairs(state.buttons) do button:SetEnabled(enabled) end
        for _, token in ipairs(widget._v2Pieces.token) do
            if token._v2State then token._v2State.enabled = enabled; PaintSentenceToken(token) end
        end
    end
    adapter.setVisible = ControlDefaults.setVisible
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        for _, button in ipairs(state.buttons) do button:Release() end
        for kind, list in pairs(widget._v2Pieces) do
            for _, piece in ipairs(list) do
                piece:Hide()
                if kind == "token" then
                    if GameTooltip:GetOwner() == piece then GameTooltip:Hide() end
                    piece._v2State = nil
                    UI:ClearControlSurface(piece)
                    piece.label:SetText("")
                    piece.icon:SetTexture(nil)
                elseif kind == "head" then
                    UI:ClearControlSurface(piece)
                    piece.icon:SetTexture(nil)
                elseif kind == "text" then
                    piece:SetText("")
                else
                    piece:SetTexture(nil)
                end
            end
        end
        UI:ClearControlSurface(widget)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

end

-- 小字键值区（props）：每行 键名 + 无框值框（悬停显框、聚焦描主色边），可带框后图标按钮；多行项平时显示一行灰字，
-- 点进去换成多行编辑框并把这一行撑高。值框是这里自己建的 EditBox（池化宿主上按项序号复用）。
local PropsAdapter
do
local PROPS_POOL = "EXUI.SettingsV2.Props"
Factory:InitCompositePool(PROPS_POOL)

local function PaintPropsValue(value)
    local GC = _G.ExwindTools.GUIColors
    local box = value.box
    local focused = box:HasFocus()
    local hover = value._v2Enabled and value:IsMouseOver()
    if value._v2Boxed then
        -- 预设 propsValueBoxed：值框平时就画成同面板输入框（控件底 + 输入框边、圆角同输入框），悬停、聚焦换边色。
        local border = focused and GC.inputFocusBorder or (hover and GC.inputHoverBorder or GC.inputBorder)
        UI:SetControlSurface(value, GM.radius.control, GC.input, border)
    else
        local border = focused and GC.inputFocusBorder or (hover and GC.inputBorder or GC.transparent)
        UI:SetControlSurface(value, 3, focused and GC.input or GC.transparent, border)
    end
    -- 多行项平时显示的是第一行预览；内容为空时预览没字，照样显示占位字。
    local filled = (box:GetText() or "") ~= ""
    value.placeholder:SetShown(not focused and not filled)
    -- prefixIcon 项：前缀图标空时同占位色、有值变亮；框内右侧按钮只在有值时显示。
    if value.prefixIcon:IsShown() then
        value.prefixIcon:SetVertexColor(unpack(filled and GC.textDim or GC.textPlaceholder))
    end
    if value._v2Inline then value._v2Inline:SetShown(filled) end
end

PropsAdapter = function(node)
    local spec, session = node.spec, node.session
    local style = session.style
    local states = {}
    local adapter = {}
    local function NewValue(widget)
        local value = CreateFrame("Frame", nil, widget)
        -- 值框装在滚动框里：单行项框与值框同大；多行项只定宽、高随文字，超过框高（propsMultilineHeight）时框内滚动。
        value.scroll = CreateFrame("ScrollFrame", nil, value)
        value.scroll:SetAllPoints(value)
        value.scroll:EnableMouse(false)
        value.scroll:EnableMouseWheel(false)
        value.box = CreateFrame("EditBox", nil, value.scroll)
        value.box:SetAutoFocus(false)
        value.box:SetFontObject("GameFontHighlightSmall")
        value.scroll:SetScrollChild(value.box)
        value.scroll:SetScript("OnMouseDown", function() if value.box:IsShown() then value.box:SetFocus() end end)
        value.scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            if range <= 0 then UI:ForwardInputMouseWheel(value, delta) return end
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * Part(style, "propsValueHeight"))))
        end)
        value.box:SetScript("OnCursorChanged", function(self, _, y, _, height)
            if not self:IsMultiLine() then return end
            -- 按整行滚，框顶不切半行；_v2TopInset 是文字上下内距（布局时记下）。
            UI:ScrollMultilineToCursor(value.scroll, y, height, value._v2TopInset)
        end)
        value.placeholder = UI:CreateVisualFontString(value, _G.EXFONTFRAME, "GameFontHighlightSmall")
        value.placeholder:SetJustifyH("LEFT")
        value.placeholder:SetWordWrap(false)
        value.preview = CreateFrame("Button", nil, value)
        value.preview:SetAllPoints(value)
        value.preview.label = UI:CreateVisualFontString(value.preview, _G.EXFONTFRAME, "GameFontHighlightSmall")
        value.preview.label:SetJustifyH("LEFT")
        value.preview.label:SetWordWrap(false)
        value.preview:Hide()
        value.prefixIcon = value:CreateTexture(nil, "OVERLAY")
        value.prefixIcon:Hide()
        -- clampLines 项右下角的“展开 / 收起”。
        value.more = CreateFrame("Button", nil, value)
        value.more.label = UI:CreateVisualFontString(value.more, _G.EXFONTFRAME, "GameFontHighlightSmall")
        value.more.label:SetPoint("RIGHT", value.more, "RIGHT", 0, 0)
        value.more:SetFrameLevel(value.preview:GetFrameLevel() + 2)
        value.more:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(_G.ExwindTools.GUIColors.accentHover)) end)
        value.more:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(_G.ExwindTools.GUIColors.accent)) end)
        value.more:SetScript("OnClick", function() if value._v2OnMore then value._v2OnMore() end end)
        value.more:Hide()
        local function Repaint() PaintPropsValue(value) end
        value.box:SetScript("OnEnter", Repaint)
        value.box:SetScript("OnLeave", Repaint)
        value.preview:SetScript("OnEnter", Repaint)
        value.preview:SetScript("OnLeave", Repaint)
        value.scroll:SetScript("OnEnter", Repaint)
        value.scroll:SetScript("OnLeave", Repaint)
        value.box:SetScript("OnEditFocusGained", function() Repaint(); if value._v2OnFocus then value._v2OnFocus(true) end end)
        value.box:SetScript("OnEditFocusLost", function()
            if value._v2OnFocus then value._v2OnFocus(false) end
            Repaint()
        end)
        value.box:SetScript("OnEnterPressed", function(self)
            if self:IsMultiLine() then self:Insert("\n") else self:ClearFocus() end
        end)
        value.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        value.box:SetScript("OnTextChanged", function()
            Repaint()
            if value._v2OnText then value._v2OnText() end
        end)
        value.preview:SetScript("OnClick", function()
            if value._v2OnOpen then value._v2OnOpen() end
        end)
        return value
    end
    -- clampLines 项：量文字在给定宽下的高（空文字按一行算）。
    local function TextHeight(widget, text, textWidth)
        local measure = widget._v2MeasureText
        measure:SetWidth(math.max(1, textWidth))
        measure:SetText(text ~= "" and text or " ")
        return measure:GetStringHeight()
    end
    -- clampLines 项的框高：平时最多 N 行（至少 N 行高），展开或正在改时随全文。
    -- 顺带记下是否超过 N 行（entry.overflow）和文字右边给“展开 / 收起”让出的宽（entry.moreRoom）。
    local function ClampHeight(widget, entry, valueWidth)
        local padY = Part(style, "propsClampPadY")
        local textWidth = valueWidth - Part(style, "propsValueInset") * 2
        local text = entry.value.box:GetText() or ""
        local minHeight = TextHeight(widget, string.rep("A", entry.item.clampLines, "\n"), textWidth)
        local full = TextHeight(widget, text, textWidth)
        entry.moreRoom = 0
        if entry.expanded then
            entry.overflow = false
            return math.max(minHeight, full) + padY * 2
        end
        entry.overflow = full > minHeight + 0.5
        if not entry.overflow then return minHeight + padY * 2 end
        entry.value.more.label:SetText(_G.ExwindTools.L[entry.open and "收起" or "展开"])
        entry.moreRoom = math.ceil(entry.value.more.label:GetUnboundedStringWidth()) + Part(style, "propsMoreGap")
        if not entry.open then return minHeight + padY * 2 end
        return math.max(minHeight, TextHeight(widget, text, textWidth - entry.moreRoom)) + padY * 2
    end
    -- 把每一项排进行里；place 为真时摆放。返回总高。
    local function Arrange(widget, width, place)
        local state = states[widget]
        local padX, padTop, padBottom = Part(style, "propsPaddingX"), Part(style, "propsPaddingTop"), Part(style, "propsPaddingBottom")
        local rowHeight, valueHeight = Part(style, "propsRowHeight"), Part(style, "propsValueHeight")
        local keyWidth, gap = Part(style, "propsKeyWidth"), Part(style, "propsGap")
        local inset = Part(style, "propsValueInset")
        local measure = widget._v2Measure
        local y = padTop
        for _, row in ipairs(state.rows) do
            -- 键名列：第一项固定宽，第二项按字宽（左右再留 propsSecondKeyLeft / Right）；没写 label 的项没有键名列。
            local fixed = 0
            for j, entry in ipairs(row) do
                local item = entry.item
                if item.size == "short" then fixed = fixed + Part(style, item.prefixIcon and "propsPrefixShortWidth" or "propsShortWidth") end
                if entry.trailing and not item.prefixIcon then fixed = fixed + entry.trailing:GetWidth() + gap end
                if not item.label then
                    entry.keyWidth = 0
                elseif j > 1 then
                    measure:SetText(item.label)
                    entry.keyWidth = math.ceil(measure:GetUnboundedStringWidth()) + Part(style, "propsSecondKeyLeft") + Part(style, "propsSecondKeyRight")
                else
                    entry.keyWidth, entry.first = keyWidth, true
                end
                if item.label then fixed = fixed + entry.keyWidth + gap end
                -- 两项之间的间距也算进去，否则两项行的右缘比单项行多出一个间距。
                if j > 1 then fixed = fixed + gap end
            end
            local flexCount = 0
            for _, entry in ipairs(row) do if entry.item.size ~= "short" then flexCount = flexCount + 1 end end
            local flexWidth = math.max(1, (width - padX * 2 - fixed) / math.max(1, flexCount))
            local height = rowHeight
            for _, entry in ipairs(row) do
                local item = entry.item
                entry.valueWidth = item.size == "short"
                    and Part(style, item.prefixIcon and "propsPrefixShortWidth" or "propsShortWidth") or flexWidth
                if item.clampLines then
                    entry.boxHeight = ClampHeight(widget, entry, entry.valueWidth)
                elseif item.multiline and (entry.expanded or style.propsMultilineFixed) then
                    entry.boxHeight = Part(style, "propsMultilineHeight")
                else
                    entry.boxHeight = valueHeight
                end
                height = math.max(height, entry.boxHeight + rowHeight - valueHeight)
            end
            if place then
                local x = padX
                for _, entry in ipairs(row) do
                    local item, value = entry.item, entry.value
                    entry.key:ClearAllPoints()
                    entry.key:SetShown(item.label ~= nil)
                    if item.label then
                        entry.key:SetPoint("TOPLEFT", widget, "TOPLEFT", x + (entry.first and Part(style, "propsKeyInset") or Part(style, "propsSecondKeyLeft")),
                            -(y + (rowHeight - valueHeight) / 2))
                        entry.key:SetHeight(valueHeight)
                        x = x + entry.keyWidth + gap
                    end
                    local valueWidth, boxHeight = entry.valueWidth, entry.boxHeight
                    Place(value, widget, x, y + (rowHeight - valueHeight) / 2, valueWidth, boxHeight)
                    if item.multiline then
                        value.box:SetWidth(valueWidth) -- 高随文字，超出框高在滚动框里滚
                    else
                        value.box:SetSize(valueWidth, boxHeight)
                    end
                    -- 多行框（固定高或 clampLines）：文字和占位字从框顶开始（上下留同样的内距）。
                    local topInset = 0
                    if item.clampLines then topInset = Part(style, "propsClampPadY")
                    elseif item.multiline and style.propsMultilineFixed then topInset = inset end
                    -- prefixIcon 项：左边让出前缀图标，右边让出框内按钮。
                    local left, right = inset, inset
                    if item.prefixIcon then
                        local size = Part(style, "propsPrefixIconSize")
                        left = Part(style, "propsPrefixWidth")
                        value.prefixIcon:SetSize(size, size)
                        value.prefixIcon:ClearAllPoints()
                        value.prefixIcon:SetPoint("LEFT", value, "LEFT", Part(style, "propsPrefixInset"), 0)
                        if entry.trailing then
                            right = Part(style, "propsInlineButtonInset") + entry.trailing:GetWidth()
                            entry.trailing:ClearAllPoints()
                            entry.trailing:SetPoint("RIGHT", value, "RIGHT", -Part(style, "propsInlineButtonInset"), 0)
                        end
                    end
                    value.box:SetTextInsets(left, right, topInset, topInset)
                    value._v2TopInset = topInset
                    value.placeholder:ClearAllPoints()
                    if topInset > 0 then
                        value.placeholder:SetPoint("TOPLEFT", value, "TOPLEFT", left, -topInset)
                        value.placeholder:SetPoint("TOPRIGHT", value, "TOPRIGHT", -right, -topInset)
                    else
                        value.placeholder:SetPoint("LEFT", value, "LEFT", left, 0)
                        -- 占位字不越出值框：右缘同样内缩，放不下单行截断。
                        value.placeholder:SetPoint("RIGHT", value, "RIGHT", -right, 0)
                    end
                    value.preview.label:ClearAllPoints()
                    if item.clampLines then
                        -- 平时显示全文、最多 N 行（展开后不限）；超过 N 行时右下角出“展开 / 收起”。
                        value.preview.label:SetPoint("TOPLEFT", value, "TOPLEFT", inset, -topInset)
                        value.preview.label:SetPoint("TOPRIGHT", value, "TOPRIGHT", -(inset + entry.moreRoom), -topInset)
                        value.preview.label:SetMaxLines(entry.open and 0 or item.clampLines)
                        value.preview.label:SetText(value.box:GetText() or "")
                        local showMore = entry.overflow and not entry.expanded
                        value.more:SetShown(showMore)
                        if showMore then
                            local labelWidth = math.ceil(value.more.label:GetUnboundedStringWidth())
                            local lineHeight = TextHeight(widget, "A", valueWidth)
                            value.more:SetSize(labelWidth, lineHeight)
                            value.more:ClearAllPoints()
                            value.more:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", -inset, topInset)
                        end
                    else
                        value.preview.label:SetPoint("LEFT", value, "LEFT", inset, 0)
                        value.preview.label:SetPoint("RIGHT", value, "RIGHT", -inset, 0)
                    end
                    x = x + valueWidth
                    if entry.trailing and not item.prefixIcon then
                        entry.trailing:ClearAllPoints()
                        entry.trailing:SetPoint("LEFT", widget, "TOPLEFT", x + gap, -(y + rowHeight / 2))
                        x = x + gap + entry.trailing:GetWidth()
                    end
                    x = x + gap
                    PaintPropsValue(value)
                end
            end
            y = y + height
        end
        return y + padBottom
    end
    local function Sync(entry)
        local text = entry.binding:Read()
        text = text == nil and "" or tostring(text)
        if not entry.value.box:HasFocus() then entry.value.box:SetText(text) end
        local clamp = entry.item.clampLines ~= nil
        if entry.item.multiline and style.propsMultilineFixed and not clamp then entry.expanded = true end
        if entry.item.multiline then
            -- clampLines 项预览全文（最多 N 行由排版定），其余多行项只预览第一行。
            entry.value.preview.label:SetText(clamp and entry.value.box:GetText() or (text:gsub("\n.*", "")))
            entry.value.preview:SetShown(not entry.expanded)
            entry.value.box:SetShown(entry.expanded == true)
            entry.value.scroll:EnableMouse(entry.expanded == true)
            entry.value.scroll:EnableMouseWheel(entry.expanded == true)
            if not entry.expanded then entry.value.scroll:SetVerticalScroll(0) end
        end
        PaintPropsValue(entry.value)
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(PROPS_POOL, host)
        if isNew then
            widget._v2Values = {}
            widget._v2Keys = {}
            widget._v2Measure = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._v2Measure:Hide()
            widget._v2MeasureText = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._v2MeasureText:SetWordWrap(true)
            widget._v2MeasureText:SetNonSpaceWrap(true)
            widget._v2MeasureText:Hide()
        end
        local GC, colors = _G.ExwindTools.GUIColors, UI.ControlAppearance.colors
        local font = Part(style, "propsFont")
        -- 预设 propsKeyRole / propsValueRole：键名、值框按标准文字角色（同面板其他行的行名、输入框字号与颜色），
        -- 占位字用占位色；没写时照小字灰字。
        local keyRole, valueRole = style.propsKeyRole, style.propsValueRole
        local function KeyFont(region)
            if keyRole then UI.ControlAppearance.ApplyTextRole(region, keyRole)
            else UI.ControlAppearance.Font(region, font, GC.textPlaceholder, "", "GameFontHighlightSmall") end
        end
        local function ValueFont(region, color)
            if valueRole then UI.ControlAppearance.ApplyTextRole(region, valueRole, color)
            else UI.ControlAppearance.Font(region, font, color, "", "GameFontHighlightSmall") end
        end
        KeyFont(widget._v2Measure)
        ValueFont(widget._v2MeasureText, colors.text)
        local binding = session.owner.binding
        local state = { host = host, rows = {}, buttons = {}, context = context }
        states[widget] = state
        local index = 0
        for r, row in ipairs(spec.rows) do
            state.rows[r] = {}
            for j, item in ipairs(row) do
                index = index + 1
                local key = widget._v2Keys[index]
                if not key then
                    key = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
                    key:SetJustifyH("LEFT")
                    key:SetJustifyV("MIDDLE")
                    key:SetWordWrap(false)
                    widget._v2Keys[index] = key
                end
                KeyFont(key)
                key:SetText(item.label or "")
                key:SetShown(item.label ~= nil)
                local value = widget._v2Values[index] or NewValue(widget)
                widget._v2Values[index] = value
                value._v2Enabled = true
                value._v2Boxed = style and style.propsValueBoxed == true or false
                value.box:SetMultiLine(item.multiline == true)
                value.scroll:EnableMouse(false)
                value.scroll:EnableMouseWheel(false)
                value.scroll:SetVerticalScroll(0)
                ValueFont(value.box, colors.text)
                ValueFont(value.placeholder, GC.textPlaceholder)
                ValueFont(value.preview.label, valueRole and colors.text or GC.textDim)
                value.placeholder:SetText(item.placeholder or "")
                -- clampLines 项预览换行、最多 N 行；其余多行项预览一行截断。
                local clamp = item.clampLines ~= nil
                value.placeholder:SetWordWrap(clamp)
                value.placeholder:SetNonSpaceWrap(clamp)
                value.preview.label:SetWordWrap(clamp)
                value.preview.label:SetNonSpaceWrap(clamp)
                value.preview.label:SetJustifyV(clamp and "TOP" or "MIDDLE")
                value.preview.label:SetMaxLines(item.clampLines or 0)
                ValueFont(value.more.label, GC.accent)
                value.more:Hide()
                value.prefixIcon:SetShown(item.prefixIcon ~= nil)
                if item.prefixIcon then value.prefixIcon:SetTexture(UI:GetIcon(item.prefixIcon)) end
                value.box:SetShown(not item.multiline)
                value:Show()
                local entry = { item = item, key = key, value = value, open = false,
                    binding = CreateBinding(binding.moduleKey, binding.config, item.path) }
                local function Commit()
                    if not context:IsCurrent() then return end
                    local text = value.box:GetText() or ""
                    local old = entry.binding:Read()
                    if (old == nil and text == "") or old == text then return end
                    entry.binding:Write(text, "commit")
                    context:RefreshPage()
                end
                value._v2OnFocus = function(gained)
                    if gained then return end
                    Commit()
                    if item.multiline and entry.expanded and (clamp or not style.propsMultilineFixed) then
                        entry.expanded = false
                        Sync(entry)
                        context:Invalidate()
                    end
                end
                value._v2OnOpen = item.multiline and context:Guard(function()
                    entry.expanded = true
                    Sync(entry)
                    value.box:SetFocus()
                    value.box:SetCursorPosition(#(value.box:GetText() or ""))
                    context:Invalidate()
                end) or nil
                -- clampLines 项：展开 / 收起换高度；正在改时文字行数变了就重排（框高随全文）。
                value._v2OnMore = clamp and context:Guard(function()
                    entry.open = not entry.open
                    context:Invalidate()
                end) or nil
                value._v2OnText = clamp and function()
                    if not (entry.expanded and entry.valueWidth and context:IsCurrent()) then return end
                    if ClampHeight(widget, entry, entry.valueWidth) ~= entry.boxHeight then context:Invalidate() end
                end or nil
                if item.trailingIcon then
                    -- prefixIcon 项：按钮在框内右侧、只在有值时显示；其余项在框后。
                    local inline = item.prefixIcon ~= nil
                    local parent = inline and value or widget
                    local size = Part(style, inline and "propsInlineButtonSize" or "propsButtonSize")
                    entry.trailing = UI:CreateIconButton(parent, size, size, { icon = item.trailingIcon, appearance = "ghost",
                        iconSize = Part(style, "propsButtonIconSize"),
                        iconColor = inline and GC.textPlaceholder or GC.accent, hoverIconColor = inline and GC.accent or GC.accentHover,
                        onClick = context:Guard(function(_, mouseButton)
                            session.owner.actions[item.trailingAction](context, mouseButton, value.box:GetText() or "", function()
                                value.box:SetFocus()
                                value.box:HighlightText()
                            end)
                        end) })
                    entry.trailing:SetFrameLevel(parent:GetFrameLevel() + 3)
                    entry.trailing:Show()
                    value._v2Inline = inline and entry.trailing or nil
                    state.buttons[#state.buttons + 1] = entry.trailing
                end
                state.rows[r][j] = entry
                Sync(entry)
            end
        end
        state.used = index
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        return widget
    end
    function adapter.update(widget)
        for _, row in ipairs(states[widget].rows) do
            for _, entry in ipairs(row) do Sync(entry) end
        end
    end
    function adapter.measure(widget, context, width) return Arrange(widget, width, false) end
    function adapter.layout(widget, context, width, height)
        Place(widget, states[widget].host, 0, 0, width, height)
        Arrange(widget, width, true)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        for _, row in ipairs(state.rows) do
            for _, entry in ipairs(row) do
                entry.value._v2Enabled = enabled
                entry.value.box:SetEnabled(enabled)
                entry.value.preview:SetEnabled(enabled)
                if not enabled then entry.value.box:ClearFocus() end
                PaintPropsValue(entry.value)
            end
        end
        for _, button in ipairs(state.buttons) do button:SetEnabled(enabled) end
    end
    function adapter.setVisible(widget, context, visible)
        if not visible then
            for _, row in ipairs(states[widget].rows) do
                for _, entry in ipairs(row) do entry.value.box:ClearFocus() end
            end
        end
        widget:SetShown(visible)
    end
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        for _, button in ipairs(state.buttons) do button:Release() end
        for i, value in ipairs(widget._v2Values) do
            value._v2OnFocus, value._v2OnOpen, value._v2Enabled = nil, nil, nil
            value._v2OnMore, value._v2OnText, value._v2Inline = nil, nil, nil
            value.more:Hide()
            value.prefixIcon:Hide()
            value.box:ClearFocus()
            value.box:SetText("")
            value.box:SetEnabled(true)
            value.preview:SetEnabled(true)
            value.preview:Hide()
            value.preview.label:SetText("")
            value.placeholder:SetText("")
            UI:ClearControlSurface(value)
            value:Hide()
            widget._v2Keys[i]:SetText("")
            widget._v2Keys[i]:Hide()
        end
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

end

-- 预览卡网格（catalog）：一组可选卡片，每张 = 预览区（图标，或 owner 绘制回调画的缩略预览）+ 名字。
-- 每行张数按宽度算（不小于 catalogCardMinWidth，多出的宽平分），卡片位置由 Core 排，绘制回调只画预览区内部。
-- catalogLabelLines（预设可覆盖，默认 1）> 1 时名字放不下换行、最多这么多行，每排卡高按这一排名字最多的行数算。
local CATALOG_POOL, CATALOG_CARD_POOL = "EXUI.SettingsV2.Catalog", "EXUI.SettingsV2.CatalogCard"
Factory:InitCompositePool(CATALOG_POOL)
Factory:InitCompositePool(CATALOG_CARD_POOL)

local function PaintCatalogCard(card)
    local state = card._v2State
    if not state then return end
    local colors = _G.ExwindTools.GUIColors
    local hover = state.enabled and card.button:IsMouseOver()
    local text = UI.ControlAppearance.colors
    if state.tile then
        UI:PaintCheckCardSurface(card, state.selected, hover, state.enabled, GM.radius.popup)
        UI:PaintSelectCell(card, false)
        card.label:SetTextColor(unpack(state.enabled and text.text or text.muted))
        local alpha = state.enabled and 1 or 0.6
        if state.dim then
            alpha = card.button:IsMouseOver() and GM.settings.parts.catalogDimHoverAlpha or GM.settings.parts.catalogDimAlpha
        end
        card:SetAlpha(alpha)
        return
    end
    if card._v2CornerCheck then card._v2CornerCheck.clip:Hide() end
    if state.entry then
        -- 入口卡：卡底 + 细边，悬停边变亮，选中走公共选中外观；图标主色。
        local border = state.selected and colors.transparent or (hover and colors.cardHoverBorder or colors.cardBorder)
        UI:SetControlSurface(card, GM.radius.card, colors.card, border)
        UI:PaintSelectCell(card, state.selected, GM.radius.card)
        card.label:SetTextColor(unpack(state.enabled and text.text or text.muted))
        if state.tintIcon then card.icon:SetVertexColor(unpack(colors.accent)) end
        card:SetAlpha(state.enabled and 1 or 0.6)
        return
    end
    local border = state.selected and colors.transparent or (hover and colors.cardHoverBorder or colors.cardBorder)
    UI:SetControlSurface(card, GM.radius.control, colors.panel, border)
    UI:PaintSelectCell(card, state.selected, GM.radius.control)
    card.label:SetTextColor(unpack(state.enabled and text.text or text.muted))
    -- 记录 dim：变暗（悬停时亮一点），悬停预览照常。
    local alpha = state.enabled and 1 or 0.6
    if state.dim then
        alpha = card.button:IsMouseOver() and GM.settings.parts.catalogDimHoverAlpha or GM.settings.parts.catalogDimAlpha
    end
    card:SetAlpha(alpha)
end

local function CatalogAdapter(node)
    local spec, session = node.spec, node.session
    local style = session.style
    local entry = spec.presentation == "entry"
    local tile = spec.presentation == "tile"
    -- 方格卡尺寸档：size = "large" 换成 catalogTileLarge*，其余同普通方格卡。
    local large = spec.size == "large"
    local TILE_WIDTH = large and "catalogTileLargeWidth" or "catalogTileWidth"
    local TILE_ICON = large and "catalogTileLargeIcon" or "catalogTileIcon"
    local TILE_RADIUS = large and "catalogTileLargeIconRadius" or "catalogTileIconRadius"
    local TILE_PAD_Y = large and "catalogTileLargePadY" or "catalogTilePadY"
    local LABEL_FONT = large and "catalogTileLargeFont" or "catalogLabelFont"
    local labelLines = (entry or tile) and 1 or Part(style, "catalogLabelLines")
    local states = {}
    local adapter = {}
    local function ReleaseCards(state)
        for _, card in ipairs(state.cards) do
            if card._v2State.cleanup then card._v2State.cleanup() end
            card._v2State = nil
            card.icon:SetTexture(nil)
            card.icon:SetVertexColor(1, 1, 1, 1)
            if card.rounded then card.rounded:SetTexture(nil); card.rounded:Hide() end
            card.icon:SetParent(card.canvas)
            card.icon:ClearAllPoints()
            card.icon:SetPoint("CENTER")
            card.canvas:Show()
            card.label:SetText("")
            UI:ClearControlSurface(card)
            card:SetAlpha(1)
            Factory:ReleaseCompositeHost(card)
        end
        state.cards = {}
    end
    local function Rebuild(widget, context)
        local state = states[widget]
        local records = Records(node)
        for _, record in ipairs(records) do
            Check(type(record.text) == "string", spec.id .. ": catalog text must be string")
            Check(record.selected == nil or type(record.selected) == "boolean", spec.id .. ": catalog selected must be boolean")
            Check(record.icon == nil or IconValue(record.icon), spec.id .. ": catalog icon must be a GUIIcons id or file id")
            Check(record.dim == nil or type(record.dim) == "boolean", spec.id .. ": catalog dim must be boolean")
            Check(record.tip == nil or type(record.tip) == "string", spec.id .. ": catalog tip must be string")
            Check(record.coords == nil or (tile and type(record.coords) == "table" and #record.coords == 4),
                spec.id .. ": catalog coords must be { left, right, top, bottom } on tile cards")
        end
        local same = state.records and #state.records == #records
        if same then
            for i, record in ipairs(records) do
                local old = state.records[i]
                if old.record ~= record or old.text ~= record.text or old.icon ~= record.icon
                    or old.selected ~= (record.selected == true) or old.dim ~= (record.dim == true)
                    or old.tip ~= record.tip or old.coords ~= (record.coords and table.concat(record.coords, ",")) then
                    same = false; break
                end
            end
        end
        if same then return end
        ReleaseCards(state)
        state.records = {}
        for i, record in ipairs(records) do
            state.records[i] = { record = record, text = record.text, icon = record.icon, selected = record.selected == true,
                dim = record.dim == true, tip = record.tip, coords = record.coords and table.concat(record.coords, ",") }
            local card, isNew = Factory:AcquireCompositeHost(CATALOG_CARD_POOL, widget)
            if isNew then
                card.canvas = CreateFrame("Frame", nil, card)
                card.icon = card.canvas:CreateTexture(nil, "ARTWORK")
                card.icon:SetPoint("CENTER")
                card.label = UI:CreateVisualFontString(card, _G.EXFONTFRAME, "GameFontHighlightSmall")
                card.label:SetJustifyH("CENTER")
                card.label:SetWordWrap(false)
                card.button = CreateFrame("Button", nil, card)
                card.button:SetAllPoints(card)
                card.button:RegisterForClicks("LeftButtonUp")
                card.button:SetScript("OnEnter", function(button)
                    PaintCatalogCard(card)
                    local cardState = card._v2State
                    if not cardState then return end
                    if cardState.tip then
                        GameTooltip:SetOwner(button, "ANCHOR_TOP")
                        GameTooltip:AddLine(cardState.tip, 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                    if cardState.onHover then cardState.onHover(true) end
                end)
                card.button:SetScript("OnLeave", function(button)
                    PaintCatalogCard(card)
                    if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
                    local cardState = card._v2State
                    if cardState and cardState.onHover then cardState.onHover(false) end
                end)
                card.button:SetScript("OnClick", function(_, mouseButton)
                    local cardState = card._v2State
                    if cardState and cardState.onClick then cardState.onClick(card, mouseButton) end
                end)
            end
            card.button:SetFrameLevel(card:GetFrameLevel() + 3)
            UI.ControlAppearance.Font(card.label, Part(style, entry and "entryLabelFont" or LABEL_FONT),
                UI.ControlAppearance.colors.text, "", "GameFontHighlightSmall")
            card.label:SetText(record.text)
            card.label:SetWordWrap(labelLines > 1)
            if labelLines > 1 then card.label:SetMaxLines(labelLines) end
            local iconSize = Part(style, entry and "entryIconSize" or (tile and TILE_ICON or "catalogIconSize"))
            card.icon:SetSize(iconSize, iconSize)
            -- 方格卡里材质文件 ID 的图标：Core 圆角图像（圆角按样式 catalogTileIconRadius），裁掉四边各 8% 的自带黑边、铺满图标区。
            local roundIcon = tile and record.icon ~= nil and not spec.paint and type(record.icon) ~= "string"
            if roundIcon and not card.rounded then
                card.rounded = UI:CreateRoundedImage(card.canvas, GM.radius.popup)
                card.rounded:SetAllPoints(card.canvas)
            end
            if card.rounded then card.rounded:SetShown(roundIcon) end
            if roundIcon then
                card.rounded:SetCornerRadius(Part(style, TILE_RADIUS))
                card.rounded:SetTexture(record.icon)
                local c = record.coords or { .08, .92, .08, .92 }
                card.rounded:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            card.icon:SetShown(record.icon ~= nil and not spec.paint and not roundIcon)
            if record.icon and not spec.paint and not roundIcon then SetIconTexture(card.icon, record.icon) end
            if entry then
                -- 入口卡不用预览区：图标直接挂在卡上靠左，名字跟在图标右边。
                card.canvas:Hide()
                card.icon:SetParent(card)
                card.icon:ClearAllPoints()
                card.icon:SetPoint("LEFT", card, "LEFT", Part(style, "entryPaddingX"), 0)
                card.label:SetJustifyH("LEFT")
            else
                card.label:SetJustifyH("CENTER")
            end
            local cardState = { selected = record.selected == true, enabled = state.enabled, entry = entry, tile = tile,
                tintIcon = entry and type(record.icon) == "string", dim = record.dim == true, tip = record.tip }
            cardState.onClick = spec.select and not cardState.dim and context:Guard(function()
                session.owner.actions[spec.select](context, record)
            end) or nil
            if spec.hover then
                local canvas = card.canvas
                cardState.onHover = context:Guard(function(entering)
                    session.owner.painters[spec.hover](canvas, record, entering, context)
                end)
            end
            card._v2State = cardState
            card.button:SetEnabled(state.enabled)
            if spec.paint then
                local cleanup = session.owner.painters[spec.paint](card.canvas, record, context)
                Check(cleanup == nil or type(cleanup) == "function", spec.id .. ": painter returns nil or a cleanup function")
                cardState.cleanup = cleanup
            end
            card:Show()
            PaintCatalogCard(card)
            state.cards[i] = card
        end
    end
    -- 每行张数与卡宽：至少一张，卡宽不小于 catalogCardMinWidth（行太窄时一张占满）。
    local function Grid(width, count)
        if tile then
            -- 方格卡：卡宽固定，每行最多 catalogTileColumns 张，靠左排。
            local tileWidth, gap = Part(style, TILE_WIDTH), Part(style, "catalogTileGap")
            local fit = math.max(1, math.floor((width + gap) / (tileWidth + gap)))
            return math.min(fit, Part(style, "catalogTileColumns")), math.min(tileWidth, width), gap
        end
        local minWidth, gap = Part(style, entry and "entryMinWidth" or "catalogCardMinWidth"), Part(style, entry and "entryGap" or "catalogGap")
        local columns = math.max(1, math.floor((width + gap) / (minWidth + gap)))
        -- 入口卡：卡片少于能放的列数时平分整行（两张就各占一半）。
        if entry then columns = math.max(1, math.min(columns, count)) end
        return columns, (width - gap * (columns - 1)) / columns, gap
    end
    local function CardHeight(widget)
        if entry then return Part(style, "entryHeight") end
        local lineHeight = select(2, widget._v2LabelFont:GetFont()) or Part(style, LABEL_FONT)
        if tile then
            return Part(style, TILE_PAD_Y) * 2 + Part(style, TILE_ICON) + Part(style, "catalogLabelGap")
                + math.ceil(lineHeight)
        end
        return Part(style, "catalogPadding") * 2 + Part(style, "catalogPreviewHeight") + Part(style, "catalogLabelGap") + math.ceil(lineHeight)
    end
    -- 每排卡高：名字只占一行时都是 CardHeight；可换行时按这一排名字最多占几行（用隐藏的量字串按卡内宽量）。
    local function RowHeights(widget, width)
        local state = states[widget]
        local count = #state.cards
        local columns, cardWidth, gap = Grid(width, count)
        local base, heights = CardHeight(widget), {}
        local lineHeight = select(2, widget._v2LabelFont:GetFont()) or Part(style, "catalogLabelFont")
        local font = widget._v2LabelFont
        if labelLines > 1 then
            font:SetWordWrap(true)
            font:SetWidth(math.max(1, cardWidth - Part(style, "catalogPadding") * 2))
        end
        for i = 1, count do
            local row = math.floor((i - 1) / columns) + 1
            local height = base
            if labelLines > 1 then
                font:SetText(state.records[i].text)
                local lines = math.min(labelLines, math.max(1, math.floor(font:GetStringHeight() / lineHeight + 0.5)))
                height = base + math.ceil(lineHeight * lines) - math.ceil(lineHeight)
            end
            heights[row] = math.max(heights[row] or 0, height)
        end
        return heights, columns, cardWidth, gap
    end
    -- 网格上方的小标题行（spec.title / description）：高 = 字高 + catalogHeadingGap；没写就是 0。
    local heading = spec.title ~= nil or spec.description ~= nil
    local function HeadingHeight(widget)
        if not heading then return 0 end
        return math.ceil(select(2, widget._v2HeadTitle:GetFont()) or Part(style, "catalogHeadingFont"))
            + Part(style, "catalogHeadingGap")
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(CATALOG_POOL, host)
        if isNew then
            widget._v2LabelFont = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._v2HeadTitle = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._v2HeadNote = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._v2HeadTitle:SetWordWrap(false)
            widget._v2HeadNote:SetWordWrap(false)
            widget._v2HeadNote:SetJustifyH("LEFT")
        end
        widget._v2LabelFont:Hide()
        local colors = _G.ExwindTools.GUIColors
        UI.ControlAppearance.Font(widget._v2HeadTitle, Part(style, "catalogHeadingFont"), colors.textDim, "", "GameFontHighlightSmall")
        UI.ControlAppearance.Font(widget._v2HeadNote, Part(style, "catalogHeadingFont"), colors.textPlaceholder, "",
            "GameFontHighlightSmall")
        widget._v2HeadTitle:SetText(spec.title or "")
        widget._v2HeadNote:SetText(spec.description or "")
        widget._v2HeadTitle:SetShown(heading)
        widget._v2HeadNote:SetShown(heading)
        UI.ControlAppearance.Font(widget._v2LabelFont, Part(style, LABEL_FONT), UI.ControlAppearance.colors.text, "", "GameFontHighlightSmall")
        states[widget] = { cards = {}, enabled = true, host = host }
        widget:Show()
        Rebuild(widget, context)
        local count = math.max(1, #states[widget].cards)
        widget:SetWidth(count * Part(style, tile and TILE_WIDTH or "catalogCardMinWidth")
            + (count - 1) * Part(style, tile and "catalogTileGap" or "catalogGap"))
        return widget
    end
    function adapter.update(widget, context) Rebuild(widget, context) end
    function adapter.measure(widget, context, width)
        if #states[widget].cards == 0 then return 0 end
        local heights, _, _, gap = RowHeights(widget, width)
        local total = (#heights - 1) * gap + HeadingHeight(widget)
        for _, height in ipairs(heights) do total = total + height end
        return total
    end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        local heights, columns, cardWidth, gap = RowHeights(widget, width)
        local pad = Part(style, "catalogPadding")
        local previewHeight = Part(style, "catalogPreviewHeight")
        local tops, top = {}, HeadingHeight(widget)
        if heading then
            local title, note = widget._v2HeadTitle, widget._v2HeadNote
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", widget, "TOPLEFT", Part(style, "catalogHeadingInset"), 0)
            note:ClearAllPoints()
            note:SetPoint("LEFT", title, "RIGHT", (spec.title or "") ~= "" and Part(style, "catalogHeadingNoteGap") or 0, 0)
            note:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
        end
        for row, rowHeight in ipairs(heights) do tops[row] = top; top = top + rowHeight + gap end
        for i, card in ipairs(state.cards) do
            local column, row = (i - 1) % columns, math.floor((i - 1) / columns) + 1
            Place(card, widget, column * (cardWidth + gap), tops[row], cardWidth, heights[row])
            card.label:ClearAllPoints()
            if tile then
                local icon, padY = Part(style, TILE_ICON), Part(style, TILE_PAD_Y)
                local labelTop = -(padY + icon + Part(style, "catalogLabelGap"))
                Place(card.canvas, card, (cardWidth - icon) / 2, padY, icon, icon)
                card.label:SetPoint("TOPLEFT", card, "TOPLEFT", 2, labelTop)
                card.label:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, labelTop)
            elseif entry then
                local padX = Part(style, "entryPaddingX")
                local left = card.icon:IsShown() and (padX + Part(style, "entryIconSize") + Part(style, "entryIconGap")) or padX
                card.label:SetPoint("LEFT", card, "LEFT", left, 0)
                card.label:SetPoint("RIGHT", card, "RIGHT", -padX, 0)
            else
                Place(card.canvas, card, pad, pad, cardWidth - pad * 2, previewHeight)
                card.label:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -(pad + previewHeight + Part(style, "catalogLabelGap")))
                card.label:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -(pad + previewHeight + Part(style, "catalogLabelGap")))
            end
            PaintCatalogCard(card)
        end
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        for _, card in ipairs(state.cards) do
            card._v2State.enabled = enabled
            card.button:SetEnabled(enabled)
            PaintCatalogCard(card)
        end
    end
    adapter.setVisible = ControlDefaults.setVisible
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        ReleaseCards(state)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

-- 可复制网址框（url）与行内提示条（notice）：文字来自 text 或 texts[textSource](scope)，每次刷新重读。
local URL_POOL, NOTICE_POOL = "EXUI.SettingsV2.Url", "EXUI.SettingsV2.Notice"
Factory:InitCompositePool(URL_POOL)
Factory:InitCompositePool(NOTICE_POOL)

local function UrlAdapter(node)
    local states = {}
    local adapter = {}
    local function Sync(widget)
        local state = states[widget]
        local text = NodeText(node, "text", "textSource")
        if text == state.text then return end
        if state.box then UI:ReleaseCopyableUrlBox(state.box); state.box = nil end
        state.text = text
        if text ~= "" then
            state.box = UI:CreateCopyableUrlBox(widget, text, Part(node.session.style, "urlWidth"))
            state.box:Show()
        end
    end
    function adapter.mount(host, context)
        local widget = Factory:AcquireCompositeHost(URL_POOL, host)
        states[widget] = { host = host }
        widget:SetSize(Part(node.session.style, "urlWidth"), GM.size.inputHeight)
        widget:Show()
        Sync(widget)
        return widget
    end
    function adapter.update(widget) Sync(widget) end
    function adapter.measure(widget) return states[widget].box and states[widget].box:GetHeight() or 0 end
    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        Place(widget, state.host, 0, 0, width, height)
        if state.box then Place(state.box, widget, 0, 0, width, height) end
    end
    function adapter.setEnabled() end -- 只读框，停用时照样可以复制
    function adapter.setVisible(widget, context, visible)
        local box = states[widget] and states[widget].box
        if box and not visible then (box.editBox or box):ClearFocus() end
        widget:SetShown(visible)
    end
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        if state.box then UI:ReleaseCopyableUrlBox(state.box) end
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

local NoticeTones = { info = "Info", ok = "Ok", error = "Err" }

local function NoticeAdapter(node)
    local spec, style = node.spec, node.session.style
    local states = {}
    local adapter = {}
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(NOTICE_POOL, host)
        if isNew then
            widget.label = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget.label:SetJustifyH("LEFT")
            widget.label:SetJustifyV("TOP")
            widget.label:SetWordWrap(true)
        end
        local colors, tone = _G.ExwindTools.GUIColors, NoticeTones[spec.tone or "info"]
        UI:SetControlSurface(widget, GM.radius.control, colors["status" .. tone .. "Tint"], colors["status" .. tone .. "Border"])
        UI.ControlAppearance.Font(widget.label, Part(style, "noticeFont"), UI.ControlAppearance.colors.text, "", "GameFontHighlightSmall")
        states[widget] = { host = host }
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        adapter.update(widget)
        return widget
    end
    function adapter.update(widget) widget.label:SetText(NodeText(node, "text", "textSource")) end
    function adapter.measure(widget, context, width)
        if (widget.label:GetText() or "") == "" then return 0 end
        widget.label:SetWidth(math.max(1, width - Part(style, "noticePaddingX") * 2))
        return math.ceil(widget.label:GetStringHeight()) + Part(style, "noticePaddingY") * 2
    end
    function adapter.layout(widget, context, width, height)
        Place(widget, states[widget].host, 0, 0, width, height)
        widget.label:ClearAllPoints()
        widget.label:SetPoint("TOPLEFT", widget, "TOPLEFT", Part(style, "noticePaddingX"), -Part(style, "noticePaddingY"))
        widget.label:SetWidth(math.max(1, width - Part(style, "noticePaddingX") * 2))
        if height <= 0 then widget:Hide() end -- 没有文字时不画空条
    end
    function adapter.setEnabled() end -- 提示条只显示文字
    adapter.setVisible = ControlDefaults.setVisible
    function adapter.release(widget)
        states[widget] = nil
        widget.label:SetText("")
        UI:ClearControlSurface(widget)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

-- 分组多选列表（picklist，过滤面板）：顶上一行搜索框 + “已选 n/m”，下面按 pickColumns 栏排分组，
-- 每组标题 + 一列勾选项；分组按高度依次放进当前最矮的一栏。搜索只筛显示，不改记录。
local PICK_POOL = "EXUI.SettingsV2.PickList"
Factory:InitCompositePool(PICK_POOL)

local function PickListAdapter(node)
    local spec, session = node.spec, node.session
    local style = session.style
    local states = {}
    local adapter = {}
    local function ReadGroups()
        local groups = Records(node)
        local seen = {}
        for _, group in ipairs(groups) do
            Check(type(group.title) == "string", spec.id .. ": picklist group title must be string")
            Check(type(group.items) == "table", spec.id .. ": picklist group items must be an array")
            for _, item in ipairs(group.items) do
                Check(type(item) == "table" and not seen[item], spec.id .. ": picklist items must be unique tables")
                seen[item] = true
                Check(type(item.text) == "string", spec.id .. ": picklist item text must be string")
                Check(item.selected == nil or type(item.selected) == "boolean", spec.id .. ": picklist selected must be boolean")
            end
        end
        return groups
    end
    local function ReleaseEntries(state)
        for _, group in ipairs(state.groups) do
            for _, entry in ipairs(group.entries) do ReleaseBoundWidget(entry.box) end
        end
        state.groups = {}
        for _, title in ipairs(state.widget._v2Titles) do title:Hide(); title:SetText("") end
    end
    local function Rebuild(widget, context)
        local state = states[widget]
        local groups = ReadGroups()
        -- 结构（分组、记录、文字）没变时只同步勾选，不重建（点击勾选项的回调里会刷新整页）。
        local same = #state.groups == #groups
        for g = 1, same and #groups or 0 do
            local old, group = state.groups[g], groups[g]
            if old.title ~= group.title or #old.entries ~= #group.items then same = false; break end
            for i, item in ipairs(group.items) do
                if old.entries[i].item ~= item or old.entries[i].text ~= item.text then same = false; break end
            end
            if not same then break end
        end
        if same then
            for _, group in ipairs(state.groups) do
                for _, entry in ipairs(group.entries) do
                    entry.box:SetChecked(entry.item.selected == true)
                    UI:ApplyControlAppearance(entry.box)
                end
            end
            return
        end
        ReleaseEntries(state)
        local titles = widget._v2Titles
        for g, group in ipairs(groups) do
            if not titles[g] then
                titles[g] = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlight")
                titles[g]:SetJustifyH("LEFT")
                titles[g]:SetWordWrap(false)
            end
            UI.ControlAppearance.Font(titles[g], Part(style, "pickGroupFont"), UI.ControlAppearance.colors.text, "", "GameFontHighlight")
            titles[g]:SetText(group.title)
            local entries = {}
            for i, item in ipairs(group.items) do
                local box = UI:CreateCheckbox(widget, item.text, item.selected == true, context:Guard(function(checked)
                    session.owner.actions[spec.toggle](context, item, checked == true)
                end))
                entries[i] = { item = item, text = item.text, box = box }
                if not state.enabled then ControlDefaults.setEnabled(box, context, false) end
            end
            state.groups[g] = { title = group.title, entries = entries, label = titles[g] }
        end
    end
    local function Matches(state, entry)
        return state.filter == "" or entry.text:lower():find(state.filter, 1, true) ~= nil
    end
    -- 排版：返回总高；place=true 时同时摆放（不匹配搜索的项与没有可见项的组隐藏）。
    local function Arrange(widget, width, place)
        local state = states[widget]
        local headerHeight = StyledControlHeight(style)
        local columns = math.max(1, Part(style, "pickColumns"))
        local columnGap, rowHeight = Part(style, "pickColumnGap"), Part(style, "pickRowHeight")
        local columnWidth = math.max(1, (width - columnGap * (columns - 1)) / columns)
        local top = headerHeight + Part(style, "pickHeaderGap")
        local heights, total, selected = {}, 0, 0
        for c = 1, columns do heights[c] = 0 end
        for _, group in ipairs(state.groups) do
            local shown = {}
            for _, entry in ipairs(group.entries) do
                total = total + 1
                if entry.item.selected then selected = selected + 1 end
                if Matches(state, entry) then shown[#shown + 1] = entry
                elseif place then entry.box:Hide() end
            end
            if #shown == 0 then
                if place then group.label:Hide() end
            else
                local column = 1
                for c = 2, columns do if heights[c] < heights[column] then column = c end end
                local y = top + heights[column] + (heights[column] > 0 and Part(style, "pickGroupGap") or 0)
                local x = (column - 1) * (columnWidth + columnGap)
                local titleHeight = math.ceil(select(2, group.label:GetFont()) or Part(style, "pickGroupFont"))
                if place then
                    group.label:ClearAllPoints()
                    group.label:SetPoint("TOPLEFT", widget, "TOPLEFT", x, -y)
                    group.label:SetWidth(columnWidth)
                    group.label:Show()
                end
                y = y + titleHeight + Part(style, "pickTitleGap")
                for _, entry in ipairs(shown) do
                    if place then
                        Place(entry.box, widget, x, y, columnWidth, rowHeight)
                        entry.box:Show()
                    end
                    y = y + rowHeight
                end
                heights[column] = y - top
            end
        end
        if place then
            local count = widget._v2Count
            count:SetText(string.format(_G.ExwindTools.L["已选 %d/%d"], selected, total))
            count:ClearAllPoints()
            count:SetPoint("RIGHT", widget, "TOPRIGHT", 0, -headerHeight / 2)
            Place(state.search, widget, 0, 0, math.min(width, Part(style, "pickSearchWidth")), headerHeight)
        end
        local tallest = 0
        for c = 1, columns do tallest = math.max(tallest, heights[c]) end
        return tallest > 0 and top + tallest or headerHeight
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(PICK_POOL, host)
        if isNew then
            widget._v2Titles = {}
            widget._v2Count = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._v2Count:SetJustifyH("RIGHT")
        end
        UI.ControlAppearance.Font(widget._v2Count, Part(style, "pickCountFont"), UI.ControlAppearance.colors.muted, "", "GameFontHighlightSmall")
        widget._v2Count:Show()
        local state = { host = host, widget = widget, groups = {}, enabled = true, filter = "" }
        states[widget] = state
        state.search = UI:CreateEditBox(widget, "", Part(style, "pickSearchWidth"), StyledControlHeight(style), nil, {
            placeholder = spec.placeholder or _G.ExwindTools.L["搜索..."], placeholderDim = true,
            onChanged = function(text)
                if not context:IsCurrent() then return end
                state.filter = strtrim(tostring(text or "")):lower()
                context:Invalidate()
            end,
        })
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        Rebuild(widget, context)
        return widget
    end
    function adapter.update(widget, context) Rebuild(widget, context) end
    function adapter.measure(widget, context, width) return Arrange(widget, width, false) end
    function adapter.layout(widget, context, width, height)
        Place(widget, states[widget].host, 0, 0, width, height)
        Arrange(widget, width, true)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        ControlDefaults.setEnabled(state.search, context, enabled)
        for _, group in ipairs(state.groups) do
            for _, entry in ipairs(group.entries) do ControlDefaults.setEnabled(entry.box, context, enabled) end
        end
    end
    function adapter.setVisible(widget, context, visible)
        if not visible then states[widget].search:ClearFocus() end
        widget:SetShown(visible)
    end
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        ReleaseEntries(state)
        state.search:ClearFocus()
        ReleaseBoundWidget(state.search)
        widget._v2Count:SetText("")
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

-- 内容自己画的种类：节点种类 → 适配器工厂（mount/update/measure/layout/setEnabled/setVisible/release）。
local PartAdapters = { chips = ChipsAdapter, chipinput = ChipsAdapter, summary = SummaryAdapter, catalog = CatalogAdapter,
    url = UrlAdapter, notice = NoticeAdapter, picklist = PickListAdapter, sentence = SentenceAdapter, props = PropsAdapter,
    -- 图标选取的实现在 ExwindIconPick.lua（本文件之后加载），这里只把要用的内部函数交给它。
    iconpick = function(node)
        return UI._SettingsV2IconPickAdapter(node, { Part = Part, Records = Records, Place = Place, Check = Check })
    end,
    -- 材质预览、材质网格的实现在 ExwindTexturePick.lua（本文件之后加载）。
    texturepreview = function(node)
        return UI._SettingsV2TexturePreviewAdapter(node, { Part = Part, Place = Place, Check = Check })
    end,
    texturegrid = function(node)
        return UI._SettingsV2TextureGridAdapter(node, { Part = Part, Place = Place, Check = Check })
    end }

Build = function(session, spec, parentFrame, scope, parent)
    local node = { session=session, spec=spec, scope=scope, parent=parent, alive=true, generation=1, children={} }
    local list = parent and parent.children or session.nodes
    list[#list + 1] = node
    MountNode(node, parentFrame)
    return node
end

MountNode = function(node, parentFrame)
    local session, spec, scope = node.session, node.spec, node.scope
    node.alive = true
    if spec.kind == "card" then
        node.frame = UI:CreateSettingsCard(parentFrame, spec)
        UI:PrepareSettingsListCard(node.frame, {
            preserveHeader=true, externalCollapsible=spec.collapsible == true, collapsed=spec.collapsed,
        })
        CardAccessories(node.frame)
        if node.frame._v2BodyScroll then node.frame._v2BodyScroll:Hide() end
        if node.frame._v2LegendBacking then node.frame._v2LegendBacking:Hide() end
        if spec.titlePosition == "legend" then
            local colors = _G.ExwindTools.GUIColors
            UI:SetControlSurface(node.frame, GM.radius.card, colors.panel, colors.cardBorder)
            local surface = node.frame._exModernSurfaces and node.frame._exModernSurfaces[GM.radius.card]
            for _, piece in ipairs(surface and surface.pieces or {}) do piece.texture:SetAlpha(1) end
            UI:ClearControlSurface(node.frame:GetBody())
        end
        if spec.surface == "none" then
            UI:ClearControlSurface(node.frame)
            UI:ClearControlSurface(node.frame:GetBody())
            UI:ClearControlSurface(node.frame._exSettingsCardHeader)
        end
        node.frame._v2Help._v2Text = spec.help
        -- 样式附件每次借出都先收起；只有样式页再按预设画（清掉卡片与正文表面，标题区改画圆角条）。
        local card = node.frame
        if card._v2StyleBar then
            card._v2StyleBar:Hide()
            card._v2StyleNote:Hide()
            card._v2StyleNote:SetText("")
            card._v2StyleAdd:Hide()
            card._v2StyleAdd._v2OnClick = nil
        end
        local style = session.style
        if style then
            StyleAccessories(card)
            UI:ClearControlSurface(card)
            UI:ClearControlSurface(card:GetBody())
            UI:ClearControlSurface(card._exSettingsCardHeader)
            UI:SetControlSurface(card._v2StyleBar, style.headerRadius, style.headerFill, _G.ExwindTools.GUIColors.transparent) -- 标题条不画边
            local colors = UI.ControlAppearance.colors
            card._exSettingsListExternalHeader.titleColor = style.headerText or colors.text
            card._exSettingsListExternalHeader.glyphColor = colors.text
            card._exSettingsCardPaintHeader()
        end
        if spec.bodyHeight then
            local scrollFrame = node.frame._v2BodyScroll
            if not scrollFrame then
                scrollFrame = UI:CreateScrollFrame(node.frame:GetBody())
                -- The native scroll child stays with this pooled card. Only the
                -- declaration content beneath it is leased and released.
                local content = CreateFrame("Frame", nil, scrollFrame)
                content:SetSize(1, 1)
                scrollFrame:SetScrollChild(content)
                scrollFrame._v2Content = content
                node.frame._v2BodyScroll = scrollFrame
            end
            node.scrollFrame = scrollFrame
            node.body = Acquire(scrollFrame._v2Content)
            node.body:SetPoint("TOPLEFT")
            node.body:SetPoint("TOPRIGHT")
            scrollFrame:SetVerticalScroll(0)
            scrollFrame:Show()
        else
            node.body = Acquire(node.frame:GetBody())
            PixelUtil.SetPoint(node.body, "TOPLEFT", node.frame:GetBody(), "TOPLEFT", PAD, -PAD, 0, 0)
            PixelUtil.SetPoint(node.body, "TOPRIGHT", node.frame:GetBody(), "TOPRIGHT", -PAD, -PAD, 0, 0)
        end
        node.headerPoints = {}
        for i = 1, node.frame._exSettingsCardHeader:GetNumPoints() do
            node.headerPoints[i] = { node.frame._exSettingsCardHeader:GetPoint(i) }
        end
        if spec.collapsible then
            node.toggleFont = { node.frame._exSettingsCardToggle._exGlyph:GetFont() }
            node.toggleSize = { node.frame._exSettingsCardToggle:GetSize() }
        end
        node.frame:SetLayoutInvalidationHandler(function(card)
            if spec.collapsible then
                card._exSettingsCardToggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
                -- page.collapse：用户点了标题，新状态交给 owner 记。
                if session.collapse and node.context and node.context:IsCurrent() then
                    session.owner.actions[session.collapse.toggle](node.context, spec.id, card._exSettingsCardCollapsed == true)
                end
            end
            session:Refresh()
        end)
        if spec.collapsible and session.collapse then
            local collapsed = CollapseState(node)
            if collapsed ~= nil then node.frame:SetCollapsed(collapsed, true) end
        end
    else
        node.frame = Acquire(parentFrame)
        node.body = node.frame
        if spec.kind == "setting" then
            -- 标签、说明与分隔线由共享设置行画；右侧子节点挂在独立的控件区里。
            local style = session.style
            local trailingWidth = (spec.help or spec.helpSource) and (style.helpIconSize + STYLE_HELP_GAP) or 0
            -- 预设 triLabelAbove：行里只有三态小标签（过滤类名 + 一串标签）时一律类名在上、标签在下，
            -- 不按放不放得下各自决定，各类排法统一。
            local triOnly = style and style.triLabelAbove and spec.label ~= nil and spec.children and #spec.children > 0
            for _, child in ipairs(triOnly and spec.children or {}) do
                if not (child.kind == "chips" and child.tristate) then triOnly = false end
            end
            node.settingRow = UI:CreateSettingsRow(node.frame, { label = spec.label, description = spec.description,
                lead = spec.toggle and "checkbox" or (spec.icon and "icon") or nil, icon = spec.icon, style = style,
                stacked = triOnly or nil,
                autoWidth = style and style.settingAutoWidth or nil, -- 预设 settingAutoWidth：setting 行文字列自适应
                trailingWidth = trailingWidth > 0 and trailingWidth or nil })
            if spec.help or spec.helpSource then
                -- 标签后的小问号（校验保证只出现在样式页）；挂在本节点宿主上，宿主借出时 Acquire 会收起。
                if not node.frame._v2RowHelp then node.frame._v2RowHelp = HelpGlyph(node.frame, style.helpIconSize) end
                node.rowHelp = node.frame._v2RowHelp
                node.rowHelp:SetSize(style.helpIconSize, style.helpIconSize)
                node.rowHelp._v2Text = spec.help
                node.rowHelp._v2TextFn = spec.helpSource and function() return session.owner.texts[spec.helpSource](scope) end or nil
                node.rowHelp:Show()
            end
            node.body = Acquire(node.frame)
            if spec.toggle then
                -- 勾选框写原有 enabled 字段；没勾时右侧控件由 RefreshNode 统一变灰。
                local binding = session.owner.binding
                node.toggleBinding = CreateBinding(binding.moduleKey, binding.config, Session._rows.Path(scope, spec.toggle))
                node.toggleBox = UI:CreateCheckbox(node.frame, "", node.toggleBinding:Read() == true, function(checked)
                    if not (node.context and node.context:IsCurrent()) then return end
                    node.toggleBinding:Write(checked == true, "commit")
                    node.context:RefreshPage()
                end)
                node.toggleBox:SetSize(GM.size.checkboxRowHeight, GM.size.checkboxRowHeight)
            end
        elseif spec.kind == "table" then
            node.tableHeader = UI:CreateSettingsTableHeader(node.frame, { columns = spec.columns })
        elseif spec.kind == "row" and TableOf(node) then
            node.tableRow = UI:CreateSettingsTableRow(node.frame, {})
        end
    end
    node.context = Context(node)
    if spec.kind == "card" and spec.addButton and session.style then
        local add = node.frame._v2StyleAdd
        add.glyph:SetText(spec.addButton.text)
        add.glyph:SetTextColor(unpack(UI.ControlAppearance.colors.muted))
        add._v2OnClick = node.context:Guard(function(_, mouseButton)
            session.owner.actions[spec.addButton.action](node.context, mouseButton)
        end)
    end
    -- 设置行与表格同属“设置列表”：铺满卡宽、相邻时不加间距，由行自己的分隔线隔开。
    -- 小字键值区（props）也算：紧贴上一行，中间那条线由上一行画。
    if spec.kind == "setting" or spec.kind == "table" or spec.kind == "props" then node.context._exSettingsRow = true end
    -- 样式页的块（group）和每条记录一块的 repeat 也算设置列表：与相邻行之间不留间距，用行线隔开（见 Stack）。
    if session.style and (spec.kind == "group" or (spec.kind == "repeat" and spec.template.kind == "group")) then
        node.context._exSettingsRow = true
    end
    if spec.kind == "row" and spec.separator then
        if not node.frame._v2SettingsSeparator then
            node.frame._v2SettingsSeparator = UI:CreateSettingsSeparator(node.frame, 1)
        end
        node.separator = node.frame._v2SettingsSeparator
        node.separator:Show()
    end
    if spec.kind == "control" or spec.kind == "component" then
        if spec.path or spec.controlType == "toggles" or spec.controlType == "preset" then
            local binding = session.owner.binding
            local function BindingFor()
                local function At(fieldPath) return CreateBinding(binding.moduleKey, binding.config, Session._rows.Path(scope, fieldPath)) end
                if spec.controlType == "preset" then
                    -- 预设：每个出现过的字段路径一个绑定。
                    local map = {}
                    for _, option in ipairs(spec.options) do
                        for fieldPath in pairs(option.values) do
                            map[fieldPath] = map[fieldPath] or At(fieldPath)
                        end
                    end
                    return map
                end
                if spec.controlType == "flow" then
                    return { direction = At(spec.path), wrap = At(spec.wrapPath) }
                end
                if spec.controlType ~= "toggles" then return At(spec.path) end
                local list = {}
                for i, item in ipairs(spec.items) do list[i] = At(item.path) end
                return list
            end
            if spec.kind == "control" then node.adapter = StandardControl(spec, BindingFor)
            elseif spec.component == "soundselector" then
                node.adapter = SoundSelectorComponent(spec, BindingFor, spec.optionsRef and session.owner.options[spec.optionsRef])
            else node.adapter = StandardComponent(spec, BindingFor, spec.optionsRef and session.owner.options[spec.optionsRef]) end
        else
            local provider = (spec.kind == "control" and session.owner.controls or session.owner.components)[spec.ref]
            node.adapter = spec.kind == "control" and ControlAdapter(provider) or provider
        end
        node.mountPending = true
        node.instance = node.adapter.mount(node.frame, node.context, spec)
        Check(node.instance ~= nil, spec.id .. ": mount must return instance")
        node.mountPending = false
        -- Keep the owner's original GUI width, not the width assigned by a prior layout.
        node.naturalWidth = node.instance.GetWidth and node.instance:GetWidth() or nil
        if spec.kind == "control" then
            Check(node.instance.GetParent and node.instance:GetParent() == node.frame,
                spec.id .. ": return original control hosted in the supplied GUI host")
            if node.instance.SetPageScroll then node.instance:SetPageScroll() end
            if spec.mode then
                Check(node.instance.mode == spec.mode, spec.id .. ": original choice mode differs")
            end
            if spec.controlType == "card" then
                Check(node.instance.checkbox ~= nil, spec.id .. ": card requires existing Checkbox")
                UI:PrepareSettingsListControl(node.instance, { presentation="card", hideLabel=false })
            end
        end
    elseif spec.kind == "button" then
        local onClick
        if spec._op then
            onClick = function() Session._rows.Run(node, spec._op) end
        elseif spec.clickKey then
            -- Same State contract the settings-section buttons published.
            local moduleKey = session.owner.binding.moduleKey
            onClick = function()
                _G.ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = spec.clickKey, fullPath = spec.clickKey, ts = GetTime() })
            end
        else
            onClick = function(_, mouseButton) session.owner.actions[spec.action](node.context, mouseButton) end
        end
        if spec.icon then
            -- 样式页图标按钮：池化 CreateIconButton，只响应左键（与文字按钮相同）。
            -- 预设写了 iconButtonSize / iconButtonIconSize / iconButtonAppearance 就用它们，否则边长取控件高。
            local guarded = node.context:Guard(onClick)
            local style = session.style
            local size = IconButtonSize(style)
            node.button = UI:CreateIconButton(node.frame, size, size, { icon = spec.icon,
                iconSize = style.iconButtonIconSize, appearance = style.iconButtonAppearance, tooltip = spec.tip,
                onClick = function(button, mouseButton)
                    if mouseButton == "LeftButton" then guarded(button, mouseButton) end
                end })
        else
            node.button = UI:CreateButton(node.frame, spec.width or GM.size.controlDefaultWidth,
                spec.height or GM.size.controlHeight, spec.text,
                node.context:Guard(onClick), { variant=spec.presentation or "secondary", compact=true })
        end
    elseif PartAdapters[spec.kind] then
        node.adapter = PartAdapters[spec.kind](node)
        node.mountPending = true
        node.instance = node.adapter.mount(node.frame, node.context, spec)
        node.mountPending = false
        node.naturalWidth = node.instance:GetWidth()
    elseif spec.kind == "_more" then
        -- Core 自动加的“高级 ›”行：整行可点的文字按钮，建在本节点宿主上（宿主借出时 Acquire 会收起）。
        local host = node.frame
        if not host._v2More then
            local more = CreateFrame("Button", nil, host)
            more:RegisterForClicks("LeftButtonUp")
            more.label = UI:CreateVisualFontString(more, _G.EXFONTFRAME, "GameFontHighlight")
            more.label:SetJustifyH("LEFT")
            more.label:SetWordWrap(false)
            local colors = UI.ControlAppearance.colors
            more:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(colors.text)) end)
            more:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(colors.muted)) end)
            more:SetScript("OnClick", function(self, mouseButton) if self._v2OnClick then self._v2OnClick(self, mouseButton) end end)
            host._v2More = more
        end
        local more = host._v2More
        UI.ControlAppearance.Font(more.label, Part(session.style, "moreFont"), UI.ControlAppearance.colors.muted, "", "GameFontHighlight")
        more._v2OnClick = node.context:Guard(function()
            session.owner.actions[session.advanced.toggle](node.context, not session.expanded)
            session:Refresh()
        end)
        more:Show()
        node.moreButton = more
    elseif spec.kind == "text" or spec.kind == "hint" or spec.kind == "group" then
        if not node.frame._v2Label then
            node.frame._v2Label = UI:CreateVisualFontString(node.frame, _G.EXFONTFRAME, "GameFontHighlight")
        end
        node.label = node.frame._v2Label
        node.label:SetFontObject(spec.kind == "group" and "GameFontNormal" or "GameFontHighlight")
        node.label:SetJustifyH("LEFT")
        node.label:SetJustifyV("TOP")
        node.label:SetWordWrap(true)
        node.label:Show()
        local colors = UI.ControlAppearance.colors
        node.label:SetTextColor(unpack(spec.kind == "hint" and colors.muted or colors.text))
        if spec.kind == "group" then node.label:SetText(spec.title) else Text(node) end
    end
    if spec.kind ~= "repeat" then
        for _, child in ipairs(spec.children or {}) do Build(session, child, node.body, scope, node) end
    end
    return node
end

local function Retire(node)
    node.alive = false
    node.generation = (node.generation or 0) + 1
    for _, child in ipairs(node.children) do Retire(child) end
end

-- [决定] 释放必须“继续必要清理，最后报告原错”：任一节点的 owner.release 或清理步骤抛错，
-- 不得中断剩余节点与 root 回池；第一个错误被记录，清理全部完成后用原样重新抛出（对齐 V1 CardSession:Release）。
local function Capture(failures, ok, failure)
    if not ok and not failures.failed then failures.failed, failures.reason = true, failure end
end

local function Rethrow(failures)
    if failures.failed then error(failures.reason, 0) end
end

-- The existing protected release boundary is shared by nodes and overflow.
local function Cleanup(failures, callback, ...)
    Capture(failures, pcall(callback, ...))
end

ReleaseNode = function(node, failures)
    Retire(node)
    local own = {}
    if node.mountPending then Capture(own, false, "SettingsV2: incomplete adapter mount " .. node.spec.id) end
    for _, child in ipairs(node.children) do ReleaseNode(child, own) end
    node.children = {}
    if node.frame then Cleanup(own, node.frame.Hide, node.frame) end
    if node.adapter and node.instance ~= nil then
        if node.spec.kind == "control" and node.spec.controlType == "card" then
            Cleanup(own, UI.RestoreSettingsListControl, UI, node.instance)
        end
        Cleanup(own, node.adapter.release, node.instance, node.context)
    end
    if node.button and node.spec.icon then Cleanup(own, node.button.Release, node.button)
    elseif node.button then Cleanup(own, Factory.Release, Factory, node.button._fromPool, node.button) end
    if node.toggleBox then Cleanup(own, ReleaseBoundWidget, node.toggleBox) end
    if node.rowHelp then
        local help = node.rowHelp
        Cleanup(own, function() help:Hide(); help._v2Text = nil; help._v2TextFn = nil end)
    end
    if node.label then Cleanup(own, function() node.label:Hide(); node.label:SetText("") end) end
    if node.moreButton then
        local more = node.moreButton
        Cleanup(own, function() more:Hide(); more._v2OnClick = nil end)
    end
    for _, field in ipairs({ "settingRow", "tableHeader", "tableRow" }) do
        local decoration = node[field]
        if decoration then Cleanup(own, decoration.Release, decoration) end
    end
    if node.settingRow and node.body and not own.failed then Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.body) end
    if node.frame and not own.failed then
        if node.spec.kind == "card" then
            local card = node.frame
            Cleanup(own, function()
                if node.scrollFrame then
                    node.scrollFrame:Hide()
                    node.scrollFrame:SetVerticalScroll(0)
                    node.scrollFrame._v2Content:SetSize(1, 1)
                end
                if card._v2LegendBacking then
                    card._v2LegendBacking:Hide()
                    card._v2LegendBacking:ClearAllPoints()
                end
                if card._v2StyleBar then
                    card._v2StyleBar:Hide()
                    card._v2StyleNote:Hide()
                    card._v2StyleNote:SetText("")
                    card._v2StyleAdd:Hide()
                    card._v2StyleAdd._v2OnClick = nil
                end
                if card._v2Help then
                    card._v2Help:Hide()
                    card._v2Help._v2Text = nil
                    card._v2CollapsedDivider:Hide()
                    card._v2CollapsedDivider:SetColorTexture(unpack(UI.ControlAppearance.DungeonAura.line))
                end
                if card._v2Step then
                    card._v2Step.number:Hide()
                    card._v2Step.number:SetText("")
                    card._v2Step.dot:Hide()
                    card._v2Step.line:Hide()
                end
                if card._v2StyleCard then
                    card._v2StyleCard:Hide()
                    UI:ClearControlSurface(card._v2StyleCard)
                    card._v2Chevron:Hide()
                    card._exSettingsCardToggle._exGlyph:Show()
                end
                if node.toggleFont then
                    card._exSettingsCardToggle._exGlyph:SetFont(unpack(node.toggleFont))
                    card._exSettingsCardToggle:SetSize(unpack(node.toggleSize))
                end
                UI:RestoreSettingsListCard(card)
                if node.headerPoints and #node.headerPoints > 0 then
                    card._exSettingsCardHeader:ClearAllPoints()
                    for _, point in ipairs(node.headerPoints) do card._exSettingsCardHeader:SetPoint(unpack(point)) end
                end
            end)
            if not own.failed and node.body then Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.body) end
            if not own.failed then Cleanup(own, card.Release, card) end
        else Cleanup(own, Factory.ReleaseCompositeHost, Factory, node.frame) end
    end
    -- A dirty ancestor is quarantined, never returned around a failed child.
    Capture(failures, not own.failed, own.reason)
    if own.failed then node.session.cleanupFailed, node.session.cleanupFailure = true, own.reason end
    node.mountPending = nil
    node.instance, node.frame, node.body, node.context, node.scrollFrame = nil, nil, nil, nil, nil
    node.adapter, node.button, node.label, node.separator = nil, nil, nil, nil
    node.width, node.reportedHeight, node.naturalWidth = nil, nil, nil
    node.headerPoints, node.toggleFont, node.toggleSize = nil, nil, nil
    node.settingRow, node.tableHeader, node.tableRow = nil, nil, nil
    node.toggleBox, node.toggleBinding, node.rowHelp = nil, nil, nil
    node.moreButton = nil
end

local function SyncRepeat(node)
    local records = Records(node)
    local changed = #records ~= #node.children
    if not changed then
        for i, child in ipairs(node.children) do
            if child.scope.item ~= records[i] then changed = true; break end
        end
    end
    if not changed then return end
    -- No index-based reuse: reset only this repeat region, preserving other nodes.
    local failures = {}
    for _, child in ipairs(node.children) do Retire(child) end
    for _, child in ipairs(node.children) do ReleaseNode(child, failures) end
    node.children = {}
    -- 旧成员清理出错：区域保持为空（下次 Refresh 会重建），先报告原错，不在脏状态上继续建新成员。
    Rethrow(failures)
    for i, record in ipairs(records) do
        local scope = { item=record, index=i, parent=node.scope, _repeatNode=node,
            _arrayPath=node.spec.path and Session._rows.Path(node.scope, node.spec.path) or nil }
        Build(node.session, node.spec.template, node.body, scope, node)
    end
end

local function Predicate(node, field)
    local ref = node.spec[field]
    if not ref then return true end
    local result = node.session.owner.predicates[ref](node.scope)
    Check(type(result) == "boolean", node.spec.id .. ": predicate must return ordinary boolean")
    return result
end

-- page.collapse.state：owner 记的折叠状态（true 收起 / false 展开 / nil 用声明的 collapsed）。
CollapseState = function(node)
    local result = node.session.owner.predicates[node.session.collapse.state](node.scope, node.spec.id)
    Check(result == nil or type(result) == "boolean", node.spec.id .. ": page.collapse.state must return boolean or nil")
    return result
end

-- 渐进披露：advanced 节点只在展开时显示；visible 判断照旧。
local function Shown(node)
    if node.spec.advanced and not node.session.expanded then return false end
    return Predicate(node, "visible")
end

-- 样式标题条右侧灰字：写了 note 显示 owner.texts[note]()；没写显示“N 项”（预设 countNote = false 时不显示）
-- （可见的直接子节点数，repeat 按展开后的成员计，折叠不影响计数）。空字串不显示。
local function StyleNote(node)
    local text
    if node.spec.note == nil and node.session.style.countNote == false then
        text = "" -- 预设 countNote = false：没写 note 的标题条不显示“N 项”
    elseif node.spec.note then
        text = node.session.owner.texts[node.spec.note](node.scope)
        Check(type(text) == "string", node.spec.id .. ": note text must return string")
    else
        local count = 0
        for _, child in ipairs(node.children) do
            if child.spec.kind == "repeat" then
                if Shown(child) then
                    for _, member in ipairs(child.children) do
                        if Shown(member) then count = count + 1 end
                    end
                end
            elseif Shown(child) then
                count = count + 1
            end
        end
        text = string.format(_G.ExwindTools.L["%d 项"], count)
    end
    local note = node.frame._v2StyleNote
    note:SetText(text)
    note:SetShown(text ~= "" and node.session.style.showHeader ~= false)
end

RefreshNode = function(node, parentVisible, parentEnabled)
    node.visible = parentVisible and Shown(node)
    node.enabled = parentEnabled and Predicate(node, "enabled") and Session._rows.Enabled(node)
    node.managesEnabled = node.spec.enabled ~= nil or (node.parent and node.parent.managesEnabled)
    node.frame:SetShown(node.visible)
    if node.spec.kind == "repeat" then SyncRepeat(node) end
    if node.adapter then
        node.reportedHeight = nil
        node.adapter.update(node.instance, node.context, node.spec)
        if node.managesEnabled then node.adapter.setEnabled(node.instance, node.context, node.enabled) end
        node.adapter.setVisible(node.instance, node.context, node.visible)
    elseif node.button then
        node.button:SetEnabled(node.enabled)
    elseif node.spec.kind == "text" or node.spec.kind == "hint" then Text(node)
    elseif node.moreButton then
        local L = _G.ExwindTools.L
        node.moreButton.label:SetText(node.session.expanded and L["收起 ‹"] or L["高级 ›"])
        node.moreButton:SetEnabled(node.enabled)
    end
    if node.settingRow and (node.spec.dimLabel or node.settingRow._v2LabelDimmed) then
        local dimmed = node.spec.dimLabel == true and not node.enabled
        node.settingRow._exSettingsRowTitle:SetAlpha(dimmed and .5 or 1)
        node.settingRow._v2LabelDimmed = dimmed or nil
    end
    local childrenEnabled = node.enabled
    if node.toggleBox then
        -- 勾选标签行：勾选框跟随本行可用状态，右侧控件只在勾上时可用。
        local checked = node.toggleBinding:Read() == true
        node.toggleBox:SetChecked(checked)
        UI:ApplyControlAppearance(node.toggleBox)
        ControlDefaults.setEnabled(node.toggleBox, node.context, node.enabled)
        childrenEnabled = node.enabled and checked
        node.managesEnabled = true
    end
    if node.spec.kind == "card" and node.spec.titleSource then
        node.frame._exSettingsCardTitle:SetText(node.session.owner.texts[node.spec.titleSource](node.scope))
    end
    if node.spec.kind == "card" and node.spec.step then
        local done = node.session.owner.predicates[node.spec.step.done](node.scope)
        Check(type(done) == "boolean", node.spec.id .. ": step.done must return ordinary boolean")
        node.stepDone = done
    end
    if node.spec.kind == "card" and node.spec.collapsible and node.session.collapse then
        local collapsed = CollapseState(node)
        if collapsed ~= nil and collapsed ~= node.frame:IsCollapsed() then node.frame:SetCollapsed(collapsed, true) end
    end
    local childrenVisible = node.visible and not (node.spec.kind == "card" and node.frame._exSettingsCardCollapsed)
    for _, child in ipairs(node.children) do RefreshNode(child, childrenVisible, childrenEnabled) end
    if node.spec.kind == "card" and node.session.style then StyleNote(node) end
end

-- 整页收起（根框已经不显示）：节点框不逐个藏，重开时只跟着根框显示一次、不各自重排两遍；
-- 控件照样收到“不显示”（收起焦点、关菜单）。重开时 Refresh 按谓词重算每个节点显不显示。
local function HideNode(node)
    node.visible = false
    if node.adapter then node.adapter.setVisible(node.instance, node.context, false) end
    for _, child in ipairs(node.children) do HideNode(child) end
end

local function Align(value, spare)
    if value == "end" then return math.max(0, spare) end
    if value == "center" then return math.max(0, spare) / 2 end
    return 0
end

local function ButtonTextWidth(node)
    local label = node.button and node.button.GetFontString and node.button:GetFontString()
    return math.ceil(label and label:GetUnboundedStringWidth() or 0) + GM.space.buttonPaddingX * 2
end

local NaturalBase

-- 前缀字母画在输入框外左边：自然宽 = 框宽 + 前缀让出的宽。
local function Natural(node)
    local width = NaturalBase(node)
    local spec = node.spec.kind == "control" and (node.adapter and node.adapter._exSpec or node.spec)
    if not spec then return width end
    return width + InputLeadReserve(spec, node.session.style)
end

NaturalBase = function(node)
    local kind = node.spec.kind
    -- 声明的宽度只是下限：按钮文字放不下时撑宽，不压窄。
    if node.spec.width then
        return kind == "button" and math.max(node.spec.width, ButtonTextWidth(node)) or node.spec.width
    end
    if kind == "button" then
        -- 记录表格的行操作按钮（Core 展开时标记 _compact）只按文字宽。
        if node.spec._compact then return ButtonTextWidth(node) end
        -- 没有文字的按钮是图标按钮（如 ▶ 试听），宽 = 高（样式页取预设控件高；写了 icon 的取预设图标按钮边长）。
        if node.spec.icon then return IconButtonSize(node.session.style) end
        if node.spec.text == "" then return StyledControlHeight(node.session.style) end
        return math.max(GM.size.buttonMinWidth, ButtonTextWidth(node))
    end
    if kind == "text" or kind == "hint" then
        return math.max(1, node.label:GetUnboundedStringWidth())
    end
    local controlType = kind == "control" and node.spec.controlType
    local style = node.session.style
    -- 样式页的平分分段占预设整列宽，不按文字自然宽。
    if style and controlType == "segment" and style.segmentEqualWidth and SizeWidth(node.spec, style) then
        return SizeWidth(node.spec, style)
    end
    if controlType == "choice" or controlType == "tristate" or controlType == "segment" or controlType == "toggles" then
        local width = ChoiceNaturalWidth(node.instance)
        if width then return width end
    end
    -- 预设 inputFitPlaceholder：没写 size 的输入框至少放得下整句占位字（放不下整行时照常收窄）。
    if style and style.inputFitPlaceholder and controlType == "input" and not node.spec.size and node.spec.placeholder
        and node.instance and node.instance.placeholder then
        local fit = math.ceil(node.instance.placeholder:GetUnboundedStringWidth()) + GM.space.inputTextPadX * 2
        return math.max(SizeWidth(node.spec, style) or node.naturalWidth or 0, fit)
    end
    if kind == "control" and SizeWidth(node.spec, style) then return SizeWidth(node.spec, style) end
    -- 预设写了 switchWidth / sliderWidth：不带 label 的开关、滑杆按预设宽（不受按钮最小宽限制）。
    if style and style.switchWidth and controlType == "switch" and not node.spec.label then return style.switchWidth end
    if style and style.sliderWidth and controlType == "slider" and not node.spec.label then return style.sliderWidth end
    if kind == "control" and not node.spec.label and SteppedSliderWidth(node.spec, style) then
        return SteppedSliderWidth(node.spec, style)
    end
    -- 预设写了 colorWidth：不带 label 的颜色控件（path 或记录控件）写色值不写文字，宽取 colorWidth。
    if style and style.colorWidth and controlType == "color" then
        local colorSpec = node.adapter and node.adapter._exSpec or node.spec
        if not colorSpec.label then return style.colorWidth end
    end
    -- 样式页的记录控件（owner 用 CreateSettingsV2Control 建）：owner 写了 size 档位就按档位宽（预设 shortWidth 等）。
    local ownerSpec = style and kind == "control" and node.adapter and node.adapter._exSpec
    if ownerSpec and ownerSpec.size and SizeWidth(ownerSpec, style) then return SizeWidth(ownerSpec, style) end
    -- Bound card checkboxes are as wide as their title (same metrics as the settings list);
    -- owner cards keep the width their owner gave them.
    if kind == "control" and node.spec.controlType == "card" and node.spec.path then
        local card = node.instance.checkbox._exSettingsCardSurface
        if card then
            return 14 + (node.instance._exSettingsCardIcon and 24 or 0)
                + math.ceil(card.Title:GetUnboundedStringWidth()) + 30
        end
    end
    -- The owner's original control width is its natural size. Explicit DSL
    -- widths still take precedence above; do not force every control to 160.
    if node.adapter then
        return math.max(kind == "control" and GM.size.buttonMinWidth or 1, node.naturalWidth or 0)
    end
    if kind == "columns" or kind == "table" then
        local width = 0
        for _, column in ipairs(node.spec.columns) do width = width + (column.width or 160) + GAP end
        return math.max(1, width - GAP)
    end
    if node.spec.children or kind == "repeat" then
        local width, count = 0, 0
        local horizontal = kind == "row" or kind == "actions" or kind == "setting"
        for _, child in ipairs(node.children) do
            if child.visible then
                local childWidth = Natural(child)
                if horizontal then
                    width = width + childWidth + (count > 0 and GAP or 0)
                else width = math.max(width, childWidth) end
                count = count + 1
            end
        end
        if kind == "group" and node.spec.title ~= "" then
            width = math.max(width, node.label:GetUnboundedStringWidth())
        end
        if kind == "card" then
            -- [WEB-REQ 03/64-67] 卡片自然宽是“外宽”：内容自然宽 + 自身左右 padding（LayoutNode 会再扣一次 PAD*2），
            -- 并不小于标题（含折叠钮/帮助钮）所需宽度；否则无显式 width 的卡内容会被二次挤窄。
            local spec, title = node.spec, node.frame._exSettingsCardTitle
            local titleWidth = title and title:GetUnboundedStringWidth() or 0
            if spec.titleAlign == "center" then titleWidth = titleWidth + 8
            else titleWidth = titleWidth + (spec.collapsible and 36 or 0) + (spec.help and 26 or 0) end
            return math.max(1, width + PAD * 2, titleWidth)
        end
        return math.max(1, width)
    end
    return 160
end

local function Flexible(node)
    if node.spec.width then return false end
    local kind = node.spec.kind
    return node.spec.weight ~= nil or kind == "group" or kind == "row" or kind == "actions" or kind == "chips" or PartAdapters[kind] ~= nil
        or kind == "columns" or kind == "repeat" or kind == "component" or kind == "hint"
        or kind == "setting" or kind == "table"
        or (kind == "control" and (node.spec.controlType == "choice" or node.spec.controlType == "multiline"))
end

local function Grow(node)
    if node.spec.width then return 0 end
    if node.spec.weight then return node.spec.weight end
    local kind = node.spec.kind
    if kind == "control" and SliderFills(node.spec, node.session.style) then return 1 end
    -- Action regions keep their requested placement; their child containers may grow.
    if kind == "group" or kind == "row" or kind == "columns" or kind == "repeat" or kind == "chips" or PartAdapters[kind] ~= nil
        or kind == "component" or kind == "hint" or kind == "setting" or kind == "table" then return 1 end
    return 0
end

local function IsSettingsRow(node)
    return node ~= nil and node.context ~= nil and node.context._exSettingsRow == true
end

-- 设置行规格（GM.settings）：设置卡片左右内边距统一 16，卡内所有内容左缘对齐。
-- 设置行与自带左右内边距的组合控件铺满卡片宽度，由它们自己的 16 内边距对齐同一左缘。
local SETTINGS = GM.settings
local BleedComponents = { fontgroup=true, icongroup=true, timerbargroup=true, modulecommonsettings=true, widgetlayout=true,
    glow_settings=true }

local function IsSettingsCard(node)
    return node.spec.kind == "card" and not node.spec.bodyHeight
end

-- 自带外框的种类（句子卡、入口卡、横排选择卡、法术芯片输入、只有按钮的无行名行）：
-- 样式页卡片里只有它们（或什么都没显示）时不再画外卡，免得框里再套一层框、底部按钮外面多一条空长框。
local function SelfSurfaced(spec)
    if spec.kind == "repeat" then return SelfSurfaced(spec.template) end
    if spec.kind == "setting" and spec.label == nil and spec.children and #spec.children > 0 then
        for _, child in ipairs(spec.children) do
            if child.kind ~= "button" then return false end
        end
        return true
    end
    -- 带小标题的预览卡网格、声音选择格子排法：每张卡 / 每格自己有框，外面不再套卡。
    return spec.kind == "sentence" or (spec.kind == "catalog" and (spec.presentation ~= nil or spec.title ~= nil))
        or (spec.kind == "control" and spec.controlType == "optionlist" and spec.columns ~= nil)
        or spec.kind == "chipinput"
        or (spec.kind == "component" and spec.component == "soundselector" and spec.opts ~= nil and spec.opts.tiles == true)
end

local function SelfSurfacedOnly(node)
    for _, child in ipairs(node.children) do
        if child.visible and not SelfSurfaced(child.spec) then return false end
    end
    return true
end

local function Bleeds(node)
    return IsSettingsRow(node) or (node.spec.kind == "component" and BleedComponents[node.spec.component] == true)
end

-- 返回卡片正文的左右、上、下内边距：只有设置行的边用 cardPaddingY，使单行卡 = 8 + 52 + 8 = 68。
local function CardPadding(node)
    -- 样式页：行左右不留白、行线通栏，标题条到第一行取预设（G3 为 0），卡片底不留白。
    local style = node.session.style
    -- 没有标题的卡（摘要卡、入口卡这类）不留标题到第一行的距离。
    if style then return 0, Name(node.spec.title) and (style.headerToFirstRow or 0) or 0, 0 end
    if not IsSettingsCard(node) then return PAD, PAD, PAD end
    local first, last
    for _, child in ipairs(node.children) do
        if child.visible then
            first = first or child
            last = child
        end
    end
    -- 铺满卡宽的组合控件（模块通用设置、字体组等）自带上下留白，首尾留白与设置行相同。
    local function RowEdge(child)
        return child ~= nil and Bleeds(child)
    end
    return SETTINGS.cardPaddingX, RowEdge(first) and SETTINGS.cardPaddingY or PAD,
        RowEdge(last) and SETTINGS.cardPaddingY or PAD
end

local function Stack(node, width, columns, offset)
    local y = offset or 0
    local visible = {}
    for _, child in ipairs(node.children) do
        if child.visible then visible[#visible + 1] = child end
    end
    local style = node.session.style
    -- 样式页卡片正文没有左右内距，设置行不用外伸。
    local bleed = (IsSettingsCard(node) and not style) and SETTINGS.cardPaddingX or 0
    -- 样式页的块（group）：块内行之间不画线；块与只放块的 repeat 的最后一项沿用自己“是不是最后”，
    -- 于是块与块、块与前后行之间各一条线。
    local block = style and node.spec.kind == "group"
    local passThrough = style and IsSettingsRow(node) and (block or node.spec.kind == "repeat")
    for index, child in ipairs(visible) do
        local previous, nextChild = visible[index - 1], visible[index + 1]
        child.hideTrailingSeparator = node.spec.kind == "repeat" and nextChild == nil
        -- Consecutive settings rows form one list: no gap, divider only between rows.
        local row = IsSettingsRow(child)
        if row then
            if passThrough and nextChild == nil then child.context._exRowLast = node.context._exRowLast ~= false
            elseif block then child.context._exRowLast = true
            else child.context._exRowLast = not IsSettingsRow(nextChild) end
        end
        if previous and not (row and IsSettingsRow(previous)) then
            -- 卡片与卡片之间按 SettingsCardSpacing；其余节点保持原间距。
            -- 样式页：组与组之间取预设 groupGap。
            -- 样式页里两个自带外框的件（句子卡、入口卡……）之间取预设 surfaceGap。
            -- 样式页里图标选取与前后节点之间取预设 iconPickSpacing（写了才用，可为负：压进前后行的上下内距，例如行下紧跟的已选图标）。
            local iconPick = style and style.iconPickSpacing and (child.spec.kind == "iconpick" or previous.spec.kind == "iconpick")
            y = y + ((child.spec.kind == "card" and previous.spec.kind == "card")
                and (style and style.groupGap or SETTINGS.cardGap)
                or (style and style.surfaceGap and SelfSurfaced(child.spec) and SelfSurfaced(previous.spec) and style.surfaceGap)
                or (iconPick and style.iconPickSpacing)
                or GAP)
        end
        local inset = Bleeds(child) and bleed or 0
        local height = LayoutNode(child, width + inset * 2, columns)
        Place(child.frame, node.body, -inset, y, width + inset * 2, height)
        y = y + height
    end
    return y
end

local function ColumnWidths(specs, width)
    local gap = math.min(GAP, width / (#specs * 2))
    local room = math.max(1, width - gap * (#specs - 1))
    local fixed, weight, flexible = 0, 0, 0
    for _, spec in ipairs(specs) do
        if spec.width then fixed = fixed + spec.width
        else weight = weight + (spec.weight or 1); flexible = flexible + 1 end
    end
    local fixedBudget = room - flexible * math.min(80, room / #specs)
    local scale = fixed > fixedBudget and fixedBudget / fixed or 1
    local widths = { gap=gap }
    for i, spec in ipairs(specs) do
        widths[i] = spec.width and spec.width * scale
            or math.max(1, room - fixed * scale) * (spec.weight or 1) / math.max(1, weight)
    end
    return widths
end

-- 设置行控件区的最小宽：输入框、下拉、颜色、分段（未选档位）可收窄到 controlMinWidth，
-- 其余控件（多选、按钮等）按自然宽，不压窄。分段压窄后放不下全部选项时由同一组选项的下拉顶替，不换到下一行。
local SHRINKABLE_CONTROLS = { input=true, select=true, color=true, segment=true }

local function Flow(node, width)
    local lines, line, used = {}, {}, 0
    local style = node.session.style
    for _, child in ipairs(node.children) do
        if child.visible then
            -- 非弹性项按自然宽占位：本行放不下就整项挪到下一行，不压窄。
            -- 自然宽超过整行时只能给满整行，按钮文字随之换行增高（见 LayoutNode）。
            local wanted = math.min(width, Natural(child))
            if child.spec.kind == "actions" and not child.spec.width then
                wanted = math.min(width, math.max(wanted, width * 0.55))
            end
            local minimum = Flexible(child) and math.min(wanted, 160) or wanted
            if style then
                -- 样式页不守 160：弹性项和未选档位的输入框、下拉、颜色都可收窄到 controlMinWidth。
                local spec = child.spec
                local shrink = Flexible(child)
                    or (spec.kind == "control" and SHRINKABLE_CONTROLS[spec.controlType] and not spec.size)
                minimum = shrink and math.min(wanted, GM.settings.controlMinWidth) or wanted
                if child.instance and child.instance._exMinWidth then minimum = math.min(wanted, child.instance._exMinWidth) end
            end
            -- 0.01 容差：自然宽（逐项相加）与这里的累计宽浮点舍入顺序不同，刚好排满的一行不能因 1ulp 误差而换行。
            if #line > 0 and used + GAP + minimum > width + 0.01 then
                lines[#lines + 1], line, used = line, {}, 0
            end
            if #line > 0 then used = used + GAP end
            line[#line + 1] = { node=child, width=minimum, preferred=wanted }
            used = used + minimum
        end
    end
    if #line > 0 then lines[#lines + 1] = line end
    local y = 0
    for _, entries in ipairs(lines) do
        local occupied, demand, weight, height = GAP * (#entries - 1), 0, 0, 0
        for _, entry in ipairs(entries) do
            occupied = occupied + entry.width
            demand = demand + entry.preferred - entry.width
            weight = weight + Grow(entry.node)
        end
        local available = math.max(0, width - occupied)
        local preferredSpace = math.min(available, demand)
        local extra = available - preferredSpace
        local x = Align(node.spec.align, weight == 0 and extra or 0)
        for _, entry in ipairs(entries) do
            local child = entry.node
            local childWidth = entry.width
                + (demand > 0 and preferredSpace * (entry.preferred - entry.width) / demand or 0)
                + (weight > 0 and extra * Grow(child) / weight or 0)
            -- Position the actions region independently of its internal alignment.
            if child.spec.kind == "actions" and weight == 0 then
                local free = math.max(0, width - x - childWidth)
                x = x + Align(child.spec.position, free)
            end
            entry.x, entry.width = x, childWidth
            entry.height = LayoutNode(child, childWidth)
            height = math.max(height, entry.height)
            x = x + childWidth + GAP
        end
        for _, entry in ipairs(entries) do
            Place(entry.node.frame, node.body, entry.x, y + (height - entry.height) / 2, entry.width, entry.height)
        end
        y = y + height + GAP
    end
    return math.max(0, y - GAP)
end

-- 表格列宽：声明了 width/weight 照用；没声明的按该列第一个控件定（沿用旧版表格规则：
-- 勾选/开关 64、按钮 96 起、其余按权重 1 分剩余宽）。
local TABLE_SWITCH_WIDTH, TABLE_BUTTON_WIDTH = 64, 96

local function TableRows(node)
    local rows = {}
    for _, child in ipairs(node.children) do
        if child.spec.kind == "repeat" then
            for _, row in ipairs(child.children) do rows[#rows + 1] = row end
        else rows[#rows + 1] = child end
    end
    return rows
end

local function TableColumns(node)
    local rows = TableRows(node)
    local columns = {}
    for i, column in ipairs(node.spec.columns) do
        local resolved = { title = column.title, width = column.width, weight = column.weight }
        if column.actions then
            -- Core 追加的操作列：按最宽一行按钮的自然宽定宽。
            local widest = 0
            for _, row in ipairs(rows) do
                local cell = row.children[i]
                local line = cell and cell.children[1]
                if line then widest = math.max(widest, Natural(line)) end
            end
            resolved.width = widest + GM.settings.tableCellPadX * 2
        elseif not column.width and not column.weight then
            -- 取该列第一个控件或按钮（跳过空白占位文字）决定列宽。
            local leaf
            for _, row in ipairs(rows) do
                local cell = row.children[i]
                local candidate = cell and cell.children[1]
                local candidateKind = candidate and candidate.spec.kind
                if candidateKind == "control" or candidateKind == "button" then leaf = candidate; break end
            end
            local kind = leaf and leaf.spec.kind
            local controlType = leaf and leaf.spec.controlType
            if kind == "control" and (controlType == "switch" or controlType == "checkbox" or controlType == "card") then
                resolved.width = TABLE_SWITCH_WIDTH
            elseif node.spec._rowsBound and kind == "control" and SizeWidth(leaf.spec, node.session.style)
                and (controlType == "number" or leaf.spec.size == "short") then
                -- 按行绑定的列表：数字框、short 档控件列只占控件自身宽（加格内边距），剩余宽留给输入框列。
                resolved.width = Natural(leaf) + 8 + GM.settings.tableCellPadX * 2
            elseif kind == "button" then
                resolved.width = math.max(TABLE_BUTTON_WIDTH, Natural(leaf) + 8)
            else
                resolved.weight = 1
            end
        end
        columns[i] = resolved
    end
    return columns
end

-- 一个表格行：每格按列宽排，行高至少 48，格内控件垂直居中，行间分隔线由共享表格行画。
local function LayoutTableRow(row, width, rects, isLast)
    local metrics = {}
    for i, cell in ipairs(row.children) do
        local cellWidth = math.max(1, rects[i].width - 8)
        metrics[i] = { visible = cell.visible, height = cell.visible and LayoutNode(cell, cellWidth) or 0 }
    end
    row.tableRow._exSettingsTableIsLast = isLast
    local height, cellRects = UI:UpdateSettingsTableRowLayout(row.tableRow, width, rects, metrics)
    row.tableRow:ClearAllPoints()
    row.tableRow:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
    for i, cell in ipairs(row.children) do
        if cell.visible then
            local rect = cellRects[i]
            Place(cell.frame, row.body, rect.x, rect.y, rect.width, metrics[i].height)
        end
    end
    if row.separator then row.separator:Hide() end
    row.frame:SetSize(math.max(1, width), math.max(1, height))
    -- 记录表格的当前行高亮（table.selected 判断）。
    local tableNode = TableOf(row)
    if tableNode and tableNode.spec.selected and row.parent.spec.kind == "repeat"
        and Predicate({ spec = { id = row.spec.id, selected = tableNode.spec.selected }, session = row.session, scope = row.scope }, "selected") then
        local colors = _G.ExwindTools.GUIColors
        UI:SetControlSurface(row.frame, GM.radius.control, colors.optionRowSelected, colors.optionRowSelectedBorder)
    else
        UI:ClearControlSurface(row.frame)
    end
    return height
end

-- 预设 tableEmptyCompact：表格没有记录、只剩新增行时不画表头，新增按钮靠右、行高同普通设置行。
-- （本文件顶层局部变量快到上限，和 LayoutTable 包在一个 do 块里。）
local LayoutTable
do
local function LayoutEmptyAddRow(node, row, width)
    local style = node.session.style
    local padX, padY = style.rowPaddingX or GM.settings.rowPaddingX, style.rowPaddingY or 0
    local addCell = row.children[#row.children]
    local cellWidth = math.max(1, Natural(addCell))
    local cellHeight = LayoutNode(addCell, cellWidth)
    local height = math.max(style.rowMinHeight or 0, cellHeight + padY * 2)
    for _, cell in ipairs(row.children) do
        if cell ~= addCell and cell.visible then Place(cell.frame, row.body, 0, 0, 1, LayoutNode(cell, 1)) end
    end
    Place(addCell.frame, row.body, width - padX - cellWidth, (height - cellHeight) / 2, cellWidth, cellHeight)
    row.tableRow:SetSize(math.max(1, width), height)
    row.tableRow:ClearAllPoints()
    row.tableRow:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
    row.tableRow._exSettingsTableDivider:Hide()
    if row.separator then row.separator:Hide() end
    UI:ClearControlSurface(row.frame)
    row.frame:SetSize(math.max(1, width), height)
    Place(row.frame, node.body, 0, 0, width, height)
    return height
end

LayoutTable = function(node, width)
    local style = node.session.style
    local compact = style and style.tableEmptyCompact
    local visible = {}
    local addRow, records = nil, 0
    for _, row in ipairs(TableRows(node)) do
        if row.visible then
            visible[#visible + 1] = row
            if row.spec.id == node.spec.id .. ".add.row" then addRow = row else records = records + 1 end
        end
    end
    node.tableHeader:SetShown(not (compact and addRow and records == 0))
    if compact and addRow and records == 0 then
        for _, child in ipairs(node.children) do
            if child.visible and child.spec.kind == "repeat" then Place(child.frame, node.body, 0, 0, width, 1) end
        end
        return LayoutEmptyAddRow(node, addRow, width)
    end
    local columns = TableColumns(node)
    node.tableHeader._exSettingsTableColumns = columns
    local headerHeight, rects = UI:UpdateSettingsTableHeaderLayout(node.tableHeader, width)
    if compact then
        -- 列名不换行：分到的宽比列名窄的列改成按列名定宽，再排一次。
        local widened = false
        for i, column in ipairs(columns) do
            local label = node.tableHeader._exSettingsTableLabels[i]
            local need = label and math.ceil(label:GetUnboundedStringWidth()) + 1 or 0
            if rects[i] and rects[i].width < need then column.width, column.weight, widened = need, nil, true end
        end
        if widened then headerHeight, rects = UI:UpdateSettingsTableHeaderLayout(node.tableHeader, width) end
    end
    if style and style.tableHeaderCellAligned then
        -- 列名和下面格子里的控件左缘对齐（格子左右各缩 tableCellPadX）。
        local cellPad = GM.settings.tableCellPadX
        for i, rect in ipairs(rects) do
            local label = node.tableHeader._exSettingsTableLabels[i]
            if label then
                label:ClearAllPoints()
                label:SetPoint("LEFT", node.tableHeader, "LEFT", rect.x + cellPad, 0)
                label:SetWidth(math.max(1, rect.width - cellPad * 2))
            end
        end
    end
    node.tableHeader:ClearAllPoints()
    node.tableHeader:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, 0)
    local last = visible[#visible]
    local y = headerHeight
    for _, child in ipairs(node.children) do
        if child.visible then
            if child.spec.kind == "repeat" then
                local inner = 0
                for _, row in ipairs(child.children) do
                    if row.visible then
                        local height = LayoutTableRow(row, width, rects, row == last)
                        Place(row.frame, child.body, 0, inner, width, height)
                        inner = inner + height
                    end
                end
                Place(child.frame, node.body, 0, y, width, inner)
                y = y + inner
            else
                local height = LayoutTableRow(child, width, rects, child == last)
                Place(child.frame, node.body, 0, y, width, height)
                y = y + height
            end
        end
    end
    return y
end
end

-- 同一张卡里占满标签右边的滑杆行（带 label 的滑杆、含这种滑杆的 setting 行）：标签列取这些行里最宽的标签
-- （含行尾小问号留位），各条滑杆从同一处起、一样长，不受行名长短、有没有小问号影响。
local function AlignSliderLabels(node)
    local function SliderRow(other)
        if other.settingRow then
            for _, child in ipairs(other.children) do
                if child.visible and child.spec.kind == "control" and SliderFills(child.spec, other.session.style) then
                    return other.settingRow
                end
            end
            return nil
        end
        return other.instance and other.instance._v2SliderRow or nil
    end
    local own = SliderRow(node)
    if not own then return end
    local widest = 0
    for _, sibling in ipairs(node.parent and node.parent.children or { node }) do
        local row = sibling.visible and SliderRow(sibling)
        local title = row and row._exSettingsRowTitle
        if title and title:IsShown() then
            widest = math.max(widest, math.ceil(title:GetUnboundedStringWidth()) + (row._exSettingsRowTrailingWidth or 0))
        end
    end
    own._exSettingsRowSliderLabelWidth = widest
end

-- 设置行：左标签（可带说明）右控件区；控件区按子节点自然宽占位，放不下时设置行自己转为上下排列。
local function SettingMinWidth(node)
    local width, count = 0, 0
    for _, child in ipairs(node.children) do
        if child.visible then
            local spec = child.spec
            local childWidth = Natural(child)
            if spec.kind == "control" and SHRINKABLE_CONTROLS[spec.controlType] and not spec.size then
                childWidth = math.min(childWidth, GM.settings.controlMinWidth)
            end
            -- 自己能收窄的原生选择器（每行个数一排方块）报了最窄宽。
            if child.instance and child.instance._exMinWidth then childWidth = math.min(childWidth, child.instance._exMinWidth) end
            width, count = width + childWidth + (count > 0 and GAP or 0), count + 1
        end
    end
    return math.max(1, width)
end

-- 没有行名的设置行：只放按钮时按钮照旧靠右（底栏“确定”这类）；只显示着一个控件时返回它。
-- （本文件顶层局部变量快到上限，这两个小函数和 LayoutSetting 包在一个 do 块里。）
local LayoutSetting
do
local function ButtonsOnly(node)
    for _, child in ipairs(node.children) do
        if child.visible and child.spec.kind ~= "button" then return false end
    end
    return true
end

local function SoleChild(node)
    local sole
    for _, child in ipairs(node.children) do
        if child.visible then
            if sole then return nil end
            sole = child
        end
    end
    return sole
end

LayoutSetting = function(node, width)
    local row = node.settingRow
    UI:SetSettingsRowLast(row, node.context._exRowLast ~= false)
    -- 控件区按自然宽请求；放不下时先收窄标签列（不小于窄版文字宽），再把输入框/下拉收窄到最小宽，
    -- 仍放不下才上标签、下控件。
    local style = node.session.style
    local _, height, x, y, controlWidth, controlHeight, leadX, leadTop
    if node.spec.label == nil and not ButtonsOnly(node) then
        -- 没有行名的设置行（预设 unlabeledFill）：控件区占满整行，左右只留行内距；只有一个控件时它占满整行。
        local padX = style.rowPaddingX or GM.settings.rowPaddingX
        controlWidth = math.max(1, width - padX * 2)
        local sole = SoleChild(node)
        controlHeight = math.max(1, sole and LayoutNode(sole, controlWidth) or Flow(node, controlWidth))
        if sole then Place(sole.frame, node.body, 0, 0, controlWidth, controlHeight) end
        -- 行只用来画分隔线、定行高：控件宽报 1，行不会转上下排。
        row._exSettingsRowControlWidth, row._exSettingsRowMinControlWidth = 1, 1
        -- 预设 tallRowPaddingY：比一行控件高的件（排列图示）上下多留这么多，边框不贴着行线。
        local tall = style.tallRowPaddingY and controlHeight > StyledControlHeight(style) + .5 and style.tallRowPaddingY or 0
        height, _, y, _, _, leadX, leadTop = UI:UpdateSettingsRowLayout(row, width, controlHeight + tall * 2)
        y = y + tall
        x = padX
    elseif SoleChild(node) and SoleChild(node).spec.kind == "chipinput" and SoleChild(node).spec.spanRow then
        -- chipinput spanRow：第一行照常排行名 + 输入框（只按输入框高），标签区从行名左缘起占满整行、接在下面；
        -- 行加高到标签区底下再留与输入框上方一样的边距（行线跟着行底走）。
        local chips = SoleChild(node)
        local padX = style.rowPaddingX or GM.settings.rowPaddingX
        row._exSettingsRowControlWidth = math.max(1, Natural(node))
        row._exSettingsRowMinControlWidth = SettingMinWidth(node)
        local firstHeight, inputX, inputY, inputWidth
        firstHeight, inputX, inputY, inputWidth, _, leadX, leadTop = UI:UpdateSettingsRowLayout(row, width, StyledControlHeight(style))
        x, y, controlWidth = padX, 0, math.max(1, width - padX * 2)
        chips.instance._v2Span = { x = inputX - padX, y = inputY, width = inputWidth }
        controlHeight = math.max(1, LayoutNode(chips, controlWidth))
        Place(chips.frame, node.body, 0, 0, controlWidth, controlHeight)
        height = math.max(firstHeight, controlHeight + inputY)
        row:SetSize(width, height)
    else
        row._exSettingsRowControlWidth = math.max(1, Natural(node))
        -- 预设 sliderFill：行里有显示着的滑杆时控件区占满标签右边，滑杆分走剩下的宽（见 Grow）。
        for _, child in ipairs(node.children) do
            if child.visible and child.spec.kind == "control" and SliderFills(child.spec, style) then
                row._exSettingsRowControlWidth = math.huge
                break
            end
        end
        row._exSettingsRowMinControlWidth = SettingMinWidth(node)
        _, _, _, controlWidth = UI:UpdateSettingsRowLayout(row, width, StyledControlHeight(style))
        controlHeight = math.max(1, Flow(node, controlWidth))
        height, x, y, _, _, leadX, leadTop = UI:UpdateSettingsRowLayout(row, width, controlHeight)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, 0)
    if node.rowHelp then
        -- 小问号紧跟标签文字第一行；行已为它在文字列里留出位置（trailingWidth）。
        local title = row._exSettingsRowTitle
        local lineHeight = select(2, title:GetFont()) or node.session.style.helpIconSize
        local textWidth = math.min(math.ceil(title:GetUnboundedStringWidth()), title:GetWidth())
        -- 标签靠右（定宽标签列）时文字右缘就是标签列右缘。
        if title:GetJustifyH() == "RIGHT" then textWidth = title:GetWidth() end
        node.rowHelp:ClearAllPoints()
        node.rowHelp:SetPoint("LEFT", title, "TOPLEFT", textWidth + STYLE_HELP_GAP, -lineHeight / 2)
    end
    Place(node.body, node.frame, x, y, controlWidth, controlHeight)
    if node.toggleBox then
        -- 勾选框容器比方框大一圈，方框居中；让方框左上角落在行给出的位置。
        local inset = (GM.size.checkboxRowHeight - GM.size.checkboxBoxSize) / 2
        Place(node.toggleBox, node.frame, leadX - inset, leadTop - inset,
            GM.size.checkboxRowHeight, GM.size.checkboxRowHeight)
    end
    return height
end
end

-- 步骤卡在页面里的位置：第几步、是不是最后一步、是不是第一个没完成的步骤（只数显示着的顶层步骤卡）。
local function StepPosition(node)
    local index, count, current, first = 0, 0, nil, nil
    for _, other in ipairs(node.session.nodes) do
        if other.visible and other.spec.kind == "card" and other.spec.step then
            count = count + 1
            if other == node then index = count end
            if not first and not other.stepDone then first = other end
        end
    end
    return index, index == count, first == node
end

-- 步骤条左栏：圆圈里写序号 1 2 3（做完的实心主色、白字；第一个没做完的描主色边、主色字；其余深灰边、灰字），
-- 到下一步的竖线（完成后变深主色）。
-- 预设 stepSide：左栏是圆角方块序号（做完的整块填主色、白字）+ 步骤名，按第一行竖直居中；不画竖线，
-- 步骤之间在组间距正中画一条横线。
local function LayoutSideStep(node, cardHeight, index, last, current, done)
    local style, card = node.session.style, node.frame
    local parts = card._v2Step
    local GC = _G.ExwindTools.GUIColors
    local dotSize, band = Part(style, "stepDotSize"), node.stepBand
    Place(parts.dot, card, Part(style, "stepDotX"), (band - dotSize) / 2, dotSize, dotSize)
    parts.ring:Hide()
    parts.core:Hide()
    UI:SetControlSurface(parts.dot, Part(style, "stepSideRadius"), done and GC.primaryFill or GC.panel,
        done and GC.primaryFill or (current and GC.accent or GC.checkboxHoverBorder))
    parts.squared = true
    parts.dot:SetFrameLevel(card:GetFrameLevel() + 2)
    card._v2StepFace:SetFrameLevel(parts.dot:GetFrameLevel() + 2)
    local numberColor = done and GC.primaryText or (current and GC.accent or GC.textDim)
    UI.ControlAppearance.Font(parts.number, Part(style, "stepNumberFont"), numberColor, "", "GameFontHighlight")
    parts.number:SetTextColor(unpack(numberColor))
    parts.number:SetText(tostring(index))
    parts.number:Show()
    parts.dot:Show()
    parts.line:SetShown(not last)
    if not last then
        local y = cardHeight + math.floor((style.groupGap or GAP) / 2)
        parts.line:SetColorTexture(unpack(UI.ControlAppearance.DungeonAura.line))
        parts.line:ClearAllPoints()
        parts.line:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
        parts.line:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -y)
        parts.line:SetHeight(Part(style, "stepSideDivider"))
    end
end

local function LayoutStep(node, cardHeight)
    local style, card = node.session.style, node.frame
    local parts = card._v2Step
    local GC = _G.ExwindTools.GUIColors
    local index, last, current = StepPosition(node)
    local done = node.stepDone == true
    if style.stepSide then return LayoutSideStep(node, cardHeight, index, last, current, done) end
    if parts.squared then
        UI:ClearControlSurface(parts.dot)
        parts.squared = nil
        parts.ring:Show()
        parts.core:Show()
    end
    local titleHeight, dotSize = Part(style, "stepTitleHeight"), Part(style, "stepDotSize")
    local dotX, border = Part(style, "stepDotX"), Part(style, "stepDotBorder")
    local top = (titleHeight - dotSize) / 2
    Place(parts.dot, card, dotX, top, dotSize, dotSize)
    local ring = done and GC.primaryFill or (current and GC.accent or GC.checkboxHoverBorder)
    parts.ring:SetVertexColor(unpack(ring))
    local coreSize = dotSize - border * 2
    Place(parts.core, parts.dot, border, border, coreSize, coreSize)
    local fill = done and GC.primaryFill or GC.panel
    parts.fill:SetVertexColor(unpack(fill))
    parts.dot:SetFrameLevel(card:GetFrameLevel() + 2)
    card._v2StepFace:SetFrameLevel(parts.dot:GetFrameLevel() + 2)
    local numberColor = done and GC.primaryText or (current and GC.accent or GC.textDim)
    UI.ControlAppearance.Font(parts.number, Part(style, "stepNumberFont"), numberColor, "", "GameFontHighlightSmall")
    parts.number:SetTextColor(unpack(numberColor))
    parts.number:SetText(tostring(index))
    parts.number:Show()
    parts.dot:Show()
    parts.line:SetShown(not last)
    if not last then
        local lineWidth, lineGap = Part(style, "stepLineWidth"), Part(style, "stepLineGap")
        parts.line:SetColorTexture(unpack(done and GC.primaryFillActive or GC.cardBorder))
        parts.line:ClearAllPoints()
        local x = dotX + dotSize / 2 - lineWidth / 2
        parts.line:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(top + dotSize + lineGap))
        -- 竖线伸过组间距，停在下一步圆点上方 lineGap 处。
        parts.line:SetPoint("BOTTOMRIGHT", card, "TOPLEFT", x + lineWidth,
            -(cardHeight + (style.groupGap or GAP) + top - lineGap))
    end
end

-- 样式页的卡片（G3+H1）：整条圆角标题条，左折叠号、组名，最右灰字；条和第一行之间不留白；
-- 标题条（连同点击区）左右各外伸预设 headerOutset，比下面的行宽；预设 showHeader=false 时不画标题条。原有卡片算法（节标题上移、sectionHeaderBottom）不经过这里。
local function LayoutStyledCard(node, width)
    local style, card = node.session.style, node.frame
    local padX, padTop, padBottom = CardPadding(node)
    local step = node.spec.step ~= nil
    -- 预设 stepSide：步骤名不在内容上方，挪进左栏（序号方块后面），内容从卡顶开始。
    local side = step and style.stepSide == true
    local rail = step and Part(style, side and "stepSideWidth" or "stepRailWidth") or 0
    if step then padTop, padBottom = Part(style, "stepTitleGap"), Part(style, "stepBottom") end
    if side then padTop, padBottom = 0, 0 end
    width = width - rail
    local scrollInset = node.scrollFrame and node.scrollFrame:GetVerticalScrollInset() or 0
    local innerWidth = math.max(1, width - padX * 2 - scrollInset)
    local height = math.max(node.spec.minBodyHeight or 0, Stack(node, innerWidth))
    if not node.scrollFrame then
        node.body:ClearAllPoints()
        PixelUtil.SetPoint(node.body, "TOPLEFT", card:GetBody(), "TOPLEFT", padX, -padTop, 0, 0)
        PixelUtil.SetPoint(node.body, "TOPRIGHT", card:GetBody(), "TOPRIGHT", -padX, -padTop, 0, 0)
    end
    node.body:SetHeight(math.max(1, height))
    local header, title, toggle = card._exSettingsCardHeader, card._exSettingsCardTitle, card._exSettingsCardToggle
    local bar, note, help, add = card._v2StyleBar, card._v2StyleNote, card._v2Help, card._v2StyleAdd
    local collapsible = node.spec.collapsible == true
    local showHeader = style.showHeader ~= false and ((title:GetText() or "") ~= "" or collapsible)
    local collapsed = collapsible and card._exSettingsCardCollapsed == true
    card._v2CollapsedDivider:Hide()
    local chevron = style.foldGlyph == "chevron" or style.foldGlyph == "plus"
    card._v2Chevron:SetShown(showHeader and collapsible and chevron)
    toggle._exGlyph:SetShown(not chevron)
    help:SetShown(showHeader and node.spec.help ~= nil)
    local headerHeight, outset = 0, showHeader and style.headerOutset or 0
    if showHeader then
        local colors = UI.ControlAppearance.colors
        local x = side and 0 or style.headerPaddingLeft
        if collapsible then
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", header, "LEFT", x, 0)
            toggle:SetSize(style.foldWidth, style.headerHeight)
            UI.ControlAppearance.Font(toggle._exGlyph, style.headerFont, colors.text, "", "GameFontHighlight")
            toggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
            if chevron then
                -- 箭头收起朝右、展开朝下；加减号收起“+”、展开“−”（灰色）。
                local icons = style.foldGlyph == "plus" and { "plus", "minus" } or { "chevron-right", "chevron-down" }
                card._v2Chevron:SetTexture(UI:GetIcon(collapsed and icons[1] or icons[2]))
                card._v2Chevron:SetSize(style.foldWidth, style.foldWidth)
                card._v2Chevron:SetVertexColor(unpack(colors.muted))
            end
            x = x + style.foldWidth + style.foldNameGap
        end
        local headerFont = step and Part(style, "stepTitleFont") or style.headerFont
        local headerLine = step and Part(style, "stepTitleHeight") or style.headerHeight
        UI.ControlAppearance.Font(title, headerFont, style.headerText or colors.text, "", "GameFontHighlight")
        UI.ControlAppearance.Font(note, style.noteFont, colors.muted, "", "GameFontHighlightSmall")
        local noteWidth = note:IsShown() and math.ceil(note:GetUnboundedStringWidth()) or 0
        local helpWidth = node.spec.help and (help:GetWidth() + STYLE_HELP_GAP) or 0
        local addWidth = node.spec.addButton and style.headerHeight or 0
        local addSpace = addWidth > 0 and addWidth + GAP or 0
        local room = width + outset * 2 - x - style.headerPaddingRight - helpWidth - (noteWidth > 0 and noteWidth + GAP or 0) - addSpace
        if side then room = rail - Part(style, "stepDotSize") - Part(style, "stepSideNameGap") - helpWidth end
        -- 组名放不下就换行，标题条随行数增高（不截断）。
        title:SetWordWrap(true)
        title:SetJustifyH("LEFT")
        title:SetJustifyV("MIDDLE")
        title:SetWidth(math.max(1, math.min(math.ceil(title:GetUnboundedStringWidth()) + 1, room)))
        headerHeight = math.max(headerLine, math.ceil(title:GetStringHeight()) + headerLine - headerFont)
        title:ClearAllPoints()
        title:SetPoint("LEFT", header, "LEFT", x, 0)
        note:ClearAllPoints()
        note:SetPoint("RIGHT", header, "RIGHT", -style.headerPaddingRight - addSpace, 0)
        if addWidth > 0 then
            UI.ControlAppearance.Font(add.glyph, style.headerFont, colors.muted, "", "GameFontHighlight")
            add:ClearAllPoints()
            add:SetPoint("RIGHT", header, "RIGHT", -style.headerPaddingRight, 0)
            add:SetSize(addWidth, addWidth)
        end
        if node.spec.help then
            help:ClearAllPoints()
            help:SetPoint("LEFT", title, "RIGHT", STYLE_HELP_GAP, 0)
        end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", header, "TOPLEFT")
        bar:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
        bar:SetFrameLevel(math.max(card:GetFrameLevel(), header:GetFrameLevel() - 1))
    end
    bar:SetShown(showHeader and not side)
    add:SetShown(showHeader and node.spec.addButton ~= nil)
    -- 预设 collapsedPadding：收起时标题下留白，底边画一条细线（卡边色）。
    local collapsedPad = (showHeader and collapsed and style.collapsedPadding) or 0
    if collapsedPad > 0 then
        local divider = card._v2CollapsedDivider
        divider:SetColorTexture(unpack(UI.ControlAppearance.DungeonAura.line)) -- 与标准页收起细线同色
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(collapsedPad - 1))
        divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -(collapsedPad - 1))
        divider:SetHeight(1)
        divider:Show()
    end
    -- 预设 cardFill：行装在圆角带边卡里；卡里只有自带外框的种类（句子卡、入口卡、横排选择卡）时不画。
    local surface = card._v2StyleCard
    local drawCard = style.cardFill ~= nil and not collapsed and not node.session.quick and not SelfSurfacedOnly(node) and not side
    if drawCard then
        UI:SetControlSurface(surface, style.cardRadius, style.cardFill, style.cardBorder)
        surface:ClearAllPoints()
        surface:SetPoint("TOPLEFT", node.body, "TOPLEFT")
        surface:SetPoint("BOTTOMRIGHT", node.body, "BOTTOMRIGHT")
        surface:SetFrameLevel(card:GetFrameLevel())
    end
    surface:SetShown(drawCard)
    headerHeight = headerHeight + collapsedPad
    header:ClearAllPoints()
    if side then
        -- 左栏：步骤名在序号方块后面，和方块一起按第一行（不超过 stepTitleHeight）竖直居中。
        local band = math.max(Part(style, "stepDotSize"), math.min(height, Part(style, "stepTitleHeight")))
        local textX = Part(style, "stepDotX") + Part(style, "stepDotSize") + Part(style, "stepSideNameGap")
        node.stepBand = band
        height = math.max(height, band)
        header:SetPoint("TOPLEFT", card, "TOPLEFT", textX, 0)
        header:SetSize(math.max(1, rail - textX), band)
        headerHeight = 0
    else
        header:SetPoint("TOPLEFT", card, "TOPLEFT", rail - outset, 0)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", outset, 0)
        header:SetHeight(math.max(1, headerHeight - collapsedPad))
    end
    card._exSettingsListExternalHeader.height = headerHeight
    header:SetShown(showHeader)
    card:GetBody():ClearAllPoints()
    PixelUtil.SetPoint(card:GetBody(), "TOPLEFT", card, "TOPLEFT", rail, -headerHeight, 0, 0)
    PixelUtil.SetPoint(card:GetBody(), "TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight, 0, 0)
    card:SetContentHeight((node.spec.bodyHeight or height) + padTop + padBottom)
    if node.scrollFrame then
        local scrollFrame = node.scrollFrame
        Place(scrollFrame, card:GetBody(), padX, padTop, innerWidth, node.spec.bodyHeight)
        scrollFrame._v2Content:SetSize(innerWidth, math.max(1, height))
        scrollFrame:UpdateScrollChildRect()
        scrollFrame:SetVerticalScroll(math.max(0, math.min(scrollFrame:GetVerticalScroll(),
            scrollFrame:GetVerticalScrollRange())))
        scrollFrame:SetShown(not card._exSettingsCardCollapsed)
    end
    local cardHeight = card:GetPreferredHeight()
    if step then LayoutStep(node, cardHeight) end
    return cardHeight
end

LayoutNode = function(node, width, columns)
    width = math.max(1, width)
    node.frame:SetWidth(width)
    AlignSliderLabels(node)
    local kind, height = node.spec.kind, 0
    if node.adapter then
        if node.width ~= width then node.reportedHeight = nil end
        node.width = width
        local measured = node.adapter.measure(node.instance, node.context, width)
        -- Default single-line controls share one height. Owner measurements
        -- still describe multiline/custom content and explicit size contracts.
        local controlType = node.spec.controlType
        if node.adapter.measure == ControlDefaults.measure
            and (controlType == "input" or controlType == "checkbox" or controlType == "card"
                or controlType == "select" or controlType == "color") then
            measured = node.spec.height or StyledControlHeight(node.session.style)
        end
        Check(type(measured) == "number" and measured >= 0 and measured < math.huge, node.spec.id .. ": invalid measure")
        height = math.max(node.spec.height or 0, node.reportedHeight or measured)
        node.adapter.layout(node.instance, node.context, width, height)
    elseif node.button then
        height = node.spec.height or (node.spec.icon and IconButtonSize(node.session.style))
            or StyledControlHeight(node.session.style)
        Place(node.button, node.frame, 0, 0, width, height)
        -- 给不到文字所需宽度时换行并增高，不出省略号（图标按钮没有文字）。
        local label = not node.spec.icon and node.button:GetFontString()
        if label and ButtonTextWidth(node) > width + 0.5 then
            label:SetWordWrap(true)
            local wrapped = math.ceil(label:GetStringHeight()) + GM.space.buttonPaddingY * 2
            if wrapped > height then
                height = wrapped
                Place(node.button, node.frame, 0, 0, width, height)
            end
        end
    elseif kind == "text" or kind == "hint" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        height = math.max(node.spec.height or 0, node.label:GetStringHeight())
    elseif kind == "_more" then
        local style = node.session.style
        height = Part(style, "moreRowHeight")
        local more, inset = node.moreButton, Part(style, "moreTextInset")
        Place(more, node.frame, 0, 0, width, height)
        more.label:ClearAllPoints()
        more.label:SetPoint("LEFT", more, "LEFT", inset, 0)
        more.label:SetPoint("RIGHT", more, "RIGHT", 0, 0)
    elseif kind == "setting" and node.settingRow then
        height = LayoutSetting(node, width)
    elseif kind == "table" then
        height = LayoutTable(node, width)
    elseif kind == "row" and columns then
        local x, heights = 0, {}
        for i, child in ipairs(node.children) do
            heights[i] = child.visible and LayoutNode(child, columns[i]) or 0
            height = math.max(height, heights[i])
        end
        for i, child in ipairs(node.children) do
            Place(child.frame, node.body, x, (height - heights[i]) / 2, columns[i], heights[i])
            x = x + columns[i] + columns.gap
        end
    elseif kind == "row" or kind == "actions" then
        height = Flow(node, width)
    elseif kind == "card" and node.session.style then
        return LayoutStyledCard(node, width)
    elseif kind == "card" then
        local padX, padTop, padBottom = CardPadding(node)
        local scrollInset = node.scrollFrame and node.scrollFrame:GetVerticalScrollInset() or 0
        local innerWidth = math.max(1, width - padX * 2 - scrollInset)
        height = math.max(node.spec.minBodyHeight or 0, Stack(node, innerWidth))
        if not node.scrollFrame then
            node.body:ClearAllPoints()
            PixelUtil.SetPoint(node.body, "TOPLEFT", node.frame:GetBody(), "TOPLEFT", padX, -padTop, 0, 0)
            PixelUtil.SetPoint(node.body, "TOPRIGHT", node.frame:GetBody(), "TOPRIGHT", -padX, -padTop, 0, 0)
        end
        node.body:SetHeight(math.max(1, height))
        local card, title = node.frame, node.frame._exSettingsCardTitle
        -- 下置标题：用小号说明字，页脚更矮；titleAlign="center" 让它居中。
        local caption = node.spec.titlePosition == "bottom"
        local legend = node.spec.titlePosition == "legend"
        -- 设置卡片的上置标题即节标题：离上方卡片远（30）、离下方卡片近（6），字号 BodyStrong。
        local section = not caption and not legend and IsSettingsCard(node)
        local captionTop, captionBottom = 5, 7
        local titleTop = section and (SETTINGS.sectionHeaderTop - SETTINGS.cardGap) or (caption and captionTop or 8)
        if caption then UI.ControlAppearance.ApplyTextRole(title, "hint") end
        if section then UI.ControlAppearance.ApplyTextRole(title, "settingsSection") end
        if legend then
            UI.ControlAppearance.ApplyTextRole(title, "cardTitle")
            title:SetJustifyV("TOP")
        end
        -- 标题放不下一律换行，表头随行数增高。
        title:SetWordWrap(true)
        title:ClearAllPoints()
        local legendExtra = 0
        if legend then
            local inset = GM.space.exboss.contentPaddingX
            local titleWidth = math.max(1, math.min(math.ceil(title:GetUnboundedStringWidth()) + 2,
                width - inset * 2 - (node.spec.collapsible and 36 or 0)))
            -- 首行骑在上边框（与单行时位置相同），多出的行向下排，正文随之下移。
            local lineHeight = select(2, title:GetFont()) or 0
            title:SetWidth(titleWidth)
            legendExtra = math.max(0, math.ceil(title:GetStringHeight() - lineHeight))
            if node.spec.titleAlign == "center" then
                title:SetPoint("TOP", card._exSettingsCardHeader, "TOP", 0, lineHeight / 2)
                title:SetJustifyH("CENTER")
            else
                title:SetPoint("TOPLEFT", card._exSettingsCardHeader, "TOPLEFT", inset, lineHeight / 2)
                title:SetJustifyH("LEFT")
            end
            if not card._v2LegendBacking then
                card._v2LegendBacking = UI:CreateVisualTexture(card._exSettingsCardHeader, _G.EXBASEFRAME)
            end
            local backing = card._v2LegendBacking
            backing:ClearAllPoints()
            backing:SetPoint("CENTER", title, "TOP", 0, -lineHeight / 2)
            backing:SetSize(titleWidth + 12,
                PixelUtil.GetNearestPixelSize(2, card._exSettingsCardHeader:GetEffectiveScale(), 1))
            backing:SetColorTexture(unpack(_G.ExwindTools.GUIColors.panel))
            backing:SetShown(node.spec.surface ~= "none" and node.spec.title ~= "")
        elseif node.spec.titleAlign == "center" then
            title:SetPoint("TOP", card._exSettingsCardHeader, "TOP", 0, -titleTop)
            title:SetWidth(math.max(1, width - 8))
            title:SetJustifyH("CENTER")
        else
            title:SetPoint("TOPLEFT", card._exSettingsCardHeader, "TOPLEFT", 0, -titleTop)
            title:SetWidth(math.max(1, math.min(title:GetUnboundedStringWidth(), width - (node.spec.collapsible and 36 or 0))))
        end
        if node.spec.collapsible then
            local toggle = card._exSettingsCardToggle
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", title, "RIGHT", 8, 0)
            toggle:SetSize(28, 28)
            UI.ControlAppearance.ApplyTextRole(toggle._exGlyph, "pageTitle")
            toggle._exGlyph:SetText(card._exSettingsCardCollapsed and "+" or "−")
        end
        local help, divider = card._v2Help, card._v2CollapsedDivider
        help:SetShown(node.spec.help ~= nil)
        if node.spec.help then
            help:ClearAllPoints()
            help:SetPoint("LEFT", node.spec.collapsible and card._exSettingsCardToggle or title, "RIGHT", 4, 0)
        end
        divider:ClearAllPoints()
        divider:SetPoint("BOTTOMLEFT", card._exSettingsCardHeader, "BOTTOMLEFT", 12, 0)
        divider:SetPoint("BOTTOMRIGHT", card._exSettingsCardHeader, "BOTTOMRIGHT", -12, 0)
        divider:SetHeight(1)
        divider:SetShown(node.spec.collapsible == true and card._exSettingsCardCollapsed == true)
        local hasHeader = (title:GetText() or "") ~= "" or node.spec.collapsible == true
        -- Legend titles straddle the border: the frame stays 24px tall so its
        -- center + 12 lands on the top edge; the body retains the original 13px inset.
        local headerHeight = hasHeader and (legend and (13 + legendExtra)
            or (titleTop + title:GetStringHeight() + (section and SETTINGS.sectionHeaderBottom or (caption and captionBottom or 18)))) or 0
        card._exSettingsListExternalHeader.height = headerHeight
        card._exSettingsCardHeader:SetShown(hasHeader)
        card._exSettingsCardHeader:SetHeight(math.max(1, legend and PAD * 2 or headerHeight))
        card:GetBody():ClearAllPoints()
        PixelUtil.SetPoint(card:GetBody(), "TOPLEFT", card, "TOPLEFT", 0, -headerHeight, 0, 0)
        PixelUtil.SetPoint(card:GetBody(), "TOPRIGHT", card, "TOPRIGHT", 0, -headerHeight, 0, 0)
        node.frame:SetContentHeight((node.spec.bodyHeight or height) + padTop + padBottom)
        if node.spec.titlePosition == "bottom" then
            card:GetBody():ClearAllPoints()
            card:GetBody():SetPoint("TOPLEFT", card, "TOPLEFT")
            card:GetBody():SetPoint("TOPRIGHT", card, "TOPRIGHT")
            card._exSettingsCardHeader:ClearAllPoints()
            card._exSettingsCardHeader:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
            card._exSettingsCardHeader:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
        else
            card._exSettingsCardHeader:ClearAllPoints()
            card._exSettingsCardHeader:SetPoint("TOPLEFT", card, "TOPLEFT")
            card._exSettingsCardHeader:SetPoint("TOPRIGHT", card, "TOPRIGHT")
        end
        if node.scrollFrame then
            local scrollFrame = node.scrollFrame
            Place(scrollFrame, card:GetBody(), PAD, PAD, innerWidth, node.spec.bodyHeight)
            scrollFrame._v2Content:SetSize(innerWidth, math.max(1, height))
            scrollFrame:UpdateScrollChildRect()
            scrollFrame:SetVerticalScroll(math.max(0, math.min(scrollFrame:GetVerticalScroll(),
                scrollFrame:GetVerticalScrollRange())))
            scrollFrame:SetShown(not card._exSettingsCardCollapsed)
        end
        return node.frame:GetPreferredHeight()
    elseif kind == "columns" then
        height = Stack(node, width, ColumnWidths(node.spec.columns, width))
    elseif kind == "group" then
        node.label:ClearAllPoints()
        node.label:SetPoint("TOPLEFT")
        node.label:SetWidth(width)
        local hasTitle = node.spec.title ~= ""
        node.label:SetShown(hasTitle)
        height = Stack(node, width, nil, hasTitle and (node.label:GetStringHeight() + GAP) or 0)
    else
        height = Stack(node, width, columns)
    end
    if node.separator then
        node.separator:SetShown(not node.hideTrailingSeparator)
        if not node.hideTrailingSeparator then
            node.separator:ClearAllPoints()
            node.separator:SetPoint("TOPLEFT", node.frame, "TOPLEFT", 0, -(height + GAP / 2))
            node.separator:SetWidth(width)
            height = height + GAP
        end
    end
    node.frame:SetHeight(math.max(1, height))
    return height
end

-- Mounted-node lookup for page services (preview focus, style presets). Repeat
-- templates share one id; the first mounted record wins.
function Session:ForEachNode(callback)
    local function Walk(nodes)
        for _, node in ipairs(nodes) do
            if node.alive then
                if callback(node) == true then return true end
                if Walk(node.children) then return true end
            end
        end
    end
    if self.alive then Walk(self.nodes) end
end

function Session:FindNode(id)
    local found
    self:ForEachNode(function(node)
        if node.spec.id == id then found = node; return true end
    end)
    return found
end

-- 卡片当前是否折叠（重建页面前记下用户的折叠，再写回声明的 collapsed）。
-- id 不是已挂载的卡片时返回 nil；重复模板里同 id 的卡片取第一张。
function Session:IsCardCollapsed(id)
    local node = self:FindNode(id)
    if not node or node.spec.kind ~= "card" then return nil end
    return node.frame:IsCollapsed()
end

function Session:GetHeight() return self.height or 0 end
function Session:GetContentWidth() return self.contentWidth or 0 end

-- Page rows are measured together; the next row always follows the tallest card.
-- 同一排的卡片拉到一样高：矮的卡片把主体加高，多出的空间留在卡片底部，行仍从顶部排。
-- This is a card layout, with no arbitrary frame targets or authored coordinates.
local function ArrangePageGrid(session, width)
    local columns, total = session.columns, 0
    for _, column in ipairs(columns) do total = total + column.weight end
    local gap = math.min(session.columnGap or GAP, width / (#columns * 2))
    local room = math.max(1, width - gap * (#columns - 1))
    local widths, offsets, x = {}, {}, PAD
    for i, column in ipairs(columns) do
        offsets[i], widths[i] = x, room * column.weight / total
        x = x + widths[i] + gap
    end
    local rows, order = {}, {}
    for _, node in ipairs(session.nodes) do
        if node.visible then
            local row = node.spec.row
            if not rows[row] then rows[row] = {}; order[#order + 1] = row end
            rows[row][#rows[row] + 1] = node
        end
    end
    table.sort(order)
    local y = PAD
    for index, row in ipairs(order) do
        local height, before, entries = 0, 0, {}
        for _, node in ipairs(rows[row]) do
            local column, span = node.spec.column, node.spec.span or 1
            local cardWidth = gap * (span - 1)
            for i = column, column + span - 1 do cardWidth = cardWidth + widths[i] end
            local nodeHeight = LayoutNode(node, cardWidth)
            height = math.max(height, nodeHeight)
            before = math.max(before, node.spec.gapBefore or 0)
            entries[#entries + 1] = { node=node, width=cardWidth, x=offsets[column], height=nodeHeight }
        end
        if index > 1 then y = y + (session.rowGap or GAP) end
        y = y + before
        for _, entry in ipairs(entries) do
            local frame = entry.node.frame
            if entry.height < height and frame.SetContentHeight and not frame._exSettingsCardCollapsed then
                frame:SetContentHeight(frame._exSettingsCardContentHeight + height - entry.height)
            end
            Place(frame, session.root, entry.x, y, entry.width, height)
        end
        y = y + height
    end
    return y + PAD
end

-- [决定] Layout 出错恢复：测量/布局阶段抛错时必须清除 layingOut 锁，再原样报告原错，
-- 否则之后的所有 Invalidate/Refresh 都会在入口直接返回、页面永远不再重排（对齐 V1/网页 renderer 的 finally）。
function Session:Layout()
    if not self.alive or self.cleanupFailed or self.layingOut then return end
    self.layingOut = true
    -- 样式页：页面四周留白取 pagePadding，第一组离顶取 firstGroupTop，组间取 groupGap（预设没写的项用原值）。
    local style, pageGap, pad = self.style, GAP, PAD
    if style then pad = style.pagePadding or PAD end
    local width, y = math.max(1, self.root:GetWidth() - pad * 2), pad
    if style then y, pageGap = style.firstGroupTop or pad, style.groupGap or GAP end
    local function Arrange(node)
        if node.visible then
            local height = LayoutNode(node, width)
            Place(node.frame, self.root, pad, y, width, height)
            y = y + height + pageGap
        end
    end
    local gridHeight
    local ok, failure = pcall(function()
        if self.layout == "grid" then gridHeight = ArrangePageGrid(self, width)
        else for _, node in ipairs(self.nodes) do Arrange(node) end end
    end)
    self.layingOut = false
    if not ok then error(failure, 0) end
    local contentWidth = width + pad * 2
    local height = gridHeight or math.max(pad * 2, y - pageGap + pad)
    self.root:SetHeight(height)
    -- 宿主回调：onHeightChanged(height) 报告真实高度；onContentWidthChanged(width) 报告真实内容宽。
    -- 两者都在布局锁释放、本次结果已落定之后才调用，回调里读 GetHeight/GetContentWidth 得到的就是这次结果。
    local heightChanged, widthChanged = self.height ~= height, self.contentWidth ~= contentWidth
    self.height, self.contentWidth = height, contentWidth
    if heightChanged and self.owner.onHeightChanged then self.owner.onHeightChanged(height) end
    if not self.alive then return end
    if widthChanged and self.owner.onContentWidthChanged then self.owner.onContentWidthChanged(contentWidth) end
end

function Session:Invalidate()
    if not self.alive or self.cleanupFailed or self.pending then return end
    self.pending = true
    C_Timer.After(0, function()
        if not self.alive then return end
        self.pending = false
        self:Layout()
    end)
end

function Session:Refresh()
    if not self.alive or self.cleanupFailed then return false end
    if self.advanced then
        local expanded = self.owner.predicates[self.advanced.expanded](nil)
        Check(type(expanded) == "boolean", "page.advanced.expanded must return ordinary boolean")
        self.expanded = expanded
    end
    for _, node in ipairs(self.nodes) do RefreshNode(node, true, true) end
    self:Invalidate()
end

-- Keep parent occupancy until all owned resources have been cleaned successfully.
function Session:Release()
    if not self.alive then return end
    self.alive = false
    local failures, root = {}, self.root
    if self.cleanupFailed then Capture(failures, false, self.cleanupFailure) end
    for _, node in ipairs(self.nodes) do Retire(node) end
    Cleanup(failures, function()
        root:SetScript("OnSizeChanged", nil)
        root:SetScript("OnHide", nil)
        root:SetScript("OnShow", nil)
    end)
    for _, node in ipairs(self.nodes) do ReleaseNode(node, failures) end
    self.nodes = {}
    Cleanup(failures, root.Hide, root)
    if not failures.failed then Cleanup(failures, Factory.ReleaseCompositeHost, Factory, root) end
    if not failures.failed and Mounted[self.parent] == self then Mounted[self.parent] = nil end
    self.root = nil
    Rethrow(failures)
end

-- 记录表格：把 rowActions / addAction 展开成普通的格与按钮（校验已在展开前做完）。
-- 操作列由 Core 追加在最后，宽度按按钮文字算；新增按钮放在首行的最后一格，
-- addAction.input 给出时，同一行第一格放这个输入框（输入和添加在同一行）。
-- 按行绑定的列表（写了 op）：样式页里 op 行操作画成图标按钮（上移 / 下移 / 删除，文字进悬停提示），
-- op = add 的新增行放在表格最下面；表格标 _rowsBound，列宽按控件分（见 TableColumns）。
local function ActionCell(id, buttons)
    return { kind = "cell", id = id, children = { { kind = "row", id = id .. ".line", children = buttons } } }
end

local function ExpandTables(node, styled)
    if type(node) ~= "table" then return end
    if node.kind == "table" and (node.rowActions or node.addAction) then
        local hasActions = node.rowActions ~= nil
        if hasActions then node.columns[#node.columns + 1] = { title = _G.ExwindTools.L["操作"], actions = true } end
        local bound = node.children[1]
        node._rowsBound = #node.children == 1 and type(bound) == "table" and bound.kind == "repeat" and bound.path ~= nil or nil
        local function Extend(row)
            local buttons = {}
            for i, action in ipairs(node.rowActions) do
                if styled and action.op then
                    local icon = ({ up = "arrow-up", down = "arrow-down", remove = "trash-2" })[action.op]
                    buttons[i] = { kind = "button", id = action.id, text = "", icon = icon, tip = action.text,
                        _op = action.op, enabled = action.enabled }
                else
                    buttons[i] = { kind = "button", id = action.id, text = action.text, action = action.action, _op = action.op,
                        enabled = action.enabled, presentation = action.presentation, _compact = true }
                end
            end
            row.children[#row.children + 1] = ActionCell(node.id .. ".actions", buttons)
        end
        for _, child in ipairs(node.children) do
            if hasActions then Extend(child.kind == "repeat" and child.template or child) end
        end
        if node.addAction then
            local add = node.addAction
            local rows = add.op and node.children[1] -- op = add：校验保证只有一个写了 path 的 repeat
            local cells = {}
            for i = 1, #node.columns - 1 do
                cells[i] = { kind = "cell", id = node.id .. ".add." .. i, children = { { kind = "text", id = node.id .. ".add." .. i .. ".text", text = "" } } }
            end
            if add.input then
                cells[1].children[1] = { kind = "control", id = add.id .. ".input", controlType = "input", ref = add.input }
            end
            cells[#node.columns] = ActionCell(node.id .. ".add", { { kind = "button", id = add.id, text = add.text,
                action = add.action, clickKey = add.clickKey, presentation = "primary", _compact = true,
                _op = add.op, _arrayPath = rows and rows.path, _rowDefaults = rows and rows.rowDefaults } })
            -- 预设 tableAddLast：新增按钮一律排在所有记录行下面（表头、记录、新增依次往下）。
            local last = add.op or (type(styled) == "table" and styled.tableAddLast)
            table.insert(node.children, last and #node.children + 1 or 1, { kind = "row", id = node.id .. ".add.row", children = cells })
        end
        node.rowActions, node.addAction = nil, nil
    end
    for _, field in ipairs({ "children", "cards" }) do
        for _, child in ipairs(type(node[field]) == "table" and node[field] or {}) do ExpandTables(child, styled) end
    end
    if node.template then ExpandTables(node.template, styled) end
end

function UI:MountSettingsDeclarationV2(parent, declaration, owner)
    local ok, issue, strict = Validate(declaration, owner)
    if not ok then return nil, issue end
    ReportStrict(owner and owner.binding and owner.binding.moduleKey or "page", strict)
    if (type(parent) ~= "table" and type(parent) ~= "userdata") or type(parent.GetWidth) ~= "function" or type(owner) ~= "table" then
        local _, invalid = Issue("parent", "parent and owner required", nil, "INVALID_ARGUMENT")
        return nil, invalid
    end
    if Mounted[parent] then
        local _, invalid = Issue("parent", "parent already owns a V2 session or failed cleanup", nil, "INVALID_ARGUMENT")
        return nil, invalid
    end
    declaration = DeclarationCopy(declaration, {})
    ExpandTables(declaration, declaration.style ~= nil and GM.settings.styles[declaration.style])
    local session = setmetatable({ alive=true, owner=owner, nodes={}, layout=declaration.layout, parent=parent,
        columns=declaration.columns, columnGap=declaration.columnGap, rowGap=declaration.rowGap,
        style=declaration.style and GM.settings.styles[declaration.style], advanced=declaration.advanced,
        collapse=declaration.collapse,
        -- 词条小框内部挂的页：owner._exQuick = "popover"。
        quick=rawget(owner, "_exQuick") }, { __index=Session })
    session.root = Acquire(parent)
    Mounted[parent] = session
    session.root:SetPoint("TOPLEFT")
    session.root:SetPoint("TOPRIGHT")
    session.root:SetScript("OnSizeChanged", function(_, width)
        if session.width ~= width then session.width = width; session:Invalidate() end
    end)
    session.root:SetScript("OnHide", function()
        if not session.alive then return end
        for _, node in ipairs(session.nodes) do HideNode(node) end
    end)
    session.root:SetScript("OnShow", function() session:Refresh() end)
    local mounted, failure = pcall(function()
        for _, spec in ipairs(declaration.cards) do Build(session, spec, session.root) end
        -- 渐进披露：整页一行“高级 ›”，排在最后一张卡片之后。
        if session.advanced then Build(session, { kind = "_more", id = "_more", visible = session.advanced.visible }, session.root) end
        session:Refresh()
        session:Layout()
    end)
    if not mounted then
        local released, releaseFailure = pcall(function() session:Release() end)
        error(tostring(failure) .. (released and "" or "\nRelease: " .. tostring(releaseFailure)), 0)
    end
    return session
end

function UI:MountSettingsPageV2(parent, pageId, owner)
    local declaration = Pages[pageId]
    Check(declaration ~= nil, "unregistered page " .. tostring(pageId))
    local session, issue = self:MountSettingsDeclarationV2(parent, declaration, owner)
    Check(session ~= nil, issue and (issue.path .. ": " .. issue.message))
    return session
end

-- =========================================================
-- 二级面板外壳：所有二级面板只用这一种浮窗。
-- UI:OpenSettingsPanelV2(spec, owner, anchor)
--   spec（纯数据）:
--     size     = "small" | "large" | "fit"（只有档位，像素在 GM.settings.parts.panelSmall*/panelLarge*）；
--                fit = 宽同 large，高随内容，最高不超过 maxHeight（不写取 large 的高）和屏幕高，再高就滚动
--     maxHeight = fit 面板的最高高度（可选，数字，只给 fit 用）
--     title    = 标题栏文字（可选）
--     page     = 已登记的页面 ID，或 declaration = V2 页面声明（二选一），内容照普通页挂载，超高时滚动
--     buttons  = 底栏动作按钮（可选，靠右从左到右排）：{ { id, text, action = actions 引用名,
--                presentation = "primary" | "secondary" | "danger"（可选） }, ... }；点击调用 actions[action](panel, mouseButton)
--     close    = actions 引用名（可选）：点 × 时调用 actions[close](panel)，由 owner 收尾后 panel:Release()；不写时 × 直接关掉
--     window   = 浮窗外观（可选）：{ background = "panel", padding = 数字, dragAnywhere, clampToScreen,
--                onDragStop = function(panel, x, y) }，同 CreateFloatingWindow 的同名选项（onDragStop 第一个参数换成 panel）
--   owner：同页面 owner（predicates / actions / binding ...）。
--   anchor（可选框体）：面板贴在它旁边，右边放不下换左、上、下，最后夹在屏幕内；不写时屏幕居中。
-- 返回 panel：panel.window、panel.session、panel:Refresh()、panel:SetTitle(text)、panel:SetAnchor(frame)、panel:Release()。
-- =========================================================
local PanelSizes = { small = true, large = true, fit = true }
local PanelPresentations = { primary = true, secondary = true, danger = true }

local function ValidatePanel(spec, owner)
    Keys(spec, "size title page declaration buttons close maxHeight window", "panel")
    Check(spec.window == nil or type(spec.window) == "table", "panel.window must be a table")
    if spec.window then
        Keys(spec.window, "background padding dragAnywhere clampToScreen onDragStop", "panel.window")
        Check(spec.window.onDragStop == nil or type(spec.window.onDragStop) == "function", "panel.window.onDragStop must be a function")
    end
    Check(PanelSizes[spec.size], "panel.size must be small, large or fit")
    Check(spec.maxHeight == nil or (spec.size == "fit" and type(spec.maxHeight) == "number" and spec.maxHeight > 0),
        "panel.maxHeight must be a positive number and only for size=fit")
    Check(spec.title == nil or type(spec.title) == "string", "panel.title must be a string")
    Check((spec.page ~= nil) ~= (spec.declaration ~= nil), "panel requires page or declaration")
    Check(spec.page == nil or Pages[spec.page] ~= nil, "panel.page is not a registered page")
    Check(type(owner) == "table", "panel requires owner")
    if spec.close ~= nil then Reference(owner, "actions", spec.close, "panel.close") end
    if spec.buttons ~= nil then
        local ids = {}
        for i = 1, Array(spec.buttons, "panel.buttons") do
            local button, at = spec.buttons[i], "panel.buttons[" .. i .. "]"
            Keys(button, "id text action presentation", at)
            Check(Name(button.id) and not ids[button.id], at .. ": missing/duplicate id")
            ids[button.id] = true
            Check(Name(button.text), at .. ": text required")
            Reference(owner, "actions", button.action, at .. ".action")
            Check(button.presentation == nil or PanelPresentations[button.presentation], at .. ": invalid presentation")
        end
    end
end

-- 滚动区与底栏建在借来的浮窗本身上（浮窗归还时只清理 content 下的子对象），每个浮窗只建一次，面板关闭时收起。
local function PanelParts(window)
    if window._v2PanelScroll then return window._v2PanelScroll, window._v2PanelFooter end
    local scrollFrame = UI:CreateScrollFrame(window)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame._v2Content = content
    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        self._v2Content:SetWidth(math.max(1, width - self:GetVerticalScrollInset()))
    end)
    local footer = CreateFrame("Frame", nil, window)
    window._v2PanelScroll, window._v2PanelFooter = scrollFrame, footer
    return scrollFrame, footer
end

function UI:OpenSettingsPanelV2(spec, owner, anchor)
    ValidatePanel(spec, owner)
    Check(anchor == nil or (type(anchor) == "table" and type(anchor.GetRect) == "function"), "panel anchor must be a frame")
    local fit = spec.size == "fit"
    local large = spec.size == "large" or fit
    local panel = { alive = true }
    local window = UI:CreateFloatingWindow({
        width = Part(nil, large and "panelLargeWidth" or "panelSmallWidth"),
        height = Part(nil, large and "panelLargeHeight" or "panelSmallHeight"),
        title = spec.title, closable = true, background = spec.window and spec.window.background,
        padding = spec.window and spec.window.padding,
        dragAnywhere = spec.window and spec.window.dragAnywhere, clampToScreen = spec.window and spec.window.clampToScreen,
        onDragStop = spec.window and spec.window.onDragStop and function(_, x, y) spec.window.onDragStop(panel, x, y) end,
        onCloseRequested = function()
            if not panel.alive then return end
            if spec.close then owner.actions[spec.close](panel) else panel:Release() end
        end,
    })
    panel.window = window
    local scrollFrame, footer = PanelParts(window)
    local footerHeight = spec.buttons and Part(nil, "panelFooterHeight") or 0
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", window.content, "BOTTOMRIGHT", -scrollFrame:GetVerticalScrollInset(), footerHeight)
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:Show()
    footer:ClearAllPoints()
    footer:SetPoint("BOTTOMLEFT", window.content, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", window.content, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(math.max(1, footerHeight))
    footer:SetShown(spec.buttons ~= nil)
    -- 面板 owner：调用方 owner 的浅拷贝，只把高度回调接到滚动区（调用方的回调照常调用）。
    local content = scrollFrame._v2Content
    local panelOwner = {}
    for key, value in pairs(owner) do panelOwner[key] = value end
    -- fit：高随内容——标题栏 + 内容 + 底栏 + 底边距，最高不超过 maxHeight（不写取 large 的高）和屏幕高；不看贴靠目标的高。
    local function FitHeight(height)
        if not fit then return end
        local screen = UIParent:GetHeight() * UIParent:GetEffectiveScale() / window:GetEffectiveScale()
        local most = math.min(spec.maxHeight or Part(nil, "panelLargeHeight"), screen)
        local chrome = GM.size.floatingHeaderHeight + footerHeight + window.contentPadding
        window:SetHeight(math.max(1, math.min(most, chrome + height)))
        if window._exFloatAnchor then window:SetAnchor(window._exFloatAnchor) end
    end
    panelOwner.onHeightChanged = function(height)
        content:SetHeight(math.max(1, height))
        scrollFrame:UpdateScrollChildRect()
        FitHeight(height)
        if owner.onHeightChanged then owner.onHeightChanged(height) end
    end
    content:SetWidth(math.max(1, (scrollFrame:GetWidth() or 1) - scrollFrame:GetVerticalScrollInset()))
    local declaration = spec.declaration or Pages[spec.page]
    local session, issue = UI:MountSettingsDeclarationV2(content, declaration, panelOwner)
    if not session then
        scrollFrame:Hide()
        footer:Hide()
        window:Release()
        Check(false, issue and (issue.path .. ": " .. issue.message) or "panel mount failed")
    end
    panel.session = session
    -- 底栏按钮：靠右排，宽按文字（不小于按钮最小宽），高取控件高。
    panel.buttons = {}
    local x, gap, height = 0, Part(nil, "panelButtonGap"), GM.size.controlHeight
    for i = #(spec.buttons or {}), 1, -1 do
        local item = spec.buttons[i]
        local button = UI:CreateButton(footer, GM.size.buttonMinWidth, height, item.text, function(_, mouseButton)
            if panel.alive then owner.actions[item.action](panel, mouseButton) end
        end, { variant = item.presentation or "secondary", compact = true })
        local label = button:GetFontString()
        local width = math.max(GM.size.buttonMinWidth,
            math.ceil(label and label:GetUnboundedStringWidth() or 0) + GM.space.buttonPaddingX * 2)
        button:SetSize(width, height)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", footer, "RIGHT", -x, 0)
        button:Show()
        x = x + width + gap
        panel.buttons[#panel.buttons + 1] = button
    end
    function panel:Refresh() if self.alive then self.session:Refresh() end end
    function panel:SetTitle(text) if self.alive then self.window:SetTitle(text) end end
    -- align = "center"（可选）：面板竖直中心线对齐目标中心（默认顶对齐）。
    function panel:SetAnchor(frame, align)
        if not self.alive then return end
        self.window:SetAnchor(frame and { frame = frame, gap = Part(nil, "panelAnchorGap"), align = align } or nil)
        if fit then FitHeight(self.session:GetHeight()) end
    end
    -- fit 面板：调用方自己用 window:SetAnchor 换了贴靠目标后调一次，重算高并按新目标重新贴靠。
    function panel:Fit()
        if self.alive and fit then FitHeight(self.session:GetHeight()) end
    end
    function panel:Release()
        if not self.alive then return end
        self.alive = false
        self.session:Release()
        for _, button in ipairs(self.buttons) do Factory:Release(button._fromPool, button) end
        self.buttons = {}
        scrollFrame:Hide()
        footer:Hide()
        self.window:Release()
        self.window, self.session = nil, nil
    end
    window:Show()
    window:RefreshDragSurfaces()
    if anchor then panel:SetAnchor(anchor) end
    return panel
end

-- =========================================================
-- 贴词小浮框用的共用框体与鼠标判断。
-- =========================================================
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local QuickFrames = {} -- 空闲的小框外框（只复用框体，不存任何选择）

local function AcquireQuickFrame()
    local frame = table.remove(QuickFrames)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame._v2Content = CreateFrame("Frame", nil, frame)
    end
    -- 不把尺寸先重置成 1×1：底板（SetControlSurface）按当时尺寸排一次，之后靠 OnSizeChanged 重排；
    -- 复用框体时“旧尺寸 → 1×1 → 同样的旧尺寸”在同一帧里不会触发 OnSizeChanged，底板就停在 1×1（看着像底板透明）。
    frame:SetClampedToScreen(true)
    frame:Show()
    return frame
end

local function RecycleQuickFrame(frame)
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    UI:SetDragAnywhere(frame, nil)
    frame._v2Dragged = nil
    frame:Hide()
    frame:ClearAllPoints()
    UI:ClearControlSurface(frame)
    QuickFrames[#QuickFrames + 1] = frame
end

-- 鼠标是否在 frame 或它的子孙上。
local function MouseInside(frame)
    if not frame then return false end
    for _, focus in ipairs(GetMouseFoci()) do
        local region = focus
        while region do
            if region == frame then return true end
            region = region.GetParent and region:GetParent() or nil
        end
    end
    return false
end

-- 鼠标是否在比 frame 更高层的弹出层上（小框里打开的下拉列表、取色器等）。
local function MouseOnHigherPopup(frame)
    local level = STRATA_ORDER[frame:GetFrameStrata()] or 0
    for _, focus in ipairs(GetMouseFoci()) do
        if focus ~= WorldFrame and focus.GetFrameStrata and (STRATA_ORDER[focus:GetFrameStrata()] or 0) > level then return true end
    end
    return MouseInside(UI.colorPicker)
end

-- =========================================================
-- 贴词小浮框：句子卡里点了词块（或任何小框体）后，贴着它弹一个无标题栏的小框，放一两个控件。
-- UI:OpenWordPopoverV2(anchor, content, owner, options)
--   anchor：贴靠的框体（例如句子卡 token action 收到的 frame）。小框在它下方，下方放不下放上方，并夹在屏幕内。
--   content：V2 页面声明（带 cards），或一组行（setting / control ... 数组，包进一张无标题卡）。照普通页挂载，写值、通知照旧。
--   owner：同页面 owner（binding / predicates / actions / sources ...）。
--   options（可选）= { style = 页面样式预设名（content 是行数组时用）, onClose = function(popover)（任何原因关掉时调一次） }。
--   options.dragAnywhere / clampToScreen / onDragStop(popover, x, y)：空白处可拖、可否拖出屏幕、拖完的位置；拖过后改高、SetAnchor 都不挪它。
-- 点小框和 anchor 以外的地方（小框里的下拉、取色器除外）、按 Esc、anchor 不再可见时自动关；
-- 页面刷新不关它（它不挂在页面里），调用方值变了想同步小框里的值就调 popover:Refresh()。同一时间只开一个，再开会先关旧的。
-- 返回 popover：popover.frame、popover.session、popover:Refresh()、popover:SetAnchor(frame)、popover:Close()。
-- 尺寸用 GM.settings.parts.quickPopoverWidth / quickPopoverPadding / quickAnchorGap（页面样式预设可覆盖）。
-- =========================================================
do
    local current -- 当前开着的贴词小框

    -- 贴在 anchor 下方，下方放不下改到上方；水平夹取交给 SetClampedToScreen。
    local function PlaceWordPopover(frame, anchor, gap)
        frame:ClearAllPoints()
        local bottom = anchor:GetBottom()
        local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if bottom and bottom * scale - gap - frame:GetHeight() < 0 then
            frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
        else
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        end
    end

    function UI:OpenWordPopoverV2(anchor, content, owner, options)
        Check(type(anchor) == "table" and type(anchor.GetRect) == "function", "贴词小框的 anchor 必须是框体")
        Check(type(content) == "table", "贴词小框的 content 要写 V2 页面声明或一组行")
        Check(type(owner) == "table", "贴词小框需要 owner")
        options = options or {}
        Keys(options, "style onClose dragAnywhere clampToScreen onDragStop", "word popover options")
        Check(options.onDragStop == nil or type(options.onDragStop) == "function", "贴词小框 options.onDragStop 要写函数")
        Check(options.onClose == nil or type(options.onClose) == "function", "贴词小框 options.onClose 要写函数")
        local declaration = content
        if content.cards == nil then
            declaration = { version = 2, style = options.style,
                cards = { { kind = "card", id = "_popover", title = "", children = content } } }
        end
        Check(declaration.style == nil or GM.settings.styles[declaration.style] ~= nil, "贴词小框的 style 不是已登记的页面样式")
        local style = declaration.style and GM.settings.styles[declaration.style]
        if current then current:Close() end
        -- 弹出小框时收起当前悬停提示。
        GameTooltip:Hide()

        local GC = _G.ExwindTools.GUIColors
        local pad, gap = Part(style, "quickPopoverPadding"), Part(style, "quickAnchorGap")
        local popover = { alive = true }
        local frame = AcquireQuickFrame()
        popover.frame = frame
        frame:Raise()
        UI:SetControlSurface(frame, GM.radius.popup, GC.popup, GC.popupBorder)
        if options.clampToScreen == false then frame:SetClampedToScreen(false) end
        if options.dragAnywhere then
            UI:SetDragAnywhere(frame, {
                onDragStart = function() frame._v2Dragged = true end,
                onDragStop = function(_, x, y)
                    if popover.alive and options.onDragStop and x then options.onDragStop(popover, x, y) end
                end,
            })
        end
        frame:SetSize(Part(style, "quickPopoverWidth"), pad * 2 + 1)
        PlaceWordPopover(frame, anchor, gap)
        local host = frame._v2Content
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
        host:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
        host:SetHeight(1)
        host:Show()
        -- owner 浅拷贝：高度回调接到小框；按小框画（不画卡面）。
        local popoverOwner = {}
        for key, value in pairs(owner) do popoverOwner[key] = value end
        popoverOwner.onContentWidthChanged = nil
        popoverOwner._exQuick = "popover"
        popoverOwner.onHeightChanged = function(height)
            if not popover.alive then return end
            frame:SetHeight(math.max(1, height) + pad * 2)
            if not frame._v2Dragged then PlaceWordPopover(frame, anchor, gap) end
        end
        local session, failure = UI:MountSettingsDeclarationV2(host, declaration, popoverOwner)
        if not session then
            RecycleQuickFrame(frame)
            Check(false, failure and (failure.path .. ": " .. failure.message) or "word popover mount failed")
        end
        popover.session = session
        current = popover

        function popover:Close()
            if not self.alive then return end
            self.alive = false
            if current == self then current = nil end
            frame:SetScript("OnUpdate", nil)
            frame:SetScript("OnKeyDown", nil)
            frame:EnableKeyboard(false)
            self.session:Release()
            RecycleQuickFrame(frame)
            self.session, self.frame = nil, nil
            if options.onClose then options.onClose(self) end
        end
        function popover:Refresh() if self.alive then self.session:Refresh() end end
        function popover:SetAnchor(target)
            if not self.alive then return end
            Check(type(target) == "table" and type(target.GetRect) == "function", "贴词小框的 anchor 必须是框体")
            anchor = target
            if not frame._v2Dragged then PlaceWordPopover(frame, anchor, gap) end
        end

        -- 点外面关（小框、anchor、小框里弹出的更高层下拉 / 取色器不算外面）。
        frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        frame:SetScript("OnEvent", function()
            if MouseInside(frame) or MouseInside(anchor) or MouseOnHigherPopup(frame) then return end
            popover:Close()
        end)
        -- anchor 不再可见（所在行被收走、面板关了）才关；页面刷新里同一帧内的隐藏再显示不算。
        frame:SetScript("OnUpdate", function()
            if not anchor:IsVisible() then popover:Close() end
        end)
        -- Esc 关：只吃 Esc，其余按键照常往下传。战斗中不接键盘（受限接口）。
        if not InCombatLockdown() then
            frame:EnableKeyboard(true)
            frame:SetPropagateKeyboardInput(true)
            frame:SetScript("OnKeyDown", function(self, key)
                if InCombatLockdown() then return end
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    popover:Close()
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)
        end
        return popover
    end
end

-- Context menus share the page reference/record rules and the existing menu painter.
local Menus, MenuSession = {}, {}
local MenuFields = {
    button = "text textSource action presentation shortcut", menu = "text textSource children",
    separator = "", ["repeat"] = "source template",
}

local function ValidateMenuNode(node, owner, ids, depth, submenuDepth)
    Check(type(node) == "table" and MenuFields[node.kind], "unknown menu node kind")
    Keys(node, "id kind visible enabled " .. MenuFields[node.kind], "menu node")
    Check(Name(node.id) and not ids[node.id], "missing/duplicate menu id " .. tostring(node.id))
    ids[node.id] = true
    for _, field in ipairs({ "visible", "enabled" }) do
        if node[field] ~= nil then Reference(owner, "predicates", node[field], node.id) end
    end
    if node.kind == "repeat" then
        Check(depth < 2, "at most two nested menu repeats")
        Reference(owner, "sources", node.source, node.id)
        ValidateMenuNode(node.template, owner, ids, depth + 1, submenuDepth)
    elseif node.kind ~= "separator" then
        Check((node.text ~= nil) ~= (node.textSource ~= nil), node.id .. ": use text or textSource")
        if node.text ~= nil then Check(type(node.text) == "string", "menu text must be string") end
        if node.textSource ~= nil then Reference(owner, "texts", node.textSource, node.id) end
        if node.kind == "button" then
            Reference(owner, "actions", node.action, node.id)
            Check(node.presentation == nil or node.presentation == "primary" or node.presentation == "secondary"
                or node.presentation == "danger", "invalid menu presentation")
            -- shortcut：菜单右侧显示的快捷键（如 "Delete"、"Ctrl+D"），只是提示，不绑定按键。
            Check(node.shortcut == nil or (type(node.shortcut) == "string" and node.shortcut ~= ""), node.id .. ": shortcut must be a non-empty string")
        else
            Check(submenuDepth < 1, "context menu supports one submenu level")
            Array(node.children, node.id .. ".children")
            for _, child in ipairs(node.children) do
                ValidateMenuNode(child, owner, ids, depth, submenuDepth + 1)
            end
        end
    end
end

local function ValidateMenu(declaration, owner)
    Keys(declaration, "version items", "menu")
    Check(declaration.version == 2, "menu version must be 2")
    Array(declaration.items, "menu items")
    local ids = {}
    for _, node in ipairs(declaration.items) do ValidateMenuNode(node, owner, ids, 0, 0) end
end

function UI:RegisterContextMenuV2(menuId, declaration)
    Check(Name(menuId) and Menus[menuId] == nil, "missing/duplicate menu id")
    local copy = DeclarationCopy(declaration, {})
    ValidateMenu(copy)
    Menus[menuId] = copy
end

function MenuSession:Release()
    if not self.alive then return end
    self.alive = false
    if self.frame and UI._contextMenu == self.frame and self.frame._v2Session == self then
        UI:HideContextMenu()
        self.frame._v2Session = nil
    end
end

function UI:ShowContextMenuV2(menuId, owner, options)
    Check(Menus[menuId] ~= nil, "unregistered menu " .. tostring(menuId))
    Check(type(owner) == "table" and type(owner.isCurrent) == "function", "menu owner requires isCurrent")
    options = options or {}
    ValidateMenu(Menus[menuId], owner)
    local previous = self._contextMenu and self._contextMenu._v2Session
    if previous then previous:Release() end
    local session = setmetatable({ alive=true, owner=owner }, { __index=MenuSession })
    local function predicate(name, scope)
        if name == nil then return true end
        local value = owner.predicates[name](scope)
        Check(type(value) == "boolean", "menu predicate must return ordinary boolean")
        return value
    end
    local function current(scope)
        if not session.alive or owner.isCurrent(scope) ~= true then return false end
        while scope do
            local records = owner.sources[scope._source](scope.parent)
            if records[scope.index] ~= scope.item then return false end
            scope = scope.parent
        end
        return true
    end
    local expand
    expand = function(nodes, scope, ancestors)
        local items = {}
        for _, node in ipairs(nodes) do
            if predicate(node.visible, scope) then
                local chain = {}
                for i, entry in ipairs(ancestors or {}) do chain[i] = entry end
                chain[#chain + 1] = { spec=node, scope=scope }
                if node.kind == "repeat" then
                    local records = owner.sources[node.source](scope)
                    Array(records, node.id .. " source")
                    local seen = {}
                    for i, record in ipairs(records) do
                        Check(type(record) == "table" and not seen[record], "menu requires unique original records")
                        seen[record] = true
                        local childScope = { item=record, index=i, parent=scope, _source=node.source }
                        for _, item in ipairs(expand({ node.template }, childScope, chain)) do
                            items[#items + 1] = item
                        end
                    end
                elseif node.kind == "separator" then
                    items[#items + 1] = { divider=true }
                else
                    local text = node.text or owner.texts[node.textSource](scope)
                    Check(type(text) == "string", "menu text source must return string")
                    local ctx = { scope=scope }
                    function ctx:IsCurrent() return current(scope) end
                    function ctx:Guard(callback)
                        Check(type(callback) == "function", "Guard expects a callback")
                        return function(...)
                            if not current(scope) then return end
                            for _, entry in ipairs(chain) do
                                if not predicate(entry.spec.visible, entry.scope)
                                    or not predicate(entry.spec.enabled, entry.scope) then return end
                            end
                            return callback(...)
                        end
                    end
                    local enabled = true
                    for _, entry in ipairs(chain) do enabled = enabled and predicate(entry.spec.enabled, entry.scope) end
                    local item = { text=text, disabled=not enabled, danger=node.presentation == "danger", shortcut=node.shortcut }
                    if node.kind == "menu" then
                        item.submenu = expand(node.children, scope, chain)
                    else
                        item.onClick = ctx:Guard(function()
                            local ok, failure = pcall(owner.actions[node.action], ctx, "LeftButton")
                            session:Release()
                            if not ok then error(failure, 0) end
                        end)
                    end
                    items[#items + 1] = item
                end
            end
        end
        return items
    end
    local items = expand(Menus[menuId].items)
    if #items == 0 or owner.isCurrent(nil) ~= true then session.alive=false; return session end
    session.frame = self:ShowContextMenu({ items=items, x=options.x, y=options.y, title=options.title })
    session.frame._v2Session = session
    return session
end
