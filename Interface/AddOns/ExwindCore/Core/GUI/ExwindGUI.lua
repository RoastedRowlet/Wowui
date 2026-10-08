-- =========================================================
-- ExwindGUI.lua: 基础控件、公共绘制、菜单及标准页面辅助。
-- SettingsCard/Row/Table 与通用 Flow: ExwindGUISettingsList.lua。
-- Font/Icon/Sound 等组合封装: ExwindGUIComposite.lua。
-- 加载顺序: 本文件 -> SettingsList -> Composite -> ControlAppearance。
-- 定位: CreateCheckbox(含 Switch/Card/Card 外观)、CreateSlider、CreateColorButton、
-- CreateEditBox、CreateDropdown/LSM、CreateButton；页面辅助 CreateStandardModulePage。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 确保 EXUI 命名空间存在（可能在 ExwindToolsUI.lua 之前加载）
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI
_G.ExwindToolsUI = EXUI

local LSM = LibStub("LibSharedMedia-3.0")
local L = ExwindTools.L
local GM = ExwindTools.GUIMetrics
if not GM then error("ExwindGUIMetrics.lua must load before ExwindGUI.lua") end

-- [Core] 严格遵照指令：只许使用游戏默认字体路径，禁止任何硬编码引用
local defaultFontPath, defaultFontSize, defaultFontFlags = _G.GameFontHighlight:GetFont()

-- DropdownButton 的箭头、文字与背景切片以 30px 为一组固定几何（GM.size.dropdownHeight）。
-- Grid 可以决定它在逻辑网格中占几格，但不能把物理按钮高度拉伸；
-- 否则右侧箭头仍维持模板尺寸，视觉会变形。LSM 与普通下拉共用此几何约束，
-- 数据/菜单实现仍各自独立。
EXUI.GridDropdownHeight = GM.size.dropdownHeight
-- Slider 的完整物理高度包含同一控件内的标题行与下方轨道。
-- Grid 与所有组合设置组都复用这个几何，不能再让标题/数值框溢出到控件外。
EXUI.GridSliderHeight = GM.size.sliderHeight

-- 所有 EXUI Collection / PanelPreview 都必须带稳定模块身份。这个身份不是
-- 页面标签，也不能由 DB 开关决定；它用于把 Duration 合同和少数历史例外收在
-- Core，而不是让任一业务模块自行开启 OnUpdate。
local LEGACY_DURATION_OWNERS = {
    ["ExBoss.TimerBar"] = true,
    ["ExBoss.BunBar"] = true,
}
local durationViolations = {}

function EXUI:RequireModuleKey(moduleKey, apiName)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error((apiName or "EXUI") .. " requires non-empty MODULE_KEY", 3)
    end
    return moduleKey
end

function EXUI:CanUseLegacyDurationPath(moduleKey)
    self:RequireModuleKey(moduleKey, "EXUI legacy-duration gate")
    return LEGACY_DURATION_OWNERS[moduleKey] == true
end

function EXUI:RequireLegacyRuntimeTickOwner(moduleKey, apiName)
    self:RequireModuleKey(moduleKey, apiName or "EXUI legacy runtime tick")
    if not LEGACY_DURATION_OWNERS[moduleKey] then
        error((apiName or "EXUI legacy runtime tick") .. " is reserved for ExBoss.TimerBar and ExBoss.BunBar", 3)
    end
    return true
end

function EXUI:ReportDurationViolation(moduleKey, renderer)
    self:RequireModuleKey(moduleKey, "EXUI duration gate")
    local key = moduleKey .. ":" .. tostring(renderer or "renderer")
    if durationViolations[key] then return false end
    durationViolations[key] = true
    local message = "EXUI Duration violation: " .. moduleKey
        .. " must provide DUR; legacy start/duration and Lua OnUpdate are reserved for ExBoss.TimerBar and ExBoss.BunBar."
    if _G.print then _G.print(message) end
    if _G.geterrorhandler then _G.geterrorhandler()(message) end
    return false
end

-- Grid 只负责把逻辑格转换成像素；复合控件才知道自己的真实最小/首选高度。
-- 这个 registry 是纯测量合同：不得创建 Frame、不得读取屏幕尺寸、不得延迟测量。
-- 页面 schema 以 `measure = true` 显式选择它，未选择的旧页面保持原有 x/y/w/h 行为。
EXUI.GridComponentMeasures = EXUI.GridComponentMeasures or {}

function EXUI:RegisterGridComponentMeasure(componentType, measure)
    if type(componentType) ~= "string" or componentType == "" or type(measure) ~= "function" then
        return false
    end
    self.GridComponentMeasures[string.lower(componentType)] = measure
    return true
end

function EXUI:MeasureGridComponent(componentType, width, opts, db, item)
    local measure = type(componentType) == "string" and self.GridComponentMeasures[string.lower(componentType)]
    if type(measure) ~= "function" then return nil end
    return measure(math.max(1, tonumber(width) or 1), opts or {}, db, item)
end

local function ApplyGridDropdownSize(dropdown, width)
    dropdown:SetSize(width or GM.size.controlDefaultWidth, GM.size.dropdownHeight)
    dropdown._exGridFixedHeight = GM.size.dropdownHeight
end

-- DropdownButton 的菜单不是子 Frame，而是暴雪 Menu 系统按“按钮自身”的 strata
-- 单独创建。池化控件会保留上一次的 strata；若不在这里同步，组合弹窗虽然在
-- TOOLTIP 层，里面的下拉菜单仍可能以 MEDIUM 层打开并被弹窗遮住。
local function SyncDropdownMenuLayer(dropdown, parent)
    -- Menu proxies live under UIParent; submenu proxies anchor to a parent row.
    -- Follow only public owner/parent/menu-anchor links, never the private menu.
    if not dropdown.OwnsFrame then
        function dropdown:OwnsFrame(frame)
            if not self:IsMenuOpen() then return false end
            local seen = {}
            local function Visit(region)
                if region == self then return true end
                if not region or seen[region] then return false end
                seen[region] = true
                if region.GetOwnerRegion then
                    if Visit(region:GetOwnerRegion()) then return true end
                    if region.GetNumPoints and region.GetPoint then
                        for index = 1, region:GetNumPoints() do
                            local _, relative = region:GetPoint(index)
                            if Visit(relative) then return true end
                        end
                    end
                end
                return region.GetParent and Visit(region:GetParent()) or false
            end
            return Visit(frame)
        end
    end
    if not dropdown or not dropdown.SetFrameStrata then return end
    if EXUI.ModernMenuStyleMixin then
        dropdown.menuMixin = EXUI.ModernMenuStyleMixin
    end
    local strata = parent and parent.GetFrameStrata and parent:GetFrameStrata() or "MEDIUM"
    dropdown:SetFrameStrata(strata)
    if dropdown.SetFrameLevel and parent and parent.GetFrameLevel then
        dropdown:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
    end

    -- 下拉控件会被对象池复用；仅在创建时同步，会让它在重新挂到
    -- TOOLTIP 弹窗后仍保留旧层级。打开菜单前再同步一次，确保
    -- Blizzard_Menu 以当前 owner 的 strata / level 创建菜单。
    dropdown._exuiDropdownLayerParent = parent
    if dropdown.OpenMenu and not dropdown._exuiDropdownLayerOpenHook then
        dropdown._exuiDropdownLayerOpenHook = true
        dropdown._exuiBaseOpenMenu = dropdown.OpenMenu
        dropdown.OpenMenu = function(self, ...)
            local owner = self._exuiDropdownLayerParent or self:GetParent()
            if owner and owner.GetFrameStrata then
                self:SetFrameStrata(owner:GetFrameStrata())
                if self.SetFrameLevel and owner.GetFrameLevel then
                    self:SetFrameLevel((owner:GetFrameLevel() or 0) + 5)
                end
            end
            return self._exuiBaseOpenMenu(self, ...)
        end
    end

    -- Blizzard_Menu 生成的真正菜单不是 DropdownButton 的子 Frame，而是 menu:ToProxy()
    -- 返回的独立窗口。它在对象池中借出后有时仍会保留较低的 frame level，造成
    -- 菜单只在组合弹窗的下缘露出。菜单创建完成后直接提升该 Proxy，不能只提升按钮。
    if dropdown.OnMenuOpened and not dropdown._exuiDropdownMenuOpenedHook then
        dropdown._exuiDropdownMenuOpenedHook = true
        dropdown._exuiBaseOnMenuOpened = dropdown.OnMenuOpened
        dropdown.OnMenuOpened = function(self, menu)
            self._exuiBaseOnMenuOpened(self, menu)

            local owner = self._exuiDropdownLayerParent or self:GetParent()
            local proxy = menu and menu.ToProxy and menu:ToProxy()
            if owner and proxy and owner.GetFrameStrata then
                local ownerStrata = owner:GetFrameStrata()
                -- DIALOG 弹窗内的列表必须位于 FULLSCREEN_DIALOG；这不是“调高一点”，
                -- 而是使用暴雪定义的相邻更高 strata，保证不会被弹窗遮住。
                local menuStrata = ownerStrata == "TOOLTIP" and "TOOLTIP" or "FULLSCREEN_DIALOG"
                proxy:SetFrameStrata(menuStrata)
                if proxy.SetFrameLevel and owner.GetFrameLevel then
                    local level = math.max(proxy:GetFrameLevel() or 0, (owner:GetFrameLevel() or 0) + 1000)
                    proxy:SetFrameLevel(level)
                end
                if proxy.SetToplevel then proxy:SetToplevel(true) end
            end
            if EXUI.StyleDropdownMenuProxy then EXUI:StyleDropdownMenuProxy(proxy) end
            if EXUI.RefreshControlAppearance then EXUI:RefreshControlAppearance(self) end
        end
    end
    if dropdown.OnMenuClosed and not dropdown._exuiDropdownMenuClosedHook then
        dropdown._exuiDropdownMenuClosedHook = true
        dropdown._exuiBaseOnMenuClosed = dropdown.OnMenuClosed
        dropdown.OnMenuClosed = function(self, menu, closeReason)
            self._exuiBaseOnMenuClosed(self, menu, closeReason)
            if EXUI.RefreshControlAppearance then EXUI:RefreshControlAppearance(self) end
        end
    end
end


-- [Style] 所有插件共用的扁平化输入/控件背景定义。
EXUI.TooltipBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- =========================================================
-- Shared modern control theme
--
-- This is the single visual implementation used by every EXUI constructor.
-- ExwindControlAppearance.lua only keeps the old opt-in API names alive; it
-- no longer owns a second skin or a second set of pools.
-- =========================================================
local MODERN_MEDIA = "Interface\\AddOns\\ExwindCore\\Textures\\GUI\\"
local GC = ExwindTools.GUIColors
if not GC then error("ExwindGUIColor.lua must load before ExwindGUI.lua") end
local GS = ExwindTools.GUIStates
local MODERN = {
    colors = {
        background = GC.page,
        panel = GC.panel,
        header = GC.header,
        headerHover = GC.headerHover,
        headerDivider = GC.headerDivider,
        subcard = GC.subcard,
        subcardBorder = GC.subcardBorder,
        subcardHoverBorder = GC.subcardHoverBorder,
        input = GC.input,
        inputBorder = GC.inputBorder,
        inputHoverBorder = GC.inputHoverBorder,
        inputFocusBorder = GC.inputFocusBorder,
        inputDisabled = GC.inputDisabled,
        inputDisabledBorder = GC.inputDisabledBorder,
        raised = GC.card,
        cardBorder = GC.cardBorder,
        hover = GC.rowHover,
        rowHover = GC.rowHover,
        cardHoverBorder = GC.cardHoverBorder,
        border = GC.panelBorder,
        text = GC.text,
        muted = GC.textDim,
        placeholder = GC.textPlaceholder,
        disabled = GC.textDisabled,
        blue = GC.primaryFill,
        blueHover = GC.primaryFillHover,
        accentActive = GC.accentActive,
        primaryHover = GC.primaryFillHover,
        primaryPressed = GC.primaryFillActive,
        lightBlue = GC.selectedText,
        blueSoft = GC.menuSelected,
        focus = GC.inputFocusBorder,
        focusRing = GC.focusRing,
        modifiedBorder = GC.modifiedBorder,
        accent = GC.accent,
        popup = GC.popup,
        popupBorder = GC.popupBorder,
        popupSearch = GC.popupSearch,
        popupSearchBorder = GC.popupSearchBorder,
        popupDivider = GC.popupDivider,
        menuSelected = GC.menuSelected,
        menuSelectedHover = GC.menuSelectedHover,
        menuHover = GC.menuHover,
        primaryFill = GC.primaryFill,
        primaryText = GC.primaryText,
        secondaryFill = GC.secondaryFill,
        secondaryBorder = GC.secondaryBorder,
        secondaryText = GC.secondaryText,
        secondaryHoverFill = GC.secondaryHoverFill,
        secondaryHoverBorder = GC.secondaryHoverBorder,
        secondaryPressedFill = GC.secondaryPressedFill,
        secondaryPressedText = GC.secondaryPressedText,
        dangerFill = GC.transparent,
        dangerBorder = GC.dangerBorder,
        dangerText = GC.dangerText,
        dangerHoverFill = GC.dangerHoverFill,
        dangerHover = GC.dangerText,
        dangerPressedFill = GC.dangerPressedFill,
        disabledFill = GC.disabledFill,
        disabledBorder = GC.disabledBorder,
        disabledText = GC.textDisabled,
        checkboxBorder = GC.checkboxBorder,
        checkboxHoverBorder = GC.checkboxHoverBorder,
        checkboxChecked = GC.checkboxChecked,
        checkboxCheckedHover = GC.checkboxCheckedHover,
        checkboxCheckedActive = GC.checkboxCheckedActive,
        switchOn = GC.switchOn,
        switchOnHover = GC.switchOnHover,
        switchOff = GC.switchOff,
        switchOffHover = GC.switchOffHover,
        switchKnobOn = GC.switchKnobOn,
        switchKnobOff = GC.switchKnobOff,
        tagBorder = GC.tagBorder,
        tagText = GC.tagText,
        tagHoverBorder = GC.tagHoverBorder,
        tagHoverText = GC.tagHoverText,
        tagSelected = GC.tagSelected,
        tagSelectedBorder = GC.tagSelectedBorder,
        tagSelectedText = GC.tagSelectedText,
        tagSelectedHover = GC.tagSelectedHover,
        segmentSelected = GC.segmentSelected,
        segmentText = GC.segmentText,
        toolHover = GC.toolHover,
        toolActive = GC.toolActive,
        toolOn = GC.toolOn,
        transparent = GC.transparent,
        white = GC.white,
        neutral = { 0.584, 0.616, 0.667, 1 },
        include = { 0.412, 0.620, 0.969, 1 },
        exclude = { 0.933, 0.443, 0.502, 1 },
    },
    metrics = {
        pageTitle = GM.font.pageTitle,
        title = GM.font.title,
        cardTitle = GM.font.cardTitle,
        section = GM.font.section,
        text = GM.font.text,
        control = GM.font.control,
        fieldValue = GM.font.fieldValue,
        button = GM.font.button,
        hint = GM.font.hint,
        height = GM.size.controlHeight,
    },
}
EXUI.ModernTheme = MODERN
EXUI.ControlAppearance = MODERN
local MC = MODERN.colors

local function CompositeThemeColor(base, overlay, alphaOverride)
    local alpha = alphaOverride or overlay[4] or 1
    return {
        overlay[1] * alpha + base[1] * (1 - alpha),
        overlay[2] * alpha + base[2] * (1 - alpha),
        overlay[3] * alpha + base[3] * (1 - alpha),
        1,
    }
end

MODERN.checkboxPressedFill = CompositeThemeColor(MC.input, MC.toolActive)
MODERN.checkboxHoverFill = CompositeThemeColor(MC.input, MC.rowHover)
MODERN.switchOffHoverFill = CompositeThemeColor(MC.switchOff, MC.switchOffHover)
MODERN.switchOnEdge = MC.switchOn
MODERN.switchOnHoverEdge = MC.switchOnHover
MODERN.switchOnPressedEdge = MC.checkboxCheckedActive
MODERN.switchOffEdge = MC.switchOff
MODERN.switchOffHoverEdge = MODERN.switchOffHoverFill
MODERN.switchOffPressedEdge = MC.checkboxHoverBorder
MODERN.settingsCardHoverFill = CompositeThemeColor(MC.subcard, MC.rowHover)
MODERN.settingsCardPressedFill = CompositeThemeColor(MC.subcard, MC.toolActive)
MODERN.settingsCardSelectedFill = CompositeThemeColor(MC.subcard, MC.tagSelected)
MODERN.settingsCardSelectedHoverFill = CompositeThemeColor(MC.subcard, MC.tagSelectedHover)

-- Blizzard_Menu compositor proxies deliberately disallow FontString:SetFont.
-- Build the two menu typography roles while this file is loading, then menu
-- initializers only bind the cached FontObject through the allowed API.
local function CreateModernMenuFontObject(globalName, size)
    local font = _G[globalName] or CreateFont(globalName)
    font:SetFont(defaultFontPath, size, "")
    font:SetTextColor(unpack(GC.white))
    if font.SetShadowOffset then font:SetShadowOffset(0, 0) end
    return font
end

MODERN.menuFonts = {
    control = CreateModernMenuFontObject("ExwindCoreModernMenuControlFont", MODERN.metrics.fieldValue),
    title = CreateModernMenuFontObject("ExwindCoreModernMenuTitleFont", MODERN.metrics.title),
}

-- Compatibility palettes are retained for callers which select a typography
-- role.  Their controls still use the same modern geometry and state painter.
MODERN.DungeonAura = {
    row = 42, buttonWidth = 62, buttonHeight = 24, gap = 8,
    text = MC.text, muted = MC.muted, title = MC.lightBlue, fact = MC.lightBlue,
    value = MC.text, focus = MC.focus, success = MC.lightBlue,
    warning = { .97, .72, .38, 1 }, danger = { .97, .45, .47, 1 },
    input = MC.input, inputBorder = MC.inputBorder, inputFocus = MC.inputFocusBorder,
    header = MC.header, panel = MC.panel, panelDeep = MC.input,
    line = MC.headerDivider, lineStrong = MC.border, button = MC.raised,
    hover = MC.hover, gold = MC.lightBlue,
}
MODERN.LoadCard = setmetatable({
    id = "load-card", row = 52, buttonHeight = 26, buttonWidth = 88,
    text = MC.text, value = MC.text, title = MC.text, muted = MC.muted,
    fact = MC.lightBlue, focus = MC.focus, background = MC.background,
    header = MC.header, panelDeep = MC.input, panel = MC.panel,
    input = MC.input, inputFocus = MC.inputFocusBorder, inputBorder = MC.inputBorder,
    button = MC.raised, hover = MC.hover, line = MC.border,
    lineStrong = MC.border, gold = MC.lightBlue,
    choiceFill = MC.lightBlue, choiceText = MC.background,
}, { __index = MODERN.DungeonAura })

function EXUI:SetControlAppearance(root, appearance)
    assert(appearance == nil or appearance == "flat" or appearance == "default" or appearance == "modern",
        "Unknown control appearance")
    root._exControlAppearance = appearance
end

function EXUI:GetControlAppearance(root)
    while root do
        if root._exControlAppearance then return root._exControlAppearance end
        root = root.GetParent and root:GetParent()
    end
    return "modern"
end

function EXUI:SetControlFontSize(root, size)
    assert(size == nil or (type(size) == "number" and size >= 10 and size <= 24), "Invalid control font size")
    root._exControlFontSize = size
end

function EXUI:GetControlFontSize(root)
    while root do
        if root._exControlFontSize then return root._exControlFontSize end
        root = root.GetParent and root:GetParent()
    end
end

function EXUI:SetControlFontStyle(root, style)
    assert(style == nil or style == "settings" or style == "dungeon-aura" or style == "load-card",
        "Unknown control font style")
    root._exControlFontStyle = style
end

function EXUI:GetControlFontStyle(root)
    while root do
        if root._exControlFontStyle then return root._exControlFontStyle end
        root = root.GetParent and root:GetParent()
    end
end

function MODERN.GetReference(frame)
    local style = EXUI:GetControlFontStyle(frame)
    return style == "load-card" and MODERN.LoadCard
        or (style == "dungeon-aura" and MODERN.DungeonAura or nil)
end

function MODERN.ReferenceText(region, template, size, color, flags)
    if not region then return end
    local font = _G[template] or template
    region:SetFontObject(font)
    if font and font.GetFont then
        local path, referenceSize, referenceFlags = font:GetFont()
        if path and region.SetFont then
            region:SetFont(path, size or referenceSize, flags == nil and (referenceFlags or "") or flags)
        end
    end
    region:SetTextColor(unpack(color or MC.text))
    if region.SetShadowOffset then region:SetShadowOffset(0, 0) end
end

function MODERN.Font(region, size, color, flags, template)
    if not region or not region.SetFont then return end
    local reference = MODERN.GetReference(region)
    if reference then
        MODERN.ReferenceText(region, template or "GameFontHighlight", size, color or reference.text, flags)
        return
    end
    local path = region:GetFont()
    if EXUI:GetControlFontStyle(region) == "settings" then
        path = ExwindTools.MAIN_FONT or path
    end
    path = path or defaultFontPath
    region:SetFont(path, size or MODERN.metrics.text, flags or "")
    region:SetTextColor(unpack(color or MC.text))
    if region.SetShadowOffset then region:SetShadowOffset(0, 0) end
end

MODERN.typography = {
    pageTitle = { size = MODERN.metrics.pageTitle, color = MC.text, template = "GameFontHighlight" },
    title = { size = MODERN.metrics.title, color = MC.text, template = "GameFontHighlight" },
    cardTitle = { size = MODERN.metrics.cardTitle, color = MC.text, template = "GameFontHighlight" },
    body = { size = MODERN.metrics.text, color = MC.text, template = "GameFontHighlight" },
    control = { size = MODERN.metrics.control, color = MC.text, template = "GameFontHighlight" },
    fieldValue = { size = MODERN.metrics.fieldValue, color = MC.text, template = "GameFontHighlight" },
    button = { size = MODERN.metrics.button, color = MC.text, template = "GameFontHighlight" },
    hint = { size = MODERN.metrics.hint, color = MC.placeholder, template = "GameFontHighlightSmall" },
    sliderInput = { size = GM.font.sliderInput, color = MC.text, template = "GameFontHighlightSmall" },
    urlValue = { size = GM.font.small, color = MC.text, template = "GameFontHighlightSmall" }, -- 只读网址框
    urlCompact = { size = GM.font.hint, color = MC.text, template = "GameFontHighlightSmall" }, -- 窄卡里的只读网址框
}

-- 滑条数值框的尺寸常量。它是 ApplyModernInput 的一种角色（_exSliderNumberInput），
-- 字号与内边距由该角色决定；CreateSlider / SettingsList 读取同一组常量。
local SLIDER_NUMBER_INPUT_WIDTH = GM.size.sliderInputWidth
local SLIDER_NUMBER_INPUT_HEIGHT = GM.size.sliderInputHeight
local SLIDER_NUMBER_INPUT_INSET = GM.space.sliderInputInset

function MODERN.ApplyTextRole(region, role, color, template)
    local spec = MODERN.typography[role] or MODERN.typography.body
    MODERN.Font(region, spec.size, color or spec.color, "", template or spec.template)
end

local function StyleModernTitle(region, color)
    MODERN.ApplyTextRole(region, "title", color)
end

-- The former flat appearance allocated parallel pools.  All appearances now
-- resolve to the same pool so a composite can never retain a visually foreign
-- child, while the public compatibility methods remain callable.
function EXUI:ResolveControlPool(poolType)
    return poolType
end

function EXUI:AcquireControl(poolType, parent)
    return _G.ExwindFactory:Acquire(poolType, parent)
end

-- =========================================================
-- 画器脚本的安装记录（按「帧 + 槽位」记）
--
-- SetScript 清掉的是整个 extrinsic 槽位，HookScript 接出来的链也在同一个槽位
-- 里，会被一起清掉；Postcall 绑定同样保不住（用户 2026-10-05 游戏内实测）。
-- 对象池归还时会对 OnEnter/OnLeave/OnMouseDown/OnMouseUp 等槽位 SetScript(nil)，
-- 所以安装记录不能是「一个帧一个布尔、跨租约永久保留」——那样下次借用既不重装、
-- 链上也没有画器。记录改成每个槽位一个键：清槽位的人（对象池 StandardReset /
-- ResetGridWidget、控件构造器）用 EXUI:ClearControlScript 同时丢掉该键，下一次
-- ApplyModernXxx 正好重装一份，不会缺也不会叠加。
-- 不走槽位的 hooksecurefunc（Enable/Disable 等）仍用独立的跨租约标记。
-- =========================================================
local function HookControlScript(frame, script, handler)
    if not frame or not frame.HookScript then return end
    if frame.HasScript and not frame:HasScript(script) then return end
    local hooks = frame._exScriptHooks
    if not hooks then
        hooks = {}
        frame._exScriptHooks = hooks
    end
    if hooks[script] then return end
    hooks[script] = true
    frame:HookScript(script, handler)
end

-- 清掉一个 extrinsic 槽位，同时丢掉该槽位的画器安装记录。
-- 任何要替换这些槽位的代码都应该走它，而不是裸 SetScript(slot, nil)。
function EXUI:ClearControlScript(frame, script)
    if not frame or not frame.SetScript then return end
    if frame.HasScript and not frame:HasScript(script) then return end
    frame:SetScript(script, nil)
    local hooks = frame._exScriptHooks
    if hooks then hooks[script] = nil end
end

local function HideControlSkin(frame)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    -- 只把 alpha 压到 0 不够稳：WowStyle1DropdownTemplate 的 Background 用
    -- common-dropdown-textholder，锚点是 TOPLEFT(-8, 7) / BOTTOMRIGHT(8, -9)，
    -- 比触发器本体上方外溢 7px；一旦它被重新显示，露出来的正好是触发器
    -- 顶部上方的一条横线，要等下一次 Paint（例如悬停）才会被重新压掉。
    -- 这里一并 Hide()，模板后续的 SetAtlas 不会把隐藏的 region 重新显示。
    if frame.Background then frame.Background:SetAlpha(0); frame.Background:Hide() end
    if frame.Arrow then frame.Arrow:SetAlpha(0); frame.Arrow:Hide() end
    -- SharedButtonLargeTemplate is a ThreeSliceButtonTemplate.  Its native
    -- Left/Center/Right art is not returned by GetNormalTexture(), and
    -- ThreeSliceButtonMixin:UpdateButton refreshes the atlas on every state
    -- transition.  Keep the regions owned by that template transparent while
    -- leaving our separately allocated modern surface untouched.
    for _, key in ipairs({ "Left", "Center", "Right" }) do
        local texture = frame[key]
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
    end
    for _, method in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local texture = frame[method] and frame[method](frame)
        if texture then texture:SetAlpha(0) end
    end
end

local function StripCheckButtonStateTextures(button)
    if not button or button._exModernNativeCheckStripped then return end

    -- MinimalCheckboxTemplate binds its native state textures to the CheckButton.  A
    -- row-wide hit target makes those textures stretch across the label, so
    -- merely lowering their alpha is not sufficient: state changes can show
    -- them again. Clear the asset on every state texture that actually exists.
    -- Button:Set*Texture requires an asset on the current client, so an absent
    -- state is skipped instead of trying to detach it through a nil setter.
    local states = {
        { "GetNormalTexture", "NormalTexture" },
        { "GetPushedTexture", "PushedTexture" },
        { "GetHighlightTexture", "HighlightTexture" },
        { "GetDisabledTexture", "DisabledTexture" },
        { "GetCheckedTexture", "CheckedTexture" },
        { "GetDisabledCheckedTexture", "DisabledCheckedTexture" },
    }
    for _, state in ipairs(states) do
        local texture = button[state[1]] and button[state[1]](button) or button[state[2]]
        if texture then
            texture:SetTexture(nil)
            texture:SetAlpha(0)
            texture:Hide()
        end
    end
    button._exModernNativeCheckStripped = true
end

local modernSurfaceFrames = setmetatable({}, { __mode = "k" })
local modernSurfaceScaleWatcher

local function TrackModernSurfaceFrame(frame)
    modernSurfaceFrames[frame] = true
    if modernSurfaceScaleWatcher then return end
    modernSurfaceScaleWatcher = CreateFrame("Frame")
    modernSurfaceScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    modernSurfaceScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    modernSurfaceScaleWatcher:SetScript("OnEvent", function()
        -- UI scale may change without changing a control's logical width/height.
        -- Re-run every cached surface layout so its logical inset continues to
        -- resolve to one physical pixel at the new effective scale.
        for owner in pairs(modernSurfaceFrames) do
            -- 像素对齐的几何（Switch）需要先按新像素尺寸重算，再重排 surface。
            if owner._exSurfaceRescale then owner._exSurfaceRescale() end
            for _, cachedSkin in pairs(owner._exModernSurfaces or {}) do
                if cachedSkin.Layout then cachedSkin.Layout() end
            end
        end
    end)
end

MODERN.surfaceAtlas = {
    file = MODERN_MEDIA .. "SurfaceBorderAtlas.tga",
    width = 512,
    height = 256,
    cell = 34,
    columns = 15,
    maxRadius = 32,
}

function MODERN.surfaceAtlas:GetPixel(frame)
    local effectiveScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    effectiveScale = type(effectiveScale) == "number" and effectiveScale > 0 and effectiveScale or 1
    local pixelUtil = _G.PixelUtil
    local pixel = pixelUtil and pixelUtil.GetNearestPixelSize
        and pixelUtil.GetNearestPixelSize(0, effectiveScale, 1)
        or (1 / effectiveScale)
    return type(pixel) == "number" and pixel > 0 and pixel or (1 / effectiveScale)
end

function MODERN.surfaceAtlas:GetMetrics(frame, radius, borderPixels)
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return nil end
    local pixel = self:GetPixel(frame)
    local widthPixels = math.max(1, math.floor(width / pixel + .5))
    local heightPixels = math.max(1, math.floor(height / pixel + .5))
    local radiusPixels = math.max(0, math.min(self.maxRadius,
        math.floor((tonumber(radius) or 0) / pixel + .5),
        math.floor(widthPixels / 2), math.floor(heightPixels / 2)))
    local strokePixels = math.max(1, math.min(2, math.floor((tonumber(borderPixels) or 1) + .5)))
    -- 同组表面（Switch 轨道 + 圆钮）共用组内第一个 Frame 的位置取整，
    -- 这样两者的像素偏移永远相同，不会各自取整而错开 1 个物理像素。
    local group = frame._exSurfaceGroup
    local ref = group and group[1] or frame
    local left, top = ref.GetLeft and ref:GetLeft(), ref.GetTop and ref:GetTop()
    local offsetX, offsetY = 0, 0
    if type(left) == "number" then offsetX = math.floor(left / pixel + .5) * pixel - left end
    if type(top) == "number" then offsetY = math.floor(top / pixel + .5) * pixel - top end
    return {
        pixel = pixel,
        widthPixels = widthPixels,
        heightPixels = heightPixels,
        radiusPixels = radiusPixels,
        strokePixels = strokePixels,
        offsetX = offsetX,
        offsetY = offsetY,
    }
end

function MODERN.surfaceAtlas:ConfigureTexture(texture)
    texture:SetTexture(self.file, "CLAMP", "CLAMP", "NEAREST")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

function MODERN.surfaceAtlas:SetSolidTexCoord(texture)
    texture:SetTexCoord((self.width - 1) / self.width, 1, (self.height - 1) / self.height, 1)
end

function MODERN.surfaceAtlas:SetCornerTexCoord(texture, radiusPixels, band, row, col)
    local index = band * self.maxRadius + radiusPixels - 1
    local x = (index % self.columns) * self.cell + 1
    local y = math.floor(index / self.columns) * self.cell + 1
    local left, right = x / self.width, (x + radiusPixels) / self.width
    local top, bottom = y / self.height, (y + radiusPixels) / self.height
    if col == 3 then left, right = right, left end
    if row == 3 then top, bottom = bottom, top end
    texture:SetTexCoord(left, right, top, bottom)
end

