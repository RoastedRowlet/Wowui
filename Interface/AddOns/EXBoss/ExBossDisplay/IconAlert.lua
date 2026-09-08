---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/IconAlert.lua
-- 通用图标容器：由其他模块通过 API 推入条目，统一负责图标/扫光/发光/堆叠布局。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
ExBoss.UI.IconAlert = ExBoss.UI.IconAlert or {}
local IconAlert = ExBoss.UI.IconAlert
local BorderUtil = ExBoss.BorderUtil

local MODULE_KEY = "ExBoss.IconAlert"
local PANEL_PREVIEW_MIN_HEIGHT = 160

local DEFAULTS = {
    enabled = true,
    anchorX = 0,
    anchorY = -40,
    attachToCustom = false,
    customAttachTarget = "",
    layout = { direction = "LEFT", spacing = 2, maxVisible = 5 },
    font_text = {
        enabled = false,
        autoWidth = false,
        font = "默认",
        size = 18,
        outline = "OUTLINE",
        r = 0.24705883860588,
        g = 0.91372555494308,
        b = 1,
        a = 1,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        x = 0,
        y = -6,
    },
    -- 图标标准固定文字槽位。名称仍是业务 child；倒数时间与层数属于 core.time /
    -- core.stacks，由标准 renderer 建立，模块只提供样式与相对位置。
    font_time = {
        enabled = true,
        autoWidth = false,
        font = "默认",
        size = 20,
        outline = "OUTLINE",
        r = 1,
        g = 0.82,
        b = 0,
        a = 1,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        x = 0,
        y = 0,
    },
    font_stacks = {
        enabled = true,
        autoWidth = false,
        font = "默认",
        size = 22,
        outline = "OUTLINE",
        r = 1,
        g = 1,
        b = 1,
        a = 1,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        x = 79.170220937111,
        y = -15.994008844103,
    },
    icon = {
        showIcon = true,
        iconID = nil,
        reverse = false,
        width = 45,
        height = 45,
        showBorder = true,
        borderTexture = "EX_Default",
        borderColorR = 0,
        borderColorG = 0,
        borderColorB = 0,
        borderColorA = 1,
        borderSize = 0,
        borderPadding = 0.6,
    },
    glowEnabled = false,
    glowStyle = "EDGE_FLOW",
    glowColorR = 1,
    glowColorG = 0.82,
    glowColorB = 0,
    glowColorA = 1,
    glowFrequency = 0.25,
    glowLines = 8,
    glowScale = 1,
    glowOffset = 0,
}

-- IconAlert 的唯一 ModuleDB 声明。root 字段和已有嵌套字段保持原名，runtime、
-- panel、world 与 Page 均只经 GetModuleDB(MODULE_KEY) 读取这一份配置。
local EX_DEFAULTS = {
    module = {
        enabled = DEFAULTS.enabled,
        anchorX = DEFAULTS.anchorX,
        anchorY = DEFAULTS.anchorY,
        attachToCustom = DEFAULTS.attachToCustom,
        customAttachTarget = DEFAULTS.customAttachTarget,
        glowEnabled = DEFAULTS.glowEnabled,
        glowStyle = DEFAULTS.glowStyle,
        glowColorR = DEFAULTS.glowColorR,
        glowColorG = DEFAULTS.glowColorG,
        glowColorB = DEFAULTS.glowColorB,
        glowColorA = DEFAULTS.glowColorA,
        glowFrequency = DEFAULTS.glowFrequency,
        glowLines = DEFAULTS.glowLines,
        glowScale = DEFAULTS.glowScale,
        glowOffset = DEFAULTS.glowOffset,
    },
    layout = DEFAULTS.layout,
    font_text = DEFAULTS.font_text,
    font_time = DEFAULTS.font_time,
    font_stacks = DEFAULTS.font_stacks,
    icon = DEFAULTS.icon,
}
local FONT_FIELDS = {
    "font", "size", "outline", "r", "g", "b", "a", "enabled", "shadow", "shadowX", "shadowY", "autoWidth", "justifyH", "justifyV", "x", "y",
}
local ICON_FIELDS = {
    "showIcon", "iconID", "reverse", "width", "height", "showBorder", "borderTexture",
    "borderColorR", "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding",
}
local DEFAULT_SCHEMA = {
    { group = "module", root = true, fields = {
        "enabled", "anchorX", "anchorY", "attachToCustom", "customAttachTarget",
        "glowEnabled", "glowStyle", "glowColorR", "glowColorG", "glowColorB", "glowColorA",
        "glowFrequency", "glowLines", "glowScale", "glowOffset",
    } },
    { group = "layout", fields = { "direction", "spacing", "maxVisible" } },
    { group = "font_text", fields = FONT_FIELDS },
    { group = "font_time", fields = FONT_FIELDS },
    { group = "font_stacks", fields = FONT_FIELDS },
    { group = "icon", fields = ICON_FIELDS },
}
ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

