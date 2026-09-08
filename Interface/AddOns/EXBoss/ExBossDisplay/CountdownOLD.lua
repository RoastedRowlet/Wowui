---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/Countdown.lua
-- 屏幕中央倒计时
--
-- 布局：[图标] [名称] [数字]
--   runtime 倒数由原生 Duration Object 驱动；Lua 只在业务触发或原生结束通知时更新条目。
--   使用 HorizontalLayoutFrame 自动布局，不在 Lua 层计算文本宽度。
--
-- 公开接口：
--   Countdown:Show(timer)       开始倒计时
--   Countdown:Stop()            提前终止
--   Countdown:RefreshVisuals()  设置变化后刷新
--
-- Show 输入约定：
--   textMode = "SECRET" 时，displayName 只能直传给 SetSecretText；不会读文字
--   宽度、不会拼接或判断内容。
--   iconMode = "SECRET" 时，iconFileID 只能直传给 SetSecretIcon；不会尝试
--   从 spellID 解析图标。两个 mode 均是调用方提供的普通字符串。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end

ExBoss.UI.Countdown = ExBoss.UI.Countdown or {}
local Countdown     = ExBoss.UI.Countdown
local MODULE_KEY    = "ExBoss.Countdown"
local L             = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local anchorController = nil
local anchorGroupOptions = nil
local anchorFrame = nil
local runtimeCollection = nil
local worldCollection = nil
local panelPreview = nil
local panelSurface = nil
local panelDock = nil
local worldEditing = false
local _entries = {}
local _entrySeq = 0
local ANCHOR_WIDTH = 200
local SIDE_GAP = 2
-- Preview is an inspection surface, not a runtime stack.  It must keep room
-- for at least two rows even when the user has configured one runtime entry.
-- The final lower bound is derived from the current row style below.
local PANEL_PREVIEW_BASE_HEIGHT = 160
local PANEL_PREVIEW_MIN_ROWS = 2
local StopAll = nil
local RenderCollection = nil
local CancelRuntimeEntryExpiry = nil
local RemoveRuntimeEntryByID = nil
local ScheduleRuntimeEntryExpiry = nil
-- INTERACTION_SCHEMA 的纯坐标换算会在 panel 实际拖动时调用这两个 helper；
-- 先前置声明，避免 Lua 在 schema 建立时错误捕获 global nil。
local EnsureCountdownIconDB = nil
local ResolveCountdownIconRootAnchor = nil

-- 显示层备注：
-- Countdown 只负责最终显示，不承担 fixed/blizzard 业务判断。
-- 无特殊情况禁止修改本模块的显示结构；若需变更，优先在调度层/分发层整理输入参数。

-- =============================================================
-- DB 访问
-- =============================================================
local function DB()
    return ExwindTools:GetModuleDB(MODULE_KEY)
end

local function SafeNum(v, def) return tonumber(v) or def end
local ANCHOR_SCHEMA = nil

local function EnsureAnchorController()
    if anchorController then
        return anchorController
    end

    anchorController, anchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)

    return anchorController
end

local EX_DEFAULTS = {
    module = {
        enabled = true,
        showDecimal = true,
        stackMax_1205 = 2,
        stackGap = 4,
        growDir = "UP",
        anchorX_1205 = 0,
        anchorY_1205 = 40,
        attachToCustom = false,
        customAttachTarget = "",
    },
    icon = {
        showIcon = true,
        iconID = nil,
        reverse = false,
        width = 30,
        height = 30,
        x = -1.4276948660354,
        y = -0.027044919604805,
        showBorder = true,
        borderTexture = "EX_WhiteBorder",
        borderColorR = 0,
        borderColorG = 0,
        borderColorB = 0,
        borderColorA = 1,
        borderSize = 1,
        borderPadding = 1,
        enableCrop = true,
        cropLeft = 0.099999994039536,
        cropTop = 0.089999996125698,
        showCooldown = false,
        cooldown = { edgeAlpha = 1, showBling = false, showEdge = true, showSwipe = true, swipeAlpha = 0.65 },
    },
    font_text = {
        font = "默认", size = 24, r = 1, g = 1, b = 1, a = 1,
        enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0,
        justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE",
        shadow = true, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        shadowX = 2, shadowY = -2, rotation = 0,
        gradientEnabled = false, gradientStart = 0, gradientLength = 0,
        x = 0, y = -7.197392933818,
    },
    font_time = {
        font = "默认", size = 22, r = 1, g = 1, b = 1, a = 1,
        enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0,
        justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE",
        shadow = true, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        shadowX = 2, shadowY = -2, rotation = 0,
        gradientEnabled = false, gradientStart = 0, gradientLength = 0,
        x = 4.241146506827, y = 0.79978092437017,
    },
}

