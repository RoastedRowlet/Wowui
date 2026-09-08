---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.BossPage = ExBoss.UI.Panel.BossPage or {}
local Page = ExBoss.UI.Panel.BossPage

local C = {
    DEFAULT_EVENT_BORDER_COLOR = { r = 0.65, g = 0.65, b = 0.65 },
    MODEL_TUNE = {
        zoom = 0.85,
        cam = 1.05,
        posX = 0.0,
        posY = 0.0,
        posZ = 0.0,
        facing = 0.0,
    },
    SPELL_CARD = {
        cols = 5,
        gapX = 6,
        gapY = 6,
        height = 36,
        titleFontSizes = { 18, 16, 14, 12 },
    },
    -- 右侧技能卡片列表固定显示两行；下方设置区承接其余高度并自行滚动。
    SPELL_LIST_VISIBLE_ROWS = 2,
    SPELL_SETTINGS_GRID_COLS = 200,
    PREALERT_FIXED_SECS = 5,
    TIMELINE_SOURCE_SCRIPT = Enum and Enum.EncounterTimelineEventSource and Enum.EncounterTimelineEventSource.Script or 1,
    SPELL_TEXT_KEYS = {
        "centralText",
        "preAlertText",
        "timerBarRenameText",
        "castProgressBarRenameText",
    },
    TRIGGER_SOURCE_ITEMS = {
        { L["语音包标签"], "pack" },
        { L["LSM音效"], "lsm" },
        { L["自定义路径"], "file" },
        { L["TTS语音"], "tts" },
    },
    COUNTDOWN_LEAD_ITEMS = {
        { "1", "1" },
        { "2", "2" },
        { "3", "3" },
        { "4", "4" },
        { "5", "5" },
        { "6", "6" },
        { "7", "7" },
        { "8", "8" },
        { "9", "9" },
    },
    TRIGGER_OFFSET_MODE_ITEMS = {
        { L["延迟"], "delay" },
        { L["提前"], "early" },
    },
    TRIGGER_NAME = {
        [0] = L["中央警告"],
        [1] = L["施法开始"],
        [2] = L["提前倒数"],
    },
    MAP_CATEGORY_ITEMS = {
        { L["12.1大秘境"], "12.1大秘境" },
        { L["12.1团本"] or "12.1团本", "12.1团本" },
    },
    MAP_ICON_RENDER_OVERRIDES = {},
}

-- Grid 的颜色方案由函数路径在渲染时解析。
local EVENT_COLOR_ITEMS_FUNC = "func:ExBoss.Voice.ColorSchemes.BuildDropdownItems"

-- Boss 法术编辑器会在切换技能后复用 Grid 控件，因此语音标签不能只在
-- 布局里写一次 items；每次绑定到新法术时都要重新取目录并写回控件。
local function GetVoiceLabelDropdownItems()
    local catalog = ExBoss and ExBoss.Voice and ExBoss.Voice.LabelCatalog
    if type(catalog) == "table" and type(catalog.GetDropdownItems) == "function" then
        local ok, items = pcall(catalog.GetDropdownItems, catalog)
        if ok and type(items) == "table" then
            return items
        end
    end
    return {}
end

local function SetDropdownText(dropdown, text)
    if not dropdown then return end
    if dropdown.OverrideText then
        dropdown:OverrideText(text)
    elseif dropdown.SetText then
        dropdown:SetText(text)
    end
end

local function RefreshVoiceLabelDropdown(dropdown, value)
    if not dropdown then return end
    local selected = tostring(value or "")
    local items = GetVoiceLabelDropdownItems()
    dropdown._items = items
    dropdown._currentValue = selected
    local display = selected
    for _, item in ipairs(items) do
        if type(item) == "table" and tostring(item[2] or "") == selected then
            display = tostring(item[1] or selected)
            break
        end
    end
    SetDropdownText(dropdown, display ~= "" and display or L["请选择..."])
end

local function GetEffectiveDisplayLocale()
    local locale = "zhCN"
    if ExBoss and ExBoss.GetEffectiveLocale then
        local mode = ExBoss.GetLocaleMode and ExBoss:GetLocaleMode() or "AUTO"
        locale = tostring(ExBoss:GetEffectiveLocale(mode) or "zhCN"):gsub("%s+", "")
    end
    if locale == "enGB" then return "enUS" end
    return locale
end

local function GetLocalizedDBName(meta, locale)
    if type(meta) ~= "table" then return nil end
    local value = meta[locale]
    if type(value) == "string" and value ~= "" then return value end
    value = meta.enUS or meta.nameEN or meta.name
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- 名称统一从 EXDB 获取；没有资料时仅显示原始数据名称。
local function ResolveLocalizedDisplayName(rawName, fallbackName, _, _, encounterID, mapID)
    local locale = GetEffectiveDisplayLocale()
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil
    if EXDB then
        local meta
        if encounterID and type(EXDB.GetEncounterNoteMeta) == "function" then
            meta = EXDB:GetEncounterNoteMeta(encounterID)
        end
        local localized = GetLocalizedDBName(meta, locale)
        if localized then return localized end
        if mapID and type(EXDB.GetInstanceNoteMetaByMapID) == "function" then
            meta = EXDB:GetInstanceNoteMetaByMapID(mapID)
        end
        localized = GetLocalizedDBName(meta, locale)
        if localized then return localized end
    end
    local raw = tostring(rawName or "")
    if raw ~= "" then return raw end
    return tostring(fallbackName or "")
end
local UI = {}

local CARD_CACHE = {
    activeMapTabs = {},
    mapTabPool = {},
    activeBossCards = {},
    bossCardPool = {},
    activeSpellCards = {},
    spellCardPool = {},
    spellCachePending = {},
    spellTextCache = {},
    alertAtlasExistCache = {},
}
local selectedSeason
local selectedMapID
local selectedBossIndex
local selectedEventID
local selectedBossCommonSettings
local STATE = {
    testTimelineLoopActive = false,
    testTimelineScriptEventIDs = {},
    testTimelineLoopHandles = {},
    testTimelineCleanupHandles = {},
    asyncHandler = nil,
    -- Render 和同帧的外部 RefreshSpellUI 都可能排入 After(0)。只允许当前
    -- 页面实例的回调继续，避免切 Tab 后旧回调在重开页面上重复重建卡片。
    pageRenderGeneration = 0,
    buildToken = 0,
    bossBuildToken = 0,
    mapBuildToken = 0,
    settingsSyncLock = false,
    suspendSpellSettingPersist = false,
    spellSettingsDirty = false,
    spellUIRefreshPending = false,
    spellUIRefreshToken = 0,
    spellTextPersistTokens = {},
    spellTextFormState = {},
    -- 文本控件会同时触发防抖、失焦和 Enter；以草稿版本去重，确保一个实际
    -- 输入只提交一次。该版本只属于当前编辑上下文，切技能后立即失效。
    spellTextDraftRevision = 0,
    spellTextCommittedRevision = 0,
    spellTextContextRevision = nil,
    spellTextContextEventID = nil,
    spellTextContextConfigID = nil,
    spellTextContextSlotKey = nil,
    spellSettingsGridBound = false,
    -- 当前法术的纯内存控件状态；它只承载正在显示的字段，不能作为
    -- 配置快照或持久化中间层。
    spellEditorDraft = nil,
    currentSpellSlotKey = nil,
    -- Boss 右侧编辑器是异步渲染的。临时表单必须明确归属到一次加载，
    -- 不能在隐藏页面或切换职责/专精后写入新的配置目标。
    spellEditorRevision = 0,
    spellEditorContext = nil,
}
ExBoss.TestTimelineScriptMeta = ExBoss.TestTimelineScriptMeta or {}
ExBoss.TestTimelineForceFixedTime = ExBoss.TestTimelineForceFixedTime or {}
Page._spellTextRawState = Page._spellTextRawState or {}
local SETTINGS = {}

local RefreshModeButton
local UpdateSummary
local RefreshSpellCards
local RefreshBossList
local RefreshMapTabs
local RefreshSeasonDropdown
local SetWidgetUsable
local PersistSpellEditorDraftToSelectedSpell
local BuildSpellEditorDraftFromSelectedSpell
local CommitSpellTextFormState
local RefreshSettingsDynamicWidgets
local RefreshSpellDetailHeaderLayout

local function GetWidgetEditText(widget)
    if type(widget) ~= "table" then
        return nil
    end
    if widget.GetText then
        local ok, text = pcall(widget.GetText, widget)
        if ok then
            return tostring(text or "")
        end
    end
    if widget.editBox and widget.editBox.GetText then
        local ok, text = pcall(widget.editBox.GetText, widget.editBox)
        if ok then
            return tostring(text or "")
        end
    end
    if widget.eb and widget.eb.GetText then
        local ok, text = pcall(widget.eb.GetText, widget.eb)
        if ok then
            return tostring(text or "")
        end
    end
    return nil
end

local function SetSpellTextFormStateValue(key, value)
    if type(key) ~= "string" or key == "" then
        return
    end
    STATE.spellTextFormState[key] = tostring(value or "")
end

local function IsCurrentSpellTextContext()
    local context = STATE.spellEditorContext
    return Page._visible == true
        and type(context) == "table"
        and context.revision == STATE.spellEditorRevision
        and STATE.spellTextContextRevision == context.revision
        and STATE.spellTextContextEventID == context.eventID
        and STATE.spellTextContextConfigID == context.configID
        and STATE.spellTextContextSlotKey == context.slotKey
        and STATE.currentSpellSlotKey == context.slotKey
        and tonumber(selectedEventID) == tonumber(context.eventID)
end

local function IsSpellTextKey(key)
    if type(key) ~= "string" then
        return false
    end
    for i = 1, #C.SPELL_TEXT_KEYS do
        if C.SPELL_TEXT_KEYS[i] == key then
            return true
        end
    end
    return false
end

local function GetSpellSettingsWidgets()
    local Grid = _G.ExwindGrid
    if not Grid then
        return nil
    end
    local state = UI.spellSettingsGridChild and Grid.ContainerStates and Grid.ContainerStates[UI.spellSettingsGridChild]
    if type(state) == "table" and type(state.widgets) == "table" then
        return state.widgets
    end
    return Grid.Widgets
end

local function RegisterSpellSettingsGridAsActive(moduleKey)
    if not (Page._visible and UI.spellSettingsGridChild and ExwindTools.UI) then
        return
    end
    ExwindTools.UI.ActivePageFrame = UI.spellSettingsGridChild
    if type(moduleKey) == "string" and moduleKey ~= "" then
        ExwindTools.UI.CurrentModule = moduleKey
    end
end

local function ClearSpellSettingsGridActiveRegistration()
    if not (ExwindTools.UI and UI.spellSettingsGridChild) then
        return
    end
    if ExwindTools.UI.ActivePageFrame == UI.spellSettingsGridChild then
        ExwindTools.UI.ActivePageFrame = nil
        ExwindTools.UI.CurrentModule = nil
    end
end

local function SyncSpellTextFormStateFromDraft(draft)
    if type(draft) ~= "table" then
        return
    end
    for i = 1, #C.SPELL_TEXT_KEYS do
        local key = C.SPELL_TEXT_KEYS[i]
        STATE.spellTextFormState[key] = tostring(draft[key] or "")
    end
end

local function ResolveDisplayedSpellTextForStorage(key, displayedText)
    local shown = tostring(displayedText or "")
    local raw = tostring((Page._spellTextRawState and Page._spellTextRawState[key]) or "")
    if raw ~= "" then
        local localizedRaw = raw
        if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
            localizedRaw = tostring(ExBoss.Locale.TranslateBossDynamicText(raw) or "")
        end
        if shown == localizedRaw then
            return raw
        end
    end
    return shown
end

local function SyncLiveSpellTextInputsToDraft(draft)
    local widgets = GetSpellSettingsWidgets()
    if not (type(draft) == "table" and type(widgets) == "table") then
        return
    end
    local centralText = STATE.spellTextFormState.centralText
    local preAlertText = STATE.spellTextFormState.preAlertText
    local timerRenameText = STATE.spellTextFormState.timerBarRenameText
    local castProgressRenameText = STATE.spellTextFormState.castProgressBarRenameText
    if centralText == nil then
        centralText = GetWidgetEditText(widgets["centralText"])
    end
    if preAlertText == nil then
        preAlertText = GetWidgetEditText(widgets["preAlertText"])
    end
    if timerRenameText == nil then
        timerRenameText = GetWidgetEditText(widgets["timerBarRenameText"])
    end
    if castProgressRenameText == nil then
        castProgressRenameText = GetWidgetEditText(widgets["castProgressBarRenameText"])
    end
    if centralText ~= nil then
        draft.centralText = tostring(ResolveDisplayedSpellTextForStorage("centralText", centralText) or "")
        STATE.spellTextFormState.centralText = draft.centralText
    end
    if preAlertText ~= nil then
        draft.preAlertText = tostring(ResolveDisplayedSpellTextForStorage("preAlertText", preAlertText) or "")
        STATE.spellTextFormState.preAlertText = draft.preAlertText
    end
    if timerRenameText ~= nil then
        draft.timerBarRenameText = tostring(ResolveDisplayedSpellTextForStorage("timerBarRenameText", timerRenameText) or
            "")
        STATE.spellTextFormState.timerBarRenameText = draft.timerBarRenameText
    end
    if castProgressRenameText ~= nil then
        draft.castProgressBarRenameText = tostring(castProgressRenameText or "")
        STATE.spellTextFormState.castProgressBarRenameText = draft.castProgressBarRenameText
    end
end

CommitSpellTextFormState = function(changedKey)
    if STATE.suspendSpellSettingPersist or STATE.settingsSyncLock then
        return
    end
    local draftRevision = tonumber(STATE.spellTextDraftRevision) or 0
    if draftRevision <= (tonumber(STATE.spellTextCommittedRevision) or 0)
        or not IsCurrentSpellTextContext() then
        return
    end
    local draft = STATE.spellEditorDraft
    if type(draft) ~= "table" then
        return
    end
    local beforeCentral = tostring(ResolveDisplayedSpellTextForStorage("centralText", draft.centralText) or "")
    local beforePreAlert = tostring(ResolveDisplayedSpellTextForStorage("preAlertText", draft.preAlertText) or "")
    local beforeTimerRename = tostring(ResolveDisplayedSpellTextForStorage("timerBarRenameText", draft.timerBarRenameText) or
        "")
    local beforeCastProgressRename = tostring(draft.castProgressBarRenameText or "")
    SyncLiveSpellTextInputsToDraft(draft)
    local afterCentral = tostring(draft.centralText or "")
    local afterPreAlert = tostring(draft.preAlertText or "")
    local afterTimerRename = tostring(draft.timerBarRenameText or "")
    local afterCastProgressRename = tostring(draft.castProgressBarRenameText or "")
    if beforeCentral == afterCentral
        and beforePreAlert == afterPreAlert
        and beforeTimerRename == afterTimerRename
        and beforeCastProgressRename == afterCastProgressRename then
        STATE.spellTextCommittedRevision = draftRevision
        STATE.spellSettingsDirty = false
        return
    end
    STATE.spellSettingsDirty = true
    local persisted = PersistSpellEditorDraftToSelectedSpell(changedKey)
    if persisted then
        STATE.spellTextCommittedRevision = draftRevision
    end
    STATE.spellSettingsDirty = (STATE.spellTextDraftRevision or 0) > (STATE.spellTextCommittedRevision or 0)
end

local function ScheduleSpellTextPersist(changedKey)
    local key = tostring(changedKey or "")
    if key == "" then
        return
    end
    STATE.spellTextPersistTokens[key] = (STATE.spellTextPersistTokens[key] or 0) + 1
    local token = STATE.spellTextPersistTokens[key]
    C_Timer.After(0.2, function()
        if STATE.spellTextPersistTokens[key] ~= token then
            return
        end
        CommitSpellTextFormState(key)
    end)
end

local function CancelPendingSpellTextPersist(changedKey)
    if changedKey ~= nil then
        local key = tostring(changedKey)
        STATE.spellTextPersistTokens[key] = (tonumber(STATE.spellTextPersistTokens[key]) or 0) + 1
        return
    end
    for key, token in pairs(STATE.spellTextPersistTokens) do
        STATE.spellTextPersistTokens[key] = (tonumber(token) or 0) + 1
    end
end

local function ClearSpellEditorTransientState()
    for key in pairs(STATE.spellTextFormState) do
        STATE.spellTextFormState[key] = nil
    end
    for key in pairs(Page._spellTextRawState) do
        Page._spellTextRawState[key] = nil
    end
end

-- 此函数只清理 Boss 页表单的内存状态，绝不改动任何持久配置。
-- 新上下文必须完成 BuildSpellEditorDraftFromSelectedSpell 后才能再次写入。
local function InvalidateSpellEditorContext()
    CancelPendingSpellTextPersist()
    STATE.spellEditorRevision = STATE.spellEditorRevision + 1
    STATE.spellEditorContext = nil
    STATE.currentSpellSlotKey = nil
    if not STATE.spellSettingsGridBound then
        STATE.spellEditorDraft = nil
    end
    STATE.spellTextContextRevision = nil
    STATE.spellTextContextEventID = nil
    STATE.spellTextContextConfigID = nil
    STATE.spellTextContextSlotKey = nil
    STATE.spellSettingsDirty = false
    ClearSpellEditorTransientState()
end

local function EnsureSpellTextInputPersistHooks()
    local widgets = GetSpellSettingsWidgets()
    if type(widgets) ~= "table" then
        return
    end
    for i = 1, #C.SPELL_TEXT_KEYS do
        local key = C.SPELL_TEXT_KEYS[i]
        local widget = widgets[key]
        if widget and widget.SetScript then
            local function UpdatePlaceholder()
                if widget.placeholder and widget.GetText then
                    if widget:GetText() == "" then
                        widget.placeholder:Show()
                    else
                        widget.placeholder:Hide()
                    end
                end
            end
            widget:SetScript("OnTextChanged", function(self, userInput)
                UpdatePlaceholder()
                if userInput ~= true then
                    return
                end
                local text = GetWidgetEditText(self)
                if text ~= nil then
                    if STATE.spellTextFormState[key] ~= tostring(text) then
                        SetSpellTextFormStateValue(key, text)
                        STATE.spellTextDraftRevision = (tonumber(STATE.spellTextDraftRevision) or 0) + 1
                        STATE.spellSettingsDirty = true
                    end
                end
                ScheduleSpellTextPersist(key)
            end)
            widget:SetScript("OnEditFocusGained", function(self)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(0.64, 0.19, 0.79, 1)
                end
            end)
            widget:SetScript("OnEditFocusLost", function(self)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
                UpdatePlaceholder()
                local text = GetWidgetEditText(self)
                if text ~= nil then
                    SetSpellTextFormStateValue(key, text)
                end
                CancelPendingSpellTextPersist(key)
                CommitSpellTextFormState(key)
            end)
            widget:SetScript("OnEnterPressed", function(self)
                local text = GetWidgetEditText(self)
                if text ~= nil then
                    SetSpellTextFormStateValue(key, text)
                end
                if self.ClearFocus then
                    self:ClearFocus()
                end
                CancelPendingSpellTextPersist(key)
                CommitSpellTextFormState(key)
            end)
            widget:SetScript("OnEscapePressed", function(self)
                if self.ClearFocus then
                    self:ClearFocus()
                end
            end)
            UpdatePlaceholder()
        end
    end
end

local function RunSilentSpellSettingsPopulate(fn)
    STATE.suspendSpellSettingPersist = true
    if coroutine.running() then
        -- 协程内不能跨 pcall 边界 yield（Lua 5.1 限制）
        -- 错误由 LibAsync errorHandler 捕获
        fn()
        STATE.suspendSpellSettingPersist = false
    else
        local ok, err = pcall(fn)
        STATE.suspendSpellSettingPersist = false
        if not ok then
            error(err)
        end
    end
end

-- 该 key 只用于 Grid 的 UI 事件命名；它不是持久化配置 owner。
SETTINGS.EDITOR_KEY = "ExBoss.BossPage.SpellEditor"
SETTINGS.DEFAULTS = {
    enabled = true,
    centralEnabled = false,
    centralLead = 0,
    centralText = "",
    countdownEnabled = true,
    countdownLead = "5",
    countdownVoiceEnabled = false,
    countdownPlayName = false,
    preAlertEnabled = true,
    preAlert = C.PREALERT_FIXED_SECS,
    preAlertText = "",
    timerBarRenameEnabled = false,
    timerBarRenameText = "",
    showBunBar = true,
    showTimerBar = true,
    ringEnabled = false,
    castProgressBarEnabled = false,
    castProgressBarRenameEnabled = false,
    castProgressBarRenameText = "",
    ringCastCheckEnabled = false,
    tr0Enabled = false,
    tr0Source = "pack",
    tr0Label = "",
    tr0LSM = "",
    tr0Path = "",
    tr0TtsText = "",
    tr1Enabled = true,
    tr1Source = "pack",
    tr1Label = "",
    tr1LSM = "",
    tr1Path = "",
    tr1TtsText = "",
    tr1OffsetMode = "delay",
    tr1OffsetSeconds = "0",
    tr2Enabled = false,
    tr2CountdownLead = "5",
    tr2PlayTextEnabled = false,
    tr2Source = "pack",
    tr2Label = "",
    tr2LSM = "",
    tr2Path = "",
    tr2TtsText = "",
    tr2OffsetMode = "delay",
    tr2OffsetSeconds = "0",
    eventColorEnabled = false,
    eventColorMode = "cooldown",
    eventColorR = 1,
    eventColorG = 0.82,
    eventColorB = 0.25,
    targetAlertStartEnabled = false,
    targetAlertStartSource = "lsm",
    targetAlertStartLabel = "",
    targetAlertStartLSM = "",
    targetAlertStartPath = "",
    targetAlertStartTtsText = "",
    -- 旧配置未保存该字段时保持原本「选择音效即播放」的行为。
    targetAlertVoiceEnabled = true,
    targetAlertTankEnabled = false,
    targetAlertRingEnabled = false,
    targetAlertIconEnabled = false,
    targetAlertTextEnabledV2 = false,
    targetAlertStealthEnabledV2 = false,
}

-- BOSS页面法术卡片右侧 被点名提示 图标测试（按 eventID）
ExBoss.TargetAlert = ExBoss.TargetAlert or {}
ExBoss.TargetAlert.SupportedBossEventIDs = {
    [298] = true,
    [224] = true,
    [275] = true,
    [241] = true,
    [22] = true,
    [155] = true,
    [107] = true,
    [153] = true,
    [157] = true,
    [166] = true,
}
local BOSS_TEST_TARGET_ALERT_EVENT_IDS = ExBoss.TargetAlert.SupportedBossEventIDs
local BOSS_TEST_TARGET_ALERT_ATLAS = "Ping_Marker_Icon_Threat"
local BOSS_TEST_TARGET_ALERT_TOOLTIP = "可设置「被点名提示」!"

local function ShouldShowBossTargetAlertTestIcon(eventID)
    return BOSS_TEST_TARGET_ALERT_EVENT_IDS[tonumber(eventID)] == true
end
local SETTINGS_LAYOUT = {}
local _spellDescMeasureFS


