-- =============================================================
-- 战斗怪物 Debuff 格子
-- 白色普通格由本模块持有；红色格只由每个 nameplate 的原生 AuraContainer
-- 在目标 Debuff 存在时显示。禁止读取 AuraButton / Aura 数据，也不监听 UNIT_AURA。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.CombatMobDebuffGrid"

local MAX_NAMEPLATES = 40
local DEFAULT_CELL_WIDTH = 20
local DEFAULT_CELL_HEIGHT = 20
local DEFAULT_CELL_GAP = 3
local DEFAULT_CELLS_PER_ROW = 5
local DEFAULT_OFFSET_X = -60
local MAX_DEBUFF_SPELL_IDS = 10
local REFRESH_INTERVAL = 0.10
local AURA_SLOT_KEY = "watched_debuff"
local AURA_TEMPLATE = "ExToolsCombatMobDebuffGridAuraButtonTemplate"

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local SPEC_OPTION_DEFS = {
    { specID = 71, className = "战士", specName = "武器", colorHex = "C79C6E" },
    { specID = 72, className = "战士", specName = "狂怒", colorHex = "C79C6E" },
    { specID = 73, className = "战士", specName = "防护", colorHex = "C79C6E" },
    { specID = 65, className = "圣骑士", specName = "神圣", colorHex = "F48CBA" },
    { specID = 66, className = "圣骑士", specName = "防护", colorHex = "F48CBA" },
    { specID = 70, className = "圣骑士", specName = "惩戒", colorHex = "F48CBA" },
    { specID = 253, className = "猎人", specName = "野兽控制", colorHex = "ABD473" },
    { specID = 254, className = "猎人", specName = "射击", colorHex = "ABD473" },
    { specID = 255, className = "猎人", specName = "生存", colorHex = "ABD473" },
    { specID = 259, className = "潜行者", specName = "奇袭", colorHex = "FFF468" },
    { specID = 260, className = "潜行者", specName = "狂徒", colorHex = "FFF468" },
    { specID = 261, className = "潜行者", specName = "敏锐", colorHex = "FFF468" },
    { specID = 256, className = "牧师", specName = "戒律", colorHex = "FFFFFF" },
    { specID = 257, className = "牧师", specName = "神圣", colorHex = "FFFFFF" },
    { specID = 258, className = "牧师", specName = "暗影", colorHex = "FFFFFF" },
    { specID = 250, className = "死亡骑士", specName = "鲜血", colorHex = "C41E3A" },
    { specID = 251, className = "死亡骑士", specName = "冰霜", colorHex = "C41E3A" },
    { specID = 252, className = "死亡骑士", specName = "邪恶", colorHex = "C41E3A" },
    { specID = 262, className = "萨满祭司", specName = "元素", colorHex = "0070DD" },
    { specID = 263, className = "萨满祭司", specName = "增强", colorHex = "0070DD" },
    { specID = 264, className = "萨满祭司", specName = "恢复", colorHex = "0070DD" },
    { specID = 62, className = "法师", specName = "奥术", colorHex = "3FC7EB" },
    { specID = 63, className = "法师", specName = "火焰", colorHex = "3FC7EB" },
    { specID = 64, className = "法师", specName = "冰霜", colorHex = "3FC7EB" },
    { specID = 265, className = "术士", specName = "痛苦", colorHex = "8788EE" },
    { specID = 266, className = "术士", specName = "恶魔学识", colorHex = "8788EE" },
    { specID = 267, className = "术士", specName = "毁灭", colorHex = "8788EE" },
    { specID = 268, className = "武僧", specName = "酒仙", colorHex = "00FF98" },
    { specID = 269, className = "武僧", specName = "踏风", colorHex = "00FF98" },
    { specID = 270, className = "武僧", specName = "织雾", colorHex = "00FF98" },
    { specID = 102, className = "德鲁伊", specName = "平衡", colorHex = "FF7C0A" },
    { specID = 103, className = "德鲁伊", specName = "野性", colorHex = "FF7C0A" },
    { specID = 104, className = "德鲁伊", specName = "守护", colorHex = "FF7C0A" },
    { specID = 105, className = "德鲁伊", specName = "恢复", colorHex = "FF7C0A" },
    { specID = 577, className = "恶魔猎手", specName = "浩劫", colorHex = "A330C9" },
    { specID = 581, className = "恶魔猎手", specName = "复仇", colorHex = "A330C9" },
    { specID = 1467, className = "唤魔师", specName = "湮灭", colorHex = "33937F" },
    { specID = 1468, className = "唤魔师", specName = "恩护", colorHex = "33937F" },
    { specID = 1473, className = "唤魔师", specName = "增辉", colorHex = "33937F" },
    { specID = 1480, className = "恶魔猎手", specName = "噬灭", colorHex = "A330C9" },
}

