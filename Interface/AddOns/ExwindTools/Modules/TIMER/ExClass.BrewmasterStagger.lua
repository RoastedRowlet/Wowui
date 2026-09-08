-- =============================================================
-- 模块职责
-- 酒仙酒池：读取玩家酒池数值、按阈值决定颜色，并向中央 TimerBar
-- 提交声明式 presentation。模块不创建任何显示 Frame、Panel 或锚点。
-- =============================================================

-- =============================================================
-- 运行时依赖与模块身份
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI, L = ExwindTools.UI, ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY, BREWMASTER_SPEC_ID, STAGGER_SPELL_ID = "ExClass.BrewmasterStagger", 268, 115069
local RefreshActiveSurfaces, SyncRuntimeEventWatches

-- =============================================================
-- 标准 TimerBar 槽位声明
-- timerGroup 是条体唯一 DB；font_spell 是主文字唯一 DB。
-- textB / textC 为可选标准槽位，本模块目前不启用。
-- =============================================================
local TIMER_SCHEMA = ExwindTools.StandardTimerBar.NormalizeSchema({
    timerBarKey = "timerGroup",
    layoutKey = "layout",
    offsetXKey = false,
    offsetYKey = false,
    showTextBKey = false,
    showTextCKey = false,
    textA = { key = "font_spell", gridKey = "font_spell", role = "spellName", label = L["酒池文字样式"] },
    textB = { key = "font_target", gridKey = "font_target", role = "targetName", label = L["目标名称"], optional = true },
    textC = { key = "font_timer", gridKey = "font_timer", role = "time", label = L["时间"], optional = true },
})
-- =============================================================
-- 模块声明：唯一默认 DB、中央锚点、预览元素与设置页几何
-- =============================================================
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "timerbar",
    defaults = {
        root = {
            attachToCustom = false,
            customAttachTarget = "",
            dangerColorA = 1,
            dangerColorB = 0.114,
            dangerColorG = 0.055,
            dangerColorR = 1,
            dangerEnabled = true,
            dangerThresholdValue = "140",
            enabled = true,
            extraColor1A = 1,
            extraColor1B = 0.965,
            extraColor1Enabled = true,
            extraColor1G = 0.114,
            extraColor1R = 1,
            extraColor1ThresholdValue = "180",
            extraColor2A = 1,
            extraColor2B = 1,
            extraColor2Enabled = false,
            extraColor2G = 0.2,
            extraColor2R = 0.75,
            extraColor2ThresholdValue = "300",
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
                size = 22,
                x = -7,
                y = 0,
            },
            fullBarPercent = 200,
            hideBar = false,
            hideOnMounted = false,
            layout = {
                direction = "DOWN",
                maxVisible = 1,
                spacing = 0,
            },
            posX = -16,
            posY = -130,
            showText = true,
            textAlign = "CENTER",
            textColorFollowsBar = false,
            textValueOnly = false,
            timerGroup = {
                barBgColorA = 0.5,
                barBgColorB = 0,
                barBgColorG = 0,
                barBgColorR = 0,
                barColorA = 1,
                barColorB = 1,
                barColorG = 0.9098,
                barColorR = 0.2902,
                borderColorA = 1,
                borderColorB = 0,
                borderColorG = 0,
                borderColorR = 0,
                borderPadding = 0.6,
                borderSize = 0.90000003576279,
                borderTexture = "EX_Default",
                fillDirection = "LEFT_TO_RIGHT",
                fillMode = "RTL_DRAIN",
                height = 35,
                iconBorderColorA = 1,
                iconBorderColorB = 0,
                iconBorderColorG = 0,
                iconBorderColorR = 0,
                iconBorderPadding = 0.6,
                iconBorderSize = 0,
                iconBorderTexture = "EX_Default",
                iconHeight = 35,
                iconOffsetX = -2,
                iconOffsetY = 0,
                iconSide = "LEFT",
                iconWidth = 35,
                progressMode = "REMAINING",
                showBorder = true,
                showIcon = true,
                showIconBorder = true,
                texture = "EX_WhiteTexture",
                width = 250,
                x = 0,
                y = 0,
            },
            warningColorA = 1,
            warningColorB = 0,
            warningColorG = 1,
            warningColorR = 0.988,
            warningEnabled = true,
            warningThresholdValue = "70",
        },
    },
    -- 主 Region 锚点：posX / posY 属于模块根 DB，不属于 timerGroup。
    anchor = { dbPath = "$root", bindRoot = true, xKey = "posX", yKey = "posY", defaultX = -16, defaultY = -130, attachEnabledKey = "attachToCustom", attachTargetKey = "customAttachTarget", initialWidth = 220, initialHeight = 30, clampedToScreen = true },
    -- 中央 TimerBar owner 使用上方 TIMER_SCHEMA 解析标准控件。
    timerBar = { schema = TIMER_SCHEMA },
    -- 编辑预览：仅主文字可在条体内局部拖动。
    preview = { positionGuiKeys = { "font_spell" }, elements = { ["core.spellName"] = { guiKey = "font_spell", movable = true, textRole = "spellName", tooltip = L["酒池文字样式"], position = { x = "font_spell.x", y = "font_spell.y" } } } },
    -- 设置页：所有控件均声明绝对 x/y/w/h，不使用流式布局。
    gui = {
        fields = {
            {
                h = 18,
                key = "anchor",
                label = L["锚点设置"],
                measure = true,
                type = "anchorgroup",
                w = 200,
                x = 1,
                y = 36,
            },
            {
                h = 50,
                key = "timerGroup",
                label = L["酒池条样式"],
                measure = true,
                type = "timerbargroup",
                w = 200,
                x = 1,
                y = 108,
            },
            {
                h = 50,
                key = "font_spell",
                label = L["酒池文字样式"],
                type = "fontgroup",
                w = 200,
                x = 1,
                y = 161,
            },
        },
        static = {
            {
                h = 8,
                key = "header",
                label = L["酒仙酒池监控"],
                labelSize = 25,
                type = "header",
                w = 200,
                x = 1,
                y = 1,
            },
            {
                h = 4,
                key = "subheader_general",
                label = L["酒池基础设置"],
                labelSize = 20,
                type = "subheader",
                w = 200,
                x = 1,
                y = 11,
            },
            {
                h = 6,
                key = "enabled",
                label = L["启用酒池条"],
                type = "checkbox",
                w = 46,
                x = 4,
                y = 17,
            },
            {
                h = 6,
                key = "showText",
                label = L["显示文字"],
                type = "checkbox",
                w = 46,
                x = 54,
                y = 17,
            },
            {
                h = 6,
                key = "hideBar",
                label = L["隐藏条体"],
                type = "checkbox",
                w = 46,
                x = 104,
                y = 17,
            },
            {
                h = 6,
                key = "hideOnMounted",
                label = L["骑乘时隐藏"],
                type = "checkbox",
                w = 46,
                x = 154,
                y = 17,
            },
            {
                h = 6,
                key = "textColorFollowsBar",
                label = L["文字跟随条体颜色"],
                type = "checkbox",
                w = 46,
                x = 4,
                y = 27,
            },
            {
                h = 6,
                key = "textValueOnly",
                label = L["仅显示数值"],
                type = "checkbox",
                w = 46,
                x = 54,
                y = 27,
            },
            {
                h = 6,
                key = "fullBarPercent",
                label = L["满条映射上限 (%)"],
                max = 500,
                min = 50,
                step = 1,
                type = "slider",
                w = 46,
                x = 104,
                y = 27,
            },
            {
                h = 6,
                key = "btn_reset_pos",
                label = L["重置酒池位置"],
                type = "button",
                w = 46,
                x = 154,
                y = 27,
            },
            {
                h = 4,
                key = "subheader_value",
                label = L["酒池数值与阈值"],
                labelSize = 20,
                type = "subheader",
                w = 197,
                x = 1,
                y = 57,
            },
            {
                h = 6,
                key = "warningEnabled",
                label = L["启用"],
                type = "checkbox",
                w = 46,
                x = 4,
                y = 67,
            },
            {
                h = 6,
                key = "warningThresholdValue",
                label = L["阶段一(%)"],
                type = "input",
                w = 46,
                x = 54,
                y = 67,
            },
            {
                h = 6,
                key = "warningColor",
                label = L["阶段一颜色"],
                type = "color",
                w = 46,
                x = 104,
                y = 67,
            },
            {
                h = 6,
                key = "dangerEnabled",
                label = L["启用"],
                type = "checkbox",
                w = 46,
                x = 4,
                y = 77,
            },
            {
                h = 6,
                key = "dangerThresholdValue",
                label = L["阶段二(%)"],
                type = "input",
                w = 46,
                x = 54,
                y = 77,
            },
            {
                h = 6,
                key = "dangerColor",
                label = L["阶段二颜色"],
                type = "color",
                w = 46,
                x = 104,
                y = 77,
            },
            {
                h = 6,
                key = "extraColor1Enabled",
                label = L["启用"],
                type = "checkbox",
                w = 46,
                x = 4,
                y = 87,
            },
            {
                h = 6,
                key = "extraColor1ThresholdValue",
                label = L["阶段三(%)"],
                type = "input",
                w = 46,
                x = 54,
                y = 87,
            },
            {
                h = 6,
                key = "extraColor1",
                label = L["阶段三颜色"],
                type = "color",
                w = 46,
                x = 104,
                y = 87,
            },
            {
                h = 6,
                key = "extraColor2Enabled",
                label = L["启用"],
                type = "checkbox",
                w = 46,
                x = 4,
                y = 97,
            },
            {
                h = 6,
                key = "extraColor2ThresholdValue",
                label = L["阶段四(%)"],
                type = "input",
                w = 46,
                x = 54,
                y = 97,
            },
            {
                h = 6,
                key = "extraColor2",
                label = L["阶段四颜色"],
                type = "color",
                w = 46,
                x = 104,
                y = 97,
            },
        },
    },
}

