---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local GC = ExwindTools.GUIColors

ExBoss.UI.Panel.GlobalSettingsPage = ExBoss.UI.Panel.GlobalSettingsPage or {}
local Page = ExBoss.UI.Panel.GlobalSettingsPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

local leftRoot
local embeddedHostFrame
local rightScrollFrame
local rightRoot
local listScroll
local listChild
local titleText
local titleSep
local descText
local colorSettingsPage
local resetSettingsPage
local embedPlaceholder
local activeButtons = {}
local headerPool = {}
local selectedIndex = 1
local categoryExpanded = {
    general = true,
    display = true,
    trash = true,
    tools = true,
    other = true,
}
local searchBox
local searchText = ""

local ResetDisplayStylesOnly
local ResetAllConfigExceptAppearance
local ResetAllConfigIncludingAppearance

-- titleKey/descKey are locale keys resolved at render time via GetTitle/GetDesc,
-- avoiding the load-time capture bug where L["..."] would always return zhCN
-- because EXBOSS12S2 (and the saved locale mode) is not yet available at file load.
-- [卡片/Grid 迁移边界：设置目录]
-- ITEMS 顺序、key/mode/moduleKey/appearanceRoots 是路由与导出业务合同，禁止因视觉迁移改名、重排或补入不可达旧页。
-- 允许迁移的是左侧目录项外观和各真实右侧页面自己的内容布局；目录项不是大型内容卡。
local ITEMS = {
    { key = "overview",           category = "general", titleKey = "通用设置",         descKey = "全局显示模式与语音输出。",                                                                                                          mode = "embedded", moduleKey = "ExBoss.GeneralOverview", appearanceRoots = { "ui.general", "voice.global", "autoGossip" } },
    { key = "countdownvoice",     category = "general", titleKey = "语音设置",          descKey = "开怪倒数与数字语音。",                                                                                                               mode = "embedded", moduleKey = "ExBoss.CountdownVoiceSettings", appearanceRoots = { "voice.countdown" } },
    { key = "batchedit",          category = "general", titleKey = "批量修改",          descKey = "批量启用/禁用事件功能，并真实写入 override。",                                                                                        mode = "embedded", moduleKey = "ExBoss.BatchEdit" },
    { key = "color",              category = "general", titleKey = "通用颜色方案",      descKey = "4个固定颜色方案 + 1个自定义方案 + 最多3个额外方案。Boss技能页可直接选择方案或自定义颜色。",                                             mode = "embedded", moduleKey = "ExBoss.GeneralColor", appearanceRoots = { "voice.colorSchemes", "voice.customColors", "voice.extraCustomColors" } },
    { key = "timerbar",           category = "display", titleKey = "计时条",            descKey = "计时条外观、文字、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.TimerBar" },
    { key = "bunbar",             category = "display", titleKey = "束状条",            descKey = "束状条外观、轨道、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.BunBar" },
    { key = "countdown",          category = "display", titleKey = "[文本]5秒倒数",     descKey = "中央倒数文字与字体、位置。",                                                                                                         mode = "embedded", moduleKey = "ExBoss.Countdown" },
    { key = "flashtextmedium",    category = "display", titleKey = "[文本]文字公告(中)", descKey = "中等尺寸中央提示，供血量转阶段、易伤、站位等功能模块复用。",                                                                         mode = "embedded", moduleKey = "ExBoss.FlashTextMedium" },
    { key = "ringprogress",       category = "display", titleKey = "中央圆环",          descKey = "屏幕中央圆环进度样式、大小、位置。",                                                                                                 mode = "embedded", moduleKey = "ExBoss.RingProgress" },
    { key = "iconalert",          category = "display", titleKey = "图标",              descKey = "通用图标容器，支持 API 推入、可选发光与多图标四向增长。",                                                                             mode = "embedded", moduleKey = "ExBoss.IconAlert" },
    { key = "castprogressbar",    category = "display", titleKey = "施法进度条",        descKey = "与中央圆环同源的施法/引导进度条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.CastProgressBar" },
    { key = "extrashieldbar",     category = "display", titleKey = "护盾条",            descKey = "供首领机制复用的单体护盾监控条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.ExtraShieldBar" },
    { key = "trashcd",            category = "trash",   titleKey = "小怪内置CD姓名版图标", descKey = "小怪内置CD姓名版图标的外观与相对姓名版位置。",                                                                                              mode = "embedded", moduleKey  = "ExBoss.TrashCD.Settings" },
    { key = "reset",              category = "other",   titleKey = "重置设置",          descKey = "提供三种重置方式：重置外观、重置配置、重置外观加配置。",                                                                                  mode = "embedded" },
    { key = "dungeonextras", category = "general", titleKey = "副本额外设置", descKey = "统一副本额外提示的位置与开关；血量条共用下方外观设置，风火图保留原有样式。", mode = "embedded", moduleKey = "ExBoss.DungeonExtras" },
}

local CATEGORIES = {
    { key = "general", titleKey = "通用" },
    { key = "display", titleKey = "显示" },
    { key = "trash",   titleKey = "小怪" },
    { key = "other",   titleKey = "其他" },
}

