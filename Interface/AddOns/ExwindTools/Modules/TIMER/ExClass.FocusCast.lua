-- 焦点施法：业务保留 Secret Duration/音效/打断状态，显示只提交纯 TimerBar presentation。
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI, L, LSM = ExwindTools.UI, ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end }),
    LibStub("LibSharedMedia-3.0")
local MODULE_KEY, MARKER_HOST_ID = "ExClass.FocusCast", "focusCastInterruptMarker"
local RefreshActiveSurfaces
local TIMER_SCHEMA = ExwindTools.StandardTimerBar.NormalizeSchema({
    timerBarKey = "timerGroup",
    layoutKey = "layout",
    offsetXKey =
    "posX",
    offsetYKey = "posY",
    positionGridKey = "timerGroup",
    showTextBKey = false,
    showTextCKey = false,
    textA = { key = "font_spell", gridKey = "font_spell", role = "spellName", label = L["法术名称"] },
    textB = { key = "font_target", gridKey = "font_target", role = "targetName", label = L["目标名称"], optional = true },
    textC = { key = "font_timer", gridKey = "font_timer", role = "time", label = L["时间"] }
})
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller, changedPath, phase)
        return RefreshActiveSurfaces(controller, changedPath, phase)
    end,
    moduleKey = MODULE_KEY,
    kind = "timerbar",
    defaults = {
        root = {
            alertChannel = "Master",
            alertEnabled = false,
            alertHostileOnly = false,
            alertLSM = "None",
            alertPath = "",
            alertSource = "lsm",
            alertTtsText = "",
            attachToCustom = false,
            customAttachTarget = "",
            enabled = true,
            font_spell = {
                a = 1,
                autoWidth = false,
                b = 1,
                enabled = true,
                fixedWidth = 200,
                font = "Friz Quadrata TT",
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
                size = 20,
                x = -50.983418423698,
                y = 0,
            },
            font_target = {
                a = 1,
                autoWidth = false,
                b = 0.4039,
                enabled = true,
                fixedWidth = 200,
                font = "默认",
                g = 0.8,
                gradientEnabled = false,
                gradientLength = 0,
                gradientStart = 0,
                justifyH = "CENTER",
                justifyV = "MIDDLE",
                maxWidth = 0,
                outline = "OUTLINE",
                r = 0.2706,
                rotation = 0,
                shadow = false,
                shadowColorA = 1,
                shadowColorB = 0,
                shadowColorG = 0,
                shadowColorR = 0,
                shadowX = 1,
                shadowY = -1,
                size = 20,
                x = 51.198869543275,
                y = 0,
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
                size = 20,
                x = 48.784548880423,
                y = 0,
            },
            hideOnInterruptCD = true,
            hideWhenNotInterruptible = true,
            interruptCDColorA = 0.6,
            interruptCDColorB = 0.5,
            interruptCDColorG = 0.5,
            interruptCDColorR = 0.5,
            interruptMarkerColorA = 1,
            interruptMarkerColorB = 0.25,
            interruptMarkerColorG = 0.95,
            interruptMarkerColorR = 1,
            interruptMarkerWidth = 4,
            layout = {
                direction = "DOWN",
                maxVisible = 1,
                spacing = 0,
            },
            muteSoundOnInterruptCD = true,
            nonInterruptColorA = 1,
            nonInterruptColorB = 0.1686,
            nonInterruptColorG = 0.1294,
            nonInterruptColorR = 1,
            posX = -13,
            posY = 263,
            showInterruptCDThreshold = 3,
            showInterruptMarkerLine = true,
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
                borderPadding = 0.30000019073486,
                borderSize = 0.80000001192093,
                borderTexture = "EX_Default",
                fillDirection = "LEFT_TO_RIGHT",
                fillMode = "RTL_DRAIN",
                height = 40,
                iconBorderColorA = 1,
                iconBorderColorB = 0,
                iconBorderColorG = 0,
                iconBorderColorR = 0,
                iconBorderPadding = 0.6,
                iconBorderSize = 0,
                iconBorderTexture = "EX_Default",
                iconHeight = 39,
                iconOffsetX = -2,
                iconOffsetY = 0,
                iconSide = "LEFT",
                iconWidth = 39,
                progressMode = "REMAINING",
                showBorder = true,
                showIcon = true,
                showIconBorder = true,
                texture = "EX_WhiteTexture",
                width = 310,
                x = 0,
                y = 0,
            },
        },
    },
    anchor = { dbPath = "$root", bindRoot = true, xKey = "posX", yKey = "posY", defaultX = 23, defaultY = 272, attachEnabledKey = "attachToCustom", attachTargetKey = "customAttachTarget", initialWidth = 350, initialHeight = 50, clampedToScreen = true },
    timerBar = { schema = TIMER_SCHEMA },
    preview = {
        positionGuiKeys = { "font_spell", "font_target", "font_timer" },
        elements = {
            ["core.spellName"] = { guiKey = "font_spell", movable = true, textRole = "spellName", tooltip = L["法术名称"], position = { x = "font_spell.x", y = "font_spell.y" } },
            ["core.targetName"] = { guiKey = "font_target", movable = true, textRole = "targetName", tooltip = L["目标名称"], position = { x = "font_target.x", y = "font_target.y" } },
            ["core.time"] = { guiKey = "font_timer", movable = true, textRole = "time", tooltip = L["时间"], position = { x = "font_timer.x", y = "font_timer.y" } },
        }
    },
    gui = {
        fields = {
            {
                h = 30,
                key = "alert",
                label = L["提示音设置"],
                measure = true,
                opts = {
                    secondaryCheckbox = {
                        key = "alertHostileOnly",
                        label = L["仅敌方单位"],
                    },
                    sources = {
                        "lsm",
                        "file",
                        "tts",
                    },
                    testButtonKey = "btn_testSound",
                },
                type = "soundgroup",
                w = 197,
                x = 1,
                y = 80,
            },
            {
                h = 20,
                key = "anchor",
                label = L["锚点设置"],
                measure = true,
                type = "anchorgroup",
                w = 197,
                x = 1,
                y = 122,
            },
            {
                h = 50,
                key = "timerGroup",
                label = L["计时条外观"],
                measure = true,
                type = "timerbargroup",
                w = 197,
                x = 1,
                y = 198,
            },
            {
                h = 50,
                key = "font_spell",
                label = L["法术名称"],
                type = "fontgroup",
                w = 197,
                x = 1,
                y = 252,
            },
            {
                h = 50,
                key = "font_target",
                label = L["目标名称"],
                type = "fontgroup",
                w = 197,
                x = 1,
                y = 306,
            },
            {
                h = 50,
                key = "font_timer",
                label = L["时间"],
                type = "fontgroup",
                w = 197,
                x = 1,
                y = 360,
            },
        },
        static = {
            {
                h = 8,
                key = "header",
                label = L["焦点施法提示"],
                labelSize = 25,
                type = "header",
                w = 197,
                x = 1,
                y = 4,
            },
            {
                h = 6,
                key = "enabled",
                label = L["启用"],
                type = "checkbox",
                w = 46,
                x = 1,
                y = 20,
            },
            {
                h = 6,
                key = "hideWhenNotInterruptible",
                label = L["|cffff080a隐藏不能打断的条 (隐藏钢条)|r"],
                type = "checkbox",
                w = 46,
                x = 1,
                y = 32,
            },
            {
                h = 6,
                key = "nonInterruptColor",
                label = L["无法打断颜色"],
                type = "color",
                w = 46,
                x = 51,
                y = 32,
            },
            {
                h = 6,
                key = "hideOnInterruptCD",
                label = L["打断CD时隐藏可断条"],
                type = "checkbox",
                w = 46,
                x = 1,
                y = 44,
            },
            {
                h = 6,
                key = "showInterruptCDThreshold",
                label = L["打断CD剩余几秒时显示(左边颜色)"],
                max = 10,
                min = 0,
                type = "slider",
                w = 46,
                x = 51,
                y = 44,
            },
            {
                h = 6,
                key = "interruptCDColor",
                label = L["打断CD时颜色"],
                type = "color",
                w = 46,
                x = 101,
                y = 44,
            },
            {
                h = 6,
                key = "muteSoundOnInterruptCD",
                label = L["打断CD时不播放音效"],
                type = "checkbox",
                w = 46,
                x = 151,
                y = 44,
            },
            {
                h = 6,
                key = "showInterruptMarkerLine",
                label = L["显示打断冷却标线"],
                type = "checkbox",
                w = 46,
                x = 1,
                y = 68,
            },
            {
                h = 6,
                key = "interruptMarkerColor",
                label = L["标线颜色"],
                type = "color",
                w = 46,
                x = 51,
                y = 68,
            },
            {
                h = 6,
                key = "interruptMarkerWidth",
                label = L["标线粗细"],
                max = 16,
                min = 1,
                step = 1,
                type = "slider",
                w = 46,
                x = 101,
                y = 68,
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
ExwindTools.StandardTimerBar.EnsureDefaults(DB, TIMER_SCHEMA)
local central = EXUI:RegisterTimerBarModule(MODULE_SPEC)
local LAYOUT = DB.layout
local function GetColor(prefix)
    return DB[prefix .. "R"] or 1, DB[prefix .. "G"] or 1, DB[prefix .. "B"] or 1,
        DB[prefix .. "A"] or 1
end
local function InterruptState()
    if ExwindTools.State.InterruptReady then return "READY" end
    local remaining = (ExwindTools.State.InterruptStartTime or 0) + (ExwindTools.State.InterruptDuration or 0) -
        GetTime()
    if remaining <= 0 then return "READY" end
    if remaining <= (DB.showInterruptCDThreshold or 0) then return "ALMOST_READY" end
    return DB.hideOnInterruptCD and "HIDDEN" or "ON_CD"
end
local function FocusInfo()
    if not UnitExists("focus") then return nil end
    local cast, channel = UnitCastingDuration("focus"), UnitChannelDuration("focus"); local duration, isChannel =
        cast or channel, channel ~= nil
    if not duration then return nil end
    local name, texture, noInterrupt; if isChannel then
        name, _, texture, _, _, _, noInterrupt = UnitChannelInfo("focus")
    else
        name, _, texture, _, _, _, _, noInterrupt =
            UnitCastingInfo("focus")
    end
    if not name then return nil end
    return {
        name = name,
        texture = texture,
        duration = duration,
        isChannel = isChannel,
        noInterrupt = noInterrupt,
        targetName =
            UnitSpellTargetName("focus"),
        targetClass = UnitSpellTargetClass("focus"),
        showTarget =
            UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName("focus") or true
    }
end

-- 面板和世界编辑模式没有实际的焦点/打断 Duration Object；这里只投影一条固定
-- 的预览标线。运行时标线仍由下方的第二条原生 StatusBar 驱动。
local function BuildPreviewMarkerRegionElement()
    local width = math.max(1, tonumber(DB.interruptMarkerWidth) or 1)
    local height = math.max(1, tonumber(DB.timerGroup.height) or 1)
    local x = math.max(1, tonumber(DB.timerGroup.width) or 1) * .25
    local r, g, b, a = GetColor("interruptMarkerColor")
    return {
        id = "interruptMarkerPreview",
        kind = "texture",
        style = DB.timerGroup,
        anchor = { point = "CENTER", relativeElement = "core.bar", relativePoint = "CENTER", x = x, y = 0 },
        bounds = { width = width, height = height },
        content = { texture = "Interface\\Buttons\\WHITE8X8", color = { r = r, g = g, b = b, a = a }, shown = DB.showInterruptMarkerLine ~= false },
    }
end

-- 标线不是静态 Region：它的位置来自打断 CD 与焦点施法 Duration Object 的原生
-- 进度关系。复用 StandardTimerBar 的正式 ExtraChildHost，Core 仍负责宿主的池化
-- 与释放；模块只持有自己的第二条透明 StatusBar 及标线。
local function GetInterruptCooldownDurationObject()
    local state = ExwindTools.State or {}
    local specID = state.SpecID or 0
    if specID == 0 then
        local specIndex = GetSpecialization()
        if specIndex then specID = GetSpecializationInfo(specIndex) or 0 end
    end
    local interruptData = _G.EXDB and _G.EXDB.InterruptData and _G.EXDB.InterruptData[specID]
    local spellID = interruptData and interruptData.id or 0
    if spellID == 0 or not (_G.C_Spell and _G.C_Spell.GetSpellCooldownDuration) then return nil end
    return _G.C_Spell.GetSpellCooldownDuration(spellID)
end

local function ConfigureMarkerHost(widget, shown)
    if not widget or type(widget.ConfigureExtraChildHost) ~= "function" then return nil end
    return widget:ConfigureExtraChildHost(MARKER_HOST_ID, {
        width = 1,
        height = 1,
        anchor = { relativeElement = "core.bar", point = "CENTER", relativePoint = "CENTER" },
        shown = shown == true,
    })
end

local function HideInterruptMarker(widget)
    local host = widget and type(widget.GetExtraChildHost) == "function" and widget:GetExtraChildHost(MARKER_HOST_ID)
    if not host then return end
    local markerBar, markerLine = host._focusCastInterruptMarkerBar, host._focusCastInterruptMarkerLine
    if markerBar then markerBar:SetAlpha(0) end
    if markerLine then markerLine:Hide() end
    ConfigureMarkerHost(widget, false)
end

local function EnsureInterruptMarker(widget)
    local host = ConfigureMarkerHost(widget, true)
    local bar = widget and type(widget.GetFixedElementRoot) == "function" and widget:GetFixedElementRoot("bar")
    if not host or not bar then return nil end
    local markerBar, markerLine = host._focusCastInterruptMarkerBar, host._focusCastInterruptMarkerLine
    if not markerBar then
        markerBar = CreateFrame("StatusBar", nil, host)
        markerBar:EnableMouse(false)
        markerBar:SetClipsChildren(true)
        markerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        markerBar:GetStatusBarTexture():SetAlpha(0)
        markerLine = markerBar:CreateTexture(nil, "OVERLAY")
        markerLine:SetTexture("Interface\\Buttons\\WHITE8X8")
        host._focusCastInterruptMarkerBar, host._focusCastInterruptMarkerLine = markerBar, markerLine
    end
    markerBar:ClearAllPoints()
    markerBar:SetAllPoints(bar)
    markerBar:SetFrameLevel((host:GetFrameLevel() or 0) + 1)
    markerBar:Show()
    return markerBar, markerLine
end

local function SetMarkerLine(markerBar, markerLine, isChannel)
    local r, g, b, a = GetColor("interruptMarkerColor")
    local edge, referenceEdge = isChannel and "RIGHT" or "LEFT", isChannel and "LEFT" or "RIGHT"
    markerLine:SetWidth(math.max(1, tonumber(DB.interruptMarkerWidth) or 1))
    markerLine:SetVertexColor(r, g, b, a)
    markerLine:ClearAllPoints()
    markerLine:SetHeight(math.max(1, markerBar:GetHeight() or 1))
    markerLine:SetPoint(edge, markerBar:GetStatusBarTexture(), referenceEdge)
end

local function ApplyInterruptMarker(widget, info, preview)
    if DB.showInterruptMarkerLine == false then
        HideInterruptMarker(widget)
        return
    end
    local markerBar, markerLine = EnsureInterruptMarker(widget)
    if not markerBar then return end
    if preview then
        markerBar:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        markerBar:SetMinMaxValues(0, 4)
        markerBar:SetValue(3)
        SetMarkerLine(markerBar, markerLine, false)
        markerBar:SetAlpha(1)
        markerLine:SetAlpha(1)
        markerLine:Show()
        return
    end

    local interruptCooldown = GetInterruptCooldownDurationObject()
    if not info or not info.duration or not interruptCooldown then
        HideInterruptMarker(widget)
        return
    end
    markerBar:SetFillStyle(info.isChannel and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
    markerBar:SetMinMaxValues(0, info.duration:GetTotalDuration())
    markerBar:SetValue(interruptCooldown:GetRemainingDuration())
    SetMarkerLine(markerBar, markerLine, info.isChannel)
    markerBar:SetAlpha(1)
    markerLine:SetAlpha(1)
    if markerBar.SetAlphaFromBoolean then
        markerBar:SetAlphaFromBoolean(info.noInterrupt, 0, 1)
        markerBar:SetAlphaFromBoolean(interruptCooldown:IsZero(), 0, markerBar:GetAlpha())
    end
    if markerLine.SetAlphaFromBoolean then
        markerLine:SetAlphaFromBoolean(info.noInterrupt, 0, 1)
        markerLine:SetAlphaFromBoolean(interruptCooldown:IsZero(), 0, markerLine:GetAlpha())
    end
    markerLine:Show()
end

local function ApplyInterruptMarkers(controller, info, phase)
    if phase == "changing" then return end
    local function apply(collection)
        for _, item in ipairs(collection and collection.currentItems or {}) do
            if item and item.widget then ApplyInterruptMarker(item.widget, info, false) end
        end
    end
    apply(controller.runtimeCollection)
end
local function BuildEntry(itemID, info, preview)
    -- 不能写成 `preview and false or info.noInterrupt`：Lua 会把 false
    -- 当作 OR 的失败值继续求右侧，Panel preview 最终会把 nil 传入 WoW 的
    -- SetVertexColorFromBoolean。这里必须保留预览的真实 false。
    local noInterrupt
    if preview then
        noInterrupt = false
    else
        noInterrupt = info.noInterrupt
    end
    local content = preview and
        { icon = 136197, textA = L["焦点测试施法"], textB = L["玩家"], textC = "2.5", progress = .55, maximum = 1 } or
        {
            icon = info.texture,
            textA = info.name,
            textAMode = "SECRET",
            textB = info.targetName,
            textBMode = "SECRET",
            secretDuration =
                info.duration,
            interpolation = Enum.StatusBarInterpolation.None,
            direction = info.isChannel and 1 or 0
        }
    local state = preview and "READY" or InterruptState(); local normalR, normalG, normalB, normalA = GetColor(state ==
        "READY" and "timerGroup.barColor" or "interruptCDColor")
    if state == "READY" then
        normalR, normalG, normalB, normalA = DB.timerGroup.barColorR, DB.timerGroup.barColorG,
            DB.timerGroup.barColorB, DB.timerGroup.barColorA
    end
    local noR, noG, noB, noA = GetColor("nonInterruptColor"); local targetColor = nil
    if not preview and ((issecretvalue and issecretvalue(info.targetClass)) or info.targetClass) then
        local color = C_ClassColor.GetClassColor(info.targetClass); if color then
            local r, g, b, a = color:GetRGBA(); targetColor = { r = r, g = g, b = b, a = a }
        end
    end
    local alpha = state == "HIDDEN" and 0 or 1
    return { itemID = itemID, presentation = { schema = TIMER_SCHEMA, db = DB, content = content, fillFromBoolean = { value = noInterrupt, trueColor = { r = noR, g = noG, b = noB, a = noA }, falseColor = { r = normalR, g = normalG, b = normalB, a = normalA } }, alphaFromBoolean = DB.hideWhenNotInterruptible and { value = noInterrupt, trueAlpha = 0, falseAlpha = alpha } or nil, alpha = DB.hideWhenNotInterruptible and nil or alpha, textColors = targetColor and { B = targetColor } or nil, textShownFromBoolean = { B = preview or info.showTarget, C = true }, regionElements = preview and { BuildPreviewMarkerRegionElement() } or nil, interaction = EXUI:BuildStandardPreviewInteraction("TimerBar", DB, MODULE_SPEC.preview.elements) } }
end
local function Refresh()
    central:SetPreview({ BuildEntry("focuscast:preview", {}, true) }, LAYOUT)
    if not DB.enabled then return central:Clear() end
    local info = FocusInfo(); if not info then return central:Clear() end
    central:SetRuntime({ BuildEntry("focuscast:runtime", info, false) }, LAYOUT)
    ApplyInterruptMarkers(central, info, "committed")
end

RefreshActiveSurfaces = function(controller, _, phase)
    -- Slider 拖动和提交都更新已物化的同一批 surface；不再刻意跳过拖动期。
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildEntry("focuscast:preview", {}, true).presentation
    end
    local info = DB.enabled and FocusInfo() or nil
    if controller.runtimeEntries and controller.runtimeEntries[1] and info then
        controller.runtimeEntries[1].presentation = BuildEntry("focuscast:runtime", info, false).presentation
    end
    ApplyInterruptMarkers(controller, info, phase)
end
local function PlaySound(force)
    if not force and not DB.alertEnabled then return false end
    if not force and DB.alertHostileOnly and not UnitCanAttack("player", "focus") then return false end
    local source = DB.alertSource or "lsm"
    if source == "tts" then
        local text = tostring(DB.alertTtsText or "")
        local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
        if text == "" or not voices or #voices == 0 then return false end
        local rate = C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate() or 0
        pcall(C_VoiceChat.SpeakText, voices[1].voiceID, text, rate, 100)
        return true
    end
    local sound = source == "file" and DB.alertPath or (LSM and LSM:Fetch("sound", DB.alertLSM or ""))
    if type(sound) ~= "string" or sound == "" then return false end
    PlaySoundFile(sound, DB.alertChannel or "Master")
    return true
end
local function OnSpell(event, unit)
    if unit and unit ~= "focus" then return end
    if DB.enabled and (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") then
        if not (DB.muteSoundOnInterruptCD and InterruptState() ~= "READY") then
            PlaySound(false)
        end
    end
    Refresh()
end
central:SetPreview({ BuildEntry("focuscast:preview", {}, true) }, LAYOUT)
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then
    ExwindTools:ReportReady(MODULE_KEY); return
end
Refresh()
ExwindTools:RegisterEvent("PLAYER_FOCUS_CHANGED", MODULE_KEY, Refresh)
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
    ExwindTools:RegisterEvent(event, MODULE_KEY, OnSpell)
end
ExwindTools:WatchState("InterruptReady", MODULE_KEY, Refresh); ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY,
    function(info) if info and info.key == "btn_testSound" then PlaySound(true) end end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function() C_Timer.After(1, Refresh) end)
ExwindTools:ReportReady(MODULE_KEY)
