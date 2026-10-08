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
-- V2 只排列原有 GUI owner；配置读取、草稿与提交仍由下方原函数负责。
-- 虚拟列表保持固定视口，不使用 repeat 展开全部 action。
local LAYOUT = {}

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

local function RaiseInteractiveChild(frame, parent, levelOffset)
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
    editor:SetParent(parent)
    editor:ClearAllPoints()
    editor:SetPoint("CENTER", parent, "CENTER", 0, 0)
    editor:SetFrameStrata("DIALOG")
    local gridLevel = UI.gridHost and UI.gridHost:GetFrameLevel() or 0
    local parentLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 0
    editor:SetFrameLevel(math.max(gridLevel, parentLevel) + 50)
    RaiseInteractiveChild(editor.close, editor, 2)
    RaiseInteractiveChild(editor.source, editor, 3)
    RaiseInteractiveChild(editor.pack, editor, 3)
    RaiseInteractiveChild(editor.lsm, editor, 3)
    RaiseInteractiveChild(editor.path, editor, 3)
    RaiseInteractiveChild(editor.preview, editor, 4)
    RaiseInteractiveChild(editor.save, editor, 4)
    RaiseInteractiveChild(editor.cancel, editor, 4)
    RaiseInteractiveChild(editor.spellIDInput, editor, 3)
    RaiseInteractiveChild(editor.categoryInput, editor, 3)
    RaiseInteractiveChild(editor.scope, editor, 3)
    RaiseInteractiveChild(editor.auraType, editor, 3)
    RaiseInteractiveChild(editor.trigger, editor, 3)
end

local AURA_SOUND_SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
    { L["自定义路径"], "file" },
}
local ENCOUNTER_VOICE_SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
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

-- Grid 释放 custom renderer 时会清掉 list.context。稳定上下文只保留三个
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
local AURA_SOUND_VISIBLE_ROWS = 12
local AURA_SOUND_LIST_HEIGHT = AURA_SOUND_ROW_HEIGHT * AURA_SOUND_VISIBLE_ROWS

local function AuraSoundTableColumns(width)
    local compact = width < 850
    return {
        { title = "", width = 28 },
        { title = L["光环 Action"], weight = 1.5 },
        { title = L["分类"], width = compact and 68 or 92 },
        { title = L["增/减益"], width = compact and 52 or 64 },
        { title = L["状态"], width = compact and 52 or 64 },
        { title = L["当前声音"], weight = 1 },
        { title = "", width = 52 },
        { title = "", width = 52 },
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
    if parts.add then
        parts.add:ClearAllPoints()
        parts.add:SetPoint("LEFT", frame, "LEFT", rects[7].x, 0)
        parts.add:SetWidth(rects[8].x + rects[8].width - rects[7].x)
    end
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
    row.voice:SetText(hasSound and Common.GetAuraSoundDisplayName(item) or L["未配置声音"])
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
    row.auraType:SetText(AURA_TYPE_LABELS[auraType] or L["减益"])
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

-- [虚拟列表边界] VirtualList/可视行池拥有行创建、绑定与回收；Grid/卡片只拥有固定视口 host，不得展开全量数据或重复释放行。
function Common.EnsureAuraSoundVirtualList(host)
    if not host then return nil end
    -- 列表、可视行和行内下拉属于通用页，而不是会被不同 custom renderer
    -- 反复借出/归还的 GridCustomHost。稳定所有权可避免每次打开都扩张 child 控件。
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
    -- 先同步稳定上下文，再 SetData；后者可能在 Grid release/update 的交错周期
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
    if type(Common.RefreshAuraSoundToolbarSummary) == "function" then
        Common.RefreshAuraSoundToolbarSummary(#items, totalCount)
    end
    if type(Common.RefreshAuraSoundHeaderSelection) == "function" then
        Common:RefreshAuraSoundHeaderSelection()
    end
    list:Show()
end

-- release 只清本 renderer 的绑定/可视行；外层 Grid host 由 Common:Hide 归还，二者不能互相重复释放。
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
    local Grid = _G.ExwindGrid
    if not (Grid and Grid.RegisterCustomRenderer) then return end
    Grid:RegisterCustomRenderer("exboss_dungeon_aura_sound_virtual_list", {
        mount = function(host, context) Common.MountAuraSoundVirtualList(host, context) end,
        update = function(host, context) Common.UpdateAuraSoundVirtualList(host, context) end,
        release = function(host) Common.ReleaseAuraSoundVirtualList(host) end,
    })
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
    local Grid, EXUI = _G.ExwindGrid, ExwindTools.UI
    Grid:RegisterCustomRenderer("exboss_dungeon_aura_sound_header", {
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
                    add = EXUI:CreateButton(host, 116, 28, L["+ 添加声音"], function()
                        Common:AddAuraSound()
                    end, { variant = "primary", compact = true }),
                }
                for _, label in ipairs(labels) do label:SetJustifyH("LEFT") end
                host._auraSoundHeader.check:SetSize(28, 28)
                RaiseInteractiveChild(host._auraSoundHeader.check, host, 3)
                RaiseInteractiveChild(host._auraSoundHeader.add, host, 3)
            end
            UI.auraSoundHeader = host._auraSoundHeader
            host._auraSoundPublicHeader:Show()
            host._auraSoundHeader.check:Show()
            host._auraSoundHeader.add:Show()
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
            host._auraSoundHeader.add:Hide()
        end,
    })
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

local function RefreshAuraSoundCategoryCardStyle(card)
    if not card then return end
    SetAuraThemeText(card.title, card._auraSoundCategorySelected and GC.accent or GC.text)
end

function Common.RefreshAuraSoundCategoryCardLSMFields(card)
    if not (card and card._auraSoundDraft and card.lsm) then return end
    local sound = NormalizeAuraCategorySoundDraft(card._auraSoundDraft)
    card._auraSoundDraft = sound
    card.lsm._selectedValue = sound.customLSM
    local display = sound.customLSM ~= "" and sound.customLSM or L["请选择 LSM 音效"]
    Common.SetAuraSoundDropdownText(card.lsm, display)
end

function Common.CommitAuraSoundCategoryCardLSM(card, value)
    if not (card and card.categoryKey) then return end
    local sound = NormalizeAuraCategorySoundDraft(card._auraSoundDraft)
    sound.sourceType = "lsm"
    sound.customLSM = tostring(value or "")
    card._auraSoundDraft = sound
    card._auraSoundDraftDirty = true
    Common.RefreshAuraSoundCategoryCardLSMFields(card)
    -- 卡片不再显示独立“应用”按钮；用户在 LSM 下拉中明确选中声音即视为
    -- 本次设置操作。仍复用原来的安全应用路径，只逐 action 写入
    -- sourceType/customLSM，语音包标签和自定义路径继续完整保留。
    Common.ApplyAuraSoundCategoryCardLSM(card)
end

function Common.PreviewAuraSoundCategoryCardLSM(card)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (card and card._auraSoundDraft and engine and type(engine.TryPlayStandaloneSound) == "function") then return end
    local sound = NormalizeAuraCategorySoundDraft(card._auraSoundDraft)
    if sound.customLSM == "" then
        card.summary:SetText(L["请先选择 LSM 音效"])
        card.summary:SetTextColor(1.00, 0.46, 0.34)
        return
    end
    engine:TryPlayStandaloneSound({
        enabled = true,
        sourceType = "lsm",
        customLSM = sound.customLSM,
        label = "",
        customPath = "",
    }, "dungeon_aura_card_preview:" .. tostring(card.categoryKey or "preview"), { triggerIndex = 0 })
end

function Common.ApplyAuraSoundCategoryCardLSM(card)
    if not (card and card.categoryKey and UI.dungeonKey and UI.slotKey) then return end
    local sound = NormalizeAuraCategorySoundDraft(card._auraSoundDraft)
    if sound.customLSM == "" then
        card.summary:SetText(L["请先选择 LSM 音效"])
        card.summary:SetTextColor(1.00, 0.46, 0.34)
        return
    end
    local view = GetAuraSoundView(UI.dungeonKey, UI.slotKey)
    local affected = 0
    for _, actionID in ipairs(type(view) == "table" and view.actionIDs or {}) do
        local current = GetAuraSoundActionView(UI.dungeonKey, UI.slotKey, actionID)
        if type(current) == "table" then
            current = GetAuraSoundItemView(current)
            if current.category == card.categoryKey then
                affected = affected + 1
                -- 切换分类当前生效的来源，只写 LSM 必需的两个叶子。
                -- 旧的语音包标签/文件路径继续原样留在 action 内，日后切回时
                -- 仍可使用；这次重构绝不以切换显示方式为代价清空用户资料。
                local desired = {
                    sourceType = "lsm",
                    customLSM = sound.customLSM,
                }
                local fields = {}
                for field, value in pairs(desired) do
                    if tostring(current[field] or "") ~= tostring(value) then
                        fields[field] = value
                    end
                end
                if next(fields) then
                    local committed, reason = SetAuraSoundActionFields(UI.dungeonKey, UI.slotKey, actionID, fields)
                    if not committed then
                        card.summary:SetText(tostring(reason or L["光环声音保存失败"]))
                        card.summary:SetTextColor(1.00, 0.46, 0.34)
                        Common:RefreshAuraSoundRows()
                        return
                    end
                end
            end
        end
    end
    if affected == 0 then
        card.summary:SetText(L["此分类暂时没有 action"])
        card.summary:SetTextColor(1.00, 0.68, 0.34)
        return
    end
    card._auraSoundDraftDirty = nil
    Common:RefreshAuraSoundRows()
end

function Common.RefreshAuraSoundCategoryCard(host)
    local card = host and host._auraSoundCategoryCard
    local categoryKey = host and host._auraSoundCategoryKey
    local meta = AURA_CATEGORY_SHORTCUTS_BY_KEY[categoryKey]
    if not (card and meta) then return end
    local _, soundSummary = Common.GetAuraSoundCategorySummary(UI.dungeonKey, UI.slotKey, categoryKey)
    local color = meta.color
    card.title:SetText(meta.label)
    card.hint:SetText(meta.hint or "")
    card._auraSoundCategorySelected = NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter) == categoryKey
    card.summary:SetText(soundSummary)
    SetAuraThemeText(card.summary, AURA_UI_THEME.ink)
    card.categoryKey = categoryKey
    card._auraSoundDraft = GetAuraSoundCategorySoundDraft(UI.dungeonKey, UI.slotKey, categoryKey)
    card._auraSoundDraftDirty = nil
    Common.RefreshAuraSoundCategoryCardLSMFields(card)
    card._auraSoundCategoryColor = color
    RefreshAuraSoundCategoryCardStyle(card)
    card:Show()