local RefreshRuntime
local EnsureAnchorController
local EnsureAnchor
local anchorController
local anchorFrame
local refreshFrame
local refreshElapsed = 0
local worldPreviewActive = false
local lastRuntimeSignature
local gridCells = {}
local auraRecordsByUnit = {}
local spellDisplayCache = {}
local spellRendererContext

local function ParseSpellID(value)
    local spellID = tonumber(value)
    if not spellID or spellID <= 0 or spellID % 1 ~= 0 then
        return nil
    end
    return spellID
end

local function ClampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value then
        return fallback
    end
    return math.min(maximum, math.max(minimum, value))
end

local function GetGridSettings(db)
    db = db or {}
    return {
        cellWidth = ClampNumber(db.cellWidth, 8, 100, DEFAULT_CELL_WIDTH),
        cellHeight = ClampNumber(db.cellHeight, 8, 100, DEFAULT_CELL_HEIGHT),
        cellGap = ClampNumber(db.cellGap, 0, 30, DEFAULT_CELL_GAP),
        cellsPerRow = math.floor(ClampNumber(db.cellsPerRow, 1, 20, DEFAULT_CELLS_PER_ROW)),
        noDebuffColorR = ClampNumber(db.noDebuffColorR, 0, 1, 1),
        noDebuffColorG = ClampNumber(db.noDebuffColorG, 0, 1, 1),
        noDebuffColorB = ClampNumber(db.noDebuffColorB, 0, 1, 1),
        noDebuffColorA = ClampNumber(db.noDebuffColorA, 0, 1, 0.95),
        debuffColorR = ClampNumber(db.debuffColorR, 0, 1, 0.92),
        debuffColorG = ClampNumber(db.debuffColorG, 0, 1, 0.08),
        debuffColorB = ClampNumber(db.debuffColorB, 0, 1, 0.08),
        debuffColorA = ClampNumber(db.debuffColorA, 0, 1, 1),
    }
end

local function GetSpecOptionValue(specID)
    return tostring(specID)
end

local function BuildSpecOptions()
    local options = {}
    for _, def in ipairs(SPEC_OPTION_DEFS) do
        options[#options + 1] = {
            value = GetSpecOptionValue(def.specID),
            label = string.format("|cff%s%s|r - %s", def.colorHex, L[def.className] or def.className, L[def.specName] or def.specName),
        }
    end
    return options
end

local function BuildDefaultEnabledSpecs()
    local enabledSpecs = {}
    for _, def in ipairs(SPEC_OPTION_DEFS) do
        enabledSpecs[GetSpecOptionValue(def.specID)] = true
    end
    return enabledSpecs
end

local SPEC_OPTIONS = BuildSpecOptions()

local function IsCurrentSpecEnabled(db)
    local state = ExwindTools.State
    local specID = state and tonumber(state.SpecID) or nil
    if not specID or specID <= 0 then
        return true
    end

    local enabledSpecs = db and db.enabledSpecs
    -- 未记录的专精保持启用，避免未来新增专精因旧配置而被静默禁用。
    return type(enabledSpecs) ~= "table" or enabledSpecs[GetSpecOptionValue(specID)] ~= false
end

local function IsHostileLivingNameplate(unit)
    return type(unit) == "string"
        and _G.UnitExists(unit) == true
        and _G.UnitCanAttack("player", unit) == true
        and _G.UnitIsDead(unit) ~= true
end