-- =============================================================
-- 中央注册与唯一模块 DB
-- DeclareModuleSpecDefaults 只补模块自己的默认值；DB 是唯一持久数据。
-- RegisterTimerBarModule 后，中央 owner 接管 Panel / World / Runtime 显示。
-- =============================================================
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterTimerBarModule(MODULE_SPEC)
local LAYOUT = DB.layout

-- =============================================================
-- 业务数据：阈值颜色
-- 从模块 DB 读取各阶段颜色；未命中阶段时使用 timerGroup 基础条体颜色。
-- =============================================================
local function GetColor(key) return DB[key .. "R"] or 1, DB[key .. "G"] or 1, DB[key .. "B"] or 1, DB[key .. "A"] or 1 end
local function BarColor(percent)
    local best, color = -1, nil
    for _, row in ipairs({ { "warningEnabled", "warningThresholdValue", "warningColor" }, { "dangerEnabled", "dangerThresholdValue", "dangerColor" }, { "extraColor1Enabled", "extraColor1ThresholdValue", "extraColor1" }, { "extraColor2Enabled", "extraColor2ThresholdValue", "extraColor2" } }) do
        local threshold = tonumber(DB[row[2]]); if DB[row[1]] and threshold and percent >= threshold and threshold >= best then
            best, color =
                threshold, row[3]
        end
    end
    if color then return GetColor(color) end
    local style = DB.timerGroup; return style.barColorR or .52, style.barColorG or 1, style.barColorB or .52,
        style.barColorA or 1
end

-- =============================================================
-- 业务数据：酒池数值
-- sample=true 仅用于设置页预览；false 读取玩家当前生命与酒池数值。
-- =============================================================
local function GetInfo(sample)
    local full = math.max(1, DB.fullBarPercent or 100)
    local percent, value, maximum
    if sample then
        percent, value, maximum = math.min(full, math.max(full * .55, 100)),
            math.min(full, math.max(full * .55, 100)), full
    else
        local health, stagger = UnitHealthMax("player") or 0, UnitStagger("player") or 0; percent, value, maximum =
            health > 0 and stagger / health * 100 or 0, stagger, health * full / 100
    end
    return {
        percent = percent,
        value = value,
        maximum = math.max(1, maximum),
        icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(STAGGER_SPELL_ID)) or
            608951
    }
end

-- =============================================================
-- presentation 构建
-- 将当前业务值、运行时颜色和非持久显示覆盖值交给中央标准 TimerBar。
-- 不复制 DB，也不直接操作任何显示对象。
-- =============================================================
local function BuildEntry(itemID, sample)
    local info = GetInfo(sample); local r, g, b, a = BarColor(info.percent)
    local labelOverrides = { justifyH = DB.textAlign or DB.font_spell.justifyH }
    if DB.textColorFollowsBar then labelOverrides.r, labelOverrides.g, labelOverrides.b, labelOverrides.a = r, g, b, a end
    local styleOverrides = { text = { label = labelOverrides } }
    if DB.hideBar then styleOverrides.timerBar = { showBorder = false, barBgColorA = 0 } end
    local text = DB.textValueOnly and string.format("%.0f", info.percent) or string.format("%.0f%%", info.percent); if not (DB.showText or DB.hideBar) then
        text =
        ""
    end
    return { itemID = itemID, presentation = { schema = TIMER_SCHEMA, db = DB, styleOverrides = styleOverrides, content = { icon = info.icon, textA = text, progress = info.value, maximum = info.maximum }, fillColor = { r = r, g = g, b = b, a = DB.hideBar and 0 or a }, textShownFromBoolean = { B = false, C = false }, interaction = EXUI:BuildStandardPreviewInteraction("TimerBar", DB, MODULE_SPEC.preview.elements) } }
end

-- =============================================================
-- 刷新分发
-- 预览只在初始化、设置变更和用户操作时构建；Runtime 只在酒仙专精、模块启用且未被骑乘隐藏时提交。
-- =============================================================
local function IsBrewmasterRuntimeActive()
    local state = ExwindTools.State or {}
    return DB.enabled and state.ClassID == 10 and state.SpecID == BREWMASTER_SPEC_ID
        and not (DB.hideOnMounted and state.IsMounted)
end

local function RefreshPreview()
    central:SetPreview({ BuildEntry("stagger:preview", true) }, LAYOUT)
end

local function RefreshRuntime()
    if IsBrewmasterRuntimeActive() then
        central:SetRuntime({ BuildEntry("stagger:runtime", false) }, LAYOUT)
    else
        central:Clear()
    end
end

local function Refresh()
    RefreshPreview()
    RefreshRuntime()
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildEntry("stagger:preview", true).presentation
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and IsBrewmasterRuntimeActive() then
        controller.runtimeEntries[1].presentation = BuildEntry("stagger:runtime", false).presentation
    end
    if SyncRuntimeEventWatches then SyncRuntimeEventWatches() end
end

-- =============================================================
-- 酒池运行时监听
-- 非酒仙、模块关闭或按骑乘隐藏时完全取消三类高频事件订阅；激活后最多每 0.2 秒读取并提交一次。
-- =============================================================
local STAGGER_RUNTIME_EVENTS = { "UNIT_MAXHEALTH", "UNIT_HEALTH", "UNIT_AURA" }
local STAGGER_REFRESH_INTERVAL_SECONDS = 0.2
local staggerRuntimeEventsRegistered = false
local staggerRefreshQueued = false
local staggerLastRuntimeRefreshAt = -math.huge

local function GetRefreshTime()
    return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local FlushStaggerRuntimeRefresh
local function QueueStaggerRuntimeRefresh(delay)
    staggerRefreshQueued = true
    C_Timer.After(delay, FlushStaggerRuntimeRefresh)
end

FlushStaggerRuntimeRefresh = function()
    staggerRefreshQueued = false
    if not IsBrewmasterRuntimeActive() then return end

    local now = GetRefreshTime()
    local remaining = STAGGER_REFRESH_INTERVAL_SECONDS - (now - staggerLastRuntimeRefreshAt)
    if remaining > 0 then
        QueueStaggerRuntimeRefresh(remaining)
        return
    end

    staggerLastRuntimeRefreshAt = now
    RefreshRuntime()
end

local function RequestStaggerRuntimeRefresh()
    if not IsBrewmasterRuntimeActive() then
        RefreshRuntime()
        return
    end
    if staggerRefreshQueued then return end

    local remaining = STAGGER_REFRESH_INTERVAL_SECONDS - (GetRefreshTime() - staggerLastRuntimeRefreshAt)
    QueueStaggerRuntimeRefresh(math.max(0, remaining))
end

local function OnStaggerRuntimeEvent(_, unit)
    if unit == "player" then RequestStaggerRuntimeRefresh() end
end

SyncRuntimeEventWatches = function()
    local shouldObserveRuntime = IsBrewmasterRuntimeActive()
    if shouldObserveRuntime == staggerRuntimeEventsRegistered then
        if shouldObserveRuntime then
            RequestStaggerRuntimeRefresh()
        else
            central:Clear()
        end
        return
    end

    staggerRuntimeEventsRegistered = shouldObserveRuntime
    for _, event in ipairs(STAGGER_RUNTIME_EVENTS) do
        if shouldObserveRuntime then
            ExwindTools:RegisterEvent(event, MODULE_KEY, OnStaggerRuntimeEvent)
        else
            ExwindTools:UnregisterEvent(event, MODULE_KEY)
        end
    end

    if shouldObserveRuntime then
        RequestStaggerRuntimeRefresh()
    else
        central:Clear()
    end
end

-- =============================================================
-- 模块初始化
-- 先提交预览，禁用模块则不注册后续业务监听；非酒仙也不会订阅酒池高频事件。
-- =============================================================
RefreshPreview()
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then
    ExwindTools:ReportReady(MODULE_KEY); return
end
SyncRuntimeEventWatches()
-- =============================================================
-- 业务事件注册
-- DB 变化、设置页按钮和角色状态负责同步运行时订阅；酒池高频事件只申请节流刷新。
-- =============================================================
-- 设置页专属按钮：重置主 Region 锚点位置。
ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY,
    function(info)
        if info and info.key == "btn_reset_pos" then
            DB.posX, DB.posY = -16, -130; Refresh()
        end
    end)
-- 职业、专精、骑乘状态改变会重新绑定或取消酒池高频监听。
for _, key in ipairs({ "SpecID", "ClassID", "IsMounted" }) do
    ExwindTools:WatchState(key, MODULE_KEY, SyncRuntimeEventWatches)
end
-- 进世界、切换专精和天赋配置后重新判定酒池显示状态。
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY,
    function() C_Timer.After(1, SyncRuntimeEventWatches) end)
ExwindTools:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", MODULE_KEY,
    function(_, unit) if unit == "player" then C_Timer.After(0, SyncRuntimeEventWatches) end end)
ExwindTools:RegisterEvent("TRAIT_CONFIG_UPDATED", MODULE_KEY, SyncRuntimeEventWatches)

-- =============================================================
-- 模块加载完成通知
-- =============================================================
ExwindTools:ReportReady(MODULE_KEY)
