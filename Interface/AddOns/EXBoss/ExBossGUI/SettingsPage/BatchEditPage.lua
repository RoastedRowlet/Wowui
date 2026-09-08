---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI

ExBoss.UI.Panel.BatchEditPage = ExBoss.UI.Panel.BatchEditPage or {}
local Page = ExBoss.UI.Panel.BatchEditPage
local TrashStore = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
local TrashData = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Data or nil

local MODULE_KEY = "ExBoss.BatchEdit"
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })
local BASE_GRID_COLS = 200
local MATCH_TEXT_ITEMS_FUNC = "func:ExBoss.UI.Panel.BatchEditPage.GetPreAlertTextDropdownItems"
local MATCH_VOICE_ITEMS_FUNC = "func:ExBoss.UI.Panel.BatchEditPage.GetVoiceMatchDropdownItems"
local LABEL_ITEMS_FUNC = "func:ExBoss.Voice.LabelCatalog.GetDropdownItems"

local function T(key)
    local v = L[key]
    if type(v) == "string" and v ~= "" then
        return v
    end
    return key
end

local THEME = {
    panel = { 0.055, 0.065, 0.090, 0.96 },
    panel2 = { 0.040, 0.048, 0.070, 0.96 },
    line = { 0.26, 0.30, 0.36, 0.78 },
    gold = { 1.00, 0.82, 0.35, 1 },
    cyan = { 0.36, 0.82, 1.00, 1 },
    text = { 0.88, 0.90, 0.94, 1 },
}

local function Font(fs, size, color, flags)
    local font = (ExwindTools and ExwindTools.MAIN_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(font, size or 14, flags or "")
    local c = color or THEME.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function CreateCardFrame(parent, accentColor, titleText, bgColor)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local bg = bgColor or THEME.panel
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(THEME.line[1], THEME.line[2], THEME.line[3], THEME.line[4])

    frame.accent = EXUI:CreateVisualTexture(frame, EXBORDERFRAME)
    frame.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.accent:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 0.95)
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.accent:SetHeight(2)

    frame.title = EXUI:CreateVisualFontString(frame, EXFONTFRAME)
    Font(frame.title, 18, accentColor, "OUTLINE")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -10)
    frame.title:SetText(titleText or "")
    return frame
end

local DEFAULTS = {
    scope = "allMplus",
    targetFilter = "allEvents",
    field1 = "preAlertEnabled",
    action1 = "enable",
    matchText = "",
    replaceText = "",
    matchVoice = "",
    voiceSource = "pack",
    voiceLabel = "",
    voiceLSM = "",
    voicePath = "",
    voiceTtsText = "",
    taEnabled = false,
    taRingEnabled = false,
    taIconEnabled = false,
    taTextEnabled = false,
    taStealthEnabled = false,
    taLSM = "",
}

local FIELD_ITEMS = {
    { T("[启用/禁用] 启用"), "enabled" },
    { T("[启用/禁用] 中央文本"), "centralEnabled" },
    { T("[启用/禁用] 提前5秒"), "preAlertEnabled" },
    { T("[启用/禁用] 计时条改名"), "timerBarRenameEnabled" },
    { T("[启用/禁用] 中央警告语音"), "trigger0" },
    { T("[启用/禁用] 施法开始语音"), "trigger1" },
    { T("[启用/禁用] 提前5秒语音"), "trigger2" },
    { T("[启用/禁用] BOSS施法时显示圆环"), "ringEnabled" },
    { T("[启用/禁用] 颜色覆盖"), "eventColorCombined" },
    { T("[文本替换] 倒数文本"), "preAlertTextReplace" },
    { T("[文本替换] 中央文本"), "centralTextReplace" },
    { T("[文本替换] 计时条改名"), "timerBarRenameTextReplace" },
    { T("[语音替换] 中央警告语音"), "trigger0VoiceReplace" },
    { T("[语音替换] 施法开始语音"), "trigger1VoiceReplace" },
    { T("[语音替换] 提前5秒语音"), "trigger2VoiceReplace" },
    { T("[被点名提示] 整体配置"), "targetAlertConfig" },
}


local ACTION_ITEMS = {
    { T("启用"), "enable" },
    { T("禁用"), "disable" },
}

local SCOPE_ITEMS = {
    { T("全部大秘境BOSS"), "allMplus" },
    { T("全部小怪法术"), "allTrash" },
}

local FILTER_ITEMS = {
    { T("全部事件"), "allEvents" },
    { T("仅当前已启用"), "enabledOnly" },
    { T("仅当前已禁用"), "disabledOnly" },
}

local VOICE_SOURCE_ITEMS = {
    { T("语音包标签"), "pack" },
    { T("LSM音效"), "lsm" },
    { T("自定义路径"), "file" },
    { T("TTS语音"), "tts" },
}

local TRASH_VOICE_SOURCE_ITEMS = {
    { T("语音包标签"), "pack" },
    { T("LSM音效"), "lsm" },
    { T("自定义路径"), "file" },
}


local LAYOUT = {
    { key = "scope", type = "dropdown", x = 4, y = 17, w = 57, h = 6, label = T("作用范围"), items = SCOPE_ITEMS },
    { key = "targetFilter", type = "dropdown", x = 68, y = 17, w = 57, h = 6, label = T("目标筛选"), items = FILTER_ITEMS },
    { key = "field1", type = "dropdown", x = 131, y = 17, w = 60, h = 6, label = T("批量动作"), items = FIELD_ITEMS },
    { key = "matchText", type = "dropdown", x = 4, y = 49, w = 89, h = 6, label = T("匹配文本"), items = MATCH_TEXT_ITEMS_FUNC },
    { key = "matchVoice", type = "dropdown", x = 4, y = 49, w = 184, h = 6, label = T("匹配语音"), items = MATCH_VOICE_ITEMS_FUNC },
    { key = "action1", type = "dropdown", x = 4, y = 71, w = 51, h = 6, label = T("操作"), items = ACTION_ITEMS },
    { key = "replaceText", type = "input", x = 4, y = 84, w = 184, h = 6, label = T("替换为") },
    { key = "voiceSource", type = "dropdown", x = 4, y = 71, w = 44, h = 6, label = T("替换来源"), items = VOICE_SOURCE_ITEMS },
    { key = "voiceLabel", type = "dropdown", x = 55, y = 71, w = 76, h = 6, label = T("语音标签"), items = LABEL_ITEMS_FUNC },
    { key = "voiceLSM", type = "lsm_sound", x = 55, y = 71, w = 76, h = 6, label = T("LSM音效") },
    { key = "voicePath", type = "input", x = 55, y = 71, w = 133, h = 6, label = T("文件路径") },
    { key = "voiceTtsText", type = "input", x = 55, y = 71, w = 133, h = 6, label = T("TTS文本") },
    { key = "btn_preview", type = "button", x = 4, y = 99, w = 44, h = 6, label = T("生成预览") },
    { key = "btn_apply", type = "button", x = 55, y = 99, w = 44, h = 6, label = T("确认应用") },
    { key = "previewText", type = "description", x = 4, y = 109, w = 187, h = 6, label = "" },
    { key = "taEnabled",        type = "checkbox",  x = 4,  y = 71, w = 44, h = 6, label = T("被点名提示") },
    { key = "taLSM",            type = "lsm_sound", x = 55, y = 71, w = 95, h = 6, label = T("音效"), search = true },
    { key = "taValueTest",      type = "button",    x = 157, y = 71, w = 29,  h = 6, label = T("试听") },
    { key = "taRingEnabled",    type = "checkbox",  x = 4,  y = 84, w = 32, h = 6, label = T("圆环") },
    { key = "taIconEnabled",    type = "checkbox",  x = 42, y = 84, w = 32, h = 6, label = T("图标") },
    { key = "taTextEnabled",    type = "checkbox",  x = 80, y = 84, w = 32, h = 6, label = T("文本") },
    { key = "taStealthEnabled", type = "checkbox",  x = 118, y = 84, w = 44, h = 6, label = T("隐遁提示") },
}

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = DeepCopy(x)
    end
    return out
end

local function NormalizeText(v)
    if type(v) ~= "string" then
        return ""
    end
    return v:gsub("^%s+", ""):gsub("%s+$", "")
end

local function LocalizeDynamicText(text)
    local normalized = NormalizeText(text)
    if normalized == "" then
        return ""
    end
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        local ok, localized = pcall(ExBoss.Locale.TranslateBossDynamicText, normalized)
        if ok and type(localized) == "string" then
            return NormalizeText(localized)
        end
    end
    return normalized
end

local function IsTextReplaceField(field)
    return field == "preAlertTextReplace"
        or field == "centralTextReplace"
        or field == "timerBarRenameTextReplace"
end

local function IsVoiceReplaceField(field)
    return field == "trigger0VoiceReplace"
        or field == "trigger1VoiceReplace"
        or field == "trigger2VoiceReplace"

end

local function IsTargetAlertConfigField(field)
    return field == "targetAlertConfig"
end

local function IsBossTargetAlertSupported(eventID)
    local ids = ExBoss and ExBoss.TargetAlert and ExBoss.TargetAlert.SupportedBossEventIDs
    return type(ids) == "table" and ids[tonumber(eventID)] == true
end

local function IsTrashTargetAlertSupported(spellID)
    local ids = ExBoss and ExBoss.TargetAlert and ExBoss.TargetAlert.SupportedTrashSpellIDs
    return type(ids) == "table" and ids[tonumber(spellID)] == true
end

local function PlayTargetAlertLSMPreview(lsmName)
    lsmName = NormalizeText(lsmName)
    if lsmName == "" then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = LSM and LSM:Fetch("sound", lsmName) or lsmName
    if path and path ~= "" then
        PlaySoundFile(path, "Master")
    end
end

local function GetVoiceReplaceTriggerIndex(field)
    if field == "trigger0VoiceReplace" then
        return 0
    end
    if field == "trigger1VoiceReplace" then
        return 1
    end
    if field == "trigger2VoiceReplace" then
        return 2
    end
    return nil
end

local function NormalizeVoiceSource(v)
    local s = tostring(v or ""):lower()
    if s == "lsm" or s == "file" or s == "tts" then
        return s
    end
    return "pack"
end

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function GetRuntimeEvent(eventID)
    local runtime = ExBoss and ExBoss.RuntimeMplus
    return type(runtime) == "table" and type(runtime.events) == "table" and runtime.events[tonumber(eventID)] or nil
end

local function GetEncounterDataSource()
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetEncounterDataRoot) == "function" then
        local ok, root = pcall(api.GetEncounterDataRoot)
        if ok and type(root) == "table" then
            return root
        end
    end
    local raw = _G.EXBOSS_ENCOUNTER_DATA
    if type(raw) == "table" and type(raw.maps) == "table" then
        return raw.maps
    end
    return raw
end

local _indexCache
local _indexSource
local _trashIndexCache
local _trashIndexSource

local function NormalizeBossEvents(events)
    local out = {}
    if type(events) ~= "table" then
        return out
    end
    for eventKey, eventRow in pairs(events) do
        if type(eventRow) == "table" then
            local eid = tonumber(eventRow.eventID) or tonumber(eventKey)
            if eid then
                local row = DeepCopy(eventRow)
                row.eventID = eid
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(a, b)
        local af = tonumber(a.firstSeenSec)
        local bf = tonumber(b.firstSeenSec)
        if af ~= nil or bf ~= nil then
            if af == nil then return false end
            if bf == nil then return true end
            if af ~= bf then return af < bf end
        end
        return (tonumber(a.eventID) or 0) < (tonumber(b.eventID) or 0)
    end)
    return out
end

local function GetSceneByMap(mapRow)
    local instanceType = tonumber(type(mapRow) == "table" and mapRow.instanceType or nil)
    if instanceType == 2 then
        return "raid"
    end
    local category = tostring(type(mapRow) == "table" and mapRow.category or "")
    if category:find("团") then
        return "raid"
    end
    return "mplus"
end

local function BuildEncounterIndex()
    local source = GetEncounterDataSource()
    if _indexCache and _indexSource == source then
        return _indexCache
    end

    local out = {
        maps = {},
        encounters = {},
        events = {},
    }

    for rawMapID, mapRow in pairs(source or {}) do
        if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
            local mapID = tonumber(mapRow.mapID) or tonumber(rawMapID)
            if mapID then
                local mapName = tostring(mapRow.mapName or mapRow.name or (T("副本 ") .. tostring(mapID)))
                local scene = GetSceneByMap(mapRow)
                local mapInfo = {
                    mapID = mapID,
                    name = mapName,
                    scene = scene,
                    encounterIDs = {},
                }
                out.maps[mapID] = mapInfo

                for bossKey, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" then
                        local encounterID = tonumber(bossRow.encounterID) or tonumber(bossKey)
                        if encounterID then
                            local bossName = tostring(bossRow.name or bossRow.bossName or (T("首领 ") .. tostring(encounterID)))
                            local eventRows = NormalizeBossEvents(bossRow.events)
                            local encounterInfo = {
                                encounterID = encounterID,
                                bossName = bossName,
                                mapID = mapID,
                                mapName = mapName,
                                scene = scene,
                                eventIDs = {},
                            }
                            out.encounters[encounterID] = encounterInfo
                            mapInfo.encounterIDs[#mapInfo.encounterIDs + 1] = encounterID

                            for _, eventRow in ipairs(eventRows) do
                                local eventID = tonumber(eventRow.eventID)
                                if eventID then
                                    encounterInfo.eventIDs[#encounterInfo.eventIDs + 1] = eventID
                                    out.events[eventID] = {
                                        eventID = eventID,
                                        eventName = tostring(eventRow.name or eventRow.eventName or (T("事件 ") .. tostring(eventID))),
                                        encounterID = encounterID,
                                        bossName = bossName,
                                        mapID = mapID,
                                        mapName = mapName,
                                        scene = scene,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    _indexCache = out
    _indexSource = source
    return out
end

local function GetRunningEncounterID()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if type(sched) == "table" and sched._running and tonumber(sched._encounterID) then
        return tonumber(sched._encounterID)
    end
    return nil
end

local function GetScopeEventIDs(scopeKey)
    local index = BuildEncounterIndex()
    local out = {}
    local seen = {}

    local function AddEncounter(encounterID)
        local row = index.encounters[tonumber(encounterID)]
        if not row or type(row.eventIDs) ~= "table" then
            return
        end
        for _, eventID in ipairs(row.eventIDs) do
            local eid = tonumber(eventID)
            if eid and not seen[eid] then
                seen[eid] = true
                out[#out + 1] = eid
            end
        end
    end

    for encounterID, row in pairs(index.encounters) do
        if row.scene == "mplus" then
            AddEncounter(encounterID)
        end
    end

    table.sort(out)
    return out
end

local function IsEventEnabled(eventID)
    local row = GetRuntimeEvent(eventID)
    if type(row) ~= "table" then
        return true
    end
    return row.enabled ~= false
end

local function IsTrashScope(scopeKey)
    return tostring(scopeKey or "") == "allTrash"
end

local function GetFieldItemsForScope(scopeKey)
    return FIELD_ITEMS
end

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function GetTrashCDDataSource()
    if TrashData and type(TrashData.GetTrashCDDataRoot) == "function" then
        local ok, root = pcall(TrashData.GetTrashCDDataRoot)
        if ok and type(root) == "table" then
            return root
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_CD_DATA")
    return type(raw) == "table" and raw or {}
end

local function GetTrashSpellNameSafe(spellID, fallback)
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(spellID))
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    if TrashData and type(TrashData.GetSpellNameSafe) == "function" then
        local ok, name = pcall(TrashData.GetSpellNameSafe, tonumber(spellID))
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(fallback or (T("技能 ") .. tostring(spellID or "")))
end

local function BuildTrashSpellIndex()
    local source = GetTrashCDDataSource()
    if _trashIndexCache and _trashIndexSource == source then
        return _trashIndexCache
    end

    local out = {
        spells = {},
        ordered = {},
    }

    for rawMapID, mapRow in pairs(source or {}) do
        if type(mapRow) == "table" and type(mapRow.mobs) == "table" then
            local mapID = tonumber(mapRow.mapID) or tonumber(rawMapID)
            if mapID then
                local mapName = tostring(mapRow.mapName or mapRow.name or (T("副本 ") .. tostring(mapID)))
                for rawNpcID, mobRow in pairs(mapRow.mobs) do
                    if type(mobRow) == "table" and type(mobRow.spells) == "table" then
                        local npcID = tonumber(mobRow.npcID) or tonumber(rawNpcID)
                        if npcID then
                            local mobName = tostring(mobRow.name or (T("小怪 ") .. tostring(npcID)))
                            for rawSpellID, spellRow in pairs(mobRow.spells) do
                                if type(spellRow) == "table" then
                                    local spellID = tonumber(spellRow.spellID) or tonumber(rawSpellID)
                                    if spellID then
                                        local key = string.format("%d:%d:%d", mapID, npcID, spellID)
                                        local spellName = GetTrashSpellNameSafe(spellID, spellRow.name)
                                        local meta = {
                                            kind = "trash",
                                            key = key,
                                            mapID = mapID,
                                            mapName = mapName,
                                            npcID = npcID,
                                            bossName = mobName,
                                            eventID = spellID,
                                            eventName = spellName,
                                            spellID = spellID,
                                            spellName = spellName,
                                        }
                                        out.spells[key] = meta
                                        out.ordered[#out.ordered + 1] = meta
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(out.ordered, function(a, b)
        if a.mapName ~= b.mapName then
            return a.mapName < b.mapName
        end
        if a.bossName ~= b.bossName then
            return a.bossName < b.bossName
        end
        if a.eventName ~= b.eventName then
            return a.eventName < b.eventName
        end
        return (a.spellID or 0) < (b.spellID or 0)
    end)

    _trashIndexCache = out
    _trashIndexSource = source
    return out
end

local function GetTrashTargets()
    local index = BuildTrashSpellIndex()
    local out = {}
    for i = 1, #(index.ordered or {}) do
        out[#out + 1] = index.ordered[i]
    end
    return out
end

local function IsTrashSpellEnabled(mapID, npcID, spellID)
    if not (TrashStore and type(TrashStore.GetRuntimeSpellEntry) == "function") then
        return true
    end
    local row = TrashStore.GetRuntimeSpellEntry(mapID, npcID, spellID)
    if type(row) ~= "table" then
        return true
    end
    return row.enabled == true
end

local GetRuntimeTextForField
local GetRuntimeVoiceConfigForField
local PassFilter
local FindDropdownDisplayText
local GetRuntimeTextForTarget
local GetRuntimeVoiceConfigForTarget
local RefreshCardChrome

local function EventMatchesRuntimeText(eventID, field, searchText)
    local needle = NormalizeText(searchText)
    if needle == "" then
        return false
    end

    local rawText = GetRuntimeTextForField(eventID, field)
    if rawText == "" then
        return false
    end
    if rawText == needle then
        return true
    end

    local localizedText = LocalizeDynamicText(rawText)
    return localizedText ~= "" and localizedText == needle
end

local function BuildVoiceConfigDisplay(cfg)
    if type(cfg) ~= "table" then
        return ""
    end
    local source = NormalizeVoiceSource(cfg.sourceType)
    if source == "lsm" then
        return string.format("%s: %s", T("LSM音效"), tostring(cfg.customLSM or ""))
    end
    if source == "file" then
        return string.format("%s: %s", T("自定义路径"), tostring(cfg.customPath or ""))
    end
    if source == "tts" then
        return string.format("%s: %s", T("TTS语音"), tostring(cfg.ttsText or ""))
    end
    return string.format("%s: %s", T("语音包标签"), tostring(LocalizeDynamicText(cfg.label or "")))
end

local function BuildVoiceConfigKey(cfg)
    if type(cfg) ~= "table" then
        return ""
    end
    local source = NormalizeVoiceSource(cfg.sourceType)
    if source == "lsm" then
        return "lsm|" .. NormalizeText(cfg.customLSM)
    end
    if source == "file" then
        return "file|" .. NormalizeText(cfg.customPath)
    end
    if source == "tts" then
        return "tts|" .. NormalizeText(cfg.ttsText)
    end
    return "pack|" .. NormalizeText(cfg.label)
end

local function ParseVoiceConfigKey(key)
    local text = NormalizeText(key)
    if text == "" then
        return nil
    end
    local sourceType, value = text:match("^(.-)|(.+)$")
    sourceType = NormalizeVoiceSource(sourceType)
    value = NormalizeText(value)
    if value == "" then
        return nil
    end
    local cfg = { sourceType = sourceType }
    if sourceType == "lsm" then
        cfg.customLSM = value
    elseif sourceType == "file" then
        cfg.customPath = value
    elseif sourceType == "tts" then
        cfg.ttsText = value
    else
        cfg.label = value
    end
    return cfg
end

local function EventMatchesVoiceConfig(eventID, field, voiceKey)
    local needle = NormalizeText(voiceKey)
    if needle == "" then
        return false
    end
    local cfg = GetRuntimeVoiceConfigForField(eventID, field)
    return BuildVoiceConfigKey(cfg) == needle
end

GetRuntimeTextForField = function(eventID, field)
    local row = GetRuntimeEvent(eventID)
    if type(row) ~= "table" then
        return ""
    end

    if field == "centralTextReplace" then
        return NormalizeText(row.centralText)
    end

    if field == "preAlertTextReplace" or field == "timerBarRenameTextReplace" then
        local linkedField = (field == "preAlertTextReplace") and "preAlertText" or "timerBarRenameText"
        return NormalizeText(row[linkedField])
    end

    return ""
end

GetRuntimeVoiceConfigForField = function(eventID, field)
    local triggerIndex = GetVoiceReplaceTriggerIndex(field)
    if triggerIndex == nil then
        return nil
    end

    local row = GetRuntimeEvent(eventID)
    if type(row) ~= "table" or type(row.triggers) ~= "table" then
        return nil
    end

    local trig = row.triggers[triggerIndex]
    if type(trig) ~= "table" then
        return nil
    end

    local sourceType = NormalizeVoiceSource(trig.sourceType)
    local out = { sourceType = sourceType }
    if sourceType == "lsm" then
        out.customLSM = NormalizeText(trig.customLSM)
        if out.customLSM == "" then return nil end
        return out
    end
    if sourceType == "file" then
        out.customPath = NormalizeText(trig.customPath)
        if out.customPath == "" then return nil end
        return out
    end
    if sourceType == "tts" then
        out.ttsText = NormalizeText(trig.ttsText)
        if out.ttsText == "" then return nil end
        return out
    end

    local label = NormalizeText(trig.label)
    if label == "" and triggerIndex == 2 then
        label = "54321"
    end
    if label == "" then
        return nil
    end
    out.label = label
    return out
end

GetRuntimeTextForTarget = function(target, field)
    if type(target) == "table" and target.kind == "trash" then
        if not (TrashStore and type(TrashStore.GetRuntimeSpellEntry) == "function") then
            return ""
        end
        local row = TrashStore.GetRuntimeSpellEntry(target.mapID, target.npcID, target.spellID)
        if type(row) ~= "table" then
            return ""
        end
        if field == "centralTextReplace" then
            return NormalizeText(row.centralText)
        end
        if field == "preAlertTextReplace" then
            return NormalizeText(row.countdownText)
        end
        if field == "timerBarRenameTextReplace" then
            return NormalizeText(row.timerBarName)
        end
        return ""
    end
    return GetRuntimeTextForField(type(target) == "table" and target.eventID or target, field)
end

GetRuntimeVoiceConfigForTarget = function(target, field)
    if type(target) == "table" and target.kind == "trash" then
        if not (TrashStore and type(TrashStore.GetRuntimeSpellEntry) == "function") then
            return nil
        end
        local row = TrashStore.GetRuntimeSpellEntry(target.mapID, target.npcID, target.spellID)
        if type(row) ~= "table" then
            return nil
        end
        local sourceType
        local cfg = nil
        if field == "trigger1VoiceReplace" then
            sourceType = NormalizeVoiceSource(row.voice1Source)
            cfg = {
                sourceType = sourceType,
                label = NormalizeText(row.voice1Label),
                customLSM = NormalizeText(row.voice1LSM),
                customPath = NormalizeText(row.voice1Path),
            }
        elseif field == "trigger2VoiceReplace" then
            sourceType = NormalizeVoiceSource(row.voice2Source)
            cfg = {
                sourceType = sourceType,
                label = NormalizeText(row.voice2Label),
                customLSM = NormalizeText(row.voice2LSM),
                customPath = NormalizeText(row.voice2Path),
            }
        else
            return nil
        end
        if sourceType == "pack" and NormalizeText(cfg.label) == "" then
            return nil
        end
        if sourceType == "lsm" and NormalizeText(cfg.customLSM) == "" then
            return nil
        end
        if sourceType == "file" and NormalizeText(cfg.customPath) == "" then
            return nil
        end
        return cfg
    end
    return GetRuntimeVoiceConfigForField(type(target) == "table" and target.eventID or target, field)
end

local function BuildTextDropdownItems()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local dedup = {}
    local out = {}
    local field = tostring(db.field1 or "")

    local targets = nil
    if IsTrashScope(db.scope) then
        targets = GetTrashTargets()
    end
    if targets then
        for i = 1, #targets do
            local target = targets[i]
            if PassFilter(target, db.targetFilter) and true then
                local rawText = GetRuntimeTextForTarget(target, field)
                if rawText ~= "" and not dedup[rawText] then
                    dedup[rawText] = true
                    out[#out + 1] = { LocalizeDynamicText(rawText), rawText }
                end
            end
        end
    else
        local ids = GetScopeEventIDs(db.scope)
        for _, eventID in ipairs(ids) do
            if PassFilter(eventID, db.targetFilter) then
                local rawText = GetRuntimeTextForField(eventID, field)
                if rawText ~= "" and not dedup[rawText] then
                    dedup[rawText] = true
                    out[#out + 1] = { LocalizeDynamicText(rawText), rawText }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local at = tostring(a and a[1] or "")
        local bt = tostring(b and b[1] or "")
        if at ~= bt then
            return at < bt
        end
        return tostring(a and a[2] or "") < tostring(b and b[2] or "")
    end)

    if #out == 0 then
        out[1] = { T("当前范围无可替换文本"), "" }
    end
    return out
end

function Page.GetPreAlertTextDropdownItems()
    return BuildTextDropdownItems()
end

local function BuildVoiceDropdownItems()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local dedup = {}
    local out = {}
    local field = tostring(db.field1 or "")

    local targets = nil
    if IsTrashScope(db.scope) then
        targets = GetTrashTargets()
    end
    if targets then
        for i = 1, #targets do
            local target = targets[i]
            if PassFilter(target, db.targetFilter) and true then
                local voiceCfg = GetRuntimeVoiceConfigForTarget(target, field)
                local key = BuildVoiceConfigKey(voiceCfg)
                if key ~= "" and not dedup[key] then
                    dedup[key] = true
                    out[#out + 1] = { BuildVoiceConfigDisplay(voiceCfg), key }
                end
            end
        end
    else
        local ids = GetScopeEventIDs(db.scope)
        for _, eventID in ipairs(ids) do
            if PassFilter(eventID, db.targetFilter) then
                local voiceCfg = GetRuntimeVoiceConfigForField(eventID, field)
                local key = BuildVoiceConfigKey(voiceCfg)
                if key ~= "" and not dedup[key] then
                    dedup[key] = true
                    out[#out + 1] = { BuildVoiceConfigDisplay(voiceCfg), key }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local at = tostring(a and a[1] or "")
        local bt = tostring(b and b[1] or "")
        if at ~= bt then
            return at < bt
        end
        return tostring(a and a[2] or "") < tostring(b and b[2] or "")
    end)

    if #out == 0 then
        out[1] = { T("当前范围无可替换语音"), "" }
    end
    return out
end

function Page.GetVoiceMatchDropdownItems()
    return BuildVoiceDropdownItems()
end

PassFilter = function(eventID, filterKey)
    if type(eventID) == "table" and eventID.kind == "trash" then
        if filterKey == "enabledOnly" then
            return IsTrashSpellEnabled(eventID.mapID, eventID.npcID, eventID.spellID)
        end
        if filterKey == "disabledOnly" then
            return not IsTrashSpellEnabled(eventID.mapID, eventID.npcID, eventID.spellID)
        end
        return true
    end
    if filterKey == "enabledOnly" then
        return IsEventEnabled(eventID)
    end
    if filterKey == "disabledOnly" then
        return not IsEventEnabled(eventID)
    end
    return true
end

local function CollectTargets(db)
    local out = {}
    local selectedField = tostring(db.field1 or "")
    local searchText = NormalizeText(db.matchText)
    if IsTrashScope(db.scope) then
        local targets = GetTrashTargets()
        for i = 1, #targets do
            local target = targets[i]
            if PassFilter(target, db.targetFilter) then
                local matched = true
                if IsTargetAlertConfigField(selectedField) then
                    matched = IsTrashTargetAlertSupported(target.spellID)
                elseif IsTextReplaceField(selectedField) then
                    local rawText = GetRuntimeTextForTarget(target, selectedField)
                    local needle = NormalizeText(searchText)
                    matched = needle ~= "" and (rawText == needle or LocalizeDynamicText(rawText) == needle)
                elseif IsVoiceReplaceField(selectedField) then
                    matched = BuildVoiceConfigKey(GetRuntimeVoiceConfigForTarget(target, selectedField)) == NormalizeText(db.matchVoice)
                end
                if matched then
                    out[#out + 1] = target
                end
            end
        end
    else
        local index = BuildEncounterIndex()
        local ids = GetScopeEventIDs(db.scope)
        for _, eventID in ipairs(ids) do
            if PassFilter(eventID, db.targetFilter) then
                local matched = true
                if IsTargetAlertConfigField(selectedField) then
                    matched = IsBossTargetAlertSupported(eventID)
                elseif IsTextReplaceField(selectedField) then
                    matched = EventMatchesRuntimeText(eventID, selectedField, searchText)
                elseif IsVoiceReplaceField(selectedField) then
                    matched = EventMatchesVoiceConfig(eventID, selectedField, db.matchVoice)
                end
                if matched then
                    local meta = index.events[eventID]
                    if meta then
                        out[#out + 1] = meta
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.mapName ~= b.mapName then
            return a.mapName < b.mapName
        end
        if a.bossName ~= b.bossName then
            return a.bossName < b.bossName
        end
        return (a.eventID or 0) < (b.eventID or 0)
    end)
    return out
end

local function GetOperations(db)
    local out = {}
    local field = tostring(db.field1 or "")
    local action = tostring(db.action1 or "enable")
    if field ~= "" then
        if IsTextReplaceField(field) then
            local matchText = NormalizeText(db.matchText)
            if matchText ~= "" then
                out[#out + 1] = {
                    field = field,
                    matchText = matchText,
                    replaceText = NormalizeText(db.replaceText),
                }
            end
        elseif IsVoiceReplaceField(field) then
            local sourceType = NormalizeVoiceSource(db.voiceSource)
            local matchVoice = NormalizeText(db.matchVoice)
            if IsTrashScope(db.scope) and sourceType == "tts" then
                return out
            end
            local op = {
                field = field,
                matchVoice = matchVoice,
                voiceSource = sourceType,
                voiceLabel = "",
                voiceLSM = "",
                voicePath = "",
                voiceTtsText = "",
            }
            if matchVoice ~= "" then
                if sourceType == "pack" then
                    op.voiceLabel = NormalizeText(db.voiceLabel)
                    if op.voiceLabel ~= "" then
                        out[#out + 1] = op
                    end
                elseif sourceType == "lsm" then
                    op.voiceLSM = NormalizeText(db.voiceLSM)
                    if op.voiceLSM ~= "" then
                        out[#out + 1] = op
                    end
                elseif sourceType == "tts" then
                    op.voiceTtsText = NormalizeText(db.voiceTtsText)
                    if op.voiceTtsText ~= "" then
                        out[#out + 1] = op
                    end
                else
                    op.voicePath = NormalizeText(db.voicePath)
                    if op.voicePath ~= "" then
                        out[#out + 1] = op
                    end
                end
            end
        elseif IsTargetAlertConfigField(field) then
            out[#out + 1] = {
                field = field,
                taEnabled = db.taEnabled == true,
                taRingEnabled = db.taRingEnabled == true,
                taIconEnabled = db.taIconEnabled == true,
                taTextEnabled = db.taTextEnabled == true,
                taStealthEnabled = db.taStealthEnabled == true,
                taLSM = NormalizeText(db.taLSM),
            }
        else
            out[#out + 1] = { field = field, action = action }
        end
    end
    return out
end

-- Batch editing writes only the current User paths this page owns.
local MPLUS_BATCH_EVENT_FIELDS = {
    "enabled", "centralEnabled", "preAlertEnabled", "preAlert", "timerBarRenameEnabled",
    "triggers", "rules", "color", "timerTextColorEnabled", "timerTextColorR",
    "timerTextColorG", "timerTextColorB", "timerTextColorA", "preAlertText",
    "centralText", "timerBarRenameText", "targetAlertStartEnabled", "targetAlertStartLSM",
    "targetAlertRingEnabled", "targetAlertIconEnabled", "targetAlertTextEnabledV2",
    "targetAlertStealthEnabledV2",
}

local function WriteMplusEventValues(api, eventID, row)
    for _, field in ipairs(MPLUS_BATCH_EVENT_FIELDS) do
        local value = row[field]
        if value ~= nil and not api.SetCurrentUserPath("mplus", { "events", eventID, field }, value) then
            return false
        end
    end
    return true
end

local function EnsureTrigger(row, index)
    row.triggers = type(row.triggers) == "table" and row.triggers or {}
    row.triggers[index] = type(row.triggers[index]) == "table" and row.triggers[index] or {}
    return row.triggers[index]
end

local function ApplyOperationToRow(row, operation)
    local field = operation.field
    local action = operation.action
    local enabled = (action == "enable")

    if field == "enabled" then
        row.enabled = enabled
    elseif field == "centralEnabled" then
        row.centralEnabled = enabled
    elseif field == "preAlertEnabled" then
        row.preAlertEnabled = enabled
        row.preAlert = enabled and 5 or 0
    elseif field == "timerBarRenameEnabled" then
        row.timerBarRenameEnabled = enabled
    elseif field == "trigger0" or field == "trigger1" or field == "trigger2" then
        local idx = tonumber(field:match("(%d)$"))
        local trig = idx and EnsureTrigger(row, idx) or nil
        if trig then
            trig.enabled = enabled
        end
    elseif field == "ringEnabled" then
        row.rules = type(row.rules) == "table" and row.rules or {}
        row.rules.castWindow = type(row.rules.castWindow) == "table" and row.rules.castWindow or {}
        local cw = row.rules.castWindow
        cw.enabled = enabled
        cw.ringEnabled = enabled
        if enabled then
            cw.windowBefore = 1
            cw.windowAfter = 2
        end
    elseif field == "eventColorCombined" then
        row.color = type(row.color) == "table" and row.color or {}
        row.color.enabled = enabled
        row.timerTextColorEnabled = enabled
        if enabled then
            local r = tonumber(row.color.r)
            local g = tonumber(row.color.g)
            local b = tonumber(row.color.b)
            local a = tonumber(row.color.a) or 1
            if (not (r and g and b)) and type(row.color.scheme) == "string" and row.color.scheme ~= "" then
                local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
                if CS and CS.GetSchemeColor then
                    r, g, b = CS.GetSchemeColor(row.color.scheme)
                end
            end
            if r and g and b then
                row.timerTextColorR = r
                row.timerTextColorG = g
                row.timerTextColorB = b
                row.timerTextColorA = a
            end
        else
            row.timerTextColorR = nil
            row.timerTextColorG = nil
            row.timerTextColorB = nil
            row.timerTextColorA = nil
        end
    elseif field == "preAlertTextReplace" then
        row.preAlertText = NormalizeText(operation.replaceText)
    elseif field == "centralTextReplace" then
        row.centralText = NormalizeText(operation.replaceText)
    elseif field == "timerBarRenameTextReplace" then
        row.timerBarRenameText = NormalizeText(operation.replaceText)
    elseif IsVoiceReplaceField(field) then
        local idx = GetVoiceReplaceTriggerIndex(field)
        local trig = idx and EnsureTrigger(row, idx) or nil
        if trig then
            local sourceType = NormalizeVoiceSource(operation.voiceSource)
            trig.sourceType = sourceType
            if sourceType == "pack" then
                trig.label = NormalizeText(operation.voiceLabel)
                trig.customLSM = nil
                trig.customPath = nil
                trig.ttsText = nil
            elseif sourceType == "lsm" then
                trig.label = nil
                trig.customLSM = NormalizeText(operation.voiceLSM)
                trig.customPath = nil
                trig.ttsText = nil
            elseif sourceType == "tts" then
                trig.label = nil
                trig.customLSM = nil
                trig.customPath = nil
                trig.ttsText = NormalizeText(operation.voiceTtsText)
            else
                trig.label = nil
                trig.customLSM = nil
                trig.customPath = NormalizeText(operation.voicePath)
                trig.ttsText = nil
            end
        end
    elseif field == "targetAlertConfig" then
        row.targetAlertStartEnabled = operation.taEnabled
        row.targetAlertStartLSM = operation.taLSM
        row.targetAlertRingEnabled = operation.taRingEnabled
        row.targetAlertIconEnabled = operation.taIconEnabled
        row.targetAlertTextEnabledV2 = operation.taTextEnabled
        row.targetAlertStealthEnabledV2 = operation.taStealthEnabled
    end

end

local function ApplyTrashOperation(mapID, npcID, spellID, operation)
    local field = tostring(operation.field or "")
    local action = tostring(operation.action or "")
    local enabled = (action == "enable")
    local function Set(path, value)
        return TrashStore.SetSpellEntryValue(mapID, npcID, spellID, { path }, value)
    end
    if field == "enabled" then
        return Set("enabled", enabled)
    elseif field == "centralEnabled" then
        return Set("centralEnabled", enabled)
    elseif field == "preAlertEnabled" then
        return Set("countdownEnabled", enabled)
    elseif field == "timerBarRenameEnabled" then
        return Set("timerBarRenameEnabled", enabled)
    elseif field == "trigger1" then
        return Set("voice1Enabled", enabled)
    elseif field == "trigger2" then
        return Set("countdownVoiceEnabled", enabled)
    elseif field == "ringEnabled" then
        return Set("ringEnabled", enabled)
    elseif field == "eventColorCombined" then
        return Set("eventColorEnabled", enabled)
    elseif field == "preAlertTextReplace" then
        return Set("countdownText", NormalizeText(operation.replaceText))
    elseif field == "centralTextReplace" then
        return Set("centralText", NormalizeText(operation.replaceText))
    elseif field == "timerBarRenameTextReplace" then
        return Set("timerBarName", NormalizeText(operation.replaceText))
    elseif field == "trigger1VoiceReplace" then
        local source = NormalizeVoiceSource(operation.voiceSource)
        if not Set("voice1Source", source) then return false end
        if source == "pack" then
            return Set("voice1Label", NormalizeText(operation.voiceLabel))
        elseif source == "lsm" then
            return Set("voice1LSM", NormalizeText(operation.voiceLSM))
        else
            return Set("voice1Path", NormalizeText(operation.voicePath))
        end
    elseif field == "trigger2VoiceReplace" then
        local source = NormalizeVoiceSource(operation.voiceSource)
        if not Set("voice2Source", source) then return false end
        if source == "pack" then
            return Set("voice2Label", NormalizeText(operation.voiceLabel))
        elseif source == "lsm" then
            return Set("voice2LSM", NormalizeText(operation.voiceLSM))
        else
            return Set("voice2Path", NormalizeText(operation.voicePath))
        end
    elseif field == "targetAlertConfig" then
        if not Set("targetAlertStartEnabled", operation.taEnabled) then return false end
        if not Set("targetAlertStartLSM", operation.taLSM) then return false end
        if not Set("targetAlertRingEnabled", operation.taRingEnabled) then return false end
        if not Set("targetAlertIconEnabled", operation.taIconEnabled) then return false end
        if not Set("targetAlertTextEnabledV2", operation.taTextEnabled) then return false end
        return Set("targetAlertStealthEnabledV2", operation.taStealthEnabled)
    end
    return false
end

local function ApplyBatch(db)
    local targets = CollectTargets(db)
    local operations = GetOperations(db)
    if #targets == 0 or #operations == 0 then
        return false, #targets, #operations
    end
    if IsTrashScope(db.scope) then
        if not (TrashStore and type(TrashStore.SetSpellEntryValue) == "function") then
            return false, #targets, #operations
        end
        for _, meta in ipairs(targets) do
            for _, operation in ipairs(operations) do
                local ok = ApplyTrashOperation(meta.mapID, meta.npcID, meta.spellID, operation)
                if not ok then return false, #targets, #operations end
            end
        end
        local TrashPage = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TrashCDPage or nil
        if TrashPage and TrashPage._visible then
            if type(TrashPage.RefreshSpellList) == "function" then
                pcall(TrashPage.RefreshSpellList, TrashPage)
            end
            if type(TrashPage.RefreshSelectedSpell) == "function" then
                pcall(TrashPage.RefreshSelectedSpell, TrashPage)
            end
        end
        return true, #targets, #operations
    end

    local api = _G.EXBossData
    if not (type(api) == "table" and type(api.SetCurrentUserPath) == "function") then
        return false, 0, 0
    end

    for _, meta in ipairs(targets) do
        local row = GetRuntimeEvent(meta.eventID)
        if type(row) ~= "table" then
            return false, #targets, #operations
        end
        row = DeepCopy(row)
        for _, operation in ipairs(operations) do
            ApplyOperationToRow(row, operation)
        end
        if not WriteMplusEventValues(api, meta.eventID, row) then
            return false, #targets, #operations
        end
    end
    return true, #targets, #operations
end

local function BuildPreviewText(db, applied)
    local targets = CollectTargets(db)
    local operations = GetOperations(db)
    local lines = {}
    if applied == true then
        lines[#lines + 1] = T("已应用批量修改。")
    end
    lines[#lines + 1] = string.format("%s：%d", T("命中事件数量"), #targets)
    lines[#lines + 1] = string.format("%s：%d", T("动作数量"), #operations)
    lines[#lines + 1] = ""

    if #operations == 0 then
        lines[#lines + 1] = T("请至少选择一条批量动作。")
    else
        lines[#lines + 1] = T("本次动作")
        local replaceFieldNames = {
            preAlertTextReplace = T("倒数文本替换"),
            centralTextReplace = T("中央文本替换"),
            timerBarRenameTextReplace = T("计时条改名替换"),
            trigger0VoiceReplace = T("中央警告语音替换"),
            trigger1VoiceReplace = T("施法开始语音替换"),
            trigger2VoiceReplace = T("提前5秒语音替换"),
        }
        for i = 1, #operations do
            local op = operations[i]
            if IsTextReplaceField(op.field) then
                lines[#lines + 1] = string.format(
                    "%d. %s: \"%s\" -> \"%s\"",
                    i,
                    tostring(replaceFieldNames[op.field] or op.field),
                    tostring(op.matchText or ""),
                    tostring(op.replaceText or "")
                )
            elseif IsVoiceReplaceField(op.field) then
                local replaceCfg = {
                    sourceType = op.voiceSource,
                    label = op.voiceLabel,
                    customLSM = op.voiceLSM,
                    customPath = op.voicePath,
                    ttsText = op.voiceTtsText,
                }
                local matchDisplay = FindDropdownDisplayText(BuildVoiceDropdownItems(), op.matchVoice)
                if not matchDisplay then
                    matchDisplay = BuildVoiceConfigDisplay(ParseVoiceConfigKey(op.matchVoice))
                end
                lines[#lines + 1] = string.format(
                    "%d. %s: \"%s\" -> \"%s\"",
                    i,
                    tostring(replaceFieldNames[op.field] or op.field),
                    tostring(matchDisplay or op.matchVoice or ""),
                    tostring(BuildVoiceConfigDisplay(replaceCfg))
                )
            elseif IsTargetAlertConfigField(op.field) then
                local lsmDisplay = op.taLSM ~= "" and op.taLSM or T("(无音效)")
                lines[#lines + 1] = string.format(
                    "%d. %s: %s=%s %s=%s %s=%s %s=%s %s=%s %s=%s",
                    i, T("[被点名提示] 整体配置"),
                    T("启用"), op.taEnabled and T("是") or T("否"),
                    T("圆环"), op.taRingEnabled and T("是") or T("否"),
                    T("图标"), op.taIconEnabled and T("是") or T("否"),
                    T("文本"), op.taTextEnabled and T("是") or T("否"),
                    T("隐遁提示"), op.taStealthEnabled and T("是") or T("否"),
                    T("音效"), lsmDisplay
                )
            else
                local fieldName = op.field
                local actionName = op.action
                for _, row in ipairs(GetFieldItemsForScope(db.scope)) do
                    if row[2] == op.field then fieldName = row[1] break end
                end
                for _, row in ipairs(ACTION_ITEMS) do
                    if row[2] == op.action then actionName = row[1] break end
                end
                lines[#lines + 1] = string.format("%d. %s -> %s", i, tostring(fieldName), tostring(actionName))
            end
        end
    end

    lines[#lines + 1] = ""
    if #targets == 0 then
        lines[#lines + 1] = T("当前范围没有命中任何事件。")
    else
        lines[#lines + 1] = T("预览前20条事件")
        local limit = math.min(#targets, 20)
        for i = 1, limit do
            local row = targets[i]
            lines[#lines + 1] = string.format(
                "[%d] %s / %s / %s",
                tonumber(row.eventID) or 0,
                tostring(row.mapName or "?"),
                tostring(row.bossName or "?"),
                tostring(row.eventName or "?")
            )
        end
        if #targets > limit then
            lines[#lines + 1] = string.format(T("其余省略，共%d条。"), #targets)
        end
    end

    return table.concat(lines, "\n")
end

local function UpdatePreviewWidget(applied)
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end
    if ExwindTools.UI and ExwindTools.UI.CurrentModule ~= MODULE_KEY then
        return
    end
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local widget = Grid.Widgets["previewText"]
    if widget and widget.text and widget.text.SetText then
        widget.text:SetText(BuildPreviewText(db, applied))
    end
end

local function SetWidgetVisible(widget, visible)
    if not widget then
        return
    end
    if visible then
        if widget.Show then widget:Show() end
        if widget.label and widget.label.Show then widget.label:Show() end
        if widget.text and widget.text.Show then widget.text:Show() end
        if widget.input and widget.input.Show then widget.input:Show() end
        if widget.button and widget.button.Show then widget.button:Show() end
        if widget.dropdown and widget.dropdown.Show then widget.dropdown:Show() end
    else
        if widget.Hide then widget:Hide() end
        if widget.label and widget.label.Hide then widget.label:Hide() end
        if widget.text and widget.text.Hide then widget.text:Hide() end
        if widget.input and widget.input.Hide then widget.input:Hide() end
        if widget.button and widget.button.Hide then widget.button:Hide() end
        if widget.dropdown and widget.dropdown.Hide then widget.dropdown:Hide() end
    end
end

local function CollectWidgetBounds(parent, keys)
    local Grid = _G.ExwindGrid
    if not (parent and Grid and type(Grid.Widgets) == "table") then
        return nil
    end

    local parentLeft = parent:GetLeft()
    local parentTop = parent:GetTop()
    if not (parentLeft and parentTop) then
        return nil
    end

    local minLeft, maxRight, maxTop, minBottom

    local function Touch(obj)
        if not (obj and obj.IsShown and obj:IsShown()) then
            return
        end
        local left, right, top, bottom = obj:GetLeft(), obj:GetRight(), obj:GetTop(), obj:GetBottom()
        if not (left and right and top and bottom) then
            return
        end
        minLeft = minLeft and math.min(minLeft, left) or left
        maxRight = maxRight and math.max(maxRight, right) or right
        maxTop = maxTop and math.max(maxTop, top) or top
        minBottom = minBottom and math.min(minBottom, bottom) or bottom
    end

    for i = 1, #keys do
        local widget = Grid.Widgets[keys[i]]
        if widget then
            Touch(widget)
            Touch(widget.label)
            Touch(widget.text)
            Touch(widget.input)
            Touch(widget.button)
            Touch(widget.dropdown)
        end
    end

    if not (minLeft and maxRight and maxTop and minBottom) then
        return nil
    end

    return {
        left = minLeft - parentLeft,
        right = maxRight - parentLeft,
        top = maxTop - parentTop,
        bottom = minBottom - parentTop,
    }
end

local function ApplyCardBounds(frame, parent, bounds, padX, padTop, padBottom, minHeight)
    if not (frame and parent and bounds) then
        if frame then frame:Hide() end
        return
    end

    local left = bounds.left - (padX or 18)
    local right = bounds.right + (padX or 18)
    local top = bounds.top + (padTop or 34)
    local bottom = bounds.bottom - (padBottom or 18)

    if minHeight and (top - bottom) < minHeight then
        bottom = top - minHeight
    end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    frame:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", right, bottom)
    frame:Show()
end

RefreshCardChrome = function()
    local Grid = _G.ExwindGrid
    local parent = Page._scrollChild
    if not (Grid and parent and Page._cards) then
        return
    end
    if ExwindTools.UI and ExwindTools.UI.CurrentModule ~= MODULE_KEY then
        return
    end

    local topBounds = CollectWidgetBounds(parent, { "scope", "targetFilter", "field1" })
    local bottomBounds = CollectWidgetBounds(parent, { "matchText", "matchVoice", "action1", "replaceText", "voiceSource", "voiceLabel", "voiceLSM", "voicePath", "voiceTtsText", "btn_preview", "btn_apply" })
    if not (topBounds and bottomBounds) then
        return
    end

    local sharedLeft = math.min(topBounds.left, bottomBounds.left)
    local sharedRight = math.max(topBounds.right, bottomBounds.right)
    topBounds.left = sharedLeft
    topBounds.right = sharedRight
    bottomBounds.left = sharedLeft
    bottomBounds.right = sharedRight

    bottomBounds.top = bottomBounds.top - 10
    bottomBounds.bottom = bottomBounds.bottom - 10

    ApplyCardBounds(Page._cards.source, parent, topBounds, 18, 72, 18, 138)
    ApplyCardBounds(Page._cards.target, parent, bottomBounds, 18, 72, 18, 234)
end

FindDropdownDisplayText = function(items, value)
    local target = tostring(value or "")
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            if tostring(item[2] or "") == target then
                return tostring(item[1] or "")
            end
        elseif tostring(item or "") == target then
            return tostring(item or "")
        end
    end
    return nil
end

local function RefreshDropdownWidget(widget, items, db, dbKey, emptyLabel)
    if not widget then
        return
    end

    widget._items = items
    local currentValue = NormalizeText(db[dbKey])
    local displayText = FindDropdownDisplayText(items, currentValue)
    if displayText then
        widget._currentValue = currentValue
        if widget.SetText then
            widget:SetText(displayText)
        end
        return
    end

    local firstLabel = emptyLabel or L["请选择..."]
    local firstValue = ""
    local firstItem = items and items[1] or nil
    if type(firstItem) == "table" then
        firstLabel = tostring(firstItem[1] or firstLabel)
        firstValue = NormalizeText(firstItem[2])
    elseif firstItem ~= nil then
        firstLabel = tostring(firstItem)
        firstValue = NormalizeText(firstItem)
    end

    db[dbKey] = firstValue
    widget._currentValue = firstValue
    if widget.SetText then
        widget:SetText(firstLabel)
    end
end

local function RefreshMatchTextDropdown()
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end
    local widget = Grid.Widgets["matchText"]
    if not widget then
        return
    end

    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local items = BuildTextDropdownItems()
    RefreshDropdownWidget(widget, items, db, "matchText", T("当前范围无可替换文本"))
end

local function BuildLabelDropdownItems()
    local catalog = ExBoss and ExBoss.Voice and ExBoss.Voice.LabelCatalog
    if type(catalog) == "table" and type(catalog.GetDropdownItems) == "function" then
        local ok, items = pcall(catalog.GetDropdownItems, catalog)
        if ok and type(items) == "table" and #items > 0 then
            return items
        end
    end
    return { { T("当前无可用语音标签"), "" } }
end

local function GetVoiceSourceItemsForScope(scopeKey)
    if IsTrashScope(scopeKey) then
        return TRASH_VOICE_SOURCE_ITEMS
    end
    return VOICE_SOURCE_ITEMS
end

local function RefreshFieldDropdown()
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end
    local widget = Grid.Widgets["field1"]
    if not widget then
        return
    end

    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    RefreshDropdownWidget(widget, GetFieldItemsForScope(db.scope), db, "field1", T("请选择..."))
end

local function RefreshMatchVoiceDropdown()
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end
    local widget = Grid.Widgets["matchVoice"]
    if not widget then
        return
    end

    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local items = BuildVoiceDropdownItems()
    RefreshDropdownWidget(widget, items, db, "matchVoice", T("当前范围无可替换语音"))
end

local function RefreshVoiceReplaceInputs()
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end

    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local sourceType = NormalizeVoiceSource(db.voiceSource)
    local voiceSourceWidget = Grid.Widgets["voiceSource"]
    if voiceSourceWidget then
        RefreshDropdownWidget(voiceSourceWidget, GetVoiceSourceItemsForScope(db.scope), db, "voiceSource", T("语音包标签"))
        sourceType = NormalizeVoiceSource(db.voiceSource)
    end

    local labelWidget = Grid.Widgets["voiceLabel"]
    if labelWidget then
        RefreshDropdownWidget(labelWidget, BuildLabelDropdownItems(), db, "voiceLabel", T("当前无可用语音标签"))
    end

    SetWidgetVisible(labelWidget, sourceType == "pack")
    SetWidgetVisible(Grid.Widgets["voiceLSM"], sourceType == "lsm")
    SetWidgetVisible(Grid.Widgets["voicePath"], sourceType == "file")
    SetWidgetVisible(Grid.Widgets["voiceTtsText"], sourceType == "tts")
end

local function RefreshReplaceCopy()
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    local field = tostring(db.field1 or "")
    local subheader = Grid.Widgets["sub_replace"]
    local tip = Grid.Widgets["replaceTip"]
    local titleMap = {
        preAlertTextReplace = T("倒数文本替换"),
        centralTextReplace = T("中央文本替换"),
        timerBarRenameTextReplace = T("计时条改名替换"),
        trigger0VoiceReplace = T("中央警告语音替换"),
        trigger1VoiceReplace = T("施法开始语音替换"),
        trigger2VoiceReplace = T("提前5秒语音替换"),
    }
    local tipMap = {
        preAlertTextReplace = T("当批量动作选择“倒数文本替换”时，会按当前生效配置的倒数文本匹配，再写入当前 author override。"),
        centralTextReplace = T("当批量动作选择“中央文本替换”时，会按当前生效配置的中央文本匹配，再写入当前 author override。"),
        timerBarRenameTextReplace = T("当批量动作选择“计时条改名替换”时，会按当前生效配置的计时条改名匹配，再写入当前 author override。"),
        trigger0VoiceReplace = T("当批量动作选择“中央警告语音替换”时，会按当前生效配置的语音匹配，再写入当前 author override。"),
        trigger1VoiceReplace = T("当批量动作选择“施法开始语音替换”时，会按当前生效配置的语音匹配，再写入当前 author override。"),
        trigger2VoiceReplace = T("当批量动作选择“提前5秒语音替换”时，会按当前生效配置的语音匹配，再写入当前 author override。"),
    }
    if subheader then
        if subheader.SetText then
            subheader:SetText(titleMap[field] or T("批量替换"))
        elseif subheader.text and subheader.text.SetText then
            subheader.text:SetText(titleMap[field] or T("批量替换"))
        end
    end
    if tip and tip.text and tip.text.SetText then
        tip.text:SetText(tipMap[field] or T("当批量动作选择替换类动作时，会按当前生效配置匹配，再写入当前 author override。"))
    end
end

local function RefreshActionUI()
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then
        return
    end
    if ExwindTools.UI and ExwindTools.UI.CurrentModule ~= MODULE_KEY then
        return
    end
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    RefreshFieldDropdown()
    local field = tostring(db.field1 or "")
    local isTextReplaceMode = IsTextReplaceField(field)
    local isVoiceReplaceMode = IsVoiceReplaceField(field)
    local isReplaceMode = isTextReplaceMode or isVoiceReplaceMode
    local isTargetAlertMode = IsTargetAlertConfigField(field)

    if isTextReplaceMode then
        RefreshMatchTextDropdown()
    elseif isVoiceReplaceMode then
        RefreshMatchVoiceDropdown()
        RefreshVoiceReplaceInputs()
    end
    RefreshReplaceCopy()

    SetWidgetVisible(Grid.Widgets["sub_action"], not isReplaceMode and not isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["action1"], not isReplaceMode and not isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["sub_replace"], isReplaceMode)
    SetWidgetVisible(Grid.Widgets["matchText"], isTextReplaceMode)
    SetWidgetVisible(Grid.Widgets["replaceText"], isTextReplaceMode)
    SetWidgetVisible(Grid.Widgets["matchVoice"], isVoiceReplaceMode)
    SetWidgetVisible(Grid.Widgets["voiceSource"], isVoiceReplaceMode)
    SetWidgetVisible(Grid.Widgets["voiceLabel"], isVoiceReplaceMode and NormalizeVoiceSource(db.voiceSource) == "pack")
    SetWidgetVisible(Grid.Widgets["voiceLSM"], isVoiceReplaceMode and NormalizeVoiceSource(db.voiceSource) == "lsm")
    SetWidgetVisible(Grid.Widgets["voicePath"], isVoiceReplaceMode and NormalizeVoiceSource(db.voiceSource) == "file")
    SetWidgetVisible(Grid.Widgets["voiceTtsText"], isVoiceReplaceMode and NormalizeVoiceSource(db.voiceSource) == "tts")
    SetWidgetVisible(Grid.Widgets["taEnabled"],        isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["taLSM"],            isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["taValueTest"],      isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["taRingEnabled"],    isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["taIconEnabled"],    isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["taTextEnabled"],    isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["taStealthEnabled"], isTargetAlertMode)
    SetWidgetVisible(Grid.Widgets["replaceTip"], false)
    SetWidgetVisible(Grid.Widgets["header"], false)
    SetWidgetVisible(Grid.Widgets["desc"], false)
    SetWidgetVisible(Grid.Widgets["sub_scope"], false)
    SetWidgetVisible(Grid.Widgets["sub_filter"], false)
    SetWidgetVisible(Grid.Widgets["sub_field"], false)
    SetWidgetVisible(Grid.Widgets["sub_action"], false)
    SetWidgetVisible(Grid.Widgets["sub_replace"], false)
    SetWidgetVisible(Grid.Widgets["replaceTip"], false)
    SetWidgetVisible(Grid.Widgets["tip"], false)
    SetWidgetVisible(Grid.Widgets["previewHeader"], false)
    SetWidgetVisible(Grid.Widgets["previewText"], false)
    RefreshCardChrome()
end

local function RefreshActiveSurfaces()
    RefreshActionUI()
    UpdatePreviewWidget(false)
end

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
    if not info or not info.key then
        return
    end
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    if info.key == "btn_preview" then
        UpdatePreviewWidget(false)
        return
    end
    if info.key == "btn_apply" then
        local ok = ApplyBatch(db)
        UpdatePreviewWidget(ok == true)
    end
    if info.key == "taValueTest" then
        PlayTargetAlertLSMPreview(db.taLSM)
    end
end)

local function ResolveGridCols()
    return BASE_GRID_COLS
end

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end

    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
    end

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_BatchEditScroll", contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        Page._scrollFrame = sf
        Page._scrollChild = sc
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild
    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    if not Page._cards then
        Page._cards = {
            source = CreateCardFrame(sc, THEME.gold, T("把什么内容"), THEME.panel2),
            target = CreateCardFrame(sc, THEME.cyan, T("变更为"), THEME.panel),
        }
        Page._cards.source:SetFrameLevel(sc:GetFrameLevel())
        Page._cards.target:SetFrameLevel(sc:GetFrameLevel())
    else
        Page._cards.source:SetParent(sc)
        Page._cards.target:SetParent(sc)
    end

    C_Timer.After(0, function()
        if not sf:IsShown() then return end
        local w = contentFrame:GetWidth()
        if w < 100 then w = 820 end
        sc:SetWidth(w - 16)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()
        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = sc
            ExwindTools.UI.CurrentModule = MODULE_KEY
        end
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, ResolveGridCols())
        end
        Grid:Render(sc, LAYOUT, db, MODULE_KEY)
        RefreshActionUI()
        UpdatePreviewWidget(false)
        RefreshCardChrome()
    end)
end