local function GetModernSurface(frame, radius)
    frame._exModernSurfaces = frame._exModernSurfaces or {}
    local skin = frame._exModernSurfaces[radius]
    if skin then
        TrackModernSurfaceFrame(frame)
        return skin
    end

    skin = { pieces = {}, radius = radius, active = false }
    frame._exModernSurfaces[radius] = skin
    TrackModernSurfaceFrame(frame)
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
            MODERN.surfaceAtlas:ConfigureTexture(texture)
            skin.pieces[#skin.pieces + 1] = {
                texture = texture, row = row, col = col, layer = 2,
                kind = (row ~= 2 and col ~= 2) and "fillCorner" or "fillSolid",
            }
        end
    end
    for _, corner in ipairs({ { 1, 1 }, { 1, 3 }, { 3, 1 }, { 3, 3 } }) do
        local row, col = corner[1], corner[2]
        local texture = frame:CreateTexture(nil, "BORDER", nil, 0)
        MODERN.surfaceAtlas:ConfigureTexture(texture)
        skin.pieces[#skin.pieces + 1] = {
            texture = texture, row = row, col = col, layer = 1, kind = "borderCorner",
        }
    end
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local texture = frame:CreateTexture(nil, "BORDER", nil, 1)
        MODERN.surfaceAtlas:ConfigureTexture(texture)
        MODERN.surfaceAtlas:SetSolidTexCoord(texture)
        skin.pieces[#skin.pieces + 1] = {
            texture = texture, layer = 1, kind = "borderEdge", side = side,
        }
    end
    skin.Layout = function()
        -- OnSizeChanged / OnShow hooks live for the frame lifetime.  A surface
        -- that was explicitly cleared must stay cleared across later layout
        -- passes instead of letting this cached skin resurrect its pieces.
        if skin.active ~= true then
            for _, piece in ipairs(skin.pieces) do piece.texture:Hide() end
            return
        end
        -- 任一组员重排时整组一起重排：同一时刻、同一取整基准。
        local group = frame._exSurfaceGroup
        if group and not group.busy then
            group.busy = true
            for _, member in ipairs(group) do
                if member ~= frame then
                    for _, other in pairs(member._exModernSurfaces or {}) do
                        if other.active == true then other.Layout() end
                    end
                end
            end
            group.busy = false
        end
        local metrics = MODERN.surfaceAtlas:GetMetrics(frame, radius, skin.borderPixels)
        if not metrics then return end
        local pixel = metrics.pixel
        local width = metrics.widthPixels * pixel
        local height = metrics.heightPixels * pixel
        local corner = metrics.radiusPixels * pixel
        local thickness = metrics.strokePixels * pixel
        local xs = {
            metrics.offsetX,
            metrics.offsetX + corner,
            metrics.offsetX + width - corner,
            metrics.offsetX + width,
        }
        local ys = { 0, corner, height - corner, height }
        local degenerateBorder = metrics.widthPixels <= metrics.strokePixels * 2
            or metrics.heightPixels <= metrics.strokePixels * 2
        for _, piece in ipairs(skin.pieces) do
            piece.texture:ClearAllPoints()
            if metrics.radiusPixels == 0 and piece.layer == 2 then
                if piece.row == 2 and piece.col == 2 then
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                    piece.texture:SetSize(width, height)
                    piece.texture:Show()
                else
                    piece.texture:Hide()
                end
            elseif degenerateBorder and piece.layer == 1 then
                if piece.kind == "borderEdge" and piece.side == "TOP" then
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                    piece.texture:SetSize(width, height)
                    piece.texture:Show()
                else
                    piece.texture:Hide()
                end
            elseif piece.kind == "borderEdge" then
                MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                piece.texture:ClearAllPoints()
                if piece.side == "TOP" then
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[2], metrics.offsetY)
                    piece.texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    piece.texture:SetShown(width > corner * 2)
                elseif piece.side == "BOTTOM" then
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[2], metrics.offsetY - height + thickness)
                    piece.texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    piece.texture:SetShown(width > corner * 2)
                elseif piece.side == "LEFT" then
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX, metrics.offsetY - corner)
                    piece.texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    piece.texture:SetShown(height > corner * 2)
                else
                    piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX + width - thickness, metrics.offsetY - corner)
                    piece.texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    piece.texture:SetShown(height > corner * 2)
                end
            else
                local pieceWidth = xs[piece.col + 1] - xs[piece.col]
                local pieceHeight = ys[piece.row + 1] - ys[piece.row]
                if piece.kind == "fillCorner" then
                    MODERN.surfaceAtlas:SetCornerTexCoord(piece.texture,
                        metrics.radiusPixels, 0, piece.row, piece.col)
                elseif piece.kind == "borderCorner" then
                    MODERN.surfaceAtlas:SetCornerTexCoord(piece.texture,
                        metrics.radiusPixels, metrics.strokePixels, piece.row, piece.col)
                else
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                end
                piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[piece.col], metrics.offsetY - ys[piece.row])
                piece.texture:SetSize(math.max(.001, pieceWidth), math.max(.001, pieceHeight))
                piece.texture:SetShown(pieceWidth > 0 and pieceHeight > 0)
            end
            -- Joined controls retain only their group's outside rounded ends.
            local joined = frame._exJoinedEdge
            if joined then
                local squareLeft = joined ~= "first"
                local squareRight = joined ~= "last"
                local squareCorner = (piece.col == 1 and squareLeft) or (piece.col == 3 and squareRight)
                if squareCorner and (piece.kind == "fillCorner" or piece.kind == "borderCorner") then
                    MODERN.surfaceAtlas:SetSolidTexCoord(piece.texture)
                    if piece.kind == "borderCorner" then
                        piece.texture:ClearAllPoints()
                        piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[piece.col],
                            metrics.offsetY - (piece.row == 1 and 0 or height - thickness))
                        piece.texture:SetSize(corner, thickness)
                    end
                elseif piece.kind == "borderEdge" then
                    if piece.side == "LEFT" and squareLeft then
                        -- The preceding control supplies the one-pixel seam.
                        piece.texture:Hide()
                    elseif piece.side == "RIGHT" and squareRight then
                        piece.texture:ClearAllPoints()
                        piece.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.offsetX + width - thickness, metrics.offsetY)
                        piece.texture:SetSize(thickness, height)
                        piece.texture:Show()
                    end
                end
            end
        end
    end
    frame:HookScript("OnSizeChanged", skin.Layout)
    frame:HookScript("OnShow", skin.Layout)
    return skin
end

-- 真正的 surface 绘制入口：半径按调用方给定的精确值使用（不经白名单）。
-- SetControlSurface 先把视觉半径归一到白名单再调用它；Switch 这类
-- 由几何推算半径的整圆胶囊直接调用它。
function MODERN.PaintControlSurface(frame, radius, fill, border)
    HideControlSkin(frame)
    for _, other in pairs(frame._exModernSurfaces or {}) do
        other.active = false
        for _, piece in ipairs(other.pieces) do piece.texture:Hide() end
    end
    local skin = GetModernSurface(frame, radius)
    -- 圆角图标默认压一圈黑边把贴图边缘收干净；但调用方显式给了边框色时（例如专精格
    -- 用职业色描边）必须尊重它，否则那条颜色线索会被黑边吃掉。
    if frame._exRoundedIconBorder and border == nil then
        border = { 0, 0, 0, 1 }
        skin.borderPixels = 1
    end
    skin.active = true
    skin.fill = fill or MC.input
    for _, piece in ipairs(skin.pieces) do
        local color = piece.layer == 1 and (border or MC.border) or (fill or MC.input)
        -- Solid pieces stay white so button transitions and settings-list
        -- capture/restore can continue treating vertex color as surface RGBA.
        if piece.texture._exButtonGradient then
            piece.texture:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
            piece.texture._exButtonGradient = nil
        end
        piece.texture:SetVertexColor(unpack(color))
        piece.texture:Show()
    end
    skin.Layout()
end

function EXUI:SetControlSurface(frame, radius, fill, border)
    if not frame then return end
    radius = (radius == 3 or radius == 4 or radius == 5 or radius == 6
        or radius == 8 or radius == 10) and radius or 4
    MODERN.PaintControlSurface(frame, radius, fill, border)
end

function EXUI:ClearControlSurface(frame)
    if not frame then return end
    HideControlSkin(frame)
    for _, skin in pairs(frame._exModernSurfaces or {}) do
        skin.active = false
        for _, piece in ipairs(skin.pieces) do piece.texture:Hide() end
    end
end

function EXUI:ApplyModernPanel(frame, elevated)
    self:SetControlSurface(frame, GM.radius.card, elevated and MC.raised or MC.panel, MC.border)
    return frame
end

-- Shared text-button geometry; B5 color changes are immediate.
local BUTTON_STYLE = {
    paddingX = GM.space.buttonPaddingX,
    paddingY = GM.space.buttonPaddingY,
    minWidth = GM.size.buttonMinWidth,
    radius = GM.radius.control,
}
MODERN.buttonStyle = BUTTON_STYLE
MODERN.buttonFont = CreateModernMenuFontObject("ExwindCoreModernButtonFont", MODERN.metrics.button)

local function SetButtonRegionColor(region, color, animate, isText)
    -- B5 buttons and selection cards change state immediately, with no color tween.
    if region._exButtonColor and region._exButtonColor.group then
        region._exButtonColor.group:Stop()
        region._exButtonColor = nil
    end
    if isText then region:SetTextColor(unpack(color)) else region:SetVertexColor(unpack(color)) end
end

local function PaintTextButtonSurface(frame, top, bottom, edge, text, enabled, highlight, pressed)
    -- Ordinary and dialog actions share one flat state surface.
    local focused = enabled and frame._exButtonKeyboardFocused == true
    EXUI:SetControlSurface(frame, BUTTON_STYLE.radius, bottom or top, focused and MC.focusRing or edge)
    if frame._exButtonTopHighlight then frame._exButtonTopHighlight:Hide() end
    if frame._exButtonPressedInset then frame._exButtonPressedInset:Hide() end
    if frame._exButtonFocusSurface then frame._exButtonFocusSurface:Hide() end
    local label = frame:GetFontString()
    if label then label:SetTextColor(unpack(text)) end
    frame._exButtonPainted = true
end

local function EnsureSidebarNavigationParts(frame)
    -- Hot-reloaded/pooled buttons may still carry the retired rectangular fill.
    -- Keep it hidden; the shared R4 control surface below owns the background.
    if frame._exSidebarBackground then
        if frame._exSidebarBackground._exButtonColor then
            frame._exSidebarBackground._exButtonColor.group:Stop()
        end
        frame._exSidebarBackground:Hide()
    end
    -- 选中项只描边（用户 2026-10-05，取代 2026-10-04 的淡底 + 左侧指示条），
    -- 描边由下面共享的 R4 surface 画，这里没有额外 region 要准备。
end

local function EnsureTextButtonFontString(frame)
    if frame._exButtonPresentation == "sidebar" then
        local label = frame._exSidebarLabel
        if not label then
            label = EXUI:CreateVisualFontString(frame, EXFONTFRAME)
            frame._exSidebarLabel = label
        end
        label:SetFontObject(MODERN.menuFonts.control)
        local nativeLabel = frame.GetFontString and frame:GetFontString()
        if nativeLabel and nativeLabel ~= label then
            nativeLabel:SetText("")
            nativeLabel:Hide()
        end
        label:Show()
        return label
    end
    if frame._exSidebarLabel then
        frame._exSidebarLabel:SetText("")
        frame._exSidebarLabel:Hide()
    end
    local label = frame.GetFontString and frame:GetFontString()
    if label then
        label:Show()
        return label
    end
    label = EXUI:CreateVisualFontString(frame, EXFONTFRAME)
    label:SetFontObject(MODERN.buttonFont)
    frame:SetFontString(label)
    frame._exOwnedButtonFontString = label
    return label
end

local function LayoutSidebarNavigationButton(frame)
    local level = tonumber(frame._exSidebarLevel) or 0
    local label = EnsureTextButtonFontString(frame)
    -- SharedButtonLargeTemplate reapplies its state FontObject after hover,
    -- selection and pooled reuse. Keep every native state on the navigation
    -- font so it cannot restore the ordinary button size mid-session.
    frame:SetNormalFontObject(MODERN.menuFonts.control)
    frame:SetHighlightFontObject(MODERN.menuFonts.control)
    frame:SetDisabledFontObject(MODERN.menuFonts.control)
    local nativeLabel = frame.GetFontString and frame:GetFontString()
    if nativeLabel and nativeLabel ~= label then
        nativeLabel:SetText("")
        nativeLabel:Hide()
    end
    label:ClearAllPoints()
    local leftInset = level > 0 and 18 or 10
    if frame._exSidebarIcon and frame._exSidebarIcon:IsShown() then
        -- 有图标的导航项不分层级，图标列与文字列固定；垂直方向取整，避免半像素错位。
        leftInset = 18
        local iconTop = 0
        local frameHeight = frame:GetHeight()
        frame._exSidebarIcon:ClearAllPoints()
        if frameHeight and frameHeight > 20 then
            iconTop = -math.floor((frameHeight - 20) / 2)
            frame._exSidebarIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", leftInset, iconTop)
        else
            frame._exSidebarIcon:SetPoint("LEFT", frame, "LEFT", leftInset, 0)
        end
        leftInset = leftInset + 28
    end
    label:SetPoint("LEFT", frame, "LEFT", leftInset, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetFontObject(MODERN.menuFonts.control)
    label:SetScale(1)
    frame.label = label
end

local function PaintSidebarNavigationButton(frame, enabled)
    EnsureSidebarNavigationParts(frame)
    if frame._exButtonTopHighlight then frame._exButtonTopHighlight:Hide() end
    if frame._exButtonPressedInset then frame._exButtonPressedInset:Hide() end
    LayoutSidebarNavigationButton(frame)

    local selected = frame._exSidebarSelected == true
    local hovered = frame._exModernHover == true
    -- 选中态只描边（用户 2026-10-05 推翻 2026-10-04 的“淡底 + 左侧指示条”）：底色不动，
    -- 只加一圈主色描边，文字用常规正文色；颜色真源是 GUIStates.sidebar。
    local state = GS.sidebar[not enabled and "disabled" or selected and "selected"
        or frame._exModernPressed and "pressed" or hovered and "hover" or "normal"]
    local fill, text = state.fill, state.text
    local animate = frame:IsShown() and frame._exButtonPainted == true
    -- Use the same R4 nine-slice owned by the shared button implementation.
    -- 悬停基准＝EXBoss 首领页首领行：只把底色抬到 GC.menuHover 的中性灰叠层，不加描边。
    -- 选中项被悬停时仍只描边，底色沿用悬停底、描边换成 primaryFillHover 表示指针在其上
    -- （与基准 BossPage 的 selected+hover 同一写法），选中态本身仍是“只描边”。
    local border = state.border
    if enabled and hovered and selected then
        fill = GS.sidebar.hover.fill
        border = GC.primaryFillHover
    end
    EXUI:SetControlSurface(frame, BUTTON_STYLE.radius, fill, border)
    local surface = frame._exModernSurfaces and frame._exModernSurfaces[BUTTON_STYLE.radius]
    for _, piece in ipairs(surface and surface.pieces or {}) do
        SetButtonRegionColor(piece.texture, piece.layer == 1 and border or fill, animate)
    end
    local label = frame.label or EnsureTextButtonFontString(frame)
    if label then SetButtonRegionColor(label, text, animate, true) end
    if frame._exSidebarIcon and frame._exSidebarIcon:IsShown() then
        SetButtonRegionColor(frame._exSidebarIcon, text, animate)
    end
    if frame._exButtonFocusSurface then frame._exButtonFocusSurface:Hide() end
    frame._exButtonPainted = true
end

local function PaintModernButton(frame)
    local enabled = not frame.IsEnabled or frame:IsEnabled()
    if frame._exJoinedEdge then
        local edge = not enabled and MC.inputDisabledBorder
            or (frame._exModernPressed and MC.inputFocusBorder or frame._exModernHover and MC.inputHoverBorder or MC.inputBorder)
        local fill = not enabled and MC.inputDisabled
            or (frame._exModernPressed and MC.secondaryPressedFill or MC.input)
        EXUI:SetControlSurface(frame, GM.radius.control, fill, edge)
        if frame._exButtonTopHighlight then frame._exButtonTopHighlight:Hide() end
        if frame._exButtonPressedInset then frame._exButtonPressedInset:Hide() end
        if frame._exButtonFocusSurface then frame._exButtonFocusSurface:Hide() end
        return
    end
    if frame._exButtonPresentation == "sidebar" and frame._gridType == "GridButton" then
        PaintSidebarNavigationButton(frame, enabled)
        return
    end
    if frame._exSidebarBackground then
        if frame._exSidebarBackground._exButtonColor then
            frame._exSidebarBackground._exButtonColor.group:Stop()
        end
        frame._exSidebarBackground:Hide()
    end
    local variant = frame._exButtonVariant or "secondary"
    local isColorButton = frame._gridType == "GridColorButton"
    local top, bottom, edge, text, highlight

    if isColorButton then
        top, edge, text = MC.input, MC.inputBorder, MC.text
        if frame._exModernPressed and enabled then
            top, edge = MC.input, MC.blue
        elseif frame._exModernHover and enabled then
            top, edge, text = MC.input, MC.inputHoverBorder, MC.text
        end
    else
        local states = GS[variant] or GS.button
        local state = states[not enabled and "disabled" or frame._exModernPressed and "pressed"
            or frame._exModernHover and "hover" or "normal"]
        top, bottom, edge, text = state.fill, state.fill, state.border, state.text
    end

    if not enabled then
        top, bottom, edge, text, highlight = MC.disabledFill, MC.disabledFill,
            MC.disabledBorder, MC.disabledText, nil
    end
    if not isColorButton then
        PaintTextButtonSurface(frame, top, bottom, edge, text, enabled, highlight,
            frame._exModernPressed == true)
    else
        if frame._exButtonTopHighlight then frame._exButtonTopHighlight:Hide() end
        if frame._exButtonPressedInset then frame._exButtonPressedInset:Hide() end
        EXUI:SetControlSurface(frame, GM.radius.control, top, edge)
        local label = frame.GetFontString and frame:GetFontString() or frame.label
        if label then label:SetTextColor(unpack(text)) end
    end
    -- 颜色按钮除了整块底色，也让预览色块的细边框一起响应。
    -- 这样即使背景色差在某些显示器上不明显，鼠标提示仍然清楚。
    if isColorButton and frame.swatchBorder then
        if not enabled then
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.disabledText))
        elseif frame._exModernPressed then
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.blue))
        elseif frame._exModernHover then
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.inputHoverBorder))
        else
            frame.swatchBorder:SetBackdropBorderColor(unpack(MC.inputBorder))
        end
    end
end

-- A keyboard-navigation owner supplies focus; this does not install key handlers.
function EXUI:SetButtonKeyboardFocus(button, focused)
    if not button or button._gridType ~= "GridButton" then return end
    button._exButtonKeyboardFocused = focused == true
    PaintModernButton(button)
end

local function ApplyModernButton(frame)
    -- 点击与悬停在新客户端可分别受控。颜色按钮过去只恢复了 EnableMouse，
    -- 因而在部分池化复用路径里会出现“可以点击但没有 OnEnter/OnLeave”。
    -- 这里在所有 EXUI 按钮的共用入口一次补齐。
    if frame.EnableMouse then frame:EnableMouse(true) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
    -- 按钮外观全部由事件驱动，没有 OnUpdate 观察器：
    --   hover   ← OnEnter / OnLeave
    --   pressed ← OnMouseDown / OnMouseUp（OnLeave 一并清）
    --   enabled ← OnEnable / OnDisable
    --   显隐与池化复用 ← OnShow（清 hover/pressed）/ OnHide
    -- 框体出现在静止的鼠标底下时引擎会补发 OnEnter（用户 2026-10-05 实机确认），
    -- 所以池化复用不需要轮询兜底；要紧的是每次借用时槽位上确实有画器，这由
    -- HookControlScript 的按槽位记录保证。对照官方 ButtonStateBehaviorMixin
    -- （Blizzard_SharedXMLBase/ButtonStateBehavior.lua），它同样是纯事件，
    -- 并且在 OnShow 把 over/down 清成 nil。
    HookControlScript(frame, "OnEnter", function(self) self._exModernHover = true; PaintModernButton(self) end)
    HookControlScript(frame, "OnLeave", function(self) self._exModernHover = false; self._exModernPressed = false; PaintModernButton(self) end)
    HookControlScript(frame, "OnMouseDown", function(self, button) if button == "LeftButton" then self._exModernPressed = true; PaintModernButton(self) end end)
    HookControlScript(frame, "OnMouseUp", function(self) self._exModernPressed = false; PaintModernButton(self) end)
    HookControlScript(frame, "OnEnable", PaintModernButton)
    HookControlScript(frame, "OnDisable", PaintModernButton)
    HookControlScript(frame, "OnShow", function(self)
        self._exModernHover = nil
        self._exModernPressed = nil
        PaintModernButton(self)
    end)
    HookControlScript(frame, "OnHide", function(self)
        self._exModernHover = nil
        self._exModernPressed = nil
        self._exButtonKeyboardFocused = nil
        self._exButtonPainted = nil
        if self._exButtonFocusSurface then self._exButtonFocusSurface:Hide() end
        local skin = self._exModernSurfaces and self._exModernSurfaces[BUTTON_STYLE.radius]
        for _, piece in ipairs(skin and skin.pieces or {}) do
            if piece.texture._exButtonColor then piece.texture._exButtonColor.group:Stop() end
        end
        local label = self._exSidebarLabel or self:GetFontString()
        if label and label._exButtonColor then label._exButtonColor.group:Stop() end
    end)
    HideControlSkin(frame)
    if frame._gridType == "GridColorButton" then
        frame:SetPushedTextOffset(0, -1)
        MODERN.ApplyTextRole(frame.GetFontString and frame:GetFontString() or frame.label, "title")
    else
        frame:SetPushedTextOffset(0, -1)
        frame:SetNormalFontObject(MODERN.buttonFont)
        frame:SetHighlightFontObject(MODERN.buttonFont)
        frame:SetDisabledFontObject(MODERN.buttonFont)
        -- FontObject assignment can restore its default text color on a reused button.
        frame._exButtonPainted = nil
    end
    PaintModernButton(frame)
end

local function PaintModernInput(surface, editBox)
    local enabled = not editBox or not editBox.IsEnabled or editBox:IsEnabled()
    local focus = enabled and editBox and editBox.HasFocus and editBox:HasFocus()
    local hover = enabled and editBox and editBox._exModernHover
    local focusBorder = surface and surface._exModernInputFocusBorder or MC.inputFocusBorder
    local idleFill = surface and surface._exModernInputIdleFill or MC.input
    local activeFill = surface and surface._exModernInputActiveFill or idleFill
    local hoverBorder = surface and surface._exModernInputHoverBorder or MC.inputHoverBorder
    local fill = enabled and ((focus or hover) and activeFill or idleFill) or MC.inputDisabled
    local idleBorder = surface and surface._exModernInputIdleBorder or MC.inputBorder
    local edge = enabled and (focus and focusBorder or (hover and hoverBorder or idleBorder))
        or MC.inputDisabledBorder
    EXUI:SetControlSurface(surface, GM.radius.control, fill, edge)
    -- The input's own focus border above is the complete focus treatment.
    -- Hide a ring left by an earlier hot-reloaded lease instead of drawing a
    -- second translucent outline outside the control.
    if surface and surface._exModernInputFocusRing then
        surface._exModernInputFocusRing:Hide()
    end
    if editBox and editBox.SetTextColor then
        editBox:SetTextColor(unpack(enabled and MC.text or MC.disabledText))
    end
end

local function ApplyModernInput(frame)
    local editBox = frame.editBox or frame
    -- 输入框外观同样没有 OnUpdate 观察器：
    --   hover   ← OnEnter / OnLeave
    --   focus   ← OnEditFocusGained / OnEditFocusLost
    --   enabled ← Enable / Disable 的 hooksecurefunc（不占槽位，终身一次）
    --   显隐与池化复用 ← OnShow / OnHide
    -- 缓存放在 editBox 自己身上，只在三个状态真的变化时重画。
    -- hover/focus/显隐这几个槽位会被对象池和构造器 SetScript 清掉，所以用
    -- HookControlScript 按槽位记录，每次借用缺哪个补哪个。
    local function RefreshModernInputState()
        local enabled = not editBox.IsEnabled or editBox:IsEnabled()
        local hover = enabled and editBox:IsMouseOver() or false
        local focus = enabled and editBox:HasFocus() or false
        if editBox._exInputStateEnabled ~= enabled
            or editBox._exInputStateHover ~= hover
            or editBox._exInputStateFocus ~= focus then
            editBox._exInputStateEnabled = enabled
            editBox._exInputStateHover = hover
            editBox._exInputStateFocus = focus
            editBox._exModernHover = hover
            PaintModernInput(frame, editBox)
        end
    end
    HookControlScript(editBox, "OnEnter", RefreshModernInputState)
    HookControlScript(editBox, "OnLeave", RefreshModernInputState)
    HookControlScript(editBox, "OnEditFocusGained", RefreshModernInputState)
    -- 失焦要同时清掉选中高亮；两件事必须在同一个 handler 里，一个槽位只装一份。
    HookControlScript(editBox, "OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        RefreshModernInputState()
    end)
    HookControlScript(editBox, "OnShow", RefreshModernInputState)
    HookControlScript(editBox, "OnHide", function(self)
        self._exInputStateEnabled = nil
        self._exInputStateHover = nil
        self._exInputStateFocus = nil
        self._exModernHover = nil
    end)
    -- 本次借用的真实状态立即同步进缓存：上一租约留下的旧值会让第一次事件
    -- 被当成“没变化”而跳过重画。
    RefreshModernInputState()
    -- hooksecurefunc 不能撤销，也不占 extrinsic 槽位，所以它的标记跨租约保留。
    if not editBox._exModernInputEnableHooks then
        editBox._exModernInputEnableHooks = true
        for _, method in ipairs({ "Enable", "Disable" }) do
            if type(editBox[method]) == "function" then
                hooksecurefunc(editBox, method, RefreshModernInputState)
            end
        end
    end
    if editBox.SetTextInsets then
        if editBox._exSearchAppearance then
            editBox:SetTextInsets(28, editBox.ClearButton and 24 or 9, 0, 0)
        elseif editBox._exSliderNumberInput then
            -- 滑条数值框：GM.size.sliderInputWidth 宽的紧凑框，保留 sliderInput 字号与
            -- sliderInputInset 内边距，才能完整显示 100.5 / -100.5 / 1000。
            -- 字号与框宽是一组（2026-10-05 由 11/40 提到 13/48），只改一个会截断数值。
            editBox:SetTextInsets(SLIDER_NUMBER_INPUT_INSET, SLIDER_NUMBER_INPUT_INSET, 0, 0)
        else
            editBox:SetTextInsets(9, 9, editBox == frame and 0 or 7, editBox == frame and 0 or 7)
        end
    end
    MODERN.ApplyTextRole(editBox, editBox._exSearchAppearance and "control"
        or editBox._exInputTextRole
        or (editBox._exSliderNumberInput and "sliderInput" or "fieldValue"))
    MODERN.ApplyTextRole(frame.placeholder, editBox._exSearchAppearance and "control"
        or editBox._exInputTextRole or (editBox._exSliderNumberInput and "sliderInput" or "fieldValue"))
    PaintModernInput(frame, editBox)
end

local function PaintModernDropdown(frame)
    local enabled = frame:IsEnabled()
    local menuOpen = enabled and frame.IsMenuOpen and frame:IsMenuOpen()
    local active = enabled and (frame._exModernHover or menuOpen)
    EXUI:SetControlSurface(frame, GM.radius.control, enabled and MC.input or MC.inputDisabled,
        enabled and (menuOpen and MC.inputFocusBorder or (active and MC.inputHoverBorder or MC.inputBorder))
            or MC.inputDisabledBorder)
    if frame.Text then frame.Text:SetTextColor(unpack(enabled and MC.text or MC.disabledText)) end
    if frame._exModernChevron then
        local target = menuOpen and -math.pi or 0
        if frame._exModernChevronTarget == nil then
            frame._exModernChevronAngle = target
            frame._exModernChevronTarget = target
            frame._exModernChevron:SetRotation(target)
        elseif frame._exModernChevronTarget ~= target then
            frame._exModernChevronStart = frame._exModernChevronAngle or 0
            frame._exModernChevronTarget = target
            frame._exModernChevronElapsed = 0
        end
        frame._exModernChevron:SetVertexColor(unpack(enabled and (menuOpen and MC.blue
            or (active and MC.white or MC.muted)) or MC.disabledText))
    end
end

local function ApplyModernDropdown(frame)
    frame:SetHeight(frame._exGridFixedHeight or GM.size.dropdownHeight)
    if not frame._exModernChevron then
        local chevron = frame:CreateTexture(nil, "OVERLAY")
        chevron:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
        chevron:SetSize(16, 16)
        chevron:SetPoint("RIGHT", -8, 0)
        frame._exModernChevron = chevron
    end
    frame.Text:ClearAllPoints()
    frame.Text:SetPoint("LEFT", 9, 0)
    frame.Text:SetPoint("RIGHT", -29, 0)
    -- 触发框当前值与 Blizzard_Menu 选项共用同一个 15px FontObject，
    -- 避免两条渲染路径各自取默认字体后产生大小/字面观感差异。
    frame.Text:SetFontObject(MODERN.menuFonts.control)
    if frame.Text.SetShadowOffset then frame.Text:SetShadowOffset(0, 0) end
    if not frame._exModernDropdownHooks then
        frame._exModernDropdownHooks = true
        frame:HookScript("OnEnter", function(self) self._exModernHover = true; PaintModernDropdown(self) end)
        frame:HookScript("OnLeave", function(self) self._exModernHover = false; PaintModernDropdown(self) end)
        frame:HookScript("OnEnable", PaintModernDropdown)
        frame:HookScript("OnDisable", PaintModernDropdown)
        frame:HookScript("OnShow", PaintModernDropdown)
    end
    if not frame._exModernDropdownVisual then
        local visual = CreateFrame("Frame", nil, frame)
        visual:EnableMouse(false)
        visual:SetScript("OnUpdate", function(self, elapsed)
            local open = frame:IsEnabled() and frame.IsMenuOpen and frame:IsMenuOpen() or false
            if self.open ~= open then
                self.open = open
                PaintModernDropdown(frame)
            end
            if frame._exModernChevronElapsed then
                frame._exModernChevronElapsed = math.min(.15, frame._exModernChevronElapsed + elapsed)
                local progress = frame._exModernChevronElapsed / .15
                local angle = frame._exModernChevronStart
                    + (frame._exModernChevronTarget - frame._exModernChevronStart) * progress
                frame._exModernChevronAngle = angle
                frame._exModernChevron:SetRotation(angle)
                if progress >= 1 then frame._exModernChevronElapsed = nil end
            end
        end)
        visual:SetScript("OnHide", function(self)
            self.open = nil
            frame._exModernChevronElapsed = nil
            frame._exModernChevronTarget = nil
        end)
        frame._exModernDropdownVisual = visual
    end
    PaintModernDropdown(frame)
end

local function IsCursorInsideFrame(frame)
    if not frame or not frame.IsVisible or not frame:IsVisible() then return false end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom or not _G.GetCursorPosition then
        return frame.IsMouseOver and frame:IsMouseOver() or false
    end
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local cursorX, cursorY = _G.GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    if cursorX < left or cursorX > right or cursorY < bottom or cursorY > top then return false end
    -- The coordinate test immediately rejects a card which moved away during
    -- this layout pass. Mouse foci then preserve native clipping/occlusion and
    -- child hit semantics instead of treating the raw rectangle as sufficient.
    if _G.GetMouseFoci then
        for _, focus in ipairs(_G.GetMouseFoci()) do
            local region = focus
            while region do
                if region == frame then return true end
                region = region.GetParent and region:GetParent() or nil
            end
        end
        return false
    end
    return frame.IsMouseOver and frame:IsMouseOver() or false
end

-- Switch 几何。轨道与圆钮是两个独立 Frame，各自的 surface 都按物理像素取整；
-- 所以所有尺寸先换算成整数物理像素、再换回 UI 单位：
--   * 轨道高度取偶数像素 -> 两端是完整半圆（半径 = 高度/2，无竖直直边）；
--   * 圆钮直径与轨道同奇偶 -> 上下留白必为整数像素且相等，任何状态/缩放下垂直居中；
--   * 圆钮关/开位置 = 留白 / (轨道宽 - 圆钮 - 留白)，都是整数像素。
-- 数值全部来自 GM.size.switch*。
function MODERN.GetSwitchGeometry(surface)
    local pixel = MODERN.surfaceAtlas:GetPixel(surface)
    local trackHeight = 2 * math.max(1, math.floor(GM.size.switchTrackHeight / pixel / 2 + .5))
    local trackWidth = math.max(trackHeight, math.floor(GM.size.switchTrackWidth / pixel + .5))
    local knob = math.floor(GM.size.switchKnobSize / pixel + .5)
    if (trackHeight - knob) % 2 ~= 0 then knob = knob - 1 end
    knob = math.max(2, math.min(knob, trackHeight - 2))
    local inset = math.max(1, math.floor(GM.size.switchKnobInset / pixel + .5))
    return {
        trackWidth = trackWidth * pixel,
        trackHeight = trackHeight * pixel,
        trackRadius = trackHeight / 2 * pixel,
        knobSize = knob * pixel,
        knobRadius = knob / 2 * pixel,
        offX = inset * pixel,
        onX = (trackWidth - knob - inset) * pixel,
    }
end

-- 两个颜色是不是同一个（RGBA 四个分量都相等）。
local function IsSameThemeColor(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

function MODERN.PaintSwitchTrack(surface, geometry, fill, edge)
    -- 半径由几何推算，不属于 SetControlSurface 的视觉半径白名单。
    -- 轨道的 fill 与 edge 在除禁用以外的每个状态下都是同一个颜色。两层同色
    -- （atlas 的填充圆角 + 1px 描边圆角）叠在同一条圆弧上，抗锯齿边缘被合成
    -- 两次，大半径（胶囊半径 = 高度/2 = 10 物理像素）下就表现为明显锯齿、
    -- 圆弧"不够圆"。同色时只画填充这一层，和圆钮走的是同一条路径——圆钮
    -- 本来就只有填充（见 PaintModernCheckbox 的 knob 分支），所以它一直很圆。
    -- 禁用态的 fill/edge 是两个颜色，仍保留描边。
    if IsSameThemeColor(fill, edge) then edge = MC.transparent end
    MODERN.PaintControlSurface(surface, geometry.trackRadius, fill, edge)
end

function MODERN.StopSwitchMotion(knob)
    local motion = knob._exSwitchMotion
    if not motion then return end
    motion.generation = motion.generation + 1
    motion.group:SetScript("OnFinished", nil)
    motion.group:Stop()
    motion.selected, motion.startX, motion.targetX = nil, nil, nil
end

function MODERN.PositionSwitchKnob(container, selected, snap, geometry)
    local knob = container.checkbox._exModernSwitchKnob
    local surface = container.checkbox._exModernCheckSurface
    local motion = knob._exSwitchMotion
    if not motion then
        local group = knob:CreateAnimationGroup()
        local translation = group:CreateAnimation("Translation")
        translation:SetDuration(.12)
        translation:SetSmoothing("OUT")
        motion = { group = group, translation = translation, generation = 0 }
        knob._exSwitchMotion = motion
        -- This private visual child survives pool resets; hiding any ancestor
        -- invalidates the old completion before the checkbox can be reused.
        knob:SetScript("OnHide", MODERN.StopSwitchMotion)
    end
    local targetX = selected and geometry.onX or geometry.offX
    snap = snap or motion.selected == nil or not container:IsVisible()
    if not snap and motion.selected == selected then
        -- 选中状态没变：只有像素几何变了（缩放）才把圆钮重新落到新的整像素位置。
        if motion.targetX == targetX or motion.group:IsPlaying() then return end
        snap = true
    end
    local currentX = motion.targetX or targetX
    if not snap and motion.group:IsPlaying() then
        -- Sample the native eased progress once on reversal, never per frame.
        currentX = motion.startX + (motion.targetX - motion.startX)
            * motion.translation:GetSmoothProgress()
    end
    MODERN.StopSwitchMotion(knob)
    motion.selected = selected
    motion.startX, motion.targetX = snap and targetX or currentX, targetX
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", surface, "LEFT", motion.startX, 0)
    if snap or currentX == targetX then return end
    local generation = motion.generation
    motion.translation:SetOffset(targetX - currentX, 0)
    motion.group:SetScript("OnFinished", function(group)
        if motion.generation ~= generation or container._exSettingsPresentation ~= "switch"
            or not knob:IsVisible() then return end
        group:SetScript("OnFinished", nil)
        group:Stop()
        -- Translation is temporary; commit its endpoint to the actual anchor.
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", surface, "LEFT", targetX, 0)
        motion.startX = targetX
    end)
    motion.group:Play()
end

local function PaintModernCheckbox(container, skipCardMeasure, snapSwitch)
    local box = container.checkbox
    if not box then return end
    HideControlSkin(box)
    -- 三态勾选框的“部分”横杠只在下面的普通方框分支里重新显示。
    if box._exModernMixedMark then box._exModernMixedMark:Hide() end
    if container._exCheckboxOnOffVisual and container._exCheckboxOnOffVisual:IsShown() then
        if box._exModernCheckSurface then box._exModernCheckSurface:Hide() end
        if box._exModernCheckMark then box._exModernCheckMark:Hide() end
        if box._exModernSwitchKnob then box._exModernSwitchKnob:Hide() end
        if box._exSettingsCardSurface then box._exSettingsCardSurface:Hide() end
        return
    end
    local enabled, selected = box:IsEnabled(), box:GetChecked() == true
    local hover = enabled and box._exModernHover
    local pressed = enabled and box._exModernPressed
    local fill, edge
    local isCard = container._exSettingsPresentation == "card"
    if box._exSettingsCardSurface then box._exSettingsCardSurface:SetShown(isCard) end
    if container._exSettingsPresentation == "switch" then
        if not box._exModernSwitchKnob then
            local knob = CreateFrame("Frame", nil, box._exModernCheckSurface)
            knob:EnableMouse(false)
            box._exModernSwitchKnob = knob
            -- 轨道与圆钮组成一个取整组；UI 缩放变化时整体按新像素尺寸重算。
            box._exModernCheckSurface._exSurfaceGroup = { box._exModernCheckSurface, knob }
            knob._exSurfaceGroup = box._exModernCheckSurface._exSurfaceGroup
            box._exModernCheckSurface._exSurfaceRescale = function()
                if container._exSettingsPresentation == "switch" then
                    PaintModernCheckbox(container, nil, true)
                end
            end
        end
        if not enabled then
            fill, edge = MC.disabledFill, MC.disabledBorder
        elseif selected then
            fill = pressed and MC.checkboxCheckedActive or (hover and MC.switchOnHover or MC.switchOn)
            edge = pressed and MODERN.switchOnPressedEdge
                or (hover and MODERN.switchOnHoverEdge or MODERN.switchOnEdge)
        else
            fill = pressed and MC.checkboxHoverBorder
                or (hover and MODERN.switchOffHoverFill or MC.switchOff)
            edge = pressed and MODERN.switchOffPressedEdge
                or (hover and MODERN.switchOffHoverEdge or MODERN.switchOffEdge)
        end
        local surface = box._exModernCheckSurface
        local knob = box._exModernSwitchKnob
        local geometry = MODERN.GetSwitchGeometry(surface)
        -- 悬停只改颜色。几何没变就不再重设尺寸、重定位圆钮或重画圆钮表面，
        -- 否则每次悬停重画都要重新做一次物理像素对齐，圆钮看起来会上下跳。
        local cached = box._exSwitchGeometry
        local geometryChanged = surface:GetNumPoints() == 0 or not cached
            or cached.trackWidth ~= geometry.trackWidth or cached.trackHeight ~= geometry.trackHeight
            or cached.knobSize ~= geometry.knobSize
            or cached.offX ~= geometry.offX or cached.onX ~= geometry.onX
        box._exSwitchGeometry = geometry
        if geometryChanged then
            surface:ClearAllPoints()
            surface:SetPoint("CENTER", box, "CENTER", 0, 0)
            surface:SetSize(geometry.trackWidth, geometry.trackHeight)
            knob:SetSize(geometry.knobSize, geometry.knobSize)
        end
        MODERN.PaintSwitchTrack(surface, geometry, fill, edge)
        box._exModernCheckMark:Hide()
        -- knob 隐藏时动画会被停掉并清空 motion.selected；那之后必须重新落位。
        local motionCleared = not knob._exSwitchMotion or knob._exSwitchMotion.selected == nil
        if geometryChanged or snapSwitch or motionCleared or box._exSwitchSelected ~= selected then
            MODERN.PositionSwitchKnob(container, selected, snapSwitch or geometryChanged, geometry)
            box._exSwitchSelected = selected
        end
        local knobColor = enabled and MC.switchKnobOn or MC.disabledText
        -- One fill mask produces a clean circular edge; a same-color border
        -- would composite the antialiased rim twice and make it look uneven.
        if geometryChanged or box._exSwitchKnobColor ~= knobColor then
            MODERN.PaintControlSurface(knob, geometry.knobRadius, knobColor, MC.transparent)
            box._exSwitchKnobColor = knobColor
        end
        knob:Show()
        surface:SetAlpha(1)
        if container.label then
            container.label:SetTextColor(unpack(enabled and MC.text or MC.disabledText))
        end
        return
    end
    if box._exModernSwitchKnob then box._exModernSwitchKnob:Hide() end
    -- 离开 switch 呈现后，下次再进来必须重新按当前几何落位。
    box._exSwitchGeometry, box._exSwitchSelected, box._exSwitchKnobColor = nil, nil, nil
    box._exModernCheckSurface:ClearAllPoints()
    box._exModernCheckSurface:SetPoint("LEFT", box, "LEFT", 0, 0)
    box._exModernCheckSurface:SetSize(GM.size.checkboxBoxSize, GM.size.checkboxBoxSize)
    if isCard then
        local card = box._exSettingsCardSurface
        if not card then
            card = CreateFrame("Frame", nil, box)
            card:EnableMouse(false)
            card:SetAllPoints(box)
            card.Title = EXUI:CreateVisualFontString(card, EXFONTFRAME, "GameFontHighlight")
            card.Title:SetJustifyH("LEFT")
            card.Title:SetWordWrap(false)
            card.Icon = EXUI:CreateVisualTexture(card, EXBASEFRAME)
            card.Icon:SetSize(16, 16)
            -- 斜角色块是一个 37×37 的白块旋转 45°、中心锚在卡片右上角，所以它必须被
            -- 裁掉卡片外的那一半才会呈现为"斜角"。卡片本体不能开裁剪（公共 surface 的
            -- 1px 描边正好画在卡片边界上，开裁剪会少一条边），因此裁剪放在这个只管斜角
            -- 的子 Frame 上：它只裁自己的子对象，卡片的描边不受影响。
            -- 小勾也放在同一个 Frame 里（OVERLAY 层），否则子 Frame 的层级会把画在
            -- 卡片上的勾盖住；勾压在斜角上是原始画法。
            card.CornerClip = CreateFrame("Frame", nil, card)
            card.CornerClip:EnableMouse(false)
            card.CornerClip:SetAllPoints(card)
            card.CornerClip:SetClipsChildren(true)
            card.Corner = card.CornerClip:CreateTexture(nil, "ARTWORK", nil, 1)
            card.Corner:SetTexture("Interface\\Buttons\\WHITE8X8")
            card.Corner:SetSize(37, 37)
            card.Corner:SetPoint("CENTER", card, "TOPRIGHT", 0, 0)
            card.Corner:SetRotation(math.pi / 4)
            card.CornerCheck = card.CornerClip:CreateTexture(nil, "OVERLAY")
            card.CornerCheck:SetTexture(MODERN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
            card.CornerCheck:SetSize(11, 11)
            card.CornerCheck:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
            box._exSettingsCardSurface = card
        end
        card:SetFrameLevel(box:GetFrameLevel())
        -- 斜角裁剪层始终压在卡片本体之上，否则卡片的填充会盖住斜角与小勾。
        card.CornerClip:SetFrameLevel(card:GetFrameLevel() + 1)
        -- 卡片不裁子对象：公共 surface 的 1px 描边正好画在卡片边界上，开启裁剪时
        -- 像素对齐一旦落在边界外半像素，整条边（通常是右边）就会被裁掉。标题已有
        -- 右锚点与 SetWordWrap(false)，溢出由它自己截断，不需要靠裁剪。
        card:SetClipsChildren(false)
        EXUI:SetControlSurface(card, GM.radius.control,
            not enabled and MC.disabledFill or (selected and GC.checkCardSelected or GC.checkCard),
            not enabled and MC.disabledBorder or (selected and GC.checkCardSelectedBorder
                or (hover and GC.checkCardHoverBorder or GC.checkCardBorder)))
        local hasDescription = container._exSettingsCardDescription == true
        box._exModernCheckSurface:Hide()
        box._exModernCheckMark:Hide()
        card.Corner:SetVertexColor(unpack(enabled and GC.checkCardCorner or MC.disabledText))
        card.CornerCheck:SetVertexColor(unpack(enabled and GC.checkCardCornerCheck or MC.disabledText))
        -- 选中时右上角是主色斜角色块（37×37 白块旋转 45°、中心锚在 TOPRIGHT），
        -- 白色小勾压在斜角上：两者一起显示，颜色分别取 checkCardCorner / checkCardCornerCheck
        -- （用户 2026-10-05 要求恢复 2026-10-02 停用的斜角，勾与斜角共存的原始画法）。
        card.Corner:SetShown(selected)
        card.CornerCheck:SetShown(selected)
        card.Icon:ClearAllPoints()
        card.Icon:SetSize(16, 16)
        card.Icon:SetPoint(hasDescription and "TOPLEFT" or "LEFT", card,
            hasDescription and "TOPLEFT" or "LEFT", 14, hasDescription and -10 or 0)
        card.Icon:SetTexture(container._exSettingsCardIcon)
        card.Icon:SetShown(container._exSettingsCardIcon ~= nil)
        card.Icon:SetAlpha(enabled and 1 or .4)
        card.Title:ClearAllPoints()
        if container._exSettingsCardIcon then
            card.Title:SetPoint("LEFT", card.Icon, "RIGHT", 8, 0)
        else
            card.Title:SetPoint(hasDescription and "TOPLEFT" or "LEFT", card,
                hasDescription and "TOPLEFT" or "LEFT", 14, hasDescription and -10 or 0)
        end
        card.Title:SetPoint("RIGHT", card, hasDescription and "TOPRIGHT" or "RIGHT",
            -30, hasDescription and -19 or 0)
        card.Title:SetText(container.label and container.label:GetText() or "")
        MODERN.ApplyTextRole(card.Title, "title", enabled and (selected and GC.checkCardSelectedText
            or GC.checkCardText) or MC.disabledText)
        if container._exSettingsCardTextSize then
            local font, _, flags = card.Title:GetFont()
            card.Title:SetFont(font, container._exSettingsCardTextSize, flags)
        end
        card:Show()
        return
    end
    box._exModernCheckSurface:Show()
    box._exModernCheckMark:ClearAllPoints()
    box._exModernCheckMark:SetAllPoints(box._exModernCheckSurface)
    -- 三态勾选框的“部分”状态：原生勾选为否，由 container._exTriState 标记。
    local mixed = container._exTriState == "mixed" and not selected
    if not enabled then
        fill, edge = MC.disabledFill, MC.disabledBorder
    elseif selected then
        fill = pressed and MC.checkboxCheckedActive or (hover and MC.checkboxCheckedHover or MC.checkboxChecked)
        edge = fill
    else
        fill = pressed and MODERN.checkboxPressedFill
            or (hover and MODERN.checkboxHoverFill or MC.input)
        edge = hover and MC.checkboxHoverBorder or MC.checkboxBorder
        -- “部分”：方框保持未选填充，边框改用选中主色，中间画横杠。
        if mixed then
            edge = pressed and MC.checkboxCheckedActive or (hover and MC.checkboxCheckedHover or MC.checkboxChecked)
        end
    end
    EXUI:SetControlSurface(box._exModernCheckSurface, GM.radius.control, fill, edge)
    box._exModernCheckMark:SetShown(selected)
    box._exModernCheckMark:SetVertexColor(unpack(enabled and MC.white or MC.disabledText))
    if mixed then
        local dash = box._exModernMixedMark
        if not dash then
            dash = box._exModernCheckSurface:CreateTexture(nil, "OVERLAY")
            dash:SetTexture("Interface\\Buttons\\WHITE8X8")
            box._exModernMixedMark = dash
        end
        dash:ClearAllPoints()
        dash:SetPoint("CENTER", box._exModernCheckSurface, "CENTER", 0, 0)
        dash:SetSize(GM.size.checkboxBoxSize / 2, 2)
        dash:SetVertexColor(unpack(enabled and edge or MC.disabledText))
        dash:Show()
    end
    box._exModernCheckSurface:SetAlpha(1)
    if container.label then
        container.label:SetTextColor(unpack(enabled and MC.text or MC.disabledText))
    end
end

local function ApplyModernCheckbox(container)
    local box = container.checkbox
    if not box then return end
    StripCheckButtonStateTextures(box)
    if not box._exModernCheckSurface then
        local surface = CreateFrame("Frame", nil, box)
        surface:SetSize(GM.size.checkboxBoxSize, GM.size.checkboxBoxSize)
        surface:SetPoint("LEFT", box, "LEFT", 0, 0)
        surface:EnableMouse(false)
        box._exModernCheckSurface = surface
        local mark = surface:CreateTexture(nil, "OVERLAY")
        mark:SetTexture(MODERN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
        mark:SetAllPoints(surface)
        box._exModernCheckMark = mark
        -- Native checked state remains the source of truth. Do not attach
        -- appearance updates to OnClick: callers legitimately replace it.
        local visual = CreateFrame("Frame", nil, box)
        visual:EnableMouse(false)
        visual:SetScript("OnUpdate", function(self)
            local enabled = box:IsEnabled()
            local hover = false
            if enabled then
                if container._exSettingsPresentation == "card" then
                    hover = IsCursorInsideFrame(box)
                else
                    hover = box:IsMouseOver()
                end
            end
            local checked = box:GetChecked() == true
            if self.enabled ~= enabled or self.hover ~= hover or self.checked ~= checked then
                self.enabled, self.hover, self.checked = enabled, hover, checked
                box._exModernHover = hover
                PaintModernCheckbox(container)
            end
        end)
        visual:SetScript("OnHide", function(self)
            self.enabled, self.hover, self.checked = nil, nil, nil
            box._exModernHover = nil
        end)
        box._exModernCheckVisual = visual
        visual:SetScript("OnShow", function()
            if container._exSettingsPresentation == "switch" then
                PaintModernCheckbox(container, nil, true)
            end
        end)
    end
    -- pressed 由指针事件驱动；这三个槽位都会被 GridCheckbox 的 reset 和
    -- CreateCheckbox 自己清掉，所以按槽位记录、每次借用补装。
    -- checked 仍由上面的 watcher 观察：它是 C 函数 SetChecked() 写入的，不触发
    -- 任何事件，且存在绕过容器直接调 box:SetChecked 的调用点，收口前不能删。
    HookControlScript(box, "OnMouseDown", function(self, button)
        if button == "LeftButton" and self:IsEnabled() then
            self._exModernPressed = true
            PaintModernCheckbox(container)
        end
    end)
    HookControlScript(box, "OnMouseUp", function(self)
        self._exModernPressed = nil
        PaintModernCheckbox(container)
    end)
    HookControlScript(box, "OnLeave", function(self)
        self._exModernPressed = nil
        PaintModernCheckbox(container)
    end)
    if container.label then
        container.label:ClearAllPoints()
        container.label:SetPoint("LEFT", container, "LEFT", 27, 0)
        container.label:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        container.label:SetJustifyH("LEFT")
        MODERN.ApplyTextRole(container.label, "title")
    end
    PaintModernCheckbox(container, nil, true)
end

-- Settings-list card widths can change the final right-aligned geometry after
-- the native checked state has already painted. Re-read only visual state once
-- the layout owner has finished moving every row/card; no click or value
-- callback is invoked here.
function EXUI:RefreshSettingsListCardVisual(container)
    local box = container and container.checkbox
    if not box or container._exSettingsPresentation ~= "card" then return false end
    local enabled = box:IsEnabled()
    local hover = enabled and IsCursorInsideFrame(box) or false
    local checked = box:GetChecked() == true
    local needsDeferredHoverRefresh = container._exSettingsCardVisualPending == true
    local visual = box._exModernCheckVisual
    if visual then
        visual.enabled, visual.hover, visual.checked = enabled, hover, checked
    end
    container._exSettingsCardVisualPending = nil
    box._exModernHover = hover
    if not enabled then box._exModernPressed = nil end
    PaintModernCheckbox(container)
    return true, needsDeferredHoverRefresh
end

-- One-shot post-layout hover sync. Geometry and checked-state caches stay
-- owned by the completed layout/normal visual watcher; this path neither
-- remeasures the card nor requests another reflow.
function EXUI:RefreshSettingsListCardHoverVisual(container)
    local box = container and container.checkbox
    if not box or container._exSettingsPresentation ~= "card"
        or container._exSettingsCardVisualPending then return false end
    local enabled = box:IsEnabled()
    local hover = enabled and IsCursorInsideFrame(box) or false
    local visual = box._exModernCheckVisual
    -- A newer click can occur before this one-shot callback. Do not paint that
    -- unchecked/checked transition at geometry committed for the older state.
    if not visual or visual.checked ~= (box:GetChecked() == true) then return false end
    visual.enabled, visual.hover = enabled, hover
    box._exModernHover = hover
    PaintModernCheckbox(container, true)
    return true
end

local function IsModernSliderEnabled(frame)
    local interactive = frame.Slider or frame
    if frame.IsSliderEnabled then return frame:IsSliderEnabled() end
    if interactive.IsEnabled then return interactive:IsEnabled() end
    return true
end

local function SuppressModernSliderSteppers(frame)
    for _, key in ipairs({ "Back", "Forward" }) do
        local stepper = frame[key]
        if stepper then
            stepper:Hide()
            stepper:SetAlpha(0)
            if stepper.EnableMouse then stepper:EnableMouse(false) end
            if stepper.Disable then stepper:Disable() end
        end
    end
end

-- 轨道与拖块都以滑条中线为中心，但各自按物理像素取整。高度换算成整数像素后
-- 必须同奇偶，否则两者的中线会差半个物理像素（拖块看起来偏上或偏下）。
-- 尺寸读 GM.size.sliderTrackHeight / sliderThumbWidth / sliderThumbHeight。
function MODERN.LayoutSliderGeometry(frame)
    local interactive = frame.Slider or frame
    local pixel = MODERN.surfaceAtlas:GetPixel(interactive)
    local thumbHeight = math.max(1, math.floor(GM.size.sliderThumbHeight / pixel + .5))
    local trackHeight = math.max(1, math.floor(GM.size.sliderTrackHeight / pixel + .5))
    if (thumbHeight - trackHeight) % 2 ~= 0 then
        trackHeight = trackHeight < thumbHeight and trackHeight + 1 or trackHeight - 1
    end
    frame._exModernSliderTrack:SetHeight(trackHeight * pixel)
    local thumb = interactive.GetThumbTexture and interactive:GetThumbTexture()
    if thumb then
        thumb:SetSize(math.max(1, math.floor(GM.size.sliderThumbWidth / pixel + .5)) * pixel,
            thumbHeight * pixel)
    end
end

local function PaintModernSlider(frame)
    SuppressModernSliderSteppers(frame)
    local interactive = frame.Slider or frame
    local enabled = IsModernSliderEnabled(frame)
    local pressed = enabled and (interactive._exModernPressed or frame._exDragging)
    local hover = enabled and (interactive._exModernHover or pressed)
    MODERN.LayoutSliderGeometry(frame)
    -- 轨道整条都是空的灰条：**不画已走过那一段的填充**（用户 2026-10-05 推翻
    -- 2026-10-04 的实心填充做法）。因为没有填充可以变亮，悬停／拖动的反馈
    -- 全部落在轨道本身换色上：常态灰 -> 悬停亮灰白 -> 拖动中近白（三档都是中性
    -- 灰阶，不带蓝；用户 2026-10-05 推翻同日早些时候的主色系悬停）。拖块是蓝色，
    -- 本次未改，拖动时靠色相而不是明暗与轨道区分。
    local trackColor = not enabled and MC.disabledText
        or (pressed and GC.sliderTrackActive
            or (hover and GC.sliderTrackHover or GC.sliderTrack))
    EXUI:SetControlSurface(frame._exModernSliderTrack, GM.radius.thumb, trackColor, trackColor)
    local thumb = interactive.GetThumbTexture and interactive:GetThumbTexture()
    if thumb then
        thumb:SetVertexColor(unpack(enabled and (pressed and GC.sliderKnobPressed
            or (hover and GC.sliderKnobHover or GC.sliderKnob)) or MC.disabledText))
    end
    if frame._exModernSliderRing then
        frame._exModernSliderRing:Hide() -- 悬停不再显示滑块后方方块（原 SetShown(enabled and hover)）
        if enabled and hover then
            frame._exModernSliderRing:SetColorTexture(unpack(GC.sliderThumbRing))
        end
    end
    if frame.numberInput then
        if enabled and frame.numberInput.Enable then frame.numberInput:Enable()
        elseif not enabled and frame.numberInput.Disable then frame.numberInput:Disable() end
        PaintModernInput(frame.numberInput, frame.numberInput)
    end
    if frame.Title then frame.Title:SetTextColor(unpack(enabled and MC.text or MC.disabledText)) end
    if frame.ValueText then frame.ValueText:SetTextColor(unpack(enabled and MC.lightBlue or MC.disabledText)) end
end

local function ApplyModernSlider(frame)
    local interactive = frame.Slider or frame
    -- 设置行呈现（SettingsList 的 valuePosition="right"）有自己的唯一布局函数：
    -- 它把数值框挂到滑条本体右侧**之外**、让轨道占满本体。本函数下面那套锚点
    -- 假定数值框在本体**之内**，两者同时生效就是两个布局器打架——切页时重新
    -- ApplyControlAppearance 会按本函数把轨道右缘锚到本体之外的数值框上，
    -- 轨道因此横着越过数值框、看起来横贯整行。已被接管时不再覆盖它的布局。
    local settingsRowOwned = frame._exSettingsValuePosition == "right" and frame.numberInput ~= nil
    if interactive ~= frame and not settingsRowOwned then
        interactive:ClearAllPoints()
        interactive:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        if frame.numberInput and frame._exNumberInputPosition ~= "title" then
            interactive:SetPoint("RIGHT", frame.numberInput, "LEFT", -8, 0)
        else
            interactive:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        interactive:SetHeight(GM.size.controlHeight)
    end
    SuppressModernSliderSteppers(frame)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if interactive[key] then interactive[key]:SetAlpha(0) end
    end
    if not frame._exModernSliderTrack then
        -- 轨道是带圆角的 surface，必须是 Frame；层级压在滑条本体之下，拖块（滑条自带贴图）仍画在它上面。
        local track = CreateFrame("Frame", nil, interactive)
        track:EnableMouse(false)
        track:SetFrameLevel(math.max(0, interactive:GetFrameLevel() - 1))
        track:SetPoint("LEFT", interactive, "LEFT", 0, 0)
        track:SetPoint("RIGHT", interactive, "RIGHT", 0, 0)
        track:SetHeight(GM.size.sliderTrackHeight)
        frame._exModernSliderTrack = track
        local thumb = interactive.GetThumbTexture and interactive:GetThumbTexture()
        if thumb then
            thumb:SetTexture(MODERN_MEDIA .. "KnobR3.tga", "CLAMP", "CLAMP", "LINEAR")
            thumb:SetTexCoord(118 / 256, 138 / 256, 52 / 128, 76 / 128)
            local ring = interactive:CreateTexture(nil, "BACKGROUND", nil, 2)
            ring:SetPoint("CENTER", thumb, "CENTER", 0, 0)
            ring:SetSize(28, 20)
            frame._exModernSliderRing = ring
        end
    end
    -- 热重载／对象池里的旧实例可能还带着上一版的填充 Frame。轨道现在是空的，
    -- 必须把它的 surface 停掉并解引用，否则旧填充会留在轨道上。
    if frame._exModernSliderFill then
        EXUI:ClearControlSurface(frame._exModernSliderFill)
        frame._exModernSliderFill:Hide()
        frame._exModernSliderFill:ClearAllPoints()
        frame._exModernSliderFill = nil
    end
    -- 轨道 hover / pressed 同样是事件驱动。OnEnter/OnLeave/OnMouseDown/OnMouseUp
    -- 这些槽位会被对象池清掉，按槽位记录后每次借用补装（同按钮一个根因）。
    HookControlScript(interactive, "OnEnter", function(self) self._exModernHover = true; PaintModernSlider(frame) end)
    HookControlScript(interactive, "OnLeave", function(self)
        self._exModernHover = false
        if not frame._exDragging then self._exModernPressed = false end
        PaintModernSlider(frame)
    end)
    HookControlScript(interactive, "OnMouseDown", function(self, button)
        if button == nil or button == "LeftButton" then self._exModernPressed = true; PaintModernSlider(frame) end
    end)
    HookControlScript(interactive, "OnMouseUp", function(self) self._exModernPressed = false; PaintModernSlider(frame) end)
    HookControlScript(interactive, "OnSizeChanged", function() PaintModernSlider(frame) end)
    HookControlScript(frame, "OnEnable", PaintModernSlider)
    HookControlScript(frame, "OnDisable", PaintModernSlider)
    HookControlScript(frame, "OnShow", PaintModernSlider)
    if not frame._exModernSliderLifetimeHooks then
        frame._exModernSliderLifetimeHooks = true
        if frame.SetEnabled then
            hooksecurefunc(frame, "SetEnabled", function(self) PaintModernSlider(self) end)
        end
        if frame.UpdateStepperStates then
            hooksecurefunc(frame, "UpdateStepperStates", function(self) PaintModernSlider(self) end)
        end
    end
    if frame.numberInput then
        ApplyModernInput(frame.numberInput)
    end
    MODERN.ApplyTextRole(frame.Title, "title")
    MODERN.ApplyTextRole(frame.ValueText, "hint", MC.lightBlue)
    PaintModernSlider(frame)
end

local function HideModernScrollBarNativePieces(owner)
    if not owner then return end
    for _, key in ipairs({ "Begin", "Middle", "End" }) do
        local texture = owner[key]
        if texture then
            texture:SetAlpha(0)
            texture:Hide()
        end
    end
end

local function SuppressModernScrollBarSteppers(scrollBar)
    for _, key in ipairs({ "Back", "Forward" }) do
        local stepper = scrollBar and scrollBar[key]
        if stepper then
            stepper:Hide()
            stepper:SetAlpha(0)
            if stepper.EnableMouse then stepper:EnableMouse(false) end
            if stepper.SetEnabled then stepper:SetEnabled(false) end
        end
    end
end

local function PaintModernScrollBar(scrollBar)
    if not scrollBar or not scrollBar.GetTrack or not scrollBar.GetThumb then return end
    local track = scrollBar:GetTrack()
    local thumb = scrollBar:GetThumb()
    if not (track and thumb) then return end

    SuppressModernScrollBarSteppers(scrollBar)
    HideModernScrollBarNativePieces(track)
    HideModernScrollBarNativePieces(thumb)

    local scrollEnabled = (not scrollBar.IsScrollAllowed or scrollBar:IsScrollAllowed())
        and (not scrollBar.HasScrollableExtent or scrollBar:HasScrollableExtent())
    local thumbEnabled = scrollEnabled and (not thumb.IsEnabled or thumb:IsEnabled())
    -- MinimalScrollBar keeps its native drag state in `down`; retain our
    -- explicit pressed flag as the immediate fallback around MouseDown/Up.
    -- Idle and hover stay neutral; blue is reserved for an active press/drag.
    local thumbPressed = thumbEnabled and (thumb._exModernPressed or thumb.down)

    EXUI:SetControlSurface(track, GM.radius.control, MC.transparent, MC.transparent)
    EXUI:SetControlSurface(thumb, GM.radius.control,
        thumbEnabled and (thumbPressed and MC.blue or MC.secondaryBorder) or MC.disabled,
        thumbEnabled and (thumbPressed and MC.blue or MC.secondaryBorder) or MC.disabled)
end

-- ScrollFrameTemplate creates its MinimalScrollBar outside the viewport.  Keep
-- the shared geometry explicit so every consumer reserves the same strip:
-- 10px bar + 6px template gap + 2px panel-edge inset = 18px.
local MODERN_SCROLL_BAR_WIDTH = 10
local MODERN_SCROLL_BAR_TRACK_WIDTH = 8
local MODERN_SCROLL_BAR_OFFSET_X = 6
local MODERN_SCROLL_BAR_OFFSET_TOP = 2
local MODERN_SCROLL_BAR_OFFSET_BOTTOM = 5
EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET = 18

-- The current Blizzard ScrollFrameTemplate creates one MinimalScrollBar and
-- binds it through ScrollUtil.InitScrollFrameWithScrollBar.  EXUI only changes
-- that native control's geometry and appearance; wheel, page-click,
-- proportional-thumb and drag behavior remain owned by Blizzard.
function EXUI:ApplyModernScrollBar(scrollBar, preserveGeometry)
    if not scrollBar or not scrollBar.GetTrack or not scrollBar.GetThumb then return scrollBar end
    local track = scrollBar:GetTrack()
    local thumb = scrollBar:GetThumb()
    if not (track and thumb) then return scrollBar end

    if not preserveGeometry then
        track:ClearAllPoints()
        if scrollBar.isHorizontal then
            scrollBar:SetHeight(MODERN_SCROLL_BAR_WIDTH)
            track:SetPoint("LEFT", scrollBar, "LEFT", 0, 0)
            track:SetPoint("RIGHT", scrollBar, "RIGHT", 0, 0)
            track:SetHeight(MODERN_SCROLL_BAR_TRACK_WIDTH)
            thumb:SetHeight(MODERN_SCROLL_BAR_TRACK_WIDTH)
        else
            scrollBar:SetWidth(MODERN_SCROLL_BAR_WIDTH)
            track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
            track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
            track:SetWidth(MODERN_SCROLL_BAR_TRACK_WIDTH)
            thumb:SetWidth(MODERN_SCROLL_BAR_TRACK_WIDTH)
        end
    end
    SuppressModernScrollBarSteppers(scrollBar)
    -- Recalculate proportional thumb extent/offset against the full-height
    -- track immediately; later size/range changes continue through Blizzard's
    -- existing Track OnSizeChanged and ScrollUtil callbacks.
    if not preserveGeometry and scrollBar.Update then scrollBar:Update() end

    if not scrollBar._exModernScrollBarHooks then
        scrollBar._exModernScrollBarHooks = true
        track:HookScript("OnEnter", function(self)
            self._exModernHover = true
            PaintModernScrollBar(scrollBar)
        end)
        track:HookScript("OnLeave", function(self)
            self._exModernHover = nil
            PaintModernScrollBar(scrollBar)
        end)
        track:HookScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self._exModernPressed = true end
            PaintModernScrollBar(scrollBar)
        end)
        track:HookScript("OnMouseUp", function(self)
            self._exModernPressed = nil
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnEnter", function(self)
            self._exModernHover = true
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnLeave", function(self)
            self._exModernHover = nil
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self._exModernPressed = true end
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnMouseUp", function(self)
            self._exModernPressed = nil
            PaintModernScrollBar(scrollBar)
        end)
        thumb:HookScript("OnEnable", function() PaintModernScrollBar(scrollBar) end)
        thumb:HookScript("OnDisable", function() PaintModernScrollBar(scrollBar) end)
        thumb:HookScript("OnShow", function() PaintModernScrollBar(scrollBar) end)
        thumb:HookScript("OnHide", function(self)
            self._exModernHover = nil
            self._exModernPressed = nil
            PaintModernScrollBar(scrollBar)
        end)
        scrollBar:HookScript("OnShow", function(self) PaintModernScrollBar(self) end)
        scrollBar:HookScript("OnHide", function(self)
            -- Blizzard stops drag/page-repeat from MouseUp.  A parent can hide
            -- before that callback is delivered, so end the native update loop
            -- through its own lifecycle API and let the next interaction start
            -- from a clean state.
            if self.UnregisterUpdate then self:UnregisterUpdate() end
            track._exModernHover = nil
            track._exModernPressed = nil
            thumb._exModernHover = nil
            thumb._exModernPressed = nil
        end)
    end

    PaintModernScrollBar(scrollBar)
    return scrollBar
end

function EXUI:ApplyModernScrollFrame(scrollFrame)
    if scrollFrame and scrollFrame.ScrollBar then
        local scrollBar = scrollFrame.ScrollBar
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT",
            MODERN_SCROLL_BAR_OFFSET_X, MODERN_SCROLL_BAR_OFFSET_TOP)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT",
            MODERN_SCROLL_BAR_OFFSET_X, MODERN_SCROLL_BAR_OFFSET_BOTTOM)
        self:ApplyModernScrollBar(scrollFrame.ScrollBar)
    end
    return scrollFrame
end

-- options.horizontal=true adds a native proportional horizontal bar below the
-- viewport (reserve GetHorizontalScrollInset()) and Shift+wheel access.
-- ScrollFrame remains non-pooled; the content owner manages its lifecycle.
function EXUI:CreateScrollFrame(parent, name, options)
    options = options or {}
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")
    scrollFrame:EnableMouseWheel(true)
    self:ApplyModernScrollFrame(scrollFrame)
    function scrollFrame:GetHorizontalScrollInset()
        return self.HorizontalScrollBar and (MODERN_SCROLL_BAR_WIDTH + MODERN_SCROLL_BAR_OFFSET_X) or 0
    end
    if options.horizontal == true then
        local bar = CreateFrame("EventFrame", nil, scrollFrame, "MinimalScrollBar")
        -- ScrollBarMixin reads the axis for its proportional geometry and native
        -- track/thumb interaction. Re-anchor too; a rotated vertical bar is insufficient.
        bar.isHorizontal, bar.thumbAnchor = true, "LEFT"
        bar:GetThumb().isHorizontal = true
        bar:GetThumb():ClearAllPoints()
        bar:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -MODERN_SCROLL_BAR_OFFSET_X)
        bar:SetPoint("TOPRIGHT", scrollFrame, "BOTTOMRIGHT", 0, -MODERN_SCROLL_BAR_OFFSET_X)
        scrollFrame.HorizontalScrollBar = bar
        self:ApplyModernScrollBar(bar)
        local updating = false
        local function UpdateHorizontal()
            if updating then return end
            updating = true
            local range = math.max(0, scrollFrame:GetHorizontalScrollRange())
            local offset = math.max(0, math.min(range, scrollFrame:GetHorizontalScroll()))
            local width = math.max(0, scrollFrame:GetWidth())
            scrollFrame:SetHorizontalScroll(offset)
            bar:SetVisibleExtentPercentage(width > 0 and width / (width + range) or 1)
            bar:SetPanExtentPercentage(range > 0 and math.min(1, 30 / range) or 0)
            bar:SetScrollPercentage(range > 0 and offset / range or 0, ScrollBoxConstants.NoScrollInterpolation)
            bar:SetShown(range > 0)
            updating = false
        end
        bar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percentage)
            if not updating then scrollFrame:SetHorizontalScroll(percentage * scrollFrame:GetHorizontalScrollRange()) end
        end, scrollFrame)
        scrollFrame:HookScript("OnHorizontalScroll", UpdateHorizontal)
        scrollFrame:HookScript("OnScrollRangeChanged", UpdateHorizontal)
        scrollFrame:HookScript("OnSizeChanged", UpdateHorizontal)
        scrollFrame:HookScript("OnShow", UpdateHorizontal)
        local verticalWheel = scrollFrame:GetScript("OnMouseWheel")
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            if IsShiftKeyDown() and self:GetHorizontalScrollRange() > 0 then bar:ScrollStepInDirection(-delta)
            elseif verticalWheel then verticalWheel(self, delta) end
        end)
        bar:SetScript("OnMouseWheel", function(_, delta) bar:ScrollStepInDirection(-delta) end)
        UpdateHorizontal()
    end
    return scrollFrame
end

