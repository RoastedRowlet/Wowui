---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Store = ExBoss.TrashCD.Store or {}
ExBoss.TrashCD.Store = Store
ExBoss.Trash.Store = Store

local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local out = {}
    for key, value in pairs(src) do
        out[key] = DeepCopy(value)
    end
    return out
end

local NormalizeSpellEntry

local function GetFactoryResolver()
    local resolver = _G.EXBossData and _G.EXBossData.FactoryResolver
    return type(resolver) == "table" and resolver or nil
end

local function GetFactoryTrashRoot()
    local resolver = GetFactoryResolver()
    local factoryID = resolver and type(resolver.GetMplusFactoryID) == "function" and resolver.GetMplusFactoryID() or nil
    local base = resolver and type(resolver.GetMplusBase) == "function" and resolver.GetMplusBase(factoryID) or nil
    local trash = type(base) == "table" and base.trashCD or nil
    return type(trash) == "table" and trash or nil
end

local function GetFactorySpellEntryTemplate()
    local resolver = GetFactoryResolver()
    local factoryID = resolver and type(resolver.GetMplusFactoryID) == "function" and resolver.GetMplusFactoryID() or nil
    local factory = resolver and type(resolver.GetFactory) == "function" and resolver.GetFactory(factoryID) or nil
    local template = type(factory) == "table" and type(factory.base) == "table"
        and type(factory.base.trashCD) == "table" and factory.base.trashCD.spellEntryDefaults or nil
    return type(template) == "table" and template or nil
end

local function IsKnownTopLevelKey(key)
    local root = GetFactoryTrashRoot()
    return type(key) == "string" and type(root) == "table" and type(root.settings) == "table"
        and root.settings[key] ~= nil
end

function Store.GetFactoryConfigBase()
    local root = GetFactoryTrashRoot()
    return type(root) == "table" and DeepCopy(root) or nil
end

function Store.GetDefaults()
    local root = GetFactoryTrashRoot()
    return type(root) == "table" and DeepCopy(root.settings) or {}
end

function Store.GetSpellEntryDefaults()
    local template = GetFactorySpellEntryTemplate()
    return type(template) == "table" and DeepCopy(template) or {}
end

function Store.GetSpellEntryKey(mapID, npcID, spellID)
    local mid = tonumber(mapID)
    local nid = tonumber(npcID)
    local sid = tonumber(spellID)
    if not mid or not nid or not sid then
        return nil
    end
    return string.format("%d:%d:%d", mid, nid, sid)
end


function NormalizeSpellEntry(row)
    local defaults = GetFactorySpellEntryTemplate() or {}
    row = type(row) == "table" and row or {}
    row.enabled = row.enabled == true
    row.showBunBar = row.showBunBar ~= false
    row.showTimerBar = row.showTimerBar ~= false
    row.showNameplate = row.showNameplate == true
    if type(row.bossStages) ~= "string" then
        row.bossStages = defaults.bossStages or ""
    end
    if type(row.customName) ~= "string" then
        row.customName = defaults.customName or ""
    end
    row.eventColorEnabled = row.eventColorEnabled == true
    if type(row.eventColorMode) ~= "string" then
        row.eventColorMode = defaults.eventColorMode or "none"
    end
    if type(row.eventColor) ~= "table" then
        row.eventColor = DeepCopy(defaults.eventColor or {})
    end
    row.eventColor.r = tonumber(row.eventColor.r) or tonumber(defaults.eventColor and defaults.eventColor.r) or 1
    row.eventColor.g = tonumber(row.eventColor.g) or tonumber(defaults.eventColor and defaults.eventColor.g) or 1
    row.eventColor.b = tonumber(row.eventColor.b) or tonumber(defaults.eventColor and defaults.eventColor.b) or 1
    row.eventColor.a = tonumber(row.eventColor.a) or tonumber(defaults.eventColor and defaults.eventColor.a) or 1
    row.centralEnabled = row.centralEnabled == true
    local centralLead = tonumber(row.centralLead)
    row.centralLead = centralLead and centralLead or tonumber(defaults.centralLead) or 0
    if type(row.centralText) ~= "string" then
        row.centralText = defaults.centralText or ""
    end
    row.countdownEnabled = row.countdownEnabled == true
    local countdownLead = tonumber(row.countdownLead)
    row.countdownLead = countdownLead and countdownLead or tonumber(defaults.countdownLead) or 5
    row.countdownVoiceEnabled = row.countdownVoiceEnabled == true
    row.countdownPlayName = row.countdownPlayName == true
    row.preAlertEnabled = row.preAlertEnabled == true
    if type(row.countdownText) ~= "string" then
        row.countdownText = defaults.countdownText or ""
    end
    row.timerBarRenameEnabled = row.timerBarRenameEnabled == true
    if type(row.timerBarName) ~= "string" then
        row.timerBarName = defaults.timerBarName or ""
    end
    row.ringEnabled = row.ringEnabled == true
    row.ringRenameEnabled = row.ringRenameEnabled == true
    if type(row.ringRenameText) ~= "string" then
        row.ringRenameText = defaults.ringRenameText or ""
    end
    row.castProgressBarEnabled = row.castProgressBarEnabled == true
        or row.castBarEnabled == true
        or row.showCastBar == true
    row.castProgressBarRenameEnabled = row.castProgressBarRenameEnabled == true
    if type(row.castProgressBarRenameText) ~= "string" then
        row.castProgressBarRenameText = defaults.castProgressBarRenameText or ""
    end
    row.ringCastCheckEnabled = row.ringCastCheckEnabled == true
    row.targetAlertStartEnabled = row.targetAlertStartEnabled == true
    if type(row.targetAlertStartLSM) ~= "string" then
        row.targetAlertStartLSM = defaults.targetAlertStartLSM or ""
    end
    row.targetAlertTankEnabled = row.targetAlertTankEnabled == true
    row.targetAlertRingEnabled = row.targetAlertRingEnabled == true
    row.targetAlertIconEnabled = row.targetAlertIconEnabled == true
    row.targetAlertTextEnabledV2 = row.targetAlertTextEnabledV2 == true
    row.targetAlertStealthEnabledV2 = row.targetAlertStealthEnabledV2 == true
    if type(row.voice1Source) ~= "string" then row.voice1Source = defaults.voice1Source or "pack" end
    if type(row.voice1Label) ~= "string" then row.voice1Label = defaults.voice1Label or "" end
    if type(row.voice1LSM) ~= "string" then row.voice1LSM = defaults.voice1LSM or "" end
    if type(row.voice1Path) ~= "string" then row.voice1Path = defaults.voice1Path or "" end
    if type(row.voice1OffsetMode) ~= "string" then row.voice1OffsetMode = defaults.voice1OffsetMode or "delay" end
    row.voice1OffsetSeconds = tonumber(row.voice1OffsetSeconds) or tonumber(defaults.voice1OffsetSeconds) or 0
    if type(row.voice2Source) ~= "string" then row.voice2Source = defaults.voice2Source or "pack" end
    if type(row.voice2Label) ~= "string" then row.voice2Label = defaults.voice2Label or "" end
    if type(row.voice2LSM) ~= "string" then row.voice2LSM = defaults.voice2LSM or "" end
    if type(row.voice2Path) ~= "string" then row.voice2Path = defaults.voice2Path or "" end
    if type(row.voice2OffsetMode) ~= "string" then row.voice2OffsetMode = defaults.voice2OffsetMode or "delay" end
    row.voice2OffsetSeconds = tonumber(row.voice2OffsetSeconds) or tonumber(defaults.voice2OffsetSeconds) or 0
    row.voice1Enabled = row.voice1Enabled == true
    row.voice2Enabled = row.voice2Enabled == true
    return row
end

-- TrashCD has one active source: EXBoss.RuntimeMplus.  Reads return
-- copies so no UI or consumer can mutate the shared runtime table.
local function GetRuntimeTrashRoot()
    local api = _G.EXBossData
    local runtime = type(api) == "table" and type(api.GetRuntime) == "function" and api.GetRuntime("mplus") or nil
    local trash = type(runtime) == "table" and runtime.trashCD or nil
    if type(trash) ~= "table" or type(trash.settings) ~= "table" or type(trash.spellEntries) ~= "table" then
        return nil, "invalid runtime trash root"
    end
    return trash
end

function Store.GetRuntimeConfig()
    local root, reason = GetRuntimeTrashRoot()
    return type(root) == "table" and DeepCopy(root) or nil, reason
end

function Store.GetRuntimeSettings()
    local root, reason = GetRuntimeTrashRoot()
    return type(root) == "table" and DeepCopy(root.settings) or nil, reason
end

local function ResolveRuntimeSettings(runtimeSettings)
    if type(runtimeSettings) == "table" then
        return runtimeSettings
    end
    return Store.GetRuntimeSettings() or {}
end

local function NormalizeRelativePath(path)
    if type(path) ~= "table" or #path == 0 then return nil end
    local out = {}
    for i = 1, #path do
        local key = path[i]
        if type(key) ~= "string" and type(key) ~= "number" then return nil end
        out[i] = key
    end
    if out[1] ~= "settings" and out[1] ~= "spellEntries" then return nil end
    return out
end

local function WriteRelativePath(relativePath, value)
    local path = NormalizeRelativePath(relativePath)
    if not path then return false, "trash path must begin with settings or spellEntries" end
    if value == nil then return false, "nil cannot be saved as a user value" end
    local api = _G.EXBossData
    if not (type(api) == "table" and type(api.SetCurrentUserPath) == "function") then
        return false, "current user configuration unavailable"
    end
    local fullPath = { "trashCD" }
    for i = 1, #path do fullPath[#fullPath + 1] = path[i] end
    return api.SetCurrentUserPath("mplus", fullPath, value)
end

function Store.SetConfigValue(path, value)
    return WriteRelativePath(path, value)
end

function Store.SetSettingValue(settingKey, value)
    if not IsKnownTopLevelKey(settingKey) then return false, "unknown trash setting" end
    return WriteRelativePath({ "settings", settingKey }, value)
end

function Store.SetSpellEntryValue(mapID, npcID, spellID, fieldPath, value)
    local key = Store.GetSpellEntryKey(mapID, npcID, spellID)
    local suffix = type(fieldPath) == "table" and fieldPath or { fieldPath }
    if #suffix == 0 then return false, "trash spell field path is required" end
    local root = GetRuntimeTrashRoot()
    local row = key and type(root) == "table" and root.spellEntries[key] or nil
    if type(row) ~= "table" then
        return false, "unknown runtime trash spell entry"
    end
    local path = { "spellEntries", key }
    for i = 1, #suffix do path[#path + 1] = suffix[i] end
    return WriteRelativePath(path, value)
end

function Store.GetRuntimeSpellEntry(mapID, npcID, spellID)
    local key = Store.GetSpellEntryKey(mapID, npcID, spellID)
    if not key then return nil end
    local root = GetRuntimeTrashRoot()
    local configured = type(root) == "table" and root.spellEntries[key] or nil
    local out = type(configured) == "table" and DeepCopy(configured) or nil
    if not out then return nil end

    local voiceBlacklist = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.VoiceBlacklist or nil
    local voiceBlock = voiceBlacklist and type(voiceBlacklist.GetEntry) == "function"
        and voiceBlacklist.GetEntry(mapID, npcID, spellID) or nil
    if type(voiceBlock) == "table" then
        out.authorVoiceDisabled = true
        out.authorVoiceDisableReasonKey = tostring(voiceBlock.reasonKey or "")
        out.authorVoiceDisableReason = tostring(voiceBlock.reason or "")
    end
    return NormalizeSpellEntry(out)
end

function Store.ListRuntimeSpellEntryKeys()
    local root = GetRuntimeTrashRoot()
    local out = {}
    for key in pairs(type(root) == "table" and root.spellEntries or {}) do out[#out + 1] = key end
    table.sort(out)
    return out
end

function Store.IsEnabled()
    local db = Store.GetRuntimeSettings() or {}
    return db.enabled ~= false
end

function Store.IsMonitorEnabled()
    local db = Store.GetRuntimeSettings() or {}
    return db.enabled ~= false and db.monitorEnabled ~= false
end

function Store.IsOutputEnabled()
    local db = Store.GetRuntimeSettings() or {}
    return db.enabled ~= false
end

function Store.GetHideLongTimerBarConfig()
    local db = Store.GetRuntimeSettings() or {}
    return {
        enabled = db.hideLongTimerBarEnabled == true,
        seconds = math.max(0, tonumber(db.hideLongTimerBarSeconds) or 0),
    }
end

function Store.GetKeepTimerBarAfterReadyConfig()
    local db = Store.GetRuntimeSettings() or {}
    return {
        enabled = db.keepTimerBarAfterReadyEnabled == true,
        seconds = math.max(0, tonumber(db.keepTimerBarAfterReadySeconds) or 0),
    }
end

function Store.GetNameplateGrowthSide(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local side = tostring(db.nameplateGrowthSide or "left")
    if side ~= "left" and side ~= "right" then
        side = "left"
    end
    return side
end

function Store.GetNameplateIconLayout(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local enabled = cfg.showIcon ~= false
    local reverse = cfg.reverse == true
    local width = tonumber(cfg.width) or tonumber(db.nameplateIconSize) or 25
    local height = tonumber(cfg.height) or tonumber(db.nameplateIconSize) or width
    local x = tonumber(cfg.x) or tonumber(db.nameplateOffsetX) or 6
    local y = tonumber(cfg.y) or tonumber(db.nameplateOffsetY) or 0
    if width < 10 then width = 10 elseif width > 300 then width = 300 end
    if height < 10 then height = 10 elseif height > 300 then height = 300 end
    if x < -1000 then x = -1000 elseif x > 1000 then x = 1000 end
    if y < -1000 then y = -1000 elseif y > 1000 then y = 1000 end
    return enabled, width, height, x, y, reverse
end

function Store.GetNameplateIconSpacing(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local spacing = tonumber(cfg.spacing)
    if spacing == nil then
        spacing = 2
    end
    if spacing < 0 then spacing = 0 elseif spacing > 20 then spacing = 20 end
    return spacing
end

function Store.GetNameplateIconHideAboveSeconds(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local seconds = tonumber(db.hideNameplateIconAboveSeconds) or 0
    -- 0 是关闭；姓名版图标不需要接受无意义的超大数值。
    if seconds < 0 then seconds = 0 elseif seconds > 3600 then seconds = 3600 end
    return seconds
end

function Store.GetNameplateIconBorder(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local size = tonumber(cfg.borderSize) or 1
    local padding = tonumber(cfg.borderPadding) or 0
    if size < 1 then size = 1 elseif size > 20 then size = 20 end
    if padding < -20 then padding = -20 elseif padding > 20 then padding = 20 end
    return {
        show = cfg.showBorder ~= false,
        texture = tostring(cfg.borderTexture or "EX_WhiteBorder"),
        size = size,
        padding = padding,
        r = tonumber(cfg.borderColorR) or 0,
        g = tonumber(cfg.borderColorG) or 0,
        b = tonumber(cfg.borderColorB) or 0,
        a = tonumber(cfg.borderColorA) or 1,
    }
end

function Store.GetNameplateReadyBorder(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local cfg = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    return {
        enabled = cfg.readyBorderEnabled ~= false,
        r = tonumber(cfg.readyBorderColorR) or 0.20,
        g = tonumber(cfg.readyBorderColorG) or 0.85,
        b = tonumber(cfg.readyBorderColorB) or 0.20,
        a = tonumber(cfg.readyBorderColorA) or 1,
    }
end

function Store.GetNameplateIconStrata(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local strata = tostring(db.nameplateIconStrata or "DIALOG"):upper()
    if strata == "BACKGROUND"
        or strata == "LOW"
        or strata == "MEDIUM"
        or strata == "HIGH"
        or strata == "DIALOG"
        or strata == "FULLSCREEN"
        or strata == "FULLSCREEN_DIALOG"
        or strata == "TOOLTIP" then
        return strata
    end
    return "DIALOG"
end

function Store.GetNameplateIconSize(runtimeSettings)
    local _, width, height = Store.GetNameplateIconLayout(runtimeSettings)
    return math.max(tonumber(width) or 25, tonumber(height) or 25)
end

function Store.GetNameplateOffset(runtimeSettings)
    local _, _, _, x, y = Store.GetNameplateIconLayout(runtimeSettings)
    return x, y
end

function Store.GetNameplateIconTextLayout(runtimeSettings)
    local db = ResolveRuntimeSettings(runtimeSettings)
    local cfg = type(db.nameplateIconText) == "table" and db.nameplateIconText or {}
    local size = tonumber(cfg.size) or 15
    local x = tonumber(cfg.x) or 0
    local y = tonumber(cfg.y) or 0
    local shadowX = tonumber(cfg.shadowX) or 1
    local shadowY = tonumber(cfg.shadowY) or -1
    if size < 4 then size = 4 elseif size > 100 then size = 100 end
    if x < -200 then x = -200 elseif x > 200 then x = 200 end
    if y < -200 then y = -200 elseif y > 200 then y = 200 end
    if shadowX < -20 then shadowX = -20 elseif shadowX > 20 then shadowX = 20 end
    if shadowY < -20 then shadowY = -20 elseif shadowY > 20 then shadowY = 20 end
    return {
        r = tonumber(cfg.r) or 1,
        g = tonumber(cfg.g) or 1,
        b = tonumber(cfg.b) or 1,
        a = tonumber(cfg.a) or 1,
        size = size,
        font = tostring(cfg.font or ""),
        outline = tostring(cfg.outline or "OUTLINE"),
        x = x,
        y = y,
        shadow = cfg.shadow ~= false,
        shadowX = shadowX,
        shadowY = shadowY,
    }
end

function Store.IsNameplateNPCIDHidden()
    return true
end

function Store.UseTimelineScriptEvent()
    local db = Store.GetRuntimeSettings() or {}
    return db.enabled ~= false and db.useTimelineScriptEvent ~= false
end
