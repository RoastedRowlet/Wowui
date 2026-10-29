---@diagnostic disable: undefined-global, undefined-field

ExBoss.UI.Panel.TrashCDPage = ExBoss.UI.Panel.TrashCDPage or {}
local Page = ExBoss.UI.Panel.TrashCDPage

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local GC = ExwindTools and ExwindTools.GUIColors
local GM = ExwindTools and ExwindTools.GUIMetrics
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
        -- 小怪页使用左侧单列技能导航；右侧只承载详情与设置。
        cols = 1,
        gapX = 0,
        gapY = 2,
        height = 40,
        titleFontSizes = { GM.font.exboss.navigationTitle, GM.font.title, GM.font.exboss.previewText, GM.font.moduleDescription },
    },
    SPELL_DETAIL_HEIGHT = 148,
    VOICE_TIMELINE_HEIGHT = 84,
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

local TRIGGER_SOURCE_ITEMS = {
    { L["语音包标签"], "pack" },
    { L["LSM音效"], "lsm" },
    { L["自定义路径"], "file" },
}
local COUNTDOWN_LEAD_ITEMS = {
    { "5", "5" },
    { "4", "4" },
    { "3", "3" },
    { "2", "2" },
    { "1", "1" },
}
local SETTINGS_LAYOUT = {}
local settingsAuthorVoiceNotice
local CACHE = {
    challengeMapLookup = nil,
    spellTextCache = {},
    spellCachePending = {},
    spellRowsByMap = {},
}

local root
local mapPane
local spellPane
local spellTitle
local detailPane
local detailSurface
local settingsPane
local mapScrollFrame
local mapScrollChild
local spellScrollFrame
local spellScrollChild
local settingsScrollFrame
local settingsScrollChild
local detailIcon
local detailIconBorder
local detailPlaceholder
local detailTitle
local detailMeta
local detailCast
local detailCastChip
local detailBody
local detailBodyScroll
local detailBodyChild
local detailInfo
local detailDivider
local detailEnableHost
local detailOutputHost
local detailRangeChip
local detailRangeValue
local detailFirstChip
local detailFirstValue
local detailCDChip
local detailCDValue
local detailSpellIDChip
local detailSpellIDValue
local voicePreviewTimeline
local voicePreviewSurface
local voicePreviewGeneration = 0

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
local _spellListBuildToken = 0
local _selectionRefreshToken = 0
local LayoutTrashQuickRow

local function RegisterSpellSettingsAsActive(moduleKey)
    if not (Page._visible and settingsScrollChild and ExwindTools and ExwindTools.UI) then
        return
    end
    ExwindTools.UI.ActivePageFrame = settingsScrollChild
    if type(moduleKey) == "string" and moduleKey ~= "" then
        ExwindTools.UI.CurrentModule = moduleKey
    end
end

local function ClearSpellSettingsActiveRegistration()
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

-- 页面分帧任务的每帧预算（毫秒）。
local FRAME_TASK_BUDGET_MS = 6

local function CreateSectionBackdrop(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(unpack(GC.panel))
    frame:SetBackdropBorderColor(unpack(GC.panelBorder))
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
                return L[shortCN]
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
            for _, line in ipairs(tip.lines) do
                local text = line and line.leftText
                if line.type == Enum.TooltipDataLineType.SpellDescription and text and text ~= "" then
                    text = NormalizeSpellDescText(text)
                    if text ~= "" then
                        lines[#lines + 1] = WrapColorText(text, line.leftColor)
                    end
                end
            end
            if #lines > 0 then
                local desc = table.concat(lines, "\n")
                CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
                CACHE.spellTextCache[spellID].desc = desc
                return desc
            end
        end
    end
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
        if ok and desc and desc ~= "" then
            desc = NormalizeSpellDescText(desc)
            CACHE.spellTextCache[spellID] = CACHE.spellTextCache[spellID] or {}
            CACHE.spellTextCache[spellID].desc = desc
            return desc
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

local function GetSpellSummaryFacts(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellInfo) then
        return "", ""
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return "", "" end
    local cast = "—"
    if type(info.castTime) == "number" then
        cast = info.castTime > 0 and string.format("%g %s", info.castTime / 1000, L["秒"]) or L["瞬发"]
    end
    local range = "—"
    if type(info.maxRange) == "number" and info.maxRange > 0 then
        range = string.format("%g %s", info.maxRange, L["码"])
        if type(info.minRange) == "number" and info.minRange > 0 then
            range = string.format("%g–", info.minRange) .. range
        end
    end
    return cast, range
end

local function RefreshDetailCardLayout()
    if not (detailPane and detailTitle and detailMeta and detailCast and detailBody and detailDivider
            and detailBodyScroll and detailBodyChild) then return end
    local width = math.max(1, detailPane:GetWidth())
    local compact = width <= 820
    local inset, topInset = 12, 8
    local iconSize = compact and 56 or 60
    detailTitle:SetFont(ExwindTools.MAIN_FONT, compact and 18 or 20, "")
    detailIcon:SetSize(iconSize, iconSize)
    detailIcon:ClearAllPoints()
    detailIcon:SetPoint("TOPLEFT", detailPane, "TOPLEFT", inset, -topInset)
    if detailIcon.SetCornerRadius and PixelUtil then
        local iconInset = PixelUtil.GetNearestPixelSize(1, detailPane:GetEffectiveScale(), 1)
        detailIcon:SetCornerRadius(10 - iconInset)
    end
    local iconInset = PixelUtil.GetNearestPixelSize(1, detailPane:GetEffectiveScale(), 1)
    detailIconBorder:SetSize(iconSize + iconInset * 2, iconSize + iconInset * 2)
    detailIconBorder:ClearAllPoints()
    detailIconBorder:SetPoint("TOPLEFT", detailIcon, "TOPLEFT", -iconInset, iconInset)
    EXUI:ClearControlSurface(detailIconBorder)

    local contentX = inset + iconSize + 12
    local outputWidth = 330
    local outputGap = 12
    local headerWidth = math.max(120, width - contentX - inset)
    local bodyWidth = math.max(120, width - contentX - inset - outputWidth - outputGap
        - detailBodyScroll:GetVerticalScrollInset())
    detailTitle:ClearAllPoints()
    detailTitle:SetPoint("TOPLEFT", detailPane, "TOPLEFT", contentX, -topInset - 1)
    detailTitle:SetWidth(math.max(60, math.min(headerWidth,
        math.ceil(detailTitle:GetUnboundedStringWidth() or 0) + 6)))
    detailTitle:SetWordWrap(false)
    detailMeta:Hide()

    local chips = { detailCastChip, detailRangeChip, detailFirstChip, detailCDChip, detailSpellIDChip }
    local chipGap = 6
    local chipX = contentX
    for _, chip in ipairs(chips) do
        if chip then
            local labelWidth = chip.label and math.ceil(chip.label:GetUnboundedStringWidth() or 0) or 0
            local valueWidth = chip.value and math.ceil(chip.value:GetUnboundedStringWidth() or 0) or 0
            local chipWidth = math.max(54, labelWidth + valueWidth + (labelWidth > 0 and 24 or 20))
            chip:SetSize(chipWidth, 26)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", detailPane, "TOPLEFT", chipX, -37)
            chipX = chipX + chipWidth + chipGap
        end
    end

    if detailEnableHost and detailEnableHost:IsShown() then
        detailEnableHost:ClearAllPoints()
        detailEnableHost:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", inset, 6)
        detailEnableHost:SetSize(90, 28)
    end
    if detailOutputHost and detailOutputHost:IsShown() then
        detailOutputHost:ClearAllPoints()
        detailOutputHost:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -inset, 9)
        detailOutputHost:SetSize(outputWidth, 34)
        if LayoutTrashQuickRow and Page._settingsCardSession then
            LayoutTrashQuickRow(Page._settingsCardSession)
        end
    end
    detailBodyScroll:ClearAllPoints()
    detailBodyScroll:SetPoint("TOPLEFT", detailPane, "TOPLEFT", contentX, -71)
    detailBodyScroll:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -(inset + outputWidth + outputGap),
        detailInfo:IsShown() and 31 or 10)
    detailBody:SetWidth(bodyWidth)
    detailBody:SetHeight(0)
    detailBodyChild:SetSize(bodyWidth, math.max(1, detailBodyScroll:GetHeight(),
        math.ceil(detailBody:GetStringHeight())))
    detailBodyScroll:UpdateScrollChildRect()
    detailBodyScroll:SetVerticalScroll(0)
    detailInfo:ClearAllPoints()
    detailInfo:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", contentX, 12)
    detailInfo:SetPoint("RIGHT", detailPane, "RIGHT", -(inset + outputWidth + outputGap), 0)
    detailPane:SetHeight(C.SPELL_DETAIL_HEIGHT)
    detailDivider:Hide()
end

local function SetDetailCardEmpty(message)
    if not detailPane then
        return
    end
    if detailPlaceholder then
        detailPlaceholder:SetText(tostring(message or L["点击左侧技能后，可在此查看法术描述。"]))
        detailPlaceholder:Show()
    end
    if detailIcon then detailIcon:Hide() end
    if detailIconBorder then detailIconBorder:Hide() end
    if detailTitle then detailTitle:SetText("") end
    if detailMeta then detailMeta:SetText("") end
    if detailCast then detailCast:SetText("") end
    if detailBody then detailBody:SetText("") end
    if detailInfo then detailInfo:SetText(""); detailInfo:Hide() end
    for _, chip in ipairs({ detailCastChip, detailRangeChip, detailFirstChip, detailCDChip, detailSpellIDChip }) do
        if chip then chip:Hide() end
    end
    if detailDivider then detailDivider:Hide() end
    if detailEnableHost then detailEnableHost:Hide() end
    if detailOutputHost then detailOutputHost:Hide() end
    detailPane:SetHeight(C.SPELL_DETAIL_HEIGHT)
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
    if n > 5 then n = 5 end
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
            return Engine:TryPlayLabel(safeLabel, { source = "trash_cd_preview" })
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
        local called, ok, handle = pcall(PlaySoundFile, soundPath, "Master")
        return called and ok, nil, called and handle or nil
    end
end

-- The draft keeps its identity while V2 owns controls and layout.
local function BuildSettingsLayout()
    local row = GetSelectedSpellRow()
    local notice = GetAuthorVoiceDisableText(row and GetRuntimeSpellEntry(row))
    if SETTINGS_LAYOUT.version == 2 and settingsAuthorVoiceNotice == notice then return false end
    settingsAuthorVoiceNotice = notice
    local function Field(id, kind, extra)
        local node = { id = id, kind = "control", controlType = kind, path = id }
        for key, value in pairs(extra or {}) do node[key] = value end
        return node
    end
    local function Options(items)
        local result = {}
        for _, item in ipairs(items) do
            result[#result + 1] = { label = item[1], value = item[2] }
        end
        return result
    end
    local function Setting(id, label, toggle, children, extra)
        local node = { id = id, kind = "setting", label = label, toggle = toggle, children = children }
        for key, value in pairs(extra or {}) do node[key] = value end
        return node
    end
    local sources = {}
    for _, item in ipairs(TRIGGER_SOURCE_ITEMS) do sources[#sources + 1] = item[2] end
    local function Sound(prefix, allowedSources)
        return { id = prefix .. "Sound", kind = "component", component = "soundselector", path = prefix,
            optionsRef = "sound." .. prefix,
            opts = { sources = allowedSources or sources,
                labelSource = prefix ~= "targetAlertStart" and "ExBoss.Voice.LabelCatalog.GetDropdownItems" or nil } }
    end
    SETTINGS_LAYOUT = {
        version = 2, layout = "grid",
        columns = { { weight = 1.57 }, { weight = 1 } },
        cards = {
            { id = "text", kind = "card", title = L["文本设置"], row = 1, column = 1, children = {
                    Setting("eventColorRow", L["颜色"], "eventColorEnabled", {
                        Field("eventColorMode", "select", {
                            optionsSource = "ExBoss.Voice.ColorSchemes.BuildDropdownItems", search = true }),
                        Field("eventColor", "color", { visible = "customColor" }),
                    }),
                    Setting("centralRow", L["中央文本"], "centralEnabled", {
                        Field("centralLead", "input", { size = "short" }),
                        { id = "centralLeadUnit", kind = "text", text = L["秒"] },
                        Field("centralText", "input"),
                    }),
                    Setting("countdownRow", L["倒数文本"], "countdownEnabled", { Field("preAlertText", "input") }),
                    Setting("timerRenameRow", L["计时条改名"], "timerBarRenameEnabled", { Field("timerBarRenameText", "input") }),
                } },
            { id = "cast", kind = "card", title = L["施法设置"], row = 1, column = 2, children = {
                    { id = "castOutputRow", kind = "control", controlType = "toggles", label = L["显示"], items = {
                        { label = L["圆环"], path = "ringEnabled" },
                        { label = L["读条"], path = "castProgressBarEnabled" },
                    } },
                    Field("ringCastCheckEnabled", "switch", { label = L["施法检测"],
                        description = L["检测当前读条能否完成，来不及时以红色提示。"] }),
                    Setting("castRenameRow", L["读条改名"], "castProgressBarRenameEnabled", { Field("castProgressBarRenameText", "input") }),
                } },
            { id = "voice", kind = "card", title = L["语音设置"], row = 2, column = 1, children = {
                    Setting("tr1Row", L["施法开始"], "tr1Enabled", { Sound("tr1") },
                        { description = notice, enabled = "voiceAllowed" }),
                    Setting("countdownVoiceRow", L["播放数字"], "tr2Enabled", {
                        Field("tr2CountdownLead", "segment", { options = Options(COUNTDOWN_LEAD_ITEMS) }),
                    }, { enabled = "voiceAllowed" }),
                    Setting("tr2Row", L["播放名称"], "tr2PlayTextEnabled", { Sound("tr2") }, { enabled = "voiceAllowed" }),
                    -- 时间轴直接放卡片里铺满整行；▶ 试听按钮在组件内部右下角（普通页卡片不能直接放按钮）。
                    { id = "voiceTimeline", kind = "component", ref = "voiceTimeline", custom = "EXBoss.VoiceTimeline" },
                } },
            { id = "target", kind = "card", title = L["被点名提示"], row = 2, column = 2, children = {
                    Field("targetAlertStartEnabled", "switch", { label = L["启用"] }),
                    { id = "targetVisualRow", kind = "control", controlType = "toggles", label = L["提示方式"], enabled = "targetOn", items = {
                        { label = L["圆环"], path = "targetAlertRingEnabled" },
                        { label = L["文本"], path = "targetAlertTextEnabledV2" },
                        { label = L["图标"], path = "targetAlertIconEnabled" },
                    } },
                    Setting("stealthRow", L["隐遁提示"], nil, { Field("targetAlertStealthEnabledV2", "switch") },
                        { icon = 132089, enabled = "targetOn" }),
                    Field("targetAlertTankEnabled", "switch", { label = L["坦克也生效"], enabled = "targetOn" }),
                    Setting("targetSoundRow", L["语音"], nil, { Sound("targetAlertStart", { "lsm" }) }, { enabled = "targetOn" }),
                } },
        },
    }
    return true
end

local function FindTrashWidget(key, session)
    session = session or Page._settingsCardSession
    if session then
        local node = session:FindNode(key)
        return node and (node.instance or node.button or node.label or node.frame)
    end
end

local function MountTrashDeclaration(parent, declaration, owner)
    local session, issue = EXUI:MountSettingsDeclarationV2(parent, declaration, owner)
    if not session then error("TrashCD V2: " .. issue.path .. ": " .. issue.message) end
    parent._exV2Session, parent._exV2Owner = session, owner
    return session
end

local function ReleaseTrashDeclaration(parent)
    local session = parent and parent._exV2Session
    if session then session:Release() end
    if parent then parent._exV2Session, parent._exV2Owner = nil, nil end
end

local function ResolveTrashVoicePreviewCaption(mdb, triggerIndex)
    local prefix = "tr" .. tostring(triggerIndex)
    local source = NormalizeTriggerSource(type(mdb) == "table" and mdb[prefix .. "Source"] or nil)
    local value = ""
    if source == "pack" then
        value = tostring(mdb[prefix .. "Label"] or "")
    elseif source == "lsm" then
        value = tostring(mdb[prefix .. "LSM"] or "")
    else
        value = tostring(mdb[prefix .. "Path"] or "")
    end
    return value ~= "" and value or L["未选择"]
end

local function BuildTrashVoicePreviewSequence(mdb)
    mdb = type(mdb) == "table" and mdb or {}
    local playDigits = mdb.tr2Enabled == true
    local playName = mdb.tr2PlayTextEnabled == true
    local playCastStart = mdb.tr1Enabled == true
    local lead = NormalizeCountdownLeadSeconds(mdb.tr2CountdownLead or mdb.countdownLead)
    local nameAt = playName and (playDigits and (lead + 1) or 5) or nil
    local earliest = nameAt or (playDigits and lead or 0)
    local sequence = {}
    for second = earliest, 0, -1 do
        local entry = { seconds = second, kind = "silent", text = L["静默"] }
        if nameAt and second == nameAt then
            entry.kind = "trigger"
            entry.triggerIndex = 2
            entry.text = ResolveTrashVoicePreviewCaption(mdb, 2)
        elseif playDigits and second >= 1 and second <= lead then
            entry.kind = "digit"
            entry.value = second
            entry.text = tostring(second)
        elseif second == 0 and playCastStart then
            entry.kind = "trigger"
            entry.triggerIndex = 1
            entry.text = ResolveTrashVoicePreviewCaption(mdb, 1)
        end
        sequence[#sequence + 1] = entry
    end
    return sequence, earliest
end

local function RefreshTrashVoicePreviewTimeline(sequence)
    local timeline = voicePreviewTimeline
    if not timeline then return end
    sequence = type(sequence) == "table" and sequence or {}
    local sequenceBySecond = {}
    for _, entry in ipairs(sequence) do
        local second = tonumber(entry.seconds)
        if second and second >= 0 and second <= 6 and entry.kind ~= "silent" then
            sequenceBySecond[second] = entry
        end
    end
    for index, node in ipairs(timeline.nodes or {}) do
        local second = 7 - index
        local entry = sequenceBySecond[second]
        node:Show()
        node.time:SetText(tostring(second) .. L["秒"])
        if entry then
            node.value:SetText(entry.text or L["静默"])
            node._previewKind = entry.kind
            if entry.kind == "digit" then
                EXUI:ClearControlSurface(node.valueHost)
                node.value:SetFont(ExwindTools.MAIN_FONT, GM.font.cardTitle, "")
                node.value:SetTextColor(1, 1, 1, 1)
            else
                EXUI:SetControlSurface(node.valueHost, 4, GC.panel, GC.cardBorder)
                node.value:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.previewText, "")
                node.value:SetTextColor(unpack(GC.selectedText))
            end
        else
            node._previewKind = "empty"
            node.value:SetText("")
            node.value:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.previewText, "")
            node.value:SetTextColor(unpack(GC.textDim))
            EXUI:ClearControlSurface(node.valueHost)
        end
    end
    timeline._visibleNodeCount = 7
    if timeline._layout then timeline:_layout() end
end

local function RefreshTrashVoicePreviewDisplay()
    local sequence = BuildTrashVoicePreviewSequence(GetSpellEditorDB())
    RefreshTrashVoicePreviewTimeline(sequence)
end

-- 序列预览播的是一串 C_Timer.After，没有单一声音句柄，用不了 RunSoundPreview；
-- 播放态只能由调用方用 SetSoundPreviewPlaying 告知公共试听按钮。只改外观，不碰播放。
local function SetTrashVoiceSequencePreviewPlaying(playing)
    local button = voicePreviewTimeline and voicePreviewTimeline.playButton
    if button then
        EXUI:SetSoundPreviewPlaying(button, playing)
    end
end

-- 作废在排的序列并立刻收回播放态。切换技能／重新套表面、页面隐藏都经过这里。
local function CancelTrashVoiceSequencePreview()
    voicePreviewGeneration = voicePreviewGeneration + 1
    SetTrashVoiceSequencePreviewPlaying(false)
end

local function StartTrashVoiceSequencePreview()
    CancelTrashVoiceSequencePreview()
    local generation = voicePreviewGeneration
    local db = GetSpellEditorDB()
    local sequence, earliest = BuildTrashVoicePreviewSequence(db)
    local scheduledAny, lastDelay = false, 0
    for _, entry in ipairs(sequence) do
        if entry.kind ~= "silent" then
            local scheduledEntry = entry
            local delay = math.max(0, earliest - scheduledEntry.seconds)
            scheduledAny = true
            if delay > lastDelay then lastDelay = delay end
            C_Timer.After(delay, function()
                if generation ~= voicePreviewGeneration or Page._visible ~= true then return end
                if scheduledEntry.kind == "digit" then
                    local countdown = ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown
                    if countdown and type(countdown.PreviewDigit) == "function" then
                        countdown:PreviewDigit(scheduledEntry.value)
                    end
                elseif scheduledEntry.triggerIndex == 1 then
                    PlayVoicePreview(db.tr1Source, db.tr1Label, db.tr1LSM, db.tr1Path)
                elseif scheduledEntry.triggerIndex == 2 then
                    PlayVoicePreview(db.tr2Source, db.tr2Label, db.tr2LSM, db.tr2Path)
                end
            end)
        end
    end
    if not scheduledAny then
        return
    end
    SetTrashVoiceSequencePreviewPlaying(true)
    -- 序列正常走完：Core 不知道这串计时器何时结束，必须由本页收回播放态。
    -- 本次之后又点了播放／被取消时 generation 已变，这里不再回写。
    C_Timer.After(lastDelay, function()
        if generation ~= voicePreviewGeneration then
            return
        end
        SetTrashVoiceSequencePreviewPlaying(false)
    end)
end

local function SetTrashPlayButtonVisual(button)
    if button then EXUI:ApplySoundPreviewAppearance(button) end
end

local function CreateTrashSettingsOwner()
    local db = GetSpellEditorDB()
    local owner = { binding = { moduleKey = SPELL_SETTINGS_MODULE_KEY, config = db },
        controls = {}, components = {}, predicates = {}, texts = {} }
    local function VoiceAllowed()
        local row = GetSelectedSpellRow()
        local cfg = row and GetRuntimeSpellEntry(row)
        return not (type(cfg) == "table" and cfg.authorVoiceDisabled == true)
    end
    owner.predicates.customColor = function()
        return db.eventColorEnabled == true and NormalizeEventColorMode(db.eventColorMode) == "__custom"
    end
    owner.predicates.targetOn = function() return db.targetAlertStartEnabled == true end
    owner.predicates.voiceAllowed = VoiceAllowed
    owner.options = {}
    for index = 1, 2 do
        local prefix = "tr" .. index
        owner.options["sound." .. prefix] = { onTest = function(_, button)
            EXUI:RunSoundPreview(button, function()
                return PlayVoicePreview(db[prefix .. "Source"], db[prefix .. "Label"],
                    db[prefix .. "LSM"], db[prefix .. "Path"])
            end)
        end }
    end
    owner.options["sound.targetAlertStart"] = { onTest = function(_, button)
        EXUI:RunSoundPreview(button, function()
            return PlayVoicePreview("lsm", "", db.targetAlertStartLSM, "")
        end)
    end }
    owner.components.voiceTimeline = {
        mount = function(host, context)
            local timeline = voicePreviewSurface or CreateFrame("Frame", nil, host)
            timeline:SetParent(host)
            timeline:SetSize(GM.settings.soundSelectorWidth, C.VOICE_TIMELINE_HEIGHT)
            timeline:SetFrameLevel((host:GetFrameLevel() or 1) + 1)
            EXUI:SetControlSurface(timeline, 5, GC.panel, GC.cardBorder)
            timeline:SetClipsChildren(true)
            if not voicePreviewSurface then
                timeline.axis = EXUI:CreateVisualTexture(timeline, EXBASEFRAME)
                timeline.axis:SetColorTexture(unpack(GC.cardBorder))
                timeline.axis:SetHeight(PixelUtil.GetNearestPixelSize(1, timeline:GetEffectiveScale(), 1))
                timeline.nodes = {}
                for index = 1, 7 do
                    local node = CreateFrame("Frame", nil, timeline)
                    node.time = EXUI:CreateVisualFontString(node, EXFONTFRAME, "GameFontDisableSmall")
                    node.time:SetPoint("TOPLEFT", node, "TOPLEFT", 0, 0)
                    node.time:SetPoint("TOPRIGHT", node, "TOPRIGHT", 0, 0)
                    node.time:SetJustifyH("CENTER")
                    node.time:SetWordWrap(false)
                    node.time:SetFont(ExwindTools.MAIN_FONT, GM.font.hint, "")
                    node.valueHost = CreateFrame("Frame", nil, node, "BackdropTemplate")
                    node.valueHost:SetPoint("TOPLEFT", node.time, "BOTTOMLEFT", 0, -5)
                    node.valueHost:SetHeight(26)
                    node.value = EXUI:CreateVisualFontString(node.valueHost, EXFONTFRAME, "GameFontHighlightSmall")
                    node.value:SetPoint("TOPLEFT", node.valueHost, "TOPLEFT", 5, -5)
                    node.value:SetPoint("TOPRIGHT", node.valueHost, "TOPRIGHT", -5, -5)
                    node.value:SetJustifyH("CENTER")
                    node.value:SetWordWrap(true)
                    node.value:SetNonSpaceWrap(true)
                    node.value:SetMaxLines(2)
                    node.valueHost:EnableMouse(true)
                    node.valueHost:SetScript("OnEnter", function(self)
                        local text = node.value:GetText()
                        if not GameTooltip or not text or text == "" then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(text, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    node.valueHost:SetScript("OnLeave", function()
                        if GameTooltip then GameTooltip:Hide() end
                    end)
                    node.tick = EXUI:CreateVisualTexture(timeline, EXBASEFRAME)
                    node.tick:SetColorTexture(unpack(GC.cardBorder))
                    node.tick:SetSize(PixelUtil.GetNearestPixelSize(1, timeline:GetEffectiveScale(), 1), 6)
                    timeline.nodes[index] = node
                end
                timeline.playButton = EXUI:CreateButton(timeline, 26, 26, "", function()
                    StartTrashVoiceSequencePreview()
                end, { variant = "secondary", compact = true })
                timeline.playButton:SetPoint("BOTTOMRIGHT", timeline, "BOTTOMRIGHT", -6, 6)
                voicePreviewSurface = timeline
            end
            timeline._layout = function(self)
                if self._layoutBusy then return end
                self._layoutBusy = true
                local count = 7
                local width = math.max(1, self:GetWidth() or 1)
                -- 右侧 38 留给右下角的试听按钮。
                local axisWidth = math.max(1, width - 6 - 38)
                local slotWidth = axisWidth / count
                local occupied = {}
                for index, node in ipairs(self.nodes) do
                    node:ClearAllPoints()
                    node:SetPoint("TOPLEFT", self, "TOPLEFT", 6 + (index - 1) * slotWidth, 0)
                    node:SetSize(slotWidth, 1)
                    if node._previewKind == "trigger" or node._previewKind == "digit" then
                        occupied[#occupied + 1] = {
                            node = node,
                            index = index,
                            center = 6 + (index - 0.5) * slotWidth,
                        }
                    end
                end
                local placements, rowHeight = {}, 40
                for position, item in ipairs(occupied) do
                    local node = item.node
                    local previous = occupied[position - 1]
                    local following = occupied[position + 1]
                    local leftBound = 6
                    local rightBound = width - 6
                    if previous then
                        if previous.node._previewKind == "digit" then
                            leftBound = previous.center + 21
                        else
                            leftBound = (previous.center + item.center) / 2 + 3
                        end
                    end
                    if following then
                        if following.node._previewKind == "digit" then
                            rightBound = following.center - 21
                        else
                            rightBound = (item.center + following.center) / 2 - 3
                        end
                    end
                    local availableWidth = math.max(24, rightBound - leftBound)
                    local desiredWidth
                    if node._previewKind == "digit" then
                        desiredWidth = math.min(36, availableWidth)
                    else
                        desiredWidth = math.min(availableWidth,
                            math.max(64, math.ceil(node.value:GetUnboundedStringWidth() or 0) + 18))
                    end
                    local left = math.max(leftBound,
                        math.min(rightBound - desiredWidth, item.center - desiredWidth / 2))
                    node.valueHost:ClearAllPoints()
                    node.value:SetWidth(math.max(1, desiredWidth - 10))
                    placements[#placements + 1] = {
                        node = node,
                        left = left,
                        width = desiredWidth,
                    }
                end
                for _, node in ipairs(self.nodes) do
                    node.valueHost:Hide()
                end
                for _, placement in ipairs(placements) do
                    local node = placement.node
                    node.valueHost:ClearAllPoints()
                    node.valueHost:SetPoint("TOPLEFT", self, "TOPLEFT", placement.left, -6)
                    node.valueHost:SetSize(placement.width, rowHeight)
                    node.value:ClearAllPoints()
                    node.value:SetPoint("TOPLEFT", node.valueHost, "TOPLEFT", 5, -5)
                    node.value:SetPoint("TOPRIGHT", node.valueHost, "TOPRIGHT", -5, -5)
                    node.value:SetHeight(rowHeight - 10)
                    node.value:SetJustifyH("CENTER")
                    node.value:SetJustifyV("MIDDLE")
                    node.valueHost:Show()
                end
                local axisTop = rowHeight + 14
                self.axis:ClearAllPoints()
                self.axis:SetPoint("TOPLEFT", self, "TOPLEFT", 6 + slotWidth / 2, -axisTop)
                self.axis:SetPoint("TOPRIGHT", self, "TOPRIGHT",
                    -(38 + slotWidth / 2), -axisTop)
                for index, node in ipairs(self.nodes) do
                    local centerX = 6 + (index - 0.5) * slotWidth
                    node.tick:ClearAllPoints()
                    node.tick:SetPoint("TOP", self, "TOPLEFT", centerX, -axisTop + 2)
                    node.time:ClearAllPoints()
                    node.time:SetPoint("TOP", self, "TOPLEFT", centerX, -(axisTop + 7))
                    node.time:SetWidth(slotWidth)
                    node.time:SetHeight(16)
                end
                local timelineHeight = C.VOICE_TIMELINE_HEIGHT
                if self:GetHeight() ~= timelineHeight then self:SetHeight(timelineHeight) end
                self._layoutBusy = nil
                context:ReportHeight(timelineHeight)
            end
            for _, node in ipairs(timeline.nodes) do
                node:SetFrameLevel(timeline:GetFrameLevel() + 1)
                node.valueHost:SetFrameLevel(timeline:GetFrameLevel() + 2)
            end
            timeline.playButton:SetFrameLevel(timeline:GetFrameLevel() + 3)
            timeline:SetScript("OnSizeChanged", function(self) self:_layout() end)
            voicePreviewTimeline = timeline
            RefreshTrashVoicePreviewDisplay()
            return timeline
        end,
        update = function() RefreshTrashVoicePreviewDisplay() end,
        measure = function(timeline, context, width)
            timeline:SetWidth(width)
            timeline:_layout()
            return C.VOICE_TIMELINE_HEIGHT
        end,
        layout = function(timeline, context, width, height)
            timeline:ClearAllPoints()
            timeline:SetPoint("TOPLEFT")
            timeline:SetSize(width, height)
            -- 背景按布局给的宽高重画，挂载时画的是初始 320 宽。
            EXUI:SetControlSurface(timeline, 5, GC.panel, GC.cardBorder)
            timeline:_layout()
        end,
        setEnabled = function() end,
        setVisible = function(timeline, context, visible) timeline:SetShown(visible) end,
        release = function(timeline)
            for _, node in ipairs(timeline.nodes) do
                if GameTooltip and GameTooltip:GetOwner() == node.valueHost then GameTooltip:Hide() end
            end
            if voicePreviewTimeline == timeline then voicePreviewTimeline = nil end
            timeline:SetScript("OnSizeChanged", nil)
            EXUI:SetSoundPreviewPlaying(timeline.playButton, false)
            timeline._layout = nil
            timeline:Hide()
            timeline:SetParent(nil)
        end,
    }
    owner.onHeightChanged = function(height)
        settingsScrollChild:SetHeight(math.max(1, height))
        settingsScrollFrame:UpdateScrollChildRect()
    end
    return owner
end

-- 技能头持有常驻控件，切换技能时只换绑当前草稿。
function Page._BindSpellSummarySwitch(db)
    local switch = Page._detailEnableSwitch
    if not switch then
        switch = EXUI:CreateCheckbox(detailEnableHost, L["启用"], false, function(checked)
            local draft = Page._detailEnableSwitch._exDraft
            if type(draft) ~= "table" then return end
            EXUI:CreateSettingsV2Binding(SPELL_SETTINGS_MODULE_KEY, draft, "enabled"):Write(checked == true, "commit")
            if Page._settingsCardSession then Page._settingsCardSession:Refresh() end
        end)
        switch:SetAllPoints(detailEnableHost)
        EXUI:PrepareSettingsListControl(switch, { presentation = "card", cardCheckSize = 14, cardTextSize = 12 })
        EXUI:ApplyCheckboxOnOffVisual(switch)
        Page._detailEnableSwitch = switch
    end
    switch._exDraft = db
    switch:SetChecked(db.enabled == true)
    EXUI:ApplyControlAppearance(switch)
    Page._detailOutputChecks = Page._detailOutputChecks or {}
    for _, field in ipairs({
        { "showBunBar", L["竖条"], 1 }, { "showTimerBar", L["计时条"], 1.2 }, { "showNameplate", L["纪事条姓名板"], 1.8 },
    }) do
        local key = field[1]
        local widget = Page._detailOutputChecks[key]
        if not widget then
            widget = EXUI:CreateCheckbox(detailOutputHost, field[2], false, function(checked)
                local draft = Page._detailOutputChecks[key]._exDraft
                if type(draft) ~= "table" then return end
                EXUI:CreateSettingsV2Binding(SPELL_SETTINGS_MODULE_KEY, draft, key):Write(checked == true, "commit")
                if Page._settingsCardSession then Page._settingsCardSession:Refresh() end
            end)
            EXUI:PrepareSettingsListControl(widget, { presentation = "card" })
            widget._exWeight = field[3]
            Page._detailOutputChecks[key] = widget
        end
        widget._exDraft = db
        widget:SetChecked(db[key] == true)
        EXUI:ApplyControlAppearance(widget)
    end
    LayoutTrashQuickRow()
end

LayoutTrashQuickRow = function()
    local checks = Page._detailOutputChecks
    if not checks then return end
    local keys = { "showBunBar", "showTimerBar", "showNameplate" }
    local totalWeight, precedingWeight = 0, 0
    for _, key in ipairs(keys) do totalWeight = totalWeight + checks[key]._exWeight end
    local availableWidth = math.max(1, detailOutputHost:GetWidth() - 16 - 4 * (#keys - 1))
    for index, key in ipairs(keys) do
        local widget = checks[key]
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", detailOutputHost, "TOPLEFT",
            8 + availableWidth * precedingWeight / totalWeight + (index - 1) * 4, -2)
        widget:SetSize(availableWidth * widget._exWeight / totalWeight, 30)
        precedingWeight = precedingWeight + widget._exWeight
    end
end
local function ReleaseTrashSettingsCardSession()
    ReleaseTrashDeclaration(settingsScrollChild)
    Page._settingsCardSession = nil
    if Page._detailEnableSwitch then Page._detailEnableSwitch._exDraft = nil end
    for _, widget in pairs(Page._detailOutputChecks or {}) do widget._exDraft = nil end
    voicePreviewTimeline = nil
    if detailOutputHost then detailOutputHost:Hide() end
end

local function RefreshSettingsDynamicWidgets()
    if not Page._settingsCardSession then return end
    settingsScrollFrame:ClearAllPoints()
    settingsScrollFrame:SetPoint("TOPLEFT", settingsPane, "TOPLEFT", 0, 0)
    settingsScrollFrame:SetPoint("BOTTOMRIGHT", settingsPane, "BOTTOMRIGHT", -18, 0)
    Page._settingsCardSession:Refresh()
    SetTrashPlayButtonVisual(voicePreviewTimeline and voicePreviewTimeline.playButton)
    RefreshTrashVoicePreviewDisplay()
    Page._BindSpellSummarySwitch(GetSpellEditorDB())
    LayoutTrashQuickRow()
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
            EXUI:SetControlSurface(btn, 10, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
            -- 选中走 Core 公共选中外观：图标框底色沿用各自原底（未选中 GC.input／悬停时沿用悬停底）。
            EXUI:PaintSelectCell(btn.iconFrame, active, 10)
            if active then
                EXUI:SetControlSurface(btn.iconFrame, 10, hovered and GC.secondaryHoverFill or GC.input, GC.transparent)
                btn.icon:SetDesaturated(false)
                btn.text:SetTextColor(unpack(GC.text))
            elseif hovered then
                EXUI:SetControlSurface(btn.iconFrame, 10, GC.secondaryHoverFill, GC.inputHoverBorder)
                btn.icon:SetDesaturated(false)
                btn.text:SetTextColor(unpack(GC.text))
            else
                EXUI:SetControlSurface(btn.iconFrame, 10, GC.input, GC.panelBorder)
                btn.icon:SetDesaturated(true)
                btn.text:SetTextColor(unpack(GC.textDim))
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
            if row.navDivider then row.navDivider:Hide() end
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
    EXUI:SetControlSurface(btn, 10, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })

    btn.iconFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    EXUI:SetControlSurface(btn.iconFrame, 10, GC.input, GC.panelBorder)
    btn.iconFrame:SetSize(70, 70)
    btn.iconFrame:SetPoint("TOP", 0, -1)

    btn.icon = EXUI:CreateRoundedImage(btn.iconFrame, 9, true)
    local function LayoutMapImage()
        local inset = PixelUtil.GetNearestPixelSize(1, btn.iconFrame:GetEffectiveScale(), 1)
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("TOPLEFT", inset, -inset)
        btn.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        btn.icon:SetCornerRadius(10 - inset)
    end
    btn.iconFrame:HookScript("OnSizeChanged", LayoutMapImage)
    btn.iconFrame:RegisterEvent("UI_SCALE_CHANGED")
    btn.iconFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    btn.iconFrame:SetScript("OnEvent", LayoutMapImage)
    LayoutMapImage()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.text = EXUI:CreateVisualFontString(btn, EXFONTFRAME, "GameFontNormalSmall")
    btn.text:SetPoint("TOP", btn.iconFrame, "BOTTOM", 0, -5)
    btn.text:SetWidth(84)
    btn.text:SetJustifyH("CENTER")
    btn.text:SetWordWrap(true)
    btn.text:SetMaxLines(0)
    btn.text:SetFont(ExwindTools.MAIN_FONT, GM.font.text, "")

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
    EXUI:ClearControlSurface(row)


    row.navDivider = EXUI:CreateSettingsSeparator(row, 1)
    row.navDivider:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 9, -1)
    row.navDivider:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -9, -1)
    row.navDivider:Hide()

    local check = EXUI:CreateCheckbox(row, "", false, nil)
    check:SetSize(26, 26)
    check:SetPoint("LEFT", 0, 0)
    check:Hide()
    row.check = check

    local icon = EXUI:CreateVisualTexture(row, EXBASEFRAME)
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.iconMask = row:CreateMaskTexture()
    row.iconMask:SetTexture("Interface\\Common\\common-iconmask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    row.iconMask:SetAllPoints(icon)
    icon:AddMaskTexture(row.iconMask)
    row.icon = icon

    local alertIcon = EXUI:CreateVisualTexture(row, EXBORDERFRAME)
    alertIcon:SetSize(16, 16)
    alertIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    alertIcon:Hide()
    row.alertIcon = alertIcon

    local textBlock = CreateFrame("Frame", nil, row)
    textBlock:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    textBlock:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    textBlock:SetPoint("CENTER", row, "CENTER", 0, 0)
    textBlock:SetHeight(34)
    row.textBlock = textBlock

    local label = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    label:SetSpacing(0)
    label:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.spellListTitle, "")
    row.label = label

    local atlasHolder = CreateFrame("Frame", nil, row)
    atlasHolder:SetPoint("RIGHT", textBlock, "RIGHT", 0, 0)
    atlasHolder:SetSize(18, 18)
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

    local npcCard = CreateFrame("Frame", nil, textBlock, "BackdropTemplate")
    npcCard:SetPoint("BOTTOMRIGHT", textBlock, "BOTTOMRIGHT", 0, 0)
    npcCard:SetWidth(96)
    npcCard:SetHeight(15)
    EXUI:SetControlSurface(npcCard, 4, GC.input, GC.panelBorder)
    row.npcCard = npcCard

    local meta = EXUI:CreateVisualFontString(npcCard, EXFONTFRAME, "GameFontDisableSmall")
    meta:SetPoint("LEFT", npcCard, "LEFT", 6, 0)
    meta:SetPoint("RIGHT", npcCard, "RIGHT", -6, 0)
    meta:SetJustifyH("RIGHT")
    meta:SetJustifyV("MIDDLE")
    meta:SetWordWrap(false)
    meta:SetMaxLines(1)
    -- 用户 2026-10-05 第五批第 67 项：技能行右侧的怪物名称字号 +1 号
    -- （GM.font.hint 11 → GM.font.small 12），只改这一个字号。
    meta:SetFont(ExwindTools.MAIN_FONT, GM.font.small, "")
    meta:SetTextColor(unpack(GC.textDim))
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
        SetDetailCardEmpty(L["点击左侧技能后，可在此查看法术描述。"])
        return
    end

    local cfg = GetRuntimeSpellEntry(row)
    local cachedName, icon = GetRowSpellNameAndIcon(row)
    local desc = GetRowSpellDescription(row)
    local summaryCast, summaryRange = GetSpellSummaryFacts(row.spellID)
    local displayName = tostring(row.spellName or "")
    if cachedName and cachedName ~= "" then
        displayName = cachedName
    end
    local cdText = FormatCDList(row.cd)
    local disabled = type(cfg) == "table" and cfg.enabled == false

    if detailPlaceholder then detailPlaceholder:Hide() end
    if detailEnableHost then detailEnableHost:Show() end
    if detailOutputHost then detailOutputHost:Show() end
    detailIcon:Show()
    if detailIconBorder then detailIconBorder:Show() end
    detailIcon:SetTexture(icon or 134400)
    detailIcon:SetDesaturated(disabled)
    detailIcon:SetAlpha(disabled and 0.65 or 1)
    detailTitle:SetText(displayName)
    detailMeta:SetText("")
    detailMeta:Hide()
    detailCast:SetText((summaryCast ~= "" and tostring(summaryCast)) or L["暂无施法信息"])
    if detailRangeValue then detailRangeValue:SetText((summaryRange ~= "" and tostring(summaryRange)) or "—") end
    if detailFirstValue then detailFirstValue:SetText(tostring(row.first or "-")) end
    if detailCDValue then detailCDValue:SetText(cdText) end
    if detailSpellIDValue then detailSpellIDValue:SetText(tostring(row.spellID or "-")) end
    for _, chip in ipairs({ detailCastChip, detailRangeChip, detailFirstChip, detailCDChip, detailSpellIDChip }) do
        if chip then chip:Show() end
    end
    detailBody:SetText((desc ~= "" and tostring(desc)) or L["暂无描述。"])
    if detailBodyScroll then detailBodyScroll:SetVerticalScroll(0) end
    -- 用户要求删除 Off 状态右侧“技能已停用，配置仍保留”说明；停用状态由 On/Off 标签表达。
    detailInfo:SetText("")
    detailInfo:Hide()
    if detailDivider then detailDivider:Hide() end
    RefreshDetailCardLayout()
end

local function RelayoutDungeonNavigation()
    if not (mapScrollChild and mapPane) then return end
    local cellWidth = math.max(1, (mapScrollChild:GetWidth() - 21) / 4)
    local iconSize = math.max(1, math.min(90, cellWidth - 2))
    local heights = {}
    for i, tab in ipairs(activeDungeonButtons) do
        tab:SetWidth(cellWidth)
        tab.iconFrame:SetSize(iconSize, iconSize)
        tab.text:SetWidth(math.max(1, cellWidth - 4))
        local row = math.floor((i - 1) / 4) + 1
        heights[row] = math.max(heights[row] or 0, iconSize + 6 + math.ceil(tab.text:GetStringHeight() or 0))
    end
    local y, visibleHeight = 0, 0
    for row = 1, math.max(1, math.ceil(#activeDungeonButtons / 4)) do
        local height = heights[row] or (iconSize + 24)
        for i = (row - 1) * 4 + 1, math.min(row * 4, #activeDungeonButtons) do
            local tab = activeDungeonButtons[i]
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", ((i - 1) % 4) * (cellWidth + 7), -y)
            tab:SetHeight(height)
        end
        if row <= 2 then visibleHeight = y + height end
        y = y + height + 12
    end
    mapScrollChild:SetHeight(math.max(1, y - 12 + 4))
    mapPane:SetHeight(visibleHeight + 4)
end

-- [业务排序边界] 地图按钮顺序来自 GetDungeonRows；迁移只能改变选择卡几何/皮肤，不能重排或复制数据。
local function BuildDungeonButtons()
    ReleaseDungeonButtons()
    if not mapScrollChild then
        return
    end

    local rows = GetDungeonRows()
    local perRow = 4
    local gapX = 7
    local gapY = 12
    local leftPad = 0
    local topPad = 0
    local availableWidth = (mapScrollChild:GetWidth() or 208) - (leftPad * 2)
    availableWidth = math.max(1, availableWidth)
    local gridWidth = math.max(1, availableWidth - ((perRow - 1) * gapX))
    local columnUnit = gridWidth / perRow
    local cellHeight = math.min(90, columnUnit - 2) + 24
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
        local iconSize = math.min(90, math.max(1, cellWidth - 2))
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
    local visibleRows = math.min(2, math.max(1, math.ceil(#rows / perRow)))
    RelayoutDungeonNavigation()

    RefreshDungeonButtonVisuals()
end

-- [业务排序边界] 法术列表维持解析后的 map/NPC/spell 顺序与当前筛选；紧凑行可换外观，但不能重排、改选择身份或每次重建整页。
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
        local y = -2 - gridRow * (C.SPELL_CARD.height + C.SPELL_CARD.gapY)
        row:SetSize(cardW, C.SPELL_CARD.height)
        row:SetPoint("TOPLEFT", 0 + x, y)
        row.npcID = rowData.npcID
        row.spellID = rowData.spellID
        row.icon:SetTexture(GetRowSpellIcon(rowData))
        row._enabled = cfg.enabled == true
        row.check:SetChecked(cfg.enabled == true)
        row.check:Hide()
        row.label:SetText(tostring(rowData.spellName or ""))
        local borderR, borderG, borderB = ResolveSpellEntryBorderColor(cfg)
        if borderR == nil or borderG == nil or borderB == nil then
            borderR, borderG, borderB = 0.38, 0.38, 0.38
        end
        row._borderR = borderR
        row._borderG = borderG
        row._borderB = borderB
        row.icon:ClearAllPoints()
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.spellListTitle, "")
        row.label:SetHeight(22)
        row.testAtlasHolder:ClearAllPoints()
        row.testAtlasHolder:SetPoint("RIGHT", row.textBlock, "RIGHT", 0, 0)
        row.alertIcon:ClearAllPoints()
        local eventTypeAtlas = ResolveEventTypeIcon(rowData.eventType)
        if eventTypeAtlas and row.alertIcon and row.alertIcon.SetAtlas then
            row.alertIcon:SetAtlas(eventTypeAtlas, false)
            row.alertIcon:SetPoint("LEFT", row.textBlock, "LEFT", 0, 0)
            row.alertIcon:Show()
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.alertIcon, "RIGHT", 3, 0)
        else
            if row.alertIcon then
                row.alertIcon:Hide()
            end
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.textBlock, "LEFT", 0, 0)
        end
        row.label:SetPoint("RIGHT", row.testAtlasHolder, "LEFT", -6, 0)
        if TEST_THREAT_ATLAS_SPELLS[tonumber(rowData.spellID)] then
            row.testAtlas:SetAtlas(TEST_THREAT_ATLAS_NAME, false)
            row.testAtlasHolder:Show()
        else
            row.testAtlasHolder:Hide()
        end
        row.meta:SetText(tostring(rowData.mobName or ""))
        row.npcCard:SetWidth(math.min(math.max(72,
            math.ceil(row.meta:GetUnboundedStringWidth() or 0) + 12),
            math.max(72, row.textBlock:GetWidth() or 96)))
        row.navDivider:SetShown(index < #orderedRows)
        row._selected = (rowData.npcID == selectedNPCID and rowData.spellID == selectedSpellID)
        row._hovered = false
        row._applyVisual = function(self)
            -- 悬停抬底；选中走 Core 公共选中外观（底色不随选中改变）。
            if self._hovered then
                EXUI:SetControlSurface(self, 4, GC.menuHover, { 0, 0, 0, 0 })
            else
                EXUI:ClearControlSurface(self)
            end
            EXUI:PaintSelectRow(self, self._selected, 4)
            if self._enabled == true then
                self.icon:SetVertexColor(1, 1, 1)
                self.label:SetTextColor(unpack(GC.text))
                self.meta:SetTextColor(unpack(GC.textDim))
            else
                self.icon:SetVertexColor(0.55, 0.55, 0.55)
                self.label:SetTextColor(unpack(GC.textDisabled))
                self.meta:SetTextColor(unpack(GC.textPlaceholder))
            end
        end

        row.check.checkbox:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
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
        spellScrollChild:SetHeight(math.max(1, totalH))
        Page:RelayoutPrototype()
        if not selectedNPCID and not selectedSpellID and orderedRows[1] then
            selectedNPCID = orderedRows[1].npcID
            selectedSpellID = orderedRows[1].spellID
        end
        PrimeSpellCache(orderedRows)
        RefreshSpellRowVisuals()
        Page:RefreshSelectedSpell()
    end

    local function BuildAsync()
        local totalW = (spellScrollChild:GetWidth() or 360)
        totalW = math.max(1, totalW)
        C.SPELL_CARD.cols = 1
        local usableW = math.max(1, totalW - 2)
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

    EXUI:StartFrameTask("EXBoss_TrashCD_SpellList", FRAME_TASK_BUDGET_MS, BuildAsync)
end

local function PrepareTrashSettingsSelection()
    CancelTrashVoiceSequencePreview()
    for _, session in pairs({ Page._settingsCardSession }) do
        if session.alive then
            session:ForEachNode(function(node)
                local widget = node.instance
                if widget then
                    if widget.ClearFocus then widget:ClearFocus() end
                    if widget.CloseMenu then widget:CloseMenu() end
                end
            end)
        end
    end
    -- A color picker callback must retire before the selected draft is reloaded.
    if ColorPickerFrame and ColorPickerFrame:IsShown() then ReleaseTrashSettingsCardSession() end
end

local function RefreshSelectedSpellSync()
    local suspended = _suspendSpellSettingPersist
    _suspendSpellSettingPersist = true
    PrepareTrashSettingsSelection()
    LoadSelectedSpellToEditor()
    UpdateDetailCard()
    Page:RenderSettingsV2(true)
    _suspendSpellSettingPersist = suspended
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
        -- 加载和回填之间不让出执行权，避免旧控件写入新选择的草稿。
        RefreshSelectedSpellSync()
    end

    EXUI:StartFrameTask("EXBoss_TrashCD_SelectedSpell", FRAME_TASK_BUDGET_MS, RunAsync)
end

-- Re-read the same draft into live V2 controls; selection identity stays in Store.
function Page:RenderSettingsV2(resetScroll)
    if not (settingsScrollChild and settingsPane and settingsPane:IsShown()) then return end
    if BuildSettingsLayout() then
        ReleaseTrashDeclaration(settingsScrollChild)
        Page._settingsCardSession = nil
    end
    local db = GetSpellEditorDB()
    settingsScrollChild:SetWidth(math.max(1, settingsScrollFrame:GetWidth() - 4))
    if resetScroll then settingsScrollFrame:SetVerticalScroll(0) end
    RegisterSpellSettingsAsActive(SPELL_SETTINGS_MODULE_KEY)
    local suspended = _suspendSpellSettingPersist
    _suspendSpellSettingPersist = true
    if not Page._settingsCardSession then
        Page._settingsCardSession = MountTrashDeclaration(settingsScrollChild, SETTINGS_LAYOUT, CreateTrashSettingsOwner())
    end
    -- 已挂载的会话由下面的 RefreshSettingsDynamicWidgets 统一 Refresh 一次。
    if detailOutputHost and GetSelectedSpellRow() then
        detailOutputHost:Show()
        RefreshDetailCardLayout()
    end
    RefreshSettingsDynamicWidgets()
    _suspendSpellSettingPersist = suspended
end

-- [混合函数边界] EnsureUI 内只可迁移三 pane、详情卡、Scroll/V2 的外观与 SetPoint/SetSize；池、OnClick、异步 Spell 数据、预览与回调禁止修改。
local function EnsureUI(parent)
    if root then
        return
    end

    root = CreateFrame("Frame", nil, parent)
    root:SetAllPoints(parent)
    root:SetScript("OnSizeChanged", function(self)
        if self._prototypeReflowPending then return end
        self._prototypeReflowPending = true
        C_Timer.After(0, function()
            self._prototypeReflowPending = false
            if Page._visible then Page:RelayoutPrototype() end
        end)
    end)

    local leftW = 248
    local topLeftH = 172
    local topRightH = C.SPELL_DETAIL_HEIGHT
    local gap = 14

    -- Boss 页左上没有副本选择的外层 Backdrop；这里只保留不可见定位容器，滚动框自身
    -- 即为唯一可见边界，消除小怪页多出来的一层嵌套框。
    mapPane = CreateFrame("Frame", nil, root)
    mapPane:SetPoint("TOPLEFT", 8, -8)
    mapPane:SetSize(leftW, topLeftH)
    mapPane:SetClipsChildren(true)

    -- 左栏下半部与 Boss 页一致：仅作布局宿主，不再套一层可见 Backdrop。
    -- 法术行默认无外框，只在悬停或选中时显示背景状态。
    spellPane = CreateFrame("Frame", nil, root)
    spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", 0, -gap)
    spellPane:SetPoint("BOTTOMLEFT", 8, 8)
    spellPane:SetWidth(leftW)
    spellPane:SetClipsChildren(true)

    spellTitle = EXUI:CreateVisualFontString(spellPane, EXFONTFRAME, "GameFontNormal")
    spellTitle:SetPoint("TOPLEFT", 0, 0)
    spellTitle:SetFont(ExwindTools.MAIN_FONT, GM.font.text, "")
    spellTitle:SetTextColor(unpack(GC.textDim))
    spellTitle:SetText(L["技能列表"])
    spellTitle:Hide()

    detailPane = CreateSectionBackdrop(root)
    detailPane:SetBackdropColor(0, 0, 0, 0)
    detailPane:SetBackdropBorderColor(0, 0, 0, 0)
    EXUI:SetControlSurface(detailPane, 10, GC.card, GC.panelBorder)
    detailPane:SetPoint("TOPLEFT", mapPane, "TOPRIGHT", gap, 0)
    detailPane:SetPoint("TOPRIGHT", -8, -8)
    detailPane:SetHeight(topRightH)
    detailPane:SetClipsChildren(true)
    detailPane._exDetailLayoutWidth = 0
    detailPane._exDetailLayoutPending = false
    detailPane:SetScript("OnSizeChanged", function(self, width)
        local nextWidth = math.floor((tonumber(width) or 0) + 0.5)
        if nextWidth <= 0 or nextWidth == self._exDetailLayoutWidth then return end
        self._exDetailLayoutWidth = nextWidth
        if self._exDetailLayoutPending then return end
        self._exDetailLayoutPending = true
        C_Timer.After(0, function()
            self._exDetailLayoutPending = false
            if self:IsShown() then
                RefreshDetailCardLayout()
            end
        end)
    end)

    detailSurface = CreateFrame("Frame", nil, detailPane)
    detailSurface:SetAllPoints(detailPane)

    settingsPane = CreateSectionBackdrop(root)
    settingsPane:SetBackdropColor(0, 0, 0, 0)
    settingsPane:SetBackdropBorderColor(0, 0, 0, 0)
    settingsPane:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -8)
    settingsPane:SetPoint("BOTTOMRIGHT", -8, 8)

    -- 副本选择固定两排八项，不建立滚动视口或滚动条。
    mapScrollFrame = CreateFrame("Frame", nil, mapPane)
    mapScrollFrame:SetAllPoints(mapPane)
    mapScrollFrame:SetClipsChildren(true)

    mapScrollChild = CreateFrame("Frame", nil, mapScrollFrame)
    mapScrollChild:SetPoint("TOPLEFT", mapScrollFrame, "TOPLEFT")
    mapScrollChild:SetSize(208, 1)

    spellScrollFrame = CreateFrame("ScrollFrame", nil, spellPane, "ScrollFrameTemplate")
    spellScrollFrame:SetPoint("TOPLEFT", spellPane, "TOPLEFT", 4, 0)
    spellScrollFrame:SetPoint("BOTTOMRIGHT", spellPane, "BOTTOMRIGHT", -4, 0)
    spellScrollChild = CreateFrame("Frame", nil, spellScrollFrame)
    spellScrollChild:SetWidth(leftW - 30)
    spellScrollChild:SetHeight(300)
    spellScrollFrame:SetScrollChild(spellScrollChild)

    detailPlaceholder = EXUI:CreateVisualFontString(detailSurface, EXFONTFRAME, "GameFontDisableSmall")
    detailPlaceholder:SetPoint("CENTER", 0, 0)
    detailPlaceholder:SetTextColor(unpack(GC.textPlaceholder))
    detailPlaceholder:SetText(L["点击左侧技能后，可在此查看法术描述。"])

    detailEnableHost = CreateFrame("Frame", nil, detailSurface)
    detailEnableHost:SetSize(90, 28)
    detailEnableHost:SetClipsChildren(true)
    detailEnableHost:SetPoint("TOPRIGHT", detailPane, "TOPRIGHT", -14, -9)
    detailEnableHost:Hide()

    detailOutputHost = CreateFrame("Frame", nil, detailSurface, "BackdropTemplate")
    detailOutputHost:SetSize(330, 34)
    detailOutputHost:SetClipsChildren(true)
    detailOutputHost:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -12, 9)
    EXUI:SetControlSurface(detailOutputHost, 4, GC.subcard, GC.subcardBorder)
    detailOutputHost:Hide()

    detailIcon = EXUI:CreateRoundedImage(detailSurface, 9)
    detailIcon:SetSize(46, 46)
    detailIcon:SetPoint("TOPLEFT", 14, -14)
    detailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detailIconBorder = CreateFrame("Frame", nil, detailSurface, "BackdropTemplate")
    detailIconBorder:SetSize(48, 48)
    detailIconBorder:SetPoint("TOPLEFT", detailIcon, "TOPLEFT", -1, 1)
    EXUI:ClearControlSurface(detailIconBorder)

    detailTitle = EXUI:CreateVisualFontString(detailSurface, EXFONTFRAME, "GameFontNormalLarge")
    detailTitle:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 8, -1)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetWordWrap(true)
    detailTitle:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.spellDetailTitle, "")
    detailTitle:SetTextColor(unpack(GC.text))

    detailMeta = EXUI:CreateVisualFontString(detailSurface, EXFONTFRAME, "GameFontHighlight")
    detailMeta:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -2)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetWordWrap(true)
    detailMeta:SetFont(ExwindTools.MAIN_FONT, GM.font.hint, "")
    detailMeta:SetTextColor(unpack(GC.textDim))
    detailMeta:Hide()

    local function CreateDetailIDChip(label, color)
        local chip = CreateFrame("Frame", nil, detailSurface, "BackdropTemplate")
        EXUI:SetControlSurface(chip, 5, GC.input, GC.panelBorder)
        if chip.SetClipsChildren then chip:SetClipsChildren(true) end
        if label then
            chip.label = EXUI:CreateVisualFontString(chip, EXFONTFRAME, "GameFontDisableSmall")
            chip.label:SetPoint("LEFT", chip, "LEFT", 9, 0)
            chip.label:SetFont(ExwindTools.MAIN_FONT, GM.font.hint, "")
            chip.label:SetTextColor(unpack(GC.textDim))
            chip.label:SetText(label)
            chip.label:SetWordWrap(false)
            if chip.label.SetMaxLines then chip.label:SetMaxLines(1) end
        end
        chip.value = EXUI:CreateVisualFontString(chip, EXFONTFRAME, "GameFontHighlightSmall")
        if chip.label then
            chip.value:SetPoint("LEFT", chip.label, "RIGHT", 6, 0)
            chip.value:SetPoint("RIGHT", chip, "RIGHT", -9, 0)
            chip.value:SetJustifyH("LEFT")
        else
            chip.value:SetPoint("LEFT", chip, "LEFT", 9, 0)
            chip.value:SetPoint("RIGHT", chip, "RIGHT", -9, 0)
            chip.value:SetJustifyH("CENTER")
        end
        chip.value:SetFont(ExwindTools.MAIN_FONT, GM.font.text, "")
        chip.value:SetTextColor(unpack(color or GC.text))
        chip.value:SetWordWrap(false)
        if chip.value.SetMaxLines then chip.value:SetMaxLines(1) end
        chip:EnableMouse(true)
        chip:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            local labelText = self.label and tostring(self.label:GetText() or "") or ""
            local valueText = self.value and tostring(self.value:GetText() or "") or ""
            local fullText = labelText ~= "" and (labelText .. "：" .. valueText) or valueText
            if fullText == "" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(fullText, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        chip:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return chip, chip.value
    end
    detailCastChip, detailCast = CreateDetailIDChip(nil, { 0.68, 0.84, 0.96, 1 })
    detailRangeChip, detailRangeValue = CreateDetailIDChip(nil, { 0.65, 0.83, 0.78, 1 })
    detailFirstChip, detailFirstValue = CreateDetailIDChip(L["首次"])
    detailCDChip, detailCDValue = CreateDetailIDChip("CD")
    detailSpellIDChip, detailSpellIDValue = CreateDetailIDChip("ID")

    detailBodyScroll = EXUI:CreateScrollFrame(detailSurface)
    detailBodyChild = CreateFrame("Frame", nil, detailBodyScroll)
    detailBodyChild:SetSize(1, 1)
    detailBodyScroll:SetScrollChild(detailBodyChild)
    detailBody = EXUI:CreateVisualFontString(detailBodyChild, EXFONTFRAME, "GameFontHighlight")
    detailBody:SetPoint("TOPLEFT", 0, 0)
    detailBody:SetJustifyH("LEFT")
    detailBody:SetJustifyV("TOP")
    detailBody:SetWordWrap(true)
    detailBody:SetSpacing(1)
    detailBody:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.previewText, "")
    detailBody:SetTextColor(unpack(GC.textDim))

    detailDivider = EXUI:CreateVisualTexture(detailSurface, EXBORDERFRAME)
    detailDivider:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 10)
    detailDivider:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -14, 10)
    detailDivider:SetHeight(1)
    detailDivider:SetColorTexture(unpack(GC.headerDivider))
    detailDivider:Hide()

    detailInfo = EXUI:CreateVisualFontString(detailSurface, EXFONTFRAME, "GameFontHighlightSmall")
    detailInfo:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 16)
    detailInfo:SetPoint("RIGHT", detailPane, "RIGHT", -18, 0)
    detailInfo:SetJustifyH("LEFT")
    detailInfo:SetJustifyV("BOTTOM")
    detailInfo:SetWordWrap(true)
    detailInfo:SetTextColor(unpack(GC.textDim))

    local settingsTitle = EXUI:CreateVisualFontString(settingsPane, EXFONTFRAME, "GameFontNormal")
    settingsTitle:SetPoint("TOPLEFT", 10, -8)
    settingsTitle:SetText("")
    settingsTitle:SetTextColor(unpack(GC.text))
    settingsTitle:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.previewText, "OUTLINE")

    settingsScrollFrame = CreateFrame("ScrollFrame", nil, settingsPane, "ScrollFrameTemplate")
    settingsScrollFrame:SetPoint("TOPLEFT", 0, 0)
    settingsScrollFrame:SetPoint("BOTTOMRIGHT", settingsPane, "BOTTOMRIGHT", -18, 0)
    settingsScrollChild = CreateFrame("Frame", nil, settingsScrollFrame)
    settingsScrollChild:SetWidth(900)
    settingsScrollChild:SetHeight(420)
    settingsScrollFrame:SetScrollChild(settingsScrollChild)

    if ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(spellScrollFrame)
        ExBoss.UI.ApplyModernScrollBarSkin(settingsScrollFrame)
    end
    SetDetailCardEmpty(L["点击左侧技能后，可在此查看法术描述。"])
end

-- Unified Shell 的 B+C 必须由 Core 按 20:80 分配。本页原本把这套结构硬编码
-- 在单一 root 的 380px 左栏内；这里仅重新挂接既有 pane，不改副本/法术/设置数据。
-- [共享宿主边界] 只可调整 left/map 与 content/spell/settings 三 pane 的锚点；Unified 挂载、独立滚动与选择状态禁止修改。
local function ApplyHostLayout(leftHost, contentHost)
    if not root or not contentHost then return end
    local contentWidth, contentHeight = contentHost:GetWidth(), contentHost:GetHeight()
    local leftWidth = leftHost and leftHost:GetWidth() or 0
    if Page._layoutLeftHost == leftHost and Page._layoutContentHost == contentHost
        and Page._layoutContentWidth == contentWidth and Page._layoutContentHeight == contentHeight
        and Page._layoutLeftWidth == leftWidth then
        mapPane:Show()
        spellPane:Show()
        detailPane:Show()
        settingsPane:Show()
        return
    end
    Page._layoutLeftHost, Page._layoutContentHost = leftHost, contentHost
    Page._layoutContentWidth, Page._layoutContentHeight = contentWidth, contentHeight
    Page._layoutLeftWidth = leftWidth
    root:SetParent(contentHost)
    root:ClearAllPoints()
    root:SetAllPoints(contentHost)
    local nav = leftHost or root
    local width = math.max(1, contentHost:GetWidth())
    local navWidth = leftHost and leftHost:GetWidth() or (width <= 1180 and 220 or math.max(248, math.min(320, width * 0.21)))
    local mainLeft = leftHost and 16 or navWidth + 16
    local navInset = navWidth <= 220 and 11 or 14
    local navTopInset = navWidth <= 220 and 15 or 18
    mapPane:SetParent(nav)
    mapPane:ClearAllPoints()
    mapPane:SetPoint("TOPLEFT", nav, "TOPLEFT", navInset, -navTopInset)
    mapPane:SetWidth(math.max(1, navWidth - navInset * 2))
    spellPane:SetParent(nav)
    spellPane:ClearAllPoints()
    spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", -6, -10)
    spellPane:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -4, navTopInset)
    detailPane:SetParent(root)
    detailPane:ClearAllPoints()
    detailPane:SetPoint("TOPLEFT", root, "TOPLEFT", mainLeft, -16)
    detailPane:SetPoint("TOPRIGHT", root, "TOPRIGHT", -16, -16)
    detailPane:SetHeight(C.SPELL_DETAIL_HEIGHT)
    -- EnsureUI may run before the unified hosts have their final size.  Reapply
    -- the same surface after final anchoring so a direct first open has the
    -- same border as a page that has already gone through hide/show.
    EXUI:SetControlSurface(detailPane, 10, GC.card, GC.panelBorder)
    settingsPane:SetParent(root)
    settingsPane:ClearAllPoints()
    settingsPane:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -8)
    settingsPane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -16, 16)
    mapScrollChild:SetWidth(math.max(1, mapScrollFrame:GetWidth() - 4))
    spellScrollChild:SetWidth(math.max(1, spellScrollFrame:GetWidth() - 4))
    C.SPELL_CARD.cols = 1
    mapPane:Show()
    spellPane:Show()
    detailPane:Show()
    settingsPane:Show()
