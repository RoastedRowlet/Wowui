---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local Page = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
if not Page then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })
local GC = ExwindTools.GUIColors

-- 副本通用设置只管理副本级 options 与 AuraSound；不持有 BossPage 的选择状态。
-- 当前副本/槽位解析仍由 BossPage 主文件通过公开方法提供。
local Common = Page.DungeonCommon or {}
Page.DungeonCommon = Common

Common.MODULE_KEY = "ExBoss.BossConfig.DungeonOptions"

local UI = Common._ui or {}
Common._ui = UI
-- V2 标准控件管理页面和草稿表单；配置提交仍由下方业务入口负责。
-- 虚拟列表保持固定视口，不使用 repeat 展开全部 action。
local LAYOUT = {}
local Renderers = {}
local RaiseInteractiveChild

-- 覆盖层复用原来的 GUI 控件；V2 节点持有每次打开的交互租约和释放。
-- 记录与草稿沿用业务读写入口，控件由 Core 标准适配器创建。
local function RecordControl(owner, ref, spec, read, write)
    owner.controls[ref] = ExwindTools.UI:CreateSettingsV2Control(spec, function()
        local binding = ExwindTools.UI:CreateSettingsV2Binding(Common.MODULE_KEY, {}, ref)
        binding.Read = function() return read() end
        binding.Write = function(_, value) write(value) end
        return binding
    end)
end

local function Options(items)
    local options = {}
    for _, item in ipairs(items) do options[#options + 1] = { label = item[1], value = item[2] } end
    return options
end

local function Field(ref, controlType, visible)
    return { id = ref, kind = "control", ref = ref, controlType = controlType, visible = visible }
end

local function Setting(id, label, children, description, visible)
    return { id = id, kind = "setting", label = label, description = description,
        visible = visible, children = children }
end

local function ReleaseOverlaySession(editor)
    if editor._v2Session then
        local session = editor._v2Session
        editor._v2Session = nil
        session:Release()
    end
end

local function MountOverlaySession(editor, declaration, owner)
    ReleaseOverlaySession(editor)
    local GM = ExwindTools.GUIMetrics
    local pad = GM.space.settingsV2Padding
    local top = GM.space.dialogPaddingY + editor.title:GetStringHeight() + GM.space.dialogSectionGap
    if editor.subtitle then top = top + editor.subtitle:GetStringHeight() + GM.space.descriptionGap end
    editor.scroll:ClearAllPoints()
    editor.scroll:SetPoint("TOPLEFT", editor, "TOPLEFT", pad, -top)
    editor.scroll:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -pad - editor.scroll:GetVerticalScrollInset(),
        pad + GM.size.controlHeight)
    editor._v2Host:SetWidth(editor.scroll:GetWidth())
    editor.scroll:SetVerticalScroll(0)
    owner.onHeightChanged = function(height)
        editor._v2Host:SetHeight(height)
        editor:SetHeight(math.min(height + top + pad + GM.size.controlHeight,
            UIParent:GetHeight() - GM.space.dialogPaddingY * 2))
    end
    editor._v2Session = ExwindTools.UI:MountSettingsDeclarationV2(editor._v2Host, declaration, owner)
end

local function ResolvePackPreviewPath(label)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and engine.ResolveStandaloneSound) then return nil end
    local info = engine:ResolveStandaloneSound(
        { enabled = true, sourceType = "pack", label = tostring(label or "") },
        { triggerIndex = 0, ignoreState = true })
    return info and info.file or nil
end

-- 方案 A 的视觉令牌。这里只影响 Frame/Texture/FontString 的表现，AuraSound
-- 的 action ID、字段结构、SavedVariables 与运行时调用链均保持原样。
local AURA_UI_THEME = {
    canvas = GC.panel,
    panel = GC.card,
    panelDeep = GC.input,
    panelHover = GC.headerHover,
    ink = GC.text,
    muted = GC.textDim,
    line = GC.headerDivider,
    lineStrong = GC.panelBorder,
    gold = GC.accent,
    cyan = GC.accentHover,
    success = { 0.420, 0.900, 0.650, 1.00 },
    danger = { 0.937, 0.498, 0.490, 1.00 },
}

local AURA_FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function SetAuraThemeText(fontString, color)
    if not (fontString and color) then return end
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function CreateAuraPrototypeButton(parent, width, height, label, callback)
    return ExwindTools.UI:CreateButton(parent, width, height, label, callback,
        { variant = "secondary", compact = true })
end

RaiseInteractiveChild = function(frame, parent, levelOffset)
    if not (frame and parent) then return end
    local strata = parent.GetFrameStrata and parent:GetFrameStrata() or "DIALOG"
    local level = (parent.GetFrameLevel and parent:GetFrameLevel() or 0) + (levelOffset or 1)
    if frame.SetFrameStrata then frame:SetFrameStrata(strata) end
    if frame.SetFrameLevel then frame:SetFrameLevel(level) end
    if frame.checkbox then
        if frame.checkbox.SetFrameStrata then frame.checkbox:SetFrameStrata(strata) end
        if frame.checkbox.SetFrameLevel then frame.checkbox:SetFrameLevel(level + 1) end
    end
end

local function PositionVoiceEditor(editor, parent)
    if not (editor and parent) then return end
    -- 浮层挂到宿主所在的顶层窗口下：独立于页面滚动裁切，且窗口被点击置顶时一起抬起。
    local host = parent
    while host:GetParent() and host:GetParent() ~= UIParent do host = host:GetParent() end
    editor:SetParent(host)
    editor:SetScale(parent:GetEffectiveScale() / host:GetEffectiveScale())
    editor:ClearAllPoints()
    editor:SetPoint("CENTER", parent, "CENTER")
    editor:SetFrameStrata("DIALOG")
    editor:SetFrameLevel(math.max(UI.gridHost and UI.gridHost:GetFrameLevel() or 0, parent:GetFrameLevel()) + 50)
    RaiseInteractiveChild(editor.close, editor, 2)
end

local function CreateVoiceOverlay(parent, close)
    local EXUI, GM = ExwindTools.UI, ExwindTools.GUIMetrics
    local pad = GM.space.settingsV2Padding
    local editor = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    editor:SetWidth(math.min(parent:GetWidth(), UIParent:GetWidth()) - GM.space.dialogPaddingX * 2)
    editor:SetHeight(GM.settings.rowMinHeight)
    editor:SetBackdrop(AURA_FLAT_BACKDROP)
    editor:SetBackdropColor(unpack(GC.popup))
    editor:SetBackdropBorderColor(unpack(GC.popupBorder))
    editor:Hide()
    editor.title = EXUI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontNormalLarge")
    editor.title:SetPoint("TOPLEFT", GM.space.dialogPaddingX, -GM.space.dialogPaddingY)
    editor.title:SetPoint("TOPRIGHT", -GM.space.dialogPaddingX - GM.size.controlHeight, -GM.space.dialogPaddingY)
    editor.title:SetJustifyH("LEFT")
    editor.title:SetWordWrap(true)
    editor.title:SetTextColor(unpack(GC.text))
    editor.close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    editor.close:SetSize(GM.size.controlHeight, GM.size.controlHeight)
    editor.close:SetPoint("TOPRIGHT")
    editor.close:SetScript("OnClick", function() close(editor) end)
    editor.error = EXUI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontNormalSmall")
    editor.error:SetPoint("BOTTOMLEFT", pad, pad)
    editor.error:SetPoint("BOTTOMRIGHT", -pad, pad)
    editor.error:SetTextColor(unpack(GC.dangerText))
    editor.error:SetWordWrap(true)
    editor.scroll = EXUI:CreateScrollFrame(editor)
    editor._v2Host = CreateFrame("Frame", nil, editor.scroll)
    editor._v2Host:SetHeight(GM.settings.rowMinHeight)
    editor.scroll:SetScrollChild(editor._v2Host)
    editor:SetScript("OnHide", function(frame) ReleaseOverlaySession(frame) end)
    PositionVoiceEditor(editor, parent)
    return editor
end

local AURA_SOUND_SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
    { L["自定义路径"], "file" },
}

function Common.GetAuraSoundSourceLabel(sourceType)
    if sourceType == "lsm" then return L["LSM音效"] end
    if sourceType == "file" then return L["自定义路径"] end
    return L["语音包标签"]
end

local AURA_UNIT_ITEMS = {
    { L["玩家"], "player" },
    { L["队友"], "party" },
    { L["怪物"], "enemy" },
}

local AURA_TYPE_ITEMS = {
    { L["减益"], "debuff" },
    { L["增益"], "buff" },
}

local AURA_TYPE_LABELS = {
    buff = L["增益"],
    debuff = L["减益"],
}

local AURA_TYPE_COLORS = {
    buff = { 0.42, 0.90, 0.65 },
    debuff = { 1.00, 0.38, 0.34 },
}

local AURA_UNIT_LABELS = {
    player = L["玩家"],
    party = L["队友"],
    enemy = L["怪物"],
}

local AURA_UNIT_COLORS = {
    player = { 0.70, 0.84, 1.00 },
    party = { 0.84, 0.66, 1.00 },
    enemy = { 1.00, 0.70, 0.34 },
}

local AURA_TRIGGER_ITEMS = {
    { L["添加"], "added" },
    { L["堆叠"], "applicationsIncreased" },
    { L["移除"], "removed" },
}

local AURA_TRIGGER_LABELS = {
    added = L["添加"],
    applicationsIncreased = L["堆叠"],
    removed = L["移除"],
}

-- 状态是规则表的重要扫描线索：新增绿、叠层黄、移除红。行首细条则由
-- BUFF/DEBUFF 单独表达，避免一个颜色承担两种语义。
local AURA_TRIGGER_COLORS = {
    added = { 0.42, 0.95, 0.70 },
    applicationsIncreased = { 1.00, 0.78, 0.24 },
    removed = { 1.00, 0.38, 0.34 },
}

local AURA_CATEGORY_LABELS = {
    uncategorized = L["未分类"],
    targeted = L["被点名"],
    stack = L["叠层危险"],
    dispel = L["驱散"],
    defensive = L["减伤"],
}

-- 顶部快捷卡只是当前常用分类的入口，不是 AuraSound 分类的完整枚举。
-- category 仍然是 action 自身的开放字符串，列表和编辑器会原样保留所有其他分类。
local AURA_CATEGORY_SHORTCUTS = {
    { key = "地板", label = L["地板"], hint = L["踩到可以规避的地板技能"], color = { 0.941, 0.733, 0.341 }, icon = 132886 },
    { key = "错误", label = L["错误"], hint = L["漏断/没有转火等"], color = { 0.937, 0.498, 0.490 }, icon = 136243 },
    { key = "坦克", label = L["坦克"], hint = L["所有与坦克相关的"], color = { 0.404, 0.780, 0.949 }, icon = 132341 },
}
local AURA_CATEGORY_SHORTCUTS_BY_KEY = {}
for _, category in ipairs(AURA_CATEGORY_SHORTCUTS) do
    AURA_CATEGORY_SHORTCUTS_BY_KEY[category.key] = category
end

