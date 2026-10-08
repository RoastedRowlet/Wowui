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

local function ResolvePackPreviewPath(label)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and engine.ResolveStandaloneSound) then return nil end
    local info = engine:ResolveStandaloneSound(
        { enabled = true, sourceType = "pack", label = tostring(label or "") },
        { triggerIndex = 0, ignoreState = true })
    return info and info.file or nil
end
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
local spellTitle
local detailPane
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
local settingsVoiceDisabledNote
local voicePreviewTimeline
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
local _asyncHandler
local _spellListBuildToken = 0
local _selectionRefreshToken = 0
local LayoutTrashQuickRow

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
    frame:SetBackdropColor(unpack(GC.panel))
    frame:SetBackdropBorderColor(unpack(GC.panelBorder))
    return frame
end

local function DisableVerticalScroll(scrollFrame)
    if not scrollFrame then return end
    scrollFrame:EnableMouseWheel(false)
    scrollFrame:SetScript("OnMouseWheel", function(self) self:SetVerticalScroll(0) end)
    scrollFrame:SetVerticalScroll(0)
    local bar = scrollFrame.ScrollBar
    if bar then
        bar:Hide()
        bar:SetAlpha(0)
        bar:EnableMouse(false)
    end
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

local function SetWidgetUsable(widget, usable)
    if not widget then
        return
    end
    usable = usable ~= false
    if widget.SetDisabled then
        widget:SetDisabled(not usable)
        return
    end
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
    local outputWidth = math.min(330, math.max(270, math.floor(width * 0.36)))
    local outputGap = 12
    local headerWidth = math.max(120, width - contentX - inset)
    local bodyWidth = math.max(120, width - contentX - inset - outputWidth - outputGap)
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
    detailBodyChild:SetSize(bodyWidth, math.max(1, detailBodyScroll:GetHeight()))
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

-- [卡片/Grid 迁移边界：TrashCD 技能编辑器]
-- 允许：只按共享规范调整 master/quick/text/voice/cast/target 六组的 x/y/w/h、外层卡片与当前可见高度。
-- 禁止：修改稳定 key/type、地图/NPC/法术业务顺序、draft→Store 提交、试听回调或三个 pane 的选择身份。
-- 来源控件共享同一坐标槽位；高度只累计当前可见来源一次。
local function BuildSettingsLayout()
    if SETTINGS_LAYOUT.version == 1 then
        return
    end
    local rows = {
        { key = "enabled", type = "checkbox", x = 80, y = 1, w = 20, h = 5, label = L["启用"], labelSize = GM.font.cardTitle },
        { key = "eventColorEnabled", type = "checkbox", x = 6, y = 16, w = 20, h = 5, label = L["颜色"] },
        { key = "eventColorMode", type = "dropdown", x = 31, y = 16, w = 37, h = 5, label = "", items = EVENT_COLOR_ITEMS_FUNC, labelPos = "left", search = true },
        { key = "eventColor", type = "color", x = 70, y = 16, w = 30, h = 5, label = L["自定义颜色"] },
        { key = "description_trash_text_1", type = "description", x = 6, y = 23, w = 35, h = 5, label = GC.markup.accent .. L["中央文本"] .. "|r" },
        { key = "centralEnabled", type = "checkbox", x = 6, y = 28, w = 25, h = 5, label = L["中央文本"] },
        { key = "centralLead", type = "input", x = 31, y = 28, w = 17, h = 5, label = L["提前(秒)"], labelPos = "right" },
        { key = "centralText", type = "input", x = 31, y = 33, w = 54, h = 5, label = "" },
        { key = "description_trash_text_2", type = "description", x = 6, y = 41, w = 44, h = 5, label = GC.markup.accent .. L["倒数文本"] .. "|r" },
        { key = "countdownEnabled", type = "checkbox", x = 6, y = 45, w = 25, h = 5, label = L["倒数文本"] },
        { key = "preAlertText", type = "input", x = 31, y = 45, w = 54, h = 5, label = "" },
        { key = "description_trash_text_3", type = "description", x = 6, y = 55, w = 44, h = 5, label = GC.markup.accent .. L["计时条改名"] .. "|r" },
        { key = "timerBarRenameEnabled", type = "checkbox", x = 6, y = 60, w = 25, h = 5, label = L["计时条改名"] },
        { key = "timerBarRenameText", type = "input", x = 31, y = 60, w = 54, h = 5, label = "" },

        { key = "description_trash_voice_1", type = "description", x = 6, y = 80, w = 44, h = 5, label = GC.markup.accent .. L["施法开始"] .. "|r" },
        { key = "tr1Enabled", type = "checkbox", x = 6, y = 85, w = 20, h = 5, label = L["施法开始"] },
        { key = "tr1Source", type = "dropdown", x = 31, y = 85, w = 25, h = 5, label = "", items = TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr1Label", type = "dropdown", previewPath = ResolvePackPreviewPath, x = 58, y = 85, w = 30, h = 5, label = "", items = LABEL_ITEMS_FUNC, search = true },
        { key = "tr1LSM", type = "lsm_sound", x = 58, y = 85, w = 30, h = 5, label = "", search = true },
        { key = "tr1Path", type = "input", x = 58, y = 85, w = 30, h = 5, label = "" },
        { key = "tr1ValueTest", type = "button", x = 90, y = 85, w = 10, h = 5, label = "▶", tooltip = L["试听"] },
        { key = "description_trash_voice_2", type = "description", x = 6, y = 97, w = 44, h = 5, label = GC.markup.accent .. L["倒数播报"] .. "|r" },
        { key = "tr2Enabled", type = "checkbox", x = 6, y = 102, w = 20, h = 5, label = L["播放数字"] },
        { key = "tr2CountdownLead", type = "segmented", x = 31, y = 102, w = 25, h = 5, label = "", items = COUNTDOWN_LEAD_ITEMS },
        { key = "tr2PlayTextEnabled", type = "checkbox", x = 6, y = 110, w = 22, h = 5, label = L["播放名称"] },
        { key = "tr2Source", type = "dropdown", x = 31, y = 110, w = 25, h = 5, label = "", items = TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr2Label", type = "dropdown", previewPath = ResolvePackPreviewPath, x = 58, y = 110, w = 30, h = 5, label = "", items = LABEL_ITEMS_FUNC, search = true },
        { key = "tr2LSM", type = "lsm_sound", x = 58, y = 110, w = 30, h = 5, label = "", search = true },
        { key = "tr2Path", type = "input", x = 58, y = 110, w = 30, h = 5, label = "" },
        { key = "tr2ValueTest", type = "button", x = 90, y = 110, w = 10, h = 5, label = "▶", tooltip = L["试听"] },
        { key = "description_voice_preview_heading", type = "description", x = 6, y = 117, w = 44, h = 5,
            label = L["你将听到"] },
        { key = "voiceSequencePreview", type = "button", x = 76, y = 117, w = 24, h = 6,
            label = L["播放预览"] },
        { key = "description_voice_preview_sequence", type = "description", x = 6, y = 124, w = 94, h = 8,
            label = L["静默"] },

        { key = "showBunBar", type = "checkbox", x = 105, y = 1, w = 15, h = 5, label = L["竖条"] },
        { key = "showTimerBar", type = "checkbox", x = 134, y = 1, w = 20, h = 5, label = L["计时条"] },
        { key = "showNameplate", type = "checkbox", x = 166, y = 1, w = 20, h = 5, label = L["纪事条姓名板"] },

        { key = "ringEnabled", type = "checkbox", x = 107, y = 16, w = 59, h = 5, label = L["显示圆环"] },
        { key = "castProgressBarEnabled", type = "checkbox", x = 107, y = 23, w = 59, h = 5, label = L["显示读条"] },
        { key = "castProgressBarRenameEnabled", type = "checkbox", x = 107, y = 28, w = 20, h = 5, label = L["读条改名"] },
        { key = "castProgressBarRenameText", type = "input", x = 132, y = 28, w = 54, h = 5, label = "" },
        { key = "ringCastCheckEnabled", type = "checkbox", x = 107, y = 36, w = 30, h = 5, label = L["施法检测"] },
        { key = "description_cast_check", type = "description", x = 107, y = 40, w = 79, h = 5,
            label = L["检测当前读条能否完成，来不及时以红色提示。"] },
        { key = "targetAlertStartEnabled", type = "checkbox", x = 107, y = 85, w = 35, h = 5, label = L["启用"] },
        { key = "targetAlertStartLSM", type = "lsm_sound", x = 144, y = 85, w = 42, h = 5, label = "", labelPos = "left", search = true },
        { key = "targetAlertStartValueTest", type = "button", x = 189, y = 85, w = 10, h = 5, label = "▶", tooltip = L["试听"] },
        { key = "targetAlertTankEnabled", type = "checkbox", x = 107, y = 95, w = 44, h = 5, label = L["坦克也生效"] },
        { key = "targetVisualHeading", type = "description", x = 107, y = 101, w = 79, h = 5,
            label = GC.markup.textDim .. L["视觉提示"] .. "|r" },
        { key = "targetAlertRingEnabled", type = "checkbox", x = 107, y = 107, w = 20, h = 7, label = L["圆环"] },
        { key = "targetAlertIconEnabled", type = "checkbox", x = 127, y = 107, w = 20, h = 7, label = L["图标"] },
        { key = "targetAlertTextEnabledV2", type = "checkbox", x = 149, y = 107, w = 17, h = 7, label = L["文本"] },
        { key = "targetAlertStealthEnabledV2", type = "checkbox", x = 166, y = 107, w = 30, h = 7, label = "|T132089:18:18|t " .. L["隐遁提示"] },
        { key = "targetAudioHeading", type = "description", x = 107, y = 113, w = 79, h = 5,
            label = GC.markup.textDim .. L["语音提示"] .. "|r" },
        { key = "targetPresentationNote", type = "description", x = 107, y = 116, w = 92, h = 5,
            label = L["停用时保留配置，启用后生效。"] },
    }
    local masterKeys = { enabled = true }
    local quickKeys = { showBunBar = true, showTimerBar = true, showNameplate = true }
    local textKeys = { eventColorEnabled = true, eventColorMode = true, eventColor = true }
    local castKeys = { ringEnabled = true, castProgressBarEnabled = true, castProgressBarRenameEnabled = true,
        castProgressBarRenameText = true, ringCastCheckEnabled = true, description_cast_check = true }
    local targetKeys = { targetAlertStartEnabled = true, targetAlertStartLSM = true, targetAlertStartValueTest = true,
        targetAlertTankEnabled = true, targetAlertRingEnabled = true, targetAlertIconEnabled = true,
        targetAlertTextEnabledV2 = true, targetAlertStealthEnabledV2 = true, targetVisualHeading = true,
        targetAudioHeading = true, targetPresentationNote = true }
    local groups = { master = {}, quick = {}, text = {}, voice = {}, cast = {}, target = {} }
    for _, row in ipairs(rows) do
        local group
        if tostring(row.key):find("^description_trash_") and row.key ~= "description_trash_voice_2" then
            group = nil
        elseif masterKeys[row.key] then group = "master"
        elseif quickKeys[row.key] then group = "quick"
        elseif castKeys[row.key] then group = "cast"
        elseif targetKeys[row.key] then group = "target"
        elseif textKeys[row.key] or (tonumber(row.y) or 0) < 73 then group = "text"
        else group = "voice" end
        if group then
            local xOffset = group == "quick" and 104
                or (group == "cast" or group == "target") and 106
                or (group == "text" or group == "voice") and 5 or 0
            local yOffset = group == "text" and 15 or group == "voice" and 79
                or group == "cast" and 15 or group == "target" and 84 or 0
            row.x = math.max(1, (tonumber(row.x) or 1) - xOffset)
            row.y = math.max(1, (tonumber(row.y) or 1) - yOffset)
            groups[group][#groups[group] + 1] = row
        end
    end
    local cardGap = 6
    local topRowBodyHeight = 196
    local wideColumnRatio = 1.57 / 2.57
    local narrowColumnRatio = 1 / 2.57
    local wideColumn = { ratio = wideColumnRatio, offset = -cardGap * wideColumnRatio }
    local narrowColumn = { ratio = narrowColumnRatio, offset = -cardGap * narrowColumnRatio }
    SETTINGS_LAYOUT = { version = 1,
        settingsListWidthPercent = 100, settingsLayoutBreakpoint = 1, cards = {
        { id = "master", title = L["通用设置"], collapsible = false,
            placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT" },
            content = { kind = "grid", items = groups.master },
            settingsList = { summaryEnabled = true } },
        { id = "quick", title = "", collapsible = false,
            placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT", width = { ratio = 1 } },
            content = { kind = "grid", items = groups.quick },
            settingsList = { rows = {
                { controls = { { key = "showBunBar", presentation = "card" },
                    { key = "showTimerBar", presentation = "card" },
                    { key = "showNameplate", presentation = "card" } } },
            } } },
        { id = "text", title = L["文本设置"], collapsible = false,
            equalHeightGroup = "trash-settings-top", minBodyHeight = topRowBodyHeight,
            placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT", width = wideColumn,
                narrow = { target = "$container", width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.text },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                    { controlsLayout = "fieldRow", controls = { { key = "eventColorEnabled", role = "label" }, { key = "eventColorMode" }, { key = "eventColor" } } },
                    { controlsLayout = "fieldRow", controls = { { key = "centralEnabled", role = "label" }, { key = "centralLead", width = 92 }, { key = "centralText" } } },
                    { controlsLayout = "fieldRow", controls = { { key = "countdownEnabled", role = "label" }, { key = "preAlertText" } } },
                    { controlsLayout = "fieldRow", controls = { { key = "timerBarRenameEnabled", role = "label" }, { key = "timerBarRenameText" } } },
                } } },
        { id = "voice", title = L["语音设置"], collapsible = false,
            equalHeightGroup = "trash-settings-bottom",
            placement = { target = "text", side = "below", align = "start", gap = cardGap + 10, width = wideColumn,
                rowAfter = { "text", "cast" },
                narrow = { target = "cast", side = "below", align = "start", gap = cardGap, width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.voice },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                    { controlsLayout = "compactVoice", controls = { { key = "tr1Enabled", role = "label" }, { key = "tr1Source" }, { key = "tr1Label" }, { key = "tr1LSM" }, { key = "tr1Path" }, { key = "tr1ValueTest", width = 35 } } },
                    { key = "description_trash_voice_2", informational = true },
                    { controlsLayout = "fieldRow", controls = { { key = "tr2Enabled", role = "label" }, { key = "tr2CountdownLead" } } },
                    { controlsLayout = "compactVoice", controls = { { key = "tr2PlayTextEnabled", role = "label" }, { key = "tr2Source" }, { key = "tr2Label" }, { key = "tr2LSM" }, { key = "tr2Path" }, { key = "tr2ValueTest", width = 35 } } },
                    { controls = { { key = "description_voice_preview_heading", role = "label" },
                        { key = "voiceSequencePreview", width = 130, presentation = "primary", align = "right" } } },
                    { key = "description_voice_preview_sequence", informational = true },
                } } },
        { id = "cast", title = L["施法设置"], collapsible = false,
            equalHeightGroup = "trash-settings-top", minBodyHeight = topRowBodyHeight,
            placement = { target = "text", side = "right", align = "start", gap = cardGap, width = narrowColumn,
                narrow = { target = "text", side = "below", align = "start", gap = cardGap, width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.cast },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                { controls = { { key = "ringEnabled", presentation = "card" },
                    { key = "castProgressBarEnabled", presentation = "card" } } },
                { key = "ringCastCheckEnabled", presentation = "card", descriptionKey = "description_cast_check" },
                { key = "castProgressBarRenameEnabled", children = { { key = "castProgressBarRenameText", indent = 28 } } },
            } } },
        { id = "target", title = L["被点名提示"], collapsible = false,
            equalHeightGroup = "trash-settings-bottom",
            placement = { target = "voice", side = "right", align = "start", gap = cardGap, width = narrowColumn,
                narrow = { target = "voice", side = "below", align = "start", gap = cardGap, width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.target },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                { key = "targetAlertStartEnabled", presentation = "switch" },
                { key = "targetVisualHeading", informational = true },
                { controls = { { key = "targetAlertRingEnabled", presentation = "card" },
                    { key = "targetAlertTextEnabledV2", presentation = "card" },
                    { key = "targetAlertIconEnabled", presentation = "card" } } },
                { key = "targetAlertStealthEnabledV2", presentation = "card" },
                { key = "targetAlertTankEnabled" },
                { key = "targetAudioHeading", informational = true },
                { controls = { { key = "targetAlertStartLSM" }, { key = "targetAlertStartValueTest", width = 35 } } },
                { key = "targetPresentationNote", informational = true },
            } } },
    } }
    if ExwindTools and ExwindTools.RegisterModuleLayout then
        ExwindTools:RegisterModuleLayout(SPELL_SETTINGS_MODULE_KEY, SETTINGS_LAYOUT)
    end
