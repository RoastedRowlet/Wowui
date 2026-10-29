-- Pooled tabs and option groups. Ordinary EXUI button skins are unchanged.
local UI = _G.ExwindTools.UI
local Factory = _G.ExwindFactory
local HOST, VIEW, ITEM = "EXUI.ChoiceGroup", "EXUI.ChoiceViewport", "EXUI.ChoiceItem"
local Methods = {}
local Appearance = UI.ControlAppearance
local GC = _G.ExwindTools.GUIColors
local GS = _G.ExwindTools.GUIStates
local GM = _G.ExwindTools.GUIMetrics
local Paint, Layout
-- 页签文字左右内距；fit=true 的页签组放不下时逐步压到 TAB_FIT_MIN_PAD。
local TAB_PAD, TAB_FIT_MIN_PAD, TAB_ICON_WIDTH = 14, 4, 22
local RADIO_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Materials\\ExwindTools\\PlayerPosition\\Circle.png"

local function IsOptionCard(host)
    return host.variant == "options" and host.mode == "single" and not host.choiceStyle
end

local function IsSegmented(host)
    return host.choiceStyle == "segmented" and host.mode == "single"
end

local function SetMovingTexture(host, texture, x, width, animate)
    if not texture then return end
    width = math.max(1, width)
    local state = host._choiceMotion
    if animate and state and state.texture == texture and state.x and
        (math.abs(state.x - x) > .5 or math.abs(state.width - width) > .5) then
        state.fromX, state.fromWidth = state.x, state.width
        state.toX, state.toWidth, state.elapsed = x, width, 0
        host:SetScript("OnUpdate", function(self, elapsed)
            local motion = self._choiceMotion
            if not motion or not self._choiceLease then self:SetScript("OnUpdate", nil); return end
            motion.elapsed = math.min(.18, motion.elapsed + elapsed)
            local t = motion.elapsed / .18
            local ease = 1 - (1 - t) * (1 - t) * (1 - t)
            motion.x = motion.fromX + (motion.toX - motion.fromX) * ease
            motion.width = motion.fromWidth + (motion.toWidth - motion.fromWidth) * ease
            motion.texture:ClearAllPoints()
            motion.texture:SetPoint(motion.anchor, self, motion.anchor, motion.x, motion.y)
            motion.texture:SetWidth(motion.width)
            -- 选中块的圆角片按自己在屏幕上的位置取整；只挪位置不触发尺寸变化，每帧按新位置重排（位置没变时直接跳过），
            -- 否则停下后片落在半个像素上、片间露缝。
            UI:RefreshCompositeSurfaces(motion.texture)
            if t >= 1 then self:SetScript("OnUpdate", nil) end
        end)
        return
    end
    host:SetScript("OnUpdate", nil)
    state = state or {}
    state.texture, state.x, state.width = texture, x, width
    state.toX, state.toWidth = nil, nil
    state.anchor = host.variant == "tabs" and "BOTTOMLEFT" or "TOPLEFT"
    -- 分段选中块的上沿 = 轨道内距（黑色轨道 2，其余 3）。
    state.y = host.variant == "tabs" and 1 or (host.darkTrack and -GM.space.segmentedDarkTrackPad or -3)
    host._choiceMotion = state
    texture:ClearAllPoints()
    texture:SetPoint(state.anchor, host, state.anchor, x, state.y)
    texture:SetWidth(width)
end

-- 页签选中线是整圆胶囊，不是方头色块：高度先取偶数物理像素，半径再取高度的一半，
-- 这样任何 UI scale 下两端都是完整半圆（和 Switch 轨道同一套做法）。
-- 这条线是纯填充，不需要 1px 描边：把 border 传成透明以后，surface 的
-- degenerateBorder（heightPixels <= strokePixels × 2）只会让那块退化的实心描边
-- 变成透明矩形，填充层仍按 radiusPixels 取圆角样本。因此 2 物理像素高也能保住
-- 半径 1 的圆头——下限就在这里：再细只剩 1 像素，半径被夹成 0，才真的变方头。
-- force：新租约必须重画一次（池化复用后不能沿用上个租约的外观）；
-- 重排时只有物理像素高度真的变了才重画，滚动页签不必每次重建 surface。
local function PaintTabIndicator(host, force)
    local indicator = host.tabIndicator
    if not indicator then return end
    local pixel = Appearance.surfaceAtlas:GetPixel(indicator)
    local height = 2 * math.max(1, math.floor(GM.size.tabIndicatorHeight / pixel / 2 + .5)) * pixel
    if not force and indicator._exTabIndicatorHeight == height then return end
    indicator._exTabIndicatorHeight = height
    indicator:SetHeight(height)
    -- 只画填充那一层：描边传透明。两层同色会把抗锯齿边缘合成两次（和 Switch 轨道
    -- 同一个原因），而且在细条上描边一退化就是方头。
    Appearance.PaintControlSurface(indicator, height / 2, GC.tabIndicator, GC.transparent)
end

Factory:InitCompositePool(HOST)
Factory:InitPool(VIEW, "Frame")
Factory:InitPool(ITEM, "Button", "BackdropTemplate", function(button)
    -- Paint owns text state. Do not register this label as Button's native
    -- font string: native pushed/font state must not move our layout-owned text.
    button.label = UI:CreateVisualFontString(button, _G.EXFONTFRAME, "GameFontHighlightSmall")
    button.label:SetWordWrap(false)
    button.label:SetJustifyH("CENTER")
    button.label:SetJustifyV("MIDDLE")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.line = button:CreateTexture(nil, "OVERLAY")
    button.line:SetColorTexture(unpack(Appearance.colors.focus))
    button.line:SetPoint("BOTTOMLEFT", 0, 0)
    button.line:SetPoint("BOTTOMRIGHT", 0, 0)
    button.line:SetHeight(2)
    button.seam = UI:CreateVisualTexture(button, _G.EXBORDERFRAME)
    button.seam:SetColorTexture(unpack(Appearance.colors.inputBorder))
    button.seam:SetPoint("TOPRIGHT")
    button.seam:SetPoint("BOTTOMRIGHT")
    button.seam:SetWidth(1)
    button.seam:Hide()
    button.description = UI:CreateVisualFontString(button, _G.EXFONTFRAME, "GameFontHighlightSmall")
    button.description:SetJustifyH("LEFT")
    button.description:Hide()
    button.radioOuter = button:CreateTexture(nil, "ARTWORK")
    button.radioInner = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.radioDot = button:CreateTexture(nil, "ARTWORK", nil, 2)
    for _, radio in ipairs({ button.radioOuter, button.radioInner, button.radioDot }) do
        radio:SetTexture(RADIO_TEXTURE)
        radio:SetTexCoord(15 / 64, 49 / 64, 15 / 64, 49 / 64)
        radio:Hide()
    end
    button.radioOuter:SetSize(18, 18)
    button.radioOuter:SetPoint("LEFT", 14, 0)
    button.radioInner:SetSize(15, 15)
    button.radioInner:SetPoint("CENTER", button.radioOuter)
    button.radioDot:SetSize(6, 6)
    button.radioDot:SetPoint("CENTER", button.radioOuter)
end)

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for id, selected in pairs(value) do if selected == true then result[id] = true end end
    return result
end

local function Composite(base, overlay)
    local alpha = overlay[4] or 1
    return {
        base[1] + (overlay[1] - base[1]) * alpha,
        base[2] + (overlay[2] - base[2]) * alpha,
        base[3] + (overlay[3] - base[3]) * alpha,
        1,
    }
end

local function Normalize(host, value)
    if host.mode == "multiple" then
        local selected = {}
        for _, item in ipairs(host.items) do
            if type(value) == "table" and value[item.id] == true then selected[item.id] = true end
        end
        if not host.allowEmpty and not next(selected) then
            for _, item in ipairs(host.items) do if not item.disabled then selected[item.id] = true; break end end
        end
        return selected
    end
    for _, item in ipairs(host.items) do if item.id == value then return value end end
    if not host.allowEmpty then
        for _, item in ipairs(host.items) do if not item.disabled then return item.id end end
    end
end

local function Selected(host, id)
    if host.mode == "multiple" then return host.selection[id] == true end
    return host.selection == id
end

local function CloseTooltip(button)
    if _G.GameTooltip and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end

Paint = function(button)
    local host, item = button._choiceHost, button._choiceItem
    if not host or not item then return end
    local selected = not button._choiceArrow and Selected(host, item.id)
    local disabled = host.disabled or item.disabled
    local hover = button._choiceHover and not disabled
    local pressed = button._choicePressed and not disabled
    local state = disabled and "disabled" or pressed and "pressed"
        or selected and "selected" or hover and "hover" or "normal"
    button:SetEnabled(not disabled)
    local fill, edge, textColor
    if host._specPickerTextColor and not button._choiceArrow then
        UI:ClearControlSurface(button)
        textColor = host._specPickerMultiple and
            ((selected or hover) and host._specPickerTextColor or GC.optionDesc) or host._specPickerTextColor
        if button._specTile then
            UI:SetControlSurface(button._specTile, GM.radius.popup, GC.input,
                selected and host._specPickerTextColor or GC.inputBorder)
            button._specTile.check:SetShown(selected and not host._specPickerMultiple)
            button._specTile.image:SetDesaturated(host._specPickerMultiple and not selected)
            button._specTile.image:SetAlpha(host._specPickerMultiple
                and (selected and 1 or (hover and .82 or .58))
                or ((hover or selected) and 1 or .85))
        end
    elseif host.variant == "tabs" and not button._choiceArrow then
        UI:ClearControlSurface(button)
        local tabState = GS and GS.tab and GS.tab[state]
        textColor = tabState and tabState.text or disabled and Appearance.colors.disabledText or
            (selected and GC.tabSelectedText or (hover and GC.tabHoverText or GC.tabText))
        -- 页签组 options.selectedText：选中项（可用、未按下时）的文字色；不写时照旧。
        if state == "selected" and host.tabSelectedText then textColor = host.tabSelectedText end
    elseif IsOptionCard(host) and not button._choiceArrow then
        local optionState = GS and GS.option and GS.option[state]
        fill = optionState and optionState.fill or disabled and Appearance.colors.disabledFill or
            (selected and GC.optionRowSelected or GC.optionRow)
        edge = optionState and optionState.border or disabled and Appearance.colors.disabledBorder or
            (selected and GC.optionRowSelectedBorder or (hover and GC.optionRowHoverBorder or GC.optionRowBorder))
        textColor = optionState and optionState.text or disabled and Appearance.colors.disabledText or
            (selected and GC.optionTitleSelected or GC.optionTitle)
        UI:SetControlSurface(button, GM.radius.control, fill, edge)
        button.radioOuter:SetVertexColor(unpack(disabled and Appearance.colors.disabledBorder or
            (selected and GC.radioSelected or (hover and GC.radioHoverBorder or GC.radioBorder))))
        button.radioInner:SetVertexColor(unpack(fill))
        button.radioDot:SetVertexColor(unpack(GC.radioDot))
        button.radioOuter:Show()
        button.radioInner:SetShown(not selected)
        button.radioDot:SetShown(selected)
        button.description:SetTextColor(unpack(disabled and Appearance.colors.disabledText or GC.optionDesc))
    elseif IsSegmented(host) and not button._choiceArrow then
        UI:ClearControlSurface(button)
        local optionState = GS and GS.option and GS.option[state]
        textColor = optionState and optionState.text or disabled and Appearance.colors.disabledText or
            (selected and GC.segmentSelectedText or (hover and GC.segmentHoverText or GC.segmentText))
        -- 分段每项可写选中文字色（只有选中且可用时生效）。
        if selected and not disabled and item.selectedText then textColor = item.selectedText end
        -- 黑色轨道：未选中、可用的段悬停 / 按下时画淡白底（选中段由滑动选中块画）。
        if host.darkTrack and not selected and not disabled and (hover or pressed) then
            local tint = pressed and GC.segmentDarkPressed or GC.segmentDarkHover
            UI:SetControlSurface(button, GM.radius.thumb, tint, GC.transparent)
        end
        -- 浮层外观（EXUI:SetControlOverlayAppearance）：分段文字加描边。
        Appearance.SyncOverlayFont(host, button.label)
    elseif (host.choiceStyle == "connected" or host.choiceStyle == "segmented") and not button._choiceArrow then
        local radius = host.choiceStyle == "connected" and 0 or GM.radius.control
        local optionState = GS and GS.option and GS.option[state]
        if optionState then
            fill, edge, textColor = optionState.fill, optionState.border, optionState.text
            UI:SetControlSurface(button, radius, fill, edge)
        elseif disabled then
            fill, textColor = Appearance.colors.disabledFill, Appearance.colors.disabledText
            UI:SetControlSurface(button, radius, fill, fill)
        elseif pressed then
            fill, textColor = Composite(Appearance.colors.input, Appearance.colors.toolActive),
                Appearance.colors.accentActive
            UI:SetControlSurface(button, radius, fill, fill)
        elseif selected then
            fill, textColor = Composite(Appearance.colors.input,
                    hover and Appearance.colors.tagSelectedHover or Appearance.colors.segmentSelected),
                Appearance.colors.white
            UI:SetControlSurface(button, radius, fill, fill)
        elseif hover then
            fill, textColor = Composite(Appearance.colors.input, Appearance.colors.toolHover),
                Appearance.colors.text
            UI:SetControlSurface(button, radius, fill, fill)
        else
            UI:ClearControlSurface(button)
            textColor = Appearance.colors.segmentText
        end
        if not optionState and selected and (host.choiceStyle == "segmented" or not disabled) then
            UI:SetControlSurface(button, radius, fill, Appearance.colors.modifiedBorder)
        end
    else
        local base = Appearance.colors.subcard
        local pillState = GS and GS.pill and GS.pill[state]
        if pillState then
            fill, edge, textColor = pillState.fill, pillState.border, pillState.text
        elseif disabled then
            fill, edge, textColor = Appearance.colors.disabledFill,
                Appearance.colors.disabledBorder, Appearance.colors.disabledText
        elseif pressed then
            fill = Composite(base, Appearance.colors.toolActive)
            edge = selected and Appearance.colors.modifiedBorder or Appearance.colors.subcardHoverBorder
            textColor = host.variant == "tabs" and Appearance.colors.accentActive
                or (selected and Appearance.colors.tagSelectedText or Appearance.colors.tagHoverText)
        elseif selected then
            fill = Composite(base, hover and Appearance.colors.tagSelectedHover
                or Appearance.colors.tagSelected)
            edge = Appearance.colors.modifiedBorder
            textColor = Appearance.colors.tagSelectedText
        elseif hover then
            fill = Composite(base, Appearance.colors.rowHover)
            edge = Appearance.colors.subcardHoverBorder
            textColor = Appearance.colors.tagHoverText
        else
            fill, edge, textColor = base, Appearance.colors.subcardBorder,
                Appearance.colors.tagText
        end
        UI:SetControlSurface(button, GM.radius.control, fill, edge)
    end
    button.label:SetTextColor(unpack(textColor))
    button.seam:SetColorTexture(unpack(selected and Appearance.colors.modifiedBorder or Appearance.colors.inputBorder))
    button.line:SetColorTexture(unpack(Appearance.colors.focus))
    button.line:Hide()
    button.icon:SetAlpha(disabled and .35 or 1)
    -- 统一图标库是白色线条贴图：跟随文字色，选中/悬停/禁用时与文字同步变化。
    if button._choiceIconTint then
        button.icon:SetVertexColor(unpack(textColor))
    else
        button.icon:SetVertexColor(1, 1, 1, 1)
    end
end

function Methods:GetValue() return Copy(self.selection) end

-- SetValue/SetItems are always silent, including calls made inside onChange.
function Methods:SetValue(value)
    if not self._choiceLease then return end
    local old = self.selection
    self.selection = Normalize(self, value)
    self._choiceRevision = self._choiceRevision + 1
    for _, button in ipairs(self.buttons) do Paint(button) end
    Layout(self, true, old ~= self.selection)
end

-- 分段轨道：平常 segmentTrack 底；浮层外观（host._exOverlay）换浮层底与边；
-- 黑色轨道（host.darkTrack）只画黑底不画边，优先于浮层外观。
local function PaintSegmentTrack(host)
    if host.darkTrack then
        UI:SetControlSurface(host, GM.radius.control, GC.segmentDarkTrack, GC.transparent)
        return
    end
    local overlay = host._exOverlay == true
    UI:SetControlSurface(host, GM.radius.control, overlay and GC.floatControlFill or GC.segmentTrack,
        overlay and GC.floatControlBorder or GC.segmentTrackBorder)
end

-- 分段选中块的颜色：整组禁用时灰；选中项写了 selectedFill 用它；否则主色（黑色轨道为白 0.22）。
local function SegmentSliderColor(host)
    if host.disabled then return Appearance.colors.disabledFill end
    for _, item in ipairs(host.items or {}) do
        if item.selectedFill and Selected(host, item.id) then return item.selectedFill end
    end
    return host.darkTrack and GC.segmentDarkSelected or GC.segmentSelected
end

function Methods:SetDisabled(disabled)
    if not self._choiceLease then return end
    self.disabled = disabled == true
    for _, button in ipairs(self.buttons) do Paint(button) end
    if IsSegmented(self) and self.segmentSlider then
        local color = SegmentSliderColor(self)
        UI:SetControlSurface(self.segmentSlider, GM.radius.thumb, color, color)
        self._choiceSliderTinted = color ~= GC.segmentSelected and not self.disabled or nil
    end
end

local function Choose(button)
    local host, item = button._choiceHost, button._choiceItem
    if not host or not host._choiceLease or not host:IsVisible() or host.disabled or item.disabled then return end
    local old, value = host:GetValue(), host:GetValue()
    if host.mode == "multiple" then
        value[item.id] = not value[item.id] or nil
        if not host.allowEmpty and not next(value) then return end
    elseif value == item.id then
        -- 分段控件的 allowEmpty 只表示“值为 nil 时不高亮”：再点已选项不取消。
        if not host.allowEmpty or IsSegmented(host) then return end
        value = nil
    else value = item.id end
    local lease, callback = host._choiceLease, host.onChange
    host:SetValue(value)
    if host._choiceLease ~= lease then return end
    local revision = host._choiceRevision
    if callback then
        local accepted = callback(host:GetValue(), host)
        if host._choiceLease == lease and host._choiceRevision == revision and accepted == false then
            host:SetValue(old)
        end
    end
end

local function LayoutLabel(button)
    local host = button._choiceHost
    if host._specPickerTextColor and not button._choiceArrow then
        -- 专精格只放图标：名称改由悬停 tooltip 给出（AcquireButton 的 OnEnter 已经
        -- 显示“专精名”+“职业 · 专精”），格高因此只需图标边长加上下留白。
        button.label:ClearAllPoints()
        button.label:Hide()
        button.icon:Hide()
        button.description:Hide()
        return
    end
    if IsOptionCard(host) and not button._choiceArrow then
        local label = button.label
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", button, "TOPLEFT", 44, button._choiceItem.description and -9 or 0)
        label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", button._choiceItem.icon and -36 or -14,
            button._choiceItem.description and 24 or 0)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(false)
        button.description:ClearAllPoints()
        button.description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        button.description:SetPoint("RIGHT", button, "RIGHT", -14, 0)
        button.description:SetHeight(16)
        button.description:SetShown(button._choiceItem.description ~= nil)
        UI:ApplyVisualLayer(label, _G.EXFONTFRAME)
        return
    end
    local padding = button:GetWidth() < 32 and 2 or 6
    if host.variant == "tabs" and not button._choiceArrow then padding = host._choiceTabPad or TAB_PAD end
    local label = button.label
    label:ClearAllPoints()
    if button._choiceItem.iconOnly and button.icon then
        -- 只有图标：图标居中，名称只在悬停提示里（OnEnter 显示 item.label）。
        button.icon:ClearAllPoints()
        button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
        label:SetWidth(0)
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
    elseif button._choiceItem.icon and button.icon then
        -- 图标与文字作为一组整体居中：间距固定 6px，且起点取整，避免半像素错位。
        local groupWidth = 20 + 6 + math.ceil(label:GetUnboundedStringWidth())
        local startX = math.max(2, math.floor((button:GetWidth() - groupWidth) / 2))
        button.icon:ClearAllPoints()
        button.icon:SetPoint("LEFT", button, "LEFT", startX, 0)
        -- 只锚左边、清除池化残留宽度：文字按自身宽度显示，不会被截成省略号。
        label:SetWidth(0)
        label:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
        label:SetJustifyH("LEFT")
    else
        -- 分段 options.textOffsetY：文字整体下移（只有分段会写）。
        local offsetY = host and host.textOffsetY or 0
        label:SetPoint("TOPLEFT", button, "TOPLEFT", padding, -offsetY)
        label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -padding, -offsetY)
        label:SetJustifyH("CENTER")
    end
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    button.description:Hide()
    UI:ApplyVisualLayer(label, _G.EXFONTFRAME)
end

local function AcquireButton(host, parent, item, onClick)
    local button = Factory:Acquire(ITEM, parent)
    button._choiceHost, button._choiceItem, button._choiceHover, button._choicePressed, button._choiceArrow = host, item, false, false, false
    local textRole = (host.variant == "tabs" or IsOptionCard(host) or host.choiceStyle == "segmented" or
        host.choiceStyle == "connected") and "fieldValue" or "control"
    if host.darkTrack then textRole = "control" end -- 黑色轨道（迷你分段）用 13 号字
    Appearance.ApplyTextRole(button.label, textRole, nil, textRole == "control" and "GameFontNormalSmall" or nil)
    if host.tabFontSize then Appearance.Font(button.label, host.tabFontSize, nil, "", "GameFontHighlight") end
    Appearance.ApplyTextRole(button.description, "hint", GC.optionDesc)
    button:SetPushedTextOffset(0, 0)
    button.label:SetText(item.iconOnly and "" or item.label)
    button.description:SetText(item.description or "")
    button.radioOuter:Hide(); button.radioInner:Hide(); button.radioDot:Hide()
    LayoutLabel(button)
    button.icon:ClearAllPoints()
    if IsOptionCard(host) and not onClick then button.icon:SetPoint("RIGHT", -14, 0)
    elseif item.iconOnly then button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    else button.icon:SetPoint("LEFT", 6, 0) end
    local iconSize = item.iconOnly and GM.size.iconGlyphSize or 20
    button.icon:SetSize(iconSize, iconSize)
    local icon = item.icon
    button._choiceIconTint = icon ~= nil and _G.ExwindTools.GUIIcons.ids[icon] ~= nil
    button.icon:SetTexture(icon and (_G.ExwindTools.GUIIcons.ids[icon] and UI:GetIcon(icon) or icon))
    button.icon:SetShown(item.icon ~= nil)
    button:SetScript("OnClick", onClick or Choose)
    button:SetScript("OnEnter", function(self)
        self._choiceHover = true; Paint(self)
        -- 文字完整可见、又没有额外 tooltip 时不出提示（否则只是把按钮名再写一遍，还会盖住旁边的页签）。
        local item = self._choiceItem
        local labelHidden = item and (item.iconOnly or not self.label:IsShown() or self.label:IsTruncated())
        if _G.GameTooltip and item and (item.tooltip or labelHidden) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._choiceItem.label)
            if self._choiceItem.tooltip then GameTooltip:AddLine(self._choiceItem.tooltip, .8, .85, .9, true) end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self._choiceHover, self._choicePressed = false, false
        Paint(self)
        CloseTooltip(self)
    end)
    button:SetScript("OnMouseDown", function(self) self._choicePressed = true; Paint(self) end)
    button:SetScript("OnMouseUp", function(self) self._choicePressed = false; Paint(self) end)
    button:SetScript("OnHide", function(self) self._choicePressed = false; CloseTooltip(self) end)
    if host.variant == "tabs" then
        button:EnableMouseWheel(true)
        button:SetScript("OnMouseWheel", function(_, delta) host:ScrollBy(-delta * 80) end)
    else
        button:SetScript("OnMouseWheel", nil)
        button:EnableMouseWheel(false)
    end
    button.seam:Hide()
    Factory:AttachPoolRelease(button, function(self)
        CloseTooltip(self)
        self._choiceHost, self._choiceItem, self._choiceHover, self._choicePressed, self._choiceArrow = nil, nil, nil, nil, nil
        self:SetScript("OnMouseWheel", nil); self:SetScript("OnMouseDown", nil)
        self:SetScript("OnMouseUp", nil); self:SetScript("OnHide", nil)
        if self._specPickerDivider then self._specPickerDivider:Hide() end
        if self._specTile then self._specTile:Hide() end
        self.line:Hide()
        self.seam:Hide()
        self.description:Hide()
        self.description:SetText("")
        self.radioOuter:Hide(); self.radioInner:Hide(); self.radioDot:Hide()
        self.label:SetText("")
        self.label:ClearAllPoints()
        -- 专精格会把名称隐藏；归还时恢复显示，下一个租约（页签/选项卡片）才有文字。
        self.label:Show()
        self:SetPushedTextOffset(0, 0)
    end)
    return button
end

function Methods:ScrollBy(delta)
    if not self._choiceLease or self.variant ~= "tabs" then return end
    self.offset = math.max(0, math.min(self.maxOffset or 0, (self.offset or 0) + delta))
    Layout(self)
end

-- Every non-tab choice leaves the wheel to its page. Tabs scroll horizontally.
function Methods:SetPageScroll()
    if self.variant == "tabs" then return end
    self._choicePageScroll = true
    self:SetScript("OnMouseWheel", nil)
    self:EnableMouseWheel(false)
    self.viewport:SetScript("OnMouseWheel", nil)
    self.viewport:EnableMouseWheel(false)
    for _, button in ipairs(self.buttons) do
        button:SetScript("OnMouseWheel", nil)
        button:EnableMouseWheel(false)
    end
    for _, button in ipairs({self.previous, self.nextButton}) do
        button:SetScript("OnMouseWheel", nil)
        button:EnableMouseWheel(false)
    end
end

-- fit=true 的页签组：总宽超过可用宽时把每项左右内距逐步压到 TAB_FIT_MIN_PAD；仍放不下才走滚动箭头。
local function FitTabPadding(host, width)
    local count = #host.buttons
    if count == 0 then return TAB_PAD end
    local function Total(pad)
        local total = host.gap * (count - 1)
        for _, button in ipairs(host.buttons) do
            total = total + math.max(host.minItemWidth, button.label:GetUnboundedStringWidth()
                + (button._choiceItem.icon and TAB_ICON_WIDTH or 0) + pad * 2)
        end
        return total
    end
    local pad = TAB_PAD
    while pad > TAB_FIT_MIN_PAD and Total(pad) > width + .5 do pad = pad - 1 end
    return pad
end

