-- =========================================================
-- ExwindGlow.lua
-- Core 级原生发光引擎：Core 内所有发光都走这里。
-- 设计约束：不读取宿主 GetWidth/GetHeight/IsShown；调用方传入已知普通尺寸。
-- =========================================================

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

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
    desaturate = false, -- PROC_FLIPBOOK：true 时翻书图去色后再着色（调用方显式开）
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

-- 当前已播着的样式：同一份参数再设一次时直接跳过（动画由暴雪自己继续播）；任何停掉画面的地方都要清掉它。
local STYLE_KEYS = { "style", "width", "height", "offset", "frequency", "particles", "length",
    "thickness", "direction", "scale", "desaturate", "r", "g", "b", "a" }
local function StyleKey(style)
    local parts = {}
    for index, key in ipairs(STYLE_KEYS) do parts[index] = tostring(StyleValue(style, key)) end
    return table.concat(parts, "|")
end

local function HideAllVisuals(widget)
    widget._appliedKey = nil
    StopGroup(widget.pulseGroup)
    StopGroup(widget.procStartGroup)
    StopGroup(widget.procLoopGroup)
    StopGroup(widget.procRevealGroup)
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
    local frequency = math.max(0.05, NumberOr(StyleValue(style, "frequency"), 1))
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

-- 线条按要用的条数才建（最多 MAX_EDGE_TRAINS 条），建过的留着复用。
local function EnsureEdgeTrains(widget, count)
    for trainIndex = #widget.edgeTrains + 1, count do
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
            edge.group:SetLooping("REPEAT")
            edge.translation = edge.group:CreateAnimation("Translation")
            edge.translation:SetOrder(1)
            edge.translation:SetSmoothing("NONE")
            edge:Hide()
            train[edgeName] = edge
        end
        widget.edgeTrains[trainIndex] = train
    end
end

local function ConfigureEdgeFlow(widget, style)
    local width = math.max(1, NumberOr(StyleValue(style, "width"), 40))
    local height = math.max(1, NumberOr(StyleValue(style, "height"), width))
    -- offset 是有方向的：正值向外扩，负值向内收。这里绝不能取绝对值。
    local offset = NumberOr(StyleValue(style, "offset"), 0)
    local scale = math.max(0.25, NumberOr(StyleValue(style, "scale"), 1))
    local frequency = math.max(0.05, NumberOr(StyleValue(style, "frequency"), 1))
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
    EnsureEdgeTrains(widget, lineCount)

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

                -- 每条边一个平移动画，建一次后只改参数（不 RemoveAnimations 再新建）。
                edge.group:Stop()
                local translation = edge.translation
                translation:SetStartDelay(startDelay)
                translation:SetEndDelay(endDelay)
                translation:SetDuration(travelDuration)
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
    local frequency = math.max(0.05, NumberOr(StyleValue(style, "frequency"), 1))
    local areaWidth = math.max(1, width + offset * 2)
    local areaHeight = math.max(1, height + offset * 2)
    local colorR, colorG, colorB, colorA = StyleValue(style, "r"), StyleValue(style, "g"), StyleValue(style, "b"), StyleValue(style, "a")

    local loopSizeW = areaWidth * 1.4 * scale
    local loopSizeH = areaHeight * 1.4 * scale
    local startSizeW = areaWidth * (150 / 42 / 1.4) * scale
    local startSizeH = areaHeight * (150 / 42 / 1.4) * scale

    -- 暴雪触发光环翻书图自带金黄底色，乘顶点色会把所选颜色染黄：调用方开了 desaturate 才去色成灰白再着色。
    local desaturate = StyleValue(style, "desaturate") == true
    widget.procStart:SetDesaturated(desaturate)
    widget.procLoop:SetDesaturated(desaturate)
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
    local startDuration = 0.7 / frequency
    widget.procStartFlip:SetDuration(startDuration)
    widget.procStartFade:SetStartDelay(startDuration)
    widget.procRevealFade:SetStartDelay(startDuration)

    widget.procLoopFlip:SetFlipBookRows(6)
    widget.procLoopFlip:SetFlipBookColumns(5)
    widget.procLoopFlip:SetFlipBookFrames(30)
    widget.procLoopFlip:SetFlipBookFrameWidth(0)
    widget.procLoopFlip:SetFlipBookFrameHeight(0)
    widget.procLoopFlip:SetDuration(1 / frequency)

    -- 宿主子树可能不执行 Lua 脚本，不能靠 OnFinished 衔接：两段同时播放，循环段延迟显形。
    widget.procStart:SetAlpha(1)
    widget.procLoop:SetAlpha(0)
    widget.procStart:Show()
    widget.procLoop:Show()
    widget.procStartGroup:Play()
    widget.procLoopGroup:Play()
    widget.procRevealGroup:Play()