end

local function ApplyTrashSettingsLabelLayout(widgets)
    for _, card in ipairs(SETTINGS_LAYOUT.cards or {}) do
        local list = card.settingsList
        if list and list.cardPresentation == "exbossSkill" then
            for _, row in ipairs(list.rows or {}) do
                if row.controlsLayout == "fieldRow" or row.controlsLayout == "compactVoice" then
                    for _, control in ipairs(row.controls or {}) do
                        if control.role == "label" then
                            local widget = widgets[control.key]
                            if widget and widget.checkbox and widget.label then
                                local label = widget.label
                                label:ClearAllPoints()
                                label:SetPoint("LEFT", widget.checkbox, "RIGHT", 7, 0)
                                label:SetPoint("RIGHT", widget, "RIGHT", -2, 0)
                                label:SetJustifyH("LEFT")
                                label:SetWordWrap(true)
                                if label.SetMaxLines then label:SetMaxLines(0) end
                                if widget.SetClipsChildren then widget:SetClipsChildren(false) end
                            end
                        end
                    end
                end
            end
        end
    end
    if Page._settingsCardSession then Page._settingsCardSession:Relayout() end
end

local function AnchorTrashWidget(widget, parent, left, top, width, height, right)
    if not widget then return end
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    if right then
        widget:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, -top)
    elseif width then
        widget:SetWidth(width)
    end
    if height then widget:SetHeight(height) end
    widget:Show()
end

local function HideTrashSettingsRowDividers(body)
    local Grid = _G.ExwindGrid
    local list = Grid and Grid:GetSettingsListSession(body)
    for _, entry in ipairs(list and list.entries or {}) do
        local divider = entry.host and entry.host._exSettingsRowDivider
        if divider then divider:Hide() end
    end
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
    local session = Page._settingsCardSession
    local button = session and session.GetWidget
        and session:GetWidget("voice", "voiceSequencePreview") or nil
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

LayoutTrashQuickRow = function(session)
    local state = session.byId.quick
    local card, body = state and state.card, state and state.body
    if not (card and body and detailOutputHost) then return end
    HideTrashSettingsRowDividers(body)
    -- The three controls are rendered in the detail card, so keep the source
    -- card hidden through the CardSession state.  Calling card:Hide() here
    -- fights Core's relayout (which restores state.visible) and creates an
    -- endless Show -> OnShow reflow -> Hide loop while this page is visible.
    if state.visible ~= false then
        session:SetCardVisible("quick", false)
    end
    local inset, gap = 8, 4
    local width = math.max(1, detailOutputHost:GetWidth() or 330)
    local itemWidth = math.max(78, (width - inset * 2 - gap * 2) / 3)
    for index, key in ipairs({ "showBunBar", "showTimerBar", "showNameplate" }) do
        local widget = session:GetWidget("quick", key)
        if widget then
            widget:SetParent(detailOutputHost)
            if widget.SetFrameLevel then
                widget:SetFrameLevel((detailOutputHost:GetFrameLevel() or 0) + 1)
            end
            if widget.checkbox and widget.checkbox.SetFrameLevel then
                widget.checkbox:SetFrameLevel((widget:GetFrameLevel() or 0) + 1)
            end
            AnchorTrashWidget(widget, detailOutputHost,
                inset + (index - 1) * (itemWidth + gap), 2, itemWidth, 30)
        end
    end
    state.reportedHeight = 0
    return 0
end

local function LayoutTrashTextCard(session)
    local state = session.byId.text
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    HideTrashSettingsRowDividers(body)
    local inset, gap = 14, 8
    local bodyWidth = math.max(1, body:GetWidth() or 600)
    local labelWidth = math.max(150, math.floor((bodyWidth - inset * 2) * 0.46))
    local controlLeft = inset + labelWidth
    local controlWidth = math.max(180, bodyWidth - controlLeft - inset)
    local modeWidth = math.max(132, math.floor((controlWidth - gap) * 0.56))
    local leadWidth = 70

    for index, top in ipairs({ 43, 91, 139 }) do
        local divider = card._exTrashTextDividers and card._exTrashTextDividers[index]
        if divider then
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -top)
            divider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, -top)
            divider:Show()
        end
    end

    AnchorTrashWidget(session:GetWidget("text", "eventColorEnabled"), body, inset, 4, labelWidth, 30)
    AnchorTrashWidget(session:GetWidget("text", "eventColorMode"), body, controlLeft, 4, modeWidth, 30)
    local eventColor = session:GetWidget("text", "eventColor")
    if eventColor then
        eventColor:ClearAllPoints()
        eventColor:SetPoint("TOPLEFT", body, "TOPLEFT", controlLeft + modeWidth + gap, -4)
        eventColor:SetSize(math.max(1, controlWidth - modeWidth - gap), 30)
    end
    AnchorTrashWidget(session:GetWidget("text", "centralEnabled"), body, inset, 52, labelWidth, 30)
    local centralLead = session:GetWidget("text", "centralLead")
    AnchorTrashWidget(centralLead, body, controlLeft, 52, leadWidth, 30)
    AnchorTrashWidget(session:GetWidget("text", "centralText"), body, controlLeft + leadWidth + gap, 52,
        math.max(1, controlWidth - leadWidth - gap), 30)
    if centralLead and centralLead.label then
        if not centralLead._exTrashUnitInside then
            centralLead._exTrashUnitOriginalText = centralLead.label:GetText()
        end
        centralLead._exTrashUnitInside = true
        centralLead:SetTextInsets(9, 30, 0, 0)
        centralLead.label:ClearAllPoints()
        centralLead.label:SetPoint("RIGHT", centralLead, "RIGHT", -8, 0)
        centralLead.label:SetJustifyH("RIGHT")
        centralLead.label:SetText(L["秒"])
        centralLead.label:Show()
    end
    AnchorTrashWidget(session:GetWidget("text", "countdownEnabled"), body, inset, 100, labelWidth, 30)
    AnchorTrashWidget(session:GetWidget("text", "preAlertText"), body, controlLeft, 100, controlWidth, 30)
    AnchorTrashWidget(session:GetWidget("text", "timerBarRenameEnabled"), body, inset, 148, labelWidth, 30)
    AnchorTrashWidget(session:GetWidget("text", "timerBarRenameText"), body, controlLeft, 148, controlWidth, 30)
    state.reportedHeight = 196
    return 196