end

function Common:RefreshAuraSoundCategoryCards()
    for _, host in pairs(UI.auraSoundCategoryCardHosts or {}) do
        Common.RefreshAuraSoundCategoryCard(host)
    end
end

function Common:RefreshAuraSoundCategoryCardSelection()
    for _, host in pairs(UI.auraSoundCategoryCardHosts or {}) do
        local card = host and host._auraSoundCategoryCard
        local categoryKey = host and host._auraSoundCategoryKey
        if card and categoryKey then
            card._auraSoundCategorySelected = NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter) == categoryKey
            RefreshAuraSoundCategoryCardStyle(card)
        end
    end
end

function Common:RefreshAuraSoundCategoryFilterSelection()
    local panel = UI.auraSoundCategoryFilterControl
    if panel and panel.choice then
        panel.choice:SetValue(NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter))
    end
end

function Common.RefreshAuraSoundCategoryFilterControl(focusSelection)
    local panel = UI.auraSoundCategoryFilterControl
    if not panel then return end
    local items = GetAuraSoundCategoryFilterItems(UI.dungeonKey, UI.slotKey)
    local options = {}
    for _, item in ipairs(items) do
        options[#options + 1] = {
            id = NormalizeAuraSoundCategoryFilter(item[2]),
            label = string.format("%s(%d)", tostring(item[1]), math.max(0, tonumber(item[3]) or 0)),
        }
    end
    panel.choice:SetItems(options)
    Common:RefreshAuraSoundCategoryFilterSelection()
    if panel:GetParent()._auraV2Context then panel:GetParent()._auraV2Context:Invalidate() end
end

function Common.SetAuraSoundCategoryFilter(categoryKey)
    categoryKey = NormalizeAuraSoundCategoryFilter(categoryKey)
    if NormalizeAuraSoundCategoryFilter(UI.auraSoundCategoryFilter) == categoryKey then return end
    UI.auraSoundCategoryFilter = categoryKey
    -- 切换分类只是显示状态变化：两个卡片区只换高亮，只有下方可见行需要重绑。
    Common:RefreshAuraSoundCategoryCardSelection()
    Common:RefreshAuraSoundCategoryFilterSelection()
    Common:RefreshAuraSoundFilteredList()
end

-- [自定义卡边界] 分类卡 renderer 可换外观/几何，但筛选身份、LSM 提交/试听与 mount/update/release 归属禁止修改。
function Common.EnsureAuraSoundCategoryCardRenderer()
    if Common._auraSoundCategoryCardRendererRegistered then return end
    local Grid, EXUI = _G.ExwindGrid, ExwindTools.UI
    Grid:RegisterCustomRenderer("exboss_dungeon_aura_sound_category_card", {
        mount = function(host, context)
            if not host._auraSoundCategoryCard then
                local card = CreateFrame("Frame", nil, host)
                card:SetAllPoints(host)
                card:EnableMouse(true)
                card.title = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontHighlight")
                card.hint = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontNormalSmall")
                local hintFont, _, hintFlags = card.hint:GetFont()
                card.hint:SetFont(hintFont, 11, hintFlags)
                card.hint:SetJustifyH("LEFT")
                card.hint:SetWordWrap(true)
                SetAuraThemeText(card.hint, GC.textDim)
                card.summary = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontNormalSmall")
                card.summary:Hide()
                card.lsm = EXUI:CreateLSMSoundDropdown(card, 240, "", "", function(value)
                    Common.CommitAuraSoundCategoryCardLSM(card, value)
                end, true)
                card:SetScript("OnMouseUp", function(_, button)
                    if button == "LeftButton" and card.categoryKey then
                        Common.SetAuraSoundCategoryFilter(card.categoryKey)
                    end
                end)
                RaiseInteractiveChild(card.lsm, card, 3)
                host._auraSoundCategoryCard = card
            end
            host._auraSoundCategoryKey = context.element.categoryKey
            UI.auraSoundCategoryCardHosts = UI.auraSoundCategoryCardHosts or {}
            UI.auraSoundCategoryCardHosts[host._auraSoundCategoryKey] = host
            Common.RefreshAuraSoundCategoryCard(host)
        end,
        update = function(host) Common.RefreshAuraSoundCategoryCard(host) end,
        release = function(host)
            if UI.auraSoundCategoryCardHosts then UI.auraSoundCategoryCardHosts[host._auraSoundCategoryKey] = nil end
            if host._auraSoundCategoryCard.lsm.CloseMenu then host._auraSoundCategoryCard.lsm:CloseMenu() end
            host._auraSoundCategoryCard:Hide()
        end,
    })
    Common._auraSoundCategoryCardRendererRegistered = true
end

function Common.EnsureAuraSoundCategoryFilterRenderer()
    if Common._auraSoundCategoryFilterRendererRegistered then return end
    local Grid, EXUI = _G.ExwindGrid, ExwindTools.UI
    Grid:RegisterCustomRenderer("exboss_dungeon_aura_sound_category_filter_cards", {
        mount = function(host)
            if not host._auraSoundCategoryFilter then
                local panel = CreateFrame("Frame", nil, host)
                panel:SetAllPoints(host)
                panel.choice = EXUI:CreateSegmentedControl(panel, 240, {}, "",
                    function(value) Common.SetAuraSoundCategoryFilter(value) end,
                    { height = ExwindTools.GUIMetrics.size.controlHeight })
                panel.choice:SetPoint("TOPLEFT")
                host._auraSoundCategoryFilter = panel
            end
            UI.auraSoundCategoryFilterControl = host._auraSoundCategoryFilter
            Common.RefreshAuraSoundCategoryFilterControl()
            UI.auraSoundCategoryFilterControl:Show()
        end,
        update = function() end,
        release = function(host)
            if UI.auraSoundCategoryFilterControl == host._auraSoundCategoryFilter then UI.auraSoundCategoryFilterControl = nil end
            host._auraSoundCategoryFilter:Hide()
        end,
    })
    Common._auraSoundCategoryFilterRendererRegistered = true