local function GetAuraSoundTarget(row)
    row = type(row) == "table" and row or {}
    local unit = row.unit == "party" and "party" or row.unit == "enemy" and "enemy" or "player"
    local auraType = row.auraType == "buff" and "buff" or "debuff"
    return unit, auraType
end

function Common.GetAuraSoundUnitLabel(row)
    local unit = GetAuraSoundTarget(row)
    return AURA_UNIT_LABELS[unit] or L["玩家"]
end

local function NormalizeAuraSoundItem(row)
    row = type(row) == "table" and row or {}
    row.spellID = tonumber(row.spellID) or 0
    local unit, auraType = GetAuraSoundTarget(row)
    row.unit = unit
    row.auraType = auraType
    row.trigger = AURA_TRIGGER_LABELS[row.trigger] and row.trigger or "added"
    row.category = tostring(row.category or "uncategorized")
    if row.category == "" then row.category = "uncategorized" end
    row.sourceType = row.sourceType == "lsm" and "lsm" or row.sourceType == "file" and "file" or "pack"
    row.label = tostring(row.label or "")
    row.customLSM = tostring(row.customLSM or "")
    row.customPath = tostring(row.customPath or "")
    row.outputChannel = tostring(row.outputChannel or "Master")
    return row
end

local AURA_ACTION_FIELDS = {
    "spellID", "unit", "auraType", "category", "trigger", "enabled",
    "sourceType", "label", "customLSM", "customPath", "outputChannel",
}
local AURA_ACTION_FIELD_SET = {}
for _, field in ipairs(AURA_ACTION_FIELDS) do AURA_ACTION_FIELD_SET[field] = true end

-- 新增自定义 action 才需要一条完整记录；既有 action 的保存会把这个草稿
-- 与打开时的值逐字段比较，只写用户实际改动的叶子。
local function BuildPersistedAuraSoundItem(row)
    local view = {}
    if type(row) == "table" then
        for _, key in ipairs(AURA_ACTION_FIELDS) do view[key] = row[key] end
    end
    row = NormalizeAuraSoundItem(view)
    local stored = {
        spellID = tonumber(row.spellID) or 0,
        unit = select(1, GetAuraSoundTarget(row)),
        auraType = select(2, GetAuraSoundTarget(row)),
        category = tostring(row.category or "uncategorized"),
        trigger = tostring(row.trigger or "added"),
        sourceType = row.sourceType == "lsm" and "lsm" or row.sourceType == "file" and "file" or "pack",
        label = tostring(row.label or ""),
        customLSM = tostring(row.customLSM or ""),
        customPath = tostring(row.customPath or ""),
        outputChannel = tostring(row.outputChannel or "Master"),
    }
    -- 完整 action 草稿必须显式携带 enabled；省略正常启用会被严格 schema
    -- 当成字段不完整，导致 catalog 编辑和用户新增被拒绝。
    stored.enabled = row.enabled ~= false
    return stored
end

local AURA_VIEW_FIELDS = {
    "spellID", "unit", "auraType", "category", "trigger", "enabled",
    "sourceType", "label", "customLSM", "customPath", "outputChannel", "displayName", "iconFileID",
}

-- 虚拟列表只保留渲染所需标量；绝不将 Factory 的嵌套展示元数据挂在复用行上。
local function GetAuraSoundItemView(row)
    local view = {}
    if type(row) == "table" then
        for _, key in ipairs(AURA_VIEW_FIELDS) do view[key] = row[key] end
    end
    return NormalizeAuraSoundItem(view)
end

-- 编辑器永远操作草稿。声音配置目前都是标量字段，但这里仍使用独立拷贝，
-- 防止以后增加嵌套元数据时把 SavedVariables 意外带入编辑过程。
local function CopyAuraSoundItem(row)
    local copy = {}
    if type(row) == "table" then
        -- 编辑器只持有一条可编辑 action 草稿。尤其不能复制 Factory 的
        -- sourceNPCIDs/sourceNames 等展示表，否则每次编辑又把静态资料带进 UI。
        for _, key in ipairs({
            "spellID", "unit", "auraType", "category", "trigger", "enabled",
            "sourceType", "label", "customLSM", "customPath", "outputChannel", "catalogKey",
            "displayName", "iconFileID",
        }) do
            copy[key] = row[key]
        end
    end
    return copy
end

local function GetAuraSpellInfo(row)
    local spellID = tonumber(row and row.spellID) or 0
    local name, icon
    if spellID > 0 and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            name, icon = info.name, info.iconID
        end
    end
    if (not name or name == "") and spellID > 0 and type(GetSpellInfo) == "function" then
        name, _, icon = GetSpellInfo(spellID)
    end
    -- Resolved catalog rows may carry Factory display metadata for spell-info
    -- cache misses; it is never an independent AuraSound data source.
    if not name or name == "" then
        name = tostring(row and (row.displayName or row.name) or "")
    end
    if not icon then
        icon = tonumber(row and row.iconFileID)
    end
    if (not name or name == "") and spellID <= 0 then
        name = L["自定义光环（待填写）"]
    end
    return tostring((name and name ~= "") and name or (L["法术 "] .. tostring(spellID))), tonumber(icon) or 134400, spellID
end

function Common.GetAuraSoundCategoryLabel(category)
    category = tostring(category or "")
    if category == "" then category = "uncategorized" end
    return AURA_CATEGORY_LABELS[category] or L[category] or category
end

function Common.GetAuraSoundTriggerLabel(trigger)
    return AURA_TRIGGER_LABELS[trigger] or L["添加"]
end

function Common.GetAuraSoundDisplayName(row)
    row = type(row) == "table" and row or {}
    local sourceType = tostring(row.sourceType or "pack")
    local value = sourceType == "lsm" and tostring(row.customLSM or "")
        or sourceType == "file" and tostring(row.customPath or "")
        or tostring(row.label or "")
    if value == "" then return L["未选择"] end

    -- 语音包保存的是跨语言稳定的原始标签；显示时才按当前客户端语言转换，
    -- 与 BOSS 语音页面的下拉项保持一致。LSM 名称及自定义路径则原样显示。
    return sourceType == "pack" and (L[value] or value) or value
end

local function HasAuraSoundSelection(row)
    row = type(row) == "table" and row or {}
    if row.sourceType == "lsm" then return tostring(row.customLSM or "") ~= "" end
    if row.sourceType == "file" then return tostring(row.customPath or "") ~= "" end
    return tostring(row.label or "") ~= ""
end

function Common.SetAuraSoundDropdownText(dropdown, text)
    if not dropdown then return end
    local value = text or L["请选择..."]
    if dropdown.OverrideText then
        dropdown:OverrideText(value)
    elseif dropdown.SetText then
        dropdown:SetText(value)
    end
end

function Common.GetAuraSoundPackItems()
    local catalog = ExBoss and ExBoss.Voice and ExBoss.Voice.LabelCatalog
    if type(catalog) == "table" and type(catalog.GetDropdownItems) == "function" then
        local items = catalog.GetDropdownItems()
        if type(items) == "table" then return items end
    end
    return {}
end

-- 设置页只拿轻量 ID View；Action View 只在可视行/编辑器按需取得。
-- UI 绝不能持有完整 auraSounds 根。
local function GetAuraSoundView(dungeonKey, slotKey)
    local cfg = ExBoss and ExBoss.BossConfig
    if not (cfg and type(cfg.GetMplusDungeonAuraSoundView) == "function") then return nil end
    return cfg:GetMplusDungeonAuraSoundView(dungeonKey, slotKey)
end

local function GetAuraSoundActionView(dungeonKey, slotKey, actionID)
    local cfg = ExBoss and ExBoss.BossConfig
    if not (cfg and type(cfg.GetMplusDungeonAuraSoundActionView) == "function") then return nil end
    return cfg:GetMplusDungeonAuraSoundActionView(dungeonKey, actionID, slotKey)
end

local function SetAuraSoundActionFields(dungeonKey, slotKey, actionID, fields)
    local cfg = ExBoss and ExBoss.BossConfig
    if not (cfg and type(cfg.SetMplusDungeonAuraSoundActionFields) == "function") then
        return false, "M+ Aura action fields API unavailable"
    end
    return cfg:SetMplusDungeonAuraSoundActionFields(slotKey, dungeonKey, actionID, fields)
end

local function SetAuraSoundActionsEnabled(dungeonKey, slotKey, actionIDs, enabled)
    local cfg = ExBoss and ExBoss.BossConfig
    if not (cfg and type(cfg.SetMplusDungeonAuraSoundActionsEnabled) == "function") then
        return false, "M+ Aura action batch API unavailable", 0
    end
    return cfg:SetMplusDungeonAuraSoundActionsEnabled(slotKey, dungeonKey, actionIDs, enabled)
end

local function CreateAuraSoundAction(dungeonKey, slotKey, actionID, action)
    local cfg = ExBoss and ExBoss.BossConfig
    if not (cfg and type(cfg.CreateMplusDungeonAuraSoundAction) == "function") then
        return false, "M+ Aura action create API unavailable"
    end
    return cfg:CreateMplusDungeonAuraSoundAction(slotKey, dungeonKey, actionID, action)
end

-- V2 释放组件时会清掉 list.context。稳定上下文只保留三个
-- 标量，不保存 db/root；刷新时可重新取得轻量 View。
local function CacheAuraSoundVirtualContext(dungeonKey, slotKey, host)
    local cached = UI.auraSoundVirtualContext or {}
    if dungeonKey ~= nil and tostring(dungeonKey) ~= "" then
        cached.dungeonKey = tostring(dungeonKey)
    end
    if slotKey ~= nil and tostring(slotKey) ~= "" then cached.slotKey = tostring(slotKey) end
    if host then cached.host = host end
    UI.auraSoundVirtualContext = cached
    return cached
end

