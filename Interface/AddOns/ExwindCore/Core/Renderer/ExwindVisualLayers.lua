-- =========================================================
-- Exwind 全局视觉层级标准
-- =========================================================
-- 这是全插件可直接引用的权威声明。DrawLayer 只控制同一 Frame 内的
-- Texture / FontString；frameLevelOffset 用于由 EXUI 创建或显式应用到
-- 子 Frame 的情况。窗口、菜单、Tooltip 的 FrameStrata 不属于本规范。

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local CreateFrame = _G.CreateFrame

local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI

local profiles = {
    background = { id = "background", drawLayer = "BACKGROUND", subLevel = 0, frameLevelOffset = 0 },
    glow       = { id = "glow",       drawLayer = "ARTWORK",   subLevel = -2, frameLevelOffset = 1 },
    base       = { id = "base",       drawLayer = "ARTWORK",   subLevel = 0, frameLevelOffset = 2 },
    fill       = { id = "fill",       drawLayer = "ARTWORK",   subLevel = 1, frameLevelOffset = 3 },
    border     = { id = "border",     drawLayer = "OVERLAY",   subLevel = 3, frameLevelOffset = 10 },
    font       = { id = "font",       drawLayer = "OVERLAY",   subLevel = 6, frameLevelOffset = 20 },
    editor     = { id = "editor",     drawLayer = "HIGHLIGHT", subLevel = 7, frameLevelOffset = 30 },

    -- 标准预览只允许使用这一条视觉堆叠：宿主背景 < 图标/条本体 <
    -- 声明式子元素 < 触控命中框。它们不是模块私有约定；标准预览组合层
    -- 必须显式应用这些 profile，不能依赖 Frame 创建先后顺序“碰巧正确”。
    previewBody   = { id = "previewBody",   drawLayer = "ARTWORK",   subLevel = 0, frameLevelOffset = 2 },
    previewChild  = { id = "previewChild",  drawLayer = "OVERLAY",   subLevel = 6, frameLevelOffset = 20 },
    previewEditor = { id = "previewEditor", drawLayer = "HIGHLIGHT", subLevel = 7, frameLevelOffset = 30 },

    -- 所有 EXWIND 编辑模式共用的一套前景覆盖视觉。背景、边框与唯一模块名都承载在
    -- 同一份 visual-layer 记录内，确保它们压过条/图标/children；它不拥有鼠标，也不
    -- 区分产品家族。标题使用独立的最高级文本承载 Frame，只为避开 StatusBar/Cooldown
    -- 等子 Frame 的跨 Frame 绘制排序；它不是第二套 Overlay，也没有第二个标题。
    editModeOverlay    = { id = "editModeOverlay",    drawLayer = "HIGHLIGHT", subLevel = 7, frameLevelOffset = 100 },
    editModeBackground = { id = "editModeBackground", drawLayer = "BACKGROUND", subLevel = 0, frameLevelOffset = 30 },
    editModeBorder     = { id = "editModeBorder",     drawLayer = "OVERLAY",    subLevel = 7, frameLevelOffset = 30 },
    editModeTitle      = { id = "editModeTitle",      drawLayer = "HIGHLIGHT",  subLevel = 7, frameLevelOffset = 30 },
}

-- 公共全局名：EXAura、EXBoss、Tools 及独立模块无需依赖 EXUI 私有表即可引用。
_G.EXBACKGROUNDFRAME = profiles.background
_G.EXGLOWFRAME       = profiles.glow
_G.EXBASEFRAME       = profiles.base
_G.EXFILLFRAME       = profiles.fill
_G.EXBORDERFRAME     = profiles.border
_G.EXFONTFRAME       = profiles.font
_G.EXEDITORFRAME     = profiles.editor
_G.EXPREVIEWBODYFRAME   = profiles.previewBody
_G.EXPREVIEWCHILDFRAME  = profiles.previewChild
_G.EXPREVIEWEDITORFRAME = profiles.previewEditor
_G.EXEDITMODEOVERLAYFRAME        = profiles.editModeOverlay
_G.EXEDITMODEBACKGROUNDFRAME = profiles.editModeBackground
_G.EXEDITMODEBORDERFRAME     = profiles.editModeBorder
_G.EXEDITMODETITLEFRAME      = profiles.editModeTitle

