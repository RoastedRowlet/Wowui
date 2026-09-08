---@diagnostic disable: undefined-global, undefined-field

ExBoss.UI.Panel.TrashCDPage = ExBoss.UI.Panel.TrashCDPage or {}
local Page = ExBoss.UI.Panel.TrashCDPage

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local TrashStore = ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
local TrashData = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local TrashCore = ExBoss.TrashCD and ExBoss.TrashCD.Core or nil

local function LocalizeDynamicText(v)
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        return tostring(ExBoss.Locale.TranslateBossDynamicText(v) or "")
    end
    return tostring(v or "")
end

local SPELL_SETTINGS_MODULE_KEY = "ExBoss.TrashCD.SpellEditor"
local C = {
    SPELL_CARD = {
        cols = 1,
        gapX = 6,
        gapY = 6,
        height = 50,
        titleFontSizes = { 16, 14, 13, 11 },
    },
}

-- 在这里写入小怪面板左侧 被点名提示的图标法术ID
ExBoss.TargetAlert = ExBoss.TargetAlert or {}
ExBoss.TargetAlert.SupportedTrashSpellIDs = {
    [1262508] = true,
    [1262506] = true,
    [388942] = true,
    [1252622] = true,
    [1281657] = true,
    [1258820] = true,
    [1258475] = true,
    [1258174] = true,
    [1282050] = true,
    [1244907] = true,
    [1252062] = true,
    [1271623] = true,
    [1253446] = true,
}
local TEST_THREAT_ATLAS_SPELLS = ExBoss.TargetAlert.SupportedTrashSpellIDs
local TEST_THREAT_ATLAS_NAME = "Ping_Marker_Icon_Threat"
local TEST_THREAT_ATLAS_TOOLTIP = "可设置「被点名提示」!"
local EVENT_COLOR_ITEMS_FUNC = "func:ExBoss.Voice.ColorSchemes.BuildDropdownItems"
local LABEL_ITEMS_FUNC = "func:ExBoss.Voice.LabelCatalog.GetDropdownItems"
local TRIGGER_SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
    { L["自定义路径"], "file" },
}
local COUNTDOWN_LEAD_ITEMS = {
    { "1", "1" },
    { "2", "2" },
    { "3", "3" },
    { "4", "4" },
    { "5", "5" },
    { "6", "6" },
    { "7", "7" },
    { "8", "8" },
    { "9", "9" },
}
local TRIGGER_OFFSET_MODE_ITEMS = {
    { L["延迟"], "delay" },
    { L["提前"], "early" },
}
local SETTINGS_LAYOUT = {}
local CACHE = {
    challengeMapLookup = nil,
    spellTextCache = {},
    spellCachePending = {},
    spellRowsByMap = {},
}

local root
local mapPane
local spellPane
local detailPane
local settingsPane
local mapScrollFrame
local mapScrollChild
local spellScrollFrame
local spellScrollChild
local settingsScrollFrame
local settingsScrollChild
local detailIcon
local detailPlaceholder
local detailTitle
local detailMeta
local detailCast
local detailBody
local detailInfo
local detailDivider
local settingsVoiceDisabledNote

local activeDungeonButtons = {}
local dungeonButtonPool = {}
local activeSpellRows = {}
local spellRowPool = {}
local spellDividerPool = {}
local selectedMapID
local selectedNPCID
local selectedSpellID
-- 编辑器只是当前控件的页面显示值，绝不是持久配置镜像；提交始终按字段
-- 直接写入 CurrentUser 与唯一 Runtime。
local spellEditorDraft
local spellEditorContext
local _suspendSpellSettingPersist = false
local GetSpellRows
local GetRuntimeSpellEntry
local GetRowSpellDescription
local GetSelectedSpellRow
local _asyncHandler
local _spellListBuildToken = 0
local _selectionRefreshToken = 0

local function RegisterSpellSettingsGridAsActive(moduleKey)
    if not (Page._visible and settingsScrollChild and ExwindTools and ExwindTools.UI) then
        return
    end
    ExwindTools.UI.ActivePageFrame = settingsScrollChild
    if type(moduleKey) == "string" and moduleKey ~= "" then
        ExwindTools.UI.CurrentModule = moduleKey
    end
end

local function ClearSpellSettingsGridActiveRegistration()
    if not (ExwindTools and ExwindTools.UI and settingsScrollChild) then
        return
    end
    if ExwindTools.UI.ActivePageFrame == settingsScrollChild then
        ExwindTools.UI.ActivePageFrame = nil
        ExwindTools.UI.CurrentModule = nil
    end
end

local SPELL_ROW_H = 32
local SPELL_CACHE_PRIME_LIMIT = 12
local function GetEffectiveDisplayLocale()
    if ExBoss and ExBoss.GetEffectiveLocale then
        local mode = ExBoss.GetLocaleMode and ExBoss:GetLocaleMode() or "AUTO"
        return tostring(ExBoss:GetEffectiveLocale(mode) or "zhCN")
    end
    return "zhCN"
end

local function GetAsyncHandler()
    if _asyncHandler and _asyncHandler ~= false then
        return _asyncHandler
    end
    local lib = LibStub and LibStub("LibAsync", true)
    if not lib then
        _asyncHandler = nil
        return nil
    end
    _asyncHandler = lib:GetHandler({
        type = "everyFrame",
        maxTime = 6,
        maxTimeCombat = 4,
        errorHandler = geterrorhandler(),
    })
    return _asyncHandler
end

local function CreateSectionBackdrop(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, 0.90)
    frame:SetBackdropBorderColor(0.22, 0.22, 0.25, 0.95)
    return frame
end

local function Clamp01(v, fallback)
    local n = tonumber(v)
    if not n then return fallback or 0 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function NormalizeTriggerSource(value)
    local source = tostring(value or "pack")
    if source ~= "pack" and source ~= "lsm" and source ~= "file" then
        source = "pack"
    end
    return source
end

local function NormalizeMapNameKey(name)
    local s = tostring(name or ""):lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

-- 小怪静态资料以挑战地图 ID（例如 249）索引；Boss 页与 EXDB 以实例地图 ID
-- （例如 1762）索引。显示层必须先解析到同一份 EXDB 副本元数据，不能用挑战
-- 地图 ID 直接查 InstanceNoteByMapID，否则会落回小怪资料中的原始名称。
local function GetLocalizedDBName(meta, locale)
    if type(meta) ~= "table" then return nil end
    local value = meta[locale]
    if type(value) == "string" and value ~= "" then return value end
    value = meta.enUS or meta.nameEN or meta.name
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function GetInstanceMetaForMapReference(mapID)
    local id = tonumber(mapID)
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil
    if not (id and EXDB) then
        return nil
    end

    local meta = type(EXDB.InstanceNoteByMapID) == "table" and EXDB.InstanceNoteByMapID[id] or nil
    if meta then
        return meta
    end

    return type(EXDB.InstanceNoteByChallengeModeID) == "table"
        and EXDB.InstanceNoteByChallengeModeID[id]
        or nil
end

local function ResolveLocalizedMapName(rawName, fallbackName, mapID)
    local locale = GetEffectiveDisplayLocale()
    local localized = GetLocalizedDBName(GetInstanceMetaForMapReference(mapID), locale)
    if localized then return localized end
    local raw = tostring(rawName or "")
    if raw ~= "" then return raw end
    return tostring(fallbackName or "")
end

local function GetMapDisplayName(mapID)
    local id = tonumber(mapID)
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    local row = id and rootData[id] or nil
    if type(row) == "table" then
        return ResolveLocalizedMapName(row.mapName or row.name, row.zhCN, id)
    end
    if C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(id or 0)
        if mapInfo and mapInfo.name and mapInfo.name ~= "" then
            return ResolveLocalizedMapName(mapInfo.name, nil, id)
        end
    end
    return L["未知副本 "] .. tostring(mapID)
end

local function GetMapShortDisplayName(mapID)
    local id = tonumber(mapID)
    local locale = GetEffectiveDisplayLocale()
    if locale == "enGB" then locale = "enUS" end
    local meta = GetInstanceMetaForMapReference(id)
    if meta then
        if locale == "enUS" then
            local shortEN = tostring(meta.enUSShort or "")
            if shortEN ~= "" then
                return shortEN
            end
        else
            local shortCN = tostring(meta.zhCNShort or "")
            if shortCN ~= "" then
                return shortCN
            end
        end
    end

    local mapName = tostring(GetMapDisplayName(id) or "")
    local nameLen = (type(strlenutf8) == "function" and strlenutf8(mapName)) or #mapName
    if nameLen > 5 then
        if type(UTF8Left) == "function" then
            mapName = UTF8Left(mapName, 5)
        else
            mapName = string.sub(mapName, 1, 5)
        end
    end
    return mapName
end

local function GetDisplayMobName(npcID, fallbackName)
    local locale = GetEffectiveDisplayLocale()
    local id = tonumber(npcID) or 0
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil
    if EXDB and type(EXDB.NPCNameByID) == "table" and id > 0 then
        local row = EXDB.NPCNameByID[id]
        if row then
            local v = row[locale]
            if type(v) == "string" and v ~= "" then return v end
            local en = row["enUS"]
            if type(en) == "string" and en ~= "" then return en end
        end
    end
    return tostring(fallbackName or ("NPC " .. tostring(npcID or "")))
end

local function SetWidgetUsable(widget, usable)
    if not widget then
        return
    end
    usable = usable ~= false
    widget:SetAlpha(usable and 1 or 0.45)
    if widget.checkbox and widget.checkbox.Enable then
        if usable then
            widget.checkbox:Enable()
        else
            widget.checkbox:Disable()
        end
    end
    if widget.editBox and widget.editBox.Enable then
        if usable then
            widget.editBox:Enable()
        else
            widget.editBox:Disable()
        end
    end
    if widget.button and widget.button.Enable then
        if usable then
            widget.button:Enable()
        else
            widget.button:Disable()
        end
    end
    if widget.Enable then
        if usable then
            widget:Enable()
        else
            widget:Disable()
        end
    elseif widget.EnableMouse then
        widget:EnableMouse(usable)
    end
end

local function GetMapIcon(mapID)
    local id = tonumber(mapID)
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    local mapRow = rootData and rootData[id] or nil
    local mapName = tostring(mapRow and (mapRow.mapName or mapRow.name) or "")
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil

    if id and EXDB and type(EXDB.InstanceIconByMapID) == "table" then
        local icon = EXDB.InstanceIconByMapID[id]
        if icon then
            return icon
        end
    end
    if mapRow and mapRow.icon then
        return mapRow.icon
    end

    if CACHE.challengeMapLookup == nil then
        local lookup = {}
        if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" and type(C_ChallengeMode.GetMapUIInfo) == "function" then
            local ok, idList = pcall(C_ChallengeMode.GetMapTable)
            if ok and type(idList) == "table" then
                for _, cmID in ipairs(idList) do
                    local okInfo, name, _, _, icon = pcall(C_ChallengeMode.GetMapUIInfo, cmID)
                    if okInfo and type(name) == "string" and name ~= "" and icon then
                        local key = NormalizeMapNameKey(name)
                        if key ~= "" and not lookup[key] then
                            lookup[key] = { id = tonumber(cmID), icon = icon }
                        end
                    end
                end
            end
        end
        CACHE.challengeMapLookup = lookup
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and id and id > 0 then
        local _, _, _, icon = C_ChallengeMode.GetMapUIInfo(id)
        if icon then
            return icon
        end
    end

    if mapName ~= "" then
        local hit = CACHE.challengeMapLookup and CACHE.challengeMapLookup[NormalizeMapNameKey(mapName)] or nil
        if hit and hit.icon then
            return hit.icon
        end
    end
    return "Interface\\LFGFrame\\LFGIcon-Dungeon"
end

local function IsSpellDataReady(spellID)
    if not spellID then
        return true
    end
    if C_Spell and C_Spell.IsSpellDataCached then
        local ok, cached = pcall(C_Spell.IsSpellDataCached, spellID)
        if ok then
            return cached and true or false
        end
    end
    return true
end

local function RequestSpellDataLoad(spellID)
    if not spellID or not (C_Spell and C_Spell.RequestLoadSpellData) then
        return
    end
    if CACHE.spellCachePending[spellID] then
        return
    end
    CACHE.spellCachePending[spellID] = true
    pcall(C_Spell.RequestLoadSpellData, spellID)
end

local function PrimeSpellCache(rows)
    local primed = 0
    for _, row in ipairs(rows or {}) do
        if primed >= SPELL_CACHE_PRIME_LIMIT then
            break
        end
        local spellID = tonumber(row and row.spellID)
        if spellID and not IsSpellDataReady(spellID) then
            RequestSpellDataLoad(spellID)
            primed = primed + 1
        end
    end
end

local function GetAuthorVoiceDisableText(cfg)
    if type(cfg) ~= "table" or cfg.authorVoiceDisabled ~= true then
        return nil
    end
    local key = tostring(cfg.authorVoiceDisableReasonKey or "")
    if key ~= "" then
        return tostring(L[key] or key)
    end
    local reason = tostring(cfg.authorVoiceDisableReason or "")
    if reason ~= "" then
        return reason
    end
    return L["该技能语音已被作者临时禁用"]
end

local function CurrentTrashHasSpellID(spellID)
    local sid = tonumber(spellID)
    if not sid then
        return false
    end
    if tonumber(selectedSpellID) == sid then
        return true
    end
    local rows = GetSpellRows(selectedMapID)
    for i = 1, #rows do
        if tonumber(rows[i].spellID) == sid then
            return true
        end
    end
    return false
end

local function NormalizeSpellDescText(text)
    local s = tostring(text or "")
    if s == "" then
        return ""
    end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("\r\n", "\n")
    return s
end

local function WrapColorText(text, color)
    local body = tostring(text or "")
    if body == "" or type(color) ~= "table" then
        return body
    end
    local r = math.floor((tonumber(color.r) or 1) * 255 + 0.5)
    local g = math.floor((tonumber(color.g) or 1) * 255 + 0.5)
    local b = math.floor((tonumber(color.b) or 1) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, body)
end

local function GetSpellNameAndIcon(spellID)
    if not spellID then
        return nil, 134400
    end
    local cached = CACHE.spellTextCache[spellID]
    if type(cached) == "table" and cached.name ~= nil and cached.icon ~= nil then
        return cached.name, cached.icon
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            local name = info.name
            local icon = info.iconID or 134400
            CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
            CACHE.spellTextCache[spellID].name = name
            CACHE.spellTextCache[spellID].icon = icon
            return name, icon
        end
    end
    return nil, 134400
end

local function GetRowSpellNameAndIcon(row)
    return GetSpellNameAndIcon(type(row) == "table" and row.spellID or nil)
end

local function GetSpellIcon(spellID)
    local _, icon = GetSpellNameAndIcon(spellID)
    return icon or 134400
end

local function GetRowSpellIcon(row)
    local _, icon = GetRowSpellNameAndIcon(row)
    return icon or 134400
end

local function GetSpellDescription(spellID)
    if not spellID then
        return L["暂无描述。"]
    end
    local cached = CACHE.spellTextCache[spellID]
    if type(cached) == "table" and type(cached.desc) == "string" and cached.desc ~= "" then
        return cached.desc
    end
    if not IsSpellDataReady(spellID) then
        RequestSpellDataLoad(spellID)
    end

    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local ok, tip = pcall(C_TooltipInfo.GetSpellByID, spellID)
        if ok and tip and tip.lines then
            local lines = {}
            for i, line in ipairs(tip.lines) do
                local text = line and line.leftText
                if i > 1 and text and text ~= "" then
                    text = NormalizeSpellDescText(text)
                    if text ~= "" then
                        lines[#lines + 1] = WrapColorText(text, line.leftColor)
                    end
                end
            end
            if #lines > 0 then
                local desc = (#lines >= 2) and ("\n" .. lines[1] .. "\n\n" .. table.concat(lines, "\n", 2)) or
                    ("\n" .. table.concat(lines, "\n"))
                CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
                CACHE.spellTextCache[spellID].desc = desc
                return desc
            end
        end
    end
    if TrashData and TrashData.GetSpellDescriptionSafe then
        local desc = TrashData.GetSpellDescriptionSafe(spellID)
        if type(desc) == "string" and desc ~= "" then
            desc = NormalizeSpellDescText(desc)
            CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
            CACHE.spellTextCache[spellID].desc = desc
            return desc
        end
    end
    CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
    CACHE.spellTextCache[spellID].desc = L["暂无描述。"]
    return L["暂无描述。"]
end

local function SplitSpellDescription(descText)
    local lines = {}
    for raw in tostring(descText or ""):gmatch("[^\n]+") do
        local line = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    local castLine = lines[1] or ""
    if #lines <= 1 then
        return castLine, ""
    end
    return castLine, table.concat(lines, "\n\n", 2)
end

local function RefreshDetailCardLayout()
    if not (detailPane and detailTitle and detailMeta and detailCast and detailBody and detailDivider) then
        return
    end
    local headerW = detailPane:GetWidth() or 0
    if headerW <= 0 then
        headerW = 980
    end

    local metaWidth = math.min(300, math.floor(headerW * 0.28))
    local titleNatural = math.ceil(detailTitle:GetUnboundedStringWidth() or 0) + 8
    local titleWidth = math.min(
        math.max(220, headerW - 44 - 14 - 12 - 12 - metaWidth - 18),
        math.max(120, titleNatural)
    )
    local bodyWidth = math.max(320, headerW - 44 - 14 - 12 - 18)

    detailTitle:SetWidth(titleWidth)
    detailMeta:ClearAllPoints()
    detailMeta:SetPoint("LEFT", detailTitle, "RIGHT", 6, 0)
    detailMeta:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailCast:SetWidth(bodyWidth)
    detailBody:SetWidth(bodyWidth)
    detailInfo:SetWidth(bodyWidth)

    local castH = detailCast:GetStringHeight() or 0
    local bodyH = detailBody:GetStringHeight() or 0
    local infoH = detailInfo:GetStringHeight() or 0
    local desiredHeight = math.max(118, math.ceil(64 + castH + 6 + bodyH + 8 + infoH + 18))
    detailPane:SetHeight(desiredHeight)
end

local function SetDetailCardEmpty(message)
    if not detailPane then
        return
    end
    if detailPlaceholder then
        detailPlaceholder:SetText(tostring(message or L["点击左侧法术后，可在此查看法术描述。"]))
        detailPlaceholder:Show()
    end
    if detailIcon then detailIcon:Hide() end
    if detailTitle then detailTitle:SetText("") end
    if detailMeta then detailMeta:SetText("") end
    if detailCast then detailCast:SetText("") end
    if detailBody then detailBody:SetText("") end
    if detailInfo then detailInfo:SetText("") end
    if detailDivider then detailDivider:Hide() end
    detailPane:SetHeight(98)
end

local function GetDungeonRows()
    local out = {}
    local seen = {}
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    for key, row in pairs(rootData) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = GetMapDisplayName(mapID)
            if mapID and mapName ~= "" then
                local mobCount = 0
                if type(row.mobs) == "table" then
                    for _ in pairs(row.mobs) do
                        mobCount = mobCount + 1
                    end
                end
                out[#out + 1] = {
                    mapID = mapID,
                    mapName = mapName,
                    mobCount = mobCount,
                }
                seen[mapID] = true
            end
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.mapName) < tostring(b.mapName)
    end)
    return out
end

local function ResolveDefaultMapID()
    local _, mapName = nil, nil
    if TrashData and TrashData.GetCurrentInstanceContext then
        _, mapName = TrashData.GetCurrentInstanceContext()
    end
    if mapName and TrashData and TrashData.GetTrashMapIDByNameKey and TrashData.NormalizeNameKey then
        local lookup = TrashData.GetTrashMapIDByNameKey()
        local mapID = lookup and lookup[TrashData.NormalizeNameKey(mapName)]
        if tonumber(mapID) then
            return tonumber(mapID)
        end
    end
    local rows = GetDungeonRows()
    return rows[1] and rows[1].mapID or nil
end

local function FilterResolvedSpellRows(rows)
    local out = {}
    for i = 1, #(rows or {}) do
        local row = rows[i]
        if type(GetRuntimeSpellEntry(row)) == "table" then
            out[#out + 1] = row
        end
    end
    return out
end

GetSpellRows = function(mapID)
    local mid = tonumber(mapID)
    if not mid then
        return {}
    end
    local cached = CACHE.spellRowsByMap[mid]
    if type(cached) == "table" then
        return FilterResolvedSpellRows(cached)
    end
    local out = {}
    local rootData = TrashData and TrashData.GetTrashCDDataRoot and TrashData.GetTrashCDDataRoot() or {}
    local mapRow = rootData and rootData[mid] or nil
    local mobs = mapRow and type(mapRow.mobs) == "table" and mapRow.mobs or nil
    if type(mobs) == "table" then
        for npcID, mob in pairs(mobs) do
            if type(mob) == "table" and type(mob.spells) == "table" then
                for spellID, spellData in pairs(mob.spells) do
                    if type(spellData) == "table" then
                        local spellName = nil
                        local apiSpellName = select(1, GetSpellNameAndIcon(tonumber(spellID)))
                        if type(apiSpellName) == "string" and apiSpellName ~= "" then
                            spellName = apiSpellName
                        else
                            spellName = tostring(spellData.name or
                                (TrashData and TrashData.GetSpellNameSafe and TrashData.GetSpellNameSafe(spellID)) or
                                spellID)
                        end
                        out[#out + 1] = {
                            mapID = mid,
                            npcID = tonumber(npcID),
                            mobName = GetDisplayMobName(npcID, mob.name),
                            spellID = tonumber(spellID),
                            spellName = spellName,
                            eventType = tostring(spellData.eventType or "其他"),
                            first = tonumber(spellData.first),
                            castTime = tonumber(spellData.castTime),
                            cd = type(spellData.cd) == "table" and spellData.cd or nil,
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.mobName ~= b.mobName then
            return a.mobName < b.mobName
        end
        if a.spellName ~= b.spellName then
            return a.spellName < b.spellName
        end
        return (a.spellID or 0) < (b.spellID or 0)
    end)
    CACHE.spellRowsByMap[mid] = out
    return FilterResolvedSpellRows(out)
end

GetSelectedSpellRow = function()
    if not selectedMapID or not selectedNPCID or not selectedSpellID then
        return nil
    end
    local rows = GetSpellRows(selectedMapID)
    for i = 1, #rows do
        local row = rows[i]
        if row.npcID == selectedNPCID and row.spellID == selectedSpellID then
            return row
        end
    end
    return nil
end

GetRuntimeSpellEntry = function(row)
    if not row or not TrashStore or not TrashStore.GetRuntimeSpellEntry then
        return nil
    end
    return TrashStore.GetRuntimeSpellEntry(row.mapID, row.npcID, row.spellID)
end

local function GetColorSchemeModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

local function NormalizeEventColorMode(mode)
    local CS = GetColorSchemeModule()
    if CS and CS.NormalizeSchemeKey and CS.GetCustomKey then
        local n = CS.NormalizeSchemeKey(mode)
        if n then
            return n
        end
        return CS.GetCustomKey()
    end
    local s = tostring(mode or "")
    if s == "tank" or s == "heal" or s == "target" or s == "cooldown" or s == "mechanic" then
        return s
    end
    return "__custom"
end

local function ResolveSpellEntryBorderColor(cfg)
    local CS = GetColorSchemeModule()
    if type(cfg) ~= "table" or cfg.eventColorEnabled ~= true then
        return nil
    end

    local mode = NormalizeEventColorMode(cfg.eventColorMode)
    if mode == "__custom" then
        local color = cfg.eventColor
        if type(color) == "table" then
            return Clamp01(color.r, 1), Clamp01(color.g, 0.82), Clamp01(color.b, 0.25)
        end
        return 1, 0.82, 0.25
    end

    if CS and CS.GetSchemeColor then
        local r, g, b = CS.GetSchemeColor(mode)
        if r ~= nil and g ~= nil and b ~= nil then
            return Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1)
        end
    end

    return nil