end

local function LayoutTrashCastCard(session)
    local state = session.byId.cast
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    local inset, gap = 14, 8
    local choiceWidth = math.max(1, ((body:GetWidth() or 400) - inset * 2 - gap) / 2)
    AnchorTrashWidget(session:GetWidget("cast", "ringEnabled"), body, inset, 6, choiceWidth, 40)
    AnchorTrashWidget(session:GetWidget("cast", "castProgressBarEnabled"), body,
        inset + choiceWidth + gap, 6, choiceWidth, 40)
    HideTrashSettingsRowDividers(body)
    local castCheck = session:GetWidget("cast", "ringCastCheckEnabled")
    local castDescription = session:GetWidget("cast", "description_cast_check")
    if not card._exTrashCastCheckHelp then
        local ringTexture = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RingWhiteThin2.tga"
        local help = EXUI:CreatePicButton(body, 11, 11,
            ringTexture, ringTexture, ringTexture, nil, true)
        card._exTrashCastCheckHelp = help
        help.label = EXUI:CreateVisualFontString(help, EXFONTFRAME, "GameFontDisableSmall")
        help.label:SetPoint("CENTER", 0, 0)
        help.label:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.micro, "")
        help.label:SetText("?")
        help.label:SetTextColor(unpack(GC.textDim))
        help:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["检测当前读条能否完成，来不及时以红色提示。"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        help:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    AnchorTrashWidget(castCheck, body, inset, 62, nil, 64, inset)
    if castDescription then
        AnchorTrashWidget(castDescription, castCheck, 0, 33, nil, 23, 14)
        if castDescription.text then
            castDescription.text:SetFont(ExwindTools.MAIN_FONT, GM.font.hint, "")
            castDescription.text:SetTextColor(unpack(GC.textDim))
        end
        EXUI:LayoutCheckboxCardDescription(castCheck, castDescription, 23)
    end
    card._exTrashCastCheckHelp:ClearAllPoints()
    card._exTrashCastCheckHelp:SetPoint("TOPRIGHT", castCheck, "TOPRIGHT", -8, -7)
    card._exTrashCastCheckHelp:SetFrameLevel(castCheck:GetFrameLevel() + 3)
    card._exTrashCastCheckHelp:Hide() -- 用户要求删除施法检测右上角问号（原 Show()）
    AnchorTrashWidget(session:GetWidget("cast", "castProgressBarRenameEnabled"), body, inset, 148, choiceWidth, 30)
    AnchorTrashWidget(session:GetWidget("cast", "castProgressBarRenameText"), body,
        inset + choiceWidth + gap, 148, nil, 30, inset)
    state.reportedHeight = 196
    return 196
end

local function SetTrashPlayButtonVisual(button)
    if not button then return end
    EXUI:ApplySoundPreviewAppearance(button)
end

local function LayoutTrashAudioControls(session, prefix, parent, top, left, sourceWidth, rightPad)
    EXUI:LayoutSoundSelector(parent, {
        source = session:GetWidget("voice", prefix .. "Source"),
        preview = session:GetWidget("voice", prefix .. "ValueTest"),
        contents = { pack = session:GetWidget("voice", prefix .. "Label"),
            lsm = session:GetWidget("voice", prefix .. "LSM"),
            file = session:GetWidget("voice", prefix .. "Path") },
        top = top, left = left, sourceWidth = sourceWidth, right = rightPad or 12,
        height = 30, previewWidth = 28, paintPreview = SetTrashPlayButtonVisual,
    })
end

local function LayoutTrashAudioRow(session, prefix, parent, top, labelWidth, sourceWidth)
    AnchorTrashWidget(session:GetWidget("voice", prefix .. "Enabled"), parent, 14, top, labelWidth, 30)
    LayoutTrashAudioControls(session, prefix, parent, top, 14 + labelWidth, sourceWidth, 12)
end

local function GetTrashVoiceContentHeight(timelineHeight)
    -- Boss 页的语音卡高度减去小怪页唯一缺少的“中央文本”一行（44px）。
    return 156 + (timelineHeight or 70)
end

local function LayoutTrashVoiceCard(session)
    local state = session.byId.voice
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    HideTrashSettingsRowDividers(body)
    local bodyWidth = math.max(1, body:GetWidth() or 600)
    local labelWidth = math.max(128, math.floor(bodyWidth * 0.36))
    local sourceWidth = math.max(78, math.floor((bodyWidth - labelWidth - 56) * 0.25))
    LayoutTrashAudioRow(session, "tr1", body, 4, labelWidth, sourceWidth)
    if card._exTrashVoicePrimaryDivider then
        card._exTrashVoicePrimaryDivider:ClearAllPoints()
        card._exTrashVoicePrimaryDivider:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -41)
        card._exTrashVoicePrimaryDivider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -41)
        card._exTrashVoicePrimaryDivider:Show()
    end

    local surface = card._exTrashVoiceTimingSurface
    if not surface then return end
    surface:ClearAllPoints()
    surface:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -50)
    surface:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 10)
    surface:SetFrameLevel(body:GetFrameLevel() or 1)
    EXUI:ClearControlSurface(surface)
    surface:Show()

    local heading = session:GetWidget("voice", "description_trash_voice_2")
    if heading then heading:Hide() end
    local controlLeft = labelWidth + 2
    AnchorTrashWidget(session:GetWidget("voice", "tr2Enabled"), surface, 2, 4, controlLeft - 2, 30)
    local segmented = session:GetWidget("voice", "tr2CountdownLead")
    if segmented then
        segmented:SetParent(surface)
        segmented:SetFrameLevel(surface:GetFrameLevel() + 6)
        segmented:ClearAllPoints()
        segmented:SetPoint("TOPLEFT", surface, "TOPLEFT", controlLeft, -4)
        segmented:SetPoint("TOPRIGHT", surface, "TOPRIGHT", 0, -4)
        segmented.itemHeight = 30
        segmented:SetHeight(30)
        segmented:Show()
    end
    local playName = session:GetWidget("voice", "tr2PlayTextEnabled")
    AnchorTrashWidget(playName, surface, 2, 44, controlLeft - 2, 30)
    LayoutTrashAudioControls(session, "tr2", surface, 44, controlLeft, sourceWidth, 0)

    if card._exTrashVoicePreviewDivider then
        card._exTrashVoicePreviewDivider:Hide()
    end
    if card._exTrashVoicePreviewBackground then
        card._exTrashVoicePreviewBackground:ClearAllPoints()
        card._exTrashVoicePreviewBackground:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, -82)
        card._exTrashVoicePreviewBackground:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", 0, 0)
        EXUI:SetControlSurface(card._exTrashVoicePreviewBackground, 5, GC.panel, GC.cardBorder)
        card._exTrashVoicePreviewBackground:Show()
    end
    local previewHeading = session:GetWidget("voice", "description_voice_preview_heading")
    if previewHeading then previewHeading:Hide() end
    local previewSequence = session:GetWidget("voice", "description_voice_preview_sequence")
    if previewSequence then previewSequence:Hide() end
    local previewButton = session:GetWidget("voice", "voiceSequencePreview")
    if previewButton then
        previewButton:ClearAllPoints()
        previewButton:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -8, 8)
        previewButton:SetFrameLevel(surface:GetFrameLevel() + 6)
        previewButton._exButtonVariant = "secondary"
        EXUI:ApplyControlAppearance(previewButton)
        previewButton:SetSize(28, 28)
        SetTrashPlayButtonVisual(previewButton)
        previewButton:Show()
    end
    local timelineHeight = 68
    if voicePreviewTimeline then
        voicePreviewTimeline:ClearAllPoints()
        voicePreviewTimeline:SetPoint("TOPLEFT", surface, "TOPLEFT", 10, -94)
        voicePreviewTimeline:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -10, -94)
        voicePreviewTimeline:Show()
        if voicePreviewTimeline._layout then voicePreviewTimeline:_layout() end
        timelineHeight = voicePreviewTimeline:GetHeight() or timelineHeight
    end
    local contentHeight = GetTrashVoiceContentHeight(timelineHeight)
    state.reportedHeight = contentHeight
    return contentHeight
