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
-- 页面声明只含数据，运行期设置选项由 SettingsOwner 提供。
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
    -- =========================================================
    -- 三、GUI 声明 | GUI Declarations
    -- =========================================================
    gui = {
        version = 2,
        cards = {
            {
                kind = "card", id = "card.common", title = L["通用设置"],
                children = {
                    { kind = "control", id = "enabled", path = "enabled", label = L["启用"], controlType = "switch" },
                    { kind = "control", id = "spellID", path = "spellID", label = L["法术 ID（优先）"], controlType = "input" },
                    { kind = "control", id = "iconTexture", path = "iconTexture", label = L["图标路径/ID"], controlType = "input" },
                },
            },
            {
                kind = "card", id = "card.anchor", title = L["锚点设置"],
                children = {
                    { kind = "component", id = "anchor", component = "anchorgroup", path = "anchor", optionsRef = "anchor" },
                },
            },
            {
                kind = "card", id = "card.icon", title = L["图标本体"],
                children = {
                    { kind = "component", id = "icon", component = "icongroup", path = "icon", optionsRef = "icon" },
                },
            },
            {
                kind = "card", id = "card.font_time", title = L["倒数文本"],
                children = {
                    { kind = "component", id = "font_time", component = "fontgroup", path = "font_time" },
                },
            },
            {
                kind = "card", id = "card.sound", title = L["音效设置"],
                children = {
                    { kind = "control", id = "sound", path = "sound", label = L["内置音效"], controlType = "select", media = "sound" },
                    { kind = "control", id = "soundChannel", path = "soundChannel", label = L["输出频道"], controlType = "select", options = {
                        { value = "Master", label = L["主音量"] }, { value = "SFX", label = L["效果"] },
                        { value = "Ambience", label = L["环境"] }, { value = "Music", label = L["音乐"] }, { value = "Dialog", label = L["对话"] },
                    } },
                    { kind = "control", id = "useCustomSound", path = "useCustomSound", label = L["使用自定义路径"], controlType = "switch" },
                    { kind = "control", id = "randomSound", path = "randomSound", label = L["随机播放多条"], controlType = "switch" },
                },
            },
            {
                kind = "card", id = "card.custom_sounds", title = L["自定义音效路径"],
                children = {
                    { kind = "table", id = "custom_sounds.table", columns = {
                        { title = L["音效"] }, { title = L["自定义音效路径"] },
                    }, children = {
                        { kind = "repeat", id = "custom_sounds.rows", source = "customSounds", template = {
                            kind = "row", id = "custom_sounds.row", children = {
                                { kind = "cell", id = "custom_sounds.name", children = {
                                    { kind = "text", id = "custom_sounds.name.text", textSource = "customSoundTitle" },
                                } },
                                { kind = "cell", id = "custom_sounds.path", children = {
                                    { kind = "control", id = "custom_sounds.input", controlType = "input", ref = "customSound" },
                                } },
                            },
                        } },
                    } },
                    { kind = "setting", id = "btn_add_custom_sound_row", label = L["添加音效"], description = CUSTOM_SOUND_PATH_GUIDE, children = {
                        { kind = "button", id = "btn_add_custom_sound", clickKey = "btn_add_custom_sound", text = L["添加音效"] },
                    } },
                },
            },
            {
                kind = "card", id = "card.test", title = L["测试操作"],
                children = {
                    { kind = "setting", id = "btn_test_row", label = L["测试效果"], children = {
                        { kind = "button", id = "btn_test", clickKey = "btn_test", text = L["测试效果"] },
                        { kind = "button", id = "btn_stop", clickKey = "btn_stop", text = L["停止测试"] },
                    } },
                },
            },
        },
    }
}
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)

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

MODULE_SPEC.SettingsOwner = function(controller)
    local records = {}
    local owner = { sources = {}, controls = {}, texts = {} }
    owner.sources.customSounds = function()
        local rows = {}
        for index = 1, GetCustomSoundCount(controller:GetConfig().customSounds) do
            records[index] = records[index] or { index = index }
            rows[index] = records[index]
        end
        return rows
    end
    owner.texts.customSoundTitle = function(scope)
        return string.format(L["音效 %d"], scope.item.index)
    end
    owner.controls.customSound = EXUI:CreateSettingsV2Control({ controlType = "input", size = "wide" },
        function(context)
            return EXUI:CreateSettingsV2Binding(MODULE_KEY, controller:GetConfig(), "customSounds." .. context.scope.item.index)
        end)
    return owner
end
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
        local page = EXUI:GetModulePage(MODULE_KEY)
        if page then page:Refresh() end
    end
end)

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ExwindTools:ReportReady(MODULE_KEY)
