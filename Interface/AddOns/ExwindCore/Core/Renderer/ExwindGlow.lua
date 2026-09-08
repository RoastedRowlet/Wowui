-- =========================================================
-- ExwindGlow.lua
-- Core 级原生发光引擎：取代 LibCustomGlow 的运行时职责。
-- 设计约束：不读取宿主 GetWidth/GetHeight/IsShown；调用方传入已知普通尺寸。
-- =========================================================

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local GLOW_WIDGET_POOL = "RuntimeGlowWidget"
local EDGE_ORDER = { "top", "right", "bottom", "left" }
local MAX_EDGE_TRAINS = 36

local DEFAULT_STYLE = {
    enabled = true,
    style = "EDGE_FLOW",
    width = 40,
    height = 40,
    offset = 3,
    frequency = 1,
    particles = 1, -- EDGE_FLOW 同时环绕的线条数量
    length = 32,
    thickness = 2,
    direction = "CLOCKWISE",
    scale = 1,
    r = 1, g = 0.82, b = 0.20, a = 1,
}

local LEGACY_STYLE_MAP = {
    ["Action Button Glow"] = "PULSE",
    ["Pixel Glow"] = "EDGE_FLOW",
    ["Autocast Shine"] = "EDGE_FLOW",
    ["Proc Glow"] = "PROC_FLIPBOOK",
    ["Proc Alt Glow"] = "PROC_FLIPBOOK",
}

local function NumberOr(value, fallback)
    local number = tonumber(value)
    return number or fallback
end

local function StyleValue(style, key)
    local value = style and style[key]
    if value == nil then value = DEFAULT_STYLE[key] end
    return value
end

local function NormalizeStyleName(value)
    local style = tostring(value or DEFAULT_STYLE.style):upper():gsub("%s+", "_")
    if LEGACY_STYLE_MAP[value] then return LEGACY_STYLE_MAP[value] end
    if style == "PERIMETER_TRAIL" then return "EDGE_FLOW" end -- 0713 初版 Path 点状样式的兼容名
    if style == "PULSE" or style == "EDGE_FLOW" or style == "PROC_FLIPBOOK" then
        return style
    end
    return DEFAULT_STYLE.style
end

local function StopGroup(group)
    if group and group.Stop then group:Stop() end
end

local function HideAllVisuals(widget)
    StopGroup(widget.pulseGroup)
    StopGroup(widget.procStartGroup)
    StopGroup(widget.procLoopGroup)
    widget.pulseTexture:Hide()
    widget.procStart:Hide()
    widget.procLoop:Hide()
    for _, train in ipairs(widget.edgeTrains) do
        for _, edge in pairs(train) do
            StopGroup(edge.group)
            edge:Hide()
        end
    end
end

local function StopGlowWidget(widget)
    if not widget then return end
    HideAllVisuals(widget)
    widget._isShown = false
    widget:Hide()
end

local function ConfigurePulse(widget, style)
    local width = NumberOr(StyleValue(style, "width"), 40)
    local height = NumberOr(StyleValue(style, "height"), width)
    local offset = NumberOr(StyleValue(style, "offset"), 0)
    local scale = math.max(0.25, NumberOr(StyleValue(style, "scale"), 1))
    local frequency = math.max(0.1, NumberOr(StyleValue(style, "frequency"), 1))
    local areaWidth = math.max(1, width + offset * 2)
    local areaHeight = math.max(1, height + offset * 2)
    local durationIn = 0.35 / frequency
    local durationOut = 0.65 / frequency

    local tex = widget.pulseTexture
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", widget, "CENTER")
    tex:SetSize(areaWidth * 1.55 * scale, areaHeight * 1.55 * scale)
    tex:SetVertexColor(StyleValue(style, "r"), StyleValue(style, "g"), StyleValue(style, "b"), StyleValue(style, "a"))
    tex:Show()

    widget.pulseIn:SetDuration(durationIn)
    widget.pulseOut:SetDuration(durationOut)
    widget.pulseScaleUp:SetDuration(durationIn)
    widget.pulseScaleDown:SetDuration(durationOut)
    widget.pulseGroup:Stop()
    widget.pulseGroup:Play()