local SIDEBAR_ICONS = {
    overview = "settings", countdownvoice = "headphones", batchedit = "pencil-line", color = "palette",
    timerbar = "timer", bunbar = "list", countdown = "hourglass", flashtextmedium = "message-square",
    ringprogress = "crosshair", iconalert = "image", castprogressbar = "wand-sparkles", extrashieldbar = "shield",
    trashcd = "castle", reset = "refresh-cw", dungeonextras = "map",
}

function Page:GetExportModuleKeys()
    local out = {}
    local seen = {}
    local function add(key)
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    for _, item in ipairs(ITEMS) do
        add(item.moduleKey)
        if type(item.moduleKeys) == "table" then
            for _, key in ipairs(item.moduleKeys) do
                add(key)
            end
        end
    end
    return out
end

-- 外观导出唯一从设置路由取范围：新增非 Boss／小怪设置页时，模块配置会
-- 自动纳入；只有直接写根 SavedVariables 的页面才需要在同一项声明其根路径。
function Page:GetAppearanceProfileSpec()
    local modules, roots, seenModules, seenRoots = {}, {}, {}, {}
    local function add(out, seen, value)
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    for _, item in ipairs(ITEMS) do
        if item.category ~= "trash" and item.key ~= "reset" then
            add(modules, seenModules, item.moduleKey)
            if type(item.moduleKeys) == "table" then
                for _, key in ipairs(item.moduleKeys) do add(modules, seenModules, key) end
            end
            if type(item.appearanceRoots) == "table" then
                for _, path in ipairs(item.appearanceRoots) do add(roots, seenRoots, path) end
            end
        end
    end
    -- Tools 模块拥有独立模块页；注册到 ExBoss.ModuleList 即自动随外观走。
    for _, module in ipairs((ExBoss and ExBoss.ModuleList) or {}) do
        add(modules, seenModules, module.Key)
    end
    return { modules = modules, roots = roots }
end
local function GetTitle(t) return L[t.titleKey or ""] end
local function GetDesc(t)  return L[t.descKey  or ""] end

local function FindItemIndexByKey(key)
    for i, item in ipairs(ITEMS) do
        if item.key == key then
            return i
        end
    end
    return nil
end

local function EnsureSelectedCategoryExpanded()
    local item = ITEMS[selectedIndex]
    if item and item.category then
        categoryExpanded[item.category] = true
    end
end

local FALLBACK_SCHEME_ORDER = { "tank", "heal", "target", "cooldown", "mechanic" }
local FALLBACK_SCHEME_KEYS = {
    tank     = "坦克方案",
    heal     = "治疗方案",
    target   = "点名方案",
    cooldown = "减伤方案",
    mechanic = "机制方案",
}
local function GetFallbackSchemeName(key)
    local k = FALLBACK_SCHEME_KEYS[key]
    return k and L[k] or tostring(key or "")
end
local EXTRA_CUSTOM_COUNT_FALLBACK = 3
local EnsureColorDB
local GetSchemeOrder
local GetSchemeDisplayName
local GetExtraCustomCount
local ApplyVoiceOverrides
local RefreshColorControls

local function TrimOptionalText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetColorModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

-- 颜色与重置页只声明标准设置行，布局和控件释放由 Core 持有。
local COLOR_PAGE_ID = "ExBoss.GeneralColor"
local RESET_PAGE_ID = "ExBoss.ResetSettings"
local standardGlobalPagesRegistered = false

local function CreateGlobalColorControl(path)
    local adapter = EXUI:CreateSettingsV2Control({ controlType = "color" }, function()
        local binding = EXUI:CreateSettingsV2Binding(COLOR_PAGE_ID, EXBOSS12S2, path)
        -- 已上市颜色方案使用记录内 r/g/b；通知仍带完整的原存档路径。
        binding.Parent = function(self) return self:Read() end
        binding.Key = function() return "" end
        return binding
    end)
    local mount = adapter.mount
    adapter.mount = function(host, context)
        local widget = mount(host, context)
        widget._hasAlpha = false
        return widget
    end
    return adapter
end

local function CreateGlobalNameControl(path)
    return EXUI:CreateSettingsV2Control({ controlType = "input" }, function()
        local binding = EXUI:CreateSettingsV2Binding(COLOR_PAGE_ID, EXBOSS12S2, path)
        local write = binding.Write
        binding.Write = function(self, value, phase)
            return write(self, TrimOptionalText(value), phase)
        end
        return binding
    end)
end

