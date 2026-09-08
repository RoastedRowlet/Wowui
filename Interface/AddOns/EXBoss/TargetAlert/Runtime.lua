---@diagnostic disable: undefined-global, undefined-field
-- =============================================================
-- TargetAlert/Runtime.lua
-- 声明式 ENCOUNTER_WARNING 提示：以 Boss event 的预计结束时刻为窗口中心。
-- 不读取目标、名字、GUID 或其他受限的 EncounterWarningInfo 字段。
-- =============================================================

ExBoss = ExBoss or {}
ExBoss.TargetAlert = ExBoss.TargetAlert or {}

local Runtime = ExBoss.TargetAlert
local OWNER_PREFIX = "ExBoss.EncounterWarningAlert"

local EMPTY_DECLARATIONS = {}

local function GetDeclarations()
    local data = _G.EXBossData
    if type(data) == "table" and type(data.GetEncounterWarningRules) == "function" then
        local declarations = data.GetEncounterWarningRules()
        if type(declarations) == "table" then
            return declarations
        end
    end
    return EMPTY_DECLARATIONS
end

local function GetCurrentBossScene()
    if type(GetInstanceInfo) ~= "function" then
        return "mplus"
    end
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then
        return "mplus"
    end
    if instanceType == "raid" then
        return "raid"
    end
    -- BossConfig 在副本外原本就预载 M+ Runtime；测试命令沿用同一选择，
    -- 不建立第二份 GUI 配置来源。
    return "mplus"
end

local function GetBossGUIConfig(eventID)
    local scene = GetCurrentBossScene()
    local bossConfig = ExBoss.BossConfig
    if scene == nil or not bossConfig
        or type(bossConfig.GetEncounterWarningAlertConfig) ~= "function" then
        return nil
    end
    return bossConfig:GetEncounterWarningAlertConfig(scene, eventID)
end

local function IsEnabledByBossGUI(eventID)
    return GetBossGUIConfig(eventID) ~= nil
end

Runtime._windows = {}

local function Now()
    return GetTime and GetTime() or 0
end

local function Say(message)
    if ExBoss.Print and type(ExBoss.Print.Say) == "function" then
        ExBoss.Print.Say(message)
    elseif type(print) == "function" then
        print("<EXBOSS> " .. tostring(message))
    end
end

local function ResolveDeclaration(raw, index)
    if type(raw) ~= "table" then
        return nil
    end

    local eventID = tonumber(raw.eventID)
    local severity = tonumber(raw.severity)
    local spellID = tonumber(raw.spellID)
    local duration = tonumber(raw.duration)
    if not eventID or severity == nil or not spellID or not duration or duration <= 0 then
        return nil
    end

    local windowBefore = tonumber(raw.windowBefore)
    local windowAfter = tonumber(raw.windowAfter)
    if windowBefore == nil or windowAfter == nil or windowBefore < 0 or windowAfter < 0 then
        return nil
    end

    local encounterID = raw.encounterID ~= nil and tonumber(raw.encounterID) or nil
    if raw.encounterID ~= nil and not encounterID then
        return nil
    end

    return {
        index = index,
        encounterID = encounterID,
        eventID = eventID,
        severity = severity,
        windowBefore = windowBefore,
        windowAfter = windowAfter,
        spellID = spellID,
        duration = duration,
    }
end

local function IsBossTimer(timer)
    if type(timer) ~= "table" then
        return false
    end
    -- 不让 TrashCD 或独立小怪计时器成为此功能的窗口来源。
    if timer.source == "trash" or timer.displaySource == "trash"
        or timer.trashMeta ~= nil or timer.trashRuntime ~= nil or timer.trashSpellData ~= nil then
        return false
    end
    return true
end

local function GetTimerEventID(timer)
    if type(timer) ~= "table" then
        return nil
    end
    -- fixed / fixed_ai 使用 eventID；原生时间轴计时器使用 timelineEventID。
    return tonumber(timer.eventID) or tonumber(timer.timelineEventID)
end

local function BuildWindowKey(encounterID, eventID, timerID, declaration)
    return table.concat({
        tostring(encounterID or "any"),
        tostring(eventID),
        tostring(timerID),
        tostring(declaration.index),
    }, ":")
end

local function StopWindowDisplay(window)
    local iconAlert = ExBoss.UI and ExBoss.UI.IconAlert or nil
    if iconAlert and type(iconAlert.StopByOwner) == "function" and window and window.owner then
        iconAlert:StopByOwner(window.owner)
        if window.stealthOwner then iconAlert:StopByOwner(window.stealthOwner) end
    end
    local ring = ExBoss.UI and ExBoss.UI.RingProgress or nil
    if ring and type(ring.StopByOwner) == "function" and window and window.ringOwner then
        ring:StopByOwner(window.ringOwner)
    end
end

local function PruneExpiredWindows(now)
    for key, window in pairs(Runtime._windows) do
        if type(window) ~= "table" or now > (tonumber(window.endAt) or 0) then
            Runtime._windows[key] = nil
        end
    end
end

local function GetSpellName(spellID)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return tostring(spellID)
end

local function BuildVoiceConfig(config)
    if type(config) ~= "table" or config.targetAlertVoiceEnabled ~= true then return nil end
    local sourceType = tostring(config.targetAlertStartSource or "lsm"):lower()
    if sourceType ~= "pack" and sourceType ~= "lsm" and sourceType ~= "file" and sourceType ~= "tts" then
        sourceType = "lsm"
    end
    return {
        enabled = true,
        sourceType = sourceType,
        label = tostring(config.targetAlertStartLabel or ""),
        customLSM = tostring(config.targetAlertStartLSM or ""),
        customPath = tostring(config.targetAlertStartPath or ""),
        ttsText = tostring(config.targetAlertStartTtsText or ""),
    }
end

local function ShowWindow(window, now, config)
    config = type(config) == "table" and config or {}

    local rule = window.rule
    if type(rule) ~= "table" then
        return 0
    end

    local shown = 0
    local spellName = GetSpellName(rule.spellID)
    local endTime = now + rule.duration

    if config.targetAlertRingEnabled == true then
        local ring = ExBoss.UI and ExBoss.UI.RingProgress or nil
        local ringDB = ring and type(ring.GetDB) == "function" and ring:GetDB() or nil
        if ring and type(ring.ShowEntry) == "function" and type(ringDB) == "table" and ringDB.enabled == true then
            window.ringOwner = {
                source = "encounter_warning_alert",
                earlyStopEnabled = true,
                eventID = rule.eventID,
                spellID = rule.spellID,
                key = window.owner,
            }
            ring:ShowEntry({
                owner = window.ringOwner,
                spellID = rule.spellID,
                displayName = spellName,
                progressDisplayName = spellName,
                duration = rule.duration,
                endTime = endTime,
                castKind = "cast",
                castCheckEnabled = false,
            })
            shown = shown + 1
        end
    end

    local iconAlert = ExBoss.UI and ExBoss.UI.IconAlert or nil
    if config.targetAlertIconEnabled == true
        and iconAlert and type(iconAlert.ShowEntry) == "function"
        and iconAlert:ShowEntry({
            owner = window.owner,
            spellID = rule.spellID,
            duration = rule.duration,
            endTime = endTime,
        }) ~= nil then
        shown = shown + 1
    end

    if config.targetAlertStealthEnabledV2 == true
        and iconAlert and type(iconAlert.ShowEntry) == "function" then
        local state = ExwindTools and ExwindTools.State or nil
        if type(state) == "table" and state.ShadowmeldAvailable == true and state.ShadowmeldCD ~= true then
            window.stealthOwner = window.owner .. ":stealth"
            if iconAlert:ShowEntry({
                owner = window.stealthOwner,
                icon = 132089,
                text = " ",
                duration = rule.duration,
                endTime = endTime,
                hideCooldown = true,
                hideCountdownNumbers = true,
            }) ~= nil then
                shown = shown + 1
            end
        end
    end

    if config.targetAlertTextEnabledV2 == true then
        local medium = ExBoss.UI and ExBoss.UI.FlashTextMedium or nil
        if medium and type(medium.Show) == "function" then
            medium:Show({ text = spellName, duration = rule.duration, noAnimation = true })
            shown = shown + 1
        end
    end

    local voiceConfig = BuildVoiceConfig(config)
    local voice = ExBoss.Voice and ExBoss.Voice.Engine or nil
    if voiceConfig and voice and type(voice.TryPlayStandaloneSound) == "function" then
        local played = voice:TryPlayStandaloneSound(voiceConfig, window.owner .. ":voice", { triggerIndex = 0 })
        if played then shown = shown + 1 end
    end

    return shown