end

local function LayoutTrashTargetCard(session)
    local state = session.byId.target
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    HideTrashSettingsRowDividers(body)
    local start = session:GetWidget("target", "targetAlertStartEnabled")
    AnchorTrashWidget(start, body, 12, 8, nil, 34, 12)
    if start and start.checkbox then
        start.checkbox:ClearAllPoints()
        start.checkbox:SetPoint("RIGHT", start, "RIGHT", -2, 0)
        if start.label then
            start.label:ClearAllPoints()
            start.label:SetPoint("LEFT", start, "LEFT", 0, 0)
            start.label:SetPoint("RIGHT", start.checkbox, "LEFT", -8, 0)
        end
    end
    local visualHeading = session:GetWidget("target", "targetVisualHeading")
    if visualHeading then visualHeading:Hide() end
    local choiceWidth = math.max(68, ((body:GetWidth() or 380) - 40) / 3)
    for index, key in ipairs({ "targetAlertRingEnabled", "targetAlertTextEnabledV2", "targetAlertIconEnabled" }) do
        AnchorTrashWidget(session:GetWidget("target", key), body,
            12 + (index - 1) * (choiceWidth + 8), 64, choiceWidth, 36)
    end
    AnchorTrashWidget(session:GetWidget("target", "targetAlertStealthEnabledV2"), body, 12, 118, nil, 44, 12)
    AnchorTrashWidget(session:GetWidget("target", "targetAlertTankEnabled"), body, 12, 186, nil, 30, 12)
    local audioHeading = session:GetWidget("target", "targetAudioHeading")
    if audioHeading then audioHeading:Hide() end
    local sound = session:GetWidget("target", "targetAlertStartLSM")
    local test = session:GetWidget("target", "targetAlertStartValueTest")
    AnchorTrashWidget(sound, body, 12, 232, nil, 30, 52)
    if test then
        test:ClearAllPoints()
        test:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -232)
        test:SetSize(28, 30)
        SetTrashPlayButtonVisual(test)
        test:Show()
    end
    local note = session:GetWidget("target", "targetPresentationNote")
    if note then note:Hide() end
    if not card._exTrashTargetDividers then
        card._exTrashTargetDividers = {}
        for index = 1, 2 do
            card._exTrashTargetDividers[index] = EXUI:CreateSettingsSeparator(body, 1)
        end
    end
    for index, top in ipairs({ 118, 174 }) do
        local divider = card._exTrashTargetDividers[index]
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -top)
        divider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -top)
        divider:SetShown(index == 2)
    end
    state.reportedHeight = 274
    return 274
end

local function ApplyTrashCustomCardLayouts(session)
    if not (session and session.byId and session.GetWidget) then return end
    LayoutTrashQuickRow(session)
    LayoutTrashTextCard(session)
    LayoutTrashCastCard(session)
    LayoutTrashVoiceCard(session)
    LayoutTrashTargetCard(session)
    local summaryEnabled = session:GetWidget("master", "enabled")
    if summaryEnabled and detailEnableHost then
        detailEnableHost:SetSize(90, 28)
        summaryEnabled:ClearAllPoints()
        summaryEnabled:SetAllPoints(detailEnableHost)
    end
end

local function ApplyTrashSettingsCardSurfaces(session)
    if not (session and session.byId) then return end
    local quickState = session.byId.quick
    local quickCard, quickBody = quickState and quickState.card, quickState and quickState.body
    if quickCard and quickBody then
        local header = quickCard._exSettingsCardHeader
        local title = quickCard._exSettingsCardTitle
        if header then header:Hide() end
        if title then title:Hide() end
        if quickCard._exSettingsListExternalHeader then
            quickCard._exSettingsListExternalHeader.height = 0
            quickCard._exSettingsListExternalHeader.footerPadding = 0
        end
        quickBody:ClearAllPoints()
        quickBody:SetAllPoints(quickCard)
        EXUI:ClearControlSurface(quickCard)
        EXUI:ClearControlSurface(quickBody)
        if quickState.visible ~= false then
            session:SetCardVisible("quick", false)
        end
    end
    for _, id in ipairs({ "text", "cast", "voice", "target" }) do
        local state = session.byId[id]
        local card, body = state and state.card, state and state.body
        if card and body then
            local header = card._exSettingsCardHeader
            local title = card._exSettingsCardTitle
            if card._exSettingsListExternalHeader then
                card._exSettingsListExternalHeader.height = 13
                card._exSettingsListExternalHeader.footerPadding = 0
            end
            if header then
                header:Show()
                header:SetHeight(24)
                header:EnableMouse(false)
                local icon = card._exSettingsCardIcon
                if icon then icon:Hide() end
                if title then
                    title:Show()
                    title:ClearAllPoints()
                    title:SetPoint("LEFT", header, "LEFT", 18, 12)
                    title:SetWidth(math.ceil(title:GetUnboundedStringWidth() or 0) + 2)
                    -- 标题骑在卡片上边框上，必须用同色垫条把边框遮断，否则线会从字中间穿过。
                    -- 与首领页 legend 垫条同一做法。
                    if not card._exTrashLegendBacking then
                        card._exTrashLegendBacking = EXUI:CreateVisualTexture(header, EXBASEFRAME)
                    end
                    local backing = card._exTrashLegendBacking
                    backing:ClearAllPoints()
                    backing:SetPoint("LEFT", header, "LEFT", 12, 12)
                    backing:SetSize(math.ceil(title:GetUnboundedStringWidth() or 0) + 14,
                        PixelUtil.GetNearestPixelSize(2, header:GetEffectiveScale(), 1))
                    backing:SetColorTexture(unpack(GC.panel))
                    backing:Show()
                end
            end
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -13)
            body:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
            EXUI:SetControlSurface(card, 10, GC.card, GC.cardBorder)
            EXUI:ClearControlSurface(body)
        end
    end
    local textState = session.byId.text
    local textCard = textState and textState.card
    local textBody = textState and textState.body
    if textCard and textBody and not textCard._exTrashTextDividers then
        textCard._exTrashTextDividers = {}
        for index = 1, 3 do
            textCard._exTrashTextDividers[index] = EXUI:CreateSettingsSeparator(textBody, 1)
        end
    end
    local voiceState = session.byId.voice
    local voiceCard = voiceState and voiceState.card
    local voiceBody = voiceState and voiceState.body
    if voiceCard and voiceBody then
        voiceCard._exTrashVoiceTimingSurface = voiceCard._exTrashVoiceTimingSurface
            or CreateFrame("Frame", nil, voiceBody, "BackdropTemplate")
        voiceCard._exTrashVoiceTimingSurface:EnableMouse(false)
        local voiceSurface = voiceCard._exTrashVoiceTimingSurface
        voiceCard._exTrashVoicePrimaryDivider = voiceCard._exTrashVoicePrimaryDivider
            or EXUI:CreateSettingsSeparator(voiceBody, 1)
        voiceCard._exTrashVoicePreviewDivider = voiceCard._exTrashVoicePreviewDivider
            or EXUI:CreateSettingsSeparator(voiceSurface, 1)
        if not voiceCard._exTrashVoicePreviewBackground then
            local background = CreateFrame("Frame", nil, voiceSurface, "BackdropTemplate")
            background:EnableMouse(false)
            voiceCard._exTrashVoicePreviewBackground = background
        end
        voiceCard._exTrashVoicePreviewBackground:SetParent(voiceSurface)
        if not voiceCard._exTrashVoicePreviewTimeline then
            local timeline = CreateFrame("Frame", nil, voiceBody)
            timeline:SetFrameLevel((voiceBody:GetFrameLevel() or 1) + 3)
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
                node.tick = EXUI:CreateVisualTexture(timeline, EXBASEFRAME)
                node.tick:SetColorTexture(unpack(GC.cardBorder))
                node.tick:SetSize(PixelUtil.GetNearestPixelSize(1, timeline:GetEffectiveScale(), 1), 6)
                timeline.nodes[index] = node
            end
            timeline._layout = function(self)
                if self._layoutBusy then return end
                self._layoutBusy = true
                local count = 7
                local width = math.max(1, self:GetWidth() or 1)
                local axisWidth = math.max(1, width - 38)
                local slotWidth = axisWidth / count
                local occupied = {}
                for index, node in ipairs(self.nodes) do
                    node:ClearAllPoints()
                    node:SetPoint("TOPLEFT", self, "TOPLEFT", (index - 1) * slotWidth, 0)
                    node:SetSize(slotWidth, 1)
                    if node._previewKind == "trigger" or node._previewKind == "digit" then
                        occupied[#occupied + 1] = {
                            node = node,
                            index = index,
                            center = (index - 0.5) * slotWidth,
                        }
                    end
                end
                local placements, rowHeight = {}, 32
                for position, item in ipairs(occupied) do
                    local node = item.node
                    local previous = occupied[position - 1]
                    local following = occupied[position + 1]
                    local leftBound = 0
                    local rightBound = width
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
                    node.value:SetHeight(0)
                    local valueHeight = math.max(32, math.ceil(node.value:GetStringHeight()) + 10)
                    rowHeight = math.max(rowHeight, valueHeight)
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
                    node.valueHost:SetPoint("TOPLEFT", self, "TOPLEFT", placement.left, 0)
                    node.valueHost:SetSize(placement.width, rowHeight)
                    node.value:ClearAllPoints()
                    node.value:SetPoint("TOPLEFT", node.valueHost, "TOPLEFT", 5, -5)
                    node.value:SetPoint("TOPRIGHT", node.valueHost, "TOPRIGHT", -5, -5)
                    node.value:SetHeight(rowHeight - 10)
                    node.value:SetJustifyH("CENTER")
                    node.value:SetJustifyV("MIDDLE")
                    node.valueHost:Show()
                end
                local axisTop = rowHeight + 10
                self.axis:ClearAllPoints()
                self.axis:SetPoint("TOPLEFT", self, "TOPLEFT", slotWidth / 2, -axisTop)
                self.axis:SetPoint("TOPRIGHT", self, "TOPRIGHT",
                    -(width - axisWidth + slotWidth / 2), -axisTop)
                for index, node in ipairs(self.nodes) do
                    local centerX = (index - 0.5) * slotWidth
                    node.tick:ClearAllPoints()
                    node.tick:SetPoint("TOP", self, "TOPLEFT", centerX, -axisTop + 2)
                    node.time:ClearAllPoints()
                    node.time:SetPoint("TOP", self, "TOPLEFT", centerX, -(axisTop + 7))
                    node.time:SetWidth(slotWidth)
                    node.time:SetHeight(16)
                end
                local timelineHeight = axisTop + 28
                if self:GetHeight() ~= timelineHeight then self:SetHeight(timelineHeight) end
                self._layoutBusy = nil
                local list = _G.ExwindGrid:GetSettingsListSession(voiceBody)
                local owner = self._exTrashCardSession
                local state = self._exTrashCardState
                local contentHeight = GetTrashVoiceContentHeight(timelineHeight)
                if state and state.reportedHeight ~= contentHeight and list and owner and not owner.released
                    and not list.visualLayoutBusy and not owner.reflowBusy then
                    _G.ExwindGrid:RequestReflow(voiceBody)
                end
            end
            timeline:SetScript("OnSizeChanged", function(self) self:_layout() end)
            voiceCard._exTrashVoicePreviewTimeline = timeline
        end
        voiceCard._exTrashVoicePreviewTimeline._exTrashCardSession = session
        voiceCard._exTrashVoicePreviewTimeline._exTrashCardState = voiceState
        voicePreviewTimeline = voiceCard._exTrashVoicePreviewTimeline
    end
    local summaryEnabled = session:GetWidget("master", "enabled")
    if summaryEnabled and summaryEnabled.checkbox and summaryEnabled._exSettingsPresentation ~= "card" then
        EXUI:RestoreSettingsListControl(summaryEnabled)
        EXUI:PrepareSettingsListControl(summaryEnabled, {
            presentation = "card", cardCheckSize = 14, cardTextSize = 12,
        })
    end
    if summaryEnabled and summaryEnabled.checkbox then
        EXUI:ApplyCheckboxOnOffVisual(summaryEnabled)
    end
    local layouts = {
        quick = LayoutTrashQuickRow,
        text = LayoutTrashTextCard,
        cast = LayoutTrashCastCard,
        voice = LayoutTrashVoiceCard,
        target = LayoutTrashTargetCard,
    }
    for id, layout in pairs(layouts) do
        local state = session.byId[id]
        local list = state and _G.ExwindGrid:GetSettingsListSession(state.body)
        if list then
            list.onVisualLayout = function()
                if session.released then return end
                return layout(session)
            end
        end
    end
    session:Relayout()
    ApplyTrashCustomCardLayouts(session)
end

local function ReleaseTrashSettingsCardSession()
    local session = Page._settingsCardSession
    local quickState = session and session.byId and session.byId.quick
    local quickBody = quickState and quickState.body
    if quickBody and session.GetWidget then
        for _, key in ipairs({ "showBunBar", "showTimerBar", "showNameplate" }) do
            local widget = session:GetWidget("quick", key)
            if widget then widget:SetParent(quickBody) end
        end
    end
    if detailOutputHost then detailOutputHost:Hide() end
    local centralLead = session and session.GetWidget and session:GetWidget("text", "centralLead")
    if centralLead and centralLead._exTrashUnitInside then
        centralLead:SetTextInsets(9, 9, 0, 0)
        if centralLead.label then
            centralLead.label:ClearAllPoints()
            centralLead.label:SetPoint("LEFT", centralLead, "RIGHT", 5, 0)
            centralLead.label:SetJustifyH("LEFT")
            centralLead.label:SetText(centralLead._exTrashUnitOriginalText or L["提前(秒)"])
        end
        centralLead._exTrashUnitInside = nil
        centralLead._exTrashUnitOriginalText = nil
    end
    local summaryEnabled = session and session.GetWidget and session:GetWidget("master", "enabled")
    if summaryEnabled then EXUI:ReleaseCheckboxOnOffVisual(summaryEnabled) end
    for _, spec in ipairs({ { "voice", "tr1ValueTest" }, { "voice", "tr2ValueTest" },
        { "voice", "voiceSequencePreview" }, { "target", "targetAlertStartValueTest" } }) do
        local button = session and session.GetWidget and session:GetWidget(spec[1], spec[2])
    end
    local voiceState = session and session.byId and session.byId.voice
    local voiceCard = voiceState and voiceState.card
    if voiceCard then
        for _, key in ipairs({
            "_exTrashVoicePrimaryDivider",
            "_exTrashVoiceTimingSurface",
            "_exTrashVoicePreviewDivider",
            "_exTrashVoicePreviewBackground",
            "_exTrashVoicePreviewTimeline",
        }) do
            local visual = voiceCard[key]
            if visual then
                visual:Hide()
                visual._layoutBusy = nil
            end
        end
    end
    -- 标题遮线垫条在每张卡上都可能存在，释放时一并隐藏。
    for _, state in pairs((session and session.byId) or {}) do
        local card = state and state.card
        if card and card._exTrashLegendBacking then card._exTrashLegendBacking:Hide() end
    end
    for _, id in ipairs({ "text", "cast", "target" }) do
        local state = session and session.byId and session.byId[id]
        local card = state and state.card
        if card then
            for _, key in ipairs({
                "_exTrashCastCheckHelp",
            }) do
                local visual = card[key]
                if visual then visual:Hide() end
            end
            for _, collectionKey in ipairs({ "_exTrashTextDividers", "_exTrashTargetDividers" }) do
                for _, visual in ipairs(card[collectionKey] or {}) do
                    visual:Hide()
                end
            end
        end
    end
    voicePreviewTimeline = nil
    if session and type(session.Release) == "function" then
        session:Release()
    end
    Page._settingsCardSession = nil
end