end

local function PositionAuraSoundCategoryDrawer(drawer, parent)
    if not (drawer and parent) then return end
    drawer:SetParent(parent)
    drawer:ClearAllPoints()
    drawer:SetPoint("CENTER", parent, "CENTER", 0, 0)
    drawer:SetFrameStrata(parent:GetFrameStrata() or "DIALOG")
    drawer:SetFrameLevel(math.max(UI.gridHost and UI.gridHost:GetFrameLevel() or 0, parent:GetFrameLevel() or 0) + 60)
    RaiseInteractiveChild(drawer.close, drawer, 3)
    RaiseInteractiveChild(drawer.search, drawer, 3)
    RaiseInteractiveChild(drawer.cancel, drawer, 4)
    RaiseInteractiveChild(drawer.save, drawer, 4)
end

function Common.RefreshAuraSoundCategoryDrawerSelection(drawer)
    if not drawer then return 0 end
    local selected = 0
    for _, actionID in ipairs(drawer.actionIDs or {}) do
        if drawer.draftMembers and drawer.draftMembers[actionID] then selected = selected + 1 end
    end
    drawer.selectionSummary:SetText(string.format(L["已选择 %d / %d 个 action"], selected, #(drawer.actionIDs or {})))
    return selected
end

function Common.BindAuraSoundCategoryDrawerRow(row, entry, _, context)
    local drawer = context and context.drawer
    local actionID = entry and entry.actionID
    if not (drawer and actionID) then
        row:Hide()
        return
    end
    local current = GetAuraSoundActionView(drawer.dungeonKey, drawer.slotKey, actionID)
    if type(current) ~= "table" then
        row:Hide()
        return
    end
    current = GetAuraSoundItemView(current)
    row._auraSoundCategoryDrawer = drawer
    row._auraSoundCategoryActionID = actionID
    row.check:SetChecked(drawer.draftMembers[actionID] == true)
    local name, icon, spellID = GetAuraSpellInfo(current)
    row.icon:SetTexture(icon)
    row.title:SetText(name)
    row.detail:SetText(string.format("[%d] · %s", spellID, Common.GetAuraSoundCategoryLabel(current.category)))
    row.sound:SetText(GetAuraCategorySoundSummary(current))
    row:Show()
end

function Common.CreateAuraSoundCategoryDrawerRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetBackdrop(AURA_FLAT_BACKDROP)
    row:SetBackdropColor(
        AURA_UI_THEME.panelDeep[1], AURA_UI_THEME.panelDeep[2],
        AURA_UI_THEME.panelDeep[3], AURA_UI_THEME.panelDeep[4]
    )
    row:SetBackdropBorderColor(
        AURA_UI_THEME.line[1], AURA_UI_THEME.line[2], AURA_UI_THEME.line[3], 0.10
    )
    row.check = ExwindTools.UI:CreateCheckbox(row, "", false, function(checked)
        local drawer = row._auraSoundCategoryDrawer
        local actionID = row._auraSoundCategoryActionID
        if drawer and actionID then
            drawer.draftMembers[actionID] = checked == true
            Common.RefreshAuraSoundCategoryDrawerSelection(drawer)
        end
    end)
    row.check:SetSize(28, 28)
    row.check:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.icon = ExwindTools.UI:CreateVisualTexture(row, EXBASEFRAME)
    row.icon:SetSize(27, 27)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.title = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -1)
    row.title:SetPoint("RIGHT", row, "RIGHT", -190, -1)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.title, "BOTTOMLEFT", 0, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -190, 1)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    SetAuraThemeText(row.detail, AURA_UI_THEME.muted)
    row.sound = ExwindTools.UI:CreateVisualFontString(row, EXFONTFRAME, "GameFontNormalSmall")
    row.sound:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.sound:SetWidth(170)
    row.sound:SetJustifyH("RIGHT")
    row.sound:SetWordWrap(false)
    SetAuraThemeText(row.sound, AURA_UI_THEME.ink)
    row:SetScript("OnEnter", function(frame)
        frame:SetBackdropColor(
            AURA_UI_THEME.panelHover[1], AURA_UI_THEME.panelHover[2],
            AURA_UI_THEME.panelHover[3], AURA_UI_THEME.panelHover[4]
        )
    end)
    row:SetScript("OnLeave", function(frame)
        frame:SetBackdropColor(
            AURA_UI_THEME.panelDeep[1], AURA_UI_THEME.panelDeep[2],
            AURA_UI_THEME.panelDeep[3], AURA_UI_THEME.panelDeep[4]
        )
    end)
    return row
end

function Common.RefreshAuraSoundCategoryDrawerList(drawer)
    if not (drawer and drawer.list) then return end
    local needle = NormalizeAuraSoundSearchText(drawer.searchText)
    local entries = {}
    for _, actionID in ipairs(drawer.actionIDs or {}) do
        local row = GetAuraSoundActionView(drawer.dungeonKey, drawer.slotKey, actionID)
        if type(row) == "table" and AuraSoundRowMatchesSearch(row, needle) then
            entries[#entries + 1] = { actionID = actionID }
        end
    end
    drawer.list:SetData(entries, { drawer = drawer })
    drawer.list:Show()
    Common.RefreshAuraSoundCategoryDrawerSelection(drawer)
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
    if drawer.search:GetText() ~= "" then drawer.search:SetText("") end
    Common.RefreshAuraSoundCategoryDrawerList(drawer)
end

function Common.CloseAuraSoundCategoryDrawer(drawer)
    if not drawer then return end
    -- 抽屉内始终只有 UI 草稿；关闭、取消与外部 Hide 都不能触碰 action 配置。
    drawer.actionIDs = nil
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
    if not parent then return nil end
    if UI.auraSoundCategoryDrawer then
        PositionAuraSoundCategoryDrawer(UI.auraSoundCategoryDrawer, parent)
        return UI.auraSoundCategoryDrawer
    end
    local EXUI = ExwindTools.UI
    local VirtualList = _G.ExwindVirtualList
    if not (EXUI and EXUI.CreateEditBox and EXUI.CreateButton and VirtualList and VirtualList.Create) then
        return nil
    end
    local drawer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    drawer:SetSize(680, 550)
    drawer:SetBackdrop(AURA_FLAT_BACKDROP)
    drawer:SetBackdropColor(
        AURA_UI_THEME.panel[1], AURA_UI_THEME.panel[2],
        AURA_UI_THEME.panel[3], 0.99
    )
    drawer:SetBackdropBorderColor(
        AURA_UI_THEME.lineStrong[1], AURA_UI_THEME.lineStrong[2],
        AURA_UI_THEME.lineStrong[3], 0.72
    )
    drawer:Hide()
    drawer:SetScript("OnHide", function(frame)
        frame.actionIDs = nil
        frame.originalMembers = nil
        frame.draftMembers = nil
        frame.categoryKey = nil
        frame.dungeonKey = nil
        frame.slotKey = nil
    end)
    drawer.title = ExwindTools.UI:CreateVisualFontString(drawer, EXFONTFRAME, "GameFontNormalLarge")
    drawer.title:SetPoint("TOPLEFT", 18, -16)
    SetAuraThemeText(drawer.title, AURA_UI_THEME.ink)
    drawer.subtitle = ExwindTools.UI:CreateVisualFontString(drawer, EXFONTFRAME, "GameFontNormalSmall")
    drawer.subtitle:SetPoint("TOPLEFT", drawer.title, "BOTTOMLEFT", 0, -2)
    drawer.subtitle:SetText(L["勾选 action 归入此分类；音效仅在上方卡片设置。"])
    SetAuraThemeText(drawer.subtitle, AURA_UI_THEME.muted)
    drawer.close = CreateFrame("Button", nil, drawer, "UIPanelCloseButton")
    drawer.close:SetSize(28, 28)
    drawer.close:SetPoint("TOPRIGHT", -5, -5)
    drawer.close:SetScript("OnClick", function() Common.CloseAuraSoundCategoryDrawer(drawer) end)
    drawer.search = EXUI:CreateSearchBox(drawer, "", 290, 30, {
        onChanged = function(text)
            drawer.searchText = tostring(text or "")
            Common.RefreshAuraSoundCategoryDrawerList(drawer)
        end,
    })
    drawer.search:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -18, -57)
    drawer.selectionSummary = ExwindTools.UI:CreateVisualFontString(drawer, EXFONTFRAME, "GameFontHighlight")
    drawer.selectionSummary:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -18, -94)
    drawer.selectionSummary:SetJustifyH("RIGHT")
    SetAuraThemeText(drawer.selectionSummary, AURA_UI_THEME.muted)
    drawer.listHost = CreateFrame("Frame", nil, drawer)
    drawer.listHost:SetPoint("TOPLEFT", drawer, "TOPLEFT", 18, -122)
    drawer.listHost:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -18, 57)
    drawer.list = VirtualList:Create(drawer.listHost, {
        rowHeight = 38,
        overscan = 0,
        maxRows = 12,
        createRow = function(listParent) return Common.CreateAuraSoundCategoryDrawerRow(listParent) end,
        bindRow = function(row, entry, index, context) Common.BindAuraSoundCategoryDrawerRow(row, entry, index, context) end,
    })
    drawer.list:SetPoint("TOPLEFT", drawer.listHost, "TOPLEFT", 0, 0)
    drawer.list:SetPoint("BOTTOMRIGHT", drawer.listHost, "BOTTOMRIGHT", 0, 0)
    if drawer.list.SetClipsChildren then drawer.list:SetClipsChildren(true) end
    drawer.cancel = CreateAuraPrototypeButton(drawer, 100, 30, L["取消"], function() Common.CloseAuraSoundCategoryDrawer(drawer) end)
    drawer.cancel:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 18, 17)
    drawer.save = CreateAuraPrototypeButton(drawer, 100, 30, L["应用"], function() Common.SaveAuraSoundCategoryDrawer(drawer) end)
    drawer.save:SetPoint("LEFT", drawer.cancel, "RIGHT", 10, 0)
    drawer.error = ExwindTools.UI:CreateVisualFontString(drawer, EXFONTFRAME, "GameFontNormalSmall")
    drawer.error:SetPoint("BOTTOM", drawer, "BOTTOM", 0, 25)
    drawer.error:SetTextColor(1.00, 0.35, 0.35)
    PositionAuraSoundCategoryDrawer(drawer, parent)
    UI.auraSoundCategoryDrawer = drawer
    return drawer
