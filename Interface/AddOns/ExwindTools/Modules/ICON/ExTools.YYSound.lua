-- =============================================================
-- 嗜血音效：业务只提交标准 IconCollection presentation。
-- 中央只管理已存在的 Collection、Anchor、Panel 和世界编辑宿主。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.YYSound"
local RUNTIME_ITEM_ID = "yysound:runtime"
local PREVIEW_ITEM_ID = "yysound:preview"
local CD_DURATION = 40
local RefreshActiveSurfaces
local CUSTOM_SOUND_PATH_GUIDE = L["有效路径示例：Interface\\AddOns\\MySoundAddon\\Assets\\example.ogg"]

local LSM = LibStub("LibSharedMedia-3.0", true)

-- 预设、DB 字段、锚点、预览交互和所有设置页坐标均由模块声明。
-- 此表只含数据，绝不把模块函数或渲染实现传给中央。
-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 2,
    -- =========================================================
    -- 二、默认配置与配置访问 | Defaults and Configuration Access
    -- =========================================================
    defaults = {
        font_time = {
            a = 1,
            autoWidth = false,
            b = 0,
            font = "默认",
            g = 1,
            justifyH = "CENTER",
            justifyV = "MIDDLE",
            outline = "OUTLINE",
            r = 1,
            shadow = true,
            shadowX = 1,
            shadowY = -1,
            size = 40,
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
                showEdge = false,
                showSwipe = true,
                swipeAlpha = 0.65,
            },
            enableCrop = true,
            height = 60,
            reverse = true,
            showBorder = true,
            showCooldown = true,
            showIcon = true,
            width = 60,
        },
        root = {
            anchor = {
                attachToCustom = false,
                customAttachTarget = "",
                x = -451,
                y = -108,
            },
            customSounds = { "", "", "", "", "", "" },
            enabled = true,
            iconTexture = "132313",
            layout = {
                direction = "RIGHT",
                maxVisible = 1,
                mode = "FLOW",
                spacing = 0,
            },
            randomSound = false,
            sound = "None",
            soundChannel = "Master",
            spellID = "",
            useCustomSound = false,
        },
    },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    anchor = {
        dbPath = "anchor",
        xKey = "x",
        yKey = "y",
        defaultX = -390,
        defaultY = 14,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 59,
        initialHeight = 59,
        clampedToScreen = true,
    },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    preview = {
        positionGuiKeys = { "font_time" },
        elements = {
            ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["嗜血音效图标"] },
            ["core.time"] = {
                guiKey = "font_time",
                movable = true,
                textRole = "time",
                tooltip = L["倒数文本"],
                position = { x = "font_time.x", y = "font_time.y" },
            },
        },
    },
    -- [卡片迁移边界：设置页] 仅可按统一规范调整下列 gui.static/gui.fields 的 x/y/w/h 与卡片分组。
    -- key/type/opts、DB path、anchor/preview/defaults 及刷新回调均属绑定或业务合同，禁止修改；复合控件必须整体引用，header 本身不等于卡片容器。
    -- =========================================================
    -- 三、GUI 声明 | GUI Declarations
    -- =========================================================
    gui = {
        version = 1,
        sections = {
            {
                kind = "settings", id = "common", title = L["通用设置"],
                items = {
                    { key = "enabled", label = L["启用"], type = "switch" },
                    { key = "spellID", label = L["法术 ID（优先）"], type = "input" },
                    { key = "iconTexture", label = L["图标路径/ID"], type = "input" },
                },
            },
            {
                kind = "composite", id = "anchor", title = L["锚点设置"],
                component = "anchorgroup", key = "anchor",
            },
            {
                kind = "composite", id = "icon", title = L["图标本体"],
                component = "icongroup", key = "icon",
            },
            {
                kind = "composite", id = "font_time", title = L["倒数文本"],
                component = "fontgroup", key = "font_time",
            },
            {
                kind = "settings", id = "sound", title = L["音效设置"],
                items = {
                    { key = "sound", label = L["内置音效"], type = "select", media = "sound" },
                    { key = "soundChannel", label = L["输出频道"], type = "select", originalOptions = { { L["主音量"], "Master" }, { L["效果"], "SFX" }, { L["环境"], "Ambience" }, { L["音乐"], "Music" }, { L["对话"], "Dialog" } } },
                    { key = "useCustomSound", label = L["使用自定义路径"], type = "switch" },
                    { key = "randomSound", label = L["随机播放多条"], type = "switch" },
                },
            },
            {
                kind = "settings", id = "custom_sounds", title = L["自定义音效路径"],
                description = { key = "custom_sound_path_guide", type = "description", label = CUSTOM_SOUND_PATH_GUIDE, fontSize = 16 },
                items = {
                    { key = "customSound1", label = L["音效 1"], parentKey = "customSounds", subKey = "1", type = "input", inputWidthPercent = 130 },
                    { key = "customSound2", label = L["音效 2"], parentKey = "customSounds", subKey = "2", type = "input", inputWidthPercent = 130 },
                    { key = "customSound3", label = L["音效 3"], parentKey = "customSounds", subKey = "3", type = "input", inputWidthPercent = 130 },
                    { key = "customSound4", label = L["音效 4"], parentKey = "customSounds", subKey = "4", type = "input", inputWidthPercent = 130 },
                    { key = "customSound5", label = L["音效 5"], parentKey = "customSounds", subKey = "5", type = "input", inputWidthPercent = 130 },
                    { key = "customSound6", label = L["音效 6"], parentKey = "customSounds", subKey = "6", type = "input", inputWidthPercent = 130 },
                },
            },
            {
                kind = "settings", id = "test", title = L["测试操作"],
                items = {
                    { key = "btn_test", label = L["测试效果"], type = "button" },
                    { key = "btn_stop", label = L["停止测试"], type = "button" },
                },
            },
        },
    }
}
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local CUSTOM_SOUNDS_SECTION_INDEX = 6
local customSoundsDescription = MODULE_SPEC.gui.sections[CUSTOM_SOUNDS_SECTION_INDEX].description

local function GetCustomSoundCount(sounds)
    local count = 6
    if type(sounds) == "table" then
        for index in pairs(sounds) do
            if type(index) == "number" and index > count and index % 1 == 0 then
                count = index
            end
        end
    end
    return count
end

local function BuildCustomSoundsSection(count)
    local items = {}
    for index = 1, count do
        items[#items + 1] = {
            key = "customSound" .. index,
            label = string.format(L["音效 %d"], index),
            parentKey = "customSounds",
            subKey = tostring(index),
            type = "input",
            inputWidthPercent = 130,
        }
    end
    items[#items + 1] = { key = "btn_add_custom_sound", label = L["添加音效"], type = "button" }
    return {
        kind = "settings", id = "custom_sounds", title = L["自定义音效路径"],
        description = customSoundsDescription,
        items = items,
    }
end

MODULE_SPEC.gui.sections[CUSTOM_SOUNDS_SECTION_INDEX] = BuildCustomSoundsSection(GetCustomSoundCount(DB.customSounds))
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

local function ResolveDisplayIcon()
    local db = DB
    local spellID = tonumber(db.spellID)
    if spellID then
        local texture = _G.C_Spell and _G.C_Spell.GetSpellTexture and _G.C_Spell.GetSpellTexture(spellID)
            or _G.GetSpellTexture and _G.GetSpellTexture(spellID)
        if texture then return texture end
    end
    return tonumber(db.iconTexture) or db.iconTexture or 132313
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function BuildPresentation(cooldown, isPreview)
    local db = DB
    local iconStyle = db.icon or {}
    local width = math.max(1, tonumber(iconStyle.width) or 59)
    local height = math.max(1, tonumber(iconStyle.height) or 59)
    return {
        style = { icon = iconStyle, text = { countdown = db.font_time or {} } },
        icon = ResolveDisplayIcon(),
        cooldown = cooldown,
        interaction = isPreview and EXUI:BuildStandardPreviewInteraction("Icon", db, MODULE_SPEC.preview.elements) or nil,
        bodySize = { width = width, height = height },
        declaredBounds = { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 },
    }
end

local function RefreshPreview()
    local previewCooldown = { static = true, remaining = 30, duration = CD_DURATION }
    local previewEntries = { { itemID = PREVIEW_ITEM_ID, presentation = BuildPresentation(previewCooldown, true) } }
    central:SetPreview(previewEntries, LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        local cooldown = { static = true, remaining = 30, duration = CD_DURATION }
        controller.previewEntries[1].presentation = BuildPresentation(cooldown, true)
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] then
        local old = controller.runtimeEntries[1].presentation or {}
        controller.runtimeEntries[1].presentation = BuildPresentation(old.cooldown, false)
    end
end

RefreshPreview()

-- =============================================================
-- 嗜血衰弱检测、声音与 40 秒业务状态
-- =============================================================

local effectTimer, lastSoundHandle

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function StopEffect()
    if lastSoundHandle then
        StopSound(lastSoundHandle)
        lastSoundHandle = nil
    end
    if effectTimer then
        effectTimer:Cancel()
        effectTimer = nil
    end
    central:Clear()
end

local function ResolveSound()
    local db = DB
    if db.useCustomSound then
        local choices = {}
        for _, sound in ipairs(type(db.customSounds) == "table" and db.customSounds or {}) do
            if type(sound) == "string" and sound ~= "" then choices[#choices + 1] = sound end
        end
        if #choices == 0 then return nil end
        return db.randomSound and choices[math.random(1, #choices)] or choices[1]
    end
    return LSM and db.sound and db.sound ~= "None" and LSM:Fetch("sound", db.sound, true) or nil
end

local function CreateDurationFromStart(startTime, durationSeconds)
    if not _G.C_DurationUtil or type(_G.C_DurationUtil.CreateDuration) ~= "function" then
        error("YYSound requires C_DurationUtil.CreateDuration", 2)
    end
    local duration = _G.C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(startTime, durationSeconds, 1)
    return duration
end

local function PlayEffect()
    if DB.enabled ~= true then return end
    StopEffect()
    local sound = ResolveSound()
    if sound then
        local _, handle = PlaySoundFile(sound, DB.soundChannel or "Master")
        lastSoundHandle = handle
    end
    local duration = CreateDurationFromStart(GetTime(), CD_DURATION)
    central:SetRuntime(
        { { itemID = RUNTIME_ITEM_ID, presentation = BuildPresentation({ mode = "DURATION", duration = duration, clearIfZero = true }, false) } },
        LAYOUT)
    effectTimer = C_Timer.NewTimer(CD_DURATION, function()
        effectTimer = nil
        central:Clear()
    end)
end

local isReady = false
C_Timer.After(5, function() isReady = true end)
local EXHAUSTION_IDS = { 57723, 57724, 80354, 95809, 160455, 207400, 264689, 390435 }
local EXHAUSTION_DURATION, FRESH_WINDOW, lastExhaustionExpiration = 600, 5, 0

local function CheckExhaustionFresh()
    local unitAuras = _G.C_UnitAuras
    if not unitAuras or type(unitAuras.GetPlayerAuraBySpellID) ~= "function" then return false, nil end
    local now = GetTime()
    for _, spellID in ipairs(EXHAUSTION_IDS) do
        local aura = unitAuras.GetPlayerAuraBySpellID(spellID)
        if aura and aura.expirationTime and aura.expirationTime - now >= EXHAUSTION_DURATION - FRESH_WINDOW then
            return true, aura.expirationTime
        end
    end
    return false, nil
end

local function CheckBloodlustDebuffTrigger()
    if not isReady or DB.enabled ~= true then return end
    local fresh, expirationTime = CheckExhaustionFresh()
    if fresh and expirationTime and expirationTime ~= lastExhaustionExpiration then
        lastExhaustionExpiration = expirationTime
        PlayEffect()
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("UNIT_AURA", MODULE_KEY, function(_, unit)
    if unit == "player" then C_Timer.After(.05, CheckBloodlustDebuffTrigger) end
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    lastExhaustionExpiration = 0
end)
-- Grid 只发布纯点击状态；业务模块自行决定测试/停止行为。
ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY, function(click)
    if not click or not click.key then return end
    if click.key == "btn_test" then
        PlayEffect()
    elseif click.key == "btn_stop" then
        StopEffect()
    elseif click.key == "btn_add_custom_sound" then
        if type(DB.customSounds) ~= "table" then return end
        local nextIndex = GetCustomSoundCount(DB.customSounds) + 1
        DB.customSounds[nextIndex] = ""
        local section = BuildCustomSoundsSection(nextIndex)
        central.spec.gui.sections[CUSTOM_SOUNDS_SECTION_INDEX] = section
        local page = EXUI.ActivePageFrame
        local session = page and _G.ExwindGrid and _G.ExwindGrid:GetMountedCardSession(page)
        if session and session.context.moduleKey == MODULE_KEY then
            session:ReplaceSettingsSection("custom_sounds", section)
        end
    end
end)

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ExwindTools:ReportReady(MODULE_KEY)
