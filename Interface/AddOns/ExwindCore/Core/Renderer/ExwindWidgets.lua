-- =========================================================
-- ExwindWidgets.lua
-- 运行时 Widget：统一承接实际战斗/预览渲染，不负责设置 GUI。
-- =========================================================

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
local EXDB = _G.EXDB
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local C_DurationUtil, C_StringUtil, Enum = _G.C_DurationUtil, _G.C_StringUtil, _G.Enum
local issecretvalue = _G.issecretvalue
if not EXUI or not EXFactory or not EXDB then return end

local TEXT_WIDGET_POOL = "RuntimeTextWidget"

local DEFAULT_TEXT_STYLE = {
    enabled = true,
    size = 14,
    r = 1, g = 1, b = 1, a = 1,
    outline = "OUTLINE",
    shadow = false,
    shadowX = 1, shadowY = -1,
    shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
    x = 0, y = 0,
        autoWidth = false,
    maxWidth = 0,
    fixedWidth = 200,
    justifyH = "LEFT", justifyV = "MIDDLE",
    wordWrap = false,
    drawLayer = "OVERLAY", drawSubLevel = 0,
    gradientEnabled = false,
    rotation = 0,
}

-- 倒数的“数字格式”独立于文字样式。图标与计时条共用这一套规则，
-- 之后由 CreateTimeFormatGroup 写入同结构配置。
local DEFAULT_COUNTDOWN_FORMAT = {
    showDecimals = true,
    decimalThreshold = 10,
    decimalPlaces = 1,
    minuteFormat = "MINUTES", -- 60 秒以上：1m
    hourFormat = "HOURS",     -- 1 小时以上：1h
    integerRounding = "ROUND", -- ROUND / CEIL / FLOOR
    zeroText = "",
}

local function NumberOr(value, fallback)
    local number = tonumber(value)
    return number or fallback
end

local function IsSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function ReadSafeDimension(owner, methodName, fallback)
    local method = owner and owner[methodName]
    if type(method) ~= "function" then
        return fallback
    end

    local value = method(owner)
    if IsSecretValue(value) then
        return fallback
    end

    value = tonumber(value)
    if not value then
        return fallback
    end

    return math.max(1, value)
end

local function GetStyleValue(style, key)
    local value = style and style[key]
    if value == nil then value = DEFAULT_TEXT_STYLE[key] end
    return value
end

local function GetCountdownRule(rules, key)
    local value = rules and rules[key]
    if value == nil then value = DEFAULT_COUNTDOWN_FORMAT[key] end
    return value
end

-- 仅处理普通数字。Secret Duration/Text 必须走暴雪允许的 Duration/FontString 渲染路径，
-- 不能传入本函数做 tonumber、比较或字符串拼接。
function EXUI:FormatCountdown(remaining, rules)
    local seconds = tonumber(remaining) or 0
    if seconds <= 0 then
        return GetCountdownRule(rules, "zeroText") or ""
    end

    local minuteFormat = tostring(GetCountdownRule(rules, "minuteFormat") or "CLOCK"):upper()
    local hourFormat = tostring(GetCountdownRule(rules, "hourFormat") or "CLOCK"):upper()
    if seconds >= 86400 then
        return string.format("%dd", math.floor(seconds / 86400 + 0.5))
    end
    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600)
        if hourFormat == "HOURS" then
            return string.format("%dh", hours)
        end
        return string.format("%d:%02d:%02d", hours, math.floor((seconds % 3600) / 60), math.floor(seconds % 60))
    end
    if seconds >= 60 then
        local minutes = math.floor(seconds / 60)
        if minuteFormat == "MINUTES" then
            return string.format("%dm", minutes)
        end
        return string.format("%d:%02d", minutes, math.floor(seconds % 60))
    end

    local decimalThreshold = math.max(0, NumberOr(GetCountdownRule(rules, "decimalThreshold"), 10))
    if GetCountdownRule(rules, "showDecimals") ~= false and seconds < decimalThreshold then
        local places = math.max(0, math.min(3, math.floor(NumberOr(GetCountdownRule(rules, "decimalPlaces"), 1))))
        return string.format("%." .. places .. "f", seconds)
    end

    local rounding = tostring(GetCountdownRule(rules, "integerRounding") or "ROUND"):upper()
    if rounding == "CEIL" then
        return tostring(math.ceil(seconds))
    elseif rounding == "FLOOR" then
        return tostring(math.floor(seconds))
    end
    return tostring(math.floor(seconds + 0.5))
end

local function ApplyTextAnchor(widget)
    local text = widget.text
    local override = widget._stylePositionOverride
    local offsetX = override and override.x or NumberOr(GetStyleValue(widget.style, "x"), 0)
    local offsetY = override and override.y or NumberOr(GetStyleValue(widget.style, "y"), 0)
    text:ClearAllPoints()
    -- Unbounded text must not use opposite-corner anchors: that gives the
    -- FontString its parent's width and silently clips Secret/Duration values
    -- which Lua is not allowed to measure.  One center anchor leaves width
    -- wholly content-defined in every host.
    if GetStyleValue(widget.style, "unboundedWidth") == true then
        text:SetPoint("CENTER", widget, "CENTER", offsetX, offsetY)
        return
    end
    text:SetPoint("TOPLEFT", widget, "TOPLEFT", offsetX, offsetY)
    text:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", offsetX, offsetY)
end

local function RefreshTextLayout(widget)
    local style = widget.style or DEFAULT_TEXT_STYLE
    local width, height

    if widget._boundsWidth then
        width = widget._boundsWidth
        height = widget._boundsHeight
        -- TimerBar 等组合控件会提供文字可活动范围（Bounds），但固定宽度仍必须
        -- 覆盖该范围；否则布局面板的“固定宽度”改变不了计时条预览或运行时文字。
        local fixedWidth = NumberOr(style.fixedWidth, 0)
        local fixedWidthEnabled = style.unboundedWidth ~= true and (style.fixedWidthEnabled == true or style.autoWidth == false)
        if fixedWidthEnabled and fixedWidth > 0 then
            width = math.max(1, fixedWidth)
        elseif fixedWidthEnabled and widget._secretText ~= true then
            -- 普通 TextWidget 也可能因为父级曾锚定 Secret FontString 而继承受保护的几何值。
            -- 必须检查 API 的返回值，不能只依赖 _secretText 标记。
            width = ReadSafeDimension(widget.text, "GetStringWidth", width)
        end
    elseif widget._measureText then
        -- 只有普通文本走尺寸测量。机密文本请使用 SetSecretText + SetBounds，
        -- 全程只交给暴雪 FontString 渲染，不读取其内容或派生数值。
        local currentWidth = ReadSafeDimension(widget, "GetWidth", 1)
        local currentHeight = ReadSafeDimension(widget, "GetHeight", 1)
        width = ReadSafeDimension(widget.text, "GetStringWidth", currentWidth)
        height = ReadSafeDimension(widget.text, "GetStringHeight", currentHeight)

        local fixedWidthEnabled = style.unboundedWidth ~= true and (style.fixedWidthEnabled == true or style.autoWidth == false)
        local fixedWidth = NumberOr(style.fixedWidth, 0)
        -- 固定宽度 0 表示不强制宽度；GUI 可以安全使用 0 作为最小值，
        -- 不会把文字 Root 压成 1 像素。
        if fixedWidthEnabled and fixedWidth > 0 then
            width = math.max(1, fixedWidth)
        elseif style.unboundedWidth ~= true and NumberOr(style.maxWidth, 0) > 0 then
            width = math.min(width, NumberOr(style.maxWidth, width))
        end
    else
        -- 未指定 Bounds 的机密文本维持现有尺寸；首次至少保持一个有效 root。
        width = ReadSafeDimension(widget, "GetWidth", 1)
        height = ReadSafeDimension(widget, "GetHeight", 1)
    end

    widget:SetSize(width, height)
    ApplyTextAnchor(widget)
end

local TextWidgetResetSecretText
local TextWidgetApplyStyle
local TextWidgetClearDurationBinding, TextWidgetSetDurationBinding

local function TextWidgetSetText(widget, text)
    if widget._durationBindingActive then
        TextWidgetClearDurationBinding(widget)
        TextWidgetApplyStyle(widget, widget.style)
    end
    if widget._secretText == true then
        TextWidgetResetSecretText(widget)
        TextWidgetApplyStyle(widget, widget.style)
    end
    if text == nil then text = "" end
    widget.text:SetText(text)
    widget._measureText = true
    RefreshTextLayout(widget)
    return widget
end

local function TextWidgetSetSecretText(widget, text)
    -- Secret Text 不作 nil/类型/内容判断，也不走 GetStringWidth / GetStringHeight。
    if widget._durationBindingActive then
        TextWidgetClearDurationBinding(widget)
        TextWidgetApplyStyle(widget, widget.style)
    end
    widget.text:SetText(text)
    widget._secretText = true
    widget._measureText = false
    RefreshTextLayout(widget)
    return widget
end

-- 同一个 TextWidget 从 Secret 内容复用为普通内容前的公开清理入口。
-- SetToDefaults 会移除 FontString 的具体 Secret 状态；调用方必须紧接着 ApplyStyle
-- 恢复字体，之后才能调用普通 SetText。
TextWidgetResetSecretText = function(widget)
    if widget._durationBindingActive then TextWidgetClearDurationBinding(widget) end
    widget.text:SetToDefaults()
    widget._secretText = nil
    widget._measureText = true
    return widget
end

local function TextWidgetSetColor(widget, color)
    widget.text:SetTextColor(color.r, color.g, color.b, color.a or 1)
    return widget
end

local function TextWidgetSetShownFromBoolean(widget, shown)
    -- FontString 没有 SetShownFromBoolean。Secret Boolean 的可见性必须直传给
    -- TextWidget 自己的普通 root Frame，由原生 Alpha 通道控制。
    widget.root:SetAlphaFromBoolean(shown, 1, 0)
    return widget
end

TextWidgetApplyStyle = function(widget, style)
    widget.style = style or DEFAULT_TEXT_STYLE
    widget.root:SetAlpha(1)

    -- EXDB 是唯一的 FontString 样式翻译层，保证旧模块与新 Widget 同一套 Set API。
    EXDB:ApplyFont(widget.text, widget.style)
    -- 用户字体配置可控制字体、颜色与排版，但不能把实际显示文字降到图标/边框下面。
    -- 全局视觉层级以 EXFONTFRAME 为最终权威入口。
    EXUI:ApplyVisualLayer(widget.text, _G.EXFONTFRAME, widget)

    local wordWrap = GetStyleValue(widget.style, "wordWrap") == true
    if widget.text.SetWordWrap then widget.text:SetWordWrap(wordWrap) end
    if widget.text.SetNonSpaceWrap then
        widget.text:SetNonSpaceWrap(GetStyleValue(widget.style, "nonSpaceWrap") == true)
    end
    if widget.text.SetMaxLines then
        widget.text:SetMaxLines(NumberOr(widget.style.maxLines, wordWrap and 0 or 1))
    end

    if GetStyleValue(widget.style, "enabled") == false then
        widget:Hide()
    else
        widget:Show()
    end

    RefreshTextLayout(widget)
    return widget
end

local function TextWidgetSetAnchor(widget, point, relativeTo, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point or "CENTER", relativeTo or widget:GetParent() or UIParent, relativePoint or point or "CENTER", x or 0, y or 0)
    return widget
end

local function TextWidgetSetBounds(widget, width, height)
    widget._boundsWidth = math.max(1, NumberOr(width, 1))
    widget._boundsHeight = math.max(1, NumberOr(height, 1))
    RefreshTextLayout(widget)
    return widget
end

local function TextWidgetClearBounds(widget)
    widget._boundsWidth = nil
    widget._boundsHeight = nil
    RefreshTextLayout(widget)
    return widget
end

local function TextWidgetGetRoot(widget)
    return widget
end

-- A content region can be used as a native anchor without inspecting its
-- string.  This is safe for ordinary, Duration-bound and Secret FontStrings.
local function TextWidgetGetContentRegion(widget)
    return widget.text
end

-- 文字 Widget 自己拥有 FontString；调用方不能通过私有 .text 反向操作它。
-- 标准预览的独立命中框只需要读取最终字形的普通几何，故由公开 API 提供。
local function TextWidgetGetVisualMetrics(widget)
    if widget._secretText == true or widget._durationBindingActive then return nil end
    local text = widget.text
    local width = ReadSafeDimension(text, "GetStringWidth")
    local height = ReadSafeDimension(text, "GetStringHeight")
    if not width or not height then return nil end
    return {
        width = width,
        height = height,
        justifyH = text:GetJustifyH() or "LEFT",
        justifyV = text:GetJustifyV() or "MIDDLE",
        offsetX = widget._stylePositionOverride and widget._stylePositionOverride.x or NumberOr(GetStyleValue(widget.style, "x"), 0),
        offsetY = widget._stylePositionOverride and widget._stylePositionOverride.y or NumberOr(GetStyleValue(widget.style, "y"), 0),
    }
end

-- Collections may own a semantic outer anchor while the style remains the
-- sole DB object.  This transient visual override prevents the style x/y from
-- being applied twice; it never copies or mutates the style table.
local function TextWidgetSetStylePositionOverride(widget, x, y)
    if x == nil and y == nil then
        widget._stylePositionOverride = nil
    else
        widget._stylePositionOverride = { x = NumberOr(x, 0), y = NumberOr(y, 0) }
    end
    RefreshTextLayout(widget)
    return widget
end

-- 名称既可能是普通字符串，也可能是暴雪 Timeline 原样透传的 Secret string。
-- Secret 值禁止与 "" 比较；唯一合法分流是官方 issecretvalue，然后交给
-- TextWidget 的原生 Secret 路径。未知 Secret 的空/非空状态也不能由 Lua 判断，
-- 故按样式显示，让客户端决定最终文本。
local function TextWidgetSetDisplayText(widget, text)
    if type(issecretvalue) == "function" and issecretvalue(text) then
        widget:SetSecretText(text)
        return true
    end
    if text == nil then text = "" end
    widget:SetText(text)
    return text ~= ""
end

local function TextWidgetHasSecretText(widget)
    return widget._secretText == true
end

local function TextWidgetRelease(widget)
    if widget._released then return end
    widget._released = true
    TextWidgetClearDurationBinding(widget)
    widget.text:SetToDefaults()
    widget:Hide()
    widget:ClearAllPoints()
    widget.style = nil
    widget.role = nil
    widget._boundsWidth = nil
    widget._boundsHeight = nil
    widget._measureText = true
    widget._secretText = nil
    EXFactory:Release(TEXT_WIDGET_POOL, widget)
end

EXFactory:InitPool(TEXT_WIDGET_POOL, "Frame", nil, function(widget)
    widget._isEXUITextWidget = true
    widget.root = widget
    widget:SetSize(1, 1)
    widget:EnableMouse(false)

    local text = EXUI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    if text.SetMaxLines then text:SetMaxLines(1) end
    widget.text = text

    widget.SetText = TextWidgetSetText
    widget.SetSecretText = TextWidgetSetSecretText
    widget.SetDurationBinding = function(self, durationObject, options)
        return TextWidgetSetDurationBinding(self, durationObject, options)
    end
    widget.ClearDurationBinding = function(self) return TextWidgetClearDurationBinding(self) end
    widget.ResetSecretText = TextWidgetResetSecretText
    widget.SetColor = TextWidgetSetColor
    widget.SetShownFromBoolean = TextWidgetSetShownFromBoolean
    widget.ApplyStyle = TextWidgetApplyStyle
    widget.SetAnchor = TextWidgetSetAnchor
    widget.SetStylePositionOverride = TextWidgetSetStylePositionOverride
    widget.SetBounds = TextWidgetSetBounds
    widget.ClearBounds = TextWidgetClearBounds
    widget.GetRoot = TextWidgetGetRoot
    widget.GetContentRegion = TextWidgetGetContentRegion
    widget.GetVisualMetrics = TextWidgetGetVisualMetrics
    widget.HasSecretText = TextWidgetHasSecretText
    widget.Release = TextWidgetRelease
end)

-- 所有实际文字（单文本、图标角标、计时条名称/时间）统一从这里取得。
-- parent 必须是模块提供的 anchorFrame 或上层 Widget root；TextWidget 自己不注册编辑模式锚点。
function EXUI:CreateTextWidget(parent, role)
    local widget = EXFactory:Acquire(TEXT_WIDGET_POOL, parent)
    widget._released = false
    widget.role = role or "text"
    widget.style = nil
    widget._boundsWidth = nil
    widget._boundsHeight = nil
    widget._stylePositionOverride = nil
    widget._measureText = true
    TextWidgetClearDurationBinding(widget)
    widget.text:ClearAllPoints()
    widget:ApplyStyle(DEFAULT_TEXT_STYLE)
    widget.text:SetText("")
    return widget
end

-- 原生 DurationTextBinding 是 TextWidget 的正式时间文字路径。Duration（普通或
-- Secret）只会原样交给 binding；这里绝不读取、换算或格式化它的数值。
TextWidgetClearDurationBinding = function(widget)
    local binding = widget.durationTextBinding
    if binding then
        binding:SetEnabled(false)
        binding:SetToDefaults()
    end
    widget._durationBindingActive = nil
    widget._measureText = true
    return widget
end

TextWidgetSetDurationBinding = function(widget, durationObject, options)
    if not durationObject then return TextWidgetClearDurationBinding(widget) end
    if not C_DurationUtil or not C_StringUtil or not Enum
        or not Enum.DurationTextBindingProperty or not Enum.NumericRuleFormatRounding then
        error("EXUI TextWidget native DurationTextBinding API is unavailable", 2)
    end
    if widget._secretText == true then
        widget.text:SetToDefaults()
        widget._secretText = nil
        TextWidgetApplyStyle(widget, widget.style)
    end
    if not widget.durationTextBinding then
        widget.durationTextBinding = C_DurationUtil.CreateDurationTextBinding()
        -- SecondsFormatter is intentionally not used here: it renders unit suffixes
        -- (for example "1m 33s"). Duration text in EXUI is always a pure number.
        widget.durationTextFormatter = C_StringUtil.CreateNumericRuleFormatter()
        widget.durationTextFormatter:SetBreakpoints({
            {
                threshold = 0,
                format = "%.1f",
            },
            {
                threshold = 10,
                step = 1,
                rounding = Enum.NumericRuleFormatRounding.Down,
                format = "%.0f",
            },
        })
    end
    local binding = widget.durationTextBinding
    binding:SetEnabled(false)
    binding:SetFontString(widget.text)
    local components = options and options.components
    if type(components) ~= "table" then
        components = {
            { property = (options and options.property) or Enum.DurationTextBindingProperty.RemainingDuration,
                formatter = (options and options.formatter) or widget.durationTextFormatter },
        }
    end
    binding:SetTextFormat((options and options.formatString) or "{}", components)
    -- DurationTextBinding otherwise clears the FontString when the duration expires.
    -- Keeping a native "0" is required for static countdown/icon labels after expiry.
    binding:SetExpiredText((options and options.expiredText) or "0")
    binding:SetZeroDurationText((options and options.zeroDurationText) or "0")
    binding:SetUpdateInterval((options and options.updateInterval) or 0)
    binding:SetDuration(durationObject)
    widget._durationBindingActive = true
    widget._measureText = false
    binding:SetEnabled(true)
    binding:UpdateFontString()
    return widget
end

-- =========================================================
-- ExtraTextureWidget：额外子元素的单一材质控件
-- =========================================================
-- 只管理一个确定尺寸的 Root + Texture。它不理解任何业务 flag、排序或配置；
-- 模块决定显示什么，Host 决定位置，控件保证可见材质绝不画到自身 bounds 外。
local EXTRA_TEXTURE_WIDGET_POOL = "RuntimeExtraTextureWidget"

local function ExtraTextureWidgetSetAtlas(widget, atlas)
    widget.texture:SetTexture(nil)
    widget.texture:SetTexCoord(0, 1, 0, 1)
    if atlas and atlas ~= "" then
        widget.texture:SetAtlas(atlas, false)
        widget:Show()
    else
        widget.texture:SetAtlas(nil)
        widget:Hide()
    end
    return widget
end

local function ExtraTextureWidgetSetTexture(widget, file, left, right, top, bottom)
    widget.texture:SetAtlas(nil)
    widget.texture:SetTexture(file)
    widget.texture:SetTexCoord(left or 0, right or 1, top or 0, bottom or 1)
    if file then widget:Show() else widget:Hide() end
    return widget
end

-- 额外材质的颜色属于材质本身的声明式外观，而非模块取得内部 Texture 后的
-- 临时修改。用于例如施法被打断时的半透明红色遮罩。
local function ExtraTextureWidgetSetColor(widget, r, g, b, a)
    widget.texture:SetVertexColor(r or 1, g or 1, b or 1, a == nil and 1 or a)
    return widget
end

-- 单材质的完整视觉合同只能通过 Widget API 应用。Collection / 模块不得拿到
-- 内部 Texture 后各自 SetTexture、SetBlendMode 或 SetRotation；否则 panel、
-- world 与 runtime 很容易变成三份不同的实现。
local function ExtraTextureWidgetApplyPresentation(widget, presentation)
    presentation = type(presentation) == "table" and presentation or {}
    local style = type(presentation.style) == "table" and presentation.style or presentation
    -- RegionElements may declare a live pure bounds rectangle while retaining
    -- `style` as the one persistent DB table.  This is visual geometry for
    -- this presentation only, not a copied or second configuration table.
    local width = math.max(1, tonumber(presentation.width) or tonumber(style.width) or 1)
    local height = math.max(1, tonumber(presentation.height) or tonumber(style.height) or 1)
    widget:SetSize(width, height)

    local source = presentation.texture
    if source == nil then source = presentation.fileID or presentation.file or presentation.path end
    local atlas = type(source) == "table" and source.atlas or presentation.atlas
    local file = type(source) == "table" and (source.fileID or source.file or source.path or source.value) or source
    if atlas and atlas ~= "" then
        widget:SetAtlas(atlas)
    else
        widget:SetTexture(file)
    end

    local left, right, top, bottom = 0, 1, 0, 1
    local coord = type(source) == "table" and source.texCoord or presentation.texCoord
    if type(coord) == "table" then
        left, right = tonumber(coord[1]) or 0, tonumber(coord[2]) or 1
        top, bottom = tonumber(coord[3]) or 0, tonumber(coord[4]) or 1
    end
    if presentation.flipH == true then left, right = right, left end
    if presentation.flipV == true then top, bottom = bottom, top end
    widget.texture:SetTexCoord(left, right, top, bottom)
    widget.texture:SetBlendMode(presentation.blendMode or "BLEND")
    widget.texture:SetRotation(math.rad(tonumber(presentation.rotation) or 0))

    local color = type(presentation.color) == "table" and presentation.color or presentation
    widget:SetColor(color.r or color[1] or presentation.colorR or 1,
        color.g or color[2] or presentation.colorG or 1,
        color.b or color[3] or presentation.colorB or 1,
        color.a or color[4] or presentation.colorA or presentation.alpha or 1)
    widget:SetVisible(presentation.shown ~= false and (atlas ~= nil and atlas ~= "" or file ~= nil and file ~= ""))
    return widget
end

local function ExtraTextureWidgetClear(widget)
    widget.texture:SetAtlas(nil)
    widget.texture:SetTexture(nil)
    widget.texture:SetTexCoord(0, 1, 0, 1)
    widget.texture:SetVertexColor(1, 1, 1, 1)
    widget.texture:SetBlendMode("BLEND")
    widget.texture:SetRotation(0)
    widget:Hide()
    return widget
end

local function ExtraTextureWidgetSetVisible(widget, shown)
    if shown == true then widget:Show() else widget:Hide() end
    return widget
end

-- ExtraTextureWidget 的 root 是公开 Widget 本体；需要放置额外材质的容器只能
-- 通过此入口设定锚点，不能绕过控件直接取得其私有 texture。
local function ExtraTextureWidgetSetAnchor(widget, point, relativeTo, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point or "CENTER", relativeTo or widget:GetParent() or UIParent,
        relativePoint or point or "CENTER", x or 0, y or 0)
    return widget
end

-- 模块不能取得内部 Texture；这两项是 Secret 团队标记与布尔可见性的窄原生通道。
local function ExtraTextureWidgetSetRaidTargetIndex(widget, index)
    widget.texture:SetAtlas(nil)
    widget.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    widget.texture:SetTexCoord(0, 1, 0, 1)
    -- `index` may be an opaque Secret Number.  Existence was established by
    -- the caller's ordinary declaration flag, so Lua must not compare it.
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(widget.texture, index)
        widget:Show()
    else
        widget:Hide()
    end
    return widget
end

local function ExtraTextureWidgetSetShownFromBoolean(widget, shown)
    if widget.texture.SetAlphaFromBoolean then
        widget.texture:SetAlphaFromBoolean(shown, 1, 0)
        widget:Show()
    else
        widget:Hide()
    end
    return widget
end

local function ExtraTextureWidgetResetShownFromBoolean(widget)
    -- A prior Secret false can leave an alpha binding at zero.  A later normal
    -- presentation must explicitly restore ordinary alpha before SetVisible.
    widget.texture:SetAlpha(1)
    return widget
end

local function ExtraTextureWidgetGetRoot(widget)
    return widget
end

local function ExtraTextureWidgetGetBounds(widget)
    local left, right, bottom, top = widget:GetLeft(), widget:GetRight(), widget:GetBottom(), widget:GetTop()
    if not left or not right or not bottom or not top then return nil end
    return { left = left, right = right, bottom = bottom, top = top }
end

local function ExtraTextureWidgetRelease(widget)
    if not widget or widget._released then return end
    widget._released = true
    ExtraTextureWidgetClear(widget)
    widget:ClearAllPoints()
    widget:SetSize(1, 1)
    EXFactory:Release(EXTRA_TEXTURE_WIDGET_POOL, widget)
end

EXFactory:InitPool(EXTRA_TEXTURE_WIDGET_POOL, "Frame", nil, function(widget)
    widget.root = widget
    widget:SetSize(1, 1)
    widget:EnableMouse(false)
    widget.texture = EXUI:CreateVisualTexture(widget, _G.EXBORDERFRAME)
    widget.texture:SetAllPoints(widget)
    widget.SetAtlas = ExtraTextureWidgetSetAtlas
    widget.SetTexture = ExtraTextureWidgetSetTexture
    widget.SetColor = ExtraTextureWidgetSetColor
    widget.ApplyPresentation = ExtraTextureWidgetApplyPresentation
    widget.Clear = ExtraTextureWidgetClear
    widget.SetVisible = ExtraTextureWidgetSetVisible
    widget.SetAnchor = ExtraTextureWidgetSetAnchor
    widget.SetRaidTargetIndex = ExtraTextureWidgetSetRaidTargetIndex
    widget.SetShownFromBoolean = ExtraTextureWidgetSetShownFromBoolean
    widget.ResetShownFromBoolean = ExtraTextureWidgetResetShownFromBoolean
    widget.GetRoot = ExtraTextureWidgetGetRoot
    widget.GetBounds = ExtraTextureWidgetGetBounds
    widget.Release = ExtraTextureWidgetRelease
end)

function EXUI:CreateExtraTextureWidget(parent)
    local widget = EXFactory:Acquire(EXTRA_TEXTURE_WIDGET_POOL, parent)
    widget._released = false
    widget:ClearAllPoints()
    widget:SetSize(1, 1)
    widget:Clear()
    return widget
end

-- =========================================================
-- SecretCountdownWidget：秘密值倒数数字专用（原生 Cooldown 数字通道的规范化封装）
-- =========================================================
-- Secret Duration 场景下，只有暴雪原生 Cooldown 组件自带的倒数数字渲染是安全的——而且它跟
-- 进度条填充、扇形动画一样是引擎原生驱动，数字会自动跳动，不需要 Lua OnUpdate 轮询。
-- 这个 Widget 把"建一个只留数字、关掉扇形/边缘/光效的 Cooldown"这个手法封装成正式的 EXUI
-- 控件：TimerBarWidget 和 IconWidget 都通过它显示秘密值来源的倒数数字，不再各自私有实现，
-- 也不需要用 string.format + OnUpdate 手动刷新那条更脆的路。
--
-- 2026-07-26 已实测并回滚：曾短暂改用 C_DurationUtil.CreateDurationTextBinding() 直接绑定普通
-- FontString，本地静态检查通过，但 MythicCast 实机测试在 UNIT_SPELLCAST_STOP（Clear/Release 路径）
-- 稳定复现 `FontString:SetText(): Font not set`（Lua Taint: ExwindCore）：DurationTextBinding 的
-- 原生自动刷新未能被 Release 时序完全同步掐断，在 FontString 被 SetToDefaults() 清空字体之后仍
-- 写了一次。这条原生 API 在这次尝试里不可靠，已改回本方案；如果以后要重新尝试，必须先搞清楚
-- DurationTextBinding:SetToDefaults() 之后是否还可能有一次排队中的原生更新，不能只按文档字面
-- 意思假设它同步生效。

local SECRET_COUNTDOWN_WIDGET_POOL = "RuntimeSecretCountdownWidget"

local DEFAULT_SECRET_COUNTDOWN_STYLE = {
    enabled = true,
    size = 14,
    r = 1, g = 1, b = 1, a = 1,
    outline = "OUTLINE",
    justifyH = "CENTER",
    x = 0, y = 0,
}

-- Secret Duration 的倒数必须由 Cooldown 原生格式化器处理，不能把剩余时间拿回 Lua
-- 做比较或字符串拼接。规则：< 10 秒显示一位小数；10~59 秒显示整数；>= 60 秒显示分钟；
-- >= 24 小时显示天数。整个规则表只在非 Secret 初始化阶段创建一次。
local secretCountdownFormatter
local function GetSecretCountdownFormatter()
    if secretCountdownFormatter then
        return secretCountdownFormatter
    end

    secretCountdownFormatter = C_StringUtil.CreateNumericRuleFormatter()
    secretCountdownFormatter:SetBreakpoints({
        { threshold = 0, format = "%.1f" },
        { threshold = 10, step = 1, rounding = Enum.NumericRuleFormatRounding.Nearest, format = "%d" },
        {
            threshold = 60,
            format = "%dm",
            components = {
                { div = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
            },
        },
        {
            threshold = 3600,
            format = "%dh",
            components = {
                { div = 3600, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
            },
        },
        {
            threshold = 86400,
            format = "%dd",
            components = {
                { div = 86400, step = 1, rounding = Enum.NumericRuleFormatRounding.Nearest },
            },
        },
    })
    return secretCountdownFormatter
end

-- 同上，但全程不出现小数（10 秒内也是整数）。调用方通过 style.showDecimals = false 选用，
-- 默认（不传该字段）仍走上面那个带一位小数的格式化器，不影响现有调用方。
local secretCountdownFormatterNoDecimals
local function GetSecretCountdownFormatterNoDecimals()
    if secretCountdownFormatterNoDecimals then
        return secretCountdownFormatterNoDecimals
    end

    secretCountdownFormatterNoDecimals = C_StringUtil.CreateNumericRuleFormatter()
    secretCountdownFormatterNoDecimals:SetBreakpoints({
        -- 向上取整：剩 3.2 秒显示"4"，跟暴雪原生动作条冷却数字的习惯一致，数字只在冷却真正结束时才归零
        { threshold = 0, step = 1, rounding = Enum.NumericRuleFormatRounding.Up, format = "%d" },
        {
            threshold = 60,
            format = "%dm",
            components = {
                { div = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
            },
        },
        {
            threshold = 3600,
            format = "%dh",
            components = {
                { div = 3600, step = 1, rounding = Enum.NumericRuleFormatRounding.Down },
            },
        },
        {
            threshold = 86400,
            format = "%dd",
            components = {
                { div = 86400, step = 1, rounding = Enum.NumericRuleFormatRounding.Nearest },
            },
        },
    })
    return secretCountdownFormatterNoDecimals
end

local function SecretCountdownWidgetClear(widget)
    -- 此 Cooldown 可能仍绑定 Secret Duration Object。Clear/Release 阶段不再调用
    -- 它的任何原生方法（包括 SetHideCountdownNumbers），避免引擎尝试读取旧 Duration。
    -- 只隐藏外层 Frame；下次 SetSecretDuration 会完整覆盖原生绑定与数字可见性。
    widget:Hide()
    return widget
end

-- durationObject 为 nil 时等同于 Clear()；reverse 对应 SetCooldownFromDurationObject 的第二参数
-- （官方名字其实是 clearIfZero，见 EXUI_组合控件规范.md 0.1；这里维持既有调用方的参数值语义
-- 不变，只是记录真实含义，暂不改名以免和刚回滚的改动混在一起，需要时再单独处理命名）。
local function SecretCountdownWidgetSetSecretDuration(widget, durationObject, reverse)
    if not durationObject then
        return SecretCountdownWidgetClear(widget)
    end
    if GetStyleValue(widget.style, "enabled") == false then
        return SecretCountdownWidgetClear(widget)
    end
    widget:Show()
    widget.cooldown:SetHideCountdownNumbers(false)
    if widget.cooldown.SetCooldownFromDurationObject then
        widget.cooldown:SetCooldownFromDurationObject(durationObject, reverse == true)
    end
    widget.cooldown:Show()
    return widget
end

local function SecretCountdownWidgetApplyStyle(widget, style)
    widget.style = style or DEFAULT_SECRET_COUNTDOWN_STYLE
    if widget.cooldown.SetCountdownFormatter then
        widget.cooldown:SetCountdownFormatter(
            widget.style.showDecimals == false and GetSecretCountdownFormatterNoDecimals() or GetSecretCountdownFormatter()
        )
    end
    local countdown = widget.cooldown.GetCountdownFontString and widget.cooldown:GetCountdownFontString()
    if countdown then
        EXDB:ApplyFont(countdown, widget.style)
        EXUI:ApplyVisualLayer(countdown, _G.EXFONTFRAME, widget)
        local anchor = tostring(GetStyleValue(widget.style, "justifyH") or "CENTER"):upper()
        if anchor ~= "LEFT" and anchor ~= "RIGHT" then anchor = "CENTER" end
        countdown:ClearAllPoints()
        countdown:SetPoint(anchor, widget, anchor,
            NumberOr(widget.style.x, 0), NumberOr(widget.style.y, 0))
    end
    if GetStyleValue(widget.style, "enabled") == false then
        widget.cooldown:SetHideCountdownNumbers(true)
    end
    return widget
end

local function SecretCountdownWidgetSetAnchor(widget, point, relativeTo, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point or "CENTER", relativeTo or widget:GetParent() or UIParent, relativePoint or point or "CENTER", x or 0, y or 0)
    return widget
end

local function SecretCountdownWidgetRelease(widget)
    if widget._released then return end
    widget._released = true
    -- Cooldown 是实际承载 Secret Duration 的 Region；交回池前由原生 API 清除其
    -- Secret 状态，不能以 Lua 数值方式重置旧 Duration。
    widget.cooldown:SetToDefaults()
    widget.style = nil
    widget:Hide()
    widget:ClearAllPoints()
    EXFactory:Release(SECRET_COUNTDOWN_WIDGET_POOL, widget)
end

EXFactory:InitPool(SECRET_COUNTDOWN_WIDGET_POOL, "Frame", nil, function(widget)
    widget.root = widget
    widget:SetSize(1, 1)
    widget:EnableMouse(false)

    local cooldown = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
    cooldown:SetAllPoints(widget)
    cooldown:EnableMouse(false)
    cooldown:SetDrawSwipe(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown.noCooldownCount = true
    cooldown.noOCC = true
    cooldown:Hide()
    widget.cooldown = cooldown

    widget.SetSecretDuration = SecretCountdownWidgetSetSecretDuration
    widget.Clear = SecretCountdownWidgetClear
    widget.ApplyStyle = SecretCountdownWidgetApplyStyle
    widget.SetAnchor = SecretCountdownWidgetSetAnchor
    widget.Release = SecretCountdownWidgetRelease
end)

-- 秘密值来源的倒数数字唯一入口。TimerBarWidget/IconWidget 内部通过它显示数字；
-- 业务模块一般不需要直接创建它（除非有脱离这两个 Widget 之外的秘密值倒数场景）。
function EXUI:CreateSecretCountdownWidget(parent, style)
    local widget = EXFactory:Acquire(SECRET_COUNTDOWN_WIDGET_POOL, parent)
    widget._released = false
    -- SetToDefaults 会清掉 Cooldown 的脚本可见配置；每次借用都恢复这组固定基线。
    widget.cooldown:SetAllPoints(widget)
    widget.cooldown:EnableMouse(false)
    widget.cooldown:SetDrawSwipe(false)
    widget.cooldown:SetDrawEdge(false)
    widget.cooldown:SetDrawBling(false)
    widget.cooldown:SetCountdownMillisecondsThreshold(10)
    widget.cooldown:SetCountdownFormatter(GetSecretCountdownFormatter())
    widget.cooldown:SetHideCountdownNumbers(true)
    widget.cooldown.noCooldownCount = true
    widget.cooldown.noOCC = true
    widget.cooldown:Hide()
    widget:ApplyStyle(style or DEFAULT_SECRET_COUNTDOWN_STYLE)
    return widget
end

-- =========================================================
-- IconWidget：完整图标运行时控件（Texture + Cooldown + TextWidget + Border）
-- =========================================================

local ICON_WIDGET_POOL = "RuntimeIconWidget"
local CROP_DEFAULT_LEFT, CROP_DEFAULT_RIGHT = 0.08, 0.92
local CROP_DEFAULT_TOP, CROP_DEFAULT_BOTTOM = 0.08, 0.92
-- CooldownFrameTemplate 的默认 SwipeTexture 是内建的纯白扇形；显式复位时用
-- 同义的白色文件，避免池化过的 static preview 自定义扇形泄漏到正式 IconWidget。
local DEFAULT_COOLDOWN_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local DEFAULT_ICON_STYLE = {
    width = 64, height = 64,
    showIcon = true,
    alpha = 1,
    colorR = 1, colorG = 1, colorB = 1, colorA = 1,
    desaturated = false,
    blendMode = "BLEND",
    rotation = 0,
    enableCrop = true,
    cropLeft = CROP_DEFAULT_LEFT, cropRight = CROP_DEFAULT_RIGHT,
    cropTop = CROP_DEFAULT_TOP, cropBottom = CROP_DEFAULT_BOTTOM,
    showBorder = true,
    borderTexture = "None",
    borderSize = 1,
    borderPadding = 0,
    borderColorR = 1, borderColorG = 1, borderColorB = 1, borderColorA = 1,
    showCooldown = true,
    reverse = false,
    cooldown = {
        showSwipe = true,
        swipeAlpha = 0.65,
        showEdge = true,
        edgeAlpha = 1,
        showBling = false,
    },
}

local function IconStyleValue(iconStyle, key)
    local value = iconStyle and iconStyle[key]
    if value == nil then value = DEFAULT_ICON_STYLE[key] end
    return value
end

local function ResolveIconStyle(style)
    if type(style) == "table" and type(style.icon) == "table" then
        return style.icon
    end
    return type(style) == "table" and style or DEFAULT_ICON_STYLE
end

local function ResolveIconTextStyles(style)
    if type(style) == "table" and type(style.text) == "table" then
        return style.text
    end
    return {}
end

local function ResolveBorderTexture(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(name) == "string" and name ~= "" and name ~= "None" then
        local path = LSM:Fetch("border", name, true)
        if path then return path end
    end
    return "Interface\\Buttons\\UI-EmptySlot-White"
end

-- swipeTexture 只属于静态 preview 样本。正常 runtime 的 IconWidget 样式没有此入口；
-- 此处仅在一个曾套用过静态样本的 pooled Cooldown 上恢复模板等价的纯白扇形。
local function ResetStaticCooldownSwipeTexture(widget)
    if not widget._staticCooldownSwipeTextureApplied then return end
    if widget.cooldown and widget.cooldown.SetSwipeTexture then
        widget.cooldown:SetSwipeTexture(DEFAULT_COOLDOWN_SWIPE_TEXTURE)
    end
    widget._staticCooldownSwipeTextureApplied = nil
end

-- 同一条静态 preview 覆盖可以给自定义环纹理着色。它绝不成为普通 Icon 样式字段；
-- 复位值严格沿用 ApplyIconCooldownStyle 的既有黑色 + swipeAlpha 语义。
local function ResetStaticCooldownSwipeColor(widget)
    if not widget._staticCooldownSwipeColorApplied then return end
    if widget.cooldown and widget.cooldown.SetSwipeColor then
        local cooldownStyle = type(widget.iconStyle and widget.iconStyle.cooldown) == "table"
            and widget.iconStyle.cooldown or {}
        widget.cooldown:SetSwipeColor(0, 0, 0, NumberOr(cooldownStyle.swipeAlpha, 0.65))
    end
    widget._staticCooldownSwipeColorApplied = nil
end

local function ApplyStaticCooldownSwipeTexture(widget)
    ResetStaticCooldownSwipeTexture(widget)
    ResetStaticCooldownSwipeColor(widget)

    local cooldownStyle = type(widget.iconStyle and widget.iconStyle.cooldown) == "table"
        and widget.iconStyle.cooldown or nil
    local swipeTexture = cooldownStyle and cooldownStyle.swipeTexture
    if swipeTexture ~= nil then
        if type(swipeTexture) ~= "string" or swipeTexture == "" then
            error("EXUI IconWidget static cooldown.swipeTexture must be a non-empty texture path", 2)
        end
        if not widget.cooldown or not widget.cooldown.SetSwipeTexture then
            error("EXUI IconWidget: Cooldown:SetSwipeTexture is required for static preview", 2)
        end
        widget.cooldown:SetSwipeTexture(swipeTexture)
        widget._staticCooldownSwipeTextureApplied = true
    end

    local swipeColor = cooldownStyle and cooldownStyle.swipeColor
    if swipeColor == nil then return end
    if type(swipeColor) ~= "table" then
        error("EXUI IconWidget static cooldown.swipeColor must be { r, g, b, a }", 2)
    end
    local r, g, b, a = swipeColor.r, swipeColor.g, swipeColor.b, swipeColor.a
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" or type(a) ~= "number"
        or r ~= r or g ~= g or b ~= b or a ~= a
        or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 or a < 0 or a > 1 then
        error("EXUI IconWidget static cooldown.swipeColor values must be numbers in [0, 1]", 2)
    end
    if not widget.cooldown.SetSwipeColor then
        error("EXUI IconWidget: Cooldown:SetSwipeColor is required for static preview", 2)
    end
    widget.cooldown:SetSwipeColor(r, g, b, a)
    widget._staticCooldownSwipeColorApplied = true
end

local function ClearNativeCooldown(widget)
    ResetStaticCooldownSwipeTexture(widget)
    ResetStaticCooldownSwipeColor(widget)
    widget._cooldownActive = false
    widget._cooldownStart = nil
    widget._cooldownDuration = nil
    widget._cooldownModRate = nil
    widget._cooldownMode = nil
    widget._countdownValue = nil
    widget:SetScript("OnUpdate", nil)
    if _G.CooldownFrame_Clear then
        _G.CooldownFrame_Clear(widget.cooldown)
    elseif widget.cooldown.SetCooldown then
        widget.cooldown:SetCooldown(0, 0)
    end
    -- 标准预览可把原生扇形暂停在普通快照进度；运行时复用前必须恢复原生
    -- Cooldown 的正常时钟，不能把暂停状态泄漏给正式 IconWidget。
    if widget.cooldown.SetPaused then widget.cooldown:SetPaused(false) end
    widget.cooldown:Hide()
end

local function IsCountdownEnabled(widget)
    if widget._countdownTextVisibleOverride ~= nil then
        return widget._countdownTextVisibleOverride == true
    end
    local style = widget.textStyles and widget.textStyles.countdown
    return type(style) ~= "table" or style.enabled ~= false
end

local function IsCooldownVisualEnabled(widget)
    if widget._cooldownVisualVisibleOverride ~= nil then
        return widget._cooldownVisualVisibleOverride == true
    end
    return IconStyleValue(widget.iconStyle, "showCooldown") ~= false
end

local function ApplyIconCooldownStyle(widget)
    local cooldown = widget.cooldown
    local cooldownStyle = type(widget.iconStyle.cooldown) == "table" and widget.iconStyle.cooldown or {}
    local showSwipe = cooldownStyle.showSwipe ~= false
    local showEdge = cooldownStyle.showEdge ~= false
    local showBling = cooldownStyle.showBling == true

    if cooldown.SetReverse then cooldown:SetReverse(IconStyleValue(widget.iconStyle, "reverse") == true) end
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(showSwipe) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(showEdge) end
    if cooldown.SetDrawBling then cooldown:SetDrawBling(showBling) end
    if cooldown.SetSwipeColor then
        cooldown:SetSwipeColor(0, 0, 0, NumberOr(cooldownStyle.swipeAlpha, 0.65))
    end
    if cooldown.SetEdgeColor then
        cooldown:SetEdgeColor(1, 1, 1, NumberOr(cooldownStyle.edgeAlpha, 1))
    end

    widget._showNativeCooldown = IsCooldownVisualEnabled(widget) and (showSwipe or showEdge or showBling)
end

local function ApplySecretSafeIconBorder(widget)
    local border = widget.secretSafeBorder
    if not border then return end
    if IconStyleValue(widget.iconStyle, "showBorder") == false then
        border:Hide()
        return
    end
    widget.border:Hide()
    border:Show()
end

local function ApplyIconBorder(widget)
    local iconStyle = widget.iconStyle
    if widget._useSecretSafeBorder then
        ApplySecretSafeIconBorder(widget)
        return
    end
    if widget.secretSafeBorder then widget.secretSafeBorder:Hide() end
    if IconStyleValue(iconStyle, "showBorder") == false then
        widget.border:Hide()
        return
    end

    local padding = NumberOr(IconStyleValue(iconStyle, "borderPadding"), 0)
    widget.border:ClearAllPoints()
    widget.border:SetPoint("TOPLEFT", widget, "TOPLEFT", -padding, padding)
    widget.border:SetSize((widget:GetWidth() or 0) + padding * 2, (widget:GetHeight() or 0) + padding * 2)
    widget.border:SetBackdrop({
        edgeFile = ResolveBorderTexture(IconStyleValue(iconStyle, "borderTexture")),
        edgeSize = math.max(1, NumberOr(IconStyleValue(iconStyle, "borderSize"), 1)),
    })
    widget.border:SetBackdropBorderColor(
        NumberOr(IconStyleValue(iconStyle, "borderColorR"), 1),
        NumberOr(IconStyleValue(iconStyle, "borderColorG"), 1),
        NumberOr(IconStyleValue(iconStyle, "borderColorB"), 1),
        NumberOr(IconStyleValue(iconStyle, "borderColorA"), 1)
    )
    widget.border:Show()
end

local function ApplyIconTextureStyle(widget)
    local iconStyle = widget.iconStyle
    widget.icon:SetAlpha(NumberOr(IconStyleValue(iconStyle, "alpha"), 1))
    if widget._unusableOverride then
        -- 不可用时直接盖成固定暗色，不跟配置的染色混合；跟 SetDesaturated 一样是轻量覆盖，
        -- 不走完整 ApplyStyle，避免高频事件（SPELL_UPDATE_USABLE）触发整份重建。
        widget.icon:SetVertexColor(0.4, 0.4, 0.4, NumberOr(IconStyleValue(iconStyle, "colorA"), 1))
    else
        widget.icon:SetVertexColor(
            NumberOr(IconStyleValue(iconStyle, "colorR"), 1),
            NumberOr(IconStyleValue(iconStyle, "colorG"), 1),
            NumberOr(IconStyleValue(iconStyle, "colorB"), 1),
            NumberOr(IconStyleValue(iconStyle, "colorA"), 1)
        )
    end
    widget.icon:SetBlendMode(tostring(IconStyleValue(iconStyle, "blendMode") or "BLEND"))
    widget.icon:SetRotation(math.rad(NumberOr(IconStyleValue(iconStyle, "rotation"), 0)))
    local desaturated = widget._desaturatedOverride
    if desaturated == nil then
        desaturated = IconStyleValue(iconStyle, "desaturated") == true
    end
    widget.icon:SetDesaturated(desaturated)
    if IconStyleValue(iconStyle, "enableCrop") == false then
        widget.icon:SetTexCoord(0, 1, 0, 1)
    else
        local left = NumberOr(IconStyleValue(iconStyle, "cropLeft"), CROP_DEFAULT_LEFT)
        local right = NumberOr(IconStyleValue(iconStyle, "cropRight"), CROP_DEFAULT_RIGHT)
        local top = NumberOr(IconStyleValue(iconStyle, "cropTop"), CROP_DEFAULT_TOP)
        local bottom = NumberOr(IconStyleValue(iconStyle, "cropBottom"), CROP_DEFAULT_BOTTOM)
        if right <= left then left, right = CROP_DEFAULT_LEFT, CROP_DEFAULT_RIGHT end
        if bottom <= top then top, bottom = CROP_DEFAULT_TOP, CROP_DEFAULT_BOTTOM end
        widget.icon:SetTexCoord(left, right, top, bottom)
    end
    widget.icon:SetShown(IconStyleValue(iconStyle, "showIcon") ~= false)
end

local function LayoutIconTextSlots(widget)
    local width, height = widget:GetWidth(), widget:GetHeight()
    local styles = widget.textStyles or {}

    widget.countdownText:ApplyStyle(styles.countdown)
    widget.countdownText:SetBounds(width, height)
    widget.countdownText:SetAnchor("CENTER", widget.textLayer, "CENTER")

    widget.secretCountdown:ApplyStyle(styles.countdown)
    widget.secretCountdown:ClearAllPoints()
    widget.secretCountdown:SetAllPoints(widget.textLayer)

    widget.stackText:ApplyStyle(styles.stacks)
    widget.stackText:ClearBounds()
    widget.stackText:SetAnchor("BOTTOMRIGHT", widget.textLayer, "BOTTOMRIGHT")

    widget.labelText:ApplyStyle(styles.label)
    widget.labelText:SetBounds(width, math.max(1, NumberOr(styles.label and styles.label.height, 20)))
    widget.labelText:SetAnchor("TOP", widget.textLayer, "BOTTOM", 0, 2)
end

local function UpdateCountdownText(widget, remaining)
    if not IsCountdownEnabled(widget) then
        widget.countdownText:Hide()
        return
    end
    local text = (widget.countdownTextPrefix or "") .. EXUI:FormatCountdown(remaining, widget.countdownFormat)
    if text ~= widget._countdownValue then
        widget._countdownValue = text
        widget.countdownText:SetText(text)
    end
    if widget.textStyles.countdown == nil or widget.textStyles.countdown.enabled ~= false then
        widget.countdownText:Show()
    end
end

local function IconWidgetOnUpdate(widget, elapsed)
    widget._cooldownElapsed = (widget._cooldownElapsed or 0) + elapsed
    if widget._cooldownElapsed < 0.05 then return end
    widget._cooldownElapsed = 0

    local rate = NumberOr(widget._cooldownModRate, 1)
    if rate <= 0 then rate = 1 end
    local remaining = ((widget._cooldownStart + widget._cooldownDuration / rate) - GetTime()) * rate
    if remaining <= 0 then
        UpdateCountdownText(widget, 0)
        widget._cooldownActive = false
        widget:SetScript("OnUpdate", nil)
        return
    end
    UpdateCountdownText(widget, remaining)
end

local IconWidgetResetSecretIcon

local function IconWidgetSetIcon(widget, texture)
    if widget._secretIcon == true then IconWidgetResetSecretIcon(widget) end
    widget.icon:SetAtlas(nil)
    widget.icon:SetTexture(texture)
    widget._secretIcon = nil
    return widget
end

-- IconWidget 的普通视觉输入除了 fileID 外，正式支持 Atlas 和单位肖像；模块仍
-- 不取得内部 Texture、也不建立 mask/texture 树。
local function IconWidgetSetAtlas(widget, atlas)
    if widget._secretIcon == true then IconWidgetResetSecretIcon(widget) end
    widget.icon:SetTexture(nil)
    widget.icon:SetAtlas(atlas, false)
    widget._secretIcon = nil
    return widget
end

local function IconWidgetSetUnitPortrait(widget, unit)
    if widget._secretIcon == true then IconWidgetResetSecretIcon(widget) end
    widget.icon:SetAtlas(nil)
    if unit and SetPortraitTexture then SetPortraitTexture(widget.icon, unit) else widget.icon:SetTexture(nil) end
    widget._secretIcon = nil
    return widget
end

-- Secret fileID 只能直传给原生 Region API；不得走普通图标的 Lua 判空路径。
local function IconWidgetSetSecretIcon(widget, texture)
    widget.icon:SetTexture(texture)
    widget._secretIcon = true
    return widget
end

-- 同一个 IconWidget 从 Secret Texture 复用或重套样式前的公开清理入口。
-- 具体 Texture 默认化后立即恢复其固定 parent-relative 锚点与层级；调用方随后
-- 必须 ApplyStyle，再写入普通或 Secret 图标。
IconWidgetResetSecretIcon = function(widget)
    widget.icon:SetToDefaults()
    EXUI:ApplyVisualLayer(widget.icon, _G.EXBASEFRAME, widget)
    widget.icon:SetAllPoints(widget)
    ApplyIconTextureStyle(widget)
    widget._secretIcon = nil
    return widget
end

local function IconWidgetSetDesaturated(widget, desaturated)
    widget._desaturatedOverride = desaturated == nil and nil or desaturated == true
    ApplyIconTextureStyle(widget)
    return widget
end

-- 跟 SetDesaturated 同一个轻量覆盖模式：只重算图标纹理这一层，不做完整 ApplyStyle（不碰
-- 边框/裁切/倒数/层数/标签），专门给 SPELL_UPDATE_USABLE 这类高频事件用，避免每次触发都
-- 级联重建全部子控件。
local function IconWidgetSetUsable(widget, isUsable)
    widget._unusableOverride = isUsable == false
    ApplyIconTextureStyle(widget)
    return widget
end

local function IconWidgetSetStacks(widget, stacks)
    local text = stacks and tostring(stacks) or ""
    -- 普通数字走自动测量（ClearBounds），不能继承上一次 SetSecretStacks 留下的固定 Bounds。
    widget.stackText:ClearBounds()
    widget.stackText:SetText(text)
    if text ~= "" and (widget.textStyles.stacks == nil or widget.textStyles.stacks.enabled ~= false) then
        widget.stackText:Show()
    else
        widget.stackText:Hide()
    end
    return widget
end

-- 2026-07-26 修复：Secret Text 不能测量宽高（TextWidget._measureText=false 时，没有
-- _boundsWidth 会回退到 widget:GetWidth() or 1，首次使用退化成 1x1 像素——SetText 调用
-- 本身不报错，但文字被压缩到看不见）。这里在写入前先给 stackText 固定 Bounds，与 IconWidget
-- 自身尺寸一致，避免测量导致的不可见问题。
local function IconWidgetSetSecretStacks(widget, secretText)
    widget.stackText:SetBounds(math.max(1, widget:GetWidth() or 1), math.max(1, widget:GetHeight() or 1))
    widget.stackText:SetSecretText(secretText)
    if widget.textStyles.stacks == nil or widget.textStyles.stacks.enabled ~= false then
        widget.stackText:Show()
    else
        widget.stackText:Hide()
    end
    return widget
end

local function IconWidgetSetLabel(widget, text)
    local hasText = TextWidgetSetDisplayText(widget.labelText, text)
    if hasText and (widget.textStyles.label == nil or widget.textStyles.label.enabled ~= false) then
        widget.labelText:Show()
    else
        widget.labelText:Hide()
    end
    return widget
end

local function IconWidgetSetCountdownText(widget, text)
    widget._cooldownActive = false
    widget:SetScript("OnUpdate", nil)
    widget.countdownText:SetText(text or "")
    widget.countdownText:SetShown(IsCountdownEnabled(widget) and text ~= "")
    return widget
end

local function IconWidgetSetSecretCountdownText(widget, text)
    widget._cooldownActive = false
    widget:SetScript("OnUpdate", nil)
    widget.countdownText:SetSecretText(text)
    if IsCountdownEnabled(widget) then widget.countdownText:Show() else widget.countdownText:Hide() end
    return widget
end

local function IconWidgetClearCooldown(widget)
    ClearNativeCooldown(widget)
    widget.countdownText:ClearDurationBinding()
    widget.countdownText:ApplyStyle(widget.textStyles and widget.textStyles.countdown or DEFAULT_TEXT_STYLE)
    widget.countdownText:SetText("")
    widget.countdownText:Hide()
    widget.secretCountdown:Clear()
    return widget
end

-- 冷却动画自然播完时没有独立事件通知调用方，只能靠原生 Cooldown 的 OnCooldownDone 脚本自己
-- 触发一次刷新，否则冷却结束后画面会一直卡在旧状态。内部 Cooldown 是私有字段，调用方不得直接
-- 访问；需要这个回调时必须通过这个公开入口注册，不能绕过封装。
local function IconWidgetSetCooldownDoneCallback(widget, callback)
    widget.cooldown:SetScript("OnCooldownDone", callback)
    return widget
end

local function IconWidgetSetCooldown(widget, moduleKey, start, duration, modRate, formatRules)
    if not EXUI:CanUseLegacyDurationPath(moduleKey) then
        EXUI:ReportDurationViolation(moduleKey, "IconWidget:SetCooldown")
        return IconWidgetClearCooldown(widget)
    end
    local numericStart = tonumber(start)
    local numericDuration = tonumber(duration)
    if not numericStart or not numericDuration or numericDuration <= 0 then
        return IconWidgetClearCooldown(widget)
    end

    widget.countdownFormat = formatRules or widget.countdownFormat
    widget._cooldownStart = numericStart
    widget._cooldownDuration = numericDuration
    widget._cooldownModRate = NumberOr(modRate, 1)
    widget._cooldownMode = "NUMERIC"
    widget._cooldownActive = true
    widget._cooldownElapsed = 0
    if widget.cooldown.SetPaused then widget.cooldown:SetPaused(false) end
    widget.cooldown:SetCooldown(start, duration, modRate)
    if widget._showNativeCooldown then widget.cooldown:Show() else widget.cooldown:Hide() end
    widget.secretCountdown:Clear()
    IconWidgetOnUpdate(widget, 1)
    if widget._cooldownActive then widget:SetScript("OnUpdate", IconWidgetOnUpdate) end
    return widget
end

-- The underlying Blizzard renderer accepts both ordinary and protected
-- Duration Objects.  Public callers must choose a semantic entry below, but
-- neither native path may leave the legacy numeric OnUpdate loop attached.
local function IconWidgetSetNativeDuration(widget, durationObject, clearIfZero, mode, durationTextProperty, durationTextOptions)
    if not durationObject then
        return IconWidgetClearCooldown(widget)
    end

    widget._cooldownActive = false
    widget._cooldownStart = nil
    widget._cooldownDuration = nil
    widget._cooldownModRate = nil
    widget._cooldownMode = mode
    widget._countdownValue = nil
    widget:SetScript("OnUpdate", nil)
    widget.countdownText:ClearDurationBinding()
    -- A pooled preview may have paused this Cooldown.  Native runtime input
    -- must always restore its clock before binding the Duration Object.
    if widget.cooldown.SetPaused then widget.cooldown:SetPaused(false) end
    if widget.cooldown.SetCooldownFromDurationObject then
        widget.cooldown:SetCooldownFromDurationObject(durationObject, clearIfZero == true)
    end
    if widget._showNativeCooldown then widget.cooldown:Show() else widget.cooldown:Hide() end

    if IsCountdownEnabled(widget) then
        -- 数字直接由 TextWidget 的原生 Duration binding 渲染；Cooldown 只保留图标
        -- 自己的扇形/边缘视觉，不再被借作“隐藏倒数圈”的文字 renderer。
        local options = type(durationTextOptions) == "table" and durationTextOptions or {}
        widget.countdownText:SetDurationBinding(durationObject, {
            property = options.property or durationTextProperty or Enum.DurationTextBindingProperty.RemainingDuration,
            formatter = options.formatter,
            components = options.components,
            formatString = options.formatString or (widget.countdownTextPrefix and (widget.countdownTextPrefix .. "{}") or nil),
            expiredText = options.expiredText,
            zeroDurationText = options.zeroDurationText,
            updateInterval = options.updateInterval,
        })
        widget.countdownText:Show()
    else
        widget.countdownText:Hide()
    end
    widget.secretCountdown:Clear()
    return widget
end

local function IconWidgetSetCountdownTextPrefix(widget, prefix)
    widget.countdownTextPrefix = type(prefix) == "string" and prefix or nil
    return widget
end

-- 设置页/世界编辑预览必须是普通模型的一帧快照，绝不能随着 GetTime 自行走动。
-- 运行时 SetCooldown 继续维持原行为；只有标准预览经此公开入口暂停原生扇形。
local function IconWidgetSetStaticCooldown(widget, remaining, duration, formatRules)
    local numericRemaining = tonumber(remaining)
    local numericDuration = tonumber(duration)
    if not numericRemaining or not numericDuration or numericDuration <= 0 then
        return IconWidgetClearCooldown(widget)
    end
    numericRemaining = math.max(0, math.min(numericDuration, numericRemaining))
    widget.countdownFormat = formatRules or widget.countdownFormat
    widget._cooldownActive = false
    widget._cooldownStart = nil
    widget._cooldownDuration = nil
    widget._cooldownModRate = nil
    widget._cooldownMode = "STATIC"
    widget._countdownValue = nil
    widget:SetScript("OnUpdate", nil)
    widget.countdownText:ClearDurationBinding()
    widget.countdownText:ApplyStyle(widget.textStyles and widget.textStyles.countdown or DEFAULT_TEXT_STYLE)
    ApplyStaticCooldownSwipeTexture(widget)
    if not widget.cooldown.SetPaused then
        error("EXUI IconWidget: Cooldown:SetPaused is required for static preview", 2)
    end
    widget.cooldown:SetPaused(false)
    widget.cooldown:SetCooldown(GetTime() - (numericDuration - numericRemaining), numericDuration, 1)
    widget.cooldown:SetPaused(true)
    if widget._showNativeCooldown then widget.cooldown:Show() else widget.cooldown:Hide() end
    -- 静态预览也必须有一帧可见的倒数数字。原先这里无条件清空数字，
    -- 使 panel/world 只有扇形却没有与 runtime 同源的时间文字。
    UpdateCountdownText(widget, numericRemaining)
    widget.secretCountdown:Clear()
    return widget
end

-- 2026-07-26 修复：原先是 start/duration/modRate 旧数值签名，从不驱动 secretCountdown，
-- 倒数数字出不来（当时留了 TODO，担心 Cooldown:SetCooldown 收 secret 参数是否安全未经验证）。
-- 现已通过 FrameAPICooldownDocumentation.lua 确认 SetCooldown 和 SetCooldownFromDurationObject
-- 都官方支持 secret 参数（SecretArgumentsAddAspect = Cooldown），改成收 Duration Object，
-- 同时驱动圆环扇形（原生 Cooldown）和倒数数字（内部 secretCountdown，同一份 Cooldown 挪用方案，
-- 已验证可靠，见 EXUI_组合控件规范.md 0.2）。clearIfZero 是 SetCooldownFromDurationObject 的
-- 官方参数名（到 0 秒是否自动清空显示），不是方向反转。
local function IconWidgetSetDurationObject(widget, durationObject, clearIfZero, durationTextProperty, durationTextOptions)
    return IconWidgetSetNativeDuration(widget, durationObject, clearIfZero, "DURATION", durationTextProperty, durationTextOptions)
end

local function IconWidgetSetSecretCooldown(widget, durationObject, clearIfZero)
    return IconWidgetSetNativeDuration(widget, durationObject, clearIfZero, "SECRET")
end

local function IconWidgetSetAnchor(widget, point, relativeTo, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point or "CENTER", relativeTo or widget:GetParent() or UIParent, relativePoint or point or "CENTER", x or 0, y or 0)
    return widget
end

-- RegionElements / fixed-core layout resolve only already-owned Icon regions.
-- Secret cooldown text has a distinct native root; expose the currently active
-- semantic root instead of making Collection guess a hidden normal FontString.
local function IconWidgetResolveDeclaredElement(widget, elementID)
    local id = tostring(elementID or "")
    if id == "core.root" or id == "core.icon" or id == "core.cooldown" then return widget end
    if id == "core.label" or id == "core.spellName" then return widget.labelText end
    if id == "core.stacks" then return widget.stackText end
    if id == "core.time" then
        if widget.secretCountdown and widget.secretCountdown:IsShown() then return widget.secretCountdown end
        return widget.countdownText
    end
    error("IconWidget unknown declared element: " .. id, 2)
end

-- 某些固定 Icon 组合需要隐藏圆形 cooldown 视觉、但仍用同一个 IconWidget
-- 显示倒数文本。这个纯 presentation 开关与 icon DB 样式分离，避免模块复制
-- 或改写 icon.cooldown/style 表。
local function IconWidgetSetCountdownTextVisibleOverride(widget, enabled)
    if enabled == nil then
        widget._countdownTextVisibleOverride = nil
    else
        widget._countdownTextVisibleOverride = enabled == true
    end
    if widget._cooldownActive then
        IconWidgetOnUpdate(widget, 1)
    elseif widget._countdownTextVisibleOverride == false then
        widget.countdownText:Hide()
        widget.secretCountdown:Clear()
    end
    return widget
end

local function IconWidgetSetCooldownVisualVisibleOverride(widget, enabled)
    if enabled == nil then
        widget._cooldownVisualVisibleOverride = nil
    else
        widget._cooldownVisualVisibleOverride = enabled == true
    end
    ApplyIconCooldownStyle(widget)
    if widget._cooldownActive then
        if widget._showNativeCooldown then widget.cooldown:Show() else widget.cooldown:Hide() end
    else
        widget.cooldown:Hide()
    end
    return widget
end

-- Icon 的额外内容必须经过这个声明式 Host；位置固定相对 Icon Body，边界仍由
-- IconCollection presentation.declaredBounds 单一声明，模块不能建立裸 visual tree。
local function IconWidgetGetExtraChildHost(widget, id)
    return type(widget.extraChildHosts) == "table" and widget.extraChildHosts[id] or nil
end

local function IconWidgetConfigureExtraChildHost(widget, id, spec)
    if type(id) ~= "string" or id == "" then error("IconWidget extra child id must be non-empty string", 2) end
    if type(spec) ~= "table" then error("IconWidget extra child spec must be table", 2) end
    local anchor = type(spec.anchor) == "table" and spec.anchor or spec
    if (anchor.relativeElement or "core.icon") ~= "core.icon" then
        error("IconWidget extra child host only supports relativeElement core.icon", 2)
    end
    widget.extraChildHosts = widget.extraChildHosts or {}
    local host = widget.extraChildHosts[id]
    if not host then
        host = CreateFrame("Frame", nil, widget)
        host:EnableMouse(false)
        EXUI:ApplyVisualLayer(host, _G.EXBORDERFRAME, widget)
        widget.extraChildHosts[id] = host
    end
    local width, height = math.max(1, NumberOr(spec.width, 1)), math.max(1, NumberOr(spec.height, 1))
    host:SetSize(width, height)
    host:ClearAllPoints()
    host:SetPoint(anchor.point or "CENTER", widget, anchor.relativePoint or anchor.point or "CENTER",
        NumberOr(anchor.x, 0), NumberOr(anchor.y, 0))
    host.__exwindDeclaredExtraChildSpec = { width = width, height = height, anchor = anchor }
    host:SetShown(spec.shown ~= false)
    return host
end

local function IconWidgetResetExtraChildHosts(widget)
    for _, host in pairs(widget.extraChildHosts or {}) do
        host:Hide()
        host:ClearAllPoints()
        host:SetSize(1, 1)
        host.__exwindDeclaredExtraChildSpec = nil
    end
end

local function IconWidgetApplyStyle(widget, style)
    widget.style = style or {}
    widget.iconStyle = ResolveIconStyle(widget.style)
    widget.textStyles = ResolveIconTextStyles(widget.style)
    widget.countdownFormat = widget.style.countdownFormat or widget.iconStyle.countdownFormat or widget.countdownFormat

    widget:SetSize(
        math.max(1, NumberOr(IconStyleValue(widget.iconStyle, "width"), 64)),
        math.max(1, NumberOr(IconStyleValue(widget.iconStyle, "height"), 64))
    )
    EXUI:ApplyVisualLayer(widget.icon, _G.EXBASEFRAME, widget)
    EXUI:ApplyVisualLayer(widget.cooldown, _G.EXFILLFRAME, widget)
    EXUI:ApplyVisualLayer(widget.border, _G.EXBORDERFRAME, widget)
    EXUI:ApplyVisualLayer(widget.textLayer, _G.EXFONTFRAME, widget)

    ApplyIconTextureStyle(widget)
    if widget.iconStyle.iconID then
        widget.icon:SetTexture(widget.iconStyle.iconID)
    end
    ApplyIconCooldownStyle(widget)
    ApplyIconBorder(widget)
    LayoutIconTextSlots(widget)

    if not IsCooldownVisualEnabled(widget) then
        widget.cooldown:Hide()
    elseif widget._cooldownActive then
        if widget._showNativeCooldown then widget.cooldown:Show() else widget.cooldown:Hide() end
    end
    if not IsCountdownEnabled(widget) then
        widget.countdownText:Hide()
        widget.secretCountdown:Clear()
    elseif widget._cooldownActive then
        IconWidgetOnUpdate(widget, 1)
    end
    return widget
end

local function IconWidgetRelease(widget)
    if widget._released then return end
    widget._released = true
    widget._countdownTextVisibleOverride = nil
    widget._cooldownVisualVisibleOverride = nil
    IconWidgetClearCooldown(widget)
    IconWidgetResetExtraChildHosts(widget)
    if widget._secretIcon then IconWidgetResetSecretIcon(widget) end
    widget.cooldown:SetScript("OnCooldownDone", nil)
    widget.icon:SetTexture(nil)
    widget.icon:SetDesaturated(false)
    widget.icon:SetAlpha(1)
    widget.icon:SetVertexColor(1, 1, 1, 1)
    widget.icon:SetBlendMode("BLEND")
    widget.icon:SetRotation(0)
    widget.border:Hide()
    if widget.secretSafeBorder then widget.secretSafeBorder:Hide() end
    widget:Hide()
    widget:ClearAllPoints()
    if widget.countdownText then widget.countdownText:Release(); widget.countdownText = nil end
    if widget.secretCountdown then widget.secretCountdown:Release(); widget.secretCountdown = nil end
    if widget.stackText then widget.stackText:Release(); widget.stackText = nil end
    if widget.labelText then widget.labelText:Release(); widget.labelText = nil end
    widget.style = nil
    widget.iconStyle = nil
    widget.textStyles = nil
    widget.countdownFormat = nil
    widget.countdownTextPrefix = nil
    widget._desaturatedOverride = nil
    widget._unusableOverride = nil
    widget._secretIcon = nil
    EXFactory:Release(ICON_WIDGET_POOL, widget)
end

EXFactory:InitPool(ICON_WIDGET_POOL, "Frame", nil, function(widget)
    widget.root = widget
    widget:SetSize(64, 64)
    widget:EnableMouse(false)

    local icon = EXUI:CreateVisualTexture(widget, _G.EXBASEFRAME)
    icon:SetAllPoints(widget)
    widget.icon = icon

    local cooldown = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
    cooldown:SetAllPoints(widget)
    cooldown:EnableMouse(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown.noCooldownCount = true
    cooldown.noOCC = true
    cooldown:Hide()
    EXUI:ApplyVisualLayer(cooldown, _G.EXFILLFRAME, widget)
    widget.cooldown = cooldown

    local border = CreateFrame("Frame", nil, widget, "BackdropTemplate")
    border:EnableMouse(false)
    border:Hide()
    EXUI:ApplyVisualLayer(border, _G.EXBORDERFRAME, widget)
    widget.border = border

    -- Secret geometry must never reach Backdrop/NineSlice: Blizzard's
    -- implementation performs Lua-visible width/height arithmetic.  These
    -- four fixed 1px textures are geometry-free and therefore safe to anchor
    -- to a Secret-positioned icon.
    local secretSafeBorder = CreateFrame("Frame", nil, widget)
    secretSafeBorder:EnableMouse(false)
    secretSafeBorder:SetAllPoints(widget)
    secretSafeBorder:Hide()
    EXUI:ApplyVisualLayer(secretSafeBorder, _G.EXBORDERFRAME, widget)
    local function Edge(pointA, pointB, width, height)
        local edge = EXUI:CreateVisualTexture(secretSafeBorder, _G.EXBORDERFRAME)
        edge:SetColorTexture(0, 0, 0, 1)
        edge:SetPoint(pointA, secretSafeBorder, pointA, pointA:find("LEFT", 1, true) and -1 or 1,
            pointA:find("TOP", 1, true) and 1 or -1)
        edge:SetPoint(pointB, secretSafeBorder, pointB, pointB:find("LEFT", 1, true) and -1 or 1,
            pointB:find("TOP", 1, true) and 1 or -1)
        if width then edge:SetWidth(width) end
        if height then edge:SetHeight(height) end
        return edge
    end
    secretSafeBorder.top = Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    secretSafeBorder.bottom = Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    secretSafeBorder.left = Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    secretSafeBorder.right = Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    widget.secretSafeBorder = secretSafeBorder

    -- Pool reuse and style changes can resize an IconWidget without recreating
    -- its Backdrop frame. Reapply the final LSM border geometry at that point.
    widget:HookScript("OnSizeChanged", function(self)
        if not self._suppressBorderGeometry and self.iconStyle and self.border:IsShown() then
            ApplyIconBorder(self)
        end
    end)
    local textLayer = CreateFrame("Frame", nil, widget)
    textLayer:SetAllPoints(widget)
    textLayer:EnableMouse(false)
    EXUI:ApplyVisualLayer(textLayer, _G.EXFONTFRAME, widget)
    widget.textLayer = textLayer
    widget.extraChildHosts = {}

    widget.SetIcon = IconWidgetSetIcon
    widget.SetAtlas = IconWidgetSetAtlas
    widget.SetUnitPortrait = IconWidgetSetUnitPortrait
    widget.SetSecretIcon = IconWidgetSetSecretIcon
    widget.ResetSecretIcon = IconWidgetResetSecretIcon
    widget.SetDesaturated = IconWidgetSetDesaturated
    widget.SetUsable = IconWidgetSetUsable
    widget.SetStacks = IconWidgetSetStacks
    widget.SetSecretStacks = IconWidgetSetSecretStacks
    widget.SetLabel = IconWidgetSetLabel
    widget.SetCountdownText = IconWidgetSetCountdownText
    widget.SetCountdownTextPrefix = IconWidgetSetCountdownTextPrefix
    widget.SetSecretCountdownText = IconWidgetSetSecretCountdownText
    widget.SetCooldown = IconWidgetSetCooldown
    widget.SetDurationObject = IconWidgetSetDurationObject
    widget.SetStaticCooldown = IconWidgetSetStaticCooldown
    widget.SetSecretCooldown = IconWidgetSetSecretCooldown
    widget.SetCooldownDoneCallback = IconWidgetSetCooldownDoneCallback
    widget.ClearCooldown = IconWidgetClearCooldown
    widget.ApplyStyle = IconWidgetApplyStyle
    widget.SetAnchor = IconWidgetSetAnchor
    widget.ResolveDeclaredElement = IconWidgetResolveDeclaredElement
    widget.SetCountdownTextVisibleOverride = IconWidgetSetCountdownTextVisibleOverride
    widget.SetCooldownVisualVisibleOverride = IconWidgetSetCooldownVisualVisibleOverride
    widget.SetSuppressBorderGeometry = function(self, suppress)
        self._suppressBorderGeometry = suppress == true
        self._useSecretSafeBorder = suppress == true
        return self
    end
    widget.GetExtraChildHost = IconWidgetGetExtraChildHost
    widget.ConfigureExtraChildHost = IconWidgetConfigureExtraChildHost
    widget.Release = IconWidgetRelease
end)

-- 模块只持有这个 Widget，不直接建立/销毁 Texture、Cooldown 或 FontString 子件。
function EXUI:CreateIconWidget(parent, style)
    local widget = EXFactory:Acquire(ICON_WIDGET_POOL, parent)
    widget._released = false
    widget._desaturatedOverride = nil
    widget._unusableOverride = nil
    widget._suppressBorderGeometry = nil
    widget._useSecretSafeBorder = nil
    widget.countdownText = EXUI:CreateTextWidget(widget.textLayer, "countdown")
    widget.secretCountdown = EXUI:CreateSecretCountdownWidget(widget.textLayer)
    widget.stackText = EXUI:CreateTextWidget(widget.textLayer, "stacks")
    widget.labelText = EXUI:CreateTextWidget(widget.textLayer, "label")
    widget:ApplyStyle(style or DEFAULT_ICON_STYLE)
    widget:ClearCooldown()
    widget:SetStacks(nil)
    widget:SetLabel(nil)
    return widget
end

-- =========================================================
-- TimerBarWidget：横向计时条（StatusBar + 显示型 IconWidget + TextWidget）
-- =========================================================

local TIMER_BAR_WIDGET_POOL = "RuntimeTimerBarWidget"
local DEFAULT_TIMER_BAR_STYLE = {
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
    fillDirection = "LEFT_TO_RIGHT",
    progressMode = "REMAINING",
    showIcon = true,
    iconWidth = 24,
    iconHeight = 24,
    iconSide = "LEFT",
    iconSize = 24,
    iconOffsetX = -5,
    iconOffsetY = 0,
    -- true：外置图标计入整个 Widget 的布局宽度（通用默认）。
    -- false：Widget 宽度始终等于条体宽度，图标仅向条体外延伸，适用于 EXBoss 多条计时条。
    includeExternalIconInBounds = true,
    showIconBorder = true,
    iconBorderTexture = "None",
    iconBorderSize = 1,
    iconBorderPadding = 0,
    iconBorderColorR = 1, iconBorderColorG = 1, iconBorderColorB = 1, iconBorderColorA = 1,
    showTime = true,
    showMarkers = false,
    -- 模块可把自己的提示 Atlas 解析成 visual 列表交给 TimerBarWidget；控件只负责绘制和布局。
    -- 运行时与设置预览共用此通道，禁止在页面层另建一套图标覆盖物。
    alertIcons = { showIcon = true, anchor = "OUTSIDE_LEFT", layout = "HORIZONTAL", size = 16, x = 0, y = 0 },
    alpha = 1,
}

local DEFAULT_TIMER_LABEL_STYLE = {
    enabled = true,
    justifyH = "LEFT", justifyV = "MIDDLE",
    x = 5, y = 0,
    drawLayer = "OVERLAY", drawSubLevel = 10,
}

local DEFAULT_TIMER_TIME_STYLE = {
    enabled = true,
    justifyH = "RIGHT", justifyV = "MIDDLE",
    x = -5, y = 0,
    drawLayer = "OVERLAY", drawSubLevel = 11,
}

local DEFAULT_TIMER_STACK_STYLE = {
    enabled = true,
    justifyH = "CENTER", justifyV = "MIDDLE",
    x = 0, y = 0,
    drawLayer = "OVERLAY", drawSubLevel = 12,
}

local function TimerStyleValue(timerStyle, key)
    local value = timerStyle and timerStyle[key]
    if value == nil then value = DEFAULT_TIMER_BAR_STYLE[key] end
    return value
end

local function ResolveTimerStyle(style)
    if type(style) == "table" and type(style.timerBar) == "table" then
        return style.timerBar
    end
    return type(style) == "table" and style or DEFAULT_TIMER_BAR_STYLE
end

local function ResolveStatusBarTexture(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(name) == "string" and name ~= "" then
        local path = LSM:Fetch("statusbar", name, true)
        if path then return path end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function IsTimerReverseFill(widget)
    local direction = tostring(TimerStyleValue(widget.timerStyle, "fillDirection") or "LEFT_TO_RIGHT"):upper()
    return direction == "RIGHT_TO_LEFT" or direction == "RTL" or direction == "REVERSE"
end

local function ApplyTimerFillDirection(widget)
    local reverse = IsTimerReverseFill(widget)
    for _, bar in ipairs({ widget.bar, widget.secretBar }) do
        if bar and bar.SetFillStyle and _G.Enum and Enum.StatusBarFillStyle then
            bar:SetFillStyle(reverse and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
        elseif bar and bar.SetReverseFill then
            bar:SetReverseFill(reverse)
        end
    end
end

-- 普通 Duration 与受保护 Secret Duration 的可见承载必须分开：普通数据走
-- 主 bar，只有 Secret 数据才使用独立的 secretBar。不能因为两者都使用原生
-- Duration Object 就把普通条也切到第二个 StatusBar，否则会形成额外前景层。
local function GetTimerDurationBar(widget, mode)
    if mode == "SECRET" then
        return widget.secretBar, widget.bar
    end
    return widget.bar, widget.secretBar
end

local function ResetTimerDurationBar(widget, mode)
    local bar = GetTimerDurationBar(widget, mode)
    if bar and bar.SetToDefaults then
        bar:SetToDefaults()
    end
end

local function ApplyTimerBarBorder(widget)
    local timerStyle = widget.timerStyle
    local configuredSize = NumberOr(TimerStyleValue(timerStyle, "borderSize"), 1)
    if TimerStyleValue(timerStyle, "showBorder") == false or configuredSize <= 0 then
        widget.border:Hide()
        return
    end
    local padding = NumberOr(TimerStyleValue(timerStyle, "borderPadding"), 0)
    widget.border:ClearAllPoints()
    widget.border:SetPoint("TOPLEFT", widget.bar, "TOPLEFT", -padding, padding)
    widget.border:SetSize((widget.bar:GetWidth() or 0) + padding * 2, (widget.bar:GetHeight() or 0) + padding * 2)
    widget.border:SetBackdrop({
        edgeFile = ResolveBorderTexture(TimerStyleValue(timerStyle, "borderTexture")),
        edgeSize = configuredSize,
    })
    widget.border:SetBackdropBorderColor(
        NumberOr(TimerStyleValue(timerStyle, "borderColorR"), 1),
        NumberOr(TimerStyleValue(timerStyle, "borderColorG"), 1),
        NumberOr(TimerStyleValue(timerStyle, "borderColorB"), 1),
        NumberOr(TimerStyleValue(timerStyle, "borderColorA"), 1)
    )
    widget.border:Show()
end

local function ResetTimerBarSecretFillColors(widget)
    local regions = widget._secretFillRegions
    if not regions then return end
    for region in pairs(regions) do
        if region and region.SetToDefaults then region:SetToDefaults() end
    end
    widget._secretFillRegions = nil
end

local function ApplyTimerBarVisual(widget)
    ResetTimerBarSecretFillColors(widget)
    local timerStyle = widget.timerStyle
    local texture = ResolveStatusBarTexture(TimerStyleValue(timerStyle, "texture"))
    local r = NumberOr(TimerStyleValue(timerStyle, "barColorR"), 1)
    local g = NumberOr(TimerStyleValue(timerStyle, "barColorG"), 0.7)
    local b = NumberOr(TimerStyleValue(timerStyle, "barColorB"), 0)
    local a = NumberOr(TimerStyleValue(timerStyle, "barColorA"), 1)
    -- 秘密 Duration 只能绑定给专属 StatusBar；普通进度条与它绝不共用同一个原生对象。
    -- 两个条始终套同一视觉样式，切换时只显示其中一个。
    for _, bar in ipairs({ widget.bar, widget.secretBar }) do
        if bar then
            bar:SetStatusBarTexture(texture)
            bar:SetStatusBarColor(r, g, b, a)
        end
    end
    widget.background:SetTexture(texture)
    widget.background:SetVertexColor(
        NumberOr(TimerStyleValue(timerStyle, "barBgColorR"), 0),
        NumberOr(TimerStyleValue(timerStyle, "barBgColorG"), 0),
        NumberOr(TimerStyleValue(timerStyle, "barBgColorB"), 0),
        NumberOr(TimerStyleValue(timerStyle, "barBgColorA"), 0.5)
    )
    widget:SetAlpha(NumberOr(TimerStyleValue(timerStyle, "alpha"), 1))
    ApplyTimerFillDirection(widget)
    ApplyTimerBarBorder(widget)
end

-- 这是 TimerBar 的声明式局部几何：所有值均相对 Widget.CENTER，不读取
-- GetLeft/GetRight。世界编辑 SelectionFrame 与实际 LayoutTimerBar 共享它，
-- 因而不受同帧几何结算、屏幕缩放或 Region 层级影响。
local function NewSelectionRect(left, right, bottom, top)
    return { left = left, right = right, bottom = bottom, top = top }
end

local function UnionSelectionRect(target, rect)
    if not rect then return target end
    if not target then return NewSelectionRect(rect.left, rect.right, rect.bottom, rect.top) end
    target.left = math.min(target.left, rect.left)
    target.right = math.max(target.right, rect.right)
    target.bottom = math.min(target.bottom, rect.bottom)
    target.top = math.max(target.top, rect.top)
    return target
end

local function TranslateSelectionRect(rect, x, y)
    return NewSelectionRect(rect.left + x, rect.right + x, rect.bottom + y, rect.top + y)
end

local function RectPoint(rect, point)
    point = tostring(point or "CENTER"):upper()
    local x = point:find("LEFT", 1, true) and rect.left or (point:find("RIGHT", 1, true) and rect.right or (rect.left + rect.right) * 0.5)
    local y = point:find("TOP", 1, true) and rect.top or (point:find("BOTTOM", 1, true) and rect.bottom or (rect.bottom + rect.top) * 0.5)
    return x, y
end

local function RectPointOffset(width, height, point)
    point = tostring(point or "CENTER"):upper()
    local x = point:find("LEFT", 1, true) and 0 or (point:find("RIGHT", 1, true) and width or width * 0.5)
    local y = point:find("TOP", 1, true) and height or (point:find("BOTTOM", 1, true) and 0 or height * 0.5)
    return x, y
end

local function BuildAnchoredSelectionRect(relativeRect, anchor, width, height)
    if not relativeRect then return nil end
    local targetX, targetY = RectPoint(relativeRect, anchor.relativePoint or anchor.point or "CENTER")
    local ownX, ownY = RectPointOffset(width, height, anchor.point or "CENTER")
    local left = targetX + NumberOr(anchor.x, 0) - ownX
    local bottom = targetY + NumberOr(anchor.y, 0) - ownY
    return NewSelectionRect(left, left + width, bottom, bottom + height)
end

local function LayoutTimerBar(widget)
    local timerStyle = widget.timerStyle
    local geometry = type(widget._geometryOverride) == "table" and widget._geometryOverride or nil
    local presentationOptions = type(widget._presentationOptions) == "table" and widget._presentationOptions or nil
    local barWidth = math.max(1, NumberOr(geometry and geometry.width, TimerStyleValue(timerStyle, "width")))
    local barHeight = math.max(1, NumberOr(geometry and geometry.height, TimerStyleValue(timerStyle, "height")))
    -- A RegionElements child may deliberately suppress the built-in icon while
    -- retaining the exact same DB style.  Do not use `and/or` here: an explicit
    -- false would otherwise fall through to the DB default and re-show it.
    local showIcon
    if presentationOptions and presentationOptions.showIcon ~= nil then
        showIcon = presentationOptions.showIcon == true
    else
        showIcon = TimerStyleValue(timerStyle, "showIcon") ~= false
    end
    local legacyIconSize = NumberOr(TimerStyleValue(timerStyle, "iconSize"), barHeight)
    -- 图标始终使用独立宽高；autoIconSize 已从 EXUI 模型移除。
    local iconWidth = math.max(1, NumberOr(TimerStyleValue(timerStyle, "iconWidth"), legacyIconSize))
    local iconHeight = math.max(1, NumberOr(TimerStyleValue(timerStyle, "iconHeight"), legacyIconSize))
    local iconX = NumberOr(TimerStyleValue(timerStyle, "iconOffsetX"), 0)
    local iconY = NumberOr(TimerStyleValue(timerStyle, "iconOffsetY"), 0)
    local iconSide = tostring(TimerStyleValue(timerStyle, "iconSide") or "LEFT"):upper()
    local iconInsideBar = iconSide == "CENTER"
    local includeExternalIconInBounds = TimerStyleValue(timerStyle, "includeExternalIconInBounds") ~= false
    local totalWidth = barWidth + (includeExternalIconInBounds and showIcon and not iconInsideBar and (iconWidth + math.abs(iconX)) or 0)
    local totalHeight = math.max(barHeight, showIcon and (iconHeight + math.abs(iconY)) or 0)

    widget:SetSize(totalWidth, totalHeight)
    widget.bar:SetSize(barWidth, barHeight)
    widget.bar:ClearAllPoints()
    if showIcon and iconSide == "RIGHT" and includeExternalIconInBounds then
        widget.bar:SetPoint("LEFT", widget, "LEFT", 0, 0)
    elseif showIcon and iconSide == "LEFT" and includeExternalIconInBounds then
        widget.bar:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
    else
        widget.bar:SetPoint("CENTER", widget, "CENTER", 0, 0)
    end

    widget.secretBar:ClearAllPoints()
    widget.secretBar:SetAllPoints(widget.bar)

    widget.background:ClearAllPoints()
    widget.background:SetAllPoints(widget.bar)
    widget.textLayer:ClearAllPoints()
    widget.textLayer:SetAllPoints(widget.bar)
    widget.markerLayer:ClearAllPoints()
    widget.markerLayer:SetAllPoints(widget.bar)
    widget.leftDecorationsLayer:ClearAllPoints()
    widget.leftDecorationsLayer:SetAllPoints(widget)
    widget.alertLayer:ClearAllPoints()
    widget.alertLayer:SetAllPoints(widget)

    if showIcon then
        widget.icon:SetSize(iconWidth, iconHeight)
        widget.icon:ClearAllPoints()
        if iconSide == "RIGHT" then
            widget.icon:SetPoint("LEFT", widget.bar, "RIGHT", iconX, iconY)
        elseif iconSide == "CENTER" then
            widget.icon:SetPoint("CENTER", widget.bar, "CENTER", iconX, iconY)
        else
            widget.icon:SetPoint("RIGHT", widget.bar, "LEFT", iconX, iconY)
        end
        widget.icon:Show()
    else
        widget.icon:Hide()
    end

    widget.labelText:SetBounds(barWidth, barHeight)
    widget.labelText:SetAnchor("CENTER", widget.bar, "CENTER")
    widget.timeText:SetBounds(barWidth, barHeight)
    widget.timeText:SetAnchor("CENTER", widget.bar, "CENTER")
    widget.secretCountdown:ClearAllPoints()
    widget.secretCountdown:SetAllPoints(widget.bar)
    -- 固定 Bounds 是必须的：Secret 层数文字不能测量宽高，没有 Bounds 会退化成 1x1 像素
    -- 不可见（同 IconWidget 踩过的坑，见 EXUI_组合控件规范.md 0.3.2）。
    widget.stackText:SetBounds(barWidth, barHeight)
    widget.stackText:SetAnchor("CENTER", widget.bar, "CENTER")

    local rootRect = NewSelectionRect(-totalWidth * 0.5, totalWidth * 0.5, -totalHeight * 0.5, totalHeight * 0.5)
    local barLeft, barRight
    if showIcon and iconSide == "RIGHT" and includeExternalIconInBounds then
        barLeft, barRight = -totalWidth * 0.5, -totalWidth * 0.5 + barWidth
    elseif showIcon and iconSide == "LEFT" and includeExternalIconInBounds then
        barRight, barLeft = totalWidth * 0.5, totalWidth * 0.5 - barWidth
    else
        barLeft, barRight = -barWidth * 0.5, barWidth * 0.5
    end
    local barRect = NewSelectionRect(barLeft, barRight, -barHeight * 0.5, barHeight * 0.5)
    local iconRect = nil
    if showIcon then
        if iconSide == "RIGHT" then
            iconRect = NewSelectionRect(barRight + iconX, barRight + iconX + iconWidth, iconY - iconHeight * 0.5, iconY + iconHeight * 0.5)
        elseif iconSide == "CENTER" then
            iconRect = NewSelectionRect(iconX - iconWidth * 0.5, iconX + iconWidth * 0.5, iconY - iconHeight * 0.5, iconY + iconHeight * 0.5)
        else
            iconRect = NewSelectionRect(barLeft + iconX - iconWidth, barLeft + iconX, iconY - iconHeight * 0.5, iconY + iconHeight * 0.5)
        end
    end
    local labelStyle, timeStyle = widget.textStyles.label or {}, widget.textStyles.time or {}
    widget.declaredSelectionRects = {
        ["core.root"] = rootRect,
        ["core.bar"] = barRect,
        ["core.icon"] = iconRect,
        ["core.spellName"] = TranslateSelectionRect(barRect, NumberOr(labelStyle.x, 0), NumberOr(labelStyle.y, 0)),
        ["core.time"] = TranslateSelectionRect(barRect, NumberOr(timeStyle.x, 0), NumberOr(timeStyle.y, 0)),
    }
end

local function EnsureTimerMarker(widget, index)
    local marker = widget.markers[index]
    if marker then return marker end

    local track = CreateFrame("StatusBar", nil, widget.markerLayer)
    track:SetAllPoints(widget.markerLayer)
    track:SetClipsChildren(true)
    track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    track:GetStatusBarTexture():SetAlpha(0)
    track:Hide()

    local line = EXUI:CreateVisualTexture(track, _G.EXBORDERFRAME)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:Hide()
    marker = { track = track, line = line }
    widget.markers[index] = marker
    return marker
end

local function ApplyTimerMarkers(widget, markerList)
    markerList = type(markerList) == "table" and markerList or {}
    local reverse = IsTimerReverseFill(widget)
    for index, entry in ipairs(markerList) do
        local marker = EnsureTimerMarker(widget, index)
        local value = type(entry) == "table" and (entry.value or entry.percent) or entry
        value = math.max(0, math.min(1, NumberOr(value, 0)))
        local lineWidth = math.max(1, NumberOr(type(entry) == "table" and entry.width, 1))
        local r = NumberOr(type(entry) == "table" and entry.r, 1)
        local g = NumberOr(type(entry) == "table" and entry.g, 1)
        local b = NumberOr(type(entry) == "table" and entry.b, 1)
        local a = NumberOr(type(entry) == "table" and entry.a, 0.65)

        if marker.track.SetFillStyle and _G.Enum and Enum.StatusBarFillStyle then
            marker.track:SetFillStyle(reverse and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
        elseif marker.track.SetReverseFill then
            marker.track:SetReverseFill(reverse)
        end
        marker.track:SetMinMaxValues(0, 1)
        marker.track:SetValue(value)
        marker.line:SetWidth(lineWidth)
        marker.line:SetHeight(widget.bar:GetHeight())
        marker.line:SetVertexColor(r, g, b, a)
        marker.line:ClearAllPoints()
        if reverse then
            marker.line:SetPoint("RIGHT", marker.track:GetStatusBarTexture(), "LEFT")
        else
            marker.line:SetPoint("LEFT", marker.track:GetStatusBarTexture(), "RIGHT")
        end
        marker.track:Show()
        marker.line:Show()
    end
    for index = #markerList + 1, #widget.markers do
        widget.markers[index].track:Hide()
        widget.markers[index].line:Hide()
    end
    widget.markerData = markerList
end

local function UpdateTimerText(widget, remaining)
    if TimerStyleValue(widget.timerStyle, "showTime") == false then
        widget.timeText:Hide()
        return
    end
    local text = EXUI:FormatCountdown(remaining, widget.countdownFormat)
    if text ~= widget._timeTextValue then
        widget._timeTextValue = text
        widget.timeText:SetText(text)
    end
    if widget.textStyles.time == nil or widget.textStyles.time.enabled ~= false then
        widget.timeText:Show()
    end
end

local function TimerBarWidgetOnUpdate(widget, elapsed)
    widget._timerElapsed = (widget._timerElapsed or 0) + elapsed
    if widget._timerElapsed < 0.05 then return end
    widget._timerElapsed = 0

    local rate = NumberOr(widget._timerModRate, 1)
    if rate <= 0 then rate = 1 end
    local remaining = ((widget._timerStart + widget._timerDuration / rate) - GetTime()) * rate
    if remaining <= 0 then
        widget.bar:SetValue(widget._timerProgressMode == "ELAPSED" and widget._timerDuration or 0)
        UpdateTimerText(widget, 0)
        widget._timerActive = false
        widget:SetScript("OnUpdate", nil)
        return
    end
    widget.bar:SetValue(widget._timerProgressMode == "ELAPSED" and (widget._timerDuration - remaining) or remaining)
    UpdateTimerText(widget, remaining)
end

-- 普通数值进度：value/minimum/maximum 全部是非 secret 明文数字，可以安全 clamp。
-- 秘密来源的数值（例如 UnitHealthPercent/UnitPowerPercent）必须走 SetSecretProgress，
-- 不能传进这个函数——这里的 math.max/math.min 对 secret 值会直接报错。
-- 参数顺序 (value, maximum, minimum)：minimum 放在最后且可选，是为了不破坏 EXBoss 现有的
-- 两参数调用方（ExBossDisplay/TimerBar/View.lua、ExtraShieldBar.lua、CastProgressBar.lua
-- 等都是 SetProgress(value, maximum) 旧签名，minimum 缺省按 0 处理，跟这些调用方原本的
-- 隐含语义完全一致）。
local function TimerBarWidgetSetProgress(widget, value, maximum, minimum)
    if widget._timerMode == "SECRET" or widget._timerMode == "DURATION" then
        ResetTimerDurationBar(widget, widget._timerMode)
        ApplyTimerBarVisual(widget)
    end
    minimum = NumberOr(minimum, 0)
    maximum = math.max(minimum + 1, NumberOr(maximum, minimum + 1))
    widget._timerActive = false
    widget:SetScript("OnUpdate", nil)
    widget._timerMode = "NUMERIC"
    widget.secretBar:Hide()
    widget.bar:Show()
    widget.bar:SetMinMaxValues(minimum, maximum)
    widget.bar:SetValue(math.max(minimum, math.min(maximum, NumberOr(value, minimum))))
    return widget
end

-- Secret Progress 专用通道：minimum/maximum 是调用方保证的非 secret 数值（例如资源槽位
-- 上限、百分比曲线固定的 0~1 值域），value 本身可能是 secret（UnitHealthPercent/
-- UnitPowerPercent 或非 secret 的次要资源点数皆可）。value 原封不动交给 StatusBar:SetValue，
-- 不做 tonumber/比较/clamp/运算；跟 SetSecretTime 共用同一条 secretBar，二者互斥（同一时刻
-- 只会处于秘密计时或秘密进度其中一种），不会冲突。参数顺序跟 SetProgress 保持一致
-- (value, maximum, minimum)，这是全新方法没有历史调用方，纯粹为了两个方法好记。
local function TimerBarWidgetSetSecretProgress(widget, secretValue, maximum, minimum)
    widget._timerActive = false
    widget:SetScript("OnUpdate", nil)
    widget._timeTextValue = nil
    widget._timerMode = "SECRET"
    widget.bar:Hide()
    widget.secretBar:Show()
    widget.secretBar:SetMinMaxValues(NumberOr(minimum, 0), math.max(1, NumberOr(maximum, 1)))
    widget.secretBar:SetValue(secretValue)
    widget.timeText:ClearDurationBinding()
    widget.timeText:ApplyStyle(widget.textStyles and widget.textStyles.time or DEFAULT_TEXT_STYLE)
    widget.timeText:SetText("")
    widget.timeText:Hide()
    widget.secretCountdown:Clear()
    return widget
end

local function TimerBarWidgetSetFillColorFromBoolean(widget, value, trueColor, falseColor)
    widget._secretFillRegions = widget._secretFillRegions or {}
    for _, statusBar in ipairs({ widget.bar, widget.secretBar }) do
        local texture = statusBar:GetStatusBarTexture()
        if texture then
            widget._secretFillRegions[texture] = true
            texture:SetVertexColorFromBoolean(value, trueColor, falseColor)
        end
    end
    return widget
end

-- 普通颜色通道：供非 Secret 的模块数据（例如职业文件名解析出的职业色）写入。
-- Secret Boolean 必须继续走 SetFillColorFromBoolean，不能借此方法绕过原生直传规则。
local function TimerBarWidgetSetFillColor(widget, color)
    if not color then return widget end
    if widget._secretFillRegions then ApplyTimerBarVisual(widget) end
    local r, g, b, a = color.r, color.g, color.b, color.a or 1
    for _, statusBar in ipairs({ widget.bar, widget.secretBar }) do
        local texture = statusBar:GetStatusBarTexture()
        if texture then
            texture:SetVertexColor(r, g, b, a)
        end
    end
    return widget
end

local function TimerBarWidgetClearTime(widget)
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: ClearTime begin") end
    widget._timerActive = false
    widget._timerStart = nil
    widget._timerDuration = nil
    widget._timerModRate = nil
    widget._timeTextValue = nil
    widget._timerDoneCallback = nil
    if widget.secretCountdown and widget.secretCountdown.cooldown then
        widget.secretCountdown.cooldown:SetScript("OnCooldownDone", nil)
    end
    widget:SetScript("OnUpdate", nil)
    if widget._timerMode == "SECRET" or widget._timerMode == "DURATION" then
        ResetTimerDurationBar(widget, widget._timerMode)
    end
    ApplyTimerBarVisual(widget)
    widget._timerMode = nil
    widget.secretBar:Hide()
    widget.bar:Show()
    widget.bar:SetMinMaxValues(0, 1)
    widget.bar:SetValue(0)
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: normal bar reset") end
    widget.timeText:ClearDurationBinding()
    widget.timeText:ApplyStyle(widget.textStyles and widget.textStyles.time or DEFAULT_TEXT_STYLE)
    widget.timeText:SetText("")
    widget.timeText:Hide()
    widget.secretCountdown:Clear()
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: ClearTime complete") end
    return widget
end

-- 原生 Duration 结束后的业务状态切换只能由 Cooldown 的 C++ 完成通知触发；
-- 不建立 Lua OnUpdate/Ticker。该回调是 TimerBarWidget 的正式窄入口，调用方
-- 不得接触私有 Cooldown Region。
local function TimerBarWidgetSetTimerDoneCallback(widget, callback)
    widget._timerDoneCallback = type(callback) == "function" and callback or nil
    local cooldown = widget.secretCountdown and widget.secretCountdown.cooldown
    if cooldown then
        cooldown:SetScript("OnCooldownDone", widget._timerDoneCallback)
    end
    return widget
end

local function TimerBarWidgetSetTime(widget, moduleKey, start, duration, modRate, formatRules)
    if not EXUI:CanUseLegacyDurationPath(moduleKey) then
        EXUI:ReportDurationViolation(moduleKey, "TimerBarWidget:SetTime")
        return TimerBarWidgetClearTime(widget)
    end
    if widget._timerMode == "SECRET" or widget._timerMode == "DURATION" then
        ResetTimerDurationBar(widget, widget._timerMode)
        ApplyTimerBarVisual(widget)
    end
    widget.secretCountdown:Clear()
    widget._timerMode = "NUMERIC"
    widget.secretBar:Hide()
    widget.bar:Show()
    local numericStart = tonumber(start)
    local numericDuration = tonumber(duration)
    if not numericStart or not numericDuration or numericDuration <= 0 then
        return TimerBarWidgetClearTime(widget)
    end
    widget.countdownFormat = formatRules or widget.countdownFormat
    widget._timerStart = numericStart
    widget._timerDuration = numericDuration
    widget._timerModRate = NumberOr(modRate, 1)
    widget._timerProgressMode = tostring(TimerStyleValue(widget.timerStyle, "progressMode") or "REMAINING"):upper()
    widget._timerActive = true
    widget._timerElapsed = 0
    widget.bar:SetMinMaxValues(0, numericDuration)
    TimerBarWidgetOnUpdate(widget, 1)
    if widget._timerActive then widget:SetScript("OnUpdate", TimerBarWidgetOnUpdate) end
    return widget
end

-- Shared native Duration Object implementation.  Callers choose the public
-- semantic entry below: SetDurationObject for ordinary data and SetSecretTime
-- for protected data.  Both hand the object directly to Blizzard rendering.
local function TimerBarWidgetSetNativeDuration(widget, durationObject, interpolation, direction, mode, textOptions)
    if not durationObject then return TimerBarWidgetClearTime(widget) end
    if widget._timerMode and widget._timerMode ~= mode then
        ResetTimerDurationBar(widget, widget._timerMode)
        ApplyTimerBarVisual(widget)
    end
    widget._timerActive = false
    widget._timerStart = nil
    widget._timerDuration = nil
    widget._timerModRate = nil
    widget:SetScript("OnUpdate", nil)
    widget._timeTextValue = nil
    widget._timerMode = mode
    local durationBar, inactiveBar = GetTimerDurationBar(widget, mode)
    inactiveBar:Hide()
    durationBar:Show()
    if durationBar.SetTimerDuration then
        durationBar:SetTimerDuration(durationObject, interpolation or (_G.Enum and Enum.StatusBarInterpolation.None),
            direction or 0)
        -- SetTimerDuration only changes the native target.  A reused StatusBar
        -- can otherwise remain at its prior rendered value (including empty)
        -- while the same DurationObject already drives the visible number.
        -- Snap the native fill to its current target once; the C++ timer owns
        -- every following frame and no Lua duration/progress value is read.
        if durationBar.SetToTargetValue then durationBar:SetToTargetValue() end
    end
    local timeStyle = widget.textStyles and widget.textStyles.time or nil
    local showDigits = TimerStyleValue(widget.timerStyle, "showTime") ~= false
        and GetStyleValue(timeStyle, "enabled") ~= false
    if showDigits then
        -- 时间文字直接绑定同一 Duration Object；不再借隐藏 Cooldown 的倒数圈显示数字。
        widget.timeText:SetDurationBinding(durationObject, textOptions or {
            property = Enum.DurationTextBindingProperty.RemainingDuration,
        })
        widget.timeText:Show()
    else
        widget.timeText:ClearDurationBinding()
        widget.timeText:Hide()
    end
    widget.secretCountdown:Clear()
    if widget._timerDoneCallback and widget.secretCountdown and widget.secretCountdown.cooldown then
        -- 结束回调仍复用原生 Cooldown 通知，但该 Cooldown 始终隐藏、绝不显示数字/扇形。
        local cooldown = widget.secretCountdown.cooldown
        cooldown:SetHideCountdownNumbers(true)
        cooldown:SetCooldownFromDurationObject(durationObject, true)
        cooldown:Hide()
        widget.secretCountdown:Hide()
    end
    return widget
end

-- Ordinary Duration Object entry: no secret classification is implied.  This
-- is the native alternative to SetTime(start, duration), so it never owns a
-- Lua timer loop and can safely preserve an external expirationTime.
local function TimerBarWidgetSetDurationObject(widget, durationObject, interpolation, direction, textOptions)
    return TimerBarWidgetSetNativeDuration(widget, durationObject, interpolation, direction, "DURATION", textOptions)
end

-- Secret Duration entry: values remain opaque from this point onward.  The
-- native renderer implementation is intentionally shared with ordinary
-- Duration Objects; only this public semantic entry is for protected input.
local function TimerBarWidgetSetSecretTime(widget, durationObject, interpolation, direction)
    return TimerBarWidgetSetNativeDuration(widget, durationObject, interpolation, direction, "SECRET")
end

-- 普通层数：走自动测量（ClearBounds 会在下次 LayoutTimerBar 时被固定 Bounds 重新覆盖，
-- 这里只是切换内容，不需要在这两个函数里重复处理 Bounds——TimerBar 的 stackText 从创建起
-- 就固定 Bounds 为整条尺寸，不像 IconWidget 的 stackText 走自动测量/ClearBounds 那套）。
local function TimerBarWidgetSetStacks(widget, stacks)
    local text = stacks and tostring(stacks) or ""
    widget.stackText:SetText(text)
    if text ~= "" and (widget.textStyles.stacks == nil or widget.textStyles.stacks.enabled ~= false) then
        widget.stackText:Show()
    else
        widget.stackText:Hide()
    end
    return widget
end

-- Secret 层数：直传 SetSecretText，不做 nil/类型/内容判断。stackText 在 LayoutTimerBar 里
-- 已经固定了 SetBounds(barWidth, barHeight)，不会重演 IconWidget 那次"没有 Bounds 导致
-- 退化成 1x1 像素不可见"的坑（见 EXUI_组合控件规范.md 0.3.2）。
local function TimerBarWidgetSetSecretStacks(widget, secretText)
    widget.stackText:SetSecretText(secretText)
    if widget.textStyles.stacks == nil or widget.textStyles.stacks.enabled ~= false then
        widget.stackText:Show()
    else
        widget.stackText:Hide()
    end
    return widget
end

local function TimerBarWidgetSetIcon(widget, texture)
    widget.icon:SetIcon(texture)
    return widget
end

-- 标准预览需要把固定计时条本体与固定图标分别作为声明锚点，但组合 Widget 的
-- 私有 Region 不能被模块或预览组合层直接读取。这个只读公开入口只暴露标准固定
-- 元素的真实几何根，不暴露创建、样式或生命周期控制权。
local function TimerBarWidgetGetFixedElementRoot(widget, elementID)
    if elementID == "bar" then return widget.bar end
    if elementID == "icon" then return widget.icon end
    return nil
end

-- TimerBar 的渲染锚点与 Selection bounds 必须经由同一 canonical ID 解析。
-- 禁止一条路径读 core.bar、另一条路径读 bar，避免“能显示却不在编辑框内”。
local function TimerBarWidgetResolveDeclaredElement(widget, elementID)
    local id = tostring(elementID or "")
    local root = id == "core.root" and widget
        or id == "core.bar" and widget.bar
        or id == "core.icon" and widget.icon
        or id == "core.spellName" and widget.labelText
        or id == "core.targetName" and widget.textB
        or id == "core.time" and widget.timeText
        or id == "core.stacks" and widget.stackText
    if not root then error("TimerBarWidget unknown declared element: " .. id, 2) end
    return root, (widget.declaredSelectionRects or {})[id]
end

-- StandardTimerBar 的第三文字槽由该模块创建；它仍必须写入同一声明范围，
-- 不能让世界选择框或 panel hitbox 改为读取屏幕坐标。
local function TimerBarWidgetSetDeclaredTextSelection(widget, elementID, style)
    local rects = widget.declaredSelectionRects or {}
    local barRect = rects["core.bar"]
    if not barRect then return widget end
    widget.declaredSelectionRects = rects
    rects[elementID] = TranslateSelectionRect(barRect,
        NumberOr(style and style.x, 0), NumberOr(style and style.y, 0))
    return widget
end

-- Selection 只包可见字形（加少量命中 padding），不能把整条 bar 再按文字 X/Y
-- 平移；后者会令右对齐时间把世界 SelectionFrame 夸大数百像素。
local function TimerBarWidgetRefreshDeclaredTextSelections(widget)
    local rects = widget.declaredSelectionRects or {}
    local barRect = rects["core.bar"]
    if not barRect then return widget end
    local function Apply(id, textWidget)
        local metrics = textWidget and textWidget.GetVisualMetrics and textWidget:GetVisualMetrics()
        if not metrics then return end
        local width = math.max(18, (metrics.width or 1) + 8)
        local height = math.max(18, (metrics.height or 1) + 6)
        local centerX = (barRect.left + barRect.right) * 0.5 + (metrics.offsetX or 0)
        local centerY = (barRect.bottom + barRect.top) * 0.5 + (metrics.offsetY or 0)
        local justifyH = tostring(metrics.justifyH or "LEFT"):upper()
        local justifyV = tostring(metrics.justifyV or "MIDDLE"):upper()
        if justifyH == "LEFT" then centerX = barRect.left + width * 0.5 + (metrics.offsetX or 0)
        elseif justifyH == "RIGHT" then centerX = barRect.right - width * 0.5 + (metrics.offsetX or 0) end
        if justifyV == "TOP" then centerY = barRect.top - height * 0.5 + (metrics.offsetY or 0)
        elseif justifyV == "BOTTOM" then centerY = barRect.bottom + height * 0.5 + (metrics.offsetY or 0) end
        rects[id] = NewSelectionRect(centerX - width * 0.5, centerX + width * 0.5,
            centerY - height * 0.5, centerY + height * 0.5)
    end
    Apply("core.spellName", widget.labelText)
    Apply("core.targetName", widget.textB)
    Apply("core.time", widget.timeText)
    return widget
end

-- ExtraChildHost 是组合控件提供给模块的唯一额外内容锚点。Core 只管理
-- id、相对固定 Body 的位置、bounds 与生命周期；Host 内显示 Atlas、团队标记
-- 或其它内容完全由模块负责。它绝不能参与 TimerBarWidget 的尺寸计算。
local function TimerBarWidgetGetExtraChildHost(widget, id)
    return type(widget.extraChildHosts) == "table" and widget.extraChildHosts[id] or nil
end

local function TimerBarWidgetGetDeclaredSelectionBounds(widget)
    local rects = widget.declaredSelectionRects or {}
    local bounds = nil
    for _, rect in pairs(rects) do
        bounds = UnionSelectionRect(bounds, rect)
    end
    for _, host in pairs(widget.extraChildHosts or {}) do
        if host.__exwindDeclaredSelectionRect then
            bounds = UnionSelectionRect(bounds, host.__exwindDeclaredSelectionRect)
        end
    end
    return bounds
end

local function TimerBarWidgetConfigureExtraChildHost(widget, id, spec)
    if type(id) ~= "string" or id == "" then error("TimerBarWidget extra child id must be non-empty string", 2) end
    if type(spec) ~= "table" then error("TimerBarWidget extra child spec must be table", 2) end
    local anchor = type(spec.anchor) == "table" and spec.anchor or spec
    local relativeID = anchor.relativeElement or "core.bar"
    local relative, relativeRect = TimerBarWidgetResolveDeclaredElement(widget, relativeID)

    widget.extraChildHosts = widget.extraChildHosts or {}
    local host = widget.extraChildHosts[id]
    if not host then
        host = CreateFrame("Frame", nil, widget)
        host:EnableMouse(false)
        EXUI:ApplyVisualLayer(host, _G.EXBORDERFRAME, widget)
        widget.extraChildHosts[id] = host
    end

    local width = math.max(1, NumberOr(spec.width, 1))
    local height = math.max(1, NumberOr(spec.height, 1))
    host:SetSize(width, height)
    host:ClearAllPoints()
    host:SetPoint(anchor.point or "CENTER", relative, anchor.relativePoint or anchor.point or "CENTER",
        NumberOr(anchor.x, 0), NumberOr(anchor.y, 0))
    local shown = spec.shown ~= false
    host:SetShown(shown)
    -- ExtraChildHost 的范围由同一 anchor/width/height 声明计算；其内所有
    -- ExtraTextureWidget 都归属这块正式范围，不需要编辑模式扫描材质。
    host.__exwindDeclaredSelectionRect = shown and BuildAnchoredSelectionRect(
        relativeRect, anchor, width, height
    ) or nil
    return host
end

local function TimerBarWidgetResetExtraChildHosts(widget)
    for _, host in pairs(widget.extraChildHosts or {}) do
        host:Hide()
        host:ClearAllPoints()
        host:SetSize(1, 1)
        host.__exwindDeclaredSelectionRect = nil
    end
end

local function TimerBarWidgetSetSecretIcon(widget, texture)
    widget.icon:SetSecretIcon(texture)
    return widget
end

local function TimerBarWidgetSetLabel(widget, text)
    local hasText = TextWidgetSetDisplayText(widget.labelText, text)
    if hasText and (widget.textStyles.label == nil or widget.textStyles.label.enabled ~= false) then
        widget.labelText:Show()
    else
        widget.labelText:Hide()
    end
    return widget
end

local function TimerBarWidgetSetMarkers(widget, markers)
    ApplyTimerMarkers(widget, markers)
    return widget
end

-- 提示图标属于计时条 RuntimeWidget 的正式视觉层。visuals 由业务模块把 iconFlags
-- 解析后传入；EXUI 不认识业务位标志，也不在预览页复制业务 Atlas 映射。
local function TimerBarWidgetSetAlertIcons(widget, visuals, config)
    if not widget.alertLayer then return widget end
    visuals = type(visuals) == "table" and visuals or {}
    widget._alertVisuals = visuals

    local cfg = type(config) == "table" and config or {}
    local enabled = cfg.showIcon ~= false
    local baseSize = math.max(6, NumberOr(cfg.size, 16))
    local baseWidth = math.max(6, NumberOr(cfg.width, baseSize))
    local baseHeight = math.max(6, NumberOr(cfg.height, baseSize))
    local vertical = tostring(cfg.layout or "HORIZONTAL"):upper() == "VERTICAL"
    local width = (vertical and #visuals > 1) and math.max(4, math.floor(baseWidth / 2)) or baseWidth
    local height = (vertical and #visuals > 1) and math.max(4, math.floor(baseHeight / 2)) or baseHeight
    local ox, oy = NumberOr(cfg.x, 0), NumberOr(cfg.y, 0)
    local anchorMode = tostring(cfg.anchor or "OUTSIDE_LEFT"):upper()

    widget.alertIcons = widget.alertIcons or {}
    while #widget.alertIcons < #visuals do
        local icon = EXUI:CreateVisualTexture(widget.alertLayer, _G.EXBORDERFRAME)
        icon:Hide()
        widget.alertIcons[#widget.alertIcons + 1] = icon
    end

    local first = nil
    for index, icon in ipairs(widget.alertIcons) do
        local visual = visuals[index]
        if visual and enabled then
            icon:ClearAllPoints()
            icon:SetSize(width, height)
            if index == 1 then
                local base = (widget.icon and widget.icon:IsShown()) and widget.icon or widget.bar or widget
                if anchorMode == "TEXT_BEFORE" then
                    base = widget.labelText or base
                    icon:SetPoint("RIGHT", base, "LEFT", ox, oy)
                elseif anchorMode == "TEXT_AFTER" then
                    base = widget.labelText or base
                    icon:SetPoint("LEFT", base, "RIGHT", ox, oy)
                else
                    icon:SetPoint("RIGHT", base, "LEFT", ox, oy)
                end
            elseif vertical then
                icon:SetPoint("TOP", widget.alertIcons[index - 1], "BOTTOM", 0, -2)
            elseif anchorMode == "TEXT_AFTER" then
                icon:SetPoint("LEFT", widget.alertIcons[index - 1], "RIGHT", 2, 0)
            else
                icon:SetPoint("RIGHT", widget.alertIcons[index - 1], "LEFT", -2, 0)
            end

            if visual.atlas then
                icon:SetTexture(nil)
                icon:SetTexCoord(0, 1, 0, 1)
                icon:SetAtlas(visual.atlas, false)
            else
                icon:SetAtlas(nil)
                icon:SetTexture(visual.file)
                icon:SetTexCoord(visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1)
            end
            icon:Show()
            if not first then first = icon end
        else
            icon:Hide()
        end
    end
    widget._lastAlertIcon = first
    return widget
end

-- Slider Panel Patch 只能整理已经物化的提示图标；这里故意不调用
-- TimerBarWidgetSetAlertIcons，后者会在数量不足时创建 Region，不能进入拖动期。
local function PatchExistingTimerBarAlertIcons(widget)
    local cfg = widget.timerStyle and widget.timerStyle.alertIcons
    local visuals = widget._alertVisuals
    if type(cfg) ~= "table" or type(visuals) ~= "table" or type(widget.alertIcons) ~= "table" then return false end
    if #widget.alertIcons < #visuals then return false end

    local enabled = cfg.showIcon ~= false
    local baseSize = math.max(6, NumberOr(cfg.size, 16))
    local baseWidth = math.max(6, NumberOr(cfg.width, baseSize))
    local baseHeight = math.max(6, NumberOr(cfg.height, baseSize))
    local vertical = tostring(cfg.layout or "HORIZONTAL"):upper() == "VERTICAL"
    local width = (vertical and #visuals > 1) and math.max(4, math.floor(baseWidth / 2)) or baseWidth
    local height = (vertical and #visuals > 1) and math.max(4, math.floor(baseHeight / 2)) or baseHeight
    local ox, oy = NumberOr(cfg.x, 0), NumberOr(cfg.y, 0)
    local anchorMode = tostring(cfg.anchor or "OUTSIDE_LEFT"):upper()

    for index, icon in ipairs(widget.alertIcons) do
        local visual = visuals[index]
        if visual and enabled then
            icon:ClearAllPoints()
            icon:SetSize(width, height)
            if index == 1 then
                local base = (widget.icon and widget.icon:IsShown()) and widget.icon or widget.bar or widget
                if anchorMode == "TEXT_BEFORE" then
                    base = widget.labelText or base
                    icon:SetPoint("RIGHT", base, "LEFT", ox, oy)
                elseif anchorMode == "TEXT_AFTER" then
                    base = widget.labelText or base
                    icon:SetPoint("LEFT", base, "RIGHT", ox, oy)
                else
                    icon:SetPoint("RIGHT", base, "LEFT", ox, oy)
                end
            elseif vertical then
                icon:SetPoint("TOP", widget.alertIcons[index - 1], "BOTTOM", 0, -2)
            elseif anchorMode == "TEXT_AFTER" then
                icon:SetPoint("LEFT", widget.alertIcons[index - 1], "RIGHT", 2, 0)
            else
                icon:SetPoint("RIGHT", widget.alertIcons[index - 1], "LEFT", -2, 0)
            end
        end
    end
    return true
end

-- RegionElements may render a TimerBar inside a pure declared viewport.  The
-- DB style remains the only persistent style table; this is per-presentation
-- geometry (for example a clipped comparison scale), never a style copy.
local function TimerBarWidgetSetGeometryOverride(widget, geometry)
    if geometry ~= nil and type(geometry) ~= "table" then error("TimerBarWidget geometry override must be table or nil", 2) end
    widget._geometryOverride = geometry
    if widget.timerStyle then LayoutTimerBar(widget) end
    return widget
end

local function TimerBarWidgetSetPresentationOptions(widget, options)
    if options ~= nil and type(options) ~= "table" then error("TimerBarWidget presentation options must be table or nil", 2) end
    widget._presentationOptions = options
    if widget.timerStyle then LayoutTimerBar(widget) end
    return widget
end

local function TimerBarWidgetSetFillVisible(widget, visible)
    widget._fillVisibleOverride = visible ~= false
    local shown = widget._fillVisibleOverride
    if widget._timerMode == "SECRET" then
        widget.secretBar:SetShown(shown)
        widget.bar:Hide()
    else
        widget.bar:SetShown(shown)
        widget.secretBar:Hide()
    end
    return widget
end

-- 模块业务装饰的公开承载入口。EXUI 只提供层级与生命周期，不解释团队标记、
-- Secret 数据或任何模块业务含义；模块只能通过此 API 取得允许扩展的宿主。
local function TimerBarWidgetGetExtensionHost(widget, slot)
    if slot == "leftDecorations" then
        return widget.leftDecorationsLayer
    end
    return nil
end

local function TimerBarWidgetSetAnchor(widget, point, relativeTo, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point or "CENTER", relativeTo or widget:GetParent() or UIParent, relativePoint or point or "CENTER", x or 0, y or 0)
    return widget
end

-- 组合 Widget 的子对象会随父 Widget 一并归还。父对象尚被旧引用持有时，禁止再把
-- 已归还的 IconWidget / TextWidget 当作可用对象套样式；调用方可据此丢弃旧引用并重新借用。
local function TimerBarWidgetIsUsable(widget)
    return widget ~= nil
        and widget._released ~= true
        and widget.icon ~= nil
        and widget.icon._released ~= true
        and widget.icon.countdownText ~= nil
        and widget.labelText ~= nil
        and widget.timeText ~= nil
        and widget.stackText ~= nil
        and widget.secretCountdown ~= nil
        and widget.alertLayer ~= nil
        and widget.leftDecorationsLayer ~= nil
end

local function TimerBarWidgetApplyStyle(widget, style)
    if not TimerBarWidgetIsUsable(widget) then return widget end
    widget.style = style or {}
    widget.timerStyle = ResolveTimerStyle(widget.style)
    widget.textStyles = type(widget.style.text) == "table" and widget.style.text or {}
    widget.countdownFormat = widget.style.countdownFormat or widget.timerStyle.countdownFormat or widget.countdownFormat

    -- 文字必须始终高于边框；图标、条体与填充只占用底层。业务 Atlas/团队标记
    -- 作为边框级装饰，不能盖住名称或时间。
    EXUI:ApplyVisualLayer(widget.bar, _G.EXFILLFRAME, widget)
    EXUI:ApplyVisualLayer(widget.secretBar, _G.EXFILLFRAME, widget)
    EXUI:ApplyVisualLayer(widget.icon, _G.EXBASEFRAME, widget)
    EXUI:ApplyVisualLayer(widget.border, _G.EXBORDERFRAME, widget)
    EXUI:ApplyVisualLayer(widget.markerLayer, _G.EXBORDERFRAME, widget)
    EXUI:ApplyVisualLayer(widget.textLayer, _G.EXFONTFRAME, widget)
    EXUI:ApplyVisualLayer(widget.leftDecorationsLayer, _G.EXBORDERFRAME, widget)
    EXUI:ApplyVisualLayer(widget.alertLayer, _G.EXBORDERFRAME, widget)

    -- 浅复制：不能为了“计时条图标不倒数”而改写模块的持久化外观配置。
    local iconAppearance = {}
    if type(widget.style.iconAppearance) == "table" then
        for key, value in pairs(widget.style.iconAppearance) do
            iconAppearance[key] = value
        end
    end
    -- TimerBar 的图标 body 尺寸属于 timerStyle。若只传边框外观，IconWidget
    -- 会在完整重套时回退到自己的 64x64 默认值，导致边框短暂或持续大于图标。
    iconAppearance.width = TimerStyleValue(widget.timerStyle, "iconWidth")
    iconAppearance.height = TimerStyleValue(widget.timerStyle, "iconHeight")
    iconAppearance.showCooldown = false -- 计时条图标固定为纯显示，倒数只走 TimeText。
    iconAppearance.showBorder = TimerStyleValue(widget.timerStyle, "showIconBorder") ~= false
    iconAppearance.borderTexture = TimerStyleValue(widget.timerStyle, "iconBorderTexture")
    iconAppearance.borderSize = TimerStyleValue(widget.timerStyle, "iconBorderSize")
    iconAppearance.borderPadding = TimerStyleValue(widget.timerStyle, "iconBorderPadding")
    iconAppearance.borderColorR = TimerStyleValue(widget.timerStyle, "iconBorderColorR")
    iconAppearance.borderColorG = TimerStyleValue(widget.timerStyle, "iconBorderColorG")
    iconAppearance.borderColorB = TimerStyleValue(widget.timerStyle, "iconBorderColorB")
    iconAppearance.borderColorA = TimerStyleValue(widget.timerStyle, "iconBorderColorA")
    widget.icon:ApplyStyle({ icon = iconAppearance })
    widget.labelText:ApplyStyle(widget.textStyles.label or DEFAULT_TIMER_LABEL_STYLE)
    widget.timeText:ApplyStyle(widget.textStyles.time or DEFAULT_TIMER_TIME_STYLE)
    widget.secretCountdown:ApplyStyle(widget.textStyles.time or DEFAULT_TIMER_TIME_STYLE)
    widget.stackText:ApplyStyle(widget.textStyles.stacks or DEFAULT_TIMER_STACK_STYLE)

    LayoutTimerBar(widget)
    ApplyTimerBarVisual(widget)
    ApplyTimerMarkers(widget, TimerStyleValue(widget.timerStyle, "showMarkers") == true and widget.style.markers or {})
    TimerBarWidgetSetAlertIcons(widget, widget._alertVisuals, TimerStyleValue(widget.timerStyle, "alertIcons"))

    if widget._timerActive then
        TimerBarWidgetOnUpdate(widget, 1)
    end
    return widget
end

local function TimerBarWidgetRelease(widget)
    if widget._released then return end
    widget._released = true
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: release begin") end
    -- secretBar 是 TimerBar 内唯一直接绑定 Duration Object 的 StatusBar。先用原生
    -- SetToDefaults 清掉其 Secret 状态，再处理普通数值条和其余子控件。
    widget.secretBar:SetToDefaults()
    TimerBarWidgetClearTime(widget)
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: ClearTime released") end
    widget.icon:Release()
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: icon released") end
    widget.labelText:Release()
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: label released") end
    widget.timeText:Release()
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: time released") end
    widget.stackText:Release()
    widget.secretCountdown:Release()
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: secret countdown released") end
    for _, icon in ipairs(widget.alertIcons or {}) do icon:Hide() end
    widget.icon = nil
    widget.labelText = nil
    widget.timeText = nil
    widget.stackText = nil
    widget.secretCountdown = nil
    for _, marker in ipairs(widget.markers) do
        marker.track:Hide()
        marker.line:Hide()
    end
    widget.markerData = nil
    widget.style = nil
    widget.timerStyle = nil
    widget.textStyles = nil
    widget.countdownFormat = nil
    widget._alertVisuals = nil
    widget._lastAlertIcon = nil
    widget._timerMode = nil
    widget._geometryOverride = nil
    widget._presentationOptions = nil
    widget._fillVisibleOverride = nil
    TimerBarWidgetResetExtraChildHosts(widget)
    widget.leftDecorationsLayer:Hide()
    widget.secretBar:Hide()
    widget:Hide()
    widget:ClearAllPoints()
    if widget._mythicReleaseTrace then _G.print("[MythicCast Release] " .. (widget._mythicReleaseTraceUnit or "?") .. " | timer: pooled") end
    widget._mythicReleaseTrace = nil
    widget._mythicReleaseTraceUnit = nil
    EXFactory:Release(TIMER_BAR_WIDGET_POOL, widget)
end

EXFactory:InitPool(TIMER_BAR_WIDGET_POOL, "Frame", nil, function(widget)
    widget.root = widget
    widget:SetSize(240, 24)
    widget:EnableMouse(false)
    widget.markers = {}
    widget.alertIcons = {}
    widget.extraChildHosts = {}

    local bar = CreateFrame("StatusBar", nil, widget)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(false)
    EXUI:ApplyVisualLayer(bar, _G.EXFILLFRAME, widget)
    widget.bar = bar

    -- 原生秘密计时使用独立 StatusBar。它一旦接收 Duration Object，之后不再进入
    -- SetValue / SetMinMaxValues 等 Lua 数值路径；普通进度和预览始终使用 widget.bar。
    local secretBar = CreateFrame("StatusBar", nil, widget)
    secretBar:SetAllPoints(bar)
    secretBar:EnableMouse(false)
    secretBar:Hide()
    EXUI:ApplyVisualLayer(secretBar, _G.EXFILLFRAME, widget)
    widget.secretBar = secretBar

    local background = EXUI:CreateVisualTexture(widget, _G.EXBACKGROUNDFRAME)
    widget.background = background

    local border = CreateFrame("Frame", nil, widget, "BackdropTemplate")
    border:EnableMouse(false)
    EXUI:ApplyVisualLayer(border, _G.EXBORDERFRAME, widget)
    widget.border = border

    -- The bar is the actual geometry owner of the TimerBar Backdrop. Its size
    -- changes independently from the outer widget when an external icon is
    -- included, so reapply against the border frame's own effective scale.
    bar:HookScript("OnSizeChanged", function()
        if widget.timerStyle and widget.border:IsShown() then
            ApplyTimerBarBorder(widget)
        end
    end)
    local markerLayer = CreateFrame("Frame", nil, widget)
    markerLayer:EnableMouse(false)
    EXUI:ApplyVisualLayer(markerLayer, _G.EXBORDERFRAME, widget)
    widget.markerLayer = markerLayer

    local textLayer = CreateFrame("Frame", nil, widget)
    textLayer:EnableMouse(false)
    EXUI:ApplyVisualLayer(textLayer, _G.EXFONTFRAME, widget)
    widget.textLayer = textLayer

    -- 模块业务装饰的唯一公开宿主。它独立于 EXUI 的 alertLayer，避免团队标记、
    -- Secret 值驱动的 Atlas 等业务 Texture 进入 EXUI 内置警报图标的数据路径。
    local leftDecorationsLayer = CreateFrame("Frame", nil, widget)
    leftDecorationsLayer:EnableMouse(false)
    EXUI:ApplyVisualLayer(leftDecorationsLayer, _G.EXBORDERFRAME, widget)
    widget.leftDecorationsLayer = leftDecorationsLayer

    local alertLayer = CreateFrame("Frame", nil, widget)
    alertLayer:EnableMouse(false)
    EXUI:ApplyVisualLayer(alertLayer, _G.EXBORDERFRAME, widget)
    widget.alertLayer = alertLayer

    widget.SetProgress = TimerBarWidgetSetProgress
    widget.SetSecretProgress = TimerBarWidgetSetSecretProgress
    widget.SetFillColor = TimerBarWidgetSetFillColor
    widget.SetFillColorFromBoolean = TimerBarWidgetSetFillColorFromBoolean
    widget.SetTime = TimerBarWidgetSetTime
    widget.SetDurationObject = TimerBarWidgetSetDurationObject
    widget.SetSecretTime = TimerBarWidgetSetSecretTime
    widget.SetTimerDoneCallback = TimerBarWidgetSetTimerDoneCallback
    widget.ClearTime = TimerBarWidgetClearTime
    widget.SetIcon = TimerBarWidgetSetIcon
    widget.SetSecretIcon = TimerBarWidgetSetSecretIcon
    widget.GetFixedElementRoot = TimerBarWidgetGetFixedElementRoot
    widget.ResolveDeclaredElement = TimerBarWidgetResolveDeclaredElement
    widget.SetDeclaredTextSelection = TimerBarWidgetSetDeclaredTextSelection
    widget.RefreshDeclaredTextSelections = TimerBarWidgetRefreshDeclaredTextSelections
    widget.GetExtraChildHost = TimerBarWidgetGetExtraChildHost
    widget.GetDeclaredSelectionBounds = TimerBarWidgetGetDeclaredSelectionBounds
    widget.ConfigureExtraChildHost = TimerBarWidgetConfigureExtraChildHost
    widget.SetLabel = TimerBarWidgetSetLabel
    widget.SetStacks = TimerBarWidgetSetStacks
    widget.SetSecretStacks = TimerBarWidgetSetSecretStacks
    widget.SetMarkers = TimerBarWidgetSetMarkers
    widget.SetAlertIcons = TimerBarWidgetSetAlertIcons
    widget.SetGeometryOverride = TimerBarWidgetSetGeometryOverride
    widget.SetPresentationOptions = TimerBarWidgetSetPresentationOptions
    widget.SetFillVisible = TimerBarWidgetSetFillVisible
    widget.GetExtensionHost = TimerBarWidgetGetExtensionHost
    widget.SetAnchor = TimerBarWidgetSetAnchor
    widget.IsUsable = TimerBarWidgetIsUsable
    widget.ApplyStyle = TimerBarWidgetApplyStyle
    widget.Release = TimerBarWidgetRelease
end)

-- 初版 TimerBarWidget：横向条，默认含纯显示图标；不会在图标上显示第二套倒数。
function EXUI:CreateTimerBarWidget(parent, style)
    local widget = EXFactory:Acquire(TIMER_BAR_WIDGET_POOL, parent)
    widget._released = false
    widget.leftDecorationsLayer:Show()
    widget.icon = EXUI:CreateIconWidget(widget)
    widget.labelText = EXUI:CreateTextWidget(widget.textLayer, "label")
    widget.timeText = EXUI:CreateTextWidget(widget.textLayer, "time")
    widget.stackText = EXUI:CreateTextWidget(widget.textLayer, "stacks")
    widget.secretCountdown = EXUI:CreateSecretCountdownWidget(widget.textLayer)
    widget:ApplyStyle(style or DEFAULT_TIMER_BAR_STYLE)
    widget._geometryOverride = nil
    widget._presentationOptions = nil
    widget._fillVisibleOverride = nil
    widget:ClearTime()
    widget:SetLabel(nil)
    widget:SetStacks(nil)
    return widget
end

-- =========================================================
-- AuraButtonAdapter：12.x AuraContainer 的绑定适配层
-- AuraButton 持有 Aura 数据与 Secret Value；此对象只交付视觉 Region，
-- 绝不读取、转换、比较 Aura 数据，也绝不建立自己的倒数 OnUpdate。
-- =========================================================
function EXUI:CreateAuraButtonAdapter(auraFrame)
    local adapter = { auraFrame = auraFrame }

    local function Bind(self, method, region, options)
        self.auraFrame[method](self.auraFrame, region, options)
        return self
    end

    local function Clear(self, method)
        local clearMethod = self.auraFrame[method]
        if clearMethod then
            clearMethod(self.auraFrame)
        end
        return self
    end

    function adapter:BindIcon(texture)
        return Bind(self, "SetIcon", texture)
    end

    function adapter:ClearIcon()
        return Clear(self, "ClearIcon")
    end

    function adapter:BindDurationCooldown(cooldown)
        return Bind(self, "SetDurationCooldown", cooldown)
    end

    function adapter:ClearDurationCooldown()
        return Clear(self, "ClearDurationCooldown")
    end

    function adapter:BindApplicationCount(fontString)
        return Bind(self, "SetApplicationCount", fontString)
    end

    function adapter:ClearApplicationCount()
        return Clear(self, "ClearApplicationCount")
    end

    function adapter:BindApplicationBar(statusBar, options)
        return Bind(self, "SetApplicationBar", statusBar, options)
    end

    function adapter:ClearApplicationBar()
        return Clear(self, "ClearApplicationBar")
    end

    function adapter:BindDurationText(fontString, options)
        return Bind(self, "SetDurationText", fontString, options)
    end

    function adapter:ClearDurationText()
        return Clear(self, "ClearDurationText")
    end

    function adapter:BindSpellName(fontString)
        return Bind(self, "SetSpellName", fontString)
    end

    function adapter:ClearSpellName()
        return Clear(self, "ClearSpellName")
    end

    function adapter:BindDurationBar(statusBar, options)
        return Bind(self, "SetDurationBar", statusBar, options)
    end

    function adapter:ClearDurationBar()
        return Clear(self, "ClearDurationBar")
    end

    function adapter:BindAuraBorder(texture, options)
        return Bind(self, "SetAuraBorder", texture, options)
    end

    function adapter:ClearAuraBorder()
        return Clear(self, "ClearAuraBorder")
    end

    return adapter
end
