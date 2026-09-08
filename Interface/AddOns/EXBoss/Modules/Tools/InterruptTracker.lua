---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- EXBoss Tools: InterruptTracker
-- 显示壳以 MythicCast 的三宿主合同重建；业务只向 record 输入状态。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end
local ExBoss = _G.ExBoss
if not ExBoss then return end
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExBoss.Tools.InterruptTracker"
local EXDB, C_Spell, C_DurationUtil = _G.EXDB, _G.C_Spell, _G.C_DurationUtil
local UnitName, UnitClass = _G.UnitName, _G.UnitClass
local UnitNameFromGUID, UnitClassFromGUID, UnitTokenFromGUID = _G.UnitNameFromGUID, _G.UnitClassFromGUID, _G.UnitTokenFromGUID
local UnitExists, GetRaidTargetIndex = _G.UnitExists, _G.GetRaidTargetIndex
local GetSpecialization, GetSpecializationInfo = _G.GetSpecialization, _G.GetSpecializationInfo
local C_ClassColor, CreateColor, C_Timer = _G.C_ClassColor, _G.CreateColor, _G.C_Timer
local GROW_DIRECTION_UP, GROW_DIRECTION_DOWN = "UP", "DOWN"

ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.InterruptTracker = ExBoss.UI.InterruptTracker or {}
local Module = ExBoss.UI.InterruptTracker

local EX_DEFAULTS = {
    attachToCustom = false, customAttachTarget = "", enabled = false, locked = true,
    pos = { "CENTER", "UIParent", "CENTER", 0, -200 }, posX = 508, posY = 187, spacing = 1,
    useClassColorName = false,
    layout = { direction = GROW_DIRECTION_DOWN, spacing = 1, maxVisible = 5 },
    font_spell = {
        enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0,
        justifyH = "LEFT", justifyV = "MIDDLE", x = 8.1977938831385, y = 0, size = 16, font = "默认",
        outline = "OUTLINE", r = 1, g = 1, b = 1, a = 1,
        shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        shadowX = 1, shadowY = -1, rotation = 0, gradientEnabled = false, gradientStart = 0,
        gradientLength = 0, drawLayer = "OVERLAY", drawSubLevel = 0,
    },
    font_timer = {
        enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0,
        justifyH = "RIGHT", justifyV = "MIDDLE", x = -9.7964762479921, y = 0, size = 16, font = "默认",
        outline = "OUTLINE", r = 1, g = .9, b = .2, a = 1,
        shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        shadowX = 1, shadowY = -1, rotation = 0, gradientEnabled = false, gradientStart = 0,
        gradientLength = 0, drawLayer = "OVERLAY", drawSubLevel = 0,
    },
    font_target = { enabled = false },
    elements = { raidMarker = { texture = { enabled = true, x = -2, y = 0, width = 24, height = 24 } } },
    timerGroup = {
        width = 184, height = 25, texture = "EX_WhiteTexture",
        barColorR = .2, barColorG = .8, barColorB = .2, barColorA = 1,
        barBgColorR = .30196079611778, barBgColorG = .30196079611778,
        barBgColorB = .30196079611778, barBgColorA = .90653932094574,
        showBorder = true, borderTexture = "EX_WhiteBorder", borderColorR = .10196079313755,
        borderColorG = .10196079313755, borderColorB = .10196079313755, borderColorA = 1,
        borderSize = 1, borderPadding = 1,
        showIcon = true, iconSide = "LEFT", iconWidth = 25, iconHeight = 25, iconOffsetX = -2, iconOffsetY = 0,
        showIconBorder = true, iconBorderTexture = "EX_WhiteBorder", iconBorderColorR = 0,
        iconBorderColorG = 0, iconBorderColorB = 0, iconBorderColorA = 1, iconBorderSize = 1,
        iconBorderPadding = 0, fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
    },
}

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
-- 保持旧 ModuleDB 的真实根路径；这里只把根字段归入声明源的 module 组，
-- 编译后仍写回同名根字段，因此 V2 不迁移或改名任何用户数据。
local DEFAULT_DECLARATION = {
    module = {
        attachToCustom = EX_DEFAULTS.attachToCustom, customAttachTarget = EX_DEFAULTS.customAttachTarget,
        enabled = EX_DEFAULTS.enabled, locked = EX_DEFAULTS.locked, pos = EX_DEFAULTS.pos,
        posX = EX_DEFAULTS.posX, posY = EX_DEFAULTS.posY, spacing = EX_DEFAULTS.spacing,
        useClassColorName = EX_DEFAULTS.useClassColorName,
    },
    layout = EX_DEFAULTS.layout, font_spell = EX_DEFAULTS.font_spell, font_timer = EX_DEFAULTS.font_timer,
    font_target = EX_DEFAULTS.font_target, timerGroup = EX_DEFAULTS.timerGroup, elements = EX_DEFAULTS.elements,
}
ExwindTools:DeclareModuleDefaults(EXWIND_MODULE_KEY, DEFAULT_DECLARATION, {
    { group = "module", root = true, fields = {
        "attachToCustom", "customAttachTarget", "enabled", "locked", "pos", "posX", "posY", "spacing", "useClassColorName",
    } },
    { group = "layout", fields = { "direction", "spacing", "maxVisible" } },
    { group = "font_spell", fields = FONT_FIELDS }, { group = "font_timer", fields = FONT_FIELDS },
    { group = "font_target", fields = FONT_FIELDS }, { group = "timerGroup", fields = TIMER_FIELDS },
    { group = "elements", fields = { raidMarker = { texture = { "enabled", "x", "y", "width", "height" } } } },
})

local function GetDB() return ExwindTools:GetModuleDB(EXWIND_MODULE_KEY) end
local EX_DB = GetDB()
local anchorController, anchorFrame, runtimeCollection, worldCollection
local panelSurface, panelPreview, panelCollection, panelDock
local worldEditing = false
local playerSelfRecord, playerSelfBarOnCD, playerSelfBarDurationObject = nil, false, nil
local partyInterruptRecords, nextPartyInterruptRecordID = {}, 0
local isValidEnvironment = nil
local STANDARD_CONFIG_BINDING, STANDARD_PAGE
local GetSemanticLayout, RefreshAll, ReLayout, UpdateLayout, SyncPlayerSelfCooldownFromState
local INTERRUPT_RECORD_DURATION = 15
local INTERRUPT_RECORD_ICON = 132357

local ANCHOR_OPTS
anchorController, ANCHOR_OPTS = EXUI:CreateStandardModuleAnchor({
    moduleKey = EXWIND_MODULE_KEY, frameName = "ExBossInterruptTrackerAnchor", title = L["队友打断监控"],
    getDB = GetDB, offsetXKey = "posX", offsetYKey = "posY",
    defaultOffsetX = EX_DEFAULTS.posX, defaultOffsetY = EX_DEFAULTS.posY,
    attachEnabledKey = "attachToCustom", attachTargetKey = "customAttachTarget", restoreKeys = { "locked" },
    syncWidgets = { "posX", "posY", "attachToCustom", "customAttachTarget" },
    widgetRanges = { posX = { min = -1000, max = 1000, step = 1 }, posY = { min = -1000, max = 1000, step = 1 } },
    initialWidth = 200, initialHeight = 20, clampedToScreen = true,
    -- Direction only changes later offsets; item #1 never changes anchor.
    anchorPoint = "CENTER",
    relativePoint = "CENTER", onCreateFrame = function(_, frame) frame:Hide() end,
})

local COMMON_OPTS = { bindRoot = true, poolType = "InterruptTrackerModuleCommonSettingsGroup", columns = 3, fields = {
    { path = "enabled", type = "checkbox", label = L["启用"] },
    { path = "useClassColorName", type = "checkbox", label = L["名称使用职业颜色"] },
} }
local RAID_MARKER_EXTRA_OPTS = ExwindTools:BuildStandardTimerBarAlertIconsGroupOptions({ timerBarKey = "timerGroup" }, {
    paths = { show = "elements.raidMarker.texture.enabled", width = "elements.raidMarker.texture.width",
        height = "elements.raidMarker.texture.height", x = "elements.raidMarker.texture.x", y = "elements.raidMarker.texture.y" },
    ranges = { width = { min = 8, max = 128, step = 1 }, height = { min = 8, max = 128, step = 1 },
        x = { min = -1000, max = 1000, step = 1 }, y = { min = -1000, max = 1000, step = 1 } },
})
local LAYOUT_OPTS = { allowedDirections = { "UP", "DOWN" }, includeMaxPerRow = false, maxVisibleMin = 1, maxVisibleMax = 5, defaultMaxVisible = 5 }
local EX_LAYOUT = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["打断监控"], labelSize = 25 },
    { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 50, label = L["模块通用设置"], opts = COMMON_OPTS },
    { key = "raidMarkerExtra", type = "modulecommonsettings", x = 1, y = 62, w = 200, h = 50, label = L["额外子元素－团队标记"], opts = RAID_MARKER_EXTRA_OPTS },
    { key = "anchor", type = "anchorgroup", x = 1, y = 114, w = 200, h = 20, label = L["锚点设置"], opts = ANCHOR_OPTS },
    { key = "layout", type = "widgetlayout", x = 1, y = 136, w = 200, h = 20, measure = true, label = L["排列设置"], opts = LAYOUT_OPTS },
    { key = "timerGroup", type = "timerBarGroup", x = 1, y = 158, w = 200, h = 52, label = L["计时条外观"] },
    { key = "font_spell", type = "fontgroup", x = 1, y = 212, w = 200, h = 50, label = L["玩家名字"] },
    { key = "font_timer", type = "fontgroup", x = 1, y = 264, w = 200, h = 50, label = L["冷却时间"] },
}
ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, EX_LAYOUT)

