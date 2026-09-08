---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- [[ EXBoss Tools: InterruptTracker ]]
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI                     = ExwindTools.UI
if not EXUI then return end
local ExBoss                   = _G.ExBoss
if not ExBoss then return end
local L                        = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY        = "ExBoss.Tools.InterruptTracker"
local GROW_DIRECTION_DOWN      = "DOWN"
local GROW_DIRECTION_UP        = "UP"
local EXDB                     = _G.EXDB
local C_Spell                  = _G.C_Spell
local C_DurationUtil           = _G.C_DurationUtil

-- 常用全局函数引用
local UnitName                 = _G.UnitName
local UnitClass                = _G.UnitClass
local C_Timer                  = _G.C_Timer
local GetSpecialization        = _G.GetSpecialization
local GetSpecializationInfo    = _G.GetSpecializationInfo
local C_ClassColor             = _G.C_ClassColor
local CreateColor              = _G.CreateColor
local anchorFrame              = nil
local anchorController         = nil
local EX_DB                    = nil
local GUIPage                  = nil
local runtimeCollection        = nil
local worldCollection          = nil
local playerSelfRecord         = nil
local worldEditing             = false
local STANDARD_CONFIG_BINDING  = nil
local STANDARD_PREVIEW_SURFACE = nil
local STANDARD_PAGE            = nil
local RefreshStandardPreviewSurface = nil

ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.InterruptTracker = ExBoss.UI.InterruptTracker or {}
local Module = ExBoss.UI.InterruptTracker

local playerSelfBarOnCD        = false -- 是否处于CD中
local playerSelfBarDuration    = 0     -- CD总时长
local playerSelfBarExpirationTime = nil -- 由 State 的 start + duration 一次推导，绝不以 GetTime 重置
local playerSelfBarDurationObject = nil
local RefreshPlayerSelfBar, ReleasePlayerSelfBar
local SyncPlayerSelfCooldownFromState
local UpdateLayout, ReLayout, RefreshAll, CreateAnchor, EnsureAnchorController, GetSemanticLayout
local function IsGrowUp()
    return EX_DB and EX_DB.layout and EX_DB.layout.direction == GROW_DIRECTION_UP
end

local function GetStandaloneAnchorPoint()
    return IsGrowUp() and "BOTTOM" or "TOP"
end

local function ApplyStandaloneAnchorPosition()
    if anchorFrame and anchorController then anchorController:ApplyPosition() end
end

-- 使用 EXDB.InterruptData
local SPEC_INTERRUPT_DB = EXDB.InterruptData


-- =============================================================
-- Grid 布局
-- =============================================================




local EX_DEFAULTS = {
    attachToCustom = false,
    customAttachTarget = "",
    enabled = false,
    layout = { direction = GROW_DIRECTION_DOWN, spacing = 1, maxVisible = 5 },
    -- 标准条体的新文字组：不复用旧手工 StatusBar 的偏移与对齐字段。
    font_spell = {
        enabled = true,
        autoWidth = false,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        x = 5,
        y = 0,
        size = 16,
        font = "默认",
        outline = "OUTLINE",
        r = 1,
        g = 1,
        b = 1,
        a = 1,
    },
    font_timer = {
        enabled = true,
        autoWidth = false,
        justifyH = "RIGHT",
        justifyV = "MIDDLE",
        x = -5,
        y = 0,
        size = 16,
        font = "默认",
        outline = "OUTLINE",
        r = 1,
        g = 0.9,
        b = 0.2,
        a = 1,
    },
    -- 打断监控没有 B 文字语义；保留 StandardTimerBar 的可选槽位但默认禁用。
    font_target = { enabled = false },
    -- 团队标记是主 TimerBar 的声明式 texture 子 Region。它的配置只能在
    -- elements.raidMarker.texture；运行时仍不恢复任何 Unit/raid-target 查询链。
    elements = {
        raidMarker = {
            texture = { enabled = true, x = -2, y = 0, width = 24, height = 24 },
        },
    },
    locked = true,
    pos = {
        "CENTER",
        "UIParent",
        "CENTER",
        0,
        -200,
    },
    posX = 495,
    posY = 138,
    spacing = 1,
    timerGroup = {
        barBgColorA = 0.90653932094574,
        barBgColorB = 0.30196079611778,
        barBgColorG = 0.30196079611778,
        barBgColorR = 0.30196079611778,
        barColorA = 1,
        barColorB = 0.2,
        barColorG = 0.8,
        barColorR = 0.2,
        borderColorA = 1,
        borderColorB = 0.10196079313755,
        borderColorG = 0.10196079313755,
        borderColorR = 0.10196079313755,
        borderPadding = 1,
        borderSize = 1,
        borderTexture = "EX_WhiteBorder",
        height = 25,
        iconOffsetX = -2,
        iconOffsetY = 0,
        iconSide = "LEFT",
        iconWidth = 25,
        iconHeight = 25,
        showBorder = true,
        showIcon = true,
        texture = "EX_WhiteTexture",
        width = 184,
        fillDirection = "LEFT_TO_RIGHT",
        progressMode = "REMAINING",
    },
    useClassColorName = false,
}

