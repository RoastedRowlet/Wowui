---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.CountdownVoicePage = ExBoss.UI.Panel.CountdownVoicePage or {}
local Page = ExBoss.UI.Panel.CountdownVoicePage

local Runtime = ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown
if not Runtime then return end

local MODULE_KEY = "ExBoss.CountdownVoiceSettings"
local MAX_COUNTDOWN_DIGIT = tonumber(Runtime.GetMaxCountdownDigit and Runtime:GetMaxCountdownDigit()) or 5

local SOURCE_ITEMS = {
    { value = "pack", label = L["语音包"] },
    { value = "lsm", label = L["LSM音效"] },
}

local function Cell(id, child)
    return { id = id, kind = "cell", children = { child } }
end

local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "pull-countdown", title = L["开怪倒数"], children = {
            { id = "pullCountdownEnabled", kind = "control", controlType = "switch", path = "pullCountdownEnabled", label = L["启用开怪倒数"] },
            { id = "pullCountdownVoiceEnabled", kind = "control", controlType = "switch", path = "pullCountdownVoiceEnabled", label = L["为开怪倒数播放语音"] },
        } },
        { kind = "card", id = "digit-voice", title = L["数字语音"], children = {
            { kind = "table", id = "digit-voice.table", columns = {
                { title = L["启用"] }, { title = L["数字"] }, { title = L["来源"] },
                { title = L["音效选择"] }, { title = L["试听"] },
            }, children = {
                { kind = "repeat", id = "digit-voice.rows", source = "digits", template = {
                    kind = "row", id = "digit-voice.row", children = {
                        Cell("digit-voice.enabled", { id = "digitEnabled", kind = "control", controlType = "checkbox", ref = "digitEnabled" }),
                        Cell("digit-voice.number", { id = "digitNumber", kind = "text", textSource = "digitNumber" }),
                        Cell("digit-voice.source", { id = "digitSource", kind = "control", controlType = "select", ref = "digitSource" }),
                        Cell("digit-voice.lsm", { id = "digitLSM", kind = "control", controlType = "select", ref = "digitLSM", visible = "usesLSM", enabled = "digitEnabled" }),
                        Cell("digit-voice.preview", { id = "preview", kind = "button", text = L["试听"], action = "previewDigit" }),
                    },
                } },
            } },
        } },
    },
}

local scrollFrame
local scrollChild
local cardSession
local renderTicket = 0

local function ApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function NormalizeDigitSource(value)
    local source = tostring(value or "pack"):lower()
    if source ~= "lsm" then
        source = "pack"
    end
    return source
end

local function GetPageDB()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, Runtime:GetDefaults())
    ApplyDefaults(db, Runtime:GetDefaults())
    return db
end

local function CopyRuntimeDBToPageDB()
    local runtimeDB = Runtime:GetDB()
    local pageDB = GetPageDB()
    for k in pairs(pageDB) do
        pageDB[k] = nil
    end
    ApplyDefaults(pageDB, runtimeDB)
    pageDB.pullCountdownEnabled      = runtimeDB.pullCountdownEnabled ~= false
    pageDB.pullCountdownVoiceEnabled = runtimeDB.pullCountdownVoiceEnabled == true
    for i = 1, MAX_COUNTDOWN_DIGIT do
        pageDB["digitEnabled" .. tostring(i)] = runtimeDB.digits and runtimeDB.digits[i] and runtimeDB.digits[i].enabled == true or false
        pageDB["digitSource" .. tostring(i)] = NormalizeDigitSource(runtimeDB.digits and runtimeDB.digits[i] and runtimeDB.digits[i].sourceType or "pack")
        pageDB["digitLSM" .. tostring(i)] = tostring(runtimeDB.digits and runtimeDB.digits[i] and runtimeDB.digits[i].customLSM or "")
    end
end

local function SyncPageDBToRuntimeDB()
    local pageDB = GetPageDB()
    local runtimeDB = Runtime:GetDB()
    runtimeDB.pullCountdownEnabled      = (pageDB.pullCountdownEnabled ~= false)
    runtimeDB.pullCountdownVoiceEnabled = (pageDB.pullCountdownVoiceEnabled == true)
    runtimeDB.digits = type(runtimeDB.digits) == "table" and runtimeDB.digits or {}
    for i = 1, MAX_COUNTDOWN_DIGIT do
        runtimeDB.digits[i] = type(runtimeDB.digits[i]) == "table" and runtimeDB.digits[i] or {}
        runtimeDB.digits[i].enabled = (pageDB["digitEnabled" .. tostring(i)] == true)
        runtimeDB.digits[i].sourceType = NormalizeDigitSource(pageDB["digitSource" .. tostring(i)])
        runtimeDB.digits[i].customLSM = tostring(pageDB["digitLSM" .. tostring(i)] or "")
    end
end