end

local function ConfigureEdgeFlow(widget, style)
    local width = math.max(1, NumberOr(StyleValue(style, "width"), 40))
    local height = math.max(1, NumberOr(StyleValue(style, "height"), width))
    -- offset 是有方向的：正值向外扩，负值向内收。这里绝不能取绝对值。
    local offset = NumberOr(StyleValue(style, "offset"), 0)
    local scale = math.max(0.25, NumberOr(StyleValue(style, "scale"), 1))
    local frequency = math.max(0.1, NumberOr(StyleValue(style, "frequency"), 1))
    local areaWidth = math.max(1, width + offset * 2)
    local areaHeight = math.max(1, height + offset * 2)
    local totalDuration = 1 / frequency
    local perimeter = math.max(1, (areaWidth + areaHeight) * 2)
    local lineCount = math.max(1, math.min(MAX_EDGE_TRAINS, math.floor(NumberOr(StyleValue(style, "particles"), 1))))
    local lineLength = math.max(8, NumberOr(StyleValue(style, "length"), 32)) * scale
    local coreThickness = math.max(1, NumberOr(StyleValue(style, "thickness"), 2) * scale)
    local colorR, colorG, colorB = StyleValue(style, "r"), StyleValue(style, "g"), StyleValue(style, "b")
    local colorA = NumberOr(StyleValue(style, "a"), 1)
    local direction = tostring(StyleValue(style, "direction") or "CLOCKWISE"):upper()

    local clockwise = {
        top = { length = areaWidth, delayDistance = 0, dx = areaWidth + lineLength * 2, dy = 0, horizontal = true, point = "LEFT", relative = "TOPLEFT", x = -lineLength, y = 0 },
        right = { length = areaHeight, delayDistance = areaWidth, dx = 0, dy = -(areaHeight + lineLength * 2), horizontal = false, point = "TOP", relative = "TOPRIGHT", x = 0, y = lineLength },
        bottom = { length = areaWidth, delayDistance = areaWidth + areaHeight, dx = -(areaWidth + lineLength * 2), dy = 0, horizontal = true, point = "RIGHT", relative = "BOTTOMRIGHT", x = lineLength, y = 0 },
        left = { length = areaHeight, delayDistance = areaWidth * 2 + areaHeight, dx = 0, dy = areaHeight + lineLength * 2, horizontal = false, point = "BOTTOM", relative = "BOTTOMLEFT", x = 0, y = -lineLength },
    }
    local counterClockwise = {
        top = { length = areaWidth, delayDistance = 0, dx = -(areaWidth + lineLength * 2), dy = 0, horizontal = true, point = "RIGHT", relative = "TOPRIGHT", x = lineLength, y = 0 },
        left = { length = areaHeight, delayDistance = areaWidth, dx = 0, dy = -(areaHeight + lineLength * 2), horizontal = false, point = "TOP", relative = "TOPLEFT", x = 0, y = lineLength },
        bottom = { length = areaWidth, delayDistance = areaWidth + areaHeight, dx = areaWidth + lineLength * 2, dy = 0, horizontal = true, point = "LEFT", relative = "BOTTOMLEFT", x = -lineLength, y = 0 },
        right = { length = areaHeight, delayDistance = areaWidth * 2 + areaHeight, dx = 0, dy = areaHeight + lineLength * 2, horizontal = false, point = "BOTTOM", relative = "BOTTOMRIGHT", x = 0, y = -lineLength },
    }
    local edgeConfig = direction == "COUNTERCLOCKWISE" and counterClockwise or clockwise

    for trainIndex, train in ipairs(widget.edgeTrains) do
        local trainPhase = totalDuration * ((trainIndex - 1) / lineCount)
        for _, edgeName in ipairs(EDGE_ORDER) do
            local edge = train[edgeName]
            local cfg = edgeConfig[edgeName]
            local travelDuration = math.max(0.06, totalDuration * (cfg.length / perimeter))
            local startDelay = totalDuration * (cfg.delayDistance / perimeter)
            local endDelay = math.max(0, totalDuration - startDelay - travelDuration)

            edge:ClearAllPoints()
            if trainIndex <= lineCount then
                if cfg.horizontal then
                    edge:SetSize(lineLength, coreThickness)
                else
                    edge:SetSize(coreThickness, lineLength)
                end
                edge:SetPoint(cfg.point, widget.flowClip, cfg.relative, cfg.x, cfg.y)
                edge.core:SetVertexColor(colorR, colorG, colorB, colorA)
                if cfg.horizontal then
                    edge.core:SetHeight(coreThickness)
                else
                    edge.core:SetWidth(coreThickness)
                end
                edge:Show()

                edge.group:Stop()
                edge.group:RemoveAnimations()
                edge.group:SetLooping("REPEAT")
                local translation = edge.group:CreateAnimation("Translation")
                translation:SetOrder(1)
                translation:SetStartDelay(startDelay)
                translation:SetEndDelay(endDelay)
                translation:SetDuration(travelDuration)
                translation:SetSmoothing("NONE")
                translation:SetOffset(cfg.dx, cfg.dy)
                edge.group:Play(false, trainPhase)
            else
                edge:Hide()
            end
        end
    end
