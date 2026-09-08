---@diagnostic disable: undefined-global, undefined-field

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.Trash.Runtime = ExBoss.Trash.Runtime or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Runtime or ExBoss.Trash.Runtime.ObservationTest or {}
ExBoss.TrashCD.Runtime = Mod
ExBoss.Trash.Runtime.ObservationTest = Mod

local ET = _G.ExwindTools
local TrashData = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local TrashCore = ExBoss.TrashCD and ExBoss.TrashCD.Core or nil
local Inference = ExBoss.TrashCD and ExBoss.TrashCD.Inference or nil
local Observation = ExBoss.TrashCD and ExBoss.TrashCD.Observation or nil
local Calibration = ExBoss.TrashCD and ExBoss.TrashCD.Calibration or nil
local Output = ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
local NameplateMarker = ExBoss.TrashCD and ExBoss.TrashCD.NameplateMarker or nil
local Store = ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
local TrashCache = ExBoss.TrashCD and ExBoss.TrashCD.TrashCache or nil
local State = ExBoss.TrashCD and ExBoss.TrashCD.State or nil
local Population = ExBoss.TrashCD and ExBoss.TrashCD.Population or nil
local CoPresence = ExBoss.TrashCD and ExBoss.TrashCD.CoPresence or nil
local KingsRestWaves = ExBoss.TrashCD and ExBoss.TrashCD.KingsRestWaves or nil
local HealthThreshold = ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.HealthThreshold or nil

local MAX_NAMEPLATES = 40
local SNAPSHOT_RETRY_DELAY = 0.12
local MARKER_REFRESH_DELAY = 1.0
local COPRESENCE_TENTATIVE_DELAY = 0.50

local function IsNameplateInCombat(unit, refresh)
    if State and type(State.IsUnitInCombat) == "function" then
        return State.IsUnitInCombat(unit, refresh) == true
    end
    return false
end

local _encounterMapNameByInstanceID
local _encounterMapNameByMapID
local _trashMapIDByNameKey

Mod._running = Mod._running == true
Mod._uiEnabled = Mod._uiEnabled == true
Mod._unitFirstSeenAt = Mod._unitFirstSeenAt or {}
Mod._observedByUnit = Mod._observedByUnit or {}
Mod._runtimeByUnit = Mod._runtimeByUnit or {}
Mod._pendingUnitRefresh = Mod._pendingUnitRefresh or {}
Mod._pendingMarkerRefresh = Mod._pendingMarkerRefresh or {}
Mod._debug = Mod._debug == true
Mod._debugLastSignatureByUnit = Mod._debugLastSignatureByUnit or {}
Mod._debugBuffer = Mod._debugBuffer or {}
Mod._debugBufferMax = tonumber(Mod._debugBufferMax) or 800
Mod._debugCopyFrame = Mod._debugCopyFrame

local CancelRuntimeScriptEvents

local function WipeTable(t)
    if type(t) ~= "table" then
        return {}
    end
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local function NormalizeNameKey(name)
    if TrashData and type(TrashData.NormalizeNameKey) == "function" then
        return TrashData.NormalizeNameKey(name)
    end
    local s = tostring(name or "")
    s = s:lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

local function NormalizeNameplateUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local index = unit:match("^nameplate(%d+)$")
    if not index then
        return nil
    end
    return "nameplate" .. index
end

local function AppendBufferLine(tag, msg, echoToChat)
    local buffer = type(Mod._debugBuffer) == "table" and Mod._debugBuffer or {}
    Mod._debugBuffer = buffer
    local limit = math.max(50, math.floor(tonumber(Mod._debugBufferMax) or 400))
    local line = string.format("[%s] %s", tostring(tag or "Debug"), tostring(msg or ""))
    buffer[#buffer + 1] = line
    while #buffer > limit do
        table.remove(buffer, 1)
    end
    if echoToChat == true and DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
end

local function DebugPrint(msg)
    if Mod._debug ~= true then
        return
    end
    -- 详细诊断只保存在缓冲区。战斗中的仇恨/刷新事件会非常频繁，
    -- 不能把内部过程逐条输出到聊天框。
    AppendBufferLine("TrashCD", msg, false)
end

local function DebugChat(msg)
    if Mod._debug ~= true then
        return
    end
    AppendBufferLine("TrashCD", msg, true)
end

local function CacheDebug(msg)
    if Mod._debug == true then
        AppendBufferLine("TrashCD Cache", msg, false)
    end
end

local function IsDeathDebugEnabled()
    return Mod._debug == true
end

function Mod.ClearDebugBuffer()
    Mod._debugBuffer = {}
    Mod._debugLastSignatureByUnit = {}
end

function Mod.GetDebugBufferText()
    local buffer = type(Mod._debugBuffer) == "table" and Mod._debugBuffer or nil
    if not buffer or #buffer == 0 then
        return ""
    end
    return table.concat(buffer, "\n")
end

local function EnsureDebugCopyFrame()
    if type(Mod._debugCopyFrame) == "table" then
        return Mod._debugCopyFrame
    end

    local frame = CreateFrame("Frame", "EXBossTrashDebugCopyFrame", UIParent, "BackdropTemplate")
    frame:SetSize(900, 620)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("ExBoss Trash Debug Copy")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -46)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 18)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 24, self:GetVerticalScrollRange())))
    end)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(820)
    editBox:SetHeight(560)
    editBox:SetPoint("TOPLEFT", 0, 0)
    editBox:SetTextInsets(8, 8, 8, 8)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetMaxLetters(0)
    editBox:EnableMouseWheel(true)
    editBox:HookScript("OnMouseWheel", function(_, delta)
        local onMouseWheel = scrollFrame:GetScript("OnMouseWheel")
        if onMouseWheel then
            onMouseWheel(scrollFrame, delta)
        end
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        local textRegion = self.GetFontString and self:GetFontString() or nil
        local textHeight = textRegion and textRegion.GetStringHeight and textRegion:GetStringHeight() or 0
        self:SetHeight(math.max(560, textHeight + 24))
    end)
    scrollFrame:SetScrollChild(editBox)

    frame.editBox = editBox
    Mod._debugCopyFrame = frame
    return frame
end

function Mod.ShowDebugCopy()
    local frame = EnsureDebugCopyFrame()
    local text = Mod.GetDebugBufferText()
    if text == "" then
        text = "No trash debug logs captured."
    end
    frame:Show()
    frame.editBox:SetText(text)
    frame.editBox:SetCursorPosition(0)
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
end

function Mod.AppendExternalDebug(tag, msg, echoToChat)
    if Mod._debug == true then
        AppendBufferLine(tag or "External", msg, echoToChat == true)
    end
end

function Mod.SetDebug(...)
    local enabled = select(1, ...)
    if type(enabled) == "table" then
        enabled = select(2, ...)
    end
    Mod._debug = enabled == true
    if Mod._debug then
        Mod.ClearDebugBuffer()
        DebugChat("debug=on（输出身份／战斗状态／缓存／名额生命周期；关闭：/run ExBoss.TrashCD.Runtime:SetDebug(false)）")
    else
        AppendBufferLine("TrashCD", "debug=off", true)
        return
    end
end

function Mod.IsDebug()
    return Mod._debug == true
end

local function FormatBool(value)
    return value == true and "true" or "false"
end

local function GetStateValue(key)
    local state = ET and ET.State or nil
    return type(state) == "table" and state[key] or nil
end