end

function Common:ShowAuraSoundCategoryDrawer(categoryKey)
    local meta = AURA_CATEGORY_SHORTCUTS_BY_KEY[categoryKey]
    if not (meta and UI.dungeonKey and UI.slotKey) then return end
    local drawer = Common.EnsureAuraSoundCategoryDrawer(UI.root or UI.host)
    if not drawer then return end
    drawer.categoryKey = meta.key
    drawer.dungeonKey = UI.dungeonKey
    drawer.slotKey = UI.slotKey
    drawer.title:SetText(string.format(L["%s · 分类管理"], meta.label))
    if drawer.error then drawer.error:SetText("") end
    Common.PopulateAuraSoundCategoryDrawer(drawer)
    drawer:Show()
end

-- Boss 专属额外机制复用这套语音封装；数据由 Grid setter 写回对应 encounterOptions。
local function NormalizeEncounterVoiceConfig(value)
    local row = type(value) == "table" and value or {}
    row.enabled = row.enabled ~= false
    row.sourceType = row.sourceType == "lsm" and "lsm" or "pack"
    row.label = tostring(row.label or "")
    row.customLSM = tostring(row.customLSM or "")
    return row
end

function Common.BuildEncounterVoiceSummary(row)
    row = NormalizeEncounterVoiceConfig(row)
    local selected = row.sourceType == "lsm" and row.customLSM or row.label
    if selected == "" then selected = L["未选择"] end
    return string.format("%s：%s", Common.GetAuraSoundSourceLabel(row.sourceType), selected)
end

function Common.RefreshEncounterVoiceHost(host, context)
    if not (host and context) then return end
    local row = NormalizeEncounterVoiceConfig(context.currentValue)
    host._encounterVoiceContext = context
    host._encounterVoiceRow = row
    local index = tonumber(context.element and context.element.voiceIndex) or 1
    host.enable:SetChecked(row.enabled ~= false)
    host.title:SetText(string.format(L["第%d断语音"], index))
    host.summary:SetText(Common.BuildEncounterVoiceSummary(row))
    host.summary:SetTextColor(row.enabled ~= false and 0.75 or 0.45, row.enabled ~= false and 0.86 or 0.45, row.enabled ~= false and 1 or 0.45, 1)
    host.enable:Show()
    host.title:Show()
    host.summary:Show()
    host.configure:Show()
    host.preview:Show()
end

function Common.SaveEncounterVoiceHost(host)
    local context = host and host._encounterVoiceContext
    local row = host and NormalizeEncounterVoiceConfig(host._encounterVoiceRow) or nil
    if not (context and row and type(context.setter) == "function") then return end
    context.currentValue = row
    context.setter(row)
    Common.RefreshEncounterVoiceHost(host, context)
end

function Common.PreviewEncounterVoiceHost(host)
    local context = host and host._encounterVoiceContext
    local row = host and NormalizeEncounterVoiceConfig(host._encounterVoiceRow) or nil
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (context and row and engine and type(engine.TryPlayStandaloneSound) == "function") then return end
    engine:TryPlayStandaloneSound(row, "exboss:encounter_voice_preview:" .. tostring(context.fullPath or ""), {
        triggerIndex = tonumber(context.element and context.element.voiceIndex) or 0,
    })
end

function Common.RefreshEncounterVoiceEditor(editor)
    if not (editor and editor.row) then return end
    local row = NormalizeEncounterVoiceConfig(editor.row)
    editor.row = row
    local isLSM = row.sourceType == "lsm"
    editor.source._currentValue = row.sourceType
    Common.SetAuraSoundDropdownText(editor.source, Common.GetAuraSoundSourceLabel(row.sourceType))
    editor.pack._items = Common.GetAuraSoundPackItems()
    editor.pack._currentValue = row.label
    Common.SetAuraSoundDropdownText(editor.pack, row.label ~= "" and (L[row.label] or row.label) or L["请选择..."])
    editor.lsm._selectedValue = row.customLSM
    Common.SetAuraSoundDropdownText(editor.lsm, row.customLSM ~= "" and row.customLSM or L["请选择..."])
    editor.pack:SetShown(not isLSM)
    editor.lsm:SetShown(isLSM)
    editor.valueLabel:SetText(isLSM and L["LSM音效"] or L["语音包标签"])
    local index = tonumber(editor.host and editor.host._encounterVoiceContext and editor.host._encounterVoiceContext.element.voiceIndex) or 1
    editor.title:SetText(string.format(L["第%d断语音"], index))
end

function Common.SaveEncounterVoiceEditor(editor)
    local host = editor and editor.host
    if not (host and editor.row) then return end
    host._encounterVoiceRow = NormalizeEncounterVoiceConfig(editor.row)
    Common.SaveEncounterVoiceHost(host)
end