-- ModuleDB 的声明结构只服务 Core 的默认值/导出白名单；实际运行字段仍保持原有
-- 根路径，避免迁移时引入第二套配置或字段映射。
local FONT_FIELDS = {
    "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
    "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB",
    "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart",
    "gradientLength", "drawLayer", "drawSubLevel", "x", "y",
}
local TIMER_FIELDS = {
    "width", "height", "texture", "barColorR", "barColorG", "barColorB", "barColorA",
    "barBgColorR", "barBgColorG", "barBgColorB", "barBgColorA", "showBorder", "borderTexture",
    "borderColorR", "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding",
    "showIcon", "iconSide", "iconWidth", "iconHeight", "iconOffsetX", "iconOffsetY",
    "showIconBorder", "iconBorderTexture", "iconBorderColorR", "iconBorderColorG", "iconBorderColorB",
    "iconBorderColorA", "iconBorderSize", "iconBorderPadding", "fillDirection", "progressMode",
}
local DEFAULT_DECLARATION = {
    module = {
        attachToCustom = EX_DEFAULTS.attachToCustom,
        customAttachTarget = EX_DEFAULTS.customAttachTarget,
        enabled = EX_DEFAULTS.enabled,
        locked = EX_DEFAULTS.locked,
        pos = EX_DEFAULTS.pos,
        posX = EX_DEFAULTS.posX,
        posY = EX_DEFAULTS.posY,
        spacing = EX_DEFAULTS.spacing,
        useClassColorName = EX_DEFAULTS.useClassColorName,
    },
    layout = EX_DEFAULTS.layout,
    font_spell = EX_DEFAULTS.font_spell,
    font_timer = EX_DEFAULTS.font_timer,
    font_target = EX_DEFAULTS.font_target,
    timerGroup = EX_DEFAULTS.timerGroup,
    elements = EX_DEFAULTS.elements,
}
local DEFAULT_SCHEMA = {
    { group = "module", root = true, fields = {
        "attachToCustom", "customAttachTarget", "enabled", "locked", "pos", "posX", "posY", "spacing", "useClassColorName",
    } },
    { group = "layout", fields = { "direction", "spacing", "maxVisible" } },
    { group = "font_spell", fields = FONT_FIELDS },
    { group = "font_timer", fields = FONT_FIELDS },
    { group = "font_target", fields = FONT_FIELDS },
    { group = "timerGroup", fields = TIMER_FIELDS },
    { group = "elements", fields = { raidMarker = { texture = { "enabled", "x", "y", "width", "height" } } } },
}
local DEFAULTS = ExwindTools:DeclareModuleDefaults(EXWIND_MODULE_KEY, DEFAULT_DECLARATION, DEFAULT_SCHEMA)

local function GetDB()
    return ExwindTools:GetModuleDB(EXWIND_MODULE_KEY)
end

EX_DB = GetDB()

-- 标准显示合同只登记同一份 ModuleDB 的真实路径；尤其保留 FontGroup 的
-- autoWidth/fixedWidth 对，后者在标准 Slider commit 时会显式写 autoWidth=false。
local STANDARD_SCHEMA_PATHS = {}
local function DeclareSchemaPath(path)
    STANDARD_SCHEMA_PATHS[path] = true
end
for _, path in ipairs({
    "attachToCustom", "customAttachTarget", "enabled",
    "locked", "posX", "posY", "spacing", "useClassColorName",
}) do
    DeclareSchemaPath(path)
end
for _, field in ipairs({ "enabled", "x", "y", "width", "height" }) do
    DeclareSchemaPath("elements.raidMarker.texture." .. field)
end
for _, field in ipairs({ "direction", "spacing", "maxVisible" }) do
    DeclareSchemaPath("layout." .. field)
end
for _, groupName in ipairs({ "font_spell", "font_timer", "font_target" }) do
    for _, field in ipairs(FONT_FIELDS) do
        DeclareSchemaPath(groupName .. "." .. field)
    end
end
for _, field in ipairs(TIMER_FIELDS) do
    if type(field) == "string" then
        DeclareSchemaPath("timerGroup." .. field)
    elseif type(field) == "table" then
        for parent, children in pairs(field) do
            for _, child in ipairs(children) do
                DeclareSchemaPath("timerGroup." .. parent .. "." .. child)
            end
        end
    end
end

local COMMON_FIELDS = {
    { path = "enabled", type = "checkbox", label = L["启用"] },
    { path = "useClassColorName", type = "checkbox", label = L["名称使用职业颜色"] },
}

local COMMON_POOL_TYPE = "InterruptTrackerModuleCommonSettingsGroup"
local COMMON_OPTS = { bindRoot = true, poolType = COMMON_POOL_TYPE, columns = 3, fields = COMMON_FIELDS }
local RAID_MARKER_EXTRA_OPTS = ExwindTools:BuildStandardTimerBarAlertIconsGroupOptions({
    timerBarKey = "timerGroup",
}, {
    paths = {
        show = "elements.raidMarker.texture.enabled",
        width = "elements.raidMarker.texture.width",
        height = "elements.raidMarker.texture.height",
        x = "elements.raidMarker.texture.x",
        y = "elements.raidMarker.texture.y",
    },
    ranges = {
        width = { min = 8, max = 128, step = 1 }, height = { min = 8, max = 128, step = 1 },
        x = { min = -1000, max = 1000, step = 1 }, y = { min = -1000, max = 1000, step = 1 },
    },
})
-- AnchorController 与 AnchorGroup 必须由同一份正式声明生成；页面不再手写
-- 第二套 key/default/picker 映射，也不保留人工 SavePosition fallback。
anchorController, ANCHOR_OPTS = EXUI:CreateStandardModuleAnchor({
    moduleKey = EXWIND_MODULE_KEY,
    frameName = "ExBossInterruptTrackerAnchor",
    title = L["队友打断监控"],
    getDB = GetDB,
    offsetXKey = "posX",
    offsetYKey = "posY",
    defaultOffsetX = EX_DEFAULTS.posX,
    defaultOffsetY = EX_DEFAULTS.posY,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    restoreKeys = { "locked" },
    syncWidgets = { "posX", "posY", "attachToCustom", "customAttachTarget" },
    widgetRanges = {
        posX = { min = -1000, max = 1000, step = 1 },
        posY = { min = -1000, max = 1000, step = 1 },
    },
    initialWidth = 200,
    initialHeight = 20,
    clampedToScreen = true,
    getAnchorPoint = GetStandaloneAnchorPoint,
    relativePoint = "CENTER",
    onCreateFrame = function(_, frame) frame:Hide() end,
})
local LAYOUT_OPTS = {
    allowedDirections = { GROW_DIRECTION_DOWN, GROW_DIRECTION_UP },
    includeMaxPerRow = false,
    maxVisibleMin = 1,
    maxVisibleMax = 10,
    defaultMaxVisible = EX_DEFAULTS.layout.maxVisible,
}
local GridExporter = ExwindTools.Grid
if GridExporter and GridExporter.RegisterExportReference then
    GridExporter:RegisterExportReference(COMMON_OPTS, "COMMON_OPTS")
    GridExporter:RegisterExportReference(RAID_MARKER_EXTRA_OPTS, "RAID_MARKER_EXTRA_OPTS")
    GridExporter:RegisterExportReference(ANCHOR_OPTS, "ANCHOR_OPTS")
    GridExporter:RegisterExportReference(LAYOUT_OPTS, "LAYOUT_OPTS")
end

local EX_LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["打断监控"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 50, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "raidMarkerExtra", type = "modulecommonsettings", x = 1, y = 62, w = 200, h = 50, label = L["额外子元素－团队标记"], opts = RAID_MARKER_EXTRA_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 114, w = 200, h = 20, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "layout", type = "widgetlayout", x = 1, y = 136, w = 200, h = 20, label = L["排列设置"], opts = LAYOUT_OPTS },
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 158, w = 200, h = 52, label = L["计时条外观"] },
    { key = "font_spell", type = "fontgroup", x = 1, y = 212, w = 200, h = 50, label = L["玩家名字"] },
    { key = "font_timer", type = "fontgroup", x = 1, y = 264, w = 200, h = 50, label = L["冷却时间"] },
}
ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)

-- 打断条只声明标准 TimerBar 的 A（玩家名）与 C（冷却时间）语义；B 为明确禁用的
-- 可选槽位。条体、图标、文字、时间和释放均由 EXUI 管理。
local INTERRUPT_TIMER_BAR_SCHEMA = {
    timerBarKey = "timerGroup",
    layoutKey = "layout",
    offsetXKey = "posX",
    offsetYKey = "posY",
    showTextBKey = false,
    showTextCKey = false,
    textA = { key = "font_spell", role = "playerName", gridKey = "font_spell" },
    textB = { key = "font_target", role = "unused", gridKey = "font_target", optional = true },
    textC = { key = "font_timer", role = "time", gridKey = "font_timer" },
}

-- =============================================================
-- 自动检测已加载的小队框体插件（仅在用户未手动设置时生效）
-- =============================================================
--- 延迟自动检测：在模块首次需要时调用（插件框架可能还未创建）
-- =============================================================
-- UI 框架系统
-- =============================================================
local INTERRUPT_RECORD_ICON = 132357
local isValidEnvironment = nil

EnsureAnchorController = function()
    return anchorController
end

local function ClearRuntimeBars()
    if runtimeCollection then
        runtimeCollection:SetItems({}, GetSemanticLayout())
    end
end

-- 与 MythicCast 一样，Panel / World 固定物化所有合法预览条。maxVisible 只
-- 决定语义布局的可见范围，Slider 因而只需原位重套，绝不能改样本拓扑。
local INTERRUPT_PREVIEW_BAR_COUNT = 10

GetSemanticLayout = function()
    local layout = GetDB().layout or {}
    return {
        direction = tostring(layout.direction or GROW_DIRECTION_DOWN):upper() == GROW_DIRECTION_UP
            and GROW_DIRECTION_UP or GROW_DIRECTION_DOWN,
        spacing = tonumber(layout.spacing) or 0,
        maxVisible = math.max(1, math.min(INTERRUPT_PREVIEW_BAR_COUNT,
            math.floor(tonumber(layout.maxVisible) or EX_DEFAULTS.layout.maxVisible))),
    }
