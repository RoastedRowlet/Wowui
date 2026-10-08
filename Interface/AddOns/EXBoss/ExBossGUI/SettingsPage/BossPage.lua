---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local GC = ExwindTools.GUIColors
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
        gapY = 4,
        height = 34,
        titleFontSizes = { ExwindTools.GUIMetrics.font.exboss.navigationTitle, ExwindTools.GUIMetrics.font.title, ExwindTools.GUIMetrics.font.exboss.previewText, ExwindTools.GUIMetrics.font.text },
    },
    -- 右侧技能卡片列表最多显示两行；实际只有一行时不预留空白行。
    SPELL_LIST_VISIBLE_ROWS = 2,
    -- 原型右侧技能导航是 5 列 × 2 行；字号与图标需要在实机缩放下仍然清楚。
    -- 页面高度始终取宿主实际可用高度，不把原型的 1050px 画布写回游戏窗口。
    SPELL_LIST_HEIGHT = 72,
    SPELL_DETAIL_HEIGHT = 148,
    SPELL_LIST_TOP_INSET = 6,
    SPELL_SETTINGS_GRID_COLS = 200,
    PREALERT_FIXED_SECS = 5,
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
        { "5", "5" },
        { "4", "4" },
        { "3", "3" },
        { "2", "2" },
        { "1", "1" },
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

-- [卡片/Grid 迁移边界：Boss 主页面]
-- C 中的卡片几何可由共享规范承接，但事件/extra/副本/首领的业务顺序、稳定选择身份与两行视口语义禁止修改。
-- 普通技能、encounter extra、DungeonCommon 三种详情共享同一右侧宿主；不得为迁移复制宿主或新增第二套选择状态。

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