end

local function HandleWarning(warningInfo, now, onlyWindowKeys)
    -- 官方文档将 severity 标为公开字段；此处不读取其他 payload 内容。
    local severity = type(warningInfo) == "table" and tonumber(warningInfo.severity) or nil
    if severity == nil then
        return 0, 0
    end

    PruneExpiredWindows(now)

    local matched = 0
    local shown = 0
    for key, window in pairs(Runtime._windows) do
        local allowed = onlyWindowKeys == nil or onlyWindowKeys[key] == true
        local rule = type(window) == "table" and window.rule or nil
        -- 实战与命令测试都重新读取当前角色/职责的 Boss 页面开关；测试不能
        -- 强制打开图标或绕过用户选择。
        local guiConfig = type(rule) == "table" and GetBossGUIConfig(rule.eventID) or nil
        local enabledByBossGUI = type(guiConfig) == "table"
        if allowed and type(rule) == "table"
            and enabledByBossGUI
            and now >= (tonumber(window.startAt) or math.huge)
            and now <= (tonumber(window.endAt) or -math.huge)
            and severity == rule.severity then
            matched = matched + 1
            -- 同一窗口内每次原生 warning 都会以收到的这一刻重置显示 duration。
            shown = shown + ShowWindow(window, now, guiConfig)
        end
    end
    return matched, shown
end

-- Scheduler 在每次 Boss timer 更新后调用本函数。即使 timer 随后被回收，
-- 已建立的窗口仍保留至 event 结束后的 windowAfter。
function Runtime:ObserveBossTimer(timer, currentEncounterID, observedAt)
    if not IsBossTimer(timer) then
        return 0
    end

    local now = tonumber(observedAt) or Now()
    local timerID = tonumber(timer.id)
    local eventID = GetTimerEventID(timer)
    local castTime = tonumber(timer.castTime)
    local encounterID = tonumber(currentEncounterID) or tonumber(timer.encounterID)
    if not timerID or not eventID or not castTime then
        return 0
    end
    -- 声明表不保存 enabled；是否建立窗口完全由当前 Boss 页面角色/职责开关决定。
    if not IsEnabledByBossGUI(eventID) then
        return 0
    end

    local createdOrUpdated = 0
    for index, raw in ipairs(GetDeclarations()) do
        local rule = ResolveDeclaration(raw, index)
        if rule and rule.eventID == eventID
            and (rule.encounterID == nil or rule.encounterID == encounterID) then
            local key = BuildWindowKey(encounterID, eventID, timerID, rule)
            local window = Runtime._windows[key] or {}
            window.rule = rule
            window.startAt = castTime - rule.windowBefore
            window.endAt = castTime + rule.windowAfter
            window.owner = OWNER_PREFIX .. ":" .. key
            Runtime._windows[key] = window
            createdOrUpdated = createdOrUpdated + 1
        end
    end

    PruneExpiredWindows(now)
    return createdOrUpdated
end

function Runtime:ReconcileFromScheduler(observedAt)
    local scheduler = ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
    if not (scheduler and type(scheduler.GetActiveTimers) == "function") then
        return 0
    end

    local now = tonumber(observedAt) or Now()
    local encounterID = type(scheduler.GetCurrentEncounterID) == "function"
        and scheduler:GetCurrentEncounterID() or nil
    local timers = scheduler:GetActiveTimers()
    local count = 0
    if type(timers) == "table" then
        for _, timer in pairs(timers) do
            count = count + self:ObserveBossTimer(timer, encounterID, now)
        end
    end
    return count
