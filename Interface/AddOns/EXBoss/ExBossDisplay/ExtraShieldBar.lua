---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- EXBoss ExtraShieldBar
-- 唯一可见路径：BuildPresentation -> ApplyRecord -> SetItems。
-- Runtime / World Edit / Panel 只改变 payload、parent 和交互权限。
-- =============================================================

do
    ExBoss = ExBoss or {}
    ExBoss.UI = ExBoss.UI or {}
    local Mod = ExBoss.UI.ExtraShieldBar or {}
    ExBoss.UI.ExtraShieldBar = Mod

    local ExwindTools = _G.ExwindTools
    if not ExwindTools or not ExwindTools.UI then return end
    local EXUI = ExwindTools.UI
    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
    local MODULE_KEY = "ExBoss.ExtraShieldBar"
    local RUNTIME_RECORD_ID = "extrashield:runtime"
    local SAMPLE_RECORD_ID = "extrashield:sample"
    local PANEL_PREVIEW_MIN_HEIGHT = 160
    -- 唯一可编辑默认值真源。运行、世界编辑、Panel 与 Page 只读取同一
    -- ModuleDB；禁止 GetModuleDB 第二 defaults、fallback 或旧 DB 兼容层。
    local EX_DEFAULTS = {
        module = {
            enabled = true, showValue = false, anchorX = 11, anchorY = -348,
            attachToCustom = false, customAttachTarget = "",
        },
        layout = { direction = "DOWN", spacing = 0, maxVisible = 1 },
        timerGroup = {
            width = 220, height = 30, texture = "EX_WhiteTexture",
            barColorR = 0.2902, barColorG = 0.9098, barColorB = 1, barColorA = 1,
            barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
            showBorder = true, borderTexture = "EX_Default", borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1, borderSize = 0.90000003576279, borderPadding = 0.6,
            showIcon = true, iconSide = "LEFT", iconWidth = 30, iconHeight = 30, iconOffsetX = -2, iconOffsetY = 0,
            showIconBorder = true, iconBorderTexture = "EX_Default", iconBorderColorR = 0, iconBorderColorG = 0, iconBorderColorB = 0, iconBorderColorA = 1, iconBorderSize = 0, iconBorderPadding = 0.6,
            fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
        },
        font_spell = { font = "默认", size = 18, r = 1, g = 1, b = 1, a = 1, enabled = false, autoWidth = false, fixedWidth = 200, maxWidth = 0, justifyH = "LEFT", justifyV = "MIDDLE", outline = "OUTLINE", shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1, shadowX = 1, shadowY = -1, rotation = 0, gradientEnabled = false, gradientStart = 0, gradientLength = 0, drawLayer = "OVERLAY", drawSubLevel = 0, x = -7, y = 0 },
    font_timer = { font = "默认", size = 18, r = 1, g = 1, b = 1, a = 1, enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0, justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE", shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1, shadowX = 1, shadowY = -1, rotation = 0, gradientEnabled = false, gradientStart = 0, gradientLength = 0, drawLayer = "OVERLAY", drawSubLevel = 0, x = -13.583842708562, y = 0 },
    }

    local MODULE_FIELDS = { "enabled", "showValue", "anchorX", "anchorY", "attachToCustom", "customAttachTarget" }
    local LAYOUT_FIELDS = { "direction", "spacing", "maxVisible" }
    local FONT_FIELDS = {
        "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
        "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB",
        "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart",
        "gradientLength", "drawLayer", "drawSubLevel", "x", "y",
    }
    local TIMER_BAR_FIELDS = {
        "width", "height", "texture", "barColorR", "barColorG", "barColorB", "barColorA",
        "barBgColorR", "barBgColorG", "barBgColorB", "barBgColorA", "showBorder", "borderTexture",
        "borderColorR", "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding",
        "showIcon", "iconSide", "iconWidth", "iconHeight", "iconOffsetX", "iconOffsetY",
        "showIconBorder", "iconBorderTexture", "iconBorderColorR", "iconBorderColorG", "iconBorderColorB",
        "iconBorderColorA", "iconBorderSize", "iconBorderPadding", "fillDirection", "progressMode",
    }
    local DEFAULT_SCHEMA = {
        { group = "module", root = true, fields = MODULE_FIELDS },
        { group = "layout", fields = LAYOUT_FIELDS },
        { group = "timerGroup", fields = TIMER_BAR_FIELDS },
        { group = "font_spell", fields = FONT_FIELDS },
        { group = "font_timer", fields = FONT_FIELDS },
    }
    local DEFAULTS = ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

    -- 模块仅声明可命中元素、GUI key 和同一 ModuleDB 的位置路径。EXUI
    -- 统一拥有 Panel 右键 Focus、拖动写回与 Grid 回读。
    local INTERACTION_SCHEMA = {
        ["core.spellName"] = {
            guiKey = "font_spell", movable = true, tooltip = L["护盾名称"], textRole = "label",
            position = { x = "font_spell.x", y = "font_spell.y" },
            anchor = { point = "LEFT", relativeElement = "core.bar", relativePoint = "LEFT" },
        },
        ["core.time"] = {
            guiKey = "font_timer", movable = true, tooltip = L["护盾数值"], textRole = "time",
            position = { x = "font_timer.x", y = "font_timer.y" },
            anchor = { point = "CENTER", relativeElement = "core.bar", relativePoint = "CENTER" },
        },
    }

    local function BuildStandardExtraShieldInteraction(db)
        return EXUI:BuildStandardPreviewInteraction("TimerBar", db, INTERACTION_SCHEMA)
    end

    local CONFIG_SCHEMA_PATHS = {
        ["timerGroup.width"] = true, ["timerGroup.height"] = true,
        ["timerGroup.borderSize"] = true, ["timerGroup.borderPadding"] = true,
        ["timerGroup.iconOffsetX"] = true, ["timerGroup.iconWidth"] = true,
        ["timerGroup.iconHeight"] = true, ["timerGroup.iconOffsetY"] = true,
        ["timerGroup.iconBorderSize"] = true, ["timerGroup.iconBorderPadding"] = true,
        ["font_spell.size"] = true, ["font_spell.x"] = true, ["font_spell.y"] = true,
        ["font_spell.shadowX"] = true, ["font_spell.shadowY"] = true,
        ["font_spell.fixedWidth"] = true, ["font_spell.maxWidth"] = true,
        ["font_spell.gradientStart"] = true, ["font_spell.gradientLength"] = true,
        ["font_spell.rotation"] = true, ["font_spell.autoWidth"] = true,
        ["font_timer.size"] = true, ["font_timer.x"] = true, ["font_timer.y"] = true,
        ["font_timer.shadowX"] = true, ["font_timer.shadowY"] = true,
        ["font_timer.fixedWidth"] = true, ["font_timer.maxWidth"] = true,
        ["font_timer.gradientStart"] = true, ["font_timer.gradientLength"] = true,
        ["font_timer.rotation"] = true, ["font_timer.autoWidth"] = true,
    }

    Mod.StandardSliderContract = {
        groupPaths = {
            timerGroup = "timerGroup",
            font_spell = "font_spell",
            font_timer = "font_timer",
        },
    }

    local anchorFrame, anchorController
    local runtimeCollection, worldCollection, panelPreview, panelDock, panelSurface
    local currentSourceKey, currentPayload, runtimeRecord
    -- 第五种护盾渲染模式：秘密进度直传主原生 StatusBar。
    -- 它不进入 Collection，只由显式请求该模式的护盾模块使用。
    local directSecretFrame, directSecretWidget, directSecretActive

    local function DB()
        local db = ExwindTools:GetModuleDB(MODULE_KEY)
        if type(db) ~= "table" then error("ExtraShieldBar ModuleDB is unavailable", 2) end
        return db
    end

    function Mod:GetDB()
        return DB()
    end

    local function Num(value, fallback)
        value = tonumber(value)
        return value or fallback
    end

    -- 旧版护盾条用 AbbreviateNumbers 将秘密护盾值交给原生格式化器，得到
    -- 可直接写入 FontString 的秘密百分比文本；不得在 Lua 中计算 value / maxValue。
    local function FormatSecretShieldPercent(secretValue, maxValue)
        local maximum = Num(maxValue, 0)
        if maximum <= 0 or type(AbbreviateNumbers) ~= "function" then return nil end
        local ok, text = pcall(AbbreviateNumbers, secretValue, {
            breakpointData = {
                {
                    breakpoint = 0,
                    abbreviation = "%",
                    significandDivisor = maximum / 100,
                    fractionDivisor = 1,
                    abbreviationIsGlobal = false,
                },
            },
        })
        return ok and type(text) == "string" and text or nil
    end

    local function ResolveTimerStyle()
        return DB().timerGroup
    end

    local function GetLayout()
        local layout = DB().layout
        local direction = tostring(layout.direction):upper()
        if direction ~= "UP" and direction ~= "DOWN" then
            error("ExtraShieldBar layout.direction must be UP or DOWN", 2)
        end
        return { mode = "FLOW", direction = direction, spacing = layout.spacing, maxVisible = 1 }
    end

    -- 整体锚点只在这里声明。世界编辑整体拖动与 Page AnchorGroup 消费同一个
    -- CreateStandardModuleAnchor 返回值，禁止再手写第二份 key/default/picker。
    local ANCHOR_SCHEMA = {
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_ExtraShieldBar_Anchor",
        title = L["额外护盾条"],
        getDB = DB,
        offsetXKey = "anchorX",
        offsetYKey = "anchorY",
        defaultOffsetX = DEFAULTS.anchorX,
        defaultOffsetY = DEFAULTS.anchorY,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        syncWidgets = { "anchorX", "anchorY", "attachToCustom", "customAttachTarget" },
        widgetRanges = {
            anchorX = { min = -1000, max = 1000, step = 1 },
            anchorY = { min = -600, max = 600, step = 1 },
        },
        initialWidth = DEFAULTS.timerGroup.width,
        initialHeight = DEFAULTS.timerGroup.height,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        onCreateFrame = function(_, owner) owner:Hide() end,
    }

    local function EnsureAnchorController()
        if anchorController then return anchorController end
        anchorController, Mod.StandardAnchorGroupOptions = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)
        return anchorController
    end

    function Mod:GetStandardAnchorGroupOptions()
        EnsureAnchorController()
        return Mod.StandardAnchorGroupOptions
    end

    local function EnsureAnchor()
        if not anchorFrame then anchorFrame = EnsureAnchorController():Ensure() end
        local style = ResolveTimerStyle()
        anchorFrame:SetSize(style.width, math.max(20, style.height))
        EnsureAnchorController():ApplyPosition()
        return anchorFrame
    end

    local function HideDirectSecretProgress()
        directSecretActive = false
        if directSecretFrame then directSecretFrame:Hide() end
    end

    local function EnsureDirectSecretProgress()
        if directSecretFrame then return directSecretFrame, directSecretWidget end
        directSecretFrame = CreateFrame("Frame", "ExBoss_ExtraShieldBar_DirectSecretProgress", UIParent)
        directSecretFrame:SetFrameStrata("DIALOG")
        directSecretFrame:SetFrameLevel(200)
        directSecretFrame:Hide()
        directSecretWidget = EXUI:CreateTimerBarWidget(directSecretFrame)
        directSecretWidget:SetPoint("TOPLEFT", directSecretFrame, "TOPLEFT", 0, 0)
        return directSecretFrame, directSecretWidget
    end

    local function RenderDirectSecretProgress(payload)
        local anchor = EnsureAnchor()
        local db, style = DB(), ResolveTimerStyle()
        local frame, widget = EnsureDirectSecretProgress()
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        frame:SetSize(math.max(1, Num(style.width, 220)), math.max(1, Num(style.height, 30)))
        widget:ApplyStyle({ timerBar = style, text = { label = db.font_spell, time = db.font_timer } })
        widget:SetIcon(payload.icon or 136197)
        widget:SetLabel(payload.name or L["护盾"])
        widget.timeText:ClearDurationBinding()
        local percentText = FormatSecretShieldPercent(payload.value, payload.maxValue)
        if percentText ~= nil then
            widget.timeText:SetSecretText(percentText)
            widget.timeText:SetShown(db.font_timer.enabled ~= false)
        else
            widget.timeText:SetText("")
            widget.timeText:Hide()
        end
        widget:SetFillVisible(true)
        widget.secretBar:Hide()
        widget.bar:Show()
        if Enum and Enum.StatusBarInterpolation then
            widget.bar:SetMinMaxValues(0, math.max(1, Num(payload.maxValue, 1)), Enum.StatusBarInterpolation.Immediate)
        else
            widget.bar:SetMinMaxValues(0, math.max(1, Num(payload.maxValue, 1)))
        end
        if Enum and Enum.StatusBarInterpolation then
            widget.bar:SetValue(payload.value, Enum.StatusBarInterpolation.Immediate)
        else
            widget.bar:SetValue(payload.value)
        end
        if type(widget.bar.SetToTargetValue) == "function" then widget.bar:SetToTargetValue() end
        directSecretActive = true
        frame:Show()
    end

    local function BuildComparisonElements(db, payload, comparison)
        if comparison ~= true then return {} end
        local style = db.timerGroup
        local width, height = math.max(1, Num(style.width, 200)), math.max(1, Num(style.height, 30))
        local displayMaximum, fillScale = math.max(1, Num(payload.displayMaximum, 150)), math.max(.01, Num(payload.fillScale, 1))
        local visualWidth = math.max(1, width * fillScale / (displayMaximum / 100))
        local function Marker(id, percent)
            return {
                id = id, kind = "texture", stylePath = "timerGroup", style = style,
                anchor = { point = "TOPLEFT", relativeElement = "elements.comparison", relativePoint = "TOPLEFT", x = width * percent / displayMaximum, y = 0 },
                bounds = { width = 1, height = height },
                content = { texture = "Interface\\Buttons\\WHITE8X8", color = { r = 1, g = .85, b = 0, a = 1 } },
            }
        end
        return {
            {
                id = "comparison", kind = "timerbar", stylePath = "timerGroup", style = style,
                anchor = { point = "CENTER", relativeElement = "core.bar", relativePoint = "CENTER", x = 0, y = 0 },
                bounds = { width = width, height = height },
                content = { viewport = true, geometry = { width = visualWidth, height = height }, presentationOptions = { showIcon = false }, hasSecretProgress = true, value = payload.value, maximum = payload.maxValue },
            },
            Marker("comparison100", 100),
            { id = "comparison100Label", kind = "text", stylePath = "font_timer", style = db.font_timer,
                anchor = { point = "BOTTOM", relativeElement = "elements.comparison100", relativePoint = "TOP", x = 0, y = 1 }, bounds = { width = 40, height = 14 }, content = { text = "100%" } },
            Marker("comparison110", 110),
            { id = "comparison110Label", kind = "text", stylePath = "font_timer", style = db.font_timer,
                anchor = { point = "BOTTOM", relativeElement = "elements.comparison110", relativePoint = "TOP", x = 0, y = 1 }, bounds = { width = 40, height = 14 }, content = { text = "110%" } },
        }
    end

    local function BuildPresentation(payload, sample)
        payload = type(payload) == "table" and payload or {}
        local db, style = DB(), ResolveTimerStyle()
        local comparison = sample ~= true and payload.secretComparison == true
        local secretProgress = sample ~= true and payload.secretProgress == true
        local shownText = payload.text ~= nil
        local progress
        if secretProgress then
            -- `value` may be a Blizzard secret number.  Keep it entirely out
            -- of Lua fallback/clamp code and let TimerBarCollection forward it
            -- through TimerBarWidget:SetSecretProgress.
            progress = { mode = "SECRET", value = payload.value, maximum = payload.maxValue, minimum = payload.minValue }
        elseif comparison then
            progress = { value = 0, maximum = 1 }
        else
            progress = { value = payload.value or 0, maximum = payload.maxValue or 1 }
        end
        return {
            style = { timerBar = style, text = { label = db.font_spell, time = db.font_timer } },
            icon = { value = payload.icon or 136197 },
            label = payload.name or L["护盾"],
            time = shownText and { text = payload.text, shown = true } or nil,
            progress = progress,
            fillVisible = comparison ~= true,
            regionElements = BuildComparisonElements(db, payload, comparison),
            interaction = BuildStandardExtraShieldInteraction(db),
        }
    end

    local function ApplyRecord(collection, record, sample)
        if not collection or not record then return end
        record.item = record.item or collection:AcquireItem(record.id)
        collection:ApplyItem(record.item, BuildPresentation(record.payload, sample))
    end

    local function SetItems(collection, records)
        local items = {}
        for _, record in ipairs(records or {}) do items[#items + 1] = record.item end
        collection:SetItems(items, GetLayout())
    end

    local function RenderRuntime()
        local host = EnsureAnchor()
        runtimeCollection = runtimeCollection or EXUI:CreateTimerBarCollection(host, "runtime", MODULE_KEY)
        if not currentPayload or DB().enabled ~= true then
            if runtimeRecord then runtimeCollection:ReleaseItem(runtimeRecord.id); runtimeRecord = nil end
            runtimeCollection:SetItems({}, GetLayout())
            host:Hide()
            return
        end
        runtimeRecord = runtimeRecord or { id = RUNTIME_RECORD_ID }
        runtimeRecord.payload = currentPayload
        ApplyRecord(runtimeCollection, runtimeRecord, false)
        SetItems(runtimeCollection, { runtimeRecord })
        host:Show()
    end

    local function SampleRecord()
        local spell = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(1282770) or nil
        return {
            id = SAMPLE_RECORD_ID,
            payload = {
                name = L["护盾样本"],
                -- 1282770 是法术 ID；TimerBarWidget 需要的是实际纹理 FileID。
                icon = spell and spell.iconID or 136197,
                value = 68,
                maxValue = 100,
                text = "68%",
            },
        }
    end

    local function RenderSampleCollection(collection)
        if not collection then return end
        local record = SampleRecord()
        ApplyRecord(collection, record, true)
        SetItems(collection, { record })
    end

    -- Panel 样本仍复用 BuildPresentation；StandardPreviewSurface 只持有 Core
    -- 唯一 session，模块不得自行 Acquire/Apply/SetItems 另一棵预览树。
    local function BuildPanelSurfacePresentation(_, mode)
        if mode ~= "panel" then error("ExtraShieldBar panel surface only supports panel mode", 2) end
        local record = SampleRecord()
        return {
            entries = {
                { itemID = record.id, presentation = BuildPresentation(record.payload, true) },
            },
            layout = GetLayout(),
        }
    end

    local function EnsurePanelSurface()
        if panelSurface then return panelSurface end
        panelSurface = EXUI:CreateStandardPreviewSurface({
            moduleKey = MODULE_KEY,
            kind = "timerbar",
            buildPresentation = BuildPanelSurfacePresentation,
            interactionSchema = INTERACTION_SCHEMA,
            requiredPositionGuiKeys = { "font_spell", "font_timer" },
        })
        return panelSurface
    end

    local function ResizePanelDock(dock, session)
        if not dock or not session then return end
        local _, height = session:GetBounds()
        dock:SetHeight(math.max(PANEL_PREVIEW_MIN_HEIGHT, (height or 0) + 28))
    end

    local function RenderPanelPreview()
        if not panelSurface or not panelDock then return end
        panelPreview = panelSurface:Render({
            dock = panelDock,
            ruleKey = MODULE_KEY,
            state = true,
        })
        ResizePanelDock(panelDock, panelPreview)
    end

    function Mod:RenderWorld(host)
        if not host then return end
        -- AnchorController 的宿主默认隐藏。世界编辑和 runtime 共享这个语义
        -- Anchor；进入编辑时必须显式显示它，而不是另建 preview Frame。
        local anchor = EnsureAnchor()
        anchor:Show()
        -- 世界样本替代 runtime item。仅 Hide 旧 root 会把 runtime collection
        -- 留在同一 Anchor 上；清空 collection 才能保证这里只有一棵样本树。
        if runtimeCollection then runtimeCollection:SetItems({}, GetLayout()) end
        runtimeRecord = nil
        if worldCollection then worldCollection:Release() end
        worldCollection = EXUI:CreateTimerBarCollection(host, "world", MODULE_KEY)
        RenderSampleCollection(worldCollection)
    end

    function Mod:GetWorldBounds()
        return worldCollection and worldCollection:GetWorldBounds() or nil
    end

    function Mod:ReleaseWorld()
        if worldCollection then worldCollection:Release(); worldCollection = nil end
        RenderRuntime()
    end

    function Mod:ShowPanelPreview(dock)
        if not dock then return end
        local surface = EnsurePanelSurface()
        panelDock = dock
        panelPreview = surface:Render({
            dock = dock,
            ruleKey = MODULE_KEY,
            state = true,
        })
        ResizePanelDock(dock, panelPreview)
    end

    function Mod:RefreshPanelPreview()
        if not panelPreview then return end
        RenderPanelPreview()
    end

    function Mod:ReleasePanelPreview()
        if panelSurface then panelSurface:Release() end
        panelPreview = nil
        panelDock = nil
    end

    function Mod:RefreshVisuals(options)
        EnsureAnchor()
        if directSecretActive and currentPayload then
            RenderDirectSecretProgress(currentPayload)
        elseif worldCollection then
            RenderSampleCollection(worldCollection)
            if EXUI.SetEditModeOverlayVisible and EXUI.EditModeState then EXUI:SetEditModeOverlayVisible(EXUI.EditModeState.overlayVisible) end
        else
            RenderRuntime()
        end
        -- 外部调用未传 options 时保留完整 Panel 刷新；标准 Slider 放开时，
        -- 仅同步 runtime/world，只有 旧字段补丁 明确要求重建才刷新 Panel。
        if options == nil or options.rebuildPanelPreview == true then
            self:RefreshPanelPreview()
        end
    end

    function Mod:Show(sourceKey, payload)
        currentSourceKey = tostring(sourceKey or MODULE_KEY)
        currentPayload = type(payload) == "table" and payload or nil
        if currentPayload and currentPayload.progressMode == "SECRET_DIRECT_PROGRESS" then
            if runtimeCollection then runtimeCollection:SetItems({}, GetLayout()) end
            EnsureAnchor():Hide()
            RenderDirectSecretProgress(currentPayload)
            return
        end
        HideDirectSecretProgress()
        if not worldCollection then RenderRuntime() end
    end

    function Mod:Update(sourceKey, payload) self:Show(sourceKey, payload) end

    function Mod:Hide(sourceKey)
        if sourceKey ~= nil and tostring(sourceKey) ~= tostring(currentSourceKey or "") then return end
        currentSourceKey, currentPayload = nil, nil
        if directSecretActive then
            HideDirectSecretProgress()
            return
        end
        if not worldCollection then RenderRuntime() end
    end

    function Mod:StartFramePicker() return EnsureAnchorController():StartFramePicker() end

    EnsureAnchor()
    runtimeCollection = EXUI:CreateTimerBarCollection(anchorFrame, "runtime", MODULE_KEY)
    RenderRuntime()

    ExwindTools.UI:RegisterEditableModule({
        addon = "EXBoss", key = "extrashieldbar", name = L["额外护盾条"], settingsPage = "extrashieldbar", appearanceProfile = "basicTimerBar", orientation = "HORIZONTAL",
        worldAnchorMode = "semantic-root", editOverlay = { titleFontSize = 30 }, getAnchor = EnsureAnchor,
        RenderWorld = function(host) return Mod:RenderWorld(host) end,
        ReleaseWorld = function() return Mod:ReleaseWorld() end,
        GetWorldBounds = function() return Mod:GetWorldBounds() end,
    })

    for _, path in ipairs({ "anchorX", "anchorY", "attachToCustom", "customAttachTarget" }) do CONFIG_SCHEMA_PATHS[path] = true end
    local STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
        moduleKey = MODULE_KEY,
        getConfig = DB,
        reapplyExisting = function()
            local function reapply(surface)
                if surface and type(surface.ReapplyPanelPresentation) == "function" then
                    surface:ReapplyPanelPresentation()
                elseif surface and type(surface.ReapplyCurrentItems) == "function" then
                    surface:ReapplyCurrentItems()
                end
            end
            reapply(panelSurface)
            reapply(panelPreview)
            reapply(worldCollection)
            reapply(runtimeCollection)
        end,
        -- 拖动仅改当前已物化的 Panel Item；不 Render、不 Acquire/Release。
        schemaPaths = CONFIG_SCHEMA_PATHS,
    })
    local function RefreshActiveSurfaces()
        return STANDARD_CONFIG_BINDING.reapplyExisting()
    end
    EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })
end