local function CreateGlobalPageOwner(pageId, config)
    local owner = { binding = { config = config, moduleKey = pageId }, controls = {}, actions = {} }
    if pageId == COLOR_PAGE_ID then
        for _, key in ipairs(GetSchemeOrder()) do
            owner.controls["fixedColor." .. key] = CreateGlobalColorControl("voice.colorSchemes." .. key)
        end
        owner.controls.customName = CreateGlobalNameControl("voice.customColors.1.name")
        owner.controls.customColor = CreateGlobalColorControl("voice.customColors.1")
        for i = 1, GetExtraCustomCount() do
            local path = "voice.extraCustomColors." .. i
            owner.controls["extraName." .. i] = CreateGlobalNameControl(path .. ".name")
            owner.controls["extraColor." .. i] = CreateGlobalColorControl(path)
        end
    else
        owner.actions.resetStyle = function()
            EXUI:ShowDialog({
                sourceAddon = "EXBoss", sourceModule = L["设置"],
                text = L["仅重置计时条/束状条/倒计时/文字公告的外观样式，不删除法术配置。是否继续？"],
                danger = true,
                buttons = {
                    { id = "cancel", text = L["取消"], variant = "secondary" },
                    { id = "confirm", text = L["确定"], variant = "dangerSolid", onClick = function()
                        ResetDisplayStylesOnly()
                        ReloadUI()
                    end },
                },
                cancelButton = "cancel",
            })
        end
        owner.actions.resetConfig = function()
            EXUI:ShowDialog({
                sourceAddon = "EXBoss", sourceModule = L["设置"],
                text = L["|cffffcc00将清空 EXBoss 的通用设置、语音配置、技能配置与时间轴设置，但保留外观样式。|r\n确认继续？"],
                danger = true,
                buttons = {
                    { id = "cancel", text = L["取消"], variant = "secondary" },
                    { id = "confirm", text = L["确定重置"], variant = "dangerSolid", onClick = function()
                        ResetAllConfigExceptAppearance()
                        ReloadUI()
                    end },
                },
                cancelButton = "cancel",
            })
        end
        owner.actions.resetAll = function()
            EXUI:ShowDialog({
                sourceAddon = "EXBoss", sourceModule = L["设置"],
                text = L["|cffff4444危险：将清空 EXBoss 的全部设置（包含外观）并重载。此操作不可撤销。|r\n确认继续？"],
                danger = true,
                buttons = {
                    { id = "cancel", text = L["取消"], variant = "secondary" },
                    { id = "confirm", text = L["确定清空"], variant = "dangerSolid", onClick = function()
                        ResetAllConfigIncludingAppearance()
                        ReloadUI()
                    end },
                },
                cancelButton = "cancel",
            })
        end
    end
    return owner
end

local function CreateRegisteredGlobalPage(pageId, title, description)
    local registeredPage = { _renderGeneration = 0 }

    local function SyncScrollChildWidth()
        local sf = registeredPage._scrollFrame
        local sc = registeredPage._scrollChild
        if not sf or not sc then return end
        local width = tonumber(sf:GetWidth()) or 0
        if width < 100 then
            local contentWidth = registeredPage._contentFrame
                and tonumber(registeredPage._contentFrame:GetWidth()) or 0
            width = contentWidth >= 100 and (contentWidth - 24) or 804
        end
        width = math.max(1, width)
        if math.abs((sc:GetWidth() or 0) - width) < 0.5 then return end
        sc:SetWidth(width)
        local session = registeredPage._cardSession
        if session and session.alive then
            session:Invalidate()
        end
    end

    local function ReleaseSession()
        registeredPage._renderGeneration = registeredPage._renderGeneration + 1
        if registeredPage._cardSession then
            EXUI:ReleaseModuleSettingsPage(registeredPage._scrollChild)
        end
        registeredPage._cardSession = nil
        if registeredPage._scrollChild then
            registeredPage._scrollChild._exV2Session = nil
            registeredPage._scrollChild._exV2Owner = nil
        end
        if EXUI.ActivePageFrame == registeredPage._scrollChild then
            EXUI.ActivePageFrame = nil
        end
        if EXUI.ActivePageScrollFrame == registeredPage._scrollFrame then
            EXUI.ActivePageScrollFrame = nil
        end
        if EXUI.CurrentModule == pageId then
            EXUI.CurrentModule = nil
        end
    end

    function registeredPage:Render(contentFrame)
        if not contentFrame then return end

        if not self._scrollFrame then
            local sf = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
            if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
                ExBoss.UI.ApplyModernScrollBarSkin(sf)
            end
            local sc = CreateFrame("Frame", nil, sf)
            sc:SetHeight(1)
            sf:SetScrollChild(sc)
            sf:HookScript("OnHide", ReleaseSession)
            sf:HookScript("OnSizeChanged", SyncScrollChildWidth)
            self._scrollFrame = sf
            self._scrollChild = sc
        end

        local sf = self._scrollFrame
        local sc = self._scrollChild
        self._contentFrame = contentFrame
        ReleaseSession()
        local generation = self._renderGeneration

        sf:SetParent(contentFrame)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
        sf:SetVerticalScroll(0)
        sf:Show()

        C_Timer.After(0, function()
            if registeredPage._renderGeneration ~= generation
                or not sf:IsShown()
                or sf:GetParent() ~= contentFrame then
                return
            end
            local config = _G.EXBOSS12S2
            if type(config) ~= "table" then
                error(pageId .. " requires the existing EXBOSS12S2 configuration", 0)
            end
            SyncScrollChildWidth()
            sc:SetParent(sf)
            sc:ClearAllPoints()
            sc:SetPoint("TOPLEFT", 0, 0)
            sc:Show()
            EXUI.ActivePageFrame = sc
            EXUI.ActivePageScrollFrame = sf
            EXUI.CurrentModule = pageId
            if pageId == COLOR_PAGE_ID then EnsureColorDB() end
            local owner = CreateGlobalPageOwner(pageId, config)
            registeredPage._cardSession = EXUI:MountModuleSettingsDeclarationV2(
                sc, pageId, owner, title, description, sf)
        end)
    end

    function registeredPage:Hide()
        ReleaseSession()
        if self._scrollFrame then self._scrollFrame:Hide() end
    end

    return registeredPage
end

