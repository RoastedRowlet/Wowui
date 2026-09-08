---@diagnostic disable: undefined-global

ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.Engine = ExBoss.Voice.Engine or {}
local Engine = ExBoss.Voice.Engine

local _lastPlayTime = {}
local PLAY_THROTTLE = 0.15
local _labelPackCache = {}
local _registeredEventSet = {}
local _registeredEventMeta = {}
local _registeredEventCount = 0
local _lastRegistrationSnapshot = nil
local _lastRegistrationError = nil
local _lastApplyScope = nil
local DEFAULT_VOICE_PACK = "EXWIND(默认)"
local DEFAULT_VOICE_PACK_ADDON = "EXBOSS-EXWIND"
local ENGLISH_VOICE_PACK = "英文(ENG)"
local ENGLISH_VOICE_PACK_ADDON = "EXBOSS-ENG"
local STANDARD_PACK_ADDONS = {
    [DEFAULT_VOICE_PACK] = DEFAULT_VOICE_PACK_ADDON,
    [ENGLISH_VOICE_PACK] = ENGLISH_VOICE_PACK_ADDON,
}

local function GetClientLocaleTag()
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.GetCurrentLocale) == "function" then
        local locale = tostring(ExBoss.Locale:GetCurrentLocale() or ""):gsub("%s+", "")
        if locale ~= "" then
            if locale == "enGB" then
                return "enUS"
            end
            return locale
        end
    end
    if ExBoss and type(ExBoss.GetEffectiveLocale) == "function" and type(ExBoss.GetLocaleMode) == "function" then
        local locale = tostring(ExBoss:GetEffectiveLocale(ExBoss:GetLocaleMode()) or ""):gsub("%s+", "")
        if locale ~= "" then
            if locale == "enGB" then
                return "enUS"
            end
            return locale
        end
    end
    if type(GetLocale) == "function" then
        local locale = tostring(GetLocale() or ""):gsub("%s+", "")
        if locale == "enGB" then
            return "enUS"
        end
        return locale
    end
    return ""
end

local function IsEnglishClientLocale(locale)
    locale = tostring(locale or "")
    return locale == "enUS" or locale == "enGB"
end

local function GetVoicePackDirectory(packName)
    local normalizedPackName = tostring(packName or "")
    local standardDirectory = STANDARD_PACK_ADDONS[normalizedPackName]
    if standardDirectory then
        return standardDirectory
    end

    local Registry = ExBoss and ExBoss.Voice and ExBoss.Voice.PackRegistry
    if Registry and type(Registry.GetPackDirectory) == "function" then
        local discovered = Registry.GetPackDirectory(normalizedPackName)
        if type(discovered) == "string" and discovered ~= "" then
            return discovered
        end
    end
    return nil
end

local function GetLocaleFallbackVoicePack()
    if IsEnglishClientLocale(GetClientLocaleTag()) then
        return ENGLISH_VOICE_PACK
    end
    return DEFAULT_VOICE_PACK
end

local function ResolveDefaultVoicePack()
    return GetLocaleFallbackVoicePack()
end

local function ShouldForceEnglishVoicePack(globalCfg)
    if type(globalCfg) ~= "table" then
        return false
    end
    if not IsEnglishClientLocale(GetClientLocaleTag()) then
        return false
    end
    return globalCfg.allowNonEnglishVoicePackOnEnglishLocale ~= true
end

local function EnsureDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    EXBOSS12S2.voice.global = EXBOSS12S2.voice.global or {}
    local g = EXBOSS12S2.voice.global
    if g.enabled == nil then g.enabled = true end
    if ShouldForceEnglishVoicePack(g) then g.selectedVoicePack = ENGLISH_VOICE_PACK end
    g.selectedVoicePack = g.selectedVoicePack or ResolveDefaultVoicePack()
    if g.fallbackLabel == nil or g.fallbackLabel == "" or g.fallbackLabel == "准备特殊技能" then
        g.fallbackLabel = "特殊技能"
    end
    g.channel = g.channel or "Master"
    g.volume = g.volume or 1.0
    if g.enabledInDungeon == nil then g.enabledInDungeon = true end
    local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
    if CS and CS.EnsureDB then CS.EnsureDB() end

    return {
        global = EXBOSS12S2.voice.global,
    }
end

-- Runtime 在配置系统重构后按场景拆分。语音层必须通过 EXBossData 读取当前
-- 场景的 Runtime，不能继续读取已经不存在的 ExBoss.Runtime 旧别名。
local function GetSceneRuntime(category)
    category = category == "raid" and "raid" or "mplus"
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetRuntime) == "function" then
        local runtime = api.GetRuntime(category)
        if type(runtime) == "table" then return runtime end
    end
    return ExBoss and (category == "raid" and ExBoss.RuntimeRaid or ExBoss.RuntimeMplus) or nil
end

local function ResolvePresentedEventConfig(timer)
    if type(timer) ~= "table" then
        return nil, nil
    end
    local eventKey = tonumber(timer.eventID) or tonumber(timer.timelineEventID)
    local _, instanceType = GetInstanceInfo()
    local runtime = GetSceneRuntime(instanceType == "raid" and "raid" or "mplus")
    local row = type(runtime) == "table" and type(runtime.events) == "table"
        and (runtime.events[eventKey] or runtime.events[tostring(eventKey)]) or nil
    if type(row) ~= "table" then
        return nil, nil
    end

    return {
        enabled = (row.enabled ~= false and timer.disabled ~= true),
        triggers = type(row.triggers) == "table" and row.triggers or nil,
        voiceLabel = row.voiceLabel,
        color = type(row.color) == "table" and row.color or nil,
    }, eventKey
end

local function ResolveEventColor(colorCfg)
    if type(colorCfg) ~= "table" or colorCfg.enabled == false then
        return nil
    end
    local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
    if CS and CS.ResolveEventColor then
        local r, g, b = CS.ResolveEventColor(colorCfg)
        if r ~= nil and g ~= nil and b ~= nil then
            return r, g, b
        end
    end
    if colorCfg.r ~= nil and colorCfg.g ~= nil and colorCfg.b ~= nil then
        return tonumber(colorCfg.r), tonumber(colorCfg.g), tonumber(colorCfg.b)
    end
    return nil
end

local function NormalizeEventID(key, cfg)
    if type(key) == "number" then
        return key
    end
    if type(key) == "string" then
        return tonumber(key)
    end
    if type(cfg) == "table" then
        return tonumber(cfg.eventID)
    end
    return nil
end

local function WipeTable(t)
    if type(t) ~= "table" then return end
    if wipe then
        wipe(t)
        return
    end
    for k in pairs(t) do
        t[k] = nil
    end
end