function Common.EnsureEncounterVoiceEditor(parent)
    if UI.encounterVoiceEditor then
        PositionVoiceEditor(UI.encounterVoiceEditor, parent or UI.root)
        return UI.encounterVoiceEditor
    end
    local EXUI = ExwindTools.UI
    if not (parent and EXUI and EXUI.CreateDropdown and EXUI.CreateEditBox and EXUI.CreateLSMSoundDropdown and EXUI.CreateButton) then return nil end
    local editor = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    editor:SetSize(510, 250)
    editor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    editor:SetBackdropColor(unpack(GC.popup))
    editor:SetBackdropBorderColor(unpack(GC.popupBorder))
    editor:Hide()
    editor.title = ExwindTools.UI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontNormalLarge")
    editor.title:SetPoint("TOPLEFT", 18, -16)
    editor.title:SetTextColor(unpack(GC.text))
    editor.close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    editor.close:SetSize(28, 28)
    editor.close:SetPoint("TOPRIGHT", -5, -5)
    editor.close:SetScript("OnClick", function() editor:Hide() end)
    editor.source = EXUI:CreateDropdown(editor, 185, L["来源"], ENCOUNTER_VOICE_SOURCE_ITEMS, "pack", function(value)
        if not editor.row then return end
        editor.row.sourceType = value == "lsm" and "lsm" or "pack"
        Common.SaveEncounterVoiceEditor(editor)
        Common.RefreshEncounterVoiceEditor(editor)
    end)
    editor.source:SetPoint("TOPLEFT", 18, -75)
    editor.valueLabel = ExwindTools.UI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontHighlight")
    editor.valueLabel:SetPoint("TOPLEFT", 18, -133)
    editor.pack = EXUI:CreateDropdown(editor, 300, "", {}, "", function(value)
        if not editor.row then return end
        editor.row.label = tostring(value or "")
        Common.SaveEncounterVoiceEditor(editor)
        Common.RefreshEncounterVoiceEditor(editor)
    end, { searchable = true, previewPath = ResolvePackPreviewPath })
    editor.pack:SetPoint("TOPLEFT", 18, -155)
    editor.lsm = EXUI:CreateLSMSoundDropdown(editor, 300, "", "", function(value)
        if not editor.row then return end
        editor.row.customLSM = tostring(value or "")
        Common.SaveEncounterVoiceEditor(editor)
        Common.RefreshEncounterVoiceEditor(editor)
    end, true)
    editor.lsm:SetPoint("TOPLEFT", 18, -155)
    editor.preview = EXUI:CreateButton(editor, 110, 30, L["试听"], function()
        Common.PreviewEncounterVoiceHost(editor.host)
    end)
    editor.preview:SetPoint("BOTTOMRIGHT", -18, 18)
    PositionVoiceEditor(editor, parent)
    UI.encounterVoiceEditor = editor
    return editor
end

function Common.ShowEncounterVoiceEditor(host)
    local context = host and host._encounterVoiceContext
    if not context then return end
    local editor = Common.EnsureEncounterVoiceEditor(UI.root or host)
    if not editor then return end
    editor.host = host
    editor.row = NormalizeEncounterVoiceConfig(host._encounterVoiceRow)
    Common.RefreshEncounterVoiceEditor(editor)
    editor:Show()
end

function Common.EnsureEncounterVoiceRenderer()
    if Common._encounterVoiceRendererRegistered then return end
    local Grid = _G.ExwindGrid
    if not (Grid and Grid.RegisterCustomRenderer) then return end
    Grid:RegisterCustomRenderer("exboss_encounter_voice_config", {
        mount = function(host, context)
            if not host._encounterVoiceBuilt then
                host._encounterVoiceBuilt = true
                host.enable = ExwindTools.UI:CreateCheckbox(host, "", true, function(checked)
                    local row = NormalizeEncounterVoiceConfig(host._encounterVoiceRow)
                    row.enabled = checked == true
                    host._encounterVoiceRow = row
                    Common.SaveEncounterVoiceHost(host)
                end)
                host.enable:SetSize(28, 28)
                host.enable:SetPoint("LEFT", host, "LEFT", 0, 0)
                RaiseInteractiveChild(host.enable, host, 2)
                host.title = ExwindTools.UI:CreateVisualFontString(host, EXFONTFRAME, "GameFontHighlight")
                host.title:SetPoint("LEFT", host.enable, "RIGHT", 3, 0)
                host.summary = ExwindTools.UI:CreateVisualFontString(host, EXFONTFRAME, "GameFontNormalSmall")
                host.summary:SetPoint("LEFT", host.title, "RIGHT", 12, 0)
                host.summary:SetPoint("RIGHT", host, "RIGHT", -164, 0)
                host.summary:SetJustifyH("LEFT")
                host.configure = ExwindTools.UI:CreateButton(host, 80, 24, L["设置语音"], function()
                    Common.ShowEncounterVoiceEditor(host)
                end)
                host.configure:SetPoint("RIGHT", host, "RIGHT", -78, 0)
                RaiseInteractiveChild(host.configure, host, 3)
                host.preview = ExwindTools.UI:CreateButton(host, 66, 24, L["试听"], function(button)
                    Common.PreviewEncounterVoiceHost(button:GetParent())
                end, { compact = true })
                host.preview:SetPoint("RIGHT", host, "RIGHT", 0, 0)
            end
            Common.RefreshEncounterVoiceHost(host, context)
        end,
        update = function(host, context)
            Common.RefreshEncounterVoiceHost(host, context)
        end,
        release = function(host)
            host._encounterVoiceContext = nil
            host._encounterVoiceRow = nil
            if host.enable then host.enable:Hide() end
            if host.title then host.title:Hide() end
            if host.summary then host.summary:Hide() end
            if host.configure then host.configure:Hide() end
            if host.preview then host.preview:Hide() end
        end,
    })
    Common._encounterVoiceRendererRegistered = true
end

-- [共享宿主边界] root/gridHost 覆盖 Boss 的同一右侧 scroll child；只可迁移锚点/外观，不能改 parent、strata、一次释放或高度稳定 guard。
function Common.EnsureFrames(host)
    if not host then return nil end
    local created = false
    if not UI.root then
        -- 新页面必须完全取代旧的 Boss 法术 Grid，不能只在其上透明叠层。
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
    -- 尺寸；同一页的重复刷新若先把内容高度压回 viewport，再由 Grid 撑开，
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
    local row = NormalizeAuraSoundItem(editor.row)
    editor.row = row
    local isLSM = row.sourceType == "lsm"
    local isFile = row.sourceType == "file"
    -- Factory catalog actions lock spell identity and listening target.
    local isCatalogAction = editor.isCatalogAction == true
    local name, icon, spellID = GetAuraSpellInfo(row)
    editor.icon:SetTexture(icon)
    editor.spellSummary:SetText(string.format("%s %s[%d]|r", name, GC.markup.placeholder, spellID))
    editor.spellIDInput:SetShown(not isCatalogAction)
    editor.scope:SetShown(not isCatalogAction)
    editor.auraType:SetShown(not isCatalogAction)
    if not isCatalogAction then
        editor.spellIDInput:SetText(spellID > 0 and tostring(spellID) or "")
    end

    -- Catalog actions use the compact editor; user actions expose spell ID and
    -- target fields. Both modes share the same save path.
    if isCatalogAction then
        editor:SetSize(480, 330)
        editor.trigger:ClearAllPoints()
        editor.trigger:SetPoint("TOPLEFT", 18, -88)
        editor.source:ClearAllPoints()
        editor.source:SetPoint("TOPLEFT", 18, -142)
        editor.valueLabel:ClearAllPoints()
        editor.valueLabel:SetPoint("TOPLEFT", 18, -196)
        editor.pack:ClearAllPoints()
        editor.pack:SetPoint("TOPLEFT", 18, -218)
        editor.lsm:ClearAllPoints()
        editor.lsm:SetPoint("TOPLEFT", 18, -218)
        editor.path:ClearAllPoints()
        editor.path:SetPoint("TOPLEFT", 18, -218)
    else
        editor:SetSize(540, 420)
        editor.trigger:ClearAllPoints()
        editor.trigger:SetPoint("TOPLEFT", 18, -142)
        editor.source:ClearAllPoints()
        editor.source:SetPoint("TOPLEFT", 18, -196)
        editor.valueLabel:ClearAllPoints()
        editor.valueLabel:SetPoint("TOPLEFT", 18, -250)
        editor.pack:ClearAllPoints()
        editor.pack:SetPoint("TOPLEFT", 18, -272)
        editor.lsm:ClearAllPoints()
        editor.lsm:SetPoint("TOPLEFT", 18, -272)
        editor.path:ClearAllPoints()
        editor.path:SetPoint("TOPLEFT", 18, -272)
    end
    -- 分类仍是 Factory / SavedVariables 的稳定字段，但不在单条声音编辑器开放；
    -- 编辑声音时绝不触碰它，已有归类会随 action 原样保留。
    editor.categoryInput:Hide()
    editor.scope._currentValue = row.unit
    Common.SetAuraSoundDropdownText(editor.scope, Common.GetAuraSoundUnitLabel(row))
    editor.auraType._currentValue = row.auraType
    Common.SetAuraSoundDropdownText(editor.auraType, row.auraType == "buff" and L["BUFF"] or L["DEBUFF"])
    editor.trigger._currentValue = row.trigger
    Common.SetAuraSoundDropdownText(editor.trigger, Common.GetAuraSoundTriggerLabel(row.trigger))
    editor.source._currentValue = isLSM and "lsm" or isFile and "file" or "pack"
    Common.SetAuraSoundDropdownText(editor.source, Common.GetAuraSoundSourceLabel(editor.source._currentValue))
    editor.pack._items = Common.GetAuraSoundPackItems()
    editor.pack._currentValue = tostring(row.label or "")
    Common.SetAuraSoundDropdownText(editor.pack, editor.pack._currentValue ~= "" and (L[editor.pack._currentValue] or editor.pack._currentValue) or L["请选择..."])
    editor.lsm._selectedValue = tostring(row.customLSM or "")
    Common.SetAuraSoundDropdownText(editor.lsm, editor.lsm._selectedValue ~= "" and editor.lsm._selectedValue or L["请选择..."])
    editor.path:SetText(tostring(row.customPath or ""))
    editor.pack:SetShown(not isLSM and not isFile)
    editor.lsm:SetShown(isLSM)
    editor.path:SetShown(isFile)
    editor.valueLabel:SetText(Common.GetAuraSoundSourceLabel(row.sourceType))
    -- 新增与编辑是两种明确事务：新增只能确认/取消；已有 action 只能字段保存/取消。
    if editor.save then
        editor.save:SetText(editor.isNewAuraSoundAction and L["确认新增"] or L["保存"])
    end
    if editor.cancel then editor.cancel:Show() end
    if editor.error then editor.error:SetText("") end
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
    if not parent then return nil end
    if UI.auraSoundEditor then
        PositionVoiceEditor(UI.auraSoundEditor, parent)
        return UI.auraSoundEditor
    end
    local EXUI = ExwindTools.UI
    if not (parent and EXUI and EXUI.CreateDropdown and EXUI.CreateEditBox and EXUI.CreateLSMSoundDropdown and EXUI.CreateButton) then return nil end
    local editor = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    editor:SetSize(540, 420)
    editor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    editor:SetBackdropColor(unpack(GC.popup))
    editor:SetBackdropBorderColor(unpack(GC.popupBorder))
    editor:Hide()
    -- 关闭按钮、取消、父页面 Hide 甚至外部 Hide 都走同一释放语义。不能让
    -- Frame 在 RegisteredLayouts/父级存活时继续抓住上一条 action 草稿。
    editor:SetScript("OnHide", function(frame)
        frame.db = nil
        frame.itemID = nil
        frame.touched = nil
        frame.row = nil
        frame.isNewAuraSoundAction = false
        frame.isCatalogAction = false
    end)
    editor.title = ExwindTools.UI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontNormalLarge")
    editor.title:SetPoint("TOPLEFT", 18, -16)
    editor.title:SetTextColor(unpack(GC.text))
    editor.title:SetText(L["光环声音"])
    editor.icon = ExwindTools.UI:CreateVisualTexture(editor, EXBASEFRAME)
    editor.icon:SetSize(26, 26)
    editor.icon:SetPoint("TOPLEFT", 18, -48)
    editor.spellSummary = ExwindTools.UI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontHighlight")
    editor.spellSummary:SetPoint("LEFT", editor.icon, "RIGHT", 7, 0)
    editor.spellSummary:SetPoint("RIGHT", editor, "RIGHT", -46, 0)
    editor.spellSummary:SetJustifyH("LEFT")
    editor.close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    editor.close:SetSize(28, 28)
    editor.close:SetPoint("TOPRIGHT", -5, -5)
    editor.close:SetScript("OnClick", function() Common.CloseAuraSoundEditor(editor) end)
    editor.spellIDInput = EXUI:CreateEditBox(editor, "", 150, 28, L["法术ID"], {
        onEditFocusLost = function(value) Common.CommitAuraSoundEditor(editor, "spellID", value) end,
        onEnter = function(value) Common.CommitAuraSoundEditor(editor, "spellID", value) end,
    })
    editor.spellIDInput:SetPoint("TOPLEFT", 18, -88)
    editor.scope = EXUI:CreateDropdown(editor, 150, L["单位"], AURA_UNIT_ITEMS, "player", function(value)
        Common.CommitAuraSoundEditor(editor, "unit", value == "party" and "party" or value == "enemy" and "enemy" or "player")
    end)
    editor.scope:SetPoint("TOPLEFT", 178, -88)
    editor.auraType = EXUI:CreateDropdown(editor, 150, L["光环类型"], AURA_TYPE_ITEMS, "debuff", function(value)
        Common.CommitAuraSoundEditor(editor, "auraType", value == "buff" and "buff" or "debuff")
    end)
    editor.auraType:SetPoint("TOPLEFT", 338, -88)
    editor.categoryInput = EXUI:CreateEditBox(editor, "", 160, 28, L["分类"], {
        onEditFocusLost = function(value) Common.CommitAuraSoundEditor(editor, "category", value) end,
        onEnter = function(value) Common.CommitAuraSoundEditor(editor, "category", value) end,
    })
    editor.categoryInput:SetPoint("TOPLEFT", 18, -142)
    editor.trigger = EXUI:CreateDropdown(editor, 160, L["状态"], AURA_TRIGGER_ITEMS, "added", function(value)
        Common.CommitAuraSoundEditor(editor, "trigger", value)
    end)
    editor.trigger:SetPoint("TOPLEFT", 196, -142)
    editor.source = EXUI:CreateDropdown(editor, 160, L["声音来源"], AURA_SOUND_SOURCE_ITEMS, "pack", function(value)
        Common.CommitAuraSoundEditor(editor, "sourceType", value == "lsm" and "lsm" or value == "file" and "file" or "pack")
    end)
    editor.source:SetPoint("TOPLEFT", 18, -196)
    editor.valueLabel = ExwindTools.UI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontHighlight")
    editor.valueLabel:SetPoint("TOPLEFT", 18, -250)
    editor.valueLabel:SetText(L["语音包标签"])
    editor.error = ExwindTools.UI:CreateVisualFontString(editor, EXFONTFRAME, "GameFontNormalSmall")
    editor.error:SetPoint("BOTTOM", editor, "BOTTOM", 0, 54)
    editor.error:SetTextColor(1.00, 0.35, 0.35)
    editor.pack = EXUI:CreateDropdown(editor, 300, "", {}, "", function(value)
        Common.CommitAuraSoundEditor(editor, "label", tostring(value or ""))
    end, { searchable = true, previewPath = ResolvePackPreviewPath })
    editor.pack:SetPoint("TOPLEFT", 18, -272)
    editor.lsm = EXUI:CreateLSMSoundDropdown(editor, 300, "", "", function(value)
        Common.CommitAuraSoundEditor(editor, "customLSM", tostring(value or ""))
    end, true)
    editor.lsm:SetPoint("TOPLEFT", 18, -272)
    editor.path = EXUI:CreateEditBox(editor, "", 300, 28, "", {
        onEditFocusLost = function(value) Common.CommitAuraSoundEditor(editor, "customPath", tostring(value or "")) end,
        onEnter = function(value) Common.CommitAuraSoundEditor(editor, "customPath", tostring(value or "")) end,
    })
    editor.path:SetPoint("TOPLEFT", 18, -272)
    editor.preview = EXUI:CreateButton(editor, 100, 30, L["试听"], function() Common.PreviewAuraSound(editor) end)
    editor.preview:SetPoint("BOTTOMRIGHT", -18, 18)
    editor.cancel = EXUI:CreateButton(editor, 100, 30, L["取消"], function() Common.CloseAuraSoundEditor(editor) end)
    editor.cancel:SetPoint("BOTTOMLEFT", 18, 18)
    editor.save = EXUI:CreateButton(editor, 100, 30, L["保存"], function() Common.SaveAuraSoundEditor(editor) end)
    editor.save:SetPoint("LEFT", editor.cancel, "RIGHT", 10, 0)
    PositionVoiceEditor(editor, parent)
    UI.auraSoundEditor = editor
    return editor
end

