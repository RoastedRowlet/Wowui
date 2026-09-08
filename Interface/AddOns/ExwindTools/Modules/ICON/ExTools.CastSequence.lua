-- =============================================================
-- 施法序列：业务状态 + 标准 IconCollection presentation
-- 中央只拥有通用 Collection、Anchor、Panel 与 World 生命周期。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.CastSequence"
local RefreshActiveSurfaces

-- 所有预设、所有 Grid 几何以及全部可见元素的类型均在本模块声明。
-- 中央只校验和消费声明，绝不保存施法序列的专属预设或生成坐标。
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 1,
    features = { cooldown = true, timeText = true },
    textSlots = { time = L["倒数文字"] },
    commands = {
        btn_addIgnore = "toggleIgnoreSpell",
        btn_showIgnore = "showIgnoredSpells",
        btn_clearIgnore = "clearIgnoredSpells",
    },
    anchor = {
        dbPath = "$root",
        xKey = "posX",
        yKey = "posY",
        defaultX = -7,
        defaultY = -201,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 36,
        initialHeight = 36,
        clampedToScreen = false,
        bindRoot = true,
    },
    defaults = {
        font_time = {
            a = 1,
            autoWidth = false,
            b = 1,
            enabled = false,
            fixedWidth = 200,
            font = "默认",
            g = 1,
            gradientEnabled = false,
            gradientLength = 0,
            gradientStart = 0,
            justifyH = "CENTER",
            justifyV = "MIDDLE",
            maxWidth = 0,
            outline = "OUTLINE",
            r = 1,
            rotation = 0,
            shadow = true,
            shadowColorA = 1,
            shadowColorB = 0,
            shadowColorG = 0,
            shadowColorR = 0,
            shadowX = 1,
            shadowY = -1,
            size = 14,
            x = 0,
            y = 0,
        },
        icon = {
            alpha = 1,
            borderColorA = 1,
            borderColorB = 0,
            borderColorG = 0,
            borderColorR = 0,
            borderPadding = 0.6,
            borderSize = 0,
            borderTexture = "EX_Default",
            cooldown = {
                edgeAlpha = 1,
                showBling = false,
                showEdge = true,
                showSwipe = true,
                swipeAlpha = 0.65,
            },
            cropBottom = 0,
            cropLeft = 0,
            cropRight = 0,
            cropTop = 0,
            enableCrop = true,
            height = 36,
            reverse = false,
            rotation = 0,
            showBorder = true,
            showCooldown = true,
            showIcon = true,
            width = 36,
        },
        layout = {
            direction = "RIGHT",
            maxPerRow = 8,
            maxVisible = 8,
            spacing = 3.6,
            wrapDirection = "DOWN",
        },
        root = {
            attachToCustom = false,
            customAttachTarget = "",
            enabled = true,
            ignoreSpellId = "",
            ignoredSpellIds = {
            },
            posX = 454,
            posY = -394,
            showTooltip = true,
            squareAmount = 8,
        },
    },
    preview = {
        positionGuiKeys = { "font_time" },
        elements = {
            ["core.time"] = {
                guiKey = "font_time", movable = true, textRole = "time", tooltip = L["倒数文字"],
                position = { x = "font_time.x", y = "font_time.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
            ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["施法序列"] },
        },
        records = {
            { spellId = 116, icon = 134851, spellName = "寒冰箭", previewRemaining = 3, previewDuration = 5 },
            { spellId = 44425, icon = 135732, spellName = "奥术弹幕", previewRemaining = 4, previewDuration = 5 },
            { spellId = 190356, icon = 135838, spellName = "冰冷血脉", previewRemaining = 2, previewDuration = 5 },
            { spellId = 2139, icon = 135856, spellName = "反制", previewRemaining = 1, previewDuration = 5 },
            { spellId = 31661, icon = 135812, spellName = "龙息术", previewRemaining = 5, previewDuration = 5 },
        },
    },
    gui = {
        fields = {
            {
                group = "settings",
                h = 22,
                key = "moduleCommon",
                label = L["模块通用设置"],
                measure = true,
                options = {
                    bindRoot = true,
                    fields = {
                        {
                            column = 1,
                            label = L["启用"],
                            path = "enabled",
                            row = 1,
                            type = "checkbox",
                        },
                        {
                            column = 2,
                            label = L["运行时悬停提示"],
                            path = "showTooltip",
                            row = 1,
                            type = "checkbox",
                        },
                        {
                            column = 3,
                            label = L["保留施法数量"],
                            max = 20,
                            min = 3,
                            path = "squareAmount",
                            row = 1,
                            step = 1,
                            type = "slider",
                        },
                    },
                    fixedLayout = {
                        controlH = 6,
                        controlW = 46,
                        firstY = 0,
                        logicalWidth = 200,
                        rowStep = 14,
                        slotX = {
                            3,
                            53,
                            103,
                            153,
                        },
                    },
                },
                order = 1,
                type = "modulecommonsettings",
                w = 200,
                x = 1,
                y = 11,
            },
            {
                group = "settings",
                h = 20,
                key = "anchor",
                label = L["锚点设置"],
                measure = true,
                order = 2,
                type = "anchorgroup",
                w = 200,
                x = 1,
                y = 33,
            },
            {
                group = "settings",
                h = 20,
                key = "layout",
                label = L["排列设置"],
                measure = true,
                options = {
                    allowedDirections = {
                        "RIGHT",
                        "LEFT",
                        "UP",
                        "DOWN",
                        "CENTER_HORIZONTAL",
                        "CENTER_VERTICAL",
                    },
                    defaultMaxVisible = 8,
                    includeMaxPerRow = false,
                    maxVisibleMax = 20,
                    maxVisibleMin = 1,
                },
                order = 3,
                type = "widgetlayout",
                w = 200,
                x = 1,
                y = 55,
            },
            {
                group = "settings",
                h = 50,
                key = "icon",
                label = L["图标本体"],
                labelSize = 20,
                order = 4,
                type = "icongroup",
                w = 200,
                x = 1,
                y = 77,
            },
            {
                group = "settings",
                h = 50,
                key = "font_time",
                label = L["倒数文字"],
                labelSize = 20,
                order = 5,
                type = "fontgroup",
                w = 200,
                x = 1,
                y = 130,
            },
            {
                group = "settings",
                h = 6,
                key = "ignoreSpellId",
                label = L["法术ID"],
                labelPos = "top",
                order = 6,
                type = "input",
                w = 46,
                x = 3,
                y = 194,
            },
            {
                group = "settings",
                h = 6,
                key = "btn_addIgnore",
                label = L["添加/移除"],
                order = 7,
                type = "button",
                w = 46,
                x = 53,
                y = 194,
            },
            {
                group = "settings",
                h = 6,
                key = "btn_showIgnore",
                label = L["显示列表"],
                order = 8,
                type = "button",
                w = 46,
                x = 103,
                y = 194,
            },
            {
                group = "settings",
                h = 6,
                key = "btn_clearIgnore",
                label = L["清空列表"],
                order = 9,
                type = "button",
                w = 46,
                x = 153,
                y = 194,
            },
        },
        groups = {
            {
                key = "settings",
                order = 1,
            },
        },
        static = {
            {
                h = 6,
                key = "header",
                label = L["施法序列"],
                labelSize = 25,
                type = "header",
                w = 200,
                x = 1,
                y = 1,
            },
            {
                h = 7,
                key = "sub_ignore",
                label = L["忽略法术"],
                labelSize = 20,
                type = "subheader",
                w = 200,
                x = 1,
                y = 183,
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

-- =============================================================
-- 玩家施法追踪：仅维护业务记录，绝不持有任何可见 Frame。
-- =============================================================

local ignoredSpells = { [49821] = true, [121557] = true }
local castContent, casts = {}, {}
local lastDisplayedSpell = {}
local lastCastId, lastChannelId, lastSpellId

local function Number(value, fallback)
    return tonumber(value) or fallback
end

local function GetSpellInfo(spellID)
    local info = _G.C_Spell and _G.C_Spell.GetSpellInfo(spellID)
    return info and info.name or nil, info and info.iconID or nil
end

local function BuildLayout()
    local layout = LAYOUT or {}
    local amount = math.max(3, math.floor(Number(DB.squareAmount, 8)))
    local direction = layout.direction
    local allowedDirections = {
        RIGHT = true,
        LEFT = true,
        UP = true,
        DOWN = true,
        CENTER_HORIZONTAL = true,
        CENTER_VERTICAL = true,
    }
    return {
        mode = "FLOW",
        direction = allowedDirections[direction] and direction or "RIGHT",
        spacing = Number(layout.spacing, 0),
        maxVisible = math.min(amount, math.max(1, math.floor(Number(layout.maxVisible, amount)))),
    }
end

local function CreateDurationFromRecord(record)
    if not record.expirationTime or not record.durationSeconds then return nil end
    local durationUtil = _G.C_DurationUtil
    if not durationUtil or type(durationUtil.CreateDuration) ~= "function" then return nil end
    local duration = durationUtil.CreateDuration()
    duration:SetTimeFromEnd(record.expirationTime, record.durationSeconds, record.modRate or 1)
    return duration
end

local function BuildPresentation(record, isPreview)
    local icon = DB.icon or {}
    local width = math.max(16, Number(icon.width, 36))
    local height = math.max(16, Number(icon.height, 36))
    local cooldown
    if isPreview then
        cooldown = { static = true, remaining = Number(record.previewRemaining, 3), duration = Number(record.previewDuration, 5) }
    else
        local duration = CreateDurationFromRecord(record)
        if duration then cooldown = { mode = "DURATION", duration = duration, clearIfZero = true } end
    end
    return {
        style = { icon = icon, text = { countdown = DB.font_time or {} } },
        icon = record.icon,
        cooldown = cooldown,
        bodySize = { width = width, height = height },
        declaredBounds = { left = -width / 2, right = width / 2, bottom = -height / 2, top = height / 2 },
        runtimeTooltip = (not isPreview and DB.showTooltip and record.spellId) and { spellID = record.spellId } or nil,
        interaction = EXUI:BuildStandardPreviewInteraction("Icon", DB, MODULE_SPEC.preview.elements),
    }
end

local function SetStandardPreview()
    local entries = {}
    for index, record in ipairs(MODULE_SPEC.preview.records) do
        entries[#entries + 1] = { itemID = "cast-preview-" .. index, presentation = BuildPresentation(record, true) }
    end
    central:SetPreview(entries, BuildLayout())
end

local function PublishRecords()
    local amount = math.max(3, math.floor(Number(DB.squareAmount, 8)))
    local entries = {}
    for index = 1, math.min(amount, #castContent) do
        local source = castContent[index]
        local cast = source and casts[source.castID]
        if source then
            entries[#entries + 1] = {
                itemID = "cast-" .. index,
                presentation = BuildPresentation({
                castID = source.castID, spellId = source.spellId, spellName = source.spellName, icon = source.icon,
                expirationTime = source.expirationTime, durationSeconds = source.durationSeconds, modRate = source.modRate,
                interrupted = cast and cast.interrupted and not cast.isChanneled or false,
                }),
            }
        end
    end
    if DB.enabled ~= true then central:Clear(); return end
    central:SetRuntime(entries, BuildLayout())
end

RefreshActiveSurfaces = function(controller)
    -- direction / spacing / maxVisible are not presentation fields.  Reproject
    -- them from the current DB so the central controller can reapply the same
    -- already-materialized items immediately on every active surface.
    controller.previewLayout = BuildLayout()
    controller.runtimeLayout = BuildLayout()
    local preview = controller.previewEntries or {}
    for index, record in ipairs(MODULE_SPEC.preview.records) do
        if preview[index] then preview[index].presentation = BuildPresentation(record, true) end
    end
    local runtime = controller.runtimeEntries or {}
    for index, source in ipairs(castContent) do
        local entry = runtime[index]
        local cast = source and casts[source.castID]
        if entry and source and DB.enabled == true then
            entry.presentation = BuildPresentation({
                castID = source.castID, spellId = source.spellId, spellName = source.spellName, icon = source.icon,
                expirationTime = source.expirationTime, durationSeconds = source.durationSeconds, modRate = source.modRate,
                interrupted = cast and cast.interrupted and not cast.isChanneled or false,
            }, false)
        end
    end
end

SetStandardPreview()

local function AddCast(castID, spellID, startTime, endTime)
    if not spellID or ignoredSpells[spellID] or (DB.ignoredSpellIds and DB.ignoredSpellIds[spellID]) then return end
    local now = GetTime()
    if lastDisplayedSpell.id == spellID and now - (lastDisplayedSpell.time or 0) < .4 then return end
    lastDisplayedSpell.id, lastDisplayedSpell.time = spellID, now
    local name, icon = GetSpellInfo(spellID)
    local expirationTime = endTime or now + 1.2
    local durationSeconds = math.max(0.01, expirationTime - (startTime or now))
    table.insert(castContent, 1, {
        castID = castID, spellId = spellID, spellName = name, icon = icon, castStart = now,
        expirationTime = expirationTime, durationSeconds = durationSeconds, modRate = 1,
    })
    table.remove(castContent, math.max(3, math.floor(Number(DB.squareAmount, 8))) + 1)
    PublishRecords()
end

local function StartCast(castID)
    local cast = casts[castID]
    if not cast or cast.displayed then return end
    cast.displayed = true
    AddCast(castID, cast.spellId, cast.startedAt, cast.endedAt)
end

local function FinishCast(castID)
    local cast = casts[castID]
    if not cast or cast.displayed then return end
    cast.displayed = true
    AddCast(castID, cast.spellId, GetTime(), GetTime() + 1.2)
end

local function MarkInterrupted(castID, isChannel)
    local cast = casts[castID]
    if not cast then return end
    cast.interrupted, cast.isChanneled, cast.done = true, isChannel == true, true
    for _, record in ipairs(castContent) do
        if record.castID == castID then record.expirationTime = GetTime(); break end
    end
    PublishRecords()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local unit, castID, spellID = ...
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        local _, _, guid, id = ...
        castID, spellID = guid, id
        casts[castID] = casts[castID] or { id = castID, startedAt = GetTime(), spellId = spellID }
        casts[castID].spellId = spellID
        lastCastId, lastSpellId = castID, spellID
    elseif event == "UNIT_SPELLCAST_START" then
        local cast = casts[castID]
        if cast then
            cast.spellId = spellID
            local _, _, _, startedAt, endedAt = UnitCastingInfo("player")
            cast.startedAt, cast.endedAt = startedAt and startedAt / 1000, endedAt and endedAt / 1000
            StartCast(castID)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        castID = castID ~= "" and castID or lastCastId
        local cast = casts[castID]
        if cast then
            cast.spellId, cast.isChanneled = spellID or lastSpellId, true
            lastChannelId = castID
            local _, _, _, startedAt, endedAt = UnitChannelInfo("player")
            cast.startedAt, cast.endedAt = startedAt and startedAt / 1000, endedAt and endedAt / 1000
            StartCast(castID)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        MarkInterrupted(castID, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        MarkInterrupted(lastChannelId, true)
        lastChannelId = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local cast = casts[castID]
        if cast then cast.success = true; FinishCast(castID) end
    end
end)

local function StartTracking()
    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    }) do
        eventFrame:RegisterEvent(event)
    end
end

local function StopTracking()
    eventFrame:UnregisterAllEvents()
end

ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY, function(message)
    local command = message and MODULE_SPEC.commands[message.key]
    if command == "toggleIgnoreSpell" then
        local spellID = tonumber(DB.ignoreSpellId)
        if not spellID then return end
        DB.ignoredSpellIds = DB.ignoredSpellIds or {}
        DB.ignoredSpellIds[spellID] = not DB.ignoredSpellIds[spellID]
        DB.ignoreSpellId = ""
        PublishRecords()
    elseif command == "clearIgnoredSpells" then
        DB.ignoredSpellIds = {}
        PublishRecords()
    elseif command == "showIgnoredSpells" then
        local ids = {}
        for spellID in pairs(DB.ignoredSpellIds or {}) do ids[#ids + 1] = spellID end
        table.sort(ids)
        print("EXUI " .. L["施法序列"] .. " " .. L["忽略法术"] .. ": " .. (#ids > 0 and table.concat(ids, ", ") or L["无"]))
    end
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    castContent = {}
    for key in pairs(casts) do casts[key] = nil end
    PublishRecords()
    if DB.enabled then StartTracking() else StopTracking() end
end)

ExwindTools:ReportReady(MODULE_KEY)