local MODULE_FIELDS = {
    "enabled", "showDecimal", "stackMax_1205", "stackGap", "growDir",
    "anchorX_1205", "anchorY_1205", "attachToCustom", "customAttachTarget",
}
local COUNTDOWN_ICON_FIELDS = {
    "showIcon", "iconID", "reverse", "width", "height", "x", "y", "showBorder",
    "borderTexture", "borderColorR", "borderColorG", "borderColorB", "borderColorA",
    "borderSize", "borderPadding", "enableCrop", "cropLeft", "cropTop", "showCooldown",
    cooldown = { "edgeAlpha", "showBling", "showEdge", "showSwipe", "swipeAlpha" },
}
local FONT_FIELDS = {
    "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
    "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB",
    "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart",
    "gradientLength", "x", "y",
}
local DEFAULT_SCHEMA = {
    { group = "module", root = true, fields = MODULE_FIELDS },
    { group = "icon", fields = COUNTDOWN_ICON_FIELDS },
    { group = "font_text", fields = FONT_FIELDS },
    { group = "font_time", fields = FONT_FIELDS },
}
ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

-- Countdown 的整体锚点只在此处声明。运行时 AnchorController 与设置页
-- AnchorGroup 必须消费同一次 CreateStandardModuleAnchor 返回的合同，禁止复制
-- 正式 *_1205 字段、默认位置或 frame picker 映射。
ANCHOR_SCHEMA = {
    moduleKey = MODULE_KEY,
    frameName = "ExBoss_CountdownAnchor",
    frameTemplate = "BackdropTemplate",
    title = L["倒计时"],
    getDB = DB,
    offsetXKey = "anchorX_1205",
    offsetYKey = "anchorY_1205",
    defaultOffsetX = EX_DEFAULTS.module.anchorX_1205,
    defaultOffsetY = EX_DEFAULTS.module.anchorY_1205,
    syncWidgets = {
        "anchorX_1205",
        "anchorY_1205",
        "attachToCustom",
        "customAttachTarget",
    },
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    initialWidth = ANCHOR_WIDTH,
    initialHeight = 80,
    clampedToScreen = false,
    frameStrata = "FULLSCREEN_DIALOG",
    fixedFrameStrata = true,
    frameLevel = 100,
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    onCreateFrame = function(_, frame)
        frame:Hide()
    end,
}

function Countdown:GetStandardAnchorGroupOptions()
    EnsureAnchorController()
    return anchorGroupOptions
end

-- 倒数中央文字是整个组件的固定语义原点：编辑模式中不可拖动，也绝不参与
-- 图标或数字的坐标计算。图标与右侧数字各自保存相对该原点的偏移；Panel
-- 拖动只投影已有样本，松手后由标准交互链统一提交同一份 ModuleDB。
local INTERACTION_SCHEMA = {
    ["core.icon"] = {
        guiKey = "icon", movable = true, tooltip = L["倒计时图标"],
        position = {
            x = "icon.x", y = "icon.y",
            toStorage = function(db, position)
                local baseX, baseY = ResolveCountdownIconRootAnchor(db,
                    EnsureCountdownIconDB(db), true)
                return { x = position.x - baseX, y = position.y - baseY }
            end,
        },
    },
    ["core.label"] = {
        guiKey = "font_text", movable = false, tooltip = L["提示文字"], textRole = "label",
    },
    ["core.time"] = {
        guiKey = "font_time", movable = true, tooltip = L["倒计时数字"], textRole = "time",
        position = {
            x = "font_time.x", y = "font_time.y",
            toStorage = function(_, position)
                return { x = position.x - SIDE_GAP, y = position.y }
            end,
        },
    },
}

local CONFIG_SCHEMA_PATHS = {
    ["stackMax_1205"] = true, ["stackGap"] = true,
    ["icon.width"] = true, ["icon.height"] = true,
    ["icon.x"] = true, ["icon.y"] = true,
    ["icon.alpha"] = true, ["icon.rotation"] = true,
    ["icon.cropLeft"] = true, ["icon.cropRight"] = true,
    ["icon.cropTop"] = true, ["icon.cropBottom"] = true,
    ["icon.borderSize"] = true, ["icon.borderPadding"] = true,
    ["icon.cooldown.swipeAlpha"] = true, ["icon.cooldown.edgeAlpha"] = true,
    ["font_text.size"] = true, ["font_text.x"] = true, ["font_text.y"] = true,
    ["font_text.shadowX"] = true, ["font_text.shadowY"] = true,
    ["font_text.fixedWidth"] = true, ["font_text.maxWidth"] = true,
    ["font_text.gradientStart"] = true, ["font_text.gradientLength"] = true,
    ["font_text.rotation"] = true,
    ["font_time.size"] = true, ["font_time.x"] = true, ["font_time.y"] = true,
    ["font_time.shadowX"] = true, ["font_time.shadowY"] = true,
    ["font_time.fixedWidth"] = true, ["font_time.maxWidth"] = true,
    ["font_time.gradientStart"] = true, ["font_time.gradientLength"] = true,
    ["font_time.rotation"] = true,
}
CONFIG_SCHEMA_PATHS["font_text.autoWidth"] = true
CONFIG_SCHEMA_PATHS["font_time.autoWidth"] = true

Countdown.StandardSliderContract = {
    groupPaths = {
        moduleCommon = "",
        icon = "icon",
        font_text = "font_text",
        font_time = "font_time",
    },
}

local function ResolveCountdownTextColor(spec)
    if type(spec) ~= "table" then return nil end
    return spec.color
end

EnsureCountdownIconDB = function(db)
    if type(db) ~= "table" or type(db.icon) ~= "table" then
        error("Countdown ModuleDB.icon is unavailable", 2)
    end
    return db.icon
end

local function ResolveCountdownIconTexture(spec, db, iconMode)
    -- Secret fileID 的唯一通路：调用方显式标记后原样返回，后续只交给原生
    -- Texture:SetTexture。这里不能对它做 nil、类型、数值或字符串处理。
    if iconMode == "SECRET" then
        return spec.iconFileID
    end

    if spec.iconFileID ~= nil then
        return spec.iconFileID
    end

    local spellID = tonumber(spec.spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then
            return tex
        end
    end
    local iconDB = EnsureCountdownIconDB(db)
    local fallbackID = tonumber(iconDB.iconID)
    if fallbackID and fallbackID > 0 then
        return fallbackID
    end
    return nil
end

local function GetStackGap(db)
    return math.max(0, math.floor(SafeNum(db and db.stackGap, 4)))
end

local function GetStackMax(db)
    return math.max(1, math.floor(SafeNum(db and db.stackMax_1205, 2)))
end

local function GetGrowDirection(db)
    return (db and db.growDir == "DOWN") and "DOWN" or "UP"
end

local function GetRowHeight(db)
    local iconDB = EnsureCountdownIconDB(db)
    local showIco = iconDB.showIcon ~= false
    local icoHeight = showIco and math.max(8, SafeNum(iconDB.height, SafeNum(iconDB.width, 25))) or 0
    local labelSize = SafeNum(db.font_text.size, 46)
    local cdSize = SafeNum(db.font_time.size, 60)
    local textH = math.max(labelSize, cdSize) + 6
    return math.max(36, icoHeight, textH)
end

local function RenderRuntime()
    if not anchorFrame or not RenderCollection then return end
    if worldEditing then return end
    local db = DB()
    if #_entries <= 0 then
        if runtimeCollection then runtimeCollection:SetItems({}, { mode = "FLOW", direction = "UP", spacing = 0, maxVisible = 1 }) end
        if anchorFrame.__ExwindStandardWorldPreview ~= true then anchorFrame:Hide() end
        return
    end
    RenderCollection(runtimeCollection, _entries, db)
    anchorFrame:Show()
end

-- A Duration Object owns only the native visual. Countdown records still
-- require one explicit lifecycle action at their known expiration; this is a
-- single cancellable timer, never a renderer OnUpdate/Ticker. It prevents a
-- missing Cooldown completion event from leaving an orphaned "名称 0" row.
CancelRuntimeEntryExpiry = function(entry)
    if type(entry) ~= "table" then return end
    entry.expiryGeneration = (tonumber(entry.expiryGeneration) or 0) + 1
    local timer = entry.expiryTimer
    entry.expiryTimer = nil
    if timer and type(timer.Cancel) == "function" then timer:Cancel() end
end

RemoveRuntimeEntryByID = function(entryID)
    local wantedID = tostring(entryID or "")
    if wantedID == "" then return false end
    for index = #_entries, 1, -1 do
        local entry = _entries[index]
        if tostring(entry and entry.id or "") == wantedID then
            CancelRuntimeEntryExpiry(entry)
            table.remove(_entries, index)
            RenderRuntime()
            return true
        end
    end
    return false
end

ScheduleRuntimeEntryExpiry = function(entry, now)
    if type(entry) ~= "table" then return end
    local timers = _G.C_Timer
    if not (timers and type(timers.NewTimer) == "function") then
        error("Countdown requires C_Timer.NewTimer for one-shot record expiry", 2)
    end
    CancelRuntimeEntryExpiry(entry)
    local generation = entry.expiryGeneration
    local delay = math.max(0, SafeNum(entry.expirationTime, now) - now)
    entry.expiryTimer = timers.NewTimer(delay, function()
        if entry.expiryGeneration ~= generation then return end
        RemoveRuntimeEntryByID(entry.id)
    end)
end

-- =============================================================
-- 帧创建
-- =============================================================
local function CreateFrames()
    if anchorFrame then return end
    anchorFrame = EnsureAnchorController():Ensure()
    runtimeCollection = ExwindTools.UI:CreateIconCollection(anchorFrame, "runtime", MODULE_KEY, {
        -- Native completion is an immediate visual-lifecycle signal. The
        -- one-shot record expiry below remains the authoritative fallback.
        onCooldownDone = function(content)
            RemoveRuntimeEntryByID(content and content.itemID)
        end,
    })
end

-- =============================================================
-- 统一样本记录
-- =============================================================
-- Countdown 的运行时可以接收 Secret 文本/图标；预览绝不能接触那些值。
-- 页面与世界编辑都通过同一 BuildCountdownPresentation 物化这些普通样本。
local PREVIEW_SPELL_IDS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }

-- panel/world 样本优先从客户端法术 API 取真实名称/图标。客户端资料尚未
-- 加载、PTR 删除了某个样本法术或 API 暂时不可用时，预览仍必须可见：设置页
-- 不能因为“演示素材缺失”而物化一组空 Collection。回退只用于静态 panel/world
-- 样本，绝不进入 runtime，也绝不替换 Secret 输入。
local PREVIEW_FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark
local PREVIEW_FALLBACK_NAMES = {
    L["测试倒计时"],
    L["预览技能"],
}

local function BuildPreviewSamples()
    local samples = {}
    for index, spellID in ipairs(PREVIEW_SPELL_IDS) do
        local info = C_Spell and type(C_Spell.GetSpellInfo) == "function" and C_Spell.GetSpellInfo(spellID) or nil
        samples[#samples + 1] = {
            spellID = spellID,
            name = (info and info.name) or PREVIEW_FALLBACK_NAMES[((index - 1) % #PREVIEW_FALLBACK_NAMES) + 1],
            iconID = (info and info.iconID) or PREVIEW_FALLBACK_ICON,
            remaining = math.min(15, index * 3),
        }
    end
    return samples
end

local COUNTDOWN_TEXT_LANE_WIDTH = 180

-- IconWidget owns label/time as children，故 IconWidget 绝不能反向锚到它们；
-- 那会形成 parent -> child -> parent 锚点环。中央 label 永远固定在 ItemRoot
-- 原点，图标只依据自身偏移投影到同一坐标系，不能再被文字/数字的位置带动。
ResolveCountdownIconRootAnchor = function(db, iconDB, ignoreIconOffset)
    local iconX = ignoreIconOffset == true and 0 or SafeNum(iconDB.x, 0)
    local iconY = ignoreIconOffset == true and 0 or SafeNum(iconDB.y, 0)
    local iconWidth = math.max(1, SafeNum(iconDB.width, 24))
    if iconDB.reverse == true then
        return COUNTDOWN_TEXT_LANE_WIDTH * 0.5 + SIDE_GAP + COUNTDOWN_TEXT_LANE_WIDTH + SIDE_GAP + iconWidth * 0.5 + iconX, iconY
    end
    return -COUNTDOWN_TEXT_LANE_WIDTH * 0.5 - SIDE_GAP - iconWidth * 0.5 + iconX, iconY
end

function Countdown:GetDB()
    return DB()
end

-- =============================================================
-- BuildStandardPreviewInteraction 统一产生 semantic slot 的 guiTarget、tooltip 与
-- movable 合同；Countdown 仅补回当前 renderer 已使用的业务基线锚点，不处理
-- intent、不写 DB。三个宿主继续消费这一份 presentation。
local function BuildStandardCountdownInteraction(db)
    local interaction = EXUI:BuildStandardPreviewInteraction("Icon", db, INTERACTION_SCHEMA)
    local slots = interaction.slots
    local iconDB = EnsureCountdownIconDB(db)
    local iconX, iconY = ResolveCountdownIconRootAnchor(db, iconDB)
    local timeX, timeY = SafeNum((db.font_time or {}).x, 0), SafeNum((db.font_time or {}).y, 0)

    slots["core.icon"].positionMode = "anchor"
    slots["core.icon"].relativeSlot = "core.root"
    slots["core.icon"].anchor = { point = "CENTER", relativePoint = "CENTER", x = iconX, y = iconY }

    slots["core.label"].positionMode = "anchor"
    slots["core.label"].relativeSlot = "core.root"
    slots["core.label"].anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }

    slots["core.time"].positionMode = "anchor"
    slots["core.time"].relativeSlot = "core.spellName"
    slots["core.time"].anchor = { point = "LEFT", relativePoint = "RIGHT", x = SIDE_GAP + timeX, y = timeY }
    return interaction
end

local function BuildCountdownPresentation(entry, db, remaining, isPreview)
    local iconDB = EnsureCountdownIconDB(db)
    local label = entry.label or entry.text or ""
    local suffix = entry.suf or ""
    local icon = entry.icon
    if entry.iconMode == "SECRET" then icon = { mode = "SECRET", value = entry.icon } end
    local cooldown
    if isPreview then
        -- panel/world 只物化固定样本，绝不启动持续时间更新。
        local previewRemaining = math.max(0, SafeNum(remaining, SafeNum(entry.remaining, 3)))
        local number = db.showDecimal == false and tostring(math.ceil(previewRemaining)) or string.format("%.1f", previewRemaining)
        cooldown = {
            static = true,
            remaining = previewRemaining,
            duration = math.max(previewRemaining, SafeNum(entry.duration, 15)),
            text = number .. suffix,
        }
    else
        if not entry.durationObject then
            error("Countdown runtime entry requires a native Duration Object", 2)
        end
        -- IconCollection 原样交给 IconWidget:SetDurationObject；Cooldown 与
        -- DurationTextBinding 都由 Blizzard C++ 驱动，Lua 不读取剩余时间。
        -- The native Cooldown must clear at zero: that is what emits its formal
        -- completion event, and IconCollection:onCooldownDone then releases the
        -- entire row (icon, label, and number) together.  Keeping it shown at
        -- zero leaves an orphaned static row such as "名称 0".
        cooldown = { mode = "DURATION", duration = entry.durationObject, clearIfZero = true }
    end
    local rowH = GetRowHeight(db)
    local iconX, iconY = ResolveCountdownIconRootAnchor(db, iconDB)
    local extentY = math.max(rowH * 0.5, math.abs(SafeNum(iconDB.y, 0)) + math.max(1, SafeNum(iconDB.height, 24)) * 0.5,
        math.abs(SafeNum((db.font_time or {}).y, 0)) + rowH * 0.5)
    return {
        style = {
            -- ModuleDB 的三份样式直接作为唯一引用传入；圆形 cooldown 的
            -- 可见性是 presentation 行为，不再复制/改写 icon style。
            icon = iconDB,
            text = {
                label = db.font_text,
                countdown = db.font_time,
            },
        },
        icon = icon,
        label = entry.textMode == "SECRET" and "" or label,
        cooldown = cooldown,
        countdownTextVisible = true,
        cooldownDone = not isPreview,
        bodySize = { width = ANCHOR_WIDTH, height = rowH },
        declaredBounds = { left = -190, right = 190, bottom = -extentY, top = extentY },
        -- Countdown 的 Icon/名称/数字全是固定 core 语义；布局合同在
        -- IconCollection 内、Panel hitbox 前应用，禁止 render callback。
        coreLayout = {
            icon = {
                anchor = { point = "CENTER", relativeElement = "core.root", relativePoint = "CENTER",
                    x = iconX, y = iconY },
            },
            label = {
                bounds = { width = COUNTDOWN_TEXT_LANE_WIDTH, height = rowH },
                anchor = { point = "CENTER", relativeElement = "core.root", relativePoint = "CENTER",
                    x = 0, y = 0 },
            },
            time = {
                bounds = { width = COUNTDOWN_TEXT_LANE_WIDTH, height = rowH },
                anchor = { point = "LEFT", relativeElement = "core.label", relativePoint = "RIGHT",
                    x = SIDE_GAP + SafeNum((db.font_time or {}).x, 0), y = SafeNum((db.font_time or {}).y, 0) },
            },
        },
        interaction = BuildStandardCountdownInteraction(db),
        runtimeTooltip = (not isPreview and entry.spellID) and { spellID = entry.spellID } or nil,
    }
end

local function BuildCountdownLayout(db, minimumRows)
    return {
        mode = "FLOW", direction = GetGrowDirection(db), spacing = GetStackGap(db), maxVisible = math.max(tonumber(minimumRows) or 1, GetStackMax(db)),
    }
end

RenderCollection = function(collection, entries, db)
    if not collection then return end
    local items = {}
    for index, entry in ipairs(entries or {}) do
        local isPanelSample = entry.isPanelSample == true
        local remaining = isPanelSample and SafeNum(entry.remaining, 3) or nil
        local item = collection:AcquireItem(tostring(entry.id or ("countdown:" .. index)))
        collection:ApplyItem(item, BuildCountdownPresentation(entry, db, remaining, isPanelSample))
        if entry.textMode == "SECRET" then item.widget.labelText:SetSecretText(entry.text) end
        items[#items + 1] = item
    end
    collection:SetItems(items, BuildCountdownLayout(db))
    if collection.host == anchorFrame then
        local _, height = collection:GetBounds()
        anchorFrame:SetSize(ANCHOR_WIDTH, math.max(1, height or GetRowHeight(db)))
    end
end

local function BuildPreviewEntries(db)
    db = db or Countdown:GetDB()
    local entries, samples = {}, BuildPreviewSamples()
    -- Runtime may intentionally show one row.  The editor/world sample must
    -- always show two so spacing, growing direction and the background are
    -- inspectable; a single-row preview repeatedly hid this regression.
    local max = math.max(PANEL_PREVIEW_MIN_ROWS, GetStackMax(db))
    for index = 1, max do
        local sample = samples[((index - 1) % #samples) + 1]
        entries[#entries + 1] = {
            -- 普通倒数固定显示为 %s %t：名称区域承接名称和一个空格，
            -- 数字仍由原生 cooldown 文本区域单独渲染。
            id = "countdown-preview:" .. index, isPanelSample = true, text = sample.name .. " ",
            spellID = sample.spellID, icon = sample.iconID, remaining = sample.remaining, duration = 15,
        }
    end
    return entries
end

local function GetPanelPreviewMinHeight(db)
    local rows = PANEL_PREVIEW_MIN_ROWS
    local contentHeight = GetRowHeight(db) * rows + GetStackGap(db) * math.max(0, rows - 1)
    return math.max(PANEL_PREVIEW_BASE_HEIGHT, contentHeight + 28)
end

local function BuildPanelPreviewEntries(db)
    local entries = {}
    for index, entry in ipairs(BuildPreviewEntries(db)) do
        entries[#entries + 1] = {
            itemID = tostring(entry.id or ("countdown-preview:" .. index)),
            presentation = BuildCountdownPresentation(entry, db, entry.remaining, true),
        }
    end
    return entries
end

local function BuildCountdownPanelSurfacePresentation(_, mode)
    if mode ~= "panel" then error("Countdown panel surface only supports panel mode", 2) end
    local db = Countdown:GetDB()
    return {
        entries = BuildPanelPreviewEntries(db),
        layout = BuildCountdownLayout(db, PANEL_PREVIEW_MIN_ROWS),
    }
end

local function EnsurePanelSurface()
    if panelSurface then return panelSurface end
    panelSurface = EXUI:CreateStandardPreviewSurface({
        moduleKey = MODULE_KEY,
        kind = "icon",
        buildPresentation = BuildCountdownPanelSurfacePresentation,
        interactionSchema = INTERACTION_SCHEMA,
        requiredPositionGuiKeys = { "icon", "font_time" },
    })
    return panelSurface
end

local function ResizePanelDock()
    if panelDock then
        local _, height = panelPreview:GetBounds()
        panelDock:SetHeight(math.max(GetPanelPreviewMinHeight(Countdown:GetDB()), (height or 0) + 28))
    end
end

local function RenderPanelPreview()
    if not panelDock then return end
    local surface = EnsurePanelSurface()
    panelPreview = surface:Render({
        dock = panelDock,
        ruleKey = MODULE_KEY,
        state = BuildPreviewEntries(Countdown:GetDB()),
    })
    ResizePanelDock()
end

function Countdown:ShowPanelPreview(dock)
    if not dock then return end
    panelDock = dock
    RenderPanelPreview()
end

function Countdown:RefreshPanelPreview(dock)
    if dock then panelDock = dock end
    RenderPanelPreview()
end

function Countdown:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelDock = nil
end

function Countdown:RenderWorld(host)
    if not host then return end
    if worldCollection then worldCollection:Release() end
    worldEditing = true
    if runtimeCollection then runtimeCollection:SetItems({}, { mode = "FLOW", direction = "UP", spacing = 0, maxVisible = 1 }) end
    worldCollection = ExwindTools.UI:CreateIconCollection(host, "world", MODULE_KEY)
    local db = self:GetDB()
    RenderCollection(worldCollection, BuildPreviewEntries(db), db)
end

function Countdown:GetWorldBounds()
    return worldCollection and worldCollection:GetWorldBounds() or nil
end

function Countdown:ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    worldEditing = false
    RenderRuntime()
end

-- =============================================================
-- 停止
-- =============================================================
StopAll = function()
    for i = #_entries, 1, -1 do
        CancelRuntimeEntryExpiry(_entries[i])
        _entries[i] = nil
    end
    if anchorFrame and anchorFrame.__ExwindStandardWorldPreview ~= true then anchorFrame:Hide() end
end

-- =============================================================
-- 刷新外观
-- =============================================================
local function RefreshStyle()
    if not anchorFrame then return end
    EnsureAnchorController():ApplyPosition()
    RenderRuntime()
end

local function CreateNormalDuration(expirationTime, duration, modRate)
    if not (C_DurationUtil and type(C_DurationUtil.CreateDuration) == "function") then
        error("Countdown requires C_DurationUtil.CreateDuration for runtime countdowns", 2)
    end
    local durationObject = C_DurationUtil.CreateDuration()
    durationObject:SetTimeFromEnd(expirationTime, duration, modRate)
    return durationObject
end

-- =============================================================
-- 公开接口
-- =============================================================
function Countdown:Show(spec)
    local db = DB()
    if db.enabled == false then return end
    if not anchorFrame then CreateFrames() end
    spec = type(spec) == "table" and spec or {}
    local textMode = spec.textMode == "SECRET" and "SECRET" or "NORMAL"
    local iconMode = spec.iconMode == "SECRET" and "SECRET" or "NORMAL"
    local iconID = ResolveCountdownIconTexture(spec, db, iconMode)

    local pre, suf
    if textMode == "SECRET" then
        -- Secret 文本不能参与任何 Lua 文本判断或拼接。
        pre, suf = spec.displayName, ""
    elseif spec.rawText == true then
        pre, suf = spec.displayName, ""
    elseif type(spec.displayName) == "string" then
        -- 普通倒数固定显示为 %s %t；名称和数字由既有两个文本区域承接。
        pre, suf = spec.displayName .. " ", ""
    else
        pre, suf = "", ""
    end
    local mechanicColor = ResolveCountdownTextColor(spec)

    _entrySeq = _entrySeq + 1
    local duration = math.max(0.1, SafeNum(spec.duration, 5.0))
    local now = GetTime()
    -- Dispatcher 目前提供 duration；此处仅在业务触发时推导稳定终点。若调用方
    -- 已提供 expirationTime 则优先消费，后续刷新始终复用同一 Duration Object。
    local expirationTime = SafeNum(spec.expirationTime, now + duration)
    local modRate = SafeNum(spec.modRate, 1)
    local durationObject = CreateNormalDuration(expirationTime, duration, modRate)
    local stackMax = GetStackMax(db)
    local entry = {
        id = _entrySeq,
        durationObject = durationObject,
        duration = duration,
        expirationTime = expirationTime,
        modRate = modRate,
        text = pre,
        suf = suf or "",
        textMode = textMode,
        icon = iconID,
        iconMode = iconMode,
        color = mechanicColor,
        disableIconBorder = (spec and spec.disableIconBorder == true) or false,
    }
    table.insert(_entries, 1, entry)
    while #_entries > stackMax do
        local evicted = table.remove(_entries, #_entries)
        CancelRuntimeEntryExpiry(evicted)
    end

    ScheduleRuntimeEntryExpiry(entry, now)
    RenderRuntime()
end

function Countdown:Stop()
    StopAll()
end

function Countdown:RefreshVisuals(options)
    -- 无参调用保留旧有完整刷新；标准 Slider commit 明确标记是否需要根据
    -- 当前已物化对象无法直接处理的字段重建 Panel。
    local rebuildPanelPreview = options == nil or options.rebuildPanelPreview == true
    if not anchorFrame then CreateFrames() end
    RefreshStyle()
    local db = self:GetDB()
    RenderCollection(worldCollection, BuildPreviewEntries(db), db)
    if rebuildPanelPreview then
        RenderPanelPreview()
    end
end

function Countdown:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

-- =============================================================
-- 初始化
-- =============================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        CreateFrames()
        RefreshStyle()
    end)
end)

-- Countdown 只注册身份、纯预览与整体 anchor；Panel 右键与 Grid 回读由
-- StandardPreviewInteractions 统一拥有。世界编辑生命周期和覆盖层仍属于 Core。
ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "countdown",
    name = L["倒计时"],
    settingsPage = "countdown",
    appearanceProfile = "basicIcon",
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor = function()
        CreateFrames()
        return anchorFrame
    end,
    GetWorldBounds = function() return Countdown:GetWorldBounds() end,
    RenderWorld = function(host) return Countdown:RenderWorld(host) end,
    ReleaseWorld = function() return Countdown:ReleaseWorld() end,
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
                surface:ReapplyCurrentItems(function(presentation, item)
                    local db = DB(); local entries = surface == runtimeCollection and _entries or BuildPreviewEntries(db)
                    for _, entry in ipairs(entries) do if item and entry.id == item.id then
                        local nextPresentation = BuildCountdownPresentation(entry, db, entry.remaining, surface ~= runtimeCollection)
                        for key in pairs(presentation) do presentation[key] = nil end
                        for key, value in pairs(nextPresentation) do presentation[key] = value end
                    end end
                end)
            end
        end
        reapply(panelSurface)
        reapply(panelPreview)
        reapply(worldCollection)
        reapply(runtimeCollection)
    end,
    schemaPaths = CONFIG_SCHEMA_PATHS,
})

local function RefreshActiveSurfaces()
    return STANDARD_CONFIG_BINDING.reapplyExisting()
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })
