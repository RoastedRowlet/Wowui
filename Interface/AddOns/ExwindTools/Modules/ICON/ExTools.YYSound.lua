-- =============================================================
-- 嗜血音效：业务只提交标准 IconCollection presentation。
-- 中央只管理已存在的 Collection、Anchor、Panel 和世界编辑宿主。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.YYSound"
local RUNTIME_ITEM_ID = "yysound:runtime"
local PREVIEW_ITEM_ID = "yysound:preview"
local CD_DURATION = 40
local RefreshActiveSurfaces

local LSM = LibStub("LibSharedMedia-3.0", true)

-- 预设、DB 字段、锚点、预览交互和所有设置页坐标均由模块声明。
-- 此表只含数据，绝不把模块函数或渲染实现传给中央。
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 2,
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
    preview = {
        positionGuiKeys = { "font_time" },
        elements = {
            ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["嗜血音效图标"] },
            ["core.time"] = {
                guiKey = "font_time", movable = true, textRole = "time", tooltip = L["倒数文本"],
                position = { x = "font_time.x", y = "font_time.y" },
            },
        },
    },
    gui = {
        fields = {
            {
                group = "settings",
                h = 6,
                key = "enabled",
                label = L["启用"],
                order = 1,
                type = "checkbox",
                w = 46,
                x = 2,
                y = 11,
            },
            {
                group = "settings",
                h = 6,
                key = "spellID",
                label = L["法术 ID（优先）"],
                labelPos = "top",
                order = 2,
                type = "input",
                w = 70,
                x = 51,
                y = 11,
            },
            {
                group = "settings",
                h = 6,
                key = "iconTexture",
                label = L["图标路径/ID"],
                labelPos = "top",
                order = 3,
                type = "input",
                w = 70,
                x = 125,
                y = 11,
            },
            {
                group = "settings",
                h = 18,
                key = "anchor",
                label = L["锚点设置"],
                order = 4,
                type = "anchorgroup",
                w = 200,
                x = 1,
                y = 36,
            },
            {
                group = "settings",
                h = 50,
                key = "icon",
                label = L["图标本体"],
                labelSize = 20,
                order = 5,
                type = "icongroup",
                w = 200,
                x = 1,
                y = 57,
            },
            {
                group = "settings",
                h = 50,
                key = "font_time",
                label = L["倒数文本"],
                labelSize = 20,
                order = 6,
                type = "fontgroup",
                w = 200,
                x = 1,
                y = 109,
            },
            {
                group = "settings",
                h = 6,
                key = "sound",
                label = L["内置音效"],
                labelPos = "top",
                labelSize = 20,
                order = 7,
                type = "lsm_sound",
                w = 46,
                x = 1,
                y = 173,
            },
            {
                group = "settings",
                h = 6,
                items = {
                    {
                        L["主音量"],
                        "Master",
                    },
                    {
                        L["效果"],
                        "SFX",
                    },
                    {
                        L["环境"],
                        "Ambience",
                    },
                    {
                        L["音乐"],
                        "Music",
                    },
                    {
                        L["对话"],
                        "Dialog",
                    },
                },
                key = "soundChannel",
                label = L["输出频道"],
                labelPos = "top",
                order = 8,
                type = "dropdown",
                w = 46,
                x = 51,
                y = 173,
            },
            {
                group = "settings",
                h = 6,
                key = "useCustomSound",
                label = L["使用自定义路径"],
                order = 9,
                type = "checkbox",
                w = 46,
                x = 2,
                y = 182,
            },
            {
                group = "settings",
                h = 6,
                key = "randomSound",
                label = L["随机播放多条"],
                order = 10,
                type = "checkbox",
                w = 46,
                x = 51,
                y = 182,
            },
            {
                group = "settings",
                h = 6,
                key = "customSound1",
                label = L["音效 1"],
                labelPos = "left",
                order = 11,
                parentKey = "customSounds",
                subKey = "1",
                type = "input",
                w = 180,
                x = 15,
                y = 201,
            },
            {
                group = "settings",
                h = 6,
                key = "customSound2",
                label = L["音效 2"],
                labelPos = "left",
                order = 12,
                parentKey = "customSounds",
                subKey = "2",
                type = "input",
                w = 180,
                x = 15,
                y = 209,
            },
            {
                group = "settings",
                h = 6,
                key = "customSound3",
                label = L["音效 3"],
                labelPos = "left",
                order = 13,
                parentKey = "customSounds",
                subKey = "3",
                type = "input",
                w = 180,
                x = 15,
                y = 217,
            },
            {
                group = "settings",
                h = 6,
                key = "customSound4",
                label = L["音效 4"],
                labelPos = "left",
                order = 14,
                parentKey = "customSounds",
                subKey = "4",
                type = "input",
                w = 180,
                x = 15,
                y = 225,
            },
            {
                group = "settings",
                h = 6,
                key = "customSound5",
                label = L["音效 5"],
                labelPos = "left",
                order = 15,
                parentKey = "customSounds",
                subKey = "5",
                type = "input",
                w = 180,
                x = 15,
                y = 233,
            },
            {
                group = "settings",
                h = 6,
                key = "customSound6",
                label = L["音效 6"],
                labelPos = "left",
                order = 16,
                parentKey = "customSounds",
                subKey = "6",
                type = "input",
                w = 180,
                x = 15,
                y = 241,
            },
            {
                group = "settings",
                h = 6,
                key = "btn_test",
                label = L["测试效果"],
                order = 23,
                type = "button",
                w = 46,
                x = 15,
                y = 263,
            },
            {
                group = "settings",
                h = 6,
                key = "btn_stop",
                label = L["停止测试"],
                order = 24,
                type = "button",
                w = 46,
                x = 65,
                y = 263,
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
                label = L["嗜血音效（YY Sound）"],
                labelSize = 25,
                type = "header",
                w = 200,
                x = 1,
                y = 1,
            },
            {
                h = 6,
                key = "soundHeader",
                label = L["音效设置"],
                labelSize = 20,
                type = "subheader",
                w = 200,
                x = 1,
                y = 162,
            },
            {
                h = 6,
                key = "customHeader",
                label = L["自定义音效路径（固定 6 条）"],
                labelSize = 20,
                type = "subheader",
                w = 200,
                x = 1,
                y = 190,
            },
            {
                h = 6,
                key = "testHeader",
                label = L["测试操作"],
                labelSize = 20,
                type = "subheader",
                w = 200,
                x = 1,
                y = 252,
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
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
    end
end)

ExwindTools:ReportReady(MODULE_KEY)