end

-- 事件类型是 Excel 导出的战斗事实；图标绝不能从用户的颜色设置反推。
-- 此映射与 Boss Factory 的 eventTypeSchemes 完全一致：特殊和机制共用 mechanic。
local EVENT_TYPE_SCHEMES = {
    ["坦克"] = "tank",
    ["治疗"] = "heal",
    ["点名"] = "target",
    ["机制"] = "mechanic",
    ["特殊"] = "mechanic",
    ["其他"] = "cooldown",
}

-- 与 Boss 技能卡使用的同一组类别图标；此处不读取任何用户配置。
local EVENT_SCHEME_ICONS = {
    tank = "icons_64x64_tank",
    heal = "icons_64x64_heal",
    target = "cursor_crosshairs_48",
    mechanic = "icons_64x64_deadly",
    cooldown = "Ping_Wheel_Icon_Warning_Disabled_Small",
}

local function ResolveEventTypeIcon(eventType)
    local scheme = EVENT_TYPE_SCHEMES[tostring(eventType or "")] or "cooldown"
    return EVENT_SCHEME_ICONS[scheme]
end

local function NormalizeCountdownLeadSeconds(v)
    local n = tonumber(v)
    if not n then
        n = 5
    end
    n = math.floor(n + 0.0001)
    if n < 1 then n = 1 end
    if n > 9 then n = 9 end
    return n
end

local function GetSpellEditorDefaults()
    local defaults = TrashStore and TrashStore.GetSpellEntryDefaults and TrashStore.GetSpellEntryDefaults() or {}
    return {
        enabled = defaults.enabled == true,
        showBunBar = defaults.showBunBar ~= false,
        showTimerBar = defaults.showTimerBar ~= false,
        showNameplate = defaults.showNameplate == true,
        eventColorEnabled = defaults.eventColorEnabled == true,
        eventColorMode = tostring(defaults.eventColorMode or "none"),
        eventColor = type(defaults.eventColor) == "table" and {
            r = tonumber(defaults.eventColor.r) or 1,
            g = tonumber(defaults.eventColor.g) or 1,
            b = tonumber(defaults.eventColor.b) or 1,
            a = tonumber(defaults.eventColor.a) or 1,
        } or { r = 1, g = 1, b = 1, a = 1 },
        centralEnabled = defaults.centralEnabled == true,
        centralLead = tonumber(defaults.centralLead) or 0,
        centralText = tostring(defaults.centralText or ""),
        countdownEnabled = defaults.countdownEnabled == true,
        countdownLead = tostring(NormalizeCountdownLeadSeconds(defaults.countdownLead)),
        preAlertEnabled = defaults.preAlertEnabled == true,
        preAlertText = tostring(defaults.countdownText or ""),
        timerBarRenameEnabled = defaults.timerBarRenameEnabled == true,
        timerBarRenameText = tostring(defaults.timerBarName or ""),
        ringEnabled = defaults.ringEnabled == true,
        ringRenameEnabled = defaults.ringRenameEnabled == true,
        ringRenameText = tostring(defaults.ringRenameText or ""),
        castProgressBarEnabled = defaults.castProgressBarEnabled == true,
        castProgressBarRenameEnabled = defaults.castProgressBarRenameEnabled == true,
        castProgressBarRenameText = tostring(defaults.castProgressBarRenameText or ""),
        ringCastCheckEnabled = defaults.ringCastCheckEnabled == true,
        targetAlertStartEnabled = defaults.targetAlertStartEnabled == true,
        targetAlertStartLSM = tostring(defaults.targetAlertStartLSM or ""),
        targetAlertTankEnabled = defaults.targetAlertTankEnabled == true,
        targetAlertRingEnabled = defaults.targetAlertRingEnabled == true,
        targetAlertIconEnabled = defaults.targetAlertIconEnabled == true,
        targetAlertTextEnabledV2 = defaults.targetAlertTextEnabledV2 == true,
        targetAlertStealthEnabledV2 = defaults.targetAlertStealthEnabledV2 == true,
        tr1Enabled = defaults.voice1Enabled == true,
        tr1Source = tostring(defaults.voice1Source or "pack"),
        tr1Label = tostring(defaults.voice1Label or ""),
        tr1LSM = tostring(defaults.voice1LSM or ""),
        tr1Path = tostring(defaults.voice1Path or ""),
        tr1OffsetMode = tostring(defaults.voice1OffsetMode or "delay"),
        tr1OffsetSeconds = tonumber(defaults.voice1OffsetSeconds) or 0,
        tr2Enabled = defaults.countdownVoiceEnabled == true,
        tr2CountdownLead = tostring(NormalizeCountdownLeadSeconds(defaults.countdownLead)),
        tr2PlayTextEnabled = defaults.countdownPlayName == true,
        tr2Source = tostring(defaults.voice2Source or "pack"),
        tr2Label = tostring(defaults.voice2Label or ""),
        tr2LSM = tostring(defaults.voice2LSM or ""),
        tr2Path = tostring(defaults.voice2Path or ""),
        tr2OffsetMode = tostring(defaults.voice2OffsetMode or "delay"),
        tr2OffsetSeconds = tonumber(defaults.voice2OffsetSeconds) or 0,
    }
end

local function GetSpellEditorDB()
    if type(spellEditorDraft) ~= "table" then
        spellEditorDraft = GetSpellEditorDefaults()
    end
    return spellEditorDraft
end