end

local PREVIEW_SPELLS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }

-- 只供 panel/world 静态样本使用：固定多职业序列必须让可见条目呈现不同职业色。
-- 名称/职业绝不读取真实玩家；runtime record 不调用此函数，也不消费 preview 标记。
local PREVIEW_CLASS_SEQUENCE = { 1, 8, 4, 11, 13 }
local function GetPreviewPlayer(index)
    local classID = PREVIEW_CLASS_SEQUENCE[((index - 1) % #PREVIEW_CLASS_SEQUENCE) + 1]
    local class = EXDB and EXDB.Classes and EXDB.Classes[classID]
    return (class and class.name) or "玩家", classID
end

local RAID_MARKER_ELEMENT_ID = "elements.raidMarker"

-- 模块只声明 panel 元素语义、正式 GUI key 与同一 ModuleDB 内的位置路径。
-- hitbox、右键 Focus、DB 回写和 Grid 回读全部由 BindStandardPreviewInteractions
-- 处理；运行时/world collection 仅消费这些同名 semantic slots。
local INTERRUPT_INTERACTION_SCHEMA = {
    ["core.spellName"] = {
        guiKey = "font_spell",
        movable = true,
        textRole = "A",
        tooltip = L["玩家名字"],
        position = { x = "font_spell.x", y = "font_spell.y" },
        anchor = { point = "LEFT", relativeElement = "core.bar", relativePoint = "LEFT" },
    },
    ["core.time"] = {
        guiKey = "font_timer",
        movable = true,
        textRole = "C",
        tooltip = L["冷却时间"],
        position = { x = "font_timer.x", y = "font_timer.y" },
        anchor = { point = "RIGHT", relativeElement = "core.bar", relativePoint = "RIGHT" },
    },
    [RAID_MARKER_ELEMENT_ID] = {
        guiKey = "raidMarkerExtra",
        movable = true,
        tooltip = L["团队标记"],
        position = { x = "elements.raidMarker.texture.x", y = "elements.raidMarker.texture.y" },
    },
}

local function BuildInterruptInteraction()
    return EXUI:BuildStandardPreviewInteraction("StandardTimerBar", GetDB, INTERRUPT_INTERACTION_SCHEMA)
end

local function BuildInterruptPresentation(record, mode)
    local db, group = GetDB(), GetDB().timerGroup
    local content = { icon = record.icon, textA = record.name, textAMode = record.nameMode, textC = record.timeText }
    if record.durationObject then
        -- 非白名单模块的普通倒数只允许把同一份原生 Duration Object 直接交给
        -- StandardTimerBar；不得回退 start/duration -> Lua OnUpdate 路径。
        content.durationObject = record.durationObject
    else
        content.progress, content.maximum = record.progress or 1, record.maximum or 1
    end
    -- 打断条的职业色属于这条记录的显示语义，而不是运行时额外补丁。
    -- 运行、世界编辑与面板样本都走同一个 presentation，因此样本也必须在
    -- 这里使用其固定 classID 生成同一条体填充色。
    local colors = {}
    local fillColor = CreateColor(
        group.barColorR or 1,
        group.barColorG or 0.7,
        group.barColorB or 0,
        group.barColorA or 1
    )
    if db.useClassColorName then
        if record.classFilename then
            colors.A = C_ClassColor.GetClassColor(record.classFilename)
        elseif record.classID then
            local r, g, b = EXDB:GetClassColorRGB(record.classID)
            colors.A = CreateColor(r, g, b, 1)
        end
    end
    if record.classFilename then
        fillColor = C_ClassColor.GetClassColor(record.classFilename) or fillColor
    elseif record.classID then
        local r, g, b = EXDB:GetClassColorRGB(record.classID)
        fillColor = CreateColor(r, g, b, 1)
    end
    local regionElements = {}
    local raidMarkerStyle = db.elements and db.elements.raidMarker and db.elements.raidMarker.texture
    if type(raidMarkerStyle) == "table" then
        local markerIndex = tonumber(record.raidMarker)
        local markerShown = record.raidMarker == true or markerIndex ~= nil
        local relative = group.showIcon ~= false and tostring(group.iconSide or "LEFT"):upper() == "LEFT"
            and "core.icon" or "core.bar"
        regionElements[1] = {
            id = "raidMarker",
            kind = "texture",
            stylePath = "elements.raidMarker.texture",
            style = raidMarkerStyle,
            shown = raidMarkerStyle.enabled ~= false,
            anchor = { point = "RIGHT", relativeElement = relative, relativePoint = "LEFT" },
            bounds = { width = raidMarkerStyle.width, height = raidMarkerStyle.height },
            content = {
                texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
                shown = markerShown,
                hasRaidTargetIndex = markerShown,
                raidTargetIndex = markerIndex or 8,
            },
            interaction = { elementID = RAID_MARKER_ELEMENT_ID, guiTarget = "raidMarkerExtra", movable = true },
        }
    end
    return {
        db = db,
        schema = INTERRUPT_TIMER_BAR_SCHEMA,
        content = content,
        textColors = colors,
        fillColor = fillColor,
        regionElements = regionElements,
        interaction = BuildInterruptInteraction(),
    }
end

-- 预览/世界编辑专属投影：不触碰 runtime presentation。C 槽位提供静态样本文字，
-- 让 Panel 与世界编辑能显示冷却时间，同时仍由同一份 interaction declaration 管理。
local function BuildPreviewInterruptPresentation(record, mode)
    return BuildInterruptPresentation(record, mode)
end

local function ApplyInterruptRecord(collection, record)
    record.item = record.item or collection:AcquireItem(record.id)
    collection:ApplyItem(record.item, BuildInterruptPresentation(record, collection.interactionMode))
end

local function BuildInterruptPreviewRecords()
    local records = {}
    for index = 1, INTERRUPT_PREVIEW_BAR_COUNT do
        local spell = C_Spell.GetSpellInfo(PREVIEW_SPELLS[((index - 1) % #PREVIEW_SPELLS) + 1])
        local playerName, classID = GetPreviewPlayer(index)
        records[#records + 1] = {
            id = "interrupt-sample:" .. index,
            name = playerName,
            classID = classID,
            icon = (spell and spell.iconID) or INTERRUPT_RECORD_ICON,
            progress = 1,
            maximum = 1,
            timeText = "8.0",
            -- 固定样本展示不同团队标记，只改善 panel/world 的辨识度；不进入
            -- runtime 业务记录，也不改变任何队伍标记判定。
            raidMarker = ((index - 1) % 8) + 1,
        }
    end
    return records
end

local function BuildInterruptPreviewEntries(mode)
    local entries = {}
    for _, record in ipairs(BuildInterruptPreviewRecords()) do
        entries[#entries + 1] = {
            itemID = record.id,
            presentation = BuildPreviewInterruptPresentation(record, mode),
        }
    end
    return entries, GetSemanticLayout()
end

local function RenderInterruptSamples(collection)
    local items = {}
    local entries, layout = BuildInterruptPreviewEntries(collection.interactionMode)
    for _, entry in ipairs(entries) do
        local record = { id = entry.itemID }
        record.item = collection:AcquireItem(record.id)
        collection:ApplyItem(record.item, entry.presentation)
        items[#items + 1] = record.item
    end
    collection:SetItems(items, layout)
end

local function GetPlayerInterruptData()
    local specIndex = GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    local specID = GetSpecializationInfo(specIndex)
    if not specID or specID <= 0 then return nil end
    local data = SPEC_INTERRUPT_DB[specID]
    if not data or data.id == 0 then return nil end
    return data
end

-- =============================================================
-- 环境检测：只在队伍且5人副本内生效
-- =============================================================
--- 检测当前环境是否有效（队伍 + 5人副本）
local function CheckEnvironment()
    local state = ExwindTools.State
    local inParty = state.IsInParty or false
    local instanceType = state.InstanceType or "none"

    -- 必须在队伍中，且副本类型为 party (5人本)
    local shouldEnable = inParty and instanceType == "party"

    if shouldEnable ~= isValidEnvironment then
        isValidEnvironment = shouldEnable

        if not shouldEnable then
            -- 环境无效，隐藏所有UI
            if anchorFrame then
                anchorFrame:Hide()
                anchorFrame:EnableMouse(false)
            end
            ClearRuntimeBars()
            ReleasePlayerSelfBar()
        else
            -- 环境有效，恢复显示
            if EX_DB.enabled then
                UpdateLayout()
            end
        end
    end

    return shouldEnable
end

-- 创建锚点
CreateAnchor = function()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(200, 20)
    runtimeCollection = ExwindTools.UI:CreateStandardTimerBarCollection(anchorFrame, "runtime", EXWIND_MODULE_KEY, { schema = INTERRUPT_TIMER_BAR_SCHEMA })
    ApplyStandaloneAnchorPosition()
end

-- =============================================================
-- 玩家自身打断计时条管理
-- =============================================================
ReleasePlayerSelfBar = function()
    if runtimeCollection and playerSelfRecord then runtimeCollection:ReleaseItem(playerSelfRecord.id) end
    playerSelfRecord = nil
    playerSelfBarOnCD = false
end

RefreshPlayerSelfBar = function()
    if not anchorFrame then return end
    local interruptData = GetPlayerInterruptData()
    if not interruptData then
        ReleasePlayerSelfBar()
        return
    end

    local _, classFilename = UnitClass("player")
    local spellInfo = C_Spell.GetSpellInfo(interruptData.id)
    if not playerSelfBarOnCD then playerSelfBarDuration = interruptData.cd end
    playerSelfRecord = playerSelfRecord or { id = "interrupt:self" }
    local record = playerSelfRecord
    record.name, record.nameMode, record.classFilename = UnitName("player"), "SECRET", classFilename
    record.icon = spellInfo and spellInfo.iconID or INTERRUPT_RECORD_ICON
    if playerSelfBarOnCD then
        record.durationObject = playerSelfBarDurationObject
    else
        record.durationObject, record.progress, record.maximum = nil, 1, 1
    end
    ApplyInterruptRecord(runtimeCollection, record)
end

-- ExwindState 是玩家打断成功的唯一安全来源：模块只消费已解密的普通冷却状态。
SyncPlayerSelfCooldownFromState = function()
    local state = ExwindTools.State or {}
    local ready = state.InterruptReady
    local startTime = tonumber(state.InterruptStartTime) or 0
    local duration = tonumber(state.InterruptDuration) or 0

    if ready == false and startTime > 0 and duration > 0 then
        if not C_DurationUtil or type(C_DurationUtil.CreateDuration) ~= "function" then
            error("InterruptTracker requires C_DurationUtil.CreateDuration for ordinary cooldown", 2)
        end
        playerSelfBarOnCD = true
        playerSelfBarDuration = duration
        -- ExwindState 只提供开始时刻与总时长；结束时刻在状态变化时精确推导一次。
        -- 后续视觉重刷复用该 Object，绝不以 GetTime() 重置倒数。
        playerSelfBarExpirationTime = startTime + duration
        playerSelfBarDurationObject = C_DurationUtil.CreateDuration()
        playerSelfBarDurationObject:SetTimeFromEnd(playerSelfBarExpirationTime, playerSelfBarDuration, 1)
    else
        playerSelfBarOnCD = false
        playerSelfBarExpirationTime = nil
        playerSelfBarDurationObject = nil
    end

    if not EX_DB.enabled or worldEditing or not isValidEnvironment then return end
    RefreshPlayerSelfBar()
    ReLayout()
end

-- 重新布局所有条
ReLayout = function()
    if not anchorFrame then return end

    if worldEditing then return end

    if not EX_DB.enabled or not isValidEnvironment then
        anchorFrame:Hide()
        anchorFrame:EnableMouse(false)
        if runtimeCollection then
            runtimeCollection:SetItems({}, GetSemanticLayout())
        end
        return
    end

    local items = {}
    if playerSelfRecord then ApplyInterruptRecord(runtimeCollection, playerSelfRecord); items[1] = playerSelfRecord.item end
    runtimeCollection:SetItems(items, GetSemanticLayout())
    anchorFrame:SetSize((EX_DB.timerGroup or {}).width or 200, (EX_DB.timerGroup or {}).height or 25)
    ApplyStandaloneAnchorPosition()
end

-- 刷新所有条
RefreshAll = function()
    if worldEditing then
        if worldCollection then
            RenderInterruptSamples(worldCollection)
        end
        return
    end

    if not EX_DB.enabled or not isValidEnvironment then
        if anchorFrame then
            anchorFrame:Hide()
            anchorFrame:EnableMouse(false)
        end
        return
    end

    ReLayout()

    if anchorFrame then
        ApplyStandaloneAnchorPosition()

        if EX_DB.locked then
            anchorFrame:EnableMouse(false)
        else
            anchorFrame:EnableMouse(true)
        end
    end
end

-- 更新打断条布局 (增量更新,保留冷却状态)
UpdateLayout = function()
    if worldEditing then return end
    -- [v5.0 新增] 环境检测：只在队伍且5人副本内生效
    if not CheckEnvironment() then
        return
    end

    if not EX_DB.enabled then
        if anchorFrame then
            anchorFrame:Hide()
        end
        return
    end

    if not anchorFrame then
        CreateAnchor()
    end

    anchorFrame:Show()

    RefreshPlayerSelfBar()
    ReLayout()
    RefreshAll()
end

-- 受限施法事件的队友打断载荷不可进入 Lua 业务链；此模块不注册也不替代该路径。

-- =============================================================
-- 玩家打断冷却：订阅 ExwindState 输出的普通状态，不直接碰受保护 spellID。
-- =============================================================
ExwindTools:WatchState("InterruptStartTime", EXWIND_MODULE_KEY .. "_PlayerInterruptState", SyncPlayerSelfCooldownFromState)
ExwindTools:WatchState("InterruptDuration", EXWIND_MODULE_KEY .. "_PlayerInterruptState", SyncPlayerSelfCooldownFromState)
ExwindTools:WatchState("InterruptReady", EXWIND_MODULE_KEY .. "_PlayerInterruptState", SyncPlayerSelfCooldownFromState)

-- =============================================================
-- 事件处理
-- =============================================================
ExwindTools:RegisterEvent("EX_PARTY_SPEC_UPDATED", EXWIND_MODULE_KEY, function()
    if not worldEditing then
        UpdateLayout()
    end
end)

ExwindTools:RegisterEvent("GROUP_ROSTER_UPDATE", EXWIND_MODULE_KEY, function()
    if not worldEditing then
        UpdateLayout()
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    C_Timer.After(1, function()
        CreateAnchor()
        SyncPlayerSelfCooldownFromState()
        UpdateLayout()
    end)
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if info.key == "btn_reset_pos" then
        EX_DB.posX = 0
        EX_DB.posY = -200
        EnsureAnchorController():SyncWidgets()
        if anchorFrame then
            ApplyStandaloneAnchorPosition()
        end
        RefreshAll()
    elseif info.key == "btn_pick_frame" then
        EnsureAnchorController():StartFramePicker()
    end
end)

-- 专精切换时重置玩家条（换专精可能打断技能变化）
ExwindTools:WatchState("SpecID", EXWIND_MODULE_KEY .. "_PlayerSpec", function()
    if not worldEditing then
        playerSelfBarOnCD = false
        RefreshPlayerSelfBar()
        UpdateLayout()
    end
end)

-- =============================================================
-- State 监听：环境变化时自动启用/禁用
-- =============================================================
-- 监听队伍状态变化
ExwindTools:WatchState("IsInParty", EXWIND_MODULE_KEY .. "_PartyWatch", function()
    CheckEnvironment()
end)

-- 监听副本类型变化
ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY .. "_InstanceWatch", function()
    CheckEnvironment()
end)

-- 模块可在 PLAYER_ENTERING_WORLD 之后按需加载；不能只依赖该事件，否则锚点与
-- EXUI 条体没有初始化机会。延迟一帧读取当前 State，随后由常规事件继续维护。
local function InitializeInterruptTrackerRuntime()
    CreateAnchor()
    CheckEnvironment()
    SyncPlayerSelfCooldownFromState()
    UpdateLayout()
end

C_Timer.After(0, InitializeInterruptTrackerRuntime)

-- InterruptTracker 只注册身份、纯预览、整体 anchor 与面板布局 intent。
-- 世界编辑生命周期、前景覆盖层、左拖与右键页面路由全部属于唯一 Core。
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "interrupttracker",
    name = L["队友打断监控"],
    settingsPage = "interrupttracker",
    appearanceProfile = "basicTimerBar",
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 28 },
    getAnchor = function()
        CreateAnchor()
        return anchorFrame
    end,
    RenderWorld = function(host)
        CreateAnchor()
        worldEditing = true
        -- World 与 runtime 共用 Anchor，但不能同时保留两批 Item。清空旧
        -- runtime item 后，唯一 renderer 才只显示世界样本；退出时 ReLayout
        -- 会依真实状态重新 materialize runtime item。
        if runtimeCollection then
            runtimeCollection:SetItems({}, GetSemanticLayout())
        end
        -- AnchorController 创建的 host 默认隐藏。世界编辑不依赖模块启用或
        -- 地城环境，必须显式显示同一语义 Anchor，不能另建 preview Frame。
        anchorFrame:Show()
        if worldCollection then worldCollection:Release() end
        worldCollection = ExwindTools.UI:CreateStandardTimerBarCollection(host, "world", EXWIND_MODULE_KEY, { schema = INTERRUPT_TIMER_BAR_SCHEMA })
        RenderInterruptSamples(worldCollection)
    end,
    ReleaseWorld = function()
        if worldCollection then worldCollection:Release(); worldCollection=nil end
        worldEditing=false; ReLayout()
    end,
    GetWorldBounds = function() return worldCollection and worldCollection:GetWorldBounds() end,
})

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

function Module:GetModuleDB()
    return GetDB()
end

function Module:RefreshVisuals()
    RefreshAll()
end

function Module:Clear()
    ClearRuntimeBars()
    ReleasePlayerSelfBar()
end

function Module:Shutdown()
    self:Clear()
    ExwindTools:UnwatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY)
    ExwindTools:UnwatchState("SpecID", EXWIND_MODULE_KEY .. "_PlayerSpec")
    ExwindTools:UnwatchState("InterruptStartTime", EXWIND_MODULE_KEY .. "_PlayerInterruptState")
    ExwindTools:UnwatchState("InterruptDuration", EXWIND_MODULE_KEY .. "_PlayerInterruptState")
    ExwindTools:UnwatchState("InterruptReady", EXWIND_MODULE_KEY .. "_PlayerInterruptState")
    ExwindTools:UnwatchState("IsInParty", EXWIND_MODULE_KEY .. "_PartyWatch")
    ExwindTools:UnwatchState("InstanceType", EXWIND_MODULE_KEY .. "_InstanceWatch")
    ExwindTools:UnregisterEvent("EX_PARTY_SPEC_UPDATED", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("GROUP_ROSTER_UPDATE", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY)
end

function Module:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

-- 重置注册（供 ToolsPage 重置按钮调用）
ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[EXWIND_MODULE_KEY] = function()
    local moduleDB = _G.EXBOSS12S2 and _G.EXBOSS12S2.ModuleDB
    if not moduleDB then return end
    moduleDB[EXWIND_MODULE_KEY] = nil
    EX_DB = GetDB()
    EXUI:NotifyModuleValueChanged(EXWIND_MODULE_KEY, "*", "committed")
end

-- =============================================================
-- 标准显示合同：唯一配置绑定、Panel surface、Slider 生命周期与页面外壳
-- =============================================================
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.Panel = ExBoss.UI.Panel or {}
ExBoss.UI.Panel.InterruptTrackerPage = ExBoss.UI.Panel.InterruptTrackerPage or {}
GUIPage = ExBoss.UI.Panel.InterruptTrackerPage

local function RefreshStandardInterruptVisuals(options)
    Module:RefreshVisuals()
    if (options == nil or options.rebuildPanelPreview == true) and RefreshStandardPreviewSurface then
        RefreshStandardPreviewSurface()
    end
end

for _, path in ipairs({ "posX", "posY", "attachToCustom", "customAttachTarget" }) do STANDARD_SCHEMA_PATHS[path] = true end
STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = EXWIND_MODULE_KEY,
    getConfig = GetDB,
    schemaPaths = STANDARD_SCHEMA_PATHS,
    reapplyExisting = function()
        -- Slider live 阶段必须像 MythicCast 一样，以当前 ModuleDB 重新生成
        -- 每个已物化条目的 presentation；不能只重套旧 table，否则颜色、额外
        -- 图标可见性和新布局声明会停留在旧值。整个过程只 Patch 既有 Item。
        local function replace(target, source)
            if not source then return end
            for key in pairs(target) do target[key] = nil end
            for key, value in pairs(source) do target[key] = value end
        end
        local samples = {}
        for _, record in ipairs(BuildInterruptPreviewRecords()) do samples[record.id] = record end
        local runtime = {}
        if playerSelfRecord then runtime[playerSelfRecord.id] = playerSelfRecord end
        local function reapplyCollection(collection, resolver, layout)
            if collection and type(collection.ReapplyCurrentItems) == "function" then
                collection:ReapplyCurrentItems(function(presentation, item)
                    local nextPresentation = resolver(item and item.id)
                    if nextPresentation then replace(presentation, nextPresentation) end
                end, { reapplyLayout = false })
            end
            if collection and type(collection.ReapplyCurrentLayout) == "function" then
                collection:ReapplyCurrentLayout(layout)
            end
        end
        local function samplePresentation(mode)
            return function(id)
                local record = samples[id]
                return record and BuildPreviewInterruptPresentation(record, mode) or nil
            end
        end
        local function runtimePresentation(id)
            local record = runtime[id]
            return record and BuildInterruptPresentation(record, "runtime") or nil
        end
        local layout = GetSemanticLayout()
        if STANDARD_PREVIEW_SURFACE and type(STANDARD_PREVIEW_SURFACE.ReapplyPanelPresentation) == "function" then
            STANDARD_PREVIEW_SURFACE:ReapplyPanelPresentation()
        end
        reapplyCollection(worldCollection, samplePresentation("world"), layout)
        reapplyCollection(runtimeCollection, runtimePresentation, layout)
    end,
})