-- 标准图标面板交互只声明语义与同一 ModuleDB 的位置字段。EXUI 统一生成
-- presentation slots，并拥有右键 Focus、拖动写回和 Grid 回读；本模块不再处理
-- Panel intent。
local INTERACTION_SCHEMA = {
    ["core.label"] = {
        guiKey = "font_text", movable = true, tooltip = L["技能名称"], textRole = "label",
        position = { x = "font_text.x", y = "font_text.y" },
        anchor = { point = "TOP", relativePoint = "BOTTOM" },
    },
    ["core.time"] = {
        guiKey = "font_time", movable = true, tooltip = L["倒数文本"], textRole = "time",
        position = { x = "font_time.x", y = "font_time.y" },
        anchor = { point = "CENTER", relativePoint = "CENTER" },
    },
    ["icon.stacks"] = {
        guiKey = "font_stacks", movable = true, tooltip = L["层数文本"], textRole = "stacks",
        position = { x = "font_stacks.x", y = "font_stacks.y" },
        anchor = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT" },
    },
}

local CONFIG_SCHEMA_PATHS = {
    ["layout.direction"] = true, ["layout.spacing"] = true, ["layout.maxVisible"] = true,
    ["icon.width"] = true, ["icon.height"] = true, ["icon.x"] = true, ["icon.y"] = true,
    ["icon.alpha"] = true, ["icon.rotation"] = true,
    ["icon.cropLeft"] = true, ["icon.cropRight"] = true,
    ["icon.cropTop"] = true, ["icon.cropBottom"] = true,
    ["icon.borderSize"] = true, ["icon.borderPadding"] = true,
    ["icon.cooldown.swipeAlpha"] = true, ["icon.cooldown.edgeAlpha"] = true,
    ["font_text.size"] = true, ["font_text.x"] = true, ["font_text.y"] = true,
    ["font_text.shadowX"] = true, ["font_text.shadowY"] = true,
    ["font_text.fixedWidth"] = true, ["font_text.maxWidth"] = true,
    ["font_text.gradientStart"] = true, ["font_text.gradientLength"] = true,
    ["font_text.rotation"] = true, ["font_text.autoWidth"] = true,
    ["font_text.enabled"] = true,
    ["font_time.size"] = true, ["font_time.x"] = true, ["font_time.y"] = true,
    ["font_time.shadowX"] = true, ["font_time.shadowY"] = true,
    ["font_time.fixedWidth"] = true, ["font_time.maxWidth"] = true,
    ["font_time.gradientStart"] = true, ["font_time.gradientLength"] = true,
    ["font_time.rotation"] = true, ["font_time.autoWidth"] = true,
    ["font_time.enabled"] = true,
    ["font_stacks.size"] = true, ["font_stacks.x"] = true, ["font_stacks.y"] = true,
    ["font_stacks.shadowX"] = true, ["font_stacks.shadowY"] = true,
    ["font_stacks.fixedWidth"] = true, ["font_stacks.maxWidth"] = true,
    ["font_stacks.gradientStart"] = true, ["font_stacks.gradientLength"] = true,
    ["font_stacks.rotation"] = true, ["font_stacks.autoWidth"] = true,
    ["font_stacks.enabled"] = true,
    ["glowLines"] = true, ["glowLength"] = true, ["glowThickness"] = true,
    ["glowFrequency"] = true, ["glowScale"] = true, ["glowOffset"] = true,
}

IconAlert.StandardSliderContract = {
    groupPaths = {
        layout = "layout",
        icon = "icon",
        font_text = "font_text",
        font_time = "font_time",
        font_stacks = "font_stacks",
    },
}

local function BuildStandardIconInteraction(db)
    return EXUI:BuildStandardPreviewInteraction("Icon", db, INTERACTION_SCHEMA)
end

local frame
local anchorController
local anchorGroupOptions
local runtimeCollection
local worldCollection
local panelCollection
local panelPreview
local panelDock
local panelSurface
local worldEditing = false
local active = {}
local activeOrder = {}
local serial = 0
-- 每次 runtime presentation 都使用唯一 ID。旧 Cooldown 的完成通知即使晚到，
-- 也不能命中同 owner 的新记录或池化后的新 Item。
local runtimeGeneration = 0
local layoutInProgress = false
local layoutRequested = false
local EnsureAnchorController
local ApplyCollectionRecord
local RefreshAllActiveVisuals

-- ANCHOR_SCHEMA 在本文件较早建立；必须先声明同一 ModuleDB 入口。
-- Lua 的 local function 只从声明行起可见，放在后面会让 schema 捕获 global nil。
local function DB()
    return ExwindTools:GetModuleDB(MODULE_KEY)
end