local function BuildCandidateSummary(candidates, maxCount)
    if type(candidates) ~= "table" or #candidates == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, math.min(maxCount or 5, #candidates) do
        local c = candidates[i]
        parts[#parts + 1] = string.format("%s(%s)", tostring(c and c.name or "?"), tostring(c and c.npcID or "?"))
    end
    return table.concat(parts, ", ")
end

local function BuildLayer2DecisionSummary(debug, maxCount)
    if type(debug) ~= "table" or type(debug.decisions) ~= "table" or #debug.decisions == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, math.min(maxCount or 6, #debug.decisions) do
        local row = debug.decisions[i]
        parts[#parts + 1] = string.format(
            "%s(%s)=%s[%s]",
            tostring(row and row.name or "?"),
            tostring(row and row.npcID or "?"),
            row and row.keep == true and "keep" or "drop",
            tostring(row and row.reason or "?")
        )
    end
    return table.concat(parts, ", ")
end

local function BuildCandidateDebugSummary(candidates, maxCount)
    if type(candidates) ~= "table" or #candidates == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, math.min(maxCount or 6, #candidates) do
        local candidate = candidates[i]
        local row = type(candidate) == "table" and candidate.row or nil
        local companions = type(candidate) == "table" and candidate.coPresenceNPCIDs or nil
        companions = type(companions) == "table" and companions
            or type(row) == "table" and row.coPresenceNPCIDs or nil
        local companionIDs = {}
        for npcID in pairs(type(companions) == "table" and companions or {}) do
            local id = tonumber(npcID)
            if id then companionIDs[#companionIDs + 1] = id end
        end
        table.sort(companionIDs)
        parts[#parts + 1] = string.format(
            "%s(%s)[score=%s/%s,lt=%s,fam=%s,co=%s]",
            tostring(candidate and candidate.name or "?"),
            tostring(candidate and candidate.npcID or "?"),
            tostring(candidate and candidate.score or "?"),
            tostring(candidate and candidate.strength or "?"),
            tostring(type(row) == "table" and row.isLieutenant or "nil"),
            tostring(type(row) == "table" and row.hasCreatureFamily or "nil"),
            #companionIDs > 0 and table.concat(companionIDs, "/") or "-"
        )
    end
    return table.concat(parts, ", ")
end

local function BuildCandidateIDSignature(candidates)
    if type(candidates) ~= "table" or #candidates == 0 then
        return "-"
    end
    local parts = {}
    for i = 1, #candidates do
        parts[#parts + 1] = tostring(candidates[i] and candidates[i].npcID or "?")
    end
    return table.concat(parts, "/")
end

local function BuildCoPresenceSignature(debug)
    if type(debug) ~= "table" then
        return "-"
    end
    local locked = type(debug.lockedNPCIDs) == "table" and table.concat(debug.lockedNPCIDs, "/") or "-"
    return table.concat({
        tostring(debug.reason or "?"),
        tostring(debug.inputCount or "?"),
        tostring(debug.outputCount or "?"),
        locked,
    }, "/")
end

local function BuildMatchDebugSignature(unit, context)
    local obs = type(context.obs) == "table" and context.obs or {}
    local result = type(context.result) == "table" and context.result or {}
    local accepted = type(context.accepted) == "table" and context.accepted or nil
    local runtime = type(context.runtime) == "table" and context.runtime or nil
    return table.concat({
        tostring(unit or "?"),
        tostring(obs.level), tostring(obs.power), tostring(obs.unitClassification),
        tostring(obs.isLieutenant), tostring(obs.hasCreatureFamily),
        tostring(obs.sawCastStart == true), tostring(obs.sawChannelStart == true), tostring(obs.sawInterrupted == true),
        tostring(obs.inCombat == true),
        BuildCandidateIDSignature(result.layer1Candidates),
        BuildCandidateIDSignature(result.candidates),
        tostring(type(result.resolved) == "table" and result.resolved.npcID or "nil"),
        tostring(accepted and accepted.npcID or "nil"),
        tostring(runtime and runtime.identityLockedNPCID or "nil"),
        runtime and tostring(runtime.activeCastTargetHostile) or "nil",
        tostring(context.acceptedSource or "nil"),
        tostring(GetStateValue("DungeonBossProgressIndex") or "nil"),
        BuildCoPresenceSignature(result.coPresenceDebug),
    }, "\31")
end

local function PrintMatchDebug(unit, context)
    if not Mod._debug or type(context) ~= "table" then
        return
    end
    local signature = BuildMatchDebugSignature(unit, context)
    if Mod._debugLastSignatureByUnit[unit] == signature then
        return
    end
    Mod._debugLastSignatureByUnit[unit] = signature

    local obs = type(context.obs) == "table" and context.obs or {}
    local result = type(context.result) == "table" and context.result or {}
    local debug = context.layer1Debug or {}
    local layer2Debug = context.layer2Debug or {}
    local resolved = type(result.resolved) == "table" and result.resolved or nil
    local layer1 = type(result.layer1Candidates) == "table" and #result.layer1Candidates or 0
    local layer2 = type(result.candidates) == "table" and #result.candidates or 0
    local inferredText = resolved and
        string.format("%s(%s)", tostring(resolved.name or "?"), tostring(resolved.npcID or "?")) or "none"
    local accepted = type(context.accepted) == "table" and context.accepted or nil
    local acceptedText = accepted and
        string.format("%s(%s)", tostring(accepted.name or "?"), tostring(accepted.npcID or "?")) or "none"
    local coPresenceDebug = type(result.coPresenceDebug) == "table" and result.coPresenceDebug or nil
    local bossProgressIndex = tonumber(GetStateValue("DungeonBossProgressIndex")) or 0
    local bossPlacementText = bossProgressIndex > 0
        and string.format("第%s号BOSS前", tostring(bossProgressIndex))
        or "未取得"

    -- 聊天框只保留一条、且仅在身份/候选/观测状态变化时输出。
    -- 这样开启调试后可以直接看，而不会被每次仇恨刷新淹没。
    DebugChat(string.format(
        "match unit=%s reason=%s ExcelBoss前=%s obs=[L%s P%s lt=%s fam=%s cast=%s ch=%s int=%s combat=%s] L1=%s L2=%s inferred=%s accepted=%s source=%s lock=%s co=%s targetHostile=%s",
        tostring(unit or "?"),
        tostring(context.reason or "?"),
        bossPlacementText,
        tostring(obs.level or "nil"),
        tostring(obs.power or "nil"),
        tostring(obs.isLieutenant),
        tostring(obs.hasCreatureFamily),
        FormatBool(obs.sawCastStart == true),
        FormatBool(obs.sawChannelStart == true),
        FormatBool(obs.sawInterrupted == true),
        FormatBool(obs.inCombat == true),
        BuildCandidateSummary(result.layer1Candidates, 3),
        BuildCandidateSummary(result.candidates, 3),
        inferredText,
        acceptedText,
        tostring(context.acceptedSource or "none"),
        tostring(type(context.runtime) == "table" and context.runtime.identityLockedNPCID or "none"),
        tostring(coPresenceDebug and coPresenceDebug.applied == true or false),
        type(context.runtime) == "table" and tostring(context.runtime.activeCastTargetHostile) or "nil"
    ))

    DebugPrint(string.format(
        "unit=%s reason=%s inst=%s map=%s playerMap=%s zone=%s dungeon=%s stage=%s mplus=%s inferred=%s",
        tostring(unit or "?"),
        tostring(context.reason or "?"),
        tostring(context.instanceID or "nil"),
        tostring(context.trashMapID or "nil"),
        tostring(GetStateValue("MapID") or "nil"),
        tostring(GetStateValue("ZoneText") or "nil"),
        tostring(context.dungeonKey or ""),
        tostring(GetStateValue("DungeonBossProgressIndex") or "nil"),
        FormatBool(GetStateValue("InMythicPlus") == true),
        inferredText
    ))
    DebugPrint(string.format(
        "obs level=%s power=%s lieutenant=%s creatureFamily=%s cast=%s channel=%s interrupt=%s combat=%s",
        tostring(obs.level or "nil"),
        tostring(obs.power or "nil"),
        tostring(obs.isLieutenant),
        tostring(obs.hasCreatureFamily),
        FormatBool(obs.sawCastStart == true),
        FormatBool(obs.sawChannelStart == true),
        FormatBool(obs.sawInterrupted == true),
        FormatBool(obs.inCombat == true)
    ))
    DebugPrint(string.format(
        "rows total=%s dungeon=%s tested=%s matched=%s L1=%s L2=%s normalizedDungeon=%s layerZone=%s",
        tostring(debug.totalRows or "nil"),
        tostring(debug.dungeonRows or "nil"),
        tostring(debug.testedRows or "nil"),
        tostring(debug.matchedRows or "nil"),
        tostring(layer1),
        tostring(layer2),
        tostring(debug.normalizedDungeonKey or ""),
        tostring(debug.zoneText or "nil")
    ))
    if debug.academyZoneExpectedNPCID ~= nil or tostring(context.trashMapID or "") == "2526" then
        DebugPrint(string.format(
            "academy-forces eligible=%s expectedNPC=%s reason=%s mplusForces=%s matchedAfterForces=%s rules=%s",
            tostring(debug.academyZoneRouteEligible or false),
            tostring(debug.academyZoneExpectedNPCID or "nil"),
            tostring(debug.academyZoneReason or "nil"),
            tostring(debug.mythicPlusForcesPercent or GetStateValue("MythicPlusForcesPercent") or "nil"),
            tostring(debug.matchedRows or "nil"),
            tostring(debug.academyZoneRules or "nil")
        ))
    end

    if type(result.layer1Candidates) == "table" and #result.layer1Candidates > 0 then
        DebugPrint("L1候选: " .. BuildCandidateSummary(result.layer1Candidates, 5))
        DebugPrint("L1特征: " .. BuildCandidateDebugSummary(result.layer1Candidates, 6))
    end

    if type(result.candidates) == "table" and #result.candidates > 0 then
        DebugPrint("L2候选: " .. BuildCandidateSummary(result.candidates, 5))
        DebugPrint("L2特征: " .. BuildCandidateDebugSummary(result.candidates, 6))
    end

    local kingsRestWave = KingsRestWaves and type(KingsRestWaves.GetUnitWaveState) == "function"
        and KingsRestWaves.GetUnitWaveState(unit) or nil
    if type(kingsRestWave) == "table" then
        DebugPrint(string.format(
            "kings-rest batch ready=%s members=%s anchor=%s expected91=%s actual91=%s extra91=%s",
            tostring(kingsRestWave.ready == true),
            tostring(kingsRestWave.memberCount or "nil"),
            tostring(kingsRestWave.waveAnchorNPCID or "nil"),
            tostring(kingsRestWave.expectedLevel91Count or "nil"),
            tostring(kingsRestWave.actualLevel91Count or "nil"),
            tostring(kingsRestWave.hasExtraLevel91 == true)
        ))
    end

    if coPresenceDebug then
        local parts = {}
        for i = 1, #(coPresenceDebug.candidates or {}) do
            local row = coPresenceDebug.candidates[i]
            local required = type(row.requiredNPCIDs) == "table" and table.concat(row.requiredNPCIDs, "/") or "-"
            parts[#parts + 1] = string.format("%s:req=%s:match=%s", tostring(row.npcID or "?"), required,
                tostring(row.matched == true))
        end
        DebugPrint(string.format(
            "coPresence map=%s reason=%s locked=%s input=%s output=%s applied=%s candidates=%s",
            tostring(coPresenceDebug.mapID or "nil"),
            tostring(coPresenceDebug.reason or "?"),
            type(coPresenceDebug.lockedNPCIDs) == "table" and table.concat(coPresenceDebug.lockedNPCIDs, "/") or "-",
            tostring(coPresenceDebug.inputCount or "nil"),
            tostring(coPresenceDebug.outputCount or "nil"),
            tostring(coPresenceDebug.applied == true),
            #parts > 0 and table.concat(parts, ",") or "-"
        ))
    end

    if context.acceptedSource or context.identityJustLocked ~= nil then
        DebugPrint(string.format(
            "identity accepted=%s source=%s lockEligible=%s justLocked=%s locked=%s",
            type(context.accepted) == "table" and tostring(context.accepted.npcID or "nil") or "nil",
            tostring(context.acceptedSource or "nil"),
            tostring(result.identityLockEligible == true),
            tostring(context.identityJustLocked == true),
            tostring(type(context.runtime) == "table" and context.runtime.identityLockedNPCID or "nil")
        ))
    end

    if type(layer2Debug) == "table" and type(layer2Debug.decisions) == "table" and #layer2Debug.decisions > 0 then
        DebugPrint(string.format(
            "L2过滤 kind=%s dur=%s narrowed=%s returnedOriginal=%s final=%s kept=%s",
            tostring(layer2Debug.behavior and layer2Debug.behavior.kind or "nil"),
            tostring(layer2Debug.behavior and layer2Debug.behavior.observedDuration or "nil"),
            FormatBool(layer2Debug.fingerprintNarrowed == true),
            FormatBool(layer2Debug.returnedOriginal == true),
            tostring(layer2Debug.finalCount or "nil"),
            BuildCandidateSummary(layer2Debug.kept, 5)
        ))
        DebugPrint("L2细节: " .. BuildLayer2DecisionSummary(layer2Debug, 6))
    end

    local samples = type(debug.samples) == "table" and debug.samples or {}
    for i = 1, math.min(5, #samples) do
        local s = samples[i]
        DebugPrint(string.format(
            "fail %s(%s) %s db=[%s/%s]",
            tostring(s.name or "?"),
            tostring(s.npcID or "?"),
            tostring(s.reason or "?"),
            tostring(s.level or "nil"),
            tostring(s.power or "nil")
        ))
    end
end

local function GetMobTraits()
    if TrashData and type(TrashData.GetTrashMobTraitsRoot) == "function" then
        return TrashData.GetTrashMobTraitsRoot()
    end
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashMobTraitsRoot) == "function" then
        local ok, data = pcall(api.GetTrashMobTraitsRoot)
        if ok and type(data) == "table" then
            return data
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_MOB_TRAITS")
    return type(raw) == "table" and raw or { rows = {} }
end

local function GetTrashCDDataRoot()
    if TrashData and type(TrashData.GetTrashCDDataRoot) == "function" then
        return TrashData.GetTrashCDDataRoot()
    end
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashCDDataRoot) == "function" then
        local ok, data = pcall(api.GetTrashCDDataRoot)
        if ok and type(data) == "table" then
            return data
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_CD_DATA")
    return type(raw) == "table" and raw or {}
end

local function BuildTrashMapIDByNameKey()
    local out = {}
    local root = GetTrashCDDataRoot()
    for key, row in pairs(root) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = tostring(row.mapName or "")
            local nameKey = NormalizeNameKey(mapName)
            if mapID and mapID > 0 and nameKey ~= "" then
                out[nameKey] = mapID
            end
        end
    end
    return out
end

local function GetTrashMapIDByNameKey()
    if not _trashMapIDByNameKey then
        _trashMapIDByNameKey = BuildTrashMapIDByNameKey()
    end
    return _trashMapIDByNameKey
end

local function BuildEncounterMapNameByInstanceID()
    local out = {}
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetEncounterDataRoot) ~= "function" then
        return out
    end

    local ok, data = pcall(api.GetEncounterDataRoot)
    if not ok or type(data) ~= "table" then
        return out
    end

    local maps = type(data.maps) == "table" and data.maps or data
    if type(maps) ~= "table" then
        return out
    end

    for key, row in pairs(maps) do
        if type(row) == "table" then
            local instanceID = tonumber(row.instanceID) or tonumber(row.instanceId) or tonumber(row.mapID) or
            tonumber(key)
            local mapName = tostring(row.mapName or row.name or "")
            if instanceID and instanceID > 0 and mapName ~= "" then
                out[instanceID] = mapName
            end
        end
    end

    return out
end

local function BuildEncounterMapNameByMapID()
    local out = {}
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetEncounterDataRoot) ~= "function" then
        return out
    end

    local ok, data = pcall(api.GetEncounterDataRoot)
    if not ok or type(data) ~= "table" then
        return out
    end

    local maps = type(data.maps) == "table" and data.maps or data
    if type(maps) ~= "table" then
        return out
    end

    for key, row in pairs(maps) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = tostring(row.mapName or row.name or "")
            if mapID and mapID > 0 and mapName ~= "" then
                out[mapID] = mapName
            end
        end
    end

    return out
end

local function GetEncounterMapNameByInstanceID()
    if not _encounterMapNameByInstanceID then
        _encounterMapNameByInstanceID = BuildEncounterMapNameByInstanceID()
    end
    return _encounterMapNameByInstanceID
end

local function GetEncounterMapNameByMapID()
    if not _encounterMapNameByMapID then
        _encounterMapNameByMapID = BuildEncounterMapNameByMapID()
    end
    return _encounterMapNameByMapID
end

local function GetCurrentInstanceContext()
    if TrashData and type(TrashData.GetCurrentInstanceContext) == "function" then
        return TrashData.GetCurrentInstanceContext()
    end
    local inInstance, instanceType = IsInInstance()
    if inInstance ~= true then
        return nil, nil, instanceType
    end

    local state = ET and ET.State or nil
    local instanceID = tonumber(state and state.InstanceID) or tonumber((select(8, GetInstanceInfo()))) or 0
    local mapID = tonumber(state and state.MapID) or 0
    local instanceName = tostring((select(1, GetInstanceInfo())) or "")
    local mapName = ""

    if mapID > 0 then
        mapName = tostring(GetEncounterMapNameByMapID()[mapID] or "")
    end
    if instanceID > 0 and mapName == "" then
        mapName = tostring(GetEncounterMapNameByInstanceID()[instanceID] or "")
    end
    if mapName == "" then
        mapName = instanceName
    end

    return instanceID > 0 and instanceID or nil, mapName, instanceType
end

local function IsHostileNameplate(unit)
    return UnitExists(unit)
        and UnitCanAttack("player", unit)
        and not UnitIsDead(unit)
end

local function IsInInstanceForTest()
    local inInstance = IsInInstance()
    return inInstance == true
end

local function ShouldRunRuntime()
    if TrashCore and type(TrashCore.ShouldRunMonitor) == "function" then
        return TrashCore.ShouldRunMonitor()
    end
    return Mod._uiEnabled == true and IsInInstanceForTest()
end

local function GetCurrentTrashMapID(dungeonKey)
    if Calibration and type(Calibration.GetCurrentTrashMapID) == "function" then
        return Calibration.GetCurrentTrashMapID(dungeonKey)
    end
    local byNameKey = GetTrashMapIDByNameKey()
    return tonumber(byNameKey[dungeonKey])
end

local function GetCurrentTrashContext()
    local instanceID, dungeonName = GetCurrentInstanceContext()
    local dungeonKey = NormalizeNameKey(dungeonName)
    return instanceID, dungeonName, dungeonKey, GetCurrentTrashMapID(dungeonKey)
end

local function BuildNameplateMarkerText(unit, resolved, runtime)
    local npcText = "???"
    if type(resolved) == "table" and resolved.npcID then
        npcText = tostring(resolved.npcID)
    end
    local unitText = tostring(unit or "?")
    local inCombat = false
    if type(runtime) == "table" then
        inCombat = runtime.engagedAt ~= nil
            or runtime.activeCastStartAt ~= nil
            or runtime.sawCastStart == true
            or runtime.sawChannelStart == true
            or runtime.pendingSucceeded == true
            or runtime.pendingInterrupted == true
    end
    if not inCombat and type(unit) == "string" then
        inCombat = IsNameplateInCombat(unit)
    end
    local combatText = inCombat and "|cff00ff00是|r" or "|cffff3030否|r"
    return string.format("%s\n%s 战斗:%s", npcText, unitText, combatText)
end

local function GetScheduler()
    return ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
end

local function BuildNameplateTimerRows(runtime)
    local scheduler = GetScheduler()
    if not (scheduler and type(scheduler.GetTrashNameplateTimers) == "function") then
        return {}
    end
    local rows = scheduler:GetTrashNameplateTimers(runtime, GetTime())
    if ExBoss and ExBoss.Debug and ExBoss.Debug.CastBar and ExBoss.Debug.CastBar.enabled == true then
        CacheDebug(string.format(
            "marker-rows runtime=%s matchedNPC=%s rows=%d",
            tostring(runtime),
            tostring(runtime and runtime.matchedNPCID or "nil"),
            #rows
        ))
    end
    return rows
end

local function GetRuntimeObs(unit)
    return Observation and Observation.GetRuntimeObs and Observation.GetRuntimeObs(Mod, unit) or nil
end

function Mod.NormalizeNameplateUnit(unit)
    return NormalizeNameplateUnit(unit)
end