function Common:ShowAuraSoundEditor(itemID, isNewAuraSoundAction, draftRow)
    -- 新增使用单条草稿，取消前不写入配置。
    local row = draftRow
    if type(row) ~= "table" then
        row = GetAuraSoundActionView(UI.dungeonKey, UI.slotKey, itemID)
    end
    if type(row) ~= "table" then return end
    local editor = Common.EnsureAuraSoundEditor(UI.root or UI.host)
    if not editor then return end
    local stableID = tostring(itemID or "")
    -- 控件始终操作草稿；既有 action 保存时仅提交用户实际触碰的字段。
    editor.itemID, editor.row = tostring(itemID), CopyAuraSoundItem(row)
    editor.isNewAuraSoundAction = isNewAuraSoundAction == true
    editor.isCatalogAction = stableID:match("^catalog:") ~= nil
    editor.touched = {}
    Common.RefreshAuraSoundEditorFields(editor)
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

function Common.RefreshAuraSoundToolbarSummary(visibleCount, totalCount)
    local toolbar = UI.auraSoundToolbar
    visibleCount = math.max(0, tonumber(visibleCount) or 0)
    totalCount = math.max(visibleCount, tonumber(totalCount) or visibleCount)
    if toolbar and toolbar.count then
        toolbar.count:SetText(string.format(L["显示 %d / %d 个 action"], visibleCount, totalCount))
    end
    local panel = UI.auraSoundCategoryFilterControl
    if panel and panel.result then
        panel.result:SetText(string.format(L["显示 %d / %d 个 action"], visibleCount, totalCount))
    end
end

-- 保留搜索控件原有 GUI owner；数量行隐藏，搜索由独立 V2 control 展示。
function Common.EnsureAuraSoundToolbarRenderer()
    if Common._auraSoundToolbarRendererRegistered then return end
    local Grid, EXUI = _G.ExwindGrid, ExwindTools.UI
    Grid:RegisterCustomRenderer("exboss_dungeon_aura_sound_toolbar", {
        mount = function(host)
            if not host._auraSoundToolbar then
                local toolbar = CreateFrame("Frame", nil, host)
                toolbar:SetAllPoints(host)
                toolbar.count = EXUI:CreateVisualFontString(toolbar, EXFONTFRAME, "GameFontNormalSmall")
                toolbar.count:SetJustifyH("LEFT")
                SetAuraThemeText(toolbar.count, GC.textDim)
                toolbar.search = EXUI:CreateSearchBox(toolbar, "", 140, 30, {
                    onChanged = function(text)
                        UI.auraSoundSearchText = tostring(text or "")
                        Common:RefreshAuraSoundFilteredList()
                    end,
                })
                host._auraSoundToolbar = toolbar
            end
            UI.auraSoundToolbar = host._auraSoundToolbar
            local desired = tostring(UI.auraSoundSearchText or "")
            if UI.auraSoundToolbar.search:GetText() ~= desired then UI.auraSoundToolbar.search:SetText(desired) end
            UI.auraSoundToolbar:Show()
        end,
        update = function(host)
            UI.auraSoundToolbar = host._auraSoundToolbar
            local desired = tostring(UI.auraSoundSearchText or "")
            if UI.auraSoundToolbar.search:GetText() ~= desired then UI.auraSoundToolbar.search:SetText(desired) end
        end,
        release = function(host)
            if UI.auraSoundToolbar == host._auraSoundToolbar then UI.auraSoundToolbar = nil end
            host._auraSoundToolbar:Hide()
        end,
    })
    Common._auraSoundToolbarRendererRegistered = true
end
-- The declaration owns card order and spacing. Original renderer owners retain
-- their controls and callbacks; these components never receive a config table.
function Common:BuildPageLayout()
    local function CategoryRow(id)
        return { id = id .. "-row", kind = "row", children = {
            { id = id, kind = "component", ref = id, weight = 1 },
            { id = id .. "-actions", kind = "actions", position = "end", align = "end", children = {
                { id = id .. "-sound", kind = "control", controlType = "select", ref = id .. "Sound", width = 240 },
                { id = id .. "-preview", kind = "button", text = L["试听"], action = id .. "Preview", width = 60 },
            } },
        } }
    end
    return { version = 2, cards = {
        { id = "categories", kind = "card", title = "", children = {
            CategoryRow("floor"),
            { id = "floor-divider", kind = "component", ref = "divider" },
            CategoryRow("error"),
            { id = "error-divider", kind = "component", ref = "divider" },
            CategoryRow("tank"),
        } },
        { id = "rules", kind = "card", title = "", children = {
            -- Keep the original search owner alive without a visible summary row.
            { id = "toolbar", kind = "component", ref = "toolbar", visible = "showToolbarSummary" },
            { id = "filter-row", kind = "row", children = {
                { id = "filter", kind = "component", ref = "filter", weight = 1 },
                { id = "search", kind = "control", controlType = "input", ref = "search", width = 140 },
            } },
            { id = "header", kind = "component", ref = "header" },
            { id = "list", kind = "component", ref = "list", height = AURA_SOUND_LIST_HEIGHT },
        } },
    } }
end

-- A retained GUI host keeps the original controls out of V2's node pool.
-- Release detaches that host before the V2 node can be reused by another page.
local function LayoutAuraComponent(host, kind, width)
    host:SetWidth(width)
    if kind == "category" then
        local card = host._auraSoundCategoryCard
        card.title:ClearAllPoints()
        card.title:SetPoint("TOPLEFT", 4, -1)
        card.title:SetWidth(math.max(1, width - 8))
        card.title:SetJustifyH("LEFT")
        card.hint:ClearAllPoints()
        card.hint:SetPoint("TOPLEFT", 4, -20)
        card.hint:SetWidth(math.max(1, width - 8))
        local textHeight = 20 + math.max(11, card.hint:GetStringHeight()) + 2
        return math.max(34, textHeight)
    elseif kind == "filter" then
        local choice = host._auraSoundCategoryFilter.choice
        choice:SetWidth(width)
        return math.max(30, choice:GetHeight())
    elseif kind == "toolbar" then
        local label = host._auraSoundToolbar.count
        label:ClearAllPoints()
        label:SetPoint("LEFT", 4, 0)
        label:SetWidth(math.max(1, width - 8))
        return math.max(28, label:GetStringHeight())
    elseif kind == "header" then
        LayoutAuraSoundColumns(host, host._auraSoundHeader)
        return 28
    end
    return AURA_SOUND_LIST_HEIGHT
end

local function CloseAuraComponentTransientUI(host)
    local card = host._auraSoundCategoryCard
    if card and card.lsm.CloseMenu then card.lsm:CloseMenu() end
    local toolbar = host._auraSoundToolbar
    if toolbar then
        local edit = toolbar.search.editBox or toolbar.search
        if edit.ClearFocus then edit:ClearFocus() end
    end
    if GameTooltip then GameTooltip:Hide() end
end

-- Guard original interaction callbacks for this V2 lease. Values, field paths
-- and commit functions are not replaced; hidden/released UI cannot act later.
function Common.GuardAuraComponent(host, kind, context)
    local function Script(frame, event)
        if not frame then return end
        frame._auraOriginalScripts = frame._auraOriginalScripts or {}
        local original = frame._auraOriginalScripts[event] or frame:GetScript(event)
        if not original then return end
        frame._auraOriginalScripts[event] = original
        frame:SetScript(event, context:Guard(original))
    end
    if kind == "category" then
        local card = host._auraSoundCategoryCard
        Script(card, "OnMouseUp")
    elseif kind == "filter" then
        local choice = host._auraSoundCategoryFilter.choice
        choice._auraOriginalChange = choice._auraOriginalChange or choice.onChange
        choice.onChange = context:Guard(choice._auraOriginalChange)
    elseif kind == "header" then
        Script(host._auraSoundHeader.check.checkbox, "OnClick")
        Script(host._auraSoundHeader.add, "OnClick")
    elseif kind == "list" then
        for _, row in ipairs(UI.auraSoundVirtualList.rows) do
            Script(row.check.checkbox, "OnClick")
            Script(row.edit, "OnClick")
            Script(row.preview, "OnClick")
        end
    end
end