local function RefreshSettingsDynamicWidgets()
    local Grid = _G.ExwindGrid
    local mdb = GetSpellEditorDB()
    if not (Grid and type(mdb) == "table") then
        return
    end
    if not (settingsScrollChild and Grid.FindMountedWidget) then
        return
    end
    local widgets = setmetatable({}, { __index = function(t, key)
        local widget = Grid:FindMountedWidget(settingsScrollChild, key)
        rawset(t, key, widget)
        return widget
    end })
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

    -- Reserve space only for the existing author notice when it is displayed.
    settingsScrollFrame:ClearAllPoints()
    local noticeHeight = settingsVoiceDisabledNote and settingsVoiceDisabledNote:IsShown()
        and math.ceil(settingsVoiceDisabledNote:GetStringHeight() or 0) + 8 or 0
    settingsScrollFrame:SetPoint("TOPLEFT", settingsPane, "TOPLEFT", 0, -noticeHeight)
    settingsScrollFrame:SetPoint("BOTTOMRIGHT", settingsPane, "BOTTOMRIGHT", -18, 0)

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
            SetWidgetUsable(playTextWidget, not authorVoiceDisabled)
        end

        EXUI:RefreshSoundSelector({
            contents = { pack = packWidget, lsm = lsmWidget, file = pathWidget },
            value = source, preview = valueTestWidget, enabled = configEnabled,
            setUsable = SetWidgetUsable,
        })

        if offsetModeWidget then
            offsetModeWidget:Hide()
        end
        if offsetSecondsWidget then
            offsetSecondsWidget:Hide()
        end
    end
    local countdownSelector = widgets["tr2CountdownLead"]
    if countdownSelector and countdownSelector.SetValue then
        countdownSelector:SetValue(tostring(NormalizeCountdownLeadSeconds(
            mdb.tr2CountdownLead or mdb.countdownLead)))
    end
    SetTrashPlayButtonVisual(widgets["tr1ValueTest"])
    SetTrashPlayButtonVisual(widgets["tr2ValueTest"])
    SetTrashPlayButtonVisual(widgets["voiceSequencePreview"])
    RefreshTrashVoicePreviewDisplay()
    ApplyTrashSettingsLabelLayout(widgets)
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
            if active then
                -- 选中只描边：图标框底色沿用各自原底（未选中 GC.input／悬停时沿用悬停底），
                -- 只换成一圈实心主色轮廓；不加淡底、不抬底、不加左侧指示条。
                EXUI:SetControlSurface(btn.iconFrame, 10,
                    hovered and GC.secondaryHoverFill or GC.input,
                    hovered and GC.primaryFillHover or GC.primaryFill)
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

    row.leftBar = EXUI:CreateVisualTexture(row, EXBACKGROUNDFRAME)
    row.leftBar:SetWidth(4)
    row.leftBar:SetPoint("TOPLEFT", 2, -7)
    row.leftBar:SetPoint("BOTTOMLEFT", 2, 7)
    row.leftBar:Hide()

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
            if self._selected then
                -- 选中只描边：底色沿用各自原底（未选中无底／悬停时沿用悬停底），
                -- 只加一圈实心主色轮廓；不加淡底、不抬底、不显示左侧指示条。
                EXUI:SetControlSurface(self, 4,
                    self._hovered and GC.menuHover or { 0, 0, 0, 0 },
                    self._hovered and GC.primaryFillHover or GC.primaryFill)
            elseif self._hovered then
                EXUI:SetControlSurface(self, 4, GC.menuHover, { 0, 0, 0, 0 })
            else
                EXUI:ClearControlSurface(self)
            end
            self.leftBar:Hide()
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

    local function BuildSync()
        local totalW = (spellScrollChild:GetWidth() or 360)
        totalW = math.max(1, totalW)
        C.SPELL_CARD.cols = 1
        local usableW = math.max(1, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        for i = 1, #orderedRows do
            BuildOne(orderedRows[i], i, cardW)
        end
        Finalize()
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

-- [混合函数边界] 只可迁移设置 Grid 的几何、卡片外框与内容高度反馈；draft/context、RegisterModuleLayout、ActivePage 与持久回调禁止修改。
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
    settingsScrollChild:SetWidth(math.max(1, settingsScrollFrame:GetWidth() - 4))
    if resetScroll == true then
        settingsScrollFrame:SetVerticalScroll(0)
    end
    RegisterSpellSettingsGridAsActive(SPELL_SETTINGS_MODULE_KEY)
    ReleaseTrashSettingsCardSession()
    Page._settingsCardSession = Grid:MountCards(settingsScrollChild, SETTINGS_LAYOUT, {
        pageId = SPELL_SETTINGS_MODULE_KEY,
        regionId = "trash-spell-editor",
        layoutDefaults = { left = 0, right = 0, top = 12, bottom = 0, gap = 6 },
        config = db,
        moduleKey = SPELL_SETTINGS_MODULE_KEY,
        scrollFrame = settingsScrollFrame,
        exbossSummaryEnableHost = detailEnableHost,
    })
    ApplyTrashSettingsCardSurfaces(Page._settingsCardSession)
    if detailOutputHost and GetSelectedSpellRow() then
        detailOutputHost:Show()
        RefreshDetailCardLayout()
    end
    RefreshSettingsDynamicWidgets()
end

-- [混合函数边界] EnsureUI 内只可迁移三 pane、详情卡、Scroll/Grid 的外观与 SetPoint/SetSize；池、OnClick、异步 Spell 数据、预览与回调禁止修改。
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

    -- 左栏下半部与 Boss 页一致：仅作布局宿主，不再套一层可见 Backdrop。
    -- 法术行默认无外框，只在悬停或选中时显示背景状态。
    spellPane = CreateFrame("Frame", nil, root)
    spellPane:SetPoint("TOPLEFT", mapPane, "BOTTOMLEFT", 0, -gap)
    spellPane:SetPoint("BOTTOMLEFT", 8, 8)
    spellPane:SetWidth(leftW)

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

    detailPlaceholder = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontDisableSmall")
    detailPlaceholder:SetPoint("CENTER", 0, 0)
    detailPlaceholder:SetTextColor(unpack(GC.textPlaceholder))
    detailPlaceholder:SetText(L["点击左侧技能后，可在此查看法术描述。"])

    detailEnableHost = CreateFrame("Frame", nil, detailPane)
    detailEnableHost:SetSize(154, 28)
    detailEnableHost:SetPoint("TOPRIGHT", detailPane, "TOPRIGHT", -14, -9)
    detailEnableHost:Hide()

    detailOutputHost = CreateFrame("Frame", nil, detailPane, "BackdropTemplate")
    detailOutputHost:SetSize(330, 34)
    detailOutputHost:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -12, 9)
    EXUI:SetControlSurface(detailOutputHost, 4, GC.subcard, GC.subcardBorder)
    detailOutputHost:Hide()

    detailIcon = EXUI:CreateRoundedImage(detailPane, 9)
    detailIcon:SetSize(46, 46)
    detailIcon:SetPoint("TOPLEFT", 14, -14)
    detailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detailIconBorder = CreateFrame("Frame", nil, detailPane, "BackdropTemplate")
    detailIconBorder:SetSize(48, 48)
    detailIconBorder:SetPoint("TOPLEFT", detailIcon, "TOPLEFT", -1, 1)
    EXUI:ClearControlSurface(detailIconBorder)

    detailTitle = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontNormalLarge")
    detailTitle:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 8, -1)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetWordWrap(true)
    detailTitle:SetFont(ExwindTools.MAIN_FONT, GM.font.exboss.spellDetailTitle, "")
    detailTitle:SetTextColor(unpack(GC.text))

    detailMeta = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontHighlight")
    detailMeta:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -2)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetWordWrap(true)
    detailMeta:SetFont(ExwindTools.MAIN_FONT, GM.font.hint, "")
    detailMeta:SetTextColor(unpack(GC.textDim))
    detailMeta:Hide()

    local function CreateDetailIDChip(label, color)
        local chip = CreateFrame("Frame", nil, detailPane, "BackdropTemplate")
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

    detailBodyScroll = CreateFrame("ScrollFrame", nil, detailPane, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(detailBodyScroll)
    end
    DisableVerticalScroll(detailBodyScroll)
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

    detailDivider = EXUI:CreateVisualTexture(detailPane, EXBORDERFRAME)
    detailDivider:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 14, 10)
    detailDivider:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -14, 10)
    detailDivider:SetHeight(1)
    detailDivider:SetColorTexture(unpack(GC.headerDivider))
    detailDivider:Hide()

    detailInfo = EXUI:CreateVisualFontString(detailPane, EXFONTFRAME, "GameFontHighlightSmall")
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

    settingsVoiceDisabledNote = EXUI:CreateVisualFontString(settingsPane, EXFONTFRAME, "GameFontNormalSmall")
    settingsVoiceDisabledNote:SetPoint("TOPLEFT", settingsPane, "TOPLEFT", 0, -2)
    settingsVoiceDisabledNote:SetPoint("RIGHT", settingsPane, "RIGHT", -28, 0)
    settingsVoiceDisabledNote:SetJustifyH("LEFT")
    settingsVoiceDisabledNote:SetWordWrap(true)
    settingsVoiceDisabledNote:SetTextColor(1, 0.82, 0.25)
    settingsVoiceDisabledNote:Hide()

    settingsScrollFrame = CreateFrame("ScrollFrame", nil, settingsPane, "ScrollFrameTemplate")
    settingsScrollFrame:SetPoint("TOPLEFT", 0, -28)
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
    if Page._settingsCardSession then Page._settingsCardSession:Relayout() end
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
            if info.key == "tr1ValueTest" or info.key == "tr2ValueTest" then
                -- 用户 2026-10-05 第五批第 66 项：这两个播放按钮原来直接调
                -- PlayVoicePreview，没有经过公共试听驱动，所以播放中没有竖线跳动。
                -- 改走与下面 targetAlertStartValueTest 相同的 RunSoundPreview：
                -- 播放逻辑、声音来源与返回值不变，Start/Stop 由 Core 按返回的
                -- 声音句柄接管（内部即 AcquirePlayingIndicator，手册 §2.5.7）。
                local prefix = (info.key == "tr1ValueTest") and "tr1" or "tr2"
                EXUI:RunSoundPreview(_G.ExwindGrid:FindMountedWidget(settingsScrollChild, info.key), function()
                    return PlayVoicePreview(db[prefix .. "Source"], db[prefix .. "Label"],
                        db[prefix .. "LSM"], db[prefix .. "Path"])
                end)
            elseif info.key == "targetAlertStartValueTest" then
                EXUI:RunSoundPreview(_G.ExwindGrid:FindMountedWidget(settingsScrollChild, info.key), function()
                    return PlayVoicePreview("lsm", "", db.targetAlertStartLSM, "")
                end)
            elseif info.key == "voiceSequencePreview" then
                StartTrashVoiceSequencePreview()
            end
        end)
end

-- The Core controller intentionally receives no field route.  Persist every
-- current draft field as the editor's single reapply transaction.
local function RefreshActiveSurfaces()
    if Page._visible ~= true then return end
    CancelTrashVoiceSequencePreview()
    local fields = {
        "enabled", "showBunBar", "showTimerBar", "showNameplate",
        "eventColorEnabled", "eventColorMode", "eventColor", "centralEnabled",
        "centralLead", "centralText", "countdownEnabled",
        -- countdownLead 没有自己的 Grid 控件，它由 PersistEditorToSelectedSpell 的互写
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

-- [释放边界] 必须保留 ActivePage 清理、Grid 控件归还、draft/context 作废、三个 pane/屏幕预览停止；卡壳不得重复释放。
function Page:Hide()
    Page._visible = false
    -- 作废序列并收回播放态必须在释放卡片会话之前：之后拿不到预览按钮。
    CancelTrashVoiceSequencePreview()
    ReleaseTrashSettingsCardSession()
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