-- Preview docks sit beside, rather than inside, their page ScrollFrame.  Keep
-- wheel capture on the dock, but forward it only to the owner registered by
-- the currently mounted page.  The owner token prevents an old page teardown
-- from clearing a newer page's registration on a shared dock.
function EXUI:SetPreviewDockScrollOwner(dock, owner, scrollFrame)
    if not dock or type(dock.EnableMouseWheel) ~= "function" then return false end
    if scrollFrame then
        dock._exPreviewWheelOwner = owner
        dock._exPreviewWheelScrollFrame = scrollFrame
        if not dock._exPreviewWheelHooked then
            dock._exPreviewWheelHooked = true
            dock:HookScript("OnMouseWheel", function(self, delta)
                local target = self._exPreviewWheelScrollFrame
                if not target or not target:IsShown() then return end
                local handler = target:GetScript("OnMouseWheel")
                if handler then handler(target, delta) end
            end)
        end
        dock:EnableMouseWheel(true)
        return true
    end
    if owner == nil or dock._exPreviewWheelOwner == owner then
        dock._exPreviewWheelOwner = nil
        dock._exPreviewWheelScrollFrame = nil
        dock:EnableMouseWheel(false)
        return true
    end
    return false
end

function EXUI:CreateScrollBar(parent, name)
    local scrollBar = CreateFrame("EventFrame", name, parent, "MinimalScrollBar")
    self:ApplyModernScrollBar(scrollBar)
    return scrollBar
end

function EXUI:StyleDropdownMenuProxy(proxy)
    -- The menu compositor already reserves and positions its own scrollbar
    -- inside the proxy. Preserve that geometry while sharing the modern thumb
    -- hover/drag state; page ScrollFrame inset rules do not apply here.
    if proxy and proxy.ScrollBar then
        if not proxy._exCompactScrollLayout then
            proxy._exCompactScrollLayout = true
            hooksecurefunc(proxy, "InitScrollLayout", function(menu, childWidth, maxScrollExtent)
                local inset = menu:GetInset()
                menu.ScrollBar:SetWidth(GM.size.menuScrollBarWidth)
                menu.ScrollBox:SetPoint("BOTTOMRIGHT", -(inset.right + GM.size.menuScrollBarWidth), inset.bottom)
                menu:SetFixedSize(childWidth + inset.left + inset.right + GM.size.menuScrollBarWidth,
                    maxScrollExtent + inset.top + inset.bottom)
            end)
        end
        local previousWidth = proxy.ScrollBar:GetWidth()
        proxy.ScrollBar:SetWidth(GM.size.menuScrollBarWidth)
        self:ApplyModernScrollBar(proxy.ScrollBar, true)
        proxy.ScrollBar:GetTrack():SetWidth(GM.size.menuScrollThumbWidth)
        proxy.ScrollBar:GetThumb():SetWidth(GM.size.menuScrollThumbWidth)
        if proxy.ScrollBox:IsShown() and previousWidth ~= GM.size.menuScrollBarWidth then
            local inset = proxy:GetInset()
            proxy.ScrollBox:SetPoint("BOTTOMRIGHT", -(inset.right + GM.size.menuScrollBarWidth), inset.bottom)
            proxy:SetFixedSize(proxy:GetWidth() - previousWidth + GM.size.menuScrollBarWidth - 10, proxy:GetHeight())
        end
        local search = EXUI.DropdownFloatingSearchFrame
        local hasSearch = search and search:IsShown()
            and search.ownerDropdown and search.ownerDropdown.menu == proxy
        proxy.ScrollBar:ClearAllPoints()
        proxy.ScrollBar:SetPoint("TOPLEFT", proxy.ScrollBox, "TOPRIGHT", 0,
            hasSearch and -ExwindTools.GUIMetrics.size.menuSearchHeight or 0)
        proxy.ScrollBar:SetPoint("BOTTOMLEFT", proxy.ScrollBox, "BOTTOMRIGHT", 0, 0)
    end
    return proxy
end

local function PaintModernGridCard(frame)
    EXUI:SetControlSurface(frame, GM.radius.card, MC.raised,
        frame._exModernHover and MC.cardHoverBorder or MC.cardBorder)
end

if _G.MenuStyleMixin and _G.CreateFromMixins then
    EXUI.ModernMenuStyleMixin = CreateFromMixins(MenuStyleMixin)
    function EXUI.ModernMenuStyleMixin:Generate()
        local radius = GM.radius.popup
        local fillPieces, borderCorners, borderEdges = {}, {}, {}
        -- WoW 没有 CSS blur。三层向下扩散的低透明黑底近似
        -- 0 10px 28px rgba(0,0,0,.55)，只在菜单生成时创建，没有 OnUpdate。
        for shadowIndex, shadow in ipairs({
            { x = 14, top = 4, bottom = 20, alpha = 0.10 },
            { x = 9, top = 2, bottom = 14, alpha = 0.16 },
            { x = 5, top = 1, bottom = 9, alpha = 0.22 },
        }) do
            local texture = self:AttachTexture()
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetPoint("TOPLEFT", -shadow.x, shadow.top)
            texture:SetPoint("BOTTOMRIGHT", shadow.x, -shadow.bottom)
            texture:SetVertexColor(0, 0, 0, shadow.alpha)
            texture:SetDrawLayer("BACKGROUND", -8 + shadowIndex)
        end

        for row = 1, 3 do
            for col = 1, 3 do
                local texture = self:AttachTexture()
                MODERN.surfaceAtlas:ConfigureTexture(texture)
                texture:SetVertexColor(unpack(MC.popup))
                texture:SetDrawLayer("BACKGROUND", 0)
                fillPieces[#fillPieces + 1] = { texture = texture, row = row, col = col }
            end
        end
        for _, corner in ipairs({ { 1, 1 }, { 1, 3 }, { 3, 1 }, { 3, 3 } }) do
            local row, col = corner[1], corner[2]
            local texture = self:AttachTexture()
            MODERN.surfaceAtlas:ConfigureTexture(texture)
            texture:SetVertexColor(unpack(MC.popupBorder))
            texture:SetDrawLayer("BORDER", 0)
            borderCorners[#borderCorners + 1] = { texture = texture, row = row, col = col }
        end
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local texture = self:AttachTexture()
            MODERN.surfaceAtlas:ConfigureTexture(texture)
            MODERN.surfaceAtlas:SetSolidTexCoord(texture)
            texture:SetVertexColor(unpack(MC.popupBorder))
            texture:SetDrawLayer("BORDER", 1)
            borderEdges[#borderEdges + 1] = { texture = texture, side = side }
        end
        local function RefreshSurface()
            local metrics = MODERN.surfaceAtlas:GetMetrics(self, radius, 1)
            if not metrics then return end
            local pixel = metrics.pixel
            local width = metrics.widthPixels * pixel
            local height = metrics.heightPixels * pixel
            local corner = metrics.radiusPixels * pixel
            local thickness = metrics.strokePixels * pixel
            local xs = {
                metrics.offsetX,
                metrics.offsetX + corner,
                metrics.offsetX + width - corner,
                metrics.offsetX + width,
            }
            local ys = { 0, corner, height - corner, height }
            for _, piece in ipairs(fillPieces) do
                local texture = piece.texture
                texture:ClearAllPoints()
                if metrics.radiusPixels == 0 then
                    if piece.row == 2 and piece.col == 2 then
                        MODERN.surfaceAtlas:SetSolidTexCoord(texture)
                        texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                        texture:SetSize(width, height)
                        texture:Show()
                    else
                        texture:Hide()
                    end
                else
                    local pieceWidth = xs[piece.col + 1] - xs[piece.col]
                    local pieceHeight = ys[piece.row + 1] - ys[piece.row]
                    if piece.row ~= 2 and piece.col ~= 2 then
                        MODERN.surfaceAtlas:SetCornerTexCoord(texture,
                            metrics.radiusPixels, 0, piece.row, piece.col)
                    else
                        MODERN.surfaceAtlas:SetSolidTexCoord(texture)
                    end
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[piece.col], metrics.offsetY - ys[piece.row])
                    texture:SetSize(math.max(.001, pieceWidth), math.max(.001, pieceHeight))
                    texture:SetShown(pieceWidth > 0 and pieceHeight > 0)
                end
            end
            local degenerateBorder = metrics.widthPixels <= metrics.strokePixels * 2
                or metrics.heightPixels <= metrics.strokePixels * 2
            for _, piece in ipairs(borderCorners) do
                local texture = piece.texture
                texture:ClearAllPoints()
                if metrics.radiusPixels > 0 and not degenerateBorder then
                    MODERN.surfaceAtlas:SetCornerTexCoord(texture,
                        metrics.radiusPixels, metrics.strokePixels, piece.row, piece.col)
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[piece.col], metrics.offsetY - ys[piece.row])
                    texture:SetSize(corner, corner)
                    texture:Show()
                else
                    texture:Hide()
                end
            end
            for _, piece in ipairs(borderEdges) do
                local texture = piece.texture
                MODERN.surfaceAtlas:SetSolidTexCoord(texture)
                texture:ClearAllPoints()
                if degenerateBorder then
                    if piece.side == "TOP" then
                        texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX, metrics.offsetY)
                        texture:SetSize(width, height)
                        texture:Show()
                    else
                        texture:Hide()
                    end
                elseif piece.side == "TOP" then
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[2], metrics.offsetY)
                    texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    texture:SetShown(width > corner * 2)
                elseif piece.side == "BOTTOM" then
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", xs[2], metrics.offsetY - height + thickness)
                    texture:SetSize(math.max(.001, width - corner * 2), thickness)
                    texture:SetShown(width > corner * 2)
                elseif piece.side == "LEFT" then
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX, metrics.offsetY - corner)
                    texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    texture:SetShown(height > corner * 2)
                else
                    texture:SetPoint("TOPLEFT", self, "TOPLEFT", metrics.offsetX + width - thickness, metrics.offsetY - corner)
                    texture:SetSize(thickness, math.max(.001, height - corner * 2))
                    texture:SetShown(height > corner * 2)
                end
            end
        end
        self:HookScript("OnSizeChanged", RefreshSurface)
        self:HookScript("OnShow", RefreshSurface)
        -- Menu compositor proxies forbid CreateAnimationGroup. Use an attached,
        -- compositor-owned frame so its update script is cleaned up with the menu.
        local fadeDriver = self:AttachFrame("Frame")
        fadeDriver:SetSize(1, 1)
        fadeDriver:SetPoint("CENTER", self, "CENTER")
        fadeDriver:EnableMouse(false)
        self:HookScript("OnShow", function()
            local elapsedTime = 0
            self:SetAlpha(0)
            fadeDriver:SetScript("OnUpdate", function(driver, elapsed)
                elapsedTime = math.min(.10, elapsedTime + elapsed)
                self:SetAlpha(elapsedTime / .10)
                if elapsedTime >= .10 then driver:SetScript("OnUpdate", nil) end
            end)
            fadeDriver:Show()
        end)
        self:HookScript("OnHide", function()
            fadeDriver:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
        end)
        self:RegisterEvent("UI_SCALE_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        self:HookScript("OnEvent", RefreshSurface)
        RefreshSurface()
    end
    function EXUI.ModernMenuStyleMixin:GetInset()
        return { left = 6, top = 6, right = 6, bottom = 6 }
    end
    function EXUI.ModernMenuStyleMixin:GetChildExtentPadding()
        return { width = 0, height = 0 }
    end
end

function EXUI:ApplyControlAppearance(frame)
    if not frame then return frame end
    local kind = frame._gridType
    if kind == "GridButton" then
        ApplyModernButton(frame)
    elseif kind == "GridPicButton" then
        local highlight = frame.GetHighlightTexture and frame:GetHighlightTexture()
        if highlight then highlight:SetVertexColor(unpack(MC.lightBlue)) end
    elseif kind == "GridDropdown" or kind == "GridLSMDropdown" or kind == "GridMultiselect" then
        ApplyModernDropdown(frame)
        StyleModernTitle(frame.labelText, MC.text)
    elseif kind == "GridCheckbox" then
        ApplyModernCheckbox(frame)
    elseif kind == "GridSlider" then
        ApplyModernSlider(frame)
    elseif kind == "GridInput" then
        ApplyModernInput(frame)
        StyleModernTitle(frame.label, MC.text)
    elseif kind == "GridColorButton" then
        ApplyModernButton(frame)
        StyleModernTitle(frame.labelText or frame.label, MC.text)
    elseif kind == "GridHeader" then
        StyleModernTitle(frame.Title, MC.text)
        if frame.Line then frame.Line:SetColorTexture(unpack(MC.border)) end
    elseif kind == "GridSubheader" then
        StyleModernTitle(frame.text, MC.lightBlue)
    elseif kind == "GridDescription" then
        MODERN.ApplyTextRole(frame.text,
            frame._exSettingsTextRole == "tableText" and "title" or "hint")
    elseif kind == "GridCard" then
        if frame.EnableMouse then frame:EnableMouse(true) end
        if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
        if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
        -- 卡片的 OnEnter/OnLeave 也会被对象池清掉，按槽位记录后每次借用补装。
        HookControlScript(frame, "OnEnter", function(self)
            self._exModernHover = true
            PaintModernGridCard(self)
        end)
        HookControlScript(frame, "OnLeave", function(self)
            self._exModernHover = nil
            PaintModernGridCard(self)
        end)
        PaintModernGridCard(frame)
        for _, key in ipairs({
            "_exCardFrameGlow", "_exCardTopEdge", "_exCardRightEdge", "_exCardBottomEdge",
            "_exCardGlowHost", "_exCardTopGlow", "_exCardRightGlow", "_exCardBottomGlow",
        }) do
            if frame[key] then frame[key]:Hide() end
        end
        MODERN.ApplyTextRole(frame.Title, "cardTitle", MC.lightBlue)
        MODERN.ApplyTextRole(frame.Desc, "body", MC.muted)
        if frame.Accent then
            frame.Accent:ClearAllPoints()
            frame.Accent:SetWidth(4)
            frame.Accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.Accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame.Accent:SetColorTexture(unpack(MC.blue))
            frame.Accent:Hide()
        end
        if frame.TitleIcon then frame.TitleIcon:SetVertexColor(unpack(MC.blue)) end
    elseif frame._exMultilineInput == true and frame.editBox and frame.editBox ~= frame then
        ApplyModernInput(frame)
        StyleModernTitle(frame.label, MC.text)
    end
    return frame
end

function EXUI:RefreshControlAppearance(frame)
    return self:ApplyControlAppearance(frame)
end

-- [Helper] 防止 UI 污染的统一清理函数
local function CleanDropdownButton(button)
    button.playBtn = nil -- Attached controls belong to the compositor, not this row lease.
    if button.fontString then
        button.fontString:SetAlpha(1)
        button.fontString:SetFontObject(MODERN.menuFonts.control)
    end
    if button.lsmFontPreview and button.lsmFontPreview.fs then
        button.lsmFontPreview.fs:SetText("")
        button.lsmFontPreview.fs:SetFontObject("GameFontHighlight")
        button.lsmFontPreview:Hide()
    end
end

local function SetDropdownDisplayText(dropdown, text)
    local displayText = text or L["请选择..."]
    if dropdown.OverrideText then
        dropdown:OverrideText(displayText)
    else
        dropdown:SetText(displayText)
    end
end

local function NormalizeDropdownSearchText(text)
    if text == nil then
        return ""
    end

    local normalized = tostring(text)
    normalized = normalized:gsub("|c%x%x%x%x%x%x%x%x", "")
    normalized = normalized:gsub("|r", "")
    normalized = normalized:gsub("|T.-|t", " ")
    normalized = normalized:gsub("|A.-|a", " ")
    normalized = normalized:gsub("%s+", " ")
    normalized = strtrim(normalized)

    return string.lower(normalized)
end

local function GetDropdownLeafSearchText(item)
    if type(item) ~= "table" then
        return NormalizeDropdownSearchText(item)
    end

    local parts = {}
    if item.searchText then parts[#parts + 1] = item.searchText end
    if item.label then parts[#parts + 1] = item.label end
    if item.text and not item.isMenu then parts[#parts + 1] = item.text end
    if item[1] ~= nil then parts[#parts + 1] = item[1] end
    if item[2] ~= nil then parts[#parts + 1] = item[2] end

    return NormalizeDropdownSearchText(table.concat(parts, " "))
end

local function DropdownLeafMatchesQuery(item, needle)
    if needle == "" then
        return true
    end

    return GetDropdownLeafSearchText(item):find(needle, 1, true) ~= nil
end

local function CloneDropdownMenuBranch(item, filteredChildren)
    local cloned = {}
    for key, value in pairs(item) do
        cloned[key] = value
    end
    cloned.menu = filteredChildren
    return cloned
end

local function FilterDropdownItemsByNeedle(list, needle)
    if not list then
        return nil
    end

    local filtered = {}

    for _, item in ipairs(list) do
        if type(item) == "table" and item.isMenu then
            local groupText = NormalizeDropdownSearchText(item.searchText or item.text or item.label or item[1] or "")
            if groupText ~= "" and groupText:find(needle, 1, true) then
                filtered[#filtered + 1] = item
            else
                local filteredChildren = FilterDropdownItemsByNeedle(item.menu, needle)
                if filteredChildren and #filteredChildren > 0 then
                    filtered[#filtered + 1] = CloneDropdownMenuBranch(item, filteredChildren)
                end
            end
        elseif DropdownLeafMatchesQuery(item, needle) then
            filtered[#filtered + 1] = item
        end
    end

    return filtered
end

local function FilterDropdownItems(list, query)
    local needle = NormalizeDropdownSearchText(query)
    if needle == "" then
        return list
    end
    return FilterDropdownItemsByNeedle(list, needle)
end

local function PrepareDropdownMenuForRegeneration(dropdown)
    local menu = dropdown and dropdown.menu
    if not menu then
        return
    end

    if menu.ScrollBox and menu.ScrollBox.RemoveDataProvider then
        menu.ScrollBox:RemoveDataProvider()
    end

    if menu.ClearScrollLayout then
        menu:ClearScrollLayout()
    end
end

local function ResetDropdownMenuScroll(dropdown)
    local menu = dropdown and dropdown.menu
    local scrollBox = menu and menu.ScrollBox
    if scrollBox and scrollBox.ScrollToBegin then
        scrollBox:ScrollToBegin(ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation or true)
    end
end

local EnsureDropdownFloatingSearchFrame
local EXTERNAL_DROPDOWN_SEARCH_HEIGHT = GM.size.menuSearchHeight
local MODERN_MENU_ROW_HEIGHT = GM.size.menuRowHeight

local function AttachModernMenuSelectionMark(frame, enabled, selected)
    local anchor = frame.leftTexture1
    if not anchor or not frame.AttachTexture then return end

    -- 保留 Blizzard selection texture 的布局占位，但不显示原生黑/黄 radio、checkbox。
    -- 单选与多选统一使用青岚菜单原型的独立白色勾号；它不是 Checkbox 控件，
    -- 因此没有方框、底色或圆点，未选中时该预留列保持为空。
    anchor:SetAlpha(0)
    anchor:Hide()
    if frame.leftTexture2 then
        frame.leftTexture2:SetAlpha(0)
        frame.leftTexture2:Hide()
    end

    if selected then
        local check = frame:AttachTexture()
        check:SetTexture(MODERN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
        check:SetPoint("LEFT", frame, "LEFT", GM.space.menuRowPaddingX, 0)
        check:SetSize(GM.size.menuCheckSize, GM.size.menuCheckSize)
        check:SetDrawLayer("ARTWORK", 7)
        check:SetVertexColor(unpack(enabled and GC.menuCheck or MC.disabledText))
    end
end

-- 菜单行不能调用 SetControlSurface：它会清除 Blizzard_Menu 自己的状态贴图，
-- 并可能让单选圆点重新接管选中标记。这里直接在 compositor 行上附加一层
-- R4 九宫格，只负责 hover / selected 背景，不碰原生按钮状态与勾号。
local function AttachModernMenuRowHighlight(frame)
    if not frame.AttachTexture then return nil end

    local radius, insetX, insetY = 4, GM.space.menuRowHighlightInset, 0
    -- FillR4 的源图左右各有 6px、上下各有 23px 透明 padding。
    -- 菜单会把 attachment 的实体矩形纳入行尺寸测量，因此这里直接裁掉
    -- padding，只把实际可见的圆角 4px 区域锚在行框内部。
    local u = { 6 / 256, (6 + radius) / 256, (250 - radius) / 256, 250 / 256 }
    local v = { 23 / 128, (23 + radius) / 128, (105 - radius) / 128, 105 / 128 }
    local insideX, insideY = insetX + radius, insetY + radius
    local pieces = {}

    for row = 1, 3 do
        for col = 1, 3 do
            local texture = frame:AttachTexture()
            texture:SetTexture(MODERN_MEDIA .. "FillR4.tga", "CLAMP", "CLAMP", "LINEAR")
            texture:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
            texture:SetDrawLayer("BACKGROUND", 1)
            if row == 1 and col == 1 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insetX, -insetY)
                texture:SetSize(radius, radius)
            elseif row == 1 and col == 2 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insideX, -insetY)
                texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -insideX, -insetY)
                texture:SetHeight(radius)
            elseif row == 1 and col == 3 then
                texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -insetX, -insetY)
                texture:SetSize(radius, radius)
            elseif row == 2 and col == 1 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insetX, -insideY)
                texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insetX, insideY)
                texture:SetWidth(radius)
            elseif row == 2 and col == 2 then
                texture:SetPoint("TOPLEFT", frame, "TOPLEFT", insideX, -insideY)
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insideX, insideY)
            elseif row == 2 and col == 3 then
                texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -insetX, -insideY)
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insetX, insideY)
                texture:SetWidth(radius)
            elseif row == 3 and col == 1 then
                texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insetX, insetY)
                texture:SetSize(radius, radius)
            elseif row == 3 and col == 2 then
                texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", insideX, insetY)
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insideX, insetY)
                texture:SetHeight(radius)
            else
                texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insetX, insetY)
                texture:SetSize(radius, radius)
            end
            texture:Hide()
            pieces[#pieces + 1] = texture
        end
    end
    return pieces
end

local function RemoveNativeMenuHighlight(frame)
    local nativeHighlight = frame.highlight or (frame.GetHighlightTexture and frame:GetHighlightTexture())
    if nativeHighlight then
        -- 直接清掉黄色 UI-QuestTitleHighlight 的纹理来源；即使外部代码误调用
        -- Show()，这里也没有任何黄色像素可显示。区域几何仍保留给菜单测量。
        nativeHighlight:SetTexture(nil)
        nativeHighlight:SetAlpha(0)
        nativeHighlight:Hide()
    end
end

local PaintModernMenuSoundPreviewButton
local function PaintModernMenuRow(frame)
    RemoveNativeMenuHighlight(frame)

    local pieces = frame._exModernMenuHighlightPieces
    if not pieces then return end
    local useSelectedVisual = frame._exModernMenuSelected and not frame._exModernMenuHoverOnly
    local color = useSelectedVisual
        and (frame._exModernMenuHover and MC.menuSelectedHover or MC.menuSelected)
        or (frame._exModernMenuHover and MC.menuHover or nil)
    for _, texture in ipairs(pieces) do
        if color and frame._exModernMenuEnabled then
            texture:SetVertexColor(unpack(color))
            texture:Show()
        else
            texture:Hide()
        end
    end
    local fontString = frame.fontString or frame.Text
    if fontString then
        local textColor = not frame._exModernMenuEnabled and MC.disabledText
            or (useSelectedVisual and GC.menuSelectedText)
            or (frame._exModernMenuHover and MC.text)
            or MC.text
        fontString:SetTextColor(unpack(textColor))
    end
    if frame.playBtn and PaintModernMenuSoundPreviewButton then
        PaintModernMenuSoundPreviewButton(frame.playBtn)
    end
end

local function ModernMenuRowOnEnter(frame)
    frame._exModernMenuHover = true
    PaintModernMenuRow(frame)
end

local function ModernMenuRowOnLeave(frame)
    frame._exModernMenuHover = false
    PaintModernMenuRow(frame)
end

local function AttachModernMenuSubmenuArrow(frame, enabled, selected)
    local nativeArrow = frame.arrow
    if not nativeArrow or not frame.AttachTexture then return end
    nativeArrow:SetAlpha(0)

    local arrow = frame:AttachTexture()
    arrow:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
    arrow:SetPoint("CENTER", nativeArrow, "CENTER", 0, 0)
    arrow:SetSize(14, 14)
    arrow:SetDrawLayer("ARTWORK", 2)
    -- GlyphChevron 的默认方向向下；旋转四分之一圈后用于右侧子菜单指示。
    arrow:SetRotation(math.pi / 2)
    arrow:SetVertexColor(unpack(enabled and (selected and GC.menuSelectedText or MC.muted) or MC.disabledText))
end

-- Every menu row is still created and reclaimed by Blizzard_Menu.  This
-- initializer only restyles compositor-owned regions after the stock
-- initializer has built them; no global MenuVariants mutation and no
-- persistent proxy-frame textures are involved.
local function StyleModernMenuDescription(description, role)
    if not description or not description.AddInitializer then return description end
    description:AddInitializer(function(frame, elementDescription)
        if not frame then return end

        if frame._exPreviewDescription ~= elementDescription then frame.playBtn = nil end
        local enabled = not elementDescription.IsEnabled or elementDescription:IsEnabled()
        local selected = elementDescription.IsSelected and elementDescription:IsSelected() == true
        -- compositor:Clear() 已经把上一轮 AttachTexture 归还资源池；这里只丢弃
        -- 旧 Lua 引用，绝不能再 Hide() 它们，否则可能误伤本轮刚租出的勾号或图标。
        frame._exModernMenuHighlightPieces = nil
        frame._exModernMenuHover = frame.IsMouseMotionFocus and frame:IsMouseMotionFocus() or false
        local checkboxRole = role == "multiCheckbox"
        if (role == "button" or checkboxRole) and frame.SetHeight and frame.GetHeight then
            frame:SetHeight(MODERN_MENU_ROW_HEIGHT)
        end
        local fontString = frame.fontString or frame.Text
        if fontString then
            local color = not enabled and MC.disabledText
                or (role == "title" and MC.muted)
                or (selected and not checkboxRole and GC.menuSelectedText)
                or MC.text
            fontString:SetFontObject(role == "title" and MODERN.menuFonts.title or MODERN.menuFonts.control)
            fontString:SetTextColor(unpack(color))
            if fontString.SetShadowOffset then fontString:SetShadowOffset(0, 0) end
            if (role == "button" or checkboxRole) and fontString.ClearAllPoints and fontString.SetPoint then
                -- 文字左槽 = 行左内距 + 勾号 + 勾号到文字的间距；没有 selection 列的
                -- 普通按钮只留行左内距，不给空勾号预留整列。
                local slot = GM.space.menuRowPaddingX + GM.size.menuCheckSize + GM.space.menuRowSlotGap
                fontString:ClearAllPoints()
                fontString:SetPoint("LEFT", frame, "LEFT",
                    frame.leftTexture1 and slot or GM.space.menuRowPaddingX, 0)
                fontString:SetHeight(20)
                local left = frame.leftTexture1 and slot or GM.space.menuRowPaddingX
                local right = frame.playBtn and 42 or (frame.arrow and 28 or GM.space.menuRowPaddingX + 2)
                local textWidth = fontString:GetUnboundedStringWidth() or 0
                frame:SetWidth(math.max(120, left + textWidth + right))
            end
        end

        if role == "button" or checkboxRole then
            frame._exModernMenuSelected = selected
            frame._exModernMenuHoverOnly = checkboxRole
            frame._exModernMenuEnabled = enabled
            frame._exModernMenuHighlightPieces = AttachModernMenuRowHighlight(frame)
            -- Blizzard ButtonInitializer 每轮都会把这两个方法重设为显示/隐藏
            -- UI-QuestTitleHighlight。此 initializer 排在其后，直接替换为唯一的
            -- 共享 R4 painter；description 自己的 OnEnter/OnLeave、submenu 与 tooltip
            -- 由 HandleOnEnter/HandleOnLeave 的后续独立步骤执行，不会被跳过。
            frame.OnEnter = ModernMenuRowOnEnter
            frame.OnLeave = ModernMenuRowOnLeave
            PaintModernMenuRow(frame)
        else
            frame._exModernMenuSelected = false
            frame._exModernMenuHoverOnly = false
            frame._exModernMenuEnabled = false
        end

        AttachModernMenuSelectionMark(frame, enabled, selected)
        AttachModernMenuSubmenuArrow(frame, enabled, selected)
        if frame.divider then frame.divider:SetVertexColor(unpack(MC.headerDivider)) end
    end)
    return description
end

local function ModernMenuButton(description)
    return StyleModernMenuDescription(description, "button")
end

local function ModernMenuMultiselectCheckbox(description)
    return StyleModernMenuDescription(description, "multiCheckbox")
end

local function ModernMenuTitle(description)
    return StyleModernMenuDescription(description, "title")
end

local function ModernMenuDivider(description)
    return StyleModernMenuDescription(description, "divider")
end

local function ModernMenuThinDivider(description)
    if not description or not description.AddInitializer then return description end
    description:AddInitializer(function(frame)
        if not frame then return end
        if frame.divider then frame.divider:SetAlpha(0); frame.divider:Hide() end
        if not frame.AttachTexture then return end
        local line = frame:AttachTexture()
        line:SetTexture(MODERN_MEDIA .. "FillR4.tga", "CLAMP", "CLAMP", "LINEAR")
        line:SetTexCoord(.49, .51, .49, .51)
        line:SetPoint("LEFT", frame, "LEFT", 8, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
        scale = type(scale) == "number" and scale > 0 and scale or 1
        local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor
            and PixelUtil.GetPixelToUIUnitFactor() or 1
        factor = type(factor) == "number" and factor > 0 and factor or 1
        line:SetHeight(factor / scale)
        line:SetDrawLayer("ARTWORK", 1)
        line:SetVertexColor(unpack(MC.headerDivider))
    end)
    return description
end

-- =====================================================================
-- 播放指示器：所有"播放中"动画的唯一公共入口。
--
-- 待播时显示一个播放图标；播放中换成 5 条竖线，只有中间 3 条上下跳动
-- （两端两条短线固定，和原下拉试听按钮的观感一致）。
--
-- 它只负责外观：不播放/不停止任何声音，不读写配置，不注册业务通知。
-- 播放状态由调用方用 Start()/Stop() 告知；颜色由调用方用 SetColor() 决定
-- （默认取 GC.menuPreview* 一族）。尺寸全部读 GM.size/space.playIndicator*。
-- =====================================================================

-- 竖线静止高度：中间一条取 playIndicatorBarMaxHeight，两侧按 0.55、
-- 最外侧按 0.18 推算（11 -> 6 -> 2，与原下拉试听按钮同值）。
local function PlayIndicatorBarHeights()
    local tallest = GM.size.playIndicatorBarMaxHeight
    local side = math.max(1, math.floor(tallest * 0.55 + .5))
    local edge = math.max(1, math.floor(tallest * 0.18 + .5))
    return { edge, side, tallest, side, edge }
end

local function LayoutPlayIndicator(indicator)
    local heights = PlayIndicatorBarHeights()
    local width = GM.size.playIndicatorBarWidth
    local gap = GM.space.playIndicatorBarGap
    for index, bar in ipairs(indicator.bars) do
        bar:SetSize(width, heights[index])
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", indicator.owner, "CENTER", (index - 3) * gap, 0)
    end
    indicator.icon:SetSize(indicator.iconSize, indicator.iconSize)
    indicator.icon:ClearAllPoints()
    indicator.icon:SetPoint("CENTER", indicator.owner, "CENTER", 0, 0)
end

-- 按当前 playing / color 重画。静止时竖线回到静止高度并隐藏，图标显示。
local function RefreshPlayIndicator(indicator)
    local heights = PlayIndicatorBarHeights()
    local color = indicator.playing and (indicator.playingColor or GC.menuPreviewPlaying)
        or (indicator.color or GC.menuPreviewIcon)
    local playing = indicator.playing == true and indicator.released ~= true
    for index, bar in ipairs(indicator.bars) do
        bar:SetVertexColor(unpack(color))
        -- 只显示并跳动中间 3 条（两端两条只在静止高度表里留位，保持与原
        -- 下拉试听按钮一致）；不在播放中时整组隐藏，只留播放图标。
        bar:SetShown(playing and index > 1 and index < 5)
        if not playing then bar:SetHeight(heights[index]) end
    end
    indicator.icon:SetVertexColor(unpack(color))
    indicator.icon:SetShown(not playing and indicator.released ~= true)
end

function EXUI:AcquirePlayingIndicator(owner, options)
    if not owner then return nil end
    options = type(options) == "table" and options or {}
    -- 菜单行的 region 必须由 Blizzard_Menu 的 AttachTexture 管理，而它每次重建
    -- 菜单都会回收这些 region，所以传了 attachTexture 的调用方每次借用都重新
    -- attach 一组；普通 owner 自己 CreateTexture，只在第一次创建。
    local attachTexture = type(options.attachTexture) == "function" and options.attachTexture or nil
    local indicator = owner._exPlayIndicator
    if indicator and attachTexture then
        indicator.bars, indicator.icon = {}, nil
    end
    if not indicator or attachTexture then
        indicator = indicator or { owner = owner }
        indicator.bars = indicator.bars or {}
        local attach = attachTexture
            or function(host) return host:CreateTexture(nil, "ARTWORK", nil, 2) end
        for index = 1, 5 do
            local bar = attach(owner)
            bar:SetTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetDrawLayer("ARTWORK", 2)
            indicator.bars[index] = bar
        end
        indicator.icon = attach(owner)
        -- 实心三角（用户 2026-10-05）：Lucide 的 play 是线条版，播放入口统一用自绘的
        -- 实心版 play-solid，两者外廓一致，所以尺寸与位置都不用改。
        indicator.icon:SetTexture(self:GetIcon("play-solid"))
        indicator.icon:SetDrawLayer("ARTWORK", 2)
    end
    if not indicator.driver then
        -- 动画驱动。owner 隐藏时只停动画、不释放，下次借用仍是同一组 region。
        local driver = CreateFrame("Frame", nil, owner)
        driver:EnableMouse(false)
        driver:SetScript("OnHide", function() indicator:Stop() end)
        indicator.driver = driver

        function indicator:IsPlaying() return self.playing == true end

        function indicator:SetColor(color, playingColor)
            self.color = color
            if playingColor ~= nil then self.playingColor = playingColor end
            RefreshPlayIndicator(self)
        end

        function indicator:Start()
            self.released = nil
            self.playing = true
            RefreshPlayIndicator(self)
            -- 跳动区间按最高那条等比缩放：下限 3/11、摆幅 9/11（原下拉试听按钮
            -- 在 tallest = 11 时用的就是 3 + 9 * …，这里只是把它写成比例）。
            local tallest = GM.size.playIndicatorBarMaxHeight
            local base, swing = tallest * 3 / 11, tallest * 9 / 11
            self.driver:SetScript("OnUpdate", function()
                local time = GetTime()
                for index = 2, 4 do
                    local phase = (time + (index - 2) * .2) / .6 * math.pi * 2
                    self.bars[index]:SetHeight(math.max(1,
                        base + swing * (.5 + .5 * math.sin(phase))))
                end
            end)
        end

        function indicator:Stop()
            self.driver:SetScript("OnUpdate", nil)
            self.playing = nil
            RefreshPlayIndicator(self)
        end

        function indicator:Release()
            self.driver:SetScript("OnUpdate", nil)
            self.playing = nil
            self.released = true
            self.color, self.playingColor = nil, nil
            for _, bar in ipairs(self.bars) do bar:Hide() end
            self.icon:Hide()
        end

        owner._exPlayIndicator = indicator
    end
    indicator.released = nil
    indicator.iconSize = tonumber(options.iconSize) or GM.size.playIndicatorIconSize
    indicator.color = options.color
    indicator.playingColor = options.playingColor
    LayoutPlayIndicator(indicator)
    RefreshPlayIndicator(indicator)
    return indicator
end

-- 归还对象池、或 owner 不再充当播放入口时调用；之后 region 保持隐藏，
-- 下次 Acquire 复用同一组 region 与驱动。
function EXUI:ReleasePlayingIndicator(owner)
    local indicator = owner and owner._exPlayIndicator
    if not indicator then return end
    indicator:Release()
end

local function IsModernMenuSoundPreviewPlaying(handle)
    if not handle then return false end
    if _G.C_Sound and type(_G.C_Sound.IsPlaying) == "function" then
        return _G.C_Sound.IsPlaying(handle) == true
    end
    -- 无 IsPlaying 的旧客户端仍可在第二次点击时用保存的 handle 停止。
    return true
end

local function StopModernMenuSoundPreview()
    local state = EXUI._modernMenuSoundPreview
    if not state then return end
    if state.handle and type(_G.StopSound) == "function" then
        _G.StopSound(state.handle)
    end
    local button = state.button
    state.handle, state.path = nil, nil
    state.button = nil
    if button then
        button:SetScript("OnUpdate", nil)
        PaintModernMenuSoundPreviewButton(button)
    end
end

PaintModernMenuSoundPreviewButton = function(button)
    -- 池化按钮可能曾被借作试听按钮；其音波条和 hook 会随 Frame 保留。
    -- 只有当前租约明确处于试听外观时才绘制，否则释放指示器，避免残留到侧栏等其他用途。
    local indicator = button._exPlayIndicator
    if not button._exSoundPreviewActive then
        if indicator then indicator:Release() end
        return
    end
    if not indicator then return end
    local enabled = not button.IsEnabled or button:IsEnabled()
    local hover = enabled and button._exModernHover
    local row = button:GetParent()
    local selected = row and row._exModernMenuSelected == true
    local rowHover = row and row._exModernMenuHover == true
    local state = EXUI._modernMenuSoundPreview
    local playing = button._exTrackedSoundPlaying or (state and state.button == button and state.handle
        and IsModernMenuSoundPreviewPlaying(state.handle))
    -- 试听这边的"是否在播放"真源仍然是声音句柄；颜色在这里按菜单行状态决定，
    -- 竖线跳动与图标显隐交给公共播放指示器，不再在这里自己画一套。
    local color = not enabled and MC.disabledText
        or selected and (hover and GC.menuPreviewSelectedHover or GC.menuPreviewSelected)
        or hover and GC.menuPreviewIconHover
        or rowHover and GC.menuPreviewIconRow
        or GC.menuPreviewIcon
    indicator:SetColor(color, enabled and GC.menuPreviewPlaying or MC.disabledText)
    if playing and not indicator:IsPlaying() then
        indicator:Start()
    elseif not playing and indicator:IsPlaying() then
        indicator:Stop()
    end
end


-- SharedMedia-style feedback for ordinary preview buttons. Playback remains
-- owned by the caller; its third return value is the actual sound handle.
function EXUI:ApplySoundPreviewAppearance(button)
    if not button then return end
    -- 播放图标与跳动竖线由公共播放指示器创建，这里只补试听按钮自己的 hook。
    self:AcquirePlayingIndicator(button)
    if not button._exSoundPreviewHooks then
        button._exSoundPreviewHooks = true
        button:HookScript("OnEnter", function(self) self._exModernHover = true; PaintModernMenuSoundPreviewButton(self) end)
        button:HookScript("OnLeave", function(self) self._exModernHover = nil; PaintModernMenuSoundPreviewButton(self) end)
        button:HookScript("OnEnable", PaintModernMenuSoundPreviewButton)
        button:HookScript("OnDisable", PaintModernMenuSoundPreviewButton)
        button:HookScript("OnHide", function(self)
            if self._exPreviewDriver then self._exPreviewDriver:Stop() end
            -- 调用方自己驱动的播放态（SetSoundPreviewPlaying）没有声音句柄，
            -- 隐藏时由这里收回，下次显示是干净的待播外观。
            if self._exTrackedSoundPlaying then
                self._exTrackedSoundPlaying = nil
                PaintModernMenuSoundPreviewButton(self)
            end
        end)
    end
    button:SetText("")
    -- 本租约第一次套试听外观：清掉上一租约可能留下的播放态。重排／重画时
    -- `_exSoundPreviewActive` 已经是 true，不会打断正在播放的那一次。
    if not button._exSoundPreviewActive then button._exTrackedSoundPlaying = nil end
    button._exSoundPreviewActive = true
    PaintModernMenuSoundPreviewButton(button)
end

-- 调用方自己管理播放时（例如 C_Timer 排出来的序列预览：没有单一声音句柄，
-- 用不上 RunSoundPreview）用这个入口把播放状态告给试听按钮。
-- 它只改外观：不播放、不停止、不查询任何声音。
-- 释放合同：按钮隐藏、归还对象池、或本租约重新套试听外观时状态自动清掉；
-- 调用方自己的播放结束／被打断时必须再调用一次 playing=false。
function EXUI:SetSoundPreviewPlaying(button, playing)
    if not button then return end
    if playing == true then
        -- 还没套过试听外观的按钮（指示器与 hook 都不在）先补齐，再进入播放态。
        if not button._exSoundPreviewActive then self:ApplySoundPreviewAppearance(button) end
        button._exTrackedSoundPlaying = true
    else
        button._exTrackedSoundPlaying = nil
        if not button._exSoundPreviewActive then return end
    end
    PaintModernMenuSoundPreviewButton(button)
end

function EXUI:RunSoundPreview(button, play, isTTS)
    if not button then return play() end
    self:ApplySoundPreviewAppearance(button)
    local driver = button._exPreviewDriver
    if not driver then
        driver = CreateFrame("Frame", nil, button)
        button._exPreviewDriver = driver
        -- 声音句柄由本驱动在 play() 返回时接管。Stop 先让仍在播放的声音真正停下，再清引用；
        -- 声音自然播完（IsPlaying 已为 false）时不再调用 StopSound。
        -- 再次试听、按钮隐藏/归还池（OnHide 钩子）都经过这里。
        function driver:Stop()
            local handle = self.handle
            self:SetScript("OnUpdate", nil)
            self:UnregisterAllEvents()
            self.handle, self.utterance, self.capturing = nil, nil, nil
            if handle and IsModernMenuSoundPreviewPlaying(handle) then StopSound(handle) end
            button._exTrackedSoundPlaying = nil
            PaintModernMenuSoundPreviewButton(button)
        end
        -- 竖线跳动由公共播放指示器负责（Paint 看到 playing 就 Start）；本驱动的
        -- OnUpdate 只剩一件事：声音自然播完后把状态收回去。
        function driver:Animate()
            button._exTrackedSoundPlaying = true
            PaintModernMenuSoundPreviewButton(button)
            self:SetScript("OnUpdate", function(frame)
                if frame.handle and not IsModernMenuSoundPreviewPlaying(frame.handle) then frame:Stop() end
            end)
        end
        driver:SetScript("OnEvent", function(frame, event, id, utterance)
            if event == "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE" then
                if frame.capturing then frame.utterance = utterance end
            elseif event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
                if frame.capturing then frame.utterance = id end
                if frame.utterance == id then frame:Animate() end
            elseif frame.utterance == id then
                frame:Stop()
            end
        end)
    end
    driver:Stop()
    if isTTS then
        driver:RegisterEvent("VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE")
        driver:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
        driver:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED")
        driver:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED")
        driver.capturing = true
    end
    local called, ok, reason, handle = pcall(play)
    driver.capturing = nil
    if not called then driver:Stop(); error(ok) end
    if handle then
        driver.handle = handle
        driver:Animate()
    elseif not isTTS or not driver.utterance then
        driver:Stop()
    end
    return ok, reason, handle
end

local function AttachModernMenuSoundPreviewButton(row, path, description)
    local playButton = MenuTemplates.AttachBasicButton(row, MODERN_MENU_ROW_HEIGHT, MODERN_MENU_ROW_HEIGHT)
    playButton:SetPoint("RIGHT", 0, 0)
    playButton._exSoundPath = path
    for _, method in ipairs({ "GetNormalTexture", "GetHighlightTexture", "GetPushedTexture" }) do
        local texture = playButton[method] and playButton[method](playButton)
        if texture then texture:SetAlpha(0) end
    end

    -- 菜单行的 region 必须由 Blizzard_Menu 的 AttachTexture 管理，所以这里把
    -- 创建方式交给公共播放指示器的 attachTexture；画法与其他播放入口同一套。
    playButton._exSoundPreviewActive = true
    EXUI:AcquirePlayingIndicator(playButton, {
        attachTexture = function(host) return host:AttachTexture() end,
    })

    playButton:SetScript("OnEnter", function(self)
        self._exModernHover = true
        PaintModernMenuSoundPreviewButton(self)
    end)
    playButton:SetScript("OnLeave", function(self)
        self._exModernHover = false
        PaintModernMenuSoundPreviewButton(self)
    end)
    if not playButton._exModernSoundHideHook then
        playButton._exModernSoundHideHook = true
        playButton:HookScript("OnHide", function(self)
            local state = EXUI._modernMenuSoundPreview
            if state and state.button == self then StopModernMenuSoundPreview() end
        end)
    end
    if playButton.SetEnabled then playButton:SetEnabled(type(path) == "function" or (type(path) == "string" and path ~= "")) end
    if MenuTemplates.SetUtilityButtonTooltipText then
        MenuTemplates.SetUtilityButtonTooltipText(playButton, L["试听 / 停止"])
    end
    MenuTemplates.SetUtilityButtonClickHandler(playButton, function()
        local path = type(path) == "function" and path() or path
        local state = EXUI._modernMenuSoundPreview or {}
        EXUI._modernMenuSoundPreview = state
        if state.handle and not IsModernMenuSoundPreviewPlaying(state.handle) then
            state.handle, state.path = nil, nil
        end

        if state.handle then
            local wasSameSound = state.path == path
            StopModernMenuSoundPreview()
            if wasSameSound then
                PaintModernMenuSoundPreviewButton(playButton)
                return
            end
        end

        if type(path) == "string" and path ~= "" then
            local willPlay, soundHandle = PlaySoundFile(path, "Master")
            if willPlay ~= false and soundHandle then
                state.path, state.handle = path, soundHandle
                state.button = playButton
                -- 竖线跳动归公共播放指示器；这个 OnUpdate 只负责声音播完后收状态。
                playButton:SetScript("OnUpdate", function(self)
                    local current = EXUI._modernMenuSoundPreview
                    if not current or current.button ~= self or not current.handle
                        or not IsModernMenuSoundPreviewPlaying(current.handle) then
                        StopModernMenuSoundPreview()
                    end
                end)
            end
        end
        PaintModernMenuSoundPreviewButton(playButton)
    end)
    row._exPreviewDescription = description
    row.playBtn = playButton
    PaintModernMenuSoundPreviewButton(playButton)
    return playButton
end

local function AddSearchSpacer(rootDescription)
    local spacer = ModernMenuButton(rootDescription:CreateButton(""))
    spacer:AddInitializer(function(button)
        if not button then return end
        button:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
        button:SetAlpha(0)
    end)
end

local function ResolveDropdownSearchEnabled(searchConfig)
    if type(searchConfig) == "table" then
        if searchConfig.searchable ~= nil then
            return searchConfig.searchable == true
        end
        if searchConfig.search ~= nil then
            return searchConfig.search == true
        end
    elseif searchConfig ~= nil then
        return searchConfig == true
    end

    return true
end

local function SetDropdownDefaultMenuAnchor(dropdown)
    if dropdown and dropdown.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4))
    end