local function RegisterStandardGlobalPages()
    if standardGlobalPagesRegistered then return end
    if type(EXUI.MountSettingsPageV2) ~= "function"
        or type(EXUI.RegisterSettingsPageV2) ~= "function"
        or type(EXUI.MountModuleSettingsDeclarationV2) ~= "function" then
        error("Global settings pages require the V2 settings page APIs", 2)
    end

    local fixedRows, extraRows = {}, {}
    for _, key in ipairs(GetSchemeOrder()) do
        fixedRows[#fixedRows + 1] = {
            kind = "setting", id = "fixed." .. key, label = GetSchemeDisplayName(key), children = {
                { kind = "control", id = "fixedColor." .. key, controlType = "color", ref = "fixedColor." .. key },
            },
        }
    end
    for i = 1, GetExtraCustomCount() do
        extraRows[#extraRows + 1] = {
            kind = "setting", id = "extra." .. i, label = L["额外方案"] .. i,
            toggle = "voice.extraCustomColors." .. i .. ".enabled", children = {
                { kind = "control", id = "extraName." .. i, controlType = "input", ref = "extraName." .. i },
                { kind = "control", id = "extraColor." .. i, controlType = "color", ref = "extraColor." .. i },
            },
        }
    end
    EXUI:RegisterSettingsPageV2(COLOR_PAGE_ID, { version = 2, cards = {
        { kind = "card", id = "fixed-colors", title = L["固定方案"], children = fixedRows },
        { kind = "card", id = "custom-color", title = L["自定义方案"], children = {
            { kind = "setting", id = "custom-name", label = L["名称"], children = {
                { kind = "control", id = "customName", controlType = "input", ref = "customName" },
            } },
            { kind = "setting", id = "custom-color-row", label = L["颜色"], children = {
                { kind = "control", id = "customColor", controlType = "color", ref = "customColor" },
            } },
        } },
        { kind = "card", id = "extra-colors", title = L["额外方案（最多3个）"], children = extraRows },
    } })
    EXUI:RegisterSettingsPageV2(RESET_PAGE_ID, { version = 2, cards = {
        { kind = "card", id = "reset-actions", title = L["重置操作"], children = {
            { kind = "setting", id = "reset-style", label = L["重置外观"], description = L["保留配置数据"], children = {
                { kind = "button", id = "resetStyle", text = L["确认"], action = "resetStyle" },
            } },
            { kind = "setting", id = "reset-config", label = L["重置配置"], description = L["保留外观"], children = {
                { kind = "button", id = "resetConfig", text = L["确认"], action = "resetConfig" },
            } },
            { kind = "setting", id = "reset-all", label = L["重置外观加配置"], description = L["恢复全部设置"], children = {
                { kind = "button", id = "resetAll", text = L["确认"], action = "resetAll" },
            } },
        } },
    } })

    colorSettingsPage = CreateRegisteredGlobalPage(COLOR_PAGE_ID, L["通用颜色方案"],
        L["Boss技能页面可选择下列方案；选择“自定义颜色”时使用“自定义方案”。勾选启用的额外方案会出现在技能页下拉。"])
    resetSettingsPage = CreateRegisteredGlobalPage(RESET_PAGE_ID, L["重置设置"],
        L["提供三种重置方式：重置外观、重置配置、重置外观加配置。"])
    EXUI:RegisterModuleValueController(COLOR_PAGE_ID, {
        RefreshActiveSurfaces = function(_, path)
            RefreshColorControls()
            if not path:match("%.name$") then ApplyVoiceOverrides() end
        end,
    })
    standardGlobalPagesRegistered = true
end
local function GetVordazaShieldModule()
    return ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.VordazaShieldBar or nil
end

EnsureColorDB = function()
    local CS = GetColorModule()
    if CS and CS.EnsureDB then
        local db = CS.EnsureDB()
        local custom = (db.customColors and db.customColors[1]) or {}
        return db, db.colorSchemes or {}, custom, db.extraCustomColors or {}
    end

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    EXBOSS12S2.voice.colorSchemes = EXBOSS12S2.voice.colorSchemes or {}
    EXBOSS12S2.voice.customColors = EXBOSS12S2.voice.customColors or {}
    EXBOSS12S2.voice.extraCustomColors = EXBOSS12S2.voice.extraCustomColors or {}
    EXBOSS12S2.voice.customColors[1] = EXBOSS12S2.voice.customColors[1] or { name = L["自定义方案"], r = 1, g = 0.82, b = 0.25 }

    for i = 1, EXTRA_CUSTOM_COUNT_FALLBACK do
        local row = EXBOSS12S2.voice.extraCustomColors[i]
        if type(row) ~= "table" then
            EXBOSS12S2.voice.extraCustomColors[i] = {
                enabled = false,
                name = L["额外方案"] .. tostring(i),
                r = 1,
                g = 0.82,
                b = 0.25,
            }
        else
            if row.enabled == nil then row.enabled = false end
            if type(row.name) ~= "string" then
                row.name = L["额外方案"] .. tostring(i)
            end
            row.r = tonumber(row.r) or 1
            row.g = tonumber(row.g) or 0.82
            row.b = tonumber(row.b) or 0.25
        end
    end

    for _, key in ipairs(FALLBACK_SCHEME_ORDER) do
        local row = EXBOSS12S2.voice.colorSchemes[key]
        if type(row) ~= "table" then
            EXBOSS12S2.voice.colorSchemes[key] = {
                name = GetFallbackSchemeName(key),
                r = 1,
                g = 1,
                b = 1,
            }
        end
    end

    return EXBOSS12S2.voice, EXBOSS12S2.voice.colorSchemes, EXBOSS12S2.voice.customColors[1], EXBOSS12S2.voice.extraCustomColors
