---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- FlashTextMedium display migration.
-- The module has one TextCollection renderer.  It accepts ordinary central
-- notices, native Duration notices, and HealthThreshold's curve-coloured rows.

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

ExBoss.UI.FlashTextMedium = ExBoss.UI.FlashTextMedium or {}
local FlashText = ExBoss.UI.FlashTextMedium
local MODULE_KEY = "ExBoss.FlashTextMedium"
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local anchorController, anchorFrame, runtimeCollection, worldCollection, panelSurface, panelPreview, panelDock
-- 血量阈值沿用原版独立 healthFrame：不能进入中央文本的 Collection。
-- 该 Collection 负责普通公告/倒数，二者的生命周期与可见性完全不同。
local healthFrame, healthTexts, healthEntries = nil, {}, {}
local worldEditing, entries, sequence, activeFlashID = false, {}, 0, nil
local fadeFrame, fadeDirection, fadeElapsed = nil, 0, 0
local FADE_IN, FADE_OUT, BODY_WIDTH, BODY_HEIGHT = .16, .35, 520, 84

local function DB() return ExwindTools:GetModuleDB(MODULE_KEY) end
local function SafeNum(value, fallback) return tonumber(value) or fallback end
local EX_DEFAULTS = {
    module = { enabled = true, anchorX_1205 = 37.989440917969, anchorY_1205 = 172.64614868164, attachToCustom = false, customAttachTarget = "", flashDuration = 1.5 },
    font_text = {
        font = "默认", size = 35, r = 1, g = 1, b = 1, a = 1, enabled = true, autoWidth = true, fixedWidth = 0, maxWidth = 0,
        justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE", shadow = true, shadowColorR = 0, shadowColorG = 0,
        shadowColorB = 0, shadowColorA = 1, shadowX = 2, shadowY = -2, rotation = 0, gradientEnabled = false,
        gradientStart = 0, gradientLength = 0, x = -27.989409579595, y = -3.1988695432753,
    },
}
local FONT_FIELDS = { "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth", "justifyH", "justifyV",
    "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA", "shadowX", "shadowY", "rotation",
    "gradientEnabled", "gradientStart", "gradientLength", "x", "y" }
ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, {
    { group = "module", root = true, fields = { "enabled", "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget", "flashDuration" } },
    { group = "font_text", fields = FONT_FIELDS },
})

local ANCHOR_SCHEMA = {
    moduleKey = MODULE_KEY, frameName = "ExBoss_FlashTextMediumAnchor", title = L["文字公告(中)"], getDB = DB,
    offsetXKey = "anchorX_1205", offsetYKey = "anchorY_1205", defaultOffsetX = EX_DEFAULTS.module.anchorX_1205, defaultOffsetY = EX_DEFAULTS.module.anchorY_1205,
    syncWidgets = { "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget" }, attachEnabledKey = "attachToCustom", attachTargetKey = "customAttachTarget",
    widgetRanges = { anchorX_1205 = { min = -1000, max = 1000, step = 5 }, anchorY_1205 = { min = -600, max = 600, step = 5 } },
    initialWidth = BODY_WIDTH, initialHeight = BODY_HEIGHT, clampedToScreen = false, frameStrata = "DIALOG", anchorPoint = "CENTER", relativePoint = "CENTER",
    onCreateFrame = function(_, frame) frame:Hide() end,
}
local function EnsureAnchorController()
    if not anchorController then anchorController, FlashText.StandardAnchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA) end
    return anchorController
end
function FlashText:GetStandardAnchorGroupOptions() EnsureAnchorController(); return FlashText.StandardAnchorGroupOptions end

local INTERACTION_SCHEMA = { announcement = { guiKey = "font_text", movable = true, tooltip = L["文字公告(中)"], position = { x = "font_text.x", y = "font_text.y" }, anchor = { point = "CENTER", relativePoint = "CENTER" } } }
local CONFIG_SCHEMA_PATHS = { ["flashDuration"] = true, ["font_text.size"] = true, ["font_text.x"] = true, ["font_text.y"] = true,
    ["font_text.shadowX"] = true, ["font_text.shadowY"] = true, ["font_text.fixedWidth"] = true, ["font_text.maxWidth"] = true,
    ["font_text.gradientStart"] = true, ["font_text.gradientLength"] = true, ["font_text.rotation"] = true, ["font_text.autoWidth"] = true }
FlashText.StandardSliderContract = { groupPaths = { moduleCommon = "", font_text = "font_text" } }

local function CopyUnboundedStyle(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    copy.autoWidth, copy.fixedWidth, copy.maxWidth, copy.unboundedWidth, copy.wordWrap = true, 0, 0, true, false
    copy.justifyH, copy.justifyV = "CENTER", "MIDDLE"
    return copy
end
local function ResolveHealthColor(record, font)
    if not (_G.C_CurveUtil and _G.CreateColor and _G.UnitHealthPercent and type(record) == "table" and UnitExists(record.unit)) then return nil end
    local low, high = math.max(0, SafeNum(record.min, 0) / 100), math.min(1, SafeNum(record.max, 0) / 100)
    if high <= low then return nil end
    local hidden = CreateColor(SafeNum(font.r, 1), SafeNum(font.g, 1), SafeNum(font.b, 1), 0)
    local shown = CreateColor(SafeNum(font.r, 1), SafeNum(font.g, 1), SafeNum(font.b, 1), SafeNum(font.a, 1))
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetPoints({ { x = 0, y = hidden }, { x = low, y = hidden }, { x = low, y = shown }, { x = high, y = shown }, { x = high, y = hidden }, { x = 1, y = hidden } })
    local color = UnitHealthPercent(record.unit, true, curve)
    if color and color.GetRGBA then local r, g, b, a = color:GetRGBA(); return { r = r, g = g, b = b, a = a } end
    return nil
end
local function BuildPresentation(record)
    local font = DB().font_text or {}
    return {
        style = CopyUnboundedStyle(font), text = record.text or "", secretText = record.secretText == true, durationObject = record.durationObject,
        durationOptions = record.durationOptions, color = record.color, unboundedWidth = true, panelAnchorLocked = false,
        anchor = { point = "CENTER", relativePoint = "CENTER", x = SafeNum(font.x, 0), y = SafeNum(font.y, 0) },
        -- Geometry is deliberately constant for a collection: it is not a text width cap.
        declaredBounds = { left = -BODY_WIDTH * .5, right = BODY_WIDTH * .5, bottom = -BODY_HEIGHT * .5, top = BODY_HEIGHT * .5 },
        semanticSlot = "announcement", interaction = EXUI:BuildStandardPreviewInteraction("Text", DB(), INTERACTION_SCHEMA),
    }
end
local function BuildLayout(count)
    -- 血量阈值依靠颜色曲线决定哪一行可见；所有行必须占用同一中央位置，
    -- 不能因规则表序号向上累积偏移。
    return { mode = "SEMANTIC", direction = "OVERLAY", spacing = 0, maxVisible = math.max(1, tonumber(count) or #entries) }
end
local function ApplyHealthFont(fs, font)
    local EXDB = _G.EXDB
    if EXDB and type(EXDB.ApplyFont) == "function" then
        EXDB:ApplyFont(fs, font or {})
    end
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
end
local function EnsureHealthText(index)
    if not healthFrame then return nil end
    local fs = healthTexts[index]
    if fs then return fs end
    -- 与 GitHub 原版一致：血量行是 healthFrame 的直接 FontString，不走 TextWidget。
    fs = healthFrame:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    healthTexts[index] = fs
    return fs
end
local function HideHealthTexts(fromIndex)
    for index = fromIndex, #healthTexts do
        local fs = healthTexts[index]
        if fs then
            fs:SetText("")
            fs:SetTextColor(1, 1, 1, 0)
        end
    end
end
local function HasHealthEntries()
    return #healthEntries > 0
end
local function RenderHealthEntries()
    if not healthFrame then return end
    local font = DB().font_text or {}
    for index, record in ipairs(healthEntries) do
        local fs = EnsureHealthText(index)
        if fs then
            ApplyHealthFont(fs, font)
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", healthFrame, "CENTER", 0, 0)
            fs:SetText(tostring(record.text or ""))
            fs:SetTextColor(1, 1, 1, 0)
            local color = ResolveHealthColor(record, font)
            if color then fs:SetTextColor(color.r, color.g, color.b, color.a or 1) end
        end
    end
    HideHealthTexts(#healthEntries + 1)
    if #healthEntries > 0 then healthFrame:Show() else healthFrame:Hide() end
end
local function RenderCollection(collection, records)
    if not collection then return end
    local items = {}
    for _, record in ipairs(records or {}) do
        local item = collection:AcquireItem(record.id)
        collection:ApplyItem(item, BuildPresentation(record))
        items[#items + 1] = item
    end
    collection:SetItems(items, BuildLayout(#records))
end
local function BuildPreviewEntries() return { { id = "flashtextmedium-preview", text = L["文字公告预览 5.0"] } } end

local function EnsureRuntime()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure(); anchorFrame:SetSize(BODY_WIDTH, BODY_HEIGHT)
    runtimeCollection = EXUI:CreateTextCollection(anchorFrame, "runtime", MODULE_KEY)
    healthFrame = CreateFrame("Frame", nil, anchorFrame)
    healthFrame:SetAllPoints(anchorFrame)
    healthFrame:SetFrameStrata("DIALOG")
    healthFrame:Hide()
    fadeFrame = CreateFrame("Frame", nil, anchorFrame); fadeFrame:Hide()
    fadeFrame:SetScript("OnUpdate", function(_, elapsed)
        if fadeDirection == 0 or not activeFlashID or not runtimeCollection then return end
        fadeElapsed = fadeElapsed + elapsed
        local duration = fadeDirection > 0 and FADE_IN or FADE_OUT
        local alpha = fadeDirection > 0 and math.min(1, fadeElapsed / duration) or math.max(0, 1 - fadeElapsed / duration)
        runtimeCollection:SetItemAlpha(activeFlashID, alpha)
        if alpha >= 1 and fadeDirection > 0 then
            fadeDirection, fadeElapsed = 0, 0; fadeFrame:Hide()
            local hold = math.max(.05, SafeNum(DB()._overrideDuration, SafeNum(DB().flashDuration, 1.5)) - FADE_IN - FADE_OUT); DB()._overrideDuration = nil
            C_Timer.After(hold, function() if activeFlashID and fadeFrame then fadeDirection, fadeElapsed = -1, 0; fadeFrame:Show() end end)
        elseif alpha <= 0 and fadeDirection < 0 then
            for index = #entries, 1, -1 do if entries[index].id == activeFlashID then table.remove(entries, index) end end
            activeFlashID, fadeDirection, fadeElapsed = nil, 0, 0; RenderCollection(runtimeCollection, entries)
            if #entries == 0 and not HasHealthEntries() and not worldEditing then anchorFrame:Hide() end; fadeFrame:Hide()
        end
    end)
end
local function ReplaceEntries(nextEntries, activeID)
    entries, activeFlashID = nextEntries, activeID; EnsureRuntime(); anchorFrame:Show(); RenderCollection(runtimeCollection, entries)
end

local function BuildPanelPresentation(_, mode)
    if mode ~= "panel" then error("FlashTextMedium only supports panel presentation", 2) end
    local rows = {}; for _, record in ipairs(BuildPreviewEntries()) do rows[#rows + 1] = { itemID = record.id, presentation = BuildPresentation(record) } end
    return { entries = rows, layout = { mode = "SEMANTIC", direction = "UP", spacing = 0, maxVisible = 1 } }
end
local function EnsurePanelSurface()
    if not panelSurface then panelSurface = EXUI:CreateStandardPreviewSurface({ moduleKey = MODULE_KEY, kind = "text", buildPresentation = BuildPanelPresentation,
        interactionSchema = INTERACTION_SCHEMA, requiredPositionGuiKeys = { "font_text" } }) end
    return panelSurface
end
local function ResizePanelDock() if panelDock and panelPreview then local _, height = panelPreview:GetBounds(); panelDock:SetHeight(math.max(160, (height or 0) + 28)) end end
function FlashText:ShowPanelPreview(dock) if not dock then return end; panelDock = dock; panelPreview = EnsurePanelSurface():Render({ dock = dock, ruleKey = MODULE_KEY, state = true }); ResizePanelDock() end
function FlashText:ReleasePanelPreview() if panelSurface then panelSurface:Release() end; panelPreview, panelDock = nil, nil end
function FlashText:RenderWorld(host)
    if not host then return end
    if worldCollection then worldCollection:Release() end
    EnsureRuntime(); worldEditing = true; runtimeCollection:SetItems({}, BuildLayout())
    if healthFrame then healthFrame:Hide() end
    -- The shared runtime anchor is normally hidden without active notices.
    -- The world-edit collection uses the same parent and needs it visible.
    anchorFrame:Show()
    worldCollection = EXUI:CreateTextCollection(host, "world", MODULE_KEY); RenderCollection(worldCollection, BuildPreviewEntries())
end
function FlashText:GetWorldBounds() return worldCollection and worldCollection:GetWorldBounds() or nil end
function FlashText:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    if runtimeCollection then RenderCollection(runtimeCollection, entries) end
    RenderHealthEntries()
    if #entries == 0 and not HasHealthEntries() and anchorFrame then anchorFrame:Hide() end
end

function FlashText:GetDB() return DB() end
function FlashText:Show(payload, text, duration)
    local db = DB(); if db.enabled == false then return end
    local displayText, displayDuration, color = text, duration, nil
    if type(payload) == "table" and text == nil then displayText, displayDuration, color = payload.text, payload.duration, payload.color
    elseif type(payload) == "table" then color = payload.flashTextColor or payload.color end
    sequence = sequence + 1; local id = "flash:" .. sequence; ReplaceEntries({ { id = id, text = tostring(displayText or ""), color = color } }, id)
    if type(payload) == "table" and (payload.noAnimation == true or payload.instant == true) then
        runtimeCollection:SetItemAlpha(id, 1); C_Timer.After(math.max(.05, SafeNum(displayDuration, SafeNum(db.flashDuration, 1.5))), function() if activeFlashID == id then self:Stop() end end); return
    end
    db._overrideDuration = displayDuration; fadeDirection, fadeElapsed = 1, 0; runtimeCollection:SetItemAlpha(id, 0); fadeFrame:Show()
end
function FlashText:ShowCountdown(payload)
    payload = type(payload) == "table" and payload or {}; if not payload.durationObject then error("FlashTextMedium countdown requires a native Duration Object", 2) end
    fadeDirection, fadeElapsed = 0, 0; if fadeFrame then fadeFrame:Hide() end
    sequence = sequence + 1; local id = "countdown:" .. sequence
    ReplaceEntries({ { id = id, durationObject = payload.durationObject, durationOptions = { formatString = tostring(payload.label or "") .. "{}" .. tostring(payload.suffix or "") }, color = payload.color } }, id)
    runtimeCollection:SetItemAlpha(id, 1)
end
function FlashText:ShowHealthEntries(source)
    local db = DB(); if db.enabled == false or type(source) ~= "table" then return self:ClearHealthEntries() end
    EnsureRuntime()
    healthEntries = source
    anchorFrame:Show()
    if not worldEditing then RenderHealthEntries() end
end
function FlashText:ClearHealthEntries()
    healthEntries = {}
    HideHealthTexts(1)
    if healthFrame then healthFrame:Hide() end
    if #entries == 0 and anchorFrame and not worldEditing then anchorFrame:Hide() end
end
function FlashText:Stop()
    entries, activeFlashID, fadeDirection, fadeElapsed = {}, nil, 0, 0
    if fadeFrame then fadeFrame:Hide() end
    if runtimeCollection then runtimeCollection:SetItems({}, BuildLayout(0)) end
    self:ClearHealthEntries()
    if anchorFrame and not worldEditing then anchorFrame:Hide() end
end
function FlashText:StopCountdown() self:Stop() end
function FlashText:StartFramePicker() return EnsureAnchorController():StartFramePicker() end

ExwindTools.UI:RegisterEditableModule({ addon = "EXBoss", key = "flashtextmedium", name = L["文字公告(中)"], settingsPage = "flashtextmedium", appearanceProfile = "basicText",
    orientation = "HORIZONTAL", worldAnchorMode = "semantic-root", editOverlay = { titleFontSize = 30 }, getAnchor = function() EnsureRuntime(); return anchorFrame end,
    GetWorldBounds = function() return FlashText:GetWorldBounds() end, RenderWorld = function(host) return FlashText:RenderWorld(host) end, ReleaseWorld = function() return FlashText:ReleaseWorld() end })

for _, path in ipairs({ "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget" }) do CONFIG_SCHEMA_PATHS[path] = true end
local function ReapplyCollection(collection, records)
    if not collection then return end
    local byID = {}; for _, record in ipairs(records or {}) do byID[record.id] = record end
    collection:ReapplyCurrentItems(function(presentation, item) local record = byID[item.id]; if record then for key in pairs(presentation) do presentation[key] = nil end; for key, value in pairs(BuildPresentation(record)) do presentation[key] = value end end end)
    collection:SetItems(collection.currentItems, BuildLayout(#records))
end
local function ReapplyAll()
    if panelSurface and type(panelSurface.ReapplyPanelPresentation) == "function" then panelSurface:ReapplyPanelPresentation() end
    if panelPreview and type(panelPreview.ReapplyPanelPresentation) == "function" then panelPreview:ReapplyPanelPresentation() end
    ReapplyCollection(worldCollection, BuildPreviewEntries()); ReapplyCollection(runtimeCollection, entries)
    if not worldEditing then RenderHealthEntries() end
end
function FlashText:RefreshVisuals() EnsureRuntime(); EnsureAnchorController():ApplyPosition(); ReapplyAll() end
local STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({ moduleKey = MODULE_KEY, getConfig = DB, reapplyExisting = ReapplyAll, schemaPaths = CONFIG_SCHEMA_PATHS })
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = function() return STANDARD_CONFIG_BINDING.reapplyExisting() end })
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function() C_Timer.After(.5, function() EnsureRuntime(); EnsureAnchorController():ApplyPosition() end) end)