EXUI.VisualLayers = profiles

function EXUI:GetVisualLayer(profile)
    if type(profile) == "string" then return profiles[profile] end
    if type(profile) == "table" then return profile end
    return profiles.base
end

function EXUI:ApplyVisualLayer(region, profile, root)
    if not region then return region end
    local layer = self:GetVisualLayer(profile)
    if region.SetDrawLayer then
        region:SetDrawLayer(layer.drawLayer, layer.subLevel)
    end
    -- Texture / FontString 没有 FrameLevel；只有子 Frame 才在这里调整。
    if region.SetFrameLevel then
        local owner = root or (region.GetParent and region:GetParent())
        local baseLevel = owner and owner.GetFrameLevel and owner:GetFrameLevel() or 0
        region:SetFrameLevel(math.max(0, baseLevel + layer.frameLevelOffset))
    end
    region._exwindVisualLayer = layer.id
    return region
end

function EXUI:CreateVisualTexture(parent, profile, templateName)
    if not parent or not parent.CreateTexture then return nil end
    local layer = self:GetVisualLayer(profile)
    local texture = parent:CreateTexture(nil, layer.drawLayer, templateName, layer.subLevel)
    return self:ApplyVisualLayer(texture, layer, parent)
end

function EXUI:CreateVisualFontString(parent, profile, templateName)
    if not parent or not parent.CreateFontString then return nil end
    local layer = self:GetVisualLayer(profile)
    local text = parent:CreateFontString(nil, layer.drawLayer, templateName, layer.subLevel)
    return self:ApplyVisualLayer(text, layer, parent)
end

-- DrawLayer 只能排列同一个 Frame 的 Region。Cooldown / StatusBar 是子 Frame，
-- 因此需要一个真正更高的 sibling Frame 来承载文字，不能只给 FontString
-- 调 SetDrawLayer。所有“文字必须压过条体/冷却扇形”的场景都应使用此入口。
function EXUI:EnsureVisualLayerFrame(root, profile, key)
    if not root then return nil end
    root._exwindVisualLayerFrames = root._exwindVisualLayerFrames or {}
    local frameKey = tostring(key or self:GetVisualLayer(profile).id)
    local frame = root._exwindVisualLayerFrames[frameKey]
    if not frame then
        frame = CreateFrame("Frame", nil, root)
        frame:EnableMouse(false)
        frame:SetAllPoints(root)
        root._exwindVisualLayerFrames[frameKey] = frame
    end
    self:ApplyVisualLayer(frame, profile, root)
    return frame
end

-- 编辑模式视觉只有这一处绘制实现。它不保存编辑状态、不挑选插件色板、不读取模块
-- 注册，也不决定何时显示；唯一的 ExwindEditMode.lua 必须把已经决定好的 profile、
-- 本地化标题和字号一次传入。
function EXUI:EnsureEditModeVisualLayer(host)
    if not host then return nil end

    local layer = host.__ExwindEditModeVisualLayer
    if not layer then
        layer = { borders = {} }
        layer.frame = CreateFrame("Frame", nil, host)
        layer.frame:EnableMouse(false)
        layer.frame:SetAllPoints(host)
        self:ApplyVisualLayer(layer.frame, profiles.editModeOverlay, host)

        layer.background = self:CreateVisualTexture(layer.frame, profiles.editModeBackground)
        layer.background:SetTexture("Interface\\Buttons\\WHITE8X8")
        for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
            local border = self:CreateVisualTexture(layer.frame, profiles.editModeBorder)
            border:SetTexture("Interface\\Buttons\\WHITE8X8")
            layer.borders[edge] = border
        end
        -- WoW 的 StatusBar/Cooldown 是独立子 Frame；同宿主子树的 FontString 会被其
        -- strata/裁切吞没。标题仍归属于这一份 layer 记录，但文字宿主必须是 UIParent
        -- 的顶层 sibling，并只锚定这份 overlay frame。
        layer.titleHost = CreateFrame("Frame", nil, _G.UIParent)
        layer.titleHost:EnableMouse(false)
        layer.titleHost:SetFrameStrata("TOOLTIP")
        layer.titleHost:SetFrameLevel(1000)
        layer.title = self:CreateVisualFontString(layer.titleHost, profiles.editModeTitle, "GameFontNormalHuge")
        layer.title:SetAllPoints(layer.titleHost)
        layer.title:SetJustifyH("CENTER")
        layer.title:SetJustifyV("MIDDLE")
        layer.title:SetWordWrap(false)
        layer.title:SetNonSpaceWrap(false)
        host.__ExwindEditModeVisualLayer = layer
    end
    return layer
end

function EXUI:SetEditModeVisualLayerShown(host, shown, profile, moduleTitle, titleFontSize, worldBounds)
    local layer = self:EnsureEditModeVisualLayer(host)
    if not layer then return nil end

    local visible = shown == true
    if visible and type(profile) ~= "table" then
        error("SetEditModeVisualLayerShown: visible layer requires Core profile", 2)
    end
    if visible and (type(moduleTitle) ~= "string" or moduleTitle == "") then
        error("SetEditModeVisualLayerShown: visible layer requires module title", 2)
    end
    if visible and (type(titleFontSize) ~= "number" or titleFontSize <= 0) then
        error("SetEditModeVisualLayerShown: visible layer requires positive title font size", 2)
    end
    if worldBounds ~= nil and (type(worldBounds) ~= "table"
        or type(worldBounds.width) ~= "number" or worldBounds.width <= 0
        or type(worldBounds.height) ~= "number" or worldBounds.height <= 0
        or type(worldBounds.anchorOffsetX) ~= "number" or type(worldBounds.anchorOffsetY) ~= "number") then
        error("SetEditModeVisualLayerShown: worldBounds must contain positive width/height and numeric anchor offsets", 2)
    end
    if worldBounds and worldBounds.anchor ~= nil and (not worldBounds.anchor.SetPoint
        or type(worldBounds.left) ~= "number" or type(worldBounds.right) ~= "number"
        or type(worldBounds.bottom) ~= "number" or type(worldBounds.top) ~= "number"
        or worldBounds.right <= worldBounds.left or worldBounds.top <= worldBounds.bottom) then
        error("SetEditModeVisualLayerShown: declared selection bounds must contain anchor and four ordered edges", 2)
    end

    layer.frame:ClearAllPoints()
    if worldBounds and worldBounds.anchor then
        -- 暴雪 EditMode 的 SelectionFrame 模式：模块的唯一 layout 已声明四边，
        -- 覆盖层直接用 TOPLEFT/BOTTOMRIGHT 锚定，绝不扫描实际渲染子树。
        layer.frame:SetPoint("TOPLEFT", worldBounds.anchor, "CENTER", worldBounds.left, worldBounds.top)
        layer.frame:SetPoint("BOTTOMRIGHT", worldBounds.anchor, "CENTER", worldBounds.right, worldBounds.bottom)
    elseif worldBounds then
        -- 内容根点和内容并集中心可以不同（AuraContainer 从 host.CENTER
        -- 向右下生长）。世界编辑拖动仍保存语义根点；覆盖层只包住标准
        -- renderer 实际计算出的可见内容并集。
        layer.frame:SetSize(worldBounds.width, worldBounds.height)
        layer.frame:SetPoint("CENTER", host, "CENTER", worldBounds.anchorOffsetX, worldBounds.anchorOffsetY)
    else
        layer.frame:SetAllPoints(host)
    end
    layer.frame:SetFrameStrata(host:GetFrameStrata())
    self:ApplyVisualLayer(layer.frame, profiles.editModeOverlay, host)
    layer.frame:SetShown(visible)

    local titleHost = layer.titleHost
    titleHost:ClearAllPoints()
    -- 标题置于选择框顶边之上，避免遮挡模块自身内容。titleHost 保持独立的最高
    -- sibling Frame，只解决跨 Cooldown/StatusBar 的绘制层级，不拥有鼠标。
    titleHost:SetSize(layer.frame:GetWidth(), titleFontSize + 4)
    titleHost:SetPoint("BOTTOM", layer.frame, "TOP", 0, 2)
    titleHost:SetFrameStrata("TOOLTIP")
    titleHost:SetFrameLevel(1000)
    if visible then
        -- TimerBar 中已在 PTR 可见的简中文字由 EXDB:ApplyFont + LSM 的“默认”字体
        -- 解析。编辑标题必须走完全相同的字体入口，不能自行猜测某个 AR 字体路径。
        local fontDB = _G.EXDB
        if not fontDB or type(fontDB.ApplyFont) ~= "function" then
            error("edit mode title font service is unavailable", 2)
        end
        fontDB:ApplyFont(layer.title, {
            font = "默认",
            size = titleFontSize,
            outline = profile.titleOutline,
            r = profile.title.r,
            g = profile.title.g,
            b = profile.title.b,
            a = profile.title.a,
        })
        layer.title:SetText(moduleTitle)
        local titleWidth = layer.title:GetStringWidth() + 8
        if titleWidth > titleHost:GetWidth() then
            titleHost:SetWidth(titleWidth)
        end
        layer.title:SetShadowColor(profile.titleShadow.r, profile.titleShadow.g, profile.titleShadow.b, profile.titleShadow.a)
        layer.title:SetShadowOffset(profile.titleShadow.x, profile.titleShadow.y)
        layer.title:SetAlpha(1)
        layer.title:Show()
    else
        layer.title:SetText("")
        layer.title:Hide()
    end
    titleHost:SetShown(visible)

    local background = layer.background
    background:ClearAllPoints()
    background:SetAllPoints(layer.frame)
    if visible then
        background:SetVertexColor(profile.fill.r, profile.fill.g, profile.fill.b, profile.fill.a)
    end
    self:ApplyVisualLayer(background, profiles.editModeBackground, host)
    background:SetShown(visible)

    for edge, border in pairs(layer.borders) do
        border:ClearAllPoints()
        if visible then
            border:SetVertexColor(profile.border.r, profile.border.g, profile.border.b, profile.border.a)
        end
        if edge == "top" then
            border:SetPoint("TOPLEFT", layer.frame, "TOPLEFT")
            border:SetPoint("TOPRIGHT", layer.frame, "TOPRIGHT")
            border:SetHeight(profile.borderSize)
        elseif edge == "bottom" then
            border:SetPoint("BOTTOMLEFT", layer.frame, "BOTTOMLEFT")
            border:SetPoint("BOTTOMRIGHT", layer.frame, "BOTTOMRIGHT")
            border:SetHeight(profile.borderSize)
        elseif edge == "left" then
            border:SetPoint("TOPLEFT", layer.frame, "TOPLEFT")
            border:SetPoint("BOTTOMLEFT", layer.frame, "BOTTOMLEFT")
            border:SetWidth(profile.borderSize)
        else
            border:SetPoint("TOPRIGHT", layer.frame, "TOPRIGHT")
            border:SetPoint("BOTTOMRIGHT", layer.frame, "BOTTOMRIGHT")
            border:SetWidth(profile.borderSize)
        end
        self:ApplyVisualLayer(border, profiles.editModeBorder, host)
        border:SetShown(visible)
    end

    return layer
end

function ExwindTools:GetVisualLayer(profile)
    return EXUI:GetVisualLayer(profile)
end

function ExwindTools:ApplyVisualLayer(region, profile, root)
    return EXUI:ApplyVisualLayer(region, profile, root)
end