function Page.ResolvePackPreviewPath(label)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and engine.ResolveStandaloneSound) then return nil end
    local info = engine:ResolveStandaloneSound(
        { enabled = true, sourceType = "pack", label = tostring(label or "") },
        { triggerIndex = 0, ignoreState = true })
    return info and info.file or nil
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
local selectedExtraKey
local selectedBossCommonSettings
local STATE = {
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
    voicePreviewGeneration = 0,
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
local RefreshVoicePreviewDisplay
local StartVoiceSequencePreview
local CancelVoiceSequencePreview
local RefreshCountdownSegmentedControl
local RefreshVoicePreviewTimeline
local ApplyBossCustomCardLayouts

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
    if not (Grid and Grid.FindMountedWidget and UI.spellSettingsGridChild) then
        return nil
    end
    return setmetatable({}, { __index = function(t, key)
        local widget = Grid:FindMountedWidget(UI.spellSettingsGridChild, key)
        rawset(t, key, widget)
        return widget
    end })
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
    if Page.Extras then Page.Extras:Hide() end
    if CancelVoiceSequencePreview then CancelVoiceSequencePreview() end
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
            -- 这两个焦点槽位里有 Core 的输入框画器（HookScript 挂的，与业务脚本
            -- 同在一个 extrinsic 槽位）。SetScript 会把画器一起清掉，所以先走
            -- ClearControlScript 丢掉该槽位的安装记录，写完业务脚本后再调一次
            -- ApplyControlAppearance 把画器补回来；顺序不能颠倒。
            EXUI:ClearControlScript(widget, "OnEditFocusGained")
            EXUI:ClearControlScript(widget, "OnEditFocusLost")
            widget:SetScript("OnEditFocusGained", function(self)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(unpack(GC.accent))
                end
            end)
            widget:SetScript("OnEditFocusLost", function(self)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(unpack(GC.panelBorder))
                end
                UpdatePlaceholder()
                local text = GetWidgetEditText(self)
                if text ~= nil then
                    SetSpellTextFormStateValue(key, text)
                end
                CancelPendingSpellTextPersist(key)
                CommitSpellTextFormState(key)
            end)
            -- 两个焦点槽位已写好业务脚本，这里把 Core 画器装回去。
            EXUI:ApplyControlAppearance(widget)
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
    if n > 5 then n = 5 end
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
    return Engine:TryPlayStandaloneSound(triggerCfg, "bosspage_target_alert_preview", { triggerIndex = 0 })
end

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
    if selectedExtraKey then
        local registry = ExBoss.BossEncounters
        if registry and registry:GetExtra(GetCurrentEncounterID(), selectedExtraKey) then
            selectedEventID = nil
            return
        end
        selectedExtraKey = nil
    end
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
    s = s:gsub("\n%s*\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
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
            for _, line in ipairs(tip.lines) do
                local text = line and line.leftText
                if line.type == Enum.TooltipDataLineType.SpellDescription and text and text ~= "" then
                    text = NormalizeSpellDescText(text)
                    if text ~= "" then
                        table.insert(lines, WrapColorText(text, line.leftColor))
                    end
                end
            end
            if #lines > 0 then
                local desc = table.concat(lines, "\n")
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

    local compact = headerW <= 820
    local iconSize = compact and 60 or 64
    local leftRailWidth = compact and 74 or 78
    local inset, topInset = 8, 8
    UI.spellDetailTitle:SetFont(ExwindTools.MAIN_FONT, compact and 18 or 20, "")
    UI.spellDetailIcon:SetSize(iconSize, iconSize)
    UI.spellDetailIcon:ClearAllPoints()
    UI.spellDetailIcon:SetPoint("TOPLEFT", inset + (leftRailWidth - iconSize) / 2, -topInset)
    local iconInset = PixelUtil.GetNearestPixelSize(1, UI.spellDetailHeader:GetEffectiveScale(), 1)
    UI.spellDetailIcon:SetCornerRadius(10 - iconInset)
    UI.spellDetailIconBorder:SetSize(iconSize + iconInset * 2, iconSize + iconInset * 2)
    UI.spellDetailIconBorder:ClearAllPoints()
    UI.spellDetailIconBorder:SetPoint("TOPLEFT", UI.spellDetailIcon, "TOPLEFT", -iconInset, iconInset)
    EXUI:ClearControlSurface(UI.spellDetailIconBorder)

    local contentX = inset + leftRailWidth + 10
    local actionWidth = compact and 246 or 286
    local chipGap = 6
    local identityWidth = math.max(140, headerW - contentX - inset - actionWidth - 12)
    local bodyWidth = math.max(1, headerW - contentX - inset)

    UI.spellDetailTitle:ClearAllPoints()
    UI.spellDetailTitle:SetPoint("TOPLEFT", UI.spellDetailHeader, "TOPLEFT", contentX, -topInset - 1)
    UI.spellDetailTitle:SetWordWrap(false)
    UI.spellDetailTitle:SetWidth(math.max(60, math.min(identityWidth,
        math.ceil(UI.spellDetailTitle:GetUnboundedStringWidth() or 0) + 6)))
    UI.spellDetailMeta:ClearAllPoints()
    UI.spellDetailMeta:SetPoint("LEFT", UI.spellDetailTitle, "RIGHT", 5, 0)
    UI.spellDetailMeta:SetWidth(24)
    UI.spellDetailMeta:SetWordWrap(false)
    UI.spellDetailMeta:Hide()

    local chipX = contentX
    for _, chip in ipairs({ UI.spellDetailCastChip, UI.spellDetailRangeChip,
        UI.spellDetailSpellIDChip, UI.spellDetailEventIDChip }) do
        local labelWidth = chip.label and math.ceil(chip.label:GetUnboundedStringWidth() or 0) or 0
        local valueWidth = math.ceil(chip.value:GetUnboundedStringWidth() or 0)
        local width = math.max(54, labelWidth + valueWidth + (labelWidth > 0 and 24 or 20))
        chip:SetSize(width, 26)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", UI.spellDetailHeader, "TOPLEFT", chipX, -37)
        chipX = chipX + width + chipGap
    end

    if UI.titleControlHost and UI.titleControlHost:IsShown() then
        local buttonWidth = compact and 48 or 56
        local dropdownWidth = compact and 126 or 150
        UI.titleControlHost:SetSize(actionWidth, 28)
        UI.titleControlHost:ClearAllPoints()
        UI.titleControlHost:SetPoint("TOPRIGHT", UI.spellDetailHeader, "TOPRIGHT", -inset, -topInset)
        UI.modeDropdown:SetWidth(dropdownWidth)
        UI.modeDropdown:ClearAllPoints()
        UI.modeDropdown:SetPoint("RIGHT", UI.titleControlHost, "RIGHT", 0, 0)
        UI.modeLabelText:Hide()
        UI.modeTestStopBtn:SetSize(buttonWidth, 28)
        UI.modeTestStopBtn:ClearAllPoints()
        UI.modeTestStopBtn:SetPoint("RIGHT", UI.modeDropdown, "LEFT", -8, 0)
        UI.modeTestStartBtn:SetSize(buttonWidth, 28)
        UI.modeTestStartBtn:ClearAllPoints()
        UI.modeTestStartBtn:SetPoint("RIGHT", UI.modeTestStopBtn, "LEFT", -6, 0)
    end
    UI.spellDetailBodyScroll:ClearAllPoints()
    UI.spellDetailBodyScroll:SetPoint("TOPLEFT", UI.spellDetailCastChip, "BOTTOMLEFT", 0, -8)
    UI.spellDetailBodyScroll:SetPoint("BOTTOMRIGHT", UI.spellDetailHeader, "BOTTOMRIGHT", -inset, 10)
    UI.spellDetailBody:SetWidth(bodyWidth)
    local bodyTextHeight = math.max(20, math.ceil(UI.spellDetailBody:GetStringHeight() or 0))
    local detailHeight = math.max(C.SPELL_DETAIL_HEIGHT, 83 + bodyTextHeight)
    UI.spellDetailHeader:SetHeight(detailHeight)
    if UI.spellDetailBodyChild then
        UI.spellDetailBodyChild:SetSize(bodyWidth,
            math.max(bodyTextHeight, math.max(1, UI.spellDetailBodyScroll:GetHeight())))
        UI.spellDetailBodyScroll:UpdateScrollChildRect()
        UI.spellDetailBodyScroll:SetVerticalScroll(0)
    end
end

local function GetSpellListViewportHeight()
    return math.max(C.SPELL_CARD.height,
        math.min(C.SPELL_LIST_HEIGHT, tonumber(UI.spellListMeasuredHeight) or C.SPELL_LIST_HEIGHT))
end

-- [混合函数边界] 这里仅 SetPoint/尺寸属于可迁移布局；描述区边界、共享 Grid 宿主和滚动层级禁止改义。
local function SyncBossRightViewport()
    if not (UI.rightViewport and UI.rightRoot) then return end
    local viewport = UI.rightViewport
    local width = math.max(1, viewport:GetWidth())
    local height = math.max(1, viewport:GetHeight())
    if math.abs(UI.rightRoot:GetWidth() - width) > 0.01 then UI.rightRoot:SetWidth(width) end
    if math.abs(UI.rightRoot:GetHeight() - height) > 0.01 then UI.rightRoot:SetHeight(height) end
    viewport:UpdateScrollChildRect()
    viewport:SetVerticalScroll(0)
end

local function ApplyBossRightPanelLayout()
    SyncBossRightViewport()
    if not (UI.rightRoot and UI.spellSettingsFrame) then return end
    -- 法术少于六个时只占一行；原有启用控件直接放进说明卡左下角。
    UI.spellDetailHeader:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 16, -(GetSpellListViewportHeight() + 8 + C.SPELL_LIST_TOP_INSET))
    UI.spellDetailHeader:SetPoint("TOPRIGHT", UI.rightRoot, "TOPRIGHT", -16, -(GetSpellListViewportHeight() + 8 + C.SPELL_LIST_TOP_INSET))
    if UI.spellSummaryEnableHost then
        UI.spellSummaryEnableHost:SetPoint("BOTTOMLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 8, 7)
    end
    UI.spellSettingsFrame:SetPoint("TOPLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 0, -8)
    UI.spellSettingsFrame:SetPoint("BOTTOMRIGHT", UI.rightRoot, "BOTTOMRIGHT", -16, 0)
end

-- [卡片/Grid 迁移边界：普通技能设置]
-- 允许：只按共享规范调整五组现有声明的 x/y/w/h 与外层卡片呈现。
-- 禁止：修改 key/type/items、同槽来源显隐、字段/语音触发业务顺序、draft/Store 回调或试听行为。
-- 五组内容只使用共享 SettingsCard；原控件 key 与回调保持不变。
local function BuildSpellSettingsLayout(spellName, spellIdentifier, eventID, spellIcon, iconFlags)
    for i = #SETTINGS_LAYOUT, 1, -1 do
        SETTINGS_LAYOUT[i] = nil
    end

    local rows = {
        { key = "enabled", type = "checkbox", x = 3, y = 1, w = 36, h = 5, label = L["启用"], labelSize = ExwindTools.GUIMetrics.font.cardTitle },

        { key = "eventColorEnabled", type = "checkbox", x = 4, y = 16, w = 26, h = 5, label = L["颜色"] },
        { key = "eventColorMode", type = "dropdown", x = 33, y = 16, w = 35, h = 5, label = "", labelPos = "left", items = EVENT_COLOR_ITEMS_FUNC, search = true },
        { key = "eventColor", type = "color", x = 73, y = 16, w = 33, h = 5, label = L["自定义颜色"] },
        { key = "centralEnabled", type = "checkbox", x = 4, y = 23, w = 26, h = 5, label = L["中央文本"] },
        { key = "centralLead", type = "input", x = 34, y = 23, w = 12, h = 5, label = L["(秒)"], labelPos = "right" },
        { key = "centralText", type = "input", x = 57, y = 23, w = 49, h = 5, label = "" },
        { key = "countdownEnabled", type = "checkbox", x = 4, y = 30, w = 26, h = 5, label = L["倒数文本"] },
        { key = "preAlertText", type = "input", x = 34, y = 30, w = 72, h = 5, label = "" },
        { key = "timerBarRenameEnabled", type = "checkbox", x = 4, y = 37, w = 26, h = 5, label = L["计时条改名"] },
        { key = "timerBarRenameText", type = "input", x = 34, y = 37, w = 72, h = 5, label = "" },

        { key = "ringEnabled", type = "checkbox", x = 112, y = 16, w = 28, h = 5, label = L["显示圆环"] },
        { key = "castProgressBarEnabled", type = "checkbox", x = 112, y = 23, w = 28, h = 5, label = L["显示读条"] },
        { key = "ringCastCheckEnabled", type = "checkbox", x = 112, y = 30, w = 28, h = 5, label = L["施法检测"] },
        { key = "description_cast_check", type = "description", x = 112, y = 34, w = 82, h = 5,
            label = L["检测当前读条能否完成，来不及时以红色提示。"] },
        { key = "castProgressBarRenameEnabled", type = "checkbox", x = 112, y = 37, w = 28, h = 5, label = L["读条改名"] },
        { key = "castProgressBarRenameText", type = "input", x = 143, y = 37, w = 54, h = 5, label = "" },

        { key = "tr0Enabled", type = "checkbox", x = 4, y = 58, w = 26, h = 5, label = L["中央文本"] },
        { key = "tr0Source", type = "dropdown", x = 34, y = 58, w = 27, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr0Label", type = "dropdown", previewPath = Page.ResolvePackPreviewPath, x = 61, y = 58, w = 33, h = 5, label = "", items = {}, search = true },
        { key = "tr0LSM", type = "lsm_sound", x = 61, y = 58, w = 33, h = 5, label = "", search = true },
        { key = "tr0Path", type = "input", x = 61, y = 58, w = 33, h = 5, label = "" },
        { key = "tr0TtsText", type = "input", x = 61, y = 58, w = 33, h = 5, label = "" },
        { key = "tr0ValueTest", type = "button", x = 95, y = 58, w = 11, h = 6, label = "", tooltip = L["试听"] },
        { key = "tr1Enabled", type = "checkbox", x = 4, y = 65, w = 26, h = 5, label = L["施法开始"] },
        { key = "tr1Source", type = "dropdown", x = 34, y = 65, w = 27, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr1Label", type = "dropdown", previewPath = Page.ResolvePackPreviewPath, x = 61, y = 65, w = 33, h = 5, label = "", items = {}, search = true },
        { key = "tr1LSM", type = "lsm_sound", x = 61, y = 65, w = 33, h = 5, label = "", search = true },
        { key = "tr1Path", type = "input", x = 61, y = 65, w = 33, h = 5, label = "" },
        { key = "tr1TtsText", type = "input", x = 61, y = 65, w = 33, h = 5, label = "" },
        { key = "tr1ValueTest", type = "button", x = 95, y = 65, w = 11, h = 6, label = "", tooltip = L["试听"] },
        { key = "description_countdown_group", type = "description", x = 4, y = 71, w = 102, h = 5,
            label = L["倒数播报"] },
        { key = "description_countdown_note", type = "description", x = 70, y = 71, w = 36, h = 5,
            label = L["数字倒数与名称播报都在这里设置"] },
        { key = "tr2Enabled", type = "checkbox", x = 4, y = 72, w = 26, h = 5, label = L["播放数字"] },
        { key = "tr2CountdownLead", type = "segmented", x = 34, y = 72, w = 27, h = 5, label = "", items = C.COUNTDOWN_LEAD_ITEMS },
        { key = "tr2PlayTextEnabled", type = "checkbox", x = 4, y = 79, w = 26, h = 5, label = L["播放名称"] },
        { key = "tr2Source", type = "dropdown", x = 34, y = 79, w = 27, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "tr2Label", type = "dropdown", previewPath = Page.ResolvePackPreviewPath, x = 61, y = 79, w = 33, h = 5, label = "", items = {}, search = true },
        { key = "tr2LSM", type = "lsm_sound", x = 61, y = 79, w = 33, h = 5, label = "", search = true },
        { key = "tr2Path", type = "input", x = 61, y = 79, w = 33, h = 5, label = "" },
        { key = "tr2TtsText", type = "input", x = 61, y = 79, w = 33, h = 5, label = "" },
        { key = "tr2ValueTest", type = "button", x = 95, y = 79, w = 11, h = 6, label = "", tooltip = L["试听"] },
        { key = "description_voice_preview_heading", type = "description", x = 4, y = 86, w = 68, h = 5,
            label = L["你将听到"] },
        { key = "voiceSequencePreview", type = "button", x = 76, y = 86, w = 30, h = 6,
            label = L["播放预览"] },
        { key = "description_voice_preview_sequence", type = "description", x = 4, y = 93, w = 102, h = 8,
            label = L["静默"] },

        { key = "targetAlertStartEnabled", type = "checkbox", x = 112, y = 58, w = 28, h = 5, label = L["启用"] },
        { key = "targetAlertRingEnabled", type = "checkbox", x = 112, y = 66, w = 25, h = 5, label = L["圆环"] },
        { key = "targetAlertTextEnabledV2", type = "checkbox", x = 142, y = 66, w = 25, h = 5, label = L["文本"] },
        { key = "targetAlertIconEnabled", type = "checkbox", x = 112, y = 73, w = 25, h = 5, label = L["图标"] },
        { key = "targetAlertStealthEnabledV2", type = "checkbox", x = 142, y = 73, w = 43, h = 5, label = "|T132089:18:18|t " .. L["隐遁提示"] },
        { key = "targetAlertVoiceEnabled", type = "checkbox", x = 112, y = 80, w = 20, h = 5, label = L["语音"] },
        { key = "targetAlertStartSource", type = "dropdown", x = 134, y = 80, w = 24, h = 5, label = "", items = C.TRIGGER_SOURCE_ITEMS, search = true },
        { key = "targetAlertStartLabel", type = "dropdown", x = 158, y = 80, w = 30, h = 5, label = "", items = {}, search = true },
        { key = "targetAlertStartLSM", type = "lsm_sound", x = 158, y = 80, w = 30, h = 5, label = "", search = true },
        { key = "targetAlertStartPath", type = "input", x = 158, y = 80, w = 30, h = 5, label = "" },
        { key = "targetAlertStartTtsText", type = "input", x = 158, y = 80, w = 30, h = 5, label = "" },
        { key = "targetAlertStartValueTest", type = "button", x = 190, y = 80, w = 9, h = 6, label = "", tooltip = L["试听"] },
    }

    local groups = { master = {}, text = {}, display = {}, voice = {}, target = {} }
    for _, row in ipairs(rows) do
        local group
        if row.key == "enabled" then group = "master"
        elseif (tonumber(row.x) or 0) >= 109 then group = (tonumber(row.y) or 0) < 50 and "display" or "target"
        else group = (tonumber(row.y) or 0) < 50 and "text" or "voice" end
        local xOffset = (group == "display" or group == "target") and 111 or (group == "text" or group == "voice") and 3 or 2
        local yOffset = group == "text" and 15 or group == "display" and 15 or group == "voice" and 57 or group == "target" and 57 or 0
        row.x = math.max(1, (tonumber(row.x) or 1) - xOffset)
        row.y = math.max(1, (tonumber(row.y) or 1) - yOffset)
        groups[group][#groups[group] + 1] = row
    end
    local cardGap = 6
    local topRowBodyHeight = 176
    local wideColumnRatio = 1.57 / 2.57
    -- 右列稍窄，给卡片右边线留出可见间距，避免贴住 Grid 裁剪边界。
    local narrowColumnRatio = (1 / 2.57) * 0.975
    local wideColumn = { ratio = wideColumnRatio, offset = -cardGap * wideColumnRatio }
    local narrowColumn = { ratio = narrowColumnRatio, offset = -cardGap * narrowColumnRatio }
    local settingsWidth = math.max(1, (UI.spellSettingsGridChild and UI.spellSettingsGridChild:GetWidth()) or 760)
    local wideCardWidth = math.max(1, (settingsWidth - cardGap) * wideColumnRatio)
    local narrowCardWidth = math.max(1, (settingsWidth - cardGap) * narrowColumnRatio)
    local textLabelWidth = math.max(150, math.floor((wideCardWidth - 36) * 0.60))
    local voiceLabelWidth = math.max(150, math.floor((wideCardWidth - 36) * 0.46))
    local displayLabelWidth = math.max(112, math.floor((narrowCardWidth - 36) * 0.42))
    local displayChoiceWidth = math.max(88, math.floor((narrowCardWidth - 50) / 2))
    -- The spell title already belongs to the compact description card above.
    SETTINGS_LAYOUT = { version = 1,
        settingsListWidthPercent = 100, settingsLayoutBreakpoint = 1, cards = {
        { id = "master", title = L["通用设置"], collapsible = false,
            placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT" },
            content = { kind = "grid", items = groups.master },
            settingsList = { summaryEnabled = true } },
        { id = "text", title = L["文本设置"], collapsible = false,
            equalHeightGroup = "boss-settings-top",
            minBodyHeight = topRowBodyHeight,
            placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT", width = wideColumn,
                narrow = { target = "$container", width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.text },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                { controls = { { key = "eventColorEnabled", width = textLabelWidth }, { key = "eventColorMode" }, { key = "eventColor" } } },
                { controls = { { key = "centralEnabled", width = textLabelWidth }, { key = "centralLead", width = 56 }, { key = "centralText" } } },
                { controls = { { key = "countdownEnabled", width = textLabelWidth }, { key = "preAlertText" } } },
                { controls = { { key = "timerBarRenameEnabled", width = textLabelWidth }, { key = "timerBarRenameText" } } },
            } } },
        { id = "display", title = L["施法设置"], collapsible = false,
            equalHeightGroup = "boss-settings-top",
            minBodyHeight = topRowBodyHeight,
            placement = { target = "text", side = "right", align = "start", gap = cardGap, width = narrowColumn,
                narrow = { target = "text", side = "below", align = "start", gap = cardGap, width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.display },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                { controls = { { key = "ringEnabled", width = displayChoiceWidth, presentation = "card" },
                    { key = "castProgressBarEnabled", width = displayChoiceWidth, presentation = "card" } } },
                { key = "ringCastCheckEnabled", presentation = "card", descriptionKey = "description_cast_check" },
                { controls = { { key = "castProgressBarRenameEnabled", width = displayLabelWidth }, { key = "castProgressBarRenameText" } } },
            } } },
        { id = "voice", title = L["语音设置"], collapsible = false,
            equalHeightGroup = "boss-settings-bottom",
            placement = { target = "text", side = "below", align = "start", gap = cardGap + 10, width = wideColumn,
                rowAfter = { "text", "display" },
                narrow = { target = "display", side = "below", align = "start", gap = cardGap, width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.voice },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                { controls = { { key = "tr0Enabled", width = voiceLabelWidth }, { key = "tr0Source" }, { key = "tr0Label" }, { key = "tr0LSM" }, { key = "tr0Path" }, { key = "tr0TtsText" }, { key = "tr0ValueTest", width = 35 } } },
                { controls = { { key = "tr1Enabled", width = voiceLabelWidth }, { key = "tr1Source" }, { key = "tr1Label" }, { key = "tr1LSM" }, { key = "tr1Path" }, { key = "tr1TtsText" }, { key = "tr1ValueTest", width = 35 } } },
                { controls = { { key = "description_countdown_group", role = "label" },
                    { key = "description_countdown_note", align = "right" } } },
                { controls = { { key = "tr2Enabled", width = voiceLabelWidth }, { key = "tr2CountdownLead" } } },
                { controls = { { key = "tr2PlayTextEnabled", width = voiceLabelWidth }, { key = "tr2Source" }, { key = "tr2Label" }, { key = "tr2LSM" }, { key = "tr2Path" }, { key = "tr2TtsText" }, { key = "tr2ValueTest", width = 35 } } },
                { controls = { { key = "description_voice_preview_heading", role = "label" },
                    { key = "voiceSequencePreview", width = 130, presentation = "primary", align = "right" } } },
                { key = "description_voice_preview_sequence", informational = true },
            } } },
        { id = "target", title = L["被点名提示"], collapsible = false,
            equalHeightGroup = "boss-settings-bottom",
            placement = { target = "voice", side = "right", align = "start", gap = cardGap, width = narrowColumn,
                narrow = { target = "voice", side = "below", align = "start", gap = cardGap, width = { ratio = 1 } } },
            content = { kind = "grid", items = groups.target },
            settingsList = { cardPresentation = "exbossSkill", preserveHeader = true, rows = {
                { controls = { { key = "targetAlertStartEnabled", presentation = "switch" } } },
                { controls = { { key = "targetAlertRingEnabled", presentation = "card" },
                    { key = "targetAlertTextEnabledV2", presentation = "card" },
                    { key = "targetAlertIconEnabled", presentation = "card" } } },
                { controls = { { key = "targetAlertStealthEnabledV2", presentation = "card" } } },
                { controls = { { key = "targetAlertVoiceEnabled" } } },
                { controls = { { key = "targetAlertStartSource" }, { key = "targetAlertStartLabel" }, { key = "targetAlertStartLSM" }, { key = "targetAlertStartPath" }, { key = "targetAlertStartTtsText" }, { key = "targetAlertStartValueTest", width = 35 } } },
            } } },
    } }
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
    local bodyText = descText
    local summaryCast, summaryRange = GetSpellSummaryFacts(sid)
    UI.spellDetailHeader:Show()
    if UI.spellSummaryEnableHost then UI.spellSummaryEnableHost:Show() end
    UI.spellDetailPlaceholder:Hide()
    UI.spellDetailIcon:SetTexture(spellIcon or 134400)
    UI.spellDetailIcon:Show()
    if UI.spellDetailIconBorder then UI.spellDetailIconBorder:Show() end
    UI.spellDetailTitle:SetText(safeName)
    -- 详情标题只保留法术名称；分类/警告图标仍保留在上方技能列表中。
    UI.spellDetailMeta:SetText("")
    UI.spellDetailMeta:Hide()
    local castValue = summaryCast ~= "" and summaryCast or "—"
    local rangeValue = summaryRange ~= "" and summaryRange or "—"
    UI.spellDetailCast:SetText((castValue:gsub("(%d)%s+", "%1")))
    UI.spellDetailCastChip:Show()
    UI.spellDetailRangeChip:Show()
    if UI.spellDetailRange then
        UI.spellDetailRange:SetText(rangeValue)
    end
    if UI.spellDetailSpellIDValue then UI.spellDetailSpellIDValue:SetText(tostring(sid or "-")) end
    if UI.spellDetailEventIDValue then UI.spellDetailEventIDValue:SetText(tostring(eid or "-")) end
    if UI.spellDetailSpellIDChip then UI.spellDetailSpellIDChip:Show() end
    if UI.spellDetailEventIDChip then UI.spellDetailEventIDChip:Show() end
    UI.spellDetailBody:SetText((bodyText and bodyText ~= "") and bodyText or L["暂无描述。"])
    UI.spellDetailBodyScroll:SetVerticalScroll(0)
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
    if UI.spellDetailIconBorder then UI.spellDetailIconBorder:Hide() end
    UI.spellDetailTitle:SetText("")
    UI.spellDetailMeta:SetText("")
    UI.spellDetailCast:SetText("")
    UI.spellDetailCastChip:Hide()
    UI.spellDetailRangeChip:Hide()
    if UI.spellDetailRange then UI.spellDetailRange:SetText("") end
    if UI.spellDetailSpellIDChip then UI.spellDetailSpellIDChip:Hide() end
    if UI.spellDetailEventIDChip then UI.spellDetailEventIDChip:Hide() end
    UI.spellDetailBody:SetText("")
    UI.spellDetailBodyScroll:SetVerticalScroll(0)
    if UI.spellSummaryEnableHost then UI.spellSummaryEnableHost:Hide() end
    UI.spellDetailHeader:SetHeight(C.SPELL_DETAIL_HEIGHT)
end

-- 副本通用设置没有“法术卡片 + 描述卡”这一层级：右侧只保留一块 Grid 容器。
-- [共享宿主边界] 只可迁移下列宿主锚点；三模式切换、同一 grid child、title/scroll 显隐和 DungeonCommon 释放顺序禁止修改。
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
    SyncBossRightViewport()

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
        UI.spellSettingsGridScroll:SetPoint("TOPLEFT", UI.spellSettingsFrame, "TOPLEFT", 0, 0)
        UI.spellSettingsGridScroll:SetPoint("BOTTOMRIGHT", UI.spellSettingsFrame, "BOTTOMRIGHT", 0, 0)
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
    EXUI:SetControlSurface(b.iconFrame, 10, GC.input, GC.panelBorder)
    b.iconFrame:SetSize(70, 70)
    b.iconFrame:SetPoint("TOP", 0, -1)

    b.icon = EXUI:CreateRoundedImage(b.iconFrame, 9, true)
    local function LayoutMapImage()
        local inset = PixelUtil.GetNearestPixelSize(1, b.iconFrame:GetEffectiveScale(), 1)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", inset, -inset)
        b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        b.icon:SetCornerRadius(10 - inset)
    end
    b.iconFrame:HookScript("OnSizeChanged", LayoutMapImage)
    b.iconFrame:RegisterEvent("UI_SCALE_CHANGED")
    b.iconFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    b.iconFrame:SetScript("OnEvent", LayoutMapImage)
    LayoutMapImage()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.text = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontNormalSmall")
    b.text:SetPoint("TOP", b.iconFrame, "BOTTOM", 0, -5)
    b.text:SetWidth(84)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(true)
    b.text:SetMaxLines(0)
    b.text:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "")

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

-- PlayerModel has no Texture mask API. Cover only its corner pixels with
-- the exact opaque navigation surface color; the original model stays intact.
local function PaintBossNavigationSurface(card, red, green, blue, alpha, borderColor)
    local baseR, baseG, baseB = GC.panel[1], GC.panel[2], GC.panel[3]
    local parent = UI.leftRoot and UI.leftRoot:GetParent()
    if parent and parent.GetBackdropColor then
        local r, g, b = parent:GetBackdropColor()
        if r and g and b then baseR, baseG, baseB = r, g, b end
    end
    local fill = {
        red * alpha + baseR * (1 - alpha),
        green * alpha + baseG * (1 - alpha),
        blue * alpha + baseB * (1 - alpha),
        1,
    }
    EXUI:SetControlSurface(card, 10, fill, borderColor or fill)
    for _, texture in ipairs(card.portraitCornerTextures or {}) do
        texture:SetColorTexture(fill[1], fill[2], fill[3], 1)
    end
end

local function CreateBossPortraitCornerCover(card)
    local cover = CreateFrame("Frame", nil, card)
    cover:SetAllPoints(card.creature)
    cover:SetFrameLevel(card.creature:GetFrameLevel() + 1)
    cover:EnableMouse(false)
    card.portraitCornerCover = cover
    card.portraitCornerTextures = {}
    -- PlayerModel 没有纹理 mask API，只能遮角。提高半径与分段数，避免旧版
    -- 8 段遮角产生肉眼可见的折线；这不会改动模型或 Boss 选择逻辑。
    local radius, bands = 10, 24
    local bandHeight = radius / bands
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local fromTop = corner == "TOPLEFT" or corner == "TOPRIGHT"
        for index = 1, bands do
            -- Use the outer edge so each band fully covers the corner outside the curve.
            local y = (index - 1) * bandHeight
            local width = radius - math.sqrt(radius * radius - (radius - y) * (radius - y))
            local texture = EXUI:CreateVisualTexture(cover, EXBORDERFRAME)
            texture:SetPoint(corner, cover, corner, 0, (fromTop and -1 or 1) * (index - 1) * bandHeight)
            texture:SetSize(math.max(0.001, width), bandHeight)
            if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
            if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
            texture:SetColorTexture(unpack(GC.panel))
            card.portraitCornerTextures[#card.portraitCornerTextures + 1] = texture
        end
    end
end

local function AcquireBossCard()
    local b = table.remove(CARD_CACHE.bossCardPool)
    if b then return b end

    b = CreateFrame("Button", nil, UI.bossScrollContent, "BackdropTemplate")
    b:SetSize(184, 64)
    EXUI:SetControlSurface(b, 10, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    b.navDivider = EXUI:CreateSettingsSeparator(b, 1)
    b.navDivider:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 9, -1)
    b.navDivider:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -9, -1)

    b.activeBar = EXUI:CreateVisualTexture(b, EXBORDERFRAME)
    b.activeBar:SetPoint("TOPLEFT", 0, 0)
    b.activeBar:SetPoint("BOTTOMLEFT", 0, 0)
    b.activeBar:SetWidth(3)
    b.activeBar:SetColorTexture(unpack(GC.accent))
    b.activeBar:Hide()

    b.creature = CreateFrame("PlayerModel", nil, b)
    b.creature:SetSize(54, 58)
    b.creature:SetPoint("LEFT", 9, 0)
    b.creature:SetFrameLevel(b:GetFrameLevel() + 3)
    b.creature:EnableMouse(false)
    CreateBossPortraitCornerCover(b)

    b.noPortraitText = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontDisableSmall")
    b.noPortraitText:SetPoint("CENTER", b.creature, "CENTER", 0, 0)
    b.noPortraitText:SetText(L["无动态头像"])
    b.noPortraitText:Hide()

    -- 用户 2026-10-05 第五批第 64 项：「光环语音」行原来只在首领缩略图那块空位
    -- 里放一个裸耳机图标，没有缩略图那样的承载面，和同一列表里的首领行不搭。
    -- 这里补一块与缩略图同槽位、同圆角角色（GUIMetrics.radius.card，与
    -- PaintBossNavigationSurface 的遮角半径一致）的 subcard 底板，图标画在它上面。
    b.auraIconTile = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.auraIconTile:SetAllPoints(b.creature)
    -- 必须高于 CreateBossPortraitCornerCover 的遮角层（creature + 1 = 卡片 + 4），
    -- 否则遮角纹理会把底板的圆角描边盖掉。
    b.auraIconTile:SetFrameLevel(b:GetFrameLevel() + 5)
    b.auraIconTile:EnableMouse(false)
    EXUI:SetControlSurface(b.auraIconTile, ExwindTools.GUIMetrics.radius.card,
        GC.subcard, GC.subcardBorder)
    b.auraIconTile:Hide()

    -- FontString/Texture 必须和底板共用同一个 Frame owner：绘制层不会从父卡片
    -- 跨到子 Frame 的表面纹理之上（与下面 detailBadge 同一条约束）。
    b.auraIcon = EXUI:CreateVisualTexture(b.auraIconTile, EXBORDERFRAME)
    b.auraIcon:SetTexture(EXUI:GetIcon("headphones"))
    b.auraIcon:SetSize(30, 30)
    b.auraIcon:SetPoint("CENTER", b.auraIconTile, "CENTER", 0, 0)
    b.auraIcon:SetVertexColor(unpack(GC.text))
    b.auraIcon:Hide()

    b.nameText = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontNormal")
    b.nameText:SetPoint("TOPLEFT", b.creature, "TOPRIGHT", 12, -8)
    b.nameText:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.nameText:SetJustifyH("LEFT")
    b.nameText:SetJustifyV("TOP")
    b.nameText:SetWordWrap(true)
    b.nameText:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.exboss.navigationTitle, "OUTLINE")

    b.detailBadge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.detailBadge:SetPoint("BOTTOMLEFT", b.creature, "BOTTOMRIGHT", 12, 7)
    b.detailBadge:SetSize(46, 21)
    b.detailBadge:EnableMouse(false)
    EXUI:SetControlSurface(b.detailBadge, 4, GC.panel, GC.cardBorder)

    -- FontString must share the badge's Frame owner: draw layers cannot cross
    -- from the parent card over a child Frame's surface textures.
    b.detailText = EXUI:CreateVisualFontString(b.detailBadge, EXFONTFRAME, "GameFontDisableSmall")
    b.detailText:SetPoint("CENTER", b.detailBadge, "CENTER", 0, 0)
    b.detailText:SetJustifyH("CENTER")
    b.detailText:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "")
    b.detailText:SetWordWrap(false)

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
    EXUI:SetControlSurface(card, 4, GC.card, GC.panelBorder)

    card.leftBar = EXUI:CreateVisualTexture(card, EXBACKGROUNDFRAME)
    card.leftBar:SetWidth(5)
    card.leftBar:SetPoint("TOPLEFT", 2, -7)
    card.leftBar:SetPoint("BOTTOMLEFT", 2, 7)
    card.leftBar:Hide()

    -- 选中内环：技能卡的外框一圈已经被业务分类色占用（GUI-03 不统一），
    -- 所以选中的主色描边压在外框内侧 1 像素处，底色与外框分类色都不动。
    card.selectionRing = CreateFrame("Frame", nil, card)
    card.selectionRing:EnableMouse(false)
    card.selectionRing:SetFrameLevel(card:GetFrameLevel() + 1)
    local function LayoutSpellSelectionRing()
        local inset = PixelUtil.GetNearestPixelSize(1, card:GetEffectiveScale(), 1)
        card.selectionRing:ClearAllPoints()
        card.selectionRing:SetPoint("TOPLEFT", card, "TOPLEFT", inset, -inset)
        card.selectionRing:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -inset, inset)
    end
    card._layoutSelectionRing = LayoutSpellSelectionRing
    card:HookScript("OnSizeChanged", LayoutSpellSelectionRing)
    card.selectionRing:RegisterEvent("UI_SCALE_CHANGED")
    card.selectionRing:RegisterEvent("DISPLAY_SIZE_CHANGED")
    card.selectionRing:SetScript("OnEvent", LayoutSpellSelectionRing)
    LayoutSpellSelectionRing()
    card.selectionRing:Hide()

    card.icon = EXUI:CreateRoundedImage(card, 4)
    card.icon:SetSize(30, 30)
    card.icon:SetPoint("LEFT", 41, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.alertIcon = EXUI:CreateVisualTexture(card, EXBORDERFRAME)
    card.alertIcon:SetSize(26, 26)
    card.alertIcon:SetPoint("LEFT", 4, 0)
    card.alertIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.alertIcon:Hide()

    card.targetAlertMarkerHolder = CreateFrame("Frame", nil, card)
    card.targetAlertMarkerHolder:SetSize(16, 16)
    card.targetAlertMarkerHolder:SetPoint("RIGHT", card, "RIGHT", -8, 0)
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
    card.title:SetPoint("LEFT", card.icon, "RIGHT", 7, 0)
    card.title:SetPoint("RIGHT", card.targetAlertMarkerHolder, "LEFT", -6, 0)
    card.title:SetJustifyH("LEFT")
    card.title:SetJustifyV("MIDDLE")
    card.title:SetWordWrap(false)
    card.title:SetMaxLines(1)
    card.title:SetSpacing(0)
    card.title:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.title, "")

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
    if not (card and card.title) then return end
    card.title:SetSpacing(0)
    card.title:SetText(tostring(text or ""))
    card.title:SetWordWrap(false)
    card.title:SetMaxLines(1)
    card.title:SetFont(ExwindTools.MAIN_FONT, C.SPELL_CARD.titleFontSizes[2], "")
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