-- 固定使用你确认的映射（EncounterEventIconmask）
-- 1 Deadly, 2 Enrage, 4 Bleed, 8 Magic, 16 Disease, 32 Curse, 64 Poison,
-- 128 Tank, 256 Healer, 512 Dps
local ALERT_FLAG_DEFS = {
    {
        name = "deadly",
        bit = 1,
        atlases = { "icons_64x64_deadly", "combattimeline-fx-deadlyglow-base", "common-icon-redx" },
        texture = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", width = 64, height = 64, left = 0, right = 1, top = 0, bottom = 1 },
    },
    {
        name = "enrage",
        bit = 2,
        atlases = { "icons_64x64_enrage" },
        texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", width = 64, height = 64, left = 0, right = 1, top = 0, bottom = 1 },
    },
    {
        name = "bleed",
        bit = 4,
        atlases = { "icons_64x64_bleed", "UI-Debuff-Border-Bleed-Icon" },
        texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", width = 64, height = 64, left = 0, right = 1, top = 0, bottom = 1 },
    },
    { name = "magic",   bit = 8,  atlases = { "icons_64x64_magic", "RaidFrame-Icon-DebuffMagic", "UI-HUD-CoolDownManager-Debuff-Magic" } },
    { name = "disease", bit = 16, atlases = { "icons_64x64_disease", "RaidFrame-Icon-DebuffDisease", "UI-HUD-CoolDownManager-Debuff-Disease" } },
    { name = "curse",   bit = 32, atlases = { "icons_64x64_curse", "RaidFrame-Icon-DebuffCurse", "UI-HUD-CoolDownManager-Debuff-Curse" } },
    { name = "poison",  bit = 64, atlases = { "icons_64x64_poison", "RaidFrame-Icon-DebuffPoison", "UI-HUD-CoolDownManager-Debuff-Poison" } },
    {
        name = "tank",
        bit = 128,
        atlases = { "icons_64x64_tank", "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "UI-LFG-RoleIcon-Tank-Micro", "UI-LFG-RoleIcon-Tank" },
        texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", width = 64, height = 64, left = 0, right = 19 / 64, top = 22 / 64, bottom = 41 / 64 },
    },
    {
        name = "heal",
        bit = 256,
        atlases = { "icons_64x64_heal", "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "UI-LFG-RoleIcon-Healer-Micro", "UI-LFG-RoleIcon-Healer" },
        texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", width = 64, height = 64, left = 20 / 64, right = 39 / 64, top = 1 / 64, bottom = 20 / 64 },
    },
    {
        name = "damage",
        bit = 512,
        atlases = { "icons_64x64_damage", "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "UI-LFG-RoleIcon-DPS-Micro", "UI-LFG-RoleIcon-DPS" },
        texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", width = 64, height = 64, left = 20 / 64, right = 39 / 64, top = 22 / 64, bottom = 41 / 64 },
    },
}
local ALERT_ICON_SIZE = 20
local ALERT_ICON_Y_OFFSET = 1
local function GetPanelDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ui = EXBOSS12S2.ui or {}
    EXBOSS12S2.ui.panel = EXBOSS12S2.ui.panel or {}
    return EXBOSS12S2.ui.panel
end

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function GetSlotCategory(slotKey)
    if slotKey == "mplus_tank" or slotKey == "mplus_dps" or slotKey == "mplus_heal" then return "mplus" end
    if slotKey == "raid_tank" or slotKey == "raid_dps" or slotKey == "raid_heal" then return "raid" end
    return nil
end

local function GetRuntimeEventConfig(eventID, slotKey)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local cfg = GetBossConfig()
    local category = GetSlotCategory(slotKey)
    if cfg and category and cfg.GetRuntimeConfig then
        local runtime = cfg:GetRuntimeConfig(category, slotKey)
        return type(runtime) == "table" and type(runtime.events) == "table" and runtime.events[eid] or nil
    end
    return nil
end

-- Grid writes its display state before Core dispatches the module refresh. This
-- state belongs only to the current controls; it is never a configuration
-- snapshot and is immediately persisted through the current Runtime path.
local GRID_DRAFT_FIELDS = {
    enabled = true, centralEnabled = true, centralLead = true, centralText = true,
    countdownEnabled = true, tr2CountdownLead = true, preAlertText = true,
    timerBarRenameEnabled = true, timerBarRenameText = true,
    showBunBar = true, showTimerBar = true,
    ringEnabled = true, castProgressBarEnabled = true, castProgressBarRenameEnabled = true,
    castProgressBarRenameText = true, ringCastCheckEnabled = true,
    tr0Enabled = true, tr0Source = true, tr0Label = true, tr0LSM = true, tr0Path = true, tr0TtsText = true,
    tr1Enabled = true, tr1Source = true, tr1Label = true, tr1LSM = true, tr1Path = true, tr1TtsText = true,
    tr2Enabled = true, tr2PlayTextEnabled = true, tr2Source = true, tr2Label = true, tr2LSM = true, tr2Path = true, tr2TtsText = true,
    eventColorEnabled = true, eventColorMode = true,
    targetAlertStartEnabled = true, targetAlertStartSource = true, targetAlertStartLabel = true,
    targetAlertStartLSM = true, targetAlertStartPath = true, targetAlertStartTtsText = true,
    targetAlertVoiceEnabled = true, targetAlertRingEnabled = true, targetAlertIconEnabled = true,
    targetAlertTextEnabledV2 = true, targetAlertStealthEnabledV2 = true,
}

local function ApplyGridChangeToSpellEditorDraft(info)
    local key, value = type(info) == "table" and info.key or nil, type(info) == "table" and info.value
    local draft = STATE.spellEditorDraft
    if GRID_DRAFT_FIELDS[key] ~= true or type(draft) ~= "table" or value == nil then return end
    if IsSpellTextKey(key) then
        local stored = tostring(ResolveDisplayedSpellTextForStorage(key, value) or "")
        draft[key] = stored
        STATE.spellTextFormState[key] = stored
    else
        draft[key] = value
    end
end

local function SetCurrentEventPath(eventID, slotKey, suffix, value)
    if value == nil then return false, "nil cannot be saved as a user value" end
    local api = _G.EXBossData
    local cfg = GetBossConfig()
    local category = GetSlotCategory(slotKey)
    local current = type(api) == "table" and api.GetCurrentConfiguration and api.GetCurrentConfiguration(category) or nil
    local selected = cfg and cfg.GetSelectedUser and cfg:GetSelectedUser(slotKey) or nil
    if not (type(api) == "table" and type(api.SetCurrentUserPath) == "function"
        and category and type(current) == "table"
        and current.category == category and current.userID == selected) then
        return false, "current Runtime does not match the editor slot"
    end
    local path = { "events", tonumber(eventID) }
    for index = 1, #suffix do path[#path + 1] = suffix[index] end
    return api.SetCurrentUserPath(category, path, value)
end

local function GetColorSchemeModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

local function ResolveVoiceEventBorderColor(eventID)
    local function ClampColor(v, fallback)
        local n = tonumber(v)
        if n == nil then
            return fallback or 0
        end
        if n < 0 then return 0 end
        if n > 1 then return 1 end
        return n
    end

    local eid = tonumber(eventID)
    if not eid then
        return nil
    end

    local slotKey = STATE.currentSpellSlotKey
    local category = GetSlotCategory(slotKey)
    local bossConfig = GetBossConfig()
    local runtime = bossConfig and category and bossConfig:GetRuntimeConfig(category, slotKey)
    local cfg = type(runtime) == "table" and type(runtime.events) == "table" and runtime.events[eid] or nil
    if type(cfg) ~= "table" then
        return nil
    end

    local colorCfg = cfg.color
    if type(colorCfg) ~= "table" or colorCfg.enabled == false then
        return nil
    end

    local CS = GetColorSchemeModule()
    if CS and CS.ResolveEventColor then
        local r, g, b = CS.ResolveEventColor(colorCfg)
        if r ~= nil and g ~= nil and b ~= nil then
            return ClampColor(r, 1), ClampColor(g, 1), ClampColor(b, 1)
        end
    end

    if colorCfg.r ~= nil and colorCfg.g ~= nil and colorCfg.b ~= nil then
        return ClampColor(colorCfg.r, 1), ClampColor(colorCfg.g, 1), ClampColor(colorCfg.b, 1)
    end

    if CS and CS.GetSchemeColor and type(colorCfg.scheme) == "string" and colorCfg.scheme ~= "" then
        local r, g, b = CS.GetSchemeColor(colorCfg.scheme)
        if r ~= nil and g ~= nil and b ~= nil then
            return ClampColor(r, 1), ClampColor(g, 1), ClampColor(b, 1)
        end
    end

    return nil
end

local function NormalizeEventColorMode(mode)
    local CS = GetColorSchemeModule()
    if CS and CS.NormalizeSchemeKey and CS.GetCustomKey then
        local n = CS.NormalizeSchemeKey(mode)
        if n then return n end
        return CS.GetCustomKey()
    end
    local s = tostring(mode or "")
    if s == "tank" or s == "heal" or s == "target" or s == "cooldown" or s == "mechanic" then
        return s
    end
    return "__custom"
end

local function Clamp01(v, fallback)
    local n = tonumber(v)
    if not n then return fallback or 0 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

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

local function NormalizeTriggerSource(v)
    local s = tostring(v or ""):lower()
    if s == "lsm" or s == "file" or s == "tts" then
        return s
    end
    return "pack"
end

local function NormalizeTriggerOffsetMode(v)
    local s = tostring(v or ""):lower()
    if s == "early" then
        return "early"
    end
    return "delay"
end

local function NormalizeTriggerOffsetSeconds(v)
    local n = tonumber(v)
    if not n then
        n = 0
    end
    if n < 0 then n = 0 end
    if n > 30 then n = 30 end
    return n
end

local function NormalizeCountdownLeadSeconds(v)
    local n = tonumber(v)
    if not n then
        n = C.PREALERT_FIXED_SECS
    end
    n = math.floor(n + 0.0001)
    if n < 1 then n = 1 end
    if n > 9 then n = 9 end
    return n
end

local function GetEventVoiceConfig(eventID, slotKey)
    local eid = tonumber(eventID)
    if not eid then return nil end
    if not GetSlotCategory(slotKey) then return nil end
    local cfg = GetRuntimeEventConfig(eid, slotKey)
    if type(cfg) ~= "table" then return nil end
    return cfg
end

local function NormalizeOptionText(v)
    if type(v) ~= "string" then return "" end
    local t = v:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

local function IsLegacyEmptyPackLabel(v)
    local t = NormalizeOptionText(v)
    if t == "" then
        return true
    end
    return t == "无" or t:lower() == "none"
end

local function NormalizeTriggerPackLabel(triggerIndex, sourceType, label)
    if NormalizeTriggerSource(sourceType) ~= "pack" then
        return NormalizeOptionText(label)
    end
    if tonumber(triggerIndex) == 2 then
        local normalized = NormalizeOptionText(label)
        if IsLegacyEmptyPackLabel(label) then
            return ""
        end
        return normalized
    end
    if IsLegacyEmptyPackLabel(label) then
        return ""
    end
    return NormalizeOptionText(label)
end

local function UTF8Left(text, maxChars)
    local s = tostring(text or "")
    local n = tonumber(maxChars) or 0
    if n <= 0 or s == "" then
        return ""
    end

    if type(strlenutf8) == "function" then
        local okLen = strlenutf8(s)
        if okLen and okLen <= n then
            return s
        end
    end

    local i, chars, bytes = 1, 0, #s
    while i <= bytes and chars < n do
        local c = string.byte(s, i)
        local step = 1
        if c and c >= 240 then
            step = 4
        elseif c and c >= 224 then
            step = 3
        elseif c and c >= 192 then
            step = 2
        end
        i = i + step
        chars = chars + 1
    end
    return string.sub(s, 1, i - 1)
end

local function GetTimelineModeDB()
    if _G.EXBossData and _G.EXBossData.GetTimelineModeDB then
        return _G.EXBossData.GetTimelineModeDB()
    end
    -- 兜底：EXBossData 未加载时回退到 EXBOSS12S2
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.timer = EXBOSS12S2.timer or {}
    EXBOSS12S2.timer.timelineMode = EXBOSS12S2.timer.timelineMode or {}
    local tdb = EXBOSS12S2.timer.timelineMode
    if type(tdb.byEncounter) ~= "table" then
        tdb.byEncounter = {}
    end
    if type(tdb.default) ~= "string" or tdb.default == "" then
        tdb.default = "auto"
    end
    return tdb
end

local function NormalizeTimelineMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "auto" or m == "fixed" or m == "blizzard" then
        return m
    end
    return "auto"
end

local function IsFixedTimelineAvailable(encounterID)
    local id = tonumber(encounterID)
    if not id then return false end
    local set = _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS
    if type(set) ~= "table" or set[id] ~= true then
        return false
    end
    local def = ExBoss and ExBoss.Timeline and ExBoss.Timeline._bosses and ExBoss.Timeline._bosses[id]
    return type(def) == "table" and type(def.skills) == "table" and #def.skills > 0
end

local function GetEncounterModeOverride(encounterID)
    if not encounterID then return "auto" end
    local tdb = GetTimelineModeDB()
    local by = tdb.byEncounter
    if type(by) ~= "table" then
        by = {}
        tdb.byEncounter = by
    end
    local mode = by[encounterID]
    if mode == nil then
        mode = by[tostring(encounterID)]
    end
    if mode == nil or mode == "" then
        mode = "auto"
    end
    return NormalizeTimelineMode(mode)
end

local function SetEncounterModeOverride(encounterID, mode)
    if not encounterID then return end
    local tdb = GetTimelineModeDB()
    local by = tdb.byEncounter
    if type(by) ~= "table" then
        by = {}
        tdb.byEncounter = by
    end
    mode = NormalizeTimelineMode(mode)
    by[encounterID] = mode
    by[tostring(encounterID)] = mode
end

local function GetEncounterAxisType(encounterID)
    if IsFixedTimelineAvailable(encounterID) then
        return "fixed"
    end
    return "blizzard"
end

local function ResolveEffectiveMode(encounterID)
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched.GetResolvedMode then
        return NormalizeTimelineMode(sched:GetResolvedMode(encounterID))
    end

    local override = GetEncounterModeOverride(encounterID)
    if override ~= "auto" then
        return override
    end
    return GetEncounterAxisType(encounterID)
end

local function GetModeDisplay(mode)
    mode = NormalizeTimelineMode(mode)
    if mode == "fixed" then
        return L["固定时间轴"]
    elseif mode == "blizzard" then
        return L["暴雪轴"]
    end
    return L["自动"]
end

local function GetAsyncHandler()
    if STATE.asyncHandler and STATE.asyncHandler ~= false then
        return STATE.asyncHandler
    end
    local lib = LibStub and LibStub("LibAsync", true)
    if not lib then
        STATE.asyncHandler = nil
        return nil
    end
    STATE.asyncHandler = lib:GetHandler({
        type = "everyFrame",
        maxTime = 6,
        maxTimeCombat = 4,
        errorHandler = geterrorhandler(),
    })
    return STATE.asyncHandler
end

local _eventDataCache
local _eventDataSource
local _challengeMapLookup

local function DeepCopyShallow(src)
    if type(src) ~= "table" then
        return {}
    end
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

local function NormalizeMapNameKey(name)
    local s = tostring(name or ""):lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

local function GetChallengeMapLookup()
    if _challengeMapLookup ~= nil then
        return _challengeMapLookup
    end

    local lookup = {}
    if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function"
        and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local ok, idList = pcall(C_ChallengeMode.GetMapTable)
        if ok and type(idList) == "table" then
            for _, cmID in ipairs(idList) do
                local okInfo, name, _, _, icon = pcall(C_ChallengeMode.GetMapUIInfo, cmID)
                if okInfo and type(name) == "string" and name ~= "" then
                    local key = NormalizeMapNameKey(name)
                    if key ~= "" and not lookup[key] then
                        lookup[key] = {
                            id = tonumber(cmID),
                            icon = icon,
                        }
                    end
                end
            end
        end
    end

    _challengeMapLookup = lookup
    return _challengeMapLookup
end

local function NormalizeBossEvents(events)
    if type(events) ~= "table" then
        return {}
    end

    local out = {}
    local blacklistAPI = _G.EXBossData and _G.EXBossData.IsEventBlacklisted
    for eventID, eventRow in pairs(events) do
        local eid = type(eventRow) == "table" and (tonumber(eventRow.eventID) or tonumber(eventID)) or tonumber(eventID)
        if type(eventRow) == "table" and not (blacklistAPI and blacklistAPI(eid)) then
            local row = DeepCopyShallow(eventRow)
            row.eventID = eid
            local localizedName = row.name or row.eventName or (row.eventID and (L["事件 "] .. tostring(row.eventID))) or
                L["未知事件"]
            if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
                localizedName = tostring(ExBoss.Locale.TranslateBossDynamicText(localizedName) or "")
            end
            row.name = localizedName
            out[#out + 1] = row
        end
    end

    table.sort(out, function(a, b)
        local aFirst = tonumber(a.firstSeenSec)
        local bFirst = tonumber(b.firstSeenSec)
        if aFirst ~= nil or bFirst ~= nil then
            if aFirst == nil then return false end
            if bFirst == nil then return true end
            if aFirst ~= bFirst then
                return aFirst < bFirst
            end
        end
        return (tonumber(a.eventID) or 0) < (tonumber(b.eventID) or 0)
    end)

    return out
end

local function NormalizeMapBosses(mapRow, bosses)
    if type(bosses) ~= "table" then
        return {}
    end

    local orderIndex = {}
    local bossOrder = type(mapRow) == "table" and mapRow.bossOrder or nil
    if type(bossOrder) == "table" then
        for idx, encounterID in ipairs(bossOrder) do
            local eid = tonumber(encounterID)
            if eid then
                orderIndex[eid] = idx
            end
        end
    end

    local out = {}
    for bossKey, bossRow in pairs(bosses) do
        if type(bossRow) == "table" then
            local row = DeepCopyShallow(bossRow)
            row.encounterID = tonumber(row.encounterID) or tonumber(bossKey)
            row._rawName = row.name or row.bossName -- 保留原始名用于 key 和 bosses 匹配
            row.name = ResolveLocalizedDisplayName(
                row.name or row.bossName or (row.encounterID and (L["首领 "] .. tostring(row.encounterID))) or L["未知首领"],
                row.zhCN,
                nil,
                nil,
                row.encounterID
            )
            row.events = NormalizeBossEvents(row.events)
            out[#out + 1] = row
        end
    end

    table.sort(out, function(a, b)
        local aOrder = tonumber(a.bossOrder) or orderIndex[tonumber(a.encounterID)] or math.huge
        local bOrder = tonumber(b.bossOrder) or orderIndex[tonumber(b.encounterID)] or math.huge
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        return (tonumber(a.encounterID) or 0) < (tonumber(b.encounterID) or 0)
    end)

    return out
end

local function GetEventData()
    local source = _G.EXBossData and _G.EXBossData.GetEncounterDataRoot and _G.EXBossData.GetEncounterDataRoot()
    if type(source) ~= "table" then
        source = _G.EXBOSS_ENCOUNTER_DATA and _G.EXBOSS_ENCOUNTER_DATA.maps or _G.EXBOSS_ENCOUNTER_DATA
    end
    if _eventDataCache and _eventDataSource == source then
        return _eventDataCache
    end

    local out = {}
    local challengeLookup = GetChallengeMapLookup()
    for mapID, mapRow in pairs(source or {}) do
        if type(mapRow) == "table" then
            local id = tonumber(mapRow.mapID) or tonumber(mapID)
            if id then
                local mapName = ResolveLocalizedDisplayName(
                    mapRow.mapName or mapRow.name or (L["副本 "] .. tostring(id)),
                    mapRow.zhCN,
                    nil,
                    nil,
                    nil,
                    id
                )
                local challengeModeID = tonumber(mapRow.challengeModeID) or tonumber(mapRow.challengeMapID)
                local icon = mapRow.icon
                if not challengeModeID or challengeModeID <= 0 or not icon then
                    local hit = challengeLookup[NormalizeMapNameKey(mapName)]
                    if hit then
                        challengeModeID = challengeModeID or hit.id
                        icon = icon or hit.icon
                    end
                end
                out[id] = {
                    mapID = id,
                    name = mapName,
                    mapName = mapName,
                    _rawMapName = mapRow.mapName or mapRow.name,
                    season = mapRow.season,
                    category = mapRow.category,
                    instanceType = tonumber(mapRow.instanceType),
                    challengeModeID = challengeModeID,
                    icon = icon,
                    bosses = NormalizeMapBosses(mapRow, mapRow.bosses),
                }
            end
        end
    end

    _eventDataCache = out
    _eventDataSource = source
    return out
end

local function GetRawEncounterEventRow(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local data = GetEventData()
    for _, mapInfo in pairs(data or {}) do
        if type(mapInfo) == "table" and type(mapInfo.bosses) == "table" then
            for _, bossInfo in ipairs(mapInfo.bosses) do
                if type(bossInfo) == "table" and type(bossInfo.events) == "table" then
                    for _, eventRow in ipairs(bossInfo.events) do
                        if type(eventRow) == "table" and tonumber(eventRow.eventID) == eid then
                            return eventRow
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function BuildRawTestSkill(skill)
    if type(skill) ~= "table" then
        return nil
    end
    local raw = GetRawEncounterEventRow(skill.eventID)
    local out = {}
    for k, v in pairs(skill) do
        out[k] = v
    end
    if type(raw) == "table" then
        local rawName = tostring(raw.name or raw.eventName or "")
        if rawName ~= "" then
            local localizedName = rawName
            if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
                localizedName = tostring(ExBoss.Locale.TranslateBossDynamicText(rawName) or "")
            end
            out.name = localizedName
            out.displayName = localizedName
        end
        local rawSpell = tonumber(raw.evenSpellID) or tonumber(raw.spellID)
        if rawSpell and rawSpell > 0 then
            out.spellIdentifier = rawSpell
            out.evenSpellID = tonumber(raw.evenSpellID) or rawSpell
            out.spellID = tonumber(raw.spellID) or rawSpell
        end
        if raw.iconFileID ~= nil then
            out.iconFileID = raw.iconFileID
        end
        out.voiceLabel = raw.voiceLabel
        local localizedPreAlert = raw.preAlertText
        local localizedScreen = raw.centralText
        if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
            localizedPreAlert = tostring(ExBoss.Locale.TranslateBossDynamicText(raw.preAlertText) or "")
            localizedScreen = tostring(ExBoss.Locale.TranslateBossDynamicText(raw.centralText) or "")
        end
        out.preAlertText = localizedPreAlert
        out.screenText = localizedScreen
    end
    return out
end

local function BuildSeasonList()
    return { "12.1大秘境", "12.1团本", "12.0大秘境", "其他" }
end

local function GetMapCategoryKey(mapInfo)
    if type(mapInfo) ~= "table" then
        return "dungeon"
    end
    local instanceType = tonumber(mapInfo.instanceType)
    if instanceType == 2 then
        return "raid"
    end
    if instanceType == 1 then
        return "dungeon"
    end
    local category = tostring(mapInfo.category or "")
    if category:find("团") then
        return "raid"
    end
    return "dungeon"
end

local function BuildMapList(filterKey)
    local out = {}
    local added = {}
    local data = GetEventData()
    local key = tostring(filterKey or "12.1大秘境")

    local function AddOne(mapID)
        local id = tonumber(mapID)
        if not id or added[id] then return end
        local info = data[id]
        if not info or type(info.bosses) ~= "table" then return end
        local season   = tostring(info.season or "")
        local category = tostring(info.category or "")
        local is121    = season:sub(1, 4) == "12.1"
        local is120    = season:sub(1, 4) == "12.0"

        if key == "12.1大秘境" then
            if not (is121 and category == "大秘境") then return end
        elseif key == "12.1团本" then
            if not (is121 and GetMapCategoryKey(info) == "raid") then return end
        elseif key == "12.0大秘境" then
            if not (is120 and category == "大秘境") then return end
        elseif key == "其他" then
            if is120 or is121 or GetMapCategoryKey(info) ~= "dungeon" then return end
        else
            return
        end

        table.insert(out, id)
        added[id] = true
    end

    for mapID in pairs(data) do
        AddOne(mapID)
    end
    table.sort(out)

    return out
end

local function GetMapDisplayName(mapID)
    local info = GetEventData()[tonumber(mapID)]
    if info and info.name and info.name ~= "" then
        return ResolveLocalizedDisplayName(info.name, info.zhCN, nil, nil, nil, mapID)
    end
    if C_Map and C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(tonumber(mapID) or 0)
        if mapInfo and mapInfo.name and mapInfo.name ~= "" then
            return ResolveLocalizedDisplayName(mapInfo.name, nil, nil, nil, nil, mapID)
        end
    end
    return L["未知副本 "] .. tostring(mapID)
end

local function GetMapShortDisplayName(mapID)
    local id = tonumber(mapID)
    local locale = GetEffectiveDisplayLocale()
    if locale == "enGB" then locale = "enUS" end
    local EXDB = _G.EXDB or (ExwindTools and ExwindTools.DB_Static) or nil
    if id and EXDB and EXDB.InstanceNoteByMapID then
        local meta = EXDB.InstanceNoteByMapID[id]
        if meta then
            -- 仅 zhCN/enUS 有既有短名；其余语言必须显示自己的完整本地化名称。
            if locale ~= "zhCN" and locale ~= "enUS" then
                return GetMapDisplayName(id)
            end
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

local function GetMapIcon(mapID)
    local id = tonumber(mapID)
    local info = GetEventData()[id]
    local EXDB = _G.EXDB or ExwindTools.DB_Static

    if id and EXDB and type(EXDB.InstanceIconByMapID) == "table" then
        local icon = EXDB.InstanceIconByMapID[id]
        if icon then
            return icon
        end
    end
    if info and info.icon then
        return info.icon
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local cmID = info and tonumber(info.challengeModeID) or id
        if cmID and cmID > 0 then
            local _, _, _, icon = C_ChallengeMode.GetMapUIInfo(cmID)
            if icon then return icon end
        end
    end

    if info and tonumber(info.instanceType) == 2 then
        return "Interface\\LFGFrame\\LFGIcon-Raid"
    end
    return "Interface\\LFGFrame\\LFGIcon-Dungeon"
end

local function GetMapIconRenderStyle(mapID)
    local id = tonumber(mapID)
    local style = C.MAP_ICON_RENDER_OVERRIDES[id]
    if not style then
        local info = GetEventData()[id]
        local cmID = info and tonumber(info.challengeModeID) or nil
        if cmID then
            style = C.MAP_ICON_RENDER_OVERRIDES[cmID]
        end
    end
    if style then
        return style
    end
    return { scale = 1.0, tex = { 0.08, 0.92, 0.08, 0.92 }, offsetX = 0, offsetY = 0 }
end

local function HasFlag(value, bitMask)
    local v = tonumber(value) or 0
    local b = tonumber(bitMask) or 0
    if b <= 0 then
        return false
    end
    if bit32 and bit32.band then
        return bit32.band(v, b) ~= 0
    end
    if bit and bit.band then
        return bit.band(v, b) ~= 0
    end
    -- Power-of-two fallback.
    return (v % (b * 2)) >= b
end

local function IsAlertAtlasValid(atlasName)
    if not atlasName or atlasName == "" then
        return false
    end
    local cached = CARD_CACHE.alertAtlasExistCache[atlasName]
    if cached ~= nil then
        return cached
    end
    local valid = true
    if C_Texture and C_Texture.GetAtlasInfo then
        valid = C_Texture.GetAtlasInfo(atlasName) ~= nil
    end
    CARD_CACHE.alertAtlasExistCache[atlasName] = valid and true or false
    return CARD_CACHE.alertAtlasExistCache[atlasName]
end

local function BuildAlertIconMarkup(iconFlags, iconSize, iconYOffset)
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return ""
    end
    local renderSize = tonumber(iconSize) or ALERT_ICON_SIZE
    local renderYOffset = tonumber(iconYOffset) or ALERT_ICON_Y_OFFSET
    local marks = {}
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        local bitMask = tonumber(cfg.bit) or 0
        if bitMask > 0 and HasFlag(flags, bitMask) then
            local atlasList = cfg.atlases
            local added = false
            if type(atlasList) ~= "table" or #atlasList == 0 then
                atlasList = { "icons_64x64_" .. tostring(cfg.name or "") }
            end
            for _, atlas in ipairs(atlasList) do
                if IsAlertAtlasValid(atlas) then
                    if CreateAtlasMarkup then
                        marks[#marks + 1] = CreateAtlasMarkup(atlas, renderSize, renderSize, 0, renderYOffset)
                    else
                        marks[#marks + 1] = string.format(
                            "|A:%s:%d:%d:0:%d|a",
                            atlas,
                            renderSize,
                            renderSize,
                            renderYOffset
                        )
                    end
                    added = true
                    break
                end
            end
            if (not added) and cfg.texture and cfg.texture.file and cfg.texture.file ~= "" then
                local tex = cfg.texture
                if CreateTextureMarkup then
                    marks[#marks + 1] = CreateTextureMarkup(
                        tex.file,
                        tonumber(tex.width) or 64,
                        tonumber(tex.height) or 64,
                        renderSize,
                        renderSize,
                        tonumber(tex.left) or 0,
                        tonumber(tex.right) or 1,
                        tonumber(tex.top) or 0,
                        tonumber(tex.bottom) or 1,
                        0,
                        renderYOffset
                    )
                else
                    marks[#marks + 1] = string.format(
                        "|T%s:%d:%d:0:%d:%d:%d:%d:%d:%d:%d:%d|t",
                        tex.file,
                        renderSize,
                        renderSize,
                        renderYOffset,
                        tonumber(tex.width) or 64,
                        tonumber(tex.height) or 64,
                        math.floor((tonumber(tex.left) or 0) * (tonumber(tex.width) or 64)),
                        math.floor((tonumber(tex.right) or 1) * (tonumber(tex.width) or 64)),
                        math.floor((tonumber(tex.top) or 0) * (tonumber(tex.height) or 64)),
                        math.floor((tonumber(tex.bottom) or 1) * (tonumber(tex.height) or 64))
                    )
                end
            end
        end
    end
    return table.concat(marks, " ")
end

local function GetEventIconFlags(event)
    if type(event) ~= "table" then
        return 0
    end
    local flags = tonumber(event.iconFlags)
    if not flags then
        flags = tonumber(event.icons)
    end
    return flags or 0
end

local function GetVoiceEventColorConfig(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local cfg = GetRuntimeEventConfig(eid, STATE.currentSpellSlotKey)
    if type(cfg) ~= "table" or type(cfg.color) ~= "table" or cfg.color.enabled == false then
        return nil
    end
    return cfg.color
end

local function ColorDistanceSq(r1, g1, b1, r2, g2, b2)
    local ar, ag, ab = tonumber(r1), tonumber(g1), tonumber(b1)
    local br, bg, bb = tonumber(r2), tonumber(g2), tonumber(b2)
    if not (ar and ag and ab and br and bg and bb) then
        return math.huge
    end
    local dr, dg, db = ar - br, ag - bg, ab - bb
    return dr * dr + dg * dg + db * db
end

local function ResolvePrimaryAlertIconSourceByBorder(eventID, borderR, borderG, borderB)
    local iconKind = nil -- "tank" | "heal" | "target" | "deadly"
    local CS = GetColorSchemeModule()
    local colorCfg = GetVoiceEventColorConfig(eventID)

    if type(colorCfg) == "table" then
        local scheme = nil
        if colorCfg.useCustom == true then
            scheme = "__custom"
        else
            scheme = tostring(colorCfg.scheme or "")
        end
        if CS and CS.NormalizeSchemeKey then
            scheme = CS.NormalizeSchemeKey(scheme)
        end
        if scheme == "tank" then
            iconKind = "tank"
        elseif scheme == "heal" then
            iconKind = "heal"
        elseif scheme == "target" then
            iconKind = "target"
        elseif scheme == "mechanic" then
            iconKind = "deadly"
        end
    end

    if not iconKind then
        local ref = {}
        if CS and CS.GetSchemeColor then
            local tr, tg, tb = CS.GetSchemeColor("tank")
            local hr, hg, hb = CS.GetSchemeColor("heal")
            local xr, xg, xb = CS.GetSchemeColor("target")
            local mr, mg, mb = CS.GetSchemeColor("mechanic")
            ref = {
                tank = { r = tr, g = tg, b = tb },
                heal = { r = hr, g = hg, b = hb },
                target = { r = xr, g = xg, b = xb },
                mechanic = { r = mr, g = mg, b = mb },
            }
        else
            ref = {
                tank = { r = 0xC6 / 255, g = 0x9B / 255, b = 0x6C / 255 },
                heal = { r = 0x5F / 255, g = 0xFF / 255, b = 0x9D / 255 },
                target = { r = 0xFF / 255, g = 0x3B / 255, b = 0x30 / 255 },
                mechanic = { r = 0xDA / 255, g = 0x5B / 255, b = 0xFF / 255 },
            }
        end

        local bestKey, bestDist = nil, math.huge
        for key, c in pairs(ref) do
            local d = ColorDistanceSq(borderR, borderG, borderB, c.r, c.g, c.b)
            if d < bestDist then
                bestDist = d
                bestKey = key
            end
        end
        -- 只在足够接近三种方案色时才给图标，避免误判普通回退色。
        if bestDist <= 0.04 and bestKey then
            if bestKey == "tank" then
                iconKind = "tank"
            elseif bestKey == "heal" then
                iconKind = "heal"
            elseif bestKey == "target" then
                iconKind = "target"
            elseif bestKey == "mechanic" then
                iconKind = "deadly"
            end
        end
    end

    local candidates = nil
    if iconKind == "tank" then
        candidates = { atlases = { "icons_64x64_tank", "UI-LFG-RoleIcon-Tank", "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "UI-LFG-RoleIcon-Tank-Micro" } }
    elseif iconKind == "heal" then
        candidates = { atlases = { "icons_64x64_heal", "UI-LFG-RoleIcon-Healer", "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "UI-LFG-RoleIcon-Healer-Micro" } }
    elseif iconKind == "target" then
        candidates = {
            atlases = { "cursor_crosshairs_48", "Ping_Marker_Icon_Threat" },
            texture = "Interface\\AddOns\\EXBoss\\Media\\textures\\target2",
        }
    elseif iconKind == "deadly" then
        candidates = {
            atlases = { "icons_64x64_deadly", "combattimeline-fx-deadlyglow-base", "common-icon-redx" },
            texture =
            "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
        }
    else
        candidates = { atlases = { "Ping_Wheel_Icon_Warning_Disabled_Small" } }
    end

    for _, atlas in ipairs(candidates.atlases or {}) do
        if IsAlertAtlasValid(atlas) then
            return "atlas", atlas
        end
    end
    if candidates.texture and candidates.texture ~= "" then
        return "texture", candidates.texture
    end

    return nil, nil
end

local function BuildPrimaryCategoryMarkup(eventID, iconSize, iconYOffset)
    local borderR, borderG, borderB = ResolveVoiceEventBorderColor(eventID)
    if borderR == nil or borderG == nil or borderB == nil then
        borderR, borderG, borderB =
            C.DEFAULT_EVENT_BORDER_COLOR.r,
            C.DEFAULT_EVENT_BORDER_COLOR.g,
            C.DEFAULT_EVENT_BORDER_COLOR.b
    end

    local kind, source = ResolvePrimaryAlertIconSourceByBorder(eventID, borderR, borderG, borderB)
    local renderSize = tonumber(iconSize) or 18
    local renderYOffset = tonumber(iconYOffset) or 0
    if kind == "atlas" and source and source ~= "" then
        if CreateAtlasMarkup then
            return CreateAtlasMarkup(source, renderSize, renderSize, 0, renderYOffset)
        end
        return string.format("|A:%s:%d:%d:0:%d|a", source, renderSize, renderSize, renderYOffset)
    end
    if kind == "texture" and source and source ~= "" then
        if CreateTextureMarkup then
            return CreateTextureMarkup(source, 128, 128, renderSize, renderSize, 0, 1, 0, 1, 0, renderYOffset)
        end
        return string.format("|T%s:%d:%d:0:%d:128:128:0:128:0:128|t", source, renderSize, renderSize, renderYOffset)
    end
    return ""
end

local function ResolveBossDisplayID(boss)
    if type(boss) ~= "table" then
        return nil
    end

    local displayID = tonumber(boss.creatureDisplayID)
    if displayID and displayID > 0 then
        return displayID
    end

    local legacyPortraitID = tonumber(boss.portrait)
    if legacyPortraitID and legacyPortraitID > 0 then
        return legacyPortraitID
    end

    return nil
end

local function ApplyModelTune(model)
    if not model then return end
    if model.SetPortraitZoom then
        model:SetPortraitZoom(C.MODEL_TUNE.zoom)
    end
    if model.SetCamDistanceScale then
        model:SetCamDistanceScale(C.MODEL_TUNE.cam)
    end
    if model.SetPosition then
        model:SetPosition(C.MODEL_TUNE.posX, C.MODEL_TUNE.posY, C.MODEL_TUNE.posZ)
    end
    if model.SetFacing then
        model:SetFacing(C.MODEL_TUNE.facing)
    end
end

local function BuildBossList(mapID)
    local out = {}
    local info = GetEventData()[tonumber(mapID)]
    if not info or type(info.bosses) ~= "table" then
        return out
    end
    for i, boss in ipairs(info.bosses) do
        table.insert(out, { index = i, data = boss })
    end
    return out
end

local function GetCurrentBossListEntry()
    local list = BuildBossList(selectedMapID)
    local idx = tonumber(selectedBossIndex)
    if not idx or idx < 1 or idx > #list then
        return nil
    end
    return list[idx]
end

local function GetCurrentBoss()
    local entry = GetCurrentBossListEntry()
    if not entry then
        return nil
    end
    return entry.data
end

local function GetCurrentEncounterID()
    local boss = GetCurrentBoss()
    return boss and tonumber(boss.encounterID) or nil
end

local function GetCurrentMapInfo()
    return GetEventData()[tonumber(selectedMapID)]
end

local function EnsureCurrentSceneRuntime()
    local scene = GetMapCategoryKey(GetCurrentMapInfo()) == "raid" and "raid" or "mplus"
    local config = GetBossConfig()
    if config and type(config.EnsureSceneRuntime) == "function" then
        return config:EnsureSceneRuntime(scene)
    end
    return false, "Boss configuration unavailable"
end

function Page:GetCurrentDungeonCommonOptions()
    if GetMapCategoryKey(GetCurrentMapInfo()) == "raid" then return nil, {} end
    local registry = ExBoss and ExBoss.BossEncounters
    if not (registry and type(registry.GetDungeonOptionsForEncounter) == "function") then
        return nil, nil
    end
    local bosses = BuildBossList(selectedMapID)
    local fallbackDungeonKey = nil
    for i = 1, #bosses do
        local encounterID = bosses[i].data and bosses[i].data.encounterID
        local options, dungeonKey = registry:GetDungeonOptionsForEncounter(encounterID)
        if type(dungeonKey) == "string" and dungeonKey ~= "" then fallbackDungeonKey = dungeonKey end
        if type(options) == "table" and type(dungeonKey) == "string" and dungeonKey ~= "" and #options > 0 then
            return dungeonKey, options
        end
    end
    return fallbackDungeonKey, {}
end

function Page:GetCurrentDungeonCommonBosses()
    if GetMapCategoryKey(GetCurrentMapInfo()) == "raid" then return {} end
    local out = {}
    local exdb = _G.EXDB or (ExwindTools and ExwindTools.DB_Static)
    for _, entry in ipairs(BuildBossList(selectedMapID)) do
        local boss = entry.data
        local encounterID = tonumber(boss and boss.encounterID)
        local name = exdb and type(exdb.GetLocalizedEncounterNoteName) == "function"
            and exdb:GetLocalizedEncounterNoteName(encounterID) or nil
        if type(name) ~= "string" or name == "" or name == "未知首领" then
            name = tostring(boss and boss.name or (L["未知首领 "] .. tostring(entry.index)))
        end
        out[#out + 1] = { index = entry.index, encounterID = encounterID, name = name }
    end
    return out
end

local function GetCurrentSpellSlotKey()
    local cfg = GetBossConfig()
    if not (cfg and type(cfg.GetRuntimeSlotForScene) == "function") then
        return nil
    end
    -- Map UI 分类使用 `dungeon` / `raid`；配置合同使用 `mplus` / `raid`。
    -- 不能把 dungeon 直接交给 Boss Store：它没有 dungeon_* 槽位，会让
    -- M+ event 读取返回 nil，继而跳过完整编辑 Grid。
    local category = GetMapCategoryKey(GetCurrentMapInfo()) == "raid" and "raid" or "mplus"
    return cfg:GetRuntimeSlotForScene(category)
end

function Page:GetCurrentDungeonOptionsDB(dungeonKey)
    local slotKey = GetCurrentSpellSlotKey()
    -- Aura 页面使用当前 Runtime 的单一配置；这里仅保留 slot 供页面识别。
    return nil, slotKey
end

function Page:GetCurrentEncounterSettingsDB(encounterID)
    local cfg = GetBossConfig()
    local slotKey = GetCurrentSpellSlotKey()
    if not (cfg and slotKey) then
        return nil, nil
    end
    local category = GetSlotCategory(slotKey)
    local runtime = category and cfg:GetRuntimeConfig(category, slotKey)
    return type(runtime) == "table" and type(runtime.encounterOptions) == "table"
        and runtime.encounterOptions[tonumber(encounterID)] or nil, slotKey
end

local function PlayTargetAlertStartPreview(mdb)
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (type(mdb) == "table" and Engine and Engine.TryPlayStandaloneSound) then
        return
    end
    local sourceType = NormalizeTriggerSource(mdb.targetAlertStartSource)
    local triggerCfg = { enabled = true, sourceType = sourceType }
    if sourceType == "pack" then
        triggerCfg.label = tostring(mdb.targetAlertStartLabel or "")
    elseif sourceType == "lsm" then
        triggerCfg.customLSM = tostring(mdb.targetAlertStartLSM or "")
    elseif sourceType == "tts" then
        triggerCfg.ttsText = tostring(mdb.targetAlertStartTtsText or "")
    else
        triggerCfg.customPath = tostring(mdb.targetAlertStartPath or "")
    end
    Engine:TryPlayStandaloneSound(triggerCfg, "bosspage_target_alert_preview", { triggerIndex = 0 })
end

local function AddTestTimelineHandle(handle)
    if type(handle) == "table" and type(handle.Cancel) == "function" then
        STATE.testTimelineLoopHandles[#STATE.testTimelineLoopHandles + 1] = handle
    end
end

local function CancelTestTimelineHandles()
    for i = 1, #STATE.testTimelineLoopHandles do
        local h = STATE.testTimelineLoopHandles[i]
        if type(h) == "table" and type(h.Cancel) == "function" then
            pcall(h.Cancel, h)
        end
    end
    wipe(STATE.testTimelineLoopHandles)
end

local function AddTestTimelineCleanupHandle(handle)
    if type(handle) == "table" and type(handle.Cancel) == "function" then
        STATE.testTimelineCleanupHandles[#STATE.testTimelineCleanupHandles + 1] = handle
    end
end

local function CancelTestTimelineCleanupHandles()
    for i = 1, #STATE.testTimelineCleanupHandles do
        local h = STATE.testTimelineCleanupHandles[i]
        if type(h) == "table" and type(h.Cancel) == "function" then
            pcall(h.Cancel, h)
        end
    end
    wipe(STATE.testTimelineCleanupHandles)
end

local function RemoveOneTestTimelineScriptEvent(eventID)
    local eid = tonumber(eventID)
    if not (eid and eid > 0 and C_EncounterTimeline) then
        return
    end
    if ExBoss and ExBoss.TestTimelineScriptMeta then
        ExBoss.TestTimelineScriptMeta[eid] = nil
    end
    if C_EncounterTimeline.FinishScriptEvent then
        pcall(C_EncounterTimeline.FinishScriptEvent, eid)
    end
    if C_EncounterTimeline.CancelScriptEvent then
        pcall(C_EncounterTimeline.CancelScriptEvent, eid)
    end
end

local function ForceCancelTestTimelineScriptEvents()
    if C_EncounterTimeline then
        if C_EncounterTimeline.CancelAllScriptEvents then
            pcall(C_EncounterTimeline.CancelAllScriptEvents)
        end

        if C_EncounterTimeline.GetEventList and C_EncounterTimeline.GetEventInfo and C_EncounterTimeline.CancelScriptEvent then
            local okEvents, events = pcall(C_EncounterTimeline.GetEventList)
            if okEvents and type(events) == "table" then
                for i = 1, #events do
                    local eventID = tonumber(events[i])
                    if eventID and eventID > 0 then
                        local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
                        if okInfo and type(info) == "table" and tonumber(info.source) == C.TIMELINE_SOURCE_SCRIPT then
                            RemoveOneTestTimelineScriptEvent(eventID)
                        end
                    end
                end
            end
        end

        if C_EncounterTimeline.CancelScriptEvent or C_EncounterTimeline.FinishScriptEvent then
            for i = 1, #STATE.testTimelineScriptEventIDs do
                local eventID = tonumber(STATE.testTimelineScriptEventIDs[i])
                if eventID and eventID > 0 then
                    RemoveOneTestTimelineScriptEvent(eventID)
                end
            end
        end
    end
end

local function CancelTestTimelineScriptEvents()
    ForceCancelTestTimelineScriptEvents()
    wipe(STATE.testTimelineScriptEventIDs)
    if ExBoss and ExBoss.TestTimelineScriptMeta then
        wipe(ExBoss.TestTimelineScriptMeta)
    end
end

-- [DISABLED] ClearEncounterWarningsUI 已注释掉。
-- 原因：同 Scheduler.lua 中同名函数。在 tainted 执行上下文里调用会触发
-- Blizzard EncounterWarnings OnHide → ScaleTextToFit 对秘密宽度做算术运算，
-- 产生 taint 报错。暴雪警告框有自己的生命周期，EXBoss 无需主动清除。
-- 如需恢复：取消下方注释，并同步恢复 ClearEncounterWarningsUI() 调用处。
--
-- local function ClearEncounterWarningsUI()
--     local frames = {
--         _G.CriticalEncounterWarnings,
--         _G.MediumEncounterWarnings,
--         _G.MinorEncounterWarnings,
--     }
--     for i = 1, #frames do
--         local frame = frames[i]
--         if type(frame) == "table" then
--             if type(frame.ClearWarning) == "function" then
--                 pcall(frame.ClearWarning, frame)
--             elseif type(frame.HideWarning) == "function" then
--                 pcall(frame.HideWarning, frame)
--             end
--         end
--     end
--     local tooltip = _G.GameTooltip
--     if tooltip and type(tooltip.Hide) == "function" then
--         pcall(tooltip.Hide, tooltip)
--     end
-- end

local function BuildTestTimelinePreAlertText(skill)
    local rawSkill = BuildRawTestSkill(skill)
    if type(rawSkill) ~= "table" then
        return nil
    end
    local txt = NormalizeOptionText(rawSkill.preAlertText)
    if txt == "" then
        return nil
    end
    local name = NormalizeOptionText(rawSkill.displayName or rawSkill.name or "")
    if name ~= "" then
        txt = txt:gsub("{name}", name)
    else
        txt = txt:gsub("{name}", "")
    end
    return NormalizeOptionText(txt)
end

local function ScheduleTestTimelineCleanupPasses()
    CancelTestTimelineCleanupHandles()
    local delays = { 0.05, 0.20, 0.50, 1.00 }
    for i = 1, #delays do
        local delay = delays[i]
        local h = C_Timer.NewTimer(delay, function()
            ForceCancelTestTimelineScriptEvents()
        end)
        AddTestTimelineCleanupHandle(h)
    end
end

local function StopTestTimelineLoop(skipDelayedCleanup)
    STATE.testTimelineLoopActive = false
    if ExBoss and ExBoss.TestTimelineForceFixedTime then
        wipe(ExBoss.TestTimelineForceFixedTime)
    end
    CancelTestTimelineHandles()
    CancelTestTimelineCleanupHandles()
    CancelTestTimelineScriptEvents()
    -- ClearEncounterWarningsUI() -- [DISABLED] 见函数定义处注释
    if not skipDelayedCleanup then
        ScheduleTestTimelineCleanupPasses()
    end
end

local function NormalizeLoopDuration(v, fallback)
    local n = tonumber(v)
    if not n then
        n = tonumber(fallback) or 1
    end
    if n < 0.2 then n = 0.2 end
    if n > 600 then n = 600 end
    return n
end

local function ResolveScriptEventPriority(skill)
    local p = tonumber(skill and skill.barPriority)
    if p and p >= 3 then
        return 2
    end
    return 1
end

local function AddLoopScriptEvent(skill, duration)
    if not STATE.testTimelineLoopActive then return end
    if not (C_EncounterTimeline and C_EncounterTimeline.AddScriptEvent) then return end
    skill = BuildRawTestSkill(skill)
    if type(skill) ~= "table" then return end

    local spellID = tonumber(skill.spellIdentifier) or tonumber(skill.evenSpellID) or tonumber(skill.spellID)
    if not spellID or spellID <= 0 then return end

    local info = nil
    if C_Spell and C_Spell.GetSpellInfo then
        info = C_Spell.GetSpellInfo(spellID)
    end

    local req = {
        spellID = spellID,
        iconFileID = tonumber(skill.iconFileID) or (info and tonumber(info.iconID)) or 136243,
        duration = NormalizeLoopDuration(duration, 1),
        maxQueueDuration = 0,
        overrideName = tostring(skill.displayName or skill.name or (info and info.name) or
            (L["技能 "] .. tostring(spellID))),
        severity = ResolveScriptEventPriority(skill),
        paused = false,
    }

    local icons = tonumber(skill.icons)
    if icons and icons > 0 and icons <= 1023 then
        req.icons = icons
    end

    local ok, eventID = pcall(C_EncounterTimeline.AddScriptEvent, req)
    eventID = tonumber(eventID)
    if ok and eventID and eventID > 0 then
        STATE.testTimelineScriptEventIDs[#STATE.testTimelineScriptEventIDs + 1] = eventID
        if ExBoss and ExBoss.TestTimelineScriptMeta then
            ExBoss.TestTimelineScriptMeta[eventID] = {
                preAlertText = BuildTestTimelinePreAlertText(skill),
                eventID = tonumber(skill.eventID),
                spellIdentifier = spellID,
            }
        end
        if #STATE.testTimelineScriptEventIDs > 2000 then
            table.remove(STATE.testTimelineScriptEventIDs, 1)
        end
    end
end

local function StartSkillLoopScriptEvents(skill)
    skill = BuildRawTestSkill(skill)
    if type(skill) ~= "table" then return end

    local firstDelay = NormalizeLoopDuration(skill.first, 5)
    AddLoopScriptEvent(skill, firstDelay)

    local function StartFixedIntervalLoop(period)
        period = NormalizeLoopDuration(period, firstDelay)
        local firstHandle = C_Timer.NewTimer(firstDelay, function()
            if not STATE.testTimelineLoopActive then return end
            AddLoopScriptEvent(skill, period)
            local ticker = C_Timer.NewTicker(period, function()
                if not STATE.testTimelineLoopActive then return end
                AddLoopScriptEvent(skill, period)
            end)
            AddTestTimelineHandle(ticker)
        end)
        AddTestTimelineHandle(firstHandle)
    end

    local ivNum = tonumber(skill.interval)
    if ivNum and ivNum > 0 then
        StartFixedIntervalLoop(ivNum)
        return
    end

    if type(skill.interval) == "table" and #skill.interval > 0 then
        local seq = {}
        for i = 1, #skill.interval do
            local v = tonumber(skill.interval[i])
            if v and v > 0 then
                seq[#seq + 1] = NormalizeLoopDuration(v, firstDelay)
            end
        end
        if #seq > 0 then
            local idx = 1
            local function ScheduleNext(waitSecs)
                local timer = C_Timer.NewTimer(waitSecs, function()
                    if not STATE.testTimelineLoopActive then return end
                    local dur = seq[idx] or seq[1]
                    AddLoopScriptEvent(skill, dur)
                    idx = idx + 1
                    if idx > #seq then
                        idx = 1
                    end
                    ScheduleNext(dur)
                end)
                AddTestTimelineHandle(timer)
            end
            ScheduleNext(firstDelay)
            return
        end
    end

    -- 无 interval 数据时，按 first 间隔循环。
    StartFixedIntervalLoop(firstDelay)
end

local function StartTestTimelineLoop(encounterID)
    StopTestTimelineLoop(true)
    if not (C_EncounterTimeline and C_EncounterTimeline.AddScriptEvent) then
        return false
    end

    local bossDef = ExBoss and ExBoss.Timeline and ExBoss.Timeline._bosses and
        ExBoss.Timeline._bosses[tonumber(encounterID)]
    local skills = bossDef and bossDef.skills
    if type(skills) ~= "table" or #skills == 0 then
        return false
    end

    ExBoss.TestTimelineForceFixedTime = ExBoss.TestTimelineForceFixedTime or {}
    ExBoss.TestTimelineForceFixedTime.active = true
    ExBoss.TestTimelineForceFixedTime.encounterID = tonumber(encounterID)

    STATE.testTimelineLoopActive = true
    local started = 0
    for _, skill in ipairs(skills) do
        local rawSkill = BuildRawTestSkill(skill)
        local sid = type(rawSkill) == "table" and
            (tonumber(rawSkill.spellIdentifier) or tonumber(rawSkill.evenSpellID) or tonumber(rawSkill.spellID)) or nil
        if sid and sid > 0 then
            StartSkillLoopScriptEvents(rawSkill)
            started = started + 1
        end
    end

    if started <= 0 then
        StopTestTimelineLoop()
        return false
    end

    return true
end

local testTimelineEventFrame = CreateFrame("Frame")
testTimelineEventFrame:RegisterEvent("ENCOUNTER_END")
testTimelineEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
testTimelineEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
testTimelineEventFrame:SetScript("OnEvent", function(_, event)
    if not STATE.testTimelineLoopActive then
        return
    end
    StopTestTimelineLoop()
end)

local function GetEventID(event)
    if type(event) ~= "table" then return nil end
    return tonumber(event.eventID)
end

local function GetEventSpellIdentifier(event)
    if type(event) ~= "table" then return nil end
    return tonumber(event.evenSpellID) or tonumber(event.spellID)
end

local function EventExistsOnCurrentBoss(eventID)
    local eid = tonumber(eventID)
    if not eid then return false end
    local boss = GetCurrentBoss()
    if not (boss and type(boss.events) == "table") then
        return false
    end
    for _, event in ipairs(boss.events) do
        if GetEventID(event) == eid then
            return true
        end
    end
    return false
end

local function EnsureSelectedEvent()
    if selectedBossCommonSettings then
        return
    end
    selectedBossCommonSettings = nil
    local boss = GetCurrentBoss()
    if not (boss and type(boss.events) == "table" and #boss.events > 0) then
        selectedEventID = nil
        return
    end
    if selectedEventID and EventExistsOnCurrentBoss(selectedEventID) then
        return
    end
    for _, event in ipairs(boss.events) do
        local eid = GetEventID(event)
        if eid then
            selectedEventID = eid
            return
        end
    end
    selectedEventID = nil
end

local function GetRuntimeSpellConfig(eventID, slotKey)
    eventID = tonumber(eventID)
    if not eventID or not GetSlotCategory(slotKey) then return nil end
    return GetRuntimeEventConfig(eventID, slotKey)
end

local function IsSpellDataReady(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellDataCached then
        local ok, cached = pcall(C_Spell.IsSpellDataCached, spellID)
        if ok then return cached and true or false end
    end
    return true
end

local function RequestSpellDataLoad(spellID)
    if not spellID then return end
    if not (C_Spell and C_Spell.RequestLoadSpellData) then return end
    if CARD_CACHE.spellCachePending[spellID] then return end
    CARD_CACHE.spellCachePending[spellID] = true
    pcall(C_Spell.RequestLoadSpellData, spellID)
end

local function PrimeSpellCache(events)
    for _, event in ipairs(events or {}) do
        local spellID = GetEventSpellIdentifier(event)
        if spellID and not IsSpellDataReady(spellID) then
            RequestSpellDataLoad(spellID)
        end
    end
end

local function CurrentBossHasSpellID(spellID)
    if not spellID then return false end
    local boss = GetCurrentBoss()
    if not (boss and type(boss.events) == "table") then
        return false
    end
    local sid = tonumber(spellID)
    for _, event in ipairs(boss.events) do
        local identifier = GetEventSpellIdentifier(event)
        if identifier == sid then
            return true
        end
    end
    return false
end

local function GetSpellNameAndIcon(spellID)
    if not spellID then
        return nil, 134400
    end
    local cached = CARD_CACHE.spellTextCache[spellID]
    if type(cached) == "table" and cached.name ~= nil and cached.icon ~= nil then
        return cached.name, cached.icon
    end
    local name = nil
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, apiName = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(apiName) == "string" and apiName ~= "" then
            name = apiName
        end
    end
    local icon = 134400
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            icon = info.iconID or 134400
            if not name then
                local infoName = type(info.name) == "string" and info.name or nil
                if infoName and infoName ~= "" then
                    name = infoName
                end
            end
        end
    end
    if name ~= nil then
        CARD_CACHE.spellTextCache[spellID] = CARD_CACHE.spellTextCache[spellID] or {}
        CARD_CACHE.spellTextCache[spellID].name = name
        CARD_CACHE.spellTextCache[spellID].icon = icon
        return name, icon
    end
    return nil, 134400
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
    if body == "" then
        return ""
    end
    if type(color) ~= "table" then
        return body
    end
    local r = math.floor((tonumber(color.r) or 1) * 255 + 0.5)
    local g = math.floor((tonumber(color.g) or 1) * 255 + 0.5)
    local b = math.floor((tonumber(color.b) or 1) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, body)
end

local function GetSpellDescription(spellID)
    if not spellID then
        return L["暂无描述。"]
    end
    local cached = CARD_CACHE.spellTextCache[spellID]
    if type(cached) == "table" and type(cached.desc) == "string" and cached.desc ~= "" then
        return cached.desc
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
                        table.insert(lines, WrapColorText(text, line.leftColor))
                    end
                end
            end
            if #lines > 0 then
                local desc
                if #lines >= 2 then
                    desc = "\n" .. lines[1] .. "\n\n" .. table.concat(lines, "\n", 2)
                else
                    desc = "\n" .. table.concat(lines, "\n")
                end
                CARD_CACHE.spellTextCache[spellID] = CARD_CACHE.spellTextCache[spellID] or {}
                CARD_CACHE.spellTextCache[spellID].desc = desc
                return desc
            end
        end
    end

    if C_Spell and C_Spell.GetSpellDescription then
        local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
        if ok and desc and desc ~= "" then
            desc = NormalizeSpellDescText(desc)
            CARD_CACHE.spellTextCache[spellID] = CARD_CACHE.spellTextCache[spellID] or {}
            CARD_CACHE.spellTextCache[spellID].desc = desc
            return desc
        end
    end

    CARD_CACHE.spellTextCache[spellID] = CARD_CACHE.spellTextCache[spellID] or {}
    CARD_CACHE.spellTextCache[spellID].desc = L["暂无描述。"]
    return L["暂无描述。"]
end

local function ComputeSpellDescRows(descText)
    local text = tostring(descText or "")
    if text == "" then
        return 5
    end
    local gw = (UI.spellSettingsGridChild and UI.spellSettingsGridChild:GetWidth()) or 760
    local cell = (gw - 20) / C.SPELL_SETTINGS_GRID_COLS
    if cell < 6 then cell = 6 end
    local descWidthPx = math.max(200, math.floor(77 * cell - 2))
    local descRowsMin = 5

    if not _spellDescMeasureFS then
        _spellDescMeasureFS = EXUI:CreateVisualFontString(UIParent, EXFONTFRAME, "GameFontDisableSmall")
        _spellDescMeasureFS:Hide()
        _spellDescMeasureFS:SetWordWrap(true)
        _spellDescMeasureFS:SetJustifyH("LEFT")
        _spellDescMeasureFS:SetSpacing(0)
    end
    _spellDescMeasureFS:SetWidth(descWidthPx)
    _spellDescMeasureFS:SetText(text)

    local h = _spellDescMeasureFS:GetStringHeight() or 0
    local rows = math.ceil((h + 6) / cell)
    if rows < descRowsMin then
        rows = descRowsMin
    end
    return rows
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

    -- 保留来源的手动换行，但不要把它放大为段落双行距；自动换行仍由 FontString 处理。
    local body = table.concat(lines, "\n", 2)
    return castLine, body
end

RefreshSpellDetailHeaderLayout = function()
    if not (UI.spellDetailHeader and UI.spellDetailTitle and UI.spellDetailMeta and UI.spellDetailCast and UI.spellDetailBody) then
        return
    end

    local headerW = UI.spellDetailHeader:GetWidth() or 0
    if headerW <= 0 and UI.spellSettingsFrame then
        headerW = (UI.spellSettingsFrame:GetWidth() or 0) - 16
    end
    if headerW <= 0 then
        headerW = 980
    end

    -- 顶部右侧由时间轴控制组占用，标题与 spell/event 元数据不能延伸到它下面。
    local controlsReserve = (UI.titleControlHost and UI.titleControlHost:IsShown()) and
        ((UI.titleControlHost:GetWidth() or 420) + 12) or 0
    local metaWidth = math.min(300, math.floor(math.max(0, headerW - controlsReserve) * 0.28))
    local titleNatural = math.ceil(UI.spellDetailTitle:GetUnboundedStringWidth() or 0) + 8
    local titleWidth = math.min(
        math.max(120, headerW - 44 - 14 - 12 - 12 - metaWidth - 18 - controlsReserve),
        math.max(120, titleNatural)
    )
    local bodyWidth = math.max(320, headerW - 44 - 14 - 12 - 18)

    UI.spellDetailTitle:SetWidth(titleWidth)
    UI.spellDetailMeta:ClearAllPoints()
    UI.spellDetailMeta:SetPoint("LEFT", UI.spellDetailTitle, "RIGHT", 6, 0)
    UI.spellDetailMeta:SetPoint("RIGHT", UI.spellDetailHeader, "RIGHT", -18 - controlsReserve, 0)
    UI.spellDetailCast:SetWidth(bodyWidth)
    UI.spellDetailBody:SetWidth(bodyWidth)

    local castH = UI.spellDetailCast:GetStringHeight() or 0
    local bodyH = UI.spellDetailBody:GetStringHeight() or 0
    local desiredHeight = math.max(156, math.ceil(50 + castH + 6 + bodyH + 8))
    UI.spellDetailHeader:SetHeight(desiredHeight)
end

local function GetSpellListViewportHeight()
    return (C.SPELL_CARD.height * C.SPELL_LIST_VISIBLE_ROWS)
        + (C.SPELL_CARD.gapY * (C.SPELL_LIST_VISIBLE_ROWS - 1))
        + 8
end

local function ApplyBossRightPanelLayout()
    if not (UI.rightRoot and UI.spellSettingsFrame) then return end
    -- 列表区是固定的两行法术卡；描述卡和下方设置区只能从这个边界之后开始。
    UI.spellSettingsFrame:ClearAllPoints()
    UI.spellSettingsFrame:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 8, -(GetSpellListViewportHeight() + 10))
    UI.spellSettingsFrame:SetPoint("BOTTOMRIGHT", UI.rightRoot, "BOTTOMRIGHT", -8, 8)
end

local function BuildSpellSettingsLayout(spellName, spellIdentifier, eventID, spellIcon, iconFlags)
    for i = #SETTINGS_LAYOUT, 1, -1 do
        SETTINGS_LAYOUT[i] = nil
    end

    local rows = {
        { key = "card_master", type = "card", x = 1, y = 1, w = 200, h = 6, label = "", padding = 6, keepBorderVisible = true,
            bgColor = { r = 0.030, g = 0.038, b = 0.054, a = 0.98 }, borderColor = { r = 0.26, g = 0.30, b = 0.38, a = 0.82 }, accentColor = { r = 1.00, g = 0.82, b = 0.22, a = 1.00 } },
        { key = "enabled", type = "checkbox", x = 3, y = 1, w = 36, h = 5, label = L["启用"], labelSize = 18 },

        { key = "card_text", type = "card", x = 1, y = 8, w = 107, h = 40, label = L["文本设置"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\text.png", titleSize = 17, keepBorderVisible = true,
            bgColor = { r = 0.020, g = 0.027, b = 0.041, a = 0.98 }, borderColor = { r = 0.22, g = 0.26, b = 0.34, a = 0.84 }, accentColor = { r = 1.00, g = 0.82, b = 0.22, a = 1.00 } },
        { key = "eventColorEnabled", type = "checkbox", x = 4, y = 16, w = 26, h = 5, label = L["颜色"] },
        { key = "eventColorMode", type = "dropdown", x = 33, y = 16, w = 35, h = 5, label = "", labelPos = "left", items = EVENT_COLOR_ITEMS_FUNC, search = true },
        { key = "eventColor", type = "color", x = 73, y = 16, w = 33, h = 5, label = L["自定义颜色"] },
        { key = "centralEnabled", type = "checkbox", x = 4, y = 23, w = 26, h = 5, label = L["|cffffd637中央文本|r"] },
        { key = "centralLead", type = "input", x = 34, y = 23, w = 12, h = 5, label = L["(秒)"], labelPos = "right" },
        { key = "centralText", type = "input", x = 57, y = 23, w = 49, h = 5, label = "" },
        { key = "countdownEnabled", type = "checkbox", x = 4, y = 30, w = 26, h = 5, label = L["|cffffd637倒数文本|r"] },
        { key = "preAlertText", type = "input", x = 34, y = 30, w = 72, h = 5, label = "" },
        { key = "timerBarRenameEnabled", type = "checkbox", x = 4, y = 37, w = 26, h = 5, label = L["|cffffd637计时条改名|r"] },
        { key = "timerBarRenameText", type = "input", x = 34, y = 37, w = 72, h = 5, label = "" },

        { key = "card_display", type = "card", x = 109, y = 8, w = 93, h = 40, label = L["施法设置"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\bar.png", titleSize = 17, keepBorderVisible = true,
            bgColor = { r = 0.020, g = 0.027, b = 0.041, a = 0.98 }, borderColor = { r = 0.22, g = 0.26, b = 0.34, a = 0.84 }, accentColor = { r = 0.50, g = 0.74, b = 1.00, a = 1.00 } },
        { key = "ringEnabled", type = "checkbox", x = 112, y = 16, w = 28, h = 5, label = L["施法圆环"] },
        { key = "castProgressBarEnabled", type = "checkbox", x = 112, y = 23, w = 28, h = 5, label = L["施法读条"] },
        { key = "ringCastCheckEnabled", type = "checkbox", x = 112, y = 30, w = 28, h = 5, label = L["施法检测"] },
        { key = "castProgressBarRenameEnabled", type = "checkbox", x = 112, y = 37, w = 28, h = 5, label = L["读条改名"] },
        { key = "castProgressBarRenameText", type = "input", x = 143, y = 37, w = 54, h = 5, label = "" },

        { key = "card_voice", type = "card", x = 1, y = 50, w = 107, h = 40, label = L["语音设置"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\sound.png", titleSize = 17, keepBorderVisible = true,
            bgColor = { r = 0.020, g = 0.027, b = 0.041, a = 0.98 }, borderColor = { r = 0.22, g = 0.26, b = 0.34, a = 0.84 }, accentColor = { r = 0.28, g = 0.84, b = 1.00, a = 1.00 } },
        { key = "tr0Enabled", type = "checkbox", x = 4, y = 58, w = 26, h = 5, label = L["|cffffd637中央文本|r"] },
        { key = "tr0Source", type = "dropdown", x = 34, y = 58, w = 27, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr0Label", type = "dropdown", x = 61, y = 58, w = 33, h = 5, label = "", items = {}, search = true },
        { key = "tr0LSM", type = "lsm_sound", x = 61, y = 58, w = 33, h = 5, label = "", search = true },
        { key = "tr0Path", type = "input", x = 61, y = 58, w = 33, h = 5, label = "" },
        { key = "tr0TtsText", type = "input", x = 61, y = 58, w = 33, h = 5, label = "" },
        { key = "tr0ValueTest", type = "button", x = 95, y = 58, w = 11, h = 6, label = L["试听"] },
        { key = "tr1Enabled", type = "checkbox", x = 4, y = 65, w = 26, h = 5, label = L["|cffffd637施法开始|r"] },
        { key = "tr1Source", type = "dropdown", x = 34, y = 65, w = 27, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr1Label", type = "dropdown", x = 61, y = 65, w = 33, h = 5, label = "", items = {}, search = true },
        { key = "tr1LSM", type = "lsm_sound", x = 61, y = 65, w = 33, h = 5, label = "", search = true },
        { key = "tr1Path", type = "input", x = 61, y = 65, w = 33, h = 5, label = "" },
        { key = "tr1TtsText", type = "input", x = 61, y = 65, w = 33, h = 5, label = "" },
        { key = "tr1ValueTest", type = "button", x = 95, y = 65, w = 11, h = 6, label = L["试听"] },
        { key = "tr2Enabled", type = "checkbox", x = 4, y = 72, w = 26, h = 5, label = L["|cffffd637倒数提示|r"] },
        { key = "tr2CountdownLead", type = "dropdown", x = 34, y = 72, w = 27, h = 5, label = "", items = C.COUNTDOWN_LEAD_ITEMS, search = true },
        { key = "tr2PlayTextEnabled", type = "checkbox", x = 4, y = 79, w = 26, h = 5, label = L["播放文字"] },
        { key = "tr2Source", type = "dropdown", x = 34, y = 79, w = 27, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr2Label", type = "dropdown", x = 61, y = 79, w = 33, h = 5, label = "", items = {}, search = true },
        { key = "tr2LSM", type = "lsm_sound", x = 61, y = 79, w = 33, h = 5, label = "", search = true },
        { key = "tr2Path", type = "input", x = 61, y = 79, w = 33, h = 5, label = "" },
        { key = "tr2TtsText", type = "input", x = 61, y = 79, w = 33, h = 5, label = "" },
        { key = "tr2ValueTest", type = "button", x = 95, y = 79, w = 11, h = 6, label = L["试听"] },

        { key = "card_target_alert", type = "card", x = 109, y = 50, w = 93, h = 40, label = L["被点名提示"], titleIcon = "Interface\\AddOns\\ExwindCore\\Textures\\target.png", titleSize = 17, keepBorderVisible = true,
            bgColor = { r = 0.020, g = 0.027, b = 0.041, a = 0.98 }, borderColor = { r = 0.22, g = 0.26, b = 0.34, a = 0.84 }, accentColor = { r = 0.40, g = 1.00, b = 0.62, a = 1.00 } },
        { key = "targetAlertStartEnabled", type = "checkbox", x = 112, y = 58, w = 28, h = 5, label = L["启用"] },
        { key = "targetAlertRingEnabled", type = "checkbox", x = 112, y = 66, w = 25, h = 5, label = L["圆环"] },
        { key = "targetAlertTextEnabledV2", type = "checkbox", x = 142, y = 66, w = 25, h = 5, label = L["文本"] },
        { key = "targetAlertIconEnabled", type = "checkbox", x = 112, y = 73, w = 25, h = 5, label = "|TInterface\\AddOns\\ExwindCore\\Textures\\umage.png:16:16:0:0|t " .. L["图标"] },
        { key = "targetAlertStealthEnabledV2", type = "checkbox", x = 142, y = 73, w = 43, h = 5, label = "|T132089:18:18|t " .. L["隐遁提示"] },
        { key = "targetAlertVoiceEnabled", type = "checkbox", x = 112, y = 80, w = 20, h = 5, label = L["语音"] },
        { key = "targetAlertStartSource", type = "dropdown", x = 134, y = 80, w = 24, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "targetAlertStartLabel", type = "dropdown", x = 158, y = 80, w = 30, h = 5, label = "", items = {}, search = true },
        { key = "targetAlertStartLSM", type = "lsm_sound", x = 158, y = 80, w = 30, h = 5, label = "", search = true },
        { key = "targetAlertStartPath", type = "input", x = 158, y = 80, w = 30, h = 5, label = "" },
        { key = "targetAlertStartTtsText", type = "input", x = 158, y = 80, w = 30, h = 5, label = "" },
        { key = "targetAlertStartValueTest", type = "button", x = 190, y = 80, w = 9, h = 6, label = L["试听"] },
    }

    for _, row in ipairs(rows) do
        SETTINGS_LAYOUT[#SETTINGS_LAYOUT + 1] = row
    end
    ExwindTools:RegisterModuleLayout(SETTINGS.EDITOR_KEY, SETTINGS_LAYOUT)
end

local function UpdateSpellDetailHeader(spellName, spellIdentifier, eventID, spellIcon, iconFlags, alertMarkupOverride)
    if not UI.spellDetailHeader then
        return
    end

    local safeName = tostring(spellName or L["未选择法术"])
    local sid = tonumber(spellIdentifier)
    local eid = tonumber(eventID)
    local descText = GetSpellDescription(sid)
    local castLine, bodyText = SplitSpellDescription(descText)
    local alertMarkup = tostring(alertMarkupOverride or "") ~= "" and tostring(alertMarkupOverride) or
        BuildPrimaryCategoryMarkup(eid, 20, -1)

    UI.spellDetailHeader:Show()
    UI.spellDetailPlaceholder:Hide()
    UI.spellDetailIcon:SetTexture(spellIcon or 134400)
    UI.spellDetailIcon:Show()
    UI.spellDetailTitle:SetText(safeName)
    UI.spellDetailMeta:SetText(string.format(
        "%s |cff7f8794spell:%s  event:%s|r",
        alertMarkup ~= "" and alertMarkup or "",
        tostring(sid or "-"),
        tostring(eid or "-")
    ))
    UI.spellDetailCast:SetText(castLine or "")
    UI.spellDetailBody:SetText((bodyText and bodyText ~= "") and bodyText or L["暂无描述。"])
    RefreshSpellDetailHeaderLayout()
end

local function SetSpellDetailHeaderEmpty(message)
    if not UI.spellDetailHeader then
        return
    end

    UI.spellDetailHeader:Show()
    UI.spellDetailPlaceholder:SetText(tostring(message or L["点击上方法术卡片后，可在此查看法术描述。"]))
    UI.spellDetailPlaceholder:Show()
    UI.spellDetailIcon:Hide()
    UI.spellDetailTitle:SetText("")
    UI.spellDetailMeta:SetText("")
    UI.spellDetailCast:SetText("")
    UI.spellDetailBody:SetText("")
    UI.spellDetailHeader:SetHeight(156)
end

-- 副本通用设置没有“法术卡片 + 描述卡”这一层级：右侧只保留一块 Grid 容器。
local function SetRightSettingsPresentation(isDungeonCommon)
    if not (UI.rightRoot and UI.spellSettingsFrame and UI.spellDetailHeader
            and UI.spellSettingsGridScroll and UI.spellScrollFrame) then
        return
    end

    local useSingleGridPanel = isDungeonCommon == true
    if UI.rightPanelSingleGrid == useSingleGridPanel then
        return
    end
    UI.rightPanelSingleGrid = useSingleGridPanel

    UI.spellSettingsFrame:ClearAllPoints()
    if useSingleGridPanel then
        UI.spellSettingsFrame:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 8, -8)
        UI.spellSettingsFrame:SetPoint("BOTTOMRIGHT", UI.rightRoot, "BOTTOMRIGHT", -8, 8)
        UI.spellDetailHeader:Hide()
        UI.spellScrollFrame:Hide()
        if UI.titleControlHost then UI.titleControlHost:Hide() end
        UI.spellSettingsGridScroll:ClearAllPoints()
        UI.spellSettingsGridScroll:SetPoint("TOPLEFT", UI.spellSettingsFrame, "TOPLEFT", 8, -8)
        UI.spellSettingsGridScroll:SetPoint("BOTTOMRIGHT", UI.spellSettingsFrame, "BOTTOMRIGHT", -8, 8)
    else
        ApplyBossRightPanelLayout()
        UI.spellDetailHeader:Show()
        UI.spellScrollFrame:Show()
        if UI.titleControlHost then UI.titleControlHost:Show() end
        UI.spellSettingsGridScroll:ClearAllPoints()
        UI.spellSettingsGridScroll:SetPoint("TOPLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 0, -2)
        UI.spellSettingsGridScroll:SetPoint("BOTTOMRIGHT", UI.spellSettingsFrame, "BOTTOMRIGHT", -8, 6)
    end
end

BuildSpellEditorDraftFromSelectedSpell = function(expectedRevision)
    if expectedRevision ~= nil and expectedRevision ~= STATE.spellEditorRevision then
        return false
    end
    local encounterID = GetCurrentEncounterID()
    local boss = GetCurrentBoss()
    if not (encounterID and boss and type(boss.events) == "table") then return end
    local selectedEvent
    for _, e in ipairs(boss.events) do
        if GetEventID(e) == tonumber(selectedEventID) then
            selectedEvent = e
            break
        end
    end
    if not selectedEvent then return end
    local eventID = GetEventID(selectedEvent)
    local spellIdentifier = GetEventSpellIdentifier(selectedEvent)
    if not eventID then return end

    local slotKey = STATE.currentSpellSlotKey or GetCurrentSpellSlotKey()
    local row = GetRuntimeSpellConfig(eventID, slotKey)
    if not row then return end
    local cfg = GetBossConfig()
    local configID = cfg and cfg.GetSelectedUser and cfg:GetSelectedUser(slotKey) or ""
    local voiceCfg = GetEventVoiceConfig(eventID, slotKey)

    -- Grid 的控件回调在首次创建时绑定到这个 table。切技能时保持 table
    -- identity、仅原地替换字段，才能复用控件而不把输入写回上一技能。
    local boundDraft = STATE.spellSettingsGridBound and STATE.spellEditorDraft or nil
    local draft = DeepCopy(SETTINGS.DEFAULTS)
    if type(draft) ~= "table" then return end

    STATE.settingsSyncLock = true
    draft.enabled = (row.enabled ~= false)
    draft.centralEnabled = (row.centralEnabled == true)
    draft.centralLead = tostring(tonumber(row.centralLead) or 0)
    Page._spellTextRawState.centralText = tostring(row.centralText or "")
    draft.centralText = Page._spellTextRawState.centralText
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        draft.centralText = tostring(ExBoss.Locale.TranslateBossDynamicText(draft.centralText) or "")
    end
    local countdownEnabled = row.countdownEnabled
    if countdownEnabled == nil then
        countdownEnabled = (row.preAlertEnabled ~= false)
    end
    local countdownLead = tonumber(row.countdownLead)
    if countdownLead == nil then
        countdownLead = tonumber(row.preAlert) or C.PREALERT_FIXED_SECS
    end
    draft.countdownEnabled = (countdownEnabled == true)
    draft.countdownLead = tostring(NormalizeCountdownLeadSeconds(countdownLead))
    draft.tr2CountdownLead = draft.countdownLead
    Page._spellTextRawState.preAlertText = tostring(row.preAlertText or "")
    draft.preAlertText = Page._spellTextRawState.preAlertText
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        draft.preAlertText = tostring(ExBoss.Locale.TranslateBossDynamicText(draft.preAlertText) or "")
    end
    draft.timerBarRenameEnabled = (row.timerBarRenameEnabled == true)
    Page._spellTextRawState.timerBarRenameText = tostring(row.timerBarRenameText or "")
    draft.timerBarRenameText = Page._spellTextRawState.timerBarRenameText
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        draft.timerBarRenameText = tostring(ExBoss.Locale.TranslateBossDynamicText(draft.timerBarRenameText) or "")
    end
    draft.showBunBar = (row.showBunBar ~= false)
    draft.showTimerBar = (row.showTimerBar ~= false)
    local castWindow = type(row.rules) == "table" and type(row.rules.castWindow) == "table" and row.rules.castWindow or
        nil
    draft.ringEnabled = castWindow and castWindow.enabled == true and castWindow.ringEnabled ~= false or false
    draft.castProgressBarEnabled = castWindow and castWindow.enabled == true and castWindow.castBarEnabled == true or false
    draft.castProgressBarRenameEnabled = castWindow and castWindow.castBarRenameEnabled == true or false
    draft.castProgressBarRenameText = tostring(castWindow and castWindow.castBarRenameText or "")
    draft.ringCastCheckEnabled = castWindow and
        (castWindow.castCheckEnabled == true or castWindow.ringCastCheckEnabled == true) or false
    local countdownVoiceEnabled = row.countdownVoiceEnabled
    if countdownVoiceEnabled == nil then
        countdownVoiceEnabled = (row.countdownPlayName == true)
    end
    for i = 0, 2 do
        local t = voiceCfg and voiceCfg.triggers and voiceCfg.triggers[i] or nil
        local prefix = "tr" .. tostring(i)
        if i == 2 then
            draft[prefix .. "Enabled"] = (countdownVoiceEnabled == true)
            draft[prefix .. "PlayTextEnabled"] = (row.countdownPlayName == true)
        else
            draft[prefix .. "Enabled"] = (t and t.enabled ~= false) or false
        end
        draft[prefix .. "Source"] = NormalizeTriggerSource(t and t.sourceType or "pack")
        draft[prefix .. "Label"] = NormalizeTriggerPackLabel(i, t and t.sourceType or "pack", (t and t.label) or "")
        draft[prefix .. "LSM"] = tostring((t and t.customLSM) or "")
        draft[prefix .. "Path"] = tostring((t and t.customPath) or "")
        draft[prefix .. "TtsText"] = tostring((t and t.ttsText) or "")
    end
    local c = (type(row.color) == "table") and row.color or nil
    draft.eventColorEnabled = (c and c.enabled ~= false) and true or false
    if c and c.enabled ~= false then
        local mode = SETTINGS.DEFAULTS.eventColorMode
        if c.useCustom == true then
            mode = "__custom"
        elseif type(c.scheme) == "string" and c.scheme ~= "" then
            mode = NormalizeEventColorMode(c.scheme)
        elseif c.r ~= nil and c.g ~= nil and c.b ~= nil then
            mode = "__custom"
        end
        draft.eventColorMode = mode
    else
        draft.eventColorMode = SETTINGS.DEFAULTS.eventColorMode
    end
    local fallbackR = SETTINGS.DEFAULTS.eventColorR
    local fallbackG = SETTINGS.DEFAULTS.eventColorG
    local fallbackB = SETTINGS.DEFAULTS.eventColorB
    if draft.eventColorMode == "__custom" then
        local CS = GetColorSchemeModule()
        if CS and CS.GetCustomColor then
            fallbackR, fallbackG, fallbackB = CS.GetCustomColor()
        end
    end
    draft.eventColorR = Clamp01(c and c.r, fallbackR)
    draft.eventColorG = Clamp01(c and c.g, fallbackG)
    draft.eventColorB = Clamp01(c and c.b, fallbackB)
    draft.eventColor = { r = draft.eventColorR, g = draft.eventColorG, b = draft.eventColorB }
    draft.targetAlertStartEnabled = (row.targetAlertStartEnabled == true)
    draft.targetAlertStartSource = NormalizeTriggerSource(row.targetAlertStartSource or "lsm")
    draft.targetAlertStartLabel = tostring(row.targetAlertStartLabel or "")
    draft.targetAlertStartLSM = tostring(row.targetAlertStartLSM or "")
    draft.targetAlertStartPath = tostring(row.targetAlertStartPath or "")
    draft.targetAlertStartTtsText = tostring(row.targetAlertStartTtsText or "")
    draft.targetAlertVoiceEnabled = (row.targetAlertVoiceEnabled ~= false)
    draft.targetAlertRingEnabled = (row.targetAlertRingEnabled == true)
    draft.targetAlertIconEnabled = (row.targetAlertIconEnabled == true)
    draft.targetAlertTextEnabledV2 = (row.targetAlertTextEnabledV2 == true)
    draft.targetAlertStealthEnabledV2 = (row.targetAlertStealthEnabledV2 == true)
    SyncSpellTextFormStateFromDraft(draft)
    STATE.settingsSyncLock = false
    if expectedRevision ~= nil and expectedRevision ~= STATE.spellEditorRevision then
        return false
    end
    if type(boundDraft) == "table" then
        for key in pairs(boundDraft) do
            boundDraft[key] = nil
        end
        for key, value in pairs(draft) do
            boundDraft[key] = value
        end
        draft = boundDraft
    end
    STATE.spellEditorDraft = draft
    STATE.spellTextDraftRevision = 0
    STATE.spellTextCommittedRevision = 0
    STATE.spellTextContextRevision = STATE.spellEditorRevision
    STATE.spellTextContextEventID = eventID
    STATE.spellTextContextConfigID = configID
    STATE.spellTextContextSlotKey = slotKey
    STATE.spellEditorContext = {
        revision = STATE.spellEditorRevision,
        encounterID = encounterID,
        eventID = eventID,
        spellIdentifier = spellIdentifier,
        slotKey = slotKey,
        configID = configID,
    }
    return true
end

local function CaptureSelectedSpellContext()
    local encounterID = GetCurrentEncounterID()
    local boss = GetCurrentBoss()
    if not (encounterID and boss and type(boss.events) == "table") then
        return nil
    end
    for _, e in ipairs(boss.events) do
        if GetEventID(e) == tonumber(selectedEventID) then
            local eventID = GetEventID(e)
            if eventID then
                local slotKey = STATE.currentSpellSlotKey or GetCurrentSpellSlotKey()
                local cfg = GetBossConfig()
                return {
                    encounterID = encounterID,
                    eventID = eventID,
                    spellIdentifier = GetEventSpellIdentifier(e),
                    slotKey = slotKey,
                    configID = cfg and cfg.GetSelectedUser and cfg:GetSelectedUser(slotKey) or "",
                }
            end
            break
        end
    end
    return nil
end

local function IsSpellEditorContextCurrent(ctx)
    local loaded = STATE.spellEditorContext
    if Page._visible ~= true or type(loaded) ~= "table" or type(ctx) ~= "table" then
        return false
    end
    return loaded.revision == STATE.spellEditorRevision
        and loaded.encounterID == ctx.encounterID
        and loaded.eventID == ctx.eventID
        and loaded.spellIdentifier == ctx.spellIdentifier
        and loaded.slotKey == ctx.slotKey
        and tostring(loaded.configID or "") == tostring(ctx.configID or "")
end

PersistSpellEditorDraftToSelectedSpell = function(changedKey)
    if STATE.settingsSyncLock then return false, "spell editor is synchronizing" end
    local ctx = CaptureSelectedSpellContext()
    if not IsSpellEditorContextCurrent(ctx) then return false, "spell editor context changed" end
    local eventID = ctx.eventID
    local slotKey = ctx.slotKey
    local values = STATE.spellEditorDraft
    if type(values) ~= "table" or type(changedKey) ~= "string" then
        return false, "spell editor values unavailable"
    end
    SyncLiveSpellTextInputsToDraft(values)
    local direct = {
        enabled = { "enabled", function(v) return v == true end }, centralEnabled = { "centralEnabled", function(v) return v == true end },
        centralLead = { "centralLead", function(v) return math.max(0, math.min(30, tonumber(v) or 0)) end }, centralText = { "centralText", NormalizeOptionText },
        preAlertText = { "preAlertText", NormalizeOptionText }, timerBarRenameEnabled = { "timerBarRenameEnabled", function(v) return v == true end },
        timerBarRenameText = { "timerBarRenameText", NormalizeOptionText }, showBunBar = { "showBunBar", function(v) return v == true end },
        showTimerBar = { "showTimerBar", function(v) return v == true end }, targetAlertStartEnabled = { "targetAlertStartEnabled", function(v) return v == true end },
        targetAlertStartLSM = { "targetAlertStartLSM", function(v) return tostring(v or "") end }, targetAlertStartSource = { "targetAlertStartSource", NormalizeTriggerSource },
        targetAlertStartLabel = { "targetAlertStartLabel", function(v) return tostring(v or "") end }, targetAlertStartPath = { "targetAlertStartPath", function(v) return tostring(v or "") end },
        targetAlertStartTtsText = { "targetAlertStartTtsText", function(v) return tostring(v or "") end }, targetAlertVoiceEnabled = { "targetAlertVoiceEnabled", function(v) return v == true end },
        targetAlertRingEnabled = { "targetAlertRingEnabled", function(v) return v == true end }, targetAlertIconEnabled = { "targetAlertIconEnabled", function(v) return v == true end },
        targetAlertTextEnabledV2 = { "targetAlertTextEnabledV2", function(v) return v == true end }, targetAlertStealthEnabledV2 = { "targetAlertStealthEnabledV2", function(v) return v == true end },
    }
    local entry = direct[changedKey]
    if entry then return SetCurrentEventPath(eventID, slotKey, { entry[1] }, entry[2](values[changedKey])) end
    if changedKey == "countdownEnabled" then
        local enabled = values.countdownEnabled == true
        local ok, reason = SetCurrentEventPath(eventID, slotKey, { "countdownEnabled" }, enabled)
        if not ok then return false, reason end
        return SetCurrentEventPath(eventID, slotKey, { "preAlertEnabled" }, enabled)
    end
    if changedKey == "tr2CountdownLead" then values.countdownLead = tostring(NormalizeCountdownLeadSeconds(values.tr2CountdownLead)) end
    if changedKey == "countdownLead" or changedKey == "tr2CountdownLead" then
        local lead = NormalizeCountdownLeadSeconds(values.countdownLead)
        values.countdownLead, values.tr2CountdownLead = tostring(lead), tostring(lead)
        local ok, reason = SetCurrentEventPath(eventID, slotKey, { "countdownLead" }, lead)
        if not ok then return false, reason end
        return SetCurrentEventPath(eventID, slotKey, { "preAlert" }, values.countdownEnabled == true and lead or 0)
    end
    if changedKey == "tr2Enabled" then return SetCurrentEventPath(eventID, slotKey, { "countdownVoiceEnabled" }, values.tr2Enabled == true) end
    if changedKey == "tr2PlayTextEnabled" then return SetCurrentEventPath(eventID, slotKey, { "countdownPlayName" }, values.tr2PlayTextEnabled == true) end
    local triggerIndex, triggerField = changedKey:match("^tr([012])(.+)$")
    if triggerIndex then
        local index = tonumber(triggerIndex)
        local field = ({ Enabled = "enabled", Source = "sourceType", Label = "label", LSM = "customLSM", Path = "customPath", TtsText = "ttsText" })[triggerField]
        if field then
            local value = values[changedKey]
            if field == "enabled" then value = value == true elseif field == "sourceType" then value = NormalizeTriggerSource(value) elseif field == "label" then value = NormalizeTriggerPackLabel(index, values["tr" .. index .. "Source"], value) else value = tostring(value or "") end
            return SetCurrentEventPath(eventID, slotKey, { "triggers", index, field }, value)
        end
    end
    if changedKey == "ringEnabled" or changedKey == "castProgressBarEnabled" then
        local field = changedKey == "ringEnabled" and "ringEnabled" or "castBarEnabled"
        local ok, reason = SetCurrentEventPath(eventID, slotKey, { "rules", "castWindow", field }, values[changedKey] == true)
        if not ok then return false, reason end
        return SetCurrentEventPath(eventID, slotKey, { "rules", "castWindow", "enabled" }, values.ringEnabled == true or values.castProgressBarEnabled == true)
    end
    local castField = ({ castProgressBarRenameEnabled = "castBarRenameEnabled", castProgressBarRenameText = "castBarRenameText", ringCastCheckEnabled = "castCheckEnabled" })[changedKey]
    if castField then
        local value = changedKey == "castProgressBarRenameText" and NormalizeOptionText(values[changedKey]) or values[changedKey] == true
        return SetCurrentEventPath(eventID, slotKey, { "rules", "castWindow", castField }, value)
    end
    if changedKey == "eventColorEnabled" then return SetCurrentEventPath(eventID, slotKey, { "color", "enabled" }, values.eventColorEnabled == true) end
    if changedKey == "eventColorMode" then
        local mode = NormalizeEventColorMode(values.eventColorMode)
        local ok, reason = SetCurrentEventPath(eventID, slotKey, { "color", "useCustom" }, mode == "__custom")
        if not ok then return false, reason end
        return SetCurrentEventPath(eventID, slotKey, { "color", "scheme" }, mode)
    end
    if changedKey == "eventColor" and type(values.eventColor) == "table" then
        local color = values.eventColor
        local ok, reason = SetCurrentEventPath(eventID, slotKey, { "color", "r" }, Clamp01(color.r, SETTINGS.DEFAULTS.eventColorR))
        if not ok then return false, reason end
        ok, reason = SetCurrentEventPath(eventID, slotKey, { "color", "g" }, Clamp01(color.g, SETTINGS.DEFAULTS.eventColorG))
        if not ok then return false, reason end
        return SetCurrentEventPath(eventID, slotKey, { "color", "b" }, Clamp01(color.b, SETTINGS.DEFAULTS.eventColorB))
    end
    return false, "unknown spell editor field"
end

local function SyncSpellSettingsFrameHeight()
    if UI.rightPanelSingleGrid ~= true then
        ApplyBossRightPanelLayout()
    end
end

local function SaveSelection()
    local db = GetPanelDB()
    db.selectedSeason = selectedSeason
    db.selectedMapID = selectedMapID
    db.selectedBossIdx = selectedBossIndex
end

local function NormalizeSelection()
    local seasons = BuildSeasonList()
    local seasonValid = false
    for _, s in ipairs(seasons) do
        if s == selectedSeason then
            seasonValid = true
            break
        end
    end
    if not seasonValid then
        selectedSeason = "12.1大秘境"
    end

    local mapList = BuildMapList(selectedSeason)
    local mapValid = false
    for _, mapID in ipairs(mapList) do
        if tonumber(mapID) == tonumber(selectedMapID) then
            mapValid = true
            break
        end
    end
    if not mapValid then
        selectedMapID = mapList[1]
    end

    local bossList = BuildBossList(selectedMapID)
    local idx = tonumber(selectedBossIndex)
    if #bossList == 0 then
        selectedBossIndex = nil
    elseif not idx or idx < 1 or idx > #bossList then
        selectedBossIndex = 1
    end

    SaveSelection()
    return seasons, mapList, bossList
end

local function ReleaseMapTabs()
    for i = 1, #CARD_CACHE.activeMapTabs do
        local b = CARD_CACHE.activeMapTabs[i]
        b:Hide()
        b:ClearAllPoints()
        b:SetParent(nil)
        table.insert(CARD_CACHE.mapTabPool, b)
    end
    wipe(CARD_CACHE.activeMapTabs)
end

local function AcquireMapTab()
    local b = table.remove(CARD_CACHE.mapTabPool)
    if b then return b end

    b = CreateFrame("Button", nil, UI.mapScrollChild, "BackdropTemplate")
    b:SetSize(90, 106)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    -- 按钮本体不再画外框；只有放大的副本图标拥有独立边框。
    b.iconFrame = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.iconFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    b.iconFrame:SetSize(70, 70)
    b.iconFrame:SetPoint("TOP", 0, -1)

    b.icon = EXUI:CreateVisualTexture(b.iconFrame, EXBASEFRAME)
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.text = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontNormalSmall")
    b.text:SetPoint("TOP", b.iconFrame, "BOTTOM", 0, -2)
    b.text:SetWidth(84)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    b.text:SetFont(ExwindTools.MAIN_FONT, 13, "OUTLINE")

    b:SetScript("OnEnter", function(self)
        self._hovered = true
        if self._applyVisual then self:_applyVisual() end
    end)
    b:SetScript("OnLeave", function(self)
        self._hovered = false
        if self._applyVisual then self:_applyVisual() end
    end)

    return b
end

local function ReleaseBossCards()
    for i = 1, #CARD_CACHE.activeBossCards do
        local b = CARD_CACHE.activeBossCards[i]
        b:Hide()
        b:ClearAllPoints()
        b:SetParent(nil)
        b._dungeonCommon = nil
        table.insert(CARD_CACHE.bossCardPool, b)
    end
    wipe(CARD_CACHE.activeBossCards)
end

local function AcquireBossCard()
    local b = table.remove(CARD_CACHE.bossCardPool)
    if b then return b end

    b = CreateFrame("Button", nil, UI.bossScrollContent, "BackdropTemplate")
    b:SetSize(184, 68)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    b.activeBar = EXUI:CreateVisualTexture(b, EXBORDERFRAME)
    b.activeBar:SetPoint("TOPLEFT", 0, 0)
    b.activeBar:SetPoint("BOTTOMLEFT", 0, 0)
    b.activeBar:SetWidth(3)
    b.activeBar:SetColorTexture(0, 0.7, 1, 1)
    b.activeBar:Hide()

    b.creature = CreateFrame("PlayerModel", nil, b)
    b.creature:SetSize(82, 62)
    b.creature:SetPoint("LEFT", 6, 0)
    b.creature:SetFrameLevel(b:GetFrameLevel() + 3)
    b.creature:EnableMouse(false)

    b.noPortraitText = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontDisableSmall")
    b.noPortraitText:SetPoint("CENTER", b.creature, "CENTER", 0, 0)
    b.noPortraitText:SetText(L["无动态头像"])
    b.noPortraitText:Hide()

    b.nameText = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontNormal")
    b.nameText:SetPoint("TOPLEFT", b.creature, "TOPRIGHT", 10, -8)
    b.nameText:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.nameText:SetJustifyH("LEFT")
    b.nameText:SetWordWrap(false)
    b.nameText:SetFont(ExwindTools.MAIN_FONT, 14, "OUTLINE")

    b.detailText = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontDisableSmall")
    b.detailText:SetPoint("TOPLEFT", b.nameText, "BOTTOMLEFT", 0, -4)
    b.detailText:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.detailText:SetJustifyH("LEFT")

    b:SetScript("OnEnter", function(self)
        self._hovered = true
        if self._applyVisual then self:_applyVisual() end
    end)
    b:SetScript("OnLeave", function(self)
        self._hovered = false
        if self._applyVisual then self:_applyVisual() end
    end)

    return b
end

local function ReleaseSpellCards()
    for i = 1, #CARD_CACHE.activeSpellCards do
        local card = CARD_CACHE.activeSpellCards[i]
        card:Hide()
        card:ClearAllPoints()
        card:SetParent(nil)
        card.eventData = nil
        card._selectionKey = nil
        card._eventID = nil
        table.insert(CARD_CACHE.spellCardPool, card)
    end
    wipe(CARD_CACHE.activeSpellCards)
end

local function AcquireSpellCard()
    local card = table.remove(CARD_CACHE.spellCardPool)
    if card then return card end

    card = CreateFrame("Button", nil, UI.spellScrollChild, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    card:SetBackdropColor(0.06, 0.06, 0.08, 0.88)
    card:SetBackdropBorderColor(0.25, 0.25, 0.28, 0.9)

    card.leftBar = EXUI:CreateVisualTexture(card, EXBACKGROUNDFRAME)
    card.leftBar:SetWidth(4)
    card.leftBar:SetPoint("TOPLEFT", 0, 0)
    card.leftBar:SetPoint("BOTTOMLEFT", 0, 0)

    card.icon = EXUI:CreateVisualTexture(card, EXBASEFRAME)
    card.icon:SetSize(30, 30)
    card.icon:SetPoint("LEFT", 11, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.alertIcon = EXUI:CreateVisualTexture(card, EXBORDERFRAME)
    card.alertIcon:SetSize(22, 22)
    card.alertIcon:SetPoint("LEFT", 9, 0)
    card.alertIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.alertIcon:Hide()

    card.targetAlertMarkerHolder = CreateFrame("Frame", nil, card)
    card.targetAlertMarkerHolder:SetSize(30, 30)
    card.targetAlertMarkerHolder:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.targetAlertMarkerHolder:EnableMouse(true)
    card.targetAlertMarkerHolder:Hide()

    card.targetAlertMarker = EXUI:CreateVisualTexture(card.targetAlertMarkerHolder, EXBORDERFRAME)
    card.targetAlertMarker:SetAllPoints()

    card.targetAlertMarkerHolder:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L[BOSS_TEST_TARGET_ALERT_TOOLTIP], 0.20, 1.00, 0.20, true)
        GameTooltip:Show()
    end)
    card.targetAlertMarkerHolder:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    card.title = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontNormal")
    card.title:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
    card.title:SetPoint("RIGHT", card.targetAlertMarkerHolder, "LEFT", -6, 0)
    card.title:SetJustifyH("LEFT")
    card.title:SetJustifyV("MIDDLE")
    card.title:SetWordWrap(true)
    card.title:SetMaxLines(2)
    card.title:SetSpacing(1)
    card.title:SetFont(ExwindTools.MAIN_FONT, 18, "OUTLINE")

    card.desc = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontHighlightSmall")
    card.desc:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.desc:SetPoint("RIGHT", card, "RIGHT", -14, 0)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetJustifyV("TOP")
    card.desc:SetWordWrap(true)
    card.desc:SetSpacing(2)

    card:SetScript("OnEnter", function(self)
        self._hovered = true
        if self._applyVisual then self:_applyVisual() end
    end)
    card:SetScript("OnLeave", function(self)
        self._hovered = false
        if self._applyVisual then self:_applyVisual() end
    end)

    return card
end

local function SetAdaptiveSpellCardTitle(card, text)
    if not (card and card.title) then
        return
    end

    local title = card.title
    local finalText = tostring(text or "")
    local maxHeight = 26

    for i = 1, #C.SPELL_CARD.titleFontSizes do
        local size = C.SPELL_CARD.titleFontSizes[i]
        title:SetFont(ExwindTools.MAIN_FONT, size, "OUTLINE")
        title:SetSpacing(size <= 14 and 0 or 1)
        title:SetText(finalText)
        if (title:GetStringHeight() or 0) <= maxHeight then
            return
        end
    end

    title:SetText(finalText)
end

local function EnsureUI(leftFrame, contentFrame)
    if UI.leftRoot and UI.rightRoot then return end

    UI.leftRoot = CreateFrame("Frame", nil, leftFrame)
    UI.leftRoot:SetAllPoints(leftFrame)

    local EXUI = ExwindTools.UI
    if EXUI and EXUI.CreateDropdown then
        UI.seasonDropdown = EXUI:CreateDropdown(
            UI.leftRoot,
            260,
            "",
            {},
            selectedSeason,
            function(val)
                if tostring(val or "") == tostring(selectedSeason or "") then return end
                CommitSpellTextFormState()
                InvalidateSpellEditorContext()
                selectedSeason = val
                selectedMapID = nil
                selectedBossIndex = nil
                selectedEventID = nil
                selectedBossCommonSettings = nil
                SyncSpellSettingsFrameHeight()
                local seasons = NormalizeSelection()
                EnsureCurrentSceneRuntime()
                RefreshSeasonDropdown(seasons)
                RefreshMapTabs(true)
                RefreshBossList(true)
                UpdateSummary()
                RefreshModeButton()
                RefreshSpellCards()
            end,
            true
        )
        UI.seasonDropdown:ClearAllPoints()
        UI.seasonDropdown:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", 10, -10)
        UI.seasonDropdown:SetPoint("TOPRIGHT", UI.leftRoot, "TOPRIGHT", -8, -10)
    end

    local mapTitle = EXUI:CreateVisualFontString(UI.leftRoot, EXFONTFRAME, "GameFontNormal")
    if UI.seasonDropdown then
        mapTitle:SetPoint("TOPLEFT", UI.seasonDropdown, "BOTTOMLEFT", 0, -10)
    else
        mapTitle:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", 10, -10)
    end
    mapTitle:SetText(L["副本切换"])
    mapTitle:SetTextColor(1, 0.82, 0.45)
    mapTitle:SetFont(ExwindTools.MAIN_FONT, 14, "OUTLINE")

    UI.mapScrollFrame = CreateFrame("ScrollFrame", nil, UI.leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.mapScrollFrame)
    end
    UI.mapScrollFrame:SetPoint("TOPLEFT", mapTitle, "BOTTOMLEFT", -2, -4)
    UI.mapScrollFrame:SetPoint("TOPRIGHT", UI.leftRoot, "TOPRIGHT", -8, -44)
    UI.mapScrollFrame:SetHeight(220)

    UI.mapScrollChild = CreateFrame("Frame", nil, UI.mapScrollFrame)
    UI.mapScrollChild:SetSize(208, 1)
    UI.mapScrollFrame:SetScrollChild(UI.mapScrollChild)

    UI.mapEmptyText = EXUI:CreateVisualFontString(UI.mapScrollChild, EXFONTFRAME, "GameFontDisableSmall")
    UI.mapEmptyText:SetPoint("CENTER", 0, 0)
    UI.mapEmptyText:SetTextColor(0.55, 0.55, 0.55)
    UI.mapEmptyText:SetText(L["该分类无副本数据"])

    local sep = EXUI:CreateVisualTexture(UI.leftRoot, EXBORDERFRAME)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", UI.mapScrollFrame, "BOTTOMLEFT", 6, -3)
    sep:SetPoint("TOPRIGHT", UI.mapScrollFrame, "BOTTOMRIGHT", -6, -3)
    sep:SetColorTexture(1, 1, 1, 0.18)

    local bossTitle = EXUI:CreateVisualFontString(UI.leftRoot, EXFONTFRAME, "GameFontNormal")
    bossTitle:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 4, -6)
    bossTitle:SetText(L["首领列表"])
    bossTitle:SetTextColor(1, 0.82, 0.45)
    bossTitle:SetFont(ExwindTools.MAIN_FONT, 14, "OUTLINE")

    UI.bossScrollFrame = CreateFrame("ScrollFrame", nil, UI.leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.bossScrollFrame)
    end
    UI.bossScrollFrame:SetPoint("TOPLEFT", bossTitle, "BOTTOMLEFT", -14, -4)
    UI.bossScrollFrame:SetPoint("BOTTOMRIGHT", UI.leftRoot, "BOTTOMRIGHT", -4, 10)

    UI.bossScrollContent = CreateFrame("Frame", nil, UI.bossScrollFrame)
    UI.bossScrollContent:SetSize(200, 1)
    UI.bossScrollFrame:SetScrollChild(UI.bossScrollContent)

    UI.bossEmptyText = EXUI:CreateVisualFontString(UI.bossScrollContent, EXFONTFRAME, "GameFontDisableSmall")
    UI.bossEmptyText:SetPoint("TOPLEFT", 8, -6)
    UI.bossEmptyText:SetPoint("RIGHT", -8, 0)
    UI.bossEmptyText:SetJustifyH("LEFT")
    UI.bossEmptyText:SetTextColor(0.55, 0.55, 0.55)
    UI.bossEmptyText:SetText(L["当前副本暂无 BOSS 数据"])

    UI.rightRoot = CreateFrame("Frame", nil, contentFrame)
    UI.rightRoot:SetAllPoints(contentFrame)

    EXUI = ExwindTools.UI
    if not UI.titleControlHost then
        -- 创建时先附在右侧根；spellDetailHeader 建好后再移入其右上角。
        UI.titleControlHost = CreateFrame("Frame", nil, UI.rightRoot)
        UI.titleControlHost:SetSize(420, 26)

        UI.modeLabelText = EXUI:CreateVisualFontString(UI.titleControlHost, EXFONTFRAME, "GameFontNormal")
        UI.modeLabelText:SetPoint("RIGHT", UI.titleControlHost, "RIGHT", -196, 0)
        UI.modeLabelText:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
        UI.modeLabelText:SetTextColor(0.95, 0.95, 0.95)
        UI.modeLabelText:SetText(L["轴模式"])
    end

    if EXUI and EXUI.CreateDropdown and UI.titleControlHost and not UI.modeDropdown then
        UI.modeDropdown = EXUI:CreateDropdown(
            UI.titleControlHost,
            176,
            "",
            {
                { L["自动"], "auto" },
                { L["固定时间轴"], "fixed" },
                { L["暴雪轴"], "blizzard" },
            },
            "auto",
            function(val)
                local boss = GetCurrentBoss()
                local encounterID = boss and tonumber(boss.encounterID)
                if not encounterID then return end
                SetEncounterModeOverride(encounterID, val)
                if RefreshModeButton then
                    RefreshModeButton()
                end
                UpdateSummary()

                local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
                if sched and sched._running and tonumber(sched._encounterID) == encounterID and sched.StartBoss then
                    sched:StartBoss(encounterID)
                end
                if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
                    C_Timer.After(0, function()
                        ExBoss.Voice.Engine:ApplyEventOverridesToAPI({
                            reason = "ui:timeline-mode-change",
                        })
                    end)
                end
            end,
            true
        )
        UI.modeDropdown:SetPoint("RIGHT", UI.titleControlHost, "RIGHT", 0, 0)
    end

    local function CreateTopTestButton(text)
        local b = CreateFrame("Button", nil, UI.rightRoot, "BackdropTemplate")
        b:SetSize(70, 28)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        b:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
        b:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.95)
        b.text = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontNormal")
        b.text:SetPoint("CENTER", 0, 0)
        b.text:SetFont(ExwindTools.MAIN_FONT, 13, "OUTLINE")
        b.text:SetText(text or "")
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.1, 0.8, 1, 1)
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.95)
        end)
        return b
    end

    if UI.titleControlHost and not UI.modeTestStartBtn then
        UI.modeTestStartBtn = CreateTopTestButton(L["测开"])
        UI.modeTestStartBtn:SetParent(UI.titleControlHost)
    end
    if UI.titleControlHost and not UI.modeTestEndBtn then
        UI.modeTestEndBtn = CreateTopTestButton(L["测关"])
        UI.modeTestEndBtn:SetParent(UI.titleControlHost)
    end

    if UI.modeDropdown and UI.modeTestStartBtn and UI.modeTestEndBtn then
        UI.modeTestEndBtn:SetPoint("RIGHT", UI.modeLabelText, "LEFT", -12, 0)
        UI.modeTestStartBtn:SetPoint("RIGHT", UI.modeTestEndBtn, "LEFT", -6, 0)
    end

    UI.modeTestStartBtn:SetScript("OnClick", function()
        local boss = GetCurrentBoss()
        local encounterID = boss and tonumber(boss.encounterID)
        if not encounterID then
            return
        end
        local encounterName = tostring((boss and (boss.bossName or boss.name)) or L["测试首领"])
        local difficultyID = tonumber(ExwindTools and ExwindTools.State and ExwindTools.State.DifficultyID) or 8
        local groupSize = (IsInRaid and IsInRaid()) and 20 or 5
        ExBoss.TestTimelineForceFixedTime = ExBoss.TestTimelineForceFixedTime or {}
        ExBoss.TestTimelineForceFixedTime.active = true
        ExBoss.TestTimelineForceFixedTime.encounterID = encounterID
        if ExwindTools and ExwindTools.SendEvent then
            ExwindTools:SendEvent("ENCOUNTER_START", encounterID, encounterName, difficultyID, groupSize)
        else
        end

        StartTestTimelineLoop(encounterID)
    end)

    UI.modeTestEndBtn:SetScript("OnClick", function()
        local boss = GetCurrentBoss()
        local encounterID = boss and tonumber(boss.encounterID) or 0
        local encounterName = tostring((boss and (boss.bossName or boss.name)) or L["测试首领"])
        local difficultyID = tonumber(ExwindTools and ExwindTools.State and ExwindTools.State.DifficultyID) or 8
        local groupSize = (IsInRaid and IsInRaid()) and 20 or 5
        if ExwindTools and ExwindTools.SendEvent then
            ExwindTools:SendEvent("ENCOUNTER_END", encounterID, encounterName, difficultyID, groupSize, 1)
        else
        end

        StopTestTimelineLoop()
    end)

    UI.spellSettingsFrame = CreateFrame("Frame", nil, UI.rightRoot, "BackdropTemplate")
    UI.spellSettingsFrame:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 8, -(GetSpellListViewportHeight() + 10))
    UI.spellSettingsFrame:SetPoint("BOTTOMRIGHT", UI.rightRoot, "BOTTOMRIGHT", -8, 8)
    UI.spellSettingsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    UI.spellSettingsFrame:SetBackdropColor(0.03, 0.04, 0.06, 0.92)
    UI.spellSettingsFrame:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    UI.spellDetailHeader = CreateFrame("Frame", nil, UI.spellSettingsFrame, "BackdropTemplate")
    UI.spellDetailHeader:SetPoint("TOPLEFT", UI.spellSettingsFrame, "TOPLEFT", 8, -8)
    UI.spellDetailHeader:SetPoint("TOPRIGHT", UI.spellSettingsFrame, "TOPRIGHT", -8, -8)
    UI.spellDetailHeader:SetHeight(156)
    UI.spellDetailHeader:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    UI.spellDetailHeader:SetBackdropColor(0.02, 0.03, 0.05, 0.96)
    UI.spellDetailHeader:SetBackdropBorderColor(0.22, 0.22, 0.28, 1)
    UI.spellDetailHeader._exDetailLayoutWidth = 0
    UI.spellDetailHeader._exDetailLayoutPending = false
    UI.spellDetailHeader:SetScript("OnSizeChanged", function(self, width)
        local nextWidth = math.floor((tonumber(width) or 0) + 0.5)
        if nextWidth <= 0 or nextWidth == self._exDetailLayoutWidth then return end
        self._exDetailLayoutWidth = nextWidth
        if self._exDetailLayoutPending then return end
        self._exDetailLayoutPending = true
        C_Timer.After(0, function()
            self._exDetailLayoutPending = false
            if Page._visible and self:IsShown() then
                RefreshSpellDetailHeaderLayout()
            end
        end)
    end)

    -- 时间轴模式与测试按钮只属于 Boss 法术描述，固定在描述卡右上。
    if UI.titleControlHost then
        UI.titleControlHost:SetParent(UI.spellDetailHeader)
        UI.titleControlHost:ClearAllPoints()
        UI.titleControlHost:SetPoint("TOPRIGHT", UI.spellDetailHeader, "TOPRIGHT", -12, -10)
        UI.titleControlHost:SetFrameLevel((UI.spellDetailHeader:GetFrameLevel() or 1) + 5)
        UI.titleControlHost:Show()
    end

    UI.spellDetailAccent = EXUI:CreateVisualTexture(UI.spellDetailHeader, EXBORDERFRAME)
    UI.spellDetailAccent:SetPoint("TOPLEFT", UI.spellDetailHeader, "TOPLEFT", 1, -1)
    UI.spellDetailAccent:SetHeight(2)
    UI.spellDetailAccent:SetWidth(180)
    UI.spellDetailAccent:SetColorTexture(1.00, 0.82, 0.22, 0.95)

    UI.spellDetailPlaceholder = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontDisableSmall")
    UI.spellDetailPlaceholder:SetPoint("CENTER", 0, 0)
    UI.spellDetailPlaceholder:SetTextColor(0.55, 0.55, 0.6)
    UI.spellDetailPlaceholder:SetText(L["点击上方法术卡片后，可在此查看法术描述。"])

    UI.spellDetailIcon = EXUI:CreateVisualTexture(UI.spellDetailHeader, EXBASEFRAME)
    UI.spellDetailIcon:SetSize(52, 52)
    UI.spellDetailIcon:SetPoint("TOPLEFT", 10, -12)
    UI.spellDetailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    UI.spellDetailTitle = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontNormal")
    UI.spellDetailTitle:SetPoint("TOPLEFT", UI.spellDetailIcon, "TOPRIGHT", 8, -1)
    UI.spellDetailTitle:SetJustifyH("LEFT")
    UI.spellDetailTitle:SetWordWrap(false)
    UI.spellDetailTitle:SetFont(ExwindTools.MAIN_FONT, 23, "OUTLINE")
    UI.spellDetailTitle:SetTextColor(1, 0.95, 0.55)

    UI.spellDetailMeta = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontHighlight")
    UI.spellDetailMeta:SetPoint("LEFT", UI.spellDetailTitle, "RIGHT", 10, 0)
    UI.spellDetailMeta:SetJustifyH("LEFT")
    UI.spellDetailMeta:SetWordWrap(false)
    UI.spellDetailMeta:SetFont(ExwindTools.MAIN_FONT, 16, "")
    UI.spellDetailMeta:SetTextColor(0.55, 0.57, 0.62)

    UI.spellDetailCast = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontNormal")
    UI.spellDetailCast:SetPoint("TOPLEFT", UI.spellDetailTitle, "BOTTOMLEFT", 0, -2)
    UI.spellDetailCast:SetPoint("RIGHT", UI.spellDetailHeader, "RIGHT", -18, 0)
    UI.spellDetailCast:SetJustifyH("LEFT")
    UI.spellDetailCast:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    UI.spellDetailCast:SetTextColor(0.92, 0.92, 0.95)

    UI.spellDetailBody = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontHighlight")
    UI.spellDetailBody:SetPoint("TOPLEFT", UI.spellDetailCast, "BOTTOMLEFT", 0, -8)
    UI.spellDetailBody:SetPoint("RIGHT", UI.spellDetailHeader, "RIGHT", -18, 0)
    UI.spellDetailBody:SetJustifyH("LEFT")
    UI.spellDetailBody:SetJustifyV("TOP")
    UI.spellDetailBody:SetWordWrap(true)
    UI.spellDetailBody:SetSpacing(2)
    UI.spellDetailBody:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")

    UI.spellDetailDivider = EXUI:CreateVisualTexture(UI.spellDetailHeader, EXBORDERFRAME)
    UI.spellDetailDivider:SetPoint("BOTTOMLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 14, 10)
    UI.spellDetailDivider:SetPoint("BOTTOMRIGHT", UI.spellDetailHeader, "BOTTOMRIGHT", -14, 10)
    UI.spellDetailDivider:SetHeight(1)
    UI.spellDetailDivider:SetColorTexture(1, 1, 1, 0.14)
    UI.spellDetailDivider:Hide()

    UI.spellSettingsGridScroll = CreateFrame("ScrollFrame", nil, UI.spellSettingsFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.spellSettingsGridScroll)
    end
    UI.spellSettingsGridScroll:SetPoint("TOPLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 0, -2)
    UI.spellSettingsGridScroll:SetPoint("BOTTOMRIGHT", UI.spellSettingsFrame, "BOTTOMRIGHT", -8, 6)

    UI.spellSettingsGridChild = CreateFrame("Frame", nil, UI.spellSettingsGridScroll)
    UI.spellSettingsGridChild:SetSize(760, 1)
    UI.spellSettingsGridScroll:SetScrollChild(UI.spellSettingsGridChild)
    Page._spellSettingsGridChild = UI.spellSettingsGridChild

    UI.spellSettingsEmptyText = EXUI:CreateVisualFontString(UI.spellSettingsGridChild, EXFONTFRAME, "GameFontDisableSmall")
    UI.spellSettingsEmptyText:SetPoint("TOPLEFT", 6, -6)
    UI.spellSettingsEmptyText:SetPoint("RIGHT", -6, 0)
    UI.spellSettingsEmptyText:SetJustifyH("LEFT")
    UI.spellSettingsEmptyText:SetWordWrap(true)
    UI.spellSettingsEmptyText:SetText(L["点击上方法术卡片后，可在此配置单法术提醒选项。"])

    UI.spellScrollFrame = CreateFrame("ScrollFrame", nil, UI.rightRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.spellScrollFrame)
    end
    UI.spellScrollFrame:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 8, -8)
    UI.spellScrollFrame:SetPoint("BOTTOMRIGHT", UI.spellSettingsFrame, "TOPRIGHT", -8, 6)

    UI.spellScrollChild = CreateFrame("Frame", nil, UI.spellScrollFrame)
    UI.spellScrollChild:SetSize(760, 1)
    UI.spellScrollFrame:SetScrollChild(UI.spellScrollChild)

    UI.spellEmptyText = EXUI:CreateVisualFontString(UI.spellScrollChild, EXFONTFRAME, "GameFontDisableSmall")
    UI.spellEmptyText:SetPoint("TOPLEFT", 4, -4)
    UI.spellEmptyText:SetPoint("RIGHT", -4, 0)
    UI.spellEmptyText:SetJustifyH("LEFT")
    UI.spellEmptyText:SetWordWrap(true)
    UI.spellEmptyText:SetText(L["请选择有技能数据的 BOSS"])

    local panelDB = GetPanelDB()
    selectedSeason = panelDB.selectedSeason
    selectedMapID = panelDB.selectedMapID
    selectedBossIndex = panelDB.selectedBossIdx
end

local function ComputeSpellCardHeight(card)
    return C.SPELL_CARD.height
end

local function RefreshActiveMapTabVisuals()
    for i = 1, #CARD_CACHE.activeMapTabs do
        local tab = CARD_CACHE.activeMapTabs[i]
        if tab and tab._applyVisual then
            tab:_applyVisual()
        end
    end
end

local function RefreshActiveBossCardVisuals()
    for i = 1, #CARD_CACHE.activeBossCards do
        local card = CARD_CACHE.activeBossCards[i]
        if card then
            if card._dungeonCommon == true then
                card._selected = selectedBossCommonSettings == true
            else
                card._selected = tonumber(card.index) == tonumber(selectedBossIndex)
            end
            if card._applyVisual then
                card:_applyVisual()
            end
        end
    end
end

local function RefreshActiveSpellCardVisuals()
    local selected = tonumber(selectedEventID)
    for i = 1, #CARD_CACHE.activeSpellCards do
        local card = CARD_CACHE.activeSpellCards[i]
        if card then
            card._selected = (selected and tonumber(card._eventID) == selected) and true or false
            if card._applyVisual then
                card:_applyVisual()
            end
        end
    end
end

local function QueueSpellUIRefresh(delay)
    if STATE.spellUIRefreshPending then
        return
    end
    STATE.spellUIRefreshPending = true
    STATE.spellUIRefreshToken = STATE.spellUIRefreshToken + 1
    local token = STATE.spellUIRefreshToken
    C_Timer.After(delay or 0.12, function()
        if token ~= STATE.spellUIRefreshToken then
            return
        end
        STATE.spellUIRefreshPending = false
        if not Page._visible then return end
        if RefreshSpellCards then
            RefreshSpellCards()
        end
    end)
end

UpdateSummary = function()
    if not UI.summaryText then
        return
    end
    local mapName = selectedMapID and GetMapDisplayName(selectedMapID) or L["未选择副本"]
    local boss = GetCurrentBoss()
    if not boss then
        UI.summaryText:SetText(string.format("|cffffd100[%s]|r  %s", tostring(selectedSeason or "-"), mapName))
        return
    end

    local events = boss.events or {}
    local encounterID = tonumber(boss.encounterID)
    local overrideMode = encounterID and GetEncounterModeOverride(encounterID) or "auto"
    local effectiveMode = encounterID and ResolveEffectiveMode(encounterID) or "blizzard"
    UI.summaryText:SetText(string.format(
        "|cffffd100[%s]|r  %s  >  %s  |  %s: |cff00ffcc%d|r  |  %s: |cffffff99%s|r (%s: %s)",
        tostring(selectedSeason or "-"),
        mapName,
        tostring(boss.name or L["未知首领"]),
        L["技能数"],
        #events,
        L["轴"],
        GetModeDisplay(overrideMode),
        L["生效"],
        GetModeDisplay(effectiveMode)
    ))
end

RefreshModeButton = function()
    if not UI.modeDropdown then return end
    local boss = GetCurrentBoss()
    local encounterID = boss and tonumber(boss.encounterID)
    if not encounterID then
        UI.modeDropdown._items = {
            { L["自动"], "auto" },
            { L["固定时间轴"], "fixed" },
            { L["暴雪轴"], "blizzard" },
        }
        UI.modeDropdown._currentValue = "auto"
        UI.modeDropdown:SetText(L["无"])
        if UI.modeDropdown.Disable then UI.modeDropdown:Disable() end
        return
    end

    local overrideMode = GetEncounterModeOverride(encounterID)
    local effectiveMode = ResolveEffectiveMode(encounterID)

    local items = {
        { L["自动"], "auto" },
        { L["固定时间轴"], "fixed" },
        { L["暴雪轴"], "blizzard" },
    }

    UI.modeDropdown._items = items
    UI.modeDropdown._currentValue = overrideMode
    UI.modeDropdown:SetText(string.format("%s -> %s", GetModeDisplay(overrideMode), GetModeDisplay(effectiveMode)))
    if UI.modeDropdown.Enable then UI.modeDropdown:Enable() end
end

local function SyncScrollChildWidth()
    local sharedLeftW
    if UI.bossScrollFrame then
        sharedLeftW = (UI.bossScrollFrame:GetWidth() or 0) - 4
    elseif UI.mapScrollFrame then
        sharedLeftW = (UI.mapScrollFrame:GetWidth() or 0) - 4
    end
    if sharedLeftW then
        if sharedLeftW < 220 then sharedLeftW = 220 end
        if UI.mapScrollChild then
            UI.mapScrollChild:SetWidth(sharedLeftW)
        end
        if UI.bossScrollContent then
            UI.bossScrollContent:SetWidth(sharedLeftW)
        end
    end
    if UI.spellScrollFrame and UI.spellScrollChild then
        local sw = (UI.spellScrollFrame:GetWidth() or 0) - 4
        if sw < 360 then sw = 760 end
        UI.spellScrollChild:SetWidth(sw)
    end
    if UI.spellSettingsGridScroll and UI.spellSettingsGridChild then
        local gw = (UI.spellSettingsGridScroll:GetWidth() or 0) - 4
        if gw < 360 then gw = 760 end
        UI.spellSettingsGridChild:SetWidth(gw)
    end
end

local function FindEventByID(eventID)
    local eid = tonumber(eventID)
    if not eid then return nil end
    local boss = GetCurrentBoss()
    if not (boss and type(boss.events) == "table") then
        return nil
    end
    for _, event in ipairs(boss.events) do
        if GetEventID(event) == eid then
            return event
        end
    end
    return nil
end

SetWidgetUsable = function(widget, enabled)
    if not widget then return end
    -- 按用户要求：禁止通过“变灰/禁用”反馈不可用状态
    -- 这里统一保持可见、可点、全亮，仅由上层控制显示/隐藏
    widget:SetAlpha(1)

    if widget.checkbox and widget.checkbox.Enable then
        widget.checkbox:Enable()
    end

    if widget.editBox and widget.editBox.Enable then
        widget.editBox:Enable()
    end

    if widget.Enable then
        widget:Enable()
    else
        widget:EnableMouse(true)
    end
end

local function SetWidgetInteractable(widget, enabled)
    if not widget then return end
    enabled = (enabled ~= false)

    if widget.checkbox then
        if enabled and widget.checkbox.Enable then
            widget.checkbox:Enable()
        elseif (not enabled) and widget.checkbox.Disable then
            widget.checkbox:Disable()
        end
    end

    if widget.editBox then
        if enabled and widget.editBox.Enable then
            widget.editBox:Enable()
        elseif (not enabled) and widget.editBox.Disable then
            widget.editBox:Disable()
        end
    end

    if widget.dropdown then
        if enabled and widget.dropdown.Enable then
            widget.dropdown:Enable()
        elseif (not enabled) and widget.dropdown.Disable then
            widget.dropdown:Disable()
        end
    end

    if widget.button then
        if enabled and widget.button.Enable then
            widget.button:Enable()
        elseif (not enabled) and widget.button.Disable then
            widget.button:Disable()
        end
    end

    if widget.Enable and widget.Disable then
        if enabled then
            widget:Enable()
        else
            widget:Disable()
        end
    else
        widget:EnableMouse(enabled)
    end
end

-- 复选框标签严格占用自己的 Grid 单元格。长语言只在标签列内裁切，
-- 不允许绘制到右侧输入框；仅在确实被裁切时提供完整文本 Tooltip。
local function ApplyBossSettingsLabelSafety(widgets)
    if type(widgets) ~= "table" then return end
    for _, widget in pairs(widgets) do
        if widget and widget.checkbox and widget.label then
            local label = widget.label
            label:ClearAllPoints()
            label:SetPoint("LEFT", widget.checkbox, "RIGHT", 7, 0)
            label:SetPoint("RIGHT", widget, "RIGHT", -2, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            if label.SetMaxLines then label:SetMaxLines(1) end
            if widget.SetClipsChildren then widget:SetClipsChildren(true) end

            local fullLabel = tostring(label:GetText() or "")
            local availableWidth = math.max(18, (widget:GetWidth() or 0) - 37)
            local truncated = label.GetUnboundedStringWidth
                and (label:GetUnboundedStringWidth() or 0) > availableWidth
            if truncated then
                widget.checkbox:SetScript("OnEnter", function(self)
                    if not GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(fullLabel, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                widget.checkbox:SetScript("OnLeave", function()
                    if GameTooltip then GameTooltip:Hide() end
                end)
            else
                widget.checkbox:SetScript("OnEnter", nil)
                widget.checkbox:SetScript("OnLeave", nil)
            end
        end
    end
end

RefreshSettingsDynamicWidgets = function(mdb)
    local widgets = GetSpellSettingsWidgets()
    if not (type(widgets) == "table" and type(mdb) == "table") then
        return
    end
    ApplyBossSettingsLabelSafety(widgets)

    local modeDropdownWidget = widgets["eventColorMode"]
    local customColor = widgets["eventColor"]
    local centralLeadWidget = widgets["centralLead"]
    local centralTextWidget = widgets["centralText"]
    local preAlertTextWidget = widgets["preAlertText"]
    local timerRenameTextWidget = widgets["timerBarRenameText"]
    local castProgressRenameTextWidget = widgets["castProgressBarRenameText"]
    local targetAlertSourceWidget = widgets["targetAlertStartSource"]
    local targetAlertLabelWidget = widgets["targetAlertStartLabel"]
    local targetAlertLSMWidget = widgets["targetAlertStartLSM"]
    local targetAlertPathWidget = widgets["targetAlertStartPath"]
    local targetAlertTtsWidget = widgets["targetAlertStartTtsText"]
    local targetAlertValueTestWidget = widgets["targetAlertStartValueTest"]
    local targetAlertVoiceWidget = widgets["targetAlertVoiceEnabled"]
    RefreshVoiceLabelDropdown(targetAlertLabelWidget, mdb.targetAlertStartLabel)
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
    if castProgressRenameTextWidget then
        castProgressRenameTextWidget:Show()
        SetWidgetUsable(castProgressRenameTextWidget, mdb.castProgressBarRenameEnabled == true)
    end
    local targetAlertVoiceUsable = mdb.targetAlertStartEnabled == true and mdb.targetAlertVoiceEnabled == true
    local targetAlertSource = NormalizeTriggerSource(mdb.targetAlertStartSource)
    if targetAlertSourceWidget then
        targetAlertSourceWidget:Show()
        SetWidgetUsable(targetAlertSourceWidget, targetAlertVoiceUsable)
    end
    if targetAlertLabelWidget then targetAlertLabelWidget:SetShown(targetAlertSource == "pack") end
    if targetAlertLSMWidget then targetAlertLSMWidget:SetShown(targetAlertSource == "lsm") end
    if targetAlertPathWidget then targetAlertPathWidget:SetShown(targetAlertSource == "file") end
    if targetAlertTtsWidget then targetAlertTtsWidget:SetShown(targetAlertSource == "tts") end
    SetWidgetUsable(targetAlertLabelWidget, targetAlertVoiceUsable and targetAlertSource == "pack")
    SetWidgetUsable(targetAlertLSMWidget, targetAlertVoiceUsable and targetAlertSource == "lsm")
    SetWidgetUsable(targetAlertPathWidget, targetAlertVoiceUsable and targetAlertSource == "file")
    SetWidgetUsable(targetAlertTtsWidget, targetAlertVoiceUsable and targetAlertSource == "tts")
    if targetAlertValueTestWidget then
        targetAlertValueTestWidget:Show()
        SetWidgetUsable(targetAlertValueTestWidget, targetAlertVoiceUsable)
    end
    if targetAlertVoiceWidget then
        targetAlertVoiceWidget:Show()
        SetWidgetUsable(targetAlertVoiceWidget, mdb.targetAlertStartEnabled == true)
    end
    local targetAlertRingWidget = widgets.targetAlertRingEnabled
    if targetAlertRingWidget then
        targetAlertRingWidget:Show()
        SetWidgetUsable(targetAlertRingWidget, mdb.targetAlertStartEnabled == true)
    end
    local targetAlertIconWidget = widgets.targetAlertIconEnabled
    if targetAlertIconWidget then
        targetAlertIconWidget:Show()
        SetWidgetUsable(targetAlertIconWidget, mdb.targetAlertStartEnabled == true)
    end
    local targetAlertTextWidget = widgets.targetAlertTextEnabledV2
    if targetAlertTextWidget then
        targetAlertTextWidget:Show()
        SetWidgetUsable(targetAlertTextWidget, mdb.targetAlertStartEnabled == true)
    end
    local targetAlertStealthWidget = widgets.targetAlertStealthEnabledV2
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

    for i = 0, 2 do
        local prefix = "tr" .. tostring(i)
        local enabled = (mdb[prefix .. "Enabled"] == true)
        local configEnabled = enabled
        if i == 2 then
            configEnabled = (mdb[prefix .. "PlayTextEnabled"] == true)
        end
        local source = NormalizeTriggerSource(mdb[prefix .. "Source"])

        local sourceWidget = widgets[prefix .. "Source"]
        local packWidget = widgets[prefix .. "Label"]
        local lsmWidget = widgets[prefix .. "LSM"]
        local pathWidget = widgets[prefix .. "Path"]
        local ttsWidget = widgets[prefix .. "TtsText"]
        local valueTestWidget = widgets[prefix .. "ValueTest"]
        local countdownLeadWidget = widgets[prefix .. "CountdownLead"]
        local playTextWidget = widgets[prefix .. "PlayTextEnabled"]

        RefreshVoiceLabelDropdown(packWidget, mdb[prefix .. "Label"])

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
            if ttsWidget then ttsWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(packWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        elseif source == "lsm" then
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Show() end
            if pathWidget then pathWidget:Hide() end
            if ttsWidget then ttsWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(lsmWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        elseif source == "tts" then
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Hide() end
            if pathWidget then pathWidget:Hide() end
            if ttsWidget then ttsWidget:Show() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(ttsWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        else
            if packWidget then packWidget:Hide() end
            if lsmWidget then lsmWidget:Hide() end
            if pathWidget then pathWidget:Show() end
            if ttsWidget then ttsWidget:Hide() end
            if valueTestWidget then valueTestWidget:Show() end
            SetWidgetUsable(pathWidget, configEnabled)
            SetWidgetUsable(valueTestWidget, configEnabled)
        end

        SetWidgetInteractable(widgets[prefix .. "Enabled"], true)
        SetWidgetInteractable(sourceWidget, configEnabled)
        SetWidgetInteractable(packWidget, configEnabled)
        SetWidgetInteractable(lsmWidget, configEnabled)
        SetWidgetInteractable(pathWidget, configEnabled)
        SetWidgetInteractable(ttsWidget, configEnabled)
        SetWidgetInteractable(valueTestWidget, configEnabled)
        SetWidgetInteractable(countdownLeadWidget, enabled)
        SetWidgetInteractable(playTextWidget, enabled)
    end
end

local function FindBossGridDropdownText(items, value)
    for _, item in ipairs(type(items) == "table" and items or {}) do
        if type(item) == "table" then
            if item.isMenu then
                local found = FindBossGridDropdownText(item.menu, value)
                if found ~= nil then return found end
            elseif item[2] == value or tostring(item[2]) == tostring(value) then
                return item[1]
            end
        elseif item == value or tostring(item) == tostring(value) then
            return item
        end
    end
    return nil
end

local function RebindSpellSettingsGrid(mdb)
    local Grid = _G.ExwindGrid
    local container = UI.spellSettingsGridChild
    local state = Grid and Grid.ContainerStates and container and Grid.ContainerStates[container]
    local widgets = state and state.widgets
    if not (STATE.spellSettingsGridBound and type(mdb) == "table" and type(widgets) == "table"
            and next(widgets) ~= nil and state.config == mdb) then
        return false
    end

    -- 固定 schema 的控件保留其原有回调；BuildSpellEditorDraft 已原地刷新
    -- 同一张 mdb，因此这些回调继续指向当前技能，而不需要 Grid:Render。
    for _, item in ipairs(SETTINGS_LAYOUT) do
        local widget = widgets[item.key]
        if widget then
            local value = mdb[item.key]
            if item.type == "checkbox" and widget.SetChecked then
                widget:SetChecked(value == true)
            elseif item.type == "input" and widget.SetText then
                local text = tostring(value or "")
                if GetWidgetEditText(widget) ~= text then
                    widget:SetText(text)
                end
            elseif item.type == "dropdown" then
                widget._currentValue = value
                SetDropdownText(widget, FindBossGridDropdownText(widget._items, value) or tostring(value or L["请选择..."]))
            elseif item.type == "lsm_sound" then
                widget._selectedValue = value
                SetDropdownText(widget, tostring(value or L["请选择..."]))
            elseif item.type == "color" then
                widget._currentDb = mdb
                widget._currentKey = item.key
                if widget.UpdateColor then widget:UpdateColor() end
            end
        end
    end
    RefreshSettingsDynamicWidgets(mdb)
    return true
end

local function PlayTriggerPreviewByIndex(triggerIndex)
    local idx = tonumber(triggerIndex)
    if not idx then
        return
    end
    idx = math.floor(idx + 0.5)
    if idx < 0 then idx = 0 end
    if idx > 2 then idx = 2 end

    local event = FindEventByID(selectedEventID)
    if not event then
        return
    end
    local eventID = GetEventID(event)
    if not eventID then
        return
    end

    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayStandaloneSound) then
        return
    end

    local mdb = STATE.spellEditorDraft
    local prefix = "tr" .. tostring(idx)
    local sourceType = NormalizeTriggerSource(type(mdb) == "table" and mdb[prefix .. "Source"] or "pack")
    local triggerCfg = {
        enabled = true,
        sourceType = sourceType,
    }

    if sourceType == "pack" then
        local label = NormalizeTriggerPackLabel(idx, sourceType, type(mdb) == "table" and mdb[prefix .. "Label"] or "")
        if label == "" then
            local rawEvent = GetRawEncounterEventRow(eventID) or event
            label = NormalizeOptionText(rawEvent and rawEvent.voiceLabel)
        end
        if label == "" then
            return
        end
        triggerCfg.label = label
    elseif sourceType == "lsm" then
        local customLSM = NormalizeOptionText(type(mdb) == "table" and mdb[prefix .. "LSM"] or "")
        if customLSM == "" then
            return
        end
        triggerCfg.customLSM = customLSM
    elseif sourceType == "tts" then
        local ttsText = NormalizeOptionText(type(mdb) == "table" and mdb[prefix .. "TtsText"] or "")
        if ttsText == "" then
            return
        end
        local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
        if voices and #voices > 0 then
            local rate = C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate() or 0
            pcall(C_VoiceChat.SpeakText, voices[1].voiceID, ttsText, rate, 100)
        end
        return
    else
        local customPath = NormalizeOptionText(type(mdb) == "table" and mdb[prefix .. "Path"] or "")
        if customPath == "" then
            return
        end
        triggerCfg.customPath = customPath
    end

    local ok, err = Engine:TryPlayStandaloneSound(
        triggerCfg,
        "bosspage_preview:" .. tostring(eventID) .. ":" .. tostring(idx),
        { triggerIndex = idx }
    )
    if not ok then
        return
    end
end

local function RefreshSpellSettingsPanel(expectedRevision)
    if expectedRevision ~= nil and expectedRevision ~= STATE.spellEditorRevision then
        return
    end
    if not (UI.spellSettingsGridChild and UI.spellSettingsEmptyText) then
        return
    end

    if selectedBossCommonSettings then
        STATE.currentSpellSlotKey = nil
        local common = Page.DungeonCommon
        if common and common.HasContent and common:HasContent() then
            SetRightSettingsPresentation(true)
            local Grid = _G.ExwindGrid
            if not Grid then
                ClearSpellSettingsGridActiveRegistration()
                UI.spellSettingsEmptyText:SetText(L["ExwindGrid 不可用，无法渲染副本通用设置。"])
                UI.spellSettingsEmptyText:SetShown(true)
                UI.spellSettingsGridChild:SetHeight(1)
                return
            end
            UI.spellSettingsEmptyText:Hide()
            UI.spellSettingsGridScroll:SetVerticalScroll(0)
            -- 副本通用页会释放同一宿主上的 Boss Grid 控件。必须同步作废
            -- 复用标记，否则返回 Boss 时会把空 widgets 误认为已绑定并跳过重建。
            STATE.spellSettingsGridBound = false
            if common:Render(UI.spellSettingsGridChild) then
                return
            end
        end
        selectedBossCommonSettings = nil
    end

    -- 退出副本通用设置后，先卸载它的独立覆盖层，再恢复 Boss 的标准 Grid。
    -- 否则 Aura/BUFF 行仍会留在同一块右侧区域上方。
    if Page.DungeonCommon and Page.DungeonCommon.Hide then
        Page.DungeonCommon:Hide()
    end
    SetRightSettingsPresentation(false)
    EnsureSelectedEvent()
    local encounterID = GetCurrentEncounterID()
    local eventID = tonumber(selectedEventID)
    local event = FindEventByID(eventID)
    if not encounterID or not eventID or not event then
        STATE.currentSpellSlotKey = nil
        ClearSpellSettingsGridActiveRegistration()
        SetSpellDetailHeaderEmpty(L["点击上方法术卡片后，可在此查看法术描述。"])
        UI.spellSettingsEmptyText:SetShown(true)
        UI.spellSettingsGridChild:SetHeight(1)
        return
    end

    -- 右侧普通事件设置区在渲染时就固定绑定当前编辑槽位。
    -- 后续即使 RoleKey 变化或 UI 分帧刷新，也只能写回这个槽位。
    STATE.currentSpellSlotKey = GetCurrentSpellSlotKey()

    local spellIdentifier = GetEventSpellIdentifier(event)
    local apiName, spellIcon = GetSpellNameAndIcon(spellIdentifier)
    local spellName = (type(apiName) == "string" and apiName ~= "") and apiName or tostring(event.name or "")
    if spellName == "" then
        spellName = L["未知法术"]
    end

    UpdateSpellDetailHeader(spellName, spellIdentifier, eventID, spellIcon, GetEventIconFlags(event))

    local Grid = _G.ExwindGrid
    if not Grid then
        ClearSpellSettingsGridActiveRegistration()
        UI.spellSettingsEmptyText:SetText(L["ExwindGrid 不可用，无法渲染设置区。"])
        UI.spellSettingsEmptyText:SetShown(true)
        UI.spellSettingsGridChild:SetHeight(1)
        return
    end

    UI.spellSettingsEmptyText:Hide()
    UI.spellSettingsGridScroll:SetVerticalScroll(0)
    RunSilentSpellSettingsPopulate(function()
        if expectedRevision ~= nil and expectedRevision ~= STATE.spellEditorRevision then
            return
        end
        if not BuildSpellEditorDraftFromSelectedSpell(expectedRevision) then
            return
        end
        local mdb = STATE.spellEditorDraft
        if type(mdb) ~= "table" then
            return
        end
        RegisterSpellSettingsGridAsActive(SETTINGS.EDITOR_KEY)
        if RebindSpellSettingsGrid(mdb) then
            return
        end
        BuildSpellSettingsLayout(spellName, spellIdentifier, eventID, spellIcon, GetEventIconFlags(event))
        if Grid.SetContainerCols then
            Grid:SetContainerCols(UI.spellSettingsGridChild, C.SPELL_SETTINGS_GRID_COLS)
        end
        if Grid.SetContainerPadding then
            Grid:SetContainerPadding(UI.spellSettingsGridChild, { left = 0, right = 10, top = 10, bottom = 0 })
        end
        -- Boss 页右下设置区现在作为标准 Grid 页面接入：
        -- 编辑模式必须显式绑定当前容器和模块，不能再借用别页的 live edit 状态。
        Grid:Render(UI.spellSettingsGridChild, SETTINGS_LAYOUT, mdb, SETTINGS.EDITOR_KEY)
        STATE.spellSettingsGridBound = true
        EnsureSpellTextInputPersistHooks()
        RefreshSettingsDynamicWidgets(mdb)
    end)
end

local function ScheduleRefreshSpellSettingsPanel()
    -- 取消旧协程前先复位 flag，防止旧协程被丢弃时 flag 卡在 true
    STATE.suspendSpellSettingPersist = false
    local revision = STATE.spellEditorRevision
    local async = GetAsyncHandler()
    -- 副本通用页只有固定的五个 Grid 项和至多 15 条虚拟行，完全不需要
    -- 交给 LibAsync 分帧。Grid 在协程内会每渲染一个 item 就 yield；旧项已
    -- 被释放而新项逐帧出现，正是该页连续闪烁的直接原因。改为下一帧同步
    -- 渲染，既不会阻塞，也能让释放和挂载在一次绘制提交前完成。
    if selectedBossCommonSettings then
        if async and type(async.CancelAsync) == "function" then
            async:CancelAsync("EXBoss_BossPage_SpellSettings")
        end
        C_Timer.After(0, function()
            if not Page._visible or revision ~= STATE.spellEditorRevision then return end
            RefreshSpellSettingsPanel(revision)
        end)
        return
    end
    if async then
        async:Async(function()
            if not Page._visible or revision ~= STATE.spellEditorRevision then return end
            RefreshSpellSettingsPanel(revision)
        end, "EXBoss_BossPage_SpellSettings", true)
    else
        C_Timer.After(0, function()
            if not Page._visible or revision ~= STATE.spellEditorRevision then return end
            RefreshSpellSettingsPanel(revision)
        end)
    end
end

RefreshSpellCards = function()
    if not UI.spellScrollChild then return end

    STATE.spellUIRefreshPending = false
    STATE.spellUIRefreshToken = STATE.spellUIRefreshToken + 1
    STATE.buildToken = STATE.buildToken + 1
    local token = STATE.buildToken

    ReleaseSpellCards()
    UI.spellScrollFrame:SetVerticalScroll(0)

    local boss = GetCurrentBoss()
    if selectedBossCommonSettings and not (Page.DungeonCommon and Page.DungeonCommon.HasContent and Page.DungeonCommon:HasContent()) then
        selectedBossCommonSettings = nil
    end
    if selectedBossCommonSettings then
        -- 通用设置直接占满右侧 Grid；不再生成一张重复的“副本通用设置”法术卡。
        SetRightSettingsPresentation(true)
        UI.spellScrollChild:SetHeight(1)
        ScheduleRefreshSpellSettingsPanel()
        return
    end
    -- 这里是从“副本通用设置”点击任意 Boss 卡片时最早执行的同步路径。
    -- 先隐藏并释放通用页，不能等右侧异步设置面板稍后刷新。
    if Page.DungeonCommon and Page.DungeonCommon.Hide then
        Page.DungeonCommon:Hide()
    end
    SetRightSettingsPresentation(false)
    if not boss and not selectedBossCommonSettings then
        UI.spellEmptyText:SetShown(true)
        UI.spellScrollChild:SetHeight(1)
        selectedEventID = nil
        selectedBossCommonSettings = nil
        STATE.currentSpellSlotKey = nil
        ScheduleRefreshSpellSettingsPanel()
        return
    end
    local events = (boss and type(boss.events) == "table") and boss.events or {}
    if not boss and #events == 0 and not selectedBossCommonSettings then
        UI.spellEmptyText:SetShown(true)
        UI.spellScrollChild:SetHeight(1)
        selectedEventID = nil
        selectedBossCommonSettings = nil
        STATE.currentSpellSlotKey = nil
        ScheduleRefreshSpellSettingsPanel()
        return
    end
    UI.spellEmptyText:Hide()
    local encounterID = GetCurrentEncounterID()
    EnsureSelectedEvent()

    local function BuildOneCard(event, index, cardW)
        if token ~= STATE.buildToken or not Page._visible or not UI.spellScrollChild then
            return nil
        end

        local card = AcquireSpellCard()
        card:SetParent(UI.spellScrollChild)

        local eventID = GetEventID(event)
        local spellID = GetEventSpellIdentifier(event)
        local spellCached = IsSpellDataReady(spellID)
        if spellID and not spellCached then
            RequestSpellDataLoad(spellID)
        end

        local spellName, icon = GetSpellNameAndIcon(spellID)
        local displayName = spellName or (event and event.name) or (L["未知技能 "] .. tostring(index))
        local override = eventID and GetRuntimeSpellConfig(eventID, GetCurrentSpellSlotKey()) or nil
        local spellEnabled = not (override and override.enabled == false)

        local flags = GetEventIconFlags(event)
        local borderR, borderG, borderB = ResolveVoiceEventBorderColor(eventID)
        if borderR == nil or borderG == nil or borderB == nil then
            borderR, borderG, borderB =
                C.DEFAULT_EVENT_BORDER_COLOR.r,
                C.DEFAULT_EVENT_BORDER_COLOR.g,
                C.DEFAULT_EVENT_BORDER_COLOR.b
        end

        local col = (index - 1) % C.SPELL_CARD.cols
        local row = math.floor((index - 1) / C.SPELL_CARD.cols)
        local x = col * (cardW + C.SPELL_CARD.gapX)
        local y = -2 - row * (C.SPELL_CARD.height + C.SPELL_CARD.gapY)
        card:SetPoint("TOPLEFT", UI.spellScrollChild, "TOPLEFT", x, y)
        card:SetSize(cardW, C.SPELL_CARD.height)
        card.eventData = event
        card._eventID = eventID
        card._spellID = spellID
        card._selected = (eventID and tonumber(selectedEventID) == eventID) and true or false
        card._hovered = false

        local alertKind, alertSource = ResolvePrimaryAlertIconSourceByBorder(eventID, borderR, borderG, borderB)
        if alertKind == "atlas" and card.alertIcon and card.alertIcon.SetAtlas then
            card.alertIcon:SetAtlas(alertSource)
            card.alertIcon:Show()
            card.icon:ClearAllPoints()
            card.icon:SetPoint("LEFT", card.alertIcon, "RIGHT", 6, 0)
        elseif alertKind == "texture" and card.alertIcon then
            card.alertIcon:SetTexture(alertSource)
            card.alertIcon:Show()
            card.icon:ClearAllPoints()
            card.icon:SetPoint("LEFT", card.alertIcon, "RIGHT", 6, 0)
        else
            if card.alertIcon then
                card.alertIcon:Hide()
            end
            card.icon:ClearAllPoints()
            card.icon:SetPoint("LEFT", 11, 0)
        end

        if card.targetAlertMarkerHolder then
            if ShouldShowBossTargetAlertTestIcon(eventID) then
                card.targetAlertMarker:SetAtlas(BOSS_TEST_TARGET_ALERT_ATLAS, false)
                card.targetAlertMarkerHolder:Show()
                card.title:ClearAllPoints()
                card.title:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
                card.title:SetPoint("RIGHT", card.targetAlertMarkerHolder, "LEFT", -6, 0)
            else
                card.targetAlertMarkerHolder:Hide()
                card.title:ClearAllPoints()
                card.title:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
                card.title:SetPoint("RIGHT", card, "RIGHT", -12, 0)
            end
        end

        card.icon:SetTexture(icon or 134400)
        local disableText = ""
        if not spellEnabled then
            if override and override.enabled == false then
                disableText = " |cffff6666[" .. L["已禁用"] .. "]|r"
            end
        end
        SetAdaptiveSpellCardTitle(card, string.format("%s%s", tostring(displayName), disableText))
        card.desc:SetText("")
        card.desc:Hide()
        card.leftBar:SetColorTexture(borderR, borderG, borderB, 1)
        card.leftBar:Show()
        card:SetAlpha(1)

        local h = ComputeSpellCardHeight(card)
        card:SetHeight(h)
        card.leftBar:ClearAllPoints()
        card.leftBar:SetPoint("TOPLEFT", 0, 0)
        card.leftBar:SetPoint("BOTTOMLEFT", 0, 0)
        card._borderR = borderR
        card._borderG = borderG
        card._borderB = borderB
        card._applyVisual = function(self)
            local br = Clamp01(self._borderR, 0.35)
            local bg = Clamp01(self._borderG, 0.35)
            local bb = Clamp01(self._borderB, 0.35)
            if self._selected then
                self:SetBackdropColor(0.08, 0.18, 0.30, 0.95)
                self:SetBackdropBorderColor(Clamp01(br * 1.15, 1), Clamp01(bg * 1.15, 1), Clamp01(bb * 1.15, 1), 1)
            elseif self._hovered then
                self:SetBackdropColor(0.08, 0.08, 0.12, 0.82)
                self:SetBackdropBorderColor(Clamp01(br * 1.08, 1), Clamp01(bg * 1.08, 1), Clamp01(bb * 1.08, 1), 1)
            else
                self:SetBackdropColor(0, 0, 0, 0.5)
                self:SetBackdropBorderColor(br, bg, bb, 1)
            end
        end
        card:SetScript("OnClick", function(self)
            if not self._eventID then return end
            CancelPendingSpellTextPersist()
            CommitSpellTextFormState()
            InvalidateSpellEditorContext()
            selectedEventID = tonumber(self._eventID)
            selectedBossCommonSettings = nil
            RefreshActiveSpellCardVisuals()
            ScheduleRefreshSpellSettingsPanel()
        end)
        card:_applyVisual()
        card:Show()

        table.insert(CARD_CACHE.activeSpellCards, card)
        return card
    end

    local function BuildSync(entries)
        local totalW = (UI.spellScrollChild:GetWidth() or 760)
        if totalW < 360 then totalW = 760 end
        local usableW = math.max(360, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        if cardW < 120 then
            cardW = 120
        end

        for i, entry in ipairs(entries) do
            local card = BuildOneCard(entry, i, cardW)
            if not card then return end
        end
        if token == STATE.buildToken and UI.spellScrollChild then
            local rows = math.max(1, math.ceil(#entries / C.SPELL_CARD.cols))
            local totalH = rows * C.SPELL_CARD.height + (rows - 1) * C.SPELL_CARD.gapY + 8
            UI.spellScrollChild:SetHeight(math.max(1, totalH))
        end
    end

    local function BuildAsync(entries)
        local totalW = (UI.spellScrollChild:GetWidth() or 760)
        if totalW < 360 then totalW = 760 end
        local usableW = math.max(360, totalW - 2)
        local cardW = math.floor((usableW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols)
        if cardW < 120 then
            cardW = 120
        end

        for i, entry in ipairs(entries) do
            local card = BuildOneCard(entry, i, cardW)
            if not card then return end
            coroutine.yield()
        end
        if token == STATE.buildToken and UI.spellScrollChild then
            local rows = math.max(1, math.ceil(#entries / C.SPELL_CARD.cols))
            local totalH = rows * C.SPELL_CARD.height + (rows - 1) * C.SPELL_CARD.gapY + 8
            UI.spellScrollChild:SetHeight(math.max(1, totalH))
        end
    end

    local entries = {}
    for i = 1, #events do
        entries[#entries + 1] = events[i]
    end
    PrimeSpellCache(events)
    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            BuildAsync(entries)
        end, "EXBoss_BossPage_SpellCards", true)
    else
        BuildSync(entries)
    end

    -- 右侧设置面板通过 LibAsync 分帧渲染，彻底规避 script ran too long
    -- 保存目标由 currentSpellSlotKey 决定，不因分帧而改变写入语义
    ScheduleRefreshSpellSettingsPanel()
end

RefreshBossList = function(resetScroll)
    if not UI.bossScrollContent then return end
    STATE.bossBuildToken = STATE.bossBuildToken + 1
    local token = STATE.bossBuildToken

    ReleaseBossCards()
    UI.bossScrollContent:SetHeight(1)
    if resetScroll and UI.bossScrollFrame then
        UI.bossScrollFrame:SetVerticalScroll(0)
    end

    local list = BuildBossList(selectedMapID)
    if #list == 0 then
        UI.bossEmptyText:Show()
        UI.bossScrollContent:SetHeight(1)
        selectedEventID = nil
        selectedBossCommonSettings = nil
        return
    end

    UI.bossEmptyText:Hide()

    local function IsValid()
        return token == STATE.bossBuildToken and Page._visible and UI.bossScrollContent ~= nil
    end

    local function ApplyVisual(self)
        local selected = self._selected
        local hovered = self._hovered
        if selected then
            self:SetBackdropColor(0.1, 0.4, 0.8, 0.3)
            self:SetBackdropBorderColor(0, 0.8, 1, 1)
            self.activeBar:Show()
            self.nameText:SetTextColor(1, 0.86, 0.48)
        elseif hovered then
            self:SetBackdropColor(0.08, 0.08, 0.08, 0.88)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            self.activeBar:Hide()
            self.nameText:SetTextColor(0.95, 0.95, 0.95)
        else
            self:SetBackdropColor(0.04, 0.04, 0.04, 0.8)
            self:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.95)
            self.activeBar:Hide()
            self.nameText:SetTextColor(0.82, 0.66, 0.46)
        end
    end

    local y = -4
    local function ApplyPortrait(card)
        if not IsValid() or not card then return false end

        if card._dungeonCommon then
            if card.creature then
                card.creature:Hide()
            end
            if card.noPortraitText then
                card.noPortraitText:SetText("⚙")
                card.noPortraitText:Show()
            end
            return true
        end

        local displayID = tonumber(card._displayID)
        if displayID and card.creature and card.creature.SetDisplayInfo then
            if card._appliedDisplayID ~= displayID then
                if card.creature.ClearModel then
                    card.creature:ClearModel()
                end
                card.creature:SetDisplayInfo(displayID)
                card._appliedDisplayID = displayID
            end
            ApplyModelTune(card.creature)
            card.creature:Show()
            if card.noPortraitText then
                card.noPortraitText:Hide()
            end
        else
            card._appliedDisplayID = nil
            if card.creature then
                card.creature:Hide()
            end
            if card.noPortraitText then
                card.noPortraitText:SetText(L["无动态头像"])
                card.noPortraitText:Show()
            end
        end
        return true
    end

    local function BuildOne(entry)
        if not IsValid() then return false end
        local b = AcquireBossCard()
        local boss = entry.data

        b:SetParent(UI.bossScrollContent)
        b:SetPoint("TOPLEFT", 0, y)
        b:SetPoint("RIGHT", UI.bossScrollContent, "RIGHT", -1, 0)
        b:SetHeight(68)
        b:Show()

        b._selected = (entry.index == selectedBossIndex)
        b._hovered = false
        b._applyVisual = ApplyVisual
        b.index = entry.index

        b.nameText:SetText(tostring(boss and boss.name or (L["未知首领 "] .. tostring(entry.index))))
        b.detailText:SetText("ID: " .. tostring(boss and boss.encounterID or "-"))

        if b.noPortraitText then
            b.noPortraitText:Hide()
        end
        b._displayID = ResolveBossDisplayID(boss)
        b._appliedDisplayID = nil
        if b._displayID and b.creature then
            b.creature:Hide()
            if b.noPortraitText then
                b.noPortraitText:SetText(L["加载中"])
                b.noPortraitText:Show()
            end
        else
            if b.creature then
                b.creature:Hide()
            end
            if b.noPortraitText then
                b.noPortraitText:SetText(L["无动态头像"])
                b.noPortraitText:Show()
            end
        end

        b:SetScript("OnClick", function(self)
            CommitSpellTextFormState()
            InvalidateSpellEditorContext()
            selectedBossIndex = self.index
            selectedEventID = nil
            selectedBossCommonSettings = nil
            SaveSelection()
            RefreshActiveBossCardVisuals()
            UpdateSummary()
            RefreshModeButton()
            RefreshSpellCards()
        end)

        b:_applyVisual()
        table.insert(CARD_CACHE.activeBossCards, b)
        y = y - 72
        return true
    end

    local function BuildDungeonCommonEntry()
        local common = Page.DungeonCommon
        if not (common and common.HasContent and common:HasContent()) then
            return true
        end

        local b = AcquireBossCard()
        b:SetParent(UI.bossScrollContent)
        b:SetPoint("TOPLEFT", 0, y)
        b:SetPoint("RIGHT", UI.bossScrollContent, "RIGHT", -1, 0)
        b:SetHeight(68)
        b:Show()

        b._dungeonCommon = true
        b.index = nil
        b._selected = selectedBossCommonSettings == true
        b._hovered = false
        b._applyVisual = ApplyVisual
        b.nameText:SetText(L["副本通用设置"])
        b.detailText:SetText(L["当前副本的共享机制与音效。"])
        b._displayID = nil
        b._appliedDisplayID = nil
        if b.creature then
            b.creature:Hide()
        end
        if b.noPortraitText then
            b.noPortraitText:SetText("⚙")
            b.noPortraitText:Show()
        end
        b:SetScript("OnClick", function()
            CommitSpellTextFormState()
            InvalidateSpellEditorContext()
            selectedBossIndex = nil
            selectedEventID = nil
            selectedBossCommonSettings = true
            RefreshActiveBossCardVisuals()
            UpdateSummary()
            RefreshModeButton()
            RefreshSpellCards()
        end)
        b:_applyVisual()
        table.insert(CARD_CACHE.activeBossCards, b)
        y = y - 72
        return true
    end

    local function Finalize()
        if not IsValid() then return end
        UI.bossScrollContent:SetHeight(math.max(1, -y + 6))
        if resetScroll and UI.bossScrollFrame then
            UI.bossScrollFrame:SetVerticalScroll(0)
        end

        local cards = CARD_CACHE.activeBossCards
        local function RenderPortraitsSync()
            for i = 1, #cards do
                if not ApplyPortrait(cards[i]) then
                    return
                end
            end
        end
        local function RenderPortraitsAsync()
            for i = 1, #cards do
                if not ApplyPortrait(cards[i]) then
                    return
                end
                coroutine.yield()
            end
        end
        local async = GetAsyncHandler()
        if async then
            async:Async(function()
                RenderPortraitsAsync()
            end, "EXBoss_BossPage_BossPortraits", true)
        else
            RenderPortraitsSync()
        end
    end

    local function BuildSync(entries)
        for _, entry in ipairs(entries) do
            if not BuildOne(entry) then
                return
            end
        end
        if not BuildDungeonCommonEntry() then
            return
        end
        Finalize()
    end

    local function BuildAsync(entries)
        for _, entry in ipairs(entries) do
            if not BuildOne(entry) then
                return
            end
            coroutine.yield()
        end
        if not BuildDungeonCommonEntry() then
            return
        end
        Finalize()
    end

    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            BuildAsync(list)
        end, "EXBoss_BossPage_BossList", true)
    else
        BuildSync(list)
    end
end

RefreshMapTabs = function(resetScroll)
    if not UI.mapScrollChild then return end
    STATE.mapBuildToken = STATE.mapBuildToken + 1
    local token = STATE.mapBuildToken

    ReleaseMapTabs()
    UI.mapScrollChild:SetHeight(1)
    if resetScroll and UI.mapScrollFrame then
        UI.mapScrollFrame:SetVerticalScroll(0)
    end

    local mapList = BuildMapList(selectedSeason)
    if #mapList == 0 then
        UI.mapEmptyText:Show()
        UI.mapScrollChild:SetHeight(1)
        return
    end

    UI.mapEmptyText:Hide()

    local function IsValid()
        return token == STATE.mapBuildToken and Page._visible and UI.mapScrollChild ~= nil
    end

    local function ApplyVisual(self)
        local selected = tonumber(self.mapID) == tonumber(selectedMapID)
        local hovered = self._hovered
        -- 外层按钮完全透明；选中和 hover 只作用于图标方框。
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if selected then
            self.iconFrame:SetBackdropColor(0.20, 0.43, 0.75, 0.95)
            -- 选中只改变填充色，仍保留原本的白色图标描边。
            self.iconFrame:SetBackdropBorderColor(0.76, 0.80, 0.90, 1)
            self.icon:SetDesaturated(false)
            self.text:SetTextColor(1, 0.85, 0.35)
        elseif hovered then
            self.iconFrame:SetBackdropColor(0.18, 0.21, 0.32, 0.95)
            self.iconFrame:SetBackdropBorderColor(0.82, 0.86, 0.96, 1)
            self.icon:SetDesaturated(false)
            self.text:SetTextColor(0.95, 0.95, 0.95)
        else
            self.iconFrame:SetBackdropColor(0.15, 0.18, 0.28, 0.95)
            self.iconFrame:SetBackdropBorderColor(0.76, 0.80, 0.90, 1)
            self.icon:SetDesaturated(true)
            self.text:SetTextColor(0.75, 0.75, 0.78)
        end
    end

    local perRow = 4
    local gapX = 3
    local gapY = 2
    local leftPad = 0
    local topPad = 0
    local availW = (UI.mapScrollChild:GetWidth() or 208) - (leftPad * 2)
    if availW < 200 then availW = 200 end
    local cellW = math.floor((availW - ((perRow - 1) * gapX)) / perRow)
    if cellW < 50 then
        cellW = 50
    end
    local cellH = 106
    local yBottom = 0

    local function BuildOne(i, mapID)
        if not IsValid() then return false end
        local b = AcquireMapTab()
        b:SetParent(UI.mapScrollChild)
        b:Show()
        b.mapID = mapID
        b:SetSize(cellW, cellH)

        local style = GetMapIconRenderStyle(mapID)
        local iconSize = cellW - 2
        if iconSize > 90 then iconSize = 90 end
        if iconSize < 46 then iconSize = 46 end
        local scale = tonumber(style.scale) or 1
        if scale > 0 then
            iconSize = math.floor(iconSize * scale + 0.5)
        end
        if iconSize > (cellW - 2) then
            iconSize = cellW - 2
        end
        if iconSize < 46 then
            iconSize = 46
        end
        b.iconFrame:SetSize(iconSize, iconSize)
        b.iconFrame:ClearAllPoints()
        b.iconFrame:SetPoint("TOP", tonumber(style.offsetX) or 0, -1 + (tonumber(style.offsetY) or 0))
        b.iconFrame:Show()
        b.text:SetWidth(cellW - 4)

        b.icon:SetTexture(GetMapIcon(mapID))
        local tex = style.tex
        if type(tex) == "table" and #tex >= 4 then
            b.icon:SetTexCoord(tex[1], tex[2], tex[3], tex[4])
        else
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        b.text:SetText(GetMapShortDisplayName(mapID))

        local row = math.floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        b:SetPoint("TOPLEFT", leftPad + col * (cellW + gapX), -topPad - row * (cellH + gapY))

        b._hovered = false
        b._applyVisual = ApplyVisual
        b:SetScript("OnClick", function(self)
            CommitSpellTextFormState()
            InvalidateSpellEditorContext()
            selectedMapID = self.mapID
            selectedBossIndex = nil
            selectedEventID = nil
            selectedBossCommonSettings = nil
            NormalizeSelection()
            EnsureCurrentSceneRuntime()
            SaveSelection()
            RefreshActiveMapTabVisuals()
            RefreshBossList(true)
            UpdateSummary()
            RefreshModeButton()
            RefreshSpellCards()
        end)
        b:_applyVisual()

        table.insert(CARD_CACHE.activeMapTabs, b)
        yBottom = row * (cellH + gapY) + cellH
        return true
    end

    local function Finalize()
        if not IsValid() then return end
        UI.mapScrollChild:SetHeight(math.max(1, yBottom + topPad + 4))
        if resetScroll and UI.mapScrollFrame then
            UI.mapScrollFrame:SetVerticalScroll(0)
        end
    end

    local function BuildSync(entries)
        for i, mapID in ipairs(entries) do
            if not BuildOne(i, mapID) then
                return
            end
        end
        Finalize()
    end

    local function BuildAsync(entries)
        for i, mapID in ipairs(entries) do
            if not BuildOne(i, mapID) then
                return
            end
            coroutine.yield()
        end
        Finalize()
    end

    local async = GetAsyncHandler()
    if async then
        async:Async(function()
            BuildAsync(mapList)
        end, "EXBoss_BossPage_MapTabs", true)
    else
        BuildSync(mapList)
    end
end

RefreshSeasonDropdown = function(seasons)
    if not UI.seasonDropdown then return end
    local items = {}
    for _, row in ipairs(C.MAP_CATEGORY_ITEMS) do
        items[#items + 1] = { tostring(row[1]), row[2] }
    end
    UI.seasonDropdown._items = items
    UI.seasonDropdown._currentValue = selectedSeason
    local displayText = tostring(selectedSeason or "-")
    for _, item in ipairs(items) do
        if item[2] == selectedSeason then
            displayText = item[1]
            break
        end
    end
    UI.seasonDropdown:SetText(displayText)
end

function Page:Render(leftFrame, contentFrame)
    if not leftFrame or not contentFrame then return end
    STATE.pageRenderGeneration = STATE.pageRenderGeneration + 1
    local renderGeneration = STATE.pageRenderGeneration

    EnsureUI(leftFrame, contentFrame)

    UI.leftRoot:SetParent(leftFrame)
    UI.leftRoot:ClearAllPoints()
    UI.leftRoot:SetAllPoints(leftFrame)
    UI.leftRoot:Show()

    UI.rightRoot:SetParent(contentFrame)
    UI.rightRoot:ClearAllPoints()
    UI.rightRoot:SetAllPoints(contentFrame)
    UI.rightRoot:Show()
    if UI.titleControlHost then
        UI.titleControlHost:Show()
    end

    Page._visible = true

    local seasons = NormalizeSelection()
    EnsureCurrentSceneRuntime()
    SyncSpellSettingsFrameHeight()
    SyncScrollChildWidth()
    RefreshSeasonDropdown(seasons)
    RefreshMapTabs(true)
    RefreshBossList(true)
    UpdateSummary()
    RefreshModeButton()

    C_Timer.After(0, function()
        if not Page._visible
            or renderGeneration ~= STATE.pageRenderGeneration
            or UI.leftRoot:GetParent() ~= leftFrame
            or UI.rightRoot:GetParent() ~= contentFrame then
            return
        end
        SyncSpellSettingsFrameHeight()
        SyncScrollChildWidth()
        RefreshSpellDetailHeaderLayout()
        RefreshSpellCards()
    end)
end

function Page:Hide()
    STATE.pageRenderGeneration = STATE.pageRenderGeneration + 1
    CommitSpellTextFormState()
    InvalidateSpellEditorContext()
    Page._visible = false
    STATE.buildToken = STATE.buildToken + 1
    STATE.bossBuildToken = STATE.bossBuildToken + 1
    STATE.mapBuildToken = STATE.mapBuildToken + 1
    STATE.spellUIRefreshPending = false
    STATE.spellUIRefreshToken = STATE.spellUIRefreshToken + 1

    local Grid = _G.ExwindGrid
    if Grid and Grid.IsLiveEditing and Grid.LiveContainer == UI.spellSettingsGridChild then
        Grid:ToggleLiveEdit(UI.spellSettingsGridChild)
    end
    if Grid and Grid.ReleaseContainerWidgets and UI.spellSettingsGridChild then
        Grid:ReleaseContainerWidgets(UI.spellSettingsGridChild)
    end
    if Grid and Grid.ClearContainerPadding and UI.spellSettingsGridChild then
        Grid:ClearContainerPadding(UI.spellSettingsGridChild)
    end
    if Grid and Grid.ClearContainerCols and UI.spellSettingsGridChild then
        Grid:ClearContainerCols(UI.spellSettingsGridChild)
    end
    STATE.spellSettingsGridBound = false
    STATE.spellEditorDraft = nil
    ClearSpellSettingsGridActiveRegistration()

    ReleaseMapTabs()
    ReleaseBossCards()
    ReleaseSpellCards()

    if UI.leftRoot then UI.leftRoot:Hide() end
    if UI.rightRoot then UI.rightRoot:Hide() end
    if UI.titleControlHost then UI.titleControlHost:Hide() end
    if Page.DungeonCommon and Page.DungeonCommon.Hide then Page.DungeonCommon:Hide() end
end

if not Page._settingsEventsRegistered then
    ExwindTools:WatchState(SETTINGS.EDITOR_KEY .. ".ButtonClicked", "ExBoss.BossPage.SpellSettingButton", function(info)
        if not info or not info.key then return end

        local triggerIdx = info.key:match("^tr([012])SourceTest$")
        if not triggerIdx then
            triggerIdx = info.key:match("^tr([012])ValueTest$")
        end
        if triggerIdx then
            PlayTriggerPreviewByIndex(tonumber(triggerIdx))
            return
        end
        if info.key == "targetAlertStartValueTest" then
            local mdb = STATE.spellEditorDraft
            if type(mdb) == "table" then
                PlayTargetAlertStartPreview(mdb)
            end
            return
        end
    end)

    local function HandleSpellEditorIdentityChanged()
        local wasVisible = (Page._visible == true)
        if wasVisible then
            -- 页面可见时，旧上下文仍有效，先提交最后一次输入。
            CommitSpellTextFormState()
        end
        -- 隐藏页面没有可提交的编辑器；两种情况都必须丢弃旧临时状态。
        InvalidateSpellEditorContext()
        if wasVisible then
            RefreshSpellCards()
        end
    end

    ExwindTools:WatchState("RoleKey", "ExBoss.BossPage.RoleState", function()
        HandleSpellEditorIdentityChanged()
    end)

    ExwindTools:WatchState("SpecID", "ExBoss.BossPage.SpecState", function()
        HandleSpellEditorIdentityChanged()
    end)

    Page._settingsEventsRegistered = true
end

-- Core deliberately does not route changedPath.  This editor therefore
-- persists the current draft as one module transaction, rather than restoring
-- a field-level state bus or rebuilding its Grid.
local function RefreshActiveSurfaces()
    if STATE.suspendSpellSettingPersist or not Page._visible then return end
    STATE.spellSettingsDirty = true
    for key in pairs(GRID_DRAFT_FIELDS) do
        PersistSpellEditorDraftToSelectedSpell(key)
    end
    STATE.spellSettingsDirty = false
    RefreshSettingsDynamicWidgets(STATE.spellEditorDraft)
end

EXUI:RegisterModuleValueController(SETTINGS.EDITOR_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

-- 供外部（如 Profiles:LoadProfileToCurrent）调用，切换方案后刷新右侧设置区 UI
function Page:RefreshSpellUI()
    if not Page._visible then return end
    local renderGeneration = STATE.pageRenderGeneration
    C_Timer.After(0, function()
        if not Page._visible or renderGeneration ~= STATE.pageRenderGeneration then return end
        RefreshSpellCards()
    end)
end

if not Page._eventsRegistered then
    ExwindTools:RegisterEvent("PORTRAITS_UPDATED", "ExBoss.BossPage.Portraits", function()
        if not Page._visible then return end
        -- 头像事件非常高频，禁止触发整表重建；PlayerModel 会自行刷新贴图。
    end)

    ExwindTools:RegisterEvent("SPELL_DATA_LOAD_RESULT", "ExBoss.BossPage.SpellCache", function(_, spellID, success)
        if spellID then
            CARD_CACHE.spellCachePending[spellID] = nil
            CARD_CACHE.spellTextCache[spellID] = nil
        end
        if not success then return end
        -- 副本通用设置的光环行悬停也会请求法术资料；不能因此重建整张右侧设置页，
        -- 否则虚拟列表会被重新 SetData() 并跳回第 0 行。
        if Page._visible and not selectedBossCommonSettings and CurrentBossHasSpellID(spellID) then
            QueueSpellUIRefresh(0.10)
        end
    end)

    ExwindTools:RegisterEvent("SPELL_TEXT_UPDATE", "ExBoss.BossPage.SpellText", function()
        wipe(CARD_CACHE.spellTextCache)
        -- 光环通用页不使用 Boss 法术卡的文本缓存。该事件会随客户端逐步
        -- 加载法术资料连发；若仍整页刷新，会反复释放并重建 Aura Grid，造成
        -- 闪屏与大量短命投影表。可见行已有静态名称/图标后备，不必为此重渲染。
        if Page._visible and not selectedBossCommonSettings then
            QueueSpellUIRefresh(0.10)
        end
    end)

    Page._eventsRegistered = true
end