end

local function EnsureDropdownSearchHooks(dropdown)
    if dropdown._exSearchHooksInstalled or not dropdown.RegisterCallback or not DropdownButtonMixin then
        return
    end

    dropdown._exSearchHooksInstalled = true
    dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, function(owner)
        local target = owner
        if type(target) ~= "table" then
            target = dropdown
        end

        if target._externalSearchEnabled then
            EnsureDropdownFloatingSearchFrame():ShowForDropdown(target)
        end
    end)
    dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, function(owner, menu, closeReason)
        local target = owner
        if type(target) ~= "table" then
            target = dropdown
        end

        EnsureDropdownFloatingSearchFrame():HideForDropdown(target)
        target._searchText = nil
    end)
end

local function RefreshDropdownSearch(dropdown, newText)
    if not dropdown or not dropdown.GenerateMenu then
        return
    end

    local trimmed = strtrim(newText or "")
    local normalizedText = trimmed ~= "" and trimmed or nil
    if dropdown._searchText == normalizedText then
        return
    end

    dropdown._searchText = normalizedText
    PrepareDropdownMenuForRegeneration(dropdown)
    dropdown:GenerateMenu()
    ResetDropdownMenuScroll(dropdown)
end

EnsureDropdownFloatingSearchFrame = function()
    if EXUI.DropdownFloatingSearchFrame then
        return EXUI.DropdownFloatingSearchFrame
    end

    local frame = CreateFrame("Frame", "ExwindDropdownFloatingSearchFrame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(300)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetSize(220, EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
    frame:Hide()
    -- 这个 frame 只承载输入框并覆盖菜单首行占位，本身完全透明。
    -- 唯一外壳是 Blizzard_Menu 的 popup；搜索区不再另画第二层 panel。
    local searchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    searchBox:SetPoint("TOPLEFT", 8, -6)
    searchBox:SetPoint("BOTTOMRIGHT", -8, 6)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(64)
    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -5, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:GetNormalTexture():SetVertexColor(unpack(MC.muted))
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:GetHighlightTexture():SetVertexColor(unpack(MC.lightBlue))
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:SetFocus()
    end)
    searchBox.ClearButton = clearBtn
    frame.SearchBox = searchBox
    searchBox._exModernInputFocusBorder = GC.inputFocusBorder
    searchBox._exModernInputIdleFill = MC.popupSearch
    searchBox._exModernInputActiveFill = MC.popupSearch
    searchBox._exModernInputHoverBorder = MC.popupSearchBorder
    EXUI:ApplySearchBoxAppearance(searchBox)

    local divider = EXUI:CreateVisualTexture(frame, EXBORDERFRAME)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 0)
    divider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(MC.popupDivider))
    frame.Divider = divider

    function frame:AnchorToDropdown(dropdown)
        self:ClearAllPoints()
        local menu = dropdown and dropdown.menu
        local opensUpward = false
        if menu and menu.GetBottom and dropdown and dropdown.GetTop then
            local menuBottom = menu:GetBottom()
            local dropdownTop = dropdown:GetTop()
            if menuBottom and dropdownTop and menuBottom >= (dropdownTop - 2) then
                opensUpward = true
            end
        end

        self:SetParent(UIParent)
        if menu and menu.GetTop then
            -- 搜索承载层直接跟随 popup 的左右边界；不要再给它独立最小宽度，
            -- 否则窄菜单会被搜索框从两侧撑出去。
            self:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
            self:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)
        elseif opensUpward then
            self:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 4)
            self:SetWidth(math.max(dropdown:GetWidth() or 0, 1))
        else
            self:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4)
            self:SetWidth(math.max(dropdown:GetWidth() or 0, 1))
        end
        if menu and menu.GetFrameStrata and menu.GetFrameLevel then
            self:SetFrameStrata(menu:GetFrameStrata())
            self:SetFrameLevel(menu:GetFrameLevel() + 50)
        elseif dropdown and dropdown.GetFrameStrata and dropdown.GetFrameLevel then
            self:SetFrameStrata(dropdown:GetFrameStrata())
            self:SetFrameLevel(dropdown:GetFrameLevel() + 600)
        end
    end

    function frame:ShowForDropdown(dropdown)
        if not dropdown then
            return
        end

        self.ownerDropdown = dropdown
        self:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
        self.SearchBox:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT - 12)
        local menu = dropdown and dropdown.menu
        self.SearchBox:ClearFocus()
        PaintModernInput(self.SearchBox, self.SearchBox)
        self:AnchorToDropdown(dropdown)
        self:Show()
        EXUI:StyleDropdownMenuProxy(menu)
        self._suppressSearchChange = true
        self.SearchBox:SetText(dropdown._searchText or "")
        self._suppressSearchChange = nil
        self.SearchBox:SetCursorPosition(string.len(self.SearchBox:GetText() or ""))
        C_Timer.After(0, function()
            if self:IsShown() and self.ownerDropdown == dropdown then
                self:AnchorToDropdown(dropdown)
            end
        end)
    end

    function frame:HideForDropdown(dropdown)
        if dropdown and self.ownerDropdown ~= dropdown then
            return
        end

        local menu = self.ownerDropdown and self.ownerDropdown.menu
        self.ownerDropdown = nil
        self:SetParent(UIParent)
        self.SearchBox:ClearFocus()
        self.SearchBox:SetText("")
        self:Hide()
        EXUI:StyleDropdownMenuProxy(menu)
    end

    frame.SearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if self.Instructions then self.Instructions:SetShown(text == "") end
        if self.ClearButton then self.ClearButton:SetShown(text ~= "") end
        if frame._suppressSearchChange then return end
        local dropdown = frame.ownerDropdown
        if dropdown then
            RefreshDropdownSearch(dropdown, self:GetText())
            C_Timer.After(0, function()
                if frame:IsShown() and frame.ownerDropdown == dropdown and dropdown.menu and dropdown.menu:IsShown() then
                    frame:AnchorToDropdown(dropdown)
                    self:SetFocus()
                    self:SetCursorPosition(string.len(self:GetText() or ""))
                end
            end)
        end
    end)
    frame.SearchBox:SetScript("OnEditFocusLost", function(self)
        if self.Instructions then self.Instructions:SetShown((self:GetText() or "") == "") end
    end)
    frame.SearchBox:SetScript("OnEditFocusGained", function(self)
        if self.Instructions then self.Instructions:Hide() end
    end)
    frame.SearchBox:SetScript("OnEscapePressed", function(self)
        local dropdown = frame.ownerDropdown
        self:ClearFocus()
        if dropdown and dropdown.CloseMenu then
            dropdown:CloseMenu()
        else
            frame:HideForDropdown()
        end
    end)
    frame.SearchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    EXUI.DropdownFloatingSearchFrame = frame
    return frame
end

local function ConfigureDropdownExternalSearch(dropdown)
    if not dropdown then
        return
    end

    dropdown._externalSearchEnabled = true
    EnsureDropdownSearchHooks(dropdown)

    if dropdown.SetMenuAnchor and AnchorUtil and AnchorUtil.CreateAnchor then
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4))
    end
end

local function SetDropdownSearchEnabled(dropdown, searchConfig)
    if not dropdown then
        return
    end

    local enabled = ResolveDropdownSearchEnabled(searchConfig)
    dropdown._externalSearchEnabled = enabled
    dropdown._searchText = nil

    if enabled then
        ConfigureDropdownExternalSearch(dropdown)
    else
        local searchFrame = EXUI.DropdownFloatingSearchFrame
        if searchFrame then
            searchFrame:HideForDropdown(dropdown)
        end
        EnsureDropdownSearchHooks(dropdown)
        SetDropdownDefaultMenuAnchor(dropdown)
    end
end

-- =========================================================
-- [Core] 统一标签样式更新 (ExwindGrid 编辑器专用)
-- =========================================================
function EXUI:UpdateLabelStyle(widget, size, pos)
    if not widget then return end

    -- `size` remains accepted for configuration compatibility, but typography
    -- is owned exclusively by ApplyControlAppearance's semantic text roles.
    local label = widget.labelText or widget.label or widget.Title
    if not label then return end

    widget._exLabel = label
    local gType = widget._gridType and widget._gridType:lower() or ""

    -- Shared composite controls own their label geometry as well as typography.
    if gType:find("fontgroup") or gType:find("header") or gType:find("soundgroup") or gType:find("modulecommonsettings")
        or gType:find("description") or gType:find("card") or gType:find("checkbox") or gType:find("slider") then
        return
    end

    -- [Fix] 对于特定的组组件，不碰位置
    if gType == "fontgroup" or gType == "gridfontgroup" or gType == "header" or gType == "gridheader"
        or gType == "soundgroup" or gType == "subheader" or gType == "gridsubheader" or gType == "icongroup" or gType == "glow_settings"
        or gType == "color" or gType == "colorbutton" or gType == "gridcolorbutton"
        or gType == "description" or gType == "griddescription" or gType == "card" or gType == "gridcard" then
        return
    end

    -- Grid controls may still choose label placement and wrapping.
    if not pos then pos = "top" end
    label:ClearAllPoints()

    if pos == "left" then
        label:SetPoint("RIGHT", widget, "LEFT", -5, 0)
        label:SetJustifyH("RIGHT")
    elseif pos == "right" then
        label:SetPoint("LEFT", widget, "RIGHT", 5, 0)
        label:SetJustifyH("LEFT")
    else -- top
        label:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 3)
        if widget._exLabelWrap == true then
            label:SetPoint("BOTTOMRIGHT", widget, "TOPRIGHT", 0, 3)
        end
        label:SetJustifyH("LEFT")
    end
    label:SetWordWrap(widget._exLabelWrap == true)
    if label.SetMaxLines then
        label:SetMaxLines(tonumber(widget._exLabelMaxLines) or 0)
    end
end

-- =========================================================
-- 0. 通用单选下拉菜单 (Generic Dropdown) - [v4.3.1] 支持池化
-- items 格式: { "选项1", "选项2" } 或 { {"显示文字", "实际值"}, ... }
-- =========================================================
function EXUI:CreateDropdown(parent, width, label, items, currentValue, onSelect, searchConfig)
    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 从池获取
        dropdown = self:AcquireControl("GridDropdown", parent)
    else
        -- 兜底：传统创建
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        if dropdown.Text then
            dropdown.Text:ClearAllPoints()
            dropdown.Text:SetPoint("LEFT", 8, 0)
            dropdown.Text:SetPoint("RIGHT", dropdown.Arrow, "LEFT", -2, 0)
        end
        if dropdown.Arrow then
            dropdown.Arrow:ClearAllPoints()
            dropdown.Arrow:SetPoint("RIGHT", -2, 0)
        end
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    -- GridDropdown 来自对象池。上一次页面可能为“未启用条件”调用过 Disable()；
    -- 每次借用必须先恢复，当前调用方若确需禁用会在创建后自行 Disable()。
    if dropdown.Enable then
        dropdown:Enable()
    end
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2 Fix] 将状态挂载到 Self，避免 SetupMenu 闭包捕获导致内存泄漏
    dropdown._currentValue = currentValue
    dropdown._onSelect = onSelect
    dropdown._items = items
    dropdown._previewPath = type(searchConfig) == "table" and searchConfig.previewPath or nil
    SetDropdownSearchEnabled(dropdown, searchConfig)

    -- [Fix] 递归查找选定值的显示文本
    local function GetEntry(val, list)
        for _, item in ipairs(list or items) do
            if type(item) == "table" then
                if item.isMenu then
                    local found, v = GetEntry(val, item.menu)
                    if found ~= L["请选择..."] then return found, v end
                elseif item[2] == val or (tonumber(item[2]) and tonumber(item[2]) == tonumber(val)) then
                    return item[1], item[2]
                end
            else
                if item == val or (tonumber(item) and tonumber(item) == tonumber(val)) then return item, item end
            end
        end
        return L["请选择..."], nil
    end

    local initialText = GetEntry(currentValue)
    SetDropdownDisplayText(dropdown, initialText)

    -- [Fix] 使用 Self 引用构建菜单
    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:AddMenuAcquiredCallback(function(proxy)
            local parent = proxy:GetParent()
            local parentScale = parent and parent:GetEffectiveScale() or 1
            local ownerScale = self:GetEffectiveScale()
            if parentScale > 0 and ownerScale > 0 then proxy:SetScale(ownerScale / parentScale) end
            EXUI:StyleDropdownMenuProxy(proxy)
        end)
        rootDescription:SetScrollMode(400)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) end

        local function BuildMenu(rootDesc, list)
            if not list then return end -- [Fix] 防止复用初始化间隙导致的 nil 报错
            for _, item in ipairs(list) do
                if type(item) == "table" and item.isMenu then
                    local subMenu = ModernMenuButton(rootDesc:CreateButton(item.text, function() end))
                    BuildMenu(subMenu, item.menu)
                else
                    local text, value
                    if type(item) == "table" then
                        text, value = item[1], item[2]
                    else
                        text, value = item, item
                    end

                    local entry = rootDesc:CreateRadio(text,
                        function()
                            -- [Fix] 必须在闭包内动态获取 self._currentValue，否则状态会死锁
                            return (self._currentValue == value) or (tostring(self._currentValue) == tostring(value))
                        end,
                        function()
                            self._currentValue = value
                            SetDropdownDisplayText(self, text)
                            if self._onSelect then self._onSelect(value, text) end
                        end
                    )
                    if type(self._previewPath) == "function" then
                        entry:AddInitializer(function(row, description)
                            AttachModernMenuSoundPreviewButton(row, function() return self._previewPath(value) end, description)
                        end)
                    end
                    ModernMenuButton(entry)
                end
            end
        end

        local filteredItems = FilterDropdownItems(self._items, self._searchText)
        if filteredItems and #filteredItems > 0 then
            BuildMenu(rootDescription, filteredItems)
        else
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
    end)

    return dropdown
end

-- =========================================================
-- 1. 字体下拉菜单 (LSM Font) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateLSMDropdown(parent, mediaType, width, label, currentValue, onSelect, searchConfig)
    -- [Fix] 兼容性处理
    if type(currentValue) == "function" and onSelect == nil then
        onSelect = currentValue
        currentValue = nil
    end

    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 复用 GridLSMDropdown 池
        dropdown = self:AcquireControl("GridLSMDropdown", parent)
    else
        -- 兜底
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridLSMDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    -- GridDropdown 来自对象池。上一次页面可能为“未启用条件”调用过 Disable()；
    -- 每次借用必须先恢复，当前调用方若确需禁用会在创建后自行 Disable()。
    if dropdown.Enable then
        dropdown:Enable()
    end
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2 Fix] 将状态挂载到 Self
    dropdown._selectedValue = currentValue or LSM:GetDefault(mediaType)
    dropdown._onSelect = onSelect
    dropdown._mediaType = mediaType
    SetDropdownSearchEnabled(dropdown, searchConfig)

    SetDropdownDisplayText(dropdown, dropdown._selectedValue == "默认" and L["默认"] or dropdown._selectedValue)

    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:AddMenuAcquiredCallback(function(proxy)
            local parent = proxy:GetParent()
            local parentScale = parent and parent:GetEffectiveScale() or 1
            local ownerScale = self:GetEffectiveScale()
            if parentScale > 0 and ownerScale > 0 then proxy:SetScale(ownerScale / parentScale) end
            EXUI:StyleDropdownMenuProxy(proxy)
        end)
        if not self._mediaType then return end -- [Fix] 防止复用时 nil 报错
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(L["选择"] .. (self._mediaType == "font" and L["字体"] or self._mediaType))) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable(self._mediaType)
        local sortedKeys = LSM:List(self._mediaType)
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false

        for _, key in ipairs(sortedKeys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                local path = list[key]
                hasMatch = true
                ModernMenuButton(rootDescription:CreateRadio(key == "默认" and L["默认"] or key, function() return self._selectedValue == key end, function()
                    self._selectedValue = key
                    SetDropdownDisplayText(self, key == "默认" and L["默认"] or key)
                    if self._onSelect then self._onSelect(key, path) end
                end))
            end
        end

        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
    end)
    return dropdown
end

-- =========================================================
-- 2. 材质下拉菜单 (LSM Texture/Border/Background/Statusbar) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateLSMTextureDropdown(parent, mediaType, width, label, currentValue, onSelect, searchConfig)
    -- [Fix] 兼容性处理
    if type(currentValue) == "function" and onSelect == nil then
        onSelect = currentValue
        currentValue = nil
    end

    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 复用 GridLSMDropdown 池
        dropdown = self:AcquireControl("GridLSMDropdown", parent)
    else
        -- 兜底
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridLSMDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    local selectedValue = currentValue or LSM:GetDefault(mediaType)
    -- 如果所选 key 在 LSM 中不存在（如用户未安装 SharedMedia），fallback 到 "Solid"
    if selectedValue and not LSM:HashTable(mediaType)[selectedValue] then
        selectedValue = LSM:HashTable(mediaType)["Solid"] and "Solid" or LSM:GetDefault(mediaType)
    end
    dropdown._selectedValue = selectedValue
    dropdown._onSelect = onSelect
    dropdown._mediaType = mediaType
    SetDropdownSearchEnabled(dropdown, searchConfig)
    SetDropdownDisplayText(dropdown, selectedValue or "None")

    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:AddMenuAcquiredCallback(function(proxy)
            local parent = proxy:GetParent()
            local parentScale = parent and parent:GetEffectiveScale() or 1
            local ownerScale = self:GetEffectiveScale()
            if parentScale > 0 and ownerScale > 0 then proxy:SetScale(ownerScale / parentScale) end
            EXUI:StyleDropdownMenuProxy(proxy)
        end)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(L["选择材质"])) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable(self._mediaType)
        local sortedKeys = LSM:List(self._mediaType)
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false

        for _, key in ipairs(sortedKeys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                local path = list[key]
                local shortKey = #key > 24 and (string.sub(key, 1, 23) .. "..") or key

                local displayText = shortKey
                if path then
                    if self._mediaType == "statusbar" then
                        displayText = string.format("|T%s:14:100:0:0:64:64:5:59:5:59|t %s", path, shortKey)
                    elseif self._mediaType == "background" then
                        displayText = string.format("|T%s:20:20:0:0:64:64:5:59:5:59|t %s", path, shortKey)
                    elseif self._mediaType == "border" then
                        -- 边框材质通常需要完整显示，不应用内裁剪
                        displayText = string.format("|T%s:14:100|t %s", path, shortKey)
                    else
                        displayText = string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t %s", path, shortKey)
                    end
                end

                hasMatch = true
                local btn = rootDescription:CreateRadio(displayText,
                    function() return self._selectedValue == key end,
                    function()
                        self._selectedValue = key
                        SetDropdownDisplayText(self, key)
                        if self._onSelect then self._onSelect(key, path) end
                    end
                )

                btn:AddInitializer(function(button)
                    CleanDropdownButton(button)
                end)
                ModernMenuButton(btn)
            end
        end

        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
    end)

    return dropdown
end

-- =========================================================
-- 3. 音效下拉菜单 (LSM Sound with Groups)
-- =========================================================
function EXUI:CreateLSMSoundDropdown(parent, width, label, currentValue, onSelect, searchConfig)
    -- [Fix] 兼容性处理：如果第四个参数是函数，说明是 legacy 调用 (onSelect 放在了 currentValue 位置)
    if type(currentValue) == "function" and onSelect == nil then
        onSelect = currentValue
        currentValue = nil
    end

    local EXFactory = _G.ExwindFactory
    local dropdown
    if EXFactory then
        dropdown = self:AcquireControl("GridLSMDropdown", parent)
    else
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridLSMDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end
    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)

    -- [池化关键] 将状态挂到 self，避免每次 Render 生成新闭包链
    dropdown._selectedValue = type(currentValue) == "string" and currentValue or LSM:GetDefault("sound")
    dropdown._onSelect = onSelect
    dropdown.labelText:SetText(label or "")
    SetDropdownSearchEnabled(dropdown, searchConfig)

    SetDropdownDisplayText(dropdown, dropdown._selectedValue or "None")

    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:AddMenuAcquiredCallback(function(proxy)
            local parent = proxy:GetParent()
            local parentScale = parent and parent:GetEffectiveScale() or 1
            local ownerScale = self:GetEffectiveScale()
            if parentScale > 0 and ownerScale > 0 then proxy:SetScale(ownerScale / parentScale) end
            EXUI:StyleDropdownMenuProxy(proxy)
        end)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(L["选择音效"])) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable("sound")
        local keys = LSM:List("sound")
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)

        -- 分类逻辑
        local exKeys = {}
        local otherKeys = {}
        for _, key in ipairs(keys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                if key:find("^%(EX%)") then
                    table.insert(exKeys, key)
                else
                    table.insert(otherKeys, key)
                end
            end
        end

        local hasMatch = (#exKeys > 0) or (#otherKeys > 0)
        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
            return
        end

        local function AddSoundToMenu(targetDescription, key, path)
            local shortKey = #key > 50 and (string.sub(key, 1, 49) .. ".") or key
            local btn = targetDescription:CreateRadio(shortKey,
                function() return self._selectedValue == key end,
                function()
                    self._selectedValue = key
                    SetDropdownDisplayText(self, key)
                    if self._onSelect then self._onSelect(key, path) end
                end
            )

            btn:AddInitializer(function(button, description, menu)
                CleanDropdownButton(button)
                AttachModernMenuSoundPreviewButton(button, path, description)
            end)
            ModernMenuButton(btn)
        end

        if #exKeys > 0 then
            local submenu = ModernMenuButton(rootDescription:CreateButton(L["EXWIND音效"]))
            for _, key in ipairs(exKeys) do
                AddSoundToMenu(submenu, key, list[key])
            end
            if #otherKeys > 0 then
                ModernMenuDivider(rootDescription:CreateDivider())
            end
        end

        for _, key in ipairs(otherKeys) do
            AddSoundToMenu(rootDescription, key, list[key])
        end
    end)

    return dropdown
end

-- =========================================================
-- 4. 多选下拉菜单 (Multi-Select)
-- =========================================================
function EXUI:CreateMultiSelectDropdown(parent, width, label, options, selections, onUpdate, searchConfig)
    local EXFactory = _G.ExwindFactory
    local dropdown

    if EXFactory then
        -- 复用 GridDropdown 池 (它本身就是 DropdownButton + Label)
        dropdown = self:AcquireControl("GridDropdown", parent)
    else
        -- 兜底
        dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown._gridType = "GridDropdown"
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME)
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    self:ApplyControlAppearance(dropdown)
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2] 将状态挂载到 Self，防止闭包泄漏
    dropdown._options = options
    dropdown._selections = selections
    dropdown._onUpdate = onUpdate
    local effectiveSearchConfig = searchConfig
    if effectiveSearchConfig == nil then
        -- Short menus open directly; long specialization lists retain search.
        -- This threshold affects presentation only, never option data.
        effectiveSearchConfig = { searchable = #(options or {}) > 8 }
    end
    SetDropdownSearchEnabled(dropdown, effectiveSearchConfig)

    local function GetOptionLabel(option)
        if type(option) == "table" then
            return tostring(option[1] or option.label or option[2] or option.value or "")
        end
        return tostring(option or "")
    end

    local function GetOptionValue(option)
        if type(option) == "table" then
            return option[2] ~= nil and option[2] or option.value or option[1] or option.label
        end
        return option
    end

    local function CountSelected(owner)
        local selected, total = 0, 0
        for _, option in ipairs(owner._options or {}) do
            total = total + 1
            if owner._selections[GetOptionValue(option)] then selected = selected + 1 end
        end
        return selected, total
    end

    -- [Fix] 重命名为 RefreshSelectionDisplay 避免与 Blizzard 内部方法冲突导致栈溢出
    function dropdown:RefreshSelectionDisplay()
        local selectedLabels = {}
        for _, option in ipairs(self._options) do
            local optionValue = GetOptionValue(option)
            if self._selections[optionValue] then
                table.insert(selectedLabels, GetOptionLabel(option))
            end
        end
        local display = L["未选择"]
        if #selectedLabels > 0 and #selectedLabels == #(self._options or {}) then
            display = L["全部"]
        elseif #selectedLabels > 0 then
            if #selectedLabels <= 2 then
                display = table.concat(selectedLabels, ", ")
            else
                display = string.format(L["已选 %d 项"], #selectedLabels)
            end
        end
        SetDropdownDisplayText(self, display)
        if self._onUpdate then self._onUpdate(self._selections) end
    end

    dropdown:RefreshSelectionDisplay()

    dropdown:SetupMenu(function(self, rootDescription)
        rootDescription:AddMenuAcquiredCallback(function(proxy)
            local parent = proxy:GetParent()
            local parentScale = parent and parent:GetEffectiveScale() or 1
            local ownerScale = self:GetEffectiveScale()
            if parentScale > 0 and ownerScale > 0 then proxy:SetScale(ownerScale / parentScale) end
            EXUI:StyleDropdownMenuProxy(proxy)
        end)
        rootDescription:SetScrollMode(400)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else ModernMenuTitle(rootDescription:CreateTitle(label)) end

        if not self._options then return end

        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false
        for _, option in ipairs(self._options) do
            local optionLabel = GetOptionLabel(option)
            local optionValue = GetOptionValue(option)
            if searchNeedle == "" or NormalizeDropdownSearchText(optionLabel):find(searchNeedle, 1, true) then
                hasMatch = true
                local optionDescription = rootDescription:CreateCheckbox(optionLabel,
                    function() return self._selections[optionValue] == true end,
                    function()
                        self._selections[optionValue] = not self._selections[optionValue]
                        self:RefreshSelectionDisplay()
                        return MenuResponse.Refresh
                    end
                )
                ModernMenuMultiselectCheckbox(optionDescription)
            end
        end

        if not hasMatch then
            ModernMenuTitle(rootDescription:CreateTitle(L["无匹配结果"]))
        end
        ModernMenuThinDivider(rootDescription:CreateDivider())
        local selectedCount, totalCount = CountSelected(self)
        local footer = ModernMenuButton(rootDescription:CreateButton(L["清空"], function()
            for _, option in ipairs(self._options) do
                self._selections[GetOptionValue(option)] = nil
            end
            self:RefreshSelectionDisplay()
            return MenuResponse.Refresh
        end))
        footer:AddInitializer(function(frame)
            if not frame or not frame.AttachFontString then return end
            frame:SetHeight(MODERN_MENU_ROW_HEIGHT)
            local clearText = frame.fontString or frame.Text
            if clearText then
                clearText:ClearAllPoints()
                clearText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
                clearText:SetTextColor(unpack(MC.lightBlue))
            end
            local countText = frame:AttachFontString()
            countText:SetPoint("LEFT", frame, "LEFT", 10, 0)
            countText:SetFontObject(MODERN.menuFonts.control)
            countText:SetText(string.format(L["已选 %d/%d"], selectedCount, totalCount))
            countText:SetTextColor(unpack(MC.muted))
        end)
    end)

    -- 兼容旧接口
    dropdown.dropdown = dropdown

    return dropdown
end

-- =========================================================
-- 5. 通用按钮 (Button) - [v4.3.1] 支持池化
-- =========================================================
-- 按钮变体的唯一入口：归一化 variant 并重画。调用点不要再直接写 _exButtonVariant，
-- 否则非法值不会被归一，外观与 CreateButton 产生分叉。
function EXUI:SetButtonVariant(button, variant, skipPaint)
    if not button then return button end
    if variant == "primary" or variant == "danger" or variant == "dangerSolid" then
        button._exButtonVariant = variant
    else
        -- 旧 soft / neutral 调用继续有效，但统一落到新的“次要按钮”语义。
        button._exButtonVariant = "secondary"
    end
    if not skipPaint then self:ApplyControlAppearance(button) end
    return button
end

function EXUI:CreateButton(parent, width, height, text, onClick, options)
    local EXFactory = _G.ExwindFactory
    local btn

    if EXFactory then
        -- 从池获取
        btn = self:AcquireControl("GridButton", parent)
        -- 清理上一租约可能留下的播放指示器外观（region 与 hook 随 Frame 常驻）。
        btn._exSoundPreviewActive = nil
        btn._exTrackedSoundPlaying = nil
        self:ReleasePlayingIndicator(btn)
        -- 清理旧的 OnClick。OnMouseDown/OnMouseUp 里有 pressed 画器，走
        -- ClearControlScript 让槽位和安装记录保持一致，由下面的
        -- ApplyControlAppearance 重装。
        btn:SetScript("OnClick", nil)
        btn:SetScript("PreClick", nil)
        btn:SetScript("PostClick", nil)
        self:ClearControlScript(btn, "OnMouseDown")
        self:ClearControlScript(btn, "OnMouseUp")
    else
        -- 兜底
        btn = CreateFrame("Button", nil, parent, "SharedButtonLargeTemplate")
        btn._gridType = "GridButton"
    end

    -- Existing compact utility buttons keep their explicit small footprint.
    -- Standard text buttons share the minimum and padding; no per-page colors.
    local requestedPresentation = type(options) == "table" and options.presentation or nil
    btn._exButtonPresentation = requestedPresentation == "sidebar" and "sidebar" or nil
    if btn._exSidebarIcon then btn._exSidebarIcon:Hide(); btn._exSidebarIcon:SetTexture(nil) end
    btn._exSidebarSelected = nil
    btn._exSidebarLevel = type(options) == "table" and tonumber(options.level) or nil
    local label = EnsureTextButtonFontString(btn)
    if btn._exButtonPresentation ~= "sidebar" then
        btn.label = nil
    end
    btn._exButtonCompact = type(options) == "table" and options.compact == true
    btn._exButtonPainted = nil
    btn._exButtonKeyboardFocused = nil
    btn:SetSize(btn._exButtonCompact and (width or GM.size.controlDefaultWidth)
        or math.max(BUTTON_STYLE.minWidth, width or GM.size.controlDefaultWidth),
        btn._exButtonCompact and (height or GM.size.buttonHeight) or math.max(MODERN.metrics.button + BUTTON_STYLE.paddingY * 2, height or GM.size.buttonHeight))
    EXUI:SetButtonVariant(btn, type(options) == "table" and options.variant or nil, true)
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end
    if btn.Enable then
        btn:Enable()
    end
    if btn.RegisterForClicks then
        btn:RegisterForClicks("LeftButtonUp")
    end

    btn:SetText(text or "")
    if btn._exButtonPresentation == "sidebar" then
        label:SetText(text or "")
    end
    self:ApplyControlAppearance(btn)
    label = EnsureTextButtonFontString(btn)
    if label then
        label:ClearAllPoints()
        if btn._exButtonPresentation == "sidebar" then
            LayoutSidebarNavigationButton(btn)
        elseif btn._exButtonCompact then
            label:SetPoint("CENTER", btn, "CENTER")
        else
            label:SetPoint("TOPLEFT", btn, "TOPLEFT", BUTTON_STYLE.paddingX, -BUTTON_STYLE.paddingY)
            label:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -BUTTON_STYLE.paddingX, BUTTON_STYLE.paddingY)
        end
        if not btn._exButtonCompact and btn._exButtonPresentation ~= "sidebar" then
            btn:SetWidth(math.max(btn:GetWidth(), math.ceil(label:GetUnboundedStringWidth() or 0)
                + BUTTON_STYLE.paddingX * 2))
        end
        label:SetJustifyH(btn._exButtonPresentation == "sidebar" and "LEFT" or "CENTER")
        label:SetJustifyV("MIDDLE")
    end

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end

-- Sidebar navigation is a presentation of the shared GridButton lease, not a
-- separate button implementation or pool. Consumers provide text/click/state;
-- hover, selected visuals and pooled-state cleanup remain owned by EXUI.
function EXUI:CreateSidebarNavigationButton(parent, text, onClick, options)
    options = type(options) == "table" and options or {}
    local level = tonumber(options.level) or 0
    local height = tonumber(options.height) or (level > 0 and 24 or 28)
    local btn = self:CreateButton(parent, tonumber(options.width) or 1, height, text or "", onClick, {
        compact = true,
        presentation = "sidebar",
        level = level,
    })
    btn:SetHeight(height)
    self:SetSidebarNavigationButtonIcon(btn, options.icon)
    self:SetSidebarNavigationButtonState(btn, options.selected == true, options.enabled ~= false)
    return btn
end

function EXUI:SetSidebarNavigationButtonIcon(button, icon)
    if not button or button._exButtonPresentation ~= "sidebar" then return end
    if icon then
        if not button._exSidebarIcon then
            button._exSidebarIcon = self:CreateVisualTexture(button, EXBORDERFRAME)
            button._exSidebarIcon:SetSize(20, 20)
        end
        button._exSidebarIcon:SetTexture(ExwindTools.GUIIcons.ids[icon] and self:GetIcon(icon) or icon)
        button._exSidebarIcon:Show()
    elseif button._exSidebarIcon then
        button._exSidebarIcon:SetTexture(nil)
        button._exSidebarIcon:Hide()
    end
    LayoutSidebarNavigationButton(button)
    PaintModernButton(button)
end

function EXUI:SetSidebarNavigationButtonLevel(button, level)
    if not button or button._exButtonPresentation ~= "sidebar" then return end
    button._exSidebarLevel = tonumber(level) or 0
    button:SetHeight(button._exSidebarLevel > 0 and 24 or 28)
    LayoutSidebarNavigationButton(button)
    PaintModernButton(button)
end

function EXUI:SetSidebarNavigationButtonState(button, selected, enabled)
    if not button or button._exButtonPresentation ~= "sidebar" then return end
    button._exSidebarSelected = selected == true
    if enabled == false then
        button._exModernHover = nil
        button._exModernPressed = nil
        button:Disable()
    else
        button:Enable()
    end
    PaintModernButton(button)
end

function EXUI:ReleaseSidebarNavigationButton(button)
    if not button or button._exButtonPresentation ~= "sidebar" then return false end
    if button._exSidebarLabel then
        button._exSidebarLabel:SetText("")
        button._exSidebarLabel:ClearAllPoints()
        button._exSidebarLabel:Hide()
    end
    if button._exSidebarIcon then button._exSidebarIcon:SetTexture(nil); button._exSidebarIcon:Hide() end
    button:SetScript("OnClick", nil)
    button:SetScript("PreClick", nil)
    button:SetScript("PostClick", nil)
    local factory = _G.ExwindFactory
    if button._fromPool and factory then
        factory:Release(button._fromPool, button)
    else
        button:Hide()
        button:ClearAllPoints()
        button:SetParent(nil)
    end
    return true
end

function EXUI:CreateSidebarNavigationHeader(parent, text, options)
    options = type(options) == "table" and options or {}
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(tonumber(options.height) or 24)
    header.label = self:CreateVisualFontString(header, EXFONTFRAME)
    header.label:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.label:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    header.label:SetJustifyH("LEFT")
    header.label:SetJustifyV("MIDDLE")
    header.label:SetFontObject(MODERN.menuFonts.title)
    header.label:SetTextColor(unpack(GC.text))
    header.label:SetText(text or "")
    return header
end

-- =========================================================
-- 5b. 图片按钮 (PicButton) - 支持 Normal/Pushed/Highlight 贴图
-- =========================================================
function EXUI:CreatePicButton(parent, width, height, normalTex, pushedTex, highlightTex, onClick, noCrop)
    local btn = CreateFrame("Button", nil, parent)
    btn._gridType = "GridPicButton"
    btn:SetSize(width or GM.size.controlHeight, height or GM.size.controlHeight)

    local crop = (not noCrop) and { 0.08, 0.92, 0.08, 0.92 } or { 0, 1, 0, 1 }

    -- 1. 正常状态贴图
    if normalTex then
        local n = EXUI:CreateVisualTexture(btn, EXBASEFRAME)
        n:SetTexture(normalTex)
        n:SetAllPoints()
        n:SetTexCoord(unpack(crop))
        btn:SetNormalTexture(n)
        btn.Normal = n
    end

    -- 2. 按下状态贴图
    if pushedTex then
        local p = EXUI:CreateVisualTexture(btn, EXBASEFRAME)
        p:SetTexture(pushedTex)
        p:SetAllPoints()
        p:SetTexCoord(unpack(crop))
        btn:SetPushedTexture(p)
        btn.Pushed = p
    else
        -- ...
        -- 自动生成按下效果：贴图四周内缩一点并压暗，使"按下去"看得出来。
        btn:SetPushedTextOffset(1, -1)
        if normalTex then
            -- 没有 Pushed 贴图时，按下状态复用 Normal 图并压暗（此前 GetPushedTexture 为 nil 会报错）。
            -- 只用 0.7 压暗时会被常驻的 ADD 高亮抵消，按下几乎看不出变化，因此同时内缩。
            local inset = GM.size.picButtonPressInset
            local p = EXUI:CreateVisualTexture(btn, EXBASEFRAME)
            p:SetTexture(normalTex)
            p:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
            p:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
            p:SetTexCoord(unpack(crop))
            p:SetVertexColor(0.55, 0.55, 0.55)
            btn:SetPushedTexture(p)
            btn.Pushed = p
        end
    end

    -- 3. 高亮(滑过)状态贴图
    if highlightTex then
        local h = EXUI:CreateVisualTexture(btn, EXEDITORFRAME)
        h:SetTexture(highlightTex)
        h:SetAllPoints()
        h:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn:SetHighlightTexture(h)
        btn._exPicButtonHighlightAlpha = h:GetAlpha()
    else
        -- 高亮沿原图标轮廓，不能套用复选框的方形光斑。
        local h = EXUI:CreateVisualTexture(btn, EXEDITORFRAME)
        h:SetTexture(normalTex)
        h:SetAllPoints()
        h:SetTexCoord(unpack(crop))
        h:SetBlendMode("ADD")
        h:SetAlpha(.25)
        btn:SetHighlightTexture(h)
        btn._exPicButtonHighlightAlpha = .25
    end

    -- 常驻 ADD 高亮会把压暗的按下贴图提亮回去；按下期间先让它退场，松开再恢复。
    if not btn._exPicButtonPressHooks then
        btn._exPicButtonPressHooks = true
        btn:HookScript("OnMouseDown", function(self)
            local highlight = self.GetHighlightTexture and self:GetHighlightTexture()
            if highlight then highlight:SetAlpha(0) end
        end)
        btn:HookScript("OnMouseUp", function(self)
            local highlight = self.GetHighlightTexture and self:GetHighlightTexture()
            if highlight then highlight:SetAlpha(self._exPicButtonHighlightAlpha or 0.25) end
        end)
    end

    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

-- =========================================================
-- 6. 通用勾选框 (CheckBox) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateCheckbox(parent, text, initialValue, onClick)
    local EXFactory = _G.ExwindFactory
    local container

    if EXFactory then
        -- 从池获取（池中已预创建 checkbox 和 label）
        container = self:AcquireControl("GridCheckbox", parent)
    else
        -- 兜底：传统创建
        container = CreateFrame("Frame", nil, parent)
        container._gridType = "GridCheckbox"
        container:SetSize(200, GM.size.checkboxRowHeight)

        local cb = CreateFrame("CheckButton", nil, container, "MinimalCheckboxTemplate")
        cb:SetSize(GM.size.checkboxRowHeight, GM.size.checkboxRowHeight)
        cb:SetPoint("LEFT", container, "LEFT", 0, 0)
        -- 移除旧版硬编码贴图，使用模板自带的现代 Atlas
        container.checkbox = cb

        local label = EXUI:CreateVisualFontString(container, EXFONTFRAME)
        label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        container.label = label

        function container:SetChecked(v) self.checkbox:SetChecked(v) end

        function container:GetChecked() return self.checkbox:GetChecked() end
    end

    if container._exSettingsListVisualState then self:RestoreSettingsListControl(container) end
    self:ApplyControlAppearance(container)

    -- 设置当前值
    container:SetSize(200, GM.size.checkboxRowHeight)
    container.checkbox:SetChecked(initialValue)
    container.label:SetText(text or "")
    if container.EnableMouse then
        container:EnableMouse(false)
    end
    self:ClearControlScript(container, "OnEnter")
    self:ClearControlScript(container, "OnLeave")
    if container.checkbox.EnableMouse then
        container.checkbox:EnableMouse(true)
    end
    -- 这四个槽位里可能还有上一租约的业务脚本；清掉的同时也丢掉画器安装记录，
    -- 下面的 ApplyModernCheckbox 会把 pressed 画器重新装回 OnLeave 槽位。
    self:ClearControlScript(container.checkbox, "OnEnter")
    self:ClearControlScript(container.checkbox, "OnLeave")
    self:ClearControlScript(container.checkbox, "PreClick")
    self:ClearControlScript(container.checkbox, "PostClick")

    -- 设置回调
    container.checkbox:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if onClick then onClick(self:GetChecked() == true) end
    end)

    -- 上面清过槽位，这里补装画器并按本租约的 checked 重画一次。
    ApplyModernCheckbox(container)

    return container
end

-- =========================================================
-- 6.1 三态勾选框（全选 / 部分 / 无）
-- 与 CreateCheckbox 同一个池化容器和同一套 painter：checked / unchecked 由原生 CheckButton 的
-- 勾选承载，“部分”(mixed) 是未勾选加 container._exTriState 标记，painter 把边框改成选中主色并画横杠。
-- 点击后：checked -> unchecked，unchecked / mixed -> checked；控件先自己切到新状态再调用 onChange，
-- 业务拒绝或要改成别的状态时再调用 SetState（静默）。
-- 归还池时 FramePool 的标准重置会清掉 _exTriState，下一次借用恢复普通勾选框。
-- =========================================================
local TRI_STATES = { checked = true, unchecked = true, mixed = true }

local function ApplyTriState(container, state)
    container._exTriState = state
    container.checkbox:SetChecked(state == "checked")
    PaintModernCheckbox(container)
end

local function TriStateSetState(container, state)
    if not TRI_STATES[state] then
        error("TriStateCheckbox:SetState expects checked/unchecked/mixed", 2)
    end
    ApplyTriState(container, state)
end

local function TriStateGetState(container)
    return container._exTriState
end

function EXUI:CreateTriStateCheckbox(parent, text, state, onChange)
    if not TRI_STATES[state] then
        error("CreateTriStateCheckbox: state must be checked/unchecked/mixed", 2)
    end
    local container
    container = self:CreateCheckbox(parent, text, false, function(checked)
        local nextState = checked and "checked" or "unchecked"
        ApplyTriState(container, nextState)
        if onChange then onChange(nextState, container) end
    end)
    container.SetState = TriStateSetState
    container.GetState = TriStateGetState
    ApplyTriState(container, state)
    return container
end

-- =========================================================
-- 7. 通用拖动条 (Slider)
--
-- 旧接口保持不变：
--   CreateSlider(parent, width, label, min, max, value, step, formatter, onValueChanged)
--
-- 新接口可以把最后一个参数换成 callbacks 表（或作为第十个参数传入）：
--   { onValueChanged = fn, onBegin = fn, onLive = fn, onCommit = fn }
--
-- onValueChanged 仍在 Slider 的每一次值变化时调用，保证旧页面行为不变。
-- onBegin/onLive/onCommit 只描述用户交互：按下、拖动、放开/输入提交。
-- 程序化静默回填使用 slider:SetEXUIValue(value, "silent")。
-- =========================================================
function EXUI:CreateSlider(parent, width, label, minVal, maxVal, curVal, step, formatter, onValueChanged, callbacks)
    local EXFactory = _G.ExwindFactory
    local slider

    if EXFactory then
        slider = self:AcquireControl("GridSlider", parent)
    else
        slider = CreateFrame("Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
        slider._gridType = "GridSlider"
    end

    -- Title occupies the first row; the track and editable number share the second.
    local controlWidth = tonumber(width) or 200
    local numberInputWidth = SLIDER_NUMBER_INPUT_WIDTH
    slider:SetSize(controlWidth, EXUI.GridSliderHeight)
    slider._exGridFixedHeight = EXUI.GridSliderHeight

    -- 不覆盖 Frame:SetPoint。MinimalSliderWithSteppersTemplate 的原生布局和
    -- 鼠标命中都依赖该 API；设置页需要微调时，必须在各自的布局常量中显式
    -- 修改，而不能在控件实例上劫持 SetPoint。

    -- 旧热重载/池化实例可能还带着上一版的 root。它不再参与布局，必须
    -- 主动隐藏和解绑，避免一个已隐藏的旧子树在复用时留下错误锚点。
    if slider._exControlRoot then
        slider._exControlRoot:Hide()
        slider._exControlRoot:ClearAllPoints()
    end
    if slider.EnableMouse then
        slider:EnableMouse(true)
    end
    if slider.SetEnabled then
        slider:SetEnabled(true)
    elseif slider.Enable then
        slider:Enable()
    end

    -- [池化关键] 将回调存到 slider 属性。第九参数接受 table，能穿过
    -- ElvUI 对 CreateSlider 的旧签名包装；第十参数是原生路径的可选别名。
    local lifecycle = type(onValueChanged) == "table" and onValueChanged
        or (type(callbacks) == "table" and callbacks)
        or nil
    -- lifecycle.showFill 已失效：轨道一律是空的，不画已走过那一段的填充
    -- （用户 2026-10-05）。旧调用点仍可以传这个字段，这里直接忽略。
    slider._exNumberInputPosition = lifecycle and lifecycle.numberInputPosition or nil
    slider._onValueChanged = type(onValueChanged) == "function" and onValueChanged
        or (lifecycle and lifecycle.onValueChanged)
    slider._onBegin = lifecycle and lifecycle.onBegin or nil
    slider._onLive = lifecycle and lifecycle.onLive or nil
    slider._onCommit = lifecycle and lifecycle.onCommit or nil
    slider._exControlWidth = controlWidth
    -- GridSlider 来自对象池时不能继承上一次拖动的交互状态。
    slider._exDragging = false
    slider._exSetPhase = nil
    slider._exNormalizing = false
    slider._exSyncingInput = false
    slider._exModernHover = nil
    slider._exModernPressed = nil
    local interactiveSlider = slider.Slider or slider
    interactiveSlider._exModernHover = nil
    interactiveSlider._exModernPressed = nil
    for _, key in ipairs({ "Back", "Forward" }) do
        if slider[key] then
            slider[key]._exModernHover = nil
            slider[key]._exModernPressed = nil
        end
    end
    -- 组合控件复用时用这份参数静默回填当前规则的数据。
    slider._exCompositeMin = tonumber(minVal) or 0
    slider._exCompositeMax = tonumber(maxVal) or slider._exCompositeMin

    -- [v4.3.15 Fix] 智能格式化：如果启用了小数步长，自动显示相应的小数位
    local precision = 0
    local numericStep = tonumber(step) or 1
    if numericStep <= 0 then numericStep = 1 end
    slider._exCompositeSteps = (slider._exCompositeMax - slider._exCompositeMin) / numericStep
    if numericStep > 0 and numericStep < 1 then
        -- 0.05/0.001 等步长均以最小必要小数位显示，并避免浮点尾巴。
        while precision < 6 do
            local scale = 10 ^ precision
            if math.abs(numericStep * scale - math.floor(numericStep * scale + 0.5)) < 0.000001 then
                break
            end
            precision = precision + 1
        end
    end
    slider._exStep = numericStep
    slider._exPrecision = precision

    slider._formatter = (type(formatter) == "function") and formatter or function(v)
        if precision > 0 then
            return string.format("%." .. precision .. "f", v)
        else
            return math.floor(v + 0.5) -- 整数模式使用四舍五入
        end
    end

    -- 池化滑块可能已预创建 ValueText/Title；仅在缺失时补建，避免拖动时叠字残影
    if not slider.ValueText then
        slider.ValueText = EXUI:CreateVisualFontString(slider, EXFONTFRAME)
        slider.ValueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", -2, 1)
        slider.ValueText:SetJustifyH("RIGHT")
    end
    if not slider.Title then
        slider.Title = EXUI:CreateVisualFontString(slider, EXFONTFRAME)
        slider.Title:SetJustifyH("LEFT")
        slider.Title:SetWordWrap(false)
    end
    slider.labelText = slider.Title

    -- 保留 ValueText 属性给旧皮肤/旧样式代码，但正式可编辑数值由 numberInput 显示。
    slider.ValueText:Hide()

    if not slider.numberInput then
        local input = CreateFrame("EditBox", nil, slider, "BackdropTemplate")
        input:SetAutoFocus(false)
        input._exSliderNumberInput = true
        input:SetJustifyH("CENTER")
        input:SetTextInsets(SLIDER_NUMBER_INPUT_INSET, SLIDER_NUMBER_INPUT_INSET, 0, 0)
        -- 不使用 SetNumeric(true)：部分客户端会因此拒绝负号，而 X/Y 偏移是合法负值。
        input:SetMaxLetters(16)
        slider.numberInput = input
    end

    local numberInput = slider.numberInput
    -- 对象池复用时明确回到当前 slider；不能继承已废弃 control root 的 parent。
    numberInput:SetParent(slider)
    -- 若对象池归还时输入框仍有焦点，先禁止旧闭包在 ClearFocus 期间提交旧 DB。
    numberInput._exSkipLostCommit = true
    numberInput:ClearFocus()
    numberInput._exSkipLostCommit = nil
    numberInput._exLastArrowCommitText = nil
    numberInput._exModernHover = nil
    numberInput:ClearAllPoints()
    if slider._exNumberInputPosition == "title" then
        numberInput:SetPoint("TOPRIGHT", slider, "TOPRIGHT", 0, 0)
    else
        -- 数值框要和轨道所在的 30 高交互行垂直居中对齐，而不是贴着滑条底边。
        numberInput:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0,
            math.floor((GM.size.controlHeight - SLIDER_NUMBER_INPUT_HEIGHT) / 2 + 0.5))
    end
    numberInput:SetSize(numberInputWidth, SLIDER_NUMBER_INPUT_HEIGHT)
    numberInput:Show()

    -- The number field stays at the right of the track without changing callbacks.
    slider.Title:ClearAllPoints()
    slider.Title:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 0)
    if slider._exNumberInputPosition == "title" then
        slider.Title:SetPoint("RIGHT", numberInput, "LEFT", -8, 0)
        slider.Title:SetHeight(SLIDER_NUMBER_INPUT_HEIGHT)
    else
        slider.Title:SetPoint("BOTTOMRIGHT", numberInput, "TOPRIGHT", 0, 4)
    end
    slider.Title:SetJustifyH("LEFT")
    slider.Title:SetJustifyV("MIDDLE")

    local function NormalizeValue(s, value)
        value = tonumber(value)
        if not value then return nil end

        local minValue = tonumber(s._exCompositeMin) or 0
        local maxValue = tonumber(s._exCompositeMax) or minValue
        if minValue > maxValue then minValue, maxValue = maxValue, minValue end
        value = math.max(minValue, math.min(maxValue, value))

        local increment = tonumber(s._exStep) or 1
        if increment > 0 then
            local units = (value - minValue) / increment
            if units >= 0 then
                units = math.floor(units + 0.5)
            else
                units = math.ceil(units - 0.5)
            end
            value = minValue + units * increment
            value = math.max(minValue, math.min(maxValue, value))
        end

        -- 让 0.1 + 0.2 之类的值回到可显示/可保存的稳定精度。
        local displayPrecision = tonumber(s._exPrecision) or 0
        if displayPrecision > 0 then
            local scale = 10 ^ displayPrecision
            if value >= 0 then
                value = math.floor(value * scale + 0.5) / scale
            else
                value = math.ceil(value * scale - 0.5) / scale
            end
        end
        return value
    end

    local function UpdateDisplayedValue(s, value)
        if s.ValueText and s._formatter then
            s.ValueText:SetText(s._formatter(value))
        end
        local input = s.numberInput
        if input and s._formatter then
            s._exSyncingInput = true
            input:SetText(s._formatter(value))
            input:SetCursorPosition(0)
            s._exSyncingInput = false
        end
    end

    -- MinimalSliderWithSteppersTemplate 的外层是布局/CallbackRegistry 容器，
    -- 实际轨道值属于它的 Slider 子对象。所有读取必须从同一个原生轨道
    -- 取得，不能把外层残留值再写回轨道；否则鼠标放开时会跳回旧值。
    local function GetInnerValue(s)
        local interactiveSlider = s.Slider or s
        return interactiveSlider:GetValue()
    end

    -- 供 Grid/模块在未来接入实时预览时使用；这里不广播、不重建。
    function slider:SetLifecycleCallbacks(newCallbacks)
        newCallbacks = type(newCallbacks) == "table" and newCallbacks or {}
        self._onBegin = newCallbacks.onBegin
        self._onLive = newCallbacks.onLive
        self._onCommit = newCallbacks.onCommit
        if type(newCallbacks.onValueChanged) == "function" then
            self._onValueChanged = newCallbacks.onValueChanged
        end
    end

    function slider:SetEXUIValue(value, phase)
        local normalized = NormalizeValue(self, value)
        if normalized == nil then return false end
        self._exSetPhase = phase
        self._exSilent = phase == "silent"
        local previous = GetInnerValue(self)
        self:SetValue(normalized)
        -- SetValue 不会在相同数值时触发 CallbackRegistry；输入提交仍应有 commit。
        if previous == normalized then
            UpdateDisplayedValue(self, normalized)
            if phase == "commit" and self._onCommit then self._onCommit(normalized) end
        end
        self._exSetPhase = nil
        self._exSilent = nil
        return true
    end

    -- 首次注册回调（只注册一次）
    if not slider._sliderInit then
        -- [v4.3.13 Fix] 传入 slider 作为 owner
        -- CallbackRegistryMixin 的 TriggerEvent 会以 callback(owner, value) 形式调用
        -- 所以第一个参数 s 就是 slider 自身
        slider:RegisterCallback("OnValueChanged", function(s, value)
            local normalized = NormalizeValue(s, value)
            if normalized == nil then return end

            -- 原生轨道可能给出带浮点尾巴的值；只让标准化后的值进入 DB。
            if math.abs(normalized - value) > 0.000001 then
                if not s._exNormalizing then
                    s._exNormalizing = true
                    s:SetValue(normalized)
                    s._exNormalizing = false
                end
                return
            end

            UpdateDisplayedValue(s, normalized)
            PaintModernSlider(s)
            if not s._exSilent and s._onValueChanged then s._onValueChanged(normalized) end

            local phase = s._exSetPhase
            if phase == "commit" then
                if s._onCommit then s._onCommit(normalized) end
            elseif s._exDragging or phase == "live" then
                if s._onLive then s._onLive(normalized) end
            end
        end, slider)

        -- MinimalSliderWithSteppersTemplate 本身只是承载 Frame；真正接收轨道
        -- 鼠标的对象是它的 Slider 子项。此前把 Hook 挂在外层，拖动时
        -- _exDragging 永远不会设为 true，生命周期式 Slider 因而既不 live
        -- 也不 commit（输入框的显式 commit 则仍正常），这正是“能输入、
        -- 不能拖动”的根因。
        local interactiveSlider = slider.Slider or slider
        local function BeginDrag(_, button)
            if button ~= nil and button ~= "LeftButton" then return end
            -- 同一次按下可能同时经过模板和外层；begin 只能发一次。
            if slider._exDragging then return end
            slider._exDragging = true
            slider._exDragStartValue = GetInnerValue(slider)
            if slider._onBegin then slider._onBegin(slider._exDragStartValue) end
        end

        interactiveSlider:HookScript("OnMouseDown", BeginDrag)
        -- 原生轨道已经 ObeyStepOnDrag；放开时只提交它的当前值。绝不能在
        -- 此处 Normalize/SetValue，否则会把外层的旧值回写造成鼠标放开跳值。
        interactiveSlider:HookScript("OnMouseUp", function()
            if not slider._exDragging then return end
            slider._exDragging = false
            local value = GetInnerValue(slider)
            local changed = value ~= slider._exDragStartValue
            slider._exDragStartValue = nil
            UpdateDisplayedValue(slider, value)
            -- 仅按下而没有改变值，不发生 DB 写入，也不能触发全量重套造成闪烁。
            if changed and slider._onCommit then slider._onCommit(value) end
        end)

        slider._sliderInit = true
    end

    -- 输入框仅在回车/失焦时提交，输入过程中绝不触发页面全量刷新。
    numberInput:SetScript("OnEditFocusGained", nil)
    numberInput:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if self._exSkipLostCommit then
            self._exSkipLostCommit = nil
            return
        end
        if self._exLastArrowCommitText and self:GetText() == self._exLastArrowCommitText then
            self._exLastArrowCommitText = nil
            return
        end
        self._exLastArrowCommitText = nil
        if slider._exSyncingInput then return end
        local text = self:GetText():gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
        local value = NormalizeValue(slider, text)
        if value == nil then
            UpdateDisplayedValue(slider, NormalizeValue(slider, GetInnerValue(slider)))
            return
        end
        slider:SetEXUIValue(value, "commit")
    end)
    numberInput:SetScript("OnEnterPressed", function(self)
        self._exSkipLostCommit = true
        local text = self:GetText():gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
        local value = NormalizeValue(slider, text)
        if value == nil then
            UpdateDisplayedValue(slider, NormalizeValue(slider, GetInnerValue(slider)))
        else
            slider:SetEXUIValue(value, "commit")
        end
        self:ClearFocus()
    end)
    numberInput:SetScript("OnEscapePressed", function(self)
        self._exSkipLostCommit = true
        UpdateDisplayedValue(slider, NormalizeValue(slider, GetInnerValue(slider)))
        self:ClearFocus()
    end)
    numberInput:SetScript("OnKeyDown", function(self, key)
        if key ~= "LEFT" and key ~= "RIGHT" and key ~= "UP" and key ~= "DOWN" then return end
        if not IsModernSliderEnabled(slider) then return end
        local direction = (key == "RIGHT" or key == "UP") and 1 or -1
        local multiplier = _G.IsShiftKeyDown and _G.IsShiftKeyDown() and 10 or 1
        local current = NormalizeValue(slider, GetInnerValue(slider))
        if current == nil then return end
        local nextValue = NormalizeValue(slider,
            current + direction * (slider._exStep or 1) * multiplier)
        if nextValue == current then return end
        slider:SetEXUIValue(nextValue, "commit")
        -- Focus loss after a keyboard step must not emit a second commit.
        self._exLastArrowCommitText = self:GetText()
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    end)

    self:ApplyControlAppearance(slider)

    -- 每次调用都更新：标题、数值显示、滑动条值
    if slider.Title then slider.Title:SetText(label or "") end
    local initialValue = NormalizeValue(slider, curVal) or slider._exCompositeMin
    UpdateDisplayedValue(slider, initialValue)

    if slider.Init then
        -- 构造/对象池回填只是显示初值，不能反向触发 DB 广播或模块刷新。
        slider._exSilent = true
        slider:Init(initialValue, slider._exCompositeMin, slider._exCompositeMax, slider._exCompositeSteps)
        slider._exSilent = nil
    elseif slider.SetValue then
        slider._exSilent = true
        slider:SetValue(initialValue)
        slider._exSilent = nil
    end

    PaintModernSlider(slider)

    return slider
end

-- =========================================================
-- Compact timeline input. Unlike the settings slider, its range can change
-- during a session and it has no label, steppers, or numeric edit box.
function EXUI:CreateTimelineSlider(parent, width, height, maximum, onValueChanged)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(width or 200, height or 20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0, maximum or 10)
    slider:SetValueStep(.05)
    slider:SetValue(0)
    local track = self:CreateVisualTexture(slider, EXBASEFRAME)
    track:SetColorTexture(unpack(GC.sliderTrack))
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(GM.size.timelineTrackHeight)
    local thumb = self:CreateVisualTexture(slider, EXEDITORFRAME)
    thumb:SetColorTexture(unpack(GC.sliderThumb))
    thumb:SetSize(12, math.max(8, (height or 20) - 2))
    slider:SetThumbTexture(thumb)
    slider.Track, slider.Thumb = track, thumb
    if onValueChanged then slider:SetScript("OnValueChanged", onValueChanged) end
    return slider
end

-- 8. 通用分隔线 (Separator)
-- =========================================================
function EXUI:CreateSubheader(parent, text, width)
    local section = self:CreateSettingsSection(parent, {kind="subsection", title=text or ""})
    section.text, section.labelText = section._exSettingsSectionTitle, section._exSettingsSectionTitle
    self:UpdateSettingsSectionLayout(section, width or 200)
    return section
end
function EXUI:CreateDescription(parent, text, width)
    local frame = self:AcquireControl("GridDescription", parent)
    frame:SetSize(width or 200, 40)
    self:ApplyControlAppearance(frame)
    frame.text:SetText(text or "")
    frame.labelText = frame.text
    return frame
end

function EXUI:CreateCard(parent, width, height)
    local frame = self:AcquireControl("GridCard", parent)
    frame:SetSize(width or 400, height or 120)
    return self:ApplyControlAppearance(frame)
end

-- =========================================================
-- 9. 分段标题 (Header with Line) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateHeader(parent, text, width)
    local section = self:CreateSettingsSection(parent, {kind="page", title=text or ""})
    section.Title = section._exSettingsSectionTitle
    self:UpdateSettingsSectionLayout(section, width or 550)
    return section
end
-- =========================================================
-- 10. 复合字体设置组 (Font Setting Group)
-- 传入一个 db 表(需包含 .font, .size, .outline)，会自动创建一整套设置
-- =========================================================
-- =========================================================
-- 11. 颜色选择按钮 (Color Button)
-- =========================================================
-- ColorPickerFrame 是暴雪全局窗口，XML 固定在 DIALOG strata。组合弹窗也在 DIALOG，
-- 因而从组合弹窗打开颜色选择器时，必须临时提升到 FULLSCREEN_DIALOG，否则会被父弹窗盖住。
-- 关闭后恢复原本 strata/level，不能污染暴雪或其他插件的普通颜色选择器。
local function PromoteColorPickerForOwner(owner)
    local picker = _G.ColorPickerFrame
    if not picker or not owner or not owner.GetFrameStrata then return end

    local ownerStrata = owner:GetFrameStrata()
    local ownerLevel = owner.GetFrameLevel and owner:GetFrameLevel() or 0
    if ownerStrata ~= "DIALOG" and ownerStrata ~= "TOOLTIP" and ownerStrata ~= "FULLSCREEN_DIALOG" then return end

    if not picker._exuiColorPickerRestoreHook then
        picker._exuiColorPickerRestoreHook = true
        picker:HookScript("OnHide", function(self)
            local restore = self._exuiColorPickerRestoreLayer
            if not restore then return end
            self:SetFrameStrata(restore.strata)
            self:SetFrameLevel(restore.level)
            self._exuiColorPickerRestoreLayer = nil
        end)
    end

    if not picker._exuiColorPickerRestoreLayer then
        picker._exuiColorPickerRestoreLayer = {
            strata = picker:GetFrameStrata(),
            level = picker:GetFrameLevel(),
        }
    end
    local pickerStrata = ownerStrata == "DIALOG" and "FULLSCREEN_DIALOG" or ownerStrata
    picker:SetFrameStrata(pickerStrata)
    picker:SetFrameLevel(math.max(ownerLevel + 600, picker:GetFrameLevel()))
    if picker.SetToplevel then picker:SetToplevel(true) end
end

function EXUI:CreateColorButton(parent, label, db, key, hasAlpha, onUpdate, options)
    local EXFactory = _G.ExwindFactory
    local btn

    if EXFactory then
        btn = self:AcquireControl("GridColorButton", parent)
    else
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        if not btn.swatch then
            btn.swatch = EXUI:CreateVisualTexture(btn, EXBORDERFRAME)
            btn.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        if not btn.labelText then
            local txt = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
            btn.labelText = txt
        end
        btn._gridType = "GridColorButton"
    end

    -- 1. 主容器
    btn:SetSize(GM.size.colorButtonDefaultWidth, GM.size.colorButtonHeight)
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end
    if btn.SetMouseMotionEnabled then
        btn:SetMouseMotionEnabled(true)
    end
    if btn.SetMouseClickEnabled then
        btn:SetMouseClickEnabled(true)
    end
    if btn.RegisterForClicks then
        btn:RegisterForClicks("LeftButtonUp")
    end

    -- 2. 左侧预览色块
    local swatch = btn.swatch
    if swatch then
        swatch:ClearAllPoints()
        swatch:SetSize(GM.size.colorSwatchSize, GM.size.colorSwatchSize)
        swatch:SetPoint("LEFT", btn, "LEFT", GM.space.colorSwatchPaddingX, 0)
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:Hide()
    end

    if not btn.swatchBorder then
        btn.swatchBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        btn.swatchBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn.swatchBorder:EnableMouse(false)
        if btn.swatchBorder.SetMouseMotionEnabled then btn.swatchBorder:SetMouseMotionEnabled(false) end
        if btn.swatchBorder.SetMouseClickEnabled then btn.swatchBorder:SetMouseClickEnabled(false) end
    end
    btn.swatchBorder:ClearAllPoints()
    btn.swatchBorder:SetPoint("TOPLEFT", swatch, -1, 1)
    btn.swatchBorder:SetPoint("BOTTOMRIGHT", swatch, 1, -1)
    btn.swatchBorder:SetBackdropBorderColor(0, 0, 0, 0.8)
    btn.swatchBorder:Hide()
    if not btn._exRoundedSwatch then
        btn._exRoundedSwatch = CreateFrame("Frame", nil, btn)
        btn._exRoundedSwatch:EnableMouse(false)
    end
    btn._exRoundedSwatch:SetSize(GM.size.colorSwatchSize, GM.size.colorSwatchSize)
    btn._exRoundedSwatch:SetPoint("LEFT", btn, "LEFT", GM.space.colorSwatchPaddingX, 0)
    local function PaintSwatch()
        local r, g, b, a = swatch:GetVertexColor()
        -- 16px 的小色块用 control(4) 半径时，圆角和 1px 描边不同源，边缘会发毛；
        -- 小件统一用 thumb(3) 半径，描边改用更贴合的子卡边框色。
        EXUI:SetControlSurface(btn._exRoundedSwatch, GM.radius.thumb, {r,g,b,a}, GC.subcardBorder)
    end
    if not btn._exSwatchColorHook then
        btn._exSwatchColorHook = true
        hooksecurefunc(swatch, "SetVertexColor", PaintSwatch)
    end
    PaintSwatch()

    -- 3. 文本标签
    if not btn.labelText then
        btn.labelText = btn.label
    end
    if not btn.labelText then
        btn.labelText = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    end
    local text = btn.labelText
    self:ApplyControlAppearance(btn)
    text:ClearAllPoints()
    text:SetPoint("LEFT", swatch, "RIGHT", GM.space.colorSwatchGap, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -GM.space.colorButtonTextPaddingRight, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label or "")

    -- [关键] 属性挂载，以便池化复用时更新
    if btn.CancelColorTransaction then btn:CancelColorTransaction() end
    btn._colorButtonLease = {}
    btn._currentDb = db
    btn._currentKey = key
    btn._currentOnUpdate = onUpdate
    btn._hasAlpha = hasAlpha
    btn._currentChangeFlow = type(options) == "table" and options._changeFlow or nil

    if not btn.UpdateColor then
        function btn:UpdateColor(nr, ng, nb, na)
            local r, g, b, a
            if type(nr) == "number" then
                r, g, b, a = nr, ng, nb, na
            else
                local d, k = self._currentDb, self._currentKey
                if not d then return end
                if not k or k == "" then
                    r, g, b, a = d.r or 1, d.g or 1, d.b or 1, d.a or 1
                else
                    r, g, b, a = d[k .. "R"] or 1, d[k .. "G"] or 1, d[k .. "B"] or 1, d[k .. "A"] or 1
                end
            end
            if self.swatch then
                self.swatch:SetVertexColor(r, g, b, a)
            end
        end
    end

    btn:UpdateColor()

    -- Retire an invalidated editor lease without committing its live draft.
    if not btn.CancelColorTransaction then
        function btn:CancelColorTransaction(token)
            local session = self._colorPickerSession
            if not session or (token ~= nil and session.token ~= token) then return false end
            self._colorPickerSession = nil
            local picker = _G.ColorPickerFrame
            local ownsPicker = picker and picker._exuiColorTransactionOwner == self
                and picker._exuiColorTransactionToken == session.token
            if ownsPicker then
                picker._exuiColorTransactionOwner, picker._exuiColorTransactionToken = nil, nil
            end
            local original = session.original
            self:UpdateColor(original.r, original.g, original.b, original.a)
            if ownsPicker then picker:Hide() end
            return true
        end
    end

    if not btn.IsColorPickerOpen then
        function btn:IsColorPickerOpen()
            local session, picker = self._colorPickerSession, _G.ColorPickerFrame
            local open = self._colorButtonLease ~= nil and session ~= nil and picker ~= nil
                and picker:IsShown() and picker._exuiColorTransactionOwner == self
                and picker._exuiColorTransactionToken == session.token
            return open == true, open and session.token or nil
        end
        function btn:OwnsColorPickerFrame(frame)
            if not self:IsColorPickerOpen() then return false end
            local picker = _G.ColorPickerFrame
            while frame do
                if frame == picker then return true end
                frame = frame.GetParent and frame:GetParent() or nil
            end
            return false
        end
    end

    if not btn.FinishColorTransaction then
        function btn:FinishColorTransaction(token)
            local session = self._colorPickerSession
            if not session or (token ~= nil and session.token ~= token) then return false end
            self._colorPickerSession = nil
            session.transaction.onCommit(session.current)
            return true
        end
    end

    local colorFactory = _G.ExwindFactory
    if colorFactory then
        colorFactory:AttachPoolRelease(btn, function(self)
            self._colorButtonLease = nil
            self:CancelColorTransaction()
            self._currentDb, self._currentKey, self._currentOnUpdate, self._currentChangeFlow = nil, nil, nil, nil
        end)
    end

    btn:SetScript("OnClick", function(self)
        local lease = self._colorButtonLease
        local d, k = self._currentDb, self._currentKey
        if type(d) ~= "table" then return end
        local picker = ColorPickerFrame
        local previousOwner, previousToken = picker._exuiColorTransactionOwner, picker._exuiColorTransactionToken
        local previousOpening = picker._exuiColorSetupLease
        if previousOwner and type(previousOwner.FinishColorTransaction) == "function" then
            previousOwner:FinishColorTransaction(previousToken)
            if self._colorButtonLease ~= lease or picker._exuiColorSetupLease ~= previousOpening
                or picker._exuiColorTransactionOwner ~= previousOwner
                or picker._exuiColorTransactionToken ~= previousToken then return end
        end
        picker._exuiColorTransactionOwner, picker._exuiColorTransactionToken = nil, nil
        local opening = {}
        picker._exuiColorSetupLease = opening
        local hasAlpha = self._hasAlpha

        local function GetDBColor()
            if not k or k == "" then
                return d.r or 1, d.g or 1, d.b or 1, d.a or 1
            else
                return d[k .. "R"] or 1, d[k .. "G"] or 1, d[k .. "B"] or 1, d[k .. "A"] or 1
            end
        end

        local function SetDBColor(r, g, b, a)
            if not k or k == "" then
                d.r, d.g, d.b, d.a = r, g, b, a
            else
                d[k .. "R"], d[k .. "G"], d[k .. "B"], d[k .. "A"] = r, g, b, a
            end
        end

        local currR, currG, currB, currA = GetDBColor()
        local factory = self._currentChangeFlow
        local transaction = type(factory) == "function" and factory() or nil
        if self._colorButtonLease ~= lease or picker._exuiColorSetupLease ~= opening then return end
        local token
        local capturedSession
        local function Current()
            return self._colorButtonLease == lease and picker._exuiColorSetupLease == opening
                and (not transaction or self._colorPickerSession == capturedSession)
        end
        local function RetireOpening()
            if picker._exuiColorSetupLease ~= opening then return end
            local owner, ownerToken = picker._exuiColorTransactionOwner, picker._exuiColorTransactionToken
            if owner ~= nil and (owner ~= self or ownerToken ~= token) then return end
            picker._exuiColorTransactionOwner, picker._exuiColorTransactionToken = nil, nil
            picker._exuiColorSetupLease = nil
            picker:Hide()
        end
        if transaction then
            token = (self._colorPickerToken or 0) + 1
            self._colorPickerToken = token
            self._colorPickerSession = {
                token = token,
                transaction = transaction,
                original = { r = currR, g = currG, b = currB, a = currA },
                current = { r = currR, g = currG, b = currB, a = currA },
            }
            capturedSession = self._colorPickerSession
            picker._exuiColorTransactionOwner, picker._exuiColorTransactionToken = self, token
            transaction.onBegin()
            if not Current() then RetireOpening(); return end
            if not ColorPickerFrame._exuiColorTransactionHook then
                ColorPickerFrame._exuiColorTransactionHook = true
                ColorPickerFrame:HookScript("OnHide", function(frame)
                    local owner, ownerToken = frame._exuiColorTransactionOwner, frame._exuiColorTransactionToken
                    frame._exuiColorTransactionOwner, frame._exuiColorTransactionToken = nil, nil
                    if owner and type(owner.FinishColorTransaction) == "function" then
                        owner:FinishColorTransaction(ownerToken)
                    end
                end)
            end
        end

        -- 打开 picker 只 Begin 一次；连续 swatch/opacity 回调只写 DB 并 Patch
        -- 当前 Panel。OnHide 才统一 Commit，取消会先恢复打开时的值再受控结束。
        local function ApplyColor(r, g, b, a)
            if not Current() then return end
            if transaction then
                local active = self._colorPickerSession
                if not active or active.token ~= token then return end
                local value = { r = r, g = g, b = b, a = a }
                transaction.onLive(value)
                local session = self._colorPickerSession
                if session ~= active or not Current() then return end
                session.current = value
            else
                SetDBColor(r, g, b, a)
                if self._currentOnUpdate then self._currentOnUpdate(d) end
                if not Current() then return end
            end
            self:UpdateColor()
        end

        local info = {
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                ApplyColor(r, g, b, a)
            end,
            opacityFunc = hasAlpha and function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                ApplyColor(r, g, b, a)
            end or nil,
            cancelFunc = function(prev)
                if not Current() then return end
                local session = self._colorPickerSession
                if transaction and (not session or session.token ~= token) then return end
                local original = session and session.original
                local r = (prev and prev.r) or (original and original.r) or currR
                local g = (prev and prev.g) or (original and original.g) or currG
                local b = (prev and prev.b) or (original and original.b) or currB
                local a = (prev and (prev.a or prev.opacity)) or (original and original.a) or currA
                ApplyColor(r, g, b, a)
                if transaction and Current() then self:FinishColorTransaction(token) end
            end,
            hasOpacity = hasAlpha,
            opacity = hasAlpha and currA or 1,
            r = currR,
            g = currG,
            b = currB,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
        if not Current() then RetireOpening(); return end
        PromoteColorPickerForOwner(self)
    end)
    return btn
end

-- SettingsList 和 Composite 共用的原宿主获取入口。
local function AcquireCompositeGroup(poolType, parent)
    local factory = _G.ExwindFactory
    if factory and factory.AcquireCompositeHost then
        return factory:AcquireCompositeHost(poolType, parent)
    end
    return CreateFrame("Frame", nil, parent, "BackdropTemplate"), true
end

-- =========================================================
-- 13. 输入框与多行文本框 (EditBox)
-- Options: .bgColor, .borderColor, .textColor
-- =========================================================
-- Search styling never installs filtering or menu lifecycle callbacks.
function EXUI:ApplySearchBoxAppearance(edit)
    edit._exSearchAppearance = true
    ApplyModernInput(edit)
    MODERN.ApplyTextRole(edit, "control", GC.text)
    edit:SetTextInsets(28, edit.ClearButton and 24 or 9, 0, 0)
    if edit.SetCursorColor then edit:SetCursorColor(unpack(GC.inputFocusBorder)) end
    if edit.placeholder then edit.placeholder:SetText(""); edit.placeholder:Hide() end
    if edit.Instructions then edit.Instructions:SetText(""); edit.Instructions:Hide() end
    if not edit._exSearchIcon then
        edit._exSearchIcon = self:CreateVisualTexture(edit, EXBORDERFRAME)
        edit._exSearchIcon:SetSize(14, 14)
        edit._exSearchIcon:SetPoint("LEFT", 8, 0)
    end
    edit._exSearchIcon:SetTexture(self:GetIcon("search"))
    edit._exSearchIcon:SetVertexColor(unpack(GC.textDim))
    edit._exSearchIcon:Show()
end

function EXUI:CreateSearchBox(parent, initialText, width, height, options)
    local edit = self:CreateEditBox(parent, initialText, width or 180,
        height or GM.size.inputHeight, nil, options)
    self:ApplySearchBoxAppearance(edit)
    return edit
end

-- Resolve the enclosing page at the current lease, not a global Tools page.
function EXUI:ForwardInputMouseWheel(owner, delta)
    local ancestor = owner:GetParent()
    while ancestor do
        if ancestor.IsObjectType and ancestor:IsObjectType("ScrollFrame") then
            local handler = ancestor:GetScript("OnMouseWheel")
            if handler then
                handler(ancestor, delta)
            else
                local maximum = math.max(0, ancestor:GetVerticalScrollRange())
                ancestor:SetVerticalScroll(math.max(0, math.min(maximum,
                    ancestor:GetVerticalScroll() - delta * 25)))
            end
            return
        end
        ancestor = ancestor:GetParent()
    end
end

function EXUI:ReleaseCheckboxOnOffVisual(widget)
    local visual = widget and widget._exCheckboxOnOffVisual
    if not visual then return end
    visual:Hide()
    PaintModernCheckbox(widget)
    if visual.originalHitInsets then
        widget.checkbox:SetHitRectInsets(unpack(visual.originalHitInsets))
        visual.originalHitInsets = nil
    end
end

function EXUI:ApplyCheckboxOnOffVisual(widget)
    if not widget or not widget.checkbox then return end
    local box = widget.checkbox
    local visual = widget._exCheckboxOnOffVisual
    if not visual then
        visual = CreateFrame("Frame", nil, box)
        visual:EnableMouse(false)
        visual:SetAllPoints(box)
        visual.on = CreateFrame("Frame", nil, visual)
        visual.off = CreateFrame("Frame", nil, visual)
        for _, segment in ipairs({ visual.on, visual.off }) do
            segment:EnableMouse(false)
            segment.text = self:CreateVisualFontString(segment, EXFONTFRAME, "GameFontHighlightSmall")
            segment.text:SetPoint("CENTER")
            MODERN.ApplyTextRole(segment.text, "control")
        end
        visual.on.text:SetText("ON")
        visual.off.text:SetText("OFF")
        visual.Refresh = function(self)
            local checked, enabled = box:GetChecked() == true, box:IsEnabled()
            local width = box:GetWidth()
            local hover = enabled and box:IsMouseOver()
            if self.checked == checked and self.enabled == enabled
                and self.width == width and self.hover == hover then return end
            self.checked, self.enabled, self.width, self.hover = checked, enabled, width, hover
            self:SetFrameLevel(box:GetFrameLevel() + 5)
            EXUI:SetControlSurface(self, GM.radius.control, GC.panel, hover and GC.cardHoverBorder or GC.cardBorder)
            self.on:ClearAllPoints()
            self.on:SetPoint("TOPLEFT", 3, -3)
            self.on:SetPoint("BOTTOMRIGHT", self, "BOTTOM", -1, 3)
            self.off:ClearAllPoints()
            self.off:SetPoint("TOPLEFT", self, "TOP", 1, -3)
            self.off:SetPoint("BOTTOMRIGHT", -3, 3)
            for index, segment in ipairs({ self.on, self.off }) do
                local selected = (index == 1) == checked
                EXUI:SetControlSurface(segment, GM.radius.thumb, selected and enabled and GC.segmentSelected or GC.panel,
                    GC.transparent)
                segment.text:SetTextColor(unpack(selected and enabled and GC.white or GC.textDim))
            end
            box:SetHitRectInsets(checked and width / 2 or 0, checked and 0 or width / 2, 0, 0)
        end
        visual:SetScript("OnUpdate", visual.Refresh)
        visual:SetScript("OnHide", function(self)
            self.checked, self.enabled, self.width, self.hover = nil, nil, nil, nil
        end)
        widget._exCheckboxOnOffVisual = visual
    end
    if not visual.originalHitInsets then visual.originalHitInsets = { box:GetHitRectInsets() } end
    visual:Show()
    PaintModernCheckbox(widget)
    visual:Refresh()
end
function EXUI:CreateEditBox(parent, text, w, h, labelText, options)
    h = h or GM.size.inputHeight
    local isMultiLine = h > 40
    options = options or {}

    local function SetPixelSize(region, width, height)
        local pixelUtil = _G.PixelUtil
        if pixelUtil and pixelUtil.SetSize then
            pixelUtil.SetSize(region, width, height, 1, 1)
        else
            region:SetSize(width, height)
        end
    end

    local EXFactory = _G.ExwindFactory

    -- [v4.3.2] 单行模式走池化通道
    if EXFactory and not isMultiLine then
        local container = self:AcquireControl("GridInput", parent)

        -- 清理旧回调。OnEditFocusLost 里有本控件的焦点画器，清槽位时必须一起
        -- 丢掉安装记录，否则下面的 ApplyControlAppearance 不会把它装回来。
        container:SetScript("OnTextChanged", nil)
        self:ClearControlScript(container, "OnEditFocusLost")
        container:SetScript("OnEnterPressed", nil)
        container:SetScript("OnMouseUp", nil)

        -- 兼容旧接口
        container.editBox = container
        if container.Enable then container:Enable() end
        container._exSearchAppearance = nil
        self:ApplyControlAppearance(container)

        -- 基础配置
        -- GridInput is shared by ordinary text fields and quantity editors.
        -- Quantity editors deliberately switch their own lease to CENTER, so
        -- every ordinary single-line lease must restore the visual baseline.
        -- This changes geometry only: cursor, accepted input and callbacks are
        -- left untouched.
        if container._exSearchIcon then container._exSearchIcon:Hide() end
        -- 数字步进器租约状态随租约结束：重新作为普通输入框租出时必须隐藏步进条并清掉数值状态。
        if container._exNumberStepper then container._exNumberStepper:Hide() end
        container._exNumberInput = nil
        container:EnableMouseWheel(true)
        container:SetScript("OnMouseWheel", function(self, delta) EXUI:ForwardInputMouseWheel(self, delta) end)
        container:SetJustifyH("LEFT")
        container:SetJustifyV("MIDDLE")
        SetPixelSize(container, w or 180, h or GM.size.inputHeight)
        -- GridInput is also leased by item quantity fields, which enable numeric
        -- mode. Restore text input before applying this lease's value.
        container:SetNumeric(false)
        if container.EnableMouse then
            container:EnableMouse(true)
        end
        container:SetAutoFocus(false)
        container:SetText(text or "")
        container:SetCursorPosition(0)

        -- 标签设置
        if labelText then
            local label = container.label
            label:Show()
            label:SetText(labelText)
            label:ClearAllPoints()

            if options.labelPos == "left" then
                label:SetPoint("RIGHT", container, "LEFT", -5, 0)
                label:SetJustifyH("RIGHT")
            else
                label:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 3)
                label:SetJustifyH("LEFT")
            end

        else
            container.label:Hide()
        end

        -- 占位符
        if not container.placeholder then
            container.placeholder = EXUI:CreateVisualFontString(container, EXFONTFRAME)
            container.placeholder:SetPoint("LEFT", 3, 0)
        end
        MODERN.ApplyTextRole(container.placeholder, "fieldValue")
        container.placeholder:SetText(options.placeholder or "")

        local function UpdatePlaceholder()
            if container:GetText() == "" then container.placeholder:Show() else container.placeholder:Hide() end
        end
        UpdatePlaceholder()

        -- 回调逻辑
        container:SetScript("OnTextChanged", function(self, userInput)
            UpdatePlaceholder()
            if options.onChanged then options.onChanged(self:GetText(), userInput) end
        end)

        -- 这两个槽位里本来有 ApplyModernInput 装的焦点画器，构造器要把业务脚本
        -- 写进同一个槽位，所以先用 ClearControlScript 丢掉安装记录，写完之后再
        -- 调一次 ApplyModernInput 把画器补回来（SetScript 会连 HookScript 的链
        -- 一起清掉，用户 2026-10-05 已实测，Postcall 绑定也保不住）。
        self:ClearControlScript(container, "OnEditFocusGained")
        self:ClearControlScript(container, "OnEditFocusLost")

        container:SetScript("OnEditFocusLost", function(self)
            -- 单行输入失焦后必须自己清掉选中高亮：这个槽位由业务脚本持有。
            self:HighlightText(0, 0)
            UpdatePlaceholder()
            if options.onEditFocusLost then options.onEditFocusLost(self:GetText()) end
        end)

        container:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if options.onEnter then options.onEnter(self:GetText()) end
        end)

        container:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        -- 补装 focus/hover 画器：OnEditFocusGained 槽位空着由它接管，
        -- OnEditFocusLost 槽位已有业务脚本，画器以 HookScript 接在其后。
        ApplyModernInput(container)

        return container
    end

    -- =========================================================
    -- 多行模式或无工厂模式 (Legacy Path)
    -- =========================================================

    -- 1. 主容器
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container._exMultilineInput = true
    SetPixelSize(container, w, h)

    -- 简化的标签逻辑
    if labelText then
        local label = EXUI:CreateVisualFontString(container, EXFONTFRAME)
        if options.labelPos == "left" then
            label:SetPoint("RIGHT", container, "LEFT", -5, 0)
            label:SetJustifyH("RIGHT")
        else
            label:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 3)
        end
        StyleModernTitle(label)
        label:SetText(labelText)
        container.label = label
    end

    -- 多行模式特有逻辑: ScrollFrame
    local eb
    local sf = CreateFrame("ScrollFrame", nil, container)
    sf:SetPoint("TOPLEFT", 5, -5)
    sf:SetPoint("BOTTOMRIGHT", -5, 5)

    -- [Fix] 使用一个容器 Frame 作为 ScrollChild，EditBox 放在里面
    -- 这样可以更精确控制 EditBox 的行为，避免 ScrollFrame 对 EditBox 的奇异约束
    local scrollContent = CreateFrame("Frame", nil, sf)
    scrollContent:SetSize(w - 20, 2000) -- 给一个巨大的高度，确保能滚动
    sf:SetScrollChild(scrollContent)

    eb = CreateFrame("EditBox", nil, scrollContent)
    eb:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, 0)
    eb:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, 0)
    eb:SetHeight(2000) -- 让 EditBox 同样巨大
    eb:SetMultiLine(true)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("TOP") -- 必须顶部对齐！

    -- 自动滚动逻辑
    eb:SetScript("OnCursorChanged", function(self, x, y, width, height)
        local vs = sf:GetVerticalScroll()
        local h = sf:GetHeight()
        -- y 是相对于 EditBox 顶部的负值
        local cursorY = -y

        if cursorY < vs then
            sf:SetVerticalScroll(cursorY)
        elseif (cursorY + height) > (vs + h) then
            sf:SetVerticalScroll(cursorY + height - h)
        end
    end)
    sf:EnableMouseWheel(true)
    container.scrollFrame = sf

    -- [Fix] 增加点击区域屏蔽，确保点击容器任何地方都能聚焦 EditBox
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    -- [Fix] 解决多行输入框拦截滚轮的问题：将滚动事件透传给父级
    local function ForwardWheelToPage(_, delta)
        EXUI:ForwardInputMouseWheel(container, delta)
    end
    sf:SetScript("OnMouseWheel", ForwardWheelToPage)
    eb:EnableMouseWheel(true)
    eb:HookScript("OnMouseWheel", ForwardWheelToPage)

    eb:SetAutoFocus(false)
    MODERN.ApplyTextRole(eb, "fieldValue")
    eb:SetText(text or "")
    eb:SetTextInsets(8, 8, 8, 8) -- 增加边距，更有呼吸感

    -- [Fix] 更新高度以适应内容，确保滚动条逻辑生效
    eb:SetScript("OnTextChanged", function(self, userInput)
        -- 自动伸缩高度：取可视高度和内容高度的较大者
        local contentH = self:GetNumLetters() * 15 -- 粗略估算，或者直接保持固定大高度
        -- 更好的做法：不做自动伸缩，只依赖 ScrollFrame。但为了点击体验，保持 SetSize(..., h)
        if options.onChanged then options.onChanged(self:GetText(), userInput) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", nil)
    eb:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if options.onEditFocusLost then options.onEditFocusLost(self:GetText()) end
    end)

    container.editBox = eb
    function container:GetText() return self.editBox:GetText() end

    function container:SetText(t) self.editBox:SetText(t or "") end

    return container
end

-- =========================================================
-- 14.1 数字输入框（步进器） [WEB-REQ 17]
-- 数值居中，右侧上下两个小三角步进箭头；全局统一样式。
-- 复用 CreateEditBox 的池化 GridInput（边框/悬停/聚焦/禁用外观与普通输入框一致），只叠加一条右侧步进条。
-- options: width 由参数给出；height（默认 GM.size.inputHeight）、label/labelPos（同 CreateEditBox）、
--   min/max（可选）、step（默认 1）、integer（取整）、value（初值）、onChanged(value, source)：
--   source = "step"（箭头）/ "input"（输入后回车或失焦）。数值越界自动夹到 [min,max]；无法解析的文字回退到上一个有效值。
--   allowEmpty=false；validation="clamp"（默认）或"reject"（原始范围/整数检查）；
--   onRejected(reason,source)在恢复后调用。SetMixed(mixed,text)仅呈现，不改底值。
-- 返回同一个输入框，并附加：GetNumber() / SetNumber(value) 不触发回调 / SetNumberRange(min,max,step,integer)。
-- =========================================================
local NUMBER_STEPPER_WIDTH = GM.size.numberStepperWidth

local function NumberInputText(state, value)
    if value == nil then return "" end
    if state.integer then return string.format("%d", math.floor(value + 0.5)) end
    return (string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function NumberInputClamp(state, value)
    if state.min ~= nil and value < state.min then value = state.min end
    if state.max ~= nil and value > state.max then value = state.max end
    if state.integer then value = math.floor(value + 0.5) end
    return value
end

local function NumberInputApply(edit, value, source)
    local state = edit._exNumberInput
    if not state then return end
    local changed = state.value ~= value or (state.mixed and state.dirty)
    state.value = value
    state.mixed, state.mixedText, state.dirty = false, nil, false
    edit:SetText(NumberInputText(state, value))
    edit:SetCursorPosition(0)
    if changed and source and state.onChanged then state.onChanged(value, source) end
end

local function NumberInputRestore(edit, state)
    state.dirty = false
    edit:SetText(state.mixed and state.mixedText or NumberInputText(state, state.value))
    edit:SetCursorPosition(0)
end

local function NumberInputReject(edit, state, reason, source)
    NumberInputRestore(edit, state)
    if state.onRejected then state.onRejected(reason, source) end
end

-- Both typed and stepped values use this validation before any clamping/rounding.
local function NumberInputValidate(state, value)
    if not value or value ~= value or math.abs(value) == math.huge then return false, "invalid-number" end
    if state.validation == "reject" then
        if (state.min and value < state.min) or (state.max and value > state.max) then return false, "out-of-range" end
        if state.integer and value ~= math.floor(value) then return false, "not-integer" end
    end
    return true, NumberInputClamp(state, value)
end

local function ReadNumberInputDraft(edit)
    local state = edit._exNumberInput
    if not state then return false, "released" end
    local text = edit:GetText()
    if state.mixed and not state.dirty then return true, state.value end
    if text:match("^%s*$") then
        if state.allowEmpty then return true, nil end
        return false, "empty"
    end
    return NumberInputValidate(state, tonumber(text))
end

local function NumberInputCommit(edit, text)
    local state = edit._exNumberInput
    if not state or (edit.IsEnabled and not edit:IsEnabled()) then return end
    if state.mixed and not state.dirty then return end
    local valid, value = ReadNumberInputDraft(edit)
    if not valid then NumberInputReject(edit, state, value, "input"); return end
    NumberInputApply(edit, value, "input")
end

local function PaintNumberStepper(edit)
    local stepper = edit._exNumberStepper
    if not stepper or not stepper:IsShown() then return end
    local enabled = not edit.IsEnabled or edit:IsEnabled()
    for _, button in ipairs({ stepper.up, stepper.down }) do
        button:SetEnabled(enabled)
        button.glyph:SetVertexColor(unpack(enabled and (button._exHover and MC.white or MC.muted) or MC.disabledText))
        if button.symbol then
            button.symbol:SetTextColor(unpack(enabled and (button._exHover and MC.white or MC.muted) or MC.disabledText))
        end
    end
    stepper.divider:SetColorTexture(unpack(MC.inputBorder))
    stepper.middle:SetColorTexture(unpack(MC.inputBorder))
    if stepper.dividerRight then stepper.dividerRight:SetColorTexture(unpack(MC.inputBorder)) end
end

local function EnsureNumberStepper(edit)
    local stepper = edit._exNumberStepper
    if stepper then return stepper end
    stepper = CreateFrame("Frame", nil, edit)
    stepper:SetWidth(NUMBER_STEPPER_WIDTH)
    stepper:SetPoint("TOPRIGHT", edit, "TOPRIGHT", -1, -1)
    stepper:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -1, 1)
    stepper:EnableMouse(false)
    stepper.divider = stepper:CreateTexture(nil, "ARTWORK")
    stepper.divider:SetWidth(1)
    stepper.divider:SetPoint("TOPLEFT")
    stepper.divider:SetPoint("BOTTOMLEFT")
    stepper.middle = stepper:CreateTexture(nil, "ARTWORK")
    stepper.middle:SetHeight(1)
    stepper.middle:SetPoint("LEFT", stepper, "LEFT", 1, 0)
    stepper.middle:SetPoint("RIGHT")
    -- 左减右加时，两个按钮各用一条竖线与数值区分开，看起来才像按钮。
    stepper.dividerRight = stepper:CreateTexture(nil, "ARTWORK")
    stepper.dividerRight:SetWidth(1)
    stepper.dividerRight:Hide()
    for _, spec in ipairs({ { key = "up", sign = 1, rotation = math.pi }, { key = "down", sign = -1, rotation = 0 } }) do
        local button = CreateFrame("Button", nil, stepper)
        button:SetPoint("LEFT", stepper, "LEFT", 1, 0)
        button:SetPoint("RIGHT")
        if spec.key == "up" then button:SetPoint("TOP"); button:SetPoint("BOTTOM", stepper, "CENTER", 0, 0)
        else button:SetPoint("BOTTOM"); button:SetPoint("TOP", stepper, "CENTER", 0, 0) end
        button.glyph = button:CreateTexture(nil, "OVERLAY")
        button.glyph:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
        button.glyph:SetSize(10, 10)
        button.glyph:SetPoint("CENTER")
        button.glyph:SetRotation(spec.rotation) -- GlyphChevron 默认朝下
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnEnter", function(self) self._exHover = true; PaintNumberStepper(edit) end)
        button:SetScript("OnLeave", function(self) self._exHover = false; PaintNumberStepper(edit) end)
        button:SetScript("OnClick", function()
            local state = edit._exNumberInput
            if not state or (edit.IsEnabled and not edit:IsEnabled()) then return end
            -- 先把输入框里尚未提交的文字当作当前值，再按步长增减。
            local typed = (not state.mixed or state.dirty) and tonumber(edit:GetText()) or nil
            if state.mixed and typed == nil and state.value == nil then return end
            local base = typed or state.value or state.min or 0
            if state.validation == "reject" and (not state.mixed or state.dirty) then
                local valid, parsed = ReadNumberInputDraft(edit)
                if not valid then NumberInputReject(edit, state, parsed, "step"); return end
                base = parsed
                if base == nil then return end
            end
            local value = base + spec.sign * state.step
            if state.validation == "clamp" then value = math.floor(value * 1000 + 0.5) / 1000 end
            local valid, accepted = NumberInputValidate(state, value)
            if not valid then NumberInputReject(edit, state, accepted, "step"); return end
            if state.mixed then state.dirty = true end
            NumberInputApply(edit, accepted, "step")
        end)
        stepper[spec.key] = button
    end
    stepper:SetScript("OnShow", function() PaintNumberStepper(edit) end)
    if edit.SetEnabled then hooksecurefunc(edit, "SetEnabled", function() PaintNumberStepper(edit) end) end
    edit._exNumberStepper = stepper
    return stepper
end

function EXUI:CreateNumberInput(parent, width, options)
    options = options or {}
    local state = {
        min = options.min, max = options.max, step = tonumber(options.step) or 1,
        integer = options.integer == true, onChanged = options.onChanged,
        allowEmpty = options.allowEmpty == true, validation = options.validation or "clamp",
        onRejected = options.onRejected,
    }
    if (state.min ~= nil and type(state.min) ~= "number") or (state.max ~= nil and type(state.max) ~= "number")
        or state.step <= 0 or state.step ~= state.step then
        error("CreateNumberInput: invalid min/max/step", 2)
    end
    if state.validation ~= "clamp" and state.validation ~= "reject" then
        error("CreateNumberInput: validation must be clamp or reject", 2)
    end
    if state.onRejected ~= nil and type(state.onRejected) ~= "function" then
        error("CreateNumberInput: onRejected must be a function", 2)
    end
    local edit
    edit = self:CreateEditBox(parent, "", width or 110, options.height or GM.size.inputHeight, options.label, {
        labelPos = options.labelPos,
        onEnter = function(text) NumberInputCommit(edit, text) end,
        onEditFocusLost = function(text) NumberInputCommit(edit, text) end,
        onChanged = function(_, userInput)
            if userInput and edit._exNumberInput == state then state.dirty = true end
        end,
    })
    edit._exNumberInput = state
    -- Commit once, before focus loss; callbacks may synchronously retire this lease.
    edit:SetScript("OnEnterPressed", function(self)
        if self._exNumberInput ~= state then return end
        self:SetScript("OnEditFocusLost", nil)
        self:ClearFocus()
        if self._exNumberInput ~= state then return end
        self:SetScript("OnEditFocusLost", function(box) NumberInputCommit(box, box:GetText()) end)
        NumberInputCommit(self, self:GetText())
    end)
    edit:SetJustifyH("CENTER")
    local stepper = EnsureNumberStepper(edit)
    if options.stepper ~= nil and options.stepper ~= "right" and options.stepper ~= "sides" then
        error("CreateNumberInput: stepper must be right or sides", 2)
    end
    local sides = options.stepper == "sides"
    stepper:ClearAllPoints()
    stepper.divider:ClearAllPoints()
    stepper.divider:SetShown(true)
    stepper.middle:SetShown(not sides)
    stepper.dividerRight:ClearAllPoints()
    stepper.dividerRight:SetShown(sides)
    if sides then
        stepper:SetAllPoints(edit)
        edit:SetTextInsets(NUMBER_STEPPER_WIDTH + 4, NUMBER_STEPPER_WIDTH + 4, 0, 0)
        -- 左右两条竖线分别贴在减号按钮右侧与加号按钮左侧。
        stepper.divider:SetPoint("TOPLEFT", stepper, "TOPLEFT", NUMBER_STEPPER_WIDTH, -1)
        stepper.divider:SetPoint("BOTTOMLEFT", stepper, "BOTTOMLEFT", NUMBER_STEPPER_WIDTH, 1)
        stepper.dividerRight:SetPoint("TOPRIGHT", stepper, "TOPRIGHT", -NUMBER_STEPPER_WIDTH, -1)
        stepper.dividerRight:SetPoint("BOTTOMRIGHT", stepper, "BOTTOMRIGHT", -NUMBER_STEPPER_WIDTH, 1)
    else
        stepper.divider:SetPoint("TOPLEFT")
        stepper.divider:SetPoint("BOTTOMLEFT")
        stepper:SetWidth(NUMBER_STEPPER_WIDTH)
        stepper:SetPoint("TOPRIGHT", edit, "TOPRIGHT", -1, -1)
        stepper:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -1, 1)
        edit:SetTextInsets(4, NUMBER_STEPPER_WIDTH + 2, 0, 0)
    end
    for _, spec in ipairs({ {key="down", side="LEFT", text="−"}, {key="up", side="RIGHT", text="+"} }) do
        local button = stepper[spec.key]
        button:ClearAllPoints()
        button.glyph:SetShown(not sides)
        if not button.symbol then
            button.symbol = self:CreateVisualFontString(button, EXFONTFRAME)
            MODERN.ApplyTextRole(button.symbol, "fieldValue")
            button.symbol:SetPoint("CENTER")
        end
        button.symbol:SetText(spec.text)
        button.symbol:SetShown(sides)
        if sides then
            button:SetWidth(NUMBER_STEPPER_WIDTH)
            button:SetPoint("TOP" .. spec.side, stepper, "TOP" .. spec.side, 0, -1)
            button:SetPoint("BOTTOM" .. spec.side, stepper, "BOTTOM" .. spec.side, 0, 1)
        else
            button:SetPoint("LEFT", stepper, "LEFT", 1, 0)
            button:SetPoint("RIGHT")
            if spec.key == "up" then
                button:SetPoint("TOP"); button:SetPoint("BOTTOM", stepper, "CENTER", 0, 0)
            else
                button:SetPoint("BOTTOM"); button:SetPoint("TOP", stepper, "CENTER", 0, 0)
            end
        end
    end
    stepper:SetFrameLevel(edit:GetFrameLevel() + 3)
    stepper:Show()
    PaintNumberStepper(edit)
    function edit:GetNumber() return self._exNumberInput and self._exNumberInput.value or nil end
    function edit:SetMixed(mixed, text)
        local current = self._exNumberInput
        if not current then return end
        if mixed and (type(text) ~= "string" or text == "") then error("SetMixed requires display text", 2) end
        current.mixed, current.mixedText = mixed == true, mixed and text or nil
        NumberInputRestore(self, current)
    end
    function edit:SetDraft(text)
        local current = self._exNumberInput
        if not current then return end
        if type(text) ~= "string" then error("SetDraft expects text", 2) end
        self:SetText(text)
        if self._exNumberInput == current then current.dirty = true end
    end
    function edit:SetNumber(value)
        local current = self._exNumberInput
        if not current then return end
        if value ~= nil and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge) then
            error("SetNumber expects a finite number or nil", 2)
        end
        NumberInputApply(self, value ~= nil and NumberInputClamp(current, value) or nil, nil)
    end
    function edit:SetNumberRange(minimum, maximum, step, integer)
        local current = self._exNumberInput
        if not current then return end
        current.min, current.max = minimum, maximum
        if step ~= nil then current.step = step end
        if integer ~= nil then current.integer = integer == true end
    end
    edit:SetNumber(options.value)
    local numberFactory = _G.ExwindFactory
    if numberFactory then
        numberFactory:AttachPoolRelease(edit, function(self)
            self._exNumberInput = nil
            self:SetScript("OnEditFocusLost", nil)
            self:SetScript("OnEnterPressed", nil)
            self:SetScript("OnTextChanged", nil)
            self:ClearFocus()
            if self._exNumberStepper then self._exNumberStepper:Hide() end
        end)
    end
    return edit
end

-- =========================================================
-- 15. 分段控制器 (Segmented Control / Tabs)
-- items: { {label, value}, ... }
-- options（可选）: height = 轨道整体高度，默认 GM.size.segmentedItemHeight（34）；
--   放进 30 高的行时传 GM.size.controlHeight，内部选中块 = 轨道高度 - 6。最小 24（ChoiceGroup 的分段下限）。
-- =========================================================
local SEGMENTED_MIN_HEIGHT = 24

function EXUI:CreateSegmentedControl(parent, width, items, currentValue, onChange, options)
    -- [WEB-REQ 38/40] 分段控件唯一走 ExwindChoiceGroup（toc 保证已加载），不再保留 type()=="function" 兼容守卫。
    local height = GM.size.segmentedItemHeight
    if options ~= nil then
        if type(options) ~= "table" then
            error("CreateSegmentedControl: options must be a table", 2)
        end
        if options.height ~= nil then
            if type(options.height) ~= "number" or options.height < SEGMENTED_MIN_HEIGHT then
                error("CreateSegmentedControl: options.height must be a number >= " .. SEGMENTED_MIN_HEIGHT, 2)
            end
            height = options.height
        end
    end
    local choiceItems = {}
    for _, item in ipairs(items or {}) do
        choiceItems[#choiceItems + 1] = { id = item[2], label = item[1] }
    end
    local container = self:_CreateSegmentedChoice(parent, {
        width = width,
        items = choiceItems,
        value = currentValue,
        appearance = "segmented",
        wrap = false,
        itemHeight = height,
        gap = 3,
        onChange = function(value)
            if onChange then onChange(value) end
        end,
    })
    function container:Refresh() self:SetValue(self:GetValue()) end
    return container
end

-- =========================================================
-- StandardModulePage
-- =========================================================
-- 显示模块设置页的唯一非业务外壳。它不读取模块 state、不创建 renderer，也不
-- 解释 layout 内的任何业务字段；模块只能交出正式 binding、既有 Grid layout 与
-- 已存在的 preview surface。页面的 Dock、Scroll、延迟 Grid Render、状态 watch
-- 与释放次序则必须统一由这里拥有，不能再由每一个 EXBoss/EXAura Page 手写一遍。
--
-- preview 合同（StandardPreviewSurface 完成前的最窄过渡接口）：
--   render(dock, context)  -- 必须可重复调用，未来由 StandardPreviewSurface 复用 session
--   release(dock, context) -- 释放该模块的唯一 Panel session
--   refresh(dock, context) -- 可选；未提供时复用 render
-- 以上只接收 Dock 和上下文，不能创建私有 Dock、DB 或业务 renderer。
-- C_Timer.After callbacks do not retain the synchronous call stack that led to
-- Page:Render.  A failure used to look like a silent empty PreviewDock because
-- it could stop between Grid Render and preview.render.  Keep the four public
-- lifecycle stages explicit so the game error has a stable, searchable contract
-- instead of an anonymous delayed-callback stack.
MODERN.standardModulePage = {
    stages = {
        grid = "grid",
        slider = "slider",
        audit = "audit",
        preview = "preview",
    },
}

function MODERN.standardModulePage.BuildStageError(moduleKey, stage, original)
    local stack
    if type(_G.debugstack) == "function" then
        stack = _G.debugstack(3, 40, 40)
    elseif _G.debug and type(_G.debug.traceback) == "function" then
        stack = _G.debug.traceback("", 3)
    else
        stack = "<debug stack unavailable>"
    end
    return "EXUI StandardModulePage stage failed"
        .. " | moduleKey=" .. tostring(moduleKey)
        .. " | stage=" .. tostring(stage)
        .. "\noriginal=" .. tostring(original)
        .. "\nstack=" .. tostring(stack)
end

function MODERN.standardModulePage.RequireFunction(value, name)
    if type(value) ~= "function" then
        error("CreateStandardModulePage requires " .. name .. " function", 3)
    end
    return value
end

function MODERN.standardModulePage.ResolveLayout(layout, context)
    local resolved = type(layout) == "function" and layout(context) or layout
    if type(resolved) ~= "table" then
        error("StandardModulePage layout must resolve to a table", 3)
    end
    if resolved.version ~= 1 or type(resolved.sections) ~= "table" or resolved.cards ~= nil then
        error("StandardModulePage accepts only version=1 sections declarations; special cards use their owning page", 3)
    end
    return resolved
end

--- Creates the common page lifecycle for a display module.
--- The returned controller is intentionally the only object a Page may call:
--- `controller:Render(contentFrame)` and `controller:Hide()`.
--- @param options table
---   moduleKey string (required)
---   page table (required; state holder only, no Page methods are replaced)
---   layout table|function(context) -> table (required)
---   binding StandardConfigBinding (optional only when already registered)
---   preview { render=function, release=function, refresh=function?, height=number? }
---   previewDock { dockPolicy="internal-top"|"external-left", ... }
---     external-left requires anchorResolver(contentFrame, context) -> Frame,
---     width=number, offsetX=number and offsetY=number.  EXUI owns the Dock;
---     modules cannot create/re-anchor a private external PreviewDock.
---   getColumns function|number (optional, defaults to 200 logical columns)
---   sliderContract table|function(context)->table (required; Core owns StandardSliderNotify)
---   afterGridLayout function(context) (optional; layout-only, never binders/preview handlers)
function EXUI:CreateStandardModulePage(options)
    if type(options) ~= "table" then error("CreateStandardModulePage requires options table", 2) end
    local moduleKey = self:RequireModuleKey(options.moduleKey, "CreateStandardModulePage")
    local page = options.page
    if type(page) ~= "table" then error("CreateStandardModulePage requires page table", 2) end
    if page._standardModulePage then
        error("StandardModulePage already exists for page: " .. moduleKey, 2)
    end
    if type(options.layout) ~= "table" and type(options.layout) ~= "function" then
        error("CreateStandardModulePage requires layout table/function", 2)
    end

    local binding = options.binding
    if not binding and type(self.GetStandardConfigBinding) == "function" then
        binding = self:GetStandardConfigBinding(moduleKey)
    end
    if type(binding) ~= "table" or binding.moduleKey ~= moduleKey then
        error("CreateStandardModulePage requires registered binding for " .. moduleKey, 2)
    end
    MODERN.standardModulePage.RequireFunction(binding.getConfig, "binding.getConfig")

    local preview = options.preview
    if type(preview) ~= "table" then error("CreateStandardModulePage requires preview surface", 2) end
    local previewRender = MODERN.standardModulePage.RequireFunction(preview.render or preview.Render, "preview.render")
    local previewRelease = MODERN.standardModulePage.RequireFunction(preview.release or preview.Release, "preview.release")

    local previewDockOptions = options.previewDock or {}
    if type(previewDockOptions) ~= "table" then
        error("CreateStandardModulePage previewDock must be table", 2)
    end
    local dockPolicy = previewDockOptions.dockPolicy or "internal-top"
    if dockPolicy ~= "internal-top" and dockPolicy ~= "external-left" then
        error("CreateStandardModulePage previewDock.dockPolicy must be internal-top or external-left", 2)
    end
    local externalDockResolver, externalDockWidth, externalDockOffsetX, externalDockOffsetY
    if dockPolicy == "external-left" then
        externalDockResolver = previewDockOptions.anchorResolver
        externalDockWidth = tonumber(previewDockOptions.width)
        externalDockOffsetX = previewDockOptions.offsetX
        externalDockOffsetY = previewDockOptions.offsetY
        if type(externalDockResolver) ~= "function" then
            error("external-left PreviewDock requires anchorResolver", 2)
        end
        if not externalDockWidth or externalDockWidth <= 0 then
            error("external-left PreviewDock requires fixed positive width", 2)
        end
        if type(externalDockOffsetX) ~= "number" or type(externalDockOffsetY) ~= "number" then
            error("external-left PreviewDock requires fixed numeric offsetX/offsetY", 2)
        end
    end

    local getColumns = options.getColumns or 200
    if type(getColumns) ~= "number" and type(getColumns) ~= "function" then
        error("CreateStandardModulePage getColumns must be number/function", 2)
    end
    local sliderContract = options.sliderContract
    if type(sliderContract) ~= "table" and type(sliderContract) ~= "function" then
        error("CreateStandardModulePage requires sliderContract table/function", 2)
    end
    local afterGridLayout = options.afterGridLayout
    if afterGridLayout ~= nil and type(afterGridLayout) ~= "function" then
        error("CreateStandardModulePage afterGridLayout must be function", 2)
    end
    local applyScrollSkin = options.applyScrollSkin
    if applyScrollSkin ~= nil and type(applyScrollSkin) ~= "function" then
        error("CreateStandardModulePage applyScrollSkin must be function", 2)
    end

    local controller = {
        moduleKey = moduleKey,
        page = page,
        binding = binding,
        layout = options.layout,
        preview = preview,
        previewRender = previewRender,
        previewRelease = previewRelease,
        dockHeight = math.max(dockPolicy == "internal-top"
            and EXUI:GetStandardPreviewMinimumCanvasHeight() or 1,
            tonumber(preview.height) or 160),
        dockPolicy = dockPolicy,
        externalDockResolver = externalDockResolver,
        externalDockWidth = externalDockWidth,
        externalDockOffsetX = externalDockOffsetX,
        externalDockOffsetY = externalDockOffsetY,
        getColumns = getColumns,
        sliderContract = sliderContract,
        afterGridLayout = afterGridLayout,
        applyScrollSkin = applyScrollSkin,
        renderGeneration = 0,
        gridRendered = false,
        cardSession = nil,
        previewMounted = false,
    }
    -- Startup audit validates that every module registered a Page and a Slider
    -- declaration.  The resolver is intentionally kept until first Render,
    -- where the actual Grid controls are validated by the lifecycle binder.
    binding.contract.page = true
    binding.contract.slider = sliderContract

    local function BuildContext(self)
        return {
            moduleKey = self.moduleKey,
            page = self.page,
            controller = self,
            dock = self.previewDock,
            scrollFrame = self.scrollFrame,
            scrollChild = self.scrollChild,
            grid = _G.ExwindGrid,
            config = self.binding.getConfig(),
            cardSession = self.cardSession,
        }
    end

    function controller:SetDockHeight(height)
        height = tonumber(height)
        if not height or height <= 0 then error("StandardModulePage dock height must be positive", 2) end
        if self.dockPolicy == "internal-top" then
            height = math.max(height, EXUI:GetStandardPreviewMinimumCanvasHeight())
        end
        self.dockHeight = height
        if self.previewDock then self.previewDock:SetHeight(height) end
    end

    function controller:SyncInternalPreviewShellHeight()
        if self.dockPolicy ~= "internal-top" or not self.topPreview then return end
        self.topPreview:SyncHeight()
    end

    function controller:RefreshGridControls()
        local session = self.cardSession
        if session and not session.released and type(session.RefreshValues) == "function" then
            return session:RefreshValues()
        end
        local grid = _G.ExwindGrid
        if grid and self.scrollChild and type(grid.RefreshContainerControlsFromDB) == "function" then
            return grid:RefreshContainerControlsFromDB(self.scrollChild)
        end
        return false
    end

    function controller:ClearActiveOwnership()
        if EXUI.ActivePageScrollFrame == self.scrollFrame then
            EXUI.ActivePageScrollFrame = nil
        end
        if EXUI.ActivePageFrame == self.scrollChild then
            EXUI.ActivePageFrame = nil
            EXUI.CurrentModule = nil
        end
    end

    function controller:ReleasePreview()
        if not self.previewMounted then return end
        self.previewMounted = false
        self.previewRelease(self.previewDock, BuildContext(self))
    end

    function controller:ReleaseGrid()
        local grid = _G.ExwindGrid
        local session = self.cardSession
        self.cardSession = nil
        self.gridRendered = false
        if session then
            if type(session.Release) ~= "function" then
                error("StandardModulePage card session does not implement Release", 2)
            end
            session:Release()
        elseif grid and self.scrollChild and type(grid.ReleaseContainerWidgets) == "function" then
            grid:ReleaseContainerWidgets(self.scrollChild)
        end
    end

    -- A delayed stage failure must leave no live half-page behind.  Cleanup is
    -- deliberately best-effort: its own failure must never replace the actual
    -- Grid/Slider/Audit/Preview exception reported to the developer.
    function controller:AbortFailedRender(generation)
        if self.renderGeneration == generation then
            self.renderGeneration = self.renderGeneration + 1
        end
        pcall(function()
            if self.previewDock then
                -- preview.render can fail after acquiring a session but before
                -- previewMounted becomes true; release unconditionally here.
                self.previewRelease(self.previewDock, BuildContext(self))
            end
        end)
        self.previewMounted = false
        pcall(function() self:ReleaseGrid() end)
        pcall(function() self:ClearActiveOwnership() end)
        pcall(function()
            EXUI:SetPreviewDockScrollOwner(self.previewDock, self, nil)
        end)
        pcall(function()
            if self.previewRow then self.previewRow:Hide() end
            if self.previewShell and self.previewShell ~= self.previewDock then self.previewShell:Hide() end
            if self.previewDock then self.previewDock:Hide() end
        end)
    end

    function controller:RaiseStageFailure(generation, stage, original, isDiagnostic)
        local diagnostic = isDiagnostic and original
            or MODERN.standardModulePage.BuildStageError(self.moduleKey, stage, original)
        self.lastFailedStage = stage
        self.lastFailedError = diagnostic
        self:AbortFailedRender(generation)

        -- Report through WoW's formal error path before rethrowing.  pcall only
        -- protects the error reporter itself; the original stage error is never
        -- swallowed and execution cannot continue with a partial page.
        local handler
        if type(_G.geterrorhandler) == "function" then
            local ok, value = pcall(_G.geterrorhandler)
            if ok and type(value) == "function" then handler = value end
        end
        if handler then pcall(handler, diagnostic) end
        error(diagnostic, 0)
    end

    function controller:RunDelayedStage(generation, stage, callback)
        local ok, result = xpcall(callback, function(original)
            return MODERN.standardModulePage.BuildStageError(self.moduleKey, stage, original)
        end)
        if not ok then
            -- The xpcall error is already structured and includes the original
            -- message/stack.  Keep it intact when sending it to the game handler.
            self:RaiseStageFailure(generation, stage, result, true)
        end
        return result
    end

    function controller:Teardown()
        -- generation 是 C_Timer.After 的取消令牌；不保留页面离开后的延迟 Render。
        self.renderGeneration = self.renderGeneration + 1
        self:ReleasePreview()
        self:ReleaseGrid()
        self:ClearActiveOwnership()
        EXUI:SetPreviewDockScrollOwner(self.previewDock, self, nil)
        if self.previewRow then self.previewRow:Hide() end
        if self.previewShell and self.previewShell ~= self.previewDock then self.previewShell:Hide() end
        if self.previewDock then self.previewDock:Hide() end
    end

    function controller:SyncScrollChildWidth(allowFallback)
        local contentFrame, scrollFrame, scrollChild = self.contentFrame, self.scrollFrame, self.scrollChild
        if not contentFrame or not scrollFrame or not scrollChild then return false end
        if allowFallback ~= true and not scrollFrame:IsShown() then return false end
        local width = tonumber(contentFrame:GetWidth()) or 0
        if width < 100 then
            if allowFallback ~= true then return false end
            width = 820
        end
        local childWidth = math.max(1, width - 16)
        if math.abs((tonumber(scrollChild:GetWidth()) or 0) - childWidth) < 0.5 then return false end
        scrollChild:SetWidth(childWidth)
        return true
    end

    function controller:EnsureFrames(contentFrame)
        if not contentFrame or type(contentFrame.SetPoint) ~= "function" then
            error("StandardModulePage Render requires contentFrame", 2)
        end
        self.contentFrame = contentFrame
        if self.scrollFrame then return end

        local scrollFrame = EXUI:CreateScrollFrame(contentFrame)
        if self.applyScrollSkin then self.applyScrollSkin(scrollFrame) end
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        local previewRow, previewShell, dock, previewToolbar
        if self.dockPolicy == "internal-top" then
            self.topPreview = EXUI:CreateStandardTopPreview(contentFrame)
            previewRow = self.topPreview.row
            previewShell = self.topPreview.shell
            dock = self.topPreview.canvas
            previewToolbar = self.topPreview.toolbar
            dock:SetHeight(self.dockHeight)
        else
            dock = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
            previewShell = dock
            EXUI:ApplyStandardPreviewShellStyle(dock)
            dock:SetHeight(self.dockHeight)
        end

        self.scrollFrame = scrollFrame
        self.scrollChild = scrollChild
        self.previewRow = previewRow
        self.previewShell = previewShell
        self.previewToolbar = previewToolbar
        self.previewDock = dock
        self:SyncInternalPreviewShellHeight()
        -- 页面只保存标准宿主引用，不能保留 module private preview/session。
        self.page._scrollFrame = scrollFrame
        self.page._scrollChild = scrollChild
        self.page._previewDock = dock
        self.page._previewShell = previewShell

        if self.dockPolicy == "internal-top" then
            dock:HookScript("OnSizeChanged", function()
                self:SyncInternalPreviewShellHeight()
            end)
            contentFrame:HookScript("OnSizeChanged", function()
                if self.contentFrame ~= contentFrame then return end
                self:SyncScrollChildWidth(true)
                self:PlacePreviewDock(contentFrame)
            end)
        end

        scrollFrame:HookScript("OnHide", function()
            self:Teardown()
        end)
        scrollFrame:HookScript("OnShow", function()
            if self._suppressOnShow or self.gridRendered or not self.contentFrame then return end
            self:Render(self.contentFrame)
        end)
        scrollFrame:HookScript("OnSizeChanged", function()
            self:SyncScrollChildWidth(false)
        end)
    end

    function controller:PlacePreviewDock(contentFrame)
        local dock = self.previewDock
        if self.dockPolicy == "external-left" then
            local context = BuildContext(self)
            local anchor = self.externalDockResolver(contentFrame, context)
            if not anchor or type(anchor.SetPoint) ~= "function" then
                error("external-left PreviewDock anchorResolver must return Frame", 2)
            end
            -- The external dock is a Core-owned sibling of the main panel.  It
            -- never becomes a child of a module Page and preserves the target
            -- panel's strata/level across page switches and pool reuse.
            dock:SetParent(UIParent)
            if type(anchor.GetFrameStrata) == "function" then dock:SetFrameStrata(anchor:GetFrameStrata()) end
            if type(anchor.GetFrameLevel) == "function" then dock:SetFrameLevel((anchor:GetFrameLevel() or 1) + 10) end
            dock:ClearAllPoints()
            dock:SetPoint("TOPRIGHT", anchor, "TOPLEFT", self.externalDockOffsetX, self.externalDockOffsetY)
            dock:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", self.externalDockOffsetX, self.externalDockOffsetY)
            dock:SetWidth(self.externalDockWidth)
            return
        end
        if not self.topPreview then error("internal-top PreviewDock requires a standard top preview", 2) end
        self:SyncScrollChildWidth(true)
        self.topPreview:Place(contentFrame, self.scrollChild:GetWidth(), -4)
    end

    function controller:Render(contentFrame)
        self:EnsureFrames(contentFrame)
        -- 同一页被路由重复 Render 时不会触发 OnHide；必须先交还上一轮
        -- Grid/preview，才能重新绑定本轮唯一 container/session。
        if self.gridRendered or self.cardSession or self.previewMounted then
            self:ReleasePreview()
            self:ReleaseGrid()
        end
        self.renderGeneration = self.renderGeneration + 1
        local generation = self.renderGeneration
        local scrollFrame, scrollChild, dock = self.scrollFrame, self.scrollChild, self.previewDock

        -- 外壳沿公共设置卡宽度规则居中；画布背景是页面预览态，不写模块配置。
        self:PlacePreviewDock(contentFrame)
        EXUI:ApplyStandardPreviewShellStyle(self.previewShell or dock)
        EXUI:SetPreviewDockScrollOwner(dock, self, scrollFrame)
        if self.previewRow then self.previewRow:Show() end
        if self.previewShell then self.previewShell:Show() end
        dock:Show()

        scrollFrame:SetParent(contentFrame)
        scrollFrame:ClearAllPoints()
        if self.dockPolicy == "external-left" then
            scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        else
            scrollFrame:SetPoint("TOPLEFT", self.previewRow, "BOTTOMLEFT", 0, -6)
        end
        scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
        scrollFrame:SetVerticalScroll(0)
        self._suppressOnShow = true
        scrollFrame:Show()
        self._suppressOnShow = false

        C_Timer.After(0, function()
            if self.renderGeneration ~= generation
                or not scrollFrame:IsShown()
                or scrollFrame:GetParent() ~= contentFrame then
                return
            end
            local grid = _G.ExwindGrid
            local config, context, columns, slider

            self:RunDelayedStage(generation, MODERN.standardModulePage.stages.grid, function()
                if not grid then error("StandardModulePage requires ExwindGrid", 2) end
                config = self.binding.getConfig()
                if type(config) ~= "table" then error("StandardModulePage binding getConfig returned non-table", 2) end
                self:SyncScrollChildWidth(true)
                scrollChild:SetParent(scrollFrame)
                scrollChild:ClearAllPoints()
                scrollChild:SetPoint("TOPLEFT", 0, 0)
                scrollChild:Show()

                EXUI.ActivePageFrame = scrollChild
                EXUI.ActivePageScrollFrame = scrollFrame
                EXUI.CurrentModule = self.moduleKey
                context = BuildContext(self)
                context.config = config
                local layout = type(self.layout) == "function" and self.layout(context) or self.layout
                if self.moduleKey:match("^EXAura%.") and type(layout) == "table"
                    and layout.version == nil and layout.cards == nil and layout.sections == nil then
                    -- Original EXAura pages retain their authored Grid coordinates.
                    -- Restore the existing Grid route from 6987675; do not reshape their layout.
                    columns = type(self.getColumns) == "function" and self.getColumns(context) or self.getColumns
                    columns = tonumber(columns)
                    if not columns or columns <= 0 then error("StandardModulePage resolved invalid Grid column count", 2) end
                    grid:SetContainerCols(scrollChild, columns)
                    grid:Render(scrollChild, layout, config, self.moduleKey)
                else
                    local declaration = MODERN.standardModulePage.ResolveLayout(layout, context)
                    if type(grid.MountSettingsDeclaration) ~= "function" then
                        error("StandardModulePage requires ExwindGrid:MountSettingsDeclaration", 2)
                    end
                    self.cardSession = grid:MountSettingsDeclaration(scrollChild, declaration, {
                        pageId = self.moduleKey,
                        regionId = "standard-module",
                        binding = self.binding,
                        config = config,
                        moduleKey = self.moduleKey,
                        scrollFrame = scrollFrame,
                    })
                end
                self.gridRendered = true
                context = BuildContext(self)
                context.config = config
                context.columns = columns
            end)

            self.binding.contract.page = true

            -- Surface 是允许懒创建的正式声明：首次 preview mount 才会把同一个
            -- surface 写入 binding.contract.surface。故必须先 mount 当前模块，
            -- 再审计当前模块；不能为通过 audit 在模块加载期虚构 session。
            self:RunDelayedStage(generation, MODERN.standardModulePage.stages.preview, function()
                if self.afterGridLayout then self.afterGridLayout(context) end
                self.previewRender(dock, context)
                self.previewMounted = true
            end)

            self:RunDelayedStage(generation, MODERN.standardModulePage.stages.audit, function()
                if type(EXUI.AssertRegisteredDisplayModules) == "function" then
                    EXUI:AssertRegisteredDisplayModules({ self.moduleKey }, {
                        requireSurface = true,
                        requirePage = true,
                        requireSlider = true,
                    })
                end
            end)
        end)
    end

    function controller:Hide()
        self:Teardown()
        if self.scrollFrame and self.scrollFrame:IsShown() then self.scrollFrame:Hide() end
    end

    page._standardModulePage = controller
    return controller
end

-- 仅供同一 GUI 实现的后续文件使用；保存原函数/常量，不承载配置或页面状态。
EXUI._GUIInternal = {
    ReadNumberInputDraft = ReadNumberInputDraft,
    StyleModernTitle = StyleModernTitle,
    SetDropdownDisplayText = SetDropdownDisplayText,
    AcquireCompositeGroup = AcquireCompositeGroup,
    AttachModernMenuSelectionMark = AttachModernMenuSelectionMark,
    MODERN_MEDIA = MODERN_MEDIA,
    PaintModernCheckbox = PaintModernCheckbox,
    PaintModernButton = PaintModernButton,
    SLIDER_NUMBER_INPUT_WIDTH = SLIDER_NUMBER_INPUT_WIDTH,
    SLIDER_NUMBER_INPUT_HEIGHT = SLIDER_NUMBER_INPUT_HEIGHT,
    PaintModernInput = PaintModernInput,
    PaintModernDropdown = PaintModernDropdown,
    BUTTON_STYLE = BUTTON_STYLE,
}