local TIMER_SCHEMA = {
    timerBarKey = "timerGroup", layoutKey = "layout", offsetXKey = "posX", offsetYKey = "posY",
    showTextBKey = false, showTextCKey = false,
    textA = { key = "font_spell", role = "playerName", gridKey = "font_spell" },
    textB = { key = "font_target", role = "unused", gridKey = "font_target", optional = true },
    textC = { key = "font_timer", role = "time", gridKey = "font_timer" },
}
local RAID_MARKER_ELEMENT_ID = "elements.raidMarker"
local INTERACTION_SCHEMA = {
    ["core.spellName"] = { textRole = "A", movable = true, guiKey = "font_spell", tooltip = L["玩家名字"], position = { x = "font_spell.x", y = "font_spell.y" } },
    ["core.time"] = { textRole = "C", movable = true, guiKey = "font_timer", tooltip = L["冷却时间"], position = { x = "font_timer.x", y = "font_timer.y" } },
    [RAID_MARKER_ELEMENT_ID] = { movable = true, guiKey = "raidMarkerExtra", tooltip = L["团队标记"], position = { x = "elements.raidMarker.texture.x", y = "elements.raidMarker.texture.y" } },
}

GetSemanticLayout = function()
    local layout = GetDB().layout or {}
    return { direction = tostring(layout.direction or "DOWN"):upper() == "UP" and "UP" or "DOWN",
        spacing = tonumber(layout.spacing) or 0, maxVisible = math.max(1, math.min(5, math.floor(tonumber(layout.maxVisible) or 5))) }
end

local function EnsureCollection(kind, parent)
    if kind == "runtime" then
        if not runtimeCollection then runtimeCollection = EXUI:CreateStandardTimerBarCollection(parent, "runtime", EXWIND_MODULE_KEY, { schema = TIMER_SCHEMA }) end
        return runtimeCollection
    end
    if kind == "world" then
        if worldCollection then worldCollection:Release() end
        worldCollection = EXUI:CreateStandardTimerBarCollection(parent, "world", EXWIND_MODULE_KEY, { schema = TIMER_SCHEMA })
        return worldCollection
    end
    error("InterruptTracker collection kind is unsupported: " .. tostring(kind), 2)
end

local function BuildInteraction() return EXUI:BuildStandardPreviewInteraction("StandardTimerBar", GetDB, INTERACTION_SCHEMA) end
-- This is the only legacy-to-Collection display adaptation: the old business
-- stored the interrupted unit on its TimerBar and resolved its raid marker
-- while styling that bar.  Collection receives the same marker value here.
local function ResolveRaidMarkerForDisplay(record)
    if record.raidTargetUnit and GetRaidTargetIndex then return GetRaidTargetIndex(record.raidTargetUnit) end
    return record.raidMarker