end

local function ConfigureProcFlipbook(widget, style)
    local width = NumberOr(StyleValue(style, "width"), 40)
    local height = NumberOr(StyleValue(style, "height"), width)
    local offset = NumberOr(StyleValue(style, "offset"), 0)
    local scale = math.max(0.25, NumberOr(StyleValue(style, "scale"), 1))
    local frequency = math.max(0.1, NumberOr(StyleValue(style, "frequency"), 1))
    local areaWidth = math.max(1, width + offset * 2)
    local areaHeight = math.max(1, height + offset * 2)
    local colorR, colorG, colorB, colorA = StyleValue(style, "r"), StyleValue(style, "g"), StyleValue(style, "b"), StyleValue(style, "a")

    local loopSizeW = areaWidth * 1.4 * scale
    local loopSizeH = areaHeight * 1.4 * scale
    local startSizeW = areaWidth * (150 / 42 / 1.4) * scale
    local startSizeH = areaHeight * (150 / 42 / 1.4) * scale

    widget.procStart:ClearAllPoints()
    widget.procStart:SetPoint("CENTER", widget, "CENTER")
    widget.procStart:SetSize(startSizeW, startSizeH)
    widget.procStart:SetVertexColor(colorR, colorG, colorB, colorA)
    widget.procLoop:ClearAllPoints()
    widget.procLoop:SetPoint("CENTER", widget, "CENTER")
    widget.procLoop:SetSize(loopSizeW, loopSizeH)
    widget.procLoop:SetVertexColor(colorR, colorG, colorB, colorA)

    widget.procStartFlip:SetFlipBookRows(6)
    widget.procStartFlip:SetFlipBookColumns(5)
    widget.procStartFlip:SetFlipBookFrames(30)
    widget.procStartFlip:SetFlipBookFrameWidth(0)
    widget.procStartFlip:SetFlipBookFrameHeight(0)
    widget.procStartFlip:SetDuration(0.7 / frequency)

    widget.procLoopFlip:SetFlipBookRows(6)
    widget.procLoopFlip:SetFlipBookColumns(5)
    widget.procLoopFlip:SetFlipBookFrames(30)
    widget.procLoopFlip:SetFlipBookFrameWidth(0)
    widget.procLoopFlip:SetFlipBookFrameHeight(0)
    widget.procLoopFlip:SetDuration(1 / frequency)

    widget.procLoopGroup:Stop()
    widget.procStartGroup:Stop()
    widget.procLoop:Hide()
    widget.procStart:Show()
    widget.procStartGroup:Play()
end

local function ApplyGlowStyle(widget, style)
    widget.style = style or DEFAULT_STYLE
    local width = math.max(1, NumberOr(StyleValue(widget.style, "width"), 40))
    local height = math.max(1, NumberOr(StyleValue(widget.style, "height"), width))
    local offset = NumberOr(StyleValue(widget.style, "offset"), 0)
    widget:SetSize(math.max(1, width + offset * 2), math.max(1, height + offset * 2))
    widget:ClearAllPoints()
    widget:SetPoint("CENTER", widget:GetParent(), "CENTER")

    HideAllVisuals(widget)
    widget._styleName = NormalizeStyleName(StyleValue(widget.style, "style"))
    if widget._styleName == "PULSE" then
        ConfigurePulse(widget, widget.style)
    elseif widget._styleName == "PROC_FLIPBOOK" then
        ConfigureProcFlipbook(widget, widget.style)
    else
        ConfigureEdgeFlow(widget, widget.style)
    end
    return widget
end

local function ShowGlowWidget(widget)
    if not widget then return end
    widget._isShown = true
    widget:Show()
    if StyleValue(widget.style, "enabled") ~= false then
        ApplyGlowStyle(widget, widget.style)
    end
    return widget
end

local function HideGlowWidget(widget)
    StopGlowWidget(widget)
    return widget
end

local function ReleaseGlowWidget(widget)
    if not widget or widget._released then return end
    widget._released = true
    StopGlowWidget(widget)
    widget:ClearAllPoints()
    widget.style = nil
    EXFactory:Release(GLOW_WIDGET_POOL, widget)
end

EXFactory:InitPool(GLOW_WIDGET_POOL, "Frame", nil, function(widget)
    widget:SetClipsChildren(false)
    widget:EnableMouse(false)

    widget.pulseTexture = EXUI:CreateVisualTexture(widget, _G.EXGLOWFRAME)
    widget.pulseTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    widget.pulseTexture:SetBlendMode("ADD")
    widget.pulseTexture:Hide()

    widget.pulseGroup = widget.pulseTexture:CreateAnimationGroup()
    widget.pulseGroup:SetLooping("REPEAT")
    widget.pulseIn = widget.pulseGroup:CreateAnimation("Alpha")
    widget.pulseIn:SetOrder(1)
    widget.pulseIn:SetFromAlpha(0.30)
    widget.pulseIn:SetToAlpha(1)
    widget.pulseOut = widget.pulseGroup:CreateAnimation("Alpha")
    widget.pulseOut:SetOrder(2)
    widget.pulseOut:SetFromAlpha(1)
    widget.pulseOut:SetToAlpha(0.30)
    widget.pulseScaleUp = widget.pulseGroup:CreateAnimation("Scale")
    widget.pulseScaleUp:SetOrder(1)
    widget.pulseScaleUp:SetScale(1.05, 1.05)
    widget.pulseScaleUp:SetOrigin("CENTER", 0, 0)
    widget.pulseScaleDown = widget.pulseGroup:CreateAnimation("Scale")
    widget.pulseScaleDown:SetOrder(2)
    widget.pulseScaleDown:SetScale(0.952381, 0.952381)
    widget.pulseScaleDown:SetOrigin("CENTER", 0, 0)

    widget.procStart = EXUI:CreateVisualTexture(widget, _G.EXGLOWFRAME)
    widget.procStart:SetAtlas("UI-HUD-ActionBar-Proc-Start-Flipbook", true)
    widget.procStart:Hide()
    widget.procLoop = EXUI:CreateVisualTexture(widget, _G.EXGLOWFRAME)
    widget.procLoop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook", true)
    widget.procLoop:Hide()

    widget.procStartGroup = widget.procStart:CreateAnimationGroup()
    widget.procStartGroup:SetToFinalAlpha(true)
    widget.procStartFlip = widget.procStartGroup:CreateAnimation("FlipBook")
    widget.procStartFlip:SetOrder(1)
    widget.procLoopGroup = widget.procLoop:CreateAnimationGroup()
    widget.procLoopGroup:SetLooping("REPEAT")
    widget.procLoopFlip = widget.procLoopGroup:CreateAnimation("FlipBook")
    widget.procLoopFlip:SetOrder(1)
    widget.procStartGroup:SetScript("OnFinished", function()
        if widget._styleName == "PROC_FLIPBOOK" and widget._isShown then
            widget.procStart:Hide()
            widget.procLoop:Show()
            widget.procLoopGroup:Play()
        end
    end)

    widget.flowClip = CreateFrame("Frame", nil, widget)
    widget.flowClip:SetAllPoints(widget)
    widget.flowClip:SetClipsChildren(true)
    widget.edgeTrains = {}
    for trainIndex = 1, MAX_EDGE_TRAINS do
        local train = {}
        for _, edgeName in ipairs(EDGE_ORDER) do
            local edge = CreateFrame("Frame", nil, widget.flowClip)
            edge.core = EXUI:CreateVisualTexture(edge, _G.EXGLOWFRAME)
            edge.core:SetTexture("Interface\\Buttons\\WHITE8X8")
            edge.core:SetBlendMode("BLEND")
            if edgeName == "top" or edgeName == "bottom" then
                edge.core:SetPoint("CENTER", edge, "CENTER")
                edge.core:SetPoint("LEFT", edge, "LEFT")
                edge.core:SetPoint("RIGHT", edge, "RIGHT")
            else
                edge.core:SetPoint("CENTER", edge, "CENTER")
                edge.core:SetPoint("TOP", edge, "TOP")
                edge.core:SetPoint("BOTTOM", edge, "BOTTOM")
            end
            edge.group = edge:CreateAnimationGroup()
            edge:Hide()
            train[edgeName] = edge
        end
        widget.edgeTrains[trainIndex] = train
    end

    widget.ApplyStyle = ApplyGlowStyle
    widget.ShowGlow = ShowGlowWidget
    widget.HideGlow = HideGlowWidget
    widget.Release = ReleaseGlowWidget
end)

--- 创建独立 Overlay；parent 必须是调用方可安全持有的宿主，宽高必须通过 style 传入。
function EXUI:CreateGlowWidget(parent, style)
    local widget = EXFactory:Acquire(GLOW_WIDGET_POOL, parent)
    widget._released = false
    widget._isShown = false
    widget.style = style or DEFAULT_STYLE
    widget:Hide()
    return widget
end

--- 方便旧模块渐进迁移的 facade：不读取 target 任何几何或显示状态。
function EXUI:ShowGlow(target, style)
    if not target then return nil end
    local glow = target._exuiGlowWidget
    if not glow or glow._released then
        glow = self:CreateGlowWidget(target, style)
        target._exuiGlowWidget = glow
    end
    glow.style = style or glow.style
    glow:ShowGlow()
    return glow
end

function EXUI:HideGlow(target)
    local glow = target and target._exuiGlowWidget
    if glow then glow:HideGlow() end
end

function EXUI:ReleaseGlow(target)
    local glow = target and target._exuiGlowWidget
    if glow then
        glow:Release()
        target._exuiGlowWidget = nil
    end
end

--- 将 GlowSettings 的扁平 DB 结构翻译成运行时 Style；保留旧字段后缀以便无迁移读取。
function EXUI:BuildGlowStyle(db, key, width, height)
    db = type(db) == "table" and db or {}
    key = key or "glow"
    return {
        enabled = db[key .. "Enabled"] ~= false,
        style = db[key .. "Style"] or DEFAULT_STYLE.style,
        width = width or db[key .. "Width"] or DEFAULT_STYLE.width,
        height = height or db[key .. "Height"] or DEFAULT_STYLE.height,
        offset = db[key .. "Offset"] or DEFAULT_STYLE.offset,
        frequency = db[key .. "Frequency"] or DEFAULT_STYLE.frequency,
        particles = db[key .. "Lines"] or DEFAULT_STYLE.particles,
        length = db[key .. "Length"] or (32 * (db[key .. "Scale"] or DEFAULT_STYLE.scale)),
        thickness = db[key .. "Thickness"] or (2 * (db[key .. "Scale"] or DEFAULT_STYLE.scale)),
        direction = db[key .. "Direction"] or DEFAULT_STYLE.direction,
        scale = db[key .. "Scale"] or DEFAULT_STYLE.scale, -- 旧字段，供 Pulse / Proc 兼容
        r = db[key .. "ColorR"] or DEFAULT_STYLE.r,
        g = db[key .. "ColorG"] or DEFAULT_STYLE.g,
        b = db[key .. "ColorB"] or DEFAULT_STYLE.b,
        a = db[key .. "ColorA"] or DEFAULT_STYLE.a,
    }
end