end

function Runtime:OnEncounterWarning(warningInfo)
    local now = Now()
    -- 事件可能发生在 Scheduler 下一次 0.05s tick 之前；先用当前活跃 timer 同步。
    self:ReconcileFromScheduler(now)
    return HandleWarning(warningInfo, now)
end

function Runtime:ClearRuntimeState()
    for _, window in pairs(self._windows) do
        StopWindowDisplay(window)
    end
    self._windows = {}
end

local function FindTestDeclarations(eventID)
    local rows = {}
    for index, raw in ipairs(GetDeclarations()) do
        local rule = ResolveDeclaration(raw, index)
        if rule and rule.eventID == eventID then
            rows[#rows + 1] = rule
        end
    end
    return rows
end

function Runtime:RunTest(eventID, severity)
    eventID = tonumber(eventID)
    if not eventID then
        local first = ResolveDeclaration(GetDeclarations()[1], 1)
        eventID = first and first.eventID or nil
        severity = severity ~= nil and tonumber(severity) or (first and first.severity)
    else
        severity = tonumber(severity)
    end

    if not eventID then
        Say("用法：/exewtest [eventID] [severity]；未填参数会测试声明表的第一条规则。")
        return false
    end

    local rules = FindTestDeclarations(eventID)
    if #rules == 0 then
        Say("测试未执行：声明表没有 eventID=" .. tostring(eventID) .. " 的规则。")
        return false
    end
    if severity == nil then
        severity = rules[1].severity
    end
    if severity == nil then
        Say("测试未执行：规则没有有效 severity。")
        return false
    end

    local now = Now()
    local testWindowKeys = {}
    for _, rule in ipairs(rules) do
        local key = "test:" .. BuildWindowKey(nil, eventID, "command", rule)
        self._windows[key] = {
            rule = rule,
            startAt = now - 1,
            endAt = now + math.max(1, rule.windowAfter),
            owner = OWNER_PREFIX .. ":" .. key,
        }
        testWindowKeys[key] = true
    end

    -- 测试只注入 severity，不伪造 Blizzard 原生事件；显示种类完整服从
    -- Boss 页面原有「被点名提示」勾选。
    local matched, shown = HandleWarning({ severity = severity }, now, testWindowKeys)
    for key in pairs(testWindowKeys) do
        self._windows[key] = nil
    end

    if matched == 0 then
        Say("测试没有命中：eventID=" .. tostring(eventID) .. "，注入 severity=" .. tostring(severity)
            .. "；请检查声明的 severity。")
        return false
    end
    if shown == 0 then
        Say("测试命中声明，但没有建立显示；请检查 Boss 页被点名提示及其显示/语音勾选。")
        return false
    end

    Say("测试已触发 " .. tostring(shown) .. " 个显示动作（eventID=" .. tostring(eventID)
        .. "，severity=" .. tostring(severity) .. "）。")
    return true
end

function Runtime:RunTestCommand(input)
    local eventID, severity = tostring(input or ""):match("^%s*(%d*)%s*(%d*)%s*$")
    if eventID == nil then
        Say("用法：/exewtest [eventID] [severity]")
        return false
    end
    return self:RunTest(eventID ~= "" and eventID or nil, severity ~= "" and severity or nil)
end

if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent("ENCOUNTER_WARNING", OWNER_PREFIX .. ".Warning", function(_, warningInfo)
        Runtime:OnEncounterWarning(warningInfo)
    end)
    ExwindTools:RegisterEvent("ENCOUNTER_START", OWNER_PREFIX .. ".Start", function()
        Runtime:ClearRuntimeState()
    end)
    ExwindTools:RegisterEvent("ENCOUNTER_END", OWNER_PREFIX .. ".End", function()
        Runtime:ClearRuntimeState()
    end)
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", OWNER_PREFIX .. ".PlayerEnteringWorld", function()
        Runtime:ClearRuntimeState()
    end)
end

SLASH_EXBOSSEWTEST1 = "/exewtest"
SlashCmdList["EXBOSSEWTEST"] = function(input)
    Runtime:RunTestCommand(input)
end