-- 整体锚点只在此处声明。运行时 AnchorController 与设置页 AnchorGroup 必须
-- 消费同一次 CreateStandardModuleAnchor 返回的合同，禁止复制 DB key、默认位置
-- 或 frame picker 映射。
local ANCHOR_SCHEMA = {
    moduleKey = MODULE_KEY,
    frameName = "ExBoss_IconAlertAnchor",
    title = L["图标提示"],
    getDB = DB,
    offsetXKey = "anchorX",
    offsetYKey = "anchorY",
    defaultOffsetX = DEFAULTS.anchorX,
    defaultOffsetY = DEFAULTS.anchorY,
    syncWidgets = {
        "anchorX",
        "anchorY",
        "attachToCustom",
        "customAttachTarget",
    },
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    widgetRanges = {
        anchorX = { min = -1000, max = 1000, step = 1 },
        anchorY = { min = -600, max = 600, step = 1 },
    },
    -- 此声明在 SafeNum helper 定义之前建立，故不能调用后声明的 local helper。
    initialWidth = math.max(20, tonumber(DEFAULTS.icon.width) or 64),
    initialHeight = math.max(20, tonumber(DEFAULTS.icon.height) or 64),
    clampedToScreen = false,
    frameStrata = "DIALOG",
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    onCreateFrame = function(_, owner)
        owner:Hide()
    end,
}

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function ClampInt(v, minValue, maxValue, def)
    local n = math.floor((tonumber(v) or tonumber(def) or minValue) + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
    return n
end

-- Fixed Panel/World sample topology.  Declare this before any layout helper:
-- Lua locals are lexical, so a later declaration is not visible above it.
local PREVIEW_SLOT_COUNT = 8

-- Panel, World and Runtime share this normalized layout.  Its ceiling equals
-- the fixed sample topology, so Slider changing only reapplies existing items.
local function GetCollectionLayout(db)
    local source = type(db and db.layout) == "table" and db.layout or DEFAULTS.layout
    local direction = tostring(source.direction or DEFAULTS.layout.direction):upper()
    local allowed = { UP = true, DOWN = true, LEFT = true, RIGHT = true, CENTER_VERTICAL = true, CENTER_HORIZONTAL = true }
    if not allowed[direction] then direction = DEFAULTS.layout.direction end
    return {
        mode = "FLOW", direction = direction,
        spacing = SafeNum(source.spacing, DEFAULTS.layout.spacing),
        maxVisible = ClampInt(source.maxVisible, 1, PREVIEW_SLOT_COUNT, DEFAULTS.layout.maxVisible),
    }
end

local function Clamp01(v, def)
    local n = tonumber(v)
    if n == nil then
        n = tonumber(def)
    end
    if n == nil then
        n = 1
    end
    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    return n
end

local function SetClickThrough(obj)
    if not obj then return end
    obj:EnableMouse(false)
    if obj.SetMouseClickEnabled then
        pcall(obj.SetMouseClickEnabled, obj, false)
    end
    if obj.SetMouseMotionEnabled then
        pcall(obj.SetMouseMotionEnabled, obj, false)
    end
end

function IconAlert:GetDB()
    return DB()
end

local function GetLSMTexture(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(LSM.Fetch) == "function" and type(name) == "string" and name ~= "" then
        local ok, path = pcall(LSM.Fetch, LSM, "statusbar", name, true)
        if ok and path then
            return path
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function BuildGlowOptions(db)
    return {
        enabled = db.glowEnabled == true,
        style = tostring(db.glowStyle or DEFAULTS.glowStyle),
        color = {
            Clamp01(db.glowColorR, DEFAULTS.glowColorR),
            Clamp01(db.glowColorG, DEFAULTS.glowColorG),
            Clamp01(db.glowColorB, DEFAULTS.glowColorB),
            Clamp01(db.glowColorA, DEFAULTS.glowColorA),
        },
        frequency = tonumber(db.glowFrequency) or DEFAULTS.glowFrequency,
        lines = ClampInt(db.glowLines, 1, 30, DEFAULTS.glowLines),
        scale = tonumber(db.glowScale) or DEFAULTS.glowScale,
        offset = tonumber(db.glowOffset) or DEFAULTS.glowOffset,
    }
end

local function NormalizeOwner(owner)
    local t = type(owner)
    if t == "table" or t == "string" or t == "number" or t == "boolean" then
        return owner
    end
    return nil
end

local function StableOwnerKey(owner)
    local t = type(owner)
    if t == "string" or t == "number" or t == "boolean" then
        return tostring(owner)
    end
    if t ~= "table" then
        return nil
    end
    if type(owner.key) == "string" and owner.key ~= "" then
        return owner.key
    end
    if type(owner.id) == "string" or type(owner.id) == "number" then
        return tostring(owner.id)
    end
    local parts = {}
    for _, k in ipairs({ "source", "kind", "eventID", "spellID", "mapID", "npcID", "unit", "castBarID", "castKind" }) do
        local v = owner[k]
        if v ~= nil then
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    if #parts > 0 then
        return table.concat(parts, "|")
    end
    return tostring(owner)
end

local function DoesOwnerMatch(lhs, rhs)
    if lhs == rhs then
        return true
    end
    local lt, rt = type(lhs), type(rhs)
    if lt ~= rt then
        return false
    end
    if lt == "string" or lt == "number" or lt == "boolean" then
        return tostring(lhs) == tostring(rhs)
    end
    if lt ~= "table" then
        return false
    end
    return StableOwnerKey(lhs) == StableOwnerKey(rhs)
end

local function ResolveTexture(entry, db)
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    local forced = tonumber(iconDB.iconID)
    if forced then
        if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, tex = pcall(C_Spell.GetSpellTexture, forced)
            if ok and tex then
                return tex
            end
        end
        if type(GetSpellTexture) == "function" then
            local ok, tex = pcall(GetSpellTexture, forced)
            if ok and tex then
                return tex
            end
        end
        return forced
    end
    if entry and entry.icon then
        return entry.icon
    end
    local spellID = tonumber(entry and entry.spellID)
    if spellID and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end
    if spellID and type(GetSpellTexture) == "function" then
        local ok, tex = pcall(GetSpellTexture, spellID)
        if ok and tex then
            return tex
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function CellWidth(db)
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    return math.max(1, SafeNum(iconDB.width, DEFAULTS.icon.width))
end

local function CellHeight(db)
    local iconDB = type(db.icon) == "table" and db.icon or DEFAULTS.icon
    local height = math.max(1, SafeNum(iconDB.height, DEFAULTS.icon.height))
    return height + 24
end

local function ResolveDisplayName(entry)
    local text = tostring(type(entry) == "table" and entry.text or "")
    if text ~= "" then
        return text
    end
    local displayName = tostring(type(entry) == "table" and entry.displayName or "")
    if displayName ~= "" then
        return displayName
    end
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if spellID and type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return ""
end

-- 运行时普通倒数的唯一构造点。expirationTime 是业务状态确定时刻，后续外观
-- 刷新只能复用这个同一 Duration Object，绝不能用 GetTime 重建旧数字路径。
local function CreateRuntimeDurationObject(expirationTime, duration, modRate)
    if not (C_DurationUtil and type(C_DurationUtil.CreateDuration) == "function") then
        error("IconAlert requires C_DurationUtil.CreateDuration for runtime cooldowns", 2)
    end
    local durationObject = C_DurationUtil.CreateDuration()
    durationObject:SetTimeFromEnd(expirationTime, duration, modRate)
    return durationObject
end

local function BuildIconPresentation(record, db, static)
    if type(record) ~= "table" then return nil end
    local icon = db.icon or DEFAULTS.icon
    local entry = record.entry or record
    local runtimeDuration = static ~= true and record.durationObject or nil
    local cooldownVisualVisible, countdownTextVisible
    if static ~= true and entry.hideCooldown == true then
        cooldownVisualVisible, countdownTextVisible = false, false
    end
    -- hideCooldown 只覆盖当前 presentation 的可见性；样式始终是同一份
    -- ModuleDB.icon，Duration Object 仍保留以接收正式完成通知。
    local width, height = math.max(1, SafeNum(icon.width, 64)), math.max(1, SafeNum(icon.height, 64))
    local labelHeight = math.max(18, SafeNum((db.font_text or {}).size, 13) + 7)
    local textX, textY = SafeNum((db.font_text or {}).x, 0), SafeNum((db.font_text or {}).y, -4)
    local timeX, timeY = SafeNum((db.font_time or {}).x, 0), SafeNum((db.font_time or {}).y, 0)
    local stacksX, stacksY = SafeNum((db.font_stacks or {}).x, -2), SafeNum((db.font_stacks or {}).y, 2)
    local glowMargin = db.glowEnabled == true and math.max(12, math.abs(SafeNum(db.glowOffset, 0)) + 12) or 0
    local labelBottom = -height * 0.5 + textY - labelHeight
    return {
        style = { icon = icon, text = { label = db.font_text or DEFAULTS.font_text, countdown = db.font_time or DEFAULTS.font_time, stacks = db.font_stacks or DEFAULTS.font_stacks } },
        -- Collection presentation is shared by runtime, world edit, and panel
        -- preview.  Resolve the texture with the same formal ModuleDB snapshot
        -- supplied to this render pass; do not let this path fall back to an
        -- implicit/preview database.
        icon = ResolveTexture(entry, db),
        label = ResolveDisplayName(entry),
        stacks = entry.stacks,
        -- panel/world 是静态样本；runtime 只能传正式 DURATION Object，禁止把
        -- { start, duration } 交给旧 IconWidget 数字逐帧路径。
        cooldown = static and { static = true, remaining = record.remaining or 3, duration = record.duration or 10 } or
            (runtimeDuration and {
                mode = "DURATION",
                duration = record.durationObject,
                clearIfZero = true,
            } or nil),
        -- 只允许有正式 Duration Object 的 runtime presentation 接收原生完成通知。
        -- Secret/无 duration 的语义不会被这里推断、比较或误删。
        cooldownDone = runtimeDuration ~= nil,
        hideCooldownVisual = static ~= true and entry.hideCooldown == true,
        cooldownVisualVisible = cooldownVisualVisible,
        countdownTextVisible = countdownTextVisible,
        -- ItemRoot 只代表固定 Icon Body；名称和 glow 只扩大声明选择范围。
        bodySize = { width = width, height = height },
        declaredBounds = { left = -width * 0.5 - math.max(20, glowMargin), right = width * 0.5 + math.max(20, glowMargin),
            bottom = math.min(labelBottom, -height * 0.5 - glowMargin), top = height * 0.5 + glowMargin },
        -- 固定 core 槽位的布局是纯 presentation。IconCollection 在建立 panel
        -- hitbox 前物化它；模块不再取得 Widget 或注册 render/release hook。
        coreLayout = {
            label = {
                bounds = { width = width + 40, height = labelHeight },
                anchor = { point = "TOP", relativeElement = "core.icon", relativePoint = "BOTTOM", x = 0, y = 0 },
            },
            time = {
                bounds = { width = width, height = height },
                anchor = { point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER", x = 0, y = 0 },
            },
            stacks = {
                anchor = { point = "BOTTOMRIGHT", relativeElement = "core.icon", relativePoint = "BOTTOMRIGHT", x = 0, y = 0 },
            },
            glow = BuildGlowOptions(db),
        },
        interaction = BuildStandardIconInteraction(db),
        runtimeTooltip = (not static and entry.spellID) and { spellID = entry.spellID } or nil,
    }
end

ApplyCollectionRecord = function(record, db, collection, static)
    collection = collection or runtimeCollection
    if not collection or type(record) ~= "table" then return nil end
    local recordKey = record.key
    local renderID = record.renderID
    local itemID = tostring(renderID or recordKey or record.id or "iconalert-preview")
    local item = collection:AcquireItem(itemID)
    -- 先登记再 Apply：若一个已到期的 native Duration 在 Apply 中同步完成，
    -- 回调会释放当前 item，而不是留下刚 acquire 的孤儿。
    record.collectionItem = item
    local presentation = BuildIconPresentation(record, db, static)
    collection:ApplyItem(item, presentation)
    if static ~= true and (not recordKey or active[recordKey] ~= record or record.renderID ~= renderID) then
        return nil
    end
    return item
end

local function ReleaseRecord(record)
    if type(record) ~= "table" then
        return
    end
    if runtimeCollection and record.collectionItem then
        runtimeCollection:ReleaseItem(record.collectionItem.id)
    end
    record.collectionItem = nil
    record.key = nil
    record.owner = nil
    record.entry = nil
    record.expirationTime = nil
    record.durationObject = nil
    record.renderID = nil
end

local function RemoveRecordByKey(key, expectedRenderID)
    local record = active[key]
    if not record or (expectedRenderID ~= nil and record.renderID ~= expectedRenderID) then
        return false
    end
    active[key] = nil
    for i = #activeOrder, 1, -1 do
        if activeOrder[i] == key then
            table.remove(activeOrder, i)
            break
        end
    end
    ReleaseRecord(record)
    return true
end

local function RemoveRecordByRenderID(renderID)
    if type(renderID) ~= "string" or renderID == "" then return false end
    for i = #activeOrder, 1, -1 do
        local key = activeOrder[i]
        local record = active[key]
        if record and record.renderID == renderID then
            return RemoveRecordByKey(key, renderID)
        end
    end
    return false
end

local function LayoutRecordsOnce()
    if not frame or not runtimeCollection then
        return
    end
    if worldEditing then
        runtimeCollection:SetItems({}, { mode = "FLOW", direction = "RIGHT", spacing = 0, maxVisible = 1 })
        return
    end
    local db = DB()
    local collectionLayout = GetCollectionLayout(db)
    local cellW = CellWidth(db)
    local cellH = CellHeight(db)
    local maxVisible = collectionLayout.maxVisible
    local visibleCount = 0
    local records = {}
    for i = 1, #activeOrder do
        local record = active[activeOrder[i]]
        if record then
            -- 即使超过显示上限，仍要把正式 Duration Object 交给 native Cooldown。
            -- WidgetLayout 会隐藏超额项，但它们仍能在到期时各自回调并释放。
            records[#records + 1] = record
        end
    end
    if db.enabled == true and db.icon.showIcon == true then
        visibleCount = math.min(maxVisible, #records)
    end

    local items = {}
    for _, record in ipairs(records) do
        local item = ApplyCollectionRecord(record, db, runtimeCollection, false)
        if item then
            record.collectionItem = item
            items[#items + 1] = item
        end
    end
    runtimeCollection:SetItems(items, collectionLayout)
    local width, height = runtimeCollection:GetBounds()
    frame:SetSize(math.max(1, width or cellW), math.max(1, height or cellH))

    if visibleCount > 0 or frame.__ExwindStandardWorldPreview == true then
        frame:Show()
    else
        frame:Hide()
    end
end

-- 原生 OnCooldownDone 可以发生在一次完整 Layout 的 Apply 过程中；把重入压成
-- 本轮结束后的一次重排，避免旧 item 在外层 layout 返回时被重新加入。
local function LayoutRecords()
    if layoutInProgress then
        layoutRequested = true
        return
    end
    layoutInProgress = true
    repeat
        layoutRequested = false
        LayoutRecordsOnce()
    until not layoutRequested
    layoutInProgress = false
end

RefreshAllActiveVisuals = function()
    LayoutRecords()
end

local function StopAllActive()
    for i = #activeOrder, 1, -1 do
        RemoveRecordByKey(activeOrder[i])
    end
    if frame and frame.__ExwindStandardWorldPreview ~= true then
        frame:Hide()
    end
end

-- 图标 Collection 的样本唯一内容真源。世界编辑和设置页面板都只消费同一
-- record -> BuildIconPresentation 链；运行时 active 记录绝不承担编辑样本。
local PREVIEW_SPELL_IDS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }
-- 设置页预览的硬下限：不论用户将 runtime maxVisible 设为多少，也必须至少有
-- 两个可见样本，才能同时检查图标、名称、倒数、层数与排列。这个下限仅适用于
-- panel/world 静态样本，绝不改变 runtime 的真实显示上限。
-- Keep the complete legal topology materialized.  Layout settings may only
-- hide/reposition those slots; a maxVisible slider must never change the
-- panel/world Item count during its live in-place reapply.
local PREVIEW_FALLBACK_SAMPLES = {
    -- 这里故意不依赖本地化表：即使语言包尚未加载，fallback 也必须是可渲染字符串。
    { spellID = 1311923, name = L["测试样本 1"], iconID = "Interface\\Icons\\INV_Misc_QuestionMark" },
    { spellID = 1310025, name = L["测试样本 2"], iconID = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

-- 优先使用客户端 API 返回的真实法术信息；API 无结果时只在静态预览补足明确的
-- fallback，不允许设置页产生零样本。
local function BuildPreviewSpells()
    local spells = {}
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        for _, spellID in ipairs(PREVIEW_SPELL_IDS) do
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.name and info.iconID then
                spells[#spells + 1] = { spellID = spellID, name = info.name, iconID = info.iconID }
            end
        end
    end

    -- PTR、旧客户端或尚未缓存这些法术时，API 可合法返回 nil。预览不能因此成为
    -- 空白页：补足两个可循环使用的静态 question-mark 样本；正式 runtime
    -- 不消费此列表。
    local fallbackIndex = 1
    while #spells < 2 do
        local fallback = PREVIEW_FALLBACK_SAMPLES[((fallbackIndex - 1) % #PREVIEW_FALLBACK_SAMPLES) + 1]
        spells[#spells + 1] = {
            spellID = fallback.spellID,
            name = fallback.name,
            iconID = fallback.iconID,
        }
        fallbackIndex = fallbackIndex + 1
    end
    return spells
end

local function BuildCollectionPreviewRecords()
    local result, spells = {}, BuildPreviewSpells()
    -- The slot count is deliberately constant.  maxVisible belongs solely to
    -- the shared semantic layout, which keeps changing/committed reapply
    -- topology-safe and makes the maximum slider authoritative at every value.
    for index = 1, PREVIEW_SLOT_COUNT do
        local sample = spells[((index - 1) % #spells) + 1]
        result[#result + 1] = {
            key = "iconalert-preview:" .. index,
            -- 直接携带 API 返回的 iconID；不要在预览二次查询 GetSpellTexture，避免
            -- 一个可用 GetSpellInfo 结果被另一个 API 的 nil 再次变成空白/问号。
            entry = { spellID = sample.spellID, icon = sample.iconID, displayName = sample.name, stacks = index },
            duration = 15,
            remaining = math.max(1, 15 - (index - 1) * 3),
        }
    end
    return result
end

local function RenderIconCollection(collection, records, db, static)
    if not collection then return end
    local items = {}
    for _, record in ipairs(records or {}) do
        local item = ApplyCollectionRecord(record, db, collection, static)
        if item then items[#items + 1] = item end
    end
    collection:SetItems(items, GetCollectionLayout(db))
end

local function BuildPanelPreviewEntries(db, records)
    local entries = {}
    for _, record in ipairs(records or BuildCollectionPreviewRecords()) do
        entries[#entries + 1] = {
            itemID = tostring(record.key),
            presentation = BuildIconPresentation(record, db, true),
        }
    end
    return entries
end

-- Panel 的唯一 session 由 StandardPreviewSurface 持有；这里仍只把既有静态样本
-- 转成同一份 Icon presentation，不创建第二棵 Collection 树。
local function BuildPanelSurfacePresentation(records, mode)
    if mode ~= "panel" then error("IconAlert panel surface only supports panel mode", 2) end
    local db = DB()
    return {
        entries = BuildPanelPreviewEntries(db, records),
        layout = GetCollectionLayout(db),
    }
end

local function EnsurePanelSurface()
    if panelSurface then return panelSurface end
    panelSurface = EXUI:CreateStandardPreviewSurface({
        moduleKey = MODULE_KEY,
        kind = "icon",
        buildPresentation = BuildPanelSurfacePresentation,
        interactionSchema = INTERACTION_SCHEMA,
        requiredPositionGuiKeys = { "font_text", "font_time", "font_stacks" },
    })
    return panelSurface
end

local function ResizePanelDock(dock, session)
    local collection = session and session:GetCollection()
    if not dock or not collection then return end
    local _, height = collection:GetBounds()
    dock:SetHeight(math.max(PANEL_PREVIEW_MIN_HEIGHT, (height or 0) + 28))
end

local function RenderPanelPreview()
    if not panelDock or not panelSurface then return end
    panelPreview = panelSurface:Render({
        dock = panelDock,
        ruleKey = MODULE_KEY,
        state = BuildCollectionPreviewRecords(),
    })
    panelCollection = panelPreview:GetCollection()
    ResizePanelDock(panelDock, panelPreview)
end

function IconAlert:ShowPanelPreview(dock)
    if not dock then return end
    local surface = EnsurePanelSurface()
    panelPreview = surface:Render({
        dock = dock,
        ruleKey = MODULE_KEY,
        state = BuildCollectionPreviewRecords(),
    })
    panelDock = dock
    panelCollection = panelPreview:GetCollection()
    ResizePanelDock(panelDock, panelPreview)
end

function IconAlert:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelCollection = nil
    panelDock = nil
end

function IconAlert:RenderWorld(host)
    if not host then return end
    if worldCollection then worldCollection:Release() end
    worldEditing = true
    if runtimeCollection then runtimeCollection:SetItems({}, { mode = "FLOW", direction = "RIGHT", spacing = 0, maxVisible = 1 }) end
    worldCollection = ExwindTools.UI:CreateIconCollection(host, "world", MODULE_KEY)
    RenderIconCollection(worldCollection, BuildCollectionPreviewRecords(), DB(), true)
end

function IconAlert:GetWorldBounds()
    return worldCollection and worldCollection:GetWorldBounds() or nil
end

function IconAlert:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    RefreshAllActiveVisuals()
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController, anchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)

    return anchorController
end

function IconAlert:GetStandardAnchorGroupOptions()
    EnsureAnchorController()
    return anchorGroupOptions
end

local function ApplyAnchorPosition()
    if not frame then
        return
    end
    EnsureAnchorController():ApplyPosition()
end

local function Ensure()
    if frame then
        return true
    end

    frame = EnsureAnchorController():Ensure()
    runtimeCollection = ExwindTools.UI:CreateIconCollection(frame, "runtime", MODULE_KEY, {
        -- 到期由 Blizzard Cooldown 原生通知；不读取剩余时间、不建 Lua 逐帧/Ticker。
        onCooldownDone = function(content)
            local renderID = content and tostring(content.itemID or "") or ""
            if RemoveRecordByRenderID(renderID) then
                LayoutRecords()
            end
        end,
    })

    ApplyAnchorPosition()
    return true
end

function IconAlert:ShowEntry(entry, forcedRemaining)
    if not Ensure() then
        return nil
    end
    local db = DB()
    if db.enabled ~= true or db.icon.showIcon ~= true or type(entry) ~= "table" then
        return nil
    end

    local duration = math.max(0.1, SafeNum(entry.duration, 5))
    local remaining = SafeNum(forcedRemaining, nil)
    local now = GetTime()
    local expirationTime
    if remaining ~= nil then
        expirationTime = now + math.max(0, remaining)
    else
        expirationTime = SafeNum(entry.endTime, now + duration)
        remaining = math.max(0, expirationTime - now)
    end
    if remaining <= 0 then
        return nil
    end

    local owner = NormalizeOwner(entry.owner or entry.key)
    local key = StableOwnerKey(owner)
    if not key or key == "" then
        serial = serial + 1
        key = "anon:" .. tostring(serial)
    end

    local record = active[key]
    if not record then
        record = {}
        active[key] = record
        activeOrder[#activeOrder + 1] = key
    end

    record.key = key
    record.owner = owner
    record.entry = entry
    runtimeGeneration = runtimeGeneration + 1
    record.renderID = key .. "@" .. tostring(runtimeGeneration)
    record.expirationTime = expirationTime
    -- hideCooldown 仍须交给原生 Duration 完成回调，只是 presentation 会隐藏视觉。
    record.durationObject = CreateRuntimeDurationObject(expirationTime, duration, SafeNum(entry.modRate, 1))
    LayoutRecords()
    return key
end

function IconAlert:ShowSequence(sequence, opts)
    if type(sequence) ~= "table" then
        return 0
    end
    local count = 0
    opts = type(opts) == "table" and opts or {}
    for i = 1, #sequence do
        local row = type(sequence[i]) == "table" and sequence[i] or nil
        if row then
            if row.owner == nil and opts.ownerPrefix then
                row.owner = tostring(opts.ownerPrefix) .. ":" .. tostring(i)
            end
            if self:ShowEntry(row, row.forcedRemaining) then
                count = count + 1
            end
        end
    end
    return count
end

function IconAlert:StopByOwner(owner)
    local removed = 0
    for i = #activeOrder, 1, -1 do
        local key = activeOrder[i]
        local record = active[key]
        if record and DoesOwnerMatch(record.owner, owner) then
            RemoveRecordByKey(key)
            removed = removed + 1
        end
    end
    LayoutRecords()
    return removed
end

-- 游戏内手动渲染检查：/run ExBoss.UI.IconAlert:Test()
-- 只通过现有 ShowEntry API 推入一条稳定记录；重复调用会替换同一 owner。
function IconAlert:Test()
    local owner = "ExBoss.IconAlert.Test"
    self:StopByOwner(owner)
    return self:ShowEntry({
        owner = owner,
        spellID = 642,
        text = L["图标测试"],
        duration = 20,
        endTime = GetTime() + 20,
        stacks = 3,
    })
end

function IconAlert:Hide()
    StopAllActive()
end

function IconAlert:IsPlaying()
    return #activeOrder > 0
end

function IconAlert:RefreshVisuals(options)
    if not frame then
        if not Ensure() then
            return
        end
    end
    ApplyAnchorPosition()
    RefreshAllActiveVisuals()
    if worldCollection then RenderIconCollection(worldCollection, BuildCollectionPreviewRecords(), DB(), true) end
    -- 外部调用未传 options 时保留完整 Panel 刷新；标准 Slider 放开时仅同步
    -- 正式 runtime/world，只有 旧字段补丁 明确要求重建才刷新 Panel。
    if options == nil or options.rebuildPanelPreview == true then
        RenderPanelPreview()
    end
end

function IconAlert:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        if Ensure() then
            IconAlert:RefreshVisuals()
        end
    end)
end)

ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", MODULE_KEY .. "_combat_init", function()
    if frame then
        return
    end
    if Ensure() then
        IconAlert:RefreshVisuals()
    end
end)

C_Timer.After(0, function()
    if frame then
        return
    end
    if Ensure() then
        IconAlert:RefreshVisuals()
    end
end)

-- 编辑模式仅注册已有 Core 的 anchor/world renderer 合同；不创建另一套预览树。
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "iconalert",
    name = L["图标提示"],
    settingsPage = "iconalert",
    appearanceProfile = "basicIcon",
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor = function()
        Ensure()
        return frame
    end,
    GetWorldBounds = function() return IconAlert:GetWorldBounds() end,
    RenderWorld = function(host) return IconAlert:RenderWorld(host) end,
    ReleaseWorld = function() return IconAlert:ReleaseWorld() end,
})

for _, path in ipairs({ "anchorX", "anchorY", "attachToCustom", "customAttachTarget" }) do CONFIG_SCHEMA_PATHS[path] = true end
local STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    reapplyExisting = function()
        local layout = GetCollectionLayout(DB())
        local function reapply(surface)
            if surface and type(surface.ReapplyPanelPresentation) == "function" then
                surface:ReapplyPanelPresentation()
            elseif surface and type(surface.ReapplyCurrentItems) == "function" then
                surface:ReapplyCurrentItems(nil, { reapplyLayout = false })
                if type(surface.ReapplyCurrentLayout) == "function" then
                    surface:ReapplyCurrentLayout(layout)
                end
            end
        end
        reapply(panelSurface)
        reapply(panelPreview)
        ResizePanelDock(panelDock, panelPreview)
        reapply(worldCollection)
        reapply(runtimeCollection)
    end,
    -- 拖动只改当前已物化 Icon/Text/Layout；不调用模块私有的重套路径。
    schemaPaths = CONFIG_SCHEMA_PATHS,
})

local function RefreshActiveSurfaces()
    return STANDARD_CONFIG_BINDING.reapplyExisting()
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })
