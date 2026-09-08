-- =========================================================
-- StandardTimerBar：标准计时条模块模型
-- 固定视觉模型：计时条本体 + A 文本（法术名）+ B 文本（目标名，可选）+
-- C 文本（时间）+ 图标 + 排列 + 预览拖动/右键跳转声明。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local EXUI = ExwindTools.UI
if not EXUI then return end

local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })

local StandardTimerBar = ExwindTools.StandardTimerBar or {}
ExwindTools.StandardTimerBar = StandardTimerBar

local DEFAULT_SCHEMA = {
    timerBarKey = "timerGroup",
    layoutKey = "layout",
    offsetXKey = "posX",
    offsetYKey = "posY",
    positionGridKey = "timerGroup",
    showIconKey = nil,
    showTextBKey = "showTarget",
    showTextCKey = "showTimer",
}

local DEFAULT_LAYOUT = {
    direction = "RIGHT",
    spacing = 8,
    maxVisible = 5,
}

local DEFAULT_TIMER_BAR = {
    width = 240,
    height = 24,
    texture = "Clean",
    barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
    barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
    showBorder = true,
    borderTexture = "None",
    borderSize = 1,
    borderPadding = 0,
    borderColorR = 1, borderColorG = 1, borderColorB = 1, borderColorA = 1,
    showIcon = true,
    iconWidth = 24,
    iconHeight = 24,
    iconSide = "LEFT",
    iconOffsetX = -5,
    iconOffsetY = 0,
    showIconBorder = true,
    iconBorderTexture = "None",
    iconBorderSize = 1,
    iconBorderPadding = 0,
    iconBorderColorR = 1, iconBorderColorG = 1, iconBorderColorB = 1, iconBorderColorA = 1,
    fillDirection = "LEFT_TO_RIGHT",
    progressMode = "REMAINING",
}

local DEFAULT_TEXT_A = {
    enabled = true,
    justifyH = "LEFT",
    justifyV = "MIDDLE",
    x = 5,
    y = 0,
    size = 16,
    font = "默认",
    outline = "OUTLINE",
    r = 1,
    g = 1,
    b = 1,
    a = 1,
}

local DEFAULT_TEXT_B = {
    enabled = true,
    justifyH = "RIGHT",
    justifyV = "MIDDLE",
    x = -5,
    y = 0,
    size = 14,
    font = "默认",
    outline = "OUTLINE",
    r = 0.35,
    g = 0.85,
    b = 1,
    a = 1,
}

local DEFAULT_TEXT_C = {
    enabled = true,
    justifyH = "RIGHT",
    justifyV = "MIDDLE",
    x = -5,
    y = 0,
    size = 16,
    font = "默认",
    outline = "OUTLINE",
    r = 1,
    g = 0.9,
    b = 0.2,
    a = 1,
}

