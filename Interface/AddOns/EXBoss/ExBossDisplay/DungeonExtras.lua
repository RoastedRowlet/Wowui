---@diagnostic disable: undefined-global
-- EXBoss 自有容器：标准 EXUI 外壳，副本生产者只提交血量数据。
local Tools = _G.ExwindTools
local EXUI = Tools.UI
local L = ExBoss.L
local KEY = "ExBoss.DungeonExtras"
local PREVIEW_BARS = 6
local MAX_VISIBLE = 6 -- 按出现顺序最多显示6条；不比较 Secret 血量。
ExBoss.UI = ExBoss.UI or {}
local Mod = {}
ExBoss.UI.DungeonExtras = Mod
local refreshDebug
local perfTimer
function Mod:SetRefreshDebug(enabled)
    if perfTimer then perfTimer:Cancel(); perfTimer = nil end
    refreshDebug = enabled and { builds = 0, layouts = 0, values = 0,
        created = 0, removed = 0, steady = 0, totalMS = 0, steadyMS = 0,
        maxSteadyMS = 0, startedAt = GetTime() } or nil
end
function Mod:GetRefreshDebug()
    if not refreshDebug then return end
    return refreshDebug.builds, refreshDebug.layouts, refreshDebug.values
end
function Mod:StopPerfTest()
    if perfTimer then perfTimer:Cancel(); perfTimer = nil end
    local stats = refreshDebug
    refreshDebug = nil
    if not stats then print("[DungeonExtras] No active performance test."); return end
    local elapsed = math.max(.001, GetTime() - stats.startedAt)
    print(string.format("[DungeonExtras] %.1fs | updates=%d steady=%d | new=%d removed=%d | builds=%d layouts=%d",
        elapsed, stats.values, stats.steady, stats.created, stats.removed, stats.builds, stats.layouts))
    print(string.format("[DungeonExtras] UpdateHealth total=%.3fms (%.3fms/s) | steady avg=%.4fms max=%.4fms",
        stats.totalMS, stats.totalMS / elapsed, stats.steadyMS / math.max(1, stats.steady), stats.maxSteadyMS))
    if stats.values == 0 then print("[DungeonExtras] No health updates sampled; repeat with matching NPCs in combat.") end
end
function Mod:StartPerfTest(seconds)
    seconds = math.max(5, math.min(120, tonumber(seconds) or 30))
    self:SetRefreshDebug(true)
    perfTimer = C_Timer.NewTimer(seconds, function() self:StopPerfTest() end)
    print(string.format("[DungeonExtras] Performance test started: %ds; auto-stop. Close settings and keep units stable.", seconds))
end

local EX_DEFAULTS = {
    module = { enabled = true, rubyWindFire = true, altarTrashHealth = false,
        healthColor = true, anchorX = 0, anchorY = 150,
        attachToCustom = false, customAttachTarget = "" },
    layout = { direction = "DOWN", spacing = 3, maxVisible = MAX_VISIBLE },
    timerGroup = {
        width = 240, height = 26, texture = "EX_WhiteTexture",
        barColorR = .2, barColorG = .85, barColorB = .3, barColorA = 1,
        barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = .6,
        showBorder = true, borderTexture = "EX_Default", borderColorR = 0,
        borderColorG = 0, borderColorB = 0, borderColorA = 1, borderSize = 1, borderPadding = 0,
        showIcon = false, iconSide = "LEFT", iconWidth = 26, iconHeight = 26, iconOffsetX = -2, iconOffsetY = 0,
        showIconBorder = true, iconBorderTexture = "EX_Default", iconBorderColorR = 0,
        iconBorderColorG = 0, iconBorderColorB = 0, iconBorderColorA = 1, iconBorderSize = 1, iconBorderPadding = 0,
        fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
    },
    font_spell = { font = "默认", size = 15, r = 1, g = 1, b = 1, a = 1, enabled = true,
        autoWidth = false, fixedWidth = 175, maxWidth = 0, justifyH = "LEFT", justifyV = "MIDDLE",
        outline = "OUTLINE", shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0,
        shadowColorA = 1, shadowX = 1, shadowY = -1, rotation = 0, gradientEnabled = false,
        gradientStart = 0, gradientLength = 0, x = 4, y = 0 },
    font_timer = { font = "默认", size = 15, r = 1, g = 1, b = 1, a = 1, enabled = true,
        autoWidth = false, fixedWidth = 60, maxWidth = 0, justifyH = "RIGHT", justifyV = "MIDDLE",
        outline = "OUTLINE", shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0,
        shadowColorA = 1, shadowX = 1, shadowY = -1, rotation = 0, gradientEnabled = false,
        gradientStart = 0, gradientLength = 0, x = -4, y = 0 },
}
local FONT_FIELDS = { "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
    "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA",
    "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart", "gradientLength", "x", "y" }
local BAR_FIELDS = { "width", "height", "texture", "barColorR", "barColorG", "barColorB", "barColorA",
    "barBgColorR", "barBgColorG", "barBgColorB", "barBgColorA", "showBorder", "borderTexture",
    "borderColorR", "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding",
    "showIcon", "iconSide", "iconWidth", "iconHeight", "iconOffsetX", "iconOffsetY", "showIconBorder",
    "iconBorderTexture", "iconBorderColorR", "iconBorderColorG", "iconBorderColorB", "iconBorderColorA",
    "iconBorderSize", "iconBorderPadding", "fillDirection", "progressMode" }
local DEFAULT_SCHEMA = {
    { group = "module", root = true, fields = { "enabled", "rubyWindFire", "altarTrashHealth", "healthColor",
        "anchorX", "anchorY", "attachToCustom", "customAttachTarget" } },
    { group = "layout", fields = { "direction", "spacing", "maxVisible" } },
    { group = "timerGroup", fields = BAR_FIELDS },
    { group = "font_spell", fields = FONT_FIELDS },
    { group = "font_timer", fields = FONT_FIELDS },
}
local DEFAULTS = Tools:DeclareModuleDefaults(KEY, EX_DEFAULTS, DEFAULT_SCHEMA)
local function DB() return Tools:GetModuleDB(KEY) end
function Mod:GetDB() return DB() end
function Mod:IsEnabled(feature) return DB().enabled == true and DB()[feature] == true end

local anchorController, anchorOptions = EXUI:CreateStandardModuleAnchor({
    moduleKey = KEY, frameName = "ExBoss_DungeonExtras_Anchor", title = L["副本额外设置"], getDB = DB,
    offsetXKey = "anchorX", offsetYKey = "anchorY", defaultOffsetX = DEFAULTS.anchorX, defaultOffsetY = DEFAULTS.anchorY,
    attachEnabledKey = "attachToCustom", attachTargetKey = "customAttachTarget",
    syncWidgets = { "anchorX", "anchorY", "attachToCustom", "customAttachTarget" },
    widgetRanges = { anchorX = { min = -1000, max = 1000, step = 1 }, anchorY = { min = -600, max = 600, step = 1 } },
    initialWidth = DEFAULTS.timerGroup.width, initialHeight = DEFAULTS.timerGroup.height,
    anchorPoint = "CENTER", relativePoint = "CENTER", clampedToScreen = false, frameStrata = "DIALOG",
})
function Mod:GetStandardAnchorGroupOptions() return anchorOptions end
function Mod:GetAnchor()
    local anchor = anchorController:Ensure()
    anchor:SetSize(DB().timerGroup.width, DB().timerGroup.height)
    anchorController:ApplyPosition()
    -- 空血量列表不能隐藏共用锚点上的风火图。
    anchor:Show()
    return anchor
end
-- 启动时物化唯一锚点，配置回调只调整已有宿主。
Mod:GetAnchor()

local INTERACTION_SCHEMA = {
    ["core.spellName"] = { guiKey = "font_spell", movable = true, textRole = "label", tooltip = L["单位名称"],
        position = { x = "font_spell.x", y = "font_spell.y" },
        anchor = { point = "LEFT", relativeElement = "core.bar", relativePoint = "LEFT" } },
    ["core.time"] = { guiKey = "font_timer", movable = true, textRole = "time", tooltip = L["血量百分比"],
        position = { x = "font_timer.x", y = "font_timer.y" },
        anchor = { point = "RIGHT", relativeElement = "core.bar", relativePoint = "RIGHT" } },
}
local function Layout()
    local layout = DB().layout
    return { mode = "FLOW", direction = layout.direction, spacing = layout.spacing,
        maxVisible = math.max(1, math.min(MAX_VISIBLE, math.floor(layout.maxVisible))) }
end
local healthCurve = C_CurveUtil.CreateColorCurve()
-- 重复阈值点形成阶跃；血量只交给原生曲线，不在 Lua 比较 Secret。
healthCurve:SetPoints({
    { x = 0, y = CreateColor(1, 0, 0) },
    { x = .33, y = CreateColor(1, 0, 0) },
    { x = .33, y = CreateColor(1, 1, 0) },
    { x = .66, y = CreateColor(1, 1, 0) },
    { x = .66, y = CreateColor(0, 1, 0) },
    { x = 1, y = CreateColor(0, 1, 0) },
})

local function BuildPresentation(record, sample)
    if not sample and refreshDebug then refreshDebug.builds = refreshDebug.builds + 1 end
    local db = DB()
    local fillColor
    if sample and db.healthColor then
        local color = healthCurve:Evaluate(record.percent / 100)
        local r, g, b = color:GetRGB()
        -- RGB 可以是 Secret；alpha 是普通配置值，避免 Core 中的 alpha fallback 检查 Secret。
        fillColor = { r = r, g = g, b = b, a = db.timerGroup.barColorA }
    end
    local interaction = EXUI:BuildStandardPreviewInteraction("TimerBar", db, INTERACTION_SCHEMA)
    return {
        style = { timerBar = db.timerGroup, text = { label = db.font_spell, time = db.font_timer } },
        label = record.name, icon = { value = 136016 },
        -- 预览使用普通文字；运行时按护盾条路径直写现成 timeText，避开普通时间参数判断。
        time = { text = sample and record.text or "", shown = db.font_timer.enabled == true },
        -- 运行血量在 ApplyNativeHealthFill 中直传主 StatusBar，绝不把 Secret
        -- 交给普通 Collection 的数字 clamp，也不进入 Duration 专用条的重置路径。
        progress = { value = sample and record.percent or 0, minimum = 0, maximum = 100 },
        fillColor = fillColor,
        interaction = interaction,
    }
end

local records = {}
local runtimeCollection, worldCollection, panelSurface, panelPreview, panelDock
local worldEditing = false
function Mod:IsWorldEditing() return worldEditing end
local samples = {}
for index = 1, PREVIEW_BARS do
    local percent = 100 - (index - 1) * 17
    samples[index] = { id = "dungeonextras:sample:" .. index, name = L["血量条预览"] .. " " .. index,
        percent = percent, text = string.format("%d%%", percent) }
end
local function EnsureRuntime()
    if not runtimeCollection then runtimeCollection = EXUI:CreateTimerBarCollection(Mod:GetAnchor(), "runtime", KEY) end
    return runtimeCollection
end
local function RelayoutRuntime()
    if not runtimeCollection then return end
    if refreshDebug then refreshDebug.layouts = refreshDebug.layouts + 1 end
    local ordered, items = {}, {}
    if not worldEditing then
        for _, record in pairs(records) do ordered[#ordered + 1] = record end
        table.sort(ordered, function(a, b) return a.order < b.order end)
        for _, record in ipairs(ordered) do items[#items + 1] = record.item end
    end
    runtimeCollection:SetItems(items, Layout())
end
local nextOrder = 0
local function ApplyNativeHealthText(record)
    -- 复用护盾条的时间文字槽，层级和拖动均由标准 TimerBar 管理。
    local text = record.item.widget.timeText
    text:ClearDurationBinding()
    text:SetSecretText(record.text)
    text:SetShown(DB().font_timer.enabled == true)
end
local function ApplyNativeHealthFill(record)
    local bar = record.item.widget.bar
    -- 与 ExUnitFrame.Player.UpdateHealthSection 相同的原生血量显示路径。
    bar:SetValue(record.percent, Enum.StatusBarInterpolation.Immediate)
    local db = DB()
    if db.healthColor then
        local r, g, b = record.color:GetRGB()
        bar:SetStatusBarColor(r, g, b, db.timerGroup.barColorA)
    end
end
function Mod:UpdateHealth(id, unit, name)
    if worldEditing or not self:IsEnabled("altarTrashHealth") then return end
    local stats = refreshDebug
    local startedMS = stats and debugprofilestop()
    local collection = EnsureRuntime()
    local record = records[id]
    local isNew = record == nil
    local nameChanged = not isNew and record.name ~= name
    if isNew then
        if stats then stats.created = stats.created + 1 end
        nextOrder = nextOrder + 1
        record = { id = id, order = nextOrder, item = collection:AcquireItem(id) }
        records[id] = record
    end
    record.name = name
    record.percent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    record.text = string.format("%.0f%%", record.percent)
    record.color = UnitHealthPercent(unit, true, healthCurve)
    if isNew then
        collection:ApplyItem(record.item, BuildPresentation(record, false))
        ApplyNativeHealthText(record)
    else
        -- 初建已由 SetSecretText 建立 Secret 文字状态；高频只写原生 FontString，
        -- 不再次调用会执行 RefreshTextLayout 的 TextWidget:SetSecretText。
        record.item.widget.timeText.text:SetText(record.text)
        if nameChanged then
            record.item.widget:SetLabel(name)
            record.item.presentation.label = name
        end
    end
    ApplyNativeHealthFill(record)
    -- 常规数值更新不 Show/Hide、不重套样式、不排序和重排。
    if isNew then RelayoutRuntime() end
    if stats then
        local elapsedMS = debugprofilestop() - startedMS
        stats.values = stats.values + 1
        stats.totalMS = stats.totalMS + elapsedMS
        if not isNew then
            stats.steady = stats.steady + 1
            stats.steadyMS = stats.steadyMS + elapsedMS
            stats.maxSteadyMS = math.max(stats.maxSteadyMS, elapsedMS)
        end
    end
end
function Mod:RemoveHealth(id)
    if not records[id] then return end
    if refreshDebug then refreshDebug.removed = refreshDebug.removed + 1 end
    runtimeCollection:ReleaseItem(id)
    records[id] = nil
    RelayoutRuntime()
end
function Mod:ClearHealth()
    for id in pairs(records) do
        if refreshDebug then refreshDebug.removed = refreshDebug.removed + 1 end
        runtimeCollection:ReleaseItem(id)
    end
    wipe(records)
    nextOrder = 0
    RelayoutRuntime()
end
local function RenderSamples(collection)
    local items = {}
    for _, record in ipairs(samples) do
        local item = collection:AcquireItem(record.id)
        collection:ApplyItem(item, BuildPresentation(record, true))
        items[#items + 1] = item
    end
    collection:SetItems(items, Layout())
end
function Mod:RenderWorld(host)
    worldEditing = true
    self:GetAnchor()
    RelayoutRuntime()
    if worldCollection then worldCollection:Release() end
    worldCollection = EXUI:CreateTimerBarCollection(host, "world", KEY)
    RenderSamples(worldCollection)
    Tools:SendEvent("EXBOSS_DUNGEON_EXTRAS_CHANGED")
end
function Mod:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    -- 生产者重新读取当前 State，而不是恢复编辑前的过期血量。
    Tools:SendEvent("EXBOSS_DUNGEON_EXTRAS_CHANGED")
end
function Mod:GetWorldBounds() return worldCollection and worldCollection:GetWorldBounds() or nil end
local function ResizePanelDock()
    if panelDock and panelPreview then
        local _, height = panelPreview:GetCollection():GetBounds()
        panelDock:SetHeight(math.max(60, height + 28))
    end
end
function Mod:ShowPanelPreview(dock)
    panelDock = dock
    panelPreview = panelSurface:Render({ dock = dock, ruleKey = KEY, state = true })
    ResizePanelDock()
end
function Mod:RefreshPanelPreview() if panelDock then self:ShowPanelPreview(panelDock) end end
function Mod:ReleasePanelPreview()
    panelSurface:Release()
    panelPreview, panelDock = nil, nil
end

local schemaPaths = {}
for _, group in ipairs(DEFAULT_SCHEMA) do
    for _, field in ipairs(group.fields) do schemaPaths[group.root and field or (group.group .. "." .. field)] = true end
end
local sampleByID = {}
for _, record in ipairs(samples) do sampleByID[record.id] = record end
local function Reapply(collection, source, sample)
    if not collection then return end
    collection:ReapplyCurrentItems(function(presentation, item)
        local record = source[item.id]
        if record then
            local nextPresentation = BuildPresentation(record, sample)
            for key in pairs(presentation) do presentation[key] = nil end
            for key, value in pairs(nextPresentation) do presentation[key] = value end
        end
    end, { reapplyLayout = false })
    if not sample then
        for _, record in pairs(source) do
            ApplyNativeHealthText(record)
            ApplyNativeHealthFill(record)
        end
        if refreshDebug then refreshDebug.layouts = refreshDebug.layouts + 1 end
    end
    collection:ReapplyCurrentLayout(Layout())
end
local settingsTimer
local function RequestSettingsRefresh()
    if settingsTimer then return end
    -- GUI 通知栈只重刷已物化条目；开关的增删生命周期在下一帧执行。
    settingsTimer = C_Timer.NewTimer(0, function()
        settingsTimer = nil
        Tools:SendEvent("EXBOSS_DUNGEON_EXTRAS_CHANGED")
    end)
end
local lastEnabled, lastRuby, lastAltar = DB().enabled, DB().rubyWindFire, DB().altarTrashHealth
local binding = EXUI:RegisterStandardConfigBinding({
    moduleKey = KEY, getConfig = DB, schemaPaths = schemaPaths,
    reapplyExisting = function()
        Mod:GetAnchor()
        Reapply(runtimeCollection, records, false)
        Reapply(worldCollection, sampleByID, true)
        Reapply(panelPreview, sampleByID, true)
        ResizePanelDock()
        local db = DB()
        if lastEnabled ~= db.enabled or lastRuby ~= db.rubyWindFire or lastAltar ~= db.altarTrashHealth then
            lastEnabled, lastRuby, lastAltar = db.enabled, db.rubyWindFire, db.altarTrashHealth
            RequestSettingsRefresh()
        end
    end,
})
Mod.StandardConfigBinding = binding
function Mod:RefreshVisuals() binding.reapplyExisting(); RequestSettingsRefresh() end
EXUI:RegisterModuleValueController(KEY, { RefreshActiveSurfaces = function() binding.reapplyExisting() end })
panelSurface = EXUI:CreateStandardPreviewSurface({
    moduleKey = KEY, kind = "timerbar", binding = binding,
    collectionOptions = { contentCenter = true }, interactionSchema = INTERACTION_SCHEMA,
    requiredPositionGuiKeys = { "font_spell", "font_timer" },
    buildPresentation = function()
        local entries = {}
        for _, record in ipairs(samples) do entries[#entries + 1] = { itemID = record.id, presentation = BuildPresentation(record, true) } end
        return { entries = entries, layout = Layout() }
    end,
})
EXUI:RegisterEditableModule({
    addon = "EXBoss", key = "dungeonextras", name = L["副本额外设置"], settingsPage = "dungeonextras",
    appearanceProfile = "basicTimerBar", orientation = "HORIZONTAL", worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 28 }, getAnchor = function() return Mod:GetAnchor() end,
    RenderWorld = function(host) return Mod:RenderWorld(host) end,
    ReleaseWorld = function() return Mod:ReleaseWorld() end,
    GetWorldBounds = function() return Mod:GetWorldBounds() end,
})