local function RefreshActiveSurfaces(_, _, phase)
    return STANDARD_CONFIG_BINDING.reapplyExisting(phase)
end
EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

STANDARD_PREVIEW_SURFACE = EXUI:CreateStandardPreviewSurface({
    moduleKey = EXWIND_MODULE_KEY,
    kind = "timerbar",
    binding = STANDARD_CONFIG_BINDING,
    collectionOptions = { schema = INTERRUPT_TIMER_BAR_SCHEMA, contentCenter = true },
    buildPresentation = function(_, mode)
        if mode ~= "panel" then error("InterruptTracker preview surface only supports panel", 2) end
        local entries, layout = BuildInterruptPreviewEntries(mode)
        return { entries = entries, layout = layout }
    end,
    interactionSchema = INTERRUPT_INTERACTION_SCHEMA,
    requiredPositionGuiKeys = { "font_spell", "font_timer", "raidMarkerExtra" },
})

RefreshStandardPreviewSurface = function()
    if not STANDARD_PAGE or not STANDARD_PAGE.previewDock or not STANDARD_PAGE.previewDock:IsShown() then return end
    local session = STANDARD_PREVIEW_SURFACE:Render({
        dock = STANDARD_PAGE.previewDock,
        ruleKey = EXWIND_MODULE_KEY,
        state = { kind = "interrupt-preview" },
    })
    local _, height = session:GetBounds()
    if height then STANDARD_PAGE:SetDockHeight(math.max(60, height + 28)) end
end

STANDARD_PAGE = EXUI:CreateStandardModulePage({
    moduleKey = EXWIND_MODULE_KEY,
    page = GUIPage,
    binding = STANDARD_CONFIG_BINDING,
    layout = EX_LAYOUT,
    preview = {
        height = 160,
        render = function() RefreshStandardPreviewSurface() end,
        refresh = function() RefreshStandardPreviewSurface() end,
        release = function() STANDARD_PREVIEW_SURFACE:Release() end,
    },
    getColumns = 200,
    applyScrollSkin = function(scrollFrame)
        if ExBoss.UI and type(ExBoss.UI.ApplyModernScrollBarSkin) == "function" then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
    end,
    sliderContract = function()
        return {
            groupPaths = {
                raidMarkerExtra = "",
                layout = "layout",
                timerGroup = "timerGroup",
                font_spell = "font_spell",
                font_timer = "font_timer",
            },
        }
    end,
})

function GUIPage:Render(contentFrame)
    return STANDARD_PAGE:Render(contentFrame)
end

function GUIPage:Hide()
    return STANDARD_PAGE:Hide()
end