end
local function BuildPresentation(record, mode)
    local db, group = GetDB(), GetDB().timerGroup or {}
    local content = record.content or { icon = record.icon, textA = record.name, textAMode = record.nameMode, textC = record.timeText,
        progress = record.progress or 1, maximum = record.maximum or 1 }
    if record.durationObject then content.durationObject = record.durationObject end
    local fillColor = CreateColor(group.barColorR or 1, group.barColorG or .7, group.barColorB or 0, group.barColorA or 1)
    local textColors = {}
    if db.useClassColorName and record.classFilename then textColors.A = C_ClassColor.GetClassColor(record.classFilename)
    elseif db.useClassColorName and record.classID and record.classID > 0 then
        local r, g, b = EXDB:GetClassColorRGB(record.classID); textColors.A = CreateColor(r, g, b, 1)
    end
    if record.classFilename then fillColor = C_ClassColor.GetClassColor(record.classFilename) or fillColor
    elseif record.classID and record.classID > 0 then
        local r, g, b = EXDB:GetClassColorRGB(record.classID)
        fillColor = CreateColor(r, g, b, 1)
    end
    local marker = db.elements and db.elements.raidMarker and db.elements.raidMarker.texture
    local markerIndex = ResolveRaidMarkerForDisplay(record)
    local markerShown = markerIndex ~= nil
    return {
        db = db, schema = TIMER_SCHEMA, content = content, fillColor = fillColor, textColors = textColors,
        regionElements = marker and {{
            id = "raidMarker", kind = "texture", stylePath = "elements.raidMarker.texture", style = marker,
            shown = marker.enabled ~= false, anchor = { point = "RIGHT", relativeElement = "core.root", relativePoint = "LEFT" },
            bounds = { width = marker.width, height = marker.height },
            content = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", shown = markerShown,
                hasRaidTargetIndex = markerShown, raidTargetIndex = markerIndex or 8 },
            interaction = { elementID = RAID_MARKER_ELEMENT_ID, guiTarget = "raidMarkerExtra", movable = true },
        }} or {}, interaction = BuildInteraction(),
    }
end

local PREVIEW_SPELLS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }
local function GetPreviewPlayerIdentity()
    local state = ExwindTools.State or {}
    local name = type(state.PlayerName) == "string" and state.PlayerName or ""
    return name ~= "" and name or L["玩家"], tonumber(state.ClassID) or 0
end
local INTERRUPT_PREVIEW_SLOT_COUNT = 5