-- [混合函数边界] EnsureUI 内只可迁移 frame/card/list 的创建外观、SetPoint/SetSize；所有 OnClick、选择身份、异步 token、池 acquire/release 禁止修改。
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
                selectedExtraKey = nil
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
        UI.seasonDropdown:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", 14, -18)
        UI.seasonDropdown:SetPoint("TOPRIGHT", UI.leftRoot, "TOPRIGHT", -14, -18)
        UI.seasonDropdown:SetHeight(28)
    end

    local mapTitle = EXUI:CreateVisualFontString(UI.leftRoot, EXFONTFRAME, "GameFontNormal")
    UI.mapNavTitle = mapTitle
    if UI.seasonDropdown then
        mapTitle:SetPoint("TOPLEFT", UI.seasonDropdown, "BOTTOMLEFT", 0, -20)
    else
        mapTitle:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", 10, -10)
    end
    mapTitle:SetText("")
    mapTitle:SetTextColor(unpack(GC.textDim))
    mapTitle:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "")
    mapTitle:Hide()

    -- 副本选择固定两排八项，不建立滚动视口或滚动条。
    UI.mapScrollFrame = CreateFrame("Frame", nil, UI.leftRoot)
    UI.mapScrollFrame:SetClipsChildren(true)
    if UI.seasonDropdown then
        UI.mapScrollFrame:SetPoint("TOPLEFT", UI.seasonDropdown, "BOTTOMLEFT", 0, -12)
        UI.mapScrollFrame:SetPoint("TOPRIGHT", UI.leftRoot, "TOPRIGHT", -14, -12)
    else
        UI.mapScrollFrame:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", 14, -18)
        UI.mapScrollFrame:SetPoint("TOPRIGHT", UI.leftRoot, "TOPRIGHT", -14, -18)
    end
    UI.mapScrollFrame:SetHeight(172)

    UI.mapScrollChild = CreateFrame("Frame", nil, UI.mapScrollFrame)
    UI.mapScrollChild:SetPoint("TOPLEFT", UI.mapScrollFrame, "TOPLEFT")
    UI.mapScrollChild:SetSize(208, 1)

    UI.mapEmptyText = EXUI:CreateVisualFontString(UI.mapScrollChild, EXFONTFRAME, "GameFontDisableSmall")
    UI.mapEmptyText:SetPoint("CENTER", 0, 0)
    UI.mapEmptyText:SetTextColor(unpack(GC.textPlaceholder))
    UI.mapEmptyText:SetText(L["该分类无副本数据"])

    local sep = EXUI:CreateSettingsSeparator(UI.leftRoot, 1)
    sep:SetPoint("TOPLEFT", UI.mapScrollFrame, "BOTTOMLEFT", 6, -3)
    sep:SetPoint("TOPRIGHT", UI.mapScrollFrame, "BOTTOMRIGHT", -6, -3)
    sep:Hide()

    local bossTitle = EXUI:CreateVisualFontString(UI.leftRoot, EXFONTFRAME, "GameFontNormal")
    UI.bossNavTitle = bossTitle
    bossTitle:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 4, -6)
    bossTitle:SetText("")
    bossTitle:SetTextColor(unpack(GC.textDim))
    bossTitle:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "")
    bossTitle:Hide()

    UI.bossScrollFrame = CreateFrame("ScrollFrame", nil, UI.leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.bossScrollFrame)
    end
    UI.bossScrollFrame:SetPoint("TOPLEFT", UI.mapScrollFrame, "BOTTOMLEFT", -6, -10)
    UI.bossScrollFrame:SetPoint("BOTTOMRIGHT", UI.leftRoot, "BOTTOMRIGHT", -18, 18)

    UI.bossScrollContent = CreateFrame("Frame", nil, UI.bossScrollFrame)
    UI.bossScrollContent:SetSize(200, 1)
    UI.bossScrollFrame:SetScrollChild(UI.bossScrollContent)

    UI.bossEmptyText = EXUI:CreateVisualFontString(UI.bossScrollContent, EXFONTFRAME, "GameFontDisableSmall")
    UI.bossEmptyText:SetPoint("TOPLEFT", 8, -6)
    UI.bossEmptyText:SetPoint("RIGHT", -8, 0)
    UI.bossEmptyText:SetJustifyH("LEFT")
    UI.bossEmptyText:SetTextColor(unpack(GC.textPlaceholder))
    UI.bossEmptyText:SetText(L["当前副本暂无 BOSS 数据"])

    UI.rightViewport = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    UI.rightViewport:SetAllPoints(contentFrame)
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.rightViewport)
    end
    DisableVerticalScroll(UI.rightViewport)
    UI.rightViewport:SetScript("OnSizeChanged", function()
        SyncBossRightViewport()
    end)
    UI.rightRoot = CreateFrame("Frame", nil, UI.rightViewport)
    UI.rightRoot:SetPoint("TOPLEFT", UI.rightViewport, "TOPLEFT", 0, 0)
    UI.rightRoot:SetSize(math.max(1, contentFrame:GetWidth()), math.max(1, contentFrame:GetHeight()))
    UI.rightViewport:SetScrollChild(UI.rightRoot)
    UI.rightRoot:SetScript("OnSizeChanged", function(self)
        if self._prototypeReflowPending then return end
        self._prototypeReflowPending = true
        C_Timer.After(0, function()
            self._prototypeReflowPending = false
            Page:RelayoutPrototype()
        end)
    end)

    EXUI = ExwindTools.UI
    if not UI.titleControlHost then
        -- 创建时先附在右侧根；spellDetailHeader 建好后再移入其右上角。
        UI.titleControlHost = CreateFrame("Frame", nil, UI.rightRoot)
        UI.titleControlHost:SetSize(420, 26)

        UI.modeLabelText = EXUI:CreateVisualFontString(UI.titleControlHost, EXFONTFRAME, "GameFontNormal")
        UI.modeLabelText:SetPoint("RIGHT", UI.titleControlHost, "RIGHT", -196, 0)
        UI.modeLabelText:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.moduleDescription, "")
        UI.modeLabelText:SetTextColor(unpack(GC.text))
        UI.modeLabelText:SetText("")
        UI.modeLabelText:Hide()
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
        UI.modeDropdown:SetHeight(28)
    end

    local function CreateTopTestButton(text)
        local b = EXUI:CreateButton(UI.rightRoot, 70, 28, text or "", nil, { compact = true })
        b.text = b:GetFontString()
        if b.text then b.text:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "") end
        return b
    end

    if UI.titleControlHost and not UI.modeTestStopBtn then
        UI.modeTestStopBtn = CreateTopTestButton(L["测关"])
        UI.modeTestStopBtn:SetParent(UI.titleControlHost)
        UI.modeTestStopBtn:SetPoint("RIGHT", UI.modeLabelText, "LEFT", -12, 0)
    end

    if UI.titleControlHost and not UI.modeTestStartBtn then
        UI.modeTestStartBtn = CreateTopTestButton(L["测开"])
        UI.modeTestStartBtn:SetParent(UI.titleControlHost)
        UI.modeTestStartBtn:SetPoint("RIGHT", UI.modeTestStopBtn, "LEFT", -6, 0)
    end

    function Page:RefreshTemporaryBossPreviewButton()
        if not (UI.modeTestStartBtn and UI.modeTestStartBtn.text and
                UI.modeTestStopBtn and UI.modeTestStopBtn.text) then return end
        local preview = ExBoss and ExBoss.TemporaryBossPreview
        local running = preview and type(preview.IsRunning) == "function" and preview:IsRunning()
        UI.modeTestStartBtn._previewActive = false
        UI.modeTestStopBtn._previewActive = running == true
        UI.modeTestStartBtn.text:SetText(L["测开"])
        UI.modeTestStopBtn.text:SetText(L["测关"])
        UI.modeTestStartBtn._exButtonVariant = "secondary"
        UI.modeTestStopBtn._exButtonVariant = running and "danger" or "secondary"
        EXUI:ApplyControlAppearance(UI.modeTestStartBtn)
        EXUI:ApplyControlAppearance(UI.modeTestStopBtn)
    end

    UI.modeTestStartBtn:SetScript("OnClick", function()
        local preview = ExBoss and ExBoss.TemporaryBossPreview
        if not (preview and type(preview.Start) == "function") then return end
        if type(preview.IsRunning) == "function" and preview:IsRunning() then return end
        CommitSpellTextFormState()
        local ok, reason = preview:Start(GetCurrentBoss())
        Page:RefreshTemporaryBossPreviewButton()
        if ok == false and reason then
            print("|cffff6600[EXBoss]|r " .. tostring(reason))
        end
    end)

    UI.modeTestStopBtn:SetScript("OnClick", function()
        local preview = ExBoss and ExBoss.TemporaryBossPreview
        if preview and type(preview.Stop) == "function" then
            preview:Stop("button")
        end
        Page:RefreshTemporaryBossPreviewButton()
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
    UI.spellSettingsFrame:SetBackdropColor(0, 0, 0, 0)
    UI.spellSettingsFrame:SetBackdropBorderColor(0, 0, 0, 0)

    UI.spellDetailHeader = CreateFrame("Frame", nil, UI.rightRoot, "BackdropTemplate")
    UI.spellDetailHeader:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 16, -(GetSpellListViewportHeight() + 8))
    UI.spellDetailHeader:SetPoint("TOPRIGHT", UI.rightRoot, "TOPRIGHT", -16, -(GetSpellListViewportHeight() + 8))
    UI.spellDetailHeader:SetHeight(C.SPELL_DETAIL_HEIGHT)
    UI.spellDetailHeader:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    UI.spellDetailHeader:SetBackdropColor(0, 0, 0, 0)
    UI.spellDetailHeader:SetBackdropBorderColor(0, 0, 0, 0)
    EXUI:SetControlSurface(UI.spellDetailHeader, 10, GC.card, GC.panelBorder)
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

    UI.spellSummaryEnableHost = CreateFrame("Frame", nil, UI.spellDetailHeader)
    UI.spellSummaryEnableHost:SetSize(76, 26)
    UI.spellSummaryEnableHost:SetPoint("BOTTOMLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 8, 7)
    UI.spellSummaryEnableHost:Hide()

    -- 触发模式与测试按钮属于摘要第二行，和射程/施法信息并列。
    if UI.titleControlHost then
        UI.titleControlHost:SetParent(UI.spellDetailHeader)
        UI.titleControlHost:ClearAllPoints()
        UI.titleControlHost:SetPoint("TOPRIGHT", UI.spellDetailHeader, "TOPRIGHT", -12, -39)
        UI.titleControlHost:SetFrameLevel((UI.spellDetailHeader:GetFrameLevel() or 1) + 5)
        UI.titleControlHost:Show()
    end

    UI.spellDetailAccent = EXUI:CreateVisualTexture(UI.spellDetailHeader, EXBORDERFRAME)
    UI.spellDetailAccent:SetPoint("TOPLEFT", UI.spellDetailHeader, "TOPLEFT", 1, -1)
    UI.spellDetailAccent:SetHeight(2)
    UI.spellDetailAccent:SetWidth(180)
    UI.spellDetailAccent:SetColorTexture(0, 0, 0, 0)

    UI.spellDetailPlaceholder = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontDisableSmall")
    UI.spellDetailPlaceholder:SetPoint("CENTER", 0, 0)
    UI.spellDetailPlaceholder:SetTextColor(unpack(GC.textPlaceholder))
    UI.spellDetailPlaceholder:SetText(L["点击上方法术卡片后，可在此查看法术描述。"])

    UI.spellDetailIcon = EXUI:CreateRoundedImage(UI.spellDetailHeader, 9)
    UI.spellDetailIcon:SetSize(46, 46)
    UI.spellDetailIcon:SetPoint("TOPLEFT", 14, -14)
    UI.spellDetailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.spellDetailIconBorder = CreateFrame("Frame", nil, UI.spellDetailHeader, "BackdropTemplate")
    UI.spellDetailIconBorder:SetSize(48, 48)
    UI.spellDetailIconBorder:SetPoint("TOPLEFT", UI.spellDetailIcon, "TOPLEFT", -1, 1)
    UI.spellDetailIconBorder:SetFrameLevel(UI.spellDetailHeader:GetFrameLevel())
    EXUI:ClearControlSurface(UI.spellDetailIconBorder)

    UI.spellDetailTitle = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontNormal")
    UI.spellDetailTitle:SetPoint("TOPLEFT", UI.spellDetailIcon, "TOPRIGHT", 8, -1)
    UI.spellDetailTitle:SetJustifyH("LEFT")
    UI.spellDetailTitle:SetWordWrap(false)
    UI.spellDetailTitle:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.exboss.spellDetailTitle, "")
    UI.spellDetailTitle:SetTextColor(1, 1, 1)

    UI.spellDetailMeta = EXUI:CreateVisualFontString(UI.spellDetailHeader, EXFONTFRAME, "GameFontHighlight")
    UI.spellDetailMeta:SetPoint("LEFT", UI.spellDetailTitle, "RIGHT", 10, 0)
    UI.spellDetailMeta:SetJustifyH("LEFT")
    UI.spellDetailMeta:SetWordWrap(false)
    UI.spellDetailMeta:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.hint, "")
    UI.spellDetailMeta:SetTextColor(unpack(GC.textDim))
    UI.spellDetailMeta:Hide()

    local function CreateDetailIDChip(label, color)
        local chip = CreateFrame("Frame", nil, UI.spellDetailHeader, "BackdropTemplate")
        EXUI:SetControlSurface(chip, 5, GC.input, GC.panelBorder)
        if label then
            chip.label = EXUI:CreateVisualFontString(chip, EXFONTFRAME, "GameFontDisableSmall")
            chip.label:SetPoint("LEFT", chip, "LEFT", 9, 0)
            chip.label:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.exboss.chipLabel, "")
            chip.label:SetTextColor(unpack(GC.textDim))
            chip.label:SetText(label)
        end
        chip.value = EXUI:CreateVisualFontString(chip, EXFONTFRAME, "GameFontHighlightSmall")
        if chip.label then
            chip.value:SetPoint("LEFT", chip.label, "RIGHT", 6, 0)
        else
            chip.value:SetPoint("CENTER", chip, "CENTER", 0, 0)
        end
        chip.value:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.moduleDescription, "")
        chip.value:SetTextColor(unpack(color or GC.text))
        chip.value:SetWordWrap(false)
        return chip, chip.value
    end
    UI.spellDetailCastChip, UI.spellDetailCast = CreateDetailIDChip(nil, { 0.68, 0.84, 0.96, 1 })
    UI.spellDetailRangeChip, UI.spellDetailRange = CreateDetailIDChip(nil, { 0.65, 0.83, 0.78, 1 })
    UI.spellDetailSpellIDChip, UI.spellDetailSpellIDValue = CreateDetailIDChip("Spell ID")
    UI.spellDetailEventIDChip, UI.spellDetailEventIDValue = CreateDetailIDChip("Event ID")

    -- 描述区固定在信息卡内部；右侧只有最上方法术列表允许滚动。
    UI.spellDetailBodyScroll = CreateFrame("ScrollFrame", nil, UI.spellDetailHeader, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.spellDetailBodyScroll)
    end
    UI.spellDetailBodyScroll:SetPoint("TOPLEFT", UI.spellDetailCast, "BOTTOMLEFT", 0, -5)
    UI.spellDetailBodyScroll:SetPoint("BOTTOMRIGHT", UI.spellDetailHeader, "BOTTOMRIGHT", -34, 10)
    DisableVerticalScroll(UI.spellDetailBodyScroll)
    UI.spellDetailBodyChild = CreateFrame("Frame", nil, UI.spellDetailBodyScroll)
    UI.spellDetailBodyChild:SetSize(1, 1)
    UI.spellDetailBodyScroll:SetScrollChild(UI.spellDetailBodyChild)
    UI.spellDetailBody = EXUI:CreateVisualFontString(UI.spellDetailBodyChild, EXFONTFRAME, "GameFontHighlight")
    UI.spellDetailBody:SetPoint("TOPLEFT", 0, 0)
    UI.spellDetailBody:SetJustifyH("LEFT")
    UI.spellDetailBody:SetJustifyV("TOP")
    UI.spellDetailBody:SetWordWrap(true)
    UI.spellDetailBody:SetSpacing(3)
    UI.spellDetailBody:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.title, "")
    UI.spellDetailBody:SetTextColor(unpack(GC.textDim))

    UI.spellDetailDivider = EXUI:CreateSettingsSeparator(UI.spellDetailHeader, 1)
    UI.spellDetailDivider:SetPoint("BOTTOMLEFT", UI.spellDetailHeader, "BOTTOMLEFT", 14, 10)
    UI.spellDetailDivider:SetPoint("BOTTOMRIGHT", UI.spellDetailHeader, "BOTTOMRIGHT", -14, 10)
    UI.spellDetailDivider:Hide()

    UI.spellSettingsGridScroll = CreateFrame("ScrollFrame", nil, UI.spellSettingsFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(UI.spellSettingsGridScroll)
    end
    UI.spellSettingsGridScroll:SetPoint("TOPLEFT", UI.spellSettingsFrame, "TOPLEFT", 0, 0)
    UI.spellSettingsGridScroll:SetPoint("BOTTOMRIGHT", UI.spellSettingsFrame, "BOTTOMRIGHT", 0, 0)
    DisableVerticalScroll(UI.spellSettingsGridScroll)

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
    UI.spellScrollFrame:SetPoint("TOPLEFT", UI.rightRoot, "TOPLEFT", 16, -C.SPELL_LIST_TOP_INSET)
    UI.spellScrollFrame:SetPoint("BOTTOMRIGHT", UI.spellDetailHeader, "TOPRIGHT", -18, 4)
    UI.spellScrollFrame:EnableMouseWheel(true)
    UI.spellScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maximum = math.max(0, self:GetVerticalScrollRange())
        self:SetVerticalScroll(math.max(0, math.min(maximum, self:GetVerticalScroll() - delta * 32)))
    end)

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
                card._selected = selectedBossCommonSettings ~= true
                    and tonumber(card.index) == tonumber(selectedBossIndex)
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
            card._selected = (card._extraKey and card._extraKey == selectedExtraKey)
                or (not selectedExtraKey and selected and tonumber(card._eventID) == selected) or false
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
        UI.summaryText:SetText(string.format("%s[%s]|r  %s", GC.markup.accent, tostring(selectedSeason or "-"), mapName))
        return
    end

    local events = boss.events or {}
    local encounterID = tonumber(boss.encounterID)
    local overrideMode = encounterID and GetEncounterModeOverride(encounterID) or "auto"
    local effectiveMode = encounterID and ResolveEffectiveMode(encounterID) or "blizzard"
    UI.summaryText:SetText(string.format(
        "%s[%s]|r  %s  >  %s  |  %s: %s%d|r  |  %s: %s%s|r (%s: %s)",
        GC.markup.accent,
        tostring(selectedSeason or "-"),
        mapName,
        tostring(boss.name or L["未知首领"]),
        L["技能数"],
        GC.markup.selectedText,
        #events,
        L["轴"],
        GC.markup.textDim,
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
        sharedLeftW = math.max(1, sharedLeftW)
        if UI.mapScrollChild then
            UI.mapScrollChild:SetWidth(math.max(1, UI.mapScrollFrame:GetWidth() - 4))
        end
        if UI.bossScrollContent then
            UI.bossScrollContent:SetWidth(sharedLeftW)
        end
    end
    if UI.spellScrollFrame and UI.spellScrollChild then
        local sw = (UI.spellScrollFrame:GetWidth() or 0) - 4
        sw = math.max(1, sw)
        C.SPELL_CARD.cols = 5
        UI.spellScrollChild:SetWidth(sw)
    end
    if UI.spellSettingsGridScroll and UI.spellSettingsGridChild then
        local gw = UI.spellSettingsGridScroll:GetWidth() or 0
        gw = math.max(1, gw)
        UI.spellSettingsGridChild:SetWidth(gw)
    end
end

local function RelayoutMapNavigation()
    if not (UI.mapScrollChild and UI.mapScrollFrame) then return end
    local compact = UI.leftRoot:GetWidth() <= 220
    local inset, topInset = compact and 11 or 14, compact and 15 or 18
    if UI.seasonDropdown then
        UI.seasonDropdown:ClearAllPoints()
        UI.seasonDropdown:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", inset, -topInset)
        UI.seasonDropdown:SetPoint("TOPRIGHT", UI.leftRoot, "TOPRIGHT", -inset, -topInset)
    end
    UI.mapNavTitle:Hide()
    UI.mapScrollFrame:ClearAllPoints()
    if UI.seasonDropdown then
        UI.mapScrollFrame:SetPoint("TOPLEFT", UI.seasonDropdown, "BOTTOMLEFT", 0, -12)
    else
        UI.mapScrollFrame:SetPoint("TOPLEFT", UI.leftRoot, "TOPLEFT", inset, -topInset)
    end
    UI.mapScrollFrame:SetWidth(math.max(1, UI.leftRoot:GetWidth() - inset * 2))
    UI.mapScrollChild:SetWidth(math.max(1, UI.mapScrollFrame:GetWidth() - 4))
    UI.bossNavTitle:Hide()
    UI.bossScrollFrame:ClearAllPoints()
    UI.bossScrollFrame:SetPoint("TOPLEFT", UI.mapScrollFrame, "BOTTOMLEFT", -6, -10)
    UI.bossScrollFrame:SetPoint("BOTTOMRIGHT", UI.leftRoot, "BOTTOMRIGHT", -18, topInset)
    UI.bossScrollContent:SetWidth(math.max(1, UI.bossScrollFrame:GetWidth() - 4))
    local cellWidth = math.max(1, (UI.mapScrollChild:GetWidth() - 21) / 4)
    local iconSize = math.max(1, math.min(90, cellWidth - 2))
    local heights = {}
    for i, tab in ipairs(CARD_CACHE.activeMapTabs) do
        tab:SetWidth(cellWidth)
        tab.iconFrame:SetSize(iconSize, iconSize)
        tab.text:SetWidth(math.max(1, cellWidth - 4))
        local row = math.floor((i - 1) / 4) + 1
        heights[row] = math.max(heights[row] or 0, iconSize + 6 + math.ceil(tab.text:GetStringHeight() or 0))
    end
    local y, visibleHeight = 0, 0
    for row = 1, math.max(1, math.ceil(#CARD_CACHE.activeMapTabs / 4)) do
        local height = heights[row] or (iconSize + 24)
        for i = (row - 1) * 4 + 1, math.min(row * 4, #CARD_CACHE.activeMapTabs) do
            local tab = CARD_CACHE.activeMapTabs[i]
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", ((i - 1) % 4) * (cellWidth + 7), -y)
            tab:SetHeight(height)
        end
        if row <= 2 then visibleHeight = y + height end
        y = y + height + 12
    end
    UI.mapScrollChild:SetHeight(math.max(1, y - 12 + 4))
    UI.mapScrollFrame:SetHeight(math.max(1, visibleHeight + 4))
end

local function RelayoutBossNavigation()
    if not (UI.leftRoot and UI.bossScrollContent) then return end
    local compact = UI.leftRoot:GetWidth() <= 220
    local inset, gap = compact and 6 or 8, compact and 8 or 10
    local portraitWidth, portraitHeight = compact and 54 or 60, compact and 54 or 60
    local cardHeight = compact and 66 or 70
    local y = 4
    for _, card in ipairs(CARD_CACHE.activeBossCards) do
        if card._dungeonCommon then y = y + 19 end
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", UI.bossScrollContent, "TOPLEFT", 0, -y)
        card:SetPoint("TOPRIGHT", UI.bossScrollContent, "TOPRIGHT", -1, -y)
        card.creature:SetSize(portraitWidth, portraitHeight)
        card.creature:ClearAllPoints()
        card.creature:SetPoint("LEFT", inset, 0)
        card.nameText:SetFont(ExwindTools.MAIN_FONT, compact and 15 or 16, "")
        card.nameText:ClearAllPoints()
        local nameTop = card._dungeonCommon and -21 or -6
        card.nameText:SetPoint("TOPLEFT", card, "TOPLEFT", inset + portraitWidth + gap, nameTop)
        card.nameText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -inset, nameTop)
        card.nameText:SetHeight(card._dungeonCommon and 20 or (compact and 30 or 34))
        card.nameText:SetJustifyV("TOP")
        if card.nameText.SetMaxLines then card.nameText:SetMaxLines(card._dungeonCommon and 1 or 2) end
        card.detailBadge:ClearAllPoints()
        card.detailBadge:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", inset + portraitWidth + gap, 7)
        card.detailText:ClearAllPoints()
        card.detailText:SetPoint("CENTER", card.detailBadge, "CENTER", 0, 0)
        card.detailText:SetJustifyH("CENTER")
        card.detailText:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "")
        card.detailText:SetWordWrap(false)
        card.detailBadge:SetShown(not card._dungeonCommon)
        card:SetHeight(cardHeight)
        y = y + cardHeight + 3
    end
    UI.bossScrollContent:SetHeight(math.max(1, y + 2))
end

-- Reflow existing frames only: no selection, editor rebuild, or data refresh.
function Page:RelayoutPrototype()
    if not (Page._visible and UI.rightRoot and UI.spellScrollChild) then return end
    SyncScrollChildWidth()
    RelayoutMapNavigation()
    RelayoutBossNavigation()
    -- DungeonCommon owns the full-height host while this existing flag is set.
    if UI.rightPanelSingleGrid == true then return end
    ApplyBossRightPanelLayout()
    local width = math.max(1, UI.spellScrollChild:GetWidth())
    local columns = C.SPELL_CARD.cols
    local cardWidth = math.max(1, (width - (columns - 1) * C.SPELL_CARD.gapX) / columns)
    local rowHeights = {}
    for i, card in ipairs(CARD_CACHE.activeSpellCards) do
        card:SetWidth(cardWidth)
        SetAdaptiveSpellCardTitle(card, card.title:GetText())
        local row = math.floor((i - 1) / columns) + 1
        rowHeights[row] = C.SPELL_CARD.height
    end
    local y, visibleHeight = 0, 0
    local totalRows = math.max(1, math.ceil((STATE.spellCardCount or #CARD_CACHE.activeSpellCards) / columns))
    for row = 1, totalRows do
        local height = rowHeights[row] or C.SPELL_CARD.height
        for i = (row - 1) * columns + 1, math.min(row * columns, #CARD_CACHE.activeSpellCards) do
            local card = CARD_CACHE.activeSpellCards[i]
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", UI.spellScrollChild, "TOPLEFT",
                ((i - 1) % columns) * (cardWidth + C.SPELL_CARD.gapX), -y)
            card:SetSize(cardWidth, height)
        end
        if row <= C.SPELL_LIST_VISIBLE_ROWS then visibleHeight = y + height end
        y = y + height + C.SPELL_CARD.gapY
    end
    UI.spellScrollChild:SetHeight(math.max(1, y - C.SPELL_CARD.gapY))
    local visibleRows = math.min(C.SPELL_LIST_VISIBLE_ROWS, totalRows)
    UI.spellListMeasuredHeight = visibleRows * C.SPELL_CARD.height
        + math.max(0, visibleRows - 1) * C.SPELL_CARD.gapY
    ApplyBossRightPanelLayout()
    RefreshSpellDetailHeaderLayout()
    if UI.spellSettingsCardSession then
        UI.spellSettingsCardSession:Relayout()
        if ApplyBossCustomCardLayouts then
            ApplyBossCustomCardLayouts(UI.spellSettingsCardSession)
        end
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

-- 复选框标签在自己的 Grid 标签列内换行，由共享呈现测量行高。
-- 保留原 Tooltip 宽度判断与事件脚本，不改变控件及配置行为。
local function ApplyBossSettingsLabelSafety(widgets)
    if type(widgets) ~= "table" then return end
    -- 标签几何（锚点与换行）与原实现完全相同，只是提成函数：下面补装 Core 画器时
    -- 必须经过 ApplyControlAppearance，而它会按公共规则重排 checkbox 标签，所以画器
    -- 装回之后要再按本页规则施加一次同样的几何，数值与原来一致。
    local function ApplyBossSettingsCheckboxLabelGeometry(widget, label)
        label:ClearAllPoints()
        label:SetPoint("LEFT", widget.checkbox, "RIGHT", 7, 0)
        label:SetPoint("RIGHT", widget, "RIGHT", -2, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        if label.SetMaxLines then label:SetMaxLines(0) end
        if widget.SetClipsChildren then widget:SetClipsChildren(false) end
    end
    for _, widget in pairs(widgets) do
        if widget and widget.checkbox and widget.label
            and widget._exSettingsPresentation ~= "card" and widget._exSettingsPresentation ~= "switch" then
            local label = widget.label
            ApplyBossSettingsCheckboxLabelGeometry(widget, label)

            local fullLabel = tostring(label:GetText() or "")
            local availableWidth = math.max(18, (widget:GetWidth() or 0) - 37)
            local truncated = label.GetUnboundedStringWidth
                and (label:GetUnboundedStringWidth() or 0) > availableWidth
            -- checkbox 的 OnLeave 槽位上有 Core 的 pressed 画器（HookScript 挂的，
            -- 与业务脚本同在一个 extrinsic 槽位），SetScript 会把它一起清掉。
            -- 两支都先走 ClearControlScript 丢掉该槽位的安装记录，写完业务脚本后
            -- 再调一次 ApplyControlAppearance 把画器补回来；顺序不能颠倒。
            EXUI:ClearControlScript(widget.checkbox, "OnEnter")
            EXUI:ClearControlScript(widget.checkbox, "OnLeave")
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
            end
            EXUI:ApplyControlAppearance(widget)
            ApplyBossSettingsCheckboxLabelGeometry(widget, label)
        end
    end
end

RefreshSettingsDynamicWidgets = function(mdb)
    local widgets = GetSpellSettingsWidgets()
    if not (type(widgets) == "table" and type(mdb) == "table") then
        return
    end
    ApplyBossSettingsLabelSafety(widgets)
    local spellDisabled = mdb.enabled == false
    if UI.spellDetailIcon then
        UI.spellDetailIcon:SetDesaturated(spellDisabled)
        UI.spellDetailIcon:SetAlpha(spellDisabled and 0.65 or 1)
    end

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
    EXUI:RefreshSoundSelector({
        contents = { pack = targetAlertLabelWidget, lsm = targetAlertLSMWidget,
            file = targetAlertPathWidget, tts = targetAlertTtsWidget },
        value = targetAlertSource, preview = targetAlertValueTestWidget,
        enabled = targetAlertVoiceUsable, setUsable = SetWidgetUsable, updateInactive = true,
    })
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
            -- “播放名称”与“播放数字”是两项独立设置；关闭数字不能让名称失去操作权。
            SetWidgetUsable(playTextWidget, true)
        end

        EXUI:RefreshSoundSelector({
            contents = { pack = packWidget, lsm = lsmWidget, file = pathWidget, tts = ttsWidget },
            value = source, preview = valueTestWidget, enabled = configEnabled,
            setUsable = SetWidgetUsable,
        })

        SetWidgetInteractable(widgets[prefix .. "Enabled"], true)
        SetWidgetInteractable(sourceWidget, configEnabled)
        SetWidgetInteractable(packWidget, configEnabled)
        SetWidgetInteractable(lsmWidget, configEnabled)
        SetWidgetInteractable(pathWidget, configEnabled)
        SetWidgetInteractable(ttsWidget, configEnabled)
        SetWidgetInteractable(valueTestWidget, configEnabled)
        SetWidgetInteractable(countdownLeadWidget, true)
        SetWidgetInteractable(playTextWidget, true)
    end
    RefreshCountdownSegmentedControl(mdb)
    if RefreshVoicePreviewDisplay then RefreshVoicePreviewDisplay() end
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
    local widgets = GetSpellSettingsWidgets()
    if not (STATE.spellSettingsGridBound and type(mdb) == "table" and type(widgets) == "table"
            and UI.spellSettingsCardConfig == mdb) then
        return false
    end

    -- 固定 schema 的控件保留其原有回调；BuildSpellEditorDraft 已原地刷新
    -- 同一张 mdb，因此这些回调继续指向当前技能，而不需要 Grid:Render。
    for _, card in ipairs(SETTINGS_LAYOUT.cards or {}) do
        for _, item in ipairs((card.content and card.content.items) or {}) do
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

    local ok, err, handle = Engine:TryPlayStandaloneSound(
        triggerCfg,
        "bosspage_preview:" .. tostring(eventID) .. ":" .. tostring(idx),
        { triggerIndex = idx }
    )
    return ok, err, handle
end

local function ResolveVoicePreviewCaption(mdb, triggerIndex)
    if type(mdb) ~= "table" then return L["静默"] end
    local prefix = "tr" .. tostring(triggerIndex)
    local source = NormalizeTriggerSource(mdb[prefix .. "Source"])
    local value = ""
    if source == "pack" then
        value = NormalizeOptionText(mdb[prefix .. "Label"])
        if value == "" then
            local event = FindEventByID(selectedEventID)
            local eventID = GetEventID(event)
            local rawEvent = eventID and (GetRawEncounterEventRow(eventID) or event) or nil
            value = NormalizeOptionText(rawEvent and rawEvent.voiceLabel)
        end
    elseif source == "lsm" then
        value = NormalizeOptionText(mdb[prefix .. "LSM"])
    elseif source == "tts" then
        value = NormalizeOptionText(mdb[prefix .. "TtsText"])
    else
        value = NormalizeOptionText(mdb[prefix .. "Path"])
    end
    return value ~= "" and value or L["未选择"]
end

local function BuildVoicePreviewSequence(mdb)
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
            entry.text = ResolveVoicePreviewCaption(mdb, 2)
        elseif playDigits and second >= 1 and second <= lead then
            entry.kind = "digit"
            entry.value = second
            entry.text = tostring(second)
        elseif second == 0 and playCastStart then
            entry.kind = "trigger"
            entry.triggerIndex = 1
            entry.text = ResolveVoicePreviewCaption(mdb, 1)
        end
        sequence[#sequence + 1] = entry
    end
    return sequence, earliest
end

RefreshCountdownSegmentedControl = function(mdb)
    local segmented = UI.voiceCountdownSelector
    if not segmented then return end
    local selected = tostring(NormalizeCountdownLeadSeconds(
        type(mdb) == "table" and (mdb.tr2CountdownLead or mdb.countdownLead) or 5))
    segmented:SetValue(selected)
    segmented:SetDisabled(false)
end

RefreshVoicePreviewTimeline = function(sequence)
    local timeline = UI.voicePreviewTimeline
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
        node._previewSecond = second
        if entry then
            node._previewKind = entry.kind
            node._previewTriggerIndex = entry.triggerIndex
            if entry.kind == "digit" then
                node.value:SetText(entry.text or tostring(second))
                EXUI:ClearControlSurface(node.valueHost)
                node.value:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.cardTitle, "")
                node.value:SetTextColor(1, 1, 1, 1)
            else
                node.value:SetText(tostring(entry.text or L["未选择"]))
                EXUI:SetControlSurface(node.valueHost, 4, GC.panel, GC.cardBorder)
                node.value:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.exboss.previewText, "")
                node.value:SetTextColor(unpack(GC.selectedText))
            end
        else
            node._previewKind = "empty"
            node._previewTriggerIndex = nil
            node.value:SetText("")
            node.value:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.exboss.previewText, "")
            node.value:SetTextColor(unpack(GC.textDim))
            EXUI:ClearControlSurface(node.valueHost)
        end
    end
    timeline._visibleNodeCount = 7
    if timeline._layout then timeline:_layout() end
end

RefreshVoicePreviewDisplay = function()
    local widgets = GetSpellSettingsWidgets()
    local preview = type(widgets) == "table" and widgets["description_voice_preview_sequence"] or nil
    local sequence = BuildVoicePreviewSequence(STATE.spellEditorDraft)
    local parts = {}
    for _, entry in ipairs(sequence) do
        if entry.seconds == 0 then
            parts[#parts + 1] = string.format("0 %s：%s", L["秒"], entry.text)
        else
            parts[#parts + 1] = string.format("%s %d %s：%s", L["前"], entry.seconds, L["秒"], entry.text)
        end
    end
    if preview then
        local textTarget = preview.SetText and preview or preview.text
        if textTarget and textTarget.SetText then
            textTarget:SetText(UI.voicePreviewTimeline and " " or table.concat(parts, "  ›  "))
        end
    end
    if RefreshVoicePreviewTimeline then RefreshVoicePreviewTimeline(sequence) end
end

-- 序列预览播的是一串 C_Timer.After，没有单一声音句柄，用不了 RunSoundPreview；
-- 播放态只能由调用方用 SetSoundPreviewPlaying 告知公共试听按钮。只改外观，不碰播放。
-- 挂在 Page 上而不是新增顶层 local：本文件已贴着 Lua 5.1 主函数 200 个 local 的上限。
function Page._SetVoiceSequencePreviewPlaying(playing)
    local widgets = GetSpellSettingsWidgets()
    local button = type(widgets) == "table" and widgets["voiceSequencePreview"] or nil
    if button then
        EXUI:SetSoundPreviewPlaying(button, playing)
    end
end

CancelVoiceSequencePreview = function()
    STATE.voicePreviewGeneration = (tonumber(STATE.voicePreviewGeneration) or 0) + 1
    Page._SetVoiceSequencePreviewPlaying(false)
end

StartVoiceSequencePreview = function()
    CancelVoiceSequencePreview()
    local generation = STATE.voicePreviewGeneration
    local revision = STATE.spellEditorRevision
    local sequence, earliest = BuildVoicePreviewSequence(STATE.spellEditorDraft)
    local scheduledAny, lastDelay = false, 0
    for _, entry in ipairs(sequence) do
        if entry.kind ~= "silent" then
            local scheduledEntry = entry
            local delay = math.max(0, earliest - scheduledEntry.seconds)
            scheduledAny = true
            if delay > lastDelay then lastDelay = delay end
            C_Timer.After(delay, function()
                if generation ~= STATE.voicePreviewGeneration
                    or revision ~= STATE.spellEditorRevision
                    or Page._visible ~= true then
                    return
                end
                if scheduledEntry.kind == "digit" then
                    local countdown = ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown
                    if countdown and type(countdown.PreviewDigit) == "function" then
                        countdown:PreviewDigit(scheduledEntry.value)
                    end
                elseif scheduledEntry.kind == "trigger" then
                    PlayTriggerPreviewByIndex(scheduledEntry.triggerIndex)
                end
            end)
        end
    end
    if not scheduledAny then
        return
    end
    Page._SetVoiceSequencePreviewPlaying(true)
    -- 序列正常走完：Core 不知道这串计时器何时结束，必须由本页收回播放态。
    -- 本次之后又点了播放／被取消时 generation 已变，这里不再回写。
    C_Timer.After(lastDelay, function()
        if generation ~= STATE.voicePreviewGeneration then
            return
        end
        Page._SetVoiceSequencePreviewPlaying(false)
    end)
end

local function ReleaseSpellSettingsCardSession()
    if UI.spellSettingsCardSession and UI.spellSettingsCardSession.byId then
        local centralLead = UI.spellSettingsCardSession:GetWidget("text", "centralLead")
        if centralLead and centralLead._exBossUnitInside then
            centralLead:SetTextInsets(9, 9, 0, 0)
            if centralLead.label then
                centralLead.label:ClearAllPoints()
                centralLead.label:SetPoint("LEFT", centralLead, "RIGHT", 5, 0)
                centralLead.label:SetJustifyH("LEFT")
                centralLead.label:SetText(centralLead._exBossUnitOriginalText or L["(秒)"])
            end
            centralLead._exBossUnitInside = nil
            centralLead._exBossUnitOriginalText = nil
        end
        local enabled = UI.spellSettingsCardSession:GetWidget("master", "enabled")
        if enabled then EXUI:ReleaseCheckboxOnOffVisual(enabled) end
        for _, spec in ipairs({ { "voice", "tr0ValueTest" }, { "voice", "tr1ValueTest" },
            { "voice", "tr2ValueTest" }, { "voice", "voiceSequencePreview" },
            { "target", "targetAlertStartValueTest" } }) do
            local button = UI.spellSettingsCardSession:GetWidget(spec[1], spec[2])
            if button and button._exBossPreviewOriginalFrameLevel then
                button:SetFrameLevel(button._exBossPreviewOriginalFrameLevel)
                button._exBossPreviewOriginalFrameLevel = nil
            end
        end
        for _, state in pairs(UI.spellSettingsCardSession.byId) do
            local card = state and state.card
            if card and card._exBossLegendBacking then
                card._exBossLegendBacking:Hide()
            end
            if card and card._exBossVoiceTimingSurface then
                card._exBossVoiceTimingSurface:Hide()
            end
            if card and card._exBossTextDividers then
                for _, divider in ipairs(card._exBossTextDividers) do divider:Hide() end
            end
            if card and card._exBossVoicePrimaryDividers then
                for _, divider in ipairs(card._exBossVoicePrimaryDividers) do divider:Hide() end
            end
            if card and card._exBossVoiceRuleDivider then
                card._exBossVoiceRuleDivider:Hide()
            end
            if card and card._exBossTargetDividers then
                for _, divider in ipairs(card._exBossTargetDividers) do divider:Hide() end
            end
            if card and card._exBossVoicePreviewDivider then
                card._exBossVoicePreviewDivider:Hide()
            end
            if card and card._exBossCastCheckHelp then
                card._exBossCastCheckHelp:Hide()
            end
            if card and card._exBossVoicePreviewTimeline then
                card._exBossVoicePreviewTimeline:Hide()
                card._exBossVoicePreviewTimeline._exBossCardSession = nil
                card._exBossVoicePreviewTimeline._exBossCardState = nil
                card._exBossVoicePreviewTimeline._layoutBusy = nil
            end
        end
    end
    UI.voiceCountdownSelector = nil
    UI.voicePreviewTimeline = nil
    if UI.spellSettingsCardSession and type(UI.spellSettingsCardSession.Release) == "function" then
        UI.spellSettingsCardSession:Release()
    end
    UI.spellSettingsCardSession = nil
end

local function AnchorBossWidget(widget, parent, left, top, width, height, right)
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

local function SetBossPlayButtonVisual(button)
    if button then EXUI:ApplySoundPreviewAppearance(button) end
end

local function LayoutBossAudioControls(session, cardID, prefix, parent, top, left, sourceWidth, rightPad)
    EXUI:LayoutSoundSelector(parent, {
        source = session:GetWidget(cardID, prefix .. "Source"),
        preview = session:GetWidget(cardID, prefix .. "ValueTest"),
        contents = { pack = session:GetWidget(cardID, prefix .. "Label"),
            lsm = session:GetWidget(cardID, prefix .. "LSM"),
            file = session:GetWidget(cardID, prefix .. "Path"),
            tts = session:GetWidget(cardID, prefix .. "TtsText") },
        top = top, left = left, sourceWidth = sourceWidth, right = rightPad or 12,
        height = 30, previewWidth = 28, paintPreview = SetBossPlayButtonVisual,
    })
end

local function LayoutBossAudioRow(session, cardID, prefix, parent, top, labelWidth, sourceWidth, rightPad)
    AnchorBossWidget(session:GetWidget(cardID, prefix .. "Enabled"), parent, 14, top, labelWidth, 30)
    LayoutBossAudioControls(session, cardID, prefix, parent, top, 14 + labelWidth, sourceWidth, rightPad)
end

local function LayoutTextSettingsCard(session)
    local state = session.byId.text
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end

    local list = _G.ExwindGrid:GetSettingsListSession(body)
    for _, entry in ipairs(list and list.entries or {}) do
        local divider = entry.host and entry.host._exSettingsRowDivider
        if divider then divider:Hide() end
    end
    for index, top in ipairs({ 43, 91, 139 }) do
        local divider = card._exBossTextDividers and card._exBossTextDividers[index]
        if divider then
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -top)
            divider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -14, -top)
            divider:Show()
        end
    end

    local inset, gap = 14, 8
    local bodyWidth = math.max(1, body:GetWidth() or 600)
    local labelWidth = math.max(150, math.floor((bodyWidth - inset * 2) * 0.46))
    local controlLeft = inset + labelWidth
    local controlWidth = math.max(180, bodyWidth - controlLeft - inset)
    local modeWidth = math.max(132, math.floor((controlWidth - gap) * 0.56))
    local leadWidth = 70

    local eventColorEnabled = session:GetWidget("text", "eventColorEnabled")
    local eventColorMode = session:GetWidget("text", "eventColorMode")
    local eventColor = session:GetWidget("text", "eventColor")
    local centralEnabled = session:GetWidget("text", "centralEnabled")
    local centralLead = session:GetWidget("text", "centralLead")
    local centralText = session:GetWidget("text", "centralText")
    local countdownEnabled = session:GetWidget("text", "countdownEnabled")
    local preAlertText = session:GetWidget("text", "preAlertText")
    local timerBarRenameEnabled = session:GetWidget("text", "timerBarRenameEnabled")
    local timerBarRenameText = session:GetWidget("text", "timerBarRenameText")

    AnchorBossWidget(eventColorEnabled, body, inset, 4, labelWidth, 30)
    AnchorBossWidget(eventColorMode, body, controlLeft, 4, modeWidth, 30)
    if eventColor then
        -- 保留 RefreshSettingsDynamicWidgets 对自定义色控件的原显隐判断。
        eventColor:ClearAllPoints()
        eventColor:SetPoint("TOPLEFT", body, "TOPLEFT", controlLeft + modeWidth + gap, -4)
        eventColor:SetSize(math.max(1, controlWidth - modeWidth - gap), 30)
    end

    AnchorBossWidget(centralEnabled, body, inset, 52, labelWidth, 30)
    AnchorBossWidget(centralLead, body, controlLeft, 52, leadWidth, 30)
    AnchorBossWidget(centralText, body, controlLeft + leadWidth + gap, 52,
        math.max(1, controlWidth - leadWidth - gap), 30)
    if centralLead and centralLead.label then
        if not centralLead._exBossUnitInside then
            centralLead._exBossUnitOriginalText = centralLead.label:GetText()
        end
        centralLead._exBossUnitInside = true
        centralLead:SetTextInsets(9, 30, 0, 0)
        centralLead.label:ClearAllPoints()
        centralLead.label:SetPoint("RIGHT", centralLead, "RIGHT", -8, 0)
        centralLead.label:SetJustifyH("RIGHT")
        centralLead.label:SetText(L["秒"])
        centralLead.label:Show()
    end

    AnchorBossWidget(countdownEnabled, body, inset, 100, labelWidth, 30)
    AnchorBossWidget(preAlertText, body, controlLeft, 100, controlWidth, 30)
    AnchorBossWidget(timerBarRenameEnabled, body, inset, 148, labelWidth, 30)
    AnchorBossWidget(timerBarRenameText, body, controlLeft, 148, controlWidth, 30)

    local contentHeight = 196
    state.reportedHeight = contentHeight
    return contentHeight
end

local function LayoutDisplaySettingsCard(session)
    local state = session.byId.display
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    local ring = session:GetWidget("display", "ringEnabled")
    local castBar = session:GetWidget("display", "castProgressBarEnabled")
    local castCheck = session:GetWidget("display", "ringCastCheckEnabled")
    local castDescription = session:GetWidget("display", "description_cast_check")
    local rename = session:GetWidget("display", "castProgressBarRenameEnabled")
    local renameText = session:GetWidget("display", "castProgressBarRenameText")
    local inset, gap = 14, 8
    local choiceWidth = math.max(1, ((body:GetWidth() or 400) - inset * 2 - gap) / 2)

    AnchorBossWidget(ring, body, inset, 6, choiceWidth, 40)
    AnchorBossWidget(castBar, body, inset + choiceWidth + gap, 6, choiceWidth, 40)
    local list = _G.ExwindGrid:GetSettingsListSession(body)
    for _, entry in ipairs(list and list.entries or {}) do
        local divider = entry.host and entry.host._exSettingsRowDivider
        if divider then divider:Hide() end
    end
    if not card._exBossCastCheckHelp then
        local ringTexture = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RingWhiteThin2.tga"
        local help = EXUI:CreatePicButton(body, 11, 11,
            ringTexture, ringTexture, ringTexture, nil, true)
        card._exBossCastCheckHelp = help
        help.label = EXUI:CreateVisualFontString(help, EXFONTFRAME, "GameFontDisableSmall")
        help.label:SetPoint("CENTER", 0, 0)
        help.label:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.exboss.micro, "")
        help.label:SetText("?")
        help.label:SetTextColor(unpack(GC.textDim))
        card._exBossCastCheckHelp:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["检测当前读条能否完成，来不及时以红色提示。"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        card._exBossCastCheckHelp:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    AnchorBossWidget(castCheck, body, inset, 62, nil, 64, inset)
    if castDescription then
        AnchorBossWidget(castDescription, castCheck, 0, 33, nil, 23, 14)
        if castDescription.text then
            castDescription.text:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.hint, "")
            castDescription.text:SetTextColor(unpack(GC.textDim))
        end
        EXUI:LayoutCheckboxCardDescription(castCheck, castDescription, 23)
    end
    card._exBossCastCheckHelp:ClearAllPoints()
    card._exBossCastCheckHelp:SetPoint("TOPRIGHT", castCheck, "TOPRIGHT", -8, -7)
    card._exBossCastCheckHelp:SetFrameLevel(castCheck:GetFrameLevel() + 3)
    card._exBossCastCheckHelp:Hide() -- 用户要求删除施法检测右上角问号（原 Show()）

    local renameWidth = choiceWidth
    AnchorBossWidget(rename, body, inset, 148, renameWidth, 30)
    if renameText then
        renameText:ClearAllPoints()
        renameText:SetPoint("TOPLEFT", body, "TOPLEFT", inset + renameWidth + gap, -148)
        renameText:SetPoint("TOPRIGHT", body, "TOPRIGHT", -inset, -148)
        renameText:SetHeight(30)
        renameText:Show()
    end
    return 196
end

local function LayoutTargetSettingsCard(session)
    local state = session.byId.target
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    local list = _G.ExwindGrid:GetSettingsListSession(body)
    for _, entry in ipairs(list and list.entries or {}) do
        local divider = entry.host and entry.host._exSettingsRowDivider
        if divider then divider:Hide() end
    end
    local start = session:GetWidget("target", "targetAlertStartEnabled")
    local ring = session:GetWidget("target", "targetAlertRingEnabled")
    local textChoice = session:GetWidget("target", "targetAlertTextEnabledV2")
    local icon = session:GetWidget("target", "targetAlertIconEnabled")
    local stealth = session:GetWidget("target", "targetAlertStealthEnabledV2")
    local voice = session:GetWidget("target", "targetAlertVoiceEnabled")

    AnchorBossWidget(start, body, 12, 8, nil, 34, 12)
    if start and start.checkbox then
        start.checkbox:ClearAllPoints()
        start.checkbox:SetPoint("RIGHT", start, "RIGHT", -2, 0)
        if start.label then
            start.label:ClearAllPoints()
            start.label:SetPoint("LEFT", start, "LEFT", 0, 0)
            start.label:SetPoint("RIGHT", start.checkbox, "LEFT", -8, 0)
        end
    end
    local choiceWidth = math.max(68, ((body:GetWidth() or 380) - 40) / 3)
    for index, widget in ipairs({ ring, textChoice, icon }) do
        AnchorBossWidget(widget, body, 12 + (index - 1) * (choiceWidth + 8), 64, choiceWidth, 36)
    end
    AnchorBossWidget(stealth, body, 12, 118, nil, 44, 12)
    AnchorBossWidget(voice, body, 12, 186, nil, 30, 12)
    LayoutBossAudioControls(session, "target", "targetAlertStart", body, 232, 12, 110, 12)
    if voice then
        voice:ClearAllPoints()
        voice:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -186)
        voice:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -186)
        voice:SetHeight(32)
    end

    if not card._exBossTargetDividers then
        card._exBossTargetDividers = {}
        for index = 1, 2 do
            card._exBossTargetDividers[index] = EXUI:CreateSettingsSeparator(body, 1)
        end
    end
    for index, top in ipairs({ 118, 174 }) do
        local divider = card._exBossTargetDividers[index]
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -top)
        divider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -top)
        divider:SetShown(index == 2)
    end
    return 274