local function NormalizeAuraSoundSearchText(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

local function AuraSoundRowMatchesSearch(row, needle)
    if needle == "" then return true end
    row = GetAuraSoundItemView(row)
    local name = select(1, GetAuraSpellInfo(row))
    local source = table.concat({
        tostring(name or ""),
        tostring(row.spellID or ""),
    }, " "):lower()
    return source:find(needle, 1, true) ~= nil
end

-- 分类筛选只是本页的临时视图状态。它从不进入 action 草稿或 SavedVariables，
-- 因而切换卡片、下拉、搜索都不会改变任何光环声音资料。
local AURA_CATEGORY_FILTER_MAX_CARDS = 10
local AURA_CATEGORY_FILTER_OTHER = "__exboss_other_aura_categories__"

local function NormalizeAuraSoundCategoryFilter(categoryKey)
    return tostring(categoryKey or "")
end

local function AuraSoundRowMatchesCategoryFilter(row, categoryKey)
    categoryKey = NormalizeAuraSoundCategoryFilter(categoryKey)
    if categoryKey == "" then return true end
    row = GetAuraSoundItemView(row)
    if categoryKey == AURA_CATEGORY_FILTER_OTHER then
        local otherKeys = UI.auraSoundCategoryOtherKeys
        return type(otherKeys) == "table" and otherKeys[row.category] == true
    end
    return row.category == categoryKey
end

-- 只刷新下方虚拟列表。分类切换和搜索都属于临时筛选，不能借用“资料保存后”
-- 的完整刷新路径，否则顶部卡片会被反复统计/绘制，造成肉眼可见的闪烁。
function Common:RefreshAuraSoundFilteredList()
    local list = UI.auraSoundVirtualList
    if not list then return end
    local context = list.context
    local cached = UI.auraSoundVirtualContext
    local dungeonKey = (context and context.dungeonKey) or (cached and cached.dungeonKey)
    local slotKey = (context and context.slotKey) or (cached and cached.slotKey)
    if dungeonKey and slotKey then
        Common.UpdateAuraSoundVirtualList((cached and cached.host) or list:GetParent(), {
            element = {
                dungeonKey = dungeonKey,
                slotKey = slotKey,
            },
        })
    elseif list.Refresh then
        list:Refresh()
    end
end

function Common:RefreshAuraSoundRows()
    -- 仅在 action 真正保存、归类或声音真正改变后才重新计算卡片摘要。
    Common:RefreshAuraSoundCategoryCards()
    Common:RefreshAuraSoundFilteredList()
end

function Common:RefreshAuraSoundVisibleRow(actionID)
    local list = UI.auraSoundVirtualList
    local wanted = tostring(actionID or "")
    if not list or wanted == "" then return end
    for _, row in ipairs(list.rows or {}) do
        local binding = row._auraSoundBinding
        if binding and binding.itemID == wanted then
            local current = GetAuraSoundActionView(binding.dungeonKey, binding.slotKey, wanted)
            if type(current) == "table" then
                binding.item = GetAuraSoundItemView(current)
                Common.RefreshAuraSoundVirtualRow(row)
            else
                row._auraSoundBinding = nil
                row:Hide()
            end
            return
        end
    end
end

-- Action、分类、增减益类型、触发状态与声音使用固定独立列。单位仍只参与
-- 搜索和运行时匹配，不在紧凑列表中重复显示。
-- [混合函数边界] 这里只可迁移列宽/锚点；action/category/auraType/trigger/voice 列身份与顺序禁止修改。
local AURA_SOUND_ROW_HEIGHT = 40
local AURA_SOUND_VISIBLE_ROWS = 13
local AURA_SOUND_LIST_HEIGHT = AURA_SOUND_ROW_HEIGHT * AURA_SOUND_VISIBLE_ROWS

local function AuraSoundTableColumns(width)
    local GM, EXUI = ExwindTools.GUIMetrics, ExwindTools.UI
    return {
        { title = "", width = GM.size.controlHeight },
        { title = L["光环 Action"] },
        { title = L["分类"], width = GM.settings.controlMinWidth },
        { title = L["光环类型"], width = GM.settings.controlShortWidth },
        { title = L["状态"], width = GM.settings.controlShortWidth },
        { title = L["当前声音"] },
        { title = "", width = EXUI:MeasureButtonWidth(L["试听"]) },
        { title = "", width = EXUI:MeasureButtonWidth(L["编辑"]) },
    }
end

local function LayoutAuraSoundColumns(frame, parts)
    if not (frame and parts) then return end
    local EXUI = ExwindTools.UI
    -- Header and virtual rows both reserve the list's 12px scrollbar strip.
    local width = math.max(1, frame:GetWidth() - (parts == frame and 0 or 12))
    local columns = AuraSoundTableColumns(width)
    local rects = EXUI:ResolveSettingsTableColumns(width, columns)
    local function Place(region, index, inset, right)
        local rect = rects[index]
        region:ClearAllPoints()
        region:SetPoint("LEFT", frame, "LEFT", rect.x + (inset or 4), 0)
        region:SetWidth(math.max(1, rect.width - (inset or 4) - (right or 4)))
    end
    if parts == frame then
        EXUI:UpdateSettingsTableRowLayout(frame, width, rects, { { height = 28 } })
        -- The shared table defaults to 48px; this virtual list owns its row pitch.
        -- Restore it before centering controls; the divider follows the bottom.
        frame:SetHeight(AURA_SOUND_ROW_HEIGHT)
    elseif frame._auraSoundPublicHeader then
        local header = frame._auraSoundPublicHeader
        header._exSettingsTableColumns = columns
        EXUI:UpdateSettingsTableHeaderLayout(header, width)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT")
    end
    if parts.check then Place(parts.check, 1, 0, 0) end
    if parts.icon then
        local iconHost = parts.iconFrame or parts.icon
        Place(iconHost, 2, 4, 4)
        iconHost:SetWidth(28)
    end
    Place(parts.title, 2, 38, 4)
    if parts.unit then parts.unit:Hide() end
    local category = parts.categoryPill or parts.category
    Place(category, 3)
    if parts.categoryPill then
        category:SetHeight(24)
        parts.category:ClearAllPoints()
        parts.category:SetPoint("LEFT", category, "LEFT", 14, 0)
        parts.category:SetPoint("RIGHT", category, "RIGHT", -4, 0)
        parts.categoryDot:ClearAllPoints()
        parts.categoryDot:SetPoint("LEFT", category, "LEFT", 4, 0)
    end
    Place(parts.auraType, 4)
    Place(parts.trigger, 5)
    Place(parts.voice, 6)
    Place(parts.preview, 7, 0, 0)
    Place(parts.edit, 8, 0, 0)
end

-- [自定义内容边界] 整行作为已有 renderer 引用；只可调整行内几何/皮肤，enabled/edit/preview/tooltip 回调与排序刷新禁止修改。
function Common.CreateAuraSoundVirtualRow(parent)
    local row = ExwindTools.UI:CreateSettingsTableRow(parent, {})
    row:SetBackdrop(AURA_FLAT_BACKDROP)
    row:SetBackdropColor(
        AURA_UI_THEME.panelDeep[1], AURA_UI_THEME.panelDeep[2],
        AURA_UI_THEME.panelDeep[3], AURA_UI_THEME.panelDeep[4]
    )
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row:EnableMouse(true)

    -- 此勾选框只对应 action.enabled 这个既有叶子字段；不会新建 action、
    -- 改写分类或覆盖任何音效设置，保证列表内的快速开关不会丢用户数据。
    row.check = ExwindTools.UI:CreateCheckbox(row, "", true, function(checked)
        local binding = row._auraSoundBinding
        if not (binding and binding.itemID and binding.dungeonKey and binding.slotKey and binding.item) then return end
        local desired = checked == true
        local current = binding.item.enabled ~= false
        if desired == current then return end
        local committed = SetAuraSoundActionFields(binding.dungeonKey, binding.slotKey, binding.itemID, {
            enabled = desired,
        })
        if not committed then
            row.check:SetChecked(current)
            return
        end
        binding.item.enabled = desired
        -- 启用状态也是列表的首要排序键；提交成功后只刷新虚拟列表，
        -- 让已启用 action 立即归到上方、未启用 action 归到下方。
        Common:RefreshAuraSoundFilteredList()
    end)
    row.check:SetSize(28, 28)
    RaiseInteractiveChild(row.check, row, 3)

    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:EnableMouse(false)
    ExwindTools.UI:SetControlSurface(row.iconFrame, 10, GC.input, GC.panelBorder)
    row.iconFrame:SetSize(28, 28)
    row.iconFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon = ExwindTools.UI:CreateRoundedImage(row.iconFrame, 9, true)
    local function LayoutAuraImage()
        local inset = PixelUtil.GetNearestPixelSize(1, row.iconFrame:GetEffectiveScale(), 1)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("TOPLEFT", inset, -inset)
        row.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        row.icon:SetCornerRadius(10 - inset)
    end
    row.iconFrame:HookScript("OnSizeChanged", LayoutAuraImage)
    row.iconFrame:RegisterEvent("UI_SCALE_CHANGED")
    row.iconFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    row.iconFrame:SetScript("OnEvent", LayoutAuraImage)
    LayoutAuraImage()
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.title = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    SetAuraThemeText(row.title, AURA_UI_THEME.ink)

    row.unit = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.unit:SetJustifyH("LEFT")
    row.unit:SetWordWrap(false)

    row.edit = CreateAuraPrototypeButton(row, 62, 24, L["编辑"], function()
        local binding = row._auraSoundBinding
        if binding and binding.itemID then
            Common:ShowAuraSoundEditor(binding.itemID)
        end
    end)
    RaiseInteractiveChild(row.edit, row, 3)

    row.preview = CreateAuraPrototypeButton(row, 62, 24, L["试听"], function()
        Common.PreviewAuraSoundVirtualRow(row)
    end)
    RaiseInteractiveChild(row.preview, row, 3)

    row.categoryPill = CreateFrame("Frame", nil, row)
    ExwindTools.UI:SetControlSurface(row.categoryPill, 10, GC.input, {
        AURA_UI_THEME.line[1], AURA_UI_THEME.line[2], AURA_UI_THEME.line[3], 0.26,
    })
    row.categoryDot = row.categoryPill:CreateTexture(nil, "ARTWORK")
    row.categoryDot:SetSize(6, 6)
    row.categoryDot:SetColorTexture(
        AURA_UI_THEME.gold[1], AURA_UI_THEME.gold[2], AURA_UI_THEME.gold[3], 1.00
    )

    -- 分类方框是 row 的子 Frame。标签必须属于该方框本身，才能位于其
    -- Backdrop 之上；此前挂在 row 上，视觉层级反而被方框背景覆盖。
    row.category = ExwindTools.UI:CreateVisualFontString(row.categoryPill, EXFONTFRAME, "GameFontNormalSmall")
    row.category:SetJustifyH("LEFT")
    row.category:SetWordWrap(false)
    row.category:SetTextColor(
        AURA_UI_THEME.gold[1], AURA_UI_THEME.gold[2], AURA_UI_THEME.gold[3]
    )

    row.auraType = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.auraType:SetJustifyH("LEFT")
    row.auraType:SetWordWrap(false)

    row.trigger = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.trigger:SetJustifyH("LEFT")
    row.trigger:SetWordWrap(false)
    row.trigger:SetTextColor(0.42, 0.95, 0.70)

    row.voice = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.voice:SetJustifyH("LEFT")
    row.voice:SetWordWrap(false)
    SetAuraThemeText(row.voice, AURA_UI_THEME.ink)

    LayoutAuraSoundColumns(row, row)

    row:SetScript("OnEnter", function(frame)
        frame:SetBackdropColor(
            AURA_UI_THEME.panelHover[1], AURA_UI_THEME.panelHover[2],
            AURA_UI_THEME.panelHover[3], AURA_UI_THEME.panelHover[4]
        )
        local binding = frame._auraSoundBinding
        local spellID = binding and binding.item and tonumber(binding.item.spellID)
        if not spellID then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(spellID) end
        local soundText = binding and binding.item and HasAuraSoundSelection(binding.item)
            and Common.GetAuraSoundDisplayName(binding.item) or L["未配置声音"]
        GameTooltip:AddLine(L["播放的声音："] .. soundText, 0.48, 0.95, 0.72)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(frame)
        GameTooltip:Hide()
        local color = frame._auraSoundRowColor
        if color then frame:SetBackdropColor(color[1], color[2], color[3], color[4]) end
    end)
    return row
end

function Common.PreviewAuraSoundVirtualRow(row)
    local binding = row and row._auraSoundBinding
    local item = binding and binding.item
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (item and engine and type(engine.TryPlayStandaloneSound) == "function") then return end
    engine:TryPlayStandaloneSound({
        enabled = true,
        sourceType = item.sourceType,
        label = item.label,
        customLSM = item.customLSM,
        customPath = item.customPath,
        outputChannel = item.outputChannel,
    }, "dungeon_aura_row_preview:" .. tostring(binding.itemID or "preview"), { triggerIndex = 0 })
end

function Common.RefreshAuraSoundVirtualRow(row)
    local binding = row and row._auraSoundBinding
    local item = binding and binding.item
    if type(item) ~= "table" then return end
    local hasSound = HasAuraSoundSelection(item)
    local soundName = hasSound and Common.GetAuraSoundDisplayName(item) or L["未配置声音"]
    -- 表格显示文件名，完整播放路径仍由行悬停说明显示。
    if item.sourceType == "file" then soundName = soundName:match("([^/\\]+)$") or soundName end
    row.voice:SetText(soundName)
    row.voice:SetTextColor(hasSound and 0.48 or 0.95, hasSound and 0.95 or 0.52, hasSound and 0.72 or 0.34)
    row.category:SetText(Common.GetAuraSoundCategoryLabel(item.category))
    local categoryMeta = AURA_CATEGORY_SHORTCUTS_BY_KEY[tostring(item.category or "")]
    local categoryColor = categoryMeta and categoryMeta.color or AURA_UI_THEME.gold
    if row.categoryDot then
        row.categoryDot:SetColorTexture(categoryColor[1], categoryColor[2], categoryColor[3], 1.00)
    end
    if row.categoryPill then
        ExwindTools.UI:SetControlSurface(row.categoryPill, 10, GC.input, {
            categoryColor[1], categoryColor[2], categoryColor[3], 0.34,
        })
    end
    -- 分类名与前方色块和边框使用同一颜色；保持满不透明度，
    -- 让弹窗背景被压暗时文字仍能清楚辨认。
    row.category:SetTextColor(categoryColor[1], categoryColor[2], categoryColor[3], 1.00)
    row.category:SetAlpha(1.00)
    local unit, auraType = GetAuraSoundTarget(item)
    local unitColor = AURA_UNIT_COLORS[unit] or AURA_UNIT_COLORS.player
    row.unit:SetText(Common.GetAuraSoundUnitLabel(item))
    row.unit:SetTextColor(unitColor[1], unitColor[2], unitColor[3])
    local auraTypeColor = AURA_TYPE_COLORS[auraType] or AURA_TYPE_COLORS.debuff
    row.auraType:SetText(auraType == "buff" and L["BUFF"] or L["DEBUFF"])
    row.auraType:SetTextColor(auraTypeColor[1], auraTypeColor[2], auraTypeColor[3], 1.00)
    local trigger = tostring(item.trigger or "added")
    local color = AURA_TRIGGER_COLORS[trigger] or AURA_TRIGGER_COLORS.added
    row.trigger:SetText(Common.GetAuraSoundTriggerLabel(trigger))
    row.trigger:SetTextColor(color[1], color[2], color[3])
    local enabled = item.enabled ~= false
    if row.check then row.check:SetChecked(enabled) end
    -- 不再降低整行父级透明度，否则分类胶囊也会被连带压暗。未启用状态
    -- 只弱化名称、图标、声音和操作按钮，分类文字始终保持清晰。
    row:SetAlpha(1.00)
    row.title:SetTextColor(
        enabled and AURA_UI_THEME.ink[1] or AURA_UI_THEME.muted[1],
        enabled and AURA_UI_THEME.ink[2] or AURA_UI_THEME.muted[2],
        enabled and AURA_UI_THEME.ink[3] or AURA_UI_THEME.muted[3],
        1.00
    )
    row.icon:SetAlpha(enabled and 1.00 or 0.52)
    row.voice:SetAlpha(enabled and 1.00 or 0.68)
    row.preview:SetAlpha(enabled and 1.00 or 0.62)
    row.edit:SetAlpha(enabled and 1.00 or 0.62)
    if row.categoryPill then row.categoryPill:SetAlpha(1.00) end
    row.edit:SetText(L["编辑"])
end

function Common.BindAuraSoundVirtualRow(row, item, index, context)
    if not (item and item.actionID) then
        row._auraSoundBinding = nil
        return
    end
    local rowData = GetAuraSoundActionView(context and context.dungeonKey, context and context.slotKey, item.actionID)
    if type(rowData) ~= "table" then
        row._auraSoundBinding = nil
        return
    end
    row._auraSoundBinding = {
        item = GetAuraSoundItemView(rowData),
        itemID = tostring(item.actionID or index or ""),
        dungeonKey = context and context.dungeonKey,
        slotKey = context and context.slotKey,
    }
    -- 方案 A 用统一深色行与极轻的交替变化；分类由胶囊承担识别，不再使用
    -- 彩色行首竖条，避免长列表重新变成彩虹表。
    local backdrop = index % 2 == 0 and GC.subcard or GC.card
    row._auraSoundRowColor = backdrop
    row:SetBackdropColor(backdrop[1], backdrop[2], backdrop[3], backdrop[4])
    -- VirtualList 的可视行在创建时可能还未拿到最终宽度；每次绑定后重算，
    -- 满宽面板才能把新增空间真实分配给名称与声音列。
    LayoutAuraSoundColumns(row, row)
    local name, icon = GetAuraSpellInfo(row._auraSoundBinding.item)
    row.icon:SetTexture(icon)
    -- 不使用 ↳ 之类的 Unicode 前缀：WoW 当前字体会把它渲染成方框，且会
    -- 挤压同一法术 ID 的名称。附加 action 已由独立状态/声音列清楚区分。
    row.title:SetText(name)
    Common.RefreshAuraSoundVirtualRow(row)
end

-- [虚拟列表边界] VirtualList/可视行池拥有行创建、绑定与回收；V2 卡片只拥有固定视口 host，不得展开全量数据或重复释放行。
function Common.EnsureAuraSoundVirtualList(host)
    if not host then return nil end
    -- 列表、可视行和行内下拉属于通用页，而不是会被不同 custom renderer
    -- 反复借出/归还的 V2 节点。稳定所有权可避免每次打开都扩张 child 控件。
    local list = UI.auraSoundVirtualList
    if not list then
        local VirtualList = _G.ExwindVirtualList
        if not (VirtualList and VirtualList.Create) then return nil end
        list = VirtualList:Create(host, {
            rowHeight = AURA_SOUND_ROW_HEIGHT,
            overscan = 0,
            maxRows = AURA_SOUND_VISIBLE_ROWS,
            createRow = function(parent) return Common.CreateAuraSoundVirtualRow(parent) end,
            bindRow = function(row, entry, index, context) Common.BindAuraSoundVirtualRow(row, entry, index, context) end,
        })
        list:Hide()
        -- 固定十二行视口，子控件裁切在列表内。
        if list.SetClipsChildren then
            list:SetClipsChildren(true)
        end
    end
    if list:GetParent() ~= host then list:SetParent(host) end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    UI.auraSoundVirtualList = list
    return list
end

-- mount/update/release 是同一自定义内容生命周期，必须成对保留。
function Common.MountAuraSoundVirtualList(host, context)
    local list = Common.EnsureAuraSoundVirtualList(host)
    if not list then return end
    local element = context and context.element or {}
    CacheAuraSoundVirtualContext(
        element.dungeonKey,
        element.slotKey,
        host
    )
end

function Common.UpdateAuraSoundVirtualList(host, context)
    local list = Common.EnsureAuraSoundVirtualList(host)
    if not list then return end
    local element = context and context.element or {}
    local cached = UI.auraSoundVirtualContext
    local dungeonKey = tostring(element.dungeonKey or (cached and cached.dungeonKey) or "")
    local restore = Common._virtualListRestore
    local currentOffset = tonumber(list.offset) or 0
    local slotKey = tostring(element.slotKey or (cached and cached.slotKey) or "")
    local view = GetAuraSoundView(dungeonKey, slotKey)
    local items = {}
    if type(view) == "table" and type(view.actionIDs) == "table" then
        for _, actionID in ipairs(view.actionIDs) do
            if type(actionID) == "string" and actionID ~= "" then
                items[#items + 1] = { actionID = actionID }
            end
        end
    end
    local totalCount = #items
    local search = NormalizeAuraSoundSearchText(UI.auraSoundSearchText)
    local categoryFilter = NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter)
    if search ~= "" or categoryFilter ~= "" then
        local filtered = {}
        for _, item in ipairs(items) do
            local row = GetAuraSoundActionView(dungeonKey, slotKey, item.actionID)
            if AuraSoundRowMatchesCategoryFilter(row, categoryFilter)
                and AuraSoundRowMatchesSearch(row, search) then
                filtered[#filtered + 1] = item
            end
        end
        items = filtered
        currentOffset = 0
        restore = nil
    end
    -- 所有筛选状态都使用同一条稳定规则：已启用 action 永远在前，未启用
    -- action 永远在后；同一状态内继续保留 actionIDs 的原始顺序。
    for sourceIndex, item in ipairs(items) do
        item._sourceIndex = sourceIndex
        local row = GetAuraSoundActionView(dungeonKey, slotKey, item.actionID)
        item._enabled = type(row) ~= "table" or row.enabled ~= false
    end
    table.sort(items, function(left, right)
        if left._enabled ~= right._enabled then return left._enabled == true end
        return (left._sourceIndex or 0) < (right._sourceIndex or 0)
    end)
    UI.auraSoundVisibleActionIDs = {}
    for i = 1, #items do
        UI.auraSoundVisibleActionIDs[i] = items[i].actionID
    end
    -- 先同步稳定上下文，再 SetData；后者可能在 V2 release/update 的交错周期
    -- 中触发 Refresh，稳定缓存必须始终比 list.context 更长寿。
    CacheAuraSoundVirtualContext(dungeonKey, slotKey, host)
    list:SetData(items, {
        dungeonKey = dungeonKey,
        slotKey = slotKey,
        revision = view and view.revision,
    })
    if host._auraV2Context then Common.GuardAuraComponent(host, "list", host._auraV2Context) end
    list._dungeonAuraSoundDungeonKey = dungeonKey
    if restore and restore.dungeonKey == dungeonKey then
        list:SetOffset(restore.offset)
    elseif currentOffset > 0 then
        list:SetOffset(currentOffset)
    end
    Common._virtualListRestore = nil
    if type(Common.RefreshAuraSoundHeaderSelection) == "function" then
        Common:RefreshAuraSoundHeaderSelection()
    end
    list:Show()
end

-- release 只清本 renderer 的绑定/可视行；外层 V2 会话由 Common:Hide 归还，二者不能互相重复释放。
function Common.ReleaseAuraSoundVirtualList(host)
    local list = UI.auraSoundVirtualList
    if list and list.ReleaseData then
        local context = list.context
        -- 释放前再拍一次快照：ReleaseData 会将 context 置 nil，而编辑器的
        -- 同步回调可能紧接着发生。
        CacheAuraSoundVirtualContext(
            context and context.dungeonKey,
            context and context.slotKey,
            host or list:GetParent()
        )
        local dungeonKey = tostring(list._dungeonAuraSoundDungeonKey or "")
        if Page._visible and dungeonKey ~= "" then
            Common._virtualListRestore = { dungeonKey = dungeonKey, offset = tonumber(list.offset) or 0 }
        end
        list:ReleaseData()
        -- ReleaseData 只隐藏可视行；复用行必须主动断开上一副本的轻量绑定。
        for _, row in ipairs(list.rows or {}) do
            row._auraSoundBinding = nil
            row._auraSoundRowColor = nil
        end
        list:ClearAllPoints()
        if UI.root then list:SetParent(UI.root) end
    end
    UI.auraSoundVisibleActionIDs = nil
    if type(Common.RefreshAuraSoundHeaderSelection) == "function" then
        Common:RefreshAuraSoundHeaderSelection()
    end
    -- 不能清空 UI 引用：WoW Frame 不会随 Lua 引用立即销毁。清空引用会让下一次
    -- Mount 新建整套虚拟行，旧行却仍挂在 root 下，造成切页阶梯式内存增长。
end

function Common.EnsureAuraSoundVirtualListRenderer()
    if Common._virtualListRendererRegistered then return end
    Renderers["exboss_dungeon_aura_sound_virtual_list"] = {
        mount = function(host, context) Common.MountAuraSoundVirtualList(host, context) end,
        update = function(host, context) Common.UpdateAuraSoundVirtualList(host, context) end,
        release = function(host) Common.ReleaseAuraSoundVirtualList(host) end,
    }
    Common._virtualListRendererRegistered = true
end

-- 表头不用依赖等宽空格。UI 缩放后空格列会和实际行错开，而声音列正好又在
-- 最容易被挤压的位置；将其与行共用 LayoutAuraSoundColumns 才能稳定对齐。
function Common:RefreshAuraSoundHeaderSelection()
    local header = UI.auraSoundHeader
    local check = header and header.check
    if not check then return end

    local actionIDs = UI.auraSoundVisibleActionIDs or {}
    local enabledCount = 0
    for i = 1, #actionIDs do
        local row = GetAuraSoundActionView(UI.dungeonKey, UI.slotKey, actionIDs[i])
        if type(row) == "table" and row.enabled ~= false then
            enabledCount = enabledCount + 1
        end
    end

    check:SetChecked(#actionIDs > 0 and enabledCount == #actionIDs)
    if check.checkbox and check.checkbox.SetEnabled then
        check.checkbox:SetEnabled(#actionIDs > 0)
    elseif check.checkbox and #actionIDs > 0 and check.checkbox.Enable then
        check.checkbox:Enable()
    elseif check.checkbox and check.checkbox.Disable then
        check.checkbox:Disable()
    end
    if check.checkbox then
        local alpha = #actionIDs == 0 and 0.35
            or (enabledCount > 0 and enabledCount < #actionIDs) and 0.65
            or 1.00
        check.checkbox:SetAlpha(alpha)
    end
end

function Common:SetVisibleAuraSoundActionsEnabled(enabled)
    local actionIDs = UI.auraSoundVisibleActionIDs or {}
    if #actionIDs == 0 then
        self:RefreshAuraSoundHeaderSelection()
        return
    end

    local ok, _, changed = SetAuraSoundActionsEnabled(UI.dungeonKey, UI.slotKey, actionIDs, enabled == true)
    if not ok then
        if (tonumber(changed) or 0) > 0 then
            self:RefreshAuraSoundRows()
        else
            self:RefreshAuraSoundHeaderSelection()
        end
        return
    end
    self:RefreshAuraSoundRows()
end

function Common.EnsureAuraSoundHeaderRenderer()
    if Common._auraSoundHeaderRendererRegistered then return end
    local EXUI = ExwindTools.UI
    Renderers["exboss_dungeon_aura_sound_header"] = {
        mount = function(host)
            if not host._auraSoundHeader then
                local header = EXUI:CreateSettingsTableHeader(host, { columns = AuraSoundTableColumns(host:GetWidth()) })
                host._auraSoundPublicHeader = header
                local labels = header._exSettingsTableLabels
                host._auraSoundHeader = {
                    check = EXUI:CreateCheckbox(host, "", false, function(checked)
                        Common:SetVisibleAuraSoundActionsEnabled(checked)
                    end),
                    title = labels[2], category = labels[3], auraType = labels[4],
                    trigger = labels[5], voice = labels[6], preview = labels[7], edit = labels[8],
                }
                for _, label in ipairs(labels) do label:SetJustifyH("LEFT") end
                host._auraSoundHeader.check:SetSize(28, 28)
                RaiseInteractiveChild(host._auraSoundHeader.check, host, 3)
            end
            UI.auraSoundHeader = host._auraSoundHeader
            host._auraSoundPublicHeader:Show()
            host._auraSoundHeader.check:Show()
            Common:RefreshAuraSoundHeaderSelection()
            LayoutAuraSoundColumns(host, host._auraSoundHeader)
        end,
        update = function(host)
            UI.auraSoundHeader = host._auraSoundHeader
            Common:RefreshAuraSoundHeaderSelection()
            LayoutAuraSoundColumns(host, host._auraSoundHeader)
        end,
        release = function(host)
            if UI.auraSoundHeader == host._auraSoundHeader then UI.auraSoundHeader = nil end
            host._auraSoundPublicHeader:Hide()
            host._auraSoundHeader.check:Hide()
        end,
    }
    Common._auraSoundHeaderRendererRegistered = true
end

local function NormalizeAuraCategorySoundDraft(value)
    value = type(value) == "table" and value or {}
    return {
        sourceType = value.sourceType == "lsm" and "lsm" or value.sourceType == "file" and "file" or "pack",
        label = tostring(value.label or ""),
        customLSM = tostring(value.customLSM or ""),
        customPath = tostring(value.customPath or ""),
    }
end

local function GetAuraCategorySoundSignature(row)
    row = NormalizeAuraCategorySoundDraft(row)
    return table.concat({ row.sourceType, row.label, row.customLSM, row.customPath }, "\31")
end

local function GetAuraCategorySoundSummary(row)
    row = NormalizeAuraCategorySoundDraft(row)
    if not HasAuraSoundSelection(row) then return L["未配置声音"] end
    return string.format("%s：%s", Common.GetAuraSoundSourceLabel(row.sourceType), Common.GetAuraSoundDisplayName(row))
end

-- 所有分类概览都只遍历 ID View 后按需读取单 action，不能持有 auraSounds 根。
local function GetAuraSoundActionEntries(dungeonKey, slotKey)
    local entries = {}
    local view = GetAuraSoundView(dungeonKey, slotKey)
    if type(view) ~= "table" or type(view.actionIDs) ~= "table" then return entries end
    for _, actionID in ipairs(view.actionIDs) do
        if type(actionID) == "string" and actionID ~= "" then
            local row = GetAuraSoundActionView(dungeonKey, slotKey, actionID)
            if type(row) == "table" then
                entries[#entries + 1] = { actionID = actionID, row = GetAuraSoundItemView(row) }
            end
        end
    end
    return entries
end

local function GetAuraSoundCategorySoundDraft(dungeonKey, slotKey, categoryKey)
    for _, entry in ipairs(GetAuraSoundActionEntries(dungeonKey, slotKey)) do
        if entry.row.category == categoryKey then
            return NormalizeAuraCategorySoundDraft(entry.row)
        end
    end
    return NormalizeAuraCategorySoundDraft(nil)
end

-- 分类卡片不是固定枚举：它从当前副本的 action View 取得已有分类，因此点名、
-- 驱散和未来的自定义分类都会自然出现在卡片下方，不需要改动资料结构。
local function GetAuraSoundCategoryFilterItems(dungeonKey, slotKey)
    local counts = {}
    local total = 0
    for _, entry in ipairs(GetAuraSoundActionEntries(dungeonKey, slotKey)) do
        local categoryKey = tostring(entry.row.category or "uncategorized")
        counts[categoryKey] = (counts[categoryKey] or 0) + 1
        total = total + 1
    end
    local keys = {}
    for categoryKey in pairs(counts) do keys[#keys + 1] = categoryKey end
    table.sort(keys, function(left, right)
        local leftCount, rightCount = counts[left] or 0, counts[right] or 0
        if leftCount ~= rightCount then return leftCount > rightCount end
        return tostring(Common.GetAuraSoundCategoryLabel(left)) < tostring(Common.GetAuraSoundCategoryLabel(right))
    end)
    local items = {
        { L["全部分类"], "", total },
    }
    local directLimit = math.max(0, AURA_CATEGORY_FILTER_MAX_CARDS - 1)
    if #keys > directLimit then directLimit = math.max(0, directLimit - 1) end
    for index = 1, math.min(#keys, directLimit) do
        local categoryKey = keys[index]
        items[#items + 1] = {
            Common.GetAuraSoundCategoryLabel(categoryKey),
            categoryKey,
            counts[categoryKey],
        }
    end
    UI.auraSoundCategoryOtherKeys = nil
    if #keys > directLimit then
        local otherCount, otherKeys = 0, {}
        for index = directLimit + 1, #keys do
            local categoryKey = keys[index]
            otherKeys[categoryKey] = true
            otherCount = otherCount + (counts[categoryKey] or 0)
        end
        UI.auraSoundCategoryOtherKeys = otherKeys
        items[#items + 1] = { L["其他分类"], AURA_CATEGORY_FILTER_OTHER, otherCount }
    end
    return items
end

function Common.GetAuraSoundCategorySummary(dungeonKey, slotKey, categoryKey)
    local count, firstSound, firstSignature, hasDifferentSound = 0, nil, nil, false
    for _, entry in ipairs(GetAuraSoundActionEntries(dungeonKey, slotKey)) do
        if entry.row.category == categoryKey then
            count = count + 1
            local signature = GetAuraCategorySoundSignature(entry.row)
            if not firstSignature then
                firstSignature = signature
                firstSound = entry.row
            elseif firstSignature ~= signature then
                hasDifferentSound = true
            end
        end
    end
    if count == 0 then return 0, L["未配置声音"] end
    if hasDifferentSound then return count, L["多个声音（待统一）"] end
    return count, GetAuraCategorySoundSummary(firstSound)
end

function Common.CommitAuraSoundCategoryCardLSM(card, value)
    card._auraSoundDraft = NormalizeAuraCategorySoundDraft(card._auraSoundDraft)
    card._auraSoundDraft.sourceType = "lsm"
    card._auraSoundDraft.customLSM = tostring(value or "")
    Common.ApplyAuraSoundCategoryCardLSM(card)
end

function Common.PreviewAuraSoundCategoryCardLSM(card)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (card and engine) then return end
    local sound = GetAuraSoundCategorySoundDraft(UI.dungeonKey, UI.slotKey, card.categoryKey)
    if sound.customLSM == "" then return end
    engine:TryPlayStandaloneSound({ enabled = true, sourceType = "lsm", customLSM = sound.customLSM,
        label = "", customPath = "" }, "dungeon_aura_card_preview:" .. card.categoryKey, { triggerIndex = 0 })
end

function Common.ApplyAuraSoundCategoryCardLSM(card)
    if not (card and card.categoryKey and UI.dungeonKey and UI.slotKey) then return end
    local sound = NormalizeAuraCategorySoundDraft(card._auraSoundDraft)
    if sound.customLSM == "" then return end
    local view = GetAuraSoundView(UI.dungeonKey, UI.slotKey)
    for _, actionID in ipairs(type(view) == "table" and view.actionIDs or {}) do
        local current = GetAuraSoundActionView(UI.dungeonKey, UI.slotKey, actionID)
        if type(current) == "table" and current.category == card.categoryKey then
            local fields = {}
            if current.sourceType ~= "lsm" then fields.sourceType = "lsm" end
            if tostring(current.customLSM or "") ~= sound.customLSM then fields.customLSM = sound.customLSM end
            if next(fields) then
                local committed = SetAuraSoundActionFields(UI.dungeonKey, UI.slotKey, actionID, fields)
                if not committed then Common:RefreshAuraSoundRows(); return end
            end
        end
    end
    Common:RefreshAuraSoundRows()
end

function Common:RefreshAuraSoundCategoryCards()
    if UI.cardSession then UI.cardSession:Refresh() end
end

function Common.RefreshAuraSoundCategoryFilterControl()
    GetAuraSoundCategoryFilterItems(UI.dungeonKey, UI.slotKey)
    if UI.cardSession then UI.cardSession:Refresh() end
end

function Common.SetAuraSoundCategoryFilter(categoryKey)
    categoryKey = NormalizeAuraSoundCategoryFilter(categoryKey)
    if NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter) == categoryKey then return end
    UI.auraSoundCategoryFilter = categoryKey
    Common:RefreshAuraSoundFilteredList()
end

function Common.RefreshAuraSoundCategoryDrawerSelection(drawer)
    local selected = 0
    for _, actionID in ipairs(drawer.actionIDs or {}) do
        if drawer.draftMembers[actionID] then selected = selected + 1 end
    end
    return selected
end

function Common.RefreshAuraSoundCategoryDrawerList(drawer)
    if drawer._v2Session then drawer._v2Session:Refresh() end
end

function Common.PopulateAuraSoundCategoryDrawer(drawer)
    if not drawer then return end
    drawer.actionIDs = {}
    drawer.originalMembers = {}
    drawer.draftMembers = {}
    local view = GetAuraSoundView(drawer.dungeonKey, drawer.slotKey)
    for _, actionID in ipairs(type(view) == "table" and view.actionIDs or {}) do
        if type(actionID) == "string" and actionID ~= "" then
            local row = GetAuraSoundActionView(drawer.dungeonKey, drawer.slotKey, actionID)
            if type(row) == "table" then
                row = GetAuraSoundItemView(row)
                drawer.actionIDs[#drawer.actionIDs + 1] = actionID
                if row.category == drawer.categoryKey then
                    drawer.originalMembers[actionID] = true
                    drawer.draftMembers[actionID] = true
                end
            end
        end
    end
    drawer.searchText = ""
    Common.RefreshAuraSoundCategoryDrawerList(drawer)
end

function Common.CloseAuraSoundCategoryDrawer(drawer)
    if not drawer then return end
    -- 抽屉内始终只有 UI 草稿；关闭、取消与外部 Hide 都不能触碰 action 配置。
    drawer.actionIDs = nil
    drawer.entries = nil
    drawer.originalMembers = nil
    drawer.draftMembers = nil
    drawer.categoryKey = nil
    drawer.dungeonKey = nil
    drawer.slotKey = nil
    if drawer.error then drawer.error:SetText("") end
    drawer:Hide()
end

function Common.SaveAuraSoundCategoryDrawer(drawer)
    if not (drawer and drawer.categoryKey and drawer.dungeonKey and drawer.slotKey) then return end
    Common.RefreshAuraSoundCategoryDrawerSelection(drawer)
    for _, actionID in ipairs(drawer.actionIDs or {}) do
        local current = GetAuraSoundActionView(drawer.dungeonKey, drawer.slotKey, actionID)
        if type(current) == "table" then
            current = GetAuraSoundItemView(current)
            local fields = {}
            if drawer.draftMembers[actionID] then
                if current.category ~= drawer.categoryKey then fields.category = drawer.categoryKey end
            elseif drawer.originalMembers[actionID] and current.category == drawer.categoryKey then
                -- 取消原有成员时只解除归类，绝不顺带清空或改写声音叶子。
                fields.category = "uncategorized"
            end
            if next(fields) then
                local committed, reason = SetAuraSoundActionFields(drawer.dungeonKey, drawer.slotKey, actionID, fields)
                if not committed then
                    drawer.error:SetText(tostring(reason or L["光环声音保存失败"]))
                    Common:RefreshAuraSoundRows()
                    return
                end
            end
        end
    end
    Common.CloseAuraSoundCategoryDrawer(drawer)
    Common.RefreshAuraSoundCategoryFilterControl()
    Common:RefreshAuraSoundRows()
end

function Common.EnsureAuraSoundCategoryDrawer(parent)
    parent = parent or UI.root or UI.host
    if UI.auraSoundCategoryDrawer then
        PositionVoiceEditor(UI.auraSoundCategoryDrawer, parent)
        return UI.auraSoundCategoryDrawer
    end
    local drawer = CreateVoiceOverlay(parent, Common.CloseAuraSoundCategoryDrawer)
    drawer.subtitle = ExwindTools.UI:CreateVisualFontString(drawer, EXFONTFRAME, "GameFontNormalSmall")
    drawer.subtitle:SetPoint("TOPLEFT", drawer.title, "BOTTOMLEFT", 0, -ExwindTools.GUIMetrics.space.descriptionGap)
    drawer.subtitle:SetPoint("RIGHT", drawer.title, "RIGHT")
    drawer.subtitle:SetJustifyH("LEFT")
    drawer.subtitle:SetWordWrap(true)
    drawer.subtitle:SetText(L["勾选 action 归入此分类；音效仅在上方卡片设置。"])
    drawer.subtitle:SetTextColor(unpack(GC.textDim))
    drawer:HookScript("OnHide", function(frame)
        frame.actionIDs, frame.originalMembers, frame.draftMembers = nil, nil, nil
        frame.categoryKey, frame.dungeonKey, frame.slotKey = nil, nil, nil
    end)
    UI.auraSoundCategoryDrawer = drawer
    return drawer
end

function Common:ShowAuraSoundCategoryDrawer(categoryKey)
    local meta = AURA_CATEGORY_SHORTCUTS_BY_KEY[categoryKey]
    if not (meta and UI.dungeonKey and UI.slotKey) then return end
    local drawer = Common.EnsureAuraSoundCategoryDrawer(UI.root or UI.host)
    drawer.categoryKey, drawer.dungeonKey, drawer.slotKey = meta.key, UI.dungeonKey, UI.slotKey
    drawer.title:SetText(string.format(L["%s · 分类管理"], meta.label))
    drawer.error:SetText("")
    Common.PopulateAuraSoundCategoryDrawer(drawer)
    drawer.entries = {}
    for _, actionID in ipairs(drawer.actionIDs) do
        local row = GetAuraSoundActionView(drawer.dungeonKey, drawer.slotKey, actionID)
        drawer.entries[#drawer.entries + 1] = { actionID = actionID, row = GetAuraSoundItemView(row) }
    end
    local owner = { controls = {}, actions = {}, sources = {}, texts = {} }
    RecordControl(owner, "search", { controlType = "input", size = "wide" },
        function() return drawer.searchText end,
        function(value) drawer.searchText = tostring(value or "") end)
    owner.sources.members = function()
        local entries = {}
        local needle = NormalizeAuraSoundSearchText(drawer.searchText)
        for _, entry in ipairs(drawer.entries) do
            if AuraSoundRowMatchesSearch(entry.row, needle) then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end
    owner.controls.member = ExwindTools.UI:CreateSettingsV2Control({ controlType = "checkbox" }, function(context)
        local actionID = context.scope.item.actionID
        local binding = ExwindTools.UI:CreateSettingsV2Binding(Common.MODULE_KEY, drawer.draftMembers, "member")
        binding.Read = function() return drawer.draftMembers[actionID] == true end
        binding.Write = function(_, value) drawer.draftMembers[actionID] = value == true end
        return binding
    end)
    owner.texts.name = function(scope) return (GetAuraSpellInfo(scope.item.row)) end
    owner.texts.category = function(scope) return Common.GetAuraSoundCategoryLabel(scope.item.row.category) end
    owner.texts.selection = function()
        return string.format(L["已选择 %d / %d 个 action"], Common.RefreshAuraSoundCategoryDrawerSelection(drawer), #drawer.actionIDs)
    end
    owner.actions.cancel = function() Common.CloseAuraSoundCategoryDrawer(drawer) end
    owner.actions.save = function() Common.SaveAuraSoundCategoryDrawer(drawer) end
    MountOverlaySession(drawer, { version = 2, cards = {
        { id = "category-drawer", kind = "card", titleSource = "selection", children = {
            Setting("search-row", L["搜索"], { Field("search", "input") }),
            { id = "members", kind = "table", columns = {
                { title = L["选择"] }, { title = L["法术"] }, { title = L["分类"] },
            }, children = {
                { id = "member-records", kind = "repeat", source = "members", template = {
                    id = "member-row", kind = "row", children = {
                        { id = "member-check", kind = "cell", children = { Field("member", "checkbox") } },
                        { id = "member-name", kind = "cell", children = { { id = "name", kind = "text", textSource = "name" } } },
                        { id = "member-category", kind = "cell", children = { { id = "category", kind = "text", textSource = "category" } } },
                    },
                } },
            } },
            Setting("actions", L["操作"], {
                { id = "cancel", kind = "button", text = L["取消"], action = "cancel" },
                { id = "save", kind = "button", text = L["应用"], action = "save" },
            }),
        } },
    } }, owner)
    drawer:Show()
end

-- [共享宿主边界] root/gridHost 覆盖 Boss 的同一右侧 scroll child；只可迁移锚点/外观，不能改 parent、strata、一次释放或高度稳定 guard。
function Common.EnsureFrames(host)
    if not host then return nil end
    local created = false
    if not UI.root then
        -- 新页面必须完全取代旧的 Boss 法术设置页，不能只在其上透明叠层。
        UI.root = CreateFrame("Frame", nil, host, "BackdropTemplate")
        UI.root:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        UI.root:SetBackdropColor(
            AURA_UI_THEME.canvas[1], AURA_UI_THEME.canvas[2], AURA_UI_THEME.canvas[3], AURA_UI_THEME.canvas[4]
        )
        UI.gridHost = CreateFrame("Frame", nil, UI.root)
        created = true
    end
    local parentChanged = UI.root:GetParent() ~= host
    if parentChanged then UI.root:SetParent(host) end
    -- 必须继承 Settings ScrollFrame 的 strata。此前硬编码 LOW，使整页落在
    -- 宿主 DIALOG 输入层之后：画面可见，但鼠标始终命中更高 strata 的 Frame。
    local hostStrata = (host.GetFrameStrata and host:GetFrameStrata()) or "DIALOG"
    UI.root:SetFrameStrata(hostStrata)
    UI.root:SetFrameLevel((host:GetFrameLevel() or 1) + 1)
    UI.gridHost:SetFrameStrata(hostStrata)
    UI.gridHost:SetFrameLevel((UI.root:GetFrameLevel() or 1) + 10)
    -- host 是 ScrollFrame 的真正 scroll child。这里只在创建或换宿主时建立
    -- 尺寸；同一页的重复刷新若先把内容高度压回 viewport，再由 V2 撑开，
    -- ScrollFrame 会连跳数次，正是肉眼可见的闪屏来源。
    if created or parentChanged then
        UI.root:ClearAllPoints()
        UI.root:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        UI.root:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        UI.root:SetHeight(math.max(1, host:GetHeight() or 1))
        UI.gridHost:ClearAllPoints()
        UI.gridHost:SetPoint("TOPLEFT", UI.root, "TOPLEFT", 0, 0)
        UI.gridHost:SetPoint("TOPRIGHT", UI.root, "TOPRIGHT", 0, 0)
        UI.gridHost:SetHeight(math.max(1, UI.root:GetHeight() or 1))
    end
    UI.root:Show()
    UI.gridHost:Show()
    return UI.root
end

function Common.RefreshAuraSoundEditorFields(editor)
    if not (editor and editor.row) then return end
    NormalizeAuraSoundItem(editor.row)
    local name, _, spellID = GetAuraSpellInfo(editor.row)
    editor.title:SetText(string.format("%s · %s [%d]", L["光环声音"], name, spellID))
    if editor.error then editor.error:SetText("") end
    if editor._v2Session then editor._v2Session:Refresh() end
end

function Common.CommitAuraSoundEditor(editor, field, value)
    -- 此函数名字保留给现有控件回调，但它只提交到弹窗草稿，绝不直接写
    -- SavedVariables / 触发运行时注册 / 重建虚拟列表。
    if not (editor and type(editor.row) == "table" and editor.itemID) then return end
    if editor.isCatalogAction == true and (field == "spellID" or field == "unit" or field == "auraType") then
        return
    end
    if AURA_ACTION_FIELD_SET[field] ~= true then return end
    local row = editor.row
    if field == "spellID" then
        row.spellID = math.max(0, tonumber(value) or 0)
    elseif field == "category" then
        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        row.category = value ~= "" and value or "uncategorized"
    elseif field then
        row[field] = value
    end
    NormalizeAuraSoundItem(row)
    editor.touched = editor.touched or {}
    editor.touched[field] = row[field]
    if editor.error then editor.error:SetText("") end
    Common.RefreshAuraSoundEditorFields(editor)
end

function Common.CloseAuraSoundEditor(editor)
    if not editor then return end
    -- 关闭和取消完全放弃草稿。尤其是新增项，在确认前不存在于 items 中。
    editor.isNewAuraSoundAction = false
    editor.isCatalogAction = false
    editor.db = nil
    editor.itemID = nil
    editor.touched = nil
    editor.row = nil
    editor.error:SetText("")
    editor:Hide()
end

function Common.SaveAuraSoundEditor(editor)
    if not (editor and editor.itemID and type(editor.row) == "table") then return end
    local itemID = tostring(editor.itemID)
    local stored = BuildPersistedAuraSoundItem(editor.row)
    local hasSound = stored.sourceType == "lsm" and tostring(stored.customLSM or "") ~= ""
        or stored.sourceType == "file" and tostring(stored.customPath or "") ~= ""
        or stored.sourceType == "pack" and tostring(stored.label or "") ~= ""
    if tonumber(stored.spellID) == nil or tonumber(stored.spellID) <= 0 then
        if editor.error then editor.error:SetText(L["请填写有效法术ID"]) end
        return
    end
    if not hasSound then
        if editor.error then editor.error:SetText(L["请选择播放的声音"]) end
        return
    end
    local committed, reason
    if editor.isNewAuraSoundAction == true then
        committed, reason = CreateAuraSoundAction(UI.dungeonKey, UI.slotKey, itemID, stored)
    else
        local touched = type(editor.touched) == "table" and editor.touched or nil
        if not touched or next(touched) == nil then
            Common.CloseAuraSoundEditor(editor)
            return
        end
        committed, reason = SetAuraSoundActionFields(UI.dungeonKey, UI.slotKey, itemID, touched)
    end
    if not committed then
        if editor.error then editor.error:SetText(tostring(reason or L["光环声音保存失败"])) end
        return
    end

    local needsListRefresh = editor.isNewAuraSoundAction == true
        or NormalizeAuraSoundSearchText(UI.auraSoundSearchText) ~= ""
        or NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter) ~= ""
    Common.CloseAuraSoundEditor(editor)
    Common.RefreshAuraSoundCategoryFilterControl()
    if needsListRefresh then
        Common:RefreshAuraSoundRows()
    else
        Common:RefreshAuraSoundCategoryCards()
        Common:RefreshAuraSoundVisibleRow(itemID)
    end
end

function Common.PreviewAuraSound(editor)
    local row = editor and editor.row
    if type(row) ~= "table" then return end
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and type(engine.TryPlayStandaloneSound) == "function") then return end
    engine:TryPlayStandaloneSound({
        enabled = true,
        sourceType = row.sourceType == "lsm" and "lsm" or row.sourceType == "file" and "file" or "pack",
        label = tostring(row.label or ""),
        customLSM = tostring(row.customLSM or ""),
        customPath = tostring(row.customPath or ""),
    }, "dungeon_aura_preview:" .. tostring(editor.itemID or "preview"), { triggerIndex = 0 })
end

function Common.EnsureAuraSoundEditor(parent)
    parent = parent or UI.root or UI.host
    if UI.auraSoundEditor then
        PositionVoiceEditor(UI.auraSoundEditor, parent)
        return UI.auraSoundEditor
    end
    local editor = CreateVoiceOverlay(parent, Common.CloseAuraSoundEditor)
    editor:HookScript("OnHide", function(frame)
        frame.db, frame.itemID, frame.touched, frame.row = nil, nil, nil, nil
        frame.isNewAuraSoundAction, frame.isCatalogAction = false, false
    end)
    UI.auraSoundEditor = editor
    return editor
end

function Common:ShowAuraSoundEditor(itemID, isNewAuraSoundAction, draftRow)
    local row = draftRow or GetAuraSoundActionView(UI.dungeonKey, UI.slotKey, itemID)
    if type(row) ~= "table" then return end
    local editor = Common.EnsureAuraSoundEditor(UI.root or UI.host)
    editor.itemID, editor.row = tostring(itemID), CopyAuraSoundItem(row)
    editor.isNewAuraSoundAction = isNewAuraSoundAction == true
    editor.isCatalogAction = tostring(itemID):match("^catalog:") ~= nil
    editor.touched = {}
    Common.RefreshAuraSoundEditorFields(editor)
    local owner = { controls = {}, actions = {}, predicates = {} }
    local function Control(ref, spec)
        RecordControl(owner, ref, spec, function() return editor.row[ref] end,
            function(value) Common.CommitAuraSoundEditor(editor, ref, value) end)
    end
    Control("spellID", { controlType = "input", size = "short" })
    Control("unit", { controlType = "select", options = Options(AURA_UNIT_ITEMS) })
    Control("auraType", { controlType = "select", options = Options(AURA_TYPE_ITEMS) })
    Control("trigger", { controlType = "select", options = Options(AURA_TRIGGER_ITEMS) })
    Control("sourceType", { controlType = "select", label = L["声音来源"], size = "wide", options = Options(AURA_SOUND_SOURCE_ITEMS) })
    Control("label", { controlType = "select", optionsSource = "ExBoss.UI.Panel.BossPage.DungeonCommon.GetAuraSoundPackItems", search = true })
    Control("customLSM", { controlType = "select", media = "sound", search = true })
    Control("customPath", { controlType = "input", size = "wide" })
    owner.predicates.identity = function() return editor.isCatalogAction ~= true end
    owner.predicates.pack = function() return editor.row.sourceType == "pack" end
    owner.predicates.lsm = function() return editor.row.sourceType == "lsm" end
    owner.predicates.file = function() return editor.row.sourceType == "file" end
    owner.actions.cancel = function() Common.CloseAuraSoundEditor(editor) end
    owner.actions.save = function() Common.SaveAuraSoundEditor(editor) end
    owner.actions.preview = function() Common.PreviewAuraSound(editor) end
    MountOverlaySession(editor, { version = 2, cards = {
        { id = "aura-editor", kind = "card", title = L["光环声音"], children = {
            Setting("spell-row", L["法术ID"], { Field("spellID", "input") }, nil, "identity"),
            Setting("unit-row", L["单位"], { Field("unit", "select") }, nil, "identity"),
            Setting("type-row", L["光环类型"], { Field("auraType", "select") }, nil, "identity"),
            Setting("trigger-row", L["状态"], { Field("trigger", "select") }),
            Field("sourceType", "select"),
            Setting("pack-row", L["语音包标签"], { Field("label", "select") }, nil, "pack"),
            Setting("lsm-row", L["LSM音效"], { Field("customLSM", "select") }, nil, "lsm"),
            Setting("file-row", L["自定义路径"], { Field("customPath", "input") }, nil, "file"),
            Setting("actions", L["操作"], {
                { id = "cancel", kind = "button", text = L["取消"], action = "cancel" },
                { id = "save", kind = "button", text = editor.isNewAuraSoundAction and L["确认新增"] or L["保存"], action = "save" },
                { id = "preview", kind = "button", text = L["试听"], action = "preview" },
            }),
        } },
    } }, owner)
    editor:Show()
end

function Common:AddAuraSound()
    -- 新增阶段不创建 auraSounds / items；取消必须是零写入。
    local view = GetAuraSoundView(UI.dungeonKey, UI.slotKey)
    local nextID = 0
    local occupied = {}
    for _, actionID in ipairs(type(view) == "table" and view.actionIDs or {}) do
        occupied[tostring(actionID)] = true
        local number = tonumber(tostring(actionID):match("^user:(%d+)$"))
        if number and number > nextID then nextID = number end
    end
    local itemID
    repeat
        nextID = nextID + 1
        itemID = "user:" .. tostring(nextID)
    until not occupied[itemID]
    local draft = {
        spellID = 0,
        unit = "player",
        auraType = "debuff",
        category = "uncategorized",
        trigger = "added",
        sourceType = "pack",
        label = "",
        customLSM = "",
        outputChannel = "Master",
    }
    Common:ShowAuraSoundEditor(itemID, true, draft)
end

function Common:BuildPageLayout()
    local categoryRows = {}
    for index, meta in ipairs(AURA_CATEGORY_SHORTCUTS) do
        local id = "category" .. index
        categoryRows[#categoryRows + 1] = Setting(id .. "-row", meta.label, {
            Field(id .. "Sound", "select"),
            { id = id .. "-preview", kind = "button", text = L["试听"], action = id .. "Preview" },
            { id = id .. "-manage", kind = "button", text = L["分类管理"], action = id .. "Manage" },
        }, meta.hint)
    end
    return { version = 2, cards = {
        { id = "categories", kind = "card", title = L["分类"], children = categoryRows },
        { id = "rules", kind = "card", title = L["光环声音"], children = {
            -- 一行工具条：搜索、分类筛选、添加声音。
            Setting("toolbar-row", L["搜索"], {
                Field("search", "input"),
                Field("filter", "select"),
                { id = "add", kind = "button", text = L["+ 添加声音"], action = "addSound", presentation = "primary" },
            }),
            { id = "header", kind = "component", ref = "header", custom = "EXBoss.AuraSoundList" },
            { id = "list", kind = "component", ref = "list", custom = "EXBoss.AuraSoundList" },
        } },
    } }
end

function Common.GetCategoryFilterOptions()
    return GetAuraSoundCategoryFilterItems(UI.dungeonKey, UI.slotKey)
end

-- A retained GUI host keeps the original controls out of V2's node pool.
-- Release detaches that host before the V2 node can be reused by another page.
local function LayoutAuraComponent(host, kind, width)
    host:SetWidth(width)
    if kind == "header" then
        LayoutAuraSoundColumns(host, host._auraSoundHeader)
        return ExwindTools.GUIMetrics.size.controlHeight
    end
    return AURA_SOUND_LIST_HEIGHT
end

local function CloseAuraComponentTransientUI()
    if GameTooltip then GameTooltip:Hide() end
end

function Common.GuardAuraComponent(host, kind, context)
    local function Script(frame, event)
        frame._auraOriginalScripts = frame._auraOriginalScripts or {}
        local original = frame._auraOriginalScripts[event] or frame:GetScript(event)
        if not original then return end
        frame._auraOriginalScripts[event] = original
        frame:SetScript(event, context:Guard(original))
    end
    if kind == "header" then
        Script(host._auraSoundHeader.check.checkbox, "OnClick")
    elseif kind == "list" then
        for _, row in ipairs(UI.auraSoundVirtualList.rows) do
            Script(row.check.checkbox, "OnClick")
            Script(row.edit, "OnClick")
            Script(row.preview, "OnClick")
        end
    end
end

function Common:CreatePageOwner(dungeonKey, slotKey, pageHost)
    local owner = { components = {}, controls = {}, actions = {} }
    owner.binding = { moduleKey = Common.MODULE_KEY }


    UI.componentHosts = UI.componentHosts or {}
    local function Component(ref, rendererKey, kind, categoryKey)
        local renderer = Renderers[rendererKey]
        owner.components[ref] = {
            mount = function(parent, context)
                local host = UI.componentHosts[ref]
                if not host then
                    host = CreateFrame("Frame", nil, UI.root)
                    UI.componentHosts[ref] = host
                end
                host:SetParent(parent)
                host:ClearAllPoints()
                host:SetPoint("TOPLEFT")
                host._auraV2Context = context
                host._auraRendererContext = { element = { dungeonKey = dungeonKey, slotKey = slotKey, categoryKey = categoryKey } }
                host:Show()
                renderer.mount(host, host._auraRendererContext)
                Common.GuardAuraComponent(host, kind, context)
                return host
            end,
            update = function(host, context)
                renderer.update(host, host._auraRendererContext)
                Common.GuardAuraComponent(host, kind, context)
            end,
            measure = function(host, context, width)
                return LayoutAuraComponent(host, kind, width)
            end,
            layout = function(host, context, width, height)
                host:SetSize(width, height)
                LayoutAuraComponent(host, kind, width)
                Common.GuardAuraComponent(host, kind, context)
            end,
            setEnabled = function(host, context, enabled)
                -- No enabled predicate is declared: each original owner keeps its state.
            end,
            setVisible = function(host, context, visible)
                if not visible then CloseAuraComponentTransientUI(host) end
                host:SetShown(visible)
            end,
            release = function(host)
                CloseAuraComponentTransientUI(host)
                renderer.release(host)
                host._auraV2Context, host._auraRendererContext = nil, nil
                host:Hide()
                host:ClearAllPoints()
                host:SetParent(UI.root)
            end,
        }
    end
    for index, meta in ipairs(AURA_CATEGORY_SHORTCUTS) do
        local categoryKey, ref = meta.key, "category" .. index
        RecordControl(owner, ref .. "Sound", { controlType = "select", media = "sound", search = true },
            function() return GetAuraSoundCategorySoundDraft(dungeonKey, slotKey, categoryKey).customLSM end,
            function(value)
                Common.CommitAuraSoundCategoryCardLSM({ categoryKey = categoryKey }, value)
            end)
        owner.actions[ref .. "Preview"] = function()
            Common.PreviewAuraSoundCategoryCardLSM({ categoryKey = categoryKey })
        end
        owner.actions[ref .. "Manage"] = function() Common:ShowAuraSoundCategoryDrawer(categoryKey) end
    end
    RecordControl(owner, "filter", { controlType = "select", optionsSource = "ExBoss.UI.Panel.BossPage.DungeonCommon.GetCategoryFilterOptions" },
        function() return NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter) end,
        Common.SetAuraSoundCategoryFilter)
    owner.actions.addSound = function() Common:AddAuraSound() end
    RecordControl(owner, "search", { controlType = "input" },
        function() return tostring(UI.auraSoundSearchText or "") end,
        function(value) UI.auraSoundSearchText = tostring(value or ""); Common:RefreshAuraSoundFilteredList() end)

    Component("header", "exboss_dungeon_aura_sound_header", "header")
    Component("list", "exboss_dungeon_aura_sound_virtual_list", "list")
    owner.onHeightChanged = function(height)
        height = math.max(1, height)
        UI.gridHost:SetHeight(height)
        UI.root:SetHeight(height)
        pageHost:SetHeight(height)
    end
    return owner
end
function Common:HasContent()
    local dungeonKey = Page:GetCurrentDungeonCommonOptions()
    -- 没有静态资料的副本仍应进入这张全页光环表，用户可以直接新增自定义
    -- 规则；是否有默认候选不能再决定页面是否存在。
    return type(dungeonKey) == "string" and dungeonKey ~= ""
end

-- 宿主交接由 BossPage 负责；本页只维护自己的副本/槽位身份和 V2 会话。
function Common:Render(host)
    local dungeonKey = Page:GetCurrentDungeonCommonOptions()
    if not (host and dungeonKey and self:HasContent()) then return false end
    local cfg = ExBoss and ExBoss.BossConfig
    local slotKey = cfg and type(cfg.GetRuntimeSlotForScene) == "function" and cfg:GetRuntimeSlotForScene("mplus") or nil
    if not slotKey then return false end

    UI.host = host
    Common.EnsureFrames(host)
    local hostWidth = math.floor((host:GetWidth() or 0) + 0.5)
    -- SPELL_TEXT_UPDATE 等全局事件可能在一帧内多次触发右侧刷新。通用页
    -- 的结构并不依赖它们；保存/搜索均走 RefreshAuraSoundRows，因此同一
    -- 宿主、同一副本、同一宽度时绝不能再次拆卸整套 V2 会话。
    if UI._renderedHost == host
        and UI._renderedDungeonKey == tostring(dungeonKey)
        and UI.slotKey == slotKey
        and UI.cardSession
        and UI.root:IsShown() then
        if UI._renderedWidth ~= hostWidth then
            UI._renderedWidth = hostWidth
            UI.cardSession:Layout()
        end
        return true
    end
    -- BossPage 宿主在切换到本页前释放自己的设置会话。
    -- 页面只需要当前 runtime slot；实际数据由 VirtualList 的 ID View 按需读取。
    Common.EnsureAuraSoundVirtualListRenderer()
    Common.EnsureAuraSoundHeaderRenderer()
    if UI.cardSession then
        if UI.auraSoundEditor then Common.CloseAuraSoundEditor(UI.auraSoundEditor) end
        if UI.auraSoundCategoryDrawer then Common.CloseAuraSoundCategoryDrawer(UI.auraSoundCategoryDrawer) end
        UI.cardSession:Release()
        UI.cardSession = nil
    end
    UI.slotKey = slotKey
    UI.dungeonKey = dungeonKey
    if not Common._v2PageRegistered then
        LAYOUT = Common:BuildPageLayout()
        ExwindTools.UI:RegisterSettingsPageV2(Common.MODULE_KEY, LAYOUT)
        Common._v2PageRegistered = true
    end
    local owner = Common:CreatePageOwner(dungeonKey, slotKey, host)
    UI.cardSession = ExwindTools.UI:MountSettingsPageV2(UI.gridHost, Common.MODULE_KEY, owner)
    UI.gridHost._exV2Session, UI.gridHost._exV2Owner = UI.cardSession, owner
    ExwindTools.UI.ActivePageFrame = UI.gridHost
    ExwindTools.UI.ActivePageScrollFrame = host:GetParent()
    ExwindTools.UI.CurrentModule = Common.MODULE_KEY
    UI._renderedHost = host
    UI._renderedDungeonKey = tostring(dungeonKey)
    UI._renderedWidth = hostWidth
    return true
end

-- [释放边界] 先关编辑覆盖层，再释放独立 V2 会话/虚拟上下文与 ActivePage 注册；卡片容器不得重复释放或保留上一副本身份。
function Common:Hide()
    self._virtualListRestore = nil
    UI._renderedHost = nil
    UI._renderedDungeonKey = nil
    UI._renderedWidth = nil
    if UI.auraSoundEditor then Common.CloseAuraSoundEditor(UI.auraSoundEditor) end
    if UI.auraSoundCategoryDrawer then Common.CloseAuraSoundCategoryDrawer(UI.auraSoundCategoryDrawer) end
    -- 离开右侧共享区域时归还本页会话，虚拟行不保留上一副本的绑定。
    if UI.cardSession and type(UI.cardSession.Release) == "function" then
        UI.cardSession:Release()
        UI.cardSession = nil
        UI.gridHost._exV2Session, UI.gridHost._exV2Owner = nil, nil
    end
    -- 离开页面后不保留上一副本的行绑定；下次 Mount 重新建立轻量上下文。
    UI.auraSoundVirtualContext = nil
    UI.auraSoundCategoryOtherKeys = nil
    UI.host = nil
    UI.slotKey = nil
    UI.dungeonKey = nil
    -- Clear only a registration owned by this host; never clear another page.
    if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == UI.gridHost then
        ExwindTools.UI.ActivePageFrame = nil
        ExwindTools.UI.ActivePageScrollFrame = nil
        ExwindTools.UI.CurrentModule = nil
    end
    if UI.root then UI.root:Hide() end
end
