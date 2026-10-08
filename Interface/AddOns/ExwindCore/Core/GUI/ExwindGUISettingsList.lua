-- =========================================================
-- ExwindGUISettingsList.lua: 设置卡片、区块、行、表格及 ModuleCommon 纯布局计算。
-- 复用 ExwindGUI 的同一 UI/外观表；不创建新的配置或对象池系统。
-- 定位: SettingsCard -> Section/Row -> Table -> Prepare/Restore -> ModuleCommon Flow。
-- 页面 session、声明和配置写回仍由原 Grid/V2/业务 owner 持有。
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local GM = ExwindTools.GUIMetrics
if not GM then error("ExwindGUIMetrics.lua must load before ExwindGUISettingsList.lua") end
local EXUI = ExwindTools.UI
local MODERN = EXUI.ControlAppearance
local MC = MODERN.colors
local Internal = EXUI._GUIInternal
local AcquireCompositeGroup = Internal.AcquireCompositeGroup
local AttachModernMenuCheckboxMark = Internal.AttachModernMenuCheckboxMark
local AttachModernMenuSelectionMark = Internal.AttachModernMenuSelectionMark
local MODERN_MEDIA = Internal.MODERN_MEDIA
local PaintModernCheckbox = Internal.PaintModernCheckbox
local PaintModernButton = Internal.PaintModernButton
local SLIDER_NUMBER_INPUT_WIDTH = Internal.SLIDER_NUMBER_INPUT_WIDTH
local SLIDER_NUMBER_INPUT_HEIGHT = Internal.SLIDER_NUMBER_INPUT_HEIGHT
local PaintModernInput = Internal.PaintModernInput
local PaintModernDropdown = Internal.PaintModernDropdown
local BUTTON_STYLE = Internal.BUTTON_STYLE

local COMPOSITE_HEADER_FILL = MC.header
local SETTINGS_CARD_HEADER_HEIGHT = GM.size.cardHeaderHeight
local SETTINGS_CARD_BODY_PADDING = GM.space.cardBodyPadding

local function CreateHeaderIconSlot(parent, size)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(size, size)
    slot:EnableMouse(false)
    EXUI:SetControlSurface(slot, GM.radius.control, MC.blue, MC.blue)
    local icon = EXUI:CreateVisualTexture(slot, EXBASEFRAME)
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    slot._exHeaderIcon = icon
    return slot
end

local function SetHeaderIcon(slot, iconPath)
    local icon = slot and slot._exHeaderIcon
    if not icon then return end
    if (type(iconPath) == "string" and iconPath ~= "") or type(iconPath) == "number" then
        icon:SetTexture(iconPath)
        icon:Show()
    else
        icon:SetTexture(nil)
        icon:Hide()
    end
end

-- 真正供 Grid:MountCards 使用的共享卡片。标题、图标占位、折叠状态和高度
-- 都由这一层拥有；Card body 内的 composite 只负责渲染无外壳内容。
function EXUI:CreateSettingsCard(parent, options)
    options = type(options) == "table" and options or {}
    local card, isNew = AcquireCompositeGroup("CompositeSettingsCard", parent)

    if isNew then
        local initialWidth = parent and parent.GetWidth and tonumber(parent:GetWidth()) or nil
        card:SetSize(math.max(64, initialWidth or 320), SETTINGS_CARD_HEADER_HEIGHT)
        EXUI:SetControlSurface(card, GM.radius.card, MC.raised, MC.cardBorder)

        local header = CreateFrame("Frame", nil, card)
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
        header:SetHeight(SETTINGS_CARD_HEADER_HEIGHT - 1)
        header:EnableMouse(true)
        if header.SetMouseMotionEnabled then header:SetMouseMotionEnabled(true) end
        if header.SetMouseClickEnabled then header:SetMouseClickEnabled(true) end
        EXUI:SetControlSurface(header, GM.radius.card, COMPOSITE_HEADER_FILL, COMPOSITE_HEADER_FILL)

        local squareBottom = EXUI:CreateVisualTexture(header, EXBASEFRAME)
        squareBottom:SetPoint("BOTTOMLEFT", 0, 0)
        squareBottom:SetPoint("BOTTOMRIGHT", 0, 0)
        squareBottom:SetHeight(GM.radius.card)
        squareBottom:SetColorTexture(unpack(COMPOSITE_HEADER_FILL))

        local divider = EXUI:CreateVisualTexture(header, EXBORDERFRAME)
        divider:SetPoint("BOTTOMLEFT", 0, 0)
        divider:SetPoint("BOTTOMRIGHT", 0, 0)
        divider:SetHeight(1)
        divider:SetColorTexture(unpack(MC.headerDivider))

        local iconSlot = CreateHeaderIconSlot(header, 18)
        iconSlot:SetPoint("LEFT", 12, 0)

        local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
        title:SetPoint("LEFT", iconSlot, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", header, "RIGHT", -36, 0)
        title:SetJustifyH("LEFT")
        MODERN.ApplyTextRole(title, "cardTitle")

        local toggle = CreateFrame("Button", nil, header)
        toggle:SetSize(24, 22)
        toggle:SetPoint("RIGHT", -6, 0)
        toggle:RegisterForClicks("LeftButtonUp")
        local glyph = EXUI:CreateVisualFontString(toggle, EXFONTFRAME, "GameFontHighlight")
        glyph:SetPoint("CENTER", 0, 1)
        MODERN.ApplyTextRole(glyph, "title", MC.muted)
        toggle._exGlyph = glyph
        local function PaintHeader()
            local listHeader = card._exSettingsListGroupMember or card._exSettingsListExternalHeader
            if listHeader then
                EXUI:ClearControlSurface(header)
                squareBottom:Hide()
                divider:Hide()
                title:SetTextColor(unpack(listHeader.titleColor))
                glyph:SetTextColor(unpack(listHeader.glyphColor))
                return
            end
            local hovered = header._exModernHover == true
            local fill = hovered and MC.headerHover or MC.header
            EXUI:SetControlSurface(header, GM.radius.card, fill, fill)
            squareBottom:SetColorTexture(unpack(fill))
            title:SetTextColor(unpack(hovered and MC.white or MC.text))
            glyph:SetTextColor(unpack(hovered and MC.text or MC.muted))
        end
        card._exSettingsCardPaintHeader = PaintHeader
        header:SetScript("OnEnter", function(self)
            self._exModernHover = true
            PaintHeader()
        end)
        header:SetScript("OnLeave", function(self)
            self._exModernHover = nil
            PaintHeader()
        end)
        toggle:SetScript("OnEnter", function(self)
            header._exModernHover = true
            PaintHeader()
        end)
        toggle:SetScript("OnLeave", function(self)
            header._exModernHover = nil
            PaintHeader()
        end)
        local function ToggleCollapsed()
            if not card._exSettingsCardCollapsible then return end
            card:SetCollapsed(not card._exSettingsCardCollapsed)
        end
        header:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then ToggleCollapsed() end
        end)
        toggle:SetScript("OnClick", ToggleCollapsed)

        local body = CreateFrame("Frame", nil, card)
        body:SetPoint("TOPLEFT", card, "TOPLEFT", SETTINGS_CARD_BODY_PADDING,
            -(SETTINGS_CARD_HEADER_HEIGHT + SETTINGS_CARD_BODY_PADDING))
        body:SetPoint("TOPRIGHT", card, "TOPRIGHT", -SETTINGS_CARD_BODY_PADDING,
            -(SETTINGS_CARD_HEADER_HEIGHT + SETTINGS_CARD_BODY_PADDING))
        body:SetHeight(1)

        card._exSettingsCardHeader = header
        card._exSettingsCardIcon = iconSlot
        card._exSettingsCardTitle = title
        card._exSettingsCardToggle = toggle
        card._exSettingsCardDivider = divider
        card._exSettingsCardSquareBottom = squareBottom
        card._exSettingsCardBody = body

        function card:GetBody()
            return self._exSettingsCardBody
        end

        function card:SetLayoutInvalidationHandler(handler)
            if handler ~= nil and type(handler) ~= "function" then
                error("SettingsCard layout invalidation handler must be a function or nil", 2)
            end
            self._exSettingsCardInvalidation = handler
        end

        function card:SetContentHeight(height)
            height = math.max(0, tonumber(height) or 0)
            local minimum = math.max(0, tonumber(self._exSettingsCardMinBodyHeight) or 0)
            local maximum = tonumber(self._exSettingsCardMaxBodyHeight)
            if maximum then height = math.min(height, math.max(minimum, maximum)) end
            height = math.max(minimum, height)
            self._exSettingsCardContentHeight = height
            self._exSettingsCardBody:SetHeight(math.max(1, height))
            self:SetHeight(self:GetPreferredHeight())
        end

        function card:GetPreferredHeight()
            if self._exSettingsListCardMode == "flat" then
                return math.max(1, tonumber(self._exSettingsCardContentHeight) or 0)
            elseif self._exSettingsListCardMode == "external" then
                local headerHeight = self._exSettingsListExternalHeader
                    and self._exSettingsListExternalHeader.height or SETTINGS_CARD_HEADER_HEIGHT
                local footerPadding = self._exSettingsListExternalHeader
                    and self._exSettingsListExternalHeader.footerPadding or 0
                if self._exSettingsCardCollapsed then return headerHeight end
                return headerHeight
                    + math.max(1, tonumber(self._exSettingsCardContentHeight) or 0) + footerPadding
            elseif self._exSettingsListCardMode == "group" then
                local headerHeight = self._exSettingsListGroupMember
                    and self._exSettingsListGroupMember.headerHeight or SETTINGS_CARD_HEADER_HEIGHT
                if self._exSettingsCardCollapsed then return headerHeight end
                return headerHeight + math.max(1, tonumber(self._exSettingsCardContentHeight) or 0) + 12
            elseif self._exSettingsListCardMode == "header" then
                if self._exSettingsCardCollapsed then return SETTINGS_CARD_HEADER_HEIGHT end
                return SETTINGS_CARD_HEADER_HEIGHT
                    + math.max(1, tonumber(self._exSettingsCardContentHeight) or 0)
            end
            if self._exSettingsCardCollapsed then return SETTINGS_CARD_HEADER_HEIGHT end
            return SETTINGS_CARD_HEADER_HEIGHT + SETTINGS_CARD_BODY_PADDING
                + (tonumber(self._exSettingsCardContentHeight) or 0) + SETTINGS_CARD_BODY_PADDING
        end

        function card:SetCollapsed(collapsed, silent)
            collapsed = collapsed == true and self._exSettingsCardCollapsible == true
            local changed = self._exSettingsCardCollapsed ~= collapsed
            self._exSettingsCardCollapsed = collapsed
            self._exSettingsCardBody:SetShown(not collapsed)
            self._exSettingsCardDivider:SetShown(not collapsed
                and self._exSettingsListExternalHeader == nil
                and self._exSettingsListGroupMember == nil)
            self._exSettingsCardSquareBottom:SetShown(not collapsed
                and self._exSettingsListExternalHeader == nil
                and self._exSettingsListGroupMember == nil)
            self._exSettingsCardToggle._exGlyph:SetText(collapsed and "v" or "^")
            self:SetHeight(self:GetPreferredHeight())
            if changed and silent ~= true and self._exSettingsCardInvalidation then
                self._exSettingsCardInvalidation(self)
            end
            return changed
        end

        function card:Release()
            self._exSettingsCardInvalidation = nil
            self._exSettingsCardBody:Hide()
            local factory = _G.ExwindFactory
            if factory and factory.ReleaseCompositeHost then
                return factory:ReleaseCompositeHost(self)
            end
            self:Hide()
            self:ClearAllPoints()
            self:SetParent(nil)
            return true
        end
    end

    card._exSettingsCardId = options.id
    card._exSettingsCardCollapsible = options.collapsible == true
    card._exSettingsCardMinBodyHeight = math.max(0, tonumber(options.minBodyHeight) or 0)
    local maximum = tonumber(options.maxBodyHeight)
    card._exSettingsCardMaxBodyHeight = maximum and math.max(0, maximum) or nil
    card._exSettingsCardOwnsScroll = options.ownsScroll == true
    card._exSettingsCardContentHeight = card._exSettingsCardMinBodyHeight
    card._exSettingsCardInvalidation = nil
    MODERN.ApplyTextRole(card._exSettingsCardTitle, "cardTitle")
    card._exSettingsCardTitle:SetJustifyH("LEFT")
    card._exSettingsCardTitle:SetJustifyV("MIDDLE")
    card._exSettingsCardTitle:SetWordWrap(false)
    card._exSettingsCardTitle:SetText(tostring(options.title or ""))
    SetHeaderIcon(card._exSettingsCardIcon, options.headerIcon or options.icon)
    card._exSettingsCardToggle:SetShown(card._exSettingsCardCollapsible)
    card._exSettingsCardBody:Show()
    card._exSettingsCardBody:SetHeight(math.max(1, card._exSettingsCardContentHeight))
    -- 有高度上限（或内容自己持有滚动区）时，卡片必须成为真正的裁切边界；
    -- 否则超高子控件仍会绘制并命中到下一张 Grid 卡片上。
    if card._exSettingsCardBody.SetClipsChildren then
        card._exSettingsCardBody:SetClipsChildren(
            card._exSettingsCardMaxBodyHeight ~= nil or card._exSettingsCardOwnsScroll
        )
    end
    EXUI:SetControlSurface(card, GM.radius.card, MC.raised, MC.cardBorder)
    card._exSettingsCardHeader._exModernHover = nil
    card._exSettingsCardPaintHeader()
    card:SetCollapsed(options.collapsed == true, true)
    return card
end

AttachModernMenuCheckboxMark = function(frame, enabled, selected)
    AttachModernMenuSelectionMark(frame, enabled, selected)
end

-- =========================================================
-- Settings list presentation
--
-- These hosts own geometry and decoration only. They never receive a config,
-- binding, getter, setter or notification callback. Grid keeps ownership of
-- the original controls and only anchors them beside these visual siblings.
-- =========================================================
local SETTINGS_LIST_ROW_PADDING_X = GM.space.rowPaddingX
local SETTINGS_LIST_ROW_PADDING_Y = GM.space.rowPaddingY
local SETTINGS_LIST_COLUMN_GAP = GM.space.columnGap
local SETTINGS_LIST_MIN_TEXT_WIDTH = GM.size.minTextWidth
local SETTINGS_LIST_STANDARD_ROW_HEIGHT = GM.size.standardRowHeight
local SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT = GM.size.ordinaryControlHeight
local SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT = GM.size.descriptionMinHeight
local SETTINGS_LIST_DESCRIPTION_GAP = GM.space.descriptionGap
local SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT = GM.size.externalHeaderHeight
local SETTINGS_LIST_SECTION_TOP = GM.space.sectionTop
local SETTINGS_LIST_SECTION_TITLE_TO_CARD_GAP = GM.space.sectionTitleToCardGap
local SETTINGS_LIST_SECTION_GROUP_GAP = GM.space.sectionGroupGap
local SETTINGS_LIST_FIELD_ROW_BREAKPOINT = GM.size.fieldRowBreakpoint
local SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT = GM.size.compactVoiceBreakpoint
local SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT = GM.size.compactVoiceSourceBreakpoint
local SETTINGS_LIST_NARROW_CONTROL_INDENT = GM.space.narrowControlIndent
local SETTINGS_LIST_COMPACT_TEXT_WIDTH = GM.size.settingsRowCompactTextWidth
local SETTINGS_LIST_STACK_GAP = GM.space.settingsRowStackGap
-- 布局 metrics 未写 height 时的默认控件槽高度；文字行（label/tableText 角色）沿用复选框行高。
local SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT = GM.size.controlHeight
local SETTINGS_LIST_TEXT_ROW_HEIGHT = GM.size.checkboxRowHeight
local SETTINGS_LIST_EXBOSS_SKILL_PROFILE = "exbossSkill"
local SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X = GM.space.exboss.contentPaddingX
local SETTINGS_LIST_EXBOSS_HEADER_HEIGHT = GM.size.exboss.headerHeight
local SETTINGS_LIST_EXBOSS_FOOTER_PADDING = GM.space.exboss.footerPadding
local SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y = GM.space.exboss.simplePaddingY
local SETTINGS_LIST_EXBOSS_SIMPLE_ROW_HEIGHT = GM.size.exboss.simpleRowHeight
local SETTINGS_LIST_EXBOSS_FIELD_PADDING_Y = GM.space.exboss.fieldPaddingY
local SETTINGS_LIST_EXBOSS_FIELD_ROW_HEIGHT = GM.size.exboss.fieldRowHeight
local SETTINGS_LIST_EXBOSS_FIELD_COLUMN_GAP = GM.space.exboss.fieldColumnGap
local SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y = GM.space.exboss.voicePaddingY
local SETTINGS_LIST_EXBOSS_VOICE_ROW_HEIGHT = GM.size.exboss.voiceRowHeight
local SETTINGS_LIST_EXBOSS_VOICE_COLUMN_GAP = GM.space.exboss.voiceColumnGap
local SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP = GM.space.exboss.voiceControlGap
local SETTINGS_LIST_EXBOSS_CARD_GAP = GM.space.exboss.cardGap
local SETTINGS_LIST_EXBOSS_CARD_STACK_BREAKPOINT = GM.size.exboss.cardStackBreakpoint
-- The screenshots define structure and rhythm, not a replacement palette.
-- Settings lists stay on the project's existing shared visual theme.
local SETTINGS_LIST_CARD_FILL = MC.raised
local SETTINGS_LIST_CARD_BORDER = MC.cardBorder
local SETTINGS_LIST_TITLE = MC.text
local SETTINGS_LIST_DESCRIPTION = MC.muted

-- [WEB-REQ 28/32] 普通行右侧控件的“最小可用宽 + 窄版结构”。
-- 返回 controlWidth, textWidth, stacked：
--   1) 空间够：文字列 >= 160，控件在 [最小可用宽, 请求宽] 内（与旧行为一致，仅把过小的默认宽抬到最小可用宽）。
--   2) 不够 160：文字列收窄，但控件仍保证最小可用宽；文字列不得小于 COMPACT_TEXT_WIDTH。
--   3) 仍不够：stacked=true，文字占满整行，控件换到下一行（默认宽的控件占满一行）。
-- minControlWidth 为 nil 表示该行不启用保证（EXBoss 技能行、多控件/特殊 profile 沿用旧算法）。
-- 显式 controlWidth / inputWidthPercent 视为作者意图：最小可用宽取 min(请求宽, 最小可用宽)，不强行放大。
local function ResolveSettingsRowColumns(innerWidth, explicitWidth, controlKind, inputWidthPercent, minControlWidth)
    local legacyDefault = math.min(260, innerWidth * 0.42)
    -- Ordinary right-side controls use one shared visual width. This is based
    -- on the original row-column budget, not on another settings-page scale.
    local ordinaryDefault = legacyDefault * 0.75
    local requested = tonumber(explicitWidth)
    if not requested or requested <= 0 then requested = nil end
    local declared = requested ~= nil
    if not requested and (controlKind == "ordinary" or controlKind == "input" or controlKind == "button") then
        local percent = tonumber(inputWidthPercent)
        declared = percent ~= nil and percent > 0 and percent ~= 100
        percent = percent and percent > 0 and percent or 100
        requested = ordinaryDefault * percent / 100
    end
    requested = requested or legacyDefault
    local maximum = math.max(1, innerWidth - SETTINGS_LIST_COLUMN_GAP - SETTINGS_LIST_MIN_TEXT_WIDTH)
    if not minControlWidth then
        local controlWidth = math.max(1, math.min(requested, maximum))
        return controlWidth, math.max(1, innerWidth - SETTINGS_LIST_COLUMN_GAP - controlWidth), false
    end
    local floor = math.min(innerWidth, declared and math.min(requested, minControlWidth) or minControlWidth)
    if maximum >= floor then
        local controlWidth = math.max(floor, math.min(requested, maximum))
        return controlWidth, math.max(1, innerWidth - SETTINGS_LIST_COLUMN_GAP - controlWidth), false
    end
    if innerWidth - SETTINGS_LIST_COLUMN_GAP - floor >= SETTINGS_LIST_COMPACT_TEXT_WIDTH then
        return floor, innerWidth - SETTINGS_LIST_COLUMN_GAP - floor, false
    end
    local stackedWidth = declared and math.min(innerWidth, math.max(floor, requested)) or innerWidth
    return math.max(1, stackedWidth), math.max(1, innerWidth), true
end

local settingsListMeasureHost = CreateFrame("Frame", nil, UIParent)
settingsListMeasureHost:SetSize(1, 1)
settingsListMeasureHost:Hide()
settingsListMeasureHost.title = EXUI:CreateVisualFontString(settingsListMeasureHost, EXFONTFRAME, "GameFontHighlight")
settingsListMeasureHost.title:SetWordWrap(true)
settingsListMeasureHost.description = EXUI:CreateVisualFontString(settingsListMeasureHost, EXFONTFRAME, "GameFontHighlightSmall")
settingsListMeasureHost.description:SetWordWrap(true)

local function MeasureSettingsListText(text, width, role)
    text = tostring(text or "")
    if text == "" then return 0 end
    local region = role == "description" and settingsListMeasureHost.description or settingsListMeasureHost.title
    if role == "description" then
        MODERN.Font(region, GM.font.text, MC.muted, "", "GameFontHighlightSmall")
    else
        MODERN.ApplyTextRole(region, role == "cardTitle" and "cardTitle" or "title")
    end
    region:SetWidth(math.max(1, tonumber(width) or 1))
    region:SetText(text)
    return math.max(1, math.ceil(region:GetStringHeight() or 0))
end

local function ReleaseSettingsListDecoration(frame)
    local factory = _G.ExwindFactory
    if factory and factory.ReleaseCompositeHost then
        return factory:ReleaseCompositeHost(frame)
    end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    return true
end

local function SettingsTextHeight(region, width)
    if not region or not region:IsShown() then return 0 end
    region:SetWidth(math.max(1, width))
    return math.max(1, math.ceil(region:GetStringHeight() or 0))
end

local function FullSettingsDescriptionHeight(region, text, width)
    local measure = settingsListMeasureHost.description
    local fontPath, fontSize, fontFlags = region:GetFont()
    if fontPath then measure:SetFont(fontPath, fontSize, fontFlags or "") end
    measure:SetWordWrap(true)
    measure:SetNonSpaceWrap(true)
    measure:SetMaxLines(0)
    measure:SetWidth(math.max(1, width))
    measure:SetText(text)
    return math.max(1, math.ceil(measure:GetStringHeight() or 0))
end

-- Reuse the exact self-drawn FillR4 surface path used by the stable modern
-- input and dropdown controls. Settings-list dividers are not native lines.
local settingsDividerFrames = setmetatable({}, { __mode = "k" })
local settingsDividerScaleWatcher
local function ApplySettingsDividerPhysicalHeight(divider)
    local effectiveScale = divider.GetEffectiveScale and divider:GetEffectiveScale() or 1
    effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
    local pixelUtil = _G.PixelUtil
    local factor = pixelUtil and pixelUtil.GetPixelToUIUnitFactor
        and pixelUtil.GetPixelToUIUnitFactor() or 1
    factor = type(factor) == "number" and factor > 0 and factor or 1
    local pixel = factor / effectiveScale
    divider:SetHeight(type(pixel) == "number" and pixel > 0 and pixel or (1 / effectiveScale))
end
local function CreateSettingsDivider(parent)
    local divider = CreateFrame("Frame", nil, parent)
    divider:EnableMouse(false)
    settingsDividerFrames[divider] = true
    if not settingsDividerScaleWatcher then
        settingsDividerScaleWatcher = CreateFrame("Frame")
        settingsDividerScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
        settingsDividerScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
        settingsDividerScaleWatcher:SetScript("OnEvent", function()
            for frame in pairs(settingsDividerFrames) do ApplySettingsDividerPhysicalHeight(frame) end
        end)
    end
    ApplySettingsDividerPhysicalHeight(divider)
    divider:HookScript("OnSizeChanged", function(self)
        if self._exDividerResizing then return end
        self._exDividerResizing = true
        ApplySettingsDividerPhysicalHeight(self)
        self._exDividerResizing = nil
    end)
    EXUI:SetControlSurface(divider, GM.radius.control, MC.headerDivider, MC.headerDivider)
    local skin = divider._exModernSurfaces and divider._exModernSurfaces[GM.radius.control]
    for _, piece in ipairs(skin and skin.pieces or {}) do
        piece.texture:SetAlpha(piece.layer == 1 and 1 or 0)
    end
    return divider
end

function EXUI:CreateSettingsSeparator(parent, width)
    local divider = CreateSettingsDivider(parent)
    divider:SetWidth(width or 200)
    return divider
end