end

-- 跳过前确认动画还在播（被别处停掉的就照常重设）。
local function StillPlaying(widget)
    local name = widget._styleName
    if name == "PULSE" then return widget.pulseGroup:IsPlaying() end
    if name == "PROC_FLIPBOOK" then return widget.procLoopGroup:IsPlaying() end
    local train = widget.edgeTrains[1]
    return train ~= nil and train.top.group:IsPlaying()
end

local function ApplyGlowStyle(widget, style)
    widget.style = style or DEFAULT_STYLE
    local key = StyleKey(widget.style)
    if widget._appliedKey == key and StillPlaying(widget) then return widget end
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
    widget._appliedKey = key
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

-- 发光框按父级就地创建、就地复用：部分宿主（如暴雪 AuraButton）的子树禁止 SetParent 进入，
-- 所以不能从全局池借出再挂过去。释放时只隐藏并记进父级自己的空闲表。
local function ReleaseGlowWidget(widget)
    if not widget or widget._released then return end
    widget._released = true
    StopGlowWidget(widget)
    widget:ClearAllPoints()
    widget.style = nil
    local parent = widget:GetParent()
    if parent then
        parent._exGlowFree = parent._exGlowFree or {}
        table.insert(parent._exGlowFree, widget)
    end
end

local function InitGlowWidget(widget)
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
    widget.procStartFade = widget.procStartGroup:CreateAnimation("Alpha")
    widget.procStartFade:SetFromAlpha(1)
    widget.procStartFade:SetToAlpha(0)
    widget.procStartFade:SetDuration(0.01)
    widget.procLoopGroup = widget.procLoop:CreateAnimationGroup()
    widget.procLoopGroup:SetLooping("REPEAT")
    widget.procLoopFlip = widget.procLoopGroup:CreateAnimation("FlipBook")
    widget.procLoopFlip:SetOrder(1)
    widget.procRevealGroup = widget.procLoop:CreateAnimationGroup()
    widget.procRevealGroup:SetToFinalAlpha(true)
    widget.procRevealFade = widget.procRevealGroup:CreateAnimation("Alpha")
    widget.procRevealFade:SetFromAlpha(0)
    widget.procRevealFade:SetToAlpha(1)
    widget.procRevealFade:SetDuration(0.01)

    widget.flowClip = CreateFrame("Frame", nil, widget)
    widget.flowClip:SetAllPoints(widget)
    widget.flowClip:SetClipsChildren(true)
    widget.edgeTrains = {} -- 线条用到才建，见 EnsureEdgeTrains

    widget.ApplyStyle = ApplyGlowStyle
    widget.ShowGlow = ShowGlowWidget
    widget.HideGlow = HideGlowWidget
    widget.Release = ReleaseGlowWidget
end

--- 创建独立 Overlay；parent 必须是调用方可安全持有的宿主，宽高必须通过 style 传入。
function EXUI:CreateGlowWidget(parent, style)
    local free = parent and parent._exGlowFree
    local widget = free and table.remove(free)
    if not widget then
        widget = CreateFrame("Frame", nil, parent or UIParent)
        InitGlowWidget(widget)
    end
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

-- Collection ItemRoot visual effects are transient.  The caller supplies ordinary
-- body dimensions; neither the Glow facade nor this path reads protected geometry.
function EXUI:ApplyCollectionItemVisualEffects(root, effects, width, height, baseScale)
    if not root then return end
    effects = type(effects) == "table" and effects or {}
    local alpha = type(effects.alpha) == "table" and effects.alpha.value or nil
    local scale = type(effects.scale) == "table" and effects.scale.value or nil
    root:SetAlpha(alpha == nil and 1 or alpha)
    root:SetScale((baseScale or 1) * (scale or 1))
    local glow = effects.glow
    if type(glow) ~= "table" then self:ReleaseGlow(root); return end
    local color = type(glow.color) == "table" and glow.color or {}
    self:ShowGlow(root, {
        enabled = true, style = glow.style or "EDGE_FLOW",
        width = width, height = height,
        offset = glow.offset, frequency = glow.frequency,
        particles = glow.particles, length = glow.length,
        thickness = glow.thickness, direction = glow.direction,
        scale = glow.scale, desaturate = glow.desaturate == true,
        r = color.r, g = color.g, b = color.b, a = color.a,
    })
end

function EXUI:ReleaseCollectionItemVisualEffects(root, baseScale)
    if not root then return end
    self:ReleaseGlow(root)
    root:SetAlpha(1)
    root:SetScale(baseScale or 1)
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