local function CreateOwner()
    local pageDB, digits = GetPageDB(), {}
    for i = 1, MAX_COUNTDOWN_DIGIT do
        digits[i] = { digit = i }
    end
    local owner = {
        binding = { moduleKey = MODULE_KEY, config = pageDB },
        controls = {}, sources = {}, texts = {}, predicates = {}, actions = {},
    }
    owner.sources.digits = function() return digits end
    owner.texts.digitNumber = function(scope)
        return string.format(L["数字 %d"], scope.item.digit)
    end
    owner.predicates.usesLSM = function(scope)
        return NormalizeDigitSource(pageDB["digitSource" .. tostring(scope.item.digit)]) == "lsm"
    end
    owner.predicates.digitEnabled = function(scope)
        return pageDB["digitEnabled" .. tostring(scope.item.digit)] == true
    end
    local function DigitBinding(context, prefix)
        return EXUI:CreateSettingsV2Binding(MODULE_KEY, pageDB, prefix .. tostring(context.scope.item.digit))
    end
    local function DigitControl(prefix, spec)
        local adapter = EXUI:CreateSettingsV2Control(spec,
            function(context) return DigitBinding(context, prefix) end)
        local mount, layout = adapter.mount, adapter.layout
        adapter.mount = function(host, context)
            local widget = mount(host, context)
            EXUI:PrepareSettingsListControl(widget, {
                hideLabel = true, ordinaryControl = spec.controlType == "select",
                presentation = spec.controlType == "checkbox" and "switch" or nil,
            })
            return widget
        end
        adapter.measure = function(widget, context, width)
            widget:SetWidth(width)
            return widget:GetHeight()
        end
        adapter.layout = function(widget, context, width, height)
            layout(widget, context, width, height)
            EXUI:UpdateSettingsListControlLayout(widget, width)
        end
        return adapter
    end
    owner.controls.digitEnabled = DigitControl("digitEnabled", { controlType = "checkbox", label = "" })
    owner.controls.digitSource = DigitControl("digitSource", { controlType = "select", options = SOURCE_ITEMS })
    owner.controls.digitLSM = DigitControl("digitLSM", { controlType = "select", media = "sound" })
    local setLSMEnabled = owner.controls.digitLSM.setEnabled
    owner.controls.digitLSM.setEnabled = function(widget, context, enabled)
        setLSMEnabled(widget, context, enabled)
        widget:SetAlpha(enabled and 1 or 0.45)
    end
    owner.actions.previewDigit = function(context)
        ExwindTools:UpdateState(MODULE_KEY .. ".ButtonClicked", {
            key = "preview" .. tostring(context.scope.item.digit), ts = GetTime(),
        })
    end
    return owner
end

local function ReleaseSession()
    cardSession = nil
    if scrollChild then
        EXUI:ReleaseModuleSettingsPage(scrollChild)
        scrollChild:Hide()
    end
end

function Page:Render(contentFrame)
    if not contentFrame then
        return
    end

    CopyRuntimeDBToPageDB()
    renderTicket = renderTicket + 1
    local ticket = renderTicket

    if not scrollFrame then
        scrollFrame = EXUI:CreateScrollFrame(contentFrame, "ExBoss_CountdownVoiceSettingsScroll")
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)
        Page._scrollFrame = scrollFrame
        Page._scrollChild = scrollChild
        scrollFrame:HookScript("OnHide", function()
            renderTicket = renderTicket + 1
            ReleaseSession()
        end)
        scrollFrame:HookScript("OnSizeChanged", function()
            if scrollChild then scrollChild:SetWidth(math.max(1, scrollFrame:GetWidth() + 6)) end
        end)
    end

    scrollFrame:SetParent(contentFrame)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
    scrollFrame:SetVerticalScroll(0)
    ReleaseSession()
    scrollFrame:Show()

    C_Timer.After(0, function()
        if ticket ~= renderTicket or not (scrollFrame and scrollFrame:IsShown() and scrollChild) then
            return
        end
        local width = contentFrame:GetWidth()
        if width < 100 then
            width = 820
        end
        scrollChild:SetWidth(width - 16)
        scrollChild:SetHeight(1)
        scrollChild:SetParent(scrollFrame)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", 0, 0)
        local owner = CreateOwner()
        cardSession = EXUI:MountModuleSettingsDeclarationV2(scrollChild, MODULE_KEY, owner,
            L["语音设置"], L["开怪倒数与数字语音。"], scrollFrame)
        EXUI.ActivePageFrame = scrollChild
        EXUI.CurrentModule = MODULE_KEY
        if ticket == renderTicket and scrollFrame:IsShown() then
            scrollChild:Show()
        end
    end)
end

function Page:Hide()
    renderTicket = renderTicket + 1
    if scrollFrame then
        scrollFrame:Hide()
    end
end

if not Page._eventsRegistered then
    ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY .. "_btn", function(info)
        local key = type(info) == "table" and tostring(info.key or "") or ""
        local digit = tonumber(key:match("^preview(%d)$"))
        if digit then
            Runtime:PreviewDigit(digit)
        end
    end)
    Page._eventsRegistered = true
end

local function RefreshActiveSurfaces()
    SyncPageDBToRuntimeDB()
    local page = EXUI:GetModulePage(MODULE_KEY, scrollChild)
    if page then page:Refresh() end
end

EXUI:RegisterSettingsPageV2(MODULE_KEY, LAYOUT)

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})
