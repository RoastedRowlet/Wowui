---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- 中央文字公告（中）：runtime / world edit / panel 均只消费同一 TextPresentation。
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

ExBoss.UI.FlashTextMedium = ExBoss.UI.FlashTextMedium or {}
local FlashText = ExBoss.UI.FlashTextMedium
local MODULE_KEY = "ExBoss.FlashTextMedium"
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

-- 唯一可编辑默认值真源。runtime、panel、world 与 Page 都只读取同一 ModuleDB；
-- 禁止在页面或 renderer 保留第二份 fallback/defaults。
local EX_DEFAULTS = {
    module = {
        enabled = true, anchorX_1205 = 37.989440917969, anchorY_1205 = 172.64614868164,
        attachToCustom = false, customAttachTarget = "", flashDuration = 1.5,
    },
    font_text = {
        font = "默认", size = 35, r = 1, g = 1, b = 1, a = 1, enabled = true,
        autoWidth = true, fixedWidth = 0, maxWidth = 0, justifyH = "CENTER",
        justifyV = "MIDDLE", outline = "OUTLINE", shadow = true,
        shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        shadowX = 2, shadowY = -2, rotation = 0, gradientEnabled = false,
        gradientStart = 0, gradientLength = 0, x = -27.989409579595, y = -3.1988695432753,
    },
}

local MODULE_FIELDS = { "enabled", "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget", "flashDuration" }
local FONT_FIELDS = {
    "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
    "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB",
    "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart",
    "gradientLength", "x", "y",
}
local DEFAULT_SCHEMA = {
    { group = "module", root = true, fields = MODULE_FIELDS },
    { group = "font_text", fields = FONT_FIELDS },
}
ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

local INTERACTION_SCHEMA = {
    announcement = {
        guiKey = "font_text", movable = true, tooltip = L["文字公告(中)"],
        position = { x = "font_text.x", y = "font_text.y" },
        anchor = { point = "CENTER", relativePoint = "CENTER" },
    },
}

local CONFIG_SCHEMA_PATHS = {
    ["flashDuration"] = true,
    ["font_text.size"] = true, ["font_text.x"] = true, ["font_text.y"] = true,
    ["font_text.shadowX"] = true, ["font_text.shadowY"] = true,
    ["font_text.fixedWidth"] = true, ["font_text.maxWidth"] = true,
    ["font_text.gradientStart"] = true, ["font_text.gradientLength"] = true,
    ["font_text.rotation"] = true, ["font_text.autoWidth"] = true,
}

FlashText.StandardSliderContract = {
    groupPaths = {
        moduleCommon = "",
        font_text = "font_text",
    },
}

local function BuildStandardTextInteraction(db)
    return EXUI:BuildStandardPreviewInteraction("Text", db, INTERACTION_SCHEMA)
end

local anchorController, anchorFrame, runtimeCollection, worldCollection
local panelPreview, panelDock, panelSurface, updateFrame
local worldEditing, fadeDirection, fadeElapsed, activeFlashID = false, 0, 0, nil
local entries, sequence = {}, 0
local FADE_IN_TIME, FADE_OUT_TIME = 0.16, 0.35
local ANCHOR_WIDTH, ANCHOR_HEIGHT, PANEL_MIN_HEIGHT = 520, 84, 160

local function DB()
    return ExwindTools:GetModuleDB(MODULE_KEY)
end

-- 整体锚点的唯一声明。runtime AnchorController 与 Page anchorgroup 都只能从此处
-- 取得字段、默认位置与 FramePicker；不得在 Page 复制第二份映射。
local ANCHOR_SCHEMA = {
    moduleKey = MODULE_KEY,
    frameName = "ExBoss_FlashTextMediumAnchor",
    title = L["文字公告(中)"],
    getDB = DB,
    offsetXKey = "anchorX_1205",
    offsetYKey = "anchorY_1205",
    defaultOffsetX = 37.989440917969,
    defaultOffsetY = 172.64614868164,
    syncWidgets = { "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget" },
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    widgetRanges = {
        anchorX_1205 = { min = -1000, max = 1000, step = 5 },
        anchorY_1205 = { min = -600, max = 600, step = 5 },
    },
    initialWidth = ANCHOR_WIDTH,
    initialHeight = ANCHOR_HEIGHT,
    clampedToScreen = false,
    frameStrata = "DIALOG",
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    onCreateFrame = function(_, frame) frame:Hide() end,
}

local function SafeNum(value, fallback) return tonumber(value) or fallback end