local TRIGGER_BIT = {
    [0] = 1,
    [1] = 2,
    [2] = 4,
}

local function HasTriggerBit(mask, trigger)
    local bitValue = TRIGGER_BIT[tonumber(trigger) or -1]
    if not bitValue then
        return false
    end
    local n = tonumber(mask) or 0
    return (n % (bitValue * 2)) >= bitValue
end

local function AddTriggerBit(mask, trigger)
    local bitValue = TRIGGER_BIT[tonumber(trigger) or -1]
    if not bitValue then
        return tonumber(mask) or 0
    end
    local n = tonumber(mask) or 0
    if HasTriggerBit(n, trigger) then
        return n
    end
    return n + bitValue
end

local function BuildTriggerList(mask)
    local out = {}
    for trigger = 0, 2 do
        if HasTriggerBit(mask, trigger) then
            out[#out + 1] = trigger
        end
    end
    return out
end

local function BuildTriggerText(mask)
    local list = BuildTriggerList(mask)
    if #list == 0 then
        return "-"
    end
    local labels = {}
    for i = 1, #list do
        labels[i] = tostring(list[i])
    end
    return table.concat(labels, ",")
end

local function BuildEventBossIndex()
    local out = {}
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) ~= "table" then
        return out
    end
    local maps = data.maps
    if type(maps) ~= "table" then
        maps = data
    end

    for mapID, mapRow in pairs(maps) do
        if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
            local dungeonID = tonumber(mapRow.instanceID) or tonumber(mapRow.instanceId) or tonumber(mapID)
            local gameMapID = tonumber(mapRow.mapID) or tonumber(mapID)
            local mapName = tostring(mapRow.mapName or mapRow.name or ("未知副本 " .. tostring(mapID)))
            local instanceType = tonumber(mapRow.instanceType)
            local categoryText = tostring(mapRow.category or "")
            local isRaid = (instanceType == 2) or (categoryText:find("团") ~= nil)
            for bossID, bossRow in pairs(mapRow.bosses) do
                if type(bossRow) == "table" and type(bossRow.events) == "table" then
                    local encounterID = tonumber(bossRow.encounterID) or tonumber(bossID) or bossID
                    local bossName = tostring(bossRow.bossName or bossRow.name or ("未知首领 " .. tostring(encounterID)))
                    for eventID, eventRow in pairs(bossRow.events) do
                        local eid = tonumber(type(eventRow) == "table" and eventRow.eventID or eventID)
                        if eid then
                            local list = out[eid]
                            if not list then
                                list = {}
                                out[eid] = list
                            end
                            local exists = false
                            for i = 1, #list do
                                if tostring(list[i].encounterID) == tostring(encounterID) then
                                    exists = true
                                    break
                                end
                            end
                            if not exists then
                                list[#list + 1] = {
                                    encounterID = encounterID,
                                    bossName = bossName,
                                    instanceID = dungeonID,
                                    mapID = gameMapID,
                                    mapName = mapName,
                                    isRaid = (isRaid == true),
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return out
end

local function GetMapNameByID(mapID)
    local id = tonumber(mapID)
    if not id or id <= 0 then
        return ""
    end
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) == "table" then
        local maps = data.maps
        if type(maps) ~= "table" then
            maps = data
        end
        local row = maps and maps[id]
        if type(row) ~= "table" and type(maps) == "table" then
            for _, item in pairs(maps) do
                if type(item) == "table" then
                    local iid = tonumber(item.instanceID) or tonumber(item.instanceId)
                    if iid and iid == id then
                        row = item
                        break
                    end
                end
            end
        end
        if type(row) == "table" then
            local name = tostring(row.mapName or row.name or "")
            if name ~= "" then
                return name
            end
        end
    end
    return "未知副本 " .. tostring(id)
end

local function BuildRegistrationSnapshot(eventMeta, eventCount, opts)
    opts = type(opts) == "table" and opts or {}
    local includeRaid = (opts.includeRaid ~= false)
    local scope = type(opts.scope) == "table" and opts.scope or nil
    local bossMap = BuildEventBossIndex()
    local bossAgg = {}
    local orphan = 0
    local filteredOutByRaid = 0
    local includedEventCount = 0
    local trigger0Events = 0
    local trigger1Events = 0
    local trigger2Events = 0

    for eventID, meta in pairs(eventMeta or {}) do
        local refs = type(meta) == "table" and meta.refs or nil
        if type(refs) ~= "table" or #refs == 0 then
            refs = bossMap[tonumber(eventID)]
        end
        local triggerMask = tonumber(type(meta) == "table" and meta.triggerMask) or 0
        local matched = false
        if type(refs) == "table" and #refs > 0 then
            for i = 1, #refs do
                local ref = refs[i]
                if includeRaid or not (ref and ref.isRaid == true) then
                    matched = true
                    local key = tostring(ref.encounterID)
                    local row = bossAgg[key]
                    if not row then
                        row = {
                            encounterID = ref.encounterID,
                            bossName = ref.bossName,
                            instanceID = ref.instanceID,
                            mapID = ref.mapID,
                            mapName = ref.mapName,
                            isRaid = (ref.isRaid == true),
                            count = 0,
                            _eventSet = {},
                            _eventMeta = {},
                        }
                        bossAgg[key] = row
                    end
                    if not row._eventSet[eventID] then
                        row._eventSet[eventID] = true
                        row._eventMeta[eventID] = meta
                        row.count = row.count + 1
                    end
                end
            end
        end

        if matched then
            includedEventCount = includedEventCount + 1
            if HasTriggerBit(triggerMask, 0) then trigger0Events = trigger0Events + 1 end
            if HasTriggerBit(triggerMask, 1) then trigger1Events = trigger1Events + 1 end
            if HasTriggerBit(triggerMask, 2) then trigger2Events = trigger2Events + 1 end
        elseif type(refs) == "table" and #refs > 0 and not includeRaid then
            filteredOutByRaid = filteredOutByRaid + 1
        else
            orphan = orphan + 1
        end
    end

    local rows = {}
    for _, row in pairs(bossAgg) do
        local eventIDs = {}
        for eid in pairs(row._eventSet or {}) do
            eventIDs[#eventIDs + 1] = tonumber(eid) or eid
        end
        table.sort(eventIDs, function(a, b)
            local na = tonumber(a)
            local nb = tonumber(b)
            if na and nb then
                return na < nb
            end
            return tostring(a) < tostring(b)
        end)
        local eventDetails = {}
        for i = 1, #eventIDs do
            local eid = eventIDs[i]
            local meta = row._eventMeta and row._eventMeta[eid] or nil
            local triggerMask = tonumber(type(meta) == "table" and meta.triggerMask) or 0
            eventDetails[#eventDetails + 1] = {
                eventID = eid,
                triggerMask = triggerMask,
                triggerText = BuildTriggerText(triggerMask),
                triggers = BuildTriggerList(triggerMask),
                policy = type(meta) == "table" and tostring(meta.policy or "") or "",
                mode = type(meta) == "table" and tostring(meta.mode or "") or "",
            }
        end
        row.eventIDs = eventIDs
        row._eventSet = nil
        row._eventMeta = nil
        row.eventDetails = eventDetails
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return tostring(a.bossName or "") < tostring(b.bossName or "")
    end)

    local stamp = date and date("%Y-%m-%d %H:%M:%S") or ""
    return {
        eventCount = includedEventCount,
        rawEventCount = tonumber(eventCount) or 0,
        bossCount = #rows,
        trigger0Events = trigger0Events,
        trigger1Events = trigger1Events,
        trigger2Events = trigger2Events,
        orphanEventCount = orphan,
        filteredOutByRaid = filteredOutByRaid,
        includeRaid = includeRaid,
        scopeInstanceID = scope and tonumber(scope.instanceID) or nil,
        scopeMapID = scope and tonumber(scope.mapID) or nil,
        scopeMapName = scope and GetMapNameByID(scope.instanceID) or "",
        scopeEncounterID = scope and tonumber(scope.encounterID) or nil,
        scopeInstanceType = scope and tostring(scope.instanceType or "") or "",
        scopeReason = scope and tostring(scope.reason or "") or "",
        updatedAt = stamp,
        rows = rows,
        error = _lastRegistrationError,
    }
end

local function IsContextEnabled(globalCfg)
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then
        return globalCfg.enabledInDungeon ~= false
    end
    return true
end

local function IsBossSceneEnabled(scene)
    local bossCfg = ExBoss and ExBoss.BossConfig
    if bossCfg and type(bossCfg.IsSceneEnabled) == "function" then
        local ok, enabled = pcall(bossCfg.IsSceneEnabled, bossCfg, scene)
        if ok then
            return enabled ~= false
        end
    end

    return tostring(scene or "") == "mplus"
end

local function ReadCVarValue(name)
    local key = tostring(name or "")
    if key == "" then
        return nil
    end
    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, key)
    end
    if (not ok or value == nil) and type(GetCVar) == "function" then
        ok, value = pcall(GetCVar, key)
    end
    if not ok or value == nil then
        return nil
    end
    local text = tostring(value or "")
    if text == "" then
        return nil
    end
    return text
end

local function WriteCVarValue(name, value)
    local key = tostring(name or "")
    local text = tostring(value or "")
    if key == "" or text == "" then
        return false
    end
    local ok = false
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, key, text)
        if ok then
            return true
        end
    end
    if type(SetCVar) == "function" then
        ok = pcall(SetCVar, key, text)
        if ok then
            return true
        end
    end
    return false
end

local function EnsureEncounterWarningsEnabled()
    local value = ReadCVarValue("encounterWarningsEnabled")
    if value == "0" then
        WriteCVarValue("encounterWarningsEnabled", "1")
        value = ReadCVarValue("encounterWarningsEnabled")
    elseif value == nil then
        WriteCVarValue("encounterWarningsEnabled", "1")
        value = "1"
    end
    return value ~= "0"
end

local function BuildLSMLabel(packName, label)
    packName = tostring(packName or "")
    label    = tostring(label    or "")
    if packName == "" or label == "" then return nil end
    return "[" .. packName .. "]" .. label
end

local function BuildCountdownLabelAliases(label)
    local text = tostring(label or "")
    local digit = text:match("^countdown%-(%d+)$")
    if not digit then
        return nil
    end
    return {
        tostring(digit),
        "倒数" .. tostring(digit),
    }
end