local function CopyTable(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for key, value in pairs(src) do
        dst[key] = value
    end
    return dst
end

local function FormatCDList(cdList)
    if type(cdList) ~= "table" or #cdList == 0 then
        return "-"
    end
    local out = {}
    for i = 1, #cdList do
        out[#out + 1] = tostring(cdList[i])
    end
    return table.concat(out, ", ")
end

local function PlayVoicePreview(sourceType, label, customLSM, customPath)
    local source = NormalizeTriggerSource(sourceType)
    if source == "pack" then
        local safeLabel = tostring(label or "")
        if safeLabel == "" then
            return
        end
        local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
        if Engine and Engine.TryPlayLabel then
            Engine:TryPlayLabel(safeLabel, { source = "trash_cd_preview" })
        end
        return
    end

    local soundPath = nil
    if source == "lsm" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM and customLSM and customLSM ~= "" then
            soundPath = LSM:Fetch("sound", customLSM, true)
        end
    elseif source == "file" then
        soundPath = tostring(customPath or "")
    end
    if soundPath and soundPath ~= "" and PlaySoundFile then
        pcall(PlaySoundFile, soundPath, "Master")
    end
end

local function BuildSettingsLayout()
    if #SETTINGS_LAYOUT > 0 then
        return
    end
    local rows = {
        { key = "enabled", type = "checkbox", x = 80, y = 1, w = 20, h = 5, label = L["启用"], labelSize = 18 },
        { key = "eventColorEnabled", type = "checkbox", x = 6, y = 16, w = 20, h = 5, label = L["颜色"] },
        { key = "eventColorMode", type = "dropdown", x = 31, y = 16, w = 37, h = 5, label = "", items = EVENT_COLOR_ITEMS_FUNC, labelPos = "left", search = true },
        { key = "eventColor", type = "color", x = 70, y = 16, w = 30, h = 5, label = L["自定义颜色"] },
        { key = "card_text", type = "card", x = 3, y = 8, w = 99, h = 62, label = L["文本设置"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\text.png", accentColor = { r = 1.00, g = 0.82, b = 0.22, a = 0.95 } },
        { key = "description_trash_text_1", type = "description", x = 6, y = 23, w = 35, h = 5, label = "|cffffd637" .. L["中央文本"] .. "|r" },
        { key = "centralEnabled", type = "checkbox", x = 6, y = 28, w = 25, h = 5, label = L["启用"] },
        { key = "centralLead", type = "input", x = 31, y = 28, w = 17, h = 5, label = L["提前(秒)"], labelPos = "right" },
        { key = "centralText", type = "input", x = 31, y = 33, w = 54, h = 5, label = "" },
        { key = "description_trash_text_2", type = "description", x = 6, y = 41, w = 44, h = 5, label = "|cffffd637" .. L["倒数文本"] .. "|r" },
        { key = "countdownEnabled", type = "checkbox", x = 6, y = 45, w = 25, h = 5, label = L["启用"] },
        { key = "preAlertText", type = "input", x = 31, y = 45, w = 54, h = 5, label = "" },
        { key = "description_trash_text_3", type = "description", x = 6, y = 55, w = 44, h = 5, label = "|cffffd637" .. L["计时条改名"] .. "|r" },
        { key = "timerBarRenameEnabled", type = "checkbox", x = 6, y = 60, w = 25, h = 5, label = L["启用"] },
        { key = "timerBarRenameText", type = "input", x = 31, y = 60, w = 54, h = 5, label = "" },

        { key = "card_voice", type = "card", x = 3, y = 73, w = 99, h = 62, label = L["语音设置"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\sound.png", accentColor = { r = 0.28, g = 0.84, b = 1.00, a = 0.95 } },
        { key = "description_trash_voice_1", type = "description", x = 6, y = 80, w = 44, h = 5, label = "|cffffd637" .. L["施法开始"] .. "|r" },
        { key = "tr1Enabled", type = "checkbox", x = 6, y = 85, w = 20, h = 5, label = L["启用"] },
        { key = "tr1Source", type = "dropdown", x = 31, y = 85, w = 25, h = 5, label = "", items = TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr1Label", type = "dropdown", x = 58, y = 85, w = 30, h = 5, label = "", items = LABEL_ITEMS_FUNC, search = true },
        { key = "tr1LSM", type = "lsm_sound", x = 58, y = 85, w = 30, h = 5, label = "", search = true },
        { key = "tr1Path", type = "input", x = 58, y = 85, w = 30, h = 5, label = "" },
        { key = "tr1ValueTest", type = "button", x = 90, y = 85, w = 10, h = 5, label = L["试听"] },
        { key = "description_trash_voice_2", type = "description", x = 6, y = 97, w = 44, h = 5, label = "|cffffd637" .. L["倒数提示"] .. "|r" },
        { key = "tr2Enabled", type = "checkbox", x = 6, y = 102, w = 20, h = 5, label = L["启用"] },
        { key = "tr2CountdownLead", type = "dropdown", x = 31, y = 102, w = 25, h = 5, label = "", items = COUNTDOWN_LEAD_ITEMS, search = true },
        { key = "tr2PlayTextEnabled", type = "checkbox", x = 6, y = 110, w = 22, h = 5, label = L["播放文字"] },
        { key = "tr2Source", type = "dropdown", x = 31, y = 110, w = 25, h = 5, label = "", items = TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr2Label", type = "dropdown", x = 58, y = 110, w = 30, h = 5, label = "", items = LABEL_ITEMS_FUNC, search = true },
        { key = "tr2LSM", type = "lsm_sound", x = 58, y = 110, w = 30, h = 5, label = "", search = true },
        { key = "tr2Path", type = "input", x = 58, y = 110, w = 30, h = 5, label = "" },
        { key = "tr2ValueTest", type = "button", x = 90, y = 110, w = 10, h = 5, label = L["试听"] },

        { key = "showBunBar", type = "checkbox", x = 105, y = 1, w = 15, h = 5, label = L["竖条"] },
        { key = "showTimerBar", type = "checkbox", x = 134, y = 1, w = 20, h = 5, label = L["计时条"] },
        { key = "showNameplate", type = "checkbox", x = 166, y = 1, w = 20, h = 5, label = L["姓名版"] },

        { key = "card_cast", type = "card", x = 105, y = 8, w = 96, h = 62, label = L["施法设置"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\bar.png", accentColor = { r = 0.50, g = 0.74, b = 1.00, a = 0.95 } },
        { key = "ringEnabled", type = "checkbox", x = 107, y = 16, w = 59, h = 5, label = L["BOSS施法时显示圆环"] },
        { key = "castProgressBarEnabled", type = "checkbox", x = 107, y = 23, w = 59, h = 5, label = L["BOSS施法时显示读条"] },
        { key = "castProgressBarRenameEnabled", type = "checkbox", x = 107, y = 28, w = 20, h = 5, label = L["改名"] },
        { key = "castProgressBarRenameText", type = "input", x = 132, y = 28, w = 54, h = 5, label = "" },
        { key = "ringCastCheckEnabled", type = "checkbox", x = 107, y = 36, w = 30, h = 5, label = L["施法检测"] },
        { key = "card_target_alert", type = "card", x = 105, y = 73, w = 96, h = 62, label = L["被点名提示"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\target.png", accentColor = { r = 0.40, g = 1.00, b = 0.62, a = 0.95 } },
        { key = "targetAlertStartEnabled", type = "checkbox", x = 107, y = 85, w = 35, h = 5, label = L["启用"] },
        { key = "targetAlertStartLSM", type = "lsm_sound", x = 144, y = 85, w = 42, h = 5, label = "", labelPos = "left", search = true },
        { key = "targetAlertStartValueTest", type = "button", x = 189, y = 85, w = 10, h = 5, label = L["试听"] },
        { key = "targetAlertTankEnabled", type = "checkbox", x = 107, y = 95, w = 44, h = 5, label = L["坦克也生效"] },
        { key = "targetAlertRingEnabled", type = "checkbox", x = 107, y = 107, w = 20, h = 7, label = L["圆环"] },
        { key = "targetAlertIconEnabled", type = "checkbox", x = 127, y = 107, w = 20, h = 7, label = "|TInterface\\AddOns\\ExwindCore\\Textures\\umage.png:14:14:0:0|t" .. L["图标"] },
        { key = "targetAlertTextEnabledV2", type = "checkbox", x = 149, y = 107, w = 17, h = 7, label = L["文本"] },
        { key = "targetAlertStealthEnabledV2", type = "checkbox", x = 166, y = 107, w = 30, h = 7, label = "|T132089:16:16|t" .. L["隐遁提示"], labelSize = 17 },
    }
    for _, row in ipairs(rows) do
        SETTINGS_LAYOUT[#SETTINGS_LAYOUT + 1] = row
    end
    if ExwindTools and ExwindTools.RegisterModuleLayout then
        ExwindTools:RegisterModuleLayout(SPELL_SETTINGS_MODULE_KEY, SETTINGS_LAYOUT)
    end
end

local function RefreshSettingsDynamicWidgets()
    local Grid = _G.ExwindGrid
    local mdb = GetSpellEditorDB()
    if not (Grid and type(mdb) == "table") then
        return
    end
    local widgets = Grid.Widgets
    local state = settingsScrollChild and Grid.ContainerStates and Grid.ContainerStates[settingsScrollChild]
    if type(state) == "table" and type(state.widgets) == "table" then
        widgets = state.widgets
    end
    if type(widgets) ~= "table" then
        return
    end
    local selectedRow = GetSelectedSpellRow()
    local runtimeCfg = selectedRow and GetRuntimeSpellEntry(selectedRow) or nil
    local authorVoiceDisabled = type(runtimeCfg) == "table" and runtimeCfg.authorVoiceDisabled == true
    local authorVoiceDisabledText = GetAuthorVoiceDisableText(runtimeCfg)

    if settingsVoiceDisabledNote then
        if authorVoiceDisabled and authorVoiceDisabledText then
            settingsVoiceDisabledNote:SetText(authorVoiceDisabledText)
            settingsVoiceDisabledNote:Show()
        else
            settingsVoiceDisabledNote:Hide()
        end
    end

    local modeDropdownWidget = widgets["eventColorMode"]
    local customColor = widgets["eventColor"]
    local centralLeadWidget = widgets["centralLead"]
    local centralTextWidget = widgets["centralText"]
    local preAlertTextWidget = widgets["preAlertText"]
    local timerRenameTextWidget = widgets["timerBarRenameText"]
    local ringRenameTextWidget = widgets["ringRenameText"]
    local castBarRenameTextWidget = widgets["castProgressBarRenameText"]
    local targetAlertLSMWidget = widgets["targetAlertStartLSM"]
    local targetAlertValueTestWidget = widgets["targetAlertStartValueTest"]
    local targetAlertTankWidget = widgets["targetAlertTankEnabled"]
    local targetAlertRingWidget = widgets["targetAlertRingEnabled"]
    local targetAlertIconWidget = widgets["targetAlertIconEnabled"]
    local targetAlertTextWidget = widgets["targetAlertTextEnabledV2"]
    local targetAlertStealthWidget = widgets["targetAlertStealthEnabledV2"]
    if centralLeadWidget then
        centralLeadWidget:Show()
        SetWidgetUsable(centralLeadWidget, true)
    end
    if centralTextWidget then
        centralTextWidget:Show()
        SetWidgetUsable(centralTextWidget, true)
    end
    if preAlertTextWidget then
        preAlertTextWidget:Show()
        SetWidgetUsable(preAlertTextWidget, true)
    end
    if timerRenameTextWidget then
        timerRenameTextWidget:Show()
        SetWidgetUsable(timerRenameTextWidget, true)
    end
    if ringRenameTextWidget then
        ringRenameTextWidget:Show()
        SetWidgetUsable(ringRenameTextWidget, mdb.ringRenameEnabled == true)
    end
    if castBarRenameTextWidget then
        castBarRenameTextWidget:Show()
        SetWidgetUsable(castBarRenameTextWidget, mdb.castProgressBarRenameEnabled == true)
    end
    if targetAlertLSMWidget then
        targetAlertLSMWidget:Show()
        SetWidgetUsable(targetAlertLSMWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertValueTestWidget then
        targetAlertValueTestWidget:Show()
        SetWidgetUsable(targetAlertValueTestWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertTankWidget then
        targetAlertTankWidget:Show()
        SetWidgetUsable(targetAlertTankWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertRingWidget then
        targetAlertRingWidget:Show()
        SetWidgetUsable(targetAlertRingWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertIconWidget then
        targetAlertIconWidget:Show()
        SetWidgetUsable(targetAlertIconWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertTextWidget then
        targetAlertTextWidget:Show()
        SetWidgetUsable(targetAlertTextWidget, mdb.targetAlertStartEnabled == true)
    end
    if targetAlertStealthWidget then
        targetAlertStealthWidget:Show()
        SetWidgetUsable(targetAlertStealthWidget, mdb.targetAlertStartEnabled == true)
    end
    local colorOn = (mdb.eventColorEnabled == true)
    local colorMode = NormalizeEventColorMode(mdb.eventColorMode)
    SetWidgetUsable(modeDropdownWidget, colorOn)
    if customColor then
        if colorOn and colorMode == "__custom" then
            customColor:Show()
            SetWidgetUsable(customColor, true)
        else
            customColor:Hide()
        end
    end

    for i = 1, 2 do
        local prefix = "tr" .. tostring(i)
        local enabled = (mdb[prefix .. "Enabled"] == true)
        local configEnabled = enabled
        if i == 2 then
            configEnabled = (mdb[prefix .. "PlayTextEnabled"] == true)
        end
        if authorVoiceDisabled then
            enabled = false
            configEnabled = false
        end
        local source = NormalizeTriggerSource(mdb[prefix .. "Source"])

        local enabledWidget = widgets[prefix .. "Enabled"]
        local sourceWidget = widgets[prefix .. "Source"]
        local packWidget = widgets[prefix .. "Label"]
        local lsmWidget = widgets[prefix .. "LSM"]
        local pathWidget = widgets[prefix .. "Path"]
        local valueTestWidget = widgets[prefix .. "ValueTest"]
        local countdownLeadWidget = widgets[prefix .. "CountdownLead"]
        local playTextWidget = widgets[prefix .. "PlayTextEnabled"]
        local offsetModeWidget = widgets[prefix .. "OffsetMode"]
        local offsetSecondsWidget = widgets[prefix .. "OffsetSeconds"]

        SetWidgetUsable(enabledWidget, not authorVoiceDisabled)
        SetWidgetUsable(sourceWidget, configEnabled)
        if countdownLeadWidget then
            countdownLeadWidget:Show()
            SetWidgetUsable(countdownLeadWidget, enabled)
        end
        if playTextWidget then
            playTextWidget:Show()
            SetWidgetUsable(playTextWidget, enabled)
        end

        if source == "pack" then
            if packWidget then packWidget:Show() end
            if lsmWidget then lsmWidget:Hide() end
            if pathWidget then pathWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(packWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        elseif source == "lsm" then
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Show() end
            if pathWidget then pathWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(lsmWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        else
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Hide() end
            if pathWidget then pathWidget:Show() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(pathWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        end

        if offsetModeWidget then
            offsetModeWidget:Hide()
        end
        if offsetSecondsWidget then
            offsetSecondsWidget:Hide()
        end
    end
end

local function LoadSelectedSpellToEditor()
    local db = GetSpellEditorDB()
    if type(db) ~= "table" then
        return
    end
    local defaults = GetSpellEditorDefaults()
    for key in pairs(db) do
        db[key] = nil
    end
    CopyTable(db, defaults)

    local row = GetSelectedSpellRow()
    spellEditorContext = row and {
        mapID = row.mapID,
        npcID = row.npcID,
        spellID = row.spellID,
    } or nil
    local cfg = GetRuntimeSpellEntry(row)
    if type(cfg) == "table" then
        db.enabled = cfg.enabled == true
        db.showBunBar = cfg.showBunBar ~= false
        db.showTimerBar = cfg.showTimerBar ~= false
        db.showNameplate = cfg.showNameplate == true
        db.eventColorEnabled = cfg.eventColorEnabled == true
        db.eventColorMode = tostring(cfg.eventColorMode or "none")
        db.eventColor = type(cfg.eventColor) == "table" and {
            r = tonumber(cfg.eventColor.r) or 1,
            g = tonumber(cfg.eventColor.g) or 1,
            b = tonumber(cfg.eventColor.b) or 1,
            a = tonumber(cfg.eventColor.a) or 1,
        } or { r = 1, g = 1, b = 1, a = 1 }
        db.centralEnabled = cfg.centralEnabled == true
        db.centralLead = tonumber(cfg.centralLead) or 0
        db.centralText = LocalizeDynamicText(cfg.centralText or "")
        local countdownEnabled = (cfg.countdownEnabled == true) or (cfg.preAlertEnabled == true)
        local countdownLead = tonumber(cfg.countdownLead)
        if countdownLead == nil then
            countdownLead = 5
        end
        db.countdownEnabled = (countdownEnabled == true)
        db.countdownLead = tostring(NormalizeCountdownLeadSeconds(countdownLead))
        db.tr2CountdownLead = db.countdownLead
        db.preAlertEnabled = cfg.preAlertEnabled == true
        db.preAlertText = LocalizeDynamicText(cfg.countdownText or "")
        db.timerBarRenameEnabled = cfg.timerBarRenameEnabled == true
        db.timerBarRenameText = LocalizeDynamicText(cfg.timerBarName or "")
        db.ringEnabled = cfg.ringEnabled == true
        db.ringRenameEnabled = cfg.ringRenameEnabled == true
        db.ringRenameText = tostring(cfg.ringRenameText or "")
        db.castProgressBarEnabled = cfg.castProgressBarEnabled == true
        db.castProgressBarRenameEnabled = cfg.castProgressBarRenameEnabled == true
        -- Keep the cast-bar rename field consistent with the other preset text
        -- fields above: Factory stores the stable source label, while the UI
        -- shows its active-client localization (for example 群控 → CC).
        db.castProgressBarRenameText = LocalizeDynamicText(cfg.castProgressBarRenameText or "")
        db.ringCastCheckEnabled = cfg.ringCastCheckEnabled == true
        db.targetAlertStartEnabled = cfg.targetAlertStartEnabled == true
        db.targetAlertStartLSM = tostring(cfg.targetAlertStartLSM or "")
        db.targetAlertTankEnabled = cfg.targetAlertTankEnabled == true
        db.targetAlertRingEnabled = cfg.targetAlertRingEnabled == true
        db.targetAlertIconEnabled = cfg.targetAlertIconEnabled == true
        db.targetAlertTextEnabledV2 = cfg.targetAlertTextEnabledV2 == true
        db.targetAlertStealthEnabledV2 = cfg.targetAlertStealthEnabledV2 == true
        db.tr1Enabled = cfg.voice1Enabled == true
        db.tr1Source = tostring(cfg.voice1Source or "pack")
        db.tr1Label = tostring(cfg.voice1Label or "")
        db.tr1LSM = tostring(cfg.voice1LSM or "")
        db.tr1Path = tostring(cfg.voice1Path or "")
        db.tr1OffsetMode = tostring(cfg.voice1OffsetMode or "delay")
        db.tr1OffsetSeconds = tonumber(cfg.voice1OffsetSeconds) or 0
        local countdownVoiceEnabled = (cfg.countdownVoiceEnabled == true) or (cfg.voice2Enabled == true)
        local playTextEnabled = (cfg.countdownPlayName == true) or (cfg.voice2Enabled == true)
        db.tr2Enabled = (countdownVoiceEnabled == true)
        db.tr2PlayTextEnabled = (playTextEnabled == true)
        db.tr2Source = tostring(cfg.voice2Source or "pack")
        db.tr2Label = tostring(cfg.voice2Label or "")
        db.tr2LSM = tostring(cfg.voice2LSM or "")
        db.tr2Path = tostring(cfg.voice2Path or "")
        db.tr2OffsetMode = tostring(cfg.voice2OffsetMode or "delay")
        db.tr2OffsetSeconds = tonumber(cfg.voice2OffsetSeconds) or 0
    end
end

local function PersistEditorToSelectedSpell(changedKey)
    if _suspendSpellSettingPersist or Page._visible ~= true then return end
    local row, db = GetSelectedSpellRow(), GetSpellEditorDB()
    local context = spellEditorContext
    if not row or not TrashStore or not TrashStore.SetSpellEntryValue or type(db) ~= "table"
        or type(context) ~= "table" or context.mapID ~= row.mapID
        or context.npcID ~= row.npcID or context.spellID ~= row.spellID then return end
    if changedKey == "tr2CountdownLead" then
        db.countdownLead = tostring(NormalizeCountdownLeadSeconds(db.tr2CountdownLead))
    elseif changedKey == "countdownLead" then
        db.tr2CountdownLead = tostring(NormalizeCountdownLeadSeconds(db.countdownLead))
    end
    local fields = {
        enabled = { "enabled", db.enabled == true }, showBunBar = { "showBunBar", db.showBunBar == true },
        showTimerBar = { "showTimerBar", db.showTimerBar == true }, showNameplate = { "showNameplate", db.showNameplate == true },
        eventColorEnabled = { "eventColorEnabled", db.eventColorEnabled == true }, eventColorMode = { "eventColorMode", tostring(db.eventColorMode or "none") },
        eventColor = { "eventColor", type(db.eventColor) == "table" and db.eventColor or { r = 1, g = 1, b = 1, a = 1 } },
        centralEnabled = { "centralEnabled", db.centralEnabled == true }, centralLead = { "centralLead", tonumber(db.centralLead) or 0 },
        centralText = { "centralText", tostring(db.centralText or "") }, countdownEnabled = { "countdownEnabled", db.countdownEnabled == true },
        countdownLead = { "countdownLead", NormalizeCountdownLeadSeconds(db.countdownLead) }, tr2CountdownLead = { "countdownLead", NormalizeCountdownLeadSeconds(db.tr2CountdownLead) },
        preAlertText = { "countdownText", tostring(db.preAlertText or "") }, timerBarRenameEnabled = { "timerBarRenameEnabled", db.timerBarRenameEnabled == true },
        timerBarRenameText = { "timerBarName", tostring(db.timerBarRenameText or "") }, ringEnabled = { "ringEnabled", db.ringEnabled == true },
        ringRenameEnabled = { "ringRenameEnabled", db.ringRenameEnabled == true }, ringRenameText = { "ringRenameText", tostring(db.ringRenameText or "") },
        castProgressBarEnabled = { "castProgressBarEnabled", db.castProgressBarEnabled == true }, castProgressBarRenameEnabled = { "castProgressBarRenameEnabled", db.castProgressBarRenameEnabled == true },
        castProgressBarRenameText = { "castProgressBarRenameText", tostring(db.castProgressBarRenameText or "") }, ringCastCheckEnabled = { "ringCastCheckEnabled", db.ringCastCheckEnabled == true },
        targetAlertStartEnabled = { "targetAlertStartEnabled", db.targetAlertStartEnabled == true }, targetAlertStartLSM = { "targetAlertStartLSM", tostring(db.targetAlertStartLSM or "") },
        targetAlertTankEnabled = { "targetAlertTankEnabled", db.targetAlertTankEnabled == true }, targetAlertRingEnabled = { "targetAlertRingEnabled", db.targetAlertRingEnabled == true },
        targetAlertIconEnabled = { "targetAlertIconEnabled", db.targetAlertIconEnabled == true }, targetAlertTextEnabledV2 = { "targetAlertTextEnabledV2", db.targetAlertTextEnabledV2 == true },
        targetAlertStealthEnabledV2 = { "targetAlertStealthEnabledV2", db.targetAlertStealthEnabledV2 == true }, tr1Enabled = { "voice1Enabled", db.tr1Enabled == true },
        tr1Source = { "voice1Source", NormalizeTriggerSource(db.tr1Source) }, tr1Label = { "voice1Label", tostring(db.tr1Label or "") },
        tr1LSM = { "voice1LSM", tostring(db.tr1LSM or "") }, tr1Path = { "voice1Path", tostring(db.tr1Path or "") },
        tr2Enabled = { "countdownVoiceEnabled", db.tr2Enabled == true }, tr2PlayTextEnabled = { "countdownPlayName", db.tr2PlayTextEnabled == true },
        tr2Source = { "voice2Source", NormalizeTriggerSource(db.tr2Source) }, tr2Label = { "voice2Label", tostring(db.tr2Label or "") },
        tr2LSM = { "voice2LSM", tostring(db.tr2LSM or "") }, tr2Path = { "voice2Path", tostring(db.tr2Path or "") },
    }
    local field = fields[changedKey]
    if field then TrashStore.SetSpellEntryValue(row.mapID, row.npcID, row.spellID, { field[1] }, field[2]) end
end

local function RefreshDungeonButtonVisuals()
    for i = 1, #activeDungeonButtons do
        local btn = activeDungeonButtons[i]
        if btn and btn.text then
            local active = btn.mapID == selectedMapID
            local hovered = btn._hovered == true
            -- 与 Boss 页面左上副本切换完全同一视觉：外按钮透明，状态只作用于图标框。
            btn:SetBackdropColor(0, 0, 0, 0)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            if active then
                btn.iconFrame:SetBackdropColor(0.20, 0.43, 0.75, 0.95)
                btn.iconFrame:SetBackdropBorderColor(0.76, 0.80, 0.90, 1)
                btn.icon:SetDesaturated(false)
                btn.text:SetTextColor(1, 0.85, 0.35)
            elseif hovered then
                btn.iconFrame:SetBackdropColor(0.18, 0.21, 0.32, 0.95)
                btn.iconFrame:SetBackdropBorderColor(0.82, 0.86, 0.96, 1)
                btn.icon:SetDesaturated(false)
                btn.text:SetTextColor(0.95, 0.95, 0.95)
            else
                btn.iconFrame:SetBackdropColor(0.15, 0.18, 0.28, 0.95)
                btn.iconFrame:SetBackdropBorderColor(0.76, 0.80, 0.90, 1)
                btn.icon:SetDesaturated(true)
                btn.text:SetTextColor(0.75, 0.75, 0.78)
            end
        end
    end
end

local function ReleaseDungeonButtons()
    for i = 1, #activeDungeonButtons do
        local btn = activeDungeonButtons[i]
        btn:Hide()
        btn:ClearAllPoints()
        btn:SetParent(nil)
        table.insert(dungeonButtonPool, btn)
    end
    wipe(activeDungeonButtons)
end

local function ReleaseSpellRows()
    for i = 1, #activeSpellRows do
        local row = activeSpellRows[i]
        if row then
            row:Hide()
            row:ClearAllPoints()
            row:SetParent(nil)
            if row._divider then
                spellDividerPool[#spellDividerPool + 1] = row
            else
                spellRowPool[#spellRowPool + 1] = row
            end
        end
    end
    wipe(activeSpellRows)
end

local function AcquireDungeonButton()
    local btn = table.remove(dungeonButtonPool)
    if btn then
        return btn
    end

    btn = CreateFrame("Button", nil, mapScrollChild, "BackdropTemplate")
    btn:SetSize(90, 106)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    btn.iconFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.iconFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn.iconFrame:SetSize(70, 70)
    btn.iconFrame:SetPoint("TOP", 0, -1)

    btn.icon = EXUI:CreateVisualTexture(btn.iconFrame, EXBASEFRAME)
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.text = EXUI:CreateVisualFontString(btn, EXFONTFRAME, "GameFontNormalSmall")
    btn.text:SetPoint("TOP", btn.iconFrame, "BOTTOM", 0, -2)
    btn.text:SetWidth(84)
    btn.text:SetJustifyH("CENTER")
    btn.text:SetWordWrap(false)
    btn.text:SetFont(ExwindTools.MAIN_FONT, 13, "OUTLINE")

    btn:SetScript("OnEnter", function(self)
        self._hovered = true
        RefreshDungeonButtonVisuals()
    end)
    btn:SetScript("OnLeave", function(self)
        self._hovered = false
        RefreshDungeonButtonVisuals()
    end)

    return btn
end

local function AcquireSpellRow()
    local row = table.remove(spellRowPool)
    if row then
        return row
    end

    row = CreateFrame("Button", nil, spellScrollChild, "BackdropTemplate")
    row:SetHeight(C.SPELL_CARD.height)
    row:EnableMouse(true)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.02, 0.02, 0.03, 0.86)
    row:SetBackdropBorderColor(0.25, 0.25, 0.28, 0.90)

    row.leftBar = EXUI:CreateVisualTexture(row, EXBACKGROUNDFRAME)
    row.leftBar:SetWidth(4)
    row.leftBar:SetPoint("TOPLEFT", 0, 0)
    row.leftBar:SetPoint("BOTTOMLEFT", 0, 0)

    local check = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
    check:SetSize(22, 22)
    check:SetPoint("LEFT", 6, 0)
    row.check = check

    local icon = EXUI:CreateVisualTexture(row, EXBASEFRAME)
    icon:SetSize(29, 29)
    icon:SetPoint("LEFT", check, "RIGHT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local alertIcon = EXUI:CreateVisualTexture(row, EXBORDERFRAME)
    alertIcon:SetSize(22, 22)
    alertIcon:SetPoint("LEFT", check, "RIGHT", 6, 0)
    alertIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    alertIcon:Hide()
    row.alertIcon = alertIcon

    local textBlock = CreateFrame("Frame", nil, row)
    textBlock:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    textBlock:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    textBlock:SetPoint("CENTER", row, "CENTER", 0, 0)
    textBlock:SetHeight(32)
    row.textBlock = textBlock

    local label = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", textBlock, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetMaxLines(2)
    label:SetSpacing(1)
    label:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")
    row.label = label

    local atlasHolder = CreateFrame("Frame", nil, row)
    atlasHolder:SetPoint("RIGHT", textBlock, "RIGHT", 0, -1)
    atlasHolder:SetSize(35, 35)
    atlasHolder:EnableMouse(true)
    atlasHolder:Hide()
    row.testAtlasHolder = atlasHolder

    local atlas = EXUI:CreateVisualTexture(atlasHolder, EXBORDERFRAME)
    atlas:SetAllPoints()
    row.testAtlas = atlas

    atlasHolder:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L[TEST_THREAT_ATLAS_TOOLTIP], 0.20, 1.00, 0.20, true)
        GameTooltip:Show()
    end)
    atlasHolder:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    label:SetPoint("RIGHT", atlasHolder, "LEFT", -6, 0)

    local meta = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontDisableSmall")
    meta:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    meta:SetPoint("TOPRIGHT", textBlock, "BOTTOMRIGHT", 0, -4)
    meta:SetJustifyH("LEFT")
    meta:SetJustifyV("TOP")
    meta:SetWordWrap(false)
    meta:SetFont(ExwindTools.MAIN_FONT, 13, "")
    meta:SetTextColor(0.72, 0.76, 0.82)
    row.meta = meta

    row:SetScript("OnEnter", function(self)
        self._hovered = true
        if self._applyVisual then self:_applyVisual() end
    end)
    row:SetScript("OnLeave", function(self)
        self._hovered = false
        if self._applyVisual then self:_applyVisual() end
    end)

    return row
end

local function RefreshSpellRowVisuals()
    for i = 1, #activeSpellRows do
        local row = activeSpellRows[i]
        if row then
            row._selected = (row.npcID == selectedNPCID and row.spellID == selectedSpellID)
        end
        if row and row._applyVisual then
            row:_applyVisual()
        end
    end
end

local function UpdateDetailCard()
    if not detailTitle then
        return
    end
    local row = GetSelectedSpellRow()
    if not row then
        SetDetailCardEmpty(L["点击左侧法术后，可在此查看法术描述。"])
        return
    end

    local cfg = GetRuntimeSpellEntry(row)
    local cachedName, icon = GetRowSpellNameAndIcon(row)
    local desc = GetRowSpellDescription(row)
    local castLine, bodyText = SplitSpellDescription(desc)
    local displayName = tostring(row.spellName or "")
    if cachedName and cachedName ~= "" then
        displayName = cachedName
    end
    local cdText = FormatCDList(row.cd)
    local infoLines = {
        string.format("%s：%s", L["首次施放时间"], tostring(row.first or "-")),
        string.format("%s：%s", L["CD时间"], cdText),
    }

    if detailPlaceholder then detailPlaceholder:Hide() end
    detailIcon:Show()
    detailIcon:SetTexture(icon or 134400)
    detailTitle:SetText(displayName)
    detailMeta:SetText(string.format("%s  |cff7f8794spell:%s|r", tostring(row.mobName or "-"),
        tostring(row.spellID or "-")))
    detailCast:SetText((castLine ~= "" and tostring(castLine)) or L["暂无施法信息"])
    detailBody:SetText((bodyText ~= "" and tostring(bodyText)) or L["暂无描述。"])
    detailInfo:SetText(table.concat(infoLines, "\n"))
    if detailDivider then
        detailDivider:Show()
    end
    RefreshDetailCardLayout()
end

local function BuildDungeonButtons()
    ReleaseDungeonButtons()
    if not mapScrollChild then
        return
    end

    local rows = GetDungeonRows()
    local perRow = 4
    local gapX = 3
    local gapY = 2
    local leftPad = 0
    local topPad = 0
    local availableWidth = (mapScrollChild:GetWidth() or 208) - (leftPad * 2)
    if availableWidth < 200 then availableWidth = 200 end
    local gridWidth = math.max(1, availableWidth - ((perRow - 1) * gapX))
    local columnUnit = gridWidth / perRow
    local cellHeight = 106
    local contentHeight = 0

    for i = 1, #rows do
        local row = rows[i]
        local btn = AcquireDungeonButton()
        btn:SetParent(mapScrollChild)
        btn.mapID = row.mapID

        local gridRow = math.floor((i - 1) / perRow)
        local gridCol = (i - 1) % perRow
        -- 原生布局按像素边界向上取整。不能只把 cellWidth 改为 ceil：四列
        -- 会累加溢出。以左右边界分别 ceil 后取差，既向上取整又严格填满可视宽度。
        local cellLeft = math.ceil(gridCol * columnUnit)
        local cellRight = math.ceil((gridCol + 1) * columnUnit)
        local cellWidth = math.max(1, cellRight - cellLeft)
        btn:SetSize(cellWidth, cellHeight)
        local iconSize = math.min(90, math.max(46, cellWidth - 2))
        btn.iconFrame:SetSize(iconSize, iconSize)
        btn.iconFrame:ClearAllPoints()
        btn.iconFrame:SetPoint("TOP", 0, -1)
        btn.text:SetWidth(math.max(1, cellWidth - 4))
        btn:SetPoint("TOPLEFT", leftPad + cellLeft + gridCol * gapX,
            -topPad - gridRow * (cellHeight + gapY))
        btn.icon:SetTexture(GetMapIcon(row.mapID))
        btn.text:SetText(GetMapShortDisplayName(row.mapID))
        btn:Show()

        btn:SetScript("OnClick", function(self)
            selectedMapID = self.mapID
            selectedNPCID = nil
            selectedSpellID = nil
            RefreshDungeonButtonVisuals()
            Page:RefreshSpellList()
        end)

        activeDungeonButtons[#activeDungeonButtons + 1] = btn
        contentHeight = gridRow * (cellHeight + gapY) + cellHeight
    end

    -- 只更新内容高度，绝不覆盖宿主已分配的左栏宽度。
    mapScrollChild:SetHeight(math.max(1, contentHeight + topPad + 4))

    RefreshDungeonButtonVisuals()
end

function Page:RefreshSpellList()
    _spellListBuildToken = _spellListBuildToken + 1
    local token = _spellListBuildToken
    ReleaseSpellRows()
    if not spellScrollChild then
        return
    end

    local rows = GetSpellRows(selectedMapID)
    local enabledRows = {}
    local disabledRows = {}
    for i = 1, #rows do
        local cfg = GetRuntimeSpellEntry(rows[i])
        if type(cfg) == "table" then
            if cfg.enabled == true then
                enabledRows[#enabledRows + 1] = rows[i]
            else
                disabledRows[#disabledRows + 1] = rows[i]
            end
        end
    end
    local orderedRows = {}
    for i = 1, #enabledRows do orderedRows[#orderedRows + 1] = enabledRows[i] end
    for i = 1, #disabledRows do orderedRows[#orderedRows + 1] = disabledRows[i] end
    local function IsValid()
        return token == _spellListBuildToken and Page._visible and spellScrollChild ~= nil
    end

    local function BuildOne(rowData, index, cardW)
        local cfg = GetRuntimeSpellEntry(rowData)
        if type(cfg) ~= "table" then
            return
        end
        local row = AcquireSpellRow()
        row:SetParent(spellScrollChild)
        local col = (index - 1) % C.SPELL_CARD.cols
        local gridRow = math.floor((index - 1) / C.SPELL_CARD.cols)
        local x = col * (cardW + C.SPELL_CARD.gapX)
        local y = -4 - gridRow * (C.SPELL_CARD.height + C.SPELL_CARD.gapY)
        row:SetSize(cardW, C.SPELL_CARD.height)
        row:SetPoint("TOPLEFT", 0 + x, y)
        row.npcID = rowData.npcID
        row.spellID = rowData.spellID
        row.icon:SetTexture(GetRowSpellIcon(rowData))
        row._enabled = cfg.enabled == true
        row.check:SetChecked(cfg.enabled == true)
        row.label:SetText(tostring(rowData.spellName or ""))
        local borderR, borderG, borderB = ResolveSpellEntryBorderColor(cfg)
        if borderR == nil or borderG == nil or borderB == nil then
            borderR, borderG, borderB = 0.38, 0.38, 0.38
        end
        row._borderR = borderR
        row._borderG = borderG
        row._borderB = borderB
        row.icon:ClearAllPoints()
        local eventTypeAtlas = ResolveEventTypeIcon(rowData.eventType)
        if eventTypeAtlas and row.alertIcon and row.alertIcon.SetAtlas then
            row.alertIcon:SetAtlas(eventTypeAtlas, false)
            row.alertIcon:Show()
            row.icon:SetPoint("LEFT", row.alertIcon, "RIGHT", 6, 0)
        else
            if row.alertIcon then
                row.alertIcon:Hide()
            end
            row.icon:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
        end
        if TEST_THREAT_ATLAS_SPELLS[tonumber(rowData.spellID)] then
            row.testAtlas:SetAtlas(TEST_THREAT_ATLAS_NAME, false)
            row.testAtlasHolder:Show()
        else
            row.testAtlasHolder:Hide()
        end
        row.meta:SetText(string.format("%s  |cff7f8794spell:%s|r", tostring(rowData.mobName or ""),
            tostring(rowData.spellID or "-")))
        row._selected = (rowData.npcID == selectedNPCID and rowData.spellID == selectedSpellID)
        row._hovered = false
        row._applyVisual = function(self)
            local br = Clamp01(self._borderR, 0.38)
            local bg = Clamp01(self._borderG, 0.38)
            local bb = Clamp01(self._borderB, 0.38)
            if self._selected then
                self:SetBackdropColor(0.08, 0.18, 0.30, 0.95)
                self:SetBackdropBorderColor(Clamp01(br * 1.15, 1), Clamp01(bg * 1.15, 1), Clamp01(bb * 1.15, 1), 1)
                self.leftBar:SetColorTexture(Clamp01(br * 1.15, 1), Clamp01(bg * 1.15, 1), Clamp01(bb * 1.15, 1), 1)
            elseif self._hovered then
                self:SetBackdropColor(0.08, 0.08, 0.08, 0.88)
                self:SetBackdropBorderColor(Clamp01(br * 1.08, 1), Clamp01(bg * 1.08, 1), Clamp01(bb * 1.08, 1), 1)
                self.leftBar:SetColorTexture(Clamp01(br * 1.08, 1), Clamp01(bg * 1.08, 1), Clamp01(bb * 1.08, 1), 1)
            else
                self:SetBackdropColor(0.04, 0.04, 0.04, 0.8)
                self:SetBackdropBorderColor(br, bg, bb, 0.95)
                self.leftBar:SetColorTexture(br, bg, bb, 0.95)
            end
            if self._enabled == true then
                self.icon:SetVertexColor(1, 1, 1)
                self.label:SetTextColor(self._selected and 1 or 0.95, self._selected and 0.86 or 0.95,
                    self._selected and 0.48 or 0.95)
                self.meta:SetTextColor(0.72, 0.76, 0.82)
            else
                self.icon:SetVertexColor(0.55, 0.55, 0.55)
                self.label:SetTextColor(0.62, 0.62, 0.64)
                self.meta:SetTextColor(0.48, 0.48, 0.52)
            end
        end

        row.check:SetScript("OnClick", function(self)
            if TrashStore and TrashStore.SetSpellEntryValue then
                TrashStore.SetSpellEntryValue(rowData.mapID, rowData.npcID, rowData.spellID, { "enabled" }, self:GetChecked() == true)
            end
            selectedNPCID = rowData.npcID
            selectedSpellID = rowData.spellID
            Page:RefreshSelectedSpell()
        end)

        row:SetScript("OnClick", function()
            selectedNPCID = rowData.npcID
            selectedSpellID = rowData.spellID
            RefreshSpellRowVisuals()
            Page:RefreshSelectedSpell()
        end)

        row:_applyVisual()
        row:Show()
        activeSpellRows[#activeSpellRows + 1] = row
    end

    local function Finalize()
        if not IsValid() then
            return
        end
        local totalRows = math.max(1, math.ceil(#orderedRows / C.SPELL_CARD.cols))
        local totalH = totalRows * C.SPELL_CARD.height + math.max(0, totalRows - 1) * C.SPELL_CARD.gapY + 8
        spellScrollChild:SetHeight(math.max(200, totalH))
        if not selectedNPCID and not selectedSpellID and orderedRows[1] then
            selectedNPCID = orderedRows[1].npcID
            selectedSpellID = orderedRows[1].spellID
        end
        PrimeSpellCache(orderedRows)
        RefreshSpellRowVisuals()
        Page:RefreshSelectedSpell()
    end

    local function BuildSync()
        local totalW = (spellScrollChild:GetWidth() or 360)
        if totalW < 240 then totalW = 360 end
        local usableW = math.max(240, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        for i = 1, #orderedRows do
            BuildOne(orderedRows[i], i, cardW)
        end
        Finalize()
    end

    local function BuildAsync()
        local totalW = (spellScrollChild:GetWidth() or 360)
        if totalW < 240 then totalW = 360 end
        local usableW = math.max(240, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        for i = 1, #orderedRows do
            if not IsValid() then
                return
            end
            BuildOne(orderedRows[i], i, cardW)
            coroutine.yield()
        end
        Finalize()
    end

    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            BuildAsync()
        end, "EXBoss_TrashCD_SpellList", true)
    else
        BuildSync()
    end
end

local function RefreshSelectedSpellSync()
    _suspendSpellSettingPersist = true
    LoadSelectedSpellToEditor()
    _suspendSpellSettingPersist = false
    UpdateDetailCard()
    Page:RenderSettingsGrid(true)
end

GetRowSpellDescription = function(row)
    return GetSpellDescription(type(row) == "table" and row.spellID or nil)
end

function Page:RefreshSelectedSpell()
    _selectionRefreshToken = _selectionRefreshToken + 1
    local token = _selectionRefreshToken

    local function IsValid()
        return token == _selectionRefreshToken and Page._visible and root ~= nil
    end

    local function RunAsync()
        if not IsValid() then
            return
        end
        _suspendSpellSettingPersist = true
        LoadSelectedSpellToEditor()
        _suspendSpellSettingPersist = false
        coroutine.yield()
        if not IsValid() then
            return
        end
        UpdateDetailCard()
        coroutine.yield()
        if not IsValid() then
            return
        end
        Page:RenderSettingsGrid(true)
    end

    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            RunAsync()
        end, "EXBoss_TrashCD_SelectedSpell", true)
    else
        RefreshSelectedSpellSync()
    end
end

function Page:RenderSettingsGrid(resetScroll)
    if not (settingsScrollChild and settingsPane and settingsPane:IsShown()) then
        return
    end
    local Grid = _G.ExwindGrid
    if not Grid then
        return
    end
    BuildSettingsLayout()
    local db = GetSpellEditorDB()
    local w = settingsPane:GetWidth()
    if w < 100 then
        w = 860
    end
    settingsScrollChild:SetWidth(w - 42)
    if resetScroll == true then
        settingsScrollFrame:SetVerticalScroll(0)
    end
    if Grid.SetContainerCols then
        Grid:SetContainerCols(settingsScrollChild, 200)
    end
    if Grid.SetContainerPadding then
        Grid:SetContainerPadding(settingsScrollChild, { left = 0, right = 10, top = 10, bottom = 0 })
    end
    RegisterSpellSettingsGridAsActive(SPELL_SETTINGS_MODULE_KEY)
    Grid:Render(settingsScrollChild, SETTINGS_LAYOUT, db, SPELL_SETTINGS_MODULE_KEY)
    RefreshSettingsDynamicWidgets()
end

local function EnsureUI(parent)
    if root then
        return
    end

    root = CreateFrame("Frame", nil, parent)
    root:SetAllPoints(parent)

    local leftW = 380
    local topLeftH = 212
    local topRightH = 170
    local gap = 8

    -- Boss 页左上没有副本选择的外层 Backdrop；这里只保留不可见定位容器，滚动框自身
    -- 即为唯一可见边界，消除小怪页多出来的一层嵌套框。
    mapPane = CreateFrame("Frame", nil, root)
    mapPane:SetPoint("TOPLEFT", 8, -8)
    mapPane:SetSize(leftW, topLeftH)

    -- 左栏下半部与 Boss 页一致：仅作布局宿主，不再套一层可见 Backdrop。
    -- 每条法术卡片保留自己的边框，避免“列表外框 + 卡片外框”的双重嵌套。
    spellPane = CreateFrame("Frame", nil, root)
    spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", 0, -gap)
    spellPane:SetPoint("BOTTOMLEFT", 8, 8)
    spellPane:SetWidth(leftW)

    detailPane = CreateSectionBackdrop(root)
    detailPane:SetPoint("TOPLEFT", mapPane, "TOPRIGHT", gap, 0)
    detailPane:SetPoint("TOPRIGHT", -8, -8)
    detailPane:SetHeight(topRightH)

    settingsPane = CreateSectionBackdrop(root)
    settingsPane:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -gap)
    settingsPane:SetPoint("BOTTOMRIGHT", -8, 8)

    mapScrollFrame = CreateFrame("ScrollFrame", nil, mapPane, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(mapScrollFrame)
    end
    mapScrollFrame:SetPoint("TOPLEFT", mapPane, "TOPLEFT", 0, -8)
    mapScrollFrame:SetPoint("TOPRIGHT", mapPane, "TOPRIGHT", -8, -8)
    mapScrollFrame:SetPoint("BOTTOMLEFT", mapPane, "BOTTOMLEFT", 0, 2)
    mapScrollFrame:SetPoint("BOTTOMRIGHT", mapPane, "BOTTOMRIGHT", -8, 2)

    mapScrollChild = CreateFrame("Frame", nil, mapScrollFrame)
    mapScrollChild:SetSize(208, 1)
    mapScrollFrame:SetScrollChild(mapScrollChild)

    spellScrollFrame = CreateFrame("ScrollFrame", nil, spellPane, "ScrollFrameTemplate")
    spellScrollFrame:SetPoint("TOPLEFT", spellPane, "TOPLEFT", 0, 0)
    spellScrollFrame:SetPoint("BOTTOMRIGHT", spellPane, "BOTTOMRIGHT", -4, 0)
    spellScrollChild = CreateFrame("Frame", nil, spellScrollFrame)
    spellScrollChild:SetWidth(leftW - 30)
    spellScrollChild:SetHeight(300)
    spellScrollFrame:SetScrollChild(spellScrollChild)

    detailPlaceholder = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontDisableSmall")
    detailPlaceholder:SetPoint("CENTER", 0, 0)
    detailPlaceholder:SetTextColor(0.55, 0.55, 0.6)
    detailPlaceholder:SetText(L["点击左侧法术后，可在此查看法术描述。"])

    detailIcon = EXUI:CreateVisualTexture(detailPane, EXBASEFRAME)
    detailIcon:SetSize(52, 52)
    detailIcon:SetPoint("TOPLEFT", 10, -12)
    detailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    detailTitle = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontNormalLarge")
    detailTitle:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 8, -1)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetWordWrap(false)
    detailTitle:SetFont(ExwindTools.MAIN_FONT, 23, "OUTLINE")
    detailTitle:SetTextColor(1, 0.95, 0.55)

    detailMeta = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontHighlight")
    detailMeta:SetPoint("LEFT", detailTitle, "RIGHT", 10, 0)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetWordWrap(false)
    detailMeta:SetFont(ExwindTools.MAIN_FONT, 16, "")
    detailMeta:SetTextColor(0.55, 0.57, 0.62)

    detailCast = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontNormal")
    detailCast:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -2)
    detailCast:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailCast:SetJustifyH("LEFT")
    detailCast:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    detailCast:SetTextColor(0.92, 0.92, 0.95)

    detailBody = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontHighlight")
    detailBody:SetPoint("TOPLEFT", detailCast, "BOTTOMLEFT", 0, -8)
    detailBody:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailBody:SetJustifyH("LEFT")
    detailBody:SetJustifyV("TOP")
    detailBody:SetWordWrap(true)
    detailBody:SetSpacing(2)
    detailBody:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")
    detailBody:SetTextColor(1, 0.82, 0.2)

    detailDivider = EXUI:CreateVisualTexture(detailPane, EXBORDERFRAME)
    detailDivider:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 10)
    detailDivider:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -14, 10)
    detailDivider:SetHeight(1)
    detailDivider:SetColorTexture(1, 1, 1, 0.14)
    detailDivider:Hide()

    detailInfo = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontHighlightSmall")
    detailInfo:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 16)
    detailInfo:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailInfo:SetJustifyH("LEFT")
    detailInfo:SetJustifyV("BOTTOM")
    detailInfo:SetWordWrap(true)
    detailInfo:SetTextColor(0.82, 0.86, 0.92)

    local settingsTitle = EXUI:CreateVisualFontString(settingsPane, EXFONTFRAME, "GameFontNormal")
    settingsTitle:SetPoint("TOPLEFT", 10, -8)
    settingsTitle:SetText(L["当前法术设置"])
    settingsTitle:SetTextColor(1, 0.82, 0.45)
    settingsTitle:SetFont(ExwindTools.MAIN_FONT, 14, "OUTLINE")

    settingsVoiceDisabledNote = EXUI:CreateVisualFontString(settingsPane, EXFONTFRAME, "GameFontNormalSmall")
    settingsVoiceDisabledNote:SetPoint("TOPLEFT", settingsPane, "TOPLEFT", 150, -10)
    settingsVoiceDisabledNote:SetPoint("RIGHT", settingsPane, "RIGHT", -28, 0)
    settingsVoiceDisabledNote:SetJustifyH("LEFT")
    settingsVoiceDisabledNote:SetWordWrap(true)
    settingsVoiceDisabledNote:SetTextColor(1, 0.82, 0.25)
    settingsVoiceDisabledNote:Hide()

    settingsScrollFrame = CreateFrame("ScrollFrame", nil, settingsPane, "ScrollFrameTemplate")
    settingsScrollFrame:SetPoint("TOPLEFT", 2, -30)
    settingsScrollFrame:SetPoint("BOTTOMRIGHT", settingsPane, "BOTTOMRIGHT", -22, 4)
    settingsScrollChild = CreateFrame("Frame", nil, settingsScrollFrame)
    settingsScrollChild:SetWidth(900)
    settingsScrollChild:SetHeight(420)
    settingsScrollFrame:SetScrollChild(settingsScrollChild)

    if ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(spellScrollFrame)
        ExBoss.UI.ApplyModernScrollBarSkin(settingsScrollFrame)
    end
    SetDetailCardEmpty(L["点击左侧法术后，可在此查看法术描述。"])
end

-- Unified Shell 的 B+C 必须由 Core 按 20:80 分配。本页原本把这套结构硬编码
-- 在单一 root 的 380px 左栏内；这里仅重新挂接既有 pane，不改副本/法术/设置数据。
local function ApplyHostLayout(leftHost, contentHost)
    if not root or not contentHost then return end
    local gap = 8

    root:SetParent(contentHost)
    root:ClearAllPoints()
    root:SetAllPoints(contentHost)

    if leftHost then
        mapPane:SetParent(leftHost)
        mapPane:ClearAllPoints()
        mapPane:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 8, -8)
        mapPane:SetPoint("TOPRIGHT", leftHost, "TOPRIGHT", -8, -8)
        mapPane:SetHeight(212)

        spellPane:SetParent(leftHost)
        spellPane:ClearAllPoints()
        spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", 0, -gap)
        spellPane:SetPoint("BOTTOMRIGHT", leftHost, "BOTTOMRIGHT", -8, 8)

        detailPane:SetParent(contentHost)
        detailPane:ClearAllPoints()
        detailPane:SetPoint("TOPLEFT", contentHost, "TOPLEFT", 8, -8)
        detailPane:SetPoint("TOPRIGHT", contentHost, "TOPRIGHT", -8, -8)
        detailPane:SetHeight(170)

        settingsPane:SetParent(contentHost)
        settingsPane:ClearAllPoints()
        settingsPane:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -gap)
        settingsPane:SetPoint("BOTTOMRIGHT", contentHost, "BOTTOMRIGHT", -8, 8)

        -- 必须以 ScrollFrame 的实际可视宽度为准。此前 mapPane / scrollbar 的两次
        -- 留边没有同步，内容比视口宽 16px，第四列就会被右侧裁切。
        if mapScrollChild and mapScrollFrame then
            mapScrollChild:SetWidth(math.max(1, (mapScrollFrame:GetWidth() or 0) - 4))
        end
        if spellScrollChild and spellScrollFrame then
            spellScrollChild:SetWidth(math.max(1, (spellScrollFrame:GetWidth() or 0) - 4))
        end
    else
        mapPane:SetParent(root)
        mapPane:ClearAllPoints()
        mapPane:SetPoint("TOPLEFT", 8, -8)
        mapPane:SetSize(380, 212)

        spellPane:SetParent(root)
        spellPane:ClearAllPoints()
        spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", 0, -gap)
        spellPane:SetPoint("BOTTOMLEFT", 8, 8)
        spellPane:SetWidth(380)

        detailPane:SetParent(root)
        detailPane:ClearAllPoints()
        detailPane:SetPoint("TOPLEFT", mapPane, "TOPRIGHT", gap, 0)
        detailPane:SetPoint("TOPRIGHT", -8, -8)
        detailPane:SetHeight(170)

        settingsPane:SetParent(root)
        settingsPane:ClearAllPoints()
        settingsPane:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -gap)
        settingsPane:SetPoint("BOTTOMRIGHT", -8, 8)
        if mapScrollChild and mapScrollFrame then
            mapScrollChild:SetWidth(math.max(1, (mapScrollFrame:GetWidth() or 0) - 4))
        end
        if spellScrollChild and spellScrollFrame then
            spellScrollChild:SetWidth(math.max(1, (spellScrollFrame:GetWidth() or 0) - 4))
        end
    end

    mapPane:Show()
    spellPane:Show()
    detailPane:Show()
    settingsPane:Show()
end

if ExwindTools and type(ExwindTools.WatchState) == "function" then
    ExwindTools:WatchState(SPELL_SETTINGS_MODULE_KEY .. ".ButtonClicked", "ExBoss.TrashCD.SpellEditorButton",
        function(info)
            if Page._visible ~= true then
                return
            end
            local db = GetSpellEditorDB()
            if type(db) ~= "table" or type(info) ~= "table" then
                return
            end
            if info.key == "tr1ValueTest" then
                PlayVoicePreview(db.tr1Source, db.tr1Label, db.tr1LSM, db.tr1Path)
            elseif info.key == "tr2ValueTest" then
                PlayVoicePreview(db.tr2Source, db.tr2Label, db.tr2LSM, db.tr2Path)
            elseif info.key == "targetAlertStartValueTest" then
                PlayVoicePreview("lsm", "", db.targetAlertStartLSM, "")
            end
        end)
end

-- The Core controller intentionally receives no field route.  Persist every
-- current draft field as the editor's single reapply transaction.
local function RefreshActiveSurfaces()
    if Page._visible ~= true then return end
    local fields = {
        "enabled", "showBunBar", "showTimerBar", "showNameplate",
        "eventColorEnabled", "eventColorMode", "eventColor", "centralEnabled",
        "centralLead", "centralText", "countdownEnabled", "countdownLead",
        "tr2CountdownLead", "preAlertText", "timerBarRenameEnabled",
        "timerBarRenameText", "ringEnabled", "ringRenameEnabled", "ringRenameText",
        "castProgressBarEnabled", "castProgressBarRenameEnabled", "castProgressBarRenameText",
        "ringCastCheckEnabled", "targetAlertStartEnabled", "targetAlertStartLSM",
        "targetAlertTankEnabled", "targetAlertRingEnabled", "targetAlertIconEnabled",
        "targetAlertTextEnabledV2", "targetAlertStealthEnabledV2", "tr1Enabled",
        "tr1Source", "tr1Label", "tr1LSM", "tr1Path", "tr2Enabled",
        "tr2PlayTextEnabled", "tr2Source", "tr2Label", "tr2LSM", "tr2Path",
    }
    for _, key in ipairs(fields) do PersistEditorToSelectedSpell(key) end
    RefreshSettingsDynamicWidgets()
end

if EXUI then
    EXUI:RegisterModuleValueController(SPELL_SETTINGS_MODULE_KEY, {
        RefreshActiveSurfaces = RefreshActiveSurfaces,
    })
end

if ExwindTools and not Page._eventsRegistered then
    ExwindTools:RegisterEvent("SPELL_DATA_LOAD_RESULT", "ExBoss.TrashCDPage.SpellCache", function(_, spellID, success)
        if spellID then
            CACHE.spellCachePending[spellID] = nil
            CACHE.spellTextCache[spellID] = nil
        end
        if not success then
            return
        end
        if Page._visible and CurrentTrashHasSpellID(spellID) then
            Page:RefreshSelectedSpell()
        end
    end)

    ExwindTools:RegisterEvent("SPELL_TEXT_UPDATE", "ExBoss.TrashCDPage.SpellText", function()
        wipe(CACHE.spellTextCache)
        if Page._visible then
            Page:RefreshSelectedSpell()
        end
    end)

    Page._eventsRegistered = true
end

function Page:Render(leftHost, contentFrame)
    -- 兼容旧独立面板调用：Render(contentFrame)。
    if contentFrame == nil then
        contentFrame = leftHost
        leftHost = nil
    end
    if not contentFrame then return end
    EnsureUI(contentFrame)
    ApplyHostLayout(leftHost, contentFrame)
    root:Show()
    Page._visible = true

    if TrashCore and TrashCore.SetMonitorUIEnabled then
        TrashCore.SetMonitorUIEnabled(true)
    end
    if not selectedMapID then
        selectedMapID = ResolveDefaultMapID()
    end

    BuildDungeonButtons()
    self:RefreshSpellList()
end

function Page:Hide()
    Page._visible = false
    -- 页面显示值永远不跨页面保存；下次显示重新读取当前 Runtime。
    spellEditorDraft = nil
    spellEditorContext = nil
    _suspendSpellSettingPersist = false
    ClearSpellSettingsGridActiveRegistration()
    if TrashCore and TrashCore.SetMonitorUIEnabled then
        TrashCore.SetMonitorUIEnabled(false)
    end
    if root then
        root:Hide()
    end
    if mapPane then mapPane:Hide() end
    if spellPane then spellPane:Hide() end
    if detailPane then detailPane:Hide() end
    if settingsPane then settingsPane:Hide() end
end