local function GetExternalCombatRows()
    local exBoss = _G.ExBoss
    local state = exBoss and exBoss.TrashCD and exBoss.TrashCD.State or nil
    if not state or type(state.GetUnits) ~= "function" then
        return nil
    end

    local rows = state.GetUnits()
    if type(rows) ~= "table" then
        return nil
    end

    local units = {}
    for index = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. index
        local row = rows[unit]
        if type(row) == "table"
            and row.active == true
            and row.inCombat == true
            and IsHostileLivingNameplate(unit) then
            units[#units + 1] = unit
        end
    end
    return units
end

local function GetFallbackCombatRows()
    local units = {}
    for index = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. index
        if IsHostileLivingNameplate(unit) and _G.UnitAffectingCombat(unit) == true then
            units[#units + 1] = unit
        end
    end
    return units
end

local function GetCombatUnits()
    -- EXBoss 存在时，战斗状态只从其已验证的 TrashCD.State 缓存读取。
    -- 没有 EXBoss 才执行同样的 nameplate combat fallback 轮询。
    return GetExternalCombatRows() or GetFallbackCombatRows()
end

local function BuildSignature(units, spellIDSignature, enabled)
    if enabled ~= true then
        return "disabled"
    end
    return tostring(spellIDSignature or "none") .. ":" .. table.concat(units, ",")
end

local function CollectSpellIDs(db)
    local spellIDs = {}
    local signatureParts = {}
    for _, entry in ipairs(type(db.debuffSpellEntries) == "table" and db.debuffSpellEntries or {}) do
        local spellID = type(entry) == "table" and entry.present == true and ParseSpellID(entry.value) or nil
        if spellID and spellIDs[spellID] ~= true then
            spellIDs[spellID] = true
            signatureParts[#signatureParts + 1] = tostring(spellID)
        end
    end
    if #signatureParts == 0 then
        return nil, nil
    end
    return spellIDs, table.concat(signatureParts, ",")
end

local function GetDB()
    return ExwindTools:GetModuleDB(MODULE_KEY)
end

local function GetStoredSpellEntries(createForExplicitEdit)
    local storage = ExwindTools:GetModuleDBStorage(MODULE_KEY)
    local existing = storage and storage.ModuleDB and storage.ModuleDB[MODULE_KEY]
    if type(existing) == "table" then
        local entries = rawget(existing, "debuffSpellEntries")
        if type(entries) == "table" then return entries end
        if entries ~= nil or not createForExplicitEdit then return nil end
        entries = {}
        existing.debuffSpellEntries = entries
        return entries
    end
    if existing ~= nil or not createForExplicitEdit then return nil end

    -- An absent module table is initialized only in direct response to Add.
    local db = GetDB()
    if type(db) ~= "table" then return nil end
    db.debuffSpellEntries = {}
    return db.debuffSpellEntries
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
local spellDataEventFrame = CreateFrame("Frame")
spellDataEventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
spellDataEventFrame:SetScript("OnEvent", function(_, _, spellID, success)
    spellID = tonumber(spellID)
    local cached = spellID and spellDisplayCache[spellID]
    if not cached then return end
    cached.requested = nil
    cached.completed = true
    cached.failed = success ~= true
    if success == true and _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local info = _G.C_Spell.GetSpellInfo(spellID)
        if info then
            cached.name = info.name
            cached.iconID = info.iconID
            cached.failed = nil
        end
    end
    if spellRendererContext then spellRendererContext:RefreshPage() end
end)

local function GetSpellDisplay(value)
    local spellID = ParseSpellID(value)
    if not spellID then return L["无效法术 ID"] end
    local cached = spellDisplayCache[spellID]
    if not cached then
        cached = {}
        spellDisplayCache[spellID] = cached
    end

    local spellAPI = _G.C_Spell
    local info = spellAPI and spellAPI.GetSpellInfo and spellAPI.GetSpellInfo(spellID)
    if info then
        cached.name = info.name
        cached.iconID = info.iconID
        cached.failed = nil
        cached.requested = nil
        cached.completed = true
    elseif spellAPI and spellAPI.RequestLoadSpellData and not cached.requested and not cached.completed then
        local exists = not spellAPI.DoesSpellExist or spellAPI.DoesSpellExist(spellID) == true
        local isCached = spellAPI.IsSpellDataCached and spellAPI.IsSpellDataCached(spellID) == true
        if exists and not isCached then
            cached.requested = true
            spellAPI.RequestLoadSpellData(spellID)
        elseif not exists or isCached then
            cached.completed = true
            cached.failed = true
        end
    end

    local name = cached.name or L["未知法术"]
    if cached.iconID then
        return string.format("|T%s:20:20:0:0|t %s", tostring(cached.iconID), name)
    end
    return name
end

local function PickAnchor()
    local controller = EnsureAnchorController and EnsureAnchorController()
    return controller and controller:StartFramePicker() or false
end

local ANCHOR_OPTS = {
    bindRoot = true,
    offsetXKey = "offsetX",
    offsetYKey = "offsetY",
    defaultOffsetX = DEFAULT_OFFSET_X,
    defaultOffsetY = 0,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    onPickFrame = PickAnchor,
}

local function IsInvalidSpellList()
    local storage = ExwindTools:GetModuleDBStorage(MODULE_KEY)
    local existing = storage and storage.ModuleDB and storage.ModuleDB[MODULE_KEY]
    return type(existing) == "table" and rawget(existing, "debuffSpellEntries") ~= nil
        and type(rawget(existing, "debuffSpellEntries")) ~= "table"
end

local function SpellEntryText(entry)
    if type(entry) ~= "table" then return tostring(entry) end
    return entry.value == nil and "" or tostring(entry.value)
end

local function CreateV2Owner(mountContext)
    local owner = { controls = {}, actions = {}, predicates = {}, sources = {}, texts = {},
        options = { anchor = ANCHOR_OPTS } }
    local records, draft, addInput = {}, "", nil
    owner.sources.spells = function()
        local current = {}
        for index, entry in ipairs(GetStoredSpellEntries(false) or {}) do
            local record = records[index]
            if not record or record.entry ~= entry then record = { entry = entry, index = index } end
            current[index] = record
        end
        records = current
        return current
    end
    owner.predicates.validList = function() return not IsInvalidSpellList() end
    owner.predicates.invalidList = IsInvalidSpellList
    owner.predicates.editableEntry = function(scope) return type(scope.item.entry) == "table" end
    owner.predicates.invalidEntry = function(scope) return type(scope.item.entry) ~= "table" end
    owner.texts.spellValue = function(scope) return SpellEntryText(scope.item.entry) end
    owner.texts.spellName = function(scope)
        local entry = scope.item.entry
        return type(entry) == "table" and GetSpellDisplay(entry.value) or L["无效记录，已保持原值"]
    end
    owner.controls.addSpell = EXUI:CreateSettingsV2Control({ controlType = "input" }, function(context)
        return {
            Read = function() return draft end,
            Write = function(_, value)
                if context:IsCurrent() then draft = value end
            end,
        }
    end)
    local mountAdd, releaseAdd = owner.controls.addSpell.mount, owner.controls.addSpell.release
    owner.controls.addSpell.mount = function(host, context)
        local widget = mountAdd(host, context)
        widget.placeholder:SetText(L["输入法术 ID"])
        addInput, spellRendererContext = widget, context
        return widget
    end
    owner.controls.addSpell.release = function(widget, context)
        if addInput == widget then addInput = nil end
        if spellRendererContext == context then spellRendererContext = nil end
        releaseAdd(widget, context)
    end
    owner.controls.spellValue = EXUI:CreateSettingsV2Control({ controlType = "input" }, function(context)
        local record = context.scope.item
        local path = "debuffSpellEntries." .. record.index
        local valueBinding = EXUI:CreateSettingsV2Binding(MODULE_KEY, mountContext.config, path .. ".value")
        local presentBinding = EXUI:CreateSettingsV2Binding(MODULE_KEY, mountContext.config, path .. ".present")
        return {
            Read = function() return SpellEntryText(record.entry) end,
            Write = function(_, value, phase)
                if not context:IsCurrent() or type(record.entry) ~= "table"
                    or value == SpellEntryText(record.entry) then return false end
                presentBinding:Write(true, "silent")
                return valueBinding:Write(value, phase)
            end,
        }
    end)
    owner.actions.addSpell = function(context)
        local target = GetStoredSpellEntries(true)
        if type(target) ~= "table" then return end
        target[#target + 1] = { present = true, value = addInput:GetText() }
        draft = ""
        EXUI:NotifyModuleValueChanged(MODULE_KEY, "debuffSpellEntries", "committed")
        context:RefreshPage()
    end
    owner.actions.deleteSpell = function(context)
        local current = GetStoredSpellEntries(false)
        if type(current) ~= "table" then return end
        table.remove(current, context.scope.item.index)
        draft = ""
        EXUI:NotifyModuleValueChanged(MODULE_KEY, "debuffSpellEntries", "committed")
        context:RefreshPage()
    end
    return owner
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local COMMON_OPTS = {
    bindRoot = true,
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用周围怪物DEBUFF监控"] },
    },
}

EXUI:RegisterModuleSettingsPageV2(MODULE_KEY, {
    version = 2,
    cards = {
        { kind = "card", id = "common", title = L["模块设置"], children = {
            { kind = "component", id = "moduleCommon", component = "modulecommonsettings",
                path = "moduleCommon", opts = COMMON_OPTS },
        } },
        { kind = "card", id = "load_conditions", title = L["加载条件"], children = {
            { kind = "control", id = "enabledSpecs", controlType = "select", path = "enabledSpecs",
                multiple = true, label = L["启用专精"], options = SPEC_OPTIONS },
        } },
        { kind = "card", id = "appearance", title = L["格子外观"], children = {
            { kind = "control", id = "cellWidth", controlType = "slider", path = "cellWidth",
                label = L["方块宽度"], min = 8, max = 100, step = 1 },
            { kind = "control", id = "cellHeight", controlType = "slider", path = "cellHeight",
                label = L["方块高度"], min = 8, max = 100, step = 1 },
            { kind = "control", id = "cellGap", controlType = "slider", path = "cellGap",
                label = L["方块间距"], min = 0, max = 30, step = 1 },
            { kind = "control", id = "cellsPerRow", controlType = "slider", path = "cellsPerRow",
                label = L["每行方块数"], min = 1, max = 20, step = 1 },
            { kind = "control", id = "noDebuffColor", controlType = "color", path = "noDebuffColor",
                label = L["没有 Debuff 时的颜色"] },
            { kind = "control", id = "debuffColor", controlType = "color", path = "debuffColor",
                label = L["有 Debuff 时的颜色"] },
        } },
        { kind = "card", id = "spells", title = L["监控法术"], children = {
            { kind = "setting", id = "invalid_spell_list", visible = "invalidList", label = L["监控法术"],
                description = L["现有法术列表不是表，已保持原值"], children = {
                    { kind = "button", id = "invalid_spell_add", text = L["添加"], action = "addSpell", enabled = "validList" },
                } },
            { kind = "setting", id = "spell_add", visible = "validList", label = L["法术 ID"],
                description = L["添加新的监控法术"], children = {
                    { kind = "control", id = "spell_add_input", controlType = "input", ref = "addSpell" },
                } },
            { kind = "table", id = "debuffSpellRecords", visible = "validList", columns = {
                { title = L["法术 ID"] }, { title = L["法术名称"] },
            }, addAction = { id = "spell_add_button", text = L["添加"], action = "addSpell" },
            rowActions = { { id = "spell_entry_delete", text = L["删除"], action = "deleteSpell",
                presentation = "danger", enabled = "editableEntry" } }, children = {
                { kind = "repeat", id = "spell_entries", source = "spells", template = {
                    kind = "row", id = "spell_entry", children = {
                        { kind = "cell", id = "spell_entry_id", children = {
                            { kind = "control", id = "spell_entry_input", controlType = "input", ref = "spellValue",
                                visible = "editableEntry" },
                            { kind = "text", id = "spell_entry_original", textSource = "spellValue", visible = "invalidEntry" },
                        } },
                        { kind = "cell", id = "spell_entry_name", children = {
                            { kind = "text", id = "spell_entry_display", textSource = "spellName" },
                        } },
                    },
                } },
            } },
        } },
        { kind = "card", id = "card.anchor", title = L["锚点设置"], children = {
            { kind = "component", id = "anchor", component = "anchorgroup", path = "anchor", optionsRef = "anchor" },
        } },
    },
}, CreateV2Owner)

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local DEFAULTS = {
    root = {
        enabled = false,
        enabledSpecs = BuildDefaultEnabledSpecs(),
        debuffSpellID = "",
        debuffSpellID2 = "",
        debuffSpellID3 = "",
        debuffSpellID4 = "",
        debuffSpellID5 = "",
        debuffSpellID6 = "",
        debuffSpellID7 = "",
        debuffSpellID8 = "",
        debuffSpellID9 = "",
        debuffSpellID10 = "",
        cellWidth = DEFAULT_CELL_WIDTH,
        cellHeight = DEFAULT_CELL_HEIGHT,
        cellGap = DEFAULT_CELL_GAP,
        cellsPerRow = DEFAULT_CELLS_PER_ROW,
        noDebuffColorR = 1,
        noDebuffColorG = 1,
        noDebuffColorB = 1,
        noDebuffColorA = 0.95,
        debuffColorR = 0.92,
        debuffColorG = 0.08,
        debuffColorB = 0.08,
        debuffColorA = 1,
        offsetX = DEFAULT_OFFSET_X,
        offsetY = 0,
        attachToCustom = false,
        customAttachTarget = "",
    },
}

ExwindTools:DeclareModuleDefaults(MODULE_KEY, DEFAULTS, {
    { group = "root", root = true, fields = {
        "enabled", "enabledSpecs", "debuffSpellID", "debuffSpellID2", "debuffSpellID3", "debuffSpellID4", "debuffSpellID5",
        "debuffSpellID6", "debuffSpellID7", "debuffSpellID8", "debuffSpellID9", "debuffSpellID10",
        "debuffSpellEntries",
        "cellWidth", "cellHeight", "cellGap", "cellsPerRow",
        "noDebuffColorR", "noDebuffColorG", "noDebuffColorB", "noDebuffColorA",
        "debuffColorR", "debuffColorG", "debuffColorB", "debuffColorA",
        "offsetX", "offsetY", "attachToCustom", "customAttachTarget",
    } },
})

do
    local storage = ExwindTools:GetModuleDBStorage(MODULE_KEY)
    local existing = storage.ModuleDB[MODULE_KEY]
    if type(existing) == "table" and rawget(existing, "debuffSpellEntries") == nil then
        local entries = {}
        for index = 1, MAX_DEBUFF_SPELL_IDS do
            local key = index == 1 and "debuffSpellID" or "debuffSpellID" .. index
            local value = rawget(existing, key)
            local entry = { present = value ~= nil }
            if value ~= nil then entry.value = value end
            entries[index] = entry
        end
        existing.debuffSpellEntries = entries
    end
end

if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

EnsureAnchor = function()
    if anchorFrame then
        return anchorFrame
    end
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(1, 1)
    return anchorFrame
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end
    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = MODULE_KEY,
        frameName = "ExwindCombatMobDebuffGridAnchor",
        title = L["周围怪物DEBUFF监控"],
        getDB = GetDB,
        offsetXKey = "offsetX",
        offsetYKey = "offsetY",
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        syncWidgets = { "offsetX", "offsetY", "attachToCustom", "customAttachTarget" },
        widgetRanges = {
            offsetX = { min = -500, max = 500, step = 1 },
            offsetY = { min = -500, max = 500, step = 1 },
        },
        initialWidth = 1,
        initialHeight = 1,
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        clampedToScreen = false,
        frameStrata = "MEDIUM",
        onCreateFrame = function(_, frame)
            frame:Hide()
        end,
        onPositionSaved = function()
            if RefreshRuntime then
                RefreshRuntime(true)
            end
        end,
    })
    return anchorController
end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function EnsureGridCell(index)
    local cell = gridCells[index]
    if cell then
        return cell
    end

    cell = _G.CreateFrame("Frame", nil, EnsureAnchor())
    cell.fill = cell:CreateTexture(nil, "BACKGROUND")
    cell.fill:SetAllPoints(cell)
    cell.fill:SetColorTexture(1, 1, 1, 0.95)
    cell:Hide()
    gridCells[index] = cell
    return cell
end

local function BuildSpellFilter(spellIDs)
    return {
        includeSpellIDs = spellIDs,
        isFromPlayerOrPlayerPet = true,
    }
end

-- CustomAuraContainer 在 initializeFrame 后会限制带秘密 Aura 的按钮访问。
-- 红格视觉只能在该创建回调中初始化，不能在名条/战斗刷新时重设。
local function ApplyAuraRecordStyle(record, settings)
    local auraFrame = record and record.auraFrame
    local redFill = auraFrame and auraFrame.CombatMobDebuffGridRedFill
    if not auraFrame or not redFill then
        return false
    end
    auraFrame:SetSize(settings.cellWidth, settings.cellHeight)
    redFill:SetVertexColor(
        settings.debuffColorR,
        settings.debuffColorG,
        settings.debuffColorB,
        settings.debuffColorA
    )
    return true
end

local function EnsureAuraRecord(unit)
    local record = auraRecordsByUnit[unit]
    if record then
        return record
    end

    local container = _G.CreateFrame("AuraContainer", nil, _G.UIParent, "CustomAuraContainerTemplate")
    record = {
        unit = unit,
        container = container,
        spellIDSignature = nil,
        visible = false,
    }
    auraRecordsByUnit[unit] = record

    container:SetUnit(unit)
    container:AddAuraSlot(AURA_SLOT_KEY, "HARMFUL", {
        templateNames = { AURA_TEMPLATE },
        candidateFilters = { includeSpellIDs = {} },
        initializeFrame = function(auraFrame)
            record.auraFrame = auraFrame
            local settings = GetGridSettings(GetDB())
            ApplyAuraRecordStyle(record, settings)
            auraFrame:ClearAllPoints()
            -- AuraButton 只锚其所属的原生 container，绝不引用普通白格 Frame。
            auraFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            if auraFrame.SetMouseMotionEnabled then
                auraFrame:SetMouseMotionEnabled(false)
            end
            EXUI:CreateAuraButtonAdapter(auraFrame):ClearIcon()
        end,
    })
    container:SetEnabled(false)
    container:Hide()
    return record
end

local function DeactivateAuraRecord(record)
    if not record or record.visible ~= true then
        if record then
            record.cell = nil
        end
        return
    end
    record.visible = false
    record.cell = nil
    record.positionX = nil
    record.positionY = nil
    record.container:SetEnabled(false)
    record.container:Hide()
    record.container:ClearAllPoints()
end

local function PlaceAuraRecord(record, cell, settings)
    local centerX, centerY = cell:GetCenter()
    if type(centerX) ~= "number" or type(centerY) ~= "number" then
        return false
    end
    -- 只读取普通白格的数值中心；不能把 AuraContainer / AuraButton 锚到该格。
    local positionX = math.floor((centerX - (settings.cellWidth / 2)) * 100 + 0.5) / 100
    local positionY = math.floor((centerY + (settings.cellHeight / 2)) * 100 + 0.5) / 100
    if record.positionX == positionX and record.positionY == positionY then
        return true
    end
    record.container:ClearAllPoints()
    record.container:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", positionX, positionY)
    record.positionX = positionX
    record.positionY = positionY
    return true
end

local function ActivateAuraRecord(record, cell, spellIDs, spellIDSignature, settings)
    if record.spellIDSignature ~= spellIDSignature then
        record.spellIDSignature = spellIDSignature
        record.container:SetAuraSlotCandidateFilters(AURA_SLOT_KEY, BuildSpellFilter(spellIDs))
    end
    record.cell = cell
    if not PlaceAuraRecord(record, cell, settings) then
        DeactivateAuraRecord(record)
        return
    end
    if record.visible ~= true then
        record.visible = true
        record.container:SetEnabled(true)
        record.container:Show()
    end
end

local function RefreshAuraPositions(settings)
    for _, record in pairs(auraRecordsByUnit) do
        if record.visible == true and record.cell then
            if not PlaceAuraRecord(record, record.cell, settings) then
                DeactivateAuraRecord(record)
            end
        end
    end
end

local function HideAllRuntimeVisuals()
    for _, cell in ipairs(gridCells) do
        cell:Hide()
    end
    for _, record in pairs(auraRecordsByUnit) do
        DeactivateAuraRecord(record)
    end
    if anchorFrame then
        anchorFrame:Hide()
    end
end

-- [卡片迁移边界：自定义渲染] 以下白格 + 原生 AuraContainer 是 Runtime/World 内容，不是设置页卡片；单位/SpellID 顺序、容器复用与刷新判定禁止修改。
local function RenderGrid(units, spellIDs, spellIDSignature, sample, settings)
    local count = sample and settings.cellsPerRow or #units
    if count <= 0 then
        HideAllRuntimeVisuals()
        return
    end

    local columns = math.min(settings.cellsPerRow, count)
    local rows = math.ceil(count / settings.cellsPerRow)
    local width = (columns * settings.cellWidth) + ((columns - 1) * settings.cellGap)
    local height = (rows * settings.cellHeight) + ((rows - 1) * settings.cellGap)
    local anchor = EnsureAnchor()
    anchor:SetSize(width, height)
    anchor:Show()

    local activeUnits = {}
    for index = 1, count do
        local cell = EnsureGridCell(index)
        local column = (index - 1) % settings.cellsPerRow
        local row = math.floor((index - 1) / settings.cellsPerRow)
        cell:SetSize(settings.cellWidth, settings.cellHeight)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", anchor, "TOPLEFT", column * (settings.cellWidth + settings.cellGap), -row * (settings.cellHeight + settings.cellGap))
        cell.fill:SetColorTexture(
            settings.noDebuffColorR,
            settings.noDebuffColorG,
            settings.noDebuffColorB,
            settings.noDebuffColorA
        )
        cell:Show()

        if not sample then
            local unit = units[index]
            activeUnits[unit] = true
            if spellIDs then
                ActivateAuraRecord(EnsureAuraRecord(unit), cell, spellIDs, spellIDSignature, settings)
            end
        end
    end

    for index = count + 1, #gridCells do
        gridCells[index]:Hide()
    end
    for unit, record in pairs(auraRecordsByUnit) do
        if not activeUnits[unit] then
            DeactivateAuraRecord(record)
        end
    end
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic — Runtime Grid Refresh / 运行网格刷新
-- =========================================================
RefreshRuntime = function(force)
    local db = GetDB()
    local settings = GetGridSettings(db)
    if worldPreviewActive then
        if force == true then
            RenderGrid({}, nil, nil, true, settings)
        end
        return
    end

    if db.enabled ~= true or not IsCurrentSpecEnabled(db) then
        lastRuntimeSignature = db.enabled == true and "spec-disabled" or "disabled"
        HideAllRuntimeVisuals()
        return
    end

    local spellIDs, spellIDSignature = CollectSpellIDs(db)
    local units = GetCombatUnits()
    -- 同一批怪物和同一组 SpellID 只更新 Aura 容器的数值位置，绝不重画格子或
    -- 反复 SetEnabled / Show 原生 AuraContainer，避免 0.10 秒刷新造成闪烁。
    local signature = BuildSignature(units, spellIDSignature, true)
    if force ~= true and signature == lastRuntimeSignature then
        RefreshAuraPositions(settings)
        return
    end
    lastRuntimeSignature = signature

    -- 未填有效 SpellID 时仍显示战斗怪物白格，但所有红色 Aura 容器保持停用。
    if not spellIDs then
        for _, record in pairs(auraRecordsByUnit) do
            DeactivateAuraRecord(record)
        end
        RenderGrid(units, nil, nil, false, settings)
        return
    end
    RenderGrid(units, spellIDs, spellIDSignature, false, settings)
end

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = function()
        lastRuntimeSignature = nil
        RefreshRuntime(true)
    end,
})

