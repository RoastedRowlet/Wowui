---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/CastProgressBar.lua
-- 圆环同源施法进度条
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

ExBoss.UI.CastProgressBar = ExBoss.UI.CastProgressBar or {}
local CastBar = ExBoss.UI.CastProgressBar
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local MODULE_KEY = "ExBoss.CastProgressBar"
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end

-- 唯一可编辑默认值真源。Grid 的“导出默认值”会完整反向输出同一结构，
-- 可直接替换本表；禁止另建页面默认值或运行时默认值。
local EX_DEFAULTS = {
    anchor = {
        -- root schema 从 anchor 声明组投影到 ModuleDB 根；缺省保持启用。
        enabled = true,
        anchorX = 7,
        anchorY = -235,
        attachToCustom = false,
        customAttachTarget = "",
    },
    font_spell = {
        a = 1,
        autoWidth = false,
        b = 1,
        enabled = true,
        fixedWidth = 200,
        font = "默认",
        g = 1,
        gradientEnabled = false,
        gradientLength = 0,
        gradientStart = 0,
        justifyH = "LEFT",
        justifyV = "MIDDLE",
        maxWidth = 0,
        outline = "OUTLINE",
        r = 1,
        rotation = 0,
        shadow = false,
        shadowColorA = 1,
        shadowColorB = 0,
        shadowColorG = 0,
        shadowColorR = 0,
        shadowX = 1,
        shadowY = -1,
        size = 16,
        x = 2.4004381512598,
        y = -0.00039627029139222,
    },
    font_timer = {
        a = 1,
        autoWidth = false,
        b = 1,
        enabled = true,
        fixedWidth = 200,
        font = "默认",
        g = 1,
        gradientEnabled = false,
        gradientLength = 0,
        gradientStart = 0,
        justifyH = "RIGHT",
        justifyV = "MIDDLE",
        maxWidth = 0,
        outline = "OUTLINE",
        r = 1,
        rotation = 0,
        shadow = false,
        shadowColorA = 1,
        shadowColorB = 0,
        shadowColorG = 0,
        shadowColorR = 0,
        shadowX = 1,
        shadowY = -1,
        size = 16,
        x = -2,
        y = 0,
    },
    layout = {
        direction = "DOWN",
        maxPerRow = 8,
        maxVisible = 3,
        spacing = 1,
        wrapDirection = "DOWN",
    },
    timerGroup = {
        barBgColorA = 0.5,
        barBgColorB = 0,
        barBgColorG = 0,
        barBgColorR = 0,
        barColorA = 1,
        barColorB = 1,
        barColorG = 0.8,
        barColorR = 0.1,
        borderColorA = 1,
        borderColorB = 0,
        borderColorG = 0,
        borderColorR = 0,
        borderPadding = 0,
        borderSize = 1,
        borderTexture = "EX_WhiteBorder",
        fillDirection = "LEFT_TO_RIGHT",
        height = 25,
        iconBorderColorA = 1,
        iconBorderColorB = 0,
        iconBorderColorG = 0,
        iconBorderColorR = 0,
        iconBorderPadding = 0.40000057220459,
        iconBorderSize = 1,
        iconBorderTexture = "EX_WhiteBorder",
        iconHeight = 24,
        iconOffsetX = -1,
        iconOffsetY = 0,
        iconSide = "LEFT",
        iconWidth = 24,
        progressMode = "REMAINING",
        showBorder = true,
        showIcon = true,
        showIconBorder = true,
        texture = "EX_WhiteTexture",
        width = 200,
    },
}

local FONT_FIELDS = { "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth", "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart", "gradientLength", "drawLayer", "drawSubLevel", "x", "y" }
local TIMER_FIELDS = { "width", "height", "texture", "barColorR", "barColorG", "barColorB", "barColorA", "barBgColorR", "barBgColorG", "barBgColorB", "barBgColorA", "showBorder", "borderTexture", "borderColorR", "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding", "showIcon", "iconSide", "iconWidth", "iconHeight", "iconOffsetX", "iconOffsetY", "showIconBorder", "iconBorderTexture", "iconBorderColorR", "iconBorderColorG", "iconBorderColorB", "iconBorderColorA", "iconBorderSize", "iconBorderPadding", "fillDirection", "progressMode" }
local DEFAULT_SCHEMA = {
    { group = "anchor",       root = true, fields = { "enabled", "anchorX", "anchorY", "attachToCustom", "customAttachTarget" } },
    { group = "font_spell", fields = FONT_FIELDS },
    { group = "font_timer", fields = FONT_FIELDS },
    { group = "layout", fields = { "direction", "maxPerRow", "maxVisible", "spacing", "wrapDirection" } },
    { group = "timerGroup", fields = TIMER_FIELDS },
}

-- DEFAULTS 是 EX_DEFAULTS 的一次编译结果，不是第二份可维护默认值。
local DEFAULTS = ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

local INTERACTION_SCHEMA = {
    ["core.spellName"] = {
        guiKey = "font_spell", movable = true, tooltip = L["法术名称"], textRole = "label",
        position = { x = "font_spell.x", y = "font_spell.y" },
    },
    ["core.time"] = {
        guiKey = "font_timer", movable = true, tooltip = L["时间文本"], textRole = "time",
        position = { x = "font_timer.x", y = "font_timer.y" },
    },
}

local function BuildStandardCastInteraction(db)
    return EXUI:BuildStandardPreviewInteraction("TimerBar", db, INTERACTION_SCHEMA)
end

local CAST_CHECK_MARGIN = 0.1
local CAST_CHECK_GOOD = { r = 0.10, g = 0.95, b = 0.20 }
local CAST_CHECK_BAD = { r = 1.00, g = 0.12, b = 0.08 }

local anchorFrame
local anchorController
local anchorGroupOptions
local eventFrame
local activeSlots = {}
local nextSlotID = 0
local runtimeCollection
local worldCollection
local panelCollection
local panelPreview
local panelSurface
local panelDock
local worldEditing = false
local castCheckPollFrame
local castCheckPollElapsed = 0
local EnsureAnchorController
local Ensure
local ReLayoutRuntime
local RenderPanelPreview
local AdvanceSlotAfterDuration
local CancelSlotExpiry
local ScheduleSlotExpiry

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[DeepCopy(k)] = DeepCopy(v)
    end
    return out
end

local function NormalizeUnitToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    unit = tostring(unit):lower()
    if unit == "" then
        return nil
    end
    return unit
end

local function NormalizeCastBarID(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return id
end

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function Clamp01(v, def)
    local n = tonumber(v)
    if n == nil then n = tonumber(def) end
    if n == nil then n = 1 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function EnsureLayoutModel(db)
    if type(db) ~= "table" then return end
    db.layout = type(db.layout) == "table" and db.layout or {}
    db.layout.direction = (db.layout.direction == "DOWN") and "DOWN" or "UP"
    db.layout.spacing = tonumber(db.layout.spacing) or DEFAULTS.layout.spacing
    db.layout.maxVisible = math.max(1,
        math.min(5, math.floor(tonumber(db.layout.maxVisible) or DEFAULTS.layout.maxVisible)))
end

local function SetClickThrough(obj)
    if not obj then return end
    obj:EnableMouse(false)
    if obj.SetMouseClickEnabled then obj:SetMouseClickEnabled(false) end
    if obj.SetMouseMotionEnabled then obj:SetMouseMotionEnabled(false) end
end

local function DB()
    local db = ExwindTools:GetModuleDB(MODULE_KEY)
    EnsureLayoutModel(db)
    return db
end

function CastBar:GetDB()
    return DB()
end

local function SavePosition(anchorX, anchorY)
    anchorX = math.floor(tonumber(anchorX) or DEFAULTS.anchorX)
    anchorY = math.floor(tonumber(anchorY) or DEFAULTS.anchorY)

    local mdb = DB()
    if type(mdb) == "table" then
        mdb.anchorX = anchorX
        mdb.anchorY = anchorY
    end
end

-- 世界编辑与设置页 panel 都只输入这组普通样本；不创建第二个预览定义或 Frame 树。
local PREVIEW_SPELL_IDS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }

-- 只构造 panel/world 静态样本；法术不存在时不伪造内容且不触及 runtime slot。
local function BuildPreviewSamples()
    local samples = {}
    if not (C_Spell and type(C_Spell.GetSpellInfo) == "function") then return samples end
    for index, spellID in ipairs(PREVIEW_SPELL_IDS) do
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name and info.iconID then
            samples[#samples + 1] = {
                spellID = spellID, displayName = info.name, iconFileID = info.iconID,
                duration = 4, remaining = math.max(0.6, 3.7 - (index - 1) * 0.55),
            }
        end
    end
    return samples
end

local function FormatTime(secs)
    secs = math.max(0, tonumber(secs) or 0)
    if secs >= 60 then
        return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
    end
    if secs >= 10 then
        return string.format("%.0f", secs)
    end
    return string.format("%.1f", secs)
end

local function GetPlayerCastEndAt()
    local now = GetTime()
    if UnitCastingInfo then
        local _name, _text, _texture, _startTimeMS, endTimeMS = UnitCastingInfo("player")
        local endAt = tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then return endAt end
    end
    if UnitChannelInfo then
        local _name, _text, _texture, _startTimeMS, endTimeMS = UnitChannelInfo("player")
        local endAt = tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then return endAt end
    end
    return nil
end

local function GetConfiguredMaxBars(db)
    local layout = type(db) == "table" and db.layout or nil
    local n = math.floor(SafeNum(layout and layout.maxVisible, DEFAULTS.layout.maxVisible) or DEFAULTS.layout.maxVisible)
    if n < 1 then n = 1 end
    if n > 5 then n = 5 end
    return n
end

local function GetConfiguredSpacing(db)
    local layout = type(db) == "table" and db.layout or nil
    -- WidgetLayout officially supports negative spacing (down to a positive
    -- 1px step).  Do not silently turn the shared layout control into zero.
    return SafeNum(layout and layout.spacing, DEFAULTS.layout.spacing)
end

local function GetGrowDir(db)
    local layout = type(db) == "table" and db.layout or nil
    local dir = tostring((layout and layout.direction) or DEFAULTS.layout.direction)
    if dir ~= "UP" and dir ~= "DOWN" then
        dir = DEFAULTS.layout.direction
    end
    return dir
end

-- 整体锚点只有这一份正式合同：AnchorController 与设置页 anchorgroup 都必须
-- 由 EXUI:CreateStandardModuleAnchor 读取它，禁止 Page 重新声明 key/default/picker。
-- root DB 已由 DEFAULT_SCHEMA.anchor 的 root=true 展平，故 rootPath 为空字符串。
local ANCHOR_SCHEMA = {
    rootPath = "",
    moduleKey = MODULE_KEY,
    frameName = "ExBoss_CastProgressBarAnchor",
    title = L["施法进度条"],
    getDB = DB,
    offsetXKey = "anchorX",
    offsetYKey = "anchorY",
    defaultOffsetX = DEFAULTS.anchorX,
    defaultOffsetY = DEFAULTS.anchorY,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    syncWidgets = {
        "anchorX",
        "anchorY",
        "attachToCustom",
        "customAttachTarget",
    },
    widgetRanges = {
        anchorX = { min = -1000, max = 1000, step = 1 },
        anchorY = { min = -600, max = 600, step = 1 },
    },
    initialWidth = DEFAULTS.timerGroup.width,
    initialHeight = DEFAULTS.timerGroup.height,
    clampedToScreen = false,
    frameStrata = "DIALOG",
    -- Direction only controls later bars; the first bar is the fixed root.
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    onCreateFrame = function(_, owner)
        owner:Hide()
    end,
}

local function IsBadCheckColor(color)
    return type(color) == "table"
        and color.r == CAST_CHECK_BAD.r
        and color.g == CAST_CHECK_BAD.g
        and color.b == CAST_CHECK_BAD.b
end

local function ResolveCastCheckColor(slot)
    local castEndAt = GetPlayerCastEndAt()
    local state = type(slot) == "table" and slot.state or nil
    local barEndAt = state and tonumber(state.endAt) or nil
    if castEndAt and barEndAt and castEndAt > (barEndAt - CAST_CHECK_MARGIN) then
        return CAST_CHECK_BAD
    end
    return CAST_CHECK_GOOD
end

local function GetNormalBarColor(db)
    local group = type(db) == "table" and type(db.timerGroup) == "table" and db.timerGroup or
        DEFAULTS.timerGroup
    return Clamp01(group.barColorR, DEFAULTS.timerGroup.barColorR),
        Clamp01(group.barColorG, DEFAULTS.timerGroup.barColorG),
        Clamp01(group.barColorB, DEFAULTS.timerGroup.barColorB),
        Clamp01(group.barColorA, DEFAULTS.timerGroup.barColorA)
end

local function ResolveSlotActiveColor(slot, db)
    if type(slot) == "table" and type(slot.state) == "table" and slot.state.castCheckEnabled == true then
        local c = ResolveCastCheckColor(slot)
        if IsBadCheckColor(c) then
            return c.r, c.g, c.b, 1
        end
        return CAST_CHECK_GOOD.r, CAST_CHECK_GOOD.g, CAST_CHECK_GOOD.b, 1
    end
    return GetNormalBarColor(db)
end

local function HasActiveCastCheckSlots()
    for i = 1, #activeSlots do
        local slot = activeSlots[i]
        if slot and type(slot.state) == "table" and slot.state.castCheckEnabled == true then
            return true
        end
    end
    return false
end

-- 玩家施法开始事件在实战中并非每次都会在本模块注册完成后到达；施法检测条存活期间
-- 固定轮询玩家当前读条，确保颜色不依赖单个 START 事件。
local function SetCastCheckPollingEnabled(enabled)
    if not castCheckPollFrame then
        castCheckPollFrame = CreateFrame("Frame")
        castCheckPollFrame:Hide()
        castCheckPollFrame:SetScript("OnUpdate", function(_, elapsed)
            castCheckPollElapsed = castCheckPollElapsed + (tonumber(elapsed) or 0)
            if castCheckPollElapsed < 0.05 then return end
            castCheckPollElapsed = 0
            if HasActiveCastCheckSlots() and ReLayoutRuntime then
                ReLayoutRuntime()
            end
        end)
    end
    castCheckPollElapsed = 0
    castCheckPollFrame:SetShown(enabled == true)
end

local function EnsureEventFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then return end
        if HasActiveCastCheckSlots() then ReLayoutRuntime() end
    end)
    return eventFrame
end

local function SetCastCheckEventsEnabled(enabled)
    local ef = EnsureEventFrame()
    ef:UnregisterAllEvents()
    if enabled ~= true then return end
    ef:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end

local function RefreshCastCheckEventState()
    local enabled = HasActiveCastCheckSlots()
    SetCastCheckEventsEnabled(enabled)
    SetCastCheckPollingEnabled(enabled)
end

local function ResolveMode(phase)
    local castKind = type(phase) == "table" and tostring(phase.castKind or "") or ""
    -- 固定业务规则：施法左→右填满；引导右→左消退。
    -- 单条 phase.barMode 与 ModuleDB 都不能覆盖它。
    return castKind == "channel" and "rtl_decay" or "ltr_fill"
end

-- “从右向左消退”描述的是消退前沿的移动方向，不是剩余色块的锚点。
-- 因此 rtl_decay 必须保留普通（左锚）填充，再让原生 Duration 走倒数；
-- 若把二者同时反向，视觉会变成从左向右消退。
local function UsesReverseFillStyle(mode)
    return mode == "rtl_fill"
end

local function UsesReverseTimerDirection(mode)
    return mode == "ltr_decay" or mode == "rtl_decay"
end

local function ResolveValue(duration, elapsed, mode)
    if mode == "ltr_fill" or mode == "rtl_fill" then
        return math.max(0, math.min(duration, elapsed))
    end
    return math.max(0, math.min(duration, duration - elapsed))
end

local function ResolveDisplayName(entry)
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    local name = type(entry) == "table" and entry.displayName or nil
    local progressName = type(entry) == "table" and entry.progressDisplayName or nil
    local rename = type(entry) == "table" and entry.castBarRenameText or nil
    if type(entry) == "table" and entry.castBarRenameEnabled == true and type(rename) == "string" and rename ~= "" then
        return rename
    end
    if type(entry) == "table" and entry.preferSpellName == true then
        if type(progressName) == "string" and progressName ~= "" then
            return progressName
        end
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.name then
                return info.name
            end
        end
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo and IsNonChineseLocale() then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    return ""
end

local function ResolveIcon(entry)
    local iconFileID = tonumber(type(entry) == "table" and entry.iconFileID or nil)
    if iconFileID and iconFileID > 0 then
        return iconFileID
    end
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then
            return tex
        end
    end
    return 136197
end

-- =============================================================
-- 唯一 Renderer：Runtime、World、Panel 都只调用这一组函数。
-- 固定 Body 是 TimerBarWidget；名称与时间是其标准文字槽，没有额外子元素。
-- =============================================================
local function CopyTable(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        result[key] = value
    end
    return result
end

local function BuildPresentation(slot, runtime)
    local db = DB()
    local state = slot and slot.state or {}
    local phase = state.phase or {}
    local duration = math.max(0.1, SafeNum(state.duration, 0.1))
    local timerStyle = CopyTable(db.timerGroup)
    local r, g, b, a = ResolveSlotActiveColor(slot, db)
    timerStyle.barColorR, timerStyle.barColorG = r, g
    timerStyle.barColorB, timerStyle.barColorA = b, a
    timerStyle.fillDirection = UsesReverseFillStyle(state.mode) and "RIGHT_TO_LEFT" or "LEFT_TO_RIGHT"

    local presentation = {
        style = {
            timerBar = timerStyle,
            text = {
                label = db.font_spell,
                time = db.font_timer,
            },
        },
        icon = { value = ResolveIcon(phase) },
        label = ResolveDisplayName(phase),
        interaction = BuildStandardCastInteraction(db),
    }

    if runtime then
        -- runtime 只把真实 expirationTime 对应的同一 Duration Object 交给 Blizzard。
        -- 外观刷新不会以 GetTime() 重置倒数起点。
        presentation.time = {
            mode = "DURATION",
            duration = state.durationObject,
            interpolation = Enum.StatusBarInterpolation.None,
            direction = UsesReverseTimerDirection(state.mode) and 1 or 0,
        }
        local phaseGeneration = state.phaseGeneration
        presentation.onTimerDone = function()
            AdvanceSlotAfterDuration(slot, phaseGeneration)
        end
    else
        -- panel/world 仅画静态样本：无 Duration、无 Native timer、无完成回调。
        local remaining = math.max(0, math.min(duration, SafeNum(state.remaining, duration)))
        local elapsed = duration - remaining
        presentation.time = {
            text = FormatTime(remaining),
            shown = db.font_timer == nil or db.font_timer.enabled ~= false,
        }
        presentation.progress = {
            value = ResolveValue(duration, elapsed, state.mode),
            maximum = duration,
            minimum = 0,
        }
    end

    return presentation
end

local function ApplyRecord(collection, slot, runtime)
    if not collection or not slot then return nil end
    slot.items = slot.items or {}
    local item = slot.items[collection]
    if not item then
        item = collection:AcquireItem(slot.id)
        slot.items[collection] = item
    end
    collection:ApplyItem(item, BuildPresentation(slot, runtime))
    return item
end

local function GetOrderedSlots()
    local visible = {}
    for _, slot in ipairs(activeSlots) do
        if slot and type(slot.state) == "table" then
            visible[#visible + 1] = slot
        end
    end
    table.sort(visible, function(a, b)
        local aEnd = tonumber(a.state and a.state.endAt) or math.huge
        local bEnd = tonumber(b.state and b.state.endAt) or math.huge
        if aEnd == bEnd then return (a.order or 0) < (b.order or 0) end
        return aEnd < bEnd
    end)
    return visible
end

local function ApplyCollectionItems(collection, slots, runtime)
    if not collection then return end
    local items = {}
    for _, slot in ipairs(slots or {}) do
        local item = ApplyRecord(collection, slot, runtime)
        if item then items[#items + 1] = item end
    end
    local db = DB()
    collection:SetItems(items, {
        mode = "FLOW",
        direction = GetGrowDir(db),
        spacing = GetConfiguredSpacing(db),
        maxVisible = GetConfiguredMaxBars(db),
    })
end

local function ReleaseSlotItems(slot)
    for collection, item in pairs(slot and slot.items or {}) do
        if collection and item then
            collection:ReleaseItem(slot.id)
        end
    end
    if slot then slot.items = nil end
end

local function SetRuntimeItemsShown(shown)
    if not runtimeCollection then return end
    for _, item in pairs(runtimeCollection:GetItems() or {}) do
        if item and item.root then item.root:SetShown(shown == true) end
    end
end

ReLayoutRuntime = function()
    if not runtimeCollection then return end
    if worldEditing then
        SetRuntimeItemsShown(false)
        return
    end
    ApplyCollectionItems(runtimeCollection, GetOrderedSlots(), true)
end

local function BuildSampleSlots()
    local result, samples = {}, BuildPreviewSamples()
    if #samples == 0 then return result end
    -- Fixed panel/world topology: maxVisible is a layout-only setting, so
    -- every slider phase can reapply the existing five slots in place.
    local count = 5
    for index = 1, count do
        local sample = samples[((index - 1) % #samples) + 1]
        local duration = math.max(0.1, SafeNum(sample.duration, 4))
        local remaining = math.max(0, math.min(duration, SafeNum(sample.remaining, duration)))
        result[#result + 1] = {
            id = "castprogress-sample:" .. index,
            order = index,
            state = {
                phase = {
                    spellID = sample.spellID,
                    displayName = sample.displayName,
                    iconFileID = sample.iconFileID,
                    duration = duration,
                    castKind = "cast",
                },
                duration = duration,
                remaining = remaining,
                mode = "ltr_fill",
            },
        }
    end
    return result
end

-- 设置页样本仍只调用本模块唯一的 BuildPresentation；StandardPreviewSurface
-- 只拥有正式 panel session 的复用/释放，不建立 CastProgressBar 私有预览树。
local function BuildCastProgressPanelPresentation(_, mode)
    if mode ~= "panel" then
        error("CastProgressBar panel surface only accepts panel mode", 2)
    end
    local entries = {}
    for _, slot in ipairs(BuildSampleSlots()) do
        entries[#entries + 1] = {
            itemID = slot.id,
            presentation = BuildPresentation(slot, false),
        }
    end
    local db = DB()
    return {
        entries = entries,
        layout = {
            mode = "FLOW",
            direction = GetGrowDir(db),
            spacing = GetConfiguredSpacing(db),
            maxVisible = GetConfiguredMaxBars(db),
        },
    }
end

local function RenderSampleCollection(collection)
    ApplyCollectionItems(collection, BuildSampleSlots(), false)
end

local function RemoveActiveSlot(slot)
    for i = #activeSlots, 1, -1 do
        if activeSlots[i] == slot then
            table.remove(activeSlots, i)
            return
        end
    end
end

local function CreateSlot()
    -- 业务 slot 只保存状态与稳定 ID；可见 Item 完全由 Collection 管理。
    nextSlotID = nextSlotID + 1
    return { id = "castprogress:runtime:" .. nextSlotID, order = nextSlotID, state = nil }
end

local function GetVisibleSlots()
    return GetOrderedSlots()
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController, anchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)

    return anchorController
end

function CastBar:GetAnchorGroupOptions()
    EnsureAnchorController()
    return anchorGroupOptions
end

local function ApplyAnchorPosition(count)
    if not anchorFrame then return end
    EnsureAnchorController():ApplyPosition()
end

local function UpdateAnchorFrameSize()
    if not anchorFrame then return end
    local db = DB()
    local group = type(db.timerGroup) == "table" and db.timerGroup or DEFAULTS.timerGroup
    local width = math.max(20, SafeNum(group.width, DEFAULTS.timerGroup.width))
    local height = math.max(4, SafeNum(group.height, DEFAULTS.timerGroup.height))
    -- Anchor 只保留首个固定 Body 的语义尺寸；集合视觉包络属于 Collection/Selection。
    anchorFrame:SetSize(width, height)
end

local function ApplyVisuals()
    UpdateAnchorFrameSize()
    ReLayoutRuntime()
    ApplyAnchorPosition()
end

local function HideAllRows()
    SetRuntimeItemsShown(false)
end

local function StopSlot(slot)
    if not slot then return end
    CancelSlotExpiry(slot)
    RemoveActiveSlot(slot)
    ReleaseSlotItems(slot)
    slot.state = nil
end

local function DoesOwnerMatch(state, owner)
    if type(state) ~= "table" or type(owner) ~= "table" then
        return false
    end
    if owner.source and tostring(state.ownerSource or "") ~= tostring(owner.source or "") then
        return false
    end
    if owner.castKind and tostring(state.ownerCastKind or "") ~= tostring(owner.castKind or "") then
        return false
    end
    local ownerCastBarID = NormalizeCastBarID(owner.castBarID)
    local stateCastBarID = NormalizeCastBarID(state.ownerCastBarID)
    if ownerCastBarID ~= nil and stateCastBarID ~= ownerCastBarID then
        return false
    end
    if owner.runtime ~= nil and state.ownerRuntime ~= owner.runtime then
        return false
    end
    if owner.encounterID ~= nil and tonumber(state.ownerEncounterID) ~= tonumber(owner.encounterID) then
        return false
    end
    if owner.eventID ~= nil and tonumber(state.ownerEventID) ~= tonumber(owner.eventID) then
        return false
    end
    if (owner.encounterID ~= nil or owner.eventID ~= nil)
        and tostring(state.ownerSource or "") == "boss"
        and tostring(owner.source or "") == "boss"
    then
        return true
    end

    local ownerUnit = NormalizeUnitToken(owner.unit)
    local stateUnit = NormalizeUnitToken(state.ownerUnit)
    if ownerUnit ~= nil then
        if stateUnit == ownerUnit then
            return true
        end
        if tostring(state.ownerSource or "") == "boss"
            and tostring(owner.source or "") == "boss"
            and ownerCastBarID ~= nil
            and stateCastBarID == ownerCastBarID
        then
            return true
        end
        return false
    end

    return true
end

-- 每个 phase 只有一份一次性到期兜底。token 让原生 onTimerDone、真实结束事件和
-- C_Timer 即使同帧竞态，也只能有一个进入 AdvanceSlotAfterDuration。
CancelSlotExpiry = function(slot)
    local state = slot and slot.state or nil
    if type(state) ~= "table" then return end
    state.expiryToken = (state.expiryToken or 0) + 1
    local timer = state.expiryTimer
    state.expiryTimer = nil
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end
end

ScheduleSlotExpiry = function(slot, expirationTime, phaseGeneration)
    local state = slot and slot.state or nil
    if type(state) ~= "table" then return end
    CancelSlotExpiry(slot)
    if not (C_Timer and type(C_Timer.NewTimer) == "function") then return end

    local delay = math.max(0, (tonumber(expirationTime) or GetTime()) - GetTime())
    local token = state.expiryToken
    state.expiryTimer = C_Timer.NewTimer(delay, function()
        local current = slot and slot.state or nil
        if current ~= state
            or state.expiryToken ~= token
            or state.phaseGeneration ~= phaseGeneration
        then
            return
        end
        state.expiryTimer = nil
        AdvanceSlotAfterDuration(slot, phaseGeneration)
    end)
end

local function StopAllAnimations()
    for i = #activeSlots, 1, -1 do
        local slot = activeSlots[i]
        if slot then
            CancelSlotExpiry(slot)
            ReleaseSlotItems(slot)
            slot.state = nil
        end
        table.remove(activeSlots, i)
    end
    RefreshCastCheckEventState()
end

local function EnsureAnchorVisible()
    if not anchorFrame then return end
    if worldEditing then
        anchorFrame:Show()
        return
    end
    if #GetVisibleSlots() > 0 then
        anchorFrame:Show()
    else
        anchorFrame:Hide()
    end
end

local function BeginSlotPhase(slot, phase)
    local state = slot and slot.state or nil
    if not state then
        return
    end
    local duration = math.max(0.1, SafeNum(phase and phase.duration, 5))
    local mode = ResolveMode(phase)
    local now = GetTime()
    local expirationTime = SafeNum(phase and phase.expirationTime,
        SafeNum(phase and phase.endTime, now + duration))
    local durationObject = C_DurationUtil.CreateDuration()
    durationObject:SetTimeFromEnd(expirationTime, duration, SafeNum(phase and phase.modRate, 1))

    state.duration = duration
    state.mode = mode
    state.expirationTime = expirationTime
    state.durationObject = durationObject
    state.phaseGeneration = (state.phaseGeneration or 0) + 1
    state.phase = phase
    local remainingPlanDuration = 0
    for index = (state.phaseIndex or 1) + 1, #(state.phases or {}) do
        remainingPlanDuration = remainingPlanDuration
            + math.max(0.1, SafeNum(state.phases[index] and state.phases[index].duration, 5))
    end
    state.endAt = expirationTime + remainingPlanDuration
    -- 原生 Duration 只负责渲染；部分客户端不会把 OnCooldownDone 回传给
    -- TimerBarWidget。为同一 phase 建一个一次性生命周期兜底，确保画面归零时
    -- slot 一定进入下一 phase 或释放。真实 STOP/INTERRUPTED 仍会更早清理。
    ScheduleSlotExpiry(slot, expirationTime, state.phaseGeneration)

    ReLayoutRuntime()
end

local function StartSlotAnimation(slot, phases, opts)
    opts = type(opts) == "table" and opts or {}
    if not slot or type(phases) ~= "table" or #phases == 0 then
        return
    end
    StopSlot(slot)

    local totalDuration = 0
    for i = 1, #phases do
        totalDuration = totalDuration + math.max(0.1, SafeNum(phases[i] and phases[i].duration, 5))
    end
    local now = GetTime()
    slot.state = {
        phases = phases,
        phaseIndex = 1,
        duration = 0,
        mode = nil,
        endAt = now + totalDuration,
        castCheckEnabled = opts.castCheckEnabled == true,
        ownerSource = type(opts.owner) == "table" and tostring(opts.owner.source or "") or nil,
        ownerUnit = type(opts.owner) == "table" and NormalizeUnitToken(opts.owner.unit) or nil,
        ownerCastKind = type(opts.owner) == "table" and tostring(opts.owner.castKind or "") or nil,
        ownerCastBarID = type(opts.owner) == "table" and NormalizeCastBarID(opts.owner.castBarID) or nil,
        ownerEncounterID = type(opts.owner) == "table" and tonumber(opts.owner.encounterID) or nil,
        ownerEventID = type(opts.owner) == "table" and tonumber(opts.owner.eventID) or nil,
        ownerRuntime = type(opts.owner) == "table" and opts.owner.runtime or nil,
        earlyStopEnabled = type(opts.owner) == "table" and opts.owner.earlyStopEnabled == true or false,
    }
    activeSlots[#activeSlots + 1] = slot
    BeginSlotPhase(slot, phases[1])
    RefreshCastCheckEventState()
    ReLayoutRuntime()
    EnsureAnchorVisible()
end

AdvanceSlotAfterDuration = function(slot, phaseGeneration)
    local state = slot and slot.state or nil
    if type(state) ~= "table" or state.phaseGeneration ~= phaseGeneration then
        return
    end
    CancelSlotExpiry(slot)

    local nextIndex = state.phaseIndex + 1
    if state.phases and state.phases[nextIndex] then
        state.phaseIndex = nextIndex
        BeginSlotPhase(slot, state.phases[nextIndex])
    else
        ReleaseSlotItems(slot)
        slot.state = nil
        RemoveActiveSlot(slot)
        RefreshCastCheckEventState()
        ReLayoutRuntime()
        EnsureAnchorVisible()
    end
end

local function NormalizePhases(sequence, opts)
    opts = type(opts) == "table" and opts or {}
    local out = {}
    for i = 1, #sequence do
        local phase = sequence[i]
        if type(phase) == "table" then
            local row = DeepCopy(phase)
            row.displayName = row.displayName or opts.displayName
            row.spellID = row.spellID or opts.spellID
            row.iconFileID = row.iconFileID or opts.iconFileID
            if opts.castCheckEnabled == true then
                row.castCheckEnabled = true
            end
            out[#out + 1] = row
        end
    end
    return out
end

local function AcquireSlot()
    local maxBars = GetConfiguredMaxBars(DB())
    if #activeSlots < maxBars then return CreateSlot() end
    local replacement = activeSlots[1]
    for i = 2, #activeSlots do
        local slot = activeSlots[i]
        if (tonumber(slot.state and slot.state.endAt) or math.huge)
            < (tonumber(replacement.state and replacement.state.endAt) or math.huge) then
            replacement = slot
        end
    end
    return replacement
end

Ensure = function()
    if anchorFrame then return end

    local db = DB()
    local group = type(db.timerGroup) == "table" and db.timerGroup or DEFAULTS.timerGroup
    local initW = math.max(20, SafeNum(group.width, DEFAULTS.timerGroup.width))
    local initH = math.max(4, SafeNum(group.height, DEFAULTS.timerGroup.height))
    anchorFrame = EnsureAnchorController():Ensure()
    anchorFrame:SetSize(initW, initH)
    runtimeCollection = ExwindTools.UI:CreateTimerBarCollection(anchorFrame, "runtime", MODULE_KEY)
    ApplyVisuals()
end

function CastBar:ShowEntry(entry, forcedRemaining)
    if DB().enabled == false then
        self:Hide()
        return
    end
    Ensure()
    if type(entry) ~= "table" then
        self:Hide()
        return
    end

    local duration = math.max(0.1, SafeNum(entry.duration, 5))
    local remaining = SafeNum(forcedRemaining, nil)
    local hasForcedRemaining = remaining ~= nil
    local now = GetTime()
    if remaining == nil then
        remaining = math.max(0, SafeNum(entry.expirationTime, SafeNum(entry.endTime, now + duration)) - now)
    end
    if remaining <= 0 then
        self:Hide()
        return
    end

    local row = DeepCopy(entry)
    row.duration = duration
    row.expirationTime = hasForcedRemaining and now + remaining
        or SafeNum(entry.expirationTime, SafeNum(entry.endTime, now + remaining))
    local slot = AcquireSlot()

    StartSlotAnimation(slot, { row }, {
        castCheckEnabled = entry.castCheckEnabled == true,
        owner = type(entry.owner) == "table" and entry.owner or nil,
    })
end

function CastBar:ShowSequence(sequence, opts)
    if DB().enabled == false then
        self:Hide()
        return
    end
    Ensure()
    if type(sequence) ~= "table" or #sequence == 0 then
        return
    end
    opts = type(opts) == "table" and opts or {}
    local phases = NormalizePhases(sequence, opts)
    if #phases == 0 then
        return
    end
    if opts.castCheckEnabled ~= true then
        for i = 1, #phases do
            if phases[i].castCheckEnabled == true then
                opts.castCheckEnabled = true
                break
            end
        end
    end
    local slot = AcquireSlot()
    StartSlotAnimation(slot, phases, opts)
end

function CastBar:Hide()
    if anchorFrame then
        StopAllAnimations()
        HideAllRows()
        anchorFrame:Hide()
    end
end

function CastBar:StopByOwner(owner)
    if type(owner) ~= "table" then
        return 0
    end
    local removed = 0
    for i = #activeSlots, 1, -1 do
        local slot = activeSlots[i]
        local state = slot and slot.state or nil
        if type(state) == "table" and state.earlyStopEnabled == true and DoesOwnerMatch(state, owner) then
            StopSlot(slot)
            removed = removed + 1
        end
    end
    if removed > 0 then
        RefreshCastCheckEventState()
        ReLayoutRuntime()
        EnsureAnchorVisible()
    end
    return removed
end

function CastBar:StopByUnitCastBar(unit, castBarID, castKind)
    return self:StopByOwner({
        source = "boss",
        unit = NormalizeUnitToken(unit),
        castBarID = NormalizeCastBarID(castBarID),
        castKind = tostring(castKind or ""),
    })
end

function CastBar:IsPlaying()
    return #activeSlots > 0
end

function CastBar:RefreshVisuals(options)
    if not anchorFrame then
        return
    end
    if DB().enabled == false and not worldEditing then
        -- 关闭开关时终止现有序列，不保留任何仍会在之后推进的运行时状态。
        self:Hide()
        if options == nil or options.rebuildPanelPreview == true then
            RenderPanelPreview()
        end
        ExwindTools.UI:RefreshEditableModule("EXBoss", "castprogressbar")
        return
    end
    if worldEditing then
        RenderSampleCollection(worldCollection)
    else
        ApplyVisuals()
    end
    -- 既有调用未传 options，仍保留完整 Panel 刷新语义。标准 Slider 放开时
    -- 只同步正式 runtime/world；只有 旧字段补丁 明确要求结构重建，才重画
    -- 已物化的 Panel Preview。
    if options == nil or options.rebuildPanelPreview == true then
        RenderPanelPreview()
    end
    UpdateAnchorFrameSize()
    ApplyAnchorPosition()
    ExwindTools.UI:RefreshEditableModule("EXBoss", "castprogressbar")
    EnsureAnchorVisible()
end

function CastBar:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        Ensure()
        CastBar:RefreshVisuals()
    end)
end)

function CastBar:RenderWorld(host)
    if worldCollection then worldCollection:Release() end
    worldEditing = true
    SetRuntimeItemsShown(false)
    -- AnchorController 的新宿主按运行时默认是隐藏的。世界编辑切换为样本
    -- Collection 后必须明确显示同一个语义 Anchor，否则 renderer 虽已建好却
    -- 整棵树不可见。
    EnsureAnchorVisible()
    worldCollection = ExwindTools.UI:CreateTimerBarCollection(host, "world", MODULE_KEY)
    RenderSampleCollection(worldCollection)
end

function CastBar:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    ReLayoutRuntime()
    EnsureAnchorVisible()
end

function CastBar:GetWorldBounds()
    return worldCollection and worldCollection:GetWorldBounds() or nil
end

RenderPanelPreview = function()
    if not panelSurface or not panelDock then return end
    panelPreview = panelSurface:Render({
        dock = panelDock,
        ruleKey = MODULE_KEY,
        state = true,
    })
    panelCollection = panelPreview:GetCollection()
    local _, height = panelCollection:GetBounds()
    panelDock:SetHeight(math.max(60, (height or 0) + 28))
end

function CastBar:ShowPanelPreview(dock)
    if not dock then return end
    if not panelSurface then
        error("CastProgressBar standard panel surface is not initialized", 2)
    end
    panelDock = dock
    RenderPanelPreview()
end

function CastBar:RefreshPanelPreview()
    RenderPanelPreview()
end

function CastBar:GetPanelBounds()
    if panelCollection then return panelCollection:GetBounds() end
    return nil
end

function CastBar:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelCollection = nil
    panelDock = nil
end

-- Runtime、世界编辑和设置页都经由 BuildPresentation → ApplyRecord → SetItems。
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "castprogressbar",
    name = L["施法进度条"],
    settingsPage = "castprogressbar",
    appearanceProfile = "basicTimerBar",
    orientation = "HORIZONTAL",
    editOverlay = { titleFontSize = 30 },
    getAnchor = function()
        Ensure()
        return anchorFrame
    end,
    RenderWorld = function(host) return CastBar:RenderWorld(host) end,
    ReleaseWorld = function() return CastBar:ReleaseWorld() end,
    GetWorldBounds = function() return CastBar:GetWorldBounds() end,
})

local STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    reapplyExisting = function()
        local sampleSlots = BuildSampleSlots()
        local db = DB()
        local layout = {
            mode = "FLOW", direction = GetGrowDir(db),
            spacing = GetConfiguredSpacing(db), maxVisible = GetConfiguredMaxBars(db),
        }
        local function reapply(surface, slots, runtime)
            if not (surface and type(surface.ReapplyCurrentItems) == "function") then return false end
            local slotsByID = {}
            for _, slot in ipairs(slots or {}) do slotsByID[slot.id] = slot end
            local patched = surface:ReapplyCurrentItems(function(presentation, item)
                local slot = item and slotsByID[item.id]
                if not slot then return end
                local nextPresentation = BuildPresentation(slot, runtime)
                for key in pairs(presentation) do presentation[key] = nil end
                for key, value in pairs(nextPresentation) do presentation[key] = value end
            end, { reapplyLayout = false })
            if patched and type(surface.ReapplyCurrentLayout) == "function" then
                surface:ReapplyCurrentLayout(layout)
            end
            return patched
        end
        -- Standard surface 当前会先尝试自己的窄重套；panel/world 使用样本 ID，
        -- runtime 使用真实 slot ID，三者不能再共用同一份 GetOrderedSlots()。
        if panelSurface and type(panelSurface.ReapplyPanelPresentation) == "function" then
            panelSurface:ReapplyPanelPresentation()
        end
        reapply(panelPreview, sampleSlots, false)
        if panelDock and panelCollection then
            local _, height = panelCollection:GetBounds()
            panelDock:SetHeight(math.max(60, (height or 0) + 28))
        end
        reapply(worldCollection, sampleSlots, false)
        reapply(runtimeCollection, GetOrderedSlots(), true)
    end,
    -- 拖动只把已物化的 Panel Item 打补丁；旧字段补丁 不创建/释放 Item，
    -- 结构字段返回 requiresRebuild，由鼠标放开后的正式刷新统一处理。
    schemaPaths = {
        ["anchorX"] = true, ["anchorY"] = true,
        ["attachToCustom"] = true, ["customAttachTarget"] = true,
        ["layout.direction"] = true, ["layout.spacing"] = true, ["layout.maxVisible"] = true,
        ["font_spell.x"] = true, ["font_spell.y"] = true,
        ["font_spell.size"] = true, ["font_spell.shadowX"] = true, ["font_spell.shadowY"] = true,
        ["font_spell.autoWidth"] = true, ["font_spell.fixedWidth"] = true, ["font_spell.maxWidth"] = true,
        ["font_spell.gradientStart"] = true, ["font_spell.gradientLength"] = true, ["font_spell.rotation"] = true,
        ["font_timer.x"] = true, ["font_timer.y"] = true,
        ["font_timer.size"] = true, ["font_timer.shadowX"] = true, ["font_timer.shadowY"] = true,
        ["font_timer.autoWidth"] = true, ["font_timer.fixedWidth"] = true, ["font_timer.maxWidth"] = true,
        ["font_timer.gradientStart"] = true, ["font_timer.gradientLength"] = true, ["font_timer.rotation"] = true,
        ["timerGroup.width"] = true, ["timerGroup.height"] = true,
        ["timerGroup.borderSize"] = true, ["timerGroup.borderPadding"] = true,
        ["timerGroup.iconOffsetX"] = true, ["timerGroup.iconWidth"] = true,
        ["timerGroup.iconHeight"] = true, ["timerGroup.iconOffsetY"] = true,
        ["timerGroup.iconBorderSize"] = true, ["timerGroup.iconBorderPadding"] = true,
    },
})

local function RefreshActiveSurfaces(_, changedPath, phase)
    local patched = STANDARD_CONFIG_BINDING.reapplyExisting()
    if changedPath == "enabled" then
        -- 标准 binding 只会重套已有 Item；总开关还必须终止当前运行序列。
        CastBar:RefreshVisuals({ rebuildPanelPreview = phase == "committed" })
    end
    return patched
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 唯一正式 Panel session：相同 CastProgressBar/Dock 只 Render，切 Dock 或页面
-- 隐藏则由 surface 先清理旧 hitbox 与 pool 引用。
panelSurface = EXUI:CreateStandardPreviewSurface({
    moduleKey = MODULE_KEY,
    kind = "timerbar",
    buildPresentation = BuildCastProgressPanelPresentation,
    interactionSchema = INTERACTION_SCHEMA,
    requiredPositionGuiKeys = { "font_spell", "font_timer" },
})
