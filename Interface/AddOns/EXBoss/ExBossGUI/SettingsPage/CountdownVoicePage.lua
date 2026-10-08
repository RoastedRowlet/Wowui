---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

local Grid = _G.ExwindGrid
if not Grid then return end

local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.CountdownVoicePage = ExBoss.UI.Panel.CountdownVoicePage or {}
local Page = ExBoss.UI.Panel.CountdownVoicePage

local Runtime = ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown
if not Runtime then return end

local MODULE_KEY = "ExBoss.CountdownVoiceSettings"
local GRID_COLS = 200
local MAX_COUNTDOWN_DIGIT = tonumber(Runtime.GetMaxCountdownDigit and Runtime:GetMaxCountdownDigit()) or 5

local SOURCE_ITEMS = {
    { value = "pack", label = L["语音包"] },
    { value = "lsm", label = L["LSM音效"] },
}

-- [卡片/Grid 迁移边界：数字语音]
-- 允许：只按共享规范调整开怪倒数与数字语音两组的 x/y/w/h、外层卡片和可见高度。
-- 禁止：修改 digit key 生成规则、数字业务顺序、Runtime↔页面 DB 投影、试听回调或来源显隐逻辑。
local LAYOUT = {
    version = 1,
    title = L["语音设置"],
    sections = {
        { kind = "settings", id = "pull-countdown", title = L["开怪倒数"], items = {
            { key = "pullCountdownEnabled", type = "switch", label = L["启用开怪倒数"] },
            { key = "pullCountdownVoiceEnabled", type = "switch", label = L["为开怪倒数播放语音"] },
        } },
        { kind = "table", id = "digit-voice", title = L["数字语音"],
            columns = {
                { title = L["启用"] }, { title = L["数字"] }, { title = L["来源"] },
                { title = L["音效选择"] }, { title = L["试听"] },
            },
            supportsAdd = false, records = {},
        },
    },
}

local root
local scrollFrame
local scrollChild
local cardSession
local renderTicket = 0

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

local function BuildLayout()
    -- 保留原数字顺序、key和原工厂语义；每行只声明一次。
    local layout = DeepCopy(LAYOUT)
    local rows = layout.sections[2].records
    for i = 1, MAX_COUNTDOWN_DIGIT do
        rows[#rows + 1] = { cells = {
            { key = "digitEnabled" .. tostring(i), type = "switch", label = string.format(L["数字 %d"], i) },
            { text = string.format(L["数字 %d"], i) },
            { key = "digitSource" .. tostring(i), type = "select", label = L["来源"], options = SOURCE_ITEMS },
            { key = "digitLSM" .. tostring(i), type = "select", media = "sound", label = L["LSM音效"] },
            { key = "preview" .. tostring(i), type = "button", label = L["试听"] },
        } }
    end
    return layout
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

local function GetEditorWidgets()
    -- state.widgets 的 digit* key 是显隐与试听的稳定入口，迁移后必须保留 key 查找语义。
    local widgets = {}
    if not (scrollChild and Grid.FindMountedWidget) then
        return widgets
    end
    for i = 1, MAX_COUNTDOWN_DIGIT do
        local suffix = tostring(i)
        widgets["digitEnabled" .. suffix] = Grid:FindMountedWidget(scrollChild, "digitEnabled" .. suffix)
        widgets["digitSource" .. suffix] = Grid:FindMountedWidget(scrollChild, "digitSource" .. suffix)
        widgets["digitLSM" .. suffix] = Grid:FindMountedWidget(scrollChild, "digitLSM" .. suffix)
        widgets["preview" .. suffix] = Grid:FindMountedWidget(scrollChild, "preview" .. suffix)
    end
    return widgets
end

local function SetWidgetShown(widget, shown)
    if not widget then return end
    if shown then widget:Show() else widget:Hide() end
end