local function NormalizeVoiceLabel(label)
    local text = tostring(label or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return ""
    end
    if text == "无" or text:lower() == "none" then
        return ""
    end
    return text
end

local function ResolvePackTriggerLabel(triggerCfg, triggerIndex)
    local label = NormalizeVoiceLabel(triggerCfg and triggerCfg.label)
    if label ~= "" then
        return label
    end
    if tonumber(triggerIndex) == 2 then
        return "54321"
    end
    return nil
end

local function ResolveEventConfig(db, timer)
    local presentedCfg, presentedKey = ResolvePresentedEventConfig(timer)
    if type(presentedCfg) == "table" then
        return presentedCfg, presentedKey
    end
    return nil, nil
end

-- 语音包候选列表（全局单一选择，无 per-event 覆盖）
local function BuildPackCandidates(globalCfg)
    local list = {}
    local function Add(name)
        if type(name) ~= "string" or name == "" then return end
        for _, v in ipairs(list) do if v == name then return end end
        list[#list + 1] = name
    end
    Add(globalCfg and globalCfg.selectedVoicePack)
    -- 若所选包的文件无法播放，按客户端语言回退到标准包；不检查 AddOn 启用状态。
    Add(GetLocaleFallbackVoicePack())
    return list
end

local function ResolvePackSoundPath(packName, label)
    local manifest = ExBoss and ExBoss.Voice and ExBoss.Voice.PackManifest
    local files = type(manifest) == "table" and manifest.files or nil
    local fileName = type(files) == "table" and files[tostring(label or "")] or nil
    local addon = GetVoicePackDirectory(packName)
    if type(fileName) ~= "string" or fileName == "" or type(addon) ~= "string" or addon == "" then
        return nil
    end
    return "Interface\\AddOns\\" .. addon .. "\\Sounds\\" .. fileName .. ".ogg"
end

local function ResolvePackLabelSoundPath(packName, label)
    local path = ResolvePackSoundPath(packName, label)
    if path then
        return path
    end
    local aliases = BuildCountdownLabelAliases(label)
    if aliases then
        for i = 1, #aliases do
            path = ResolvePackSoundPath(packName, aliases[i])
            if path then
                return path
            end
        end
    end
    return nil
end

local function ResolveStandardPackPaths(globalCfg, label)
    local primary, fallback
    for _, pack in ipairs(BuildPackCandidates(globalCfg)) do
        local path = ResolvePackLabelSoundPath(pack, label)
        if path then
            if not primary then
                primary = path
            elseif path ~= primary then
                fallback = path
                break
            end
        end
    end
    return primary, fallback
end

local function ResolveLabelSoundInfo(globalCfg, eventCfg, label)
    label = tostring(label or "")
    if label == "" then return nil end

    local soundPath = nil

    -- 1. event 自定义 LSM key（直接 LSM key，bypass 语音包逻辑）
    local customLSM = eventCfg and eventCfg.customLSM
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if type(customLSM) == "string" and customLSM ~= "" and LSM then
        soundPath = LSM:Fetch("sound", customLSM, true)
    end

    -- 2. 标准语音包：核心映射 + 已选 AddOn 目录，直接播放文件。
    local fallbackPath = nil
    if not soundPath then
        soundPath, fallbackPath = ResolveStandardPackPaths(globalCfg, label)
    end

    if not soundPath then return nil end

    return {
        file    = soundPath,
        fallbackFile = fallbackPath,
        channel = (eventCfg and eventCfg.channel) or globalCfg.channel or "Master",
        volume  = (eventCfg and eventCfg.volume)  or globalCfg.volume  or 1.0,
    }
end

local function TryPlaySoundInfo(soundInfo, throttleKey, opts)
    if type(soundInfo) ~= "table" then
        return false, "invalid sound info"
    end
    if soundInfo.isTTS then
        local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
        if voices and #voices > 0 then
            local rate = C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate() or 0
            pcall(C_VoiceChat.SpeakText, voices[1].voiceID, soundInfo.ttsText, rate, 100)
        end
        return true
    end
    if type(soundInfo.file) ~= "string" or soundInfo.file == "" then
        return false, "invalid sound info"
    end
    opts = type(opts) == "table" and opts or nil
    local now = GetTime and GetTime() or 0
    local throttleEnabled = not (opts and opts.throttle == false)
    local tk = tostring(throttleKey or "default")
    if throttleEnabled then
        if _lastPlayTime[tk] and (now - _lastPlayTime[tk]) < PLAY_THROTTLE then
            return false, "throttled"
        end
    end
    local channel = soundInfo.channel or "Master"
    local ok = PlaySoundFile and PlaySoundFile(soundInfo.file, channel)
    if not ok and type(soundInfo.fallbackFile) == "string" and soundInfo.fallbackFile ~= "" then
        ok = PlaySoundFile and PlaySoundFile(soundInfo.fallbackFile, channel)
    end
    if ok then
        if throttleEnabled then
            _lastPlayTime[tk] = now
        end
        return true
    end
    return false, "PlaySoundFile failed"
end

local function ResolveTriggerSound(globalCfg, triggerCfg, triggerIndex)
    if type(triggerCfg) ~= "table" then return nil end
    if triggerCfg.enabled == false    then return nil end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local sourceType = tostring(triggerCfg.sourceType or ""):lower()
    local file
    local fallbackFile

    local function FetchSoundByKey(key)
        if not (LSM and type(key) == "string" and key ~= "") then
            return nil
        end
        local path = LSM:Fetch("sound", key, true)
        if path and path ~= "" then
            return path
        end
        local tbl = LSM:HashTable("sound")
        local raw = type(tbl) == "table" and tbl[key] or nil
        if type(raw) == "string" and raw ~= "" then
            return raw
        end
        return nil
    end

    if sourceType == "tts" then
        local text = tostring(triggerCfg.ttsText or "")
        if text == "" then return nil end
        return { isTTS = true, ttsText = text }
    elseif sourceType == "file" and triggerCfg.customPath and triggerCfg.customPath ~= "" then
        file = triggerCfg.customPath
    elseif sourceType == "lsm" and triggerCfg.customLSM and triggerCfg.customLSM ~= "" and LSM then
        file = FetchSoundByKey(triggerCfg.customLSM)
    else
        local label = ResolvePackTriggerLabel(triggerCfg, triggerIndex)
        if label and label ~= "" then
            file, fallbackFile = ResolveStandardPackPaths(globalCfg, label)
        end
    end

    if not file or file == "" then return nil end

    return {
        file    = file,
        fallbackFile = fallbackFile,
        channel = globalCfg.channel or "Master",
        volume  = tonumber(globalCfg.volume) or 1.0,
    }
end

local function NormalizeStandaloneTriggerConfig(triggerCfg)
    if type(triggerCfg) ~= "table" then
        return nil
    end

    local sourceType = tostring(triggerCfg.sourceType or "pack"):lower()
    if sourceType ~= "lsm" and sourceType ~= "file" and sourceType ~= "tts" then
        sourceType = "pack"
    end

    return {
        enabled = (triggerCfg.enabled ~= false),
        sourceType = sourceType,
        label = tostring(triggerCfg.label or ""),
        customLSM = tostring(triggerCfg.customLSM or ""),
        customPath = tostring(triggerCfg.customPath or ""),
        ttsText = tostring(triggerCfg.ttsText or ""),
    }
end

local function HasMeaningfulTriggerSource(triggerCfg)
    if type(triggerCfg) ~= "table" then
        return false
    end
    local sourceType = tostring(triggerCfg.sourceType or ""):lower()
    if sourceType == "file" then
        return type(triggerCfg.customPath) == "string" and triggerCfg.customPath ~= ""
    end
    if sourceType == "lsm" then
        return type(triggerCfg.customLSM) == "string" and triggerCfg.customLSM ~= ""
    end
    return type(triggerCfg.label) == "string" and triggerCfg.label ~= ""
end

-- ── 公开 API ──────────────────────────────────────────────────────────────

function Engine:InvalidateLabelCache()
    _labelPackCache = {}
end

function Engine:RefreshSelectedVoicePackForLocale(opts)
    opts = type(opts) == "table" and opts or {}
    local db = EnsureDB()
    local g = db.global or {}
    local before = tostring(g.selectedVoicePack or "")

    if ShouldForceEnglishVoicePack(g) then g.selectedVoicePack = ENGLISH_VOICE_PACK end
    g.selectedVoicePack = g.selectedVoicePack or ResolveDefaultVoicePack()

    local after = tostring(g.selectedVoicePack or "")
    if before == after then
        return false, after
    end

    self:InvalidateLabelCache()

    if opts.applyOverrides ~= false and self.ApplyEventOverridesToAPI then
        local _, instanceType = GetInstanceInfo()
        if instanceType == "party" or instanceType == "raid" then
            C_Timer.After(0, function()
                self:ApplyEventOverridesToAPI()
            end)
        end
    end

    return true, after
end

function Engine:ResolveStandaloneSound(triggerCfg, opts)
    opts = type(opts) == "table" and opts or {}
    local db = EnsureDB()
    local g = db.global
    if opts.ignoreState ~= true and g.enabled == false then
        return nil, "voice disabled"
    end
    if opts.ignoreState ~= true and not IsContextEnabled(g) then
        return nil, "context disabled"
    end

    local normalized = NormalizeStandaloneTriggerConfig(triggerCfg)
    if not normalized then
        return nil, "invalid trigger cfg"
    end

    local soundInfo = ResolveTriggerSound(g, normalized, opts.triggerIndex)
    if not soundInfo then
        return nil, "sound not found"
    end
    return soundInfo
end

local function DebugTrashStandaloneVoice(throttleKey, stage, detail)
    local key = tostring(throttleKey or "")
    if not key:match("^trash%-cast:") then
        return
    end
    local controller = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Runtime or nil
    if not (controller and type(controller.AppendExternalDebug) == "function") then
        return
    end
    if type(controller.IsDebug) == "function" and controller.IsDebug() ~= true then
        return
    end
    controller.AppendExternalDebug("TrashCD PreviewVoice", string.format(
        "engine-%s %s", tostring(stage or "?"), tostring(detail or "")), true)
end

local function DebugTrashTimerVoice(timer, stage, detail)
    if type(timer) ~= "table" or tostring(timer.source or "") ~= "trash" then
        return
    end
    local controller = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Runtime or nil
    if not (controller and type(controller.AppendExternalDebug) == "function") then
        return
    end
    if type(controller.IsDebug) == "function" and controller.IsDebug() ~= true then
        return
    end
    local runtime = type(timer.trashRuntime) == "table" and timer.trashRuntime or nil
    controller.AppendExternalDebug("TrashCD Voice", string.format(
        "timer-%s spell=%s lock=%s %s", tostring(stage or "?"),
        tostring(timer.spellID or "nil"),
        tostring(runtime and runtime.identityLockedNPCID or "none"),
        tostring(detail or "")), true)
end

function Engine:TryPlayStandaloneSound(triggerCfg, throttleKey, opts)
    local soundInfo, err = self:ResolveStandaloneSound(triggerCfg, opts)
    if not soundInfo then
        DebugTrashStandaloneVoice(throttleKey, "resolve-deny", tostring(err or "unknown"))
        return false, err
    end
    local normalized = NormalizeStandaloneTriggerConfig(triggerCfg) or {}
    local sourceType = tostring(normalized.sourceType or "pack")
    local sourceDetail
    if soundInfo.isTTS then
        local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
        sourceDetail = "source=tts voices=" .. tostring(type(voices) == "table" and #voices or 0)
    else
        sourceDetail = "source=" .. sourceType
            .. " channel=" .. tostring(soundInfo.channel or "Master")
            .. " file=" .. tostring(soundInfo.file or "")
    end
    DebugTrashStandaloneVoice(throttleKey, "resolved", sourceDetail)

    local ok, playErr = TryPlaySoundInfo(soundInfo, tostring(throttleKey or "standalone"), opts)
    DebugTrashStandaloneVoice(throttleKey, ok and "queued" or "play-deny",
        sourceDetail .. " err=" .. tostring(playErr or "nil"))
    return ok, playErr
end

function Engine:TryPlayLabel(label, timer, opts)
    local db = EnsureDB()
    local g  = db.global
    if g.enabled == false    then return false, "voice disabled"   end
    if not IsContextEnabled(g) then return false, "context disabled" end

    local eventCfg = ResolveEventConfig(db, timer)
    if eventCfg and eventCfg.enabled == false then
        return false, "event muted"
    end

    local info = ResolveLabelSoundInfo(g, eventCfg, label)
    if not info then return false, "sound not found" end
    opts = type(opts) == "table" and opts or nil
    local source = type(timer) == "table" and tostring(timer.source or "") or ""
    if not opts and type(timer) == "table" and source:find("preview", 1, true) == nil then
        opts = { throttle = false }
    end
    return TryPlaySoundInfo(info, "label:" .. tostring(label), opts)
end

function Engine:TryPlayForTimer(timer, trigger)
    if not timer then return false, "nil timer" end
    local db = EnsureDB()
    local g  = db.global
    if g.enabled == false then
        DebugTrashTimerVoice(timer, "deny", "voice-disabled")
        return false, "voice disabled"
    end
    if not IsContextEnabled(g) then
        DebugTrashTimerVoice(timer, "deny", "context-disabled")
        return false, "context disabled"
    end

    local eventCfg, eventKey = ResolveEventConfig(db, timer)
    if eventCfg and eventCfg.enabled == false then
        DebugTrashTimerVoice(timer, "deny", "event-muted")
        return false, "event muted"
    end

    trigger = tonumber(trigger) or 2
    if eventCfg and type(eventCfg.triggers) == "table" then
        local triggerCfg  = eventCfg.triggers[trigger]
        if type(triggerCfg) == "table" and triggerCfg.enabled == false then
            DebugTrashTimerVoice(timer, "deny", "trigger-muted trigger=" .. tostring(trigger))
            return false, "trigger muted"
        end
        local triggerSound = ResolveTriggerSound(g, triggerCfg, trigger)
        if triggerSound then
            local tk = "event:" .. tostring(eventKey or "unknown") .. ":tr:" .. tostring(trigger)
            local ok, err = TryPlaySoundInfo(triggerSound, tk, { throttle = false })
            DebugTrashTimerVoice(timer, ok and "event-queued" or "event-deny",
                "trigger=" .. tostring(trigger) .. " source=" .. tostring(triggerCfg.sourceType or "pack")
                .. " file=" .. tostring(triggerSound.file or "tts") .. " err=" .. tostring(err or "nil"))
            return ok, err
        end
    end

    local label = type(eventCfg) == "table" and eventCfg.voiceLabel or nil
    if label == nil or label == "" then
        label = timer.voiceLabel
    end
    if not label then
        DebugTrashTimerVoice(timer, "deny", "no-label")
        return false, "no label"
    end

    local soundInfo = ResolveLabelSoundInfo(g, eventCfg, label)
    if not soundInfo then
        DebugTrashTimerVoice(timer, "deny", "sound-not-found label=" .. tostring(label))
        return false, "sound not found"
    end

    local tk = "timer:" .. tostring(eventKey or "noevent") .. ":" .. tostring(label)
    local ok, err = TryPlaySoundInfo(soundInfo, tk, { throttle = false })
    DebugTrashTimerVoice(timer, ok and "label-queued" or "label-deny",
        "label=" .. tostring(label) .. " file=" .. tostring(soundInfo.file or "tts")
        .. " err=" .. tostring(err or "nil"))
    return ok, err
end

-- ── C_EncounterEvents 注册：分批（10条/批，批间隔1秒）───────────────────

local function ResolveApplyScope(opts)
    opts = type(opts) == "table" and opts or {}
    local state = ExwindTools and ExwindTools.State or nil

    local inInstance = (opts.inInstance ~= nil) and (opts.inInstance == true)
    if opts.inInstance == nil then
        inInstance = (state and state.InInstance == true) or false
    end
    if not inInstance then
        return nil, "not in instance"
    end

    local instanceType = tostring(opts.instanceType or (state and state.InstanceType) or ""):lower()
    if instanceType == "" then
        local ok, ii, it = pcall(IsInInstance)
        if ok and ii then
            instanceType = tostring(it or ""):lower()
        end
    end
    if instanceType ~= "party" and instanceType ~= "raid" then
        return nil, "unsupported instanceType: " .. tostring(instanceType)
    end

    local instanceID = tonumber(opts.instanceID or (state and state.InstanceID)) or 0
    if instanceID <= 0 then
        local _, _, _, _, _, _, _, runtimeInstanceID = GetInstanceInfo()
        instanceID = tonumber(runtimeInstanceID) or 0
    end
    if instanceID <= 0 then
        return nil, "instanceID unavailable"
    end

    local encounterID = tonumber(opts.encounterID)
    if (not encounterID or encounterID <= 0) and opts.useEncounterState == true then
        encounterID = tonumber(state and state.EncounterID) or 0
    end
    if encounterID and encounterID <= 0 then
        encounterID = nil
    end

    return {
        instanceID = instanceID,
        mapID = tonumber(opts.mapID or (state and state.MapID)) or nil, -- 仅用于展示
        encounterID = encounterID,
        instanceType = instanceType,
        reason = tostring(opts.reason or ""),
    }, nil
end

local function MatchRefsForScope(eventID, scope, bossMap)
    local refs = bossMap and bossMap[tonumber(eventID)] or nil
    if type(refs) ~= "table" or #refs == 0 then
        return {}
    end
    if type(scope) ~= "table" then
        return refs
    end
    local scopeInstanceID = tonumber(scope.instanceID)
    local scopeEncounterID = tonumber(scope.encounterID)
    local out = {}
    for i = 1, #refs do
        local ref = refs[i]
        local refInstanceID = tonumber(ref and ref.instanceID)
        local refEncounterID = tonumber(ref and ref.encounterID)
        local instanceOK = (scopeInstanceID == nil) or (scopeInstanceID == refInstanceID)
        local encounterOK = (scopeEncounterID == nil) or (scopeEncounterID == refEncounterID)
        if instanceOK and encounterOK then
            out[#out + 1] = ref
        end
    end
    return out
end

local function ResolveEncounterMode(encounterID, modeCache)
    local id = tonumber(encounterID)
    if not id then
        return "blizzard"
    end
    if type(modeCache) == "table" and modeCache[id] then
        return modeCache[id]
    end

    local mode = "blizzard"
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and type(sched.GetMode) == "function" then
        local resolved = sched:GetMode(id)
        local m = tostring(resolved or ""):lower()
        if m == "fixed" or m == "blizzard" then
            mode = m
        end
    end

    if type(modeCache) == "table" then
        modeCache[id] = mode
    end
    return mode
end

local function IsCentralTriggerChecked(cfg)
    local triggers = cfg and cfg.triggers
    local trigger0 = type(triggers) == "table" and triggers[0] or nil
    return type(trigger0) == "table" and trigger0.enabled == true
end

local function EvaluateRegistrationPolicy(eventID, cfg, refs, modeCache)
    local allowedRefs = {}
    local allowMask = 0
    local sawFixed = false
    local sawNonFixed = false
    local centralChecked = IsCentralTriggerChecked(cfg)

    for i = 1, #refs do
        local ref = refs[i]
        local mode = ResolveEncounterMode(ref and ref.encounterID, modeCache)
        if mode == "fixed" then
            sawFixed = true
            if centralChecked then
                allowMask = AddTriggerBit(allowMask, 0)
                local copy = {}
                for k, v in pairs(ref) do copy[k] = v end
                copy.mode = "fixed"
                allowedRefs[#allowedRefs + 1] = copy
            end
        else
            sawNonFixed = true
            allowMask = AddTriggerBit(AddTriggerBit(AddTriggerBit(allowMask, 0), 1), 2)
            local copy = {}
            for k, v in pairs(ref) do copy[k] = v end
            copy.mode = "blizzard"
            allowedRefs[#allowedRefs + 1] = copy
        end
    end

    if #allowedRefs == 0 or allowMask == 0 then
        return nil
    end

    local mode = "blizzard"
    local policy = "non-fixed"
    if sawFixed and not sawNonFixed then
        mode = "fixed"
        policy = "fixed-central-only"
    elseif sawFixed and sawNonFixed then
        mode = "mixed"
        policy = "mixed"
    end

    return {
        allowMask = allowMask,
        mode = mode,
        policy = policy,
        refs = allowedRefs,
    }
end

local function GetEventsForScope(scope)
    if type(scope) ~= "table" then return {} end
    local runtime = GetSceneRuntime(scope.instanceType == "raid" and "raid" or "mplus")
    return type(runtime) == "table" and type(runtime.events) == "table" and runtime.events or {}
end

local function CollectEventEntries(db, scope)
    local entries = {}
    local visited = {}
    local bossMap = BuildEventBossIndex()
    local globalCfg = db.global or {}
    local modeCache = {}
    for key, cfg in pairs(GetEventsForScope(scope)) do
        local eventID = NormalizeEventID(key, cfg)
        if eventID and type(cfg) == "table" and not visited[eventID] then
            visited[eventID] = true
            local refs = MatchRefsForScope(eventID, scope, bossMap)
            if #refs > 0 then
                local policy = EvaluateRegistrationPolicy(eventID, cfg, refs, modeCache)
                if policy then
                    local triggerSounds = {}
                    local triggerMask = 0
                    local triggers = cfg.triggers
                    for trigger = 0, 2 do
                        if HasTriggerBit(policy.allowMask, trigger) then
                            local triggerCfg = type(triggers) == "table" and triggers[trigger] or nil
                            local soundInfo = ResolveTriggerSound(globalCfg, triggerCfg, trigger)
                            if soundInfo then
                                triggerMask = AddTriggerBit(triggerMask, trigger)
                                triggerSounds[trigger] = soundInfo
                            end
                        end
                    end

                    local hasColor = (cfg.enabled ~= false) and (ResolveEventColor(cfg.color) ~= nil)
                    if triggerMask ~= 0 or hasColor then
                        entries[#entries + 1] = {
                            eventID = eventID,
                            cfg = cfg,
                            globalCfg = globalCfg,
                            triggerMask = triggerMask,
                            triggerSounds = triggerSounds,
                            hasColor = hasColor,
                            mode = policy.mode,
                            policy = policy.policy,
                            refs = policy.refs,
                        }
                    end
                end
            end
        end
    end
    return entries
end

local function ApplyOneEntry(entry)
    if not C_EncounterEvents then return end
    local eventID   = entry.eventID
    local cfg       = entry.cfg
    local globalCfg = entry.globalCfg

    local eventEnabled = (cfg.enabled ~= false)

    if C_EncounterEvents.SetEventColor then
        if not eventEnabled then
            pcall(C_EncounterEvents.SetEventColor, eventID, nil)
        else
            local r, g, b = ResolveEventColor(cfg.color)
            if r ~= nil and g ~= nil and b ~= nil then
                local color = CreateColor and CreateColor(r, g, b) or { r=r, g=g, b=b }
                pcall(C_EncounterEvents.SetEventColor, eventID, color)
            else
                pcall(C_EncounterEvents.SetEventColor, eventID, nil)
            end
        end
    end

    if C_EncounterEvents.SetEventSound then
        for trigger = 0, 2 do
            local soundInfo = nil
            if eventEnabled then
                soundInfo = type(entry.triggerSounds) == "table" and entry.triggerSounds[trigger] or nil
            end
            if soundInfo and soundInfo.isTTS then soundInfo = nil end
            pcall(C_EncounterEvents.SetEventSound, eventID, trigger, soundInfo)
        end
    end
end

-- 首次进本/重载后需要尽快把颜色与语音覆盖下发完成，
-- 否则开场第一轮技能可能命中默认色。
local BATCH_SIZE     = 500
local BATCH_INTERVAL = 0.05
local _applyScheduleToken = 0

local function RefreshTimelineVisuals()
    if ExBoss and ExBoss.UI then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshVisuals then
            pcall(function()
                ExBoss.UI.TimerBar:RefreshVisuals()
            end)
        end
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshVisuals then
            pcall(function()
                ExBoss.UI.BunBar:RefreshVisuals()
            end)
        end
    end
end

local function ApplyOneColorEntry(entry)
    if not (C_EncounterEvents and C_EncounterEvents.SetEventColor) then
        return false
    end
    local eventID = entry.eventID
    local cfg = entry.cfg
    local eventEnabled = (cfg and cfg.enabled ~= false)

    if not eventEnabled then
        pcall(C_EncounterEvents.SetEventColor, eventID, nil)
        return true
    end

    local r, g, b = ResolveEventColor(cfg and cfg.color or nil)
    if r ~= nil and g ~= nil and b ~= nil then
        local color = CreateColor and CreateColor(r, g, b) or { r = r, g = g, b = b }
        pcall(C_EncounterEvents.SetEventColor, eventID, color)
    else
        pcall(C_EncounterEvents.SetEventColor, eventID, nil)
    end
    return true
end

local function ApplyInBatches(entries)
    if not C_EncounterEvents then return end
    local total = #entries
    local idx   = 1

    local function DoNextBatch()
        if idx > total then
            RefreshTimelineVisuals()
            return
        end
        local limit = math.min(idx + BATCH_SIZE - 1, total)
        for i = idx, limit do
            ApplyOneEntry(entries[i])
        end
        -- C_EncounterEvents 颜色/语音分批下发后，立即刷新现有条体，
        -- 避免先出现的时间轴条停留在旧颜色。
        RefreshTimelineVisuals()
        idx = limit + 1
        if idx <= total then
            C_Timer.After(BATCH_INTERVAL, DoNextBatch)
        end
    end

    DoNextBatch()
end

local ClearOneEntryByEventID

function Engine:ApplyEventOverridesToAPI(opts)
    local db = EnsureDB()
    if not C_EncounterEvents then
        _lastRegistrationError = "C_EncounterEvents unavailable"
        return false, "C_EncounterEvents unavailable"
    end
    if C_EncounterEvents.SetEventSound and not EnsureEncounterWarningsEnabled() then
        _lastRegistrationError = "encounter warnings disabled"
        return false, _lastRegistrationError
    end

    local scope, scopeErr = ResolveApplyScope(opts)
    if not scope then
        _lastRegistrationError = scopeErr or "scope invalid"
        return false, _lastRegistrationError
    end

    local scene = nil
    if scope.instanceType == "party" then scene = "mplus" end
    if scope.instanceType == "raid" then scene = "raid" end
    if scene and not IsBossSceneEnabled(scene) then
        Engine:ClearEventOverridesInMemory("boss scene disabled")
        return false, "boss scene disabled"
    end

    local entries = CollectEventEntries(db, scope)
    local prevSet = {}
    for eid in pairs(_registeredEventSet) do
        prevSet[eid] = true
    end

    WipeTable(_registeredEventSet)
    WipeTable(_registeredEventMeta)
    _registeredEventCount = 0
    for i = 1, #entries do
        local entry = entries[i]
        local eid = entry and tonumber(entry.eventID)
        if eid and not _registeredEventSet[eid] then
            _registeredEventSet[eid] = true
            _registeredEventMeta[eid] = {
                eventID = eid,
                triggerMask = tonumber(entry.triggerMask) or 0,
                mode = tostring(entry.mode or ""),
                policy = tostring(entry.policy or ""),
                refs = entry.refs,
            }
            _registeredEventCount = _registeredEventCount + 1
        end
    end

    for eid in pairs(prevSet) do
        if not _registeredEventSet[eid] then
            ClearOneEntryByEventID(eid)
        end
    end

    _lastApplyScope = {
        instanceID = scope.instanceID,
        mapID = scope.mapID,
        encounterID = scope.encounterID,
        instanceType = scope.instanceType,
        reason = scope.reason,
    }
    _lastRegistrationError = nil
    _lastRegistrationSnapshot = BuildRegistrationSnapshot(_registeredEventMeta, _registeredEventCount, {
        scope = _lastApplyScope,
    })
    ApplyInBatches(entries)
    return true
end

ClearOneEntryByEventID = function(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return
    end
    if C_EncounterEvents and C_EncounterEvents.SetEventSound then
        for trigger = 0, 2 do
            pcall(C_EncounterEvents.SetEventSound, eid, trigger, nil)
        end
    end
    if C_EncounterEvents and C_EncounterEvents.SetEventColor then
        pcall(C_EncounterEvents.SetEventColor, eid, nil)
    end
end

function Engine:ClearEventOverridesInMemory(reason)
    reason = tostring(reason or "")
    for eventID in pairs(_registeredEventSet) do
        ClearOneEntryByEventID(eventID)
    end
    WipeTable(_registeredEventSet)
    WipeTable(_registeredEventMeta)
    _registeredEventCount = 0
    _lastApplyScope = nil
    _lastRegistrationError = (reason ~= "" and reason) or "cleared"
    _lastRegistrationSnapshot = BuildRegistrationSnapshot(_registeredEventMeta, _registeredEventCount, {
        scope = nil,
    })
end

function Engine:ApplyEventColorOverridesToAPI(opts)
    local db = EnsureDB()
    if not (C_EncounterEvents and C_EncounterEvents.SetEventColor) then
        return false, "SetEventColor unavailable", 0
    end
    local scope, scopeErr = ResolveApplyScope(opts)
    if not scope then
        return false, scopeErr or "scope invalid", 0
    end
    local entries = CollectEventEntries(db, scope)
    local count = 0
    for i = 1, #entries do
        if ApplyOneColorEntry(entries[i]) then
            count = count + 1
        end
    end
    RefreshTimelineVisuals()
    return true, nil, count
end

function Engine:ScheduleApplyEventOverrides(delays)
    delays = type(delays) == "table" and delays or { 1, 3, 5 }
    _applyScheduleToken = _applyScheduleToken + 1
    local token = _applyScheduleToken
    for _, delay in ipairs(delays) do
        local d = tonumber(delay) or 0
        if d < 0 then d = 0 end
        C_Timer.After(d, function()
            if token ~= _applyScheduleToken then
                return
            end
            local ok, err = Engine:ApplyEventOverridesToAPI({
                reason = "schedule:" .. tostring(d),
            })
            local _, instanceType = GetInstanceInfo()
--                 "|cffff4400Ex|r|cff00ccffBoss|r 颜色+语音注册执行 delay=%.1fs ctx=%s result=%s%s",
--                 d,
--                 tostring(instanceType or "unknown"),
--                 tostring(ok),
--                 err and (" err=" .. tostring(err)) or ""
--             ))
        end)
    end
end

function Engine:GetRegistrationSnapshot(opts)
    opts = type(opts) == "table" and opts or {}
    local includeRaid = (opts.includeRaid ~= false)
    if type(_lastRegistrationSnapshot) == "table" then
        if includeRaid == true and (not _lastRegistrationSnapshot.scopeInstanceID or _lastRegistrationSnapshot.scopeInstanceID > 0) then
            return _lastRegistrationSnapshot
        end
        return BuildRegistrationSnapshot(_registeredEventMeta, _registeredEventCount, {
            includeRaid = false,
            scope = _lastApplyScope,
        })
    end

    local scope, scopeErr = ResolveApplyScope(opts)
    if not scope then
        return {
            eventCount = 0,
            rawEventCount = 0,
            bossCount = 0,
            trigger0Events = 0,
            trigger1Events = 0,
            trigger2Events = 0,
            orphanEventCount = 0,
            filteredOutByRaid = 0,
            includeRaid = includeRaid,
            scopeInstanceID = nil,
            scopeMapID = nil,
            scopeMapName = "",
            scopeEncounterID = nil,
            scopeInstanceType = "",
            scopeReason = tostring(opts.reason or ""),
            updatedAt = date and date("%Y-%m-%d %H:%M:%S") or "",
            rows = {},
            error = scopeErr or "scope invalid",
            isPreview = true,
        }
    end

    local db = EnsureDB()
    local entries = CollectEventEntries(db, scope)
    local previewMeta = {}
    local previewCount = 0
    for i = 1, #entries do
        local entry = entries[i]
        local eid = entry and tonumber(entry.eventID)
        if eid and not previewMeta[eid] then
            previewMeta[eid] = {
                eventID = eid,
                triggerMask = tonumber(entry.triggerMask) or 0,
                mode = tostring(entry.mode or ""),
                policy = tostring(entry.policy or ""),
                refs = entry.refs,
            }
            previewCount = previewCount + 1
        end
    end

    local snap = BuildRegistrationSnapshot(previewMeta, previewCount, {
        includeRaid = includeRaid,
        scope = scope,
    })
    snap.isPreview = true
    return snap
end

-- ── 注册时机：仅在副本内注册当前本；ENCOUNTER_START 补注册 ───────────

if ExwindTools and not Engine._eventsRegistered then
    local function ApplyCurrentInstance(reason, encounterID)
        local opts = {
            reason = tostring(reason or ""),
            encounterID = tonumber(encounterID),
            useEncounterState = (encounterID == nil),
        }
        local ok, err = Engine:ApplyEventOverridesToAPI(opts)
        if not ok and tostring(err) == "not in instance" then
            Engine:ClearEventOverridesInMemory("not in instance")
        end
    end

    ExwindTools:WatchState("InInstance", "ExBossVoice.Engine.InInstanceScope", function(newValue)
        if newValue == true then
            C_Timer.After(0.1, function()
                ApplyCurrentInstance("state:InInstance=true", nil)
            end)
        else
            Engine:ClearEventOverridesInMemory("state:InInstance=false")
        end
    end)

    ExwindTools:WatchState("InstanceID", "ExBossVoice.Engine.InstanceScope", function(newID, oldID)
        if tonumber(newID) == tonumber(oldID) then
            return
        end
        if ExwindTools.State and ExwindTools.State.InInstance == true then
            C_Timer.After(0.1, function()
                ApplyCurrentInstance("state:InstanceID", nil)
            end)
        end
    end)

    ExwindTools:WatchState("RoleKey", "ExBossVoice.Engine.RoleScope", function()
        if ExwindTools.State and ExwindTools.State.InInstance == true then
            C_Timer.After(0.05, function()
                ApplyCurrentInstance("state:RoleKey", nil)
            end)
        end
    end)

    ExwindTools:WatchState("SpecID", "ExBossVoice.Engine.SpecScope", function(newID, oldID)
        if tonumber(newID) == tonumber(oldID) then
            return
        end
        if ExwindTools.State and ExwindTools.State.InInstance == true then
            C_Timer.After(0.05, function()
                ApplyCurrentInstance("state:SpecID", nil)
            end)
        end
    end)

    ExwindTools:WatchState("ExBoss.BossConfig.SelectionChanged", "ExBossVoice.Engine.BossSelection", function()
        if ExwindTools.State and ExwindTools.State.InInstance == true then
            C_Timer.After(0, function()
                ApplyCurrentInstance("state:BossSelection", nil)
            end)
        end
    end)

    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBossVoice.Engine.OnPEW", function()
        C_Timer.After(0.2, function()
            Engine:RefreshSelectedVoicePackForLocale({
                applyOverrides = true,
            })
            ApplyCurrentInstance("event:PLAYER_ENTERING_WORLD", nil)
        end)
    end)

    ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBossVoice.Engine.OnEncounterStart", function(_, encounterID)
        C_Timer.After(0, function()
            ApplyCurrentInstance("event:ENCOUNTER_START", encounterID)
        end)
    end)

    ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBossVoice.Engine.OnEncounterEnd", function()
        -- 首领战结束后回到副本级作用域（去掉 encounter 级收窄）
        C_Timer.After(0, function()
            ApplyCurrentInstance("event:ENCOUNTER_END", nil)
        end)
    end)

    -- 初始化补一次（支持副本中 /reload）
    C_Timer.After(0.5, function()
        Engine:RefreshSelectedVoicePackForLocale({
            applyOverrides = false,
        })
        ApplyCurrentInstance("init:delayed", nil)
    end)

    Engine._eventsRegistered = true
end