end

local function SetBossVoicePreviewVisibility(session)
    local state = session and session.byId.voice
    local card = state and state.card
    if not card then return false end
    -- 预览区属于只读说明，始终保留；未启用的时刻由现有 sequence 显示为空。
    local visible = true
    local previewHeading = session:GetWidget("voice", "description_voice_preview_heading")
    if previewHeading then previewHeading:Hide() end
    local previewButton = session:GetWidget("voice", "voiceSequencePreview")
    if previewButton then previewButton:SetShown(visible) end
    if card._exBossVoicePreviewDivider then card._exBossVoicePreviewDivider:Hide() end
    if card._exBossVoicePreviewBackground then card._exBossVoicePreviewBackground:SetShown(visible) end
    if card._exBossVoicePreviewTimeline then card._exBossVoicePreviewTimeline:SetShown(visible) end
    if card._exBossVoiceBranchV then card._exBossVoiceBranchV:Hide() end
    if card._exBossVoiceBranchH then card._exBossVoiceBranchH:Hide() end
    return visible
end

local function GetBossVoiceContentHeight(visible, timelineHeight)
    return visible and (200 + (timelineHeight or 70)) or 218
end

local function LayoutVoiceSettingsCard(session)
    local state = session.byId.voice
    local card, body = state and state.card, state and state.body
    if not (card and body) then return end
    local list = _G.ExwindGrid:GetSettingsListSession(body)
    for _, entry in ipairs(list and list.entries or {}) do
        local divider = entry.host and entry.host._exSettingsRowDivider
        if divider then divider:Hide() end
    end
    local labelWidth = math.max(128, math.floor((body:GetWidth() or 600) * 0.36))
    local sourceWidth = math.max(78, math.floor((body:GetWidth() - labelWidth - 56) * 0.25))
    LayoutBossAudioRow(session, "voice", "tr0", body, 4, labelWidth, sourceWidth, 12)
    LayoutBossAudioRow(session, "voice", "tr1", body, 48, labelWidth, sourceWidth, 12)
    for index, top in ipairs({ 41, 85 }) do
        local line = card._exBossVoicePrimaryDividers and card._exBossVoicePrimaryDividers[index]
        if line then
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -top)
            line:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -top)
            line:Show()
        end
    end

    local surface = card._exBossVoiceTimingSurface
    if not surface then return end
    surface:ClearAllPoints()
    surface:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -94)
    surface:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 10)
    surface:SetFrameLevel(body:GetFrameLevel() or 1)
    EXUI:ClearControlSurface(surface)
    surface:Show()

    local heading = session:GetWidget("voice", "description_countdown_group")
    local note = session:GetWidget("voice", "description_countdown_note")
    local digit = session:GetWidget("voice", "tr2Enabled")
    local segmented = session:GetWidget("voice", "tr2CountdownLead")
    local playName = session:GetWidget("voice", "tr2PlayTextEnabled")
    local previewHeading = session:GetWidget("voice", "description_voice_preview_heading")
    local previewButton = session:GetWidget("voice", "voiceSequencePreview")
    local previewSequence = session:GetWidget("voice", "description_voice_preview_sequence")
    if heading then heading:Hide() end
    if note then note:Hide() end
    local controlLeft = labelWidth + 2
    AnchorBossWidget(digit, surface, 2, 4, controlLeft - 2, 30)
    if segmented then
        segmented:ClearAllPoints()
        segmented:SetPoint("TOPLEFT", surface, "TOPLEFT", controlLeft, -4)
        segmented:SetPoint("TOPRIGHT", surface, "TOPRIGHT", 0, -4)
        -- Keep the shared control's relayout at the same height as this card's inputs.
        segmented.itemHeight = 30
        segmented:SetHeight(30)
        segmented:Show()
    end
    AnchorBossWidget(playName, surface, 2, 44, controlLeft - 2, 30)
    LayoutBossAudioControls(session, "voice", "tr2", surface, 44, controlLeft, sourceWidth, 0)
    if card._exBossVoiceRuleDivider then
        card._exBossVoiceRuleDivider:Hide()
    end

    local previewVisible = SetBossVoicePreviewVisibility(session)
    local divider = card._exBossVoicePreviewDivider
    if divider then
        divider:Hide()
    end
    if previewHeading then previewHeading:Hide() end
    local background = card._exBossVoicePreviewBackground
    if background then
        background:ClearAllPoints()
        background:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, -82)
        background:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", 0, 0)
        EXUI:SetControlSurface(background, 5, GC.panel, GC.cardBorder)
        background:SetShown(previewVisible)
    end
    if previewSequence then previewSequence:Hide() end
    local timeline = card._exBossVoicePreviewTimeline
    local timelineHeight = 68
    if timeline then
        timeline:ClearAllPoints()
        timeline:SetPoint("TOPLEFT", surface, "TOPLEFT", 10, -94)
        timeline:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -10, -94)
        if timeline._layout then timeline:_layout() end
        timelineHeight = timeline:GetHeight() or timelineHeight
    end
    if previewButton then
        previewButton:ClearAllPoints()
        previewButton:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -8, 8)
        previewButton._exBossPreviewOriginalFrameLevel = previewButton._exBossPreviewOriginalFrameLevel
            or previewButton:GetFrameLevel()
        previewButton:SetFrameLevel(surface:GetFrameLevel() + 6)
        previewButton._exButtonVariant = "secondary"
        EXUI:ApplyControlAppearance(previewButton)
        SetBossPlayButtonVisual(previewButton)
        previewButton:SetSize(28, 28)
        previewButton:SetShown(previewVisible)
    end
    local contentHeight = GetBossVoiceContentHeight(previewVisible, timelineHeight)
    -- The existing geometry report must track resize measurements as well as
    -- text changes, so its next comparison cannot use an older narrow width.
    state.reportedHeight = contentHeight
    return contentHeight
end

ApplyBossCustomCardLayouts = function(session)
    if not (session and session.byId and session.GetWidget) then return end
    LayoutTextSettingsCard(session)
    LayoutDisplaySettingsCard(session)
    LayoutVoiceSettingsCard(session)
    LayoutTargetSettingsCard(session)
    local summaryEnabled = session:GetWidget("master", "enabled")
    if summaryEnabled and UI.spellSummaryEnableHost then
        UI.spellSummaryEnableHost:SetSize(76, 26)
        summaryEnabled:ClearAllPoints()
        summaryEnabled:SetAllPoints(UI.spellSummaryEnableHost)
    end
end

local function ApplyPrototypeSettingsCardSurfaces(session)
    if not (session and session.byId) then return end
    for _, id in ipairs({ "text", "display", "voice", "target" }) do
        local state = session.byId[id]
        local card = state and state.card
        local body = state and state.body
        if card and body then
            local header = card._exSettingsCardHeader
            local title = card._exSettingsCardTitle
            if card._exSettingsListExternalHeader then
                card._exSettingsListExternalHeader.height = 13
                card._exSettingsListExternalHeader.footerPadding = 0
            end
            if header then
                header:SetHeight(24)
                header:EnableMouse(false)
                local icon = card._exSettingsCardIcon
                if icon then icon:Hide() end
                if title then
                    title:ClearAllPoints()
                    title:SetPoint("LEFT", header, "LEFT", 18, 12)
                    title:SetWidth(math.ceil(title:GetUnboundedStringWidth() or 0) + 2)
                end
                if not card._exBossLegendBacking then
                    card._exBossLegendBacking = EXUI:CreateVisualTexture(header, EXBASEFRAME)
                end
                local backing = card._exBossLegendBacking
                backing:ClearAllPoints()
                backing:SetPoint("LEFT", header, "LEFT", 12, 12)
                backing:SetSize(math.ceil((title and title:GetUnboundedStringWidth()) or 0) + 14,
                    PixelUtil.GetNearestPixelSize(2, header:GetEffectiveScale(), 1))
                backing:SetColorTexture(unpack(GC.panel))
                backing:Show()
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
    if textCard and textBody and not textCard._exBossTextDividers then
        textCard._exBossTextDividers = {}
        for index = 1, 3 do
            textCard._exBossTextDividers[index] = EXUI:CreateSettingsSeparator(textBody, 1)
        end
    end
    local summaryEnabled = session:GetWidget("master", "enabled")
    if summaryEnabled and summaryEnabled.checkbox and summaryEnabled._exSettingsPresentation ~= "card" then
        -- 只改变原控件的呈现方式；控件对象、字段、setter 与通知通道保持不变。
        EXUI:RestoreSettingsListControl(summaryEnabled)
        EXUI:PrepareSettingsListControl(summaryEnabled, {
            presentation = "card", cardCheckSize = 14, cardTextSize = 12,
        })
    end
    if summaryEnabled and summaryEnabled.checkbox then
        EXUI:ApplyCheckboxOnOffVisual(summaryEnabled)
    end
    local voiceState = session.byId.voice
    local voiceCard = voiceState and voiceState.card
    local voiceBody = voiceState and voiceState.body
    if voiceCard and voiceBody then
        voiceCard._exBossVoiceTimingSurface = voiceCard._exBossVoiceTimingSurface
            or CreateFrame("Frame", nil, voiceBody, "BackdropTemplate")
        voiceCard._exBossVoiceTimingSurface:EnableMouse(false)
        local voiceSurface = voiceCard._exBossVoiceTimingSurface
        if voiceCard._exBossVoicePreviewDivider then
            voiceCard._exBossVoicePreviewDivider:Hide()
        end
        if not voiceCard._exBossVoicePreviewBackground then
            local background = CreateFrame("Frame", nil, voiceSurface)
            background:EnableMouse(false)
            voiceCard._exBossVoicePreviewBackground = background
        end
        voiceCard._exBossVoicePreviewBackground:SetParent(voiceSurface)
        if voiceCard._exBossVoiceRuleDivider then
            voiceCard._exBossVoiceRuleDivider:Hide()
        end
        if not voiceCard._exBossVoicePrimaryDividers then
            voiceCard._exBossVoicePrimaryDividers = {}
            for index = 1, 2 do
                voiceCard._exBossVoicePrimaryDividers[index] = EXUI:CreateSettingsSeparator(voiceBody, 1)
            end
        end
        UI.voiceCountdownSelector = session:GetWidget("voice", "tr2CountdownLead")
        if not voiceCard._exBossVoicePreviewTimeline then
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
                node.time:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.hint, "")
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
                -- 右下角只为试听按钮保留轴线空间；上方名称仍可使用完整宽度。
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

                -- 名称与倒数数字共用同一条内容行。名称优先按真实内容宽度排布，
                -- 相邻触发项才在同一行内收窄并换行，不再拆成上下两条轨道。
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
                    node.valueHost:SetWidth(desiredWidth)
                    node.value:SetHeight(0)
                    local valueHeight = math.max(32, math.ceil(node.value:GetStringHeight() or 0) + 10)
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
                local heightChanged = self:GetHeight() ~= timelineHeight
                if heightChanged then self:SetHeight(timelineHeight) end
                self._layoutBusy = nil
                local list = _G.ExwindGrid:GetSettingsListSession(voiceBody)
                local owner = self._exBossCardSession
                local visible = owner and SetBossVoicePreviewVisibility(owner)
                local contentHeight = GetBossVoiceContentHeight(visible, timelineHeight)
                local state = self._exBossCardState
                if state and state.reportedHeight ~= contentHeight and list and owner and not owner.released
                    and not list.visualLayoutBusy and not owner.reflowBusy then
                    _G.ExwindGrid:RequestReflow(voiceBody)
                end
            end
            timeline:SetScript("OnSizeChanged", function(self) self:_layout() end)
            voiceCard._exBossVoicePreviewTimeline = timeline
        end
        voiceCard._exBossVoicePreviewTimeline._exBossCardSession = session
        voiceCard._exBossVoicePreviewTimeline._exBossCardState = voiceState
        UI.voicePreviewTimeline = voiceCard._exBossVoicePreviewTimeline
    end
    for id, layout in pairs({ text = LayoutTextSettingsCard, display = LayoutDisplaySettingsCard, voice = LayoutVoiceSettingsCard,
        target = LayoutTargetSettingsCard }) do
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
    ApplyBossCustomCardLayouts(session)
end

-- [三模式边界] 这里只允许各模式完成后的宿主尺寸/reflow 接线；revision/context、extra isCurrent、DungeonCommon Hide/Render 和普通 draft 绑定禁止修改。
local function RefreshSpellSettingsPanel(expectedRevision)
    if expectedRevision ~= nil and expectedRevision ~= STATE.spellEditorRevision then
        return
    end
    if not (UI.spellSettingsGridChild and UI.spellSettingsEmptyText) then
        return
    end

    if Page.Extras then Page.Extras:Hide() end

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
            ReleaseSpellSettingsCardSession()
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
    if selectedExtraKey and Page.Extras then
        local extraKey = selectedExtraKey
        local extra = ExBoss.BossEncounters:GetExtra(encounterID, extraKey)
        local slot = GetCurrentSpellSlotKey()
        local scene = GetSlotCategory(slot)
        local revision = STATE.spellEditorRevision
        STATE.spellSettingsGridBound = false
        STATE.currentSpellSlotKey = nil
        UI.spellSettingsGridScroll:SetVerticalScroll(0)
        ReleaseSpellSettingsCardSession()
        UI.spellDetailHeader:Show()
        UI.spellDetailPlaceholder:Hide()
        UI.spellDetailIcon:SetTexture(extra.icon or 134400)
        UI.spellDetailIcon:Show()
        UI.spellDetailIcon:SetDesaturated(false)
        UI.spellDetailIcon:SetAlpha(1)
        if UI.spellDetailIconBorder then UI.spellDetailIconBorder:Show() end
        UI.spellDetailTitle:SetText(extra.label)
        UI.spellDetailMeta:SetText("")
        UI.spellDetailCast:SetText("")
        UI.spellDetailCastChip:Hide()
        UI.spellDetailRangeChip:Hide()
        if UI.spellDetailRange then UI.spellDetailRange:SetText("") end
        if UI.spellDetailSpellIDChip then UI.spellDetailSpellIDChip:Hide() end
        if UI.spellDetailEventIDChip then UI.spellDetailEventIDChip:Hide() end
        UI.spellDetailBody:SetText(extra.description or "")
        UI.spellDetailBodyScroll:SetVerticalScroll(0)
        if UI.spellSummaryEnableHost then UI.spellSummaryEnableHost:Hide() end
        if UI.titleControlHost then UI.titleControlHost:Hide() end
        RefreshSpellDetailHeaderLayout()
        local rendered = Page.Extras:Render(UI.spellSettingsGridChild, scene, slot, encounterID, extraKey, function()
            return revision == STATE.spellEditorRevision and selectedExtraKey == extraKey
                and GetCurrentEncounterID() == encounterID and GetCurrentSpellSlotKey() == slot
        end)
        UI.spellSettingsEmptyText:SetShown(not rendered)
        if rendered then
            RegisterSpellSettingsGridAsActive(Page.Extras.MODULE_KEY)
        else
            ClearSpellSettingsGridActiveRegistration()
            local Grid = _G.ExwindGrid
            if Grid then Grid:ReleaseContainerWidgets(UI.spellSettingsGridChild) end
            UI.spellSettingsEmptyText:SetText(L["配置不可用"])
        end
        return
    end
    if UI.titleControlHost then UI.titleControlHost:Show() end
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
        -- Boss 页右下设置区现在作为标准 Grid 页面接入：
        -- 编辑模式必须显式绑定当前容器和模块，不能再借用别页的 live edit 状态。
        ReleaseSpellSettingsCardSession()
        UI.spellSettingsCardSession = Grid:MountCards(UI.spellSettingsGridChild, SETTINGS_LAYOUT, {
            pageId = SETTINGS.EDITOR_KEY,
            regionId = "boss-spell-editor",
            layoutDefaults = { left = 0, right = 0, top = 12, bottom = 0, gap = 6 },
            config = mdb,
            moduleKey = SETTINGS.EDITOR_KEY,
            scrollFrame = UI.spellSettingsGridScroll,
            exbossSummaryEnableHost = UI.spellSummaryEnableHost,
        })
        ApplyPrototypeSettingsCardSurfaces(UI.spellSettingsCardSession)
        UI.spellSettingsCardConfig = mdb
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