-- Nine image slices preserve source-image UVs while each corner uses only one
-- circular mask. Mask UVs stay untouched; the corner image covers one quadrant.
function EXUI:CreateRoundedImage(parent, radius, matchSurface)
    local image = CreateFrame("Frame", nil, parent)
    image:EnableMouse(false)
    image._radius = math.max(0, tonumber(radius) or 9)
    image._uv = { 0, 1, 0, 1 }
    image._pieces = {}
    if matchSurface then
        parent._exRoundedIconBorder = true
        for surfaceRadius, skin in pairs(parent._exModernSurfaces or {}) do
            if skin.active then EXUI:SetControlSurface(parent, surfaceRadius, skin.fill, {0, 0, 0, 1}); break end
        end
    else
        image._border = CreateFrame("Frame", nil, image)
        image._border:EnableMouse(false)
        image._border:SetAllPoints(image)
        image._border._exRoundedIconBorder = true
    end
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = self:CreateVisualTexture(image, EXBASEFRAME)
            if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
            if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
            local piece = { texture = texture, row = row, col = col }
            if row ~= 2 and col ~= 2 then
                local mask = image:CreateMaskTexture(nil, "ARTWORK")
                mask:SetTexture(matchSurface and (MODERN_MEDIA .. "FillR10ImageMask.tga")
                    or "Interface\\CharacterFrame\\TempPortraitAlphaMask",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
                -- Keep the circular edge on the same fractional coordinates as
                -- its image quadrant so their sampled edges stay aligned.
                if mask.SetSnapToPixelGrid then mask:SetSnapToPixelGrid(false) end
                if mask.SetTexelSnappingBias then mask:SetTexelSnappingBias(0) end
                texture:AddMaskTexture(mask)
                piece.mask = mask
            end
            image._pieces[#image._pieces + 1] = piece
        end
    end
    local function Layout()
        local width, height = image:GetWidth(), image:GetHeight()
        if width <= 0 or height <= 0 then return end
        if image._border then
            EXUI:SetControlSurface(image._border, image._radius <= GM.radius.control and GM.radius.control or GM.radius.card, {0, 0, 0, 0}, {0, 0, 0, 1})
        end
        local r = math.min(image._radius, width / 2, height / 2)
        local x, y = { 0, r, width - r, width }, { 0, r, height - r, height }
        local uv = image._uv
        for _, piece in ipairs(image._pieces) do
            local col, row, texture = piece.col, piece.row, piece.texture
            local w, h = x[col + 1] - x[col], y[row + 1] - y[row]
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", image, "TOPLEFT", x[col], -y[row])
            texture:SetSize(math.max(.001, w), math.max(.001, h))
            texture:SetTexCoord(uv[1] + (uv[2] - uv[1]) * x[col] / width,
                uv[1] + (uv[2] - uv[1]) * x[col + 1] / width,
                uv[3] + (uv[4] - uv[3]) * y[row] / height,
                uv[3] + (uv[4] - uv[3]) * y[row + 1] / height)
            texture:SetShown(w > 0 and h > 0)
            if piece.mask then
                local point = (row == 1 and "TOP" or "BOTTOM") .. (col == 1 and "LEFT" or "RIGHT")
                piece.mask:ClearAllPoints()
                -- The surface-matched asset retains FillR10's 12px padding
                -- around its 20px source radius. Preserve that sampling scale.
                local padding = matchSurface and r * 12 / 20 or 0
                local size = 2 * (r + padding)
                piece.mask:SetPoint(point, image, point,
                    col == 1 and -padding or padding, row == 1 and padding or -padding)
                piece.mask:SetSize(math.max(.001, size), math.max(.001, size))
            end
        end
    end
    function image:SetTexture(texture)
        for _, piece in ipairs(self._pieces) do
            piece.texture:SetTexture(texture, "CLAMP", "CLAMP", "LINEAR")
        end
    end
    function image:SetTexCoord(left, right, top, bottom)
        self._uv = { left, right, top, bottom }
        Layout()
    end
    function image:SetDesaturated(desaturated)
        for _, piece in ipairs(self._pieces) do piece.texture:SetDesaturated(desaturated) end
    end
    function image:SetVertexColor(r, g, b, a)
        for _, piece in ipairs(self._pieces) do piece.texture:SetVertexColor(r, g, b, a or 1) end
    end
    function image:SetCornerRadius(nextRadius)
        self._radius = math.max(0, tonumber(nextRadius) or 0)
        Layout()
    end
    image:SetScript("OnSizeChanged", Layout)
    image:SetScript("OnShow", Layout)
    return image
end

local function ResolveSettingsListRoleRegion(widget)
    if not widget then return nil end
    if widget.text then return widget.text end
    if widget.labelText then return widget.labelText end
    if widget.IsObjectType and widget:IsObjectType("FontString") then return widget end
    return nil
end

function EXUI:CreateSettingsSection(parent, options)
    options = type(options) == "table" and options or {}
    if options.presentationProfile ~= nil
        and options.presentationProfile ~= SETTINGS_LIST_EXBOSS_SKILL_PROFILE then
        error("unknown settings section presentation profile: " .. tostring(options.presentationProfile), 2)
    end
    local section, isNew = AcquireCompositeGroup("CompositeSettingsListSection", parent)
    if isNew then
        section:EnableMouse(false)
        local title = EXUI:CreateVisualFontString(section, EXFONTFRAME, "GameFontHighlight")
        title:SetJustifyH("LEFT")
        title:SetJustifyV("TOP")
        title:SetWordWrap(true)
        local description = EXUI:CreateVisualFontString(section, EXFONTFRAME, "GameFontHighlightSmall")
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetWordWrap(true)
        local divider = CreateSettingsDivider(section)
        section._exSettingsSectionTitle = title
        section._exSettingsSectionDescription = description
        section._exSettingsSectionDivider = divider
        section.Release = ReleaseSettingsListDecoration
    end
    section:EnableMouse(false)
    section._exSettingsSectionKind = options.kind == "page" and "page"
        or (options.kind == "subsection" and "subsection"
        or (options.kind == "information" and "information" or "section"))
    section._exSettingsSectionPresentationProfile = options.presentationProfile
    section._exSettingsSectionTitle:SetText(tostring(options.title or ""))
    section._exSettingsSectionTitle:SetShown(options.title ~= nil and tostring(options.title) ~= "")
    section._exSettingsSectionDescription:SetText(tostring(options.description or ""))
    section._exSettingsSectionDescription:SetShown(options.description ~= nil and tostring(options.description) ~= "")
    section._exSettingsSectionDescriptionWidgets = type(options.descriptionWidgets) == "table"
        and options.descriptionWidgets or {}
    -- Category headings sit outside the continuous card. The card's own border
    -- supplies the visual boundary; an extra full-width rule is not part of the
    -- reference hierarchy.
    section._exSettingsSectionDivider:Hide()
    if section._exSettingsSectionKind == "page" then
        MODERN.ApplyTextRole(section._exSettingsSectionTitle, "pageTitle", SETTINGS_LIST_TITLE)
    elseif section._exSettingsSectionKind == "section" then
        MODERN.ApplyTextRole(section._exSettingsSectionTitle, "cardTitle", SETTINGS_LIST_TITLE)
    else
        MODERN.ApplyTextRole(section._exSettingsSectionTitle, "title", SETTINGS_LIST_TITLE)
    end
    MODERN.Font(section._exSettingsSectionDescription, GM.font.text, SETTINGS_LIST_DESCRIPTION,
        "", "GameFontHighlightSmall")
    return section
end

function EXUI:UpdateSettingsSectionLayout(section, width)
    if not section then return 0 end
    width = math.max(1, tonumber(width) or 1)
    section:SetWidth(width)
    local title = section._exSettingsSectionTitle
    local description = section._exSettingsSectionDescription
    local divider = section._exSettingsSectionDivider
    local page = section._exSettingsSectionKind == "page"
    local information = section._exSettingsSectionKind == "information"
    local cardSection = section._exSettingsSectionKind == "section"
    local top = page and 0 or SETTINGS_LIST_SECTION_TOP
    local insetX = information and (section._exSettingsSectionPresentationProfile
        == SETTINGS_LIST_EXBOSS_SKILL_PROFILE and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X) or 0
    local contentTop = information and SETTINGS_LIST_ROW_PADDING_Y or 0
    local textWidth = math.max(1, width - insetX * 2)
    title:ClearAllPoints()
    local height = 0
    if title:IsShown() then
        local titleTop = information and contentTop or top
        title:SetPoint("TOPLEFT", section, "TOPLEFT", insetX, -titleTop)
        title:SetPoint("TOPRIGHT", section, "TOPRIGHT", -insetX, -titleTop)
        local measured = SettingsTextHeight(title, textWidth)
        if title.GetText then
            measured = math.max(measured, MeasureSettingsListText(title:GetText(), textWidth,
                cardSection and "cardTitle" or "title"))
        end
        height = titleTop + measured
    end
    if description:IsShown() then
        local descriptionTop = height > 0 and (height + SETTINGS_LIST_DESCRIPTION_GAP) or contentTop
        description:ClearAllPoints()
        description:SetPoint("TOPLEFT", section, "TOPLEFT", insetX, -descriptionTop)
        description:SetPoint("TOPRIGHT", section, "TOPRIGHT", -insetX, -descriptionTop)
        height = descriptionTop + SettingsTextHeight(description, textWidth)
    end
    for _, widget in ipairs(section._exSettingsSectionDescriptionWidgets or {}) do
        if widget and widget.IsShown and widget:IsShown() then
            local region = ResolveSettingsListRoleRegion(widget)
            if region then
                local widgetTop = height > 0 and (height + SETTINGS_LIST_DESCRIPTION_GAP) or contentTop
                widget:SetWidth(textWidth)
                region:SetWordWrap(true)
                region:SetNonSpaceWrap(true)
                region:SetMaxLines(0)
                local text = region.GetText and tostring(region:GetText() or "") or nil
                local widgetHeight = text == "" and 1
                    or FullSettingsDescriptionHeight(region, text, textWidth)
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", section, "TOPLEFT", insetX, -widgetTop)
                widget:SetSize(textWidth, widgetHeight)
                region:SetHeight(widgetHeight)
                if text ~= "" then height = widgetTop + widgetHeight end
            end
        end
    end
    if height > 0 then
        height = height + (information and SETTINGS_LIST_ROW_PADDING_Y
            or (cardSection and SETTINGS_LIST_SECTION_TITLE_TO_CARD_GAP or 18))
    end
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 0, 0)
    ApplySettingsDividerPhysicalHeight(divider)
    section:SetSize(width, math.max(1, height))
    return height
end

function EXUI:GetSettingsSectionGroupGap()
    return SETTINGS_LIST_SECTION_GROUP_GAP
end

function EXUI:CreateSettingsRow(parent, options)
    options = type(options) == "table" and options or {}
    local row, isNew = AcquireCompositeGroup("CompositeSettingsListRow", parent)
    if isNew then
        row:EnableMouse(false)
        local title = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
        title:SetJustifyH("LEFT")
        title:SetJustifyV("TOP")
        title:SetWordWrap(true)
        local description = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetWordWrap(true)
        local divider = CreateSettingsDivider(row)
        row._exSettingsRowTitle = title
        row._exSettingsRowDescription = description
        row._exSettingsRowDivider = divider
        row.Release = ReleaseSettingsListDecoration
    end
    row:EnableMouse(false)
    if parent and row.SetFrameLevel and parent.GetFrameLevel then
        row:SetFrameLevel(parent:GetFrameLevel())
    end
    row._exSettingsRowFullWidth = options.fullWidth == true
    local controlWidth = tonumber(options.controlWidth)
    row._exSettingsRowControlWidth = controlWidth and controlWidth > 0 and controlWidth or nil
    row._exSettingsRowControlKind = options.controlKind
    row._exSettingsRowInputWidthPercent = tonumber(options.inputWidthPercent)
    row._exSettingsRowContentWidth = options.contentWidth
    -- [WEB-REQ 28] 普通行右侧控件最小可用宽（nil = 沿用旧算法）；EXBoss 技能行不启用。
    local minControlWidth = tonumber(options.controlMinWidth)
    row._exSettingsRowMinControlWidth = minControlWidth and minControlWidth > 0
        and options.presentationProfile == nil and minControlWidth or nil
    row._exSettingsRowSingleLineControls = options.singleLineControls == true
    row._exSettingsRowHTMLControlsLayout = options.htmlControlsLayout
    if options.presentationProfile ~= nil
        and options.presentationProfile ~= SETTINGS_LIST_EXBOSS_SKILL_PROFILE then
        error("unknown settings row presentation profile: " .. tostring(options.presentationProfile), 2)
    end
    row._exSettingsRowPresentationProfile = options.presentationProfile
    -- Settings-list modules declare content only.  A legacy Grid h/minHeight
    -- must not make otherwise identical ordinary rows use different heights.
    row._exSettingsRowMinHeight = options.presentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
        and SETTINGS_LIST_EXBOSS_SIMPLE_ROW_HEIGHT or SETTINGS_LIST_STANDARD_ROW_HEIGHT
    row._exSettingsRowIsLast = options.isLast == true
    row._exSettingsRowTitle:SetText(tostring(options.label or ""))
    row._exSettingsRowTitle:SetShown(options.label ~= nil and tostring(options.label) ~= "")
    row._exSettingsRowDescription:SetText(tostring(options.description or ""))
    row._exSettingsRowDescription:SetShown(options.description ~= nil and tostring(options.description) ~= "")
    MODERN.ApplyTextRole(row._exSettingsRowTitle, "title", SETTINGS_LIST_TITLE)
    MODERN.Font(row._exSettingsRowDescription, GM.font.text, SETTINGS_LIST_DESCRIPTION,
        "", "GameFontHighlightSmall")
    row._exSettingsRowDivider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return row
end

function EXUI:UpdateSettingsRowLayout(row, width, controlHeight, descriptionWidget)
    if not row then return 0, 0, 0, 0 end
    width = math.max(1, tonumber(width) or 1)
    controlHeight = math.max(1, tonumber(controlHeight) or MODERN.metrics.height)
    local exbossProfile = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    local rowPaddingX = exbossProfile and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X
    local innerWidth = math.max(1, width - rowPaddingX * 2)
    local title = row._exSettingsRowTitle
    local description = descriptionWidget
        and (descriptionWidget.text or descriptionWidget.labelText)
        or row._exSettingsRowDescription
    local descriptionShown = descriptionWidget and descriptionWidget:IsShown()
        or (not descriptionWidget and description:IsShown())
    local rowPaddingY = exbossProfile
        and SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y or SETTINGS_LIST_ROW_PADDING_Y
    local textWidth, textHeight, controlX, controlY, controlWidth, height, stacked
    if row._exSettingsRowFullWidth then
        textWidth = innerWidth
        local titleHeight = SettingsTextHeight(title, textWidth)
        textHeight = titleHeight
        if descriptionShown then
            if descriptionWidget then descriptionWidget:SetWidth(textWidth) end
            textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
                + SettingsTextHeight(description, textWidth)
        end
        controlX = 0
        controlY = textHeight > 0 and (rowPaddingY + textHeight + 10) or 0
        controlWidth = width
        local bottomPadding = textHeight > 0 and rowPaddingY or 0
        height = math.max(textHeight > 0 and row._exSettingsRowMinHeight or 0,
            controlY + controlHeight + bottomPadding)
    else
        controlWidth, textWidth, stacked = ResolveSettingsRowColumns(innerWidth,
            row._exSettingsRowControlWidth, row._exSettingsRowControlKind,
            row._exSettingsRowInputWidthPercent, row._exSettingsRowMinControlWidth)
        local titleHeight = SettingsTextHeight(title, textWidth)
        textHeight = titleHeight
        if descriptionShown then
            if descriptionWidget then descriptionWidget:SetWidth(textWidth) end
            textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
                + SettingsTextHeight(description, textWidth)
        end
        if stacked then
            -- 窄版：文字在上（占满整行），控件换到下一行并与文字左缘对齐。
            local stackGap = textHeight > 0 and SETTINGS_LIST_STACK_GAP or 0
            height = math.max(row._exSettingsRowMinHeight,
                rowPaddingY * 2 + textHeight + stackGap + controlHeight)
            controlX = rowPaddingX
            controlY = rowPaddingY + textHeight + stackGap
        else
            height = math.max(row._exSettingsRowMinHeight,
                rowPaddingY * 2 + math.max(textHeight, controlHeight))
            controlX = width - rowPaddingX - controlWidth
            controlY = math.floor((height - controlHeight) * 0.5 + 0.5)
        end
        if descriptionShown then
            local minimum = SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT
            if height < minimum then
                -- 窄版时把多出来的高度加在控件上方，保持控件贴近行底。
                if stacked then controlY = controlY + (minimum - height) end
                height = minimum
            end
        end
    end
    local textTop = rowPaddingY
    if not row._exSettingsRowFullWidth and not stacked and textHeight > 0 then
        textTop = math.floor((height - textHeight) * 0.5 + 0.5)
    end
    title:ClearAllPoints()
    if title:IsShown() then
        title:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
        title:SetWidth(textWidth)
    end
    if descriptionShown then
        local descriptionHeight = SettingsTextHeight(description, textWidth)
        if descriptionWidget then
            descriptionWidget:ClearAllPoints()
            if title:IsShown() then
                descriptionWidget:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else
                descriptionWidget:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
            end
            descriptionWidget:SetSize(textWidth, descriptionHeight)
        else
            description:ClearAllPoints()
            if title:IsShown() then
                description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else
                description:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
            end
            description:SetWidth(textWidth)
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", rowPaddingX, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -rowPaddingX, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, controlX, controlY, controlWidth, stacked == true
end

local function SettingsControlTextWidth(region)
    if not region or not region.IsShown or not region:IsShown() then return 0 end
    local width = region.GetUnboundedStringWidth and region:GetUnboundedStringWidth()
        or (region.GetStringWidth and region:GetStringWidth())
        or 0
    return math.max(0, math.ceil(tonumber(width) or 0))
end

local function ResolveSettingsSingleLineSlot(metric)
    local widget = metric and metric.widget
    if metric.slotKind == "specQueue" and widget and widget._gridType == "GridInput" then
        local labelWidth = SettingsControlTextWidth(widget.label or widget.labelText)
        local bodyWidth = 56
        return labelWidth + 5 + bodyWidth, bodyWidth
    end
    if metric.slotKind == "specAlpha" and widget and widget._gridType == "GridSlider" then
        local titleWidth = SettingsControlTextWidth(widget.Title)
        local numberWidth = widget.numberInput and widget.numberInput:GetWidth() or 48
        return math.max(80, titleWidth + 12 + math.max(1, tonumber(numberWidth) or 48)), nil
    end
    error("unsupported settings single-line control slot: " .. tostring(metric and metric.slotKind), 2)
end

local function UpdateSettingsSingleLineControlsLayout(row, width, metrics)
    local gap = 8
    local innerWidth = math.max(1, width - SETTINGS_LIST_ROW_PADDING_X * 2)
    local title = row._exSettingsRowTitle
    local description = row._exSettingsRowDescription
    local hasText = title:IsShown() or description:IsShown()
    local textWidth = 0
    if hasText then
        textWidth = math.max(SettingsControlTextWidth(title), SettingsControlTextWidth(description)) + 12
    end
    local controlsX = SETTINGS_LIST_ROW_PADDING_X
    local controlsWidth = innerWidth
    if hasText then
        controlsX = controlsX + textWidth + SETTINGS_LIST_COLUMN_GAP
        controlsWidth = math.max(0, innerWidth - textWidth - SETTINGS_LIST_COLUMN_GAP)
    end

    local visibleIndexes, slotMinimums, bodyWidths = {}, {}, {}
    local minimumControlsWidth, controlsHeight = 0, 0
    for index, metric in ipairs(metrics) do
        if metric.visible ~= false then
            local slotMinimum, bodyWidth = ResolveSettingsSingleLineSlot(metric)
            visibleIndexes[#visibleIndexes + 1] = index
            slotMinimums[index], bodyWidths[index] = slotMinimum, bodyWidth
            minimumControlsWidth = minimumControlsWidth + slotMinimum
            controlsHeight = math.max(controlsHeight, math.max(1, tonumber(metric.height) or SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT))
        end
    end
    minimumControlsWidth = minimumControlsWidth + math.max(0, #visibleIndexes - 1) * gap
    local requiredWidth = SETTINGS_LIST_ROW_PADDING_X * 2 + minimumControlsWidth
        + (hasText and (textWidth + SETTINGS_LIST_COLUMN_GAP) or 0)
    local fits = width + 0.5 >= requiredWidth
    local extraPerSlot = fits and #visibleIndexes > 0
        and math.max(0, controlsWidth - minimumControlsWidth) / #visibleIndexes or 0

    local textHeight = SettingsTextHeight(title, math.max(1, textWidth))
    if description:IsShown() then
        textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
            + SettingsTextHeight(description, math.max(1, textWidth))
    end
    local height = math.max(row._exSettingsRowMinHeight,
        SETTINGS_LIST_ROW_PADDING_Y * 2 + math.max(textHeight, controlsHeight))
    if description:IsShown() then height = math.max(height, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT) end

    local rects, slotX = {}, controlsX
    for _, index in ipairs(visibleIndexes) do
        local metric = metrics[index]
        local slotWidth = slotMinimums[index] + extraPerSlot
        local bodyWidth = bodyWidths[index] or slotWidth
        local bodyX = slotX + slotWidth - bodyWidth
        local controlHeight = math.max(1, tonumber(metric.height) or SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT)
        rects[index] = {
            slotX = slotX, slotWidth = slotWidth,
            x = bodyX,
            y = math.floor((height - controlHeight) * 0.5 + 0.5),
            width = bodyWidth, height = controlHeight,
        }
        slotX = slotX + slotWidth + gap
    end
    for index, metric in ipairs(metrics) do
        if metric.visible == false then
            rects[index] = {
                slotX = controlsX + controlsWidth, slotWidth = 1,
                x = controlsX + controlsWidth,
                y = math.floor(height * 0.5 + 0.5),
                width = 1, height = math.max(1, tonumber(metric.height) or 1),
            }
        end
    end

    if hasText then
        local textTop = math.floor((height - textHeight) * 0.5 + 0.5)
        title:ClearAllPoints()
        if title:IsShown() then
            title:SetPoint("TOPLEFT", row, "TOPLEFT", SETTINGS_LIST_ROW_PADDING_X, -textTop)
            title:SetWidth(textWidth)
        end
        description:ClearAllPoints()
        if description:IsShown() then
            if title:IsShown() then
                description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else
                description:SetPoint("TOPLEFT", row, "TOPLEFT", SETTINGS_LIST_ROW_PADDING_X, -textTop)
            end
            description:SetWidth(textWidth)
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, rects, {
        fits = fits,
        requiredWidth = requiredWidth,
        availableWidth = width,
    }
end

local function ResolveSettingsControlLine(metrics, indexes, x, availableWidth, y, controlGap, flexWeights)
    local gap, fixedWidth, flexibleWeight = math.max(0, tonumber(controlGap) or 8), 0, 0
    local rightAlign = false
    for _, index in ipairs(indexes) do
        local metric = metrics[index]
        local requested = tonumber(metric.width)
        if requested and requested > 0 then
            fixedWidth = fixedWidth + requested
        else
            flexibleWeight = flexibleWeight + math.max(0.001,
                tonumber(type(flexWeights) == "table" and flexWeights[index]) or 1)
        end
        if metric.presentation == "card" or metric.align == "right" then rightAlign = true end
    end
    local contentWidth = math.max(1, availableWidth - math.max(0, #indexes - 1) * gap)
    local flexibleAvailable = math.max(0, contentWidth - fixedWidth)
    local widths = {}
    for _, index in ipairs(indexes) do
        local metric = metrics[index]
        local controlWidth = tonumber(metric.width)
        if not controlWidth or controlWidth <= 0 then
            local weight = math.max(0.001,
                tonumber(type(flexWeights) == "table" and flexWeights[index]) or 1)
            controlWidth = flexibleWeight > 0 and math.max(tonumber(metric.minWidth) or 80,
                flexibleAvailable * weight / flexibleWeight) or 0
        end
        controlWidth = math.max(1, controlWidth)
        if controlWidth > availableWidth + 0.5 then
            error("responsive settings control " .. tostring(index)
                .. " resolved width exceeds its available line width", 2)
        end
        widths[index] = controlWidth
    end
    local rawRects, lineWidths, lineHeights, lineIndexes = {}, {}, {}, {}
    local cursorX, cursorY, lineHeight, line = 0, 0, 0, 1
    for _, index in ipairs(indexes) do
        local metric = metrics[index]
        local controlHeight = math.max(1, tonumber(metric.height) or SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT)
        local controlWidth = widths[index]
        if cursorX > 0 and cursorX + controlWidth > availableWidth + 0.5 then
            lineWidths[line] = math.max(0, cursorX - gap)
            lineHeights[line] = lineHeight
            cursorY = cursorY + lineHeight + gap
            cursorX, lineHeight, line = 0, 0, line + 1
        end
        rawRects[index] = { x = cursorX, y = cursorY, width = controlWidth, height = controlHeight }
        lineIndexes[index] = line
        cursorX = cursorX + controlWidth + gap
        lineHeight = math.max(lineHeight, controlHeight)
    end
    if #indexes > 0 then
        lineWidths[line] = math.max(0, cursorX - gap)
        lineHeights[line] = lineHeight
    end
    local rects = {}
    for _, index in ipairs(indexes) do
        local raw = rawRects[index]
        local physicalLine = lineIndexes[index]
        rects[index] = {
            x = x + (rightAlign
                and math.max(0, availableWidth - (lineWidths[physicalLine] or availableWidth)) or 0) + raw.x,
            y = y + raw.y
                + math.max(0, ((lineHeights[physicalLine] or raw.height) - raw.height) * 0.5),
            width = raw.width, height = raw.height,
        }
    end
    return rects, (#indexes > 0 and (cursorY + lineHeight) or 0)
end

local function FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
    local paddingX = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
        and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X or SETTINGS_LIST_ROW_PADDING_X
    for index, metric in ipairs(metrics) do
        if metric.visible == false then
            rects[index] = {
                x = width - paddingX,
                y = math.floor(height * 0.5 + 0.5),
                width = 1, height = math.max(1, tonumber(metric.height) or 1),
            }
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", paddingX, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -paddingX, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, rects
end

local function ResolveSettingsVoiceFlexWeights(metrics, indexes)
    local includesSource = false
    local flexibleContent = {}
    for _, index in ipairs(indexes) do
        if index == 2 then
            includesSource = true
        elseif index >= 3 and index < #metrics then
            local requested = tonumber(metrics[index].width)
            if not requested or requested <= 0 then flexibleContent[#flexibleContent + 1] = index end
        end
    end
    if not includesSource or #flexibleContent == 0 then return nil end
    local weights = { [2] = 1.08 }
    local candidateWeight = 1 / #flexibleContent
    for _, index in ipairs(flexibleContent) do weights[index] = candidateWeight end
    return weights
end

local function UpdateSettingsExbossCardChoicesLayout(row, width, metrics, containerWidth)
    local visible = {}
    for index, metric in ipairs(metrics) do
        if metric.visible ~= false then
            if metric.presentation ~= "card" then return nil end
            visible[#visible + 1] = index
        end
    end
    if #visible ~= 3 then return nil end
    local paddingX = SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
    local paddingY = SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y
    local gap = SETTINGS_LIST_EXBOSS_CARD_GAP
    local innerWidth = math.max(1, width - paddingX * 2)
    local stacked = containerWidth <= SETTINGS_LIST_EXBOSS_CARD_STACK_BREAKPOINT
    local controlWidth = stacked and innerWidth or math.max(1, (innerWidth - gap * 2) / 3)
    local rects, y, maxHeight = {}, paddingY, 0
    for position, index in ipairs(visible) do
        local controlHeight = math.max(1, tonumber(metrics[index].height) or SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT)
        if stacked then
            rects[index] = { x = paddingX, y = y, width = controlWidth, height = controlHeight }
            y = y + controlHeight + (position < #visible and gap or 0)
        else
            rects[index] = {
                x = paddingX + (position - 1) * (controlWidth + gap),
                y = paddingY, width = controlWidth, height = controlHeight,
            }
        end
        maxHeight = math.max(maxHeight, controlHeight)
    end
    local contentHeight = stacked and (y - paddingY) or maxHeight
    local height = math.max(row._exSettingsRowMinHeight, paddingY * 2 + contentHeight)
    return FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
end

local function UpdateSettingsHTMLWideControlsLayout(row, width, metrics, mode)
    local label = metrics[1]
    if not label or label.visible == false or label.role ~= "label" then
        error("responsive settings controls require declared control 1 to be the visible label", 2)
    end
    local controls = {}
    for index = 2, #metrics do
        if metrics[index].visible ~= false then controls[#controls + 1] = index end
    end
    local paddingX = SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
    local innerWidth = math.max(1, width - paddingX * 2)
    local columnGap = mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_COLUMN_GAP or SETTINGS_LIST_EXBOSS_FIELD_COLUMN_GAP
    local labelRatio = mode == "compactVoice" and (0.66 / 2.66) or (0.83 / 2)
    local columnsWidth = math.max(1, innerWidth - columnGap)
    local labelWidth = math.max(1, columnsWidth * labelRatio)
    local controlsX = paddingX + labelWidth + columnGap
    local controlsWidth = math.max(1, columnsWidth - labelWidth)
    local paddingY = mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y or SETTINGS_LIST_EXBOSS_FIELD_PADDING_Y
    local controlGap = mode == "compactVoice" and SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP or 8
    local flexWeights = mode == "compactVoice"
        and ResolveSettingsVoiceFlexWeights(metrics, controls) or nil
    local controlRects, controlsHeight = ResolveSettingsControlLine(
        metrics, controls, controlsX, controlsWidth, paddingY, controlGap, flexWeights)
    local labelHeight = math.max(1, tonumber(label.height) or SETTINGS_LIST_TEXT_ROW_HEIGHT)
    local contentHeight = math.max(labelHeight, controlsHeight)
    local minimum = mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_ROW_HEIGHT or SETTINGS_LIST_EXBOSS_FIELD_ROW_HEIGHT
    local height = math.max(minimum, paddingY * 2 + contentHeight)
    local rects = controlRects
    rects[1] = {
        x = paddingX,
        y = math.floor((height - labelHeight) * 0.5 + 0.5),
        width = labelWidth, height = labelHeight,
    }
    local controlsOffset = math.max(0, math.floor((height - controlsHeight) * 0.5 + 0.5) - paddingY)
    if controlsOffset > 0 then
        for _, index in ipairs(controls) do controlRects[index].y = controlRects[index].y + controlsOffset end
    end
    return FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
end

local function UpdateSettingsHTMLControlsLayout(row, width, metrics, mode, containerWidth)
    local label = metrics[1]
    if not label or label.visible == false or label.role ~= "label" then
        error("responsive settings controls require declared control 1 to be the visible label", 2)
    end
    local lines = { { 1 } }
    if mode == "compactVoice" and containerWidth <= SETTINGS_LIST_COMPACT_VOICE_SOURCE_BREAKPOINT then
        local source = metrics[2]
        if source and source.visible ~= false then lines[#lines + 1] = { 2 } end
        local contentLine = {}
        for index = 3, #metrics do
            if metrics[index].visible ~= false then contentLine[#contentLine + 1] = index end
        end
        if #contentLine > 0 then lines[#lines + 1] = contentLine end
    else
        local controlsLine = {}
        for index = 2, #metrics do
            if metrics[index].visible ~= false then controlsLine[#controlsLine + 1] = index end
        end
        if #controlsLine > 0 then lines[#lines + 1] = controlsLine end
    end

    local exbossProfile = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    local paddingY = exbossProfile and (mode == "fieldRow" and 10
        or SETTINGS_LIST_EXBOSS_VOICE_PADDING_Y) or SETTINGS_LIST_ROW_PADDING_Y
    local lineGap = exbossProfile and (mode == "compactVoice" and 7 or 8) or 8
    local controlGap = exbossProfile and mode == "compactVoice"
        and SETTINGS_LIST_EXBOSS_VOICE_CONTROL_GAP or 8
    local rects = {}
    local y = paddingY
    local paddingX = exbossProfile and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X
    for lineIndex, indexes in ipairs(lines) do
        local x = lineIndex == 1 and paddingX
            or (paddingX + SETTINGS_LIST_NARROW_CONTROL_INDENT)
        local availableWidth = math.max(1, width - x - paddingX)
        local flexWeights = mode == "compactVoice"
            and ResolveSettingsVoiceFlexWeights(metrics, indexes) or nil
        local lineRects, lineHeight = ResolveSettingsControlLine(
            metrics, indexes, x, availableWidth, y, controlGap, flexWeights)
        for index, rect in pairs(lineRects) do rects[index] = rect end
        y = y + lineHeight
        if lineIndex < #lines then y = y + lineGap end
    end
    local height = math.max(row._exSettingsRowMinHeight, y + paddingY)
    return FinishSettingsHTMLControlsLayout(row, width, metrics, rects, height)
end

function EXUI:UpdateSettingsRowControlsLayout(row, width, metrics, containerWidth)
    if not row then return 0, {} end
    metrics = type(metrics) == "table" and metrics or {}
    width = math.max(1, tonumber(width) or 1)
    containerWidth = math.max(1, tonumber(containerWidth) or width)
    local htmlLayout = row._exSettingsRowHTMLControlsLayout
    local exbossProfile = row._exSettingsRowPresentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    if exbossProfile then
        local cardHeight, cardRects = UpdateSettingsExbossCardChoicesLayout(
            row, width, metrics, containerWidth)
        if cardHeight then return cardHeight, cardRects end
    end
    if exbossProfile and (htmlLayout == "fieldRow" or htmlLayout == "compactVoice") then
        local breakpoint = htmlLayout == "fieldRow" and SETTINGS_LIST_FIELD_ROW_BREAKPOINT
            or SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
        if containerWidth > breakpoint then
            return UpdateSettingsHTMLWideControlsLayout(row, width, metrics, htmlLayout)
        end
        return UpdateSettingsHTMLControlsLayout(row, width, metrics, htmlLayout, containerWidth)
    end
    local narrowHTML = htmlLayout == "fieldRow" and containerWidth <= SETTINGS_LIST_FIELD_ROW_BREAKPOINT
        or htmlLayout == "compactVoice" and containerWidth <= SETTINGS_LIST_COMPACT_VOICE_BREAKPOINT
    if narrowHTML then
        return UpdateSettingsHTMLControlsLayout(row, width, metrics, htmlLayout, containerWidth)
    end
    if row._exSettingsRowContentWidth == "intrinsic"
        and row._exSettingsRowSingleLineControls == true then
        return UpdateSettingsSingleLineControlsLayout(row, width, metrics)
    end
    local gap = 8
    local rowPaddingX = exbossProfile and SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X
        or SETTINGS_LIST_ROW_PADDING_X
    local innerWidth = math.max(1, width - rowPaddingX * 2)
    local title = row._exSettingsRowTitle
    local description = row._exSettingsRowDescription
    local hasText = title:IsShown() or description:IsShown()
    local labelIndex, rightAlign
    for index, metric in ipairs(metrics) do
        local visible = metric.visible ~= false
        if visible and (metric.presentation == "card" or metric.align == "right") then rightAlign = true end
        if metric.role ~= nil and metric.role ~= "label" then
            error("unknown settings row control role: " .. tostring(metric.role), 2)
        elseif visible and metric.role == "label" then
            if labelIndex then error("settings row controls only support one label role", 2) end
            labelIndex = index
        end
    end
    local hasLeft = hasText or labelIndex ~= nil
    local textWidth = hasLeft and math.max(80,
        math.min(280, innerWidth * 0.38)) or 0
    local controlsX = rowPaddingX
    local controlsWidth = innerWidth
    if hasLeft then
        controlsX = controlsX + textWidth + SETTINGS_LIST_COLUMN_GAP
        controlsWidth = math.max(1, innerWidth - textWidth - SETTINGS_LIST_COLUMN_GAP)
    end
    local controlIndexes, fixedWidth, flexible, flexibleMin = {}, 0, 0, 80
    for index, metric in ipairs(metrics) do
        if metric.visible ~= false and index ~= labelIndex then
            controlIndexes[#controlIndexes + 1] = index
            local metricWidth = tonumber(metric.width)
            if metricWidth and metricWidth > 0 then fixedWidth = fixedWidth + metricWidth
            else
                flexible = flexible + 1
                flexibleMin = math.max(flexibleMin, tonumber(metric.minWidth) or 0)
            end
        end
    end
    local available = math.max(1,
        controlsWidth - math.max(0, #controlIndexes - 1) * gap)
    local flexibleWidth = flexible > 0
        and math.max(flexibleMin, (available - fixedWidth) / flexible) or 0
    local rawRects, lines, lineHeights, lineIndexes, x, y, lineHeight, line = {}, {}, {}, {}, 0, 0, 0, 1
    for _, index in ipairs(controlIndexes) do
        local metric = metrics[index]
        local controlWidth = tonumber(metric.width)
        if not controlWidth or controlWidth <= 0 then controlWidth = flexibleWidth end
        controlWidth = math.min(controlsWidth, math.max(1, controlWidth))
        local controlHeight = math.max(1, tonumber(metric.height) or SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT)
        if x > 0 and x + controlWidth > controlsWidth + 0.5 then
            lines[line] = math.max(0, x - gap)
            lineHeights[line] = lineHeight
            y = y + lineHeight + gap
            x, lineHeight, line = 0, 0, line + 1
        end
        rawRects[index] = { x = x, y = y, width = controlWidth, height = controlHeight }
        lineIndexes[index] = line
        x = x + controlWidth + gap
        lineHeight = math.max(lineHeight, controlHeight)
    end
    if #controlIndexes > 0 then
        lines[line] = math.max(0, x - gap)
        lineHeights[line] = lineHeight
    end
    local controlsHeight = #controlIndexes > 0 and (y + lineHeight) or 0
    local labelHeight = labelIndex and math.max(1, tonumber(metrics[labelIndex].height) or SETTINGS_LIST_TEXT_ROW_HEIGHT) or 0
    local textHeight = SettingsTextHeight(title, math.max(1, textWidth))
    if description:IsShown() then
        textHeight = textHeight + (textHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0)
            + SettingsTextHeight(description, math.max(1, textWidth))
    end
    local rowPaddingY = exbossProfile and SETTINGS_LIST_EXBOSS_SIMPLE_PADDING_Y
        or SETTINGS_LIST_ROW_PADDING_Y
    local height = math.max(row._exSettingsRowMinHeight,
        rowPaddingY * 2 + math.max(textHeight, labelHeight, controlsHeight))
    if description:IsShown() then height = math.max(height, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT) end
    local rects = {}
    local controlsTop = math.floor((height - controlsHeight) * 0.5 + 0.5)
    for _, index in ipairs(controlIndexes) do
        local rect = rawRects[index]
        rects[index] = {
            x = controlsX + (rightAlign
                and math.max(0, controlsWidth - (lines[lineIndexes[index]] or controlsWidth)) or 0) + rect.x,
            y = controlsTop + rect.y
                + math.max(0, ((lineHeights[lineIndexes[index]] or rect.height) - rect.height) * 0.5),
            width = rect.width,
            height = rect.height,
        }
    end
    if labelIndex then
        rects[labelIndex] = {
            x = rowPaddingX,
            y = math.floor((height - labelHeight) * 0.5 + 0.5),
            width = textWidth,
            height = labelHeight,
        }
    end
    for index, metric in ipairs(metrics) do
        if metric.visible == false then
            rects[index] = {
                x = controlsX + controlsWidth,
                y = math.floor(height * 0.5 + 0.5),
                width = 1,
                height = math.max(1, tonumber(metric.height) or 1),
            }
        end
    end
    if hasText then
        local textTop = math.floor((height - textHeight) * 0.5 + 0.5)
        title:ClearAllPoints()
        if title:IsShown() then
            title:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop)
            title:SetWidth(textWidth)
        end
        description:ClearAllPoints()
        if description:IsShown() then
            if title:IsShown() then
                description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
            else description:SetPoint("TOPLEFT", row, "TOPLEFT", rowPaddingX, -textTop) end
            description:SetWidth(textWidth)
        end
    end
    row:SetSize(width, height)
    local divider = row._exSettingsRowDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", rowPaddingX, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -rowPaddingX, 0)
    divider:SetShown(not row._exSettingsRowIsLast)
    EXUI:ClearControlSurface(row)
    return height, rects
end

-- Settings-list owners may recompute the last visible row after dynamic layout.
-- This changes only the shared decorative divider, never widget visibility.
function EXUI:SetSettingsRowLast(row, isLast)
    if not row then return false end
    if row._exSettingsRowDivider then
        row._exSettingsRowIsLast = isLast == true
        row._exSettingsRowDivider:SetShown(not row._exSettingsRowIsLast)
        return true
    end
    if row._exSettingsTableDivider then
        row._exSettingsTableIsLast = isLast == true
        row._exSettingsTableDivider:SetShown(not row._exSettingsTableIsLast)
        return true
    end
    return false
end

function EXUI:SetSettingsCardGroupMemberLast(card, isLast)
    if not card or not card._exSettingsGroupDivider then return false end
    card._exSettingsGroupDivider:SetShown(isLast ~= true)
    return true
end

local function ResolveSettingsTableColumns(width, columns)
    width = math.max(1, tonumber(width) or 1)
    columns = type(columns) == "table" and columns or {}
    local gap = 12
    local available = math.max(1,
        width - SETTINGS_LIST_ROW_PADDING_X * 2 - math.max(0, #columns - 1) * gap)
    local fixed, totalWeight = 0, 0
    for _, column in ipairs(columns) do
        local columnWidth = tonumber(column.width)
        if columnWidth and columnWidth > 0 then fixed = fixed + columnWidth
        else totalWeight = totalWeight + math.max(0.01, tonumber(column.weight) or 1) end
    end
    local weighted = math.max(1, available - fixed)
    local rects, x = {}, SETTINGS_LIST_ROW_PADDING_X
    for index, column in ipairs(columns) do
        local columnWidth = tonumber(column.width)
        if not columnWidth or columnWidth <= 0 then
            columnWidth = weighted * math.max(0.01, tonumber(column.weight) or 1) / totalWeight
        end
        rects[index] = { x = x, width = math.max(1, columnWidth) }
        x = x + columnWidth + gap
    end
    return rects
end

-- Pure shared column geometry for settings-form groups whose original controls
-- remain mounted in separate card bodies. No frames, bindings or values are
-- created or changed here.
function EXUI:ResolveSettingsTableColumns(width, columns)
    return ResolveSettingsTableColumns(width, columns)
end

function EXUI:CreateSettingsTableHeader(parent, options)
    options = type(options) == "table" and options or {}
    local header, isNew = AcquireCompositeGroup("CompositeSettingsTableHeader", parent)
    if isNew then
        header:EnableMouse(false)
        header._exSettingsTableLabels = {}
        header.Release = ReleaseSettingsListDecoration
    end
    header._exSettingsTableColumns = {}
    for index, column in ipairs(options.columns or {}) do
        header._exSettingsTableColumns[index] = {
            title = tostring(column.title or ""),
            width = tonumber(column.width),
            weight = tonumber(column.weight),
        }
        local label = header._exSettingsTableLabels[index]
        if not label then
            label = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontHighlightSmall")
            header._exSettingsTableLabels[index] = label
        end
        label:SetJustifyH("LEFT")
        label:SetText(header._exSettingsTableColumns[index].title)
        label:Show()
        MODERN.Font(label, GM.font.label, SETTINGS_LIST_TITLE, "", "GameFontHighlightSmall")
    end
    for index = #(options.columns or {}) + 1, #header._exSettingsTableLabels do
        header._exSettingsTableLabels[index]:Hide()
    end
    return header
end

function EXUI:UpdateSettingsTableHeaderLayout(header, width)
    if not header then return 0, {} end
    local rects = ResolveSettingsTableColumns(width, header._exSettingsTableColumns)
    local height = 38
    header:SetSize(math.max(1, tonumber(width) or 1), height)
    for index, rect in ipairs(rects) do
        local label = header._exSettingsTableLabels[index]
        label:ClearAllPoints()
        label:SetPoint("LEFT", header, "LEFT", rect.x, 0)
        label:SetWidth(rect.width)
    end
    return height, rects
end

function EXUI:CreateSettingsTableRow(parent, options)
    options = type(options) == "table" and options or {}
    local row, isNew = AcquireCompositeGroup("CompositeSettingsTableRow", parent)
    if isNew then
        row:EnableMouse(false)
        row._exSettingsTableStaticLabels = {}
        local divider = CreateSettingsDivider(row)
        row._exSettingsTableDivider = divider
        row.Release = ReleaseSettingsListDecoration
    end
    row._exSettingsTableIsLast = options.isLast == true
    row._exSettingsTableIcons = row._exSettingsTableIcons or {}
    local shown = {}
    for column, value in pairs(options.staticCells or {}) do
        if type(column) == "number" and value ~= nil then
            local label = row._exSettingsTableStaticLabels[column]
            if not label then
                label = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
                label:SetJustifyH("LEFT")
                row._exSettingsTableStaticLabels[column] = label
            end
            local cell = type(value) == "table" and value or {text=value}
            label:SetText(tostring(cell.text or ""))
            local icon = row._exSettingsTableIcons[column]
            if cell.icon and not icon then
                icon = CreateFrame("Frame", nil, row)
                icon:SetSize(GM.size.controlHeight, GM.size.controlHeight)
                -- 物品图标走公共圆角图片封装；matchSurface 复用公共圆角遮罩，
                -- 不给图标另加描边，外观只从直角方图变成公共控件圆角。
                icon.image = EXUI:CreateRoundedImage(icon, GM.radius.control, true)
                icon.image:SetAllPoints()
                icon:SetScript("OnEnter", function(self)
                    if not self.itemID then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:Show()
                end)
                icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
                icon:SetScript("OnHide", function(self)
                    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
                end)
                row._exSettingsTableIcons[column] = icon
            end
            if icon then
                icon.itemID = cell.itemID
                icon:EnableMouse(cell.itemID ~= nil)
                icon.image:SetTexture(cell.icon)
                icon:SetShown(cell.icon ~= nil)
            end
            label:Show()
            MODERN.ApplyTextRole(label, "title", SETTINGS_LIST_TITLE)
            shown[column] = true
        end
    end
    for column, label in pairs(row._exSettingsTableStaticLabels) do
        if not shown[column] then
            label:Hide()
            local icon = row._exSettingsTableIcons[column]
            if icon then icon.itemID=nil; icon:Hide() end
        end
    end
    row._exSettingsTableDivider:SetShown(not row._exSettingsTableIsLast)
    EXUI:ClearControlSurface(row)
    return row
end

function EXUI:UpdateSettingsTableRowLayout(row, width, columns, metrics)
    if not row then return 0, {} end
    columns = type(columns) == "table" and columns or {}
    metrics = type(metrics) == "table" and metrics or {}
    local height = 48
    for _, metric in ipairs(metrics) do
        if not metric or metric.visible ~= false then
            height = math.max(height, math.max(1, tonumber(metric and metric.height) or 1) + 16)
        end
    end
    row:SetSize(math.max(1, tonumber(width) or 1), height)
    local rects = {}
    for index, column in ipairs(columns) do
        local metric = metrics[index] or {}
        local cellHeight = math.max(1, tonumber(metric.height) or SETTINGS_LIST_DEFAULT_CONTROL_HEIGHT)
        rects[index] = {
            x = column.x + 4,
            y = math.floor((height - cellHeight) * 0.5 + 0.5),
            width = math.max(1, column.width - 8),
            height = cellHeight,
        }
        local label = row._exSettingsTableStaticLabels[index]
        if label and label:IsShown() then
            local icon = row._exSettingsTableIcons[index]
            local inset = 0
            if icon and icon:IsShown() then
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", row, "LEFT", column.x + 4, 0)
                inset = GM.size.controlHeight + 8
            end
            label:ClearAllPoints()
            label:SetPoint("LEFT", row, "LEFT", column.x + 4 + inset, 0)
            label:SetWidth(math.max(1, column.width - 8 - inset))
        end
    end
    local divider = row._exSettingsTableDivider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -SETTINGS_LIST_ROW_PADDING_X, 0)
    divider:SetShown(not row._exSettingsTableIsLast)
    return height, rects
end

local function CaptureRegionPoints(region)
    local points = {}
    if not region or not region.GetNumPoints then return points end
    for index = 1, region:GetNumPoints() do
        points[index] = { region:GetPoint(index) }
    end
    return points
end

local function RestoreRegionPoints(region, points)
    if not region or not region.ClearAllPoints then return end
    region:ClearAllPoints()
    for _, point in ipairs(points or {}) do region:SetPoint(unpack(point)) end
end

local function CaptureControlSurfaceState(frame)
    local state = {}
    for radius, skin in pairs(frame and frame._exModernSurfaces or {}) do
        local saved = { pieces = {} }
        for index, piece in ipairs(skin.pieces or {}) do
            local r, g, b, a = piece.texture:GetVertexColor()
            saved.pieces[index] = {
                shown = piece.texture:IsShown(), alpha = piece.texture:GetAlpha(),
                color = { r, g, b, a },
            }
        end
        state[radius] = saved
    end
    return state
end

local function RestoreControlSurfaceState(frame, state)
    for radius, skin in pairs(frame and frame._exModernSurfaces or {}) do
        local saved = state and state[radius]
        if skin.Layout then skin.Layout() end
        for index, piece in ipairs(skin.pieces or {}) do
            local pieceState = saved and saved.pieces[index]
            if pieceState then
                piece.texture:SetVertexColor(unpack(pieceState.color))
                piece.texture:SetAlpha(pieceState.alpha)
                piece.texture:SetShown(pieceState.shown)
            else
                piece.texture:SetAlpha(0)
                piece.texture:Hide()
            end
        end
    end
end

local function SetControlSurfaceAlpha(frame, alpha)
    for _, skin in pairs(frame and frame._exModernSurfaces or {}) do
        for _, piece in ipairs(skin.pieces or {}) do piece.texture:SetAlpha(alpha) end
    end
end

function EXUI:PrepareSettingsListCard(card, options)
    if not card or not card._exSettingsCardBody then return false, "not-settings-card" end
    if card._exSettingsListCardState then return true end
    options = type(options) == "table" and options or {}
    local presentationProfile = options.presentationProfile
    if presentationProfile ~= nil and presentationProfile ~= SETTINGS_LIST_EXBOSS_SKILL_PROFILE then
        return false, "unknown-presentation-profile"
    end
    local exbossProfile = presentationProfile == SETTINGS_LIST_EXBOSS_SKILL_PROFILE
    local groupMember = options.groupMember == true
    local descriptionOnly = options.descriptionOnly == true and not groupMember
    local groupCollapsible = not groupMember or options.groupCollapsible ~= false
    local externalCollapsible = options.externalCollapsible == true and not groupMember
    local preserveHeader = options.preserveHeader == true or externalCollapsible or groupMember
    if exbossProfile and (groupMember or options.preserveHeader ~= true) then
        return false, "exboss-skill-profile-requires-external-header"
    end
    if not preserveHeader and not descriptionOnly and card._exSettingsCardCollapsible == true then
        return false, "collapsible-card"
    end
    if not preserveHeader and not descriptionOnly and card._exSettingsCardCollapsed == true then
        return false, "collapsed-card"
    end
    local body = card._exSettingsCardBody
    card._exSettingsListCardState = {
        mode = groupMember and (groupCollapsible and "group" or "flat")
            or (preserveHeader and "external" or "flat"),
        headerShown = card._exSettingsCardHeader:IsShown(),
        headerHeight = card._exSettingsCardHeader:GetHeight(),
        headerMouseEnabled = card._exSettingsCardHeader:IsMouseEnabled(),
        bodyShown = body:IsShown(),
        bodyPoints = CaptureRegionPoints(body),
        bodyWidth = body:GetWidth(),
        bodyHeight = body:GetHeight(),
        cardWidth = card:GetWidth(),
        cardHeight = card:GetHeight(),
        surfaces = CaptureControlSurfaceState(card),
        bodySurfaces = CaptureControlSurfaceState(body),
        headerSurfaces = CaptureControlSurfaceState(card._exSettingsCardHeader),
        titleShown = card._exSettingsCardTitle:IsShown(),
        titlePoints = CaptureRegionPoints(card._exSettingsCardTitle),
        iconShown = card._exSettingsCardIcon:IsShown(),
        iconPoints = CaptureRegionPoints(card._exSettingsCardIcon),
        toggleShown = card._exSettingsCardToggle:IsShown(),
        togglePoints = CaptureRegionPoints(card._exSettingsCardToggle),
        dividerShown = card._exSettingsCardDivider:IsShown(),
        squareBottomShown = card._exSettingsCardSquareBottom:IsShown(),
        collapsible = card._exSettingsCardCollapsible,
        collapsed = card._exSettingsCardCollapsed,
    }
    card._exSettingsListPresentationProfile = presentationProfile
    card._exSettingsListCardMode = card._exSettingsListCardState.mode
    if groupMember and groupCollapsible then
        local headerHeight = 52
        card._exSettingsListGroupMember = {
            titleColor = MC.text,
            glyphColor = MC.muted,
            headerHeight = headerHeight,
        }
        card._exSettingsCardCollapsible = true
        local header = card._exSettingsCardHeader
        header:SetHeight(headerHeight)
        header:Show()
        header:EnableMouse(true)
        card._exSettingsCardIcon:Hide()
        card._exSettingsCardTitle:ClearAllPoints()
        card._exSettingsCardTitle:SetPoint("LEFT", header, "LEFT", 20, 0)
        card._exSettingsCardTitle:SetPoint("RIGHT", card._exSettingsCardToggle, "LEFT", -8, 0)
        card._exSettingsCardTitle:Show()
        card._exSettingsCardToggle:ClearAllPoints()
        card._exSettingsCardToggle:SetPoint("RIGHT", header, "RIGHT", -16, 0)
        card._exSettingsCardToggle:Show()
        card._exSettingsCardDivider:Hide()
        card._exSettingsCardSquareBottom:Hide()
        if not card._exSettingsGroupDivider then
            card._exSettingsGroupDivider = CreateSettingsDivider(card)
        end
        local groupDivider = card._exSettingsGroupDivider
        groupDivider:ClearAllPoints()
        groupDivider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 0)
        groupDivider:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, 0)
        groupDivider:SetShown(options.isLast ~= true)
        SetControlSurfaceAlpha(header, 0)
        card._exSettingsCardPaintHeader()
    elseif groupMember then
        -- An explicitly non-collapsible settings group contributes only its
        -- existing body to the shared outer group surface.  Header interaction,
        -- configuration ownership and child controls remain untouched.
        local header = card._exSettingsCardHeader
        header:Hide()
        header:EnableMouse(externalCollapsible)
        card._exSettingsCardIcon:Hide()
        card._exSettingsCardTitle:Hide()
        card._exSettingsCardToggle:Hide()
        card._exSettingsCardDivider:Hide()
        card._exSettingsCardSquareBottom:Hide()
        card._exSettingsCardCollapsible = false
        card._exSettingsCardCollapsed = false
        body:Show()
        if not card._exSettingsGroupDivider then
            card._exSettingsGroupDivider = CreateSettingsDivider(card)
        end
        local groupDivider = card._exSettingsGroupDivider
        groupDivider:ClearAllPoints()
        groupDivider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 0)
        groupDivider:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, 0)
        groupDivider:SetShown(options.isLast ~= true)
        SetControlSurfaceAlpha(header, 0)
    elseif preserveHeader then
        -- The existing toggle remains the original object with the original
        -- click scripts. Only its geometry and the surrounding paint change.
        local title = card._exSettingsCardTitle
        local externalHeaderHeight = exbossProfile and SETTINGS_LIST_EXBOSS_HEADER_HEIGHT
            or SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT
        if not exbossProfile then
            MODERN.ApplyTextRole(title, "title", SETTINGS_LIST_TITLE)
            title:SetJustifyH("LEFT")
            title:SetJustifyV("TOP")
            title:SetWordWrap(true)
            local titleWidth = math.max(1, (tonumber(card:GetWidth()) or 1)
                - (externalCollapsible and 32 or 0))
            externalHeaderHeight = 8 + SettingsTextHeight(title, titleWidth) + 18
        end
        card._exSettingsListExternalHeader = {
            titleColor = SETTINGS_LIST_TITLE,
            glyphColor = SETTINGS_LIST_DESCRIPTION,
            height = externalHeaderHeight,
            footerPadding = exbossProfile and SETTINGS_LIST_EXBOSS_FOOTER_PADDING or 0,
        }
        local header = card._exSettingsCardHeader
        header:SetHeight(card._exSettingsListExternalHeader.height)
        header:Show()
        header:EnableMouse(false)
        if exbossProfile then
            card._exSettingsCardIcon:ClearAllPoints()
            card._exSettingsCardIcon:SetPoint("LEFT", header, "LEFT", SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X, 0)
            card._exSettingsCardIcon:Show()
        else
            card._exSettingsCardIcon:Hide()
        end
        card._exSettingsCardTitle:ClearAllPoints()
        if exbossProfile then
            card._exSettingsCardTitle:SetPoint("LEFT", card._exSettingsCardIcon, "RIGHT", 8, 0)
            card._exSettingsCardTitle:SetPoint("RIGHT", header, "RIGHT", -SETTINGS_LIST_EXBOSS_CONTENT_PADDING_X, 0)
        else
            title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -8)
            if externalCollapsible then
                title:SetPoint("TOPRIGHT", card._exSettingsCardToggle, "TOPLEFT", -8, -8)
            else
                title:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -8)
            end
        end
        card._exSettingsCardTitle:Show()
        card._exSettingsCardToggle:ClearAllPoints()
        card._exSettingsCardToggle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        -- Collapsible typed sections keep this same transparent external title
        -- geometry and the same flat body surface. The original header/toggle
        -- scripts remain the sole interaction owner; only their visibility and
        -- the existing card flag change.
        card._exSettingsCardCollapsible = externalCollapsible
        if not externalCollapsible then card._exSettingsCardCollapsed = false end
        card._exSettingsCardToggle:SetShown(externalCollapsible)
        body:SetShown(not card._exSettingsCardCollapsed)
        card._exSettingsCardDivider:Hide()
        card._exSettingsCardSquareBottom:Hide()
        SetControlSurfaceAlpha(header, 0)
        card._exSettingsCardPaintHeader()
    else
        local header = card._exSettingsCardHeader
        header:Hide()
        if descriptionOnly then
            header:EnableMouse(false)
            card._exSettingsCardIcon:Hide()
            card._exSettingsCardTitle:Hide()
            card._exSettingsCardToggle:Hide()
            card._exSettingsCardDivider:Hide()
            card._exSettingsCardSquareBottom:Hide()
            card._exSettingsCardCollapsible = false
            card._exSettingsCardCollapsed = false
            body:Show()
            SetControlSurfaceAlpha(header, 0)
        end
    end
    body:ClearAllPoints()
    local bodyTop = groupMember and (groupCollapsible and 52 or 0)
        or (preserveHeader and (card._exSettingsListExternalHeader
            and card._exSettingsListExternalHeader.height
            or (exbossProfile and SETTINGS_LIST_EXBOSS_HEADER_HEIGHT
                or SETTINGS_LIST_EXTERNAL_HEADER_HEIGHT)) or 0)
    local bodyInset = groupMember and groupCollapsible and 12 or 0
    body:SetPoint("TOPLEFT", card, "TOPLEFT", bodyInset, -bodyTop)
    body:SetPoint("TOPRIGHT", card, "TOPRIGHT", -bodyInset, -bodyTop)
    if (groupMember and groupCollapsible) or externalCollapsible then
        body:SetShown(not card._exSettingsCardCollapsed)
    else
        body:Show()
    end
    EXUI:SetControlSurface(body, GM.radius.card,
        groupMember and MC.raised or SETTINGS_LIST_CARD_FILL, SETTINGS_LIST_CARD_BORDER)
    if exbossProfile then
        EXUI:SetControlSurface(card, GM.radius.card, SETTINGS_LIST_CARD_FILL, SETTINGS_LIST_CARD_BORDER)
        SetControlSurfaceAlpha(card, 1)
        SetControlSurfaceAlpha(body, 0)
    else
        SetControlSurfaceAlpha(card, 0)
        SetControlSurfaceAlpha(body,
            (descriptionOnly or (groupMember and not groupCollapsible)) and 0 or 1)
    end
    if (groupMember and groupCollapsible) or externalCollapsible then
        card:SetCollapsed(options.collapsed == true, true)
    end
    card:SetHeight(card:GetPreferredHeight())
    return true
end

function EXUI:RestoreSettingsListCard(card)
    local state = card and card._exSettingsListCardState
    if not state then return false end
    local body = card._exSettingsCardBody
    card._exSettingsListCardMode = nil
    card._exSettingsListExternalHeader = nil
    card._exSettingsListGroupMember = nil
    card._exSettingsListPresentationProfile = nil
    card._exSettingsCardCollapsible = state.collapsible == true
    card._exSettingsCardCollapsed = state.collapsed == true
    card:SetSize(state.cardWidth, state.cardHeight)
    RestoreRegionPoints(body, state.bodyPoints)
    body:SetHeight(state.bodyHeight)
    body:SetShown(state.bodyShown)
    RestoreControlSurfaceState(body, state.bodySurfaces)
    card._exSettingsCardHeader:SetShown(state.headerShown)
    card._exSettingsCardHeader:SetHeight(state.headerHeight)
    card._exSettingsCardHeader:EnableMouse(state.headerMouseEnabled ~= false)
    RestoreControlSurfaceState(card._exSettingsCardHeader, state.headerSurfaces)
    RestoreRegionPoints(card._exSettingsCardTitle, state.titlePoints)
    MODERN.ApplyTextRole(card._exSettingsCardTitle, "cardTitle")
    card._exSettingsCardTitle:SetJustifyH("LEFT")
    card._exSettingsCardTitle:SetJustifyV("MIDDLE")
    card._exSettingsCardTitle:SetWordWrap(false)
    card._exSettingsCardTitle:SetShown(state.titleShown)
    RestoreRegionPoints(card._exSettingsCardIcon, state.iconPoints)
    card._exSettingsCardIcon:SetShown(state.iconShown)
    RestoreRegionPoints(card._exSettingsCardToggle, state.togglePoints)
    card._exSettingsCardToggle:SetShown(state.toggleShown)
    card._exSettingsCardDivider:SetShown(state.dividerShown)
    card._exSettingsCardSquareBottom:SetShown(state.squareBottomShown)
    card._exSettingsCardToggle._exGlyph:SetText(state.collapsed and "v" or "^")
    RestoreControlSurfaceState(card, state.surfaces)
    card._exSettingsListCardState = nil
    if card._exSettingsGroupDivider then card._exSettingsGroupDivider:Hide() end
    card._exSettingsCardPaintHeader()
    return true
end

function EXUI:CreateSettingsCardGroupSurface(parent, options)
    local surface, isNew = AcquireCompositeGroup("CompositeSettingsCardGroupSurface", parent)
    if isNew then
        surface:EnableMouse(false)
        surface.Release = ReleaseSettingsListDecoration
    end
    if parent and surface.SetFrameLevel and parent.GetFrameLevel then
        surface:SetFrameLevel(parent:GetFrameLevel())
    end
    if parent and surface.SetFrameStrata and parent.GetFrameStrata then
        surface:SetFrameStrata(parent:GetFrameStrata())
    end
    EXUI:SetControlSurface(surface, GM.radius.card, MC.panel, MC.border)
    surface:Show()
    return surface
end

function EXUI:UpdateSettingsCardGroupSurfaceLayout(surface, width, height)
    if not surface then return 0 end
    width = math.max(1, tonumber(width) or 1)
    height = math.max(1, tonumber(height) or 1)
    surface:SetSize(width, height)
    EXUI:SetControlSurface(surface, GM.radius.card, MC.panel, MC.border)
    return height
end

-- 非 ordinary 路径下复选框的摆放高度；PrepareSettingsListControl 摆放与
-- BuildModuleCommonSettingsFlow 测量共用这一个函数，保证两处同源同值。
local function ResolveSettingsListCheckboxHeight(presentation)
    return GM.size.controlHeight
end

local SETTINGS_LIST_BORROWED_KINDS = {
    input = true, switch = true, select = true, color = true,
    button = true, text = true, multiline = true,
}

function EXUI:RestoreSettingsListControl(widget)
    local state = widget and widget._exSettingsListVisualState
    if not state then return false end
    if state.hasSettingsListHeight then
        widget._exGridFixedHeight = state.settingsListFixedHeight
        widget:SetHeight(state.settingsListHeight)
    end
    widget._exSettingsOrdinaryControl = state.ordinaryControl
    widget._exSettingsTextRole = state.textRole
    widget._exSettingsBorrowedKind = state.borrowedKind
    for _, entry in ipairs(state.labels or {}) do
        if entry.region and entry.region.SetShown then entry.region:SetShown(entry.shown) end
    end
    local role = state.roleLabel
    if role and role.region then
        local region = role.region
        region:SetText(role.text)
        RestoreRegionPoints(region, role.points)
        if role.fontPath then region:SetFont(role.fontPath, role.fontSize, role.fontFlags) end
        region:SetTextColor(unpack(role.color))
        if region.SetShadowColor and role.shadowColor then region:SetShadowColor(unpack(role.shadowColor)) end
        if region.SetShadowOffset and role.shadowX then region:SetShadowOffset(role.shadowX, role.shadowY) end
        if region.SetJustifyH and role.justifyH then region:SetJustifyH(role.justifyH) end
        if region.SetJustifyV and role.justifyV then region:SetJustifyV(role.justifyV) end
        if role.widgetHeight then widget:SetHeight(role.widgetHeight) end
    end
    local tableTextRole = state.roleTableText
    if tableTextRole and tableTextRole.region then
        local region = tableTextRole.region
        RestoreRegionPoints(region, tableTextRole.points)
        if tableTextRole.fontPath then
            region:SetFont(tableTextRole.fontPath, tableTextRole.fontSize, tableTextRole.fontFlags)
        end
        region:SetTextColor(unpack(tableTextRole.color))
        if region.SetShadowColor and tableTextRole.shadowColor then
            region:SetShadowColor(unpack(tableTextRole.shadowColor))
        end
        if region.SetShadowOffset and tableTextRole.shadowX then
            region:SetShadowOffset(tableTextRole.shadowX, tableTextRole.shadowY)
        end
        region:SetJustifyH(tableTextRole.justifyH or "LEFT")
        region:SetJustifyV(tableTextRole.justifyV or "TOP")
        region:SetWordWrap(tableTextRole.wordWrap == true)
        if region.SetMaxLines and tableTextRole.maxLines ~= nil then
            region:SetMaxLines(tableTextRole.maxLines)
        end
    end
    local descriptionRole = state.roleDescription
    if descriptionRole and descriptionRole.region then
        local region = descriptionRole.region
        region:SetSize(descriptionRole.width, descriptionRole.height)
        RestoreRegionPoints(region, descriptionRole.points)
        if descriptionRole.fontPath then
            region:SetFont(descriptionRole.fontPath, descriptionRole.fontSize, descriptionRole.fontFlags)
        end
        region:SetTextColor(unpack(descriptionRole.color))
        if region.SetShadowColor and descriptionRole.shadowColor then
            region:SetShadowColor(unpack(descriptionRole.shadowColor))
        end
        if region.SetShadowOffset and descriptionRole.shadowX then
            region:SetShadowOffset(descriptionRole.shadowX, descriptionRole.shadowY)
        end
        region:SetJustifyH(descriptionRole.justifyH or "LEFT")
        region:SetJustifyV(descriptionRole.justifyV or "TOP")
        region:SetWordWrap(descriptionRole.wordWrap == true)
        if region.SetMaxLines and descriptionRole.maxLines ~= nil then
            region:SetMaxLines(descriptionRole.maxLines)
        end
    end
    local box = widget.checkbox
    if box and state.checkbox then
        widget._exSettingsPresentation = state.presentation
        widget._exSettingsCardDescription = state.cardDescription
        widget._exSettingsCardIcon = state.cardIcon
        widget._exSettingsCardCheckSize = state.cardCheckSize
        widget._exSettingsCardTextSize = state.cardTextSize
        widget._exSettingsCardVisualPending = nil
        box:SetSize(state.checkbox.width, state.checkbox.height)
        RestoreRegionPoints(box, state.checkbox.points)
        if widget.label and state.checkbox.labelPoints then
            RestoreRegionPoints(widget.label, state.checkbox.labelPoints)
            widget.label:SetJustifyH(state.checkbox.labelJustify or "LEFT")
            widget.label:SetShown(state.checkbox.labelShown ~= false)
        end
        if box._exSettingsCardLabel then box._exSettingsCardLabel:Hide() end
        PaintModernCheckbox(widget, nil, true)
    end
    if state.buttonVariant then
        -- 走公共入口归一化，避免这里和 CreateButton 的变体语义分叉。
        EXUI:SetButtonVariant(widget, state.buttonVariant, true)
        PaintModernButton(widget)
    end
    if state.sliderLayout then
        local sliderState = state.sliderLayout
        widget._exSettingsValuePosition = sliderState.valuePosition
        widget._exGridFixedHeight = sliderState.fixedHeight
        widget:SetSize(sliderState.width, sliderState.height)
        local input = widget.numberInput
        if input then
            RestoreRegionPoints(input, sliderState.inputPoints)
            input:SetSize(sliderState.inputWidth, sliderState.inputHeight)
        end
        local interactive = widget.Slider
        if interactive and sliderState.interactivePoints then
            RestoreRegionPoints(interactive, sliderState.interactivePoints)
            interactive:SetSize(sliderState.interactiveWidth, sliderState.interactiveHeight)
        end
    end
    widget._exSettingsListVisualState = nil
    return true
end

-- Reflow only the original GridSlider and its original number EditBox.  The
-- numeric value, formatter, interaction scripts and lifecycle callbacks remain
-- owned by CreateSlider.
function EXUI:UpdateSettingsListControlLayout(widget, width)
    if not widget then return 0 end
    width = math.max(1, tonumber(width) or widget:GetWidth() or 1)
    local borrowedKind = widget._exSettingsBorrowedKind
    if widget._exSettingsOrdinaryControl == true and borrowedKind ~= nil then
        widget:SetSize(width, SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT)
        widget._exGridFixedHeight = SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
        return SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT, width
    elseif borrowedKind == "text" or borrowedKind == "multiline" then
        widget:SetWidth(width)
        return math.max(1, widget:GetHeight()), width
    end
    if widget._gridType == "GridSlider" and widget._exSettingsValuePosition == "right"
        and widget.numberInput then
        local height = math.max(SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT, SLIDER_NUMBER_INPUT_HEIGHT)
        local gap, inputWidth, trackWidth
        if widget._exSettingsOrdinaryControl == true then
            gap = math.min(10, math.max(0, width - 2))
            inputWidth = math.min(SLIDER_NUMBER_INPUT_WIDTH, math.max(1, width - gap - 1))
            trackWidth = math.max(1, width - gap - inputWidth)
        else
            gap, inputWidth = 10, SLIDER_NUMBER_INPUT_WIDTH
            trackWidth = math.max(80, width - gap - inputWidth)
        end
        widget:SetSize(trackWidth, height)
        widget._exGridFixedHeight = height
        local input = widget.numberInput
        input:ClearAllPoints()
        input:SetPoint("LEFT", widget, "RIGHT", gap, 0)
        input:SetSize(inputWidth, SLIDER_NUMBER_INPUT_HEIGHT)
        local interactive = widget.Slider
        if interactive then
            interactive:ClearAllPoints()
            interactive:SetPoint("LEFT", widget, "LEFT", 0, 0)
            interactive:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            interactive:SetHeight(GM.size.controlHeight)
        end
        return height, width
    end
    if widget._exSettingsOrdinaryControl == true
        and (widget._gridType == "GridButton" or widget._gridType == "GridInput" or widget._gridType == "GridDropdown"
            or widget._gridType == "GridLSMDropdown" or widget._gridType == "GridMultiselect"
            or widget._gridType == "GridColorButton") then
        widget:SetSize(width, SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT)
        widget._exGridFixedHeight = SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
        -- Repaint against the final first-pass geometry as well as later
        -- reflows. This synchronizes the surface slices even when a pooled
        -- dropdown happens to be assigned the same root width it held before.
        if widget._gridType == "GridButton" then
            PaintModernButton(widget)
        elseif widget._gridType == "GridInput" then
            PaintModernInput(widget, widget)
        elseif widget._gridType == "GridColorButton" then
            PaintModernButton(widget)
        else
            PaintModernDropdown(widget)
        end
        return SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT, width
    end
    widget:SetWidth(width)
    return math.max(1, widget:GetHeight()), width
end

function EXUI:PrepareSettingsListControl(widget, options)
    if not widget then return false end
    options = type(options) == "table" and options or {}
    if widget._exSettingsListVisualState then self:RestoreSettingsListControl(widget) end
    -- hideLabel and checkbox presentations can both act on the same FontString.
    -- Capture its lease-entry visibility before either path hides it, so restore
    -- never mistakes a temporary presentation state for the original state.
    local checkboxLabelShown = widget.label and widget.label.IsShown
        and widget.label:IsShown()
    local borrowedKind = options.borrowedKind
    if borrowedKind ~= nil then
        if SETTINGS_LIST_BORROWED_KINDS[borrowedKind] ~= true then
            error("unknown borrowed settings-list control kind: " .. tostring(borrowedKind), 2)
        end
        if widget._gridType ~= nil then
            error("borrowed settings-list control kind requires an original control without _gridType", 2)
        end
    end
    local state = {
        labels = {},
        presentation = widget._exSettingsPresentation,
        cardDescription = widget._exSettingsCardDescription,
        cardIcon = widget._exSettingsCardIcon,
        cardCheckSize = widget._exSettingsCardCheckSize,
        cardTextSize = widget._exSettingsCardTextSize,
        ordinaryControl = widget._exSettingsOrdinaryControl,
        textRole = widget._exSettingsTextRole,
        borrowedKind = widget._exSettingsBorrowedKind,
    }
    widget._exSettingsBorrowedKind = borrowedKind
    local function SetSettingsListHeight(height)
        if not state.hasSettingsListHeight then
            state.hasSettingsListHeight = true
            state.settingsListHeight = widget:GetHeight()
            state.settingsListFixedHeight = widget._exGridFixedHeight
        end
        widget._exGridFixedHeight = height
        widget:SetHeight(height)
    end
    local isSingleLineInput = widget._gridType == "GridInput"
        and widget.IsMultiLine and not widget:IsMultiLine()
    local isOrdinaryRectangle = isSingleLineInput or widget._gridType == "GridButton" or widget._gridType == "GridDropdown"
        or widget._gridType == "GridLSMDropdown" or widget._gridType == "GridMultiselect"
        or widget._gridType == "GridColorButton"
    local isOrdinarySlider = widget._gridType == "GridSlider" and options.valuePosition == "right"
    local isBorrowedOrdinary = borrowedKind ~= nil
        and borrowedKind ~= "text" and borrowedKind ~= "multiline"
    widget._exSettingsOrdinaryControl = options.ordinaryControl == true
        and (isOrdinaryRectangle or isOrdinarySlider or isBorrowedOrdinary) or nil
    if widget._exSettingsOrdinaryControl and (isOrdinaryRectangle or isBorrowedOrdinary) then
        SetSettingsListHeight(SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT)
    elseif isSingleLineInput or widget._gridType == "GridColorButton" then
        SetSettingsListHeight(isSingleLineInput and GM.size.inputHeight or GM.size.colorButtonHeight)
    elseif widget._gridType == "GridButton" then
        SetSettingsListHeight(GM.size.buttonHeight)
    elseif widget._gridType == "GridCheckbox" then
        SetSettingsListHeight(ResolveSettingsListCheckboxHeight(options.presentation))
    end
    if options.presentation == "primary" and widget._gridType == "GridButton" then
        state.buttonVariant = widget._exButtonVariant or "secondary"
        EXUI:SetButtonVariant(widget, "primary", true)
        PaintModernButton(widget)
    end
    if options.width == "content" and widget._gridType == "GridButton" then
        local label = widget.GetFontString and widget:GetFontString() or nil
        local textWidth = label and label.GetUnboundedStringWidth
            and math.ceil(label:GetUnboundedStringWidth() or 0) or 0
        widget:SetWidth(math.max(BUTTON_STYLE.minWidth, textWidth + BUTTON_STYLE.paddingX * 2))
    end
    if options.valuePosition == "right" and widget._gridType == "GridSlider" and widget.numberInput then
        local input = widget.numberInput
        local interactive = widget.Slider
        state.sliderLayout = {
            valuePosition = widget._exSettingsValuePosition,
            fixedHeight = widget._exGridFixedHeight,
            width = widget:GetWidth(), height = widget:GetHeight(),
            inputPoints = CaptureRegionPoints(input),
            inputWidth = input:GetWidth(), inputHeight = input:GetHeight(),
            interactivePoints = interactive and CaptureRegionPoints(interactive) or nil,
            interactiveWidth = interactive and interactive:GetWidth() or nil,
            interactiveHeight = interactive and interactive:GetHeight() or nil,
        }
        widget._exSettingsValuePosition = "right"
        self:UpdateSettingsListControlLayout(widget, widget:GetWidth())
    end
    if options.role == "label" then
        local region = ResolveSettingsListRoleRegion(widget)
        if region and region.GetText and region.SetText then
            local fontPath, fontSize, fontFlags = region:GetFont()
            local shadowR, shadowG, shadowB, shadowA = region:GetShadowColor()
            local shadowX, shadowY = region:GetShadowOffset()
            state.roleLabel = {
                region = region, text = region:GetText(), points = CaptureRegionPoints(region),
                widgetHeight = widget:GetHeight(),
                fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
                color = { region:GetTextColor() }, shadowColor = { shadowR, shadowG, shadowB, shadowA },
                shadowX = shadowX, shadowY = shadowY,
                justifyH = region:GetJustifyH(), justifyV = region:GetJustifyV(),
            }
            local plain = tostring(region:GetText() or "")
                :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            region:SetText(plain)
            if region ~= widget then
                region:ClearAllPoints()
                region:SetPoint("LEFT", widget, "LEFT", 0, 0)
                region:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            end
            region:SetJustifyH("LEFT")
            region:SetJustifyV("MIDDLE")
            MODERN.ApplyTextRole(region, "title", SETTINGS_LIST_TITLE)
            SetSettingsListHeight(SETTINGS_LIST_TEXT_ROW_HEIGHT)
        end
    elseif options.role == "tableText" then
        local region = ResolveSettingsListRoleRegion(widget)
        if region and region.GetText then
            local fontPath, fontSize, fontFlags = region:GetFont()
            local shadowR, shadowG, shadowB, shadowA = region:GetShadowColor()
            local shadowX, shadowY = region:GetShadowOffset()
            state.roleTableText = {
                region = region, points = CaptureRegionPoints(region),
                fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
                color = { region:GetTextColor() },
                shadowColor = { shadowR, shadowG, shadowB, shadowA },
                shadowX = shadowX, shadowY = shadowY,
                justifyH = region:GetJustifyH(), justifyV = region:GetJustifyV(),
                wordWrap = region:CanWordWrap(),
                maxLines = region.GetMaxLines and region:GetMaxLines() or nil,
            }
            widget._exSettingsTextRole = "tableText"
            if region ~= widget then
                region:ClearAllPoints()
                region:SetPoint("LEFT", widget, "LEFT", 0, 0)
                region:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            end
            region:SetJustifyH("LEFT")
            region:SetJustifyV("MIDDLE")
            MODERN.ApplyTextRole(region, "title", SETTINGS_LIST_TITLE)
            SetSettingsListHeight(SETTINGS_LIST_TEXT_ROW_HEIGHT)
        end
    elseif options.role == "description" then
        local region = ResolveSettingsListRoleRegion(widget)
        if region and region.GetText then
            local fontPath, fontSize, fontFlags = region:GetFont()
            local shadowR, shadowG, shadowB, shadowA = region:GetShadowColor()
            local shadowX, shadowY = region:GetShadowOffset()
            state.roleDescription = {
                region = region, points = CaptureRegionPoints(region),
                width = region:GetWidth(), height = region:GetHeight(),
                fontPath = fontPath, fontSize = fontSize, fontFlags = fontFlags,
                color = { region:GetTextColor() },
                shadowColor = { shadowR, shadowG, shadowB, shadowA },
                shadowX = shadowX, shadowY = shadowY,
                justifyH = region:GetJustifyH(), justifyV = region:GetJustifyV(),
                wordWrap = region:CanWordWrap(),
                maxLines = region.GetMaxLines and region:GetMaxLines() or nil,
            }
            if region ~= widget then
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
                region:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)
            end
            region:SetJustifyH("LEFT")
            region:SetJustifyV("TOP")
            region:SetWordWrap(true)
            if region.SetMaxLines then region:SetMaxLines(0) end
            MODERN.Font(region, options.descriptionFontSize or GM.font.text,
                SETTINGS_LIST_DESCRIPTION, "", "GameFontHighlightSmall")
        end
    end
    if options.hideLabel == true then
        local seen = {}
        for _, field in ipairs({ "labelText", "label", "Title" }) do
            local region = widget[field]
            if region and not seen[region] and region.IsShown and region.SetShown then
                seen[region] = true
                state.labels[#state.labels + 1] = { region = region, shown = region:IsShown() }
                region:Hide()
            end
        end
    end
    local box = widget.checkbox
    if (options.presentation == "switch" or options.presentation == "card") and box then
        state.checkbox = {
            width = box:GetWidth(), height = box:GetHeight(), points = CaptureRegionPoints(box),
            labelPoints = widget.label and CaptureRegionPoints(widget.label) or nil,
            labelJustify = widget.label and widget.label:GetJustifyH() or nil,
            labelShown = checkboxLabelShown,
        }
        widget._exSettingsPresentation = options.presentation
        box:ClearAllPoints()
        if options.presentation == "card" then
            widget._exSettingsCardDescription = options.cardDescription == true
            widget._exSettingsCardIcon = options.cardIcon
            widget._exSettingsCardCheckSize = tonumber(options.cardCheckSize)
            widget._exSettingsCardTextSize = tonumber(options.cardTextSize)
            box:SetAllPoints(widget)
            if widget.label then widget.label:Hide() end
        else
            box:SetPoint("RIGHT", widget, "RIGHT", 0, 0)
            box:SetSize(GM.size.switchTrackWidth, GM.size.switchTrackHeight)
        end
        PaintModernCheckbox(widget, nil, true)
    end
    widget._exSettingsListVisualState = state
    return true
end

-- 卡片说明直接跟随公共标题的左右锚点，业务页不再复制标题内边距。
function EXUI:LayoutCheckboxCardDescription(control, description, height)
    local card = control.checkbox and control.checkbox._exSettingsCardSurface
    if not card then error("LayoutCheckboxCardDescription requires a prepared checkbox card", 2) end
    description:ClearAllPoints()
    description:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
    description:SetPoint("TOPRIGHT", card.Title, "BOTTOMRIGHT", 0, -SETTINGS_LIST_DESCRIPTION_GAP)
    description:SetHeight(height or GM.size.controlHeight)
end

-- =========================================================
-- 20.1 模块通用设置卡片：统一紧凑 Flow
--
-- 模块运行逻辑自身的开关、阈值等非外观字段统一收进这里；外观一律使用对应封装组。
-- 新标准最低以三到四列密排；
-- 新声明如确有内容宽度需要，可使用 field.span / field.minWidth / field.fullWidth，
-- 而不是给模块私写另一套布局。
-- =========================================================
local function CollectModuleCommonFields(opts)
    local result = {}
    for _, field in ipairs((type(opts) == "table" and opts.fields) or {}) do
        local path = tostring(field.path or field.key or "")
        if path ~= "" or field.type == "button" then
            result[#result + 1] = field
        end
    end
    return result
end

local function IsModuleCommonOrdinaryField(field)
    if type(field) ~= "table" or field.fullWidth == true
        or field.presentation == "card" or field.presentation == "switch" then
        return false
    end
    local kind = field.type
    if kind == "slider" then return field.valuePosition ~= "top" end
    return kind == "input" or kind == "dropdown" or kind == "color"
        or kind == "lsm_background" or kind == "lsm_border" or kind == "lsm_texture"
end

-- [WEB-REQ 28] 普通行右侧控件最小可用宽：滑条 settingsRowSliderMinWidth，其余普通控件 settingsRowControlMinWidth；
-- 非普通字段（开关/胶囊/整行/按钮）返回 nil，沿用旧算法。Grid 与复合控件创建 Row 时用同一函数，保证测量与摆放同源。
function EXUI:GetModuleCommonControlMinWidth(field)
    if not IsModuleCommonOrdinaryField(field) then return nil end
    return field.type == "slider" and GM.size.settingsRowSliderMinWidth or GM.size.settingsRowControlMinWidth
end

local function GetModuleCommonFieldMinWidth(field)
    local explicit = tonumber(field.minWidth or field.preferredWidth or field.width)
    if explicit and explicit > 0 then return explicit end

    local kind = tostring(field.type or "slider")
    local base = {
        checkbox = 176, color = 172, button = 188,
        slider = 228, dropdown = 244, input = 244,
        lsm_background = 260, lsm_border = 260, lsm_texture = 260,
    }
    local minWidth = base[kind] or 228
    -- 标签不截断优先于凑列数。中文字节数仅作保守视觉估算，
    -- 不参与任何业务数据或 DB 逻辑。
    local labelBytes = #(tostring(field.label or field.path or field.key or ""))
    if labelBytes > 30 then
        minWidth = math.max(minWidth, math.min(380, 150 + labelBytes * 5))
    end
    return minWidth
end

-- 公共纯布局计算：Grid 在创建 widget 前也调用它，以相同规则压缩布局占位。
function EXUI:BuildModuleCommonSettingsFlow(width, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = CollectModuleCommonFields(opts)
    local groupWidth = math.max(1, tonumber(width) or 760)

    if opts.presentation == "settings-list" then
        local entries, cursor = {}, 0
        local rowGap = 0
        local innerWidth = math.max(1, groupWidth - SETTINGS_LIST_ROW_PADDING_X * 2)
        -- 与 PrepareSettingsListControl 的非 ordinary 摆放高度读同一批 GM 键。
        local controlHeightByType = {
            color = GM.size.colorButtonHeight, button = GM.size.buttonHeight,
            slider = EXUI.GridSliderHeight, dropdown = GM.size.dropdownHeight, input = GM.size.inputHeight,
            lsm_background = GM.size.dropdownHeight, lsm_border = GM.size.dropdownHeight,
            lsm_texture = GM.size.dropdownHeight,
        }
        for _, field in ipairs(fields) do
            local ordinaryControl = IsModuleCommonOrdinaryField(field)
            local controlHeight = ordinaryControl and SETTINGS_LIST_ORDINARY_CONTROL_HEIGHT
                or (field.type == "checkbox" and ResolveSettingsListCheckboxHeight(field.presentation))
                or controlHeightByType[field.type] or EXUI.GridSliderHeight
            local controlWidth, textWidth, stacked = ResolveSettingsRowColumns(innerWidth,
                field.controlWidth, ordinaryControl and "ordinary" or nil,
                field.inputWidthPercent, EXUI:GetModuleCommonControlMinWidth(field))
            local titleHeight = MeasureSettingsListText(field.label or field.path or field.key, textWidth, "title")
            local descriptionHeight = MeasureSettingsListText(field.description, textWidth, "description")
            local textHeight = titleHeight + (descriptionHeight > 0
                and ((titleHeight > 0 and SETTINGS_LIST_DESCRIPTION_GAP or 0) + descriptionHeight) or 0)
            -- 窄版（stacked）：与 UpdateSettingsRowLayout 同一公式——文字在上、控件换到下一行。
            local rowHeight = math.max(SETTINGS_LIST_STANDARD_ROW_HEIGHT,
                SETTINGS_LIST_ROW_PADDING_Y * 2 + (stacked
                    and (textHeight + (textHeight > 0 and SETTINGS_LIST_STACK_GAP or 0) + controlHeight)
                    or math.max(textHeight, controlHeight)))
            if descriptionHeight > 0 then
                rowHeight = math.max(rowHeight, SETTINGS_LIST_DESCRIPTION_MIN_HEIGHT)
            end
            entries[#entries + 1] = {
                field = field,
                row = #entries,
                column = 0,
                span = 1,
                x = 0,
                y = -cursor,
                width = groupWidth,
                height = rowHeight,
                controlHeight = controlHeight,
            }
            cursor = cursor + rowHeight + rowGap
        end
        local height = #entries > 0 and (cursor - rowGap) or 1
        return {
            fields = fields,
            entries = entries,
            columns = 1,
            rows = math.max(1, #entries),
            width = groupWidth,
            padding = 0,
            contentTopInset = 0,
            entryOriginX = 0,
            cardInsetX = 0,
            cardInsetY = 0,
            cardBottomInset = 0,
            settingsList = true,
            height = math.max(1, height),
        }
    end

    -- 模块声明 fixedLayout 时使用固定的逻辑网格；不声明的历史调用者继续走
    -- 下方原有动态 Flow。逻辑尺寸只在这里按实际 groupWidth 转为物理像素，
    -- 让 Grid measure 与复合控件重排始终共享同一份高度合同。
    if type(opts.fixedLayout) == "table" then
        local fixed = opts.fixedLayout
        local logicalWidth = math.max(1, tonumber(fixed.logicalWidth) or 200)
        local controlW = math.max(1, tonumber(fixed.controlW) or 40)
        local controlH = math.max(1, tonumber(fixed.controlH) or 6)
        local slotX = type(fixed.slotX) == "table" and fixed.slotX or { 1, 51, 101, 151 }
        local firstY = tonumber(fixed.firstY) or 5
        local rowStep = math.max(controlH, tonumber(fixed.rowStep) or 12)
        local cardTopLogical = math.max(0, tonumber(fixed.cardTopInset) or 1)
        local cardBottomLogical = math.max(0, tonumber(fixed.cardBottomInset) or 5)
        local scale = groupWidth / logicalWidth
        -- 控件框的逻辑几何保持 40×6；但它们的 WoW 模板可见区域是固定像素，
        -- 例如 checkbox/color 取 GM.size 对应键，slider 还包含标题、轨道和数值输入框。
        -- 因此测量时逐行记录实际可见底边，绝不能只用 6×scale 截断末行。
        -- 加号前的数字是 Composite 摆放时的顶部偏移，后面读 GM 控件高度。
        local visibleBottomByType = {
            checkbox = 11 + GM.size.checkboxRowHeight,
            color = 14 + GM.size.colorButtonHeight,
            slider = 8 + EXUI.GridSliderHeight,
            dropdown = 25 + GM.size.dropdownHeight,
            lsm_background = 25 + GM.size.dropdownHeight,
            lsm_border = 25 + GM.size.dropdownHeight,
            lsm_texture = 25 + GM.size.dropdownHeight,
            input = 16 + GM.size.inputHeight,
            button = 16 + GM.size.buttonHeight,
        }
        local bottomSafety = math.max(2, (tonumber(fixed.visibleBottomSafety) or 2) * scale)
        local entries, rowColumns, rowVisibleBottoms, maxRow, cardHeight = {}, {}, {}, 1, 1

        for _, field in ipairs(fields) do
            -- 固定布局只相信调用方声明的 row；不再根据 label 或控件类型猜语义。
            local row = math.max(1, math.floor(tonumber(field.row) or 1))
            local nextColumn = rowColumns[row] or 0
            local declaredColumn = tonumber(field.column)
            local column = declaredColumn
                and math.max(1, math.min(#slotX, math.floor(declaredColumn))) - 1
                or nextColumn
            rowColumns[row] = math.max(nextColumn, column + 1)
            maxRow = math.max(maxRow, row)
            local slotTop = (firstY + (row - 1) * rowStep) * scale
            local visibleBottom = math.max(controlH * scale,
                tonumber(visibleBottomByType[field.type]) or visibleBottomByType.slider)
            local rowBottom = slotTop + visibleBottom
            rowVisibleBottoms[row] = math.max(rowVisibleBottoms[row] or 0, rowBottom)
            cardHeight = math.max(cardHeight, rowBottom + bottomSafety)
            entries[#entries + 1] = {
                field = field,
                row = row,
                column = column,
                span = 1,
                x = (tonumber(slotX[column + 1]) or tonumber(slotX[#slotX]) or 5) * scale,
                y = -slotTop,
                width = controlW * scale,
                height = controlH * scale,
            }
        end

        return {
            fields = fields,
            entries = entries,
            columns = #slotX,
            rows = maxRow,
            width = groupWidth,
            padding = 0,
            contentTopInset = 0,
            entryOriginX = 0,
            headerHeight = 0,
            cardInsetX = 0,
            cardInsetY = cardTopLogical * scale,
            cardBottomInset = cardBottomLogical * scale,
            rowVisibleBottoms = rowVisibleBottoms,
            cardHeight = cardHeight,
            height = math.max(1, cardTopLogical * scale
                + cardHeight + cardBottomLogical * scale),
        }
    end

    local padding, gap = 16, 12
    local available = math.max(1, groupWidth - padding * 2)
    -- 新标准：正常空间优先四列。若声明确有语义上限，只能使用 maxColumns；
    -- 不读取旧 columns，避免形成旧布局的转译/兼容分支。
    local maxColumns = math.max(1, math.min(4, tonumber(opts.maxColumns) or 4))
    local minCellWidth = math.max(160, tonumber(opts.minCellWidth) or 220)
    local columns = math.max(1, math.min(maxColumns, math.floor((available + gap) / (minCellWidth + gap))))
    local unitWidth = math.floor((available - gap * (columns - 1)) / columns)
    local rowHeight = math.max(1, tonumber(opts.rowHeight) or 52)
    local firstRowHeight = math.max(1, tonumber(opts.firstRowHeight) or rowHeight)
    local rowStep = math.max(rowHeight, tonumber(opts.rowStep) or 60)
    local firstRowStep = math.max(firstRowHeight, tonumber(opts.firstRowStep) or rowStep)
    local contentTopInset = math.max(0, tonumber(opts.contentTopInset) or 44)
    local heightOffset = tonumber(opts.heightOffset) or 0
    local row, occupied = 0, 0
    local entries = {}

    for _, field in ipairs(fields) do
        local span
        if field.fullWidth == true then
            span = columns
        else
            span = math.max(1, math.ceil(GetModuleCommonFieldMinWidth(field) / math.max(1, unitWidth)))
            span = math.max(span, math.floor(tonumber(field.span) or 1))
            span = math.min(columns, span)
        end
        if occupied > 0 and occupied + span > columns then
            row, occupied = row + 1, 0
        end
        entries[#entries + 1] = {
            field = field,
            row = row,
            column = occupied,
            span = span,
            x = padding + occupied * (unitWidth + gap),
            y = -contentTopInset - (row == 0 and 0 or (firstRowStep + (row - 1) * rowStep)),
            width = unitWidth * span + gap * (span - 1),
            height = row == 0 and firstRowHeight or rowHeight,
        }
        occupied = occupied + span
        if occupied >= columns then row, occupied = row + 1, 0 end
    end

    local rows = math.max(1, #entries > 0 and (entries[#entries].row + 1) or 1)
    return {
        fields = fields,
        entries = entries,
        columns = columns,
        rows = rows,
        width = groupWidth,
        padding = padding,
        contentTopInset = contentTopInset,
        entryOriginX = padding,
        headerHeight = 0,
        cardInsetX = padding,
        cardInsetY = 8,
        cardBottomInset = 8,
        -- 保留原来的外框总高度基线；紧凑首行只把后续行上移，留下底部安全
        -- 留白，避免 slider 的数值输入框贴住外框。
        height = math.max(1, 68 + (rows - 1) * rowStep + heightOffset),
    }
end

-- 组合构造器与本文件的布局计算共用同一个字段呈现判定。
Internal.IsModuleCommonOrdinaryField = IsModuleCommonOrdinaryField