local function SetWidgetUsable(widget, usable)
    if not widget then return end
    local isInput = widget._gridType == "GridInput" or (widget.IsObjectType and widget:IsObjectType("EditBox"))
    if isInput then
        if widget.Enable then widget:Enable() end
        if widget.EnableMouse then widget:EnableMouse(true) end
    elseif widget.SetEnabled then
        widget:SetEnabled(usable == true)
    elseif widget.Enable and widget.Disable then
        if usable then widget:Enable() else widget:Disable() end
    end
    widget:SetAlpha(usable and 1 or 0.45)
    if widget._exLabel then
        widget._exLabel:SetAlpha(usable and 1 or 0.45)
    elseif widget.labelText then
        widget.labelText:SetAlpha(usable and 1 or 0.45)
    end
end

local function RefreshDynamicWidgets()
    local widgets = GetEditorWidgets()
    local pageDB = GetPageDB()
    for i = 1, MAX_COUNTDOWN_DIGIT do
        local source = NormalizeDigitSource(pageDB["digitSource" .. tostring(i)])
        local lsmWidget = widgets["digitLSM" .. tostring(i)]
        local enabled = pageDB["digitEnabled" .. tostring(i)] == true
        SetWidgetShown(lsmWidget, source == "lsm")
        SetWidgetUsable(lsmWidget, enabled and source == "lsm")
    end
end

local function RegisterLayout()
    ExwindTools:RegisterModuleLayout(MODULE_KEY, BuildLayout())
end

-- [混合函数边界] Page:Render 内只可调整 Scroll/Grid 几何；投影复制、RegisterModuleLayout、WatchState 与 ActivePage 注册禁止修改。
-- Page:Hide 只隐藏 ScrollFrame；从设置目录离开时 ActivePageFrame/CurrentModule 由 GlobalSettingsPage 清理，不能误写为本页 OnHide 释放。
function Page:Render(contentFrame)
    if not contentFrame then
        return
    end

    CopyRuntimeDBToPageDB()
    RegisterLayout()
    renderTicket = renderTicket + 1
    local ticket = renderTicket

    if not scrollFrame then
        scrollFrame = CreateFrame("ScrollFrame", "ExBoss_CountdownVoiceSettingsScroll", contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame)
        end
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)
        Page._scrollFrame = scrollFrame
        Page._scrollChild = scrollChild
    end

    scrollFrame:SetParent(contentFrame)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
    scrollFrame:SetVerticalScroll(0)
    -- Page:Hide retains the mounted GUI session. Do not expose that previous
    -- lease for one frame while the deferred width pass is still rebuilding it.
    scrollChild:Hide()
    if cardSession and type(cardSession.Release) == "function" then
        cardSession:Release()
        cardSession = nil
    end
    scrollFrame:Show()

    C_Timer.After(0, function()
        if ticket ~= renderTicket or not (scrollFrame and scrollFrame:IsShown() and scrollChild) then
            return
        end
        local width = contentFrame:GetWidth()
        if width < 100 then
            width = 820
        end
        local mounted, failure = pcall(function()
            scrollChild:SetWidth(width - 16)
            scrollChild:SetHeight(980)
            scrollChild:SetParent(scrollFrame)
            scrollChild:ClearAllPoints()
            scrollChild:SetPoint("TOPLEFT", 0, 0)
            if ExwindTools.UI then
                ExwindTools.UI.ActivePageFrame = scrollChild
                ExwindTools.UI.CurrentModule = MODULE_KEY
            end
            cardSession = Grid:MountCards(scrollChild, BuildLayout(), {
                pageId = MODULE_KEY,
                regionId = "countdown-voice",
                config = GetPageDB(),
                moduleKey = MODULE_KEY,
                scrollFrame = scrollFrame,
            })
            RefreshDynamicWidgets()
        end)
        if ticket == renderTicket and scrollFrame:IsShown() then
            scrollChild:Show()
        end
        if not mounted then error(failure, 0) end
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
    RefreshDynamicWidgets()
end

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})