EXUI:RegisterEditableModule({
    addon = "ExwindTools",
    key = MODULE_KEY,
    name = L["周围怪物DEBUFF监控"],
    settingsPage = MODULE_KEY,
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor = EnsureAnchor,
    RenderWorld = function()
        worldPreviewActive = true
        lastRuntimeSignature = nil
        RenderGrid({}, nil, nil, true, GetGridSettings(GetDB()))
    end,
    ReleaseWorld = function()
        worldPreviewActive = false
        lastRuntimeSignature = nil
        RefreshRuntime(true)
    end,
    GetWorldBounds = function()
        local settings = GetGridSettings(GetDB())
        local width = anchorFrame and anchorFrame:GetWidth() or ((settings.cellWidth * settings.cellsPerRow) + (settings.cellGap * (settings.cellsPerRow - 1)))
        local height = anchorFrame and anchorFrame:GetHeight() or settings.cellHeight
        return { width = width, height = height, anchorOffsetX = 0, anchorOffsetY = 0 }
    end,
})

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh — Runtime Events / 运行时事件
-- =========================================================
refreshFrame = _G.CreateFrame("Frame")
refreshFrame:SetScript("OnUpdate", function(_, elapsed)
    refreshElapsed = refreshElapsed + (tonumber(elapsed) or 0)
    if refreshElapsed < REFRESH_INTERVAL then
        return
    end
    refreshElapsed = 0
    RefreshRuntime(false)
end)

ExwindTools:RegisterEvent("NAME_PLATE_UNIT_ADDED", MODULE_KEY, function()
    RefreshRuntime(true)
end)
ExwindTools:RegisterEvent("NAME_PLATE_UNIT_REMOVED", MODULE_KEY, function()
    RefreshRuntime(true)
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    lastRuntimeSignature = nil
    RefreshRuntime(true)
end)
ExwindTools:RegisterEvent("PLAYER_REGEN_DISABLED", MODULE_KEY, function()
    RefreshRuntime(true)
end)
ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", MODULE_KEY, function()
    RefreshRuntime(true)
end)
ExwindTools:WatchState("SpecID", MODULE_KEY, function()
    lastRuntimeSignature = nil
    RefreshRuntime(true)
end)

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
_G.C_Timer.After(0, function()
    EnsureAnchor()
    RefreshRuntime(true)
end)

ExwindTools:ReportReady(MODULE_KEY)