end

GetSchemeOrder = function()
    local CS = GetColorModule()
    if CS and CS.GetFixedOrder then
        return CS.GetFixedOrder()
    end
    return FALLBACK_SCHEME_ORDER
end

GetSchemeDisplayName = function(key)
    local CS = GetColorModule()
    if CS and CS.GetSchemeDisplayName then
        return CS.GetSchemeDisplayName(key)
    end
    return GetFallbackSchemeName(key)
end

GetExtraCustomCount = function()
    local CS = GetColorModule()
    if CS and CS.GetExtraCustomCount then
        return tonumber(CS.GetExtraCustomCount()) or EXTRA_CUSTOM_COUNT_FALLBACK
    end
    return EXTRA_CUSTOM_COUNT_FALLBACK
end

ApplyVoiceOverrides = function()
    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local STYLE_MODULE_KEYS = {
    "ExBoss.DungeonExtras",
    "ExBoss.TimerBar",
    "ExBoss.BunBar",
    "ExBoss.Countdown",
    "ExBoss.FlashTextMedium",
    "ExBoss.RingProgress",
    "ExBoss.IconAlert",
    "ExBoss.CastProgressBar",
    -- ExtraShieldBar owns only display configuration in its ModuleDB, so its
    -- complete DB is part of the appearance snapshot/reset contract.
    "ExBoss.ExtraShieldBar",
}

local EXBOSS_MODULE_KEYS = {
    "ExBoss.DungeonExtras",
    "ExBoss.TimerBar",
    "ExBoss.BunBar",
    "ExBoss.Countdown",
    "ExBoss.FlashTextMedium",
    "ExBoss.RingProgress",
    "ExBoss.IconAlert",
    "ExBoss.CastProgressBar",
    "ExBoss.ExtraShieldBar",
    "ExBoss.BossSpellOptions",
    "ExBoss.TrashCD.Settings",
}

local STYLE_MODULE_KEY_SET = {
    ["ExBoss.DungeonExtras"] = true,
    ["ExBoss.TimerBar"] = true,
    ["ExBoss.BunBar"] = true,
    ["ExBoss.Countdown"] = true,
    ["ExBoss.FlashTextMedium"] = true,
    ["ExBoss.RingProgress"] = true,
    ["ExBoss.IconAlert"] = true,
    ["ExBoss.CastProgressBar"] = true,
    ["ExBoss.ExtraShieldBar"] = true,
}

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

local function CaptureAppearanceSnapshot()
    local snap = {
        timer = {},
        voice = {},
        moduleDB = {},
    }

    if type(EXBOSS12S2) == "table" then
        local timer = type(EXBOSS12S2.timer) == "table" and EXBOSS12S2.timer or nil
        if timer then
            if timer.bunBar ~= nil then snap.timer.bunBar = DeepCopy(timer.bunBar) end
            if timer.countdown ~= nil then snap.timer.countdown = DeepCopy(timer.countdown) end
            if timer.flashTextMedium ~= nil then snap.timer.flashTextMedium = DeepCopy(timer.flashTextMedium) end
            if timer.ringProgress ~= nil then snap.timer.ringProgress = DeepCopy(timer.ringProgress) end
        end

        local voice = type(EXBOSS12S2.voice) == "table" and EXBOSS12S2.voice or nil
        if voice then
            if voice.colorSchemes ~= nil then snap.voice.colorSchemes = DeepCopy(voice.colorSchemes) end
            if voice.customColors ~= nil then snap.voice.customColors = DeepCopy(voice.customColors) end
            if voice.extraCustomColors ~= nil then snap.voice.extraCustomColors = DeepCopy(voice.extraCustomColors) end
        end
    end

    if type(EXBOSS12S2) == "table" and type(EXBOSS12S2.ModuleDB) == "table" then
        for _, key in ipairs(STYLE_MODULE_KEYS) do
            if EXBOSS12S2.ModuleDB[key] ~= nil then
                snap.moduleDB[key] = DeepCopy(EXBOSS12S2.ModuleDB[key])
            end
        end
    end

    return snap
end

local function RestoreAppearanceSnapshot(snap)
    if type(snap) ~= "table" then
        return
    end

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.timer = EXBOSS12S2.timer or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}

    EXBOSS12S2.timer.bunBar = DeepCopy(snap.timer and snap.timer.bunBar)
    EXBOSS12S2.timer.countdown = DeepCopy(snap.timer and snap.timer.countdown)
    EXBOSS12S2.timer.flashTextMedium = DeepCopy(snap.timer and snap.timer.flashTextMedium)
    EXBOSS12S2.timer.ringProgress = DeepCopy(snap.timer and snap.timer.ringProgress)
    EXBOSS12S2.voice.colorSchemes = DeepCopy(snap.voice and snap.voice.colorSchemes)
    EXBOSS12S2.voice.customColors = DeepCopy(snap.voice and snap.voice.customColors)
    EXBOSS12S2.voice.extraCustomColors = DeepCopy(snap.voice and snap.voice.extraCustomColors)

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ModuleDB = EXBOSS12S2.ModuleDB or {}
    for _, key in ipairs(STYLE_MODULE_KEYS) do
        EXBOSS12S2.ModuleDB[key] = nil
    end
    if type(snap.moduleDB) == "table" then
        for key, value in pairs(snap.moduleDB) do
            EXBOSS12S2.ModuleDB[key] = DeepCopy(value)
        end
    end
end

local function ClearExBossModuleDB(preserveAppearanceModules)
    if type(EXBOSS12S2) ~= "table" or type(EXBOSS12S2.ModuleDB) ~= "table" then
        return
    end
    for _, key in ipairs(EXBOSS_MODULE_KEYS) do
        if not (preserveAppearanceModules and STYLE_MODULE_KEY_SET[key]) then
            EXBOSS12S2.ModuleDB[key] = nil
        end
    end
end

ResetDisplayStylesOnly = function()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.timer = EXBOSS12S2.timer or {}
    EXBOSS12S2.timer.bunBar = nil
    EXBOSS12S2.timer.countdown = nil
    EXBOSS12S2.timer.flashTextMedium = nil
    EXBOSS12S2.timer.ringProgress = nil

    if EXBOSS12S2 and type(EXBOSS12S2.ModuleDB) == "table" then
        for _, key in ipairs(STYLE_MODULE_KEYS) do
            EXBOSS12S2.ModuleDB[key] = nil
        end
    end

    if ExBoss and ExBoss.UI then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshVisuals then
            ExBoss.UI.TimerBar:RefreshVisuals()
        end
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshVisuals then
            ExBoss.UI.BunBar:RefreshVisuals()
        end
        if ExBoss.UI.Countdown and ExBoss.UI.Countdown.RefreshVisuals then
            ExBoss.UI.Countdown:RefreshVisuals()
        end
        if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.RefreshVisuals then
            ExBoss.UI.FlashTextMedium:RefreshVisuals()
        end
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.RefreshVisuals then
            ExBoss.UI.RingProgress:RefreshVisuals()
        end
        if ExBoss.UI.IconAlert and ExBoss.UI.IconAlert.RefreshVisuals then
            ExBoss.UI.IconAlert:RefreshVisuals()
        end
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.RefreshVisuals then
            ExBoss.UI.CastProgressBar:RefreshVisuals()
        end
        if ExBoss.UI.ExtraShieldBar and ExBoss.UI.ExtraShieldBar.RefreshVisuals then
            ExBoss.UI.ExtraShieldBar:RefreshVisuals()
        end
        if ExBoss.UI.DungeonExtras then ExBoss.UI.DungeonExtras:RefreshVisuals() end
        local VordazaShield = GetVordazaShieldModule()
        if VordazaShield and VordazaShield.RefreshVisuals then
            VordazaShield:RefreshVisuals()
        end
    end
end

ResetAllConfigExceptAppearance = function()
    local appearance = CaptureAppearanceSnapshot()

    ExwindTools:ResetAddonModuleStorage("EXBOSS")
    EXBossDataDB = nil

    RestoreAppearanceSnapshot(appearance)
end

ResetAllConfigIncludingAppearance = function()
    ExwindTools:ResetAddonModuleStorage("EXBOSS")
    EXBossDataDB = nil
end

RefreshColorControls = function()
    local container = colorSettingsPage and colorSettingsPage._scrollChild
    local modulePage = container and EXUI:GetModulePage(COLOR_PAGE_ID, container)
    if modulePage then modulePage:Refresh() end
end