end

-- Geometry-only resize, preserving the mounted controls and all selection state.
function Page:RelayoutPrototype()
    if not (Page._visible and Page._prototypeContentHost) then return end
    ApplyHostLayout(Page._prototypeLeftHost, Page._prototypeContentHost)
    local width = math.max(1, spellScrollChild:GetWidth())
    local columns = C.SPELL_CARD.cols
    local cardWidth = math.max(1, (width - (columns - 1) * C.SPELL_CARD.gapX) / columns)
    local rowHeights = {}
    for i, item in ipairs(activeSpellRows) do
        item:SetWidth(cardWidth)
        item.textBlock:SetHeight(34)
        item.npcCard:SetWidth(math.min(math.max(72,
            math.ceil(item.meta:GetUnboundedStringWidth() or 0) + 12),
            math.max(72, item.textBlock:GetWidth() or 96)))
        local row = math.floor((i - 1) / columns) + 1
        rowHeights[row] = C.SPELL_CARD.height
    end
    local y, visibleHeight = 4, 0
    for row = 1, math.max(1, math.ceil(#activeSpellRows / columns)) do
        local height = rowHeights[row] or C.SPELL_CARD.height
        for i = (row - 1) * columns + 1, math.min(row * columns, #activeSpellRows) do
            local item = activeSpellRows[i]
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", ((i - 1) % columns) * (cardWidth + C.SPELL_CARD.gapX), -y)
            item:SetSize(cardWidth, height)
        end
        if row <= 2 then visibleHeight = y + height end
        y = y + height + C.SPELL_CARD.gapY
    end
    spellScrollChild:SetHeight(math.max(1, y - C.SPELL_CARD.gapY + 4))
    RelayoutDungeonNavigation()
    RefreshDetailCardLayout()
    settingsScrollChild:SetWidth(math.max(1, settingsScrollFrame:GetWidth() - 4))
    if Page._settingsCardSession then Page._settingsCardSession:Invalidate() end
end

-- The Core controller intentionally receives no field route.  Persist every
-- current draft field as the editor's single reapply transaction.
local function RefreshActiveSurfaces()
    if _suspendSpellSettingPersist or Page._visible ~= true then return end
    CancelTrashVoiceSequencePreview()
    local fields = {
        "enabled", "showBunBar", "showTimerBar", "showNameplate",
        "eventColorEnabled", "eventColorMode", "eventColor", "centralEnabled",
        "centralLead", "centralText", "countdownEnabled",
        -- countdownLead 没有自己的 V2 控件，它由 PersistEditorToSelectedSpell 的互写
        -- 与 LoadSelectedSpellToEditor 同步。放进这张表会在 tr2CountdownLead 之前执行，
        -- 用旧值把刚选中的秒数覆盖回去，分段切换因此点不动。
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
    -- The description-card ON/OFF is the only visible enabled control now.
    -- Keep the existing Store/controller write path and only refresh the two
    -- current-page visual consumers after that write has completed.
    local selectedRow = GetSelectedSpellRow()
    local runtimeCfg = selectedRow and GetRuntimeSpellEntry(selectedRow) or nil
    if selectedRow and type(runtimeCfg) == "table" then
        for _, spellRow in ipairs(activeSpellRows) do
            if spellRow.npcID == selectedRow.npcID and spellRow.spellID == selectedRow.spellID then
                spellRow._enabled = runtimeCfg.enabled == true
                if spellRow.check then
                    spellRow.check:SetChecked(spellRow._enabled)
                    spellRow.check:Hide()
                end
                break
            end
        end
        RefreshSpellRowVisuals()
        UpdateDetailCard()
    end
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

-- [页面生命周期边界] Render 仅可新增安全 reflow；不得改变页面 generation、列表刷新次序、draft 身份与预览启动。
function Page:Render(leftHost, contentFrame)
    -- 兼容旧独立面板调用：Render(contentFrame)。
    if contentFrame == nil then
        contentFrame = leftHost
        leftHost = nil
    end
    if not contentFrame then return end
    EnsureUI(contentFrame)
    Page._prototypeLeftHost, Page._prototypeContentHost = leftHost, contentFrame
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

-- [释放边界] 必须保留 ActivePage 清理、V2 控件归还、draft/context 作废、三个 pane/屏幕预览停止；卡壳不得重复释放。
function Page:Hide()
    Page._visible = false
    -- 作废序列并收回播放态必须在释放卡片会话之前：之后拿不到预览按钮。
    CancelTrashVoiceSequencePreview()
    ReleaseTrashSettingsCardSession()
    -- 页面显示值永远不跨页面保存；下次显示重新读取当前 Runtime。
    spellEditorDraft = nil
    spellEditorContext = nil
    _suspendSpellSettingPersist = false
    _spellListBuildToken = _spellListBuildToken + 1
    _selectionRefreshToken = _selectionRefreshToken + 1
    ClearSpellSettingsActiveRegistration()
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