function Mod.GetRuntimeByUnit(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    return GetRuntimeObs(unit)
end

local function TrackNameplate(unit)
    if State and type(State.OnNameplateAdded) == "function" then
        State.OnNameplateAdded(unit)
    end
    if KingsRestWaves and type(KingsRestWaves.OnNameplateAdded) == "function" then
        KingsRestWaves.OnNameplateAdded(unit)
    end
    if TrashCache and type(TrashCache.OnNameplateAdded) == "function" then
        TrashCache.OnNameplateAdded(unit)
    end
    if Observation and type(Observation.TrackNameplate) == "function" then
        return Observation.TrackNameplate(Mod, unit, IsHostileNameplate)
    end
end

local function SyncUnitCDTimers(unit, obs, candidate, mapID)
    local runtime = GetRuntimeObs(unit)
    local candidateNPCID = tonumber(type(candidate) == "table" and candidate.npcID or nil)
    if HealthThreshold then
        if obs and candidateNPCID and mapID and type(HealthThreshold.ActivateTrashUnit) == "function" then
            HealthThreshold:ActivateTrashUnit(unit, mapID, candidateNPCID)
        elseif type(HealthThreshold.DeactivateTrashUnit) == "function" then
            HealthThreshold:DeactivateTrashUnit(unit)
        end
    end
    if Calibration and type(Calibration.SyncUnitCDTimers) == "function" then
        return Calibration.SyncUnitCDTimers(runtime, obs, candidate, mapID)
    end
end

local function ClearRuntimeIdentityLock(runtime)
    if type(runtime) ~= "table" then
        return
    end
    if CoPresence and type(CoPresence.UnregisterRuntime) == "function" then
        CoPresence.UnregisterRuntime(runtime)
    end
    runtime.identityLockedNPCID = nil
    runtime.identityLockedMapID = nil
    runtime.identityLockedAt = nil
    runtime.identityLockSource = nil
    runtime.identityLockedCandidate = nil
    runtime.priorityPreviewVoiceNPCID = nil
    runtime.priorityPreviewVoiceMapID = nil
    runtime.priorityPreviewVoiceSource = nil
end

-- 优先级候选只可在 Excel 白名单技能上临时授权读条语音；它不是身份锁，
-- 不能参与 Population、同场证据、缓存或任何其他身份业务。
local function ClearRuntimePriorityPreviewVoice(runtime)
    if type(runtime) ~= "table" then
        return
    end
    runtime.priorityPreviewVoiceNPCID = nil
    runtime.priorityPreviewVoiceMapID = nil
    runtime.priorityPreviewVoiceSource = nil
end

local function SyncRuntimePriorityPreviewVoice(runtime, candidate, resolutionSource, mapID)
    if type(runtime) ~= "table" then
        return
    end
    local npcID = tonumber(type(candidate) == "table" and candidate.npcID or nil)
    local source = tostring(resolutionSource or "")
    local isPreviewSource = source == "priority" or source == "candidate-preview"
    if tonumber(runtime.identityLockedNPCID) then
        ClearRuntimePriorityPreviewVoice(runtime)
        return
    end

    if isPreviewSource and npcID and tonumber(mapID) then
        runtime.priorityPreviewVoiceNPCID = npcID
        runtime.priorityPreviewVoiceMapID = tonumber(mapID)
        runtime.priorityPreviewVoiceSource = source
        return
    end

    -- 读条刚开始时，单帧快照可能暂时无法复现 L1/L2 候选；Calibration 会继续
    -- 保留同一预判候选的本地排程。此时不能先清掉语音授权，否则真实读条会被静音。
    -- 一旦候选实际变更、正式锁定或排程被重置，下面的匹配条件自然失效或被清除。
    if not npcID
        and tonumber(runtime.priorityPreviewVoiceNPCID) == tonumber(runtime.matchedNPCID)
        and tonumber(runtime.priorityPreviewVoiceMapID) == tonumber(runtime.matchedMapID) then
        return
    end

    ClearRuntimePriorityPreviewVoice(runtime)
end

-- Runtime 是唯一可接受身份结论的入口。
-- priority 只做预览；只有 L2 唯一结论才可把 nameplate 身份锁定。
local function AcceptRuntimeIdentity(runtime, result, mapID)
    if type(runtime) ~= "table" then
        return nil, nil, false
    end

    local lockedNPCID = tonumber(runtime.identityLockedNPCID)
    local lockedMapID = tonumber(runtime.identityLockedMapID)
    if lockedNPCID and lockedMapID and lockedMapID ~= tonumber(mapID) then
        ClearRuntimeIdentityLock(runtime)
        lockedNPCID = nil
    end

    local inferred = type(result) == "table" and result.resolved or nil
    local inferredNPCID = tonumber(type(inferred) == "table" and inferred.npcID or nil)
    local inferredSource = type(result) == "table" and result.resolutionSource or nil
    local inferredLockEligible = type(result) == "table" and result.identityLockEligible == true

    if lockedNPCID then
        -- 同一 nameplate 已锁后不可被一次新的推理翻转；若出现矛盾 L2，保留锁以便调试。
        if inferredLockEligible and inferredNPCID and inferredNPCID ~= lockedNPCID then
            local conflictSignature = tostring(lockedNPCID) .. ":" .. tostring(inferredNPCID)
            if runtime._debugLastIdentityConflict ~= conflictSignature then
                runtime._debugLastIdentityConflict = conflictSignature
                DebugPrint(string.format("identity-lock-conflict locked=%s layer2=%s", tostring(lockedNPCID), tostring(inferredNPCID)))
            end
        end
        local lockedCandidate = type(runtime.identityLockedCandidate) == "table" and runtime.identityLockedCandidate or nil
        if lockedCandidate and tonumber(lockedCandidate.npcID) == lockedNPCID then
            return lockedCandidate, "identity-lock", false
        end
        return {
            npcID = lockedNPCID,
            name = runtime.lastResolvedName,
        }, "identity-lock", false
    end

    if inferredNPCID and inferredLockEligible then
        runtime.identityLockedNPCID = inferredNPCID
        runtime.identityLockedMapID = tonumber(mapID)
        runtime.identityLockedAt = GetTime()
        runtime.identityLockSource = tostring(inferredSource or "layer2-evidence")
        runtime.identityLockedCandidate = inferred
        return inferred, "identity-lock", true
    end

    return inferred, inferredSource, false
end

local function UpdateUnitNameplate(unit, resolved, runtime)
    if not NameplateMarker then
        return
    end
    local runtimeSettings = Store and type(Store.GetRuntimeSettings) == "function" and Store.GetRuntimeSettings() or nil
    if type(NameplateMarker.SetUnitText) == "function" then
        NameplateMarker.SetUnitText(unit, BuildNameplateMarkerText(unit, resolved, runtime),
            type(resolved) == "table" and resolved.npcID ~= nil, runtimeSettings)
    end
    if type(NameplateMarker.SetUnitTimers) == "function" then
        local markerRows = {}
        local resolvedNPCID = tonumber(type(resolved) == "table" and resolved.npcID or nil)
        if resolvedNPCID and type(runtime) == "table" and tonumber(runtime.matchedNPCID) == resolvedNPCID then
            markerRows = BuildNameplateTimerRows(runtime)
        end
        NameplateMarker.SetUnitTimers(unit, markerRows, runtimeSettings)
        if #markerRows > 0 then
            Mod:ScheduleMarkerRefresh(unit)
        end
    end
end

local function UntrackNameplate(unit)
    Mod._debugLastSignatureByUnit[unit] = nil
    local runtime = GetRuntimeObs(unit)
    if CoPresence and type(CoPresence.UnregisterRuntime) == "function" then
        CoPresence.UnregisterRuntime(runtime)
    end
    local keepPending = false
    if State and type(State.OnNameplateRemoved) == "function" then
        State.OnNameplateRemoved(unit)
    end
    if KingsRestWaves and type(KingsRestWaves.OnNameplateRemoved) == "function" then
        KingsRestWaves.OnNameplateRemoved(unit)
    end
    if TrashCache and type(TrashCache.OnNameplateRemoved) == "function" then
        keepPending = TrashCache.OnNameplateRemoved(unit, runtime, CancelRuntimeScriptEvents) == true
    end
    if NameplateMarker and type(NameplateMarker.HideUnit) == "function" then
        NameplateMarker.HideUnit(unit)
    end
    if HealthThreshold and type(HealthThreshold.DeactivateTrashUnit) == "function" then
        HealthThreshold:DeactivateTrashUnit(unit)
    end
    if Observation and type(Observation.UntrackNameplate) == "function" then
        return Observation.UntrackNameplate(Mod, unit, keepPending and nil or CancelRuntimeScriptEvents)
    end
end

CancelRuntimeScriptEvents = function(runtime)
    if Output and type(Output.CancelRuntimeScriptEvents) == "function" then
        return Output.CancelRuntimeScriptEvents(runtime)
    end
end

function Mod:ScheduleUnitRefresh(unit, delay, reason, forceSnapshot)
    unit = NormalizeNameplateUnit(unit)
    if not unit or not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    delay = math.max(0.01, tonumber(delay) or SNAPSHOT_RETRY_DELAY)
    local key = unit .. ":" .. tostring(reason or "refresh")
    if self._pendingUnitRefresh[key] then
        return
    end
    self._pendingUnitRefresh[key] = true
    C_Timer.After(delay, function()
        self._pendingUnitRefresh[key] = nil
        if self._running == true then
            self:RefreshUnit(unit, reason or "delayed", forceSnapshot == true)
        end
    end)
end

if KingsRestWaves and type(KingsRestWaves.SetRefreshCallback) == "function" then
    KingsRestWaves.SetRefreshCallback(function(units, reason)
        if Mod._running ~= true or type(units) ~= "table" then
            return
        end
        for unit in pairs(units) do
            if IsHostileNameplate(unit) then
                Mod:ScheduleUnitRefresh(unit, 0.01, reason or "kings-rest-wave", true)
            end
        end
    end)
end

function Mod:ScheduleMarkerRefresh(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit or not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    if self._pendingMarkerRefresh[unit] then
        return
    end
    self._pendingMarkerRefresh[unit] = true
    C_Timer.After(MARKER_REFRESH_DELAY, function()
        self._pendingMarkerRefresh[unit] = nil
        if self._running == true then
            self:RefreshUnitMarker(unit)
        end
    end)
end

function Mod:RefreshUnitMarker(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit or not IsHostileNameplate(unit) then
        UntrackNameplate(unit)
        return
    end
    local runtime = GetRuntimeObs(unit)
    if not runtime or not runtime.matchedNPCID then
        if NameplateMarker and type(NameplateMarker.SetUnitTimers) == "function" then
            NameplateMarker.SetUnitTimers(unit, {})
        end
        return
    end
    local resolved = {
        npcID = tonumber(runtime.matchedNPCID),
        name = runtime.lastResolvedName,
    }
    UpdateUnitNameplate(unit, resolved, runtime)
end

function Mod:RefreshUnresolvedNameplatesForCoPresence(mapID, sourceUnit)
    if self._running ~= true or not tonumber(mapID) then
        return
    end
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if unit ~= sourceUnit and IsHostileNameplate(unit) then
            local runtime = GetRuntimeObs(unit)
            if type(runtime) == "table" and not tonumber(runtime.identityLockedNPCID) then
                self:ScheduleUnitRefresh(unit, 0.01, "co-presence-lock", true)
            end
        end
    end
end

function Mod:RefreshUnit(unit, reason, forceSnapshot, combatConfirmed)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    if not ShouldRunRuntime() then
        self:Stop()
        return
    end
    if not IsHostileNameplate(unit) then
        UntrackNameplate(unit)
        return
    end
    if not (Observation and type(Observation.CollectTrackedNameplate) == "function" and Inference and type(Inference.ResolveCandidates) == "function") then
        return
    end

    local instanceID, _dungeonName, dungeonKey, trashMapID = GetCurrentTrashContext()
    if not instanceID or dungeonKey == "" then
        if Mod._debug == true then
            PrintMatchDebug(unit, {
                reason = "no-trash-context",
                instanceID = instanceID,
                dungeonKey = dungeonKey,
                trashMapID = trashMapID,
            })
        end
        UntrackNameplate(unit)
        return
    end

    local obs = Observation.CollectTrackedNameplate(Mod, unit, IsHostileNameplate, CancelRuntimeScriptEvents,
        forceSnapshot == true, combatConfirmed == true)
    if not obs then
        UntrackNameplate(unit)
        return
    end
    if obs.pending == true then
        if Mod._debug == true then
            PrintMatchDebug(unit, {
                reason = "snapshot-pending",
                instanceID = instanceID,
                dungeonKey = dungeonKey,
                trashMapID = trashMapID,
                obs = obs,
            })
        end
        local runtimeSettings = Store and type(Store.GetRuntimeSettings) == "function" and Store.GetRuntimeSettings() or nil
        if NameplateMarker and type(NameplateMarker.SetUnitText) == "function" then
            NameplateMarker.SetUnitText(unit, BuildNameplateMarkerText(unit, nil, GetRuntimeObs(unit)), false,
                runtimeSettings)
        end
        if NameplateMarker and type(NameplateMarker.SetUnitTimers) == "function" then
            NameplateMarker.SetUnitTimers(unit, {}, runtimeSettings)
        end
        self:ScheduleUnitRefresh(unit, tonumber(obs.retryAfter) or SNAPSHOT_RETRY_DELAY, "snapshot", true)
        return
    end

    -- 只保存已取得的 L1 快照；不会额外调用游戏 API。
    if State and type(State.SyncL1Observation) == "function" then
        State.SyncL1Observation(unit, obs)
    end
    if KingsRestWaves and type(KingsRestWaves.OnL1Snapshot) == "function" then
        KingsRestWaves.OnL1Snapshot(unit, trashMapID)
    end

    local runtime = GetRuntimeObs(unit)
    if type(runtime) == "table" then
        runtime._debugUnit = unit
        runtime._debugTrace = Mod._debug == true
    end
    local result
    local resolved, resolutionSource, identityJustLocked
    -- identityLockedNPCID 的业务语义是同一 runtime 生命周期内不可再被推理翻转。
    -- 正常路径直接使用锁定候选；debug 模式仍跑完整推理以保留冲突诊断。
    if type(runtime) == "table" and tonumber(runtime.identityLockedNPCID) and Mod._debug ~= true then
        resolved, resolutionSource, identityJustLocked = AcceptRuntimeIdentity(runtime, nil, trashMapID)
    end
    if not resolved then
        local traits = GetMobTraits()
        local traitRows = type(traits.rows) == "table" and traits.rows or {}
        result = Inference.ResolveCandidates(obs, dungeonKey, traitRows, runtime, trashMapID, GetTime())
        resolved, resolutionSource, identityJustLocked = AcceptRuntimeIdentity(runtime, result, trashMapID)
    end
    if identityJustLocked == true and KingsRestWaves and type(KingsRestWaves.OnIdentityLocked) == "function" then
        KingsRestWaves.OnIdentityLocked(unit, resolved, trashMapID)
    end
    local isCoPresenceProvisional = false
    local tentativeSession = type(runtime) == "table" and tonumber(runtime._coPresenceTentativeSession) or nil
    if not resolved and obs.inCombat == true
        and runtime and not tonumber(runtime.identityLockedNPCID)
        and tentativeSession ~= nil
        and tonumber(runtime._coPresenceTentativeReadySession) == tentativeSession
        and CoPresence and type(CoPresence.GetTentativeFallback) == "function" then
        local tentative = CoPresence.GetTentativeFallback(result.candidates, runtime, trashMapID)
        if tentative then
            local previousProvisionalNPCID = tonumber(runtime._coPresenceProvisionalNPCID)
            resolved = tentative
            resolutionSource = "co-presence-timeout"
            isCoPresenceProvisional = true
            runtime._coPresenceProvisionalNPCID = tonumber(tentative.npcID)
            runtime._coPresenceProvisionalSource = resolutionSource
            if previousProvisionalNPCID ~= tonumber(tentative.npcID) then
                DebugChat(string.format("co-presence-provisional unit=%s npc=%s", tostring(unit),
                    tostring(tentative.npcID)))
            end
        end
    end
    if runtime and tonumber(runtime.identityLockedNPCID) then
        runtime._coPresenceProvisionalNPCID = nil
        runtime._coPresenceProvisionalSource = nil
    elseif runtime and resolved and not isCoPresenceProvisional then
        runtime._coPresenceProvisionalNPCID = nil
        runtime._coPresenceProvisionalSource = nil
    end
    if not resolved and obs.inCombat == true
        and runtime and not tonumber(runtime.identityLockedNPCID)
        and CoPresence and type(CoPresence.HasCompanionRequirement) == "function"
        and CoPresence.HasCompanionRequirement(result.candidates) then
        self:ScheduleCoPresenceTentativeFallback(unit, runtime)
    end
    local coPresenceJustRegistered = false
    if runtime and tonumber(runtime.identityLockedNPCID)
        and CoPresence and type(CoPresence.MarkRuntimeLocked) == "function" then
        coPresenceJustRegistered = CoPresence.MarkRuntimeLocked(runtime, trashMapID, runtime.identityLockedNPCID) == true
    end
    SyncRuntimePriorityPreviewVoice(runtime, resolved, resolutionSource, trashMapID)
    -- 预览候选不能占用 bossCounts 名额；只有已经上锁的真实身份才写 Population。
    if runtime and tonumber(runtime.identityLockedNPCID)
        and resolved and Population and type(Population.MarkResolved) == "function" then
        Population.MarkResolved(runtime, resolved, trashMapID, resolutionSource, obs.inCombat == true)
    end
    if Mod._debug == true then
        local Layer1 = ExBoss.TrashCD and ExBoss.TrashCD.Layer1Filter or nil
        local Layer2 = ExBoss.TrashCD and ExBoss.TrashCD.Layer2Filter or nil
        local layer1Debug = Layer1 and type(Layer1.GetLastDebug) == "function" and Layer1.GetLastDebug() or nil
        local layer2Debug = Layer2 and type(Layer2.GetLastDebug) == "function" and Layer2.GetLastDebug() or nil
        PrintMatchDebug(unit, {
            reason = reason,
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
            obs = obs,
            result = result,
            layer1Debug = layer1Debug,
            layer2Debug = layer2Debug,
            runtime = runtime,
            accepted = resolved,
            acceptedSource = resolutionSource,
            identityJustLocked = identityJustLocked,
        })
    end
    local resolvedNPCID = tonumber(type(resolved) == "table" and resolved.npcID or nil)
    local restored = false
    if resolvedNPCID and runtime and TrashCache and type(TrashCache.TryRestoreRuntime) == "function" then
        restored = TrashCache.TryRestoreRuntime(unit, runtime, resolved) == true
        if Mod._debug == true then
            CacheDebug(string.format(
                "refresh unit=%s reason=%s resolvedNPC=%s restored=%s combat=%s matchedNPC=%s",
                tostring(unit),
                tostring(reason or "?"),
                tostring(resolvedNPCID),
                tostring(restored),
                tostring(obs and obs.inCombat == true),
                tostring(runtime and runtime.matchedNPCID or "nil")
            ))
        end
    end
    local canSchedule = (obs.inCombat == true)
    local keepLockedRuntime = resolvedNPCID == nil
        and canSchedule == true
        and type(runtime) == "table"
        and tonumber(runtime.matchedNPCID) ~= nil
    if type(runtime) == "table" then
        runtime._debugUnit = unit
    end
    if resolvedNPCID and canSchedule then
        if runtime and resolved.name then
            runtime.lastResolvedName = resolved.name
        end
        SyncUnitCDTimers(unit, obs, resolved, trashMapID)
    elseif keepLockedRuntime then
        -- 单帧快照可能因为施法/引导状态变化而无法重新推理 NPC。
        -- 已锁定且仍在战斗中时保留 runtime，并继续同步旧 runtime，
        -- 否则 pendingSucceeded / pendingInterrupted 会卡到下一次事件才结算。
        local lockedMapID = tonumber(runtime and runtime.matchedMapID) or tonumber(trashMapID)
        local lockedResolved = {
            npcID = tonumber(runtime and runtime.matchedNPCID),
            name = runtime and runtime.lastResolvedName or nil,
        }
        if lockedResolved.npcID and lockedMapID then
            SyncUnitCDTimers(unit, obs, lockedResolved, lockedMapID)
        end
    else
        SyncUnitCDTimers(unit, nil, nil, nil)
    end

    -- 锁定或预判在读条期间才取得时，立刻重试一次；同一 activeCastSeq 的后续
    -- UNIT_SPELLCAST_START / 刷新调用会被 Output 的序号去重挡住。
    local previewVoicePending = type(runtime) == "table"
        and not tonumber(runtime.identityLockedNPCID)
        and tonumber(runtime.priorityPreviewVoiceNPCID)
        and tonumber(runtime.priorityPreviewVoiceMapID)
        and (tostring(runtime.priorityPreviewVoiceSource or "") == "priority"
            or tostring(runtime.priorityPreviewVoiceSource or "") == "candidate-preview")
    if (identityJustLocked or previewVoicePending) and runtime and runtime.activeCastStartAt
        and Output and type(Output.PlayRuntimeCastStartVoice) == "function" then
        Output.PlayRuntimeCastStartVoice(runtime, runtime.activeCastKind)
    end

    if coPresenceJustRegistered then
        self:RefreshUnresolvedNameplatesForCoPresence(trashMapID, unit)
    end

    local displayResolved = resolved
    if keepLockedRuntime and type(runtime) == "table" then
        displayResolved = {
            npcID = tonumber(runtime.matchedNPCID),
            name = runtime.lastResolvedName,
        }
    end
    if State and type(State.SyncUnit) == "function" then
        State.SyncUnit(unit, runtime, obs, displayResolved, trashMapID)
    end
    UpdateUnitNameplate(unit, displayResolved, runtime)
end

function Mod:RefreshTargetDebug(reason)
    if not Mod._debug then
        return
    end
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        PrintMatchDebug("target", { reason = "no-hostile-target" })
        return
    end
    if not (Observation and type(Observation.CollectObservedUnit) == "function" and Inference and type(Inference.ResolveCandidates) == "function") then
        PrintMatchDebug("target", { reason = "missing-runtime-modules" })
        return
    end

    local instanceID, _dungeonName, dungeonKey, trashMapID = GetCurrentTrashContext()
    if not instanceID or dungeonKey == "" then
        PrintMatchDebug("target", {
            reason = "no-trash-context",
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
        })
        return
    end

    local obs = Observation.CollectObservedUnit("target")
    if type(obs) ~= "table" then
        PrintMatchDebug("target", {
            reason = "collect-target-failed",
            instanceID = instanceID,
            dungeonKey = dungeonKey,
            trashMapID = trashMapID,
        })
        return
    end

    obs.unit = "target"
    obs.inCombat = UnitAffectingCombat("target") == true

    local traits = GetMobTraits()
    local traitRows = type(traits.rows) == "table" and traits.rows or {}
    local runtime = Mod._targetDebugRuntime or {}
    Mod._targetDebugRuntime = runtime
    runtime._debugTrace = true
    local result = Inference.ResolveCandidates(obs, dungeonKey, traitRows, runtime, trashMapID, GetTime())
    local Layer1 = ExBoss.TrashCD and ExBoss.TrashCD.Layer1Filter or nil
    local Layer2 = ExBoss.TrashCD and ExBoss.TrashCD.Layer2Filter or nil
    local layer1Debug = Layer1 and type(Layer1.GetLastDebug) == "function" and Layer1.GetLastDebug() or nil
    local layer2Debug = Layer2 and type(Layer2.GetLastDebug) == "function" and Layer2.GetLastDebug() or nil

    PrintMatchDebug("target", {
        reason = reason or "target",
        instanceID = instanceID,
        dungeonKey = dungeonKey,
        trashMapID = trashMapID,
        obs = obs,
        result = result,
        layer1Debug = layer1Debug,
        layer2Debug = layer2Debug,
    })
end

function Mod:RefreshAllActiveNameplates(reason, forceSnapshot)
    if not ShouldRunRuntime() then
        self:Stop()
        return
    end
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if IsHostileNameplate(unit) then
            TrackNameplate(unit)
            self:RefreshUnit(unit, reason or "full", forceSnapshot == true)
            if forceSnapshot ~= true then
                self:ScheduleUnitRefresh(unit, SNAPSHOT_RETRY_DELAY, "snapshot", true)
            end
        else
            UntrackNameplate(unit)
        end
    end
end

function Mod:Start()
    self._running = true
    self:RefreshAllActiveNameplates("start", false)
end

function Mod:Stop()
    for _, runtime in pairs(self._runtimeByUnit or {}) do
        CancelRuntimeScriptEvents(runtime)
    end
    if NameplateMarker and type(NameplateMarker.HideAll) == "function" then
        NameplateMarker.HideAll()
    end
    if HealthThreshold and type(HealthThreshold.DeactivateAllTrashUnits) == "function" then
        HealthThreshold:DeactivateAllTrashUnits()
    end
    self._running = false
    WipeTable(self._unitFirstSeenAt)
    WipeTable(self._observedByUnit)
    WipeTable(self._runtimeByUnit)
    WipeTable(self._pendingUnitRefresh)
    WipeTable(self._pendingMarkerRefresh)
    if TrashCache and type(TrashCache.Reset) == "function" then
        TrashCache.Reset()
    end
    if CoPresence and type(CoPresence.Reset) == "function" then
        CoPresence.Reset()
    end
    if KingsRestWaves and type(KingsRestWaves.Reset) == "function" then
        KingsRestWaves.Reset()
    end
    if State and type(State.Reset) == "function" then
        State.Reset()
    end
end

function Mod:EnsureRunning()
    if not ShouldRunRuntime() then
        self:Stop()
        return false
    end
    if self._running ~= true then
        self:Start()
    end
    return self._running == true
end

-- State 每次检测到单个姓名板进战或脱战时，由 Runtime 重新采样。
-- 进入战斗会建立计时；脱离战斗会走 SyncUnitCDTimers(nil) 清掉旧计时。
if State and type(State.SetCombatStateCallback) == "function" then
    State.SetCombatStateCallback(function(unit, inCombat)
        if Mod._running == true then
            Mod:OnCoPresenceCombatTransition(unit)
            DebugChat(string.format("state-callback unit=%s inCombat=%s action=refresh", tostring(unit),
                tostring(inCombat == true)))
            Mod:ScheduleUnitRefresh(unit, 0.01,
                inCombat == true and "state-combat-enter" or "state-combat-leave", true)
        end
    end)
end

local function ResetCoPresenceTentativeSession(runtime)
    if type(runtime) ~= "table" then
        return
    end
    runtime._coPresenceTentativeSession = (tonumber(runtime._coPresenceTentativeSession) or 0) + 1
    runtime._coPresenceTentativeTimerSession = nil
    runtime._coPresenceTentativeReadySession = nil
    runtime._coPresenceProvisionalNPCID = nil
    runtime._coPresenceProvisionalSource = nil
end

function Mod:OnCoPresenceCombatTransition(unit)
    ResetCoPresenceTentativeSession(GetRuntimeObs(unit))
end

function Mod:ScheduleCoPresenceTentativeFallback(unit, runtime)
    unit = NormalizeNameplateUnit(unit)
    if not unit or type(runtime) ~= "table" or not C_Timer or type(C_Timer.After) ~= "function" then
        return false
    end
    local session = tonumber(runtime._coPresenceTentativeSession)
    if session == nil then
        session = 0
        runtime._coPresenceTentativeSession = session
    end
    if tonumber(runtime._coPresenceTentativeTimerSession) == session
        or tonumber(runtime._coPresenceTentativeReadySession) == session then
        return false
    end
    runtime._coPresenceTentativeTimerSession = session
    C_Timer.After(COPRESENCE_TENTATIVE_DELAY, function()
        if Mod._running ~= true then
            return
        end
        local currentRuntime = type(Mod._runtimeByUnit) == "table" and Mod._runtimeByUnit[unit] or nil
        if currentRuntime ~= runtime
            or tonumber(runtime._coPresenceTentativeSession) ~= session
            or (State and type(State.IsUnitInCombat) == "function" and State.IsUnitInCombat(unit, false) ~= true) then
            return
        end
        runtime._coPresenceTentativeReadySession = session
        DebugPrint(string.format("co-presence-timeout-ready unit=%s session=%s", tostring(unit), tostring(session)))
        Mod:RefreshUnit(unit, "co-presence-timeout", true)
    end)
    return true
end

local function MarkRuntimeObservation(unit, key)
    if Observation and type(Observation.MarkRuntimeObservation) == "function" then
        return Observation.MarkRuntimeObservation(Mod, unit, key)
    end
end

local function BeginRuntimeCast(unit, kind, castBarID, combatConfirmed)
    if Observation and type(Observation.BeginRuntimeCast) == "function" then
        return Observation.BeginRuntimeCast(Mod, unit, kind, castBarID, combatConfirmed)
    end
end

local function MarkRuntimeInterruptible(unit, castBarID)
    if Observation and type(Observation.MarkRuntimeInterruptible) == "function" then
        return Observation.MarkRuntimeInterruptible(Mod, unit, castBarID)
    end
end

local function MarkRuntimeCastStop(unit, castBarID)
    if Observation and type(Observation.MarkRuntimeCastStop) == "function" then
        return Observation.MarkRuntimeCastStop(Mod, unit, castBarID)
    end
end

local function MarkRuntimeInterrupted(unit, castBarID)
    if Observation and type(Observation.MarkRuntimeInterrupted) == "function" then
        return Observation.MarkRuntimeInterrupted(Mod, unit, castBarID)
    end
end

local function MarkRuntimeChannelStop(unit, castBarID, interruptedBy)
    if Observation and type(Observation.MarkRuntimeChannelStop) == "function" then
        return Observation.MarkRuntimeChannelStop(Mod, unit, castBarID, interruptedBy)
    end
end

local function MarkRuntimeUnitTarget(unit)
    if Observation and type(Observation.MarkRuntimeUnitTarget) == "function" then
        return Observation.MarkRuntimeUnitTarget(Mod, unit)
    end
end

local function Register(event, owner, func)
    if ET and ET.RegisterEvent then
        ET:RegisterEvent(event, owner, func)
    end
end

Register("PLAYER_ENTERING_WORLD", "ExBoss_Trash_Observation_PEW", function()
    if ShouldRunRuntime() then
        Mod:Start()
    else
        Mod:Stop()
    end
end)

Register("PLAYER_REGEN_DISABLED", "ExBoss_Trash_Observation_CombatStart", function()
    if not ShouldRunRuntime() then
        Mod:Stop()
    elseif Mod._running ~= true then
        Mod:Start()
    else
        Mod:RefreshAllActiveNameplates("combat-start", true)
    end
end)

Register("PLAYER_REGEN_ENABLED", "ExBoss_Trash_Observation_CombatEnd", function()
    if ShouldRunRuntime() then
        Mod:RefreshAllActiveNameplates("combat-end", true)
    else
        Mod:Stop()
    end
end)

Register("PLAYER_TARGET_CHANGED", "ExBoss_Trash_Observation_TargetDebug", function()
    if Mod._debug == true then
        Mod:RefreshTargetDebug("target-changed")
    end
end)

Register("NAME_PLATE_UNIT_ADDED", "ExBoss_Trash_Observation_NPA", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod:EnsureRunning() then
        if Mod._debug == true then
            DebugChat(string.format(
                "nameplate-added unit=%s name=%s unitCombat=%s",
                tostring(unit),
                tostring(UnitExists(unit) and UnitName(unit) or "nil"),
                FormatBool(UnitExists(unit) and IsNameplateInCombat(unit))
            ))
        end
        TrackNameplate(unit)
        Mod:RefreshUnit(unit, "nameplate-added", false)
        Mod:ScheduleUnitRefresh(unit, SNAPSHOT_RETRY_DELAY, "snapshot", true)
    end
end)

Register("NAME_PLATE_UNIT_REMOVED", "ExBoss_Trash_Observation_NPR", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._debug == true then
        local runtime = GetRuntimeObs(unit)
        DebugChat(string.format(
            "nameplate-removed unit=%s name=%s resolvedNPC=%s lock=%s reserved=%s deathConsumed=%s activeCast=%s",
            tostring(unit),
            tostring(UnitExists(unit) and UnitName(unit) or "nil"),
            tostring(type(runtime) == "table" and runtime.matchedNPCID or "nil"),
            tostring(type(runtime) == "table" and runtime.identityLockedNPCID or "nil"),
            tostring(type(runtime) == "table" and runtime._populationReserved == true),
            tostring(type(runtime) == "table" and runtime._populationDeathConsumed == true),
            FormatBool(type(runtime) == "table" and runtime.activeCastStartAt ~= nil)
        ))
    end
    UntrackNameplate(unit)
end)

Register("UNIT_DISPLAYPOWER", "ExBoss_Trash_Observation_DisplayPower", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        Mod:RefreshUnit(unit, "display-power", true)
    end
end)

Register("UNIT_HEALTH", "ExBoss_Trash_Observation_UnitHealth", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit or Mod._running ~= true then
        return
    end
    if UnitIsDead(unit) then
        local runtime = type(Mod._runtimeByUnit) == "table" and Mod._runtimeByUnit[unit] or nil
        DebugChat(string.format("unit-health-dead unit=%s resolvedNPC=%s reserved=%s", tostring(unit),
            tostring(type(runtime) == "table" and runtime.matchedNPCID or "nil"),
            tostring(type(runtime) == "table" and runtime._populationReserved == true)))
        if Population and type(Population.OnUnitDead) == "function" then
            Population.OnUnitDead(runtime)
        end
        if TrashCache and type(TrashCache.OnUnitDead) == "function" then
            TrashCache.OnUnitDead(unit)
        end
        if State and type(State.OnUnitDead) == "function" then
            State.OnUnitDead(unit)
        end
        UntrackNameplate(unit)
    end
end)

Register("UNIT_DIED", "ExBoss_Trash_Observation_UnitDied", function()
    if Mod._running ~= true then
        return
    end
    if TrashCache and type(TrashCache.OnCombatLogUnitDied) == "function" then
        TrashCache.OnCombatLogUnitDied()
    end
    if State and type(State.OnCombatLogUnitDied) == "function" then
        State.OnCombatLogUnitDied()
    end
end)

Register("UNIT_TARGET", "ExBoss_Trash_Observation_UnitTarget", function(_, unit)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        MarkRuntimeUnitTarget(unit)
    end
end)

Register("UNIT_SPELLCAST_START", "ExBoss_Trash_Observation_CastStart", function(_, unit, _castGUID, _spellID, castBarID)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod:EnsureRunning() and IsNameplateInCombat(unit, true) == true then
        MarkRuntimeObservation(unit, "sawCastStart")
        local started = BeginRuntimeCast(unit, "cast", castBarID, true)
        Mod:RefreshUnit(unit, "cast-start", true, true)
        if started ~= false and Output and type(Output.PlayRuntimeCastStartVoice) == "function" then
            Output.PlayRuntimeCastStartVoice(GetRuntimeObs(unit), "cast")
        end
    end
end)

Register("UNIT_SPELLCAST_CHANNEL_START", "ExBoss_Trash_Observation_ChannelStart",
    function(_, unit, _castGUID, _spellID, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod:EnsureRunning() and IsNameplateInCombat(unit, true) == true then
            MarkRuntimeObservation(unit, "sawChannelStart")
            local started = BeginRuntimeCast(unit, "channel", castBarID, true)
            Mod:RefreshUnit(unit, "channel-start", true, true)
            if started ~= false and Output and type(Output.PlayRuntimeCastStartVoice) == "function" then
                Output.PlayRuntimeCastStartVoice(GetRuntimeObs(unit), "channel")
            end
        end
    end)

Register("UNIT_SPELLCAST_INTERRUPTIBLE", "ExBoss_Trash_Observation_Interruptible",
    function(_, unit, _castGUID, _spellID, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeInterruptible(unit, castBarID)
            Mod:RefreshUnit(unit, "cast-interruptible", true)
        end
    end)

Register("UNIT_SPELLCAST_INTERRUPTED", "ExBoss_Trash_Observation_Interrupted",
    function(_, unit, _castGUID, _spellID, _interruptedBy, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeObservation(unit, "sawInterrupted")
            MarkRuntimeInterrupted(unit, castBarID)
            Mod:RefreshUnit(unit, "cast-interrupted", true)
        end
    end)

Register("UNIT_SPELLCAST_FAILED", "ExBoss_Trash_Observation_Failed", function(_, unit, _castGUID, _spellID, castBarID)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        MarkRuntimeObservation(unit, "sawInterrupted")
        MarkRuntimeInterrupted(unit, castBarID)
        Mod:RefreshUnit(unit, "cast-failed", true)
    end
end)

Register("UNIT_SPELLCAST_FAILED_QUIET", "ExBoss_Trash_Observation_FailedQuiet",
    function(_, unit, _castGUID, _spellID, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeObservation(unit, "sawInterrupted")
            MarkRuntimeInterrupted(unit, castBarID)
            Mod:RefreshUnit(unit, "cast-failed-quiet", true)
        end
    end)

Register("UNIT_SPELLCAST_STOP", "ExBoss_Trash_Observation_CastStop", function(_, unit, _castGUID, _spellID, castBarID)
    unit = NormalizeNameplateUnit(unit)
    if unit and Mod._running == true then
        MarkRuntimeCastStop(unit, castBarID)
        Mod:RefreshUnit(unit, "cast-stop", true)
    end
end)

Register("UNIT_SPELLCAST_CHANNEL_STOP", "ExBoss_Trash_Observation_ChannelStop",
    function(_, unit, _castGUID, _spellID, interruptedBy, castBarID)
        unit = NormalizeNameplateUnit(unit)
        if unit and Mod._running == true then
            MarkRuntimeChannelStop(unit, castBarID, interruptedBy)
            Mod:RefreshUnit(unit, "channel-stop", true)
        end
    end)

function Mod:SetUIEnabled(enabled)
    self._uiEnabled = (enabled == true)
    if TrashCore and type(TrashCore.SetMonitorUIEnabled) == "function" then
        TrashCore.SetMonitorUIEnabled(enabled == true)
    end
    if ShouldRunRuntime() then
        self:Start()
    else
        self:Stop()
    end
end