-- [业务排序边界] 普通 events 维持源数组顺序，extras 维持 Registry 顺序并追加；迁移只能改变卡片几何/皮肤，不能重排或合并数据。
RefreshSpellCards = function()
    if not UI.spellScrollChild then return end

    STATE.spellUIRefreshPending = false
    STATE.spellUIRefreshToken = STATE.spellUIRefreshToken + 1
    STATE.buildToken = STATE.buildToken + 1
    local token = STATE.buildToken

    ReleaseSpellCards()
    STATE.spellCardCount = nil
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

    local entries = {}
    for i = 1, #events do
        entries[#entries + 1] = events[i]
    end
    local registry = ExBoss.BossEncounters
    for _, extra in ipairs(registry and registry:GetExtras(encounterID) or {}) do
        entries[#entries + 1] = { _extra = extra }
    end
    -- 分帧创建前就按完整列表占位，说明卡不跟着已创建的卡片数量上下移动。
    STATE.spellCardCount = #entries
    local visibleRows = math.min(C.SPELL_LIST_VISIBLE_ROWS, math.max(1, math.ceil(#entries / C.SPELL_CARD.cols)))
    UI.spellListMeasuredHeight = visibleRows * C.SPELL_CARD.height
        + math.max(0, visibleRows - 1) * C.SPELL_CARD.gapY
    ApplyBossRightPanelLayout()

    local function BuildOneCard(event, index, cardW)
        if token ~= STATE.buildToken or not Page._visible or not UI.spellScrollChild then
            return nil
        end

        local card = AcquireSpellCard()
        card:SetParent(UI.spellScrollChild)

        local extra = event._extra
        local eventID = GetEventID(event)
        local spellID = GetEventSpellIdentifier(event)
        local spellCached = IsSpellDataReady(spellID)
        if spellID and not spellCached then
            RequestSpellDataLoad(spellID)
        end

        local spellName, icon = GetSpellNameAndIcon(spellID)
        local displayName = spellName or (event and event.name) or (L["未知技能 "] .. tostring(index))
        if extra then displayName, icon = extra.label, extra.icon end
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
        local y = -row * (C.SPELL_CARD.height + C.SPELL_CARD.gapY)
        card:SetPoint("TOPLEFT", UI.spellScrollChild, "TOPLEFT", x, y)
        card:SetSize(cardW, C.SPELL_CARD.height)
        card.eventData = event
        card._eventID = eventID
        card._extraKey = extra and extra.key or nil
        card._spellID = spellID
        card._selected = (extra and selectedExtraKey == extra.key)
            or (not selectedExtraKey and eventID and tonumber(selectedEventID) == eventID) or false
        card._hovered = false

        local alertKind, alertSource = ResolvePrimaryAlertIconSourceByBorder(eventID, borderR, borderG, borderB)
        if extra then alertKind, alertSource = nil, nil end
        if alertKind == "atlas" and card.alertIcon and card.alertIcon.SetAtlas then
            card.alertIcon:SetAtlas(alertSource)
            card.alertIcon:Show()
            card.icon:ClearAllPoints()
            card.icon:SetPoint("LEFT", card.alertIcon, "RIGHT", 3, 0)
        elseif alertKind == "texture" and card.alertIcon then
            card.alertIcon:SetTexture(alertSource)
            card.alertIcon:Show()
            card.icon:ClearAllPoints()
            card.icon:SetPoint("LEFT", card.alertIcon, "RIGHT", 3, 0)
        else
            if card.alertIcon then
                card.alertIcon:Hide()
            end
            card.icon:ClearAllPoints()
            card.icon:SetPoint("LEFT", 10, 0)
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
        -- 分类色已经由卡片边框表达，不再重复绘制左侧装饰竖条。
        card.leftBar:Hide()
        card:SetAlpha(1)

        local h = ComputeSpellCardHeight(card)
        card:SetHeight(h)
        card._borderR = borderR
        card._borderG = borderG
        card._borderB = borderB
        card._applyVisual = function(self)
            local br = Clamp01(self._borderR, 0.35)
            local bg = Clamp01(self._borderG, 0.35)
            local bb = Clamp01(self._borderB, 0.35)
            -- 选中只描边：底色不随选中改变，只有悬停保留原悬停底；
            -- 主色描边走内环（外框一圈仍是业务分类色）。
            local overlay = self._hovered and GC.menuHover
            local fill = GC.card
            if overlay then
                local alpha = overlay[4] or 1
                fill = { GC.card[1] * (1 - alpha) + overlay[1] * alpha,
                    GC.card[2] * (1 - alpha) + overlay[2] * alpha,
                    GC.card[3] * (1 - alpha) + overlay[3] * alpha, 1 }
            end
            EXUI:SetControlSurface(self, 4, fill, { br, bg, bb, 1 })
            if self.selectionRing then
                if self._selected then
                    if self._layoutSelectionRing then self:_layoutSelectionRing() end
                    EXUI:SetControlSurface(self.selectionRing, 3, { 0, 0, 0, 0 },
                        self._hovered and GC.primaryFillHover or GC.primaryFill)
                    self.selectionRing:Show()
                else
                    self.selectionRing:Hide()
                    EXUI:ClearControlSurface(self.selectionRing)
                end
            end
        end
        card:SetScript("OnClick", function(self)
            if not self._eventID and not self._extraKey then return end
            CancelPendingSpellTextPersist()
            CommitSpellTextFormState()
            InvalidateSpellEditorContext()
            selectedEventID = tonumber(self._eventID)
            selectedExtraKey = self._extraKey
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
        totalW = math.max(1, totalW)
        local cardW = (totalW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols
        cardW = math.max(1, cardW)

        for i, entry in ipairs(entries) do
            local card = BuildOneCard(entry, i, cardW)
            if not card then return end
        end
        if token == STATE.buildToken and UI.spellScrollChild then
            local rows = math.max(1, math.ceil(#entries / C.SPELL_CARD.cols))
            local totalH = rows * C.SPELL_CARD.height + (rows - 1) * C.SPELL_CARD.gapY + 8
            UI.spellScrollChild:SetHeight(math.max(1, totalH))
            Page:RelayoutPrototype()
        end
    end

    local function BuildAsync(entries)
        local totalW = (UI.spellScrollChild:GetWidth() or 760)
        totalW = math.max(1, totalW)
        local cardW = (totalW - ((C.SPELL_CARD.cols - 1) * C.SPELL_CARD.gapX)) / C.SPELL_CARD.cols
        cardW = math.max(1, cardW)

        for i, entry in ipairs(entries) do
            local card = BuildOneCard(entry, i, cardW)
            if not card then return end
            coroutine.yield()
        end
        if token == STATE.buildToken and UI.spellScrollChild then
            local rows = math.max(1, math.ceil(#entries / C.SPELL_CARD.cols))
            local totalH = rows * C.SPELL_CARD.height + (rows - 1) * C.SPELL_CARD.gapY + 8
            UI.spellScrollChild:SetHeight(math.max(1, totalH))
            Page:RelayoutPrototype()
        end
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
            -- 选中只描边：底色沿用各自原底（未选中为列表底，悬停时沿用悬停底），
            -- 只加一圈实心主色轮廓；不加淡底、不抬底、不显示左侧指示条。
            if hovered then
                PaintBossNavigationSurface(self,
                    GC.menuHover[1], GC.menuHover[2], GC.menuHover[3], GC.menuHover[4],
                    GC.primaryFillHover)
            else
                PaintBossNavigationSurface(self, 0, 0, 0, 0, GC.primaryFill)
            end
            self.activeBar:Hide()
            self.nameText:SetTextColor(unpack(GC.text))
        elseif hovered then
            PaintBossNavigationSurface(self, unpack(GC.menuHover))
            self.activeBar:Hide()
            self.nameText:SetTextColor(unpack(GC.text))
        else
            PaintBossNavigationSurface(self, 0, 0, 0, 0)
            self.activeBar:Hide()
            self.nameText:SetTextColor(unpack(GC.textDim))
        end
        -- 「光环语音」行的耳机图标跟随本行名称色（常态 textDim、悬停 text、
        -- 选中 selectedText），原来恒定 GC.text，和同一行的文字状态不一致。
        if self.auraIcon then
            self.auraIcon:SetVertexColor(self.nameText:GetTextColor())
        end
    end

    local y = -4
    local function ApplyPortrait(card)
        if not IsValid() or not card then return false end

        if card._dungeonCommon then
            if card.creature then
                card.creature:Hide()
            end
            if card.noPortraitText then card.noPortraitText:Hide() end
            if card.auraIconTile then card.auraIconTile:Show() end
            if card.auraIcon then card.auraIcon:Show() end
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
        b:SetPoint("TOPRIGHT", UI.bossScrollContent, "TOPRIGHT", -1, y)
        b:SetHeight(66)
        b:Show()

        b.auraIcon:Hide()
        b.auraIconTile:Hide()
        b._selected = selectedBossCommonSettings ~= true and (entry.index == selectedBossIndex)
        b._hovered = false
        b._applyVisual = ApplyVisual
        b.index = entry.index

        -- 首领行：名称在上、徽标在下，所以名称顶部对齐（与 AcquireBossCard 的
        -- 初始锚点一致）。池化卡片可能上一次被用作「光环语音」行，这里复位。
        b.nameText:ClearAllPoints()
        b.nameText:SetPoint("TOPLEFT", b.creature, "TOPRIGHT", 12, -8)
        b.nameText:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        b.nameText:SetJustifyV("TOP")
        b.nameText:SetText(tostring(boss and boss.name or (L["未知首领 "] .. tostring(entry.index))))
        b.detailText:SetText(tostring(boss and boss.encounterID or "-"))
        b.detailText:ClearAllPoints()
        b.detailText:SetPoint("CENTER", b.detailBadge, "CENTER", 0, 0)
        b.detailText:SetJustifyH("CENTER")
        b.detailText:SetFont(ExwindTools.MAIN_FONT, ExwindTools.GUIMetrics.font.text, "")
        b.detailBadge:SetWidth(math.max(46,
            math.ceil(b.detailText:GetUnboundedStringWidth() or 0) + 16))
        b.detailBadge:Show()

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
            selectedExtraKey = nil
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
        y = y - 69
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
        b:SetPoint("TOPRIGHT", UI.bossScrollContent, "TOPRIGHT", -1, y)
        b:SetHeight(66)
        b:Show()

        b.auraIconTile:Show()
        b.auraIcon:Show()
        b._dungeonCommon = true
        b.index = nil
        b._selected = selectedBossCommonSettings == true
        b._hovered = false
        b._applyVisual = ApplyVisual
        -- 本行没有编号徽标，名称若继续顶部对齐会在 66px 高的行里偏上、下方留空；
        -- 单行内容按垂直居中，和首领行「缩略图 + 文字块」的重心对齐。
        b.nameText:ClearAllPoints()
        b.nameText:SetPoint("LEFT", b.creature, "RIGHT", 12, 0)
        b.nameText:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        b.nameText:SetJustifyV("MIDDLE")
        b.nameText:SetText(L["光环语音"])
        b.detailText:SetText("")
        b.detailBadge:Hide()
        b._displayID = nil
        b._appliedDisplayID = nil
        if b.creature then
            b.creature:Hide()
        end
        if b.noPortraitText then
            b.noPortraitText:Hide()
        end
        b:SetScript("OnClick", function()
            CommitSpellTextFormState()
            InvalidateSpellEditorContext()
            selectedBossIndex = nil
            selectedExtraKey = nil
            selectedEventID = nil
            selectedBossCommonSettings = true
            RefreshActiveBossCardVisuals()
            UpdateSummary()
            RefreshModeButton()
            RefreshSpellCards()
        end)
        b:_applyVisual()
        table.insert(CARD_CACHE.activeBossCards, b)
        y = y - 69
        return true
    end

    local function Finalize()
        if not IsValid() then return end
        RelayoutBossNavigation()
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

RefreshMapTabs = function()
    if not UI.mapScrollChild then return end
    STATE.mapBuildToken = STATE.mapBuildToken + 1
    local token = STATE.mapBuildToken

    ReleaseMapTabs()
    UI.mapScrollChild:SetHeight(1)

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
            -- 选中只描边：图标框底色沿用各自原底（未选中 GC.input／悬停时沿用悬停底），
            -- 只换成一圈实心主色轮廓；不加淡底、不抬底、不加左侧指示条。
            EXUI:SetControlSurface(self.iconFrame, 10,
                hovered and GC.secondaryHoverFill or GC.input,
                hovered and GC.primaryFillHover or GC.primaryFill)
            self.icon:SetDesaturated(false)
            self.text:SetTextColor(unpack(GC.text))
        elseif hovered then
            EXUI:SetControlSurface(self.iconFrame, 10, GC.secondaryHoverFill, GC.inputHoverBorder)
            self.icon:SetDesaturated(false)
            self.text:SetTextColor(unpack(GC.text))
        else
            EXUI:SetControlSurface(self.iconFrame, 10, GC.input, GC.panelBorder)
            self.icon:SetDesaturated(true)
            self.text:SetTextColor(unpack(GC.textDim))
        end
    end

    local perRow = 4
    local gapX = 7
    local gapY = 12
    local leftPad = 0
    local topPad = 0
    local availW = (UI.mapScrollChild:GetWidth() or 208) - (leftPad * 2)
    availW = math.max(1, availW)
    local cellW = math.floor((availW - ((perRow - 1) * gapX)) / perRow)
    cellW = math.max(1, cellW)
    local cellH = math.min(90, cellW - 2) + 24
    UI.mapScrollFrame:SetHeight(math.min(2, math.ceil(#mapList / perRow)) * (cellH + gapY) - gapY + 4)
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
        if iconSize < 1 then iconSize = 1 end
        local scale = tonumber(style.scale) or 1
        if scale > 0 then
            iconSize = math.floor(iconSize * scale + 0.5)
        end
        if iconSize > (cellW - 2) then
            iconSize = cellW - 2
        end
        if iconSize < 1 then
            iconSize = 1
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
            selectedExtraKey = nil
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
        RelayoutMapNavigation()
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

-- [页面生命周期边界] Page:Render 内只可迁移 left/right root 几何与内容 reflow；generation guard、选择归一化、异步刷新顺序禁止修改。
function Page:Render(leftFrame, contentFrame)
    if not leftFrame or not contentFrame then return end
    STATE.pageRenderGeneration = STATE.pageRenderGeneration + 1
    local renderGeneration = STATE.pageRenderGeneration

    EnsureUI(leftFrame, contentFrame)

    UI.leftRoot:SetParent(leftFrame)
    UI.leftRoot:ClearAllPoints()
    UI.leftRoot:SetAllPoints(leftFrame)
    UI.leftRoot:Show()

    UI.rightViewport:SetParent(contentFrame)
    UI.rightViewport:ClearAllPoints()
    UI.rightViewport:SetAllPoints(contentFrame)
    UI.rightViewport:Show()
    UI.rightRoot:Show()
    SyncBossRightViewport()
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
    Page:RefreshTemporaryBossPreviewButton()

    C_Timer.After(0, function()
        if not Page._visible
            or renderGeneration ~= STATE.pageRenderGeneration
            or UI.leftRoot:GetParent() ~= leftFrame
            or UI.rightRoot:GetParent() ~= UI.rightViewport
                or UI.rightViewport:GetParent() ~= contentFrame then
            return
        end
        SyncSpellSettingsFrameHeight()
        SyncScrollChildWidth()
        RefreshSpellDetailHeaderLayout()
        RefreshSpellCards()
    end)
end

-- [释放边界] 必须保持先作废 revision/token，再释放 Grid 与三类池/覆盖层；卡片容器不能重复释放内容或截断 DungeonCommon Hide。
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
    ReleaseSpellSettingsCardSession()
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
    if UI.rightViewport then UI.rightViewport:Hide() end
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
            local widgets = GetSpellSettingsWidgets()
            local key = "tr" .. triggerIdx
            EXUI:RunSoundPreview(widgets and widgets[key .. "ValueTest"], function()
                return PlayTriggerPreviewByIndex(tonumber(triggerIdx))
            end, STATE.spellEditorDraft[key .. "Source"] == "tts")
            return
        end
        if info.key == "targetAlertStartValueTest" then
            local mdb = STATE.spellEditorDraft
            if type(mdb) == "table" then
                local widgets = GetSpellSettingsWidgets()
                EXUI:RunSoundPreview(widgets and widgets.targetAlertStartValueTest, function()
                    return PlayTargetAlertStartPreview(mdb)
                end, mdb.targetAlertStartSource == "tts")
            end
            return
        end
        if info.key == "voiceSequencePreview" then
            if StartVoiceSequencePreview then StartVoiceSequencePreview() end
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
    if CancelVoiceSequencePreview then CancelVoiceSequencePreview() end
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
