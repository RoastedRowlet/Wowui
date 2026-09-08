-- =============================================================
-- 战斗怪物 Debuff 格子
-- 白色普通格由本模块持有；红色格只由每个 nameplate 的原生 AuraContainer
-- 在目标 Debuff 存在时显示。禁止读取 AuraButton / Aura 数据，也不监听 UNIT_AURA。
-- =============================================================

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
            string.format("|cff%s%s|r - %s", def.colorHex, L[def.className] or def.className, L[def.specName] or def.specName),
            GetSpecOptionValue(def.specID),
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
    for index = 1, MAX_DEBUFF_SPELL_IDS do
        local key = index == 1 and "debuffSpellID" or "debuffSpellID" .. index
        local spellID = ParseSpellID(db[key])
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

local COMMON_OPTS = {
    bindRoot = true,
    fixedLayout = {
        logicalWidth = 200,
        controlW = 46,
        controlH = 6,
        slotX = { 3, 53, 103, 153 },
        firstY = 0,
        rowStep = 14,
    },
    fields = {
        { path = "enabled", type = "checkbox", label = L["启用周围怪物DEBUFF监控"], row = 1 },
    },
}

ExwindTools:RegisterModuleLayout(MODULE_KEY, {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["周围怪物DEBUFF监控"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 18,
        label = L["模块设置"], opts = COMMON_OPTS },
    { key = "loadSpecHeader", type = "subheader", x = 3, y = 31, w = 194, h = 5, label = L["加载条件"] },
    { key = "enabledSpecs", type = "multiselect", x = 3, y = 39, w = 194, h = 8,
        label = L["启用专精"], items = SPEC_OPTIONS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 50, w = 200, h = 25,
        label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "appearance", type = "subheader", x = 3, y = 78, w = 194, h = 5, label = L["格子外观"] },
    { key = "cellWidth", type = "slider", x = 3, y = 86, w = 46, h = 6,
        label = L["方块宽度"], min = 8, max = 100, step = 1 },
    { key = "cellHeight", type = "slider", x = 53, y = 86, w = 46, h = 6,
        label = L["方块高度"], min = 8, max = 100, step = 1 },
    { key = "cellGap", type = "slider", x = 103, y = 86, w = 46, h = 6,
        label = L["方块间距"], min = 0, max = 30, step = 1 },
    { key = "cellsPerRow", type = "slider", x = 153, y = 86, w = 46, h = 6,
        label = L["每行方块数"], min = 1, max = 20, step = 1 },
    { key = "noDebuffColor", type = "color", x = 3, y = 100, w = 46, h = 6,
        label = L["没有 Debuff 时的颜色"] },
    { key = "debuffColor", type = "color", x = 53, y = 100, w = 46, h = 6,
        label = L["有 Debuff 时的颜色"] },
    { key = "debuffSpellID", type = "input", x = 103, y = 100, w = 46, h = 6,
        label = L["Debuff ID 1"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID2", type = "input", x = 153, y = 100, w = 46, h = 6,
        label = L["Debuff ID 2"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID3", type = "input", x = 3, y = 113, w = 46, h = 6,
        label = L["Debuff ID 3"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID4", type = "input", x = 53, y = 113, w = 46, h = 6,
        label = L["Debuff ID 4"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID5", type = "input", x = 103, y = 113, w = 46, h = 6,
        label = L["Debuff ID 5"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID6", type = "input", x = 153, y = 113, w = 46, h = 6,
        label = L["Debuff ID 6"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID7", type = "input", x = 3, y = 126, w = 46, h = 6,
        label = L["Debuff ID 7"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID8", type = "input", x = 53, y = 126, w = 46, h = 6,
        label = L["Debuff ID 8"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID9", type = "input", x = 103, y = 126, w = 46, h = 6,
        label = L["Debuff ID 9"], labelPos = "top", labelSize = 16 },
    { key = "debuffSpellID10", type = "input", x = 153, y = 126, w = 46, h = 6,
        label = L["Debuff ID 10"], labelPos = "top", labelSize = 16 },
})

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
        "cellWidth", "cellHeight", "cellGap", "cellsPerRow",
        "noDebuffColorR", "noDebuffColorG", "noDebuffColorB", "noDebuffColorA",
        "debuffColorR", "debuffColorG", "debuffColorB", "debuffColorA",
        "offsetX", "offsetY", "attachToCustom", "customAttachTarget",
    } },
})

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

_G.C_Timer.After(0, function()
    EnsureAnchor()
    RefreshRuntime(true)
end)

ExwindTools:ReportReady(MODULE_KEY)