function Common:CreatePageOwner(dungeonKey, slotKey, pageHost)
    local Grid = _G.ExwindGrid
    local owner = { components = {}, controls = {}, actions = {} }
    owner.predicates = { showToolbarSummary = function() return false end }
    owner.components.divider = {
        mount = function(parent)
            local divider = ExwindTools.UI:CreateSettingsSeparator(parent, 1)
            return divider
        end,
        update = function() end,
        measure = function(divider) return divider:GetHeight() end,
        layout = function(divider, context, width, height)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT")
            divider:SetSize(width, height)
        end,
        setEnabled = function() end,
        setVisible = function(divider, context, visible) divider:SetShown(visible) end,
        release = function(divider) divider:Hide(); divider:ClearAllPoints(); divider:SetParent(nil) end,
    }
    UI.componentHosts = UI.componentHosts or {}
    local function Component(ref, rendererKey, kind, categoryKey)
        local renderer = Grid:GetCustomRenderer(rendererKey)
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
                -- Search has its own visible V2 node and focus lifecycle.
                if not visible and kind ~= "toolbar" then CloseAuraComponentTransientUI(host) end
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
    Component("floor", "exboss_dungeon_aura_sound_category_card", "category", "地板")
    Component("error", "exboss_dungeon_aura_sound_category_card", "category", "错误")
    Component("tank", "exboss_dungeon_aura_sound_category_card", "category", "坦克")
    for _, ref in ipairs({ "floor", "error", "tank" }) do
        local categoryRef = ref
        -- Only the frame parent/geometry changes. The dropdown still closes over
        -- the same card and uses CommitAuraSoundCategoryCardLSM unchanged.
        owner.controls[categoryRef .. "Sound"] = {
            mount = function(parent, context)
                local card = UI.componentHosts[categoryRef]._auraSoundCategoryCard
                local dropdown = card.lsm
                dropdown._auraOriginalSelect = dropdown._auraOriginalSelect or dropdown._onSelect
                dropdown:SetParent(parent)
                dropdown._onSelect = context:Guard(dropdown._auraOriginalSelect)
                dropdown:Show()
                return dropdown
            end,
            release = function(dropdown)
                if dropdown.CloseMenu then dropdown:CloseMenu() end
                dropdown._onSelect = dropdown._auraOriginalSelect
                dropdown:Hide()
                dropdown:ClearAllPoints()
                dropdown:SetParent(UI.componentHosts[categoryRef]._auraSoundCategoryCard)
            end,
        }
        owner.actions[categoryRef .. "Preview"] = function()
            Common.PreviewAuraSoundCategoryCardLSM(UI.componentHosts[categoryRef]._auraSoundCategoryCard)
        end
    end
    Component("filter", "exboss_dungeon_aura_sound_category_filter_cards", "filter")
    Component("toolbar", "exboss_dungeon_aura_sound_toolbar", "toolbar")
    owner.controls.search = {
        mount = function(parent, context)
            local search = UI.componentHosts.toolbar._auraSoundToolbar.search
            local edit = search.editBox or search
            edit._auraOriginalTextChanged = edit._auraOriginalTextChanged or edit:GetScript("OnTextChanged")
            search:SetParent(parent)
            edit:SetScript("OnTextChanged", context:Guard(edit._auraOriginalTextChanged))
            search:Show()
            return search
        end,
        release = function(search)
            local edit = search.editBox or search
            if edit.ClearFocus then edit:ClearFocus() end
            edit:SetScript("OnTextChanged", edit._auraOriginalTextChanged)
            search:Hide()
            search:ClearAllPoints()
            search:SetParent(UI.componentHosts.toolbar._auraSoundToolbar)
        end,
    }
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

-- [混合函数边界] Render 内只可接入共享卡外框与最终高度/reflow；host/dungeon/width guard、旧 Boss 控件单次释放、slot 身份和 renderer 注册禁止修改。
function Common:Render(host)
    local dungeonKey = Page:GetCurrentDungeonCommonOptions()
    if not (host and dungeonKey and self:HasContent()) then return false end
    local Grid = _G.ExwindGrid
    if not Grid then return false end

    UI.host = host
    Common.EnsureFrames(host)
    local hostWidth = math.floor((host:GetWidth() or 0) + 0.5)
    -- SPELL_TEXT_UPDATE 等全局事件可能在一帧内多次触发右侧刷新。通用页
    -- 的结构并不依赖它们；保存/搜索均走 RefreshAuraSoundRows，因此同一
    -- 宿主、同一副本、同一宽度时绝不能再次拆卸整套 Grid。
    if UI._renderedHost == host
        and UI._renderedDungeonKey == tostring(dungeonKey)
        and UI._renderedWidth == hostWidth
        and UI.root:IsShown() then
        return true
    end
    -- 通用设置使用独立的 gridHost 覆盖在 Boss 设置 Grid 之上。进入前必须
    -- 归还宿主原有的 Boss 控件；仅靠新 Frame 的背景遮挡会在 frame level
    -- 或异步刷新时留下旧控件。
    if Grid.ReleaseContainerWidgets and UI._hostWidgetsReleased ~= true then
        Grid:ReleaseContainerWidgets(host)
        UI._hostWidgetsReleased = true
    end
    -- 页面只需要当前 runtime slot；实际数据由 VirtualList 的 ID View 按需读取。
    local cfg = ExBoss and ExBoss.BossConfig
    local slotKey = cfg and type(cfg.GetRuntimeSlotForScene) == "function" and cfg:GetRuntimeSlotForScene("mplus") or nil
    if not slotKey then return false end
    Common.EnsureAuraSoundVirtualListRenderer()
    Common.EnsureAuraSoundHeaderRenderer()
    Common.EnsureAuraSoundToolbarRenderer()
    Common.EnsureAuraSoundCategoryCardRenderer()
    Common.EnsureAuraSoundCategoryFilterRenderer()
    if UI.cardSession then UI.cardSession:Release(); UI.cardSession = nil end
    UI.slotKey = slotKey
    UI.dungeonKey = dungeonKey
    if not Common._v2PageRegistered then
        LAYOUT = Common:BuildPageLayout()
        ExwindTools.UI:RegisterSettingsPageV2(Common.MODULE_KEY, LAYOUT)
        Common._v2PageRegistered = true
    end
    UI.cardSession = ExwindTools.UI:MountSettingsPageV2(UI.gridHost, Common.MODULE_KEY,
        Common:CreatePageOwner(dungeonKey, slotKey, host))
    UI._renderedHost = host
    UI._renderedDungeonKey = tostring(dungeonKey)
    UI._renderedWidth = hostWidth
    return true
end

-- [释放边界] 先关编辑覆盖层，再释放独立 Grid/虚拟上下文与 ActivePage 注册；卡片容器不得重复释放或保留上一副本身份。
function Common:Hide()
    self._virtualListRestore = nil
    UI._renderedHost = nil
    UI._renderedDungeonKey = nil
    UI._renderedWidth = nil
    -- 下次从普通 Boss 设置切回本页时，宿主上的旧 Grid 控件需要恰好归还一次。
    UI._hostWidgetsReleased = nil
    if UI.auraSoundEditor then Common.CloseAuraSoundEditor(UI.auraSoundEditor) end
    if UI.auraSoundCategoryDrawer then Common.CloseAuraSoundCategoryDrawer(UI.auraSoundCategoryDrawer) end
    if UI.encounterVoiceEditor then UI.encounterVoiceEditor:Hide() end
    -- 与 Boss 页面共用右侧区域，但不共用 Grid 容器。离开通用页时同时释放
    -- 本页的独立 Grid，避免 BUFF 行控件停留在随后渲染的 Boss 页面上。
    if UI.cardSession and type(UI.cardSession.Release) == "function" then
        UI.cardSession:Release()
        UI.cardSession = nil
    end
    -- 离开页面后不保留上一副本的行绑定；下次 Mount 重新建立轻量上下文。
    UI.auraSoundVirtualContext = nil
    UI.auraSoundCategoryCardHosts = nil
    UI.auraSoundCategoryFilterControl = nil
    UI.auraSoundToolbar = nil
    UI.auraSoundCategoryOtherKeys = nil
    UI.host = nil
    UI.slotKey = nil
    UI.dungeonKey = nil
    -- Clear only a registration owned by this host; never clear another page.
    if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == UI.gridHost then
        ExwindTools.UI.ActivePageFrame = nil
        ExwindTools.UI.CurrentModule = nil
    end
    if UI.root then UI.root:Hide() end
end