local function BuildSampleRecords()
    local records = {}
    -- Keep the materialized preview topology equal to the legal maximum.  The
    -- layout slider only hides/reveals these existing samples, so changing it
    -- remains an in-place reapply rather than a preview rebuild.
    for index = 1, INTERRUPT_PREVIEW_SLOT_COUNT do
        local spell = C_Spell.GetSpellInfo(PREVIEW_SPELLS[((index - 1) % #PREVIEW_SPELLS) + 1])
        local playerName, classID = GetPreviewPlayerIdentity()
        records[#records + 1] = { id = "interrupt-sample:" .. index, name = playerName, classID = classID,
            icon = (spell and spell.iconID) or 132357, progress = 1, maximum = 1, timeText = "8.0", raidMarker = ((index - 1) % 8) + 1 }
    end
    return records
end
local function ApplyRecord(collection, record, mode)
    local item = collection:AcquireItem(record.id)
    record.item = item
    -- StandardTimerBar does not clear a previous native Duration merely because
    -- the next content payload is static progress.  The legacy ready branch
    -- explicitly called ClearTime(), so preserve that exact display boundary.
    if record.clearTime == true and item.widget and item.widget.ClearTime then
        item.widget:ClearTime()
    end
    collection:ApplyItem(item, BuildPresentation(record, mode))
    return item
end
local function RenderSampleCollection(collection)
    local records, items = BuildSampleRecords(), {}
    for _, record in ipairs(records) do items[#items + 1] = ApplyRecord(collection, record, collection.interactionMode) end
    collection:SetItems(items, GetSemanticLayout())
end
local function BuildPanelPresentation(_, mode)
    if mode ~= "panel" then error("InterruptTracker panel surface only accepts panel mode", 2) end
    local entries = {}
    for _, record in ipairs(BuildSampleRecords()) do entries[#entries + 1] = { itemID = record.id, presentation = BuildPresentation(record, "panel") } end
    return { entries = entries, layout = GetSemanticLayout() }
end

local function CreateAnchor()
    if anchorFrame then return anchorFrame end
    anchorFrame = anchorController:Ensure()
    return anchorFrame
end
local function GetPlayerInterruptData()
    local index = GetSpecialization()
    if not index or index <= 0 then return nil end
    local specID = GetSpecializationInfo(index)
    local data = specID and EXDB.InterruptData and EXDB.InterruptData[specID]
    return data and data.id ~= 0 and data or nil
end
local function ReleasePlayerSelfBar()
    if runtimeCollection and playerSelfRecord then runtimeCollection:ReleaseItem(playerSelfRecord.id) end
    playerSelfRecord, playerSelfBarOnCD, playerSelfBarDurationObject = nil, false, nil
end
local function ClearPartyInterruptRecords()
    if runtimeCollection then
        for _, record in ipairs(partyInterruptRecords) do runtimeCollection:ReleaseItem(record.id) end
    end
    partyInterruptRecords = {}
end
local function RefreshPlayerSelfBar()
    if not anchorFrame then return end
    local data = GetPlayerInterruptData()
    if not data then ReleasePlayerSelfBar(); return end
    local _, classFilename = UnitClass("player")
    local spell = C_Spell.GetSpellInfo(data.id)
    playerSelfRecord = playerSelfRecord or { id = "interrupt:self" }
    local record = playerSelfRecord
    record.name, record.nameMode, record.classFilename = UnitName("player"), "SECRET", classFilename
    record.icon = spell and spell.iconID or INTERRUPT_RECORD_ICON
    record.content = { icon = record.icon, textA = record.name, textAMode = "SECRET" }
    if playerSelfBarOnCD and playerSelfBarDurationObject then
        record.clearTime = false
        record.content.durationObject = playerSelfBarDurationObject
    else
        -- The July business layer keeps the player's interrupt row visible
        -- when ready.  It clears timing state rather than rendering a zero.
        record.clearTime = true
        record.content.progress, record.content.maximum = 1, 1
    end
    ApplyRecord(EnsureCollection("runtime", CreateAnchor()), record, "runtime")
end

local function CheckEnvironment()
    local state = ExwindTools.State or {}
    local valid = state.IsInParty == true and state.InstanceType == "party"
    if valid ~= isValidEnvironment then
        isValidEnvironment = valid
        if not valid then
            if anchorFrame then anchorFrame:Hide(); anchorFrame:EnableMouse(false) end
            if runtimeCollection then runtimeCollection:SetItems({}, GetSemanticLayout()) end
            ReleasePlayerSelfBar()
            ClearPartyInterruptRecords()
        end
    end
    return valid
end
ReLayout = function()
    if not anchorFrame or worldEditing then return end
    if not EX_DB.enabled or not isValidEnvironment then anchorFrame:Hide(); if runtimeCollection then runtimeCollection:SetItems({}, GetSemanticLayout()) end; return end
    local collection = EnsureCollection("runtime", anchorFrame)
    local items = {}
    if playerSelfRecord then items[1] = ApplyRecord(collection, playerSelfRecord, "runtime") end
    local sortedRecords = {}
    for _, record in ipairs(partyInterruptRecords) do sortedRecords[#sortedRecords + 1] = record end
    table.sort(sortedRecords, function(a, b)
        if a.startTime ~= b.startTime then return a.startTime > b.startTime end
        if a.expireTime ~= b.expireTime then return a.expireTime > b.expireTime end
        return a.legacyRecordID > b.legacyRecordID
    end)
    for _, record in ipairs(sortedRecords) do
        items[#items + 1] = ApplyRecord(collection, record, "runtime")
    end
    collection:SetItems(items, GetSemanticLayout())
    anchorFrame:SetSize((EX_DB.timerGroup or {}).width or 200, (EX_DB.timerGroup or {}).height or 25)
    anchorController:ApplyPosition()
end
RefreshAll = function(options)
    if worldEditing then if worldCollection then RenderSampleCollection(worldCollection) end else ReLayout() end
    if options == nil or options.rebuildPanelPreview == true then Module:RefreshPanelPreview() end
end
UpdateLayout = function()
    if worldEditing then return end
    if not CheckEnvironment() then return end
    if not EX_DB.enabled then
        if anchorFrame then anchorFrame:Hide() end
        return
    end
    CreateAnchor():Show(); RefreshPlayerSelfBar(); ReLayout()
end
SyncPlayerSelfCooldownFromState = function()
    local state = ExwindTools.State or {}
    local startTime, duration = tonumber(state.InterruptStartTime) or 0, tonumber(state.InterruptDuration) or 0
    if state.InterruptReady == false and startTime > 0 and duration > 0 then
        if not C_DurationUtil or type(C_DurationUtil.CreateDuration) ~= "function" then
            error("InterruptTracker requires C_DurationUtil.CreateDuration for ordinary cooldown", 2)
        end
        playerSelfBarOnCD = true
        playerSelfBarDurationObject = C_DurationUtil.CreateDuration()
        playerSelfBarDurationObject:SetTimeFromEnd(startTime + duration, duration, 1)
    else
        playerSelfBarOnCD, playerSelfBarDurationObject = false, nil
    end
    if EX_DB.enabled and not worldEditing and isValidEnvironment then RefreshPlayerSelfBar(); ReLayout() end
end

local function IsTrackedNameplateUnit(unit)
    if type(unit) ~= "string" then return false end
    local index = string.match(unit, "^nameplate(%d+)$")
    if not index then return false end
    index = tonumber(index)
    return index ~= nil and index >= 1 and index <= 40
end

-- July 31 legacy business layer.  Do not add policy or fallback branches in
-- this section; only the old TimerBar write is replaced by the Collection
-- output record immediately below it.
local function RemovePartyInterruptRecord(recordID)
    for index, record in ipairs(partyInterruptRecords) do
        if record.id == recordID then
            table.remove(partyInterruptRecords, index)
            if runtimeCollection then runtimeCollection:ReleaseItem(recordID) end
            ReLayout()
            return
        end
    end
end
local function AddInterruptRecord(interruptedBy, interruptedUnit, resolvedUnit, spellID)
    if interruptedBy == nil then
        return false, "missing_interruptedBy"
    end

    local displayName, classFilename
    if resolvedUnit and UnitExists(resolvedUnit) then
        displayName = UnitName(resolvedUnit)
        local _, classFile = UnitClass(resolvedUnit)
        classFilename = classFile
    else
        displayName = UnitNameFromGUID(interruptedBy)
        local _, classFile = UnitClassFromGUID(interruptedBy)
        classFilename = classFile
    end

    local iconTexture = C_Spell.GetSpellTexture(spellID)

    if not C_DurationUtil or type(C_DurationUtil.CreateDuration) ~= "function" then
        error("InterruptTracker requires C_DurationUtil.CreateDuration for party interrupt records", 2)
    end
    nextPartyInterruptRecordID = nextPartyInterruptRecordID + 1
    local recordID = "interrupt:party:" .. nextPartyInterruptRecordID
    local startTime = _G.GetTime()
    local expireTime = startTime + INTERRUPT_RECORD_DURATION
    local durationObject = C_DurationUtil.CreateDuration()
    durationObject:SetTimeFromEnd(expireTime, INTERRUPT_RECORD_DURATION, 1)

    -- Legacy TimerBar output -> current Collection output adapter.
    partyInterruptRecords[#partyInterruptRecords + 1] = {
        id = recordID, legacyRecordID = nextPartyInterruptRecordID,
        name = displayName, nameMode = "SECRET", classFilename = classFilename,
        icon = iconTexture, raidTargetUnit = interruptedUnit,
        startTime = startTime, expireTime = expireTime, duration = INTERRUPT_RECORD_DURATION,
        content = { icon = iconTexture, iconMode = "SECRET", textA = displayName, textAMode = "SECRET", durationObject = durationObject },
    }
    ReLayout()
    C_Timer.After(INTERRUPT_RECORD_DURATION, function() RemovePartyInterruptRecord(recordID) end)
    return true, "ok"
end

local function HandleInterruptEvent(eventName, unit, spellID, interruptedBy, castBarID)
    local interruptedByIsNil = (interruptedBy == nil)
    if not EX_DB.enabled then return end
    if worldEditing then return end
    if not isValidEnvironment then return end
    if not IsTrackedNameplateUnit(unit) then return end
    if interruptedBy == nil then return end

    local interrupterToken = UnitTokenFromGUID(interruptedBy)
    if interrupterToken == nil then
        AddInterruptRecord(interruptedBy, unit, nil, spellID)
    end
end

function Module:RenderWorld(host)
    CreateAnchor(); worldEditing = true; anchorFrame:Show()
    if runtimeCollection then runtimeCollection:SetItems({}, GetSemanticLayout()) end
    RenderSampleCollection(EnsureCollection("world", host))
end
function Module:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false; ReLayout()
end
function Module:GetWorldBounds() return worldCollection and worldCollection:GetWorldBounds() or nil end
local function ResizePanelDock()
    if not panelDock or not panelCollection then return end
    local _, height = panelCollection:GetBounds()
    panelDock:SetHeight(math.max(60, (height or 0) + 28))
end

function Module:ShowPanelPreview(dock)
    if not dock then return end
    panelDock = dock
    panelPreview = panelSurface:Render({ dock = dock, ruleKey = EXWIND_MODULE_KEY, state = true })
    panelCollection = panelPreview:GetCollection()
    ResizePanelDock()
end
function Module:RefreshPanelPreview()
    if not panelPreview or not panelDock then return end
    self:ShowPanelPreview(panelDock)
end
function Module:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview, panelCollection, panelDock = nil, nil, nil
end
function Module:GetModuleDB() return GetDB() end
function Module:RefreshVisuals(options) RefreshAll(options) end
function Module:StartFramePicker() return anchorController:StartFramePicker() end
function Module:Clear()
    if runtimeCollection then runtimeCollection:SetItems({}, GetSemanticLayout()) end
    ReleasePlayerSelfBar()
    ClearPartyInterruptRecords()
end
function Module:Shutdown()
    self:Clear()
    ExwindTools:UnwatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY)
    ExwindTools:UnwatchState("InterruptStartTime", EXWIND_MODULE_KEY .. "_PlayerInterruptState")
    ExwindTools:UnwatchState("InterruptDuration", EXWIND_MODULE_KEY .. "_PlayerInterruptState")
    ExwindTools:UnwatchState("InterruptReady", EXWIND_MODULE_KEY .. "_PlayerInterruptState")
    ExwindTools:UnwatchState("IsInParty", EXWIND_MODULE_KEY .. "_PartyWatch")
    ExwindTools:UnwatchState("InstanceType", EXWIND_MODULE_KEY .. "_InstanceWatch")
    ExwindTools:UnwatchState("SpecID", EXWIND_MODULE_KEY .. "_PlayerSpec")
    ExwindTools:UnregisterEvent("EX_PARTY_SPEC_UPDATED", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("GROUP_ROSTER_UPDATE", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY)
    ExwindTools:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED", EXWIND_MODULE_KEY .. "_PartyInterrupt")
    ExwindTools:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", EXWIND_MODULE_KEY .. "_PartyInterruptChannel")
end

local STANDARD_SCHEMA_PATHS = { posX = true, posY = true, attachToCustom = true, customAttachTarget = true }
for _, prefix in ipairs({ "font_spell", "font_timer", "font_target" }) do
    for _, field in ipairs(FONT_FIELDS) do STANDARD_SCHEMA_PATHS[prefix .. "." .. field] = true end
end
for _, field in ipairs(TIMER_FIELDS) do STANDARD_SCHEMA_PATHS["timerGroup." .. field] = true end
for _, field in ipairs({ "enabled", "x", "y", "width", "height" }) do STANDARD_SCHEMA_PATHS["elements.raidMarker.texture." .. field] = true end
for _, field in ipairs({ "direction", "spacing", "maxVisible" }) do STANDARD_SCHEMA_PATHS["layout." .. field] = true end

STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = EXWIND_MODULE_KEY, getConfig = GetDB, schemaPaths = STANDARD_SCHEMA_PATHS,
    reapplyExisting = function()
        local function replace(target, source) for key in pairs(target) do target[key] = nil end; for key, value in pairs(source or {}) do target[key] = value end end
        local samples, runtime = {}, {}; for _, record in ipairs(BuildSampleRecords()) do samples[record.id] = record end
        if playerSelfRecord then runtime[playerSelfRecord.id] = playerSelfRecord end
        for _, record in ipairs(partyInterruptRecords) do runtime[record.id] = record end
        local function reapply(collection, resolve)
            if collection and collection.ReapplyCurrentItems then collection:ReapplyCurrentItems(function(presentation, item)
                local nextPresentation = resolve(item and item.id); if nextPresentation then replace(presentation, nextPresentation) end
            end, { reapplyLayout = false }) end
            if collection and collection.ReapplyCurrentLayout then collection:ReapplyCurrentLayout(GetSemanticLayout()) end
        end
        reapply(panelCollection, function(id) return samples[id] and BuildPresentation(samples[id], "panel") end)
        -- ReapplyCurrentLayout changes the collection bounds in place.  Keep
        -- the host dock in sync during slider changing as well as committed.
        ResizePanelDock()
        reapply(worldCollection, function(id) return samples[id] and BuildPresentation(samples[id], "world") end)
        reapply(runtimeCollection, function(id) return runtime[id] and BuildPresentation(runtime[id], "runtime") end)
    end,
})
EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = function(_, _, phase) return STANDARD_CONFIG_BINDING.reapplyExisting(phase) end })

panelSurface = EXUI:CreateStandardPreviewSurface({
    moduleKey = EXWIND_MODULE_KEY, kind = "timerbar", binding = STANDARD_CONFIG_BINDING,
    collectionOptions = { schema = TIMER_SCHEMA, contentCenter = true }, buildPresentation = BuildPanelPresentation,
    interactionSchema = INTERACTION_SCHEMA, requiredPositionGuiKeys = { "font_spell", "font_timer", "raidMarkerExtra" },
})
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss", key = "interrupttracker", name = L["队友打断监控"], settingsPage = "interrupttracker",
    appearanceProfile = "basicTimerBar", orientation = "HORIZONTAL", worldAnchorMode = "semantic-root", editOverlay = { titleFontSize = 28 },
    getAnchor = CreateAnchor, RenderWorld = function(host) return Module:RenderWorld(host) end,
    ReleaseWorld = function() return Module:ReleaseWorld() end, GetWorldBounds = function() return Module:GetWorldBounds() end,
})

ExBoss.ResetModuleConfig = ExBoss.ResetModuleConfig or {}
ExBoss.ResetModuleConfig[EXWIND_MODULE_KEY] = function()
    local moduleDB = _G.EXBOSS12S2 and _G.EXBOSS12S2.ModuleDB
    if not moduleDB then return end
    moduleDB[EXWIND_MODULE_KEY] = nil; EX_DB = GetDB(); EXUI:NotifyModuleValueChanged(EXWIND_MODULE_KEY, "*", "committed")
end
ExBoss.UI.Panel = ExBoss.UI.Panel or {}; ExBoss.UI.Panel.InterruptTrackerPage = ExBoss.UI.Panel.InterruptTrackerPage or {}
local GUIPage = ExBoss.UI.Panel.InterruptTrackerPage
STANDARD_PAGE = EXUI:CreateStandardModulePage({
    moduleKey = EXWIND_MODULE_KEY, page = GUIPage, binding = STANDARD_CONFIG_BINDING, layout = EX_LAYOUT, getColumns = 200,
    preview = { height = 172, render = function(dock) Module:ShowPanelPreview(dock) end,
        refresh = function() Module:RefreshPanelPreview() end, release = function() Module:ReleasePanelPreview() end },
    applyScrollSkin = function(scrollFrame) if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame) end end,
    sliderContract = function() return { groupPaths = { raidMarkerExtra = "", layout = "layout", timerGroup = "timerGroup", font_spell = "font_spell", font_timer = "font_timer" } } end,
})
function GUIPage:Render(contentFrame) return STANDARD_PAGE:Render(contentFrame) end
function GUIPage:Hide() return STANDARD_PAGE:Hide() end

-- 原业务状态入口保持原 key 与 State 名称；它们只更新 runtime record，不拥有任何显示树。
ExwindTools:WatchState("InterruptStartTime", EXWIND_MODULE_KEY .. "_PlayerInterruptState", SyncPlayerSelfCooldownFromState)
ExwindTools:WatchState("InterruptDuration", EXWIND_MODULE_KEY .. "_PlayerInterruptState", SyncPlayerSelfCooldownFromState)
ExwindTools:WatchState("InterruptReady", EXWIND_MODULE_KEY .. "_PlayerInterruptState", SyncPlayerSelfCooldownFromState)
ExwindTools:WatchState("IsInParty", EXWIND_MODULE_KEY .. "_PartyWatch", function() CheckEnvironment(); UpdateLayout() end)
ExwindTools:WatchState("InstanceType", EXWIND_MODULE_KEY .. "_InstanceWatch", function() CheckEnvironment(); UpdateLayout() end)
ExwindTools:WatchState("SpecID", EXWIND_MODULE_KEY .. "_PlayerSpec", function() playerSelfBarOnCD = false; RefreshPlayerSelfBar(); UpdateLayout() end)
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if not info then return end
    if info.key == "btn_reset_pos" then
        EX_DB.posX, EX_DB.posY = 0, -200
        anchorController:SyncWidgets()
        if anchorFrame then anchorController:ApplyPosition() end
        RefreshAll()
    elseif info.key == "btn_pick_frame" then
        anchorController:StartFramePicker()
    end
end)
ExwindTools:RegisterEvent("EX_PARTY_SPEC_UPDATED", EXWIND_MODULE_KEY, UpdateLayout)
ExwindTools:RegisterEvent("GROUP_ROSTER_UPDATE", EXWIND_MODULE_KEY, UpdateLayout)
ExwindTools:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", EXWIND_MODULE_KEY .. "_PartyInterrupt", function(_, unit, castGUID, spellID, interruptedBy, castBarID)
    HandleInterruptEvent("UNIT_SPELLCAST_INTERRUPTED", unit, spellID, interruptedBy, castBarID)
end)
ExwindTools:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", EXWIND_MODULE_KEY .. "_PartyInterruptChannel", function(_, unit, castGUID, spellID, interruptedBy, castBarID)
    HandleInterruptEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit, spellID, interruptedBy, castBarID)
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function() C_Timer.After(1, function() CreateAnchor(); CheckEnvironment(); SyncPlayerSelfCooldownFromState(); UpdateLayout() end) end)
C_Timer.After(0, function() CreateAnchor(); CheckEnvironment(); SyncPlayerSelfCooldownFromState(); UpdateLayout() end)
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