local function ResolveHealthColor(entry, font)
    if not (_G.C_CurveUtil and _G.CreateColor and _G.UnitHealthPercent and type(entry) == "table" and UnitExists(entry.unit)) then return nil end
    local low, high = math.max(0, SafeNum(entry.min, 0) / 100), math.min(1, SafeNum(entry.max, 0) / 100)
    if high <= low then return nil end
    local hidden = CreateColor(SafeNum(font.r, 1), SafeNum(font.g, 1), SafeNum(font.b, 1), 0)
    local shown = CreateColor(SafeNum(font.r, 1), SafeNum(font.g, 1), SafeNum(font.b, 1), SafeNum(font.a, 1))
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetPoints({ { x = 0, y = hidden }, { x = low, y = hidden }, { x = low, y = shown }, { x = high, y = shown }, { x = high, y = hidden }, { x = 1, y = hidden } })
    local color = UnitHealthPercent(entry.unit, true, curve)
    if color and color.GetRGBA then
        local r, g, b, a = color:GetRGBA()
        return { r = r, g = g, b = b, a = a }
    end
    return nil
end

local function CopyStyle(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    copy.justifyH, copy.justifyV = "CENTER", "MIDDLE"
    -- 中央公告是单纯文本，不允许 ModuleDB 的旧宽度字段、页面控件或任一宿主
    -- 把它截断、压窄或强制换行。底层 TextWidget 亦以此标记跳过所有宽度限制。
    copy.autoWidth, copy.fixedWidth, copy.maxWidth, copy.unboundedWidth = true, 0, 0, true
    copy.wordWrap = false
    return copy
end

local function TextBounds(db)
    local font = db.font_text or {}
    -- 这是 Secret/Duration 无法测量时的交互几何兜底，不是视觉宽度；普通文本
    -- 会在 TextCollection 中以 FontString 实际宽度替换它。
    return 1, math.max(1, SafeNum(font.size, 35) * 1.55)
end

local function EnsureAnchorController()
    if anchorController then return anchorController end
    anchorController, FlashText.StandardAnchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)
    return anchorController
end

function FlashText:GetStandardAnchorGroupOptions()
    EnsureAnchorController()
    return FlashText.StandardAnchorGroupOptions
end

local function BuildPresentation(entry, db)
    local width, height = TextBounds(db)
    local font = db.font_text or {}
    return {
        style = CopyStyle(font), text = entry.text or "", secretText = entry.secretText == true,
        durationObject = entry.durationObject,
        durationOptions = entry.durationOptions,
        color = entry.color,
        unboundedWidth = true,
        anchor = { point = "CENTER", relativePoint = "CENTER", x = SafeNum(font.x, 0), y = SafeNum(font.y, 0) },
        declaredBounds = { left = -width * 0.5, right = width * 0.5, bottom = -height * 0.5, top = height * 0.5 },
        semanticSlot = "announcement",
        interaction = BuildStandardTextInteraction(db),
    }
end

local function RenderCollection(collection, source, db)
    if not collection then return end
    local items = {}
    for _, entry in ipairs(source or {}) do
        local item = collection:AcquireItem(entry.id)
        collection:ApplyItem(item, BuildPresentation(entry, db))
        items[#items + 1] = item
    end
    collection:SetItems(items, { mode = "SEMANTIC", direction = "UP", spacing = 0, maxVisible = math.max(1, #items) })
end

local function BuildPreviewEntries()
    return { { id = "flashtextmedium-preview", text = L["文字公告预览 5.0"] } }
end

-- Panel 样本仍复用 BuildPresentation；StandardPreviewSurface 只持有 Core 的唯一
-- TextPanel session，不创建模块私有 Collection 或第二棵预览 Frame 树。
local function BuildPanelSurfacePresentation(_, mode)
    if mode ~= "panel" then error("FlashTextMedium panel surface only supports panel mode", 2) end
    local db, records = DB(), {}
    for _, entry in ipairs(BuildPreviewEntries()) do
        records[#records + 1] = {
            itemID = entry.id,
            presentation = BuildPresentation(entry, db),
        }
    end
    return {
        entries = records,
        layout = { mode = "SEMANTIC", direction = "UP", spacing = 0, maxVisible = 1 },
    }
end

local function EnsurePanelSurface()
    if panelSurface then return panelSurface end
    panelSurface = EXUI:CreateStandardPreviewSurface({
        moduleKey = MODULE_KEY,
        kind = "text",
        buildPresentation = BuildPanelSurfacePresentation,
        interactionSchema = INTERACTION_SCHEMA,
        requiredPositionGuiKeys = { "font_text" },
    })
    return panelSurface
end

local function ResizePanelDock(dock, session)
    if not dock or not session then return end
    local _, height = session:GetBounds()
    dock:SetHeight(math.max(PANEL_MIN_HEIGHT, (height or 0) + 28))
end

local function RenderPanelPreview()
    if not panelSurface or not panelDock then return end
    panelPreview = panelSurface:Render({
        dock = panelDock,
        ruleKey = MODULE_KEY,
        state = true,
    })
    ResizePanelDock(panelDock, panelPreview)
end

local function EnsureFrames()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(ANCHOR_WIDTH, ANCHOR_HEIGHT)
    runtimeCollection = ExwindTools.UI:CreateTextCollection(anchorFrame, "runtime", MODULE_KEY)
    updateFrame = CreateFrame("Frame", nil, anchorFrame)
    updateFrame:Hide()
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        if fadeDirection == 0 or not activeFlashID or not runtimeCollection then return end
        fadeElapsed = fadeElapsed + elapsed
        local duration = fadeDirection > 0 and FADE_IN_TIME or FADE_OUT_TIME
        local alpha = fadeDirection > 0 and math.min(1, fadeElapsed / duration) or math.max(0, 1 - fadeElapsed / duration)
        runtimeCollection:SetItemAlpha(activeFlashID, alpha)
        if alpha <= 0 and fadeDirection < 0 then
            for index = #entries, 1, -1 do if entries[index].id == activeFlashID then table.remove(entries, index) end end
            activeFlashID, fadeDirection, fadeElapsed = nil, 0, 0
            RenderCollection(runtimeCollection, entries, DB())
            if #entries == 0 and not worldEditing then anchorFrame:Hide() end
            updateFrame:Hide()
        elseif alpha >= 1 and fadeDirection > 0 then
            fadeDirection, fadeElapsed = 0, 0
            local durationValue = math.max(0.05, SafeNum(DB()._overrideDuration, SafeNum(DB().flashDuration, 1.5)))
            DB()._overrideDuration = nil
            C_Timer.After(math.max(0.05, durationValue - FADE_IN_TIME - FADE_OUT_TIME), function()
                if activeFlashID and updateFrame then fadeDirection, fadeElapsed = -1, 0; updateFrame:Show() end
            end)
            updateFrame:Hide()
        end
    end)
end

function FlashText:GetDB() return DB() end

function FlashText:ShowPanelPreview(dock)
    if not dock then return end
    local surface = EnsurePanelSurface()
    panelDock = dock
    panelPreview = surface:Render({
        dock = dock,
        ruleKey = MODULE_KEY,
        state = true,
    })
    ResizePanelDock(dock, panelPreview)
end

function FlashText:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelDock = nil
end

function FlashText:RenderWorld(host)
    if not host then return end
    if worldCollection then worldCollection:Release() end
    worldEditing = true
    if runtimeCollection then runtimeCollection:SetItems({}, { mode = "SEMANTIC", direction = "UP", spacing = 0, maxVisible = 1 }) end
    worldCollection = ExwindTools.UI:CreateTextCollection(host, "world", MODULE_KEY)
    RenderCollection(worldCollection, BuildPreviewEntries(), DB())
end

function FlashText:GetWorldBounds() return worldCollection and worldCollection:GetWorldBounds() or nil end

function FlashText:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    if runtimeCollection then RenderCollection(runtimeCollection, entries, DB()) end
end

local function ReplaceEntry(entry)
    entries = { entry }
    activeFlashID = entry.id
    EnsureFrames()
    anchorFrame:Show()
    RenderCollection(runtimeCollection, entries, DB())
end

function FlashText:Show(payload, text, duration)
    local db = DB()
    if db.enabled == false then return end
    local displayText, displayDuration, color = text, duration, nil
    if type(payload) == "table" and text == nil then displayText, displayDuration, color = payload.text, payload.duration, payload.color
    elseif type(payload) == "table" then color = payload.flashTextColor or payload.color end
    sequence = sequence + 1
    local id = "flash:" .. sequence
    ReplaceEntry({ id = id, text = tostring(displayText or ""), color = color })
    if type(payload) == "table" and (payload.noAnimation == true or payload.instant == true) then
        runtimeCollection:SetItemAlpha(id, 1)
        C_Timer.After(math.max(0.05, SafeNum(displayDuration, SafeNum(db.flashDuration, 1.5))), function()
            if activeFlashID == id then self:Stop() end
        end)
        return
    end
    db._overrideDuration = displayDuration
    fadeDirection, fadeElapsed = 1, 0
    runtimeCollection:SetItemAlpha(id, 0)
    updateFrame:Show()
end

function FlashText:ShowCountdown(payload)
    payload = type(payload) == "table" and payload or {}
    if not payload.durationObject then
        error("FlashTextMedium countdown requires a native Duration Object", 2)
    end
    local label = tostring(payload.label or "")
    local suffix = tostring(payload.suffix or "")
    sequence = sequence + 1
    local id = "countdown:" .. sequence
    ReplaceEntry({
        id = id,
        durationObject = payload.durationObject,
        durationOptions = { formatString = label .. "{}" .. suffix },
        color = payload.color,
    })
    runtimeCollection:SetItemAlpha(id, 1)
end

function FlashText:ShowHealthEntries(source)
    local db = DB()
    if db.enabled == false or type(source) ~= "table" then return self:ClearHealthEntries() end
    EnsureFrames()
    entries = {}
    for index, entry in ipairs(source) do
        entries[#entries + 1] = { id = "health:" .. index, text = tostring(entry.text or ""), color = ResolveHealthColor(entry, db.font_text or {}) }
    end
    activeFlashID = nil
    anchorFrame:Show()
    RenderCollection(runtimeCollection, entries, db)
end

function FlashText:ClearHealthEntries()
    for index = #entries, 1, -1 do if tostring(entries[index].id):match("^health:") then table.remove(entries, index) end end
    if runtimeCollection then RenderCollection(runtimeCollection, entries, DB()) end
    if #entries == 0 and anchorFrame and not worldEditing then anchorFrame:Hide() end
end

function FlashText:Stop()
    entries, activeFlashID, fadeDirection, fadeElapsed = {}, nil, 0, 0
    if updateFrame then updateFrame:Hide() end
    if runtimeCollection then runtimeCollection:SetItems({}, { mode = "SEMANTIC", direction = "UP", spacing = 0, maxVisible = 1 }) end
    if anchorFrame and not worldEditing then anchorFrame:Hide() end
end

function FlashText:StopCountdown() self:Stop() end

function FlashText:RefreshVisuals(options)
    EnsureFrames()
    EnsureAnchorController():ApplyPosition()
    if worldEditing then RenderCollection(worldCollection, BuildPreviewEntries(), DB()) else RenderCollection(runtimeCollection, entries, DB()) end
    -- 外部调用未传 options 时保留完整 Panel 刷新；标准 Slider 放开时仅同步
    -- 正式 runtime/world，只有 旧字段补丁 要求重建才刷新 Panel。
    if options == nil or options.rebuildPanelPreview == true then
        RenderPanelPreview()
    end
end

function FlashText:StartFramePicker() return EnsureAnchorController():StartFramePicker() end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function() EnsureFrames(); EnsureAnchorController():ApplyPosition() end)
end)

ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss", key = "flashtextmedium", name = L["文字公告(中)"], settingsPage = "flashtextmedium",
    appearanceProfile = "basicText",
    orientation = "HORIZONTAL", worldAnchorMode = "semantic-root", editOverlay = { titleFontSize = 30 },
    getAnchor = function() EnsureFrames(); return anchorFrame end,
    GetWorldBounds = function() return FlashText:GetWorldBounds() end,
    RenderWorld = function(host) return FlashText:RenderWorld(host) end,
    ReleaseWorld = function() return FlashText:ReleaseWorld() end,
})

for _, path in ipairs({ "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget" }) do CONFIG_SCHEMA_PATHS[path] = true end
local STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    reapplyExisting = function()
        local function reapply(surface)
            if surface and type(surface.ReapplyPanelPresentation) == "function" then
                surface:ReapplyPanelPresentation()
            elseif surface and type(surface.ReapplyCurrentItems) == "function" then
                surface:ReapplyCurrentItems()
            end
        end
        reapply(panelSurface)
        reapply(panelPreview)
        reapply(worldCollection)
        reapply(runtimeCollection)
    end,
    -- 拖动只更新已物化 TextWidget；不 Render、不创建或重套 Panel Item。
    schemaPaths = CONFIG_SCHEMA_PATHS,
})

local function RefreshActiveSurfaces()
    return STANDARD_CONFIG_BINDING.reapplyExisting()
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })
