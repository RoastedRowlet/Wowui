-- 取色面板：Core 自己的颜色选择窗口，代替暴雪 ColorPickerFrame；外壳是 Core 浮窗（CreateFloatingWindow），空白处能拖。
-- 左边色轮 + 明度条 + 透明度条由引擎 ColorSelect 画；右栏上下两块新旧对比色（点下面的原色 = 恢复打开时的颜色）、
-- 十六进制输入、透明度百分比输入；底下三排色块：常用色（GC.colorPresets）、全部职业色（C_ClassColor）、
-- 物品品质色（C_Item.GetItemQualityColor），后两排打开时从游戏取，点一下换成该色，透明度不变。
-- 透明度条一律显示、都能调；调用方没要透明度（hasOpacity 不是 true）时照旧由它自己的回调决定存不存。
-- 用法同暴雪取色器：picker = UI:GetColorPicker()；picker:SetupColorPickerAndShow(info, owner)，
--   info = { r, g, b, opacity, hasOpacity, swatchFunc, opacityFunc, cancelFunc }；换色、换透明度都调 swatchFunc
--   （没给 swatchFunc 才调 opacityFunc），回调里用 picker:GetColorRGB() / picker:GetColorAlpha() 取当前色。
--   owner 可选：面板贴在它旁边（用户拖过之后就留在拖到的位置），picker:GetOwner() 取回。打开时的颜色不回调。
-- 点面板外面（owner 除外）或点 × 都是关掉面板、收下当前色，调用方在 OnHide 里收尾；
-- cancelFunc / previousValues 只是存着，留给调用方自己撤销时用。
local UI = _G.ExwindTools.UI
local GM = _G.ExwindTools.GUIMetrics
local L = _G.ExwindTools.L
local function Colors() return _G.ExwindTools.GUIColors end

local THUMB_FILE = "Interface\\Buttons\\UI-ColorPicker-Buttons"
local picker

local function ToHex(r, g, b)
    return string.format("%02X%02X%02X", math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

local function SameColor(color, r, g, b)
    return math.abs(color[1] - r) < 0.005 and math.abs(color[2] - g) < 0.005 and math.abs(color[3] - b) < 0.005
end

-- 当前色画到新色块、两个输入框（正在打字的不动）和色块（当前色描亮边）。
local function Refresh()
    local GC = Colors()
    local r, g, b = picker.select:GetColorRGB()
    local a = picker.select:GetColorAlpha()
    UI:SetControlSurface(picker.current, GM.radius.thumb, { r, g, b, a }, GC.subcardBorder)
    if not picker.hexBox:HasFocus() then picker.hexBox:SetText("#" .. ToHex(r, g, b)) end
    if not picker.alphaBox:HasFocus() then picker.alphaBox:SetText(math.floor(a * 100 + .5) .. "%") end
    for _, chip in ipairs(picker.chips) do
        local color = chip._exColor
        local border = SameColor(color, r, g, b) and GC.text or (chip:IsMouseOver() and GC.cardHoverBorder or GC.subcardBorder)
        UI:SetControlSurface(chip, GM.radius.thumb, color, border)
    end
end

local function Notify()
    if picker.swatchFunc then
        picker.swatchFunc()
    elseif picker.opacityFunc then
        picker.opacityFunc()
    end
end

-- 程序设色：ColorSelect 自己的回调不算，设完再统一通知一次（quiet 时不通知）。
local function SetColor(r, g, b, a, quiet)
    picker._exQuiet = true
    picker.select:SetColorRGB(r, g, b)
    if a then picker.select:SetColorAlpha(a) end
    picker._exQuiet = nil
    Refresh()
    if not quiet then Notify() end
end

local function ApplyHexText(text)
    local hex = (text or ""):gsub("[^%x]", "")
    if #hex == 3 then hex = hex:gsub("(%x)", "%1%1") end
    if #hex ~= 6 then Refresh(); return end
    local r, g, b = picker.select:GetColorRGB()
    if hex:upper() == ToHex(r, g, b) then Refresh(); return end
    SetColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
end

local function ApplyAlphaText(text)
    local number = tonumber(((text or ""):gsub("[%%%s]", "")))
    if not number then Refresh(); return end
    local a = math.max(0, math.min(100, number)) / 100
    if math.abs(a - picker.select:GetColorAlpha()) < 0.005 then Refresh(); return end
    local r, g, b = picker.select:GetColorRGB()
    SetColor(r, g, b, a)
end

-- 色轮 | 明度条 | 透明度条 | 右栏，底下三排色块。
local function Layout()
    local wheel, bar, gap = GM.size.colorPickerWheelSize, GM.size.colorPickerBarWidth, GM.space.colorPickerGap
    local side, sideGap = GM.size.colorPickerSideWidth, GM.space.colorPickerSideGap
    local selectWidth = wheel + (gap + bar) * 2
    local pad = picker.contentPadding
    local rows = #picker.rows
    picker:SetSize(pad * 2 + selectWidth + gap + side, GM.size.floatingHeaderHeight + wheel + gap
        + rows * GM.size.colorPresetSize + (rows - 1) * sideGap + pad)
    picker.select:SetSize(selectWidth, wheel)

    local swatchHeight = GM.size.colorPickerSwatchHeight
    picker.current:SetSize(side, swatchHeight)
    picker.original:SetSize(side, swatchHeight)
    picker.hexBox:ClearAllPoints()
    picker.hexBox:SetPoint("TOPLEFT", picker.original, "BOTTOMLEFT", 0, -sideGap)
    picker.alphaBox:ClearAllPoints()
    picker.alphaBox:SetPoint("TOPLEFT", picker.hexBox, "BOTTOMLEFT", 0, -sideGap)
end

-- 三排色块的颜色：常用色、全部职业色（按职业 ID）、物品品质色（粗糙到传家宝），后两排从游戏取。
local function SwatchRows()
    local classes, qualities = {}, {}
    for classID = 1, GetNumClasses() do
        local _, classFile = GetClassInfo(classID)
        local color = classFile and C_ClassColor.GetClassColor(classFile)
        if color then classes[#classes + 1] = { color:GetRGB() } end
    end
    for quality = Enum.ItemQuality.Poor, Enum.ItemQuality.Heirloom do
        local r, g, b = C_Item.GetItemQualityColor(quality)
        qualities[#qualities + 1] = { r, g, b }
    end
    return { Colors().colorPresets, classes, qualities }
end

local function Build()
    -- 用户拖过（标题栏或空白处）就记下，之后再打开不再贴回 owner 旁边。
    picker = UI:CreateFloatingWindow({ width = 300, height = 200, title = _G.COLOR_PICKER, closable = true,
        strata = "FULLSCREEN_DIALOG", dragAnywhere = true, background = "panel",
        onDragStop = function(window) window._exPlaced = true end })
    local content = picker.content
    local wheelSize, bar, gap = GM.size.colorPickerWheelSize, GM.size.colorPickerBarWidth, GM.space.colorPickerGap

    -- ColorSelect 必须自己吃鼠标：不吃时按在色轮上拖，按下落到窗口本身，窗口跟着鼠标走，
    -- 色轮又按移动中的窗口算取色点，两边一起算坐标，窗口就飘走了。
    local select = CreateFrame("ColorSelect", nil, content)
    select:EnableMouse(true)
    select:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local wheel = select:CreateTexture(nil, "ARTWORK")
    wheel:SetSize(wheelSize, wheelSize)
    wheel:SetPoint("TOPLEFT", select, "TOPLEFT", 0, 0)
    select:SetColorWheelTexture(wheel)
    local wheelThumb = select:CreateTexture(nil, "OVERLAY")
    wheelThumb:SetTexture(THUMB_FILE)
    wheelThumb:SetTexCoord(0, 0.15625, 0, 0.625)
    wheelThumb:SetSize(10, 10)
    select:SetColorWheelThumbTexture(wheelThumb)

    local value = select:CreateTexture(nil, "ARTWORK")
    value:SetSize(bar, wheelSize)
    value:SetPoint("TOPLEFT", wheel, "TOPRIGHT", gap, 0)
    select:SetColorValueTexture(value)
    local valueThumb = select:CreateTexture(nil, "OVERLAY")
    valueThumb:SetTexture(THUMB_FILE)
    valueThumb:SetTexCoord(0.25, 1, 0, 0.875)
    valueThumb:SetSize(bar + 16, 10)
    select:SetColorValueThumbTexture(valueThumb)

    -- 透明度条底下垫棋盘格，透明的部分看得出来。
    local checker = select:CreateTexture(nil, "BACKGROUND")
    checker:SetAtlas("colorpicker-checkerboard")
    checker:SetSize(bar, wheelSize)
    checker:SetPoint("TOPLEFT", value, "TOPRIGHT", gap, 0)
    local alphaBar = select:CreateTexture(nil, "ARTWORK")
    alphaBar:SetAllPoints(checker)
    select:SetColorAlphaTexture(alphaBar)
    local alphaThumb = select:CreateTexture(nil, "OVERLAY")
    alphaThumb:SetTexture(THUMB_FILE)
    alphaThumb:SetTexCoord(0.25, 1, 0, 0.875)
    alphaThumb:SetSize(bar + 16, 10)
    select:SetColorAlphaThumbTexture(alphaThumb)
    select:SetScript("OnColorSelect", function()
        if picker._exQuiet then return end
        Refresh()
        Notify()
    end)
    picker.select = select

    -- 右栏：新色在上、原色在下（点原色恢复），再下面十六进制、透明度两个输入框。
    local current = CreateFrame("Frame", nil, content)
    current:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    local original = CreateFrame("Button", nil, content)
    original:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, 0)
    original:SetScript("OnClick", function()
        local prev = picker.previousValues
        SetColor(prev.r, prev.g, prev.b, prev.a or 1)
    end)
    original:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["点一下恢复打开时的颜色"])
        GameTooltip:Show()
    end)
    original:SetScript("OnLeave", function() GameTooltip:Hide() end)
    picker.current, picker.original = current, original

    local side = GM.size.colorPickerSideWidth
    picker.hexBox = UI:CreateEditBox(content, "", side, GM.size.inputHeight, nil, { onEditFocusLost = ApplyHexText })
    picker.alphaBox = UI:CreateEditBox(content, "", side, GM.size.inputHeight, nil, { onEditFocusLost = ApplyAlphaText })

    picker.chips, picker.rows = {}, SwatchRows()
    local chipSize, chipGap, rowGap = GM.size.colorPresetSize, GM.space.colorPresetGap, GM.space.colorPickerSideGap
    local rowTop = -(wheelSize + gap)
    for _, row in ipairs(picker.rows) do
        for index, color in ipairs(row) do
            local chip = CreateFrame("Button", nil, content)
            chip:SetSize(chipSize, chipSize)
            chip:SetPoint("TOPLEFT", content, "TOPLEFT", (index - 1) * (chipSize + chipGap), rowTop)
            chip:SetScript("OnClick", function() SetColor(color[1], color[2], color[3]) end)
            chip:SetScript("OnEnter", Refresh)
            chip:SetScript("OnLeave", Refresh)
            chip._exColor = color
            picker.chips[#picker.chips + 1] = chip
        end
        rowTop = rowTop - chipSize - rowGap
    end

    -- 点面板外面就关掉（按住 owner 不算：owner 自己的点击决定收起还是换人）。
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function()
        local foci = GetMouseFoci()
        if DoesAncestryIncludeAny(picker, foci) then return end
        if picker._exOwner and DoesAncestryIncludeAny(picker._exOwner, foci) then return end
        picker:Hide()
    end)
    picker:HookScript("OnShow", function() watcher:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    -- 关面板时正在打字的框先按打的字收下，再轮到调用方的 OnHide 收尾（本钩子最先挂，最先跑）。
    picker:HookScript("OnHide", function()
        watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        picker.hexBox:ClearFocus()
        picker.alphaBox:ClearFocus()
    end)

    function picker:GetColorRGB() return self.select:GetColorRGB() end
    function picker:GetColorAlpha() return self.select:GetColorAlpha() end
    function picker:GetOwner() return self._exOwner end
    function picker:GetPreviousValues()
        local prev = self.previousValues
        return prev.r, prev.g, prev.b, prev.a
    end
    function picker:SetupColorPickerAndShow(info, owner)
        -- 上一位没打完的字先交给上一位。
        self.hexBox:ClearFocus()
        self.alphaBox:ClearFocus()
        self.swatchFunc, self.opacityFunc, self.cancelFunc = info.swatchFunc, info.opacityFunc, info.cancelFunc
        self.hasOpacity = info.hasOpacity == true
        self.opacity = info.opacity
        self.previousValues = { r = info.r, g = info.g, b = info.b, a = info.opacity }
        self._exOwner = owner
        Layout()
        local a = info.opacity or 1
        UI:SetControlSurface(self.original, GM.radius.thumb, { info.r, info.g, info.b, a }, Colors().subcardBorder)
        SetColor(info.r, info.g, info.b, a, true)
        if owner and not self._exPlaced and not self:IsDragging() then self:SetAnchor({ frame = owner }) end
        self:Show()
    end
end

-- 全项目共用一个取色面板，第一次用时才建；建好后 UI.colorPicker 就是它。
function UI:GetColorPicker()
    if not picker then
        Build()
        UI.colorPicker = picker
    end
    return picker
end