Layout = function(host, reveal, animate)
    if not host._choiceLease or host._choiceLayout then return end
    host._choiceLayout = true
    -- Pooled children can retain levels from an earlier parent. Keep the moving
    -- segment surface below the viewport and its text-bearing buttons.
    local baseLevel = host:GetFrameLevel()
    if host.segmentSlider then host.segmentSlider:SetFrameLevel(baseLevel + 1) end
    host.viewport:SetFrameLevel(baseLevel + 2)
    if host.tabOverlay then host.tabOverlay:SetFrameLevel(baseLevel + 30) end -- 高于壳层分隔线（+20），选中线压在分隔线上
    for _, button in ipairs(host.buttons) do button:SetFrameLevel(baseLevel + 3) end
    local padding = IsSegmented(host) and (host.darkTrack and GM.space.segmentedDarkTrackPad or GM.space.segmentedTrackPad) or ((host.choiceStyle == "segmented" or host.choiceStyle == "connected") and GM.space.connectedTrackPad or 0)
    local width, gap, height = math.max(1, host:GetWidth() - padding * 2), host.gap, host.itemHeight - padding * 2
    host._choiceTabPad = host.variant == "tabs" and (host.fit and FitTabPadding(host, width) or TAB_PAD) or nil
    if host.segmentSlider then host.segmentSlider:SetHeight(height) end
    local count = #host.buttons
    local columns = host.columns or (host.wrap and math.min(count, math.max(1, math.floor((width + gap) / (host.minItemWidth + gap)))) or count)
    columns = math.max(1, columns)
    local equalWidth = math.max(1, (width - (columns - 1) * gap) / columns)
    local x, y, lastRight = 0, 0, 0
    for index, button in ipairs(host.buttons) do
        local contentPadding = host.variant == "tabs"
            and ((button._choiceItem.icon and TAB_ICON_WIDTH or 0) + host._choiceTabPad * 2) or
            (button._choiceItem.icon and GM.space.choiceIconItemPadX or GM.space.choiceItemPadX)
        local size = host.sizing == "content" and math.max(host.minItemWidth, button.label:GetUnboundedStringWidth() + contentPadding) or equalWidth
        if host.variant == "tabs" then size = math.max(host.minItemWidth, size) else size = math.min(width, size) end
        if host.wrap and x > 0 and (x + size > width + .5 or (host.columns and (index - 1) % columns == 0)) then x, y = 0, y + height + gap end
        button._choiceX, button._choiceY, button._choiceWidth = x, y, size
        x = x + size + gap; lastRight = math.max(lastRight, x - gap)
    end
    local overflow = host.variant == "tabs" and lastRight > width + .5
    local inset = overflow and 20 or 0
    local visibleWidth = math.max(1, width - 2 * inset)
    host.maxOffset = overflow and math.max(0, lastRight - visibleWidth) or 0
    host.offset = math.max(0, math.min(host.maxOffset, host.offset or 0))
    if reveal and overflow then
        for _, button in ipairs(host.buttons) do
            if Selected(host, button._choiceItem.id) then
                if button._choiceX < host.offset then host.offset = button._choiceX
                elseif button._choiceX + button._choiceWidth > host.offset + visibleWidth then
                    host.offset = math.min(host.maxOffset, button._choiceX + button._choiceWidth - visibleWidth)
                end
                break
            end
        end
    end
    host.viewport:ClearAllPoints()
    host.viewport:SetPoint("TOPLEFT", inset + padding, -padding)
    host.viewport:SetSize(visibleWidth, y + height)
    for index, button in ipairs(host.buttons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", host.viewport, "TOPLEFT", button._choiceX - host.offset, -button._choiceY)
        button:SetSize(button._choiceWidth, height)
        LayoutLabel(button)
        button.seam:Hide()
    end
    host.previous:SetShown(overflow); host.nextButton:SetShown(overflow)
    host.previous:SetSize(18, height); host.nextButton:SetSize(18, height)
    LayoutLabel(host.previous); LayoutLabel(host.nextButton)
    host.previous._choiceItem.disabled = host.offset <= 0
    host.nextButton._choiceItem.disabled = host.offset >= host.maxOffset
    Paint(host.previous); Paint(host.nextButton)
    host:SetHeight(y + height + padding * 2)
    if host.tabDivider then
        host.tabDivider:Hide()
        host.tabIndicator:SetShown(host.variant == "tabs")
        -- UI scale 改变后像素尺寸会变：每次重排都按当前 scale 重取偶数像素高度。
        if host.variant == "tabs" then PaintTabIndicator(host) end
    end
    if host.segmentSlider then host.segmentSlider:SetShown(IsSegmented(host)) end
    if host.variant == "tabs" or IsSegmented(host) then
        local target
        for _, button in ipairs(host.buttons) do
            if Selected(host, button._choiceItem.id) then target = button; break end
        end
        if target then
            if host.variant == "tabs" then
                -- 下划线比文字内距少 2；内距被 fit 压窄时随之少缩。
                local tabInset = math.min(GM.size.tabIndicatorInset, math.max(0, host._choiceTabPad - 2))
                local indicatorX = inset + target._choiceX - host.offset + tabInset
                local indicatorWidth = math.max(1, target._choiceWidth - tabInset * 2)
                host.tabIndicator:SetShown(indicatorX + indicatorWidth > inset and indicatorX < inset + visibleWidth)
                local clippedX = math.max(inset, indicatorX)
                local clippedRight = math.min(inset + visibleWidth, indicatorX + indicatorWidth)
                SetMovingTexture(host, host.tabIndicator, clippedX, math.max(1, clippedRight - clippedX), animate)
            else
                -- 选中项写了 selectedFill 才改选中块颜色；换回没写的项时恢复（借出时已重画默认色）。
                if target._choiceItem.selectedFill or host._choiceSliderTinted then
                    local color = SegmentSliderColor(host)
                    UI:SetControlSurface(host.segmentSlider, GM.radius.thumb, color, color)
                    host._choiceSliderTinted = target._choiceItem.selectedFill ~= nil and not host.disabled or nil
                end
                SetMovingTexture(host, host.segmentSlider, padding + target._choiceX, target._choiceWidth, animate)
            end
        elseif host.variant == "tabs" then host.tabIndicator:Hide()
        else host.segmentSlider:Hide() end
    end
    if host.choiceStyle == "connected" then
        -- The shared outline follows the actual rows, not the available line width.
        host:SetWidth(math.max(1, math.min(host:GetWidth(), lastRight + padding * 2)))
    end
    -- A reused host/button can keep the same size under a new parent scale.
    UI:RefreshCompositeSurfaces(host)
    host._choiceLayout = nil
end

local function CopyItems(items)
    local copied, seen = {}, {}
    for _, item in ipairs(items or {}) do
        assert(type(item.id) == "string" or type(item.id) == "number", "Choice item requires a string/number id")
        assert(not seen[item.id], "Duplicate choice id: " .. tostring(item.id))
        seen[item.id] = true
        assert(item.tone == nil or item.tone == "neutral" or item.tone == "include" or item.tone == "exclude", "Unknown choice tone")
        assert(not item.iconOnly or item.icon ~= nil, "Icon-only choice item requires an icon")
        copied[#copied + 1] = { id = item.id, label = tostring(item.label or item.id), icon = item.icon,
            iconOnly = item.iconOnly == true or nil,
            tooltip = item.tooltip, description = item.description or item.desc,
            disabled = item.disabled == true, tone = item.tone,
            selectedFill = item.selectedFill, selectedText = item.selectedText }
    end
    return copied
end

function Methods:SetItems(items)
    if not self._choiceLease then return end
    local copied = CopyItems(items)
    if IsOptionCard(self) then
        local hasDescription = false
        for _, item in ipairs(copied) do if item.description then hasDescription = true; break end end
        self.itemHeight = math.max(self._choiceBaseHeight or GM.size.controlHeight,
            hasDescription and 56 or 0)
    end
    for index = #self.buttons, 1, -1 do Factory:Release(ITEM, self.buttons[index]); self.buttons[index] = nil end
    self.items = copied
    for _, item in ipairs(copied) do self.buttons[#self.buttons + 1] = AcquireButton(self, self.viewport, item) end
    self:SetValue(self.selection)
end

function Methods:Release() Factory:Release(HOST, self) end

local function Create(parent, options, tabs)
    options = options or {}
    local items = CopyItems(options.items)
    local host = Factory:AcquireCompositeHost(HOST, parent)
    for key, method in pairs(Methods) do host[key] = method end
    host._choiceLease, host._choiceRevision = {}, 0
    host._choicePageScroll = not tabs
    host._gridType = "ChoiceGroup"
    host.variant = tabs and "tabs" or "options"
    host.choiceStyle = not tabs and (options.appearance == "compact" or options.appearance == "form" or options.appearance == "dungeon-aura" or options.appearance == "load-card" or options.appearance == "segmented" or options.appearance == "connected") and options.appearance or nil
    host.mode = not tabs and options.mode == "multiple" and "multiple" or "single"
    -- 黑色轨道外观只给分段；每次借出重设，没写就是 nil。
    host.darkTrack = IsSegmented(host) and options.track == "dark" or nil
    host.textOffsetY = IsSegmented(host) and options.textOffsetY or nil
    if IsSegmented(host) then
        PaintSegmentTrack(host)
    elseif host.choiceStyle == "segmented" or host.choiceStyle == "connected" or host.choiceStyle == "compact" or host.choiceStyle == "load-card" then
        UI:SetControlSurface(host, GM.radius.control, Appearance.colors.input, Appearance.colors.inputBorder)
    else
        UI:ClearControlSurface(host)
    end
    host._specPickerTextColor = nil
    -- 浮层外观开关的重画：只有分段画轨道与文字描边，其它选择产品不受影响。
    host._exOverlayRefresh = function(self)
        if not IsSegmented(self) then return end
        PaintSegmentTrack(self)
        for _, button in ipairs(self.buttons or {}) do Paint(button) end
    end
    host.allowEmpty = not tabs and options.allowEmpty == true
    -- 页签选中字色每次借出重设，没写就是 nil。
    assert(not tabs or options.selectedText == nil or type(options.selectedText) == "table", "selectedText must be a color table")
    host.tabSelectedText = tabs and options.selectedText or nil
    -- 页签字号 options.fontSize（可选，正数）：不传时照旧（fieldValue 字号）。
    assert(not tabs or options.fontSize == nil or (type(options.fontSize) == "number" and options.fontSize > 0), "fontSize must be a positive number")
    host.tabFontSize = tabs and options.fontSize or nil
    host.fit = tabs and options.fit == true or nil
    host.sizing = options.sizing == "content" and "content" or "equal"
    if tabs then host.sizing = "content" end
    if host.choiceStyle == "connected" then host.sizing = "content" end
    host.wrap = not tabs and options.wrap ~= false
    host.columns = options.columns and math.max(1, math.floor(options.columns)) or nil
    host.minItemWidth = math.max(16, options.minItemWidth or 44)
    host.gap = math.max(0, options.gap or (tabs and 4 or 3))
    if host.choiceStyle == "connected" then host.gap = 0 end
    -- 分段默认各段等宽；调用方写了 sizing = "content" 才按文字宽。
    if IsSegmented(host) then host.gap, host.wrap = 0, false; if options.sizing ~= "content" then host.sizing = "equal" end end
    if IsOptionCard(host) then host.gap, host.columns, host.sizing, host.wrap = 8, 1, "equal", true end
    host.itemHeight = math.max(18, options.itemHeight or (tabs and GM.size.tabHeight or GM.size.chipHeight))
    if tabs then host.itemHeight = math.max(GM.size.tabHeight, host.itemHeight) end
    if IsSegmented(host) then host.itemHeight = math.max(24, options.itemHeight or GM.size.segmentedItemHeight) end
    host._choiceBaseHeight = host.itemHeight
    host.disabled, host.offset, host.buttons, host.items = options.disabled == true, 0, {}, {}
    host.selection = options.value
    host.onChange = options.onChange
    if tabs and not host.tabDivider then
        host.tabDivider = host:CreateTexture(nil, "BORDER")
        host.tabDivider:SetPoint("BOTTOMLEFT")
        host.tabDivider:SetPoint("BOTTOMRIGHT")
        host.tabDivider:SetHeight(1)
        -- 选中线放在独立的高层 Frame 上：否则会被 Tab 按钮的底色盖住。
        host.tabOverlay = CreateFrame("Frame", nil, host)
        host.tabOverlay:SetAllPoints(host)
        host.tabOverlay:EnableMouse(false)
        -- 选中线是独立 Frame（不是 Texture）：圆角胶囊要走公共 surface 画器。
        -- 初宽给 1，避免首次 Paint 时 GetMetrics 因宽度为 0 直接返回 nil。
        host.tabIndicator = CreateFrame("Frame", nil, host.tabOverlay)
        host.tabIndicator:EnableMouse(false)
        host.tabIndicator:SetSize(1, GM.size.tabIndicatorHeight)
    end
    if host.tabDivider then
        host.tabDivider:SetColorTexture(unpack(GC.tabDivider))
        PaintTabIndicator(host, true)
        host.tabDivider:Hide()
        host.tabIndicator:SetShown(tabs)
    end
    if IsSegmented(host) and not host.segmentSlider then
        host.segmentSlider = CreateFrame("Frame", nil, host)
        host.segmentSlider:EnableMouse(false)
        host.segmentSlider:SetHeight(host.itemHeight - 6) -- 与 Layout 的 padding*2 一致，随后由 Layout 重算
    end
    if host.segmentSlider then
        local sliderColor = host.disabled and Appearance.colors.disabledFill
            or (host.darkTrack and GC.segmentDarkSelected or GC.segmentSelected)
        UI:SetControlSurface(host.segmentSlider, GM.radius.thumb, sliderColor, sliderColor)
        host.segmentSlider:SetShown(IsSegmented(host))
    end
    -- 借出时选中块已画回默认色：每项选中色的标记随之清掉。
    host._choiceSliderTinted = nil
    host.viewport = Factory:Acquire(VIEW, host)
    -- 只有页签需要裁剪（溢出横向滚动）。其它选择产品的按钮高度正好等于 viewport
    -- 高度、左边也与 viewport 左边重合，裁剪会削掉 surface 按物理像素取整后溢出的
    -- 那 1 像素描边与圆角——饱和色（选项卡片）一眼就能看出缺边。
    -- 非页签不会横向溢出：按钮宽已被 min(width, size) 夹住，wrap 会换行，connected 还会收宽。
    host.viewport:SetClipsChildren(host.variant == "tabs")
    host.viewport:EnableMouse(false)
    host.previous = AcquireButton(host, host, { id = "previous", label = "‹" }, function() host:ScrollBy(-100) end)
    host.nextButton = AcquireButton(host, host, { id = "next", label = "›" }, function() host:ScrollBy(100) end)
    host.previous._choiceArrow, host.nextButton._choiceArrow = true, true
    host.previous:SetPoint("TOPLEFT"); host.nextButton:SetPoint("TOPRIGHT")
    if tabs then
        host:EnableMouseWheel(true)
        host:SetScript("OnMouseWheel", function(self, delta) self:ScrollBy(-delta * 80) end)
    else
        host:SetPageScroll()
    end
    host:SetScript("OnSizeChanged", function(self) Layout(self, true) end)
    host:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        local motion = self._choiceMotion
        if motion and motion.toX then
            motion.x, motion.width = motion.toX, motion.toWidth
            motion.texture:ClearAllPoints()
            motion.texture:SetPoint(motion.anchor, self, motion.anchor, motion.x, motion.y)
            motion.texture:SetWidth(motion.width)
            motion.toX, motion.toWidth = nil, nil
        end
    end)
    Factory:AttachPoolRelease(host, function(self)
        self._choiceLease, self.onChange = nil, nil
        self:SetScript("OnSizeChanged", nil); self:SetScript("OnMouseWheel", nil)
        self:SetScript("OnUpdate", nil); self:SetScript("OnHide", nil)
        self._choiceMotion = nil
        if self.tabDivider then self.tabDivider:Hide(); self.tabIndicator:Hide() end
        if self.segmentSlider then self.segmentSlider:Hide() end
        for _, button in ipairs(self.buttons) do Factory:Release(ITEM, button) end
        Factory:Release(ITEM, self.previous); Factory:Release(ITEM, self.nextButton)
        Factory:Release(VIEW, self.viewport)
        self.buttons, self.items, self.selection, self.viewport, self.previous, self.nextButton = nil, nil, nil, nil, nil, nil
    end)
    host:SetWidth(options.width or 240)
    host:SetItems(items)
    return host
end

-- appearance = "segmented": a single-selection track with a sliding solid fill.
-- 页签组 options.fit = true：总宽超过可用宽时先把每项左右内距逐步压到最小值，仍放不下才出滚动箭头；不传时不变。
-- 页签组 options.selectedText = 色表颜色：选中页签的文字色（如 GC.accent）；按下、停用时照旧；不传时不变。
-- 页签组 options.itemHeight = 页签高（不低于 GM.size.tabHeight），options.fontSize = 页签字号；不传时不变。
-- items = { { id, label, icon?, tooltip?, description?, disabled?, tone? }, ... }
-- single value = id; multiple value = { [id] = true }. onChange may return false.
function UI:CreateTabGroup(parent, options) return Create(parent, options, true) end

-- Private construction for CreateSegmentedControl; its public tuple API lives
-- in ExwindGUI. Other choice products use their own local construction here.
function UI:_CreateSegmentedChoice(parent, options)
    local segmented = {}
    for key, value in pairs(options or {}) do segmented[key] = value end
    segmented.appearance, segmented.mode = "segmented", "single"
    return Create(parent, segmented, false)
end

-- 单选卡片列表：竖排，每项一个单选圆点 + 标题 + 可选一行说明。value = 选中项 id。
-- V2 的 optionlist 控件用它（例如 EXAura 二级面板左栏的“当”）。
function UI:CreateOptionList(parent, options)
    local list = {}
    for key, value in pairs(options or {}) do list[key] = value end
    list.appearance, list.mode = nil, "single"
    return Create(parent, list, false)
end

-- 多选：一排独立的勾选小块（选中时右上角主色斜角 + 白勾，与勾选卡片同一画法），
-- 不套外框，可同时选多个，也可全不选。value = { [id] = true }。
-- V2 的 toggles 控件用它，每项各写一个 boolean 字段。
local TOGGLE_GROUP = "EXUI.ToggleGroup"
Factory:InitCompositePool(TOGGLE_GROUP)

local function LayoutToggleGroup(host)
    local x = 0
    for _, card in ipairs(host.cards) do
        local width = card._exToggleWidth
        card:ClearAllPoints()
        PixelUtil.SetPoint(card, "TOPLEFT", host, "TOPLEFT", x, 0, 0, 0)
        card:SetSize(width, GM.size.controlHeight)
        x = x + width + GM.settings.toggleItemGap
    end
end

function UI:CreateToggleGroup(parent, options)
    local host = Factory:AcquireCompositeHost(TOGGLE_GROUP, parent)
    host:SetHeight(GM.size.controlHeight)
    host.cards, host._toggleValue = {}, {}
    for id, selected in pairs(options.value or {}) do host._toggleValue[id] = selected end
    for index, item in ipairs(options.items) do
        local card = UI:CreateCheckbox(host, item.label, host._toggleValue[item.id] == true, function(checked)
            local next = {}
            for id, selected in pairs(host._toggleValue) do next[id] = selected end
            next[item.id] = checked == true or nil
            host._toggleValue = next
            options.onChange(next)
        end)
        UI:PrepareSettingsListControl(card, { presentation = "card" })
        UI:ApplyControlAppearance(card)
        -- 按卡片标题（与显示同一字体）量文字宽。
        card._exToggleWidth = math.ceil(card.checkbox._exSettingsCardSurface.Title:GetUnboundedStringWidth())
            + GM.settings.toggleItemPadX
        host.cards[index] = card
        card._exToggleId = item.id
    end
    function host:NaturalWidth()
        local width = 0
        for index, card in ipairs(self.cards) do
            width = width + card._exToggleWidth + (index > 1 and GM.settings.toggleItemGap or 0)
        end
        return width
    end
    function host:SetValue(selection)
        self._toggleValue = {}
        for id, selected in pairs(selection or {}) do self._toggleValue[id] = selected end
        for _, card in ipairs(self.cards) do
            card:SetChecked(self._toggleValue[card._exToggleId] == true)
            UI:ApplyControlAppearance(card)
        end
    end
    function host:SetDisabled(disabled)
        for _, card in ipairs(self.cards) do
            card.checkbox:SetEnabled(not disabled)
            UI:ApplyControlAppearance(card)
        end
    end
    host:SetScript("OnSizeChanged", LayoutToggleGroup)
    Factory:AttachPoolRelease(host, function(frame)
        frame:SetScript("OnSizeChanged", nil)
        for index = #frame.cards, 1, -1 do
            local card = frame.cards[index]
            UI:RestoreSettingsListControl(card)
            Factory:ReleaseGridWidget(card)
            frame.cards[index] = nil
        end
        frame.cards, frame._toggleValue = nil, nil
        frame.NaturalWidth, frame.SetValue, frame.SetDisabled = nil, nil, nil
    end)
    host:SetWidth(host:NaturalWidth())
    LayoutToggleGroup(host)
    host:Show()
    return host
end

-- A compact trigger opens four armor columns in a floating choice surface.
-- The caller owns only the spec ID; no module configuration is accessed here.
local SPEC_PICKER = "EXUI.SpecPicker"
local SPEC_PICKER_POPUP = "EXUI.SpecPickerPopup"
local SPEC_PICKER_BLOCKER = "EXUI.SpecPickerBlocker"
local SPEC_PICKER_TRIGGER = "EXUI.SpecPickerDropdown"
local SPEC_POPUP_WIDTH = GM.size.specPopupWidth
Factory:InitCompositePool(SPEC_PICKER)
Factory:InitCompositePool(SPEC_PICKER_POPUP)
Factory:InitPool(SPEC_PICKER_BLOCKER, "Button")
Factory:InitPool(SPEC_PICKER_TRIGGER, "Button", nil, function(frame)
    frame._gridType = "GridDropdown"
    frame.Text = UI:CreateVisualFontString(frame, _G.EXFONTFRAME, "GameFontHighlight")
    frame.Text:SetJustifyH("LEFT")
    frame.Text:SetWordWrap(false)
    frame.IsMenuOpen = function(self)
        local owner = self._specPickerOwner
        return owner and owner.popup and owner.popup:IsShown() or false
    end
end)

local function LayoutSpecPopup(popup)
    local gap, inset = GM.space.specColumnGap, GM.space.specPopupInset
    local popupWidth = math.max(1, math.min(SPEC_POPUP_WIDTH, UIParent:GetWidth() - inset * 2))
    local columnWidth = math.max(1, (popupWidth - inset * 2 - gap * 3) / 4)
    local height = 0
    for index, armorKey in ipairs(popup.armorKeys) do
        local x = inset + (index - 1) * (columnWidth + gap)
        local title = popup.headers[index]
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -inset)
        title:SetWidth(columnWidth)
        if not title._specDivider then title._specDivider = popup:CreateTexture(nil, "ARTWORK") end
        title._specDivider:SetColorTexture(unpack(GC.popupDivider))
        title._specDivider:ClearAllPoints()
        title._specDivider:SetPoint("TOPLEFT", popup, "TOPLEFT", x,
            -(GM.size.specColumnHeaderHeight - GM.space.specHeaderDividerGap))
        title._specDivider:SetSize(columnWidth, 1 / popup:GetEffectiveScale())
        title._specDivider:Show()
        local y = GM.size.specColumnHeaderHeight
        for _, classID in ipairs(_G.EXDB.ArmorTypes[armorKey].classIDs) do
            local heading = popup.classHeaders[classID]
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -y)
            heading:SetWidth(columnWidth)
            y = y + GM.size.specClassHeaderHeight
            local group = popup.groups[classID]
            group:ClearAllPoints()
            group:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -y)
            group:SetWidth(columnWidth)
            group:SetFrameLevel(popup:GetFrameLevel() + 1)
            UI:ClearControlSurface(group)
            for _, button in ipairs(group.buttons) do
                if button._specPickerDivider then button._specPickerDivider:Hide() end
                if not button._specTile then
                    local tile = CreateFrame("Frame", nil, button)
                    tile:EnableMouse(false)
                    tile.image = UI:CreateRoundedImage(tile, GM.radius.popup, true)
                    tile.image:SetPoint("TOPLEFT", 2, -2)
                    tile.image:SetPoint("BOTTOMRIGHT", -2, 2)
                    tile.image:SetTexCoord(.08, .92, .08, .92)
                    tile.badge = CreateFrame("Frame", nil, tile)
                    tile.badge:EnableMouse(false)
                    tile.badge:SetAllPoints(tile)
                    tile.check = tile.badge:CreateTexture(nil, "OVERLAY", nil, 7)
                    tile.check:SetTexture("Interface\\AddOns\\ExwindCore\\Textures\\GUI\\GlyphCheck.tga")
                    tile.check:SetSize(14, 14)
                    tile.check:SetPoint("TOPRIGHT", 3, 3)
                    tile.check:SetVertexColor(1, .82, .3, 1)
                    button._specTile = tile
                end
                local tile = button._specTile
                tile:SetFrameLevel(button:GetFrameLevel() + 1)
                tile.badge:SetFrameLevel(tile.image:GetFrameLevel() + 2)
                tile:ClearAllPoints()
                -- 图标格垂直居中：格高变化时不用再跟着调锚点。
                tile:SetPoint("CENTER", button, "CENTER", 0, 0)
                local padding = GM.space.specTilePadding
                local iconSize = math.min(GM.size.specTileSize,
                    math.max(GM.size.specTileMinSize, button:GetWidth() - padding * 2))
                tile:SetSize(iconSize, iconSize)
                -- 外层的 inset 是浮层四周内缩；这里的 edge 是贴图到格子边缘的 1 物理像素。
                local edge = PixelUtil.GetNearestPixelSize(1, tile:GetEffectiveScale(), 1)
                tile.image:ClearAllPoints()
                tile.image:SetPoint("TOPLEFT", edge, -edge)
                tile.image:SetPoint("BOTTOMRIGHT", -edge, edge)
                tile.image:SetCornerRadius(GM.radius.popup - edge)
                tile.image:SetTexture(button._choiceItem.icon)
                tile:Show()
                button.icon:Hide()
                LayoutLabel(button)
                Paint(button)
            end
            y = y + group:GetHeight() + GM.space.specClassGap
        end
        height = math.max(height, y)
    end
    -- 最后一个职业块后面已经加过一次块间距，换成浮层内缩，让上下留白对称。
    popup:SetSize(popupWidth, height - GM.space.specClassGap + GM.space.specPopupInset)
end

local BuildSpecPopup
local SpecPickerMethods = {}

function SpecPickerMethods:GetValue()
    return self._specPickerLease and Copy(self.value) or nil
end

-- Programmatic selection is silent; only a user click calls onSelect.
function SpecPickerMethods:SetValue(specID)
    if not self._specPickerLease then return end
    local db = _G.EXDB
    local id = tonumber(specID)
    local spec = id and db.SpecByID[id]
    if self.multiple then
        self.value = {}
        for key, selected in pairs(type(specID) == "table" and specID or {}) do
            local specKey = tonumber(key)
            if selected == true and db.SpecByID[specKey] then self.value[specKey] = true end
        end
    else
        self.value = spec and id or nil
    end
    if self.popup then
        for classID, group in pairs(self.popup.groups) do
            group:SetValue(self.multiple and self.value or (spec and spec.classID == classID and id or nil))
        end
        LayoutSpecPopup(self.popup)
    end
    local text = (_G.ExwindTools.L and _G.ExwindTools.L["请选择..."]) or "请选择..."
    if self.multiple then
        local labels = {}
        for _, entry in ipairs(db.Specs) do
            if self.value[entry.id] then labels[#labels + 1] = entry.names[self.locale] or entry.names.enUS end
        end
        if #labels > 0 then text = table.concat(labels, ", ") end
    elseif spec then
        local class = db.Classes[spec.classID]
        text = (class.names[self.locale] or class.names.enUS) .. " · " ..
            (spec.names[self.locale] or spec.names.enUS)
        text = "|cff" .. class.colorHex .. text .. "|r"
    end
    self.trigger.Text:SetText(text)
end

function SpecPickerMethods:HidePopup()
    if self.popup then self.popup:Hide() end
    if self.blocker then self.blocker:Hide() end
    if UI._openSpecPicker == self then UI._openSpecPicker = nil end
end

function SpecPickerMethods:ShowPopup()
    if not self._specPickerLease then return end
    if UI._openSpecPicker and UI._openSpecPicker ~= self then UI._openSpecPicker:HidePopup() end
    if not self.popup then BuildSpecPopup(self) end
    local popup = self.popup
    local level = math.max(9500, self:GetFrameLevel() + 2)
    self.blocker:SetFrameLevel(level)
    popup:SetFrameLevel(level + 2)
    LayoutSpecPopup(popup)
    popup:ClearAllPoints()
    local opensUp = self:GetBottom() and self:GetBottom() < popup:GetHeight() + 8
    local opensLeft = self:GetLeft() and self:GetLeft() + popup:GetWidth() > UIParent:GetRight()
    if opensUp then
        popup:SetPoint(opensLeft and "BOTTOMRIGHT" or "BOTTOMLEFT", self,
            opensLeft and "TOPRIGHT" or "TOPLEFT", 0, 4)
    else
        popup:SetPoint(opensLeft and "TOPRIGHT" or "TOPLEFT", self,
            opensLeft and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -4)
    end
    if self.blocker.SetPropagateKeyboardInput then self.blocker:SetPropagateKeyboardInput(true) end
    self.blocker:Show()
    popup:Show()
    LayoutSpecPopup(popup)
    UI._openSpecPicker = self
end

function SpecPickerMethods:Release()
    if self._specPickerLease then Factory:Release(SPEC_PICKER, self) end
end

BuildSpecPopup = function(picker)
    local db = _G.EXDB
    local popup = Factory:AcquireCompositeHost(SPEC_PICKER_POPUP, UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(9502)
    popup:SetClampedToScreen(true)
    popup.armorKeys = db.ArmorTypeOrder
    popup.groups = {}
    popup.headers = popup.headers or {}
    popup.classHeaders = popup.classHeaders or {}
    popup.classIcons = popup.classIcons or {}
    UI:SetControlSurface(popup, GM.radius.popup, GC.popup, GC.popupBorder)
    picker.popup = popup

    for index, armorKey in ipairs(popup.armorKeys) do
        local armor = db.ArmorTypes[armorKey]
        local title = popup.headers[index]
        if not title then
            title = UI:CreateVisualFontString(popup, _G.EXFONTFRAME, "GameFontNormalSmall")
            title:SetJustifyH("LEFT")
            title:SetJustifyV("MIDDLE")
            Appearance.ApplyTextRole(title, "title")
            popup.headers[index] = title
        end
        title:SetText((armor.names[picker.locale] or armor.names.enUS) .. "  |cff7f909f(" .. #armor.classIDs .. ")|r")
        title:Show()

        for _, classID in ipairs(armor.classIDs) do
            local class = db.Classes[classID]
            local className = class.names[picker.locale] or class.names.enUS
            local heading = popup.classHeaders[classID]
            if not heading then
                heading = UI:CreateVisualFontString(popup, _G.EXFONTFRAME, "GameFontHighlight")
                heading:SetJustifyH("LEFT")
                heading:SetWordWrap(false)
                popup.classHeaders[classID] = heading
            end
            local font = heading:GetFont()
            heading:SetFont(font, GM.font.title, "OUTLINE")
            local hex = class.colorHex
            local classColor = {tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1}
            heading:SetTextColor(unpack(classColor))
            heading:SetText(className)
            heading:Show()
            local items = {}
            for _, spec in ipairs(db.SpecsByClassID[classID] or {}) do
                items[#items + 1] = {
                    id = spec.id,
                    label = spec.names[picker.locale] or spec.names.enUS,
                    tooltip = className .. " · " .. (spec.names[picker.locale] or spec.names.enUS),
                    icon = spec.icon,
                }
            end
            table.sort(items, function(a, b)
                local roleA, roleB = db:GetSpecRolePriority(a.id), db:GetSpecRolePriority(b.id)
                if roleA ~= roleB then return roleA < roleB end
                return a.id < b.id
            end)
        local group = Create(popup, {
            items = items,
            width = (SPEC_POPUP_WIDTH - GM.space.specPopupInset * 2 - GM.space.specColumnGap * 3) / 4,
            itemHeight = GM.size.specTileSize + GM.space.specTilePadding * 2,
            columns = #items,
            mode = picker.multiple and "multiple" or "single",
            gap = GM.space.specTileGap,
            appearance = "compact",
            allowEmpty = true,
            onChange = function(specID)
                if picker.multiple then
                    local selected = picker:GetValue()
                    for _, item in ipairs(items) do selected[item.id] = specID[item.id] == true or nil end
                    picker:SetValue(selected)
                    if picker.onSelect then picker.onSelect(picker:GetValue()) end
                    return
                end
                if not specID then
                    picker:SetValue(picker.value)
                    picker:HidePopup()
                    return
                end
                picker:SetValue(specID)
                picker:HidePopup()
                if picker.onSelect then
                    local spec = specID and db.SpecByID[specID]
                    picker.onSelect(specID, spec, spec and db.Classes[spec.classID])
                end
            end,
        }, false)
        group._specPickerTextColor = classColor
        group._specPickerMultiple = picker.multiple
        group:SetPageScroll()
        popup.groups[classID] = group
        end
    end
    LayoutSpecPopup(popup)
    popup:Hide()

    Factory:AttachPoolRelease(popup, function(self)
        for _, group in pairs(self.groups) do group:Release() end
        for _, heading in pairs(self.classHeaders) do heading:SetText(""); heading:Hide() end
        for _, icon in pairs(self.classIcons) do icon:Hide() end
        self.groups, self.armorKeys = nil, nil
        for _, title in ipairs(self.headers) do
            title:SetText(""); title:Hide()
            if title._specDivider then title._specDivider:Hide() end
        end
    end)

    local blocker = Factory:Acquire(SPEC_PICKER_BLOCKER, UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:SetFrameLevel(9500)
    blocker:ClearAllPoints()
    blocker:SetAllPoints(UIParent)
    blocker:EnableMouse(true)
    blocker:EnableKeyboard(true)
    if blocker.SetPropagateKeyboardInput then blocker:SetPropagateKeyboardInput(true) end
    blocker:SetScript("OnClick", function() picker:HidePopup() end)
    blocker:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            picker:HidePopup()
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    blocker:Hide()
    picker.blocker = blocker

    picker:SetValue(picker.value)
end

function UI:CreateSpecPicker(parent, width, value, onSelect, options)
    local db = _G.EXDB
    assert(db and db.ArmorTypes and db.SpecByID, "CreateSpecPicker requires EXDB")
    local picker = Factory:AcquireCompositeHost(SPEC_PICKER, parent)
    for key, method in pairs(SpecPickerMethods) do picker[key] = method end
    picker._specPickerLease = true
    picker.multiple = type(options) == "table" and options.mode == "multiple"
    local localeAPI = rawget(_G, "ExwindLocale")
    picker.locale = type(localeAPI) == "table" and type(localeAPI.GetCurrentLocale) == "function"
        and localeAPI.GetCurrentLocale() or GetLocale()
    picker.onSelect = onSelect
    picker.popup, picker.blocker = nil, nil
    picker:SetSize(width or 190, GM.size.dropdownHeight)

    picker.trigger = Factory:Acquire(SPEC_PICKER_TRIGGER, picker)
    picker.trigger._specPickerOwner = picker
    picker.trigger:Enable()
    picker.trigger:SetScript("OnClick", function()
        if picker.popup and picker.popup:IsShown() then picker:HidePopup() else picker:ShowPopup() end
    end)
    UI:ApplyControlAppearance(picker.trigger)
    picker.trigger:SetAllPoints(picker)
    picker:SetScript("OnSizeChanged", function(self)
        if self._specPickerLease then self.trigger:SetSize(self:GetSize()) end
    end)
    picker:SetScript("OnHide", function(self) self:HidePopup() end)

    Factory:AttachPoolRelease(picker, function(self)
        self:HidePopup()
        self._specPickerLease, self.onSelect, self.value, self.locale = nil, nil, nil, nil
        self.multiple = nil
        self:SetScript("OnSizeChanged", nil)
        self:SetScript("OnHide", nil)
        self.trigger._specPickerOwner = nil
        Factory:Release(self.trigger._fromPool, self.trigger)
        if self.blocker then
            self.blocker:EnableKeyboard(false)
            self.blocker:SetScript("OnKeyDown", nil)
            self.blocker:SetScript("OnClick", nil)
            Factory:Release(SPEC_PICKER_BLOCKER, self.blocker)
        end
        if self.popup then Factory:Release(SPEC_PICKER_POPUP, self.popup) end
        self.trigger, self.blocker, self.popup = nil, nil, nil
    end)
    picker:SetValue(value)
    return picker
end