local function ClearButtons()
    for _, b in ipairs(activeButtons) do
        b:Hide()
        b:ClearAllPoints()
        if b.IsObjectType and b:IsObjectType("Button") then
            b:SetScript("OnClick", nil)
        end
        if b._sidebarKind == "header" then
            headerPool[#headerPool + 1] = b
        else
            EXUI:ReleaseSidebarNavigationButton(b)
        end
    end
    wipe(activeButtons)
end

local function AcquireListButton()
    local b
    if ExBoss.UI and ExBoss.UI.CreateSidebarModuleButton then
        b = ExBoss.UI.CreateSidebarModuleButton(listChild)
    elseif EXUI and EXUI.CreateSidebarNavigationButton then
        b = EXUI:CreateSidebarNavigationButton(listChild, "", nil, {
            level = 1, height = 28,
        })
    else
        error("GlobalSettings sidebar requires the shared navigation button API", 2)
    end
    b._sidebarKind = "item"
    return b
end

local function AcquireHeaderButton()
    local b = table.remove(headerPool)
    if b then
        b:SetParent(listChild)
        return b
    end
    if ExBoss.UI and ExBoss.UI.CreateSidebarCategoryHeader then
        b = ExBoss.UI.CreateSidebarCategoryHeader(listChild)
    elseif EXUI and EXUI.CreateSidebarNavigationHeader then
        b = EXUI:CreateSidebarNavigationHeader(listChild, "", { height = 26 })
    else
        error("GlobalSettings sidebar requires the shared navigation header API", 2)
    end
    b._sidebarKind = "header"
    return b
end

local function SetupListButton(button, height, leftInset)
    button:SetHeight(height)
    local label = button.label or button.fs
    if button._exButtonPresentation ~= "sidebar" then
        label:ClearAllPoints()
        label:SetPoint("LEFT", leftInset or 14, 0)
        label:SetPoint("RIGHT", -8, 0)
    end
    label:SetJustifyH("LEFT")
    if button.Enable then button:Enable() end
end

local function ItemMatchesSearch(item)
    if searchText == "" then
        return true
    end
    if not ExBoss.UI or not ExBoss.UI.SidebarTextContains then
        return true
    end
    return ExBoss.UI.SidebarTextContains(GetTitle(item), searchText)
        or ExBoss.UI.SidebarTextContains(GetDesc(item), searchText)
        or ExBoss.UI.SidebarTextContains(item.key, searchText)
        or ExBoss.UI.SidebarTextContains(item.moduleKey, searchText)
end

local function HideEmbeddedPages()
    -- 目录切换只直接隐藏各页 _scrollFrame 并在下方清 ActivePageFrame/CurrentModule，不调用 page:Hide()。
    -- StandardModulePage 依靠 ScrollFrame OnHide 进入 teardown；非标准页只执行各自已有的 OnHide。迁移不得把预期的完整释放写成现状或另造第二条释放链。
    local pages = {
        colorSettingsPage,
        resetSettingsPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GeneralOverviewPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownVoicePage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BatchEditPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TimerBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BunBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextMediumPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.RingProgressPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.IconAlertPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CastProgressBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ExtraShieldBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.DungeonExtrasPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ImportExportPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalTrashCDPage,
    }
    for _, page in ipairs(pages) do
        if page and page._scrollFrame then
            page._scrollFrame:Hide()
            if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == page._scrollChild then
                ExwindTools.UI.ActivePageFrame = nil
                ExwindTools.UI.CurrentModule = nil
            end
        end
    end
end

local function ShowBuiltinLayout(show)
    if titleText then
        if show then titleText:Show() else titleText:Hide() end
    end
    if titleSep then
        if show then titleSep:Show() else titleSep:Hide() end
    end
    if descText then
        if show then descText:Show() else descText:Hide() end
    end
end

local function RefreshRight()
    local item = ITEMS[selectedIndex] or ITEMS[1]
    local key = item and item.key or "overview"

    HideEmbeddedPages()
    if embedPlaceholder then embedPlaceholder:Hide() end

    if item and item.mode == "embedded" then
        if rightScrollFrame then
            rightScrollFrame:Hide()
        end
        if rightRoot then
            rightRoot:Hide()
        end
        ShowBuiltinLayout(false)

        local pageMap = {
            color = colorSettingsPage,
            reset = resetSettingsPage,
            overview = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GeneralOverviewPage,
            countdownvoice = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownVoicePage,
            batchedit = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BatchEditPage,
            timerbar = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TimerBarPage,
            bunbar = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BunBarPage,
            countdown = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownPage,
            flashtextmedium = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextMediumPage,
            ringprogress         = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.RingProgressPage,
            iconalert            = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.IconAlertPage,
            castprogressbar      = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CastProgressBarPage,
            extrashieldbar       = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ExtraShieldBarPage,
            dungeonextras       = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.DungeonExtrasPage,
            trashcd              = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalTrashCDPage,
        }
        local page = pageMap[key]
        if page and page.Render then
            page:Render(embeddedHostFrame)
        elseif embedPlaceholder then
            embedPlaceholder:SetText((GetTitle(item) or L["设置页"]) .. L[" 未就绪"])
            embedPlaceholder:Show()
        end
        return
    end

    if rightScrollFrame then
        rightScrollFrame:SetVerticalScroll(0)
        rightScrollFrame:Show()
    end
    if rightRoot then
        rightRoot:Show()
    end
    ShowBuiltinLayout(true)
    if titleText then
        titleText:SetText(item and GetTitle(item) or L["通用设置"])
        titleText:ClearAllPoints()
        titleText:SetPoint("TOPLEFT", rightRoot, "TOPLEFT", 14, -14)
        titleText:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -14, -14)
    end
    if descText then
        descText:SetText(item and GetDesc(item) or "")
    end
    if titleSep and descText then
        titleSep:ClearAllPoints()
        titleSep:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
        descText:ClearAllPoints()
        descText:SetPoint("TOPLEFT", titleSep, "BOTTOMLEFT", 0, -10)
        titleSep:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -12, -8)
        descText:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    end
end

local function RefreshList()
    if not listChild then return end
    ClearButtons()

    local y = -6
    local shown = 0
    for _, category in ipairs(CATEGORIES) do
        local matchedItems = {}
        for i, item in ipairs(ITEMS) do
            if item.category == category.key and ItemMatchesSearch(item) then
                matchedItems[#matchedItems + 1] = { index = i, item = item }
            end
        end

        if #matchedItems > 0 then
            local header = AcquireHeaderButton()
            SetupListButton(header, 26, 0)
            header:SetPoint("TOPLEFT", 10, y)
            header:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
            header.label:SetText(GetTitle(category))
            activeButtons[#activeButtons + 1] = header
            header:Show()
            y = y - 30
            shown = shown + 1

            for _, row in ipairs(matchedItems) do
                local i = row.index
                local item = row.item
                local b = AcquireListButton()
                SetupListButton(b, 30, 34)
                EXUI:SetSidebarNavigationButtonIcon(b, EXUI:GetIcon(SIDEBAR_ICONS[item.key]))
                b:SetPoint("TOPLEFT", 10, y)
                b:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)

                local label = b.label or b.fs
                label:SetText(GetTitle(item) or (L["条目 "] .. tostring(i)))
                if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and b.label then
                    ExBoss.UI.ApplySidebarModuleButtonState(b, selectedIndex == i, true)
                end

                b:SetScript("OnClick", function()
                    selectedIndex = i
                    EnsureSelectedCategoryExpanded()
                    RefreshList()
                    RefreshRight()
                end)

                activeButtons[#activeButtons + 1] = b
                b:Show()
                y = y - 34
                shown = shown + 1
            end
            y = y - 6
        end
    end

    if shown == 0 then
        local empty = AcquireListButton()
        SetupListButton(empty, 30, 34)
        empty:SetPoint("TOPLEFT", 10, y)
        empty:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
        local label = empty.label or empty.fs
        label:SetText(L["没有匹配项"])
        if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and empty.label then
            ExBoss.UI.ApplySidebarModuleButtonState(empty, false, false)
        else
            label:SetTextColor(unpack(GC.textDisabled))
        end
        empty:Show()
        activeButtons[#activeButtons + 1] = empty
        y = y - 32
    end

    listChild:SetHeight(math.max(1, -y + 8))
end

-- [混合函数边界] EnsureUI 内只可调整目录/宿主/内置区的几何与外观；搜索、ITEMS 顺序、embedded host、回调和释放链禁止修改。
local function EnsureUI(leftFrame, contentFrame)
    RegisterStandardGlobalPages()
    if leftRoot and rightRoot then return end

    leftRoot = CreateFrame("Frame", nil, leftFrame)
    leftRoot:SetAllPoints(leftFrame)

    if ExBoss.UI and ExBoss.UI.CreateSidebarSearchBox then
        searchBox = ExBoss.UI.CreateSidebarSearchBox(leftRoot, searchText, {
            placeholder = L["搜索设置..."],
            onChanged = function(text)
                local normalized = ExBoss.UI.NormalizeSidebarSearchText and ExBoss.UI.NormalizeSidebarSearchText(text) or tostring(text or "")
                if normalized == searchText then
                    return
                end
                searchText = normalized
                if listScroll and listScroll.SetVerticalScroll then
                    listScroll:SetVerticalScroll(0)
                end
                RefreshList()
            end,
        })
        searchBox:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 10, -5)
        searchBox:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -22, -5)
    end

    listScroll = CreateFrame("ScrollFrame", nil, leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(listScroll)
    end
    listScroll:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -40)
    listScroll:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -18, 5)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(340, 1)
    listScroll:SetScrollChild(listChild)
    listScroll:HookScript("OnSizeChanged", function(_, width)
        listChild:SetWidth(math.max(1, width))
    end)

    rightScrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(rightScrollFrame)
    end
    rightRoot = CreateFrame("Frame", nil, rightScrollFrame)
    rightRoot:SetPoint("TOPLEFT", 0, 0)
    rightRoot:SetSize(math.max((contentFrame:GetWidth() or 0) - 28, 760), 1600)
    rightScrollFrame:SetScrollChild(rightRoot)

    titleText = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 14, -14)
    titleText:SetTextColor(unpack(GC.text))

    local sep = EXUI:CreateVisualTexture(rightRoot, EXBORDERFRAME)
    sep:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
    sep:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -12, -8)
    sep:SetHeight(1)
    sep:SetColorTexture(unpack(GC.headerDivider))
    titleSep = sep

    descText = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontHighlight")
    descText:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
    descText:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetWordWrap(true)
    descText:SetTextColor(unpack(GC.textDim))

    embedPlaceholder = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontHighlight")
    embedPlaceholder:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -14)
    embedPlaceholder:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    embedPlaceholder:SetJustifyH("LEFT")
    embedPlaceholder:SetTextColor(unpack(GC.textPlaceholder))
    embedPlaceholder:Hide()
end

function Page:Render(leftFrame, contentFrame)
    if not leftFrame or not contentFrame then return end
    embeddedHostFrame = contentFrame
    EnsureUI(leftFrame, contentFrame)
    if selectedIndex < 1 or selectedIndex > #ITEMS then
        selectedIndex = 1
    end
    EnsureSelectedCategoryExpanded()

    leftRoot:SetParent(leftFrame)
    leftRoot:ClearAllPoints()
    leftRoot:SetAllPoints(leftFrame)
    leftRoot:Show()
    listChild:SetWidth(math.max(1, listScroll:GetWidth()))

    rightScrollFrame:SetParent(contentFrame)
    rightScrollFrame:ClearAllPoints()
    rightScrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    rightScrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 0)
    rightRoot:SetWidth(math.max((contentFrame:GetWidth() or 0) - 28, 760))
    RefreshList()
    RefreshColorControls()
    RefreshRight()
end

function Page:Hide()
    HideEmbeddedPages()
    if leftRoot then leftRoot:Hide() end
    if rightRoot then rightRoot:Hide() end
    if rightScrollFrame then rightScrollFrame:Hide() end
end

function Page:SetSelectedKey(key)
    if type(key) ~= "string" or key == "" then return end
    local index = FindItemIndexByKey(key)
    if index then
        selectedIndex = index
        EnsureSelectedCategoryExpanded()
    end

    if leftRoot and embeddedHostFrame and leftRoot:IsShown() then
        RefreshList()
        RefreshColorControls()
        RefreshRight()
    end
end