local function ShallowCopy(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            result[key] = value
        end
    end
    return result
end

local function MergeMissing(target, defaults)
    target = type(target) == "table" and target or {}
    for key, value in pairs(defaults or {}) do
        if target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function CopyWithDefaults(source, defaults)
    local result = ShallowCopy(source)
    MergeMissing(result, defaults)
    return result
end

local function NormalizeTextSpec(spec, fallback)
    spec = type(spec) == "table" and spec or {}
    local result = ShallowCopy(fallback)
    for key, value in pairs(spec) do
        result[key] = value
    end
    result.key = result.key or fallback.key
    result.gridKey = result.gridKey or result.key
    result.role = result.role or fallback.role
    result.label = result.label or fallback.label
    result.priority = tonumber(result.priority) or fallback.priority
    return result
end

function StandardTimerBar.NormalizeSchema(schema)
    schema = type(schema) == "table" and schema or {}
    local result = ShallowCopy(DEFAULT_SCHEMA)
    for key, value in pairs(schema) do
        if key ~= "textA" and key ~= "textB" and key ~= "textC" then
            result[key] = value
        end
    end

    result.textA = NormalizeTextSpec(schema.textA, {
        key = "font_spell",
        gridKey = "font_spell",
        role = "spellName",
        label = L["法术名称"],
        priority = 20,
    })
    result.textB = NormalizeTextSpec(schema.textB, {
        key = "font_target",
        gridKey = "font_target",
        role = "targetName",
        label = L["目标名称"],
        priority = 30,
        optional = true,
        enabledKey = result.showTextBKey,
    })
    result.textC = NormalizeTextSpec(schema.textC, {
        key = "font_timer",
        gridKey = "font_timer",
        role = "time",
        label = L["时间"],
        priority = 25,
        enabledKey = result.showTextCKey,
    })

    return result
end

function StandardTimerBar.EnsureDefaults(db, schema)
    db = type(db) == "table" and db or {}
    schema = StandardTimerBar.NormalizeSchema(schema)

    db[schema.layoutKey] = MergeMissing(db[schema.layoutKey], DEFAULT_LAYOUT)
    db[schema.timerBarKey] = MergeMissing(db[schema.timerBarKey], DEFAULT_TIMER_BAR)
    db[schema.textA.key] = MergeMissing(db[schema.textA.key], DEFAULT_TEXT_A)
    -- Optional slots are visual capabilities, not permission for Core to add
    -- undeclared DB groups to a module.
    if schema.textB.optional ~= true then db[schema.textB.key] = MergeMissing(db[schema.textB.key], DEFAULT_TEXT_B) end
    if schema.textC.optional ~= true then db[schema.textC.key] = MergeMissing(db[schema.textC.key], DEFAULT_TEXT_C) end

    if schema.showTextBKey and db[schema.showTextBKey] == nil then
        db[schema.showTextBKey] = true
    end
    if schema.showTextCKey and db[schema.showTextCKey] == nil then
        db[schema.showTextCKey] = true
    end
    return db
end

function StandardTimerBar.BuildDefaults(schema)
    local db = {}
    StandardTimerBar.EnsureDefaults(db, schema)
    return db
end

local function IsTextEnabled(db, textSpec)
    if textSpec.enabledKey and db[textSpec.enabledKey] == false then
        return false
    end
    local style = db[textSpec.key]
    return type(style) ~= "table" or style.enabled ~= false
end

local function BuildTextStyle(db, textSpec, defaults)
    local style = CopyWithDefaults(db[textSpec.key], defaults)
    style.enabled = IsTextEnabled(db, textSpec)
    return style
end

function EXUI:BuildStandardTimerBarStyle(db, schema)
    schema = StandardTimerBar.NormalizeSchema(schema)
    db = StandardTimerBar.EnsureDefaults(db, schema)

    local timerStyle = CopyWithDefaults(db[schema.timerBarKey], DEFAULT_TIMER_BAR)
    if schema.showIconKey and db[schema.showIconKey] ~= nil then
        timerStyle.showIcon = db[schema.showIconKey] == true
    end
    -- `false` is an explicit standard-schema contract: this module has no
    -- persisted time-visibility switch, so stale generic timerGroup.showTime
    -- must not hide its C slot. Its font group's `enabled` remains the sole
    -- visibility control. `nil` and a real key keep their existing behavior.
    if schema.showTextCKey == false then
        timerStyle.showTime = true
    elseif schema.showTextCKey and db[schema.showTextCKey] ~= nil then
        timerStyle.showTime = db[schema.showTextCKey] == true
    end

    return {
        timerBar = timerStyle,
        text = {
            label = BuildTextStyle(db, schema.textA, DEFAULT_TEXT_A),
            time = BuildTextStyle(db, schema.textC, DEFAULT_TEXT_C),
        },
    }
end

function EXUI:CreateStandardTimerBarWidget(parent, schema)
    schema = StandardTimerBar.NormalizeSchema(schema)
    local widget = self:CreateTimerBarWidget(parent, self:BuildStandardTimerBarStyle({}, schema))
    widget.standardSchema = schema
    widget.textA = widget.labelText
    widget.textC = widget.timeText
    widget.textB = self:CreateTextWidget(widget.textLayer, schema.textB.role or "targetName")
    widget.textB:SetBounds(widget.bar:GetWidth() or 1, widget.bar:GetHeight() or 1)
    widget.textB:SetAnchor("CENTER", widget.bar, "CENTER")
    return widget
end

local function ApplyStyleOverrides(target, overrides)
    if type(target) ~= "table" or type(overrides) ~= "table" then return target end
    for key, value in pairs(overrides) do
        if type(value) == "table" and type(target[key]) == "table" then
            ApplyStyleOverrides(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

function EXUI:ApplyStandardTimerBarStyle(widget, db, schema, styleOverrides)
    if not widget then return nil end
    schema = StandardTimerBar.NormalizeSchema(schema or widget.standardSchema)
    db = StandardTimerBar.EnsureDefaults(db, schema)
    widget.standardSchema = schema

    local style = self:BuildStandardTimerBarStyle(db, schema)
    ApplyStyleOverrides(style, styleOverrides)
    widget:ApplyStyle(style)

    if widget.textB then
        widget.textB:SetBounds(widget.bar:GetWidth() or 1, widget.bar:GetHeight() or 1)
        widget.textB:SetAnchor("CENTER", widget.bar, "CENTER")
        local textBStyle = BuildTextStyle(db, schema.textB, DEFAULT_TEXT_B)
        ApplyStyleOverrides(textBStyle, styleOverrides and styleOverrides.text and styleOverrides.text.target)
        widget.textB:ApplyStyle(textBStyle)
        if type(widget.SetDeclaredTextSelection) == "function" then
            widget:SetDeclaredTextSelection("core.targetName", textBStyle)
        end
    end
    return widget
end

function EXUI:SetStandardTimerBarContent(widget, moduleKey, content)
    if not widget then return nil end
    EXUI:RequireModuleKey(moduleKey, "SetStandardTimerBarContent")
    content = type(content) == "table" and content or {}

    if content.iconMode == "SECRET" then
        widget:SetSecretIcon(content.icon)
    elseif content.icon ~= nil then
        widget:SetIcon(content.icon)
    end
    -- 由调用方用普通字符串 mode 明确声明秘密文本，避免在这里用 `or` / `~=` 读取文本内容。
    if content.textAMode == "SECRET" then
        widget.labelText:SetSecretText(content.textA)
        if widget.textStyles.label == nil or widget.textStyles.label.enabled ~= false then
            widget.labelText:Show()
        else
            widget.labelText:Hide()
        end
    else
        widget:SetLabel(content.textA or content.spellName or content.label or "")
    end

    if widget.textB then
        if content.textBMode == "SECRET" then
            widget.textB:SetSecretText(content.textB)
            local targetStyle = widget.textB.style
            if targetStyle == nil or targetStyle.enabled ~= false then
                widget.textB:Show()
            else
                widget.textB:Hide()
            end
        else
            widget.textB:SetText(content.textB or content.targetName or "")
        end
    end

    if content.secretDuration ~= nil then
        widget:SetSecretTime(content.secretDuration, content.interpolation, content.direction)
    elseif content.durationObject ~= nil then
        widget:SetDurationObject(content.durationObject, content.interpolation, content.direction)
    elseif content.start ~= nil and content.duration ~= nil then
        widget:SetTime(moduleKey, content.start, content.duration, content.modRate, content.countdownFormat)
    else
        widget:SetProgress(content.progress or 0, content.maximum or content.max or 1)
        if content.textC or content.timeText then
            widget.timeText:SetText(content.textC or content.timeText)
            widget.timeText:Show()
        end
    end

    if content.markers ~= nil then
        widget:SetMarkers(content.markers)
    end
    return widget
end

local function GetStandardTextSlot(widget, slot)
    if slot == "A" then return widget.textA end
    if slot == "B" then return widget.textB end
    if slot == "C" then return widget.textC end
    return nil
end

-- 标准文字槽位的颜色与 Secret 可见性属于公开语义 API；模块不得改写 TextWidget 内部 FontString。
function EXUI:SetStandardTimerBarTextColor(widget, slot, color)
    local textWidget = widget and GetStandardTextSlot(widget, slot)
    if textWidget then
        textWidget:SetColor(color)
    end
    return widget
end

function EXUI:SetStandardTimerBarTextShownFromBoolean(widget, slot, shown)
    local textWidget = widget and GetStandardTextSlot(widget, slot)
    if textWidget then
        textWidget:SetShownFromBoolean(shown)
    end
    return widget
end

function EXUI:BuildStandardTimerBarPreviewHandles(widget, schema)
    if not widget then return nil end
    schema = StandardTimerBar.NormalizeSchema(schema or widget.standardSchema)
    widget.standardSchema = schema

    -- 模块整体位置只由 AnchorController 在游戏世界编辑模式中负责。
    -- 设置页预览只声明局部文字部件，绝不让预览拖动写入模块 posX/posY。
    local handles = {}

    local function AddTextHandle(textWidget, textSpec)
        if not textWidget or not textWidget.GetRoot then return end
        handles[#handles + 1] = {
            id = textSpec.role or textSpec.key,
            getRoot = function() return textWidget:GetRoot() end,
            position = {
                x = tostring(textSpec.key) .. ".x",
                y = tostring(textSpec.key) .. ".y",
            },
            gridKey = textSpec.gridKey or textSpec.key,
            label = textSpec.label,
            priority = textSpec.priority,
            -- TextWidget 的 root 为整条 bounds；命中框只覆盖预览样本的可见字形，
            -- 但实际鼠标处理始终由独立普通 Frame 承担，不直接拖动 FontString。
            getPreviewHitBox = function()
                local root = textWidget:GetRoot()
                local fontString = textWidget.text
                if not root or not fontString then return nil end

                local width = math.max(18, (fontString:GetStringWidth() or 0) + 8)
                local height = math.max(18, (fontString:GetStringHeight() or 0) + 8)
                local rootWidth = math.max(1, root:GetWidth() or 1)
                local style = textWidget.style or {}
                local justifyH = tostring(style.justifyH or "LEFT"):upper()
                local offsetX = tonumber(style.x) or 0
                local offsetY = tonumber(style.y) or 0
                local x
                if justifyH == "RIGHT" then
                    x = (rootWidth - width) / 2 + offsetX
                elseif justifyH == "CENTER" then
                    x = offsetX
                else
                    x = -(rootWidth - width) / 2 + offsetX
                end
                return x, offsetY, width, height
            end,
        }
    end

    AddTextHandle(widget.textA, schema.textA)
    AddTextHandle(widget.textC, schema.textC)
    AddTextHandle(widget.textB, schema.textB)

    widget._exPreviewHandles = handles
    return handles
end

function EXUI:ReleaseStandardTimerBarWidget(widget)
    if not widget then return end
    if widget.textB then
        if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | standard: textB release begin") end
        widget.textB:Release()
        if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | standard: textB release complete") end
        widget.textB = nil
    end
    widget.textA = nil
    widget.textC = nil
    widget.standardSchema = nil
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | standard: enter timer widget release") end
    widget:Release()
end

function EXUI:CreateStandardTimerBarPreviewController(moduleKey, options)
    if type(options) ~= "table" then
        error("CreateStandardTimerBarPreviewController: options must be table", 2)
    end
    if type(options.getDB) ~= "function" then
        error("CreateStandardTimerBarPreviewController: options.getDB must be function", 2)
    end

    local schema = StandardTimerBar.NormalizeSchema(options.schema)
    return ExwindTools:CreatePreviewController(moduleKey, {
        getDB = options.getDB,
        getPreviewHandles = function(widget)
            return widget and widget._exPreviewHandles
        end,
        -- 模块可覆盖；未覆盖时统一由 Core 定位当前模块 Grid 的同名顶层分区。
        focusGrid = options.focusGrid or function(gridKey)
            if EXUI.FocusModuleGridKey then
                EXUI:FocusModuleGridKey(moduleKey, gridKey)
            end
        end,
        createInstance = function(parent)
            local widget
            if type(options.createInstance) == "function" then
                widget = options.createInstance(parent, schema)
            else
                widget = EXUI:CreateStandardTimerBarWidget(parent, schema)
            end
            EXUI:BuildStandardTimerBarPreviewHandles(widget, schema)
            if type(options.onCreate) == "function" then
                options.onCreate(widget, schema)
            end
            return widget
        end,
        seedContent = function(widget)
            local content = type(options.previewContent) == "function" and options.previewContent(widget, schema) or options.previewContent
            EXUI:SetStandardTimerBarContent(widget, options.moduleKey, content or {
                icon = 136243,
                textA = L["测试施法"],
                textB = L["目标"],
                textC = "2.5",
                progress = 0.6,
                maximum = 1,
            })
            if type(options.seedContent) == "function" then
                options.seedContent(widget, schema)
            end
        end,
        applyStyle = function(widget)
            EXUI:ApplyStandardTimerBarStyle(widget, options.getDB(), schema)
            if type(options.applyStyle) == "function" then
                options.applyStyle(widget, schema)
            end
        end,
        releaseInstance = function(widget)
            if type(options.releaseInstance) == "function" then
                local handled = options.releaseInstance(widget, schema)
                if handled == true then
                    return
                end
            end
            EXUI:ReleaseStandardTimerBarWidget(widget)
        end,
    })
end

function ExwindTools:BuildStandardTimerBarDefaults(schema)
    return StandardTimerBar.BuildDefaults(schema)
end

-- 标准 TimerBar 的提示图标复合控件规格。它使用现有 modulecommonsettings。
-- 内部坐标只在这里定义：逻辑宽 200、控件 46×6、X=3/53/103/153；
-- 显示在第一行第 1 列，四个 slider 在第二行四列。调用模块只放置整个 group，
-- 不得覆写 fixedLayout 或 fields 的 row/column。
function ExwindTools:BuildStandardTimerBarAlertIconsGroupOptions(schema, opts)
    schema = StandardTimerBar.NormalizeSchema(schema)
    opts = type(opts) == "table" and opts or {}
    -- 默认仍使用 TimerBar 的 alertIcons DB；其他计时条模块可只声明
    -- 已有的五个字段路径与数值范围，复用完全相同的控件树和外观。
    local prefix = schema.timerBarKey .. ".alertIcons."
    local paths = opts.paths
    if paths ~= nil and type(paths) ~= "table" then
        error("BuildStandardTimerBarAlertIconsGroupOptions: opts.paths must be table", 2)
    end
    paths = paths or {}
    local function Path(key, fallback)
        local path = paths[key]
        if path == nil then return fallback end
        if type(path) ~= "string" or path == "" then
            error("BuildStandardTimerBarAlertIconsGroupOptions: opts.paths." .. key .. " must be non-empty string", 2)
        end
        return path
    end
    local ranges = opts.ranges
    if ranges ~= nil and type(ranges) ~= "table" then
        error("BuildStandardTimerBarAlertIconsGroupOptions: opts.ranges must be table", 2)
    end
    ranges = ranges or {}
    local function Range(key, defaultMin, defaultMax, defaultStep)
        local range = ranges[key]
        if range == nil then return defaultMin, defaultMax, defaultStep end
        if type(range) ~= "table" then
            error("BuildStandardTimerBarAlertIconsGroupOptions: opts.ranges." .. key .. " must be table", 2)
        end
        return tonumber(range.min) or defaultMin, tonumber(range.max) or defaultMax, tonumber(range.step) or defaultStep
    end
    local widthMin, widthMax, widthStep = Range("width", 6, 80, 1)
    local heightMin, heightMax, heightStep = Range("height", 6, 80, 1)
    local xMin, xMax, xStep = Range("x", -100, 100, 1)
    local yMin, yMax, yStep = Range("y", -100, 100, 1)
    return {
        bindRoot = true,
        poolType = "StandardTimerBarAlertIconsGroup",
        fixedLayout = {
            logicalWidth = 200,
            controlW = 46,
            controlH = 6,
            slotX = { 3, 53, 103, 153 },
            firstY = 0,
            rowStep = 14,
        },
        fields = {
            { path = Path("show", prefix .. "showIcon"), type = "checkbox", label = L["显示"], row = 1, column = 1 },
            { path = Path("width", prefix .. "width"), type = "slider", label = L["宽度"], min = widthMin, max = widthMax, step = widthStep, row = 2, column = 1 },
            { path = Path("height", prefix .. "height"), type = "slider", label = L["高度"], min = heightMin, max = heightMax, step = heightStep, row = 2, column = 2 },
            { path = Path("x", prefix .. "x"), type = "slider", label = L["X 偏移"], min = xMin, max = xMax, step = xStep, row = 2, column = 3 },
            { path = Path("y", prefix .. "y"), type = "slider", label = L["Y 偏移"], min = yMin, max = yMax, step = yStep, row = 2, column = 4 },
        },
        onFieldChanged = opts.onFieldChanged,
    }
end

function ExwindTools:AppendStandardTimerBarLayout(layout, schema, opts)
    layout = type(layout) == "table" and layout or {}
    schema = StandardTimerBar.NormalizeSchema(schema)
    opts = type(opts) == "table" and opts or {}

    local x = tonumber(opts.x) or 1
    local y = tonumber(opts.y) or 1
    local w = tonumber(opts.w) or 53
    local titleSize = tonumber(opts.titleSize) or 20
    local function Add(item)
        layout[#layout + 1] = item
    end

    if opts.includeLayout ~= false then
        Add({ key = schema.layoutKey, type = "widgetlayout", x = x, y = y, w = w, h = 12, label = opts.layoutLabel or L["排列设置"], labelSize = titleSize })
        y = y + 14
    end

    Add({ key = schema.timerBarKey, type = "timerBarGroup", x = x, y = y, w = w, h = 27, label = opts.timerBarLabel or L["计时条设置"], labelSize = titleSize })
    y = y + 29

    Add({ key = schema.textA.key .. "_header", type = "header", x = x, y = y, w = w, h = 2, label = schema.textA.label or L["法术名称"], labelSize = titleSize })
    Add({ key = schema.textA.key, type = "fontgroup", x = x, y = y + 4, w = w, h = 50, label = schema.textA.label or L["法术名称"], labelSize = titleSize })
    y = y + 48

    if schema.textB.optional ~= false and schema.showTextBKey then
        Add({ key = schema.showTextBKey, type = "checkbox", x = x, y = y, w = 12, h = 2, label = opts.textBVisibleLabel or L["显示目标文字"] })
        y = y + 4
    end
    Add({ key = schema.textB.key .. "_header", type = "header", x = x, y = y, w = w, h = 2, label = schema.textB.label or L["目标名称"], labelSize = titleSize })
    Add({ key = schema.textB.key, type = "fontgroup", x = x, y = y + 4, w = w, h = 50, label = schema.textB.label or L["目标名称"], labelSize = titleSize })
    y = y + 48

    if schema.showTextCKey then
        Add({ key = schema.showTextCKey, type = "checkbox", x = x, y = y, w = 12, h = 2, label = opts.textCVisibleLabel or L["显示时间文字"] })
        y = y + 4
    end
    Add({ key = schema.textC.key .. "_header", type = "header", x = x, y = y, w = w, h = 2, label = schema.textC.label or L["时间"], labelSize = titleSize })
    Add({ key = schema.textC.key, type = "fontgroup", x = x, y = y + 4, w = w, h = 50, label = schema.textC.label or L["时间"], labelSize = titleSize })
    y = y + 48

    return y
end
